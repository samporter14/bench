// ReferenceFilesTests.swift — opening what a reply made (DESIGN.md, Reference):
// which files are figures and which are documents, the Quick Look panel's
// items and their temporary copies (gone when the window closes), the reading
// view for a Markdown document (back with Esc and ⌘[, cut at 2 MiB and saying
// so, Add to Shelf), a failed read's one sentence, and the bounds on what is
// read. No page, no daemon, no panel: the downloads, the disk and the panel
// are made up.
import AppKit
import Foundation
import QuickLookUI
import Testing
@testable import Bench

/// What the made-up download answers, and what it was asked.
@MainActor
final class FakeDownloads {
    var bytes: [String: Data] = [:]
    var failures: [String: ReferenceDownload] = [:]
    /// Every version asked for, in order of asking.
    private(set) var reads: [String] = []
    /// Reads wait here while `holding`; `release` lets them go.
    var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// What happened, in order: "read <v>" when a read starts (for the gate's order).
    private(set) var log: [String] = []

    func release() {
        let waiting = waiters
        waiters = []
        holding = false
        for waiter in waiting { waiter.resume() }
    }

    /// Reads of this one version wait until `release(_:)`; the others go on.
    private var heldVersions: Set<String> = []
    private var heldWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func hold(_ version: String) { heldVersions.insert(version) }

    func release(_ version: String) {
        heldVersions.remove(version)
        for waiter in heldWaiters.removeValue(forKey: version) ?? [] { waiter.resume() }
    }

    func download(_ version: String) async -> ReferenceDownload {
        reads.append(version)
        log.append("read \(version)")
        if holding { await withCheckedContinuation { waiters.append($0) } }
        if heldVersions.contains(version) { await withCheckedContinuation { heldWaiters[version, default: []].append($0) } }
        if let failure = failures[version] { return failure }
        return bytes[version].map { .bytes($0) } ?? .failed(.missing)
    }

    func note(_ event: String) { log.append(event) }
}

