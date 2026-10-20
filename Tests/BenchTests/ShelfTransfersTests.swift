// ShelfTransfersTests.swift — the results shelf's one queue for reads
// (ShelfTransfers) and the time limit on each, cancellation down to the page's
// fetch (the reader script's abort, run in JavaScriptCore), and its disk work
// off the main actor (ShelfTemporaryCopies, ShelfSavedFiles, with its time
// limit and the folder that stops answering), on made-up sessions and files.
// A seeded fuzz of both limits closes the file.
// Readers, clocks and disks are fakes the tests hold and let go: nothing waits
// on a clock, and nothing reaches a page, a daemon, the real pasteboard or the
// real temporary folder. Also here: a window closed and opened again while the
// old run's work is still unwinding, which must leave the new run's alone.
import Combine
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
private func until(_ condition: () -> Bool, within net: Duration = .seconds(60),
                   sourceLocation: SourceLocation = #_sourceLocation) async {
    let limit = ContinuousClock.now + net
    while !condition(), ContinuousClock.now < limit { await Task.yield() }
    if !condition() { Issue.record("the condition never held", sourceLocation: sourceLocation) }
}

/// A task's value. A result that never comes is a failure after 20 seconds
/// (an issue, and nil), not a test that hangs: callers ask only once what
/// settles it has happened.
@MainActor
private func finished<T: Sendable>(_ task: Task<T, Never>, sourceLocation: SourceLocation = #_sourceLocation) async -> T? {
    let box = Box<[T]>([])
    Task { box.value = [await task.value] }
    await until({ !box.value.isEmpty }, within: .seconds(20), sourceLocation: sourceLocation)
    return box.value.first
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
    /// How long each timer was asked to wait, in the order they were set.
    private(set) var asked: [Duration] = []

    func wait(_ limit: Duration) async {
        let id = next
        next += 1
        asked.append(limit)
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

    /// The time limit passes for the `index`th timer waiting now (oldest first).
    func pass(nth index: Int) {
        let ids = waiting.keys.sorted()
        guard ids.indices.contains(index), let continuation = waiting.removeValue(forKey: ids[index]) else { return }
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

    /// The names of what was written to a folder, as a listing of it would give them.
    func names(in folder: URL) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths.filter { ($0 as NSString).deletingLastPathComponent == folder.path }
            .map { ($0 as NSString).lastPathComponent }
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

/// Waits until `count` operations of `storage` wait at its gate. Like `until`,
/// a minute's limit is only a safety net: how long the work takes depends on
/// how busy the other tests keep the machine.
private func untilHeld(_ storage: GatedStorage, _ name: String, count: Int = 1) async {
    let limit = ContinuousClock.now + .seconds(60)
    while ContinuousClock.now < limit {
        if await storage.waiting(name) >= count { return }
        await Task.yield()
    }
}

/// A results shelf over the held reader (through the page-abort path the
/// app uses), the fake clock, a scratch temporary folder and a recorded disk.
@MainActor
private final class ShelfRig {
    let reader = HeldReader()
    let clock = FakeClock()
    /// The saved-file writer's time limits, apart from the reads'.
    let writeClock = FakeClock()
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

    /// The writer the shelf saves through: real threads, a fake clock.
    private(set) lazy var writer = ShelfSavedFiles(wait: { [writeClock] in await writeClock.wait($0) })
    /// Files the shelf told the panel it saved.
    var didSave: [URL] = []

    /// `exists` and `list` stand in for the disk's own looks (default: the recorded disk's).
    func shelf(write: (@Sendable (Data, URL) throws -> Void)? = nil,
               exists: (@Sendable (URL) -> Bool)? = nil,
               list: (@Sendable (URL) throws -> [String]?)? = nil) -> ResultsShelf {
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
            didSave: { [unowned self] url in self.didSave.append(url) },
            write: write ?? { data, url in saved.write(data, to: url) },
            savedFiles: writer,
            wait: { await clock.wait($0) },
            temporaryFolder: base,
            storage: storage,
            exists: exists ?? { saved.exists($0) },
            list: list ?? { saved.names(in: $0) },
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
        await turns(10)
        #expect(queue.clock.released == 0 && queue.clock.pending == 2, "its deadline still stands, to free the slot of a reader that never returns")
        queue.reader.release(download(1))
        await until { queue.reader.started.contains(download(3)) }
        #expect(queue.clock.released == 1, "and goes when the reader returns")
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

    @Test func aReadOverTheTimeLimitAnswersAtOnceAndFreesItsSlotWhetherOrNotItsReaderReturns() async {
        let queue = Queue()
        let slow = queue.ask(download(1), .foreground)
        let sharing = queue.ask(download(1), .saveAll)
        let other = queue.ask(download(2), .foreground)
        await until { queue.reader.inFlight == 2 && queue.clock.pending == 2 }
        let waiting = queue.ask(download(3), .foreground)
        await until { queue.transfers.queued == 1 }
        queue.clock.pass()
        #expect(await finished(slow) == .timedOut)
        #expect(await finished(sharing) == .timedOut)
        #expect(await finished(other) == .timedOut)
        await until { queue.reader.cancelled.count == 2 }
        #expect(Set(queue.reader.cancelled) == [download(1), download(2)], "both readers were cancelled, in either order")
        // Neither reader has returned, and both slots are free: the waiting read starts.
        await until { queue.reader.started.contains(download(3)) }
        #expect(queue.transfers.lost == 2 && queue.transfers.active == 1 && queue.transfers.queued == 0)
        #expect(queue.transfers.running == 1)
        // The late answers go nowhere, and take no slot with them.
        queue.reader.release(download(1))
        queue.reader.release(download(2))
        await until { queue.transfers.lost == 0 }
        #expect(queue.transfers.active == 1, "the waiting read still holds its own slot")
        queue.reader.release(download(3))
        #expect(await finished(waiting) == .answered(.bytes(Data("bytes of v-3".utf8))))
        await until { queue.transfers.active == 0 }
        #expect(queue.reader.started == [download(1), download(2), download(3)], "nothing was read twice")
    }

    @Test func readersThatNeverReturnCostNoSlotAndTheQueueKeepsWorking() async {
        let queue = Queue()
        let stuck = [queue.ask(download(1), .foreground), queue.ask(download(2), .foreground)]
        await until { queue.reader.inFlight == 2 && queue.clock.pending == 2 }
        let third = queue.ask(download(3), .foreground)
        let fourth = queue.ask(download(4), .foreground)
        await until { queue.transfers.queued == 2 }
        // Two reads wait in line behind two slots nothing will ever give back.
        queue.clock.pass()
        for task in stuck { #expect(await finished(task) == .timedOut) }
        // Neither stuck reader is ever let go; the next two read all the same.
        await until { queue.reader.started.count == 4 }
        #expect(queue.transfers.lost == 2 && queue.transfers.active == 2)
        queue.reader.release(download(3))
        queue.reader.release(download(4))
        #expect(await finished(third) == .answered(.bytes(Data("bytes of v-3".utf8))))
        #expect(await finished(fourth) == .answered(.bytes(Data("bytes of v-4".utf8))))
        // And a fifth, with the two stuck readers still out.
        let fifth = queue.ask(download(5), .foreground)
        await until { queue.reader.started.count == 5 }
        queue.reader.release(download(5))
        #expect(await finished(fifth) == .answered(.bytes(Data("bytes of v-5".utf8))))
        #expect(queue.transfers.lost == 2 && queue.transfers.active == 0)
        // A stuck reader that comes back at last is forgotten, once.
        queue.reader.releaseAll()
        await until { queue.transfers.lost == 0 }
        #expect(queue.transfers.active == 0 && queue.transfers.queued == 0 && queue.clock.pending == 0)
    }

    @Test func aStuckReaderIsGivenUpOnEvenWhenNobodyWaitsForItAnyMore() async {
        let queue = Queue()
        let first = queue.ask(download(1), .foreground)
        let second = queue.ask(download(2), .foreground)
        await until { queue.reader.inFlight == 2 && queue.clock.pending == 2 }
        // A Save waits in line through the close.
        let waiting = queue.ask(download(3), .foreground, keepsOnClose: true)
        await until { queue.transfers.queued == 1 }
        // Both askers leave (the window closed, say), and neither reader answers the cancellation.
        queue.transfers.close()
        #expect(await finished(first) == .cancelled)
        #expect(await finished(second) == .cancelled)
        await until { queue.reader.cancelled.count == 2 }
        #expect(queue.transfers.active == 2 && queue.transfers.lost == 0, "their slots stay taken within the limit")
        #expect(queue.clock.pending == 2 && queue.clock.released == 0, "their deadlines still stand")
        // The limit passes with nobody waiting: the slots are freed all the same.
        queue.clock.pass()
        await until { queue.reader.started.contains(download(3)) }
        #expect(queue.transfers.lost == 2 && queue.transfers.active == 1)
        queue.reader.release(download(3))
        #expect(await finished(waiting) == .answered(.bytes(Data("bytes of v-3".utf8))))
        queue.reader.releaseAll()
        await until { queue.transfers.lost == 0 }
    }

    @Test func aLateAnswerIsNeverHandedToTheNextAskerOfTheSameFile() async {
        let queue = Queue()
        queue.reader.answers[download(1)] = .bytes(Data("old".utf8))
        let first = queue.ask(download(1), .foreground)
        await until { queue.reader.inFlight == 1 && queue.clock.pending == 1 }
        queue.clock.pass()
        #expect(await finished(first) == .timedOut)
        // The same file again, with the old reader still out.
        queue.reader.answers[download(1)] = .bytes(Data("new".utf8))
        let second = queue.ask(download(1), .foreground)
        await until { queue.reader.started.count == 2 && queue.clock.pending == 1 }
        // The old reader answers late with what it had: not the new asker's answer.
        queue.reader.releaseOldest()
        await until { queue.transfers.lost == 0 }
        await turns(10)
        #expect(queue.transfers.waiting(for: download(1)) == 1, "the new asker is still waiting for its own read")
        queue.reader.releaseOldest()
        #expect(await finished(second) == .answered(.bytes(Data("new".utf8))))
    }

    @Test func aReadThatTimedOutIsNotJoinedByTheNextAskerOfTheSameFile() async {
        let queue = Queue()
        let first = queue.ask(download(1), .foreground)
        await until { queue.reader.inFlight == 1 && queue.clock.pending == 1 }
        queue.clock.pass()
        #expect(await finished(first) == .timedOut)
        #expect(queue.transfers.active == 0 && queue.transfers.lost == 1, "its reader hasn't returned, but its slot is free")
        // The same file again while the old reader is still stuck: a read of its
        // own, with a timer of its own, not the dead one.
        let second = queue.ask(download(1), .foreground)
        await until { queue.transfers.waiting(for: download(1)) == 1 }
        await turns(10)
        #expect(queue.reader.started == [download(1), download(1)], "the second asker started a reader")
        #expect(queue.clock.pending == 1, "and a timer")
        #expect(queue.transfers.active == 1)
        // The old reader coming back late is not the new asker's answer.
        queue.reader.releaseOldest()
        await turns(10)
        #expect(queue.transfers.active == 1 && queue.transfers.running == 1 && queue.transfers.lost == 0)
        // The new read's own time limit passes.
        queue.clock.pass()
        #expect(await finished(second) == .timedOut)
        queue.reader.releaseAll()
        await until { queue.transfers.active == 0 }
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
        // When nobody waits any more it stays, for the slot of a reader that never returns.
        let dropped = queue.ask(download(2), .foreground)
        await until { queue.clock.pending == 1 }
        dropped.cancel()
        _ = await dropped.value
        await turns(10)
        #expect(queue.clock.pending == 1 && queue.clock.released == 1)
        // It goes with the reader.
        queue.reader.releaseAll()
        await until { queue.clock.pending == 0 }
        #expect(queue.clock.released == 2)
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
        await until { rig.reader.cancelled.count == 2 && rig.reader.aborted.count == 2 }
        #expect(Set(rig.reader.cancelled) == Set(first), "the readers' tasks were cancelled")
        #expect(Set(rig.reader.aborted) == Set(first.compactMap { rig.reader.nonces[$0] }),
                "the page was asked to abort exactly those reads, each by its own nonce")
        #expect(rig.clock.pending == 2 && rig.clock.released == 0, "their deadlines stand until the readers return")
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

// MARK: A window closed and opened again

/// What a session's Save All row and the spinners showed, change by change:
/// each moment is the state of both just after one of them changed, and
/// whether a Save All was still registered (so a close could stop it).
@MainActor
private final class SaveAllTrail {
    struct Moment: Equatable {
        var batch: ShelfSaveAllState?
        var saving: Set<String>
        var registered: Bool
    }

    private(set) var moments: [Moment] = []
    private var batch: ShelfSaveAllState?
    private var saving: Set<String>
    private var subscriptions: [any Cancellable] = []

    init(_ shelf: ResultsShelf, session id: String) {
        batch = shelf.batches[id]
        saving = shelf.saving
        subscriptions.append(shelf.$batches.dropFirst().sink { [weak self, weak shelf] all in
            MainActor.assumeIsolated {
                self?.batch = all[id]
                self?.note(shelf)
            }
        })
        subscriptions.append(shelf.$saving.dropFirst().sink { [weak self, weak shelf] all in
            MainActor.assumeIsolated {
                self?.saving = all
                self?.note(shelf)
            }
        })
    }

    private func note(_ shelf: ResultsShelf?) {
        moments.append(Moment(batch: batch, saving: saving, registered: shelf?.isSavingAll ?? false))
    }
}

/// The window closing while work for its run is still under way, and opening
/// again: what the old run does when it winds up must touch nothing the new
/// run owns.
@MainActor
struct ShelfCloseAndReopenTests {
    // MARK: Save All

    @Test func aSaveAllTheWindowClosedOnLeavesTheNextOneItsRowItsSpinnersAndItsPlace() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list((1...3).map { file($0) })
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            // Only the first write is slow, as a slow destination would make it.
            if !gate.hasEntered { gate.block() }
            saved.write(data, to: url)
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered }
        // The window closes with the first file's write still under way, and opens again.
        shelf.close()
        #expect(shelf.batches[id] == nil && !shelf.isSavingAll)
        shelf.open()
        // A Save All of the same session: its first two downloads wait in the page.
        rig.reader.hold = true
        shelf.saveAll(id, into: out)
        await until { rig.reader.inFlight == 2 }
        #expect(shelf.batches[id] == .saving(done: 0, total: 3) && shelf.saving == ["v-1", "v-2"])
        let trail = SaveAllTrail(shelf, session: id)
        // The old write lands, and the old Save All winds up. Nothing it clears is the new one's.
        gate.open()
        await until { !shelf.saved.isEmpty }   // whichever of its two downloads came first
        await turns(10)
        #expect(shelf.isSavingAll, "the new Save All is still registered, so a close can stop it")
        #expect(shelf.batches[id] == .saving(done: 0, total: 3), "its progress row is still there")
        #expect(shelf.saving == ["v-1", "v-2"], "and so are the spinners of the files it is downloading")
        // The new Save All goes on and finishes by itself.
        rig.reader.hold = false
        rig.reader.releaseAll()
        await until { if case .finished? = shelf.batches[id] { true } else { false } }
        await shelf.settled()
        await until { shelf.saving.isEmpty }
        if case .finished(let summary)? = shelf.batches[id] {
            #expect(summary.saved == 3 && summary.failed == 0 && summary.tooBig == 0)
        } else {
            Issue.record("the new Save All never finished: \(String(describing: shelf.batches[id]))")
        }
        #expect(!shelf.isSavingAll && shelf.saving.isEmpty)
        #expect(rig.saved.written.count == 4, "the old run's file, then the new run's three")
        // Across every change on the way: a row all along, a spinner for every file in hand, and registered.
        #expect(trail.moments.allSatisfy { $0.batch != nil }, "the row never went: \(trail.moments)")
        #expect(trail.moments.allSatisfy { $0.registered }, "it never lost its place: \(trail.moments)")
        // (The last file's spinner goes just before its progress is counted, so it is the one moment without.)
        let unfinished = trail.moments.filter { moment in
            if case .saving(let done, let total)? = moment.batch { done + 1 < total } else { false }
        }
        #expect(unfinished.allSatisfy { !$0.saving.isEmpty }, "files still to save always showed a spinner: \(trail.moments)")
    }

    @Test func aSaveAllOnAFileASaveIsWritingKeepsItsSpinnerAfterTheSaveEnds() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list((1...3).map { file($0) })
        let first = ThreadGate(), second = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            // The Save's write is slow, and so is the first one of the Save All after it.
            if !first.hasEntered { first.block() } else if !second.hasEntered { second.block() }
            saved.write(data, to: url)
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        let save = Task { await shelf.save(file(1), to: out.appending(path: "single.md")) }
        await until { first.hasEntered }
        #expect(shelf.saving == ["v-1"])
        shelf.saveAll(id, into: out)
        // The Save's download, then the Save All's of the same file and of the next.
        await until { rig.reader.started.filter { $0 == download(1) || $0 == download(2) }.count == 3 }
        first.open()
        #expect(await save.value == .saved(out.appending(path: "single.md")))
        await until { second.hasEntered }
        // The Save is over; the Save All still has the file in hand.
        #expect(shelf.saving.contains("v-1"), "the Save's end took the Save All's spinner")
        let again = Task { await shelf.save(file(1), to: out.appending(path: "again.md")) }
        second.open()
        #expect(await again.value == .busy, "the file is still being saved: a second Save does nothing")
        await shelf.settled()
        await until { shelf.saving.isEmpty }
        #expect(!shelf.isSavingAll)
    }

    @Test func closingBeforeASaveAllHasStartedLeavesItNoProgressRow() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list((1...3).map { file($0) })
        let shelf = rig.shelf()
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        // Asked and closed in one turn: the Save All's task hasn't run yet.
        shelf.saveAll(id, into: out)
        #expect(shelf.batches[id] == .saving(done: 0, total: 3))
        shelf.close()
        #expect(shelf.batches[id] == nil && !shelf.isSavingAll)
        await turns(10)
        #expect(shelf.batches[id] == nil, "the stopped run put its row back")
        #expect(shelf.saving.isEmpty && !shelf.isSavingAll)
        #expect(rig.reader.started == [list(1)] && rig.saved.written.isEmpty, "nothing was downloaded or written")
        // The window's next Save All is its own.
        shelf.open()
        shelf.saveAll(id, into: out)
        await shelf.settled()
        if case .finished(let summary)? = shelf.batches[id] {
            #expect(summary.saved == 3)
        } else {
            Issue.record("the next Save All never finished: \(String(describing: shelf.batches[id]))")
        }
    }

    // MARK: Copies

    @Test func aCopyIsNotHandedOverWhenTheWindowClosesWhileItsExistenceIsChecked() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        let shelf = rig.shelf()
        let url = try #require(await shelf.prepareQuickLook(file(1)))
        #expect(shelf.cachedCopy("v-1") == url)
        // A drop asks for the copy again; the window closes while the check that
        // it is still there is under way. The run's folder is still there too
        // (its deletion waits), so the check answers yes.
        await storage.hold("exists")
        await storage.hold("remove")
        let drop = Task { await shelf.temporaryCopy(of: file(1)) }
        await untilHeld(storage, "exists")
        shelf.close()
        await storage.release("exists")
        #expect(await drop.value == .cancelled, "a drop in flight must not be handed a copy of the run being deleted")
        #expect(shelf.cachedCopy("v-1") == nil && shelf.preparing.isEmpty && shelf.fileProblems.isEmpty)
        #expect(rig.reader.started == [download(1)], "nothing was downloaded for a window that closed")
        await storage.release("remove")
        await shelf.settled()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aDownloadThatLandedJustBeforeTheWindowClosedStartsNoWriteForTheDeadRun() async {
        let rig = ShelfRig()
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        let shelf = rig.shelf()
        // The asker's download, another, and a third read that waits for a slot.
        let asker = Task { await shelf.temporaryCopy(of: file(1)) }
        let other = Task { await shelf.transfers.read(download(2), priority: .foreground) }
        await until { rig.reader.inFlight == 2 }
        // The window closes in the very turn the download lands: the third read
        // starts as the first one's slot is freed, in the reader's own turn, after
        // the asker has been handed its bytes and before it has run again. (The
        // close isn't left to the test's own turn: that would be queued behind
        // the asker's or ahead of it as the executors happen to schedule it.)
        // It has bytes, and the run they are for is over.
        let sawBytesHandedOver = Box(false)
        let third = Task {
            await shelf.transfers.read(download(3), priority: .foreground, started: {
                sawBytesHandedOver.value = shelf.transfers.waiting(for: download(1)) == 0 && shelf.preparing == ["v-1"]
                shelf.close()
            })
        }
        await until { shelf.transfers.queued == 1 }
        rig.reader.release(download(1))
        #expect(await finished(asker) == .cancelled)
        #expect(sawBytesHandedOver.value, "the download had landed and the asker had not run again when the window closed")
        await shelf.settled()
        #expect(await storage.calls.contains("write") == false, "no write was started for the closed run")
        #expect(files(under: rig.base).isEmpty && shelf.cachedCopy("v-1") == nil)
        #expect(shelf.preparing.isEmpty && shelf.fileProblems.isEmpty)
        // The other reads were let go by the close; their readers are let go here.
        #expect(await finished(other) == .cancelled)
        #expect(await finished(third) == .cancelled)
        rig.reader.hold = false
        rig.reader.releaseAll()
        await until { shelf.transfers.active == 0 }
    }

    @Test func anAskerThatOutlivedTheWindowDoesNotEndTheNextWindowsSpinner() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        await storage.hold("write")
        let shelf = rig.shelf()
        // The first window's copy is being written when it closes and opens again.
        let old = Task { await shelf.prepareQuickLook(file(1)) }
        await untilHeld(storage, "write")
        shelf.close()
        shelf.open()
        #expect(shelf.preparing.isEmpty)
        // The same file is asked for in the new window: its download is under way.
        rig.reader.hold = true
        let new = Task { await shelf.prepareQuickLook(file(1)) }
        await until { rig.reader.inFlight == 1 }
        #expect(shelf.preparing == ["v-1"])
        // The first window's asker is done. The new window's is not.
        await storage.release("write")
        #expect(await old.value == nil)
        #expect(shelf.preparing == ["v-1"], "the old asker's end took the new asker's spinner")
        rig.reader.hold = false
        rig.reader.releaseAll()
        let url = try #require(await new.value)
        #expect(shelf.cachedCopy("v-1") == url && shelf.preparing.isEmpty)
    }

    @Test func aCopyBeingWrittenForTheClosedWindowIsNotJoinedByTheNewWindowsAsker() async throws {
        let rig = ShelfRig()
        rig.reader.hold = false
        let storage = GatedStorage(base: rig.base)
        rig.storage = storage
        await storage.hold("write")
        let shelf = rig.shelf()
        let old = Task { await shelf.prepareQuickLook(file(1)) }
        await untilHeld(storage, "write")
        shelf.close()
        shelf.open()
        // The same file again, in the new window: a write of its own, not the old run's.
        let new = Task { await shelf.prepareQuickLook(file(1)) }
        await untilHeld(storage, "write", count: 2)
        #expect(await storage.waiting("write") == 2, "the new asker waits on a write of its own")
        await storage.release("write")
        #expect(await old.value == nil, "the old run's copy was dropped")
        let url = try #require(await new.value)
        await shelf.settled()
        #expect(shelf.cachedCopy("v-1") == url)
        #expect(files(under: rig.base) == [url.path.replacingOccurrences(of: rig.base.path + "/", with: "")],
                "only the new run's copy is on the disk")
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

// MARK: Saved files within a time limit

/// Stands in for the queue a saved file's blocking write runs on: a call is
/// held until the test runs it, as a folder that doesn't answer would hold it.
@MainActor
private final class HeldCalls {
    private var held: [ShelfSavedFiles.Work] = []

    var count: Int { held.count }

    /// The `run` the writer is given.
    func hold(_ work: @escaping ShelfSavedFiles.Work) { held.append(work) }

    /// The oldest held call returns: its write runs now.
    func finishOldest() { if !held.isEmpty { held.removeFirst()() } }

    func finish(at index: Int) { if held.indices.contains(index) { held.remove(at: index)() } }

    func finishAll() { while !held.isEmpty { held.removeFirst()() } }
}

/// How a save through the writer ended.
private enum SaveEnd {
    case written
    case failed(any Error)

    var isWritten: Bool { if case .written = self { true } else { false } }
    var reason: ShelfSaveError? { if case .failed(let error) = self { error as? ShelfSaveError } else { nil } }
    var cocoaCode: CocoaError.Code? { if case .failed(let error) = self { (error as? CocoaError)?.code } else { nil } }
}

/// A `ShelfSavedFiles` over a fake clock and held calls, writing to a recorded disk.
@MainActor
private final class WriterRig {
    let clock = FakeClock()
    let calls = HeldCalls()
    let disk = SavedDisk()
    let writer: ShelfSavedFiles

    init(limit: @escaping (Int) -> Duration = ShelfSavedFiles.limit(forBytes:)) {
        let clock = clock, calls = calls
        writer = ShelfSavedFiles(limit: limit, holdOff: .seconds(30), wait: { await clock.wait($0) },
                                 run: { calls.hold($0) })
    }

    /// A save of four bytes to `path`, writing to the recorded disk; with
    /// `unlessExists`, Save All's kind, which looks in the same call.
    func save(_ path: String, bytes: Int = 4,
              using write: (@Sendable (Data, URL) throws -> Void)? = nil,
              unlessExists: (@Sendable (URL) -> Bool)? = nil) -> Task<SaveEnd, Never> {
        let disk = disk, writer = writer
        return Task {
            do {
                try await writer.write(Data(count: bytes), to: URL(fileURLWithPath: path),
                                       using: write ?? { data, url in disk.write(data, to: url) },
                                       unlessExists: unlessExists)
                return .written
            } catch {
                return .failed(error)
            }
        }
    }

    /// Whether a file is there, asked through the writer; the disk's answer is `answer`.
    func exists(_ path: String, answer: Bool = true) -> Task<LookEnd, Never> {
        let writer = writer
        return Task {
            do {
                return .exists(try await writer.fileExists(URL(fileURLWithPath: path), using: { _ in answer }))
            } catch {
                return .failed(error)
            }
        }
    }

    /// Whether a folder is there, asked through the writer.
    func folderExists(_ path: String, answer: Bool = true) -> Task<LookEnd, Never> {
        let writer = writer
        return Task {
            do {
                return .exists(try await writer.folderExists(folder(path), using: { _ in answer }))
            } catch {
                return .failed(error)
            }
        }
    }

    /// What a folder holds, asked through the writer.
    func names(in path: String, _ list: @escaping @Sendable (URL) throws -> [String]?) -> Task<LookEnd, Never> {
        let writer = writer
        return Task {
            do {
                return .names(try await writer.names(in: folder(path), using: list))
            } catch {
                return .failed(error)
            }
        }
    }
}

/// How a look through the writer ended.
private enum LookEnd: Sendable {
    case exists(Bool)
    case names(Set<String>?)
    case failed(any Error)

    var answer: Bool? { if case .exists(let there) = self { there } else { nil } }
    var reason: ShelfSaveError? { if case .failed(let error) = self { error as? ShelfSaveError } else { nil } }
    var wasCancelled: Bool { if case .failed(let error) = self { error is CancellationError } else { false } }
}

/// A count the blocking calls bump from any thread.
private final class CallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// A writer whose calls run at once, where they are asked, over a clock that
/// never passes: for what a plan makes of what the disk says.
@MainActor
private func inlineWriter() -> ShelfSavedFiles {
    ShelfSavedFiles(wait: { _ in try? await Task.sleep(for: .seconds(3600)) }, run: { $0() })
}

private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

@MainActor
struct ShelfSavedFilesTests {
    @Test func aDestinationIsTheVolumeUnderVolumesElseTheFolderByItsPathAlone() {
        let destination = ShelfSavedFiles.destination(of:)
        #expect(destination(URL(fileURLWithPath: "/Volumes/Share/a/b.md")) == "/volumes/share")
        #expect(destination(URL(fileURLWithPath: "/Volumes/Share/c.md")) == "/volumes/share")
        #expect(destination(URL(fileURLWithPath: "/Volumes/Share/a/b.md")) == destination(URL(fileURLWithPath: "/Volumes/share/z/y.md")))
        #expect(destination(URL(fileURLWithPath: "/Volumes/Share/b.md")) != destination(URL(fileURLWithPath: "/Volumes/Other/b.md")))
        #expect(destination(URL(fileURLWithPath: "/Users/made-up/Desktop/b.md")) == "/users/made-up/desktop")
        #expect(destination(URL(fileURLWithPath: "/Users/made-up/Desktop/b.md"))
                != destination(URL(fileURLWithPath: "/Users/made-up/Documents/b.md")))
        #expect(destination(URL(fileURLWithPath: "/Volumes/b.md")) == "/volumes")
        #expect(ShelfSavedFiles.destination(inFolder: folder("/Volumes/Share/a")) == "/volumes/share")
    }

    @Test func theLimitIsFifteenSecondsAndOneMoreForEachMiB() {
        let limit = ShelfSavedFiles.limit(forBytes:)
        #expect(limit(-5) == .seconds(15) && limit(0) == .seconds(15))
        #expect(limit(1) == .seconds(16) && limit(1 << 20) == .seconds(16))
        #expect(limit((1 << 20) + 1) == .seconds(17))
        #expect(limit(8 << 20) == .seconds(23), "an 8 MB file: the cap")
    }

    @Test func theClockIsAskedForTheLimitOfTheBytesAndTheHoldOff() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/a/one.md", bytes: 3 << 20)
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        #expect(rig.clock.asked == [.seconds(18)])
        rig.clock.pass()
        _ = await finished(stuck)
        await until { rig.clock.pending == 1 }
        #expect(rig.clock.asked == [.seconds(18), .seconds(30)], "then the hold-off")
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func aWriteRunsOffTheCallerAndAnswersWhenItsCallReturns() async {
        let rig = WriterRig()
        let save = rig.save("/made-up/a/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        #expect(rig.disk.written.isEmpty, "nothing is written until the call runs")
        #expect(rig.writer.isPending(URL(fileURLWithPath: "/made-up/a/ONE.md")), "a name is spoken for, whatever its case")
        rig.calls.finishOldest()
        #expect((await finished(save))?.isWritten == true)
        #expect(rig.disk.written == ["/made-up/a/one.md"])
        #expect(rig.writer.isAtRest && rig.clock.pending == 0 && rig.clock.released == 1, "its timer was let go")
    }

    @Test func aWriteThatNeverReturnsFailsAtItsLimitAndASaveElsewhereGoes() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        #expect(!rig.writer.isHeldOff(folder("/made-up/elsewhere")))
        // Another folder: its own turn, at once, though the first call is still out.
        let elsewhere = rig.save("/made-up/elsewhere/two.md")
        await until { rig.calls.count == 2 }
        rig.calls.finish(at: 1)
        #expect((await finished(elsewhere))?.isWritten == true)
        #expect(rig.disk.written == ["/made-up/elsewhere/two.md"])
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func savesWaitingBehindAWriteThatTimedOutFailAtOnceWithoutACall() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        // Two more for the same folder, queued behind it.
        let second = rig.save("/made-up/dropped/two.md")
        let third = rig.save("/made-up/dropped/three.md")
        await turns(10)
        #expect(rig.calls.count == 1, "one at a time per destination")
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        #expect((await finished(second))?.reason == .folderStillSilent)
        #expect((await finished(third))?.reason == .folderStillSilent)
        // And one asked later, while it is held off.
        let later = rig.save("/made-up/dropped/four.md")
        #expect((await finished(later))?.reason == .folderStillSilent)
        #expect(rig.calls.count == 1, "none of them made a call")
        #expect(!rig.writer.isPending(URL(fileURLWithPath: "/made-up/dropped/two.md")), "a refused save speaks for nothing")
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func theHoldOffEndsOnItsOwnClockAndOneSaveIsLetThroughToFindOut() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        _ = await finished(stuck)
        await until { rig.clock.pending == 1 }
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        // The hold-off passes with the first call still out.
        rig.clock.pass()
        await until { !rig.writer.isHeldOff(folder("/made-up/dropped")) }
        let probe = rig.save("/made-up/dropped/two.md")
        await until { rig.calls.count == 2 && rig.clock.pending == 1 }
        // The probe is silent too: the folder is held off again, for a hold-off of its own.
        rig.clock.pass()
        #expect((await finished(probe))?.reason == .folderDidNotRespond)
        await until { rig.clock.pending == 1 }
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        // Both stuck calls come back late: the folder answers.
        rig.calls.finishAll()
        await until { rig.writer.isAtRest && rig.clock.pending == 0 }
        #expect(!rig.writer.isHeldOff(folder("/made-up/dropped")))
        #expect(Set(rig.disk.written) == ["/made-up/dropped/one.md", "/made-up/dropped/two.md"])
    }

    @Test func aStuckWriteReturningLateLiftsTheHoldOffAndIsHeardOfOnce() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        _ = await finished(stuck)
        await until { rig.clock.pending == 1 }
        rig.calls.finishOldest()
        await until { !rig.writer.isHeldOff(folder("/made-up/dropped")) }
        #expect(rig.disk.written == ["/made-up/dropped/one.md"], "it landed, late")
        await until { rig.clock.pending == 0 }
        #expect(rig.writer.isAtRest, "and the hold-off's timer was let go")
        // Its limit passing now, or its answer again, changes nothing.
        rig.clock.pass()
        await turns(10)
        #expect(rig.writer.isAtRest)
        // The folder takes saves again.
        let next = rig.save("/made-up/dropped/two.md")
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(next))?.isWritten == true)
    }

    @Test func aWriteThatFailsLateIsDroppedAndTheFolderCountsAsAnsweringAgain() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/dropped/one.md", using: { _, _ in throw CocoaError(.fileWriteVolumeReadOnly) })
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        rig.calls.finishOldest()
        await until { rig.writer.isAtRest && rig.clock.pending == 0 }
        #expect(rig.disk.written.isEmpty)
    }

    @Test func aNameIsSpokenForUntilItsCallReturnsLateOrNot() async {
        let rig = WriterRig()
        let one = URL(fileURLWithPath: "/made-up/dropped/one.md")
        let stuck = rig.save("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        // The same name while its write is out, within the limit.
        #expect((await finished(rig.save("/made-up/dropped/one.md")))?.reason == .earlierSaveUnfinished)
        #expect(rig.calls.count == 1)
        rig.clock.pass()
        _ = await finished(stuck)
        #expect(rig.writer.isPending(one), "past its limit, the call is still out")
        // The hold-off passes: other names go through, this one still waits for its call.
        await until { rig.clock.pending == 1 }
        rig.clock.pass()
        await until { !rig.writer.isHeldOff(folder("/made-up/dropped")) }
        #expect((await finished(rig.save("/made-up/dropped/ONE.md")))?.reason == .earlierSaveUnfinished)
        let other = rig.save("/made-up/dropped/two.md")
        await until { rig.calls.count == 2 }
        rig.calls.finish(at: 1)
        #expect((await finished(other))?.isWritten == true)
        // The late call lands; the name is free (and the file is there, for the next to see).
        rig.calls.finishOldest()
        await until { !rig.writer.isPending(one) }
        #expect(rig.disk.exists(one))
        #expect(rig.writer.isAtRest)
    }

    @Test func savesToOneDestinationGoOneAtATimeInOrderAndOthersDoNotWait() async {
        let rig = WriterRig()
        let first = rig.save("/made-up/a/one.md")
        await until { rig.calls.count == 1 }
        let second = rig.save("/made-up/a/two.md")
        let third = rig.save("/made-up/a/three.md")
        let elsewhere = rig.save("/made-up/b/four.md")
        await until { rig.calls.count == 2 }
        await turns(10)
        #expect(rig.calls.count == 2, "the second and third of a wait for the first; b's goes")
        rig.calls.finish(at: 1)
        #expect((await finished(elsewhere))?.isWritten == true)
        rig.calls.finishOldest()
        #expect((await finished(first))?.isWritten == true)
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(second))?.isWritten == true)
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(third))?.isWritten == true)
        #expect(rig.disk.written == ["/made-up/b/four.md", "/made-up/a/one.md", "/made-up/a/two.md", "/made-up/a/three.md"])
        #expect(rig.writer.isAtRest && rig.clock.pending == 0)
    }

    @Test func aWriteThatFailsReportsItsErrorAndPassesTheTurn() async {
        let rig = WriterRig()
        let bad = rig.save("/made-up/a/one.md", using: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let good = rig.save("/made-up/a/two.md")
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(bad))?.cocoaCode == .fileWriteNoPermission)
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(good))?.isWritten == true)
        #expect(rig.writer.isAtRest && !rig.writer.isHeldOff(folder("/made-up/a")), "an ordinary failure holds nothing off")
    }

    @Test func theSentencesSayWhatHappenedPlainly() {
        #expect(ShelfSaveError.folderDidNotRespond.localizedDescription
                == "The folder didn't respond. If it comes back, the file may still appear there.")
        #expect(ShelfSaveError.folderStillSilent.localizedDescription == "The folder still isn't responding.")
        #expect(ShelfSaveError.earlierSaveUnfinished.localizedDescription == "An earlier save of this file hasn't finished.")
    }
}

