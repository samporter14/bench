// ReminderTests.swift — Later on a needs-input card: it comes back when its
// time comes or a focus session ends, but only while its session still waits;
// and the list of what is put off, with Show Now and Cancel Reminder. Made-up
// sessions only; the model under test is a fresh one, never `shared`, and is
// never started.
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

    /// A model with session "b" waiting on a plan as well, its card behind a's.
    private func twoWaitingModel() -> LabModel {
        let model = waitingModel()
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .needsInput, reason: .plan)))
        return model
    }

    private func card(_ model: LabModel, _ id: String) throws -> LabCard {
        try #require(model.cards.first { $0.id == id })
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

    // MARK: Seeing and managing what is put off

    @Test func aTimedReminderRecordsWhenItIsDue() throws {
        let model = twoWaitingModel()
        model.lifetimeScale = 1 // real minutes; both reminders are cancelled below
        let before = Date()
        model.remind(try card(model, "needs-a"), .fiveMinutes)
        model.remind(try card(model, "needs-b"), .fifteenMinutes)
        let after = Date()
        let five = try #require(model.snoozed.first { $0.id == "a" })
        let fifteen = try #require(model.snoozed.first { $0.id == "b" })
        let fiveDue = try #require(five.due)
        let fifteenDue = try #require(fifteen.due)
        #expect(fiveDue >= before.addingTimeInterval(5 * 60) && fiveDue <= after.addingTimeInterval(5 * 60))
        #expect(fifteenDue >= before.addingTimeInterval(15 * 60) && fifteenDue <= after.addingTimeInterval(15 * 60))
        #expect(five.session.waitingReason == .question)
        #expect(fifteen.session.waitingReason == .plan)
        // The list says it in the clock's own format.
        #expect(ActivityList.line(for: five) == "Reminds you at \(fiveDue.formatted(date: .omitted, time: .shortened))")
        model.cancelReminder("a")
        model.cancelReminder("b")
    }

    @Test func aReminderThatWaitsForFocusHasNoDueTime() {
        let model = waitingModel(focusing: { true })
        #expect(model.snoozed.isEmpty)
        model.remind(model.cards[0], .afterFocus)
        #expect(model.snoozed.map(\.id) == ["a"])
        #expect(model.snoozed.first?.due == nil)
        #expect(ActivityList.line(for: model.snoozed[0]) == "Reminds you after your focus session")
    }

    @Test func aReminderThatIsDueLeavesTheList() async throws {
        let model = waitingModel()
        model.remind(model.cards[0], .fiveMinutes)
        #expect(model.snoozed.count == 1)
        try await until { !model.cards.isEmpty }
        #expect(model.snoozed.isEmpty)
    }

    @Test func theListKeepsTheSessionAsLastRead() {
        let model = waitingModel(focusing: { true })
        model.remind(model.cards[0], .afterFocus)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question, title: "Renamed")))
        #expect(model.snoozed.first?.session.title == "Renamed")
        #expect(model.remindedSessionIDs == ["a"])
    }

    @Test(arguments: [LabReminder.fiveMinutes, .afterFocus])
    func theListEmptiesWhenTheSessionStopsWaiting(_ reminder: LabReminder) {
        let model = waitingModel(focusing: { true })
        model.remind(model.cards[0], reminder)
        #expect(model.snoozed.count == 1)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(model.snoozed.isEmpty)
        // It stays empty when the session asks again: that is a new request.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.snoozed.isEmpty)
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func theListEmptiesWhenTheSessionFinishesOrFails() {
        for last in [SessionState.finished, .error] {
            let model = waitingModel(focusing: { true })
            model.remind(model.cards[0], .afterFocus)
            model.ingest(Fixture.snapshot(Fixture.session("a", last)))
            #expect(model.snoozed.isEmpty)
        }
    }

    @Test func showNowBringsTheCardBackAtOnce() {
        let model = waitingModel()
        model.lifetimeScale = 1
        model.remind(model.cards[0], .fifteenMinutes)
        #expect(model.cards.isEmpty)
        model.showNow("a")
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.cards.first?.session?.waitingReason == .question)
        #expect(model.snoozed.isEmpty)
        #expect(model.remindedSessionIDs.isEmpty)
    }

    @Test func showNowLeavesNothingForTheEndOfFocusToBringBack() {
        var focusing = true
        let model = waitingModel(focusing: { focusing })
        model.remind(model.cards[0], .afterFocus)
        model.showNow("a")
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.remindedSessionIDs.isEmpty)
        model.dismiss(model.cards[0])
        focusing = false
        model.focusEnded()
        #expect(model.cards.isEmpty)
    }

    @Test func showNowStopsTheTimerSoALaterReminderIsNotWokenByIt() async throws {
        let model = waitingModel()
        model.lifetimeScale = 0.0005 // five minutes last 150 ms, fifteen 450 ms
        model.remind(model.cards[0], .fiveMinutes)
        model.showNow("a")
        model.remind(try card(model, "needs-a"), .fifteenMinutes)
        try await Task.sleep(for: .milliseconds(250)) // past the first timer's end
        #expect(model.cards.isEmpty)
        #expect(model.snoozed.count == 1)
        try await until { !model.cards.isEmpty }
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func showNowBringsNothingForASessionThatIsNotPutOff() {
        let model = waitingModel()
        // Dismissed for good: Show Now is not a way back.
        model.dismiss(model.cards[0])
        model.showNow("a")
        model.showNow("no-such-session")
        #expect(model.cards.isEmpty)
    }

    @Test func showNowBringsNothingForASessionThatStoppedWaiting() {
        let model = waitingModel()
        model.remind(model.cards[0], .fiveMinutes)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.showNow("a")
        #expect(model.cards.isEmpty)
        #expect(model.snoozed.isEmpty)
    }

    @Test(arguments: [LabReminder.fiveMinutes, .afterFocus])
    func cancelReminderDropsItAndTheCardDoesNotReturn(_ reminder: LabReminder) async throws {
        var focusing = true
        let model = waitingModel(focusing: { focusing })
        model.remind(model.cards[0], reminder)
        model.cancelReminder("a")
        #expect(model.snoozed.isEmpty)
        #expect(model.remindedSessionIDs.isEmpty)
        // Past the five minutes, and the end of the focus session.
        try await Task.sleep(for: .milliseconds(150))
        focusing = false
        model.focusEnded()
        #expect(model.cards.isEmpty)
        // The session still waits, and stays dismissed as after Dismiss.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.cards.isEmpty)
        #expect(model.waiting.map(\.id) == ["a"])
        // Only a new kind of request brings it back.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func cancelReminderOnlyDropsThatSessionsReminder() throws {
        let model = twoWaitingModel()
        model.remind(try card(model, "needs-a"), .afterFocus)
        model.remind(try card(model, "needs-b"), .afterFocus)
        model.cancelReminder("a")
        #expect(model.snoozed.map(\.id) == ["b"])
        model.cancelReminder("no-such-session")
        #expect(model.snoozed.map(\.id) == ["b"])
    }

    @Test func theDockMenuSaysWhenAPutOffSessionComesBack() throws {
        let model = waitingModel(focusing: { true })
        model.lifetimeScale = 1 // a real five minutes; cancelled below
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question, title: "Put off"),
                                      Fixture.session("b", .needsInput, reason: .plan, title: "Waiting"),
                                      Fixture.session("c", .needsInput, reason: .question, title: "After focus")))
        model.remind(try card(model, "needs-a"), .fiveMinutes)
        model.remind(try card(model, "needs-c"), .afterFocus)
        let items = ActivityMenu.shared.make(model: model).items
        let putOff = try #require(items.first { $0.title == "Put off" })
        let waiting = try #require(items.first { $0.title == "Waiting" })
        let afterFocus = try #require(items.first { $0.title == "After focus" })
        let due = try #require(model.snoozed.first { $0.id == "a" }?.due)
        #expect(putOff.subtitle == "Reminds you at \(due.formatted(date: .omitted, time: .shortened))")
        #expect(afterFocus.subtitle == "Reminds you after your focus session")
        // Others keep their reason, and all keep opening their session.
        #expect(waiting.subtitle == WaitingReason.plan.sentence)
        #expect(putOff.action != nil && afterFocus.action != nil)
        model.cancelReminder("a")
        let after = ActivityMenu.shared.make(model: model).items.first { $0.title == "Put off" }
        #expect(after?.subtitle == WaitingReason.question.sentence)
    }
}
