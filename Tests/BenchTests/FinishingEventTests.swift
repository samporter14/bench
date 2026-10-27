// FinishingEventTests.swift — the events that start a closing gesture (DESIGN.md,
// "Finishing gestures", since 1.1.0): once, for the session that finished and
// the turn it finished, never for what is not a success, never from a first
// look, never for a finish held back, and never twice. Made-up sessions fed to
// a fresh `LabModel`, which is never started: nothing is read or played.
import Foundation
import Testing
@testable import Bench

private func specimen(_ name: String) -> LabScene {
    LabScenes.catalogue.first { $0.name == name }!
}

@MainActor
struct FinishingEventTests {
    /// Where the made-up world is: a clock, and what it answers.
    final class World {
        var on = true
        var holds = false
        var shows = true
        var clock = 0.0
        var scene: LabScene
        var now = Date(timeIntervalSinceReferenceDate: 5_000)
        var rotation: Rotation
        init(_ name: String, at local: Double = 2.0) {
            scene = specimen(name)
            rotation = Rotation([scene])
            clock = local
        }
    }

    private func store(_ world: World, rotations: [String: Rotation] = [:]) -> FinishingGestures {
        FinishingGestures(
            isOn: { world.on },
            rotation: { rotations[$0.id] ?? world.rotation },
            clock: { world.clock },
            holds: { world.holds },
            panelShows: { _ in world.shows },
            poster: { $0.duration * 0.6 },
            now: { world.now })
    }

    /// A made-up session whose turn began `turn` seconds after a fixed start.
    private func session(_ id: String, _ state: SessionState = .finished, ending: SessionEnding? = .completed,
                         turn: Double = 0, updated: Double = 0) -> SessionStatus {
        let start = Date(timeIntervalSinceReferenceDate: 1_000 + turn)
        return SessionStatus(id: id, projectID: "p", projectName: "Example project", title: "Example session", state: state,
                             updatedAt: Date(timeIntervalSinceReferenceDate: 1_900 + turn + updated), startedAt: start,
                             ending: state == .finished ? ending : nil)
    }

    private func model(_ store: FinishingGestures, calls: Calls? = nil) -> LabModel {
        let model = LabModel()
        model.lifetimeScale = 0.01
        model.finishRaised = { session, onShow in
            calls?.told.append((session.id, onShow))
            store.finishRaised(session, onShow: onShow)
        }
        return model
    }

    final class Calls { var told: [(id: String, onShow: Bool)] = [] }

    /// The cards are gone, as they are by the time a long turn ends.
    private func clear(_ model: LabModel) {
        for card in model.cards { model.dismiss(card) }
    }

    // MARK: Trigger once, for what really finished

    @Test func aCompletionOfTheSpecimenOnShowPlansAGestureFromItsSceneAndPhase() throws {
        let world = World("Droplet coalescence", at: 2.0)
        let gestures = store(world)
        let model = model(gestures)
        model.ingest(Fixture.snapshot(session("a", .running)))
        model.ingest(Fixture.snapshot(session("a")))
        let run = try #require(gestures.claim(session("a"), allowed: true))
        #expect(run.plan.scene == "Droplet coalescence")
        #expect(run.plan.kind == .settle && run.plan.from == 2.0, "from the frame that was showing")
        #expect(run.began == world.now)
    }

    @Test func theSameCompletionToldTwiceIsOneGestureThatPlaysOnce() throws {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let calls = Calls()
        let model = model(gestures, calls: calls)
        model.ingest(Fixture.snapshot(session("a", .running)))
        model.ingest(Fixture.snapshot(session("a")))
        model.ingest(Fixture.snapshot(session("a")))
        #expect(calls.told.count == 1, "the read that found it again told nobody")
        let first = try #require(gestures.claim(session("a"), allowed: true))
        // The view is rebuilt, the card reopened, the completion told again: it is the one run.
        world.now = world.now.addingTimeInterval(30)
        gestures.finishRaised(session("a"), onShow: true)
        #expect(gestures.count == 1)
        #expect(gestures.standing(of: session("a")) == .played, "told again, it is not planned afresh")
        #expect(gestures.claim(session("a"), allowed: true) == first, "and a rebuilt well finds the same run")
    }

