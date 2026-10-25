// AskModelStreamingWindowTests.swift — the Ask window's model through a stream
// (AskModel/AskModel.swift): asking, then thinking, then words (drawn a tenth of
// a second apart at most), then the end; and the three ways it stops short
// (Cancel, a failure, a deadline), each keeping its words with Copy and without
// Send to Session. Also the rules for following the end of the text
// (AskScrollFollow.swift) and the words over it. A scripted ask stands in for the
// client, so the test says when each word arrives and when the clock is up;
// made-up sessions and answers; nothing reaches a daemon or another model.
import AppKit
import Foundation
import Testing
@testable import Bench

private let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

/// A scripted ask: the test says each word, the end, and when a tenth of a second is up.
@MainActor
private final class StreamRig {
    var asked = 0
    var now = ContinuousClock.now
    /// What the window drew, in order, and when (by `now`).
    var drawn: [String] = []
    var drawnAt: [ContinuousClock.Instant] = []
    var lines: [String] = []
    var copied: [String] = []
    var sent: [RemoteActionRequest] = []
    /// Everything said so far: what the ask hands back when it ends.
    var said = ""
    /// The wait that spaces the drawing.
    let drawClock = ManualClock()
    private var emit: (@MainActor (AskProgress) -> Void)?
    private var pending: CheckedContinuation<AnotherModelAnswer, Never>?

