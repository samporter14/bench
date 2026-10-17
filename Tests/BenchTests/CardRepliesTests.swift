// CardRepliesTests.swift — answering more from the card, on made-up sessions:
// permission requests (the Mac's table is the phone's, said for the Mac),
// what to change in a plan (the write, its check, and the phone's own
// message to a waiting plan still refused), what Claude said before asking,
// the window's keys, stepping to the next session, and an answer chosen in a
// Mac notification. Nothing here reaches a page or a daemon.
import Foundation
import Testing
@testable import Bench

private let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
private let other = "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6"
private let helper = "2d9e4a6b-3c4d-4e5f-a0b1-c2d3e4f5a6b7"
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
private let intent2 = "2c5f39cb-3ab2-42e3-994a-1127e4ddb538"

private let buffer = SessionProjection.Question(
    question: "Which buffer should the made-up screen use?", header: "Buffer", multi: false,
    options: [.init(label: "HEPES", detail: nil), .init(label: "Tris", detail: nil)])

private func ask(toolID: String = "toolu_made_up_1") -> QuestionAsk {
    QuestionAsk(toolID: toolID, items: [buffer])
}

/// A read-only tool from a listed source: the one kind besides code that may be allowed once.
private let readOnlyTool = PermissionRequest(requestID: "req-tool", toolID: "tool-1", mode: "parked", kind: "mcp_tool",
                                             frame: session, tool: "search_made_up_papers", server: "Made-up Library",
                                             source: "directory", readOnly: true)
private let code = PermissionRequest(requestID: "req-code", toolID: "tool-2", kind: "local_exec", frame: session,
                                     tool: "python", code: "print('made-up plate count')")
private let site = PermissionRequest(requestID: "req-net", toolID: "tool-3", mode: "parked", kind: "network",
                                     frame: session, target: "genomes.example.org")
private let email = PermissionRequest(requestID: "req-mail", toolID: "tool-4", mode: "parked", kind: "contact_email",
                                      frame: session)

private func waiting(_ request: PermissionRequest?, status: String = "processing",
                     turns: [SessionProjection.Turn]? = []) -> SessionProjection {
    SessionProjection(status: status, agentName: "OPERON", projectID: "proj_example", turns: turns, permission: request)
}

private func planRead(version: String = "ver_made_up_1", status: String = "awaiting_plan_approval") -> SessionProjection {
    SessionProjection(status: status, agentName: "OPERON", projectID: "proj_example", planVersion: version)
}

private let plan = PlanPreview(summary: "Screen four made-up buffers", steps: 4, confidence: "high",
                               versionID: "ver_made_up_1", artifactID: nil)

// MARK: The write and its check

struct PlanFeedbackWriteTests {
    private func build(_ write: RemoteWrite) -> [String: Any]? {
        let script = PageScript(SessionWriterScript.builder)
        guard let data = try? JSONSerialization.data(withJSONObject: write.arguments),
              let out = script.callJSON("benchBuildWrite", [String(decoding: data, as: UTF8.self)]) else { return nil }
        #expect(script.exception == nil)
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
    }

