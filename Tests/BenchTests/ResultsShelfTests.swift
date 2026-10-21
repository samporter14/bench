// ResultsShelfTests.swift — the results shelf on made-up sessions and files:
// what it covers (recent sessions taken when it opens, the newest few read,
// older ones a page at a time and only when asked), how its reads go (two at a
// time, within a time limit, stopped when the window closes), what each failure
// says, the phone's own checks on kinds and sizes, Quick Look's, a drag's and
// Copy's temporary copies and pasteboard content, Save All, the folder
// remembered per project, and showing one session. A file reaches the disk only
// through Save, Save All, and the private temporary copies. Nothing here
// reaches a page, a daemon, the real pasteboard or the real temporary folder:
// the disk is a scratch folder made for each test.
import AppKit
import Foundation
import Testing
@testable import Bench

// MARK: Made-up sessions and files

private let start = Date(timeIntervalSince1970: 1_792_000_000)

private func made(_ n: Int, project: String = "proj_a", minutesAgo: Double? = nil) -> SessionStatus {
    let name = project == "proj_a" ? "Made-up A" : "Made-up B"
    return SessionStatus(id: madeUpID(n), projectID: project, projectName: name, title: "Made-up session \(n)",
                         state: .finished, updatedAt: start.addingTimeInterval(-60 * (minutesAgo ?? Double(n))),
                         deepLink: URL(string: "http://localhost:8765/projects/\(project)/frames/\(madeUpID(n))"))
}

private func entry(_ name: String, version: String, size: Int = 1_024, mime: String? = nil) -> ArtifactEntry {
    ArtifactEntry(version: version, artifact: nil, name: name, mime: mime, size: size, at: start)
}

private let webp = Data("RIFF\u{4}\0\0\0WEBPVP8L".utf8)

/// What the fake disk holds and was asked to write. Saved files are written
/// off the main actor, so the fake's writer reaches it under a lock.
private final class FakeDisk: @unchecked Sendable {
    struct State {
        /// Paths that exist already; what is "written" is added.
        var existing: Set<String> = []
        var written: [URL] = []
        var writtenBytes: [Data] = []
        var writeFails = false
        /// Writes to the disk for real, instead of only recording them.
        var realWrites = false
        /// Whether each write ran on the main thread.
        var onMain: [Bool] = []
        /// What the shelf asked the disk, and whether each ask ran on the main thread.
        var existsCalls: [String] = []
        var listCalls: [String] = []
        var looksOnMain: [Bool] = []
        /// How the folder listing answers: with the names, with nil (too many), or with an error.
        var listing: Listing = .names
    }

    enum Listing { case names, tooMany, fails }

    private let lock = NSLock()
    private var state = State()

    func with<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    /// Whether a path is there, as the shelf asks the disk (off the main actor).
    func exists(_ url: URL) -> Bool {
        let (found, real) = with { state in
            state.existsCalls.append(url.path)
            state.looksOnMain.append(Thread.isMainThread)
            return (state.existing.contains(url.path), state.realWrites)
        }
        return found || (real && FileManager.default.fileExists(atPath: url.path))
    }

    /// The names in a folder, as the shelf asks the disk (off the main actor).
    func list(_ folder: URL) throws -> [String]? {
        let (names, listing, real) = with { state in
            state.listCalls.append(folder.path)
            state.looksOnMain.append(Thread.isMainThread)
            let inFolder = state.existing.filter { ($0 as NSString).deletingLastPathComponent == folder.path }
            return (inFolder.map { ($0 as NSString).lastPathComponent }, state.listing, state.realWrites)
        }
        switch listing {
        case .tooMany: return nil
        case .fails: throw CocoaError(.fileReadNoPermission)
        case .names: return names + (real ? ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) : [])
        }
    }

    /// The saved-file writer the shelf runs off the main actor.
    func write(_ data: Data, to url: URL) throws {
        let (fails, real) = with { ($0.writeFails, $0.realWrites) }
        with { $0.onMain.append(Thread.isMainThread) }
        if fails { throw CocoaError(.fileWriteNoPermission) }
        if real { try data.write(to: url, options: .atomic) }
        with { state in
            state.written.append(url)
            state.writtenBytes.append(data)
            state.existing.insert(url.path)
        }
    }
}

/// Stands in for the page, the database, the clock and the disk: answers
/// from tables, records every read and write, and can hold reads until let go.
@MainActor
private final class FakeShelf {
    var recent: [SessionStatus] = []
    var lists: [String: ArtifactReadOutcome] = [:]
    var files: [ArtifactRead: ArtifactReadOutcome] = [:]
    var olderPages: [OlderPage?] = []
    var ready = true
    var hold = false
    var expireAtOnce = false
    let disk = FakeDisk()
    var writeFails: Bool {
        get { disk.with { $0.writeFails } }
        set { disk.with { $0.writeFails = newValue } }
    }
    /// Paths that exist already (the fake disk); what is "written" is added.
    var existing: Set<String> {
        get { disk.with { $0.existing } }
        set { disk.with { $0.existing = newValue } }
    }
    /// Writes to the disk for real, instead of only recording them.
    var realWrites: Bool {
        get { disk.with { $0.realWrites } }
        set { disk.with { $0.realWrites = newValue } }
    }
    /// The paths the shelf asked the disk about, and the folders it listed.
    var existsCalls: [String] { disk.with { $0.existsCalls } }
    var listCalls: [String] { disk.with { $0.listCalls } }
    /// Whether any look at the disk ran on the main thread.
    var anyLookOnMain: Bool { disk.with { $0.looksOnMain.contains(true) } }
    var listing: FakeDisk.Listing {
        get { disk.with { $0.listing } }
        set { disk.with { $0.listing = newValue } }
    }
    var pasteboardFails = false
    var now = start
    private(set) var reads: [ArtifactRead] = []
    private(set) var olderCursors: [BrowseCursor?] = []
    private(set) var inFlight = 0
    private(set) var mostAtOnce = 0
    private(set) var opened: [String] = []
    var written: [URL] { disk.with { $0.written } }
    var writtenBytes: [Data] { disk.with { $0.writtenBytes } }
    private(set) var savedNotices: [URL] = []
    private(set) var copied: [ShelfCopyContent] = []
    private var gates: [CheckedContinuation<Void, Never>] = []
    /// A folder of this test's own, for the temporary copies and anything real.
    let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var temporaryFolder: URL { scratch.appending(path: ShelfTemporaryCopies.folderName, directoryHint: .isDirectory) }
    let suite = "capsid-tests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
        // A suite nothing was saved in has no file to clean up.
        if let used = UserDefaults(suiteName: suite), used.persistentDomain(forName: suite) != nil {
            used.removePersistentDomain(forName: suite)
        }
    }

    func shelf(thumbnails: ShelfThumbnails = ShelfThumbnails()) -> ResultsShelf {
        ResultsShelf(dependencies: ResultsShelf.Dependencies(
            recent: { [unowned self] in self.recent },
            older: { [unowned self] cursor in
                self.olderCursors.append(cursor)
                await Task.yield()
                return self.olderPages.isEmpty ? nil : self.olderPages.removeFirst()
            },
            read: { [unowned self] read in
                self.reads.append(read)
                self.inFlight += 1
                self.mostAtOnce = max(self.mostAtOnce, self.inFlight)
                if self.hold { await withCheckedContinuation { self.gates.append($0) } } else { await Task.yield() }
                self.inFlight -= 1
                if case .list(let frame) = read { return self.lists[frame] ?? .list([]) }
                return self.files[read] ?? .unreadable
            },
            isReady: { [unowned self] in self.ready },
            open: { [unowned self] in self.opened.append($0.id) },
            didSave: { [unowned self] in self.savedNotices.append($0) },
            write: { [disk] data, url in try disk.write(data, to: url) },
            now: { [unowned self] in self.now },
            wait: { [unowned self] limit in
                if self.expireAtOnce { return }
                try? await Task.sleep(for: limit)
            },
            temporaryFolder: temporaryFolder,
            exists: { [disk] url in disk.exists(url) },
            list: { [disk] folder in try disk.list(folder) },
            defaults: defaults,
            pasteboard: { [unowned self] content in
                if self.pasteboardFails { return false }
                self.copied.append(content)
                return true
            }), thumbnails: thumbnails)
    }

    /// Lets every held read answer.
    func release() {
        let waiting = gates
        gates = []
        waiting.forEach { $0.resume() }
    }

    var listReads: [String] {
        reads.compactMap { if case .list(let frame) = $0 { frame } else { nil } }
    }

    /// The versions downloaded whole, in the order asked.
    var downloads: [String] {
        reads.compactMap { if case .download(let version) = $0 { version } else { nil } }
    }
}

/// Lets the other work run until `condition` holds: saved files are written
/// off the main actor, so a fixed number of turns isn't enough. No clock.
@MainActor
private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    // A minute's limit is only a safety net for a broken run.
    let limit = ContinuousClock.now + .seconds(60)
    while !condition(), ContinuousClock.now < limit { await Task.yield() }
    if !condition() { Issue.record("the condition never held", sourceLocation: sourceLocation) }
}

@MainActor
private func results(_ shelf: ResultsShelf, _ n: Int) -> ShelfResults? {
    shelf.sessions.first { $0.id == madeUpID(n) }?.results
}

private let cap = ArtifactReaderScript.Cap.download

