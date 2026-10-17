// QuestionReply.swift — answering a session's question from its card (DESIGN.md,
// Lab, "Answering a question from the card"). The card shows the question and
// a Reply button; Reply opens a small window of its own (Lab/ReplyWindow.swift),
// since the panel is never key and can't take typing. What is sent goes the way
// the phone's answers go, beneath the phone's own gates: `RemoteSessions.respond`
// reads the session afresh, checks it still asks the very question shown, and
// only then writes (Remote/RemoteActions.swift). So a reply from the Mac works
// with Capsid on your phone off, and an answer to a question that changed or was
// answered elsewhere is never sent.
//
// Nothing here logs what a question or an answer says.
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "reply")

typealias QuestionAsk = SessionProjection.Ask

// MARK: The draft, and the answer it makes

/// What the person has chosen and typed for one question request, by the
/// question's place in it. Kept in memory while the session waits, so a
/// failed send or a closed window doesn't lose it.
struct ReplyDraft: Equatable, Sendable {
    /// Option indexes picked, per question.
    var picks: [Int: [Int]] = [:]
    /// Whether "Other…" is on, per question.
    var otherOn: [Int: Bool] = [:]
    /// What was typed for "Other…", per question.
    var other: [Int: String] = [:]

    /// A fresh draft: a question with no options to pick from has its typed
    /// answer on from the start, as there is nothing else to choose.
    init(for ask: QuestionAsk? = nil) {
        for (index, item) in (ask?.items ?? []).enumerated() where item.options.isEmpty {
            otherOn[index] = true
        }
    }

    /// The phone's `pickOption`: one choice replaces the last and turns
    /// "Other…" off; with several allowed it toggles.
    mutating func pick(_ option: Int, in question: Int, multi: Bool) {
        let current = picks[question] ?? []
        if multi {
            picks[question] = current.contains(option) ? current.filter { $0 != option } : current + [option]
        } else {
            picks[question] = [option]
            otherOn[question] = false
        }
    }

    /// "Other…" on or off; on, a single choice is cleared.
    mutating func setOther(_ on: Bool, in question: Int, multi: Bool) {
        otherOn[question] = on
        if on, !multi { picks[question] = [] }
    }

    /// The draft for a re-read ask with the same request id: what still
    /// fits it is kept (picks within its options), the rest dropped.
    func fitted(to ask: QuestionAsk) -> ReplyDraft {
        var kept = ReplyDraft(for: ask)
        for (index, item) in ask.items.enumerated() {
            kept.picks[index] = (picks[index] ?? []).filter { item.options.indices.contains($0) }
            if let on = otherOn[index] { kept.otherOn[index] = on || item.options.isEmpty }
            kept.other[index] = other[index]
        }
        return kept
    }
}

