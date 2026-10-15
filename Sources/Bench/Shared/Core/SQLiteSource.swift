// SQLiteSource.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.
//
// Reads the daemon's SQLite database through the system SQLite library, on
// one read-only connection kept open while reads keep coming (`SQLiteReader`;
// until Bench 0.5.0 every query ran `/usr/bin/sqlite3` afresh). Metadata only: ids,
// names, statuses, timestamps. Never input_data / output_data / task_summary /
// payload bodies; the one look at an output is a count of its pending input
// requests and the first one's kind, taken inside SQLite (see
// `pendingInputSQL`).

import Foundation
import SQLite3

/// The org database the daemon is using, without guessing where its data
/// lives (Bench's version; the droplet's looked only in ~/.claude-science):
///
/// 1. The folder the daemon's own `status` names (`data_dir`), then
///    ~/.claude-science.
/// 2. In it, the org in `active-org.json`, unless another org's database has
///    been written clearly more recently: that one is the live one.
func resolveDatabase() -> URL? {
    let home = URL(fileURLWithPath: NSHomeDirectory() + "/.claude-science")
    var bases: [URL] = []
    if let known = ScienceDataDirectory.current { bases.append(known.standardizedFileURL) }
    if !bases.contains(home.standardizedFileURL) { bases.append(home) }
    for base in bases {
        if let db = orgDatabases(in: base).picked { return db }
    }
    return nil
}

/// One org's database in a data folder.
struct OrgDatabase {
    let url: URL
    let isActive: Bool
    /// The later of the database's and its write-ahead log's modification
    /// times: while the daemon works, the log is what changes.
    let lastWrite: Date
}

/// Every readable org database under `base`, and the one to read.
func orgDatabases(in base: URL) -> (all: [OrgDatabase], picked: URL?) {
    var activeUUID: String?
    if
        let data = try? Data(contentsOf: base.appendingPathComponent("active-org.json")),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
        activeUUID = json["org_uuid"] as? String
    }
    let fm = FileManager.default
    let orgs = base.appendingPathComponent("orgs")
    let uuids = (try? fm.contentsOfDirectory(atPath: orgs.path)) ?? []
    func modified(_ path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
    let all: [OrgDatabase] = uuids.sorted().compactMap { uuid in
        let db = orgs.appendingPathComponent("\(uuid)/operon-cli.db")
        guard fm.isReadableFile(atPath: db.path), let written = modified(db.path) else { return nil }
        let lastWrite = max(written, modified(db.path + "-wal") ?? .distantPast)
        return OrgDatabase(url: db, isActive: uuid == activeUUID, lastWrite: lastWrite)
    }
    guard let newest = all.max(by: { $0.lastWrite < $1.lastWrite }) else { return (all, nil) }
    // A minute's grace, so the active org keeps its place while two orgs
    // are both idle and were last written about the same time.
    if let active = all.first(where: \.isActive), active.lastWrite >= newest.lastWrite.addingTimeInterval(-60) {
        return (all, active.url)
    }
    return (all, newest.url)
}

// MARK: The connection

/// A value bound to a `?` in a statement: values are never written into SQL.
enum SQLArgument: Sendable, Equatable {
    case text(String)
    case integer(Int64)
}

/// Run one read-only query and return its rows, every value as text: NULL
/// as "", numbers as SQLite writes them (as `sqlite3 -list` printed them).
func runReadOnlyQuery(db: URL, sql: String, arguments: [SQLArgument] = [], timeout: TimeInterval = 8) throws -> [[String]] {
    try SQLiteReader.shared.rows(db: db, sql: sql, arguments: arguments, timeout: timeout)
}

/// Claude Science's database, read through one connection with the system
/// SQLite library, kept open while reads keep coming and let go after 10 s
/// without one. Until Bench 0.5.0 every query started `/usr/bin/sqlite3`
/// (5–10 ms a spawn, about once a second while a session works).
///
/// - Let go when idle because an open connection, read-only or not, keeps
///   the daemon's own close from being the last: it then leaves its
///   write-ahead log in place, and `DatabaseWatcher` doesn't see the log go
///   when Claude Science quits. (A quit while a session works, with the
///   connection open, is seen through the daemon's process: `LabModel`.)
/// - Read-only twice over: `SQLITE_OPEN_READONLY` and a `file:…?mode=ro`
///   URI. A write fails with SQLITE_READONLY.
/// - Every statement runs on one serial queue, so the connection needs no
///   mutex of its own (`SQLITE_OPEN_NOMUTEX`). Callers are off the main thread
///   already (`Task.detached`, or `--diagnose` before the app starts); a read
///   must never start another from inside the queue.
/// - Statements are prepared once and kept, by their SQL; values are bound.
///   Each is reset the moment its rows are read, so no read transaction stays
///   open to hold up the daemon's checkpoints.
/// - It opens again when the path names another file (a new inode: the
///   database was replaced), when another database is asked for (the active
///   org or the daemon's data folder changed), and after any error, retrying
///   a failed read once on the fresh connection.
/// - A writer's lock is waited on for 2 s; a statement still running at
///   `timeout` is interrupted ("query timed out").
final class SQLiteReader: @unchecked Sendable {
    static let shared = SQLiteReader()
    /// How long a read waits for a lock the daemon holds, in milliseconds.
    static let busyTimeout: Int32 = 2_000
    /// More distinct statements than this and the kept ones are let go.
    static let statementLimit = 64

