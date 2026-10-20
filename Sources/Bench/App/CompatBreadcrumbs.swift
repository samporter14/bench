// CompatBreadcrumbs.swift — the last time a feature looked for something in
// Claude Science and found it changed (DESIGN.md, Diagnostics). When a
// Claude Science update moves a page hook or an answer's shape, features fail
// quietly; this keeps the latest such miss in memory, logs it at notice level
// and lets Diagnostics say "Last problem: …".
//
// Only misses that mean the markup or an answer changed are recorded, never
// ordinary states: no tab strip because no panel is open, a signed-out page
// with or without its Sign in card (the sign-in has a fallback of its own), a
// refused or slow read, a session with no turns yet. Every miss is a case of
// `CompatMiss`, a fixed phrase, so nothing read from the page (a name, an id)
// can reach the log or the report.
import Foundation
import os

private let log = Logger(subsystem: "local.sam.bench", category: "compat")

/// Every way a feature can find Claude Science changed. The phrase says what
/// was missing, in plain words.
enum CompatMiss: String, CaseIterable, Sendable {
    // Close Other Tabs and Close All Tabs (Web/PageTabs.swift)
    case severalTabStrips
    case tabStripWithoutToolbar
    case tabWithoutCloseButton
    case noTabMarkedShown
    case tabAnswerNotUnderstood
    // The usage readout (Usage/PlanUsageModel.swift)
    case usageNotDecoded
    case usageWithoutLimits
    // The context ring (Context/ContextModel.swift)
    case contextNotDecoded
    case contextWithoutWindow
    case contextWithoutTurns
    // The plan on a card, and Approve (Lab/PlanApproval.swift)
    case planFrameNotUnderstood
    case planWithoutVersion
    case planFileNotUnderstood
    case planFileWithoutSummary
    case approveRouteGone
    case approveAnswerNotUnderstood

    var feature: CompatFeature {
        switch self {
        case .severalTabStrips, .tabStripWithoutToolbar, .tabWithoutCloseButton, .noTabMarkedShown, .tabAnswerNotUnderstood:
            .closeTabs
        case .usageNotDecoded, .usageWithoutLimits:
            .usage
        case .contextNotDecoded, .contextWithoutWindow, .contextWithoutTurns:
            .context
        case .planFrameNotUnderstood, .planWithoutVersion, .planFileNotUnderstood, .planFileWithoutSummary:
            .planCard
        case .approveRouteGone, .approveAnswerNotUnderstood:
            .approve
        }
    }

    /// What was missing, as the end of a sentence.
    var phrase: String {
        switch self {
        case .severalTabStrips: "the page has more than one tab strip"
        case .tabStripWithoutToolbar: "the tab strip has no toolbar of open panels"
        case .tabWithoutCloseButton: "a tab has no close button"
        case .noTabMarkedShown: "no single tab is marked as the shown one"
        case .tabAnswerNotUnderstood: "the page's answer wasn't understood"
        case .usageNotDecoded: "the usage answer couldn't be read"
        case .usageWithoutLimits: "the usage answer has none of the limits Capsid reads"
        case .contextNotDecoded: "the context answer couldn't be read"
        case .contextWithoutWindow: "the context answer has no window size"
        case .contextWithoutTurns: "the context answer has no turns with a size"
        case .planFrameNotUnderstood: "the session's answer has no status"
        case .planWithoutVersion: "a session waiting for its plan names no plan file"
        case .planFileNotUnderstood: "the plan file wasn't a JSON object"
        case .planFileWithoutSummary: "the plan file has no summary"
        case .approveRouteGone: "the Approve route wasn't found"
        case .approveAnswerNotUnderstood: "the Approve answer wasn't what Capsid expects"
        }
    }
}

/// The last miss, in memory only.
final class CompatBreadcrumbs: @unchecked Sendable {
    static let shared = CompatBreadcrumbs()

    struct Entry: Equatable, Sendable {
        let miss: CompatMiss
        let at: Date
    }

    /// How long a repeat of the same miss is ignored, by the log and by "Last
    /// problem" alike: a read every five minutes that keeps missing would
    /// otherwise fill the log and keep the line forever "just now".
    static let quietFor: TimeInterval = 600

    private let lock = NSLock()
    private var entry: Entry?
    private let now: @Sendable () -> Date
    private let emit: @Sendable (String) -> Void

    /// `emit` is where the log line goes; tests replace it.
    init(now: @escaping @Sendable () -> Date = { Date() },
         emit: @escaping @Sendable (String) -> Void = { text in log.notice("\(text, privacy: .public)") }) {
        self.now = now
        self.emit = emit
    }

    /// The latest miss, or nil if none has happened since Capsid started.
    var last: Entry? {
        lock.lock(); defer { lock.unlock() }
        return entry
    }

    /// Keeps `miss` as the latest and logs it at notice level, unless it is
    /// the same miss as the latest and that was less than ten minutes ago: then
    /// neither happens, so a read that keeps missing is one line in the log and
    /// one "Last problem" whose time is the first miss's, not a line that
    /// restarts every five minutes.
    func record(_ miss: CompatMiss) {
        let moment = now()
        lock.lock()
        let repeated = entry.map { $0.miss == miss && moment.timeIntervalSince($0.at) < Self.quietFor } ?? false
        if !repeated { entry = Entry(miss: miss, at: moment) }
        lock.unlock()
        if !repeated {
            emit("Claude Science may have changed: \(miss.feature.shortTitle): \(miss.phrase)")
        }
    }

    /// "Last problem: Close Other Tabs, 12 minutes ago: the tab strip has no
    /// toolbar of open panels", or nil when there has been none.
    func line() -> String? {
        guard let entry = last else { return nil }
        return Self.line(for: entry, now: now())
    }

    static func line(for entry: Entry, now: Date) -> String {
        "Last problem: \(entry.miss.feature.shortTitle), \(age(of: entry.at, now: now)): \(entry.miss.phrase)"
    }

    /// "just now", "1 minute ago", "12 minutes ago", "3 hours ago", "2 days ago".
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        func plural(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s") ago" }
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return plural(seconds / 60, "minute")
        case ..<86_400: return plural(seconds / 3600, "hour")
        default: return plural(seconds / 86_400, "day")
        }
    }
}
