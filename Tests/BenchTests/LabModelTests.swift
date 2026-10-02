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
        try await Task.sleep(for: .milliseconds(200))
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
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.cards.isEmpty)
        #expect(model.recent.count == 2)
    }
}