/// The shelf's Save and Save All over a folder that stops answering: the
/// blocking write holds a real thread, the clock is the test's.
@MainActor
struct ShelfSaveTimeoutTests {
    private static let silent = "Couldn't save it there: " + (ShelfSaveError.folderDidNotRespond.errorDescription ?? "")
    private static let stillSilent = "Couldn't save it there: " + (ShelfSaveError.folderStillSilent.errorDescription ?? "")

    @Test func aSaveToAFolderThatStopsAnsweringFailsAtItsLimitAndLaterSavesGoOrFailAtOnce() async {
        let rig = ShelfRig()
        rig.reader.hold = false
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            // The first write never returns until the test lets it: a dropped network volume.
            if !gate.hasEntered { gate.block() }
            saved.write(data, to: url)
        })
        let stuck = rig.scratch.appending(path: "Dropped/made-up-1.md")
        let save = Task { await shelf.save(file(1), to: stuck) }
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        #expect(shelf.saving == ["v-1"])
        rig.writeClock.pass()
        #expect(await finished(save) == .writeFailed(Self.silent))
        #expect(shelf.saving.isEmpty && shelf.saved.isEmpty && rig.didSave.isEmpty)
        #expect(shelf.fileProblems["v-1"] == Self.silent)
        #expect(gate.isBlocking, "the write itself is still out")
        // Another folder is not held up.
        let elsewhere = rig.scratch.appending(path: "Elsewhere/made-up-2.md")
        #expect(await shelf.save(file(2), to: elsewhere) == .saved(elsewhere))
        // The same folder fails at once, and nothing is written.
        let again = rig.scratch.appending(path: "Dropped/made-up-3.md")
        #expect(await shelf.save(file(3), to: again) == .writeFailed(Self.stillSilent))
        #expect(shelf.fileProblems["v-3"] == Self.stillSilent && shelf.saving.isEmpty)
        #expect(!rig.saved.written.contains(again.path))
        #expect(!rig.reader.started.contains(download(3)), "and nothing was downloaded for it")
        // The write lands at last, late: the folder answers, and a save there goes through.
        gate.open()
        await until { rig.saved.written.contains(stuck.path) && !rig.writer.isHeldOff(stuck.deletingLastPathComponent()) }
        #expect(shelf.saved["v-1"] == nil, "a save reported as failed is not recorded as saved")
        #expect(await shelf.save(file(3), to: again) == .saved(again))
        #expect(rig.writer.isAtRest && rig.writeClock.pending == 0)
    }

    @Test func saveAllIntoAFolderThatStopsAnsweringCostsOneLimitAndCountsTheRestAsFailed() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list((1...4).map { file($0) })
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            if !gate.hasEntered { gate.block() }
            saved.write(data, to: url)
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Dropped", directoryHint: .isDirectory)
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        rig.writeClock.pass()
        await until { if case .finished? = shelf.batches[id] { true } else { false } }
        guard case .finished(let summary)? = shelf.batches[id] else { return }
        #expect(summary.saved == 0 && summary.failed == 4 && summary.tooBig == 0)
        #expect(summary.line == "Nothing was saved. 4 couldn't be saved.")
        let downloads = rig.reader.started.filter { if case .download = $0 { true } else { false } }
        #expect(downloads == [download(1), download(2)], "the files after the first two were never downloaded")
        // One of the two in hand timed out; the other, and the rest, were refused.
        #expect(Set([shelf.fileProblems["v-1"], shelf.fileProblems["v-2"]]) == [Self.silent, Self.stillSilent])
        #expect(shelf.fileProblems["v-3"] == Self.stillSilent && shelf.fileProblems["v-4"] == Self.stillSilent)
        #expect(shelf.saving.isEmpty && !shelf.isSavingAll && shelf.saved.isEmpty)
        #expect(rig.saved.written.isEmpty)
        gate.open()
        await until { rig.writer.isAtRest }
    }

    @Test func aSaveThatTimesOutLetsGoOfItsOwnHoldAndNotTheSaveAlls() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list((1...3).map { file($0) })
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            if url.lastPathComponent == "single.md" { gate.block() }
            saved.write(data, to: url)
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        let single = rig.scratch.appending(path: "Dropped/single.md")
        let save = Task { await shelf.save(file(1), to: single) }
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        // A Save All of the same session, its first two downloads waiting in the page.
        rig.reader.hold = true
        shelf.saveAll(id, into: out)
        await until { rig.reader.inFlight == 2 }
        #expect(shelf.saving == ["v-1", "v-2"])
        // The Save's write is silent past its limit (the only timer pending).
        rig.writeClock.pass()
        #expect(await finished(save) == .writeFailed(Self.silent))
        #expect(shelf.saving == ["v-1", "v-2"], "the Save's end let go of its own hold, not the Save All's")
        // The Save All goes on and finishes by itself.
        rig.reader.hold = false
        rig.reader.releaseAll()
        await until { if case .finished? = shelf.batches[id] { true } else { false } }
        await shelf.settled()
        await until { shelf.saving.isEmpty }
        if case .finished(let summary)? = shelf.batches[id] {
            #expect(summary.saved == 3 && summary.failed == 0)
        } else {
            Issue.record("the Save All never finished: \(String(describing: shelf.batches[id]))")
        }
        gate.open()
        await until { rig.writer.isAtRest }
    }

    @Test func aWriteThatLandsLateNeverRacesALaterSaveForItsName() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list([file(1)])
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            if !gate.hasEntered { gate.block() }
            saved.write(data, to: url)
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        let plain = out.appending(path: "made-up-1.md")
        // The first Save All's only write goes silent.
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        rig.writeClock.pass()
        await shelf.settled()
        if case .finished(let summary)? = shelf.batches[id] { #expect(summary.failed == 1 && summary.saved == 0) }
        // The hold-off passes, the call still out. The name is spoken for: a Save of it is refused...
        await until { rig.writeClock.pending == 1 }
        rig.writeClock.pass()
        await until { !rig.writer.isHeldOff(out) }
        #expect(await shelf.save(file(1), to: plain)
                == .writeFailed("Couldn't save it there: " + (ShelfSaveError.earlierSaveUnfinished.errorDescription ?? "")))
        // ...and a Save All numbers its name around it, though nothing is on the disk yet.
        #expect(!rig.saved.exists(plain))
        shelf.saveAll(id, into: out)
        await shelf.settled()
        if case .finished(let summary)? = shelf.batches[id] { #expect(summary.saved == 1 && summary.failed == 0) }
        let second = out.appending(path: "made-up-1 2.md")
        #expect(shelf.saved["v-1"] == second)
        // The late write lands at last, under its own name.
        gate.open()
        await until { rig.saved.exists(plain) && rig.writer.isAtRest }
        #expect(Set(rig.saved.written) == [plain.path, second.path])
        #expect(rig.saved.written.count == 2, "no name was written twice")
        // And the next Save All sees both on the disk.
        shelf.saveAll(id, into: out)
        await shelf.settled()
        #expect(shelf.saved["v-1"] == out.appending(path: "made-up-1 3.md"))
    }
}

