// RemotePhase2Tests.swift — the action routes in the server's table, their
// body limits, and `/api/sessions/<id>` version 2 as the JSON the phone reads.
// Made-up requests and sessions; nothing listens.
import Foundation
import Testing
@testable import Bench

struct RemoteActionRouteTests {
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

    @Test func theThreeActionsAreRoutesThatNeedAToken() {
        for action in RemoteAction.allCases {
            let path = "/api/sessions/\(Self.id)/\(action.rawValue)"
            #expect(RemoteRoute.match(method: "POST", path: Substring(path)) == .found(.action(action, Self.id)))
            #expect(RemoteRoute.action(action, Self.id).pattern == "/api/sessions/<id>/\(action.rawValue)")
            #expect(RemoteRoute.action(action, Self.id).needsToken)
            #expect(status(request("POST", path)) == 200)
            #expect(status(request("GET", path)) == 405)
        }
        #expect(status(request("POST", "/api/sessions/\(Self.id)/discard")) == 404)
        #expect(status(request("POST", "/api/sessions/\(Self.id)/Approve")) == 404)
        #expect(status(request("POST", "/api/sessions/\(Self.id)/approve/")) == 404)
        #expect(status(request("POST", "/api/sessions/0f8fad5b/approve")) == 404)
        // The log names the pattern, never the id.
        #expect(!RemoteRoute.action(.message, Self.id).pattern.contains(Self.id))
    }

    @Test func aMessageMayCarrySixteenKilobytesAndNothingElseMoreThanEight() {
        let message = "/api/sessions/\(Self.id)/message", answer = "/api/sessions/\(Self.id)/answer"
        #expect(status(request("POST", message, body: Data(repeating: 0x20, count: 16 * 1024))) == 200)
        #expect(status(request("POST", message, body: Data(repeating: 0x20, count: 16 * 1024 + 1))) == 413)
        #expect(status(request("POST", answer, body: Data(repeating: 0x20, count: 8 * 1024 + 1))) == 413)
        #expect(status(request("POST", "/pair", body: Data(repeating: 0x20, count: 8 * 1024 + 1))) == 413)
    }

    @Test func theParsersDeclaredLengthCheckTakesTheRoutesLimit() {
        func parse(_ target: String, length: Int) -> RemoteHTTP.Parse {
            RemoteHTTP.parse(Data("POST \(target) HTTP/1.1\r\nContent-Length: \(length)\r\n\r\n".utf8))
        }
        func waits(_ parsed: RemoteHTTP.Parse) -> Bool {
            if case .head = parsed { true } else { false }
        }
        let message = "/api/sessions/\(Self.id)/message"
        #expect(waits(parse(message, length: 16 * 1024)))
        #expect(parse(message, length: 16 * 1024 + 1) == .reject(413))
        #expect(waits(parse(message + "?x=1", length: 16 * 1024)))
        #expect(parse("/api/sessions/\(Self.id)/approve", length: 8 * 1024 + 1) == .reject(413))
        #expect(waits(parse("/api/sessions/\(Self.id)/approve", length: 8 * 1024)))
        // Under another method, or anywhere else: 8 KB.
        #expect(RemoteHTTP.parse(Data("GET \(message) HTTP/1.1\r\nContent-Length: 9000\r\n\r\n".utf8)) == .reject(413))
        #expect(parse("/nothing", length: 8 * 1024 + 1) == .reject(413))
    }
}

// MARK: `/api/sessions/<id>`, version 2

