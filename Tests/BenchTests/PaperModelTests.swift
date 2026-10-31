// PaperModelTests.swift: a paper on the demo's made-up shelf (Kept/PaperModel.swift, the papers half of
// KeptDisk.swift): made, filled, emptied and relabelled, each change in its PAPER.md at once and none of them near a
// kept folder; a PAPER.md changed in another app is read again and not written over; a folder that has gone is a
// broken slot, not a crash; and an export is a folder of figures named for their panels, legends.md and a PDF.
// Everything is in a temporary folder; the PDF is drawn by a stand-in.
import Foundation
import Testing
@testable import Bench

@MainActor
struct PaperModelTests {
    private struct Rig {
        let root: URL
        let disk: KeptDisk
        let items: [ShelfItem]
        let papers: PaperModel
        let exports: URL
        var rendered: Rendered

        func item(_ file: String) throws -> ShelfItem { try #require(items.first { $0.fileName == file }) }
    }

    @MainActor final class Rendered {
        var titles: [String] = []
        var revealed: URL?
    }

    private func rig(chooses: Bool = true) async -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paper-model-\(UUID().uuidString)", isDirectory: true)
        let exports = FileManager.default.temporaryDirectory.appendingPathComponent("paper-export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let rendered = Rendered()
        let dependencies = PaperModel.Dependencies(
            chooseFolder: { _ in chooses ? exports : nil },
            render: { pages, url, _ in
                await MainActor.run { rendered.titles = pages.map(\.title) }
                try Data("%PDF-1.7 stand-in".utf8).write(to: url)
            },
            words: { _ in "Some words." },
            reveal: { rendered.revealed = $0 },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            capsidVersion: "1.2")
        let papers = PaperModel(disk: disk, root: { root }, dependencies: dependencies)
        return Rig(root: root, disk: disk, items: ShelfRules.items(from: index.results), papers: papers, exports: exports, rendered: rendered)
    }

