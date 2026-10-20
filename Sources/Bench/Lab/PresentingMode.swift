// PresentingMode.swift — keeping Capsid out of sight while the user presents
// (DESIGN.md, Quiet while presenting). Two things turn it on, and either is
// enough: a macOS Focus that has Capsid's filter added to it
// (App/PresentingFocusFilter.swift), and "Quiet While Presenting" in the app
// menu and the Dock menu. While it is on the panel is not shown, "Finished"
// cards wait, and no sound or Mac notification is made.
//
// This file is the state and nothing else. The panel, `LabModel` and the
// notifier each ask it through a closure of their own (as `LabModel.holdsFinishes`
// asks `NidusFocus`), so the rules are tested without a Focus or a window.
import AppKit
import Combine

@MainActor
final class PresentingMode: ObservableObject {
    static let shared = PresentingMode()

    /// A Focus with Capsid's filter added to it is on, as the system last said.
    /// Never set in a demo.
    @Published private(set) var focusFilterOn = false
    /// "Quiet While Presenting" in the app menu or the Dock menu. In memory
    /// only: a quit turns it off, so Capsid never comes back from a launch
    /// silent without anyone having said so.
    @Published private(set) var manualOn = false
    /// Either one: Capsid keeps out of sight. Stored, not computed, and
    /// assigned before `changed` is told, so whoever listens reads the new value.
    @Published private(set) var isQuiet = false

    /// Told after `isQuiet` changes, with its new value. Not told when a
    /// source moves and the answer stays the same (a Focus ending while the
    /// switch is still on).
    var changed: (Bool) -> Void = { _ in }

    /// The system has told Capsid what a Focus filter says, so the one look
    /// at launch (`catchUp`) can only be older news.
    private var heardFilter = false

    /// The app uses `shared`; tests make their own.
    init() {}

    /// The Focus filter ran: `quiet` is its parameter, on for a Focus that has
    /// been set to keep Capsid quiet and off (its default) when that Focus
    /// ends. Called from the intent's `perform()`.
    func setFocusFilter(_ quiet: Bool) {
        heardFilter = true
        apply(quiet)
    }

    /// What the system says the Focus filter is right now, read once at launch:
    /// the filter runs when a Focus turns on or off, which a Focus already on
    /// when Capsid started did before it was there to hear. Nil is no answer
    /// (none configured), which is off. Ignored if the filter has run since,
    /// which is newer.
    func catchUp(_ quiet: Bool?) {
        guard !heardFilter else { return }
        apply(quiet ?? false)
    }

    private func apply(_ quiet: Bool) {
        guard quiet != focusFilterOn else { return }
        focusFilterOn = quiet
        settle()
    }

    /// The menu items' switch: the way to be quiet when no Focus is set up.
    func setManual(_ on: Bool) {
        guard on != manualOn else { return }
        manualOn = on
        settle()
    }

    func toggleManual() { setManual(!manualOn) }

    private func settle() {
        let quiet = focusFilterOn || manualOn
        guard quiet != isQuiet else { return }
        isQuiet = quiet
        changed(quiet)
    }
}

/// The two menu items, the app menu's and the Dock menu's. The app menu's is
/// a SwiftUI toggle (BenchApp.swift); the Dock menu is AppKit, so this one is
/// an `NSMenuItem`.
@MainActor
final class PresentingMenu: NSObject {
    static let shared = PresentingMenu()
    static let title = "Quiet While Presenting"

    /// The Dock menu's item: checked while the switch is on, and saying so
    /// when a Focus is what keeps Capsid quiet. Off in a demo, which starts no
    /// part of this.
    func item(mode: PresentingMode = .shared, inDemo: Bool = Demo.mode != nil) -> NSMenuItem {
        let item = NSMenuItem(title: Self.title, action: #selector(toggle(_:)), keyEquivalent: "")
        item.target = self
        item.state = mode.manualOn ? .on : .off
        if mode.focusFilterOn { item.subtitle = "A Focus is keeping Capsid quiet" }
        item.isEnabled = !inDemo
        return item
    }

    @objc private func toggle(_ item: NSMenuItem) {
        PresentingMode.shared.toggleManual()
    }
}