// MARK: Looks at the destination within a time limit

/// The looks (is there a file, is the folder there, what does it hold) go
/// through the same layer as the writes: off the caller, in the destination's
/// turn, within a limit, and a look that doesn't answer counts like a write
/// that didn't.
@MainActor
struct ShelfDestinationLookTests {
    @Test func aLookRunsOffTheCallerAndAnswersWhenItsCallReturns() async {
        let rig = WriterRig()
        let there = rig.exists("/made-up/a/one.md", answer: true)
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        #expect(!rig.writer.isPending(URL(fileURLWithPath: "/made-up/a/one.md")), "a look speaks for no name")
        rig.calls.finishOldest()
        #expect((await finished(there))?.answer == true)
        #expect(rig.writer.isAtRest && rig.clock.pending == 0 && rig.clock.released == 1, "its timer was let go")
        let gone = rig.exists("/made-up/a/two.md", answer: false)
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(gone))?.answer == false)
        let folderThere = rig.folderExists("/made-up/a", answer: true)
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(folderThere))?.answer == true)
        #expect(rig.writer.isAtRest)
    }

    @Test func aLookIsGivenTheLimitOfNoBytes() async {
        let rig = WriterRig(limit: { .seconds(100 + $0) })
        let look = rig.exists("/made-up/a/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        #expect(rig.clock.asked == [.seconds(100)], "the writer's own limit function, for a call with no bytes")
        rig.calls.finishOldest()
        _ = await finished(look)
        let defaulted = WriterRig()
        let other = defaulted.exists("/made-up/a/one.md")
        await until { defaulted.calls.count == 1 && defaulted.clock.pending == 1 }
        #expect(defaulted.clock.asked == [.seconds(15)])
        defaulted.calls.finishOldest()
        _ = await finished(other)
    }

    @Test func aLookTheFolderNeverAnswersFailsAtItsLimitAndHoldsTheDestinationOffLikeAWrite() async {
        let rig = WriterRig()
        let stuck = rig.exists("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        #expect(!rig.writer.isHeldOff(folder("/made-up/elsewhere")))
        // Everything asked of that folder now fails at once, without a call.
        let again = rig.exists("/made-up/dropped/two.md")
        let folderThere = rig.folderExists("/made-up/dropped")
        let listing = rig.names(in: "/made-up/dropped") { _ in [] }
        let save = rig.save("/made-up/dropped/three.md")
        let saveAll = rig.save("/made-up/dropped/four.md", unlessExists: { _ in false })
        #expect((await finished(again))?.reason == .folderStillSilent)
        #expect((await finished(folderThere))?.reason == .folderStillSilent)
        #expect((await finished(listing))?.reason == .folderStillSilent)
        #expect((await finished(save))?.reason == .folderStillSilent)
        #expect((await finished(saveAll))?.reason == .folderStillSilent)
        #expect(rig.calls.count == 1, "none of them made a call")
        // Another folder is not held up.
        let elsewhere = rig.exists("/made-up/elsewhere/one.md")
        await until { rig.calls.count == 2 }
        rig.calls.finish(at: 1)
        #expect((await finished(elsewhere))?.answer == true)
        // The hold-off passes on its own clock with the first call still out: one look finds out.
        await until { rig.clock.pending == 1 }
        rig.clock.pass()
        await until { !rig.writer.isHeldOff(folder("/made-up/dropped")) }
        let probe = rig.exists("/made-up/dropped/five.md")
        await until { rig.calls.count == 2 && rig.clock.pending == 1 }
        rig.calls.finishAll()
        #expect((await finished(probe))?.answer == true)
        await until { rig.writer.isAtRest && rig.clock.pending == 0 }
    }

    @Test func aStuckLookReturningLateLiftsTheHoldOff() async {
        let rig = WriterRig()
        let stuck = rig.folderExists("/made-up/dropped")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        await until { rig.clock.pending == 1 }
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        rig.calls.finishOldest()
        await until { !rig.writer.isHeldOff(folder("/made-up/dropped")) }
        await until { rig.clock.pending == 0 }
        #expect(rig.writer.isAtRest, "and the hold-off's timer was let go")
        // The folder answers again.
        let next = rig.exists("/made-up/dropped/two.md")
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(next))?.answer == true)
    }

    @Test func aWriteThatTimedOutHoldsLooksOffToo() async {
        let rig = WriterRig()
        let stuck = rig.save("/made-up/dropped/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        #expect((await finished(rig.exists("/made-up/dropped/two.md")))?.reason == .folderStillSilent)
        #expect((await finished(rig.folderExists("/made-up/dropped")))?.reason == .folderStillSilent)
        #expect(rig.calls.count == 1, "no call for either")
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func aFolderIsLookedAtByItsOwnDestinationAndAFileByItsFolders() async {
        let rig = WriterRig()
        // A write into /made-up/dropped/data is stuck: its folder is held off...
        let stuck = rig.save("/made-up/dropped/data/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        _ = await finished(stuck)
        // ...so asking whether that folder is there is refused, though its parent isn't held off.
        #expect((await finished(rig.folderExists("/made-up/dropped/data")))?.reason == .folderStillSilent)
        #expect((await finished(rig.exists("/made-up/dropped/data/two.md")))?.reason == .folderStillSilent)
        let parent = rig.folderExists("/made-up/dropped")
        await until { rig.calls.count == 2 }
        rig.calls.finish(at: 1)
        #expect((await finished(parent))?.answer == true, "the parent is its own destination")
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func writesGoOneAtATimeAndSoDoLooksEachInTheirOwnTurnAndNeitherWaitsForTheOther() async {
        let rig = WriterRig()
        let write = rig.save("/made-up/a/one.md")
        await until { rig.calls.count == 1 }
        // A look doesn't wait behind a slow write to the same folder (a Save All started now still settles its names)...
        let look = rig.exists("/made-up/a/two.md")
        await until { rig.calls.count == 2 }
        // ...but a second write waits for the first, and a second look for the first look.
        let second = rig.save("/made-up/a/three.md")
        let secondLook = rig.exists("/made-up/a/four.md")
        let elsewhere = rig.exists("/made-up/b/five.md")
        await until { rig.calls.count == 3 }
        await turns(10)
        #expect(rig.calls.count == 3, "b's look goes; the second write and the second look wait")
        rig.calls.finish(at: 2)
        #expect((await finished(elsewhere))?.answer == true)
        rig.calls.finish(at: 1)
        #expect((await finished(look))?.answer == true)
        await until { rig.calls.count == 2 }
        rig.calls.finish(at: 1)
        #expect((await finished(secondLook))?.answer == true)
        rig.calls.finishOldest()
        #expect((await finished(write))?.isWritten == true)
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(second))?.isWritten == true)
        #expect(rig.disk.written == ["/made-up/a/one.md", "/made-up/a/three.md"])
        #expect(rig.writer.isAtRest && rig.clock.pending == 0)
    }

    @Test func aLookWhoseTaskWasCancelledWhileItWaitedForItsTurnMakesNoCall() async {
        let rig = WriterRig()
        let first = rig.exists("/made-up/a/one.md")
        await until { rig.calls.count == 1 }
        let look = rig.exists("/made-up/a/two.md")
        await turns(10)
        look.cancel()
        rig.calls.finishOldest()
        #expect((await finished(first))?.answer == true)
        #expect((await finished(look))?.wasCancelled == true)
        await turns(10)
        #expect(rig.calls.count == 0, "the cancelled look was never made")
        #expect(rig.writer.isAtRest && !rig.writer.isHeldOff(folder("/made-up/a")))
        // And a cancelled look gives the turn to the next.
        let after = rig.exists("/made-up/a/three.md")
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(after))?.answer == true)
    }

    @Test func aListingHasLowercasedNamesAndFailsOrTooLongIsNilWithoutHoldingAnythingOff() async {
        let rig = WriterRig()
        let listed = rig.names(in: "/made-up/a") { _ in ["Report.MD", "b.md", "Straße.txt"] }
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        guard case .names(let names)? = await finished(listed) else { Issue.record("no listing"); return }
        #expect(names == ["report.md", "b.md", "straße.txt"])
        let unreadable = rig.names(in: "/made-up/a") { _ in throw CocoaError(.fileReadNoPermission) }
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        guard case .names(let none)? = await finished(unreadable) else { Issue.record("a failed listing is an answer: nil"); return }
        #expect(none == nil)
        let tooMany = rig.names(in: "/made-up/a") { _ in nil }
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        guard case .names(let nothing)? = await finished(tooMany) else { Issue.record("no answer"); return }
        #expect(nothing == nil)
        #expect(!rig.writer.isHeldOff(folder("/made-up/a")), "an ordinary failure holds nothing off")
        #expect(rig.writer.isAtRest)
    }

    @Test func aWriteThatLooksFirstLooksAndWritesInOneCallAndWritesNothingOverAName() async {
        let rig = WriterRig()
        let asked = CallCount()
        let taken = rig.save("/made-up/a/one.md", unlessExists: { _ in asked.bump(); return true })
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        #expect(asked.count == 0, "nothing is asked until the call runs")
        rig.calls.finishOldest()
        #expect((await finished(taken))?.reason == .nameTaken)
        #expect(asked.count == 1 && rig.disk.written.isEmpty, "the name was there: nothing was written")
        #expect(rig.calls.count == 0, "the look and the write are one call")
        #expect(rig.writer.isAtRest && !rig.writer.isHeldOff(folder("/made-up/a")), "a name taken holds nothing off")
        let free = rig.save("/made-up/a/one.md", unlessExists: { _ in asked.bump(); return false })
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(free))?.isWritten == true)
        #expect(asked.count == 2 && rig.disk.written == ["/made-up/a/one.md"])
        // A Save… (no look) writes over whatever is there: the person was asked.
        let over = rig.save("/made-up/a/one.md")
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        #expect((await finished(over))?.isWritten == true)
        #expect(rig.disk.written == ["/made-up/a/one.md", "/made-up/a/one.md"])
    }

    @Test func aNameIsStillSpokenForWhenTheLookInItsWriteTimesOut() async {
        let rig = WriterRig()
        let url = URL(fileURLWithPath: "/made-up/dropped/one.md")
        let stuck = rig.save("/made-up/dropped/one.md", unlessExists: { _ in true })
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(stuck))?.reason == .folderDidNotRespond)
        #expect(rig.writer.isPending(url), "the call is still out")
        rig.calls.finishOldest()
        await until { !rig.writer.isPending(url) && !rig.writer.isHeldOff(folder("/made-up/dropped")) }
        await until { rig.writer.isAtRest }
        #expect(rig.disk.written.isEmpty, "it found the name taken, late: nothing was written")
    }
}