private func permissions(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

/// Every file under a folder, as paths relative to it (none when it isn't there).
private func files(under folder: URL) -> [String] {
    let paths = (try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []
    return paths.filter { path in
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.appending(path: path).path, isDirectory: &isFolder) && !isFolder.boolValue
    }.sorted()
}

@MainActor
struct ResultsShelfTests {
    private let fake = FakeShelf()

    // MARK: What it covers

    @Test func theNewestRecentSessionsAreReadAndTheRestWait() async {
        fake.recent = (1...10).map { made($0, project: $0 % 3 == 0 ? "proj_b" : "proj_a") }
        fake.lists[madeUpID(1)] = .list([entry("figure.png", version: "v-png", mime: "image/png"),
                                         entry("report.md", version: "v-md")])
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(fake.listReads == (1...8).map(madeUpID))
        #expect(results(shelf, 9) == .notLoaded)
        #expect(results(shelf, 10) == .notLoaded)
        // Documents first, as the phone lists them.
        #expect(results(shelf, 1)?.entries?.map(\.name) == ["report.md", "figure.png"])
        #expect(results(shelf, 2) == .loaded([], at: start))
        let groups = shelf.groups
        #expect(groups.map(\.id) == ["recent-proj_a", "recent-proj_b"])
        #expect(groups[0].projectName == "Made-up A")
        #expect(groups[1].sessions.map(\.id) == [3, 6, 9].map(madeUpID))
        #expect(shelf.coverageLine == "Your 10 most recent sessions, 8 read. Older sessions load only when you ask.")
        // The rest when asked for.
        shelf.load(madeUpID(9))
        await shelf.settled()
        #expect(fake.listReads.last == madeUpID(9))
        #expect(results(shelf, 9) == .loaded([], at: start))
    }

    @Test func readsGoTwoAtATime() async {
        fake.recent = (1...8).map { made($0) }
        fake.hold = true
        let shelf = fake.shelf()
        shelf.open()
        for _ in 0..<10 { await Task.yield() }
        #expect(shelf.readsUnderWay == 2)
        #expect(fake.inFlight == 2)
        #expect(shelf.sessions.filter { $0.results == .queued }.count == 6)
        fake.hold = false
        fake.release()
        await shelf.settled()
        #expect(fake.mostAtOnce == 2)
        #expect(fake.listReads.count == 8)
        #expect(shelf.sessions.allSatisfy { $0.results.entries != nil })
    }

    @Test func notConnectedReadsNothing() async {
        fake.recent = [made(1), made(2)]
        fake.ready = false
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(fake.reads.isEmpty)
        #expect(results(shelf, 1) == .failed(.notReady))
        #expect(ShelfFailure.notReady.sentence == "Capsid isn't connected to Claude Science right now.")
    }

    @Test func reopeningKeepsWhatWasReadLately() async {
        fake.recent = [made(1), made(2)]
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        shelf.close()
        shelf.open()
        await shelf.settled()
        #expect(fake.listReads.count == 2)
        fake.now = start.addingTimeInterval(ResultsShelf.freshFor + 1)
        shelf.close()
        shelf.open()
        await shelf.settled()
        #expect(fake.listReads.count == 4)
        shelf.open(refresh: true)
        await shelf.settled()
        #expect(fake.listReads.count == 6)
    }

    // MARK: Failures

    @Test func eachFailureSaysWhyAndTriesAgain() async {
        fake.recent = [made(1), made(2), made(3)]
        fake.lists[madeUpID(1)] = .missing
        fake.lists[madeUpID(2)] = .lost
        fake.lists[madeUpID(3)] = .unreadable
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(results(shelf, 1) == .failed(.missing))
        #expect(results(shelf, 2) == .failed(.signedOut))
        #expect(results(shelf, 3) == .failed(.unreadable))
        #expect(ShelfFailure.missing.sentence == "This isn't in Claude Science any more.")
        fake.lists[madeUpID(1)] = .list([entry("report.md", version: "v-md")])
        shelf.load(madeUpID(1))
        await shelf.settled()
        #expect(results(shelf, 1)?.entries?.map(\.version) == ["v-md"])
    }

    @Test func aMalformedListIsUnreadable() async throws {
        fake.recent = [made(1)]
        // A version id unfit for a path: the reader's own check refuses the whole list.
        let malformed = Data(#"{"outcome":"list","artifacts":[{"v":"../made-up","a":null,"name":"x.md","mime":null,"size":1,"at":null}]}"#.utf8)
        fake.lists[madeUpID(1)] = ArtifactReaderScript.outcome(of: malformed, for: .list(frame: madeUpID(1)))
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(results(shelf, 1) == .failed(.unreadable))
    }

    @Test func aReadThatNeverAnswersRunsOutOfTime() async {
        fake.recent = [made(1)]
        fake.hold = true
        fake.expireAtOnce = true
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(results(shelf, 1) == .failed(.timedOut))
        // The read answering late changes nothing.
        fake.lists[madeUpID(1)] = .list([entry("late.md", version: "v-late")])
        fake.release()
        for _ in 0..<5 { await Task.yield() }
        #expect(results(shelf, 1) == .failed(.timedOut))
    }

    @Test func closingStopsTheReadsAndLateAnswersLandNowhere() async {
        fake.recent = (1...4).map { made($0) }
        fake.lists[madeUpID(1)] = .list([entry("report.md", version: "v-md")])
        fake.hold = true
        let shelf = fake.shelf()
        shelf.open()
        for _ in 0..<10 { await Task.yield() }
        shelf.close()
        #expect(shelf.readsUnderWay == 0)
        #expect(shelf.sessions.allSatisfy { $0.results == .notLoaded })
        fake.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(shelf.sessions.allSatisfy { $0.results == .notLoaded })
        #expect(fake.listReads.count == 2, "only the two under way had started")
    }

    // MARK: Older sessions

    @Test func olderSessionsComeAPageAtATimeAndOnlyWhenAsked() async {
        fake.recent = [made(1), made(2)]
        let cursor = BrowseCursor(updatedMs: 1_791_000_000_000, id: madeUpID(21))
        fake.olderPages = [
            OlderPage(sessions: [made(20, project: "proj_b"), made(21, project: "proj_b"), made(1)], next: cursor),
            nil,
            OlderPage(sessions: [made(22)], next: nil),
        ]
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(shelf.older == .hidden)
        #expect(fake.olderCursors.isEmpty)
        shelf.showOlder()
        await shelf.settled()
        #expect(shelf.older == .shown(next: cursor))
        let older = shelf.sessions.filter { $0.coverage == .older }
        #expect(older.map(\.id) == [madeUpID(20), madeUpID(21)], "a recent session isn't listed twice")
        #expect(older.allSatisfy { $0.results == .notLoaded })
        #expect(fake.listReads.count == 2, "older sessions aren't read until asked")
        #expect(shelf.groups.map(\.id) == ["recent-proj_a", "older-proj_b"])
        // A page that fails is tried again from where it failed, keeping what was shown.
        shelf.showOlder()
        await shelf.settled()
        #expect(shelf.older == .failed)
        shelf.showOlder()
        await shelf.settled()
        #expect(fake.olderCursors == [nil, cursor, cursor])
        #expect(shelf.older == .shown(next: nil))
        #expect(shelf.sessions.filter { $0.coverage == .older }.map(\.id) == [20, 21, 22].map(madeUpID))
        shelf.load(madeUpID(20))
        await shelf.settled()
        #expect(fake.listReads.last == madeUpID(20))
    }

    @Test func aPageOfRowsSaysWhereTheNextStartsAndLinksEachSession() {
        let rows = (1...(BrowseSQL.pageSize + 1)).map {
            BrowseRow(id: madeUpID($0), projectID: "proj_a", projectName: "Made-up A", name: "Session \($0)",
                      status: "completed", createdMs: 1, updatedMs: 1_791_000_000_000 - Int64($0), completedMs: nil,
                      turnStartedMs: 1)
        }
        let page = OlderPage(rows: rows, port: 8765)
        #expect(page.sessions.count == BrowseSQL.pageSize)
        #expect(page.next == BrowseCursor(updatedMs: 1_791_000_000_000 - Int64(BrowseSQL.pageSize), id: madeUpID(BrowseSQL.pageSize)))
        #expect(page.sessions[0].deepLink?.absoluteString == "http://localhost:8765/projects/proj_a/frames/\(madeUpID(1))")
        #expect(OlderPage(rows: Array(rows.prefix(3)), port: nil).next == nil)
    }

    @Test func openConversationOpensWhereTheResultCameFrom() {
        fake.recent = [made(1)]
        let shelf = fake.shelf()
        shelf.open()
        shelf.openSession(made(1))
        #expect(fake.opened == [madeUpID(1)])
    }

    // MARK: Thumbnails

    @Test func aSecondSaveWhileOneRunsDoesNothing() async {
        fake.hold = true
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        let url = URL(fileURLWithPath: "/made-up/report.md")
        async let first = shelf.save(report, to: url)
        for _ in 0..<5 { await Task.yield() }
        #expect(await shelf.save(report, to: url) == .busy)
        fake.release()
        #expect(await first == .saved(url))
        #expect(fake.written == [url])
    }

    /// The daemon's kind of thumbnail: a WebP that decodes.
    private let drawn = DemoChart.webp(bars: [3, 5, 4, 6], width: 120)

    @Test func aFailedThumbnailIsTriedAgainWhenTheWindowOpensAgain() async {
        let shelf = fake.shelf()
        let image = entry("plot.png", version: "v-img", mime: "image/png")
        shelf.wantThumbnail(image)
        await shelf.settled()
        #expect(shelf.thumbnailStore.versions.isEmpty)
        shelf.wantThumbnail(image)
        await shelf.settled()
        #expect(fake.reads.count == 1)
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(drawn)
        shelf.open()
        shelf.wantThumbnail(image)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        #expect(shelf.thumbnailStore.contains("v-img"))
    }

    @Test func thumbnailsOnlyForImagesOnlyWebPAndOnce() async {
        let log = ThumbnailDecodeLog()
        let shelf = fake.shelf(thumbnails: ShelfThumbnails(decoder: log.decoder))
        let image = entry("plot.png", version: "v-img", mime: "image/png")
        let other = entry("plot2.png", version: "v-img2", mime: "image/png")
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(drawn)
        fake.files[.thumb(version: "v-img2", width: 120)] = .bytes(Data([0x89, 0x50, 0x4E, 0x47]))
        shelf.wantThumbnail(entry("notes.md", version: "v-md"))
        shelf.wantThumbnail(image)
        shelf.wantThumbnail(other)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        shelf.wantThumbnail(image)
        shelf.wantThumbnail(other)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        #expect(fake.reads == [.thumb(version: "v-img", width: 120), .thumb(version: "v-img2", width: 120)])
        #expect(shelf.thumbnailStore.versions == ["v-img"])
        #expect(log.inputs == [drawn], "only the checked WebP reached the decoder, once")
    }

    @Test func bytesThatDontDecodeAreNotReadAgainUntilTheWindowOpensAgain() async {
        let log = ThumbnailDecodeLog()
        let shelf = fake.shelf(thumbnails: ShelfThumbnails(decoder: log.decoder))
        let image = entry("plot.png", version: "v-img", mime: "image/png")
        // WebP by its first bytes, so the phone's check lets it by; not a picture.
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(webp)
        shelf.wantThumbnail(image)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        #expect(shelf.thumbnailStore.versions.isEmpty && shelf.thumbnailStore.totalCost == 0)
        shelf.wantThumbnail(image)
        await shelf.settled()
        #expect(fake.reads.count == 1 && log.count == 1, "not fetched again in a loop")
        // The window closes and opens again: tried again.
        shelf.close()
        shelf.open()
        shelf.wantThumbnail(image)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        #expect(fake.reads.count == 2 && log.count == 2)
    }

    @Test func aThumbnailIsNotReadAgainWhileItsBytesAreBeingDecoded() async {
        let gate = ThumbnailDecodeGate()
        let shelf = fake.shelf(thumbnails: ShelfThumbnails(decoder: gate.decoder))
        let image = entry("plot.png", version: "v-img", mime: "image/png")
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(drawn)
        shelf.wantThumbnail(image)
        await shelf.settled()
        #expect(shelf.thumbnailStore.knows("v-img") && !shelf.thumbnailStore.contains("v-img"), "read, decode held")
        shelf.wantThumbnail(image)
        await shelf.settled()
        #expect(fake.reads.count == 1)
        gate.open()
        await shelf.thumbnailStore.settled()
        #expect(shelf.thumbnailStore.contains("v-img"))
    }

    @Test func closingTheWindowLetsTheDecodedThumbnailsGoAndOpeningReadsThemAgain() async {
        let shelf = fake.shelf()
        let image = entry("plot.png", version: "v-img", mime: "image/png")
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(drawn)
        shelf.open()
        shelf.wantThumbnail(image)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        #expect(shelf.thumbnailStore.contains("v-img") && shelf.thumbnailStore.totalCost > 0)
        shelf.close()
        #expect(shelf.thumbnailStore.versions.isEmpty && shelf.thumbnailStore.totalCost == 0)
        // Open again: the row asks again, and the picture is read and decoded again.
        shelf.open()
        shelf.wantThumbnail(image)
        await shelf.settled()
        await shelf.thumbnailStore.settled()
        #expect(fake.reads.count == 2 && shelf.thumbnailStore.contains("v-img"))
    }

    @Test func aDecodeStillRunningWhenTheWindowClosesKeepsNothing() async {
        let gate = ThumbnailDecodeGate()
        let shelf = fake.shelf(thumbnails: ShelfThumbnails(decoder: gate.decoder))
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(drawn)
        shelf.wantThumbnail(entry("plot.png", version: "v-img", mime: "image/png"))
        await shelf.settled()
        shelf.close()
        gate.open()
        await shelf.thumbnailStore.settled()
        #expect(shelf.thumbnailStore.versions.isEmpty && shelf.thumbnailStore.totalCost == 0)
    }

    @Test func unrelatedShelfUpdatesDecodeNothingAndTouchNoThumbnail() async {
        let log = ThumbnailDecodeLog()
        let store = ShelfThumbnails(decoder: log.decoder)
        fake.recent = [made(1), made(2)]
        let image = entry("plot.png", version: "v-img", mime: "image/png")
        fake.lists[madeUpID(1)] = .list([image, entry("report.md", version: "v-md")])
        fake.lists[madeUpID(2)] = .list([entry("notes.md", version: "v-notes"), entry("counts.csv", version: "v-csv")])
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(drawn)
        for version in ["v-md", "v-notes", "v-csv"] { fake.files[.download(version: version)] = .bytes(Data(version.utf8)) }
        let shelf = fake.shelf(thumbnails: store)
        shelf.open()
        await shelf.settled()
        shelf.wantThumbnail(image)
        await shelf.settled()
        await store.settled()
        let picture = store.image(for: "v-img")
        #expect(picture != nil && log.count == 1)

        // What the rows watch: the store's own changes, and the shelf's.
        let storeChanges = ChangeCount(store.objectWillChange)
        let shelfChanges = ChangeCount(shelf.objectWillChange)
        // Save All's progress on the other session, line by line.
        fake.hold = true
        shelf.saveAll(madeUpID(2), into: URL(fileURLWithPath: "/made-up/Out", isDirectory: true))
        await until { fake.inFlight == 2 }
        #expect(shelf.batches[madeUpID(2)] == .saving(done: 0, total: 2))
        fake.release()
        for _ in 0..<10 { await Task.yield() }
        fake.hold = false
        fake.release()
        await shelf.settled()
        // Another session's list arrives, the list is taken again, and the row asks again.
        shelf.load(madeUpID(2))
        await shelf.settled()
        shelf.open(refresh: true)
        await shelf.settled()
        shelf.wantThumbnail(image)
        shelf.wantThumbnail(image)
        await shelf.settled()
        await store.settled()

        #expect(shelfChanges.count > 0, "the shelf did publish")
        #expect(storeChanges.count == 0, "no thumbnail view is told anything")
        #expect(log.count == 1, "nothing was decoded again")
        #expect(fake.reads.filter { $0 == .thumb(version: "v-img", width: 120) }.count == 1, "nor read again")
        #expect(store.image(for: "v-img") === picture, "the very same picture")
    }

    // MARK: Saving

    @Test func saveWritesTheFileWhereChosenAndOnlyThen() async {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        let bytes = Data("# Made-up report".utf8)
        fake.files[.download(version: "v-md")] = .bytes(bytes)
        let url = URL(fileURLWithPath: "/made-up/Downloads/report.md")
        #expect(fake.written.isEmpty)
        #expect(await shelf.save(report, to: url) == .saved(url))
        #expect(fake.written == [url] && fake.writtenBytes == [bytes])
        #expect(shelf.saved["v-md"] == url)
        #expect(fake.savedNotices == [url])
        #expect(await shelf.savedCopy("v-md") == url, "the writer put it on the fake disk")
        // Moved or deleted since: forgotten, and said so.
        fake.existing.remove(url.path)
        #expect(await shelf.savedCopy("v-md") == nil)
        #expect(shelf.saved["v-md"] == nil)
        #expect(shelf.fileProblems["v-md"] == "The saved copy was moved or deleted.")
    }

    @Test func saveKeepsToTheCapsAndSaysWhatWentWrong() async {
        let shelf = fake.shelf()
        let url = URL(fileURLWithPath: "/made-up/Downloads/x")
        // Too big by its listing: not read at all.
        let listedBig = entry("big.pdf", version: "v-big", size: ArtifactReaderScript.Cap.download + 1)
        #expect(await shelf.save(listedBig, to: url) == .tooBig)
        #expect(fake.reads.isEmpty)
        #expect(shelf.fileProblems["v-big"] == "Over 8 MB: open the session to download it there.")
        // Too big by its bytes, whatever the listing said.
        fake.files[.download(version: "v-liar")] = .bytes(Data(count: ArtifactReaderScript.Cap.download + 1))
        #expect(await shelf.save(entry("small.bin", version: "v-liar"), to: url) == .tooBig)
        fake.files[.download(version: "v-gone")] = .missing
        #expect(await shelf.save(entry("gone.md", version: "v-gone"), to: url) == .failed(.missing))
        fake.files[.download(version: "v-ok")] = .bytes(Data("ok".utf8))
        fake.writeFails = true
        guard case .writeFailed = await shelf.save(entry("ok.md", version: "v-ok"), to: url) else {
            Issue.record("a failed write wasn't reported")
            return
        }
        #expect(fake.written.isEmpty)
        #expect(shelf.saved.isEmpty)
        #expect(fake.savedNotices.isEmpty)
    }

    @Test func browsingNeverWritesToTheDisk() async {
        fake.recent = (1...3).map { made($0) }
        fake.lists[madeUpID(1)] = .list([entry("report.md", version: "v-md"), entry("plot.png", version: "v-img", mime: "image/png")])
        fake.files[.thumb(version: "v-img", width: 120)] = .bytes(webp)
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        for file in results(shelf, 1)?.entries ?? [] { shelf.wantThumbnail(file) }
        shelf.showOlder()
        await shelf.settled()
        #expect(fake.written.isEmpty)
        #expect(fake.savedNotices.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fake.temporaryFolder.path), "browsing makes no temporary copy")
    }
}

// MARK: Which rows are open

struct ShelfDisclosureTests {
    /// Opened to load: it stays open when its results arrive (it used to snap shut).
    @Test func aSessionOpenedToLoadStaysOpenWhenItsResultsArrive() {
        var rows = ShelfDisclosure()
        #expect(!rows.isOpen("s", hasResults: false, searching: false))
        rows.set("s", open: true)
        #expect(rows.isOpen("s", hasResults: false, searching: false))
        #expect(rows.isOpen("s", hasResults: true, searching: false))
    }

    @Test func readWithResultsIsOpenUntilClosedByHand() {
        var rows = ShelfDisclosure()
        #expect(rows.isOpen("s", hasResults: true, searching: false))
        rows.set("s", open: false)
        #expect(!rows.isOpen("s", hasResults: true, searching: false))
        // A search opens everything it matches, whatever was closed.
        #expect(rows.isOpen("s", hasResults: true, searching: true))
        rows.set("s", open: true)
        #expect(rows.isOpen("s", hasResults: true, searching: false))
    }
}

// MARK: Quick Look and drag: temporary copies

private let tooBigPreview = "Too big to preview here (over 8 MB). Save it instead, or open it in Capsid."

extension ResultsShelfTests {
    @Test func previewMakesOneTemporaryCopyAndReusesIt() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        let bytes = Data("# Made-up report".utf8)
        fake.files[.download(version: "v-md")] = .bytes(bytes)
        let url = try #require(await shelf.prepareQuickLook(report))
        #expect(try Data(contentsOf: url) == bytes)
        // <temporary folder>/Capsid Quick Look/<UUID>/<version id>/<name>
        let version = url.deletingLastPathComponent()
        let run = version.deletingLastPathComponent()
        #expect(url.lastPathComponent == "report.md" && version.lastPathComponent == "v-md")
        #expect(UUID(uuidString: run.lastPathComponent) != nil)
        #expect(run.deletingLastPathComponent().path == fake.temporaryFolder.path)
        #expect(permissions(url) == 0o600)
        #expect([version, run, fake.temporaryFolder].map(permissions) == [0o700, 0o700, 0o700])
        #expect(fake.reads == [.download(version: "v-md")])
        #expect(shelf.cachedCopy("v-md") == url)
        // Going back to the file doesn't download it again.
        #expect(await shelf.prepareQuickLook(report) == url)
        #expect(fake.reads.count == 1)
        #expect(shelf.preparing.isEmpty)
        #expect(fake.written.isEmpty && shelf.saved.isEmpty, "a temporary copy is not a save")
        #expect(fake.savedNotices.isEmpty)
    }

    @Test func twoFilesOfOneNameKeepTheirOwnCopies() async throws {
        let shelf = fake.shelf()
        fake.files[.download(version: "v-1")] = .bytes(Data("first".utf8))
        fake.files[.download(version: "v-2")] = .bytes(Data("second".utf8))
        let first = try #require(await shelf.prepareQuickLook(entry("figure.png", version: "v-1")))
        let second = try #require(await shelf.prepareQuickLook(entry("figure.png", version: "v-2")))
        #expect(first != second)
        #expect(first.lastPathComponent == "figure.png" && second.lastPathComponent == "figure.png")
        #expect(try Data(contentsOf: first) == Data("first".utf8) && Data(contentsOf: second) == Data("second".utf8))
    }

    @Test func aFileWithAnAwkwardNameGetsASafeOne() async throws {
        let shelf = fake.shelf()
        fake.files[.download(version: "v-odd")] = .bytes(Data("x".utf8))
        let url = try #require(await shelf.prepareQuickLook(entry(".hidden:name.csv", version: "v-odd")))
        #expect(url.lastPathComponent == "hidden_name.csv")
        #expect(url.path.hasPrefix(fake.temporaryFolder.path + "/"))
    }

    @Test func previewOverTheCapDownloadsNothingAndSaysSo() async {
        let shelf = fake.shelf()
        // Over by its listing: not read at all, and no folder is made.
        #expect(await shelf.prepareQuickLook(entry("big.pdf", version: "v-big", size: cap + 1)) == nil)
        #expect(fake.reads.isEmpty)
        #expect(shelf.fileProblems["v-big"] == tooBigPreview)
        #expect(!FileManager.default.fileExists(atPath: fake.temporaryFolder.path))
        // Over by its bytes, whatever the listing said.
        fake.files[.download(version: "v-liar")] = .bytes(Data(count: cap + 1))
        #expect(await shelf.prepareQuickLook(entry("small.bin", version: "v-liar")) == nil)
        #expect(shelf.fileProblems["v-liar"] == tooBigPreview)
        // Or the reader says so.
        fake.files[.download(version: "v-reader")] = .tooBig
        #expect(await shelf.prepareQuickLook(entry("x.bin", version: "v-reader")) == nil)
        #expect(shelf.fileProblems["v-reader"] == tooBigPreview)
        #expect(shelf.cachedCopy("v-liar") == nil && shelf.preparing.isEmpty)
        #expect(files(under: fake.temporaryFolder).isEmpty)
    }

    @Test func aPreviewThatFailsSaysWhyOnTheRow() async {
        let shelf = fake.shelf()
        for (version, outcome, failure) in [("v-a", ArtifactReadOutcome.missing, ShelfFailure.missing),
                                            ("v-b", .lost, .signedOut), ("v-c", .unreadable, .unreadable)] {
            fake.files[.download(version: version)] = outcome
            #expect(await shelf.prepareQuickLook(entry("x.md", version: version)) == nil)
            #expect(shelf.fileProblems[version] == failure.sentence)
        }
        // A read that never answers.
        fake.hold = true
        fake.expireAtOnce = true
        #expect(await shelf.prepareQuickLook(entry("slow.md", version: "v-slow")) == nil)
        #expect(shelf.fileProblems["v-slow"] == ShelfFailure.timedOut.sentence)
        fake.release()
        // The page isn't up.
        fake.ready = false
        let readsBefore = fake.reads.count
        #expect(await shelf.prepareQuickLook(entry("y.md", version: "v-y")) == nil)
        #expect(shelf.fileProblems["v-y"] == ShelfFailure.notReady.sentence)
        #expect(fake.reads.count == readsBefore)
        #expect(shelf.preparing.isEmpty)
        // A press that works clears the line.
        fake.ready = true
        fake.hold = false
        fake.expireAtOnce = false
        fake.files[.download(version: "v-a")] = .bytes(Data("ok".utf8))
        #expect(await shelf.prepareQuickLook(entry("x.md", version: "v-a")) != nil)
        #expect(shelf.fileProblems["v-a"] == nil)
    }

    @Test func aSecondPressWhileItLoadsDoesNothing() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        fake.hold = true
        let first = Task { await shelf.prepareQuickLook(report) }
        for _ in 0..<5 { await Task.yield() }
        #expect(shelf.preparing == ["v-md"], "the row shows a spinner")
        #expect(await shelf.prepareQuickLook(report) == nil)
        #expect(fake.reads.count == 1)
        #expect(shelf.fileProblems["v-md"] == nil)
        fake.hold = false
        fake.release()
        #expect(await first.value != nil)
        #expect(shelf.preparing.isEmpty)
        #expect(fake.reads.count == 1)
    }

    @Test func closingDeletesTheCopiesAndALaterPreviewFetchesAgain() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        let first = try #require(await shelf.prepareQuickLook(report))
        let firstRun = first.deletingLastPathComponent().deletingLastPathComponent()
        shelf.close()
        #expect(shelf.cachedCopy("v-md") == nil)
        // Deleted off the main actor.
        await shelf.settled()
        #expect(!FileManager.default.fileExists(atPath: firstRun.path))
        #expect(shelf.cachedCopy("v-md") == nil)
        let second = try #require(await shelf.prepareQuickLook(report))
        #expect(fake.downloads == ["v-md", "v-md"])
        #expect(second.deletingLastPathComponent().deletingLastPathComponent() != firstRun, "a new run, a new folder")
        shelf.close()
        await shelf.settled()
        #expect(files(under: fake.temporaryFolder).isEmpty)
    }

    @Test func closingWhileACopyLoadsWritesNothing() async {
        let shelf = fake.shelf()
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        fake.hold = true
        let first = Task { await shelf.prepareQuickLook(entry("report.md", version: "v-md")) }
        for _ in 0..<5 { await Task.yield() }
        shelf.close()
        #expect(shelf.preparing.isEmpty)
        fake.hold = false
        fake.release()
        #expect(await first.value == nil)
        #expect(files(under: fake.temporaryFolder).isEmpty)
        #expect(shelf.fileProblems["v-md"] == nil)
    }

    @Test func browsingStartsEmptyAndLaunchCleanupTakesTheWholeFolder() async throws {
        let shelf = fake.shelf()
        fake.files[.download(version: "v-1")] = .bytes(Data("x".utf8))
        _ = await shelf.prepareQuickLook(entry("a.md", version: "v-1"))
        // A run that never closed leaves its folder behind; launch deletes all of them.
        let stray = fake.temporaryFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stray.appending(path: "old.md"))
        #expect(files(under: fake.temporaryFolder).count == 2)
        ShelfTemporaryCopies.removeAll(base: fake.temporaryFolder)
        #expect(!FileManager.default.fileExists(atPath: fake.temporaryFolder.path))
        #expect(ShelfTemporaryCopies.defaultBase.lastPathComponent == "Capsid Quick Look")
        #expect(ShelfTemporaryCopies.defaultBase.deletingLastPathComponent().path
                == FileManager.default.temporaryDirectory.path.trimmingSuffix("/"))
    }

    // MARK: Drag

    @Test func aDragFetchesNothingUntilItIsDropped() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        let bytes = Data("# Made-up".utf8)
        fake.files[.download(version: "v-md")] = .bytes(bytes)
        // The drag begins: nothing is read, nothing written.
        let provider = ShelfDrag.provider(for: report, shelf: shelf)
        #expect(provider.registeredTypeIdentifiers == [ShelfDrag.contentType(forName: "report.md").identifier])
        #expect(fake.reads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fake.temporaryFolder.path))
        // The drop: the receiver asks for the file, and gets the copy's bytes under the real name.
        let received: (name: String, data: Data?) = await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: provider.registeredTypeIdentifiers[0]) { url, _ in
                continuation.resume(returning: (url?.lastPathComponent ?? "", url.flatMap { try? Data(contentsOf: $0) }))
            }
        }
        #expect(received.name == "report.md" && received.data == bytes)
        #expect(fake.downloads == ["v-md"])
    }

    @Test func aDropReturnsTheCopyAndSharesItWithPreview() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        let bytes = Data("# Made-up".utf8)
        fake.files[.download(version: "v-md")] = .bytes(bytes)
        #expect(shelf.canDrag(report))
        let previewed = try #require(await shelf.prepareQuickLook(report))
        let dropped = try #require(await shelf.exportForDrag(report))
        #expect(dropped == previewed)
        #expect(try Data(contentsOf: dropped) == bytes)
        #expect(fake.downloads == ["v-md"], "one download for both")
        // And the other way round.
        fake.files[.download(version: "v-csv")] = .bytes(Data("a,b\n".utf8))
        let table = entry("counts.csv", version: "v-csv")
        let first = try #require(await shelf.exportForDrag(table))
        #expect(await shelf.prepareQuickLook(table) == first)
        #expect(fake.downloads == ["v-md", "v-csv"])
    }

    @Test func twoDropsAtOnceFetchTheFileOnce() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        fake.hold = true
        let first = Task { await shelf.exportForDrag(report) }
        let second = Task { await shelf.exportForDrag(report) }
        for _ in 0..<5 { await Task.yield() }
        fake.hold = false
        fake.release()
        let urls = await [first.value, second.value]
        #expect(urls[0] != nil && urls[0] == urls[1])
        #expect(fake.downloads == ["v-md"])
    }

    @Test func aDragOfAFileOverTheCapProvidesNothingAndSaysWhy() async {
        let shelf = fake.shelf()
        let big = entry("big.pdf", version: "v-big", size: cap + 1)
        let provider = ShelfDrag.provider(for: big, shelf: shelf)
        #expect(provider.registeredTypeIdentifiers.isEmpty)
        #expect(shelf.fileProblems["v-big"] == "Too big to drag out (over 8 MB). Save it instead, or open it in Capsid.")
        #expect(!shelf.canDrag(big))
        #expect(await shelf.exportForDrag(big) == nil)
        // Over by its bytes: the drop gets nothing.
        fake.files[.download(version: "v-liar")] = .bytes(Data(count: cap + 1))
        #expect(await shelf.exportForDrag(entry("small.bin", version: "v-liar")) == nil)
        #expect(shelf.fileProblems["v-liar"] == "Too big to drag out (over 8 MB). Save it instead, or open it in Capsid.")
        #expect(fake.downloads == ["v-liar"])
        #expect(files(under: fake.temporaryFolder).isEmpty)
    }

    @Test func aDropThatFailsSaysWhyOnTheRow() async {
        let shelf = fake.shelf()
        fake.files[.download(version: "v-gone")] = .missing
        #expect(await shelf.exportForDrag(entry("gone.md", version: "v-gone")) == nil)
        #expect(shelf.fileProblems["v-gone"] == ShelfFailure.missing.sentence)
        fake.ready = false
        #expect(!shelf.canDrag(entry("x.md", version: "v-x")))
        #expect(shelf.fileProblems["v-x"] == ShelfFailure.notReady.sentence)
    }

    @Test func aDragTakesItsContentTypeFromTheExtension() {
        #expect(ShelfDrag.contentType(forName: "paper.pdf") == .pdf)
        #expect(ShelfDrag.contentType(forName: "plot.PNG") == .png)
        #expect(ShelfDrag.contentType(forName: "README") == .data)
        #expect(ShelfDrag.contentType(forName: "trailing.") == .data)
        #expect(ShelfDrag.contentType(forName: "reads.fasta").conforms(to: .data))
    }

    // MARK: The panel's files

    @Test func theQuickLookPanelListsTheShownFilesThatCanBePreviewed() {
        let shown = [entry("a.md", version: "v-a"), entry("huge.pdf", version: "v-huge", size: cap + 1),
                     entry("b.png", version: "v-b"), entry("c.csv", version: "v-c")]
        #expect(ResultsQuickLook.panelFiles(shown[2], among: shown).map(\.version) == ["v-a", "v-b", "v-c"])
        // The file asked for is always there, and a list without it gets it.
        #expect(ResultsQuickLook.panelFiles(shown[0], among: []).map(\.version) == ["v-a"])
    }

    @Test func aPanelItemHasNoURLUntilItsCopyIsThereAndTheRealNameAsItsTitle() async throws {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        let item = ShelfQuickLookItem(entry: report) { [shelf] in shelf.cachedCopy("v-md") }
        #expect(item.previewItemURL == nil, "Quick Look shows its loading view")
        #expect(item.previewItemTitle == "report.md")
        let url = try #require(await shelf.prepareQuickLook(report))
        #expect(item.previewItemURL == url)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}

// MARK: Copy

private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@MainActor
struct ShelfCopyTests {
    private let fake = FakeShelf()

    @Test func whatGoesOnThePasteboardDependsOnTheKindAndTheBytes() {
        #expect(ShelfCopy.content(kind: .image, data: png) == .image(png))
        for kind in [ArtifactKind.markdown, .text, .table] {
            #expect(ShelfCopy.content(kind: kind, data: Data("# Made-up, é".utf8)) == .text("# Made-up, é"))
        }
        #expect(ShelfCopy.content(kind: .text, data: Data("\u{FEFF}a,b".utf8)) == .text("a,b"), "a byte-order mark isn't copied")
        #expect(ShelfCopy.content(kind: .text, data: Data()) == .text(""))
        #expect(ShelfCopy.content(kind: .table, data: Data([0x61, 0xFF, 0xFE, 0x62])) == .notText, "not valid UTF-8")
        let pdf = Data("%PDF-1.7 made-up".utf8)
        #expect(ShelfCopy.content(kind: .pdf, data: pdf) == .pdf(pdf))
        for kind in [ArtifactKind.svg, .html, .notebook, .other] {
            #expect(ShelfCopy.content(kind: kind, data: Data("x".utf8)) == .notOffered)
            #expect(!ShelfCopy.isOffered(kind))
        }
        for kind in [ArtifactKind.image, .markdown, .text, .table, .pdf] { #expect(ShelfCopy.isOffered(kind)) }
        #expect(ShelfCopy.content(kind: .other, data: Data()).problem?.contains("Drag it out or save it") == true)
        #expect(ShelfCopyContent.notText.problem == "Couldn't copy this as text, because it isn't valid UTF-8. Save it instead.")
        #expect(ShelfCopyContent.text("x").problem == nil)
    }

    @Test func everyKindTheShelfClassifiesIsDecidedExactlyOnce() {
        // Copy follows the kinds the existing classification gives, not a list of its own.
        #expect(ArtifactKind.classify(name: "a.png", mime: nil) == .image)
        #expect(ArtifactKind.classify(name: "a.jpeg", mime: nil) == .image)
        #expect(ArtifactKind.classify(name: "a.tsv", mime: nil) == .table)
        #expect(ArtifactKind.allCases.filter(ShelfCopy.isOffered).count == 5)
    }

    @Test func copyPutsTheFullFileOnThePasteboardAndNothingOnTheDisk() async {
        let shelf = fake.shelf()
        fake.files[.download(version: "v-md")] = .bytes(Data("# Made-up".utf8))
        fake.files[.download(version: "v-img")] = .bytes(png)
        fake.files[.download(version: "v-pdf")] = .bytes(Data("%PDF-1.7".utf8))
        #expect(await shelf.copy(entry("notes.md", version: "v-md")))
        #expect(await shelf.copy(entry("plot.png", version: "v-img", mime: "image/png")))
        #expect(await shelf.copy(entry("paper.pdf", version: "v-pdf")))
        #expect(fake.copied == [.text("# Made-up"), .image(png), .pdf(Data("%PDF-1.7".utf8))])
        // The whole file through the download path, never the thumbnail or the 256 KB text read.
        #expect(fake.reads == [.download(version: "v-md"), .download(version: "v-img"), .download(version: "v-pdf")])
        #expect(fake.written.isEmpty && !FileManager.default.fileExists(atPath: fake.temporaryFolder.path))
        #expect(shelf.preparing.isEmpty && shelf.fileProblems.isEmpty)
    }

    @Test func copyKeepsToTheCapAndSaysWhatWentWrong() async {
        let shelf = fake.shelf()
        let tooBig = "Too big to copy here (over 8 MB). Save it instead, or open it in Capsid."
        #expect(await !shelf.copy(entry("big.md", version: "v-big", size: cap + 1)))
        #expect(shelf.fileProblems["v-big"] == tooBig)
        #expect(fake.reads.isEmpty)
        fake.files[.download(version: "v-liar")] = .bytes(Data(count: cap + 1))
        #expect(await !shelf.copy(entry("small.pdf", version: "v-liar")))
        #expect(shelf.fileProblems["v-liar"] == tooBig)
        fake.files[.download(version: "v-latin")] = .bytes(Data([0x63, 0xE9, 0x6C]))
        #expect(await !shelf.copy(entry("latin1.txt", version: "v-latin")))
        #expect(shelf.fileProblems["v-latin"] == ShelfCopyContent.notText.problem)
        #expect(await !shelf.copy(entry("plot.svg", version: "v-svg")))
        #expect(shelf.fileProblems["v-svg"] == ShelfCopyContent.notOffered.problem)
        fake.files[.download(version: "v-gone")] = .missing
        #expect(await !shelf.copy(entry("gone.md", version: "v-gone")))
        #expect(shelf.fileProblems["v-gone"] == ShelfFailure.missing.sentence)
        #expect(fake.downloads == ["v-liar", "v-latin", "v-gone"], "no read for an over-cap listing or an svg")
        fake.files[.download(version: "v-ok")] = .bytes(Data("ok".utf8))
        fake.pasteboardFails = true
        #expect(await !shelf.copy(entry("ok.md", version: "v-ok")))
        #expect(shelf.fileProblems["v-ok"] == "Couldn't copy this.")
        #expect(fake.copied.isEmpty)
        // A copy that works clears the line.
        fake.pasteboardFails = false
        #expect(await shelf.copy(entry("ok.md", version: "v-ok")))
        #expect(shelf.fileProblems["v-ok"] == nil && fake.copied == [.text("ok")])
    }

    @Test func copyUsesThePreviewsTemporaryCopyWhenThereIsOne() async {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("# Made-up".utf8))
        _ = await shelf.prepareQuickLook(report)
        #expect(await shelf.copy(report))
        #expect(fake.copied == [.text("# Made-up")])
        #expect(fake.downloads == ["v-md"], "one download for both")
    }

    @Test func aCopyShowsASpinnerAndOnePressAtATimeIsEnough() async {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        fake.hold = true
        let first = Task { await shelf.copy(report) }
        for _ in 0..<5 { await Task.yield() }
        #expect(shelf.preparing == ["v-md"])
        #expect(await !shelf.copy(report))
        fake.hold = false
        fake.release()
        #expect(await first.value)
        #expect(fake.copied == [.text("x")] && fake.downloads == ["v-md"] && shelf.preparing.isEmpty)
    }

    @Test func theThinPasteboardWriteFillsAPrivatePasteboard() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("capsid-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        #expect(ShelfPasteboard.write(.text("# Made-up"), to: board))
        #expect(board.string(forType: .string) == "# Made-up")
        let pdf = Data("%PDF-1.7 made-up".utf8)
        #expect(ShelfPasteboard.write(.pdf(pdf), to: board))
        #expect(board.data(forType: .pdf) == pdf)
        #expect(board.string(forType: .string) == nil, "the last copy replaces the one before")
        // An image that doesn't decode isn't put there.
        #expect(!ShelfPasteboard.write(.image(Data("not an image".utf8)), to: board))
        let picture = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(picture.tiffRepresentation)
        #expect(ShelfPasteboard.write(.image(tiff), to: board))
        #expect(board.canReadObject(forClasses: [NSImage.self], options: nil))
        #expect(!ShelfPasteboard.write(.notOffered, to: board) && !ShelfPasteboard.write(.notText, to: board))
    }
}

// MARK: Save All

private let out = URL(fileURLWithPath: "/made-up/Out", isDirectory: true)

@MainActor
struct ShelfSaveAllTests {
    private let fake = FakeShelf()

    /// A shelf whose one session (the first) is read and holds these files,
    /// each downloading its own name as bytes unless the test said otherwise.
    private func shelf(with files: [ArtifactEntry]) async -> ResultsShelf {
        fake.recent = [made(1)]
        fake.lists[madeUpID(1)] = .list(files)
        for file in files where fake.files[.download(version: file.version)] == nil {
            fake.files[.download(version: file.version)] = .bytes(Data(file.name.utf8))
        }
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        return shelf
    }

    private func summary(_ shelf: ResultsShelf) -> ShelfSaveAllSummary? {
        if case .finished(let summary)? = shelf.batches[madeUpID(1)] { summary } else { nil }
    }

    // MARK: Naming

    @Test func aNameAlreadyTakenGetsANumberBeforeItsExtension() {
        #expect(ShelfFileName.unique("report.md", taken: { _ in false }) == "report.md")
        #expect(ShelfFileName.unique("report.md", taken: { ["report.md"].contains($0) }) == "report 2.md")
        #expect(ShelfFileName.unique("report.md", taken: { ["report.md", "report 2.md"].contains($0) }) == "report 3.md")
        #expect(ShelfFileName.unique("notes", taken: { $0 == "notes" }) == "notes 2")
        #expect(ShelfFileName.unique("archive.tar.gz", taken: { $0 == "archive.tar.gz" }) == "archive.tar 2.gz")
    }

    @Test func saveAllNeverOverwritesAndNamesTheFilesInTheListsOrder() async {
        fake.existing = ["/made-up/Out/report.md"]
        let shelf = await shelf(with: [entry("report.md", version: "v-md"),
                                       entry("figure.png", version: "v-1", mime: "image/png"),
                                       entry("figure.png", version: "v-2", mime: "image/png"),
                                       entry("Figure.png", version: "v-3", mime: "image/png")])
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(shelf.saved["v-md"]?.lastPathComponent == "report 2.md", "the folder already had report.md")
        #expect(shelf.saved["v-1"]?.lastPathComponent == "figure.png")
        #expect(shelf.saved["v-2"]?.lastPathComponent == "figure 2.png", "earlier in the same batch")
        #expect(shelf.saved["v-3"]?.lastPathComponent == "Figure 3.png", "names differing by case collide on this Mac")
        #expect(Set(fake.written.map(\.path)).count == 4, "no two files went to one path")
        #expect(fake.written.allSatisfy { $0.deletingLastPathComponent().path == "/made-up/Out" })
    }

    @Test func saveAllAsksTheDiskForOneListingAndNothingOnTheMainThread() async {
        fake.existing = ["/made-up/Out/report.md", "/made-up/Out/other.txt"]
        let shelf = await shelf(with: [entry("report.md", version: "v-md"), entry("report.md", version: "v-2"),
                                       entry("figure.png", version: "v-1", mime: "image/png")])
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(fake.listCalls == ["/made-up/Out"], "one listing of the folder for the whole batch")
        // The only other look is each write's own, in its own call: no question per name.
        #expect(fake.existsCalls.count == 3 && Set(fake.existsCalls).count == 3)
        #expect(fake.existsCalls.allSatisfy { $0.hasPrefix("/made-up/Out/") })
        #expect(!fake.anyLookOnMain, "no look at the disk ran on the main thread")
        #expect(fake.disk.with { $0.onMain }.allSatisfy { !$0 })
        #expect(shelf.saved["v-md"]?.lastPathComponent == "report 2.md")
        #expect(shelf.saved["v-2"]?.lastPathComponent == "report 3.md")
        #expect(shelf.saved["v-1"]?.lastPathComponent == "figure.png")
    }

    @Test func aFolderThatCannotBeListedIsAskedAboutNameByNameWithTheSameNames() async {
        var plans: [[String]] = []
        for listing in [FakeDisk.Listing.names, .tooMany, .fails] {
            let fake = FakeShelf()
            fake.existing = ["/made-up/Out/report.md", "/made-up/Out/report 2.md"]
            fake.listing = listing
            fake.recent = [made(1)]
            let files = [entry("report.md", version: "v-1"), entry("report.md", version: "v-2"),
                         entry("Figure.png", version: "v-3"), entry("figure.png", version: "v-4")]
            fake.lists[madeUpID(1)] = .list(files)
            for file in files { fake.files[.download(version: file.version)] = .bytes(Data(file.name.utf8)) }
            let shelf = fake.shelf()
            shelf.open()
            await shelf.settled()
            shelf.saveAll(madeUpID(1), into: out)
            await shelf.settled()
            plans.append(files.map { shelf.saved[$0.version]?.lastPathComponent ?? "-" })
            #expect(fake.listCalls == ["/made-up/Out"], "the listing is tried once, whatever it says")
            #expect(!fake.anyLookOnMain)
            // Asked about by name only when it could not be listed.
            let byName = fake.existsCalls.filter { !$0.contains("Figure") && !$0.contains("figure") }.count
            #expect((byName > 3) == (listing != .names), "\(listing): \(fake.existsCalls)")
        }
        #expect(plans[0] == ["report 3.md", "report 4.md", "Figure.png", "figure 2.png"])
        #expect(plans[1] == plans[0] && plans[2] == plans[0])
    }

    @Test func aNameTakenAfterThePlanIsMadeIsNeverOverwrittenAndTheFileTakesTheNextFreeOne() async {
        let shelf = await shelf(with: [entry("report.md", version: "v-1"), entry("report.md", version: "v-2"),
                                       entry("figure.png", version: "v-3", mime: "image/png")])
        fake.hold = true
        shelf.saveAll(madeUpID(1), into: out)
        await until { fake.inFlight == 2 }
        #expect(fake.inFlight == 2, "the names are settled: the downloads are under way")
        // A program puts a file at the planned name since the plan was made.
        fake.existing.insert("/made-up/Out/report.md")
        fake.hold = false
        fake.release()
        await shelf.settled()
        #expect(!fake.written.map(\.path).contains("/made-up/Out/report.md"), "what was there is untouched")
        #expect(shelf.saved["v-2"]?.lastPathComponent == "report 2.md", "its planned name was free")
        #expect(shelf.saved["v-1"]?.lastPathComponent == "report 3.md", "numbered from report.md around what is taken")
        #expect(Set(fake.written.map(\.path)).count == 3 && fake.written.count == 3)
        #expect(summary(shelf) == ShelfSaveAllSummary(folder: out, saved: 3))
    }

    @Test func aPlannedNumberTakenAfterThePlanIsNumberedFromTheNameTheFileAskedFor() async {
        let shelf = await shelf(with: [entry("report.md", version: "v-1"), entry("report.md", version: "v-2")])
        fake.hold = true
        shelf.saveAll(madeUpID(1), into: out)
        await until { fake.inFlight == 2 }
        // Both planned names ("report.md" and "report 2.md") are taken since.
        fake.existing.formUnion(["/made-up/Out/report.md", "/made-up/Out/report 2.md"])
        fake.hold = false
        fake.release()
        await shelf.settled()
        #expect(Set(fake.written.map(\.lastPathComponent)) == ["report 3.md", "report 4.md"],
                "numbered from report.md, not from the number that was taken (never \"report 2 2.md\")")
        #expect(summary(shelf) == ShelfSaveAllSummary(folder: out, saved: 2))
    }

    @Test func aSaveAllOfFilesAllOverTheCapLooksAtNothingOnTheDisk() async {
        let shelf = await shelf(with: [entry("huge.csv", version: "v-1", size: cap + 1),
                                       entry("huger.csv", version: "v-2", size: cap + 1)])
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(summary(shelf) == ShelfSaveAllSummary(folder: out, tooBig: 2))
        #expect(fake.listCalls.isEmpty && fake.existsCalls.isEmpty, "no names to settle: a folder that doesn't answer costs nothing")
    }

    @Test func theRememberedFolderIsReadWithoutAskingTheDisk() {
        var asked: [String] = []
        let memory = ShelfFolderMemory(defaults: fake.defaults, exists: { url in
            asked.append(url.path)
            return true
        })
        #expect(memory.remembered(for: "proj_a") == nil)
        memory.remember(URL(fileURLWithPath: "/made-up/Remembered", isDirectory: true), for: "proj_a")
        #expect(memory.remembered(for: "proj_a")?.path == "/made-up/Remembered")
        #expect(asked.isEmpty, "knowing the path asks nothing of the disk")
    }

    @Test func saveAllKeepsFilesOutOfOtherFoldersAndAwkwardNamesSafe() async {
        let shelf = await shelf(with: [entry("../../etc/passwd", version: "v-1"), entry(".hidden.md", version: "v-2")])
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(fake.written.allSatisfy { $0.deletingLastPathComponent().path == "/made-up/Out" })
        #expect(shelf.saved["v-2"]?.lastPathComponent == "hidden.md")
    }

    // MARK: The batch

    @Test func saveAllSavesEveryFileAndRecordsEachLikeASingleSave() async {
        let files = [entry("report.md", version: "v-1"), entry("counts.csv", version: "v-2"),
                     entry("plot.png", version: "v-3", mime: "image/png")]
        let shelf = await shelf(with: files)
        #expect(!shelf.isSavingAll)
        shelf.saveAll(madeUpID(1), into: out)
        #expect(shelf.isSavingAll)
        #expect(shelf.batches[madeUpID(1)] == .saving(done: 0, total: 3))
        await shelf.settled()
        #expect(!shelf.isSavingAll)
        #expect(fake.written.map(\.lastPathComponent).sorted() == ["counts.csv", "plot.png", "report.md"])
        for file in files {
            #expect(shelf.saved[file.version]?.path == "/made-up/Out/\(file.name)", "Open and Reveal in Finder work for each")
            #expect(await shelf.savedCopy(file.version) != nil)
        }
        #expect(fake.writtenBytes.contains(Data("report.md".utf8)))
        #expect(summary(shelf) == ShelfSaveAllSummary(folder: out, saved: 3))
        #expect(summary(shelf)?.line == "Saved 3 files.")
        #expect(shelf.fileProblems.isEmpty)
        #expect(shelf.saving.isEmpty)
        #expect(fake.savedNotices.isEmpty, "one summary line, not a Saved card for every file")
    }

    @Test func saveAllRunsTwoDownloadsAtATime() async {
        let shelf = await shelf(with: (1...5).map { entry("f\($0).md", version: "v-\($0)") })
        fake.hold = true
        shelf.saveAll(madeUpID(1), into: out)
        // The names are settled off the main actor first, so the downloads start a little later.
        await until { fake.inFlight == 2 }
        #expect(fake.inFlight == 2)
        #expect(fake.downloads.count == 2)
        #expect(shelf.batches[madeUpID(1)] == .saving(done: 0, total: 5))
        #expect(shelf.batches[madeUpID(1)]?.line == "Saving 1 of 5…")
        #expect(shelf.saving.count == 2, "the rows show their spinners")
        // Two finish: two more start, and the line moves on.
        fake.release()
        await until { fake.downloads.count == 4 && fake.inFlight == 2 }
        #expect(fake.downloads.count == 4 && fake.inFlight == 2)
        #expect(shelf.batches[madeUpID(1)] == .saving(done: 2, total: 5))
        #expect(shelf.batches[madeUpID(1)]?.line == "Saving 3 of 5…")
        fake.hold = false
        fake.release()
        await shelf.settled()
        #expect(fake.mostAtOnce == 2)
        #expect(fake.downloads.count == 5)
        #expect(summary(shelf)?.saved == 5)
        #expect(shelf.saving.isEmpty)
    }

    @Test func aFileOverTheCapIsSkippedAndCounted() async {
        fake.files[.download(version: "v-liar")] = .bytes(Data(count: cap + 1))
        let shelf = await shelf(with: [entry("ok.md", version: "v-ok"), entry("huge.csv", version: "v-huge", size: cap + 1),
                                       entry("liar.txt", version: "v-liar")])
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(Set(fake.downloads) == ["v-ok", "v-liar"], "the one over the cap by its listing is never downloaded")
        #expect(fake.written.map(\.lastPathComponent) == ["ok.md"])
        #expect(summary(shelf)?.line == "Saved 1 file. 2 were too big to save here.")
        #expect(shelf.fileProblems["v-huge"] == "Over 8 MB: open the session to download it there.")
        #expect(shelf.fileProblems["v-liar"] == "Over 8 MB: open the session to download it there.")
        #expect(shelf.saved.keys.sorted() == ["v-ok"])
    }

    @Test func aSummaryCountsFailuresAndNeverNamesAFile() async {
        fake.files[.download(version: "v-gone")] = .missing
        fake.files[.download(version: "v-lost")] = .lost
        let shelf = await shelf(with: [entry("ok.md", version: "v-ok"), entry("secret-name.md", version: "v-gone"),
                                       entry("other-name.md", version: "v-lost")])
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(summary(shelf)?.line == "Saved 1 file. 2 couldn't be saved.")
        #expect(summary(shelf)?.line.contains("name") == false)
        #expect(shelf.fileProblems["v-gone"] == ShelfFailure.missing.sentence, "the row says why")
        #expect(shelf.fileProblems["v-lost"] == ShelfFailure.signedOut.sentence)
        // A write that fails counts the same way.
        fake.writeFails = true
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(summary(shelf)?.line == "Nothing was saved. 3 couldn't be saved.")
        #expect(shelf.saved["v-ok"] != nil, "the first batch's save is still recorded")
    }

    @Test func theSummaryLinesReadAsSentences() {
        let folder = out
        #expect(ShelfSaveAllSummary(folder: folder, saved: 6, tooBig: 1).line == "Saved 6 files. 1 was too big to save here.")
        #expect(ShelfSaveAllSummary(folder: folder, saved: 1).line == "Saved 1 file.")
        #expect(ShelfSaveAllSummary(folder: folder, saved: 2, tooBig: 3, failed: 1).line
                == "Saved 2 files. 3 were too big to save here. 1 couldn't be saved.")
        #expect(ShelfSaveAllSummary(folder: folder, tooBig: 2).line == "Nothing was saved. 2 were too big to save here.")
        #expect(ShelfSaveAllState.saving(done: 2, total: 7).line == "Saving 3 of 7…")
        #expect(ShelfSaveAllState.saving(done: 7, total: 7).line == "Saving 7 of 7…")
        #expect(ShelfSaveAllState.finished(ShelfSaveAllSummary(folder: folder, saved: 2)).line == "Saved 2 files.")
    }

    @Test func saveAllNeedsLoadedFilesAndRunsOneAtATime() async {
        fake.recent = [made(1), made(2)]
        fake.lists[madeUpID(1)] = .list([entry("a.md", version: "v-a")])
        fake.lists[madeUpID(2)] = .list([entry("b.md", version: "v-b")])
        fake.files[.download(version: "v-a")] = .bytes(Data("a".utf8))
        fake.files[.download(version: "v-b")] = .bytes(Data("b".utf8))
        let shelf = fake.shelf()
        // Not read yet: nothing to save.
        shelf.saveAll(madeUpID(1), into: out)
        #expect(!shelf.isSavingAll && shelf.batches.isEmpty)
        shelf.open()
        await shelf.settled()
        fake.hold = true
        shelf.saveAll(madeUpID(1), into: out)
        shelf.saveAll(madeUpID(2), into: out)
        #expect(shelf.batches.keys.sorted() == [madeUpID(1)], "a second Save All waits for the first")
        shelf.saveAll("no-such-session", into: out)
        fake.hold = false
        fake.release()
        await shelf.settled()
        #expect(fake.written.map(\.lastPathComponent) == ["a.md"])
        // An empty session has nothing to save.
        fake.lists[madeUpID(2)] = .list([])
        shelf.load(madeUpID(2))
        await shelf.settled()
        shelf.saveAll(madeUpID(2), into: out)
        #expect(shelf.batches[madeUpID(2)] == nil)
    }

    // MARK: Closing

    @Test func closingStopsWhatHasNotStartedAndLeavesNoHalfWrittenFile() async throws {
        let folder = fake.scratch.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fake.realWrites = true
        let shelf = await shelf(with: (1...4).map { entry("f\($0).md", version: "v-\($0)") })
        fake.hold = true
        shelf.saveAll(madeUpID(1), into: folder)
        await until { fake.inFlight == 2 }
        // The first two arrive and are saved; the next two start and are waiting.
        fake.release()
        await until { fake.downloads.count == 4 && fake.inFlight == 2 }
        #expect(fake.written.count == 2 && fake.downloads.count == 4)
        #expect(files(under: folder).count == 2)
        shelf.close()
        #expect(!shelf.isSavingAll)
        #expect(shelf.batches.isEmpty, "a batch cut short has no summary")
        fake.hold = false
        fake.release()
        await shelf.settled()
        for _ in 0..<10 { await Task.yield() }
        #expect(shelf.saving.isEmpty, "the spinners go once the stopped downloads unwind")
        #expect(fake.written.count == 2, "what was waiting never lands")
        #expect(fake.downloads.count == 4, "and nothing more was started")
        // Exactly the two finished files: nothing half-written, no temporary leftovers.
        #expect(files(under: folder) == ["f1.md", "f2.md"])
        #expect(shelf.saved.keys.sorted() == ["v-1", "v-2"])
    }

    @Test func closingBeforeAnyAnswerWritesNothing() async throws {
        let folder = fake.scratch.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fake.realWrites = true
        let shelf = await shelf(with: (1...3).map { entry("f\($0).md", version: "v-\($0)") })
        fake.hold = true
        shelf.saveAll(madeUpID(1), into: folder)
        await until { fake.inFlight == 2 }
        shelf.close()
        fake.hold = false
        fake.release()
        await shelf.settled()
        for _ in 0..<10 { await Task.yield() }
        #expect(fake.written.isEmpty && files(under: folder).isEmpty)
        #expect(shelf.saved.isEmpty && shelf.saving.isEmpty && !shelf.isSavingAll)
        // A finished summary survives the window closing; Save All can start again.
        fake.writeFails = false
        shelf.open()
        await shelf.settled()
        shelf.saveAll(madeUpID(1), into: folder)
        await shelf.settled()
        #expect(summary(shelf)?.saved == 3)
        shelf.close()
        #expect(summary(shelf)?.saved == 3)
    }

    // MARK: The folder remembered per project

    @Test func theFolderLastSavedToIsRememberedPerProjectByItsID() async {
        let shelf = fake.shelf()
        let report = entry("report.md", version: "v-md")
        fake.files[.download(version: "v-md")] = .bytes(Data("x".utf8))
        let documents = "/made-up/Documents/Data"
        #expect(await shelf.startingFolder(for: "proj_a") == nil)
        // Without a project nothing is remembered; a failed save remembers nothing.
        await shelf.save(report, to: URL(fileURLWithPath: documents + "/report.md"))
        fake.existing.insert(documents)
        #expect(await shelf.startingFolder(for: "proj_a") == nil)
        fake.writeFails = true
        await shelf.save(report, to: URL(fileURLWithPath: documents + "/report.md"), project: "proj_a")
        #expect(await shelf.startingFolder(for: "proj_a") == nil)
        fake.writeFails = false
        await shelf.save(report, to: URL(fileURLWithPath: documents + "/report.md"), project: "proj_a")
        #expect(await shelf.startingFolder(for: "proj_a")?.path == documents)
        #expect(await shelf.startingFolder(for: "proj_b") == nil)
        // Stored by the project's id, never its name, as a path.
        #expect(fake.defaults.dictionary(forKey: ShelfFolderMemory.key) as? [String: String] == ["proj_a": documents])
        // It comes back with the next shelf (the next launch).
        #expect(await fake.shelf().startingFolder(for: "proj_a")?.path == documents)
        // The folder is gone: the panel starts where it would.
        fake.existing.remove(documents)
        #expect(await shelf.startingFolder(for: "proj_a") == nil)
    }

    @Test func saveAllRemembersItsFolderToo() async {
        let shelf = await shelf(with: [entry("a.md", version: "v-a")])
        fake.existing.insert(out.path)
        #expect(await shelf.startingFolder(for: "proj_a") == nil)
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        #expect(await shelf.startingFolder(for: "proj_a")?.path == out.path)
        // A batch that saved nothing remembers nothing.
        let other = URL(fileURLWithPath: "/made-up/Elsewhere", isDirectory: true)
        fake.existing.insert(other.path)
        fake.files[.download(version: "v-a")] = .missing
        shelf.saveAll(madeUpID(1), into: other)
        await shelf.settled()
        #expect(await shelf.startingFolder(for: "proj_a")?.path == out.path)
    }

    @Test func aRememberedFolderThatIsGoneFallsBackOnTheRealDisk() async throws {
        let folder = fake.scratch.appending(path: "Remembered", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let memory = ShelfFolderMemory(defaults: fake.defaults, exists: { FileManager.default.fileExists(atPath: $0.path) })
        memory.remember(folder, for: "proj_a")
        #expect(await memory.folder(for: "proj_a")?.path == folder.path)
        try FileManager.default.removeItem(at: folder)
        #expect(await memory.folder(for: "proj_a") == nil)
        #expect(await memory.folder(for: "proj_never") == nil)
        #expect(memory.remembered(for: "proj_a")?.path == folder.path, "what is remembered is a path, whatever the disk says")
    }
}

