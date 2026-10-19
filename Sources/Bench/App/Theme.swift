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
    /// Check GitHub once a day for a newer Bench. Off unless the user turns it
    /// on, in Settings or the welcome window: it's the one request Bench makes
    /// beyond this Mac that a click didn't ask for.
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
    /// Which Settings tab is showing: "general", "phone" or "scenes".
    static let settingsTab = "settingsTab"
    /// "system" (follow the Mac), "light" or "dark": see `BenchAppearance`.
    static let appearance = "appearance"
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
            checkForUpdates: false,
            remoteEnabled: false,
            panelScreen: "",
            pageZoom: 1.0,
            appearance: BenchAppearance.system.rawValue,
            remoteActions: true, // Phase 2 actions
            remoteBrowse: true, // Phase 3 browse
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