    @Test func aNewTurnOfTheSameSessionFinishesAgainByItself() throws {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let model = model(gestures)
        model.ingest(Fixture.snapshot(session("a", .running)))
        model.ingest(Fixture.snapshot(session("a")))
        let first = try #require(gestures.claim(session("a"), allowed: true))
        // The first card has gone by the time the next turn runs, and finishes.
        clear(model)
        world.now = world.now.addingTimeInterval(120)
        world.clock = 3.0
        model.ingest(Fixture.snapshot(session("a", .running, turn: 200)))
        model.ingest(Fixture.snapshot(session("a", turn: 200)))
        #expect(gestures.standing(of: session("a", turn: 200)) == .waiting, "a finish of its own")
        let second = try #require(gestures.claim(session("a", turn: 200), allowed: true))
        #expect(second != first && second.plan.from == 3.0 && second.began > first.began)
        // The first stays played.
        #expect(gestures.standing(of: session("a")) == .played)
    }

    @Test func aStaleFinishFromAnotherSessionNeverClosesTheSceneThatIsShown() throws {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let calls = Calls()
        let model = model(gestures, calls: calls)
        // B is the one the panel plays (written last); A works behind it.
        model.ingest(Fixture.snapshot(session("a", .running), session("b", .running, updated: 50)))
        #expect(model.working.first?.id == "b")
        model.ingest(Fixture.snapshot(session("a"), session("b", .running, updated: 50)))
        #expect(calls.told.map(\.id) == ["a"] && calls.told.map(\.onShow) == [false], "A was not what the panel played")
        clear(model)
        #expect(gestures.standing(of: session("a")) == .none)
        #expect(gestures.claim(session("a"), allowed: true) == nil)
        #expect(gestures.count == 0, "B's scene, still playing, has nothing planned to close it")
        // B's own finish, later, is its own.
        model.ingest(Fixture.snapshot(session("a"), session("b", updated: 50)))
        #expect(gestures.standing(of: session("b", updated: 50)) == .waiting)
        #expect(gestures.standing(of: session("a")) == .none)
        let run = try #require(gestures.claim(session("b", updated: 50), allowed: true))
        #expect(run.plan.scene == "Droplet coalescence")
    }

    @Test func theSpecimenOnShowIsOnlyTheHeadOfTheWorkingSessionsWithNothingOverIt() {
        let a = session("a", .running), b = session("b", .running)
        func onShow(_ s: SessionStatus, head: SessionStatus?, hidden: Bool = false, cardUp: Bool = false, unreadable: Bool = false) -> Bool {
            FinishingGestures.wasOnShow(s, head: head, hidden: hidden, cardUp: cardUp, unreadable: unreadable)
        }
        #expect(onShow(a, head: a))
        #expect(!onShow(a, head: b), "another session's specimen was playing")
        #expect(!onShow(a, head: nil), "nothing was playing")
        #expect(!onShow(a, head: a, hidden: true), "the user had hidden the working panel")
        #expect(!onShow(a, head: a, cardUp: true), "a card was over the working face")
        #expect(!onShow(a, head: a, unreadable: true), "the panel said it was not updating")
    }

    @Test func aPlanIsOnlyEverFoundByTheSessionAndTurnItWasMadeFor() throws {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        gestures.finishRaised(session("a"), onShow: true)
        #expect(gestures.claim(session("b"), allowed: true) == nil, "another session")
        #expect(gestures.claim(session("a", turn: 5), allowed: true) == nil, "another turn")
        #expect(gestures.claim(session("a"), allowed: true) != nil)
    }

    @Test func eachSessionKeepsItsOwnSpecimenAndPhase() throws {
        let world = World("Droplet coalescence", at: 2.0)
        let fern = Rotation([specimen("Fern unfurling")])
        let gestures = store(world, rotations: ["f": fern])
        gestures.finishRaised(session("d"), onShow: true)
        world.clock = 1.0
        gestures.finishRaised(session("f"), onShow: true)
        #expect(gestures.claim(session("d"), allowed: true)?.plan.scene == "Droplet coalescence")
        #expect(gestures.claim(session("f"), allowed: true)?.plan.scene == "Fern unfurling")
        #expect(gestures.claim(session("d"), allowed: true)?.plan.from == 2.0, "A's phase is A's, not what the clock says now")
    }