    /// The library's version, as `--diagnose` reports it.
    static var libraryVersion: String { String(cString: sqlite3_libversion()) }

    private let queue = DispatchQueue(label: "local.sam.bench.sqlite", qos: .utility)
    /// How long the connection stays open after a read.
    private let idleClose: TimeInterval
    // Touched only on `queue`.
    private var connection: Connection?
    private var opens = 0
    private var letGo: DispatchWorkItem?

    /// Tests make their own; the app uses `shared`.
    init(idleClose: TimeInterval = 10) {
        self.idleClose = idleClose
    }

    /// How many connections have been opened: for tests.
    var openCount: Int { queue.sync { opens } }

    /// The rows of one read; see `runReadOnlyQuery`.
    func rows(db: URL, sql: String, arguments: [SQLArgument] = [], timeout: TimeInterval = 8) throws -> [[String]] {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return try queue.sync {
            defer { letGoLater() }
            return try read(path: db.path, sql: sql, arguments: arguments, timeout: timeout)
        }
    }

    /// After `idleClose` without another read, the connection goes. On the queue.
    private func letGoLater() {
        letGo?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.connection = nil }
        letGo = item
        queue.asyncAfter(deadline: .now() + idleClose, execute: item)
    }

    /// Lets the connection go; the next read opens it again.
    func close() {
        queue.sync { connection = nil }
    }

    private func read(path: String, sql: String, arguments: [SQLArgument], timeout: TimeInterval) throws -> [[String]] {
        var retried = false
        while true {
            let (current, fresh) = try open(path)
            do {
                return try current.rows(sql, arguments, until: .now() + timeout)
            } catch let failure as SQLiteFailure {
                // Whatever went wrong, the next read starts on a new connection.
                connection = nil
                if failure.primary == SQLITE_INTERRUPT { throw ScienceError.databaseUnreadable("query timed out") }
                // Once more on a fresh connection, unless this one was fresh or
                // it was a lock that outlasted the 2 s wait.
                if !fresh, !retried, failure.primary != SQLITE_BUSY, failure.primary != SQLITE_LOCKED {
                    retried = true
                    continue
                }
                throw ScienceError.databaseUnreadable("query failed: \(failure.message)")
            }
        }
    }

    /// The connection for `path`: the open one while it still reads that very
    /// file, else a new one.
    private func open(_ path: String) throws -> (Connection, fresh: Bool) {
        var info = stat()
        let found = stat(path, &info) == 0
        if let connection, connection.path == path, found,
           connection.device == info.st_dev, connection.inode == info.st_ino {
            return (connection, false)
        }
        connection = nil
        do {
            let opened = try Connection(path: path, device: found ? info.st_dev : 0, inode: found ? info.st_ino : 0)
            connection = opened
            opens += 1
            return (opened, true)
        } catch let failure as SQLiteFailure {
            throw ScienceError.databaseUnreadable("couldn't open: \(failure.message)")
        }
    }
}

/// What SQLite said when a call failed.
private struct SQLiteFailure: Error {
    let code: Int32
    let message: String

    var primary: Int32 { code & 0xFF }
}

