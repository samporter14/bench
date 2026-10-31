// PaperModel.swift — the papers in the Shelf window (DESIGN.md, Shelf → Papers): which papers there are, the one
// shown, and every change to it, each written to its PAPER.md at once. The shape of a paper and its rules are
// PaperFile.swift's; the disk is `KeptDisk`'s. A paper only names kept folders: assigning, emptying, removing and
// relabelling a panel change PAPER.md and nothing else, so taking a figure out of a paper never touches its folder.
//
// The folders are the record. There is no index of papers and nothing cached between windows: the papers are read
// when the Papers page first shows and whenever the Shelf's folders are read again, and a change is made from the
// PAPER.md last read and written only if the file is still, byte for byte, that text. A paper changed in another app
// is read again and the change is not made ("PAPER.md was changed in another app…"). Writes go one at a time.
import AppKit
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "papers")

extension PaperRules {
    /// The legends file an export writes beside the figures.
    static let legendsFileName = "legends.md"
}

/// What a paper's slot holds, against the shelf as it is now.
enum PaperSlotState: Equatable {
    /// A label with no figure yet, or a letter skipped between two panels.
    case empty
    case filled(ShelfItem)
    /// The kept folder the paper names isn't on the shelf any more: moved, renamed or in the Trash. Said, never a crash.
    case broken(String)
}

/// One slot as the map draws it.
struct PaperSlot: Identifiable, Equatable {
    let label: PaperLabel
    /// The panel the paper holds for the label; nil for a letter skipped between two panels.
    let panel: PaperPanel?
    let state: PaperSlotState
    var id: String { label.text }
    var item: ShelfItem? { if case .filled(let item) = state { item } else { nil } }
}

/// A figure of the map: its heading and its slots, in order.
struct PaperFigureRow: Identifiable, Equatable {
    let figure: PaperFigure
    let slots: [PaperSlot]
    var id: PaperFigure { figure }
}

@MainActor
final class PaperModel: ObservableObject {
    enum State: Equatable {
        case idle, reading, ready
        case failed(String)
    }

    /// Every step that reaches outside the model, so the tests and the demo give their own.
    struct Dependencies {
        /// Where an export goes: a folder the person chooses; nil when they cancel.
        var chooseFolder: @MainActor (_ paperName: String) async -> URL?
        /// Draws the combined PDF (ShelfPDF.swift).
        var render: @Sendable (_ pages: [ShelfPDFPage], _ url: URL, _ title: String) async throws -> Void
        /// A text file's first words, for its page of the PDF.
        var words: @MainActor (_ file: URL) async -> String?
        /// Shows the export in Finder.
        var reveal: @MainActor (_ folder: URL) -> Void
        var now: @MainActor () -> Date
        var capsidVersion: String

        static func live(disk: KeptDisk) -> Dependencies {
            Dependencies(
                chooseFolder: { name in await PaperModel.folderPanel(paperName: name) },
                render: { pages, url, title in try await ShelfPDF.make(pages, to: url, title: title) },
                words: { url in (try? await disk.peek(url, limit: ShelfPDFMaker.textBytes)) ?? nil },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                now: { Date() },
                capsidVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.1")
        }
    }

    @Published private(set) var papers: [KeptPaper] = []
    @Published private(set) var state: State = .idle
    /// The paper shown, by its folder's path.
    @Published var selection: String?
    /// The last thing that went wrong, in a sentence, until the next change.
    @Published private(set) var problem: String?
    /// An export under way.
    @Published private(set) var exporting = false

    let disk: KeptDisk
    private let root: @MainActor () -> URL
    private var dependencies: Dependencies
    /// The one write at a time: each change waits for the one before.
    private var writing: Task<Void, Never>?

    init(disk: KeptDisk, root: @escaping @MainActor () -> URL, dependencies: Dependencies? = nil) {
        self.disk = disk
        self.root = root
        self.dependencies = dependencies ?? .live(disk: disk)
    }

    var selected: KeptPaper? { papers.first { $0.id == selection } ?? papers.first }

    // MARK: Reading

