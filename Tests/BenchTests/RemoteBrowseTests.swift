// RemoteBrowseTests.swift — Phase 3 on made-up projects and sessions: the
// routes, the query and the cursor, the new-session write in the page, every
// answer of `RemoteBrowser` against fakes that only record what they were
// asked, the session gate's point lookup, and `--demo remote`'s made-up store.
// Nothing reaches a real daemon, database or web view.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"

private func json(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

// MARK: Routes

struct RemoteBrowseRouteTests {
    private func match(_ method: String, _ path: String) -> RemoteRoute.Match {
        RemoteRoute.match(method: method, path: Substring(path))
    }

    @Test func thePhase3Paths() {
        #expect(match("GET", "/api/projects") == .found(.projects))
        #expect(match("GET", "/api/projects/proj_a-1/sessions") == .found(.projectSessions("proj_a-1")))
        #expect(match("POST", "/api/projects/proj_a-1/sessions") == .found(.newSession("proj_a-1")))
        #expect(match("GET", "/api/sessions/\(root)/history") == .found(.history(root)))
        #expect(match("GET", "/api/sessions/\(root)/turn/0") == .found(.turn(root, 0)))
        #expect(match("GET", "/api/sessions/\(root)/turn/9999999") == .found(.turn(root, 9_999_999)))
        // Phase 1 and 2 are as they were.
        #expect(match("GET", "/api/sessions/\(root)") == .found(.session(root)))
        #expect(match("POST", "/api/sessions/\(root)/approve") == .found(.action(.approve, root)))
        #expect(match("POST", "/api/sessions/\(root)/open") == .found(.openSession(root)))
    }

    @Test(arguments: ["__proto__", "constructor", "prototype"])
    func aNameAScriptsObjectAnswersToIsNoProject(_ name: String) {
        // The phone refuses these in its address; the routes refuse them too: 404, not an empty project.
        #expect(match("GET", "/api/projects/\(name)/sessions") == .notFound)
        #expect(match("POST", "/api/projects/\(name)/sessions") == .notFound)
        #expect(match("POST", "/api/projects/\(name)/photo") == .notFound)
        #expect(!RemoteRoute.isRoutableProject(name))
        // A project whose id only holds the word is as any other.
        for id in ["\(name)x", "x\(name)", "my_\(name)", name.uppercased()] {
            #expect(match("GET", "/api/projects/\(id)/sessions") == .found(.projectSessions(id)), "\(id)")
            #expect(match("POST", "/api/projects/\(id)/photo") == .found(.photo(.project(id))), "\(id)")
        }
    }

    @Test func anythingElseIsNotFoundOrTheWrongMethod() {
        #expect(match("POST", "/api/projects") == .wrongMethod)
        #expect(match("PUT", "/api/projects/p/sessions") == .wrongMethod)
        #expect(match("POST", "/api/sessions/\(root)/history") == .wrongMethod)
        for path in ["/api/projects/", "/api/projects/a.b/sessions", "/api/projects/%41/sessions",
                     "/api/projects/\(String(repeating: "a", count: 65))/sessions", "/api/projects/p/sessions/",
                     "/api/projects/p", "/api/projects/p/artifacts", "/api/projects//sessions",
                     "/api/sessions/\(root)/turn/007", "/api/sessions/\(root)/turn/-1", "/api/sessions/\(root)/turn/10000000",
                     "/api/sessions/\(root)/turn/", "/api/sessions/\(root)/turn/1/x", "/api/sessions/\(root)/history/",
                     "/api/sessions/\(root.uppercased())/history", "/api/sessions/short/history"] {
            #expect(match("GET", path) == .notFound, "\(path)")
        }
    }

    @Test func thePatternsNameNoId() {
        #expect(RemoteRoute.projectSessions("proj_secret").pattern == "/api/projects/<pid>/sessions")
        #expect(RemoteRoute.newSession("proj_secret").pattern == "/api/projects/<pid>/sessions")
        #expect(RemoteRoute.history(root).pattern == "/api/sessions/<id>/history")
        #expect(RemoteRoute.turn(root, 5).pattern == "/api/sessions/<id>/turn/<i>")
        #expect(RemoteRoute.projects.pattern == "/api/projects")
    }

    @Test func aNewSessionsBodyMayBeSixteenKilobytes() {
        #expect(RemoteRoute.newSession("p").bodyLimit == 16 * 1024)
        #expect(RemoteRoute.projectSessions("p").bodyLimit == RemoteHTTP.maxBody)
        let big = String(repeating: "界", count: 4000)
        let body = Data(#"{"text":"\#(big)","id":"\#(intent)"}"#.utf8)
        let head = "POST /api/projects/p/sessions HTTP/1.1\r\nHost: x\r\nContent-Length: \(body.count)\r\n\r\n"
        guard case .request(let request) = RemoteHTTP.parse(Data(head.utf8) + body) else { Issue.record("refused"); return }
        #expect(request.body.count == body.count)
        let get = "GET /api/projects/p/sessions HTTP/1.1\r\nHost: x\r\nContent-Length: \(body.count)\r\n\r\n"
        #expect(RemoteHTTP.parse(Data(get.utf8) + body) == .reject(413))
    }
}

// MARK: The query and the cursor

struct BrowseQueryTests {
    @Test func onlyTheNamesTheRouteTakesEachOnce() {
        #expect(BrowseQuery.parse("/api/projects", allowed: []) == [:])
        #expect(BrowseQuery.parse("/api/projects?", allowed: []) == [:])
        #expect(BrowseQuery.parse("/x?q=made%20up+text&before=abc", allowed: ["q", "before"]) == ["q": "made up text", "before": "abc"])
        #expect(BrowseQuery.parse("/x?q=%2B1", allowed: ["q"]) == ["q": "+1"])
        for bad in ["/x?other=1", "/x?q=a&q=b", "/x?q", "/x?q=%ZZ", "/x?&q=a", "/x?q=a&"] {
            #expect(BrowseQuery.parse(bad, allowed: ["q"]) == nil, "\(bad)")
        }
    }

    @Test func aSearchIsTwoToSixtyFourCharacters() {
        #expect(BrowseQuery.search(nil) == .some(nil))
        #expect(BrowseQuery.search("   ") == .some(nil))
        #expect(BrowseQuery.search(" ab ") == .some("ab"))
        #expect(BrowseQuery.search(String(repeating: "界", count: 64)) == .some(String(repeating: "界", count: 64)))
        #expect(BrowseQuery.search("a") == nil)
        #expect(BrowseQuery.search(String(repeating: "a", count: 65)) == nil)
        #expect(BrowseQuery.search("a\nb") == nil)
        #expect(BrowseQuery.search("a\u{0}b") == nil)
    }

    @Test func indexes() {
        #expect(BrowseQuery.index("0") == 0)
        #expect(BrowseQuery.index("9999999") == 9_999_999)
        for bad in ["", "01", "-1", "10000000", "1e3", " 1", "١"] { #expect(BrowseQuery.index(bad) == nil, "\(bad)") }
    }

    @Test func theCursorRoundTripsAndNothingElseDecodes() {
        let cursor = BrowseCursor(updatedMs: 1_791_833_400_000, id: root)
        let text = BrowseCursorCoding.encode(cursor)
        #expect(!text.contains("=") && !text.contains("+") && !text.contains("/"))
        #expect(BrowseCursorCoding.decode(text) == cursor)
        func base64url(_ plain: String) -> String {
            Data(plain.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        for plain in ["1|short", "x|\(root)", "|\(root)", "1|\(root)|2", "-5|\(root)", "1|\(root.uppercased())",
                      "12345678901234567|\(root)", "1|\(root)' OR 1=1"] {
            #expect(BrowseCursorCoding.decode(base64url(plain)) == nil, "\(plain)")
        }
        #expect(BrowseCursorCoding.decode(text + "==") == nil)
        #expect(BrowseCursorCoding.decode("not a cursor") == nil)
        #expect(BrowseCursorCoding.decode("") == nil)
    }

    @Test func aNewSessionsBody() {
        func parse(_ text: String) -> NewSessionRequest? { NewSessionRequest.parse(Data(text.utf8)) }
        #expect(parse(#"{"text":"  Made-up question \n","id":"\#(intent)","planFirst":true}"#)
                == NewSessionRequest(text: "Made-up question", intentID: intent, planFirst: true))
        #expect(parse(#"{"text":"Hi","id":"\#(intent)"}"#)?.planFirst == false)
        #expect(parse(#"{"text":"\#(String(repeating: "界", count: 4000))","id":"\#(intent)"}"#) != nil)
        for bad in [#"{"text":"","id":"\#(intent)"}"#, #"{"text":"Hi"}"#, #"{"text":"Hi","id":"\#(intent)","planFirst":"yes"}"#,
                    #"{"text":"Hi","id":"\#(intent)","planFirst":1}"#, #"{"text":"Hi","id":"\#(intent.uppercased())"}"#,
                    #"{"text":"\#(String(repeating: "a", count: 4001))","id":"\#(intent)"}"#, "[]", "nope"] {
            #expect(parse(bad) == nil, "\(bad.prefix(40))")
        }
    }
}

// MARK: The new session's write, in the page

struct NewSessionWriteTests {
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

    private func sorted(_ value: Any?) -> String {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func itGoesToTheProjectsOwnRequestWithItsPlanModeAndNoAgent() {
        let write = build(.newSession(project: "proj_a", text: "Made-up question", planMode: true, intentID: intent))
        #expect(write?["path"] as? String == "/api/projects/proj_a/request")
        #expect(sorted(write?["body"]) == #"{"input_data":{"request":"Made-up question"},"intent_id":"\#(intent)","plan_mode":true}"#)
        let off = build(.newSession(project: "proj_a", text: "x", planMode: false, intentID: intent))
        #expect((off?["body"] as? [String: Any])?["plan_mode"] as? Bool == false)
    }

    @Test func anythingElseBuildsNothing() {
        let refused: [RemoteWrite] = [
            .newSession(project: "", text: "x", planMode: false, intentID: intent),
            .newSession(project: "../usage", text: "x", planMode: false, intentID: intent),
            .newSession(project: String(repeating: "p", count: 65), text: "x", planMode: false, intentID: intent),
            .newSession(project: "p", text: "", planMode: false, intentID: intent),
            .newSession(project: "p", text: String(repeating: "a", count: 4001), planMode: false, intentID: intent),
            .newSession(project: "p", text: "x", planMode: false, intentID: "6ba7b810-9dad-11d1-80b4-00c04fd430c8"),
        ]
        for write in refused { #expect(build(write) == nil) }
        var noMode = RemoteWrite.newSession(project: "p", text: "x", planMode: false, intentID: intent).arguments
        noMode["planMode"] = NSNull()
        #expect(build(arguments: noMode) == nil)
        noMode["planMode"] = "true"
        #expect(build(arguments: noMode) == nil)
    }

    @Test func itCarriesTheCSRFSecretAndComesBackWithTheNewId() {
        let write = RemoteWrite.newSession(project: "proj_a", text: "Hello", planMode: false, intentID: intent)
        let script = PageScript()
        let arguments = write.arguments.keys.sorted().map { key -> (String, String) in
            let data = (try? JSONSerialization.data(withJSONObject: write.arguments[key]!, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            return (key, String(decoding: data, as: UTF8.self))
        }
        let path = "/api/projects/proj_a/request"
        let (raw, requests) = script.runPage(SessionWriterScript.body, arguments: arguments, answers: [
            path: [PageScript.Answer(status: 403, body: #"{"code":"csrf_stale"}"#),
                   PageScript.Answer(status: 200, body: #"{"root_frame_id":"\#(root)","frame_id":"\#(root)","status":"accepted","secret":"SECRET"}"#)],
            "/api/csrf": [PageScript.Answer(status: 204, body: "")],
        ])
        #expect(script.exception == nil)
        #expect(requests.map(\.path) == [path, "/api/csrf", path])
        #expect(requests.first?.csrf == "secret-one")
        #expect(raw?.contains("SECRET") == false)
        let result = raw.flatMap { try? SessionWriterScript.result(of: Data($0.utf8)) }
        #expect(result == RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root))
    }

    @Test func onlyAFullFrameIdComesBack() {
        let good: [String: Any] = ["status": 200, "isJSON": true, "code": "", "bodyStatus": "accepted", "remaining": -1,
                                   "noPlanAwaiting": false, "askPending": false, "staleInput": false, "rootFrameId": root]
        #expect(RemoteWriteResult(object: good)?.rootFrameID == root)
        var empty = good
        empty["rootFrameId"] = ""
        #expect(RemoteWriteResult(object: empty)?.rootFrameID == nil)
        for bad: Any in ["r", root.uppercased(), 5, NSNull()] {
            var refused = good
            refused["rootFrameId"] = bad
            #expect(RemoteWriteResult(object: refused) == nil)
        }
    }
}

// MARK: The answers, against fakes

/// Stands in for the database, the page and the writer: answers from tables,
/// records every call, and never reaches anything.
@MainActor
private final class FakeBrowse {
    var browseOn = true
    var actionsOn = true
    var projects: [ProjectRow]? = [ProjectRow(id: "proj_a", name: "Made-up A", sessions: 2, lastActiveMs: 1_791_833_400_000),
                                   ProjectRow(id: "proj_b", name: "", sessions: 0, lastActiveMs: nil)]
    var rows: [BrowseRow]? = []
    var known: [SessionStatus] = []
    var database: [String: SessionStatus] = [:]
    var history: RemoteBrowser.HistoryRead = .unreadable
    var turn: RemoteBrowser.TurnRead = .none
    var created: RemoteWriteResult? = nil
    /// The write that makes a session goes in and never comes back.
    var createNeverReturns = false
    /// How long the Swift side gives it (read when `browser` is first used).
    var createLimit: Duration = .seconds(60)
    var intents: [String?] = []
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var calls: [String] = []
    /// The `knownTotal` each history read was given.
    private(set) var knownTotals: [Int?] = []
    private(set) var writes: [RemoteWrite] = []
    private(set) var listed: [(versions: [String], device: String)] = []
    private(set) var sessionReads: [(project: String, after: BrowseCursor?, search: String?)] = []

    lazy var sessions = RemoteSessions(dependencies: RemoteSessions.Dependencies(
        actionsOn: { [unowned self] in self.actionsOn },
        known: { [unowned self] in self.known },
        cardPlan: { _ in nil },
        read: { [unowned self] _, _ in self.calls.append("read"); return nil },
        readPlan: { _ in nil },
        write: { _ in nil },
        now: { [unowned self] in self.now },
        browseOn: { [unowned self] in self.browseOn },
        lookup: { [unowned self] id in self.calls.append("lookup"); return self.database[id] }))

    lazy var browser = RemoteBrowser(sessions: sessions, dependencies: RemoteBrowser.Dependencies(
        browseOn: { [unowned self] in self.browseOn },
        actionsOn: { [unowned self] in self.actionsOn },
        projects: { [unowned self] in self.calls.append("projects"); return self.projects },
        sessions: { [unowned self] project, after, search in
            self.calls.append("sessions")
            self.sessionReads.append((project, after, search))
            return self.rows
        },
        known: { [unowned self] in self.known },
        history: { [unowned self] _, before, knownTotal in
            self.calls.append("history \(before.map(String.init) ?? "last")")
            self.knownTotals.append(knownTotal)
            return self.history
        },
        turn: { [unowned self] _, index in self.calls.append("turn \(index)"); return self.turn },
        create: { [unowned self] write in
            self.calls.append("create")
            self.writes.append(write)
            if self.createNeverReturns { await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } }
            return self.created
        },
        findIntent: { [unowned self] _, _ in
            self.calls.append("intent")
            return self.intents.isEmpty ? nil : self.intents.removeFirst()
        },
        listed: { [unowned self] files, device in self.listed.append((files.map(\.v), device)) },
        now: { [unowned self] in self.now },
        pause: { [unowned self] in self.calls.append("pause") },
        createLimit: createLimit))

    func respond(_ method: String, _ target: String, body: String = "", device: String = "device-1") async -> RemoteActionReply {
        let path = Substring(target.prefix { $0 != "?" })
        guard case .found(let route) = RemoteRoute.match(method: method, path: path) else {
            return RemoteActionReply(status: 404, body: Data())
        }
        return await browser.respond(route, target: target, device: device, body: Data(body.utf8))
    }

    static func row(_ n: Int, name: String = "Made-up session", status: String = "completed", updated: Int64) -> BrowseRow {
        BrowseRow(id: madeUpID(n), projectID: "proj_a", projectName: "Made-up A", name: name, status: status,
                  createdMs: updated - 60_000, updatedMs: updated, completedMs: nil, turnStartedMs: updated - 60_000)
    }
}

@MainActor
struct RemoteBrowserTests {
    private let fake = FakeBrowse()

    @Test func browseOffAnswers403ToEveryRouteAndReadsNothing() async {
        fake.browseOn = false
        for (method, target) in [("GET", "/api/projects"), ("GET", "/api/projects/proj_a/sessions"),
                                 ("POST", "/api/projects/proj_a/sessions"), ("GET", "/api/sessions/\(root)/history"),
                                 ("GET", "/api/sessions/\(root)/turn/3")] {
            let reply = await fake.respond(method, target, body: #"{"text":"Hi","id":"\#(intent)"}"#)
            #expect(reply.status == 403)
            #expect(String(decoding: reply.body, as: UTF8.self) == #"{"error":"browseOff"}"#)
        }
        #expect(fake.calls.isEmpty)
        #expect(RemoteBrowse.off == RemoteActionReply(status: 403, body: Data(#"{"error":"browseOff"}"#.utf8)))
    }

    @Test func theSwitchIsOnUnlessTurnedOff() throws {
        let scratch = ScratchDefaults.make(prefix: "bench-tests")
        defer { scratch.discard() }
        let defaults = scratch.defaults
        #expect(RemoteBrowse.setting(defaults))
        defaults.set(false, forKey: SettingsKey.remoteBrowse)
        #expect(!RemoteBrowse.setting(defaults))
        defaults.set("NO", forKey: SettingsKey.remoteBrowse)
        #expect(!RemoteBrowse.setting(defaults))
        defaults.set(true, forKey: SettingsKey.remoteBrowse)
        #expect(RemoteBrowse.setting(defaults))
    }

    @Test func theMeAnswerSaysWhetherBrowseIsOn() {
        let me = String(decoding: RemoteAPI.encode(RemoteAPI.Me(paired: true, device: "Pat's iPhone", bench: "0.4.0", browse: false)), as: UTF8.self)
        #expect(me == #"{"bench":"0.4.0","browse":false,"device":"Pat's iPhone","paired":true}"#)
    }

    @Test func theProjects() async {
        let reply = await fake.respond("GET", "/api/projects")
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"projects":[{"id":"proj_a","lastActive":"2026-10-12T19:30:00Z","name":"Made-up A","sessions":2},{"id":"proj_b","lastActive":null,"name":"Untitled project","sessions":0}],"version":1}"#)
        #expect(await fake.respond("GET", "/api/projects?x=1").status == 400)
        fake.projects = nil
        let unreadable = await fake.respond("GET", "/api/projects")
        #expect(unreadable.status == 503)
        #expect(json(unreadable.body)["error"] as? String == "unreadable")
    }

    @Test func aPageOfSessionsAndTheCursorToTheNext() async throws {
        let base: Int64 = 1_791_833_400_000
        var rows = (1...51).map { FakeBrowse.row($0, updated: base - Int64($0) * 1000) }
        rows[0] = FakeBrowse.row(1, name: "", status: "processing", updated: base - 1000)
        rows[1] = FakeBrowse.row(2, status: "failed", updated: base - 2000)
        fake.rows = rows
        // Bench knows the third is waiting on a question: its own state wins.
        fake.known = [Fixture.session(madeUpID(3), .needsInput, reason: .question)]
        let reply = await fake.respond("GET", "/api/projects/proj_a/sessions?q=made+up")
        #expect(reply.status == 200)
        let page = json(reply.body)
        let sessions = try #require(page["sessions"] as? [[String: Any]])
        #expect(sessions.count == 50)
        #expect(sessions[0] as NSDictionary == ["id": madeUpID(1), "title": "Untitled session", "state": "running", "sentence": "Working",
                                                "startedAt": "2026-10-12T19:28:59Z", "updatedAt": "2026-10-12T19:29:59Z"])
        #expect(sessions[1]["state"] as? String == "error")
        #expect(sessions[1]["sentence"] as? String == "Stopped with an error")
        #expect(sessions[2]["sentence"] as? String == "Asked you a question")
        let next = try #require(page["next"] as? String)
        #expect(BrowseCursorCoding.decode(next) == BrowseCursor(updatedMs: base - 50_000, id: madeUpID(50)))
        #expect(fake.sessionReads.last?.search == "made up")
        #expect(fake.sessionReads.last?.project == "proj_a")

        fake.rows = Array(rows.prefix(3))
        let last = await fake.respond("GET", "/api/projects/proj_a/sessions?before=\(next)")
        #expect(json(last.body)["next"] is NSNull)
        #expect(fake.sessionReads.last?.after == BrowseCursor(updatedMs: base - 50_000, id: madeUpID(50)))
    }

    @Test func aBadQueryIs400AndReadsNothing() async {
        for target in ["/api/projects/proj_a/sessions?q=a", "/api/projects/proj_a/sessions?before=nonsense",
                       "/api/projects/proj_a/sessions?page=2", "/api/projects/proj_a/sessions?q=ab&q=cd"] {
            #expect(await fake.respond("GET", target).status == 400, "\(target)")
        }
        #expect(fake.calls.isEmpty)
    }

    // MARK: History

    @Test func historyOpensAnyRootTheDatabaseHasAndListsItsFilesToThatDevice() async {
        let file = HistoryFile(v: "v-1", a: "a-1", name: "plot.png", kind: .image, size: 10)
        fake.history = .page(HistoryPage(total: 3, from: 0, items: [
            .turn(i: 0, role: .you, at: nil, text: "Made-up question", cut: false, files: []),
            .turn(i: 2, role: .claude, at: Date(timeIntervalSince1970: 1_791_833_400), text: "Made-up answer", cut: false, files: [file]),
        ]))
        #expect(await fake.respond("GET", "/api/sessions/\(root)/history").status == 404)
        #expect(fake.calls == ["lookup"])
        fake.database[root] = Fixture.session(root, .finished)
        let reply = await fake.respond("GET", "/api/sessions/\(root)/history?before=40", device: "device-9")
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"from":0,"items":[{"at":null,"cut":false,"files":[],"i":0,"role":"you","text":"Made-up question"},{"at":"2026-10-12T19:30:00Z","cut":false,"files":[{"a":"a-1","kind":"image","name":"plot.png","size":10,"v":"v-1"}],"i":2,"role":"claude","text":"Made-up answer"}],"total":3}"#)
        #expect(fake.calls.last == "history 40")
        #expect(fake.listed.count == 1)
        #expect(fake.listed.first?.versions == ["v-1"])
        #expect(fake.listed.first?.device == "device-9")
    }

    @Test func historyAnswers() async {
        fake.known = [Fixture.session(root, .running)]
        #expect(await fake.respond("GET", "/api/sessions/\(root)/history?before=0").status == 400)
        #expect(await fake.respond("GET", "/api/sessions/\(root)/history?before=01").status == 400)
        #expect(await fake.respond("GET", "/api/sessions/\(root)/history?from=3").status == 400)
        let unreadable = await fake.respond("GET", "/api/sessions/\(root)/history")
        #expect(unreadable.status == 503)
        #expect(fake.calls == ["history last"])
        // Known sessions need no lookup.
        #expect(!fake.calls.contains("lookup"))
    }

    // MARK: Pages kept (Fable's review of 0.5.0, P3)

    private func page(total: Int, from: Int, text: String = "Made-up answer") -> RemoteBrowser.HistoryRead {
        .page(HistoryPage(total: total, from: from, items: [.turn(i: from, role: .claude, at: nil, text: text, cut: false, files: [
            HistoryFile(v: "v-\(from)", a: nil, name: "plot.png", kind: .image, size: 10),
        ])]))
    }

    @Test func theNewestPageOfAHistoryAsLongIsTheOneKept() async {
        fake.known = [Fixture.session(root, .running)]
        fake.history = page(total: 100, from: 50)
        let first = await fake.respond("GET", "/api/sessions/\(root)/history")
        #expect(first.status == 200)
        // The page is asked whether the history is still 100 rows long: it is.
        fake.history = .same(total: 100)
        fake.now = fake.now.addingTimeInterval(10)
        let second = await fake.respond("GET", "/api/sessions/\(root)/history", device: "device-2")
        #expect(second == first)
        #expect(fake.calls == ["history last", "history last"])
        #expect(fake.knownTotals == [nil, 100])
        // Its files are listed to the device that asked, as for a read.
        #expect(fake.listed.map(\.device) == ["device-1", "device-2"])
        // Longer now: read whole, and that page is the one kept.
        fake.history = page(total: 104, from: 54, text: "Newer answer")
        let third = await fake.respond("GET", "/api/sessions/\(root)/history")
        #expect(String(decoding: third.body, as: UTF8.self).contains("Newer answer"))
        #expect(fake.knownTotals.last == 100)
        fake.history = .same(total: 104)
        #expect(await fake.respond("GET", "/api/sessions/\(root)/history") == third)
        #expect(fake.knownTotals.last == 104)
    }

    @Test func anEarlierPageOfAHistoryAsLongNeedsNoRead() async {
        fake.known = [Fixture.session(root, .running)]
        fake.history = page(total: 100, from: 50)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history")
        fake.history = page(total: 100, from: 0, text: "Earlier answer")
        let earlier = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        #expect(String(decoding: earlier.body, as: UTF8.self).contains("Earlier answer"))
        fake.history = .unreadable
        #expect(await fake.respond("GET", "/api/sessions/\(root)/history?before=50") == earlier)
        #expect(fake.calls == ["history last", "history 50"])
        // The history grew: the earlier page is read again, with the new length.
        fake.history = page(total: 101, from: 51)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history")
        fake.history = page(total: 101, from: 0, text: "Earlier answer")
        let again = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        #expect(fake.calls == ["history last", "history 50", "history last", "history 50"])
        #expect(String(decoding: again.body, as: UTF8.self).contains(#""total":101"#))
    }

    @Test func keptPagesLastThirtySeconds() async {
        fake.known = [Fixture.session(root, .running)]
        fake.history = page(total: 100, from: 50)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history")
        _ = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        fake.now = fake.now.addingTimeInterval(29)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        #expect(fake.calls == ["history last", "history 50"])
        fake.now = fake.now.addingTimeInterval(2)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        _ = await fake.respond("GET", "/api/sessions/\(root)/history")
        #expect(fake.calls == ["history last", "history 50", "history 50", "history last"])
        #expect(fake.knownTotals == [nil, nil, nil, nil])
    }

    @Test func anActionLetsTheSessionsPagesGo() async {
        fake.known = [Fixture.session(root, .running)]
        fake.history = page(total: 100, from: 50)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history")
        _ = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        #expect(fake.sessions.historyPages.count == 2)
        _ = await fake.sessions.act(.message, session: root, device: "d", body: Data(#"{"text":"Hi","id":"\#(intent)"}"#.utf8))
        #expect(fake.sessions.historyPages.count == 0)
        _ = await fake.respond("GET", "/api/sessions/\(root)/history?before=50")
        _ = await fake.respond("GET", "/api/sessions/\(root)/history")
        #expect(fake.calls.filter { $0.hasPrefix("history") } == ["history last", "history 50", "history 50", "history last"])
        #expect(fake.knownTotals == [nil, nil, nil, nil])
    }

    @Test func aReadUnderWayWhenAnActionLandsIsntKept() {
        let pages = HistoryPages()
        let now = Date(timeIntervalSince1970: 1_791_833_400)
        let started = pages.generation(of: root)
        pages.forget(root)
        pages.keep(HistoryPage(total: 3, from: 0, items: []), session: root, before: nil, at: now, generation: started)
        #expect(pages.count == 0)
        #expect(pages.total(of: root, now: now) == nil)
        pages.keep(HistoryPage(total: 3, from: 0, items: []), session: root, before: nil, at: now,
                   generation: pages.generation(of: root))
        #expect(pages.page(root, total: 3, before: nil, now: now) != nil)
    }

    @Test func everyKindAsTheSpecShowsIt() async {
        fake.known = [Fixture.session(root, .running)]
        fake.history = .page(HistoryPage(total: 9, from: 1, items: [
            .steps(i: 1, line: "Ran a command", failed: false, files: []),
            .plan(i: 3, steps: 4),
            .ask(i: 5, q: "Which buffer?", a: nil),
            .toYou(i: 7, text: "Made-up note", files: []),
            .helper(i: 8),
        ]))
        let reply = await fake.respond("GET", "/api/sessions/\(root)/history")
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"from":1,"items":[{"failed":false,"i":1,"kind":"steps","line":"Ran a command"},{"i":3,"kind":"plan","steps":4},{"a":null,"i":5,"kind":"ask","q":"Which buffer?"},{"files":[],"i":7,"kind":"toYou","text":"Made-up note"},{"i":8,"kind":"helper"}],"total":9}"#)
    }

    @Test func aWholeTurn() async {
        fake.known = [Fixture.session(root, .running)]
        #expect(await fake.respond("GET", "/api/sessions/\(root)/turn/4").status == 404)
        fake.turn = .turn(HistoryTurn(i: 4, role: .claude, at: nil, text: "All of it"))
        let reply = await fake.respond("GET", "/api/sessions/\(root)/turn/4")
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"at":null,"i":4,"role":"claude","text":"All of it"}"#)
        // A turn from another index is no answer.
        #expect(await fake.respond("GET", "/api/sessions/\(root)/turn/5").status == 503)
        fake.turn = .unreadable
        #expect(await fake.respond("GET", "/api/sessions/\(root)/turn/4").status == 503)
        #expect(await fake.respond("GET", "/api/sessions/\(madeUpID(77))/turn/4").status == 404)
    }

    // MARK: A new session

    private func start(_ body: String = #"{"text":" Made-up question ","id":"\#(intent)","planFirst":true}"#,
                       device: String = "device-1") async -> RemoteActionReply {
        await fake.respond("POST", "/api/projects/proj_a/sessions", body: body, device: device)
    }

    @Test func aNewSessionStartsAndOpensAtOnce() async {
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root)
        let reply = await start()
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"id":"\#(root)","result":"started","sentence":"Started"}"#)
        #expect(fake.writes == [.newSession(project: "proj_a", text: "Made-up question", planMode: true, intentID: intent)])
        // The database doesn't have it yet; it opens anyway.
        let session = await fake.sessions.sessionJSON(root)
        #expect(session.map(json)?["title"] as? String == "Made-up question")
        #expect(!fake.calls.contains("intent"))
    }

    @Test(arguments: [
        "{{artifact:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee}}", #"{"type":"artifact","id":"x"}"#, #"{"type":"attachment","id":"x"}"#,
        #"{"type":"skill","name":"x"}"#, #"{"type":"session","id":"x"}"#, #"{"artifact_ref":"x"}"#, #"{"file_path":"/x"}"#,
        #"{ "type" : "attachment", "id": "x"}"#, "{{ artifact: aaaa }}",
    ])
    func aNewSessionWithAReferenceIs400ReferenceAndWritesNothing(_ reference: String) async {
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root)
        for text in [reference, "Look at " + reference] {
            let body = String(decoding: PhotoFixture.json(["text": text, "id": intent]), as: UTF8.self)
            #expect(NewSessionRequest.parse(Data(body.utf8)) == nil)
            let reply = await start(body)
            #expect(reply.status == 400)
            #expect(String(decoding: reply.body, as: UTF8.self) == #"{"error":"reference"}"#)
        }
        #expect(fake.writes.isEmpty)
        // Any other bad body is the plain 400.
        #expect(await start(#"{"text":"","id":"\#(intent)"}"#) == .badRequest)
        // And braces that aren't a reference start a session as ever.
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root)
        #expect(await start(#"{"text":"Use {{ var }} here","id":"\#(intent)"}"#).status == 200)
    }

    @Test func aLostOrRepeatedReplyIsFoundByItsIntent() async {
        fake.created = nil
        fake.intents = [nil, root]
        let lost = await start()
        #expect(json(lost.body)["result"] as? String == "started")
        #expect(json(lost.body)["id"] as? String == root)
        #expect(fake.calls == ["projects", "create", "intent", "pause", "intent"])

        fake.created = RemoteWriteResult(status: 409, code: "intent_conflict")
        fake.intents = [madeUpID(5)]
        #expect(json(await start().body)["id"] as? String == madeUpID(5))

        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        fake.intents = [nil, nil]
        let nothing = await start()
        #expect(json(nothing.body) as NSDictionary == ["result": "unavailable", "sentence": "Couldn't do that from here. Open it on your Mac."])
    }

    @Test func aRefusedNewSessionLooksForNothing() async {
        fake.created = RemoteWriteResult(status: 404, code: "not_found")
        #expect(json(await start().body)["result"] as? String == "unavailable")
        #expect(fake.calls == ["projects", "create"])
    }

    @Test func aNewSessionStartsOnlyInAProjectTheListShows() async {
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root)
        // A hidden concierge or archived project isn't in the list: 404, nothing written.
        let hidden = await fake.respond("POST", "/api/projects/proj_concierge_sys_1/sessions",
                                        body: #"{"text":"Made-up question","id":"\#(intent)"}"#)
        #expect(hidden.status == 404)
        #expect(fake.writes.isEmpty)
        #expect(fake.calls == ["projects"])
        // The list is held a minute: the next start reads it no more.
        #expect(await start().status == 200)
        #expect(fake.calls == ["projects", "create"])
        fake.now = fake.now.addingTimeInterval(61)
        _ = await start(#"{"text":"Another","id":"6ba7b810-9dad-41d1-80b4-00c04fd430c8"}"#)
        #expect(fake.calls.filter { $0 == "projects" }.count == 2)
    }

    @Test func aNewSessionWaitsForAProjectsListItCanRead() async {
        fake.projects = nil
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root)
        #expect(await start().status == 503)
        #expect(fake.writes.isEmpty)
    }

    @Test func theProjectsRouteFillsTheListANewSessionChecks() async {
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: root)
        #expect(await fake.respond("GET", "/api/projects").status == 200)
        #expect(await start().status == 200)
        #expect(fake.calls == ["projects", "create"])
    }

    @Test func aNewSessionNeedsActionsAndAGoodBody() async {
        fake.actionsOn = false
        let off = await start()
        #expect(off.status == 403)
        #expect(json(off.body)["error"] as? String == "actionsOff")
        fake.actionsOn = true
        #expect(await start(#"{"text":"","id":"\#(intent)"}"#).status == 400)
        #expect(fake.writes.isEmpty)
    }

    @Test func aNewSessionCountsTowardTheSameSixAMinute() async {
        fake.known = [Fixture.session(root, .running)]
        fake.created = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: madeUpID(9))
        for _ in 0..<3 {
            #expect(await fake.sessions.act(.message, session: root, device: "d", body: Data("{}".utf8)).status == 400)
        }
        for _ in 0..<3 { #expect(await start(device: "d").status == 200) }
        #expect(await start(device: "d").status == 429)
        #expect(await fake.sessions.act(.message, session: root, device: "d", body: Data("{}".utf8)).status == 429)
        #expect(await start(device: "other").status == 200)
    }
}

// MARK: A new session whose write gets no answer

@MainActor
struct RemoteBrowserUnknownTests {
    private let fake = FakeBrowse()
    private let request = NewSessionRequest(text: "Made-up question", intentID: intent, planFirst: true, attachment: false)

    @Test func aWriteWithNoAnswerThatTheDatabaseShowsIsStarted() async {
        fake.created = .unknown
        fake.intents = [root]
        var checking = 0
        let attempt = await fake.browser.attempt("proj_a", request: request, checking: { checking += 1 })
        guard case .started(let reply) = attempt else { Issue.record("not started: \(attempt)"); return }
        #expect(reply.status == 200)
        #expect(checking == 1)
        // One write, one look.
        #expect(fake.writes.count == 1)
        #expect(fake.calls == ["create", "intent"])
    }

    @Test func aWriteWithNoAnswerThatTheDatabaseDoesntShowCanBeTriedAgain() async {
        fake.created = .unknown
        fake.intents = [nil, nil]
        var checking = 0
        let attempt = await fake.browser.attempt("proj_a", request: request, checking: { checking += 1 })
        guard case .notThere = attempt else { Issue.record("not notThere: \(attempt)"); return }
        #expect(checking == 1)
        #expect(fake.writes.count == 1)
        #expect(fake.calls == ["create", "intent", "pause", "intent"])
        // The plain start reports it as no session.
        #expect(await fake.browser.start("proj_a", request: request) == nil)
        // Nothing is sent again on its own: one more write, from the second call, and no third.
        #expect(fake.writes.count == 2)
    }

    @Test func aWriteThatNeverReturnsIsCutOffAndLookedFor() async {
        fake.createNeverReturns = true
        fake.createLimit = .milliseconds(40)
        fake.intents = [nil, root]
        var checking = 0
        let attempt = await fake.browser.attempt("proj_a", request: request, checking: { checking += 1 })
        guard case .started = attempt else { Issue.record("not started: \(attempt)"); return }
        #expect(checking == 1)
        #expect(fake.writes.count == 1, "never sent again")
        // And when nothing shows, it can be tried again.
        let other = FakeBrowse()
        other.createNeverReturns = true
        other.createLimit = .milliseconds(40)
        other.intents = [nil, nil]
        guard case .notThere = await other.browser.attempt("proj_a", request: request) else { Issue.record("not notThere"); return }
    }

    @Test func aWriteThatWasNotMadeLooksForTheSessionButIsNotCalledUnknown() async {
        fake.created = nil
        fake.intents = [nil, nil]
        var checking = 0
        let attempt = await fake.browser.attempt("proj_a", request: request, checking: { checking += 1 })
        guard case .notStarted = attempt else { Issue.record("not notStarted: \(attempt)"); return }
        #expect(checking == 0)
    }

    @Test func aRefusalLooksForNothing() async {
        fake.created = RemoteWriteResult(status: 404, code: "not_found")
        let attempt = await fake.browser.attempt("proj_a", request: request)
        guard case .notStarted = attempt else { Issue.record("not notStarted: \(attempt)"); return }
        #expect(fake.calls == ["create"])
    }

    @Test func thePhonesRouteSaysItDidntGoThroughWhenNothingShows() async {
        fake.created = .unknown
        fake.intents = [nil, nil]
        let reply = await fake.respond("POST", "/api/projects/proj_a/sessions", body: #"{"text":"Made-up question","id":"\#(intent)"}"#)
        let body = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any]
        #expect(reply.status == 200)
        #expect(body?["result"] as? String == "retry")
        #expect(body?["sentence"] as? String == RemoteBrowser.Sentence.notThere)
        #expect(fake.writes.count == 1)
    }

    @Test func thePhonesRouteOpensTheSessionTheDatabaseShows() async {
        fake.created = .unknown
        fake.intents = [nil, root]
        let reply = await fake.respond("POST", "/api/projects/proj_a/sessions", body: #"{"text":"Made-up question","id":"\#(intent)"}"#)
        let body = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any]
        #expect(body?["result"] as? String == "started")
        #expect(body?["id"] as? String == root)
    }
}

// MARK: Which sessions open

@MainActor
struct RemoteSessionGateTests {
    private let fake = FakeBrowse()

    @Test func anyRootOpensWhileBrowseIsOnAndOnlyKnownOnesWhenOff() async {
        let other = madeUpID(42)
        fake.database[other] = Fixture.session(other, .finished, title: "Made-up old session")
        let session = await fake.sessions.sessionJSON(other)
        #expect(session.map(json)?["title"] as? String == "Made-up old session")
        #expect(session.map(json)?["readable"] as? Bool == false)
        #expect(fake.sessions.heldSession(other)?.id == other)

        fake.browseOn = false
        #expect(await fake.sessions.sessionJSON(other) == nil)
        #expect(fake.sessions.heldSession(other) == nil)
        #expect(await fake.sessions.act(.message, session: other, device: "d", body: Data("{}".utf8)).status == 404)
    }

    @Test func aKnownSessionNeedsNoLookup() async {
        fake.known = [Fixture.session(root, .running)]
        #expect(await fake.sessions.sessionJSON(root) != nil)
        #expect(!fake.calls.contains("lookup"))
    }

    @Test func anActionOnAnOldSessionReadsItAfresh() async {
        let other = madeUpID(43)
        fake.database[other] = Fixture.session(other, .finished)
        let reply = await fake.sessions.act(.message, session: other, device: "d", body: Data(#"{"text":"Hi","id":"\#(intent)"}"#.utf8))
        #expect(reply.status == 200)
        #expect(fake.calls == ["lookup", "read"])
    }

    @Test func aStartedSessionOpensForTwoMinutesWithoutTheDatabase() async {
        let new = madeUpID(44)
        fake.sessions.admitStarted(Fixture.session(new, .running))
        #expect(await fake.sessions.admitted(new) != nil)
        fake.now = fake.now.addingTimeInterval(121)
        #expect(await fake.sessions.admitted(new) == nil)
    }
}

// MARK: `--demo remote`

@MainActor
struct DemoBrowseTests {
    private func store() -> DemoBrowseStore {
        let now = Date()
        func make(_ suffix: String, _ title: String, _ project: String, _ state: SessionState, _ reason: WaitingReason? = nil) -> SessionStatus {
            SessionStatus(id: "00000000-0000-4000-8000-0000000000\(suffix)", projectID: DemoBrowseStore.projectID(for: project),
                          projectName: project, title: title, state: state, updatedAt: now.addingTimeInterval(-60),
                          startedAt: now.addingTimeInterval(-300), waitingReason: reason)
        }
        let sessions = [make("d1", "Protein stability screen", "Example project", .needsInput, .question),
                        make("d3", "Figure 2 rebuild", "Example project", .error),
                        make("d6", "Primer design", "Cloning", .finished)]
        return DemoBrowseStore(nowSessions: sessions, reads: Demo.remoteReads(sessions), now: now)
    }

    private func browser(_ store: DemoBrowseStore) -> (RemoteBrowser, RemoteSessions) {
        let sessions = RemoteSessions.demo(reads: [:], known: { store.nowSessions }, cardPlan: { _ in nil },
                                           lookup: { store.lookup($0) }, more: { store.read($0) })
        return (RemoteBrowser.demo(sessions: sessions, store: store, browseOn: { true }, actionsOn: { true }, listed: { _, _ in }), sessions)
    }

    private func get(_ browser: RemoteBrowser, _ target: String) async -> [String: Any] {
        let path = Substring(target.prefix { $0 != "?" })
        guard case .found(let route) = RemoteRoute.match(method: "GET", path: path) else { return [:] }
        return json(await browser.respond(route, target: target, device: "d", body: Data()).body)
    }

    @Test func exampleProjectHasTwoPagesAndEveryProjectSomething() async throws {
        let (browser, _) = browser(store())
        let projects = try #require(await get(browser, "/api/projects")["projects"] as? [[String: Any]])
        #expect(projects.count == DemoBrowseStore.projects.count)
        let example = try #require(projects.first { $0["name"] as? String == "Example project" })
        #expect(example["sessions"] as? Int == 64)
        let first = await get(browser, "/api/projects/proj_demo_example/sessions")
        #expect((first["sessions"] as? [Any])?.count == 50)
        let next = try #require(first["next"] as? String)
        let second = await get(browser, "/api/projects/proj_demo_example/sessions?before=\(next)")
        #expect((second["sessions"] as? [Any])?.count == 14)
        #expect(second["next"] is NSNull)
        let titles = ((first["sessions"] as? [[String: Any]]) ?? []) + ((second["sessions"] as? [[String: Any]]) ?? [])
        #expect(Set(titles.compactMap { $0["id"] as? String }).count == 64)
        #expect(titles.contains { $0["title"] as? String == "Untitled session" })
        let found = await get(browser, "/api/projects/proj_demo_example/sessions?q=melt")
        #expect(((found["sessions"] as? [[String: Any]]) ?? []).allSatisfy { ($0["title"] as? String)?.lowercased().contains("melt") == true })
    }

    @Test func primerDesignHasAPagedHistoryWithEveryKind() async throws {
        let store = store()
        let (browser, _) = browser(store)
        let id = "00000000-0000-4000-8000-0000000000d6"
        var kinds = Set<String>()
        var before: Int?
        var pages = 0
        var cut: Int?
        repeat {
            let page = await get(browser, "/api/sessions/\(id)/history" + (before.map { "?before=\($0)" } ?? ""))
            let items = try #require(page["items"] as? [[String: Any]])
            for item in items {
                kinds.insert(item["kind"] as? String ?? item["role"] as? String ?? "")
                if item["cut"] as? Bool == true { cut = item["i"] as? Int }
                for file in item["files"] as? [[String: Any]] ?? [] { kinds.insert("file:" + (file["kind"] as? String ?? "")) }
            }
            let from = try #require(page["from"] as? Int)
            before = from > 0 ? from : nil
            pages += 1
        } while before != nil
        #expect(pages >= 3)
        #expect(kinds.isSuperset(of: ["you", "claude", "steps", "plan", "ask", "toYou", "helper"]))
        #expect(kinds.isSuperset(of: ArtifactKind.allCases.map { "file:" + $0.rawValue }))
        let whole = await get(browser, "/api/sessions/\(id)/turn/\(try #require(cut))")
        #expect(((whole["text"] as? String) ?? "").count > 2000)
    }

    @Test func aNewSessionStartsListsAndOpens() async throws {
        let store = store()
        let (browser, sessions) = browser(store)
        let body = Data(#"{"text":"Made-up new question","id":"\#(intent)","planFirst":false}"#.utf8)
        let started = json(await browser.respond(.newSession("proj_demo_cloning"), target: "/api/projects/proj_demo_cloning/sessions",
                                                 device: "d", body: body).body)
        #expect(started["result"] as? String == "started")
        let id = try #require(started["id"] as? String)
        #expect(PlanCheck.isFrameID(id))
        let session = try #require(await sessions.sessionJSON(id))
        #expect(json(session)["title"] as? String == "Made-up new question")
        #expect(json(session)["readable"] as? Bool == true)
        let list = await get(browser, "/api/projects/proj_demo_cloning/sessions")
        #expect(((list["sessions"] as? [[String: Any]])?.first)?["id"] as? String == id)
        // The same intent again: the daemon's 409, then found by it.
        let again = json(await browser.respond(.newSession("proj_demo_cloning"), target: "/api/projects/proj_demo_cloning/sessions",
                                               device: "d", body: body).body)
        #expect(again["id"] as? String == id)
        // A project the list doesn't show: no session starts there.
        let elsewhere = await browser.respond(.newSession("proj_nowhere"), target: "/api/projects/proj_nowhere/sessions",
                                              device: "d", body: Data(#"{"text":"x","id":"6ba7b810-9dad-41d1-80b4-00c04fd430c8"}"#.utf8))
        #expect(elsewhere.status == 404)
    }
}
