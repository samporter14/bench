// RemoteActions.swift — what the phone may do, and reading a session for it
// (DESIGN.md, Capsid on your phone → Phase 2: `/api/sessions/<id>` version 2
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
//
// Every write has a deadline (Remote/WriteDeadline.swift). One that gets no
// answer is unknown, not failed: the session is read once more to see whether
// it landed (`RemoteDecide.settled…`), and the answer is then done, "didn't go
// through" (safe to send again, by the person), or "not sure". Nothing is ever
// sent again on its own, and a session's queue moves on past a turn that stalls.
import Foundation
import SwiftUI

// MARK: The routes and their answers

/// The action routes, `POST /api/sessions/<id>/<action>`; `permission` is
/// Phase 4's.
enum RemoteAction: String, CaseIterable, Sendable {
    case approve, answer, message
    case permission // Phase 4 permissions
}

/// What an action answers the phone: `{"result": …, "sentence": "…"}`.
struct RemoteActionResult: Encodable, Equatable, Sendable {
    enum Result: String, Encodable, Sendable {
        case approved, changed, unavailable, sent, queued, resumed, blocked
        case allowed, denied // Phase 4 permissions
        /// The write got no answer, and a fresh read couldn't say whether it
        /// landed either: neither done nor failed.
        case unknown
        /// The write got no answer, and a fresh read shows it did not land: it
        /// is safe to send again, when the person chooses to.
        case retry
    }

    let result: Result
    let sentence: String

    static let unavailable = RemoteActionResult(result: .unavailable,
                                                sentence: "Couldn't do that from here. Open it on your Mac.")
    /// A write with no answer, and nothing to settle it by.
    static let unsure = RemoteActionResult(result: .unknown, sentence: RemoteDecide.Sentence.unsure)
    /// A write with no answer that the session shows did not land.
    static let notThere = RemoteActionResult(result: .retry, sentence: RemoteDecide.Sentence.notThere)
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
        case .photo: RemotePhotoRoute.bodyLimit // Phase 4 photos
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
    /// `{"id","decision":"allow"|"deny"}`, and optionally the `kind` the phone
    /// showed. // Phase 4 permissions
    case permission(id: String, allow: Bool, kind: String?)
    /// What to change in the plan the Mac's window showed (by its version):
    /// never parsed from the phone, only made by the reply window.
    case planFeedback(version: String, text: String, intentID: String)

    static let answerLimit = 1_000
    /// The most a message may be when it comes from the phone: `parse`'s, the
    /// new-session and photo bodies' (`NewSessionRequest`, `PhotoRequest`) and
    /// the phone page's own text boxes. The phone's request bodies are kept
    /// small (DESIGN.md, Actions), and this is what they allow for.
    static let messageLimit = 4_000
    /// The most a message may be when it is made on the Mac, where the person
    /// is at a keyboard and no small body is waiting: Ask Another Model's Send
    /// to Session, Quick Start (and the menu bar's field, and Shortcuts), and
    /// the reply window's changes to a plan. The in-page writer allows the
    /// same (`SessionWriterScript.builder`); the phone's routes never get more
    /// than `messageLimit`, because `parse` and its kin refuse first.
    static let macMessageLimit = 32_000

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
            guard let given = root["answers"] as? [String: Any] else { return nil }
            var answers: [String: String] = [:]
            for (question, value) in given {
                guard let text = Pick.string(value) else { return nil }
                answers[question] = text
            }
            return checkedAnswer(toolID: toolID, answers: answers)
        case .message:
            guard let text = Pick.string(root["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text.unicodeScalars.count <= messageLimit, !PhotoText.hasReference(text),
                  let id = Pick.string(root["id"]), isUUIDv4(id) else { return nil }
            return .message(text: text, intentID: id)
        case .permission: // Phase 4 permissions
            return parsePermission(root)
        }
    }

    /// An answer, checked as every answer is, whoever sends it: the phone's
    /// body (`parse`) or the Mac's reply window (Lab/QuestionReply.swift). One
    /// to ten questions, each named, each answer trimmed, not empty and at
    /// most 1,000 characters. Nil for anything else.
    static func checkedAnswer(toolID: String, answers: [String: String]) -> RemoteActionRequest? {
        guard !toolID.isEmpty, toolID.unicodeScalars.count <= SessionProjection.Limit.toolID,
              (1...SessionProjection.Limit.questions).contains(answers.count) else { return nil }
        var checked: [String: String] = [:]
        for (question, value) in answers {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty, question.unicodeScalars.count <= SessionProjection.Limit.question,
                  !text.isEmpty, text.unicodeScalars.count <= answerLimit else { return nil }
            checked[question] = text
        }
        return .answer(toolID: toolID, answers: checked)
    }

