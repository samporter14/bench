// LabInsights.swift — what the panel and the cards say about a session beyond
// its status: how far through its plan it is, what the reviewer found, and a
// note Claude sent while it worked (DESIGN.md, Lab → Plan progress, Reviewer
// counts, Mid-run notes; since 1.0).
//
// The panel says which running sessions are on screen (`showing(running:)`) and
// which finished one a card is up for (`wantReviewers(for:)`); this decides
// whether and when to read, and keeps the answers in memory only, for as long
// as the session is on screen. Three reads, each projected in the page so that
// Swift sees only what the panel draws:
//
//  - `progress`: `Remote/InsightReader.swift`, the plan's step n of m and, when
//    it is unambiguous, one step title. Per running session on screen, at least
//    15 s apart.
//  - `reviewers`: the same file, four counts. One read for each finished
//    session (and again if the session ran since: its `updatedAt` moved).
//  - `notes`: a `send_user_message` call in the session's transcript, found by
//    the history reader's tail read (`WebContainer.readHistory`, the newest
//    page) at most every 30 s per running session on screen. Only rows that
//    arrived after the session was first seen: a note sent before Capsid
//    looked is never offered.
//
// All three are off with "Show plans, questions and requests on the card" (or
// the cards), as the failure card's reason is, off in a demo, and wait for the
// page. One read is in flight at a time, across sessions and kinds. Nothing is
// logged but the kind of an answer (at debug level), and nothing is saved: what
// was read goes when the session leaves the screen, the setting goes off, or
// Capsid quits.
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "insights")

// MARK: What the panel is given

/// How far through its plan a running session is: "Step 4 of 6 · Check against
/// published screens" (DESIGN.md, 1.0 spikes, S3). `step` is the page's own
/// number, `min(done + 1, total)` with `done` the steps completed or skipped;
/// the title comes only when exactly one step is in progress, it is the plan's
/// alone, and it is step `step`.
struct PlanProgress: Equatable, Sendable {
    /// The "n" of "Step n of m".
    let step: Int
    let total: Int
    /// The step in progress, as one line of at most 200 characters.
    let title: String?

    init(step: Int, total: Int, title: String? = nil) {
        self.step = step
        self.total = total
        self.title = title
    }

    /// "Step 4 of 6 · Check against published screens", or "Step 4 of 6".
    var line: String {
        guard let title, !title.isEmpty else { return "Step \(step) of \(total)" }
        return "Step \(step) of \(total) · \(title)"
    }

    /// Steps done over steps, 0 to 1, for the bar.
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(step - 1) / Double(total)))
    }
}

/// What the reviewer found in a finished session (DESIGN.md, 1.0 spikes, S4).
struct ReviewerCounts: Equatable, Sendable {
    /// Findings still standing: `fail` or `warn`, open, claimed, or left
    /// unaddressed when the turn ended and not withdrawn.
    let standing: Int
    /// Findings that were fixed.
    let fixed: Int
    /// Reviews under way now.
    let running: Int
    /// Reviews that finished.
    let reviews: Int

    init(standing: Int, fixed: Int, running: Int, reviews: Int) {
        self.standing = standing
        self.fixed = fixed
        self.running = running
        self.reviews = reviews
    }

    /// "Reviewer: 2 findings", "Reviewer: 1 finding" or "Reviewer: no
    /// findings"; nil when no review ran (or one is under way and nothing
    /// stands yet).
    var line: String? {
        if standing > 0 { return "Reviewer: \(standing) finding\(standing == 1 ? "" : "s")" }
        return reviews > 0 ? "Reviewer: no findings" : nil
    }
}

/// A note Claude sent the user while it worked (`send_user_message`).
struct MidRunNote: Equatable, Sendable, Identifiable {
    /// `<session id>#<row>`: the row of the session's history the note is in.
    let id: String
    let sessionID: String
    /// The note, plain text of at most 300 characters.
    let text: String
    /// When it was sent, when that is known. The history carries no time for
    /// a note, so a note read from it has none.
    let at: Date?

    init(id: String, sessionID: String, text: String, at: Date? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.text = text
        self.at = at
    }
}

/// A note as the card shows it: plain text, one cut.
enum NoteText {
    /// A note is at most this many characters, an ellipsis included.
    static let limit = 300