// MARK: Save All's names

/// `ShelfNamePlan`: the names settled before the first download, from one
/// listing, or asked for by name when the folder can't be listed.
@MainActor
struct ShelfNamePlanTests {
    private let out = folder("/made-up/out")

    private func claims(_ wanted: [String], on disk: Set<String>, listing: Bool) async throws -> [String] {
        let writer = inlineWriter()
        let there = Set(disk.map { $0.lowercased() })
        let plan = try await writer.plan(in: out, exists: { there.contains($0.lastPathComponent.lowercased()) },
                                         list: { _ in listing ? Array(disk) : nil })
        var names: [String] = []
        for name in wanted { names.append(try await plan.claim(name)) }
        return names
    }

    @Test func namesNumberAroundTheFolderTheBatchAndCaseFromOneListing() async throws {
        let writer = inlineWriter()
        let listed = CallCount(), asked = CallCount()
        let plan = try await writer.plan(in: out, exists: { _ in asked.bump(); return false },
                                         list: { _ in listed.bump(); return ["Report.md", "notes"] })
        #expect(try await plan.claim("report.md") == "report 2.md", "the folder has Report.md, and this Mac compares without case")
        #expect(try await plan.claim("figure.png") == "figure.png")
        #expect(try await plan.claim("figure.png") == "figure 2.png", "earlier in the same batch")
        #expect(try await plan.claim("Figure.png") == "Figure 3.png")
        #expect(try await plan.claim("report.md") == "report 3.md")
        #expect(try await plan.claim("notes") == "notes 2")
        #expect(try await plan.claim("archive.tar.gz") == "archive.tar.gz")
        #expect(listed.count == 1 && asked.count == 0, "one listing, and no question per name")
        #expect(plan.url("a b.md").path == "/made-up/out/a b.md")
    }

