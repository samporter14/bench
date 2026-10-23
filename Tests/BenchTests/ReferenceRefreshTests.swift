// ReferenceRefreshTests.swift — the reference reader kept up to date and
// whole (Reference/ReferenceModel.swift) on made-up histories: the newest rows
// read again when the window is shown again, becomes key or the session
// finishes (one read at a time, not within a few seconds of the last), a reply
// that landed while the window was away reached with Later, the reader never
// moved off a reply they are reading, a gap bridged or let go; Earlier pressed
// while a read is under way; a long message to the user read whole; and the
// words kept by Add to Shelf and Keep… waiting briefly for the rest, then
// saying so. No page, no daemon.
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Bench

/// The model's clock, which the test moves.
@MainActor
private final class MadeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func pass(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private func until(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1_000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw CancellationError()
}

/// Lets what was started finish, and anything it wrongly started.
@MainActor
private func quiet() async throws {
    for _ in 0..<40 { await Task.yield() }
    try await Task.sleep(for: .milliseconds(40))
}

@MainActor
private struct Story {
    let fake: FakeHistory
    let model: ReferenceModel
    let clock: MadeClock

    typealias Made = ReferenceModelTests

    /// Replies of ten rows each: the user asks at every tenth row and Claude
    /// answers in the last row of the ten (and `extra` says more, by row).
    static func rows(_ count: Int, extra: [Int: String] = [:], cut: Set<Int> = [], figures: [Int: [HistoryFile]] = [:]) -> [HistoryItem] {
        var you: [Int: String] = [:], claude: [Int: String] = extra
        for start in stride(from: 0, to: count, by: 10) {
            you[start] = "Question \(start / 10)"
            if start + 9 < count { claude[start + 9] = "Answer \(start / 10)" }
        }
        return Made.history(count, you: you, claude: claude, cut: cut, figures: figures)
    }

    init(_ rows: [HistoryItem]) {
        let (fake, model) = Made.make(rows)
        let clock = MadeClock()
        model.clock = { clock.now }
        self.fake = fake
        self.model = model
        self.clock = clock
    }

    /// The conversation goes on: more rows.
    func grow(to rows: [HistoryItem]) {
        fake.rows = rows
        fake.total = (rows.map(\.index).max() ?? -1) + 1
    }

    func open() async {
        model.open()
        await Made.settle(model)
    }

    /// Reads of the newest rows so far: the opening, and each refresh.
    var tailReads: Int { fake.pageReads.filter { $0 == nil }.count }
}

// MARK: The newest rows, read again

@MainActor
struct ReferenceRefreshTests {
    @Test func aReplyThatLandedWhileTheWindowWasAwayIsReachedWithLater() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        #expect(story.model.answers.map(\.id) == [9, 19, 29])
        // The reader is on an older reply when the conversation goes on.
        story.model.earlier()
        #expect(story.model.current?.id == 19)
        story.grow(to: Story.rows(40))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the new reply is read") { story.model.answers.count == 4 }
        // Nothing moved the reader; Later reaches it, a reply at a time.
        #expect(story.model.current?.id == 19)
        #expect(story.model.canGoLater)
        story.model.later()
        story.model.later()
        #expect(story.model.current?.id == 39)
        #expect(story.model.current?.text == "Answer 3")
        #expect(story.fake.pageReads == [nil, nil])
    }

    @Test func aWindowOnTheNewestReplyFollowsItToTheNewestAndStartsItAtTheTop() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        let key = story.model.shownKey
        #expect(story.model.current?.id == 29)
        story.grow(to: Story.rows(40))
        story.clock.pass(10)
        story.model.refresh()
        try await until("it follows") { story.model.current?.id == 39 }
        #expect(story.model.shownID == 39)
        #expect(story.model.shownKey == key + 1)
        #expect(story.model.current?.question == "Question 3")
    }

    @Test func theNewestReplyGrownByARowStaysWhereItIsOnThePage() async throws {
        // Reply 2 is under way: Claude has said one thing and gone on working.
        let you: [Int: String] = [0: "Question 0", 10: "Question 1", 20: "Question 2"]
        let said: [Int: String] = [9: "Answer 0", 19: "Answer 1", 24: "Working on the heatmap."]
        let story = Story(ReferenceModelTests.history(28, you: you, claude: said))
        await story.open()
        let before = try #require(story.model.current)
        #expect(before.text == "Working on the heatmap." && before.id == 27)
        let key = story.model.shownKey
        // It finishes: its last row moves, and it is the same reply.
        story.grow(to: ReferenceModelTests.history(34, you: you, claude: said.merging([33: "Here it is."]) { $1 }))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the reply grew") { story.model.current?.text == "Working on the heatmap.\n\nHere it is." }
        #expect(story.model.current?.id == 33)
        #expect(story.model.shownID == 33)
        #expect(story.model.current?.start == before.start)
        // The same reply: the page is not asked to start over.
        #expect(story.model.shownKey == key)
    }

    @Test func aWindowOnAnOlderReplyStaysOnItWhileTheNewestOneFinishes() async throws {
        // Three replies and a fourth under way; the reader steps back to the second.
        let story = Story(Story.rows(40).filter { $0.index != 39 })
        await story.open()
        #expect(story.model.answers.map(\.id) == [9, 19, 29])
        story.model.earlier()
        #expect(story.model.current?.id == 19)
        story.grow(to: Story.rows(40))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the fourth is read") { story.model.answers.last?.id == 39 }
        #expect(story.model.current?.id == 19)
        #expect(story.model.current?.text == "Answer 1")
    }

    @Test func oneReadAtATimeAndNotWithinAFewSecondsOfTheLast() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        #expect(story.tailReads == 1)
        // Shown again at once: the rows were read a moment ago.
        story.model.refresh()
        try await quiet()
        #expect(story.tailReads == 1)

        story.clock.pass(ReferenceModel.refreshEvery + 1)
        story.fake.holding = true
        story.model.refresh()
        story.model.refresh()
        story.model.refresh()
        try await until("the read began") { story.tailReads == 2 }
        try await quiet()
        // Three asks, one read, under way.
        #expect(story.tailReads == 2)
        story.fake.holding = false
        story.fake.release()
        try await quiet()
        // And it began the few seconds again.
        story.model.refresh()
        try await quiet()
        #expect(story.tailReads == 2)
        story.clock.pass(ReferenceModel.refreshEvery + 1)
        story.model.refresh()
        try await until("a read after the few seconds") { story.tailReads == 3 }
    }

    @Test func aSessionThatFinishesIsReadAgainAtOnce() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        // The session is running as the window opens (its state in the panel's reads), and finishes.
        story.model.sessionChanged(to: .running)
        story.model.sessionChanged(to: .running)
        try await quiet()
        #expect(story.tailReads == 1)
        story.grow(to: Story.rows(40))
        story.model.sessionChanged(to: .finished)
        try await until("the finished session is read") { story.model.answers.count == 4 }
        #expect(story.tailReads == 2)
        // A session that goes on running, or whose state is unknown, reads nothing.
        story.model.sessionChanged(to: nil)
        story.model.sessionChanged(to: .running)
        story.model.sessionChanged(to: .needsInput)
        try await until("a session that needs you has stopped writing") { story.tailReads == 3 }
    }

    @Test func aSessionThatFinishesWhileALookReadsIsReadAgainWhenTheLookEnds() async throws {
        let story = Story(Story.rows(300))
        await story.open()
        // Back to the oldest reply read, then a look for an older one, held.
        for _ in 0..<4 { story.model.earlier() }
        #expect(story.model.shownID == story.model.answers.first?.id)
        story.fake.holding = true
        story.model.earlier()
        try await until("the look began") { story.fake.pageReads.count == 2 }
        story.model.sessionChanged(to: .running)
        story.model.sessionChanged(to: .finished)
        #expect(story.tailReads == 1)
        story.fake.holding = false
        story.fake.release()
        try await until("the tail is read once the look is over") { story.tailReads == 2 }
    }

    @Test func aReadThatFailsChangesNothingAndSaysNothing() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        let before = story.model.answers
        story.fake.pagesThrow = true
        story.clock.pass(10)
        story.model.refresh()
        try await until("the failed read") { story.tailReads == 2 }
        try await quiet()
        #expect(story.model.phase == .idle)
        #expect(story.model.answers == before)
        #expect(story.model.current?.id == 29)
    }

    @Test func aTailReadNeverMarksTheStartAsReached() async throws {
        // The first read of a long history reaches back only 50 rows: a re-read of the newest
        // rows is no page back from them, and must not say row 0 was read.
        let story = Story(Story.rows(300))
        await story.open()
        #expect(!story.model.reachedStart)
        story.grow(to: Story.rows(310))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the new reply") { story.model.answers.last?.id == 309 }
        #expect(!story.model.reachedStart)
        #expect(story.model.canGoEarlier)
        // The rows read before are kept: the tail read joined them.
        #expect(story.model.from == 250)
    }

    // MARK: Rows between

    @Test func theRowsBetweenTheNewOnesAndWhatWasReadAreReadSoNoReplyIsSkipped() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        story.model.earlier()
        story.grow(to: Story.rows(130))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the gap is read") { story.model.answers.count == 13 }
        // The newest 50 rows, then the two pages back that meet what was read.
        #expect(story.fake.pageReads == [nil, nil, 80, 55])
        #expect(story.model.answers.map(\.id) == Array(stride(from: 9, through: 129, by: 10)))
        #expect(story.model.reachedStart)
        // The reader is where they were.
        #expect(story.model.current?.id == 19)
        #expect(story.model.caption.hasSuffix(" · 2 of 13"))
    }

    @Test func aGapTooFarToBridgeLetsTheOldRowsGoAndTheWindowStartsFromTheNewEnd() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        #expect(story.model.current?.id == 29)
        story.grow(to: Story.rows(400))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the newest reply is shown") { story.model.current?.id == 399 }
        // The newest 50 rows and a look's worth of pages back: 350 down to 150.
        #expect(story.fake.pageReads.count == 2 + ReferenceModel.pagesPerLook)
        #expect(story.model.from == 150)
        #expect(!story.model.reachedStart)
        #expect(story.model.answers.first?.id ?? 0 >= 150)
        // Earlier reads back from there again.
        #expect(story.model.canGoEarlier)
    }

    @Test func aWindowThatFoundNoReplyLooksAgain() async throws {
        let rows = ReferenceModelTests.history(6, you: [0: "Please run the QC."], claude: [:])
        let story = Story(rows)
        await story.open()
        #expect(story.model.current == nil && story.model.reachedStart)
        story.grow(to: ReferenceModelTests.history(12, you: [0: "Please run the QC."], claude: [11: "Eleven plates passed."]))
        story.clock.pass(10)
        story.model.refresh()
        try await until("the reply is shown") { story.model.current?.text == "Eleven plates passed." }
    }

    @Test func closingTheWindowEndsARefreshAndDropsWhatLands() async throws {
        let story = Story(Story.rows(30))
        await story.open()
        story.grow(to: Story.rows(40))
        story.clock.pass(10)
        story.fake.holding = true
        story.model.refresh()
        try await until("the read began") { story.tailReads == 2 }
        story.model.close()
        story.fake.holding = false
        story.fake.release()
        try await quiet()
        #expect(story.model.answers.map(\.id) == [9, 19, 29])
    }

    // MARK: Earlier, pressed while a read is under way

    @Test func earlierPressedWhileAReadIsUnderWayGoesWhenItEndsOneStepOnly() async throws {
        let story = Story(Story.rows(300))
        await story.open()
        // Back to the oldest reply read (the replies from row 250), then Earlier for an older one, held.
        for _ in 0..<4 { story.model.earlier() }
        #expect(story.model.current?.id == 259)
        story.fake.holding = true
        story.model.earlier()
        try await until("the look began") { story.fake.pageReads.count == 2 }
        // Pressed three times more while it reads: one step waits, not three.
        story.model.earlier()
        story.model.earlier()
        story.model.earlier()
        story.fake.holding = false
        story.fake.release()
        // The look shows reply 249; the step that waited goes on to 239, which that look read too.
        try await until("the waiting step") { story.model.current?.id == 239 }
        try await quiet()
        #expect(story.model.current?.id == 239)
        // A pile of steps would have gone on to read yet another page.
        #expect(story.fake.pageReads == [nil, 250])
    }

    @Test func earlierBeforeAnyReplyIsOnThePageDoesNothing() async throws {
        let story = Story(Story.rows(300))
        story.fake.holding = true
        story.model.open()
        try await until("the first read began") { story.fake.pageReads.count == 1 }
        story.model.earlier()
        story.fake.holding = false
        story.fake.release()
        await ReferenceModelTests.settle(story.model)
        try await quiet()
        // The newest reply, as opening shows it: no step was made behind the user's back.
        #expect(story.model.current?.id == 299)
        #expect(story.fake.pageReads == [nil])
    }

    @Test func laterDropsAWaitingEarlier() async throws {
        let story = Story(Story.rows(300))
        await story.open()
        for _ in 0..<4 { story.model.earlier() }
        #expect(story.model.current?.id == 259)
        story.fake.holding = true
        story.model.earlier()
        try await until("the look began") { story.fake.pageReads.count == 2 }
        story.model.earlier()
        story.model.later()
        story.fake.holding = false
        story.fake.release()
        try await quiet()
        // The look finished, and the reader is where Later put them; the waiting step was withdrawn.
        #expect(story.model.current?.id == 269)
        #expect(story.fake.pageReads == [nil, 250])
    }
}

