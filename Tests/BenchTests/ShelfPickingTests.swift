// ShelfPickingTests.swift — choosing several things on the Shelf
// (Kept/ShelfPicking.swift): a plain click, ⌘-click and ⇧-click, ⌘A, the
// arrow keys and Esc, what the filters do to the picks, the order the pages
// follow, and that everything the Shelf did with one selection still holds.
// On the demo's made-up shelf in a temporary root; nothing is drawn.
import AppKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct ShelfPickingTests {
    /// The demo's ten items, newest first, in a model of their own.
    private func rig() async throws -> (model: ShelfModel, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-picking-\(UUID().uuidString)", isDirectory: true)
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        await index.refreshAndWait()
        let model = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining))
        #expect(model.shown.count == 10)
        return (model, root)
    }

    private func ids(_ model: ShelfModel, _ positions: Int...) -> [String] { positions.map { model.shown[$0].id } }

    @Test func aPlainClickPicksOneCardAndTheWindowOpensWithTheFirstPicked() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.picked == [model.shown[0].id] && model.selection == model.shown[0].id)
        model.pick(model.shown[3].id, .only)
        #expect(model.picked == [model.shown[3].id] && model.selection == model.shown[3].id)
        #expect(model.pickCount == 1 && model.pageNumber(of: model.shown[3].id) == nil)
        // A card that isn't shown can't be picked.
        model.pick("nothing", .only)
        model.pick("nothing", .toggle)
        model.pick("nothing", .range)
        #expect(model.picked == [model.shown[3].id])
    }

    @Test func aCommandClickAddsACardAndTakesItAwayAndTheLastPickStays() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        model.pick(model.shown[1].id, .only)
        model.pick(model.shown[4].id, .toggle)
        model.pick(model.shown[2].id, .toggle)
        #expect(model.picked == Set(ids(model, 1, 4, 2)))
        // The card just added is the one the detail shows.
        #expect(model.selection == model.shown[2].id)
        // Taking away another leaves the selection where it was.
        model.pick(model.shown[4].id, .toggle)
        #expect(model.picked == Set(ids(model, 1, 2)) && model.selection == model.shown[2].id)
        // Taking away the selected one moves it to the first still picked, in the order shown.
        model.pick(model.shown[2].id, .toggle)
        #expect(model.picked == Set(ids(model, 1)) && model.selection == model.shown[1].id)
        // The last pick can't be taken away.
        model.pick(model.shown[1].id, .toggle)
        #expect(model.picked == Set(ids(model, 1)) && model.selection == model.shown[1].id)
    }

    @Test func aShiftClickPicksTheRunFromTheLastCardClickedInEitherDirection() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        model.pick(model.shown[2].id, .only)
        model.pick(model.shown[5].id, .range)
        #expect(model.picked == Set(ids(model, 2, 3, 4, 5)) && model.selection == model.shown[5].id)
        // A second ⇧-click runs from the same card, not the last one: the run grows and shrinks.
        model.pick(model.shown[7].id, .range)
        #expect(model.picked == Set(ids(model, 2, 3, 4, 5, 6, 7)))
        model.pick(model.shown[3].id, .range)
        #expect(model.picked == Set(ids(model, 2, 3)))
        model.pick(model.shown[0].id, .range)
        #expect(model.picked == Set(ids(model, 0, 1, 2)))
        // After a ⌘-click the run starts at that card.
        model.pick(model.shown[6].id, .toggle)
        model.pick(model.shown[8].id, .range)
        #expect(model.picked == Set(ids(model, 6, 7, 8)))
        // With nothing clicked yet it runs from the selected card.
        let fresh = ShelfModel(shelf: model.shelf, pdf: ShelfPDFMaker(dependencies: .declining))
        fresh.pick(fresh.shown[2].id, .range)
        #expect(fresh.picked == Set(ids(fresh, 0, 1, 2)))
    }

    @Test func commandATakesEverythingShownAndKeepsTheSelectedCardSelected() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        model.pick(model.shown[4].id, .only)
        model.pickAll()
        #expect(model.pickCount == 10 && model.selection == model.shown[4].id)
        // Only what the chip and the search leave.
        model.kind = .figure
        model.pick(model.shown[0].id, .only)
        model.pickAll()
        #expect(model.pickCount == model.shown.count && model.shown.allSatisfy { $0.kind == .figure })
        #expect(model.pickedItems.map(\.id) == model.shown.map(\.id))
        model.kind = .table
        model.search = "no such thing"
        model.pickAll()
        #expect(model.picked.isEmpty && model.selection == nil)
    }

    @Test func anArrowKeyAnythingSelectingOrEscGoesBackToOneCard() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        model.pick(model.shown[0].id, .only)
        model.pick(model.shown[3].id, .range)
        #expect(model.pickCount == 4)
        model.move(1, 0)
        #expect(model.pickCount == 1 && model.picked == [model.selection!])
        model.pickAll()
        model.pickOnlySelected()
        #expect(model.pickCount == 1 && model.picked == [model.selection!])
        model.pickAll()
        model.selection = model.shown[6].id
        #expect(model.picked == [model.shown[6].id])
        // A click on one of several picks is a plain click: it goes back to that one.
        model.pickAll()
        model.pick(model.shown[2].id, .only)
        #expect(model.picked == [model.shown[2].id])
    }

    @Test func theFiltersLeaveOnlyThePicksThatAreStillShown() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        // A figure, a note and a table picked.
        let figure = try #require(model.shown.first { $0.kind == .figure })
        let note = try #require(model.shown.first { $0.kind == .document })
        let table = try #require(model.shown.first { $0.kind == .table })
        model.pick(figure.id, .only)
        model.pick(note.id, .toggle)
        model.pick(table.id, .toggle)
        #expect(model.pickCount == 3 && model.selection == table.id)
        // Documents only: the two others go, and the selected one with them, so the picked note takes over.
        model.kind = .document
        #expect(model.picked == [note.id] && model.selection == note.id)
        model.kind = nil
        #expect(model.picked == [note.id])
        // Two picks that survive a filter stay two, the selection moving to one of them.
        model.pick(figure.id, .toggle)
        model.pick(table.id, .toggle)
        model.kind = .figure
        #expect(model.picked == [figure.id] && model.selection == figure.id)
        model.kind = nil
        model.pickAll()
        model.pick(figure.id, .only)
        model.pick(note.id, .toggle)
        model.pick(table.id, .toggle)
        model.project = figure.collection
        let inProject = [figure, note, table].filter { $0.collection == figure.collection }.map(\.id)
        #expect(model.picked == Set(inProject) && model.picked.contains(model.selection!))
    }

    @Test func thePagesFollowTheOrderOfTheCardsNotTheOrderOfTheClicks() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        model.pick(model.shown[5].id, .only)
        model.pick(model.shown[1].id, .toggle)
        model.pick(model.shown[3].id, .toggle)
        #expect(model.pickedItems.map(\.id) == ids(model, 1, 3, 5))
        #expect(model.pageNumber(of: model.shown[1].id) == 1)
        #expect(model.pageNumber(of: model.shown[3].id) == 2)
        #expect(model.pageNumber(of: model.shown[5].id) == 3)
        #expect(model.pageNumber(of: model.shown[0].id) == nil)
    }

    @Test func theMenuMakesThePDFOfThePicksWhenItsCardIsOneOfThemElseOfThatCardAlone() async throws {
        let (model, root) = try await rig()
        defer { try? FileManager.default.removeItem(at: root) }
        model.pick(model.shown[0].id, .only)
        model.pick(model.shown[2].id, .toggle)
        // The menu on a card outside the picks makes that card the pick.
        model.pick(model.shown[6].id, .only)
        model.pick(model.shown[2].id, .toggle)
        let picked = model.picked
        let outside = model.shown[8]
        model.exportPDF(from: outside)
        #expect(model.picked == [outside.id])
        // On a card among them it leaves them alone.
        model.picked = picked
        model.exportPDF(from: model.shown[6])
        #expect(model.picked == picked)
    }

    @Test func theModifiersSayHowAClickPicks() {
        #expect(ShelfModel.Pick([]) == .only)
        #expect(ShelfModel.Pick(.command) == .toggle)
        #expect(ShelfModel.Pick(.shift) == .range)
        #expect(ShelfModel.Pick([.command, .shift]) == .range)
        #expect(ShelfModel.Pick(.option) == .only)
        #expect(ShelfModel.Pick(.capsLock) == .only)
    }
}
