// MenuBarHome.swift — Capsid's menu bar item (DESIGN.md, Menu bar home; it was
// the menu bar specimen, Lab/MenuBarSpecimen.swift, until 1.0). It is there
// whenever Settings → General's "Show Capsid in the menu bar" is on, which it
// is unless turned off: a small quiet Capsid glyph, and beside it the count of
// what needs you when something does. While a session works it plays the
// specimen instead, but only when the older switch (Settings → Panel, off by
// default) is on. A click opens the home popover (CompanionPanel.swift).
//
// The item draws a count and a glyph and names nothing, so Quiet while
// presenting leaves it. Its ink follows the menu bar, which follows the
// wallpaper, not Capsid's Ivory or Slate. It holds still with the other
// specimens (Holding still).
import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarHome: NSObject {
    static let shared = MenuBarHome()

    private var item: NSStatusItem?
    private var hosting: NSHostingView<MenuBarItemView>?
    private var subscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?
    private var face = MenuBarFace.hidden
    private var started = false
    private var inDemo = false
    /// The older switch as the last look saw it, for "turning it on turns this on too".
    private var specimenWas = false

    /// What the item shows now, for tests and Diagnostics.
    var currentFace: MenuBarFace { face }

    /// Starts watching what decides the item. A demo has no item unless it is asked for with
    /// `-showMenuBarSpecimen YES`, and writes no setting.
    func start(inDemo: Bool = Demo.mode != nil) {
        guard !started else { return }
        let defaults = UserDefaults.standard
        if !inDemo { CompanionSettings.register(defaults) }
        if inDemo && !CompanionSettings.specimenIsOn(defaults) { return }
        started = true
        self.inDemo = inDemo
        specimenWas = CompanionSettings.specimenIsOn(defaults)
        let model = LabModel.shared
        let changes: [AnyPublisher<Void, Never>] = [
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            model.$working.map { _ in () }.eraseToAnyPublisher(),
            model.$waiting.map { _ in () }.eraseToAnyPublisher(),
            model.$cards.map { _ in () }.eraseToAnyPublisher(),
            model.$snoozed.map { _ in () }.eraseToAnyPublisher(),
            UsagePauseModel.shared.$held.map { _ in () }.eraseToAnyPublisher(),
        ]
        // Each is told before its value lands: look on the next turn.
        Publishers.MergeMany(changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.look() } }
            .store(in: &subscriptions)
        look()
    }

    /// What the face is, from the sessions and the two switches now.
    static func face(defaults: UserDefaults = .standard, model: LabModel = .shared,
                     pauses: UsagePauseModel = .shared, homeOn: Bool? = nil) -> MenuBarFace {
        let working = model.working
        return MenuBarFace.of(homeOn: homeOn ?? CompanionSettings.isOn(defaults),
                              specimenOn: CompanionSettings.specimenIsOn(defaults),
                              working: working.count, allPaused: !working.isEmpty && pauses.holdsAll(working),
                              needs: CompanionSections.needsCount(NeedsYou(model: model)))
    }

    private func look() {
        let defaults = UserDefaults.standard
        // The older switch just went on: this one follows it on.
        let specimen = CompanionSettings.specimenIsOn(defaults)
        let home = CompanionSettings.homeAfter(specimenWas: specimenWas, specimenNow: specimen, home: CompanionSettings.isOn(defaults))
        specimenWas = specimen
        if !inDemo, home != CompanionSettings.isOn(defaults) { defaults.set(home, forKey: CompanionSettings.key) }
        apply(Self.face(defaults: defaults, homeOn: home))
    }

    private func apply(_ next: MenuBarFace) {
        // The first look is the launch; what follows is a change.
        let launching = !looked
        looked = true
        guard next != face else { return }
        let wasVisible = face.visible
        face = next
        guard next.visible else {
            CompanionPanelController.shared.close()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            hosting = nil
            appearanceObservation = nil
            return
        }
        // Turned on by the user in this run: the item shows, even if an earlier run's item was taken
        // off the menu bar by hand. At launch that choice stands.
        let item = item ?? makeItem(showing: !launching && !wasVisible)
        if item.length != next.width { item.length = next.width }
        hosting?.frame = NSRect(x: 0, y: 0, width: next.width, height: NSStatusBar.system.thickness)
        if let button = item.button {
            hosting?.rootView = MenuBarItemView(face: next, dark: Self.isDark(button))
            button.setAccessibilityLabel(next.accessibilityLabel)
            button.toolTip = CompanionText.name
        }
    }

    /// The first look has been made.
    private var looked = false

    private func makeItem(showing: Bool) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: face.width)
        // The place the user gives it is kept. A demo shares the real app's settings: it keeps none.
        if !inDemo { item.autosaveName = "capsid-home" }
        if showing { item.isVisible = true }
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel(face.accessibilityLabel)
            let hosting = NSHostingView(rootView: MenuBarItemView(face: face, dark: Self.isDark(button)))
            hosting.frame = NSRect(x: 0, y: 0, width: face.width, height: NSStatusBar.system.thickness)
            button.addSubview(hosting)
            self.hosting = hosting
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] button, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hosting?.rootView = MenuBarItemView(face: self.face, dark: Self.isDark(button))
                }
            }
        }
        self.item = item
        return item
    }

    private static func isDark(_ view: NSView) -> Bool {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        CompanionPanelController.shared.toggle(from: button)
    }
}
