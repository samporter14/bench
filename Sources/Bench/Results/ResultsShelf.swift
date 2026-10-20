// ResultsShelf.swift — the results shelf (DESIGN.md, Results): the files sessions
// made, by project and session, to preview, save, and open the conversation they
// came from. It reads through the page's own artifact reader (Remote/ArtifactReader.swift)
// with the phone's own checks (`ArtifactGate`), and needs nothing of Capsid on
// your phone: no server, no paired device, no Settings → Phone switch.
//
// What it covers is said, never guessed at:
//   - Recent: the sessions the Lab already reads (the ~25 most recently active),
//     taken when the window opens and on Refresh, never followed live. The 8
//     newest are read then; the rest when opened.
//   - Older: read from the database a page at a time, and each session's results
//     only when asked for.
// Every read goes through one queue (ShelfTransfers): two at a time, whoever
// asked, each with a time limit, and stopped when the window closes, down to
// the page's fetch. What is listed lives in memory only; a file's contents
// reach the disk only through Save, Save All, and the temporary copies Quick
// Look and a drag need (ShelfTemporaryCopies: a private folder, deleted when
// the window closes). The disk is written and read off the main actor.
import Foundation

/// Which part of the shelf a session is in.
enum ShelfCoverage: String, Equatable, Sendable {
    /// One of the sessions the Lab reads anyway.
    case recent
    /// Read from the database because it was asked for.
    case older
}

/// Why something couldn't be read, in a sentence that says what to do.
enum ShelfFailure: Equatable, Sendable {
    case notReady, signedOut, missing, unreadable, timedOut

    var sentence: String {
        switch self {
        case .notReady: "Capsid isn't connected to Claude Science right now."
        case .signedOut: "Claude Science needs you to sign in again."
        case .missing: "This isn't in Claude Science any more."
        case .unreadable: "Couldn't read this."
        case .timedOut: "Claude Science took too long to answer."
        }
    }

    init(_ outcome: ArtifactReadOutcome) {
        switch outcome {
        case .lost: self = .signedOut
        case .missing: self = .missing
        default: self = .unreadable
        }
    }
}

/// What is known of a session's results.
enum ShelfResults: Equatable, Sendable {
    /// Not read: older sessions, and recent ones past the first few.
    case notLoaded
    /// Waiting its turn.
    case queued
    case loading
    case loaded([ArtifactEntry], at: Date)
    case failed(ShelfFailure)

    var entries: [ArtifactEntry]? {
        if case .loaded(let entries, _) = self { entries } else { nil }
    }
}

struct ShelfSession: Identifiable, Equatable, Sendable {
    let session: SessionStatus
    let coverage: ShelfCoverage
    var results: ShelfResults
    var id: String { session.id }
}

/// One project's sessions, in one part of the shelf.
struct ShelfGroup: Identifiable, Equatable, Sendable {
    let coverage: ShelfCoverage
    let projectID: String
    let projectName: String
    let sessions: [ShelfSession]
    var id: String { "\(coverage.rawValue)-\(projectID)" }
}

/// A page of older sessions from the database, and where the next starts.
struct OlderPage: Equatable, Sendable {
    let sessions: [SessionStatus]
    /// Nil when there are no more.
    let next: BrowseCursor?

    /// Up to a page of rows; the extra row `fetchRecentSessions` reads says
    /// there is another page.
    init(rows: [BrowseRow], port: Int?) {
        let shown = Array(rows.prefix(BrowseSQL.pageSize))
        sessions = shown.map { $0.status(port: port) }
        next = rows.count > BrowseSQL.pageSize ? shown.last.map { BrowseCursor(updatedMs: $0.updatedMs, id: $0.id) } : nil
    }

    init(sessions: [SessionStatus], next: BrowseCursor?) {
        self.sessions = sessions
        self.next = next
    }
}

/// The older sessions' part.
enum OlderState: Equatable, Sendable {
    /// Not asked for: "Show Older Sessions".
    case hidden
    case loading
    /// Shown; `next` when there are more ("Show More").
    case shown(next: BrowseCursor?)
    case failed
}

/// What making a temporary copy of a file (for Quick Look or a drag) came to.
enum ShelfTemporaryOutcome: Equatable, Sendable {
    case ready(URL)
    case tooBig
    case failed(ShelfFailure)
    case writeFailed(String)
    /// The window closed meanwhile: nothing was written.
    case cancelled
}

/// What a file is being fetched for: the sentences differ.
enum ShelfFileUse: Sendable {
    case preview, drag, copy

    /// An over-cap file, in a line that says what to do instead.
    var tooBig: String {
        switch self {
        case .preview: "Too big to preview here (over 8 MB). Save it instead, or open it in Capsid."
        case .drag: "Too big to drag out (over 8 MB). Save it instead, or open it in Capsid."
        case .copy: "Too big to copy here (over 8 MB). Save it instead, or open it in Capsid."
        }
    }
}

/// The session the window was asked to show (`ResultsShelf.focus`): the
/// view scrolls to it and selects it. A new request on the same session
/// bumps `token`, so it is seen again.
struct ShelfFocus: Equatable, Sendable {
    let sessionID: String
    let token: Int
}