/// The answer a draft makes, by the phone's own rule (`answerOf` in
/// RemoteWeb/app.js), so the Mac and the phone send the same words.
enum QuestionAnswers {
    /// One question's answer: with several allowed, the picked labels in the
    /// options' order and then any typed text, joined by ", "; with one,
    /// the typed text when "Other…" is on, else the pick. "" when there is none.
    static func text(_ item: SessionProjection.Question, at index: Int, draft: ReplyDraft) -> String {
        let picked = (draft.picks[index] ?? []).filter { item.options.indices.contains($0) }.sorted()
            .map { item.options[$0].label }
        let otherOn = draft.otherOn[index] ?? false
        let typed = otherOn ? (draft.other[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if item.multi { return (picked + (typed.isEmpty ? [] : [typed])).joined(separator: ", ") }
        return otherOn ? typed : (picked.first ?? "")
    }

    /// Every question has an answer.
    static func isComplete(_ ask: QuestionAsk, draft: ReplyDraft) -> Bool {
        ask.items.indices.allSatisfy { !text(ask.items[$0], at: $0, draft: draft).isEmpty }
    }

    /// The request the draft makes, checked as the phone's are
    /// (`RemoteActionRequest.checkedAnswer`): nil while a question is
    /// unanswered or an answer is too long.
    static func request(_ ask: QuestionAsk, draft: ReplyDraft) -> RemoteActionRequest? {
        guard isComplete(ask, draft: draft) else { return nil }
        var answers: [String: String] = [:]
        for (index, item) in ask.items.enumerated() {
            answers[item.question] = text(item, at: index, draft: draft)
        }
        return RemoteActionRequest.checkedAnswer(toolID: ask.toolID, answers: answers)
    }

    /// Whether an answer is over the 1,000 characters any answer may be.
    static func isTooLong(_ ask: QuestionAsk, draft: ReplyDraft) -> Bool {
        ask.items.indices.contains {
            text(ask.items[$0], at: $0, draft: draft).unicodeScalars.count > RemoteActionRequest.answerLimit
        }
    }
}

// MARK: What the card shows

/// A needs-input card's state, by session: every wait but a plan's, which
/// `PlanApprover` reads.
enum QuestionCardState: Equatable, Sendable {
    /// Reading the session: "Loading the question…".
    case loading
    /// The root's own question, which the card shows with Reply.
    case ready(QuestionAsk)
    /// A permission request of the root's or a helper's, at the head of the
    /// queue: what it asks, with Allow Once or Deny when the Mac's table
    /// (`RemotePermission.decideOnMac`) offers them, else why not.
    case permission(PermissionRequest)
    /// Waiting on something the card can't answer: a question asked mid-run,
    /// or a request whose shape Capsid doesn't know. The card offers Open in
    /// Capsid.
    case unsupported
    /// The read failed: Open and Later, as before; read again a while later.
    case unavailable

    /// The pure decision from a fresh read of the session, with its helpers'
    /// requests: the root's own question first, then the head of the queue.
    static func from(_ read: SessionProjection?) -> QuestionCardState {
        guard let read else { return .unavailable }
        if read.status == "awaiting_user_response", let ask = read.question, !ask.items.isEmpty {
            return .ready(ask)
        }
        if let request = read.permission { return .permission(request) }
        return .unsupported
    }

    /// Whether a card waiting for this reason is read here: all but a plan's.
    static func reads(_ reason: WaitingReason?) -> Bool {
        reason != .plan
    }

    /// What Claude said last before it asked, from the read's turns: shown
    /// above the question, so a question that refers back can be answered.
    static func context(_ read: SessionProjection?) -> String? {
        guard let text = read?.turns?.last(where: { $0.role == .claude })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// "3 choices", "Pick any of 4", "Type an answer", "2 questions": what the
    /// card says under the question, never what it asks.
    static func shape(_ ask: QuestionAsk) -> String {
        guard ask.items.count == 1, let item = ask.items.first else { return "\(ask.items.count) questions" }
        if item.options.isEmpty { return "Type an answer" }
        let count = item.options.count
        return item.multi ? "Pick any of \(count)" : (count == 1 ? "1 choice" : "\(count) choices")
    }
}

/// Where a reply stands, in its window or on its card.
enum ReplyPhase: Equatable, Sendable {
    /// Choosing and typing.
    case editing
    /// Sent to the session; waiting for its answer. Nothing can be sent twice.
    case sending
    /// It went: Claude Science took it.
    case sent(String)
    /// Not sent, because the question isn't the one shown any more; the window
    /// shows the new one when there is one to answer.
    case changed(String)
    /// Not sent, for another reason: the draft is kept, and Send tries again.
    case failed(String)
    /// Nothing to answer any more: answered elsewhere, or the session stopped
    /// waiting.
    case closed(String)

    var canSend: Bool {
        switch self {
        case .editing, .changed, .failed: true
        default: false
        }
    }
}

/// One open reply: where it goes, what it answers, the draft and its phase.
struct QuestionReply: Equatable, Sendable {
    /// The destination, shown at the top of the window: its title and project.
    var session: SessionStatus
    var ask: QuestionAsk
    var draft: ReplyDraft
    var phase: ReplyPhase
    /// What Claude said last before asking (`QuestionCardState.context`).
    var context: String? = nil
}

/// A permission request being answered from the card or its window.
struct PermissionReply: Equatable, Sendable {
    var session: SessionStatus
    var request: PermissionRequest
    var phase: ReplyPhase
    var context: String? = nil

    /// What may be done with it here, and why not when nothing may.
    var decision: RemotePermission.Decision { RemotePermission.decideOnMac(request) }
}

/// What to change in a plan that waits, typed in the reply window.
struct PlanReply: Equatable, Sendable {
    var session: SessionStatus
    /// The plan as the card showed it: its version is what the send checks.
    var plan: PlanPreview
    var text: String
    /// Kept while the text is the same, so a retry after a lost reply is
    /// recognised by the daemon and not sent twice.
    var intentID: String
    var phase: ReplyPhase
}

/// What Send, Choose for Me and Cancel Question send.
enum ReplyKind: Sendable {
    case answer, chooseForMe, cancel
}

/// What a reply window shows for a session.
enum ReplyMode: Equatable, Sendable {
    case question, permission, plan
}

// MARK: The replier

/// Reads the needs-input card on top (its question, or its permission
/// request), keeps the open replies, and sends them through
/// `RemoteSessions.respond`. One read per card, as `PlanApprover` does: a
/// card's state goes with the card. A plan's card is `PlanApprover`'s; what to
/// change in a plan is sent from here, through the same core.
@MainActor
final class QuestionReplier: ObservableObject {
    static let shared = QuestionReplier(model: .shared, dependencies: .live())

    struct Dependencies {
        /// "Show plans, questions and requests on the card" and "Show a card"
        /// are on, and no demo runs.
        var isEnabled: @MainActor () -> Bool
        /// The page is up, so the session can be read.
        var isReady: @MainActor () -> Bool
        /// The root frame with its turns and the head of its permission
        /// requests (`RemoteSessions.readFrame(_:full:)`).
        var read: @MainActor (String) async -> SessionProjection?
        /// The phone's actions beneath their gates (`RemoteSessions.respond`).
        var respond: @MainActor (RemoteActionRequest, String) async -> RemoteActionResult
        var now: @MainActor () -> Date = { Date() }
        /// The plan a plan's card shows, when it has one (`PlanApprover`).
        var plan: @MainActor (String) -> PlanPreview? = { _ in nil }
        /// A fresh uuid v4, lower case: the intent id of what to change in a plan.
        var newIntentID: @MainActor () -> String = { UUID().uuidString.lowercased() }
        /// Waits out a notification's time limit; tests stand in for the clock.
        /// Returns early when its task is cancelled.
        var wait: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

        static func live() -> Dependencies {
            Dependencies(
                isEnabled: {
                    let defaults = UserDefaults.standard
                    return Demo.mode == nil && defaults.bool(forKey: SettingsKey.showPlansOnCard)
                        && defaults.bool(forKey: SettingsKey.showCards)
                },
                isReady: { WebContainer.shared.status == .ready },
                read: { await RemoteSessions.shared.readFrame($0, full: true) },
                respond: { await RemoteSessions.shared.respond($0, session: $1) },
                plan: { PlanApprover.shared.state(for: $0)?.revisable })
        }
    }

    enum Sentence {
        static let changed = RemoteDecide.Sentence.questionChanged
        static let failed = "Couldn't send it. Your answer is still here: try again, or open the session in Capsid."
        static let stoppedWaiting = "This session isn't waiting for an answer any more."
        static let tooLong = "An answer can be at most 1,000 characters."
        static let couldntCheck = "The question may have changed, and Capsid couldn't read it again. Send checks it first."
        static let requestChanged = PermissionDecide.Sentence.changed
        static let requestHandled = PermissionDecide.Sentence.alreadyHandled
        static let requestGone = "This session isn't waiting for this any more."
        static let requestCouldntCheck = "The request may have changed, and Capsid couldn't read it again. Look at it in Capsid."
        static let requestFailed = "Couldn't send it. Try again, or open the session in Capsid."
        static let planGone = RemoteDecide.Sentence.planGone
        static let planChanged = "The plan changed. Look at the new one in Capsid: what you wrote is still here to copy."
        static let feedbackFailed = "Couldn't send it. What you wrote is still here: try again, or open the session in Capsid."
        static let feedbackTooLong = "At most 4,000 characters."
        static let feedbackReference = "This reads like a file reference, which can't be sent from here. Reword it, or send it in Capsid."
    }

    /// By session id: only sessions whose needs-input card is in the queue.
    @Published private(set) var cards: [String: QuestionCardState] = [:]
    /// By session id: what Claude said last, from the card's read.
    @Published private(set) var contexts: [String: String] = [:]
    /// By session id: the replies opened with Reply, while their session waits.
    @Published private(set) var replies: [String: QuestionReply] = [:]
    /// By session id: permission requests being answered.
    @Published private(set) var permissionReplies: [String: PermissionReply] = [:]
    /// By session id: what to change in a waiting plan.
    @Published private(set) var planReplies: [String: PlanReply] = [:]

    static let retryAfter: TimeInterval = 15

    /// Sessions whose reply window is open: their reply is kept while it
    /// shows, sent or not (`windowOpened`, `windowClosed`).
    private(set) var openWindows: Set<String> = []

    private let model: LabModel
    private let dependencies: Dependencies
    /// Card reads under way, by session; each one takes itself out when done.
    private var tasks: [String: Task<Void, Never>] = [:]
    private var loadTokens: [String: UUID] = [:]
    /// Sends under way, by session: each answers with the reply's phase once done.
    private var sending: [String: Task<ReplyPhase?, Never>] = [:]
    private var unavailableSince: [String: Date] = [:]
    /// `--demo card`'s made-up session: answering it sends nothing anywhere.
    private var demoSessions: Set<String> = []
    private var subscriptions = Set<AnyCancellable>()

    init(model: LabModel, dependencies: Dependencies) {
        self.model = model
        self.dependencies = dependencies
    }

    func cardState(for sessionID: String) -> QuestionCardState? { cards[sessionID] }

    /// Follows the cards, what waits, the settings and the page. Never in a demo.
    func start() {
        guard subscriptions.isEmpty, Demo.mode == nil else { return }
        let center = NotificationCenter.default
        Publishers.Merge4(
            model.$cards.map { _ in () },
            model.$waiting.map { _ in () },
            center.publisher(for: UserDefaults.didChangeNotification).map { _ in () },
            WebContainer.shared.$status.map { _ in () })
            // @Published publishes before the value changes: look after it has.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &subscriptions)
    }

    /// Drops what no longer has a card or a waiting session to go with, and
    /// reads the card on top if it has nothing yet. Internal for tests.
    func sync() {
        let enabled = dependencies.isEnabled()
        var readCards: Set<String> = []
        for case .needsInput(let session) in model.cards where QuestionCardState.reads(session.waitingReason) {
            readCards.insert(session.id)
        }
        for id in Array(cards.keys) where !demoSessions.contains(id) && (!enabled || !readCards.contains(id)) {
            forgetCard(id)
        }
        // What was kept for a card that is gone goes too, whatever took the card.
        for id in Array(contexts.keys) where cards[id] == nil { contexts[id] = nil }
        for id in Array(unavailableSince.keys) where cards[id] == nil { unavailableSince[id] = nil }
        for id in Array(tasks.keys) where cards[id] == nil { tasks.removeValue(forKey: id)?.cancel(); loadTokens[id] = nil }
        // A reply outlives its card (Later, ×), but not the session's wait. An
        // open window still says why; any other is let go (`prune`).
        let asking = asking()
        for (id, reply) in replies where !asking.contains(id) && !Self.isSettled(reply.phase) {
            replies[id]?.phase = .closed(Sentence.stoppedWaiting)
        }
        for (id, reply) in permissionReplies where !asking.contains(id) && !Self.isSettled(reply.phase) {
            permissionReplies[id]?.phase = .closed(Sentence.requestGone)
        }
        let planning = planning()
        for (id, reply) in planReplies where !planning.contains(id) && !Self.isSettled(reply.phase) {
            planReplies[id]?.phase = .closed(Sentence.planGone)
        }
        for id in Set(replies.keys).union(permissionReplies.keys).union(planReplies.keys) { prune(id) }
        guard case .needsInput(let session)? = model.cards.first else { return }
        prepare(session.id)
    }

    /// Reads a card's session when it has nothing yet (or its last read failed
    /// a while ago): the card on top, or the next one the reply window steps
    /// to. True when there is, or soon will be, something to show.
    @discardableResult
    func prepare(_ id: String) -> Bool {
        guard dependencies.isEnabled(), dependencies.isReady(), let session = cardSession(id),
              QuestionCardState.reads(session.waitingReason) else { return cards[id] != nil }
        switch cards[id] {
        case nil:
            load(id)
        case .unavailable?:
            if dependencies.now().timeIntervalSince(unavailableSince[id] ?? .distantPast) >= Self.retryAfter {
                load(id)
            }
        default:
            break
        }
        return cards[id] != nil
    }

    private static func isSettled(_ phase: ReplyPhase) -> Bool {
        switch phase {
        case .sending, .sent, .closed: true
        default: false
        }
    }

    private func load(_ id: String) {
        guard PlanCheck.isFrameID(id) else {
            cards[id] = .unsupported
            return
        }
        cards[id] = .loading
        let token = UUID()
        loadTokens[id] = token
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let read = await self.dependencies.read(id)
            // Done: this read is no longer under way, whatever it found.
            defer {
                if self.loadTokens[id] == token {
                    self.tasks[id] = nil
                    self.loadTokens[id] = nil
                }
            }
            let state = QuestionCardState.from(read)
            guard !Task.isCancelled, self.cards[id] == .loading else { return }
            self.cards[id] = state
            self.contexts[id] = QuestionCardState.context(read)
            self.unavailableSince[id] = state == .unavailable ? self.dependencies.now() : nil
        }
    }

    /// A card's state and everything read for it.
    private func forgetCard(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        loadTokens[id] = nil
        cards[id] = nil
        contexts[id] = nil
        unavailableSince[id] = nil
    }

    /// Sessions waiting for anything a card here answers, and those waiting for a plan.
    private func asking() -> Set<String> {
        Set(model.waiting.filter { QuestionCardState.reads($0.waitingReason) }.map(\.id))
    }

    private func planning() -> Set<String> {
        Set(model.waiting.filter { $0.waitingReason == .plan }.map(\.id))
    }

    // MARK: What is kept

    /// The reply window for a session opened: its reply is kept while it
    /// shows, whatever its phase.
    func windowOpened(_ sessionID: String) {
        openWindows.insert(sessionID)
    }

    /// It closed: what it showed is kept only if it is still a draft for a
    /// session that waits, or still being sent.
    func windowClosed(_ sessionID: String) {
        openWindows.remove(sessionID)
        closeReply(sessionID)
    }

    /// Who owns a reply, for one session: its open window, a send under way,
    /// a draft (editing, changed or failed) for a session still waiting, or
    /// its card while the card is still up, which shows how it ended (a
    /// request handled elsewhere: its note and Open instead of Allow and
    /// Deny). Anything else is let go: one sent or closed with no window or
    /// card to show it, and a draft whose session no longer waits.
    private func prune(_ id: String) {
        guard !openWindows.contains(id), !demoSessions.contains(id) else { return }
        let cardShows = cards[id] != nil
        func keeps(_ phase: ReplyPhase, waiting: Bool) -> Bool {
            switch phase {
            case .sending: true
            case .editing, .changed, .failed: waiting || cardShows
            case .sent, .closed: cardShows
            }
        }
        let asking = model.waiting.contains { $0.id == id && QuestionCardState.reads($0.waitingReason) }
        let planning = model.waiting.contains { $0.id == id && $0.waitingReason == .plan }
        if let reply = replies[id], !keeps(reply.phase, waiting: asking) { replies[id] = nil }
        if let reply = permissionReplies[id], !keeps(reply.phase, waiting: asking) { permissionReplies[id] = nil }
        if let reply = planReplies[id], !keeps(reply.phase, waiting: planning) { planReplies[id] = nil }
    }

    // MARK: Which reply

    /// Opens whatever the session's card can be answered with here: its
    /// question, its permission request, or (`plan`) what to change in its
    /// plan. False when there is nothing to answer from here.
    @discardableResult
    func begin(_ sessionID: String, plan: Bool = false) -> Bool {
        if plan { return beginPlanFeedback(sessionID) }
        switch cards[sessionID] {
        case .ready?: return beginReply(sessionID)
        case .permission?: return beginPermission(sessionID)
        default: return false
        }
    }

    /// What the window shows for a session: the reply that goes with its
    /// card's state, or whichever it has.
    func mode(_ sessionID: String) -> ReplyMode? {
        switch cards[sessionID] {
        case .ready? where replies[sessionID] != nil: return .question
        case .permission? where permissionReplies[sessionID] != nil: return .permission
        default: break
        }
        if planReplies[sessionID] != nil { return .plan }
        if replies[sessionID] != nil { return .question }
        if permissionReplies[sessionID] != nil { return .permission }
        return nil
    }

    /// The other sessions whose card a reply window can step to, in the
    /// queue's order: every needs-input card but a plan's.
    func othersWaiting(besides sessionID: String) -> [String] {
        model.cards.compactMap { card in
            guard case .needsInput(let session) = card, session.id != sessionID,
                  QuestionCardState.reads(session.waitingReason) else { return nil }
            return session.id
        }
    }

    // MARK: Questions

    /// Reply: the question the card shows, with the draft kept from before
    /// when it is still the same request. False when there is nothing to
    /// answer from here.
    @discardableResult
    func beginReply(_ sessionID: String) -> Bool {
        guard case .ready(let ask)? = cards[sessionID], let session = waitingSession(sessionID) else {
            return false
        }
        if var reply = replies[sessionID], reply.ask.toolID == ask.toolID, reply.phase != .sending {
            reply.session = session
            reply.ask = ask
            reply.draft = reply.draft.fitted(to: ask)
            reply.context = contexts[sessionID]
            if case .closed = reply.phase { reply.phase = .editing }
            if case .sent = reply.phase { reply.phase = .editing }
            replies[sessionID] = reply
        } else if replies[sessionID]?.phase != .sending {
            replies[sessionID] = QuestionReply(session: session, ask: ask, draft: ReplyDraft(for: ask), phase: .editing,
                                               context: contexts[sessionID])
        }
        return true
    }

    /// The window's edits.
    func updateDraft(_ sessionID: String, _ change: (inout ReplyDraft) -> Void) {
        guard var reply = replies[sessionID], reply.phase.canSend else { return }
        change(&reply.draft)
        replies[sessionID] = reply
    }

    /// Whether Send can go now: a phase that allows it, and a whole answer.
    func canSend(_ sessionID: String) -> Bool {
        guard let reply = replies[sessionID], reply.phase.canSend else { return false }
        return QuestionAnswers.request(reply.ask, draft: reply.draft) != nil
    }

    /// Sends, once: only from a phase that allows it, which it leaves at
    /// once, so a second press sends nothing. The send's task answers with
    /// the reply's phase when it is done.
    @discardableResult
    func submit(_ sessionID: String, _ kind: ReplyKind = .answer) -> Task<ReplyPhase?, Never>? {
        guard var reply = replies[sessionID], reply.phase.canSend, sending[sessionID] == nil else { return nil }
        let request: RemoteActionRequest?
        switch kind {
        case .answer: request = QuestionAnswers.request(reply.ask, draft: reply.draft)
        case .chooseForMe: request = .chooseForMe(toolID: reply.ask.toolID)
        case .cancel: request = .cancel(toolID: reply.ask.toolID)
        }
        guard let request else { return nil }
        reply.phase = .sending
        replies[sessionID] = reply
        if let fake = fakeSend(sessionID, { $0.replies[sessionID]?.phase = .sent(RemoteDecide.Sentence.answered) }) {
            return fake
        }
        let toolID = reply.ask.toolID
        let task = Task { [weak self] () -> ReplyPhase? in
            guard let self else { return nil }
            let result = await self.dependencies.respond(request, sessionID)
            await self.finish(sessionID, toolID: toolID, result: result)
            return self.done(sessionID, phase: self.replies[sessionID]?.phase)
        }
        sending[sessionID] = task
        return task
    }

    /// A send is over: it is no longer under way, and what nothing owns any
    /// more is let go. Answers with the phase it ended in.
    private func done(_ id: String, phase: ReplyPhase?) -> ReplyPhase? {
        sending[id] = nil
        prune(id)
        return phase
    }

    /// An answer chosen in a Mac notification (`NotificationRules.QuestionActions`):
    /// sent as Send sends it, through the same check of the question's id,
    /// and answered with how this send ended (nil when nothing could start).
    /// It waits for this send alone. A draft that didn't go is kept while the
    /// session waits, so the window can show it; a sent one is let go.
    @discardableResult
    func answerFromNotification(_ sessionID: String, ask: QuestionAsk, draft: ReplyDraft) async -> ReplyPhase? {
        guard sending[sessionID] == nil, replies[sessionID]?.phase != .sending,
              let session = waitingSession(sessionID) else { return nil }
        replies[sessionID] = QuestionReply(session: session, ask: ask, draft: draft, phase: .editing,
                                           context: contexts[sessionID])
        guard dependencies.isReady() else {
            replies[sessionID]?.phase = .failed(Sentence.failed)
            return replies[sessionID]?.phase
        }
        guard let send = submit(sessionID) else { return replies[sessionID]?.phase }
        return await send.value
    }

    /// The question a Mac notification offers answers for: the card's read
    /// when there is one, else one read of its own, within `limit` whichever
    /// it is. Nil with the card setting off, the page down, the limit passed,
    /// or anything but a root question to answer. Waiting on the card's own
    /// read never cancels it (the card still needs it); a read of its own
    /// that loses to the limit is cancelled.
    func askForNotification(_ sessionID: String, within limit: Duration = .seconds(4)) async -> QuestionAsk? {
        guard dependencies.isEnabled(), dependencies.isReady(), PlanCheck.isFrameID(sessionID) else { return nil }
        if case .ready(let ask)? = cards[sessionID] { return ask }
        if cards[sessionID] == .loading, let shared = tasks[sessionID] {
            guard await firstOf(within: limit, { await shared.value; return true }) == true,
                  case .ready(let ask)? = cards[sessionID] else { return nil }
            return ask
        }
        let read: SessionProjection?? = await firstOf(within: limit) { () async -> SessionProjection? in
            await self.dependencies.read(sessionID)
        }
        guard let read else { return nil }
        let state = QuestionCardState.from(read)
        guard case .ready(let ask) = state else { return nil }
        // Kept for its card, with what Claude said, which then needs no read of its own.
        if cards[sessionID] == nil, cardSession(sessionID) != nil {
            cards[sessionID] = state
            contexts[sessionID] = QuestionCardState.context(read)
        }
        return ask
    }

    /// The work's answer, or nil once `limit` passes first or the caller is
    /// cancelled: exactly once. The loser is cancelled at once (the work's
    /// task when the limit wins, the timer when the work does), so nothing
    /// is left waiting for it.
    private func firstOf<Value: Sendable>(within limit: Duration,
                                         _ work: @escaping @MainActor () async -> Value) async -> Value? {
        let deadline = Deadline<Value>()
        let wait = dependencies.wait
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                deadline.continuation = continuation
                deadline.work = Task { @MainActor in deadline.finish(await work()) }
                deadline.timer = Task { @MainActor in
                    await wait(limit)
                    deadline.finish(nil)
                }
            }
        } onCancel: {
            Task { @MainActor in deadline.finish(nil) }
        }
    }

