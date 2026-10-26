// ShelfClaudeLegendTests.swift — Claude's own legend file put into a shelved figure's legend (Kept/ShelfClaudeLegend.swift,
// ShelfLegend.swift, KeptDisk.listFile), driven whole on a scratch Kept folder and made-up reads: the files of the answer
// that showed the figure are looked up once; using the offer puts the legend in through the field's own save and copies
// Claude's file beside the figure, listed in the README as role `legend`, with every other byte of the README as it was
// (a README with words under its title, with Windows line ends, with a byte order mark); a written legend is asked about
// first; Undo puts the legend back unless it was edited since; a README changed in another app is never written over; and
// a file that can't be had changes nothing. Nothing here talks to Claude Science or touches the real Kept folder.
import Foundation
import Testing
@testable import Bench

private typealias Rules = ShelfClaudeLegendRules

enum ClaudeLegendMade {
    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000c1", projectID: "p-3", projectName: "Assay development",
                                       title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)
    static let artifact = "bbbbbbbb-0000-4000-8000-000000000031"
    static let figure = "aaaaaaaa-0000-4000-8000-000000000201"
    static let legends = "aaaaaaaa-0000-4000-8000-000000000202"
    static let sibling = "aaaaaaaa-0000-4000-8000-000000000203"
    static let other = "aaaaaaaa-0000-4000-8000-000000000204"
    static let base = Date(timeIntervalSince1970: 1_800_000_000)
    static let row = 12
    static let figureName = "fig2_edge_effects.png"

    /// Claude's legend file: a section for each of three figures.
    static let legendsText = """
        # Figure legends

        ## Figure 1

        **Plate map.** Eight plates, sixteen rows.

        ## Figure 2

        **Edge effects.** Wells in column 1 read low on every plate.

        ## Figure 3

        **Recovery.** Spiked wells came back at 94%.
        """
    /// What the Figure 2 section comes to.
    static let figureTwo = "Edge effects. Wells in column 1 read low on every plate."
    static let siblingText = "The edge reads low on plates 3 and 7.\n"

    static func entry(_ name: String) -> ArtifactEntry {
        ArtifactEntry(version: figure, artifact: artifact, name: name, mime: name.hasSuffix(".md") ? "text/markdown" : "image/png",
                      size: 14, at: base)
    }

    static func historyFile(_ v: String, _ name: String, size: Int? = nil) -> HistoryFile {
        HistoryFile(v: v, a: "bbbbbbbb-0000-4000-8000-0000000003" + v.suffix(2), name: name,
                    kind: ArtifactKind.classify(name: name, mime: nil), size: size)
    }

    static let legendsFile = historyFile(legends, "FIGURE_LEGENDS_final.md", size: legendsText.utf8.count)
    static let siblingFile = historyFile(sibling, "fig2_edge_effects.md", size: siblingText.utf8.count)
}

/// Claude Science, made up: the figure, Claude's legend files, and the files of the answer.
@MainActor
final class ClaudeLegendScience {
    var factsName = ClaudeLegendMade.figureName
    var files: [HistoryFile]? = [ClaudeLegendMade.legendsFile]
    var bytes: [String: Data] = [ClaudeLegendMade.figure: Data("made-up figure".utf8), ClaudeLegendMade.legends: Data(ClaudeLegendMade.legendsText.utf8),
                                 ClaudeLegendMade.sibling: Data(ClaudeLegendMade.siblingText.utf8)]
    var downloadFail: [String: ShelfTransferResult] = [:]
    var showing: ShowingRead = .found(ShowingMessage(i: ClaudeLegendMade.row, at: ClaudeLegendMade.base, text: "Here is the figure and its legends.", how: .inline, v: ClaudeLegendMade.figure))
    var downloadDelay: Duration = .zero
    private(set) var downloads: [String] = []
    private(set) var fileCalls: [Int] = []

    func read(_ read: ArtifactRead) async -> ShelfTransferResult {
        switch read {
        case .facts(let v):
            let data = bytes[v] ?? Data()
            return .answered(.facts(ArtifactFacts(v: v, a: ClaudeLegendMade.artifact, n: 1, name: factsName, mime: "image/png", size: data.count, at: ClaudeLegendMade.base,
                                                  sha: KeptDisk.sha256(of: data), isUpload: false, code: nil, codeCut: false, environment: nil)))
        case .download(let v):
            downloads.append(v)
            if downloadDelay > .zero { try? await Task.sleep(for: downloadDelay) }
            if let failure = downloadFail[v] { return failure }
            guard let data = bytes[v] else { return .answered(.missing) }
            return .answered(.bytes(data))
        default:
            return .answered(.unreadable)
        }
    }

    func answerFiles(_ row: Int) -> [HistoryFile]? {
        fileCalls.append(row)
        return files
    }
}

/// How an editor or another app left a README: all, some or none of these shapes (supported since 2026-10-24).
struct ClaudeLegendReadmeShape: Sendable, CustomTestStringConvertible {
    var words = false
    var windows = false
    var mark = false

    var testDescription: String {
        [words ? "words under the title" : nil, windows ? "Windows line ends" : nil, mark ? "a byte order mark" : nil]
            .compactMap { $0 }.joined(separator: ", ").nonEmpty ?? "a plain README"
    }

    static let all: [ClaudeLegendReadmeShape] = [.init(), .init(words: true), .init(windows: true), .init(mark: true),
                                                 .init(words: true, windows: true, mark: true)]
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

@MainActor
final class ClaudeLegendRig {
    let science = ClaudeLegendScience()
    let scratch: URL
    let root: URL
    let disk: KeptDisk
    let index: KeptIndex
    let shelf: Shelf
    let model: ShelfModel
    private let settings = ScratchDefaults.make(prefix: "capsid-tests-claude-legend")

