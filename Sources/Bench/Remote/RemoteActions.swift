// RemoteActions.swift — what the phone may do, and reading a session for it
// (DESIGN.md, Bench on your phone → Phase 2: `/api/sessions/<id>` version 2
// and Actions). Three POST routes: approve a plan, answer a question, send a
// message. Each one reads the root frame afresh, decides, and only then
// writes; anything unexpected is "unavailable", and the phone offers Open on
// Mac instead.
//
// The decisions are pure (`RemoteDecide`, `RemoteMessageMode`,
// `ActionLimiter`, the body parsers) and tested on made-up frames.
// `RemoteSessions` is the thin part that reads and writes through injected
// closures: the page in the app, made-up sessions in `--demo remote` and the
// tests. Nothing here logs; the server logs the route's pattern and status.
import Foundation
import SwiftUI

// MARK: The routes and their answers

/// The three action routes, `POST /api/sessions/<id>/<action>`.
enum RemoteAction: String, CaseIterable, Sendable {
    case approve, answer, message
}

/// What an action answers the phone: `{"result": …, "sentence": "…"}`.
struct RemoteActionResult: Encodable, Equatable, Sendable {
    enum Result: String, Encodable, Sendable {
        case approved, changed, unavailable, sent, queued, resumed, blocked
    }

    let result: Result
    let sentence: String

    static let unavailable = RemoteActionResult(result: .unavailable,
                                                sentence: "Couldn't do that from here. Open it on your Mac.")
}

/// The status and JSON body of an action's answer.
struct RemoteActionReply: Equatable, Sendable {
    let status: Int
    let body: Data

    static func ok(_ result: RemoteActionResult) -> RemoteActionReply {
        RemoteActionReply(status: 200, body: RemoteActionReply.encode(result))
    }

    /// Settings → Phone has actions off: 403, with a sentence the phone can show.
    static let actionsOff = RemoteActionReply(status: 403, body: encode(
        Refusal(error: "actionsOff", result: .unavailable, sentence: RemoteCan.Why.actionsOff)))
    /// Over six a minute from this device.
    static let tooMany = RemoteActionReply(status: 429, body: encode(
        Refusal(error: "tooMany", result: .unavailable, sentence: "That's a lot at once. Try again in a minute.")))
    static let notFound = RemoteActionReply(status: 404, body: encode(Refusal(error: "Not Found", result: nil, sentence: nil)))
    static let badRequest = RemoteActionReply(status: 400, body: encode(Refusal(error: "Bad Request", result: nil, sentence: nil)))

    private struct Refusal: Encodable {
        let error: String
        let result: RemoteActionResult.Result?
        let sentence: String?
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }
}

extension RemoteRoute {
    /// A message's body may be up to 16 KB: 4,000 characters of non-Latin
    /// text is more than 8 KB of JSON. Every other body stays at 8 KB.
    static let messageBodyLimit = 16 * 1024

    /// The most this route's body may be.
    var bodyLimit: Int {
        switch self {
        case .action(.message, _), .newSession: Self.messageBodyLimit // Phase 3 browse: a new session's text too
        default: RemoteHTTP.maxBody
        }
    }

    /// The parser's declared-length check, before the request is whole: the
    /// route's own limit, else 8 KB.
    static func bodyLimit(method: String, path: Substring) -> Int {
        if case .found(let route) = match(method: method, path: path) { route.bodyLimit } else { RemoteHTTP.maxBody }
    }
}

// MARK: The bodies

/// An action's body, checked. Nil from `parse` for anything else (400).
enum RemoteActionRequest: Equatable, Sendable {
    /// `{"version":"…"}`: the plan version the phone showed.
    case approve(version: String)
    /// `{"toolId","answers":{"<question>":"<text>"}}`.
    case answer(toolID: String, answers: [String: String])
    /// `{"toolId","action":"chooseForMe"}`.
    case chooseForMe(toolID: String)
    /// `{"toolId","action":"cancel"}`.
    case cancel(toolID: String)
    /// `{"text","id"}`: the text trimmed, the phone's uuid v4 the intent id.
    case message(text: String, intentID: String)

