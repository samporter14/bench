// FindSQLTests.swift — Find any figure's read of the sessions' database: names,
// kinds, projects, session titles and days, against a made-up database that has
// Claude Science's four tables in full (FindFixtures.swift), with and without
// the two indexes the read may hint at. Nothing here opens the real database.
import Foundation
import Testing
@testable import Bench

private let t = findMoment()
private let hour: Int64 = 3_600_000
private let day: Int64 = 86_400_000

/// The same few sessions and files for most of the tests.
///
/// Sessions: s1 "Plate reader QC" and s2 "Melt curve review" in "Assay development"; s3 "Differential
/// expression" in "RNA-seq pilot"; s4 "Figure style" in "Paper draft"; helper (a sub-agent of s1); and the ones
/// that are no session to list: hidden, concierge, uploads.
private func standard(indexes: Bool = true) throws -> FindDatabase {
    let db = try FindDatabase(indexes: indexes)
    try db.project("proj_a", "Assay development")
    try db.project("proj_b", "RNA-seq pilot")
    try db.project("proj_c", "Paper draft")
    try db.session(madeUpID(1), project: "proj_a", title: "Plate reader QC")
    try db.session(madeUpID(2), project: "proj_a", title: "Melt curve review")
    try db.session(madeUpID(3), project: "proj_b", title: "Differential expression")
    try db.session(madeUpID(4), project: "proj_c", title: "Figure style")
    try db.session(madeUpID(11), project: "proj_a", title: "Helper of the plate session", parent: madeUpID(1))
    try db.session(madeUpID(5), project: "proj_a", title: "Hidden plate session", hidden: true)
    try db.session(madeUpID(6), project: "proj_a", title: "Plate concierge", agent: "CONCIERGE")
    try db.session(madeUpID(7), project: "proj_a", title: "Plate uploads", type: "uploads")
    try db.file("z_prime_by_plate.png", in: madeUpID(1), at: t - hour, versions: 3, id: 1)
    try db.file("plate_7_heatmap.png", in: madeUpID(1), at: t - 2 * hour, id: 2)
    try db.file("qc_notes.md", in: madeUpID(1), at: t - 3 * hour, mime: "text/markdown", id: 3)
    try db.file("melt_table.csv", in: madeUpID(2), at: t - day - hour, mime: "text/csv", id: 4)
    try db.file("receptors.xlsx", in: madeUpID(3), project: "proj_b", at: t - 3 * day, mime: "application/vnd.ms-excel", id: 5)
    try db.file("volcano.png", in: madeUpID(3), project: "proj_b", at: t - 2 * day - hour, id: 6)
    try db.file("heatmap_colours.md", in: madeUpID(4), project: "proj_c", at: t - 10 * day, mime: "text/markdown", id: 7)
    return db
}

private func found(_ db: FindDatabase, _ text: String, kind: ShelfKind? = nil, project: String? = nil,
                   limit: Int = FindQuery.defaultLimit) throws -> [FoundFile] {
    let query = try #require(FindTime.parse(text, kind: kind, project: project, limit: limit))
    return try fetchFiles(db: db.url, query: query)
}

private func names(_ files: [FoundFile]) -> [String] { files.map(\.name) }

@Suite(.serialized)
struct FindSQLTests {
    @Test func aWordIsFoundInTheNameAnywhereInItIgnoringCase() throws {
        let db = try standard()
        defer { db.remove() }
        #expect(names(try found(db, "HEATMAP")) == ["plate_7_heatmap.png", "heatmap_colours.md"])
        #expect(names(try found(db, "prime")) == ["z_prime_by_plate.png"])
        // Inside a word; "_" is a letter of the name, not a wildcard.
        #expect(names(try found(db, "ime_by")) == ["z_prime_by_plate.png"])
        #expect(try found(db, "ime-by").isEmpty)
    }

    @Test func aRowIsTheLatestVersionOfAnArtifactWithItsSessionAndProject() throws {
        let db = try standard()
        defer { db.remove() }
        let file = try #require(try found(db, "z_prime").first)
        #expect(file.version == FindDatabase.version(1, 3) && file.number == 3)
        #expect(file.artifact == madeUpID(0x1001))
        #expect(file.name == "z_prime_by_plate.png" && file.mime == "image/png" && file.size == 1_000)
        #expect(file.createdMs == t - hour)
        #expect(file.sessionID == madeUpID(1) && file.sessionTitle == "Plate reader QC")
        #expect(file.projectID == "proj_a" && file.projectName == "Assay development")
        #expect(file.kind == .figure)
    }

