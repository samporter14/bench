// SQLiteReaderTests.swift — the one read-only connection Bench reads Claude
// Science's database through, and the sessions poll it runs, against made-up
// databases built here (`MadeUpDatabase`). Nothing reads the real database.
import Foundation
import Testing
@testable import Bench

/// A made-up database with one table and one row holding `value`.
private func tinyDatabase(_ value: String, at url: URL) throws {
    let make = Process()
    make.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    make.arguments = [url.path, "CREATE TABLE t(v TEXT); INSERT INTO t VALUES (\(MadeUpDatabase.quote(value)));"]
    try make.run()
    make.waitUntilExit()
    #expect(make.terminationStatus == 0)
}

/// Runs `sql` with `/usr/bin/sqlite3`, read-write, as another process: the
/// daemon's part in these tests. Returns what it printed.
@discardableResult
private func writer(_ url: URL, _ sql: String) throws -> String {
    let run = Process()
    run.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    run.arguments = [url.path, sql]
    let out = Pipe()
    run.standardOutput = out
    try run.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    run.waitUntilExit()
    #expect(run.terminationStatus == 0)
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

@Suite(.serialized)
struct SQLiteReaderTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func remove() { try? FileManager.default.removeItem(at: dir) }

    @Test func aWriteFailsAndChangesNothing() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try tinyDatabase("one", at: db)
        let reader = SQLiteReader()
        for write in ["INSERT INTO t VALUES ('two');", "UPDATE t SET v = 'changed';", "DELETE FROM t;",
                      "CREATE TABLE u(x);", "DROP TABLE t;", "PRAGMA user_version = 7;"] {
            #expect(throws: ScienceError.self, "\(write)") { try reader.rows(db: db, sql: write) }
        }
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
        #expect(try reader.rows(db: db, sql: "PRAGMA user_version;") == [["0"]])
    }

    @Test func valuesAreBoundNeverRunAsSQL() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try tinyDatabase("it's", at: db)
        let reader = SQLiteReader()
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t WHERE v = ?1;", arguments: [.text("it's")]) == [["it's"]])
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t WHERE v = ?1;", arguments: [.text("x' OR '1'='1")]).isEmpty)
        #expect(try reader.rows(db: db, sql: "SELECT ?1 + 1, ?2, NULL;", arguments: [.integer(41), .text("")]) == [["42", "", ""]])
    }

    @Test func oneConnectionServesEveryRead() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try tinyDatabase("one", at: db)
        let reader = SQLiteReader()
        for _ in 0..<20 { #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]]) }
        #expect(reader.openCount == 1)
        // Another process's write is seen on the same connection.
        try writer(db, "INSERT INTO t VALUES ('two');")
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t ORDER BY v;") == [["one"], ["two"]])
        #expect(reader.openCount == 1)
    }

    @Test func anErrorMeansANewConnectionAndTheNextReadWorks() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try tinyDatabase("one", at: db)
        let reader = SQLiteReader()
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
        #expect(reader.openCount == 1)
        // Tried on the open connection, then once more on a fresh one.
        #expect(throws: ScienceError.self) { try reader.rows(db: db, sql: "SELECT nothing FROM nowhere;") }
        #expect(reader.openCount == 2)
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
        #expect(reader.openCount == 3)
    }

    @Test func aReplacedDatabaseIsOpenedAgain() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        let other = dir.appendingPathComponent("other.db")
        try tinyDatabase("old", at: db)
        try tinyDatabase("new", at: other)
        let reader = SQLiteReader()
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["old"]])
        // Another file at the same path: another inode.
        #expect(rename(other.path, db.path) == 0)
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["new"]])
        #expect(reader.openCount == 2)
    }

    @Test func somethingThatIsntADatabaseFailsUntilOneIsThere() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try Data("not a database, not at all, just text".utf8).write(to: db)
        let reader = SQLiteReader()
        #expect(throws: ScienceError.self) { try reader.rows(db: db, sql: "SELECT v FROM t;") }
        let good = dir.appendingPathComponent("good.db")
        try tinyDatabase("found", at: good)
        #expect(rename(good.path, db.path) == 0)
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["found"]])
        // And no database at all is an error, not a new empty one.
        let missing = dir.appendingPathComponent("missing.db")
        #expect(throws: ScienceError.self) { try reader.rows(db: missing, sql: "SELECT 1;") }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func anotherDatabaseIsAnotherConnection() throws {
        defer { remove() }
        let first = dir.appendingPathComponent("first.db")
        let second = dir.appendingPathComponent("second ? # % odd.db")
        try tinyDatabase("first", at: first)
        try tinyDatabase("second", at: second)
        let reader = SQLiteReader()
        #expect(try reader.rows(db: first, sql: "SELECT v FROM t;") == [["first"]])
        #expect(try reader.rows(db: second, sql: "SELECT v FROM t;") == [["second"]])
        #expect(try reader.rows(db: first, sql: "SELECT v FROM t;") == [["first"]])
        #expect(reader.openCount == 3)
    }

    @Test func aReadHoldsNothingOpenBetweenReads() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try writer(db, "PRAGMA journal_mode=WAL; CREATE TABLE t(v TEXT); INSERT INTO t VALUES ('one');")
        let reader = SQLiteReader()
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
        // A writer's full checkpoint isn't held up by Bench: its first
        // column, "busy", is 0.
        let checkpoint = try writer(db, "PRAGMA journal_mode=WAL; INSERT INTO t VALUES ('two'); PRAGMA wal_checkpoint(TRUNCATE);")
        #expect(checkpoint.split(separator: "\n").last?.hasPrefix("0|") == true, "\(checkpoint)")
        #expect(try reader.rows(db: db, sql: "SELECT COUNT(*) FROM t;") == [["2"]])
    }

    @Test func aReadThatRunsTooLongIsStopped() throws {
        defer { remove() }
        let db = dir.appendingPathComponent("made-up.db")
        try tinyDatabase("one", at: db)
        let reader = SQLiteReader()
        let forever = "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) SELECT COUNT(*) FROM n;"
        let start = Date()
        #expect(throws: ScienceError.databaseUnreadable("query timed out")) {
            try reader.rows(db: db, sql: forever, timeout: 0.2)
        }
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
    }
}

