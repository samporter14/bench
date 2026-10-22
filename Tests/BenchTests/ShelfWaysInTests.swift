// ShelfWaysInTests.swift — the small shared pieces of the Shelf's ways in
// (Shelf/ShelfAccess.swift, ShelfCommands.swift, ShelfToolbarButton.swift):
// how a version's place on the shelf reads, the toolbar's words, File → Add to
// Shelf's gate, and that a view watching the shelf is told when it changes.
// A made-up shelf; nothing is added anywhere.
import Combine
import Foundation
import Testing
@testable import Bench

@MainActor
struct ShelfWaysInTests {
    // MARK: A version's place

    @Test func aVersionIsOffAddingOrOn() {
        let shelf = MadeShelf()
        shelf.onShelf = ["on"]
        shelf.adding = ["adding"]
        #expect(ShelfMark("none", in: shelf.access) == .off)
        #expect(ShelfMark("adding", in: shelf.access) == .adding)
        #expect(ShelfMark("on", in: shelf.access) == .on)
        // Being added wins: a second copy is on its way while the first is there.
        shelf.onShelf.insert("adding")
        #expect(ShelfMark("adding", in: shelf.access) == .adding)
    }

    @Test func theMarkFollowsTheShelfAsItAddsThenFinishes() async {
        let shelf = MadeShelf()
        let source = ShelfSource(session: ReferenceModelTests.session,
                                 entry: ArtifactEntry(version: "v1", artifact: nil, name: "plate.png", mime: nil, size: 0, at: nil))
        shelf.holding = true
        let adding = Task { await shelf.access.add(source) }
        for _ in 0..<50 where shelf.added.isEmpty { await Task.yield() }
        #expect(ShelfMark("v1", in: shelf.access) == .adding)
        shelf.release()
        _ = await adding.value
        #expect(ShelfMark("v1", in: shelf.access) == .on)
    }

    // MARK: Words

    @Test func theToolbarSaysShelfAndThenHowMany() {
        #expect(ShelfWords.pill(count: 0) == "Shelf")
        #expect(ShelfWords.pill(count: 1) == "Shelf \u{00B7} 1")
        #expect(ShelfWords.pill(count: 12) == "Shelf \u{00B7} 12")
    }

    @Test func theSharedWordsAreTheBoardsOwn() {
        #expect(ShelfWords.add == "Add to Shelf")
        #expect(ShelfWords.on == "On Shelf \u{2713}")
        #expect(ShelfWords.keep == "Keep with Data and Code\u{2026}")
    }

    // MARK: File → Add to Shelf

    @Test func addToShelfIsOnOnlyWithAFileSelected() {
        let commands = ShelfCommands()
        #expect(!commands.canAdd)
        commands.addSelected()
        #expect(commands.requests == 0)
        commands.selected = ShelfSource(session: ReferenceModelTests.session,
                                        entry: ArtifactEntry(version: "v1", artifact: nil, name: "plate.png", mime: nil, size: 0, at: nil))
        #expect(commands.canAdd)
        commands.addSelected()
        commands.addSelected()
        #expect(commands.requests == 2)
        commands.selected = nil
        #expect(!commands.canAdd)
    }

    // MARK: Watching

    @Test func aViewWatchingTheShelfIsToldAfterItChanges() async {
        let shelf = MadeShelf()
        var told = 0
        let watch = shelf.access.objectWillChange.sink { told += 1 }
        shelf.changes.send()
        // After the change, on the main queue, not in the middle of it.
        #expect(told == 0)
        for _ in 0..<200 where told == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(told == 1)
        withExtendedLifetime(watch) {}
    }

    @Test func theToolbarPrimesTheShelfOnce() {
        var primed = 0
        let access = ShelfAccess(contains: { _ in false }, count: { 3 }, add: { _ in .failed("x") }, prime: { primed += 1 })
        access.prime()
        #expect(primed == 1)
        #expect(access.count() == 3)
    }
}
