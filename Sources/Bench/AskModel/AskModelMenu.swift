// AskModelMenu.swift — the ways into Ask Another Model (DESIGN.md, Ask another
// model), each shown only while the feature is on with a key saved:
// - File → Ask Another Model…, for the session in the main window (no
//   shortcut: no letter is safe from the page, and the keys left are awkward);
// - "Ask Another Model…" at the top of the Mac's right-click menu on the
//   conversation's text, starting from the selection when there is one (not on
//   a tab or a figure, which have Capsid's own items);
// - the same item in the reference window's right-click menu on Claude's
//   words, starting from the selection or the reply's question.
import AppKit
import Combine

/// File → Ask Another Model…: shown while the feature is on with a key, and on
/// while a session is in the main window.
@MainActor
final class AskCommands: ObservableObject {
    static let shared = AskCommands()

    @Published private(set) var isShown = false
    @Published private(set) var isEnabled = false
    private var watch: AnyCancellable?

    private init() {
        let model = AnotherModel.shared
        watch = model.objectWillChange.prepend(())
            .combineLatest(WebContainer.shared.$currentFrameID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, frame in
                MainActor.assumeIsolated {
                    let state = AskMenu.fileItem(available: model.isAvailable, session: frame, demo: Demo.mode != nil)
                    self?.isShown = state.shown
                    self?.isEnabled = state.enabled
                }
            }
    }

    func ask() { AskModelWindowController.shared.askAboutViewedSession() }
}

enum AskMenu {
    static let title = "Ask Another Model\u{2026}"
    static let itemID = NSUserInterfaceItemIdentifier("capsid.askModel")

    /// File's item: shown only while the feature is available, and on only
    /// with a session in the main window and outside a demo.
    static func fileItem(available: Bool, session: String?, demo: Bool) -> (shown: Bool, enabled: Bool) {
        guard available else { return (false, false) }
        return (true, !demo && session.map(PlanCheck.isFrameID) == true)
    }

    /// The item at the top of a right-click menu, and a separator under it,
    /// while the feature is available. Not added twice, and not to a menu
    /// that already has Capsid's tab or Shelf items (a tab or a figure).
    /// True when it was added.
    @MainActor
    @discardableResult
    static func insert(into menu: NSMenu, available: Bool, action: @escaping @MainActor () -> Void) -> Bool {
        guard available,
              !menu.items.contains(where: { [itemID, TabContextMenu.itemID, ConversationMenu.itemID].contains($0.identifier) })
        else { return false }
        let handler = AskMenuAction(run: action)
        let item = NSMenuItem(title: title, action: #selector(AskMenuAction.fire(_:)), keyEquivalent: "")
        item.target = handler
        // The item holds its target weakly; this keeps it alive as long as the item.
        item.representedObject = handler
        item.identifier = itemID
        menu.insertItem(item, at: 0)
        if menu.items.count > 1 {
            let separator = NSMenuItem.separator()
            separator.identifier = itemID
            menu.insertItem(separator, at: 1)
        }
        return true
    }
}

/// What the item does when it is chosen.
@MainActor
private final class AskMenuAction: NSObject {
    private let run: @MainActor () -> Void

    init(run: @escaping @MainActor () -> Void) {
        self.run = run
    }

    @objc func fire(_ sender: Any?) {
        run()
    }
}