// MARK: Two items on one row

@MainActor
struct ReferenceSharedRowTests {
    typealias Made = ReferenceModelTests

    /// As the page projects a message of words and then a tool call: two items on one row.
    private static let rows: [HistoryItem] = [
        .turn(i: 0, role: .you, at: nil, text: "Plot it.", cut: false, files: []),
        .turn(i: 1, role: .claude, at: nil, text: "Let me look first.", cut: false, files: []),
        .steps(i: 1, line: "Ran a command", failed: false, files: [Made.figure(1)]),
        .turn(i: 3, role: .claude, at: nil, text: "Done.", cut: false, files: []),
    ]

    @Test func aRowOfWordsAndAToolCallKeepsBothItems() async throws {
        let (_, model) = Made.make(Self.rows)
        model.open()
        await Made.settle(model)
        // The words before the call were lost: the second item on the row replaced the first.
        #expect(model.current?.text == "Let me look first.\n\nDone.")
        #expect(model.current?.figures == [Made.figure(1)])
    }

    @Test func twoMessagesToTheUserInOneRowAreEachReadWhole() async throws {
        let whole = String(repeating: "Plate 7 has an edge effect in column 12. ", count: 120).trimmingCharacters(in: .whitespaces)
        let rows: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Run the QC.", cut: false, files: []),
            .toYou(i: 1, text: "First, short.", files: [], cut: false),
            .toYou(i: 1, text: String(whole.prefix(1999)) + "\u{2026}", files: [], cut: true),
            .turn(i: 3, role: .claude, at: nil, text: "Done.", cut: false, files: []),
        ]
        let (fake, model) = Made.make(rows)
        fake.wholeNotes[1] = ["First, short.", whole]
        model.open()
        await Made.settle(model)
        for _ in 0..<400 where fake.turnReads.isEmpty || model.readingRest { try await Task.sleep(for: .milliseconds(5)) }
        // Through the model, not just the rules: the second message is the one read whole, the first is itself.
        #expect(model.current?.parts.map(\.text) == ["First, short.", whole, "Done."])
        #expect(model.current?.cutRows.isEmpty == true)
        #expect(fake.turnReads == [1])
    }

    @Test func aRowReadAgainReplacesItsItemsAndDoesntDoubleThem() async throws {
        let (fake, model) = Made.make(Self.rows)
        let clock = MadeClock()
        model.clock = { clock.now }
        model.open()
        await Made.settle(model)
        fake.rows = Self.rows + [.turn(i: 4, role: .you, at: nil, text: "And a table?", cut: false, files: []),
                                 .turn(i: 5, role: .claude, at: nil, text: "Here.", cut: false, files: [])]
        fake.total = 6
        clock.pass(10)
        model.refresh()
        for _ in 0..<400 where model.answers.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.answers.count == 2)
        #expect(model.answers.first?.text == "Let me look first.\n\nDone.")
        #expect(model.answers.last?.text == "Here.")
    }
}

