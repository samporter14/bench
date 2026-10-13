// BrowseSQLTests.swift — Phase 3's database reads (projects, a project's
// sessions, the point lookup, the intent lookup) against a made-up SQLite
// database built here, with the columns Bench's reads expect. Nothing reads
// Claude Science's own database.
import Foundation
import Testing
@testable import Bench

/// A made-up database in a temporary folder. Every text column a read must
/// never return holds a SECRET marker.
struct MadeUpDatabase {
    let dir: URL
    let url: URL

    init(archived: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-browse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("made-up.db")
        try run("""
            CREATE TABLE projects(id TEXT PRIMARY KEY, name TEXT, description TEXT, context TEXT\(archived ? ", archived_at INTEGER" : ""));
            CREATE TABLE frames(id TEXT PRIMARY KEY, project_id TEXT, name TEXT, status TEXT, created_at INTEGER,
                updated_at INTEGER, completed_at INTEGER, last_user_message_at INTEGER, root_frame_id TEXT,
                parent_frame_id TEXT, input_tokens INTEGER, output_tokens INTEGER, is_hidden INTEGER, output_data TEXT,
                input_data TEXT, task_summary TEXT, conversation_type TEXT, agent_name TEXT, status_description TEXT);
            CREATE TABLE frame_blobs(frame_id TEXT, kind TEXT, body TEXT);
            CREATE TABLE frame_messages(frame_id TEXT, msg_json TEXT);
            """)
    }

    func remove() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Runs SQL against the file, read-write: for building it only.
    func run(_ sql: String) throws {
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        make.arguments = [url.path]
        let input = Pipe()
        make.standardInput = input
        make.standardOutput = FileHandle.nullDevice
        try make.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        make.waitUntilExit()
        #expect(make.terminationStatus == 0)
    }

    static func quote(_ text: String?) -> String {
        text.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? "NULL"
    }

    func project(_ id: String, _ name: String, archivedAt: Int? = nil) throws {
        let archived = archivedAt == nil ? "" : ", archived_at"
        let value = archivedAt.map { ", \($0)" } ?? ""
        try run("INSERT INTO projects(id, name, description, context\(archived)) VALUES (\(Self.quote(id)), \(Self.quote(name)), 'SECRET-DESCRIPTION', 'SECRET-CONTEXT'\(value));")
    }

    static func frameSQL(_ id: String, project: String = "proj_a", name: String? = "Made-up session",
                         status: String = "completed", created: Int64, updated: Int64, completed: Int64? = nil,
                         lastUser: Int64? = nil, parent: String? = nil, hidden: Bool = false,
                         type: String = "chat", agent: String = "OPERON", summary: String? = "SECRET-SUMMARY",
                         input: String = #"{"request":"SECRET-INPUT"}"#) -> String {
        """
        INSERT INTO frames VALUES (\(quote(id)), \(quote(project)), \(quote(name)), \(quote(status)), \(created), \(updated),
            \(completed.map(String.init) ?? "NULL"), \(lastUser.map(String.init) ?? "NULL"), \(quote(parent ?? id)), \(quote(parent)),
            10, 20, \(hidden ? 1 : 0), '{"response":"SECRET-OUTPUT"}', \(quote(input)), \(quote(summary)), \(quote(type)),
            \(quote(agent)), 'SECRET-STATUS-LINE');
        """
    }

    func frame(_ id: String, project: String = "proj_a", name: String? = "Made-up session", status: String = "completed",
               created: Int64 = 1_791_800_000_000, updated: Int64 = 1_791_800_000_000, completed: Int64? = nil,
               lastUser: Int64? = nil, parent: String? = nil, hidden: Bool = false, type: String = "chat",
               agent: String = "OPERON", summary: String? = "SECRET-SUMMARY",
               input: String = #"{"request":"SECRET-INPUT"}"#) throws {
        try run(Self.frameSQL(id, project: project, name: name, status: status, created: created, updated: updated,
                              completed: completed, lastUser: lastUser, parent: parent, hidden: hidden, type: type,
                              agent: agent, summary: summary, input: input))
    }
}

/// A made-up frame id, `n` in its last group.
func madeUpID(_ n: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012x", n)
}

/// Every string a row holds, to check nothing secret came out.
private func strings(_ value: Any) -> [String] {
    Mirror(reflecting: value).children.flatMap { child -> [String] in
        if let text = child.value as? String { return [text] }
        if let optional = child.value as? String?, let text = optional { return [text] }
        return []
    }
}