    init() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-claude-legend-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.scratch = scratch
        self.root = root
        let disk = KeptDisk(root: { root })
        self.disk = disk
        index = KeptIndex(disk: disk, root: { root })
        let science = self.science, defaults = settings.defaults
        shelf = Shelf(index: index, dependencies: {
            ShelfDependencies(
                keep: KeepDependencies(
                    read: { await science.read($0) },
                    showing: { _, _, _ in science.showing },
                    lastAnswer: { _ in KeepAnswer(text: "Last words of the session.", at: ClaudeLegendMade.base, how: nil, isFallback: true) },
                    thumbnails: ShelfThumbnails(),
                    disk: disk,
                    defaults: defaults,
                    root: { root },
                    scienceVersion: { "0.1.70" },
                    capsidVersion: "1.0",
                    now: { ClaudeLegendMade.base },
                    didKeep: { _ in }),
                question: { _, _ in nil },
                answerFiles: { _, row in science.answerFiles(row) })
        })
        model = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining), legendDelay: .seconds(60))
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        settings.discard()
    }

    /// Puts the figure on the shelf by the real add and leaves its README in `shape`.
    func shelve(_ shape: ClaudeLegendReadmeShape = .init(), name: String = ClaudeLegendMade.figureName) async throws -> ShelfItem {
        science.factsName = name
        guard case .added(let placement) = await shelf.add(ShelfSource(session: ClaudeLegendMade.session, entry: ClaudeLegendMade.entry(name))) else {
            Issue.record("The figure wasn't shelved")
            throw CancellationError()
        }
        let url = placement.folder.appending(path: "README.md", directoryHint: .notDirectory)
        var text = try String(contentsOf: url, encoding: .utf8)
        if shape.words {
            text = text.replacingOccurrences(of: "## Your legend\n", with: "Words I wrote under the title.\n\n## Your legend\n")
        }
        if shape.windows { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        try ((shape.mark ? byteOrderMark : Data()) + Data(text.utf8)).write(to: url)
        await index.refreshAndWait()
        return try item()
    }

    func item() throws -> ShelfItem { try #require(model.items.first) }

    func readmeURL(_ item: ShelfItem) -> URL { item.folder.appending(path: "README.md", directoryHint: .notDirectory) }
    func readmeBytes(_ item: ShelfItem) throws -> Data { try Data(contentsOf: readmeURL(item)) }
    func parsed(_ item: ShelfItem) throws -> (record: KeptRecord, text: KeptText) {
        let data = try readmeBytes(item)
        return try #require(KeptReadme.parse(String(decoding: data.starts(with: byteOrderMark) ? data.dropFirst(3) : data[...], as: UTF8.self)))
    }

    func folderFiles(_ item: ShelfItem) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: item.folder.path).sorted()
    }

    /// Looks, and answers the best candidate.
    func look(_ item: ShelfItem) async throws -> ShelfClaudeLegend.Candidate {
        await model.claudeLegend.look(at: item)
        return try #require(model.claudeLegend.candidates(for: item).first)
    }

    /// The README as it should be after Claude's `legend` went in with `file` listed: the same functions that write a
    /// legend and a file list, applied to the README as it was, with its byte order mark put back.
    func expected(from original: Data, legend: String, listing file: KeptFile?) throws -> Data {
        let marked = original.starts(with: byteOrderMark)
        let text = String(decoding: marked ? original.dropFirst(3) : original[...], as: UTF8.self)
        var result = try #require(KeptReadme.replacingLegend(in: text, with: legend))
        if let file {
            let record = try #require(KeptReadme.parse(text)).record
            result = try #require(KeptReadme.updating(result, files: record.files + [file], missing: record.missing))
        }
        return (marked ? byteOrderMark : Data()) + Data(result.utf8)
    }

    func legendRow(_ name: String, _ v: String, bytes: Data) -> KeptFile {
        KeptFile(path: name, role: .legend, artifact: ClaudeLegendMade.historyFile(v, name).a, version: v, index: nil, of: nil,
                 sha256: KeptDisk.sha256(of: bytes), bytes: bytes.count)
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

private func count(_ needle: [UInt8], in data: Data) -> Int {
    let bytes = [UInt8](data)
    guard bytes.count >= needle.count else { return 0 }
    return (0...(bytes.count - needle.count)).reduce(0) { total, i in bytes[i..<(i + needle.count)].elementsEqual(needle) ? total + 1 : total }
}

@MainActor
struct ShelfClaudeLegendTests {
    // MARK: Looking

    @Test func theFilesOfTheAnswerThatShowedTheFigureAreLookedUpOnceByItsRow() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        rig.science.files = [ClaudeLegendMade.historyFile("aaaaaaaa-0000-4000-8000-000000000299", "z_prime.csv"), ClaudeLegendMade.siblingFile, ClaudeLegendMade.legendsFile]
        let item = try await rig.shelve()
        #expect(item.record.sourceRow == ClaudeLegendMade.row)

        await rig.model.claudeLegend.look(at: item)
        await rig.model.claudeLegend.look(at: item)
        #expect(rig.science.fileCalls == [ClaudeLegendMade.row])
        #expect(rig.model.claudeLegend.candidates(for: item).map(\.name) == ["fig2_edge_effects.md", "FIGURE_LEGENDS_final.md"])
        #expect(rig.model.claudeLegend.offer(for: item, legend: "")?.title == "Use Claude\u{2019}s legend")
        #expect(rig.model.claudeLegend.offer(for: item, legend: "Mine.")?.title == "Replace with Claude\u{2019}s legend\u{2026}")
    }

    @Test func aFigureWhoseAnswerWasNotFoundHasNoOfferAndNothingIsRead() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        rig.science.showing = .notFound
        let item = try await rig.shelve()
        #expect(item.record.sourceRow == nil)
        await rig.model.claudeLegend.look(at: item)
        #expect(rig.science.fileCalls.isEmpty)
        #expect(rig.model.claudeLegend.offer(for: item, legend: "") == nil)
    }

    @Test func aDocumentOnTheShelfIsNotLookedUp() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve(name: "notes.md")
        #expect(item.kind == .document)
        await rig.model.claudeLegend.look(at: item)
        #expect(rig.science.fileCalls.isEmpty && rig.model.claudeLegend.offer(for: item, legend: "") == nil)
    }

    @Test func aPageThatCouldNotBeReadIsAskedAgainAndAnswerWithNoLegendFileIsNot() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        rig.science.files = nil
        let item = try await rig.shelve()
        await rig.model.claudeLegend.look(at: item)
        #expect(rig.model.claudeLegend.offer(for: item, legend: "") == nil)
        rig.science.files = [ClaudeLegendMade.historyFile("aaaaaaaa-0000-4000-8000-000000000299", "z_prime.csv")]
        await rig.model.claudeLegend.look(at: item)
        await rig.model.claudeLegend.look(at: item)
        #expect(rig.science.fileCalls.count == 2)
        #expect(rig.model.claudeLegend.offer(for: item, legend: "") == nil)
    }

    // MARK: Using it, and the README

    @Test(arguments: ClaudeLegendReadmeShape.all) func claudesLegendGoesInAndItsFileBesideTheFigureWhateverShapeTheReadmeIsIn(shape: ClaudeLegendReadmeShape) async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve(shape)
        let original = try rig.readmeBytes(item)
        let candidate = try await rig.look(item)

        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)

        // The README: the legend and the file list changed, every other byte as it was.
        let bytes = Data(ClaudeLegendMade.legendsText.utf8)
        let row = rig.legendRow("FIGURE_LEGENDS_final.md", ClaudeLegendMade.legends, bytes: bytes)
        let after = try rig.readmeBytes(item)
        #expect(after == (try rig.expected(from: original, legend: ClaudeLegendMade.figureTwo, listing: row)))
        #expect(after.starts(with: byteOrderMark) == shape.mark)
        if shape.mark { #expect(!after.dropFirst(3).starts(with: byteOrderMark)) }
        if shape.windows {
            #expect(count([0x0A], in: after) == count([0x0D, 0x0A], in: after), "every line end is still a Windows one")
        } else {
            #expect(count([0x0D], in: after) == 0)
        }
        if shape.words { #expect(String(decoding: after, as: UTF8.self).contains("Words I wrote under the title.")) }

        // What it says, and what is beside the figure.
        let read = try rig.parsed(item)
        #expect(read.text.legend == ClaudeLegendMade.figureTwo)
        #expect(read.record.files == [row])
        #expect(read.record.files.first?.role == .legend && read.record.figure == item.record.figure)
        #expect(try rig.folderFiles(item) == ["FIGURE_LEGENDS_final.md", "README.md", ClaudeLegendMade.figureName])
        #expect(try Data(contentsOf: item.folder.appending(path: "FIGURE_LEGENDS_final.md")) == bytes)
    }

    @Test func thePillSaysWhichPartWasChosenAndOffersUndo() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)

        let note = try #require(rig.model.note)
        #expect(note.sentence == "Put in Claude\u{2019}s legend for \u{201C}Figure 2\u{201D} from FIGURE_LEGENDS_final.md. The file is beside the figure.")
        #expect(note.hasUndo && note.legend?.before == "" && note.legend?.put == ClaudeLegendMade.figureTwo)
        // The offer waits while the field holds exactly what was put in.
        let shown = try rig.item()
        #expect(rig.model.claudeLegend.offer(for: shown, legend: ClaudeLegendMade.figureTwo) == nil)
    }

    @Test func aFileWithNoSectionForTheFigureIsUsedWholeAndTheItemKeepsOfferingKeepWithDataAndCode() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve(name: "plate_map.png")
        let candidate = try await rig.look(item)
        #expect(item.canKeepWithDataAndCode)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)

        let whole = ShelfClaudeLegendRules.unbolded(ShelfClaudeLegendRules.normalized(ClaudeLegendMade.legendsText))
        #expect(try rig.parsed(item).text.legend == whole)
        #expect(rig.model.note?.sentence == "Put in all of FIGURE_LEGENDS_final.md, which has no section for plate_map.png. The file is beside the figure.")
        // A legend file beside the figure is not data and code: Keep with Data and Code… stays, and the folder is not the richer one.
        let after = try rig.item()
        #expect(after.hasMore && after.canKeepWithDataAndCode && !after.record.keepsDataOrCode)
    }

    @Test func aLegendFileIsNotWhatMakesAFolderTheRicherOfTwoForTheSameFigure() throws {
        let light = KeptResult(folder: URL(filePath: "/tmp/kept-test/A/light", directoryHint: .isDirectory), collection: "A",
                               record: record(files: [KeptFile(path: "legend.md", role: .legend, artifact: nil, version: "v-l", index: nil, of: nil,
                                                               sha256: nil, bytes: 5)], at: 100),
                               text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
        let rich = KeptResult(folder: URL(filePath: "/tmp/kept-test/A/rich", directoryHint: .isDirectory), collection: "A",
                              record: record(files: [KeptFile(path: "data/plates.csv", role: .data, artifact: nil, version: "v-d", index: nil, of: nil,
                                                              sha256: nil, bytes: 5)], at: 50),
                              text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
        // The legend-only folder is newer, and still not the one shown.
        let items = ShelfRules.items(from: [light, rich])
        #expect(items.count == 1 && items[0].folder.lastPathComponent == "rich")
        #expect(!ShelfItem(result: light, others: []).record.keepsDataOrCode && ShelfItem(result: rich, others: []).record.keepsDataOrCode)
        #expect(ShelfItem(result: light, others: []).canKeepWithDataAndCode && !ShelfItem(result: rich, others: []).canKeepWithDataAndCode)
    }

    private func record(files: [KeptFile], at seconds: TimeInterval) -> KeptRecord {
        KeptRecord(name: "plate map", keptAt: Date(timeIntervalSince1970: seconds), projectID: "p", projectName: "Assay development",
                   sessionID: "s", sessionTitle: "Plate reader QC",
                   figure: KeptFile(path: "plate_map.png", role: .figure, artifact: "a", version: "v-fig", index: 1, of: nil, sha256: nil, bytes: 3),
                   files: files, missing: [], claudeScience: "0.1.70", capsid: "1.0")
    }

    @Test func aLegendThatIsAlreadyThereIsNotWrittenAgainButItsFileIsStillListed() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        // The person has already written exactly these words.
        let read = try await rig.disk.readme(at: item.folder)
        _ = try await rig.disk.replaceLegend(at: item.folder, with: ClaudeLegendMade.figureTwo, lastRead: read.markdown)
        await rig.index.refreshAndWait()
        let shown = try rig.item()

        await rig.model.useClaudeLegend(candidate, for: shown, confirmed: true)
        #expect(try rig.parsed(shown).text.legend == ClaudeLegendMade.figureTwo)
        #expect(try rig.parsed(shown).record.files.map(\.path) == ["FIGURE_LEGENDS_final.md"])
        // Nothing changed in the legend, so there is nothing to undo.
        #expect(rig.model.note?.hasUndo == false)
    }

    // MARK: A written legend

    @Test func aWrittenLegendIsAskedAboutFirstAndNothingIsTouchedUntilAnswered() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        let first = try await rig.disk.readme(at: item.folder)
        _ = try await rig.disk.replaceLegend(at: item.folder, with: "Z\u{2032} per plate; plate 7 re-run.", lastRead: first.markdown)
        await rig.index.refreshAndWait()
        let written = try rig.item()
        let before = try rig.readmeBytes(written)

        let editor = rig.model.legendEditor(for: written)
        let asked = await rig.model.claudeLegend.use(candidate, for: written, editor: editor, confirmed: false)
        #expect(asked == .needsConfirmation)
        #expect(try rig.readmeBytes(written) == before)
        #expect(!rig.science.downloads.contains(ClaudeLegendMade.legends), "nothing was fetched before the answer")
        #expect(try rig.folderFiles(written) == ["README.md", ClaudeLegendMade.figureName])
        #expect(rig.model.note == nil)

        // The model says nothing either when it has to ask.
        await rig.model.useClaudeLegend(candidate, for: written, confirmed: false)
        #expect(rig.model.note == nil && !rig.science.downloads.contains(ClaudeLegendMade.legends))

        // Answered: replaced, with Undo.
        await rig.model.useClaudeLegend(candidate, for: written, confirmed: true)
        #expect(try rig.parsed(written).text.legend == ClaudeLegendMade.figureTwo)
        #expect(rig.model.note?.legend?.before == "Z\u{2032} per plate; plate 7 re-run.")
        #expect(try rig.folderFiles(written) == ["FIGURE_LEGENDS_final.md", "README.md", ClaudeLegendMade.figureName])
    }

    @Test func wordsTypedButNotYetSavedCountAsWrittenToo() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        let editor = rig.model.legendEditor(for: item)
        await editor.show()
        editor.legend = "Typed a moment ago."
        let asked = await rig.model.claudeLegend.use(candidate, for: item, editor: editor, confirmed: false)
        #expect(asked == .needsConfirmation && editor.legend == "Typed a moment ago.")
    }

    // MARK: Undo

    @Test func undoPutsTheLegendBackAndTheCopyOfClaudesFileStays() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let original = try rig.readmeBytes(item)
        let candidate = try await rig.look(item)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)

        rig.model.undoNote()
        try await until("the legend to go back") { rig.model.note?.sentence == Rules.undone }
        let bytes = Data(ClaudeLegendMade.legendsText.utf8)
        let row = rig.legendRow("FIGURE_LEGENDS_final.md", ClaudeLegendMade.legends, bytes: bytes)
        #expect(try rig.readmeBytes(item) == (try rig.expected(from: original, legend: "", listing: row)))
        #expect(try rig.parsed(item).text.legend == "")
        // The file stays, listed: nothing in a kept folder is deleted.
        #expect(try rig.folderFiles(item).contains("FIGURE_LEGENDS_final.md"))
        #expect(try rig.parsed(item).record.files.count == 1)
        // The offer is back.
        let shown = try rig.item()
        #expect(rig.model.claudeLegend.offer(for: shown, legend: "")?.title == "Use Claude\u{2019}s legend")
    }

    @Test func undoOfAReplacementBringsBackTheWordsThatWereWritten() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        let first = try await rig.disk.readme(at: item.folder)
        _ = try await rig.disk.replaceLegend(at: item.folder, with: "Z\u{2032} per plate;\nplate 7 re-run.", lastRead: first.markdown)
        await rig.index.refreshAndWait()
        let written = try rig.item()
        await rig.model.useClaudeLegend(candidate, for: written, confirmed: true)
        #expect(try rig.parsed(written).text.legend == ClaudeLegendMade.figureTwo)

        rig.model.undoNote()
        try await until("the legend to go back") { rig.model.note?.sentence == Rules.undone }
        #expect(try rig.parsed(written).text.legend == "Z\u{2032} per plate;\nplate 7 re-run.")
    }

    @Test func undoLeavesALegendThatWasEditedSince() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)

        let editor = rig.model.legendEditor(for: item)
        await editor.show()
        editor.legend = ClaudeLegendMade.figureTwo + " I added the plate numbers."
        await editor.settle()
        rig.model.undoNote()
        try await until("the sentence") { rig.model.note?.sentence == Rules.editedSince }
        #expect(try rig.parsed(item).text.legend == ClaudeLegendMade.figureTwo + " I added the plate numbers.")
        #expect(editor.legend == ClaudeLegendMade.figureTwo + " I added the plate numbers.")
    }

    // MARK: The file, once

    @Test func theFileIsCopiedAndListedOnceWhateverHowOftenItsLegendIsUsed() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
        rig.model.undoNote()
        try await until("the legend to go back") { rig.model.note?.sentence == Rules.undone }
        let shown = try rig.item()
        await rig.model.useClaudeLegend(candidate, for: shown, confirmed: false)

        let read = try rig.parsed(item)
        #expect(read.record.files.map(\.path) == ["FIGURE_LEGENDS_final.md"])
        #expect(try rig.folderFiles(item) == ["FIGURE_LEGENDS_final.md", "README.md", ClaudeLegendMade.figureName])
        // The second time the sentence says nothing of the file.
        #expect(rig.model.note?.sentence == "Put in Claude\u{2019}s legend for \u{201C}Figure 2\u{201D} from FIGURE_LEGENDS_final.md.")
    }

    @Test func anotherLegendFileIsListedBesideTheFirstAndTheSameNameWithOtherBytesGetsANumber() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        rig.science.files = [ClaudeLegendMade.legendsFile, ClaudeLegendMade.siblingFile]
        let item = try await rig.shelve()
        await rig.model.claudeLegend.look(at: item)
        let found = rig.model.claudeLegend.candidates(for: item)
        #expect(found.map(\.name) == ["fig2_edge_effects.md", "FIGURE_LEGENDS_final.md"])

        await rig.model.useClaudeLegend(found[1], for: item, confirmed: false)
        let shown = try rig.item()
        await rig.model.useClaudeLegend(found[0], for: shown, confirmed: true)
        #expect(try rig.parsed(item).text.legend == "The edge reads low on plates 3 and 7.")
        #expect(try rig.parsed(item).record.files.map(\.path) == ["FIGURE_LEGENDS_final.md", "fig2_edge_effects.md"])

        // The same name from another version of the file, with other bytes: a number, never a replacement.
        rig.science.bytes[ClaudeLegendMade.other] = Data("Another version of the legends.\n".utf8)
        let again = ShelfClaudeLegend.Candidate(file: ClaudeLegendMade.historyFile(ClaudeLegendMade.other, "FIGURE_LEGENDS_final.md"), match: .legend)
        let latest = try rig.item()
        await rig.model.useClaudeLegend(again, for: latest, confirmed: true)
        #expect(try rig.parsed(item).record.files.map(\.path) == ["FIGURE_LEGENDS_final.md", "fig2_edge_effects.md", "FIGURE_LEGENDS_final 2.md"])
        #expect(try Data(contentsOf: item.folder.appending(path: "FIGURE_LEGENDS_final.md")) == Data(ClaudeLegendMade.legendsText.utf8))
        #expect(try Data(contentsOf: item.folder.appending(path: "FIGURE_LEGENDS_final 2.md")) == Data("Another version of the legends.\n".utf8))
    }

    // MARK: The field's own rules

    @Test func theEditorHoldsTheREADMEPutInSoALaterEditSavesWithoutAFalseChangedInAnotherApp() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve(.init(words: true, windows: true, mark: true))
        let candidate = try await rig.look(item)
        let editor = rig.model.legendEditor(for: item)
        await editor.show()
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
        #expect(editor.legend == ClaudeLegendMade.figureTwo && !editor.hasUnsavedText)

        // The README was rewritten twice (the legend, then the file list): the next save is made from the last.
        editor.legend = ClaudeLegendMade.figureTwo + " And the plate numbers."
        await editor.settle()
        #expect(!editor.changedOutside && editor.problem == nil && !editor.hasUnsavedText)
        let read = try rig.parsed(item)
        #expect(read.text.legend == ClaudeLegendMade.figureTwo + " And the plate numbers.")
        #expect(read.record.files.map(\.path) == ["FIGURE_LEGENDS_final.md"])
        let after = try rig.readmeBytes(item)
        #expect(after.starts(with: byteOrderMark) && count([0x0A], in: after) == count([0x0D, 0x0A], in: after))
    }

    @Test func aREADMEChangedInAnotherAppIsNeverWrittenOverAndNothingIsLeftHalfDone() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        let editor = rig.model.legendEditor(for: item)
        await editor.load()

        // Another app changes the README after the field read it.
        let url = rig.readmeURL(item)
        let text = try String(contentsOf: url, encoding: .utf8)
        let theirs = try #require(KeptReadme.replacingLegend(in: text, with: "Theirs, from another app."))
        try Data(theirs.utf8).write(to: url)

        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)

        #expect(try rig.readmeBytes(item) == Data(theirs.utf8))
        #expect(try rig.folderFiles(item) == ["README.md", ClaudeLegendMade.figureName])
        #expect(rig.model.note?.sentence == "Couldn\u{2019}t put Claude\u{2019}s legend in. README.md was changed in another app. Nothing was changed.")
        #expect(rig.model.note?.hasUndo == false)
        // No draft is left behind: the field shows what the README says, and the window's own line is not added.
        #expect(editor.legend == "Theirs, from another app." && !editor.changedOutside && editor.problem == nil && !editor.holdsDraft)
    }

    @Test func aSaveWaitingOnThePersonIsNeverTakenOverByClaudesLegend() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        let editor = rig.model.legendEditor(for: item)
        await editor.show()
        editor.legend = "My own words, typed just now."
        // Another app changes the README, and the save of those words meets it: the field holds a draft and a question.
        let url = rig.readmeURL(item)
        let theirs = try #require(KeptReadme.replacingLegend(in: try String(contentsOf: url, encoding: .utf8), with: "Theirs."))
        try Data(theirs.utf8).write(to: url)
        await editor.save()
        #expect(editor.changedOutside && editor.legend == "My own words, typed just now.")

        await rig.model.useClaudeLegend(candidate, for: item, confirmed: true)
        #expect(rig.model.note?.sentence == "Couldn\u{2019}t put Claude\u{2019}s legend in. Your legend has a save waiting: README.md was changed in another app. Nothing was changed.")
        // The draft, the question and the README are as they were.
        #expect(editor.changedOutside && editor.legend == "My own words, typed just now.")
        #expect(try rig.readmeBytes(item) == Data(theirs.utf8))
        #expect(try rig.folderFiles(item) == ["README.md", ClaudeLegendMade.figureName])
        #expect(!rig.science.downloads.contains(ClaudeLegendMade.legends), "refused before anything was fetched")
    }

    @Test func theWindowIsToldWhenALegendIsLookedAtOrPutInSoTheCardIsDrawnAgain() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        var told = 0
        let subscription = rig.model.objectWillChange.sink { told += 1 }
        defer { subscription.cancel() }
        await rig.model.claudeLegend.look(at: item)
        let afterLook = told
        #expect(afterLook > 0)
        let candidate = try #require(rig.model.claudeLegend.candidates(for: item).first)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
        #expect(told > afterLook)
    }

    @Test func thePillWithUndoStaysAsLongAsARemovalsAndAFailureTwiceAsLong() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        let model = ShelfModel(shelf: rig.shelf, noteLifetime: .seconds(1), pdf: ShelfPDFMaker(dependencies: .declining), legendDelay: .seconds(60),
                               claudeLegend: rig.model.claudeLegend)
        await model.useClaudeLegend(candidate, for: item, confirmed: false)
        #expect(model.note?.hasUndo == true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.note != nil, "an undoable line stays its lifetime")
        try await until("the undoable line to go") { model.note == nil }

        let again = ShelfClaudeLegend.Candidate(file: ClaudeLegendMade.historyFile(ClaudeLegendMade.other, "gone.md"), match: .legend)
        await model.useClaudeLegend(again, for: item, confirmed: true)
        #expect(model.note?.hasUndo == false)
        // The failure line outlasts the undoable one's whole lifetime (1 s) and goes by its own, at 2 s.
        try await Task.sleep(for: .milliseconds(1_100))
        let stillThere = model.note != nil
        try await until("the failure line to go") { model.note == nil }
        #expect(stillThere, "a line that only says what went wrong stays twice as long")
    }

    @Test func aREADMEThatCantBeReadStopsItBeforeAnythingIsFetched() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        try FileManager.default.removeItem(at: rig.readmeURL(item))
        let editor = rig.model.legendEditor(for: item)
        let outcome = await rig.model.claudeLegend.use(candidate, for: item, editor: editor, confirmed: false)
        guard case .failed(let sentence) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(sentence.hasPrefix("Couldn\u{2019}t read the README, so the legend can\u{2019}t be edited here."))
        #expect(!rig.science.downloads.contains(ClaudeLegendMade.legends))
    }

    @Test func aFileThatCantBeHadChangesNothing() async throws {
        let cases: [(String, (ClaudeLegendScience) -> Void, String)] = [
            ("gone", { $0.bytes[ClaudeLegendMade.legends] = nil },
             "Couldn\u{2019}t put Claude\u{2019}s legend in. FIGURE_LEGENDS_final.md isn\u{2019}t in Claude Science any more. Nothing was changed."),
            ("empty", { $0.bytes[ClaudeLegendMade.legends] = Data() },
             "Couldn\u{2019}t put Claude\u{2019}s legend in. FIGURE_LEGENDS_final.md is empty. Nothing was changed."),
            ("binary", { $0.bytes[ClaudeLegendMade.legends] = Data([0x00, 0x01, 0x02, 0x03]) },
             "Couldn\u{2019}t put Claude\u{2019}s legend in. FIGURE_LEGENDS_final.md isn\u{2019}t text Capsid can read. Nothing was changed."),
            ("blank", { $0.bytes[ClaudeLegendMade.legends] = Data("  \n\n".utf8) },
             "Couldn\u{2019}t put Claude\u{2019}s legend in. FIGURE_LEGENDS_final.md is empty. Nothing was changed."),
            ("too big", { $0.downloadFail[ClaudeLegendMade.legends] = .answered(.tooBig) },
             "Couldn\u{2019}t put Claude\u{2019}s legend in. FIGURE_LEGENDS_final.md is too big to be a legend. Nothing was changed."),
        ]
        for (name, arrange, sentence) in cases {
            let rig = try ClaudeLegendRig()
            defer { rig.tearDown() }
            let item = try await rig.shelve()
            let original = try rig.readmeBytes(item)
            let candidate = try await rig.look(item)
            arrange(rig.science)
            await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
            #expect(rig.model.note?.sentence == sentence, "\(name)")
            #expect(rig.model.note?.hasUndo == false, "\(name)")
            #expect(try rig.readmeBytes(item) == original, "\(name)")
            #expect(try rig.folderFiles(item) == ["README.md", ClaudeLegendMade.figureName], "\(name)")
        }
    }

    @Test func aDownloadThatFailsSaysSoAndChangesNothing() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let original = try rig.readmeBytes(item)
        let candidate = try await rig.look(item)
        rig.science.downloadFail[ClaudeLegendMade.legends] = .timedOut
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
        let sentence = try #require(rig.model.note?.sentence)
        #expect(sentence.hasPrefix("Couldn\u{2019}t put Claude\u{2019}s legend in. Couldn\u{2019}t get FIGURE_LEGENDS_final.md.") && sentence.hasSuffix("Nothing was changed."))
        #expect(try rig.readmeBytes(item) == original)
    }

    @Test func aSecondAskWhileTheLegendIsGoingInDoesNothing() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        rig.science.downloadDelay = .milliseconds(150)
        let editor = rig.model.legendEditor(for: item)
        async let first = rig.model.claudeLegend.use(candidate, for: item, editor: editor, confirmed: false)
        try await until("the first to be under way") { rig.model.claudeLegend.busy.contains(item.id) }
        let second = await rig.model.claudeLegend.use(candidate, for: item, editor: editor, confirmed: false)
        #expect(second == .busy)
        if case .done = await first {} else { Issue.record("the first should have gone in") }
        #expect(rig.science.downloads.filter { $0 == ClaudeLegendMade.legends }.count == 1)
    }

    @Test func aDirectoryUnderTheFilesNameIsNeverWrittenOver() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let candidate = try await rig.look(item)
        try FileManager.default.createDirectory(at: item.folder.appending(path: "FIGURE_LEGENDS_final.md", directoryHint: .isDirectory),
                                                withIntermediateDirectories: false)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
        // Something else is under that name: the next free one is used.
        #expect(try rig.parsed(item).text.legend == ClaudeLegendMade.figureTwo)
        #expect(try rig.parsed(item).record.files.map(\.path) == ["FIGURE_LEGENDS_final 2.md"])
        #expect(try Data(contentsOf: item.folder.appending(path: "FIGURE_LEGENDS_final 2.md")) == Data(ClaudeLegendMade.legendsText.utf8))
    }

    @Test func aREADMEChangedBetweenTheLegendAndTheFileListLeavesTheLegendAndSaysTheFileWasNotListed() async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        let item = try await rig.shelve()
        let editor = rig.model.legendEditor(for: item)
        await editor.load()
        #expect(await editor.put("Claude says.") == .saved(before: ""))
        // Another app changes the README now, before the file is listed.
        let url = rig.readmeURL(item)
        let theirs = try #require(KeptReadme.replacingLegend(in: try String(contentsOf: url, encoding: .utf8), with: "Theirs."))
        try Data(theirs.utf8).write(to: url)

        let listed = await editor.list(Data("x".utf8), as: rig.legendRow("legend.md", ClaudeLegendMade.legends, bytes: Data("x".utf8)))
        #expect(listed == .failed("README.md was changed in another app, so the file wasn\u{2019}t listed in it."))
        #expect(try rig.readmeBytes(item) == Data(theirs.utf8))
        #expect(try rig.folderFiles(item) == ["README.md", ClaudeLegendMade.figureName])
    }
}