// MARK: A long message to the user

@MainActor
struct ReferenceLongMessageTests {
    private static let whole = String(repeating: "Plate 7 has an edge effect in column 12. ", count: 120)
    private static var cutText: String { String(whole.prefix(1999)) + "\u{2026}" }

    private static func rows(cut: Bool = true) -> [HistoryItem] {
        [.turn(i: 0, role: .you, at: nil, text: "Run the QC.", cut: false, files: []),
         .steps(i: 1, line: "Ran 2 commands", failed: false, files: []),
         .toYou(i: 3, text: cut ? cutText : "Halfway there.", files: [], cut: cut),
         .turn(i: 5, role: .claude, at: Date(timeIntervalSince1970: 1_791_990_000), text: "Done.", cut: false, files: [])]
    }

    @Test func aMessageToTheUserThePageCutIsMarkedAndItsRestIsRead() async throws {
        let (fake, model) = ReferenceModelTests.make(Self.rows())
        fake.wholeNotes[3] = [Self.whole.trimmingCharacters(in: .whitespaces)]
        model.open()
        await ReferenceModelTests.settle(model)
        try await until("the rest is read") { fake.turnReads == [3] && !model.readingRest }
        #expect(fake.turnReads == [3])
        let reply = try #require(model.current)
        #expect(reply.cutRows.isEmpty)
        #expect(reply.text.hasPrefix("Plate 7 has an edge effect"))
        #expect(reply.text.count > 4_000)
        #expect(reply.text.hasSuffix("Done."))
        #expect(!model.restMissing)
    }

