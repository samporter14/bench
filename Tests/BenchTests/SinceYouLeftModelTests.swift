// SinceYouLeftModelTests.swift — Since You Left as a whole, on a fresh lab and
// a fresh model with every outside thing stood in for: the clock, the idle
// time, the screen, the window, the settings, the page's reads. The return and
// what it holds, when the sheet opens by itself and when the card carries it,
// the card taking the batched finish card's place, and the rule for reads: none
// before the sheet or the list shows them, none while away, six sessions at
// most, one read each. Nothing here touches a real session or the real page.
import CoreGraphics
import Foundation
import Testing
@testable import Bench

/// Holds whoever waits on it until it is opened, and stays open.
@MainActor
private final class Latch {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var holding: Int { waiting.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        let held = waiting
        waiting = []
        held.forEach { $0.resume() }
    }
}

/// What the files' reader was asked for, shared with the closure that answers it.
@MainActor
private final class FileReadLog {
    var reads: [ArtifactRead] = []
}

/// One return's whole scene, with the clock and the switches in hand.
@MainActor
private final class Rig {
    /// A made-up time: three hours before the real now, so the events a lab
    /// makes (stamped by the real clock) come after the leaving. And never later
    /// than 19:00 UTC: a stretch that crossed midnight in the rig's UTC calendar
    /// would be a new day, where a shorter absence counts, so a test of a short
    /// one failed in the hours before midnight UTC.
    var now: Date = {
        let start = Date().addingTimeInterval(-3 * 3600)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return min(start, utc.date(bySettingHour: 19, minute: 0, second: 0, of: start) ?? start)
    }()
    var idle: TimeInterval = 3
    var screenOff = false
    var cardsOn = true, sheetOn = true, windowKey = false, quiet = false, holds = false, readable = true, mayRead = true
    var usage: PlanLimit?
    var opened = 0, closed = 0
    var answered: [String] = [], reasoned: [String] = []
    /// While set, an answer's read waits on it (a page that is slow to answer).
    var holdAnswers: Latch?
    var knownReasons: [String: String] = [:]
    let lab = LabModel()
    /// Every read the files' reader (the panel's own, which the rows use) was asked for: the lists of files and the
    /// thumbnails, answered with a picture and a table each, so what a row draws is real.
    var fileReads: [ArtifactRead] { fileReadLog.reads }
    private let fileReadLog: FileReadLog
    let finished: FinishedResults
    let actions: CardActions

    /// The files every session in the rig made: a picture and a table.
    static let files = [
        ArtifactEntry(version: "v-picture", artifact: nil, name: "z_prime.png", mime: "image/png", size: 2_048, at: nil),
        ArtifactEntry(version: "v-table", artifact: nil, name: "plates_cleaned.csv", mime: "text/csv", size: 512, at: nil),
    ]

