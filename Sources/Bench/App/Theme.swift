// Theme.swift — Bench's palette and measures (DESIGN.md, Look). Everything
// else is the system's own: semantic colours, the system font, Liquid Glass.
import AppKit
import SwiftUI

enum Theme {
    /// The one accent: the primary action, the live dot, "needs you".
    /// (The shared scenes define the same value as `clay`.)
    static let clay = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
    static let slate = Color(red: 20 / 255, green: 20 / 255, blue: 19 / 255)
    static let ivory = Color(red: 240 / 255, green: 238 / 255, blue: 230 / 255)

    /// Clay for WORDS. The fill above is about 3:1 on ivory, too faint for
    /// small text, so anything read in clay (a card's heading, "6 need you",
    /// a low figure) uses Solanum's clay-text instead: #9C4221 on light
    /// grounds, #E4927A on dark ones. Fills, rings, bars, switches, the
    /// prominent buttons' tint and glyphs that only decorate stay `clay`.
    static let clayText = Color(nsColor: clayTextColor)

    /// `clayText` as a dynamic colour: it follows the appearance it is drawn
    /// in, so the Ivory and Slate setting (which sets the app's appearance)
    /// and the Specimens tab's own light/dark switch (the window's) both
    /// reach it with nothing passed down.
    static let clayTextColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? clayTextDark : clayTextLight
    }
    static let clayTextLight = NSColor(srgbRed: 0x9C / 255, green: 0x42 / 255, blue: 0x21 / 255, alpha: 1)
    static let clayTextDark = NSColor(srgbRed: 0xE4 / 255, green: 0x92 / 255, blue: 0x7A / 255, alpha: 1)

    /// The panel's glass shape.
    static let panelCorner: CGFloat = 26
    static let panelPadding: CGFloat = 16
    /// The scene well in the panel: about five times the Droppy pill.
    static let sceneSize: CGFloat = 88
    /// The scene in the toolbar capsule.
    static let capsuleSceneSize: CGFloat = 18
    /// The panel's inset from the screen's corner.
    static let panelInset: CGFloat = 20

    static let spring = Animation.spring(duration: 0.35, bounce: 0.15)
}