    private func sorted(_ value: Any?) -> String {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Exactly the message the session's own composer makes, with no
    /// `plan_mode` at all: the session keeps its own.
    @Test func whatToChangeIsAMessageWithNoPlanMode() {
        let write = build(.planFeedback(frame: session, agent: "OPERON", projectID: "proj_example",
                                        text: "Add a made-up control plate.", intentID: intent))
        #expect(write?["path"] as? String == "/api/request")
        #expect(sorted(write?["body"]) == #"{"input_data":{"request":"Add a made-up control plate."},"intent_id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427","project_id":"proj_example","root_frame_id":"0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5","target_agent":"OPERON"}"#)
        #expect((write?["body"] as? [String: Any])?["plan_mode"] == nil)
    }

    @Test func anythingOutOfShapeBuildsNothing() {
        let refused: [RemoteWrite] = [
            .planFeedback(frame: session, agent: "OPERON", projectID: "proj_example", text: "  ", intentID: intent),
            .planFeedback(frame: session, agent: "OPERON", projectID: "proj_example", text: "{{artifact:x}}", intentID: intent),
            .planFeedback(frame: session, agent: "OPERON", projectID: "", text: "Fine.", intentID: intent),
            .planFeedback(frame: session, agent: "", projectID: "proj_example", text: "Fine.", intentID: intent),
            .planFeedback(frame: session, agent: "OPERON", projectID: "proj_example", text: "Fine.", intentID: "not-a-uuid"),
            .planFeedback(frame: "short", agent: "OPERON", projectID: "proj_example", text: "Fine.", intentID: intent),
            .planFeedback(frame: session, agent: "OPERON", projectID: "proj_example",
                          text: String(repeating: "a", count: 4_001), intentID: intent),
        ]
        for write in refused {
            let script = PageScript(SessionWriterScript.builder)
            let data = try? JSONSerialization.data(withJSONObject: write.arguments)
            #expect(script.callJSON("benchBuildWrite", [data.map { String(decoding: $0, as: UTF8.self) }]) == "null")
        }
    }

    @Test func theRequestIsCheckedAsAPhoneMessageIs() {
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: "  Drop step 3. ", intentID: intent)
                == .planFeedback(version: "ver_1", text: "Drop step 3.", intentID: intent))
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: "   ", intentID: intent) == nil)
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: "{\"file_path\":\"x\"}", intentID: intent) == nil)
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver/1", text: "Fine.", intentID: intent) == nil)
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: "Fine.", intentID: intent.uppercased()) == nil)
        #expect(RemoteActionRequest.checkedPlanFeedback(version: "ver_1", text: String(repeating: "a", count: 4_001),
                                                        intentID: intent) == nil)
    }

    @Test func onlyThePlanShownWhileItStillWaits() {
        let request = RemoteActionRequest.planFeedback(version: "ver_made_up_1", text: "Fine.", intentID: intent)
        #expect(RemoteDecide.planFeedback(request, session: session, fresh: planRead())
                == .write(.planFeedback(frame: session, agent: "OPERON", projectID: "proj_example", text: "Fine.", intentID: intent)))
        #expect(RemoteDecide.planFeedback(request, session: session, fresh: planRead(version: "ver_made_up_2"))
                == .answer(RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.planChanged)))
        #expect(RemoteDecide.planFeedback(request, session: session, fresh: planRead(status: "processing"))
                == .answer(RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.planGone)))
        #expect(RemoteDecide.planFeedback(request, session: session, fresh: nil) == .answer(.unavailable))
        let approved = SessionProjection(status: "awaiting_plan_approval", agentName: "OPERON", projectID: "proj_example",
                                         planVersion: "ver_made_up_1", approval: .yes)
        #expect(RemoteDecide.planFeedback(request, session: session, fresh: approved)
                == .answer(RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.planChanged)))
        let noProject = SessionProjection(status: "awaiting_plan_approval", agentName: "OPERON", projectID: nil,
                                          planVersion: "ver_made_up_1")
        #expect(RemoteDecide.planFeedback(request, session: session, fresh: noProject) == .answer(.unavailable))
    }

    @Test func theDaemonsRepliesMeanSentQueuedOrNot() {
        #expect(RemoteDecide.planFeedbackSent(RemoteWriteResult(status: 200, bodyStatus: "accepted")).result == .sent)
        #expect(RemoteDecide.planFeedbackSent(RemoteWriteResult(status: 200, bodyStatus: "already_delivered")).result == .sent)
        #expect(RemoteDecide.planFeedbackSent(RemoteWriteResult(status: 200, bodyStatus: "message_queued")).result == .queued)
        #expect(RemoteDecide.planFeedbackSent(RemoteWriteResult(status: 429)).result == .blocked)
        #expect(RemoteDecide.planFeedbackSent(RemoteWriteResult(status: 200, isJSON: false, bodyStatus: "accepted")) == .unavailable)
        #expect(RemoteDecide.planFeedbackSent(RemoteWriteResult(status: 500)) == .unavailable)
        #expect(RemoteDecide.planFeedbackSent(nil) == .unavailable)
    }
}

/// The page, as `RemoteSessions` reads and writes it.
@MainActor
private final class FakePage {
    var actionsOn = true
    var read: SessionProjection? = planRead()
    private(set) var writes: [RemoteWrite] = []