/// Renders wait here, the ones asked to, until `release()`: a document that is slow to draw.
actor RenderHold {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var waiting = 0

    func wait() async {
        guard !open else { return }
        waiting += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// A made-up reply with two pictures and two documents, one made-up disk, and a model on them.
@MainActor
struct FilesRig {
    static let chart1 = file(1, "z_prime_by_plate.png", .image)
    static let chart2 = file(2, "plate_7_heatmap.png", .image)
    static let notes = file(3, "plate_qc_notes.md", .markdown, size: 1_900)
    static let table = file(4, "z_prime_by_plate.csv", .table, size: 1_100)

    static func file(_ n: Int, _ name: String, _ kind: ArtifactKind, size: Int? = 1_000) -> HistoryFile {
        HistoryFile(v: String(format: "aaaaaaaa-0000-4000-8000-%012d", n), a: String(format: "bbbbbbbb-0000-4000-8000-%012d", n),
                    name: name, kind: kind, size: size)
    }

    let history: FakeHistory
    let downloads = FakeDownloads()
    let model: ReferenceModel
    let base: URL
    let storage: ShelfTemporaryCopies
    let shelf = MadeShelf()
    /// What the panel was asked to show: the files in order, and where.
    var presented: [(files: [String], index: Int)] { recorder.presented }
    private let recorder = PanelRecorder()

    @MainActor
    final class PanelRecorder {
        var presented: [(files: [String], index: Int)] = []
    }

    init(rows: [HistoryItem]? = nil, gate: ReadingGate? = nil,
         render: (@Sendable (String) async -> AnswerDocument)? = nil) {
        let rows = rows ?? ReferenceModelTests.history(
            30, you: [0: "Run the QC.", 20: "Plot Z′ by plate."], claude: [5: "Eleven passed.", 28: "Plate 7 is low."],
            figures: [24: [Self.chart1], 25: [Self.chart2], 26: [Self.notes], 27: [Self.table]])
        history = FakeHistory(rows: rows)
        base = FileManager.default.temporaryDirectory.appending(path: "capsid-reference-files-tests-\(UUID().uuidString)",
                                                                directoryHint: .isDirectory)
        storage = ShelfTemporaryCopies(base: base)
        var dependencies = history.dependencies
        let downloads = downloads
        dependencies.download = { await downloads.download($0) }
        if let render { dependencies.renderDocument = render }
        dependencies.storage = storage
        dependencies.shelf = shelf.access
        model = ReferenceModel(session: ReferenceModelTests.session, dependencies: dependencies,
                               gate: gate ?? ReadingGate(now: { Date() }, sleep: { _ in }))
        let recorder = recorder
        model.files.presenter = { files in
            recorder.presented.append((files.items.map(\.file.v), files.current))
        }
        for file in [Self.chart1, Self.chart2, Self.notes, Self.table] {
            downloads.bytes[file.v] = Data("bytes of \(file.name)".utf8)
        }
        downloads.bytes[Self.notes.v] = Data("# Plate reader QC\n\nEleven passed. **Plate 7** failed.\n\n- Z\u{2032} is 0.41\n".utf8)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }

    /// The window opened on the newest reply, and read.
    func open() async {
        model.open()
        await ReferenceModelTests.settle(model)
    }

    /// Until nothing is being read for a file.
    func settle() async {
        for _ in 0..<2_000 where !model.files.preparing.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        // The write that follows a read is the disk actor's.
        try? await Task.sleep(for: .milliseconds(5))
    }

    var runFolder: URL { storage.runFolder(model.files.run) }
}

// MARK: Which files are figures and which are documents

@MainActor
struct ReferenceFileRulesTests {
    private func answer(files: [HistoryFile], on uploads: [HistoryFile] = []) -> ReferenceAnswer {
        let rows: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Run it.", cut: false, files: uploads),
            .steps(i: 1, line: "Ran code", failed: false, files: files),
            .turn(i: 2, role: .claude, at: nil, text: "Done.", cut: false, files: []),
        ]
        return ReferenceRules.answers(items: rows, reachedStart: true, whole: [:])[0]
    }

    @Test func aPictureIsAFigureAndEveryOtherKindIsADocument() {
        for kind in ArtifactKind.allCases {
            let file = FilesRig.file(9, "thing", kind)
            #expect(ReferenceFileRules.isFigure(file) == (kind == .image), "\(kind)")
        }
        // A vector picture has no thumbnail: Quick Look draws it, as a document.
        #expect(!ReferenceFileRules.isFigure(FilesRig.file(9, "diagram.svg", .svg)))
    }

    @Test func aRepliesDocumentsAreItsOtherFilesInOrderOnePerArtifact() throws {
        let draft = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000031", a: "bbbbbbbb-0000-4000-8000-000000000003",
                                name: "plate_qc_notes.md", kind: .markdown, size: 800)
        let pdf = FilesRig.file(5, "report.pdf", .pdf)
        let script = FilesRig.file(6, "qc.py", .text)
        let page = FilesRig.file(7, "dashboard.html", .html)
        let reply = answer(files: [draft, FilesRig.chart1, pdf, FilesRig.table, FilesRig.notes, script, page])
        // The notes' later version stands in the place of the draft; the picture is a figure.
        let documents = ReferenceFileRules.documents(of: reply)
        #expect(documents.map(\.name) == ["plate_qc_notes.md", "report.pdf", "z_prime_by_plate.csv", "qc.py", "dashboard.html"])
        #expect(documents[0] == FilesRig.notes)
        #expect(reply.figures == [FilesRig.chart1])
    }

    @Test func theUsersOwnUploadsAreNeitherFiguresNorDocuments() {
        let upload = FilesRig.file(8, "my_plate_map.csv", .table)
        let reply = answer(files: [FilesRig.table], on: [upload, FilesRig.file(10, "photo.png", .image)])
        #expect(ReferenceFileRules.documents(of: reply) == [FilesRig.table])
        #expect(reply.figures.isEmpty)
    }

    @Test func whatClaudeScienceHidesIsNotListed() {
        let plan = FilesRig.file(11, "plan.json", .text)
        let planTwo = FilesRig.file(12, "plan_v2.json", .text)
        let goal = FilesRig.file(13, "goal_overview.html", .html)
        let kept = FilesRig.file(14, "planets.csv", .table)
        let reply = answer(files: [plan, planTwo, goal, kept, FilesRig.notes])
        #expect(ReferenceFileRules.documents(of: reply) == [kept, FilesRig.notes])
        #expect(ReferenceFileRules.isHidden("Plan.JSON") && ReferenceFileRules.isHidden("goal_x.html"))
        #expect(!ReferenceFileRules.isHidden("plan.md") && !ReferenceFileRules.isHidden("goal.html"))
    }

    @Test func markdownReadsInTheWindowAndTheRestGoesToQuickLookAfterTheFigures() {
        let pdf = FilesRig.file(5, "report.pdf", .pdf)
        #expect(ReferenceFileRules.readsInWindow(FilesRig.notes))
        #expect(!ReferenceFileRules.readsInWindow(pdf) && !ReferenceFileRules.readsInWindow(FilesRig.table))
        let list = ReferenceFileRules.quickLookFiles(figures: [FilesRig.chart1, FilesRig.chart2],
                                                      documents: [FilesRig.notes, FilesRig.table, pdf])
        #expect(list == [FilesRig.chart1, FilesRig.chart2, FilesRig.table, pdf])
    }

    @Test func theKindTileSaysTheEndingOrTheKind() {
        #expect(ReferenceFileRules.tile(FilesRig.notes) == "MD")
        #expect(ReferenceFileRules.tile(FilesRig.table) == "CSV")
        #expect(ReferenceFileRules.tile(FilesRig.file(5, "report.pdf", .pdf)) == "PDF")
        #expect(ReferenceFileRules.tile(FilesRig.file(6, "qc.py", .text)) == "PY")
        #expect(ReferenceFileRules.tile(FilesRig.file(7, "README", .text)) == "TXT")
        #expect(ReferenceFileRules.detail(FilesRig.notes) == "Markdown \u{00B7} 2 KB")
    }
}

// MARK: What is read

