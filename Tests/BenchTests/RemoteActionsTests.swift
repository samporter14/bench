// RemoteActionsTests.swift — the phone's actions and its session route, on
// made-up sessions: the bodies, every decision and reply mapping, the limit,
// the setting, the cache, and the whole flow against a fake daemon that only
// records what it was asked. Nothing reaches a real daemon or web view.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"

private func body(_ json: String) -> Data { Data(json.utf8) }

private func read(_ status: String, agent: String? = "made-up-agent", project: String? = "proj-1",
                  asks: [SessionProjection.Ask?] = [], version: String? = nil,
                  approval: PlanFrame.Approval = .no, turns: [SessionProjection.Turn]? = nil) -> SessionProjection {
    SessionProjection(status: status, agentName: agent, projectID: project, asks: asks,
                      planVersion: version, approval: approval, turns: turns)
}

private let buffers = SessionProjection.Ask(toolID: "toolu_1", items: [
    SessionProjection.Question(question: "Which buffer?", header: "Buffer", multi: false,
                               options: [SessionProjection.Option(label: "HEPES", detail: nil)]),
    SessionProjection.Question(question: "How many replicates?", header: "", multi: false, options: []),
])

// MARK: Bodies

struct RemoteActionBodyTests {
    @Test func goodBodies() {
        #expect(RemoteActionRequest.parse(.approve, body: body(#"{"version":"ver-001"}"#)) == .approve(version: "ver-001"))
        #expect(RemoteActionRequest.parse(.answer, body: body(#"{"toolId":"t","answers":{"Q?":"  HEPES \n"}}"#))
                == .answer(toolID: "t", answers: ["Q?": "HEPES"]))
        #expect(RemoteActionRequest.parse(.answer, body: body(#"{"toolId":"t","action":"chooseForMe"}"#)) == .chooseForMe(toolID: "t"))
        #expect(RemoteActionRequest.parse(.answer, body: body(#"{"toolId":"t","action":"cancel"}"#)) == .cancel(toolID: "t"))
        #expect(RemoteActionRequest.parse(.message, body: body(#"{"text":"  Try again \n","id":"\#(intent)"}"#))
                == .message(text: "Try again", intentID: intent))
    }

    @Test func aFourThousandCharacterMessageFitsAndOneMoreDoesNot() {
        let most = String(repeating: "界", count: 4000)
        #expect(RemoteActionRequest.parse(.message, body: body(#"{"text":"\#(most)","id":"\#(intent)"}"#)) != nil)
        #expect(RemoteActionRequest.parse(.message, body: body(#"{"text":"\#(most)界","id":"\#(intent)"}"#)) == nil)
        // 4,000 such characters are 12 KB of JSON: more than the 8 KB other routes take.
        #expect(body(#"{"text":"\#(most)","id":"\#(intent)"}"#).count > RemoteHTTP.maxBody)
    }

    @Test(arguments: [
        (RemoteAction.approve, #"{}"#),
        (.approve, #"{"version":"a/b"}"#),
        (.approve, #"{"version":5}"#),
        (.approve, #"["ver"]"#),
        (.answer, #"{"answers":{"Q?":"A"}}"#),
        (.answer, #"{"toolId":"t"}"#),
        (.answer, #"{"toolId":"t","answers":{"Q?":"A"},"action":"cancel"}"#),
        (.answer, #"{"toolId":"t","action":"discuss"}"#),
        (.answer, #"{"toolId":"t","answers":{}}"#),
        (.answer, #"{"toolId":"t","answers":{"Q?":"   "}}"#),
        (.answer, #"{"toolId":"t","answers":{"Q?":5}}"#),
        (.answer, #"{"toolId":"t","answers":["A"]}"#),
        (.message, #"{"text":"   ","id":"\#(intent)"}"#),
        (.message, #"{"text":"Hi"}"#),
        (.message, #"{"text":"Hi","id":"\#(intent.uppercased())"}"#),
        (.message, #"{"text":"Hi","id":"6ba7b810-9dad-11d1-80b4-00c04fd430c8"}"#),
        (.message, #"{"text":5,"id":"\#(intent)"}"#),
        (.message, "not json"),
    ])
    func badBodies(_ action: RemoteAction, _ json: String) {
        #expect(RemoteActionRequest.parse(action, body: body(json)) == nil)
    }

    @Test func anAnswerOverAThousandCharactersIsRefused() {
        let long = String(repeating: "a", count: 1001)
        #expect(RemoteActionRequest.parse(.answer, body: body(#"{"toolId":"t","answers":{"Q?":"\#(long)"}}"#)) == nil)
    }
}

// MARK: What may be done

struct RemoteCanTests {
    @Test func theMessageTable() {
        #expect(RemoteMessageMode(status: "completed") == .send)
        #expect(RemoteMessageMode(status: "success") == .send)
        #expect(RemoteMessageMode(status: "processing") == .queue)
        #expect(RemoteMessageMode(status: "failed") == .resume)
        #expect(RemoteMessageMode(status: "cancelled") == .resume)
        #expect(RemoteMessageMode(status: "awaiting_user_response") == .blocked("Answer its question first"))
        #expect(RemoteMessageMode(status: "awaiting_plan_approval") == .blocked("Approve or revise the plan on your Mac"))
        #expect(RemoteMessageMode(status: "replaced").word == nil)
    }

    private let plan = PlanPreview(summary: "Made-up plan", steps: 2, confidence: "high", versionID: "ver-1", artifactID: nil)

    @Test func actionsOffComesFirstThenUnreadable() {
        let off = RemoteCan.make(read: read("completed"), plan: nil, actionsOn: false)
        #expect(off == RemoteAPI.Can(approve: false, answer: false, message: nil, why: "Actions are off in Bench's Settings"))
        #expect(RemoteCan.make(read: nil, plan: plan, actionsOn: false).why == "Actions are off in Bench's Settings")
        #expect(RemoteCan.make(read: nil, plan: plan, actionsOn: true)
                == RemoteAPI.Can(approve: false, answer: false, message: nil, why: "Bench can't read this session"))
    }

    @Test func eachStatusOffersItsOwn() {
        #expect(RemoteCan.make(read: read("completed"), plan: nil, actionsOn: true)
                == RemoteAPI.Can(approve: false, answer: false, message: "send", why: nil))
        #expect(RemoteCan.make(read: read("processing"), plan: nil, actionsOn: true).message == "queue")
        #expect(RemoteCan.make(read: read("failed"), plan: nil, actionsOn: true).message == "resume")
        #expect(RemoteCan.make(read: read("awaiting_user_response", asks: [buffers]), plan: nil, actionsOn: true)
                == RemoteAPI.Can(approve: false, answer: true, message: nil, why: "Answer its question first"))
        #expect(RemoteCan.make(read: read("awaiting_plan_approval", version: "ver-1"), plan: plan, actionsOn: true)
                == RemoteAPI.Can(approve: true, answer: false, message: nil, why: "Approve or revise the plan on your Mac"))
    }

    @Test func approveNeedsTheSamePlanStillWaitingAndNotApproved() {
        #expect(!RemoteCan.make(read: read("awaiting_plan_approval", version: "ver-2"), plan: plan, actionsOn: true).approve)
        #expect(!RemoteCan.make(read: read("awaiting_plan_approval", version: "ver-1"), plan: nil, actionsOn: true).approve)
        #expect(!RemoteCan.make(read: read("awaiting_plan_approval", version: "ver-1", approval: .yes), plan: plan, actionsOn: true).approve)
        #expect(!RemoteCan.make(read: read("awaiting_plan_approval", version: "ver-1", approval: .unclear), plan: plan, actionsOn: true).approve)
        // A sub-agent's plan leaves the root processing: no Approve.
        #expect(!RemoteCan.make(read: read("processing", version: "ver-1"), plan: plan, actionsOn: true).approve)
    }

    @Test func answerNeedsAReadableRootQuestion() {
        #expect(!RemoteCan.make(read: read("awaiting_user_response", asks: [nil, buffers]), plan: nil, actionsOn: true).answer)
        #expect(!RemoteCan.make(read: read("processing", asks: [buffers]), plan: nil, actionsOn: true).answer)
    }

    @Test func noAgentNoMessage() {
        #expect(RemoteCan.make(read: read("completed", agent: nil), plan: nil, actionsOn: true)
                == RemoteAPI.Can(approve: false, answer: false, message: nil, why: "Bench can't read this session"))
    }
}

// MARK: The decisions

struct RemoteDecideTests {
    @Test func approveChecksTheVersionFirst() {
        #expect(RemoteDecide.approve(version: "ver-1", session: root, fresh: nil) == .answer(.unavailable))
        #expect(RemoteDecide.approve(version: "ver-1", session: root, fresh: read("awaiting_plan_approval", version: "ver-1"))
                == .write(.approvePlan(frame: root)))
        for fresh in [read("awaiting_plan_approval", version: "ver-2"), read("processing", version: "ver-1"),
                      read("awaiting_plan_approval", version: "ver-1", approval: .yes),
                      read("awaiting_plan_approval", version: "ver-1", approval: .unclear)] {
            guard case .answer(let result) = RemoteDecide.approve(version: "ver-1", session: root, fresh: fresh) else {
                Issue.record("wrote for \(fresh.status)")
                continue
            }
            #expect(result.result == .changed)
        }
    }

    @Test(arguments: [
        (RemoteWriteResult(status: 200, bodyStatus: "accepted"), RemoteActionResult.Result.approved),
        (RemoteWriteResult(status: 400, code: "plan_already_approved"), .approved),
        (RemoteWriteResult(status: 400, code: "plan_frame_processing"), .changed),
        (RemoteWriteResult(status: 400, noPlanAwaiting: true), .changed),
        (RemoteWriteResult(status: 200, bodyStatus: "buffered"), .unavailable),
        (RemoteWriteResult(status: 200, isJSON: false), .unavailable),
        (RemoteWriteResult(status: 400, code: "something_new"), .unavailable),
        (RemoteWriteResult(status: 401), .unavailable),
        (RemoteWriteResult(status: 403, code: "csrf_stale"), .unavailable),
        (RemoteWriteResult(status: 404), .unavailable),
        (RemoteWriteResult(status: 405), .unavailable),
    ])
    func approveReplies(_ reply: RemoteWriteResult, _ expected: RemoteActionResult.Result) {
        #expect(RemoteDecide.approved(reply).result == expected)
    }

    @Test func noReplyIsUnavailable() {
        #expect(RemoteDecide.approved(nil) == .unavailable)
        #expect(RemoteDecide.answered(nil, request: .cancel(toolID: "t")) == .unavailable)
        #expect(RemoteDecide.messaged(nil, status: "completed") == .unavailable)
        #expect(RemoteActionResult.unavailable.sentence == "Couldn't do that from here. Open it on your Mac.")
    }

    @Test func anAnswerMustMatchTheQuestionStillWaiting() {
        let waiting = read("awaiting_user_response", asks: [buffers])
        let full = ["Which buffer?": "HEPES", "How many replicates?": "Three"]
        #expect(RemoteDecide.answer(.answer(toolID: "toolu_1", answers: full), session: root, fresh: waiting)
                == .write(.answer(frame: root, toolID: "toolu_1", answers: full)))
        let changed: [(RemoteActionRequest, SessionProjection?)] = [
            (.answer(toolID: "toolu_1", answers: full), read("processing", asks: [buffers])),
            (.answer(toolID: "toolu_2", answers: full), waiting),
            (.answer(toolID: "toolu_1", answers: ["Which buffer?": "HEPES"]), waiting),
            (.answer(toolID: "toolu_1", answers: full.merging(["Extra?": "x"]) { a, _ in a }), waiting),
            (.answer(toolID: "toolu_1", answers: ["Which buffer? ": "HEPES", "How many replicates?": "Three"]), waiting),
            (.cancel(toolID: "toolu_1"), read("awaiting_user_response", asks: [nil])),
        ]
        for (request, fresh) in changed {
            guard case .answer(let result) = RemoteDecide.answer(request, session: root, fresh: fresh) else {
                Issue.record("wrote \(request)")
                continue
            }
            #expect(result.result == .changed)
        }
        #expect(RemoteDecide.answer(.cancel(toolID: "toolu_1"), session: root, fresh: nil) == .answer(.unavailable))
    }

    @Test func chooseForMeAnswersEveryQuestionAndCancelSendsNone() {
        let waiting = read("awaiting_user_response", asks: [buffers])
        #expect(RemoteDecide.answer(.chooseForMe(toolID: "toolu_1"), session: root, fresh: waiting)
                == .write(.answer(frame: root, toolID: "toolu_1", answers: [
                    "Which buffer?": "Use your best judgment for this question",
                    "How many replicates?": "Use your best judgment for this question",
                ])))
        #expect(RemoteDecide.answer(.cancel(toolID: "toolu_1"), session: root, fresh: waiting)
                == .write(.cancel(frame: root, toolID: "toolu_1")))
    }

    @Test func answerReplies() {
        let answer = RemoteActionRequest.answer(toolID: "t", answers: [:])
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 200, bodyStatus: "accepted"), request: answer)
                == RemoteActionResult(result: .sent, sentence: "Answer sent."))
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 200, bodyStatus: "buffered"), request: .chooseForMe(toolID: "t")).result == .sent)
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 200, bodyStatus: "accepted"), request: .cancel(toolID: "t")).sentence
                == "Question cancelled.")
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 200, bodyStatus: "already_resolved"), request: answer).result == .changed)
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 400, staleInput: true), request: answer).result == .changed)
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 400), request: answer).result == .unavailable)
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 200), request: answer).result == .unavailable)
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 200, isJSON: false, bodyStatus: "accepted"), request: answer).result == .unavailable)
        #expect(RemoteDecide.answered(RemoteWriteResult(status: 404), request: answer).result == .unavailable)
    }

    @Test func aMessageGoesToTheFreshAgentOnlyWhenTheStatusAllows() {
        let request = RemoteActionRequest.message(text: "Try again", intentID: intent)
        #expect(RemoteDecide.message(request, session: root, fresh: read("failed", agent: "specialist-7"))
                == .write(.message(frame: root, agent: "specialist-7", projectID: "proj-1", text: "Try again", intentID: intent)))
        // No project in the fresh read: nothing is sent (`/api/request` without one makes a project).
        #expect(RemoteDecide.message(request, session: root, fresh: read("failed", agent: "specialist-7", project: nil))
                == .answer(.unavailable))
        for status in ["completed", "success", "processing", "cancelled"] {
            guard case .write = RemoteDecide.message(request, session: root, fresh: read(status)) else {
                Issue.record("no write for \(status)")
                continue
            }
        }
        for status in ["awaiting_user_response", "awaiting_plan_approval", "replaced"] {
            guard case .answer(let result) = RemoteDecide.message(request, session: root, fresh: read(status)) else {
                Issue.record("wrote for \(status)")
                continue
            }
            #expect(result.result == .blocked)
        }
        #expect(RemoteDecide.message(request, session: root, fresh: read("completed", agent: nil)) == .answer(.unavailable))
        #expect(RemoteDecide.message(request, session: root, fresh: nil) == .answer(.unavailable))
    }

    @Test(arguments: [
        (RemoteWriteResult(status: 200, bodyStatus: "accepted"), "completed", RemoteActionResult.Result.sent),
        (RemoteWriteResult(status: 200, bodyStatus: "accepted"), "failed", .resumed),
        (RemoteWriteResult(status: 200, bodyStatus: "accepted"), "cancelled", .resumed),
        (RemoteWriteResult(status: 200, bodyStatus: "message_queued"), "processing", .queued),
        (RemoteWriteResult(status: 200, bodyStatus: "already_delivered"), "completed", .sent),
        (RemoteWriteResult(status: 200, bodyStatus: "already_retracted"), "processing", .unavailable),
        (RemoteWriteResult(status: 200), "completed", .unavailable),
        (RemoteWriteResult(status: 200, isJSON: false), "completed", .unavailable),
        (RemoteWriteResult(status: 400, askPending: true), "completed", .blocked),
        (RemoteWriteResult(status: 400), "completed", .unavailable),
        (RemoteWriteResult(status: 404), "completed", .unavailable),
        (RemoteWriteResult(status: 409), "completed", .unavailable),
        (RemoteWriteResult(status: 429), "processing", .blocked),
        (RemoteWriteResult(status: 503), "completed", .unavailable),
    ])
    func messageReplies(_ reply: RemoteWriteResult, _ status: String, _ expected: RemoteActionResult.Result) {
        #expect(RemoteDecide.messaged(reply, status: status).result == expected)
    }
}