    func sessions() -> RemoteSessions {
        RemoteSessions(dependencies: RemoteSessions.Dependencies(
            actionsOn: { [unowned self] in self.actionsOn },
            known: { [Fixture.session(session, .needsInput, reason: .plan)] },
            cardPlan: { _ in nil },
            read: { [unowned self] _, _ in self.read },
            readPlan: { _ in nil },
            write: { [unowned self] write in
                self.writes.append(write)
                return RemoteWriteResult(status: 200, bodyStatus: "accepted")
            },
            now: { Date(timeIntervalSince1970: 1_792_000_000) }))
    }
}

@MainActor
struct PlanFeedbackCoreTests {
    private let page = FakePage()

    @Test func theMacSendsWhatToChangeThroughTheCore() async {
        page.actionsOn = false
        let sessions = page.sessions()
        let request = RemoteActionRequest.planFeedback(version: "ver_made_up_1", text: "Add a control.", intentID: intent)
        let result = await sessions.respond(request, session: session)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising))
        #expect(page.writes == [.planFeedback(frame: session, agent: "OPERON", projectID: "proj_example",
                                              text: "Add a control.", intentID: intent)])
    }

    /// The phone is as it was: a message to a waiting plan is refused, and
    /// it has no route that makes what to change.
    @Test func thePhonesMessageToAWaitingPlanIsStillRefused() async {
        let sessions = page.sessions()
        let body = Data(#"{"text":"Add a control.","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#.utf8)
        let reply = await sessions.act(.message, session: session, device: "made-up-phone", body: body)
        let result = (try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any])?["result"] as? String
        #expect(result == "blocked")
        #expect(page.writes.isEmpty)
        #expect(RemoteAction.allCases.map(\.rawValue).sorted() == ["answer", "approve", "message", "permission"])
    }
}

// MARK: The Mac's table

struct MacPermissionTableTests {
    /// Every kind, every shape: the Mac may do exactly what the phone may.
    @Test func theMacMayDoExactlyWhatThePhoneMay() {
        var requests: [PermissionRequest] = [readOnlyTool, code, site, email]
        for kind in PermissionKind.allCases {
            requests.append(PermissionRequest(requestID: "r", toolID: "t", kind: kind.rawValue, frame: session,
                                              tool: kind == .localExec ? "python" : "made_up", source: "directory",
                                              readOnly: true, code: kind == .localExec ? "print(1)" : nil))
            requests.append(PermissionRequest(requestID: "r", toolID: "t", kind: kind.rawValue, frame: session,
                                              shape: false))
            requests.append(PermissionRequest(requestID: nil, toolID: "t", kind: kind.rawValue, frame: session))
        }
        requests.append(PermissionRequest(requestID: "r", toolID: "t", kind: "ask", frame: helper, chain: [helper, session]))
        requests.append(PermissionRequest(requestID: "r", toolID: "t", kind: "made_up_kind", frame: session))
        for request in requests {
            let phone = RemotePermission.decide(request, actionsOn: true)
            let mac = RemotePermission.decideOnMac(request)
            #expect(mac.canAllow == phone.canAllow && mac.canDeny == phone.canDeny, "\(request.kind)")
            #expect(mac.why == phone.why.map(RemotePermission.onMac), "\(request.kind)")
            #expect(!(mac.why ?? "").localizedCaseInsensitiveContains("phone"), "\(request.kind)")
        }
    }

    @Test func everyPhoneSentenceHasAMacOne() {
        let sentences = [RemotePermission.Why.lasting, RemotePermission.Why.onMac, RemotePermission.Why.unknown,
                         RemotePermission.Why.unreadable, RemotePermission.Why.language, RemotePermission.Why.shared,
                         RemotePermission.Why.codeLong, RemotePermission.Why.codeOdd, RemotePermission.Why.codeLines,
                         RemotePermission.Why.toolIdShared, RemotePermission.Why.helperAsked, RemotePermission.Why.noCode,
                         RemotePermission.Why.notReadOnly, RemotePermission.Why.source, RemoteActionResult.unavailable.sentence]
        for sentence in sentences {
            let mac = RemotePermission.onMac(sentence)
            #expect(mac != sentence)
            #expect(!mac.localizedCaseInsensitiveContains("phone"))
            #expect(!mac.localizedCaseInsensitiveContains("on your Mac"))
        }
    }

