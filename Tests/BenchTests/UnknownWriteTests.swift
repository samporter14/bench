// UnknownWriteTests.swift — a write that gets no answer is unknown, and a fresh
// read of the session settles it (Remote/WriteSettle.swift): it landed, it
// didn't (and can be tried again, by the person), or that can't be told. Never
// sent again on its own, and a session's queue moves on past a turn that stalls.
// Made-up sessions and a fake page; nothing reaches a real daemon.
import Foundation
import Testing
@testable import Bench

private let root = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"

private func projection(_ status: String, version: String? = nil, approval: PlanFrame.Approval = .no,
                        asks: [SessionProjection.Ask?] = [], queued: Int = 0,
                        turns: [SessionProjection.Turn]? = nil, permission: PermissionRequest? = nil) -> SessionProjection {
    SessionProjection(status: status, agentName: "made-up-agent", projectID: "proj-made-up", queued: queued, asks: asks,
                      planVersion: version, planArtifact: version == nil ? nil : "art-1", approval: approval,
                      turns: turns, permission: permission)
}

private func question(_ text: String = "Which buffer?", tool: String = "toolu_1") -> SessionProjection.Ask {
    SessionProjection.Ask(toolID: tool, items: [SessionProjection.Question(
        question: text, header: "Buffer", multi: false,
        options: [.init(label: "HEPES", detail: nil), .init(label: "Tris", detail: nil)])])
}

private let tool = PermissionRequest(requestID: "req-tool", toolID: "tool-1", mode: "parked", kind: "mcp_tool", frame: root,
                                     tool: "search_made_up_papers", server: "Made-up Library", source: "directory", readOnly: true)

/// A page that answers the read before a write from `before`, every read after it
/// from `after`, and a write from `reply`, or never.
@MainActor
private final class Rig {
    var before: SessionProjection? = projection("completed")
    var after: SessionProjection?
    var reply: RemoteWriteResult? = .unknown
    /// The first write goes in and never comes back, until `release()`.
    var firstWriteHangs = false
    /// The first read (before the write) never returns.
    var firstReadHangs = false
    var afterHangs = false
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    /// Every deadline (a turn's, the read that settles) waits on this; `clock.fire()` is "the time is up".
    let clock = ManualClock()
    private(set) var reads: [Bool] = []
    private(set) var writes: [RemoteWrite] = []
    private var parked: CheckedContinuation<Void, Never>?

    func sessions(turnLimit: Duration = .seconds(60), settleLimit: Duration = .seconds(60)) -> RemoteSessions {
        var dependencies = RemoteSessions.Dependencies(
            actionsOn: { true },
            known: { [] },
            cardPlan: { _ in nil },
            read: { id, full in
                self.reads.append(full)
                if self.firstReadHangs && self.reads.count == 1 { await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } }
                if self.writes.isEmpty { return full ? self.before : self.before?.withoutTurns }
                if self.afterHangs { await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } }
                return full ? self.after : self.after?.withoutTurns
            },
            readPlan: { _ in nil },
            write: { write in
                self.writes.append(write)
                if self.firstWriteHangs && self.writes.count == 1 { await withCheckedContinuation { self.parked = $0 } }
                return self.firstWriteHangs && self.writes.count > 1 ? RemoteWriteResult(status: 200, bodyStatus: "accepted") : self.reply
            },
            now: { self.now })
        dependencies.turnLimit = turnLimit
        dependencies.settleLimit = settleLimit
        dependencies.wait = { await self.clock.wait($0) }
        return RemoteSessions(dependencies: dependencies)
    }

    func release() {
        parked?.resume()
        parked = nil
    }

    var isParked: Bool { parked != nil }
}

/// What a request comes to, and how many times the checking line was called.
@MainActor
private func run(_ rig: Rig, _ request: RemoteActionRequest, sessions: RemoteSessions? = nil) async -> (result: RemoteActionResult, checking: Int) {
    var checking = 0
    let result = await (sessions ?? rig.sessions()).respond(request, session: root, checking: { checking += 1 })
    return (result, checking)
}

// MARK: Approving

@MainActor
struct UnknownApprovalTests {
    private let rig = Rig()
    private let approve = RemoteActionRequest.approve(version: "ver-1")