/// One open connection and its kept statements. Used only on the reader's queue.
private final class Connection {
    let path: String
    let device: dev_t
    let inode: ino_t
    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]
    /// When the statement under way must stop; the progress handler reads it.
    fileprivate var deadline = DispatchTime.distantFuture

    init(path: String, device: dev_t, inode: ino_t) throws {
        self.path = path
        self.device = device
        self.inode = inode
        // A URI, so `mode=ro` holds whatever the flags say; the path is
        // escaped, so a `?`, `#` or `%` in it is part of the path.
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var opened: OpaquePointer?
        let status = sqlite3_open_v2("file:\(escaped)?mode=ro", &opened,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI, nil)
        guard status == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close_v2(opened)
            throw SQLiteFailure(code: status, message: message)
        }
        handle = opened
        sqlite3_extended_result_codes(handle, 1)
        sqlite3_busy_timeout(handle, SQLiteReader.busyTimeout)
        // Every 10,000 steps of a statement's program: past the deadline, stop.
        sqlite3_progress_handler(handle, 10_000, { context in
            guard let context else { return 0 }
            let connection = Unmanaged<Connection>.fromOpaque(context).takeUnretainedValue()
            return DispatchTime.now() > connection.deadline ? 1 : 0
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    /// SQLite copies a bound value at once.
    private static var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

    func rows(_ sql: String, _ arguments: [SQLArgument], until deadline: DispatchTime) throws -> [[String]] {
        let statement = try prepared(sql)
        self.deadline = deadline
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            self.deadline = .distantFuture
        }
        for (index, argument) in arguments.enumerated() {
            let position = Int32(index + 1)
            let status = switch argument {
            case .text(let text): sqlite3_bind_text(statement, position, text, Int32(text.utf8.count), Self.transient)
            case .integer(let value): sqlite3_bind_int64(statement, position, value)
            }
            guard status == SQLITE_OK else { throw failure(status) }
        }
        let columns = sqlite3_column_count(statement)
        var rows: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure(status) }
            rows.append((0..<columns).map { column in
                guard let text = sqlite3_column_text(statement, column) else { return "" }
                let count = Int(sqlite3_column_bytes(statement, column))
                return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
            })
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let kept = statements[sql] { return kept }
        if statements.count >= SQLiteReader.statementLimit {
            for statement in statements.values { sqlite3_finalize(statement) }
            statements = [:]
        }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard status == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw status == SQLITE_OK ? SQLiteFailure(code: SQLITE_MISUSE, message: "not a statement") : failure(status)
        }
        statements[sql] = statement
        return statement
    }

    private func failure(_ status: Int32) -> SQLiteFailure {
        SQLiteFailure(code: status, message: String(cString: sqlite3_errmsg(handle)))
    }
}

/// One session row: a conversation root, metadata only.
struct FrameRow: Equatable {
    let id: String
    let projectID: String
    let name: String
    let status: String
    let createdMs: Int64
    let updatedMs: Int64
    let completedMs: Int64?
    /// When the latest turn began: the last user message, else creation.
    let turnStartedMs: Int64
    let hasPendingInput: Bool
    /// Tokens the whole session used, sub-agents included: input (cached
    /// input included) plus output.
    var tokens: Int64 = 0
    /// For a waiting session, why: an `awaiting_*` status or a pending
    /// request's kind, the session's own or a sub-agent's.
    var waitingSignal: String? = nil
    /// The latest write anywhere in the session's tree, its sub-agents'
    /// included (milliseconds): the poll's order key. A root waits quietly
    /// while its helpers work, so `updatedMs` alone can look idle.
    var activeMs: Int64? = nil
}

/// A text column as one line: line breaks and the field separator become
/// spaces, so a name with a newline can't split its row in two (and drop the
/// session from view).
private func oneLineSQL(_ column: String) -> String {
    "replace(replace(replace(COALESCE(\(column),''), char(10), ' '), char(13), ' '), char(31), ' ')"
}

/// `alias`'s output JSON, from the frame row or else its blob.
private func outputSQL(_ alias: String) -> String {
    """
    COALESCE(\(alias).output_data, (SELECT b.body FROM frame_blobs b \
    WHERE b.frame_id = \(alias).id AND b.kind = 'output'))
    """
}

/// SQL that is true when `alias`'s output lists pending input requests.
/// The same test the daemon's dashboard runs. It measures the array in
/// SQLite; the output body itself never leaves the database.
private func pendingInputSQL(_ alias: String) -> String {
    let output = outputSQL(alias)
    return """
        COALESCE(json_array_length(CASE WHEN json_valid(\(output)) THEN \(output) END, \
        '$.pending_input_requests'), 0) > 0
        """
}

/// The `kind` of `alias`'s first pending input request, or NULL: one word
/// from the daemon's fixed vocabulary, which `WaitingReason` maps and never
/// shows as is. Nothing else of the request leaves the database.
private func pendingKindSQL(_ alias: String) -> String {
    let output = outputSQL(alias)
    return """
        json_extract(CASE WHEN json_valid(\(output)) THEN \(output) END, \
        '$.pending_input_requests[0].kind')
        """
}

/// What Claude Science's own dashboard counts as a session: conversation
/// roots only, never hidden sub-agents, uploads or the concierge.
private func sessionFilterSQL(_ alias: String) -> String {
    """
    \(alias).parent_frame_id IS NULL
      AND \(sessionKindSQL(alias))
    """
}

