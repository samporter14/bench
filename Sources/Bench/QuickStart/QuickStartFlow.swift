// QuickStartFlow.swift — what Start and ⇧↩ do (DESIGN.md, Quick Start): start a
// session in a project, or send a message to the session in view, with files
// uploaded to the project first. It is the phone's own machinery under the
// phone's gates (`RemoteBrowser.start` for a new session, `RemoteSessions`'s
// serial queue, fresh read and `RemoteDecide.message` for a message), so the
// same checks stand between a request and the daemon, and the same rules say
// "sent", "queued" or "picks up again". The phone's switches (Settings →
// Phone) and its six-a-minute limit are the phone's: they don't apply to a
// person at the Mac.
//
// The order, for a session: the text and the files are checked here; the
// project is one Claude Science lists; each file is read, then uploaded to it
// (`POST /api/projects/<pid>/attachments`); then one request writes the text,
// a blank line and one attachment line to a line. A message reads the session
// first, so nothing goes up for a session that can't take one now, and uploads
// to the project that read names.
//
// A retry dedupes. The panel keeps one intent id for what it sends and sends
// it again unchanged until something in it changes (`IntentLedger`); the
// daemon refuses a repeated intent (409), and Capsid looks the session up by
// it (`RemoteBrowser.start`). A file that went up is remembered ten minutes by
// that intent id and its bytes, so a retry after a failed send reuses it
// instead of saving a second copy. Nothing is deleted. Nothing here logs
// text or names.
import CryptoKit
import Foundation

/// What the panel (and the intents) need of a sender: the live flow, or the
/// demo's, or a test's.
@MainActor
protocol QuickStartSending: AnyObject {
    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome
}

/// Keeps one intent id for as long as what is sent is the same: a retry after
/// an error dedupes at the daemon, an edit is a new request and gets a new one.
struct IntentLedger: Equatable, Sendable {
    private(set) var signature: String?
    private(set) var current: String

    init(make: () -> String = IntentLedger.newID) {
        current = make()
    }

    /// The id for this request: the same as last time when `signature` is.
    mutating func id(for signature: String, make: () -> String = IntentLedger.newID) -> String {
        if self.signature != signature {
            self.signature = signature
            current = make()
        }
        return current
    }

    /// What was sent worked: the next request is a new one, whatever it holds.
    mutating func sent(make: () -> String = IntentLedger.newID) {
        signature = nil
        current = make()
    }

    /// A version-4 UUID in lower case, as `crypto.randomUUID()` writes it.
    static func newID() -> String { UUID().uuidString.lowercased() }
}

@MainActor
final class QuickStartFlow: QuickStartSending {
    static let shared = QuickStartFlow(sessions: .shared, browser: .shared, dependencies: .live())

    /// The most a request's text may be, as the phone's message and new-session
    /// bodies have it.
    nonisolated static let textLimit = RemoteActionRequest.messageLimit

    // MARK: What is asked and what comes back

    struct Request: Equatable, Sendable {
        enum Target: Equatable, Sendable {
            /// A new session in this project.
            case newSession(project: String)
            /// A message to this session.
            case session(id: String)
        }

        var target: Target
        /// The project's name, for the sentences (the session's project, for a message).
        var projectName: String
        var text: String
        var files: [QuickStartFile]
        /// A new session only: ask Claude for a plan before it works.
        var planFirst: Bool
        /// A version-4 UUID, lower case.
        var intentID: String

        /// What makes this request the same one when sent again: the target, the
        /// words, the files (by place and size) and the plan switch.
        var signature: String {
            let target = switch target {
            case .newSession(let project): "new:" + project
            case .session(let id): "session:" + id
            }
            return ([target, text, planFirst ? "plan" : "go"] + files.map { "\($0.url.path)#\($0.size)" })
                .joined(separator: "\u{1F}")
        }
    }

    enum Outcome: Error, Equatable, Sendable {
        /// A new session is working: its id, and the sentence for the panel.
        case started(sessionID: String, sentence: String)
        /// The message went (or waits its turn): `sent`, `queued` or `resumed`.
        case sent(RemoteActionResult.Result, sentence: String)
        /// Nothing went, or not all of it; the sentence says what happened. The
        /// text stays in the panel.
        case failed(sentence: String)

