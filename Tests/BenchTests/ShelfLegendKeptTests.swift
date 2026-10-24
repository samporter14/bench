// ShelfLegendKeptTests.swift — a legend draft outlives its card (Kept/ShelfLegend.swift, ShelfModel.legendEditor(for:)):
// the field is hidden the moment another item is chosen, but the save it started may still fail (a README changed in
// another app, a disk that says no). The draft and the sentence stay with the model, the window says so on its pill,
// and choosing the item again shows both, not the README's old text. The disk is the real `KeptDisk` on the demo's
// made-up Kept folder, with its calls held back so a save can be left pending while the item is left.
import Foundation
import Testing
@testable import Bench

/// The disk's calls, kept back while `holding`, then run in order.
private final class HeldCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [KeptDisk.Work] = []
    private var hold = false

    func holding(_ on: Bool) {
        let release: [KeptDisk.Work] = lock.withLock {
            hold = on
            guard !on else { return [] }
            defer { kept = [] }
            return kept
        }
        for work in release { KeptDisk.runOnDisk(work) }
    }

    var count: Int { lock.withLock { kept.count } }

    func run(_ work: @escaping KeptDisk.Work) {
        let held = lock.withLock { () -> Bool in
            guard hold else { return false }
            kept.append(work)
            return true
        }
        if !held { KeptDisk.runOnDisk(work) }
    }
}

@MainActor
private func until(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw CancellationError()
}