/// `sessionFilterSQL` without its first line, for the poll, which says
/// "a root" its own way.
private func sessionKindSQL(_ alias: String) -> String {
    """
    \(alias).is_hidden IS NOT 1
      AND \(alias).conversation_type != 'uploads'
      AND \(alias).agent_name NOT IN ('CONCIERGE','CANVAS_CONCIERGE')
    """
}

/// Recent sessions, the way Claude Science's own dashboard picks them (see
/// `sessionFilterSQL`). Working and waiting sessions sort first so they are
/// never pushed out of `limit`, then by the latest activity anywhere in the
/// tree. Only the few roots that can make the list are looked at closely
/// (`sessionsPollSQL`), so the poll stays cheap however many sessions there
/// have ever been.
func fetchRecentFrames(db: URL, limit: Int = 25) throws -> [FrameRow] {
    // Whether SQLite can walk the roots newest first, and find the working
    // ones, by the daemon's own indexes; a failed look is a no.
    let byTime = (try? ColumnProbe.shared.leadsIndex(db: db, table: "frames", column: "updated_at")) ?? false
    let byStatus = (try? ColumnProbe.shared.leadsIndex(db: db, table: "frames", column: "status")) ?? false
    let rows = try runReadOnlyQuery(db: db, sql: sessionsPollSQL(byTime: byTime, byStatus: byStatus),
                                    arguments: [.integer(Int64(max(1, min(limit, 50))))])
    return rows.compactMap { cols in
        guard cols.count >= 10 else { return nil }
        let created = Int64(cols[4]) ?? 0
        return FrameRow(
            id: cols[0], projectID: cols[1], name: cols[2], status: cols[3],
            createdMs: created, updatedMs: Int64(cols[5]) ?? 0,
            completedMs: cols[6].isEmpty ? nil : Int64(cols[6]),
            turnStartedMs: Int64(cols[7]) ?? created,
            hasPendingInput: cols[8] == "1",
            tokens: Int64(cols[9]) ?? 0,
            waitingSignal: cols.count > 10 && !cols[10].isEmpty ? cols[10] : nil,
            activeMs: cols.count > 11 ? Int64(cols[11]) : nil
        )
    }
}