    /// The window was closed. A reply that went, or has nothing left to
    /// answer, is let go; any other keeps its draft for the next Reply.
    func closeReply(_ sessionID: String) {
        if let reply = replies[sessionID], Self.isDone(reply.phase) { replies[sessionID] = nil }
        if let reply = permissionReplies[sessionID], Self.isDone(reply.phase) { permissionReplies[sessionID] = nil }
        if let reply = planReplies[sessionID], Self.isDone(reply.phase) { planReplies[sessionID] = nil }
        prune(sessionID)
    }

    private static func isDone(_ phase: ReplyPhase) -> Bool {
        switch phase {
        case .sent, .closed: true
        default: false
        }
    }

    // MARK: Permission requests

    /// The request the card shows, kept with its phase. The card's own
    /// buttons start here too, without a window.
    @discardableResult
    func beginPermission(_ sessionID: String) -> Bool {
        guard case .permission(let request)? = cards[sessionID], let session = waitingSession(sessionID) else {
            return false
        }
        if var reply = permissionReplies[sessionID], reply.phase != .sending {
            if reply.request.id != request.id || Self.isDone(reply.phase) { reply.phase = .editing }
            reply.session = session
            reply.request = request
            reply.context = contexts[sessionID]
            permissionReplies[sessionID] = reply
        } else if permissionReplies[sessionID] == nil {
            permissionReplies[sessionID] = PermissionReply(session: session, request: request, phase: .editing,
                                                           context: contexts[sessionID])
        }
        return true
    }