// MARK: The disk's part

@MainActor
struct ShelfClaudeLegendDiskTests {
    private func rig(_ body: (ClaudeLegendRig, ShelfItem) async throws -> Void) async throws {
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        try await body(rig, rig.shelve())
    }

    private let bytes = Data("A made-up legend.\n".utf8)

    private func file(_ name: String = "legend.md", version: String? = "v-legend") -> KeptFile {
        KeptFile(path: name, role: .legend, artifact: nil, version: version, index: nil, of: nil, sha256: KeptDisk.sha256(of: bytes), bytes: bytes.count)
    }

    @Test func aFileIsCopiedBesideTheFigureAndListedWithEveryOtherByteOfTheReadmeKept() async throws {
        try await rig { rig, item in
            let before = try await rig.disk.readme(at: item.folder)
            let listing = try await rig.disk.listFile(bytes, as: file(), in: item.folder, lastRead: before.markdown)
            #expect(listing.path == "legend.md" && !listing.wasListed)
            #expect(try Data(contentsOf: item.folder.appending(path: "legend.md")) == bytes)
            let after = try await rig.disk.readme(at: item.folder)
            #expect(after.markdown == listing.markdown)
            #expect(after.record.files == [file()])
            // Only the files rows changed.
            #expect(after.markdown == KeptReadme.updating(before.markdown, files: [file()], missing: []))
        }
    }

