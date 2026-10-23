// CompanionPanel.swift — the window the home popover lives in (DESIGN.md, Menu
// bar home). Board 1 draws a glass sheet with 18-point corners under the menu
// bar item and no arrow, which a system popover cannot be, so this is a panel
// in the manner of Quick Start's: borderless, a blur behind a tint of ivory (or
// slate), it does not activate Capsid, and it can take the keyboard for the
// Quick Start field. It goes away on Esc, a click anywhere else, switching to
// another app, or the item's own click.
//
// Nothing of it is kept while it is closed: the window's content is let go
// and the model stops watching (`CompanionModel.close`).
import AppKit
import SwiftUI

/// Takes the keyboard without activating the app.
final class CompanionWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Where the panel goes, as plain geometry in screen coordinates (y grows upward).
enum CompanionPlacement {
    /// Between the menu bar's foot and the panel's top: the board has 6.
    static let gap: CGFloat = 6
    /// Kept clear of the screen's edges.
    static let margin: CGFloat = 12

    /// The room the panel has below the menu bar item, in points.
    static func maxHeight(anchor: CGRect, visible: CGRect) -> CGFloat {
        max(200, top(anchor: anchor, visible: visible) - visible.minY - margin)
    }

    private static func top(anchor: CGRect, visible: CGRect) -> CGFloat {
        min(anchor.minY, visible.maxY) - gap
    }

    /// Centred under the item, kept inside the visible area, its top `gap` below the menu bar, and no taller
    /// than the room below it.
    static func frame(size: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let height = min(size.height, maxHeight(anchor: anchor, visible: visible))
        let low = visible.minX + margin, high = visible.maxX - margin - size.width
        let x = high >= low ? min(max(anchor.midX - size.width / 2, low), high) : low
        return CGRect(x: x, y: top(anchor: anchor, visible: visible) - height, width: size.width, height: height)
    }
}

@MainActor
final class CompanionPanelController: NSObject {
    static let shared = CompanionPanelController()

    /// A demo's own model and buttons, in place of the app's.
    struct Stage {
        let model: CompanionModel
        let actions: CompanionActions
    }

    /// Set by `--demo menubar --step panel` only.
    var stage: Stage?

    private var model: CompanionModel?
    private var window: CompanionWindow?
    private var glass: NSVisualEffectView?
    private var hosting: NSHostingView<CompanionHomeView>?
    /// The menu bar item's window: a click on it is the item's own toggle, not "somewhere else".
    private weak var anchorWindow: NSWindow?
    private var anchor = CGRect.zero
    private var visible = CGRect.zero
    private var top: CGFloat?
    private var hasBeenKey = false
    private var monitors: [Any] = []
    private var observers: [any NSObjectProtocol] = []

    var isShowing: Bool { window?.isVisible == true }

    // MARK: Showing

    /// The item was clicked: opens the popover under it, or puts it away if it is up.
    func toggle(from button: NSStatusBarButton) {
        if isShowing {
            close()
        } else if let itemWindow = button.window {
            // A quiet demo's panel never takes the keyboard from what is in use.
            show(below: itemWindow.frame, itemWindow: itemWindow, takesKeyboard: !Demo.isQuiet)
        }
    }

