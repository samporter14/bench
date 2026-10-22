// LabInsightsTests.swift — when step progress, the reviewer's counts and
// Claude's notes are read, and what is kept of them, against fakes with an
// injected clock. No page, no daemon and no UserDefaults are touched; every
// session, title and note is made up.
import Foundation
import Testing
@testable import Bench

private let a = "00000000-0000-4000-8000-00000000000a"
private let b = "00000000-0000-4000-8000-00000000000b"
private let c = "00000000-0000-4000-8000-00000000000c"
private let start = Date(timeIntervalSince1970: 1_791_833_400)

private func session(_ id: String, _ state: SessionState = .running, updated: TimeInterval = 0) -> SessionStatus {
    SessionStatus(id: id, projectID: "p", projectName: "Assay development", title: "Plate reader QC", state: state,
                  updatedAt: Date(timeIntervalSince1970: 1_791_833_000 + updated), startedAt: Date(timeIntervalSince1970: 1_791_832_000))
}

private let facts = PlanProgressFacts(running: true, children: 1, reported: 2, unknown: 0)
private let stepFour = PlanProgress(step: 4, total: 6, title: "Check against published screens")

/// A page of a session's history holding only these notes (`rows` is the
/// history's length, each note at the row it names).
private func history(total: Int, notes: [(row: Int, text: String)]) -> RemoteBrowser.HistoryRead {
    let items = notes.map { HistoryItem.toYou(i: $0.row, text: $0.text, files: []) }
    return .page(HistoryPage(total: total, from: 0, items: items))
}

@MainActor
private final class Fake {
    var enabled = true
    var ready = true
    var demo = false
    var date = start

    var progress: PlanProgressRead = .progress(stepFour, facts)
    var progressFor: [String: PlanProgressRead] = [:]
    var progressError: (any Error)?
    var reviewer: ReviewerRead = .counts(ReviewerCounts(standing: 2, fixed: 1, running: 0, reviews: 1))
    /// What the history answers, by session, in turn (the last repeats).
    var pages: [String: [RemoteBrowser.HistoryRead]] = [:]

    /// When true, a wait ends at once with the clock moved on by it: time passing by itself.
    var sleepAdvances = false
    private(set) var sleeps = 0
    /// The clock at each read, by kind and session ("progress:<id>").
    private(set) var times: [String: [Date]] = [:]
    private(set) var log: [String] = []
    private(set) var known: [(id: String, total: Int?)] = []
    private(set) var concurrent = 0
    private(set) var mostAtOnce = 0
    private(set) var badNonce = false
    private var turns: [String: Int] = [:]
    let breadcrumbs = CompatBreadcrumbs(emit: { _ in })

    func asked(_ kind: String) -> [String] {
        log.filter { $0.hasPrefix(kind + ":") }.map { String($0.dropFirst(kind.count + 1)) }
    }

    private func around(_ line: String, nonce: String) async {
        if !HistoryShowing.isNonce(nonce) { badNonce = true }
        log.append(line)
        times[line, default: []].append(date)
        concurrent += 1
        mostAtOnce = max(mostAtOnce, concurrent)
        // A read takes a moment: a second one started meanwhile would overlap it.
        await Task.yield()
        await Task.yield()
        concurrent -= 1
    }

