// CompareWindow.swift — the Compare window's shell (DESIGN.md, Compare): one
// native window, reused (a new Compare replaces its pair), drawn on the 1.0
// windows' surfaces like the Shelf's; the View menu's Compare commands, there
// only while the window is key; and the Shelf's ways in: Compare With in the
// menu of a card Compare reads (the cards shown that pair with it, or dimmed
// with the reason when none does), Compare in a card's menu while exactly two
// are picked and it is one of them (dimmed, with the reason, when the two aren't
// two pictures or two text files), and the title bar's Compare pill for two
// picks that pair.
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

// MARK: The Shelf's ways in

extension ShelfModel {
    /// The two picked items in the Shelf's order, the first the left side: nil unless exactly two are picked and shown.
    var comparePair: (ShelfItem, ShelfItem)? {
        guard pickCount == 2 else { return nil }
        let items = pickedItems
        guard items.count == 2 else { return nil }
        return (items[0], items[1])
    }

    /// The pair the title bar's Compare pill opens: the two picks, in the Shelf's order, only when they pair.
    var comparablePair: (ShelfItem, ShelfItem)? {
        guard let pair = comparePair, case .comparable = CompareRules.pairing(pair.0, pair.1) else { return nil }
        return pair
    }

    /// The Compare pill beside Export as PDF…: exactly two picked, and two Compare reads.
    var showsComparePill: Bool { comparablePair != nil }

    /// What `item`'s card menu offers for Compare (`CompareRules.offer`): the picks only count when exactly two are
    /// picked and this card is one of them; else Compare With, from the cards shown now.
    func compareOffer(for item: ShelfItem) -> CompareRules.Offer {
        CompareRules.offer(for: item, pickedPair: isPicked(item.id) && pickCount == 2 ? comparePair : nil,
                           shown: shown, filtered: isFiltered)
    }
}

/// Compare in a card's menu, after Export … as PDF…. A card Compare reads has Compare With ▸, the cards shown that pair
/// with it (this card on the left, the one chosen on the right), or Compare With dimmed, with why, when none does. On a
/// card among exactly two picks it is Compare, as before: two pictures or two text files open the Compare window on
/// them; any other pair has the item dimmed with its reason, and opens nothing. A card Compare can't read has nothing.
struct ShelfCompareItem: View {
    @ObservedObject var model: ShelfModel
    let item: ShelfItem

    var body: some View {
        switch model.compareOffer(for: item) {
        case .none:
            EmptyView()
        case .compare(let left, let right):
            Button(CompareRules.menuTitle) { CompareWindowController.shared.show(left, right, shelf: model.shelf) }
        case .unavailable:
            Button(CompareRules.unavailableTitle) {}
                .disabled(true)
                .help(CompareRules.unavailableHelp)
        case .compareWith(let entries):
            Menu(CompareRules.compareWithTitle) {
                ForEach(entries) { entry in
                    Button(entry.title) { CompareWindowController.shared.show(entry.left, entry.right, shelf: model.shelf) }
                }
            }
        case .nothingToCompareWith(let help):
            // A dimmed item, not an empty submenu: nothing to open, and the reason on it.
            Button(CompareRules.compareWithTitle) {}
                .disabled(true)
                .help(help)
        }
    }
}

/// "Compare" in the title bar, beside Export as PDF…, while exactly two picks pair: a quiet pill like it, opening the
/// Compare window on them, the one shown first on the left.
struct ShelfComparePill: View {
    @ObservedObject var model: ShelfModel

    var body: some View {
        if let pair = model.comparablePair, case .comparable(let kind) = CompareRules.pairing(pair.0, pair.1) {
            Button { CompareWindowController.shared.show(pair.0, pair.1, shelf: model.shelf) } label: { Text(CompareRules.pillTitle) }
                .buttonStyle(SolanumPillStyle(.small))
                .fixedSize()
                .help(CompareRules.pillHelp(kind))
                .accessibilityLabel(CompareRules.pillSpoken(kind))
        }
    }
}