    /// What to change in a plan, from the Mac's reply window: the text
    /// trimmed, 1 to 32,000 characters (`macMessageLimit`) with none of the
    /// UI's reference prefixes (as a phone message), the plan's version and a
    /// uuid v4 intent id. Nil for anything else.
    static func checkedPlanFeedback(version: String, text: String, intentID: String) -> RemoteActionRequest? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlanCheck.isVersionID(version), !text.isEmpty, text.unicodeScalars.count <= macMessageLimit,
              !PhotoText.hasReference(text), isUUIDv4(intentID) else { return nil }
        return .planFeedback(version: version, text: text, intentID: intentID)
    }

    /// The answer to a body `parse` turned away: 400 `{"error":"reference"}`
    /// when its text holds one of the UI's reference prefixes (the phone
    /// explains that one), else the plain 400.
    static func refusal(body: Data) -> RemoteActionReply {
        let text = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]).flatMap { Pick.string($0["text"]) }
        return text.map(PhotoText.hasReference) == true ? PhotoRefusal.reference.reply : .badRequest
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
        static let actionsOff = "Actions are off in Capsid's Settings"
        static let unreadable = "Capsid can't read this session"
        static let answerFirst = "Answer its question first"
        static let planFirst = "Approve or revise the plan on your Mac"
        /// A parked session whose wait is a permission request, not a question. // Phase 4 permissions
        static let requestFirst = "Answer its request first"
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
        // Phase 4 permissions: a helper's question waits on the person, and the composer says so.
        if mode.word != nil, read.permission?.isHelperAsk == true { mode = .blocked(RemotePermission.Why.helperAsked) }
        if case .blocked(var why) = mode {
            // Phase 4 permissions: a parked request is not "its question".
            if read.status == "awaiting_user_response", read.question == nil, let waiting = read.permission {
                why = waiting.isHelperAsk ? RemotePermission.Why.helperAsked : Why.requestFirst
            }
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
        static let revising = "Sent. Claude is revising the plan."
        static let planGone = "The plan isn't waiting for you any more."
        /// While a write that got no answer is looked for.
        static let checking = "Not sure that went through. Checking…"
        /// The read after an unanswered write found it did not land.
        static let notThere = "That didn't go through. Try again."
        /// The read couldn't tell either.
        static let unsure = "Not sure that went through. Look at it on your Mac before you try again."
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

    // MARK: What to change in a plan

    /// The plan still waits, not approved, at the very version the window
    /// showed; the fresh read names the agent and the project. Then a message
    /// with no `plan_mode`, which the daemon takes as a change request: the
    /// plan stays unapproved and Claude revises it.
    static func planFeedback(_ request: RemoteActionRequest, session: String, fresh: SessionProjection?) -> Step {
        guard case .planFeedback(let version, let text, let intentID) = request, let fresh else {
            return .answer(.unavailable)
        }
        guard fresh.status == "awaiting_plan_approval" else {
            return .answer(RemoteActionResult(result: .changed, sentence: Sentence.planGone))
        }
        guard PlanCheck.versionToRead(fresh.planFrame) == version else {
            return .answer(RemoteActionResult(result: .changed, sentence: Sentence.planChanged))
        }
        guard let agent = fresh.agentName, let project = fresh.projectID else { return .answer(.unavailable) }
        return .write(.planFeedback(frame: session, agent: agent, projectID: project, text: text, intentID: intentID))
    }

    static func planFeedbackSent(_ reply: RemoteWriteResult?) -> RemoteActionResult {
        guard let reply, reply.isJSON else { return .unavailable }
        switch (reply.status, reply.bodyStatus) {
        case (200, "accepted"?), (200, "already_delivered"?):
            return RemoteActionResult(result: .sent, sentence: Sentence.revising)
        case (200, "message_queued"?):
            return RemoteActionResult(result: .queued, sentence: Sentence.queued)
        case (429, _):
            return RemoteActionResult(result: .blocked, sentence: Sentence.tooManyQueued)
        default:
            return .unavailable
        }
    }

    // MARK: Message

    /// Only for `completed`/`success`, `processing`, `failed`/`cancelled`;
    /// to the agent and project the fresh read names, with `plan_mode`
    /// false. A read without a `project_id` sends nothing: `/api/request`
    /// without one is how the daemon starts a new project. `attachment` is for
    /// the photo flow alone: its text ends in the attachment line, which the
    /// writer accepts for no other message.
    static func message(_ request: RemoteActionRequest, session: String, fresh: SessionProjection?,
                        attachment: Bool = false) -> Step {
        guard case .message(let text, let intentID) = request, let fresh else { return .answer(.unavailable) }
        let mode = RemoteMessageMode(status: fresh.status)
        if case .blocked(let why) = mode { return .answer(RemoteActionResult(result: .blocked, sentence: why + ".")) }
        guard let agent = fresh.agentName, let project = fresh.projectID else { return .answer(.unavailable) }
        return .write(.message(frame: session, agent: agent, projectID: project, text: text, intentID: intentID,
                               attachment: attachment))
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
        // Phase 4 live
        /// The live read: whether the root works, its streaming text (when
        /// asked for) and its activity line (when asked for). Nil when it
        /// can't be read.
        var readLive: RemoteLive.Reader = { _, _, _, _ in nil }
        // Bounded writes
        /// The most one turn in a session's queue may take (`WriteDeadline.turn`).
        var turnLimit: Duration = WriteDeadline.turn()
        /// The most the read that settles an unknown write may take.
        var settleLimit: Duration = WriteDeadline.settleRead
        /// Waits out a deadline; tests stand in for the clock.
        var wait: @MainActor (Duration) async -> Void = WriteDeadline.sleep

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
                    return await WebContainer.shared.writeAnswer(write)
                },
                now: { Date() },
                lookup: { await RemoteBrowser.lookUp($0) }, // Phase 3 browse
                readLive: { id, activity, text, mayWait in // Phase 4 live
                    guard Demo.mode == nil else { return nil }
                    return (try? await WebContainer.shared.readLive(id, activity: activity, text: text, mayWait: mayWait)) ?? nil
                })
        }
    }

    private struct Entry {
        let at: Date
        let read: SessionProjection?
        /// The plan waiting on the root, when it could be read.
        let plan: PlanPreview?
    }

    private let dependencies: Dependencies
    /// Phase 4 live: what the live route keeps between asks.
    let live: RemoteLive
    /// The history pages read lately (HistoryPages.swift), let go with the rest below.
    let historyPages = HistoryPages()
    private var cache: [String: Entry] = [:]
    /// A read in flight, and the generation it started under.
    private var loading: [String: (task: Task<Entry, Never>, started: Int)] = [:]
    /// Bumped when an action may have changed the session: a read started
    /// before it isn't kept, nor handed out after the action.
    private var generation: [String: Int] = [:]
    /// The last turn in each session's queue: the next one waits for its
    /// task, and it is let go only once that task has ended (`runSerially`).
    private var acting: [String: (turn: SessionTurn, task: Task<Void, Never>)] = [:]
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
        live = RemoteLive(read: dependencies.readLive, now: dependencies.now, known: dependencies.known) // Phase 4 live
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
        // Whatever has been held 5 seconds goes at every ask, not only once
        // the asking pauses.
        dropExpired()
        if let cached = cache[id], cached.at <= now, now.timeIntervalSince(cached.at) < Self.cacheLifetime { return cached }
        if let reading = loading[id] {
            let entry = await reading.task.value
            // An action landed while it read: what it read is from before, so read again.
            return generation[id, default: 0] == reading.started ? entry : await self.entry(for: id)
        }
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
        loading[id] = (task, started)
        let entry = await task.value
        return generation[id, default: 0] == started ? entry : await self.entry(for: id)
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
        historyPages.forget(id)
    }

    // MARK: Acting

    /// One action from a paired device: actions on (403), within the
    /// device's limit (429), a session Bench knows (404), a body that fits
    /// (400); then `respond`.
    func act(_ action: RemoteAction, session id: String, device: String, body: Data) async -> RemoteActionReply {
        guard dependencies.actionsOn() else { return .actionsOff }
        guard limiter.allow(device, at: dependencies.now()) else { return .tooMany }
        guard await admitted(id) != nil else { return .notFound } // Phase 3 browse
        guard let request = RemoteActionRequest.parse(action, body: body) else {
            return action == .message ? RemoteActionRequest.refusal(body: body) : .badRequest
        }
        return .ok(await respond(request, session: id))
    }

    /// The part beneath every way of acting, the phone's routes and the Mac's
    /// reply window alike: one at a time per session, on the queue the photo
    /// flow shares, read the session afresh, decide, and only then write.
    /// What was held of the session is dropped once it is done. The phone's
    /// own gates (Settings → Phone, the device's limit, which sessions it may
    /// open) are `act`'s, so a reply from the Mac works with the phone off.
    ///
    /// A write that gets no answer is unknown: `checking` is called, the
    /// session is read once more, and the result says whether it landed
    /// (the same result the daemon's answer would have made), didn't (`.retry`)
    /// or can't be told (`.unknown`). Never sent again here. A turn that
    /// stalls ends as `.unknown` and the queue moves on.
    func respond(_ request: RemoteActionRequest, session id: String,
                 checking: (@MainActor () -> Void)? = nil) async -> RemoteActionResult {
        var result = RemoteActionResult.unsure
        var wrote = false
        let end = await runSerially(on: id, limit: dependencies.turnLimit) { [weak self] in
            if let self { result = await self.perform(request, session: id, checking: checking, leaving: { wrote = true }) }
            return .ok(result)
        }
        switch end {
        case .finished: return result
        // The turn ran out of time: if the write hadn't left, nothing was sent; if it had, it may have gone.
        case .stalled: return wrote ? .unsure : .notThere
        case .cancelled: return .unavailable
        }
    }

    /// The root frame as an action's check reads it, or with `full` its turns
    /// and the head of its permission requests too: what the Mac's card and
    /// reply window show before anything is answered. Nil when it can't be read.
    func readFrame(_ id: String, full: Bool = false) async -> SessionProjection? {
        await dependencies.read(id, full)
    }

    private func perform(_ request: RemoteActionRequest, session id: String,
                         checking: (@MainActor () -> Void)?, leaving: (@MainActor () -> Void)?) async -> RemoteActionResult {
        // Phase 4 permissions: an answer to a request reads the helpers' frames too (a full read).
        let fresh = await dependencies.read(id, request.isPermission)
        switch request {
        case .approve(let version):
            switch RemoteDecide.approve(version: version, session: id, fresh: fresh) {
            case .answer(let result): return result
            case .write(let write):
                return await settling(write, session: id, full: false, checking: checking, leaving: leaving,
                                      map: { RemoteDecide.approved($0) },
                                      settle: { RemoteDecide.settledApprove(version: version, fresh: $0) })
            }
        case .answer, .chooseForMe, .cancel:
            switch RemoteDecide.answer(request, session: id, fresh: fresh) {
            case .answer(let result): return result
            case .write(let write):
                let toolID: String
                switch request {
                case .answer(let id, _), .chooseForMe(let id), .cancel(let id): toolID = id
                default: return .unavailable
                }
                return await settling(write, session: id, full: false, checking: checking, leaving: leaving,
                                      map: { RemoteDecide.answered($0, request: request) },
                                      settle: { RemoteDecide.settledAnswer(toolID: toolID, fresh: $0) })
            }
        case .message:
            switch RemoteDecide.message(request, session: id, fresh: fresh) {
            case .answer(let result): return result
            case .write(let write):
                guard case .message(_, _, _, let text, _, _) = write else { return .unavailable }
                return await deliver(write, text: text, session: id, before: fresh, checking: checking, leaving: leaving).result
            }
        case .permission(let requestID, let allow, _): // Phase 4 permissions
            switch PermissionDecide.decide(request, session: id, fresh: fresh) {
            case .answer(let result): return result
            case .write(let write):
                return await settling(write, session: id, full: true, checking: checking, leaving: leaving,
                                      map: { PermissionDecide.answered($0, allow: allow) },
                                      settle: { PermissionDecide.settled(requestID: requestID, fresh: $0) })
            }
        case .planFeedback(let version, _, _):
            switch RemoteDecide.planFeedback(request, session: id, fresh: fresh) {
            case .answer(let result): return result
            case .write(let write):
                guard case .planFeedback(_, _, _, let text, let intent) = write else { return .unavailable }
                let since = dependencies.now()
                return await settling(write, session: id, full: true, checking: checking, leaving: leaving,
                                      map: { RemoteDecide.planFeedbackSent($0) },
                                      settle: { RemoteDecide.settledPlanFeedback(version: version, text: text, intent: intent,
                                                                                 since: since, fresh: $0) })
            }
        }
    }

    // MARK: Writing, and settling a write that got no answer (Bounded writes)

    /// The one place a write leaves for the daemon: not once the turn has been
    /// cancelled or given up on, and not again on its own. Nil when it didn't
    /// complete; `RemoteWriteResult.unknown` when it got no answer.
    /// `leaving` is called just before it goes, so that a turn which runs out
    /// of time can say whether anything was sent.
    func send(_ write: RemoteWrite, leaving: (@MainActor () -> Void)? = nil) async -> RemoteWriteResult? {
        guard !Task.isCancelled else { return nil }
        leaving?()
        return await dependencies.write(write)
    }

    /// A write, and its answer mapped by `map`; or, when it got none, `checking`
    /// and then one fresh read, mapped by `settle`.
    func settling(_ write: RemoteWrite, session id: String, full: Bool, checking: (@MainActor () -> Void)?,
                  leaving: (@MainActor () -> Void)? = nil,
                  map: (RemoteWriteResult?) -> RemoteActionResult,
                  settle: (SessionProjection?) -> RemoteActionResult) async -> RemoteActionResult {
        let reply = await send(write, leaving: leaving)
        guard reply?.isUnknown == true else { return map(reply) }
        // A turn that was given up on while the write was out has ended as unknown: it says and reads nothing more.
        guard !Task.isCancelled else { return .unsure }
        checking?()
        return settle(await settledRead(id, full: full))
    }

    /// A message write and what it came to: the daemon's answer, as `messaged`
    /// reads it, or the session as it reads now when there was none, looked
    /// at for this very message (its intent id, else its whole words and its
    /// files: `MessageSeen`). `text` is the request's words (attachment lines
    /// and all); `before` is the read the write was decided by. The reply
    /// comes back too, for a caller that reads a 409 as a repeat.
    func deliver(_ write: RemoteWrite, text: String, session id: String, before: SessionProjection?,
                 checking: (@MainActor () -> Void)? = nil,
                 leaving: (@MainActor () -> Void)? = nil) async -> (reply: RemoteWriteResult?, result: RemoteActionResult) {
        let since = dependencies.now()
        let reply = await send(write, leaving: leaving)
        guard reply?.isUnknown == true else { return (reply, RemoteDecide.messaged(reply, status: before?.status ?? "")) }
        guard !Task.isCancelled else { return (reply, .unsure) }
        checking?()
        let fresh = await settledRead(id, full: true)
        return (reply, RemoteDecide.settledMessage(text: text, intent: write.intentID, before: before, since: since, fresh: fresh))
    }

    /// The session read once more, for at most `settleLimit`; nil when it
    /// can't be read in time.
    func settledRead(_ id: String, full: Bool) async -> SessionProjection? {
        let read = dependencies.read
        let raced = await WriteDeadline.race(dependencies.settleLimit, wait: dependencies.wait, cancel: .ignore) { () async -> SessionProjection? in
            await read(id, full)
        }
        if case .finished(let projection) = raced { return projection }
        return nil
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
                     more: @escaping @MainActor (String) -> SessionProjection? = { _ in nil },
                     live: DemoLive = DemoLive()) -> RemoteSessions { // Phase 4 live
        RemoteSessions(dependencies: Dependencies(
            actionsOn: { RemoteSessions.actionsSetting() },
            known: known,
            cardPlan: cardPlan,
            read: { id, turns in
                guard let read = (reads[id] ?? more(id)).map(live.settled) else { return nil } // Phase 4 permissions
                return turns ? read : read.withoutTurns
            },
            readPlan: { _ in nil },
            write: { write in
                switch write {
                case .message(let frame, _, _, _, _, _) where (reads[frame] ?? more(frame))?.status == "processing":
                    RemoteWriteResult(status: 200, bodyStatus: "message_queued")
                case .answer, .cancel:
                    RemoteWriteResult(status: 200, bodyStatus: "accepted", remaining: 0)
                case .permission(_, let requestID, _, _): // Phase 4 permissions
                    live.answer(requestID)
                default:
                    RemoteWriteResult(status: 200, bodyStatus: "accepted")
                }
            },
            now: now,
            lookup: { lookup($0) },
            readLive: { id, activity, text, _ in live.read(id, activity: activity, text: text) })) // Phase 4 live
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
/// on). A row of Settings → Phone's options.
struct RemoteActionsToggle: View {
    @AppStorage(SettingsKey.remoteActions) private var actionsOn = true

    var body: some View {
        Toggle(isOn: $actionsOn) {
            Text("Let paired devices answer, approve and send messages")
            Text("Off, paired devices can still read your sessions, but only Open on Mac acts on them.")
        }
    }
}

// MARK: Photos (Phase 4)

// Phase 4 photos: what RemotePhotos.swift needs of the actions' own machinery,
// and no more.
extension RemoteSessions {
    /// The reads, the write and the clock the actions use.
    var photoDependencies: Dependencies { dependencies }

    /// Runs `work` as one of this session's actions: after the ones before
    /// it on the same queue `act` uses, and with what was held of the session
    /// dropped once it is done. The reply of the turn, `stalled`'s when it ran
    /// out of time (unknown, unless the caller knows nothing was sent) and
    /// `.unavailable` when it was cancelled before it began.
    func actSerially(on id: String, limit: Duration? = nil, stalled: @MainActor () -> RemoteActionReply = { .ok(.unsure) },
                     _ work: @escaping @MainActor () async -> RemoteActionReply) async -> RemoteActionReply {
        switch await runSerially(on: id, limit: limit ?? dependencies.turnLimit, work) {
        case .finished(let reply): reply
        case .stalled: stalled()
        case .cancelled: .ok(.unavailable)
        }
    }

    /// How a turn in a session's queue ended.
    enum TurnEnd: Sendable {
        case finished(RemoteActionReply)
        /// It didn't finish within `limit`: the queue moved on without it, and
        /// what it was doing is cancelled (and sends nothing more, `send`).
        case stalled
        /// Its caller was cancelled before it began: it never ran.
        case cancelled
    }

    /// One turn of a session's queue: it waits for the turns before it (each
    /// of which ends, at the latest, at its own `limit`), runs `work` for at
    /// most `limit`, and lets the next begin. A caller that is cancelled while
    /// it waits its turn never has one; once `work` has begun, the cancellation
    /// reaches it as `Task.isCancelled`, to stop at its next step, and the turn
    /// is waited for: what it has sent can't be taken back.
    ///
    /// The caller and the queue are let go separately. A caller cancelled
    /// while it waits is answered at once, but its turn keeps its place, still
    /// waiting for the one before it, and ends (writing nothing) only after
    /// that one; so the turn behind it still waits for everything ahead. The
    /// queue forgets a turn only when its own task has ended.
    func runSerially(on id: String, limit: Duration,
                     _ work: @escaping @MainActor () async -> RemoteActionReply) async -> TurnEnd {
        let previous = acting[id]?.task
        let turn = SessionTurn()
        let wait = dependencies.wait
        let task = Task { @MainActor [weak self] in
            defer { self?.ended(turn, on: id) }
            _ = await previous?.value
            guard !Task.isCancelled else {
                turn.settle(.cancelled)
                self?.forget(id)
                return
            }
            turn.began = true
            let raced = await WriteDeadline.race(limit, wait: wait, cancel: .propagate) { await work() }
            switch raced {
            case .finished(let reply): turn.settle(.finished(reply))
            case .timedOut: turn.settle(.stalled)
            case .cancelled: turn.settle(.cancelled)
            }
            self?.forget(id)
        }
        acting[id] = (turn, task)
        return await withTaskCancellationHandler {
            await turn.wait()
        } onCancel: {
            task.cancel()
            Task { @MainActor in turn.giveUpWaiting() }
        }
    }

    /// A turn's task has ended: the queue lets it go, unless another has
    /// joined behind it since (that one is the tail now, and waits on it).
    private func ended(_ turn: SessionTurn, on id: String) {
        if acting[id]?.turn === turn { acting[id] = nil }
    }
}

/// One turn's ending, for the caller that waits on it.
@MainActor
private final class SessionTurn {
    var began = false
    private var end: RemoteSessions.TurnEnd?
    private var waiting: CheckedContinuation<RemoteSessions.TurnEnd, Never>?

    func settle(_ value: RemoteSessions.TurnEnd) {
        guard end == nil else { return }
        end = value
        waiting?.resume(returning: value)
        waiting = nil
    }

    func wait() async -> RemoteSessions.TurnEnd {
        if let end { return end }
        return await withCheckedContinuation { waiting = $0 }
    }

    /// Its caller was cancelled: a turn that hasn't begun ends here, at once.
    func giveUpWaiting() {
        if !began { settle(.cancelled) }
    }
}
