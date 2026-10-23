// FindSearch.swift — looking for a figure or a file across every session
// (DESIGN.md, Find any figure). The Shelf window's search field and Quick Open
// each own one: typing is looked up in Claude Science's database after a short
// pause, off the main actor, one read at a time, and the answer is ranked
// (`FindRanking`) and published. An answer for a query that has moved on is
// dropped; closing the window or the sheet cancels the read, which SQLite
// notices at its next progress callback. Nothing typed or found is kept, and
// nothing is written anywhere.
import Foundation

@MainActor
final class FindSearch: ObservableObject {
    /// What a search needs and does, so tests can stand in for the database
    /// and the clock.
    struct Dependencies {
        /// The files matching the query, or nil when the database can't be read.
        var lookup: @MainActor (_ query: FindQuery) async -> [FoundFile]?
        /// How long typing must pause before a search starts.
        var pause: Duration = .milliseconds(250)
        /// Waits out `pause`; tests stand in for the clock.
        var wait: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        /// The day "today" means.
        var now: @MainActor () -> Date = { Date() }

        static func live() -> Dependencies {
            Dependencies(lookup: { query in
                // A demo reads nothing: its windows find nothing, rather than say the database is down.
                guard Demo.mode == nil else { return [] }
                return await FindSearch.databaseFiles(query)
            })
        }
    }

    /// The live read shares cancellation with its asking task: a new query
    /// cancels the old one, which, if still queued behind another database
    /// read, never runs, and if running, stops at SQLite's next progress or
    /// busy callback.
    nonisolated static func databaseFiles(
        _ query: FindQuery,
        resolve: @escaping @Sendable () -> URL? = { resolveDatabase() },
        read: @escaping @Sendable (URL, FindQuery, SQLiteReadCancellation) throws -> [FoundFile] = {
            try fetchFiles(db: $0, query: $1, cancellation: $2)
        }
    ) async -> [FoundFile]? {
        let cancellation = SQLiteReadCancellation()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) { () -> [FoundFile]? in
                guard !cancellation.isCancelled, let db = resolve(), !cancellation.isCancelled else { return nil }
                return try? read(db, query, cancellation)
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// The files the latest answer found, best match first. Callers take away
    /// what is on the shelf (`FindRanking.visible`).
    @Published private(set) var files: [FoundFile] = []
    /// A search is waiting out the pause or reading the database.
    @Published private(set) var isSearching = false
    /// The last search couldn't read the database.
    @Published private(set) var couldntRead = false
    /// The query the files answer, or the one being looked up; nil when the
    /// text is too short to look up.
    @Published private(set) var query: FindQuery?
    /// The database returned as many as it was asked for, so there may be more.
    @Published private(set) var mayHaveMore = false

    private let dependencies: Dependencies
    private var task: Task<Void, Never>?
    /// Counts the queries, so an answer knows whether it is still wanted.
    private var generation = 0
    /// The query the search in hand (or last answered) is for.
    private var requested: FindQuery?

    init(dependencies: Dependencies = .live()) {
        self.dependencies = dependencies
    }

    /// The text, kind chip and project of the window changed. Too little to
    /// look up: whatever was found goes, and so does a search under way. The
    /// same query again (a space typed at the end): the search in hand, or its
    /// answer, stands.
    func update(_ text: String, kind: ShelfKind? = nil, project: String? = nil, limit: Int = FindQuery.defaultLimit) {
        guard let next = FindQuery.parse(text, kind: kind, project: project, limit: limit, now: dependencies.now()) else {
            stop()
            query = nil
            if !files.isEmpty { files = [] }
            couldntRead = false
            mayHaveMore = false
            return
        }
        // Compared as parsed, but the day a word names moves with the clock:
        // "today" typed before midnight is not "today" after it.
        guard next != requested else { return }
        stop()
        requested = next
        query = next
        isSearching = true
        couldntRead = false
        let mine = generation
        task = Task { [weak self] in
            guard let self else { return }
            await dependencies.wait(dependencies.pause)
            guard !Task.isCancelled, generation == mine else { return }
            let answer = await dependencies.lookup(next)
            // The query moved on while the database was read.
            guard !Task.isCancelled, generation == mine else { return }
            isSearching = false
            guard let answer else {
                // Unreadable: what was found stays out of date, so it goes,
                // and the next keystroke may try again.
                files = []
                mayHaveMore = false
                couldntRead = true
                requested = nil
                return
            }
            mayHaveMore = answer.count >= next.limit
            files = FindRanking.order(answer, for: next)
        }
    }

    /// The window or sheet is going: stop, and forget.
    func cancel() {
        stop()
        query = nil
        files = []
        couldntRead = false
        mayHaveMore = false
    }

    /// Drops the search in hand: its answer, if it comes, is for a query
    /// nobody wants.
    private func stop() {
        generation += 1
        task?.cancel()
        task = nil
        requested = nil
        isSearching = false
    }
}
