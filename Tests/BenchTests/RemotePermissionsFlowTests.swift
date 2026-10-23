// RemotePermissionsFlowTests.swift — the permission route end to end on made-up
// sessions: the page's reads against a fake daemon (which paths, when), the
// session JSON, the action route's order of checks, its limit, its setting,
// and the table's routes and costs. Nothing reaches a real daemon or web view.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let helper = "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6"
private let at = "2026-10-12T19:30:00Z"

private func json(_ value: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])) ?? Data(),
           as: UTF8.self)
}

private func ask(_ kind: String, _ fields: [String: Any] = [:], id: String = "req-1", tool: String = "tool-1",
                 mode: String = "live", created: String = at) -> [String: Any] {
    var made: [String: Any] = ["kind": kind, "requestId": id, "tool_id": tool, "createdAt": created, "mode": mode]
    for (key, value) in fields { made[key] = value }
    return made
}

private var python: [String: Any] { ["tool": "python", "code": "print(1)"] }
private var search: [String: Any] {
    ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers", "server_source": "directory", "read_only": true]
}

private func rootFrame(status: String = "processing", _ requests: [[String: Any]]) -> String {
    ReaderFixture.frame(status: status, context: "null", output: json(["pending_input_requests": requests]))
}

private func tree(_ children: [[String: Any]] = []) -> String {
    json(["id": root, "parent_frame_id": NSNull(), "status": "processing", "children": children])
}

private func child(_ requests: [[String: Any]], status: String = "awaiting_user_response") -> [String: Any] {
    ["id": helper, "parent_frame_id": root, "status": status, "output_data": ["pending_input_requests": requests], "children": [Any]()]
}

// MARK: The page's reads

struct PermissionPageReadTests {
    private let frame = "/api/frames/\(root)?shallow=true"
    private let messages = "/api/frames/\(root)/messages?from=-12&limit=12"
    private let trace = "/api/frames/\(root)/trace-shallow?include_messages=false"

    private func run(turns: Bool = true, answers: [String: [PageScript.Answer]]) -> (outcome: SessionReaderScript.Outcome?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (result, requests) = script.runPage(SessionReaderScript.body,
                                                arguments: [("frameId", json(root)), ("withTurns", turns ? "true" : "false")],
                                                answers: answers)
        #expect(script.exception == nil)
        return (result.map { SessionReaderScript.outcome(of: Data($0.utf8)) }, requests)
    }

    private func ok(_ body: String) -> [PageScript.Answer] { [.init(status: 200, body: body)] }

    @Test func aWorkingSessionAlsoReadsItsHelpers() throws {
        let (outcome, requests) = run(answers: [frame: ok(rootFrame([])), messages: ok(ReaderFixture.page()),
                                                trace: ok(tree([child([ask("mcp_tool", search, mode: "parked")])]))])
        guard case .read(let read)? = outcome else {
            Issue.record("not read: \(String(describing: outcome))")
            return
        }
        #expect(read.permission?.frame == helper)
        #expect(read.permission?.chain == [helper, root])
        #expect(read.permission?.kind == "mcp_tool")
        #expect(requests.map(\.path) == [frame, messages, trace])
        #expect(requests.allSatisfy { $0.method == "GET" && $0.cache == "no-store" && $0.body == nil })
    }

    @Test(arguments: ["processing", "awaiting_user_response"])
    func theTraceIsReadOnlyWhereARequestMayWait(_ status: String) {
        let (_, requests) = run(answers: [frame: ok(rootFrame(status: status, [])), messages: ok(ReaderFixture.page()), trace: ok(tree())])
        #expect(requests.map(\.path) == [frame, messages, trace])
    }

    @Test(arguments: ["completed", "success", "failed", "cancelled", "replaced", "awaiting_plan_approval"])
    func anyOtherStatusReadsNoTrace(_ status: String) {
        let (_, requests) = run(answers: [frame: ok(rootFrame(status: status, [])), messages: ok(ReaderFixture.page())])
        #expect(requests.map(\.path) == [frame, messages])
    }

