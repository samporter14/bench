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
//
// Cancel stops what is unsent. Every step checks for it, the ones that wait
// (the project list, a file read, an upload, the session's turn in its queue)
// give way to it at once, and the request itself, the one write that makes
// the session or the message, is the point past which it can't be taken back.
// A cancel before that ends with "Cancelled. Nothing was sent." (or says which
// files already went up); one after it is not a cancel, and the outcome says
// what happened. A write that gets no answer is unknown: the panel says "Not
// sure that went through. Checking…", a fresh read settles it, and Retry is
// the person's (Remote/WriteDeadline.swift).
import CryptoKit
import Foundation

/// What the panel (and the intents) need of a sender: the live flow, or the
/// demo's, or a test's.
@MainActor
protocol QuickStartSending: AnyObject {
    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome
    /// The same, telling the panel where it stands (`QuickStartFlow.Progress`).
    /// A sender that has nothing to tell takes the default.
    func perform(_ request: QuickStartFlow.Request,
                 progress: @escaping @MainActor (QuickStartFlow.Progress) -> Void) async -> QuickStartFlow.Outcome
}

extension QuickStartSending {
    func perform(_ request: QuickStartFlow.Request,
                 progress: @escaping @MainActor (QuickStartFlow.Progress) -> Void) async -> QuickStartFlow.Outcome {
        await perform(request)
    }
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

