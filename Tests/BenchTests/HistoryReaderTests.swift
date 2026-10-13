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

    private func run(before: String = "null", frame: String = "\"\(root)\"", answers: [String: [PageScript.Answer]])
        -> (outcome: HistoryReaderScript.Outcome?, raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (raw, requests) = script.runPage(HistoryReaderScript.pageBody, arguments: [("frameId", frame), ("before", before)],
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
        guard case .read(let page)? = outcome else { Issue.record("not read"); return }
        #expect(page.total == 100)
        #expect(page.from == 50)
        #expect(page.items.map(\.index) == Array(50..<100))
    }

    @Test func aTailThatEchoesItsNegativeFromStillReads() {
        let (outcome, _, _) = run(answers: [
            path("from=-12&limit=12"): [reply(from: -12, total: 20, count: 12, first: 8)],
            path("from=0&limit=8"): [reply(from: 0, total: 20, count: 8)],
        ])
        guard case .read(let page)? = outcome else { Issue.record("not read"); return }
        #expect(page.from == 0)
        #expect(page.items.count == 20)
    }

    @Test func aShortSessionIsOneRequest() {
        let (outcome, _, requests) = run(answers: [path("from=-12&limit=12"): [reply(from: 0, total: 5, count: 5)]])
        #expect(requests.count == 1)
        guard case .read(let page)? = outcome else { Issue.record("not read"); return }
        #expect(page.items.count == 5)
    }

    @Test func anEarlierPageIsTheFiftyRowsBeforeIt() {
        let (outcome, _, requests) = run(before: "120", answers: [path("from=70&limit=50"): [reply(from: 70, total: 300, count: 50)]])
        #expect(requests.map(\.path) == [path("from=70&limit=50")])
        guard case .read(let page)? = outcome else { Issue.record("not read"); return }
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