    /// Allow Once or Deny, once, and only what the Mac's table offers for the
    /// request shown. The answer is the phone's (`PermissionDecide`): the
    /// request read afresh, still the head and the same, then `resolve-input`
    /// with no scope, so an allow is for this once.
    @discardableResult
    func decide(_ sessionID: String, allow: Bool) -> Task<ReplyPhase?, Never>? {
        if permissionReplies[sessionID] == nil || cards[sessionID].map(Self.isPermission) == true {
            beginPermission(sessionID)
        }
        guard var reply = permissionReplies[sessionID], reply.phase.canSend, sending[sessionID] == nil else { return nil }
        let decision = reply.decision
        guard allow ? decision.canAllow : decision.canDeny else { return nil }
        reply.phase = .sending
        permissionReplies[sessionID] = reply
        let words = allow ? PermissionDecide.Sentence.allowed : PermissionDecide.Sentence.denied
        if let fake = fakeSend(sessionID, { $0.permissionReplies[sessionID]?.phase = .sent(words) }) { return fake }
        let request = RemoteActionRequest.permission(id: reply.request.id, allow: allow, kind: reply.request.kind)
        let shown = reply.request.id
        let task = Task { [weak self] () -> ReplyPhase? in
            guard let self else { return nil }
            let result = await self.dependencies.respond(request, sessionID)
            await self.finishPermission(sessionID, shown: shown, result: result)
            return self.done(sessionID, phase: self.permissionReplies[sessionID]?.phase)
        }
        sending[sessionID] = task
        return task
    }

