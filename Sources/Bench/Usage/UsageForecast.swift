// UsageForecast.swift — when a plan limit runs out if the last stretch of use
// carries on (DESIGN.md, Title-bar readouts). `UsageForecast.estimate` is
// pure, so the tests run it on made-up reads; `UsageSamples` is what the plan
// model keeps for it, in memory only.
import Foundation

/// One read of a limit: when, and the whole percent used then.
struct UsageSample: Equatable {
    let time: Date
    let usedPercent: Int
}

/// What the pace so far points to for one limit.
enum Forecast: Equatable {
    /// Too little to go on, or nothing left to forecast: nothing is said.
    case tooEarly
    /// The pace doesn't reach 100% before the window starts over.
    case lastsUntilReset
    /// The pace reaches 100% around this time, to the nearest five minutes.
    case limitAround(Date)

    /// The popover's quiet line under a limit's bar, or nil for nothing.
    func line(now: Date) -> String? {
        switch self {
        case .tooEarly: nil
        case .lastsUntilReset: "At this pace: lasts until it resets"
        case .limitAround(let time): "At this pace: limit around \(UsageForecast.clock(time, now: now))"
        }
    }
}

enum UsageForecast {
    /// The pace is the slope over this much of the window, the most recent.
    static let lookback: TimeInterval = 45 * 60
    /// Less than this and there's no pace yet.
    static let minimumSamples = 3
    static let minimumSpan: TimeInterval = 15 * 60
    /// Whole percents wobble by one, so a smaller climb is noise.
    static let minimumChange = 3
    /// The time is rounded to this: a finer one would claim too much.
    static let rounding: TimeInterval = 5 * 60

    /// When `samples` (oldest first) put the limit at 100%, if that comes
    /// before `resetsAt`. The line is a least-squares fit through the reads
    /// of the last 45 minutes, so one read's rounding doesn't swing it. A
    /// drop in the percent is the window starting over, so only the reads
    /// from the last drop on count. A flat line is too early, not "lasts".
    static func estimate(samples: [UsageSample], resetsAt: Date, now: Date) -> Forecast {
        let ordered = samples.filter { $0.time <= now }.sorted { $0.time < $1.time }
        let drop = ordered.indices.dropFirst().last { ordered[$0].usedPercent < ordered[$0 - 1].usedPercent }
        let recent = ordered[(drop ?? 0)...].filter { $0.time >= now.addingTimeInterval(-lookback) }
        guard let first = recent.first, let last = recent.last,
              recent.count >= minimumSamples,
              last.time.timeIntervalSince(first.time) >= minimumSpan,
              last.usedPercent - first.usedPercent >= minimumChange,
              last.usedPercent < 100 else { return .tooEarly }

        // Seconds from the first read, so the sums stay small.
        let xs = recent.map { $0.time.timeIntervalSince(first.time) }
        let ys = recent.map { Double($0.usedPercent) }
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let spread = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / spread
        guard slope.isFinite, slope > 0 else { return .tooEarly }

        let seconds = meanX + (100 - meanY) / slope
        // A fit that puts it at or before now has the limit about to run out.
        let projected = max(first.time.addingTimeInterval(seconds), now)
        let rounded = Date(timeIntervalSince1970: (projected.timeIntervalSince1970 / rounding).rounded() * rounding)
        return rounded >= resetsAt ? .lastsUntilReset : .limitAround(rounded)
    }

    /// "3:40 PM" for today, with the day ("Thu 3:40 PM") when it is another.
    static func clock(_ time: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(time, inSameDayAs: now)
            ? time.formatted(.dateTime.hour().minute())
            : time.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// The reads of one limit's current window, newest last. In memory only: it
/// starts over when the window does, and nothing is written to disk.
struct UsageSamples: Equatable {
    /// Two reset times this close are the same window: the API's seconds
    /// wobble between reads, while the next window is hours on.
    static let sameWindow: TimeInterval = 5 * 60
    /// Reads older than this are never looked at again.
    static let retention = 2 * UsageForecast.lookback

    private(set) var resetsAt: Date?
    private(set) var points: [UsageSample] = []

    /// Adds a read. One with no reset time can't be placed in a window, so
    /// it clears the rest.
    mutating func record(usedPercent: Int, resetsAt: Date?, at time: Date) {
        guard let resetsAt else {
            self = UsageSamples()
            return
        }
        if let known = self.resetsAt, abs(known.timeIntervalSince(resetsAt)) >= Self.sameWindow {
            points = []
        }
        self.resetsAt = resetsAt
        points.append(UsageSample(time: time, usedPercent: usedPercent))
        points.removeAll { $0.time < time.addingTimeInterval(-Self.retention) }
    }
}