    init() {
        let lab = lab
        let picture = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let log = FileReadLog()
        fileReadLog = log
        finished = FinishedResults(dependencies: .init(read: { read in
            log.reads.append(read)
            switch read {
            case .list: return .list(Rig.files)
            case .thumb: return .bytes(Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBP".utf8))
            default: return .unreadable
            }
        }, isReady: { true }), thumbnails: ShelfThumbnails(decoder: { _ in .success(picture) }))
        actions = CardActions(model: lab, plans: PlanApprover.shared,
                              questions: QuestionReplier(model: lab, dependencies: .live()))
        // Re-made with this rig's own closures (the struct's are values).
        let holder = Holder(self)
        var deps = SinceYouLeftDependencies()
        deps.now = { holder.rig.now }
        deps.idle = { holder.rig.idle }
        deps.screenOff = { holder.rig.screenOff }
        deps.calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
        deps.usage = { holder.rig.usage }
        deps.refreshUsage = {}
        deps.cardsOn = { holder.rig.cardsOn }
        deps.sheetOn = { holder.rig.sheetOn }
        deps.mainWindowIsKey = { holder.rig.windowKey }
        deps.isQuiet = { holder.rig.quiet }
        deps.holdsFinishes = { holder.rig.holds }
        deps.showSheet = { holder.rig.opened += 1 }
        deps.closeSheet = { holder.rig.closed += 1 }
        deps.canRead = { holder.rig.readable }
        deps.readsContent = { holder.rig.mayRead }
        // The shared typing gate is other tests' too: a key one of them noted would make a read here wait.
        deps.loadFiles = { finished, session in await finished.load(session) }
        deps.fullReason = { holder.rig.knownReasons[$0].map { "Full: \($0)" } }
        deps.readAnswer = { id in
            holder.rig.answered.append(id)
            if let latch = holder.rig.holdAnswers { await latch.wait() }
            return "Answer for \(id)."
        }
        deps.readReason = { id in holder.rig.reasoned.append(id); return "Reason for \(id)." }
        deps.knownReason = { holder.rig.knownReasons[$0] }
        rebuilt = SinceYouLeftModel(lab: lab, finished: finished, dependencies: deps)
        rebuilt.attach()
        lab.holdsFinishes = { holder.rig.holds }
        lab.isQuiet = { holder.rig.quiet }
    }

    /// The model built with this rig's closures.
    private(set) var rebuilt: SinceYouLeftModel!
    /// Strong: a read the model started can still be under way when the test ends, and must find the rig there.
    private final class Holder { let rig: Rig; init(_ rig: Rig) { self.rig = rig } }

    var m: SinceYouLeftModel { rebuilt }

    func advance(minutes: Double, idle: TimeInterval) {
        now = now.addingTimeInterval(minutes * 60)
        self.idle = idle
        m.observe()
    }

    /// Present, then gone for `minutes`, as the observations would see it.
    func leave() {
        idle = 2
        m.observe()
        advance(minutes: 3, idle: 180)
    }

    func session(_ id: String, _ state: SessionState, reason: WaitingReason? = nil, title: String = "Session") -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Example project", title: "\(title) \(id)", state: state,
                      updatedAt: Date(), startedAt: Date().addingTimeInterval(-600), waitingReason: reason)
    }

    /// The events the real lab would have remembered, at the real time.
    func happen(_ kind: LabEvent.Kind, _ session: SessionStatus, at: Date? = nil) {
        m.remember(LabEvent(kind, session: session, at: at ?? now))
    }

    /// Time passing with someone at the Mac, looked at every five minutes as the reads do.
    func elapse(minutes: Double) {
        var left = minutes
        while left > 0 {
            advance(minutes: min(5, left), idle: 2)
            left -= 5
        }
    }
}

