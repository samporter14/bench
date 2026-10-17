// ShelfTransfersTests.swift — the results shelf's one queue for reads
// (ShelfTransfers), cancellation down to the page's fetch (the reader script's
// abort, run in JavaScriptCore), and its disk work off the main actor
// (ShelfTemporaryCopies, ShelfSavedFiles), on made-up sessions and files.
// Readers, clocks and disks are fakes the tests hold and let go: nothing waits
// on a clock, and nothing reaches a page, a daemon, the real pasteboard or the
// real temporary folder.
import Foundation
import JavaScriptCore
import Testing
@testable import Bench

// MARK: Made-up reads

private func list(_ n: Int) -> ArtifactRead { .list(frame: madeUpID(n)) }
private func thumb(_ n: Int) -> ArtifactRead { .thumb(version: "i-\(n)", width: 120) }
private func download(_ n: Int) -> ArtifactRead { .download(version: "v-\(n)") }

private func file(_ n: Int, size: Int = 64) -> ArtifactEntry {
    ArtifactEntry(version: "v-\(n)", artifact: nil, name: "made-up-\(n).md", mime: "text/markdown", size: size, at: nil)
}

private func picture(_ n: Int) -> ArtifactEntry {
    ArtifactEntry(version: "i-\(n)", artifact: nil, name: "plot-\(n).png", mime: "image/png", size: 64, at: nil)
}

private func session(_ n: Int) -> SessionStatus {
    SessionStatus(id: madeUpID(n), projectID: "proj_a", projectName: "Made-up A", title: "Made-up session \(n)",
                  state: .finished, updatedAt: Date(timeIntervalSince1970: 1_792_000_000 - Double(n) * 60))
}

private let webp = Data("RIFF\u{4}\0\0\0WEBPVP8L".utf8)

/// Lets the other work run until `condition` holds. No clock: the disk is
/// written off the main actor, so a fixed number of turns isn't enough.
/// A minute's limit is only a safety net for a broken run, never what a test waits for.
@MainActor
private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let limit = ContinuousClock.now + .seconds(60)
    while !condition(), ContinuousClock.now < limit { await Task.yield() }
    if !condition() { Issue.record("the condition never held", sourceLocation: sourceLocation) }
}

/// A few turns of the main actor: enough for work it already has queued to run.
@MainActor
private func turns(_ count: Int = 3) async {
    for _ in 0..<count { await Task.yield() }
}

/// Every file under a folder, as paths relative to it (none when it isn't there).
private func files(under folder: URL) -> [String] {
    let paths = (try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []
    return paths.filter { path in
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.appending(path: path).path, isDirectory: &isFolder) && !isFolder.boolValue
    }.sorted()
}

/// `Thread.isMainThread`, from anywhere.
private func onMainThread() -> Bool { Thread.isMainThread }

/// Something a callback fills in.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// MARK: Fakes

/// Stands in for the page's reader: holds each read until it is let go,
/// counts how many are under way, and records what saw cancellation and
/// which nonces the page was asked to abort.
@MainActor
private final class HeldReader {
    private struct Held {
        let read: ArtifactRead
        let continuation: CheckedContinuation<Void, Never>
    }

    var answers: [ArtifactRead: ArtifactReadOutcome] = [:]
    var hold = true
    /// A held read returns `.cancelled` as soon as its task is cancelled;
    /// otherwise it waits to be let go, cancelled or not.
    var cooperative = false
    private(set) var started: [ArtifactRead] = []
    private(set) var inFlight = 0
    private(set) var mostAtOnce = 0
    /// Held reads whose task was cancelled, in order.
    private(set) var cancelled: [ArtifactRead] = []
    /// What the page was asked to abort (`ArtifactReadAbort`).
    private(set) var aborted: [String] = []
    /// The nonce each read was last made with.
    private(set) var nonces: [ArtifactRead: String] = [:]
    private var held: [Int: Held] = [:]
    private var next = 0

    /// The reads held now, oldest first.
    var heldReads: [ArtifactRead] { held.keys.sorted().compactMap { held[$0]?.read } }

    func read(_ read: ArtifactRead, nonce: String) async -> ArtifactReadOutcome {
        started.append(read)
        nonces[read] = nonce
        inFlight += 1
        mostAtOnce = max(mostAtOnce, inFlight)
        defer { inFlight -= 1 }
        if hold {
            let id = next
            next += 1
            await withTaskCancellationHandler {
                await withCheckedContinuation { held[id] = Held(read: read, continuation: $0) }
            } onCancel: {
                Task { @MainActor [weak self] in self?.sawCancellation(id) }
            }
        }
        if cooperative, Task.isCancelled { return .cancelled }
        if let answer = answers[read] { return answer }
        switch read {
        case .list: return .list([])
        case .thumb: return .bytes(webp)
        case .text: return .unreadable
        case .download(let version): return .bytes(Data("bytes of \(version)".utf8))
        }
    }

    private func sawCancellation(_ id: Int) {
        guard let entry = held[id] else { return }
        cancelled.append(entry.read)
        if cooperative {
            held[id] = nil
            entry.continuation.resume()
        }
    }

    func abort(_ nonce: String) {
        aborted.append(nonce)
    }

    /// Lets the held reads of `read` answer.
    func release(_ read: ArtifactRead) {
        for id in held.keys.sorted() where held[id]?.read == read {
            held.removeValue(forKey: id)?.continuation.resume()
        }
    }

    /// Lets the oldest held read answer.
    func releaseOldest() {
        guard let id = held.keys.min() else { return }
        held.removeValue(forKey: id)?.continuation.resume()
    }

    func releaseAll() {
        for id in held.keys.sorted() { held.removeValue(forKey: id)?.continuation.resume() }
    }
}

/// Stands in for the clock: a time limit passes only when the test says so.
@MainActor
private final class FakeClock {
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private var next = 0
    /// Timers let go before their time (the read ended, or was dropped).
    private(set) var released = 0

    /// Timers still waiting.
    var pending: Int { waiting.count }

    func wait(_ limit: Duration) async {
        let id = next
        next += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[id] = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.letGo(id) }
        }
    }

    private func letGo(_ id: Int) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        released += 1
        continuation.resume()
    }

    /// The time limit passes for every timer waiting now.
    func pass() {
        let all = waiting
        waiting = [:]
        for id in all.keys.sorted() { all[id]?.resume() }
    }
}

/// `ShelfTransfers` over a held reader and a fake clock.
@MainActor
private final class Queue {
    final class Readiness { var ready = true }

    let reader = HeldReader()
    let clock = FakeClock()
    let readiness = Readiness()
    let transfers: ShelfTransfers

    init() {
        let reader = reader, clock = clock, readiness = readiness
        transfers = ShelfTransfers(limit: 2, read: { await reader.read($0, nonce: "") },
                                   isReady: { readiness.ready }, timeout: .seconds(30),
                                   wait: { await clock.wait($0) })
    }

