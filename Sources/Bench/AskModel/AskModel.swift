// AskModel.swift — what the Ask Another Model window holds and does (DESIGN.md,
// Ask another model): the question (the session's last one, or the selection
// it was opened from), whether the conversation so far goes with it, the ask
// itself with its deadline and Cancel, the answer, Copy, and Send to Session.
//
// The question and the conversation are read with the history reader the
// reference window uses (Remote/HistoryReader.swift), through the reading gate,
// one page of the session's newest rows: no new page hook. What is sent is what
// the window shows: the question as it stands in the field and, with the switch
// on, the turns listed under it.
//
// Send to Session is the bounded path every write to a session takes
// (`RemoteSessions.respond`): the session's own queue, a fresh read, the
// message rule, a deadline, an unknown outcome settled by one more read, and
// never a second send on its own. The answer goes as the user's next message,
// after one line naming the model, with an intent id kept while the words are
// the same, so a second press after a lost reply is the daemon's own repeat.
import AppKit
import Foundation

// MARK: The rules

/// What the window is about: a session, and what the question starts from.
struct AskSubject: Equatable, Sendable {
    let sessionID: String
    let title: String
    let projectName: String
    /// The selection it was opened from, or the reply's question in a
    /// reference window. Nil: the session's last question is read.
    let seed: String?
}

/// One text turn of the conversation, as the window lists it and sends it.
struct AskTurn: Equatable, Sendable, Identifiable {
    /// Its row in the session's history.
    let id: Int
    let role: HistoryItem.Role
    let text: String
}

enum AskRules {
    /// The conversation goes as the newest 10 turns at most…
    static let maxTurns = 10
    /// …and 12,000 characters at most, all told.
    static let maxCharacters = 12_000
    /// The question, at most.
    static let maxQuestion = 32_000

    /// From the newest page of a session's history: the last message of yours
    /// with words in it (its row, its text as the page has it, and whether the
    /// page cut it), and the text turns before it, yours and Claude's (and what
    /// Claude sent you mid-run), as `conversation` caps them. Steps, plans,
    /// questions and files are left out, and so is everything after your last
    /// message: Claude's reply to it is never sent.
    static func read(_ page: HistoryPage) -> (question: (row: Int, text: String, cut: Bool)?, before: [AskTurn]) {
        var turns: [(turn: AskTurn, cut: Bool)] = []
        for item in page.items {
            switch item {
            case .turn(let i, let role, _, let text, let cut, _):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                turns.append((AskTurn(id: i, role: role, text: text), cut))
            case .toYou(let i, let text, _, let cut):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                turns.append((AskTurn(id: i, role: .claude, text: text), cut))
            default:
                continue
            }
        }
        guard let last = turns.lastIndex(where: { $0.turn.role == .you }) else {
            return (nil, conversation(turns.map(\.turn)))
        }
        let question = turns[last]
        return ((question.turn.id, question.turn.text, question.cut), conversation(turns[..<last].map(\.turn)))
    }

    /// The newest turns that fit: 10 at most, 12,000 characters at most; a
    /// turn that doesn't fit whole ends the list (an older one is never sent
    /// without the newer ones). Oldest first.
    static func conversation(_ turns: [AskTurn]) -> [AskTurn] {
        var kept: [AskTurn] = []
        var characters = 0
        for turn in turns.reversed() {
            guard kept.count < maxTurns, characters + turn.text.count <= maxCharacters else { break }
            kept.append(turn)
            characters += turn.text.count
        }
        return kept.reversed()
    }

    /// The chat that is sent: the turns (with the switch on), then the question.
    static func chat(question: String, conversation: [AskTurn]) -> [ChatTurn] {
        conversation.map { ChatTurn(role: $0.role == .you ? .user : .assistant, text: $0.text) }
            + [ChatTurn(role: .user, text: question)]
    }

    /// The question as it is asked: trimmed, and nil when empty or over
    /// `maxQuestion`.
    static func question(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxQuestion else { return nil }
        return trimmed
    }