        var sentence: String {
            switch self {
            case .started(_, let sentence), .sent(_, let sentence), .failed(let sentence): sentence
            }
        }

        var succeeded: Bool {
            if case .failed = self { false } else { true }
        }
    }

    enum Sentence {
        static let notReady = "Claude Science isn't ready yet. Wait for Capsid's window to finish loading, then try again."
        static let nothingToSend = "Write what Claude should do, or drop a file."
        static let needsProject = "Choose a project to start in."
        static let tooLong = "That's over 4,000 characters. Shorten it, or put the rest in a file."
        static let reference = "Part of that text looks like one of Claude Science's own attachment tags, which can't be sent as text. "
            + "Take out the braces and try again."
        static let projectGone = "That project isn't in Claude Science any more. Choose another."
        static let projectsUnreadable = "Couldn't read your projects. Try again in a moment."
        static let notStarted = "Couldn't start the session. Your request is still here."
        static let notSent = "Couldn't send the message. It's still here."
        static let noSession = "No session is open to send to."
        static let badIntent = "Couldn't make that request. Close Quick Start and open it again."

        static func uploadFailed(_ name: String, project: String, starting: Bool) -> String {
            "Couldn't upload \u{201C}\(name)\u{201D} to \(project). Nothing was \(starting ? "started" : "sent"). Your request is still here."
        }

        static func savedNotStarted(project: String) -> String {
            "The files are in \(project), but the session didn't start. Start again and they won't go up twice."
        }

        static func savedNotSent(project: String) -> String {
            "The files are in \(project), but the message didn't send. Send again and they won't go up twice."
        }

        static func started(project: String) -> String { "Started in \(project)." }

        /// A message the session won't take, in the Mac's words.
        static func blocked(_ sentence: String) -> String { sentence + " Your message is still here." }
    }

    // MARK: Over fakes in tests

    struct Dependencies {
        /// Whether Claude Science's page can be written to now.
        var ready: @MainActor () -> Bool
        /// The upload to a project: nil when it didn't complete.
        var upload: @MainActor (_ project: String, _ file: UploadFile) async -> PhotoUploadReply?
        var now: @MainActor () -> Date

        static func live() -> Dependencies {
            Dependencies(
                ready: { Demo.mode == nil && WebContainer.shared.status == .ready },
                upload: { project, file in
                    guard Demo.mode == nil else { return nil }
                    return try? await WebContainer.shared.uploadFile(project: project, file: file)
                },
                now: { Date() })
        }
    }

    /// How long an upload is remembered by its intent id.
    static let uploadedLifetime: TimeInterval = 10 * 60
    private static let uploadedLimit = 40

    private struct Uploaded {
        let digest: SHA256Digest
        let project: String
        let attachment: PhotoAttachment
        let at: Date
    }

    let sessions: RemoteSessions
    let browser: RemoteBrowser
    private let dependencies: Dependencies
    /// By intent id and the file's digest.
    private var uploaded: [String: Uploaded] = [:]

    init(sessions: RemoteSessions, browser: RemoteBrowser, dependencies: Dependencies) {
        self.sessions = sessions
        self.browser = browser
        self.dependencies = dependencies
    }

    // MARK: Perform

    func perform(_ request: Request) async -> Outcome {
        if let refusal = Self.check(request) { return .failed(sentence: refusal) }
        guard dependencies.ready() else { return .failed(sentence: Sentence.notReady) }
        switch request.target {
        case .newSession(let project): return await start(project, request: request)
        case .session(let id): return await send(to: id, request: request)
        }
    }