/// The poll's statement, its limit bound as `?1`. The order is the one it
/// always was: working and waiting roots first, then by the latest write
/// anywhere in the tree, `MAX(root's updated_at, its helpers' latest)`. What
/// changed is which rows are looked at:
///
/// 1. The candidates, by cheap columns only: the roots that work or wait;
///    the newest `?1` roots by their own `updated_at` (`newest`); the roots
///    of every helper written since the oldest of those (`helped`), since a
///    helper's write can lift a root above them; and, only while fewer than
///    `?1` roots have a status, the ones without (they sort last).
///    Nothing outside these can make the list: a root that isn't one has
///    its own and all its helpers' writes older than the oldest in `newest`,
///    so at least `?1` roots sort before it.
/// 2. Their trees, metadata only (`tree`), and the order key for those alone
///    (`picked`).
/// 3. The tokens, the pending-input test and the waiting signal (the JSON
///    reads) for the `?1` picked roots only, as before; and last, the order
///    key itself, the tree's latest write (`FrameRow.activeMs`, Bench 0.5.3).
///
/// With an index that starts with `updated_at` (`byTime`), SQLite walks it
/// newest first and stops at `?1` roots, and finds the helpers' writes by
/// range; with one that starts with `status` (`byStatus`), it finds the
/// working roots by it. The `+` in front of `parent_frame_id` keeps it off a
/// parent index for those, which would mean visiting every root. Without such
/// indexes it reads each root once (`roots`), never once per root as before.
func sessionsPollSQL(byTime: Bool, byStatus: Bool) -> String {
    let awaiting = "'awaiting_user_response','awaiting_plan_approval'"
    let active = "'processing',\(awaiting)"
    let firstLook: String
    if byTime {
        firstLook = """
            newest AS MATERIALIZED (
                SELECT f.id, f.updated_at FROM frames f
                WHERE +f.parent_frame_id IS NULL AND f.status IS NOT NULL AND \(sessionKindSQL("f"))
                ORDER BY f.updated_at DESC LIMIT ?1),
            working AS MATERIALIZED (
                SELECT f.id FROM frames f
                WHERE f.status IN (\(active)) AND \(byStatus ? "+" : "")f.parent_frame_id IS NULL AND \(sessionKindSQL("f"))),
            unsorted AS MATERIALIZED (
                SELECT f.id FROM frames f
                WHERE (SELECT COUNT(*) FROM newest) < ?1 AND f.status IS NULL AND \(sessionFilterSQL("f"))),
            """
    } else {
        firstLook = """
            roots AS MATERIALIZED (
                SELECT f.id, f.updated_at, f.status FROM frames f WHERE \(sessionFilterSQL("f"))),
            newest AS MATERIALIZED (
                SELECT id, updated_at FROM roots WHERE status IS NOT NULL ORDER BY updated_at DESC LIMIT ?1),
            working AS MATERIALIZED (
                SELECT id FROM roots WHERE status IN (\(active))),
            unsorted AS MATERIALIZED (
                SELECT id FROM roots WHERE status IS NULL AND (SELECT COUNT(*) FROM newest) < ?1),
            """
    }
    // A helper of root `f`, in `tree t`, that holds a request: waiting on the
    // user, or working with one pending. Its output is read only then.
    let holding = """
        t.root_frame_id = f.id AND t.parent_frame_id IS NOT NULL AND t.is_hidden IS NOT 1
          AND (t.status IN (\(awaiting))
               OR (t.status = 'processing' AND (SELECT \(pendingInputSQL("x")) FROM frames x WHERE x.id = t.id)))
        """
    return """
        WITH \(firstLook)
        helped AS MATERIALIZED (
            SELECT c.root_frame_id AS id FROM frames c
            WHERE c.updated_at >= (SELECT MIN(updated_at) FROM newest) AND +c.parent_frame_id IS NOT NULL),
        candidates(id) AS MATERIALIZED (
            SELECT id FROM working UNION SELECT id FROM newest UNION SELECT id FROM helped
            UNION SELECT id FROM unsorted),
        tree AS MATERIALIZED (
            SELECT c.id, c.root_frame_id, c.parent_frame_id, c.status, c.updated_at, c.is_hidden,
                   c.input_tokens, c.output_tokens
            FROM frames c WHERE c.root_frame_id IN (SELECT id FROM candidates)),
        picked AS MATERIALIZED (
            SELECT f.id AS id, f.status IN (\(active)) AS active,
                   MAX(f.updated_at, COALESCE((SELECT MAX(t.updated_at) FROM tree t
                       WHERE t.root_frame_id = f.id AND t.parent_frame_id IS NOT NULL), 0)) AS recency
            FROM candidates k CROSS JOIN frames f ON f.id = k.id
            WHERE \(sessionFilterSQL("f"))
            ORDER BY active DESC, recency DESC
            LIMIT ?1)
        SELECT f.id, COALESCE(f.project_id,''), \(oneLineSQL("f.name")), f.status,
               f.created_at, f.updated_at, COALESCE(f.completed_at,''),
               MAX(f.created_at, COALESCE(f.last_user_message_at, 0)),
               CASE WHEN f.status = 'processing' AND (\(pendingInputSQL("f"))
                        OR EXISTS (SELECT 1 FROM tree t WHERE \(holding))) THEN 1 ELSE 0 END,
               (SELECT COALESCE(SUM(COALESCE(t.input_tokens, 0) + COALESCE(t.output_tokens, 0)), 0)
                FROM tree t WHERE t.root_frame_id = f.id),
               CASE WHEN f.status = 'awaiting_user_response' THEN COALESCE(NULLIF(\(pendingKindSQL("f")), 'ask'), f.status)
                    WHEN f.status IN (\(awaiting)) THEN f.status
                    WHEN f.status = 'processing' THEN COALESCE(\(pendingKindSQL("f")), (
                        SELECT CASE WHEN t.status = 'awaiting_user_response'
                                    THEN COALESCE(NULLIF(\(pendingKindSQL("y")), 'ask'), t.status)
                                    WHEN t.status IN (\(awaiting)) THEN t.status ELSE \(pendingKindSQL("y")) END
                        FROM tree t CROSS JOIN frames y ON y.id = t.id
                        WHERE \(holding)
                        ORDER BY t.updated_at DESC LIMIT 1))
               END,
               p.recency
        FROM picked p CROSS JOIN frames f ON f.id = p.id
        ORDER BY p.active DESC, p.recency DESC;
        """
}

/// Sessions started per local day over the last `days`, for the activity
/// graph. One grouped count; no names, no content.
func fetchDailySessionCounts(db: URL, days: Int, now: Date = Date()) throws -> [String: Int] {
    let since = Int64((now.timeIntervalSince1970 - Double(max(1, days)) * 86_400) * 1000)
    let sql = """
        SELECT date(f.created_at / 1000, 'unixepoch', 'localtime'), COUNT(*)
        FROM frames f
        WHERE \(sessionFilterSQL("f")) AND f.created_at >= ?1
        GROUP BY 1;
        """
    return try dailyCounts(db: db, sql: sql, since: since)
}

