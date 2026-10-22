// HistoryReaderTests.swift — the history reader's projection and its in-page
// bodies, the very JavaScript the page runs, in JavaScriptCore on made-up
// pages, then Swift's checks of what comes back. Nothing reaches a daemon.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let ts = 1_791_833_000_000

/// One made-up page: every kind of row the history shows or hides. Every
/// SECRET is something that must never leave the page.
private let rows = #"""
[
 {"role": "user", "content": "Design primers for gene A.", "_ts": 1791833000000, "_attachments": [{"path": "/Users/someone/SECRET-UPLOAD"}]},
 {"role": "assistant", "_ts": 1791833010000, "content": [
   {"type": "thinking", "thinking": "SECRET-THINKING"},
   {"type": "text", "text": "I'll look first."},
   {"type": "tool_use", "id": "t1", "name": "bash", "input": {"command": "cat /Users/someone/SECRET-PATH"}},
   {"type": "tool_use", "id": "t2", "name": "read_file", "input": {"path": "/Users/someone/SECRET-FILE"}}]},
 {"role": "user", "_ts": 1791833020000, "content": [
   {"type": "tool_result", "tool_use_id": "t1", "content": "SECRET-RESULT"},
   {"type": "tool_result", "tool_use_id": "t2", "content": "SECRET-ERROR", "is_error": true}]},
 {"role": "assistant", "_ts": 1791833030000, "content": [
   {"type": "tool_use", "id": "t3", "name": "web_search", "input": {"query": "SECRET-QUERY"}},
   {"type": "tool_use", "id": "t4", "name": "Bash", "input": {"command": "SECRET"}},
   {"type": "tool_use", "id": "t5", "name": "mcp__made_up__tool", "input": {"x": "SECRET"}},
   {"type": "tool_use", "id": "t6", "name": "web_fetch", "input": {"url": "https://SECRET.example"}},
   {"type": "tool_use", "id": "t7", "name": "wait_for_notification", "input": {}}]},
 {"role": "user", "_ts": 1791833040000, "content": [
   {"type": "tool_result", "tool_use_id": "t3", "content": [{"type": "text", "text": "SECRET-SEARCH"}]},
   {"type": "tool_result", "tool_use_id": "t4", "content": "SECRET"}]},
 {"role": "assistant", "_ts": 1791833050000, "content": [
   {"type": "tool_use", "id": "t8", "name": "generate_plan", "input": {"steps": [{"title": "SECRET-1"}, {"title": "SECRET-2"}, {"title": "SECRET-3"}]}}]},
 {"role": "user", "_ts": 1791833060000, "content": [{"type": "tool_result", "tool_use_id": "t8", "content": "SECRET-PLAN"}]},
 {"role": "assistant", "_ts": 1791833070000, "content": [
   {"type": "tool_use", "id": "t9", "name": "ask_user", "input": {"question": "Which   melting\ntemperature?", "options": [{"label": "SECRET-OPTION"}]}}]},
 {"role": "user", "_ts": 1791833080000, "content": [
   {"type": "tool_result", "tool_use_id": "t9", "content": "{\"status\":\"answered\",\"answers\":{\"Which melting temperature?\":\"58 °C\"}}"}]},
 {"role": "user", "content": "[System] SECRET-SYSTEM", "_ts": 1791833090000},
 {"role": "user", "content": "SECRET-HARNESS", "_harness_prompt": true, "_ts": 1791833100000},
 {"role": "assistant", "_ts": 1791833110000, "content": [
   {"type": "tool_use", "id": "t10", "name": "send_user_message", "input": {"message": "  Found two made-up papers.  "}}]},
 {"role": "user", "_ts": 1791833120000, "content": [
   {"type": "tool_result", "tool_use_id": "t10", "content": "{\"attachments\":[{\"artifact_id\":\"a-1\",\"version_id\":\"v-1\",\"filename\":\"/Users/someone/SECRET-DIR/notes.md\",\"content_type\":\"text/markdown\",\"size_bytes\":120,\"file_path\":\"/Users/someone/SECRET-PATH\"}]}"}]},
 {"role": "assistant", "_ts": 1791833130000, "content": [
   {"type": "tool_use", "id": "t11", "name": "delegate_task", "input": {"task": "SECRET-TASK"}}]},
 {"role": "user", "_ts": 1791833140000, "content": [{"type": "tool_result", "tool_use_id": "t11", "content": "SECRET-HELPER"}]},
 {"role": "assistant", "_ts": 1791833150000, "content": [
   {"type": "tool_use", "id": "t12", "name": "save_artifacts", "input": {"files": "SECRET"}}]},
 {"role": "user", "_ts": 1791833160000, "content": [
   {"type": "tool_result", "tool_use_id": "t12", "content": "{\"artifacts\":[{\"artifact_id\":\"a-2\",\"version_id\":\"v-2\",\"filename\":\"plot.png\",\"content_type\":\"image/png\",\"size_bytes\":2048,\"ref_host_path\":\"SECRET\"},{\"artifact_id\":\"a-3\",\"version_id\":\"bad/version\",\"filename\":\"x.csv\"},{\"artifact_id\":\"a-2\",\"version_id\":\"v-2\",\"filename\":\"plot.png\"}]}"}]},
 {"role": "assistant", "_ts": 1791833170000, "content": [{"type": "text", "text": "Done: the **plot** is saved."}],
  "_artifact_refs": {"table.csv": {"artifact_id": null, "version_id": "v-3"}, "plot.png": {"artifact_id": "a-2", "version_id": "v-2"}}},
 {"role": "user", "_ts": 1791833180000, "content": [{"type": "image", "source": {"type": "_disk_ref", "path": "/Users/someone/SECRET-IMAGE.png"}}]},
 {"role": "assistant", "content": "SECRET-ELIDED", "_oversized_bytes": 3000000, "_ts": 1791833190000},
 {"role": "system", "content": "SECRET-ROLE", "_ts": 1791833200000}
]
"""#

private func page(_ messages: String = rows, total: Int = 21) -> String {
    #"{"total": \#(total), "messages": \#(messages)}"#
}

/// The projection in JavaScriptCore, then Swift's check of it.
private func project(_ page: String, base: Int = 0) -> (json: String?, page: HistoryPage?) {
    let script = PageScript(HistoryReaderScript.projection)
    script.set("__page", page)
    let json = script.evaluate("JSON.stringify(benchProjectHistory(JSON.parse(__page), \(base)))")
    #expect(script.exception == nil)
    let checked = json.flatMap { HistoryPage(object: try? JSONSerialization.jsonObject(with: Data($0.utf8))) }
    return (json, checked)
}

private func userRows(_ count: Int, text: (Int) -> String = { "Made-up question \($0)" }) -> String {
    "[" + (0..<count).map { ReaderFixture.userRow(text($0), at: ts + $0) }.joined(separator: ",") + "]"
}

struct HistoryProjectionTests {
    @Test func everyKindOfRowAndNothingElse() throws {
        let (json, checked) = project(page())
        let page = try #require(checked)
        #expect(json?.contains("SECRET") == false)
        #expect(json?.contains("Users") == false)
        #expect(page.total == 21)
        #expect(page.from == 0)
        let plot = HistoryFile(v: "v-2", a: "a-2", name: "plot.png", kind: .image, size: 2048)
        let table = HistoryFile(v: "v-3", a: nil, name: "table.csv", kind: .table, size: nil)
        #expect(page.items == [
            .turn(i: 0, role: .you, at: Date(timeIntervalSince1970: 1_791_833_000), text: "Design primers for gene A.", cut: false, files: []),
            .turn(i: 1, role: .claude, at: Date(timeIntervalSince1970: 1_791_833_010), text: "I'll look first.", cut: false, files: []),
            // Rows 1 to 4 fold into one line; the bookkeeping call isn't counted.
            .steps(i: 1, line: "Ran 2 commands, read a file, ran a search +2 more", failed: true, files: []),
            .plan(i: 5, steps: 3),
            .ask(i: 7, q: "Which melting temperature?", a: "58 °C"),
            .toYou(i: 11, text: "Found two made-up papers.",
                   files: [HistoryFile(v: "v-1", a: "a-1", name: "notes.md", kind: .markdown, size: 120)]),
            .helper(i: 13),
            .steps(i: 15, line: "Saved artifacts", failed: false, files: []),
            // The turn's files go under its last reply, each once.
            .turn(i: 17, role: .claude, at: Date(timeIntervalSince1970: 1_791_833_170), text: "Done: the **plot** is saved.",
                  cut: false, files: [plot, table]),
        ])
        #expect(page.versions == ["v-1", "v-2", "v-3"])
    }

    @Test func aLongTurnIsCutAndSaysSo() throws {
        let long = String(repeating: "é", count: 2500)
        let page = try #require(project(page(userRows(1) { _ in long }, total: 1)).page)
        guard case .turn(_, _, _, let text, let cut, _) = page.items.first else { Issue.record("no turn"); return }
        #expect(cut)
        #expect(text.unicodeScalars.count == 2000)
        #expect(text.hasSuffix("…"))
    }

    @Test func atMostSixtyItemsTheOldestGoing() throws {
        let page = try #require(project(page(userRows(80), total: 180), base: 100).page)
        #expect(page.items.count == 60)
        #expect(page.from == 120)
        #expect(page.items.first?.index == 120)
        #expect(page.items.last?.index == 179)
    }

    @Test func atMostSixtyFourKilobytesAsSwiftWritesIt() async throws {
        let wide = String(repeating: "界", count: 1990)
        let (json, checked) = project(page(userRows(50) { "\($0) \(wide)" }, total: 50))
        let page = try #require(checked)
        #expect(try #require(json).utf8.count <= 64 * 1024 + 64)
        #expect(page.items.count < 50)
        #expect(page.from == page.items.first?.index)
        let encoded = await MainActor.run { BrowseAPI.encode(page.capped { BrowseAPI.encode($0) }) }
        #expect(encoded.count <= 64 * 1024)
    }

    @Test func toolCallsAcrossRowsFoldUntilSomethingIsSaid() throws {
        let messages = #"""
        [{"role": "assistant", "_ts": 1791833000000, "content": [{"type": "tool_use", "id": "a", "name": "python", "input": {}}]},
         {"role": "user", "_ts": 1791833000001, "content": [{"type": "tool_result", "tool_use_id": "a", "content": "x"}]},
         {"role": "assistant", "_ts": 1791833000002, "content": [{"type": "tool_use", "id": "b", "name": "read_file", "input": {}},
                                                                 {"type": "tool_use", "id": "c", "name": "read_file", "input": {}}]},
         {"role": "assistant", "_ts": 1791833000003, "content": [{"type": "text", "text": "Made-up summary."},
                                                                 {"type": "tool_use", "id": "d", "name": "skill", "input": {}}]}]
        """#
        let page = try #require(project(page(messages, total: 4)).page)
        #expect(page.items == [
            .steps(i: 0, line: "Read 2 files, ran a command", failed: false, files: []),
            .turn(i: 3, role: .claude, at: Date(timeIntervalSince1970: 1_791_833_000.003), text: "Made-up summary.", cut: false, files: []),
            .steps(i: 3, line: "Loaded a skill", failed: false, files: []),
        ])
    }

    @Test func filesWithoutAReplyOnThePageGoUnderTheSteps() throws {
        let messages = #"""
        [{"role": "assistant", "_ts": 1791833000000, "content": [{"type": "tool_use", "id": "a", "name": "save_artifacts", "input": {}}]},
         {"role": "user", "_ts": 1791833000001, "content": [{"type": "tool_result", "tool_use_id": "a",
           "content": "{\"artifacts\":[{\"artifact_id\":\"a-9\",\"version_id\":\"v-9\",\"filename\":\"C:\\\\made\\\\up\\\\data.tsv\",\"content_type\":\"text/tab-separated-values\",\"size_bytes\":9}]}"}]}]
        """#
        let (json, checked) = project(page(messages, total: 2))
        let page = try #require(checked)
        #expect(page.items == [.steps(i: 0, line: "Saved artifacts", failed: false,
                                      files: [HistoryFile(v: "v-9", a: "a-9", name: "data.tsv", kind: .table, size: 9)])])
        #expect(json?.contains("made") == false)
    }

    @Test(arguments: [
        #"[5]"#,
        #"[{"role": "user", "content": 5}]"#,
        #"[{"role": "user", "content": [7]}]"#,
        #"[{"role": "user", "content": [{"type": "text", "text": 5}]}]"#,
        #"[{"role": "assistant", "content": [{"type": "tool_use", "id": "x", "name": 5}]}]"#,
    ])
    func aShapeThatDoesNotMatchIsUnreadable(_ messages: String) {
        #expect(project(page(messages, total: 1)).json == "null")
    }

    @Test func aPageOutOfShapeIsRefusedBySwift() {
        let good: [String: Any] = ["total": 3, "from": 1, "items": [["i": 1, "kind": "helper"]]]
        #expect(HistoryPage(object: good) == HistoryPage(total: 3, from: 1, items: [.helper(i: 1)]))
        let bad: [[String: Any]] = [
            ["total": 3, "from": 4, "items": []],
            ["total": 3, "from": 1, "items": [["i": 0, "kind": "helper"]]],
            ["total": 3, "from": 0, "items": [["i": 2, "kind": "helper"], ["i": 1, "kind": "helper"]]],
            ["total": 3, "from": 0, "items": [["i": 1, "kind": "thinking"]]],
            ["total": 3, "from": 0, "items": [["i": 1, "role": "system", "at": NSNull(), "text": "x", "cut": false, "files": []]]],
            ["total": 3, "from": 0, "items": [["i": 1, "role": "you", "at": NSNull(), "text": String(repeating: "x", count: 2001), "cut": true, "files": []]]],
            ["total": 3, "from": 0, "items": [["i": 1, "kind": "toYou", "text": "x", "files": [["v": "a/b", "a": NSNull(), "name": "x", "mime": NSNull(), "size": NSNull()]]]]],
            ["total": 3, "from": 0, "items": [["i": 1, "kind": "steps", "line": "x", "failed": 1]]],
            ["total": 3, "from": 0, "items": Array(repeating: ["i": 1, "kind": "helper"], count: 61)],
        ]
        for object in bad { #expect(HistoryPage(object: object) == nil) }
    }
}

// MARK: The paths and the in-page bodies

struct HistoryReaderPageTests {
    private func messages(_ count: Int, from: Int) -> String {
        "[" + (0..<count).map { ReaderFixture.userRow("Made-up row \(from + $0)", at: ts + $0) }.joined(separator: ",") + "]"
    }

    private func reply(from: Int, total: Int, count: Int, first: Int? = nil) -> PageScript.Answer {
        PageScript.Answer(status: 200, body: #"{"frame_id": "\#(root)", "from": \#(from), "total": \#(total), "messages": \#(messages(count, from: first ?? from))}"#)
    }

    private func path(_ query: String) -> String { "/api/frames/\(root)/messages?\(query)" }

    private func run(before: String = "null", frame: String = "\"\(root)\"", known: String = "null",
                     answers: [String: [PageScript.Answer]])
        -> (outcome: HistoryReaderScript.Outcome?, raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (raw, requests) = script.runPage(HistoryReaderScript.pageBody,
                                             arguments: [("frameId", frame), ("before", before), ("knownTotal", known)],
                                             answers: answers)
        #expect(script.exception == nil)
        return (raw.map { HistoryReaderScript.outcome(of: Data($0.utf8)) }, raw, requests)
    }

    @Test func theLastPageAsksForTheTailThenTheRowsBeforeIt() {
        let (outcome, _, requests) = run(answers: [
            path("from=-12&limit=12"): [reply(from: 88, total: 100, count: 12)],
            path("from=50&limit=38"): [reply(from: 50, total: 100, count: 38)],
        ])
        #expect(requests.map(\.path) == [path("from=-12&limit=12"), path("from=50&limit=38")])
        #expect(requests.allSatisfy { $0.cache == "no-store" && $0.method == "GET" })
        #expect(requests.allSatisfy { HistoryReaderScript.isAllowedPath($0.path) })
        guard case .read(let page, _)? = outcome else { Issue.record("not read"); return }
        #expect(page.total == 100)
        #expect(page.from == 50)
        #expect(page.items.map(\.index) == Array(50..<100))
    }

    /// Fable's review of 0.5.0, P3: a history as long as the page Bench holds
    /// is the tail's one request, and nothing is projected.
    @Test func aHistoryAsLongAsTheOneBenchHoldsIsTheTailAlone() {
        let answers = [
            path("from=-12&limit=12"): [reply(from: 88, total: 100, count: 12)],
            path("from=50&limit=38"): [reply(from: 50, total: 100, count: 38)],
        ]
        let same = run(known: "100", answers: answers)
        #expect(same.outcome == .same(total: 100))
        #expect(same.raw == #"{"outcome":"same","total":100}"#)
        #expect(same.requests.map(\.path) == [path("from=-12&limit=12")])
        // Longer than Bench's: read whole, as before.
        let grown = run(known: "96", answers: answers)
        #expect(grown.requests.map(\.path) == [path("from=-12&limit=12"), path("from=50&limit=38")])
        guard case .read(let page, _)? = grown.outcome else { Issue.record("not read"); return }
        #expect(page.total == 100)
        // Anything but a whole number is no length.
        for known in ["\"100\"", "100.5", "true"] {
            #expect(run(known: known, answers: answers).requests.count == 2, "\(known)")
        }
        // An earlier page has no tail to stop at: it is read.
        let earlier = run(before: "120", known: "300", answers: [path("from=70&limit=50"): [reply(from: 70, total: 300, count: 50)]])
        guard case .read? = earlier.outcome else { Issue.record("not read"); return }
        // Swift takes a "same" only with a length that could be one.
        #expect(HistoryReaderScript.outcome(of: Data(#"{"outcome":"same","total":-1}"#.utf8)) == .unreadable)
        #expect(HistoryReaderScript.outcome(of: Data(#"{"outcome":"same"}"#.utf8)) == .unreadable)
    }

    @Test func aTailThatEchoesItsNegativeFromStillReads() {
        let (outcome, _, _) = run(answers: [
            path("from=-12&limit=12"): [reply(from: -12, total: 20, count: 12, first: 8)],
            path("from=0&limit=8"): [reply(from: 0, total: 20, count: 8)],
        ])
        guard case .read(let page, _)? = outcome else { Issue.record("not read"); return }
        #expect(page.from == 0)
        #expect(page.items.count == 20)
    }

    @Test func aShortSessionIsOneRequest() {
        let (outcome, _, requests) = run(answers: [path("from=-12&limit=12"): [reply(from: 0, total: 5, count: 5)]])
        #expect(requests.count == 1)
        guard case .read(let page, _)? = outcome else { Issue.record("not read"); return }
        #expect(page.items.count == 5)
    }

    @Test func anEarlierPageIsTheFiftyRowsBeforeIt() {
        let (outcome, _, requests) = run(before: "120", answers: [path("from=70&limit=50"): [reply(from: 70, total: 300, count: 50)]])
        #expect(requests.map(\.path) == [path("from=70&limit=50")])
        guard case .read(let page, _)? = outcome else { Issue.record("not read"); return }
        #expect(page.from == 70)
        #expect(page.total == 300)
        let near = run(before: "30", answers: [path("from=0&limit=30"): [reply(from: 0, total: 300, count: 30)]])
        #expect(near.requests.map(\.path) == [path("from=0&limit=30")])
    }

    @Test func aReplyFromElsewhereIsUnreadable() {
        let (outcome, _, _) = run(before: "120", answers: [path("from=70&limit=50"): [reply(from: 0, total: 300, count: 50)]])
        #expect(outcome == .unreadable)
        let tooMany = run(before: "120", answers: [path("from=70&limit=50"): [reply(from: 70, total: 300, count: 51)]])
        #expect(tooMany.outcome == .unreadable)
    }

    @Test func aRefusalIsLostAndNonsenseIsRefused() {
        let lost = run(answers: [path("from=-12&limit=12"): [PageScript.Answer(status: 401, body: "{}")]])
        #expect(lost.outcome == .lost)
        let badID = run(frame: #""../../usage""#, answers: [:])
        #expect(badID.raw == #"{"outcome":"refused"}"#)
        #expect(badID.requests.isEmpty)
        for before in ["0", "10000000", "1.5", #""5""#] {
            let bad = run(before: before, answers: [:])
            #expect(bad.raw == #"{"outcome":"refused"}"#, "\(before)")
            #expect(bad.requests.isEmpty)
        }
    }

    @Test func theAllowedPathsAndThePageAgree() {
        let good = ["from=-12&limit=12", "from=0&limit=1", "from=9999999&limit=50", "from=12&limit=38", "from=5&limit=9",
                    "from=5&limit=10", "from=5&limit=49"]
        let bad = ["from=5&limit=51", "from=5&limit=0", "from=5&limit=05", "from=-1&limit=1", "from=12345678&limit=1",
                   "from=5&limit=1&x=1", "limit=1&from=5", "from=-12&limit=13", "from=&limit=1", "from=1&limit="]
        let script = PageScript(HistoryReaderScript.fetcher)
        func page(_ path: String) -> Bool {
            script.set("__path", path)
            return script.evaluate("ALLOWED.test(__path)") == "true"
        }
        for query in good {
            #expect(HistoryReaderScript.isAllowedPath(path(query)), "\(query)")
            #expect(page(path(query)), "\(query)")
        }
        for query in bad {
            #expect(!HistoryReaderScript.isAllowedPath(path(query)), "\(query)")
            #expect(!page(path(query)), "\(query)")
        }
        for other in ["/api/frames/\(root.uppercased())/messages?from=1&limit=1", "/frames/\(root)/messages?from=1&limit=1",
                      "/api/frames/\(root.dropLast())/messages?from=1&limit=1", "/api/frames/\(root)/artifacts?from=1&limit=1",
                      "/api/frames/\(root)?shallow=true"] {
            #expect(!HistoryReaderScript.isAllowedPath(other), "\(other)")
            #expect(!page(other), "\(other)")
        }
    }

    // MARK: One turn whole

    private func turn(_ index: Int, answer: PageScript.Answer) -> (outcome: HistoryReaderScript.Outcome?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (raw, requests) = script.runPage(HistoryReaderScript.turnBody, arguments: [("frameId", "\"\(root)\""), ("index", "\(index)")],
                                             answers: [path("from=\(index)&limit=1"): [answer]])
        #expect(script.exception == nil)
        return (raw.map { HistoryReaderScript.outcome(of: Data($0.utf8)) }, requests)
    }

    @Test func aCutTurnComesWholeUpToTwentyThousand() {
        let long = String(repeating: "a", count: 25_000)
        let row = #"{"role": "assistant", "_ts": 1791833000000, "content": [{"type": "thinking", "thinking": "SECRET"}, {"type": "text", "text": "\#(long)"}]}"#
        let (outcome, requests) = turn(7, answer: PageScript.Answer(status: 200, body: #"{"from": 7, "total": 10, "messages": [\#(row)]}"#))
        #expect(requests.map(\.path) == [path("from=7&limit=1")])
        guard case .turn(let whole)? = outcome else { Issue.record("no turn"); return }
        #expect(whole.i == 7)
        #expect(whole.role == .claude)
        #expect(whole.text.unicodeScalars.count == 20_000)
        #expect(!whole.text.contains("SECRET"))
    }

    @Test func aRowTheHistoryHidesIsNoTurn() {
        let hidden = ReaderFixture.userRow("SECRET", #", "_harness_prompt": true"#)
        #expect(turn(3, answer: PageScript.Answer(status: 200, body: #"{"from": 3, "total": 10, "messages": [\#(hidden)]}"#)).outcome == HistoryReaderScript.Outcome.none)
        let tools = #"{"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": "SECRET"}]}"#
        #expect(turn(3, answer: PageScript.Answer(status: 200, body: #"{"from": 3, "total": 10, "messages": [\#(tools)]}"#)).outcome == HistoryReaderScript.Outcome.none)
        #expect(turn(30, answer: PageScript.Answer(status: 200, body: #"{"from": 30, "total": 10, "messages": []}"#)).outcome == HistoryReaderScript.Outcome.none)
        #expect(turn(3, answer: PageScript.Answer(status: 500, body: "")).outcome == .unreadable)
    }
}

/// A photo or file sent with a message comes as one attachment line in the
/// message's text (Claude Science's upload format): history shows it as a
/// file, never as the raw line.
struct HistoryAttachmentTests {
    private static let line = #"{\"type\":\"attachment\",\"id\":\"0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5\",\"version_id\":\"1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6\",\"filename\":\"phone-photo-20261014-120000.jpg\",\"artifact_ref\":\"{{artifact:1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6}}\",\"content_type\":\"image/jpeg\",\"size_bytes\":204800}"#

    @Test func anAttachmentLineBecomesAFile() throws {
        let rows = #"[{"role": "user", "_ts": 1791833000000, "content": "Here is the made-up gel\n\n\#(Self.line)"}]"#
        let page = try #require(project(page(rows, total: 1)).page)
        guard case .turn(_, .you, _, let text, _, let files) = try #require(page.items.first) else {
            Issue.record("not a turn"); return
        }
        #expect(text == "Here is the made-up gel")
        #expect(files.map(\.name) == ["phone-photo-20261014-120000.jpg"])
        #expect(files.first?.kind == .image)
    }

    @Test func aPhotoAloneIsATurnWithAFileAndNoText() throws {
        let rows = #"[{"role": "user", "_ts": 1791833000000, "content": "\#(Self.line)"}]"#
        let page = try #require(project(page(rows, total: 1)).page)
        guard case .turn(_, .you, _, let text, _, let files) = try #require(page.items.first) else {
            Issue.record("not a turn"); return
        }
        #expect(text == "")
        #expect(files.count == 1)
    }

    @Test func somethingThatOnlyLooksLikeOneStaysText() throws {
        let rows = #"[{"role": "user", "_ts": 1791833000000, "content": "{\"type\":\"attachment\" is how it starts"}]"#
        let page = try #require(project(page(rows, total: 1)).page)
        guard case .turn(_, .you, _, let text, _, let files) = try #require(page.items.first) else {
            Issue.record("not a turn"); return
        }
        #expect(text == #"{"type":"attachment" is how it starts"#)
        #expect(files.isEmpty)
    }
}

struct HistorySystemNoteTests {
    @Test func theDaemonsAttachedFileNoteStaysHidden() throws {
        let rows = #"[{"role": "user", "_ts": 1791833000000, "content": [{"type": "text", "text": "Made-up question"}, {"type": "text", "text": "[System] Attached file: phone-photo-20261014-120000.jpg"}]}]"#
        let page = try #require(project(page(rows, total: 1)).page)
        guard case .turn(_, .you, _, let text, _, _) = try #require(page.items.first) else {
            Issue.record("not a turn"); return
        }
        #expect(text == "Made-up question")
    }
}

// MARK: Keep: the message that shows a figure

/// Made-up rows for the showing op. Every SECRET is something that must never
/// leave the page; nothing here is a real session, id or path.
private enum Show {
    static let v1 = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
    static let v2 = "2d9e4b60-3c4d-4e5f-8011-c2d3e4f5a6b7"
    static let v3 = "3eaf5c71-4d5e-4f60-9122-d3e4f5a6b7c8"
    /// A version of some other artifact.
    static let other = "9a0b1c2d-3e4f-4051-8263-748596a7b8c9"
    static let ids = [v1, v2, v3]

    static func json(_ object: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    static func at(_ n: Int) -> Int { ts + n * 1_000 }
    static func date(_ ms: Int) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// An assistant row of text, with the files its `_artifact_refs` name.
    static func said(_ text: String, ts: Int? = nil, refs: [String: String] = [:], before: [[String: Any]] = []) -> [String: Any] {
        var row: [String: Any] = ["role": "assistant", "content": before + [["type": "text", "text": text] as [String: Any]]]
        if let ts { row["_ts"] = ts }
        if !refs.isEmpty {
            row["_artifact_refs"] = refs.mapValues { ["artifact_id": NSNull(), "version_id": $0] as [String: Any] }
        }
        return row
    }

    /// An assistant row that calls a tool, with some text before the call.
    static func call(_ id: String, _ name: String, input: [String: Any] = [:], text: String? = nil, ts: Int? = nil) -> [String: Any] {
        var blocks: [[String: Any]] = []
        if let text { blocks.append(["type": "text", "text": text]) }
        blocks.append(["type": "tool_use", "id": id, "name": name, "input": input])
        var row: [String: Any] = ["role": "assistant", "content": blocks]
        if let ts { row["_ts"] = ts }
        return row
    }

    /// The user row that carries a tool's result.
    static func result(_ id: String, _ content: Any, error: Bool = false, ts: Int? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var block: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": content]
        if error { block["is_error"] = true }
        var row: [String: Any] = ["role": "user", "content": [block]]
        if let ts { row["_ts"] = ts }
        return row.merging(extra) { $1 }
    }

    /// A save or run tool's result text, listing these versions.
    static func listing(_ versions: [String]) -> String {
        json(["artifacts": versions.map {
            ["artifact_id": "an-artifact", "version_id": $0, "filename": "plot.png", "content_type": "image/png", "size_bytes": 10] as [String: Any]
        }])
    }

    static func you(_ text: String, ts: Int? = nil) -> [String: Any] {
        var row: [String: Any] = ["role": "user", "content": text]
        if let ts { row["_ts"] = ts }
        return row
    }

    static func page(_ rows: [[String: Any]], total: Int? = nil) -> String {
        json(["total": total ?? rows.count, "messages": rows] as [String: Any])
    }
}

/// `benchFindShowingMessage` in JavaScriptCore on one made-up page, then Swift's
/// check of what it answers.
private func find(_ rows: [[String: Any]], base: Int = 0, ids: [String] = Show.ids)
    -> (json: String?, message: ShowingMessage?, raised: Bool) {
    let script = PageScript(HistoryReaderScript.showingProjection)
    script.set("__page", Show.page(rows))
    script.set("__ids", Show.json(ids))
    let json = script.evaluate("JSON.stringify(benchFindShowingMessage(JSON.parse(__page), \(base), JSON.parse(__ids)))")
    let raised = script.exception != nil
    guard let json, json != "null" else { return (json, nil, raised) }
    let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
    return (json, ShowingMessage(object: object, rows: base..<(base + rows.count), versions: ids), raised)
}

struct ShowingFindTests {
    @Test func aMessageWithTheIdInItsTextShowsItInline() {
        let rows = [Show.you("Plot it", ts: Show.at(0)), Show.said("Here it is: ![Z prime]({{artifact:\(Show.v2)}})", ts: Show.at(10))]
        let result = find(rows, base: 4)
        #expect(result.message == ShowingMessage(i: 5, at: Show.date(Show.at(10)), text: "Here it is: ![Z prime]({{artifact:\(Show.v2)}})",
                                                 how: .inline, v: Show.v2))
        // The other written form, in an image's source.
        let query = find([Show.said("![x](figures/z.png?v=\(Show.v1)&w=2)", ts: Show.at(1))])
        #expect(query.message?.how == .inline && query.message?.v == Show.v1)
        // An id of another artifact, an `art_` id (the artifact's latest) and a half of an id show nothing.
        for text in ["{{artifact:\(Show.other)}}", "{{artifact:art_\(Show.v2)}}", "?v=\(Show.v2.dropLast(2))", "{{artifact:\(Show.v2)", "artifact:\(Show.v2)"] {
            #expect(find([Show.said(text)]).json == "null", "\(text)")
        }
    }

    @Test func anImageWhoseFileTheRefsNameIsShownAsAnImage() {
        let text = "Result: ![plot](figures/plot.png?width=600)\nThe data are in data.csv."
        let image = find([Show.said(text, ts: Show.at(3), refs: ["plot.png": Show.v2, "data.csv": Show.v3])])
        // The file the text shows beats a newer one it only names.
        #expect(image.message?.how == .image && image.message?.v == Show.v2 && image.message?.text == text)
        let encoded = find([Show.said("![x](my%20plot.png)", refs: ["my plot.png": Show.v1])])
        #expect(encoded.message?.how == .image && encoded.message?.v == Show.v1)
        let prefixed = find([Show.said("![x](v1c8d3a5f_plot.png)", refs: ["plot.png": Show.v1])])
        #expect(prefixed.message?.how == .image)
        // A ref for a file of another artifact doesn't count.
        #expect(find([Show.said("![plot](plot.png)", refs: ["plot.png": Show.other])]).json == "null")
    }

    @Test func aRefToAFileTheTextDoesntShowIsOnlyAMention() {
        let said = Show.said("I saved plot.png for you.", refs: ["plot.png": Show.v1, "old.png": Show.v3])
        let result = find([said])
        #expect(result.message?.how == .mention)
        #expect(result.message?.v == Show.v3, "the latest of the versions it names")
        // An image of another file in the text isn't a way of showing this one.
        #expect(find([Show.said("![other](other.png)", refs: ["plot.png": Show.v1])]).message?.how == .mention)
        #expect(find([Show.said("Nothing here.", refs: [:])]).json == "null")
    }

    @Test func aSaveShowsItsReplyAndWithoutOneItself() {
        func rows(_ tool: String = "save_artifacts", then: [[String: Any]] = [Show.said("Done: the figure is updated.", ts: Show.at(3))])
            -> [[String: Any]] {
            [Show.you("Redraw it", ts: Show.at(0)), Show.call("t1", tool, input: ["files": "SECRET-INPUT"], text: "Saving it.", ts: Show.at(1)),
             Show.result("t1", Show.listing([Show.v2, Show.other]), ts: Show.at(2))] + then
        }
        let reply = find(rows())
        #expect(reply.message == ShowingMessage(i: 3, at: Show.date(Show.at(3)), text: "Done: the figure is updated.", how: .saved, v: Show.v2))
        // No reply after it: the message that made the call.
        let alone = find(rows(then: []))
        #expect(alone.message == ShowingMessage(i: 1, at: Show.date(Show.at(1)), text: "Saving it.", how: .saved, v: Show.v2))
        // A turn of the user's between the save and the next reply: that reply is another answer.
        let turn = find(rows(then: [Show.you("Thanks!", ts: Show.at(3)), Show.said("You're welcome.", ts: Show.at(4))]))
        #expect(turn.message?.i == 1 && turn.message?.how == .saved)
        // A message of steps with no text doesn't stand for the reply.
        let steps = find(rows(then: [Show.call("t2", "bash", ts: Show.at(3)), Show.result("t2", "ok", ts: Show.at(4)), Show.said("Finished.", ts: Show.at(5))]))
        #expect(steps.message?.i == 5)
        // Every tool that makes files counts; others and failed ones don't.
        for tool in ["python", "r", "bash", "powershell", "operon", "compute_provider", "code_execution", "Python"] {
            #expect(find(rows(tool)).message?.i == 3, "\(tool)")
        }
        for tool in ["web_search", "read_file", "generate_plan", "mcp__made_up__tool"] {
            #expect(find(rows(tool)).json == "null", "\(tool)")
        }
        var failed = rows()
        failed[2] = Show.result("t1", Show.listing([Show.v2]), error: true, ts: Show.at(2))
        #expect(find(failed).json == "null")
        // A result for no call on the page, one with no list and one listing other artifacts' versions.
        #expect(find([Show.result("t9", Show.listing([Show.v1])), Show.said("Hi.")]).json == "null")
        var empty = rows()
        empty[2] = Show.result("t1", "{\"artifacts\": []}")
        #expect(find(empty).json == "null")
        empty[2] = Show.result("t1", Show.listing([Show.other]))
        #expect(find(empty).json == "null")
    }

    @Test func aSavesResultMayCarryItsTextAsBlocks() {
        let block: [[String: Any]] = [["type": "text", "text": Show.listing([Show.v3])]]
        let rows = [Show.call("t1", "save_artifacts"), Show.result("t1", block), Show.said("Saved.")]
        #expect(find(rows).message?.v == Show.v3)
    }

    @Test func theNewestMessageWinsWhateverItsWay() {
        let rows = [
            Show.said("First: ![a]({{artifact:\(Show.v1)}})", ts: Show.at(0)),
            Show.you("Again", ts: Show.at(1)),
            Show.said("Second: ![b](b.png)", ts: Show.at(2), refs: ["b.png": Show.v2]),
            Show.said("Third, of another artifact: {{artifact:\(Show.other)}}", ts: Show.at(3)),
            Show.said("Only a word on c.png", ts: Show.at(4), refs: ["c.png": Show.v3]),
            Show.said("Not about it.", ts: Show.at(5)),
        ]
        let result = find(rows)
        #expect(result.message?.i == 4 && result.message?.how == .mention && result.message?.v == Show.v3)
        #expect(find(Array(rows.prefix(4))).message?.i == 2)
        #expect(find(Array(rows.prefix(2))).message?.i == 0)
    }

    @Test func eachMessageTakesItsSurestWayAndItsLatestVersion() {
        // Inline beats an image and a mention in the same message.
        let both = find([Show.said("![a]({{artifact:\(Show.v1)}}) ![b](b.png)", refs: ["b.png": Show.v3])])
        #expect(both.message?.how == .inline && both.message?.v == Show.v1)
        // Two ids written the same way: the one latest in the list, in either order.
        let two = Show.said("{{artifact:\(Show.v3)}} and {{artifact:\(Show.v1)}}")
        #expect(find([two]).message?.v == Show.v3)
        #expect(find([two], ids: [Show.v3, Show.v1]).message?.v == Show.v1)
        // A save's reply that shows another way takes that way.
        let rows = [Show.call("t1", "python"), Show.result("t1", Show.listing([Show.v1])),
                    Show.said("![c](c.png)", refs: ["c.png": Show.v2])]
        let reply = find(rows)
        #expect(reply.message?.i == 2 && reply.message?.how == .image && reply.message?.v == Show.v2)
        // Two saves in one reply: the later version.
        let twice = [Show.call("t1", "python"), Show.result("t1", Show.listing([Show.v1])),
                     Show.call("t2", "python"), Show.result("t2", Show.listing([Show.v3])), Show.said("Both.")]
        #expect(find(twice).message?.v == Show.v3)
    }

    @Test func nothingShownIsNullAndRowsKeepTheirIndexFromTheBase() {
        #expect(find([]).json == "null")
        #expect(find([Show.you("Hi"), Show.said("Hello.")]).json == "null")
        let result = find([Show.you("Hi"), Show.said("{{artifact:\(Show.v1)}}")], base: 100)
        #expect(result.message?.i == 101)
    }

    @Test func aMessageWithNoTimeHasNone() {
        #expect(find([Show.said("{{artifact:\(Show.v1)}}")]).message?.at == nil)
        var odd = Show.said("{{artifact:\(Show.v1)}}")
        odd["_ts"] = "not a time"
        #expect(find([odd]).message?.at == nil)
        odd["_ts"] = 5
        #expect(find([odd]).message?.at == nil)
        odd["_ts"] = 1_791_833_000
        #expect(find([odd]).message?.at == Show.date(1_791_833_000_000), "seconds are taken as seconds")
    }

    @Test func theTextIsCutAtTwentyThousandCharacters() {
        let long = String(repeating: "é", count: 25_000)
        let result = find([Show.said(long + " {{artifact:\(Show.v1)}}")])
        #expect(result.message?.how == .inline, "found past the cut")
        #expect(result.message?.text.unicodeScalars.count == 20_000)
        #expect(result.message?.text.hasSuffix("…") == true)
        let tail = " {{artifact:\(Show.v1)}}"
        let exact = String(repeating: "a", count: 20_000 - tail.count) + tail
        #expect(exact.count == 20_000)
        #expect(find([Show.said(exact)]).message?.text == exact)
    }

    @Test func nothingIsReadFromThinkingToolInputOtherResultsOrImages() {
        let thinking: [[String: Any]] = [["type": "thinking", "thinking": "SECRET-THINKING {{artifact:\(Show.v1)}} ![x](p.png)"]]
        let rows: [[String: Any]] = [
            Show.said("Plain words.", refs: [:], before: thinking),
            Show.call("t1", "bash", input: ["command": "SECRET-INPUT ![x]({{artifact:\(Show.v2)}}) ?v=\(Show.v3)"], text: "Running."),
            Show.result("t1", "SECRET-OUTPUT {{artifact:\(Show.v1)}} ?v=\(Show.v2)"),
            Show.call("t2", "send_user_message", input: ["message": "SECRET-MESSAGE ![x](x.png?v=\(Show.v3))", "attachments": [Show.v1]]),
            Show.result("t2", Show.listing([Show.v1])),
            Show.call("t3", "web_search", input: ["query": "SECRET-QUERY"]),
            Show.result("t3", Show.listing([Show.v2]) + "SECRET-RESULT"),
            ["role": "user", "content": [["type": "image", "source": ["type": "_disk_ref", "path": "/opt/made-up/SECRET-IMAGE.png"]]]],
            ["role": "assistant", "content": [["type": "text", "text": "A reply."], ["type": "redacted_thinking", "data": "SECRET-DATA"]], "_artifact_refs": ["z.png": ["version_id": Show.other]]],
        ]
        #expect(find(rows).json == "null")
        // With a real hit in the page, none of it comes out.
        let hit = rows + [Show.call("t4", "save_artifacts", input: ["files": "SECRET-FILES"], text: "Saving."),
                          Show.result("t4", Show.json(["artifacts": [["version_id": Show.v1, "filename": "SECRET-NAME", "file_path": "/opt/made-up/SECRET-PATH"]],
                                                       "stdout": "SECRET-STDOUT", "stderr": "SECRET-STDERR"] as [String: Any])),
                          Show.said("All done.", before: thinking)]
        let found = find(hit)
        #expect(found.message?.text == "All done." && found.message?.how == .saved && found.message?.v == Show.v1)
        #expect(!(found.json ?? "").contains("SECRET") && !(found.json ?? "").contains("/opt"))
        #expect(Set(((try? JSONSerialization.jsonObject(with: Data((found.json ?? "{}").utf8))) as? [String: Any])?.keys.map { $0 } ?? []) == ["i", "at", "text", "how", "v"])
    }

    @Test func onlyVisibleAssistantMessagesShowAnything() {
        let text = "{{artifact:\(Show.v1)}}"
        let rows: [[String: Any]] = [
            Show.you(text), ["role": "system", "content": text], ["role": "assistant", "content": text, "_oversized_bytes": 3_000_000],
            Show.call("t1", "save_artifacts"),
            Show.result("t1", Show.listing([Show.v1]), extra: ["_harness_prompt": true]),
            Show.result("t1", Show.listing([Show.v1]), extra: ["_oversized_bytes": 4_000_000]),
        ]
        #expect(find(rows).json == "null")
        // A string for a message's whole content is its text.
        #expect(find([["role": "assistant", "content": text]]).message?.how == .inline)
    }

    @Test func aShapeThatDoesNotMatchIsRaisedAndNothingIsAnswered() {
        let ok = Show.said("hi")
        let bad: [[[String: Any]]] = [
            [["role": "user", "content": 5]], [["role": "user", "content": [7]]],
            [["role": "assistant", "content": [["type": "text", "text": 5]]]],
            [["role": "assistant", "content": [["type": 5]]]], [ok, ["role": "assistant"]],
        ]
        for rows in bad {
            let result = find(rows)
            #expect(result.raised && result.json == nil, "\(Show.json(rows).prefix(60))")
        }
        // No ids, an id out of shape, too many, a page with no list of messages.
        #expect(find([ok], ids: []).raised)
        #expect(find([ok], ids: ["a/b"]).raised)
        #expect(find([ok], ids: (0...600).map { "v\($0)" }).raised)
        #expect(!find([ok], ids: (0..<600).map { "v\($0)" }).raised)
        let script = PageScript(HistoryReaderScript.showingProjection)
        script.set("__ids", Show.json(Show.ids))
        script.evaluate("benchFindShowingMessage({total: 1, messages: {}}, 0, JSON.parse(__ids))")
        #expect(script.exception != nil)
    }

    @Test func theNewestTimeOfAPageIsItsLargestUsableTs() {
        let script = PageScript(HistoryReaderScript.showingProjection)
        func newest(_ rows: String) -> String? {
            script.set("__rows", rows)
            return script.evaluate("JSON.stringify(benchNewestTs(JSON.parse(__rows)))")
        }
        #expect(newest(#"[{"_ts": 1791833000000}, {"_ts": 1791833090000}, {"_ts": 1791833050000}]"#) == "1791833090000")
        #expect(newest(#"[{"role": "user"}, {"_ts": "x"}, null, 5, {"_ts": 3}]"#) == "null")
        #expect(newest(#"[{"_ts": 1791833000}, {"_ts": 99999999999999}]"#) == "1791833000000")
        #expect(newest("[]") == "null")
        #expect(newest("{}") == "null")
    }
}

// MARK: Keep: one page of the showing read, in the page

struct ShowingPageTests {
    private func filler(_ range: Range<Int>) -> [[String: Any]] {
        range.map { Show.you("Made-up row \($0)", ts: ts + $0 * 1_000) }
    }

    private func reply(_ rows: [[String: Any]], from: Int, total: Int) -> PageScript.Answer {
        PageScript.Answer(status: 200, body: Show.json(["frame_id": root, "from": from, "total": total, "messages": rows] as [String: Any]))
    }

    private func path(_ query: String) -> String { "/api/frames/\(root)/messages?\(query)" }

    private func run(before: String = "null", frame: String = "\"\(root)\"", ids: [String] = Show.ids, nonce: String = "null",
                     answers: [String: [PageScript.Answer]])
        -> (outcome: ShowingPageRead?, raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (raw, requests) = script.runPage(HistoryReaderScript.showingBody,
                                             arguments: [("frameId", frame), ("before", before), ("versionIds", Show.json(ids)), ("nonce", nonce)],
                                             answers: answers)
        #expect(script.exception == nil)
        return (raw.map { HistoryReaderScript.showingOutcome(of: Data($0.utf8), versions: ids) }, raw, requests)
    }

    @Test func theLastPageIsTheTailAndTheRowsBeforeItAndFindsTheMessageInEither() throws {
        var rows = filler(0..<70)
        rows[30] = Show.said("Here: {{artifact:\(Show.v2)}}", ts: ts + 30_000)
        let answers = [
            path("from=-12&limit=12"): [reply(Array(rows[58...]), from: 58, total: 70)],
            path("from=20&limit=38"): [reply(Array(rows[20..<58]), from: 20, total: 70)],
        ]
        let (outcome, raw, requests) = run(answers: answers)
        #expect(requests.map(\.path) == [path("from=-12&limit=12"), path("from=20&limit=38")])
        #expect(requests.allSatisfy { $0.cache == "no-store" && $0.method == "GET" && HistoryReaderScript.isAllowedPath($0.path) })
        guard case .page(let page)? = outcome else { Issue.record("not a page: \(raw ?? "nil")"); return }
        #expect(page.total == 70 && page.from == 20)
        #expect(page.newest == Show.date(ts + 69_000))
        #expect(page.found == ShowingMessage(i: 30, at: Show.date(ts + 30_000), text: "Here: {{artifact:\(Show.v2)}}", how: .inline, v: Show.v2))
        // In the tail itself.
        rows[65] = Show.said("{{artifact:\(Show.v3)}}")
        let tail = run(answers: [path("from=-12&limit=12"): [reply(Array(rows[58...]), from: 58, total: 70)],
                                 path("from=20&limit=38"): [reply(Array(rows[20..<58]), from: 20, total: 70)]])
        guard case .page(let second)? = tail.outcome else { Issue.record("not a page"); return }
        #expect(second.found?.i == 65 && second.found?.at == nil, "the newest of the two")
    }

    @Test func anEarlierPageIsOneGetOfTheRowsBeforeIt() {
        var rows = filler(70..<120)
        rows[30] = Show.said("{{artifact:\(Show.v1)}}")
        let (outcome, _, requests) = run(before: "120", answers: [path("from=70&limit=50"): [reply(rows, from: 70, total: 300)]])
        #expect(requests.map(\.path) == [path("from=70&limit=50")])
        guard case .page(let page)? = outcome else { Issue.record("not a page"); return }
        #expect(page.from == 70 && page.total == 300 && page.found?.i == 100)
        let near = run(before: "30", answers: [path("from=0&limit=30"): [reply(filler(0..<30), from: 0, total: 300)]])
        #expect(near.requests.map(\.path) == [path("from=0&limit=30")])
        guard case .page(let start)? = near.outcome else { Issue.record("not a page"); return }
        #expect(start.from == 0 && start.found == nil)
    }

    @Test func aPageWithNothingShownSaysSoAndOneWithNoTimesHasNoNewest() {
        let (outcome, raw, _) = run(before: "10", answers: [path("from=0&limit=10"): [reply(filler(0..<10), from: 0, total: 10)]])
        #expect(raw?.contains("\"found\":null") == true)
        guard case .page(let page)? = outcome else { Issue.record("not a page"); return }
        #expect(page.found == nil && page.newest == Show.date(ts + 9_000))
        let untimed = (0..<5).map { _ in Show.you("No time") }
        let none = run(before: "5", answers: [path("from=0&limit=5"): [reply(untimed, from: 0, total: 5)]])
        guard case .page(let bare)? = none.outcome else { Issue.record("not a page"); return }
        #expect(bare.newest == nil && none.raw?.contains("\"newest\":null") == true)
    }

    @Test func aRefusalIsLostAndNonsenseIsRefusedBeforeAnyFetch() {
        let lost = run(answers: [path("from=-12&limit=12"): [PageScript.Answer(status: 401, body: "{}")]])
        #expect(lost.outcome == .lost)
        let down = run(before: "10", answers: [path("from=0&limit=10"): [PageScript.Answer(status: 500, body: "")]])
        #expect(down.outcome == .unreadable)
        for (frame, before) in [("\"../../usage\"", "null"), ("\"\(root)\"", "0"), ("\"\(root)\"", "10000000"), ("\"\(root)\"", "1.5"), ("\"\(root)\"", "\"5\"")] {
            let bad = run(before: before, frame: frame, answers: [:])
            #expect(bad.raw == #"{"outcome":"refused"}"#, "\(frame) \(before)")
            #expect(bad.requests.isEmpty)
            #expect(bad.outcome == .unreadable)
        }
    }

    @Test func aPageThatDoesntMatchOrACallWithNoVersionsIsUnreadable() {
        let broken = [["role": "user", "content": 5] as [String: Any]]
        let one = run(before: "1", answers: [path("from=0&limit=1"): [reply(broken, from: 0, total: 1)]])
        #expect(one.outcome == .unreadable)
        let none = run(before: "1", ids: [], answers: [path("from=0&limit=1"): [reply([Show.said("hi")], from: 0, total: 1)]])
        #expect(none.outcome == .unreadable)
        let elsewhere = run(before: "10", answers: [path("from=0&limit=10"): [reply(filler(0..<10), from: 3, total: 10)]])
        #expect(elsewhere.outcome == .unreadable)
    }

    @Test func swiftChecksWhatThePageSaid() {
        let versions = Show.ids
        func read(_ json: String) -> ShowingPageRead { HistoryReaderScript.showingOutcome(of: Data(json.utf8), versions: versions) }
        let found = #"{"i":7,"at":1791833000000,"text":"Here.","how":"inline","v":"\#(Show.v2)"}"#
        let good = #"{"outcome":"read","total":10,"from":4,"newest":1791833000000,"found":\#(found)}"#
        guard case .page(let page) = read(good) else { Issue.record("not a page"); return }
        #expect(page.found?.i == 7 && page.total == 10 && page.from == 4 && page.newest == Show.date(ts))
        #expect(read(#"{"outcome":"lost"}"#) == .lost && read(#"{"outcome":"cancelled"}"#) == .cancelled)
        #expect(read(#"{"outcome":"refused"}"#) == .unreadable && read("[]") == .unreadable && read("nope") == .unreadable)
        let longText = String(repeating: "a", count: 20_001)
        let bad = [
            found.replacingOccurrences(of: #""i":7"#, with: #""i":3"#), found.replacingOccurrences(of: #""i":7"#, with: #""i":10"#),
            found.replacingOccurrences(of: #""how":"inline""#, with: #""how":"guess""#),
            found.replacingOccurrences(of: Show.v2, with: Show.other), found.replacingOccurrences(of: #""text":"Here.""#, with: #""text":"\#(longText)""#),
            found.replacingOccurrences(of: #""at":1791833000000"#, with: #""at":"today""#), found.replacingOccurrences(of: #""text":"Here.""#, with: #""text":5"#),
        ]
        for message in bad {
            #expect(read(#"{"outcome":"read","total":10,"from":4,"newest":null,"found":\#(message)}"#) == .unreadable, "\(message.prefix(60))")
        }
        for page in [#"{"outcome":"read","total":10,"from":11,"newest":null,"found":null}"#, #"{"outcome":"read","total":-1,"from":0,"newest":null,"found":null}"#,
                     #"{"outcome":"read","total":10,"from":4,"newest":5,"found":null}"#, #"{"outcome":"read","total":10,"newest":null,"found":null}"#] {
            #expect(read(page) == .unreadable, "\(page)")
        }
        // A message with no text is a message (a mention in a reply that is all files).
        #expect(read(#"{"outcome":"read","total":10,"from":4,"newest":null,"found":{"i":5,"at":null,"text":"","how":"mention","v":"\#(Show.v1)"}}"#)
                == .page(ShowingPage(total: 10, from: 4, newest: nil, found: ShowingMessage(i: 5, at: nil, text: "", how: .mention, v: Show.v1))))
    }
}

/// The read's controller, in the page's content world, as the shelf's reads file theirs.
private final class ShowingAbortPage {
    let script = PageScript("""
    var __results = {}, __pending = {}, __controllers = 0;
    function __Signal() { this.aborted = false; this.listeners = []; }
    __Signal.prototype.addEventListener = function (type, listener) { if (type === "abort") { this.listeners.push(listener); } };
    __Signal.prototype.fire = function () {
        if (this.aborted) { return; }
        this.aborted = true;
        var all = this.listeners;
        this.listeners = [];
        for (var i = 0; i < all.length; i++) { all[i](); }
    };
    var AbortController = function () { __controllers += 1; this.signal = new __Signal(); };
    AbortController.prototype.abort = function () { this.signal.fire(); };
    var AbortSignal = function () {};
    AbortSignal.timeout = function () { return undefined; };
    AbortSignal.any = function (signals) {
        var either = new __Signal();
        for (var i = 0; i < signals.length; i++) { signals[i].addEventListener("abort", function () { either.fire(); }); }
        return either;
    };
    var document = { cookie: "" };
    var fetch = function (path, init) {
        return new Promise(function (resolve, reject) {
            var signal = init && init.signal;
            var abort = function () { reject(new Error("AbortError")); };
            if (signal) { if (signal.aborted) { abort(); return; } signal.addEventListener("abort", abort); }
            __pending[path] = resolve;
        });
    };
    function __answer(path, status, body) {
        var resolve = __pending[path];
        delete __pending[path];
        resolve({ status: status, ok: status >= 200 && status < 300, text: function () { return Promise.resolve(body); } });
    }
    """)

    func start(nonce: String?, label: String = "a") {
        script.set("__label", label)
        script.set("__nonce", nonce ?? "")
        script.set("__ids", Show.json(Show.ids))
        script.evaluate("""
        (function (label, nonce, ids) {
            __results[label] = null;
            return (async function (frameId, before, versionIds, nonce) {
            \(HistoryReaderScript.showingBody)
            })("\(root)", 10, ids, nonce === "" ? null : nonce)
                .then(function (v) { __results[label] = v; }, function (e) { __results[label] = "threw: " + e; });
        })(__label, __nonce, JSON.parse(__ids));
        """)
        #expect(script.exception == nil)
    }

    func result(_ label: String = "a") -> String? {
        script.set("__label", label)
        return script.evaluate("__results[__label]")
    }

    func abort(_ nonce: String) -> String? {
        script.set("__nonce", nonce)
        script.evaluate("""
        __aborted = null;
        (async function (nonce) {
        \(ArtifactReaderScript.abort)
        })(__nonce).then(function (v) { __aborted = String(v); });
        """)
        #expect(script.exception == nil)
        return script.evaluate("__aborted")
    }

    var filed: [String] {
        let json = script.evaluate("JSON.stringify(Object.keys(globalThis.\(ArtifactReaderScript.readsName) || {}).sort())") ?? "[]"
        return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    func answer(_ body: String, status: Int = 200) {
        script.set("__path", "/api/frames/\(root)/messages?from=0&limit=10")
        script.set("__body", body)
        script.evaluate("__answer(__path, \(status), __body);")
        #expect(script.exception == nil)
    }
}

struct ShowingAbortTests {
    private func outcome(_ raw: String?) -> ShowingPageRead? {
        raw.map { HistoryReaderScript.showingOutcome(of: Data($0.utf8), versions: Show.ids) }
    }

    @Test func anAbortEndsTheFetchAndTheReadIsCancelledNotUnreadable() {
        let page = ShowingAbortPage()
        page.start(nonce: "nonce-showing-1")
        #expect(page.filed == ["nonce-showing-1"])
        #expect(page.result() == nil, "the fetch is pending")
        #expect(page.abort("nonce-other") == "false" && page.filed == ["nonce-showing-1"], "another nonce is let be")
        #expect(page.abort("nonce-showing-1") == "true")
        #expect(outcome(page.result()) == .cancelled)
        #expect(page.filed.isEmpty, "its entry is gone")
        #expect(page.abort("nonce-showing-1") == "false")
    }

    @Test func aReadThatEndsTakesItsEntryOutAndAnswersAsItShould() {
        let page = ShowingAbortPage()
        page.start(nonce: "nonce-showing-2")
        let rows = (0..<10).map { Show.you("Row \($0)", ts: ts + $0 * 1_000) }
        page.answer(Show.json(["from": 0, "total": 10, "messages": rows] as [String: Any]))
        guard case .page(let read)? = outcome(page.result()) else { Issue.record("not a page: \(page.result() ?? "nil")"); return }
        #expect(read.from == 0 && read.found == nil)
        #expect(page.filed.isEmpty)
    }

    @Test func aRefusedAnswerLeavesNothingFiled() {
        let page = ShowingAbortPage()
        page.start(nonce: "nonce-showing-3")
        page.answer("{}", status: 401)
        #expect(outcome(page.result()) == .lost)
        #expect(page.filed.isEmpty)
    }

    @Test func aReadWithNoNonceOrAMalformedOneFilesNothing() {
        let none = ShowingAbortPage()
        none.start(nonce: nil)
        #expect(none.filed.isEmpty)
        #expect(none.script.evaluate("String(__controllers)") == "0")
        let bad = ShowingAbortPage()
        bad.start(nonce: "../not-a-nonce")
        #expect(bad.filed.isEmpty)
        #expect(bad.abort("../not-a-nonce") == "false")
        // They still read.
        none.answer("{}", status: 500)
        #expect(outcome(none.result()) == .unreadable)
    }
}

// MARK: Keep: the walk

@MainActor
struct HistoryShowingWalkTests {
    private let hit = ShowingMessage(i: 12, at: nil, text: "Here.", how: .inline, v: Show.v2)

    /// A history of `total` rows, read by pages as the page answers them: the
    /// last 50, then the 50 before each `before`. `found` says which pages
    /// (by their first row) hold a message; `newest` the page's time.
    @MainActor
    private final class History {
        let total: Int
        var found: [Int: ShowingMessage] = [:]
        var newest: [Int: Date?] = [:]
        var outcomes: [Int: ShowingPageRead] = [:]
        private(set) var asked: [Int?] = []

        init(total: Int) { self.total = total }

        func read(_ before: Int?) async throws -> ShowingPageRead {
            asked.append(before)
            let from = max(0, (before ?? total) - 50)
            if let outcome = outcomes[from] { return outcome }
            return .page(ShowingPage(total: total, from: from, newest: newest[from] ?? nil, found: found[from]))
        }
    }

    @Test func theLastPageFirstAndItsMessageEndsTheWalk() async throws {
        let history = History(total: 300)
        history.found[250] = hit
        let result = try await HistoryShowing.walk(near: nil, read: history.read)
        #expect(result == .found(hit))
        #expect(history.asked == [nil])
    }

    @Test func eachOlderPageOverlapsTheOneBeforeAndSixAreTheMost() async throws {
        let history = History(total: 1_000)
        let result = try await HistoryShowing.walk(near: nil, read: history.read)
        #expect(result == .notFound)
        // Page after page: 950, 906, 862, 818, 774, 730 (each starts 44 rows before the last).
        #expect(history.asked == [nil, 956, 912, 868, 824, 780])
        #expect(history.asked.count == HistoryShowing.pages)
    }

    @Test func aMessageOnAnOlderPageIsFoundThereAndNothingOlderIsAskedFor() async throws {
        let history = History(total: 1_000)
        history.found[862] = hit
        #expect(try await HistoryShowing.walk(near: nil, read: history.read) == .found(hit))
        #expect(history.asked == [nil, 956, 912])
    }

    @Test func theStartOfTheHistoryEndsTheWalk() async throws {
        let history = History(total: 70)
        #expect(try await HistoryShowing.walk(near: nil, read: history.read) == .notFound)
        #expect(history.asked == [nil, 26], "the second page starts at the first row")
        // The page before is never asked for past the history's end.
        let odd = History(total: 70)
        odd.outcomes[20] = .page(ShowingPage(total: 70, from: 68, newest: nil, found: nil))
        _ = try await HistoryShowing.walk(near: nil, read: odd.read)
        #expect(odd.asked.dropFirst().first == 70)
        let short = History(total: 30)
        #expect(try await HistoryShowing.walk(near: nil, read: short.read) == .notFound)
        #expect(short.asked == [nil])
        #expect(try await HistoryShowing.walk(near: nil, read: History(total: 0).read) == .notFound)
    }

    @Test func aPageOlderThanTheVersionsEndsTheWalkEarly() async throws {
        let near = Date(timeIntervalSince1970: 1_791_833_000)
        let history = History(total: 1_000)
        history.newest[950] = Date(timeIntervalSince1970: 1_791_833_100)
        history.newest[906] = Date(timeIntervalSince1970: 1_791_832_999)
        #expect(try await HistoryShowing.walk(near: near, read: history.read) == .notFound)
        #expect(history.asked == [nil, 956], "the second page's newest message is older than the versions")
        // Equal is not older; a page with no time can't say; no `near` never stops.
        let equal = History(total: 1_000)
        equal.newest[950] = near
        equal.found[906] = hit
        #expect(try await HistoryShowing.walk(near: near, read: equal.read) == .found(hit))
        let untimed = History(total: 1_000)
        #expect(try await HistoryShowing.walk(near: near, read: untimed.read) == .notFound)
        #expect(untimed.asked.count == 6)
        let never = History(total: 1_000)
        never.newest[950] = Date(timeIntervalSince1970: 1)
        #expect(try await HistoryShowing.walk(near: nil, read: never.read) == .notFound)
        #expect(never.asked.count == 6)
        // A page that holds the message is the answer, old or not.
        let old = History(total: 1_000)
        old.newest[950] = Date(timeIntervalSince1970: 1)
        old.found[950] = hit
        #expect(try await HistoryShowing.walk(near: near, read: old.read) == .found(hit))
    }

    @Test func aPageThatCantBeReadEndsItUnreadable() async throws {
        let history = History(total: 1_000)
        history.outcomes[906] = .unreadable
        #expect(try await HistoryShowing.walk(near: nil, read: history.read) == .unreadable)
        #expect(history.asked == [nil, 956])
        let lost = History(total: 1_000)
        lost.outcomes[950] = .lost
        #expect(try await HistoryShowing.walk(near: nil, read: lost.read) == .unreadable)
    }

    @Test func anAbortedPageOrACancelledTaskThrowsCancellation() async {
        let history = History(total: 1_000)
        history.outcomes[906] = .cancelled
        do {
            _ = try await HistoryShowing.walk(near: nil, read: history.read)
            Issue.record("an aborted page ended the walk without a throw")
        } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect(history.asked == [nil, 956])
        let second = History(total: 1_000)
        let task = Task { @MainActor in
            try await HistoryShowing.walk(near: nil) { before in
                try await Task.sleep(for: .milliseconds(1))
                return try await second.read(before)
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("a cancelled task read on")
        } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect(second.asked.count <= 1)
    }

    @Test func theNonceTheWalkTakesIsTheOneThePageFiles() {
        #expect(HistoryShowing.isNonce(ArtifactReadAbort.makeNonce()))
        for text in ["a", "A-b-9", String(repeating: "a", count: 64)] { #expect(HistoryShowing.isNonce(text), "\(text)") }
        for text in ["", "a b", "a/b", "ä", String(repeating: "a", count: 65), "a_b", "a\n"] { #expect(!HistoryShowing.isNonce(text), "\(text)") }
    }
}
