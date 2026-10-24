// AskModelTests.swift — the Ask Another Model window's rules and model (AskModel/
// AskModel.swift): the question read from the session's last message (whole
// when the page cut it), never over what the user typed; the conversation that
// goes with it (text turns before that message, ten at most, 12,000 characters
// at most) and only when the switch is on; the log in counts; Cancel; and Send
// to Session through the bounded path, with its outcomes and its intent id.
// Made-up sessions and answers; nothing reaches a daemon or another model.
import AppKit
import Foundation
import Testing
@testable import Bench

private let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

private func page(_ items: [HistoryItem], total: Int? = nil) -> HistoryPage {
    HistoryPage(total: total ?? ((items.last?.index ?? 0) + 1), from: items.first?.index ?? 0, items: items)
}

private func you(_ i: Int, _ text: String, cut: Bool = false) -> HistoryItem {
    .turn(i: i, role: .you, at: nil, text: text, cut: cut, files: [])
}

private func claude(_ i: Int, _ text: String) -> HistoryItem {
    .turn(i: i, role: .claude, at: nil, text: text, cut: false, files: [])
}

/// A session: plate QC, a rerun asked about, and Claude declining.
private let qcPage = page([
    you(0, "Load the plate reader export for plate 3."),
    claude(1, "Loaded: 96 wells, two failed QC (A3, B7)."),
    .steps(i: 2, line: "Ran 3 commands", failed: false, files: []),
    you(3, "Which buffer should the rerun use?"),
    claude(4, "I can't recommend that here."),
])

// MARK: The rules