struct ReferenceReadBoundsTests {
    @Test func aDocumentIsReadWholeUpToTheLimitAndCutAfterIt() throws {
        let line = "abcdefghi\n"
        let data = Data(String(repeating: line, count: 20).utf8)   // 200 bytes
        let whole = try #require(ReferenceFileRules.text(from: data, limit: 200))
        #expect(!whole.cut && whole.text == String(repeating: line, count: 20))
        let cut = try #require(ReferenceFileRules.text(from: data, limit: 199))
        // One byte over: cut, and back to the end of a whole line.
        #expect(cut.cut)
        #expect(cut.text == String(repeating: line, count: 19).dropLast())
        #expect(cut.text.utf8.count <= 199)
    }

    @Test func theLimitIsTwoMiBLikeTheHistoryReads() {
        #expect(ReferenceFileRules.readLimit == 2 * 1_024 * 1_024)
        #expect(ReferenceFileRules.readLimit == HistoryReaderScript.bodyCap)
    }

    @Test func aCutNeverSplitsACharacterOrLeavesAReplacementMark() throws {
        // "é" is two bytes: a limit that lands between them gives the character back.
        let data = Data(("a" + String(repeating: "é", count: 10)).utf8)   // 21 bytes
        for limit in 2...20 {
            let read = try #require(ReferenceFileRules.text(from: data, limit: limit))
            #expect(read.cut)
            #expect(!read.text.contains("\u{FFFD}"), "limit \(limit)")
            #expect(read.text.utf8.count <= limit)
        }
    }

    @Test func aByteOrderMarkIsDropped() throws {
        let read = try #require(ReferenceFileRules.text(from: Data([0xEF, 0xBB, 0xBF]) + Data("# Notes".utf8)))
        #expect(read.text == "# Notes" && !read.cut)
    }

    @Test func bytesThatAreNotTextAreNotRead() {
        #expect(ReferenceFileRules.text(from: Data([0x23, 0x00, 0x41])) == nil)
        #expect(ReferenceFileRules.text(from: Data([0xFF, 0xFE, 0x41])) == nil)
    }

    @Test func anEmptyFileIsEmptyText() throws {
        let read = try #require(ReferenceFileRules.text(from: Data()))
        #expect(read.text.isEmpty && !read.cut)
    }

    @Test func aReadOverTheDownloadCapIsTooBigWhatEverTheListingSaid() {
        let big = Data(count: ArtifactReaderScript.Cap.download + 1)
        #expect(ReferenceDownload(.answered(.bytes(big))) == .tooBig)
        #expect(ReferenceDownload(.answered(.bytes(Data("ok".utf8)))) == .bytes(Data("ok".utf8)))
        #expect(ReferenceDownload(.answered(.tooBig)) == .tooBig)
    }

    @Test func aFailedReadIsOneOfTheShelfsSentences() {
        #expect(ReferenceDownload(.answered(.unreadable)) == .failed(.unreadable))
        #expect(ReferenceDownload(.answered(.missing)) == .failed(.missing))
        #expect(ReferenceDownload(.answered(.lost)) == .failed(.signedOut))
        #expect(ReferenceDownload(.timedOut) == .failed(.timedOut))
        #expect(ReferenceDownload(.notReady) == .failed(.notReady))
        #expect(ReferenceDownload(.cancelled) == .cancelled)
        #expect(ReferenceDownload(.answered(.cancelled)) == .cancelled)
    }
}

// MARK: Quick Look: the items and their temporary copies