    @Test func aWordIsFoundInTheSessionTitleAndInTheProjectName() throws {
        let db = try standard()
        defer { db.remove() }
        // The title: every file of the session, newest first.
        #expect(names(try found(db, "plate reader")) == ["z_prime_by_plate.png", "plate_7_heatmap.png", "qc_notes.md"])
        // The project's name: every file of its sessions.
        #expect(names(try found(db, "rna-seq")) == ["volcano.png", "receptors.xlsx"])
        #expect(names(try found(db, "paper draft")) == ["heatmap_colours.md"])
    }

    @Test func everyWordMustMatchSomewhereAndAnyWayWillDo() throws {
        let db = try standard()
        defer { db.remove() }
        // "heatmap" in the name, "plate" in the name or the title.
        #expect(names(try found(db, "heatmap plate")) == ["plate_7_heatmap.png"])
        // One word in the title and one in the name.
        #expect(names(try found(db, "differential volcano")) == ["volcano.png"])
        #expect(try found(db, "volcano plate").isEmpty)
        // The project, the title and the name.
        #expect(names(try found(db, "assay melt table")) == ["melt_table.csv"])
    }

    @Test func aWordThatNamesAKindMatchesThatKindAndStillMatchesNames() throws {
        let db = try standard()
        defer { db.remove() }
        #expect(names(try found(db, "figures")) == ["z_prime_by_plate.png", "plate_7_heatmap.png", "volcano.png"])
        #expect(names(try found(db, "tables")) == ["melt_table.csv", "receptors.xlsx"])
        #expect(names(try found(db, "notes")) == ["qc_notes.md", "heatmap_colours.md"])
        // With another word: the figures of the QC session.
        #expect(names(try found(db, "figures plate reader")) == ["z_prime_by_plate.png", "plate_7_heatmap.png"])
        // A word that is a kind and a word of a name: the name is found too.
        try db.file("figures_for_paper.md", in: madeUpID(4), project: "proj_c", at: t - 20 * day, mime: "text/markdown", id: 20)
        #expect(names(try found(db, "figures")).contains("figures_for_paper.md"))
    }

    @Test func theKindChipAndTheProjectPillNarrowTheWords() throws {
        let db = try standard()
        defer { db.remove() }
        #expect(names(try found(db, "heatmap", kind: .figure)) == ["plate_7_heatmap.png"])
        #expect(names(try found(db, "heatmap", kind: .document)) == ["heatmap_colours.md"])
        #expect(try found(db, "heatmap", kind: .table).isEmpty)
        #expect(names(try found(db, "heatmap", project: "Paper draft")) == ["heatmap_colours.md"])
        #expect(names(try found(db, "heatmap", kind: .figure, project: "Paper draft")).isEmpty)
        // A project's name is compared whole, not as a piece of it.
        #expect(try found(db, "heatmap", project: "Paper").isEmpty)
        // A document is whatever isn't a figure or a table, whatever its extension.
        try db.file("analysis.py", in: madeUpID(1), at: t - 4 * hour, mime: "text/x-python", id: 21)
        try db.file("report.PDF", in: madeUpID(1), at: t - 5 * hour, mime: "application/pdf", id: 22)
        #expect(names(try found(db, "plate reader", kind: .document)) == ["qc_notes.md", "analysis.py", "report.PDF"])
        // A figure's extension is matched whatever its case.
        try db.file("PHOTO.JPG", in: madeUpID(1), at: t - 6 * hour, id: 23)
        #expect(names(try found(db, "plate reader", kind: .figure)).contains("PHOTO.JPG"))
    }