    func dependencies() -> AskDependencies {
        AskDependencies(
            readPage: { _ in nil },
            readTurn: { _, _ in nil },
            modelName: { "abliterated-model" },
            host: { "api.abliteration.ai" },
            limit: .seconds(120),
            ask: { _, progress in
                self.asked += 1
                self.emit = progress
                return await withTaskCancellationHandler {
                    await withCheckedContinuation { self.pending = $0 }
                } onCancel: {
                    // As the client does: Cancel ends it at once, keeping the words.
                    Task { @MainActor in self.end(.cancelled) }
                }
            },
            send: { request, _, _ in
                self.sent.append(request)
                return RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent)
            },
            pasteboard: { self.copied.append($0); return true },
            render: { text in
                self.drawn.append(text)
                self.drawnAt.append(self.now)
                return NSAttributedString(string: text)
            },
            clock: { self.now },
            wait: { await self.drawClock.wait($0) },
            log: { self.lines.append($0) })
    }

    func model() -> AskModel {
        AskModel(subject: AskSubject(sessionID: session, title: "Plate reader QC", projectName: "Assay development",
                                     seed: "Which buffer should the rerun use?"),
                 dependencies: dependencies())
    }

    func say(_ text: String) {
        said += text
        emit?(.words(text))
    }

    func think() { emit?(.thinking) }

    /// The ask ends: whole (nil), or in part.
    func end(_ failure: AnotherModelFailure? = nil) {
        pending?.resume(returning: AnotherModelAnswer(text: said, failure: failure))
        pending = nil
    }

    /// A tenth of a second is up for the drawing.
    func tick() async {
        drawClock.fire()
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor
private func settle(_ until: @MainActor () -> Bool) async {
    for _ in 0..<1_000 where !until() { await Task.yield() }
}

/// An ask that has begun: the model, asked.
@MainActor
private func asked(_ rig: StreamRig) async -> AskModel {
    let model = rig.model()
    model.ask()
    await settle { rig.asked == 1 }
    return model
}

// MARK: The states through a stream

@MainActor
struct AskStreamStatesTests {
    @Test func askingThenThinkingThenWordsThenAnswered() async {
        let rig = StreamRig()
        let model = await asked(rig)
        #expect(model.phase == .asking)
        #expect(model.isAsking && !model.canAsk)
        #expect(!model.thinking && model.answer == nil)

        // Reasoning only: still asking, but the window can say the model is thinking.
        rig.think()
        #expect(model.thinking && model.phase == .asking)
        #expect(model.answer == nil && rig.drawn.isEmpty)

        // The first words: streaming, drawn at once, thinking over.
        rig.now += .seconds(2)
        rig.say("Use ")
        #expect(model.phase == .streaming)
        #expect(!model.thinking)
        #expect(model.answer == "Use ")
        #expect(model.rendered.string == "Use ")
        #expect(model.isAsking && !model.canAsk)
        // Not an answer yet: nothing to time, nothing to copy or send.
        #expect(model.seconds == nil && model.answeredBy == nil)
        #expect(!model.canSend && model.sendCheck == nil && !model.isPartial)

        rig.now += .seconds(7)
        rig.say("**HEPES**.")
        rig.end()
        await settle { model.phase == .answered }
        #expect(model.phase == .answered)
        #expect(model.answer == "Use **HEPES**.")
        #expect(model.rendered.string == "Use **HEPES**.")
        #expect(model.seconds == 9)
        #expect(model.answeredBy == "abliterated-model")
        #expect(!model.isAsking && model.canAsk)
        #expect(rig.lines == ["Another model: asked, 34 characters, first word in 2 s, answered in 9 s"])
    }

    @Test func aFinishedAnswerCanBeCopiedAndSentAndOnlyThen() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("Use HEPES.")
        // While words arrive: Copy and Send do nothing.
        model.copy()
        model.sendToSession()
        #expect(rig.copied.isEmpty && rig.sent.isEmpty && !model.canSend)
        rig.end()
        await settle { model.phase == .answered }
        model.copy()
        #expect(rig.copied == ["Use HEPES."] && model.copied)
        #expect(model.canSend)
        model.sendToSession()
        await settle { model.sending != .sending }
        #expect(model.sending == .done("Sent to the session."))
        guard case .message(let text, _)? = rig.sent.first else {
            Issue.record("no message: \(rig.sent)")
            return
        }
        #expect(text == "Another model (abliterated-model) answered:\n\nUse HEPES.")
    }

    @Test func spacesAloneAreNoAnswerYet() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("\n\n")
        #expect(model.phase == .asking && rig.drawn.isEmpty)
        rig.say("Use")
        #expect(model.phase == .streaming)
        #expect(model.answer == "\n\nUse")
    }

    @Test func aServerThatSendsItWholeGoesStraightFromAskingToAnswered() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.said = "Use **HEPES** at 25 mM."
        rig.end()
        await settle { model.phase == .answered }
        #expect(model.answer == "Use **HEPES** at 25 mM.")
        #expect(rig.drawn == ["Use **HEPES** at 25 mM."])
        // No word arrived on its own, so no first word is told.
        #expect(rig.lines == ["Another model: asked, 34 characters, answered in 0 s"])
    }

    @Test func theLogIsCountsAndFixedWordsAndNeverTheWords() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.think()
        rig.now += .seconds(3)
        rig.say("Use HEPES at 25 mM in the plate buffer.")
        rig.now += .seconds(4)
        rig.end(.cutOff(.stalled))
        await settle { model.phase != .streaming }
        #expect(rig.lines == ["Another model: asked, 34 characters, first word in 3 s, failed after 7 s, stalled"])
        for line in rig.lines {
            for words in ["HEPES", "plate", "buffer", "abliterated", "Plate reader QC", "Assay development", "api."] {
                #expect(!line.contains(words), "\(line)")
            }
        }
    }

    @Test func askingAgainAfterAStopStartsClean() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("Use HEPES")
        rig.end(.cutOff(.stalled))
        await settle { model.isPartial }
        #expect(model.canAsk)
        rig.said = ""
        model.ask()
        await settle { rig.asked == 2 }
        #expect(model.phase == .asking)
        #expect(model.answer == nil && model.rendered.string.isEmpty && model.seconds == nil && model.answeredBy == nil)
        #expect(!model.isPartial && model.sendCheck == nil && !model.thinking)
        rig.say("Tris.")
        rig.end()
        await settle { model.phase == .answered }
        #expect(model.answer == "Tris.")
    }

    @Test func aWindowAlreadyAskingTakesNoNewSeedAndNoNewAsk() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("Use")
        model.reseed("Something else entirely.")
        #expect(model.question == "Which buffer should the rerun use?")
        model.ask()
        #expect(rig.asked == 1)
    }
}

// MARK: The drawing, a tenth of a second apart

