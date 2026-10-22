// ShelfToastTests.swift — the toast after Add to Shelf (Shelf/ShelfToast.swift)
// on a made-up shelf and a clock the test holds: what it says in each state,
// how long it stays, that a pointer on it holds it, that a newer toast
// replaces an older one's timer, and Undo and Show Shelf. No window is opened.
import Foundation
import Testing
@testable import Bench

/// A clock the test fires by hand: every sleep waits for `fire`.
actor ToastClock {
    private(set) var requested: [Duration] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    func fire() {
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }
}

@MainActor
struct ShelfToastTests {
    private func make() -> (ShelfToastModel, MadeShelf, ToastClock, Announcements) {
        let fake = MadeShelf()
        let clock = ToastClock()
        let said = Announcements()
        let model = ShelfToastModel(shelf: fake.access, sleep: { await clock.sleep($0) }, announce: { said.words.append($0) })
        return (model, fake, clock, said)
    }

    final class Announcements {
        var words: [String] = []
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: What it says

    @Test func eachStateSaysWhatHappened() {
        let placement = MadeShelf.placement("z_prime_by_plate.png")
        #expect(ShelfToastModel.words(.adding) == "Adding to your shelf\u{2026}")
        #expect(ShelfToastModel.words(.added(placement)) == "On your shelf: z_prime_by_plate.png")
        #expect(ShelfToastModel.words(.already(placement)) == "Already on your shelf")
        #expect(ShelfToastModel.words(.failed("That file is gone from Claude Science.")) == "That file is gone from Claude Science.")
        #expect(ShelfToastModel.words(.undone("z_prime_by_plate.png")) == "Taken off your shelf")
    }

    @Test func aboutFourSecondsThenItFadesAndAFailureStaysLonger() {
        let placement = MadeShelf.placement()
        #expect(ShelfToastModel.lasting(.added(placement)) == .seconds(4))
        #expect(ShelfToastModel.lasting(.already(placement)) == .seconds(4))
        #expect(ShelfToastModel.lasting(.failed("x"))! > .seconds(4))
        #expect(ShelfToastModel.lasting(.undone("x"))! < .seconds(4))
        // Adding stays until it is answered.
        #expect(ShelfToastModel.lasting(.adding) == nil)
    }

    // MARK: Staying and going

    @Test func itShowsAnnouncesAndGoesAfterItsTime() async {
        let (model, _, clock, said) = make()
        let placement = MadeShelf.placement()
        model.show(.added(placement))
        #expect(model.state == .added(placement))
        #expect(said.words == ["On your shelf: z_prime_by_plate.png"])
        await settle()
        #expect(await clock.requested == [.seconds(4)])
        #expect(model.state != nil)
        await clock.fire()
        await settle()
        #expect(model.state == nil)
    }

    @Test func addingNeverTimesOutOnItsOwn() async {
        let (model, _, clock, _) = make()
        model.show(.adding)
        await settle()
        #expect(await clock.requested.isEmpty)
        #expect(model.state == .adding)
    }

    @Test func aNewerToastReplacesAnOlderOnesTimer() async {
        let (model, _, clock, _) = make()
        model.show(.failed("First."))
        await settle()
        model.show(.added(MadeShelf.placement()))
        await settle()
        // The first timer fires: it belongs to a toast that is gone.
        await clock.fire()
        await settle()
        #expect(model.state == nil || model.state != .failed("First."))
        // And the newer one still got its own time.
        #expect(await clock.requested == [.seconds(6), .seconds(4)])
    }

    @Test func aPointerOnItHoldsItAndLeavingGivesItsTimeAgain() async {
        let (model, _, clock, _) = make()
        let placement = MadeShelf.placement()
        model.show(.added(placement))
        await settle()
        model.hover(true)
        await clock.fire()
        await settle()
        #expect(model.state == .added(placement))
        model.hover(false)
        await settle()
        #expect(await clock.requested == [.seconds(4), .seconds(4)])
        await clock.fire()
        await settle()
        #expect(model.state == nil)
    }

    @Test func dismissingForgetsTheTimer() async {
        let (model, _, clock, _) = make()
        model.show(.added(MadeShelf.placement()))
        await settle()
        model.dismiss()
        #expect(model.state == nil)
        model.show(.adding)
        await clock.fire()
        await settle()
        // The old timer didn't clear the new toast.
        #expect(model.state == .adding)
    }

    // MARK: The buttons

    @Test func showShelfOpensTheShelfOnTheItemAndGoes() {
        let (model, fake, _, _) = make()
        let placement = MadeShelf.placement()
        model.show(.added(placement))
        model.showShelf()
        #expect(fake.shown == [placement.folder])
        #expect(model.state == nil)
        model.show(.already(placement))
        model.showShelf()
        #expect(fake.shown == [placement.folder, placement.folder])
        // With no item in the toast, the window alone.
        model.show(.failed("Sentence."))
        model.showShelf()
        #expect(fake.shown.last! == nil)
    }

    @Test func undoSendsTheFolderToTheTrashAndSaysSo() async {
        let (model, fake, _, said) = make()
        let placement = MadeShelf.placement()
        model.show(.added(placement))
        await model.undo()
        #expect(fake.undone == [placement])
        #expect(model.state == .undone(placement.name))
        #expect(said.words.last == "Taken off your shelf")
    }

    @Test func aFailedUndoSaysTheFolderIsStillThere() async {
        let (model, fake, _, _) = make()
        fake.undoResult = false
        model.show(.added(MadeShelf.placement()))
        await model.undo()
        #expect(model.state == .failed(ShelfToastModel.undoFailed))
        #expect(ShelfToastModel.undoFailed.contains("still on your shelf"))
    }

    @Test func undoOnlyActsOnAnAddedToast() async {
        let (model, fake, _, _) = make()
        model.show(.already(MadeShelf.placement()))
        await model.undo()
        model.show(.adding)
        await model.undo()
        model.dismiss()
        await model.undo()
        #expect(fake.undone.isEmpty)
    }

    @Test func aToastThatCameDuringUndoStays() async {
        let (model, fake, _, _) = make()
        let placement = MadeShelf.placement()
        fake.undoResult = true
        fake.undoHolds = true
        model.show(.added(placement))
        // Undo runs; its answer lands after a newer toast replaced the first.
        let undoing = Task { await model.undo() }
        await settle()
        #expect(fake.undone == [placement])
        model.show(.failed("A newer word."))
        fake.releaseUndo()
        await undoing.value
        #expect(model.state == .failed("A newer word."))
    }
}