    func ask(_ key: ArtifactRead, _ priority: ShelfTransfers.Priority, keepsOnClose: Bool = false,
             started: (@MainActor () -> Void)? = nil) -> Task<ShelfTransferResult, Never> {
        Task { await self.transfers.read(key, priority: priority, keepsOnClose: keepsOnClose, started: started) }
    }

    /// Lets the held reads go one at a time, oldest first, until every task is done.
    func drain(_ tasks: [Task<ShelfTransferResult, Never>]) async -> [ShelfTransferResult] {
        var results: [ShelfTransferResult] = []
        for task in tasks {
            let done = Box(false)
            let waiter = Task { _ = await task.value; done.value = true }
            await until {
                if !done.value { reader.releaseOldest() }
                return done.value
            }
            _ = await waiter.value
            results.append(await task.value)
        }
        return results
    }
}

/// The saved-file disk: what was written, recorded under a lock because the
/// writer runs off the main actor.
private final class SavedDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var threads: [Bool] = []

    func write(_ data: Data, to url: URL) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(url.path)
        threads.append(onMainThread())
    }

    func exists(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paths.contains(url.path)
    }

    var written: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    /// Whether each write ran on the main thread.
    var onMain: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return threads
    }
}

/// Blocks the thread a disk operation runs on until it is opened, as a slow
/// disk would. A thirty-second limit is only a safety net for a broken run.
private final class ThreadGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var opened = false
    private var entered = false
    private var enteredOnMain: Bool?

    func block() {
        condition.lock()
        entered = true
        enteredOnMain = onMainThread()
        let limit = Date().addingTimeInterval(30)
        while !opened, condition.wait(until: limit) {}
        condition.unlock()
    }

    func open() {
        condition.lock()
        opened = true
        condition.broadcast()
        condition.unlock()
    }

    var hasEntered: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    /// Still holding the thread it blocked.
    var isBlocking: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered && !opened
    }

    var ranOnMain: Bool? {
        condition.lock()
        defer { condition.unlock() }
        return enteredOnMain
    }
}

/// The real temporary copies, with each operation able to be held (a
/// suspension the test lets go), made to fail, or to block its thread.
private actor GatedStorage: ShelfCopyStorage {
    let real: ShelfTemporaryCopies
    private let threadGate: ThreadGate?
    private(set) var calls: [String] = []
    private var holding: Set<String> = []
    private var gates: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var failing: Set<String> = []

    init(base: URL, threadGate: ThreadGate? = nil) {
        real = ShelfTemporaryCopies(base: base)
        self.threadGate = threadGate
    }

    func hold(_ name: String) { holding.insert(name) }

    func release(_ name: String) {
        holding.remove(name)
        for gate in gates.removeValue(forKey: name) ?? [] { gate.resume() }
    }

    func fail(_ name: String) { failing.insert(name) }

    /// Operations waiting at their gate.
    func waiting(_ name: String) -> Int { gates[name]?.count ?? 0 }

    private func pass(_ name: String) async throws {
        calls.append(name)
        if holding.contains(name) { await withCheckedContinuation { gates[name, default: []].append($0) } }
        if failing.contains(name) { throw CocoaError(.fileWriteNoPermission) }
    }

    func write(_ data: Data, for entry: ArtifactEntry, run: UUID) async throws -> URL? {
        try await pass("write")
        threadGate?.block()
        return try await real.write(data, for: entry, run: run)
    }

    func exists(_ url: URL) async -> Bool {
        try? await pass("exists")
        return await real.exists(url)
    }

    func read(_ url: URL) async throws -> Data {
        try await pass("read")
        return try await real.read(url)
    }

    func remove(run: UUID) async {
        try? await pass("remove")
        await real.remove(run: run)
    }

    func removeLeftovers() async {
        try? await pass("removeLeftovers")
        await real.removeLeftovers()
    }
}

/// Waits until an operation of `storage` waits at its gate.
private func untilHeld(_ storage: GatedStorage, _ name: String) async {
    for _ in 0..<100_000 {
        if await storage.waiting(name) > 0 { return }
        await Task.yield()
    }
}

/// A results shelf over the held reader (through the page-abort path the
/// app uses), the fake clock, a scratch temporary folder and a recorded disk.
@MainActor
private final class ShelfRig {
    let reader = HeldReader()
    let clock = FakeClock()
    let saved = SavedDisk()
    let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var base: URL { scratch.appending(path: ShelfTemporaryCopies.folderName, directoryHint: .isDirectory) }
    var recent: [SessionStatus] = []
    var storage: (any ShelfCopyStorage)?
    var copied: [ShelfCopyContent] = []
    let suite = "capsid-tests-\(UUID().uuidString)"

    deinit {
        try? FileManager.default.removeItem(at: scratch)
        if let used = UserDefaults(suiteName: suite), used.persistentDomain(forName: suite) != nil {
            used.removePersistentDomain(forName: suite)
        }
    }

    func shelf(write: (@Sendable (Data, URL) throws -> Void)? = nil) -> ResultsShelf {
        let reader = reader, clock = clock, saved = saved
        return ResultsShelf(dependencies: .init(
            recent: { [unowned self] in self.recent },
            older: { _ in nil },
            read: { read in
                await ArtifactReadAbort.abortable(read, perform: { read, nonce in
                    await reader.read(read, nonce: nonce)
                }, abort: { nonce in reader.abort(nonce) })
            },
            isReady: { true },
            open: { _ in },
            write: write ?? { data, url in saved.write(data, to: url) },
            wait: { await clock.wait($0) },
            temporaryFolder: base,
            storage: storage,
            exists: { saved.exists($0) },
            defaults: UserDefaults(suiteName: suite)!,
            pasteboard: { [unowned self] content in
                self.copied.append(content)
                return true
            }))
    }
}

// MARK: The queue

@MainActor
struct ShelfTransfersTests {
    @Test func twoAtATimeAndWhatThePersonAskedForGoesFirst() async {
        let queue = Queue()
        let first = [queue.ask(thumb(1), .thumbnail), queue.ask(thumb(2), .thumbnail)]
        await until { queue.reader.inFlight == 2 }
        let later = [queue.ask(thumb(3), .thumbnail), queue.ask(list(1), .list),
                     queue.ask(download(1), .saveAll), queue.ask(download(2), .foreground)]
        await until { queue.transfers.queued == 4 }
        #expect(queue.reader.started == [thumb(1), thumb(2)])
        #expect(queue.transfers.active == 2)
        // One slot frees at a time: a preview, then Save All, a list, a thumbnail.
        for expected in 3...6 {
            queue.reader.releaseOldest()
            await until { queue.reader.started.count == expected }
            #expect(queue.reader.inFlight == 2 || expected == 6)
        }
        #expect(queue.reader.started == [thumb(1), thumb(2), download(2), download(1), list(1), thumb(3)])
        let results = await queue.drain(first + later)
        #expect(results.allSatisfy { if case .answered = $0 { true } else { false } })
        #expect(queue.reader.mostAtOnce == 2 && queue.transfers.mostActive == 2)
        #expect(queue.transfers.active == 0 && queue.transfers.queued == 0)
    }

