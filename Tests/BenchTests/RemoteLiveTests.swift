// RemoteLiveTests.swift — the phone's live text (Phase 4) on made-up frames:
// the page's projection of the streaming buffer and of the activity line, in
// JavaScriptCore (the very strings the page runs) against a fake daemon, then
// Swift's checks and the route's own state. Every text and tool name is
// invented; what must never leave the page holds "SECRET".
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let helper = "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6"

private func json(_ value: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])) ?? Data(),
           as: UTF8.self)
}

private func evaluated(_ function: String, _ arguments: [String?], source: String = LiveScript.projections) -> String? {
    let script = PageScript(source)
    let out = script.callJSON(function, arguments)
    #expect(script.exception == nil)
    return out
}

// MARK: The streaming buffer

struct LiveTextTests {
    private func project(_ raw: String) -> (ok: Bool, text: String?) {
        let out = evaluated("benchLiveText", [raw]) ?? ""
        let object = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
        return (object?["ok"] as? Bool ?? false, object?["text"] as? String)
    }

    private func buffer(text: String, thinking: String = "SECRET-THINKING", stdout: Any = [["tool_use_id": "t1", "stdout": "SECRET-STDOUT"]]) -> String {
        json(["frame_id": root, "text": text, "thinking": thinking, "tool_stdout": stdout])
    }

    @Test func nothingBufferedIsNoTextAndStillWorks() {
        let result = project("null")
        #expect(result.ok)
        #expect(result.text == nil)
    }

    @Test func onlyTheTextComesBackNeverThinkingOrOutput() {
        let out = evaluated("benchLiveText", [buffer(text: "I'll compare the *made-up* buffers.")]) ?? ""
        #expect(!out.contains("SECRET"))
        #expect(out == #"{"ok":true,"text":"I'll compare the *made-up* buffers."}"#)
    }

    @Test func aTextIsKeptAsItIsInsideTheTail() {
        let text = "Line one.\n\n  Line two, indented.  \n"
        #expect(project(buffer(text: text)).text == text)
    }

    @Test func theLastFourThousandCharactersAreKept() {
        let exactly = String(repeating: "a", count: 4000)
        #expect(project(buffer(text: exactly)).text == exactly)
        let longer = "FIRST" + String(repeating: "b", count: 4000)
        let tail = project(buffer(text: longer)).text
        #expect(tail == String(repeating: "b", count: 4000))
        // The end is what is being written: a text of 10,000 keeps its last 4,000.
        let numbered = (0..<2000).map { String(format: "%04d", $0) }.joined()
        #expect(project(buffer(text: numbered)).text == String(numbered.suffix(4000)))
    }

    @Test func aCharacterIsNeverSplit() throws {
        let emoji = String(repeating: "😀", count: 4001)
        let tail = try #require(project(buffer(text: emoji)).text)
        #expect(tail.unicodeScalars.count == 4000)
        #expect(tail == String(repeating: "😀", count: 4000))
        let wide = String(repeating: "界", count: 4500)
        #expect(try #require(project(buffer(text: wide)).text).unicodeScalars.count == 4000)
    }

    @Test(arguments: ["", "   ", "\n\n\t "])
    func nothingButSpaceIsNoText(_ text: String) {
        let result = project(buffer(text: text))
        #expect(result.ok)
        #expect(result.text == nil)
    }

    @Test(arguments: [
        #"{"text": "x", "tool_stdout": []}"#,
        #"{"text": "x", "thinking": null, "tool_stdout": []}"#,
        #"{"text": "x", "thinking": "", "tool_stdout": {}}"#,
        #"{"text": "x", "thinking": "", "tool_stdout": "none"}"#,
        #"{"text": 5, "thinking": "", "tool_stdout": []}"#,
        #"{"text": null, "thinking": "", "tool_stdout": []}"#,
        #"{"thinking": "", "tool_stdout": []}"#,
        #"["x"]"#, #""x""#, "42", "true",
    ])
    func aBufferThatIsNotTheDaemonsShapeIsOff(_ raw: String) {
        let result = project(raw)
        #expect(!result.ok)
        #expect(result.text == nil)
    }

    @Test func aBuffersOtherKeysAreIgnored() {
        let raw = #"{"frame_id": "\#(root)", "text": "Hello", "thinking": "", "tool_stdout": [], "secret": "SECRET", "chunks": 4}"#
        let out = evaluated("benchLiveText", [raw]) ?? ""
        #expect(out == #"{"ok":true,"text":"Hello"}"#)
    }
}

// MARK: The activity line

struct LiveActivityTests {
    private func rows(_ items: [[String: Any]]) -> String { json(items) }