    private static func isPermission(_ state: QuestionCardState) -> Bool {
        if case .permission = state { true } else { false }
    }

    private func finishPermission(_ id: String, shown: String, result: RemoteActionResult) async {
        guard var reply = permissionReplies[id], reply.phase == .sending else { return }
        log.notice("Permission from the card: \(result.result.rawValue, privacy: .public)")
        switch result.result {
        case .allowed, .denied:
            reply.phase = .sent(result.sentence)
            permissionReplies[id] = reply
            settleCard(id, session: reply.session)
        case .changed:
            let read = await dependencies.read(id)
            guard var current = permissionReplies[id], current.phase == .sending else { return }
            switch QuestionCardState.from(read) {
            case .permission(let request) where request.id != shown || result.sentence != Sentence.requestHandled:
                current.request = request
                current.phase = .changed(Sentence.requestChanged)
                if cards[id] != nil { cards[id] = .permission(request) }
            case .unavailable:
                current.phase = .changed(Sentence.requestCouldntCheck)
            case .ready(let ask):
                // Now it asks a question: the card shows that instead.
                current.phase = .closed(Sentence.requestHandled)
                if cards[id] != nil { cards[id] = .ready(ask) }
            default:
                current.phase = .closed(result.sentence == Sentence.requestHandled ? result.sentence : Sentence.requestGone)
            }
            permissionReplies[id] = current
        default:
            // A refusal names why in the phone's words; a failed write says try again.
            reply.phase = .failed(result.sentence == RemoteActionResult.unavailable.sentence
                ? Sentence.requestFailed : RemotePermission.onMac(result.sentence))
            permissionReplies[id] = reply
        }
    }