    @Test func aReadOnlyToolMayBeAllowedCodeIsReadFirstASiteOnlyDenied() {
        #expect(RemotePermission.decideOnMac(readOnlyTool).canAllow)
        #expect(RemotePermission.decideOnMac(code).canAllow)
        let net = RemotePermission.decideOnMac(site)
        #expect(!net.canAllow && net.canDeny)
        let mail = RemotePermission.decideOnMac(email)
        #expect(!mail.canAllow && !mail.canDeny)
    }
}

// MARK: What the card reads

struct CardReadTests {
    @Test func aRequestAtTheHeadOfTheQueueIsTheCards() {
        #expect(QuestionCardState.from(waiting(site)) == .permission(site))
        #expect(QuestionCardState.from(waiting(nil)) == .unsupported)
        // The root's own question comes first.
        let both = SessionProjection(status: "awaiting_user_response", agentName: "OPERON", projectID: "proj_example",
                                     asks: [ask()], turns: [], permission: site)
        #expect(QuestionCardState.from(both) == .ready(ask()))
    }

    @Test func everyWaitButAPlansIsRead() {
        for reason in WaitingReason.allCases {
            #expect(QuestionCardState.reads(reason) == (reason != .plan), "\(reason)")
        }
        #expect(QuestionCardState.reads(nil))
    }

    @Test func whatClaudeSaidLastBeforeAsking() {
        let turns: [SessionProjection.Turn] = [
            .init(role: .you, at: nil, text: "Screen the made-up buffers."),
            .init(role: .claude, at: nil, text: "  I compared three made-up buffers.  "),
            .init(role: .you, at: nil, text: "Go on."),
        ]
        #expect(QuestionCardState.context(waiting(nil, turns: turns)) == "I compared three made-up buffers.")
        #expect(QuestionCardState.context(waiting(nil, turns: [.init(role: .claude, at: nil, text: "  ")])) == nil)
        #expect(QuestionCardState.context(waiting(nil, turns: nil)) == nil)
        #expect(QuestionCardState.context(nil) == nil)
    }
}

// MARK: The window's keys

struct ReplyKeysTests {
    @Test func commandNumbersPickThenOtherThenNothing() {
        #expect(ReplyKeys.pick(1, options: 3) == .option(0))
        #expect(ReplyKeys.pick(3, options: 3) == .option(2))
        #expect(ReplyKeys.pick(4, options: 3) == .other)
        #expect(ReplyKeys.pick(5, options: 3) == .none)
        #expect(ReplyKeys.pick(1, options: 0) == .other)
        #expect(ReplyKeys.pick(9, options: 12) == .option(8))
        #expect(ReplyKeys.pick(0, options: 3) == .none)
        #expect(ReplyKeys.pick(10, options: 12) == .none)
    }
}

// MARK: The replier

@MainActor
private final class FakeCore {
    var reads: [String: SessionProjection?] = [:]
    var plans: [String: PlanPreview] = [:]
    var ready = true
    var results: [RemoteActionResult] = []
    private(set) var requests: [RemoteActionRequest] = []
    private var intents = [intent, intent2]

    func dependencies() -> QuestionReplier.Dependencies {
        QuestionReplier.Dependencies(
            isEnabled: { true },
            isReady: { [unowned self] in self.ready },
            read: { [unowned self] id in
                await Task.yield()
                return self.reads[id] ?? nil
            },
            respond: { [unowned self] request, _ in
                self.requests.append(request)
                return self.results.isEmpty ? RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.answered)
                    : self.results.removeFirst()
            },
            plan: { [unowned self] in self.plans[$0] },
            newIntentID: { [unowned self] in
                let next = self.intents.removeFirst()
                self.intents.append(next)
                return next
            })
    }
}

@MainActor
struct CardRepliesTests {
    private let core = FakeCore()
    private let model = LabModel()

    private func waitingCard(_ id: String = session, reason: WaitingReason) -> SessionStatus {
        Fixture.session(id, .needsInput, reason: reason, title: "Made-up screen")
    }

    /// A card waiting for `reason` on top, read.
    private func card(_ reason: WaitingReason, read: SessionProjection?) async -> QuestionReplier {
        core.reads[session] = read
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        model.ingest(Fixture.snapshot(waitingCard(reason: reason)))
        let replier = QuestionReplier(model: model, dependencies: core.dependencies())
        replier.sync()
        await replier.settled()
        return replier
    }