    /// Reads the papers again; the selection stays on its paper while it is there.
    func refresh() async {
        if papers.isEmpty { state = .reading }
        do {
            papers = try await disk.papers()
            state = .ready
            if let selection, !papers.contains(where: { $0.id == selection }) { self.selection = papers.first?.id }
            if selection == nil { selection = papers.first?.id }
        } catch {
            state = .failed(KeptDiskError.sentence(error))
        }
    }

    // MARK: The map

    /// The kept folder a shelf item is in, as a paper names it: "Assay development/z_prime_by_plate".
    func folderPath(of item: ShelfItem) -> String {
        PaperRules.folderPath(collection: item.result.folder.deletingLastPathComponent().lastPathComponent,
                              name: item.result.folder.lastPathComponent)
    }

    /// The panel a paper holds for `item` in `label`: its folder and its figure's ids, as they are now.
    func panel(for item: ShelfItem, label: PaperLabel) -> PaperPanel {
        PaperPanel(label: label, folder: folderPath(of: item), artifact: item.record.figure.artifact,
                   version: item.record.figure.version, file: item.fileName)
    }

    /// What a panel holds against the shelf: the item whose folders include the one named, else broken.
    func state(of panel: PaperPanel, items: [ShelfItem]) -> PaperSlotState {
        guard let folder = panel.folder else { return .empty }
        let url = root().appending(path: folder, directoryHint: .isDirectory)
        if let item = items.first(where: { $0.contains(folder: url) }) { return .filled(item) }
        return .broken(PaperRules.brokenSlot(folder: folder))
    }

    /// The map of a paper: each figure with its slots, gaps between letters drawn as empty slots.
    func figures(of paper: Paper, items: [ShelfItem]) -> [PaperFigureRow] {
        PaperRules.figures(paper.panels).map { group in
            PaperFigureRow(figure: group.figure, slots: group.slots.map { slot in
                switch slot {
                case .panel(let panel): PaperSlot(label: panel.label, panel: panel, state: state(of: panel, items: items))
                case .gap(let label): PaperSlot(label: label, panel: nil, state: .empty)
                }
            })
        }
    }

    /// The items a paper's slots hold, in label order: what Check reads and what an export copies.
    func items(of paper: Paper, items: [ShelfItem]) -> [ShelfItem] {
        paper.panels.compactMap { panel in
            if case .filled(let item) = state(of: panel, items: items) { item } else { nil }
        }
    }

    /// "3 of 5 panels filled", and the panels out of date when there are any.
    func summary(of paper: Paper, items: [ShelfItem], outOfDate: Int) -> (filled: String, outOfDate: String?) {
        let slots = figures(of: paper, items: items).flatMap(\.slots)
        let filled = slots.filter { $0.item != nil }.count
        return (PaperRules.missingSummary(filled: filled, slots: slots.count), PaperRules.outOfDateSummary(outOfDate))
    }

    /// The label "Add to Paper…" offers first: the next letter of the paper's last main figure, else 1A.
    func suggestedLabel(in paper: Paper?) -> PaperLabel {
        guard let paper, let last = paper.panels.filter({ !$0.label.supplementary }).map(\.label).max() else {
            return PaperLabel(supplementary: false, figure: 1, panel: "A")
        }
        return PaperRules.nextLabel(in: last.figureKey, after: paper.panels)
            ?? PaperLabel(supplementary: false, figure: PaperRules.nextFigure(supplementary: false, after: paper.panels).number, panel: "A")
    }

    // MARK: Changing

    /// Makes a new paper and shows it. Answers it, or nil with `problem` said.
    @discardableResult
    func create(named name: String) async -> KeptPaper? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        await writing?.value
        let paper = Paper(name: trimmed, createdAt: dependencies.now(), panels: [], capsid: dependencies.capsidVersion)
        do {
            let made = try await disk.createPaper(paper)
            problem = nil
            log.notice("Papers: made a paper")
            await refresh()
            selection = made.id
            return made
        } catch {
            problem = "Couldn\u{2019}t make the paper. \(KeptDiskError.sentence(error))"
            return nil
        }
    }

    /// Puts `item` in `label` of `paper`, replacing what the label held.
    func assign(_ item: ShelfItem, to label: PaperLabel, in paper: KeptPaper) {
        let panel = panel(for: item, label: label)
        change(paper) { PaperRules.assigning(panel, in: $0) }
    }