// MARK: The sessions poll

/// The poll as Bench 0.5.0 ran it, word for word: every root ordered by its
/// tree's latest write, the JSON read for each. The new poll must give
/// exactly its rows, in its order.
private enum PollBefore {
    static func oneLine(_ c: String) -> String {
        "replace(replace(replace(COALESCE(\(c),''), char(10), ' '), char(13), ' '), char(31), ' ')"
    }
    static func output(_ a: String) -> String {
        "COALESCE(\(a).output_data, (SELECT b.body FROM frame_blobs b WHERE b.frame_id = \(a).id AND b.kind = 'output'))"
    }
    static func pendingInput(_ a: String) -> String {
        "COALESCE(json_array_length(CASE WHEN json_valid(\(output(a))) THEN \(output(a)) END, '$.pending_input_requests'), 0) > 0"
    }
    static func pendingKind(_ a: String) -> String {
        "json_extract(CASE WHEN json_valid(\(output(a))) THEN \(output(a)) END, '$.pending_input_requests[0].kind')"
    }
    static func sql(limit: Int) -> String {
        let awaiting = "'awaiting_user_response','awaiting_plan_approval'"
        return """
            SELECT f.id, COALESCE(f.project_id,''), \(oneLine("f.name")), f.status,
                   f.created_at, f.updated_at, COALESCE(f.completed_at,''),
                   MAX(f.created_at, COALESCE(f.last_user_message_at, 0)),
                   CASE WHEN f.status = 'processing' AND (\(pendingInput("f")) OR EXISTS (
                       SELECT 1 FROM frames c
                       WHERE c.root_frame_id = f.id AND c.parent_frame_id IS NOT NULL
                         AND c.is_hidden IS NOT 1
                         AND (c.status IN (\(awaiting))
                              OR (c.status = 'processing' AND \(pendingInput("c"))))
                   )) THEN 1 ELSE 0 END,
                   (SELECT COALESCE(SUM(COALESCE(c.input_tokens, 0) + COALESCE(c.output_tokens, 0)), 0)
                    FROM frames c WHERE c.root_frame_id = f.id),
                   CASE WHEN f.status = 'awaiting_user_response' THEN COALESCE(NULLIF(\(pendingKind("f")), 'ask'), f.status)
                        WHEN f.status IN (\(awaiting)) THEN f.status
                        WHEN f.status = 'processing' THEN COALESCE(\(pendingKind("f")), (
                            SELECT CASE WHEN c.status = 'awaiting_user_response'
                                        THEN COALESCE(NULLIF(\(pendingKind("c")), 'ask'), c.status)
                                        WHEN c.status IN (\(awaiting)) THEN c.status ELSE \(pendingKind("c")) END
                            FROM frames c
                            WHERE c.root_frame_id = f.id AND c.parent_frame_id IS NOT NULL
                              AND c.is_hidden IS NOT 1
                              AND (c.status IN (\(awaiting))
                                   OR (c.status = 'processing' AND \(pendingInput("c"))))
                            ORDER BY c.updated_at DESC LIMIT 1))
                   END
            FROM frames f
            WHERE f.parent_frame_id IS NULL AND f.is_hidden IS NOT 1 AND f.conversation_type != 'uploads'
              AND f.agent_name NOT IN ('CONCIERGE','CANVAS_CONCIERGE')
            ORDER BY f.status IN ('processing',\(awaiting)) DESC,
                     MAX(f.updated_at, COALESCE((SELECT MAX(c.updated_at) FROM frames c
                         WHERE c.root_frame_id = f.id AND c.parent_frame_id IS NOT NULL), 0)) DESC
            LIMIT \(max(1, min(limit, 50)));
            """
    }

