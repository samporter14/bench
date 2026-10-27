// CompareWindow.swift — the Compare window's shell (DESIGN.md, Compare): one
// native window, reused (a new Compare replaces its pair), drawn on the 1.0
// windows' surfaces like the Shelf's; the View menu's Compare commands, there
// only while the window is key; and the Shelf's way in, Compare in a card's menu
// while exactly two items are picked (dimmed, with the reason, when the two
// aren't two pictures or two text files).
import AppKit
import Combine
import SwiftUI

@MainActor
final class CompareWindowController: NSObject, NSWindowDelegate {
    static let shared = CompareWindowController()
    /// Two pictures side by side with room to see them; the least that still shows two panes and the row of pills.
    static let size = NSSize(width: 1080, height: 760)
    static let minimum = NSSize(width: 720, height: 480)
    static let frameName = "CapsidCompare"
    private var window: NSWindow?
    private(set) var model: CompareModel?

    /// Compares `a` (left) with `b` (right) in the one Compare window, opening it the first time.
    func show(_ a: ShelfItem, _ b: ShelfItem, shelf: Shelf = .shared) {
        if window == nil {
            let index = shelf.index
            let model = CompareModel(reader: .live(disk: index.disk),
                                     changes: index.$results.dropFirst().map { _ in () }.eraseToAnyPublisher())
            let hosting = NSHostingController(rootView: CompareView(model: model).compareWindowChrome(model))
            hosting.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.contentViewController = hosting
            // The Shelf's arrangement (KeptWindow.swift): the title in the toolbar, the page's colour under a
            // transparent title bar.
            window.title = "Compare"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = Solanum.pageColor
            window.setContentSize(Self.size)
            window.contentMinSize = Self.minimum
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.toolbarStyle = .unified
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            window.setFrameAutosaveName(Self.frameName)
            self.window = window
            self.model = model
        }
        model?.compare(a, b)
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window?.orderFrontRegardless() } else { window?.makeKeyAndOrderFront(nil) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        CompareCommands.shared.set(model)
    }

    func windowDidResignKey(_ notification: Notification) {
        if CompareCommands.shared.model === model { CompareCommands.shared.set(nil) }
    }

    /// Closed: nothing read for the pair may arrive, and its pictures are let go.
    func windowWillClose(_ notification: Notification) {
        model?.close()
        CompareCommands.shared.set(nil)
    }
}

/// The View menu's Compare commands reach the key Compare window's model through this.
@MainActor
final class CompareCommands: ObservableObject {
    static let shared = CompareCommands()
    @Published private(set) var model: CompareModel?
    private var forwarding: AnyCancellable?

    /// The menu follows the model's own changes (Wipe offered, a change reached) while its window is key.
    func set(_ model: CompareModel?) {
        guard model !== self.model else { return }
        self.model = model
        forwarding = model?.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }
}

/// View → the Compare commands, while a Compare window is key, and only the ones its pair has: Swap Sides (⇧⌘X); for
/// pictures Fit (⌘9), Link Zoom and, when the two are the same size, Wipe (⌃⌘W); for text, Previous and Next Change
/// (⌃⌘↑, ⌃⌘↓). None of the keys is another menu item's.
struct CompareMenu: View {
    @ObservedObject var commands: CompareCommands

    var body: some View {
        if let model = commands.model, model.kind != nil {
            Divider()
            Button("Swap Sides") { model.swap() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            if model.kind == .images {
                Button("Fit") { model.fit() }
                    .keyboardShortcut("9", modifiers: .command)
                if !model.wiping {
                    Toggle("Link Zoom", isOn: Binding(get: { model.linked }, set: { model.setLinked($0) }))
                }
                if model.canWipe {
                    Toggle("Wipe", isOn: Binding(get: { model.wiping }, set: { model.setWiping($0) }))
                        .keyboardShortcut("w", modifiers: [.command, .control])
                }
            } else {
                Button("Previous Change") { model.previousChange() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                    .disabled(!model.canGoToPreviousChange)
                Button("Next Change") { model.nextChange() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                    .disabled(!model.canGoToNextChange)
            }
        }
    }
}

// MARK: The Shelf's way in

extension ShelfModel {
    /// The two picked items in the Shelf's order, the first the left side: nil unless exactly two are picked and shown.
    var comparePair: (ShelfItem, ShelfItem)? {
        let items = pickedItems
        guard pickCount == 2, items.count == 2 else { return nil }
        return (items[0], items[1])
    }
}

/// Compare in a card's menu: only on a card among exactly two picks. Two pictures or two text files open the Compare
/// window on them; any other pair has the item dimmed with its reason, and opens nothing.
struct ShelfCompareItem: View {
    @ObservedObject var model: ShelfModel
    let item: ShelfItem

    var body: some View {
        if model.isPicked(item.id), let pair = model.comparePair {
            if case .comparable = CompareRules.pairing(pair.0, pair.1) {
                Button(CompareRules.menuTitle) { CompareWindowController.shared.show(pair.0, pair.1, shelf: model.shelf) }
            } else {
                Button(CompareRules.unavailableTitle) {}
                    .disabled(true)
                    .help(CompareRules.unavailableHelp)
            }
        }
    }
}
