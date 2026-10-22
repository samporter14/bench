// SinceYouLeftSummaryTests.swift — what Since You Left says and how it groups
// what happened: the sentences (singular and plural, the long and the short
// spans), the groups (only what happened after the stretch began, a session's
// latest event, what works or waits now), the six rows, the usage a stretch
// used, and the first lines of an answer. Pure: made-up sessions and events.
import Foundation
import Testing
@testable import Bench

struct SinceYouLeftTextTests {
    @Test func theLongSpanIsWrittenInWords() {
        #expect(SinceYouLeftText.span((2 * 60 + 14) * 60) == "2 hours 14 minutes")
        #expect(SinceYouLeftText.span(3600) == "1 hour")
        #expect(SinceYouLeftText.span(3900) == "1 hour 5 minutes")
        #expect(SinceYouLeftText.span(2700) == "45 minutes")
        #expect(SinceYouLeftText.span(60) == "1 minute")
        #expect(SinceYouLeftText.span(10) == "1 minute")
        #expect(SinceYouLeftText.span(26 * 3600) == "1 day 2 hours")
        #expect(SinceYouLeftText.span(48 * 3600) == "2 days")
        // Whole minutes, rounded.
        #expect(SinceYouLeftText.span(89 * 60 + 40) == "1 hour 30 minutes")
    }

    @Test func theShortSpanIsTheListsOwn() {
        #expect(SinceYouLeftText.shortSpan((2 * 60 + 14) * 60) == "2 h 14 min")
        #expect(SinceYouLeftText.shortSpan(3900) == "1 h 5 min")
        #expect(SinceYouLeftText.shortSpan(3600) == "1 h")
        #expect(SinceYouLeftText.shortSpan(45 * 60) == "45 min")
        #expect(SinceYouLeftText.shortSpan(26 * 3600) == "1 d 2 h")
    }

    @Test func theOverlineAndTheListTitleAreTheSpansAfterTheName() {
        #expect(SinceYouLeftText.overline((2 * 60 + 14) * 60) == "Since you left \u{00B7} 2 hours 14 minutes")
        #expect(SinceYouLeftText.listTitle((2 * 60 + 14) * 60) == "Since you left \u{00B7} 2 h 14 min")
    }

    @Test func theHeadlineHasTheGroupsThatHaveSomething() {
        #expect(SinceYouLeftText.headline(finished: 3, stopped: 1, needs: 1) == "3 finished, 1 stopped, 1 needs you")
        #expect(SinceYouLeftText.headline(finished: 1, stopped: 0, needs: 0) == "1 finished")
        #expect(SinceYouLeftText.headline(finished: 0, stopped: 2, needs: 2) == "2 stopped, 2 need you")
        #expect(SinceYouLeftText.headline(finished: 0, stopped: 0, needs: 1) == "1 needs you")
        #expect(SinceYouLeftText.headline(finished: 0, stopped: 0, needs: 0) == nil)
    }

    @Test func theCardCountsWhatFinishedAndStoppedNotWhatNeedsYou() {
        #expect(SinceYouLeftText.cardTitle(finished: 3, stopped: 1) == "Since you left: 3 finished, 1 stopped")
        #expect(SinceYouLeftText.cardTitle(finished: 1, stopped: 0) == "Since you left: 1 finished")
        #expect(SinceYouLeftText.cardTitle(finished: 0, stopped: 0) == nil)
    }

    @Test func aWaitIsInTheShortForm() {
        #expect(SinceYouLeftText.waiting(41 * 60) == "waiting 41 min")
        #expect(SinceYouLeftText.waiting(65 * 60) == "waiting 1 h 5 min")
    }
}

struct SinceYouLeftSummaryTests {
    private static let t0 = Date(timeIntervalSince1970: 1_791_986_400)