    static func rows(db: URL, limit: Int) throws -> [FrameRow] {
        try runReadOnlyQuery(db: db, sql: sql(limit: limit)).compactMap { cols in
            guard cols.count >= 10 else { return nil }
            let created = Int64(cols[4]) ?? 0
            return FrameRow(id: cols[0], projectID: cols[1], name: cols[2], status: cols[3],
                            createdMs: created, updatedMs: Int64(cols[5]) ?? 0,
                            completedMs: cols[6].isEmpty ? nil : Int64(cols[6]),
                            turnStartedMs: Int64(cols[7]) ?? created, hasPendingInput: cols[8] == "1",
                            tokens: Int64(cols[9]) ?? 0,
                            waitingSignal: cols.count > 10 && !cols[10].isEmpty ? cols[10] : nil)
        }
    }
}

@Suite(.serialized)
struct SessionsPollTests {
    /// Sixty made-up sessions with three helpers each: every status, pending
    /// requests on roots and on helpers (live, parked, a question), output in
    /// the row, in a blob or broken, hidden and nested helpers, sessions the
    /// list leaves out, and old sessions whose helper wrote last of all. Every
    /// time is distinct, so the order has no ties.
    private static func busyDatabase() throws -> MadeUpDatabase {
        let db = try MadeUpDatabase()
        try db.run("""
            WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 60)
            INSERT INTO frames
            SELECT printf('00000000-0000-4000-8000-%012x', i), 'proj_' || (i % 4),
                   CASE WHEN i % 10 = 0 THEN 'Two' || char(10) || 'lines' ELSE 'Session ' || i END,
                   CASE WHEN i = 59 THEN NULL
                        WHEN i % 11 = 0 THEN 'processing' WHEN i % 13 = 0 THEN 'awaiting_user_response'
                        WHEN i % 17 = 0 THEN 'awaiting_plan_approval' WHEN i % 7 = 0 THEN 'failed'
                        ELSE 'completed' END,
                   1000000 + i * 1000, CASE WHEN i = 58 THEN NULL ELSE 1000000 + i * 1000 + (i * 37) % 500 END,
                   CASE WHEN i % 3 = 0 THEN NULL ELSE 1000000 + i * 1000 + 600 END,
                   CASE WHEN i % 2 = 0 THEN 1000000 + i * 1000 + 5 END,
                   printf('00000000-0000-4000-8000-%012x', i), NULL, i * 10, i, CASE WHEN i = 47 THEN 1 ELSE 0 END,
                   CASE WHEN i = 22 THEN '{"pending_input_requests":[{"kind":"local_exec","mode":"live"}]}'
                        WHEN i = 26 THEN '{"pending_input_requests":[{"kind":"network","mode":"parked"}]}'
                        WHEN i = 39 THEN '{"pending_input_requests":[{"kind":"ask","mode":"parked"}]}'
                        WHEN i = 52 THEN NULL WHEN i = 44 THEN '{broken'
                        ELSE '{"response":"SECRET"}' END,
                   '{"request":"SECRET"}', 'SECRET', CASE WHEN i = 49 THEN 'uploads' ELSE 'chat' END,
                   CASE WHEN i = 50 THEN 'CONCIERGE' WHEN i = 51 THEN 'CANVAS_CONCIERGE' ELSE 'OPERON' END, 'SECRET'
            FROM n;
            INSERT INTO frame_blobs VALUES (printf('00000000-0000-4000-8000-%012x', 52), 'output',
                '{"pending_input_requests":[{"kind":"host","mode":"parked"}]}');
            WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 60),
                 k(j) AS (VALUES (1), (2), (3))
            INSERT INTO frames
            SELECT printf('10000000-0000-4000-8000-%08x%04x', i, j), 'proj_' || (i % 4), 'Helper',
                   CASE WHEN i IN (33, 55) AND j = 1 THEN 'awaiting_user_response'
                        WHEN i IN (11, 33) AND j = 2 THEN 'processing'
                        WHEN i = 44 AND j = 3 THEN 'awaiting_plan_approval'
                        WHEN i = 22 AND j = 1 THEN 'awaiting_user_response'
                        ELSE 'completed' END,
                   1000000 + i * 1000 + j,
                   CASE WHEN i % 9 = 0 AND j = 3 THEN 1060000 + i * 7 + j ELSE 1000000 + i * 1000 + (i * 37) % 500 + 10 + j END,
                   NULL, NULL, printf('00000000-0000-4000-8000-%012x', i),
                   CASE WHEN j = 3 AND i % 5 = 0 THEN printf('10000000-0000-4000-8000-%08x%04x', i, 1)
                        ELSE printf('00000000-0000-4000-8000-%012x', i) END,
                   100 + j, 10 + j, CASE WHEN i = 22 AND j = 1 THEN 1 ELSE 0 END,
                   CASE WHEN i = 33 AND j = 1 THEN '{"pending_input_requests":[{"kind":"ask","mode":"parked"}]}'
                        WHEN i = 55 AND j = 1 THEN '{"pending_input_requests":[{"kind":"mcp_tool","mode":"parked"}]}'
                        WHEN i IN (11, 33) AND j = 2 THEN '{"pending_input_requests":[{"kind":"local_exec","mode":"live"}]}'
                        ELSE '{"response":"SECRET"}' END,
                   '{"request":"SECRET"}', NULL, 'chat', 'OPERON', 'SECRET'
            FROM n, k;
            """)
        return db
    }