@MainActor
struct ShelfLegendKeptTests {
    /// The demo's shelf in a scratch root with the disk's calls under `held`'s control, a model on it (the field waits a
    /// minute, so only leaving it saves), the item kept with a legend, and another item.
    private func rig(_ body: (ShelfModel, ShelfItem, ShelfItem, HeldCalls) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-legend-kept-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let held = HeldCalls()
        let disk = KeptDisk(root: { root }, run: { held.run($0) })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        await index.refreshAndWait()
        let model = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining), legendDelay: .seconds(60))
        let item = try #require(model.shown.first { !$0.text.legend.isEmpty })
        let other = try #require(model.shown.first { $0.id != item.id })
        try await body(model, item, other, held)
    }

    private func legendOnDisk(_ item: ShelfItem, _ model: ShelfModel) async throws -> String {
        try await model.index.disk.readme(at: item.folder).text.legend
    }

    // MARK: A save that fails after the item was left

    @Test func aDraftWhoseSaveRunsIntoAChangeMadeElsewhereIsStillThereWhenTheItemIsChosenAgain() async throws {
        try await rig { model, item, other, held in
            let disk = model.index.disk
            let editor = model.legendEditor(for: item)
            await editor.show()
            #expect(editor.onScreen && editor.legend == item.text.legend)
            editor.legend = "Draft typed before moving on."

            // Another app changes the README; then the item is left while the save waits on the disk.
            let read = try await disk.readme(at: item.folder)
            _ = try await disk.replaceLegend(at: item.folder, with: "Theirs, from another app.", lastRead: read.markdown)
            held.holding(true)
            editor.hide()
            model.selection = other.id
            #expect(!editor.onScreen)
            try await until("the save to reach the disk") { held.count == 1 }
            held.holding(false)
            try await until("the save to run into the change") { editor.changedOutside }

            // The window says so, naming the item; nothing was written over.
            #expect(model.note?.sentence == ShelfLegendEditor.leftUnsaved(item.title, conflict: true))
            let onDisk = try await legendOnDisk(item, model)
            #expect(onDisk == "Theirs, from another app.")

            // Chosen again: the same editor, with the draft and the conflict, not the README's text.
            model.selection = item.id
            let again = model.legendEditor(for: item)
            #expect(again === editor)
            await again.show()
            #expect(again.legend == "Draft typed before moving on." && again.changedOutside && again.canEdit)
            #expect(again.hasUnsavedText)

            // Use Mine settles it, and an editor with nothing left to say is let go.
            await again.useMine()
            let mine = try await legendOnDisk(item, model)
            #expect(mine == "Draft typed before moving on." && !again.changedOutside)
            again.hide()
            await again.settle()
            _ = model.legendEditor(for: other)
            #expect(!model.keepsLegendEditor(for: item.id))
        }
    }

    @Test func aDraftWhoseSaveFailsOnTheDiskIsStillThereWithItsSentenceWhenTheItemIsChosenAgain() async throws {
        try await rig { model, item, other, held in
            let editor = model.legendEditor(for: item)
            await editor.show()
            editor.legend = "Draft typed before the disk said no."
            held.holding(true)
            editor.hide()
            model.selection = other.id
            try await until("the save to reach the disk") { held.count == 1 }
            // The README goes while the save waits.
            try FileManager.default.removeItem(at: item.folder.appending(path: "README.md", directoryHint: .notDirectory))
            held.holding(false)
            try await until("the save to fail") { editor.problem != nil }

            #expect(model.note?.sentence == ShelfLegendEditor.leftUnsaved(item.title, conflict: false))
            model.selection = item.id
            let again = model.legendEditor(for: item)
            #expect(again === editor)
            await again.show()
            #expect(again.legend == "Draft typed before the disk said no.")
            #expect(again.problem == ShelfLegendEditor.unsaved("There is no README.md in this folder."))
            #expect(again.canEdit && again.hasUnsavedText && model.keepsLegendEditor(for: item.id))
        }
    }

    @Test func aFailedSaveWhileTheFieldIsOnScreenIsTheFieldsToSayAndTheWindowSaysNothing() async throws {
        try await rig { model, item, _, _ in
            let disk = model.index.disk
            let editor = model.legendEditor(for: item)
            await editor.show()
            let read = try await disk.readme(at: item.folder)
            _ = try await disk.replaceLegend(at: item.folder, with: "Theirs.", lastRead: read.markdown)
            editor.legend = "Mine."
            await editor.save()
            #expect(editor.changedOutside)
            #expect(model.note == nil)
        }
    }

    // MARK: A README a person has written in

    /// Words written under the README's title used to make `parse` answer nil, and the item left the Shelf.
    @Test func anItemWhoseReadmeHasWordsUnderItsTitleIsStillOnTheShelfWithItsFigureAndItsWords() async throws {
        try await rig { model, item, other, _ in
            let url = item.folder.appending(path: "README.md", directoryHint: .notDirectory)
            let before = try String(contentsOf: url, encoding: .utf8)
            let words = "Draft for the plate 7 discussion.\nCheck the cutoff with Dana first."
            let heading = "# \(item.record.name)\n\n"
            #expect(before.contains(heading))
            try Data(before.replacingOccurrences(of: heading, with: heading + words + "\n\n").utf8).write(to: url)
            let count = model.items.count
            await model.index.refreshAndWait()

            #expect(model.items.count == count)
            let still = try #require(model.items.first { $0.id == item.id })
            #expect(still.title == item.title && still.text.legend == item.text.legend && still.text.claudeSaid == item.text.claudeSaid)
            #expect(still.record == item.record)
            #expect(FileManager.default.fileExists(atPath: still.folder.appending(path: item.record.figure.path).path))
            #expect(model.shown.contains { $0.id == item.id } && model.shown.contains { $0.id == other.id })

            // The legend is edited in it, and the words stay.
            let editor = model.legendEditor(for: still)
            await editor.show()
            #expect(editor.canEdit && editor.legend == item.text.legend)
            editor.legend = "Edited under the words."
            await editor.flush().value
            #expect(!editor.changedOutside && editor.problem == nil)
            let after = try String(contentsOf: url, encoding: .utf8)
            #expect(after.contains(heading + words + "\n\n## Your legend"))
            #expect(try await legendOnDisk(still, model) == "Edited under the words.")
            await model.index.refreshAndWait()
            #expect(model.items.first { $0.id == item.id }?.text.legend == "Edited under the words.")
        }
    }

    // MARK: Keeping and letting go

    @Test func aSavedDraftIsLetGoAndACleanFieldIsReadAgainEachTimeItIsShown() async throws {
        try await rig { model, item, other, _ in
            let disk = model.index.disk
            let editor = model.legendEditor(for: item)
            await editor.show()
            editor.legend = "Saved on the way out."
            editor.hide()
            await editor.settle()
            let saved = try await legendOnDisk(item, model)
            #expect(saved == "Saved on the way out." && !editor.holdsDraft && model.note == nil)
            // Nothing left to say: the next editor asked for lets it go.
            #expect(editor.isIdle)
            _ = model.legendEditor(for: other)
            #expect(!model.keepsLegendEditor(for: item.id))
            // A new one reads the README, as the card always did.
            let fresh = model.legendEditor(for: item)
            #expect(fresh !== editor)
            let read = try await disk.readme(at: item.folder)
            _ = try await disk.replaceLegend(at: item.folder, with: "Changed meanwhile.", lastRead: read.markdown)
            await fresh.show()
            #expect(fresh.legend == "Changed meanwhile.")
            // The same editor shown again with nothing to keep also reads it again.
            fresh.hide()
            await fresh.settle()
            let again = model.legendEditor(for: item)
            let read2 = try await disk.readme(at: item.folder)
            _ = try await disk.replaceLegend(at: item.folder, with: "And again.", lastRead: read2.markdown)
            await again.show()
            #expect(again.legend == "And again.")
        }
    }

    @Test func theEditorForAnItemIsTheSameOneWhileTheFieldIsOnScreen() async throws {
        try await rig { model, item, other, _ in
            let editor = model.legendEditor(for: item)
            await editor.show()
            // Another item's card is made first (the next card's view is built before the old one goes), and the one on
            // screen is kept.
            _ = model.legendEditor(for: other)
            #expect(model.legendEditor(for: item) === editor)
            #expect(model.keepsLegendEditor(for: item.id))
        }
    }

    // MARK: The view

    /// The wiring the editor's tests can't see: the card takes the model's editor and shows and hides it.
    @Test func theCardTakesTheModelsEditorAndShowsAndHidesIt() throws {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let extras = try #require(view.range(of: "struct ShelfExtras: View"))
        let body = String(view[extras.lowerBound...].prefix(upTo: view.range(of: "// MARK: Pieces")!.lowerBound))
        #expect(body.contains("@ObservedObject private var editor: ShelfLegendEditor"))
        #expect(body.contains("model.legendEditor(for: item)"))
        #expect(!body.contains("StateObject"))
        #expect(body.contains(".task { await editor.show() }"))
        #expect(body.contains(".onDisappear { editor.hide() }"))
    }
}
