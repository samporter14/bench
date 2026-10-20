// NeedsYouTests.swift — what the activity list's Needs you holds and in what
// order, the Later group, the Dock menu's order, and the popover's size: on
// made-up sessions, with no model started and nothing read.
import AppKit
import Foundation
import Testing
@testable import Bench

private let epoch = Date(timeIntervalSince1970: 1_792_000_000)

/// A session that last wrote `minutesAgo` before the epoch (so, began to wait then).
private func waiting(_ id: String, minutesAgo: Double, reason: WaitingReason = .question,
                     title: String? = nil) -> SessionStatus {
    SessionStatus(id: id, projectID: "p", projectName: "Example project", title: title ?? "Session \(id)",
                  state: .needsInput, updatedAt: epoch.addingTimeInterval(-minutesAgo * 60),
                  startedAt: epoch.addingTimeInterval(-(minutesAgo + 5) * 60), waitingReason: reason)
}

private func failed(_ id: String) -> SessionStatus {
    SessionStatus(id: id, projectID: "p", projectName: "Example project", title: "Failed \(id)", state: .error,
                  updatedAt: epoch, startedAt: epoch.addingTimeInterval(-300))
}

struct NeedsYouOrderTests {
    @Test func theSessionThatHasWaitedLongestIsFirstWhateverOrderTheyComeIn() {
        // `LabModel.waiting` is the most recently active first.
        let list = [waiting("c", minutesAgo: 2), waiting("a", minutesAgo: 30), waiting("b", minutesAgo: 9)]
        let needs = NeedsYou(waiting: list, snoozed: [], failed: [])
        #expect(needs.asks.map(\.id) == ["a", "b", "c"])
    }

    @Test func sessionsThatWroteAtTheSameMomentKeepAStableOrderById() {
        let list = [waiting("b", minutesAgo: 5), waiting("a", minutesAgo: 5), waiting("c", minutesAgo: 5)]
        #expect(NeedsYou(waiting: list, snoozed: [], failed: []).asks.map(\.id) == ["a", "b", "c"])
        #expect(NeedsYou(waiting: list.reversed(), snoozed: [], failed: []).asks.map(\.id) == ["a", "b", "c"])
    }

    @Test func aSessionPutOffWithLaterIsNotAmongTheAsks() {
        let a = waiting("a", minutesAgo: 30), b = waiting("b", minutesAgo: 10)
        let needs = NeedsYou(waiting: [b, a], snoozed: [SnoozedReminder(session: a, due: epoch.addingTimeInterval(300))],
                             failed: [])
        #expect(needs.asks.map(\.id) == ["b"])
        #expect(needs.later.map(\.id) == ["a"])
        #expect(needs.count == 2)
    }

    @Test func laterIsInTheOrderTheRemindersComeBackWithTheFocusOneLast() {
        let a = waiting("a", minutesAgo: 40), b = waiting("b", minutesAgo: 30), c = waiting("c", minutesAgo: 20)
        let d = waiting("d", minutesAgo: 10), e = waiting("e", minutesAgo: 5)
        let soon = epoch.addingTimeInterval(300), later = epoch.addingTimeInterval(900)
        let needs = NeedsYou(
            waiting: [e, d, c, b, a],
            snoozed: [SnoozedReminder(session: a, due: nil), SnoozedReminder(session: b, due: later),
                      SnoozedReminder(session: c, due: soon), SnoozedReminder(session: d, due: later),
                      SnoozedReminder(session: e, due: nil)],
            failed: [])
        // The same time: the one that waited longer first. The focus ones: the same.
        #expect(needs.later.map(\.id) == ["c", "b", "d", "a", "e"])
        #expect(needs.asks.isEmpty)
    }

    @Test func failuresAreTheirOwnGroupAndCountInNeedsYou() {
        let needs = NeedsYou(waiting: [waiting("a", minutesAgo: 3)], snoozed: [], failed: [failed("f"), failed("g")])
        #expect(needs.failed.map(\.id) == ["f", "g"])
        #expect(needs.count == 3)
        #expect(!needs.isEmpty)
        #expect(NeedsYou(waiting: [], snoozed: [], failed: []).isEmpty)
    }
}