// MARK: Showing one session

@MainActor
struct ShelfFocusTests {
    private let fake = FakeShelf()

    @Test func aSessionInTheListIsOpenedAndReadWithoutRetakingTheSnapshot() async {
        fake.recent = (1...10).map { made($0) }
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(results(shelf, 10) == .notLoaded, "past the first eight, not read until asked")
        let readsBefore = fake.listReads.count
        shelf.focus(made(10))
        await shelf.settled()
        #expect(results(shelf, 10) == .loaded([], at: start))
        #expect(fake.listReads == (1...8).map(madeUpID) + [madeUpID(10)], "only that session was read")
        #expect(fake.listReads.count == readsBefore + 1)
        #expect(shelf.disclosure.isOpen(madeUpID(10), hasResults: false, searching: false), "its row is open")
        #expect(shelf.focused == ShelfFocus(sessionID: madeUpID(10), token: 1))
        #expect(shelf.sessions.count == 10)
        // Asked again, it is seen again, and nothing is read twice.
        shelf.focus(made(10))
        await shelf.settled()
        #expect(shelf.focused == ShelfFocus(sessionID: madeUpID(10), token: 2))
        #expect(fake.listReads.count == readsBefore + 1)
    }

    @Test func aSessionThatFinishedAfterTheSnapshotIsFoundByTakingItAgain() async {
        fake.recent = [made(2), made(3)]
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        // The Lab knows session 1 now.
        fake.recent = [made(1), made(2), made(3)]
        fake.lists[madeUpID(1)] = .list([entry("report.md", version: "v-md")])
        shelf.focus(made(1))
        await shelf.settled()
        #expect(shelf.sessions.map(\.id) == [1, 2, 3].map(madeUpID))
        #expect(shelf.sessions.first?.coverage == .recent)
        #expect(results(shelf, 1)?.entries?.map(\.version) == ["v-md"])
        #expect(shelf.disclosure.isOpen(madeUpID(1), hasResults: true, searching: false))
        #expect(shelf.focused?.sessionID == madeUpID(1))
    }