@MainActor
struct AskStreamDrawingTests {
    @Test func theFirstWordsAreDrawnAtOnceAndTheRestNoMoreThanOnceInATenthOfASecond() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("a")
        #expect(rig.drawn == ["a"])
        // Fifty more words in the same instant: one drawing waits, and nothing more is drawn yet.
        for _ in 0..<50 { rig.say("b") }
        #expect(rig.drawn == ["a"])
        #expect(model.answer == "a")
        await rig.drawClock.until(waiting: 1)
        #expect(rig.drawClock.waiting(.milliseconds(100)) == 1)
        await rig.tick()
        #expect(rig.drawn.count == 2)
        #expect(model.answer == "a" + String(repeating: "b", count: 50))
        #expect(rig.drawn.last == model.answer)
        // Later in the next tenth of a second, the wait is only what is left of it.
        rig.now += .milliseconds(30)
        rig.say("c")
        await rig.drawClock.until(waiting: 1)
        #expect(rig.drawClock.waiting(.milliseconds(70)) == 1)
        rig.say("d")
        #expect(rig.drawClock.waiting() == 1)
        await rig.tick()
        #expect(rig.drawn.count == 3)
        #expect(rig.drawn.last?.hasSuffix("cd") == true)
        // A tenth of a second has passed since the last drawing: the next word is drawn at once.
        rig.now += .milliseconds(100)
        rig.say("e")
        #expect(rig.drawn.count == 4)
    }

    @Test func aSecondOfWordsIsDrawnAboutTenTimes() async {
        let rig = StreamRig()
        _ = await asked(rig)
        for _ in 0..<100 {
            rig.now += .milliseconds(10)
            rig.say("word ")
            for _ in 0..<5 { await Task.yield() }
            // The timer runs out when its time is up, as a real one does.
            if let last = rig.drawnAt.last, rig.now >= last + AskRules.renderEvery, rig.drawClock.waiting() > 0 {
                await rig.tick()
            }
        }
        // A hundred words in a second: about ten drawings, never one a word.
        #expect((9...12).contains(rig.drawn.count), "\(rig.drawn.count)")
        for (earlier, later) in zip(rig.drawnAt, rig.drawnAt.dropFirst()) {
            #expect(later - earlier >= AskRules.renderEvery, "drawn too soon after the one before")
        }
    }

    @Test func theEndDrawsEveryWordAtOnceAndLeavesNoDrawingWaiting() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("a")
        rig.say("b")
        rig.say("c")
        #expect(rig.drawn == ["a"])
        await rig.drawClock.until(waiting: 1)
        #expect(rig.drawClock.waiting() == 1)
        rig.end()
        await settle { model.phase == .answered }
        // An ending never shows fewer words than the answer holds.
        #expect(model.rendered.string == "abc" && model.answer == "abc")
        #expect(rig.drawn.last == "abc")
        let drawings = rig.drawn.count
        // The drawing that was waiting is gone: the clock running out draws nothing.
        for _ in 0..<50 where rig.drawClock.waiting() > 0 { await Task.yield() }
        #expect(rig.drawClock.waiting() == 0)
        rig.drawClock.fire()
        await rig.tick()
        #expect(rig.drawn.count == drawings)
    }

    @Test func stoppingDrawsEveryWordThatCame() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("Use ")
        rig.say("HEPES")
        rig.say(" at 25 mM")
        #expect(model.answer == "Use ")
        model.cancel()
        await settle { model.phase == .cancelled }
        #expect(model.answer == "Use HEPES at 25 mM")
        #expect(model.rendered.string == "Use HEPES at 25 mM")
    }
}

// MARK: Stopping short

