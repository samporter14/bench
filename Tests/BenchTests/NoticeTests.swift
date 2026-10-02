// NoticeTests.swift — when each notice is due, and holding finishes during a
// Nidus focus session. Made-up limits, histories and focus states only.
import Foundation
import Testing
@testable import Bench

struct PlanNoticeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func limit(_ kind: PlanLimit.Kind, used: Int, resetsIn minutes: Double) -> PlanLimit {
        PlanLimit(kind: kind, usedPercent: used, resetsAt: now.addingTimeInterval(minutes * 60))
    }

    @Test func nearTheLimitOncePerWindow() {
        let first = NoticeRules.plan(limits: [limit(.session, used: 92, resetsIn: 47)], announced: [:], now: now)
        #expect(first.notices.count == 1)
        #expect(first.notices.first?.title == "8% of your 5-hour limit left")
        // The next read, its reset time a few seconds off: the same window.
        let wobble = PlanLimit(kind: .session, usedPercent: 95, resetsAt: now.addingTimeInterval(47 * 60 + 8))
        #expect(NoticeRules.plan(limits: [wobble], announced: first.announced, now: now).notices.isEmpty)
    }

    @Test func belowTheThresholdAndOtherLimitsStayQuiet() {
        let limits = [limit(.session, used: 70, resetsIn: 30), limit(.weekOpus, used: 99, resetsIn: 600)]
        #expect(NoticeRules.plan(limits: limits, announced: [:], now: now).notices.isEmpty)
    }

    @Test func aResetSeenHappeningGetsACardAStaleOneDoesNot() throws {
        let ended = PlanLimit(kind: .session, usedPercent: 95, resetsAt: now.addingTimeInterval(-2 * 60))
        let key = try #require(NoticeRules.windowKey(ended))
        let fresh = NoticeRules.plan(limits: [limit(.session, used: 3, resetsIn: 298)],
                                     announced: [key: ended.resetsAt!], now: now)
        #expect(fresh.notices.map(\.title) == ["Your 5-hour limit has reset"])
        #expect(fresh.announced.isEmpty)
        let lateNow = now.addingTimeInterval(3 * 3600)
        let stale = NoticeRules.plan(limits: [PlanLimit(kind: .session, usedPercent: 3, resetsAt: lateNow.addingTimeInterval(3600))],
                                     announced: [key: ended.resetsAt!], now: lateNow)
        #expect(stale.notices.isEmpty)
    }
}

struct ContextNoticeTests {
    @Test func onceASessionPassesTheThreshold() {
        #expect(NoticeRules.context(frameID: "f", percent: 84, title: nil, announced: []) == nil)
        #expect(NoticeRules.context(frameID: "f", percent: 88, title: "Example", announced: [])?.title == "Example")
        #expect(NoticeRules.context(frameID: "f", percent: 95, title: nil, announced: ["f"]) == nil)
    }
}

struct WeekReviewTests {
    @Test func lastWeeksTotalsAndBusiestDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7))) // a Wednesday
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        func day(_ offset: Int) -> String { DailyCounts.key(for: calendar.date(byAdding: .day, value: offset, to: monday)!, calendar: calendar) }
        let sessions = DailyCounts(counts: [day(0): 2, day(2): 5, day(4): 1, day(9): 7])
        let messages = DailyCounts(counts: [day(0): 20, day(2): 50, day(4): 10])
        let week = try #require(NoticeRules.lastWeek(ActivityHistory(sessions: sessions, messages: messages, tokens: nil),
                                                     today: today, calendar: calendar))
        #expect(week.sessions == 8) // day(9) is this week
        #expect(week.messages == 80)
        #expect(week.busiestDay == "Wednesday")
        #expect(NoticeRules.weekNotice(week).title == "8 sessions last week")
    }

    @Test func aWeekWithNoSessionsHasNoCard() throws {
        let history = ActivityHistory(sessions: DailyCounts(counts: [:]), messages: nil, tokens: nil)
        #expect(NoticeRules.lastWeek(history, today: Date()) == nil)
    }
}

struct FocusTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func focusingOnlyWhileTheFileNidusAndTheClockAgree() {
        let soon = NoticeRules.FocusFile(version: 1, focusing: true, until: now.timeIntervalSince1970 + 600)
        #expect(NoticeRules.isFocusing(soon, nidusRunning: true, now: now))
        #expect(!NoticeRules.isFocusing(soon, nidusRunning: false, now: now)) // left behind by a crash
        #expect(!NoticeRules.isFocusing(soon, nidusRunning: true, now: now.addingTimeInterval(601)))
        let openEnded = NoticeRules.FocusFile(version: 1, focusing: true, until: nil)
        #expect(NoticeRules.isFocusing(openEnded, nidusRunning: true, now: now))
        #expect(!NoticeRules.isFocusing(nil, nidusRunning: true, now: now))
    }
}

@MainActor
struct HoldTests {
    @Test func finishesWaitForTheFocusSessionThenComeAsOne() {
        let model = LabModel()
        var focusing = true
        model.holdsFinishes = { focusing }
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished), Fixture.session("b", .needsInput, reason: .question)))
        // The question comes at once; the finish waits, and is in Recent.
        #expect(model.cards.map(\.id) == ["needs-b"])
        #expect(model.heldFinishes.map(\.id) == ["a"])
        #expect(model.recent.contains { $0.session?.id == "a" })
        // Claude Science's own notification for that finish doesn't get past.
        model.receive(WebNotification(id: "n", title: "Done", body: "", tag: "operon-a",
                                      requireInteraction: false, receivedAt: Date()))
        #expect(model.cards.map(\.id) == ["needs-b"])
        focusing = false
        model.releaseHeldFinishes()
        #expect(model.cards.map(\.id).last?.hasPrefix("notice-focus-held") == true)
        #expect(model.heldFinishes.isEmpty)
    }
}