    /// The message Send to Session posts: one line naming the model, a blank
    /// line, then the answer.
    static func message(answer: String, model: String) -> String {
        "Another model (\(model)) answered:\n\n" + answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether that message can go as a message: what the phone's route and
    /// the writer accept (4,000 characters, none of the page's reference
    /// prefixes).
    enum SendCheck: Equatable {
        case ok(String)
        /// Over the 4,000: its length.
        case tooLong(Int)
        /// It holds text Claude Science would read as a file or a session.
        case reference
    }

    static func sendable(answer: String, model: String) -> SendCheck {
        let text = message(answer: answer, model: model)
        let count = text.unicodeScalars.count
        if count > RemoteActionRequest.messageLimit { return .tooLong(count) }
        if PhotoText.hasReference(text) { return .reference }
        return .ok(text)
    }

    /// The line under Send to Session when the answer can't go.
    static func unsendable(_ check: SendCheck) -> String? {
        switch check {
        case .ok: nil
        case .tooLong(let count):
            "Too long to send as a message (\(count.formatted()) characters; the most is \(RemoteActionRequest.messageLimit.formatted())). Copy it instead."
        case .reference: "It holds text Claude Science reads as a file reference, so it can\u{2019}t be sent. Copy it instead."
        }
    }

    /// What the bounded path's answer means, in the window's words, and
    /// whether the message went.
    static func outcome(_ result: RemoteActionResult) -> (sentence: String, sent: Bool) {
        switch result.result {
        case .sent: ("Sent to the session.", true)
        case .queued: (RemoteDecide.Sentence.queued, true)
        case .resumed: (RemoteDecide.Sentence.resumed, true)
        case .blocked, .changed: (result.sentence, false)
        case .retry: (RemoteDecide.Sentence.notThere, false)
        case .unknown: ("Not sure that went through. Look at the session before you send it again.", false)
        default: ("Couldn\u{2019}t send it. Copy it, and paste it in the session.", false)
        }
    }

    /// The log's word for that outcome.
    static func word(_ result: RemoteActionResult) -> String {
        switch result.result {
        case .sent: "sent"
        case .queued: "queued"
        case .resumed: "resumed"
        case .blocked, .changed: "not now"
        case .retry: "didn't go through"
        case .unknown: "not sure"
        default: "couldn't"
        }
    }

    /// "Another model: asked, 812 characters, with 6 turns, answered in 9 s".
    /// Counts only: never the words, the model or the session.
    static func logLine(characters: Int, turns: Int, seconds: Int, failure: AnotherModelFailure?) -> String {
        let with = turns > 0 ? ", with \(turns) turns" : ""
        guard let failure else { return "Another model: asked, \(characters) characters\(with), answered in \(seconds) s" }
        if failure == .cancelled { return "Another model: asked, \(characters) characters\(with), cancelled after \(seconds) s" }
        return "Another model: asked, \(characters) characters\(with), failed after \(seconds) s, \(failure.word)"
    }
}

// MARK: The window's model

@MainActor
struct AskDependencies {
    /// The session's newest history page; nil when it can't be read.
    var readPage: @MainActor (_ sessionID: String) async -> HistoryPage?
    /// One row's text whole (a cut question); nil when it can't be read.
    var readTurn: @MainActor (_ sessionID: String, _ row: Int) async -> HistoryTurn?
    /// The model chosen in Settings; nil when none is.
    var modelName: @MainActor () -> String?
    /// The host what is asked goes to.
    var host: @MainActor () -> String
    /// The deadline an ask has.
    var limit: Duration
    /// Asks the chosen model.
    var ask: @MainActor (_ chat: [ChatTurn]) async -> Result<String, AnotherModelFailure>
    /// A message to the session, by the bounded path; `checking` is called
    /// while an unknown outcome is read for.
    var send: @MainActor (_ request: RemoteActionRequest, _ sessionID: String,
                          _ checking: @escaping @MainActor () -> Void) async -> RemoteActionResult
    /// Puts the text on the pasteboard; false when it couldn't.
    var pasteboard: @MainActor (String) -> Bool
    /// The answer as the window draws it.
    var render: @MainActor (String) -> NSAttributedString
    var clock: @MainActor () -> ContinuousClock.Instant = { .now }
    var log: @MainActor (String) -> Void

