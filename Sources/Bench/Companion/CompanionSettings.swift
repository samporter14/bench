// CompanionSettings.swift — the switch for Capsid's menu bar item (DESIGN.md,
// Menu bar home). One key, on unless the user turns it off, in Settings →
// General. It decides whether the item is in the menu bar at all; the older
// switch (Settings → Panel, `SettingsKey.showMenuBarSpecimen`, off by default)
// keeps its meaning: while a session works the item plays the specimen instead
// of the quiet glyph.
//
// The key is kept here, apart from `SettingsKey`'s own file, and registered by
// `MenuBarHome.start()`.
import Foundation

extension SettingsKey {
    /// Capsid in the menu bar (since 1.0): a quiet glyph with a count of what
    /// needs you, and a click for the home popover. On by default.
    static let showMenuBarHome = "showCapsidInMenuBar"
}

enum CompanionSettings {
    static let key = SettingsKey.showMenuBarHome

    /// The default: on. An install from before 1.0 has no stored value, so it
    /// gets the item the first time it runs this build, whatever the older
    /// switch says.
    static func register(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [key: true])
    }

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        resolve(stored: defaults.object(forKey: key))
    }

    /// The older switch, "play the specimen in the menu bar".
    static func specimenIsOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: SettingsKey.showMenuBarSpecimen)
    }

    /// On unless the stored value says no: a bool, or the string a command-line
    /// `-showCapsidInMenuBar NO` gives. Nothing stored is on.
    static func resolve(stored: Any?) -> Bool {
        switch stored {
        case let flag as Bool: flag
        case let text as String: !["no", "false", "0"].contains(text.lowercased())
        default: true
        }
    }

    /// The item's switch after the older one moved: turning the specimen on
    /// turns the item on too, so a switch that says "play it in the menu bar"
    /// never leaves the menu bar empty. Turning it off, or any other change,
    /// leaves the item's switch as it was.
    static func homeAfter(specimenWas: Bool, specimenNow: Bool, home: Bool) -> Bool {
        specimenNow && !specimenWas ? true : home
    }
}
