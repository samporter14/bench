// MacNotifications.swift — a Mac notification as well as the card, when the
// user asks for one (DESIGN.md, Mac notifications). What to send and in what
// words is `NotificationRules`: pure, and tested on made-up cards. Posting,
// withdrawing, listening for a click and checking, at a launch, the
// notifications that outlived the last run are `MacNotifications`, which is
// thin: it speaks to the system only through `SystemCenter`, which tests
// replace with a fake. The Settings section is at the bottom.
import AppKit
import Combine
import OSLog
import SwiftUI
import UserNotifications

private let log = Logger(subsystem: "local.sam.bench", category: "notifications")

// MARK: Rules

enum NotificationRules {
    /// Everything the decision depends on besides the card.
    struct Settings: Equatable, Sendable {
        /// "Also send a Mac notification".
        var enabled = false
        /// macOS lets Bench post.
        var authorized = false
        /// "When a session finishes too".
        var finishes = false
        /// "Show session and project names".
        var showNames = true
        /// Bench's own "Play a sound": the panel chimes then, so the
        /// notification keeps quiet.
        var benchPlaysSound = true
        /// A Nidus focus session holds finishes: the cards wait, and so do
        /// their notifications.
        var holdingFinishes = false
        /// Capsid is quiet while the user presents (PresentingMode.swift):
        /// nothing is sent, the held finishes' one included, until it ends.
        var presenting = false
    }

    /// What to post for one card.
    struct Content: Equatable, Sendable {
        /// The card's id, so a card that goes can take its notification with it.
        let id: String
        let title: String
        let body: String
        /// The default sound, or none.
        let sound: Bool
        /// The session a click opens, and the link to it for when Bench no
        /// longer knows the session (a notification that outlived a launch).
        let sessionID: String?
        let link: URL?
        /// A question's own answers, offered on the notification
        /// (`questionActions`); its words are then the question's.
        var question: QuestionActions? = nil
    }

    // MARK: What a notification carries

    /// The keys of what a notification carries besides its words: the
    /// session and the link to it, opaque ids and no names.
    static let sessionKey = "session"
    static let linkKey = "link"

    /// Everything a notification carries besides its words. A question's own
    /// copy of what it offered comes with it (`QuestionActions.userInfo`).
    static func userInfo(for content: Content) -> [String: Any] {
        var info: [String: Any] = [:]
        if let id = content.sessionID { info[sessionKey] = id }
        if let link = content.link { info[linkKey] = link.absoluteString }
        if let question = content.question { info.merge(question.userInfo) { _, new in new } }
        return info
    }

    // MARK: Notifications that outlived a quit

    /// A notification Capsid delivered earlier, as read back at a launch:
    /// what it was about, from its identifier (the card's id) and the session
    /// id in what it carries. Nil for any other: the "While you focused"
    /// notice, the test notification, anything not recognised. Those keep
    /// their own rules and are left alone.
    struct Delivered: Equatable, Sendable {
        let identifier: String
        let kind: LabCard.SessionKind
        let sessionID: String
        /// A question's answers, when it offered them.
        let question: QuestionActions?

        init(identifier: String, kind: LabCard.SessionKind, sessionID: String, question: QuestionActions? = nil) {
            self.identifier = identifier
            self.kind = kind
            self.sessionID = sessionID
            self.question = question
        }

        init?(identifier: String, userInfo: [AnyHashable: Any]) {
            // The identifier must be the very card id of that session, so a
            // notification that doesn't fit is not guessed at.
            guard let sessionID = userInfo[NotificationRules.sessionKey] as? String,
                  let kind = LabCard.SessionKind.allCases.first(where: { identifier == $0.cardID(sessionID) })
            else { return nil }
            self.init(identifier: identifier, kind: kind, sessionID: sessionID,
                      question: kind == .needsInput ? QuestionActions(userInfo: userInfo) : nil)
        }
    }