@MainActor
struct RemoteSessionV2Tests {
    private let now = Date(timeIntervalSince1970: 1_791_833_400) // 2026-10-12T19:30:00Z
    private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    private func session(_ state: SessionState, reason: WaitingReason? = nil) -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Example project", title: "Protein stability screen",
                      state: state, updatedAt: now.addingTimeInterval(-60), startedAt: now.addingTimeInterval(-600),
                      waitingReason: reason)
    }

    private func text(_ value: RemoteAPI.Session?) -> String {
        value.map { String(decoding: RemoteAPI.encode($0), as: UTF8.self) } ?? ""
    }

    @Test func aReadableQuestion() {
        let read = SessionProjection(
            status: "awaiting_user_response", agentName: "made-up-agent", projectID: "p",
            statusLine: "Waiting for your answer", reply: "Made-up *reply*.", replyAt: now.addingTimeInterval(-120),
            toYou: [SessionProjection.Note(text: "Started on the buffers.", at: now.addingTimeInterval(-300))],
            queued: 0,
            asks: [SessionProjection.Ask(toolID: "toolu_1", items: [SessionProjection.Question(
                question: "Which buffer?", header: "Buffer", multi: false,
                options: [SessionProjection.Option(label: "HEPES", detail: "Most stable"),
                          SessionProjection.Option(label: "Tris", detail: nil)])])],
            turns: [SessionProjection.Turn(role: .you, at: now.addingTimeInterval(-400), text: "Screen the buffers."),
                    SessionProjection.Turn(role: .claude, at: now.addingTimeInterval(-120), text: "Made-up *reply*.")])
        let built = RemoteAPI.session(id: id, candidates: [session(.needsInput, reason: .question)], plan: nil, read: read)
        #expect(text(built) == #"""
        {"can":{"answer":true,"approve":false,"message":null,"why":"Answer its question first"},"id":"0f8fad5b-d9cb-469f-a165-70867728950e","messages":[],"permission":null,"plan":null,"project":"Example project","question":{"items":[{"header":"Buffer","multi":false,"options":[{"detail":"Most stable","label":"HEPES"},{"detail":null,"label":"Tris"}],"question":"Which buffer?"}],"toolId":"toolu_1"},"queued":0,"readable":true,"reason":"question","reply":{"at":"2026-10-12T19:28:00Z","text":"Made-up *reply*."},"sentence":"Asked you a question","startedAt":"2026-10-12T19:20:00Z","state":"needsInput","statusLine":"Waiting for your answer","title":"Protein stability screen","toYou":[{"at":"2026-10-12T19:25:00Z","text":"Started on the buffers."}],"turns":[{"at":"2026-10-12T19:23:20Z","role":"you","text":"Screen the buffers."},{"at":"2026-10-12T19:28:00Z","role":"claude","text":"Made-up *reply*."}],"updatedAt":"2026-10-12T19:29:00Z","version":2}
        """#)
    }

    @Test func aTurnsIntentAndFileIDsStayOnTheMac() {
        // They tell a message just sent from another (WriteSettle.swift); the phone never gets them.
        let read = SessionProjection(
            status: "completed", agentName: "made-up-agent", projectID: "p",
            turns: [SessionProjection.Turn(role: .you, at: now.addingTimeInterval(-400), text: "Look at this.\n\nAttached: plate.csv",
                                           intent: "1b4e28ba-2fa1-41d2-883f-0016d3cca427",
                                           files: ["11111111-2222-4333-8444-555555555555"])])
        let json = text(RemoteAPI.session(id: id, candidates: [session(.finished)], plan: nil, read: read))
        #expect(json.contains(#""turns":[{"at":"2026-10-12T19:23:20Z","role":"you","text":"Look at this.\n\nAttached: plate.csv"}]"#))
        #expect(!json.contains("1b4e28ba"))
        #expect(!json.contains("11111111-2222"))
        #expect(!json.contains("intent"))
        #expect(!json.contains("files"))
    }

    @Test func unreadableIsVersionOneWithNulls() {
        let built = RemoteAPI.session(id: id, candidates: [session(.running)], plan: nil)
        #expect(text(built) == #"""
        {"can":{"answer":false,"approve":false,"message":null,"why":"Capsid can't read this session"},"id":"0f8fad5b-d9cb-469f-a165-70867728950e","messages":[],"permission":null,"plan":null,"project":"Example project","question":null,"queued":null,"readable":false,"reason":null,"reply":null,"sentence":"Working","startedAt":"2026-10-12T19:20:00Z","state":"running","statusLine":null,"title":"Protein stability screen","toYou":null,"turns":null,"updatedAt":"2026-10-12T19:29:00Z","version":2}
        """#)
    }

    @Test func thePlanCarriesItsVersionOnlyWhileThatVersionWaits() throws {
        let preview = PlanPreview(summary: "Made-up plan", steps: 2, confidence: "high", stepTitles: ["One", "Two"],
                                  versionID: "ver-1", artifactID: nil)
        let waiting = SessionProjection(status: "awaiting_plan_approval", agentName: "a", projectID: nil,
                                        planVersion: "ver-1", turns: [])
        let built = try #require(RemoteAPI.session(id: id, candidates: [session(.needsInput, reason: .plan)],
                                                   plan: preview, read: waiting))
        #expect(built.plan == RemoteAPI.Plan(summary: "Made-up plan", steps: ["One", "Two"], feasibility: "high", version: "ver-1"))
        #expect(built.can.approve)
        let moved = SessionProjection(status: "awaiting_plan_approval", agentName: "a", projectID: nil,
                                      planVersion: "ver-2", turns: [])
        let stale = try #require(RemoteAPI.session(id: id, candidates: [session(.needsInput, reason: .plan)],
                                                   plan: preview, read: moved))
        #expect(stale.plan == nil)
        #expect(!stale.can.approve)
    }

    @Test func aQuestionShowsOnlyWhileTheRootWaitsForAnAnswer() throws {
        let ask = SessionProjection.Ask(toolID: "t", items: [SessionProjection.Question(question: "Q?", header: "", multi: false, options: [])])
        let working = SessionProjection(status: "processing", agentName: "a", projectID: nil, asks: [ask], turns: [])
        let built = try #require(RemoteAPI.session(id: id, candidates: [session(.running)], plan: nil, read: working))
        #expect(built.question == nil)
        #expect(built.can.message == "queue")
    }

    @Test func actionsOffTurnsEveryCanOff() throws {
        let read = SessionProjection(status: "completed", agentName: "a", projectID: nil, turns: [])
        let built = try #require(RemoteAPI.session(id: id, candidates: [session(.finished)], plan: nil, read: read, actionsOn: false))
        #expect(built.can == RemoteAPI.Can(approve: false, answer: false, message: nil, why: "Actions are off in Capsid's Settings"))
        #expect(built.readable)
    }
}