    @Test func aPlanStillWaitingMeansItDidNotGoThrough() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1")
        let (result, checking) = await run(rig, approve)
        #expect(result == .notThere)
        #expect(result.result == .retry && result.sentence == "That didn't go through. Try again.")
        #expect(checking == 1)
        #expect(rig.writes.count == 1)
    }

    @Test func aPlanThatIsWorkingNowWasApproved() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("processing", version: "ver-1")
        let (result, _) = await run(rig, approve)
        #expect(result == RemoteActionResult(result: .approved, sentence: RemoteDecide.Sentence.approved))
        #expect(rig.writes.count == 1)
    }

    @Test func aPlanFlaggedApprovedWasApproved() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1", approval: .yes)
        #expect(await run(rig, approve).result.result == .approved)
    }

    @Test func anotherPlanWaitingIsAChange() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-2")
        let (result, _) = await run(rig, approve)
        #expect(result == RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.planChanged))
    }

    @Test func aSessionThatCantBeReadAfterwardsIsUnknown() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = nil
        let (result, checking) = await run(rig, approve)
        #expect(result == .unsure)
        #expect(result.result == .unknown && result.sentence == RemoteDecide.Sentence.unsure)
        #expect(checking == 1)
        #expect(rig.writes.count == 1)
    }

    @Test func aStateThatSaysNeitherIsUnknown() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("failed", version: "ver-1")
        #expect(await run(rig, approve).result == .unsure)
    }

    @Test func aReadThatNeverReturnsIsCutOffAndIsUnknown() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.afterHangs = true
        // The turn's deadline and the read's are different lengths; only the read's passes.
        let sessions = rig.sessions(turnLimit: .seconds(61), settleLimit: .seconds(7))
        let task = Task { @MainActor in await run(rig, approve, sessions: sessions) }
        await rig.clock.until(waiting: 1, .seconds(7))
        rig.clock.fire(.seconds(7))
        let (result, checking) = await task.value
        #expect(result == .unsure)
        #expect(checking == 1)
        #expect(rig.clock.waiting(.seconds(61)) == 0, "the turn had finished, and its deadline was let go")
    }

    @Test func anAnswerThatCameBackNeverCallsTheCheckingLineOrReadsAgain() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.reply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        let (result, checking) = await run(rig, approve)
        #expect(result.result == .approved)
        #expect(checking == 0)
        #expect(rig.reads == [false])
    }
}

// MARK: Answering

@MainActor
struct UnknownAnswerTests {
    private let rig = Rig()
    private let answer = RemoteActionRequest.answer(toolID: "toolu_1", answers: ["Which buffer?": "HEPES"])

    @Test func aQuestionStillWaitingMeansItDidNotGoThrough() async {
        rig.before = projection("awaiting_user_response", asks: [question()])
        rig.after = projection("awaiting_user_response", asks: [question()])
        let (result, checking) = await run(rig, answer)
        #expect(result == .notThere)
        #expect(checking == 1)
        #expect(rig.writes.count == 1)
    }

    @Test func aQuestionThatIsGoneWasAnswered() async {
        rig.before = projection("awaiting_user_response", asks: [question()])
        rig.after = projection("processing")
        let (result, _) = await run(rig, answer)
        #expect(result == RemoteActionResult(result: .changed, sentence: RemoteDecide.Sentence.alreadyAnswered))
    }

    @Test func anotherQuestionWaitingMeansTheOneAskedWasAnswered() async {
        rig.before = projection("awaiting_user_response", asks: [question()])
        rig.after = projection("awaiting_user_response", asks: [question("Which temperature?", tool: "toolu_2")])
        #expect(await run(rig, answer).result.sentence == RemoteDecide.Sentence.alreadyAnswered)
    }

    @Test func aQuestionTheReadCouldntUnderstandCouldBeThisOne() async {
        rig.before = projection("awaiting_user_response", asks: [question()])
        rig.after = projection("awaiting_user_response", asks: [nil])
        #expect(await run(rig, answer).result == .unsure)
    }

    @Test func aSessionThatCantBeReadAfterwardsIsUnknown() async {
        rig.before = projection("awaiting_user_response", asks: [question()])
        rig.after = nil
        #expect(await run(rig, answer).result == .unsure)
    }

