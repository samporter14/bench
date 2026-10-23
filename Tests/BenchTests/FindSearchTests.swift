// FindSearchTests.swift — the searcher that looks for figures and files while
// typing (wait for the pause, one read at a time off the main actor, drop an
// answer for a query that moved on, say when the database can't be read), the
// Shelf window's finder over it (what is shown, adding, the pictures), and
// Quick Open's group. Made-up files; no database, no window.
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Bench

// MARK: The searcher

@MainActor
private final class FindRig {
    /// The queries each read was asked for.
    private(set) var lookups: [FindQuery] = []
    private var replies: [CheckedContinuation<[FoundFile]?, Never>?] = []
    private var pauses: [CheckedContinuation<Void, Never>] = []
    private(set) var waits = 0

    func search() -> FindSearch {
        FindSearch(dependencies: .init(
            lookup: { [unowned self] query in
                lookups.append(query)
                return await withCheckedContinuation { replies.append($0) }
            },
            pause: .milliseconds(250),
            wait: { [unowned self] _ in
                waits += 1
                await withCheckedContinuation { pauses.append($0) }
            },
            now: { FindTime.now }))
    }

    func pauseElapses() async {
        await settle()
        let waiting = pauses
        pauses = []
        waiting.forEach { $0.resume() }
        await settle()
    }

    func answer(_ index: Int, _ files: [FoundFile]?) async {
        replies[index]?.resume(returning: files)
        replies[index] = nil
        await settle()
    }

    func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    isolated deinit {
        replies.forEach { $0?.resume(returning: nil) }
        pauses.forEach { $0.resume() }
    }
}