    static let answerLimit = 1_000
    static let messageLimit = 4_000

    static func parse(_ action: RemoteAction, body: Data) -> RemoteActionRequest? {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        switch action {
        case .approve:
            guard let version = Pick.string(root["version"]), PlanCheck.isVersionID(version) else { return nil }
            return .approve(version: version)
        case .answer:
            guard let toolID = Pick.text(root["toolId"], limit: SessionProjection.Limit.toolID) else { return nil }
            let hasAnswers = root["answers"] != nil, hasAction = root["action"] != nil
            guard hasAnswers != hasAction else { return nil }
            if hasAction {
                switch Pick.string(root["action"]) {
                case "chooseForMe": return .chooseForMe(toolID: toolID)
                case "cancel": return .cancel(toolID: toolID)
                default: return nil
                }
            }
            guard let given = root["answers"] as? [String: Any],
                  (1...SessionProjection.Limit.questions).contains(given.count) else { return nil }
            var answers: [String: String] = [:]
            for (question, value) in given {
                guard !question.isEmpty, question.unicodeScalars.count <= SessionProjection.Limit.question,
                      let text = Pick.string(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty, text.unicodeScalars.count <= answerLimit else { return nil }
                answers[question] = text
            }
            return .answer(toolID: toolID, answers: answers)
        case .message:
            guard let text = Pick.string(root["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text.unicodeScalars.count <= messageLimit,
                  let id = Pick.string(root["id"]), isUUIDv4(id) else { return nil }
            return .message(text: text, intentID: id)
        }
    }

    /// `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`,
    /// as `crypto.randomUUID()` makes them.
    static func isUUIDv4(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            switch index {
            case 8, 13, 18, 23: if byte != 0x2D { return false }
            case 14: if byte != 0x34 { return false }
            case 19: if ![0x38, 0x39, 0x61, 0x62].contains(byte) { return false }
            default: if !((0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)) { return false }
            }
        }
        return true
    }
}

// MARK: What may be done

/// Whether a session takes a message, from its root's status: the same
/// table for the phone's `can.message` and for the check before sending.
enum RemoteMessageMode: Equatable, Sendable {
    /// `completed`, `success`: a new turn.
    case send
    /// `processing`: it waits for a safe point.
    case queue
    /// `failed`, `cancelled`: the session picks up again.
    case resume
    /// Not now, and why.
    case blocked(String)

    init(status: String) {
        switch status {
        case "completed", "success": self = .send
        case "processing": self = .queue
        case "failed", "cancelled": self = .resume
        case "awaiting_user_response": self = .blocked(RemoteCan.Why.answerFirst)
        case "awaiting_plan_approval": self = .blocked(RemoteCan.Why.planFirst)
        default: self = .blocked(RemoteCan.Why.noMessage)
        }
    }

    /// `can.message`: "send", "queue", "resume" or null.
    var word: String? {
        switch self {
        case .send: "send"
        case .queue: "queue"
        case .resume: "resume"
        case .blocked: nil
        }
    }
}

/// The session's `can`: what the phone may offer.
enum RemoteCan {
    enum Why {
        static let actionsOff = "Actions are off in Bench's Settings"
        static let unreadable = "Bench can't read this session"
        static let answerFirst = "Answer its question first"
        static let planFirst = "Approve or revise the plan on your Mac"
        /// A `replaced` frame: not in the spec's table, so not offered.
        static let noMessage = "This session can't take a message from here"
    }

    /// In this order: actions off, then unreadable, then what the root's
    /// status allows. `plan` is the plan shown, when it is the one waiting.
    static func make(read: SessionProjection?, plan: PlanPreview?, actionsOn: Bool) -> RemoteAPI.Can {
        guard actionsOn else { return RemoteAPI.Can(approve: false, answer: false, message: nil, why: Why.actionsOff) }
        guard let read else { return RemoteAPI.Can(approve: false, answer: false, message: nil, why: Why.unreadable) }
        let version = PlanCheck.versionToRead(read.planFrame)
        let approve = version != nil && plan?.versionID == version
        let answer = read.status == "awaiting_user_response" && read.question != nil
        var mode = RemoteMessageMode(status: read.status)
        // Every message names the root's own agent; without one, none goes.
        if mode.word != nil, read.agentName == nil { mode = .blocked(Why.unreadable) }
        if case .blocked(let why) = mode {
            return RemoteAPI.Can(approve: approve, answer: answer, message: nil, why: why)
        }
        return RemoteAPI.Can(approve: approve, answer: answer, message: mode.word, why: nil)
    }
}

/// Every decision about an action, pure: check the fresh read, say what to
/// write or what to answer, and what the daemon's reply means.
enum RemoteDecide {
    enum Step: Equatable {
        /// Write this, then map the reply.
        case write(RemoteWrite)
        /// Answer this without writing anything.
        case answer(RemoteActionResult)
    }

    /// The text "Choose for me" sends for every question, as Claude Science's
    /// own UI does.
    static let bestJudgment = "Use your best judgment for this question"

    enum Sentence {
        static let approved = "Approved. Claude is starting on the plan."
        static let planChanged = "The plan changed. Look at it again."
        static let planBusy = "Claude is busy with it. Look again in a moment."
        static let answered = "Answer sent."
        static let chosen = "Sent. Claude will use its best judgment."
        static let cancelled = "Question cancelled."
        static let questionChanged = "The question changed. Look at it again."
        static let alreadyAnswered = "It was already answered."
        static let sent = "Sent."
        static let queued = "Queued. Claude reads it at the next safe point."
        static let resumed = "Sent. The session picks up again."
        static let tooManyQueued = "Too many messages are waiting for it. Try again later."
    }

    // MARK: Approve

    /// `PlanApprover`'s check: the root itself still waits, not approved,
    /// with the very version the phone showed. Then `approve-plan` `{}`.
    static func approve(version: String, session: String, fresh: SessionProjection?) -> Step {
        guard let fresh else { return .answer(.unavailable) }
        guard PlanCheck.versionToRead(fresh.planFrame) == version else {
            return .answer(RemoteActionResult(result: .changed, sentence: Sentence.planChanged))
        }
        return .write(.approvePlan(frame: session))
    }

    /// The card's own reading of the reply (`PlanCheck.outcome`).
    static func approved(_ reply: RemoteWriteResult?) -> RemoteActionResult {
        guard let reply else { return .unavailable }
        switch PlanCheck.outcome(reply.asApproval) {
        case .approved: return RemoteActionResult(result: .approved, sentence: Sentence.approved)
        case .changed: return RemoteActionResult(result: .changed, sentence: Sentence.planChanged)
        case .busy: return RemoteActionResult(result: .changed, sentence: Sentence.planBusy)
        case .failed: return .unavailable
        }
    }

    // MARK: Answer

    /// Still `awaiting_user_response`, the same `tool_id` pending on the
    /// root, the same question texts, and every one answered.
    static func answer(_ request: RemoteActionRequest, session: String, fresh: SessionProjection?) -> Step {
        guard let fresh else { return .answer(.unavailable) }
        let changed = RemoteActionResult(result: .changed, sentence: Sentence.questionChanged)
        let toolID: String
        switch request {
        case .answer(let id, _), .chooseForMe(let id), .cancel(let id): toolID = id
        default: return .answer(.unavailable)
        }
        guard fresh.status == "awaiting_user_response",
              let ask = fresh.asks.compactMap({ $0 }).first(where: { $0.toolID == toolID }) else { return .answer(changed) }
        let questions = ask.items.map(\.question)
        switch request {
        case .answer(_, let answers):
            guard Set(answers.keys) == Set(questions), answers.count == questions.count else { return .answer(changed) }
            return .write(.answer(frame: session, toolID: toolID, answers: answers))
        case .chooseForMe:
            let answers = Dictionary(questions.map { ($0, bestJudgment) }, uniquingKeysWith: { first, _ in first })
            return .write(.answer(frame: session, toolID: toolID, answers: answers))
        default:
            return .write(.cancel(frame: session, toolID: toolID))
        }
    }

    static func answered(_ reply: RemoteWriteResult?, request: RemoteActionRequest) -> RemoteActionResult {
        guard let reply else { return .unavailable }
        switch (reply.status, reply.bodyStatus) {
        case (200, "accepted"?), (200, "buffered"?):
            guard reply.isJSON else { return .unavailable }
            let sentence = switch request {
            case .chooseForMe: Sentence.chosen
            case .cancel: Sentence.cancelled
            default: Sentence.answered
            }
            return RemoteActionResult(result: .sent, sentence: sentence)
        case (200, "already_resolved"?):
            return RemoteActionResult(result: .changed, sentence: Sentence.alreadyAnswered)
        case (400, _) where reply.staleInput:
            return RemoteActionResult(result: .changed, sentence: Sentence.questionChanged)
        default:
            return .unavailable
        }
    }

    // MARK: Message

    /// Only for `completed`/`success`, `processing`, `failed`/`cancelled`;
    /// to the agent the fresh read names, with `plan_mode` false.
    static func message(_ request: RemoteActionRequest, session: String, fresh: SessionProjection?) -> Step {
        guard case .message(let text, let intentID) = request, let fresh else { return .answer(.unavailable) }
        let mode = RemoteMessageMode(status: fresh.status)
        if case .blocked(let why) = mode { return .answer(RemoteActionResult(result: .blocked, sentence: why + ".")) }
        guard let agent = fresh.agentName else { return .answer(.unavailable) }
        return .write(.message(frame: session, agent: agent, projectID: fresh.projectID, text: text, intentID: intentID))
    }

    /// `status` is the root's, as read just before sending.
    static func messaged(_ reply: RemoteWriteResult?, status: String) -> RemoteActionResult {
        guard let reply else { return .unavailable }
        switch (reply.status, reply.bodyStatus) {
        case (200, "accepted"?) where reply.isJSON:
            return RemoteMessageMode(status: status) == .resume
                ? RemoteActionResult(result: .resumed, sentence: Sentence.resumed)
                : RemoteActionResult(result: .sent, sentence: Sentence.sent)
        case (200, "message_queued"?) where reply.isJSON:
            return RemoteActionResult(result: .queued, sentence: Sentence.queued)
        case (200, "already_delivered"?) where reply.isJSON:
            // A retry with the same intent id: the first one went.
            return RemoteActionResult(result: .sent, sentence: Sentence.sent)
        case (400, _) where reply.askPending:
            return RemoteActionResult(result: .blocked, sentence: RemoteCan.Why.answerFirst + ".")
        case (429, _):
            return RemoteActionResult(result: .blocked, sentence: Sentence.tooManyQueued)
        default:
            return .unavailable
        }
    }
}

/// At most six actions a minute per device; the seventh gets 429.
struct ActionLimiter {
    static let perMinute = 6
    static let window: TimeInterval = 60

    private var times: [String: [Date]] = [:]

    /// Counts the attempt when it is allowed.
    mutating func allow(_ device: String, at now: Date) -> Bool {
        times = times.compactMapValues { list in
            let recent = list.filter { now.timeIntervalSince($0) < Self.window && $0 <= now }
            return recent.isEmpty ? nil : recent
        }
        let recent = times[device] ?? []
        guard recent.count < Self.perMinute else { return false }
        times[device] = recent + [now]
        return true
    }
}

// MARK: Reading and acting

/// `/api/sessions/<id>` (version 2) and the three actions, over injected
/// reads and writes. A session is read only when the phone asks for it,
/// and what was read is kept 5 seconds, so a burst of requests reads the
/// page once.
@MainActor
final class RemoteSessions {
    static let shared = RemoteSessions(dependencies: .live())
    static let cacheLifetime: TimeInterval = 5

    /// `remoteActions`, on unless it was turned off (as a bool, or as the
    /// string a command-line `-remoteActions NO` gives).
    nonisolated static func actionsSetting(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.remoteActions) == nil ? true : defaults.bool(forKey: SettingsKey.remoteActions)
    }

    struct Dependencies {
        /// Settings → Phone → "Let paired devices answer, approve and send
        /// messages" (`remoteActions`).
        var actionsOn: @MainActor () -> Bool
        /// Every session Bench knows now (`RemoteAPI.knownSessions`).
        var known: @MainActor () -> [SessionStatus]
        /// The plan a card holds ready (`RemoteAPI.readyPlan`).
        var cardPlan: @MainActor (String) -> PlanPreview?
        /// The session reader: nil when it can't be read.
        var read: @MainActor (_ id: String, _ turns: Bool) async -> SessionProjection?
        /// A plan file (`apiGET /artifacts/versions/<id>`).
        var readPlan: @MainActor (_ version: String) async -> PlanDocument?
        /// The writer: nil when the write didn't complete.
        var write: @MainActor (RemoteWrite) async -> RemoteWriteResult?
        var now: @MainActor () -> Date
        // Phase 3 browse
        /// Settings → Phone → "Let paired devices browse…" (`remoteBrowse`).
        var browseOn: @MainActor () -> Bool = { RemoteBrowse.isOn }
        /// The database's point lookup: any root session, by its id.
        var lookup: @MainActor (String) async -> SessionStatus? = { _ in nil }

        static func live() -> Dependencies {
            Dependencies(
                actionsOn: { RemoteSessions.actionsSetting() },
                known: { RemoteAPI.knownSessions(lab: .shared) },
                cardPlan: { RemoteAPI.readyPlan(.shared, sessionID: $0) },
                read: { id, turns in
                    guard Demo.mode == nil else { return nil }
                    return (try? await WebContainer.shared.readSession(id, turns: turns)) ?? nil
                },
                readPlan: { version in
                    guard Demo.mode == nil, let path = PlanCheck.versionPath(version),
                          let data = try? await WebContainer.shared.apiGET(path) else { return nil }
                    return PlanDocument(json: data)
                },
                write: { write in
                    guard Demo.mode == nil else { return nil }
                    return try? await WebContainer.shared.writeSession(write)
                },
                now: { Date() },
                lookup: { await RemoteBrowser.lookUp($0) }) // Phase 3 browse
        }
    }

    private struct Entry {
        let at: Date
        let read: SessionProjection?
        /// The plan waiting on the root, when it could be read.
        let plan: PlanPreview?
    }

    private let dependencies: Dependencies
    private var cache: [String: Entry] = [:]
    private var loading: [String: Task<Entry, Never>] = [:]
    /// Bumped when an action may have changed the session: a read started
    /// before it isn't kept.
    private var generation: [String: Int] = [:]
    private var acting: [String: Task<RemoteActionReply, Never>] = [:]
    private var limiter = ActionLimiter()
    private var sweep: Task<Void, Never>?
    /// Phase 3 browse: sessions found by id or just started, by id.
    private var held: [String: Held] = [:]

    private struct Held {
        let session: SessionStatus
        let until: Date
        /// Admits the session when the database doesn't have it yet: one
        /// the phone has just started.
        let admits: Bool
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: Reading

    /// `/api/sessions/<id>`, version 2; nil when the phone may not open the
    /// session (`admitted`).
    func sessionJSON(_ id: String) async -> Data? {
        guard let found = await admitted(id) else { return nil } // Phase 3 browse
        let entry = await entry(for: id)
        // Unreadable: the card's plan, as version 1 showed it.
        let plan = entry.read == nil ? dependencies.cardPlan(id) : entry.plan
        return RemoteAPI.session(id: id, candidates: dependencies.known() + found, plan: plan, read: entry.read,
                                 actionsOn: dependencies.actionsOn()).map(RemoteAPI.encode)
    }

    // MARK: Which sessions open (Phase 3 browse)

    /// Whether the phone may open this session, and what else to know it by:
    /// `[]` for one Bench knows now (its own reading is fresher), the
    /// database's row for any other root session while browse is on, or one
    /// the phone has just started that the database doesn't have yet. Nil:
    /// not this one (404).
    func admitted(_ id: String) async -> [SessionStatus]? {
        if dependencies.known().contains(where: { $0.id == id }) { return [] }
        guard dependencies.browseOn() else { return nil }
        let now = dependencies.now()
        if let row = await dependencies.lookup(id), row.id == id {
            hold(row, until: now.addingTimeInterval(60 * 60), admits: false)
            return [row]
        }
        if let held = held[id], held.admits, held.until > now { return [held.session] }
        return nil
    }

    /// A session the phone opened lately by browsing, for Open on Mac.
    func heldSession(_ id: String) -> SessionStatus? {
        guard dependencies.browseOn(), let held = held[id], held.until > dependencies.now() else { return nil }
        return held.session
    }

    /// A session the phone just started: it opens for two minutes even before
    /// the database has it.
    func admitStarted(_ session: SessionStatus) {
        hold(session, until: dependencies.now().addingTimeInterval(120), admits: true)
    }

    /// A new session counts toward the same six a minute as the actions.
    func allowAction(device: String) -> Bool {
        limiter.allow(device, at: dependencies.now())
    }

    private func hold(_ session: SessionStatus, until: Date, admits: Bool) {
        let now = dependencies.now()
        held[session.id] = Held(session: session, until: until, admits: admits)
        guard held.count > 200 else { return }
        held = held.filter { $0.value.until > now }
        while held.count > 200, let oldest = held.min(by: { $0.value.until < $1.value.until }) { held[oldest.key] = nil }
    }

    /// What is held for a session now: for tests.
    var cachedSessions: Set<String> { Set(cache.keys) }

    private func entry(for id: String) async -> Entry {
        let now = dependencies.now()
        if let cached = cache[id], cached.at <= now, now.timeIntervalSince(cached.at) < Self.cacheLifetime { return cached }
        if let task = loading[id] { return await task.value }
        let started = generation[id, default: 0]
        let task = Task { [weak self] () -> Entry in
            guard let self else { return Entry(at: .distantPast, read: nil, plan: nil) }
            let entry = await self.load(id)
            self.loading[id] = nil
            if self.generation[id, default: 0] == started {
                self.cache[id] = entry
                self.scheduleSweep()
            }
            return entry
        }
        loading[id] = task
        return await task.value
    }

    private func load(_ id: String) async -> Entry {
        let read = await dependencies.read(id, true)
        var plan: PlanPreview?
        if let read, let version = PlanCheck.versionToRead(read.planFrame) {
            if let card = dependencies.cardPlan(id), card.versionID == version {
                plan = card
            } else if let document = await dependencies.readPlan(version) {
                plan = PlanCheck.preview(frame: read.planFrame, plan: document)
            }
        }
        return Entry(at: dependencies.now(), read: read, plan: plan)
    }

    /// Drops what has been held 5 seconds, once nothing new comes.
    private func scheduleSweep() {
        sweep?.cancel()
        sweep = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.cacheLifetime + 0.5))
            guard !Task.isCancelled, let self else { return }
            self.dropExpired()
        }
    }

    func dropExpired() {
        let now = dependencies.now()
        cache = cache.filter { $0.value.at <= now && now.timeIntervalSince($0.value.at) < Self.cacheLifetime }
    }

    private func forget(_ id: String) {
        cache[id] = nil
        generation[id, default: 0] += 1
    }

    // MARK: Acting

    /// One action: actions on (403), within the device's limit (429), a
    /// session Bench knows (404), a body that fits (400); then, one at a time
    /// per session, read afresh, decide, write.
    func act(_ action: RemoteAction, session id: String, device: String, body: Data) async -> RemoteActionReply {
        guard dependencies.actionsOn() else { return .actionsOff }
        guard limiter.allow(device, at: dependencies.now()) else { return .tooMany }
        guard await admitted(id) != nil else { return .notFound } // Phase 3 browse
        guard let request = RemoteActionRequest.parse(action, body: body) else { return .badRequest }
        let previous = acting[id]
        let task = Task { [weak self] () -> RemoteActionReply in
            _ = await previous?.value
            guard let self else { return .ok(.unavailable) }
            let reply = await self.perform(request, session: id)
            self.forget(id)
            return reply
        }
        acting[id] = task
        let reply = await task.value
        if acting[id] == task { acting[id] = nil }
        return reply
    }

    private func perform(_ request: RemoteActionRequest, session id: String) async -> RemoteActionReply {
        let fresh = await dependencies.read(id, false)
        switch request {
        case .approve(let version):
            switch RemoteDecide.approve(version: version, session: id, fresh: fresh) {
            case .answer(let result): return .ok(result)
            case .write(let write): return .ok(RemoteDecide.approved(await dependencies.write(write)))
            }
        case .answer, .chooseForMe, .cancel:
            switch RemoteDecide.answer(request, session: id, fresh: fresh) {
            case .answer(let result): return .ok(result)
            case .write(let write): return .ok(RemoteDecide.answered(await dependencies.write(write), request: request))
            }
        case .message:
            switch RemoteDecide.message(request, session: id, fresh: fresh) {
            case .answer(let result): return .ok(result)
            case .write(let write):
                return .ok(RemoteDecide.messaged(await dependencies.write(write), status: fresh?.status ?? ""))
            }
        }
    }

    // MARK: `--demo remote`

    /// Made-up reads for made-up sessions; writes answer as the daemon would
    /// and go nowhere. No web view is touched.
    /// `known` and `cardPlan` are the demo's own models, unless a test
    /// gives its own.
    /// Phase 3 browse: `lookup` and `more` are the made-up sessions only
    /// browsing finds, and what they read.
    static func demo(reads: [String: SessionProjection],
                     known: @escaping @MainActor () -> [SessionStatus] = { RemoteAPI.knownSessions(lab: .shared) },
                     cardPlan: @escaping @MainActor (String) -> PlanPreview? = { RemoteAPI.readyPlan(.shared, sessionID: $0) },
                     now: @escaping @MainActor () -> Date = { Date() },
                     lookup: @escaping @MainActor (String) -> SessionStatus? = { _ in nil },
                     more: @escaping @MainActor (String) -> SessionProjection? = { _ in nil }) -> RemoteSessions {
        RemoteSessions(dependencies: Dependencies(
            actionsOn: { RemoteSessions.actionsSetting() },
            known: known,
            cardPlan: cardPlan,
            read: { id, turns in
                guard let read = reads[id] ?? more(id) else { return nil }
                return turns ? read : read.withoutTurns
            },
            readPlan: { _ in nil },
            write: { write in
                switch write {
                case .message(let frame, _, _, _, _) where (reads[frame] ?? more(frame))?.status == "processing":
                    RemoteWriteResult(status: 200, bodyStatus: "message_queued")
                case .answer, .cancel:
                    RemoteWriteResult(status: 200, bodyStatus: "accepted", remaining: 0)
                default:
                    RemoteWriteResult(status: 200, bodyStatus: "accepted")
                }
            },
            now: now,
            lookup: { lookup($0) }))
    }
}

extension SessionProjection {
    /// As an action's check reads it: the frame only.
    var withoutTurns: SessionProjection {
        SessionProjection(status: status, agentName: agentName, projectID: projectID, statusLine: statusLine,
                          reply: reply, replyAt: replyAt, toYou: toYou, queued: queued, asks: asks,
                          planVersion: planFrame.versionID, planArtifact: planFrame.artifactID,
                          approval: planFrame.approval, turns: nil)
    }
}

// MARK: Settings → Phone

/// "Let paired devices answer, approve and send messages" (`remoteActions`,
/// on). Its own section in Settings → Phone.
struct RemoteActionsSettingsSection: View {
    @AppStorage(SettingsKey.remoteActions) private var actionsOn = true

    var body: some View {
        Section {
            Toggle(isOn: $actionsOn) {
                Text("Let paired devices answer, approve and send messages")
                Text("Off, paired devices can still read your sessions, but only Open on Mac acts on them.")
            }
        }
    }
}