    func dependencies() -> LabInsights.Dependencies {
        LabInsights.Dependencies(
            isEnabled: { [unowned self] in self.enabled },
            isReady: { [unowned self] in self.ready },
            isDemo: { [unowned self] in self.demo },
            now: { [unowned self] in self.date },
            // The wake-up never comes by itself unless asked: a test moves the clock and says so.
            sleep: { [unowned self] duration in
                self.sleeps += 1
                if self.sleepAdvances {
                    let parts = duration.components
                    self.date = self.date.addingTimeInterval(Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
                    return
                }
                try? await Task.sleep(for: .seconds(3600))
            },
            readProgress: { [unowned self] id, nonce in
                await self.around("progress:\(id)", nonce: nonce)
                if let error = self.progressError { throw error }
                return self.progressFor[id] ?? self.progress
            },
            readReviewers: { [unowned self] id, nonce in
                await self.around("reviewers:\(id)", nonce: nonce)
                return self.reviewer
            },
            readHistory: { [unowned self] id, total, nonce in
                self.known.append((id, total))
                await self.around("notes:\(id)", nonce: nonce)
                let list = self.pages[id] ?? []
                let turn = self.turns[id, default: 0]
                self.turns[id] = turn + 1
                guard !list.isEmpty else { return .unreadable }
                return list[min(turn, list.count - 1)]
            },
            breadcrumbs: breadcrumbs)
    }

    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
private func makeInsights(_ fake: Fake) -> LabInsights {
    LabInsights(dependencies: fake.dependencies())
}

// MARK: Step progress

@MainActor
struct LabInsightsProgressTests {
    private let fake = Fake()

    @Test func aRunningSessionOnScreenIsReadAtOnce() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress") == [a])
        #expect(insights.progress == [a: stepFour])
        #expect(insights.progress[a]?.line == "Step 4 of 6 · Check against published screens")
        #expect(fake.badNonce == false)
    }

    @Test func progressIsFifteenSecondsApartAndTheTranscriptThirty() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 1 && fake.asked("notes").count == 1)