        /// Cancel stopped it before anything was sent: nothing to say but
        /// that, and the panel goes. (A cancel after files went up is a
        /// `failed` of its own, whose sentence says which.)
        var isCleanCancel: Bool { self == .failed(sentence: Sentence.cancelled) }
    }

    /// Where a send stands, for the panel.
    enum Progress: Equatable, Sendable {
        /// The request itself (the session's start, the message) is going:
        /// past this, Cancel can't take it back.
        case committed
        /// It got no answer, and Capsid is looking in Claude Science for what
        /// became of it.
        case checking
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

        // Cancel
        static let cancelled = "Cancelled. Nothing was sent."

        /// A cancel after some files went up, or while one was.
        static func cancelled(uploaded: Int, uploading: Bool, project: String, starting: Bool) -> String {
            let what = starting ? "started" : "sent"
            if uploading { return "Cancelled. A file may already be in \(project). Nothing was \(what)." }
            if uploaded == 0 { return cancelled }
            return "Cancelled. \(uploaded == 1 ? "1 file was" : "\(uploaded) files were") already in \(project). Nothing was \(what)."
        }

        // A write that got no answer
        static let startNotThere = "That didn't go through, as far as Capsid can see. Your request is still here: start it again, and it won't start twice."
        static func savedStartNotThere(project: String) -> String {
            "The files are in \(project), but no session shows. Start again: the files won't go up twice, and it won't start twice."
        }
        static let sendNotThere = "That didn't go through. Your message is still here."
        static func savedSendNotThere(project: String) -> String {
            "The files are in \(project), but the message didn't go through. Send again and they won't go up twice."
        }
        static let sendUnsure = "Not sure that went through. Look at the session before you send again. Your message is still here."
        /// The session's turn ran out of time before the message left.
        static func stalledNothingSent(files: Bool, project: String) -> String {
            files ? "Claude Science took too long. Nothing was sent, but a file may already be in \(project). Your message is still here."
                : "Claude Science took too long, and nothing was sent. Your message is still here."
        }
        static func uploadUnsure(_ name: String, project: String, starting: Bool) -> String {
            "Not sure \u{201C}\(name)\u{201D} reached \(project). Nothing was \(starting ? "started" : "sent"). Your request is still here: sending it again may add a second copy."
        }

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
        /// The most one message's turn in its session's queue may take, given
        /// the sizes of the files it uploads (`WriteDeadline.turn`).
        var turn: @MainActor ([Int]) -> Duration = { WriteDeadline.turn(uploadBytes: $0) }
        /// Waits out an upload's deadline; tests stand in for the clock.
        var wait: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

        static func live() -> Dependencies {
            Dependencies(
                ready: { Demo.mode == nil && WebContainer.shared.status == .ready },
                upload: { project, file in
                    guard Demo.mode == nil else { return nil }
                    return await WebContainer.shared.uploadAnswer(project: project, file: file)
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
        await perform(request, progress: { _ in })
    }

    func perform(_ request: Request, progress: @escaping @MainActor (Progress) -> Void) async -> Outcome {
        if let refusal = Self.check(request) { return .failed(sentence: refusal) }
        guard dependencies.ready() else { return .failed(sentence: Sentence.notReady) }
        guard !Task.isCancelled else { return .failed(sentence: Sentence.cancelled) }
        switch request.target {
        case .newSession(let project): return await start(project, request: request, progress: progress)
        case .session(let id): return await send(to: id, request: request, progress: progress)
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

    // MARK: Waiting, and giving way to Cancel

    private enum Step<Value: Sendable> {
        case done(Value)
        /// Cancel came first. What was being waited for is not stopped (a read
        /// or an upload under way can't be), only left behind: its answer goes nowhere.
        case cancelled
        /// Its own time ran out (an upload whose page never answered).
        case timedOut
    }

    /// `work`, or Cancel, whichever comes first; with `limit`, or its time.
    private func step<Value: Sendable>(limit: Duration? = nil,
                                       _ work: @escaping @MainActor () async -> Value) async -> Step<Value> {
        switch await WriteDeadline.race(limit, wait: dependencies.wait, cancel: .finish, work) {
        case .finished(let value): .done(value)
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        }
    }

    /// What Cancel ended, in words: nothing was sent, or some files already were.
    private func cancelled(uploaded: Int, uploading: Bool, project: String, starting: Bool) -> Outcome {
        .failed(sentence: Sentence.cancelled(uploaded: uploaded, uploading: uploading, project: project, starting: starting))
    }

    // MARK: A new session

    private func start(_ project: String, request: Request, progress: @escaping @MainActor (Progress) -> Void) async -> Outcome {
        let browser = browser
        guard case .done(let listedOrNil) = await step({ await browser.projectIDs() }) else {
            return cancelled(uploaded: 0, uploading: false, project: request.projectName, starting: true)
        }
        guard let listed = listedOrNil else { return .failed(sentence: Sentence.projectsUnreadable) }
        guard listed.contains(project) else { return .failed(sentence: Sentence.projectGone) }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached: [PhotoAttachment]
        switch await attach(request.files, intent: request.intentID, project: project, name: request.projectName, starting: true) {
        case .failed(let failed): return failed
        case .cancelled(let uploaded, let uploading):
            return cancelled(uploaded: uploaded, uploading: uploading, project: request.projectName, starting: true)
        case .done(let made): attached = made.map(\.attachment)
        }
        // Past this, the session is being made, and Cancel can't take it back.
        guard !Task.isCancelled else {
            return cancelled(uploaded: attached.count, uploading: false, project: request.projectName, starting: true)
        }
        let body = Self.requestText(text: text, attachments: attached)
        let started = NewSessionRequest(text: body, intentID: request.intentID, planFirst: request.planFirst,
                                        attachment: false, files: !attached.isEmpty)
        let title = text.isEmpty ? (request.files.first?.name ?? "Files") : String(text.prefix(50))
        progress(.committed)
        switch await browser.attempt(project, request: started, title: title, checking: { progress(.checking) }) {
        case .started(let reply):
            guard let id = Self.startedID(in: reply) else { fallthrough }
            return .started(sessionID: id, sentence: Sentence.started(project: request.projectName))
        case .notStarted:
            return .failed(sentence: attached.isEmpty ? Sentence.notStarted : Sentence.savedNotStarted(project: request.projectName))
        case .notThere:
            return .failed(sentence: attached.isEmpty ? Sentence.startNotThere : Sentence.savedStartNotThere(project: request.projectName))
        }
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

    private func send(to id: String, request: Request, progress: @escaping @MainActor (Progress) -> Void) async -> Outcome {
        var outcome = Outcome.failed(sentence: Sentence.notSent)
        var committed = false
        let told: @MainActor (Progress) -> Void = { stage in
            if stage == .committed { committed = true }
            progress(stage)
        }
        // The turn is bounded, uploads and all, so a message behind a stalled one still goes.
        let end = await sessions.runSerially(on: id, limit: dependencies.turn(request.files.map(\.size))) { [weak self] in
            if let self { outcome = await self.sendToSession(id, request: request, progress: told) }
            return .ok(.unavailable)
        }
        switch end {
        case .finished: return outcome
        // Never began: nothing was sent.
        case .cancelled: return .failed(sentence: Sentence.cancelled)
        // The turn ran out of time: if the message hadn't left, nothing was sent; if it had, it may have gone.
        case .stalled:
            if committed { return .failed(sentence: Sentence.sendUnsure) }
            return .failed(sentence: Sentence.stalledNothingSent(files: !request.files.isEmpty, project: request.projectName))
        }
    }

    private func sendToSession(_ id: String, request: Request, progress: @escaping @MainActor (Progress) -> Void) async -> Outcome {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessions = sessions
        let stopped = cancelled(uploaded: 0, uploading: false, project: request.projectName, starting: false)
        // First the check the message route makes, so that nothing goes up for
        // a session that can't take a message now (its status, agent, project).
        guard case .done(let before) = await step({ await sessions.photoDependencies.read(id, false) }) else { return stopped }
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
            case .failed(let failed): return failed
            case .cancelled(let uploaded, let uploading):
                return cancelled(uploaded: uploaded, uploading: uploading, project: request.projectName, starting: false)
            case .done(let made):
                attached = made.map(\.attachment)
                retried = made.contains { $0.retried }
            }
        }
        guard !Task.isCancelled else {
            return cancelled(uploaded: attached.count, uploading: false, project: request.projectName, starting: false)
        }
        // Then the message route's own re-read: the status says send, queue or
        // resume, and the agent is the one it names.
        let fresh: SessionProjection?
        if attached.isEmpty {
            fresh = before
        } else {
            guard case .done(let again) = await step({ await sessions.photoDependencies.read(id, false) }) else {
                return cancelled(uploaded: attached.count, uploading: false, project: request.projectName, starting: false)
            }
            fresh = again
        }
        let body = Self.requestText(text: text, attachments: attached)
        guard case .write(.message(let frame, let agent, let sentTo?, _, let intent, _)) = RemoteDecide.message(
            .message(text: body, intentID: request.intentID), session: id, fresh: fresh), sentTo == project else {
            return .failed(sentence: attached.isEmpty ? Sentence.notSent : Sentence.savedNotSent(project: request.projectName))
        }
        let write: RemoteWrite = attached.isEmpty
            ? .message(frame: frame, agent: agent, projectID: sentTo, text: body, intentID: intent)
            : .messageWithFiles(frame: frame, agent: agent, projectID: sentTo, text: body, intentID: intent)
        // Past this, the message is going, and Cancel can't take it back.
        guard !Task.isCancelled else {
            return cancelled(uploaded: attached.count, uploading: false, project: request.projectName, starting: false)
        }
        progress(.committed)
        let delivered = await sessions.deliver(write, text: body, session: id, before: fresh, checking: { progress(.checking) })
        var result = delivered.result
        // A retry the daemon refuses as a repeat (409): the first try went.
        if retried, delivered.reply?.status == 409 { result = RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent) }
        switch result.result {
        case .sent, .queued, .resumed:
            return .sent(result.result, sentence: result.sentence)
        case .retry:
            return .failed(sentence: attached.isEmpty ? Sentence.sendNotThere : Sentence.savedSendNotThere(project: request.projectName))
        case .unknown:
            return .failed(sentence: Sentence.sendUnsure)
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

    private enum Attach {
        case done([(attachment: PhotoAttachment, retried: Bool)])
        case failed(Outcome)
        /// Cancel came: how many files were in the project, and whether one
        /// was on its way (it may be there too).
        case cancelled(uploaded: Int, uploading: Bool)
    }

    /// Every file read and in the project (or reused from an earlier try of
    /// this intent): its place there, and whether it was reused. The first
    /// that can't be read or uploaded ends it, with the sentence; what already
    /// went up stays and is reused by the retry. Cancel ends it before the
    /// next file, or at once if one is being read or sent.
    private func attach(_ files: [QuickStartFile], intent: String, project: String, name: String, starting: Bool) async -> Attach {
        var made: [(attachment: PhotoAttachment, retried: Bool)] = []
        for file in files {
            guard !Task.isCancelled else { return .cancelled(uploaded: made.count, uploading: false) }
            guard case .done(let read) = await step({ await file.read() }) else {
                return .cancelled(uploaded: made.count, uploading: false)
            }
            guard let upload = read else {
                return .failed(.failed(sentence: AttachmentRefusal.unreadable(file.name).sentence))
            }
            guard !Task.isCancelled else { return .cancelled(uploaded: made.count, uploading: false) }
            // The page bounds an upload (WriteDeadline.upload); this is the Swift side's own, beyond it.
            let limit = WriteDeadline.upload(bytes: upload.data.count) + WriteDeadline.grace + WriteDeadline.grace
            let placed: Placed
            switch await step(limit: limit, { await self.place(upload, intent: intent, project: project) }) {
            case .done(let made): placed = made
            case .cancelled: return .cancelled(uploaded: made.count, uploading: true)
            case .timedOut: placed = .unsure
            }
            switch placed {
            case .placed(let attachment, let retried): made.append((attachment, retried))
            case .failed: return .failed(.failed(sentence: Sentence.uploadFailed(file.name, project: name, starting: starting)))
            case .unsure: return .failed(.failed(sentence: Sentence.uploadUnsure(file.name, project: name, starting: starting)))
            }
        }
        return .done(made)
    }

    private enum Placed: Sendable {
        case placed(PhotoAttachment, retried: Bool)
        case failed
        /// The upload got no answer: the file may be in the project.
        case unsure
    }

    /// The file's place in the project: what an earlier try of this intent
    /// uploaded (the same bytes, the same project, within ten minutes), else a
    /// new upload, which is remembered.
    private func place(_ file: UploadFile, intent: String, project: String) async -> Placed {
        let now = dependencies.now()
        uploaded = uploaded.filter { $0.value.at <= now && now.timeIntervalSince($0.value.at) < Self.uploadedLifetime }
        let digest = SHA256.hash(data: file.data)
        let key = intent + "|" + digest.map { String(format: "%02x", $0) }.joined()
        if let earlier = uploaded[key], earlier.digest == digest, earlier.project == project {
            return .placed(earlier.attachment, retried: true)
        }
        guard BrowseSQL.isProjectID(project), let reply = await dependencies.upload(project, file) else { return .failed }
        if reply.isUnknown { return .unsure }
        guard reply.status == 200, let upload = reply.upload,
              upload.filename == file.name, upload.contentType == file.contentType, upload.sizeBytes == file.data.count
        else { return .failed }
        uploaded[key] = Uploaded(digest: digest, project: project, attachment: upload, at: now)
        while uploaded.count > Self.uploadedLimit, let oldest = uploaded.min(by: { $0.value.at < $1.value.at }) {
            uploaded[oldest.key] = nil
        }
        return .placed(upload, retried: false)
    }
}