    // Permission requests

    @Test func aToolsRequestIsReadAndAllowedOnceFromTheCard() async {
        let replier = await card(.tool, read: waiting(readOnlyTool))
        #expect(replier.cardState(for: session) == .permission(readOnlyTool))
        core.results = [RemoteActionResult(result: .allowed, sentence: PermissionDecide.Sentence.allowed)]
        let send = replier.decide(session, allow: true)
        #expect(replier.decide(session, allow: true) == nil, "one send per press")
        #expect(await send?.value == .sent(PermissionDecide.Sentence.allowed))
        #expect(core.requests == [.permission(id: "req-tool", allow: true, kind: "mcp_tool")])
        // Answered from the card itself, with no window to show it: nothing is kept.
        #expect(replier.permissionReplies[session] == nil)
        #expect(replier.contexts[session] == nil)
        #expect(!model.cards.contains { $0.id == LabCard.needsInput(waitingCard(reason: .tool)).id })
        #expect(replier.cardState(for: session) == nil)
    }

    @Test func whatTheTableDoesntOfferIsNeverSent() async {
        let replier = await card(.web, read: waiting(site))
        replier.decide(session, allow: true)
        await replier.settled()
        #expect(core.requests.isEmpty, "a site's allow is chosen in Capsid")
        core.results = [RemoteActionResult(result: .denied, sentence: PermissionDecide.Sentence.denied)]
        replier.decide(session, allow: false)
        await replier.settled()
        #expect(core.requests == [.permission(id: "req-net", allow: false, kind: "network")])
        let typed = await card(.other, read: waiting(email))
        typed.decide(session, allow: false)
        await typed.settled()
        #expect(core.requests.count == 1, "an email is typed in Capsid")
    }

    @Test func aChangedRequestIsShownInstead() async {
        let replier = await card(.tool, read: waiting(readOnlyTool))
        core.results = [RemoteActionResult(result: .changed, sentence: PermissionDecide.Sentence.changed)]
        core.reads[session] = waiting(site)
        replier.decide(session, allow: true)
        await replier.settled()
        #expect(replier.permissionReplies[session]?.request == site)
        #expect(replier.permissionReplies[session]?.phase == .changed(QuestionReplier.Sentence.requestChanged))
        #expect(replier.cardState(for: session) == .permission(site))
    }

    @Test func handledElsewhereLeavesNothingToDo() async {
        let replier = await card(.tool, read: waiting(readOnlyTool))
        core.results = [RemoteActionResult(result: .changed, sentence: PermissionDecide.Sentence.alreadyHandled)]
        core.reads[session] = waiting(nil)
        #expect(await replier.decide(session, allow: false)?.value == .closed(PermissionDecide.Sentence.alreadyHandled))
        // The card is still up and says so, with Open instead of Allow and Deny.
        #expect(replier.cardState(for: session) != nil)
        #expect(replier.permissionReplies[session]?.phase == .closed(PermissionDecide.Sentence.alreadyHandled))
        // Once the card goes, so does the reply.
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        replier.sync()
        #expect(replier.permissionReplies[session] == nil)
    }