    @Test func whenTheFolderCannotBeListedEachNameIsAskedAndTheNamesAreTheSame() async throws {
        let disk: Set<String> = ["Report.md", "report 2.md", "notes"]
        let wanted = ["report.md", "figure.png", "figure.png", "Figure.png", "report.md", "notes"]
        let byListing = try await claims(wanted, on: disk, listing: true)
        let byName = try await claims(wanted, on: disk, listing: false)
        #expect(byListing == ["report 3.md", "figure.png", "figure 2.png", "Figure 3.png", "report 4.md", "notes 2"])
        #expect(byName == byListing)
        // A listing that throws is the same as one that is too long.
        let writer = inlineWriter()
        let plan = try await writer.plan(in: out, exists: { $0.lastPathComponent == "a.md" },
                                         list: { _ in throw CocoaError(.fileReadNoPermission) })
        #expect(try await plan.claim("a.md") == "a 2.md")
    }

    @Test func askingByNameAsksOnlyWhatTheBatchHasNotRuledOutAndNeverTwice() async throws {
        let writer = inlineWriter()
        let asked = NameLog()
        let plan = try await writer.plan(in: out, exists: { url in
            asked.add(url.lastPathComponent)
            return url.lastPathComponent == "a.md"
        }, list: { _ in nil })
        #expect(try await plan.claim("a.md") == "a 2.md")
        #expect(try await plan.claim("a.md") == "a 3.md")
        #expect(try await plan.claim("a.md") == "a 4.md")
        // a.md was asked once (it is there); each number once, when first tried.
        #expect(asked.names == ["a.md", "a 2.md", "a 3.md", "a 4.md"])
    }