    @Test func chooseForMeAndCancelAreSettledTheSameWay() async {
        for request in [RemoteActionRequest.chooseForMe(toolID: "toolu_1"), .cancel(toolID: "toolu_1")] {
            let rig = Rig()
            rig.before = projection("awaiting_user_response", asks: [question()])
            rig.after = projection("awaiting_user_response", asks: [question()])
            #expect(await run(rig, request).result == .notThere)
            #expect(rig.writes.count == 1)
        }
    }
}

// MARK: A message

@MainActor
struct UnknownMessageTests {
    private let rig = Rig()
    private let message = RemoteActionRequest.message(text: "Try one panel per condition.", intentID: intent)

    private func you(_ text: String, after seconds: TimeInterval? = 1, intent: String? = nil,
                     files: [String] = []) -> SessionProjection.Turn {
        .init(role: .you, at: seconds.map { rig.now.addingTimeInterval($0) }, text: text, intent: intent, files: files)
    }

    private let other = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

    @Test func aMessageTheSessionShowsAsYoursWasSent() async {
        rig.after = projection("processing", turns: [you("Try one panel per condition.")])
        let (result, checking) = await run(rig, message)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent))
        #expect(checking == 1)
        #expect(rig.writes.count == 1)
        // The read that looked had the turns.
        #expect(rig.reads == [false, true])
    }

    @Test func toAFailedSessionItPicksUpAgain() async {
        rig.before = projection("failed")
        rig.after = projection("processing", turns: [you("Try one panel per condition.")])
        #expect(await run(rig, message).result.result == .resumed)
    }

    @Test func anOlderMessageOfTheSameWordsIsNotThisOne() async {
        rig.after = projection("completed", turns: [you("Try one panel per condition.", after: -3_600)])
        #expect(await run(rig, message).result == .notThere)
    }

    @Test func aTurnWithNoTimeCouldBeAnOlderOne() async {
        rig.after = projection("completed", turns: [you("Try one panel per condition.", after: nil)])
        #expect(await run(rig, message).result == .unsure)
    }

    @Test func aTurnOfClaudesWordsIsNotYours() async {
        rig.after = projection("completed", turns: [.init(role: .claude, at: rig.now.addingTimeInterval(1), text: "Try one panel per condition.")])
        #expect(await run(rig, message).result == .notThere)
    }

    @Test func aLargerQueueAloneIsNotThisMessageQueued() async {
        // Another device's message, or this one: the count can't say which, so it is neither queued nor sent.
        rig.before = projection("processing", queued: 1)
        rig.after = projection("processing", queued: 2, turns: [])
        let (result, _) = await run(rig, message)
        #expect(result == .unsure)
        #expect(result.result != .queued && result.result != .sent)
    }

    @Test func anotherDeviceRaisingTheQueueWhileItsOwnTurnShowsIsNotThisMessage() async {
        rig.before = projection("processing", queued: 0)
        rig.after = projection("processing", queued: 1, turns: [you("Plot the controls first.", intent: other)])
        let (result, _) = await run(rig, message)
        #expect(result == .unsure)
        #expect(rig.writes.count == 1)
    }

    @Test func aTurnWithThisMessagesIntentIsThisMessage() async {
        // Its words as the reader shows them may differ (cut, rewritten): the intent id is what ties it.
        rig.after = projection("processing", turns: [you("Try one panel per…", intent: intent)])
        #expect(await run(rig, message).result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent))
    }

    @Test func theSameWordsUnderAnotherIntentAreNeverThisMessage() async {
        // Another device's message of the same words: not this one, and not proof that this one is missing either.
        rig.after = projection("completed", turns: [you("Try one panel per condition.", intent: other)])
        #expect(await run(rig, message).result == .unsure)
        // From before the send, it says nothing of this one.
        let earlier = Rig()
        earlier.after = projection("completed", turns: [.init(role: .you, at: earlier.now.addingTimeInterval(-60),
                                                              text: "Try one panel per condition.", intent: other)])
        #expect(await run(earlier, message).result == .notThere)
        // Other words under another intent: another message.
        let elsewhere = Rig()
        elsewhere.after = projection("completed", turns: [.init(role: .you, at: elsewhere.now.addingTimeInterval(1),
                                                                text: "Plot the controls first.", intent: other)])
        #expect(await run(elsewhere, message).result == .notThere)
    }

    @Test func theSameWordsSentAMomentBeforeAreNotThisMessage() async {
        // Three seconds before the send began: an earlier message of the same words, not this one.
        rig.after = projection("completed", turns: [you("Try one panel per condition.", after: -3)])
        #expect(await run(rig, message).result == .notThere)
        let earlier = Rig()
        earlier.after = projection("completed", turns: [.init(role: .you, at: earlier.now.addingTimeInterval(-0.002),
                                                              text: "Try one panel per condition.")])
        #expect(await run(earlier, message).result == .notThere)
    }

    @Test func wordsThatOnlyShareAnOpeningAreAnotherMessage() async {
        rig.after = projection("completed", turns: [you("Try one panel per condition. Then plot the means.")])
        #expect(await run(rig, message).result == .notThere)
        // The other way round: this message says more than the turn.
        let longer = Rig()
        longer.after = projection("completed", turns: [you("Try one panel")])
        #expect(await run(longer, message).result == .notThere)
        // Two long messages that differ only after their first 200 characters.
        let opening = String(repeating: "Use the made-up buffer series again. ", count: 7)
        let long = Rig()
        long.after = projection("completed", turns: [.init(role: .you, at: long.now.addingTimeInterval(1), text: opening + "Then stop.")])
        #expect(await run(long, .message(text: opening + "Then plot.", intentID: intent)).result == .notThere)
    }

    @Test func aTurnCutShortThatCouldBeThisOneIsUnknown() async {
        let words = String(repeating: "word ", count: 600) + "end."
        let shown = String(words.prefix(SessionProjection.Limit.turn - 1)) + "…"
        rig.after = projection("completed", turns: [you(shown)])
        #expect(await run(rig, .message(text: words, intentID: intent)).result == .unsure)
    }

    @Test func aMessagesFilesAreToldApartByTheirIDsNotTheirNames() async {
        let mine = "11111111-1111-4111-8111-111111111111", theirs = "33333333-3333-4333-8333-333333333333"
        let line = #"{"type":"attachment","id":"\#(mine)","version_id":"22222222-2222-4222-8222-222222222222","filename":"plate.csv","artifact_ref":"{{artifact:22222222-2222-4222-8222-222222222222}}","content_type":"text/csv","size_bytes":10}"#
        let request = RemoteActionRequest.message(text: "Look at this.\n\n" + line, intentID: intent)
        // The same words and the same file name, but another file: another message.
        let another = Rig()
        another.after = projection("completed", turns: [you("Look at this.\n\nAttached: plate.csv", files: [theirs])])
        #expect(await run(another, request).result == .notThere)
        // The same words and this very file: this message.
        let same = Rig()
        same.after = projection("completed", turns: [you("Look at this.\n\nAttached: plate.csv", files: [mine])])
        #expect(await run(same, request).result.result == .sent)
        // The same words, but no files the reader could see: it could be this one.
        let unseen = Rig()
        unseen.after = projection("completed", turns: [you("Look at this.")])
        #expect(await run(unseen, request).result == .unsure)
        // A turn with a file, for a message without one: another message.
        let plain = Rig()
        plain.after = projection("completed", turns: [you("Look at this.\n\nAttached: plate.csv", files: [mine])])
        #expect(await run(plain, .message(text: "Look at this.", intentID: intent)).result == .notThere)
    }

    @Test func nothingShowingMeansItDidNotGoThrough() async {
        rig.before = projection("processing", queued: 1)
        rig.after = projection("processing", queued: 1, turns: [you("Something else entirely")])
        let (result, _) = await run(rig, message)
        #expect(result == .notThere)
        #expect(rig.writes.count == 1)
    }

    @Test func aSessionThatCantBeReadWithItsTurnsIsUnknown() async {
        rig.after = nil
        #expect(await run(rig, message).result == .unsure)
        let bare = Rig()
        bare.after = projection("completed", turns: nil)
        #expect(await run(bare, message).result == .unsure)
    }

    @Test func theWordsAreComparedWholeAndAttachmentLinesAreFilesNotWords() {
        let line = #"{"type":"attachment","id":"11111111-1111-4111-8111-111111111111","version_id":"22222222-2222-4222-8222-222222222222","filename":"plate.csv","artifact_ref":"{{artifact:11111111-1111-4111-8111-111111111111}}","content_type":"text/csv","size_bytes":10}"#
        let request = MessageSeen.Request("Look at this.\n\n" + line)
        #expect(request.words == "Look at this.")
        #expect(request.files == ["11111111-1111-4111-8111-111111111111"])
        #expect(MessageSeen.Request(line).words == "")
        let long = String(repeating: "word ", count: 100)
        #expect(MessageSeen.Request(long).words.count == long.count - 1, "all of them, not an opening")
        let photo = SessionProjection.Turn(role: .you, at: nil, text: "Look at this.\n\nAttached: plate.csv",
                                           files: ["11111111-1111-4111-8111-111111111111"])
        #expect(MessageSeen.Request("Look at this.\n\n" + line).compare(photo) == .same)
        #expect(MessageSeen.Request(line).compare(.init(role: .you, at: nil, text: "Attached: plate.csv",
                                                         files: ["11111111-1111-4111-8111-111111111111"])) == .same)
        #expect(MessageSeen.Request("Look at that.").compare(.init(role: .you, at: nil, text: "Look at this.")) == .different)
        // White space is one space.
        #expect(MessageSeen.Request("Look at this.").compare(.init(role: .you, at: nil, text: "Look   at\nthis.")) == .same)
    }
}

