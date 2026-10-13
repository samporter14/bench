// SQLiteSource.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.
//
// Reads the daemon's SQLite database with the system `sqlite3` tool in
// read-only mode (`file:...?mode=ro`), one short query per poll, connection
// never held open. Metadata only: ids, names, statuses, timestamps.
// Never input_data / output_data / task_summary / payload bodies; the one
// look at an output is a count of its pending input requests, taken inside
// SQLite (see `pendingInputSQL`).

import Foundation

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

func resolveSqlite3() -> URL {
    // For testing against another sqlite3 build (Bench's own addition).
    if let path = ProcessInfo.processInfo.environment["BENCH_SQLITE3"],
       FileManager.default.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    for path in ["/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3"] {
        if FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
    }
    return URL(fileURLWithPath: "/usr/bin/sqlite3")
}

/// Run one read-only query, return raw rows split on `separator`.
func runReadOnlyQuery(db: URL, sql: String, timeout: TimeInterval = 8) throws -> [[String]] {
    let separator = "\u{1F}"
    let result: (status: Int32, output: Data)
    do {
        // The mode before the separator: since sqlite3 3.52 or so, `-list`
        // resets the separator to "|", so the other way round every row came
        // back as one field and parsed as nothing (macOS 27 ships 3.54).
        result = try runProcess(
            resolveSqlite3(), ["-list", "-separator", separator, "file:\(db.path)?mode=ro", sql],
            timeout: timeout)
    } catch SubprocessFailure.timedOut {
        throw ScienceError.databaseUnreadable("query timed out")
    } catch {
        throw ScienceError.databaseUnreadable("\(error)")
    }
    guard result.status == 0 else {
        throw ScienceError.databaseUnreadable("query failed (schema changed?)")
    }
    let out = String(data: result.output, encoding: .utf8) ?? ""
    return out
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.split(separator: Character(separator), omittingEmptySubsequences: false).map(String.init) }
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
      AND \(alias).is_hidden IS NOT 1
      AND \(alias).conversation_type != 'uploads'
      AND \(alias).agent_name NOT IN ('CONCIERGE','CANVAS_CONCIERGE')
    """
}

/// Recent sessions, the way Claude Science's own dashboard picks them (see
/// `sessionFilterSQL`). Working and waiting sessions sort first so they are
/// never pushed out of `limit`, then by the latest activity anywhere in the
/// tree. `limit` keeps the poll cheap against a 1 GB db.
func fetchRecentFrames(db: URL, limit: Int = 25) throws -> [FrameRow] {
    let awaiting = "'awaiting_user_response','awaiting_plan_approval'"
    let sql = """
        SELECT f.id, COALESCE(f.project_id,''), \(oneLineSQL("f.name")), f.status,
               f.created_at, f.updated_at, COALESCE(f.completed_at,''),
               MAX(f.created_at, COALESCE(f.last_user_message_at, 0)),
               CASE WHEN f.status = 'processing' AND (\(pendingInputSQL("f")) OR EXISTS (
                   SELECT 1 FROM frames c
                   WHERE c.root_frame_id = f.id AND c.parent_frame_id IS NOT NULL
                     AND c.is_hidden IS NOT 1
                     AND (c.status IN (\(awaiting))
                          OR (c.status = 'processing' AND \(pendingInputSQL("c"))))
               )) THEN 1 ELSE 0 END,
               (SELECT COALESCE(SUM(COALESCE(c.input_tokens, 0) + COALESCE(c.output_tokens, 0)), 0)
                FROM frames c WHERE c.root_frame_id = f.id),
               CASE WHEN f.status IN (\(awaiting)) THEN f.status
                    WHEN f.status = 'processing' THEN COALESCE(\(pendingKindSQL("f")), (
                        SELECT CASE WHEN c.status IN (\(awaiting)) THEN c.status ELSE \(pendingKindSQL("c")) END
                        FROM frames c
                        WHERE c.root_frame_id = f.id AND c.parent_frame_id IS NOT NULL
                          AND c.is_hidden IS NOT 1
                          AND (c.status IN (\(awaiting))
                               OR (c.status = 'processing' AND \(pendingInputSQL("c"))))
                        ORDER BY c.updated_at DESC LIMIT 1))
               END
        FROM frames f
        WHERE \(sessionFilterSQL("f"))
        ORDER BY f.status IN ('processing',\(awaiting)) DESC,
                 MAX(f.updated_at, COALESCE((SELECT MAX(c.updated_at) FROM frames c
                     WHERE c.root_frame_id = f.id AND c.parent_frame_id IS NOT NULL), 0)) DESC
        LIMIT \(max(1, min(limit, 50)));
        """
    let rows = try runReadOnlyQuery(db: db, sql: sql)
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
            waitingSignal: cols.count > 10 && !cols[10].isEmpty ? cols[10] : nil
        )
    }
}

/// Sessions started per local day over the last `days`, for the activity
/// graph. One grouped count; no names, no content.
func fetchDailySessionCounts(db: URL, days: Int, now: Date = Date()) throws -> [String: Int] {
    let since = Int64((now.timeIntervalSince1970 - Double(max(1, days)) * 86_400) * 1000)
    let sql = """
        SELECT date(f.created_at / 1000, 'unixepoch', 'localtime'), COUNT(*)
        FROM frames f
        WHERE \(sessionFilterSQL("f")) AND f.created_at >= \(since)
        GROUP BY 1;
        """
    return try dailyCounts(db: db, sql: sql)
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
          AND m.frame_id IN \(recentFramesSQL(since))
          AND json_valid(m.msg_json)
          AND json_extract(m.msg_json, '$.role') = 'user'
          AND json_type(m.msg_json, '$._intent_id') IS NOT NULL
          AND json_type(m.msg_json, '$._ts') = 'integer'
          AND json_extract(m.msg_json, '$._ts') >= \(since)
        GROUP BY 1;
        """
    return try dailyCounts(db: db, sql: sql)
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
        WHERE frame_id IN \(recentFramesSQL(since))
          AND json_valid(msg_json)
          AND json_type(msg_json, '$._tokens') = 'object'
          AND json_type(msg_json, '$._ts') = 'integer'
          AND json_extract(msg_json, '$._ts') >= \(since)
        GROUP BY 1;
        """
    return try dailyCounts(db: db, sql: sql)
}

/// Frames updated since `since` (ms). A frame's `updated_at` never trails
/// its messages' `_ts` (checked on a real db, 2026-09-27: 43,391 dated
/// messages, none later than their frame), so a message sent since then is
/// in one of these frames. Looking only there lets SQLite use the frame_id
/// index instead of reading every message: 0.14 s instead of 2.2 s for two
/// weeks of tokens, 0.8 s instead of 1.9 s for a year, same counts.
private func recentFramesSQL(_ since: Int64) -> String {
    "(SELECT id FROM frames WHERE updated_at >= \(since))"
}

private func dailyCounts(db: URL, sql: String) throws -> [String: Int] {
    var out: [String: Int] = [:]
    for cols in try runReadOnlyQuery(db: db, sql: sql) where cols.count >= 2 {
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
// Every value put into the SQL is checked first (ids by their shape, numbers
// as numbers) or escaped (`q`); sqlite3 takes the statement as one argument.

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

    /// `'%text%'` for `LIKE … ESCAPE '\'`: the quote doubled, and `\`, `%` and
    /// `_` escaped, so the text matches only itself.
    static func containsPattern(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "'": out += "''"
            case "\\": out += "\\\\"
            case "%": out += "\\%"
            case "_": out += "\\_"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return "'%" + out + "%'"
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
        let key = "\(db.path)\u{1F}\(table)\u{1F}\(column)"
        lock.lock()
        let cached = known[key]
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 300 { return cached.has }
        let rows = try runReadOnlyQuery(
            db: db, sql: "SELECT COUNT(*) FROM pragma_table_info('\(table)') WHERE name = '\(column)';")
        let has = rows.first?.first == "1"
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
/// after `cursor`, and with `search` its names containing that text. Up to
/// `BrowseSQL.pageSize + 1` rows: the extra one says there is a next page.
/// Nil (nothing read) for a project id or cursor out of shape.
func fetchProjectSessions(db: URL, project: String, after cursor: BrowseCursor?, search: String?) throws -> [BrowseRow]? {
    guard BrowseSQL.isProjectID(project) else { return nil }
    var conditions = ["\(sessionFilterSQL("f"))", "f.task_summary IS NOT NULL", "f.project_id = '\(project)'"]
    if let cursor {
        guard PlanCheck.isFrameID(cursor.id), cursor.updatedMs >= 0 else { return nil }
        conditions.append("""
            (COALESCE(f.updated_at,0) < \(cursor.updatedMs) \
            OR (COALESCE(f.updated_at,0) = \(cursor.updatedMs) AND f.id < '\(cursor.id)'))
            """)
    }
    if let search { conditions.append("f.name LIKE \(BrowseSQL.containsPattern(search)) ESCAPE '\\'") }
    let sql = """
        SELECT \(BrowseSQL.rowColumns)
        FROM frames f LEFT JOIN projects p ON p.id = f.project_id
        WHERE \(conditions.joined(separator: "\n  AND "))
        ORDER BY COALESCE(f.updated_at,0) DESC, f.id DESC
        LIMIT \(BrowseSQL.pageSize + 1);
        """
    return try runReadOnlyQuery(db: db, sql: sql).compactMap(BrowseSQL.row)
}

/// One root session by its full id, as the session list's filter counts
/// sessions (without the `task_summary` test, so any root opens). Nil when
/// there is none, or for an id out of shape.
func fetchSession(db: URL, id: String) throws -> BrowseRow? {
    guard PlanCheck.isFrameID(id) else { return nil }
    let sql = """
        SELECT \(BrowseSQL.rowColumns)
        FROM frames f LEFT JOIN projects p ON p.id = f.project_id
        WHERE \(sessionFilterSQL("f")) AND f.id = '\(id)'
        LIMIT 1;
        """
    return try runReadOnlyQuery(db: db, sql: sql).compactMap(BrowseSQL.row).first
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
        WHERE \(sessionFilterSQL("f")) AND f.project_id = '\(project)' AND COALESCE(f.created_at,0) >= \(since)
          AND json_extract(CASE WHEN json_valid(f.input_data) THEN f.input_data END, '$._intent_id') = '\(intent)'
        ORDER BY f.created_at DESC
        LIMIT 1;
        """
    return try runReadOnlyQuery(db: db, sql: sql).first.flatMap { $0.first }.flatMap { PlanCheck.isFrameID($0) ? $0 : nil }
}