/// How a Save went.
enum ShelfSaveOutcome: Equatable, Sendable {
    case saved(URL)
    /// This file is being saved already: nothing more is done.
    case busy
    case tooBig
    case failed(ShelfFailure)
    case writeFailed(String)
    /// The task asking was cancelled before the file arrived: nothing was written.
    case cancelled
}

/// Which sessions' rows are open. By default a session is open once read
/// with results; one opened or closed by hand stays so, including one opened
/// to load, which stays open when its results arrive.
struct ShelfDisclosure: Equatable, Sendable {
    private(set) var opened: Set<String> = []
    private(set) var closed: Set<String> = []

    func isOpen(_ id: String, hasResults: Bool, searching: Bool) -> Bool {
        searching || ((opened.contains(id) || hasResults) && !closed.contains(id))
    }

    mutating func set(_ id: String, open: Bool) {
        if open {
            opened.insert(id)
            closed.remove(id)
        } else {
            closed.insert(id)
            opened.remove(id)
        }
    }
}

@MainActor
final class ResultsShelf: ObservableObject {
    static let shared = ResultsShelf(dependencies: .live())

    struct Dependencies {
        /// The sessions the Lab read last (`LabModel.sessions`).
        var recent: @MainActor () -> [SessionStatus]
        /// A page of older root sessions from the database; nil when it can't be read.
        var older: @MainActor (BrowseCursor?) async -> OlderPage?
        /// The page's artifact reader, checked (`WebContainer.readArtifact`).
        /// Cancelling the task awaiting it aborts the page's fetch (`ArtifactReadAbort`).
        var read: @MainActor (ArtifactRead) async -> ArtifactReadOutcome
        /// The page is up, so it can read.
        var isReady: @MainActor () -> Bool
        /// Open a session's conversation in the main window.
        var open: @MainActor (SessionStatus) -> Void
        /// A file was saved: the panel's Saved card (`Router.downloadSaved`).
        var didSave: @MainActor (URL) -> Void = { _ in }
        /// Writes a saved file's bytes. Always run off the main actor, one at
        /// a time per destination, within a time limit (`ShelfSavedFiles`).
        var write: @Sendable (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }
        /// The writer that runs `write`; nil for a `ShelfSavedFiles` with the
        /// real limits. Tests hand in one with a clock and a queue they hold.
        var savedFiles: ShelfSavedFiles?
        var now: @MainActor () -> Date = { Date() }
        /// How long one read may take, from its start, before it counts as failed
        /// and its reader, if it hasn't returned, gives up its slot.
        var timeout: Duration = .seconds(30)
        /// Waits out the time limit; tests stand in for the clock.
        var wait: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        /// The folder the temporary copies go under ("Capsid Quick Look").
        var temporaryFolder: URL = ShelfTemporaryCopies.defaultBase
        /// The temporary copies' disk work; nil for `ShelfTemporaryCopies`
        /// under `temporaryFolder`. Tests hold it with a gate.
        var storage: (any ShelfCopyStorage)?
        /// Whether a file or folder is there: Save All never overwrites, and a
        /// remembered folder that is gone is forgotten.
        var exists: @MainActor (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        /// Where each project's last save folder is remembered.
        var defaults: UserDefaults = .standard
        /// Puts what Copy decided on the pasteboard; false when it couldn't.
        var pasteboard: @MainActor (ShelfCopyContent) -> Bool = { ShelfPasteboard.write($0) }

        static func live() -> Dependencies {
            Dependencies(
                recent: { LabModel.shared.sessions },
                older: { cursor in
                    guard Demo.mode == nil else { return nil }
                    let port = WebContainer.shared.port
                    let rows = await Task.detached(priority: .utility) { () -> [BrowseRow]? in
                        guard let db = resolveDatabase() else { return nil }
                        return (try? fetchRecentSessions(db: db, after: cursor)) ?? nil
                    }.value
                    return rows.map { OlderPage(rows: $0, port: port) }
                },
                read: { read in
                    guard Demo.mode == nil else { return .unreadable }
                    return await ArtifactReadAbort.abortable(read, perform: { read, nonce in
                        (try? await WebContainer.shared.readArtifact(read, nonce: nonce)) ?? .unreadable
                    }, abort: { nonce in
                        await WebContainer.shared.abortArtifactRead(nonce)
                    })
                },
                isReady: { Demo.mode == nil && WebContainer.shared.status == .ready },
                open: { LabModel.shared.open($0) },
                didSave: { Router.shared.downloadSaved($0) })
        }
    }

    /// How many of the recent sessions are read when the window opens.
    static let autoLoad = 8
    /// Reads at once, of every kind together (`ShelfTransfers`).
    static let concurrency = 2
    /// A list read this lately is kept when the window opens again.
    static let freshFor: TimeInterval = 300

