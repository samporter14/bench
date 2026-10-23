// ShelfPDFFreshTests.swift — the PDF is made from what is saved (Kept/ShelfPicking.swift,
// ShelfModel.latest(of:), ShelfLegendEditor.settle()): a legend typed a moment before the command, or while the
// save panel is up, or a README changed in another app meanwhile, is what the pages say, not the words the shelf
// held when the command was given. The disk is the real `KeptDisk` on the demo's made-up Kept folder; the save
// panel, the drawing and Finder are fakes.
import Foundation
import Testing
@testable import Bench

@MainActor
private final class Pages {
    var pages: [ShelfPDFPage] = []
    var made = 0
    /// What happens while the save panel is up.
    var whileAsking: (@MainActor () async -> Void)?
    var destination: URL? = URL(fileURLWithPath: "/tmp/Downloads/Lab meeting 2026-10-22.pdf", isDirectory: false)

    var maker: ShelfPDFMaker {
        ShelfPDFMaker(dependencies: ShelfPDFMaker.Dependencies(
            choose: { [self] _ in
                await whileAsking?()
                return destination
            },
            render: { [self] pages, _, _, _ in await record(pages) },
            words: { _ in nil }, reveal: { _ in },
            now: { Date(timeIntervalSince1970: 1_792_674_720) }, calendar: .current, locale: Locale(identifier: "en_US")))
    }

    func record(_ pages: [ShelfPDFPage]) {
        self.pages = pages
        made += 1
    }
}

@MainActor
struct ShelfPDFFreshTests {
    /// The demo's shelf in a scratch root, a model on it making PDFs through the fakes, the item that was kept with
    /// a legend of its own picked, and its legend field as the card makes it (a minute's wait, so only the command
    /// can save what is typed).
    private func rig(_ body: (ShelfModel, ShelfItem, ShelfLegendEditor, Pages) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pdf-fresh-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        await index.refreshAndWait()
        let pages = Pages()
        let model = ShelfModel(shelf: shelf, pdf: pages.maker)
        let item = try #require(model.shown.first { !$0.text.legend.isEmpty })
        model.pick(item.id, .only)
        let editor = ShelfLegendEditor(folder: item.folder, disk: disk, delay: .seconds(60)) { await index.reload(item.result) }
        await editor.load()
        model.track(legend: editor, for: item.id)
        #expect(editor.canEdit && editor.legend == item.text.legend)
        try await body(model, item, editor, pages)
    }

    private func legendOnDisk(_ item: ShelfItem, _ disk: KeptDisk) async throws -> String {
        try await disk.readme(at: item.folder).text.legend
    }

    @Test func aLegendTypedJustBeforeTheCommandIsInThePDF() async throws {
        try await rig { model, item, editor, pages in
            editor.legend = "Z\u{2032} above 0.5 on every plate but 7."
            #expect(editor.hasUnsavedText)
            await model.exportPDF().value
            #expect(pages.made == 1)
            #expect(pages.pages.map(\.legend) == ["Z\u{2032} above 0.5 on every plate but 7."])
            // What was typed is saved, not only drawn.
            let onDisk = try await legendOnDisk(item, model.index.disk)
            #expect(onDisk == "Z\u{2032} above 0.5 on every plate but 7.")
            #expect(!editor.hasUnsavedText)
        }
    }

    @Test func aLegendTypedWhileTheSavePanelIsUpIsInThePDF() async throws {
        try await rig { model, item, editor, pages in
            // The card's own wait is a minute here; the panel is answered before it is over.
            pages.whileAsking = { editor.legend = "Typed while the panel was up." }
            await model.exportPDF().value
            #expect(pages.pages.map(\.legend) == ["Typed while the panel was up."])
            let onDisk = try await legendOnDisk(item, model.index.disk)
            #expect(onDisk == "Typed while the panel was up.")
        }
    }

    @Test func aLegendSavedAndThenChangedInAnotherAppWhileThePanelIsUpIsReadAgain() async throws {
        try await rig { model, item, _, pages in
            let disk = model.index.disk
            pages.whileAsking = {
                let read = try? await disk.readme(at: item.folder)
                _ = try? await disk.replaceLegend(at: item.folder, with: "Written in a text editor.", lastRead: read?.markdown ?? "")
            }
            await model.exportPDF().value
            #expect(pages.pages.map(\.legend) == ["Written in a text editor."])
        }
    }