    @Test func daysAreTheLatestVersionsDateInTheCalendarsOwnDay() throws {
        let db = try standard()
        defer { db.remove() }
        // Midnight UTC is 2026-10-23 00:00: z_prime (-1 h) and the heatmap and notes were made on the 22nd.
        func ask(_ word: String, calendar: Calendar = FindTime.utc) throws -> [String] {
            let query = try #require(FindQuery.parse(word, now: FindTime.now, calendar: calendar))
            return names(try fetchFiles(db: db.url, query: query))
        }
        // Now is 12:00 on the 23rd: -1 h, -2 h and -3 h are all this morning.
        #expect(try ask("today") == ["z_prime_by_plate.png", "plate_7_heatmap.png", "qc_notes.md"])
        #expect(try ask("yesterday") == ["melt_table.csv"])
        #expect(try ask("tuesday") == ["receptors.xlsx"])
        #expect(try ask("sunday").isEmpty)
        // A word of a name still finds the name: a file called "yesterday_plan.md".
        try db.file("yesterday_plan.md", in: madeUpID(4), project: "proj_c", at: t - 9 * day, mime: "text/markdown", id: 24)
        #expect(try ask("yesterday") == ["melt_table.csv", "yesterday_plan.md"])
        // With another word: made today, and about plates.
        #expect(try ask("today heatmap") == ["plate_7_heatmap.png"])
    }

    @Test func nothingIsFoundThatClaudeScienceHidesFromItsOwnList() throws {
        let db = try standard()
        defer { db.remove() }
        try db.file("plan_main.json", in: madeUpID(1), at: t - 4 * hour, mime: "application/json", id: 30)
        try db.file("goal_main.html", in: madeUpID(1), at: t - 4 * hour, mime: "text/html", id: 31)
        try db.file("hidden_by_user.png", in: madeUpID(1), at: t - 4 * hour, priority: "user_hidden", id: 32)
        try db.file("user_upload.png", in: madeUpID(1), at: t - 4 * hour, upload: true, id: 33)
        try db.file("scratch_copy.png", in: madeUpID(1), at: t - 4 * hour, ephemeral: true, id: 34)
        try db.file("autosave_draft.png", in: madeUpID(1), at: t - 4 * hour, intermediate: true, id: 35)
        try db.file("in_hidden_session.png", in: madeUpID(5), at: t - 4 * hour, id: 36)
        try db.file("in_concierge_session.png", in: madeUpID(6), at: t - 4 * hour, id: 37)
        try db.file("in_uploads_session.png", in: madeUpID(7), at: t - 4 * hour, id: 38)
        // A starred file is shown: only `user_hidden` hides.
        try db.file("starred.png", in: madeUpID(1), at: t - 4 * hour, priority: "user_starred", id: 39)
        for hidden in ["plan_main", "goal_main", "hidden_by_user", "user_upload", "scratch_copy", "autosave_draft",
                       "in_hidden_session", "in_concierge_session", "in_uploads_session"] {
            #expect(try found(db, hidden).isEmpty, "\(hidden)")
        }
        #expect(names(try found(db, "starred")) == ["starred.png"])
        // Nor by the words of the session they were made in.
        #expect(try found(db, "hidden plate").isEmpty && (try found(db, "concierge")).isEmpty)
    }

    // MARK: What is left out is left out before the limit

    /// A made-up database in which the newest matches of "run" are all files Find never lists (two hundred of them,
    /// twice the default limit), with five that it does, older. `indexes` as `FindDatabase`.
    private func crowded(indexes: Bool) throws -> FindDatabase {
        let db = try FindDatabase(indexes: indexes)
        try db.project("proj_a", "Assay development")
        try db.session(madeUpID(1), project: "proj_a", title: "Plate reader QC")
        try db.session(madeUpID(5), project: "proj_a", title: "Hidden helper session", hidden: true)
        try db.session(madeUpID(6), project: "proj_a", title: "Concierge session", agent: "CONCIERGE")
        try db.session(madeUpID(7), project: "proj_a", title: "Uploads session", type: "uploads")
        var sql = ""
        var id = 1
        func add(_ name: String, in session: String, at: Int64, mime: String = "image/png") {
            sql += FindDatabase.fileSQL(name, in: session, at: at, mime: mime, id: id).sql
            id += 1
        }
        // The newest: a hidden session's files, the concierge's, the uploads session's, and the planner's own.
        for n in 1...60 { add("run_hidden_\(n).png", in: madeUpID(5), at: t - Int64(n) * 60_000) }
        for n in 1...40 { add("run_concierge_\(n).png", in: madeUpID(6), at: t - Int64(100 + n) * 60_000) }
        for n in 1...30 { add("run_upload_\(n).png", in: madeUpID(7), at: t - Int64(200 + n) * 60_000) }
        for n in 1...50 { add("plan_run_\(n).json", in: madeUpID(1), at: t - Int64(300 + n) * 60_000, mime: "application/json") }
        for n in 1...20 { add("goal_run_\(n).html", in: madeUpID(1), at: t - Int64(400 + n) * 60_000, mime: "text/html") }
        // Older, and the only ones that should be found.
        for n in 1...5 { add("run_valid_\(n).png", in: madeUpID(1), at: t - Int64(n) * hour) }
        try db.run(sql)
        return db
    }