// MARK: A permission answer

@MainActor
struct UnknownPermissionTests {
    private let rig = Rig()
    private let allow = RemoteActionRequest.permission(id: "req-tool", allow: true, kind: nil)

    @Test func aRequestStillAtTheHeadMeansItDidNotGoThrough() async {
        rig.before = projection("awaiting_user_response", permission: tool)
        rig.after = projection("awaiting_user_response", permission: tool)
        let (result, checking) = await run(rig, allow)
        #expect(result == .notThere)
        #expect(checking == 1)
        #expect(rig.writes.count == 1)
    }

    @Test func aRequestThatIsGoneWasHandled() async {
        rig.before = projection("awaiting_user_response", permission: tool)
        rig.after = projection("processing")
        let (result, _) = await run(rig, allow)
        #expect(result == RemoteActionResult(result: .changed, sentence: PermissionDecide.Sentence.alreadyHandled))
    }

    @Test func aSessionStillWaitingThatShowsNoRequestIsUnknown() async {
        rig.before = projection("awaiting_user_response", permission: tool)
        rig.after = projection("awaiting_user_response")
        #expect(await run(rig, allow).result == .unsure)
    }

    @Test func aSessionThatCantBeReadAfterwardsIsUnknown() async {
        rig.before = projection("awaiting_user_response", permission: tool)
        rig.after = nil
        #expect(await run(rig, allow).result == .unsure)
    }
}