@MainActor
struct FindSearchTests {
    @Test func nothingIsReadUntilTypingPausesThenTheAnswerIsRanked() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("volcano")
        await rig.settle()
        #expect(rig.lookups.isEmpty && search.isSearching && search.query != nil)
        await rig.pauseElapses()
        #expect(rig.lookups.map(\.phrase) == ["volcano"])
        let t = FindTime.midnight
        await rig.answer(0, [madeFile("a_volcano.png", ms: t + 300), madeFile("volcano.png", ms: t + 100)])
        // The exact name first, though older.
        #expect(search.files.map(\.name) == ["volcano.png", "a_volcano.png"])
        #expect(!search.isSearching && !search.couldntRead && !search.mayHaveMore)
    }

    @Test func typingOnInsideThePauseReadsOnlyTheLastQuery() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("vo")
        search.update("volc")
        search.update("volcano plot")
        await rig.pauseElapses()
        #expect(rig.waits == 3)
        #expect(rig.lookups.map(\.phrase) == ["volcano plot"])
    }

    @Test func aTrailingSpaceDoesNotSearchAgainAndAChangedChipDoes() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("volcano")
        await rig.pauseElapses()
        await rig.answer(0, [madeFile("volcano.png")])
        search.update("volcano ")
        await rig.pauseElapses()
        #expect(rig.lookups.count == 1 && search.files.count == 1)
        search.update("volcano", kind: .figure)
        await rig.pauseElapses()
        #expect(rig.lookups.count == 2 && rig.lookups.last?.kind == .figure)
        search.update("volcano", kind: .figure, project: "Assay development")
        await rig.pauseElapses()
        #expect(rig.lookups.last?.project == "Assay development")
    }

    @Test func anAnswerForAnOlderQueryIsDropped() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("volcano")
        await rig.pauseElapses()
        // Typing resumes while the database is read.
        search.update("volcano plot")
        await rig.pauseElapses()
        await rig.answer(0, [madeFile("old.png")])
        #expect(search.files.isEmpty && search.isSearching)
        await rig.answer(1, [madeFile("new.png")])
        #expect(search.files.map(\.name) == ["new.png"] && !search.isSearching)
    }

    @Test func tooLittleClearsWhatWasFoundAndStopsTheSearch() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("volcano")
        await rig.pauseElapses()
        await rig.answer(0, [madeFile("volcano.png")])
        search.update("v")
        #expect(search.files.isEmpty && search.query == nil && !search.isSearching)
        // A search under way when the text is emptied: its answer lands nowhere.
        search.update("heat")
        await rig.pauseElapses()
        search.update("")
        await rig.answer(1, [madeFile("heat.png")])
        #expect(search.files.isEmpty && search.query == nil)
    }

    @Test func aDatabaseThatCantBeReadSaysSoAndTheNextKeystrokeTriesAgain() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("volcano")
        await rig.pauseElapses()
        await rig.answer(0, [madeFile("volcano.png")])
        search.update("volcano plot")
        await rig.pauseElapses()
        await rig.answer(1, nil)
        // What was found for other words is gone, not left looking right.
        #expect(search.files.isEmpty && search.couldntRead && !search.isSearching)
        // The same words again look again.
        search.update("volcano plot x")
        search.update("volcano plot")
        await rig.pauseElapses()
        #expect(rig.lookups.count == 3 && !search.couldntRead)
    }

    @Test func anAnswerAsLongAsTheLimitMayHaveMore() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("png", limit: 3)
        await rig.pauseElapses()
        await rig.answer(0, (1...3).map { madeFile("f\($0).png") })
        #expect(search.mayHaveMore)
        search.update("png ", limit: 3)
        search.update("png z", limit: 3)
        await rig.pauseElapses()
        await rig.answer(1, [madeFile("z.png")])
        #expect(!search.mayHaveMore)
    }

    @Test func cancellingForgetsEverything() async {
        let rig = FindRig()
        let search = rig.search()
        search.update("volcano")
        await rig.pauseElapses()
        await rig.answer(0, [madeFile("volcano.png")])
        search.cancel()
        #expect(search.files.isEmpty && search.query == nil && !search.isSearching && !search.couldntRead)
    }

    @Test func theLiveReadRunsOffTheMainActorAndStopsWhenItsTaskIsCancelled() async throws {
        let query = try #require(FindTime.parse("volcano"))
        // It reads the database it resolved, with the query it was given, and not on the main thread.
        let files = await FindSearch.databaseFiles(query, resolve: { URL(fileURLWithPath: "/made-up.db") }, read: { db, asked, _ in
            #expect(!Thread.isMainThread && db.path == "/made-up.db" && asked == query)
            return [madeFile("volcano.png")]
        })
        #expect(files?.map(\.name) == ["volcano.png"])
        // No database: nil, nothing read.
        let none = await FindSearch.databaseFiles(query, resolve: { nil }, read: { _, _, _ in
            Issue.record("read without a database")
            return []
        })
        #expect(none == nil)
        // A failed read is nil too.
        struct Boom: Error {}
        let failed = await FindSearch.databaseFiles(query, resolve: { URL(fileURLWithPath: "/x.db") }, read: { _, _, _ in throw Boom() })
        #expect(failed == nil)
        // Cancelling the asking task trips the read's token.
        let tripped = Tripped()
        let task = Task.detached {
            await FindSearch.databaseFiles(query, resolve: { URL(fileURLWithPath: "/x.db") }, read: { _, _, token in
                tripped.start()
                for _ in 0..<500 where !token.isCancelled { Thread.sleep(forTimeInterval: 0.01) }
                tripped.finish(sawCancel: token.isCancelled)
                return []
            })
        }
        while !tripped.started { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        _ = await task.value
        #expect(tripped.sawCancel)
    }

    private final class Tripped: @unchecked Sendable {
        private let lock = NSLock()
        private var _started = false, _sawCancel = false
        var started: Bool { lock.withLock { _started } }
        var sawCancel: Bool { lock.withLock { _sawCancel } }
        func start() { lock.withLock { _started = true } }
        func finish(sawCancel: Bool) { lock.withLock { _sawCancel = sawCancel } }
    }
}

// MARK: The Shelf window's finder

@MainActor
private final class FinderRig {
    var onShelf: Set<String> = []
    var adding: Set<String> = []
    var outcome: ShelfAddOutcome = .failed("It was stopped.")
    private(set) var added: [String] = []
    private(set) var shown: [String] = []
    private(set) var results: [String] = []
    private(set) var asked: [String] = []
    let lookup = FindRig()
    let changes = PassthroughSubject<Void, Never>()
    var available = true

