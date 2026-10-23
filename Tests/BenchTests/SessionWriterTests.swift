// SessionWriterTests.swift — the phone's writer on made-up arguments: the
// very JavaScript the page runs, in JavaScriptCore, against a fake daemon that
// only records what it was sent. Nothing reaches a real daemon.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"

/// `benchBuildWrite` on the arguments Swift passes for `write`, as JSON.
private func build(_ write: RemoteWrite) -> [String: Any]? {
    build(arguments: write.arguments)
}

private func build(arguments: [String: Any]) -> [String: Any]? {
    let script = PageScript(SessionWriterScript.builder)
    guard let data = try? JSONSerialization.data(withJSONObject: arguments),
          let json = script.callJSON("benchBuildWrite", [String(decoding: data, as: UTF8.self)]) else { return nil }
    #expect(script.exception == nil)
    return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
}

/// The body as sorted JSON, for exact comparisons.
private func sorted(_ value: Any?) -> String {
    guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
    return String(decoding: data, as: UTF8.self)
}

struct SessionWriterBuildTests {
    @Test func approveIsAnEmptyBodyToApprovePlan() {
        let write = build(.approvePlan(frame: root))
        #expect(write?["path"] as? String == "/api/frames/\(root)/approve-plan")
        #expect(sorted(write?["body"]) == "{}")
    }

    @Test func anAnswer() {
        let write = build(.answer(frame: root, toolID: "toolu_1", answers: ["Which buffer?": "HEPES", "How many?": "Three"]))
        #expect(write?["path"] as? String == "/api/frames/\(root)/resolve-input")
        #expect(sorted(write?["body"]) == #"{"responses":[{"action":"answer","answers":{"How many?":"Three","Which buffer?":"HEPES"},"tool_id":"toolu_1"}]}"#)
    }

    @Test func aCancel() {
        let write = build(.cancel(frame: root, toolID: "toolu_1"))
        #expect(write?["path"] as? String == "/api/frames/\(root)/resolve-input")
        #expect(sorted(write?["body"]) == #"{"responses":[{"action":"cancel","answers":{},"tool_id":"toolu_1"}]}"#)
    }

    @Test func aMessageNamesTheAgentAndNeverPlanMode() {
        let write = build(.message(frame: root, agent: "made-up-agent", projectID: "proj-1", text: "Try one panel per condition.", intentID: intent))
        #expect(write?["path"] as? String == "/api/request")
        #expect(sorted(write?["body"]) == #"{"input_data":{"request":"Try one panel per condition."},"intent_id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427","plan_mode":false,"project_id":"proj-1","root_frame_id":"0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5","target_agent":"made-up-agent"}"#)
        let noProject = build(.message(frame: root, agent: "a", projectID: nil, text: "x", intentID: intent))
        #expect((noProject?["body"] as? [String: Any])?["project_id"] == nil)
    }

    @Test func aQuestionCalledProtoStaysAKey() {
        let write = build(.answer(frame: root, toolID: "t", answers: ["__proto__": "x"]))
        let answers = (((write?["body"] as? [String: Any])?["responses"] as? [[String: Any]])?.first)?["answers"] as? [String: Any]
        #expect(answers?["__proto__"] as? String == "x")
    }

