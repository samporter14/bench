// ResultsOnShelf.swift — the pure parts of Results' "On your shelf" section
// (DESIGN.md, Results; Shelf): which rows it lists and how many items it says
// there are, and what Open Conversation does on a row. The rows are the
// Shelf's items (`ShelfRules.items`), so a figure kept three times is one row
// here as it is one card in the Shelf and one in the toolbar's pill; and a
// kept result's conversation is opened from the ids its README kept, which
// reach any session, not only the ones Capsid has in memory.
import Foundation

enum ResultsOnShelf {
    /// How many shelved items the section shows before "Open Shelf".
    static let shown = 5

    /// The items the section lists, newest first: the first few, or those whose
    /// name or file name match the filter.
    static func rows(from results: [KeptResult], matching search: String, limit: Int = ResultsOnShelf.shown) -> [ShelfItem] {
        let items = ShelfRules.items(from: results)
        let matching = search.isEmpty ? items : items.filter {
            $0.record.name.localizedCaseInsensitiveContains(search) || $0.fileName.localizedCaseInsensitiveContains(search)
        }
        return Array(matching.prefix(limit))
    }

    /// How many items are on the shelf, as the pill and the Shelf count them.
    static func count(of results: [KeptResult]) -> Int {
        ShelfRules.items(from: results).count
    }

    /// "3 items on your shelf".
    static func countLine(of results: [KeptResult]) -> String {
        KeepRules.count(count(of: results), "item") + " on your shelf"
    }

    /// Whether the section says how many there are: more than it lists, or a filter is on.
    static func showsCount(of results: [KeptResult], matching search: String, limit: Int = ResultsOnShelf.shown) -> Bool {
        count(of: results) > limit || !search.isEmpty
    }

    /// The session a kept result came from, built from the ids and words its
    /// README kept (`ReferenceWindowController.session`): its address is made
    /// only from ids as the database has them.
    @MainActor
    static func session(of record: KeptRecord, port: Int?) -> SessionStatus {
        ReferenceWindowController.session(id: record.sessionID, projectID: record.projectID, title: record.sessionTitle,
                                          projectName: record.projectName, port: port)
    }

    /// Open Conversation on a row: the session built from the record, opened
    /// through the router, whether or not Capsid has it in memory (a kept
    /// result can be older than the last 30 sessions it lists). The router
    /// opens its address, or just shows the window when the ids aren't ones
    /// the database has.
    @MainActor
    static func openConversation(of record: KeptRecord, port: Int? = WebContainer.shared.port, router: Router = .shared) {
        router.open(session(of: record, port: port))
    }
}