struct AskRulesTests {
    @Test func theQuestionIsYourLastMessageAndTheConversationIsWhatCameBeforeIt() throws {
        let found = AskRules.read(qcPage)
        let question = try #require(found.question)
        #expect(question.row == 3)
        #expect(question.text == "Which buffer should the rerun use?")
        #expect(question.cut == false)
        // Text turns only, and Claude's reply to the question is never sent.
        #expect(found.before == [AskTurn(id: 0, role: .you, text: "Load the plate reader export for plate 3."),
                                 AskTurn(id: 1, role: .claude, text: "Loaded: 96 wells, two failed QC (A3, B7).")])
    }

    @Test func whatClaudeSentYouMidRunCountsAsItsWords() {
        let found = AskRules.read(page([
            you(0, "Normalize the counts."),
            .toYou(i: 1, text: "Halfway: 4 of 8 plates done.", files: []),
            .plan(i: 2, steps: 4),
            .ask(i: 3, q: "Which control?", a: "DMSO"),
            you(4, "Now plot them."),
        ]))
        #expect(found.before.map(\.text) == ["Normalize the counts.", "Halfway: 4 of 8 plates done."])
        #expect(found.before.map(\.role) == [.you, .claude])
    }

    @Test func aSessionWithNoMessageOfYoursHasNoQuestion() {
        let found = AskRules.read(page([claude(0, "Ready.")]))
        #expect(found.question == nil)
        #expect(found.before.map(\.text) == ["Ready."])
        #expect(AskRules.read(page([])).question == nil)
    }

    @Test func theConversationIsTheNewestTenTurnsAndTwelveThousandCharactersAtMost() {
        let many = (0..<14).map { AskTurn(id: $0, role: $0 % 2 == 0 ? .you : .claude, text: "turn \($0)") }
        let kept = AskRules.conversation(many)
        #expect(kept.count == 10)
        #expect(kept.first?.id == 4 && kept.last?.id == 13)
        // Long turns: the newest that fit, and an older one never without the newer.
        let long = [AskTurn(id: 0, role: .you, text: String(repeating: "a", count: 3_000)),
                    AskTurn(id: 1, role: .claude, text: String(repeating: "b", count: 5_000)),
                    AskTurn(id: 2, role: .you, text: String(repeating: "c", count: 6_000)),
                    AskTurn(id: 3, role: .claude, text: String(repeating: "d", count: 2_000))]
        #expect(AskRules.conversation(long).map(\.id) == [2, 3])
        #expect(AskRules.conversation([]).isEmpty)
    }

    @Test func theChatIsTheTurnsThenTheQuestion() {
        let chat = AskRules.chat(question: "Which buffer?", conversation: [
            AskTurn(id: 0, role: .you, text: "Load plate 3."), AskTurn(id: 1, role: .claude, text: "Loaded.")])
        #expect(chat == [ChatTurn(role: .user, text: "Load plate 3."), ChatTurn(role: .assistant, text: "Loaded."),
                         ChatTurn(role: .user, text: "Which buffer?")])
        #expect(AskRules.chat(question: "Which buffer?", conversation: []) == [ChatTurn(role: .user, text: "Which buffer?")])
    }

    @Test func aQuestionIsTrimmedAndNeitherEmptyNorEndless() {
        #expect(AskRules.question("  Which buffer?\n") == "Which buffer?")
        #expect(AskRules.question(" \n ") == nil)
        #expect(AskRules.question(String(repeating: "q", count: AskRules.maxQuestion + 1)) == nil)
    }

    @Test func theMessageNamesTheModelOnItsFirstLine() {
        let text = AskRules.message(answer: "\nUse HEPES at 25 mM.\n", model: "abliterated-model")
        #expect(text == "Another model (abliterated-model) answered:\n\nUse HEPES at 25 mM.")
        #expect(text.split(separator: "\n", omittingEmptySubsequences: false).first == "Another model (abliterated-model) answered:")
    }

    @Test func anAnswerTooLongOrWithAReferenceCantGoAsAMessage() {
        #expect(AskRules.sendable(answer: "Use HEPES.", model: "m") == .ok("Another model (m) answered:\n\nUse HEPES."))
        let long = String(repeating: "x", count: 4_000)
        guard case .tooLong(let count) = AskRules.sendable(answer: long, model: "m") else {
            Issue.record("a long answer was taken")
            return
        }
        #expect(count == 4_000 + "Another model (m) answered:\n\n".count)
        #expect(AskRules.unsendable(.tooLong(4_031))
            == "Too long to send as a message (4,031 characters; the most is 4,000). Copy it instead.")
        #expect(AskRules.sendable(answer: #"See {"type":"attachment","id":"x"}"#, model: "m") == .reference)
        #expect(AskRules.unsendable(.ok("x")) == nil)
    }

    @Test func theBoundedPathsAnswersReadInTheWindowsWords() {
        #expect(AskRules.outcome(RemoteActionResult(result: .sent, sentence: "Sent.")) == ("Sent to the session.", true))
        #expect(AskRules.outcome(RemoteActionResult(result: .queued, sentence: "")).sent)
        #expect(AskRules.outcome(RemoteActionResult(result: .resumed, sentence: "")).sent)
        #expect(AskRules.outcome(RemoteActionResult(result: .blocked, sentence: "Answer its question first."))
            == ("Answer its question first.", false))
        #expect(AskRules.outcome(.notThere) == ("That didn't go through. Try again.", false))
        #expect(AskRules.outcome(.unsure)
            == ("Not sure that went through. Look at the session before you send it again.", false))
        #expect(AskRules.outcome(.unavailable).sent == false)
    }

    @Test func theLogLineIsCountsAndFixedWords() {
        #expect(AskRules.logLine(characters: 812, turns: 0, seconds: 9, failure: nil)
            == "Another model: asked, 812 characters, answered in 9 s")
        #expect(AskRules.logLine(characters: 812, turns: 6, seconds: 9, failure: nil)
            == "Another model: asked, 812 characters, with 6 turns, answered in 9 s")
        #expect(AskRules.logLine(characters: 40, turns: 0, seconds: 120, failure: .timedOut)
            == "Another model: asked, 40 characters, failed after 120 s, timed out")
        #expect(AskRules.logLine(characters: 40, turns: 0, seconds: 3, failure: .cancelled)
            == "Another model: asked, 40 characters, cancelled after 3 s")
    }
}

// MARK: The window's model

