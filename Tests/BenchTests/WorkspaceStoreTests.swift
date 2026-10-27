// WorkspaceStoreTests.swift — the workspaces in memory and on disk: two
// projects of one name share nothing; four pins and a fifth refused; the note
// written a moment after typing stops (and within the longest wait however
// long it goes on), at once when the panel moves on or closes; held writes
// that never land out of order; a read that never lands over newer typing; a
// failed save that keeps the text and a Retry that writes it; the 64 KB limit
// refused whole; damaged and newer files left byte for byte; Clear Workspace…
// to the Trash. Every disk is made up or a temporary folder.
import Foundation
import Testing
@testable import Bench

@MainActor
struct WorkspaceStoreTests {
    private static let alpha = "proj-alpha"
    private static let beta = "proj-beta"
    private static let delay = Duration.milliseconds(800)
    private static let longest = Duration.seconds(4)

    private func store(_ disk: FakeWorkspaceDisk, clock: ManualClock? = nil) -> WorkspaceStore {
        let clock = clock ?? ManualClock()
        return WorkspaceStore(disk: disk, delay: Self.delay, longest: Self.longest, sleep: { await clock.wait($0) },
                              now: { Date(timeIntervalSince1970: 1_790_000_000) })
    }

    private func panel(_ store: WorkspaceStore) -> WorkspacePanelModel {
        let app = FakeWorkspaceApp()
        return WorkspacePanelModel(store: store, returner: WorkspaceReturner(dependencies: app.dependencies),
                                   dependencies: WorkspacePanelDependencies(
                                       look: { _, _ in .unreadable }, projectName: { _ in nil }, watchedName: { _ in nil },
                                       lastSession: { _ in nil }, openPin: { _, _ in }))
    }

    // MARK: One name, two projects