    @Test func aREADMEThatIsNotWhatWasReadIsLeftAloneAndNothingIsCopied() async throws {
        try await rig { rig, item in
            let before = try await rig.disk.readme(at: item.folder)
            try Data((before.markdown + "\nA line added in another app.\n").utf8).write(to: rig.readmeURL(item))
            await #expect(throws: KeptDiskError.changedOutside) {
                _ = try await rig.disk.listFile(bytes, as: file(), in: item.folder, lastRead: before.markdown)
            }
            #expect(try rig.folderFiles(item) == ["README.md", ClaudeLegendMade.figureName])
        }
    }

    @Test func theSameVersionIsNotCopiedOrListedTwice() async throws {
        try await rig { rig, item in
            let first = try await rig.disk.readme(at: item.folder)
            let one = try await rig.disk.listFile(bytes, as: file(), in: item.folder, lastRead: first.markdown)
            let again = try await rig.disk.listFile(bytes, as: file(), in: item.folder, lastRead: one.markdown)
            #expect(again.wasListed && again.path == "legend.md" && again.markdown == one.markdown)
            #expect(try rig.parsed(item).record.files.count == 1)
        }
    }

    @Test func aNameTakenByOtherBytesGetsTheNextNumberAndTheSameBytesAreReused() async throws {
        try await rig { rig, item in
            // Another file under the name, put there by hand.
            try Data("Mine.\n".utf8).write(to: item.folder.appending(path: "legend.md"))
            let first = try await rig.disk.readme(at: item.folder)
            let one = try await rig.disk.listFile(bytes, as: file(), in: item.folder, lastRead: first.markdown)
            #expect(one.path == "legend 2.md")
            #expect(try Data(contentsOf: item.folder.appending(path: "legend.md")) == Data("Mine.\n".utf8))
            #expect(try Data(contentsOf: item.folder.appending(path: "legend 2.md")) == bytes)

            // The same bytes are already there under the name (an earlier run wrote the file and not the README): reused.
            try bytes.write(to: item.folder.appending(path: "other.md"))
            let two = try await rig.disk.listFile(bytes, as: file("other.md", version: "v-other"), in: item.folder, lastRead: one.markdown)
            #expect(two.path == "other.md")
            #expect(try rig.folderFiles(item).filter { $0.hasPrefix("other") } == ["other.md"])
        }
    }

    @Test func aNameCantBeREADMEOrAPathOutOfTheFolder() async throws {
        try await rig { rig, item in
            let before = try await rig.disk.readme(at: item.folder)
            let listing = try await rig.disk.listFile(bytes, as: file("readme.md"), in: item.folder, lastRead: before.markdown)
            #expect(listing.path == "readme 2.md")
            #expect(try String(contentsOf: rig.readmeURL(item), encoding: .utf8).hasPrefix("---\ncapsid_kept: 1"))
            let outside = try await rig.disk.listFile(bytes, as: file("../escape.md", version: "v-2"), in: item.folder, lastRead: listing.markdown)
            #expect(!outside.path.contains("/"))
            #expect(!FileManager.default.fileExists(atPath: item.folder.deletingLastPathComponent().appending(path: "escape.md").path))
        }
    }
}

