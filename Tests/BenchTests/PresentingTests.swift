// PresentingTests.swift — keeping Capsid quiet while the user presents: the
// state the Focus filter and the menu switch share, the panel that stays out
// of sight, "Finished" cards held and told as one afterwards, and no sound or
// Mac notification meanwhile. Made-up sessions only; every model under test is
// a fresh one, never `shared`, and is never started.
import Combine
import Foundation
import Testing
@testable import Bench

/// What a test says is on, read by the closures a model asks.
private final class Switches {
    var presenting = false
    var focusing = false
}

@MainActor
struct PresentingModeTests {
    @Test func eitherSourceMakesCapsidQuiet() {
        let mode = PresentingMode()
        #expect(!mode.isQuiet)
        mode.setFocusFilter(true)
        #expect(mode.isQuiet && mode.focusFilterOn && !mode.manualOn)
        mode.setFocusFilter(false)
        #expect(!mode.isQuiet)
        mode.setManual(true)
        #expect(mode.isQuiet && mode.manualOn && !mode.focusFilterOn)
        mode.toggleManual()
        #expect(!mode.isQuiet && !mode.manualOn)
    }

    @Test func bothSourcesCombineAndQuietEndsWhenTheLastOneDoes() {
        let mode = PresentingMode()
        mode.setManual(true)
        mode.setFocusFilter(true)
        // The Focus ends (the filter runs again with its default): the switch is still on.
        mode.setFocusFilter(false)
        #expect(mode.isQuiet)
        mode.setManual(false)
        #expect(!mode.isQuiet)
        // The other way round.
        mode.setFocusFilter(true)
        mode.setManual(true)
        mode.setManual(false)
        #expect(mode.isQuiet)
        mode.setFocusFilter(false)
        #expect(!mode.isQuiet)
    }

    @Test func changedIsToldOnlyWhenTheAnswerChanges() {
        let mode = PresentingMode()
        var told: [Bool] = []
        mode.changed = { told.append($0) }
        mode.setManual(true)
        mode.setFocusFilter(true)  // already quiet: nothing to tell
        mode.setManual(false)      // the Focus still keeps it quiet
        #expect(told == [true])
        mode.setFocusFilter(false)
        #expect(told == [true, false])
        // The same word again is no news.
        mode.setFocusFilter(false)
        mode.setManual(false)
        #expect(told == [true, false])
    }

    @Test func aListenerReadsTheNewAnswer() {
        let mode = PresentingMode()
        var read: [Bool] = []
        mode.changed = { _ in read.append(mode.isQuiet) }
        mode.setManual(true)
        mode.setManual(false)
        #expect(read == [true, false])
    }

    @Test func theSwitchIsNotKeptAcrossALaunch() {
        // A new model, as after a quit, comes up as usual whatever the last one said.
        let before = PresentingMode()
        before.setManual(true)
        let after = PresentingMode()
        #expect(!after.manualOn && !after.isQuiet)
    }

    @Test func launchTakesWhatTheSystemSaysAboutAFocusAlreadyOn() {
        let mode = PresentingMode()
        mode.catchUp(true)
        #expect(mode.isQuiet && mode.focusFilterOn)
        mode.catchUp(nil)
        #expect(!mode.isQuiet) // no filter configured is off
    }

    @Test func launchReadNeverOverridesAFilterThatHasRun() {
        let mode = PresentingMode()
        mode.setFocusFilter(true)
        mode.catchUp(false) // older than the run
        #expect(mode.isQuiet)
        let other = PresentingMode()
        other.setFocusFilter(false)
        other.catchUp(true)
        #expect(!other.isQuiet)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startReadsTheFilterOnceAtLaunch() async throws {
        let mode = PresentingMode()
        mode.start(inDemo: false, currentFilter: { true })
        try await until { mode.isQuiet }
        #expect(mode.isQuiet && mode.focusFilterOn)
    }

    @Test func aDemoStartsNothingReal() async throws {
        let mode = PresentingMode()
        var asked = false
        mode.start(inDemo: true, currentFilter: { asked = true; return true })
        try await Task.sleep(for: .milliseconds(150))
        #expect(!asked && !mode.isQuiet && !mode.focusFilterOn)
    }

