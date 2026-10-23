// AwayRuleTests.swift — when someone has been away and when they are back:
// the 30 minute threshold, the first activity of the day, a screen that is
// off, a Mac that slept without a word, and nothing old. The rule is pure and
// the clock, the idle time and the calendar are given, so no Mac is left alone.
import Foundation
import Testing
@testable import Bench

struct AwayRuleTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-10-14 14:00 UTC.
    private static let noon = Date(timeIntervalSince1970: 1_791_986_400)

    private static func minutes(_ n: Double) -> TimeInterval { n * 60 }

    private func observe(_ rule: inout AwayRule, at start: Date, plus minutes: Double, idle: TimeInterval,
                         screenOff: Bool = false) -> AwayRule.Return? {
        rule.observe(now: start.addingTimeInterval(Self.minutes(minutes)), idle: idle, screenOff: screenOff, calendar: Self.calendar)
    }

    @Test func anIdleStretchOfThirtyMinutesCountsWhenInputComesBack() {
        var rule = AwayRule()
        let t0 = Self.noon
        #expect(observe(&rule, at: t0, plus: 0, idle: 3) == nil)
        #expect(!rule.isAway)
        // Nothing touched for 5 minutes: the stretch began 5 minutes ago, at t0.
        #expect(observe(&rule, at: t0, plus: 5, idle: Self.minutes(5)) == nil)
        #expect(rule.stretch?.since == t0)
        #expect(observe(&rule, at: t0, plus: 20, idle: Self.minutes(20)) == nil)
        // Someone is back at minute 41, 4 seconds ago: the stretch lasted 40 minutes.
        let back = observe(&rule, at: t0, plus: 41, idle: 60)
        #expect(back == AwayRule.Return(since: t0, back: t0.addingTimeInterval(Self.minutes(40))))
        #expect(back?.duration == Self.minutes(40))
        #expect(!rule.isAway)
    }

    @Test func aShorterStretchIsNothing() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: 2)
        _ = observe(&rule, at: t0, plus: 10, idle: Self.minutes(10))
        #expect(rule.isAway)
        #expect(observe(&rule, at: t0, plus: 29, idle: 4) == nil)
        #expect(!rule.isAway)
    }

    @Test func exactlyThirtyMinutesCountsAndAMinuteLessDoesNot() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: Self.minutes(2))
        // Back 30 minutes after the last input, which was 2 minutes before t0.
        #expect(observe(&rule, at: t0, plus: 28, idle: 0) != nil)
        var short = AwayRule()
        _ = observe(&short, at: t0, plus: 0, idle: Self.minutes(2))
        #expect(observe(&short, at: t0, plus: 27, idle: 0) == nil)
    }

    @Test func lessThanTwoMinutesOfIdleIsNotYetAStretch() {
        var rule = AwayRule()
        _ = observe(&rule, at: Self.noon, plus: 0, idle: 110)
        #expect(!rule.isAway)
        _ = observe(&rule, at: Self.noon, plus: 1, idle: 170)
        #expect(rule.isAway)
    }

    @Test func theSameStretchObservedAgainKeepsItsStart() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 5, idle: Self.minutes(5))
        let first = rule.stretch
        // The idle counter and the clock don't read at one instant: a second of noise is the same moment.
        _ = rule.observe(now: t0.addingTimeInterval(Self.minutes(15) + 1), idle: Self.minutes(15) + 0.4, screenOff: false, calendar: Self.calendar)
        #expect(rule.stretch == first)
    }

    @Test func aScreenThatIsOffIsAwayWhateverTheIdleTimeSays() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: 1)
        // Locked a minute later with a second of idle time: the stretch begins there.
        #expect(observe(&rule, at: t0, plus: 1, idle: 1, screenOff: true) == nil)
        #expect(rule.stretch?.since == t0.addingTimeInterval(Self.minutes(1) - 1))
        // A dark wake at 3:00 that reads a small idle time (the counter doesn't run asleep): still away.
        #expect(observe(&rule, at: t0, plus: 180, idle: 2, screenOff: true) == nil)
        #expect(rule.isAway)
        // Unlocked with a key: back, after nearly three hours.
        let back = observe(&rule, at: t0, plus: 185, idle: 3)
        #expect(back != nil)
        #expect((back?.duration ?? 0) > Self.minutes(170))
    }

    @Test func aMacThatSleptWithoutAWordIsAwayFromWhereItWasLastSeen() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: 2)
        // Nothing observed for eight hours, then a key a moment ago.
        let back = observe(&rule, at: t0, plus: 8 * 60, idle: 3)
        #expect(back?.since == t0.addingTimeInterval(-2))
        #expect((back?.duration ?? 0) > Self.minutes(7 * 60))
    }

    @Test func aHoleInTheObservationsWithNoInputYetIsAwayAndStaysAway() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: 2)
        // Woke in the night for a moment with nobody there: idle covers the whole hole.
        #expect(observe(&rule, at: t0, plus: 8 * 60, idle: Self.minutes(8 * 60)) == nil)
        #expect(rule.isAway)
    }

    @Test func theFirstActivityOfTheDayCountsBelowThirtyMinutes() {
        // 23:52 to 00:05: thirteen minutes, across midnight.
        var overnight = AwayRule()
        let late = Self.noon.addingTimeInterval(9 * 3600 + 52 * 60)   // 23:52 UTC
        _ = observe(&overnight, at: late, plus: 0, idle: Self.minutes(3))
        let back = observe(&overnight, at: late, plus: 13, idle: 5)
        #expect(back != nil)
        #expect(Self.calendar.component(.hour, from: late) == 23)
        // The same thirteen minutes in the middle of a day are not.
        var same = AwayRule()
        _ = observe(&same, at: Self.noon, plus: 0, idle: Self.minutes(3))
        #expect(observe(&same, at: Self.noon, plus: 13, idle: 5) == nil)
        // And across midnight for only a few minutes is nothing: the day's floor is ten minutes.
        var brief = AwayRule()
        _ = observe(&brief, at: late, plus: 0, idle: Self.minutes(3))
        #expect(observe(&brief, at: late, plus: 8, idle: 5) == nil)
    }

    @Test func aReturnIsToldOnceAndNothingOldComesBack() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: Self.minutes(2))
        #expect(observe(&rule, at: t0, plus: 50, idle: 3) != nil)
        // More activity afterwards is just being present.
        #expect(observe(&rule, at: t0, plus: 51, idle: 3) == nil)
        #expect(observe(&rule, at: t0, plus: 52, idle: 1) == nil)
        #expect(!rule.isAway)
        // A new stretch has a new start: the old one is not carried over.
        _ = observe(&rule, at: t0, plus: 60, idle: Self.minutes(8))
        #expect(rule.stretch?.since == t0.addingTimeInterval(Self.minutes(52)))
    }

    @Test func aStretchStartedByTheReturnsOwnIdleReadingIsTracked() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 0, idle: Self.minutes(2))
        // Back after an hour, but already idle again for 3 minutes when seen.
        let back = observe(&rule, at: t0, plus: 63, idle: Self.minutes(3))
        // The input that ended the stretch is the one 3 minutes ago; the idle again begins there.
        #expect(back != nil)
        #expect(rule.isAway)
        #expect(rule.stretch?.since == t0.addingTimeInterval(Self.minutes(60)))
    }

    @Test func awayForIsHowLongTheStretchHasLasted() {
        var rule = AwayRule()
        let t0 = Self.noon
        #expect(rule.awayFor(now: t0) == nil)
        _ = observe(&rule, at: t0, plus: 6, idle: Self.minutes(6))
        #expect(rule.awayFor(now: t0.addingTimeInterval(Self.minutes(36))) == Self.minutes(36))
    }

    @Test func aClockThatMovedBackwardsIsNotAReturn() {
        var rule = AwayRule()
        let t0 = Self.noon
        _ = observe(&rule, at: t0, plus: 5, idle: Self.minutes(5))
        #expect(observe(&rule, at: t0, plus: 2, idle: Self.minutes(2)) == nil)
        #expect(rule.isAway)
    }
}