    /// The note's text with control, invisible and direction-changing
    /// characters gone, line breaks as `\n`, trailing spaces gone, a run of
    /// blank lines one, no blank line at either end, and cut at `limit`
    /// characters. Nil when nothing is left. Markdown stays as written.
    static func clean(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in raw.unicodeScalars {
            defer { previous = scalar }
            switch scalar.value {
            case 0x0A:
                if previous?.value == 0x0D { continue }
                scalars.append("\n")
            case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                scalars.append("\n")
            case 0x09:
                scalars.append(" ")
            default:
                if !isNoise(scalar) { scalars.append(scalar) }
            }
        }
        var lines: [String] = []
        for piece in String(scalars).split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(piece)
            while line.last?.isWhitespace == true { line.removeLast() }
            if line.isEmpty, lines.last?.isEmpty != false { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let text = lines.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard text.count > limit else { return text }
        return text.prefix(limit - 1).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// A control, format (zero-width, direction marks), private-use or
    /// unassigned character: nothing a reader should see in a note.
    private static func isNoise(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned: true
        default: false
        }
    }
}

// MARK: Deciding when to read

@MainActor
final class LabInsights: ObservableObject {
    static let shared = LabInsights(dependencies: .live())

    /// Plan progress is read for a session no sooner than this after the last
    /// read of it began.
    static let progressInterval: TimeInterval = 15
    /// A session whose last answer was that it has no plan to follow (no
    /// approved plan, no phases, or every step done) is asked again no sooner
    /// than this: such an answer only changes when a plan is approved, which
    /// takes the session off the running list and back, and that starts again.
    static let noPlanInterval: TimeInterval = 60
    /// A session that comes back onto the running list after its last answer
    /// was "the plan isn't approved" is probably a plan that was just approved
    /// (a session waiting for approval is not running): it is read this soon
    /// after its last read, not 15 s.
    static let approvalFloor: TimeInterval = 5
    /// Its transcript is looked at for a new note no sooner than this.
    static let noteInterval: TimeInterval = 30
    /// The most sessions on screen that are followed, in the order given.
    static let maxFollowed = 8
    /// The most unseen notes kept, newest first.
    static let maxNotes = 20
    /// The most notes remembered as seen, and finished sessions remembered as
    /// read.
    static let maxRemembered = 500
    /// A page that isn't ready is looked at again after this long.
    static let notReadyRetry: TimeInterval = 5
    /// Read times older than this, of sessions no longer on screen, are dropped.
    static let remembersReadsFor: TimeInterval = 600