    @Test func aReadThatHasWaitedOutEightStartsGoesNext() async {
        let queue = Queue()
        var tasks = [queue.ask(download(100), .foreground), queue.ask(download(101), .foreground)]
        await until { queue.reader.inFlight == 2 }
        tasks.append(queue.ask(thumb(1), .thumbnail))
        tasks += (102...111).map { queue.ask(download($0), .foreground) }
        await until { queue.transfers.queued == 11 }
        _ = await queue.drain(tasks)
        let order = queue.reader.started
        // Eight previews started while the thumbnail waited; then its turn came.
        #expect(Array(order.prefix(10)) == (100...109).map(download))
        #expect(order[10] == thumb(1))
        #expect(Array(order.suffix(2)) == [download(110), download(111)])
        #expect(queue.reader.mostAtOnce == 2)
    }

    @Test func oneReadForTheSameVersionAndEachAskerGetsIt() async {
        let queue = Queue()
        queue.reader.answers[download(1)] = .bytes(Data("shared".utf8))
        let started = Box<[String]>([])
        let preview = queue.ask(download(1), .foreground, started: { started.value.append("preview") })
        let saveAll = queue.ask(download(1), .saveAll, started: { started.value.append("save all") })
        await until { queue.reader.inFlight == 1 && started.value.count == 2 }
        #expect(queue.reader.started == [download(1)])
        #expect(started.value == ["preview", "save all"], "a consumer joining a running read hears it started")
        queue.reader.release(download(1))
        #expect(await preview.value == .answered(.bytes(Data("shared".utf8))))
        #expect(await saveAll.value == .answered(.bytes(Data("shared".utf8))))
        // Asked again after it ended: read again.
        queue.reader.hold = false
        #expect(await queue.ask(download(1), .foreground).value == .answered(.bytes(Data("shared".utf8))))
        #expect(queue.reader.started == [download(1), download(1)])
    }

    @Test func cancellingAQueuedAskerNeverStartsItsRead() async {
        let queue = Queue()
        let busy = [queue.ask(download(1), .foreground), queue.ask(download(2), .foreground)]
        await until { queue.reader.inFlight == 2 }
        let waiting = queue.ask(download(3), .foreground)
        await until { queue.transfers.queued == 1 }
        waiting.cancel()
        #expect(await waiting.value == .cancelled)
        #expect(queue.transfers.queued == 0)
        _ = await queue.drain(busy)
        queue.reader.hold = false
        await turns()
        #expect(!queue.reader.started.contains(download(3)), "its read never started")
        #expect(queue.reader.cancelled.isEmpty)
    }

    @Test func cancellingOneOfTwoAskersKeepsTheReadForTheOther() async {
        let queue = Queue()
        let preview = queue.ask(download(1), .foreground)
        let drag = queue.ask(download(1), .foreground)
        await until { queue.reader.inFlight == 1 && queue.transfers.running == 1 }
        preview.cancel()
        #expect(await preview.value == .cancelled)
        await turns()
        #expect(queue.reader.cancelled.isEmpty, "the drag still wants it")
        #expect(queue.transfers.running == 1)
        queue.reader.release(download(1))
        #expect(await drag.value == .answered(.bytes(Data("bytes of v-1".utf8))))
        #expect(queue.reader.started == [download(1)])
    }

    @Test func cancellingTheLastAskerCancelsTheReaderAndItsSlotIsHeldUntilItReturns() async {
        let queue = Queue()
        let first = queue.ask(download(1), .foreground)
        let second = queue.ask(download(2), .foreground)
        await until { queue.reader.inFlight == 2 }
        let third = queue.ask(download(3), .foreground)
        await until { queue.transfers.queued == 1 }
        first.cancel()
        #expect(await first.value == .cancelled, "the asker returns at once")
        await until { queue.reader.cancelled == [download(1)] }
        #expect(queue.reader.cancelled == [download(1)], "the reader's own task was cancelled")
        // The reader hasn't returned: its slot is still taken, and the third waits.
        #expect(queue.transfers.active == 2 && queue.transfers.running == 1)
        #expect(queue.transfers.queued == 1 && !queue.reader.started.contains(download(3)))
        await until { queue.clock.released == 1 }
        #expect(queue.clock.released == 1, "its timer was let go")
        queue.reader.release(download(1))
        await until { queue.reader.started.contains(download(3)) }
        #expect(queue.reader.inFlight == 2 && queue.transfers.active == 2)
        _ = await queue.drain([second, third])
        #expect(queue.reader.mostAtOnce == 2)
    }

    @Test func aCooperativeReaderFreesItsSlotAsSoonAsItStops() async {
        let queue = Queue()
        queue.reader.cooperative = true
        let first = queue.ask(download(1), .foreground)
        let second = queue.ask(download(2), .foreground)
        await until { queue.reader.inFlight == 2 }
        let third = queue.ask(download(3), .foreground)
        await until { queue.transfers.queued == 1 }
        first.cancel()
        #expect(await first.value == .cancelled)
        // The reader saw it and returned: the third starts without anyone letting the first go.
        await until { queue.reader.started.contains(download(3)) }
        #expect(queue.reader.cancelled == [download(1)])
        #expect(queue.reader.inFlight == 2)
        _ = await queue.drain([second, third])
    }

    @Test func aReadOverTheTimeLimitAnswersAtOnceAndHoldsItsSlotUntilItReturns() async {
        let queue = Queue()
        let slow = queue.ask(download(1), .foreground)
        let sharing = queue.ask(download(1), .saveAll)
        let other = queue.ask(download(2), .foreground)
        await until { queue.reader.inFlight == 2 && queue.clock.pending == 2 }
        let waiting = queue.ask(download(3), .foreground)
        await until { queue.transfers.queued == 1 }
        queue.clock.pass()
        #expect(await slow.value == .timedOut)
        #expect(await sharing.value == .timedOut)
        #expect(await other.value == .timedOut)
        await until { queue.reader.cancelled.count == 2 }
        #expect(Set(queue.reader.cancelled) == [download(1), download(2)], "both readers were cancelled, in either order")
        // Neither reader has returned: both slots are still taken.
        #expect(queue.transfers.active == 2 && queue.transfers.running == 0)
        #expect(!queue.reader.started.contains(download(3)))
        // One returns late: its answer goes nowhere, and the waiting read starts.
        queue.reader.release(download(1))
        await until { queue.reader.started.contains(download(3)) }
        #expect(queue.transfers.active == 2)
        queue.reader.release(download(2))
        queue.reader.release(download(3))
        #expect(await waiting.value == .answered(.bytes(Data("bytes of v-3".utf8))))
        #expect(queue.reader.mostAtOnce == 2)
    }

