// QuestionReplyTests.swift — answering a question from its card, on made-up
// sessions: the answer a draft makes (the phone's own rule), which requests the
// card can answer, the replier's whole life (one read per card, one send per
// press, a question that changed or was answered elsewhere, a failure that
// keeps the draft, a session that stops waiting), and the answer going through
// the phone's actions beneath their gates, so it works with phone actions off.
// Nothing here reaches a page or a daemon.
import Foundation
import Testing
@testable import Bench

// MARK: Made-up questions

private let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

private let buffer = SessionProjection.Question(
    question: "Which buffer should the made-up screen use?", header: "Buffer", multi: false,
    options: [.init(label: "HEPES", detail: "Most stable"), .init(label: "Tris", detail: nil),
              .init(label: "PBS", detail: nil)])
private let readouts = SessionProjection.Question(
    question: "Which made-up readouts?", header: "Readouts", multi: true,
    options: [.init(label: "Absorbance", detail: nil), .init(label: "Fluorescence", detail: nil),
              .init(label: "Turbidity", detail: nil)])
private let freeText = SessionProjection.Question(
    question: "Anything else about the made-up plates?", header: "", multi: false, options: [])

private func ask(_ items: [SessionProjection.Question] = [buffer], toolID: String = "toolu_made_up_1") -> QuestionAsk {
    QuestionAsk(toolID: toolID, items: items)
}

private func waitingRead(_ ask: QuestionAsk? = ask(), status: String = "awaiting_user_response") -> SessionProjection {
    SessionProjection(status: status, agentName: "OPERON", projectID: "proj_example", asks: ask.map { [$0] } ?? [])
}

// MARK: The answer a draft makes

struct QuestionAnswersTests {
    @Test func oneChoiceIsItsLabel() {
        var draft = ReplyDraft(for: ask())
        draft.pick(1, in: 0, multi: false)
        #expect(QuestionAnswers.text(buffer, at: 0, draft: draft) == "Tris")
        draft.pick(0, in: 0, multi: false)
        #expect(QuestionAnswers.text(buffer, at: 0, draft: draft) == "HEPES")
    }

    @Test func otherReplacesTheChoiceWhenOnlyOneIsAllowed() {
        var draft = ReplyDraft(for: ask())
        draft.pick(0, in: 0, multi: false)
        draft.setOther(true, in: 0, multi: false)
        draft.other[0] = "  MOPS \n"
        #expect(draft.picks[0] == [])
        #expect(QuestionAnswers.text(buffer, at: 0, draft: draft) == "MOPS")
        // Picking again turns Other off.
        draft.pick(2, in: 0, multi: false)
        #expect(draft.otherOn[0] == false)
        #expect(QuestionAnswers.text(buffer, at: 0, draft: draft) == "PBS")
    }

    @Test func severalAreInTheOptionsOrderThenWhatWasTyped() {
        var draft = ReplyDraft(for: ask([readouts]))
        draft.pick(2, in: 0, multi: true)
        draft.pick(0, in: 0, multi: true)
        #expect(QuestionAnswers.text(readouts, at: 0, draft: draft) == "Absorbance, Turbidity")
        draft.setOther(true, in: 0, multi: true)
        draft.other[0] = "Made-up luminescence"
        #expect(QuestionAnswers.text(readouts, at: 0, draft: draft) == "Absorbance, Turbidity, Made-up luminescence")
        // A second click on a pick takes it away.
        draft.pick(2, in: 0, multi: true)
        #expect(QuestionAnswers.text(readouts, at: 0, draft: draft) == "Absorbance, Made-up luminescence")
    }

    @Test func severalAllowedButOnlyTyped() {
        var draft = ReplyDraft(for: ask([readouts]))
        draft.setOther(true, in: 0, multi: true)
        draft.other[0] = "Only this"
        #expect(QuestionAnswers.text(readouts, at: 0, draft: draft) == "Only this")
    }

