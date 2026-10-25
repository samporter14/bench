// AskModel.swift — what the Ask Another Model window holds and does (DESIGN.md,
// Ask another model): the question (the session's last one, or the selection
// it was opened from), whether the conversation so far goes with it, the ask
// itself with its deadline and Cancel, the answer, Copy, and Send to Session.
//
// The answer streams in: words arrive as the other model writes them, and the
// Markdown is drawn again at most ten times a second (`AskRules.renderEvery`).
// A stream that ends before its end (Cancel, a deadline, an error, a lost
// connection) keeps its words on screen, marked, with Copy and without Send to
// Session: only a finished answer is sent as "answered".
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

    /// Whether that message can go as a message: what the Mac's own sends and
    /// the writer accept (32,000 characters, `RemoteActionRequest.macMessageLimit`,
    /// none of the page's reference prefixes).
    enum SendCheck: Equatable {
        case ok(String)
        /// Over the 32,000: its length.
        case tooLong(Int)
        /// It holds text Claude Science would read as a file or a session.
        case reference
        /// The answer stopped before its end (Cancel, a deadline, an error):
        /// only part of it came, and part of an answer isn't sent as one.
        case partial
    }

    static func sendable(answer: String, model: String) -> SendCheck {
        let text = message(answer: answer, model: model)
        let count = text.unicodeScalars.count
        if count > RemoteActionRequest.macMessageLimit { return .tooLong(count) }
        if PhotoText.hasReference(text) { return .reference }
        return .ok(text)
    }

    /// The line under Send to Session when the answer can't go.
    static func unsendable(_ check: SendCheck) -> String? {
        switch check {
        case .ok: nil
        case .tooLong(let count):
            "Too long to send as a message (\(count.formatted()) characters; the most is \(RemoteActionRequest.macMessageLimit.formatted())). Copy it instead."
        case .reference: "It holds text Claude Science reads as a file reference, so it can\u{2019}t be sent. Copy it instead."
        case .partial: "Only part of the answer came, so it can\u{2019}t be sent."
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

    /// Words are drawn again at most this often while an answer streams in.
    static let renderEvery: Duration = .milliseconds(100)

    /// The quiet line over the words, in the same place from the first word to
    /// the last, so nothing moves when it ends: "Answering…", then "Answered in
    /// 9 s", or "Stopped after 14 s", or "Cut off after 14 s". "Answered" names
    /// the model only when it isn't the one named above (the choice changed in
    /// Settings since).
    static func caption(phase: AskModel.Phase, seconds: Int?, answeredBy: String?, model: String?) -> String {
        let span = seconds.map { $0 < 1 ? "under a second" : "\($0) s" }
        switch phase {
        case .streaming: return "Answering\u{2026}"
        case .cancelled: return "Stopped" + (span.map { " after \($0)" } ?? "")
        case .failed: return "Cut off" + (span.map { " after \($0)" } ?? "")
        default:
            let time = span.map { " in \($0)" } ?? ""
            guard let by = answeredBy, by != model else { return "Answered" + time }
            return "\(by) answered" + time
        }
    }

    /// "Another model: asked, 812 characters, with 6 turns, first word in 2 s,
    /// answered in 9 s". Counts only: never the words, the model or the
    /// session. The first word's time is there only when words arrived.
    static func logLine(characters: Int, turns: Int, seconds: Int, firstWord: Int? = nil, failure: AnotherModelFailure?) -> String {
        let with = turns > 0 ? ", with \(turns) turns" : ""
        let first = firstWord.map { ", first word in \($0) s" } ?? ""
        let head = "Another model: asked, \(characters) characters\(with)\(first)"
        guard let failure else { return "\(head), answered in \(seconds) s" }
        if failure == .cancelled { return "\(head), cancelled after \(seconds) s" }
        return "\(head), failed after \(seconds) s, \(failure.word)"
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
    /// Asks the chosen model; `progress` hears the words as they arrive. The
    /// answer is whole, or the words that came and why it stopped.
    var ask: @MainActor (_ chat: [ChatTurn], _ progress: @escaping @MainActor (AskProgress) -> Void) async -> AnotherModelAnswer
    /// A message to the session, by the bounded path; `checking` is called
    /// while an unknown outcome is read for.
    var send: @MainActor (_ request: RemoteActionRequest, _ sessionID: String,
                          _ checking: @escaping @MainActor () -> Void) async -> RemoteActionResult
    /// Puts the text on the pasteboard; false when it couldn't.
    var pasteboard: @MainActor (String) -> Bool
    /// The answer as the window draws it.
    var render: @MainActor (String) -> NSAttributedString
    var clock: @MainActor () -> ContinuousClock.Instant = { .now }
    /// The wait that spaces the drawing of a streaming answer.
    var wait: @MainActor (Duration) async -> Void = WriteDeadline.sleep
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
            ask: { chat, progress in await model.ask(chat, progress: progress) },
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
        /// Asked; nothing of the answer has come yet (the model may be thinking).
        case asking
        /// Words are arriving.
        case streaming
        case answered
        /// It stopped before its end, or never began: the sentence says why.
        /// Words that came before are kept (`isPartial`).
        case failed(String)
        /// Cancel was pressed; words that came before are kept.
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
    /// The answer as it came, and drawn. While it streams, the words so far as
    /// of the last drawing; after a stop, the words that came.
    @Published private(set) var answer: String?
    @Published private(set) var rendered = NSAttributedString()
    /// Only reasoning has come so far: the model is thinking. Its words are never shown.
    @Published private(set) var thinking = false
    /// The model that answered, and how long it took (or ran before it stopped).
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
    /// Every word that has arrived; `answer` and `rendered` follow it, a tenth of a second apart.
    private var streamed = ""
    private var lastDrawn: ContinuousClock.Instant?
    /// How soon the next drawing may come: a tenth of a second, or longer when drawing took long.
    private var drawEvery = AskRules.renderEvery
    private var drawTask: Task<Void, Never>?
    /// Seconds from the question to the first word, for the log.
    private var firstWord: Int?

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
        guard let seed, !isAsking else { return }
        setQuestion(String(seed.prefix(AskRules.maxQuestion)))
        edited = true
    }

    var modelName: String? { dependencies.modelName() }
    var host: String { dependencies.host() }

    /// A question is out: nothing of the answer yet, or words arriving.
    var isAsking: Bool { phase == .asking || phase == .streaming }

    /// Words are on screen that are not a whole answer: it stopped, or failed, partway.
    var isPartial: Bool {
        switch phase {
        case .failed, .cancelled: answer != nil
        default: false
        }
    }

    var canAsk: Bool {
        !isAsking && AskRules.question(question) != nil && modelName != nil
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
        thinking = false
        sending = .idle
        copied = false
        answer = nil
        answeredBy = nil
        seconds = nil
        rendered = NSAttributedString()
        streamed = ""
        firstWord = nil
        lastDrawn = nil
        drawEvery = AskRules.renderEvery
        drawTask?.cancel()
        drawTask = nil
        askTask = Task { [weak self] in
            guard let self else { return }
            let result = await dependencies.ask(chat) { [weak self] progress in
                self?.arrived(progress, since: started)
            }
            let seconds = Int((dependencies.clock() - started).components.seconds)
            ended(result, model: model, seconds: seconds, log: AskRules.logLine(
                characters: characters(chat), turns: turns.count, seconds: seconds, firstWord: firstWord, failure: result.failure))
            askTask = nil
        }
    }

    /// Ends the ask under way (or the stream): the words that came stay.
    func cancel() {
        askTask?.cancel()
    }

    // MARK: Words arriving

    private func arrived(_ progress: AskProgress, since started: ContinuousClock.Instant) {
        guard isAsking else { return }
        switch progress {
        case .thinking:
            if phase == .asking { thinking = true }
        case .words(let delta):
            streamed += delta
            if phase == .asking {
                // White space alone is no answer yet.
                guard streamed.contains(where: { !$0.isWhitespace }) else { return }
                phase = .streaming
                thinking = false
                firstWord = Int((dependencies.clock() - started).components.seconds)
            }
            drawSoon()
        }
    }

    /// Draws the words so far now, if a tenth of a second has passed since the
    /// last time; else once it has. The first words are drawn at once.
    private func drawSoon() {
        guard drawTask == nil else { return }
        let now = dependencies.clock()
        if let lastDrawn, lastDrawn + drawEvery > now {
            let remaining = lastDrawn + drawEvery - now
            drawTask = Task { [weak self] in
                guard let self else { return }
                await dependencies.wait(remaining)
                guard !Task.isCancelled else { return }
                drawTask = nil
                draw()
            }
        } else {
            draw()
        }
    }

    private func draw() {
        let began = dependencies.clock()
        answer = streamed
        rendered = dependencies.render(streamed)
        let done = dependencies.clock()
        lastDrawn = done
        // A very long answer takes longer to draw: the next drawing waits three times as long as this
        // one took (a second at most), so drawing never takes the window over.
        drawEvery = min(.seconds(1), max(AskRules.renderEvery, (done - began) * 3))
    }

    /// The ask is over, whole or in part. The words that came are drawn in
    /// full before anything else is shown, so an ending never shows fewer
    /// words than the answer holds.
    private func ended(_ result: AnotherModelAnswer, model: String?, seconds: Int, log: String) {
        drawTask?.cancel()
        drawTask = nil
        thinking = false
        streamed = result.text
        let hasWords = !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasWords {
            draw()
            answeredBy = model
            self.seconds = seconds
        } else {
            answer = nil
            rendered = NSAttributedString()
        }
        switch result.failure {
        case nil where hasWords:
            phase = .answered
        case nil:
            phase = .failed(AnotherModelFailure.unreadable.sentence(host: host, limit: dependencies.limit))
        case .cancelled?:
            phase = .cancelled
        case let failure?:
            phase = .failed(failure.sentence(host: host, limit: dependencies.limit))
        }
        dependencies.log(log)
    }

    // MARK: The answer

    /// Copies what came, as it came: the whole answer, or after a stop the
    /// part that arrived (its words are on screen). Not while words arrive.
    func copy() {
        guard let answer, !isAsking else { return }
        copied = dependencies.pasteboard(answer)
    }

    /// Whether the answer can go to the session, and if not, why.
    var sendCheck: AskRules.SendCheck? {
        guard let answer, let answeredBy else { return nil }
        if isPartial { return .partial }
        guard phase == .answered else { return nil }
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

    /// The message request: the phone's own shape (a message to `respond`), the
    /// text checked as the window checked it, at the Mac's limit.
    static func message(text: String, intent: String) -> RemoteActionRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= RemoteActionRequest.macMessageLimit,
              !PhotoText.hasReference(trimmed), RemoteActionRequest.isUUIDv4(intent) else { return nil }
        return .message(text: trimmed, intentID: intent)
    }

    // MARK: Closing

    /// The window closed: the reads and the ask end. A send under way goes on
    /// to its end (it may already have left), and only its log line is left.
    func close() {
        readTask?.cancel()
        askTask?.cancel()
        drawTask?.cancel()
    }
}
