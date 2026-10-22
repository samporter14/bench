// MadeShelf.swift — a made-up shelf for the tests of the ways in (the
// conversation's menu, the toast, Results' rows, the reference window): it
// remembers what it was asked to add, answers from a table, and says when it
// changed, as `Shelf.shared` does. It writes nothing anywhere.
import Combine
import Foundation
@testable import Bench

@MainActor
final class MadeShelf {
    /// Versions on the shelf now.
    var onShelf: Set<String> = []
    /// Versions being added now.
    var adding: Set<String> = []
    /// What `add` answers; nil puts the version on the shelf and says `.added`.
    var outcome: ShelfAddOutcome?
    var undoResult = true
    /// Page reads wait here while `holding`, so a test can look mid-add.
    var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Undo waits here while `undoHolds`; `releaseUndo` lets it go.
    var undoHolds = false
    private var undoWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var added: [ShelfSource] = []
    private(set) var undone: [ShelfPlacement] = []
    private(set) var shown: [URL?] = []
    let changes = PassthroughSubject<Void, Never>()

    static func placement(_ name: String = "z_prime_by_plate.png", collection: String = "Assay development") -> ShelfPlacement {
        ShelfPlacement(folder: URL(fileURLWithPath: "/tmp/kept-test/\(collection)/\(name)", isDirectory: true),
                       name: name, collection: collection)
    }

    func release() {
        let waiting = waiters
        waiters = []
        holding = false
        for waiter in waiting { waiter.resume() }
    }

    func releaseUndo() {
        let waiting = undoWaiters
        undoWaiters = []
        undoHolds = false
        for waiter in waiting { waiter.resume() }
    }

    private(set) lazy var access = ShelfAccess(
        contains: { [self] in onShelf.contains($0) },
        isAdding: { [self] in adding.contains($0) },
        count: { [self] in onShelf.count },
        add: { [self] source in
            added.append(source)
            let version = source.entry.version
            adding.insert(version)
            changes.send()
            if holding { await withCheckedContinuation { waiters.append($0) } }
            adding.remove(version)
            let result = outcome ?? .added(Self.placement(source.entry.name))
            if case .added = result { onShelf.insert(version) }
            if case .alreadyOnShelf = result { onShelf.insert(version) }
            changes.send()
            return result
        },
        undo: { [self] in
            undone.append($0)
            if undoHolds { await withCheckedContinuation { undoWaiters.append($0) } }
            return undoResult
        },
        show: { [self] in shown.append($0) },
        changes: changes.eraseToAnyPublisher())
}