    private func use(_ names: [String], ids: [String]? = nil) -> [String: Any] {
        let blocks: [[String: Any]] = names.enumerated().map { index, name in
            ["type": "tool_use", "id": ids?[index] ?? "toolu_\(index)", "name": name, "input": ["command": "SECRET-INPUT"]]
        }
        return ["role": "assistant", "content": [["type": "text", "text": "SECRET-ASSISTANT-TEXT"]] + blocks, "_ts": 1_791_833_000_000]
    }

    private func result(_ ids: [String]) -> [String: Any] {
        ["role": "user", "content": ids.map { ["type": "tool_result", "tool_use_id": $0, "content": "SECRET-RESULT"] }, "_ts": 1_791_833_010_000]
    }

    private func user(_ text: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var row: [String: Any] = ["role": "user", "content": text, "_ts": 1_791_833_020_000]
        for (key, value) in extra { row[key] = value }
        return row
    }

    private func activity(working: Bool = true, pending: Bool = false, _ items: [[String: Any]]?) -> String? {
        let out = evaluated("benchLiveActivity", [working ? "true" : "false", pending ? "true" : "false", items.map(rows)])
        return out.flatMap { $0 == "null" ? nil : String($0.dropFirst().dropLast()) }
    }

    @Test func aSessionThatIsNotWorkingHasNoActivity() {
        #expect(activity(working: false, pending: true, [use(["bash"])]) == nil)
    }

    @Test func aPendingRequestComesFirst() {
        #expect(activity(pending: true, [use(["bash"])]) == "Waiting for your approval")
        #expect(activity(pending: true, nil) == "Waiting for your approval")
    }

    @Test(arguments: ["bash", "powershell", "python", "r"])
    func aCodeToolIsExecutingCode(_ name: String) {
        #expect(activity([user("Go"), use([name])]) == "Executing code")
    }

    @Test(arguments: [["delegate"], ["wait_for_notification"], ["delegate", "delegate"], ["delegate", "wait_for_notification"]])
    func onlyWaitsAreWaitingOnSubagents(_ names: [String]) {
        #expect(activity([use(names)]) == "Waiting on subagents")
    }

    @Test func codeBeatsAWait() {
        #expect(activity([use(["delegate", "bash"])]) == "Executing code")
    }

    @Test(arguments: ["repl", "operon", "compute_provider", "web_search", "mcp__made_up__lookup", "SECRET-tool-name"])
    func anyOtherToolIsRunningATool(_ name: String) {
        #expect(activity([use([name])]) == "Running a tool")
        #expect(activity([use(["delegate", name])]) == "Running a tool")
    }

    @Test(arguments: ["boundary", "request_review", "send_user_message", "update_step_status"])
    func aMetaToolIsNotAnActivity(_ name: String) {
        #expect(activity([use([name])]) == "Working")
        #expect(activity([use([name, "python"])]) == "Executing code")
    }

    @Test func aToolWithItsResultIsDone() {
        #expect(activity([use(["bash"], ids: ["t1"]), result(["t1"])]) == "Working")
        // One of two done: the other still runs.
        #expect(activity([use(["bash", "delegate"], ids: ["t1", "t2"]), result(["t1"])]) == "Waiting on subagents")
        // A result for another call doesn't count.
        #expect(activity([use(["bash"], ids: ["t1"]), result(["t9"])]) == "Executing code")
    }

    @Test func aVisibleUserRowEndsTheWalk() {
        #expect(activity([use(["bash"]), user("Actually, stop.")]) == "Working")
    }

    @Test(arguments: ["_harness_notice", "_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent", "_from_aside"])
    func aFlaggedUserRowIsNotTheUserSpeaking(_ flag: String) {
        #expect(activity([use(["bash"]), user("SECRET", [flag: true])]) == "Executing code")
    }

    @Test(arguments: ["[System] note", "[compute] x", "[Memory] x", "[Auditor] x", "[image: a.png]", "[document: a.pdf]",
                      "You are reviewing work an agent did in frame abc"])
    func aMarkerRowIsNotTheUserSpeaking(_ text: String) {
        #expect(activity([use(["bash"]), user(text)]) == "Executing code")
    }

    @Test func rowsOfOnlyToolResultsDontEndTheWalk() {
        #expect(activity([use(["bash"], ids: ["t1"]), result(["t0"])]) == "Executing code")
    }

    @Test func theNewestAssistantRowWithAnOpenCallDecides() {
        #expect(activity([use(["bash"], ids: ["t1"]), ["role": "assistant", "content": [["type": "text", "text": "Thinking."]]]]) == "Executing code")
        #expect(activity([use(["delegate"], ids: ["t1"]), use(["python"], ids: ["t2"])]) == "Executing code")
    }