// MARK: The setting

struct RemoteActionsSettingTests {
    @Test func onUnlessTurnedOff() throws {
        let name = "bench-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(RemoteSessions.actionsSetting(defaults))
        defaults.set(false, forKey: SettingsKey.remoteActions)
        #expect(!RemoteSessions.actionsSetting(defaults))
        // As `-remoteActions NO` on the command line gives it.
        defaults.set("NO", forKey: SettingsKey.remoteActions)
        #expect(!RemoteSessions.actionsSetting(defaults))
        defaults.set(true, forKey: SettingsKey.remoteActions)
        #expect(RemoteSessions.actionsSetting(defaults))
    }
}

// MARK: The limit

struct ActionLimiterTests {
    @Test func sixAMinutePerDevice() {
        var limiter = ActionLimiter()
        let start = Date(timeIntervalSince1970: 1_791_833_400)
        func allow(_ device: String, _ second: Double) -> Bool { limiter.allow(device, at: start.addingTimeInterval(second)) }
        for second in 0..<6 {
            let allowed = allow("phone", Double(second))
            #expect(allowed)
        }
        let seventh = allow("phone", 10), other = allow("tablet", 10), stillOver = allow("phone", 59.5), later = allow("phone", 60)
        #expect(!seventh)
        #expect(other)
        #expect(!stillOver)
        #expect(later)
    }
}

