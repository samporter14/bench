// QuickOpenSearchTests.swift — Quick Open finding sessions beyond the recent
// ones: the database's name search (made-up databases, with the columns the
// reads expect), how its answer is merged after the recent sessions, and the
// searcher that waits for typing to pause, reads off the main actor and drops
// an answer for a query that has moved on. Made-up names only; nothing reads
// Claude Science's own database.
import Foundation
import Testing
@testable import Bench

// MARK: The database's name search

@Suite(.serialized)
struct SessionNameSearchTests {
    private func names(_ rows: [BrowseRow]) -> [String] { rows.map(\.name) }

    @Test func aWordIsFoundInTheTitleAnywhereInItIgnoringCase() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.frame(madeUpID(1), name: "Gel imaging", updated: 1_791_800_000_000)
        try db.frame(madeUpID(2), name: "Angelica notes", updated: 1_791_800_001_000)
        try db.frame(madeUpID(3), name: "Western blot", updated: 1_791_800_002_000)
        let rows = try fetchSessionsNamed(db: db.url, words: ["GEL"], limit: 10)
        // Newest first; "Western blot" has no "gel".
        #expect(names(rows) == ["Angelica notes", "Gel imaging"])
    }

    @Test func aWordIsFoundInTheProjectNameToo() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Soil microbiome")
        try db.project("proj_b", "Enzyme kinetics")
        try db.frame(madeUpID(1), project: "proj_a", name: "Plate map", updated: 1_791_800_000_000)
        try db.frame(madeUpID(2), project: "proj_b", name: "Plate map", updated: 1_791_800_001_000)
        let rows = try fetchSessionsNamed(db: db.url, words: ["microbiome"], limit: 10)
        #expect(rows.map(\.id) == [madeUpID(1)])
        #expect(rows.first?.projectName == "Soil microbiome")
        // An untitled session is found by its project, as Quick Open lists it.
        try db.frame(madeUpID(3), project: "proj_a", name: nil, updated: 1_791_800_002_000)
        #expect(try fetchSessionsNamed(db: db.url, words: ["soil"], limit: 10).map(\.id) == [madeUpID(3), madeUpID(1)])
    }

    @Test func everyWordMustMatchInTheTitleOrTheProject() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Soil microbiome")
        try db.project("proj_b", "Enzyme kinetics")
        try db.frame(madeUpID(1), project: "proj_a", name: "Gel imaging", updated: 1_791_800_000_000)
        try db.frame(madeUpID(2), project: "proj_b", name: "Gel imaging", updated: 1_791_800_001_000)
        try db.frame(madeUpID(3), project: "proj_a", name: "Primer design", updated: 1_791_800_002_000)
        // One word in the title and one in the project; "gel" alone would match two.
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel", "soil"], limit: 10).map(\.id) == [madeUpID(1)])
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel", "primer"], limit: 10).isEmpty)
    }

    @Test func wildcardsAndQuotesInAWordMatchOnlyThemselves() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.frame(madeUpID(1), name: "100% pure", updated: 1_791_800_000_000)
        try db.frame(madeUpID(2), name: "1000 samples", updated: 1_791_800_001_000)
        try db.frame(madeUpID(3), name: "a_b", updated: 1_791_800_002_000)
        try db.frame(madeUpID(4), name: "axb", updated: 1_791_800_003_000)
        try db.frame(madeUpID(5), name: #"back\slash"#, updated: 1_791_800_004_000)
        try db.frame(madeUpID(6), name: "O'Brien", updated: 1_791_800_005_000)
        func found(_ word: String) throws -> [String] { try fetchSessionsNamed(db: db.url, words: [word], limit: 10).map(\.id) }
        #expect(try found("0%") == [madeUpID(1)])
        #expect(try found("a_b") == [madeUpID(3)])
        #expect(try found(#"\s"#) == [madeUpID(5)])
        #expect(try found("O'B") == [madeUpID(6)])
        // Bound as a value, never part of the statement.
        #expect(try found("' OR 1=1 --").isEmpty)
        // Not "everything": only a name with a percent sign in it.
        #expect(try found("%") == [madeUpID(1)])
    }

    @Test func nothingHiddenOrSystemEverComesBack() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Gel work")
        try db.frame(madeUpID(1), project: "proj_a", name: "Gel imaging", updated: 1_791_800_000_000)
        // Each of these names matches "gel", and none is a session the list shows.
        try db.frame(madeUpID(2), project: "proj_a", name: "Gel helper", updated: 1_791_800_001_000, parent: madeUpID(1))
        try db.frame(madeUpID(3), project: "proj_a", name: "Gel hidden", updated: 1_791_800_002_000, hidden: true)
        try db.frame(madeUpID(4), project: "proj_a", name: "Gel uploads", updated: 1_791_800_003_000, type: "uploads")
        try db.frame(madeUpID(5), project: "proj_a", name: "Gel concierge", updated: 1_791_800_004_000, agent: "CONCIERGE")
        try db.frame(madeUpID(6), project: "proj_a", name: "Gel canvas concierge", updated: 1_791_800_005_000, agent: "CANVAS_CONCIERGE")
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 10).map(\.id) == [madeUpID(1)])
    }

    @Test func aSessionWithNoSummaryOrInAnArchivedProjectIsStillFound() throws {
        // As the Recent list has it: Quick Open must find what Recent shows.
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Gel work")
        try db.project("proj_old", "Gel archive", archivedAt: 1_791_000_000_000)
        try db.frame(madeUpID(1), project: "proj_a", name: "Gel one", updated: 1_791_800_000_000, summary: nil)
        try db.frame(madeUpID(2), project: "proj_old", name: "Gel two", updated: 1_791_800_001_000)
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 10).map(\.id) == [madeUpID(2), madeUpID(1)])
    }

    @Test func atMostTheLimitComeBackNewestFirst() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        for n in 1...12 {
            try db.frame(madeUpID(n), name: "Gel run \(n)", updated: 1_791_800_000_000 + Int64(n) * 1_000)
        }
        // The same time as the newest: the larger id first.
        try db.frame(madeUpID(13), name: "Gel run 13", updated: 1_791_800_012_000)
        let rows = try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 5)
        #expect(rows.map(\.id) == [madeUpID(13), madeUpID(12), madeUpID(11), madeUpID(10), madeUpID(9)])
        // A limit out of range is brought in: at least one, at most a hundred.
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 0).count == 1)
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: -3).count == 1)
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 1_000).count == 13)
    }

    @Test func noMoreThanAHundredEverComeBack() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        // One statement, not 105 processes.
        try db.run((1...105).map { n in
            MadeUpDatabase.frameSQL(madeUpID(n), name: "Gel run \(n)", created: 1_791_800_000_000,
                                    updated: 1_791_800_000_000 + Int64(n) * 1_000)
        }.joined(separator: "\n"))
        let rows = try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 10_000)
        #expect(rows.count == 100)
        // The newest hundred.
        #expect(rows.first?.id == madeUpID(105) && rows.last?.id == madeUpID(6))
    }

    @Test func aSessionBeyondTheRecentOnesIsFound() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        // 40 newer sessions: far past the ~25 the poll reads.
        try db.frame(madeUpID(1), name: "Old gel imaging", updated: 1_700_000_000_000)
        for n in 2...41 {
            try db.frame(madeUpID(n), name: "Notebook \(n)", updated: 1_791_800_000_000 + Int64(n) * 1_000)
        }
        let recent = try fetchRecentFrames(db: db.url).map(\.id)
        #expect(!recent.contains(madeUpID(1)))
        #expect(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 10).map(\.id) == [madeUpID(1)])
    }

    @Test func blankWordsAndTooManyWordsAreDealtWith() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.frame(madeUpID(1), name: "alpha beta gamma delta epsilon zeta eta", updated: 1_791_800_000_000)
        #expect(try fetchSessionsNamed(db: db.url, words: [], limit: 10).isEmpty)
        #expect(try fetchSessionsNamed(db: db.url, words: ["", "  "], limit: 10).isEmpty)
        // Blank words are skipped, not matched against everything.
        #expect(try fetchSessionsNamed(db: db.url, words: ["", "alpha"], limit: 10).count == 1)
        // Only the first six words count: a seventh that matches nothing is ignored.
        let seven = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "nomatch"]
        #expect(try fetchSessionsNamed(db: db.url, words: seven, limit: 10).count == 1)
        #expect(try fetchSessionsNamed(db: db.url, words: Array(seven.prefix(6)) + ["x"], limit: 10).count == 1)
        // A word is cut at 64 characters: this one matches the first 64 of itself, not the rest.
        let long = String(repeating: "a", count: 70)
        try db.frame(madeUpID(2), name: String(repeating: "a", count: 64), updated: 1_791_800_001_000)
        #expect(try fetchSessionsNamed(db: db.url, words: [long], limit: 10).map(\.id) == [madeUpID(2)])
    }

    @Test func aRowHoldsNoTextButNamesAndIds() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.frame(madeUpID(1), name: "Gel imaging", updated: 1_791_800_000_000)
        let row = try #require(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 10).first)
        let text = [row.id, row.projectID, row.projectName, row.name, row.status].joined(separator: " ")
        #expect(!text.contains("SECRET"))
    }

    @Test func aStatusOfTheRowOpensTheSessionOnTheDaemonsPort() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Gel work")
        try db.frame(madeUpID(1), project: "proj_a", name: "Gel imaging", status: "completed", updated: 1_791_800_000_000)
        let row = try #require(try fetchSessionsNamed(db: db.url, words: ["gel"], limit: 10).first)
        let status = row.status(port: 9100)
        #expect(status.deepLink?.absoluteString == "http://localhost:9100/projects/proj_a/frames/\(madeUpID(1))")
        #expect(status.title == "Gel imaging" && status.projectName == "Gel work" && status.state == .finished)
    }
}