    private func check(_ db: MadeUpDatabase, limits: [Int] = [1, 2, 3, 5, 8, 25, 50], note: String) throws {
        for limit in limits {
            let before = try PollBefore.rows(db: db.url, limit: limit)
            let now = try fetchRecentFrames(db: db.url, limit: limit)
            #expect(now == before, "\(note), limit \(limit)")
            #expect(now.count == min(limit, before.count))
        }
    }

    @Test func thePollGivesExactlyWhatItGaveBeforeWhateverTheIndexes() throws {
        let db = try Self.busyDatabase()
        defer { db.remove() }
        let rows = try fetchRecentFrames(db: db.url)
        // The made-up data covers what the poll must get right.
        #expect(rows.contains { $0.hasPendingInput && $0.waitingSignal == "mcp_tool" })
        #expect(rows.contains { $0.waitingSignal == "network" })
        #expect(rows.contains { $0.status == "awaiting_user_response" && $0.waitingSignal == "awaiting_user_response" })
        #expect(rows.contains { $0.waitingSignal == "awaiting_plan_approval" })
        #expect(rows.contains { $0.name == "Two lines" })
        try check(db, note: "no indexes")
        try db.run("CREATE INDEX f_root ON frames(root_frame_id); CREATE INDEX f_parent ON frames(parent_frame_id);")
        try check(db, note: "root and parent indexes")
        try db.run("CREATE INDEX f_updated ON frames(updated_at);")
        try check(db, note: "and updated_at")
        try db.run("CREATE INDEX f_status ON frames(status); CREATE INDEX b_frame ON frame_blobs(frame_id, kind);")
        try check(db, note: "and status")
    }