/// Which sessions the model puts in Needs you, and when a put-off one counts.
@MainActor
struct NeedsYouModelTests {
    private func waitingModel() -> LabModel {
        let model = LabModel()
        model.lifetimeScale = 0.0001 // five minutes last 30 ms
        model.isFocusing = { true }
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .needsInput, reason: .plan)))
        return model
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aPutOffSessionCountsOnlyOnceItsReminderIsDue() async throws {
        let model = waitingModel()
        #expect(Set(NeedsYou(model: model).asks.map(\.id)) == ["a", "b"])
        model.remind(try #require(model.cards.first { $0.id == "needs-a" }), .fiveMinutes)
        #expect(NeedsYou(model: model).asks.map(\.id) == ["b"])
        #expect(NeedsYou(model: model).later.map(\.id) == ["a"])
        try await until { model.snoozed.isEmpty }
        #expect(Set(NeedsYou(model: model).asks.map(\.id)) == ["a", "b"])
        #expect(NeedsYou(model: model).later.isEmpty)
    }

    @Test func aSessionThatWaitsForTheFocusSessionCountsOnceItEnds() throws {
        let model = waitingModel()
        model.remind(try #require(model.cards.first { $0.id == "needs-a" }), .afterFocus)
        #expect(NeedsYou(model: model).asks.map(\.id) == ["b"])
        model.focusEnded()
        #expect(Set(NeedsYou(model: model).asks.map(\.id)) == ["a", "b"])
    }

    @Test func showNowAndCancelReminderBothLeaveLaterAndShowNowIsAnAsk() throws {
        let model = waitingModel()
        model.remind(try #require(model.cards.first { $0.id == "needs-a" }), .afterFocus)
        model.remind(try #require(model.cards.first { $0.id == "needs-b" }), .afterFocus)
        #expect(NeedsYou(model: model).asks.isEmpty)
        model.showNow("a")
        model.cancelReminder("b")
        #expect(NeedsYou(model: model).later.isEmpty)
        #expect(Set(NeedsYou(model: model).asks.map(\.id)) == ["a", "b"])
    }

    @Test func aFailureIsInNeedsYouButNotAmongTheAsks() {
        let model = LabModel()
        model.ingest(Fixture.snapshot(Fixture.session("f", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("f", .error)))
        let needs = NeedsYou(model: model)
        #expect(needs.failed.map(\.id) == ["f"])
        #expect(needs.asks.isEmpty)
    }
}

@MainActor
struct DockMenuOrderTests {
    @Test func theMenuListsAsksThenFailuresThenLaterThenWorking() throws {
        let model = LabModel()
        model.lifetimeScale = 1
        model.isFocusing = { true }
        model.ingest(Fixture.snapshot(Fixture.session("w", .running, title: "Works"),
                                      Fixture.session("a", .running), Fixture.session("b", .running),
                                      Fixture.session("c", .running), Fixture.session("f", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("w", .running, title: "Works"),
                                      Fixture.session("a", .needsInput, reason: .question, title: "Put off"),
                                      Fixture.session("b", .needsInput, reason: .plan, title: "Asks"),
                                      Fixture.session("c", .needsInput, reason: .question, title: "After focus"),
                                      Fixture.session("f", .error, title: "Broke")))
        model.remind(try #require(model.cards.first { $0.id == "needs-a" }), .fiveMinutes)
        model.remind(try #require(model.cards.first { $0.id == "needs-c" }), .afterFocus)
        let items = ActivityMenu.shared.make(model: model).items
        let layout = items.map { $0.isSectionHeader ? "[\($0.title)]" : $0.title }
        let working = try #require(layout.firstIndex(of: "[Working]"))
        // Real asks, then what failed; Later under its own header; Working after.
        #expect(Array(layout[0...working - 1]) == ["[Needs you]", "Asks", "Broke", "[Later]", "Put off", "After focus"])
        model.cancelReminder("a")
        model.cancelReminder("c")
        let after = ActivityMenu.shared.make(model: model).items.filter { !$0.isSectionHeader }.map(\.title)
        #expect(Set(after.prefix(4)) == ["Put off", "Asks", "After focus", "Broke"])
        #expect(!ActivityMenu.shared.make(model: model).items.contains { $0.isSectionHeader && $0.title == "Later" })
    }

    @Test func laterAloneStillGetsItsHeaderAndNoEmptyNeedsYou() throws {
        let model = LabModel()
        model.lifetimeScale = 1
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question, title: "Put off")))
        model.remind(try #require(model.cards.first), .fiveMinutes)
        let layout = ActivityMenu.shared.make(model: model).items.map { $0.isSectionHeader ? "[\($0.title)]" : $0.title }
        #expect(layout.first == "[Later]")
        #expect(!layout.contains("[Needs you]"))
        #expect(!layout.contains("Nothing working right now"))
    }
}

struct NeedsYouCapTests {
    private func needs(asks: Int, failed failures: Int = 0, later: Int = 0) -> NeedsYou {
        let asked = (0..<asks).map { waiting("a\($0)", minutesAgo: Double(100 - $0)) }
        let put = (0..<later).map { waiting("l\($0)", minutesAgo: Double(50 - $0)) }
        return NeedsYou(waiting: asked + put,
                        snoozed: put.enumerated().map { SnoozedReminder(session: $1, due: epoch.addingTimeInterval(Double($0) * 60)) },
                        failed: (0..<failures).map { failed("f\($0)") })
    }

    @Test func nothingIsCutWhenItAllFits() {
        let all = needs(asks: 3, failed: 1, later: 2)
        #expect(all.capped(to: 6).hidden == 0)
        #expect(all.capped(to: 6).rows == all)
        #expect(all.capped(to: nil).rows == all)
        #expect(all.capped(to: 5).hidden == 1)
    }

    @Test func theRowsThatShowAreTheFirstInTheOrderAsksFailuresLater() {
        let all = needs(asks: 4, failed: 1, later: 3)
        let (shown, hidden) = all.capped(to: 6)
        #expect(shown.asks.map(\.id) == ["a0", "a1", "a2", "a3"])
        #expect(shown.failed.map(\.id) == ["f0"])
        #expect(shown.later.map(\.id) == ["l0"])
        #expect(hidden == 2)
        // A tight cap takes from the end: Later goes first, then failures, then the newest ask.
        let (tight, tightHidden) = all.capped(to: 3)
        #expect(tight.asks.map(\.id) == ["a0", "a1", "a2"] && tight.failed.isEmpty && tight.later.isEmpty)
        #expect(tightHidden == 5)
    }
}

struct ActivitySizingTests {
    @Test func theListGrowsToTheBottomOfTheScreenAndNoFurther() {
        // A window whose top is 900 up on a screen from 0 to 1000 (usable).
        #expect(ActivitySizing.heightLimit(windowTop: 900, visibleBottom: 0, visibleHeight: 1000)
                == 900 - ActivitySizing.aboveList - ActivitySizing.belowList)
        // A window higher still: no taller than the screen's usable height.
        #expect(ActivitySizing.heightLimit(windowTop: 2000, visibleBottom: 0, visibleHeight: 1000)
                == 1000 - 2 * ActivitySizing.belowList)
    }

    @Test func aWindowLowOnTheScreenStillGetsAUsableList() {
        #expect(ActivitySizing.heightLimit(windowTop: 200, visibleBottom: 0, visibleHeight: 1000) == ActivitySizing.shortest)
        // A screen shorter than that: the screen decides.
        #expect(ActivitySizing.heightLimit(windowTop: 300, visibleBottom: 0, visibleHeight: 300) == ActivitySizing.shortest)
    }

    /// Whatever the height, Working's rows (to the three it keeps) fit under
    /// the Needs-you rows that show.
    @Test(arguments: [0, 1, 2, 3, 5])
    func workingAlwaysFitsBelowWhatNeedsYouShows(_ working: Int) {
        for height in stride(from: ActivitySizing.shortest, through: 1_400, by: 20) {
            let limit = ActivitySizing.needsRowLimit(height: height, workingRows: working)
            #expect(limit >= ActivitySizing.leastNeeds)
            guard limit > ActivitySizing.leastNeeds else { continue }
            let workingBlock = working == 0 ? 0
                : ActivitySizing.titleHeight + ActivitySizing.sectionGap
                    + CGFloat(min(working, ActivitySizing.workingKept)) * ActivitySizing.rowHeight
            let used = ActivitySizing.padding + 2 * ActivitySizing.titleHeight + ActivitySizing.rowHeight / 2
                + CGFloat(limit) * ActivitySizing.rowHeight + workingBlock
            #expect(used <= height, "height \(height), working \(working), limit \(limit)")
        }
    }

    @Test func aTallerListShowsMoreRowsAndASmallScreenAtLeastFour() {
        #expect(ActivitySizing.needsRowLimit(height: 900, workingRows: 2) > ActivitySizing.needsRowLimit(height: 600, workingRows: 2))
        #expect(ActivitySizing.needsRowLimit(height: 320, workingRows: 3) == ActivitySizing.leastNeeds)
        // The size the user had it at, with six waiting and two working, shows all six.
        #expect(ActivitySizing.needsRowLimit(height: 900, workingRows: 2) >= 7)
    }
}