    @Test func aQuestionWithNoChoicesIsTypedFromTheStart() {
        let freeAsk = ask([freeText])
        var draft = ReplyDraft(for: freeAsk)
        #expect(draft.otherOn[0] == true)
        #expect(!QuestionAnswers.isComplete(freeAsk, draft: draft))
        draft.other[0] = "Seal them."
        #expect(QuestionAnswers.request(freeAsk, draft: draft)
                == .answer(toolID: "toolu_made_up_1", answers: [freeText.question: "Seal them."]))
    }

    @Test func everyQuestionMustBeAnsweredBeforeAnythingIsSent() {
        let both = ask([buffer, readouts])
        var draft = ReplyDraft(for: both)
        draft.pick(0, in: 0, multi: false)
        #expect(QuestionAnswers.request(both, draft: draft) == nil)
        draft.setOther(true, in: 1, multi: true)
        draft.other[1] = "   "
        #expect(QuestionAnswers.request(both, draft: draft) == nil, "white space is no answer")
        draft.pick(1, in: 1, multi: true)
        #expect(QuestionAnswers.request(both, draft: draft)
                == .answer(toolID: "toolu_made_up_1", answers: [buffer.question: "HEPES", readouts.question: "Fluorescence"]))
    }

    @Test func anAnswerOverTheLimitIsNeverSent() {
        let freeAsk = ask([freeText])
        var draft = ReplyDraft(for: freeAsk)
        draft.other[0] = String(repeating: "a", count: RemoteActionRequest.answerLimit + 1)
        #expect(QuestionAnswers.isTooLong(freeAsk, draft: draft))
        #expect(QuestionAnswers.request(freeAsk, draft: draft) == nil)
        draft.other[0] = String(repeating: "a", count: RemoteActionRequest.answerLimit)
        #expect(QuestionAnswers.request(freeAsk, draft: draft) != nil)
    }

    /// The same check the phone's bodies get: the Mac builds no request the phone's parser would refuse.
    @Test func theCheckIsTheOnePhoneAnswersGet() {
        #expect(RemoteActionRequest.checkedAnswer(toolID: "t", answers: [:]) == nil)
        #expect(RemoteActionRequest.checkedAnswer(toolID: "", answers: ["q": "a"]) == nil)
        #expect(RemoteActionRequest.checkedAnswer(toolID: "t", answers: ["": "a"]) == nil)
        let eleven = Dictionary(uniqueKeysWithValues: (0...10).map { ("q\($0)", "a") })
        #expect(RemoteActionRequest.checkedAnswer(toolID: "t", answers: eleven) == nil)
        #expect(RemoteActionRequest.checkedAnswer(toolID: "t", answers: ["q": " a "]) == .answer(toolID: "t", answers: ["q": "a"]))
        let body = Data(#"{"toolId":"t","answers":{"q":" a "}}"#.utf8)
        #expect(RemoteActionRequest.parse(.answer, body: body) == .answer(toolID: "t", answers: ["q": "a"]))
    }

    @Test func aDraftFittedToTheSameRequestKeepsWhatStillFits() {
        var draft = ReplyDraft(for: ask([readouts]))
        draft.pick(0, in: 0, multi: true)
        draft.pick(2, in: 0, multi: true)
        draft.other[0] = "kept"
        let fewer = SessionProjection.Question(question: readouts.question, header: "", multi: true,
                                               options: [.init(label: "Absorbance", detail: nil)])
        let fitted = draft.fitted(to: ask([fewer]))
        #expect(fitted.picks[0] == [0])
        #expect(fitted.other[0] == "kept")
    }
}

// MARK: Which requests the card answers

struct QuestionCardStateTests {
    @Test func onlyTheRootsOwnWaitingQuestion() {
        #expect(QuestionCardState.from(waitingRead()) == .ready(ask()))
        #expect(QuestionCardState.from(nil) == .unavailable)
        // Asked mid-run: the phone can't answer those either.
        #expect(QuestionCardState.from(waitingRead(status: "processing")) == .unsupported)
        // Waiting on a helper's question or a permission request: no root ask.
        #expect(QuestionCardState.from(waitingRead(nil)) == .unsupported)
        // A first ask whose shape Capsid doesn't know is not passed over for a later one.
        let unreadableFirst = SessionProjection(status: "awaiting_user_response", agentName: "OPERON",
                                                projectID: "proj_example", asks: [nil, ask()])
        #expect(QuestionCardState.from(unreadableFirst) == .unsupported)
        #expect(QuestionCardState.from(waitingRead(ask([]))) == .unsupported)
    }

    @Test func theCardSaysHowItIsAnsweredNeverWhatItAsks() {
        #expect(QuestionCardState.shape(ask()) == "3 choices")
        #expect(QuestionCardState.shape(ask([readouts])) == "Pick any of 3")
        #expect(QuestionCardState.shape(ask([freeText])) == "Type an answer")
        #expect(QuestionCardState.shape(ask([buffer, readouts])) == "2 questions")
    }
}

// MARK: The replier

/// Stands in for the reads and the phone's action core: answers from a table,
/// records each request, and can hold a send until let go.
@MainActor
private final class FakeCore {
    var enabled = true
    var ready = true
    var read: SessionProjection? = waitingRead()
    /// What each send answers, in turn; then "sent".
    var results: [RemoteActionResult] = []
    var holdSends = false
    var now = Date(timeIntervalSince1970: 1_792_000_000)
    private(set) var reads = 0
    private(set) var requests: [RemoteActionRequest] = []
    private var gates: [CheckedContinuation<Void, Never>] = []