    @Published private(set) var sessions: [ShelfSession] = []
    @Published private(set) var older: OlderState = .hidden
    /// When the recent sessions were taken.
    @Published private(set) var takenAt: Date?
    /// The thumbnails, decoded small and kept within a byte budget (ShelfThumbnails).
    let thumbnailStore: ShelfThumbnails
    /// Where each file was saved, by version: Open and Reveal in Finder.
    @Published private(set) var saved: [String: URL] = [:]
    /// Files being saved (Save, Save All), by version: a spinner on the row, and
    /// a second Save of the file does nothing. Each is held by what is saving it
    /// (`savingHolds`), so one that ends lets go of its own hold and no other.
    @Published private(set) var saving: Set<String> = []
    /// Files being fetched for Quick Look, a drag or Copy, by version: a spinner on the row.
    @Published private(set) var preparing: Set<String> = []
    /// Each session's Save All, by session id: its progress, then its summary.
    @Published private(set) var batches: [String: ShelfSaveAllState] = [:]
    /// Which sessions' rows are open (`ShelfDisclosure`).
    @Published private(set) var disclosure = ShelfDisclosure()
    /// The session the window was asked to show, until it closes.
    @Published private(set) var focused: ShelfFocus?
    /// What went wrong with a file's Save, Open or Reveal, by version.
    @Published private(set) var fileProblems: [String: String] = [:]

    private let dependencies: Dependencies
    /// Every read the shelf makes, two at a time.
    let transfers: ShelfTransfers

    private enum Job: Hashable {
        case list(String)
        case thumb(String)
    }

    /// The list and thumbnail reads asked for, each waiting in `transfers`.
    private var jobs: [Job: Task<Void, Never>] = [:]
    private var failedThumbnails: Set<String> = []
    /// Bumped when the window closes: a read started before lands nowhere.
    private var generation = 0
    private var olderTask: Task<Void, Never>?
    private let storage: any ShelfCopyStorage
    private let savedFiles: ShelfSavedFiles
    private let folders: ShelfFolderMemory
    /// This window's run of temporary copies; a new one each time it closes.
    private var runID = UUID()
    /// The copies known to be complete this run, by version: what Quick Look
    /// asks for on the main thread (`cachedCopy`). Set when a write lands.
    private var copies: [String: URL] = [:]
    /// Copies being written, by version: a second asker waits for the first.
    private var copyWrites: [String: Task<URL?, any Error>] = [:]
    /// How many askers are fetching each version for a temporary copy or Copy.
    private var preparers: [String: Int] = [:]
    /// How many are saving each version in `saving`: a Save, a Save All, and a
    /// Save All the window's closing left unwinding while the next one began.
    private var savingHolds: [String: Int] = [:]
    private var saveAllTasks: [String: Task<Void, Never>] = [:]
    /// What closing the window left to finish: stopped tasks unwinding and
    /// the old run's folder being deleted. Each close adds to the chain.
    private var unwinding: Task<Void, Never>?
    /// Launch's cleanup of earlier runs' copies: the first copy is written after it.
    private var launchCleanup: Task<Void, Never>?
    /// Where the next page of older sessions starts (nil: the first page).
    private var olderCursor: BrowseCursor?

    init(dependencies: Dependencies, thumbnails: ShelfThumbnails = ShelfThumbnails()) {
        self.dependencies = dependencies
        transfers = ShelfTransfers(limit: Self.concurrency, read: dependencies.read, isReady: dependencies.isReady,
                                   timeout: dependencies.timeout, wait: dependencies.wait)
        storage = dependencies.storage ?? ShelfTemporaryCopies(base: dependencies.temporaryFolder)
        savedFiles = dependencies.savedFiles ?? ShelfSavedFiles()
        thumbnailStore = thumbnails
        folders = ShelfFolderMemory(defaults: dependencies.defaults, exists: dependencies.exists)
    }

    var isReady: Bool { dependencies.isReady() }

    // MARK: What is shown

    /// Recent, then older; each by project, the most recently active first.
    var groups: [ShelfGroup] {
        [ShelfCoverage.recent, .older].flatMap { coverage in
            var order: [String] = []
            var byProject: [String: [ShelfSession]] = [:]
            for item in sessions where item.coverage == coverage {
                if byProject[item.session.projectID] == nil { order.append(item.session.projectID) }
                byProject[item.session.projectID, default: []].append(item)
            }
            return order.map { project in
                let members = byProject[project] ?? []
                return ShelfGroup(coverage: coverage, projectID: project,
                                  projectName: members.first?.session.projectName ?? project, sessions: members)
            }
        }
    }

    /// The coverage, in a sentence: how many recent sessions are listed and
    /// read, and that older ones load on request.
    var coverageLine: String {
        let recent = sessions.filter { $0.coverage == .recent }
        let read = recent.filter { $0.results.entries != nil }.count
        let older = sessions.filter { $0.coverage == .older }.count
        var line = "Your \(recent.count) most recent session\(recent.count == 1 ? "" : "s"), \(read) read."
        line += older > 0 ? " \(older) older session\(older == 1 ? "" : "s") listed; each is read when you open it."
                          : " Older sessions load only when you ask."
        return line
    }

    // MARK: Opening and closing

    /// The window opened, or Refresh: takes the recent sessions now, keeps
    /// results read lately, and reads the newest few that need it.
    func open(refresh: Bool = false) {
        let now = dependencies.now()
        let previous = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = dependencies.recent()
        let recentIDs = Set(recent.map(\.id))
        var next: [ShelfSession] = recent.map { session in
            var results = ShelfResults.notLoaded
            if !refresh, case .loaded(_, let at)? = previous[session.id]?.results,
               now.timeIntervalSince(at) < Self.freshFor {
                results = previous[session.id]!.results
            }
            return ShelfSession(session: session, coverage: .recent, results: results)
        }
        // Older sessions stay as they were, unless they are recent now.
        next += sessions.filter { $0.coverage == .older && !recentIDs.contains($0.id) }
        sessions = next
        takenAt = now
        // A thumbnail that failed (the page not up, say) is tried again.
        failedThumbnails.removeAll()
        for item in sessions.prefix(Self.autoLoad) where item.coverage == .recent {
            switch item.results {
            case .notLoaded, .failed: enqueue(.list(item.id))
            default: break
            }
        }
    }