@Suite(.serialized)
struct BrowseSQLTests {
    @Test func projectsCountTheSessionsTheListShowsNewestFirst() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Made-up A")
        try db.project("proj_b", "Made-up B")
        try db.project("proj_empty", "Made-up empty")
        try db.project("proj_concierge_sys_1", "SECRET-CONCIERGE")
        // `_` is literal: this one is not the concierge's.
        try db.project("proj_concierge_sysX1", "Made-up lookalike")
        try db.project("proj_old", "Made-up archived", archivedAt: 1_791_000_000_000)
        try db.frame(madeUpID(1), project: "proj_a", updated: 1_791_800_000_000)
        try db.frame(madeUpID(2), project: "proj_a", updated: 1_791_810_000_000)
        try db.frame(madeUpID(3), project: "proj_b", updated: 1_791_820_000_000)
        // None of these count: a sub-agent, a hidden one, uploads, the concierge agent, no task summary.
        try db.frame(madeUpID(4), project: "proj_a", updated: 1_791_900_000_000, parent: madeUpID(1))
        try db.frame(madeUpID(5), project: "proj_a", updated: 1_791_900_000_000, hidden: true)
        try db.frame(madeUpID(6), project: "proj_a", updated: 1_791_900_000_000, type: "uploads")
        try db.frame(madeUpID(7), project: "proj_a", updated: 1_791_900_000_000, agent: "CONCIERGE")
        try db.frame(madeUpID(8), project: "proj_a", updated: 1_791_900_000_000, summary: nil)
        try db.frame(madeUpID(9), project: "proj_concierge_sysX1", updated: 1_791_700_000_000)