    /// Takes a panel off the paper, label and all. The kept folder is left as it is.
    func remove(_ label: PaperLabel, from paper: KeptPaper) {
        change(paper) { PaperRules.removing(label, from: $0) }
    }

    /// Leaves the label and takes its figure out. The kept folder is left as it is.
    func empty(_ label: PaperLabel, in paper: KeptPaper) {
        change(paper) { PaperRules.emptying(label, in: $0) }
    }

    /// An empty slot under a new label: "Add Panel" at the end of a figure, or a new figure.
    func addSlot(_ label: PaperLabel, to paper: KeptPaper) {
        change(paper) { panels in
            panels.contains { $0.label == label } ? panels : PaperRules.assigning(PaperPanel(label: label), in: panels)
        }
    }

    /// Relabel: onto a free or empty label it moves; onto a filled one the two trade places, so nothing is lost.
    func relabel(_ from: PaperLabel, to: PaperLabel, in paper: KeptPaper) {
        guard from != to else { return }
        change(paper) { panels in
            PaperRules.relabelling(from, to: to, in: panels) ?? PaperRules.swapping(from, to, in: panels)
        }
    }

    /// A slot dragged onto another: the two trade what they hold.
    func swap(_ a: PaperLabel, _ b: PaperLabel, in paper: KeptPaper) {
        guard a != b else { return }
        change(paper) { PaperRules.swapping(a, b, in: $0) }
    }

