import Foundation
import SQLite3
import Testing
@testable import Bench

/// Keep blocking semaphore waits off Swift's cooperative executor.
private func waitForQuerySignal(_ signal: DispatchSemaphore) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let outcome = signal.wait(timeout: .now() + 5)
            #expect(outcome == .success, "A query test gate did not receive its signal")
            continuation.resume()
        }
    }
}

/// These tests hold only their own reader queue. No daemon, live database or
/// timing assumption about how long a real query normally takes is involved.
@Suite(.serialized)
struct QueryCancellationTests {
    private func database() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-cancellation-\(UUID()).db")
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "CREATE TABLE t(v); INSERT INTO t VALUES (1);", nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func queueTimeCountsAndExpiredWorkNeverOpensTheDatabase() throws {
        let db = try database()
        defer { try? FileManager.default.removeItem(at: db) }
        let queue = DispatchQueue(label: "capsid.test.held-reader")
        let reader = SQLiteReader(queue: queue)
        let held = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        queue.async {
            held.signal()
            // A safety bound makes a broken implementation fail, not hang.
            _ = release.wait(timeout: .now() + 2)
        }
        held.wait()
        // The old reader would wait through the blocker, then succeed: its
        // timeout began only after reaching the front of the queue.
        let result = Result { try reader.rows(db: db, sql: "SELECT v FROM t", timeout: 0.02) }
        release.signal()
        #expect(throws: ScienceError.databaseUnreadable("query timed out")) { try result.get() }
        // Reading this property drains the skipped queued request first.
        #expect(reader.openCount == 0)
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t") == [["1"]])
    }

    @Test func cancellationBeforeEnqueueDoesNoDatabaseWork() throws {
        let db = try database()
        defer { try? FileManager.default.removeItem(at: db) }
        let reader = SQLiteReader()
        let cancellation = SQLiteReadCancellation()
        cancellation.cancel()
        #expect(throws: CancellationError.self) {
            try reader.rows(db: db, sql: "SELECT v FROM t", cancellation: cancellation)
        }
        #expect(reader.openCount == 0)
    }

    @Test func aCancelledCallerCanLeaveWhileAnotherReadHoldsTheQueue() async throws {
        let db = try database()
        defer { try? FileManager.default.removeItem(at: db) }
        let queue = DispatchQueue(label: "capsid.test.cancelled-reader")
        let reader = SQLiteReader(queue: queue)
        let cancellation = SQLiteReadCancellation()
        let entered = DispatchSemaphore(value: 0)
        queue.suspend()
        let read = Task.detached {
            entered.signal()
            return Result { try reader.rows(db: db, sql: "SELECT v FROM t", timeout: 1,
                                            cancellation: cancellation) }
        }
        await waitForQuerySignal(entered)
        cancellation.cancel()
        let result = await read.value
        queue.resume()
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(reader.openCount == 0)
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t") == [["1"]])
    }

    @Test func anExpiredRunningStatementDoesNotHoldUpTheNextRead() throws {
        let db = try database()
        defer { try? FileManager.default.removeItem(at: db) }
        let reader = SQLiteReader()
        // No finite answer: a progress callback must stop SQLite, not merely
        // let the timed-out caller leave its expensive statement running.
        let forever = "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) SELECT COUNT(*) FROM n"
        #expect(throws: ScienceError.databaseUnreadable("query timed out")) {
            try reader.rows(db: db, sql: forever, timeout: 0.05)
        }
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t", timeout: 2) == [["1"]])
    }

    @Test func aCancelledReadLeavesTheConnectionForTheNextRead() throws {
        let db = try database()
        defer { try? FileManager.default.removeItem(at: db) }
        let reader = SQLiteReader()
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t") == [["1"]])
        #expect(reader.openCount == 1)
        // No finite answer, so the cancellation lands while SQLite runs the
        // statement and its progress callback is what stops it.
        let forever = "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) SELECT COUNT(*) FROM n"
        let cancellation = SQLiteReadCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancellation.cancel() }
        #expect(throws: CancellationError.self) {
            try reader.rows(db: db, sql: forever, timeout: 5, cancellation: cancellation)
        }
        // Whoever cancelled (a Quick Open search a newer keystroke replaced)
        // asked for the stop; nothing was wrong with the connection, so the
        // next read is not made to open the database again.
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t") == [["1"]])
        #expect(reader.openCount == 1)
        #expect(reader.isOpen)
    }

    @Test func aReadRunsAtItsCallersPriority() throws {
        let db = try database()
        defer { try? FileManager.default.removeItem(at: db) }
        let probe = PriorityProbe()
        // The idle-close scheduler is called on the queue, inside the read's
        // own block, so it sees the priority that block runs at.
        let reader = SQLiteReader(schedule: { _, _, _ in probe.record() })
        let finished = DispatchSemaphore(value: 0)
        let rows = ResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            rows.store(Result { try reader.rows(db: db, sql: "SELECT v FROM t") })
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(try rows.value() == [["1"]])
        // The reader's queue is utility; a user-initiated search is not made to
        // wait at that priority.
        #expect(probe.classes == [QOS_CLASS_USER_INITIATED])
    }

    @Test func sessionNameSearchPassesItsCancellationToTheReader() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        let cancellation = SQLiteReadCancellation()
        cancellation.cancel()
        #expect(throws: CancellationError.self) {
            try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 30, cancellation: cancellation)
        }
    }
}

/// What priority a read's block ran at, noted from inside it.
private final class PriorityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [qos_class_t] = []

    func record() { lock.withLock { seen.append(qos_class_self()) } }
    var classes: [qos_class_t] { lock.withLock { seen } }
}

/// A read's answer, handed from the thread that asked to the test.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[[String]], any Error>?

    func store(_ value: Result<[[String]], any Error>) { lock.withLock { result = value } }
    func value() throws -> [[String]] { try lock.withLock { result! }.get() }
}

private final class SearchCancellationProbe: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var cancellation: SQLiteReadCancellation?

    func read(_ token: SQLiteReadCancellation) -> [BrowseRow] {
        lock.withLock { cancellation = token }
        entered.signal()
        _ = release.wait(timeout: .now() + 5)
        return []
    }

    var isCancelled: Bool { lock.withLock { cancellation?.isCancelled == true } }
}

struct QuickOpenDatabaseCancellationTests {
    @Test func cancellingTheAskingTaskCancelsItsDetachedDatabaseRead() async {
        let probe = SearchCancellationProbe()
        let task = Task {
            await QuickOpenSearch.databaseRows(["gel"], resolve: { URL(fileURLWithPath: "/made-up.db") },
                                               read: { _, _, token in probe.read(token) })
        }
        await waitForQuerySignal(probe.entered)
        task.cancel()
        #expect(probe.isCancelled)
        probe.release.signal()
        _ = await task.value
    }

    @Test func aTaskCancelledBeforeItStartsNeverResolvesTheDatabase() async {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let task = Task.detached {
            entered.signal()
            await waitForQuerySignal(release)
            return await QuickOpenSearch.databaseRows(["gel"], resolve: {
                Issue.record("A cancelled search must not resolve or open the database")
                return nil
            })
        }
        await waitForQuerySignal(entered)
        task.cancel()
        release.signal()
        #expect(await task.value == nil)
    }
}