    @Test(arguments: 0..<20)
    func theNamesAreTheOnesTheOldSynchronousRuleGaveWhetherListedOrAskedFor(seed: Int) async throws {
        var random = SplitMix64(seed: seed &+ 9_000)
        let pool = ["a.md", "A.md", "a 2.md", "b.csv", "B 2.csv", "c", "c 2", "d.tar.gz", "Figure.png", "figure.png"]
        let disk = Set(pool.filter { _ in Int.random(in: 0..<3, using: &random) == 0 })
        let wanted = (0..<Int.random(in: 1...9, using: &random)).map { _ in pool.randomElement(using: &random)! }
        // What `runSaveAll` did before the disk work moved: ShelfFileName.unique against the batch and the folder.
        var reserved: Set<String> = []
        let lowered = Set(disk.map { $0.lowercased() })
        var expected: [String] = []
        for name in wanted {
            let name = ShelfFileName.unique(name) { reserved.contains($0.lowercased()) || lowered.contains($0.lowercased()) }
            reserved.insert(name.lowercased())
            expected.append(name)
        }
        #expect(try await claims(wanted, on: disk, listing: true) == expected)
        #expect(try await claims(wanted, on: disk, listing: false) == expected)
    }

    @Test func aNameAWriteStillHasOutIsTakenThoughNothingIsOnTheDiskYet() async throws {
        let rig = WriterRig()
        let url = URL(fileURLWithPath: "/made-up/out/one.md")
        // A write of one.md goes silent; the hold-off passes; its call is still out.
        let stuck = rig.save("/made-up/out/one.md")
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        _ = await finished(stuck)
        await until { rig.clock.pending == 1 }
        rig.clock.pass()
        await until { !rig.writer.isHeldOff(out) }
        #expect(rig.writer.isPending(url))
        // The plan lists the folder (the stuck call is not it) and numbers around the name.
        let writer = rig.writer
        let planned = Task { () -> [String]? in
            guard let plan = try? await writer.plan(in: folder("/made-up/out"), exists: { _ in false }, list: { _ in [] }) else { return nil }
            return [(try? await plan.claim("one.md")) ?? "?", (try? await plan.claim("two.md")) ?? "?"]
        }
        await until { rig.calls.count == 2 }
        rig.calls.finish(at: 1)
        #expect((await finished(planned)).flatMap { $0 } == ["one 2.md", "two.md"])
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func aPlanFailsAsALookDoesWhenTheFolderDoesNotAnswer() async {
        let rig = WriterRig()
        let writer = rig.writer
        let planning = Task { () -> ShelfSaveError? in
            do {
                _ = try await writer.plan(in: folder("/made-up/dropped"), exists: { _ in false }, list: { _ in [] })
                return nil
            } catch {
                return error as? ShelfSaveError
            }
        }
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        #expect((await finished(planning)).flatMap { $0 } == .folderDidNotRespond)
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        // Planned again while it is held off: refused at once, no call.
        let again = Task { () -> ShelfSaveError? in
            do {
                _ = try await writer.plan(in: folder("/made-up/dropped"), exists: { _ in false }, list: { _ in [] })
                return nil
            } catch {
                return error as? ShelfSaveError
            }
        }
        #expect((await finished(again)).flatMap { $0 } == .folderStillSilent)
        #expect(rig.calls.count == 1)
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }

    @Test func aNameAskedForThatNeverAnswersEndsTheClaimWithTheFoldersSentence() async {
        let rig = WriterRig()
        let writer = rig.writer
        let claimed = Task { () -> (names: [String], error: ShelfSaveError?) in
            guard let plan = try? await writer.plan(in: folder("/made-up/dropped"), exists: { _ in true }, list: { _ in nil }) else {
                return ([], nil)
            }
            do { return ([try await plan.claim("a.md")], nil) } catch { return ([], error as? ShelfSaveError) }
        }
        // The listing answers "too many"; the first name asked for is silent.
        await until { rig.calls.count == 1 }
        rig.calls.finishOldest()
        await until { rig.calls.count == 1 && rig.clock.pending == 1 }
        rig.clock.pass()
        let result = await finished(claimed)
        #expect(result?.error == .folderDidNotRespond && result?.names == [])
        #expect(rig.writer.isHeldOff(folder("/made-up/dropped")))
        rig.calls.finishAll()
        await until { rig.writer.isAtRest }
    }
}

// MARK: What the real calls do

@MainActor
struct ShelfRealListingTests {
    private func scratchFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "capsid-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aFolderIsListedByNameWithoutDotsAndTooManyIsNil() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.md", ".hidden", "Ünï.txt", "c"] {
            try Data().write(to: folder.appending(path: name, directoryHint: .notDirectory))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "sub", directoryHint: .isDirectory),
                                                withIntermediateDirectories: false)
        let names = try #require(try ShelfSavedFiles.listFolder(folder))
        #expect(Set(names) == ["a.md", ".hidden", "Ünï.txt", "c", "sub"])
        #expect(names.count == 5)
        #expect(try ShelfSavedFiles.listFolder(folder, cap: 5)?.count == 5, "a folder of exactly the cap is listed")
        #expect(try ShelfSavedFiles.listFolder(folder, cap: 4) == nil, "one more than the cap isn't")
        #expect(try ShelfSavedFiles.listFolder(folder, cap: 0) == nil)
        #expect(ShelfSavedFiles.listingCap == 10_000)
    }

    @Test func aFolderThatIsNotThereOrNotAFolderThrows() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: (any Error).self) { try ShelfSavedFiles.listFolder(folder.appending(path: "nope", directoryHint: .isDirectory)) }
        let file = folder.appending(path: "plain", directoryHint: .notDirectory)
        try Data().write(to: file)
        #expect(throws: (any Error).self) { try ShelfSavedFiles.listFolder(file) }
        #expect(try ShelfSavedFiles.listFolder(folder)?.count == 1)
    }

    @Test func theRealWriterPlansAndWritesNothingOverAFileOnARealDisk() async throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("mine".utf8).write(to: folder.appending(path: "report.md", directoryHint: .notDirectory))
        let writer = ShelfSavedFiles()
        let exists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
        let plan = try await writer.plan(in: folder, exists: exists, list: { try ShelfSavedFiles.listFolder($0) })
        let name = try await plan.claim("report.md")
        #expect(name == "report 2.md")
        try await writer.write(Data("new".utf8), to: plan.url(name), using: { try $0.write(to: $1, options: .atomic) },
                               unlessExists: exists)
        // The original is untouched; asking to write over it is refused and writes nothing.
        await #expect(throws: ShelfSaveError.nameTaken) {
            try await writer.write(Data("new".utf8), to: folder.appending(path: "report.md", directoryHint: .notDirectory),
                                   using: { try $0.write(to: $1, options: .atomic) }, unlessExists: exists)
        }
        #expect(try String(contentsOf: folder.appending(path: "report.md", directoryHint: .notDirectory), encoding: .utf8) == "mine")
        #expect(try String(contentsOf: plan.url(name), encoding: .utf8) == "new")
        #expect(try await writer.fileExists(plan.url(name), using: exists))
        #expect(try await writer.folderExists(folder, using: exists))
        #expect(try await !writer.fileExists(plan.url("nope.md"), using: exists))
        await until { writer.isAtRest }
    }
}

// MARK: The shelf over a disk that stops answering to a look

/// What the shelf asks the disk, on a thread that really blocks: the main
/// actor stays free, the limit is the test's clock, and a dead folder costs one
/// limit. Like `ShelfSaveTimeoutTests`, with the looks held instead of the writes.
@MainActor
struct ShelfLookTimeoutTests {
    private static let silent = "Couldn't save it there: " + (ShelfSaveError.folderDidNotRespond.errorDescription ?? "")
    private static let stillSilent = "Couldn't save it there: " + (ShelfSaveError.folderStillSilent.errorDescription ?? "")

    private func downloads(_ rig: ShelfRig) -> [ArtifactRead] {
        rig.reader.started.filter { if case .download = $0 { true } else { false } }
    }

    private func isFinished(_ shelf: ResultsShelf, _ id: String) -> Bool {
        if case .finished? = shelf.batches[id] { true } else { false }
    }