    /// The window closed: every read stops (one under way is cancelled, down
    /// to the page's fetch, and keeps its place among the two until it has
    /// returned or its time limit passes), and what was waiting is let go. What was read stays, in
    /// memory, but for the decoded thumbnails, which are let go. A Save All
    /// that hasn't finished stops (files already saved stay saved; none is
    /// left half-written), and the temporary copies are deleted, off the main
    /// actor. A single Save goes on: the person chose where it goes.
    func close() {
        generation += 1
        transfers.close()
        let stopped = Array(jobs.values) + Array(saveAllTasks.values)
        for task in stopped { task.cancel() }
        jobs = [:]
        saveAllTasks = [:]
        preparers = [:]
        preparing = []
        batches = batches.filter { if case .finished = $0.value { true } else { false } }
        olderTask?.cancel()
        olderTask = nil
        if older == .loading {
            older = sessions.contains { $0.coverage == .older } ? .shown(next: olderCursor) : .hidden
        }
        for index in sessions.indices {
            switch sessions[index].results {
            case .queued, .loading: sessions[index].results = .notLoaded
            default: break
            }
        }
        focused = nil
        // A new run: a write still landing for the old one is dropped.
        let oldRun = runID
        runID = UUID()
        copies = [:]
        let writes = Array(copyWrites.values)
        copyWrites = [:]
        let previous = unwinding
        let storage = storage
        unwinding = Task {
            await previous?.value
            await storage.remove(run: oldRun)
            for task in stopped { await task.value }
            for write in writes { _ = try? await write.value }
        }
        thumbnailStore.removeAll()
    }

    /// Launch: deletes the temporary copies every earlier run left (a run
    /// that never closed), off the main actor. It returns at once; this run's
    /// first copy is written only after it, and it never deletes this run's.
    func cleanUpAtLaunch() {
        let previous = launchCleanup
        let storage = storage
        launchCleanup = Task {
            await previous?.value
            await storage.removeLeftovers()
        }
    }

    /// BenchApp's launch call: `cleanUpAtLaunch()` on the shared shelf.
    /// It doesn't wait for the disk.
    static func removeTemporaryCopies() {
        shared.cleanUpAtLaunch()
    }

    /// A session opened or retried: its results are read.
    func load(_ sessionID: String) {
        guard let item = sessions.first(where: { $0.id == sessionID }) else { return }
        switch item.results {
        case .queued, .loading: return
        default: enqueue(.list(sessionID))
        }
    }

    /// "Show Older Sessions", then "Show More": the next page from the database.
    /// A page that fails is tried again from where it failed, keeping what
    /// was shown.
    func showOlder() {
        switch older {
        case .loading, .shown(nil): return
        case .shown(let next?): olderCursor = next
        case .hidden: olderCursor = nil
        case .failed: break
        }
        let cursor = olderCursor
        older = .loading
        let started = generation
        olderTask = Task { [weak self] in
            guard let self else { return }
            let page = await self.dependencies.older(cursor)
            guard !Task.isCancelled, started == self.generation else { return }
            guard let page else {
                self.older = .failed
                return
            }
            let known = Set(self.sessions.map(\.id))
            self.sessions += page.sessions.filter { !known.contains($0.id) }
                .map { ShelfSession(session: $0, coverage: .older, results: .notLoaded) }
            self.older = .shown(next: page.next)
        }
    }

    /// Opens the conversation a result came from.
    func openSession(_ session: SessionStatus) {
        dependencies.open(session)
    }

    /// Waits until the work the shelf owns is done: the reads asked for and
    /// any they start, Save All, copies being written, what a close left to
    /// unwind, and launch's cleanup. A read nobody waits for any more isn't
    /// waited for (`transfers.active` still counts it). For tests.
    func settled() async {
        var seen: Set<Task<Void, Never>> = []
        var seenWrites: Set<Task<URL?, any Error>> = []
        while true {
            let owned = Array(jobs.values) + [olderTask, unwinding, launchCleanup].compactMap { $0 } + Array(saveAllTasks.values)
            if let task = owned.first(where: { !seen.contains($0) }) {
                await task.value
                seen.insert(task)
            } else if let write = copyWrites.values.first(where: { !seenWrites.contains($0) }) {
                _ = try? await write.value
                seenWrites.insert(write)
            } else {
                break
            }
        }
    }

    /// Reads under way that someone still waits for: for tests.
    var readsUnderWay: Int { transfers.running }

    // MARK: Thumbnails

    /// An image's row came into view: its thumbnail, once.
    func wantThumbnail(_ entry: ArtifactEntry) {
        guard ArtifactGate.thumb(kind: entry.kind) == nil, !thumbnailStore.knows(entry.version),
              !failedThumbnails.contains(entry.version), jobs[.thumb(entry.version)] == nil else { return }
        enqueue(.thumb(entry.version))
    }

    /// Hands a thumbnail's bytes to the store, which decodes and keeps them within its budget.
    private func storeThumbnail(_ data: Data, for version: String) {
        thumbnailStore.receive(data, for: version)
    }