// MARK: What to change in a plan

@MainActor
struct UnknownPlanFeedbackTests {
    private let rig = Rig()
    private let feedback = RemoteActionRequest.planFeedback(version: "ver-1", text: "Use two replicates.", intentID: intent)

    private func you(_ text: String, intent: String? = nil) -> SessionProjection.Turn {
        .init(role: .you, at: rig.now.addingTimeInterval(1), text: text, intent: intent)
    }

    @Test func theSameWordsUnderAnotherIntentAreNotThemButOnlyTheIntentIsProof() async {
        // Another device sent the same words: never "sent" for these, and not "didn't go through" either.
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("processing", version: "ver-1",
                               turns: [you("Use two replicates.", intent: "7c9e6679-7425-40de-944b-e07fc1f90ae7")])
        #expect(await run(rig, feedback).result == .unsure)
        let mine = Rig()
        mine.before = projection("awaiting_plan_approval", version: "ver-1")
        mine.after = projection("processing", version: "ver-1",
                                turns: [.init(role: .you, at: mine.now.addingTimeInterval(1), text: "Use two…", intent: intent)])
        #expect(await run(mine, feedback).result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising))
    }

    @Test func wordsTheSessionShowsAsYoursWereSent() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("processing", version: "ver-1", turns: [you("Use two replicates.")])
        let (result, checking) = await run(rig, feedback)
        #expect(result == RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.revising))
        #expect(checking == 1)
        #expect(rig.writes.count == 1)
    }

    @Test func aPlanStillWaitingAtTheSameVersionWithoutThemDidNotGoThrough() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1", turns: [])
        #expect(await run(rig, feedback).result == .notThere)
    }

    @Test func aPlanThatMovedOnWithoutThemIsAChange() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-2", turns: [])
        #expect(await run(rig, feedback).result.result == .changed)
    }

    @Test func aSessionThatCantBeReadIsUnknown() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = nil
        #expect(await run(rig, feedback).result == .unsure)
    }
}