@MainActor
private final class Rig {
    var page: HistoryPage? = qcPage
    var whole: HistoryTurn?
    var reads = 0
    var turnReads: [Int] = []
    var asked: [[ChatTurn]] = []
    var answer: Result<String, AnotherModelFailure> = .success("Use **HEPES** at 25 mM; Tris drifts with temperature.")
    var model: String? = "abliterated-model"
    var lines: [String] = []
    var sent: [RemoteActionRequest] = []
    var sendResult: RemoteActionResult = RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent)
    var copied: [String] = []
    /// Holds the read, or the ask, until `release()`.
    var holdRead = false
    var holdAsk = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var now = ContinuousClock.now
    /// The bounded path itself, when a test wants it in place of `sendResult`.
    var sessions: RemoteSessions?

    func dependencies() -> AskDependencies {
        AskDependencies(
            readPage: { _ in
                self.reads += 1
                if self.holdRead { await withCheckedContinuation { self.held.append($0) } }
                return self.page
            },
            readTurn: { _, row in
                self.turnReads.append(row)
                return self.whole
            },
            modelName: { self.model },
            host: { "api.abliteration.ai" },
            limit: .seconds(120),
            ask: { chat in
                self.asked.append(chat)
                if self.holdAsk {
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { self.held.append($0) }
                    } onCancel: {
                        Task { @MainActor in self.release() }
                    }
                    if Task.isCancelled { return .failure(.cancelled) }
                }
                self.now += .seconds(9)
                return self.answer
            },
            send: { request, id, checking in
                self.sent.append(request)
                if let sessions = self.sessions { return await sessions.respond(request, session: id, checking: checking) }
                return self.sendResult
            },
            pasteboard: { self.copied.append($0); return true },
            render: { NSAttributedString(string: $0) },
            clock: { self.now },
            log: { self.lines.append($0) })
    }

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func model(seed: String? = nil) -> AskModel {
        AskModel(subject: AskSubject(sessionID: session, title: "Plate reader QC", projectName: "Assay development", seed: seed),
                 dependencies: dependencies())
    }
}

@MainActor
private func settle(_ until: @MainActor () -> Bool) async {
    for _ in 0..<500 where !until() { await Task.yield() }
}

@MainActor
struct AskModelQuestionTests {
    @Test func itStartsFromTheSessionsLastQuestion() async {
        let rig = Rig()
        let model = rig.model()
        #expect(model.question.isEmpty)
        model.open()
        #expect(model.reading == .reading)
        await settle { model.reading == .read }
        #expect(model.question == "Which buffer should the rerun use?")
        #expect(rig.reads == 1)
        #expect(rig.turnReads.isEmpty)
    }

    @Test func aQuestionThePageCutIsReadWhole() async {
        let rig = Rig()
        rig.page = page([you(0, String(repeating: "w", count: 2_000), cut: true)])
        rig.whole = HistoryTurn(i: 0, role: .you, at: nil, text: String(repeating: "w", count: 2_500))
        let model = rig.model()
        model.open()
        await settle { model.reading == .read }
        #expect(rig.turnReads == [0])
        #expect(model.question.count == 2_500)
    }

    @Test func whatYouTypedIsNeverOverwrittenByALateRead() async {
        let rig = Rig()
        rig.holdRead = true
        let model = rig.model()
        model.open()
        await settle { rig.reads == 1 }
        model.question = "My own question."
        rig.release()
        await settle { model.reading == .read }
        #expect(model.question == "My own question.")
    }

    @Test func aSelectionIsTheQuestionAndNothingIsReadForIt() async {
        let rig = Rig()
        let model = rig.model(seed: "Tris drifts with temperature.")
        model.open()
        await settle { false }
        #expect(model.question == "Tris drifts with temperature.")
        #expect(rig.reads == 0)
        // The switch reads the conversation when it goes on, and only then.
        model.includeConversation = true
        await settle { model.reading == .read }
        #expect(rig.reads == 1)
        #expect(model.question == "Tris drifts with temperature.")
        #expect(model.conversation.count == 2)
    }

    @Test func anUnreadableSessionLeavesTheFieldToYou() async {
        let rig = Rig()
        rig.page = nil
        let model = rig.model()
        model.open()
        await settle { model.reading == .unreadable }
        #expect(model.question.isEmpty)
        #expect(model.canAsk == false)
        model.question = "Which buffer?"
        #expect(model.canAsk)
    }

    @Test func noModelChosenMeansNoAsk() {
        let rig = Rig()
        rig.model = nil
        let model = rig.model(seed: "Which buffer?")
        #expect(model.canAsk == false)
        model.ask()
        #expect(rig.asked.isEmpty)
    }
}

