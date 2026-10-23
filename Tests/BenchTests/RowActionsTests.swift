// RowActionsTests.swift — acting from the activity list. What a needs-input
// card offers (`CardOffer`) is decided in one place that the card and the
// list's rows both read, and what a button does (`CardActions.perform`) goes
// through the card's own core: the replier's `decide`, the approver's
// `approve`, the reply window. On made-up sessions with fakes standing in for
// the page and the daemon: nothing here reaches either.
import Foundation
import Testing
@testable import Bench

private let first = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
private let second = "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6"
private let third = "2d9e4a6b-3c4d-4e5f-a0b1-c2d3e4f5a6b7"

private let buffer = SessionProjection.Question(
    question: "Which buffer should the made-up screen use?", header: "Buffer", multi: false,
    options: [.init(label: "HEPES", detail: nil), .init(label: "Tris", detail: nil)])
private let ask = QuestionAsk(toolID: "toolu_made_up_1", items: [buffer])

/// Read-only tool from a listed source: may be allowed once. Code: read first. A site: only denied.
/// An email request: neither (Open in Capsid).
private func readOnlyTool(_ frame: String) -> PermissionRequest {
    PermissionRequest(requestID: "req-tool", toolID: "tool-1", mode: "parked", kind: "mcp_tool", frame: frame,
                      tool: "search_made_up_papers", server: "Made-up Library", source: "directory", readOnly: true)
}
private func code(_ frame: String) -> PermissionRequest {
    PermissionRequest(requestID: "req-code", toolID: "tool-2", kind: "local_exec", frame: frame, tool: "python",
                      code: "print('made-up plate count')")
}
private func site(_ frame: String) -> PermissionRequest {
    PermissionRequest(requestID: "req-net", toolID: "tool-3", mode: "parked", kind: "network", frame: frame,
                      target: "genomes.example.org")
}
private func email(_ frame: String) -> PermissionRequest {
    PermissionRequest(requestID: "req-mail", toolID: "tool-4", mode: "parked", kind: "contact_email", frame: frame)
}

private let planPreview = PlanPreview(summary: "Screen four made-up buffers", steps: 4, confidence: "high",
                                      versionID: "ver_made_up_1", artifactID: nil)

// MARK: What a card offers, state by state

struct CardOfferTests {
    private func plan(_ state: PlanCardState?) -> CardOffer {
        CardOffer.of(reason: .plan, plan: state, question: nil, reply: nil, permission: nil)
    }

    private func question(_ state: QuestionCardState?, reply: ReplyPhase? = nil, permission: ReplyPhase? = nil,
                          reason: WaitingReason = .question) -> CardOffer {
        CardOffer.of(reason: reason, plan: nil, question: state, reply: reply, permission: permission)
    }

    @Test func aPlanOffersApproveOnceItIsReadAndRequestChangesBesideIt() {
        let ready = plan(.ready(planPreview))
        #expect(ready.lead == .button(.approve) && ready.hasOpen && ready.canRequestChanges)
        #expect(ready.rowActions == [.approve, .requestChanges])
        for state in [nil, .loading, .unavailable] as [PlanCardState?] {
            let offer = plan(state)
            #expect(offer.lead == .button(.open) && !offer.canRequestChanges)
            #expect(offer.rowActions.isEmpty, "nothing to do from a row but open it")
        }
    }

    @Test func aPlanThatIsBeingApprovedOrWasShowsItAsTheCardDoes() {
        let approving = plan(.approving(planPreview))
        #expect(approving.lead == .sending("Approving") && approving.hasOpen && approving.rowActions.isEmpty)
        let approved = plan(.approved(planPreview))
        #expect(approved.lead == .done("Approved") && !approved.hasOpen && approved.rowActions.isEmpty)
    }

    @Test func aPlanThatDidntApproveSaysWhyAndStillOffersRequestChanges() {
        let problem = plan(.problem("The plan changed.", planPreview))
        #expect(problem.lead == .button(.open) && problem.problem == "The plan changed.")
        #expect(problem.rowActions == [.requestChanges])
    }

    @Test func aQuestionOffersReplyAndShowsItsProgress() {
        let ready = question(.ready(ask))
        #expect(ready.lead == .button(.reply) && ready.hasOpen && !ready.hasDeny)
        #expect(ready.rowActions == [.reply])
        #expect(question(.ready(ask), reply: .editing).lead == .button(.reply))
        #expect(question(.ready(ask), reply: .failed("x")).lead == .button(.reply), "a failed send can be tried again")
        let sending = question(.ready(ask), reply: .sending)
        #expect(sending.lead == .sending("Sending the answer") && sending.hasOpen && sending.rowActions.isEmpty)
        #expect(question(.ready(ask), reply: .sent("Sent.")).lead == .done("Sent"))
    }