    // MARK: What to change in a plan

    /// Request Changes on a plan's card: the plan it shows, and a draft kept
    /// from before while it is the same plan.
    @discardableResult
    func beginPlanFeedback(_ sessionID: String) -> Bool {
        guard let plan = dependencies.plan(sessionID), let session = waitingSession(sessionID) else { return false }
        if var reply = planReplies[sessionID], reply.phase != .sending {
            if reply.plan.versionID != plan.versionID || Self.isDone(reply.phase) { reply.phase = .editing }
            reply.session = session
            reply.plan = plan
            planReplies[sessionID] = reply
        } else if planReplies[sessionID] == nil {
            planReplies[sessionID] = PlanReply(session: session, plan: plan, text: "",
                                               intentID: dependencies.newIntentID(), phase: .editing)
        }
        return true
    }

    /// The window's typing. New words get a new intent id; the same words
    /// sent again keep theirs.
    func updatePlanFeedback(_ sessionID: String, text: String) {
        guard var reply = planReplies[sessionID], reply.phase.canSend, reply.text != text else { return }
        reply.text = text
        reply.intentID = dependencies.newIntentID()
        planReplies[sessionID] = reply
    }

    func planFeedbackRequest(_ sessionID: String) -> RemoteActionRequest? {
        guard let reply = planReplies[sessionID] else { return nil }
        return RemoteActionRequest.checkedPlanFeedback(version: reply.plan.versionID, text: reply.text,
                                                       intentID: reply.intentID)
    }

