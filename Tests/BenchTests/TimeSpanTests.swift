// TimeSpanTests.swift — one way to write a length of time and when a limit
// starts over (TimeSpan): "1h 28m" in the toolbar, the Usage popover, the plan
// notices and a finished card. Fixed dates, a fixed zone and a fixed locale.
import Foundation
import Testing
@testable import Bench

struct TimeSpanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let locale = Locale(identifier: "en_US")
    /// Monday 19 October 2026, noon in UTC.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))! }

    /// The Mac's own formats put a narrow no-break space before "PM".
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test func aDurationIsMinutesAndHoursInTheCompactStyle() {
        #expect(TimeSpan.short(0) == "0s")
        #expect(TimeSpan.short(45) == "45s")
        #expect(TimeSpan.short(12 * 60) == "12m")
        #expect(TimeSpan.short(3600 + 5 * 60) == "1h 5m")
        #expect(TimeSpan.short(2 * 3600) == "2h")
        // Never "1h 0m", and never "60m".
        #expect(TimeSpan.short(59 * 60 + 40) == "1h")
    }

    @Test func aDurationRoundsToTheNearestMinute() {
        #expect(TimeSpan.short(12 * 60 + 29) == "12m")
        #expect(TimeSpan.short(12 * 60 + 31) == "13m")
        #expect(TimeSpan.short(59.6) == "1m")
        // A clock that ran backwards is no time at all.
        #expect(TimeSpan.short(-30) == "0s")
    }

    @Test func aCountdownRoundsUpSoItNeverReadsZeroWhileTimeIsLeft() {
        #expect(TimeSpan.countdown(0.4) == "1m")
        #expect(TimeSpan.countdown(60) == "1m")
        #expect(TimeSpan.countdown(61) == "2m")
        #expect(TimeSpan.countdown(88 * 60) == "1h 28m")
        #expect(TimeSpan.countdown(88 * 60 - 20) == "1h 28m")
        #expect(TimeSpan.countdown(3600) == "1h")
        #expect(TimeSpan.countdown(3601) == "1h 1m")
        #expect(TimeSpan.countdown(5 * 3600) == "5h")
    }

    @Test func aResetWithinADayIsACountdownAndPastItAWeekday() throws {
        func reset(in seconds: TimeInterval, withTime: Bool = false) -> String {
            plain(TimeSpan.reset(now.addingTimeInterval(seconds), now: now, withTime: withTime, calendar: calendar, locale: locale))
        }
        #expect(reset(in: 88 * 60) == "in 1h 28m")
        #expect(reset(in: 12 * 60) == "in 12m")
        #expect(reset(in: 24 * 3600 - 60) == "in 23h 59m")
        #expect(reset(in: 0) == "now")
        #expect(reset(in: -5) == "now")
        // Thursday 22 October, 11:27 PM: "Thu" where there is no room, with the time where there is.
        let thursday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 23, minute: 27)))
        #expect(plain(TimeSpan.reset(thursday, now: now, calendar: calendar, locale: locale)) == "Thu")
        #expect(plain(TimeSpan.reset(thursday, now: now, withTime: true, calendar: calendar, locale: locale)) == "Thu 11:27 PM")
    }

    @Test func theToolbarAndThePopoverAgreeOnACountdown() {
        // The two places that used to write "1h 28m" and "1 h 28 m".
        let date = now.addingTimeInterval(88 * 60)
        let toolbar = "resets " + TimeSpan.reset(date, now: now, calendar: calendar, locale: locale)
        let popover = "Resets " + TimeSpan.reset(date, now: now, withTime: true, calendar: calendar, locale: locale)
        #expect(toolbar == "resets in 1h 28m")
        #expect(popover == "Resets in 1h 28m")
    }

    @Test func aSpokenResetSpellsTheUnitsOut() throws {
        func spoken(in seconds: TimeInterval) -> String {
            plain(TimeSpan.spokenReset(now.addingTimeInterval(seconds), now: now, calendar: calendar, locale: locale))
        }
        #expect(spoken(in: 88 * 60) == "in 1 hour, 28 minutes")
        #expect(spoken(in: 45 * 60) == "in 45 minutes")
        #expect(spoken(in: 20) == "in 1 minute")
        #expect(spoken(in: 0) == "now")
        let thursday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 23, minute: 27)))
        #expect(plain(TimeSpan.spokenReset(thursday, now: now, calendar: calendar, locale: locale)) == "Thu 11:27 PM")
    }
}