// MARK: The flow, against a fake daemon

/// Stands in for the page: answers reads from a table, records every read
/// and write, and never reaches anything.
@MainActor
private final class FakePage {
    var reads: [String: SessionProjection] = [:]
    var reply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted")
    var actionsOn = true
    var known: [SessionStatus] = [Fixture.session(root, .needsInput, reason: .plan, title: "Made-up session")]
    var cardPlan: PlanPreview?
    var document: PlanDocument? = PlanDocument(summary: "Made-up plan", steps: 2, stepTitles: ["One", "Two"], confidence: "high")
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var readLog: [String] = []
    private(set) var planReads: [String] = []
    private(set) var writes: [RemoteWrite] = []

    func sessions() -> RemoteSessions {
        RemoteSessions(dependencies: RemoteSessions.Dependencies(
            actionsOn: { [unowned self] in self.actionsOn },
            known: { [unowned self] in self.known },
            cardPlan: { [unowned self] _ in self.cardPlan },
            read: { [unowned self] id, turns in
                self.readLog.append(turns ? "turns" : "frame")
                await Task.yield()
                guard let read = self.reads[id] else { return nil }
                return turns ? read : read.withoutTurns
            },
            readPlan: { [unowned self] version in
                self.planReads.append(version)
                return self.document
            },
            write: { [unowned self] write in
                self.writes.append(write)
                return self.reply
            },
            now: { [unowned self] in self.now }))
    }
}