    @Test func theFilterIsOffByDefaultAndQuietWhenSet() {
        // The system passes the default when the Focus ends, so the default must be "not quiet".
        #expect(QuietWhilePresentingFilter().quiet == false)
        #expect(QuietWhilePresentingFilter(quiet: true).quiet)
    }

    @Test func theDockItemShowsTheSwitchAndWhenAFocusIsTheReason() {
        let mode = PresentingMode()
        let off = PresentingMenu.shared.item(mode: mode, inDemo: false)
        #expect(off.title == "Quiet While Presenting" && off.state == .off && off.isEnabled && off.subtitle == nil)
        mode.setManual(true)
        #expect(PresentingMenu.shared.item(mode: mode, inDemo: false).state == .on)
        mode.setManual(false)
        mode.setFocusFilter(true)
        let focused = PresentingMenu.shared.item(mode: mode, inDemo: false)
        // A Focus is what keeps it quiet, not the switch.
        #expect(focused.state == .off && focused.subtitle == "A Focus is keeping Capsid quiet")
        #expect(!PresentingMenu.shared.item(mode: mode, inDemo: true).isEnabled)
    }
}

@MainActor
struct PresentingPanelTests {
    private let prefs = LabPanelController.Preferences(showPanel: true, showCards: true, whileFront: true)

    @Test func quietHidesThePanelWhateverIsOnIt() {
        for (cards, working) in [(true, false), (false, true), (true, true)] {
            #expect(LabPanelController.shouldShow(cards: cards, working: working, preferences: prefs, active: false, quiet: false))
            #expect(!LabPanelController.shouldShow(cards: cards, working: working, preferences: prefs, active: false, quiet: true))
        }
    }

    @Test func notQuietTheOldRulesStand() {
        let shouldShow = LabPanelController.shouldShow
        #expect(!shouldShow(false, false, prefs, false, false))
        #expect(shouldShow(true, false, LabPanelController.Preferences(showPanel: false, showCards: true, whileFront: true), false, false))
        #expect(!shouldShow(true, false, LabPanelController.Preferences(showPanel: true, showCards: false, whileFront: true), false, false))
        // Not while Capsid is in front, when that is the setting.
        #expect(!shouldShow(true, true, LabPanelController.Preferences(showPanel: true, showCards: true, whileFront: false), true, false))
    }

    @Test func thePanelGoesWhenQuietBeginsAndComesBackWithWhatWaitedWhenItEnds() {
        let model = LabModel()
        let quiet = CurrentValueSubject<Bool, Never>(false)
        var seen: [Bool] = []
        let subscription = LabPanelController.visibility(
            model: model, preferences: Just(prefs).eraseToAnyPublisher(),
            active: Just(false).eraseToAnyPublisher(), quiet: quiet.eraseToAnyPublisher())
            .sink { seen.append($0) }
        #expect(seen == [false])

        // A session works: the panel is up.
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(seen == [false, true])
        // The user starts presenting: it goes.
        quiet.send(true)
        #expect(seen == [false, true, false])
        // Meanwhile a session asks something, and the one that worked finishes.
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .needsInput, reason: .question)))
        #expect(seen == [false, true, false])
        #expect(model.cards.map(\.id) == ["needs-b"])
        // Presenting ends: the panel is back, with the card.
        quiet.send(false)
        #expect(seen == [false, true, false, true])
        #expect(model.cards.map(\.id) == ["needs-b"])
        subscription.cancel()
    }

    @Test func quietWithNothingToShowStaysHiddenAfterIt() {
        let model = LabModel()
        let quiet = CurrentValueSubject<Bool, Never>(true)
        var seen: [Bool] = []
        let subscription = LabPanelController.visibility(
            model: model, preferences: Just(prefs).eraseToAnyPublisher(),
            active: Just(false).eraseToAnyPublisher(), quiet: quiet.eraseToAnyPublisher())
            .sink { seen.append($0) }
        quiet.send(false)
        #expect(seen == [false])
        subscription.cancel()
    }
}