/// User settings (DESIGN.md, Settings), read with @AppStorage by the views
/// and with UserDefaults by controllers.
enum SettingsKey {
    /// The working specimen (the panel while a session works). Before 0.2.0
    /// it also turned the cards on and off; `showCards` does that now.
    static let showPanel = "showLabPanel"
    /// Cards when a session needs you, fails or finishes, and page
    /// notifications.
    static let showCards = "showLabCards"
    /// The working specimen in the menu bar too. Off by default.
    static let showMenuBarSpecimen = "showMenuBarSpecimen"
    /// A quiet line in the working panel naming the specimen that's playing,
    /// with its caption from the field guide. Off by default.
    static let showSpecimenCaption = "showSpecimenCaption"
    /// Plan and context cards.
    static let headsUpNotices = "headsUpNotices"
    /// The week in review, once a new week starts.
    static let weekInReview = "weekInReview"
    /// Hold "Finished" cards while a Nidus focus session runs.
    static let holdDuringFocus = "holdDuringNidusFocus"
    /// Share the focused Claude Science task's project and title with Nidus.
    /// Off until chosen in Settings → General.
    static let shareTaskWithNidus = "shareTaskWithNidus"
    static let soundOnNeedsInput = "soundOnNeedsInput"
    /// A plan's card shows its summary and an Approve button (since 0.3.4).
    /// Off, the card is Open and Later, and no plan is read.
    static let showPlansOnCard = "showPlansOnCard"
    /// A Mac notification as well as the card. Off by default: macOS asks
    /// permission when it is turned on.
    static let macNotifications = "macNotifications"
    /// Notifications for finishes too, not only for what needs you or failed.
    static let macNotifyFinishes = "macNotifyFinishes"
    /// The session and project names in a notification's words.
    static let macNotifyNames = "macNotifyNames"
    static let panelWhileFront = "panelWhileFront"
    /// Which corner of the screen the panel sits in: see `PanelCorner`.
    static let panelCorner = "panelCorner"
    /// Which screen the panel sits on, by its name; empty for the one with
    /// the menu bar. See `PanelScreen`.
    static let panelScreen = "panelScreen"
    static let pageZoom = "pageZoom"
    /// The session the main window was showing, as `<project id>/<session id>`
    /// (opaque ids, never a name), for the next launch to reopen
    /// (Web/LastSession.swift). Not registered: absent means none.
    static let lastSession = "lastSession"
    /// Check GitHub once a day for a newer Bench. On unless the user turns it
    /// off, in Settings or the welcome window (on by default since 0.9.7, so
    /// updates get seen): it's the one request Bench makes beyond this Mac that
    /// a click didn't ask for.
    static let checkForUpdates = "checkForUpdates"
    /// Capsid on your phone (since 0.4.0): the loopback listener and its
    /// Tailscale Serve mapping. Off unless the user turns it on in Settings
    /// → Phone: it is what lets the user's own devices reach Bench.
    static let remoteEnabled = "remoteEnabled"
    /// The listener's port, from 47280 to 47290, tried first next time.
    static let remotePort = "remotePort"
    /// The tailnet login Capsid on your phone was turned on with: Serve's
    /// `Tailscale-User-Login` must match it.
    static let remoteLogin = "remoteLogin"
    /// The welcome window has been shown (or was skipped for someone who used
    /// Bench before it existed).
    static let hasSeenWelcome = "hasSeenWelcome"
    /// The newest release whose What's New the user has seen (or that Capsid
    /// started on, for a fresh install): "1.1", major.minor, as the table in
    /// App/WhatsNew.swift is keyed. Absent means none. Never registered, and
    /// not one of the keys that make `WelcomeGate` take a Mac for a used one.
    static let whatsNewSeen = "whatsNewSeen"
    /// Which Settings tab is showing: "general", "phone" or "scenes".
    static let settingsTab = "settingsTab"
    /// "system" (follow the Mac), "light" or "dark": see `BenchAppearance`.
    static let appearance = "appearance"
    /// Which icon Capsid shows in the Dock while it runs, an `AppIconChoice`
    /// (since 0.9.5). Clay is the bundle's own.
    static let appIcon = "appIcon"
    // Phase 2 actions
    /// Paired devices may answer a question, approve a plan and send a
    /// message (Capsid on your phone, since 0.4.0). On by default; off, the
    /// action routes answer 403 and the phone offers Open on Mac only.
    static let remoteActions = "remoteActions"
    // Phase 3 browse
    /// Paired devices may browse every project, read whole conversations and
    /// see artifacts, and start a session (Capsid on your phone, since 0.4.0).
    /// On by default; off, those routes answer 403 and the phone shows Now only.
    static let remoteBrowse = "remoteBrowse"
    /// "Skip" on Settings → Phone's "Put Tailscale on your phone", for
    /// someone pairing a computer instead: that step counts as done. Off
    /// unless pressed.
    static let remotePhoneSkipped = "remotePhoneSkipped"
    /// Which limit the title bar's usage readout shows, a `TitleBarUsage`
    /// (since 0.9.1).
    static let titleBarUsage = "titleBarUsage"
    /// Where Keep puts results (since 1.0): a path, empty for
    /// `~/Documents/Kept` (`KeptSettings.root`). Not registered: absent
    /// means the default.
    static let keptRoot = "keptRoot"
    /// The collection last kept into, by project id (since 1.0): a
    /// settings-sized dictionary of opaque ids to folder names.
    static let keptCollections = "keptCollections"
    // 1.0, M6–M8
    /// The specimen that plays is matched to the session's title when one
    /// fits (Lab/SpecimenTopics.swift). On by default (the handoff's
    /// proposal; Sam's call).
    static let matchSpecimenToSession = "matchSpecimenToSession"
    /// Quick Start's global key (`GlobalHotKey`), a `GlobalHotKey.Choice`
    /// raw value: "none" turns it off.
    static let quickStartKey = "quickStartKey"
    /// The global key that opens Reply on the top card, a `GlobalHotKey.Choice`.
    static let replyKey = "replyKey"
    /// Shortcuts may start sessions and send messages without asking each
    /// time. Off by default; off, those intents ask for confirmation.
    static let shortcutsMayAct = "shortcutsMayAct"
    /// Quick Start's recipes, as JSON (`Recipe`): user-written and
    /// settings-sized. Not registered: absent means none.
    static let recipes = "recipes"
    // Ask Another Model (AskModel/)
    /// Ask another model: File → Ask Another Model…, the right-click items
    /// and the window, with the user's own key. Off unless turned on in
    /// Settings → General; off, none of it shows. The key itself is never a
    /// setting (`AnotherModelKey`).
    static let askAnotherModel = "askAnotherModel"
    /// The OpenAI-compatible address it asks, https only
    /// (`AnotherModelAddress.usual`).
    static let anotherModelAddress = "anotherModelAddress"
    /// The model chosen from the address's own list (`GET /models`), as
    /// that list names it. Not registered: absent means none chosen yet.
    static let anotherModelName = "anotherModelName"