    // MARK: Lists and thumbnails

    /// A list (before thumbnails) or a thumbnail (last of all) joins the queue.
    private func enqueue(_ job: Job) {
        guard jobs[job] == nil else { return }
        let started = generation
        let key: ArtifactRead
        let priority: ShelfTransfers.Priority
        switch job {
        case .list(let id):
            key = .list(frame: id)
            priority = .list
            setResults(id, .queued)
        case .thumb(let version):
            key = .thumb(version: version, width: 120)
            priority = .thumbnail
        }
        jobs[job] = Task { [weak self] in
            guard let self else { return }
            let result = await self.transfers.read(key, priority: priority, started: { [weak self] in
                guard let self, started == self.generation, case .list(let id) = job else { return }
                self.setResults(id, .loading)
            })
            guard started == self.generation else { return }
            self.jobs[job] = nil
            self.finish(job, result)
        }
    }

    private func finish(_ job: Job, _ result: ShelfTransferResult) {
        switch job {
        case .list(let id):
            switch result {
            case .answered(.list(let entries)): setResults(id, .loaded(ArtifactJSON.sorted(entries), at: dependencies.now()))
            case .answered(.cancelled), .cancelled: setResults(id, .notLoaded)
            case .answered(let other): setResults(id, .failed(ShelfFailure(other)))
            case .timedOut: setResults(id, .failed(.timedOut))
            case .notReady: setResults(id, .failed(.notReady))
            }
        case .thumb(let version):
            if case .answered(.bytes(let data)) = result, case .success(let webp) = ArtifactGate.thumbBytes(data) {
                storeThumbnail(webp, for: version)
            } else if result != .cancelled, result != .answered(.cancelled) {
                failedThumbnails.insert(version)
            }
        }
    }