@MainActor
struct ReferenceQuickLookTests {
    @Test func pressingAFigureReadsItOnceAndShowsItAmongTheRepliesFigures() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.chart2)
        await rig.settle()
        #expect(rig.downloads.reads == [FilesRig.chart2.v])
        // Figures first, then the documents Quick Look shows; the Markdown one opens in the window.
        let files = rig.model.files
        #expect(files.items.map(\.file) == [FilesRig.chart1, FilesRig.chart2, FilesRig.table])
        #expect(files.current == 1)
        #expect(rig.presented.count == 1 && rig.presented[0].index == 1)
        // Only the file asked for has its copy; the panel's other items wait for the arrow keys.
        #expect(files.items[1].previewItemURL != nil)
        #expect(files.items[0].previewItemURL == nil && files.items[2].previewItemURL == nil)
        #expect(files.preparing.isEmpty && files.problems.isEmpty)
        // The data source the panel asks.
        #expect(files.numberOfPreviewItems(in: nil) == 3)
        #expect(files.previewPanel(nil, previewItemAt: 1) === files.items[1])
        #expect(files.previewPanel(nil, previewItemAt: 3) == nil)
        #expect(files.items[1].previewItemTitle == "plate_7_heatmap.png")
    }

    @Test func theCopyKeepsTheRealNameAndIsPrivate() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        let url = try #require(rig.model.files.items[0].previewItemURL)
        #expect(url.lastPathComponent == "z_prime_by_plate.png")
        #expect(try Data(contentsOf: url) == Data("bytes of z_prime_by_plate.png".utf8))
        // <base>/<run>/<version>/<name>, in folders of their own: 0700 and 0600.
        #expect(url.path.hasPrefix(rig.runFolder.path))
        #expect(url.deletingLastPathComponent().lastPathComponent == FilesRig.chart1.v)
        let file = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let folder = try FileManager.default.attributesOfItem(atPath: rig.runFolder.path)[.posixPermissions] as? Int
        #expect(file == 0o600 && folder == 0o700)
        // Nothing is written outside the reference windows' own folder.
        #expect(rig.base.lastPathComponent.hasPrefix("capsid-reference-files-tests-"))
        #expect(ReferenceFiles.defaultBase.lastPathComponent == "Capsid Reference Files")
        #expect(ReferenceFiles.defaultBase != ShelfTemporaryCopies.defaultBase)
    }

    @Test func aDocumentThatIsNotMarkdownOpensInQuickLookToo() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.table)
        await rig.settle()
        #expect(rig.downloads.reads == [FilesRig.table.v])
        #expect(rig.model.files.items.map(\.file.v).contains(FilesRig.table.v))
        #expect(rig.model.files.current == 2)
        #expect(rig.model.files.document == nil)
        #expect(rig.model.files.items[2].previewItemURL?.lastPathComponent == "z_prime_by_plate.csv")
    }

    @Test func theArrowKeysFetchTheNextFileAndTheLastOneIsWithdrawn() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.chart2)
        await rig.settle()
        let files = rig.model.files
        // ← : the first figure is fetched, and the panel is told when it is there.
        files.moved(to: 0)
        #expect(files.preparing == [FilesRig.chart1.v])
        await rig.settle()
        #expect(files.items[0].previewItemURL?.lastPathComponent == "z_prime_by_plate.png")
        #expect(rig.downloads.reads == [FilesRig.chart2.v, FilesRig.chart1.v])
        // Back onto a file that has its copy: nothing is read again.
        files.moved(to: 1)
        await rig.settle()
        #expect(rig.downloads.reads.count == 2)
        // On to a file, and away again before it came: its read is withdrawn.
        rig.downloads.holding = true
        files.moved(to: 2)
        for _ in 0..<50 where rig.downloads.reads.count < 3 { try await Task.sleep(for: .milliseconds(5)) }
        files.moved(to: 1)
        #expect(files.preparing.isEmpty)
        rig.downloads.release()
        await rig.settle()
        #expect(files.items[2].previewItemURL == nil)
    }

    @Test func aFileThatCantBeHadLeavesThePanelAndSaysWhyOnItsCard() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.chart2)
        await rig.settle()
        rig.downloads.failures[FilesRig.table.v] = .failed(.timedOut)
        rig.model.files.moved(to: 2)
        await rig.settle()
        #expect(rig.model.files.items.map(\.file.v) == [FilesRig.chart1.v, FilesRig.chart2.v])
        #expect(rig.model.files.problems[FilesRig.table.v] == "Claude Science took too long to answer.")
    }

    @Test func pressingAFigureAgainShowsItWithoutReadingAgain() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        #expect(rig.downloads.reads == [FilesRig.chart1.v])
        #expect(rig.presented.count == 2)
    }

    @Test func aSecondPressWhileItIsBeingReadDoesNothing() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.holding = true
        rig.model.openFile(FilesRig.chart1)
        // The card's spinner: it is being read.
        #expect(rig.model.files.preparing == [FilesRig.chart1.v])
        rig.model.openFile(FilesRig.chart1)
        for _ in 0..<50 where rig.downloads.reads.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        rig.downloads.release()
        await rig.settle()
        #expect(rig.downloads.reads == [FilesRig.chart1.v])
        #expect(rig.model.files.preparing.isEmpty)
        #expect(rig.presented.count == 1)
    }

    @Test func closingTheWindowDeletesTheFolderAndTheCopiesInIt() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        let url = try #require(rig.model.files.items[0].previewItemURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let folder = rig.runFolder
        rig.model.close()
        await rig.model.files.removal?.value
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(rig.model.files.items.isEmpty && rig.model.files.copies.isEmpty)
    }

    @Test func aReadThatLandsAfterTheWindowClosedWritesNothingAndShowsNothing() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.holding = true
        rig.model.openFile(FilesRig.chart1)
        for _ in 0..<50 where rig.downloads.reads.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        rig.model.close()
        rig.downloads.release()
        await rig.model.files.removal?.value
        #expect(rig.presented.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.runFolder.path))
        #expect(rig.model.files.copies.isEmpty && rig.model.files.document == nil)
    }

    @Test func eachWindowsCopiesAreInARunOfTheirOwn() async throws {
        let one = FilesRig(), two = FilesRig()
        defer { one.cleanUp(); two.cleanUp() }
        #expect(one.model.files.run != two.model.files.run)
        #expect(one.base != two.base)
    }
}

// MARK: Failures, bounds and the gate

