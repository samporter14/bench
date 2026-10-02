// LabPanelController.swift — the floating window (DESIGN.md, Lab, "The
// panel"): a non-activating panel in the bottom-right corner of the menu-bar
// screen, there only while something works or a card is up. While idle it
// does not exist at all.
import AppKit
import Combine
import SwiftUI

/// Never key and never main: it floats over other apps and must not take
/// focus from whatever the user is typing in.
private final class LabPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a click land on the first try, without activating Bench, and tells
/// the panel view when the pointer is over it.
private final class LabHostingView: NSHostingView<LabPanelView> {
    var onHover: (Bool) -> Void = { _ in }
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // Always active: the panel is in an app that is not in front.
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
}

@MainActor
final class LabPanelController {
    static let shared = LabPanelController()
    private init() {}

    private let model = LabModel.shared
    private let hover = PanelHover()
    private var subscriptions = Set<AnyCancellable>()
    private var panel: LabPanel?
    /// Whether the content has reported its size since the panel came up.
    private var fitted = false
    private var shrinking: Task<Void, Never>?
    private var hiding: Task<Void, Never>?

    /// Until the content reports its size, which it does in its first layout:
    /// wide as the widest card at the chosen size, tall enough for the
    /// tallest, with its margin.
    private var provisionalSize: CGSize {
        let wider = max(0, SceneSettings.shared.size.points - Theme.sceneSize)
        return CGSize(width: 360 + wider + 2 * LabPanelView.margin, height: 240)
    }

    /// The settings that decide whether the panel may show: the working
    /// specimen and the cards are separate choices since 0.2.0.
    private struct Preferences: Equatable {
        let showPanel: Bool
        let showCards: Bool
        let whileFront: Bool

        static func current() -> Preferences {
            let defaults = UserDefaults.standard
            return Preferences(showPanel: defaults.bool(forKey: SettingsKey.showPanel),
                               showCards: defaults.bool(forKey: SettingsKey.showCards),
                               whileFront: defaults.bool(forKey: SettingsKey.panelWhileFront))
        }
    }

    /// Starts observing; the panel comes and goes with the model and the settings.
    func start() {
        guard subscriptions.isEmpty else { return }
        let center = NotificationCenter.default

        let content = Publishers.CombineLatest3(model.$working, model.$cards, model.$workingHidden)
            .map { working, cards, hidden in (cards: !cards.isEmpty, working: !working.isEmpty && !hidden) }
        // Any change to any default posts this, from any thread; the map is cheap.
        let preferences = center.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { _ in Preferences.current() }
            .prepend(Preferences.current())
        let active = Publishers.Merge(
            center.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in true },
            center.publisher(for: NSApplication.didResignActiveNotification).map { _ in false })
            .prepend(NSApp.isActive)

        Publishers.CombineLatest3(content, preferences, active)
            .map { content, preferences, active in
                let has = (preferences.showCards && content.cards) || (preferences.showPanel && content.working)
                return has && (preferences.whileFront || !active)
            }
            .removeDuplicates()
            // @Published publishes as a value is about to change, not after.
            // A panel built inside that call would read the model's old state
            // and never hear of the change that caused it.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                if visible { self?.present() } else { self?.dismiss() }
            }
            .store(in: &subscriptions)

        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel else { return }
                self.place(panel.frame.size)
            }
            .store(in: &subscriptions)
    }

    // MARK: Showing and hiding

    private func present() {
        hiding?.cancel()
        hiding = nil
        if let panel {
            // Still fading out, or already up.
            fade(panel, to: 1)
            return
        }
        // The report comes from inside SwiftUI's own layout pass, so the
        // window is resized on the next turn rather than under it.
        let view = LabPanelView(model: model, hover: hover) { [weak self] size in
            Task { self?.fit(size) }
        }
        let hosting = LabHostingView(rootView: view)
        // The window follows the content's size, never the other way round.
        hosting.sizingOptions = []
        hosting.onHover = { [hover] inside in hover.isInside = inside }

        let panel = LabPanel(contentRect: NSRect(origin: .zero, size: provisionalSize),
                             styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass carries its own shadow.
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        fitted = false

        place(panel.frame.size)
        panel.alphaValue = 0
        // Not orderFront: a non-activating panel of an app that is not in
        // front is not reliably shown by it.
        panel.orderFrontRegardless()
        fade(panel, to: 1)
    }

    /// Fades out, then takes the window away entirely, unless the panel was
    /// wanted again meanwhile: `present()` cancels the pending removal.
    private func dismiss() {
        guard let panel else { return }
        fade(panel, to: 0)
        hiding = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.shrinking?.cancel()
            self.shrinking = nil
            self.hover.isInside = false
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
        }
    }

    private func fade(_ panel: NSPanel, to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = alpha
        }
    }

    // MARK: Size and position

    /// The content's spring and the window's frame must not fight, so the
    /// content animates alone, anchored bottom-right in the window. The
    /// window grows first, so the growing content has room, and shrinks after
    /// the spring has settled, so the shrinking content is not clipped.
    private func fit(_ wanted: CGSize) {
        guard let panel else { return }
        shrinking?.cancel()
        shrinking = nil
        let size = CGSize(width: wanted.width.rounded(.up), height: wanted.height.rounded(.up))
        guard fitted else {
            fitted = true
            place(size)
            return
        }
        let current = panel.frame.size
        let room = CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
        if room != current { place(room) }
        if room != size {
            let settle: Duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .zero : .milliseconds(450)
            shrinking = Task { [weak self] in
                try? await Task.sleep(for: settle)
                guard !Task.isCancelled else { return }
                self?.place(size)
            }
        }
    }

    /// Bottom-right of the menu-bar screen's visible frame, with the glass
    /// (not the clear margin round it) `Theme.panelInset` from the corner.
    private func place(_ size: CGSize) {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let margin = LabPanelView.margin
        let origin = CGPoint(x: area.maxX - Theme.panelInset + margin - size.width,
                             y: area.minY + Theme.panelInset - margin)
        let frame = NSRect(origin: origin, size: size)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}