    /// What to do with the notifications delivered before this launch, once a
    /// read has said how the sessions stand: the rule the running app uses to
    /// take a card's notification back, `SessionStanding.holds`.
    struct Sweep: Equatable, Sendable {
        /// Their reason is gone: a session that no longer waits, or no longer
        /// failed. They are taken back.
        var gone: [Delivered] = []
        /// Their reason stands and can still go: they stay, and are watched
        /// for the rest of the run, so they are taken back as any other.
        var adopted: [Delivered] = []
        // A finish is a record and no reason can take it back: it stays, and
        // nothing watches it. Neither does a notification that isn't a
        // session's (`Delivered`).
    }

    static func sweep(_ delivered: [Delivered], against standing: SessionStanding) -> Sweep {
        var sweep = Sweep()
        for note in delivered {
            if !standing.holds(note.kind, for: note.sessionID) {
                sweep.gone.append(note)
            } else if note.kind != .finished {
                sweep.adopted.append(note)
            }
        }
        return sweep
    }

    // MARK: Answering a question from its notification

    /// The answers a question's notification offers: a button for each
    /// choice and Reply… to type one. Only for a single question with one
    /// answer and at most four choices, and only when names are shown, since
    /// the buttons say what it asks. A plan or a permission request never
    /// gets an answer here: those are read on the card first.
    struct QuestionActions: Equatable, Sendable {
        static let maxChoices = 4
        static let replyID = "reply"
        static let choicePrefix = "answer."

        let toolID: String
        let question: String
        let choices: [String]

        /// The category: one per card, as the buttons are the card's own.
        static func categoryID(for cardID: String) -> String { "question." + cardID }

        static func choiceID(_ index: Int) -> String { choicePrefix + String(index) }

        // The notification's own copy of what it offered, read back when an
        // answer comes, checked again as the page's words are.
        private static let toolKey = "q.tool", questionKey = "q.text", choicesKey = "q.choices"

        var userInfo: [String: Any] {
            [Self.toolKey: toolID, Self.questionKey: question, Self.choicesKey: choices]
        }

        init(toolID: String, question: String, choices: [String]) {
            self.toolID = toolID
            self.question = question
            self.choices = choices
        }

        init?(userInfo: [AnyHashable: Any]) {
            guard let toolID = Pick.text(userInfo[Self.toolKey], limit: SessionProjection.Limit.toolID),
                  let question = Pick.text(userInfo[Self.questionKey], limit: SessionProjection.Limit.question),
                  let raw = userInfo[Self.choicesKey] as? [Any], raw.count <= Self.maxChoices else { return nil }
            var choices: [String] = []
            for value in raw {
                guard let label = Pick.text(value, limit: SessionProjection.Limit.label) else { return nil }
                choices.append(label)
            }
            self.init(toolID: toolID, question: question, choices: choices)
        }

        /// The question as the notification knows it: enough for the check
        /// beneath every answer, which matches its request id and its words.
        var ask: QuestionAsk {
            QuestionAsk(toolID: toolID, items: [SessionProjection.Question(
                question: question, header: "", multi: false,
                options: choices.map { SessionProjection.Option(label: $0, detail: nil) })])
        }

        /// What a button or Reply… answers, as a draft the window could show;
        /// nil for anything else, or an answer that couldn't be sent.
        func draft(actionID: String, typed: String?) -> ReplyDraft? {
            var draft = ReplyDraft(for: ask)
            if actionID.hasPrefix(Self.choicePrefix) {
                guard let index = Int(actionID.dropFirst(Self.choicePrefix.count)), choices.indices.contains(index) else {
                    return nil
                }
                draft.pick(index, in: 0, multi: false)
            } else if actionID == Self.replyID, let typed {
                draft.setOther(true, in: 0, multi: false)
                draft.other[0] = typed
            } else {
                return nil
            }
            return QuestionAnswers.request(ask, draft: draft) == nil ? nil : draft
        }
    }

    static func questionActions(for ask: QuestionAsk, settings: Settings) -> QuestionActions? {
        guard settings.showNames, ask.items.count == 1, let item = ask.items.first, !item.multi,
              item.options.count <= QuestionActions.maxChoices else { return nil }
        return QuestionActions(toolID: ask.toolID, question: item.question, choices: item.options.map(\.label))
    }