    @Test func aSessionTheSnapshotNeverHasGoesAtTheTopOfTheRecentOnes() async {
        fake.recent = [made(1), made(2)]
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        let newest = made(7, project: "proj_b", minutesAgo: 0)
        fake.lists[madeUpID(7)] = .list([entry("fresh.md", version: "v-fresh")])
        shelf.focus(newest)
        await shelf.settled()
        #expect(shelf.sessions.map(\.id) == [7, 1, 2].map(madeUpID))
        #expect(shelf.sessions.first?.coverage == .recent)
        #expect(shelf.groups.first?.id == "recent-proj_b")
        #expect(results(shelf, 7)?.entries?.map(\.version) == ["v-fresh"])
        #expect(shelf.disclosure.isOpen(madeUpID(7), hasResults: true, searching: false))
        #expect(shelf.focused == ShelfFocus(sessionID: madeUpID(7), token: 1))
    }

    @Test func anOlderSessionIsOpenedWhereItIsAndNotListedTwice() async {
        fake.recent = [made(1)]
        fake.olderPages = [OlderPage(sessions: [made(20, project: "proj_b")], next: nil)]
        let shelf = fake.shelf()
        shelf.open()
        shelf.showOlder()
        await shelf.settled()
        shelf.focus(made(20, project: "proj_b"))
        await shelf.settled()
        #expect(shelf.sessions.filter { $0.id == madeUpID(20) }.count == 1)
        #expect(shelf.sessions.first { $0.id == madeUpID(20) }?.coverage == .older)
        #expect(results(shelf, 20) == .loaded([], at: start))
        #expect(shelf.disclosure.isOpen(madeUpID(20), hasResults: false, searching: false))
    }