    @Test func cancellingBeforeTheStartAfterTheEndAndAtTheTimeLimit() async {
        let queue = Queue()
        // Before it starts: cancelled before its task ran, it never joins.
        let early = queue.ask(download(1), .foreground)
        early.cancel()
        #expect(await early.value == .cancelled)
        #expect(queue.reader.started.isEmpty && queue.transfers.queued == 0 && queue.transfers.active == 0)
        // After it ended: nothing changes, nothing is resumed twice.
        let done = queue.ask(download(2), .foreground)
        await until { queue.reader.inFlight == 1 }
        queue.reader.release(download(2))
        let answer = await done.value
        done.cancel()
        await turns()
        #expect(answer == .answered(.bytes(Data("bytes of v-2".utf8))))
        #expect(queue.transfers.active == 0 && queue.reader.cancelled.isEmpty)
        // At the time limit: one asker withdraws in the same turn the limit
        // passes. Each asker is answered exactly once, whichever came first.
        let leaving = queue.ask(download(3), .foreground)
        let staying = queue.ask(download(3), .foreground)
        await until { queue.reader.inFlight == 1 && queue.clock.pending == 1 }
        leaving.cancel()
        queue.clock.pass()
        let left = await leaving.value
        #expect(left == .cancelled || left == .timedOut)
        #expect(await staying.value == .timedOut)
        queue.reader.release(download(3))
        await until { queue.transfers.active == 0 }
        #expect(queue.transfers.active == 0 && queue.transfers.running == 0)
    }

    @Test func timersAreLetGoWhenTheirReadEnds() async {
        let queue = Queue()
        let read = queue.ask(download(1), .foreground)
        await until { queue.clock.pending == 1 }
        queue.reader.release(download(1))
        _ = await read.value
        await until { queue.clock.pending == 0 }
        #expect(queue.clock.pending == 0 && queue.clock.released == 1)
        // And when nobody waits any more.
        let dropped = queue.ask(download(2), .foreground)
        await until { queue.clock.pending == 1 }
        dropped.cancel()
        _ = await dropped.value
        await until { queue.clock.pending == 0 }
        #expect(queue.clock.released == 2)
        queue.reader.releaseAll()
    }

    @Test func closingLetsEveryAskerGoButASave() async {
        let queue = Queue()
        let preview = queue.ask(download(1), .foreground)
        let save = queue.ask(download(2), .foreground, keepsOnClose: true)
        await until { queue.reader.inFlight == 2 }
        let listing = queue.ask(list(1), .list)
        let saveQueued = queue.ask(download(3), .foreground, keepsOnClose: true)
        await until { queue.transfers.queued == 2 }
        queue.transfers.close()
        #expect(await preview.value == .cancelled)
        #expect(await listing.value == .cancelled)
        await until { queue.reader.cancelled == [download(1)] }
        #expect(queue.transfers.queued == 1, "a queued Save still waits its turn")
        queue.reader.release(download(1))
        await until { queue.reader.started.contains(download(3)) }
        #expect(!queue.reader.started.contains(list(1)), "the list never started")
        queue.reader.releaseAll()
        #expect(await save.value == .answered(.bytes(Data("bytes of v-2".utf8))))
        queue.reader.releaseAll()
        #expect(await saveQueued.value == .answered(.bytes(Data("bytes of v-3".utf8))))
    }

    @Test func whenThePageIsntUpNothingIsReadAndNoSlotIsTaken() async {
        let queue = Queue()
        queue.readiness.ready = false
        #expect(await queue.ask(list(1), .list).value == .notReady)
        #expect(await queue.ask(download(1), .foreground).value == .notReady)
        #expect(queue.reader.started.isEmpty && queue.transfers.active == 0 && queue.transfers.mostActive == 0)
    }

    @Test func mixedWorkAndTwoSaveAllBatchesNeverRunMoreThanTwo() async {
        let queue = Queue()
        var tasks = (1...3).map { queue.ask(list($0), .list) }
        tasks += (1...4).map { queue.ask(thumb($0), .thumbnail) }
        tasks += [queue.ask(download(1), .foreground), queue.ask(download(2), .foreground),  // two previews
                  queue.ask(download(1), .foreground),                                    // a drop of the first
                  queue.ask(download(3), .foreground),                                    // Copy
                  queue.ask(download(4), .foreground, keepsOnClose: true)]                // Save
        tasks += (10...14).map { queue.ask(download($0), .saveAll) }                       // one batch
        tasks += (20...23).map { queue.ask(download($0), .saveAll) } + [queue.ask(download(1), .saveAll)] // another
        await until { queue.transfers.queued + queue.transfers.active == 20 }
        let results = await queue.drain(tasks)
        #expect(results.count == 22)
        #expect(results.allSatisfy { if case .answered = $0 { true } else { false } }, "each asker answered once")
        #expect(queue.reader.started.count == 20, "the same version read once for its three askers")
        #expect(queue.reader.mostAtOnce == 2 && queue.transfers.mostActive == 2)
    }
}

// MARK: The shelf on the queue