        // Calling again, as the panel does on every change, reads nothing early.
        for seconds in [1.0, 5, 8] {
            fake.advance(seconds)
            insights.showing(running: [session(a)])
            await insights.settled()
        }
        fake.advance(0.9)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 1)

        // 15 s after the first read began: progress, and not yet the transcript.
        fake.advance(0.1)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.date == start.addingTimeInterval(15))
        #expect(fake.asked("progress").count == 2 && fake.asked("notes").count == 1)

        // 29 s: nothing. 30 s: both are due, one after the other.
        fake.advance(14)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 2 && fake.asked("notes").count == 1)
        fake.advance(1)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 3 && fake.asked("notes").count == 2)
        #expect(fake.mostAtOnce == 1)
    }

    @Test func sayingWhatIsOnScreenAgainAndAgainMakesNoNewWait() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        let waits = fake.sleeps
        #expect(waits == 1)
        for _ in 0..<50 { insights.showing(running: [session(a)]) }
        await insights.settled()
        #expect(fake.sleeps == waits)
        #expect(fake.asked("progress").count == 1)
    }

    @Test func timePassingByItselfReadsAtTheIntervalsAndNoSoonerAndStopsWhenTheSessionLeaves() async {
        fake.sleepAdvances = true
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        for _ in 0..<2_000 where fake.times["progress:\(a)", default: []].count < 4 { await Task.yield() }
        insights.showing(running: [])
        await insights.settled()
        let progress = fake.times["progress:\(a)", default: []]
        let notes = fake.times["notes:\(a)", default: []]
        #expect(progress.count >= 4)
        #expect(notes.count >= 2)
        for (earlier, later) in zip(progress, progress.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= LabInsights.progressInterval - 0.001)
        }
        for (earlier, later) in zip(notes, notes.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= LabInsights.noteInterval - 0.001)
        }
        // Gone from the screen: no more wakes read anything.
        let reads = fake.log.count
        for _ in 0..<50 { await Task.yield() }
        #expect(fake.log.count == reads)
    }

    @Test func oneReadIsInFlightAtATimeWhateverTheSessions() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a), session(b), session(c)])
        insights.showing(running: [session(a), session(b), session(c)])
        await insights.settled()
        #expect(fake.mostAtOnce == 1)
        // Each of the three was read, for progress and for the transcript, and none twice.
        #expect(Set(fake.asked("progress")) == [a, b, c] && fake.asked("progress").count == 3)
        #expect(Set(fake.asked("notes")) == [a, b, c] && fake.asked("notes").count == 3)
        #expect(insights.progress.keys.sorted() == [a, b, c])
    }

    @Test func theMostOverdueSessionGoesFirst() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        fake.advance(20)
        insights.showing(running: [session(a), session(b)])
        await insights.settled()
        // B has never been read (so it is due before A's second read), then A's progress.
        #expect(fake.asked("progress") == [a, b, a])
    }

    @Test func aSessionThatLeavesTheScreenLosesItsProgressAndIsReadAgainWhenItComesBack() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a), session(b)])
        await insights.settled()
        #expect(insights.progress.keys.sorted() == [a, b])
        insights.showing(running: [session(b)])
        #expect(insights.progress.keys.sorted() == [b])
        insights.showing(running: [])
        #expect(insights.progress.isEmpty)
        // It comes back (a plan was approved, say) before 15 s are up: it waits for them.
        fake.advance(10)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress") == [a, b])
        // And once they are, it is read at once.
        fake.advance(5)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress") == [a, b, a])
        #expect(insights.progress[a] == stepFour)
    }

    @Test func onlyRunningSessionsAreFollowedAndNoMoreThanEight() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a, .needsInput), session(b, .finished), session(c, .error)])
        await insights.settled()
        #expect(fake.log.isEmpty)
        let many = (0..<12).map { session(String(format: "00000000-0000-4000-8000-%012x", $0)) }
        insights.showing(running: many + many)
        await insights.settled()
        #expect(fake.asked("progress").count == LabInsights.maxFollowed)
        #expect(Set(fake.asked("progress")).count == LabInsights.maxFollowed)
    }

    @Test func whatTheReadSaysDecidesWhatIsShown() async {
        let insights = makeInsights(fake)
        func next(_ read: PlanProgressRead) async {
            fake.progress = read
            fake.advance(LabInsights.noPlanInterval)
            insights.showing(running: [session(a)])
            await insights.settled()
        }
        await next(.progress(stepFour, facts))
        #expect(insights.progress[a] == stepFour)
        // Not the root's own turn: nothing to show.
        await next(.progress(PlanProgress(step: 2, total: 3), PlanProgressFacts(running: false, children: 0, reported: 1, unknown: 0)))
        #expect(insights.progress[a] == nil)
        await next(.progress(stepFour, facts))
        #expect(insights.progress[a] == stepFour)
        // Understood, and nothing to show.
        for why in [PlanProgressWhy.notApproved, .noPlan, .noStatuses, .complete] {
            await next(.progress(stepFour, facts))
            await next(.idle(why, facts))
            #expect(insights.progress[a] == nil, "\(why)")
        }
        #expect(fake.breadcrumbs.last == nil)
    }

    @Test func aReadThatIsNotAnAnswerLeavesWhatWasShown() async {
        let insights = makeInsights(fake)
        func next(_ read: PlanProgressRead) async {
            fake.progress = read
            fake.advance(LabInsights.noPlanInterval)
            insights.showing(running: [session(a)])
            await insights.settled()
        }
        await next(.progress(stepFour, facts))
        for read in [PlanProgressRead.lost, .tooBig, .cancelled] {
            await next(read)
            #expect(insights.progress[a] == stepFour, "\(read)")
        }
        fake.progressError = WebAPIError.notReady
        await next(.progress(PlanProgress(step: 6, total: 6), facts))
        #expect(insights.progress[a] == stepFour)
        fake.progressError = nil
        // A session or route that is gone clears it.
        await next(.missing)
        #expect(insights.progress[a] == nil)
        #expect(fake.breadcrumbs.last == nil)
    }

    @Test func anAnswerThatChangedLeavesABreadcrumbAndShowsNothing() async {
        let insights = makeInsights(fake)
        func next(_ read: PlanProgressRead) async {
            fake.progress = read
            fake.advance(LabInsights.noPlanInterval)
            insights.showing(running: [session(a)])
            await insights.settled()
        }
        await next(.unreadable)
        #expect(insights.progress[a] == nil)
        #expect(fake.breadcrumbs.last?.miss == .progressTreeNotUnderstood)
        await next(.idle(.planMissing, facts))
        #expect(fake.breadcrumbs.last?.miss == .progressTreeWithoutPlan)
        await next(.progress(stepFour, PlanProgressFacts(running: true, children: 0, reported: 2, unknown: 1)))
        #expect(fake.breadcrumbs.last?.miss == .progressStatusNotUnderstood)
        // The number is still the page's own, so it is shown.
        #expect(insights.progress[a] == stepFour)
        #expect(CompatMiss.progressTreeNotUnderstood.feature == .planProgress)
    }

    @Test func aSessionWithNoPlanToFollowIsAskedLessOften() async {
        let insights = makeInsights(fake)
        fake.progress = .idle(.notApproved, facts)
        insights.showing(running: [session(a)])
        await insights.settled()
        for seconds in [15.0, 30, 59.5] {
            fake.date = start.addingTimeInterval(seconds)
            insights.showing(running: [session(a)])
            await insights.settled()
        }
        #expect(fake.asked("progress").count == 1)
        fake.date = start.addingTimeInterval(60)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 2)

        // Coming back to the screen (a plan was approved) is the end of the wait, if the usual 15 s are up.
        insights.showing(running: [])
        fake.date = start.addingTimeInterval(80)
        fake.progress = .progress(stepFour, facts)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 3)
        #expect(insights.progress[a] == stepFour)
        // A session being followed is asked every 15 s again.
        fake.date = start.addingTimeInterval(95)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.asked("progress").count == 4)
    }

    @Test func theWaitForANoPlanAnswerAppliesToEveryReasonButWaitingForAFirstStatus() async {
        for (read, waits) in [(PlanProgressRead.idle(.notApproved, facts), true), (.idle(.noPlan, facts), true), (.idle(.planMissing, facts), true),
                              (.idle(.complete, facts), true), (.unreadable, true), (.missing, true), (.idle(.noStatuses, facts), false),
                              (.progress(stepFour, facts), false), (.lost, false), (.tooBig, false)] {
            let daemon = Fake()
            let insights = makeInsights(daemon)
            daemon.progress = read
            insights.showing(running: [session(a)])
            await insights.settled()
            daemon.advance(LabInsights.progressInterval)
            insights.showing(running: [session(a)])
            await insights.settled()
            #expect(daemon.asked("progress").count == (waits ? 1 : 2), "\(read)")
        }
    }

    @Test func aSessionThatLeftWhileItsReadWasUnderWayGetsNothing() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        insights.showing(running: [])
        await insights.settled()
        #expect(insights.progress.isEmpty)
    }

    @Test func nothingIsReadWithTheSettingOffAndWhatWasReadGoes() async {
        let insights = makeInsights(fake)
        fake.pages[a] = [history(total: 5, notes: [])]
        insights.showing(running: [session(a)])
        await insights.settled()
        insights.wantReviewers(for: session(b, .finished))
        await insights.settled()
        #expect(insights.progress[a] != nil && insights.reviewers[b] != nil)
        let reads = fake.log.count

        fake.enabled = false
        fake.advance(60)
        insights.showing(running: [session(a)])
        insights.wantReviewers(for: session(c, .finished))
        await insights.settled()
        #expect(fake.log.count == reads)
        #expect(insights.progress.isEmpty && insights.reviewers.isEmpty && insights.notes.isEmpty)

        // Switched back on: reads again, from the start.
        fake.enabled = true
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(fake.log.count > reads)
        #expect(insights.progress[a] == stepFour)
    }

    @Test func nothingIsReadUntilThePageIsReady() async {
        let insights = makeInsights(fake)
        fake.ready = false
        insights.showing(running: [session(a)])
        insights.wantReviewers(for: session(b, .finished))
        await insights.settled()
        #expect(fake.log.isEmpty && insights.progress.isEmpty)
        fake.ready = true
        insights.showing(running: [session(a)])
        insights.wantReviewers(for: session(b, .finished))
        await insights.settled()
        #expect(fake.asked("progress") == [a])
        #expect(fake.asked("reviewers") == [b])
    }

    @Test func aReadThatCannotBeUnderstoodIsNotReadInALoop() async {
        let insights = makeInsights(fake)
        fake.progress = .unreadable
        for _ in 0..<20 {
            insights.showing(running: [session(a)])
            await insights.settled()
        }
        #expect(fake.asked("progress").count == 1)
    }
}

