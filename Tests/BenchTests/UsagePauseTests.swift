// UsagePauseTests.swift — running sessions held by a used-up plan limit: when
// Bench reads it as a pause, what it says, and what the phone is told.
import Foundation
import Testing
@testable import Bench

struct UsagePauseTests {
    private let now = Date(timeIntervalSince1970: 1_791_900_000)
    private var inAnHour: Date { now.addingTimeInterval(3_600) }

    private func limit(_ kind: PlanLimit.Kind, used: Int, reached: Bool, resets: Date?) -> PlanLimit {
        PlanLimit(kind: kind, usedPercent: used, resetsAt: resets, reached: reached)
    }

    @Test func aUsedUpLimitWithQuietSessionsIsAPause() {
        let reached = limit(.session, used: 100, reached: true, resets: inAnHour)
        let pause = UsagePause.decide(running: true, lastWrite: now.addingTimeInterval(-25), now: now, reached: reached)
        #expect(pause == UsagePause(limit: .session, until: inAnHour))
    }

    @Test func aSessionStillWritingIsNotPaused() {
        let reached = limit(.session, used: 100, reached: true, resets: inAnHour)
        #expect(UsagePause.decide(running: true, lastWrite: now.addingTimeInterval(-5), now: now, reached: reached) == nil)
    }

    @Test func nothingRunningOrNoLimitUsedUpIsNoPause() {
        let reached = limit(.session, used: 100, reached: true, resets: inAnHour)
        #expect(UsagePause.decide(running: false, lastWrite: now.addingTimeInterval(-60), now: now, reached: reached) == nil)
        #expect(UsagePause.decide(running: true, lastWrite: now.addingTimeInterval(-60), now: now, reached: nil) == nil)
    }

    @Test func aLimitIsUsedUpOnlyWhenAllOfItIsGoneAndItHasNotStartedOver() {
        // Rounded to 100 but still running (99.6 %) doesn't count.
        let almost = limit(.session, used: 100, reached: false, resets: inAnHour)
        #expect(PlanUsageModel.limitReached([almost], extra: nil, now: now) == nil)
        // Started over already: Claude Science sends again.
        let past = limit(.session, used: 100, reached: true, resets: now.addingTimeInterval(-1))
        #expect(PlanUsageModel.limitReached([past], extra: nil, now: now) == nil)
        let used = limit(.session, used: 100, reached: true, resets: inAnHour)
        #expect(PlanUsageModel.limitReached([used], extra: nil, now: now)?.kind == .session)
    }

    @Test func extraUsageCarriesOnPastALimitUntilItIsUsedUpToo() {
        let used = limit(.session, used: 100, reached: true, resets: inAnHour)
        #expect(PlanUsageModel.limitReached([used], extra: PlanExtraUsage(usedPercent: 40), now: now) == nil)
        #expect(PlanUsageModel.limitReached([used], extra: PlanExtraUsage(usedPercent: nil), now: now) == nil)
        #expect(PlanUsageModel.limitReached([used], extra: PlanExtraUsage(usedPercent: 100), now: now)?.kind == .session)
    }

    @Test func withTwoUsedUpThePauseLastsUntilTheLaterReset() {
        let session = limit(.session, used: 100, reached: true, resets: inAnHour)
        let week = limit(.week, used: 100, reached: true, resets: now.addingTimeInterval(86_400 * 2))
        #expect(PlanUsageModel.limitReached([session, week], extra: nil, now: now)?.kind == .week)
    }

    @Test func itSaysWhenItResumes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let later = calendar.date(byAdding: .hour, value: 3, to: noon)!
        let tomorrow = calendar.date(byAdding: .hour, value: 20, to: noon)!
        #expect(UsagePause(limit: .session, until: later).sentence(now: noon, calendar: calendar).hasPrefix("Resumes at "))
        #expect(UsagePause(limit: .session, until: tomorrow).sentence(now: noon, calendar: calendar).hasPrefix("Resumes tomorrow at "))
        #expect(UsagePause(limit: .session, until: nil).sentence(now: noon) == "Resumes when your limit resets")
    }

    @MainActor @Test func thePhoneIsToldOnlyWhileSomethingRuns() throws {
        let working = SessionStatus(id: "00000000-0000-4000-8000-0000000000aa", projectID: "p", projectName: "Made-up project",
                                    title: "Made-up session", state: .running, updatedAt: now, startedAt: now)
        let pause = UsagePause(limit: .session, until: inAnHour)
        func state(working: [SessionStatus]) -> RemoteAPI.State {
            RemoteAPI.state(RemoteAPI.Input(bench: "0.5.2", now: now, problem: nil, waiting: [], snoozed: [], failed: [],
                                            working: working, recent: [], limits: [], forecasts: [:], pause: pause))
        }
        let on = state(working: [working])
        #expect(on.pause?.limit == "5-hour")
        #expect(on.pause?.until == inAnHour)
        let json = try #require(String(data: RemoteAPI.encode(on), encoding: .utf8))
        #expect(json.contains(#""pause":{"#))
        #expect(state(working: []).pause == nil)
        let off = try #require(String(data: RemoteAPI.encode(state(working: [])), encoding: .utf8))
        #expect(off.contains(#""pause":null"#))
    }
}
