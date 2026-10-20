// NextWaiting.swift — File → Next Waiting Session, ⌥⌘↓ (DESIGN.md, Next Waiting
// Session): opens the session that has waited longest among those that need
// you, and on the next press the one after it, round again. It walks the same
// asks the activity list shows first (`NeedsYou.asks`), in the same order, so
// a press is a step down the list.
import AppKit

@MainActor
final class NextWaiting {
    static let shared = NextWaiting(model: .shared)

    /// What the menus show: the name, and the keys that open it.
    static let title = "Next Waiting Session"
    static let keysHint = "⌥⌘↓"

    private let model: LabModel
    private let open: (SessionStatus) -> Void
    /// The session the last press opened, as it was read then: the next press
    /// goes on from it, even after it has been answered and left the list.
    /// In memory only, like everything about sessions.
    private var last: SessionStatus?

    /// The app uses `shared`; tests pass their own model and what opens.
    init(model: LabModel, open: ((SessionStatus) -> Void)? = nil) {
        self.model = model
        self.open = open ?? { [weak model] in model?.open($0) }
    }

    /// The sessions a press walks, the longest wait first.
    var order: [SessionStatus] { NeedsYou(model: model).asks }

    /// Nothing waits: the menu items are dimmed.
    var isEnabled: Bool { !order.isEmpty }

    /// Opens the next one and says which, or does nothing when none waits.
    @discardableResult
    func openNext() -> SessionStatus? {
        guard let session = Self.pick(from: order, after: last) else { return nil }
        last = session
        open(session)
        return session
    }

    /// The one after `last`, and the first when the list has come to its end,
    /// when nothing was opened yet, or after a session that is gone: that one
    /// is placed where its wait puts it, so answering a session between two
    /// presses doesn't send the next one back to the top. Pure.
    nonisolated static func pick(from order: [SessionStatus], after last: SessionStatus?) -> SessionStatus? {
        guard let first = order.first else { return nil }
        guard let last else { return first }
        if let index = order.firstIndex(where: { $0.id == last.id }) {
            return order[(index + 1) % order.count]
        }
        return order.first { NeedsYou.waitedLonger(last, $0) } ?? first
    }

    // MARK: The keys

    /// ⌥⌘↓: the down arrow with Command and Option and nothing else but the
    /// flags an arrow key always carries (`function`, `numericPad`). The key
    /// code, not a character, so it holds on any keyboard layout. Pure.
    nonisolated static func isKey(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        keyCode == Self.downArrow
            && modifiers.intersection([.command, .shift, .option, .control]) == [.command, .option]
    }

    private nonisolated static let downArrow: UInt16 = 125
}
