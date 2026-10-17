// MacNotifications.swift — a Mac notification as well as the card, when the
// user asks for one (DESIGN.md, Mac notifications). What to send and in what
// words is `NotificationRules`: pure, and tested on made-up cards. Posting,
// withdrawing and listening for a click are `MacNotifications`, which is thin
// and which tests never use. The Settings section is at the bottom.
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
    /// hasn't allowed it, a finish nobody asked for or one that waits for a
    /// focus session, or a card that isn't about a session (a page's own
    /// notification, a saved file, a notice). The one notice that is about
    /// sessions is what finished during a focus session, which comes as one
    /// when the session ends, as its card does.
    static func content(for card: LabCard, settings: Settings) -> Content? {
        guard settings.enabled, settings.authorized else { return nil }
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

    /// The "While you focused" notice (`NoticeRules.held`), as a finish: only
    /// when finishes are asked for. One session opens it on a click; more than
    /// one only bring Bench forward.
    private static func heldFinishes(_ notice: LabNotice, cardID: String, settings: Settings) -> Content? {
        guard notice.isHeldFinishes, settings.finishes else { return nil }
        var session: SessionStatus?
        if case .openSession(let s) = notice.action { session = s }
        let words = settings.showNames
            ? (title: notice.title, body: "\(notice.caption) · \(notice.detail)")
            : (title: session == nil ? "Sessions finished while you focused" : "A session finished while you focused", body: "")
        return Content(id: cardID, title: words.title, body: words.body,
                       sound: !settings.benchPlaysSound, sessionID: session?.id, link: session?.deepLink)
    }
}

extension LabNotice {
    /// What finished during a focus session, held until it ended.
    var isHeldFinishes: Bool { id.hasPrefix("focus-held-") }
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
    init(authorized: Bool, holdingFinishes: Bool, defaults: UserDefaults = .standard) {
        self.init(enabled: defaults.bool(forKey: SettingsKey.macNotifications),
                  authorized: authorized,
                  finishes: defaults.bool(forKey: SettingsKey.macNotifyFinishes),
                  showNames: defaults.bool(forKey: SettingsKey.macNotifyNames),
                  benchPlaysSound: defaults.bool(forKey: SettingsKey.soundOnNeedsInput),
                  holdingFinishes: holdingFinishes)
    }
}

// MARK: Posting

/// Posts what the rules say, takes a notification back when its card is dealt
/// with, and opens the session when one is clicked. It touches
/// `UNUserNotificationCenter` only in the real app: that call crashes outside
/// an app bundle, as in `swift test`, and a demo starts nothing real.
@MainActor
final class MacNotifications: NSObject, ObservableObject {
    static let shared = MacNotifications()

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
    nonisolated private static let sessionKey = "session"
    nonisolated private static let linkKey = "link"
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

