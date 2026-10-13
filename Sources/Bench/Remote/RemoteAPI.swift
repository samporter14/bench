// RemoteAPI.swift — what the phone is told (DESIGN.md, `/api/state` and
// `/api/sessions/<id>`, version 1). The builders are pure functions of plain
// inputs, tested with made-up sessions; `RemoteFeed` watches the models and
// says when the state changed, for the events stream.
//
// Titles and project names are the user's own and go only to their paired
// devices. Nothing a session says is read: `messages` stays empty in Phase 1.
import Combine
import Foundation

@MainActor
enum RemoteAPI {
    static let version = 1

    // MARK: `/api/state`

    /// Everything `/api/state` is built from, as plain values.
    struct Input {
        var bench: String
        var now: Date
        var problem: ScienceError?
        /// Sessions parked on the user, as `LabModel.waiting`.
        var waiting: [SessionStatus]
        var snoozed: [SnoozedReminder]
        /// The sessions of the failure cards.
        var failed: [SessionStatus]
        var working: [SessionStatus]
        var recent: [LabEvent]
        var limits: [PlanLimit]
        var forecasts: [PlanLimit.Kind: Forecast]
    }

    struct State: Encodable, Equatable {
        let version: Int
        let bench: String
        let updatedAt: Date
        let problem: String?
        let needsYou: [NeedsYou]
        let failed: [Failed]
        let working: [Working]
        let recent: [Recent]
        let usage: Usage?

        private enum CodingKeys: String, CodingKey {
            case version, bench, updatedAt, problem, needsYou, failed, working, recent, usage
        }

        // Written out so a missing value is `null`, as the spec shows,
        // rather than left out.
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(version, forKey: .version)
            try c.encode(bench, forKey: .bench)
            try c.encode(updatedAt, forKey: .updatedAt)
            try c.encode(problem, forKey: .problem)
            try c.encode(needsYou, forKey: .needsYou)
            try c.encode(failed, forKey: .failed)
            try c.encode(working, forKey: .working)
            try c.encode(recent, forKey: .recent)
            try c.encode(usage, forKey: .usage)
        }

