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
    static let showPanel = "showLabPanel"
    static let soundOnNeedsInput = "soundOnNeedsInput"
    static let panelWhileFront = "panelWhileFront"
    static let pageZoom = "pageZoom"
    /// Which Settings tab is showing: "general" or "scenes".
    static let settingsTab = "settingsTab"
    /// "system" (follow the Mac), "light" or "dark": see `BenchAppearance`.
    static let appearance = "appearance"

    static func register() {
        UserDefaults.standard.register(defaults: [
            showPanel: true,
            soundOnNeedsInput: true,
            panelWhileFront: true,
            pageZoom: 1.0,
            appearance: BenchAppearance.system.rawValue,
        ])
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
        case .light: "Light"
        case .dark: "Dark"
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