    /// A question card's notification once its question is read: the
    /// question as the words, and its answers.
    static func withQuestion(_ content: Content, ask: QuestionAsk?, settings: Settings) -> Content {
        guard let ask, let actions = questionActions(for: ask, settings: settings) else { return content }
        var asked = Content(id: content.id, title: content.title, body: actions.question, sound: content.sound,
                            sessionID: content.sessionID, link: content.link)
        asked.question = actions
        return asked
    }

    /// Nil when the card gets no notification: the setting is off, macOS
    /// hasn't allowed it, Capsid is quiet for a presentation, a finish nobody
    /// asked for or one that waits for a focus session, or a card that isn't
    /// about a session (a page's own notification, a saved file, a notice).
    /// The one notice that is about sessions is what finished during a focus
    /// session or while presenting, which comes as one when that ends, as its
    /// card does.
    static func content(for card: LabCard, settings: Settings) -> Content? {
        guard settings.enabled, settings.authorized, !settings.presenting else { return nil }
        if case .notice(let notice) = card { return heldFinishes(notice, cardID: card.id, settings: settings) }
        let session: SessionStatus
        let caption: String
        let hidden: (title: String, body: String)
        switch card {
        case .needsInput(let s):
            session = s
            caption = (s.waitingReason ?? .other).sentence
            hidden = ("A session needs you", caption)
        case .failed(let s):
            session = s
            caption = "Stopped with an error"
            hidden = ("A session stopped with an error", "")
        case .finished(let s):
            guard settings.finishes, !settings.holdingFinishes else { return nil }
            session = s
            caption = "Finished"
            hidden = ("A session finished", "")
        case .web, .saved, .notice:
            return nil
        }
        let words = settings.showNames
            ? (title: session.displayTitle, body: "\(caption) · \(session.projectName)")
            : hidden
        return Content(id: card.id, title: words.title, body: words.body, sound: !settings.benchPlaysSound,
                       sessionID: session.id, link: session.deepLink)
    }

    /// The "While you focused" or "While you presented" notice
    /// (`NoticeRules.held`), as a finish: only when finishes are asked for.
    /// One session opens it on a click; more than one only bring Bench forward.
    private static func heldFinishes(_ notice: LabNotice, cardID: String, settings: Settings) -> Content? {
        guard let reason = notice.heldFor, settings.finishes else { return nil }
        var session: SessionStatus?
        if case .openSession(let s) = notice.action { session = s }
        let words = settings.showNames
            ? (title: notice.title, body: "\(notice.caption) · \(notice.detail)")
            : (title: session == nil ? "Sessions finished \(reason.whileYou)" : "A session finished \(reason.whileYou)", body: "")
        return Content(id: cardID, title: words.title, body: words.body,
                       sound: !settings.benchPlaysSound, sessionID: session?.id, link: session?.deepLink)
    }
}

extension LabNotice {
    /// What finished during a focus session or while presenting, held until
    /// that ended.
    var isHeldFinishes: Bool { heldFor != nil }
}

private extension LabCard {
    /// A card whose notification is Bench's to take back: one about a
    /// session, or the held finishes.
    var hasNotification: Bool {
        if case .notice(let notice) = self { return notice.isHeldFinishes }
        return session != nil
    }
}

extension NotificationRules.Settings {
    /// What the user chose in Settings, as it is now.
    init(authorized: Bool, holdingFinishes: Bool, presenting: Bool = false, defaults: UserDefaults = .standard) {
        self.init(enabled: defaults.bool(forKey: SettingsKey.macNotifications),
                  authorized: authorized,
                  finishes: defaults.bool(forKey: SettingsKey.macNotifyFinishes),
                  showNames: defaults.bool(forKey: SettingsKey.macNotifyNames),
                  benchPlaysSound: defaults.bool(forKey: SettingsKey.soundOnNeedsInput),
                  holdingFinishes: holdingFinishes, presenting: presenting)
    }
}

// MARK: The system's center