    func finder() -> ShelfFinder {
        let actions = FindActions(
            isAvailable: available,
            add: { [unowned self] file in
                added.append(file.version)
                return outcome
            },
            show: { [unowned self] in shown.append($0.version) },
            results: { [unowned self] in results.append($0.version) },
            onShelf: { [unowned self] in onShelf.contains($0) },
            isAdding: { [unowned self] in adding.contains($0) })
        return ShelfFinder(search: lookup.search(), actions: actions, thumbnails: ShelfThumbnails(),
                           requestThumbnail: { [unowned self] in asked.append($0.version) }, changes: changes.eraseToAnyPublisher())
    }

    /// Types `text` and answers the read with `files`.
    func type(_ text: String, into finder: ShelfFinder, answer files: [FoundFile], project: String? = nil, kind: ShelfKind? = nil) async {
        finder.scopeChanged(text: text, project: project, kind: kind)
        await lookup.pauseElapses()
        await lookup.answer(lookup.lookups.count - 1, files)
    }
}

@MainActor
struct ShelfFinderTests {
    @Test func theSectionShowsWhatIsNotOnTheShelfAndCountsIt() async {
        let rig = FinderRig()
        rig.onShelf = ["on-shelf"]
        let finder = rig.finder()
        #expect(!finder.isWanted)
        await rig.type("volcano", into: finder, answer: [
            madeFile("a.png", version: "on-shelf"), madeFile("b_volcano.png", version: "free"), madeFile("volcano.png", version: "other"),
        ])
        #expect(finder.isWanted)
        #expect(finder.visible.map(\.version) == ["other", "free"])
        #expect(finder.countText == "2")
    }

    @Test func aFullAnswerIsCountedWithAPlus() async {
        let rig = FinderRig()
        let finder = rig.finder()
        finder.scopeChanged(text: "png", project: nil, kind: nil)
        await rig.lookup.pauseElapses()
        await rig.lookup.answer(0, (1...FindQuery.defaultLimit).map { madeFile("f\($0).png") })
        #expect(finder.countText == "\(FindQuery.defaultLimit)+")
    }

    @Test func theShelfsPillAndTheKindChipReachTheSearch() async {
        let rig = FinderRig()
        let finder = rig.finder()
        await rig.type("heatmap", into: finder, answer: [], project: "Paper draft", kind: .table)
        #expect(rig.lookup.lookups.last?.project == "Paper draft" && rig.lookup.lookups.last?.kind == .table)
    }

    @Test func addingPutsTheFileOnTheShelfAndKeepsItInTheListAsOnShelf() async {
        let rig = FinderRig()
        let finder = rig.finder()
        let file = madeFile("volcano.png", version: "v1")
        await rig.type("volcano", into: finder, answer: [file])
        #expect(finder.mark(of: file) == .off)
        let folder = URL(fileURLWithPath: "/made-up/Kept/Assay development/volcano")
        rig.outcome = .added(ShelfPlacement(folder: folder, name: "volcano.png", collection: "Assay development"))
        finder.add(file)
        await rig.lookup.settle()
        #expect(rig.added == ["v1"])
        // The shelf now has it (as the real one does), and the row stays, marked.
        rig.onShelf = ["v1"]
        #expect(finder.visible.map(\.version) == ["v1"] && finder.mark(of: file) == .on)
        // "On Shelf ✓" opens the item in the grid.
        var selected: URL?
        finder.selectFolder = { selected = $0 }
        finder.showOnShelf(file)
        #expect(selected == folder)
        // A new search drops it, as it is on the shelf.
        await rig.type("volcano plot", into: finder, answer: [file])
        #expect(finder.visible.isEmpty)
    }

    @Test func aFailedAddSaysWhyUnderTheFileAndDoesNotMarkIt() async {
        let rig = FinderRig()
        let finder = rig.finder()
        let file = madeFile("volcano.png", version: "v1")
        await rig.type("volcano", into: finder, answer: [file])
        rig.outcome = .failed("Capsid couldn\u{2019}t add volcano.png. It was stopped.")
        finder.add(file)
        await rig.lookup.settle()
        #expect(finder.problems["v1"] == "Capsid couldn\u{2019}t add volcano.png. It was stopped.")
        #expect(finder.mark(of: file) == .off && finder.visible.count == 1)
        // Trying again clears the sentence.
        rig.outcome = .added(ShelfPlacement(folder: URL(fileURLWithPath: "/made-up/a"), name: "volcano.png", collection: "A"))
        finder.add(file)
        await rig.lookup.settle()
        #expect(finder.problems["v1"] == nil && finder.mark(of: file) == .on)
    }