/// Messages the user sent per local day, for the activity graph.
///
/// Only the user's own prompts: `role = user` rows in a session's root
/// frame that carry an `_intent_id` (a user action). Tool results, harness
/// notices and one agent's instructions to another are stored as `user`
/// rows too and are left out. Dated by the message's own `_ts` (ms); rows
/// written before `_ts` existed cannot be dated and are skipped. Only keys
/// are read, never `content`. Like the tokens, only messages of sessions
/// touched since `since` are looked at (see `recentFramesSQL`).
func fetchDailyMessageCounts(db: URL, days: Int, now: Date = Date()) throws -> [String: Int] {
    let since = Int64((now.timeIntervalSince1970 - Double(max(1, days)) * 86_400) * 1000)
    let sql = """
        SELECT date(json_extract(m.msg_json, '$._ts') / 1000, 'unixepoch', 'localtime'), COUNT(*)
        FROM frame_messages m JOIN frames f ON f.id = m.frame_id
        WHERE \(sessionFilterSQL("f"))
          AND m.frame_id IN \(recentFramesSQL)
          AND json_valid(m.msg_json)
          AND json_extract(m.msg_json, '$.role') = 'user'
          AND json_type(m.msg_json, '$._intent_id') IS NOT NULL
          AND json_type(m.msg_json, '$._ts') = 'integer'
          AND json_extract(m.msg_json, '$._ts') >= ?1
        GROUP BY 1;
        """
    return try dailyCounts(db: db, sql: sql, since: since)
}

/// Tokens the model processed per local day, for the activity graph: every
/// assistant reply's `_tokens.input + _tokens.output`, sub-agents included.
/// `input` already includes cached input (`input = uncached + cache_read +
/// cache_write` on every row), so nothing is counted twice.
func fetchDailyTokenCounts(db: URL, days: Int, now: Date = Date()) throws -> [String: Int] {
    let since = Int64((now.timeIntervalSince1970 - Double(max(1, days)) * 86_400) * 1000)
    let sql = """
        SELECT date(json_extract(msg_json, '$._ts') / 1000, 'unixepoch', 'localtime'),
               SUM(COALESCE(json_extract(msg_json, '$._tokens.input'), 0)
                   + COALESCE(json_extract(msg_json, '$._tokens.output'), 0))
        FROM frame_messages
        WHERE frame_id IN \(recentFramesSQL)
          AND json_valid(msg_json)
          AND json_type(msg_json, '$._tokens') = 'object'
          AND json_type(msg_json, '$._ts') = 'integer'
          AND json_extract(msg_json, '$._ts') >= ?1
        GROUP BY 1;
        """
    return try dailyCounts(db: db, sql: sql, since: since)
}

/// Frames updated since `?1` (ms). A frame's `updated_at` never trails
/// its messages' `_ts` (checked on a real db, 2026-09-27: 43,391 dated
/// messages, none later than their frame), so a message sent since then is
/// in one of these frames. Looking only there lets SQLite use the frame_id
/// index instead of reading every message: 0.14 s instead of 2.2 s for two
/// weeks of tokens, 0.8 s instead of 1.9 s for a year, same counts.
private let recentFramesSQL = "(SELECT id FROM frames WHERE updated_at >= ?1)"

private func dailyCounts(db: URL, sql: String, since: Int64) throws -> [String: Int] {
    var out: [String: Int] = [:]
    for cols in try runReadOnlyQuery(db: db, sql: sql, arguments: [.integer(since)]) where cols.count >= 2 {
        out[cols[0]] = Int(cols[1]) ?? 0
    }
    return out
}

/// Project names for the ids we show. Never description/context (research).
func fetchProjectNames(db: URL) throws -> [String: String] {
    let rows = try runReadOnlyQuery(db: db, sql: "SELECT id, \(oneLineSQL("name")) FROM projects;")
    var out: [String: String] = [:]
    for cols in rows where cols.count >= 2 { out[cols[0]] = cols[1] }
    return out
}

// MARK: Browse (Bench on your phone, Phase 3)
//
// Pageable reads for the phone's Projects tab and a project's sessions, and a
// point lookup by id. Metadata only, like the reads above: ids, names,
// statuses, times and counts. Never input_data, output_data or any text column
// but `name`. Only two looks go further, each a test inside SQLite's WHERE
// whose value never leaves the database: `task_summary IS NOT NULL` (Claude
// Science's own list shows only sessions with one), and, to find a new session
// whose reply was lost, whether `input_data`'s `_intent_id` is the phone's id.
// Every value is checked first (ids by their shape, numbers as numbers), then
// bound to the statement, never written into it.

/// A project for the phone: how many sessions it has, and when the newest
/// was last active (milliseconds; nil without sessions).
struct ProjectRow: Equatable, Sendable {
    let id: String
    let name: String
    let sessions: Int
    let lastActiveMs: Int64?
}