// MARK: Merging with the recent sessions

struct QuickOpenMergeTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func session(_ id: String, _ title: String, project: String = "Notebook",
                         state: SessionState = .finished, minutes: Double = 10) -> SessionStatus {
        SessionStatus(id: id, projectID: "p-\(id)", projectName: project, title: title, state: state,
                      updatedAt: Self.now.addingTimeInterval(-minutes * 60))
    }

    private func ids(_ recent: [SessionStatus], _ older: [SessionStatus], _ query: String) -> [String] {
        QuickOpen.rank(recent, plus: older, query: query).map(\.id)
    }

    @Test func aSessionInBothIsListedOnceAsTheRecentOneWithItsLiveState() {
        let live = session("a", "Gel imaging", state: .needsInput, minutes: 1)
        // The database knows it by its status alone, and a little differently.
        let row = session("a", "Gel imaging", state: .finished, minutes: 30)
        let merged = QuickOpen.rank([live], plus: [row, session("b", "Gel notes", minutes: 60)], query: "gel")
        #expect(merged.map(\.id) == ["a", "b"])
        #expect(merged.first?.state == .needsInput)
        // Whichever order the database's answer came in.
        #expect(QuickOpen.rank([live], plus: [session("b", "Gel notes", minutes: 60), row], query: "gel").first?.state == .needsInput)
    }

    @Test func olderSessionsAreRankedByTheSameRulesAsTheRecentOnes() {
        let recent = [
            // "gel" inside a word, and the newest.
            session("recent-inside", "Angelica notes", minutes: 1),
            // g…e…l in order, nothing more.
            session("recent-fuzzy", "Growth experiment log", minutes: 2),
        ]
        let older = [
            // "gel" starting a word, but months old.
            session("older-prefix", "Gel imaging", minutes: 90_000),
            session("older-inside", "Hydrogel casting", minutes: 80_000),
        ]
        #expect(ids(recent, older, "gel") == ["older-prefix", "recent-inside", "older-inside", "recent-fuzzy"])
    }

    @Test func aTieStaysWithTheRecentSessionFirst() {
        // Same tier, same state, same time: the recent one comes first.
        let recent = [session("recent", "Gel imaging", minutes: 5)]
        let older = [session("older", "Gel quantification", minutes: 5)]
        #expect(ids(recent, older, "gel") == ["recent", "older"])
    }

    @Test func nothingTypedListsOnlyTheRecentOnesAsBefore() {
        let recent = [session("a", "One", minutes: 3), session("b", "Two", minutes: 1)]
        #expect(ids(recent, [], "") == ["b", "a"])
        #expect(ids(recent, [], "   ") == ["b", "a"])
    }

    @Test func olderOnesNeedToMatchTheQueryToo() {
        // A stale answer for "ge" is still on screen when the query is "gel".
        let older = [session("x", "Gel imaging"), session("y", "Gene notes")]
        #expect(ids([], older, "gel") == ["x"])
    }
}