struct ShelfClaudeLegendRoleTests {
    private let record = KeptRecord(
        name: "plate map", keptAt: Date(timeIntervalSince1970: 1_800_000_000), projectID: "p", projectName: "Assay development",
        sessionID: "s", sessionTitle: "Plate reader QC",
        figure: KeptFile(path: "plate_map.png", role: .figure, artifact: "a", version: "v-fig", index: 1, of: nil, sha256: "ab", bytes: 3),
        files: [KeptFile(path: "FIGURE_LEGENDS_final.md", role: .legend, artifact: "a2", version: "v-leg", index: nil, of: nil, sha256: "cd", bytes: 9)],
        missing: [KeptMissing(role: .legend, name: "legend.md", reason: "too big")], claudeScience: "0.1.70", capsid: "1.0")
    private let text = KeptText(legend: "A legend.", claudeSaid: "Here.", attribution: "From Claude\u{2019}s answer.", origin: "")

    @Test func aLegendRowIsWrittenReadAndWrittenAgainByteForByte() throws {
        let zone = TimeZone(identifier: "UTC")!, locale = Locale(identifier: "en_US_POSIX")
        let written = KeptReadme.render(record, text: text, timeZone: zone, locale: locale)
        #expect(written.contains("  - { path: \"FIGURE_LEGENDS_final.md\", role: legend, artifact: \"a2\", version: \"v-leg\", sha256: \"cd\", bytes: 9 }"))
        let parsed = try #require(KeptReadme.parse(written))
        #expect(parsed.record.files == record.files && parsed.record.missing == record.missing)
        #expect(KeptReadme.render(parsed.record, text: parsed.text, timeZone: zone, locale: locale) == written)
        #expect(written.contains("Claude\u{2019}s legend file, legend.md: too big."))
    }

