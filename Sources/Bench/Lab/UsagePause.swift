// UsagePause.swift — sessions held by a used-up plan limit (DESIGN.md, Usage
// pause). When a limit runs out mid-turn, Claude Science keeps the session
// `processing` but sends nothing until the limit starts over ("Sending
// messages is paused — resumes at 3:40 PM"). It says so only over its own
// page's socket, which Bench doesn't open, so Bench infers it, session by
// session, from what it reads anyway:
//
// - the session's whole tree, sub-agents included, has written nothing for
//   `quiet` (`SessionStatus.activeAt`; a session without it is never quiet);
// - a read of the plan taken after that last write, and no older than
//   `evidence`, says a limit that holds every session is used up, by its
//   unrounded figure, with no extra usage left (`PlanUsageModel.limitReached`).
//
// It is an inference: a session running a long tool after the limit ran out
// reads as paused until it writes again. Then the panel stops its specimen,
// the menu bar and the toolbar say "Paused" once every working session is
// held, and the phone shows when it resumes. A session's next write ends its
// pause; the limit starting over, or a read saying there is room again,
// ends them all.
import Combine
import Foundation

/// The limit holding running sessions, and when it starts over.
struct UsagePause: Equatable, Sendable {
    let limit: PlanLimit.Kind
    /// When the limit starts over, when Claude Science says.
    let until: Date?

    /// How long a session's tree must have written nothing before a used-up
    /// limit is read as holding it: a turn between writes is shorter.
    static let quiet: TimeInterval = 20
    /// How old the plan's last good read may be and still say a session is
    /// paused: two of the minute's re-reads, and a little over. After two
    /// failed reads in a row Bench stops saying so, rather than go on from
    /// what it can no longer check.
    static let evidence: TimeInterval = 150
    /// A read saying there is room again ends a pause only when taken this
    /// long after the pause began, as Claude Science's own page waits 75 s
    /// before it believes one: a read just after may not have caught up.
    static let settle: TimeInterval = 75
    /// How often, while a session is quiet or held, the plan is read again:
    /// Claude Science's own page checks every minute while it shows the pause.
    static let recheck: TimeInterval = 60
    /// Below this much used of every limit that holds every session, quiet
    /// sessions aren't worth reading the plan for (a long tool run writes
    /// nothing either).
    static let nearLimit = 85

    /// "Resumes at 3:40 PM", "Resumes tomorrow at 9:00 AM", "Resumes Friday
    /// at …", "Resumes on Oct 22 at …", or, with no time from Claude
    /// Science, "Resumes when your limit resets". In `calendar`'s time zone
    /// and `locale`'s words.
    func sentence(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        guard let until else { return "Resumes when your limit resets" }
        if until <= now { return "Resumes shortly" }
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        timeStyle.timeZone = calendar.timeZone
        let time = until.formatted(timeStyle)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: until)).day ?? 0
        switch days {
        case ...0: return "Resumes at \(time)"
        case 1: return "Resumes tomorrow at \(time)"
        case 2...6:
            var weekday = Date.FormatStyle(locale: locale).weekday(.wide)
            weekday.timeZone = calendar.timeZone
            return "Resumes \(until.formatted(weekday)) at \(time)"
        default:
            var day = Date.FormatStyle(locale: locale).month(.abbreviated).day()
            day.timeZone = calendar.timeZone
            return "Resumes on \(until.formatted(day)) at \(time)"
        }
    }
}

/// The plan as last read, as the pause reads it.
struct PlanReading: Equatable, Sendable {
    var limits: [PlanLimit] = []
    var extra: PlanExtraUsage?
    /// When the last read that worked was taken; a failed one leaves it.
    var lastRead: Date?
}

/// A used-up limit that holds every session, and since when Bench has said so.
struct UsageHold: Equatable, Sendable {
    let pause: UsagePause
    let since: Date
}