@MainActor
struct ShelfCancellationTests {
    @Test func closingCancelsReadsDownToThePageAndReopenedReadsWaitForTheirSlots() async {
        let rig = ShelfRig()
        rig.recent = (1...4).map(session)
        let shelf = rig.shelf()
        shelf.open()
        await until { rig.reader.inFlight == 2 }
        let first = rig.reader.heldReads
        #expect(first == [list(1), list(2)])
        shelf.close()
        #expect(shelf.readsUnderWay == 0, "nobody waits for them")
        #expect(shelf.transfers.active == 2, "their slots stay taken until the reader returns")
        await until { rig.reader.cancelled.count == 2 && rig.reader.aborted.count == 2 && rig.clock.pending == 0 }
        #expect(Set(rig.reader.cancelled) == Set(first), "the readers' tasks were cancelled")
        #expect(Set(rig.reader.aborted) == Set(first.compactMap { rig.reader.nonces[$0] }),
                "the page was asked to abort exactly those reads, each by its own nonce")
        #expect(rig.clock.released == 2, "their timers were let go")
        // Opened again at once: the new reads wait for the old ones' slots.
        shelf.open()
        await until { shelf.transfers.queued == 4 }
        #expect(rig.reader.started.count == 2 && rig.reader.inFlight == 2)
        #expect(shelf.sessions.prefix(4).allSatisfy { $0.results == .queued })
        rig.reader.release(list(1))
        await until { rig.reader.started.count == 3 }
        #expect(rig.reader.inFlight == 2)
        rig.reader.hold = false
        rig.reader.releaseAll()
        await shelf.settled()
        await until { shelf.transfers.active == 0 }
        #expect(shelf.sessions.allSatisfy { $0.results.entries != nil })
        #expect(rig.reader.mostAtOnce == 2 && shelf.transfers.mostActive == 2)
    }

    @Test func aReaderThatStopsWhenCancelledFreesTheSlotsAtOnceAndLandsNowhere() async {
        let rig = ShelfRig()
        rig.recent = (1...4).map(session)
        rig.reader.cooperative = true
        let shelf = rig.shelf()
        shelf.open()
        await until { rig.reader.inFlight == 2 }
        shelf.close()
        await until { shelf.transfers.active == 0 }
        #expect(rig.reader.inFlight == 0 && Set(rig.reader.cancelled) == [list(1), list(2)])
        #expect(rig.reader.started.count == 2, "what was waiting never started")
        #expect(shelf.sessions.allSatisfy { $0.results == .notLoaded })
    }

    @Test func aLateAnswerAfterClosingWritesNoCopyAndReopeningStartsAFreshRun() async throws {
        let rig = ShelfRig()
        let shelf = rig.shelf()
        let preview = Task { await shelf.prepareQuickLook(file(1)) }
        await until { rig.reader.inFlight == 1 }
        #expect(shelf.preparing == ["v-1"])
        shelf.close()
        #expect(await preview.value == nil)
        #expect(shelf.preparing.isEmpty && shelf.fileProblems.isEmpty)
        // The page answers after all: nothing lands.
        rig.reader.release(download(1))
        await until { shelf.transfers.active == 0 }
        await shelf.settled()
        #expect(files(under: rig.base).isEmpty)
        #expect(shelf.cachedCopy("v-1") == nil)
        // Opened again: a new run, which closing takes away too.
        rig.reader.hold = false
        shelf.open()
        let url = try #require(await shelf.prepareQuickLook(file(1)))
        #expect(files(under: rig.base).count == 1 && FileManager.default.fileExists(atPath: url.path))
        shelf.close()
        await shelf.settled()
        #expect(files(under: rig.base).isEmpty)
    }

    @Test func everythingTheShelfDoesAtOnceRunsTwoReadsAtMostAcrossCloseAndReopen() async throws {
        let rig = ShelfRig()
        rig.recent = (1...3).map(session)
        let entries = (1...6).map { file($0) } + (1...4).map(picture)
        rig.reader.answers[list(1)] = .list(entries)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        let shelf = rig.shelf()
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        rig.reader.hold = true
        for image in (1...4).map(picture) { shelf.wantThumbnail(image) }
        let preview = Task { await shelf.prepareQuickLook(file(1)) }
        let drop = Task { await shelf.exportForDrag(file(2)) }
        let copy = Task { await shelf.copy(file(3)) }
        let save = Task { await shelf.save(file(4), to: out.appending(path: "made-up-4.md")) }
        shelf.saveAll(madeUpID(1), into: out)
        await until { rig.reader.inFlight == 2 }
        // Some of it answers, then the window closes and opens again with more.
        for _ in 0..<3 {
            let count = rig.reader.started.count
            rig.reader.releaseOldest()
            await until { rig.reader.started.count > count || rig.reader.heldReads.count < 2 }
        }
        shelf.close()
        shelf.open(refresh: true)
        for image in (1...4).map(picture) { shelf.wantThumbnail(image) }
        let again = Task { await shelf.prepareQuickLook(file(5)) }
        await until { rig.reader.inFlight == 2 }
        // Let everything go: still two at a time.
        rig.reader.hold = false
        rig.reader.releaseAll()
        await shelf.settled()
        _ = await (preview.value, drop.value, copy.value, again.value)
        #expect(await save.value == .saved(out.appending(path: "made-up-4.md")), "a Save goes on through the close")
        // A second Save All after the close, while nothing else runs.
        shelf.saveAll(madeUpID(1), into: out)
        await shelf.settled()
        await until { shelf.transfers.active == 0 }
        #expect(rig.reader.mostAtOnce == 2)
        #expect(shelf.transfers.mostActive == 2 && shelf.transfers.active == 0 && shelf.transfers.queued == 0)
    }
}

// MARK: Quick Look's want of a file

@MainActor
struct ShelfPreviewDemandTests {
    @Test func movingQuicklyThroughFilesStartsOnlyTheLastOne() async throws {
        let rig = ShelfRig()
        let shelf = rig.shelf()
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        // Two saves take both slots.
        let saves = [Task { await shelf.save(file(1), to: out.appending(path: "1.md")) },
                     Task { await shelf.save(file(2), to: out.appending(path: "2.md")) }]
        await until { rig.reader.inFlight == 2 }
        let demand = ShelfPreviewDemand(shelf: shelf)
        let shown = Box<[String: URL?]>([:])
        for n in 3...5 {
            demand.want(file(n), pressed: false) { shown.value["v-\(n)"] = $0 }
            // Its download is queued (and the last one's let go) before the panel moves on.
            await until { shelf.transfers.waiting(for: download(n)) == 1 && shelf.preparing == ["v-\(n)"] }
        }
        await until { shelf.transfers.queued == 1 && shelf.preparing == ["v-5"] }
        #expect(demand.version == "v-5")
        #expect(shelf.preparing == ["v-5"], "the files left show no spinner")
        rig.reader.hold = false
        rig.reader.releaseAll()
        await until { shown.value["v-5"] != nil }
        #expect(rig.reader.started.filter { if case .download = $0 { true } else { false } }
                == [download(1), download(2), download(5)], "the files passed over were never downloaded")
        #expect(shown.value.keys.sorted() == ["v-5"], "nothing is called back for a file withdrawn")
        let url = try #require(shown.value["v-5"] ?? nil)
        #expect(shelf.cachedCopy("v-5") == url)
        for save in saves { _ = await save.value }
    }

    @Test func leavingAFileStopsItsDownloadUnlessSomethingElseWantsIt() async throws {
        let rig = ShelfRig()
        let shelf = rig.shelf()
        let demand = ShelfPreviewDemand(shelf: shelf)
        demand.want(file(6), pressed: false) { _ in }
        await until { rig.reader.inFlight == 1 }
        demand.want(file(7), pressed: false) { _ in }
        await until { rig.reader.cancelled == [download(6)] && rig.reader.aborted.count == 1 }
        #expect(rig.reader.aborted == [rig.reader.nonces[download(6)]].compactMap { $0 }, "the page is asked to stop it")
        // A drop wants file 8 as well: leaving it in the panel doesn't stop it.
        rig.reader.release(download(6))
        rig.reader.release(download(7))
        let drop = Task { await shelf.exportForDrag(file(8)) }
        await until { rig.reader.heldReads == [download(8)] }
        demand.want(file(8), pressed: false) { _ in }
        await until { shelf.transfers.waiting(for: download(8)) == 2 }
        demand.want(file(9), pressed: false) { _ in }
        await until { rig.reader.heldReads.contains(download(9)) && shelf.transfers.waiting(for: download(8)) == 1 }
        await turns()
        #expect(!rig.reader.cancelled.contains(download(8)), "the drop still wants it")
        rig.reader.hold = false
        rig.reader.releaseAll()
        let dropped = try #require(await drop.value)
        #expect(FileManager.default.fileExists(atPath: dropped.path))
        demand.withdraw()
    }

    @Test func goingBackToAFileWhoseWantWasJustWithdrawnStillLoadsIt() async throws {
        let rig = ShelfRig()
        let shelf = rig.shelf()
        let demand = ShelfPreviewDemand(shelf: shelf)
        let shown = Box<URL?>(nil)
        demand.want(file(1), pressed: false) { _ in }
        await until { rig.reader.inFlight == 1 }
        // A, B and back to A in one turn: A's old want goes, the new one stays.
        demand.want(file(2), pressed: false) { _ in }
        demand.want(file(1), pressed: false) { shown.value = $0 }
        await until { rig.reader.cancelled.contains(download(1)) }
        rig.reader.hold = false
        rig.reader.releaseAll()
        await until { shown.value != nil }
        let url = try #require(shown.value)
        #expect(shelf.cachedCopy("v-1") == url)
        #expect(!rig.reader.started.contains(download(2)), "B was left before its download began")
        #expect(rig.reader.started == [download(1), download(1)], "A's dropped read, then A again")
    }
}