// MARK: The searcher

@MainActor
private final class SearchRig {
    /// The words each read was asked for.
    private(set) var lookups: [[String]] = []
    private var replies: [CheckedContinuation<[SessionStatus]?, Never>?] = []
    private var pauses: [CheckedContinuation<Void, Never>] = []
    private(set) var waits = 0

    func search() -> QuickOpenSearch {
        QuickOpenSearch(dependencies: .init(
            lookup: { [unowned self] words in
                lookups.append(words)
                return await withCheckedContinuation { replies.append($0) }
            },
            pause: .milliseconds(250),
            wait: { [unowned self] _ in
                waits += 1
                await withCheckedContinuation { pauses.append($0) }
            }))
    }

    /// Typing has paused long enough, for every search waiting on it.
    func pauseElapses() async {
        // Every search has started waiting by now, the cancelled ones too.
        await settle()
        let waiting = pauses
        pauses = []
        waiting.forEach { $0.resume() }
        await settle()
    }

    /// The `index`th read answers.
    func answer(_ index: Int, _ sessions: [SessionStatus]?) async {
        replies[index]?.resume(returning: sessions)
        replies[index] = nil
        await settle()
    }

    func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    /// A test that ends with a read or a pause still out lets it go, so
    /// nothing is left suspended.
    isolated deinit {
        replies.forEach { $0?.resume(returning: nil) }
        pauses.forEach { $0.resume() }
    }

    static func session(_ id: String, _ title: String = "Gel imaging") -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Notebook", title: title, state: .finished,
                      updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000))
    }
}