    func canSendPlanFeedback(_ sessionID: String) -> Bool {
        guard let reply = planReplies[sessionID], reply.phase.canSend else { return false }
        return planFeedbackRequest(sessionID) != nil
    }

    /// Sends what to change, once, through the same core: the plan read
    /// afresh, still waiting at the version shown, then a message with no
    /// `plan_mode`.
    @discardableResult
    func submitPlanFeedback(_ sessionID: String) -> Task<ReplyPhase?, Never>? {
        guard var reply = planReplies[sessionID], reply.phase.canSend, sending[sessionID] == nil,
              let request = planFeedbackRequest(sessionID) else { return nil }
        reply.phase = .sending
        planReplies[sessionID] = reply
        if let fake = fakeSend(sessionID, { $0.planReplies[sessionID]?.phase = .sent(RemoteDecide.Sentence.revising) }) {
            return fake
        }
        let task = Task { [weak self] () -> ReplyPhase? in
            guard let self else { return nil }
            let result = await self.dependencies.respond(request, sessionID)
            self.finishPlanFeedback(sessionID, result: result)
            return self.done(sessionID, phase: self.planReplies[sessionID]?.phase)
        }
        sending[sessionID] = task
        return task
    }

    private func finishPlanFeedback(_ id: String, result: RemoteActionResult) {
        guard var reply = planReplies[id], reply.phase == .sending else { return }
        log.notice("Plan changes from the card: \(result.result.rawValue, privacy: .public)")
        switch result.result {
        case .sent, .queued:
            reply.phase = .sent(result.sentence)
            planReplies[id] = reply
            settleCard(id, session: reply.session)
        case .changed:
            reply.phase = .closed(result.sentence == Sentence.planGone ? Sentence.planGone : Sentence.planChanged)
            planReplies[id] = reply
        case .blocked:
            reply.phase = .failed(result.sentence)
            planReplies[id] = reply
        default:
            reply.phase = .failed(Sentence.feedbackFailed)
            planReplies[id] = reply
        }
    }