    /// The checks that need nothing but the request: the text, the files, the
    /// intent id and the ids. The sentence for the first that fails, or nil.
    nonisolated static func check(_ request: Request) -> String? {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && request.files.isEmpty { return Sentence.nothingToSend }
        if text.unicodeScalars.count > textLimit { return Sentence.tooLong }
        if PhotoText.hasReference(text) { return Sentence.reference }
        if request.files.count > AttachmentRules.maxFiles { return AttachmentRefusal.tooMany.sentence }
        if request.files.reduce(0, { $0 + $1.size }) > AttachmentRules.maxTotalBytes { return AttachmentRefusal.allTooBig.sentence }
        guard RemoteActionRequest.isUUIDv4(request.intentID) else { return Sentence.badIntent }
        switch request.target {
        case .newSession(let project):
            if !BrowseSQL.isProjectID(project) { return Sentence.needsProject }
        case .session(let id):
            if !PlanCheck.isFrameID(id) { return Sentence.noSession }
        }
        return nil
    }

    // MARK: A new session

    private func start(_ project: String, request: Request) async -> Outcome {
        guard let listed = await browser.projectIDs() else { return .failed(sentence: Sentence.projectsUnreadable) }
        guard listed.contains(project) else { return .failed(sentence: Sentence.projectGone) }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached: [PhotoAttachment]
        switch await attach(request.files, intent: request.intentID, project: project, name: request.projectName, starting: true) {
        case .failure(let failed): return failed
        case .success(let made): attached = made.map(\.attachment)
        }
        let body = Self.requestText(text: text, attachments: attached)
        let started = NewSessionRequest(text: body, intentID: request.intentID, planFirst: request.planFirst,
                                        attachment: false, files: !attached.isEmpty)
        let title = text.isEmpty ? (request.files.first?.name ?? "Files") : String(text.prefix(50))
        guard let reply = await browser.start(project, request: started, title: title), let id = Self.startedID(in: reply) else {
            return .failed(sentence: attached.isEmpty ? Sentence.notStarted
                           : Sentence.savedNotStarted(project: request.projectName))
        }
        return .started(sessionID: id, sentence: Sentence.started(project: request.projectName))
    }