/// What `MacNotifications` asks of the system's notification center, and
/// nothing else, so tests can stand in for it with a fake. The real one,
/// `live`, exists only in the real app: `UNUserNotificationCenter.current()`
/// crashes outside an app bundle, as in `swift test`, and a demo starts
/// nothing real. Its closures are thin on purpose: they only pass on. The
/// handlers macOS calls back are `@Sendable`, so they run wherever macOS calls
/// them and never ask to be on the main actor.
@MainActor
struct SystemCenter {
    var setDelegate: (any UNUserNotificationCenterDelegate) -> Void
    var authorization: () async -> UNAuthorizationStatus
    var requestAuthorization: () async -> (granted: Bool, failure: String?)
    /// What it still shows of Capsid's, as `NotificationRules.Delivered` reads
    /// them: only the notifications about a session.
    var delivered: () async -> [NotificationRules.Delivered]
    /// Called at once, not later: a notification withdrawn right after it is
    /// added must find it there. `completion` says how it ended: a failure's
    /// words, or nil.
    var add: (UNNotificationRequest, @escaping @Sendable (String?) -> Void) -> Void
    var removeDelivered: ([String]) -> Void
    var removeAllDelivered: () -> Void
    var setCategories: (Set<UNNotificationCategory>) -> Void

    /// Nil unless this is the real app (its bundle identifier) and no demo
    /// is running.
    static func live() -> SystemCenter? {
        guard Bundle.main.bundleIdentifier == MacNotifications.bundleID, Demo.mode == nil else { return nil }
        let center = UNUserNotificationCenter.current()
        return SystemCenter(
            setDelegate: { center.delegate = $0 },
            authorization: {
                await withCheckedContinuation { continuation in
                    center.getNotificationSettings { @Sendable in continuation.resume(returning: $0.authorizationStatus) }
                }
            },
            requestAuthorization: {
                await withCheckedContinuation { continuation in
                    center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, error in
                        continuation.resume(returning: (granted, error?.localizedDescription))
                    }
                }
            },
            delivered: {
                await withCheckedContinuation { continuation in
                    center.getDeliveredNotifications { @Sendable notifications in
                        continuation.resume(returning: notifications.compactMap {
                            NotificationRules.Delivered(identifier: $0.request.identifier,
                                                        userInfo: $0.request.content.userInfo)
                        })
                    }
                }
            },
            add: { request, completion in center.add(request) { @Sendable in completion($0?.localizedDescription) } },
            removeDelivered: { center.removeDeliveredNotifications(withIdentifiers: $0) },
            removeAllDelivered: { center.removeAllDeliveredNotifications() },
            setCategories: { center.setNotificationCategories($0) })
    }
}

// MARK: Posting

/// Posts what the rules say, takes a notification back when its card is dealt
/// with, and opens the session when one is clicked. It speaks to the system
/// only through `SystemCenter`, which is nil outside the real app.
@MainActor
final class MacNotifications: NSObject, ObservableObject {
    static let shared = MacNotifications(center: { SystemCenter.live() }, lab: .shared)