    private func setResults(_ id: String, _ results: ShelfResults) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].results = results
    }

    // MARK: Fetching a file

    /// A file's whole content, or why not.
    private enum Fetched: Sendable {
        case bytes(Data)
        case tooBig
        case failed(ShelfFailure)
        /// The asker stopped waiting, or the window closed: no failure to show.
        case cancelled
    }

    /// Before any read: the page is up, and the listing's size is within the 8 MB cap.
    private func refusal(for entry: ArtifactEntry) -> Fetched? {
        guard dependencies.isReady() else { return .failed(.notReady) }
        if ArtifactGate.download(size: entry.size) != nil { return .tooBig }
        return nil
    }

    /// The one path every whole-file read takes (Quick Look, drag, Copy, Save,
    /// Save All): the shared queue within the time limit, and the bytes
    /// checked against the cap again, whatever the listing said.
    private func fetch(_ entry: ArtifactEntry, priority: ShelfTransfers.Priority,
                       keepsOnClose: Bool = false) async -> Fetched {
        switch await transfers.read(.download(version: entry.version), priority: priority, keepsOnClose: keepsOnClose) {
        case .answered(.bytes(let data)):
            guard case .success(let bytes) = ArtifactGate.downloadBytes(data) else { return .tooBig }
            return .bytes(bytes)
        case .answered(.tooBig): return .tooBig
        case .answered(.cancelled), .cancelled: return .cancelled
        case .answered(let other): return .failed(ShelfFailure(other))
        case .timedOut: return .failed(.timedOut)
        case .notReady: return .failed(.notReady)
        }
    }

    /// Puts what a refused or failed fetch says on the row.
    private func setProblem(_ fetched: Fetched, for entry: ArtifactEntry, use: ShelfFileUse) {
        switch fetched {
        case .bytes, .cancelled: break
        case .tooBig: fileProblems[entry.version] = use.tooBig
        case .failed(let failure): fileProblems[entry.version] = failure.sentence
        }
    }

    /// A version is being fetched for a copy or Copy: the row's spinner.
    private func beginPreparing(_ version: String) {
        preparers[version, default: 0] += 1
        preparing.insert(version)
    }

    /// One asker is done; the spinner goes with the last. A close since
    /// cleared them all.
    private func endPreparing(_ version: String, started: Int) {
        guard started == generation, let count = preparers[version] else { return }
        if count > 1 {
            preparers[version] = count - 1
        } else {
            preparers[version] = nil
            preparing.remove(version)
        }
    }

    /// A version is being saved: its row's spinner, and the Save's busy guard.
    private func beginSaving(_ version: String) {
        let holds = savingHolds[version, default: 0]
        savingHolds[version] = holds + 1
        if holds == 0 { saving.insert(version) }
    }

    /// One saver is done with a version; the spinner goes with the last. Closing
    /// the window doesn't clear these: a Save goes on, and a Save All unwinds.
    private func endSaving(_ version: String) {
        guard let holds = savingHolds[version] else { return }
        if holds > 1 {
            savingHolds[version] = holds - 1
        } else {
            savingHolds[version] = nil
            saving.remove(version)
        }
    }

    // MARK: Temporary copies: Quick Look and drag

    /// The temporary copy made this run for a version, as last known: what
    /// Quick Look asks for on the main thread, so nothing is read from the
    /// disk here.
    func cachedCopy(_ version: String) -> URL? {
        copies[version]
    }

    /// A file's temporary copy: the one made already this run (by version id,
    /// if it is still on disk), or a download within the cap, written 0600
    /// into this run's private folder off the main actor. Askers of the same
    /// version share one download and one write. Cancelling the asking task
    /// withdraws its want of the download.
    func temporaryCopy(of entry: ArtifactEntry) async -> ShelfTemporaryOutcome {
        let version = entry.version
        let started = generation
        let run = runID
        if let url = copies[version] {
            let there = await storage.exists(url)
            // The window closed meanwhile: that copy is of the run being deleted,
            // and nothing is fetched for a window that is gone.
            guard started == generation else { return .cancelled }
            if there { return .ready(url) }
            // The system cleaned it away: made again, not trusted.
            if copies[version] == url { copies[version] = nil }
        }
        switch refusal(for: entry) {
        case .tooBig?: return .tooBig
        case .failed(let failure)?: return .failed(failure)
        default: break
        }
        beginPreparing(version)
        defer { endPreparing(version, started: started) }
        let fetched = await fetch(entry, priority: .foreground)
        guard started == generation else { return .cancelled }
        switch fetched {
        case .bytes(let data):
            do {
                guard let url = try await writeCopy(data, for: entry, run: run), started == generation else {
                    return .cancelled
                }
                return .ready(url)
            } catch {
                return .writeFailed("Couldn't make a temporary copy: \(error.localizedDescription)")
            }
        case .tooBig: return .tooBig
        case .failed(let failure): return .failed(failure)
        case .cancelled: return .cancelled
        }
    }

    /// Writes a copy off the main actor, once however many asked; nil when
    /// the run ended meanwhile (the storage dropped it). The first copy waits
    /// for launch's cleanup.
    private func writeCopy(_ data: Data, for entry: ArtifactEntry, run: UUID) async throws -> URL? {
        let version = entry.version
        let task: Task<URL?, any Error>
        if let writing = copyWrites[version] {
            task = writing
        } else {
            let storage = storage
            let cleanup = launchCleanup
            task = Task {
                await cleanup?.value
                return try await storage.write(data, for: entry, run: run)
            }
            copyWrites[version] = task
        }
        defer { if copyWrites[version] == task { copyWrites[version] = nil } }
        guard let url = try await task.value, run == runID else { return nil }
        copies[version] = url
        return url
    }

    /// Preview: the file's temporary copy, ready for Quick Look. Nil when it
    /// isn't (the row says why), or when a press already has it loading.
    func prepareQuickLook(_ entry: ArtifactEntry) async -> URL? {
        guard !preparing.contains(entry.version) else { return nil }
        return await readyCopy(of: entry, use: .preview)
    }

    /// The Quick Look panel reached a file: its copy, joining a download
    /// already under way for it (Preview's one-press rule is the button's).
    func previewCopy(_ entry: ArtifactEntry) async -> URL? {
        await readyCopy(of: entry, use: .preview)
    }

    /// A drag was dropped: the file's temporary copy to hand over, fetched
    /// now and not when the drag began. Nil when it can't be (the row says why).
    func exportForDrag(_ entry: ArtifactEntry) async -> URL? {
        await readyCopy(of: entry, use: .drag)
    }

    /// A drag began: false, with the reason on the row, when there is nothing to drag out.
    func canDrag(_ entry: ArtifactEntry) -> Bool {
        fileProblems[entry.version] = nil
        guard let refusal = refusal(for: entry) else { return true }
        setProblem(refusal, for: entry, use: .drag)
        return false
    }

    private func readyCopy(of entry: ArtifactEntry, use: ShelfFileUse) async -> URL? {
        fileProblems[entry.version] = nil
        switch await temporaryCopy(of: entry) {
        case .ready(let url): return url
        case .tooBig: fileProblems[entry.version] = use.tooBig
        case .failed(let failure): fileProblems[entry.version] = failure.sentence
        case .writeFailed(let reason): fileProblems[entry.version] = reason
        case .cancelled: break
        }
        return nil
    }

    // MARK: Copy

    /// Copy: the file's content on the pasteboard (an image, text or a PDF;
    /// `ShelfCopy` decides), read within the cap, or from this run's temporary
    /// copy when there is one (read off the main actor). True when it was
    /// copied; otherwise the row says why.
    @discardableResult
    func copy(_ entry: ArtifactEntry) async -> Bool {
        let version = entry.version
        guard !preparing.contains(version) else { return false }
        fileProblems[version] = nil
        guard ShelfCopy.isOffered(entry.kind) else {
            fileProblems[version] = ShelfCopyContent.notOffered.problem
            return false
        }
        let started = generation
        var data: Data?
        if let url = copies[version] {
            beginPreparing(version)
            data = try? await storage.read(url)
            endPreparing(version, started: started)
            guard started == generation else { return false }
            // Gone from the disk: fetched again, and not offered to Quick Look.
            if data == nil, copies[version] == url { copies[version] = nil }
        }
        if data == nil {
            if let refusal = refusal(for: entry) {
                setProblem(refusal, for: entry, use: .copy)
                return false
            }
            beginPreparing(version)
            let fetched = await fetch(entry, priority: .foreground)
            guard started == generation else { return false }
            endPreparing(version, started: started)
            guard case .bytes(let bytes) = fetched else {
                setProblem(fetched, for: entry, use: .copy)
                return false
            }
            data = bytes
        }
        let content = ShelfCopy.content(kind: entry.kind, data: data ?? Data())
        if let problem = content.problem {
            fileProblems[version] = problem
            return false
        }
        guard dependencies.pasteboard(content) else {
            fileProblems[version] = "Couldn't copy this."
            return false
        }
        return true
    }

    // MARK: Saving

    /// Save: the file's bytes, within 8 MB by its listing and again by its
    /// bytes, written where the person chose (off the main actor). Only here,
    /// and in Save All, does a result's content reach the disk for keeps.
    /// Pass the file's project to remember the folder for the next save in it.
    /// It goes on if the window closes.
    @discardableResult
    func save(_ entry: ArtifactEntry, to url: URL, project: String? = nil) async -> ShelfSaveOutcome {
        guard !saving.contains(entry.version) else { return .busy }
        fileProblems[entry.version] = nil
        let outcome = await download(entry, to: url)
        switch outcome {
        case .saved(let url):
            saved[entry.version] = url
            dependencies.didSave(url)
            if let project { folders.remember(url.deletingLastPathComponent(), for: project) }
        case .tooBig:
            fileProblems[entry.version] = Self.tooBigToSave
        case .failed(let failure):
            fileProblems[entry.version] = failure.sentence
        case .writeFailed(let reason):
            fileProblems[entry.version] = reason
        case .busy, .cancelled:
            break
        }
        return outcome
    }

    private static let tooBigToSave = "Over 8 MB: open the session to download it there."

    /// A write that failed, on the row: what the system or the writer said.
    private static func couldntSave(_ error: any Error) -> String {
        "Couldn't save it there: \(error.localizedDescription)"
    }

    private func download(_ entry: ArtifactEntry, to url: URL) async -> ShelfSaveOutcome {
        switch refusal(for: entry) {
        case .tooBig?: return .tooBig
        case .failed(let failure)?: return .failed(failure)
        default: break
        }
        beginSaving(entry.version)
        defer { endSaving(entry.version) }
        switch await fetch(entry, priority: .foreground, keepsOnClose: true) {
        case .bytes(let bytes):
            do {
                try await savedFiles.write(bytes, to: url, using: dependencies.write)
                return .saved(url)
            } catch {
                return .writeFailed(Self.couldntSave(error))
            }
        case .tooBig: return .tooBig
        case .failed(let failure): return .failed(failure)
        case .cancelled: return .cancelled
        }
    }

    /// The folder a save panel starts in for a project: the last one files of
    /// it were saved to, if that is still there.
    func startingFolder(for projectID: String) -> URL? {
        folders.folder(for: projectID)
    }

    /// The saved copy, if it is still where it was saved; a copy that was
    /// moved or deleted is forgotten, and says so.
    func savedCopy(_ version: String, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL? {
        guard let url = saved[version] else { return nil }
        guard exists(url) else {
            saved[version] = nil
            fileProblems[version] = "The saved copy was moved or deleted."
            return nil
        }
        return url
    }

    // MARK: Save All

    /// A Save All is under way. One runs at a time, so a Mac that is
    /// saving isn't also asked to save another session.
    var isSavingAll: Bool { !saveAllTasks.isEmpty }

    /// Save All…: every file of a loaded session, saved into `folder`.
    /// Two of its downloads wait in the shared queue at a time (after what the
    /// person asked for, before lists and thumbnails), each within the time
    /// limit and the 8 MB cap (one over it is skipped without a download).
    /// A name already in the folder, or earlier in the batch, gets " 2",
    /// " 3"… before its extension: nothing is overwritten. Each file is
    /// written whole, off the main actor, and recorded like a single Save
    /// (Open and Reveal in Finder work for it). Progress and then a summary
    /// by count go in `batches`. Closing the window stops what hasn't started.
    /// A folder that stops answering fails the write that found out after its
    /// limit and the rest at once, without downloading them (`ShelfSavedFiles`).
    func saveAll(_ sessionID: String, into folder: URL) {
        guard saveAllTasks.isEmpty,
              let item = sessions.first(where: { $0.id == sessionID }),
              let entries = item.results.entries, !entries.isEmpty else { return }
        let started = generation
        batches[sessionID] = .saving(done: 0, total: entries.count)
        saveAllTasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            await self.runSaveAll(sessionID, entries: entries, project: item.session.projectID, folder: folder, started: started)
            // Only a run the window's closing didn't cut short unregisters itself.
            // One that did is still unwinding while the next Save All may already
            // be registered (one runs per opening), and that one is not its to clear.
            if started == self.generation { self.saveAllTasks[sessionID] = nil }
        }
    }

    /// A run the window's closing cut short has nothing of its own to clear once
    /// it unwinds but the files it marked saving: `close()` already dropped its
    /// progress row and its registration, and the next Save All of the same
    /// session may have set both again. (Only one Save All runs at a time, so a
    /// run is the live one exactly while `started == generation`.)
    private func runSaveAll(_ sessionID: String, entries: [ArtifactEntry], project: String, folder: URL,
                            started: Int) async {
        guard !Task.isCancelled, started == generation else { return }
        var summary = ShelfSaveAllSummary(folder: folder)
        var done = 0
        var remembered = false
        var reserved: Set<String> = []
        // The files of `work` this run has marked saving and not yet let go of.
        var marked: Set<Int> = []
        // A name is taken when this batch has it, the folder has it, or an
        // earlier write of it hasn't returned (a save that timed out and may
        // still land): numbering around it keeps two writes off one file.
        let isTaken: (String) -> Bool = { [self] candidate in
            reserved.contains(candidate.lowercased())
                || dependencies.exists(folder.appending(path: candidate, directoryHint: .notDirectory))
                || savedFiles.isPending(folder.appending(path: candidate, directoryHint: .notDirectory))
        }
        // The names are settled up front, in the session's order, so the first
        // of two of the same name gets the plain one whatever finishes first.
        var work: [(entry: ArtifactEntry, name: String)] = []
        for entry in entries {
            fileProblems[entry.version] = nil
            if ArtifactGate.download(size: entry.size) != nil {
                summary.tooBig += 1
                done += 1
                fileProblems[entry.version] = Self.tooBigToSave
                continue
            }
            let name = ShelfFileName.unique(ShelfFileName.sanitized(entry.name), taken: isTaken)
            reserved.insert(name.lowercased())
            work.append((entry, name))
        }
        batches[sessionID] = .saving(done: done, total: entries.count)

        await withTaskGroup(of: (Int, Fetched).self) { group in
            var next = 0
            var active = 0
            while true {
                // Up to `concurrency` of this batch's downloads ask at once (so
                // at most that many files wait in memory); one more as each ends.
                while active < Self.concurrency, next < work.count, !Task.isCancelled {
                    let index = next
                    let entry = work[index].entry
                    next += 1
                    // A folder that stopped answering refuses the rest at once
                    // (ShelfSavedFiles): nothing more is downloaded for it.
                    if savedFiles.isHeldOff(folder) {
                        done += 1
                        summary.failed += 1
                        fileProblems[entry.version] = Self.couldntSave(ShelfSaveError.folderStillSilent)
                        batches[sessionID] = .saving(done: done, total: entries.count)
                        continue
                    }
                    active += 1
                    beginSaving(entry.version)
                    marked.insert(index)
                    group.addTask {
                        let fetched = await self.fetch(entry, priority: .saveAll)
                        return (index, fetched)
                    }
                }
                guard active > 0, let result = await group.next() else { break }
                let (index, fetched) = result
                active -= 1
                guard !Task.isCancelled, started == generation else {
                    group.cancelAll()
                    break
                }
                let entry = work[index].entry
                done += 1
                switch fetched {
                case .bytes(let bytes):
                    var name = work[index].name
                    var url = folder.appending(path: name, directoryHint: .notDirectory)
                    if dependencies.exists(url) || savedFiles.isPending(url) {
                        // Something took the name since the plan was made.
                        name = ShelfFileName.unique(name, taken: isTaken)
                        reserved.insert(name.lowercased())
                        url = folder.appending(path: name, directoryHint: .notDirectory)
                    }
                    do {
                        try await savedFiles.write(bytes, to: url, using: dependencies.write)
                        // Written whole: saved, even if the window closed meanwhile.
                        saved[entry.version] = url
                        summary.saved += 1
                        if !remembered {
                            folders.remember(folder, for: project)
                            remembered = true
                        }
                    } catch {
                        summary.failed += 1
                        fileProblems[entry.version] = Self.couldntSave(error)
                    }
                case .tooBig:
                    summary.tooBig += 1
                    fileProblems[entry.version] = Self.tooBigToSave
                case .failed(let failure):
                    summary.failed += 1
                    fileProblems[entry.version] = failure.sentence
                case .cancelled:
                    break
                }
                endSaving(entry.version)
                marked.remove(index)
                guard !Task.isCancelled, started == generation else {
                    group.cancelAll()
                    break
                }
                batches[sessionID] = .saving(done: done, total: entries.count)
            }
        }
        for index in marked { endSaving(work[index].entry.version) }
        guard !Task.isCancelled, started == generation else { return }
        batches[sessionID] = .finished(summary)
    }

    // MARK: Showing one session

    /// A session's row opened or closed by hand (or by `focus`).
    func setExpanded(_ id: String, open: Bool) {
        disclosure.set(id, open: open)
    }

    /// Show this session: in the list (the recent snapshot is taken again if the
    /// Lab knows it now, and it goes at the top of the recent sessions if the
    /// snapshot still doesn't), its row open, its results read if they weren't
    /// (or were read before the session last wrote), and `focused` set so the
    /// window scrolls to it and selects it.
    func focus(_ session: SessionStatus) {
        if !sessions.contains(where: { $0.id == session.id }), dependencies.recent().contains(where: { $0.id == session.id }) {
            open()
        }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            // The newer word on the session (its title, say) replaces the older.
            if session.updatedAt > sessions[index].session.updatedAt {
                sessions[index] = ShelfSession(session: session, coverage: sessions[index].coverage,
                                               results: sessions[index].results)
            }
        } else {
            sessions.insert(ShelfSession(session: session, coverage: .recent, results: .notLoaded), at: 0)
        }
        disclosure.set(session.id, open: true)
        switch sessions.first(where: { $0.id == session.id })?.results {
        case .notLoaded?, .failed?: load(session.id)
        case .loaded(_, let at)? where at < session.updatedAt: load(session.id)
        default: break
        }
        focused = ShelfFocus(sessionID: session.id, token: (focused?.token ?? 0) + 1)
    }
}