// MARK: The queue

@MainActor
struct SessionQueueDeadlineTests {
    private let rig = Rig()
    private let approve = RemoteActionRequest.approve(version: "ver-1")

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
    }

    @Test func aTurnThatNeverEndsIsUnknownAndTheNextOneGoes() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1")
        rig.firstWriteHangs = true
        let sessions = rig.sessions()
        let first = Task { @MainActor in await sessions.respond(approve, session: root) }
        await waitUntil { rig.isParked }
        // A second action on the same session, behind the stuck one.
        let second = Task { @MainActor in await sessions.respond(approve, session: root) }
        for _ in 0..<40 { await Task.yield() }
        rig.clock.fire()
        let stalled = await first.value
        #expect(stalled == .unsure, "the write had left, so it may have gone")
        let next = await second.value
        #expect(next.result == .approved)
        // Both wrote once each; the stuck write was never sent again.
        #expect(rig.writes.count == 2)
        rig.release()
        for _ in 0..<40 { await Task.yield() }
    }

    @Test func aTurnThatNeverGotToItsWriteIsNotCalledUnknown() async {
        // The read before the write never returns: the turn is given up, and nothing was sent.
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1")
        rig.firstReadHangs = true
        rig.reply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        let sessions = rig.sessions()
        let stuck = Task { @MainActor in await sessions.respond(approve, session: root) }
        for _ in 0..<2_000 where rig.reads.isEmpty { await Task.yield() }
        await rig.clock.until(waiting: 1)
        let next = Task { @MainActor in await sessions.respond(approve, session: root) }
        for _ in 0..<40 { await Task.yield() }
        rig.clock.fire()
        let first = await stuck.value
        #expect(first == .notThere, "it didn't go through, and can be tried again")
        #expect(first != .unsure)
        let second = await next.value
        #expect(second.result == .approved)
        #expect(rig.writes.count == 1, "only the second went")
    }

    @Test func aWriteThatLeftAfterTheTurnWasGivenUpOnSendsNothingMore() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.firstWriteHangs = true
        let sessions = rig.sessions()
        let first = Task { @MainActor in await sessions.respond(approve, session: root) }
        await waitUntil { rig.isParked }
        await rig.clock.until(waiting: 1)
        rig.clock.fire()
        _ = await first.value
        // The stuck write finally comes back: nothing follows it (no settle read, no second write).
        let readsThen = rig.reads.count
        rig.release()
        for _ in 0..<50 { await Task.yield() }
        #expect(rig.writes.count == 1)
        #expect(rig.reads.count == readsThen)
    }

    @Test func aCallerCancelledWhileItWaitsItsTurnNeverRuns() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.reply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        rig.firstWriteHangs = true
        let sessions = rig.sessions()
        let first = Task { @MainActor in await sessions.respond(approve, session: root) }
        await waitUntil { rig.isParked }
        let second = Task { @MainActor in await sessions.respond(approve, session: root) }
        for _ in 0..<20 { await Task.yield() }
        second.cancel()
        // It is released at once, with nothing sent.
        let cancelled = await second.value
        #expect(cancelled == .unavailable)
        rig.release()
        _ = await first.value
        #expect(rig.writes.count == 1)
        #expect(rig.reads.count == 1)
    }

    @Test func aTurnCancelledInTheQueueStillHoldsTheNextBehindTheOneInFlight() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1")
        rig.reply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        rig.firstWriteHangs = true
        let sessions = rig.sessions()
        // A is sending: its write is out and hasn't answered.
        let a = Task { @MainActor in await sessions.respond(approve, session: root) }
        await waitUntil { rig.isParked }
        await rig.clock.until(waiting: 1)
        #expect(rig.clock.waiting() == 1, "A's turn deadline")
        // B queues behind A and is cancelled while it waits: its caller hears at once.
        let b = Task { @MainActor in await sessions.respond(approve, session: root) }
        for _ in 0..<20 { await Task.yield() }
        b.cancel()
        #expect(await b.value == .unavailable)
        // C comes while A is still out. It must not begin before A is done.
        let c = Task { @MainActor in await sessions.respond(approve, session: root) }
        for _ in 0..<400 { await Task.yield() }
        #expect(rig.reads.count == 1, "only A has read: C waits")
        #expect(rig.writes.count == 1, "only A has written")
        #expect(rig.clock.waiting() == 1, "C's turn hasn't begun, so it has no deadline yet")
        // A comes back; then C has its turn.
        rig.release()
        #expect(await a.value.result == .approved)
        #expect(await c.value.result == .approved)
        // B never read or wrote; A and C each did once, A first.
        #expect(rig.reads.count == 2)
        #expect(rig.writes.count == 2)
    }

    @Test func turnsOfOneSessionRunOneAtATimeInOrder() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.after = projection("awaiting_plan_approval", version: "ver-1")
        rig.reply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        let sessions = rig.sessions()
        async let a = sessions.respond(approve, session: root)
        async let b = sessions.respond(approve, session: root)
        let results = await [a, b]
        #expect(results.map(\.result) == [.approved, .approved])
        #expect(rig.writes.count == 2)
    }

    @Test func aTurnThatIsOverInTimeEndsAsFinishedNotStalled() async {
        rig.before = projection("awaiting_plan_approval", version: "ver-1")
        rig.reply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        let sessions = rig.sessions(turnLimit: .seconds(30))
        let end = await sessions.runSerially(on: root, limit: .seconds(30)) { .ok(.unavailable) }
        guard case .finished = end else { Issue.record("not finished: \(end)"); return }
    }

    @Test func aTurnThatNeverReturnsIsStalledAndTheQueueIsFree() async {
        let sessions = rig.sessions()
        let stuck = Task { @MainActor in
            await sessions.runSerially(on: root, limit: .seconds(30)) {
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return .ok(.unavailable)
            }
        }
        await rig.clock.until(waiting: 1)
        rig.clock.fire()
        let end = await stuck.value
        guard case .stalled = end else { Issue.record("not stalled: \(end)"); return }
        let after = await sessions.runSerially(on: root, limit: .seconds(30)) { .ok(.unavailable) }
        guard case .finished = after else { Issue.record("not finished: \(after)"); return }
    }
}

