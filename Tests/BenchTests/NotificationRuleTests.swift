// NotificationRuleTests.swift — what gets a Mac notification, and in what
// words, on made-up cards; and when the Lab model tells the notifier about a
// card. The notifier itself (MacNotifications) is never used: it touches the
// system's notification center, which crashes outside an app bundle. The
// models under test are fresh ones, never `shared`, and are never started.
import Foundation
import Testing
@testable import Bench

struct NotificationRuleTests {
    /// Notifications on, allowed, with the defaults of every other setting
    /// except the sound, which is off here so a test can see it come.
    private func on(_ change: (inout NotificationRules.Settings) -> Void = { _ in }) -> NotificationRules.Settings {
        var settings = NotificationRules.Settings(enabled: true, authorized: true, benchPlaysSound: false)
        change(&settings)
        return settings
    }

    private let waiting = LabCard.needsInput(Fixture.session("a", .needsInput, reason: .plan, title: "Fit the curves"))
    private let failed = LabCard.failed(Fixture.session("b", .error, title: "Align the reads"))
    private let finished = LabCard.finished(Fixture.session("c", .finished, title: "Count the colonies"))

    // MARK: What each kind says

    @Test func aSessionThatNeedsYouSaysWhyAndWhere() throws {
        let content = try #require(NotificationRules.content(for: waiting, settings: on()))
        #expect(content.title == "Fit the curves")
        #expect(content.body == "Plan ready for your review · Example project")
        #expect(content.id == "needs-a")
        #expect(content.sessionID == "a")
    }

    @Test(arguments: WaitingReason.allCases)
    func theBodyIsTheReasonSentenceThenTheProject(_ reason: WaitingReason) throws {
        let card = LabCard.needsInput(Fixture.session("a", .needsInput, reason: reason))
        let content = try #require(NotificationRules.content(for: card, settings: on()))
        #expect(content.body == "\(reason.sentence) · Example project")
    }

    @Test func aFailureSaysItStoppedWithAnError() throws {
        let content = try #require(NotificationRules.content(for: failed, settings: on()))
        #expect(content.title == "Align the reads")
        #expect(content.body == "Stopped with an error · Example project")
        #expect(content.id == "failed-b")
    }

    @Test func aFinishSaysItFinishedWhenAsked() throws {
        let content = try #require(NotificationRules.content(for: finished, settings: on { $0.finishes = true }))
        #expect(content.title == "Count the colonies")
        #expect(content.body == "Finished · Example project")
        #expect(content.id == "finished-c")
    }

    @Test func anUntitledSessionIsNamedByItsProject() throws {
        let card = LabCard.needsInput(Fixture.session("a", .needsInput, reason: .question, title: ""))
        let content = try #require(NotificationRules.content(for: card, settings: on()))
        #expect(content.title == "Example project")
    }

    // MARK: Names hidden

    @Test func hiddenNamesLeaveNoSessionOrProjectInAnyWord() throws {
        let names = on { $0.showNames = false; $0.finishes = true }
        for card in [waiting, failed, finished] {
            let content = try #require(NotificationRules.content(for: card, settings: names))
            let words = content.title + " " + content.body
            #expect(!words.contains("Example project"))
            for title in ["Fit the curves", "Align the reads", "Count the colonies"] {
                #expect(!words.contains(title))
            }
        }
    }

    @Test func hiddenNamesStillSayWhatHappened() throws {
        let names = on { $0.showNames = false; $0.finishes = true }
        let needs = try #require(NotificationRules.content(for: waiting, settings: names))
        #expect(needs.title == "A session needs you")
        #expect(needs.body == "Plan ready for your review")
        let error = try #require(NotificationRules.content(for: failed, settings: names))
        #expect(error.title == "A session stopped with an error")
        let done = try #require(NotificationRules.content(for: finished, settings: names))
        #expect(done.title == "A session finished")
    }

    // MARK: Finishes

    @Test func aFinishNeedsItsOwnSetting() {
        #expect(NotificationRules.content(for: finished, settings: on { $0.finishes = false }) == nil)
        // What needs you comes either way.
        #expect(NotificationRules.content(for: waiting, settings: on { $0.finishes = false }) != nil)
        #expect(NotificationRules.content(for: failed, settings: on { $0.finishes = false }) != nil)
    }

    @Test func aFinishHeldForAFocusSessionIsNotSent() {
        let focusing = on { $0.finishes = true; $0.holdingFinishes = true }
        #expect(NotificationRules.content(for: finished, settings: focusing) == nil)
        // Questions and errors still come at once.
        #expect(NotificationRules.content(for: waiting, settings: focusing) != nil)
        #expect(NotificationRules.content(for: failed, settings: focusing) != nil)
    }

    // MARK: Nothing for other cards, or without permission