    /// The new session's id from `RemoteBrowser.start`'s answer: 200 and
    /// `{"result":"started","id":"<36>"}`.
    nonisolated static func startedID(in reply: RemoteActionReply) -> String? {
        guard reply.status == 200,
              let root = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any],
              Pick.string(root["result"]) == "started", let id = Pick.string(root["id"]), PlanCheck.isFrameID(id) else { return nil }
        return id
    }

    // MARK: A message

    private func send(to id: String, request: Request) async -> Outcome {
        var outcome = Outcome.failed(sentence: Sentence.notSent)
        _ = await sessions.actSerially(on: id) { [weak self] in
            if let self { outcome = await self.sendToSession(id, request: request) }
            return .ok(.unavailable)
        }
        return outcome
    }

    private func sendToSession(_ id: String, request: Request) async -> Outcome {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // First the check the message route makes, so that nothing goes up for
        // a session that can't take a message now (its status, agent, project).
        let before = await sessions.photoDependencies.read(id, false)
        let probe = RemoteDecide.message(.message(text: text.isEmpty ? "Files" : text, intentID: request.intentID),
                                         session: id, fresh: before)
        let project: String
        switch probe {
        case .answer(let result): return Self.outcome(of: result)
        case .write(.message(_, _, let named?, _, _, _)): project = named
        case .write: return .failed(sentence: Sentence.notSent)
        }
        guard BrowseSQL.isProjectID(project) else { return .failed(sentence: Sentence.notSent) }
        var attached: [PhotoAttachment] = []
        var retried = false
        if !request.files.isEmpty {
            switch await attach(request.files, intent: request.intentID, project: project, name: request.projectName, starting: false) {
            case .failure(let failed): return failed
            case .success(let made):
                attached = made.map(\.attachment)
                retried = made.contains { $0.retried }
            }
        }
        // Then the message route's own re-read: the status says send, queue or
        // resume, and the agent is the one it names.
        let fresh = attached.isEmpty ? before : await sessions.photoDependencies.read(id, false)
        let body = Self.requestText(text: text, attachments: attached)
        guard case .write(.message(let frame, let agent, let sentTo?, _, let intent, _)) = RemoteDecide.message(
            .message(text: body, intentID: request.intentID), session: id, fresh: fresh), sentTo == project else {
            return .failed(sentence: attached.isEmpty ? Sentence.notSent : Sentence.savedNotSent(project: request.projectName))
        }
        let write: RemoteWrite = attached.isEmpty
            ? .message(frame: frame, agent: agent, projectID: sentTo, text: body, intentID: intent)
            : .messageWithFiles(frame: frame, agent: agent, projectID: sentTo, text: body, intentID: intent)
        let reply = await sessions.photoDependencies.write(write)
        var result = RemoteDecide.messaged(reply, status: fresh?.status ?? "")
        // A retry the daemon refuses as a repeat (409): the first try went.
        if retried, reply?.status == 409 { result = RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent) }
        switch result.result {
        case .sent, .queued, .resumed:
            return .sent(result.result, sentence: result.sentence)
        default:
            return .failed(sentence: attached.isEmpty ? Self.outcome(of: result).sentence : Sentence.savedNotSent(project: request.projectName))
        }
    }

    /// What a message's decision says, in the Mac's words: it went, or it
    /// didn't and the text stays.
    nonisolated static func outcome(of result: RemoteActionResult) -> Outcome {
        switch result.result {
        case .sent, .queued, .resumed: .sent(result.result, sentence: result.sentence)
        case .blocked, .changed: .failed(sentence: Sentence.blocked(result.sentence))
        default: .failed(sentence: Sentence.notSent)
        }
    }

    // MARK: Files

    /// `input_data.request`: the text, a blank line, then the attachment
    /// lines, one to a line; the lines alone for files with no text.
    nonisolated static func requestText(text: String, attachments: [PhotoAttachment]) -> String {
        guard !attachments.isEmpty else { return text }
        let lines = attachments.map(\.line).joined(separator: "\n")
        return text.isEmpty ? lines : text + "\n\n" + lines
    }

    /// Every file read and in the project (or reused from an earlier try of
    /// this intent): its place there, and whether it was reused. The first
    /// that can't be read or uploaded ends it, with the sentence; what already
    /// went up stays and is reused by the retry.
    private func attach(_ files: [QuickStartFile], intent: String, project: String, name: String, starting: Bool) async
        -> Result<[(attachment: PhotoAttachment, retried: Bool)], Outcome> {
        var made: [(attachment: PhotoAttachment, retried: Bool)] = []
        for file in files {
            guard let upload = await file.read() else {
                return .failure(.failed(sentence: AttachmentRefusal.unreadable(file.name).sentence))
            }
            guard let placed = await place(upload, intent: intent, project: project) else {
                return .failure(.failed(sentence: Sentence.uploadFailed(file.name, project: name, starting: starting)))
            }
            made.append(placed)
        }
        return .success(made)
    }

    /// The file's place in the project: what an earlier try of this intent
    /// uploaded (the same bytes, the same project, within ten minutes), else a
    /// new upload, which is remembered. Nil when there is none.
    private func place(_ file: UploadFile, intent: String, project: String) async -> (attachment: PhotoAttachment, retried: Bool)? {
        let now = dependencies.now()
        uploaded = uploaded.filter { $0.value.at <= now && now.timeIntervalSince($0.value.at) < Self.uploadedLifetime }
        let digest = SHA256.hash(data: file.data)
        let key = intent + "|" + digest.map { String(format: "%02x", $0) }.joined()
        if let earlier = uploaded[key], earlier.digest == digest, earlier.project == project {
            return (earlier.attachment, true)
        }
        guard BrowseSQL.isProjectID(project),
              let reply = await dependencies.upload(project, file), reply.status == 200, let upload = reply.upload,
              upload.filename == file.name, upload.contentType == file.contentType, upload.sizeBytes == file.data.count
        else { return nil }
        uploaded[key] = Uploaded(digest: digest, project: project, attachment: upload, at: now)
        while uploaded.count > Self.uploadedLimit, let oldest = uploaded.min(by: { $0.value.at < $1.value.at }) {
            uploaded[oldest.key] = nil
        }
        return (upload, false)
    }
}
