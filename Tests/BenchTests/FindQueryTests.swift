// FindQueryTests.swift — Find any figure, the pure part: what a typed query
// means (words, kinds, days), how the files found are ranked and set against
// the shelf, and how a file is worded. Made-up names only.
import Foundation
import Testing
@testable import Bench

enum FindTime {
    /// 2026-10-23 12:00 UTC, a Friday.
    static let now = Date(timeIntervalSince1970: 1_792_756_800)
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func parse(_ text: String, kind: ShelfKind? = nil, project: String? = nil, limit: Int = FindQuery.defaultLimit) -> FindQuery? {
        FindQuery.parse(text, kind: kind, project: project, limit: limit, now: now, calendar: utc)
    }

    /// Midnight UTC of 2026-10-23, in milliseconds.
    static let midnight: Int64 = 1_792_713_600_000
    static let dayMs: Int64 = 86_400_000
}

func madeFile(_ name: String, version: String? = nil, session: String = "Plate reader QC", project: String = "Assay development",
              ms: Int64 = FindTime.midnight + 40_000_000, number: Int = 1, mime: String? = nil) -> FoundFile {
    FoundFile(version: version ?? "v-\(name)", artifact: nil, name: name, mime: mime, size: 1_000, createdMs: ms, number: number,
              sessionID: madeUpID(1), sessionTitle: session, projectID: "proj_a", projectName: project)
}

// MARK: What was typed

struct FindQueryTests {
    @Test func tooLittleIsNoQuery() {
        #expect(FindTime.parse("") == nil)
        #expect(FindTime.parse("   ") == nil)
        #expect(FindTime.parse("a") == nil)
        #expect(FindTime.parse(" x ") == nil)
        // Two letters, or one in each of two words, are worth a look.
        #expect(FindTime.parse("ab")?.terms.map(\.text) == ["ab"])
        #expect(FindTime.parse("a b")?.terms.map(\.text) == ["a", "b"])
    }

    @Test func wordsAreCappedAndCut() throws {
        let many = try #require(FindTime.parse("one two three four five six seven eight"))
        #expect(many.terms.count == FindQuery.wordLimit && many.terms.last?.text == "six")
        let long = try #require(FindTime.parse(String(repeating: "x", count: 100)))
        #expect(long.terms.first?.text.count == FindQuery.wordLength)
    }

    @Test func wordsThatNameAKind() throws {
        let query = try #require(FindTime.parse("Figures tables notes csv text"))
        #expect(query.terms.map(\.kind) == [.figure, .table, .document, nil, nil])
        // The plurals and the plain nouns both count; extensions and common words of names don't.
        #expect(FindQuery.kinds["plot"] == .figure && FindQuery.kinds["spreadsheet"] == .table && FindQuery.kinds["report"] == .document)
        #expect(FindQuery.kinds["png"] == nil && FindQuery.kinds["data"] == nil)
    }

    @Test func wordsThatNameADay() throws {
        let query = try #require(FindTime.parse("today yesterday tuesday friday saturday heatmap"))
        let days = query.terms.map(\.day)
        let midnight = FindTime.midnight, day = FindTime.dayMs
        #expect(days[0] == FindDay(from: midnight, to: midnight + day))
        #expect(days[1] == FindDay(from: midnight - day, to: midnight))
        // This Friday is the 23rd: Tuesday was the 20th, Saturday the 17th; Friday is today.
        #expect(days[2] == FindDay(from: midnight - 3 * day, to: midnight - 2 * day))
        #expect(days[3] == FindDay(from: midnight, to: midnight + day))
        #expect(days[4] == FindDay(from: midnight - 6 * day, to: midnight - 5 * day))
        #expect(days[5] == nil)
        #expect(days[0]?.contains(midnight) == true && days[0]?.contains(midnight + day) == false)
    }