    static func register() {
        let defaults = UserDefaults.standard
        // From 0.1.x: someone who had switched the whole panel off had the
        // cards off too, so they stay off rather than appearing after an
        // update.
        if defaults.object(forKey: showCards) == nil, let panel = defaults.object(forKey: showPanel) as? Bool {
            defaults.set(panel, forKey: showCards)
        }
        defaults.register(defaults: [
            showPanel: true,
            showCards: true,
            showMenuBarSpecimen: false,
            showSpecimenCaption: false,
            headsUpNotices: true,
            weekInReview: true,
            holdDuringFocus: true,
            shareTaskWithNidus: false,
            soundOnNeedsInput: true,
            showPlansOnCard: true,
            macNotifications: false,
            macNotifyFinishes: false,
            macNotifyNames: true,
            panelWhileFront: true,
            panelCorner: PanelCorner.bottomRight.rawValue,
            checkForUpdates: true,
            remoteEnabled: false,
            panelScreen: "",
            pageZoom: 1.0,
            appearance: BenchAppearance.system.rawValue,
            appIcon: AppIconChoice.standard.rawValue,
            remoteActions: true, // Phase 2 actions
            remoteBrowse: true, // Phase 3 browse
            titleBarUsage: TitleBarUsage.fiveHour.rawValue,
            matchSpecimenToSession: true,
            quickStartKey: "controlOptionCommandSpace",
            replyKey: "controlOptionCommandR",
            shortcutsMayAct: false,
            askAnotherModel: false,
            anotherModelAddress: AnotherModelAddress.usual,
        ])
    }
}

/// The corner of the menu-bar screen the specimens panel sits in.
enum PanelCorner: String, CaseIterable, Identifiable {
    case bottomRight, bottomLeft, topRight, topLeft
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        case .topRight: "Top right"
        case .topLeft: "Top left"
        }
    }

    var isTop: Bool { self == .topRight || self == .topLeft }
    var isLeft: Bool { self == .bottomLeft || self == .topLeft }

    /// Where the panel's content sits in its window, and grows from.
    var alignment: SwiftUI.Alignment {
        switch self {
        case .bottomRight: .bottomTrailing
        case .bottomLeft: .bottomLeading
        case .topRight: .topTrailing
        case .topLeft: .topLeading
        }
    }

    var anchor: UnitPoint {
        switch self {
        case .bottomRight: .bottomTrailing
        case .bottomLeft: .bottomLeading
        case .topRight: .topTrailing
        case .topLeft: .topLeading
        }
    }

    static var current: PanelCorner {
        UserDefaults.standard.string(forKey: SettingsKey.panelCorner).flatMap(PanelCorner.init(rawValue:)) ?? .bottomRight
    }
}

/// The screen the specimens panel sits on: the one with the menu bar, or one
/// chosen by name. A screen that isn't connected falls back to the menu bar's
/// until it is again. By name, not display ID, which can change when a screen
/// is unplugged and plugged back in.
enum PanelScreen {
    static var chosenName: String { UserDefaults.standard.string(forKey: SettingsKey.panelScreen) ?? "" }

    @MainActor
    static var current: NSScreen? {
        let name = chosenName
        return NSScreen.screens.first { !name.isEmpty && $0.localizedName == name } ?? NSScreen.screens.first
    }
}

/// Light or dark for the whole app, or whatever the Mac is set to. It is the
/// app's appearance, so the window, Settings, the scenes panel and the web
/// view all follow; the Claude Science page follows too while its own theme
/// is set to System.
enum BenchAppearance: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "Match Mac"
        case .light: "Ivory"
        case .dark: "Slate"
        }
    }

    /// Reads the setting and applies it. Called at launch and when it changes.
    @MainActor
    static func apply() {
        let chosen = UserDefaults.standard.string(forKey: SettingsKey.appearance).flatMap(Self.init) ?? .system
        switch chosen {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