@MainActor
struct AskStreamStoppedTests {
    @Test func cancelMidStreamKeepsTheWordsAndMarksThemStopped() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.now += .seconds(1)
        rig.say("Use HEPES")
        rig.now += .seconds(13)
        model.cancel()
        await settle { model.phase == .cancelled }
        #expect(model.phase == .cancelled)
        #expect(model.isPartial && !model.isAsking && model.canAsk)
        #expect(model.answer == "Use HEPES" && model.seconds == 14)
        #expect(AskRules.caption(phase: model.phase, seconds: model.seconds, answeredBy: model.answeredBy, model: model.modelName)
            == "Stopped after 14 s")
        #expect(rig.lines == ["Another model: asked, 34 characters, first word in 1 s, cancelled after 14 s"])
        #expect(rig.asked == 1)
    }

    @Test func aStoppedAnswerCanBeCopiedButNotSent() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("Use HEPES")
        model.cancel()
        await settle { model.isPartial }
        #expect(model.sendCheck == .partial)
        #expect(!model.canSend)
        #expect(AskRules.unsendable(.partial) == "Only part of the answer came, so it can\u{2019}t be sent. Copy it instead.")
        model.sendToSession()
        #expect(rig.sent.isEmpty && model.sending == .idle)
        model.copy()
        #expect(rig.copied == ["Use HEPES"] && model.copied)
    }

    @Test func cancelBeforeAnyWordIsJustCancelled() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.think()
        model.cancel()
        await settle { model.phase == .cancelled }
        #expect(model.phase == .cancelled)
        #expect(!model.isPartial && model.answer == nil && !model.thinking)
        #expect(model.sendCheck == nil && !model.canSend)
        #expect(rig.lines.count == 1 && rig.lines[0].contains("cancelled after") && !rig.lines[0].contains("first word"))
    }

    @Test func aFailureMidStreamKeepsTheWordsWithItsSentence() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.now += .seconds(2)
        rig.say("Use HEPES at 25 mM, because")
        rig.now += .seconds(68)
        rig.end(.cutOff(.stalled))
        await settle { model.phase != .streaming }
        #expect(model.phase == .failed("The answer stopped coming. Ask again, or ask something shorter."))
        #expect(model.isPartial && model.canAsk)
        #expect(model.answer == "Use HEPES at 25 mM, because")
        #expect(model.sendCheck == .partial && !model.canSend)
        #expect(AskRules.caption(phase: model.phase, seconds: model.seconds, answeredBy: model.answeredBy, model: model.modelName)
            == "Cut off after 70 s")
        model.copy()
        model.sendToSession()
        #expect(rig.copied == ["Use HEPES at 25 mM, because"] && rig.sent.isEmpty)
    }

    @Test func eachWayItEndsKeepsItsWordsAndSaysItsOwnSentence() async {
        let endings: [AnotherModelFailure] = [.timedOut, .cutOff(.stalled), .cutOff(.overran), .cutOff(.closed), .cutOff(.errored),
                                              .offline, .unreachable]
        for failure in endings {
            let rig = StreamRig()
            let model = await asked(rig)
            rig.say("Use HEPES")
            rig.end(failure)
            await settle { model.phase != .streaming }
            #expect(model.phase == .failed(failure.sentence(host: "api.abliteration.ai", limit: .seconds(120))), "\(failure)")
            #expect(model.answer == "Use HEPES" && model.isPartial, "\(failure)")
        }
    }

    @Test func aFailureBeforeAnyWordIsOneSentenceAndNoWords() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.think()
        rig.end(.cutOff(.errored))
        await settle { model.phase != .asking }
        #expect(model.phase == .failed("api.abliteration.ai reported an error while it was answering. Try again in a moment."))
        #expect(!model.isPartial && model.answer == nil && !model.thinking)
        #expect(model.sendCheck == nil && !model.canSend)
        model.copy()
        #expect(rig.copied.isEmpty)
    }

    @Test func closingTheWindowEndsTheStreamAndKeepsNothingDrawing() async {
        let rig = StreamRig()
        let model = await asked(rig)
        rig.say("a")
        rig.say("b")
        model.close()
        await settle { model.phase == .cancelled }
        #expect(model.phase == .cancelled)
        #expect(model.answer == "ab")
    }
}

// MARK: The words over the answer

struct AskCaptionTests {
    private func caption(_ phase: AskModel.Phase, _ seconds: Int?, by: String? = "abliterated-model") -> String {
        AskRules.caption(phase: phase, seconds: seconds, answeredBy: by, model: "abliterated-model")
    }

    @Test func theLineOverTheWordsChangesOnlyItsWords() {
        #expect(caption(.streaming, nil) == "Answering\u{2026}")
        #expect(caption(.answered, 9) == "Answered in 9 s")
        #expect(caption(.answered, 0) == "Answered in under a second")
        #expect(caption(.cancelled, 14) == "Stopped after 14 s")
        #expect(caption(.cancelled, 0) == "Stopped after under a second")
        #expect(caption(.failed("x"), 70) == "Cut off after 70 s")
        // The model is named when it isn't the one chosen now.
        #expect(caption(.answered, 9, by: "abliterated-model-large") == "abliterated-model-large answered in 9 s")
    }
}