// MARK: The disk, off the main actor

@MainActor
struct ShelfDiskTests {
    @Test func aCopyWhoseDiskIsStuckLeavesTheMainActorFree() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let gate = ThreadGate()
        rig.storage = GatedStorage(base: rig.base, threadGate: gate)
        let shelf = rig.shelf()
        let preview = Task { await shelf.prepareQuickLook(file(1)) }
        await until { gate.hasEntered }
        // The write holds its thread; the main actor still runs other work.
        let callback = await Task { @MainActor in "ran" }.value
        #expect(callback == "ran" && gate.isBlocking)
        #expect(gate.ranOnMain == false)
        #expect(shelf.preparing == ["v-1"] && shelf.cachedCopy("v-1") == nil, "Quick Look sees no copy until it is whole")
        gate.open()
        let url = try #require(await preview.value)
        #expect(shelf.cachedCopy("v-1") == url)
        #expect(try Data(contentsOf: url) == Data("bytes of v-1".utf8))
    }

    @Test func aSavedFileIsWrittenOffTheMainThreadAndAStuckOneLeavesTheMainActorFree() async {
        let rig = ShelfRig()
        rig.reader.hold = false
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            gate.block()
            saved.write(data, to: url)
        })
        let url = rig.scratch.appending(path: "Out/made-up-1.md")
        let save = Task { await shelf.save(file(1), to: url) }
        await until { gate.hasEntered }
        let callback = await Task { @MainActor in "ran" }.value
        #expect(callback == "ran" && gate.isBlocking)
        #expect(shelf.saving == ["v-1"])
        gate.open()
        #expect(await save.value == .saved(url))
        #expect(gate.ranOnMain == false && rig.saved.onMain == [false])
    }

    @Test func closingWhileACopyIsBeingWrittenLeavesNoCopyAndNoFolder() async {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        await storage.hold("write")
        let shelf = rig.shelf()
        let preview = Task { await shelf.prepareQuickLook(file(1)) }
        await untilHeld(storage, "write")
        shelf.close()
        await storage.release("write")
        #expect(await preview.value == nil)
        await shelf.settled()
        #expect(files(under: rig.base).isEmpty, "the late write was dropped")
        #expect(shelf.cachedCopy("v-1") == nil && shelf.fileProblems.isEmpty)
        #expect(await storage.calls.contains("remove"))
    }

    @Test func openingAndClosingQuicklyLeavesOnlyTheOpenRunsCopies() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        let shelf = rig.shelf()
        _ = try #require(await shelf.prepareQuickLook(file(1)))
        shelf.close()
        shelf.open()
        await storage.hold("write")
        let held = Task { await shelf.prepareQuickLook(file(2)) }
        await untilHeld(storage, "write")
        shelf.close()
        shelf.open()
        await storage.release("write")
        #expect(await held.value == nil)
        let kept = try #require(await shelf.prepareQuickLook(file(3)))
        await shelf.settled()
        #expect(files(under: rig.base) == [kept.path.replacingOccurrences(of: rig.base.path + "/", with: "")])
        // 0700 folders, 0600 file.
        let attributes = { (url: URL) in (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int }
        #expect(attributes(kept) == 0o600)
        #expect([kept.deletingLastPathComponent(), kept.deletingLastPathComponent().deletingLastPathComponent(), rig.base]
            .map(attributes) == [0o700, 0o700, 0o700])
        shelf.close()
        await shelf.settled()
        #expect(files(under: rig.base).isEmpty)
    }

    @Test func aCopyThatCantBeWrittenSaysSoAndCopyFallsBackWhenItCantBeRead() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        let shelf = rig.shelf()
        await storage.fail("write")
        #expect(await shelf.prepareQuickLook(file(1)) == nil)
        #expect(shelf.fileProblems["v-1"]?.hasPrefix("Couldn't make a temporary copy:") == true)
        #expect(shelf.preparing.isEmpty && shelf.cachedCopy("v-1") == nil)
        // A copy that can't be read back: Copy downloads the file instead.
        let fresh = GatedStorage(base: rig.base)
        rig.storage = fresh
        let other = rig.shelf()
        _ = try #require(await other.prepareQuickLook(file(2)))
        await fresh.fail("read")
        #expect(await other.copy(file(2)))
        #expect(rig.copied == [.text("bytes of v-2")])
        #expect(rig.reader.started.filter { $0 == download(2) }.count == 2)
        #expect(other.cachedCopy("v-2") == nil, "a copy that can't be read isn't offered to Quick Look")
    }

    @Test func copyReadsThePreviewsCopyOffTheMainActorWithoutADownload() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        let shelf = rig.shelf()
        _ = try #require(await shelf.prepareQuickLook(file(1)))
        #expect(await shelf.copy(file(1)))
        #expect(rig.copied == [.text("bytes of v-1")])
        #expect(await storage.calls == ["write", "read"])
        #expect(rig.reader.started == [download(1)])
    }

    @Test func aCopyTheSystemCleanedAwayIsFetchedAgain() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let shelf = rig.shelf()
        let url = try #require(await shelf.prepareQuickLook(file(1)))
        try FileManager.default.removeItem(at: url)
        #expect(shelf.cachedCopy("v-1") == url, "Quick Look's answer on the main thread reads no disk")
        let again = try #require(await shelf.prepareQuickLook(file(1)))
        #expect(again == url && FileManager.default.fileExists(atPath: again.path))
        #expect(rig.reader.started == [download(1), download(1)])
    }

    @Test func launchCleanupGoesFirstAndNeverTakesTheNewRunsCopy() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        // A run that never closed, from an earlier launch.
        let stray = rig.base.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stray.appending(path: "old.md"))
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        await storage.hold("removeLeftovers")
        let shelf = rig.shelf()
        shelf.cleanUpAtLaunch()
        let preview = Task { await shelf.prepareQuickLook(file(1)) }
        await until { rig.reader.started == [download(1)] && rig.reader.inFlight == 0 }
        await turns(5)
        #expect(await storage.calls == ["removeLeftovers"], "the copy waits for the cleanup")
        #expect(shelf.preparing == ["v-1"])
        await storage.release("removeLeftovers")
        let url = try #require(await preview.value)
        #expect(await storage.calls == ["removeLeftovers", "write"])
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Cleaning up again while this run is open leaves its copy.
        shelf.cleanUpAtLaunch()
        await shelf.settled()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: Telling the page to stop