    private func clean(_ rig: Rig) {
        try? FileManager.default.removeItem(at: rig.root)
        try? FileManager.default.removeItem(at: rig.exports)
    }

    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private func label(_ text: String) throws -> PaperLabel { try #require(PaperLabel(text)) }

    @Test func aPaperIsMadeFilledAndChangedInItsPaperMDAndNeverTouchesAKeptFolder() async throws {
        let rig = await rig()
        defer { clean(rig) }
        let made = try #require(await rig.papers.create(named: "Z\u{2032} assay paper"))
        #expect(made.folder.path == rig.root.appending(path: "Papers/Z\u{2032} assay paper").path)
        #expect(rig.papers.selection == made.id)

        let chart = try rig.item("z_prime_by_plate.png")
        let readme = chart.folder.appending(path: "README.md")
        let before = try Data(contentsOf: readme)
        let files = try FileManager.default.contentsOfDirectory(atPath: chart.folder.path).sorted()

        rig.papers.assign(chart, to: try label("1A"), in: made)
        rig.papers.assign(try rig.item("plate_7_heatmap.png"), to: try label("1C"), in: made)
        await rig.papers.settle()
        var onDisk = try #require(PaperFile.parse(try text(made.folder.appending(path: "PAPER.md"))))
        #expect(onDisk.panels.map(\.label.text) == ["1A", "1C"])
        #expect(onDisk.panels[0].folder == "Assay development/\(chart.folder.lastPathComponent)")
        #expect(onDisk.panels[0].artifact == chart.record.figure.artifact && onDisk.panels[0].version == chart.version)
        #expect(onDisk.panels[0].file == "z_prime_by_plate.png")

        // The map: 1B, skipped, is drawn as a slot, empty.
        let paper = try #require(rig.papers.selected)
        let rows = rig.papers.figures(of: paper.paper, items: rig.items)
        #expect(rows.map(\.figure.title) == ["Figure 1"])
        #expect(rows[0].slots.map(\.label.text) == ["1A", "1B", "1C"])
        #expect(rows[0].slots[1].state == .empty && rows[0].slots[1].panel == nil)
        #expect(rows[0].slots[0].item?.id == chart.id)
        #expect(rig.papers.summary(of: paper.paper, items: rig.items, outOfDate: 0) == ("2 of 3 panels filled", nil))

        // Relabelled onto a free label it moves; onto a filled one the two trade places.
        rig.papers.relabel(try label("1C"), to: try label("1B"), in: paper)
        rig.papers.relabel(try label("1B"), to: try label("1A"), in: paper)
        await rig.papers.settle()
        onDisk = try #require(PaperFile.parse(try text(made.folder.appending(path: "PAPER.md"))))
        #expect(onDisk.panels.map { "\($0.label.text)=\($0.file ?? "-")" } == ["1A=plate_7_heatmap.png", "1B=z_prime_by_plate.png"])

        // Emptied, the label stays; removed, it goes. The kept folder is as it was, every byte.
        rig.papers.empty(try label("1B"), in: paper)
        rig.papers.remove(try label("1A"), from: paper)
        await rig.papers.settle()
        onDisk = try #require(PaperFile.parse(try text(made.folder.appending(path: "PAPER.md"))))
        #expect(onDisk.panels == [PaperPanel(label: try label("1B"))])
        #expect(try Data(contentsOf: readme) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: chart.folder.path).sorted() == files)
        #expect(rig.papers.problem == nil)

        // Read again from the disk, the paper is the same.
        await rig.papers.refresh()
        #expect(rig.papers.papers.map(\.paper) == [onDisk])
    }

    @Test func aPaperChangedInAnotherAppIsReadAgainAndNotWrittenOver() async throws {
        let rig = await rig()
        defer { clean(rig) }
        let made = try #require(await rig.papers.create(named: "Draft"))
        let url = made.folder.appending(path: "PAPER.md")
        // Another app adds a panel.
        var theirs = made.paper
        theirs.panels = [PaperPanel(label: try label("3"))]
        let edited = PaperFile.render(theirs)
        try Data(edited.utf8).write(to: url)

        rig.papers.assign(try rig.item("z_prime_by_plate.png"), to: try label("1A"), in: made)
        await rig.papers.settle()
        #expect(rig.papers.problem == PaperModel.changedOutside)
        #expect(try text(url) == edited, "their file, untouched")
        #expect(rig.papers.selected?.paper.panels.map(\.label.text) == ["3"], "and read again")

        // The next change is made on what was read.
        rig.papers.assign(try rig.item("z_prime_by_plate.png"), to: try label("1A"), in: try #require(rig.papers.selected))
        await rig.papers.settle()
        #expect(rig.papers.problem == nil)
        #expect(PaperFile.parse(try text(url))?.panels.map(\.label.text) == ["1A", "3"])
    }

    @Test func aFolderThatHasGoneIsABrokenSlotWithItsSentence() async throws {
        let rig = await rig()
        defer { clean(rig) }
        let gone = PaperPanel(label: try label("2A"), folder: "Assay development/standard_curve_old", file: "standard_curve.png")
        let state = rig.papers.state(of: gone, items: rig.items)
        #expect(state == .broken(PaperRules.brokenSlot(folder: "Assay development/standard_curve_old")))
        #expect(rig.papers.state(of: PaperPanel(label: try label("2B")), items: rig.items) == .empty)
        // A kept folder moved to the Trash after the paper named it: broken too, and no item for Check or the export.
        let chart = try rig.item("z_prime_by_plate.png")
        let named = rig.papers.panel(for: chart, label: try label("1A"))
        #expect(rig.papers.state(of: named, items: rig.items) == .filled(chart))
        let others = rig.items.filter { $0.id != chart.id }
        #expect(rig.papers.state(of: named, items: others) == .broken(PaperRules.brokenSlot(folder: try #require(named.folder))))
        #expect(rig.papers.items(of: Paper(name: "P", createdAt: Date(), panels: [named, gone], capsid: "1"), items: others).isEmpty)
        // A paper whose PAPER.md isn't one Capsid wrote is not shown, and the others still are.
        let papers = rig.root.appending(path: "Papers/Not ours", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: papers, withIntermediateDirectories: true)
        try Data("---\nname: something else\n---\n".utf8).write(to: papers.appending(path: "PAPER.md"))
        _ = await rig.papers.create(named: "Ours")
        await rig.papers.refresh()
        #expect(rig.papers.papers.map(\.paper.name) == ["Ours"])
        #expect(rig.papers.state == .ready)
    }

    @Test func anExportIsTheFiguresInOrderNamedForTheirPanelsLegendsAndOnePDF() async throws {
        let rig = await rig()
        defer { clean(rig) }
        let made = try #require(await rig.papers.create(named: "Z\u{2032} assay paper"))
        let kept = try #require(rig.items.first { $0.record.keepsDataOrCode })
        rig.papers.assign(kept, to: try label("2B"), in: made)
        rig.papers.assign(try rig.item("z_prime_by_plate.png"), to: try label("1A"), in: made)
        rig.papers.assign(try rig.item("plate_7_heatmap.png"), to: try label("S1A"), in: made)
        rig.papers.addSlot(try label("2A"), to: made)
        await rig.papers.settle()
        let paper = try #require(rig.papers.selected)

        let sentence = try #require(await rig.papers.export(paper, items: rig.items, latest: { $0 }))
        let folder = rig.exports.appending(path: "Z\u{2032} assay paper figures", directoryHint: .isDirectory)
        #expect(sentence == PaperModel.exported(3, missing: 1, folder: folder.lastPathComponent))
        #expect(rig.rendered.revealed?.path == folder.path)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["Fig 1A \u{00B7} z_prime_by_plate.png", "Fig 2B \u{00B7} \(kept.title).png", "Fig S1A \u{00B7} plate_7_heatmap.png",
                          "Z\u{2032} assay paper.pdf", "legends.md"].sorted())
        // The figures are the kept files, byte for byte.
        #expect(try Data(contentsOf: folder.appending(path: "Fig 1A \u{00B7} z_prime_by_plate.png")) == Data(contentsOf: try rig.item("z_prime_by_plate.png").fileURL))
        // The PDF's pages in figure order, each titled with its label.
        #expect(rig.rendered.titles.map { String($0.prefix(while: { $0 != "\u{00B7}" })) } == ["Fig 1A ", "Fig 2B ", "Fig S1A "])
        // The legends: the person's own for Fig 2B, Claude's words where there is no legend, the empty panel said.
        let legends = try text(folder.appending(path: "legends.md"))
        #expect(legends.hasPrefix("# Z\u{2032} assay paper\n\n## Figure 1\n\n**Fig 1A**"))
        #expect(legends.contains(kept.text.legend))
        #expect(legends.contains("**Fig 2A** \u{00B7} Empty\n\n_No legend yet._"))
        #expect(legends.contains("## Supplementary Figure S1"))
        // Nothing hidden is left beside it, and a second export gets a name of its own.
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.exports.path).filter { $0.hasPrefix(".") }.isEmpty)
        _ = await rig.papers.export(paper, items: rig.items, latest: { $0 })
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.exports.path).filter { !$0.hasPrefix(".") }.count == 2)
    }

    @Test func anExportCancelledOrOfNothingWritesNothing() async throws {
        var rig = await rig(chooses: false)
        defer { clean(rig) }
        let made = try #require(await rig.papers.create(named: "Draft"))
        rig.papers.assign(try rig.item("z_prime_by_plate.png"), to: try label("1A"), in: made)
        await rig.papers.settle()
        #expect(await rig.papers.export(try #require(rig.papers.selected), items: rig.items, latest: { $0 }) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.exports.path).isEmpty)
        clean(rig)
        rig = await self.rig()
        let empty = try #require(await rig.papers.create(named: "Empty"))
        #expect(await rig.papers.export(empty, items: rig.items, latest: { $0 }) == PaperModel.nothingToExport)
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.exports.path).isEmpty)
    }

    @Test func addToPaperSuggestsTheNextLetterOfTheLastMainFigure() throws {
        let papers = PaperModel(disk: KeptDisk(root: { URL(fileURLWithPath: "/nonexistent") }), root: { URL(fileURLWithPath: "/nonexistent") })
        #expect(papers.suggestedLabel(in: nil).text == "1A")
        let panels = [PaperPanel(label: try label("1A")), PaperPanel(label: try label("2B")), PaperPanel(label: try label("S1A"))]
        #expect(papers.suggestedLabel(in: Paper(name: "P", createdAt: Date(), panels: panels, capsid: "1")).text == "2C")
    }

    @Test func thePapersFolderIsNotAProjectOfTheShelf() async throws {
        let rig = await rig()
        defer { clean(rig) }
        _ = await rig.papers.create(named: "Draft")
        let index = KeptIndex(disk: rig.disk, root: { rig.root })
        await index.refreshAndWait()
        #expect(!index.results.contains { $0.collection == PaperFile.folderName })
        #expect(ShelfRules.items(from: index.results).count == rig.items.count)
    }
}