    /// What macOS lets Bench do, as far as it said last.
    enum Authorization: Equatable {
        case notDetermined, denied, allowed

        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .authorized, .provisional: self = .allowed
            case .denied: self = .denied
            default: self = .notDetermined
            }
        }
    }

    @Published private(set) var authorization = Authorization.notDetermined

    nonisolated static let bundleID = "local.sam.bench"
    /// The identifier of the test notification, which shows as a banner even
    /// with Bench in front: the Settings window it is sent from is Bench.
    nonisolated static let testID = "bench-test-notification"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")!

    private var started = false
    private var subscriptions: Set<AnyCancellable> = []
    /// Cards whose notification waits for macOS to say whether it may post,
    /// by id, the latest of each: one that goes meanwhile is not posted, and
    /// one that asks something new meanwhile posts as it is now.
    private var waiting: [String: LabCard] = [:]
    /// A question card's answers, by card id: the categories registered with
    /// macOS, one per card, dropped with the card.
    private var categories: [String: UNNotificationCategory] = [:]
    /// Notifications from before this launch that still tell the truth and
    /// can still stop doing so, by identifier (Notifications that outlived a
    /// quit). Taken back as any other, when their reason goes.
    private var adopted: [String: NotificationRules.Delivered] = [:]
    /// What the latest read that could be trusted says of the sessions.
    private var standing: SessionStanding?
    /// Whether the delivered notifications were checked yet this run: once,
    /// at the first read that could be trusted.
    private var swept = false
    /// The check under way or done, for tests to wait on.
    private(set) var sweeping: Task<Void, Never>?
    /// Bumped when every notification is cleared, so a check that was waiting
    /// on macOS when that happened does not bring any of them back.
    private var cleared = 0

    private let access: () -> SystemCenter?
    private let lab: LabModel
    private let defaults: UserDefaults

    /// The app uses `shared`; tests make their own, with a fake center, a
    /// model of their own and defaults of their own.
    init(center: @escaping () -> SystemCenter?, lab: LabModel, defaults: UserDefaults = .standard) {
        access = center
        self.lab = lab
        self.defaults = defaults
        super.init()
    }

    private var center: SystemCenter? { access() }

    /// Hooks the Lab model up, listens for clicks and reads what macOS allows.
    /// Called at launch, so a click on a notification from an earlier run is
    /// heard, and the status is known before Settings is opened.
    func start() {
        guard !started, let center else { return }
        started = true
        center.setDelegate(self)
        lab.cardRaised = { [weak self] in self?.raised($0) }
        lab.cardWithdrawn = { [weak self] in self?.withdraw($0) }
        lab.sessionsRead = { [weak self] in self?.sessionsRead($0) }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    /// Reads what macOS allows, now.
    func refresh() {
        guard let center else { return }
        Task { [weak self] in
            let status = await center.authorization()
            self?.authorization = Authorization(status)
        }
    }

    /// Asks macOS, which asks the user the first time only.
    func requestAuthorization() {
        guard let center else { return }
        Task { [weak self] in
            let answer = await center.requestAuthorization()
            if let failure = answer.failure {
                log.error("Notification permission request failed: \(failure, privacy: .public)")
            }
            log.info("Notification permission: \(answer.granted ? "granted" : "not granted", privacy: .public)")
            self?.refresh()
        }
    }

    // MARK: Cards

    /// A card came. macOS is asked what it allows each time, not trusted from
    /// the last time it was asked: the user may have changed it since in System
    /// Settings, while Bench was behind.
    func raised(_ card: LabCard) {
        guard let center, NotificationRules.content(for: card, settings: settings(authorized: true)) != nil
        else { return }
        waiting[card.id] = card
        let id = card.id
        Task { [weak self] in
            let status = await center.authorization()
            self?.post(id, status: status)
        }
    }

    private func post(_ id: String, status: UNAuthorizationStatus) {
        authorization = Authorization(status)
        // The card went, or was dealt with, while macOS answered; or an
        // earlier answer already posted its latest.
        guard let card = waiting.removeValue(forKey: id) else { return }
        let settings = self.settings(authorized: authorization == .allowed)
        guard let content = NotificationRules.content(for: card, settings: settings) else { return }
        // A question's answers come with it: its question is read first (or
        // taken from the card's read), a few seconds at most.
        if case .needsInput(let session) = card, session.waitingReason == .question, settings.showNames {
            Task {
                let ask = await QuestionReplier.shared.askForNotification(session.id)
                // Gone, or dealt with, meanwhile.
                guard self.lab.cards.contains(where: { $0.id == card.id }) else { return }
                self.add(NotificationRules.withQuestion(content, ask: ask, settings: settings))
            }
            return
        }
        add(content)
    }

    /// A card was opened, dismissed or stopped being true: its notification
    /// goes from Notification Center too.
    func withdraw(_ card: LabCard) {
        guard card.hasNotification else { return }
        takeBack([card.id])
    }

    /// Takes notifications out of Notification Center, with everything kept
    /// for them: a card waiting to post, an adopted notification, a question's
    /// answers.
    private func takeBack(_ ids: [String]) {
        var droppedAnswers = false
        for id in ids {
            waiting.removeValue(forKey: id)
            adopted.removeValue(forKey: id)
            if categories.removeValue(forKey: id) != nil { droppedAnswers = true }
        }
        center?.removeDelivered(ids)
        if droppedAnswers { center?.setCategories(Set(categories.values)) }
    }

    /// Clears every notification Bench has delivered: when names are turned
    /// off (those already shown named their sessions) or notifications are.
    func clearDelivered() {
        waiting.removeAll()
        adopted.removeAll()
        cleared += 1
        center?.removeAllDelivered()
        categories.removeAll()
        center?.setCategories([])
    }

    // MARK: Notifications that outlived a quit

    /// A read that worked and found sessions (`LabModel.sessionsRead`). The
    /// first of a run checks the notifications macOS still shows from an
    /// earlier run, which nothing in memory remembers; every later one takes
    /// back an adopted notification whose reason has gone since.
    func sessionsRead(_ read: SessionStanding) {
        standing = read
        guard center != nil else { return }
        if swept {
            retireAdopted()
        } else {
            swept = true
            sweeping = Task { [weak self] in
                guard let self else { return }
                await sweepDelivered()
            }
        }
    }

    /// Takes back the notifications delivered before this launch whose reason
    /// has gone, by the rule the running app uses (`NotificationRules.sweep`),
    /// and adopts the rest. Only with Mac notifications on and allowed; it
    /// sends nothing and says nothing new, so names stay as they were.
    private func sweepDelivered() async {
        guard let center, defaults.bool(forKey: SettingsKey.macNotifications) else { return }
        let clearedThen = cleared
        guard Authorization(await center.authorization()) == .allowed else { return }
        let delivered = await center.delivered()
        // Switched off, or cleared, while macOS answered: nothing to bring back.
        guard clearedThen == cleared, defaults.bool(forKey: SettingsKey.macNotifications), let standing else { return }
        let sweep = NotificationRules.sweep(delivered, against: standing)
        if !sweep.gone.isEmpty { takeBack(sweep.gone.map(\.identifier)) }
        let showNames = settings(authorized: true).showNames
        var answers = false
        for note in sweep.adopted {
            adopted[note.identifier] = note
            // A question's buttons are a category Capsid registers with macOS,
            // and each registration replaces the whole set. Nothing has
            // registered these in this run, so the next question posted would
            // leave them without: register the ones that still stand, as
            // `add` does, from the notification's own copy of them.
            if showNames, let question = note.question {
                categories[note.identifier] = Self.category(note.identifier, question)
                answers = true
            }
        }
        if answers { center.setCategories(Set(categories.values)) }
        log.info("Delivered notifications checked: \(sweep.gone.count, privacy: .public) taken back, \(sweep.adopted.count, privacy: .public) watched")
        // A read may have landed while macOS answered.
        retireAdopted()
    }

    /// Takes back the adopted notifications whose reason is gone. A plan held
    /// for an approval keeps its notification as it keeps its card.
    private func retireAdopted() {
        guard let standing else { return }
        let gone = adopted.values
            .filter { !standing.holds($0.kind, for: $0.sessionID) && !lab.holdsPlanCard($0.sessionID) }
            .map(\.identifier).sorted()
        if !gone.isEmpty { takeBack(gone) }
    }

    private func settings(authorized: Bool) -> NotificationRules.Settings {
        Self.settings(authorized: authorized, defaults: defaults)
    }

    /// What the rules decide by now; internal so a test can read what the app would pass.
    static func settings(authorized: Bool, defaults: UserDefaults = .standard) -> NotificationRules.Settings {
        NotificationRules.Settings(authorized: authorized, holdingFinishes: NidusFocus.shared.holding,
                                   presenting: PresentingMode.shared.isQuiet, defaults: defaults)
    }

    /// A notification with made-up words, to see how they look: no session
    /// of the user's, and it shows even with Bench in front.
    func sendTest() {
        let benchSounds = UserDefaults.standard.bool(forKey: SettingsKey.soundOnNeedsInput)
        // The panel's chime would come with a real one: Capsid's own question sound
        // (the Mac's Glass only where the bundle has none, as for any chime).
        if benchSounds { PanelSound.play(.question) }
        add(NotificationRules.Content(id: Self.testID, title: "Test notification",
                                      body: "This is how Capsid tells you a session needs you.",
                                      sound: !benchSounds, sessionID: nil, link: nil))
    }

    private func add(_ content: NotificationRules.Content) {
        guard let center else { return }
        let note = UNMutableNotificationContent()
        note.title = content.title
        note.body = content.body
        if content.sound { note.sound = .default }
        if let question = content.question {
            // Its own category, registered before it is posted, so the
            // buttons are there when it shows.
            let category = Self.category(content.id, question)
            categories[content.id] = category
            center.setCategories(Set(categories.values))
            note.categoryIdentifier = category.identifier
        }
        note.userInfo = NotificationRules.userInfo(for: content)
        // The card's id is the identifier, so a card that asks something new
        // replaces its notification rather than adding another.
        center.add(UNNotificationRequest(identifier: content.id, content: note, trigger: nil)) { failure in
            if let failure {
                log.error("Couldn't post a notification: \(failure, privacy: .public)")
            }
        }
    }

    /// A button for each choice, then Reply… to type an answer. Each asks for
    /// the Mac to be unlocked first, and none brings Capsid forward.
    private static func category(_ cardID: String, _ question: NotificationRules.QuestionActions) -> UNNotificationCategory {
        var actions: [UNNotificationAction] = question.choices.enumerated().map { index, label in
            UNNotificationAction(identifier: NotificationRules.QuestionActions.choiceID(index),
                                 title: label.count > 60 ? String(label.prefix(59)) + "…" : label,
                                 options: [.authenticationRequired])
        }
        actions.append(UNTextInputNotificationAction(identifier: NotificationRules.QuestionActions.replyID, title: "Reply…",
                                                     options: [.authenticationRequired], textInputButtonTitle: "Send",
                                                     textInputPlaceholder: "Your answer"))
        return UNNotificationCategory(identifier: NotificationRules.QuestionActions.categoryID(for: cardID),
                                      actions: actions, intentIdentifiers: [], options: [])
    }

    /// An answer chosen in a notification: sent as the window sends it, once
    /// the page is up and the session known (a launch from the notification
    /// waits a little for both). It waits for this answer's own send, never
    /// for other sessions'. Sent, or answered elsewhere meanwhile: nothing
    /// more. Not sent: the reply window with the answer still in it, or the
    /// session when even that can't be.
    fileprivate func answered(sessionID: String, link: URL?, ask: QuestionAsk, draft: ReplyDraft) async {
        let replier = QuestionReplier.shared
        for _ in 0..<40 where !(WebContainer.shared.status == .ready && LabModel.shared.knows(sessionID)) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        switch await replier.answerFromNotification(sessionID, ask: ask, draft: draft) {
        case .sent?, .closed?:
            break
        case nil:
            opened(sessionID: sessionID, link: link)
        default:
            ReplyWindowController.shared.show(sessionID)
        }
    }

    /// A click: Bench comes forward, on that session if there is one.
    fileprivate func opened(sessionID: String?, link: URL?) {
        if let sessionID, LabModel.shared.open(sessionID: sessionID) { return }
        if let link { Router.shared.open(link) } else { Router.shared.showWindow() }
    }
}