@MainActor
struct AskModelAskingTests {
    @Test func onlyTheQuestionGoesWhileTheSwitchIsOff() async {
        let rig = Rig()
        let model = rig.model()
        model.open()
        await settle { model.reading == .read }
        model.ask()
        await settle { model.phase == .answered }
        #expect(rig.asked == [[ChatTurn(role: .user, text: "Which buffer should the rerun use?")]])
        #expect(model.answer == "Use **HEPES** at 25 mM; Tris drifts with temperature.")
        #expect(model.answeredBy == "abliterated-model")
        #expect(model.seconds == 9)
        #expect(model.rendered.string == model.answer)
    }

    @Test func withTheSwitchOnTheListedTurnsGoBeforeIt() async {
        let rig = Rig()
        let model = rig.model()
        model.open()
        await settle { model.reading == .read }
        model.includeConversation = true
        model.ask()
        await settle { model.phase == .answered }
        #expect(rig.asked == [[ChatTurn(role: .user, text: "Load the plate reader export for plate 3."),
                               ChatTurn(role: .assistant, text: "Loaded: 96 wells, two failed QC (A3, B7)."),
                               ChatTurn(role: .user, text: "Which buffer should the rerun use?")]])
        // Exactly what the window lists.
        #expect(rig.asked.first?.dropLast().map(\.text) == model.conversation.map(\.text))
    }

    @Test func theLogSaysCountsAndNeverTheWords() async {
        let rig = Rig()
        let model = rig.model()
        model.open()
        await settle { model.reading == .read }
        model.includeConversation = true
        model.ask()
        await settle { model.phase == .answered }
        let characters = "Load the plate reader export for plate 3.".count + "Loaded: 96 wells, two failed QC (A3, B7).".count
            + "Which buffer should the rerun use?".count
        #expect(rig.lines == ["Another model: asked, \(characters) characters, with 2 turns, answered in 9 s"])
        for line in rig.lines {
            for words in ["buffer", "HEPES", "plate", "Plate reader QC", "Assay development", "abliterated"] {
                #expect(!line.contains(words), "\(line)")
            }
        }
    }

    @Test func aFailureIsItsSentenceAndAskCanBePressedAgain() async {
        let rig = Rig()
        rig.answer = .failure(.keyRefused)
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        await settle { model.phase != .asking && model.phase != .ready }
        #expect(model.phase == .failed("api.abliteration.ai didn\u{2019}t accept your key. Check it in Settings \u{2192} General."))
        #expect(model.answer == nil)
        #expect(model.canAsk)
        #expect(rig.lines == ["Another model: asked, 13 characters, failed after 9 s, key not accepted"])
        // Asked once; nothing is tried again on its own.
        #expect(rig.asked.count == 1)
    }

    @Test func cancelEndsTheAskAndNothingMoreComes() async {
        let rig = Rig()
        rig.holdAsk = true
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        #expect(model.phase == .asking)
        #expect(model.canAsk == false)
        await settle { rig.asked.count == 1 }
        model.cancel()
        await settle { model.phase == .cancelled }
        #expect(model.phase == .cancelled)
        #expect(model.answer == nil)
        #expect(rig.lines.first?.hasPrefix("Another model: asked, 13 characters, cancelled after") == true)
    }

    @Test func closingTheWindowEndsTheAsk() async {
        let rig = Rig()
        rig.holdAsk = true
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        await settle { rig.asked.count == 1 }
        model.close()
        await settle { model.phase == .cancelled }
        #expect(model.phase == .cancelled)
    }

    @Test func copyPutsTheAnswerAsItCameOnThePasteboard() async {
        let rig = Rig()
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        await settle { model.phase == .answered }
        model.copy()
        #expect(rig.copied == ["Use **HEPES** at 25 mM; Tris drifts with temperature."])
        #expect(model.copied)
    }
}

// MARK: Send to Session

@MainActor
struct AskModelSendTests {
    private func answered(_ rig: Rig) async -> AskModel {
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        await settle { model.phase == .answered }
        return model
    }