    private static func session(_ id: String, _ state: SessionState, reason: WaitingReason? = nil, updated: Double = 0,
                                title: String? = nil) -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Example project", title: title ?? "Session \(id)", state: state,
                      updatedAt: t0.addingTimeInterval(updated * 60), startedAt: nil, waitingReason: reason)
    }

    private static func event(_ kind: LabEvent.Kind, _ session: SessionStatus, at minutes: Double) -> LabEvent {
        LabEvent(kind, session: session, at: t0.addingTimeInterval(minutes * 60))
    }

    private func make(events: [LabEvent], waiting: [SessionStatus] = [], working: [SessionStatus] = [],
                      putOff: Set<String> = [], since: Double = 0) -> SinceYouLeftSummary {
        SinceYouLeftSummary.make(since: Self.t0.addingTimeInterval(since * 60), back: Self.t0.addingTimeInterval(200 * 60),
                                 events: events, waiting: waiting, working: working, putOff: putOff)
    }

    @Test func eachGroupHoldsWhatHappenedAfterTheStretchBegan() {
        let a = Self.session("a", .finished), b = Self.session("b", .error), c = Self.session("c", .needsInput, reason: .question, updated: 40)
        let summary = make(events: [
            Self.event(.finished, a, at: 20), Self.event(.failed, b, at: 30), Self.event(.needsInput(.question), c, at: 40),
        ], waiting: [c])
        #expect(summary.finished.map(\.id) == ["a"])
        #expect(summary.stopped.map(\.id) == ["b"])
        #expect(summary.needs.map(\.id) == ["c"])
        #expect(summary.headline == "1 finished, 1 stopped, 1 needs you")
        #expect(summary.finished.first?.at == Self.t0.addingTimeInterval(20 * 60))
    }

    @Test func nothingOldIsInIt() {
        let a = Self.session("a", .finished), b = Self.session("b", .error)
        // One event before the stretch, one exactly at its start (the last input, not after it): neither counts.
        let summary = make(events: [Self.event(.finished, a, at: -5), Self.event(.failed, b, at: 0)], since: 0)
        #expect(summary.isEmpty)
        #expect(summary.headline == nil)
    }

    @Test func aSessionIsWhatItsLatestEventSaysAndNothingElse() {
        let a = Self.session("a", .finished)
        // It asked, then was answered somewhere else and finished: finished only.
        let summary = make(events: [Self.event(.needsInput(.question), a, at: 10), Self.event(.finished, a, at: 25)])
        #expect(summary.needs.isEmpty)
        #expect(summary.finished.map(\.id) == ["a"])
        // Finished twice (two turns): once, at the later time.
        let twice = make(events: [Self.event(.finished, a, at: 10), Self.event(.finished, a, at: 25)])
        #expect(twice.finished.count == 1)
        #expect(twice.finished.first?.at == Self.t0.addingTimeInterval(25 * 60))
    }

    @Test func aSessionThatWorksOrWaitsNowIsNotFinishedOrStopped() {
        let a = Self.session("a", .finished), b = Self.session("b", .error), c = Self.session("c", .needsInput, reason: .plan)
        let events = [Self.event(.finished, a, at: 10), Self.event(.failed, b, at: 11), Self.event(.finished, c, at: 12)]
        let summary = make(events: events, waiting: [c], working: [Self.session("a", .running), Self.session("b", .running)])
        #expect(summary.finished.isEmpty)
        #expect(summary.stopped.isEmpty)
        // Waiting now, but its latest event is a finish: it isn't something that began to wait since.
        #expect(summary.needs.isEmpty)
    }

    @Test func whatWaitedBeforeTheStretchAndStillWaitsIsNotNews() {
        let old = Self.session("old", .needsInput, reason: .question, updated: -90)
        let summary = make(events: [Self.event(.needsInput(.question), old, at: -90)], waiting: [old])
        #expect(summary.needs.isEmpty)
    }

    @Test func aCardPutOffWithLaterIsNotAskedAgainHere() {
        let c = Self.session("c", .needsInput, reason: .question, updated: 40)
        let summary = make(events: [Self.event(.needsInput(.question), c, at: 40)], waiting: [c], putOff: ["c"])
        #expect(summary.needs.isEmpty)
    }

    @Test func theOrderIsTheLongestWaitFirstThenTheOrderTheyHappened() {
        let a = Self.session("a", .needsInput, reason: .question, updated: 50)
        let b = Self.session("b", .needsInput, reason: .plan, updated: 30)
        let x = Self.session("x", .finished), y = Self.session("y", .finished), z = Self.session("z", .error), w = Self.session("w", .error)
        let summary = make(events: [
            Self.event(.finished, y, at: 70), Self.event(.finished, x, at: 20), Self.event(.failed, w, at: 90), Self.event(.failed, z, at: 15),
            Self.event(.needsInput(.question), a, at: 50), Self.event(.needsInput(.plan), b, at: 30),
        ], waiting: [a, b])
        #expect(summary.needs.map(\.id) == ["b", "a"])
        #expect(summary.finished.map(\.id) == ["x", "y"])
        #expect(summary.stopped.map(\.id) == ["z", "w"])
    }

    @Test func aSavedDownloadAndAnEventWithNoSessionAreNoOneRow() {
        let summary = make(events: [LabEvent(.saved(URL(fileURLWithPath: "/tmp/made-up.csv")), session: nil, at: Self.t0.addingTimeInterval(600))])
        #expect(summary.isEmpty)
    }

    @Test func sixRowsAreShownNeedsYouFirstThenStoppedThenFinished() {
        let needs = (1...2).map { Self.session("n\($0)", .needsInput, reason: .question, updated: Double(10 + $0)) }
        let stopped = (1...2).map { Self.session("s\($0)", .error) }
        let finished = (1...5).map { Self.session("f\($0)", .finished) }
        var events: [LabEvent] = []
        for (index, s) in needs.enumerated() { events.append(Self.event(.needsInput(.question), s, at: Double(10 + index + 1))) }
        for (index, s) in stopped.enumerated() { events.append(Self.event(.failed, s, at: Double(30 + index))) }
        for (index, s) in finished.enumerated() { events.append(Self.event(.finished, s, at: Double(50 + index))) }
        let summary = make(events: events, waiting: needs)
        #expect(summary.count == 9)
        let shown = summary.shown()
        #expect(shown.needs.map(\.id) == ["n1", "n2"])
        #expect(shown.stopped.map(\.id) == ["s1", "s2"])
        #expect(shown.finished.map(\.id) == ["f1", "f2"])
        #expect(shown.hidden == 3)
        #expect(summary.readOrder().count == SinceYouLeftSummary.rowLimit)
        #expect(summary.readOrder().map(\.id) == ["n1", "n2", "s1", "s2", "f1", "f2"])
        // A smaller summary shows everything.
        #expect(make(events: [events[2]]).shown().hidden == 0)
    }

    @Test func howLongTheyWereAwayIsToTheReturnOrToNowWhileItLasts() {
        let ended = SinceYouLeftSummary(since: Self.t0, back: Self.t0.addingTimeInterval(134 * 60), needs: [], finished: [], stopped: [])
        #expect(ended.away(now: Self.t0.addingTimeInterval(500 * 60)) == 134 * 60)
        let going = SinceYouLeftSummary(since: Self.t0, back: nil, needs: [], finished: [], stopped: [])
        #expect(going.away(now: Self.t0.addingTimeInterval(45 * 60)) == 45 * 60)
    }
}

