// ReplyLifetimeTests.swift — what the card's replier keeps, and for how long,
// and a notification's time limit, on made-up sessions with held reads and a
// stand-in clock. Who owns a reply: its open window, a send under way, or a
// draft for a session still waiting; nothing else outlives its use. A
// notification waits at most its limit on any path, never cancels the card's
// own read, and waits for its own answer alone. Nothing here reaches a page or
// a daemon, and nothing sleeps.
import Foundation
import Testing
@testable import Bench

private let buffer = SessionProjection.Question(
    question: "Which buffer should the made-up screen use?", header: "Buffer", multi: false,
    options: [.init(label: "HEPES", detail: nil), .init(label: "Tris", detail: nil)])

private func ask(_ toolID: String = "toolu_made_up_1") -> QuestionAsk {
    QuestionAsk(toolID: toolID, items: [buffer])
}

private func asking(_ toolID: String = "toolu_made_up_1") -> SessionProjection {
    SessionProjection(status: "awaiting_user_response", agentName: "OPERON", projectID: "proj_example",
                      asks: [ask(toolID)], turns: [.init(role: .claude, at: nil, text: "Made-up context.")])
}

private func tool(_ id: String) -> SessionProjection {
    SessionProjection(status: "processing", agentName: "OPERON", projectID: "proj_example",
                      turns: [.init(role: .claude, at: nil, text: "Made-up context.")],
                      permission: PermissionRequest(requestID: "req-\(id.prefix(8))", toolID: "tool-1", mode: "parked",
                                                    kind: "mcp_tool", frame: id, tool: "search_made_up", server: "Made-up",
                                                    source: "directory", readOnly: true))
}

private func newID() -> String { UUID().uuidString.lowercased() }

/// Reads and sends by table, each of which can be held until let go, and a
/// clock whose waits end only when told to (or when their task is cancelled).
@MainActor
private final class Bench {
    var reads: [String: SessionProjection?] = [:]
    var results: [RemoteActionResult] = []
    var ready = true
    /// Sessions whose reads wait until `letGo(_:)`.
    var holdReads: Set<String> = []
    var holdSends = false
    private var readGates: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var sendGates: [CheckedContinuation<Void, Never>] = []
    private(set) var readsStarted: [String] = []
    private(set) var cancelledReads = 0
    private(set) var requests: [RemoteActionRequest] = []

    // The clock.
    private var timers: [UUID: CheckedContinuation<Void, Never>] = [:]
    private(set) var timersStarted = 0
    private(set) var timersCancelled = 0
    var timersWaiting: Int { timers.count }

    func dependencies() -> QuestionReplier.Dependencies {
        QuestionReplier.Dependencies(
            isEnabled: { true },
            isReady: { [unowned self] in self.ready },
            read: { [unowned self] id in
                self.readsStarted.append(id)
                if self.holdReads.contains(id) {
                    await withCheckedContinuation { self.readGates[id, default: []].append($0) }
                } else {
                    await Task.yield()
                }
                if Task.isCancelled { self.cancelledReads += 1 }
                return self.reads[id] ?? nil
            },
            respond: { [unowned self] request, _ in
                self.requests.append(request)
                if self.holdSends { await withCheckedContinuation { self.sendGates.append($0) } }
                return self.results.isEmpty ? RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.answered)
                    : self.results.removeFirst()
            },
            wait: { [unowned self] _ in
                self.timersStarted += 1
                let key = UUID()
                await withTaskCancellationHandler {
                    await withCheckedContinuation { self.timers[key] = $0 }
                } onCancel: {
                    Task { @MainActor in
                        if let timer = self.timers.removeValue(forKey: key) {
                            self.timersCancelled += 1
                            timer.resume()
                        }
                    }
                }
            })
    }

    func letGo(_ id: String) {
        holdReads.remove(id)
        readGates.removeValue(forKey: id)?.forEach { $0.resume() }
    }

    func letSendsGo() {
        holdSends = false
        let held = sendGates
        sendGates = []
        held.forEach { $0.resume() }
    }

    /// Every waiting timer's limit passes.
    func tick() {
        let fired = timers
        timers = [:]
        fired.values.forEach { $0.resume() }
    }
}