// MARK: Demos

@MainActor
struct LabInsightsDemoTests {
    private let fake = Fake()

    @Test func aDemoReadsNothingAtAll() async {
        fake.demo = true
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        insights.wantReviewers(for: session(b, .finished))
        await insights.settled()
        fake.advance(600)
        insights.showing(running: [session(a), session(c)])
        await insights.settled()
        #expect(fake.log.isEmpty)
        #expect(insights.progress.isEmpty && insights.reviewers.isEmpty && insights.notes.isEmpty)
    }

    @Test func madeUpValuesStandInAndStay() async {
        fake.demo = true
        let insights = makeInsights(fake)
        let note = MidRunNote(id: "\(a)#4", sessionID: a, text: "Two made-up papers found.")
        insights.demo(progress: [a: stepFour], reviewers: [b: ReviewerCounts(standing: 2, fixed: 0, running: 0, reviews: 1)], notes: [note])
        // The panel keeps saying what is on screen; the made-up values are not read away.
        insights.showing(running: [session(a)])
        insights.showing(running: [])
        insights.wantReviewers(for: session(b, .finished))
        #expect(insights.progress == [a: stepFour])
        #expect(insights.reviewers[b]?.line == "Reviewer: 2 findings")
        #expect(insights.notes == [note])
        insights.noteSeen(note.id)
        #expect(insights.notes.isEmpty)
        #expect(fake.log.isEmpty)
    }
}

