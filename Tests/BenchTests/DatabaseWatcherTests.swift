// DatabaseWatcherTests.swift — what the database watcher does while the
// daemon's write-ahead log isn't there: it looks again after two seconds, then
// four, up to a minute (a test supplies the timer and fires it itself), and it
// also watches the log's folder, so a log that appears is picked up at once,
// not at the next look. Real temporary folders and real kqueue events (they
// arrive within milliseconds; waits are bounded and only for those), made-up
// databases, never the daemon's.
import Foundation
import Testing
@testable import Bench

/// The timer, in the test's hands: every retry the watcher asks for.
private final class Retries: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: [@Sendable () -> Void] = []
    private var asked: [TimeInterval] = []

    func add(_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        asked.append(delay)
        scheduled.append(work)
    }

    /// The delays asked for, in order.
    var delays: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return asked }

    /// Fires the retry asked for `index`th (the last by default), as the timer would, on the watcher's queue.
    func fire(_ index: Int? = nil, on queue: DispatchQueue) {
        lock.lock()
        let at = index ?? scheduled.count - 1
        let work = scheduled.indices.contains(at) ? scheduled[at] : nil
        lock.unlock()
        queue.sync { work?() }
    }
}

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    func bump() { lock.lock(); total += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return total }
}

/// A folder of its own, standing in for the daemon's data folder.
private struct Folder {
    let url: URL
    var database: URL { url.appendingPathComponent("science.db") }
    var log: URL { url.appendingPathComponent("science.db-wal") }

    init(creating: Bool = true) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString)")
        if creating { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }

    func makeLog() { FileManager.default.createFile(atPath: log.path, contents: Data("x".utf8)) }
    func removeLog() { try? FileManager.default.removeItem(at: log) }
    func removeAll() { try? FileManager.default.removeItem(at: url) }

    func write(to file: URL? = nil) throws {
        let handle = try FileHandle(forWritingTo: file ?? log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("more".utf8))
        try handle.close()
    }
}

