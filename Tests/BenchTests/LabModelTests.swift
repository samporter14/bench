// LabModelTests.swift — the card queue and Recent, fed made-up snapshots. The
// model under test is a fresh one, never `shared`, and is never started, so
// nothing reads a database or plays a sound.
import Foundation
import Testing
@testable import Bench

@MainActor
struct LabModelTests {
    private func model() -> LabModel {
        let model = LabModel()
        model.lifetimeScale = 0.01 // a 6 s card lasts 60 ms
        return model
    }

    /// Waits for `condition`, up to a few seconds, rather than for a fixed
    /// time: a busy test run can make a 60 ms card take longer than 200 ms.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aFinishQueuedBehindAQuestionWaitsItsTurn() async throws {
        let model = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .finished)))
        #expect(model.cards.map(\.id) == ["needs-a", "finished-b"])
        try await Task.sleep(for: .milliseconds(200))
        // Behind the question, the finish has not used up its time.
        #expect(model.cards.map(\.id) == ["needs-a", "finished-b"])
        model.dismiss(model.cards[0])
        #expect(model.cards.map(\.id) == ["finished-b"])
        try await until { model.cards.isEmpty }
        #expect(model.cards.isEmpty)
    }

    @Test func aWaitingCardSaysWhatItWaitsForNow() {
        let model = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(model.cards.count == 1)
        #expect(model.cards.first?.session?.waitingReason == .plan)
    }

    @Test func aDismissedRequestComesBackWhenANewKindArrives() {
        let model = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        model.dismiss(model.cards[0])
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.cards.isEmpty)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func aFailureCardStaysUntilTheSessionRunsAgain() {
        let model = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .error)))
        #expect(model.cards.map(\.id) == ["failed-a"])
        #expect(model.working.isEmpty)
        model.ingest(Fixture.snapshot(Fixture.session("a", .error)))
        #expect(model.cards.map(\.id) == ["failed-a"])
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(model.cards.isEmpty)
    }

    @Test func aFailedReadKeepsTheSessionsButSaysItIsStale() {
        let model = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.failedRead)
        #expect(model.working.map(\.id) == ["a"])
        #expect(model.problem != nil)
        #expect(model.staleSince != nil)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(model.problem == nil)
        #expect(model.staleSince == nil)
    }

    @Test func aNotificationThePageClosesTakesItsCard() {
        let model = model()
        model.receive(WebNotification(id: "n1", title: "Done", body: "", tag: nil,
                                      requireInteraction: true, receivedAt: Date()))
        #expect(model.cards.map(\.id) == ["web-n1"])
        model.closeWebNotification("n1")
        #expect(model.cards.isEmpty)
    }

    @Test func recentKeepsEachEventOnceAndOutlivesItsCard() async throws {
        let model = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .finished)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .finished)))
        #expect(model.recent.count == 2)
        model.dismiss(model.cards[0])
        try await until { model.cards.isEmpty }
        #expect(model.cards.isEmpty)
        #expect(model.recent.count == 2)
    }
}

@MainActor
struct DaemonRestartTests {
    @Test func aWaitingCardOutlivesTheDaemonGoingAway() {
        let model = LabModel()
        var raised: [String] = []
        model.cardRaised = { raised.append($0.id) }
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(raised == ["needs-a"])
        // The daemon stops: nothing works, but the session still waits for you.
        model.ingest(Fixture.daemonDown)
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.working.isEmpty)
        #expect(model.waiting.map(\.id) == ["a"])
        // It comes back with the same question: the card is there, and isn't news again.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(raised == ["needs-a"])
        // And it goes once the session stops waiting, as ever.
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(model.cards.isEmpty)
    }

    @Test func startingWhileTheDaemonIsDownIsNoBurst() {
        let model = LabModel()
        var raised: [String] = []
        model.cardRaised = { raised.append($0.id) }
        model.ingest(Fixture.daemonDown)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .needsInput, reason: .plan)))
        // The first read that works shows what waits, without a notification each.
        #expect(Set(model.cards.map(\.id)) == ["needs-a", "needs-b"])
        #expect(raised.isEmpty)
        // After that, a new one is news.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .needsInput, reason: .plan),
                                      Fixture.session("c", .needsInput, reason: .question)))
        #expect(raised == ["needs-c"])
    }
}

@MainActor
struct LatestTests {
    @Test func latestListsTheNewestSessionsThatNeitherWorkNorWait() {
        let model = LabModel()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .finished),
                                      Fixture.session("c", .needsInput, reason: .question), Fixture.session("d", .error)))
        #expect(Set(model.latest.map(\.id)) == ["b", "d"])
    }

    @Test func theDockMenuIsNeverEmpty() {
        let model = LabModel()
        #expect(model.latest.isEmpty && model.recent.isEmpty && model.working.isEmpty)
        // ActivityMenu reads `shared`; an idle shared model still gets a menu
        // with the idle line.
        #expect(!ActivityMenu.shared.make().items.isEmpty)
    }
}

/// The fallback read: quick only while something works and nothing reports
/// the daemon's writes; with the watcher up, a slow safety net.
struct FallbackTimerTests {
    @Test func theTimerIsQuickOnlyWhileSomethingWorksWithoutTheWatcher() {
        #expect(LabModel.fallbackInterval(busy: true, watching: false) == .seconds(3))
        #expect(LabModel.fallbackInterval(busy: false, watching: false) == .seconds(30))
        #expect(LabModel.fallbackInterval(busy: true, watching: true) == .seconds(30))
        #expect(LabModel.fallbackInterval(busy: false, watching: true) == .seconds(30))
    }
}
