// TimeSpan.swift — how Capsid writes a length of time and when a limit starts
// over, in one style everywhere (DESIGN.md, Title-bar readouts): "1h 28m",
// "28m", "45s", never "1 h 28 m" or "1 hour". The toolbar, the Usage popover,
// the plan notices and a finished card's duration all come here.
//
// Not here: the running turn clock ("4:12", `ElapsedClock`), which is a clock
// and not a length; and times of day ("Resumes at 3:40 PM").
import Foundation

enum TimeSpan {
    /// How long something took: "45s" under a minute, then whole minutes,
    /// "12m", "1h 5m", "2h". The nearest minute, so a turn of 59.6 s is "1m".
    static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total < 60 ? "\(total)s" : minutes(Int((Double(total) / 60).rounded()))
    }

    /// How long until something: whole minutes, rounded up so a countdown
    /// never reads "0m" while there is time left.
    static func countdown(_ seconds: TimeInterval) -> String {
        minutes(max(1, Int((seconds / 60).rounded(.up))))
    }

    /// What follows "Resets" or "resets": "in 1h 28m" within a day, "now" once
    /// it is over, and past a day the weekday ("Thu"), with the time when
    /// there is room for it ("Thu 11:27 PM"; `withTime`). The toolbar has no
    /// room, so it leaves the time off.
    static func reset(_ date: Date, now: Date, withTime: Bool = false,
                      calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        guard seconds >= 24 * 3600 else { return "in " + countdown(seconds) }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
        if withTime { style = style.hour().minute() }
        return date.formatted(style)
    }

    /// `reset` for VoiceOver, which reads "1h 28m" letter by letter: the same
    /// words with the units spelled out, "in 1 hour, 28 minutes".
    static func spokenReset(_ date: Date, now: Date,
                            calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0, seconds < 24 * 3600 else { return reset(date, now: now, withTime: true, calendar: calendar, locale: locale) }
        let wholeMinutes = max(1, Int((seconds / 60).rounded(.up)))
        return "in " + Duration.seconds(wholeMinutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2).locale(locale))
    }

    /// "28m", "1h 5m", or "2h" for an exact hour: minutes alone under an hour.
    private static func minutes(_ total: Int) -> String {
        let (hours, rest) = total.quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