// MARK: The reviewer

@MainActor
struct LabInsightsReviewerTests {
    private let fake = Fake()

    @Test func aFinishedSessionIsReadOnceForItsFinish() async {
        let insights = makeInsights(fake)
        let finished = session(a, .finished, updated: 100)
        for _ in 0..<5 {
            insights.wantReviewers(for: finished)
            await insights.settled()
        }
        #expect(fake.asked("reviewers") == [a])
        #expect(insights.reviewers[a] == ReviewerCounts(standing: 2, fixed: 1, running: 0, reviews: 1))
        #expect(insights.reviewers[a]?.line == "Reviewer: 2 findings")
        // Time passing is no reason to read again.
        fake.advance(3600)
        insights.wantReviewers(for: finished)
        await insights.settled()
        #expect(fake.asked("reviewers").count == 1)
    }

    @Test func aSessionThatRanAgainSinceIsReadAgain() async {
        let insights = makeInsights(fake)
        insights.wantReviewers(for: session(a, .finished, updated: 100))
        await insights.settled()
        fake.reviewer = .counts(ReviewerCounts(standing: 0, fixed: 2, running: 0, reviews: 2))
        insights.wantReviewers(for: session(a, .finished, updated: 900))
        await insights.settled()
        #expect(fake.asked("reviewers") == [a, a])
        #expect(insights.reviewers[a]?.line == "Reviewer: no findings")
    }

    @Test func onlyAFinishedSessionIsAsked() async {
        let insights = makeInsights(fake)
        for state in [SessionState.running, .needsInput, .error, .unknown] {
            insights.wantReviewers(for: session(a, state))
        }
        await insights.settled()
        #expect(fake.log.isEmpty)
    }

    @Test func aReviewerReadGoesBeforeTheNextProgressRead() async {
        let insights = makeInsights(fake)
        insights.showing(running: [session(b)])
        insights.wantReviewers(for: session(a, .finished))
        await insights.settled()
        // B's progress was under way; then the finished card's read; then B's transcript.
        #expect(fake.log == ["progress:\(b)", "reviewers:\(a)", "notes:\(b)"])
    }

    @Test func aNoReviewSessionHasNoLineButIsStillKnownToHaveBeenRead() async {
        let insights = makeInsights(fake)
        fake.reviewer = .counts(ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 0))
        insights.wantReviewers(for: session(a, .finished))
        await insights.settled()
        #expect(insights.reviewers[a] != nil)
        #expect(insights.reviewers[a]?.line == nil)
    }

    @Test func whatIsNotAnAnswerShowsNothing() async {
        let insights = makeInsights(fake)
        for read in [ReviewerRead.lost, .missing, .tooBig, .cancelled] {
            fake.reviewer = read
            insights.wantReviewers(for: session(a, .finished, updated: Double.random(in: 1...1_000_000)))
            await insights.settled()
        }
        #expect(insights.reviewers.isEmpty)
        #expect(fake.breadcrumbs.last == nil)
        // An answer in a shape Capsid doesn't read leaves a breadcrumb and no line.
        fake.reviewer = .unreadable
        insights.wantReviewers(for: session(b, .finished))
        await insights.settled()
        #expect(insights.reviewers.isEmpty)
        #expect(fake.breadcrumbs.last?.miss == .reviewerAnswerNotUnderstood)
        #expect(CompatMiss.reviewerAnswerNotUnderstood.feature == .reviewer)
    }

    @Test func aReadAskedForWhileThePageWasNotUpIsNotCountedAsMade() async {
        let insights = makeInsights(fake)
        fake.ready = false
        insights.wantReviewers(for: session(a, .finished))
        fake.ready = true
        insights.wantReviewers(for: session(a, .finished))
        await insights.settled()
        #expect(fake.asked("reviewers") == [a])
    }

    @Test func manyFinishedSessionsAreRememberedWithinABound() async {
        let insights = makeInsights(fake)
        for n in 0..<(LabInsights.maxRemembered + 20) {
            insights.wantReviewers(for: session(String(format: "00000000-0000-4000-8000-%012x", n), .finished))
            await insights.settled()
        }
        #expect(insights.reviewers.count <= LabInsights.maxRemembered)
    }
}