struct UsageWhileAwayTests {
    private static let resets = Date(timeIntervalSince1970: 1_791_990_000)

    @Test func theDifferenceIsWhatTheStretchUsed() throws {
        let used = try #require(UsageWhileAway.between(baseline: PlanLimit(kind: .session, usedPercent: 12, resetsAt: Self.resets),
                                                      current: PlanLimit(kind: .session, usedPercent: 50, resetsAt: Self.resets.addingTimeInterval(20))))
        #expect(used.used == 38)
        #expect(used.left == 50)
        #expect(used.leftLine.hasPrefix("50% left \u{00B7} resets "))
    }

    @Test func aWindowThatStartedOverSaysNothing() {
        let before = PlanLimit(kind: .session, usedPercent: 80, resetsAt: Self.resets)
        let after = PlanLimit(kind: .session, usedPercent: 10, resetsAt: Self.resets.addingTimeInterval(5 * 3600))
        #expect(UsageWhileAway.between(baseline: before, current: after) == nil)
        // Even if the new window has used more than the old one had.
        let busy = PlanLimit(kind: .session, usedPercent: 95, resetsAt: Self.resets.addingTimeInterval(5 * 3600))
        #expect(UsageWhileAway.between(baseline: PlanLimit(kind: .session, usedPercent: 4, resetsAt: Self.resets), current: busy) == nil)
        // And a figure that went down with the same window is not a difference.
        #expect(UsageWhileAway.between(baseline: before, current: PlanLimit(kind: .session, usedPercent: 70, resetsAt: Self.resets)) == nil)
    }

    @Test func aMissingReadingLeavesItOut() {
        let limit = PlanLimit(kind: .session, usedPercent: 10, resetsAt: Self.resets)
        #expect(UsageWhileAway.between(baseline: nil, current: limit) == nil)
        #expect(UsageWhileAway.between(baseline: limit, current: nil) == nil)
        #expect(UsageWhileAway.between(baseline: limit, current: PlanLimit(kind: .week, usedPercent: 40, resetsAt: Self.resets)) == nil)
    }

    @Test func noResetTimeIsStillTold() throws {
        let used = try #require(UsageWhileAway.between(baseline: PlanLimit(kind: .session, usedPercent: 0, resetsAt: nil),
                                                      current: PlanLimit(kind: .session, usedPercent: 38, resetsAt: nil)))
        #expect(used.leftLine == "62% left")
        #expect(used.used == 38)
    }
}