    @Test func itPostsTheAnswerAsYourNextMessageAfterALineNamingTheModel() async throws {
        let rig = Rig()
        let model = await answered(rig)
        #expect(model.canSend)
        model.sendToSession()
        #expect(model.sending == .sending)
        #expect(model.canSend == false)
        await settle { model.sending != .sending }
        #expect(model.sending == .done("Sent to the session."))
        guard case .message(let text, let intent) = try #require(rig.sent.first) else {
            Issue.record("not a message: \(rig.sent)")
            return
        }
        #expect(text == "Another model (abliterated-model) answered:\n\nUse **HEPES** at 25 mM; Tris drifts with temperature.")
        #expect(RemoteActionRequest.isUUIDv4(intent))
        #expect(rig.lines.last == "Another model: sent the answer to the session, sent")
        // Sent: a second press sends nothing.
        model.sendToSession()
        #expect(rig.sent.count == 1)
    }

    @Test func aSecondPressWhileItGoesSendsNothing() async {
        let rig = Rig()
        let model = await answered(rig)
        model.sendToSession()
        model.sendToSession()
        await settle { model.sending != .sending }
        #expect(rig.sent.count == 1)
    }

    @Test func aTryAfterADidntGoThroughKeepsTheSameIntent() async {
        let rig = Rig()
        rig.sendResult = .notThere
        let model = await answered(rig)
        model.sendToSession()
        await settle { model.sending != .sending }
        #expect(model.sending == .failed("That didn't go through. Try again."))
        #expect(model.canSend)
        rig.sendResult = RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent)
        model.sendToSession()
        await settle { model.sending != .sending }
        #expect(rig.sent.count == 2)
        guard case .message(_, let first) = rig.sent[0], case .message(_, let second) = rig.sent[1] else {
            Issue.record("not messages")
            return
        }
        // The daemon tells a repeat by it, so a lost reply is never sent twice.
        #expect(first == second)
    }

    @Test func anAnswerTooLongToSendSaysSoAndSendsNothing() async {
        let rig = Rig()
        rig.answer = .success(String(repeating: "Long answer. ", count: 400))
        let model = await answered(rig)
        #expect(model.canSend == false)
        guard case .tooLong? = model.sendCheck else {
            Issue.record("not too long: \(String(describing: model.sendCheck))")
            return
        }
        model.sendToSession()
        #expect(rig.sent.isEmpty)
    }

    @Test func theMessageRequestIsCheckedAsThePhonesIs() {
        let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
        #expect(AskModel.message(text: " Use HEPES. ", intent: intent) == .message(text: "Use HEPES.", intentID: intent))
        #expect(AskModel.message(text: "Use HEPES.", intent: "not-a-uuid") == nil)
        #expect(AskModel.message(text: String(repeating: "x", count: 4_001), intent: intent) == nil)
        #expect(AskModel.message(text: #"{{artifact:abc}}"#, intent: intent) == nil)
        #expect(AskModel.message(text: "  ", intent: intent) == nil)
    }
}

// MARK: Send to Session, through the bounded path itself

/// A made-up page behind `RemoteSessions`: the read before the write, the
/// write (answered, or not at all), and the read that settles it.
@MainActor
private final class Page {
    var before = SessionProjection(status: "completed", agentName: "made-up-agent", projectID: "proj-made-up",
                                   queued: 0, asks: [], planVersion: nil, planArtifact: nil, approval: .no, turns: nil)
    var after: SessionProjection?
    var reply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted")
    private(set) var writes: [RemoteWrite] = []
    let start = Date(timeIntervalSince1970: 1_791_833_400)
    /// Every deadline waits on it, and none is up unless a test says so.
    let clock = ManualClock()

    func sessions() -> RemoteSessions {
        var dependencies = RemoteSessions.Dependencies(
            actionsOn: { false }, // The phone's switch: Send to Session doesn't ask it.
            known: { [] },
            cardPlan: { _ in nil },
            read: { _, full in
                let read = self.writes.isEmpty ? self.before : (self.after ?? self.before)
                return full ? read : read.withoutTurns
            },
            readPlan: { _ in nil },
            write: { write in
                self.writes.append(write)
                return self.reply
            },
            now: { self.start })
        dependencies.wait = { await self.clock.wait($0) }
        return RemoteSessions(dependencies: dependencies)
    }
}

