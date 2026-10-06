// QuickOpen.swift — ⌘⇧O (DESIGN.md, Quick Open): type to jump to a session.
// The ranking is a pure function so tests can cover it; QuickOpenSheet is the
// view, and nothing here keeps what was typed or what was found.
import Foundation

enum QuickOpen {
    /// How well a word of the query matched: the order they rank in.
    private enum Match: Int, Comparable {
        /// At the start of a word of the title or project.
        case prefix
        /// Somewhere inside one.
        case substring
        /// Its letters turn up in order, with others between them.
        case fuzzy

        static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    /// The sessions to list for what was typed, best first.
    ///
    /// With nothing typed: the ones that need you, then those that work, then
    /// the rest, each by most recent activity. With a query, only sessions
    /// whose title or project it matches, ignoring case and diacritics; a
    /// query of several words needs every word to match. Prefix-of-word
    /// matches come before substring matches, which come before fuzzy ones,
    /// and within each the order is the one for nothing typed. A session
    /// that appears twice is listed once.
    static func rank(_ sessions: [SessionStatus], query: String) -> [SessionStatus] {
        let ordered = idleOrder(sessions)
        let words = fold(query).split(whereSeparator: \.isWhitespace).map { Array($0) }
        guard !words.isEmpty else { return ordered }
        return ordered.enumerated()
            .compactMap { index, session -> (match: Match, index: Int, session: SessionStatus)? in
                let fields = [session.displayTitle, session.projectName].map { Array(fold($0)) }
                var worst = Match.prefix
                for word in words {
                    guard let best = fields.compactMap({ match(word, in: $0) }).min() else { return nil }
                    worst = max(worst, best)
                }
                return (worst, index, session)
            }
            // The index is the tie-break, so the order never depends on the
            // sort being stable.
            .sorted { ($0.match, $0.index) < ($1.match, $1.index) }
            .map(\.session)
    }

    /// Needs you, working, then the rest: each by most recent activity, and
    /// as given when that is the same.
    private static func idleOrder(_ sessions: [SessionStatus]) -> [SessionStatus] {
        func group(_ session: SessionStatus) -> Int {
            switch session.state {
            case .needsInput: 0
            case .running: 1
            case .finished, .error, .unknown: 2
            }
        }
        var seen = Set<String>()
        return sessions.filter { seen.insert($0.id).inserted }
            .enumerated()
            .sorted { a, b in
                if group(a.element) != group(b.element) { return group(a.element) < group(b.element) }
                if a.element.updatedAt != b.element.updatedAt { return a.element.updatedAt > b.element.updatedAt }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// Lower case, without accents or marks.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// How `word` matches `field`, both already folded; nil when it doesn't.
    private static func match(_ word: [Character], in field: [Character]) -> Match? {
        var inside = false
        if field.count >= word.count {
            for start in 0...(field.count - word.count) where field[start..<start + word.count].elementsEqual(word) {
                // A word starts at the front, or after anything that isn't a
                // letter or a number.
                if start == 0 || !(field[start - 1].isLetter || field[start - 1].isNumber) { return .prefix }
                inside = true
            }
        }
        if inside { return .substring }
        var next = word.startIndex
        for character in field where next < word.endIndex && character == word[next] { next += 1 }
        return next == word.endIndex ? .fuzzy : nil
    }
}

/// Whether Quick Open's sheet shows on the main window. The ⌘⇧O menu item
/// sets it and `MainView` presents the sheet, so the item works whether the
/// window is showing, hidden or behind another app's.
@MainActor
final class QuickOpenPresenter: ObservableObject {
    static let shared = QuickOpenPresenter()
    private init() {}

    @Published var isShowing = false

    func show() {
        Router.shared.showWindow()
        isShowing = true
    }
}