struct AnswerLinesTests {
    @Test func theFirstParagraphsAreKeptAsPlainWords() {
        let markdown = """
        ## Summary

        All plates **passed** except plate 7, which has an edge effect in column 12. See [the table](https://example.com/t).

        - `plates_cleaned.csv` has the rest
        """
        #expect(AnswerLines.first(markdown) == "All plates passed except plate 7, which has an edge effect in column 12. See the table. plates_cleaned.csv has the rest")
    }

    @Test func codeTablesPicturesAndRulesSaySNothingInWords() {
        let markdown = """
        ```python
        print("hello")
        ```
        | a | b |
        |---|---|
        | 1 | 2 |
        ![Figure](fig.png)
        ---
        The fit converged after 14 iterations.
        """
        #expect(AnswerLines.first(markdown) == "The fit converged after 14 iterations.")
    }

    @Test func onlyHeadingsIsBetterThanNothing() {
        #expect(AnswerLines.first("# Results\n\n## Methods") == "Results \u{00B7} Methods")
        #expect(AnswerLines.first("") == nil)
        #expect(AnswerLines.first("   \n\n") == nil)
    }

    @Test func aLongAnswerIsCutAtAWordWithAnEllipsis() throws {
        let words = Array(repeating: "normalized", count: 60).joined(separator: " ")
        let line = try #require(AnswerLines.first(words, limit: 100))
        #expect(line.hasSuffix("\u{2026}"))
        #expect(line.count <= 101)
        #expect(!line.dropLast().hasSuffix(" "))
    }

    @Test func numberedListsAndQuotesLoseTheirMarks() {
        #expect(AnswerLines.first("1. First step\n2. Second step") == "First step Second step")
        #expect(AnswerLines.first("> Quoted words") == "Quoted words")
    }
}