    /// A send that didn't go says why, wherever the offer is drawn (card, row, menu-bar home, Since You Left
    /// sheet): the same `problem` a permission request's failed send already had.
    @Test func aQuestionThatDidntSendSaysWhyAndTheDraftCanBeSentAgain() {
        for phase in [ReplyPhase.failed("Couldn't send it."), .changed("The question changed.")] {
            let offer = question(.ready(ask), reply: phase)
            let sentence = phase == .failed("Couldn't send it.") ? "Couldn't send it." : "The question changed."
            #expect(offer.problem == sentence, "\(phase)")
            #expect(offer.lead == .button(.reply) && offer.hasOpen && offer.rowActions == [.reply], "Reply is the retry")
        }
        let closed = question(.ready(ask), reply: .closed("Already answered."))
        #expect(closed.problem == "Already answered.")
        #expect(closed.lead == .button(.open) && closed.rowActions.isEmpty, "nothing left to answer: Open")
        // The ones that are not a failure say nothing.
        for phase in [ReplyPhase.editing, .sending, .sent("Sent.")] {
            #expect(question(.ready(ask), reply: phase).problem == nil, "\(phase)")
        }
    }

    @Test func aWaitThatCantBeAnsweredHereOffersOpenOnly() {
        #expect(question(.unsupported).lead == .button(.openInCapsid) && question(.unsupported).rowActions.isEmpty)
        for state in [nil, .loading, .unavailable] as [QuestionCardState?] {
            #expect(question(state).lead == .button(.open) && question(state).rowActions.isEmpty)
        }
    }

    @Test func aReadOnlyToolMayBeAllowedOnceOrDenied() {
        let offer = question(.permission(readOnlyTool(first)), reason: .tool)
        #expect(offer.lead == .button(.allowOnce) && offer.hasDeny && offer.laterHasOpen && !offer.hasOpen)
        #expect(offer.rowActions == [.allowOnce, .deny])
    }

    @Test func codeToRunIsReviewedFirst() {
        let offer = question(.permission(code(first)), reason: .other)
        #expect(offer.lead == .button(.review) && offer.hasDeny && offer.laterHasOpen)
        #expect(offer.rowActions == [.review, .deny])
    }

    @Test func aSiteIsOnlyDeniedHereAndAnEmailNotEvenThat() {
        let net = question(.permission(site(first)), reason: .web)
        #expect(net.lead == .button(.open) && net.hasDeny && !net.laterHasOpen)
        #expect(net.rowActions == [.deny])
        let mail = question(.permission(email(first)), reason: .other)
        #expect(mail.lead == .button(.openInCapsid) && !mail.hasDeny && mail.rowActions.isEmpty)
    }

    @Test func aPermissionRequestShowsHowItsSendWent() {
        let request = QuestionCardState.permission(readOnlyTool(first))
        #expect(question(request, permission: .sending).lead == .sending("Sending"))
        #expect(question(request, permission: .sending).rowActions.isEmpty)
        #expect(question(request, permission: .sent(PermissionDecide.Sentence.allowed)).lead == .done("Allowed once"))
        #expect(question(request, permission: .sent(PermissionDecide.Sentence.denied)).lead == .done("Denied"))
        let closed = question(request, permission: .closed("Already handled."))
        #expect(closed.lead == .button(.open) && closed.problem == "Already handled." && closed.rowActions.isEmpty)
        // Changed or failed: the buttons stay, with the sentence.
        for phase in [ReplyPhase.changed("It changed."), .failed("Couldn't send it.")] {
            let offer = question(request, permission: phase)
            #expect(offer.lead == .button(.allowOnce) && offer.rowActions == [.allowOnce, .deny])
            #expect(offer.problem == (phase == .changed("It changed.") ? "It changed." : "Couldn't send it."))
        }
    }

    @Test func aStateOfTheOtherKindIsNeverShown() {
        // A card waiting on a plan reads the plan's state only, and the rest the question's.
        let mixed = CardOffer.of(reason: .plan, plan: nil, question: .ready(ask), reply: nil, permission: nil)
        #expect(mixed.lead == .button(.open))
        let other = CardOffer.of(reason: .question, plan: .ready(planPreview), question: nil, reply: nil, permission: nil)
        #expect(other.lead == .button(.open))
    }