    @Test func aFailureSaysTryAgainAndARefusalSaysWhyForTheMac() async {
        let replier = await card(.tool, read: waiting(readOnlyTool))
        core.results = [.unavailable,
                        RemoteActionResult(result: .unavailable, sentence: RemotePermission.Why.toolIdShared)]
        replier.decide(session, allow: true)
        await replier.settled()
        #expect(replier.permissionReplies[session]?.phase == .failed(QuestionReplier.Sentence.requestFailed))
        replier.decide(session, allow: true)
        await replier.settled()
        #expect(replier.permissionReplies[session]?.phase
                == .failed(RemotePermission.onMac(RemotePermission.Why.toolIdShared)))
        #expect(core.requests.count == 2)
    }

    @Test func aRequestThatStopsWaitingClosesItsReply() async {
        let replier = await card(.tool, read: waiting(readOnlyTool))
        #expect(replier.begin(session))
        replier.windowOpened(session)
        #expect(replier.mode(session) == .permission)
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        replier.sync()
        #expect(replier.permissionReplies[session]?.phase == .closed(QuestionReplier.Sentence.requestGone))
        replier.windowClosed(session)
        #expect(replier.permissionReplies[session] == nil)
    }

    @Test func theRequestCarriesWhatClaudeSaid() async {
        let said = [SessionProjection.Turn(role: .claude, at: nil, text: "I need the made-up library.")]
        let replier = await card(.tool, read: waiting(readOnlyTool, turns: said))
        #expect(replier.begin(session))
        #expect(replier.permissionReplies[session]?.context == "I need the made-up library.")
    }

    // What to change in a plan

    private func planCard() -> QuestionReplier {
        core.plans[session] = plan
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        model.ingest(Fixture.snapshot(waitingCard(reason: .plan)))
        return QuestionReplier(model: model, dependencies: core.dependencies())
    }

    @Test func aPlansCardIsNotReadHereButItsChangesAreSent() async {
        let replier = planCard()
        replier.sync()
        await replier.settled()
        #expect(replier.cards.isEmpty)
        #expect(!replier.begin(session), "Reply is for questions and requests")
        #expect(replier.begin(session, plan: true))
        replier.windowOpened(session)
        #expect(replier.mode(session) == .plan)
        #expect(!replier.canSendPlanFeedback(session), "nothing typed")
        replier.updatePlanFeedback(session, text: "Add a made-up control plate.")
        #expect(replier.canSendPlanFeedback(session))
        core.results = [RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising)]
        replier.submitPlanFeedback(session)
        replier.submitPlanFeedback(session)
        await replier.settled()
        #expect(core.requests == [.planFeedback(version: "ver_made_up_1", text: "Add a made-up control plate.",
                                                intentID: intent2)])
        #expect(replier.planReplies[session]?.phase == .sent(RemoteDecide.Sentence.revising))
        #expect(!model.cards.contains { $0.id == LabCard.needsInput(waitingCard(reason: .plan)).id })
    }

    /// A retry of the same words keeps their intent id, so the daemon knows
    /// it; new words get a new one.
    @Test func theSameWordsKeepTheirIntentID() async {
        let replier = planCard()
        #expect(replier.begin(session, plan: true))
        replier.updatePlanFeedback(session, text: "Drop step 3.")
        let first = replier.planReplies[session]?.intentID
        core.results = [.unavailable, .unavailable]
        replier.submitPlanFeedback(session)
        await replier.settled()
        #expect(replier.planReplies[session]?.phase == .failed(QuestionReplier.Sentence.feedbackFailed))
        #expect(replier.planReplies[session]?.text == "Drop step 3.")
        replier.updatePlanFeedback(session, text: "Drop step 3.")
        replier.submitPlanFeedback(session)
        await replier.settled()
        #expect(core.requests.map { if case .planFeedback(_, _, let id) = $0 { id } else { "" } } == [first, first])
        replier.updatePlanFeedback(session, text: "Drop step 4.")
        #expect(replier.planReplies[session]?.intentID != first)
    }

    @Test func aPlanThatChangedOrStoppedWaitingSendsNoMore() async {
        let replier = planCard()
        #expect(replier.begin(session, plan: true))
        replier.windowOpened(session)
        replier.updatePlanFeedback(session, text: "Drop step 3.")
        core.results = [RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.planChanged)]
        replier.submitPlanFeedback(session)
        await replier.settled()
        #expect(replier.planReplies[session]?.phase == .closed(QuestionReplier.Sentence.planChanged))
        #expect(replier.planReplies[session]?.text == "Drop step 3.", "still there to copy")
        #expect(!replier.canSendPlanFeedback(session))
        // The session runs again: a reply still open says so.
        replier.windowClosed(session)
        #expect(replier.planReplies[session] == nil, "closed with nothing to send: let go")
        #expect(replier.begin(session, plan: true))
        replier.windowOpened(session)
        #expect(replier.planReplies[session]?.phase == .editing)
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        replier.sync()
        #expect(replier.planReplies[session]?.phase == .closed(QuestionReplier.Sentence.planGone))
        core.plans[session] = nil
        #expect(!replier.begin(session, plan: true), "no plan shown, nothing to change")
    }

    @Test func whatReadsLikeAReferenceIsNeverSent() async {
        let replier = planCard()
        #expect(replier.begin(session, plan: true))
        replier.updatePlanFeedback(session, text: "Use {{artifact:made-up}} instead.")
        #expect(!replier.canSendPlanFeedback(session))
        replier.submitPlanFeedback(session)
        await replier.settled()
        #expect(core.requests.isEmpty)
    }

    // Next

    @Test func nextStepsThroughTheOtherCardsButAPlans() async {
        let third = "3e0f5b7c-4d5e-4f6a-b1c2-d3e4f5a6b7c8"
        model.ingest(Fixture.snapshot(Fixture.session(session, .running), Fixture.session(other, .running),
                                      Fixture.session(third, .running)))
        model.ingest(Fixture.snapshot(waitingCard(reason: .question), waitingCard(other, reason: .plan),
                                      waitingCard(third, reason: .tool)))
        let replier = QuestionReplier(model: model, dependencies: core.dependencies())
        #expect(replier.othersWaiting(besides: session) == [third])
        #expect(replier.othersWaiting(besides: third) == [session])
    }

    /// The window can open on a card that isn't on top yet: it is read then.
    @Test func aCardNotOnTopIsReadWhenTheWindowStepsToIt() async {
        let third = "3e0f5b7c-4d5e-4f6a-b1c2-d3e4f5a6b7c8"
        core.reads[third] = waiting(readOnlyTool)
        core.reads[session] = SessionProjection(status: "awaiting_user_response", agentName: "OPERON",
                                                projectID: "proj_example", asks: [ask()])
        model.ingest(Fixture.snapshot(Fixture.session(session, .running), Fixture.session(third, .running)))
        model.ingest(Fixture.snapshot(waitingCard(reason: .question), waitingCard(third, reason: .tool)))
        let replier = QuestionReplier(model: model, dependencies: core.dependencies())
        replier.sync()
        await replier.settled()
        let top = model.cards.compactMap(\.session).first?.id
        let below = top == session ? third : session
        #expect(replier.cardState(for: below) == nil)
        #expect(replier.prepare(below))
        await replier.settled()
        #expect(replier.cardState(for: below) != nil)
        #expect(replier.begin(below))
    }

    // From a notification

    @Test func anAnswerFromANotificationGoesThroughTheSameCheck() async {
        let read = SessionProjection(status: "awaiting_user_response", agentName: "OPERON", projectID: "proj_example",
                                     asks: [ask()])
        let replier = await card(.question, read: read)
        var draft = ReplyDraft(for: ask())
        draft.pick(1, in: 0, multi: false)
        let phase = await replier.answerFromNotification(session, ask: ask(), draft: draft)
        #expect(core.requests == [.answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Tris"])])
        #expect(phase == .sent(RemoteDecide.Sentence.answered))
        // Sent with no window to show it: nothing of it is kept.
        #expect(replier.replies[session] == nil)
    }

    /// A question's notification reads it when the card hasn't, and the card
    /// keeps that read, with what Claude said.
    @Test func theNotificationsReadIsKeptForTheCard() async {
        let said = [SessionProjection.Turn(role: .claude, at: nil, text: "Two made-up buffers held.")]
        core.reads[session] = SessionProjection(status: "awaiting_user_response", agentName: "OPERON",
                                                projectID: "proj_example", asks: [ask()], turns: said)
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        model.ingest(Fixture.snapshot(waitingCard(reason: .question)))
        let replier = QuestionReplier(model: model, dependencies: core.dependencies())
        #expect(await replier.askForNotification(session) == ask())
        #expect(replier.cardState(for: session) == .ready(ask()))
        #expect(replier.contexts[session] == "Two made-up buffers held.")
        core.reads[session] = waiting(site)
        #expect(await replier.askForNotification(session) == ask(), "the card's read, not another")
    }

    @Test func aNotificationAnswerBeforeThePageIsUpIsKeptForTheWindow() async {
        let read = SessionProjection(status: "awaiting_user_response", agentName: "OPERON", projectID: "proj_example",
                                     asks: [ask()])
        let replier = await card(.question, read: read)
        core.ready = false
        var draft = ReplyDraft(for: ask())
        draft.pick(0, in: 0, multi: false)
        let phase = await replier.answerFromNotification(session, ask: ask(), draft: draft)
        #expect(core.requests.isEmpty)
        #expect(phase == .failed(QuestionReplier.Sentence.failed))
        #expect(replier.replies[session]?.phase == .failed(QuestionReplier.Sentence.failed))
        #expect(replier.replies[session]?.draft.picks[0] == [0])
        core.ready = true
        replier.submit(session)
        await replier.settled()
        #expect(core.requests.count == 1)
    }
}