/// What the pause watcher makes of one look.
struct UsagePauseDecision: Equatable, Sendable {
    /// The account-wide hold, while a recent enough read says so.
    var hold: UsageHold?
    /// The running sessions it holds now, by id.
    var held: [String: UsagePause] = [:]
    /// Read the plan again (bypassing Claude Science's cache) unless the
    /// last try is newer than this, when a read could settle it.
    var readIfOlder: TimeInterval?
    /// When to look again with nothing else changing; nil while nothing runs.
    var wake: TimeInterval?

    /// One look: pure, for the tests. `previous` is the last look's hold.
    static func make(running: [SessionStatus], plan: PlanReading, now: Date, previous: UsageHold?) -> Self {
        var decision = Self()
        guard !running.isEmpty else { return decision }

        // The hold, from a read no older than `evidence`.
        let recent = plan.lastRead.map { now.timeIntervalSince($0) <= UsagePause.evidence } ?? false
        if recent, let reached = PlanUsageModel.limitReached(plan.limits, extra: plan.extra, now: now) {
            decision.hold = UsageHold(pause: UsagePause(limit: reached.kind, until: reached.resetsAt),
                                      since: previous?.since ?? now)
        } else if recent, let previous, let lastRead = plan.lastRead,
                  previous.pause.until.map({ $0 > now }) ?? true,
                  lastRead < previous.since.addingTimeInterval(UsagePause.settle) {
            // Room again, by a read too soon after the pause began to trust.
            decision.hold = previous
        }

        // Each session: held when its tree is quiet and the hold was read after its last write.
        let near = Self.nearLimit(plan.limits)
        var quietest: TimeInterval?
        var wake: TimeInterval?
        for session in running {
            guard let active = session.activeAt else { continue }
            let quietFor = now.timeIntervalSince(active)
            guard quietFor >= UsagePause.quiet else {
                // Look again just after it would turn quiet.
                wake = min(wake ?? .infinity, UsagePause.quiet - quietFor + 1)
                continue
            }
            wake = min(wake ?? .infinity, UsagePause.recheck)
            if let hold = decision.hold, let lastRead = plan.lastRead, lastRead >= active {
                decision.held[session.id] = hold.pause
            }
            quietest = min(quietest ?? .infinity, quietFor)
        }
        // Quiet and near a limit (or limits unknown): read the plan, at once
        // when the last try is older than the latest quiet session's last
        // write, else at most once a minute.
        if let quietest, near || decision.hold != nil {
            decision.readIfOlder = min(UsagePause.recheck, quietest)
        }
        // While it holds any, look again just after the limit starts over.
        if !decision.held.isEmpty, let until = decision.hold?.pause.until {
            wake = min(wake ?? .infinity, max(1, until.timeIntervalSince(now) + 1))
        }
        decision.wake = wake
        return decision
    }

    /// Whether a limit that holds every session is near used up, or none is known.
    static func nearLimit(_ limits: [PlanLimit]) -> Bool {
        let holding = limits.filter(\.kind.holdsEverySession)
        return holding.isEmpty || holding.contains { $0.usedPercent >= UsagePause.nearLimit || $0.reached }
    }
}

/// Watches the running sessions and the plan, and publishes which sessions
/// a used-up limit holds.
@MainActor
final class UsagePauseModel: ObservableObject {
    static let shared = UsagePauseModel()

    /// The running sessions a used-up limit holds, by id; empty while none is.
    @Published private(set) var held: [String: UsagePause] = [:]

    /// What the watcher reads, and how it asks for a read of the plan.
    struct Inputs {
        /// Fires after the sessions as read, the working set or the plan change.
        var changes: AnyPublisher<Void, Never>
        /// The running sessions as last read, `activeAt` included.
        var running: @MainActor () -> [SessionStatus]
        var plan: @MainActor () -> PlanReading
        /// Read the plan again unless the last try is newer than the age.
        var read: @MainActor (_ olderThan: TimeInterval, _ now: Date) -> Void