    @Test func aMessageWhoseRestCouldntBeReadStaysCutAndSaysSo() async throws {
        let (fake, model) = ReferenceModelTests.make(Self.rows())
        fake.turnsThrow = true
        model.open()
        await ReferenceModelTests.settle(model)
        try await until("the read failed") { model.restMissing }
        let reply = try #require(model.current)
        #expect(reply.cutRows == [3])
        #expect(reply.parts.first?.text.hasSuffix("\u{2026}") == true)
        #expect(model.restMissing)
    }

    @Test func aNoteTheReadHasNoWordOfStaysCutAndSaysSo() async throws {
        let (fake, model) = ReferenceModelTests.make(Self.rows())
        // The row came back, with no message in it for this one.
        fake.wholeTexts[3] = "Some other words."
        model.open()
        await ReferenceModelTests.settle(model)
        try await until("the read ended") { model.restMissing }
        #expect(model.current?.cutRows == [3])
    }

    @Test func eachMessageOfARowIsReplacedByItsOwnWholeText() {
        let long = String(repeating: "x", count: 5_000)
        let rows: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Go.", cut: false, files: []),
            .toYou(i: 1, text: "First, short.", files: [], cut: false),
            .toYou(i: 1, text: String(long.prefix(1999)) + "\u{2026}", files: [], cut: true),
            .toYou(i: 2, text: "Another row.", files: [], cut: false),
        ]
        // Not read yet: the second of row 1 is cut, the rest are what they are.
        let cut = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:])
        #expect(cut.first?.parts.map(\.cut) == [false, true, false])
        #expect(cut.first?.cutRows == [1])
        // Read: the nth message of a row takes the nth of the read's, and no other.
        let read = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:], notes: [1: ["First, short.", long]])
        #expect(read.first?.parts.map(\.text) == ["First, short.", long, "Another row."])
        #expect(read.first?.cutRows.isEmpty == true)
        // A read with fewer messages than the row has leaves the missing one cut.
        let short = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:], notes: [1: ["First, short."]])
        #expect(short.first?.cutRows == [1])
        // A reply that has the user's turn first keeps its start.
        #expect(cut.first?.start == 0)
    }

    @Test func aMessageUnderTheLimitIsNeverCut() {
        let rows: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Go.", cut: false, files: []),
            .toYou(i: 1, text: "Short.", files: [], cut: false),
        ]
        let answers = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:])
        #expect(answers.first?.cutRows.isEmpty == true)
    }
}