// MARK: A question's notification

struct NotificationAnswerTests {
    private let named = NotificationRules.Settings(enabled: true, authorized: true, showNames: true)

    @Test func onlyOneQuestionWithOneAnswerAndFewChoices() {
        let actions = NotificationRules.questionActions(for: ask(), settings: named)
        #expect(actions == NotificationRules.QuestionActions(toolID: "toolu_made_up_1", question: buffer.question,
                                                             choices: ["HEPES", "Tris"]))
        var hidden = named
        hidden.showNames = false
        #expect(NotificationRules.questionActions(for: ask(), settings: hidden) == nil, "the buttons would say what it asks")
        let several = SessionProjection.Question(question: "Which made-up readouts?", header: "", multi: true,
                                                 options: [.init(label: "A", detail: nil)])
        #expect(NotificationRules.questionActions(for: QuestionAsk(toolID: "t", items: [several]), settings: named) == nil)
        #expect(NotificationRules.questionActions(for: QuestionAsk(toolID: "t", items: [buffer, buffer]), settings: named) == nil)
        let five = SessionProjection.Question(question: "Which made-up plate?", header: "", multi: false,
                                              options: (1...5).map { .init(label: "P\($0)", detail: nil) })
        #expect(NotificationRules.questionActions(for: QuestionAsk(toolID: "t", items: [five]), settings: named) == nil)
        let typed = SessionProjection.Question(question: "Anything else?", header: "", multi: false, options: [])
        #expect(NotificationRules.questionActions(for: QuestionAsk(toolID: "t", items: [typed]), settings: named)?.choices == [])
    }

    @Test func theNotificationSaysTheQuestionOnceItIsRead() {
        let plain = NotificationRules.Content(id: "card-1", title: "Made-up screen", body: "Has a question · Example project",
                                              sound: false, sessionID: session, link: nil)
        let asked = NotificationRules.withQuestion(plain, ask: ask(), settings: named)
        #expect(asked.body == buffer.question)
        #expect(asked.question?.choices == ["HEPES", "Tris"])
        #expect(NotificationRules.withQuestion(plain, ask: nil, settings: named) == plain)
    }

    @Test func whatComesBackIsCheckedAgain() throws {
        let actions = NotificationRules.QuestionActions(toolID: "toolu_made_up_1", question: buffer.question,
                                                        choices: ["HEPES", "Tris"])
        let back = try #require(NotificationRules.QuestionActions(userInfo: actions.userInfo))
        #expect(back == actions)
        var bad = actions.userInfo
        bad["q.choices"] = ["A", "B", "C", "D", "E"]
        #expect(NotificationRules.QuestionActions(userInfo: bad) == nil)
        bad = actions.userInfo
        bad["q.tool"] = 5
        #expect(NotificationRules.QuestionActions(userInfo: bad) == nil)
        #expect(NotificationRules.QuestionActions(userInfo: [:]) == nil)
    }

    @Test func aButtonOrReplyMakesTheAnswerTheWindowWould() throws {
        let actions = NotificationRules.QuestionActions(toolID: "toolu_made_up_1", question: buffer.question,
                                                        choices: ["HEPES", "Tris"])
        let picked = try #require(actions.draft(actionID: "answer.1", typed: nil))
        #expect(QuestionAnswers.request(actions.ask, draft: picked)
                == .answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Tris"]))
        let typed = try #require(actions.draft(actionID: "reply", typed: "  Made-up MOPS "))
        #expect(QuestionAnswers.request(actions.ask, draft: typed)
                == .answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Made-up MOPS"]))
        #expect(actions.draft(actionID: "answer.2", typed: nil) == nil)
        #expect(actions.draft(actionID: "answer.x", typed: nil) == nil)
        #expect(actions.draft(actionID: "reply", typed: "   ") == nil)
        #expect(actions.draft(actionID: "reply", typed: String(repeating: "a", count: 1_001)) == nil)
        #expect(actions.draft(actionID: UUID().uuidString, typed: nil) == nil)
        #expect(NotificationRules.QuestionActions.categoryID(for: "needs-input-x") == "question.needs-input-x")
    }
}