    /// Only an answer is in the clay, on a row as on the card: Deny, alone or beside one, is plain.
    @Test func onlyTheAnswerTheCardMakesItsPrimaryIsInTheClay() {
        #expect([CardAction.approve, .reply, .review, .allowOnce].allSatisfy { $0.isPrimary })
        #expect(![CardAction.deny, .requestChanges, .open, .openInCapsid].contains { $0.isPrimary })
        let offers = [question(.permission(site(first)), reason: .web), question(.permission(readOnlyTool(first)), reason: .tool),
                      plan(.ready(planPreview)), plan(.problem("x", planPreview)), question(.ready(ask))]
        for offer in offers {
            #expect(offer.rowActions.filter(\.isPrimary).count <= 1)
            // It comes first, as the card puts it.
            if let index = offer.rowActions.firstIndex(where: { $0.isPrimary }) { #expect(index == 0) }
        }
    }

    @Test func rowTitlesSayWhenAButtonOpensAWindow() {
        #expect(CardAction.reply.rowTitle == "Reply…" && CardAction.reply.title == "Reply")
        #expect(CardAction.review.rowTitle == "Review…" && CardAction.review.title == "Review")
        #expect(CardAction.requestChanges.rowTitle == "Request changes…")
        #expect(CardAction.approve.rowTitle == "Approve" && CardAction.allowOnce.rowTitle == "Allow Once"
                && CardAction.deny.rowTitle == "Deny")
        #expect([CardAction.reply, .review, .requestChanges].allSatisfy { $0.opensWindow })
        #expect(![CardAction.approve, .allowOnce, .deny, .open].contains { $0.opensWindow })
    }
}

// MARK: Doing it, through the card's core

/// The page and the daemon, as the replier and the approver reach them: reads
/// by session, every send recorded, nothing real.
@MainActor
private final class Rig {
    let model = LabModel()
    var enabled = true
    var reads: [String: SessionProjection] = [:]
    private(set) var frameReads: [String] = []
    private(set) var sent: [(request: RemoteActionRequest, session: String)] = []
    var result = RemoteActionResult(result: .allowed, sentence: PermissionDecide.Sentence.allowed)
    /// A send waits here until released.
    var held: CheckedContinuation<Void, Never>?
    var holdSends = false
    private(set) var posts: [String] = []
    private(set) var planReads: [String] = []
    private(set) var windows: [(session: String, plan: Bool)] = []
    var questions: QuestionReplier!
    var plans: PlanApprover!
    var actions: CardActions!

    init() {
        questions = QuestionReplier(model: model, dependencies: QuestionReplier.Dependencies(
            isEnabled: { [unowned self] in self.enabled }, isReady: { true },
            read: { [unowned self] id in
                self.frameReads.append(id)
                await Task.yield()
                return self.reads[id]
            },
            respond: { [unowned self] request, session, _ in
                self.sent.append((request, session))
                if self.holdSends { await withCheckedContinuation { self.held = $0 } }
                return self.result
            }))
        plans = PlanApprover(model: model, dependencies: PlanApprover.Dependencies(
            isEnabled: { [unowned self] in self.enabled }, isReady: { true },
            get: { [unowned self] path in
                self.planReads.append(path)
                if path.hasPrefix("/frames/") { return Self.frame }
                if path.hasPrefix("/artifacts/versions/") { return Self.plan }
                throw WebAPIError.notAllowed
            },
            post: { [unowned self] path in
                self.posts.append(path)
                return APIWriteResult(status: 200, isJSON: true, code: nil, accepted: true, noPlanAwaiting: false)
            },
            approvedPause: .milliseconds(20)))
        actions = CardActions(model: model, plans: plans, questions: questions,
                              showReply: { [unowned self] in self.windows.append(($0, $1)) })
    }