@MainActor
struct QuickOpenSearcherTests {
    private typealias Rig = SearchRig

    @Test func nothingIsReadUntilTypingPauses() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.settle()
        #expect(rig.lookups.isEmpty)
        #expect(search.isSearching)
        await rig.pauseElapses()
        #expect(rig.lookups == [["gel"]])
        await rig.answer(0, [Rig.session("a")])
        #expect(search.found.map(\.id) == ["a"])
        #expect(!search.isSearching)
    }

    @Test func typingOnInsideThePauseReadsOnlyTheLastQuery() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("ge")
        search.queryChanged("gel")
        search.queryChanged("gel im")
        await rig.pauseElapses()
        // Three pauses were started and two were cancelled before they ended.
        #expect(rig.waits == 3)
        #expect(rig.lookups == [["gel", "im"]])
    }

    @Test func anAnswerForAnOlderQueryIsDropped() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.pauseElapses()
        #expect(rig.lookups == [["gel"]])
        // Typing moves on while the first read is still out.
        search.queryChanged("gelx")
        await rig.pauseElapses()
        #expect(rig.lookups == [["gel"], ["gelx"]])
        await rig.answer(0, [Rig.session("stale")])
        #expect(search.found.isEmpty)
        #expect(search.isSearching)
        await rig.answer(1, [Rig.session("fresh")])
        #expect(search.found.map(\.id) == ["fresh"])
        #expect(!search.isSearching)
    }

    @Test func theNewerAnswerFirstStillWinsOverTheOlderOneArrivingLate() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.pauseElapses()
        search.queryChanged("gelx")
        await rig.pauseElapses()
        await rig.answer(1, [Rig.session("fresh")])
        await rig.answer(0, [Rig.session("stale")])
        #expect(search.found.map(\.id) == ["fresh"])
    }

    @Test func clearingTheQueryClearsWhatWasFoundAndDropsWhatIsOut() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.pauseElapses()
        await rig.answer(0, [Rig.session("a")])
        #expect(search.found.count == 1)
        search.queryChanged("")
        #expect(search.found.isEmpty && !search.isSearching)

        search.queryChanged("gel")
        await rig.pauseElapses()
        search.queryChanged("  ")
        await rig.answer(1, [Rig.session("late")])
        #expect(search.found.isEmpty && !search.isSearching)
    }

    @Test func aQueryTooShortToLookUpReadsNothing() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("g")
        search.queryChanged(" g ")
        await rig.pauseElapses()
        #expect(rig.lookups.isEmpty && rig.waits == 0)
        #expect(!search.isSearching)
        // Two letters in all, over two words, is enough.
        search.queryChanged("g e")
        await rig.pauseElapses()
        #expect(rig.lookups == [["g", "e"]])
    }

    @Test func aSpaceTypedAtTheEndDoesNotSearchAgain() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.pauseElapses()
        await rig.answer(0, [Rig.session("a")])
        search.queryChanged("gel ")
        await rig.pauseElapses()
        #expect(rig.lookups.count == 1)
        #expect(search.found.map(\.id) == ["a"] && !search.isSearching)
    }

    @Test func aDatabaseThatCantBeReadLeavesWhatWasFoundAndTriesAgainOnTheNextQuery() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.pauseElapses()
        await rig.answer(0, [Rig.session("a")])
        search.queryChanged("gel i")
        await rig.pauseElapses()
        await rig.answer(1, nil)
        #expect(search.found.map(\.id) == ["a"] && !search.isSearching)
        // The same words typed again are read again.
        search.queryChanged("gel")
        search.queryChanged("gel i")
        await rig.pauseElapses()
        #expect(rig.lookups.count == 3)
    }

    @Test func cancellingDropsTheAnswerAndForgetsWhatWasFound() async {
        let rig = Rig()
        let search = rig.search()
        search.queryChanged("gel")
        await rig.pauseElapses()
        await rig.answer(0, [Rig.session("a")])
        search.queryChanged("gel i")
        await rig.pauseElapses()
        search.cancel()
        await rig.answer(1, [Rig.session("late")])
        #expect(search.found.isEmpty && !search.isSearching)
    }

    @Test func theWordsSentAreTheQuerysFirstFewCutShort() {
        #expect(QuickOpenSearch.words(in: "Gel   imaging\tplate") == ["Gel", "imaging", "plate"])
        #expect(QuickOpenSearch.words(in: "a b c d e f g h") == ["a", "b", "c", "d", "e", "f"])
        #expect(QuickOpenSearch.words(in: String(repeating: "x", count: 100)) == [String(repeating: "x", count: 64)])
        #expect(QuickOpenSearch.words(in: "").isEmpty && QuickOpenSearch.words(in: "x").isEmpty)
    }
}