// MARK: The phone

/// The phone's side of a write that got no answer: it says the Mac's sentence, reads the
/// session afresh, and leaves the words where they are, so a second try is the same message.
@Suite(.serialized)
struct PhoneUnknownTests {
    private func describe(_ result: String, sentence: String? = nil, status: Int = 200) throws -> [String: Any] {
        let app = try PhoneAppHarness(hash: "#/", now: Date(timeIntervalSince1970: 1_791_986_400), answers: [:])
        let data = sentence.map { #"{"result":"\#(result)","sentence":"\#($0)"}"# } ?? #"{"result":"\#(result)"}"#
        let json = try #require(app.string("JSON.stringify(describe({status:\(status),data:\(data)}))"))
        return try #require((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any])
    }

    @Test func aWriteThatDidntGoThroughIsSaidSoAndTheSessionIsReadAgain() throws {
        let said = try describe("retry", sentence: RemoteDecide.Sentence.notThere)
        #expect(said["ok"] as? Bool == false)
        #expect(said["refetch"] as? Bool == true)
        #expect(said["text"] as? String == "That didn't go through. Try again.")
        // No "Open on Mac" link: nothing is wrong that opening it would fix.
        #expect(said["open"] == nil)
    }

    @Test func aWriteThatCantBeToldIsNotCalledSentOrFailed() throws {
        let said = try describe("unknown", sentence: RemoteDecide.Sentence.unsure)
        #expect(said["ok"] as? Bool == false)
        #expect(said["refetch"] as? Bool == true)
        #expect(said["text"] as? String == RemoteDecide.Sentence.unsure)
        // It says to look on the Mac, and the link to do it is there.
        #expect(said["open"] as? Bool == true)
    }

    @Test func withoutASentenceThePhoneHasItsOwn() throws {
        #expect(try describe("retry")["text"] as? String == "That didn’t go through. Try again.")
        #expect((try describe("unknown")["text"] as? String)?.hasPrefix("Not sure that went through.") == true)
    }

    @Test func aSettledWriteIsStillJustDone() throws {
        let sent = try describe("sent", sentence: "Sent.")
        #expect(sent["ok"] as? Bool == true)
        #expect(sent["text"] as? String == "Sent.")
    }

    private static let id = "00000000-0000-4000-8000-00000000bb01"
    private static let session = #"{"can":{"answer":false,"approve":false,"message":"send","why":null},"id":"\#(id)","messages":[],"permission":null,"plan":null,"project":"Example project","question":null,"queued":null,"readable":true,"reason":null,"reply":null,"sentence":"Finished","startedAt":"2026-10-14T13:50:00Z","state":"finished","statusLine":null,"title":"Made-up screen","toYou":null,"turns":[],"updatedAt":"2026-10-14T13:59:00Z","version":2}"#

    private func page(also extra: [String: String] = [:]) throws -> PhoneAppHarness {
        try PhoneAppHarness(hash: "#/session/\(Self.id)", now: Date(timeIntervalSince1970: 1_791_986_400), answers: [
            "/api/me": #"{"paired":true,"browse":false,"act":true}"#,
            "/api/state": #"{"version":1,"bench":"1.0","updatedAt":"2026-10-14T14:00:00Z","problem":null,"needsYou":[],"failed":[],"working":[],"recent":[],"usage":null,"pause":null}"#,
            "/api/sessions/\(Self.id)": Self.session,
        ].merging(extra) { _, new in new })
    }

    private func note(_ app: PhoneAppHarness) -> String? {
        app.string("ui(\(PhoneAppHarness.quoted(Self.id))).note ? ui(\(PhoneAppHarness.quoted(Self.id))).note.text : null")
    }

    @Test func aWriteThatNothingHasAnsweredYetSaysItIsStillWaitingNotThatItIsChecking() throws {
        let app = try page()
        #expect(app.exceptions == [])
        // The Mac never answers this message.
        app.evaluate("doAction(\(PhoneAppHarness.quoted(Self.id)), 'message', '/api/sessions/\(Self.id)/message', { text: 'x', id: 'i' })")
        app.advance(21_000)
        #expect(note(app) == nil, "not before the Mac's own twenty seconds are up")
        app.advance(2_000)
        // The phone doesn't know whether the Mac is looking for the write or only waiting its turn behind another.
        #expect(note(app) == "Still waiting for your Mac…")
        #expect(note(app)?.contains("Not sure") == false)
    }

    /// The Mac's own "not sure" is its answer: it replaces the waiting line, with the way to look at it.
    @Test func whenTheMacAnswersNotSureTheWaitingLineGivesWayToItsSentence() throws {
        let app = try page(also: ["/api/sessions/\(Self.id)/message": #"{"result":"unknown","sentence":"\#(RemoteDecide.Sentence.unsure)"}"#])
        app.evaluate("doAction(\(PhoneAppHarness.quoted(Self.id)), 'message', '/api/sessions/\(Self.id)/message', { text: 'x', id: 'i' })")
        app.advance(500)
        #expect(note(app) == RemoteDecide.Sentence.unsure)
        #expect(note(app)?.contains("Still waiting") == false)
    }

    @Test func aPhotoGetsLongerBecauseItsUploadAloneTakesAMinute() throws {
        let app = try page()
        app.evaluate("doAction(\(PhoneAppHarness.quoted(Self.id)), 'message', '/api/sessions/\(Self.id)/photo', { image: 'x', text: '', id: 'i' }, PHOTO_SLOW_MS)")
        app.advance(60_000)
        #expect(note(app) == nil)
        app.advance(26_000)
        #expect(note(app) == "Still waiting for your Mac…")
    }

    @Test func theMacsDeadlineIsTheNumberThePhoneWaitsFor() {
        // The phone waits a little longer than the Mac gives a small write, and for a photo a little longer than its upload and the write.
        let app = RemoteWebApp.files["/app.js"]?.body ?? ""
        #expect(app.contains("const WRITE_SLOW_MS = 22000;"))
        #expect(app.contains("const PHOTO_SLOW_MS = 85000;"))
        #expect(WriteDeadline.small < .milliseconds(22_000))
        #expect(WriteDeadline.upload(bytes: PhotoImage.maxBytes) + WriteDeadline.small < .milliseconds(85_000))
    }

    @Test func theEmbeddedPageIsTheSourceOfTheSameWords() {
        let app = RemoteWebApp.files["/app.js"]?.body ?? ""
        #expect(app.contains("result === 'retry'") && app.contains("result === 'unknown'"))
    }
}