private func decode(_ reply: RemoteActionReply) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any] ?? [:]
}

@MainActor
struct RemoteSessionsTests {
    private let page = FakePage()

    @Test func actionsOffIs403AndReadsNothing() async {
        page.actionsOn = false
        page.reads[root] = read("awaiting_plan_approval", version: "ver-1")
        let reply = await page.sessions().act(.approve, session: root, device: "d", body: body(#"{"version":"ver-1"}"#))
        #expect(reply.status == 403)
        #expect(decode(reply)["sentence"] as? String == "Actions are off in Bench's Settings")
        #expect(page.readLog.isEmpty)
        #expect(page.writes.isEmpty)
    }

    @Test func theSeventhActionInAMinuteIs429() async {
        let sessions = page.sessions()
        for _ in 0..<6 {
            #expect(await sessions.act(.message, session: root, device: "d", body: body("{}")).status == 400)
        }
        #expect(await sessions.act(.message, session: root, device: "d", body: body("{}")).status == 429)
        #expect(await sessions.act(.message, session: root, device: "other", body: body("{}")).status == 400)
        page.now = page.now.addingTimeInterval(61)
        #expect(await sessions.act(.message, session: root, device: "d", body: body("{}")).status == 400)
    }

    @Test func anUnknownSessionIs404AndABadBody400() async {
        let sessions = page.sessions()
        let other = "9f8e7d6c-5b4a-4321-8fed-cba987654321"
        #expect(await sessions.act(.approve, session: other, device: "d", body: body(#"{"version":"v"}"#)).status == 404)
        #expect(await sessions.act(.approve, session: root, device: "d", body: body(#"{"version":"a/b"}"#)).status == 400)
        #expect(await sessions.sessionJSON(other) == nil)
        #expect(page.readLog.isEmpty)
    }

    @Test func approveReadsAfreshThenWrites() async {
        page.reads[root] = read("awaiting_plan_approval", version: "ver-1")
        let reply = await page.sessions().act(.approve, session: root, device: "d", body: body(#"{"version":"ver-1"}"#))
        #expect(reply.status == 200)
        #expect(decode(reply)["result"] as? String == "approved")
        #expect(page.readLog == ["frame"])
        #expect(page.writes == [.approvePlan(frame: root)])
    }

    @Test func aChangedPlanWritesNothing() async {
        page.reads[root] = read("awaiting_plan_approval", version: "ver-2")
        let reply = await page.sessions().act(.approve, session: root, device: "d", body: body(#"{"version":"ver-1"}"#))
        #expect(decode(reply)["result"] as? String == "changed")
        #expect(page.writes.isEmpty)
    }

    @Test func anUnreadableSessionWritesNothing() async {
        let reply = await page.sessions().act(.message, session: root, device: "d", body: body(#"{"text":"Hi","id":"\#(intent)"}"#))
        #expect(decode(reply) as NSDictionary == ["result": "unavailable", "sentence": "Couldn't do that from here. Open it on your Mac."])
        #expect(page.writes.isEmpty)
    }

    @Test func aMessageWhileWorkingIsQueuedToTheRootsOwnAgent() async {
        page.reads[root] = read("processing", agent: "specialist-7", project: "proj-1")
        page.reply = RemoteWriteResult(status: 200, bodyStatus: "message_queued")
        let reply = await page.sessions().act(.message, session: root, device: "d", body: body(#"{"text":" Use HEPES ","id":"\#(intent)"}"#))
        #expect(decode(reply)["result"] as? String == "queued")
        #expect(page.writes == [.message(frame: root, agent: "specialist-7", projectID: "proj-1", text: "Use HEPES", intentID: intent)])
    }

    @Test func anAnswerIsSent() async {
        page.reads[root] = read("awaiting_user_response", asks: [buffers])
        let reply = await page.sessions().act(.answer, session: root, device: "d",
                                              body: body(#"{"toolId":"toolu_1","action":"chooseForMe"}"#))
        #expect(decode(reply)["result"] as? String == "sent")
        #expect(page.writes.count == 1)
    }

    // MARK: Reading

    @Test func aBurstReadsThePageOnceForFiveSeconds() async throws {
        page.reads[root] = read("completed", turns: [])
        let sessions = page.sessions()
        async let first = sessions.sessionJSON(root)
        async let second = sessions.sessionJSON(root)
        let both = await [first, second]
        #expect(both.allSatisfy { $0 != nil })
        #expect(page.readLog == ["turns"])
        page.now = page.now.addingTimeInterval(4.9)
        _ = await sessions.sessionJSON(root)
        #expect(page.readLog == ["turns"])
        page.now = page.now.addingTimeInterval(0.2)
        _ = await sessions.sessionJSON(root)
        #expect(page.readLog == ["turns", "turns"])
        // Held no longer than that.
        page.now = page.now.addingTimeInterval(6)
        sessions.dropExpired()
        #expect(sessions.cachedSessions.isEmpty)
    }

    @Test func whatWasHeldGoesAtEveryAskNotOnlyInAPause() async {
        let other = "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6"
        page.reads[root] = read("completed", turns: [])
        page.reads[other] = read("completed", turns: [])
        page.known.append(Fixture.session(other, .running, title: "Another made-up session"))
        let sessions = page.sessions()
        _ = await sessions.sessionJSON(root)
        #expect(sessions.cachedSessions == [root])
        // Phone after phone keeps asking, never pausing: still nothing older than 5 s stays.
        page.now = page.now.addingTimeInterval(6)
        _ = await sessions.sessionJSON(other)
        #expect(sessions.cachedSessions == [other])
    }

    @Test func anActionDropsWhatWasHeld() async {
        page.reads[root] = read("completed", turns: [])
        let sessions = page.sessions()
        _ = await sessions.sessionJSON(root)
        _ = await sessions.act(.message, session: root, device: "d", body: body(#"{"text":"Hi","id":"\#(intent)"}"#))
        _ = await sessions.sessionJSON(root)
        #expect(page.readLog == ["turns", "frame", "turns"])
    }

    @Test func thePlanIsReadForAPlanWaitingOnTheRoot() async throws {
        page.reads[root] = read("awaiting_plan_approval", version: "ver-9", turns: [])
        let json = try #require(await page.sessions().sessionJSON(root))
        let session = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let plan = session["plan"] as? [String: Any]
        #expect(plan?["version"] as? String == "ver-9")
        #expect(plan?["summary"] as? String == "Made-up plan")
        #expect((session["can"] as? [String: Any])?["approve"] as? Bool == true)
        #expect(page.planReads == ["ver-9"])
    }

    @Test func theCardsPlanIsUsedWhenItIsTheSameVersion() async throws {
        page.reads[root] = read("awaiting_plan_approval", version: "ver-9", turns: [])
        page.cardPlan = PlanPreview(summary: "From the card", steps: 1, confidence: nil, versionID: "ver-9", artifactID: nil)
        let json = try #require(await page.sessions().sessionJSON(root))
        #expect(String(decoding: json, as: UTF8.self).contains("From the card"))
        #expect(page.planReads.isEmpty)
    }

    @Test func unreadableFallsBackToVersionOne() async throws {
        page.cardPlan = PlanPreview(summary: "From the card", steps: 1, confidence: nil, versionID: "ver-9", artifactID: nil)
        let json = try #require(await page.sessions().sessionJSON(root))
        let session = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(session["readable"] as? Bool == false)
        #expect((session["plan"] as? [String: Any])?["summary"] as? String == "From the card")
        #expect(session["turns"] is NSNull)
        #expect((session["can"] as? [String: Any])?["why"] as? String == "Bench can't read this session")
    }
}

// MARK: `--demo remote`

@MainActor
struct RemoteDemoActionsTests {
    private func demoSessions() -> ([SessionStatus], RemoteSessions) {
        func make(_ suffix: String, _ title: String, _ state: SessionState, _ reason: WaitingReason? = nil) -> SessionStatus {
            Fixture.session("00000000-0000-4000-8000-0000000000\(suffix)", state, reason: reason, title: title)
        }
        let sessions = [make("d1", "Protein stability screen", .needsInput, .question),
                        make("d2", "Batch effect check", .needsInput, .plan),
                        make("d3", "Figure 2 rebuild", .error),
                        make("d4", "Literature sweep", .running),
                        make("d6", "Primer design", .finished),
                        make("d7", "Gel quantification", .needsInput, .question)]
        let preview = PlanPreview(summary: "Made-up plan", steps: 4, confidence: "high", versionID: "demo", artifactID: nil)
        return (sessions, RemoteSessions.demo(reads: Demo.remoteReads(sessions), known: { sessions },
                                              cardPlan: { $0 == sessions[1].id ? preview : nil }))
    }

    private func can(_ sessions: RemoteSessions, _ id: String) async -> [String: Any] {
        guard let json = await sessions.sessionJSON(id),
              let session = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return [:] }
        return session["can"] as? [String: Any] ?? [:]
    }

    @Test func eachMadeUpSessionOffersSomethingDifferent() async {
        let (list, sessions) = demoSessions()
        #expect(await can(sessions, list[0].id)["answer"] as? Bool == true)
        #expect(await can(sessions, list[1].id)["approve"] as? Bool == true)
        #expect(await can(sessions, list[2].id)["message"] as? String == "resume")
        #expect(await can(sessions, list[3].id)["message"] as? String == "queue")
        #expect(await can(sessions, list[4].id)["message"] as? String == "send")
        #expect(await can(sessions, list[5].id)["why"] as? String == "Bench can't read this session")
    }

    @Test func theDemosActionsSucceedWithMadeUpResults() async {
        let (list, sessions) = demoSessions()
        let approve = await sessions.act(.approve, session: list[1].id, device: "d", body: body(#"{"version":"demo"}"#))
        #expect(decode(approve)["result"] as? String == "approved")
        let answer = await sessions.act(.answer, session: list[0].id, device: "d",
                                        body: body(#"{"toolId":"demo-ask","answers":{"Which buffer should the screen start with?":"HEPES pH 7.5"}}"#))
        #expect(decode(answer)["result"] as? String == "sent")
        let queued = await sessions.act(.message, session: list[3].id, device: "d", body: body(#"{"text":"Hi","id":"\#(intent)"}"#))
        #expect(decode(queued)["result"] as? String == "queued")
        let sent = await sessions.act(.message, session: list[4].id, device: "d", body: body(#"{"text":"Hi","id":"\#(intent)"}"#))
        #expect(decode(sent)["result"] as? String == "sent")
    }
}