    static func live() -> AskDependencies {
        ReadingGate.shared.start()
        let model = AnotherModel.shared
        return AskDependencies(
            readPage: { id in
                guard Demo.mode == nil else { return nil }
                let read = try? await ReadingGate.shared.perform {
                    try await WebContainer.shared.readHistory(id, before: nil, nonce: ArtifactReadAbort.makeNonce())
                }
                if case .page(let page) = read { return page }
                return nil
            },
            readTurn: { id, row in
                guard Demo.mode == nil else { return nil }
                let outcome = try? await ReadingGate.shared.perform {
                    try await WebContainer.shared.readTurn(id, index: row, nonce: ArtifactReadAbort.makeNonce())
                }
                if case .turn(let turn) = outcome { return turn }
                return nil
            },
            modelName: { model.model },
            host: { model.host },
            limit: model.askLimit,
            ask: { chat in await model.ask(chat) },
            send: { request, id, checking in
                guard Demo.mode == nil else { return .unavailable }
                return await RemoteSessions.shared.respond(request, session: id, checking: checking)
            },
            pasteboard: { text in
                let board = NSPasteboard.general
                board.clearContents()
                return board.setString(text, forType: .string)
            },
            render: { AnswerMarkdown.render($0, style: .reference).text },
            log: AnotherModel.writeLog)
    }
}

@MainActor
final class AskModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case asking
        case answered
        case failed(String)
        case cancelled
    }

    /// Reading the session for the question, or the conversation.
    enum Reading: Equatable {
        case unread, reading, read, unreadable
    }

    enum Sending: Equatable {
        case idle
        case sending
        /// The write got no answer: the session is read to see if it landed.
        case checking
        case done(String)
        case failed(String)
    }

    let subject: AskSubject
    @Published var question: String {
        didSet { if question != oldValue, !settingQuestion { edited = true } }
    }
    @Published var includeConversation = false {
        didSet { if includeConversation, reading == .unread || reading == .unreadable { readSession() } }
    }
    @Published private(set) var reading: Reading = .unread
    /// The turns sent with the switch on.
    @Published private(set) var conversation: [AskTurn] = []
    @Published private(set) var phase: Phase = .ready
    /// The answer as it came, and drawn.
    @Published private(set) var answer: String?
    @Published private(set) var rendered = NSAttributedString()
    /// The model that answered, and how long it took.
    @Published private(set) var answeredBy: String?
    @Published private(set) var seconds: Int?
    @Published private(set) var sending: Sending = .idle
    @Published private(set) var copied = false

    private let dependencies: AskDependencies
    /// The user typed in the field: a read landing late never overwrites it.
    private var edited = false
    private var settingQuestion = false
    private var readTask: Task<Void, Never>?
    private var askTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var ledger = IntentLedger()

    init(subject: AskSubject, dependencies: AskDependencies) {
        self.subject = subject
        self.dependencies = dependencies
        question = subject.seed.map { String($0.prefix(AskRules.maxQuestion)) } ?? ""
    }

    /// The window opened: the session's last question is read, unless the
    /// window was opened from a selection or a reply.
    func open() {
        if subject.seed == nil { readSession() }
    }

    /// A seed for a window already open (the same session, opened again from a
    /// selection): the field takes it, unless a question is being asked.
    func reseed(_ seed: String?) {
        guard let seed, phase != .asking else { return }
        setQuestion(String(seed.prefix(AskRules.maxQuestion)))
        edited = true
    }

    var modelName: String? { dependencies.modelName() }
    var host: String { dependencies.host() }

    var canAsk: Bool {
        phase != .asking && AskRules.question(question) != nil && modelName != nil
            && !(includeConversation && reading == .reading)
    }

    /// The characters a question sends, all told (for the log).
    private func characters(_ chat: [ChatTurn]) -> Int { chat.reduce(0) { $0 + $1.text.count } }

    // MARK: Reading the session

    private func readSession() {
        guard readTask == nil else { return }
        reading = .reading
        let id = subject.sessionID, wantsQuestion = subject.seed == nil
        readTask = Task { [weak self] in
            guard let self else { return }
            defer { readTask = nil }
            guard let page = await dependencies.readPage(id), !Task.isCancelled else {
                if !Task.isCancelled { reading = .unreadable }
                return
            }
            let found = AskRules.read(page)
            conversation = found.before
            if wantsQuestion, let asked = found.question, !edited {
                var text = asked.text
                if asked.cut, let whole = await dependencies.readTurn(id, asked.row), whole.i == asked.row, !whole.text.isEmpty {
                    text = whole.text
                }
                guard !Task.isCancelled else { return }
                if !edited { setQuestion(String(text.prefix(AskRules.maxQuestion))) }
            }
            reading = .read
        }
    }

    private func setQuestion(_ text: String) {
        settingQuestion = true
        question = text
        settingQuestion = false
    }

    // MARK: Asking

    func ask() {
        guard canAsk, let text = AskRules.question(question) else { return }
        let turns = includeConversation && reading == .read ? conversation : []
        let chat = AskRules.chat(question: text, conversation: turns)
        let model = modelName
        let started = dependencies.clock()
        phase = .asking
        sending = .idle
        askTask = Task { [weak self] in
            guard let self else { return }
            let result = await dependencies.ask(chat)
            let seconds = Int((dependencies.clock() - started).components.seconds)
            switch result {
            case .success(let words):
                answer = words
                rendered = dependencies.render(words)
                answeredBy = model
                self.seconds = seconds
                copied = false
                phase = .answered
                dependencies.log(AskRules.logLine(characters: characters(chat), turns: turns.count, seconds: seconds, failure: nil))
            case .failure(let failure):
                phase = failure == .cancelled ? .cancelled : .failed(failure.sentence(host: host, limit: dependencies.limit))
                dependencies.log(AskRules.logLine(characters: characters(chat), turns: turns.count, seconds: seconds, failure: failure))
            }
            askTask = nil
        }
    }

    /// Ends the ask under way; nothing more comes from it.
    func cancel() {
        askTask?.cancel()
    }

    // MARK: The answer

    func copy() {
        guard let answer else { return }
        copied = dependencies.pasteboard(answer)
    }

    /// Whether the answer can go to the session, and if not, why.
    var sendCheck: AskRules.SendCheck? {
        guard let answer, let answeredBy else { return nil }
        return AskRules.sendable(answer: answer, model: answeredBy)
    }

    var canSend: Bool {
        guard case .ok = sendCheck else { return false }
        switch sending {
        case .sending, .checking: return false
        case .done: return false
        case .idle, .failed: return phase == .answered
        }
    }

    /// Posts the answer into the session as your next message, by the bounded
    /// path. Once: a second press while it is under way does nothing, and a
    /// press after it went does nothing either. After "didn't go through" or
    /// "not sure", a press is the person's own retry, with the same intent id.
    func sendToSession() {
        guard canSend, case .ok(let text)? = sendCheck else { return }
        let intent = ledger.id(for: subject.sessionID + "\n" + text)
        guard let request = Self.message(text: text, intent: intent) else { return }
        sending = .sending
        let id = subject.sessionID
        sendTask = Task { [weak self] in
            guard let self else { return }
            let result = await dependencies.send(request, id) { [weak self] in self?.sending = .checking }
            let outcome = AskRules.outcome(result)
            if outcome.sent {
                ledger.sent()
                sending = .done(outcome.sentence)
            } else {
                sending = .failed(outcome.sentence)
            }
            dependencies.log("Another model: sent the answer to the session, \(AskRules.word(result))")
            sendTask = nil
        }
    }

    /// The message request: the phone's own shape, the text checked as the
    /// window checked it.
    static func message(text: String, intent: String) -> RemoteActionRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= RemoteActionRequest.messageLimit,
              !PhotoText.hasReference(trimmed), RemoteActionRequest.isUUIDv4(intent) else { return nil }
        return .message(text: trimmed, intentID: intent)
    }

    // MARK: Closing

    /// The window closed: the reads and the ask end. A send under way goes on
    /// to its end (it may already have left), and only its log line is left.
    func close() {
        readTask?.cancel()
        askTask?.cancel()
    }
}