extension MacNotifications: UNUserNotificationCenterDelegate {
    /// With Bench in front the user is already here, so a notification goes to
    /// the list without a banner or a sound. The test is the exception.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isTest = notification.request.identifier == Self.testID
        completionHandler(isTest ? [.banner, .list, .sound] : [.list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let session = info[NotificationRules.sessionKey] as? String
        let link = (info[NotificationRules.linkKey] as? String).flatMap { URL(string: $0) }
        let isClick = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            && response.notification.request.identifier != Self.testID
        // A button or Reply…: the answer the notification offered, read back
        // from its own copy and checked as any answer is.
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        let question = NotificationRules.QuestionActions(userInfo: info)
        let draft = question?.draft(actionID: response.actionIdentifier, typed: typed)
        let ask = question?.ask
        completionHandler()
        if let session, let ask, let draft, PlanCheck.isFrameID(session) {
            Task { @MainActor in await self.answered(sessionID: session, link: link, ask: ask, draft: draft) }
            return
        }
        guard isClick else { return }
        Task { @MainActor in self.opened(sessionID: session, link: link) }
    }
}

extension LabModel {
    /// Opens a session by its id, from whatever Bench knows of it: a card, the
    /// lists, Recent. Says whether it knew it. Like `open(_ session:)`, it
    /// clears the session's cards and reminder.
    @discardableResult
    func open(sessionID id: String) -> Bool {
        guard let session = known(id) else { return false }
        open(session)
        return true
    }

