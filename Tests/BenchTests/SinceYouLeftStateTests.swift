// SinceYouLeftStateTests.swift — `since` in `/api/state`, checked as the JSON
// the phone reads: left out while there is none (so the state every older
// phone page was written for is byte for byte what it was), its own version,
// at most six rows with the whole counts, what is known of the rows, the same
// state at another moment, and the feed that tells the events stream when it
// changes. Made-up sessions only.
import Combine
import Foundation
import Testing
@testable import Bench

@MainActor
struct SinceYouLeftStateTests {
    private let now = Date(timeIntervalSince1970: 1_791_833_400) // 2026-10-12T19:30:00Z

    private func session(_ id: String, _ state: SessionState, reason: WaitingReason? = nil, title: String = "Plate reader QC",
                         updated: Double = -60) -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Assay development", title: title, state: state,
                      updatedAt: now.addingTimeInterval(updated), startedAt: nil, waitingReason: reason)
    }

    private func summary(back: Bool = true, finished: Int = 2, stopped: Int = 1, needs: Int = 1) -> SinceYouLeftSummary {
        func row(_ id: String, _ state: SessionState, at: Double, reason: WaitingReason? = nil) -> SinceYouLeftSummary.Row {
            SinceYouLeftSummary.Row(session: session(id, state, reason: reason, updated: at), at: now.addingTimeInterval(at))
        }
        return SinceYouLeftSummary(
            since: now.addingTimeInterval(-134 * 60), back: back ? now : nil,
            needs: (1...max(needs, 1)).prefix(needs).map { row("n\($0)", .needsInput, at: Double(-41 * $0) * 60, reason: .question) },
            finished: (1...max(finished, 1)).prefix(finished).map { row("f\($0)", .finished, at: Double(-100 + $0) * 60) },
            stopped: (1...max(stopped, 1)).prefix(stopped).map { row("s\($0)", .error, at: Double(-120 + $0) * 60) })
    }

    private func input(since: SinceYouLeftSummary?, details: [String: SinceYouLeftDetail] = [:]) -> RemoteAPI.Input {
        var input = RemoteAPI.Input(bench: "1.0", now: now, problem: nil, waiting: [], snoozed: [], failed: [], working: [],
                                    recent: [], limits: [], forecasts: [:])
        input.since = since
        input.sinceDetails = details
        return input
    }

    private func json(_ state: RemoteAPI.State) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: RemoteAPI.encode(state))) as? [String: Any] ?? [:]
    }

    @Test func aStateWithoutSinceIsExactlyWhatEveryOlderPhonePageWasWrittenFor() {
        let text = String(decoding: RemoteAPI.encode(RemoteAPI.state(input(since: nil))), as: UTF8.self)
        #expect(text == #"{"bench":"1.0","failed":[],"needsYou":[],"pause":null,"problem":null,"recent":[],"updatedAt":"2026-10-12T19:30:00Z","usage":null,"version":1,"working":[]}"#)
        #expect(!text.contains("since"))
        // An empty summary is none.
        let empty = SinceYouLeftSummary(since: now, back: now, needs: [], finished: [], stopped: [])
        #expect(!String(decoding: RemoteAPI.encode(RemoteAPI.state(input(since: empty))), as: UTF8.self).contains("since"))
    }

    @Test func theStateKeepsEveryFieldItHadAndGainsOneWithItsOwnVersion() throws {
        let plain = json(RemoteAPI.state(input(since: nil)))
        let with = json(RemoteAPI.state(input(since: summary())))
        // Every old key is there with the same value; the new one is `since`, and the state's own version stays 1.
        for (key, value) in plain { #expect("\(with[key] ?? "missing")" == "\(value)", Comment(rawValue: key)) }
        #expect(Set(with.keys).subtracting(plain.keys) == ["since"])
        #expect(with["version"] as? Int == 1)
        let since = try #require(with["since"] as? [String: Any])
        #expect(since["v"] as? Int == 1)
        #expect(Set(since.keys) == ["v", "awayAt", "back", "counts", "asks", "finished", "stopped", "more", "content"])
        #expect(since["content"] as? Bool == true)
        #expect(since["awayAt"] as? String == "2026-10-12T17:16:00Z")
        #expect(since["back"] as? String == "2026-10-12T19:30:00Z")
        let counts = try #require(since["counts"] as? [String: Int])
        #expect(counts == ["finished": 2, "stopped": 1, "needs": 1])
        #expect(since["more"] as? Int == 0)
    }

    @Test func whileTheyAreStillAwayBackIsNull() throws {
        let since = try #require(json(RemoteAPI.state(input(since: summary(back: false))))["since"] as? [String: Any])
        #expect(since["back"] is NSNull)
    }

    @Test func theRowsSayWhoTheyAreAndWhatIsKnownOfThem() throws {
        let details: [String: SinceYouLeftDetail] = [
            "f1": .init(answer: "All plates passed except plate 7."), "s1": .init(reason: "The R kernel ran out of memory."),
        ]
        let since = try #require(json(RemoteAPI.state(input(since: summary(), details: details)))["since"] as? [String: Any])
        let asks = try #require(since["asks"] as? [[String: Any]])
        #expect(asks.count == 1)
        #expect(asks[0]["id"] as? String == "n1")
        #expect(asks[0]["title"] as? String == "Plate reader QC")
        #expect(asks[0]["project"] as? String == "Assay development")
        #expect(asks[0]["reason"] as? String == "question")
        #expect(asks[0]["sentence"] as? String == "Asked you a question")
        #expect(asks[0]["since"] as? String == "2026-10-12T18:49:00Z")
        let finished = try #require(since["finished"] as? [[String: Any]])
        #expect(finished.map { $0["id"] as? String } == ["f1", "f2"])
        #expect(finished[0]["line"] as? String == "All plates passed except plate 7.")
        // Not read yet: null, which the phone fills in from the session's own data.
        #expect(finished[1]["line"] is NSNull)
        let stopped = try #require(since["stopped"] as? [[String: Any]])
        #expect(stopped[0]["reason"] as? String == "The R kernel ran out of memory.")
        #expect(stopped[0]["at"] as? String != nil)
    }

    @Test func withTheCardSettingOffTheRowsCarryNothingASessionSaid() throws {
        let details: [String: SinceYouLeftDetail] = [
            "f1": .init(answer: "All plates passed except plate 7."), "s1": .init(reason: "The R kernel ran out of memory."),
        ]
        var off = input(since: summary(), details: details)
        off.sinceContent = false
        let since = try #require(json(RemoteAPI.state(off))["since"] as? [String: Any])
        #expect(since["content"] as? Bool == false)
        let finished = try #require(since["finished"] as? [[String: Any]])
        #expect(finished[0]["line"] is NSNull)
        let stopped = try #require(since["stopped"] as? [[String: Any]])
        #expect(stopped[0]["reason"] is NSNull)
    }

    @Test func atMostSixRowsGoAndTheCountsAreWhole() throws {
        let many = summary(finished: 8, stopped: 2, needs: 2)
        let since = try #require(json(RemoteAPI.state(input(since: many)))["since"] as? [String: Any])
        let rows = ["asks", "finished", "stopped"].map { (since[$0] as? [Any])?.count ?? 0 }
        #expect(rows.reduce(0, +) == 6)
        #expect(rows == [2, 2, 2])
        #expect(since["more"] as? Int == 6)
        #expect(since["counts"] as? [String: Int] == ["finished": 8, "stopped": 2, "needs": 2])
    }

    @Test func theSameStateAtAnotherMomentKeepsItsSince() {
        let state = RemoteAPI.state(input(since: summary()))
        #expect(state.since != nil)
        #expect(state.at(.distantPast).since == state.since)
        #expect(state.at(.distantPast) != RemoteAPI.state(input(since: nil)).at(.distantPast))
    }

    @Test func aLabThatIsNotTheAppsAddsNoSince() {
        let lab = LabModel()
        let input = RemoteAPI.input(lab: lab, usage: .shared, bench: "1.0", now: now)
        #expect(input.since == nil)
        #expect(input.sinceDetails.isEmpty)
    }

    @Test func theFeedToldWhenAStretchBeginsOrEndsOrItsRowsAreRead() async throws {
        let lab = LabModel()
        let model = SinceYouLeftModel(lab: lab, finished: FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false })),
                                      dependencies: SinceYouLeftDependencies())
        let feed = RemoteFeed()
        var told = 0
        feed.start(lab: lab, usage: .shared, approver: .shared, since: model) { told += 1 }
        defer { feed.stop() }
        // The publishers' first values arrive at once; let that settle.
        try await Task.sleep(for: .milliseconds(450))
        let before = told
        model.showDemo(since: now.addingTimeInterval(-3600), back: now, events: [], baseline: nil)
        try await Task.sleep(for: .milliseconds(450))
        #expect(told > before)
        let afterReturn = told
        model.showDemo(since: now.addingTimeInterval(-3600), back: now, events: [], baseline: nil, details: ["a": .init(answer: "Done.")])
        try await Task.sleep(for: .milliseconds(450))
        #expect(told > afterReturn)
    }
}