    @Test func aTooBigRowHasNothingToRead() {
        var big = use(["bash"])
        big["_oversized_bytes"] = 3_000_000
        #expect(activity([big]) == "Working")
    }

    @Test func nothingToReadIsWorking() {
        #expect(activity(nil) == "Working")
        #expect(activity([]) == "Working")
        #expect(activity([["role": "assistant", "content": "plain"], "row" as Any].compactMap { $0 as? [String: Any] }) == "Working")
    }

    @Test func onlyOneOfFiveWordsEverComesOutWhateverTheToolsAreCalled() {
        let words: Set<String> = ["Waiting for your approval", "Executing code", "Waiting on subagents", "Running a tool", "Working"]
        for names in [["SECRET-A"], ["bash", "SECRET-B"], ["delegate", "SECRET-C"], ["SECRET-D", "SECRET-E", "python"], []] as [[String]] {
            let out = activity([use(names)]) ?? ""
            #expect(words.contains(out), "\(names) → \(out)")
            #expect(!out.contains("SECRET"))
        }
    }

    @Test func theWordsAreTheOnesSwiftKnows() {
        #expect(LiveScript.Activity.all == ["Waiting for your approval", "Executing code", "Waiting on subagents", "Running a tool", "Working"])
    }
}

// MARK: The in-page body, against a fake daemon

struct LivePageTests {
    private let frame = "/api/frames/\(root)?shallow=true"
    private let streaming = "/api/frames/\(root)/streaming"
    private let trace = "/api/frames/\(root)/trace-shallow?include_messages=false"
    private let messages = "/api/frames/\(root)/messages?from=-12&limit=12"

    private func run(_ id: String = root, activity: Bool = false, text: Bool = true, mayWait: Bool = false,
                     answers: [String: [PageScript.Answer]]) -> (outcome: LiveScript.Outcome?, raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (result, requests) = script.runPage(LiveScript.body, arguments: [("frameId", json(id)), ("wantActivity", activity ? "true" : "false"),
                                                                              ("wantText", text ? "true" : "false"),
                                                                              ("mayWait", mayWait ? "true" : "false")], answers: answers)
        #expect(script.exception == nil)
        return (result.map { LiveScript.outcome(of: Data($0.utf8)) }, result, requests)
    }