        /// The same state at another moment: for telling a real change from
        /// a tick.
        func at(_ date: Date) -> State {
            State(version: version, bench: bench, updatedAt: date, problem: problem, needsYou: needsYou,
                  failed: failed, working: working, recent: recent, usage: usage)
        }
    }

    struct NeedsYou: Encodable, Equatable {
        let id: String
        let title: String
        let project: String
        let reason: String
        let sentence: String
        let since: Date
        let snooze: Snooze?

        private enum CodingKeys: String, CodingKey { case id, title, project, reason, sentence, since, snooze }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encode(project, forKey: .project)
            try c.encode(reason, forKey: .reason)
            try c.encode(sentence, forKey: .sentence)
            try c.encode(since, forKey: .since)
            try c.encode(snooze, forKey: .snooze)
        }
    }

    /// A card put off with Later: until when, or until the focus session ends.
    struct Snooze: Encodable, Equatable {
        let until: Date?
        let afterFocus: Bool

        private enum CodingKeys: String, CodingKey { case until, afterFocus }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(until, forKey: .until)
            try c.encode(afterFocus, forKey: .afterFocus)
        }
    }

    struct Failed: Encodable, Equatable {
        let id: String
        let title: String
        let project: String
        let since: Date
    }

    struct Working: Encodable, Equatable {
        let id: String
        let title: String
        let project: String
        let startedAt: Date?

        private enum CodingKeys: String, CodingKey { case id, title, project, startedAt }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encode(project, forKey: .project)
            try c.encode(startedAt, forKey: .startedAt)
        }
    }

    struct Recent: Encodable, Equatable {
        /// "needsInput", "failed" or "finished".
        let kind: String
        let id: String
        let title: String
        let project: String
        let at: Date
        let line: String
    }

    struct Usage: Encodable, Equatable {
        let limits: [Limit]
    }

    struct Limit: Encodable, Equatable {
        let name: String
        let usedPercent: Int
        let resetsAt: Date?
        /// "At this pace: limit around 3:40 PM", when the pace says anything.
        let pace: String?

        private enum CodingKeys: String, CodingKey { case name, usedPercent, resetsAt, pace }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(usedPercent, forKey: .usedPercent)
            try c.encode(resetsAt, forKey: .resetsAt)
            try c.encode(pace, forKey: .pace)
        }
    }

    static func state(_ input: Input) -> State {
        let snoozed = Dictionary(input.snoozed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let needsYou = input.waiting.map { session in
            let reason = session.waitingReason ?? .other
            return NeedsYou(id: session.id, title: session.displayTitle, project: session.projectName,
                            reason: reason.rawValue, sentence: reason.sentence, since: session.updatedAt,
                            snooze: snoozed[session.id].map { Snooze(until: $0.due, afterFocus: $0.due == nil) })
        }
        let failed = input.failed.map {
            Failed(id: $0.id, title: $0.displayTitle, project: $0.projectName, since: $0.updatedAt)
        }
        let working = input.working.map {
            Working(id: $0.id, title: $0.displayTitle, project: $0.projectName, startedAt: $0.startedAt)
        }
        // A download has no session, and its file name is no business of
        // the phone's: saved files stay on the Mac.
        let recent = input.recent.compactMap { event -> Recent? in
            guard let session = event.session, let kind = kindName(event.kind) else { return nil }
            return Recent(kind: kind, id: session.id, title: session.displayTitle, project: session.projectName,
                          at: event.at, line: ActivityList.line(for: event.kind))
        }
        let limits = input.limits.map { limit in
            Limit(name: name(limit.kind), usedPercent: limit.usedPercent, resetsAt: limit.resetsAt,
                  pace: input.forecasts[limit.kind]?.line(now: input.now))
        }
        return State(version: version, bench: input.bench, updatedAt: input.now, problem: input.problem?.label,
                     needsYou: needsYou, failed: failed, working: working, recent: recent,
                     usage: limits.isEmpty ? nil : Usage(limits: limits))
    }

    private static func kindName(_ kind: LabEvent.Kind) -> String? {
        switch kind {
        case .needsInput: "needsInput"
        case .failed: "failed"
        case .finished: "finished"
        case .saved: nil
        }
    }

    /// The limit's name on the phone.
    static func name(_ kind: PlanLimit.Kind) -> String {
        switch kind {
        case .session: "5-hour"
        case .week: "Weekly"
        case .weekOpus: "Weekly Opus"
        case .weekSonnet: "Weekly Sonnet"
        }
    }

    // MARK: `/api/sessions/<id>`

    struct Session: Encodable, Equatable {
        let version: Int
        let id: String
        let title: String
        let project: String
        let state: String
        let reason: String?
        let sentence: String
        let startedAt: Date?
        let updatedAt: Date
        let plan: Plan?
        /// Empty in Phase 1: what a session says needs its own research.
        let messages: [String]

        private enum CodingKeys: String, CodingKey {
            case version, id, title, project, state, reason, sentence, startedAt, updatedAt, plan, messages
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(version, forKey: .version)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encode(project, forKey: .project)
            try c.encode(state, forKey: .state)
            try c.encode(reason, forKey: .reason)
            try c.encode(sentence, forKey: .sentence)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(updatedAt, forKey: .updatedAt)
            try c.encode(plan, forKey: .plan)
            try c.encode(messages, forKey: .messages)
        }
    }

    struct Plan: Encodable, Equatable {
        let summary: String
        /// The steps' titles, in plan order.
        let steps: [String]
        /// Claude's own confidence word ("high"), when the plan gives one.
        let feasibility: String?

        private enum CodingKeys: String, CodingKey { case summary, steps, feasibility }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(summary, forKey: .summary)
            try c.encode(steps, forKey: .steps)
            try c.encode(feasibility, forKey: .feasibility)
        }
    }

    /// The most step titles sent; a plan's card lists far fewer.
    static let stepLimit = 50

    /// The first of `candidates` with the id, as Bench knows it now. `plan`
    /// is the card's preview, when Bench holds one ready.
    static func session(id: String, candidates: [SessionStatus], plan: PlanPreview?) -> Session? {
        guard let session = candidates.first(where: { $0.id == id }) else { return nil }
        let reason = session.state == .needsInput ? (session.waitingReason ?? .other) : nil
        return Session(
            version: version, id: session.id, title: session.displayTitle, project: session.projectName,
            state: session.state.rawValue, reason: reason?.rawValue, sentence: sentence(session),
            startedAt: session.startedAt, updatedAt: session.updatedAt,
            plan: reason == .plan ? plan.map {
                Plan(summary: $0.summary, steps: Array($0.stepTitles.prefix(stepLimit)), feasibility: $0.confidence)
            } : nil,
            messages: [])
    }

    /// What the session's row says, as the Mac's activity list words it.
    static func sentence(_ session: SessionStatus) -> String {
        switch session.state {
        case .needsInput: (session.waitingReason ?? .other).sentence
        case .running: "Working"
        case .finished: "Finished"
        case .error: "Stopped with an error"
        case .unknown: "Unknown"
        }
    }

    // MARK: `/api/me`

    struct Me: Encodable, Equatable {
        let paired: Bool
        let device: String
        let bench: String
    }

    // MARK: Encoding

    /// ISO 8601 UTC dates, sorted keys, unescaped slashes; one line, so a
    /// state fits one `data:` line of the events stream.
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    // MARK: From the live models

    /// The input, from the models as they are now.
    static func input(lab: LabModel, usage: PlanUsageModel, bench: String, now: Date = Date()) -> Input {
        Input(bench: bench, now: now, problem: lab.problem, waiting: lab.waiting, snoozed: lab.snoozed,
              failed: lab.cards.compactMap { if case .failed(let session) = $0 { session } else { nil } },
              working: lab.working, recent: lab.recent, limits: usage.limits, forecasts: usage.forecasts)
    }

    /// Every session Bench knows of now, the freshest reading first: what
    /// waits and works, the last read, the failure cards, then Recent.
    static func knownSessions(lab: LabModel) -> [SessionStatus] {
        lab.waiting + lab.working + lab.sessions + lab.cards.compactMap(\.session)
            + lab.recent.compactMap(\.session) + lab.latest
    }

    /// The plan a card holds ready, for the session's `plan`.
    static func readyPlan(_ approver: PlanApprover, sessionID: String) -> PlanPreview? {
        if case .ready(let preview)? = approver.state(for: sessionID) { preview } else { nil }
    }

    /// Bench's version, from its bundle: empty for a build-folder binary.
    static var benchVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

