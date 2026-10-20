// QuickOpenSearch.swift — older sessions for Quick Open (DESIGN.md, Quick
// Open). The sheet ranks the ~25 recent sessions at once; a typed query is
// also looked up by name in Claude Science's database, off the main actor,
// after a short pause in typing, and what that finds is ranked in after them
// when it arrives. An answer for a query the sheet has moved on from is
// dropped. Nothing found or typed is kept: the sheet owns this, and it goes
// when the sheet does.
import Foundation

@MainActor
final class QuickOpenSearch: ObservableObject {
    /// At most this many sessions come back from the database for a query.
    nonisolated static let limit = 30
    /// A query needs at least this many characters (all its words together)
    /// to be worth a look in the database: one letter matches nearly every
    /// title, and the recent sessions are there for it already.
    static let shortestQuery = 2

    /// What a search needs and does, so tests can stand in for the database
    /// and the clock.
    struct Dependencies {
        /// Sessions whose title or project name contains every word, newest
        /// first, or nil when the database can't be read.
        var lookup: @MainActor (_ words: [String]) async -> [SessionStatus]?
        /// How long typing must pause before a search starts.
        var pause: Duration = .milliseconds(250)
        /// Waits out `pause`; tests stand in for the clock.
        var wait: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

        static func live() -> Dependencies {
            Dependencies(lookup: { words in
                guard Demo.mode == nil else { return nil }
                let port = WebContainer.shared.port
                let rows = await Task.detached(priority: .userInitiated) { () -> [BrowseRow]? in
                    guard let db = resolveDatabase() else { return nil }
                    return try? fetchSessionsNamed(db: db, words: words, limit: QuickOpenSearch.limit)
                }.value
                return rows?.map { $0.status(port: port) }
            })
        }
    }

    /// What the latest answer found, newest first. The sheet ranks it after
    /// the recent sessions, which hold any session it has too.
    @Published private(set) var found: [SessionStatus] = []
    /// A search is waiting out the pause or reading the database.
    @Published private(set) var isSearching = false

    private let dependencies: Dependencies
    private var task: Task<Void, Never>?
    /// Counts the queries, so an answer knows whether it is still wanted.
    private var generation = 0
    /// The words the search in hand (or last answered) is for.
    private var requested: [String] = []

    init(dependencies: Dependencies = .live()) {
        self.dependencies = dependencies
    }

    /// The words of `query` that go to the database: split on spaces as
    /// `QuickOpen.rank` splits them, the first few only, each cut short. None
    /// when the query is too short to look up.
    static func words(in query: String) -> [String] {
        let words = query.split(whereSeparator: \.isWhitespace).prefix(BrowseSQL.searchWordLimit)
            .map { String($0.prefix(BrowseSQL.searchWordLength)) }
        return words.reduce(0) { $0 + $1.count } >= shortestQuery ? words : []
    }

    /// The query changed. The recent sessions answer it at once (the sheet's
    /// ranking); this starts the database's part after a pause, and drops
    /// whatever was under way for an older query.
    func queryChanged(_ query: String) {
        let words = Self.words(in: query)
        guard !words.isEmpty else {
            // Emptied, or too short to look up: nothing is wanted, so what
            // was found goes and so does any search under way.
            stop()
            if !found.isEmpty { found = [] }
            return
        }
        // The same words (a space typed at the end): the search in hand, or
        // its answer, stands.
        guard words != requested else { return }
        stop()
        requested = words
        isSearching = true
        let mine = generation
        task = Task { [weak self] in
            guard let self else { return }
            await dependencies.wait(dependencies.pause)
            guard !Task.isCancelled, generation == mine else { return }
            let answer = await dependencies.lookup(words)
            // The query moved on while the database was read: this answer
            // is for an older one.
            guard !Task.isCancelled, generation == mine else { return }
            isSearching = false
            // A database that can't be read leaves what was found (the sheet
            // ranks it against the current query, so none of it is wrong),
            // and the next keystroke may try again.
            guard let answer else { requested = []; return }
            found = answer
        }
    }

    /// The sheet is going: stop, and forget.
    func cancel() {
        stop()
        found = []
    }

    /// Drops the search in hand: its answer, if it comes, is for a query
    /// nobody wants.
    private func stop() {
        generation += 1
        task?.cancel()
        task = nil
        requested = []
        isSearching = false
    }
}