@MainActor
private final class AbortRecord {
    var performed: [String] = []
    var aborted: [String] = []
    var gate: CheckedContinuation<Void, Never>?
}

@MainActor
struct ArtifactReadAbortTests {
    @Test func aCancelledReadAsksThePageToAbortItByItsOwnNonce() async {
        let record = AbortRecord()
        let task = Task {
            await ArtifactReadAbort.abortable(.download(version: "v-1"), nonce: "nonce-1", perform: { _, nonce in
                record.performed.append(nonce)
                await withCheckedContinuation { record.gate = $0 }
                return .cancelled
            }, abort: { record.aborted.append($0) })
        }
        await until { record.gate != nil }
        task.cancel()
        await until { record.aborted == ["nonce-1"] }
        #expect(record.performed == ["nonce-1"] && record.aborted == ["nonce-1"])
        // Swift's cancellation is no proof the fetch stopped: the read still ends when the page answers.
        record.gate?.resume()
        #expect(await task.value == .cancelled)
    }

    @Test func aReadNobodyCancelsIsNeverAbortedAndOneCancelledFirstIsNeverMade() async {
        let record = AbortRecord()
        let outcome = await ArtifactReadAbort.abortable(.list(frame: madeUpID(1)), perform: { _, nonce in
            record.performed.append(nonce)
            return .list([])
        }, abort: { record.aborted.append($0) })
        #expect(outcome == .list([]))
        #expect(record.performed.count == 1 && record.aborted.isEmpty)
        #expect(record.performed[0].range(of: #"^[a-z0-9-]{36}$"#, options: .regularExpression) != nil)
        let early = Task {
            await ArtifactReadAbort.abortable(.list(frame: madeUpID(1)), perform: { _, nonce in
                record.performed.append(nonce)
                return .list([])
            }, abort: { record.aborted.append($0) })
        }
        early.cancel()
        #expect(await early.value == .cancelled)
        #expect(record.performed.count == 1)
    }

    @Test func thePagesCancelledAnswerIsItsOwnOutcomeForEveryRead() {
        let answer = Data(#"{"outcome":"cancelled"}"#.utf8)
        for read in [list(1), thumb(1), ArtifactRead.text(version: "v-1"), download(1)] {
            #expect(ArtifactReaderScript.outcome(of: answer, for: read) == .cancelled)
        }
        #expect(ShelfFailure(.cancelled) == .unreadable, "never shown as a failure: the shelf drops it first")
    }
}

// MARK: The abort in the page (JavaScriptCore)

/// `ArtifactReaderScript.body` and `.abort` in JavaScriptCore, with an
/// AbortController, `AbortSignal.timeout` (and `AbortSignal.any` when asked
/// for) and a `fetch` that answers only when the test says so and rejects
/// when its signal aborts, as WebKit's does.
private final class AbortPage {
    private let script: PageScript

    init(any: Bool) {
        script = PageScript(Self.fake + (any ? Self.anySignal : ""))
    }

    private static let fake = """
    var __results = {};
    var __pending = {};
    var __deadlines = [];
    var __bodies = [];
    var __anyCalls = 0;
    var __aborted = null;
    var document = { cookie: "" };
    function __Signal() { this.aborted = false; this.listeners = []; }
    __Signal.prototype.addEventListener = function (type, listener) { if (type === "abort") { this.listeners.push(listener); } };
    __Signal.prototype.fire = function () {
        if (this.aborted) { return; }
        this.aborted = true;
        var all = this.listeners;
        this.listeners = [];
        for (var i = 0; i < all.length; i++) { all[i](); }
    };
    var AbortController = function () { this.signal = new __Signal(); };
    AbortController.prototype.abort = function () { this.signal.fire(); };
    var AbortSignal = function () {};
    AbortSignal.timeout = function (ms) { var s = new __Signal(); s.ms = ms; __deadlines.push(s); return s; };
    var fetch = function (path, init) {
        var signal = init && init.signal;
        return new Promise(function (resolve, reject) {
            var abort = function () { reject(new Error("AbortError")); };
            if (signal) { if (signal.aborted) { abort(); return; } signal.addEventListener("abort", abort); }
            __pending[path] = { resolve: resolve, signal: signal };
        });
    };
    function __answer(path, text, holdBody) {
        var p = __pending[path];
        delete __pending[path];
        var bytes = new Uint8Array(text.length);
        for (var i = 0; i < text.length; i++) { bytes[i] = text.charCodeAt(i); }
        var sent = false;
        var reader = {
            read: function () {
                if (sent) { return Promise.resolve({ done: true, value: undefined }); }
                if (!holdBody) { sent = true; return Promise.resolve({ done: false, value: bytes }); }
                return new Promise(function (resolve, reject) {
                    __bodies.push(function () { sent = true; resolve({ done: false, value: bytes }); });
                    if (p.signal) { p.signal.addEventListener("abort", function () { reject(new Error("AbortError")); }); }
                });
            },
            cancel: function () { return Promise.resolve(); }
        };
        p.resolve({ status: 200, ok: true, headers: { get: function () { return null; } },
                    body: { getReader: function () { return reader; }, cancel: function () { return Promise.resolve(); } },
                    text: function () { return Promise.resolve(text); } });
    }
    """

    private static let anySignal = """

    AbortSignal.any = function (signals) {
        __anyCalls += 1;
        var either = new __Signal();
        for (var i = 0; i < signals.length; i++) {
            if (signals[i].aborted) { either.fire(); }
            else { signals[i].addEventListener("abort", function () { either.fire(); }); }
        }
        return either;
    };
    """