        let projects = try fetchProjects(db: db.url)
        #expect(projects == [
            ProjectRow(id: "proj_b", name: "Made-up B", sessions: 1, lastActiveMs: 1_791_820_000_000),
            ProjectRow(id: "proj_a", name: "Made-up A", sessions: 2, lastActiveMs: 1_791_810_000_000),
            ProjectRow(id: "proj_concierge_sysX1", name: "Made-up lookalike", sessions: 1, lastActiveMs: 1_791_700_000_000),
            ProjectRow(id: "proj_empty", name: "Made-up empty", sessions: 0, lastActiveMs: nil),
        ])
        #expect(!projects.flatMap(strings).contains { $0.contains("SECRET") })
    }

    @Test func aDatabaseWithoutArchivedAtListsEveryProject() throws {
        let db = try MadeUpDatabase(archived: false)
        defer { db.remove() }
        try db.project("proj_a", "Made-up A")
        try db.project("proj_b", "Made-up B")
        #expect(try fetchProjects(db: db.url).map(\.id) == ["proj_a", "proj_b"])
    }

    @Test func pagesWalkEverySessionOnceNewestFirstThroughTies() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Made-up A")
        // 120 sessions; every three share an updated_at, so the id breaks ties.
        var sql = ""
        for n in 1...120 {
            sql += MadeUpDatabase.frameSQL(madeUpID(n), name: "Session \(n)", created: 1_791_000_000_000,
                                           updated: 1_791_000_000_000 + Int64(n / 3) * 1000)
        }
        sql += MadeUpDatabase.frameSQL(madeUpID(500), project: "proj_b", created: 1_791_000_000_000, updated: 1_799_000_000_000)
        try db.run(sql)
        var seen: [String] = []
        var cursor: BrowseCursor?
        var pages: [Int] = []
        repeat {
            let rows = try #require(try fetchProjectSessions(db: db.url, project: "proj_a", after: cursor, search: nil))
            let page = Array(rows.prefix(BrowseSQL.pageSize))
            pages.append(page.count)
            seen += page.map(\.id)
            cursor = rows.count > BrowseSQL.pageSize ? page.last.map { BrowseCursor(updatedMs: $0.updatedMs, id: $0.id) } : nil
        } while cursor != nil
        #expect(pages == [50, 50, 20])
        let expected = (1...120).map { (n: $0, updated: $0 / 3) }
            .sorted { ($0.updated, madeUpID($0.n)) > ($1.updated, madeUpID($1.n)) }.map { madeUpID($0.n) }
        #expect(seen == expected)
    }

    @Test func aSearchMatchesItsTextLiterally() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        let names = ["50% done", "50 percent done", "a_b test", "axb test", "it's here", "plain"]
        var sql = ""
        for (n, name) in names.enumerated() {
            sql += MadeUpDatabase.frameSQL(madeUpID(n + 1), name: name, created: 1, updated: 1_791_000_000_000 + Int64(n))
        }
        try db.run(sql)
        func search(_ text: String) throws -> [String] {
            try fetchProjectSessions(db: db.url, project: "proj_a", after: nil, search: text)?.map(\.name) ?? []
        }
        #expect(try search("0%") == ["50% done"])
        #expect(try search("%") == ["50% done"])
        #expect(try search("a_b") == ["a_b test"])
        #expect(try search("'s") == ["it's here"])
        #expect(try search("PLAIN") == ["plain"])
        #expect(try search("\\") == [])
        #expect(try search("x' OR '1'='1") == [])
    }

    @Test func aBadProjectIdReadsNothing() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        #expect(try fetchProjectSessions(db: db.url, project: "proj_a' OR 1=1 --", after: nil, search: nil) == nil)
        #expect(try fetchProjectSessions(db: db.url, project: "", after: nil, search: nil) == nil)
        #expect(try fetchProjectSessions(db: db.url, project: "p", after: BrowseCursor(updatedMs: 1, id: "x'"), search: nil) == nil)
    }

    @Test func thePointLookupFindsAnyRootAndOnlyRoots() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Made-up A")
        // A root without a task summary still opens.
        try db.frame(madeUpID(1), name: "Made-up root", status: "awaiting_plan_approval", created: 1_791_000_000_000,
                     updated: 1_791_000_600_000, completed: 1_790_000_000_000, lastUser: 1_791_000_300_000, summary: nil)
        try db.frame(madeUpID(2), parent: madeUpID(1))
        try db.frame(madeUpID(3), hidden: true)
        try db.frame(madeUpID(4), agent: "CANVAS_CONCIERGE")
        let row = try #require(try fetchSession(db: db.url, id: madeUpID(1)))
        #expect(row == BrowseRow(id: madeUpID(1), projectID: "proj_a", projectName: "Made-up A", name: "Made-up root",
                                 status: "awaiting_plan_approval", createdMs: 1_791_000_000_000, updatedMs: 1_791_000_600_000,
                                 completedMs: 1_790_000_000_000, turnStartedMs: 1_791_000_300_000))
        let status = row.status(port: 9100)
        #expect(status.state == .needsInput)
        #expect(status.waitingReason == .plan)
        // A completed_at from an earlier turn isn't this turn's end.
        #expect(status.updatedAt == Date(timeIntervalSince1970: 1_791_000_600))
        #expect(status.startedAt == Date(timeIntervalSince1970: 1_791_000_300))
        #expect(status.deepLink?.absoluteString == "http://localhost:9100/projects/proj_a/frames/\(madeUpID(1))")
        for id in [madeUpID(2), madeUpID(3), madeUpID(4), madeUpID(99)] {
            #expect(try fetchSession(db: db.url, id: id) == nil)
        }
        #expect(try fetchSession(db: db.url, id: "' OR 1=1 --") == nil)
    }

    @Test func theIntentLookupFindsOnlyThisProjectsRecentRoot() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
        let now = Date(timeIntervalSince1970: 1_791_833_400)
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let input = #"{"request":"SECRET-INPUT","_intent_id":"\#(intent)"}"#
        try db.frame(madeUpID(1), project: "proj_a", created: ms - 2 * 60_000, input: input)
        // Broken JSON elsewhere doesn't stop the query.
        try db.frame(madeUpID(2), project: "proj_a", created: ms - 60_000, input: "{SECRET not json")
        #expect(try fetchSessionByIntent(db: db.url, project: "proj_a", intent: intent, now: now) == madeUpID(1))
        #expect(try fetchSessionByIntent(db: db.url, project: "proj_b", intent: intent, now: now) == nil)
        #expect(try fetchSessionByIntent(db: db.url, project: "proj_a", intent: "6ba7b810-9dad-41d1-80b4-00c04fd430c8", now: now) == nil)
        // Older than ten minutes, or a sub-agent: not the one.
        #expect(try fetchSessionByIntent(db: db.url, project: "proj_a", intent: intent, now: now.addingTimeInterval(11 * 60)) == nil)
        let other = "2c5f39cb-3fb2-42e3-994f-1127dde4b538"
        try db.frame(madeUpID(3), project: "proj_a", created: ms, parent: madeUpID(1),
                     input: #"{"_intent_id":"\#(other)"}"#)
        #expect(try fetchSessionByIntent(db: db.url, project: "proj_a", intent: other, now: now) == nil)
        // Ids out of shape are never put into the SQL.
        #expect(try fetchSessionByIntent(db: db.url, project: "proj_a", intent: "' OR 1=1 --", now: now) == nil)
        #expect(try fetchSessionByIntent(db: db.url, project: "a'b", intent: intent, now: now) == nil)
    }

    @Test func projectIDs() {
        #expect(BrowseSQL.isProjectID("proj_demo-1"))
        #expect(BrowseSQL.isProjectID(String(repeating: "a", count: 64)))
        #expect(!BrowseSQL.isProjectID(String(repeating: "a", count: 65)))
        for bad in ["", "a b", "a/b", "a.b", "a'b", "a%41", "é"] { #expect(!BrowseSQL.isProjectID(bad)) }
    }
}