    private static func refused() -> [RemoteWrite] {
        [
            .approvePlan(frame: "0b7c2f4e"),
            .approvePlan(frame: root.uppercased()),
            .approvePlan(frame: "../../usage/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            .answer(frame: root, toolID: "", answers: ["Q?": "A"]),
            .answer(frame: root, toolID: "t", answers: [:]),
            .answer(frame: root, toolID: "t", answers: ["Q?": ""]),
            .answer(frame: root, toolID: "t", answers: ["Q?": String(repeating: "a", count: 1001)]),
            .answer(frame: root, toolID: "t", answers: Dictionary(uniqueKeysWithValues: (0..<11).map { ("Q\($0)?", "A") })),
            .answer(frame: root, toolID: String(repeating: "t", count: 201), answers: ["Q?": "A"]),
            .message(frame: root, agent: "", projectID: nil, text: "x", intentID: intent),
            .message(frame: root, agent: "a", projectID: nil, text: "", intentID: intent),
            .message(frame: root, agent: "a", projectID: nil, text: String(repeating: "a", count: 4001), intentID: intent),
            .message(frame: root, agent: "a", projectID: nil, text: "x", intentID: "1b4e28ba-2fa1-11d2-883f-0016d3cca427"),
            .message(frame: root, agent: "a", projectID: nil, text: "x", intentID: intent.uppercased()),
            .message(frame: root, agent: "a", projectID: "", text: "x", intentID: intent),
        ]
    }

    @Test(arguments: 0..<15)
    func anythingElseBuildsNothing(_ index: Int) {
        let cases = Self.refused()
        #expect(cases.count == 15)
        guard index < cases.count else { return }
        let script = PageScript(SessionWriterScript.builder)
        let data = try? JSONSerialization.data(withJSONObject: cases[index].arguments)
        #expect(script.callJSON("benchBuildWrite", [data.map { String(decoding: $0, as: UTF8.self) }]) == "null")
    }

    @Test func noPathComesFromTheArguments() {
        var arguments = RemoteWrite.approvePlan(frame: root).arguments
        arguments["kind"] = "discard"
        #expect(build(arguments: arguments) == nil)
        arguments["path"] = "/api/frames/\(root)/discard-plan"
        arguments["kind"] = "approve"
        #expect(build(arguments: arguments)?["path"] as? String == "/api/frames/\(root)/approve-plan")
        var projectNumber = RemoteWrite.message(frame: root, agent: "a", projectID: nil, text: "x", intentID: intent).arguments
        projectNumber["projectId"] = 5
        #expect(build(arguments: projectNumber) == nil)
    }
}

// MARK: What comes back

struct SessionWriterResultTests {
    private func summarize(_ status: Int, _ body: String) -> RemoteWriteResult? {
        let script = PageScript(SessionWriterScript.summarizer)
        script.set("__body", body)
        guard let json = script.evaluate("JSON.stringify(benchSummarizeWrite(\(status), __body))") else { return nil }
        return RemoteWriteResult(object: try? JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    @Test func onlyTheWhitelistedFieldsComeBack() {
        let body = #"{"root_frame_id": "r", "frame_id": "f", "status": "accepted", "remaining_tool_ids": ["a", "b"], "secret": "SECRET"}"#
        #expect(summarize(200, body) == RemoteWriteResult(status: 200, bodyStatus: "accepted", remaining: 2))
        #expect(summarize(200, #"{"status": "message_queued"}"#)?.bodyStatus == "message_queued")
        #expect(summarize(200, #"{"status": "SECRET whatever"}"#) == RemoteWriteResult(status: 200))
        #expect(summarize(403, #"{"code": "csrf_stale"}"#)?.code == "csrf_stale")
        #expect(summarize(400, #"{"code": "has spaces SECRET"}"#)?.code == nil)
        #expect(summarize(500, "<html>SECRET</html>") == RemoteWriteResult(status: 500, isJSON: false))
    }

    @Test func theSentencesBenchReadsBecomeFlags() {
        #expect(summarize(400, #"{"error": "No plan awaiting approval for this frame"}"#)?.noPlanAwaiting == true)
        #expect(summarize(400, #"{"error": "Please answer the pending question(s) before sending"}"#)?.askPending == true)
        #expect(summarize(400, #"{"error": "Frame not awaiting user response"}"#)?.staleInput == true)
        #expect(summarize(400, #"{"error": "No pending request with tool_id x"}"#)?.staleInput == true)
        #expect(summarize(400, #"{"error": "Missing answers for: Q"}"#) == RemoteWriteResult(status: 400))
    }

    @Test func aSummaryOutOfShapeIsRefused() {
        let good: [String: Any] = ["status": 200, "isJSON": true, "code": "", "bodyStatus": "", "remaining": -1,
                                   "noPlanAwaiting": false, "askPending": false, "staleInput": false]
        #expect(RemoteWriteResult(object: good) == RemoteWriteResult(status: 200))
        let cases: [(String, Any)] = [("status", 0), ("status", "200"), ("isJSON", 1), ("code", "a b"),
                                      ("bodyStatus", "done"), ("remaining", -2), ("staleInput", NSNull())]
        for (key, value) in cases {
            var bad = good
            bad[key] = value
            #expect(RemoteWriteResult(object: bad) == nil, "\(key)")
        }
    }

    @Test func approveReadsAsTheCardReadsIt() {
        let accepted = RemoteWriteResult(status: 200, bodyStatus: "accepted").asApproval
        #expect(PlanCheck.outcome(accepted) == .approved)
        #expect(PlanCheck.outcome(RemoteWriteResult(status: 400, code: "plan_already_approved").asApproval) == .approved)
        #expect(PlanCheck.outcome(RemoteWriteResult(status: 400, noPlanAwaiting: true).asApproval) == .changed)
    }
}

// MARK: The in-page body, against a fake daemon

struct SessionWriterPageTests {
    private func run(_ write: RemoteWrite, answers: [String: [PageScript.Answer]],
                     cookie: String = "theme=dark; operon_csrf=secret%20one") -> (result: RemoteWriteResult?, raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let arguments = write.arguments.keys.sorted().map { key -> (String, String) in
            let value = write.arguments[key]!
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            return (key, String(decoding: data, as: UTF8.self))
        }
        let (raw, requests) = script.runPage(SessionWriterScript.body, arguments: arguments, answers: answers, cookie: cookie)
        #expect(script.exception == nil)
        let result = raw.flatMap { try? SessionWriterScript.result(of: Data($0.utf8)) }
        return (result, raw, requests)
    }

    private let approve = "/api/frames/\(root)/approve-plan"

    @Test func aWriteCarriesTheCSRFSecretAndItsBody() {
        let (result, _, requests) = run(.approvePlan(frame: root), answers: [approve: [.init(status: 200, body: #"{"status":"accepted"}"#)]])
        #expect(result == RemoteWriteResult(status: 200, bodyStatus: "accepted"))
        #expect(requests == [PageScript.Request(path: approve, method: "POST", body: "{}", csrf: "secret one", cache: "no-store")])
    }

    @Test func aStaleSecretIsRefreshedAndTriedOnceMore() {
        let stale = PageScript.Answer(status: 403, body: #"{"code":"csrf_stale"}"#)
        let (result, _, requests) = run(.approvePlan(frame: root), answers: [
            approve: [stale, .init(status: 200, body: #"{"status":"accepted"}"#)],
            "/api/csrf": [.init(status: 204, body: "")],
        ])
        #expect(result?.bodyStatus == "accepted")
        #expect(requests.map(\.path) == [approve, "/api/csrf", approve])
        #expect(requests.map(\.method) == ["POST", "GET", "POST"])
        // Only once: a second stale answer comes back as it is.
        let twice = run(.approvePlan(frame: root), answers: [approve: [stale], "/api/csrf": [.init(status: 204, body: "")]])
        #expect(twice.result?.status == 403)
        #expect(twice.requests.map(\.path) == [approve, "/api/csrf", approve])
    }

    @Test func aMessageGoesToRequestAlone() {
        let (result, _, requests) = run(.message(frame: root, agent: "made-up-agent", projectID: nil, text: "Hello", intentID: intent),
                                        answers: ["/api/request": [.init(status: 200, body: #"{"status":"message_queued"}"#)]])
        #expect(result?.bodyStatus == "message_queued")
        #expect(requests.map(\.path) == ["/api/request"])
        let body = requests.first?.body.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
        #expect(body?["target_agent"] as? String == "made-up-agent")
        #expect(body?["plan_mode"] as? Bool == false)
        #expect(body?["intent_id"] as? String == intent)
    }

    @Test func refusedArgumentsSendNothing() {
        let (result, raw, requests) = run(.approvePlan(frame: "short"), answers: [:])
        #expect(result == nil)
        #expect(raw == #"{"refused":true}"#)
        #expect(requests.isEmpty)
    }

    @Test func aRequestWithNoAnswerAtAllIsUnknownNotFailed() {
        // A POST that fails with no response may have reached the daemon first.
        let (result, raw, _) = run(.approvePlan(frame: root), answers: [:])
        #expect(result == nil)
        #expect(raw == #"{"unknown":true}"#)
    }
}