/// Lets the main actor run what is ready to run.
@MainActor
private func spin(_ times: Int = 20) async {
    for _ in 0..<times { await Task.yield() }
}

@MainActor
struct ReplyLifetimeTests {
    private let bench = Bench()
    private let model = LabModel()

    private func waits(_ id: String, _ reason: WaitingReason) {
        model.ingest(Fixture.snapshot(Fixture.session(id, .running)))
        model.ingest(Fixture.snapshot(Fixture.session(id, .needsInput, reason: reason)))
    }

    private func finishes(_ id: String) {
        model.ingest(Fixture.snapshot(Fixture.session(id, .finished)))
    }

    private func replier() -> QuestionReplier {
        QuestionReplier(model: model, dependencies: bench.dependencies())
    }

    private func isEmpty(_ replier: QuestionReplier) -> Bool {
        let held = replier.retained
        return held.replies + held.permissions + held.plans + held.contexts + held.cards + held.tasks + held.sends == 0
    }

    // MARK: Finished replies are let go

    @Test func hundredsOfDirectApprovalsKeepNothing() async {
        let replier = replier()
        for _ in 0..<300 {
            let id = newID()
            bench.reads[id] = tool(id)
            waits(id, .tool)
            replier.sync()
            await replier.settled()
            bench.results = [RemoteActionResult(result: .allowed, sentence: PermissionDecide.Sentence.allowed)]
            #expect(await replier.decide(id, allow: true)?.value == .sent(PermissionDecide.Sentence.allowed))
            finishes(id)
            replier.sync()
        }
        #expect(isEmpty(replier), "\(replier.retained)")
    }