    @Test func eachWayOfPickingGivesTheSameRows() throws {
        let db = try Self.busyDatabase()
        defer { db.remove() }
        try db.run("CREATE INDEX f_updated ON frames(updated_at); CREATE INDEX f_status ON frames(status);")
        for limit in [1, 4, 25] {
            let before = try PollBefore.rows(db: db.url, limit: limit)
            for (byTime, byStatus) in [(false, false), (true, false), (true, true)] {
                let rows = try runReadOnlyQuery(db: db.url, sql: sessionsPollSQL(byTime: byTime, byStatus: byStatus),
                                                arguments: [.integer(Int64(limit))])
                #expect(rows.map(\.first) == before.map(\.id), "byTime \(byTime), byStatus \(byStatus), limit \(limit)")
            }
        }
    }

    @Test func aRootWithoutAStatusComesLastWhenThereIsRoom() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.frame(madeUpID(1), status: "completed", updated: 1_791_800_000_003)
        try db.frame(madeUpID(2), status: "processing", updated: 1_791_800_000_001)
        try db.run("""
            \(MadeUpDatabase.frameSQL(madeUpID(3), created: 1_791_800_000_000, updated: 1_791_800_000_009))
            UPDATE frames SET status = NULL WHERE id = '\(madeUpID(3))';
            """)
        try check(db, limits: [1, 2, 3, 25], note: "a root without a status")
        #expect(try fetchRecentFrames(db: db.url).map(\.id) == [madeUpID(2), madeUpID(1), madeUpID(3)])
    }

    @Test func aHelpersLateWriteLiftsItsSession() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        for n in 1...6 { try db.frame(madeUpID(n), updated: 1_791_800_000_000 + Int64(n) * 1000) }
        // The oldest session's helper wrote after every session's own write.
        try db.frame(madeUpID(100), updated: 1_791_800_009_000, parent: madeUpID(1))
        try check(db, limits: [1, 2, 3, 6], note: "a late helper")
        #expect(try fetchRecentFrames(db: db.url, limit: 2).map(\.id) == [madeUpID(1), madeUpID(6)])
    }
}

// MARK: Letting go, and hearing the daemon go

@Suite(.serialized)
struct LettingGoTests {
    @Test func theConnectionIsLetGoWhenNoReadComes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-idle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("made-up.db")
        try tinyDatabase("one", at: db)
        // Generous times: the suite runs in parallel, and a loaded machine stretches sleeps.
        let reader = SQLiteReader(idleClose: 1.5)
        // Reads that keep coming keep it.
        for _ in 0..<4 {
            #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.openCount == 1)
        // A pause longer than the idle time lets it go; the next read opens it again.
        try await Task.sleep(for: .milliseconds(3_500))
        #expect(try reader.rows(db: db, sql: "SELECT v FROM t;") == [["one"]])
        #expect(reader.openCount == 2)
    }
}

@MainActor
struct ProcessExitWatcherTests {
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func anExitIsHeardOnce() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        var heard = 0
        let watcher = ProcessExitWatcher(pid: child.processIdentifier) { heard += 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(heard == 0)
        child.terminate()
        try await until { heard > 0 }
        #expect(heard == 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(heard == 1)
        _ = watcher
    }

    @Test func aProcessAlreadyGoneIsHeardAtOnce() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        var heard = 0
        let watcher = ProcessExitWatcher(pid: child.processIdentifier) { heard += 1 }
        try await until { heard > 0 }
        #expect(heard == 1)
        _ = watcher
    }

    @Test func aStoppedWatcherHearsNothing() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        var heard = 0
        let watcher = ProcessExitWatcher(pid: child.processIdentifier) { heard += 1 }
        watcher.stop()
        child.terminate()
        child.waitUntilExit()
        try await Task.sleep(for: .milliseconds(200))
        #expect(heard == 0)
    }
}
