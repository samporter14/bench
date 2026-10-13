// SessionReaderTests.swift — the phone's session reader on made-up frames.
// The projection is the very JavaScript the page runs, run here in
// JavaScriptCore; Swift's own checks run on what it returns. Every frame and
// message is invented; the fields Bench must never pass on hold "SECRET" so a
// leak shows.
import Foundation
import Testing
@testable import Bench

// MARK: Made-up frames

enum ReaderFixture {
    static let root = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
    /// 2026-10-12T19:30:00Z.
    static let now: Int = 1_791_833_400_000

    static let context = #"""
    {"_sent_user_messages": [
        {"id": "m1", "text": "Started on the made-up buffers.", "attachments": [{"path": "/Users/someone/SECRET-ATTACHMENT.csv"}], "at": 1791833100000}
     ],
     "_plan_version_id": null, "_messages": "SECRET-MESSAGES", "_system": "SECRET-SYSTEM-PROMPT"}
    """#

    static let output = #"""
    {"response": "  Made-up **final** reply.  ", "thinking": "SECRET-THINKING", "_completion_bullets": ["SECRET-BULLET"],
     "pending_input_requests": [{"kind": "network", "tool_id": "t-net", "target": "SECRET-HOST.example", "reason": "SECRET-REASON"}]}
    """#

    static func frame(status: String = "completed", context: String = ReaderFixture.context,
                      output: String = ReaderFixture.output, extra: String = "") -> String {
        """
        {"id": "\(root)", "name": "SECRET-NAME", "task_summary": "SECRET-SUMMARY",
         "input_data": {"request": "SECRET-INPUT"}, "status": "\(status)", "agent_name": "made-up-agent",
         "project_id": "proj-made-up", "status_description": "Fitting   the\\nmodel", "updated_at": \(now),
         "message_count": 9, "queued_user_messages": [{"id": "q1", "text": "SECRET-QUEUED", "queued_at": 1, "frame_id": "x"}],
         "context_data": \(context), "output_data": \(output)\(extra)}
        """
    }

    static let messages = #"""
    [
     {"role": "user", "content": "Compare the made-up buffers.", "_ts": 1791833000000, "_uuid": "u1", "_attachments": [{"path": "SECRET-UPLOAD"}]},
     {"role": "assistant", "content": [{"type": "thinking", "thinking": "SECRET-THINKING"}, {"type": "text", "text": "I'll start with HEPES."},
       {"type": "tool_use", "id": "t1", "name": "bash", "input": {"command": "cat /Users/someone/SECRET-PATH"}}], "_ts": 1791833010000},
     {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "SECRET-RESULT"}], "_ts": 1791833020000},
     {"role": "user", "content": "[System] SECRET-SYSTEM", "_ts": 1791833030000},
     {"role": "user", "content": "SECRET-HARNESS", "_harness_prompt": true, "_ts": 1791833040000},
     {"role": "user", "content": [{"type": "image", "source": {"type": "_disk_ref", "path": "/Users/someone/SECRET-IMAGE.png"}}], "_ts": 1791833050000},
     {"role": "user", "content": "[image: SECRET-IMAGE-TEXT]", "_ts": 1791833060000},
     {"role": "system", "content": "SECRET-ROLE", "_ts": 1791833070000},
     {"role": "assistant", "content": "SECRET-ELIDED", "_oversized_bytes": 3000000, "_ts": 1791833080000},
     {"role": "assistant", "content": [{"type": "server_tool_use", "id": "s1"}, {"type": "web_search_tool_result", "content": "SECRET-WEB"}], "_ts": 1791833090000},
     {"role": "assistant", "content": [{"type": "text", "text": "HEPES kept it soluble longest."}], "_ts": 1791833100000}
    ]
    """#

    static func page(_ rows: String = ReaderFixture.messages) -> String {
        #"{"frame_id": "\#(root)", "from": 0, "total": 11, "messages": \#(rows)}"#
    }

    /// One user row with the given extra fields.
    static func userRow(_ text: String, _ extra: String = "", at: Int = 1791833000000) -> String {
        let quoted = String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        return #"{"role": "user", "content": \#(quoted), "_ts": \#(at)\#(extra)}"#
    }
}

/// The projection run in JavaScriptCore, then checked by Swift.
private func project(_ frame: String, _ page: String? = ReaderFixture.page(), turns: Bool = true)
    -> (json: String?, read: SessionProjection?) {
    let script = PageScript(SessionReaderScript.projection)
    let json = script.callJSON("benchProjectSession", [frame, page, turns ? "true" : "false"])
    #expect(script.exception == nil)
    guard let json, json != "null" else { return (json, nil) }
    let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
    return (json, SessionProjection(object: object))
}

// MARK: The projection

struct SessionProjectionTests {
    @Test func onlyTheSpecsFieldsReachSwift() throws {
        let (json, read) = project(ReaderFixture.frame())
        let text = try #require(json)
        #expect(!text.contains("SECRET"))
        let session = try #require(read)
        #expect(session.status == "completed")
        #expect(session.agentName == "made-up-agent")
        #expect(session.projectID == "proj-made-up")
        #expect(session.statusLine == "Fitting the model")
        #expect(session.reply == "Made-up **final** reply.")
        #expect(session.replyAt == Date(timeIntervalSince1970: 1_791_833_400))
        #expect(session.toYou == [SessionProjection.Note(text: "Started on the made-up buffers.",
                                                         at: Date(timeIntervalSince1970: 1_791_833_100))])
        #expect(session.queued == 1)
        // A network request is not a question, and nothing of it is kept.
        #expect(session.asks.isEmpty)
        #expect(session.question == nil)
        #expect(session.turns?.map(\.role) == [.you, .claude, .claude])
        #expect(session.turns?.map(\.text) == ["Compare the made-up buffers.", "I'll start with HEPES.",
                                                "HEPES kept it soluble longest."])
        #expect(session.turns?.first?.at == Date(timeIntervalSince1970: 1_791_833_000))
    }

    @Test func withoutTurnsOnlyTheFrameIsRead() {
        let read = project(ReaderFixture.frame(), nil, turns: false).read
        #expect(read != nil)
        #expect(read?.turns == nil)
    }

    @Test(arguments: ["_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent", "_from_aside", "_harness_notice"])
    func flaggedUserRowsAreHidden(_ flag: String) {
        let rows = "[\(ReaderFixture.userRow("SECRET flagged", ", \"\(flag)\": true")), \(ReaderFixture.userRow("Shown"))]"
        let read = project(ReaderFixture.frame(), ReaderFixture.page(rows)).read
        #expect(read?.turns?.map(\.text) == ["Shown"])
    }

    @Test(arguments: ["[System] x", "[compute] x", "[Memory] x", "[image: x]", "[document: x]", "  [System] leading space"])
    func userRowsStartingWithAMarkerAreHidden(_ text: String) {
        let rows = "[\(ReaderFixture.userRow(text)), \(ReaderFixture.userRow("Shown"))]"
        let read = project(ReaderFixture.frame(), ReaderFixture.page(rows)).read
        #expect(read?.turns?.map(\.text) == ["Shown"])
    }

    @Test func aFlagThatIsFalseHidesNothing() {
        let rows = "[\(ReaderFixture.userRow("Shown", ", \"_from_agent\": false"))]"
        #expect(project(ReaderFixture.frame(), ReaderFixture.page(rows)).read?.turns?.map(\.text) == ["Shown"])
    }

    @Test func atMostTwelveTurnsOldestFirstEachCut() throws {
        let rows = (0..<20).map { ReaderFixture.userRow("Turn \($0)", at: 1791833000000 + $0 * 1000) }
            + [ReaderFixture.userRow(String(repeating: "é", count: 3000), at: 1791833100000)]
        let read = try #require(project(ReaderFixture.frame(), ReaderFixture.page("[\(rows.joined(separator: ","))]")).read)
        let turns = try #require(read.turns)
        #expect(turns.count == 12)
        #expect(turns.first?.text == "Turn 9")
        #expect(turns.last?.text.unicodeScalars.count == 2000)
        #expect(turns.last?.text.hasSuffix("…") == true)
    }

    @Test func theReplyAndTheLinesAreCut() throws {
        let long = String(repeating: "a", count: 5000)
        let output = #"{"response": "\#(long)"}"#
        let read = try #require(project(ReaderFixture.frame(output: output), nil, turns: false).read)
        #expect(read.reply?.count == 4000)
        let notes = (0..<8).map { #"{"text": "Note \#($0)"}"# }.joined(separator: ",")
        let many = try #require(project(ReaderFixture.frame(context: #"{"_sent_user_messages": [\#(notes)]}"#), nil, turns: false).read)
        #expect(many.toYou.map(\.text) == ["Note 3", "Note 4", "Note 5", "Note 6", "Note 7"])
        #expect(many.toYou.first?.at == nil)
    }

    @Test func nothingWaitingAndNoContextReadsAsEmpty() throws {
        let read = try #require(project(ReaderFixture.frame(context: "null", output: "null"), nil, turns: false).read)
        #expect(read.reply == nil)
        #expect(read.replyAt == nil)
        #expect(read.toYou.isEmpty)
        #expect(read.asks.isEmpty)
        #expect(read.planFrame.versionID == nil)
    }

    // MARK: Shapes that don't match

    @Test(arguments: [
        ReaderFixture.frame(status: "thinking"),
        ReaderFixture.frame(status: "error"),
        ReaderFixture.frame(output: "[]"),
        ReaderFixture.frame(output: "42"),
        ReaderFixture.frame(output: #"{"response": 12}"#),
        ReaderFixture.frame(output: #"{"pending_input_requests": {"kind": "ask"}}"#),
        ReaderFixture.frame(context: #"{"_sent_user_messages": {"text": "x"}}"#),
        ReaderFixture.frame(context: #"{"_sent_user_messages": [{"words": "x"}]}"#),
        ReaderFixture.frame(context: #"{"_sent_user_messages": ["x"]}"#),
        ReaderFixture.frame(extra: #", "queued_user_messages": 3"#),
        #"{"status": 1}"#,
        "[]",
    ])
    func aFrameThatDoesNotMatchIsUnreadable(_ frame: String) {
        #expect(project(frame, nil, turns: false).read == nil)
    }

    @Test(arguments: [
        #"{"frame_id": "x", "from": 0, "messages": []}"#,
        #"{"frame_id": "x", "from": "0", "total": 1, "messages": []}"#,
        #"{"from": 0, "total": 1, "messages": {}}"#,
        ReaderFixture.page(#"[{"role": "user", "content": 12, "_ts": 1791833000000}]"#),
        ReaderFixture.page(#"[{"role": "user", "content": [{"text": "no type"}], "_ts": 1791833000000}]"#),
        ReaderFixture.page(#"[{"role": "user", "content": [{"type": "text", "text": 5}], "_ts": 1791833000000}]"#),
        ReaderFixture.page(#"["row"]"#),
    ])
    func messagesThatDoNotMatchAreUnreadable(_ page: String) {
        #expect(project(ReaderFixture.frame(), page).read == nil)
    }

    /// The daemon's rows can come without `_ts` (seen live in October): the
    /// turn shows, without a time.
    @Test(arguments: [
        ReaderFixture.page(#"[{"role": "user", "content": "No time"}]"#),
        ReaderFixture.page(#"[{"role": "user", "content": "Odd time", "_ts": "yesterday"}]"#),
        ReaderFixture.page(#"[{"role": "assistant", "content": "Too early", "_ts": 12}]"#),
    ])
    func aTurnWithoutAUsableTimeShowsWithoutOne(_ page: String) throws {
        let read = try #require(project(ReaderFixture.frame(), page).read)
        let turn = try #require(read.turns?.first)
        #expect(turn.at == nil)
    }

    @Test func aMissingPageIsUnreadableWhenTurnsAreAskedFor() {
        #expect(project(ReaderFixture.frame(), nil, turns: true).read == nil)
    }

    // MARK: Questions

    private static func ask(_ body: String) -> String {
        #"{"response": null, "pending_input_requests": [\#(body)]}"#
    }

    private static let goodAsk = #"""
    {"kind": "ask", "tool_id": "toolu_made_up", "createdAt": 1,
     "questions": [{"question": "Which made-up buffer first?", "header": "Buffer", "multi_select": false,
                    "options": [{"label": "HEPES", "description": "Most stable", "pros": ["SECRET-PRO"]},
                                {"label": "Tris"}, {"label": "Phosphate", "description": "  Matches\nthe assay "}]},
                   {"question": "How many replicates?", "multi_select": true}]}
    """#

    @Test func aRootQuestionIsProjected() throws {
        let (json, read) = project(ReaderFixture.frame(status: "awaiting_user_response", output: Self.ask(Self.goodAsk)), nil, turns: false)
        #expect(json?.contains("SECRET") == false)
        let ask = try #require(read?.question)
        #expect(ask.toolID == "toolu_made_up")
        #expect(ask.items.count == 2)
        #expect(ask.items[0].question == "Which made-up buffer first?")
        #expect(ask.items[0].header == "Buffer")
        #expect(ask.items[0].multi == false)
        #expect(ask.items[0].options == [
            SessionProjection.Option(label: "HEPES", detail: "Most stable"),
            SessionProjection.Option(label: "Tris", detail: nil),
            SessionProjection.Option(label: "Phosphate", detail: "Matches the assay"),
        ])
        #expect(ask.items[1].header == "")
        #expect(ask.items[1].multi == true)
        #expect(ask.items[1].options.isEmpty)
    }

    @Test(arguments: [
        #"{"kind": "ask", "tool_id": 5, "questions": [{"question": "Q?"}]}"#,
        #"{"kind": "ask", "tool_id": "t", "questions": []}"#,
        #"{"kind": "ask", "tool_id": "t", "questions": [{"question": ""}]}"#,
        #"{"kind": "ask", "tool_id": "t", "questions": [{"question": "Q?", "options": [{"label": ""}]}]}"#,
        #"{"kind": "ask", "tool_id": "t", "questions": [{"question": "Q?", "options": [{"description": "no label"}]}]}"#,
        #"{"kind": "ask", "tool_id": "t", "questions": [{"question": "Q?", "options": "HEPES"}]}"#,
        #"{"kind": "ask", "tool_id": "t", "questions": [{"question": "Q?"}, {"question": "Q?"}]}"#,
    ])
    func aQuestionThatDoesNotMatchIsNotOffered(_ body: String) throws {
        let read = try #require(project(ReaderFixture.frame(status: "awaiting_user_response",
                                                            output: Self.ask("\(body), \(Self.goodAsk)")), nil, turns: false).read)
        // The first is unreadable: the second isn't offered in its place.
        #expect(read.asks.count == 2)
        #expect(read.asks[0] == nil)
        #expect(read.question == nil)
    }

    @Test func aQuestionTooLongToSendBackWholeIsNotOffered() throws {
        let long = String(repeating: "q", count: 2001)
        let body = #"{"kind": "ask", "tool_id": "t", "questions": [{"question": "\#(long)"}]}"#
        let read = try #require(project(ReaderFixture.frame(status: "awaiting_user_response", output: Self.ask(body)), nil, turns: false).read)
        #expect(read.question == nil)
    }

    // MARK: The plan, as Approve reads it

    private static let planFrames: [(String, String?, String?)] = [
        ("awaiting_plan_approval", #"{"_plan_version_id": "ver-001", "_plan_artifact_id": "art-001", "_plan_approved": false}"#, nil),
        ("awaiting_plan_approval", nil, #"{"plan_version_id": "ver-002", "plan_artifact_id": "art-2", "plan_approved": false}"#),
        ("awaiting_plan_approval", #"{"_plan_version_id": "ver-ctx"}"#, #"{"plan_version_id": "ver-out"}"#),
        ("awaiting_plan_approval", #"{"_plan_version_id": 7}"#, #"{"plan_version_id": "ver-out"}"#),
        ("awaiting_plan_approval", #"{"_plan_version_id": "ver-1", "_plan_approved": true}"#, nil),
        ("awaiting_plan_approval", #"{"_plan_version_id": "ver-1", "_plan_approved": "no"}"#, nil),
        ("awaiting_plan_approval", #"{"_plan_version_id": "ver-1"}"#, #"{"plan_approved": 1}"#),
        ("awaiting_plan_approval", #"{"_plan_version_id": "ver/1"}"#, nil),
        ("awaiting_plan_approval", #"{"_plan_version_id": ""}"#, nil),
        ("awaiting_plan_approval", "\"{\\\"_plan_version_id\\\": \\\"ver-text\\\"}\"", nil),
        ("processing", #"{"_plan_version_id": "ver-1"}"#, nil),
    ]

    @Test(arguments: 0..<planFrames.count)
    func thePlanFieldsMatchPlanFrame(_ index: Int) throws {
        let (status, context, output) = Self.planFrames[index]
        let frame = ReaderFixture.frame(status: status, context: context ?? "null", output: output ?? "null")
        let swift = try #require(PlanFrame(json: Data(frame.utf8)))
        let read = try #require(project(frame, nil, turns: false).read)
        #expect(read.planFrame.status == swift.status)
        #expect(read.planFrame.approval == swift.approval)
        #expect(PlanCheck.versionToRead(read.planFrame) == PlanCheck.versionToRead(swift))
    }

    // MARK: Swift's own checks

    private static func valid() -> [String: Any] {
        ["status": "completed", "agentName": "a", "projectId": NSNull(), "statusLine": NSNull(), "reply": NSNull(),
         "replyAt": NSNull(), "toYou": [Any](), "queued": 0, "asks": [Any](),
         "plan": ["version": NSNull(), "artifact": NSNull(), "approval": "no"], "turns": NSNull()]
    }

    @Test func aValidProjectionIsTaken() {
        #expect(SessionProjection(object: Self.valid()) != nil)
    }

    /// Each a field set to something out of shape.
    private static func outOfShape() -> [(String, Any)] {
        [
            ("status", "thinking"),
            ("status", 1),
            ("agentName", 7),
            ("reply", String(repeating: "a", count: 4001)),
            ("reply", ""),
            ("statusLine", String(repeating: "a", count: 201)),
            ("replyAt", 12),
            ("replyAt", "2026-10-12"),
            ("queued", -1),
            ("queued", true),
            ("queued", 1.5),
            ("toYou", [["text": "a"], ["text": "b"], ["text": "c"], ["text": "d"], ["text": "e"], ["text": "f"]]),
            ("toYou", [["words": "a"]]),
            ("asks", [["toolId": "t", "items": [Any]()]]),
            ("plan", ["version": "a/b", "artifact": NSNull(), "approval": "no"]),
            ("plan", ["version": NSNull(), "artifact": NSNull(), "approval": "maybe"]),
            ("turns", Array(repeating: ["role": "you", "at": 1_791_833_000_000, "text": "t"] as [String: Any], count: 13)),
            ("turns", [["role": "system", "at": 1_791_833_000_000, "text": "t"]]),
            ("turns", [["role": "you", "at": "yesterday", "text": "t"]]),
            ("turns", [["role": "you", "at": 1_791_833_000_000, "text": String(repeating: "t", count: 2001)]]),
        ]
    }

    @Test(arguments: 0..<20)
    func anythingOutOfShapeIsUnreadable(_ index: Int) throws {
        let cases = Self.outOfShape()
        #expect(cases.count == 20)
        let (key, value) = try #require(index < cases.count ? cases[index] : nil)
        var object = Self.valid()
        object[key] = value
        #expect(SessionProjection(object: object) == nil)
    }

    @Test func theOutcomeEnvelope() {
        #expect(SessionReaderScript.outcome(of: Data(#"{"outcome":"lost"}"#.utf8)) == .lost)
        #expect(SessionReaderScript.outcome(of: Data(#"{"outcome":"unreadable"}"#.utf8)) == .unreadable)
        #expect(SessionReaderScript.outcome(of: Data(#"{"outcome":"read","session":{}}"#.utf8)) == .unreadable)
        #expect(SessionReaderScript.outcome(of: Data("not json".utf8)) == .unreadable)
    }
}

// MARK: The in-page body, against a fake daemon

struct SessionReaderPageTests {
    private let frame = "/api/frames/\(ReaderFixture.root)?shallow=true"
    private let messages = "/api/frames/\(ReaderFixture.root)/messages?from=-12&limit=12"

    private func run(_ id: String = ReaderFixture.root, turns: Bool = true,
                     answers: [String: [PageScript.Answer]]) -> (outcome: SessionReaderScript.Outcome?, requests: [PageScript.Request]) {
        let script = PageScript()
        let quoted = String(decoding: try! JSONEncoder().encode(id), as: UTF8.self)
        let (result, requests) = script.runPage(SessionReaderScript.body,
                                                arguments: [("frameId", quoted), ("withTurns", turns ? "true" : "false")],
                                                answers: answers)
        #expect(script.exception == nil)
        return (result.map { SessionReaderScript.outcome(of: Data($0.utf8)) }, requests)
    }

    @Test func itMakesExactlyTheTwoGETs() throws {
        let (outcome, requests) = run(answers: [frame: [.init(status: 200, body: ReaderFixture.frame())],
                                                messages: [.init(status: 200, body: ReaderFixture.page())]])
        guard case .read(let read)? = outcome else {
            Issue.record("not read: \(String(describing: outcome))")
            return
        }
        #expect(read.turns?.count == 3)
        #expect(requests.map(\.path) == [frame, messages])
        #expect(requests.allSatisfy { $0.method == "GET" && $0.cache == "no-store" && $0.body == nil })
    }

    @Test func anActionsCheckReadsOnlyTheFrame() {
        let (outcome, requests) = run(turns: false, answers: [frame: [.init(status: 200, body: ReaderFixture.frame())]])
        if case .read(let read)? = outcome { #expect(read.turns == nil) } else { Issue.record("not read") }
        #expect(requests.map(\.path) == [frame])
    }

    @Test func a401IsLostAndAFailureUnreadable() {
        #expect(run(answers: [frame: [.init(status: 401, body: "{}")]]).outcome == .lost)
        #expect(run(answers: [frame: [.init(status: 200, body: ReaderFixture.frame())],
                              messages: [.init(status: 401, body: "{}")]]).outcome == .lost)
        #expect(run(answers: [frame: [.init(status: 500, body: "{}")]]).outcome == .unreadable)
        #expect(run(answers: [frame: [.init(status: 200, body: "<html>")]]).outcome == .unreadable)
        #expect(run(answers: [frame: [.init(status: 200, body: ReaderFixture.frame())],
                              messages: [.init(status: 404, body: "{}")]]).outcome == .unreadable)
        // No answer at all: fetch throws.
        #expect(run(answers: [:]).outcome == .unreadable)
    }

    @Test(arguments: ["0b7c2f4e", "0B7C2F4E-1A2B-4C3D-8E9F-A0B1C2D3E4F5", "../../usage-0000000000000000000000000000", "\(ReaderFixture.root)/x"])
    func anIDThatIsNotOneReadsNothing(_ id: String) {
        let (outcome, requests) = run(id, answers: [:])
        #expect(outcome == .unreadable)
        #expect(requests.isEmpty)
    }
}

// MARK: What `apiGET` may read

struct ReadablePathTests {
    private let id = ReaderFixture.root

    @Test func theCardsTheRingsAndUsageReadsStayAllowed() {
        #expect(WebContainer.isReadablePath("/frames/\(id)?shallow=true"))
        #expect(WebContainer.isReadablePath("/frames/\(id)/token-series"))
        #expect(WebContainer.isReadablePath("/artifacts/versions/ver-001"))
        #expect(WebContainer.isReadablePath("/usage"))
        #expect(WebContainer.isReadablePath("/usage?fresh=1"))
    }

    @Test(arguments: [
        "/frames/\(ReaderFixture.root)/messages?from=-12&limit=12",
        "/frames/\(ReaderFixture.root)/messages",
        "/frames/\(ReaderFixture.root)",
        "/frames/\(ReaderFixture.root)?shallow=false",
        "/frames/\(ReaderFixture.root)/streaming",
        "/frames/\(ReaderFixture.root)/trace-shallow",
        "/frames/0b7c2f4e?shallow=true",
        "/frames/\(ReaderFixture.root.uppercased())?shallow=true",
        "/frames/a/b/token-series",
        "/frames/a%2Fb/token-series",
        "/frames/../usage/token-series",
        "/frames/",
        "/me",
        "/csrf",
    ])
    func everythingElseUnderFramesIsRefused(_ path: String) {
        #expect(!WebContainer.isReadablePath(path))
    }
}