    /// Every change: made from the PAPER.md last read, written if the file is still that, one at a time. A file
    /// changed in another app meanwhile is read again and the change is not made, with a sentence.
    private func change(_ kept: KeptPaper, _ transform: @escaping ([PaperPanel]) -> [PaperPanel]) {
        let previous = writing
        writing = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            // What the last write left, not what the caller held: two quick changes both land.
            let current = papers.first { $0.id == kept.id } ?? kept
            var paper = current.paper
            paper.panels = transform(paper.panels)
            guard paper != current.paper else { return }
            do {
                let written = try await disk.replacePaper(at: current.folder, with: paper, lastRead: current.markdown)
                if let index = papers.firstIndex(where: { $0.id == written.id }) { papers[index] = written }
                problem = nil
            } catch KeptDiskError.changedOutside {
                problem = PaperModel.changedOutside
                await refresh()
            } catch {
                problem = "Couldn\u{2019}t save the paper. \(KeptDiskError.sentence(error))"
            }
        }
    }

    static let changedOutside = "PAPER.md was changed in another app, so Capsid read it again and didn\u{2019}t make that change. Make it again if you still want it."

    /// Waits for the writes asked for so far: for the tests, and before an export.
    func settle() async { await writing?.value }

    // MARK: Exporting

    /// Exports `paper` into a folder the person chooses: each filled panel's figure named for its label, in figure
    /// order, `legends.md` with each panel's legend, and one PDF of them all. `items` are the shelf's, read again
    /// (`latest`) so a legend typed a second ago is in. A panel that is empty or whose folder is gone is listed in the
    /// legends as missing and has no file. Answers the sentence to say, or nil when the person cancelled.
    func export(_ kept: KeptPaper, items: [ShelfItem], latest: @MainActor ([ShelfItem]) async -> [ShelfItem]) async -> String? {
        // Taken before the panel is asked for, so a second click while it comes up opens no second one.
        guard !exporting else { return nil }
        exporting = true
        defer { exporting = false }
        await settle()
        let paper = (papers.first { $0.id == kept.id } ?? kept).paper
        guard let parent = await dependencies.chooseFolder(paper.name) else { return nil }
        // Each filled panel's item, as the disk has it now.
        let held = paper.panels.compactMap { panel -> (PaperPanel, ShelfItem)? in
            if case .filled(let item) = state(of: panel, items: items) { (panel, item) } else { nil }
        }
        let fresh = await latest(held.map(\.1))
        let filled = zip(held.map(\.0), fresh).map { ($0, $1) }
        guard !filled.isEmpty else { return PaperModel.nothingToExport }
        let files = filled.map { panel, item in
            PaperExportPlan.File(source: item.fileURL, name: PaperRules.exportName(label: panel.label, name: item.title, fileName: item.fileName),
                                 bytes: item.record.figure.bytes)
        }
        let entries = paper.panels.map { panel -> PaperRules.LegendEntry in
            if let item = filled.first(where: { $0.0.label == panel.label })?.1 {
                return PaperRules.LegendEntry(label: panel.label, title: item.title, legend: item.text.legend, claudeSaid: item.text.claudeSaid,
                                              claudeIsLastAnswer: ShelfRules.isLastAnswer(item.text))
            }
            return PaperRules.LegendEntry(label: panel.label, title: panel.folder == nil ? "Empty" : (panel.file ?? "Missing"),
                                          legend: panel.folder == nil ? "" : PaperRules.brokenSlot(folder: panel.folder ?? ""),
                                          claudeSaid: "", claudeIsLastAnswer: false)
        }
        let plan = PaperExportPlan(parent: parent, name: PaperModel.exportFolderName(paper.name), files: files,
                                   legends: PaperRules.legends(paper: paper.name, entries))
        let folder: PaperExportFolder
        do {
            folder = try await disk.beginExport(plan, at: dependencies.now())
        } catch {
            return "Couldn\u{2019}t export \u{201C}\(paper.name)\u{201D}. \(KeptDiskError.sentence(error))"
        }
        // The PDF, a page for each panel, in figure order, titled with its label.
        var text: [String: String] = [:]
        for (_, item) in filled where ShelfPeek.proseExtensions.contains((item.fileName as NSString).pathExtension.lowercased()) {
            if let words = await dependencies.words(item.fileURL) { text[item.id] = words }
        }
        let pages = filled.map { panel, item in
            let page = ShelfPDFRules.page(for: item, text: text[item.id])
            return ShelfPDFPage(title: "\(panel.label.title) \u{00B7} \(page.title)", legend: page.legend, source: page.source,
                                picture: page.picture, tile: page.tile, fileName: page.fileName)
        }
        let pdf = folder.temp.appending(path: ShelfFileName.sanitized("\(paper.name).pdf"), directoryHint: .notDirectory)
        do {
            try await dependencies.render(pages, pdf, paper.name)
        } catch ShelfPDF.Failure.unreadable(let name) {
            await disk.abandonExport(folder)
            return ShelfPDFRules.couldntRead(name)
        } catch {
            await disk.abandonExport(folder)
            return "Couldn\u{2019}t make the PDF for \u{201C}\(paper.name)\u{201D}, so nothing was exported."
        }
        do {
            let landed = try await disk.finishExport(folder)
            log.notice("Papers: exported \(filled.count, privacy: .public) panels")
            dependencies.reveal(landed)
            let missing = paper.panels.count - filled.count
            return PaperModel.exported(filled.count, missing: missing, folder: landed.lastPathComponent)
        } catch {
            await disk.abandonExport(folder)
            return "Couldn\u{2019}t export \u{201C}\(paper.name)\u{201D}. \(KeptDiskError.sentence(error))"
        }
    }

    static let nothingToExport = "There\u{2019}s nothing to export yet: no panel of this paper holds a figure on your shelf."

    static func exportFolderName(_ paper: String) -> String { "\(paper) figures" }

    static func exported(_ count: Int, missing: Int, folder: String) -> String {
        let panels = count == 1 ? "1 panel" : "\(count) panels"
        let rest = missing == 0 ? "" : missing == 1 ? " 1 panel was empty or missing; legends.md says which." : " \(missing) panels were empty or missing; legends.md says which."
        return "Exported \(panels) to \u{201C}\(folder)\u{201D}.\(rest)"
    }

    /// The folder panel: where the export's folder goes, Downloads at first.
    static func folderPanel(paperName: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL.downloadsDirectory
        panel.prompt = "Export Here"
        panel.message = "Capsid makes a folder here, \u{201C}\(exportFolderName(paperName))\u{201D}, with each figure named for its panel, legends.md and one PDF."
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let done: @MainActor (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            if let window = (NSApp.keyWindow as? KeptWindow) ?? NSApp.windows.first(where: { $0 is KeptWindow && $0.isVisible }) {
                panel.beginSheetModal(for: window) { response in MainActor.assumeIsolated { done(response) } }
            } else {
                panel.begin { response in MainActor.assumeIsolated { done(response) } }
            }
        }
    }
}