    @Test func whatIsNotASuccessNeverGetsOne() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let cases: [(String, SessionState, SessionEnding?)] = [
            ("cancelled", .finished, .cancelled), ("replaced", .finished, .replaced), ("unsaid", .finished, nil),
            ("error", .error, nil), ("waiting", .needsInput, nil), ("working", .running, nil), ("unknown", .unknown, nil),
        ]
        for (name, state, ending) in cases {
            gestures.finishRaised(session(name, state, ending: ending), onShow: true)
            #expect(gestures.standing(of: session(name, state, ending: ending)) == .none, "\(name)")
        }
        #expect(gestures.count == 0)
        // And the completion that was a success is the one that does.
        gestures.finishRaised(session("done"), onShow: true)
        #expect(gestures.count == 1)
    }

    @Test func throughTheModelAWaitingOrFailedSessionTellsNoOneAndAnAnsweredOneThatFinishesDoes() {
        let world = World("Droplet coalescence")
        let calls = Calls()
        let model = model(store(world), calls: calls)
        model.ingest(Fixture.snapshot(session("a", .running), session("b", .running, updated: 5), session("c", .running, updated: 9)))
        model.ingest(Fixture.snapshot(session("a", .needsInput), session("b", .error), session("c", .running, updated: 9)))
        #expect(calls.told.isEmpty)
        // A question answered and the work done is a finish; a failure that then runs and stops is not.
        model.ingest(Fixture.snapshot(session("a"), session("b", .error), session("c", .running, updated: 9)))
        #expect(calls.told.map(\.id) == ["a"])
    }

    @Test func aSessionFoundAlreadyFinishedWhenCapsidLooksFirstIsNotAnEvent() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let calls = Calls()
        let model = model(gestures, calls: calls)
        model.ingest(Fixture.snapshot(session("a")))
        model.ingest(Fixture.snapshot(session("a")))
        #expect(calls.told.isEmpty && gestures.count == 0)
    }

    @Test func aFinishSeenBeforeAReadHasWorkedIsNotNewsToTheGesture() {
        // The first read that worked is the baseline: a read that failed halfway is not one.
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let calls = Calls()
        let model = model(gestures, calls: calls)
        let broken: (SessionStatus) -> ScienceSnapshot = {
            ScienceSnapshot(runningCount: 1, daemonVersion: nil, sessions: [$0], readError: .databaseUnreadable("test"))
        }
        model.ingest(broken(session("a", .running)))
        model.ingest(broken(session("a")))
        #expect(calls.told.isEmpty && gestures.count == 0)
    }

    @Test func aDisconnectTellsNoOneAndAFinishDuringTheGapStillIsNewsAfterIt() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let calls = Calls()
        let model = model(gestures, calls: calls)
        model.ingest(Fixture.snapshot(session("a", .running)))
        model.ingest(Fixture.failedRead)
        model.ingest(Fixture.daemonDown)
        #expect(calls.told.isEmpty && gestures.count == 0, "the daemon being away is no completion")
    }

    @Test func aFinishHeldForAPresentationOrFocusNeverPlays() {
        let world = World("Droplet coalescence")
        for quiet in [true, false] {
            let gestures = store(world)
            let calls = Calls()
            let model = model(gestures, calls: calls)
            model.isQuiet = { quiet }
            model.holdsFinishes = { !quiet }
            model.ingest(Fixture.snapshot(session("a", .running)))
            model.ingest(Fixture.snapshot(session("a")))
            #expect(calls.told.isEmpty && gestures.count == 0, "held while \(quiet ? "presenting" : "focusing")")
            #expect(model.heldFinishes.map(\.id) == ["a"])
            // What comes when the hold lifts is a notice with no specimen in it.
            model.isQuiet = { false }
            model.holdsFinishes = { false }
            model.releaseHeldFinishes()
            #expect(calls.told.isEmpty && gestures.count == 0)
        }
    }

    @Test func aFinishThatLandsBehindACardOrAHiddenPanelHadNoSpecimenToClose() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        let calls = Calls()
        let model = model(gestures, calls: calls)
        model.ingest(Fixture.snapshot(session("a", .running), session("b", .running, updated: 50)))
        // A card is up over the working face when A finishes.
        model.ingest(Fixture.snapshot(session("a", .running), session("b", .needsInput, updated: 50)))
        model.ingest(Fixture.snapshot(session("a"), session("b", .needsInput, updated: 50)))
        #expect(calls.told.map(\.onShow) == [false])
        #expect(gestures.count == 0)
    }

    // MARK: What the world allows

    @Test func theSettingOffAndEveryOtherSpecimenKeepTheirFinish() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        world.on = false
        gestures.finishRaised(session("a"), onShow: true)
        world.on = true
        world.scene = specimen("Flask")
        world.rotation = Rotation([world.scene])
        gestures.finishRaised(session("b"), onShow: true)
        #expect(gestures.count == 0)
        world.scene = specimen("Diatom")
        world.rotation = Rotation([world.scene])
        gestures.finishRaised(session("c"), onShow: true)
        #expect(gestures.count == 1)
    }

    @Test func theSettingIsOnUnlessSwitchedOff() {
        let scratch = ScratchDefaults.make(prefix: "finishing")
        defer { scratch.discard() }
        #expect(FinishingGestures.settingIsOn(scratch.defaults), "absent is on")
        scratch.defaults.set(false, forKey: SettingsKey.finishingGesture)
        #expect(!FinishingGestures.settingIsOn(scratch.defaults))
        scratch.defaults.set(true, forKey: SettingsKey.finishingGesture)
        #expect(FinishingGestures.settingIsOn(scratch.defaults))
    }

    @Test func whileNobodyIsAtTheMacOrThePanelDoesNotPlayItsSpecimenThereIsNothingToClose() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        world.holds = true
        gestures.finishRaised(session("a"), onShow: true)
        world.holds = false
        world.shows = false
        gestures.finishRaised(session("b"), onShow: true)
        #expect(gestures.count == 0)
    }

    @Test func underReduceMotionTheStillShowsAtOnceAndTheGestureNeverPlaysLater() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        gestures.finishRaised(session("a"), onShow: true)
        #expect(gestures.claim(session("a"), allowed: false) == nil, "the plate, at once")
        #expect(gestures.standing(of: session("a")) == .declined)
        // Motion comes back, the card is reopened, the view rebuilt: still the plate.
        #expect(gestures.claim(session("a"), allowed: true) == nil)
        gestures.finishRaised(session("a"), onShow: true)
        #expect(gestures.claim(session("a"), allowed: true) == nil, "told again, it is not re-armed")
    }

    // MARK: A short sequence

    @Test func aSequenceMemberFinishesAsItselfAndTheRestOfTheStoryIsNeverTouched() throws {
        let story = ["Microtome ribbon", "Histology slide", "Microscope"].map(specimen)
        let rotation = Rotation(story)
        let world = World("Microtome ribbon")
        world.rotation = rotation
        let gestures = store(world)
        // 1.0 s into the ribbon, the story's first member (5.6 s).
        world.clock = 1.0
        gestures.finishRaised(session("a"), onShow: true)
        let run = try #require(gestures.claim(session("a"), allowed: true))
        #expect(run.plan.scene == "Microtome ribbon")
        #expect(run.plan.from == 1.0 && run.plan.to - run.plan.from <= FinishingGesture.reach, "a fraction of a second of its own loop")
        // In the second member, which has no gesture, nothing is planned and the plate shows.
        world.clock = story[0].duration + 1.0
        gestures.finishRaised(session("b"), onShow: true)
        #expect(gestures.standing(of: session("b")) == .none)
        // Late in the first member, near where the story moves on, it dissolves in its own member and does not run on.
        world.clock = story[0].duration - 0.1
        gestures.finishRaised(session("c"), onShow: true)
        let late = try #require(gestures.claim(session("c"), allowed: true))
        #expect(late.plan.scene == "Microtome ribbon" && late.plan.kind == .dissolve)
        #expect(late.plan.rest == .scene(specimen("Microtome ribbon").duration * 0.6), "to its own still")
    }

    // MARK: The work ends

    @Test func theOldestFinishesAreForgottenAndTheKeptNumberIsBounded() {
        let world = World("Droplet coalescence")
        let gestures = store(world)
        for k in 0..<(FinishingGestures.kept + 5) { gestures.finishRaised(session("s\(k)"), onShow: true) }
        #expect(gestures.count == FinishingGestures.kept)
        #expect(gestures.claim(session("s0"), allowed: true) == nil)
        #expect(gestures.claim(session("s\(FinishingGestures.kept + 4)"), allowed: true) != nil)
    }

    @Test func nothingRunsOfItsOwn() {
        // The store has no timer or task: it only ever answers. Asking again later gives the same run.
        let world = World("Droplet coalescence")
        let gestures = store(world)
        gestures.finishRaised(session("a"), onShow: true)
        let run = gestures.claim(session("a"), allowed: true)
        world.now = world.now.addingTimeInterval(3_600)
        #expect(gestures.claim(session("a"), allowed: true) == run, "an hour later: the same began, so the well finds it over")
        let elapsed = world.now.timeIntervalSince(run!.began)
        #expect(elapsed >= run!.plan.duration)
        #expect(run!.plan.frame(at: elapsed) == run!.plan.rest)
    }
}