@MainActor
struct PresentingHoldTests {
    /// A model whose quiet and Nidus focus are `switches`.
    private func model(_ switches: Switches) -> LabModel {
        let model = LabModel()
        model.lifetimeScale = 0.01 // a 6 s card lasts 60 ms
        model.holdsFinishes = { switches.focusing }
        model.isFocusing = { switches.focusing }
        model.isQuiet = { switches.presenting }
        return model
    }

    /// Sessions that work and then finish, as two reads.
    private func finish(_ model: LabModel, _ ids: String...) {
        model.ingest(ScienceSnapshot(runningCount: ids.count, daemonVersion: "test",
                                     sessions: ids.map { Fixture.session($0, .running) }))
        model.ingest(ScienceSnapshot(runningCount: 0, daemonVersion: "test",
                                     sessions: ids.map { Fixture.session($0, .finished) }))
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func finishesWaitWhileQuietAndComeAsOneCardWordedForPresenting() throws {
        let switches = Switches()
        let model = model(switches)
        switches.presenting = true
        finish(model, "a", "b")
        // No card; they are held and in Recent.
        #expect(model.cards.isEmpty)
        #expect(model.heldFinishes.map(\.id) == ["a", "b"])
        #expect(model.recent.contains { $0.session?.id == "a" } && model.recent.contains { $0.session?.id == "b" })

        switches.presenting = false
        model.quietChanged()
        let card = try #require(model.cards.last)
        #expect(card.id.hasPrefix("notice-presenting-held-"))
        guard case .notice(let notice) = card else { Issue.record("not a notice"); return }
        #expect(notice.caption == "While you presented")
        #expect(notice.title == "2 sessions finished")
        #expect(notice.detail == "Example session and 1 more")
        #expect(!notice.caption.contains("focused"))
        #expect(model.heldFinishes.isEmpty)
    }

    @Test func oneFinishOpensItsSession() throws {
        let switches = Switches()
        let model = model(switches)
        switches.presenting = true
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished, title: "Fit the curves")))
        switches.presenting = false
        model.quietChanged()
        guard case .notice(let notice)? = model.cards.last, case .openSession(let opened) = notice.action else {
            Issue.record("no notice that opens its session")
            return
        }
        #expect(notice.title == "Fit the curves" && notice.detail == "Finished" && notice.caption == "While you presented")
        #expect(opened.id == "a")
    }

    @Test func notQuietAFinishIsACardAtOnce() {
        let switches = Switches()
        let model = model(switches)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        #expect(model.cards.map(\.id) == ["finished-a"])
        #expect(model.heldFinishes.isEmpty)
    }

    @Test func aNidusFocusSessionKeepsItsOwnWording() throws {
        let switches = Switches()
        let model = model(switches)
        switches.focusing = true
        finish(model, "a", "b")
        #expect(model.cards.isEmpty)
        switches.focusing = false
        model.focusEnded()
        let card = try #require(model.cards.last)
        #expect(card.id.hasPrefix("notice-focus-held-"))
        guard case .notice(let notice) = card else { Issue.record("not a notice"); return }
        #expect(notice.caption == "While you focused")
        #expect(notice.title == "2 sessions finished")
    }

    @Test func withBothOnTheHoldLastsUntilTheLastEndsAndIsWordedForThatOne() throws {
        // Nidus ends first: still presenting, so nothing yet.
        let switches = Switches()
        let model = model(switches)
        switches.focusing = true
        switches.presenting = true
        finish(model, "a", "b")
        switches.focusing = false
        model.focusEnded()
        #expect(model.cards.isEmpty)
        #expect(model.heldFinishes.count == 2)
        switches.presenting = false
        model.quietChanged()
        guard case .notice(let afterPresenting)? = model.cards.last else { Issue.record("no notice"); return }
        #expect(afterPresenting.caption == "While you presented")

        // Presenting ends first: the Nidus focus session still holds them.
        let other = Switches()
        let second = self.model(other)
        other.focusing = true
        other.presenting = true
        finish(second, "a", "b")
        other.presenting = false
        second.quietChanged()
        #expect(second.cards.isEmpty)
        #expect(second.heldFinishes.count == 2)
        other.focusing = false
        second.focusEnded()
        guard case .notice(let afterFocus)? = second.cards.last else { Issue.record("no notice"); return }
        #expect(afterFocus.caption == "While you focused")
    }

    @Test func turningOffTheNidusHoldSettingStillWaitsForThePresentation() {
        let switches = Switches()
        let model = model(switches)
        switches.presenting = true
        finish(model, "a", "b")
        // What Settings does when "Hold finishes" is turned off mid-session.
        model.releaseHeldFinishes()
        #expect(model.cards.isEmpty && model.heldFinishes.count == 2)
    }

    @Test func questionsAreStillRaisedAndWaitForTheEndOfQuiet() {
        let switches = Switches()
        let model = model(switches)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        switches.presenting = true
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        // Nothing is lost: the card is in the queue (the panel just isn't showing it).
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(model.waiting.map(\.id) == ["a"])
        switches.presenting = false
        model.quietChanged()
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func noSoundIsPlayedWhileQuietAndOneIsWhenNot() {
        let switches = Switches()
        let model = model(switches)
        var sounds = 0
        model.playChime = { sounds += 1 }
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        switches.presenting = true
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question), Fixture.session("b", .running)))
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(sounds == 0)
        // Not quiet: the same moment plays it.
        switches.presenting = false
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question), Fixture.session("b", .needsInput, reason: .plan)))
        #expect(sounds == 1)
    }

    @Test func aReminderComingBackIsSilentWhileQuietAndChimesWhenNot() {
        for quiet in [true, false] {
            let switches = Switches()
            let model = model(switches)
            var sounds = 0
            model.playChime = { sounds += 1 }
            switches.focusing = true
            model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
            model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
            model.remind(model.cards[0], .afterFocus)
            #expect(model.cards.isEmpty)
            sounds = 0 // the question's own sound, when it first came
            switches.focusing = false
            switches.presenting = quiet
            model.focusEnded()
            #expect(model.cards.map(\.id) == ["needs-a"])
            #expect(sounds == (quiet ? 0 : 1))
        }
    }

    @Test func aCardThatTimesOutDoesNotRunOutOfSightButStartsWhenQuietEnds() async throws {
        let switches = Switches()
        let model = model(switches)
        switches.presenting = true
        model.receive(WebNotification(id: "n", title: "Done", body: "", tag: "x", requireInteraction: false, receivedAt: Date()))
        #expect(model.cards.map(\.id) == ["web-n"])
        // Its 8 s would be 80 ms here: well past it, still there.
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.cards.map(\.id) == ["web-n"])
        switches.presenting = false
        model.quietChanged()
        try await until { model.cards.isEmpty }
        #expect(model.cards.isEmpty)
    }

    @Test func theModelAndTheStateWorkTogether() throws {
        // As the app wires them: the state tells the model, the model asks the state.
        let mode = PresentingMode()
        let model = LabModel()
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        model.isQuiet = { mode.isQuiet }
        mode.changed = { _ in model.quietChanged() }

        mode.setFocusFilter(true)       // the Focus turns on
        finish(model, "a", "b")
        #expect(model.cards.isEmpty)
        mode.setFocusFilter(false)      // it turns off: the filter's default
        let card = try #require(model.cards.last)
        #expect(card.id.hasPrefix("notice-presenting-held-"))
        guard case .notice(let notice) = card else { Issue.record("not a notice"); return }
        #expect(notice.caption == "While you presented")

        // The menu switch does the same.
        let second = LabModel()
        second.holdsFinishes = { false }
        second.isFocusing = { false }
        let manual = PresentingMode()
        second.isQuiet = { manual.isQuiet }
        manual.changed = { _ in second.quietChanged() }
        manual.setManual(true)
        finish(second, "a", "b")
        #expect(second.cards.isEmpty)
        manual.setManual(false)
        #expect(second.cards.last?.id.hasPrefix("notice-presenting-held-") == true)
    }
}