    @Test func anActionsCheckOfThePlanOrAMessageReadsOnlyTheFrame() {
        let (outcome, requests) = run(turns: false, answers: [frame: ok(rootFrame([ask("network", ["target": "genomes.example.org"])]))])
        if case .read(let read)? = outcome { #expect(read.permission == nil) } else { Issue.record("not read") }
        #expect(requests.map(\.path) == [frame])
    }

    @Test func theRootsOwnRequestIsFoundEvenWhenTheTraceHasNoChildren() {
        let (outcome, _) = run(answers: [frame: ok(rootFrame([ask("local_exec", python)])), messages: ok(ReaderFixture.page()), trace: ok(tree())])
        if case .read(let read)? = outcome {
            #expect(read.permission?.kind == "local_exec")
            #expect(read.permission?.frame == root)
            #expect(read.permission?.helper == false)
        } else {
            Issue.record("not read")
        }
    }

    @Test(arguments: [(404, "{}"), (500, "{}"), (200, "<html>"), (200, "[]"), (200, #"{"id": "x", "children": []}"#)])
    func aTraceThatFailsLeavesTheSessionReadableWithoutAPermission(_ status: Int, _ body: String) {
        let (outcome, requests) = run(answers: [frame: ok(rootFrame([ask("local_exec", python)])), messages: ok(ReaderFixture.page()),
                                                trace: [.init(status: status, body: body)]])
        if case .read(let read)? = outcome {
            #expect(read.permission == nil)
            #expect(read.turns?.count == 3)
        } else {
            Issue.record("not read: \(String(describing: outcome))")
        }
        #expect(requests.map(\.path) == [frame, messages, trace])
        // No answer at all (fetch throws): the same.
        let none = run(answers: [frame: ok(rootFrame([])), messages: ok(ReaderFixture.page())])
        if case .read(let read)? = none.outcome { #expect(read.permission == nil) } else { Issue.record("not read") }
    }

    @Test func aTraceThatIsRefusedAsNotSignedInIsLost() {
        let (outcome, _) = run(answers: [frame: ok(rootFrame([])), messages: ok(ReaderFixture.page()), trace: [.init(status: 401, body: "{}")]])
        #expect(outcome == .lost)
    }

    @Test func nothingOfTheFramesOrTheirTextsReachesSwift() {
        let script = PageScript()
        let output = json(["pending_input_requests": [ask("network", ["target": "genomes.example.org", "reason": "SECRET-REASON"])],
                           "response": "SECRET-RESPONSE", "thinking": "SECRET-THINKING"])
        let (result, _) = script.runPage(SessionReaderScript.body, arguments: [("frameId", json(root)), ("withTurns", "true")], answers: [
            frame: ok(ReaderFixture.frame(status: "processing", context: "null", output: output)),
            messages: ok(ReaderFixture.page()),
            trace: ok(tree([child([ask("host", ["target": "/Users/made-up/data", "warning": "SECRET-WARNING"], created: "2026-10-12T20:00:00Z")])])),
        ])
        let text = result ?? ""
        // The reply the page returns is what Swift receives: the reader's own markers
        // (reply text and the like) are accounted for by SessionReaderTests; here only
        // what the permission adds.
        #expect(text.contains("genomes.example.org"))
        #expect(!text.contains("SECRET-REASON") && !text.contains("SECRET-WARNING") && !text.contains("/Users/made-up/data"))
        #expect(!text.contains("SECRET-THINKING"))
    }

    @Test func theTracePathIsTheAllowlistedOneAndNoOther() {
        let script = PageScript(PermissionScript.paths)
        #expect(script.callJSON("benchReadPath", ["\"trace\"", json(root)]) == "\"\(trace)\"")
        #expect(script.callJSON("benchReadPath", ["\"streaming\"", json(root)]) == "\"/api/frames/\(root)/streaming\"")
        for (op, id) in [("trace", "0b7c2f4e"), ("trace", root.uppercased()), ("trace", "../../usage"), ("messages", root),
                         ("trace?focus_frame_id=x", root), ("", root)] {
            #expect(script.callJSON("benchReadPath", [json(op), json(id)]) == "null", Comment(rawValue: "\(op) \(id)"))
        }
        #expect(script.callJSON("benchReadPath", ["\"trace\"", "null"]) == "null")
        // Swift's mirror says the same.
        #expect(PermissionPaths.trace(root) == "/api/frames/\(root)/trace-shallow?include_messages=false")
        #expect(PermissionPaths.streaming(root) == "/api/frames/\(root)/streaming")
        #expect(PermissionPaths.trace("0b7c2f4e") == nil)
        #expect(PermissionPaths.isAllowed("/api/frames/\(root)/streaming"))
        #expect(PermissionPaths.isAllowed("/api/frames/\(root)/trace-shallow?include_messages=false"))
        for path in ["/api/frames/\(root)/trace-shallow", "/api/frames/\(root)/trace-shallow?include_messages=true",
                     "/api/frames/\(root)/streaming?x=1", "/api/frames/\(root)/streaming/", "/api/frames/0b7c2f4e/streaming",
                     "/api/frames/\(root.uppercased())/streaming", "/frames/\(root)/streaming", "/api/frames/\(root)/messages",
                     "/api/frames/\(root)/streaming-batch", "/api/frames/../\(root)/streaming"] {
            #expect(!PermissionPaths.isAllowed(path), Comment(rawValue: path))
        }
    }

    @Test func apiGETStillRefusesBoth() {
        // The card's and the rings' reader is unchanged: neither path is readable there.
        #expect(!WebContainer.isReadablePath("/frames/\(root)/streaming"))
        #expect(!WebContainer.isReadablePath("/frames/\(root)/trace-shallow"))
        #expect(!WebContainer.isReadablePath("/frames/\(root)/trace-shallow?include_messages=false"))
    }
}

// MARK: The route

@MainActor
private final class PermissionPage {
    var reads: [String: SessionProjection] = [:]
    var reply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted")
    var actionsOn = true
    var known: [SessionStatus] = [Fixture.session(root, .running, title: "Made-up session")]
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var readLog: [String] = []
    private(set) var writes: [RemoteWrite] = []

    func sessions() -> RemoteSessions {
        RemoteSessions(dependencies: RemoteSessions.Dependencies(
            actionsOn: { [self] in self.actionsOn },
            known: { [self] in self.known },
            cardPlan: { _ in nil },
            read: { [self] id, turns in
                self.readLog.append(turns ? "turns" : "frame")
                await Task.yield()
                guard let read = self.reads[id] else { return nil }
                return turns ? read : read.withoutTurns
            },
            readPlan: { _ in nil },
            write: { [self] write in
                self.writes.append(write)
                return self.reply
            },
            now: { [self] in self.now }))
    }
}

private func body(_ text: String) -> Data { Data(text.utf8) }

private func decode(_ data: Data?) -> [String: Any] {
    data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

private func read(_ permission: PermissionRequest?, status: String = "processing") -> SessionProjection {
    SessionProjection(status: status, agentName: "made-up-agent", projectID: "proj-1", turns: [], permission: permission)
}

private let exec = PermissionRequest(requestID: "req-1", toolID: "tool-1", kind: "local_exec", frame: root, tool: "python", code: "print(1)")
private let net = PermissionRequest(requestID: "req-2", toolID: "tool-2", mode: "parked", kind: "network", frame: root, target: "genomes.example.org")
private let viaHelper = PermissionRequest(requestID: "req-3", toolID: "tool-3", mode: "parked", kind: "mcp_tool", frame: helper, chain: [helper, root],
                                          tool: "search_papers", server: "Paper search", source: "directory", readOnly: true)

@MainActor
struct PermissionRouteTests {
    private let page = PermissionPage()

    private func act(_ text: String, device: String = "d") async -> RemoteActionReply {
        await page.sessions().act(.permission, session: root, device: device, body: body(text))
    }

    // MARK: Reading

    @Test func aCodeCellWaitingIsShownWithItsCode() async throws {
        page.reads[root] = read(exec)
        let session = decode(await page.sessions().sessionJSON(root))
        #expect(session["version"] as? Int == 2)
        let permission = try #require(session["permission"] as? [String: Any])
        #expect(permission as NSDictionary == [
            "id": "req-1", "kind": "local_exec", "title": "Run Python code", "detail": "Claude wants to run this code on your Mac.",
            "code": "print(1)", "helper": false, "canAllow": true, "canDeny": true, "why": NSNull(),
        ])
    }

    @Test func aHelpersRequestSaysSo() async throws {
        page.reads[root] = read(viaHelper)
        let session = decode(await page.sessions().sessionJSON(root))
        let permission = try #require(session["permission"] as? [String: Any])
        #expect(permission as NSDictionary == [
            "id": "req-3", "kind": "mcp_tool", "title": "Use search_papers from Paper search", "detail": "The tool says it only reads.",
            "code": NSNull(), "helper": true, "canAllow": true, "canDeny": true, "why": NSNull(),
        ])
    }

    @Test func aNetworkRequestCanOnlyBeDenied() async throws {
        page.reads[root] = read(net, status: "awaiting_user_response")
        let permission = try #require(decode(await page.sessions().sessionJSON(root))["permission"] as? [String: Any])
        #expect(permission["canAllow"] as? Bool == false)
        #expect(permission["canDeny"] as? Bool == true)
        #expect(permission["title"] as? String == "Wants to reach genomes.example.org")
        #expect(permission["why"] as? String == "Allowing this from your phone would give lasting access. Open it on your Mac.")
        #expect(permission["code"] is NSNull)
    }

    @Test func nothingWaitingIsNull() async {
        page.reads[root] = read(nil)
        let session = decode(await page.sessions().sessionJSON(root))
        #expect(session["permission"] is NSNull)
        // Unreadable: the same.
        page.reads[root] = nil
        let unreadable = decode(await RemoteSessions(dependencies: .init(
            actionsOn: { true }, known: { [Fixture.session(root, .running)] }, cardPlan: { _ in nil },
            read: { _, _ in nil }, readPlan: { _ in nil }, write: { _ in nil }, now: { Date() })).sessionJSON(root))
        #expect(unreadable["permission"] is NSNull)
    }

    @Test func withActionsOffThePhoneStillHearsWhatWaitsButCanDoNothing() async throws {
        page.actionsOn = false
        page.reads[root] = read(exec)
        let permission = try #require(decode(await page.sessions().sessionJSON(root))["permission"] as? [String: Any])
        #expect(permission["canAllow"] as? Bool == false)
        #expect(permission["canDeny"] as? Bool == false)
        #expect(permission["why"] as? String == "Actions are off in Capsid's Settings")
        #expect(permission["title"] as? String == "Run Python code")
    }

    // MARK: Answering

    @Test func allowReadsTheTraceToo_thenWritesToTheRootWithNoScope() async {
        page.reads[root] = read(exec)
        let reply = await act(#"{"id":"req-1","decision":"allow"}"#)
        #expect(reply.status == 200)
        let answer = decode(reply.body)
        #expect(answer["result"] as? String == "allowed")
        #expect(answer["sentence"] as? String == "Allowed once. Claude is carrying on.")
        // A permission's check is a full read: the helpers' frames come with it.
        #expect(page.readLog == ["turns"])
        #expect(page.writes == [.permission(frame: root, requestID: "req-1", toolID: "tool-1", allow: true)])
    }

    @Test func aHelpersAnswerGoesToTheHelpersFrame() async {
        page.reads[root] = read(viaHelper)
        let reply = await act(#"{"id":"req-3","decision":"deny"}"#)
        #expect(decode(reply.body)["result"] as? String == "denied")
        #expect(page.writes == [.permission(frame: helper, requestID: "req-3", toolID: "tool-3", allow: false)])
    }

    @Test func aRequestThatChangedWritesNothing() async {
        page.reads[root] = read(net, status: "awaiting_user_response")
        let reply = await act(#"{"id":"req-1","decision":"allow"}"#)
        #expect(decode(reply.body)["result"] as? String == "changed")
        #expect(page.writes.isEmpty)
        page.reads[root] = read(nil)
        #expect(decode(await act(#"{"id":"req-1","decision":"deny"}"#).body)["result"] as? String == "changed")
        #expect(page.writes.isEmpty)
    }

    @Test func aKindThatChangedWritesNothing() async {
        page.reads[root] = read(exec)
        let reply = await act(#"{"id":"req-1","decision":"allow","kind":"network"}"#)
        #expect(decode(reply.body)["result"] as? String == "changed")
        #expect(page.writes.isEmpty)
    }

    @Test func anAllowThatIsNotAllowedWritesNothing() async {
        page.reads[root] = read(net, status: "awaiting_user_response")
        let reply = await act(#"{"id":"req-2","decision":"allow"}"#)
        #expect(reply.status == 200)
        #expect(decode(reply.body)["result"] as? String == "unavailable")
        #expect(decode(reply.body)["sentence"] as? String == "Allowing this from your phone would give lasting access. Open it on your Mac.")
        #expect(page.writes.isEmpty)
        // A deny of the same request goes.
        #expect(decode(await act(#"{"id":"req-2","decision":"deny"}"#).body)["result"] as? String == "denied")
        #expect(page.writes == [.permission(frame: root, requestID: "req-2", toolID: "tool-2", allow: false)])
    }

    @Test func aHolderOutsideThisSessionIsChangedAndWritesNothing() async {
        let stray = PermissionRequest(requestID: "req-3", toolID: "tool-3", mode: "parked", kind: "mcp_tool", frame: helper,
                                      chain: [helper, "2d9e4a6b-3c4d-4e5f-8a1b-c2d3e4f5a6b7"], tool: "t", server: "s", source: "directory", readOnly: true)
        page.reads[root] = read(stray)
        #expect(decode(await act(#"{"id":"req-3","decision":"allow"}"#).body)["result"] as? String == "changed")
        #expect(page.writes.isEmpty)
    }

    @Test func anUnreadableSessionWritesNothing() async {
        let reply = await act(#"{"id":"req-1","decision":"allow"}"#)
        #expect(decode(reply.body) as NSDictionary == ["result": "unavailable", "sentence": "Couldn't do that from here. Open it on your Mac."])
        #expect(page.writes.isEmpty)
    }

    @Test(arguments: [
        (RemoteWriteResult(status: 200, bodyStatus: "buffered"), "allowed"),
        (RemoteWriteResult(status: 200, bodyStatus: "partial"), "allowed"),
        (RemoteWriteResult(status: 200, bodyStatus: "already_resolved"), "changed"),
        (RemoteWriteResult(status: 400, staleInput: true), "changed"),
        (RemoteWriteResult(status: 400), "unavailable"),
        (RemoteWriteResult(status: 500), "unavailable"),
    ])
    func theDaemonsReplyIsMapped(_ reply: RemoteWriteResult, _ expected: String) async {
        page.reads[root] = read(exec)
        page.reply = reply
        #expect(decode(await act(#"{"id":"req-1","decision":"allow"}"#).body)["result"] as? String == expected)
    }

    @Test func noReplyIsUnavailable() async {
        page.reads[root] = read(exec)
        page.reply = nil
        #expect(decode(await act(#"{"id":"req-1","decision":"allow"}"#).body)["result"] as? String == "unavailable")
    }

    @Test func actionsOffIs403AndReadsNothing() async {
        page.actionsOn = false
        page.reads[root] = read(exec)
        let reply = await act(#"{"id":"req-1","decision":"allow"}"#)
        #expect(reply.status == 403)
        #expect(decode(reply.body)["sentence"] as? String == "Actions are off in Capsid's Settings")
        #expect(page.readLog.isEmpty)
        #expect(page.writes.isEmpty)
    }

    @Test func itCountsTowardTheSixAMinute() async {
        let sessions = page.sessions()
        for _ in 0..<6 {
            #expect(await sessions.act(.permission, session: root, device: "d", body: body("{}")).status == 400)
        }
        #expect(await sessions.act(.permission, session: root, device: "d", body: body(#"{"id":"req-1","decision":"allow"}"#)).status == 429)
        // The same six are shared with the other actions.
        let other = page.sessions()
        for _ in 0..<5 { _ = await other.act(.message, session: root, device: "e", body: body("{}")) }
        #expect(await other.act(.permission, session: root, device: "e", body: body("{}")).status == 400)
        #expect(await other.act(.permission, session: root, device: "e", body: body("{}")).status == 429)
    }

    @Test func anUnknownSessionIs404AndABadBody400() async {
        let sessions = page.sessions()
        let stranger = "9f8e7d6c-5b4a-4321-8fed-cba987654321"
        #expect(await sessions.act(.permission, session: stranger, device: "d", body: body(#"{"id":"req-1","decision":"allow"}"#)).status == 404)
        #expect(await sessions.act(.permission, session: root, device: "d", body: body(#"{"id":"req-1","decision":"always"}"#)).status == 400)
        #expect(page.readLog.isEmpty)
    }

    @Test func anActionDropsWhatWasHeld() async {
        page.reads[root] = read(exec)
        let sessions = page.sessions()
        _ = await sessions.sessionJSON(root)
        _ = await sessions.act(.permission, session: root, device: "d", body: body(#"{"id":"req-1","decision":"allow"}"#))
        _ = await sessions.sessionJSON(root)
        #expect(page.readLog == ["turns", "turns", "turns"])
    }
}

// MARK: What the session may do while it waits

struct PermissionCanTests {
    @Test func aParkedRequestIsNotItsQuestion() {
        let parked = read(net, status: "awaiting_user_response")
        let can = RemoteCan.make(read: parked, plan: nil, actionsOn: true)
        #expect(can == RemoteAPI.Can(approve: false, answer: false, message: nil, why: "Answer its request first"))
        // A question stays a question; no request at all stays as it was.
        let question = SessionProjection.Ask(toolID: "t", items: [SessionProjection.Question(question: "Q?", header: "", multi: false, options: [])])
        let both = SessionProjection(status: "awaiting_user_response", agentName: "a", projectID: "p", asks: [question], permission: net)
        #expect(RemoteCan.make(read: both, plan: nil, actionsOn: true).why == "Answer its question first")
        #expect(RemoteCan.make(read: read(nil, status: "awaiting_user_response"), plan: nil, actionsOn: true).why == "Answer its question first")
        // A live request leaves the root working: messages queue as before.
        #expect(RemoteCan.make(read: read(exec), plan: nil, actionsOn: true).message == "queue")
    }
}

// MARK: The table's routes

struct PermissionRouteTableTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let policy = RemotePolicy.tailnet(dnsName: host, login: "pat@example.com")
    private static let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    private func request(_ method: String, _ target: String, body: Data = Data()) -> RemoteRequest {
        var headers: [String: [String]] = [
            "host": ["\(Self.host):8443"], "tailscale-user-login": ["pat@example.com"],
            "cookie": ["bench_device=\(String(repeating: "A", count: 43))"],
        ]
        if method == "POST" {
            headers["content-type"] = ["application/json"]
            headers["origin"] = ["https://\(Self.host):8443"]
            headers["x-bench"] = ["1"]
        }
        return RemoteRequest(method: method, target: target, headers: headers, body: body)
    }

    private func status(_ request: RemoteRequest) -> Int {
        switch RemoteCheck.evaluate(request, policy: Self.policy) {
        case .reject(let status, _, _): status
        case .accept: 200
        }
    }

    @Test func permissionIsAPostRouteThatNeedsAToken() {
        let path = "/api/sessions/\(Self.id)/permission"
        #expect(RemoteRoute.match(method: "POST", path: Substring(path)) == .found(.action(.permission, Self.id)))
        #expect(RemoteRoute.action(.permission, Self.id).pattern == "/api/sessions/<id>/permission")
        #expect(RemoteRoute.action(.permission, Self.id).needsToken)
        #expect(status(request("POST", path)) == 200)
        #expect(status(request("GET", path)) == 405)
        #expect(status(request("POST", "/api/sessions/\(Self.id)/Permission")) == 404)
        #expect(status(request("POST", "/api/sessions/\(Self.id)/permission/")) == 404)
        #expect(status(request("POST", "/api/sessions/0f8fad5b/permission")) == 404)
        #expect(!RemoteRoute.action(.permission, Self.id).pattern.contains(Self.id))
        // A small body: the 8 KB every route but a message takes.
        #expect(status(request("POST", path, body: Data(repeating: 0x20, count: 8 * 1024 + 1))) == 413)
    }

    @Test func liveIsAGetRouteThatNeedsATokenAndCostsOne() {
        let path = "/api/sessions/\(Self.id)/live"
        #expect(RemoteRoute.match(method: "GET", path: Substring(path)) == .found(.live(Self.id)))
        #expect(RemoteRoute.match(method: "POST", path: Substring(path)) == .wrongMethod)
        #expect(RemoteRoute.live(Self.id).pattern == "/api/sessions/<id>/live")
        #expect(!RemoteRoute.live(Self.id).pattern.contains(Self.id))
        #expect(RemoteRoute.live(Self.id).needsToken)
        #expect(RemoteRoute.live(Self.id).cost == 1)
        #expect(RemoteRoute.live(Self.id).method == "GET")
        #expect(!RemoteRoute.live(Self.id).isTransfer)
        #expect(status(request("GET", path)) == 200)
        #expect(status(request("POST", path)) == 405)
        #expect(status(request("GET", path + "?x=1")) == 200)
        #expect(status(request("GET", "/api/sessions/\(Self.id)/live/")) == 404)
        #expect(status(request("GET", "/api/sessions/\(Self.id)/Live")) == 404)
        #expect(status(request("GET", "/api/sessions/0f8fad5b/live")) == 404)
        var cookieless = request("GET", path)
        cookieless = RemoteRequest(method: "GET", target: path, headers: cookieless.headers.filter { $0.key != "cookie" })
        #expect(status(cookieless) == 401)
    }

    @Test func aPollEveryOneAndAHalfSecondsFitsTheBucket() {
        var budgets = DeviceBudgets()
        let start = Date(timeIntervalSince1970: 1_791_833_400)
        // 40 polls a minute from a phone, cost 1 each, the bucket refills at two a second: never refused.
        for poll in 0..<400 {
            let verdict = budgets.admit(.live(Self.id), device: "phone", at: start.addingTimeInterval(Double(poll) * 1.5))
            #expect(verdict == .go(transfer: false))
        }
    }
}

// MARK: `--demo remote`

@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_791_833_400)
}

@MainActor
struct PermissionDemoTests {
    private let clock = Clock()

    private func demo() -> ([String: SessionStatus], RemoteSessions) {
        func make(_ suffix: String, _ title: String, _ state: SessionState, _ reason: WaitingReason? = nil) -> SessionStatus {
            Fixture.session(DemoLive.id(suffix), state, reason: reason, title: title)
        }
        let list = [make("d4", "Literature sweep", .running), make("d5", "Plate layout", .running),
                    make("d8", "Peak calling script", .needsInput, .other), make("d9", "Reference genome download", .needsInput, .web),
                    make("da", "Citation check", .needsInput, .tool), make("d6", "Primer design", .finished)]
        let clock = clock
        let sessions = RemoteSessions.demo(reads: Demo.remoteReads(list), known: { list }, cardPlan: { _ in nil }, now: { clock.now })
        return (Dictionary(uniqueKeysWithValues: list.map { ($0.title, $0) }), sessions)
    }

    private func permission(_ sessions: RemoteSessions, _ id: String) async -> [String: Any]? {
        guard let data = await sessions.sessionJSON(id),
              let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return session["permission"] as? [String: Any]
    }

    @Test func eachMadeUpSessionAsksSomethingDifferent() async throws {
        let (list, sessions) = demo()
        let exec = try #require(await permission(sessions, list["Peak calling script"]!.id))
        #expect(exec["kind"] as? String == "local_exec")
        #expect(exec["title"] as? String == "Run Python code")
        #expect((exec["code"] as? String)?.contains("pandas") == true)
        #expect(exec["canAllow"] as? Bool == true && exec["canDeny"] as? Bool == true && exec["helper"] as? Bool == false)
        let network = try #require(await permission(sessions, list["Reference genome download"]!.id))
        #expect(network["kind"] as? String == "network")
        #expect(network["canAllow"] as? Bool == false && network["canDeny"] as? Bool == true)
        #expect(network["why"] as? String != nil)
        let helper = try #require(await permission(sessions, list["Citation check"]!.id))
        #expect(helper["helper"] as? Bool == true)
        #expect(helper["kind"] as? String == "mcp_tool")
        #expect(helper["canAllow"] as? Bool == true)
        #expect(await permission(sessions, list["Primer design"]!.id) == nil)
        #expect(await permission(sessions, list["Literature sweep"]!.id) == nil)
    }

    @Test func theDemosAnswersAreMadeUpAndTheRequestLeavesTheScreen() async throws {
        let (list, sessions) = demo()
        let id = list["Peak calling script"]!.id
        let allowed = await sessions.act(.permission, session: id, device: "d", body: body(#"{"id":"demo-request-exec","decision":"allow"}"#))
        #expect(decode(allowed.body)["result"] as? String == "allowed")
        #expect(await permission(sessions, id) == nil)
        // The others are untouched.
        #expect(await permission(sessions, list["Reference genome download"]!.id) != nil)
        // The network request: an allow is refused, a deny goes.
        let netID = list["Reference genome download"]!.id
        let refused = await sessions.act(.permission, session: netID, device: "d", body: body(#"{"id":"demo-request-net","decision":"allow"}"#))
        #expect(decode(refused.body)["result"] as? String == "unavailable")
        #expect(await permission(sessions, netID) != nil)
        let denied = await sessions.act(.permission, session: netID, device: "d", body: body(#"{"id":"demo-request-net","decision":"deny"}"#))
        #expect(decode(denied.body)["result"] as? String == "denied")
        #expect(await permission(sessions, netID) == nil)
        // The helper's: answered through its own frame, and gone.
        let helperID = list["Citation check"]!.id
        let helper = await sessions.act(.permission, session: helperID, device: "d", body: body(#"{"id":"demo-request-mcp","decision":"allow","kind":"mcp_tool"}"#))
        #expect(decode(helper.body)["result"] as? String == "allowed")
        #expect(await permission(sessions, helperID) == nil)
    }

    private func live(_ sessions: RemoteSessions, _ id: String) async -> [String: Any] {
        clock.now = clock.now.addingTimeInterval(1.5)
        return decode(await sessions.liveJSON(id))
    }

    @Test func theWorkingSessionsTextGrowsOnEachReadThenResetsAfterARunningStretch() async {
        let (list, sessions) = demo()
        let id = list["Literature sweep"]!.id
        var lengths: [Int] = []
        var activities: [String?] = []
        var steps = 0
        // Until the text has gone through a gap and come back.
        while steps < 60 {
            let answer = await live(sessions, id)
            #expect(answer["working"] as? Bool == true)
            lengths.append((answer["text"] as? String)?.count ?? 0)
            activities.append(answer["activity"] as? String)
            steps += 1
            if lengths.count > 3, lengths.last == DemoLive.stride, lengths.contains(0) { break }
        }
        let first = lengths.prefix { $0 > 0 }
        #expect(first.count >= 5)
        #expect(Array(first) == (1...first.count).map { $0 * DemoLive.stride }.map { min($0, DemoLive.passage.count) })
        // The whole passage, then the gap: no text, and the activity says what runs.
        #expect(lengths[first.count..<(first.count + DemoLive.gap)].allSatisfy { $0 == 0 })
        #expect(activities[first.count..<(first.count + DemoLive.gap)].contains("Executing code"))
        // Then it starts over.
        #expect(lengths[first.count + DemoLive.gap] == DemoLive.stride)
        // While text shows, the activity doesn't.
        #expect(activities[..<first.count].allSatisfy { $0 == nil })
    }

    @Test func theOtherWorkingSessionIsAlwaysRunningCode() async {
        let (list, sessions) = demo()
        let id = list["Plate layout"]!.id
        for _ in 0..<3 {
            let answer = await live(sessions, id)
            #expect(answer["working"] as? Bool == true)
            #expect(answer["text"] is NSNull)
            #expect(answer["activity"] as? String == "Executing code")
        }
    }

    @Test func aSessionThatDoesNotWorkReadsNothingWorking() async {
        let (list, sessions) = demo()
        let answer = await live(sessions, list["Primer design"]!.id)
        #expect(answer["working"] as? Bool == false)
        #expect(answer["text"] is NSNull)
    }

    @Test func aStrangerIs404() async {
        let (_, sessions) = demo()
        #expect(await sessions.liveJSON("9f8e7d6c-5b4a-4321-8fed-cba987654321") == nil)
    }
}
