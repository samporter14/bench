// WorkspaceStore.swift — the workspaces in memory and on disk (DESIGN.md,
// Project Workspaces). Each project's record is read as one snapshot, changed
// here (the note typed, a reference pinned or unpinned, the workspace
// cleared) and written whole, off the main actor, one write at a time per
// project, each taking the record as it is when the write begins. The note is
// written a moment after typing stops (and never more than a few seconds
// after it began), at once when the panel moves to another project or
// closes. A save that fails keeps everything in memory and says so; nothing
// is called saved until a write has landed. A read never lands over a change
// made since it began, and a file that isn't a record Capsid can read (damaged,
// or a newer Capsid's) is left exactly as it is: nothing is written over it.
//
// Every record is keyed by the project's id, so two projects of one name
// never share anything. Nothing here reads Claude Science or calls the
// daemon; a launch reads the records' folder once, for the menu.
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "workspace")

/// A project with a record on disk, as the Return to Project menu lists it.
struct WorkspaceSummary: Equatable, Sendable {
    let projectID: String
    let projectName: String
    let pinned: [String]
    let hasContent: Bool
    let updatedAt: Date

    init(_ record: WorkspaceRecord) {
        projectID = record.projectID
        projectName = record.projectName
        pinned = record.pins.map(\.sessionID)
        hasContent = record.hasContent
        updatedAt = record.updatedAt
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore(disk: WorkspaceFiles())

    /// Whether a project's record can be shown and changed.
    enum Standing: Equatable, Sendable {
        case loading
        case ready
        /// A file that isn't a record of this shape: left as it is.
        case damaged
        /// A newer Capsid's record: left as it is.
        case newer
        /// The file couldn't be read at all.
        case unreadable(String)

        /// Why the panel can't show the record, or nil when it can.
        var sentence: String? {
            switch self {
            case .loading, .ready: nil
            case .damaged: "This workspace\u{2019}s file is damaged, so Capsid leaves it exactly as it is."
            case .newer: "This workspace was saved by a newer Capsid, so this one leaves it as it is."
            case .unreadable(let sentence): sentence
            }
        }
    }

    /// How the record's saving stands. Every change made in memory is a revision; a write that lands has saved the
    /// revisions up to the one it took.
    struct SaveState: Equatable, Sendable {
        var revision = 0
        var savedRevision = 0
        var writing = false
        /// The last write failed, and nothing has landed since: the panel says so and offers Retry.
        var failure: String?

        var isSaved: Bool { revision == savedRevision }
    }

    /// What pinning a reference came to.
    enum PinOutcome: Equatable, Sendable {
        case pinned
        case alreadyPinned
        /// Four are pinned already: nothing was dropped and nothing was added.
        case full(projectName: String)
        /// Pinned in memory, but the write failed: the panel offers Retry.
        case unsaved(String)
        case unavailable(String)
    }

    @Published private(set) var records: [String: WorkspaceRecord] = [:]
    @Published private(set) var standings: [String: Standing] = [:]
    @Published private(set) var saves: [String: SaveState] = [:]
    /// Projects whose last edit to the note was refused for its size, until the next edit that is made.
    @Published private(set) var refused: Set<String> = []
    /// Every project with a record, as the launch's read found it and as changed since: the menu's list.
    @Published private(set) var summaries: [String: WorkspaceSummary] = [:]

    let disk: any WorkspaceDisk
    private let delay: Duration
    private let longest: Duration
    private let sleep: @MainActor (Duration) async -> Void
    private let now: () -> Date

    /// Changes made here, by project, never reset: a read that began before one lands on nothing.
    private var changes: [String: Int] = [:]
    private var loads: [String: Task<Void, Never>] = [:]
    /// Each project's last write: the next waits for it, so two never overlap and the newest is written last.
    private var lastWrite: [String: Task<Void, Never>] = [:]
    /// A write asked for and not yet begun: asking again is that write, which takes the record as it is when it begins.
    private var pending: Set<String> = []
    private var debounces: [String: Task<Void, Never>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var clearing: Set<String> = []
    private var scanStarted = false

    /// Records the launch reads for the menu, at most.
    static let scanLimit = 200

    /// `delay` is the wait after a keystroke, `longest` the most typing can hold a save back. `sleep` waits (tests
    /// stand a clock in that they set off).
    init(disk: any WorkspaceDisk, delay: Duration = .milliseconds(800), longest: Duration = .seconds(4),
         sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         now: @escaping () -> Date = { Date() }) {
        self.disk = disk
        self.delay = delay
        self.longest = longest
        self.sleep = sleep
        self.now = now
    }

    // MARK: The launch's read, for the menu

    /// Reads the records' folder once, a few seconds after launch and off the main actor, so Return to Project can
    /// list the projects that have a workspace. A record read here never replaces one loaded since.
    func start(after wait: Duration = .seconds(3)) {
        guard !scanStarted else { return }
        scanStarted = true
        let disk = disk
        Task { [weak self] in
            if wait > .zero { try? await Task.sleep(for: wait) }
            let found = await Task.detached(priority: .utility) { () -> [WorkspaceSummary] in
                var found: [WorkspaceSummary] = []
                for id in await disk.projects().prefix(WorkspaceStore.scanLimit) {
                    guard case .bytes(let data) = await disk.read(id),
                          case .record(let record) = WorkspaceRules.decode(data, projectID: id) else { continue }
                    found.append(WorkspaceSummary(record))
                }
                return found
            }.value
            guard let self else { return }
            for summary in found where self.standings[summary.projectID] == nil && self.summaries[summary.projectID] == nil {
                self.summaries[summary.projectID] = summary
            }
            log.notice("Workspaces read: \(found.count, privacy: .public)")
        }
    }

    // MARK: Reading a record

    /// Reads `projectID`'s record, unless a read is under way (that one is returned) or something here isn't saved
    /// yet (memory is the newest there is). A read that lands after a change made here changes nothing.
    @discardableResult
    func load(_ projectID: String, name: String? = nil) -> Task<Void, Never> {
        guard WorkspaceRules.isProjectID(projectID) else { return Task {} }
        if let name { rename(projectID, to: name) }
        if let running = loads[projectID] { return running }
        if standings[projectID] == .ready, hasUnsaved(projectID) || clearing.contains(projectID) { return Task {} }
        if standings[projectID] == nil { standings[projectID] = .loading }
        let started = changes[projectID, default: 0]
        let disk = disk
        let task = Task { [weak self] in
            let read = await disk.read(projectID)
            guard let self else { return }
            self.loads[projectID] = nil
            guard self.changes[projectID, default: 0] == started else { return }
            self.apply(read, to: projectID, name: name)
        }
        loads[projectID] = task
        return task
    }

    /// Reads the record if it hasn't been, and says whether it can be changed.
    func ready(_ projectID: String) async -> Bool {
        if standings[projectID] != .ready { await load(projectID).value }
        return standings[projectID] == .ready && !clearing.contains(projectID)
    }

    private func apply(_ read: WorkspaceRead, to projectID: String, name: String?) {
        let known = name.map(WorkspaceRules.clean) ?? records[projectID]?.projectName ?? summaries[projectID]?.projectName ?? ""
        switch read {
        case .missing:
            records[projectID] = WorkspaceRecord(projectID: projectID, projectName: known, updatedAt: now())
            standings[projectID] = .ready
        case .bytes(let data):
            switch WorkspaceRules.decode(data, projectID: projectID) {
            case .record(var record):
                if !known.isEmpty { record.projectName = known }
                records[projectID] = record
                standings[projectID] = .ready
            case .none:
                records[projectID] = WorkspaceRecord(projectID: projectID, projectName: known, updatedAt: now())
                standings[projectID] = .ready
            case .damaged:
                records[projectID] = nil
                standings[projectID] = .damaged
                log.notice("A workspace file is damaged; it is left as it is")
            case .newer(let schema):
                records[projectID] = nil
                standings[projectID] = .newer
                log.notice("A workspace file has schema \(schema, privacy: .public); it is left as it is")
            }
        case .failed(let sentence):
            records[projectID] = nil
            standings[projectID] = .unreadable(sentence)
        }
        saves[projectID] = SaveState()
        summarise(projectID)
    }

    // MARK: What is shown

    func record(_ projectID: String) -> WorkspaceRecord? { records[projectID] }

    func standing(_ projectID: String) -> Standing? { standings[projectID] }

    func save(_ projectID: String) -> SaveState { saves[projectID] ?? SaveState() }

    /// Whether `sessionID` is pinned to `projectID`, as far as is known (the record, else the launch's read).
    func isPinned(_ sessionID: String, in projectID: String) -> Bool {
        if let record = records[projectID] { return record.isPinned(sessionID) }
        return summaries[projectID]?.pinned.contains(sessionID) ?? false
    }

    /// Something typed or pinned here isn't written yet, or a write is under way.
    func hasUnsaved(_ projectID: String) -> Bool {
        let state = save(projectID)
        return !state.isSaved || state.writing || pending.contains(projectID) || debounces[projectID] != nil
    }

    /// Any project with something not yet written: what quitting waits for.
    var hasUnsavedWork: Bool { records.keys.contains { hasUnsaved($0) } }

    /// The projects Return to Project offers, with what the menu calls each: those with a pin or a note, the one
    /// shown most recently first (then the one changed most recently), two of one name told apart.
    func returnable(recency: (String) -> Int?, limit: Int = 20) -> [(id: String, title: String)] {
        let listed = summaries.values.filter(\.hasContent).sorted { a, b in
            switch (recency(a.projectID), recency(b.projectID)) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.updatedAt == b.updatedAt ? a.projectID < b.projectID : a.updatedAt > b.updatedAt
            }
        }.prefix(limit)
        let titles = WorkspaceRules.listTitles(listed.map { ($0.projectID, $0.projectName) })
        return zip(listed, titles).map { ($0.projectID, $1) }
    }

    // MARK: Presentation

    /// The project's name as the app knows it now: kept in memory, written with the next change.
    func rename(_ projectID: String, to name: String) {
        let clean = WorkspaceRules.clean(name)
        guard !clean.isEmpty, var record = records[projectID], record.projectName != clean else { return }
        record.projectName = clean
        records[projectID] = record
        summarise(projectID)
    }

    /// The pinned sessions' titles as the database has them now, likewise.
    func retitle(_ projectID: String, titles: [String: String]) {
        guard var record = records[projectID] else { return }
        var changed = false
        for index in record.pins.indices {
            if let title = titles[record.pins[index].sessionID].map(WorkspaceRules.clean), !title.isEmpty,
               record.pins[index].title != title {
                record.pins[index].title = title
                changed = true
            }
        }
        if changed { records[projectID] = record }
    }

    // MARK: The note

    /// The note as typed. A note past the limit is refused whole (the field keeps what it had, and says why), never
    /// cut. False when the change wasn't taken.
    @discardableResult
    func setNote(_ text: String, for projectID: String) -> Bool {
        guard standings[projectID] == .ready, !clearing.contains(projectID), var record = records[projectID] else { return false }
        guard WorkspaceRules.fits(note: text) else {
            refused.insert(projectID)
            return false
        }
        if refused.contains(projectID) { refused.remove(projectID) }
        guard record.note != text else { return true }
        record.note = text
        record.updatedAt = now()
        commit(record)
        scheduleSave(projectID)
        return true
    }

    /// A note edit was refused before it reached the store (the field checks first): the panel says so.
    func refuseNote(for projectID: String) {
        refused.insert(projectID)
    }

    /// Writes what isn't written now, after any write under way: the panel moved to another project or closed. The
    /// task is the write, for whoever needs to wait for it.
    @discardableResult
    func flush(_ projectID: String) -> Task<Void, Never> {
        let timed = debounces[projectID] != nil || deadlines[projectID] != nil
        cancelTimers(projectID)
        if timed || !save(projectID).isSaved { return persist(projectID) }
        return lastWrite[projectID] ?? Task {}
    }

    /// Every project's unwritten changes, for quitting.
    func flushAll() async {
        for projectID in Array(records.keys) where hasUnsaved(projectID) {
            await flush(projectID).value
        }
    }

    /// Retry, after a save failed.
    @discardableResult
    func retry(_ projectID: String) -> Task<Void, Never> {
        cancelTimers(projectID)
        return persist(projectID)
    }

    private func scheduleSave(_ projectID: String) {
        debounces[projectID]?.cancel()
        let delay = delay
        debounces[projectID] = Task { [weak self] in
            await self?.sleep(delay)
            guard !Task.isCancelled else { return }
            self?.saveNow(projectID)
        }
        // However long the typing goes on, a save comes this soon after it began.
        guard deadlines[projectID] == nil else { return }
        let longest = longest
        deadlines[projectID] = Task { [weak self] in
            await self?.sleep(longest)
            guard !Task.isCancelled else { return }
            self?.saveNow(projectID)
        }
    }

    private func saveNow(_ projectID: String) {
        cancelTimers(projectID)
        persist(projectID)
    }

    private func cancelTimers(_ projectID: String) {
        debounces.removeValue(forKey: projectID)?.cancel()
        deadlines.removeValue(forKey: projectID)?.cancel()
    }

    // MARK: Pins

    /// Pins a session's reference to its own project: the reply's row when the window shows one, and the titles as
    /// they are. Four at most; a fifth is refused and says so, and nothing pinned is dropped.
    func pin(sessionID: String, projectID: String, row: Int?, title: String, projectName: String) async -> PinOutcome {
        guard WorkspaceRules.isProjectID(projectID), PlanCheck.isFrameID(sessionID) else {
            return .unavailable("This conversation can\u{2019}t be pinned to a project.")
        }
        guard await ready(projectID), var record = records[projectID] else {
            return .unavailable(standings[projectID]?.sentence ?? "The workspace can\u{2019}t be changed right now.")
        }
        let name = WorkspaceRules.clean(projectName)
        if !name.isEmpty { record.projectName = name }
        guard !record.isPinned(sessionID) else { return .alreadyPinned }
        guard record.pins.count < WorkspaceRules.pinLimit else { return .full(projectName: record.projectName) }
        record.pins.append(WorkspacePin(sessionID: sessionID, projectID: projectID, row: row.map { max(0, $0) },
                                        title: WorkspaceRules.clean(title), pinnedAt: now()))
        record.updatedAt = now()
        commit(record)
        await persist(projectID).value
        if let failure = save(projectID).failure { return .unsaved(failure) }
        return .pinned
    }

    /// Takes a pin off. The session and anything it made are untouched.
    func unpin(sessionID: String, projectID: String) async {
        guard await ready(projectID), var record = records[projectID], record.isPinned(sessionID) else { return }
        record.pins.removeAll { $0.sessionID == sessionID }
        record.updatedAt = now()
        commit(record)
        await persist(projectID).value
    }

    // MARK: Clearing

    /// Clear Workspace…: the record's file goes to the Trash (Finder's Put Back undoes it), and the workspace here
    /// is empty. Kept files and conversations are never touched. A damaged or newer file goes the same way, whole.
    /// Nil when it went, else why not.
    func clear(_ projectID: String) async -> String? {
        guard WorkspaceRules.isProjectID(projectID), !clearing.contains(projectID) else { return nil }
        clearing.insert(projectID)
        defer { clearing.remove(projectID) }
        cancelTimers(projectID)
        // A write under way lands first, so nothing written afterwards can bring the file back.
        await lastWrite[projectID]?.value
        do {
            try await disk.trash(projectID)
        } catch {
            return "Couldn\u{2019}t clear the workspace: \(WorkspaceDiskError.sentence(error))"
        }
        changes[projectID, default: 0] += 1
        let name = records[projectID]?.projectName ?? summaries[projectID]?.projectName ?? ""
        records[projectID] = WorkspaceRecord(projectID: projectID, projectName: name, updatedAt: now())
        standings[projectID] = .ready
        saves[projectID] = SaveState()
        refused.remove(projectID)
        summaries[projectID] = nil
        return nil
    }

    // MARK: Writing

    /// A change made here: a new revision to write, and the menu's line for the project.
    private func commit(_ record: WorkspaceRecord) {
        let projectID = record.projectID
        records[projectID] = record
        changes[projectID, default: 0] += 1
        var state = save(projectID)
        state.revision += 1
        saves[projectID] = state
        summarise(projectID)
    }

    private func summarise(_ projectID: String) {
        guard standings[projectID] == .ready, let record = records[projectID] else { return }
        let summary = WorkspaceSummary(record)
        if summaries[projectID] != summary { summaries[projectID] = summary }
    }

    /// Writes the record after the write under way, if any. One not yet begun is the same write.
    @discardableResult
    private func persist(_ projectID: String) -> Task<Void, Never> {
        if pending.contains(projectID), let queued = lastWrite[projectID] { return queued }
        pending.insert(projectID)
        let before = lastWrite[projectID]
        let task = Task { [weak self] in
            await before?.value
            await self?.write(projectID)
        }
        lastWrite[projectID] = task
        return task
    }

    /// The record as it is now, written whole. Only a record that was read (or begun) here is ever written: a
    /// damaged, newer or unreadable file has none in memory.
    private func write(_ projectID: String) async {
        pending.remove(projectID)
        guard standings[projectID] == .ready, !clearing.contains(projectID), let record = records[projectID] else { return }
        var state = save(projectID)
        guard !state.isSaved || state.failure != nil else { return }
        let revision = state.revision
        let data: Data
        do {
            data = try WorkspaceRules.encode(record)
        } catch {
            state.failure = "The workspace couldn\u{2019}t be put into words for the disk."
            saves[projectID] = state
            return
        }
        state.writing = true
        saves[projectID] = state
        do {
            try await disk.write(data, for: projectID)
            var after = save(projectID)
            after.writing = false
            after.savedRevision = max(after.savedRevision, revision)
            after.failure = nil
            saves[projectID] = after
        } catch {
            var after = save(projectID)
            after.writing = false
            after.failure = WorkspaceDiskError.sentence(error)
            saves[projectID] = after
            log.error("A workspace couldn't be saved")
        }
    }
}
