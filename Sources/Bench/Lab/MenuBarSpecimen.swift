// MenuBarSpecimen.swift — the working specimen in the menu bar (DESIGN.md,
// Menu bar specimen), off by default: it plays while a session works, shows
// the waiting glyph and a count while any waits, and opens the activity list.
// Hidden, not removed, while nothing works, so it keeps its place.
import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarSpecimen: NSObject {
    static let shared = MenuBarSpecimen()

    private var item: NSStatusItem?
    private var hosting: NSHostingView<MenuBarSpecimenView>?
    private var popover: NSPopover?
    private var subscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?

    func start() {
        guard subscriptions.isEmpty else { return }
        let model = LabModel.shared
        let enabled = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarSpecimen) }
            .prepend(UserDefaults.standard.bool(forKey: SettingsKey.showMenuBarSpecimen))
            .removeDuplicates()
        Publishers.CombineLatest3(enabled, model.$working, model.$waiting)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, working, waiting in
                self?.update(visible: enabled && (!working.isEmpty || !waiting.isEmpty), waiting: waiting.count)
            }
            .store(in: &subscriptions)
    }

    private func update(visible: Bool, waiting: Int) {
        guard visible || item != nil else { return }
        let item = item ?? makeItem()
        let width: CGFloat = waiting > 0 ? 34 : 24
        if item.length != width { item.length = width }
        hosting?.frame = NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
        if item.isVisible != visible { item.isVisible = visible }
        if !visible { popover?.performClose(nil) }
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: 24)
        item.autosaveName = "bench-specimen"
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel("Bench sessions")
            let hosting = NSHostingView(rootView: MenuBarSpecimenView(dark: Self.isDark(button)))
            hosting.frame = NSRect(x: 0, y: 0, width: 24, height: NSStatusBar.system.thickness)
            button.addSubview(hosting)
            self.hosting = hosting
            // The ink follows the menu bar, which follows the wallpaper, not
            // Bench's own Ivory or Slate.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] button, _ in
                MainActor.assumeIsolated { self?.hosting?.rootView = MenuBarSpecimenView(dark: Self.isDark(button)) }
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
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = popover ?? NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ActivityList { [weak popover] in
            popover?.performClose(nil)
        })
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

/// What sits in the menu bar: the specimen, or the waiting glyph and how many
/// wait. Ink is the menu bar's: white on a dark one, black on a light one.
struct MenuBarSpecimenView: View {
    let dark: Bool
    @ObservedObject private var model = LabModel.shared
    @ObservedObject private var settings = SceneSettings.shared

    private var ink: Color { dark ? .white : .black }

    var body: some View {
        HStack(spacing: 2) {
            if let waiting = model.waiting.first {
                PlayedLoop(glyph: (waiting.waitingReason ?? .other).glyph, tint: ink)
                    .frame(width: 16, height: 16)
                Text("\(model.waiting.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
            } else {
                WorkingGlyph(tint: ink, rotation: settings.rotation)
                    .frame(width: 17, height: 17)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
