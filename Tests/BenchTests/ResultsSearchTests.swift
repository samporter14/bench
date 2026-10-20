import Foundation
import Testing
@testable import Bench

@Suite("Results search scope")
struct ResultsSearchTests {
    private func session(_ id: String, results: ShelfResults, coverage: ShelfCoverage = .recent) -> ShelfSession {
        ShelfSession(session: Fixture.session(id, .finished), coverage: coverage, results: results)
    }

    private func files(_ names: String...) -> ShelfResults {
        .loaded(names.enumerated().map { index, name in
            ArtifactEntry(version: "v\(index)", artifact: nil, name: name, mime: nil, size: 32, at: nil)
        }, at: Date(timeIntervalSince1970: 1))
    }

    @Test func searchRemovesEmptyProjectHeadingsAndKeepsCoverageAndOrder() {
        let first = session("one", results: files("notes.md", "Plot A.png"))
        let second = session("two", results: files("plot B.svg"))
        let older = session("old", results: files("PLOT C.pdf"), coverage: .older)
        let groups = [
            ShelfGroup(coverage: .recent, projectID: "empty", projectName: "Unrelated",
                       sessions: [session("none", results: files("notes.md"))]),
            ShelfGroup(coverage: .recent, projectID: "recent", projectName: "Current",
                       sessions: [first, session("unloaded", results: .notLoaded), second]),
            ShelfGroup(coverage: .older, projectID: "past", projectName: "Earlier", sessions: [older]),
        ]
        let found = ShelfResultSearch.groups(groups, matching: "plot")
        #expect(found.map(\.projectID) == ["recent", "past"])
        #expect(found.map(\.coverage) == [.recent, .older])
        #expect(found.flatMap(\.sessions).map(\.id) == ["one", "two", "old"])
        // Searching never changes a session's loaded list or file order.
        #expect(found[0].sessions == [first, second])
    }

    @Test func unreadAndFailedSessionsDoNotBecomeSearchMatches() {
        let groups = [ShelfGroup(coverage: .recent, projectID: "p", projectName: "Example project", sessions: [
            session("waiting", results: .notLoaded),
            session("loading", results: .loading),
            session("failed", results: .failed(.unreadable)),
            session("empty", results: files()),
        ])]
        #expect(ShelfResultSearch.groups(groups, matching: "Example").isEmpty)
        // Clearing search restores the original sessions, including ones the
        // person can open or retry to extend the searchable results.
        #expect(ShelfResultSearch.groups(groups, matching: "") == groups)
    }

    @Test func noMatchHasNoResidualHeadings() {
        let groups = [ShelfGroup(coverage: .recent, projectID: "p", projectName: "Example", sessions: [
            session("one", results: files("notes.md")),
        ])]
        #expect(ShelfResultSearch.groups(groups, matching: "figure").isEmpty)
    }
}