@MainActor
struct ReferenceOpeningTests {
    @Test func aFailedReadIsOneSentenceUnderTheCardUntilTheNextTry() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.failures[FilesRig.chart1.v] = .failed(.unreadable)
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        #expect(rig.model.files.problems[FilesRig.chart1.v] == ShelfFailure.unreadable.sentence)
        #expect(rig.presented.isEmpty && rig.model.files.items.isEmpty)
        #expect(rig.model.files.preparing.isEmpty)
        // The next try clears the sentence, and works.
        rig.downloads.failures[FilesRig.chart1.v] = nil
        rig.model.openFile(FilesRig.chart1)
        #expect(rig.model.files.problems[FilesRig.chart1.v] == nil)
        await rig.settle()
        #expect(rig.presented.count == 1)
    }

    @Test func eachKindOfFailureHasItsOwnSentence() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        for (failure, sentence) in [(ShelfFailure.missing, "This isn't in Claude Science any more."),
                                    (.signedOut, "Claude Science needs you to sign in again."),
                                    (.notReady, "Capsid isn't connected to Claude Science right now.")] {
            rig.downloads.failures[FilesRig.chart1.v] = .failed(failure)
            rig.model.openFile(FilesRig.chart1)
            await rig.settle()
            #expect(rig.model.files.problems[FilesRig.chart1.v] == sentence)
        }
        rig.downloads.failures[FilesRig.chart1.v] = .tooBig
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        #expect(rig.model.files.problems[FilesRig.chart1.v] == ReferenceFileRules.tooBigSentence)
    }

    @Test func aFileOverTheCapIsRefusedBeforeAnythingIsRead() async throws {
        let huge = FilesRig.file(20, "genome.csv", .table, size: ArtifactReaderScript.Cap.download + 1)
        let rig = FilesRig(rows: ReferenceModelTests.history(
            30, you: [0: "Go."], claude: [28: "Done."], figures: [20: [huge], 21: [FilesRig.chart1]]))
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(huge)
        await rig.settle()
        #expect(rig.downloads.reads.isEmpty)
        #expect(rig.model.files.problems[huge.v] == ReferenceFileRules.tooBigSentence)
    }

    @Test func bytesOverTheCapAreRefusedWhenTheListingHadNoSize() async throws {
        let unsized = FilesRig.file(21, "genome.csv", .table, size: nil)
        let rig = FilesRig(rows: ReferenceModelTests.history(
            30, you: [0: "Go."], claude: [28: "Done."], figures: [20: [unsized]]))
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.bytes[unsized.v] = Data(count: ArtifactReaderScript.Cap.download + 1)
        rig.model.openFile(unsized)
        await rig.settle()
        #expect(rig.model.files.problems[unsized.v] == ReferenceFileRules.tooBigSentence)
        #expect(rig.presented.isEmpty)
    }

    @Test func readsWaitOutTheTypingAndCome()  async throws {
        // A key press just now: the gate waits the quiet out before the read starts.
        let fixed = Date(timeIntervalSince1970: 1_792_000_000)
        let log = GateLog()
        let gate = ReadingGate(now: { fixed }, sleep: { _ in log.slept += 1 })
        gate.noteKey(at: fixed)
        let rig = FilesRig(gate: gate)
        defer { rig.cleanUp() }
        // The page's own reads waited too; start counting at the figure's.
        await rig.open()
        let before = log.slept
        #expect(before > 0)
        gate.noteKey(at: fixed)
        rig.model.openFile(FilesRig.chart1)
        await rig.settle()
        #expect(log.slept > before)
        #expect(rig.downloads.reads == [FilesRig.chart1.v])
    }

    @Test func readsGoOneAtATimeInOrder() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.holding = true
        rig.model.openFile(FilesRig.chart1)
        rig.model.openFile(FilesRig.chart2)
        for _ in 0..<50 where rig.downloads.reads.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(30))
        // The second waits for the first.
        #expect(rig.downloads.reads == [FilesRig.chart1.v])
        rig.downloads.release()
        await rig.settle()
        #expect(rig.downloads.reads == [FilesRig.chart1.v, FilesRig.chart2.v])
    }
}

@MainActor
final class GateLog {
    var slept = 0
}

// MARK: The reading view

