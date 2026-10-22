// QuickStartPanel.swift — the window Quick Start lives in (DESIGN.md, Quick
// Start). A floating panel in the manner of Spotlight: borderless, ivory glass
// over a blur, centred on the screen the pointer is on, and it does not
// activate Capsid, so the app you were in stays in front and the main window
// doesn't come forward. It can take the keyboard (the field has it at once);
// Esc closes it, so does Cancel, a send that went, or switching to another
// app. The panel opens from a global key (GlobalHotKey.swift), File → Quick
// Start…, Finder's Services menu (QuickStartServices.swift), and Shortcuts.
import AppKit
import Combine
import SwiftUI

/// Takes the keyboard without activating the app.
final class QuickStartWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class QuickStartController: NSObject {
    static let shared = QuickStartController()

    /// The panel's model, made when it first opens.
    private(set) var model: QuickStartModel?
    private var window: QuickStartWindow?
    private var hosting: NSHostingView<QuickStartView>?
    private var flagsMonitor: Any?
    private var activation: NSObjectProtocol?
    private var changes: AnyCancellable?
    /// Where the panel's top edge sits: its height may change, its top doesn't.
    private var top: CGFloat?
    /// Dependencies a demo or a test gives instead of the live ones.
    private var dependencies: QuickStartModel.Dependencies?

    var isShowing: Bool { window?.isVisible == true }

    // MARK: Showing

    /// Opens the panel, on the screen the pointer is on. Already open, it keeps
    /// what was typed and takes the files and text it is given.
    func show(files: [URL] = [], text: String? = nil, dependencies given: QuickStartModel.Dependencies? = nil) {
        if let given { dependencies = given }
        let model = ensureModel()
        let wasShowing = isShowing
        model.open(files: files, text: text, keeping: wasShowing)
        let window = ensureWindow(model)
        if !wasShowing {
            top = nil
            relayout()
            place(window)
        }
        installWatchers()
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// The global key: closes the panel when it is up.
    func toggle() {
        if isShowing { close() } else { show() }
    }

    func close() {
        guard let window else { return }
        removeWatchers()
        window.orderOut(nil)
        model?.shiftHeld = false
    }

    // MARK: Building

    private func ensureModel() -> QuickStartModel {
        if let model { return model }
        let made = QuickStartModel(dependencies: dependencies ?? .live(close: { QuickStartController.shared.close() }))
        model = made
        return made
    }

    private func ensureWindow(_ model: QuickStartModel) -> QuickStartWindow {
        if let window { return window }
        let view = NSHostingView(rootView: QuickStartView(model: model))
        view.sizingOptions = [.intrinsicContentSize]
        let panel = QuickStartWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: QuickStartView.width, height: 440)),
                                     styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = Self.roundedMask(radius: QuickStartView.corner)
        view.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            view.topAnchor.constraint(equalTo: glass.topAnchor),
            view.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass
        panel.level = .floating
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
        panel.title = "Quick Start"
        panel.onCancel = { [weak self] in self?.model?.cancel() }
        window = panel
        hosting = view
        // The panel is as tall as what it shows, from a fixed top.
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.relayout() }
        }
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

    // MARK: Placing

    /// The screen under the pointer, else the main one.
    private static func activeScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Centred across the screen, its top a fifth of the way down.
    private func place(_ window: NSWindow) {
        let area = Self.activeScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        let x = area.midX - size.width / 2
        let topEdge = area.maxY - area.height * 0.2
        top = topEdge
        window.setFrame(NSRect(x: x, y: topEdge - size.height, width: size.width, height: size.height), display: true)
    }

    /// The height follows the content; the top stays.
    private func relayout() {
        guard let window, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let fit = hosting.fittingSize
        guard fit.height > 1, abs(fit.height - window.frame.height) > 0.5 || abs(fit.width - window.frame.width) > 0.5 else { return }
        let topEdge = top ?? window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: topEdge - fit.height, width: fit.width, height: fit.height), display: true)
        top = topEdge
    }

    // MARK: While it is up

    private func installWatchers() {
        if flagsMonitor == nil {
            // ⇧ changes what ↩ does, and the sentence and the button say so.
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.model?.shiftHeld = event.modifierFlags.contains(.shift)
                return event
            }
        }
        if activation == nil {
            // Switching to another app puts the panel away; it never took the
            // front, so this is the only way it learns you've moved on.
            activation = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated {
                    guard let self, self.model?.phase != .sending else { return }
                    self.close()
                }
            }
        }
    }

    private func removeWatchers() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
    }
}