// MARK: The words kept with a figure

@MainActor
struct ReferenceKeptWordsTests {
    typealias Made = ReferenceModelTests
    private static let chart = Made.figure(1)
    private static let whole = String(repeating: "Plate 7 has an edge effect in column 12. ", count: 120)
        .trimmingCharacters(in: .whitespaces)

    /// A reply of one long, cut answer with a figure on the step before it.
    private static func setUp(holdingTurns: Bool = false, throwing: Bool = false) async throws -> (FakeHistory, ReferenceModel, MadeShelf) {
        let rows = Made.history(24, you: [0: "Plot it."], claude: [20: String(whole.prefix(1999)) + "\u{2026}"], cut: [20],
                                figures: [10: [chart]])
        let (fake, model, shelf) = ShelfReferenceTests.make(rows)
        fake.wholeTexts[20] = whole.trimmingCharacters(in: .whitespaces)
        fake.holdingTurns = holdingTurns
        fake.turnsThrow = throwing
        model.open()
        await ShelfReferenceTests.land(model)
        return (fake, model, shelf)
    }

    @Test func addToShelfWaitsForTheRestOfTheReplyAndKeepsItWhole() async throws {
        let (fake, model, shelf) = try await Self.setUp(holdingTurns: true)
        model.restWait = .seconds(5)
        // Pressed before the whole-turn read has landed.
        let adding = Task { await model.addToShelf(Self.chart) }
        try await until("the add is waiting") { model.shelfMark(Self.chart) == .adding }
        try await quiet()
        #expect(shelf.added.isEmpty)
        fake.holdingTurns = false
        fake.release()
        _ = await adding.value
        let source = try #require(shelf.added.first)
        #expect(source.answer?.text == Self.whole)
        #expect(source.answer?.cut == false)
    }