    private func ok(_ body: String) -> [PageScript.Answer] { [.init(status: 200, body: body)] }
    private func working(_ requests: [[String: Any]] = []) -> String {
        ReaderFixture.frame(status: "processing", context: "null", output: json(["pending_input_requests": requests, "response": "SECRET-RESPONSE"]))
    }
    private func buffer(_ text: String) -> String {
        json(["frame_id": root, "text": text, "thinking": "SECRET-THINKING", "tool_stdout": [["tool_use_id": "t1", "stdout": "SECRET-STDOUT"]]])
    }
    private let page: String = ReaderFixture.page(#"""
    [{"role": "user", "content": "Go.", "_ts": 1791833000000},
     {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "python", "input": {"code": "SECRET-CODE"}}], "_ts": 1791833010000}]
    """#)

    private func read(_ outcome: LiveScript.Outcome?) -> LiveRead? {
        if case .read(let read)? = outcome { read } else { nil }
    }

    @Test func aSessionThatIsNotWorkingReadsOnlyItsFrame() {
        let (outcome, _, requests) = run(activity: true, answers: [frame: ok(ReaderFixture.frame(status: "completed"))])
        #expect(read(outcome) == LiveRead(working: false, text: nil, activity: nil, streaming: .skipped))
        #expect(requests.map(\.path) == [frame])
    }

    @Test func aWorkingSessionsTextIsTheCurrentBuffersTail() {
        let (outcome, raw, requests) = run(answers: [frame: ok(working()), streaming: ok(buffer("Comparing the first two buffers."))])
        #expect(read(outcome) == LiveRead(working: true, text: "Comparing the first two buffers.", activity: nil, streaming: .ok))
        #expect(requests.map(\.path) == [frame, streaming])
        #expect(requests.allSatisfy { $0.method == "GET" && $0.cache == "no-store" && $0.body == nil })
        // Never thinking, never output, never the frame's own reply.
        #expect(raw?.contains("SECRET") == false)
    }

    @Test func aTextOverFourThousandCharactersIsTheEndOfIt() {
        let long = String(repeating: "a", count: 3000) + String(repeating: "z", count: 4000)
        let (outcome, _, _) = run(answers: [frame: ok(working()), streaming: ok(buffer(long))])
        #expect(read(outcome)?.text == String(repeating: "z", count: 4000))
    }

    @Test func nothingBufferedIsNoText() {
        let (outcome, _, _) = run(answers: [frame: ok(working()), streaming: ok("null")])
        #expect(read(outcome) == LiveRead(working: true, text: nil, activity: nil, streaming: .ok))
    }

    /// A Bool through `callAsyncJavaScript` may arrive as a number.
    @Test func theFlagsMayArriveAsNumbers() {
        let script = PageScript()
        let (result, requests) = script.runPage(LiveScript.body, arguments: [("frameId", json(root)), ("wantActivity", "1"), ("wantText", "1"),
                                                                              ("mayWait", "1")], answers: [
            frame: ok(working()), streaming: ok(buffer("Hello")), trace: ok(json(["id": root, "children": [Any]()])), messages: ok(page),
        ])
        #expect(script.exception == nil)
        #expect(result.map { LiveScript.outcome(of: Data($0.utf8)) } == .read(LiveRead(working: true, text: "Hello", activity: "Executing code", streaming: .ok)))
        #expect(requests.map(\.path) == [frame, streaming, trace, messages])
        let off = PageScript()
        let (none, offRequests) = off.runPage(LiveScript.body, arguments: [("frameId", json(root)), ("wantActivity", "0"), ("wantText", "0"),
                                                                           ("mayWait", "0")],
                                              answers: [frame: ok(working())])
        #expect(none.map { LiveScript.outcome(of: Data($0.utf8)) } == .read(LiveRead(working: true, streaming: .skipped)))
        #expect(offRequests.map(\.path) == [frame])
    }

    @Test func textNotWantedIsNotRead() {
        let (outcome, _, requests) = run(text: false, answers: [frame: ok(working())])
        #expect(read(outcome) == LiveRead(working: true, text: nil, activity: nil, streaming: .skipped))
        #expect(requests.map(\.path) == [frame])
    }

    @Test(arguments: [(404, "{}"), (405, "{}"), (403, "{}"), (400, "{}"), (200, "<html>"), (200, "[1]"), (200, #"{"text": 1}"#)])
    func aDaemonWithoutTheRouteOrAnotherShapeIsOff(_ status: Int, _ body: String) {
        let (outcome, _, requests) = run(answers: [frame: ok(working()), streaming: [.init(status: status, body: body)]])
        #expect(read(outcome) == LiveRead(working: true, text: nil, activity: nil, streaming: .off))
        #expect(requests.count == 2)
    }

    @Test(arguments: [500, 502, 503, 408, 429])
    func aFailureThatMayPassIsFailedNotOff(_ status: Int) {
        let (outcome, _, _) = run(answers: [frame: ok(working()), streaming: [.init(status: status, body: "{}")]])
        #expect(read(outcome) == LiveRead(working: true, text: nil, activity: nil, streaming: .failed))
        // No answer at all (fetch throws): the same.
        #expect(read(run(answers: [frame: ok(working())]).outcome) == LiveRead(working: true, text: nil, activity: nil, streaming: .failed))
    }

    @Test func aRefusedSignInIsLostWhereverItHappens() {
        #expect(run(answers: [frame: [.init(status: 401, body: "{}")]]).outcome == .lost)
        #expect(run(answers: [frame: ok(working()), streaming: [.init(status: 401, body: "{}")]]).outcome == .lost)
        #expect(run(activity: true, mayWait: true, answers: [frame: ok(working()), streaming: ok("null"), trace: [.init(status: 401, body: "{}")]]).outcome == .lost)
        #expect(run(activity: true, answers: [frame: ok(working()), streaming: ok("null"), trace: ok(json(["id": root, "children": [Any]()])),
                                              messages: [.init(status: 401, body: "{}")]]).outcome == .lost)
    }

    @Test func aFrameThatCantBeReadIsUnreadable() {
        #expect(run(answers: [frame: [.init(status: 500, body: "{}")]]).outcome == .unreadable)
        #expect(run(answers: [frame: ok("<html>")]).outcome == .unreadable)
        #expect(run(answers: [frame: ok(#"{"status": 7}"#)]).outcome == .unreadable)
        #expect(run(answers: [frame: ok("[]")]).outcome == .unreadable)
        #expect(run(answers: [:]).outcome == .unreadable)
    }

    @Test(arguments: ["0b7c2f4e", "0B7C2F4E-1A2B-4C3D-8E9F-A0B1C2D3E4F5", "../../usage-0000000000000000000000000000", "\(ReaderFixture.root)/x"])
    func anIDThatIsNotOneReadsNothing(_ id: String) {
        let (raw, requests) = (run(id, answers: [:]).raw, run(id, answers: [:]).requests)
        #expect(raw == #"{"outcome":"refused"}"#)
        #expect(requests.isEmpty)
    }

    // MARK: The activity

    @Test func theActivityReadsTheHelpersAndTheLastMessages() {
        let (outcome, raw, requests) = run(activity: true, mayWait: true, answers: [
            frame: ok(working()), streaming: ok("null"), trace: ok(json(["id": root, "children": [Any]()])), messages: ok(page),
        ])
        #expect(read(outcome) == LiveRead(working: true, text: nil, activity: "Executing code", streaming: .ok))
        #expect(requests.map(\.path) == [frame, streaming, trace, messages])
        #expect(raw?.contains("SECRET") == false)
        #expect(raw?.contains("python") == false)
    }

    @Test func aPendingRequestOfTheRootIsWaitingForApprovalWithoutReadingMessages() {
        let pending: [String: Any] = ["kind": "local_exec", "requestId": "r", "tool_id": "t", "createdAt": "2026-10-12T19:30:00Z", "mode": "live"]
        let (outcome, _, requests) = run(activity: true, answers: [
            frame: ok(working([pending])), streaming: ok("null"), trace: ok(json(["id": root, "children": [Any]()])),
        ])
        #expect(read(outcome)?.activity == "Waiting for your approval")
        // The root's own request is in its frame: no helpers to read.
        #expect(requests.map(\.path) == [frame, streaming])
    }

    @Test func aPendingRequestOfAHelperIsWaitingForApproval() {
        let asking: [String: Any] = ["id": helper, "parent_frame_id": root, "status": "awaiting_user_response", "children": [Any](),
                                     "output_data": ["pending_input_requests": [["kind": "network", "requestId": "r", "tool_id": "t",
                                                                                 "createdAt": "2026-10-12T19:30:00Z", "mode": "parked", "target": "h"]]]]
        let (outcome, _, _) = run(activity: true, mayWait: true, answers: [
            frame: ok(working()), streaming: ok("null"), trace: ok(json(["id": root, "children": [asking]])), messages: ok(page),
        ])
        #expect(read(outcome)?.activity == "Waiting for your approval")
    }

    @Test func aQuestionPendingCountsToo() {
        let question: [String: Any] = ["kind": "ask", "tool_id": "t", "createdAt": "2026-10-12T19:30:00Z", "questions": [["question": "Q?"]]]
        let (outcome, _, _) = run(activity: true, answers: [frame: ok(working([question])), streaming: ok("null"),
                                                            trace: ok(json(["id": root, "children": [Any]()]))])
        #expect(read(outcome)?.activity == "Waiting for your approval")
    }

    @Test func aTraceThatFailsIsReadAsNoHelpersAndTheMessagesStillCount() {
        let (outcome, _, requests) = run(activity: true, mayWait: true, answers: [
            frame: ok(working()), streaming: ok("null"), trace: [.init(status: 500, body: "{}")], messages: ok(page),
        ])
        #expect(read(outcome)?.activity == "Executing code")
        #expect(requests.map(\.path) == [frame, streaming, trace, messages])
    }

    /// Fable's review of 0.5.0, P3: up to 2,000 frames every 4 s, only while
    /// something may be pending.
    @Test func theHelpersAreReadOnlyWhileSomethingMayBePending() {
        let asking: [String: Any] = ["id": helper, "parent_frame_id": root, "status": "awaiting_user_response", "children": [Any](),
                                     "output_data": ["pending_input_requests": [["kind": "network", "requestId": "r", "tool_id": "t",
                                                                                 "createdAt": "2026-10-12T19:30:00Z", "mode": "parked"]]]]
        let answers: [String: [PageScript.Answer]] = [
            frame: ok(working()), streaming: ok("null"), trace: ok(json(["id": root, "children": [asking]])), messages: ok(page),
        ]
        // Nothing pending as far as the root's frame and Bench's own reading say: no trace.
        let quiet = run(activity: true, answers: answers)
        #expect(quiet.requests.map(\.path) == [frame, streaming, messages])
        #expect(read(quiet.outcome)?.activity == "Executing code")
        // Bench's reading says the session waits (a helper's request): the trace is read, and the request shows.
        let waiting = run(activity: true, mayWait: true, answers: answers)
        #expect(waiting.requests.map(\.path) == [frame, streaming, trace])
        #expect(read(waiting.outcome)?.activity == "Waiting for your approval")
        // A request of the root's own is in its frame: nothing more to read.
        let pending: [String: Any] = ["kind": "local_exec", "requestId": "r", "tool_id": "t", "createdAt": "2026-10-12T19:30:00Z", "mode": "live"]
        var own = answers
        own[frame] = ok(working([pending]))
        let rootAsks = run(activity: true, answers: own)
        #expect(rootAsks.requests.map(\.path) == [frame, streaming])
        #expect(read(rootAsks.outcome)?.activity == "Waiting for your approval")
        // The root waits on helpers (an open `delegate`, here beside an open
        // `python`): a hidden helper's request is invisible to Bench's own
        // reading, so the trace is read after the messages.
        for tools in [["delegate"], ["wait_for_notification"], ["python", "delegate"]] {
            let calls = tools.enumerated().map { ["type": "tool_use", "id": "t\($0.offset)", "name": $0.element, "input": [String: Any]()] }
            var delegating = answers
            delegating[messages] = ok(ReaderFixture.page(json([["role": "user", "content": "Go.", "_ts": 1_791_833_000_000],
                                                               ["role": "assistant", "content": calls, "_ts": 1_791_833_010_000]])))
            let asked = run(activity: true, answers: delegating)
            #expect(asked.requests.map(\.path) == [frame, streaming, messages, trace], "\(tools)")
            #expect(read(asked.outcome)?.activity == "Waiting for your approval", "\(tools)")
            // No helper asks: the words the open calls give.
            delegating[trace] = ok(json(["id": root, "children": [Any]()]))
            #expect(read(run(activity: true, answers: delegating).outcome)?.activity
                    == (tools == ["python", "delegate"] ? "Executing code" : "Waiting on subagents"), "\(tools)")
        }
        // An empty list, or none at all, is nothing pending.
        for output in [json(["pending_input_requests": [Any](), "response": "SECRET"]), "null"] {
            var none = answers
            none[frame] = ok(ReaderFixture.frame(status: "processing", context: "null", output: output))
            #expect(run(activity: true, answers: none).requests.map(\.path) == [frame, streaming, messages], "\(output)")
        }
    }

    @Test func messagesThatCantBeReadStillSayWorking() {
        let (outcome, _, _) = run(activity: true, answers: [
            frame: ok(working()), streaming: ok("null"), trace: ok(json(["id": root, "children": [Any]()])), messages: [.init(status: 500, body: "{}")],
        ])
        #expect(read(outcome)?.activity == "Working")
    }

    @Test func theActivityAloneNeedsNoText() {
        let (outcome, _, requests) = run(activity: true, text: false, mayWait: true, answers: [
            frame: ok(working()), trace: ok(json(["id": root, "children": [Any]()])), messages: ok(page),
        ])
        #expect(read(outcome) == LiveRead(working: true, text: nil, activity: "Executing code", streaming: .skipped))
        #expect(requests.map(\.path) == [frame, trace, messages])
    }
}

// MARK: Swift's own checks

struct LiveReadChecksTests {
    private static func valid() -> [String: Any] {
        ["working": true, "text": "Hello", "activity": "Working", "streaming": "ok"]
    }

    @Test func aValidReadIsTaken() {
        #expect(LiveRead(object: Self.valid()) == LiveRead(working: true, text: "Hello", activity: "Working", streaming: .ok))
        var none = Self.valid()
        none["text"] = NSNull()
        none["activity"] = NSNull()
        #expect(LiveRead(object: none) == LiveRead(working: true, text: nil, activity: nil, streaming: .ok))
    }

    private static func outOfShape() -> [(String, Any)] {
        [("working", 1), ("working", "true"), ("working", NSNull()), ("text", String(repeating: "a", count: 4001)), ("text", "  "), ("text", 5),
         ("activity", "Doing something else"), ("activity", "Run: rm -rf /"), ("activity", 7), ("streaming", "maybe"), ("streaming", NSNull())]
    }

    @Test(arguments: 0..<11)
    func anythingOutOfShapeIsUnreadable(_ index: Int) throws {
        let cases = Self.outOfShape()
        #expect(cases.count == 11)
        let (key, value) = try #require(index < cases.count ? cases[index] : nil)
        var object = Self.valid()
        object[key] = value
        #expect(LiveRead(object: object) == nil, Comment(rawValue: key))
    }

    @Test func theEnvelope() {
        #expect(LiveScript.outcome(of: Data(#"{"outcome":"lost"}"#.utf8)) == .lost)
        #expect(LiveScript.outcome(of: Data(#"{"outcome":"unreadable"}"#.utf8)) == .unreadable)
        #expect(LiveScript.outcome(of: Data(#"{"outcome":"refused"}"#.utf8)) == .unreadable)
        #expect(LiveScript.outcome(of: Data(#"{"outcome":"read","live":{}}"#.utf8)) == .unreadable)
        #expect(LiveScript.outcome(of: Data("not json".utf8)) == .unreadable)
        #expect(LiveScript.outcome(of: Data(#"{"outcome":"read","live":{"working":true,"text":null,"activity":null,"streaming":"ok"}}"#.utf8))
                == .read(LiveRead(working: true)))
    }
}

// MARK: What the route keeps between asks

@MainActor
private final class FakeLiveReader {
    var answers: [String: LiveRead] = [:]
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var asked: [String] = []
    /// What each read was told of Bench's own reading.
    private(set) var mayWait: [Bool] = []
    var known: [SessionStatus] = []

    func live() -> RemoteLive {
        RemoteLive(read: { [self] id, activity, text, mayWait in
            self.asked.append("\(activity ? "activity" : "-")/\(text ? "text" : "-")")
            self.mayWait.append(mayWait)
            await Task.yield()
            return self.answers[id]
        }, now: { [self] in self.now }, known: { [self] in self.known })
    }
}

@MainActor
struct RemoteLiveStateTests {
    private let reader = FakeLiveReader()

    private func ask(_ live: RemoteLive) async -> [String: Any] {
        let data = await live.json(root, extra: [])
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @Test func theAnswerIsTheThreeFieldsWithNullsWritten() async {
        reader.answers[root] = LiveRead(working: true, text: "Hello", activity: "Working")
        let live = reader.live()
        let data = await live.json(root, extra: [])
        #expect(String(decoding: data, as: UTF8.self) == #"{"activity":null,"text":"Hello","working":true}"#)
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Executing code")
        reader.now = reader.now.addingTimeInterval(10)
        #expect(String(decoding: await live.json(root, extra: []), as: UTF8.self) == #"{"activity":"Executing code","text":null,"working":true}"#)
    }

    @Test func theActivityIsAskedForEveryFourSecondsAndTheTextEveryTime() async {
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Executing code")
        let live = reader.live()
        #expect(await ask(live)["activity"] as? String == "Executing code")
        #expect(reader.asked == ["activity/text"])
        reader.now = reader.now.addingTimeInterval(1.5)
        reader.answers[root] = LiveRead(working: true, text: "More text", activity: nil)
        let second = await ask(live)
        // Inside the 4 s: not asked for again, and the kept word is used when there is no text.
        #expect(reader.asked == ["activity/text", "-/text"])
        #expect(second["text"] as? String == "More text")
        reader.answers[root] = LiveRead(working: true, text: nil, activity: nil)
        reader.now = reader.now.addingTimeInterval(1.5)
        #expect(await ask(live)["activity"] as? String == "Executing code")
        #expect(reader.asked == ["activity/text", "-/text", "-/text"])
        reader.now = reader.now.addingTimeInterval(1.5)
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Working")
        #expect(await ask(live)["activity"] as? String == "Working")
        #expect(reader.asked.last == "activity/text")
    }

    @Test func textShowsInsteadOfAnActivityButAPendingRequestStillShows() async {
        let live = reader.live()
        reader.answers[root] = LiveRead(working: true, text: "Writing.", activity: "Working")
        #expect(await ask(live)["activity"] is NSNull)
        reader.now = reader.now.addingTimeInterval(10)
        reader.answers[root] = LiveRead(working: true, text: "Writing.", activity: "Executing code")
        #expect(await ask(live)["activity"] is NSNull)
        reader.now = reader.now.addingTimeInterval(10)
        reader.answers[root] = LiveRead(working: true, text: "Writing.", activity: "Waiting for your approval")
        let answer = await ask(live)
        #expect(answer["activity"] as? String == "Waiting for your approval")
        #expect(answer["text"] as? String == "Writing.")
    }

    @Test func aSessionThatStoppedWorkingIsNotWorkingAndForgetsItsActivity() async {
        let live = reader.live()
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Executing code")
        _ = await ask(live)
        reader.now = reader.now.addingTimeInterval(1)
        reader.answers[root] = LiveRead(working: false, streaming: .skipped)
        #expect(await ask(live) as NSDictionary == ["working": false, "text": NSNull(), "activity": NSNull()])
        // Working again right away: the activity is asked for afresh.
        reader.now = reader.now.addingTimeInterval(1)
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Running a tool")
        #expect(await ask(live)["activity"] as? String == "Running a tool")
        #expect(reader.asked.last == "activity/text")
    }

    @Test func aDaemonWithoutStreamingIsLeftAloneForTenMinutes() async {
        let live = reader.live()
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Working", streaming: .off)
        _ = await ask(live)
        #expect(reader.asked == ["activity/text"])
        // With no text asked for, the page says "skipped".
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Working", streaming: .skipped)
        reader.now = reader.now.addingTimeInterval(5)
        _ = await ask(live)
        #expect(reader.asked == ["activity/text", "activity/-"])
        reader.now = reader.now.addingTimeInterval(9 * 60)
        _ = await ask(live)
        #expect(reader.asked.last == "activity/-")
        reader.now = reader.now.addingTimeInterval(61)
        _ = await ask(live)
        #expect(reader.asked.last == "activity/text")
    }

    @Test func thePageIsToldWhetherBenchSaysTheSessionWaits() async {
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Executing code")
        let live = reader.live()
        reader.known = [Fixture.session(root, .running)]
        _ = await ask(live)
        reader.now = reader.now.addingTimeInterval(5)
        // A helper asks: Bench's database read has the session waiting.
        reader.known = [Fixture.session(root, .needsInput, reason: .other)]
        _ = await ask(live)
        reader.now = reader.now.addingTimeInterval(5)
        // A session found by browsing counts as Bench knows it too.
        reader.known = []
        _ = await live.json(root, extra: [Fixture.session(root, .needsInput, reason: .question)])
        #expect(reader.mayWait == [false, true, true])
    }

    @Test func aFailedStreamingReadIsNotRemembered() async {
        let live = reader.live()
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Working", streaming: .failed)
        _ = await ask(live)
        reader.now = reader.now.addingTimeInterval(1)
        _ = await ask(live)
        #expect(reader.asked == ["activity/text", "-/text"])
    }

    @Test func aReadThatFailsAnswersFromWhatBenchKnows() async {
        reader.known = [Fixture.session(root, .running)]
        let live = reader.live()
        #expect(await ask(live) as NSDictionary == ["working": true, "text": NSNull(), "activity": NSNull()])
        reader.known = [Fixture.session(root, .finished)]
        #expect(await ask(live)["working"] as? Bool == false)
        reader.known = []
        #expect(await ask(live)["working"] as? Bool == false)
        // A session found by browsing (not in Bench's list) counts too.
        let extra = [Fixture.session(root, .running)]
        let data = await live.json(root, extra: extra)
        #expect((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["working"] as? Bool == true)
    }

    @Test func askersAtTheSameMomentShareOneRead() async {
        reader.answers[root] = LiveRead(working: true, text: "Hello", activity: nil)
        let live = reader.live()
        async let first = live.json(root, extra: [])
        async let second = live.json(root, extra: [])
        let both = await [first, second]
        #expect(both[0] == both[1])
        #expect(reader.asked.count == 1)
    }

    @Test func eachSessionHasItsOwnActivity() async {
        let other = "9f8e7d6c-5b4a-4321-8fed-cba987654321"
        reader.answers[root] = LiveRead(working: true, text: nil, activity: "Executing code")
        reader.answers[other] = LiveRead(working: true, text: nil, activity: "Running a tool")
        let live = reader.live()
        _ = await ask(live)
        let data = await live.json(other, extra: [])
        #expect((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["activity"] as? String == "Running a tool")
        #expect(reader.asked == ["activity/text", "activity/text"])
    }

    @Test func whatIsKeptIsBounded() async {
        let live = reader.live()
        for number in 0..<100 {
            let id = String(format: "00000000-0000-4000-8000-%012d", number)
            reader.answers[id] = LiveRead(working: true, text: nil, activity: "Working")
            _ = await live.json(id, extra: [])
            reader.now = reader.now.addingTimeInterval(0.01)
        }
        #expect(reader.asked.count == 100)
    }
}

// MARK: The route on a session Bench knows

@MainActor
struct RemoteLiveRouteTests {
    @Test func liveIsServedForAKnownSessionAndNotForAStranger() async throws {
        let known = Fixture.session(root, .running, title: "Made-up session")
        let sessions = RemoteSessions(dependencies: .init(
            actionsOn: { true }, known: { [known] }, cardPlan: { _ in nil }, read: { _, _ in nil }, readPlan: { _ in nil },
            write: { _ in nil }, now: { Date() },
            readLive: { id, _, _, _ in id == root ? LiveRead(working: true, text: "Hello", activity: nil) : nil }))
        let data = try #require(await sessions.liveJSON(root))
        #expect(String(decoding: data, as: UTF8.self) == #"{"activity":null,"text":"Hello","working":true}"#)
        #expect(await sessions.liveJSON("9f8e7d6c-5b4a-4321-8fed-cba987654321") == nil)
    }
}