    static let sent = RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.answered)

    func dependencies() -> QuestionReplier.Dependencies {
        QuestionReplier.Dependencies(
            isEnabled: { [unowned self] in self.enabled },
            isReady: { [unowned self] in self.ready },
            read: { [unowned self] _ in
                self.reads += 1
                await Task.yield()
                return self.read
            },
            respond: { [unowned self] request, _, _ in
                self.requests.append(request)
                if self.holdSends { await withCheckedContinuation { self.gates.append($0) } }
                return self.results.isEmpty ? Self.sent : self.results.removeFirst()
            },
            now: { [unowned self] in self.now })
    }

    func letGo() {
        let waiting = gates
        gates = []
        waiting.forEach { $0.resume() }
    }
}

@MainActor
struct QuestionReplierTests {
    private let core = FakeCore()
    private let model = LabModel()

    private var waiting: SessionStatus {
        Fixture.session(session, .needsInput, reason: .question, title: "Made-up buffer screen")
    }

    /// The question card on top, its question read.
    private func ready() async -> QuestionReplier {
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        model.ingest(Fixture.snapshot(waiting))
        let replier = QuestionReplier(model: model, dependencies: core.dependencies())
        replier.sync()
        #expect(replier.cardState(for: session) == .loading)
        await replier.settled()
        return replier
    }

    /// Reply pressed (its window open), and HEPES picked.
    private func replying() async -> QuestionReplier {
        let replier = await ready()
        #expect(replier.beginReply(session))
        replier.windowOpened(session)
        replier.updateDraft(session) { $0.pick(0, in: 0, multi: false) }
        return replier
    }

    @Test func theTopQuestionIsReadOnce() async {
        let replier = await ready()
        #expect(replier.cardState(for: session) == .ready(ask()))
        replier.sync()
        await replier.settled()
        #expect(core.reads == 1)
    }

    @Test func withTheSettingOffOrForAPlanNothingIsRead() async {
        core.enabled = false
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        model.ingest(Fixture.snapshot(waiting))
        let off = QuestionReplier(model: model, dependencies: core.dependencies())
        off.sync()
        await off.settled()
        #expect(off.cards.isEmpty)
        #expect(!off.beginReply(session))
        #expect(core.reads == 0)
        let planModel = LabModel()
        planModel.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        planModel.ingest(Fixture.snapshot(Fixture.session(session, .needsInput, reason: .plan)))
        core.enabled = true
        let replier = QuestionReplier(model: planModel, dependencies: core.dependencies())
        replier.sync()
        #expect(replier.cards.isEmpty)
        #expect(core.reads == 0)
    }

    @Test func aRequestTheCardCantAnswerOffersOpenInCapsid() async {
        core.read = waitingRead(nil)
        let replier = await ready()
        #expect(replier.cardState(for: session) == .unsupported)
        #expect(!replier.beginReply(session))
    }

    @Test func aFailedReadIsTriedAgainAWhileLater() async {
        core.read = nil
        let replier = await ready()
        #expect(replier.cardState(for: session) == .unavailable)
        replier.sync()
        #expect(core.reads == 1)
        core.now = core.now.addingTimeInterval(QuestionReplier.retryAfter + 1)
        core.read = waitingRead()
        replier.sync()
        await replier.settled()
        #expect(core.reads == 2)
        #expect(replier.cardState(for: session) == .ready(ask()))
    }

    @Test func theReplySaysWhereItGoes() async {
        let replier = await replying()
        let reply = replier.replies[session]
        #expect(reply?.session.displayTitle == "Made-up buffer screen")
        #expect(reply?.session.projectName == "Example project")
        #expect(reply?.phase == .editing)
    }

    @Test func anUnfinishedAnswerSendsNothing() async {
        let replier = await ready()
        replier.beginReply(session)
        #expect(!replier.canSend(session))
        replier.submit(session)
        await replier.settled()
        #expect(core.requests.isEmpty)
        #expect(replier.replies[session]?.phase == .editing)
    }

    @Test func oneSendPerPressAndTheCardGoesOnceSent() async {
        let replier = await replying()
        core.holdSends = true
        replier.submit(session)
        replier.submit(session)
        replier.submit(session, .chooseForMe)
        // Let the first send reach the core.
        for _ in 0..<5 { await Task.yield() }
        #expect(core.requests == [.answer(toolID: "toolu_made_up_1", answers: [buffer.question: "HEPES"])])
        #expect(replier.replies[session]?.phase == .sending)
        #expect(!replier.canSend(session))
        core.letGo()
        await replier.settled()
        #expect(core.requests.count == 1)
        #expect(replier.replies[session]?.phase == .sent(RemoteDecide.Sentence.answered))
        #expect(!model.cards.contains { $0.id == LabCard.needsInput(waiting).id })
        #expect(replier.cardState(for: session) == nil)
    }