    @Test func aDayIsTheCalendarsOwnNotUTCs() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 12:00 UTC is 21:00 in Tokyo, the same date: its today starts nine hours before UTC's.
        let query = try #require(FindQuery.parse("today", now: FindTime.now, calendar: tokyo))
        #expect(query.terms.first?.day?.from == FindTime.midnight - 9 * 3_600_000)
    }

    @Test func theChipsAndThePillAndTheLimit() throws {
        let query = try #require(FindTime.parse("heatmap", kind: .figure, project: "Assay development", limit: 5_000))
        #expect(query.kind == .figure && query.project == "Assay development" && query.limit == FindQuery.maxLimit)
        #expect(try #require(FindTime.parse("heatmap", project: "")).project == nil)
        #expect(try #require(FindTime.parse("heatmap", limit: 0)).limit == 1)
    }

    @Test func theExtensionListsAreTheShelfsOwnKinds() {
        for ext in FindExtensions.figures { #expect(ShelfKind.classify(fileName: "x.\(ext)") == .figure, "\(ext)") }
        for ext in FindExtensions.tables { #expect(ShelfKind.classify(fileName: "x.\(ext)") == .table, "\(ext)") }
        // And what the lists leave out is a document: nothing in the lists is missing a kind it should have.
        for ext in ["md", "pdf", "html", "py", "txt", "json", "ipynb", "docx", "pptx", "tex", "r"] {
            #expect(ShelfKind.classify(fileName: "x.\(ext)") == .document, "\(ext)")
            #expect(!FindExtensions.figures.contains(ext) && !FindExtensions.tables.contains(ext), "\(ext)")
        }
    }

    @Test func aKindConditionHoldsOnlyFixedWords() {
        for kind in ShelfKind.allCases {
            let condition = FindExtensions.condition(kind, column: "a.filename")
            #expect(!condition.contains("?") && !condition.contains(";") && !condition.contains("--"))
        }
        #expect(FindExtensions.condition(.figure, column: "c").hasPrefix("(c LIKE '%.png' OR "))
        #expect(FindExtensions.condition(.document, column: "c").hasPrefix("NOT ("))
    }
}

// MARK: Ranking

struct FindRankingTests {
    private func names(_ files: [FoundFile]) -> [String] { files.map(\.name) }
    private func order(_ files: [FoundFile], _ text: String) throws -> [String] {
        names(FindRanking.order(files, for: try #require(FindTime.parse(text))))
    }

    @Test func anExactNameComesFirstThenWordStartsThenContainsThenTheRest() throws {
        let t = FindTime.midnight
        let files = [
            // Only the session says "volcano": the weakest.
            madeFile("fig_7.png", session: "Volcano plot for the paper", ms: t + 500),
            // "volcano" inside a word of the name.
            madeFile("myvolcanoes.png", ms: t + 400),
            // A word of the name starts with it.
            madeFile("volcano_plot_v2.png", ms: t + 300),
            // The name, whole: the oldest, and first all the same.
            madeFile("volcano.png", ms: t + 100),
        ]
        #expect(try order(files, "volcano") == ["volcano.png", "volcano_plot_v2.png", "myvolcanoes.png", "fig_7.png"])
        // The extension is part of the name, and optional.
        #expect(try order(files, "volcano.png").first == "volcano.png")
    }

    @Test func severalWordsRankByTheirWorstAndMatchNamesAcrossSeparators() throws {
        let t = FindTime.midnight
        let files = [
            madeFile("heatmap.png", session: "Plate reader QC", ms: t + 300),
            madeFile("plate_7_heatmap.png", ms: t + 200),
            madeFile("z_prime_by_plate.png", session: "Heatmaps", ms: t + 100),
        ]
        #expect(try order(files, "plate heatmap") == ["plate_7_heatmap.png", "heatmap.png", "z_prime_by_plate.png"])
        #expect(try order([madeFile("z_prime_by_plate.png"), madeFile("z_prime.png")], "z prime by plate") == ["z_prime_by_plate.png", "z_prime.png"])
    }

    @Test func newestFirstWithinATierAndAFileTwiceIsOnce() throws {
        let t = FindTime.midnight
        let files = [
            madeFile("a_umap.png", version: "v1", ms: t + 100),
            madeFile("b_umap.png", version: "v2", ms: t + 300),
            madeFile("c_umap.png", version: "v3", ms: t + 200),
            madeFile("b_umap.png", version: "v2", ms: t + 300),
        ]
        #expect(try order(files, "umap") == ["b_umap.png", "c_umap.png", "a_umap.png"])
    }

    @Test func aKindOrADayCountsAsMatchingTheName() throws {
        let t = FindTime.midnight
        // "figures" names the kind: a picture matches without the word in its name; a note does not.
        let query = try #require(FindTime.parse("figures"))
        #expect(FindRanking.tier(of: madeFile("volcano.png"), for: query) == .inName)
        #expect(FindRanking.tier(of: madeFile("notes.md"), for: query) == .elsewhere)
        let today = try #require(FindTime.parse("today"))
        #expect(FindRanking.tier(of: madeFile("a.png", ms: t + 1_000), for: today) == .inName)
        #expect(FindRanking.tier(of: madeFile("a.png", ms: t - 1_000), for: today) == .elsewhere)
    }

    @Test func theShelfsFilesAreLeftOutExceptTheOnesAddedFromThisSearch() {
        let files = [madeFile("a.png", version: "on-shelf"), madeFile("b.png", version: "free"), madeFile("c.png", version: "added-here")]
        let onShelf: (String) -> Bool = { $0 == "on-shelf" || $0 == "added-here" }
        #expect(FindRanking.visible(files, onShelf: onShelf).map(\.version) == ["free"])
        #expect(FindRanking.visible(files, onShelf: onShelf, keeping: ["added-here"]).map(\.version) == ["free", "added-here"])
        #expect(FindRanking.visible(files, onShelf: { _ in false }).count == 3)
    }

    @Test func thePlannersFilesAreTheOnesClaudeScienceHides() {
        for name in ["plan.json", "plan_v2.json", "Plan_3.JSON", "goal_main.html", "goal_x_y.html"] {
            #expect(FindRanking.isPlanningFile(name), "\(name)")
        }
        for name in ["plane.png", "airplane.json", "plan.md", "goal.html", "my_goal_1.html", "planning.csv"] {
            #expect(!FindRanking.isPlanningFile(name), "\(name)")
        }
    }
}

// MARK: How a file is worded

struct FoundFileTests {
    private let now = FindTime.now

    @Test func theCaptionIsSessionProjectAndDate() {
        let file = madeFile("a.png", session: "Plate reader QC", project: "Assay development", ms: Int64(now.timeIntervalSince1970 * 1000) - 3_600_000)
        let caption = file.caption(now: now, calendar: FindTime.utc, locale: Locale(identifier: "en_US_POSIX"))
        #expect(caption.hasPrefix("Plate reader QC \u{00B7} Assay development \u{00B7} "))
        #expect(caption.contains("11:00"), "\(caption)")
        let yesterday = madeFile("a.png", ms: FindTime.midnight - 3_600_000)
        #expect(yesterday.caption(now: now, calendar: FindTime.utc).hasSuffix("Yesterday"))
    }

    @Test func anUntitledSessionOrNoProjectIsSaidOrLeftOut() {
        let file = madeFile("a.png", session: "", project: "")
        let caption = file.caption(now: now, calendar: FindTime.utc)
        #expect(caption.hasPrefix("Untitled session \u{00B7} "))
        #expect(caption.components(separatedBy: " \u{00B7} ").count == 2)
    }

    @Test func theKindIsTheShelfsKindOfTheName() {
        #expect(madeFile("a.png").kind == .figure && madeFile("a.csv").kind == .table && madeFile("a.md").kind == .document)
    }
}