    @Test func aPageNotificationIsNotSent() {
        let page = WebNotification(id: "n", title: "Done", body: "Your session finished", tag: "operon-a",
                                   requireInteraction: false, receivedAt: Date())
        #expect(NotificationRules.content(for: .web(page), settings: on { $0.finishes = true }) == nil)
    }

    // MARK: What finished during a focus session

    private func held(_ sessions: SessionStatus...) throws -> LabCard {
        .notice(try #require(NoticeRules.held(sessions)))
    }

    @Test func whatFinishedDuringAFocusSessionComesAsOneWhenFinishesAreAsked() throws {
        let one = try held(Fixture.session("a", .finished, title: "Fit the curves"))
        let single = try #require(NotificationRules.content(for: one, settings: on { $0.finishes = true }))
        #expect(single.title == "Fit the curves")
        #expect(single.body == "While you focused · Finished")
        #expect(single.id == one.id)
        #expect(single.sessionID == "a")

        let many = try held(Fixture.session("a", .finished, title: "Fit the curves"),
                            Fixture.session("b", .finished), Fixture.session("c", .finished))
        let all = try #require(NotificationRules.content(for: many, settings: on { $0.finishes = true }))
        #expect(all.title == "3 sessions finished")
        #expect(all.body == "While you focused · Fit the curves and 2 more")
        // More than one session has nothing to open, so a click only brings Bench forward.
        #expect(all.sessionID == nil)

        #expect(NotificationRules.content(for: one, settings: on { $0.finishes = false }) == nil)
        #expect(NotificationRules.content(for: many, settings: on { $0.finishes = false }) == nil)
    }

    @Test func whatFinishedDuringAFocusSessionHidesNamesToo() throws {
        let names = on { $0.showNames = false; $0.finishes = true }
        let one = try held(Fixture.session("a", .finished, title: "Fit the curves"))
        let single = try #require(NotificationRules.content(for: one, settings: names))
        #expect(single.title == "A session finished while you focused")
        let many = try held(Fixture.session("a", .finished, title: "Fit the curves"), Fixture.session("b", .finished))
        let all = try #require(NotificationRules.content(for: many, settings: names))
        #expect(all.title == "Sessions finished while you focused")
        for content in [single, all] {
            #expect(!(content.title + content.body).contains("Fit the curves"))
            #expect(!(content.title + content.body).contains("Example"))
        }
    }

    @Test func aSavedFileAndAnyOtherNoticeAreNotSent() {
        let notice = LabNotice(id: "n", symbol: "bell", caption: "Plan", title: "9% left", detail: "",
                               lifetime: .seconds(6))
        #expect(NotificationRules.content(for: .saved(URL(filePath: "/tmp/example.csv")), settings: on()) == nil)
        #expect(NotificationRules.content(for: .notice(notice), settings: on()) == nil)
    }

    @Test func nothingIsSentWithTheSettingOffOrWithoutPermission() {
        for card in [waiting, failed, finished] {
            #expect(NotificationRules.content(for: card, settings: on { $0.enabled = false; $0.finishes = true }) == nil)
            #expect(NotificationRules.content(for: card, settings: on { $0.authorized = false; $0.finishes = true }) == nil)
        }
    }

    @Test func theDefaultsSendNothing() {
        for card in [waiting, failed, finished] {
            #expect(NotificationRules.content(for: card, settings: NotificationRules.Settings()) == nil)
        }
    }

    // MARK: Sound

    @Test func noSoundWhenBenchPlaysItsOwn() throws {
        let quiet = on { $0.benchPlaysSound = true; $0.finishes = true }
        for card in [waiting, failed, finished] {
            let content = try #require(NotificationRules.content(for: card, settings: quiet))
            #expect(content.sound == false)
        }
    }

    @Test func theDefaultSoundWhenBenchPlaysNone() throws {
        let loud = on { $0.benchPlaysSound = false; $0.finishes = true }
        for card in [waiting, failed, finished] {
            let content = try #require(NotificationRules.content(for: card, settings: loud))
            #expect(content.sound == true)
        }
    }

    // MARK: Settings

    @Test func theSettingsAreOffByDefaultAndNamesAreOn() throws {
        let suite = "NotificationRuleTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: [
            SettingsKey.macNotifications: false,
            SettingsKey.macNotifyFinishes: false,
            SettingsKey.macNotifyNames: true,
            SettingsKey.soundOnNeedsInput: true,
        ])
        let settings = NotificationRules.Settings(authorized: true, holdingFinishes: false, defaults: defaults)
        #expect(settings == NotificationRules.Settings(enabled: false, authorized: true, finishes: false,
                                                       showNames: true, benchPlaysSound: true))
        defaults.set(true, forKey: SettingsKey.macNotifications)
        defaults.set(true, forKey: SettingsKey.macNotifyFinishes)
        defaults.set(false, forKey: SettingsKey.macNotifyNames)
        defaults.set(false, forKey: SettingsKey.soundOnNeedsInput)
        let chosen = NotificationRules.Settings(authorized: true, holdingFinishes: true, defaults: defaults)
        #expect(chosen == NotificationRules.Settings(enabled: true, authorized: true, finishes: true,
                                                     showNames: false, benchPlaysSound: false, holdingFinishes: true))
    }
}

