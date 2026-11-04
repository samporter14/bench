import Foundation
import Testing
@testable import Bench

@MainActor
struct AnswerSearchLimitsTests {
    private func waitUntilFinished(_ search: AnswerSearch) async {
        for _ in 0..<1_000 {
            if !search.searching { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Answer search did not finish")
    }

    private func row(_ number: Int = 1) -> BrowseRow {
        BrowseRow(id: String(format: "00000000-0000-4000-8000-%012d", number),
                  projectID: "project-a", projectName: "A", name: "Session", status: "completed",
                  createdMs: 0, updatedMs: 0, completedMs: nil, turnStartedMs: 0)
    }

    @Test func searchStopsAtTheSessionAndPageLimitsAndSaysItIsIncomplete() async {
        var reads: [String: Int] = [:]
        let sessions = (1...51).map(row)
        let search = AnswerSearch(dependencies: .init(
            projects: { [] }, sessions: { _ in sessions },
            page: { id, before in
                reads[id, default: 0] += 1
                return .page(HistoryPage(total: 1_000, from: (before ?? 1_000) - 50, items: []))
            }, turn: { _, _ in .none }, port: { nil }))
        search.start(project: "project-a", query: "calibration")
        await waitUntilFinished(search)
        #expect(reads.count == 50)
        #expect(reads.values.allSatisfy { $0 == 6 })
        #expect(search.status.contains("Results may be incomplete"))
    }

    @Test func anInterruptedReadEndsTheSpinner() async {
        let session = row()
        let search = AnswerSearch(dependencies: .init(
            projects: { [] }, sessions: { _ in [session] },
            page: { _, _ in throw CancellationError() },
            turn: { _, _ in .none }, port: { nil }))
        search.start(project: "project-a", query: "calibration")
        await waitUntilFinished(search)
        #expect(!search.searching)
        #expect(search.status == "Search interrupted. Showing matches found so far.")
    }

    @Test func anUnreadableFullTurnKeepsPreviewMatchesButReportsIncompleteResults() async {
        let session = row()
        let search = AnswerSearch(dependencies: .init(
            projects: { [] }, sessions: { _ in [session] },
            page: { _, _ in .page(HistoryPage(total: 2, from: 0, items: [
                .turn(i: 1, role: .claude, at: nil, text: "Calibration summary", cut: true, files: [])
            ])) }, turn: { _, _ in .tooBig }, port: { nil }))
        search.start(project: "project-a", query: "calibration")
        await waitUntilFinished(search)
        #expect(search.matches.count == 1)
        #expect(search.matches.first?.row == 1)
        #expect(search.status.contains("Results may be incomplete"))
    }
}