    @Test func aDirectApprovalIsLetGoBeforeItsSessionEvenEnds() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = tool(id)
        bench.results = [RemoteActionResult(result: .allowed, sentence: PermissionDecide.Sentence.allowed)]
        waits(id, .tool)
        replier.sync()
        await replier.settled()
        _ = await replier.decide(id, allow: true)?.value
        // The session still shows as waiting until the next read says otherwise.
        #expect(replier.permissionReplies[id] == nil)
        #expect(replier.contexts[id] == nil)
        #expect(replier.cardState(for: id) == nil)
    }

    @Test func hundredsOfNotificationAnswersKeepNothing() async {
        let replier = replier()
        for _ in 0..<300 {
            let id = newID()
            bench.reads[id] = asking()
            waits(id, .question)
            replier.sync()
            await replier.settled()
            var draft = ReplyDraft(for: ask())
            draft.pick(1, in: 0, multi: false)
            #expect(await replier.answerFromNotification(id, ask: ask(), draft: draft) == .sent(RemoteDecide.Sentence.answered))
            finishes(id)
            replier.sync()
        }
        #expect(isEmpty(replier), "\(replier.retained)")
        #expect(bench.requests.count == 300)
    }

    @Test func plansChangedInTheirWindowAreLetGoWhenItCloses() async {
        let replier = QuestionReplier(model: model, dependencies: {
            var dependencies = bench.dependencies()
            dependencies.plan = { _ in PlanPreview(summary: "Made-up plan", steps: 2, confidence: nil,
                                                   versionID: "ver_made_up", artifactID: nil) }
            return dependencies
        }())
        for _ in 0..<50 {
            let id = newID()
            waits(id, .plan)
            #expect(replier.begin(id, plan: true))
            replier.windowOpened(id)
            replier.updatePlanFeedback(id, text: "Add a made-up control.")
            bench.results = [RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising)]
            #expect(await replier.submitPlanFeedback(id)?.value == .sent(RemoteDecide.Sentence.revising))
            #expect(replier.planReplies[id]?.phase == .sent(RemoteDecide.Sentence.revising), "its window still shows it")
            replier.windowClosed(id)
            finishes(id)
            replier.sync()
        }
        #expect(isEmpty(replier), "\(replier.retained)")
    }

    // MARK: What is kept while it matters

    @Test func aDraftClosedBeforeTheSessionEndsIsKeptThenLetGo() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        waits(id, .question)
        replier.sync()
        await replier.settled()
        #expect(replier.begin(id))
        replier.windowOpened(id)
        replier.updateDraft(id) { $0.pick(1, in: 0, multi: false) }
        replier.windowClosed(id)
        #expect(replier.replies[id]?.draft.picks[0] == [1], "still waiting: the draft stays")
        finishes(id)
        replier.sync()
        #expect(replier.replies[id] == nil, "the wait ended with no window: let go")
        #expect(isEmpty(replier), "\(replier.retained)")
    }

    @Test func laterThenTheCardBackKeepsTheDraft() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        waits(id, .question)
        replier.sync()
        await replier.settled()
        #expect(replier.begin(id))
        replier.windowOpened(id)
        replier.updateDraft(id) { $0.pick(1, in: 0, multi: false) }
        replier.windowClosed(id)
        let card = LabCard.needsInput(Fixture.session(id, .needsInput, reason: .question))
        model.remind(card, .fiveMinutes)
        replier.sync()
        #expect(replier.cardState(for: id) == nil, "Later took the card")
        #expect(replier.contexts[id] == nil, "and what was read for it")
        #expect(replier.replies[id]?.draft.picks[0] == [1])
        // The card comes back (the reminder, or the session asking again).
        model.ingest(Fixture.snapshot(Fixture.session(id, .running)))
        waits(id, .question)
        replier.sync()
        await replier.settled()
        #expect(replier.begin(id))
        #expect(replier.replies[id]?.draft.picks[0] == [1])
    }

    @Test func aWindowClosedWhileSendingKeepsTheSendThenLetsGo() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        waits(id, .question)
        replier.sync()
        await replier.settled()
        #expect(replier.begin(id))
        replier.windowOpened(id)
        replier.updateDraft(id) { $0.pick(0, in: 0, multi: false) }
        bench.holdSends = true
        let send = replier.submit(id)
        await spin()
        replier.windowClosed(id)
        #expect(replier.replies[id]?.phase == .sending, "a send under way is kept")
        bench.letSendsGo()
        #expect(await send?.value == .sent(RemoteDecide.Sentence.answered))
        #expect(replier.replies[id] == nil)
    }

    @Test func anOpenWindowKeepsItsStatus() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        waits(id, .question)
        replier.sync()
        await replier.settled()
        #expect(replier.begin(id))
        replier.windowOpened(id)
        replier.updateDraft(id) { $0.pick(0, in: 0, multi: false) }
        _ = await replier.submit(id)?.value
        finishes(id)
        replier.sync()
        #expect(replier.replies[id]?.phase == .sent(RemoteDecide.Sentence.answered))
        replier.windowClosed(id)
        #expect(replier.replies[id] == nil)
    }

    @Test func aFailedOrChangedRequestStaysWhileItsSessionWaits() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = tool(id)
        waits(id, .tool)
        replier.sync()
        await replier.settled()
        bench.results = [.unavailable]
        #expect(await replier.decide(id, allow: true)?.value == .failed(QuestionReplier.Sentence.requestFailed))
        #expect(replier.permissionReplies[id] != nil, "the card says it failed, and Allow can be pressed again")
        // Changed: the new request is shown, from the card's own re-read.
        let other = newID()
        bench.reads[id] = tool(other)
        bench.results = [RemoteActionResult(result: .changed, sentence: PermissionDecide.Sentence.changed)]
        #expect(await replier.decide(id, allow: true)?.value == .changed(QuestionReplier.Sentence.requestChanged))
        #expect(replier.permissionReplies[id]?.request.frame == other)
        finishes(id)
        replier.sync()
        #expect(isEmpty(replier), "\(replier.retained)")
    }

    @Test func whatWasReadForACardGoesWithItHoweverItGoes() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        waits(id, .question)
        replier.sync()
        await replier.settled()
        #expect(replier.contexts[id] == "Made-up context.")
        #expect(replier.retained.tasks == 0, "a finished read takes itself out")
        if let card = model.cards.first { model.dismiss(card) }
        replier.sync()
        #expect(replier.contexts[id] == nil)
        #expect(replier.cardState(for: id) == nil)
    }

    // MARK: A notification's time limit

    @Test func aStalledCardReadReachesTheLimitAndTheCardStillGetsIt() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        bench.holdReads = [id]
        waits(id, .question)
        replier.sync()
        #expect(replier.cardState(for: id) == .loading)
        var answer: QuestionAsk?? = .none
        let waiting = Task { answer = .some(await replier.askForNotification(id)) }
        await spin()
        #expect(bench.timersWaiting == 1)
        bench.tick()
        await waiting.value
        #expect(answer == .some(nil), "the limit passed: the notification goes as it is")
        #expect(bench.readsStarted == [id], "no second read")
        // The card's read was never cancelled, and lands for the card.
        bench.letGo(id)
        await replier.settled()
        #expect(bench.cancelledReads == 0)
        #expect(replier.cardState(for: id) == .ready(ask()))
    }

    @Test func aFastReadCancelsItsTimer() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        waits(id, .question)
        // Not read for the card yet: the notification reads it itself.
        #expect(await replier.askForNotification(id) == ask())
        await spin()
        #expect(bench.timersStarted == 1)
        #expect(bench.timersCancelled == 1)
        #expect(bench.timersWaiting == 0)
        #expect(replier.cardState(for: id) == .ready(ask()), "kept for the card")
    }

    @Test func theLimitCancelsAPrivateReadAndALateOneChangesNothing() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        bench.holdReads = [id]
        waits(id, .question)
        let waiting = Task { await replier.askForNotification(id) }
        await spin()
        bench.tick()
        #expect(await waiting.value == nil)
        bench.letGo(id)
        await spin()
        #expect(bench.cancelledReads == 1, "the losing read was cancelled")
        #expect(replier.cardState(for: id) == nil, "a late answer is let go")
    }

    @Test func aCancelledCallerReturnsAtOnceAndCancelsItsWork() async {
        let replier = replier()
        let id = newID()
        bench.reads[id] = asking()
        bench.holdReads = [id]
        waits(id, .question)
        let waiting = Task { await replier.askForNotification(id) }
        await spin()
        waiting.cancel()
        #expect(await waiting.value == nil)
        await spin()
        #expect(bench.timersCancelled == 1)
        #expect(bench.timersWaiting == 0)
        bench.letGo(id)
        await spin()
        #expect(bench.cancelledReads == 1)
    }

    /// The read and the limit arriving together answer once (a second
    /// answer would trap), whichever wins.
    @Test func theLimitAndTheReadRacingAnswerOnce() async {
        for _ in 0..<100 {
            let replier = replier()
            let id = newID()
            bench.reads[id] = asking()
            bench.holdReads = [id]
            waits(id, .question)
            let waiting = Task { await replier.askForNotification(id) }
            await spin()
            bench.letGo(id)
            bench.tick()
            let answer = await waiting.value
            #expect(answer == nil || answer == ask())
        }
    }

    @Test func anUnrelatedStalledSessionDoesntHoldANotificationAnswer() async {
        let replier = replier()
        let stalled = newID(), answered = newID()
        bench.reads[stalled] = asking()
        bench.reads[answered] = asking()
        bench.holdReads = [stalled]
        model.ingest(Fixture.snapshot(Fixture.session(stalled, .running), Fixture.session(answered, .running)))
        model.ingest(Fixture.snapshot(Fixture.session(stalled, .needsInput, reason: .question),
                                      Fixture.session(answered, .needsInput, reason: .question)))
        // The stalled one's card read is under way, and never ends in this test.
        #expect(replier.prepare(stalled))
        #expect(replier.prepare(answered))
        bench.letGo(answered)
        await spin()
        var draft = ReplyDraft(for: ask())
        draft.pick(0, in: 0, multi: false)
        #expect(await replier.answerFromNotification(answered, ask: ask(), draft: draft) == .sent(RemoteDecide.Sentence.answered))
        #expect(replier.cardState(for: stalled) == .loading, "still held, and it didn't matter")
        bench.letGo(stalled)
        await replier.settled()
    }
}