    /// A shelf with three files read, whose folder listing blocks until `gate` opens.
    private func listingShelf(_ rig: ShelfRig, _ gate: ThreadGate) async -> ResultsShelf {
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list((1...3).map { file($0) })
        let shelf = rig.shelf(list: { _ in
            gate.block()
            return []
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        return shelf
    }

    @Test func aListingThatStopsAnsweringBlocksNobodyAndSaveAllFailsAtOnceAfterOneLimit() async {
        let rig = ShelfRig()
        let gate = ThreadGate()
        let shelf = await listingShelf(rig, gate)
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Dropped", directoryHint: .isDirectory)
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        #expect(gate.ranOnMain == false, "the listing runs on the disk's queue, not the main thread")
        // The main actor is free while the listing is out: work on it carries on.
        let ticks = Box(0)
        await Task { @MainActor in
            for _ in 0..<100 {
                ticks.value += 1
                await Task.yield()
            }
        }.value
        #expect(ticks.value == 100 && gate.isBlocking)
        #expect(shelf.batches[id] == .saving(done: 0, total: 3))
        #expect(downloads(rig).isEmpty, "nothing is downloaded before the names are settled")
        // The limit passes: one wait, and every file is counted as failed.
        rig.writeClock.pass()
        await until { isFinished(shelf, id) }
        guard case .finished(let summary)? = shelf.batches[id] else { return }
        #expect(summary.saved == 0 && summary.failed == 3 && summary.tooBig == 0)
        #expect(summary.line == "Nothing was saved. 3 couldn't be saved.")
        #expect(shelf.fileProblems["v-1"] == Self.silent, "the one that found out")
        #expect(shelf.fileProblems["v-2"] == Self.stillSilent && shelf.fileProblems["v-3"] == Self.stillSilent)
        #expect(downloads(rig).isEmpty && rig.saved.written.isEmpty)
        #expect(!shelf.isSavingAll && shelf.saving.isEmpty)
        #expect(rig.writer.isHeldOff(out))
        // Another Save All into it is refused at once, without a call of any kind.
        shelf.saveAll(id, into: out)
        await shelf.settled()
        guard case .finished(let again)? = shelf.batches[id] else { Issue.record("no summary"); return }
        #expect(again.failed == 3 && shelf.fileProblems["v-1"] == Self.stillSilent)
        #expect(downloads(rig).isEmpty)
        // The listing comes back late: the folder answers, and a Save All goes through.
        gate.open()
        await until { !rig.writer.isHeldOff(out) }
        shelf.saveAll(id, into: out)
        await shelf.settled()
        guard case .finished(let last)? = shelf.batches[id] else { Issue.record("no summary"); return }
        #expect(last.saved == 3 && last.failed == 0)
        #expect(Set(rig.saved.written.map { ($0 as NSString).lastPathComponent }) == ["made-up-1.md", "made-up-2.md", "made-up-3.md"])
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }

    @Test func closingWhileTheListingIsOutLetsTheWindowGoAtOnceAndTheRunDownloadsAndWritesNothing() async {
        let rig = ShelfRig()
        let gate = ThreadGate()
        let shelf = await listingShelf(rig, gate)
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Dropped", directoryHint: .isDirectory)
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        shelf.close()
        #expect(!shelf.isSavingAll && shelf.batches.isEmpty, "closing needs nothing from the stuck folder")
        #expect(shelf.saving.isEmpty)
        // The window opens again meanwhile: the shelf answers, and shows its sessions.
        shelf.open()
        #expect(shelf.sessions.count == 1)
        // The listing returns, inside its limit.
        gate.open()
        await shelf.settled()
        #expect(shelf.batches.isEmpty, "the closed run leaves no summary")
        #expect(downloads(rig).isEmpty && rig.saved.written.isEmpty)
        #expect(!rig.writer.isHeldOff(out))
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }

    @Test func aRunClosedBeforeItsListingTimesOutLeavesNoSummaryAndNoFailures() async {
        let rig = ShelfRig()
        let gate = ThreadGate()
        let shelf = await listingShelf(rig, gate)
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Dropped", directoryHint: .isDirectory)
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        shelf.close()
        // The limit passes for the closed run's listing: the destination is held off, nothing else changes.
        rig.writeClock.pass()
        await until { rig.writer.isHeldOff(out) }
        await turns(10)
        #expect(shelf.batches.isEmpty, "a closed run says nothing, not even that the folder was silent")
        #expect(shelf.fileProblems.isEmpty && !shelf.isSavingAll)
        #expect(downloads(rig).isEmpty)
        gate.open()
        await shelf.settled()
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }

    @Test func aNameAnotherSaveIsWritingWhenItsTurnComesIsNumberedAroundNotFailed() async {
        let rig = ShelfRig()
        rig.recent = [session(1)]
        rig.reader.answers[list(1)] = .list([file(1)])
        let gate = ThreadGate()
        let saved = rig.saved
        let shelf = rig.shelf(write: { data, url in
            if url.lastPathComponent == "made-up-1.md", !gate.hasEntered { gate.block() }
            saved.write(data, to: url)
        })
        rig.reader.hold = false
        shelf.open()
        await shelf.settled()
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Out", directoryHint: .isDirectory)
        let taken = out.appending(path: "made-up-1.md")
        // The Save All settles its names (made-up-1.md is free), and its download waits in the page.
        rig.reader.hold = true
        shelf.saveAll(id, into: out)
        await until { rig.reader.inFlight == 1 }
        // Then a Save of another file to that very name goes first, and its write is out.
        let save = Task { await shelf.save(file(2), to: taken) }
        await until { rig.reader.inFlight == 2 }
        rig.reader.release(download(2))
        await until { gate.hasEntered }
        // The Save All's download answers: its write meets the name a write has out.
        rig.reader.release(download(1))
        await turns(30)
        #expect(!rig.saved.exists(taken), "the first write is still out")
        gate.open()
        #expect(await finished(save) == .saved(taken))
        await shelf.settled()
        guard case .finished(let summary)? = shelf.batches[id] else { Issue.record("no summary"); return }
        #expect(summary.saved == 1 && summary.failed == 0, "numbered around the name, not failed")
        #expect(shelf.saved["v-1"] == out.appending(path: "made-up-1 2.md"))
        #expect(shelf.saved["v-2"] == taken)
        #expect(Set(rig.saved.written) == [taken.path, out.appending(path: "made-up-1 2.md").path] && rig.saved.written.count == 2)
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }

    @Test func aSaveAllStartedAfterReopeningWaitsBehindTheOldRunsListingAndIsNotItsToClear() async {
        let rig = ShelfRig()
        let gate = ThreadGate()
        let shelf = await listingShelf(rig, gate)
        let id = madeUpID(1)
        let out = rig.scratch.appending(path: "Dropped", directoryHint: .isDirectory)
        shelf.saveAll(id, into: out)
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        shelf.close()
        shelf.open()
        shelf.saveAll(id, into: out)
        #expect(shelf.isSavingAll && shelf.batches[id] == .saving(done: 0, total: 3))
        await turns(10)
        #expect(downloads(rig).isEmpty, "its listing waits its turn in the folder's lane")
        gate.open()
        await shelf.settled()
        guard case .finished(let summary)? = shelf.batches[id] else { Issue.record("no summary"); return }
        #expect(summary.saved == 3 && summary.failed == 0)
        #expect(downloads(rig).count == 3, "only the new run downloaded")
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }

    /// A shelf whose looks at `exists` block while `gate` is closed and `silent` is set.
    private func askingShelf(_ rig: ShelfRig, _ gate: ThreadGate, silent: Switch) -> ResultsShelf {
        let saved = rig.saved
        return rig.shelf(exists: { url in
            if silent.isOn, !gate.hasEntered { gate.block() }
            return saved.exists(url)
        })
    }

    @Test func aRememberedFolderThatDoesNotAnswerIsPassedOverAndHeldOffForTheNext() async {
        let rig = ShelfRig()
        let gate = ThreadGate()
        let silent = Switch(true)
        let shelf = askingShelf(rig, gate, silent: silent)
        let dropped = rig.scratch.appending(path: "Dropped", directoryHint: .isDirectory)
        UserDefaults(suiteName: rig.suite)!.set(["proj_a": dropped.path], forKey: ShelfFolderMemory.key)
        let ask = Task { await shelf.startingFolder(for: "proj_a") }
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        #expect(gate.ranOnMain == false)
        // The panel is waiting on the answer, and the main actor is free.
        let ticks = Box(0)
        await Task { @MainActor in
            for _ in 0..<50 {
                ticks.value += 1
                await Task.yield()
            }
        }.value
        #expect(ticks.value == 50)
        rig.writeClock.pass()
        let result = await finished(ask)
        #expect(result == .some(nil), "it didn't answer in time: the panel starts where it would")
        #expect(rig.writer.isHeldOff(dropped))
        // And the next panel doesn't wait for another limit: the folder is passed over at once.
        #expect(await finished(Task { await shelf.startingFolder(for: "proj_a") }) == .some(nil))
        // A Save… into it is refused without a download, like any write into a folder that is held off.
        rig.reader.hold = false
        let refused = dropped.appending(path: "made-up-1.md")
        #expect(await shelf.save(file(1), to: refused) == .writeFailed(Self.stillSilent))
        #expect(downloads(rig).isEmpty)
        // The look returns late: the folder answers again. Not there, it is passed over as before; there, the panel starts in it.
        silent.isOn = false
        gate.open()
        await until { !rig.writer.isHeldOff(dropped) }
        #expect(await shelf.startingFolder(for: "proj_a") == nil)
        rig.saved.write(Data(), to: dropped)
        #expect(await shelf.startingFolder(for: "proj_a")?.path == dropped.path)
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }

    @Test func aSavedCopyInAFolderThatDoesNotAnswerIsKeptAndSaysSo() async {
        let rig = ShelfRig()
        rig.reader.hold = false
        let gate = ThreadGate()
        let silent = Switch(false)
        let shelf = askingShelf(rig, gate, silent: silent)
        let url = rig.scratch.appending(path: "Dropped/made-up-1.md")
        #expect(await shelf.save(file(1), to: url) == .saved(url))
        #expect(await shelf.savedCopy("v-1") == url, "there, and asked off the main actor")
        silent.isOn = true
        let open = Task { await shelf.savedCopy("v-1") }
        await until { gate.hasEntered && rig.writeClock.pending == 1 }
        #expect(gate.ranOnMain == false)
        rig.writeClock.pass()
        #expect(await finished(open) == .some(nil))
        #expect(shelf.saved["v-1"] == url, "the copy may still be there: it is not forgotten")
        #expect(shelf.fileProblems["v-1"] == ShelfSaveError.folderDidNotRespond.errorDescription)
        // Asked again while the folder is held off: at once, with the folder's other sentence.
        #expect(await finished(Task { await shelf.savedCopy("v-1") }) == .some(nil))
        #expect(shelf.fileProblems["v-1"] == ShelfSaveError.folderStillSilent.errorDescription)
        #expect(shelf.saved["v-1"] == url)
        // The look returns: the folder answers, and the copy is found.
        silent.isOn = false
        gate.open()
        await until { !rig.writer.isHeldOff(url.deletingLastPathComponent()) }
        #expect(await shelf.savedCopy("v-1") == url)
        await until { rig.writer.isAtRest && rig.writeClock.pending == 0 }
    }
}

/// Names the blocking calls record from any thread.
private final class NameLog: @unchecked Sendable {
    private let lock = NSLock()
    private var added: [String] = []

    func add(_ name: String) { lock.lock(); added.append(name); lock.unlock() }
    var names: [String] { lock.lock(); defer { lock.unlock() }; return added }
}

/// A flag the blocking calls read from any thread.
private final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool

    init(_ on: Bool) { self.on = on }

    var isOn: Bool {
        get { lock.lock(); defer { lock.unlock() }; return on }
        set { lock.lock(); on = newValue; lock.unlock() }
    }
}

// MARK: Nothing in the Results code asks the disk on the main actor

struct ResultsDiskCallsTests {
    /// What each file of Results/ may say: calls made off the main actor, by
    /// the actor that owns the temporary copies, the default closures the
    /// writer runs on its queue, and the real listing. Anything else is a call
    /// that may block the main actor on a disk that has stopped answering.
    @Test func theOnlyFileSystemCallsAreTheOnesTheDiskLayerMakesOffTheMainActor() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/Results")
        // Every way the Results code reaches the file system: the file manager, the C calls, and reads of a URL.
        let calls = ["FileManager.default", "fileManager.", "opendir(", "readdir(", "Data(contentsOf", "String(contentsOf",
                     "resourceValues(", "FileHandle(", "NSWorkspace", "bookmarkData("]
        var found: [String: Int] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: base.path).sorted() where name.hasSuffix(".swift") {
            let text = try String(contentsOf: base.appending(path: name), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                for call in calls where code.contains(call) { found["\(name): \(call)", default: 0] += 1 }
            }
        }
        let allowed: [String: Int] = [
            // The default of `Dependencies.exists`: blocking, run only by ShelfSavedFiles on its queue.
            "ResultsShelf.swift: FileManager.default": 1,
            // The temporary copies' actor: its writes, checks and deletes run off the main actor.
            "ShelfTemporaryCopies.swift: FileManager.default": 7,
            "ShelfTemporaryCopies.swift: fileManager.": 4,
            "ShelfTemporaryCopies.swift: Data(contentsOf": 1,
            // The real listing `Dependencies.list` defaults to, run as `exists` is.
            "ShelfSaveAll.swift: opendir(": 1,
            "ShelfSaveAll.swift: readdir(": 1,
            // The Downloads folder's path for a panel to start in: a search-path lookup, not a look at the disk.
            "ResultsWindow.swift: FileManager.default": 1,
            // Open, Reveal in Finder and the Save All folder's Reveal: the path is handed to Finder or the
            // default app, after a look (through the writer) that the file is there.
            "ResultsWindow.swift: NSWorkspace": 3,
        ]
        #expect(found == allowed, "now: \(found.sorted { $0.key < $1.key })")
    }
}