    static let frame = Data(#"{"status": "awaiting_plan_approval", "context_data": {"_plan_version_id": "ver-001", "_plan_artifact_id": "art-001", "_plan_approved": false}, "output_data": null}"#.utf8)
    static let plan = Data(#"{"task_summary": "Screen made-up buffers", "steps": [{"title": "One"}, {"title": "Two"}], "feasibility": {"confidence": "high"}}"#.utf8)

    /// Sessions waiting, in the order their cards queue (the first is on top).
    func wait(_ sessions: [(id: String, reason: WaitingReason)]) {
        model.ingest(Fixture.snapshot(Fixture.session(sessions[0].id, .running)))
        model.ingest(ScienceSnapshot(runningCount: 0, daemonVersion: "test", sessions: sessions.map {
            Fixture.session($0.id, .needsInput, reason: $0.reason, title: "Session \($0.id.prefix(4))")
        }))
    }

    func session(_ id: String) -> SessionStatus {
        model.waiting.first { $0.id == id }!
    }

    func readAll() async {
        questions.sync()
        plans.sync()
        await questions.settled()
        await plans.settled()
    }
}

@MainActor
struct RowActionsCoreTests {
    private let rig = Rig()

    private func waitingRead(_ request: PermissionRequest? = nil, ask: QuestionAsk? = nil) -> SessionProjection {
        SessionProjection(status: ask == nil ? "processing" : "awaiting_user_response", agentName: "OPERON",
                          projectID: "proj_example", asks: ask.map { [$0] } ?? [], turns: [], permission: request)
    }

    @Test func aRowBehindTheTopCardReadsItsCardOnceWhenAsked() async {
        rig.reads = [first: waitingRead(ask: ask), second: waitingRead(ask: ask)]
        rig.wait([(first, .question), (second, .question)])
        await rig.readAll()
        #expect(rig.frameReads == [first], "the card on top is read as it comes, the other waits")
        #expect(rig.actions.offer(for: rig.session(second)).lead == .button(.open))
        rig.actions.prepare(rig.session(second))
        await rig.questions.settled()
        #expect(rig.actions.offer(for: rig.session(second)).rowActions == [.reply])
        rig.actions.prepare(rig.session(second))
        rig.actions.prepare(rig.session(first))
        await rig.questions.settled()
        #expect(rig.frameReads == [first, second], "one read a card, however often a row is hovered")
    }

    @Test func aPlansRowBehindTheTopCardReadsItsPlanToo() async {
        rig.reads = [first: waitingRead(ask: ask)]
        rig.wait([(first, .question), (second, .plan)])
        await rig.readAll()
        #expect(rig.planReads.isEmpty)
        rig.actions.prepare(rig.session(second))
        await rig.plans.settled()
        #expect(rig.planReads == ["/frames/\(second)?shallow=true", "/artifacts/versions/ver-001"])
        #expect(rig.actions.offer(for: rig.session(second)).rowActions == [.approve, .requestChanges])
        rig.actions.prepare(rig.session(second))
        await rig.plans.settled()
        #expect(rig.planReads.count == 2)
    }

    @Test func withTheCardSettingsOffARowOffersNothingAndNothingIsRead() async {
        rig.enabled = false
        rig.reads = [first: waitingRead(ask: ask)]
        rig.wait([(first, .question), (second, .plan)])
        await rig.readAll()
        rig.actions.prepare(rig.session(first))
        rig.actions.prepare(rig.session(second))
        await rig.questions.settled()
        await rig.plans.settled()
        #expect(rig.frameReads.isEmpty && rig.planReads.isEmpty)
        #expect(rig.actions.offer(for: rig.session(first)).rowActions.isEmpty)
        #expect(rig.actions.offer(for: rig.session(second)).rowActions.isEmpty)
        #expect(rig.actions.offer(for: rig.session(first)).lead == .button(.open))
    }

    @Test func aSessionWithNoCardInTheQueueHasNothingToOffer() async throws {
        rig.reads = [first: waitingRead(ask: ask), second: waitingRead(ask: ask)]
        rig.wait([(first, .question), (second, .question)])
        // Put off with Later, and dismissed: their cards leave the queue, the sessions still wait.
        rig.model.remind(try #require(rig.model.cards.first { $0.id == "needs-\(first)" }), .fiveMinutes)
        rig.model.dismiss(try #require(rig.model.cards.first { $0.id == "needs-\(second)" }))
        #expect(rig.model.waiting.count == 2)
        rig.actions.prepare(rig.session(first))
        rig.actions.prepare(rig.session(second))
        await rig.questions.settled()
        #expect(rig.frameReads.isEmpty)
        #expect(rig.actions.offer(for: rig.session(first)).rowActions.isEmpty)
        #expect(rig.actions.offer(for: rig.session(second)).rowActions.isEmpty)
    }

    @Test func allowOnceAndDenySendTheCardsOwnRequests() async {
        rig.reads = [first: waitingRead(readOnlyTool(first)), second: waitingRead(site(second))]
        rig.wait([(first, .tool), (second, .web)])
        await rig.readAll()
        rig.actions.prepare(rig.session(second))
        await rig.questions.settled()
        rig.actions.perform(.allowOnce, for: rig.session(first))
        await rig.questions.settled()
        rig.actions.perform(.deny, for: rig.session(second))
        await rig.questions.settled()
        #expect(rig.sent.map(\.session) == [first, second])
        #expect(rig.sent.map(\.request) == [.permission(id: "req-tool", allow: true, kind: "mcp_tool"),
                                            .permission(id: "req-net", allow: false, kind: "network")])
    }

    /// What `QuestionReplier.decide` itself does: the same, whoever presses.
    @Test func aRowsAllowIsTheCardsAllow() async {
        rig.reads = [first: waitingRead(readOnlyTool(first))]
        rig.wait([(first, .tool)])
        await rig.readAll()
        let viaRow = rig.actions
        viaRow?.perform(.allowOnce, for: rig.session(first))
        await rig.questions.settled()
        let viaRowSent = rig.sent.map(\.request)

        let card = Rig()
        card.reads = [first: waitingRead(readOnlyTool(first))]
        card.wait([(first, .tool)])
        await card.readAll()
        card.questions.decide(first, allow: true)
        await card.questions.settled()
        #expect(viaRowSent == card.sent.map(\.request))
    }

    @Test func aSendUnderWayShowsAsOnTheCardAndAFailedOneKeepsItsButtons() async {
        rig.reads = [first: waitingRead(readOnlyTool(first))]
        rig.wait([(first, .tool)])
        await rig.readAll()
        rig.holdSends = true
        rig.actions.perform(.allowOnce, for: rig.session(first))
        await Task.yield()
        for _ in 0..<50 where rig.held == nil { try? await Task.sleep(for: .milliseconds(10)) }
        var offer = rig.actions.offer(for: rig.session(first))
        #expect(offer.lead == .sending("Sending") && offer.rowActions.isEmpty)
        // A second press while it is under way sends nothing.
        rig.actions.perform(.allowOnce, for: rig.session(first))
        await Task.yield()
        #expect(rig.sent.count == 1)
        rig.result = .unavailable
        rig.holdSends = false
        rig.held?.resume()
        await rig.questions.settled()
        offer = rig.actions.offer(for: rig.session(first))
        #expect(offer.problem == QuestionReplier.Sentence.requestFailed)
        #expect(offer.rowActions == [.allowOnce, .deny], "it can be tried again, as on the card")
    }

    @Test func replyReviewAndRequestChangesOnlyOpenTheWindow() async {
        rig.reads = [first: waitingRead(ask: ask)]
        rig.wait([(first, .question)])
        await rig.readAll()
        rig.actions.perform(.reply, for: rig.session(first))
        rig.actions.perform(.review, for: rig.session(first))
        rig.actions.perform(.requestChanges, for: rig.session(first))
        #expect(rig.windows.map(\.session) == [first, first, first])
        #expect(rig.windows.map(\.plan) == [false, false, true])
        #expect(rig.sent.isEmpty && rig.posts.isEmpty)
    }

    @Test func approvePostsTheCardsOwnApproval() async {
        rig.wait([(first, .plan)])
        await rig.readAll()
        #expect(rig.actions.offer(for: rig.session(first)).lead == .button(.approve))
        rig.actions.perform(.approve, for: rig.session(first))
        rig.actions.perform(.approve, for: rig.session(first))
        await rig.plans.settled()
        #expect(rig.posts == ["/frames/\(first)/approve-plan"], "once, as the card's own button sends it")
        #expect(rig.sent.isEmpty)
    }

    @Test func openingFromARowIsTheListsOwnOpen() {
        // `.open` takes no part in the core: it is `LabModel.open`, which clears the session's cards and reminder.
        rig.wait([(first, .question)])
        #expect(rig.model.cards.count == 1)
        rig.actions.perform(.open, for: rig.session(first))
        #expect(rig.model.cards.isEmpty)
    }
}

// MARK: One rule for the card and the row

/// The card and the row both ask `CardActions` and nothing else (this scans the
/// source: a view is not something a test can press).
struct RowAndCardShareOneRuleTests {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)
    }

    @Test func bothViewsReadTheOfferAndDoWhatItSaysThroughCardActions() throws {
        let card = try source("Lab/LabPanelView.swift"), list = try source("Lab/ActivityList.swift")
        for view in [card, list] {
            #expect(view.contains("CardActions("))
            #expect(view.contains(".offer(for: session)"))
            #expect(view.contains(".perform("))
            // Nothing sent from a view: no calls of the core itself.
            for call in [".decide(", "plans.approve(", "ReplyWindowController", ".respond(", "apiPOST", "RemoteSessions"] {
                #expect(!view.contains(call), "\(call)")
            }
        }
    }

    @Test func theCoreIsCalledFromOnePlace() throws {
        let actions = try source("Lab/CardActions.swift")
        #expect(actions.contains("plans.approve(session.id)"))
        #expect(actions.contains("questions.decide(session.id, allow: true)"))
        #expect(actions.contains("questions.decide(session.id, allow: false)"))
        #expect(actions.contains("ReplyWindowController.shared.show($0, plan: $1)"))
    }
}