    /// Whether Bench knows the session now, from a card or the lists.
    func knows(_ id: String) -> Bool { known(id) != nil }

    private func known(_ id: String) -> SessionStatus? {
        let known = cards.compactMap(\.session) + waiting + working + latest + recent.compactMap(\.session)
        return known.first(where: { $0.id == id })
    }
}

// MARK: Settings

/// Settings → Alerts → Mac notifications: what they are, whether macOS lets
/// Bench send them, and where to turn them off. A section of its own, placed
/// in the form by GeneralSettingsView.
struct MacNotificationsSection: View {
    @AppStorage(SettingsKey.macNotifications) private var enabled = false
    @AppStorage(SettingsKey.macNotifyFinishes) private var finishes = false
    @AppStorage(SettingsKey.macNotifyNames) private var names = true
    @ObservedObject private var notifications = MacNotifications.shared

    private var status: String {
        switch notifications.authorization {
        case .allowed: "Allowed"
        case .denied: "Not allowed: turned off in System Settings"
        case .notDetermined: enabled ? "Waiting for your answer to macOS's question" : "macOS will ask when you turn this on"
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                InfoTitle("Also send a Mac notification", info: MacNotificationsInfo.alsoSend)
                Text("As well as the card, so you see it in full screen or with the panel off.")
            }
            Toggle(isOn: $finishes) {
                Text("When a session finishes too")
                Text("Off, they come only when a session needs you or stops with an error.")
            }
            .disabled(!enabled)
            Toggle(isOn: $names) {
                InfoTitle("Show session and project names", info: MacNotificationsInfo.names)
                Text("Off, they read \u{201C}A session needs you\u{201D}, with no names and no answers.")
            }
            .disabled(!enabled)
            // Those already in Notification Center named their sessions, or
            // shouldn't linger once notifications are off.
            .onChange(of: names) { _, on in if !on { notifications.clearDelivered() } }
            .onChange(of: enabled) { _, on in if !on { notifications.clearDelivered() } }
            LabeledContent {
                if notifications.authorization == .denied {
                    Button("Open Notification Settings…") { NSWorkspace.shared.open(MacNotifications.settingsURL) }
                }
            } label: {
                Text("Permission")
                Text(status)
            }
            LabeledContent {
                Button("Send a Test Notification") { notifications.sendTest() }
                    .disabled(!enabled || notifications.authorization != .allowed)
            } label: {
                Text("See how it looks")
                Text("Made-up words: nothing from your sessions.")
            }
        } header: {
            Text("Mac notifications")
        }
        .onChange(of: enabled) { _, on in
            if on { notifications.requestAuthorization() }
        }
        .onAppear { notifications.refresh() }
    }
}

/// Settings → Alerts → Mac notifications: what the line under a switch leaves
/// out.
enum MacNotificationsInfo {
    static let alsoSend = """
        A notification in Notification Center as well as the card, so you see it in full screen or with the panel \
        off. macOS asks your permission the first time you turn this on.

        Notifications name the session and its project unless you turn names off. To stop them, turn this off, or \
        turn Capsid off in System Settings \u{2192} Notifications.
        """

    static let names = """
        On, each notification names the session and its project, and a question's notification also offers its \
        answers when it has a few choices or a typed answer (with questions shown on the card).

        Off, they read \u{201C}A session needs you\u{201D}, \u{201C}A session stopped with an error\u{201D} and \
        \u{201C}A session finished\u{201D}, with nothing of the session or its project in them, and offer no answers.
        """
}
