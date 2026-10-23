// AwayRule.swift — when someone has been away from the Mac, and when they are
// back (DESIGN.md, Since You Left). Pure: the clock, the idle time, whether
// the screen is off and the calendar come in as values, so the rule is tested
// without leaving a Mac alone.
//
// Nothing here runs a timer. `AwayWatcher` (SinceYouLeftModel.swift) hands it
// an observation whenever Capsid already looks (a read of the sessions, a
// wake, an unlock) and the rule decides from the last two what happened:
//
//   - **Away** begins at the last input before the idle stretch, found by
//     looking back: an observation with two minutes of idle time or more
//     says the stretch began that long ago. A screen that is off (asleep,
//     locked) begins it at once. A hole in the observations (Capsid was
//     suspended while the Mac slept) begins it at the last moment someone
//     was seen at the Mac.
//   - **Back** is the first observation with input after that moment. The
//     return counts when the stretch lasted `threshold` (30 minutes), or
//     when it crossed into a new day and lasted at least `dayFloor`: the
//     first activity of the day.
//
// The idle time alone is not trusted across a sleep (the counter may not run
// while the Mac sleeps): a screen that is off is away whatever it says.
import Foundation

struct AwayRule: Equatable, Sendable {
    /// A stretch this long, or longer, is worth telling about.
    static let threshold: TimeInterval = 30 * 60
    /// A stretch that crosses into a new day counts from here: the first
    /// activity of the day. Ten minutes is when the specimens hold still.
    static let dayFloor: TimeInterval = 10 * 60
    /// Idle for this long is the start of a stretch, to be judged when it ends.
    static let noticeAfter: TimeInterval = 2 * 60
    /// A hole of this length between two observations is a Mac that slept:
    /// they are never more than 30 seconds apart while it is awake.
    static let hole: TimeInterval = 10 * 60
    /// Input this soon after the stretch began is the same moment, measured
    /// twice (the idle counter and the clock do not read at one instant).
    static let slack: TimeInterval = 2

    /// A stretch away: from the last moment someone was at the Mac.
    struct Stretch: Equatable, Sendable {
        let since: Date
    }

    /// A return that counts.
    struct Return: Equatable, Sendable {
        let since: Date
        let back: Date
        var duration: TimeInterval { back.timeIntervalSince(since) }
    }

    /// The stretch under way, if there is one.
    private(set) var stretch: Stretch?
    /// The last observation: when it was made, and when someone last touched
    /// the Mac as of then.
    private struct Seen: Equatable, Sendable {
        let at: Date
        let activeAt: Date
    }
    private var last: Seen?

    init() {}

    /// Whether a stretch is under way.
    var isAway: Bool { stretch != nil }

    /// How long the stretch under way has lasted, at `now`.
    func awayFor(now: Date) -> TimeInterval? {
        stretch.map { max(0, now.timeIntervalSince($0.since)) }
    }

    /// Takes one observation: `idle` seconds since the last key, click or
    /// touch, and whether the screen is off. Answers the return it finds, if
    /// the stretch that ended counts.
    mutating func observe(now: Date, idle: TimeInterval, screenOff: Bool, calendar: Calendar = .current) -> Return? {
        let lastInput = now.addingTimeInterval(-max(0, idle))
        defer { last = Seen(at: now, activeAt: min(lastInput, now)) }

        if screenOff {
            // Nobody is at the screen. If someone was, this is where it starts.
            if stretch == nil { stretch = Stretch(since: min(lastInput, now)) }
            return nil
        }

        // A hole in the observations: the Mac slept without a word. The
        // stretch began where the last observation left someone present.
        if stretch == nil, let last, now.timeIntervalSince(last.at) >= Self.hole {
            stretch = Stretch(since: last.activeAt)
        }

        guard let current = stretch else {
            if idle >= Self.noticeAfter { stretch = Stretch(since: lastInput) }
            return nil
        }

        // Still no input since it began: still away.
        guard lastInput.timeIntervalSince(current.since) > Self.slack else { return nil }

        // Input: it ended. This is the first moment seen back (the input is
        // at most one observation old).
        stretch = idle >= Self.noticeAfter ? Stretch(since: lastInput) : nil
        let back = Return(since: current.since, back: lastInput)
        return Self.counts(back, calendar: calendar) ? back : nil
    }

    /// Whether a stretch that ended is worth telling about.
    static func counts(_ stretch: Return, calendar: Calendar = .current) -> Bool {
        if stretch.duration >= threshold { return true }
        return stretch.duration >= dayFloor && !calendar.isDate(stretch.since, inSameDayAs: stretch.back)
    }

    /// Forgets the stretch under way (the feature was switched off, or a
    /// test starts over).
    mutating func reset() {
        stretch = nil
        last = nil
    }
}