    @Test func theRoleIsBesideTheFigureAndAValidPath() {
        #expect(KeptRole.allCases.contains(.legend) && KeptRole(rawValue: "legend") == .legend)
        #expect(KeptLayout.folder(for: .legend) == nil)
        #expect(KeptLayout.relativePath(role: .legend, fileName: "FIGURE_LEGENDS_final.md") == "FIGURE_LEGENDS_final.md")
        #expect(KeptLayout.isValidRelativePath("FIGURE_LEGENDS_final.md"))
        let item = KeepItem(role: .legend, source: .download(version: "v"), artifact: nil, version: "v", name: "legend.md", size: 3, sha: nil)
        #expect(item.relativePath == "legend.md")
        #expect(KeepRules.roleTitle(.legend) == "Claude\u{2019}s legend file")
    }

    @Test func aLegendRowIsAddedToAReadmeInEveryShapeWithEveryOtherByteKept() throws {
        let zone = TimeZone(identifier: "UTC")!, locale = Locale(identifier: "en_US_POSIX")
        var bare = record
        bare.files = []
        bare.missing = []
        let plain = KeptReadme.render(bare, text: text, timeZone: zone, locale: locale)
        let shapes = [plain,
                      plain.replacingOccurrences(of: "## Your legend", with: "Words under the title.\n\n## Your legend"),
                      plain.replacingOccurrences(of: "\n", with: "\r\n"),
                      "\u{FEFF}" + plain]
        for shape in shapes {
            let updated = try #require(KeptReadme.updating(shape, files: record.files, missing: []))
            let back = try #require(KeptReadme.parse(updated))
            #expect(back.record.files == record.files)
            #expect(back.text.legend == text.legend && back.text.claudeSaid == text.claudeSaid && back.text.attribution == text.attribution)
            // Taking the row out again gives the README back exactly.
            #expect(KeptReadme.updating(updated, files: [], missing: []) == shape)
        }
    }
}