private func eventually(_ seconds: Double = 5, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func makeWatcher(_ folder: Folder, queue: DispatchQueue, retries: Retries, reports: Reports) -> DatabaseWatcher {
    DatabaseWatcher(database: folder.database, interval: 0, queue: queue, backoff: RetryBackoff(),
                    schedule: { retries.add($0, $1) }, onChange: { reports.bump() })
}

struct RetryBackoffTests {
    @Test func twoSecondsDoublingToAMinuteThenStaying() {
        var backoff = RetryBackoff()
        #expect((0..<9).map { _ in backoff.advance() } == [2, 4, 8, 16, 32, 60, 60, 60, 60])
    }

    @Test func resettingStartsOverFromTwoSeconds() {
        var backoff = RetryBackoff()
        for _ in 0..<7 { _ = backoff.advance() }
        backoff.reset()
        #expect((0..<3).map { _ in backoff.advance() } == [2, 4, 8])
    }
}

struct DatabaseWatcherTests {
    private let queue = DispatchQueue(label: "DatabaseWatcherTests")

    @Test func aLogThatIsThereIsWatchedAtOnceWithNothingToRetry() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        folder.makeLog()
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        #expect(watcher.isWatching)
        #expect(retries.delays.isEmpty)
        try folder.write()
        #expect(await eventually { reports.count == 1 })
        watcher.stop()
        #expect(!watcher.isWatching)
    }

    @Test func aMissingLogIsLookedForAtTwoSecondsThenFourThenDoublingToAMinute() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        #expect(!watcher.isWatching)
        #expect(retries.delays == [2])
        for _ in 0..<8 { retries.fire(on: queue) }
        #expect(retries.delays == [2, 4, 8, 16, 32, 60, 60, 60, 60])
        #expect(!watcher.isWatching)
        watcher.stop()
    }

    @Test func aMissingFolderBacksOffTheSameWay() async throws {
        let folder = try Folder(creating: false)
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        #expect(retries.delays == [2])
        for _ in 0..<6 { retries.fire(on: queue) }
        #expect(retries.delays == [2, 4, 8, 16, 32, 60, 60])
        // The folder and the log appear; the next look finds it.
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        defer { folder.removeAll() }
        folder.makeLog()
        retries.fire(on: queue)
        #expect(watcher.isWatching)
        #expect(retries.delays.count == 7, "a log that opens asks for no more looks")
        watcher.stop()
    }

    @Test func aLogThatAppearsIsPickedUpAtOnceWithoutWaitingForTheTimer() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        #expect(!watcher.isWatching)
        folder.makeLog()
        // The timer is never fired: the folder's own event does it.
        #expect(await eventually { watcher.isWatching })
        // And it is the log that is watched now: a write is reported.
        try folder.write()
        #expect(await eventually { reports.count == 1 })
        // The timer, firing late, finds nothing to do and asks for nothing.
        retries.fire(on: queue)
        #expect(retries.delays == [2])
        #expect(watcher.isWatching)
        watcher.stop()
    }

    @Test func otherFilesComingAndGoingCostALookAndNothingElse() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        let other = folder.url.appendingPathComponent("journal")
        for _ in 0..<5 {
            FileManager.default.createFile(atPath: other.path, contents: Data())
            try? FileManager.default.removeItem(at: other)
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(!watcher.isWatching)
        #expect(retries.delays == [2], "no extra timer, and the delay did not move on")
        // The watch is still alive after all that.
        folder.makeLog()
        #expect(await eventually { watcher.isWatching })
        watcher.stop()
    }

    @Test func losingTheLogReportsOnceAndStartsTheDelayOverFromTwoSeconds() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        // Three looks that find nothing: 2, 4, 8 asked for.
        retries.fire(on: queue)
        retries.fire(on: queue)
        #expect(retries.delays == [2, 4, 8])
        // The log appears and the timer finds it.
        folder.makeLog()
        retries.fire(on: queue)
        #expect(watcher.isWatching)
        // The daemon stops: the log goes.
        folder.removeLog()
        #expect(await eventually { reports.count == 1 })
        #expect(await eventually { !watcher.isWatching && retries.delays.count == 4 })
        #expect(retries.delays == [2, 4, 8, 2], "after a success the next wait starts at two seconds again")
        watcher.stop()
    }

    @Test func aTimerLeftOverFromBeforeTheLogCameDoesNotStartASecondChain() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        #expect(retries.delays == [2])
        // The log comes (by the folder's event, so the timer is left waiting)
        // and goes again, which asks for a timer of its own.
        folder.makeLog()
        #expect(await eventually { watcher.isWatching })
        folder.removeLog()
        #expect(await eventually { !watcher.isWatching && retries.delays.count == 2 })
        #expect(retries.delays == [2, 2])
        // The first timer fires now: it was set before, so it does nothing.
        retries.fire(0, on: queue)
        #expect(retries.delays == [2, 2])
        // The second is the one that counts, and goes on from two seconds.
        retries.fire(1, on: queue)
        #expect(retries.delays == [2, 2, 4])
        watcher.stop()
    }

    @Test func aLogThatComesBackAfterTheDaemonRestartsIsWatchedAgain() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        folder.makeLog()
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        folder.removeLog()
        #expect(await eventually { reports.count == 1 && !watcher.isWatching })
        folder.makeLog()
        #expect(await eventually { watcher.isWatching })
        try folder.write()
        #expect(await eventually { reports.count == 2 })
        watcher.stop()
    }

    @Test func stoppingEndsBothWatchesAndTheTimer() async throws {
        let folder = try Folder()
        defer { folder.removeAll() }
        let retries = Retries(), reports = Reports()
        let watcher = makeWatcher(folder, queue: queue, retries: retries, reports: reports)
        watcher.stop()
        folder.makeLog()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!watcher.isWatching, "the folder watch is gone")
        retries.fire(on: queue)
        #expect(!watcher.isWatching, "and the timer does nothing")
        #expect(retries.delays == [2])
    }
}