// MARK: A seeded fuzz of both limits

/// SplitMix64: the same numbers for the same seed, on every run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    /// The seed is mixed first: neighbouring seeds would otherwise be one stream, shifted.
    init(seed: Int) {
        var z = UInt64(truncatingIfNeeded: seed) &+ 0x2545_F491_4F6C_DD1D
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        state = z ^ (z >> 31)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
struct ShelfLimitsFuzzTests {
    /// What a read of `key` answers when it answers (`HeldReader`).
    private func answer(of key: ArtifactRead) -> ArtifactReadOutcome {
        switch key {
        case .list: .list([])
        case .thumb: .bytes(webp)
        case .text: .unreadable
        case .download(let version): .bytes(Data("bytes of \(version)".utf8))
        }
    }

    @Test(arguments: 0..<30)
    func theQueueKeepsItsRulesUnderTimeLimitsCancellationsAndClosing(seed: Int) async {
        let queue = Queue()
        var random = SplitMix64(seed: seed)
        let keys: [ArtifactRead] = [download(1), download(2), download(3), download(4), list(1), list(2), thumb(1), thumb(2)]
        let priorities: [ShelfTransfers.Priority] = [.thumbnail, .list, .saveAll, .foreground]
        let finished = Box<[Bool]>([])
        var asked: [(key: ArtifactRead, task: Task<ShelfTransferResult, Never>)] = []
        for _ in 0..<300 {
            switch Int.random(in: 0..<14, using: &random) {
            case 0, 1, 2, 3:
                let key = keys.randomElement(using: &random)!
                let priority = priorities.randomElement(using: &random)!
                let keeps = Int.random(in: 0..<6, using: &random) == 0
                let index = asked.count
                finished.value.append(false)
                asked.append((key, Task {
                    let result = await queue.transfers.read(key, priority: priority, keepsOnClose: keeps)
                    finished.value[index] = true
                    return result
                }))
            case 4:
                if let index = asked.indices.filter({ !finished.value[$0] }).randomElement(using: &random) {
                    asked[index].task.cancel()
                }
            case 5, 6, 7:
                queue.reader.releaseOldest()
            case 8, 9:
                queue.reader.release(keys.randomElement(using: &random)!)
            case 10:
                if queue.clock.pending > 0 {
                    queue.clock.pass(nth: Int.random(in: 0..<queue.clock.pending, using: &random))
                }
            case 11:
                if Int.random(in: 0..<4, using: &random) == 0 { queue.transfers.close() }
            default:
                await turns(Int.random(in: 1...3, using: &random))
            }
            await turns(1)
            #expect(queue.transfers.active <= queue.transfers.limit)
            #expect(queue.reader.inFlight <= queue.transfers.active + queue.transfers.lost)
        }
        // Everything is let go and every limit passes: all rests.
        await until {
            queue.reader.releaseAll()
            queue.clock.pass()
            return finished.value.allSatisfy { $0 } && queue.transfers.active == 0 && queue.transfers.lost == 0
                && queue.transfers.queued == 0 && queue.clock.pending == 0 && queue.reader.inFlight == 0
        }
        #expect(queue.transfers.mostActive <= queue.transfers.limit)
        for (key, task) in asked {
            switch await task.value {
            case .answered(let outcome): #expect(outcome == answer(of: key), "an answer is its own read's")
            case .timedOut, .cancelled: break
            case .notReady: Issue.record("the page was up")
            }
        }
    }

    @Test(arguments: 0..<30)
    func theWriterKeepsItsRulesUnderTimeLimitsAndStuckFolders(seed: Int) async {
        let rig = WriterRig()
        var random = SplitMix64(seed: seed &+ 7_000)
        let folders = ["/made-up/a", "/made-up/b", "/Volumes/Disk/c"]
        let names = ["one.md", "two.md", "three.md", "four.md", "five.md"]
        let outcomes = Box<[SaveEnd?]>([])
        var tasks: [Task<Void, Never>] = []
        for _ in 0..<300 {
            switch Int.random(in: 0..<12, using: &random) {
            case 0, 1, 2, 3:
                let place = folders.randomElement(using: &random)!
                let path = place + "/" + names.randomElement(using: &random)!
                let refused = rig.writer.isPending(URL(fileURLWithPath: path)) || rig.writer.isHeldOff(folder(place))
                let index = tasks.count
                outcomes.value.append(nil)
                let save = rig.save(path, bytes: Int.random(in: 0..<(3 << 20), using: &random))
                tasks.append(Task {
                    outcomes.value[index] = await save.value
                })
                if refused {
                    // Held off, or the name has a call out: refused before any call.
                    await until { outcomes.value[index] != nil }
                    let reason = outcomes.value[index]?.reason
                    #expect(reason == .folderStillSilent || reason == .earlierSaveUnfinished,
                            "a refused save was refused without waiting")
                }
            case 4, 5:
                rig.calls.finishOldest()
            case 6, 7:
                if rig.calls.count > 0 { rig.calls.finish(at: Int.random(in: 0..<rig.calls.count, using: &random)) }
            case 8:
                if rig.clock.pending > 0 {
                    rig.clock.pass(nth: Int.random(in: 0..<rig.clock.pending, using: &random))
                }
            default:
                await turns(Int.random(in: 1...3, using: &random))
            }
            await turns(1)
        }
        await until {
            rig.calls.finishAll()
            rig.clock.pass()
            return outcomes.value.allSatisfy { $0 != nil } && rig.writer.isAtRest && rig.clock.pending == 0
                && rig.calls.count == 0
        }
        for task in tasks { await task.value }
        for case .failed(let error)? in outcomes.value {
            #expect(error is ShelfSaveError, "only the writer's own reasons: \(error)")
        }
        #expect(outcomes.value.count == tasks.count)
    }

    /// How a save or a look of the mixed fuzz ended.
    private enum Ended: Sendable {
        case save(SaveEnd)
        case look(LookEnd)
    }

    @Test(arguments: 0..<30)
    func theWriterKeepsItsRulesWithLooksAndGuardedWritesMixedIn(seed: Int) async {
        let rig = WriterRig()
        var random = SplitMix64(seed: seed &+ 11_000)
        let folders = ["/made-up/a", "/made-up/b", "/Volumes/Disk/c"]
        let names = ["one.md", "two.md", "three.md"]
        let outcomes = Box<[Ended?]>([])
        var tasks: [Task<Void, Never>] = []
        var cancels: [() -> Void] = []
        for _ in 0..<300 {
            switch Int.random(in: 0..<16, using: &random) {
            case 0, 1, 2, 3, 4, 5:
                let place = folders.randomElement(using: &random)!
                let path = place + "/" + names.randomElement(using: &random)!
                // Let the earlier asks make their calls first, so a new call is the new ask's.
                await turns(3)
                let callsBefore = rig.calls.count
                let heldOff = rig.writer.isHeldOff(folder(place))
                let pendingName = rig.writer.isPending(URL(fileURLWithPath: path))
                let index = outcomes.value.count
                outcomes.value.append(nil)
                let ask: Task<Ended, Never>
                let cancel: () -> Void
                var isSave = false
                switch Int.random(in: 0..<5, using: &random) {
                case 0:
                    let taken = Bool.random(using: &random)
                    let save = rig.save(path, unlessExists: { _ in taken })
                    ask = Task { .save(await save.value) }
                    cancel = { save.cancel() }
                    isSave = true
                case 1:
                    let look = rig.exists(path, answer: true)
                    ask = Task { .look(await look.value) }
                    cancel = { look.cancel() }
                case 2:
                    let look = rig.folderExists(place, answer: true)
                    ask = Task { .look(await look.value) }
                    cancel = { look.cancel() }
                case 3:
                    let shape = Int.random(in: 0..<3, using: &random)
                    let look = rig.names(in: place) { _ in
                        switch shape {
                        case 0: ["One.md"]
                        case 1: nil
                        default: throw CocoaError(.fileReadNoPermission)
                        }
                    }
                    ask = Task { .look(await look.value) }
                    cancel = { look.cancel() }
                default:
                    let save = rig.save(path)
                    ask = Task { .save(await save.value) }
                    cancel = { save.cancel() }
                    isSave = true
                }
                cancels.append(cancel)
                tasks.append(Task { outcomes.value[index] = await ask.value })
                if heldOff || (isSave && pendingName) {
                    // Held off, or the name has a call out: refused at once, and no call was made.
                    await until { outcomes.value[index] != nil }
                    #expect(rig.calls.count == callsBefore, "a refused ask made a call")
                    switch outcomes.value[index] {
                    case .save(let end)?:
                        #expect(end.reason == .folderStillSilent || end.reason == .earlierSaveUnfinished)
                    case .look(let end)?: #expect(end.reason == .folderStillSilent)
                    case nil: break
                    }
                }
            case 6, 7:
                rig.calls.finishOldest()
            case 8, 9:
                if rig.calls.count > 0 { rig.calls.finish(at: Int.random(in: 0..<rig.calls.count, using: &random)) }
            case 10, 11:
                if rig.clock.pending > 0 {
                    rig.clock.pass(nth: Int.random(in: 0..<rig.clock.pending, using: &random))
                }
            case 12:
                if let index = outcomes.value.indices.filter({ outcomes.value[$0] == nil }).randomElement(using: &random) {
                    cancels[index]()
                }
            default:
                await turns(Int.random(in: 1...3, using: &random))
            }
            await turns(1)
        }
        await until {
            rig.calls.finishAll()
            rig.clock.pass()
            return outcomes.value.allSatisfy { $0 != nil } && rig.writer.isAtRest && rig.clock.pending == 0
                && rig.calls.count == 0
        }
        for task in tasks { await task.value }
        for ended in outcomes.value {
            switch ended {
            case .save(let end)?:
                if case .failed(let error) = end { #expect(error is ShelfSaveError, "only the writer's own reasons: \(error)") }
            case .look(let end)?:
                switch end {
                case .exists(let there): #expect(there, "a look's answer is the disk's")
                case .names(let found): #expect(found == nil || found == ["one.md"])
                case .failed(let error): #expect(error is ShelfSaveError || error is CancellationError, "\(error)")
                }
            case nil: break
            }
        }
    }
}