    @Test func filesFromHiddenSessionsAndThePlannersFilesNeverUseUpTheLimit() throws {
        for indexes in [true, false] {
            let db = try crowded(indexes: indexes)
            defer { db.remove() }
            let valid = (1...5).map { "run_valid_\($0).png" }
            // More than the default limit of them are newer than the first valid one.
            #expect(names(try found(db, "run")) == valid, "indexes: \(indexes)")
            // A smaller limit is filled from the valid ones too, newest first.
            #expect(names(try found(db, "run", limit: 3)) == Array(valid.prefix(3)), "indexes: \(indexes)")
            // And with the kind chip on: the same files, the same way.
            #expect(names(try found(db, "run", kind: .figure, limit: 2)) == Array(valid.prefix(2)), "indexes: \(indexes)")
        }
    }

    @Test func theStatementLeavesThemOutBeforeItsLimit() throws {
        let (sql, _) = FindSQL.statement(try #require(FindTime.parse("run", limit: 5)))
        // The limit is applied once, in `top`; the exclusions come before it in the text.
        let limit = try #require(sql.range(of: "LIMIT ?"))
        let sessions = try #require(sql.range(of: "is_hidden IS NOT 1"))
        let planning = try #require(sql.range(of: "plan%.json"))
        #expect(sessions.lowerBound < limit.lowerBound && planning.lowerBound < limit.lowerBound)
        #expect(sql.components(separatedBy: "LIMIT ?").count == 2)
    }

    /// The statement's idea of a planning file is `FindRanking.isPlanningFile`'s: the last part of the name, case ignored,
    /// and "goal_" with its underscore, not any letter.
    @Test func thePlannersFilesAreLeftOutByTheirLastPartAndOnlyThose() throws {
        let db = try FindDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Assay development")
        try db.session(madeUpID(1), project: "proj_a", title: "Plate reader QC")
        let names = ["out/plan_run_main.json", "PLAN_run_Upper.JSON", "planet_run.json", "goal_run_a.html", "figures/goal_run_b.HTML",
                     // Not the planner's:
                     "plan_dir/run_curve.json", "run_plan.json", "goal.run.html", "goalXrun.html", "goal_run.htm", "plan_run.md", "airplane_run.json",
                     "my_goal_run_1.html", "run_plane.png"]
        var sql = ""
        for (n, name) in names.enumerated() {
            sql += FindDatabase.fileSQL(name, in: madeUpID(1), at: t - Int64(n) * 60_000, mime: "text/plain", id: n + 1).sql
        }
        try db.run(sql)
        let listed = Set(names.filter { !FindRanking.isPlanningFile(($0 as NSString).lastPathComponent) })
        #expect(listed.count == 9)
        // The statement alone, before the Swift check on each row, leaves out the same ones.
        let (statement, arguments) = FindSQL.statement(try #require(FindTime.parse("run")))
        let rows = try runReadOnlyQuery(db: db.url, sql: statement, arguments: arguments)
        #expect(Set(rows.map { $0[2] }) == listed)
        #expect(Set(try found(db, "run").map(\.name)) == Set(listed.map { ($0 as NSString).lastPathComponent }))
    }

    @Test func aFileMadeByAHelperBelongsToItsArtifactsSession() throws {
        let db = try standard()
        defer { db.remove() }
        // The version's frame is a sub-agent of s1; the artifact is s1's.
        try db.file("helper_made.png", in: madeUpID(11), at: t - 4 * hour, id: 40)
        try db.run("UPDATE artifacts SET root_frame_id = '\(madeUpID(1))' WHERE filename = 'helper_made.png';")
        let file = try #require(try found(db, "helper_made").first)
        #expect(file.sessionID == madeUpID(1) && file.sessionTitle == "Plate reader QC")
    }

    @Test func atMostTheLimitComeBackNewestFirstAndTheLimitIsBound() throws {
        let db = try FindDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Assay development")
        try db.session(madeUpID(1), project: "proj_a", title: "Gel imaging")
        for n in 1...12 { try db.file("gel_\(n).png", in: madeUpID(1), at: t - Int64(n) * hour, id: 100 + n) }
        #expect(names(try found(db, "gel_", limit: 5)) == ["gel_1.png", "gel_2.png", "gel_3.png", "gel_4.png", "gel_5.png"])
        #expect(try found(db, "gel_").count == 12)
        let (sql, arguments) = FindSQL.statement(try #require(FindTime.parse("gel_", limit: 5)))
        #expect(sql.contains("LIMIT ?") && !sql.contains("LIMIT 5") && arguments.last == .integer(5))
        // Two files at the same moment: the larger version id first.
        try db.file("gel_same_a.png", in: madeUpID(1), at: t, id: 130)
        try db.file("gel_same_b.png", in: madeUpID(1), at: t, id: 131)
        #expect(names(try found(db, "gel_same")) == ["gel_same_b.png", "gel_same_a.png"])
    }

    @Test func wildcardsAndQuotesInAWordMatchOnlyThemselves() throws {
        let db = try FindDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Assay development")
        try db.session(madeUpID(1), project: "proj_a", title: "Gel imaging")
        try db.file("100% pure.csv", in: madeUpID(1), at: t - 1 * hour, mime: "text/csv", id: 1)
        try db.file("1000 samples.csv", in: madeUpID(1), at: t - 2 * hour, mime: "text/csv", id: 2)
        try db.file("a_b.png", in: madeUpID(1), at: t - 3 * hour, id: 3)
        try db.file("axb.png", in: madeUpID(1), at: t - 4 * hour, id: 4)
        try db.file(#"back\slash.png"#, in: madeUpID(1), at: t - 5 * hour, id: 5)
        try db.file("O'Brien.png", in: madeUpID(1), at: t - 6 * hour, id: 6)
        #expect(names(try found(db, "0%")) == ["100% pure.csv"])
        #expect(names(try found(db, "a_b")) == ["a_b.png"])
        #expect(names(try found(db, #"\s"#)) == [#"back\slash.png"#])
        #expect(names(try found(db, "O'B")) == ["O'Brien.png"])
        // Bound as a value, never part of the statement.
        #expect(try found(db, "' OR 1=1 --").isEmpty)
        #expect(try found(db, "%%").isEmpty)
        let (sql, _) = FindSQL.statement(try #require(FindTime.parse("'; DROP TABLE artifacts; --")))
        #expect(!sql.contains("DROP") && !sql.contains("'; "))
    }

    @Test func aRowHoldsNoTextButNamesAndIds() throws {
        let db = try standard()
        defer { db.remove() }
        for file in try found(db, "plate reader") {
            let text = [file.version, file.artifact ?? "", file.name, file.mime ?? "", file.sessionID, file.sessionTitle,
                        file.projectID, file.projectName].joined(separator: " ")
            #expect(!text.contains("SECRET"), "\(file.name)")
        }
    }

    @Test func aNameWithALineBreakStaysOneRowAndAPathIsItsLastSegment() throws {
        let db = try FindDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Assay development")
        try db.session(madeUpID(1), project: "proj_a", title: "Gel\nimaging")
        try db.file("out/figs/split\nname.png", in: madeUpID(1), at: t - hour, id: 1)
        let file = try #require(try found(db, "split").first)
        #expect(file.name == "split name.png" && file.sessionTitle == "Gel imaging")
    }

    @Test func idsThatAreNotTheDaemonsAreLeftOut() throws {
        let db = try FindDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Assay development")
        try db.session("not-a-frame-id", project: "proj_a", title: "Odd session")
        try db.file("odd.png", in: "not-a-frame-id", at: t - hour, id: 1)
        #expect(try found(db, "odd").isEmpty)
    }

    @Test func thePlainAndTheIndexedReadsAgreeAndTheIndexesAreOnlyHintedWhenThere() throws {
        let plain = try standard(indexes: false)
        let indexed = try standard(indexes: true)
        defer { plain.remove(); indexed.remove() }
        for text in ["heatmap", "plate reader", "figures", "tables plate", "today", "rna-seq", "differential volcano"] {
            #expect(names(try found(plain, text)) == names(try found(indexed, text)), "\(text)")
        }
        // The shapes: a hint only when asked for, and nothing typed in the statement either way.
        let query = try #require(FindTime.parse("plate today"))
        let bare = FindSQL.statement(query, shape: .init()).sql
        let hinted = FindSQL.statement(query, shape: .init(namesIndexed: true, versionsIndexed: true)).sql
        #expect(!bare.contains("INDEXED BY"))
        #expect(hinted.contains("INDEXED BY \(FindSQL.namesIndex)") && hinted.contains("INDEXED BY \(FindSQL.versionsIndex)"))
        #expect(!bare.lowercased().contains("plate") && !hinted.lowercased().contains("plate"))
        // The compact index holds only the sessions with a summary (as Claude Science's own list does);
        // the plain read finds a session's files by its title either way.
        try plain.session(madeUpID(8), project: "proj_a", title: "Fresh session", summary: nil)
        try indexed.session(madeUpID(8), project: "proj_a", title: "Fresh session", summary: nil)
        try plain.file("fresh.png", in: madeUpID(8), at: t - hour, id: 50)
        try indexed.file("fresh.png", in: madeUpID(8), at: t - hour, id: 50)
        #expect(names(try found(plain, "fresh session")) == ["fresh.png"])
        #expect(try found(indexed, "fresh session").isEmpty)
        // Its file is found by its name, either way.
        #expect(names(try found(indexed, "fresh.png")) == ["fresh.png"])
    }

    @Test func theIndexesAreNamedTheWayTheMigrationsNameThem() {
        #expect(FindSchema.indexes.map(\.name).contains(FindSQL.namesIndex))
        #expect(FindSchema.indexes.map(\.name).contains(FindSQL.versionsIndex))
    }

    @Test func aCancelledReadNeverRunsAndAnExpiredOneStops() throws {
        let db = try standard()
        defer { db.remove() }
        let query = try #require(FindTime.parse("plate"))
        let cancellation = SQLiteReadCancellation()
        cancellation.cancel()
        #expect(throws: CancellationError.self) { try fetchFiles(db: db.url, query: query, cancellation: cancellation) }
        #expect(throws: (any Error).self) { try fetchFiles(db: db.url, query: query, timeout: 0) }
    }

    @Test func theCountIsTheFilesTheListWouldShow() throws {
        let db = try standard()
        defer { db.remove() }
        #expect(try fetchFileCount(db: db.url) == 7)
        try db.file("hidden_by_user.png", in: madeUpID(1), at: t, priority: "user_hidden", id: 60)
        try db.file("user_upload.png", in: madeUpID(1), at: t, upload: true, id: 61)
        try db.file("scratch.png", in: madeUpID(1), at: t, ephemeral: true, id: 62)
        #expect(try fetchFileCount(db: db.url) == 7)
    }

    @Test func noQueryReadsNothing() throws {
        let db = try standard()
        defer { db.remove() }
        let empty = FindQuery(terms: [], kind: nil, project: nil, limit: 10)
        #expect(try fetchFiles(db: db.url, query: empty).isEmpty)
    }
}

// MARK: What Capsid says it relies on

@Suite(.serialized)
struct FindCompatTests {
    private var findItems: [CompatDependency] { CompatInventory.all.filter { $0.feature == .find } }

    @Test func theInventoryListsEveryColumnTheReadNamesAndNothingElse() {
        let columns = findItems.filter { $0.check == .live }.map(\.token)
        #expect(columns == [
            "artifacts.id", "artifacts.project_id", "artifacts.root_frame_id", "artifacts.filename", "artifacts.latest_version_id",
            "artifacts.is_user_upload", "artifacts.is_ephemeral", "artifacts.priority",
            "artifact_versions.id", "artifact_versions.content_type", "artifact_versions.size_bytes", "artifact_versions.created_at",
            "artifact_versions.version_number", "artifact_versions.is_intermediate",
        ])
        #expect(findItems.allSatisfy { $0.kind == .schema && !$0.optional })
        // The columns of frames and projects it reads are the session reads' own.
        let sessionColumns = Set(CompatInventory.database.filter { $0.feature != .find && $0.check == .live }.map(\.token))
        for token in ["frames.id", "frames.name", "frames.parent_frame_id", "frames.is_hidden", "frames.agent_name",
                      "frames.conversation_type", "frames.task_summary", "projects.id", "projects.name"] {
            #expect(sessionColumns.contains(token), "\(token)")
        }
    }

    @Test func whatLivesInsideTheDatabaseIsListedAsCheckedWhenUsed() {
        let stored = findItems.filter { $0.check != .live }
        #expect(stored.map(\.token) == ["artifacts.priority (user_hidden)", "artifacts.filename (plan, goal)",
                                        "ix_frames_bench_name_search", "ix_artifact_versions_slim_covering"])
        #expect(stored.allSatisfy { $0.isWhenUsed && $0.file == "Shared/Core/SQLiteSource.swift" })
        // The two indexes are the ones the read hints at, by name.
        #expect(stored.contains { $0.token == FindSQL.namesIndex } && stored.contains { $0.token == FindSQL.versionsIndex })
    }

    @Test func theFeatureHasWords() {
        #expect(CompatFeature.find.title == "Find a figure or file from any session, in the Shelf and in Quick Open")
        #expect(CompatFeature.find.inASentence == "finding files")
    }

    @Test func diagnosticsSaysHowManyFilesAndHowLongOneSearchTook() throws {
        let db = try standard()
        defer { db.remove() }
        let lines = Diagnose.fileLines(db: db.url, now: FindTime.now, calendar: FindTime.utc)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.hasPrefix("✓ Files across sessions read: 7 listed; a search for today's files returned 3 in "), "\(line)")
        #expect(line.hasSuffix(" ms"))
        // Counts and a time: no file, session or project is named.
        for word in ["z_prime", "Plate reader", "Assay", "volcano"] { #expect(!line.contains(word)) }
    }

    @Test func diagnosticsSaysWhenTheTablesAreNotThere() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-find-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let empty = dir.appendingPathComponent("empty.db")
        FileManager.default.createFile(atPath: empty.path, contents: nil)
        let line = try #require(Diagnose.fileLines(db: empty).first)
        #expect(line.hasPrefix("✗ Files across sessions: "), "\(line)")
    }

