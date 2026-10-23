// ResultsOnShelfTests.swift — Results' "On your shelf" section
// (Results/ResultsOnShelf.swift) on made-up kept folders: the rows are the
// Shelf's items, so the count agrees with the pill and a figure kept twice is
// one row; and Open Conversation reaches any kept result's session through
// the router, built from the ids its README kept. Nothing is opened.
import Foundation
import Testing
@testable import Bench

private let now = Date(timeIntervalSince1970: 1_792_674_720)
private let session = "00000000-0000-4000-8000-0000000000aa"
private let project = "00000000-0000-4000-8000-0000000000bb"

private func result(_ file: String, version: String?, folder: String, keptAt: Date = now, name: String? = nil,
                    sessionID: String = session, projectID: String = project) -> KeptResult {
    let stem = (file as NSString).deletingPathExtension
    let record = KeptRecord(
        name: name ?? stem, keptAt: keptAt, projectID: projectID, projectName: "Assay development", sessionID: sessionID,
        sessionTitle: "Plate reader QC",
        figure: KeptFile(path: file, role: .figure, artifact: "a", version: version, index: 1, of: nil, sha256: nil, bytes: 10),
        files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
    return KeptResult(folder: URL(fileURLWithPath: "/tmp/kept/Assay development/\(folder)", isDirectory: true),
                      collection: "Assay development", record: record,
                      text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
}

struct ResultsOnShelfRowsTests {
    @Test func aFigureKeptTwiceIsOneRowAndOneItem() {
        // The same version in two folders: the Shelf and the pill count one.
        let results = [
            result("z.png", version: "v-1", folder: "z", keptAt: now.addingTimeInterval(-600)),
            result("z.png", version: "v-1", folder: "z 2", keptAt: now),
            result("b.png", version: "v-2", folder: "b", keptAt: now.addingTimeInterval(-60)),
        ]
        let rows = ResultsOnShelf.rows(from: results, matching: "")
        #expect(rows.map(\.fileName) == ["z.png", "b.png"])
        #expect(ResultsOnShelf.count(of: results) == 2)
        #expect(ResultsOnShelf.count(of: results) == ShelfRules.items(from: results).count)
        #expect(ResultsOnShelf.countLine(of: results) == "2 items on your shelf")
        #expect(ResultsOnShelf.countLine(of: [results[0]]) == "1 item on your shelf")
    }

    @Test func theSectionListsTheFirstFiveAndSaysHowManyThereAre() {
        let results = (0..<7).map { n in
            result("fig_\(n).png", version: "v-\(n)", folder: "fig_\(n)", keptAt: now.addingTimeInterval(Double(-n)))
        }
        #expect(ResultsOnShelf.rows(from: results, matching: "").count == 5)
        #expect(ResultsOnShelf.showsCount(of: results, matching: ""))
        #expect(!ResultsOnShelf.showsCount(of: Array(results.prefix(5)), matching: ""))
        // Seven folders of five versions: five items, no more to say.
        let doubled = (0..<5).flatMap { n in
            [result("fig_\(n).png", version: "v-\(n)", folder: "fig_\(n)"), result("fig_\(n).png", version: "v-\(n)", folder: "fig_\(n) 2")]
        }
        #expect(doubled.count == 10)
        #expect(ResultsOnShelf.count(of: doubled) == 5)
        #expect(!ResultsOnShelf.showsCount(of: doubled, matching: ""))
        // A filter always says how many are on the shelf.
        #expect(ResultsOnShelf.showsCount(of: Array(results.prefix(2)), matching: "fig"))
    }

    @Test func theFilterMatchesTheNameOrTheFileName() {
        let results = [
            result("z_prime.png", version: "v-1", folder: "Z prime", name: "Plate Z prime"),
            result("viability.csv", version: "v-2", folder: "viability", name: "Counts"),
        ]
        #expect(ResultsOnShelf.rows(from: results, matching: "plate").map(\.fileName) == ["z_prime.png"])
        #expect(ResultsOnShelf.rows(from: results, matching: "VIABILITY").map(\.fileName) == ["viability.csv"])
        #expect(ResultsOnShelf.rows(from: results, matching: "nothing").isEmpty)
    }
}

@MainActor
struct ResultsOnShelfConversationTests {
    @Test func anyKeptResultsConversationOpensFromItsIdsThroughTheRouter() {
        // Capsid has no session in memory here; the old way (LabModel.open(sessionID:))
        // found nothing and did nothing.
        let router = Router()
        var navigated: [URL] = []
        var shown = 0
        router.navigate = { navigated.append($0) }
        router.showWindow = { shown += 1 }
        let kept = result("z.png", version: "v-1", folder: "z")
        ResultsOnShelf.openConversation(of: kept.record, port: 8123, router: router)
        #expect(navigated == [URL(string: "http://localhost:8123/projects/\(project)/frames/\(session)")!])
        #expect(shown == 1)
    }

    @Test func idsADatabaseWouldntHaveJustShowTheWindow() {
        let router = Router()
        var navigated: [URL] = []
        var shown = 0
        router.navigate = { navigated.append($0) }
        router.showWindow = { shown += 1 }
        let odd = result("z.png", version: "v-1", folder: "z", sessionID: "../../etc", projectID: "p/../q")
        ResultsOnShelf.openConversation(of: odd.record, port: 8123, router: router)
        #expect(navigated.isEmpty)
        #expect(shown == 1)
        #expect(ResultsOnShelf.session(of: odd.record, port: 8123).deepLink == nil)
    }

    @Test func theSessionKeepsTheTitleAndProjectTheREADMEKept() {
        let kept = result("z.png", version: "v-1", folder: "z")
        let built = ResultsOnShelf.session(of: kept.record, port: nil)
        #expect(built.id == session && built.projectID == project)
        #expect(built.displayTitle == "Plate reader QC" && built.projectName == "Assay development")
        // No port known: the daemon's usual one.
        #expect(built.deepLink?.absoluteString == "http://localhost:8765/projects/\(project)/frames/\(session)")
    }
}
