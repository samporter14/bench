// SinceYouLeftSummary.swift — what changed while someone was away, grouped as
// board 2 groups it (DESIGN.md, Since You Left): what needs you, what
// finished, what stopped. Pure: the events Capsid saw, the sessions as they
// stand now and the moment the stretch began come in; the groups, the counts
// and every sentence come out. In memory only, like Recent.
import Foundation

/// The words of the section, one place for the sheet, the activity list, the
/// panel's card and the tests. The phone writes its own short forms from the
/// same numbers (RemoteWeb/app.js, `awaySpan`).
enum SinceYouLeftText {
    static let title = "Since you left"

    /// How long, in words: "2 hours 14 minutes", "1 hour", "45 minutes",
    /// "1 day 3 hours". Whole minutes, rounded; never "0 minutes".
    static func span(_ seconds: TimeInterval) -> String {
        let (days, hours, minutes) = parts(seconds)
        func unit(_ n: Int, _ one: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(one)s" }
        if days > 0 { return hours > 0 ? "\(unit(days, "day")) \(unit(hours, "hour"))" : unit(days, "day") }
        if hours > 0 { return minutes > 0 ? "\(unit(hours, "hour")) \(unit(minutes, "minute"))" : unit(hours, "hour") }
        return unit(max(minutes, 1), "minute")
    }

    /// The same in the activity list's short form: "2 h 14 min", "1 h", "45 min".
    static func shortSpan(_ seconds: TimeInterval) -> String {
        let (days, hours, minutes) = parts(seconds)
        if days > 0 { return hours > 0 ? "\(days) d \(hours) h" : "\(days) d" }
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        return "\(max(minutes, 1)) min"
    }

    private static func parts(_ seconds: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        let total = max(0, Int((seconds / 60).rounded()))
        let (hours, minutes) = total.quotientAndRemainder(dividingBy: 60)
        let (days, rest) = hours.quotientAndRemainder(dividingBy: 24)
        return (days, rest, minutes)
    }

    /// The sheet's overline: "Since you left · 2 hours 14 minutes".
    static func overline(_ seconds: TimeInterval) -> String { "\(title) · \(span(seconds))" }

    /// The activity list's section title: "Since you left · 2 h 14 min".
    static func listTitle(_ seconds: TimeInterval) -> String { "\(title) · \(shortSpan(seconds))" }

    static func finished(_ n: Int) -> String { "\(n) finished" }
    static func stopped(_ n: Int) -> String { "\(n) stopped" }
    /// "1 needs you", "2 need you".
    static func needs(_ n: Int) -> String { n == 1 ? "1 needs you" : "\(n) need you" }

    /// "3 finished, 1 stopped, 1 needs you": the groups with something in them.
    static func headline(finished f: Int, stopped s: Int, needs n: Int) -> String? {
        let parts = [f > 0 ? finished(f) : nil, s > 0 ? stopped(s) : nil, n > 0 ? needs(n) : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The panel's card: "Since you left: 3 finished, 1 stopped". What needs
    /// you has its own cards, so it isn't counted here. Nil when nothing
    /// finished or stopped.
    static func cardTitle(finished f: Int, stopped s: Int) -> String? {
        headline(finished: f, stopped: s, needs: 0).map { "\(title): \($0)" }
    }

    /// "waiting 41 min", "waiting 1 h 5 min".
    static func waiting(_ seconds: TimeInterval) -> String { "waiting \(shortSpan(seconds))" }

    /// "Plate reader QC" under "Assay development · 8:12 AM": the project and the time of day.
    static func meta(project: String, at: Date?) -> String {
        guard let at else { return project }
        return "\(project) · \(at.formatted(date: .omitted, time: .shortened))"
    }
}

/// How much of the 5-hour limit was used while away, from a reading when the
/// stretch began and the one now. Nil when it can't be said: a reading
/// missing, or the window started over meanwhile.
struct UsageWhileAway: Equatable, Sendable {
    /// Points of the limit used since the stretch began.
    let used: Int
    /// What is left now, and when the window starts over.
    let left: Int
    let resetsAt: Date?

    /// `baseline` is the limit when the stretch began, `current` the limit now.
    static func between(baseline: PlanLimit?, current: PlanLimit?) -> UsageWhileAway? {
        guard let baseline, let current, baseline.kind == current.kind else { return nil }
        // A window that started over, or a figure that went down: no honest difference.
        if let a = baseline.resetsAt, let b = current.resetsAt, abs(a.timeIntervalSince(b)) >= UsageSamples.sameWindow { return nil }
        guard current.usedPercent >= baseline.usedPercent else { return nil }
        return UsageWhileAway(used: current.usedPercent - baseline.usedPercent, left: current.leftPercent, resetsAt: current.resetsAt)
    }

    /// "62% left · resets 11:12 AM".
    var leftLine: String {
        guard let resetsAt else { return "\(left)% left" }
        return "\(left)% left · resets \(resetsAt.formatted(date: .omitted, time: .shortened))"
    }
}

struct SinceYouLeftSummary: Equatable, Sendable {
    /// One session in a group, with when it happened: the event's time for a
    /// finish or a stop, when it began to wait for one that needs you.
    struct Row: Identifiable, Equatable, Sendable {
        let session: SessionStatus
        let at: Date
        var id: String { session.id }
    }

    /// The last moment someone was at the Mac, and when they were back
    /// (nil while they are still away).
    let since: Date
    let back: Date?
    let needs: [Row]
    let finished: [Row]
    let stopped: [Row]

    /// The most session rows the sheet, the list and the phone show: the
    /// pictures and sentences of any more are never read.
    static let rowLimit = 6

    var isEmpty: Bool { needs.isEmpty && finished.isEmpty && stopped.isEmpty }
    var count: Int { needs.count + finished.count + stopped.count }

    /// How long they were away: to the return, or to `now` while it lasts.
    func away(now: Date) -> TimeInterval { max(0, (back ?? now).timeIntervalSince(since)) }

    var headline: String? {
        SinceYouLeftText.headline(finished: finished.count, stopped: stopped.count, needs: needs.count)
    }

    var cardTitle: String? {
        SinceYouLeftText.cardTitle(finished: finished.count, stopped: stopped.count)
    }

    /// The rows to show: what needs you first, then what stopped, then what
    /// finished, `limit` in all (each group in its own order). `hidden` is how
    /// many were left out.
    func shown(limit: Int = SinceYouLeftSummary.rowLimit) -> (needs: [Row], finished: [Row], stopped: [Row], hidden: Int) {
        let needs = Array(self.needs.prefix(limit))
        let stopped = Array(self.stopped.prefix(max(0, limit - needs.count)))
        let finished = Array(self.finished.prefix(max(0, limit - needs.count - stopped.count)))
        return (needs, finished, stopped, count - needs.count - stopped.count - finished.count)
    }

    /// The sessions whose details are read, in the order they are read: at most `limit`.
    func readOrder(limit: Int = SinceYouLeftSummary.rowLimit) -> [Row] {
        let rows = shown(limit: limit)
        return rows.needs + rows.stopped + rows.finished
    }

    /// Groups what happened since `since`. Only events after it count, and
    /// only a session's latest: a session that finished and then runs again,
    /// or that was answered somewhere else, is what it is now.
    ///   - needs you: the session began to wait since, and still does, and
    ///     its card isn't put off with Later;
    ///   - stopped: its latest event is an error and it neither works nor waits;
    ///   - finished: its latest event is a finish and it neither works nor waits.
    static func make(since: Date, back: Date?, events: [LabEvent], waiting: [SessionStatus], working: [SessionStatus],
                     putOff: Set<String> = []) -> SinceYouLeftSummary {
        var latest: [String: LabEvent] = [:]
        for event in events where event.at > since {
            guard let id = event.session?.id else { continue }
            if case .saved = event.kind { continue }
            if let known = latest[id], known.at > event.at { continue }
            latest[id] = event
        }
        let waitingNow = Dictionary(waiting.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let workingNow = Set(working.map(\.id))
        var needs: [Row] = [], finished: [Row] = [], stopped: [Row] = []
        for event in latest.values {
            guard let session = event.session else { continue }
            switch event.kind {
            case .needsInput:
                if let now = waitingNow[session.id], !putOff.contains(session.id) { needs.append(Row(session: now, at: event.at)) }
            case .failed:
                if waitingNow[session.id] == nil, !workingNow.contains(session.id) { stopped.append(Row(session: session, at: event.at)) }
            case .finished:
                if waitingNow[session.id] == nil, !workingNow.contains(session.id) { finished.append(Row(session: session, at: event.at)) }
            case .saved:
                break
            }
        }
        // Needs you: the longest wait first, as the activity list has it. The others in the order they happened.
        needs.sort { NeedsYou.waitedLonger($0.session, $1.session) }
        let byTime = { (a: Row, b: Row) in a.at != b.at ? a.at < b.at : a.id < b.id }
        return SinceYouLeftSummary(since: since, back: back, needs: needs, finished: finished.sorted(by: byTime),
                                   stopped: stopped.sorted(by: byTime))
    }
}

/// The first lines of one of Claude's answers, as plain words for a row under
/// a title: the Markdown's marks taken out, the first paragraphs kept. Pure.
enum AnswerLines {
    /// Enough for two lines of 13-point text across the sheet.
    static let limit = 240

    static func first(_ markdown: String, limit: Int = AnswerLines.limit) -> String? {
        var paragraphs: [[String]] = [[]]
        var headings: [String] = []
        var inFence = false
        func endParagraph() { if paragraphs.last?.isEmpty == false { paragraphs.append([]) } }
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                endParagraph()
                continue
            }
            if inFence { continue }
            if line.isEmpty { endParagraph(); continue }
            // A table, a rule and a picture say nothing in words.
            if line.hasPrefix("|") || line.hasPrefix("![") || line.allSatisfy({ "-*_= ".contains($0) }) { endParagraph(); continue }
            if line.hasPrefix("#") {
                let text = clean(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                if !text.isEmpty { headings.append(text) }
                endParagraph()
                continue
            }
            let text = clean(line)
            if !text.isEmpty { paragraphs[paragraphs.count - 1].append(text) }
        }
        let prose = paragraphs.filter { !$0.isEmpty }.map { $0.joined(separator: " ") }
        var words = ""
        for paragraph in prose {
            words += (words.isEmpty ? "" : " ") + paragraph
            if words.count >= limit { break }
        }
        // Only headings: better than nothing.
        if words.isEmpty { words = headings.joined(separator: " · ") }
        guard !words.isEmpty else { return nil }
        guard words.count > limit else { return words }
        // Cut at a word, with an ellipsis.
        let cut = String(words.prefix(limit))
        let trimmed = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        return trimmed.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "\u{2026}"
    }

    /// One line with its list, quote and emphasis marks taken out.
    private static func clean(_ line: String) -> String {
        var text = line
        for prefix in ["> ", "- ", "* ", "+ "] where text.hasPrefix(prefix) { text.removeFirst(prefix.count); break }
        // "1. " and "12) " lists.
        if let dot = text.firstIndex(where: { $0 == "." || $0 == ")" }), dot != text.startIndex,
           text[..<dot].allSatisfy(\.isNumber), text[text.index(after: dot)...].hasPrefix(" ") {
            text = String(text[text.index(dot, offsetBy: 2)...])
        }
        // [text](link) keeps its text.
        while let open = text.range(of: "["), let mid = text.range(of: "](", range: open.upperBound..<text.endIndex),
              let close = text.range(of: ")", range: mid.upperBound..<text.endIndex) {
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: String(text[open.upperBound..<mid.lowerBound]))
        }
        for mark in ["**", "__", "`", "*", "~~"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
