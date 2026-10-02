// LabNotice.swift — a card that tells rather than asks (DESIGN.md, Notices):
// the plan nearly used up or reset, a session's context filling up, the week
// in review, what finished during a Nidus focus session. Notices queue after
// the cards about sessions, never play a sound, and always time out.
//
// `NoticeRules` decides when each one is due. It is pure, so the tests run it
// on made-up limits, histories and focus states.
import Foundation

struct LabNotice: Identifiable, Equatable {
    /// What the card's Open does.
    enum Action: Equatable {
        case none
        case openSession(SessionStatus)
    }

    let id: String
    let symbol: String
    let caption: String
    let title: String
    let detail: String
    /// How long it stays on top. Every notice has one, so none keeps the
    /// panel up while nobody is there.
    let lifetime: Duration
    var action: Action = .none
}

enum NoticeRules {
    // MARK: Plan

    /// At or above this much used, a limit gets its one card per window.
    static let planThreshold = 90
    /// A reset card only for a window seen ending this recently: launching
    /// the next morning is not news.
    static let resetFreshness: TimeInterval = 10 * 60

    /// The limits that get cards: the 5-hour window and the all-models week.
    static func watches(_ kind: PlanLimit.Kind) -> Bool { kind == .session || kind == .week }

    /// A window's key: its kind and its reset time to the minute, which
    /// stays the same however the seconds wobble between reads.
    static func windowKey(_ limit: PlanLimit) -> String? {
        guard let resetsAt = limit.resetsAt else { return nil }
        return "\(limit.kind)-\(Int((resetsAt.timeIntervalSince1970 / 60).rounded()))"
    }

    /// The cards due for `limits`, given the windows already announced (key
    /// to reset time), and the announced windows to keep from now on.
    static func plan(limits: [PlanLimit], announced: [String: Date], now: Date)
        -> (notices: [LabNotice], announced: [String: Date]) {
        var notices: [LabNotice] = []
        var kept = announced
        for limit in limits where watches(limit.kind) {
            guard let key = windowKey(limit), let resetsAt = limit.resetsAt, resetsAt > now else { continue }
            if limit.usedPercent >= planThreshold, kept[key] == nil {
                kept[key] = resetsAt
                notices.append(nearLimit(limit, now: now))
            }
        }
        // Announced windows that have ended: a reset card if it just happened
        // and the limit is in its new window, then forget them.
        for (key, resetsAt) in announced where resetsAt <= now {
            kept[key] = nil
            guard now.timeIntervalSince(resetsAt) < resetFreshness,
                  let kind = limits.first(where: { key.hasPrefix("\($0.kind)-") }),
                  let next = kind.resetsAt, next > now else { continue }
            notices.append(LabNotice(
                id: "plan-reset-\(key)", symbol: "arrow.counterclockwise.circle", caption: "Plan",
                title: kind.kind == .session ? "Your 5-hour limit has reset" : "Your weekly limit has reset",
                detail: "\(kind.leftPercent)% left", lifetime: .seconds(8)))
        }
        return (notices, kept)
    }

    private static func nearLimit(_ limit: PlanLimit, now: Date) -> LabNotice {
        let resets = limit.resetsAt.map { date -> String in
            limit.kind == .session
                ? "Resets \(date.formatted(.relative(presentation: .named, unitsStyle: .wide)))"
                : "Resets \(date.formatted(.dateTime.weekday(.wide).hour().minute()))"
        } ?? ""
        let which = limit.kind == .session ? "5-hour limit" : "weekly limit"
        return LabNotice(
            id: "plan-near-\(windowKey(limit) ?? "")", symbol: "gauge.with.dots.needle.67percent", caption: "Plan",
            title: "\(limit.leftPercent)% of your \(which) left", detail: resets, lifetime: .seconds(10))
    }

    // MARK: Context

    /// The share of the context window that gets its one card per session.
    static let contextThreshold = 85

    static func context(frameID: String?, percent: Int?, title: String?, announced: Set<String>) -> LabNotice? {
        guard let frameID, let percent, percent >= contextThreshold, !announced.contains(frameID) else { return nil }
        return LabNotice(
            id: "context-\(frameID)", symbol: "text.page", caption: "Context",
            title: title ?? "The session you have open",
            detail: "\(percent)% of its context window is used", lifetime: .seconds(10))
    }

    // MARK: Week in review

    struct Week: Equatable {
        let key: String
        let sessions: Int
        let messages: Int?
        let busiestDay: String?
    }

    /// Last week by `calendar` (the activity graph's), or nil when it had no
    /// sessions.
    static func lastWeek(_ history: ActivityHistory, today: Date, calendar: Calendar = .current) -> Week? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
              let lastStart = calendar.date(byAdding: .day, value: -7, to: thisWeek.start) else { return nil }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: lastStart) }
        let sessions = days.map { history.sessions.count(on: $0, calendar: calendar) }
        let total = sessions.reduce(0, +)
        guard total > 0 else { return nil }
        let messages = history.messages.map { counts in days.map { counts.count(on: $0, calendar: calendar) }.reduce(0, +) }
        // Named in the calendar's own time zone, the one the days were counted in.
        let weekdayName = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
        let busiest = zip(days, sessions).max { $0.1 < $1.1 }.map { day, _ in day.formatted(weekdayName) }
        let week = calendar.component(.weekOfYear, from: lastStart)
        let year = calendar.component(.yearForWeekOfYear, from: lastStart)
        return Week(key: "\(year)-W\(week)", sessions: total, messages: messages, busiestDay: busiest)
    }

    static func weekNotice(_ week: Week) -> LabNotice {
        let parts = [week.messages.map { "\($0) messages" }, week.busiestDay.map { "busiest on \($0)" }].compactMap { $0 }
        return LabNotice(
            id: "week-\(week.key)", symbol: "calendar", caption: "Week in review",
            title: "\(week.sessions) \(week.sessions == 1 ? "session" : "sessions") last week",
            detail: parts.joined(separator: " · "), lifetime: .seconds(30))
    }

    // MARK: Nidus

    /// What Nidus publishes in its folder (`focus.json`): only whether a
    /// focus session runs and until when. Never its goal.
    struct FocusFile: Codable, Equatable {
        var version: Int
        var focusing: Bool
        /// Seconds since 1970; nil for an open-ended session.
        var until: Double?
    }

    /// Focusing only while the file says so, Nidus runs, and the session's
    /// end hasn't passed: a file left behind by a crash means nothing.
    static func isFocusing(_ file: FocusFile?, nidusRunning: Bool, now: Date) -> Bool {
        guard let file, file.focusing, nidusRunning else { return false }
        if let until = file.until { return Date(timeIntervalSince1970: until) > now }
        return true
    }

    /// The one card for what finished during a focus session.
    static func held(_ sessions: [SessionStatus]) -> LabNotice? {
        guard let first = sessions.first else { return nil }
        let others = sessions.count - 1
        return LabNotice(
            id: "focus-held-\(sessions.map(\.id).joined(separator: "-"))", symbol: "checkmark.circle",
            caption: "While you focused",
            title: sessions.count == 1 ? first.displayTitle : "\(sessions.count) sessions finished",
            detail: others == 0 ? "Finished" : "\(first.displayTitle) and \(others) more",
            lifetime: .seconds(15), action: sessions.count == 1 ? .openSession(first) : .none)
    }
}
