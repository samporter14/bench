// ReminderTests.swift — Later on a needs-input card: it comes back when its
// time comes or a focus session ends, but only while its session still waits.
// Made-up sessions only; the model under test is a fresh one, never `shared`,
// and is never started.
import Foundation
import Testing
@testable import Bench

@MainActor
struct ReminderTests {
    /// A model whose five minutes last 30 ms and fifteen last 90 ms.
    private func model(focusing: @escaping () -> Bool = { false }) -> LabModel {
        let model = LabModel()
        model.lifetimeScale = 0.0001
        model.isFocusing = focusing
        return model
    }

    /// A model with session "a" waiting on a question, its card on top.
    private func waitingModel(focusing: @escaping () -> Bool = { false }) -> LabModel {
        let model = model(focusing: focusing)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        return model
    }

    private func needsCards(_ model: LabModel) -> [String] {
        model.cards.map(\.id).filter { $0.hasPrefix("needs-") }
    }

    /// Waits for `condition`, up to a few seconds, rather than for a fixed time.
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aPutOffCardLeavesAtOnceAndReturnsAfterItsTimeIfStillWaiting() async throws {
        let model = waitingModel()
        model.remind(model.cards[0], .fiveMinutes)
        #expect(model.cards.isEmpty)
        #expect(model.remindedSessionIDs == ["a"])
        // The same request read again is not news, and does not bring it back.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.cards.isEmpty)
        try await until { !model.cards.isEmpty }
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.cards.first?.session?.waitingReason == .question)
        #expect(model.remindedSessionIDs.isEmpty)
    }

    @Test func fifteenMinutesWaitLongerThanFive() async throws {
        let model = waitingModel()
        model.lifetimeScale = 0.0005 // five minutes last 150 ms, fifteen 450 ms
        model.remind(model.cards[0], .fifteenMinutes)
        try await Task.sleep(for: .milliseconds(250)) // past the five minute mark
        #expect(model.cards.isEmpty)
        try await until { !model.cards.isEmpty }
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test(arguments: [LabReminder.fiveMinutes, .afterFocus])
    func aSessionThatStoppedWaitingIsNotRemindedOf(_ reminder: LabReminder) async throws {
        var focusing = true
        let model = waitingModel(focusing: { focusing })
        model.remind(model.cards[0], reminder)
        // It was answered elsewhere, and finished: the reminder goes quietly.
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(model.remindedSessionIDs.isEmpty)
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        try await Task.sleep(for: .milliseconds(150))
        focusing = false
        model.focusEnded()
        #expect(needsCards(model).isEmpty)
    }

    @Test func aSessionThatFailedWhileWaitingIsNotRemindedOfEither() async throws {
        let model = waitingModel()
        model.remind(model.cards[0], .fiveMinutes)
        model.ingest(Fixture.snapshot(Fixture.session("a", .error)))
        try await Task.sleep(for: .milliseconds(150))
        // The failure card is its own news; the question does not return.
        #expect(model.cards.map(\.id) == ["failed-a"])
    }

    @Test func aNewKindOfRequestShowsAtOnceAndClearsTheReminder() async throws {
        let model = waitingModel()
        model.remind(model.cards[0], .fiveMinutes)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.cards.first?.session?.waitingReason == .plan)
        #expect(model.remindedSessionIDs.isEmpty)
        // With the reminder cleared, dismissing the plan is for good: the old
        // wake-up does not bring it back.
        model.dismiss(model.cards[0])
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.cards.isEmpty)
    }

    @Test func afterFocusReturnsWhenFocusEnds() async throws {
        var focusing = true
        let model = waitingModel(focusing: { focusing })
        model.remind(model.cards[0], .afterFocus)
        #expect(model.cards.isEmpty)
        // No timer brings it back while the focus session goes on.
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.cards.isEmpty)
        #expect(model.remindedSessionIDs == ["a"])
        focusing = false
        model.focusEnded()
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.remindedSessionIDs.isEmpty)
    }

    @Test func afterFocusTakesTheFinishesHeldDuringItToo() {
        var focusing = true
        let model = waitingModel(focusing: { focusing })
        model.holdsFinishes = { focusing }
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .running)))
        model.remind(model.cards[0], .afterFocus)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .finished)))
        #expect(model.cards.isEmpty)
        focusing = false
        model.focusEnded()
        #expect(model.cards.map(\.id).first == "needs-a")
        #expect(model.cards.map(\.id).last?.hasPrefix("notice-focus-held") == true)
    }

    @Test func afterFocusWithNoFocusSessionOnIsFiveMinutes() async throws {
        let model = waitingModel(focusing: { false })
        model.remind(model.cards[0], .afterFocus)
        try await until { !model.cards.isEmpty }
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func dismissIsStillForGood() async throws {
        let model = waitingModel()
        model.dismiss(model.cards[0])
        #expect(model.remindedSessionIDs.isEmpty)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        try await Task.sleep(for: .milliseconds(150))
        model.focusEnded()
        #expect(model.cards.isEmpty)
        // Only a new kind of request brings it back.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func aLateClickOnLaterDoesNotBringADismissedCardBack() async throws {
        let model = waitingModel()
        let card = model.cards[0]
        model.dismiss(card)
        model.remind(card, .fiveMinutes)
        #expect(model.remindedSessionIDs.isEmpty)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.cards.isEmpty)
    }

    @Test func openingTheSessionClearsItsReminder() async throws {
        let model = waitingModel()
        model.remind(model.cards[0], .fiveMinutes)
        model.open(Fixture.session("a", .needsInput, reason: .question))
        #expect(model.remindedSessionIDs.isEmpty)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.cards.isEmpty)
    }

    @Test func aReminderKeepsItsPlaceWhileOtherCardsComeAndGo() async throws {
        let model = waitingModel()
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .running)))
        model.remind(model.cards[0], .fiveMinutes)
        // A finish card rises and falls on its own, which prunes the card
        // timers; the reminder is not one of them.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .finished)))
        #expect(model.cards.map(\.id) == ["finished-b"])
        try await until { needsCards(model) == ["needs-a"] }
        #expect(needsCards(model) == ["needs-a"])
    }
}