@MainActor
struct PresentingNotificationTests {
    private let session = Fixture.session("a", .running, title: "Fit the curves")
    private let allOn = NotificationRules.Settings(enabled: true, authorized: true, finishes: true, showNames: true, benchPlaysSound: true)

    private var quiet: NotificationRules.Settings {
        var settings = allOn
        settings.presenting = true
        return settings
    }

    private func held(_ reason: NoticeRules.HoldReason) throws -> LabCard {
        .notice(try #require(NoticeRules.held([Fixture.session("a", .finished, title: "Fit the curves")], reason: reason)))
    }

    @Test func nothingIsSentWhileQuiet() throws {
        let cards: [LabCard] = [
            .needsInput(Fixture.session("a", .needsInput, reason: .question)),
            .failed(Fixture.session("a", .error)),
            .finished(Fixture.session("a", .finished)),
            try held(.presenting), try held(.focus),
        ]
        for card in cards {
            #expect(NotificationRules.content(for: card, settings: allOn) != nil, "\(card.id) is sent when not quiet")
            #expect(NotificationRules.content(for: card, settings: quiet) == nil, "\(card.id) is not sent while quiet")
        }
    }

    @Test func theSettingsReadWhetherPresenting() {
        let defaults = UserDefaults(suiteName: "presenting-tests-\(UUID().uuidString)")!
        #expect(NotificationRules.Settings(authorized: true, holdingFinishes: false, defaults: defaults).presenting == false)
        #expect(NotificationRules.Settings(authorized: true, holdingFinishes: false, presenting: true, defaults: defaults).presenting)
    }

    @Test func theSummaryAfterAPresentationIsWordedForIt() throws {
        let one = try #require(NotificationRules.content(for: try held(.presenting), settings: allOn))
        #expect(one.title == "Fit the curves")
        #expect(one.body == "While you presented · Finished")
        #expect(one.sessionID == "a")
        #expect(!one.body.contains("focused"))
        var hidden = allOn
        hidden.showNames = false
        let anonymous = try #require(NotificationRules.content(for: try held(.presenting), settings: hidden))
        #expect(anonymous.title == "A session finished while you presented" && anonymous.body.isEmpty)
        let many = LabCard.notice(try #require(NoticeRules.held(
            [Fixture.session("a", .finished), Fixture.session("b", .finished)], reason: .presenting)))
        let manyHidden = try #require(NotificationRules.content(for: many, settings: hidden))
        #expect(manyHidden.title == "Sessions finished while you presented")
    }

    @Test func theSummaryAfterANidusFocusSessionKeepsItsWording() throws {
        let one = try #require(NotificationRules.content(for: try held(.focus), settings: allOn))
        #expect(one.body == "While you focused · Finished")
        var hidden = allOn
        hidden.showNames = false
        #expect(NotificationRules.content(for: try held(.focus), settings: hidden)?.title == "A session finished while you focused")
        let many = LabCard.notice(try #require(NoticeRules.held(
            [Fixture.session("a", .finished), Fixture.session("b", .finished)])))
        #expect(NotificationRules.content(for: many, settings: hidden)?.title == "Sessions finished while you focused")
    }

    @Test func theSummaryIsToldToTheNotifierWhenQuietEnds() throws {
        let switches = Switches()
        let model = LabModel()
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        model.isQuiet = { switches.presenting }
        var raised: [String] = []
        model.cardRaised = { raised.append($0.id) }
        switches.presenting = true
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        // The rules would not send anything now; the finish is not even a card.
        #expect(raised.isEmpty)
        switches.presenting = false
        model.quietChanged()
        let card = try #require(model.cards.last)
        #expect(raised == [card.id])
        #expect(NotificationRules.content(for: card, settings: allOn)?.body.hasPrefix("While you presented") == true)
    }

    @Test func theSummaryHasItsOwnPhonePushWording() throws {
        let one = try #require(PushRules.event(for: try held(.presenting), holdingFinishes: false))
        #expect(PushRules.message(one, names: true).body == "Finished while you presented · Example project")
        let nidus = try #require(PushRules.event(for: try held(.focus), holdingFinishes: false))
        #expect(PushRules.message(nidus, names: true).body == "Finished while you focused · Example project")
        let many = LabCard.notice(try #require(NoticeRules.held(
            [Fixture.session("a", .finished), Fixture.session("b", .finished)], reason: .presenting)))
        let both = try #require(PushRules.event(for: many, holdingFinishes: false))
        #expect(PushRules.message(both, names: false).body == "Sessions finished while you presented")
    }
}
