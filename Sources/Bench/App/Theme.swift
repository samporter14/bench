// Theme.swift — Bench's palette and measures (DESIGN.md, Look). Everything
// else is the system's own: semantic colours, the system font, Liquid Glass.
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

    static func register() {
        UserDefaults.standard.register(defaults: [
            showPanel: true,
            soundOnNeedsInput: true,
            panelWhileFront: true,
            pageZoom: 1.0,
        ])
    }
}