// MARK: The finished row's pills and the keyboard

/// The row's pills (Open, Results, Add to Shelf) are shown while the pointer or the keyboard is on the row. With
/// the focus kept as a Bool on the row's button alone, Tab from the row moved the focus to a pill, the Bool went
/// false, the pills went with it, and they could never be reached. A source scan: the row is a private view of
/// the sheet, and the behaviour is SwiftUI's focus.
struct FinishedRowFocusTests {
    private func row() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sheet = try String(contentsOf: root.appendingPathComponent("Sources/Bench/SinceYouLeft/SinceYouLeftSheet.swift"), encoding: .utf8)
        let start = try #require(sheet.range(of: "private struct FinishedRow: View {"))
        let end = try #require(sheet.range(of: "// MARK: Hosting it as a sheet"))
        return String(sheet[start.lowerBound..<end.lowerBound])
    }

    @Test func theFocusCoversTheRowAndEachPillAndThePillsStayWhileAnyOfThemHasIt() throws {
        let source = try row()
        #expect(source.contains("@FocusState private var focus: Focus?"))
        #expect(source.contains("case row") && source.contains("case pill(String)"))
        #expect(!source.contains("@FocusState private var focused: Bool"))
        #expect(source.contains("private var showsPills: Bool { hovering || focus != nil }"))
        #expect(source.contains(".focused($focus, equals: .row)"))
        // Open, Results, and Add to Shelf (or On Shelf), each its own stop.
        #expect(source.contains(".focused($focus, equals: .pill(\"open\"))"))
        #expect(source.contains(".focused($focus, equals: .pill(\"results\"))"))
        #expect(source.components(separatedBy: ".focused($focus, equals: .pill(\"shelf\"))").count - 1 == 2)
        // The pills are drawn by the one rule, not by the row's own focus.
        #expect(source.contains("if showsPills {"))
        #expect(!source.contains("hovering || focused"))
    }
}
