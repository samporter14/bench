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
        guard let content = NotificationRules.content(for: card, settings: Self.settings(authorized: authorization == .allowed))
        else { return }
        add(content)
    }

    /// A card was opened, dismissed or stopped being true: its notification
    /// goes from Notification Center too.
    func withdraw(_ card: LabCard) {
        guard card.hasNotification else { return }
        waiting.removeValue(forKey: card.id)
        center?.removeDeliveredNotifications(withIdentifiers: [card.id])
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
                                      body: "This is how Bench tells you a session needs you.",
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
        note.userInfo = info
        // The card's id is the identifier, so a card that asks something new
        // replaces its notification rather than adding another.
        center.add(UNNotificationRequest(identifier: content.id, content: note, trigger: nil)) { error in
            if let error {
                log.error("Couldn't post a notification: \(error.localizedDescription, privacy: .public)")
            }
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
        completionHandler()
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
        let known = cards.compactMap(\.session) + waiting + working + latest + recent.compactMap(\.session)
        guard let session = known.first(where: { $0.id == id }) else { return false }
        open(session)
        return true
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
                Text("As well as the card: a notification in Notification Center, so you see it in full screen, with the panel off, and on your iPhone if it shows your Mac's notifications. macOS asks your permission the first time.")
            }
            Toggle(isOn: $finishes) {
                Text("When a session finishes too")
                Text("Off, they come only when a session needs you or stops with an error.")
            }
            .disabled(!enabled)
            Toggle(isOn: $names) {
                Text("Show session and project names")
                Text("Off, they read \u{201C}A session needs you\u{201D}, and so on.")
            }
            .disabled(!enabled)
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
            Text("Notifications name the session and its project unless you turn names off. To stop them, turn off \u{201C}Also send a Mac notification\u{201D}, or turn Bench off in System Settings \u{2192} Notifications.")
        }
        .onChange(of: enabled) { _, on in
            if on { notifications.requestAuthorization() }
        }
        .onAppear { notifications.refresh() }
    }
}