/// Says when what `/api/state` shows may have changed: any of the models'
/// published values, debounced 300 ms. Only while the server runs.
@MainActor
final class RemoteFeed {
    static let debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)

    private var subscription: AnyCancellable?

    func start(lab: LabModel, usage: PlanUsageModel, approver: PlanApprover, changed: @escaping @MainActor () -> Void) {
        let signals: [AnyPublisher<Void, Never>] = [
            lab.$working.map { _ in () }.eraseToAnyPublisher(),
            lab.$waiting.map { _ in () }.eraseToAnyPublisher(),
            lab.$cards.map { _ in () }.eraseToAnyPublisher(),
            lab.$snoozed.map { _ in () }.eraseToAnyPublisher(),
            lab.$recent.map { _ in () }.eraseToAnyPublisher(),
            lab.$problem.map { _ in () }.eraseToAnyPublisher(),
            usage.$limits.map { _ in () }.eraseToAnyPublisher(),
            usage.$forecasts.map { _ in () }.eraseToAnyPublisher(),
            approver.$states.map { _ in () }.eraseToAnyPublisher(),
        ]
        // @Published publishes before the value changes; after the wait the
        // models hold the new values.
        subscription = Publishers.MergeMany(signals)
            .debounce(for: Self.debounce, scheduler: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { changed() } }
    }

    func stop() {
        subscription = nil
    }
}