    @Test func aNewQuestionTakesTheOldOnesPlaceWithAFreshDraft() async {
        let replier = await replying()
        core.results = [RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.questionChanged)]
        let newer = ask([readouts], toolID: "toolu_made_up_2")
        core.read = waitingRead(newer)
        replier.submit(session)
        await replier.settled()
        let reply = replier.replies[session]
        #expect(reply?.phase == .changed(QuestionReplier.Sentence.changed))
        #expect(reply?.ask == newer)
        #expect(reply?.draft == ReplyDraft(for: newer))
        #expect(replier.cardState(for: session) == .ready(newer))
        #expect(!replier.canSend(session), "nothing is picked for the new question yet")
    }

    @Test func theSameRequestReadAgainKeepsTheDraft() async {
        let replier = await replying()
        core.results = [RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.questionChanged)]
        replier.submit(session)
        await replier.settled()
        #expect(replier.replies[session]?.phase == .changed(QuestionReplier.Sentence.changed))
        #expect(replier.replies[session]?.draft.picks[0] == [0])
        #expect(replier.canSend(session))
    }

    /// A re-read that fails says nothing about the question: it isn't
    /// reported as answered or gone, and Send stays possible.
    @Test func aFailedReReadKeepsTheDraftAndSend() async {
        let replier = await replying()
        core.results = [RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.questionChanged)]
        core.read = nil
        replier.submit(session)
        await replier.settled()
        #expect(replier.replies[session]?.phase == .changed(QuestionReplier.Sentence.couldntCheck))
        #expect(replier.replies[session]?.draft.picks[0] == [0])
        #expect(replier.canSend(session))
    }

    @Test func answeredElsewhereLeavesNothingToSend() async {
        let replier = await replying()
        core.results = [RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.alreadyAnswered)]
        core.read = waitingRead(status: "processing")
        replier.submit(session)
        await replier.settled()
        #expect(replier.replies[session]?.phase == .closed(RemoteDecide.Sentence.alreadyAnswered))
        #expect(!replier.canSend(session))
    }

    @Test func aFailureKeepsTheDraftAndSendTriesAgain() async {
        let replier = await replying()
        replier.updateDraft(session) { $0.setOther(true, in: 0, multi: false); $0.other[0] = "Made-up MOPS" }
        let draft = replier.replies[session]?.draft
        core.results = [.unavailable]
        replier.submit(session)
        await replier.settled()
        #expect(replier.replies[session]?.phase == .failed(QuestionReplier.Sentence.failed))
        #expect(replier.replies[session]?.draft == draft)
        replier.submit(session)
        await replier.settled()
        #expect(core.requests.count == 2)
        #expect(core.requests.last == .answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Made-up MOPS"]))
        #expect(replier.replies[session]?.phase == .sent(RemoteDecide.Sentence.answered))
    }

    @Test func aSessionThatStopsWaitingClosesItsReply() async {
        let replier = await replying()
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        replier.sync()
        // The open window still says why.
        #expect(replier.replies[session]?.phase == .closed(QuestionReplier.Sentence.stoppedWaiting))
        #expect(!replier.canSend(session))
        replier.windowClosed(session)
        #expect(replier.replies[session] == nil)
    }

    @Test func closingTheWindowKeepsTheDraftForTheNextReply() async {
        let replier = await replying()
        replier.closeReply(session)
        #expect(replier.replies[session]?.draft.picks[0] == [0])
        #expect(replier.beginReply(session))
        #expect(replier.replies[session]?.draft.picks[0] == [0])
    }

    @Test func laterKeepsAnOpenReply() async {
        let replier = await replying()
        model.remind(LabCard.needsInput(waiting), .fiveMinutes)
        replier.sync()
        #expect(replier.cardState(for: session) == nil, "the card went")
        #expect(replier.replies[session]?.phase == .editing, "the session still waits")
    }
}

// MARK: Through the phone's actions, with phone actions off

/// The page, as `RemoteSessions` reads and writes it: a table of reads and a
/// record of writes.
@MainActor
private final class FakePage {
    var actionsOn = false
    var read: SessionProjection? = waitingRead()
    /// An answer written makes the session run again, as the daemon's does.
    var resolvesOnWrite = false
    private(set) var writes: [RemoteWrite] = []
    private(set) var frameReads = 0