@MainActor
struct ReferenceReadingViewTests {
    @Test func aMarkdownDocumentOpensInTheWindowAndIsNeverWritten() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        let document = try #require(rig.model.files.document)
        #expect(document.file == FilesRig.notes)
        #expect(!document.cut && !document.isEmpty)
        #expect(document.rendered.string.hasPrefix("Plate reader QC"))
        #expect(document.rendered.string.contains("Plate 7"))
        // Not Quick Look, and nothing on disk.
        #expect(rig.presented.isEmpty && rig.model.files.items.isEmpty && rig.model.files.copies.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.base.path))
        #expect(rig.downloads.reads == [FilesRig.notes.v])
    }

    @Test func theDocumentIsDrawnInTheWindowsOwnReadingType() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        let document = try #require(rig.model.files.document)
        // Same renderer and style as the answer: 14-on-21 body in the reference style.
        let expected = AnswerMarkdown.render(String(decoding: try #require(rig.downloads.bytes[FilesRig.notes.v]), as: UTF8.self),
                                             style: .reference).text
        #expect(document.rendered.isEqual(to: expected))
        let body = document.rendered.attribute(.font, at: document.rendered.string.count - 3, effectiveRange: nil) as? NSFont
        #expect(body?.pointSize == Solanum.bodySize)
    }

    @Test func aDocumentOverTwoMiBIsCutAndSaysSo() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        let line = "- A line of the document that goes on and on and on.\n"
        let count = (ReferenceFileRules.readLimit / line.utf8.count) + 4_000
        rig.downloads.bytes[FilesRig.notes.v] = Data(String(repeating: line, count: count).utf8)
        #expect(rig.downloads.bytes[FilesRig.notes.v]!.count > ReferenceFileRules.readLimit)
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        for _ in 0..<400 where rig.model.files.document == nil { try await Task.sleep(for: .milliseconds(25)) }
        let document = try #require(rig.model.files.document)
        #expect(document.cut)
        // Bounded: no more than the limit's worth of lines was drawn.
        let lines = document.rendered.string.split(separator: "\n").count
        #expect(lines <= ReferenceFileRules.readLimit / line.utf8.count)
        #expect(lines > 1_000)
        #expect(ReferenceFileRules.cutSentence == "Only the first 2 MB are shown. Add it to your shelf for the whole file.")
    }

    @Test func aDocumentUnderTheLimitIsNotCut() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document?.cut == false)
    }

    @Test func anEmptyDocumentSaysSo() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.bytes[FilesRig.notes.v] = Data("\n  \n".utf8)
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document?.isEmpty == true)
        #expect(ReferenceFileRules.emptySentence == "This document is empty.")
    }

    @Test func markdownThatIsNotTextOpensInQuickLookInstead() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.bytes[FilesRig.notes.v] = Data([0x23, 0x20, 0x00, 0x01, 0x02, 0xFF])
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document == nil)
        #expect(rig.presented.count == 1)
        #expect(rig.model.files.items.map(\.file.v) == [FilesRig.notes.v])
        #expect(rig.model.files.items[0].previewItemURL?.lastPathComponent == "plate_qc_notes.md")
    }

    @Test func backLeavesTheDocumentAndTheAnswerIsUntouched() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document != nil)
        let shown = rig.model.shownID, key = rig.model.shownKey
        rig.model.closeDocument()
        #expect(rig.model.files.document == nil)
        // The page under it is the same reply, not started again: nothing scrolls it.
        #expect(rig.model.shownID == shown && rig.model.shownKey == key && rig.model.scrollRequest == nil)
        // Back with nothing open does nothing.
        rig.model.closeDocument()
        #expect(rig.model.shownKey == key)
        // And it can be opened again.
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document != nil)
    }

    @Test func anotherReplyIsTheAnswerAgain() async throws {
        let rows = ReferenceModelTests.history(
            40, you: [0: "First.", 20: "Second."], claude: [10: "One.", 30: "Two."],
            figures: [5: [FilesRig.table], 25: [FilesRig.notes]])
        let rig = FilesRig(rows: rows)
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document != nil)
        rig.model.earlier()
        await ReferenceModelTests.settle(rig.model)
        #expect(rig.model.files.document == nil)
        #expect(rig.model.scrollRequest == nil)
    }

    // MARK: A document that is opened and then left behind

    /// Until the held read has started.
    private func untilRead(_ rig: FilesRig) async {
        for _ in 0..<1_000 where rig.downloads.reads.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func leavingDocumentModeWhileItLoadsDropsItsLateDownload() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.downloads.holding = true
        rig.model.files.open(FilesRig.notes, among: [])
        await untilRead(rig)
        #expect(!rig.downloads.reads.isEmpty)
        rig.model.files.closeDocument()
        rig.downloads.release()
        await rig.settle()
        #expect(rig.model.files.document == nil, "what Back left is not shown again when the read lands")
        #expect(rig.model.files.preparing.isEmpty)
        rig.model.close()
    }

    @Test func aDocumentStillBeingReadWhenTheWindowGoesToAnotherReplyNeverAppearsThere() async throws {
        let rows = ReferenceModelTests.history(
            40, you: [0: "First.", 20: "Second."], claude: [10: "One.", 30: "Two."],
            figures: [5: [FilesRig.table], 25: [FilesRig.notes]])
        let rig = FilesRig(rows: rows)
        defer { rig.cleanUp() }
        await rig.open()
        let newest = rig.model.shownID
        rig.downloads.holding = true
        rig.model.openFile(FilesRig.notes)
        await untilRead(rig)
        rig.model.earlier()
        await ReferenceModelTests.settle(rig.model)
        #expect(rig.model.shownID != newest, "the window is on the other reply")
        rig.downloads.release()
        await rig.settle()
        #expect(rig.model.files.document == nil, "the old reply's document does not turn up under the new one")
        #expect(rig.model.files.preparing.isEmpty && rig.model.files.problems.isEmpty)
        // And it can be opened again where it belongs.
        rig.model.later()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document?.file == FilesRig.notes)
        rig.model.close()
    }

    /// A reply with two Markdown documents.
    private static func twoDocuments() -> (rows: [HistoryItem], second: HistoryFile) {
        let second = FilesRig.file(5, "assay_readme.md", .markdown, size: 700)
        let rows = ReferenceModelTests.history(
            30, you: [0: "Run the QC.", 20: "Plot Z\u{2032} by plate."], claude: [5: "Eleven passed.", 28: "Plate 7 is low."],
            figures: [26: [FilesRig.notes, second]])
        return (rows, second)
    }

    @Test func aSecondDocumentPressedWhileTheFirstIsBeingReadLeavesTheFirstBehind() async throws {
        let (rows, second) = Self.twoDocuments()
        let rig = FilesRig(rows: rows)
        defer { rig.cleanUp() }
        rig.downloads.bytes[second.v] = Data("# Assay readme\n\nThe second one.\n".utf8)
        await rig.open()
        rig.downloads.hold(FilesRig.notes.v)
        rig.model.openFile(FilesRig.notes)
        await untilRead(rig)
        rig.model.openFile(second)
        #expect(!rig.model.files.preparing.contains(FilesRig.notes.v), "the first one's spinner goes when it is left behind")
        // The first one's read comes in late: it is dropped, and the second is what the window shows.
        rig.downloads.release(FilesRig.notes.v)
        for _ in 0..<1_000 where rig.model.files.document == nil { try? await Task.sleep(for: .milliseconds(5)) }
        await rig.settle()
        #expect(rig.model.files.document?.file == second)
        #expect(rig.model.files.preparing.isEmpty && rig.model.files.problems.isEmpty)
        // The first can be pressed again once the second is left.
        rig.model.closeDocument()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.files.document?.file == FilesRig.notes)
        rig.model.close()
    }

    @Test func theDocumentOpenedLastIsTheOneShownEvenWhenTheOlderOneIsSlowToDraw() async throws {
        let (rows, second) = Self.twoDocuments()
        let slow = RenderHold()
        let rig = FilesRig(rows: rows, render: { markdown in
            if markdown.hasPrefix("# Plate reader QC") { await slow.wait() }
            return AnswerMarkdown.render(markdown, style: .reference)
        })
        defer { rig.cleanUp() }
        rig.downloads.bytes[second.v] = Data("# Assay readme\n\nThe second one.\n".utf8)
        await rig.open()
        // The first document is read and is being drawn; the second is pressed, read and drawn at once.
        rig.model.openFile(FilesRig.notes)
        for _ in 0..<1_000 { if await slow.waiting > 0 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        #expect(await slow.waiting == 1)
        rig.model.openFile(second)
        for _ in 0..<1_000 where rig.model.files.document == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(rig.model.files.document?.file == second)
        // Now the first one is drawn.
        await slow.release()
        await rig.settle()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(rig.model.files.document?.file == second, "the older document does not replace the newer when its drawing ends last")
        #expect(rig.model.files.preparing.isEmpty && rig.model.files.problems.isEmpty)
        rig.model.close()
    }

    @Test func theSameReplyGrownByARowKeepsTheDocumentOpenAndItsReply() async throws {
        let you: [Int: String] = [0: "Run the QC.", 20: "Plot Z\u{2032} by plate."]
        let said: [Int: String] = [5: "Eleven passed.", 24: "Working on the heatmap."]
        let rig = FilesRig(rows: ReferenceModelTests.history(28, you: you, claude: said, figures: [22: [FilesRig.notes]]))
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        let opened = try #require(rig.model.files.document)
        let reply = try #require(rig.model.current)
        // Claude finishes: the reply's last row moves, and it is the same reply.
        rig.history.rows = ReferenceModelTests.history(34, you: you, claude: said.merging([33: "Here it is."]) { $1 },
                                                       figures: [22: [FilesRig.notes]])
        rig.history.total = 34
        rig.model.refresh(afterFinish: true)
        for _ in 0..<1_000 where rig.model.current?.text.contains("Here it is.") != true { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(rig.model.current?.text.contains("Here it is.") == true && rig.model.current?.start == reply.start)
        #expect(rig.model.files.document?.file == FilesRig.notes, "the reading view stays for the same reply")
        #expect(rig.model.files.document?.answerStart == opened.answerStart)
        rig.model.close()
    }

    @Test func aDocumentKeepsTheReplyItCameFromAndCopyWithSourceNamesThatRepliesTime() async throws {
        let rows = ReferenceModelTests.history(
            40, you: [0: "First.", 20: "Second."], claude: [10: "One.", 30: "Two."],
            figures: [5: [FilesRig.table], 25: [FilesRig.notes]])
        let rig = FilesRig(rows: rows)
        defer { rig.cleanUp() }
        await rig.open()
        let newest = try #require(rig.model.current)
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        let opened = try #require(rig.model.files.document)
        #expect(opened.answerStart == newest.start && opened.answerAt == newest.at && newest.at != nil)
        #expect(rig.model.copy("Plate 7 failed.", from: opened))
        #expect(rig.history.copied.last == ReferenceRules.copyText("Plate 7 failed.", session: ReferenceModelTests.session,
                                                                   at: newest.at, file: "plate_qc_notes.md"))
        // A document of the older reply, with the page on the newer one: its copy is the older reply's.
        let older = try #require(rig.model.answers.first { $0.start != newest.start })
        #expect(older.at != nil && older.at != newest.at)
        let elsewhere = ReferenceDocument(file: FilesRig.notes, rendered: ReferenceRules.plainText("Plate 7 failed."), cut: false,
                                          isEmpty: false, answerStart: older.start, answerAt: older.at)
        rig.model.files.show(elsewhere)
        #expect(rig.model.copy("Plate 7 failed.", from: elsewhere))
        let copied = try #require(rig.history.copied.last)
        #expect(copied == ReferenceRules.copyText("Plate 7 failed.", session: ReferenceModelTests.session, at: older.at,
                                                  file: "plate_qc_notes.md"))
        #expect(copied != ReferenceRules.copyText("Plate 7 failed.", session: ReferenceModelTests.session, at: newest.at,
                                                  file: "plate_qc_notes.md"))
        // A document with no reply known (a demo's) takes the page's.
        let unplaced = ReferenceDocument(file: FilesRig.notes, rendered: ReferenceRules.plainText("x"), cut: false, isEmpty: false)
        #expect(rig.model.copy("x", from: unplaced))
        #expect(rig.history.copied.last == ReferenceRules.copyText("x", session: ReferenceModelTests.session, at: newest.at,
                                                                   file: "plate_qc_notes.md"))
        rig.model.close()
    }

    @Test func addToShelfOnADocumentKeepsItWithTheWordsAroundIt() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        rig.model.openFile(FilesRig.notes)
        await rig.settle()
        #expect(rig.model.shelfMark(FilesRig.notes) == .off)
        let outcome = await rig.model.addToShelf(FilesRig.notes)
        guard case .added? = outcome else { Issue.record("not added: \(String(describing: outcome))"); return }
        let source = try #require(rig.shelf.added.first)
        #expect(source.entry.version == FilesRig.notes.v && source.entry.name == "plate_qc_notes.md")
        #expect(source.answer?.text == "Plate 7 is low.")
        #expect(source.question == "Plot Z′ by plate.")
        #expect(rig.model.shelfMark(FilesRig.notes) == .on)
    }

    @Test func copyWithSourceNamesTheDocument() async throws {
        let rig = FilesRig()
        defer { rig.cleanUp() }
        await rig.open()
        #expect(rig.model.copy("Plate 7 failed.", file: "plate_qc_notes.md"))
        let copied = try #require(rig.history.copied.last)
        #expect(copied.hasPrefix("Plate 7 failed.\n\n\u{2014} plate_qc_notes.md, Claude, in \u{201C}Plate reader QC\u{201D} (Assay development)"))
        #expect(copied.contains("bench://session?"))
        // The answer's own copy is as it was.
        #expect(rig.model.copy("Eleven passed."))
        #expect(rig.history.copied.last?.contains("\u{2014} Claude, in \u{201C}Plate reader QC\u{201D}") == true)
    }

    // MARK: Esc and ⌘[

    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func theKeysThatGoBackAreEscAndCommandBracket() {
        #expect(ReferenceFileRules.goesBack(keyCode: 53, charactersIgnoringModifiers: "\u{1B}", modifiers: []))
        #expect(ReferenceFileRules.goesBack(keyCode: 33, charactersIgnoringModifiers: "[", modifiers: .command))
        // Caps Lock and the numeric pad don't change a key's meaning.
        #expect(ReferenceFileRules.goesBack(keyCode: 53, charactersIgnoringModifiers: "\u{1B}", modifiers: .capsLock))
        // Nothing else does: ] goes forward, \u{21E7}\u{2318}[ is another command, a plain [ is a character.
        #expect(!ReferenceFileRules.goesBack(keyCode: 30, charactersIgnoringModifiers: "]", modifiers: .command))
        #expect(!ReferenceFileRules.goesBack(keyCode: 33, charactersIgnoringModifiers: "[", modifiers: [.command, .shift]))
        #expect(!ReferenceFileRules.goesBack(keyCode: 33, charactersIgnoringModifiers: "[", modifiers: []))
        #expect(!ReferenceFileRules.goesBack(keyCode: 53, charactersIgnoringModifiers: "\u{1B}", modifiers: .command))
    }

    @Test func escAndCommandBracketLeaveTheDocumentWhenTheWindowGetsThem() async throws {
        for (code, characters, modifiers) in [(UInt16(53), "\u{1B}", NSEvent.ModifierFlags()), (33, "[", .command)] {
            let rig = FilesRig()
            defer { rig.cleanUp() }
            await rig.open()
            let window = ReferenceWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled],
                                         backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.goBack = ReferenceWindowController.goBack(for: rig.model)
            // No document open: the keys are not the window's.
            #expect(!window.performKeyEquivalent(with: try key(code, characters, modifiers, in: window)))
            rig.model.openFile(FilesRig.notes)
            await rig.settle()
                #expect(rig.model.files.document != nil)
            // Another command key is not a way back.
            _ = window.performKeyEquivalent(with: try key(30, "]", .command, in: window))
            #expect(rig.model.files.document != nil)
            #expect(window.performKeyEquivalent(with: try key(code, characters, modifiers, in: window)))
            #expect(rig.model.files.document == nil)
        }
    }

    @Test func aWindowHandsItselfTheQuickLookPanelsControl() {
        let window = ReferenceWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled],
                                     backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(window.acceptsPreviewPanelControl(nil))
    }
}
