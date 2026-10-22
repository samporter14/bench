// ShelfAccess.swift — what the ways into the shelf ask of it (DESIGN.md,
// Shelf; Kept/Shelf.swift is the shelf itself). The conversation's menu, the
// toast, the toolbar's pill, Results' rows and the reference window all ask
// the same few things: is this version on the shelf, is it being added, how
// many are there, add this, take that back, show the window. They ask through
// this, so a test or a snapshot can stand a made-up shelf in, and the live one
// is `Shelf.shared`. It is an ObservableObject that says when the shelf
// changed, so a view that watches it draws "On Shelf ✓" the moment it is.
import Combine
import Foundation

@MainActor
final class ShelfAccess: ObservableObject {
    /// Whether a version is on the shelf.
    var contains: @MainActor (String) -> Bool
    /// Whether a version is being added now.
    var isAdding: @MainActor (String) -> Bool
    /// How many items are on the shelf.
    var count: @MainActor () -> Int
    /// Puts one file on the shelf.
    var add: @MainActor (ShelfSource) async -> ShelfAddOutcome
    /// Takes an add back: the folder goes to the Trash.
    var undo: @MainActor (ShelfPlacement) async -> Bool
    /// Shows the Shelf window, on an item when it is given.
    var show: @MainActor (URL?) -> Void
    /// Asks the shelf to start reading what is on it, if it hasn't: the
    /// toolbar's count is shown at launch and nothing else would ask.
    var prime: @MainActor () -> Void

    private var watch: AnyCancellable?

    /// `changes` says the shelf changed (a version came or went, an add began
    /// or ended); views watching this object redraw after it.
    init(contains: @escaping @MainActor (String) -> Bool,
         isAdding: @escaping @MainActor (String) -> Bool = ShelfAccess.notAdding,
         count: @escaping @MainActor () -> Int,
         add: @escaping @MainActor (ShelfSource) async -> ShelfAddOutcome,
         undo: @escaping @MainActor (ShelfPlacement) async -> Bool = ShelfAccess.cannotUndo,
         show: @escaping @MainActor (URL?) -> Void = ShelfAccess.cannotShow,
         prime: @escaping @MainActor () -> Void = ShelfAccess.nothingToPrime,
         changes: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()) {
        self.contains = contains
        self.isAdding = isAdding
        self.count = count
        self.add = add
        self.undo = undo
        self.show = show
        self.prime = prime
        // After the change, not before it: `objectWillChange` fires first.
        watch = changes.receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    // What a made-up shelf does when it is not told: nothing is added, taken
    // back, shown or read ahead. (Named functions, not closures: a closure
    // written as a default of a main-actor closure type does not compile
    // where the caller's isolation is not the same.)
    static func notAdding(_ version: String) -> Bool { false }
    static func cannotUndo(_ placement: ShelfPlacement) async -> Bool { false }
    static func cannotShow(_ folder: URL?) {}
    static func nothingToPrime() {}

    /// The real shelf.
    static let live = ShelfAccess(
        contains: { Shelf.shared.contains(version: $0) },
        isAdding: { Shelf.shared.adding.contains($0) },
        count: { Shelf.shared.count },
        add: { await Shelf.shared.add($0) },
        undo: { await Shelf.shared.undo($0) },
        show: { Shelf.shared.show(selecting: $0) },
        // The contract has no explicit load: `versions` is read lazily, on first use.
        prime: { Shelf.shared.load() },
        changes: Shelf.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
}

/// How a row, a card or a pill shows one version's place on the shelf.
enum ShelfMark: Equatable, Sendable {
    /// Not on it: "Add to Shelf".
    case off
    /// An add is under way: a spinner.
    case adding
    /// On it: "On Shelf ✓".
    case on

    @MainActor
    init(_ version: String, in shelf: ShelfAccess) {
        self = shelf.isAdding(version) ? .adding : (shelf.contains(version) ? .on : .off)
    }
}

/// The shelf's words that more than one place says.
enum ShelfWords {
    static let add = "Add to Shelf"
    static let on = "On Shelf \u{2713}"
    static let adding = "Adding\u{2026}"
    static let keep = "Keep with Data and Code\u{2026}"
    /// The toolbar's pill: "Shelf", or "Shelf · 12" once there is something on it.
    static func pill(count: Int) -> String { count > 0 ? "Shelf \u{00B7} \(count)" : "Shelf" }
}
