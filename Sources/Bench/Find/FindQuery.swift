// FindQuery.swift — what was typed into a search for a figure or a file, as
// the database read and the ranking need it (DESIGN.md, Find any figure). Pure:
// no database, no window, so the tests cover every rule.
//
// A query is up to six words. Every word must match, and a word matches a file
// in any of these ways: its name contains the word, its session's title does,
// its project's name does, the word names a kind ("figures", "tables",
// "notes") and the file is of that kind, or the word names a day ("today",
// "yesterday", "tuesday") and the file's latest version was made that day.
// Any of them is enough, so a file named "yesterday.csv" is found by
// "yesterday" as well as the files made yesterday.
import Foundation

/// A day, as the half-open span of milliseconds the database stores times in.
struct FindDay: Equatable, Sendable {
    let from: Int64
    let to: Int64

    func contains(_ ms: Int64) -> Bool { ms >= from && ms < to }
}

struct FindQuery: Equatable, Sendable {
    /// One typed word, and what else it may mean.
    struct Term: Equatable, Sendable {
        /// As typed, cut short.
        let text: String
        /// The kind of file the word names, if it names one.
        let kind: ShelfKind?
        /// The day the word names, if it names one.
        let day: FindDay?
    }

    /// At most this many words count, each cut to this many characters: the
    /// phone's and Quick Open's rule (`BrowseSQL.searchWordLimit`).
    static let wordLimit = BrowseSQL.searchWordLimit
    static let wordLength = BrowseSQL.searchWordLength
    /// A query needs this many characters, all its words together, to be worth
    /// a look: one letter matches nearly every name.
    static let shortest = 2
    /// How many matches the database returns, at most: the newest ones, which
    /// are then ranked. Callers may ask for 1 to this many.
    static let defaultLimit = 100
    static let maxLimit = 200

    let terms: [Term]
    /// The Shelf window's kind chip, when one is chosen.
    var kind: ShelfKind?
    /// The Shelf window's project pill (a project's name), when one is chosen.
    var project: String?
    var limit: Int

    /// The words as typed, folded the way the ranking folds names.
    var phrase: String { terms.map(\.text).joined(separator: " ") }

    /// Nil when there is nothing worth looking up: no words, or fewer than
    /// `shortest` characters among them.
    static func parse(_ text: String, kind: ShelfKind? = nil, project: String? = nil, limit: Int = defaultLimit,
                      now: Date = Date(), calendar: Calendar = .current) -> FindQuery? {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(wordLimit).map { String($0.prefix(wordLength)) }
        guard words.reduce(0, { $0 + $1.count }) >= shortest else { return nil }
        let terms = words.map { word -> Term in
            let key = fold(word)
            return Term(text: word, kind: kinds[key], day: day(named: key, now: now, calendar: calendar))
        }
        return FindQuery(terms: terms, kind: kind, project: project.flatMap { $0.isEmpty ? nil : $0 },
                         limit: min(max(1, limit), maxLimit))
    }

    // MARK: Words that mean more than themselves

    /// Lower case, without accents or marks: how names and words are compared.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The words that name a kind. Nouns only: "csv" and "png" are in the file
    /// names already, and "text" and "data" are far likelier to be a word of a
    /// name than a kind of file.
    static let kinds: [String: ShelfKind] = {
        var map: [String: ShelfKind] = [:]
        for word in ["figure", "figures", "image", "images", "picture", "pictures", "photo", "photos", "plot", "plots",
                     "chart", "charts", "graph", "graphs"] { map[word] = .figure }
        for word in ["table", "tables", "spreadsheet", "spreadsheets"] { map[word] = .table }
        for word in ["document", "documents", "doc", "docs", "note", "notes", "report", "reports", "markdown"] { map[word] = .document }
        return map
    }()

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// The day a folded word names: today, yesterday, or a weekday's most
    /// recent day (today counts: on a Tuesday "tuesday" is today).
    static func day(named key: String, now: Date, calendar: Calendar) -> FindDay? {
        let start = calendar.startOfDay(for: now)
        func span(_ offset: Int) -> FindDay? {
            guard let from = calendar.date(byAdding: .day, value: -offset, to: start),
                  let to = calendar.date(byAdding: .day, value: 1, to: from) else { return nil }
            return FindDay(from: Int64((from.timeIntervalSince1970 * 1000).rounded()),
                           to: Int64((to.timeIntervalSince1970 * 1000).rounded()))
        }
        switch key {
        case "today": return span(0)
        case "yesterday": return span(1)
        default:
            guard let index = weekdays.firstIndex(of: key) else { return nil }
            // Calendar weekdays count Sunday as 1.
            let today = calendar.component(.weekday, from: now) - 1
            return span((today - index + 7) % 7)
        }
    }
}

// MARK: What kind a file is, for the database

