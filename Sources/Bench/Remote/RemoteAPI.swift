// RemoteAPI.swift — what the phone is told (DESIGN.md, `/api/state` version 1
// and `/api/sessions/<id>` version 2). The builders are pure functions of
// plain inputs, tested with made-up sessions; `RemoteFeed` watches the models
// and says when the state changed, for the events stream.
//
// Titles and project names are the user's own and go only to their paired
// devices. What a session says comes only from the session reader's
// projection (SessionReader.swift), read when the phone opens that session.
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
        /// The running sessions a used-up limit holds, by id (Lab/UsagePause.swift).
        var held: [String: UsagePause] = [:]
        /// What changed while someone was away, when it is worth telling (SinceYouLeft/), and
        /// what is known of its rows: the last words of a finished session, why one stopped.
        var since: SinceYouLeftSummary?
        var sinceDetails: [String: SinceYouLeftDetail] = [:]
    }

    /// `pause` in `/api/state`: some of the running sessions (those marked
    /// `paused`) wait for a limit to start over. `until` is the time to show,
    /// in the phone's own time zone; `sentence` says it in the Mac's, for an
    /// older phone app.
    struct Pause: Encodable, Equatable {
        let limit: String
        let until: Date?
        let sentence: String

        private enum CodingKeys: String, CodingKey { case limit, until, sentence }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(limit, forKey: .limit)
            try c.encode(until, forKey: .until)
            try c.encode(sentence, forKey: .sentence)
        }
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
        var pause: Pause? = nil
        /// Since You Left, version 1 of its own (`Since.v`). Left out of the JSON while there is
        /// none, so a state without it is the one every older phone page was written for.
        var since: Since? = nil

        private enum CodingKeys: String, CodingKey {
            case version, bench, updatedAt, problem, needsYou, failed, working, recent, usage, pause, since
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
            try c.encode(pause, forKey: .pause)
            try c.encodeIfPresent(since, forKey: .since)
        }

        /// The count on the phone's Home Screen icon: what needs you plus what
        /// stopped with an error. The app adds the same two lists.
        var badge: Int { needsYou.count + failed.count }

        /// The same state at another moment: for telling a real change from
        /// a tick.
        func at(_ date: Date) -> State {
            State(version: version, bench: bench, updatedAt: date, problem: problem, needsYou: needsYou,
                  failed: failed, working: working, recent: recent, usage: usage, pause: pause, since: since)
        }
    }

    /// `since` in `/api/state` (its own version 1): what changed while the person was away from the
    /// Mac. At most six rows (needs you first, then stopped, then finished) with the whole counts, so the
    /// headline is right; the rows' own detail is what Capsid knows without asking the page, and the
    /// phone reads the rest from the session's screen data. Titles and projects are the user's own, for
    /// paired devices only, as everywhere in the state.
    struct Since: Encodable, Equatable {
        struct Counts: Encodable, Equatable {
            let finished: Int
            let stopped: Int
            let needs: Int
        }

        struct Ask: Encodable, Equatable {
            let id: String
            let title: String
            let project: String
            let reason: String
            let sentence: String
            /// When it began to wait.
            let since: Date
        }

        struct Done: Encodable, Equatable {
            let id: String
            let title: String
            let project: String
            let at: Date
            /// The first lines of Claude's last words, when Capsid has read them.
            let line: String?

            private enum CodingKeys: String, CodingKey { case id, title, project, at, line }

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .id)
                try c.encode(title, forKey: .title)
                try c.encode(project, forKey: .project)
                try c.encode(at, forKey: .at)
                try c.encode(line, forKey: .line)
            }
        }

        struct Stop: Encodable, Equatable {
            let id: String
            let title: String
            let project: String
            let at: Date
            /// Why it stopped, one line, when Capsid has read it.
            let reason: String?

            private enum CodingKeys: String, CodingKey { case id, title, project, at, reason }

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .id)
                try c.encode(title, forKey: .title)
                try c.encode(project, forKey: .project)
                try c.encode(at, forKey: .at)
                try c.encode(reason, forKey: .reason)
            }
        }

        let v: Int
        /// The last moment someone was at the Mac; the phone counts "how long" from it.
        let awayAt: Date
        /// When they were back, or null while they are still away.
        let back: Date?
        let counts: Counts
        let asks: [Ask]
        let finished: [Done]
        let stopped: [Stop]
        /// How many rows were left out of the three lists.
        let more: Int

        private enum CodingKeys: String, CodingKey { case v, awayAt, back, counts, asks, finished, stopped, more }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(v, forKey: .v)
            try c.encode(awayAt, forKey: .awayAt)
            try c.encode(back, forKey: .back)
            try c.encode(counts, forKey: .counts)
            try c.encode(asks, forKey: .asks)
            try c.encode(finished, forKey: .finished)
            try c.encode(stopped, forKey: .stopped)
            try c.encode(more, forKey: .more)
        }

        /// Its own version, which grows only by adding fields.
        static let version = 1

        init(_ summary: SinceYouLeftSummary, details: [String: SinceYouLeftDetail]) {
            let rows = summary.shown()
            v = Self.version
            awayAt = summary.since
            back = summary.back
            counts = Counts(finished: summary.finished.count, stopped: summary.stopped.count, needs: summary.needs.count)
            asks = rows.needs.map {
                let reason = $0.session.waitingReason ?? .other
                return Ask(id: $0.id, title: $0.session.displayTitle, project: $0.session.projectName, reason: reason.rawValue,
                           sentence: reason.sentence, since: $0.at)
            }
            finished = rows.finished.map {
                Done(id: $0.id, title: $0.session.displayTitle, project: $0.session.projectName, at: $0.at, line: details[$0.id]?.answer)
            }
            stopped = rows.stopped.map {
                Stop(id: $0.id, title: $0.session.displayTitle, project: $0.session.projectName, at: $0.at, reason: details[$0.id]?.reason)
            }
            more = rows.hidden
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
        /// A used-up limit holds it (`pause` says until when).
        var paused = false

        private enum CodingKeys: String, CodingKey { case id, title, project, startedAt, paused }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(title, forKey: .title)
            try c.encode(project, forKey: .project)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encode(paused, forKey: .paused)
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
            Working(id: $0.id, title: $0.displayTitle, project: $0.projectName, startedAt: $0.startedAt,
                    paused: input.held[$0.id] != nil)
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
        // Only while a working session is held: a limit used up with nothing
        // running holds nothing. One limit holds them all.
        let pause = input.working.lazy.compactMap { input.held[$0.id] }.first.map {
            Pause(limit: name($0.limit), until: $0.until, sentence: $0.sentence(now: input.now))
        }
        let since = input.since.flatMap { $0.isEmpty ? nil : Since($0, details: input.sinceDetails) }
        return State(version: version, bench: input.bench, updatedAt: input.now, problem: input.problem?.label,
                     needsYou: needsYou, failed: failed, working: working, recent: recent,
                     usage: limits.isEmpty ? nil : Usage(limits: limits), pause: pause, since: since)
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

    /// The session route's version: 2 since Phase 2 (read, act).
    static let sessionVersion = 2

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
        /// Always empty: kept from version 1. The turns are in `turns`.
        let messages: [String]
        // Version 2: null (and `readable` false) when the session couldn't
        // be read.
        let readable: Bool
        /// The root's `status_description`.
        let statusLine: String?
        let reply: Reply?
        /// Oldest first, at most 12.
        let turns: [Turn]?
        /// The agent's "messages to you", at most 5.
        let toYou: [Note]?
        /// Messages waiting for a safe point.
        let queued: Int?
        /// The root's own question, while it waits for an answer.
        let question: Question?
        let can: Can
        /// The head of the root's and its helpers' permission requests, when
        /// there is one (Phase 4). // Phase 4 permissions
        var permission: Permission?

        private enum CodingKeys: String, CodingKey {
            case version, id, title, project, state, reason, sentence, startedAt, updatedAt, plan, messages
            case readable, statusLine, reply, turns, toYou, queued, question, can
            case permission // Phase 4 permissions
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
            try c.encode(readable, forKey: .readable)
            try c.encode(statusLine, forKey: .statusLine)
            try c.encode(reply, forKey: .reply)
            try c.encode(turns, forKey: .turns)
            try c.encode(toYou, forKey: .toYou)
            try c.encode(queued, forKey: .queued)
            try c.encode(question, forKey: .question)
            try c.encode(can, forKey: .can)
            try c.encode(permission, forKey: .permission) // Phase 4 permissions
        }
    }

    struct Plan: Encodable, Equatable {
        let summary: String
        /// The steps' titles, in plan order.
        let steps: [String]
        /// Claude's own confidence word ("high"), when the plan gives one.
        let feasibility: String?
        /// The plan's version, opaque to the phone: Approve sends it back,
        /// and Bench approves only while that version still waits.
        let version: String

        private enum CodingKeys: String, CodingKey { case summary, steps, feasibility, version }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(summary, forKey: .summary)
            try c.encode(steps, forKey: .steps)
            try c.encode(feasibility, forKey: .feasibility)
            try c.encode(version, forKey: .version)
        }
    }

    /// The last reply, as markdown the phone renders as plain text with a
    /// small safe subset.
    struct Reply: Encodable, Equatable {
        let text: String
        let at: Date?

        private enum CodingKeys: String, CodingKey { case text, at }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(at, forKey: .at)
        }
    }

    struct Turn: Encodable, Equatable {
        /// "you" or "claude".
        let role: String
        /// Null when the daemon's row has no time.
        let at: Date?
        let text: String

        private enum CodingKeys: String, CodingKey { case role, at, text }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encode(at, forKey: .at)
            try c.encode(text, forKey: .text)
        }
    }

    struct Note: Encodable, Equatable {
        let text: String
        let at: Date?

        private enum CodingKeys: String, CodingKey { case text, at }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(at, forKey: .at)
        }
    }

    struct Question: Encodable, Equatable {
        let toolId: String
        let items: [Item]
    }

    struct Item: Encodable, Equatable {
        let question: String
        let header: String
        let multi: Bool
        let options: [Option]
    }

    struct Option: Encodable, Equatable {
        let label: String
        let detail: String?

        private enum CodingKeys: String, CodingKey { case label, detail }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(label, forKey: .label)
            try c.encode(detail, forKey: .detail)
        }
    }

    /// What the phone may offer (`RemoteCan.make`).
    struct Can: Encodable, Equatable {
        let approve: Bool
        let answer: Bool
        /// "send", "queue", "resume", or null.
        let message: String?
        /// Why something isn't offered, when that needs saying.
        let why: String?

        private enum CodingKeys: String, CodingKey { case approve, answer, message, why }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(approve, forKey: .approve)
            try c.encode(answer, forKey: .answer)
            try c.encode(message, forKey: .message)
            try c.encode(why, forKey: .why)
        }
    }

    /// The most step titles sent; a plan's card lists far fewer.
    static let stepLimit = 50

    /// The first of `candidates` with the id, as Bench knows it now.
    ///
    /// `read` is the session reader's projection, nil when the session
    /// couldn't be read. `plan` is the plan to show: read, the one waiting on
    /// the root (shown only when its version is the one the read names);
    /// unreadable, the card's preview, as version 1 showed it.
    static func session(id: String, candidates: [SessionStatus], plan: PlanPreview?,
                        read: SessionProjection? = nil, actionsOn: Bool = true) -> Session? {
        guard let session = candidates.first(where: { $0.id == id }) else { return nil }
        let reason = session.state == .needsInput ? (session.waitingReason ?? .other) : nil
        let shown: PlanPreview?
        if let read {
            let waiting = PlanCheck.versionToRead(read.planFrame)
            shown = plan.flatMap { waiting != nil && $0.versionID == waiting ? $0 : nil }
        } else {
            shown = reason == .plan ? plan : nil
        }
        let question = read.flatMap { $0.status == "awaiting_user_response" ? $0.question : nil }
        return Session(
            version: sessionVersion, id: session.id, title: session.displayTitle, project: session.projectName,
            state: session.state.rawValue, reason: reason?.rawValue, sentence: sentence(session),
            startedAt: session.startedAt, updatedAt: session.updatedAt,
            plan: shown.map {
                Plan(summary: $0.summary, steps: Array($0.stepTitles.prefix(stepLimit)), feasibility: $0.confidence,
                     version: $0.versionID)
            },
            messages: [],
            readable: read != nil,
            statusLine: read?.statusLine,
            reply: read.flatMap { read in read.reply.map { Reply(text: $0, at: read.replyAt) } },
            turns: read.map { ($0.turns ?? []).map { Turn(role: $0.role.rawValue, at: $0.at, text: $0.text) } },
            toYou: read.map { $0.toYou.map { Note(text: $0.text, at: $0.at) } },
            queued: read?.queued,
            question: question.map { ask in
                Question(toolId: ask.toolID, items: ask.items.map { item in
                    Item(question: item.question, header: item.header, multi: item.multi,
                         options: item.options.map { Option(label: $0.label, detail: $0.detail) })
                })
            },
            can: RemoteCan.make(read: read, plan: shown, actionsOn: actionsOn),
            permission: read?.permission.map { RemotePermission.describe($0, actionsOn: actionsOn) }) // Phase 4 permissions
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
        /// Settings → Phone lets paired devices browse (`remoteBrowse`). // Phase 3 browse
        var browse: Bool = RemoteBrowse.isOn
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
        var input = Input(bench: bench, now: now, problem: lab.problem, waiting: lab.waiting, snoozed: lab.snoozed,
                          failed: failedSessions(lab: lab),
                          working: lab.working, recent: lab.recent, limits: usage.limits, forecasts: usage.forecasts,
                          held: UsagePauseModel.shared.held)
        // What changed while someone was away (SinceYouLeft/): while the stretch lasts, and after the return until Done.
        if lab === LabModel.shared, let summary = SinceYouLeftModel.shared.forPhone(now: now) {
            input.since = summary
            let details = SinceYouLeftModel.shared.detailsForPhone(summary)
            input.sinceDetails = details
        }
        return input
    }

    /// The sessions of the failure cards: `failed` in `/api/state`.
    static func failedSessions(lab: LabModel) -> [SessionStatus] {
        lab.cards.compactMap { if case .failed(let session) = $0 { session } else { nil } }
    }

    /// `State.badge` of the lab as it is now, for a push to carry.
    static func badge(lab: LabModel) -> Int {
        lab.waiting.count + failedSessions(lab: lab).count
    }

    /// Every session Bench knows of now, the freshest reading first: what
    /// waits and works, the last read, the failure cards, then Recent.
    static func knownSessions(lab: LabModel) -> [SessionStatus] {
        lab.waiting + lab.workingAsRead + lab.sessions + lab.cards.compactMap(\.session)
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

    func start(lab: LabModel, usage: PlanUsageModel, approver: PlanApprover,
               since: SinceYouLeftModel = .shared, reasonChanges: AnyPublisher<Void, Never> = SinceYouLeftReads.reasonChanges,
               changed: @escaping @MainActor () -> Void) {
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
            UsagePauseModel.shared.$held.map { _ in () }.eraseToAnyPublisher(),
            // Since You Left: a stretch begins or ends, what was read for its rows lands, a failure's reason is read.
            since.$awaySince.map { _ in () }.eraseToAnyPublisher(),
            since.$pending.map { _ in () }.eraseToAnyPublisher(),
            since.$details.map { _ in () }.eraseToAnyPublisher(),
            reasonChanges,
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