/// A session found by browsing or by its id: a conversation root, metadata only.
struct BrowseRow: Equatable, Sendable {
    let id: String
    let projectID: String
    let projectName: String
    let name: String
    let status: String
    let createdMs: Int64
    let updatedMs: Int64
    let completedMs: Int64?
    /// When the latest turn began: the last user message, else creation.
    let turnStartedMs: Int64
}

/// Where the next page of a project's sessions starts: after this
/// `(updated_at, id)`, newest first.
struct BrowseCursor: Equatable, Sendable {
    let updatedMs: Int64
    let id: String
}

enum BrowseSQL {
    /// A page of sessions: 50, and one more to tell whether there is a next page.
    static let pageSize = 50
    /// At most this many projects, as Claude Science's own list.
    static let projectLimit = 500

    /// `^[A-Za-z0-9_-]{1,64}$`: a project id, safe in a path and in SQL.
    static func isProjectID(_ id: some StringProtocol) -> Bool {
        (1...64).contains(id.utf8.count) && id.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    /// `%text%`, bound to `LIKE ? ESCAPE '\'`: `\`, `%` and `_` escaped, so
    /// the text matches only itself.
    static func containsPattern(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "%": out += "\\%"
            case "_": out += "\\_"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return "%" + out + "%"
    }

    /// The columns of a `BrowseRow`, from `frames f` and `projects p`.
    fileprivate static let rowColumns = """
        f.id, COALESCE(f.project_id,''), \(oneLineSQL("p.name")), \(oneLineSQL("f.name")), COALESCE(f.status,''),
        COALESCE(f.created_at,0), COALESCE(f.updated_at,0), COALESCE(f.completed_at,''),
        MAX(COALESCE(f.created_at,0), COALESCE(f.last_user_message_at,0))
        """

    fileprivate static func row(_ cols: [String]) -> BrowseRow? {
        guard cols.count >= 9, PlanCheck.isFrameID(cols[0]) else { return nil }
        let created = Int64(cols[5]) ?? 0
        return BrowseRow(id: cols[0], projectID: cols[1], projectName: cols[2], name: cols[3], status: cols[4],
                         createdMs: created, updatedMs: Int64(cols[6]) ?? 0,
                         completedMs: cols[7].isEmpty ? nil : Int64(cols[7]),
                         turnStartedMs: Int64(cols[8]) ?? created)
    }
}

/// Whether `table` has `column`, from SQLite's own pragma; remembered for five
/// minutes per database, so a daemon update while Bench runs is noticed.
private final class ColumnProbe: @unchecked Sendable {
    static let shared = ColumnProbe()
    private let lock = NSLock()
    private var known: [String: (has: Bool, at: Date)] = [:]

    func has(db: URL, table: String, column: String) throws -> Bool {
        try look(db: db, key: "column\u{1F}\(table)\u{1F}\(column)",
                 sql: "SELECT COUNT(*) FROM pragma_table_info(?1) WHERE name = ?2;", table, column)
    }

    /// Whether a whole (not partial) index on `table` starts with `column`, so
    /// SQLite can walk the table in that column's order. The same five minutes.
    func leadsIndex(db: URL, table: String, column: String) throws -> Bool {
        try look(db: db, key: "index\u{1F}\(table)\u{1F}\(column)", sql: """
            SELECT COUNT(*) FROM pragma_index_list(?1) AS l, pragma_index_info(l.name) AS i
            WHERE l.partial = 0 AND i.seqno = 0 AND i.name = ?2;
            """, table, column)
    }