    /// Starts a read as `callAsyncJavaScript` would, its answer kept under `label`.
    func start(_ read: ArtifactRead, nonce: String?, label: String) {
        var arguments = read.arguments
        arguments["nonce"] = nonce ?? NSNull()
        let data = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        script.set("__args", String(decoding: data, as: UTF8.self))
        script.set("__label", label)
        script.evaluate("""
        (function (a, label) {
            __results[label] = null;
            return (async function (op, frameId, versionId, width, nonce) {
            \(ArtifactReaderScript.body)
            })(a.op, a.frameId, a.versionId, a.width, a.nonce)
                .then(function (v) { __results[label] = v; }, function (e) { __results[label] = "threw: " + e; });
        })(JSON.parse(__args), __label);
        """)
        #expect(script.exception == nil)
    }

    func result(_ label: String) -> String? {
        script.evaluate("__results[\(Self.quoted(label))]")
    }

    /// Runs the abort script as the shelf does; "true" when there was such a read.
    func abort(_ nonce: String) -> String? {
        script.set("__nonce", nonce)
        script.evaluate("""
        __aborted = null;
        (async function (nonce) {
        \(ArtifactReaderScript.abort)
        })(__nonce).then(function (v) { __aborted = String(v); });
        """)
        #expect(script.exception == nil)
        return script.evaluate("__aborted")
    }

    /// The nonces filed in the page's map now.
    var filed: [String] {
        let json = script.evaluate("JSON.stringify(Object.keys(globalThis.\(ArtifactReaderScript.readsName) || {}).sort())") ?? "[]"
        return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    func answer(_ path: String, _ text: String, holdBody: Bool = false) {
        script.set("__path", path)
        script.set("__text", text)
        script.evaluate("__answer(__path, __text, \(holdBody));")
        #expect(script.exception == nil)
    }

    func passDeadline(_ index: Int) {
        script.evaluate("__deadlines[\(index)].fire();")
    }

    var deadlines: [Int] {
        let json = script.evaluate("JSON.stringify(__deadlines.map(function (s) { return s.ms; }))") ?? "[]"
        return (try? JSONDecoder().decode([Int].self, from: Data(json.utf8))) ?? []
    }

    var anyCalls: Int { Int(script.evaluate("__anyCalls") ?? "") ?? -1 }

    var objectPrototypeIsClean: Bool { script.evaluate("String(typeof Object.prototype.abort)") == "undefined" }

    private static func quoted(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]), as: UTF8.self)
    }
}

struct ArtifactAbortScriptTests {
    private func outcome(_ raw: String?, _ read: ArtifactRead) -> ArtifactReadOutcome? {
        raw.map { ArtifactReaderScript.outcome(of: Data($0.utf8), for: read) }
    }

    @Test(arguments: [true, false])
    func anAbortStopsThatReadAloneAndEveryReadTakesItsEntryOut(any: Bool) {
        let page = AbortPage(any: any)
        page.start(download(1), nonce: "nonce-a", label: "a")
        page.start(list(1), nonce: "nonce-b", label: "b")
        #expect(page.filed == ["nonce-a", "nonce-b"])
        #expect(page.deadlines == [20000, 10000], "the 20 s and 10 s deadlines still hold")
        #expect(page.anyCalls == (any ? 2 : 0))
        #expect(page.result("a") == nil && page.result("b") == nil)
        #expect(page.abort("nonce-a") == "true")
        #expect(outcome(page.result("a"), download(1)) == .cancelled, "aborted mid-fetch: cancelled, not unreadable")
        #expect(page.filed == ["nonce-b"], "its entry is gone; the other read's stays")
        #expect(page.result("b") == nil, "the other read goes on")
        // The other answers normally and takes its own entry out.
        page.answer("/api/frames/\(madeUpID(1))/artifacts", "[]")
        #expect(outcome(page.result("b"), list(1)) == .list([]))
        #expect(page.filed.isEmpty)
    }

    @Test(arguments: [true, false])
    func anAbortWhileTheBodyIsReadIsCancelledToo(any: Bool) {
        let page = AbortPage(any: any)
        page.start(download(1), nonce: "nonce-a", label: "a")
        page.answer("/api/artifacts/versions/v-1", "made-up bytes", holdBody: true)
        #expect(page.result("a") == nil && page.filed == ["nonce-a"])
        #expect(page.abort("nonce-a") == "true")
        #expect(outcome(page.result("a"), download(1)) == .cancelled)
        #expect(page.filed.isEmpty)
    }

    @Test func abortingAReadThatIsntThereDoesNothing() {
        let page = AbortPage(any: true)
        #expect(page.abort("nonce-unknown") == "false", "no read filed at all")
        page.start(download(1), nonce: "nonce-a", label: "a")
        #expect(page.abort("nonce-other") == "false")
        #expect(page.filed == ["nonce-a"] && page.result("a") == nil)
        page.answer("/api/artifacts/versions/v-1", "made-up bytes")
        #expect(outcome(page.result("a"), download(1)) == .bytes(Data("made-up bytes".utf8)))
        #expect(page.filed.isEmpty)
        #expect(page.abort("nonce-a") == "false", "a read that ended is let be")
    }

    @Test(arguments: [true, false])
    func theDeadlineStillStopsAReadAndThatIsUnreadable(any: Bool) {
        let page = AbortPage(any: any)
        page.start(download(1), nonce: "nonce-a", label: "a")
        page.passDeadline(0)
        #expect(outcome(page.result("a"), download(1)) == .unreadable, "a deadline is a failure, not a cancellation")
        #expect(page.filed.isEmpty)
    }

    @Test func thePhonesReadsCarryNoNonceAndFileNothing() {
        let page = AbortPage(any: true)
        page.start(download(1), nonce: nil, label: "a")
        #expect(page.filed.isEmpty)
        #expect(page.deadlines == [20000] && page.anyCalls == 0, "its fetch has only the deadline")
        #expect(page.abort("nonce-a") == "false")
        page.answer("/api/artifacts/versions/v-1", "made-up bytes")
        #expect(outcome(page.result("a"), download(1)) == .bytes(Data("made-up bytes".utf8)))
        // A nonce of the wrong shape is no nonce.
        page.start(download(2), nonce: "../not-a-nonce", label: "b")
        #expect(page.filed.isEmpty)
        page.answer("/api/artifacts/versions/v-2", "x")
        #expect(outcome(page.result("b"), download(2)) == .bytes(Data("x".utf8)))
    }

    @Test func aNonceNamedLikeAnObjectsOwnKeyIsJustANonce() {
        let page = AbortPage(any: false)
        page.start(download(1), nonce: "constructor", label: "a")
        #expect(page.filed == ["constructor"])
        #expect(page.abort("constructor") == "true")
        #expect(outcome(page.result("a"), download(1)) == .cancelled)
        #expect(page.filed.isEmpty && page.objectPrototypeIsClean)
        #expect(page.abort("toString") == "false")
    }
}
