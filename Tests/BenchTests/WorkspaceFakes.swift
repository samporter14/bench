// WorkspaceFakes.swift — made-up pieces for the Project Workspaces tests: a disk
// in memory that can hold a read or a write until the test lets it go (and
// counts how many writes are under way at once), and a made-up app for Return
// to Project that records every effect it is asked for and holds a database
// look until it is released. Nothing here reads Claude Science, opens a window
// or touches the real Application Support folder.
import Foundation
@testable import Bench

/// Workspace files in memory.
@MainActor
final class FakeWorkspaceDisk: WorkspaceDisk {
    /// The files, by project id.
    var files: [String: Data] = [:]
    /// Files moved to the "Trash", by project id.
    private(set) var trashed: [String: Data] = [:]
    /// Every write that landed, in order.
    private(set) var written: [(projectID: String, data: Data)] = []
    var failsWrites = false
    var holdsWrites = false
    var holdsReads = false
    private(set) var reads = 0
    private(set) var writing = 0
    private(set) var mostWritingAtOnce = 0
    private var heldWrites: [CheckedContinuation<Void, Never>] = []
    private var heldReads: [CheckedContinuation<Void, Never>] = []

    var heldWriteCount: Int { heldWrites.count }
    var heldReadCount: Int { heldReads.count }

    func read(_ projectID: String) async -> WorkspaceRead {
        reads += 1
        if holdsReads { await withCheckedContinuation { heldReads.append($0) } }
        return files[projectID].map { .bytes($0) } ?? .missing
    }

    func write(_ data: Data, for projectID: String) async throws {
        writing += 1
        mostWritingAtOnce = max(mostWritingAtOnce, writing)
        defer { writing -= 1 }
        if holdsWrites { await withCheckedContinuation { heldWrites.append($0) } }
        if failsWrites { throw WorkspaceDiskError.failed("The disk is full.") }
        files[projectID] = data
        written.append((projectID, data))
    }

    func trash(_ projectID: String) async throws {
        if let data = files.removeValue(forKey: projectID) { trashed[projectID] = data }
    }

    func projects() async -> [String] { files.keys.sorted() }

    /// Lets the held writes go, the newest first when `newestFirst`.
    func releaseWrites(newestFirst: Bool = false) {
        let held = newestFirst ? heldWrites.reversed() : heldWrites
        heldWrites = []
        for waiter in held { waiter.resume() }
    }

    func releaseReads() {
        let held = heldReads
        heldReads = []
        for waiter in held { waiter.resume() }
    }

    /// The note in `projectID`'s file as written, when it is a record.
    func note(_ projectID: String) -> String? {
        guard let data = files[projectID], case .record(let record) = WorkspaceRules.decode(data, projectID: projectID) else { return nil }
        return record.note
    }

    func record(_ projectID: String) -> WorkspaceRecord? {
        guard let data = files[projectID], case .record(let record) = WorkspaceRules.decode(data, projectID: projectID) else { return nil }
        return record
    }
}

/// The app as Return to Project sees it: every effect recorded, and the database's looks answered from a table,
/// each held while the test says so.
@MainActor
final class FakeWorkspaceApp {
    /// What the database says of each session; anything not here is gone.
    var sessions: [String: WorkspaceSessionLook] = [:]
    /// How a pin's window lands; anything not here lands.
    var landings: [String: WorkspacePinOutcome] = [:]
    var shelfProjects: Set<String> = []
    var canNavigate = true
    /// Sessions whose looks wait for `release`.
    var holding: Set<String> = []
    private var held: [(session: String, continuation: CheckedContinuation<Void, Never>)] = []

    /// The one main web view's loads.
    private(set) var navigations: [LastSession.Route] = []
    /// Reference windows, by session: one each, as the controller keeps them.
    private(set) var windows: [String: Int] = [:]
    /// Every time a window was asked for (made or reused) and its row.
    private(set) var openings: [(session: String, row: Int?)] = []
    private(set) var shelfShown: [String] = []
    private(set) var looks: [String] = []
    /// Window landings being waited on right now: what Return leaves behind must be none.
    private(set) var waiting = 0

    func release(_ session: String) {
        let ready = held.filter { $0.session == session }
        held.removeAll { $0.session == session }
        for item in ready { item.continuation.resume() }
    }

    var heldLooks: Int { held.count }

    func look(_ sessionID: String) async -> WorkspaceSessionLook {
        looks.append(sessionID)
        if holding.contains(sessionID) { await withCheckedContinuation { held.append((sessionID, $0)) } }
        return sessions[sessionID] ?? .gone
    }

    var dependencies: WorkspaceReturnDependencies {
        WorkspaceReturnDependencies(
            look: { [self] sessionID, _ in await look(sessionID) },
            navigate: { [self] route in
                guard canNavigate else { return false }
                navigations.append(route)
                return true
            },
            openReference: { [self] pin, _ in
                openings.append((pin.sessionID, pin.row))
                windows[pin.sessionID] = 1
                waiting += 1
                defer { waiting -= 1 }
                await Task.yield()
                return landings[pin.sessionID] ?? .landed
            },
            shelfHas: { [self] projectID in
                // A project in `holding` as "shelf:<id>" waits for `release` too.
                if holding.contains("shelf:" + projectID) {
                    await withCheckedContinuation { held.append(("shelf:" + projectID, $0)) }
                }
                return shelfProjects.contains(projectID)
            },
            showShelf: { [self] projectID in shelfShown.append(projectID) })
    }
}

/// Waits a few turns of the main actor at most for `condition`.
@MainActor
func untilWorkspace(_ tries: Int = 2_000, _ condition: () -> Bool) async {
    for _ in 0..<tries where !condition() { await Task.yield() }
}
