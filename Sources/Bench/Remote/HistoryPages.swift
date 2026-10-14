// HistoryPages.swift — the history pages the phone read lately, kept 30
// seconds (Fable's review of 0.5.0, P3). Every read of a history runs in the
// Claude Science page, on the main thread that draws the user's own UI, and
// the phone reads a session's newest page each time it opens or refreshes it.
//
// A page is kept by its session, the history's length (`total`) and where it
// ends (`before`, nil for the newest). The same page of a history just as
// long is answered from here: an earlier page without reading anything, the
// newest after the 12-row tail says the length hasn't changed (the 38 rows
// before it, and their projection, are skipped). An action on the session
// (`RemoteSessions.forget`) lets its pages go, and a read that was under way
// when it landed isn't kept. In memory only.
import Foundation

@MainActor
final class HistoryPages {
    static let lifetime: TimeInterval = 30
    /// At most this many pages are kept, across sessions.
    static let limit = 64

    private struct Key: Hashable {
        let session: String
        let total: Int
        let before: Int?
    }

    private var pages: [Key: (page: HistoryPage, at: Date)] = [:]
    /// The length each session's history had at its last read, and when.
    private var totals: [String: (total: Int, at: Date)] = [:]
    /// Bumped by `forget`: a read begun before it isn't kept.
    private var generations: [String: Int] = [:]

    /// The session's history length as last read, while that is fresh.
    func total(of session: String, now: Date) -> Int? {
        guard let known = totals[session], Self.fresh(known.at, now) else { return nil }
        return known.total
    }

    /// The page kept for this session, length and end, while it is fresh.
    func page(_ session: String, total: Int, before: Int?, now: Date) -> HistoryPage? {
        guard let kept = pages[Key(session: session, total: total, before: before)], Self.fresh(kept.at, now) else { return nil }
        return kept.page
    }

    /// Where the session's pages stand: pass it back to `keep`.
    func generation(of session: String) -> Int {
        generations[session, default: 0]
    }

    /// A page just read, unless an action came since its read began.
    func keep(_ page: HistoryPage, session: String, before: Int?, at now: Date, generation: Int) {
        guard generations[session, default: 0] == generation else { return }
        pages[Key(session: session, total: page.total, before: before)] = (page, now)
        totals[session] = (page.total, now)
        prune(now)
    }

    /// The history still has `total` rows, as just read.
    func confirm(_ session: String, total: Int, at now: Date, generation: Int) {
        guard generations[session, default: 0] == generation else { return }
        totals[session] = (total, now)
    }

    /// An action on the session: its pages go.
    func forget(_ session: String) {
        generations[session, default: 0] += 1
        totals[session] = nil
        pages = pages.filter { $0.key.session != session }
    }

    /// The pages kept now: for tests.
    var count: Int { pages.count }

    private static func fresh(_ at: Date, _ now: Date) -> Bool {
        at <= now && now.timeIntervalSince(at) < lifetime
    }

    private func prune(_ now: Date) {
        pages = pages.filter { Self.fresh($0.value.at, now) }
        totals = totals.filter { Self.fresh($0.value.at, now) }
        while pages.count > Self.limit, let oldest = pages.min(by: { $0.value.at < $1.value.at }) {
            pages[oldest.key] = nil
        }
    }
}