    @Test func twoProjectsOfOneNameShareNoNotePinOrState() async throws {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        await store.load(Self.alpha, name: "Assay development").value
        await store.load(Self.beta, name: "Assay development").value
        #expect(store.setNote("Alpha's note", for: Self.alpha))
        #expect(await store.pin(sessionID: madeUpID(1), projectID: Self.alpha, row: 19, title: "Plate reader QC",
                                projectName: "Assay development") == .pinned)
        #expect(await store.pin(sessionID: madeUpID(2), projectID: Self.beta, row: 7, title: "Dose response",
                                projectName: "Assay development") == .pinned)
        await store.flush(Self.alpha).value
        await store.flush(Self.beta).value

        #expect(store.record(Self.beta)?.note == "")
        #expect(store.isPinned(madeUpID(1), in: Self.alpha) && !store.isPinned(madeUpID(1), in: Self.beta))
        #expect(store.isPinned(madeUpID(2), in: Self.beta) && !store.isPinned(madeUpID(2), in: Self.alpha))
        let a = try #require(disk.record(Self.alpha))
        let b = try #require(disk.record(Self.beta))
        #expect(a.note == "Alpha's note" && a.pins.map(\.sessionID) == [madeUpID(1)] && a.pins.first?.row == 19)
        #expect(b.note == "" && b.pins.map(\.sessionID) == [madeUpID(2)])
        // A failure in one is not the other's.
        disk.failsWrites = true
        store.setNote("Beta changes", for: Self.beta)
        await store.flush(Self.beta).value
        #expect(store.save(Self.beta).failure != nil && store.save(Self.alpha).failure == nil)
        #expect(store.hasUnsaved(Self.beta) && !store.hasUnsaved(Self.alpha))
        // The menu lists both, told apart.
        let titles = store.returnable(recency: { _ in nil }).map(\.title)
        #expect(titles.count == 2 && Set(titles).count == 2 && titles.allSatisfy { $0.hasPrefix("Assay development \u{00B7} ") })
    }

    @Test func thePanelMovingBetweenTwoProjectsOfOneNameKeepsEachNote() async {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        let model = panel(store)
        await model.show(Self.alpha, name: "Assay development").value
        model.edit("Alpha only")
        await model.show(Self.beta, name: "Assay development").value
        #expect(model.record?.note == "")
        model.edit("Beta only")
        await model.show(Self.alpha).value
        #expect(model.record?.note == "Alpha only")
        await store.flush(Self.beta).value
        #expect(disk.note(Self.alpha) == "Alpha only" && disk.note(Self.beta) == "Beta only")
    }

    // MARK: Pins

    @Test func fourPinsAndAFifthIsRefusedWithNothingDropped() async throws {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        for n in 1...4 {
            #expect(await store.pin(sessionID: madeUpID(n), projectID: Self.alpha, row: n * 10, title: "Run \(n)",
                                    projectName: "Assay development") == .pinned)
        }
        #expect(await store.pin(sessionID: madeUpID(5), projectID: Self.alpha, row: 50, title: "Run 5",
                                projectName: "Assay development") == .full(projectName: "Assay development"))
        #expect(store.record(Self.alpha)?.pins.map(\.sessionID) == (1...4).map(madeUpID))
        #expect(disk.record(Self.alpha)?.pins.map(\.sessionID) == (1...4).map(madeUpID))
        #expect(WorkspacePinWords.sentence(for: .full(projectName: "Assay development"))?.contains("four pinned") == true)
        // Pinned again: nothing changes.
        #expect(await store.pin(sessionID: madeUpID(2), projectID: Self.alpha, row: 99, title: "Run 2",
                                projectName: "Assay development") == .alreadyPinned)
        #expect(store.record(Self.alpha)?.pins.first { $0.sessionID == madeUpID(2) }?.row == 20)
        // Unpin one, and the fifth fits.
        await store.unpin(sessionID: madeUpID(2), projectID: Self.alpha)
        #expect(disk.record(Self.alpha)?.pins.map(\.sessionID) == [1, 3, 4].map(madeUpID))
        #expect(await store.pin(sessionID: madeUpID(5), projectID: Self.alpha, row: 50, title: "Run 5",
                                projectName: "Assay development") == .pinned)
        #expect(disk.record(Self.alpha)?.pins.count == 4)
        // A pin that can't be one.
        #expect(await store.pin(sessionID: "not-a-session", projectID: Self.alpha, row: 1, title: "x", projectName: "x")
                != .pinned)
        #expect(await store.pin(sessionID: madeUpID(9), projectID: "../x", row: 1, title: "x", projectName: "x") != .pinned)
    }

    // MARK: The note's saving

    @Test func theNoteIsWrittenAMomentAfterTypingStops() async {
        let disk = FakeWorkspaceDisk()
        let clock = ManualClock()
        let store = store(disk, clock: clock)
        await store.load(Self.alpha).value
        store.setNote("R", for: Self.alpha)
        store.setNote("Re", for: Self.alpha)
        store.setNote("Repeat plate 7", for: Self.alpha)
        await clock.until(waiting: 1, Self.delay)
        // The earlier keystrokes' waits were let go: one wait after typing, and the longest one.
        await untilWorkspace { clock.waiting(Self.delay) == 1 }
        #expect(clock.waiting(Self.delay) == 1 && clock.waiting(Self.longest) == 1)
        #expect(disk.written.isEmpty && store.hasUnsaved(Self.alpha))
        clock.fire(Self.delay)
        await untilWorkspace { !disk.written.isEmpty && !store.hasUnsaved(Self.alpha) }
        #expect(disk.written.count == 1 && disk.note(Self.alpha) == "Repeat plate 7")
        #expect(store.save(Self.alpha).isSaved)
        // The longest wait went with it.
        await untilWorkspace { clock.waiting(Self.longest) == 0 }
        #expect(clock.waiting() == 0)
    }

    @Test func typingThatGoesOnIsWrittenWithinTheLongestWait() async {
        let disk = FakeWorkspaceDisk()
        let clock = ManualClock()
        let store = store(disk, clock: clock)
        await store.load(Self.alpha).value
        for count in 1...30 { store.setNote(String(repeating: "a", count: count), for: Self.alpha) }
        await clock.until(waiting: 1, Self.longest)
        #expect(disk.written.isEmpty)
        clock.fire(Self.longest)
        await untilWorkspace { !disk.written.isEmpty }
        #expect(disk.note(Self.alpha) == String(repeating: "a", count: 30))
    }

    @Test func movingToAnotherProjectOrClosingWritesTheNoteAtOnce() async {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        let model = panel(store)
        await model.show(Self.alpha).value
        model.edit("Written on the move")
        await model.show(Self.beta).value
        // No wait fired: the move wrote it.
        await untilWorkspace { disk.note(Self.alpha) != nil }
        #expect(disk.note(Self.alpha) == "Written on the move")
        model.edit("Written on close")
        await model.close().value
        #expect(disk.note(Self.beta) == "Written on close")
        #expect(!store.hasUnsaved(Self.alpha) && !store.hasUnsaved(Self.beta))
    }

    @Test func heldWritesNeverLandOutOfOrderAndTheNewestTextWins() async {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        await store.load(Self.alpha).value
        disk.holdsWrites = true
        store.setNote("one", for: Self.alpha)
        store.flush(Self.alpha)
        await untilWorkspace { disk.heldWriteCount == 1 }
        store.setNote("one two", for: Self.alpha)
        store.flush(Self.alpha)
        store.setNote("one two three", for: Self.alpha)
        store.flush(Self.alpha)
        for _ in 0..<50 { await Task.yield() }
        // The later saves wait for the one under way: never two writes at once, so none can land after a newer one.
        #expect(disk.heldWriteCount == 1 && disk.mostWritingAtOnce == 1)
        // Let every held write go, the newest first each time, until none is left.
        for _ in 0..<10 {
            disk.releaseWrites(newestFirst: true)
            for _ in 0..<50 { await Task.yield() }
            #expect(store.record(Self.alpha)?.note == "one two three")
            #expect(store.save(Self.alpha).isSaved == !store.hasUnsaved(Self.alpha))
        }
        await untilWorkspace { !store.hasUnsaved(Self.alpha) }
        #expect(disk.note(Self.alpha) == "one two three")
        #expect(disk.mostWritingAtOnce == 1)
        #expect(store.save(Self.alpha).isSaved && store.save(Self.alpha).failure == nil)
    }

    @Test func aReadThatLandsAfterTypingNeverReplacesIt() async throws {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        await store.load(Self.alpha).value
        store.setNote("first", for: Self.alpha)
        await store.flush(Self.alpha).value
        // The panel comes to the project again: nothing is unsaved, so the file is read again (Put Back may have
        // brought an older one). The read is held while the user types.
        disk.holdsReads = true
        let reading = store.load(Self.alpha)
        await untilWorkspace { disk.heldReadCount == 1 }
        store.setNote("newer typing", for: Self.alpha)
        disk.releaseReads()
        await reading.value
        #expect(store.record(Self.alpha)?.note == "newer typing")
        await store.flush(Self.alpha).value
        #expect(disk.note(Self.alpha) == "newer typing")
    }

    @Test func aReadOfOneProjectLandingLateTouchesNoOther() async {
        let disk = FakeWorkspaceDisk()
        disk.files[Self.alpha] = try? WorkspaceRules.encode(WorkspaceRecord(projectID: Self.alpha, projectName: "Assay development",
                                                                             note: "Alpha's", updatedAt: Date()))
        let store = store(disk)
        let model = panel(store)
        disk.holdsReads = true
        let first = model.show(Self.alpha)
        await untilWorkspace { disk.heldReadCount == 1 }
        disk.holdsReads = false
        await model.show(Self.beta).value
        model.edit("Beta's")
        disk.releaseReads()
        await first.value
        await untilWorkspace { store.standing(Self.alpha) == .ready }
        #expect(model.projectID == Self.beta && model.record?.note == "Beta's")
        #expect(store.record(Self.alpha)?.note == "Alpha's")
    }

    @Test func aFailedSaveKeepsTheTextSaysSoAndRetryWritesIt() async {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        await store.load(Self.alpha).value
        disk.failsWrites = true
        store.setNote("Kept through a failure", for: Self.alpha)
        await store.flush(Self.alpha).value
        let failed = store.save(Self.alpha)
        #expect(failed.failure == "The disk is full." && !failed.isSaved)
        #expect(store.record(Self.alpha)?.note == "Kept through a failure" && store.hasUnsaved(Self.alpha))
        #expect(WorkspaceWords.unsaved(failed.failure ?? "").contains("Your note is kept here"))
        // Coming back to the project doesn't read over what isn't saved.
        await store.load(Self.alpha).value
        #expect(store.record(Self.alpha)?.note == "Kept through a failure")
        disk.failsWrites = false
        await store.retry(Self.alpha).value
        #expect(store.save(Self.alpha).isSaved && store.save(Self.alpha).failure == nil)
        #expect(disk.note(Self.alpha) == "Kept through a failure")
    }

    @Test func aNotePastTheLimitIsRefusedWholeAndSaid() async {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        await store.load(Self.alpha).value
        let full = String(repeating: "a", count: WorkspaceRules.noteLimit)
        #expect(store.setNote(full, for: Self.alpha))
        #expect(!store.setNote(full + "b", for: Self.alpha))
        #expect(store.record(Self.alpha)?.note == full)
        #expect(store.refused.contains(Self.alpha))
        await store.flush(Self.alpha).value
        #expect(disk.note(Self.alpha) == full)
        // The next change that fits is taken, and the sentence goes.
        #expect(store.setNote(String(full.dropLast()), for: Self.alpha))
        #expect(!store.refused.contains(Self.alpha))
    }

    // MARK: Files Capsid can't read

    @Test(arguments: [Data("{ not a record".utf8), Data(#"{"schema": 7, "future": true}"#.utf8)])
    func aDamagedOrNewerFileKeepsItsBytes(bytes: Data) async {
        let disk = FakeWorkspaceDisk()
        disk.files[Self.alpha] = bytes
        let store = store(disk)
        let model = panel(store)
        await model.show(Self.alpha, name: "Assay development").value
        #expect(store.standing(Self.alpha) == .damaged || store.standing(Self.alpha) == .newer)
        #expect(model.standing?.sentence != nil)
        #expect(!store.setNote("over it", for: Self.alpha))
        if case .pinned = await store.pin(sessionID: madeUpID(1), projectID: Self.alpha, row: 1, title: "x", projectName: "x") {
            Issue.record("A pin went into a file Capsid can't read")
        }
        await store.unpin(sessionID: madeUpID(1), projectID: Self.alpha)
        await store.flush(Self.alpha).value
        await model.close().value
        #expect(disk.files[Self.alpha] == bytes)
        #expect(disk.written.isEmpty)
        // Clear Workspace… is the way out, and it moves the bytes, whole, to the Trash.
        #expect(model.canClear)
        await model.clear().value
        #expect(disk.files[Self.alpha] == nil)
        #expect(store.standing(Self.alpha) == .ready && store.record(Self.alpha)?.hasContent == false)
    }

    @Test func aDamagedFileOnTheLiveDiskIsLeftByteForByte() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-workspaces-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(try #require(WorkspaceRules.fileName(for: Self.alpha)))
        let bytes = Data(#"{"schema": 3, "projectID": "proj-alpha", "note": "from a newer Capsid"}"#.utf8)
        try bytes.write(to: file)
        let store = WorkspaceStore(disk: WorkspaceFiles(folder: folder, trasher: { _ in }))
        await store.load(Self.alpha).value
        #expect(store.standing(Self.alpha) == .newer)
        store.setNote("written over?", for: Self.alpha)
        _ = await store.pin(sessionID: madeUpID(1), projectID: Self.alpha, row: 1, title: "x", projectName: "x")
        await store.flush(Self.alpha).value
        #expect(try Data(contentsOf: file) == bytes)
    }

    // MARK: Clearing

    @Test func clearWorkspaceMovesTheRecordToTheTrashAndNothingElse() async throws {
        let disk = FakeWorkspaceDisk()
        let store = store(disk)
        let model = panel(store)
        await model.show(Self.alpha, name: "Assay development").value
        model.edit("A note to clear")
        _ = await store.pin(sessionID: madeUpID(1), projectID: Self.alpha, row: 3, title: "Plate reader QC", projectName: "Assay development")
        await store.flush(Self.alpha).value
        let before = try #require(disk.files[Self.alpha])
        #expect(model.canClear)
        await model.clear().value
        #expect(model.clearProblem == nil)
        #expect(disk.files[Self.alpha] == nil && disk.trashed[Self.alpha] == before)
        #expect(store.record(Self.alpha)?.note == "" && store.record(Self.alpha)?.pins.isEmpty == true)
        #expect(store.summaries[Self.alpha] == nil && store.returnable(recency: { _ in nil }).isEmpty)
        // Nothing is written back after it.
        for _ in 0..<50 { await Task.yield() }
        #expect(disk.files[Self.alpha] == nil)
    }

    @Test func clearWithTheLiveDiskUsesTheInjectedTrasher() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-workspaces-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trashed = TrashedURLs()
        let store = WorkspaceStore(disk: WorkspaceFiles(folder: folder, trasher: { url in
            trashed.add(url)
            try FileManager.default.removeItem(at: url)
        }))
        await store.load(Self.alpha).value
        store.setNote("Clear me", for: Self.alpha)
        await store.flush(Self.alpha).value
        #expect(await store.clear(Self.alpha) == nil)
        #expect(trashed.urls.map(\.lastPathComponent) == [WorkspaceRules.fileName(for: Self.alpha)])
    }

    // MARK: The launch's read

    @Test func theLaunchReadListsTheProjectsWithAWorkspace() async throws {
        let disk = FakeWorkspaceDisk()
        disk.files[Self.alpha] = try WorkspaceRules.encode(WorkspaceRecord(projectID: Self.alpha, projectName: "Assay development",
                                                                           note: "Something", updatedAt: Date()))
        disk.files[Self.beta] = try WorkspaceRules.encode(WorkspaceRecord(projectID: Self.beta, projectName: "Plate reader QC",
                                                                          updatedAt: Date()))
        disk.files["proj-damaged"] = Data("{".utf8)
        let store = store(disk)
        store.start(after: .zero)
        for _ in 0..<200 where store.summaries.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(Set(store.summaries.keys) == [Self.alpha, Self.beta])
        // Only one with a note or a pin is offered.
        #expect(store.returnable(recency: { _ in nil }).map(\.id) == [Self.alpha])
    }
}

/// The URLs an injected trasher was handed.
final class TrashedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [URL] = []
    var urls: [URL] { lock.withLock { list } }
    func add(_ url: URL) { lock.withLock { list.append(url) } }
}