    @Test func aReplyStillCutWhenTheWaitEndsSaysSoAndIsAddedAllTheSame() async throws {
        let (fake, model, shelf) = try await Self.setUp(holdingTurns: true)
        model.restWait = .milliseconds(100)
        _ = await model.addToShelf(Self.chart)
        let source = try #require(shelf.added.first)
        #expect(source.answer?.cut == true)
        #expect(source.answer?.text.hasSuffix("\u{2026}") == true)
        fake.holdingTurns = false
        fake.release()
    }

    @Test func aReadThatFailedSaysSoTooWithoutWaiting() async throws {
        let (_, model, shelf) = try await Self.setUp(throwing: true)
        try await until("the read failed") { model.restMissing }
        model.restWait = .seconds(5)
        let started = ContinuousClock.now
        _ = await model.addToShelf(Self.chart)
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(shelf.added.first?.answer?.cut == true)
    }

    @Test func keepIsPinnedToTheWholeWordsWhenTheyCameAndCutWhenTheyDidnt() async throws {
        let (fake, model, _) = try await Self.setUp(holdingTurns: true)
        model.restWait = .milliseconds(100)
        await model.restRead(for: Self.chart)
        #expect(model.keepSubject(Self.chart).pinned?.cut == true)
        fake.holdingTurns = false
        fake.release()
        try await until("the rest is read") { !model.readingRest }
        await model.restRead(for: Self.chart)
        let pinned = try #require(model.keepSubject(Self.chart).pinned)
        #expect(pinned.cut == false && pinned.text == Self.whole)
    }