    @Test func aReadmeChangedElsewhereIsNeverWrittenOverAndThePDFSaysWhatItHolds() async throws {
        try await rig { model, item, editor, pages in
            let disk = model.index.disk
            // Another app changes the README; the field then holds text of its own.
            let read = try await disk.readme(at: item.folder)
            _ = try await disk.replaceLegend(at: item.folder, with: "Theirs, from another app.", lastRead: read.markdown)
            editor.legend = "Mine, typed a moment ago."
            await model.exportPDF().value
            // The editor's own way: nothing is forced, the field says what happened.
            #expect(editor.changedOutside)
            let onDisk = try await legendOnDisk(item, disk)
            #expect(onDisk == "Theirs, from another app.")
            #expect(pages.pages.map(\.legend) == ["Theirs, from another app."])
            #expect(editor.legend == "Mine, typed a moment ago.")
        }
    }

    @Test func aReadmeThatCantBeReadLeavesThePageAsTheShelfHadIt() async throws {
        try await rig { model, item, _, pages in
            try FileManager.default.removeItem(at: item.folder.appending(path: "README.md", directoryHint: .notDirectory))
            await model.exportPDF().value
            #expect(pages.made == 1)
            #expect(pages.pages.map(\.legend) == [ShelfPDFRules.words(for: item).legend])
        }
    }

    @Test func everyPickedItemIsReadAgainNotOnlyTheOneWithAField() async throws {
        try await rig { model, item, editor, pages in
            let other = try #require(model.shown.first { $0.id != item.id })
            model.pick(other.id, .toggle)
            let disk = model.index.disk
            let read = try await disk.readme(at: other.folder)
            _ = try await disk.replaceLegend(at: other.folder, with: "Written beside the figure.", lastRead: read.markdown)
            editor.legend = "Typed on the first."
            await model.exportPDF().value
            let byName = Dictionary(uniqueKeysWithValues: zip(model.pickedItems.map(\.id), pages.pages.map(\.legend)))
            #expect(byName[item.id] == "Typed on the first.")
            #expect(byName[other.id] == "Written beside the figure.")
        }
    }

    @Test func cancellingThePanelStillLeavesTheLegendUntouchedByTheCommand() async throws {
        try await rig { model, item, editor, pages in
            pages.destination = nil
            editor.legend = "Typed, then the panel was cancelled."
            await model.exportPDF().value
            // No PDF; the field's own wait is what saves it, as ever.
            #expect(pages.made == 0)
            #expect(editor.hasUnsavedText)
            let onDisk = try await legendOnDisk(item, model.index.disk)
            #expect(onDisk == item.text.legend)
        }
    }

    // MARK: The maker

    @Test func theMakerAsksForTheLatestItemsAfterThePanelAndMakesTheirPages() async throws {
        let pages = Pages()
        let maker = pages.maker
        let stale = try await Self.item("a.png", legend: "Old words.")
        let fresh = try await Self.item("a.png", legend: "New words.")
        var asked: [[String]] = []
        pages.whileAsking = { #expect(asked.isEmpty, "not before the panel is answered") }
        await maker.make([stale], latest: { items in
            asked.append(items.map(\.text.legend))
            return [fresh]
        }, tell: { _ in })
        #expect(asked == [["Old words."]])
        #expect(pages.pages.map(\.legend) == ["New words."])
        // A cancelled panel asks for nothing.
        pages.whileAsking = nil
        pages.destination = nil
        await maker.make([stale], latest: { _ in asked.append(["again"]); return [stale] }, tell: { _ in })
        #expect(asked.count == 1)
    }

    private static func item(_ file: String, legend: String) async throws -> ShelfItem {
        let record = KeptRecord(
            name: "a", keptAt: Date(timeIntervalSince1970: 1_792_674_720), projectID: "p", projectName: "Assay development", sessionID: "s",
            sessionTitle: "Plate reader QC",
            figure: KeptFile(path: file, role: .figure, artifact: "a", version: "v-1", index: 1, of: nil, sha256: nil, bytes: 4_096),
            files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
        let result = KeptResult(folder: URL(fileURLWithPath: "/tmp/kept/Assay development/a", isDirectory: true), collection: "Assay development",
                                record: record, text: KeptText(legend: legend, claudeSaid: "", attribution: "", origin: ""))
        return ShelfRules.items(from: [result])[0]
    }
}