// MARK: Following the end

struct AskScrollFollowTests {
    private typealias Metrics = AskScrollMetrics

    /// The rule with its state held in an object, so `#expect` can call it.
    private final class Follower {
        private var rule = AskScrollFollow()
        var following: Bool { rule.following }
        func update(from old: Metrics, to new: Metrics) -> Bool { rule.update(from: old, to: new) }
    }

    /// A 400-point window over a text `content` points tall, scrolled `top` down.
    private func at(_ top: CGFloat, of content: CGFloat, viewport: CGFloat = 400) -> Metrics {
        Metrics(top: top, bottom: top + viewport, content: content)
    }

    @Test func aTextThatGrowsWithTheReadersPlaceUnchangedIsGrowthAndNotAScrollUp() {
        let follow = Follower()
        // At the end of 500 points, the text grows to 520: the top is where it was.
        let goes = follow.update(from: at(100, of: 500), to: at(100, of: 520))
        #expect(goes, "following, and the end moved away")
        #expect(follow.following)
        // And again: still following.
        #expect(follow.update(from: at(100, of: 520), to: at(100, of: 560)))
        #expect(follow.following)
    }

    @Test func goingToTheEndItselfChangesNothing() {
        let follow = Follower()
        #expect(!follow.update(from: at(100, of: 560), to: at(160, of: 560)))
        #expect(follow.following)
    }

    @Test func scrollingUpStopsTheFollowingAndGrowthThenLeavesTheReaderWhereTheyAre() {
        let follow = Follower()
        #expect(!follow.update(from: at(160, of: 560), to: at(80, of: 560)))
        #expect(!follow.following)
        #expect(!follow.update(from: at(80, of: 560), to: at(80, of: 700)))
        #expect(!follow.following)
        // Scrolling down, but short of the end, does not start it again.
        #expect(!follow.update(from: at(80, of: 700), to: at(200, of: 700)))
        #expect(!follow.following)
    }

    @Test func reachingTheEndAgainStartsFollowingAgain() {
        let follow = Follower()
        _ = follow.update(from: at(160, of: 560), to: at(60, of: 560))
        #expect(!follow.following)
        // Scrolled down to within a few points of the end.
        #expect(!follow.update(from: at(60, of: 560), to: at(155, of: 560)))
        #expect(follow.following)
        #expect(follow.update(from: at(155, of: 560), to: at(155, of: 640)))
    }

    @Test func aSmallWobbleIsNotAScrollUp() {
        let follow = Follower()
        _ = follow.update(from: at(160, of: 560), to: at(159, of: 560))
        #expect(follow.following)
    }

    @Test func aTextThatShrinksUnderTheReaderAtTheEndDoesNotStopIt() {
        let follow = Follower()
        // The text is drawn again a little shorter: the view clamps to the new end, the top moves up.
        #expect(!follow.update(from: at(160, of: 560), to: at(140, of: 540)))
        #expect(follow.following)
    }

    @Test func theFootAppearingBelowTheAnswerKeepsItAtTheEndWhileFollowing() {
        let follow = Follower()
        // The window under the text shrinks by 50 points: the top stays, the bottom moves up.
        let shorter = Metrics(top: 160, bottom: 510, content: 560)
        #expect(follow.update(from: at(160, of: 560), to: shorter))
        // A reader who has scrolled up is left alone.
        let reading = Follower()
        _ = reading.update(from: at(160, of: 560), to: at(40, of: 560))
        #expect(!reading.update(from: at(40, of: 560), to: Metrics(top: 40, bottom: 390, content: 560)))
    }

    @Test func aTextShorterThanTheWindowHasNothingToFollow() {
        let follow = Follower()
        #expect(!follow.update(from: at(0, of: 120), to: at(0, of: 180)))
        #expect(follow.following)
        // Growing past the window: now the end is out of reach.
        #expect(follow.update(from: at(0, of: 380), to: at(0, of: 440)))
    }
}
