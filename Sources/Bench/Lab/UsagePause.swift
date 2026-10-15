// UsagePause.swift — sessions held by a used-up plan limit (DESIGN.md, Usage
// pause). When a limit runs out mid-turn, Claude Science keeps the session
// `processing` but sends nothing until the limit starts over ("Sending
// messages is paused — resumes at 3:40 PM"). It says so only over its own
// page's socket, so Bench reads it the way that page checks it: the running
// sessions have gone quiet, and a fresh read of the plan says a limit is used
// up with no extra usage to carry on. Then the panel stops its specimen, the
// menu bar and the toolbar say "Paused", and the phone shows when it resumes;
// the first write from a session, or the limit starting over, ends it.
import Combine
import Foundation

/// Running sessions waiting for a plan limit to start over.
struct UsagePause: Equatable, Sendable {
    let limit: PlanLimit.Kind
    /// When the limit starts over, when Claude Science says.
    let until: Date?

    /// How long the running sessions must have written nothing before a
    /// used-up limit is read as holding them: a turn between writes is shorter.
    static let quiet: TimeInterval = 20

    /// Paused when something runs, nothing has been written for `quiet`, and a
    /// limit is used up. Pure, for the tests.
    static func decide(running: Bool, lastWrite: Date?, now: Date, reached: PlanLimit?) -> UsagePause? {
        guard running, let reached, let lastWrite, now.timeIntervalSince(lastWrite) >= quiet else { return nil }
        return UsagePause(limit: reached.kind, until: reached.resetsAt)
    }

    /// "Resumes at 3:40 PM", "Resumes tomorrow at 9:00 AM", or, with no time
    /// from Claude Science, "Resumes when your limit resets".
    func sentence(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let until else { return "Resumes when your limit resets" }
        let time = until.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(until, inSameDayAs: now) { return "Resumes at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
            return "Resumes tomorrow at \(time)"
        }
        return "Resumes \(until.formatted(.dateTime.weekday(.wide))) at \(time)"
    }
}

/// Watches the running sessions and the plan, and publishes the pause.
@MainActor
final class UsagePauseModel: ObservableObject {
    static let shared = UsagePauseModel()

    @Published private(set) var pause: UsagePause?

    /// How often, while quiet or paused, the plan is read again: Claude
    /// Science's own page checks every minute while it shows the pause.
    static let recheck: TimeInterval = 60
    /// Below this much used of every limit, quiet sessions aren't a pause
    /// worth reading the plan for (a long tool run writes nothing either).
    static let nearLimit = 85

    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Task<Void, Never>?

    func start() {
        // A demo can show a made-up pause (`-demoUsagePause YES`), an hour long.
        if Demo.mode != nil {
            if UserDefaults.standard.bool(forKey: "demoUsagePause") {
                pause = UsagePause(limit: .session, until: Date().addingTimeInterval(3_600))
            }
            return
        }
        guard subscriptions.isEmpty else { return }
        let lab = LabModel.shared, usage = PlanUsageModel.shared
        // Every read of the sessions (a write moves `updatedAt`), every change
        // of who runs, and every read of the plan.
        lab.reads.$sessions.map { _ in () }
            .merge(with: lab.$working.map { _ in () })
            .merge(with: usage.$limits.map { _ in () })
            .merge(with: usage.$extra.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.evaluate() }
            .store(in: &subscriptions)
    }

    private func evaluate(now: Date = Date()) {
        let running = LabModel.shared.workingAsRead
        let usage = PlanUsageModel.shared
        let lastWrite = running.map(\.updatedAt).max()
        let quietFor = lastWrite.map { now.timeIntervalSince($0) } ?? 0
        // Quiet long enough to wonder, and the plan near or past a limit (or
        // not known): read it again, at most once a minute.
        if !running.isEmpty, quietFor >= UsagePause.quiet,
           usage.limits.isEmpty || usage.limits.contains(where: { $0.usedPercent >= Self.nearLimit }) {
            usage.readIfOlder(than: Self.recheck)
        }
        let next = UsagePause.decide(running: !running.isEmpty, lastWrite: lastWrite, now: now,
                                     reached: usage.limitReached(now: now))
        if next != pause { pause = next }
        schedule(running: !running.isEmpty, quietFor: quietFor)
    }

    /// Looks again when the quiet would turn into a pause, and every minute
    /// while quiet or paused; nothing while nothing runs.
    private func schedule(running: Bool, quietFor: TimeInterval) {
        timer?.cancel()
        guard running else { timer = nil; return }
        let wait = quietFor < UsagePause.quiet ? UsagePause.quiet - quietFor + 1 : Self.recheck
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }
}
