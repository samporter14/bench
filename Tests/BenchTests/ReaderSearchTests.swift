import AppKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct ReaderSearchTests {
    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Search did not finish")
    }

    @Test func findCountsNavigatesAndSwitchesToTheActiveDocument() async {
        let find = ReferenceFind()
        let answer = NSTextView()
        answer.string = "Résumé and resume, then another RESUME."
        find.attach(answer)
        find.show()
        find.query = "resume"
        await waitFor { find.matches.count == 3 }
        #expect(find.countLabel == "1 of 3")
        find.next()
        #expect(find.countLabel == "2 of 3")
        find.previous()
        #expect(find.countLabel == "1 of 3")
        let document = NSTextView()
        document.string = "A document with one resume."
        find.attach(document)
        await waitFor { find.matches.count == 1 }
        #expect(find.countLabel == "1 of 1")
        find.query = "absent"
        await waitFor { find.matches.isEmpty }
        #expect(find.countLabel == "No matches")
    }

    @Test func hidingTheAnswerForAnEmptyPageClearsFindAndCancelsItsQueuedAttachment() async {
        let find = ReferenceFind()
        let answer = NSTextView()
        answer.string = "An answer with two matches: answer."
        find.show()
        find.query = "answer"
        find.attach(answer)
        await waitFor { find.matches.count == 2 }

        // SwiftUI may already have queued an update when the answer is hidden or removed.
        find.attach(answer)
        find.detach(answer)
        await waitFor { find.matches.isEmpty }
        #expect(find.countLabel == "No matches")
        answer.setSelectedRange(NSRange(location: 0, length: 0))
        find.next()
        #expect(answer.selectedRange().length == 0)
        #expect(find.query == "answer")
    }

    @Test func removingTheOldPageDoesNotClearTheNewFindTarget() async {
        let find = ReferenceFind()
        let answer = NSTextView()
        answer.string = "Match and match."
        let document = NSTextView()
        document.string = "One match."
        find.show()
        find.query = "match"
        find.attach(answer)
        await waitFor { find.matches.count == 2 }

        find.attach(document)
        find.detach(answer)
        await waitFor { find.matches.count == 1 }
        #expect(document.selectedRange().length == 5)

        // Closing a document can queue its detach before the answer attaches again.
        find.detach(document)
        find.attach(answer)
        await waitFor { find.matches.count == 2 }
        #expect(answer.selectedRange().length == 5)
    }

    @Test func projectSearchReadsWholeCutAnswersAndOpensAtTheMatchedRow() async throws {
        let project = "project-a"
        let id = "00000000-0000-4000-8000-000000000001"
        let row = BrowseRow(id: id, projectID: project, projectName: "A", name: "Untitled session", status: "completed",
                            createdMs: 0, updatedMs: 0, completedMs: nil, turnStartedMs: 0)
        var requestedProjects: [String] = []
        let dependencies = AnswerSearch.Dependencies(
            projects: { [] },
            sessions: { requested in requestedProjects.append(requested); return [row] },
            page: { _, _ in .page(HistoryPage(total: 2, from: 0, items: [
                .turn(i: 1, role: .claude, at: nil, text: "A long answer starts here", cut: true, files: [])
            ])) },
            turn: { _, index in .turn(HistoryTurn(i: index, role: .claude, at: nil, text: "A long answer about calibration results")) },
            port: { 8765 })
        let search = AnswerSearch(dependencies: dependencies)
        search.start(project: project, query: "calibration")
        await waitFor { !search.searching }
        let found = try #require(search.matches.first)
        #expect(requestedProjects == [project])
        #expect(found.session.id == id && found.row == 1)
        #expect(found.snippet.contains("calibration"))
        #expect(search.status == "Found 1 match.")
    }

    @Test func snippetsMatchWithoutCaseOrAccentSensitivity() {
        #expect(AnswerSearch.snippet("A résumé of the results", matching: "RESUME")?.contains("résumé") == true)
        #expect(AnswerSearch.snippet("Nothing relevant", matching: "calibration") == nil)
    }

    @Test func aCanceledSearchCannotReplaceANewerAnswerSearch() async {
        let project = "project-a"
        let id = "00000000-0000-4000-8000-000000000001"
        let row = BrowseRow(id: id, projectID: project, projectName: "A", name: "Session", status: "completed",
                            createdMs: 0, updatedMs: 0, completedMs: nil, turnStartedMs: 0)
        var firstRead: CheckedContinuation<Void, Never>?
        var reads = 0
        let dependencies = AnswerSearch.Dependencies(
            projects: { [] }, sessions: { _ in [row] },
            page: { _, _ in
                reads += 1
                let number = reads
                if number == 1 { await withCheckedContinuation { firstRead = $0 } }
                return .page(HistoryPage(total: 2, from: 0, items: [
                    .turn(i: 1, role: .claude, at: nil, text: number == 1 ? "older result" : "newer result", cut: false, files: [])
                ]))
            }, turn: { _, _ in .none }, port: { 8765 })
        let search = AnswerSearch(dependencies: dependencies)
        search.start(project: project, query: "older")
        await waitFor { firstRead != nil }
        search.start(project: project, query: "newer")
        await waitFor { !search.searching }
        #expect(search.matches.first?.snippet == "newer result")
        firstRead?.resume()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(search.matches.first?.snippet == "newer result")
    }
}