// MARK: Claude's notes

@MainActor
struct LabInsightsNotesTests {
    private let fake = Fake()

    /// Looks at session `a` at the clock's time, and waits for the reads.
    private func look(_ insights: LabInsights, after seconds: TimeInterval = LabInsights.noteInterval) async {
        fake.advance(seconds)
        insights.showing(running: [session(a)])
        await insights.settled()
    }

    @Test func nothingThatWasThereBeforeTheFirstLookIsEverOffered() async {
        fake.pages[a] = [
            history(total: 10, notes: [(2, "An old note."), (5, "Another old one."), (8, "And a third.")]),
            .same(total: 10),
            history(total: 10, notes: [(2, "An old note."), (5, "Another old one."), (8, "And a third.")]),
            history(total: 12, notes: [(2, "An old note."), (8, "And a third."), (11, "Found two made-up papers.")]),
        ]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(insights.notes.isEmpty)
        await look(insights)
        await look(insights)
        #expect(insights.notes.isEmpty)
        await look(insights)
        #expect(insights.notes.map(\.id) == ["\(a)#11"])
        #expect(insights.notes.first?.text == "Found two made-up papers.")
        #expect(insights.notes.first?.sessionID == a)
        #expect(insights.notes.first?.at == nil)
    }

    @Test func theLengthItWasLastKnownAtGoesBackSoAnUnchangedHistoryIsOneSmallRead() async {
        fake.pages[a] = [history(total: 10, notes: []), .same(total: 10), history(total: 14, notes: [(12, "A made-up note.")]), .same(total: 14)]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        for _ in 0..<3 { await look(insights) }
        #expect(fake.known.map(\.total) == [nil, 10, 10, 14])
        #expect(insights.notes.map(\.id) == ["\(a)#12"])
    }

    @Test func theNewestNoteIsFirstAndNoneComesTwice() async {
        let page1 = history(total: 5, notes: [])
        let page2 = history(total: 9, notes: [(6, "First made-up note."), (8, "Second made-up note.")])
        let page3 = history(total: 11, notes: [(6, "First made-up note."), (8, "Second made-up note."), (10, "Third made-up note.")])
        fake.pages[a] = [page1, page2, page3, page3]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        #expect(insights.notes.map(\.id) == ["\(a)#8", "\(a)#6"])
        await look(insights)
        #expect(insights.notes.map(\.id) == ["\(a)#10", "\(a)#8", "\(a)#6"])
        await look(insights)
        #expect(insights.notes.count == 3)
    }

    @Test func aNoteSeenIsGoneAndNeverOfferedAgain() async {
        let page = history(total: 9, notes: [(6, "First made-up note."), (8, "Second made-up note.")])
        fake.pages[a] = [history(total: 5, notes: []), page, page, page]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        insights.noteSeen("\(a)#8")
        #expect(insights.notes.map(\.id) == ["\(a)#6"])
        await look(insights)
        #expect(insights.notes.map(\.id) == ["\(a)#6"])
        insights.noteSeen("\(a)#6")
        insights.noteSeen("\(a)#6")
        insights.noteSeen("never-offered")
        await look(insights)
        #expect(insights.notes.isEmpty)
    }