    @Test func aListReadBeforeTheSessionLastWroteIsReadAgain() async {
        fake.recent = [made(1)]
        fake.lists[madeUpID(1)] = .list([entry("old.md", version: "v-old")])
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(results(shelf, 1)?.entries?.map(\.version) == ["v-old"])
        // The session wrote after that read, and made a file.
        fake.now = start.addingTimeInterval(120)
        fake.lists[madeUpID(1)] = .list([entry("old.md", version: "v-old"), entry("new.md", version: "v-new")])
        let later = SessionStatus(id: madeUpID(1), projectID: "proj_a", projectName: "Made-up A", title: "Renamed",
                                  state: .finished, updatedAt: start.addingTimeInterval(60))
        shelf.focus(later)
        await shelf.settled()
        #expect(Set(results(shelf, 1)?.entries?.map(\.version) ?? []) == ["v-old", "v-new"])
        #expect(shelf.sessions.first?.session.title == "Renamed", "the newer word on the session wins")
        #expect(fake.listReads == [madeUpID(1), madeUpID(1)])
    }

    @Test func aFailedReadIsTriedAgainAndAnUnreadyPageStillShowsTheSession() async {
        fake.recent = [made(1)]
        fake.ready = false
        let shelf = fake.shelf()
        shelf.open()
        await shelf.settled()
        #expect(results(shelf, 1) == .failed(.notReady))
        shelf.focus(made(1))
        await shelf.settled()
        #expect(results(shelf, 1) == .failed(.notReady), "said, not guessed at")
        #expect(shelf.disclosure.isOpen(madeUpID(1), hasResults: false, searching: false))
        #expect(shelf.focused?.sessionID == madeUpID(1))
        fake.ready = true
        shelf.focus(made(1))
        await shelf.settled()
        #expect(results(shelf, 1) == .loaded([], at: start))
    }

    @Test func closingTheWindowForgetsTheRequestAndRowsStayOpenOrShutByHand() async {
        fake.recent = [made(1)]
        let shelf = fake.shelf()
        shelf.open()
        shelf.focus(made(1))
        await shelf.settled()
        #expect(shelf.focused != nil)
        shelf.close()
        #expect(shelf.focused == nil, "a reopened window doesn't scroll to an old request")
        shelf.setExpanded(madeUpID(1), open: false)
        #expect(!shelf.disclosure.isOpen(madeUpID(1), hasResults: true, searching: false))
        shelf.setExpanded(madeUpID(1), open: true)
        #expect(shelf.disclosure.isOpen(madeUpID(1), hasResults: false, searching: false))
    }
}