    @Test func aFileBeingAddedOrAlreadyThereIsNotAddedAgain() async {
        let rig = FinderRig()
        let finder = rig.finder()
        let file = madeFile("volcano.png", version: "v1")
        await rig.type("volcano", into: finder, answer: [file])
        rig.adding = ["v1"]
        #expect(finder.mark(of: file) == .adding)
        finder.add(file)
        await rig.lookup.settle()
        #expect(rig.added.isEmpty)
        rig.adding = []
        rig.onShelf = ["v1"]
        finder.add(file)
        await rig.lookup.settle()
        #expect(rig.added.isEmpty)
    }

    @Test func showingWhereAndOpeningInResultsAreTheActionsOnes() async {
        let rig = FinderRig()
        let finder = rig.finder()
        let file = madeFile("volcano.png", version: "v1")
        finder.showWhere(file)
        finder.openInResults(file)
        #expect(rig.shown == ["v1"] && rig.results == ["v1"])
        rig.available = false
        let demo = rig.finder()
        demo.showWhere(file)
        demo.openInResults(file)
        demo.add(file)
        await rig.lookup.settle()
        #expect(rig.shown == ["v1"] && rig.results == ["v1"] && rig.added.isEmpty)
    }

    @Test func theWordsChangingForgetsWhatWasAddedButAChipDoesNot() async {
        let rig = FinderRig()
        let finder = rig.finder()
        let file = madeFile("volcano.png", version: "v1")
        await rig.type("volcano", into: finder, answer: [file])
        rig.outcome = .added(ShelfPlacement(folder: URL(fileURLWithPath: "/made-up/a"), name: "volcano.png", collection: "A"))
        finder.add(file)
        await rig.lookup.settle()
        #expect(finder.added.keys.contains("v1"))
        finder.scopeChanged(text: "volcano", project: nil, kind: .figure)
        #expect(finder.added.keys.contains("v1"))
        finder.scopeChanged(text: "  volcano   ", project: nil, kind: .figure)
        #expect(finder.added.keys.contains("v1"))
        finder.scopeChanged(text: "volcano plot", project: nil, kind: .figure)
        #expect(finder.added.isEmpty && finder.problems.isEmpty)
        finder.cancel()
        #expect(!finder.isWanted)
    }

    @Test func aPictureIsAskedForOnlyForAPictureNotAlreadyReadAndNotInADemo() async {
        // The gate is shared: forget the typing the other tests did.
        ReadingGate.shared.noteKey(at: .distantPast)
        let rig = FinderRig()
        let finder = rig.finder()
        await finder.wantPicture(of: madeFile("table.csv", version: "t1"))
        await finder.wantPicture(of: madeFile("notes.md", version: "d1"))
        #expect(rig.asked.isEmpty)
        await finder.wantPicture(of: madeFile("volcano.png", version: "p1"))
        #expect(rig.asked == ["p1"])
        // One the store has read already is not read again.
        finder.thumbnails.insert(Self.pixel(), for: "p2")
        await finder.wantPicture(of: madeFile("volcano.png", version: "p2"))
        #expect(rig.asked == ["p1"])
        rig.available = false
        await rig.finder().wantPicture(of: madeFile("volcano.png", version: "p3"))
        #expect(rig.asked == ["p1"])
    }

    @Test func theShelfChangingRedrawsTheSection() async {
        let rig = FinderRig()
        let finder = rig.finder()
        var redraws = 0
        let watch = finder.objectWillChange.sink { redraws += 1 }
        defer { watch.cancel() }
        rig.changes.send()
        for _ in 0..<20 { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
        #expect(redraws > 0)
    }

    private static func pixel() -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}

// MARK: Quick Open's group

struct QuickOpenFilesTests {
    private func session(_ id: String) -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Notebook", title: "Gel imaging", state: .finished,
                      updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    @Test func theFilesComeAfterTheSessionsInTheOrderGivenAndAreCapped() {
        let files = (1...10).map { madeFile("f\($0).png", version: "v\($0)") }
        let entries = QuickOpenFiles.entries(sessions: [session(madeUpID(1)), session(madeUpID(2))], files: files)
        #expect(entries.count == 2 + QuickOpenFiles.shown)
        #expect(entries.prefix(2).allSatisfy { if case .session = $0 { true } else { false } })
        #expect(entries.dropFirst(2).map(\.id) == (1...QuickOpenFiles.shown).map { "file:v\($0)" })
        // No sessions: the files alone, and nothing for no files.
        #expect(QuickOpenFiles.entries(sessions: [], files: Array(files.prefix(2))).count == 2)
        #expect(QuickOpenFiles.entries(sessions: [], files: []).isEmpty)
    }