    /// `takesKeyboard` is false for a quiet demo, which must not take the keyboard from whatever is in use.
    func show(below anchor: CGRect, itemWindow: NSWindow?, takesKeyboard: Bool = true) {
        guard !isShowing else { return }
        let screen = itemWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let area = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 870)
        self.anchor = anchor
        visible = area
        anchorWindow = itemWindow
        hasBeenKey = false
        // A reopening a moment after a close finds the old content still there to let go.
        releaseContent()
        let model = ensureModel()
        model.open()
        let window = ensureWindow()
        let room = CompanionPlacement.maxHeight(anchor: anchor, visible: area)
        let view = CompanionHomeView(model: model, actions: actions(), maxHeight: room, onFit: { [weak self] height in
            self?.fit(height)
        })
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        glass?.addSubview(hosting)
        if let glass {
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: glass.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
        }
        self.hosting = hosting
        hosting.layoutSubtreeIfNeeded()
        let size = CGSize(width: CompanionHomeView.width, height: max(120, hosting.fittingSize.height))
        let frame = CompanionPlacement.frame(size: size, anchor: anchor, visible: area)
        top = frame.maxY
        window.setFrame(frame, display: true)
        installWatchers(window)
        window.orderFrontRegardless()
        if takesKeyboard { window.makeKey() }
    }

    func close() {
        guard let window, window.isVisible || hosting != nil else { return }
        removeWatchers()
        window.orderOut(nil)
        model?.close()
        // The view that asked may be in the middle of its own button's action: let it finish first.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.releaseContent() }
        }
    }

    private func releaseContent() {
        guard !isShowing else { return }
        hosting?.removeFromSuperview()
        hosting = nil
    }

    // MARK: Building

    private func ensureModel() -> CompanionModel {
        if let stage {
            model = stage.model
            return stage.model
        }
        if let model { return model }
        let made = CompanionModel(sources: .live())
        model = made
        return made
    }

    private func ensureWindow() -> CompanionWindow {
        if let window { return window }
        let panel = CompanionWindow(contentRect: NSRect(x: 0, y: 0, width: CompanionHomeView.width, height: 400),
                                    styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                    backing: .buffered, defer: false)
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMask(radius: CompanionHomeView.corner)
        panel.contentView = blur
        // Above the menu bar's own windows, on whatever space (or full screen app) is up.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The edge is a hairline, never a shadow.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.animationBehavior = .utilityWindow
        panel.isExcludedFromWindowsMenu = true
        panel.title = CompanionText.name
        panel.setAccessibilityLabel(CompanionText.name)
        panel.onCancel = { [weak self] in self?.close() }
        window = panel
        glass = blur
        return panel
    }

    /// A rounded rectangle to mask the blur with.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// The height follows the content (rows come and go, a list is expanded); the top stays.
    private func fit(_ height: CGFloat) {
        guard let window, window.isVisible, height > 1 else { return }
        let size = CGSize(width: CompanionHomeView.width, height: height)
        let frame = CompanionPlacement.frame(size: size, anchor: anchor, visible: visible)
        guard abs(frame.height - window.frame.height) > 0.5 else { return }
        window.setFrame(CGRect(x: window.frame.minX, y: (top ?? frame.maxY) - frame.height, width: frame.width,
                               height: frame.height), display: true)
    }

    // MARK: What the buttons do

    private func actions() -> CompanionActions {
        if let stage { return stage.actions }
        let lab = LabModel.shared
        let cards = CardActions.shared
        return CompanionActions(
            perform: { cards.perform($0, for: $1) },
            later: { session in
                // The card is the thing put off: a session whose card isn't up has no Later.
                if let card = lab.cards.first(where: { $0.id == LabCard.SessionKind.needsInput.cardID(session.id) }) {
                    lab.remind(card, .fiveMinutes)
                }
            },
            open: { [weak self] session in
                lab.open(session)
                self?.close()
            },
            quickStart: { text in
                QuickStartController.shared.show(text: text.isEmpty ? nil : text)
            },
            showResults: { [weak self] in
                self?.close()
                ResultsWindowController.shared.show()
            },
            showSince: { [weak self] in
                self?.close()
                SinceYouLeftModel.shared.showSheet()
            },
            openCapsid: { [weak self] in
                self?.close()
                MainWindowController.shared.show()
            },
            openSettings: { [weak self] in
                self?.close()
                SettingsWindow.open()
            },
            toggleQuiet: { PresentingMode.shared.toggleManual() },
            close: { [weak self] in self?.close() })
    }

    // MARK: While it is up

    private func installWatchers(_ window: CompanionWindow) {
        removeWatchers()
        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // A click in another app.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: buttons, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            monitors.append(global)
        }
        // A click in one of Capsid's other windows. The item's own click is its toggle.
        if let local = NSEvent.addLocalMonitorForEvents(matching: buttons, handler: { [weak self] event in
            if let self, event.window !== self.window, event.window !== self.anchorWindow { self.close() }
            return event
        }) {
            monitors.append(local)
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hasBeenKey = true }
        })
        // Another window took the keyboard (Command-Tab, Mission Control, a window opened by a button).
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.hasBeenKey == true { self?.close() } }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.close() }
        })
    }

    private func removeWatchers() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
    }
}
