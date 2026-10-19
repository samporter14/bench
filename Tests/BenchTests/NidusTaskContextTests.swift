import Foundation
import Testing
@testable import Bench

struct NidusTaskContextTests {
    private let frame = "12345678-1234-1234-1234-123456789abc"

    private func session(title: String = "Analyze assay", project: String = "Protein study") -> SessionStatus {
        SessionStatus(id: frame, projectID: "lab", projectName: project, title: title,
                      state: .running, updatedAt: Date())
    }

    @Test func sharesOnlyTheExactVisibleTask() {
        let url = URL(string: "http://localhost:8765/projects/lab/frames/\(frame)")!
        let found = NidusTaskSelection.names(url: url, daemonPort: 8765, sessions: [session()])
        #expect(found?.project == "Protein study")
        #expect(found?.task == "Analyze assay")

        let wrongProject = URL(string: "http://localhost:8765/projects/other/frames/\(frame)")!
        #expect(NidusTaskSelection.names(url: wrongProject, daemonPort: 8765, sessions: [session()]) == nil)
        let overview = URL(string: "http://localhost:8765/projects/lab")!
        #expect(NidusTaskSelection.names(url: overview, daemonPort: 8765, sessions: [session()]) == nil)
        let browser = URL(string: "https://example.org/projects/lab/frames/\(frame)")!
        #expect(NidusTaskSelection.names(url: browser, daemonPort: 8765, sessions: [session()]) == nil)
    }

    @Test func requiresReadableNamesAndBoundsThem() {
        let url = URL(string: "http://localhost:8765/projects/lab/frames/\(frame)")!
        #expect(NidusTaskSelection.names(url: url, daemonPort: 8765, sessions: [session(title: "")]) == nil)
        #expect(NidusTaskSelection.names(url: url, daemonPort: 8765, sessions: [session(project: "")]) == nil)
        let found = NidusTaskSelection.names(url: url, daemonPort: 8765,
                                             sessions: [session(title: String(repeating: "A", count: 400) + "\n")])
        #expect(found?.task.count == 240)
        #expect(found?.task.contains("\n") == false)
    }
}