@MainActor
struct AskModelBoundedSendTests {
    private func send(_ page: Page, checking: inout [AskModel.Sending]) async -> (AskModel, Rig) {
        let rig = Rig()
        rig.sessions = page.sessions()
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        await settle { model.phase == .answered }
        model.sendToSession()
        var seen: [AskModel.Sending] = []
        for _ in 0..<2_000 {
            if seen.last != model.sending { seen.append(model.sending) }
            if case .done = model.sending { break }
            if case .failed = model.sending { break }
            await Task.yield()
        }
        checking = seen
        return (model, rig)
    }

    @Test func itIsTheSessionsOwnMessageWriteWithTheIntentID() async throws {
        let page = Page()
        var states: [AskModel.Sending] = []
        let (model, _) = await send(page, checking: &states)
        #expect(model.sending == .done("Sent to the session."))
        let write = try #require(page.writes.first)
        #expect(page.writes.count == 1)
        guard case .message(let frame, let agent, let project, let text, let intent, let attachment) = write else {
            Issue.record("not a message write: \(write)")
            return
        }
        #expect(frame == session && agent == "made-up-agent" && project == "proj-made-up" && attachment == false)
        #expect(text.hasPrefix("Another model (abliterated-model) answered:\n\n"))
        #expect(RemoteActionRequest.isUUIDv4(intent))
    }

    @Test func aSessionWaitingOnAQuestionTakesNoMessage() async {
        let page = Page()
        page.before = SessionProjection(status: "awaiting_user_response", agentName: "made-up-agent", projectID: "proj-made-up",
                                        queued: 0, asks: [], planVersion: nil, planArtifact: nil, approval: .no, turns: nil)
        var states: [AskModel.Sending] = []
        let (model, _) = await send(page, checking: &states)
        #expect(model.sending == .failed("Answer its question first."))
        #expect(page.writes.isEmpty)
    }

    @Test func aWriteWithNoAnswerIsCheckedAndFoundByItsIntent() async throws {
        let page = Page()
        page.reply = .unknown
        var states: [AskModel.Sending] = []
        // The settling read shows a turn of yours carrying this message's intent id.
        let rig = Rig()
        rig.sessions = page.sessions()
        let model = rig.model(seed: "Which buffer?")
        model.ask()
        await settle { model.phase == .answered }
        model.sendToSession()
        for _ in 0..<2_000 where page.writes.isEmpty { await Task.yield() }
        guard case .message(_, _, _, let text, let intent, _)? = page.writes.first else {
            Issue.record("no write")
            return
        }
        page.after = SessionProjection(status: "processing", agentName: "made-up-agent", projectID: "proj-made-up",
                                       queued: 0, asks: [], planVersion: nil, planArtifact: nil, approval: .no,
                                       turns: [.init(role: .you, at: page.start.addingTimeInterval(1), text: text, intent: intent)])
        for _ in 0..<2_000 {
            if states.last != model.sending { states.append(model.sending) }
            if case .done = model.sending { break }
            if case .failed = model.sending { break }
            await Task.yield()
        }
        #expect(states.contains(.checking))
        #expect(model.sending == .done("Sent to the session."))
        #expect(page.writes.count == 1)
    }

    @Test func aWriteWithNoAnswerThatDidntLandIsTheUsersToTryAgain() async {
        let page = Page()
        page.reply = .unknown
        // The settling read has the turns, and none of them is this message.
        page.after = SessionProjection(status: "completed", agentName: "made-up-agent", projectID: "proj-made-up",
                                       queued: 0, asks: [], planVersion: nil, planArtifact: nil, approval: .no,
                                       turns: [.init(role: .you, at: page.start.addingTimeInterval(-60), text: "Which buffer?")])
        var states: [AskModel.Sending] = []
        let (model, rig) = await send(page, checking: &states)
        #expect(states.contains(.checking))
        #expect(model.sending == .failed("That didn't go through. Try again."))
        // Never sent again on its own.
        #expect(page.writes.count == 1)
        #expect(rig.lines.last == "Another model: sent the answer to the session, didn't go through")
    }
}