    func sessions() -> RemoteSessions {
        RemoteSessions(dependencies: RemoteSessions.Dependencies(
            actionsOn: { [unowned self] in self.actionsOn },
            known: { [Fixture.session(session, .needsInput, reason: .question)] },
            cardPlan: { _ in nil },
            read: { [unowned self] _, turns in
                self.frameReads += 1
                await Task.yield()
                return turns ? self.read : self.read?.withoutTurns
            },
            readPlan: { _ in nil },
            write: { [unowned self] write in
                self.writes.append(write)
                if self.resolvesOnWrite { self.read = waitingRead(status: "processing") }
                return RemoteWriteResult(status: 200, bodyStatus: "accepted", remaining: 0)
            },
            now: { Date(timeIntervalSince1970: 1_792_000_000) }))
    }
}

@MainActor
struct NativeReplyCoreTests {
    private let page = FakePage()

    @Test func theMacAnswersWhilePhoneActionsAreOff() async {
        let sessions = page.sessions()
        let body = Data(#"{"toolId":"toolu_made_up_1","answers":{"Which buffer should the made-up screen use?":"Tris"}}"#.utf8)
        let phone = await sessions.act(.answer, session: session, device: "made-up-phone", body: body)
        #expect(phone == .actionsOff)
        #expect(page.writes.isEmpty)
        let request = RemoteActionRequest.answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Tris"])
        let result = await sessions.respond(request, session: session)
        #expect(result.result == .sent)
        #expect(page.writes == [.answer(frame: session, toolID: "toolu_made_up_1", answers: [buffer.question: "Tris"])])
    }

    @Test func theRequestIsReadAgainJustBeforeSending() async {
        let sessions = page.sessions()
        // Between showing and sending, the question was replaced.
        page.read = waitingRead(ask(toolID: "toolu_made_up_2"))
        let stale = RemoteActionRequest.answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Tris"])
        let result = await sessions.respond(stale, session: session)
        #expect(result == RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.questionChanged))
        #expect(page.writes.isEmpty)
        #expect(page.frameReads == 1)
        // Resolved elsewhere: the session runs again.
        page.read = waitingRead(status: "processing")
        #expect(await sessions.respond(stale, session: session).result == .changed)
        #expect(page.writes.isEmpty)
    }

    @Test func theReplierSendsThroughTheCoreWithThePhoneOff() async {
        let sessions = page.sessions()
        let model = LabModel()
        model.ingest(Fixture.snapshot(Fixture.session(session, .running)))
        model.ingest(Fixture.snapshot(Fixture.session(session, .needsInput, reason: .question, title: "Made-up")))
        let replier = QuestionReplier(model: model, dependencies: QuestionReplier.Dependencies(
            isEnabled: { true }, isReady: { true },
            read: { await sessions.readFrame($0) },
            respond: { await sessions.respond($0, session: $1, checking: $2) }))
        replier.sync()
        await replier.settled()
        #expect(replier.beginReply(session))
        replier.windowOpened(session)
        replier.updateDraft(session) { $0.pick(2, in: 0, multi: false) }
        replier.submit(session)
        await replier.settled()
        #expect(page.writes == [.answer(frame: session, toolID: "toolu_made_up_1", answers: [buffer.question: "PBS"])])
        #expect(replier.replies[session]?.phase == .sent(RemoteDecide.Sentence.answered))
    }

    /// The Mac and the phone answer at once: they take turns on the session's
    /// queue, each reading it afresh, so the second finds it answered and
    /// writes nothing.
    @Test func phoneAndMacAnswersTakeTurnsAndOnlyOneIsWritten() async {
        page.actionsOn = true
        page.resolvesOnWrite = true
        let sessions = page.sessions()
        let request = RemoteActionRequest.answer(toolID: "toolu_made_up_1", answers: [buffer.question: "Tris"])
        async let mac = sessions.respond(request, session: session)
        let body = Data(#"{"toolId":"toolu_made_up_1","answers":{"Which buffer should the made-up screen use?":"HEPES"}}"#.utf8)
        async let phone = sessions.act(.answer, session: session, device: "made-up-phone", body: body)
        let (macResult, phoneReply) = await (mac, phone)
        #expect(page.frameReads == 2)
        #expect(page.writes.count == 1)
        let phoneResult = (try? JSONSerialization.jsonObject(with: phoneReply.body) as? [String: Any])?["result"] as? String
        #expect([macResult.result.rawValue, phoneResult].sorted { ($0 ?? "") < ($1 ?? "") } == ["changed", "sent"])
    }
}
