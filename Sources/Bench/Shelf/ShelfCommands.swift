// ShelfCommands.swift — File → Add to Shelf (⌥⌘S) reaches the Results
// window's selection through this, as File → Keep with Data and Code… does
// through `KeptCommands`: the Results window says which file is selected while
// it is key, and the menu item is on only then. The add itself is the same as
// the row's seal: the shelf takes the file and the row shows "On Shelf ✓".
import Foundation

@MainActor
final class ShelfCommands: ObservableObject {
    static let shared = ShelfCommands()

    /// What the Results window has selected, while it is key.
    @Published var selected: ShelfSource?
    /// Bumped by the menu: the Results window adds `selected` and says how it went.
    @Published private(set) var requests = 0

    /// On with a file selected, and never in a demo.
    var canAdd: Bool { Demo.mode == nil && selected != nil }

    /// The menu item: the Results window sees `requests` change and adds the file.
    func addSelected() {
        guard canAdd else { return }
        requests += 1
    }
}