/// The extensions `ShelfKind.classify` sorts into figures and tables, which the
/// database read repeats as `LIKE` patterns (it can't call Swift). A test holds
/// the two lists to `classify`, so they can't drift.
enum FindExtensions {
    static let figures = ["png", "jpg", "jpeg", "gif", "webp", "svg", "tif", "tiff", "bmp", "heic", "avif"]
    static let tables = ["csv", "tsv", "xlsx", "xls", "xlsm", "ods", "numbers", "parquet"]

    /// A condition on `column` (a file name): true when the file is of `kind`.
    /// Only fixed words go into it, never anything typed.
    static func condition(_ kind: ShelfKind, column: String) -> String {
        func any(_ list: [String]) -> String { "(" + list.map { "\(column) LIKE '%.\($0)'" }.joined(separator: " OR ") + ")" }
        switch kind {
        case .figure: return any(figures)
        case .table: return any(tables)
        case .document: return "NOT \(any(figures)) AND NOT \(any(tables))"
        }
    }
}

// MARK: A file that was found

/// One file Claude made, as the database lists it: an artifact's latest
/// version, the session it was made in and that session's project. Metadata
/// only, like every read of the database: never the file's bytes, its code or
/// anything Claude said.
struct FoundFile: Equatable, Sendable, Identifiable {
    /// The version's id: what the shelf knows a file by.
    let version: String
    /// The artifact the version belongs to.
    let artifact: String?
    /// The file's name, its last path segment.
    let name: String
    let mime: String?
    let size: Int
    let createdMs: Int64
    /// `version_number`: "version 3".
    let number: Int
    let sessionID: String
    let sessionTitle: String
    let projectID: String
    let projectName: String

    var id: String { version }
    var kind: ShelfKind { ShelfKind.classify(fileName: name) }
    var created: Date { Date(timeIntervalSince1970: Double(createdMs) / 1000) }

    /// "Plate reader QC · Assay development · Yesterday".
    func caption(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let session = sessionTitle.isEmpty ? "Untitled session" : sessionTitle
        let parts = [session, projectName, ShelfRules.when(created, now: now, calendar: calendar, locale: locale)]
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

// MARK: Ranking

enum FindRanking {
    /// How well a file matched, best first.
    enum Tier: Int, Comparable, Sendable {
        /// The name is what was typed.
        case exact
        /// Every word starts a word of the name.
        case prefix
        /// Every word is in the name, or names the file's kind or day.
        case inName
        /// Some word matched only the session's title or the project's name.
        case elsewhere

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// The files best match first: an exact name, then names whose words start
    /// with the query's, then names that contain them, then the rest; newest
    /// first within each. A file listed twice is listed once.
    static func order(_ files: [FoundFile], for query: FindQuery) -> [FoundFile] {
        var seen = Set<String>()
        return files.filter { seen.insert($0.version).inserted }
            .map { (file: $0, tier: tier(of: $0, for: query)) }
            .sorted { a, b in
                if a.tier != b.tier { return a.tier < b.tier }
                if a.file.createdMs != b.file.createdMs { return a.file.createdMs > b.file.createdMs }
                return a.file.version > b.file.version
            }
            .map(\.file)
    }

    static func tier(of file: FoundFile, for query: FindQuery) -> Tier {
        let name = FindQuery.fold(file.name)
        let stem = FindQuery.fold((file.name as NSString).deletingPathExtension)
        let nameWords = words(in: stem)
        let typed = query.terms.map { FindQuery.fold($0.text) }
        let phrase = typed.joined(separator: " ")
        let typedWords = typed.flatMap { words(in: $0) }
        if name == phrase || stem == phrase || (!typedWords.isEmpty && nameWords == typedWords) {
            return .exact
        }
        var worst = Tier.prefix
        for (term, word) in zip(query.terms, typed) {
            let this: Tier
            if nameWords.contains(where: { $0.hasPrefix(word) }) {
                this = .prefix
            } else if name.contains(word) || term.kind == file.kind || term.day?.contains(file.createdMs) == true {
                this = .inName
            } else {
                this = .elsewhere
            }
            worst = max(worst, this)
        }
        return worst
    }

    /// The words of a folded name: runs of letters and numbers.
    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// The files to show: those not on the shelf, by version, except the ones
    /// added from this search (`keeping`), which stay put as "On Shelf ✓"
    /// rather than vanishing under the pointer.
    static func visible(_ files: [FoundFile], onShelf: (String) -> Bool, keeping: Set<String> = []) -> [FoundFile] {
        files.filter { keeping.contains($0.version) || !onShelf($0.version) }
    }

    /// The names Claude Science itself hides from its file list, which the
    /// database lists all the same: `plan*.json` and `goal_*.html`.
    static func isPlanningFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        return (lower.hasPrefix("plan") && lower.hasSuffix(".json")) || (lower.hasPrefix("goal_") && lower.hasSuffix(".html"))
    }
}
