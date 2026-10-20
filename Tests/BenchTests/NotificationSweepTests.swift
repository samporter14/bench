// NotificationSweepTests.swift — the Mac notifications that outlive a quit
// (DESIGN.md, Mac notifications → Taken back): what is checked at the first
// read that can be trusted, and by which rule. The pure parts run on made-up
// notifications and sessions; the rest runs `MacNotifications` itself against
// a fake `SystemCenter`, a model of its own that is never started, and
// defaults of their own. The real center is never touched: it crashes outside
// an app bundle, and there is nothing of the user's here to take back.
import Foundation
import Testing
import UserNotifications
@testable import Bench

// MARK: The rule, pure

struct NotificationSweepRuleTests {
    private let states: [SessionState] = [.running, .needsInput, .finished, .error, .unknown]

    @Test func eachKindHoldsForTheStateItIsAbout() {
        let standing = SessionStanding([
            Fixture.session("w", .needsInput, reason: .question), Fixture.session("e", .error),
            Fixture.session("r", .running), Fixture.session("f", .finished),
        ])
        #expect(standing.holds(.needsInput, for: "w"))
        #expect(standing.holds(.failed, for: "e"))
        for id in ["e", "r", "f", "gone"] { #expect(!standing.holds(.needsInput, for: id)) }
        for id in ["w", "r", "f", "gone"] { #expect(!standing.holds(.failed, for: id)) }
    }

    @Test func aFinishIsARecordWhateverTheSessionDoesNext() {
        let standing = SessionStanding(states.map { Fixture.session("s-\($0.rawValue)", $0) })
        for state in states { #expect(standing.holds(.finished, for: "s-\(state.rawValue)")) }
        #expect(standing.holds(.finished, for: "a session this read does not have"))
    }

    /// The panel's cards and a delivered notification are told the same thing
    /// by the same `holds`: for every state a session can be in, the card of a
    /// model stays or goes as the standing says.
    @MainActor
    @Test(arguments: [SessionState.running, .needsInput, .finished, .error, .unknown])
    func theRunningAppAndTheLaunchCheckAgree(_ now: SessionState) {
        let model = LabModel()
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        // A waiting card and a failure card, then the sessions as they are now.
        model.ingest(Fixture.snapshot(Fixture.session("w", .running), Fixture.session("e", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("w", .needsInput, reason: .question), Fixture.session("e", .error)))
        #expect(Set(model.cards.map(\.id)) == ["needs-w", "failed-e"])
        let sessions = [Fixture.session("w", now, reason: now == .needsInput ? .question : nil),
                        Fixture.session("e", now, reason: now == .needsInput ? .question : nil),
                        Fixture.session("other", .running)]
        model.ingest(ScienceSnapshot(runningCount: 1, daemonVersion: "test", sessions: sessions))
        let standing = SessionStanding(sessions)
        #expect(model.cards.contains { $0.id == "needs-w" } == standing.holds(.needsInput, for: "w"))
        #expect(model.cards.contains { $0.id == "failed-e" } == standing.holds(.failed, for: "e"))
    }

    @Test func eachKindIsDecidedAlone() {
        let standing = SessionStanding([
            Fixture.session("a", .running), Fixture.session("b", .needsInput, reason: .plan),
            Fixture.session("c", .running), Fixture.session("d", .error), Fixture.session("e", .running),
        ])
        let delivered: [NotificationRules.Delivered] = [
            .init(identifier: "needs-a", kind: .needsInput, sessionID: "a"),
            .init(identifier: "needs-b", kind: .needsInput, sessionID: "b"),
            .init(identifier: "failed-c", kind: .failed, sessionID: "c"),
            .init(identifier: "failed-d", kind: .failed, sessionID: "d"),
            .init(identifier: "finished-e", kind: .finished, sessionID: "e"),
            .init(identifier: "finished-nobody", kind: .finished, sessionID: "nobody"),
        ]
        let sweep = NotificationRules.sweep(delivered, against: standing)
        #expect(sweep.gone.map(\.identifier) == ["needs-a", "failed-c"])
        #expect(sweep.adopted.map(\.identifier) == ["needs-b", "failed-d"])
        // The finishes are in neither: kept, and not watched.
    }

    // MARK: Reading a delivered notification

    private func content(_ card: LabCard) throws -> NotificationRules.Content {
        let settings = NotificationRules.Settings(enabled: true, authorized: true, finishes: true)
        return try #require(NotificationRules.content(for: card, settings: settings))
    }

    @Test func aNotificationIsReadBackFromWhatItWasPostedWith() throws {
        let link = URL(string: "http://localhost:1/projects/p/frames/a")
        for (card, kind) in [(LabCard.needsInput(Fixture.session("a", .needsInput, reason: .plan)), LabCard.SessionKind.needsInput),
                             (.failed(Fixture.session("a", .error)), .failed),
                             (.finished(Fixture.session("a", .finished)), .finished)] {
            var posted = try content(card)
            posted = NotificationRules.Content(id: posted.id, title: posted.title, body: posted.body, sound: posted.sound,
                                               sessionID: posted.sessionID, link: link)
            let read = try #require(NotificationRules.Delivered(identifier: posted.id, userInfo: NotificationRules.userInfo(for: posted)))
            #expect(read == NotificationRules.Delivered(identifier: card.id, kind: kind, sessionID: "a"))
        }
    }

    @Test func aQuestionsAnswersAreReadBackWithIt() throws {
        let ask = QuestionAsk(toolID: "toolu_made_up", items: [SessionProjection.Question(
            question: "Which baseline?", header: "", multi: false,
            options: [SessionProjection.Option(label: "Mean", detail: nil), SessionProjection.Option(label: "Median", detail: nil)])])
        let settings = NotificationRules.Settings(enabled: true, authorized: true)
        let base = try #require(NotificationRules.content(
            for: .needsInput(Fixture.session("a", .needsInput, reason: .question)), settings: settings))
        let asked = NotificationRules.withQuestion(base, ask: ask, settings: settings)
        let read = try #require(NotificationRules.Delivered(identifier: asked.id, userInfo: NotificationRules.userInfo(for: asked)))
        #expect(read.question == asked.question)
        #expect(read.question?.choices == ["Mean", "Median"])
        // Answers belong to a question: the same keys on a failure are not read.
        let onFailure = NotificationRules.Delivered(identifier: "failed-a", userInfo: NotificationRules.userInfo(for: asked))
        #expect(onFailure?.question == nil)
    }

    @Test func aNotificationThatDoesNotFitIsNotRead() {
        let session: [AnyHashable: Any] = [NotificationRules.sessionKey: "a"]
        #expect(NotificationRules.Delivered(identifier: "needs-a", userInfo: session) != nil)
        // The test notification, the "While you focused" notice, a stranger.
        #expect(NotificationRules.Delivered(identifier: MacNotifications.testID, userInfo: [:]) == nil)
        #expect(NotificationRules.Delivered(identifier: "notice-focus-held-1", userInfo: session) == nil)
        #expect(NotificationRules.Delivered(identifier: "something-a", userInfo: session) == nil)
        // The identifier and the session it carries must be the same card's.
        #expect(NotificationRules.Delivered(identifier: "needs-b", userInfo: session) == nil)
        #expect(NotificationRules.Delivered(identifier: "needs-a", userInfo: [:]) == nil)
        #expect(NotificationRules.Delivered(identifier: "needs-a", userInfo: [NotificationRules.sessionKey: 7]) == nil)
    }

    @Test func aNotificationCarriesOpaqueIdsAndNoNames() throws {
        let session = SessionStatus(id: "a", projectID: "p", projectName: "Example project", title: "Fit the curves",
                                    state: .needsInput, updatedAt: Date(), deepLink: URL(string: "http://localhost:1/projects/p/frames/a"),
                                    waitingReason: .plan)
        let posted = try content(.needsInput(session))
        let info = NotificationRules.userInfo(for: posted)
        #expect(Set(info.keys) == [NotificationRules.sessionKey, NotificationRules.linkKey])
        for value in info.values {
            let text = try #require(value as? String)
            #expect(!text.contains("Fit the curves") && !text.contains("Example"))
        }
    }
}

// MARK: The launch check, against a fake center

/// The system's notification center, made up: what it shows, and a record of
/// everything asked of it.
@MainActor
private final class FakeCenter {
    var status = UNAuthorizationStatus.authorized
    var shown: [NotificationRules.Delivered] = []
    var listings = 0
    var removed: [String] = []
    var removedAll = 0
    var categorySets: [Set<String>] = []
    var added: [UNNotificationRequest] = []
    /// Runs while macOS is "answering" which notifications it shows.
    var whileListing: () -> Void = {}

    var center: SystemCenter {
        SystemCenter(
            setDelegate: { _ in },
            authorization: { [self] in status },
            requestAuthorization: { (true, nil) },
            delivered: { [self] in
                listings += 1
                whileListing()
                return shown
            },
            add: { [self] request, completion in
                added.append(request)
                completion(nil)
            },
            removeDelivered: { [self] in removed += $0 },
            removeAllDelivered: { [self] in removedAll += 1 },
            setCategories: { [self] in categorySets.append(Set($0.map(\.identifier))) })
    }
}

@MainActor
private final class Rig {
    let fake = FakeCenter()
    let model = LabModel()
    let notifications: MacNotifications
    private let defaults: UserDefaults
    private let suite = "NotificationSweepTests-\(UUID().uuidString)"

    /// `real` false is a demo or `swift test` itself: no center at all.
    init(on: Bool = true, finishes: Bool = false, names: Bool = true, real: Bool = true) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(on, forKey: SettingsKey.macNotifications)
        defaults.set(finishes, forKey: SettingsKey.macNotifyFinishes)
        defaults.set(names, forKey: SettingsKey.macNotifyNames)
        defaults.set(false, forKey: SettingsKey.soundOnNeedsInput)
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        let fake = fake
        notifications = MacNotifications(center: { real ? fake.center : nil }, lab: model, defaults: defaults)
        notifications.start()
    }

    deinit { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    /// For an assertion that nothing happened, which a slow machine cannot
    /// make fail: a short wait for anything wrongly started to show itself.
    func settle() async throws { try await Task.sleep(for: .milliseconds(30)) }

    /// Waits for what a read set going. The check is a task of the notifier's
    /// (`sweeping`), which a read starts at once or not at all, so awaiting
    /// it is exact; everything else a read does is done when it returns.
    func read(_ sessions: SessionStatus...) async {
        await read(ScienceSnapshot(runningCount: sessions.count, daemonVersion: "test", sessions: sessions))
    }

    func read(_ snapshot: ScienceSnapshot) async {
        model.ingest(snapshot)
        await notifications.sweeping?.value
    }

    /// Polls for a condition that only a task outside the notifier's own can
    /// bring about, with a ceiling no loaded machine reaches.
    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func question(_ tool: String = "toolu_made_up", _ text: String = "Which baseline?") -> NotificationRules.QuestionActions {
        NotificationRules.QuestionActions(toolID: tool, question: text, choices: ["Mean", "Median"])
    }
}

private func note(_ kind: LabCard.SessionKind, _ session: String,
                  question: NotificationRules.QuestionActions? = nil) -> NotificationRules.Delivered {
    NotificationRules.Delivered(identifier: kind.cardID(session), kind: kind, sessionID: session, question: question)
}

@MainActor
struct NotificationSweepTests {
    // MARK: What goes and what stays

    @Test func aStaleNotificationGoesAndWhatStillHoldsStays() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "answered"), note(.needsInput, "waiting"),
                          note(.failed, "rerun"), note(.failed, "broken"),
                          note(.finished, "done"), note(.finished, "done-and-running-again")]
        await rig.read(Fixture.session("answered", .running), Fixture.session("waiting", .needsInput, reason: .plan),
                           Fixture.session("rerun", .running), Fixture.session("broken", .error),
                           Fixture.session("done", .finished), Fixture.session("done-and-running-again", .running))
        #expect(rig.fake.listings == 1)
        #expect(rig.fake.removed == ["needs-answered", "failed-rerun"])
        #expect(rig.fake.removedAll == 0)
    }

    @Test func aSessionTheReadDoesNotHaveIsNotWaitingOrFailedToo() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "old"), note(.failed, "older"), note(.finished, "oldest")]
        await rig.read(Fixture.session("other", .running))
        #expect(rig.fake.removed == ["needs-old", "failed-older"])
    }

    @Test func nothingNewIsEverPosted() async throws {
        for names in [true, false] {
            let rig = Rig(finishes: true, names: names)
            rig.fake.shown = [note(.needsInput, "a", question: Rig.question()), note(.needsInput, "b"), note(.failed, "c")]
            await rig.read(Fixture.session("a", .needsInput, reason: .question), Fixture.session("b", .running),
                               Fixture.session("c", .error))
            #expect(rig.fake.added.isEmpty)
            #expect(rig.fake.listings == 1)
        }
    }

    // MARK: Not before a read that can be trusted

    @Test func nothingIsListedOrTakenBackBeforeTheFirstRead() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "a"), note(.failed, "b")]
        try await rig.settle()
        #expect(rig.fake.listings == 0 && rig.fake.removed.isEmpty)
    }

    @Test func aFailedFirstReadTakesNothingBackButTheNextGoodOneDoes() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "a"), note(.failed, "b")]
        await rig.read(Fixture.failedRead)
        await rig.read(Fixture.daemonDown)
        // Sessions that arrived with an error are not a read that worked either.
        await rig.read(ScienceSnapshot(runningCount: 1, daemonVersion: "test",
                                           sessions: [Fixture.session("z", .running)],
                                           readError: .databaseUnreadable("test")))
        #expect(rig.fake.listings == 0 && rig.fake.removed.isEmpty)
        await rig.read(Fixture.session("z", .running))
        #expect(rig.fake.listings == 1)
        #expect(rig.fake.removed == ["needs-a", "failed-b"])
    }

    @Test func anEmptyFirstReadTakesNothingBackButTheNextOneWithSessionsDoes() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "a"), note(.failed, "b")]
        await rig.read(Fixture.snapshot())
        #expect(rig.fake.listings == 0 && rig.fake.removed.isEmpty)
        await rig.read(Fixture.session("z", .running))
        #expect(rig.fake.listings == 1)
        #expect(rig.fake.removed == ["needs-a", "failed-b"])
    }

    @Test func theCheckIsMadeOnceARun() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "a")]
        await rig.read(Fixture.session("a", .needsInput, reason: .question))
        await rig.read(Fixture.session("a", .needsInput, reason: .question))
        await rig.read(Fixture.session("a", .needsInput, reason: .question), Fixture.session("b", .running))
        #expect(rig.fake.listings == 1)
    }

    // MARK: Only when Capsid is the real app, with notifications on and allowed

    @Test func nothingIsTouchedWithMacNotificationsOff() async throws {
        let rig = Rig(on: false)
        rig.fake.shown = [note(.needsInput, "a"), note(.failed, "b")]
        await rig.read(Fixture.session("z", .running))
        await rig.read(Fixture.session("z", .running))
        #expect(rig.fake.listings == 0 && rig.fake.removed.isEmpty && rig.fake.removedAll == 0)
        #expect(rig.fake.categorySets.isEmpty)
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .notDetermined])
    func nothingIsTouchedWithoutPermission(_ status: UNAuthorizationStatus) async throws {
        let rig = Rig()
        rig.fake.status = status
        rig.fake.shown = [note(.needsInput, "a"), note(.failed, "b")]
        await rig.read(Fixture.session("z", .running))
        #expect(rig.fake.listings == 0 && rig.fake.removed.isEmpty && rig.fake.removedAll == 0)
    }

    @Test func aProvisionalPermissionIsPermissionEnough() async throws {
        let rig = Rig()
        rig.fake.status = .provisional
        rig.fake.shown = [note(.needsInput, "a")]
        await rig.read(Fixture.session("z", .running))
        #expect(rig.fake.removed == ["needs-a"])
    }

    @Test func aDemoOrATestRunHasNoCenterAndDoesNothing() async throws {
        let rig = Rig(real: false)
        rig.fake.shown = [note(.needsInput, "a")]
        // Cards come and go as ever; nothing reaches any center.
        await rig.read(Fixture.session("a", .running))
        await rig.read(Fixture.session("a", .needsInput, reason: .question))
        await rig.read(Fixture.session("a", .running))
        rig.notifications.sessionsRead(SessionStanding([Fixture.session("z", .running)]))
        rig.notifications.clearDelivered()
        try await rig.settle()
        let fake = rig.fake
        #expect(fake.listings == 0 && fake.removed.isEmpty && fake.removedAll == 0)
        #expect(fake.categorySets.isEmpty && fake.added.isEmpty)
    }

    // MARK: Adopted: taken back as any other, later in the run

    @Test func aFailureStillStandingIsTakenBackWhenItsSessionRunsAgain() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.failed, "broken")]
        await rig.read(Fixture.session("broken", .error))
        // The engine announces no failure for a session it first meets
        // failed: there is no card, so nothing but the adoption can do this.
        #expect(rig.model.cards.isEmpty)
        #expect(rig.fake.removed.isEmpty)
        await rig.read(Fixture.session("broken", .running))
        #expect(rig.fake.removed == ["failed-broken"])
        // And once only.
        await rig.read(Fixture.session("broken", .running))
        await rig.read(Fixture.session("broken", .finished))
        #expect(rig.fake.removed == ["failed-broken"])
    }

    @Test func aWaitingNotificationIsTakenBackOnceWhenItsSessionIsAnswered() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "b")]
        await rig.read(Fixture.session("b", .needsInput, reason: .question))
        // Its card is the silent one of the first read.
        #expect(rig.model.cards.map(\.id) == ["needs-b"])
        #expect(rig.fake.removed.isEmpty)
        await rig.read(Fixture.session("b", .running))
        #expect(rig.fake.removed == ["needs-b"])
        await rig.read(Fixture.session("b", .running))
        #expect(rig.fake.removed == ["needs-b"])
    }

    @Test func aFinishNotificationIsNeverTakenBackBySessionsMovingOn() async throws {
        let rig = Rig(finishes: true)
        rig.fake.shown = [note(.finished, "e")]
        await rig.read(Fixture.session("e", .finished))
        for state in [SessionState.running, .needsInput, .error, .finished] {
            await rig.read(Fixture.session("e", state, reason: state == .needsInput ? .question : nil))
        }
        await rig.read(Fixture.session("z", .running))
        // (The session's own waiting and failure notifications of these
        // moves come and go as ever; the finish stays.)
        #expect(!rig.fake.removed.contains("finished-e") && rig.fake.removedAll == 0)
    }

    @Test func aCardDealtWithTakesItsAdoptedNotificationBackOnce() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "b")]
        await rig.read(Fixture.session("b", .needsInput, reason: .plan))
        rig.model.dismiss(try #require(rig.model.cards.first))
        #expect(rig.fake.removed == ["needs-b"])
        // The session stops waiting later: nothing is left to take back.
        await rig.read(Fixture.session("b", .running))
        #expect(rig.fake.removed == ["needs-b"])
    }

    @Test func aPlanHeldForItsApprovalKeepsItsNotificationAsItKeepsItsCard() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "b")]
        await rig.read(Fixture.session("b", .needsInput, reason: .plan))
        rig.model.holdPlanCard("b")
        await rig.read(Fixture.session("b", .running))
        #expect(rig.model.cards.map(\.id) == ["needs-b"])
        #expect(rig.fake.removed.isEmpty)
        rig.model.releasePlanCard("b", approved: true)
        #expect(rig.fake.removed == ["needs-b"])
    }

    @Test func clearingEverythingForgetsWhatWasAdopted() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.failed, "broken")]
        await rig.read(Fixture.session("broken", .error))
        rig.notifications.clearDelivered()
        #expect(rig.fake.removedAll == 1)
        await rig.read(Fixture.session("broken", .running))
        #expect(rig.fake.removed.isEmpty)
    }

    // MARK: A question's answers

    @Test func aQuestionStillWaitingKeepsItsAnswersRegisteredAndDropsThemWithIt() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "b", question: Rig.question("toolu_b")),
                          note(.needsInput, "c", question: Rig.question("toolu_c")),
                          note(.needsInput, "stale", question: Rig.question("toolu_s"))]
        await rig.read(Fixture.session("b", .needsInput, reason: .question),
                           Fixture.session("c", .needsInput, reason: .question), Fixture.session("stale", .running))
        // Registered for the two that stand, none for the one that went.
        #expect(rig.fake.removed == ["needs-stale"])
        #expect(rig.fake.categorySets.last == ["question.needs-b", "question.needs-c"])
        // One answered: its answers go, the other's stay, as the very next
        // change to the set of categories replaces them all.
        await rig.read(Fixture.session("b", .running), Fixture.session("c", .needsInput, reason: .question))
        #expect(rig.fake.removed == ["needs-stale", "needs-b"])
        #expect(rig.fake.categorySets.last == ["question.needs-c"])
        await rig.read(Fixture.session("b", .running), Fixture.session("c", .running))
        #expect(rig.fake.categorySets.last == [])
    }

    @Test func withNamesHiddenNoAnswersAreRegisteredButTheNotificationIsStillChecked() async throws {
        let rig = Rig(names: false)
        rig.fake.shown = [note(.needsInput, "b", question: Rig.question()), note(.needsInput, "c")]
        await rig.read(Fixture.session("b", .needsInput, reason: .question), Fixture.session("c", .running))
        #expect(rig.fake.categorySets.isEmpty)
        #expect(rig.fake.removed == ["needs-c"])
        await rig.read(Fixture.session("b", .running))
        #expect(rig.fake.removed == ["needs-c", "needs-b"])
    }

    // MARK: Cleared meanwhile

    @Test func notificationsClearedWhileMacOSAnswersAreNotBroughtBack() async throws {
        let rig = Rig()
        rig.fake.shown = [note(.needsInput, "b", question: Rig.question()), note(.needsInput, "stale")]
        let notifications = rig.notifications
        rig.fake.whileListing = { notifications.clearDelivered() }
        await rig.read(Fixture.session("b", .needsInput, reason: .question), Fixture.session("stale", .running))
        #expect(rig.fake.listings == 1)
        #expect(rig.fake.removedAll == 1)
        #expect(rig.fake.removed.isEmpty)
        // Only the clearing touched the categories.
        #expect(rig.fake.categorySets == [[]])
    }

    // MARK: What was already there keeps working

    @Test func aCardStillPostsAndWithdrawsThroughTheCenter() async throws {
        let rig = Rig()
        // A first read, then a session that starts to fail.
        await rig.read(Fixture.session("a", .running))
        await rig.read(Fixture.session("a", .error))
        // Posted by a task of its own, after macOS says what it allows.
        try await rig.until { rig.fake.added.count == 1 }
        let request = try #require(rig.fake.added.first)
        #expect(rig.fake.added.count == 1)
        #expect(request.identifier == "failed-a")
        #expect(request.content.userInfo[NotificationRules.sessionKey] as? String == "a")
        // Its card going takes it back.
        await rig.read(Fixture.session("a", .running))
        #expect(rig.fake.removed == ["failed-a"])
    }
}
