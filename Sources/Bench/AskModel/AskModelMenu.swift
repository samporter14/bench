// AskModelMenu.swift — the ways into Ask Another Model (DESIGN.md, Ask another
// model), each shown only while the feature is on with a key saved:
// - a button in the main window's toolbar (AskToolbarButton.swift), beside
//   Results and the Shelf, on while a session is in the main window;
// - File → Ask Another Model…, the same rule (no shortcut: no letter is safe
//   from the page, and the keys left are awkward);
// - "Ask Another Model…" at the end of Claude Science's own model menu, in the
//   page, starting from what is typed in the message box (ModelPickerMenu.swift);
// - "Ask Another Model…" in the reference window's right-click menu on
//   Claude's words, starting from the selection or the reply's question.
// The Mac's right-click menu on the conversation had it first; it was found
// odd, and these two places replaced it.
import AppKit
import Combine

/// The toolbar button's and File's item: shown while the feature is on with a
/// key, and on while a session is in the main window. One rule for both
/// (`AskMenu.fileItem`).
@MainActor
final class AskCommands: ObservableObject {
    static let shared = AskCommands()

    @Published private(set) var isShown = false
    @Published private(set) var isEnabled = false
    private var watch: AnyCancellable?
    private let open: @MainActor () -> Void

    /// `model` says whether the feature is available, `frames` is the session
    /// the main window shows (nil: none), `demo` whether this is a demo run and
    /// `open` what the button and the item do.
    init(model: AnotherModel, frames: some Publisher<String?, Never>, demo: Bool,
         open: @escaping @MainActor () -> Void) {
        self.open = open
        watch = model.objectWillChange.prepend(())
            .combineLatest(frames)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, frame in
                MainActor.assumeIsolated {
                    let state = AskMenu.fileItem(available: model.isAvailable, session: frame, demo: demo)
                    self?.isShown = state.shown
                    self?.isEnabled = state.enabled
                }
            }
    }

    private convenience init() {
        self.init(model: .shared, frames: WebContainer.shared.$currentFrameID, demo: Demo.mode != nil,
                  open: { AskModelWindowController.shared.askAboutViewedSession() })
    }

    func ask() { open() }
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
    /// while the feature is available (the reference window's text menu).
    /// Not added twice. True when it was added.
    @MainActor
    @discardableResult
    static func insert(into menu: NSMenu, available: Bool, action: @escaping @MainActor () -> Void) -> Bool {
        guard available, !menu.items.contains(where: { $0.identifier == itemID }) else { return false }
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