        /// LabModel's sessions and PlanUsageModel's reads.
        @MainActor static func live() -> Inputs {
            let lab = LabModel.shared, usage = PlanUsageModel.shared
            // @Published says so before the value changes: hop to the main
            // queue, after which the models hold the new values.
            let changes = lab.reads.$sessions.map { _ in () }
                .merge(with: lab.$working.map { _ in () })
                .merge(with: usage.$limits.map { _ in () })
                .merge(with: usage.$extra.map { _ in () })
                .merge(with: usage.$lastRead.map { _ in () })
                .merge(with: usage.$failure.map { _ in () })
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
            return Inputs(changes: changes,
                          running: { lab.workingAsRead },
                          plan: { PlanReading(limits: usage.limits, extra: usage.extra, lastRead: usage.lastRead) },
                          read: { age, now in usage.readIfOlder(than: age, now: now) })
        }
    }

    /// Runs `action` after a wait, until the returned value is cancelled.
    typealias Schedule = @MainActor (_ after: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable

    private let now: () -> Date
    private let schedule: Schedule
    private var inputs: Inputs?
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: AnyCancellable?
    private(set) var hold: UsageHold?

    /// The app's uses the clock and a sleeping task; tests pass their own.
    init(now: @escaping () -> Date = { Date() }, schedule: @escaping Schedule = UsagePauseModel.sleep) {
        self.now = now
        self.schedule = schedule
    }

    /// The pause holding the held sessions: one limit holds them all.
    var pause: UsagePause? { held.values.first }

    /// The pause holding this session, if one does.
    func pause(for id: String) -> UsagePause? { held[id] }

    /// The first of `sessions` that isn't held, else the first: what the
    /// panel puts on top, so a session still working isn't hidden behind
    /// one that waits.
    func head(of sessions: [SessionStatus]) -> SessionStatus? {
        sessions.first { held[$0.id] == nil } ?? sessions.first
    }

    /// Whether there are sessions and every one is held: only then is
    /// nothing happening, and the menu bar and toolbar stand still.
    func holdsAll(_ sessions: [SessionStatus]) -> Bool {
        !sessions.isEmpty && sessions.allSatisfy { held[$0.id] != nil }
    }

    func start(_ inputs: Inputs? = nil) {
        // A demo can show a made-up pause (`-demoUsagePause YES`), an hour
        // long, on every working session.
        if Demo.mode != nil, inputs == nil {
            guard UserDefaults.standard.bool(forKey: "demoUsagePause"), subscriptions.isEmpty else { return }
            let pause = UsagePause(limit: .session, until: now().addingTimeInterval(3_600))
            LabModel.shared.$working
                .sink { [weak self] working in
                    self?.held = Dictionary(working.map { ($0.id, pause) }, uniquingKeysWith: { first, _ in first })
                }
                .store(in: &subscriptions)
            return
        }
        guard subscriptions.isEmpty else { return }
        let inputs = inputs ?? .live()
        self.inputs = inputs
        inputs.changes
            .sink { [weak self] in self?.evaluate() }
            .store(in: &subscriptions)
        evaluate()
    }

    /// One look: decides, asks for a read when one would settle it, and
    /// looks again when the time alone could change the answer.
    func evaluate() {
        guard let inputs else { return }
        let now = now()
        let decision = UsagePauseDecision.make(running: inputs.running(), plan: inputs.plan(), now: now, previous: hold)
        hold = decision.hold
        if decision.held != held { held = decision.held }
        if let age = decision.readIfOlder { inputs.read(age, now) }
        timer?.cancel()
        timer = decision.wake.map { wait in
            schedule(wait) { [weak self] in self?.evaluate() }
        }
    }

    /// The app's schedule: a task that sleeps, with a little tolerance.
    static func sleep(after wait: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(2))
            guard !Task.isCancelled else { return }
            action()
        }
        return AnyCancellable { task.cancel() }
    }
}