    private func look(db: URL, key: String, sql: String, _ table: String, _ column: String) throws -> Bool {
        let key = "\(db.path)\u{1F}\(key)"
        lock.lock()
        let cached = known[key]
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 300 { return cached.has }
        let rows = try runReadOnlyQuery(db: db, sql: sql, arguments: [.text(table), .text(column)])
        let has = (rows.first?.first).flatMap { Int($0) }.map { $0 > 0 } ?? false
        lock.lock()
        known[key] = (has, Date())
        lock.unlock()
        return has
    }
}

/// Every project but the concierge's own, archived ones hidden when the
/// database has `archived_at`; with its root-session count and latest
/// activity, newest first. Counted as the session list lists them.
func fetchProjects(db: URL) throws -> [ProjectRow] {
    let archived = try ColumnProbe.shared.has(db: db, table: "projects", column: "archived_at")
    let sql = """
        SELECT p.id, \(oneLineSQL("p.name")), COUNT(f.id), COALESCE(MAX(f.updated_at),'')
        FROM projects p
        LEFT JOIN frames f ON f.project_id = p.id AND \(sessionFilterSQL("f")) AND f.task_summary IS NOT NULL
        WHERE p.id NOT LIKE 'proj\\_concierge\\_sys\\_%' ESCAPE '\\'\(archived ? " AND p.archived_at IS NULL" : "")
        GROUP BY p.id
        ORDER BY COALESCE(MAX(f.updated_at),0) DESC, p.id
        LIMIT \(BrowseSQL.projectLimit);
        """
    return try runReadOnlyQuery(db: db, sql: sql).compactMap { cols in
        guard cols.count >= 4, BrowseSQL.isProjectID(cols[0]) else { return nil }
        return ProjectRow(id: cols[0], name: cols[1], sessions: Int(cols[2]) ?? 0,
                          lastActiveMs: cols[3].isEmpty ? nil : Int64(cols[3]))
    }
}

/// One page of a project's root sessions, newest first by `(updated_at, id)`,
/// after `cursor`, and with `search` its names containing that text; none
/// when the project is archived (the point lookup below still opens one). Up to
/// `BrowseSQL.pageSize + 1` rows: the extra one says there is a next page.
/// Nil (nothing read) for a project id or cursor out of shape.
func fetchProjectSessions(db: URL, project: String, after cursor: BrowseCursor?, search: String?) throws -> [BrowseRow]? {
    guard BrowseSQL.isProjectID(project) else { return nil }
    var conditions = ["\(sessionFilterSQL("f"))", "f.task_summary IS NOT NULL", "f.project_id = ?"]
    var arguments: [SQLArgument] = [.text(project)]
    // An archived project's sessions are hidden, as `fetchProjects` hides the project.
    if try ColumnProbe.shared.has(db: db, table: "projects", column: "archived_at") { conditions.append("p.archived_at IS NULL") }
    if let cursor {
        guard PlanCheck.isFrameID(cursor.id), cursor.updatedMs >= 0 else { return nil }
        conditions.append("""
            (COALESCE(f.updated_at,0) < ? \
            OR (COALESCE(f.updated_at,0) = ? AND f.id < ?))
            """)
        arguments += [.integer(cursor.updatedMs), .integer(cursor.updatedMs), .text(cursor.id)]
    }
    if let search {
        conditions.append("f.name LIKE ? ESCAPE '\\'")
        arguments.append(.text(BrowseSQL.containsPattern(search)))
    }
    let sql = """
        SELECT \(BrowseSQL.rowColumns)
        FROM frames f LEFT JOIN projects p ON p.id = f.project_id
        WHERE \(conditions.joined(separator: "\n  AND "))
        ORDER BY COALESCE(f.updated_at,0) DESC, f.id DESC
        LIMIT \(BrowseSQL.pageSize + 1);
        """
    return try runReadOnlyQuery(db: db, sql: sql, arguments: arguments).compactMap(BrowseSQL.row)
}

/// One root session by its full id, as the session list's filter counts
/// sessions (without the `task_summary` test, so any root opens). Nil when
/// there is none, or for an id out of shape.
func fetchSession(db: URL, id: String) throws -> BrowseRow? {
    guard PlanCheck.isFrameID(id) else { return nil }
    let sql = """
        SELECT \(BrowseSQL.rowColumns)
        FROM frames f LEFT JOIN projects p ON p.id = f.project_id
        WHERE \(sessionFilterSQL("f")) AND f.id = ?1
        LIMIT 1;
        """
    return try runReadOnlyQuery(db: db, sql: sql, arguments: [.text(id)]).compactMap(BrowseSQL.row).first
}

/// The root session a new-session request with this intent id made in this
/// project within `window` seconds of `now`: for a reply that was lost (a
/// timeout) or refused as a repeat (409). The intent is compared inside
/// SQLite; only the session's id comes out.
func fetchSessionByIntent(db: URL, project: String, intent: String, now: Date = Date(),
                          window: TimeInterval = 600) throws -> String? {
    guard BrowseSQL.isProjectID(project), RemoteActionRequest.isUUIDv4(intent) else { return nil }
    let since = Int64((now.timeIntervalSince1970 - window) * 1000)
    let sql = """
        SELECT f.id FROM frames f
        WHERE \(sessionFilterSQL("f")) AND f.project_id = ?1 AND COALESCE(f.created_at,0) >= ?2
          AND json_extract(CASE WHEN json_valid(f.input_data) THEN f.input_data END, '$._intent_id') = ?3
        ORDER BY f.created_at DESC
        LIMIT 1;
        """
    return try runReadOnlyQuery(db: db, sql: sql, arguments: [.text(project), .integer(since), .text(intent)]).first.flatMap { $0.first }.flatMap { PlanCheck.isFrameID($0) ? $0 : nil }
}