    @Test func aNoteIsPlainTextOfAtMostThreeHundredCharacters() async {
        let long = String(repeating: "word ", count: 200)
        fake.pages[a] = [
            history(total: 2, notes: []),
            history(total: 9, notes: [(3, long), (4, "   \n  "), (5, "Tab\there\u{7} and\u{200B} zero-width\r\n\r\n\r\n\r\nafter blank lines   "), (6, "")]),
        ]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        #expect(insights.notes.map(\.id) == ["\(a)#5", "\(a)#3"])
        let text = insights.notes.map(\.text)
        #expect(text[0] == "Tab here and zero-width\n\nafter blank lines")
        #expect(text[1].count == NoteText.limit)
        #expect(text[1].hasSuffix("…"))
    }

    @Test func notesStayWhenTheirSessionLeavesTheScreenButAreReadNoMore() async {
        fake.pages[a] = [history(total: 2, notes: []), history(total: 6, notes: [(4, "A made-up note.")]), history(total: 8, notes: [(7, "Too late.")])]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        insights.showing(running: [])
        fake.advance(100)
        insights.showing(running: [])
        await insights.settled()
        #expect(insights.notes.map(\.id) == ["\(a)#4"])
        #expect(fake.asked("notes").count == 2)
    }

    @Test func aSessionThatComesBackIsLookedAtAsIfNew() async {
        // The second look is its first this time: what it holds then is old.
        fake.pages[a] = [history(total: 2, notes: []), history(total: 8, notes: [(5, "Said while it was off the screen.")]),
                         history(total: 8, notes: [(5, "Said while it was off the screen.")])]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        insights.showing(running: [])
        fake.advance(60)
        insights.showing(running: [session(a)])
        await insights.settled()
        #expect(insights.notes.isEmpty)
        #expect(fake.known.map(\.total) == [nil, nil])
    }

    @Test func aReadThatFailsBeforeTheFirstLookDoesNotMakeTheNextOneOld() async {
        // Nothing answers at first; the first answer is the first look.
        fake.pages[a] = []
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        fake.pages[a] = [history(total: 6, notes: [(4, "Sent before Capsid looked.")])]
        await look(insights)
        #expect(insights.notes.isEmpty)
        #expect(fake.known.map(\.total) == [nil, nil])
    }

    @Test func aHistoryThatGrowsShorterStartsTheCountAgain() async {
        fake.pages[a] = [history(total: 10, notes: []), history(total: 6, notes: []), history(total: 9, notes: [(7, "Said after the roll-back.")])]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        await look(insights)
        #expect(insights.notes.map(\.id) == ["\(a)#7"])
    }

    @Test func notesFromSeveralSessionsAreNewestFirst() async {
        fake.pages[a] = [history(total: 2, notes: []), history(total: 5, notes: [(3, "From A.")])]
        fake.pages[b] = [history(total: 2, notes: []), history(total: 5, notes: [(4, "From B.")])]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a), session(b)])
        await insights.settled()
        fake.advance(LabInsights.noteInterval)
        insights.showing(running: [session(a), session(b)])
        await insights.settled()
        #expect(Set(insights.notes.map(\.id)) == ["\(a)#3", "\(b)#4"])
        #expect(insights.notes.count == 2)
    }

    @Test func aFewNotesAreKeptAndTheOnesThatFallOffAreNotOfferedAgain() async {
        let rows = (0..<(LabInsights.maxNotes + 5)).map { (row: 10 + $0, text: "Made-up note \($0).") }
        let all = history(total: 10 + rows.count, notes: rows)
        fake.pages[a] = [history(total: 10, notes: []), all, all]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        #expect(insights.notes.count == LabInsights.maxNotes)
        // The newest are kept.
        #expect(insights.notes.first?.id == "\(a)#\(10 + rows.count - 1)")
        await look(insights)
        #expect(insights.notes.count == LabInsights.maxNotes)
    }

    @Test func otherKindsOfRowsAreNoNotes() async {
        let items: [HistoryItem] = [
            .turn(i: 6, role: .claude, at: nil, text: "A reply, not a note.", cut: false, files: []),
            .steps(i: 7, line: "Ran a command", failed: false, files: []),
            .helper(i: 8), .plan(i: 9, steps: 3), .ask(i: 10, q: "Which?", a: nil),
        ]
        fake.pages[a] = [history(total: 5, notes: []), .page(HistoryPage(total: 12, from: 6, items: items))]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        await look(insights)
        #expect(insights.notes.isEmpty)
    }

    @Test func aPageTooBigOrNotUnderstoodIsLetGo() async {
        fake.pages[a] = [.tooBig, .unreadable, history(total: 4, notes: [(2, "Old.")]), history(total: 6, notes: [(5, "New.")])]
        let insights = makeInsights(fake)
        insights.showing(running: [session(a)])
        await insights.settled()
        for _ in 0..<3 { await look(insights) }
        #expect(insights.notes.map(\.id) == ["\(a)#5"])
    }
}