    /// Whether anything may be read: "Show plans, questions and requests on
    /// the card" and "Show a card" are both on, as for the failure card's
    /// reason (the first is greyed out while the second is off). Plan
    /// progress is a line on the panel, but it is read from the same plan and
    /// under the same switch, so a Mac that shows no plans reads none.
    nonisolated static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: SettingsKey.showPlansOnCard) && defaults.bool(forKey: SettingsKey.showCards)
    }

    /// Everything that reaches outside, so tests can stand in for it.
    struct Dependencies {
        /// "Show plans, questions and requests on the card" and "Show a card"
        /// are on (the failure card's reason is read under the same two).
        var isEnabled: @MainActor @Sendable () -> Bool
        /// The page is up, so its API can be called.
        var isReady: @MainActor @Sendable () -> Bool
        /// A demo runs: nothing is read.
        var isDemo: @MainActor @Sendable () -> Bool
        var now: @MainActor @Sendable () -> Date
        /// Waits; cancelled when the wait is no longer wanted.
        var sleep: @MainActor @Sendable (Duration) async -> Void
        /// `WebContainer.readPlanProgress(frameID, nonce:)`.
        var readProgress: @MainActor @Sendable (String, String) async throws -> PlanProgressRead
        /// `WebContainer.readReviewerCounts(frameID, nonce:)`.
        var readReviewers: @MainActor @Sendable (String, String) async throws -> ReviewerRead
        /// `WebContainer.readHistory(frameID, before: nil, knownTotal:, nonce:)`: the newest page.
        var readHistory: @MainActor @Sendable (String, Int?, String) async throws -> RemoteBrowser.HistoryRead
        /// Where an answer that isn't what Capsid reads is noted.
        var breadcrumbs: CompatBreadcrumbs = .shared

        static func live() -> Dependencies {
            Dependencies(
                isEnabled: { LabInsights.isEnabled(in: .standard) },
                isReady: { WebContainer.shared.status == .ready },
                isDemo: { Demo.mode != nil },
                now: { Date() },
                sleep: { try? await Task.sleep(for: $0) },
                readProgress: { try await WebContainer.shared.readPlanProgress($0, nonce: $1) },
                readReviewers: { try await WebContainer.shared.readReviewerCounts($0, nonce: $1) },
                readHistory: { try await WebContainer.shared.readHistory($0, before: nil, knownTotal: $1, nonce: $2) })
        }
    }

    /// By session id; only sessions asked for in `showing(running:)`, and only
    /// while they are on screen.
    @Published private(set) var progress: [String: PlanProgress] = [:]
    /// By session id; the finished sessions `wantReviewers(for:)` was asked for.
    @Published private(set) var reviewers: [String: ReviewerCounts] = [:]
    /// Notes not yet shown or dismissed, newest first.
    @Published private(set) var notes: [MidRunNote] = []

    private let dependencies: Dependencies

    /// What is on screen, running, in the order the panel gave.
    private var onScreen: [SessionStatus] = []
    /// When each session's last read of that kind began.
    private var lastProgress: [String: Date] = [:]
    private var lastNotes: [String: Date] = [:]
    /// The sessions whose last progress answer was "no plan to follow".
    private var withoutPlan: Set<String> = []
    /// The last answer that was "nothing to show", by session: what a session
    /// that comes back was last waiting for. Kept while it is off the screen.
    private var lastIdle: [String: PlanProgressWhy] = [:]
    /// Sessions that came back after waiting for a plan to be approved.
    private var comeBack: Set<String> = []
    /// Where a session's transcript was when it was first looked at, and how
    /// long it was at the last look.
    private struct NoteWatch {
        var baseline: Int?
        var total: Int?
    }
    private var watches: [String: NoteWatch] = [:]
    /// Notes shown or dismissed (and dropped from the list), by id, oldest first.
    private var seen: [String] = []
    private var seenSet: Set<String> = []
    /// Finished sessions waiting for their reviewer read, and the `updatedAt`
    /// each was last read for.
    private var reviewerQueue: [SessionStatus] = []
    private var reviewerAsked: [String: Date] = [:]
    private var reviewerOrder: [String] = []

    private enum Job {
        case progress(SessionStatus)
        case notes(SessionStatus)
        case reviewers(SessionStatus)
    }

    /// The one read in flight, if any, and the wait for the next one due.
    private var inFlight: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var timerDue: Date?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: What the panel says

    /// The panel (and the activity list) says which running sessions are on
    /// screen. Reads at most every 15 s per session, one in flight, only while
    /// the page is ready, and only while "Show plans, questions and requests
    /// on the card" is on. A session that leaves the list loses its progress
    /// and its place in the transcript. One that comes back is read when its
    /// 15 s are up, or 5 s after its last read if it was last found to have
    /// no approved plan: a session waiting for approval is not running, so
    /// that is a plan that was just approved.
    func showing(running sessions: [SessionStatus]) {
        guard !dependencies.isDemo() else { return }
        guard dependencies.isEnabled() else { return reset() }
        var seenIDs: Set<String> = []
        let running = sessions.filter { $0.state == .running && seenIDs.insert($0.id).inserted }.prefix(Self.maxFollowed)
        let ids = Set(running.map(\.id))
        let before = Set(onScreen.map(\.id))
        comeBack = comeBack.intersection(ids).union(ids.subtracting(before).filter { lastIdle[$0] == .notApproved })
        let kept = progress.filter { ids.contains($0.key) }
        if kept.count != progress.count { progress = kept }
        watches = watches.filter { ids.contains($0.key) }
        withoutPlan = withoutPlan.intersection(ids)
        onScreen = Array(running)
        pump()
    }

    /// A finished card is up for this session: one projected reviewer read
    /// (gated the same way), and no second for the same finish. A session
    /// that ran again since (its `updatedAt` moved) is read again.
    func wantReviewers(for session: SessionStatus) {
        guard !dependencies.isDemo(), dependencies.isEnabled(), session.state == .finished else { return }
        guard reviewerAsked[session.id] != session.updatedAt else { return }
        guard dependencies.isReady() else { return }
        reviewerAsked[session.id] = session.updatedAt
        reviewerOrder.removeAll { $0 == session.id }
        reviewerOrder.append(session.id)
        while reviewerOrder.count > Self.maxRemembered {
            let oldest = reviewerOrder.removeFirst()
            reviewerAsked[oldest] = nil
            reviewers[oldest] = nil
        }
        reviewerQueue.removeAll { $0.id == session.id }
        reviewerQueue.append(session)
        pump()
    }

    /// A note card was shown or dismissed: it isn't offered again.
    func noteSeen(_ id: String) {
        notes.removeAll { $0.id == id }
        remember(seen: id)
    }

    /// `--demo`: made-up values, in place of reads (a demo reads nothing).
    func demo(progress: [String: PlanProgress] = [:], reviewers: [String: ReviewerCounts] = [:], notes: [MidRunNote] = []) {
        self.progress = progress
        self.reviewers = reviewers
        self.notes = notes
    }

    /// Waits until the read in flight is done, and any that follows at once.
    /// For tests.
    func settled() async {
        while let task = inFlight { await task.value }
    }

    // MARK: Deciding

    /// Starts the read that is due, if none is in flight; else waits for the
    /// next one to come due.
    private func pump() {
        guard !dependencies.isDemo() else { return }
        guard dependencies.isEnabled() else { return reset() }
        guard inFlight == nil else { return }
        let now = dependencies.now()
        guard dependencies.isReady() else {
            if !onScreen.isEmpty || !reviewerQueue.isEmpty { arm(at: now.addingTimeInterval(Self.notReadyRetry), now: now) }
            return
        }
        forgetOldReads(before: now)
        if !reviewerQueue.isEmpty {
            start(.reviewers(reviewerQueue.removeFirst()), at: now)
            return
        }
        var next: (due: Date, job: Job)?
        func consider(_ due: Date, _ job: Job) {
            if next == nil || due < next!.due { next = (due, job) }
        }
        for session in onScreen {
            let wait = comeBack.contains(session.id) ? Self.approvalFloor
                : withoutPlan.contains(session.id) ? Self.noPlanInterval : Self.progressInterval
            consider(lastProgress[session.id].map { $0.addingTimeInterval(wait) } ?? .distantPast, .progress(session))
            consider(lastNotes[session.id].map { $0.addingTimeInterval(Self.noteInterval) } ?? .distantPast, .notes(session))
        }
        guard let next else { return }
        if next.due <= now { start(next.job, at: now) } else { arm(at: next.due, now: now) }
    }

    /// Wakes `pump` at `due`, unless a wake-up at or before then is already
    /// waiting: the panel says what is on screen as often as it redraws, and
    /// that must not make a new wait each time.
    private func arm(at due: Date, now: Date) {
        if timer != nil, let timerDue, timerDue <= due { return }
        timer?.cancel()
        timerDue = due
        let wait = dependencies.sleep
        let seconds = max(0.05, due.timeIntervalSince(now))
        timer = Task { [weak self] in
            await wait(.seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.timer = nil
            self.timerDue = nil
            self.pump()
        }
    }

    private func start(_ job: Job, at now: Date) {
        // The read in hand ends in a `pump`, which waits again if need be.
        timer?.cancel()
        timer = nil
        timerDue = nil
        switch job {
        case .progress(let session):
            lastProgress[session.id] = now
            comeBack.remove(session.id)
        case .notes(let session): lastNotes[session.id] = now
        case .reviewers: break
        }
        inFlight = Task { [weak self] in
            guard let self else { return }
            switch job {
            case .progress(let session): await self.readProgress(of: session)
            case .notes(let session): await self.readNotes(of: session)
            case .reviewers(let session): await self.readReviewers(of: session)
            }
            self.inFlight = nil
            self.pump()
        }
    }

    /// Everything off: the setting went off, or the cards did.
    private func reset() {
        timer?.cancel()
        timer = nil
        timerDue = nil
        inFlight?.cancel()
        onScreen = []
        lastProgress = [:]
        lastNotes = [:]
        withoutPlan = []
        lastIdle = [:]
        comeBack = []
        watches = [:]
        reviewerQueue = []
        reviewerAsked = [:]
        reviewerOrder = []
        if !progress.isEmpty { progress = [:] }
        if !reviewers.isEmpty { reviewers = [:] }
        if !notes.isEmpty { notes = [] }
    }

    private func forgetOldReads(before now: Date) {
        let live = Set(onScreen.map(\.id))
        let cutoff = now.addingTimeInterval(-Self.remembersReadsFor)
        lastProgress = lastProgress.filter { live.contains($0.key) || $0.value > cutoff }
        lastNotes = lastNotes.filter { live.contains($0.key) || $0.value > cutoff }
        lastIdle = lastIdle.filter { live.contains($0.key) || lastProgress[$0.key] != nil }
    }

    private func isShowing(_ id: String) -> Bool {
        onScreen.contains { $0.id == id }
    }

    private func remember(seen id: String) {
        guard seenSet.insert(id).inserted else { return }
        seen.append(id)
        while seen.count > Self.maxRemembered { seenSet.remove(seen.removeFirst()) }
    }

    // MARK: Reading

    private func nonce() -> String { UUID().uuidString }

    private func readProgress(of session: SessionStatus) async {
        let id = session.id
        guard let read = try? await dependencies.readProgress(id, nonce()),
              !Task.isCancelled, isShowing(id), dependencies.isEnabled() else { return }
        func set(_ value: PlanProgress?) {
            if progress[id] != value { progress[id] = value }
        }
        switch read {
        case .progress(let value, let facts):
            set(facts.running ? value : nil)
            withoutPlan.remove(id)
            lastIdle[id] = nil
            if facts.unknown > 0 { dependencies.breadcrumbs.record(.progressStatusNotUnderstood) }
        case .idle(let why, let facts):
            set(nil)
            lastIdle[id] = why
            // Waiting for a first status is a state that changes; the others change with a new plan.
            if why == .noStatuses { withoutPlan.remove(id) } else { withoutPlan.insert(id) }
            if why == .planMissing { dependencies.breadcrumbs.record(.progressTreeWithoutPlan) }
            if facts.unknown > 0 { dependencies.breadcrumbs.record(.progressStatusNotUnderstood) }
        case .unreadable:
            set(nil)
            withoutPlan.insert(id)
            lastIdle[id] = nil
            dependencies.breadcrumbs.record(.progressTreeNotUnderstood)
        case .missing:
            set(nil)
            withoutPlan.insert(id)
            lastIdle[id] = nil
        case .lost, .tooBig, .cancelled:
            // Not an answer: what was shown stays until the next read.
            break
        }
        log.debug("Plan progress read: \(read.kind, privacy: .public)")
    }

    private func readReviewers(of session: SessionStatus) async {
        guard let read = try? await dependencies.readReviewers(session.id, nonce()),
              !Task.isCancelled, dependencies.isEnabled() else { return }
        switch read {
        case .counts(let counts):
            guard reviewerAsked[session.id] != nil else { return }
            if reviewers[session.id] != counts { reviewers[session.id] = counts }
        case .unreadable:
            dependencies.breadcrumbs.record(.reviewerAnswerNotUnderstood)
        case .lost, .missing, .tooBig, .cancelled:
            break
        }
        log.debug("Reviewer read: \(read.kind, privacy: .public)")
    }

    private func readNotes(of session: SessionStatus) async {
        let id = session.id
        var watch = watches[id] ?? NoteWatch()
        guard let read = try? await dependencies.readHistory(id, watch.total, nonce()),
              !Task.isCancelled, isShowing(id), dependencies.isEnabled() else { return }
        switch read {
        case .same(let total):
            // As long as it was: nothing arrived. (A first look can't be this.)
            if watch.baseline == nil { watch.baseline = total }
            watch.total = total
        case .page(let page):
            if let baseline = watch.baseline {
                // A history that is shorter than it was (rolled back) starts the count again.
                watch.baseline = min(baseline, page.total)
                let fresh = newNotes(in: page, of: id, since: min(baseline, page.total))
                if !fresh.isEmpty {
                    notes.insert(contentsOf: fresh.reversed(), at: 0)
                    while notes.count > Self.maxNotes { remember(seen: notes.removeLast().id) }
                }
            } else {
                // The first look at this session: everything in it is old.
                watch.baseline = page.total
            }
            watch.total = page.total
        case .unreadable, .tooBig:
            break
        }
        watches[id] = watch
    }

    /// The notes on `page` that arrived after `baseline` rows and were neither
    /// shown nor dismissed nor already waiting, oldest first.
    private func newNotes(in page: HistoryPage, of sessionID: String, since baseline: Int) -> [MidRunNote] {
        var fresh: [MidRunNote] = []
        for case .toYou(let row, let text, _, _) in page.items where row >= baseline {
            let id = "\(sessionID)#\(row)"
            guard !seenSet.contains(id), !notes.contains(where: { $0.id == id }), !fresh.contains(where: { $0.id == id }),
                  let clean = NoteText.clean(text) else { continue }
            fresh.append(MidRunNote(id: id, sessionID: sessionID, text: clean))
        }
        return fresh
    }
}

private extension PlanProgressRead {
    /// What happened, in a word: never what was read.
    var kind: String {
        switch self {
        case .progress: "progress"
        case .idle(let why, _): "nothing to show (\(why.rawValue))"
        case .unreadable: "not understood"
        case .lost: "signed out"
        case .missing: "gone"
        case .tooBig: "too big"
        case .cancelled: "cancelled"
        }
    }
}

private extension ReviewerRead {
    var kind: String {
        switch self {
        case .counts: "counts"
        case .unreadable: "not understood"
        case .lost: "signed out"
        case .missing: "gone"
        case .tooBig: "too big"
        case .cancelled: "cancelled"
        }
    }
}