    private override init() { super.init() }

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == Self.bundleID && Demo.mode == nil ? .current() : nil
    }

    /// Hooks the Lab model up, listens for clicks and reads what macOS allows.
    /// Called at launch, so a click on a notification from an earlier run is
    /// heard, and the status is known before Settings is opened.
    func start() {
        guard !started, let center else { return }
        started = true
        center.delegate = self
        let lab = LabModel.shared
        lab.cardRaised = { [weak self] in self?.raised($0) }
        lab.cardWithdrawn = { [weak self] in self?.withdraw($0) }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    /// Reads what macOS allows, now.
    func refresh() {
        center?.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in self?.authorization = Authorization(status) }
        }
    }

    /// Asks macOS, which asks the user the first time only.
    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                log.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            }
            log.info("Notification permission: \(granted ? "granted" : "not granted", privacy: .public)")
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Cards

    /// A card came. macOS is asked what it allows each time, not trusted from
    /// the last time it was asked: the user may have changed it since in System
    /// Settings, while Bench was behind.
    func raised(_ card: LabCard) {
        guard let center, NotificationRules.content(for: card, settings: Self.settings(authorized: true)) != nil
        else { return }
        waiting[card.id] = card
        let id = card.id
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in self?.post(id, status: status) }
        }
    }

    private func post(_ id: String, status: UNAuthorizationStatus) {
        authorization = Authorization(status)
        // The card went, or was dealt with, while macOS answered; or an
        // earlier answer already posted its latest.
        guard let card = waiting.removeValue(forKey: id) else { return }
        let settings = Self.settings(authorized: authorization == .allowed)
        guard let content = NotificationRules.content(for: card, settings: settings) else { return }
        // A question's answers come with it: its question is read first (or
        // taken from the card's read), a few seconds at most.
        if case .needsInput(let session) = card, session.waitingReason == .question, settings.showNames {
            Task {
                let ask = await QuestionReplier.shared.askForNotification(session.id)
                // Gone, or dealt with, meanwhile.
                guard LabModel.shared.cards.contains(where: { $0.id == card.id }) else { return }
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
        waiting.removeValue(forKey: card.id)
        center?.removeDeliveredNotifications(withIdentifiers: [card.id])
        if categories.removeValue(forKey: card.id) != nil { center?.setNotificationCategories(Set(categories.values)) }
    }

    /// Clears every notification Bench has delivered: when names are turned
    /// off (those already shown named their sessions) or notifications are.
    func clearDelivered() {
        waiting.removeAll()
        center?.removeAllDeliveredNotifications()
        categories.removeAll()
        center?.setNotificationCategories([])
    }

    private static func settings(authorized: Bool) -> NotificationRules.Settings {
        NotificationRules.Settings(authorized: authorized, holdingFinishes: NidusFocus.shared.holding)
    }

    /// A notification with made-up words, to see how they look: no session
    /// of the user's, and it shows even with Bench in front.
    func sendTest() {
        let benchSounds = UserDefaults.standard.bool(forKey: SettingsKey.soundOnNeedsInput)
        // The panel's chime would come with a real one.
        if benchSounds { NSSound(named: "Glass")?.play() }
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
        var info: [String: String] = [:]
        if let id = content.sessionID { info[Self.sessionKey] = id }
        if let link = content.link { info[Self.linkKey] = link.absoluteString }
        var userInfo: [String: Any] = info
        if let question = content.question {
            // Its own category, registered before it is posted, so the
            // buttons are there when it shows.
            let category = Self.category(content.id, question)
            categories[content.id] = category
            center.setNotificationCategories(Set(categories.values))
            note.categoryIdentifier = category.identifier
            userInfo.merge(question.userInfo) { _, new in new }
        }
        note.userInfo = userInfo
        // The card's id is the identifier, so a card that asks something new
        // replaces its notification rather than adding another.
        center.add(UNNotificationRequest(identifier: content.id, content: note, trigger: nil)) { error in
            if let error {
                log.error("Couldn't post a notification: \(error.localizedDescription, privacy: .public)")
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
    /// waits a little for both). Anything but sent opens the reply window,
    /// with the answer still in it, or the session when even that can't be.
    fileprivate func answered(sessionID: String, link: URL?, ask: QuestionAsk, draft: ReplyDraft) async {
        let replier = QuestionReplier.shared
        for _ in 0..<40 where !(WebContainer.shared.status == .ready && LabModel.shared.knows(sessionID)) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        replier.answerFromNotification(sessionID, ask: ask, draft: draft)
        await replier.settled()
        switch replier.replies[sessionID]?.phase {
        case .sent?:
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
        let session = info[Self.sessionKey] as? String
        let link = (info[Self.linkKey] as? String).flatMap { URL(string: $0) }
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
                Text("Also send a Mac notification")
                Text("As well as the card: a notification in Notification Center, so you see it in full screen or with the panel off. macOS asks your permission the first time.")
            }
            Toggle(isOn: $finishes) {
                Text("When a session finishes too")
                Text("Off, they come only when a session needs you or stops with an error.")
            }
            .disabled(!enabled)
            Toggle(isOn: $names) {
                Text("Show session and project names")
                Text("On, a question's notification also offers its answers when it has a few choices or a typed answer (with questions shown on the card). Off, they read \u{201C}A session needs you\u{201D}, and so on, with no answers.")
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
        } footer: {
            Text("Notifications name the session and its project unless you turn names off. To stop them, turn off \u{201C}Also send a Mac notification\u{201D}, or turn Capsid off in System Settings \u{2192} Notifications.")
        }
        .onChange(of: enabled) { _, on in
            if on { notifications.requestAuthorization() }
        }
        .onAppear { notifications.refresh() }
    }
}