@MainActor
struct SinceYouLeftModelTests {
    @Test func aReturnAfterAnHourHoldsWhatHappenedWhileAway() {
        let rig = Rig()
        rig.leave()
        let finished = rig.session("a", .finished), stopped = rig.session("b", .error), asking = rig.session("c", .needsInput, reason: .question)
        rig.lab.showDemo(working: [], cards: [.needsInput(asking)])
        rig.happen(.finished, finished); rig.happen(.failed, stopped); rig.happen(.needsInput(.question), asking)
        // Some time passes with nothing touched, and then a key.
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.pending != nil)
        let summary = rig.m.display
        #expect(summary?.finished.map(\.id) == ["a"])
        #expect(summary?.stopped.map(\.id) == ["b"])
        #expect(summary?.needs.map(\.id) == ["c"])
        #expect(summary?.headline == "1 finished, 1 stopped, 1 needs you")
        #expect((rig.m.awayDuration ?? 0) > 60 * 60)
    }

    @Test func lessThanThirtyMinutesAwayShowsNothing() {
        let rig = Rig()
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 15, idle: 2)
        #expect(rig.m.pending == nil)
        #expect(rig.lab.cards.isEmpty)
        #expect(rig.opened == 0)
    }

    @Test func aStretchWhereNothingChangedShowsNothing() {
        let rig = Rig()
        rig.leave()
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.pending == nil)
        #expect(rig.opened == 0)
        #expect(rig.lab.cards.isEmpty)
    }

    @Test func whatHappenedBeforeTheyLeftIsNotInIt() {
        let rig = Rig()
        rig.happen(.finished, rig.session("old", .finished), at: rig.now.addingTimeInterval(-600))
        rig.leave()
        rig.happen(.finished, rig.session("new", .finished))
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.display?.finished.map(\.id) == ["new"])
    }

    // MARK: Where it shows

    @Test func theSheetOpensByItselfWhenItIsOnAndTheMainWindowIsKey() {
        let rig = Rig()
        rig.windowKey = true
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.opened == 1)
        // The sheet carries it: no card as well.
        #expect(rig.lab.cards.isEmpty)
    }

    @Test func otherwiseTheCardCarriesIt() {
        for (label, setup) in [
            ("the setting is off", { (r: Rig) in r.windowKey = true; r.sheetOn = false }),
            ("the main window is not key", { (r: Rig) in r.windowKey = false }),
        ] as [(String, (Rig) -> Void)] {
            let rig = Rig()
            setup(rig)
            rig.leave()
            rig.happen(.finished, rig.session("a", .finished)); rig.happen(.finished, rig.session("b", .finished))
            rig.happen(.failed, rig.session("c", .error))
            rig.advance(minutes: 70, idle: 2)
            #expect(rig.opened == 0, Comment(rawValue: label))
            let card = rig.lab.cards.first
            guard case .notice(let notice)? = card else { Issue.record("no card when \(label)"); continue }
            #expect(notice.id.hasPrefix(SinceYouLeftModel.cardIDPrefix))
            #expect(notice.caption == "Since you left")
            #expect(notice.title == "2 finished, 1 stopped")
            #expect(notice.detail.hasSuffix("minutes") || notice.detail.contains("hour"))
            #expect(notice.action == .sinceYouLeft)
            // The summary stays for the list and the sheet.
            #expect(rig.m.display?.count == 3)
        }
    }

    @Test func aCardsOffSettingMeansNoCard() {
        let rig = Rig()
        rig.cardsOn = false
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.lab.cards.isEmpty)
        #expect(rig.m.display != nil)
    }

    @Test func whatOnlyNeedsYouHasNoCardOfItsOwn() {
        let rig = Rig()
        rig.leave()
        let asking = rig.session("c", .needsInput, reason: .question)
        rig.lab.showDemo(working: [], cards: [.needsInput(asking)])
        rig.happen(.needsInput(.question), asking)
        rig.advance(minutes: 70, idle: 2)
        // Its own card is there; the summary adds none of its own.
        #expect(rig.lab.cards.count == 1)
        #expect(rig.lab.cards.first?.id == "needs-c")
        #expect(rig.m.display?.needs.count == 1)
    }

    @Test func aFocusSessionOrAPresentationHoldsTheSheetAndTheCard() {
        let rig = Rig()
        rig.windowKey = true
        rig.holds = true
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.opened == 0)
        #expect(rig.lab.cards.isEmpty)
        #expect(rig.m.cardHeld)
        // The hold lifts with nothing batched: the card comes by itself, with the next look.
        rig.holds = false
        rig.windowKey = false
        rig.advance(minutes: 1, idle: 2)
        #expect(!rig.m.cardHeld)
        #expect(rig.lab.cards.count == 1)
    }

    @Test func theCardTakesTheBatchedFinishedCardsPlaceWhenTheHoldLifts() {
        let rig = Rig()
        rig.holds = true
        rig.leave()
        // Two sessions finish while a focus session holds finishes: the lab batches them.
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .finished), Fixture.session("b", .finished)))
        #expect(rig.lab.heldFinishes.count == 2)
        #expect(rig.lab.cards.isEmpty)
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.cardHeld)
        rig.holds = false
        rig.lab.focusEnded()
        // One card, and it is Since You Left's, not "While you focused".
        #expect(rig.lab.cards.count == 1)
        guard case .notice(let notice)? = rig.lab.cards.first else { Issue.record("no card"); return }
        #expect(notice.id.hasPrefix(SinceYouLeftModel.cardIDPrefix))
        #expect(notice.heldFor == nil)
        #expect(notice.title == "2 finished")
        #expect(rig.lab.heldFinishes.isEmpty)
    }

    @Test func withoutAReturnTheBatchedCardComesAsBefore() {
        let rig = Rig()
        rig.holds = true
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .finished), Fixture.session("b", .finished)))
        rig.holds = false
        rig.lab.focusEnded()
        guard case .notice(let notice)? = rig.lab.cards.first else { Issue.record("no card"); return }
        #expect(notice.heldFor == .focus)
        #expect(notice.id.hasPrefix("focus-held-"))
    }

    @Test func aPresentationHoldsItLikeAFocusSession() {
        let rig = Rig()
        rig.quiet = true
        rig.windowKey = true
        rig.leave()
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.opened == 0)
        rig.quiet = false
        rig.lab.quietChanged()
        guard case .notice(let notice)? = rig.lab.cards.first else { Issue.record("no card"); return }
        #expect(notice.id.hasPrefix(SinceYouLeftModel.cardIDPrefix))
        #expect(rig.lab.cards.count == 1)
    }

    // MARK: Done, and nothing old

    @Test func doneClearsTheSummaryTheCardAndWhatWasRead() async {
        let rig = Rig()
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.m.details["a"]?.answer != nil)
        #expect(rig.lab.cards.count == 1)
        rig.m.done()
        #expect(rig.m.pending == nil)
        #expect(rig.m.display == nil)
        #expect(rig.m.details.isEmpty)
        #expect(rig.lab.cards.isEmpty)
        #expect(rig.closed == 1)
    }

    @Test func aReturnNotAnsweredIsReplacedByTheNext() {
        let rig = Rig()
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 70, idle: 2)
        let first = rig.m.pending
        // Gone again, a session finishes, and back.
        rig.advance(minutes: 5, idle: 300)
        rig.happen(.finished, rig.session("b", .finished))
        rig.advance(minutes: 60, idle: 2)
        #expect(rig.m.pending != first)
        #expect(rig.m.display?.finished.map(\.id) == ["b"])
    }

    @Test func aSummaryNobodyAnsweredIsDroppedAfterTwelveHours() {
        let rig = Rig()
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.pending != nil)
        rig.elapse(minutes: 11 * 60)
        #expect(rig.m.pending != nil)
        rig.elapse(minutes: 61)
        #expect(rig.m.pending == nil)
    }

    // MARK: What the stretch used, and the phone

    @Test func theLimitWhenTheyLeftIsTheBaselineForWhatTheStretchUsed() {
        let rig = Rig()
        let resets = Date().addingTimeInterval(3 * 3600)
        rig.usage = PlanLimit(kind: .session, usedPercent: 10, resetsAt: resets)
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.usage = PlanLimit(kind: .session, usedPercent: 48, resetsAt: resets)
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.usage()?.used == 38)
        #expect(rig.m.usage()?.left == 52)
    }

    @Test func noBaselineMeansNoUsageLine() {
        let rig = Rig()
        rig.usage = nil
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        rig.usage = PlanLimit(kind: .session, usedPercent: 48, resetsAt: nil)
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.usage() == nil)
    }

    @Test func thePhoneSeesWhatHasHappenedWhileTheStretchLastsAndNothingBefore() {
        let rig = Rig()
        rig.leave()
        rig.happen(.finished, rig.session("a", .finished))
        // 10 minutes in: not yet worth telling.
        rig.advance(minutes: 10, idle: 13 * 60)
        #expect(rig.m.forPhone() == nil)
        rig.advance(minutes: 25, idle: 38 * 60)
        let summary = rig.m.forPhone()
        #expect(summary?.finished.map(\.id) == ["a"])
        #expect(summary?.back == nil)
        #expect(summary?.away(now: rig.now) ?? 0 > 30 * 60)
        // Back: the same summary, now with a return, until Done.
        rig.advance(minutes: 5, idle: 2)
        #expect(rig.m.forPhone()?.back != nil)
        rig.m.done()
        #expect(rig.m.forPhone() == nil)
    }

    // MARK: The reads

    private func manyFinished(_ rig: Rig, count: Int, stopped: Int = 0) {
        for n in 1...count { rig.happen(.finished, rig.session("f\(n)", .finished)) }
        for n in 0..<stopped { rig.happen(.failed, rig.session("s\(n)", .error)) }
    }

    @Test func nothingIsReadUntilTheSheetOrTheListShowsIt() {
        let rig = Rig()
        rig.leave()
        manyFinished(rig, count: 3)
        rig.advance(minutes: 70, idle: 2)
        #expect(rig.m.pending != nil)
        #expect(rig.answered.isEmpty && rig.reasoned.isEmpty)
        #expect(rig.m.readsStarted == 0)
    }

    @Test func atMostSixSessionsAreReadAndEachOnce() async {
        let rig = Rig()
        rig.leave()
        manyFinished(rig, count: 8, stopped: 1)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.count + rig.reasoned.count == SinceYouLeftSummary.rowLimit)
        // What stopped first, then what finished.
        #expect(rig.reasoned.count == 1)
        #expect(rig.answered.count == 5)
        // Showing it again reads nothing more.
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.count + rig.reasoned.count == 6)
        #expect(Set(rig.answered).count == rig.answered.count)
    }

    /// A loader that was cancelled (Done) and has not yet noticed must not clear the handle of the one that
    /// replaced it: that left the new loader unguarded, so a second look started a second loader beside it.
    @Test func aLoaderThatWasCancelledDoesNotClearTheHandleOfTheOneThatReplacedIt() async {
        let rig = Rig()
        let first = Latch(), second = Latch()
        rig.holdAnswers = first
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        for _ in 0..<2_000 where first.holding == 0 { await Task.yield() }
        #expect(first.holding == 1 && rig.answered.count == 1, "the first loader is in its first read")
        // Done: the first loader is cancelled, but is still waiting in its read.
        rig.m.done()
        // A new return, and the sheet shows its rows: a second loader, held in its first read too.
        rig.holdAnswers = second
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.answered = []
        rig.m.loadDetails(cardActions: rig.actions)
        for _ in 0..<2_000 where second.holding == 0 { await Task.yield() }
        #expect(second.holding == 1 && rig.answered.count == 1, "the second loader is in its first read")
        // The first one's read comes back; it sees it was cancelled and ends.
        first.open()
        for _ in 0..<200 { await Task.yield() }
        // The sheet looks again (it does, as it appears and as rows change): nothing starts beside the second loader.
        rig.m.loadDetails(cardActions: rig.actions)
        for _ in 0..<200 { await Task.yield() }
        #expect(rig.answered.count == 1, "one loader at a time: the second is still the one reading")
        second.open()
        await rig.m.settled()
        #expect(rig.answered.count == 2 && Set(rig.answered).count == 2, "and it reads each row once")
    }

    @Test func nothingIsReadWhileAway() async {
        let rig = Rig()
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        // Gone again before the sheet could show the rows.
        rig.advance(minutes: 5, idle: 300)
        #expect(rig.m.rule.isAway)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.isEmpty)
    }

    @Test func nothingIsReadWhenThePageIsNotUp() async {
        let rig = Rig()
        rig.readable = false
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.isEmpty)
        // Up again: the next look reads.
        rig.readable = true
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.count == 2)
    }

    @Test func aReasonTheFailureCardAlreadyReadIsNotReadAgain() async {
        let rig = Rig()
        rig.knownReasons["s0"] = "Already known."
        rig.leave()
        manyFinished(rig, count: 1, stopped: 1)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.reasoned.isEmpty)
        #expect(rig.m.details["s0"]?.reason == "Already known.")
        #expect(rig.answered == ["f1"])
    }

    @Test func withTheContentSettingOffARowIsItsTitleAndNothingMore() async {
        let rig = Rig()
        rig.mayRead = false
        rig.leave()
        manyFinished(rig, count: 2, stopped: 1)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.isEmpty && rig.reasoned.isEmpty)
        #expect(rig.m.details.isEmpty)
        #expect(rig.m.display?.count == 3)
    }

    @Test func thePhoneGetsAReasonTheCardHasReadAndCopyGetsAllOfIt() {
        let rig = Rig()
        rig.knownReasons["s0"] = "Out of memory."
        rig.leave()
        manyFinished(rig, count: 1, stopped: 1)
        rig.advance(minutes: 70, idle: 2)
        let summary = try? #require(rig.m.display)
        #expect(summary.map { rig.m.detailsForPhone($0)["s0"]?.reason } == "Out of memory.")
        #expect(rig.m.fullReason(for: "s0") == "Full: Out of memory.")
        // Nothing known: the line the sheet read, or nothing.
        #expect(rig.m.fullReason(for: "f1") == nil)
    }

    @Test func turningTheContentSettingOffAfterTheReadsHidesWhatWasRead() async {
        let rig = Rig()
        rig.knownReasons["s0"] = "Out of memory."
        rig.leave()
        manyFinished(rig, count: 1, stopped: 1)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.m.detail(for: "s0")?.reason == "Out of memory.")
        rig.mayRead = false
        let summary = try? #require(rig.m.display)
        #expect(rig.m.detail(for: "s0") == nil && rig.m.detail(for: "f1") == nil)
        #expect(summary.map { rig.m.detailsForPhone($0).isEmpty } == true)
        #expect(rig.m.fullReason(for: "s0") == nil)
    }

    // MARK: Files, with the content setting

    private func fileVersions(_ rig: Rig) -> Set<String> {
        Set(rig.fileReads.compactMap { if case .thumb(let version, _) = $0 { version } else { nil } })
    }

    private func isLoaded(_ listing: FinishedResults.Listing) -> Bool {
        if case .loaded = listing { true } else { false }
    }

    @Test func withTheContentSettingOffNoFileIsListedOrFetchedAndNoRowHasATile() async {
        let rig = Rig()
        rig.mayRead = false
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.fileReads.isEmpty, "no list of files and no picture is asked for")
        #expect(rig.m.listing(for: "f1") == .unknown && rig.m.listing(for: "f2") == .unknown)
        // The rows stay what they were before any read.
        #expect(rig.m.display?.count == 2)
    }

    @Test func withTheContentSettingOnTheRowsGetTheirFilesAndTheirPictures() async {
        let rig = Rig()
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        await rig.finished.thumbnails.settled()
        let lists = rig.fileReads.filter { if case .list = $0 { true } else { false } }
        #expect(lists.count == 2, "one list for each finished row")
        #expect(fileVersions(rig) == ["v-picture"])
        #expect(isLoaded(rig.m.listing(for: "f1")) && isLoaded(rig.m.listing(for: "f2")))
    }

    @Test func turningTheContentSettingOffAfterTheFilesLoadedTakesTheirTilesAway() async {
        let rig = Rig()
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        await rig.finished.thumbnails.settled()
        #expect(isLoaded(rig.m.listing(for: "f1")))
        #expect(SinceTile.tiles(from: Rig.files) == [.picture(version: "v-picture"), .kind("CSV")])
        rig.mayRead = false
        // What was read is still held in memory, but the sheet is not given any of it.
        #expect(isLoaded(rig.finished.listing(for: "f1")), "the cache is the Finished card's own")
        #expect(rig.m.listing(for: "f1") == .unknown && rig.m.listing(for: "f2") == .unknown)
        let reads = rig.fileReads.count
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.fileReads.count == reads, "nothing is read again while it is off")
        // Back on, they are there again, as they were.
        rig.mayRead = true
        #expect(isLoaded(rig.m.listing(for: "f1")))
    }

    @Test func turningTheContentSettingOffWhileTheRowsAreReadStopsTheReadsAtOnce() async {
        let rig = Rig()
        let latch = Latch()
        rig.holdAnswers = latch
        rig.leave()
        manyFinished(rig, count: 2)
        rig.advance(minutes: 70, idle: 2)
        rig.m.loadDetails(cardActions: rig.actions)
        for _ in 0..<2_000 where latch.holding == 0 { await Task.yield() }
        #expect(latch.holding == 1 && rig.answered.count == 1, "the first row's answer is in flight")
        rig.mayRead = false
        latch.open()
        await rig.m.settled()
        #expect(rig.answered.count == 1, "the second row is not read")
        #expect(rig.fileReads.isEmpty, "and the first one's files are not asked for after its answer")
        // Turned on again, the rows that were not finished are read.
        rig.mayRead = true
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        await rig.finished.thumbnails.settled()
        #expect(Set(rig.answered) == ["f1", "f2"])
        #expect(isLoaded(rig.m.listing(for: "f1")) && isLoaded(rig.m.listing(for: "f2")))
    }

    @Test func aRowWhoseSessionIsNoLongerThereIsNotRead() async {
        let rig = Rig()
        rig.leave()
        let a = rig.session("a", .finished)
        rig.happen(.finished, a)
        rig.advance(minutes: 70, idle: 2)
        // The session starts again: it is no longer finished.
        rig.lab.showDemo(working: [rig.session("a", .running)], cards: [])
        rig.m.loadDetails(cardActions: rig.actions)
        await rig.m.settled()
        #expect(rig.answered.isEmpty)
    }

    @Test func leavingAndReturningMakesNoReadsOfItsOwn() {
        let rig = Rig()
        rig.leave()
        manyFinished(rig, count: 3)
        rig.advance(minutes: 70, idle: 2)
        rig.advance(minutes: 1, idle: 2)
        rig.m.done()
        #expect(rig.answered.isEmpty && rig.reasoned.isEmpty)
    }

    // MARK: Wiring

    @Test func theLabTellsTheModelOfNewEventsOnlyOnceEach() {
        let rig = Rig()
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        #expect(rig.m.eventCount == 1)
    }

    @Test func everyReadOfTheSessionsIsALookAtTheMac() {
        let rig = Rig()
        rig.idle = 2
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(!rig.m.rule.isAway)
        rig.now = rig.now.addingTimeInterval(600)
        rig.idle = 600
        rig.lab.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(rig.m.rule.isAway)
        #expect(rig.m.awaySince != nil)
    }

    @Test func theSheetSettingIsOnUnlessTurnedOff() {
        #expect(SinceYouLeftSettings.sheetIsOn(stored: nil))
        #expect(SinceYouLeftSettings.sheetIsOn(stored: true))
        #expect(!SinceYouLeftSettings.sheetIsOn(stored: false))
        #expect(!SinceYouLeftSettings.sheetIsOn(stored: "NO"))
        #expect(SinceYouLeftSettings.sheetIsOn(stored: "YES"))
        #expect(SinceYouLeftSettings.sheetKey == "sinceYouLeftSheet")
    }
}