    @Test func aFilesIdCanNeverBeASessionsId() {
        let file = madeFile("a.png", version: madeUpID(1))
        #expect(QuickOpenEntry.file(file).id != QuickOpenEntry.session(session(madeUpID(1))).id)
        #expect(QuickOpenEntry.file(file).id == "file:\(madeUpID(1))")
    }

    @Test func theRowSaysWhatReturnAndOptionReturnDo() {
        #expect(QuickOpenFiles.hint(onShelf: false) == "\u{21A9} Where from  \u{00B7}  \u{2325}\u{21A9} Add")
        #expect(QuickOpenFiles.hint(onShelf: true) == "\u{21A9} Where from  \u{00B7}  \u{2325}\u{21A9} Shelf")
        #expect(QuickOpenFiles.spokenHint(onShelf: false).contains("Return shows where it came from"))
        #expect(QuickOpenFiles.spokenHint(onShelf: false).contains("adds it to your shelf"))
        #expect(QuickOpenFiles.spokenHint(onShelf: true).contains("where it already is"))
        #expect(QuickOpenFiles.heading == "Figures and files")
    }

    @Test func theSheetAsksForFilesWithTheQueryAndShowsTheGroupUnderTheSessions() {
        let sheet = FindRepo.source("Lab/QuickOpenSheet.swift")
        #expect(sheet.contains("files.update(query, limit: QuickOpenFiles.asked)"))
        #expect(sheet.contains("QuickOpenFiles.entries(sessions: QuickOpen.rank(reads.sessions, plus: search.found, query: query),"))
        #expect(sheet.contains("QuickOpenFiles.heading"))
        // Return shows where; ⌥↩ adds.
        #expect(sheet.contains("case .file(let file)?: showWhere(file)") && sheet.contains("case .file(let file)?: addToShelf(file)"))
        #expect(sheet.contains("files.cancel()"))
    }

    @MainActor
    @Test func optionReturnAddsAndSaysSoInTheToast() async {
        var outcomes: [ShelfAddOutcome] = [
            .added(ShelfPlacement(folder: URL(fileURLWithPath: "/made-up/a"), name: "a.png", collection: "A")),
            .alreadyOnShelf(ShelfPlacement(folder: URL(fileURLWithPath: "/made-up/a"), name: "a.png", collection: "A")),
            .failed("Capsid couldn\u{2019}t add a.png. It was stopped."),
        ]
        let actions = FindActions(isAvailable: true, add: { _ in outcomes.removeFirst() }, show: { _ in }, results: { _ in },
                                  onShelf: { _ in false }, isAdding: { _ in false })
        let access = ShelfAccess(contains: { _ in false }, count: { 0 }, add: { _ in .failed("") })
        let toast = ShelfToastModel(shelf: access, announce: { _ in })
        await actions.addSayingSo(madeFile("a.png"), toast: toast)
        if case .added? = toast.state {} else { Issue.record("not added: \(String(describing: toast.state))") }
        await actions.addSayingSo(madeFile("a.png"), toast: toast)
        if case .already? = toast.state {} else { Issue.record("not already") }
        await actions.addSayingSo(madeFile("a.png"), toast: toast)
        if case .failed(let sentence)? = toast.state { #expect(sentence.hasPrefix("Capsid couldn")) } else { Issue.record("not failed") }
        // Not in a demo: no toast, no add.
        let demo = FindActions(isAvailable: false, add: { _ in
            Issue.record("added in a demo")
            return .failed("")
        }, show: { _ in }, results: { _ in }, onShelf: { _ in false }, isAdding: { _ in false })
        toast.dismiss()
        await demo.addSayingSo(madeFile("a.png"), toast: toast)
        #expect(toast.state == nil)
    }
}