/// When the model tells the notifier: recorded by closures, since the notifier
/// itself is never used here.
@MainActor
struct NotificationHookTests {
    private final class Record {
        var raised: [String] = []
        var withdrawn: [String] = []
    }

    private func model(_ record: Record) -> LabModel {
        let model = LabModel()
        model.lifetimeScale = 0.01 // a 6 s card lasts 60 ms
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        model.cardRaised = { record.raised.append($0.id) }
        model.cardWithdrawn = { record.withdrawn.append($0.id) }
        return model
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func nothingIsSentForWhatAlreadyWaitsAtLaunch() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.cards.map(\.id) == ["needs-a"])
        #expect(record.raised.isEmpty)
    }

    @Test func aSessionThatStartsToWaitIsSentOnceHoweverOftenItIsRead() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(record.raised == ["needs-a"])
        // Read again, a moment later: not news.
        for _ in 0..<3 {
            model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        }
        #expect(record.raised == ["needs-a"])
    }

    @Test func aQuestionThatBecomesAPlanIsSentAgain() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(record.raised == ["needs-a", "needs-a"])
        #expect(record.withdrawn.isEmpty)
    }

    @Test func aNotificationGoesWhenItsSessionStopsWaiting() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(record.withdrawn == ["needs-a"])
    }

    @Test func aNotificationGoesWhenItsCardIsOpenedOrDismissed() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question),
                                      Fixture.session("b", .needsInput, reason: .plan)))
        #expect(Set(record.raised) == ["needs-a", "needs-b"])
        model.dismiss(model.cards.first { $0.id == "needs-a" }!)
        #expect(record.withdrawn == ["needs-a"])
        model.open(model.cards.first { $0.id == "needs-b" }!)
        #expect(record.withdrawn == ["needs-a", "needs-b"])
    }

    @Test func aFailureIsSentAndGoesWhenTheSessionRunsAgain() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .error)))
        #expect(record.raised == ["failed-a"])
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(record.withdrawn == ["failed-a"])
    }

    @Test func aFinishTimingOutLeavesItsNotificationButAnOpenedOneTakesItAway() async throws {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished), Fixture.session("b", .running)))
        #expect(record.raised == ["finished-a"])
        try await until { model.cards.isEmpty }
        #expect(model.cards.isEmpty)
        #expect(record.withdrawn.isEmpty)
        // Another, acted on before its time is up.
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished), Fixture.session("b", .finished)))
        model.open(model.cards[0])
        #expect(record.withdrawn == ["finished-b"])
    }

    @Test func aFinishHeldForAFocusSessionIsNotSentThen() {
        let record = Record()
        let model = model(record)
        model.holdsFinishes = { true }
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        #expect(model.cards.isEmpty)
        #expect(record.raised.isEmpty)
    }

    @Test func whatFinishedDuringAFocusSessionIsToldWhenTheSessionEnds() throws {
        let record = Record()
        let model = model(record)
        model.holdsFinishes = { true }
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        #expect(record.raised.isEmpty)
        model.holdsFinishes = { false }
        model.focusEnded()
        #expect(record.raised.count == 1)
        let card = try #require(model.cards.last)
        #expect(record.raised == [card.id])
        // It is the card the rules send, when finishes are asked for.
        let settings = NotificationRules.Settings(enabled: true, authorized: true, finishes: true)
        #expect(NotificationRules.content(for: card, settings: settings)?.id == card.id)
        // Opening it takes its notification back.
        model.open(card)
        #expect(record.withdrawn == [card.id])
    }

    @Test func aReminderComingBackIsSentAgain() async throws {
        let record = Record()
        let model = model(record)
        model.lifetimeScale = 0.0001
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        model.remind(model.cards[0], .fiveMinutes)
        #expect(record.withdrawn == ["needs-a"])
        try await until { record.raised.count == 2 }
        #expect(record.raised == ["needs-a", "needs-a"])
    }

    @Test func aSessionIsOpenedByIdFromAnyListItIsIn() {
        let record = Record()
        let model = model(record)
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(model.open(sessionID: "a"))
        // Its card is cleared: the user is looking at it now.
        #expect(model.cards.isEmpty)
        #expect(record.withdrawn == ["needs-a"])
        // Known only from Recent, once its card and its place in the lists are gone.
        model.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        model.dismiss(model.cards[0])
        model.ingest(Fixture.snapshot())
        #expect(model.cards.isEmpty && model.latest.isEmpty)
        #expect(model.open(sessionID: "a"))
        #expect(!model.open(sessionID: "nobody"))
    }
}