// MARK: The words of a note, and the setting

struct NoteTextTests {
    @Test func plainTextStaysAsItIs() {
        #expect(NoteText.clean("Found two made-up papers.") == "Found two made-up papers.")
        #expect(NoteText.clean("**Bold** and `code`\n\n- a list") == "**Bold** and `code`\n\n- a list")
        #expect(NoteText.clean("Ångström — naïve “quotes” 日本語") == "Ångström — naïve “quotes” 日本語")
    }

    @Test func controlInvisibleAndDirectionCharactersGo() {
        #expect(NoteText.clean("a\u{0}b\u{7}c") == "abc")
        #expect(NoteText.clean("zero\u{200B}width\u{FEFF}") == "zerowidth")
        #expect(NoteText.clean("\u{202E}reversed") == "reversed")
        #expect(NoteText.clean("tab\tseparated") == "tab separated")
    }

    @Test func lineBreaksAreOneKindAndBlankRunsAreOne() {
        #expect(NoteText.clean("one\r\ntwo\rthree\u{2028}four") == "one\ntwo\nthree\nfour")
        #expect(NoteText.clean("\n\n\nfirst   \n\n\n\n\nsecond\n\n") == "first\n\nsecond")
    }

    @Test func nothingLeftIsNil() {
        #expect(NoteText.clean("") == nil)
        #expect(NoteText.clean("  \n\t \n ") == nil)
        #expect(NoteText.clean("\u{200B}\u{0}") == nil)
    }

    @Test func atMostThreeHundredCharactersEllipsisIncluded() {
        let exactly = String(repeating: "x", count: 300)
        #expect(NoteText.clean(exactly) == exactly)
        let cut = NoteText.clean(exactly + "y")
        #expect(cut?.count == 300)
        #expect(cut?.hasSuffix("…") == true)
        #expect(cut?.hasPrefix(String(repeating: "x", count: 299)) == true)
        // Counted in characters, not bytes.
        #expect(NoteText.clean(String(repeating: "界", count: 301))?.count == 300)
        // No space dangles before the ellipsis.
        let spaced = String(repeating: "x", count: 298) + " " + "yyyy"
        #expect(NoteText.clean(spaced)?.hasSuffix("x…") == true)
    }
}

struct LabInsightsGateTests {
    /// A suite of its own, as WelcomeTests does, holding the two switches as
    /// registered defaults: those are in memory, so no preferences file is
    /// ever written for it.
    private func gate(plans: Bool?, cards: Bool?) throws -> Bool {
        let name = "LabInsightsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var registered: [String: Any] = [:]
        if let plans { registered[SettingsKey.showPlansOnCard] = plans }
        if let cards { registered[SettingsKey.showCards] = cards }
        defaults.register(defaults: registered)
        return LabInsights.isEnabled(in: defaults)
    }

    @Test func bothOfTheFailureCardsSwitchesMustBeOn() throws {
        #expect(try gate(plans: true, cards: true))
        #expect(try !gate(plans: false, cards: true))
        #expect(try !gate(plans: true, cards: false))
        #expect(try !gate(plans: false, cards: false))
        // Nothing stored and nothing registered is off: Capsid registers its defaults at launch.
        #expect(try !gate(plans: nil, cards: nil))
    }

    @Test func theContractsLinesRead() {
        #expect(PlanProgress(step: 4, total: 6, title: "Check against published screens").line == "Step 4 of 6 · Check against published screens")
        #expect(ReviewerCounts(standing: 2, fixed: 0, running: 0, reviews: 1).line == "Reviewer: 2 findings")
        #expect(ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 1).line == "Reviewer: no findings")
        #expect(ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 0).line == nil)
        #expect(MidRunNote(id: "x#1", sessionID: "x", text: "t").at == nil)
    }
}