    @Test func aReplyWithNothingCutIsAddedAtOnce() async throws {
        let (_, model, shelf) = ShelfReferenceTests.make(ShelfReferenceTests.conversation(rows: 24, figures: [14: [Self.chart]]))
        model.open()
        await ShelfReferenceTests.land(model)
        model.restWait = .seconds(5)
        let started = ContinuousClock.now
        _ = await model.addToShelf(Self.chart)
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(shelf.added.first?.answer?.cut == false)
    }
}

// MARK: A figure whose picture the store let go

@MainActor
struct ReferenceThumbnailAsksTests {
    typealias Made = ReferenceModelTests

    private func make() -> (FakeHistory, ReferenceModel, HistoryFile) {
        let chart = Made.figure(1)
        let (fake, model) = Made.make(Made.history(12, you: [0: "Plot it."], claude: [10: "Here."], figures: [5: [chart]]))
        fake.thumbnails[chart.v] = Data("not a picture".utf8)
        return (fake, model, chart)
    }

    @Test func aPictureTheStoreLetGoIsAskedForAgainAFewTimesAndThenTheCardSaysItCantBeShown() async throws {
        let (fake, model, chart) = make()
        let picture = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                                    bitsPerPixel: 0)?.cgImage)
        for round in 1...(ReferenceModel.thumbnailReAsks + 1) {
            model.wantThumbnail(chart)
            try await until("the read \(round)") { fake.thumbnailReads.count == round }
            // The picture comes, then goes (a reply with more pictures than the store holds).
            model.thumbnails.insert(picture, for: chart.v)
            model.thumbnails.removeAll()
            try await quiet()
        }
        #expect(fake.thumbnailReads.count == ReferenceModel.thumbnailReAsks + 1)
        // Drawn missing once more: not asked for, and the card says so rather than spinning.
        model.wantThumbnail(chart)
        try await quiet()
        #expect(fake.thumbnailReads.count == ReferenceModel.thumbnailReAsks + 1)
        #expect(model.thumbnailFailed(chart))
    }

    @Test func aCardDrawnWithoutItsPictureAsksAgainWhenTheStoreLetsItGo() async throws {
        let store = ShelfThumbnails()
        let chart = Made.figure(1)
        var asks = 0
        let host = NSHostingView(rootView: ReferenceFigureView(store: store, file: chart, failed: false, wantsPicture: { asks += 1 }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        func draw() async throws {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        try await draw()
        // Drawn with no picture: it asks.
        #expect(asks == 1)
        let picture = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                                    bitsPerPixel: 0)?.cgImage)
        store.insert(picture, for: chart.v)
        try await draw()
        #expect(asks == 1)
        // The store lets it go (a reply with more pictures than it holds): drawn missing again, it asks again.
        store.removeAll()
        try await draw()
        #expect(asks == 2)
        window.contentView = nil
    }

    @Test func aPictureThatIsOnItsWayOrKeptIsNotAskedForAgain() async throws {
        let (fake, model, chart) = make()
        model.wantThumbnail(chart)
        model.wantThumbnail(chart)
        model.wantThumbnail(chart)
        try await quiet()
        #expect(fake.thumbnailReads.count == 1)
    }
}