    @Test func diagnosticsAsksTheFindReadAfterTheSessionOnes() {
        let diagnose = FindRepo.source("App/Diagnose.swift")
        #expect(diagnose.contains("out.append(contentsOf: fileLines(db: db))"))
    }
}

// MARK: Measuring

/// Not a check: when `CAPSID_FIND_MEASURE_DB` names a made-up database built
/// from the migrations (never Claude Science's own), times the statements Find
/// runs on it, and prints the numbers. Without it the test does nothing.
@Suite(.serialized)
struct FindMeasureTests {
    @Test func theStatementsAreTimedOnAMadeUpDatabaseWhenAsked() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_FIND_MEASURE_DB"], !path.isEmpty else { return }
        let db = URL(fileURLWithPath: path)
        for text in ["volcano", "plate", "plate heatmap", "fi", "figures plate", "today", "yesterday", "heatmap yesterday", "qc notes"] {
            let query = try #require(FindQuery.parse(text))
            var times: [Int] = []
            var count = 0
            for _ in 0..<3 {
                let started = ContinuousClock.now
                count = try fetchFiles(db: db, query: query, timeout: 20).count
                times.append(Int(((ContinuousClock.now - started) / .milliseconds(1)).rounded()))
            }
            print("FIND-MEASURE \(text): \(count) files, \(times.map(String.init).joined(separator: " / ")) ms")
        }
        let started = ContinuousClock.now
        let total = try fetchFileCount(db: db)
        print("FIND-MEASURE count: \(total) files, \(Int(((ContinuousClock.now - started) / .milliseconds(1)).rounded())) ms")
    }
}