    // MARK: Demo and tests

    /// `--demo card`: a made-up question, ready, for a made-up session.
    func showDemo(sessionID: String, ask: QuestionAsk) {
        demoSessions.insert(sessionID)
        cards[sessionID] = .ready(ask)
    }

    /// `--demo card`: a made-up permission request, for a made-up session.
    func showDemo(sessionID: String, request: PermissionRequest) {
        demoSessions.insert(sessionID)
        cards[sessionID] = .permission(request)
    }

    /// `--demo plan`: what to change in its made-up plan sends nothing anywhere.
    func markDemo(_ sessionID: String) {
        demoSessions.insert(sessionID)
    }

    /// Waits until the reads and sends under way are done. For tests.
    func settled() async {
        var reads: Set<Task<Void, Never>> = []
        var sends: Set<Task<ReplyPhase?, Never>> = []
        while true {
            if let task = tasks.values.first(where: { !reads.contains($0) }) {
                await task.value
                reads.insert(task)
            } else if let task = sending.values.first(where: { !sends.contains($0) }) {
                _ = await task.value
                sends.insert(task)
            } else {
                return
            }
        }
    }

    /// How much is held, for tests: replies of each kind, contexts, card
    /// states, and reads and sends under way.
    var retained: (replies: Int, permissions: Int, plans: Int, contexts: Int, cards: Int, tasks: Int, sends: Int) {
        (replies.count, permissionReplies.count, planReplies.count, contexts.count, cards.count, tasks.count, sending.count)
    }

    // MARK: Parts

    /// A demo's send: the given result after a moment, with nothing sent
    /// anywhere. False for a real session.
    private func fakeSend(_ id: String, _ sent: @escaping @MainActor (QuestionReplier) -> Void) -> Task<ReplyPhase?, Never>? {
        guard demoSessions.contains(id) else { return nil }
        let task = Task { [weak self] () -> ReplyPhase? in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self else { return nil }
            sent(self)
            self.sending[id] = nil
            return nil
        }
        sending[id] = task
        return task
    }

    /// Answered: its card has done its job, and a reminder for it too.
    private func settleCard(_ id: String, session: SessionStatus) {
        if let card = model.cards.first(where: { $0.id == LabCard.needsInput(session).id }) {
            model.dismiss(card)
        }
        model.cancelReminder(id)
        forgetCard(id)
    }

    private func finish(_ id: String, toolID: String, result: RemoteActionResult) async {
        guard var reply = replies[id], reply.phase == .sending else { return }
        log.notice("Reply from the card: \(result.result.rawValue, privacy: .public)")
        switch result.result {
        case .sent:
            reply.phase = .sent(result.sentence)
            replies[id] = reply
            settleCard(id, session: reply.session)
        case .changed:
            // Read it again: a new question takes the old one's place; the
            // same one answered elsewhere has nothing left to answer.
            let read = await dependencies.read(id)
            let state = QuestionCardState.from(read)
            guard var current = replies[id], current.phase == .sending else { return }
            switch state {
            case .ready(let ask):
                current.draft = ask.toolID == toolID ? current.draft.fitted(to: ask) : ReplyDraft(for: ask)
                current.ask = ask
                current.context = QuestionCardState.context(read) ?? current.context
                current.phase = .changed(Sentence.changed)
                if cards[id] != nil { cards[id] = .ready(ask) }
            case .unavailable:
                // Not read: nothing is known of it now, so nothing is claimed. The
                // draft stays, and Send's own check reads it afresh first.
                current.phase = .changed(Sentence.couldntCheck)
            default:
                let answered = result.sentence == RemoteDecide.Sentence.alreadyAnswered
                current.phase = .closed(answered ? result.sentence : Sentence.stoppedWaiting)
            }
            replies[id] = current
        default:
            reply.phase = .failed(Sentence.failed)
            replies[id] = reply
        }
    }

    /// The session, as what waits or the card on top knows it.
    private func waitingSession(_ id: String) -> SessionStatus? {
        model.waiting.first(where: { $0.id == id }) ?? cardSession(id)
    }

    private func cardSession(_ id: String) -> SessionStatus? {
        for case .needsInput(let session) in model.cards where session.id == id { return session }
        return nil
    }
}

/// A wait with a time limit: the first of the work and the timer to finish
/// answers, exactly once, and cancels the other.
@MainActor
private final class Deadline<Value: Sendable> {
    var continuation: CheckedContinuation<Value?, Never>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?

    func finish(_ value: Value?) {
        guard let continuation else { return }
        self.continuation = nil
        work?.cancel()
        timer?.cancel()
        work = nil
        timer = nil
        continuation.resume(returning: value)
    }
}

extension PlanCardState {
    /// The plan Request Changes may be sent for: one shown and not yet being
    /// approved or approved.
    var revisable: PlanPreview? {
        switch self {
        case .ready(let preview), .problem(_, let preview): preview
        default: nil
        }
    }
}
