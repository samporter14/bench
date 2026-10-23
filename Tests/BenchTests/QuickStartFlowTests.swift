// QuickStartFlowTests.swift — what Start and ⇧↩ do, against fakes that only
// record what they were asked: a new session in a project, a message to a
// session, the files uploaded first, the intent id that makes a retry dedupe,
// plan first, a queued message, and every sentence an error says. Nothing here
// reaches a real daemon, database or web view, and no real session is made.
import CryptoKit
import Foundation
import Testing
@testable import Bench

private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
private let otherIntent = "2c5f39cb-3fb2-42e3-994f-1127e4ddb538"
private let sessionID = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
private let newID = "9f8e7d6c-5b4a-4321-8fed-cba987654321"
private let attachmentID = "11111111-2222-4333-8444-555555555555"
private let versionID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

/// Holds whoever waits on it until it is opened, as a page that is slow to answer does.
@MainActor
private final class Gate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var holding: Int { waiting.count }

    func wait() async {
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        let held = waiting
        waiting = []
        held.forEach { $0.resume() }
    }
}

@MainActor
private final class FlowRig {
    enum Upload { case echo, none, status(Int), noUpload, wrongSize, unknown }

    // Holds, for the tests of Cancel: each waits on `gate` until `gate.open()`.
    let gate = Gate()
    var holdProjects = false
    var holdUploads = false
    var holdCreate = false
    /// The reads (0-based, in turn) that wait.
    var holdReads: Set<Int> = []
    /// Called as each read begins, with its place in turn.
    var onRead: ((Int) -> Void)?
    var turnLimit: Duration = .seconds(60)
    /// An upload's deadline in Swift passes at once.
    var uploadsRunOutOfTime = false
    private var readCalls = 0

    var ready = true
    var known: [SessionStatus] = []
    /// Handed out in turn, the last one repeating; a new list starts over.
    var reads: [SessionProjection?] = [FlowRig.session("completed")] { didSet { readIndex = 0 } }
    var upload: Upload = .echo
    var writeReply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted")
    var createReplies: [RemoteWriteResult?] = [RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: newID)]
    var intents: [String?] = []
    var projects: [ProjectRow]? = [ProjectRow(id: "proj-1", name: "Made-up", sessions: 1, lastActiveMs: nil),
                                   ProjectRow(id: "proj_a", name: "Made-up A", sessions: 0, lastActiveMs: nil)]
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var log: [String] = []
    private(set) var writes: [RemoteWrite] = []
    private(set) var uploads: [(project: String, file: UploadFile)] = []
    private var readIndex = 0
    private var createIndex = 0
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-flow-\(UUID().uuidString)", isDirectory: true)

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    static func session(_ status: String, agent: String? = "made-up-agent", project: String? = "proj-1") -> SessionProjection {
        SessionProjection(status: status, agentName: agent, projectID: project)
    }

    /// A real small file on disk, as a dropped one is.
    func file(_ name: String, _ text: String = "a,b\n1,2\n") throws -> QuickStartFile {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return try QuickStartFile.make(url: url).get()
    }

    lazy var sessions = RemoteSessions(dependencies: RemoteSessions.Dependencies(
        actionsOn: { false },
        known: { [unowned self] in self.known },
        cardPlan: { _ in nil },
        read: { [unowned self] _, turns in
            self.log.append(turns ? "turns" : "read")
            let call = self.readCalls
            self.readCalls += 1
            self.onRead?(call)
            if self.holdReads.contains(call) { await self.gate.wait() }
            let index = min(self.readIndex, self.reads.count - 1)
            self.readIndex += 1
            return self.reads.isEmpty ? nil : self.reads[index]
        },
        readPlan: { _ in nil },
        write: { [unowned self] write in
            self.log.append("write")
            self.writes.append(write)
            return self.writeReply
        },
        now: { [unowned self] in self.now },
        browseOn: { false },
        lookup: { _ in nil }))

    lazy var browser = RemoteBrowser(sessions: sessions, dependencies: RemoteBrowser.Dependencies(
        browseOn: { false },
        actionsOn: { false },
        projects: { [unowned self] in
            self.log.append("projects")
            if self.holdProjects { await self.gate.wait() }
            return self.projects
        },
        sessions: { _, _, _ in nil },
        known: { [unowned self] in self.known },
        history: { _, _, _ in .unreadable },
        turn: { _, _ in .none },
        create: { [unowned self] write in
            self.log.append("create")
            self.writes.append(write)
            if self.holdCreate { await self.gate.wait() }
            let index = min(self.createIndex, self.createReplies.count - 1)
            self.createIndex += 1
            return self.createReplies.isEmpty ? nil : self.createReplies[index]
        },
        findIntent: { [unowned self] _, _ in
            self.log.append("intent")
            return self.intents.isEmpty ? nil : self.intents.removeFirst()
        },
        listed: { _, _ in },
        now: { [unowned self] in self.now },
        pause: { [unowned self] in self.log.append("pause") }))

    lazy var flow = QuickStartFlow(sessions: sessions, browser: browser, dependencies: QuickStartFlow.Dependencies(
        ready: { [unowned self] in self.ready },
        upload: { [unowned self] project, file in
            self.log.append("upload")
            self.uploads.append((project, file))
            if self.holdUploads { await self.gate.wait() }
            switch self.upload {
            case .echo:
                return PhotoUploadReply(status: 200, upload: PhotoAttachment(
                    id: attachmentID, versionID: versionID, filename: file.name, contentType: file.contentType, sizeBytes: file.data.count))
            case .wrongSize:
                return PhotoUploadReply(status: 200, upload: PhotoAttachment(
                    id: attachmentID, versionID: versionID, filename: file.name, contentType: file.contentType, sizeBytes: file.data.count + 1))
            case .none: return nil
            case .status(let status): return PhotoUploadReply(status: status)
            case .noUpload: return PhotoUploadReply(status: 200)
            case .unknown: return .unknown
            }
        },
        now: { [unowned self] in self.now },
        turn: { [unowned self] _ in self.turnLimit },
        wait: { [unowned self] in await self.waitOut($0) }))

    /// An upload's deadline in Swift: real time, or at once.
    func waitOut(_ duration: Duration) async {
        if uploadsRunOutOfTime { return }
        try? await Task.sleep(for: duration)
    }

    func line(of file: UploadFile) -> String {
        PhotoAttachment(id: attachmentID, versionID: versionID, filename: file.name, contentType: file.contentType,
                        sizeBytes: file.data.count).line
    }

    func newSession(_ text: String = "QC this export", files: [QuickStartFile] = [], plan: Bool = true, project: String = "proj-1",
                    intent: String = intent) -> QuickStartFlow.Request {
        QuickStartFlow.Request(target: .newSession(project: project), projectName: "Made-up", text: text, files: files,
                               planFirst: plan, intentID: intent)
    }

    func message(_ text: String = "Add the second plate", files: [QuickStartFile] = [], id: String = sessionID,
                 intent: String = intent) -> QuickStartFlow.Request {
        QuickStartFlow.Request(target: .session(id: id), projectName: "Made-up", text: text, files: files, planFirst: false, intentID: intent)
    }
}

// MARK: A new session

@MainActor
struct QuickStartNewSessionTests {
    private let rig = FlowRig()

    @Test func aSessionIsStartedInTheProjectWithItsWordsAndPlanFirst() async {
        let outcome = await rig.flow.perform(rig.newSession("  QC this export  "))
        #expect(outcome == .started(sessionID: newID, sentence: "Started in Made-up."))
        #expect(rig.log == ["projects", "create"])
        // The existing request writer, to the default agent, with the intent id so a retry dedupes.
        #expect(rig.writes == [.newSession(project: "proj-1", text: "QC this export", planMode: true, intentID: intent)])
    }

    @Test func planFirstOffIsPlanModeOff() async {
        _ = await rig.flow.perform(rig.newSession(plan: false))
        #expect(rig.writes == [.newSession(project: "proj-1", text: "QC this export", planMode: false, intentID: intent)])
    }

    @Test func filesGoUpToTheProjectBeforeTheRequestWhichEndsInTheirLines() async throws {
        let first = try rig.file("plate one.csv"), second = try rig.file("notes.md", "# notes\n")
        let outcome = await rig.flow.perform(rig.newSession(files: [first, second]))
        #expect(outcome.succeeded)
        #expect(rig.log == ["projects", "upload", "upload", "create"])
        #expect(rig.uploads.map(\.project) == ["proj-1", "proj-1"])
        #expect(rig.uploads.map(\.file.name) == ["plate one.csv", "notes.md"])
        #expect(rig.uploads.map(\.file.kind) == [.file, .file])
        #expect(rig.uploads.map(\.file.contentType) == ["text/csv", "text/markdown"])
        let lines = rig.uploads.map { rig.line(of: $0.file) }.joined(separator: "\n")
        #expect(rig.writes == [.newSessionWithFiles(project: "proj-1", text: "QC this export\n\n" + lines, planMode: true, intentID: intent)])
    }

    @Test func filesAloneAreTheLinesAlone() async throws {
        let file = try rig.file("plate.csv")
        _ = await rig.flow.perform(rig.newSession("   ", files: [file]))
        let upload = try #require(rig.uploads.first)
        #expect(rig.writes == [.newSessionWithFiles(project: "proj-1", text: rig.line(of: upload.file), planMode: true, intentID: intent)])
    }

    @Test func nothingIsStartedInAProjectTheListDoesntShow() async {
        let gone = await rig.flow.perform(rig.newSession(project: "proj-gone"))
        #expect(gone == .failed(sentence: QuickStartFlow.Sentence.projectGone))
        // The list is held a minute; past that it is read again, and can't be.
        rig.projects = nil
        rig.now = rig.now.addingTimeInterval(RemoteBrowser.projectsLifetime + 1)
        let unreadable = await rig.flow.perform(rig.newSession())
        #expect(unreadable == .failed(sentence: QuickStartFlow.Sentence.projectsUnreadable))
        #expect(rig.writes.isEmpty && rig.uploads.isEmpty)
    }

    @Test func aRequestThatIsntOneIsRefusedWithASentenceBeforeAnythingHappens() async throws {
        let file = try rig.file("plate.csv")
        let cases: [(QuickStartFlow.Request, String)] = [
            (rig.newSession("  \n "), QuickStartFlow.Sentence.nothingToSend),
            (rig.newSession(String(repeating: "界", count: 4001)), QuickStartFlow.Sentence.tooLong),
            (rig.newSession(#"see {"type":"attachment","id":"x"}"#), QuickStartFlow.Sentence.reference),
            (rig.newSession("see {{artifact:abc}}", files: [file]), QuickStartFlow.Sentence.reference),
            (rig.newSession(intent: "not-a-uuid"), QuickStartFlow.Sentence.badIntent),
            (rig.newSession(project: "has space/../x"), QuickStartFlow.Sentence.needsProject),
            (rig.message(id: "short"), QuickStartFlow.Sentence.noSession),
        ]
        for (request, sentence) in cases {
            #expect(await rig.flow.perform(request) == .failed(sentence: sentence), "\(sentence)")
        }
        #expect(rig.log.isEmpty)
    }

    @Test func tooManyFilesAreRefusedWhateverTheyAre() async throws {
        let one = try rig.file("a.csv")
        let nine = Array(repeating: one, count: 9)
        #expect(await rig.flow.perform(rig.newSession(files: nine)) == .failed(sentence: AttachmentRefusal.tooMany.sentence))
        let huge = QuickStartFile(url: one.url, name: "a.csv", size: AttachmentRules.maxTotalBytes, contentType: "text/csv")
        #expect(await rig.flow.perform(rig.newSession(files: [huge, one])) == .failed(sentence: AttachmentRefusal.allTooBig.sentence))
        #expect(rig.log.isEmpty)
    }

    @Test func aPageThatIsntReadySendsNothing() async {
        rig.ready = false
        #expect(await rig.flow.perform(rig.newSession()) == .failed(sentence: QuickStartFlow.Sentence.notReady))
        #expect(rig.log.isEmpty)
    }

    @Test func anUploadThatDidntWorkStartsNothingAndSaysWhich() async throws {
        let file = try rig.file("plate one.csv")
        for upload in [FlowRig.Upload.none, .status(404), .status(413), .status(500), .noUpload, .wrongSize] {
            rig.upload = upload
            let outcome = await rig.flow.perform(rig.newSession(files: [file], intent: UUID().uuidString.lowercased()))
            #expect(outcome == .failed(sentence: "Couldn't upload \u{201C}plate one.csv\u{201D} to Made-up. Nothing was started. Your request is still here."))
        }
        #expect(!rig.log.contains("create"))
        #expect(rig.writes.isEmpty)
    }

    @Test func aFileThatChangedOrWentIsNamedAndNothingIsSent() async throws {
        let file = try rig.file("plate.csv")
        try Data("a different length\n".utf8).write(to: file.url)
        let outcome = await rig.flow.perform(rig.newSession(files: [file]))
        #expect(outcome == .failed(sentence: AttachmentRefusal.unreadable("plate.csv").sentence))
        try FileManager.default.removeItem(at: file.url)
        #expect(await rig.flow.perform(rig.newSession(files: [file])).succeeded == false)
        #expect(rig.uploads.isEmpty && rig.writes.isEmpty)
    }

    @Test func aStartThatDidntGoSaysTheTextIsStillThereAndTheFilesAreInTheProject() async throws {
        rig.createReplies = [nil]
        let plain = await rig.flow.perform(rig.newSession())
        #expect(plain == .failed(sentence: QuickStartFlow.Sentence.notStarted))
        rig.createReplies = [RemoteWriteResult(status: 500)]
        let file = try rig.file("plate.csv")
        let withFile = await rig.flow.perform(rig.newSession(files: [file], intent: otherIntent))
        #expect(withFile == .failed(sentence: "The files are in Made-up, but the session didn't start. Start again and they won't go up twice."))
    }

    @Test func aRetryDedupesTheIntentIsFoundAndTheFileIsNotUploadedTwice() async throws {
        let file = try rig.file("plate.csv")
        // The first try's answer was lost, and the database doesn't have the session.
        rig.createReplies = [nil]
        let first = await rig.flow.perform(rig.newSession(files: [file]))
        #expect(first.succeeded == false)
        #expect(rig.uploads.count == 1)
        // The retry: the same intent id (the daemon says it saw it: 409), found by it.
        rig.createReplies = [RemoteWriteResult(status: 409)]
        rig.intents = [newID]
        let retry = await rig.flow.perform(rig.newSession(files: [file]))
        #expect(retry == .started(sessionID: newID, sentence: "Started in Made-up."))
        #expect(rig.uploads.count == 1, "the file went up once")
        let creates = rig.writes.compactMap { write -> String? in
            if case .newSessionWithFiles(_, let text, _, let id) = write { return text + "|" + id }
            return nil
        }
        #expect(creates.count == 2)
        #expect(creates[0] == creates[1], "the same words, the same lines, the same intent")
    }

    @Test func aDifferentIntentUploadsAgainAndAChangedFileToo() async throws {
        let file = try rig.file("plate.csv")
        _ = await rig.flow.perform(rig.newSession(files: [file]))
        _ = await rig.flow.perform(rig.newSession(files: [file], intent: otherIntent))
        #expect(rig.uploads.count == 2)
        // An upload is only remembered ten minutes.
        _ = await rig.flow.perform(rig.newSession(files: [file], intent: otherIntent))
        #expect(rig.uploads.count == 2)
        rig.now = rig.now.addingTimeInterval(QuickStartFlow.uploadedLifetime + 1)
        _ = await rig.flow.perform(rig.newSession(files: [file], intent: otherIntent))
        #expect(rig.uploads.count == 3)
    }
}

// MARK: A message to the session in view

@MainActor
struct QuickStartMessageTests {
    private let rig = FlowRig()

    private func sentText(_ write: RemoteWrite?) -> String? {
        switch write {
        case .message(_, _, _, let text, _, _)?, .messageWithFiles(_, _, _, let text, _)?: text
        default: nil
        }
    }

    @Test func aSessionThatTakesAMessageGetsIt() async {
        let outcome = await rig.flow.perform(rig.message("  Add the second plate  "))
        #expect(outcome == .sent(.sent, sentence: "Sent."))
        #expect(rig.log == ["read", "write"])
        #expect(rig.writes == [.message(frame: sessionID, agent: "made-up-agent", projectID: "proj-1", text: "Add the second plate",
                                        intentID: intent)])
    }

    @Test func aBusySessionQueuesItAndAFailedOneResumes() async {
        rig.reads = [FlowRig.session("processing")]
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "message_queued")
        #expect(await rig.flow.perform(rig.message()) == .sent(.queued, sentence: "Queued. Claude reads it at the next safe point."))
        rig.reads = [FlowRig.session("failed")]
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        #expect(await rig.flow.perform(rig.message(intent: otherIntent)) == .sent(.resumed, sentence: "Sent. The session picks up again."))
        rig.reads = [FlowRig.session("completed")]
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "already_delivered")
        #expect(await rig.flow.perform(rig.message(intent: otherIntent)).succeeded)
    }

    @Test func aSessionThatCantTakeOneSaysSoAndKeepsTheMessage() async throws {
        let file = try rig.file("plate.csv")
        rig.reads = [FlowRig.session("awaiting_user_response")]
        #expect(await rig.flow.perform(rig.message(files: [file])) == .failed(sentence: "Answer its question first. Your message is still here."))
        rig.reads = [FlowRig.session("awaiting_plan_approval")]
        #expect(await rig.flow.perform(rig.message()) == .failed(sentence: "Approve or revise the plan on your Mac. Your message is still here."))
        for unreadable in [nil, FlowRig.session("completed", agent: nil), FlowRig.session("completed", project: nil),
                           FlowRig.session("replaced")] as [SessionProjection?] {
            rig.reads = [unreadable]
            let outcome = await rig.flow.perform(rig.message())
            #expect(outcome.succeeded == false)
        }
        // Nothing went up for a session that can't take it, and nothing was written.
        #expect(rig.uploads.isEmpty && rig.writes.isEmpty)
    }

    @Test func filesGoUpToTheProjectTheReadNamesThenTheMessageEndsInTheirLines() async throws {
        let file = try rig.file("plate.csv")
        rig.reads = [FlowRig.session("completed", project: "proj_a"), FlowRig.session("completed", project: "proj_a")]
        let outcome = await rig.flow.perform(rig.message("Look at this", files: [file]))
        #expect(outcome.succeeded)
        // Read, upload, read again (the message route's own), write.
        #expect(rig.log == ["read", "upload", "read", "write"])
        let upload = try #require(rig.uploads.first)
        #expect(upload.project == "proj_a")
        #expect(rig.writes == [.messageWithFiles(frame: sessionID, agent: "made-up-agent", projectID: "proj_a",
                                                 text: "Look at this\n\n" + rig.line(of: upload.file), intentID: intent)])
    }

    @Test func aSessionThatChangedWhileItUploadedSavesTheFilesAndSaysSo() async throws {
        let file = try rig.file("plate.csv")
        rig.reads = [FlowRig.session("completed"), FlowRig.session("awaiting_user_response")]
        let outcome = await rig.flow.perform(rig.message(files: [file]))
        #expect(outcome == .failed(sentence: "The files are in Made-up, but the message didn't send. Send again and they won't go up twice."))
        rig.reads = [FlowRig.session("completed"), nil]
        #expect(await rig.flow.perform(rig.message(files: [file], intent: otherIntent)).succeeded == false)
        rig.reads = [FlowRig.session("completed", project: "proj-1"), FlowRig.session("completed", project: "proj-2")]
        #expect(await rig.flow.perform(rig.message(files: [file], intent: sessionID)).succeeded == false)
    }

    @Test func aProjectIdThatIsNotOneIsNeverUploadedTo() async throws {
        let file = try rig.file("plate.csv")
        rig.reads = [FlowRig.session("completed", project: "has space/../x")]
        #expect(await rig.flow.perform(rig.message(files: [file])).succeeded == false)
        #expect(rig.uploads.isEmpty && rig.writes.isEmpty)
    }

    @Test func aRetryOfTheSameMessageReusesTheUploadAndAConflictReadsAsSent() async throws {
        let file = try rig.file("plate.csv")
        rig.writeReply = nil
        #expect(await rig.flow.perform(rig.message(files: [file])).succeeded == false)
        rig.writeReply = RemoteWriteResult(status: 409)
        let retry = await rig.flow.perform(rig.message(files: [file]))
        #expect(retry == .sent(.sent, sentence: "Sent."))
        #expect(rig.uploads.count == 1)
    }

    @Test func aMessageIsCheckedLikeTheOtherRequests() async {
        for text in ["", "  ", String(repeating: "界", count: 4001), #"{"file_path":"/x"}"#] {
            #expect(await rig.flow.perform(rig.message(text)).succeeded == false)
        }
        #expect(rig.log.isEmpty)
    }

    @Test func twoMessagesToOneSessionTakeTurns() async {
        async let first = rig.flow.perform(rig.message("one", intent: intent))
        async let second = rig.flow.perform(rig.message("two", intent: otherIntent))
        _ = await (first, second)
        // One at a time: read, write, read, write, never read, read.
        #expect(rig.log == ["read", "write", "read", "write"])
    }
}

// MARK: The intent id

struct IntentLedgerTests {
    @Test func theSameRequestKeepsItsIdAndAnEditGetsANewOne() {
        var counter = 0
        let make: () -> String = { counter += 1; return "id-\(counter)" }
        var ledger = IntentLedger(make: make)
        let first = ledger.id(for: "a", make: make)
        #expect(ledger.id(for: "a", make: make) == first)
        #expect(ledger.id(for: "a", make: make) == first)
        let second = ledger.id(for: "b", make: make)
        #expect(second != first)
        #expect(ledger.id(for: "a", make: make) != second)
    }

    @Test func aRequestThatWentStartsTheNextWithANewId() {
        var counter = 0
        let make: () -> String = { counter += 1; return "id-\(counter)" }
        var ledger = IntentLedger(make: make)
        let first = ledger.id(for: "a", make: make)
        ledger.sent(make: make)
        #expect(ledger.id(for: "a", make: make) != first)
    }

    @Test func theIdsAreLowerCaseVersion4UUIDsAsTheDaemonsWriterWantsThem() {
        for _ in 0..<20 { #expect(RemoteActionRequest.isUUIDv4(IntentLedger.newID())) }
    }

    @Test @MainActor func aRequestsSignatureIsItsTargetWordsFilesAndPlan() {
        let file = QuickStartFile(url: URL(fileURLWithPath: "/tmp/a.csv"), name: "a.csv", size: 10, contentType: "text/csv")
        func request(_ target: QuickStartFlow.Request.Target = .newSession(project: "p"), text: String = "t",
                     files: [QuickStartFile] = [], plan: Bool = true) -> QuickStartFlow.Request {
            QuickStartFlow.Request(target: target, projectName: "P", text: text, files: files, planFirst: plan, intentID: "x")
        }
        let base = request().signature
        #expect(request().signature == base)
        #expect(request(text: "u").signature != base)
        #expect(request(files: [file]).signature != base)
        #expect(request(plan: false).signature != base)
        #expect(request(.newSession(project: "q")).signature != base)
        #expect(request(.session(id: sessionID)).signature != base)
    }
}

// MARK: Cancel

/// Cancel stops what is unsent, and tells "cancelled before anything was sent" from
/// "already sent". Everything is held on a gate the test opens; nothing is real.
@MainActor
struct QuickStartFlowCancelTests {
    private let rig = FlowRig()

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<4_000 where !condition() { await Task.yield() }
    }

    private func settle() async {
        for _ in 0..<60 { await Task.yield() }
    }

    @Test func aTaskCancelledBeforeItBeginsSendsNothing() async {
        let flow = rig.flow
        let request = rig.newSession()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await flow.perform(request)
        }
        let outcome = await task.value
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.cancelled))
        #expect(outcome.isCleanCancel)
        #expect(rig.log.isEmpty)
    }

    @Test func cancelWhileTheProjectsAreReadSendsNothingAndAnswersAtOnce() async {
        rig.holdProjects = true
        let flow = rig.flow
        let request = rig.newSession()
        let task = Task { @MainActor in await flow.perform(request) }
        await waitUntil { rig.gate.holding == 1 }
        task.cancel()
        // It answers while the read is still held.
        let outcome = await task.value
        #expect(outcome.isCleanCancel)
        #expect(outcome.sentence == "Cancelled. Nothing was sent.")
        rig.gate.open()
        await settle()
        #expect(rig.log == ["projects"])
        #expect(rig.writes.isEmpty && rig.uploads.isEmpty)
    }

    @Test func cancelWhileAnUploadIsHeldNeverStartsTheSession() async throws {
        rig.holdUploads = true
        let flow = rig.flow
        let request = rig.newSession(files: [try rig.file("a.csv")])
        let task = Task { @MainActor in await flow.perform(request) }
        await waitUntil { rig.gate.holding == 1 }
        task.cancel()
        let outcome = await task.value
        // The upload is on its way and may land: said so, and not a clean cancel.
        #expect(outcome == .failed(sentence: "Cancelled. A file may already be in Made-up. Nothing was started."))
        #expect(!outcome.isCleanCancel)
        rig.gate.open()
        await settle()
        #expect(rig.log == ["projects", "upload"])
        #expect(rig.writes.isEmpty, "the session is never started after the upload is let go")
    }

    @Test func cancelWhileASendWaitsBehindAnotherActionNeverSends() async {
        let sessions = rig.sessions
        let flow = rig.flow
        // Another action on the same session holds the queue.
        let holder = Task { @MainActor in
            await sessions.runSerially(on: sessionID, limit: .seconds(60)) {
                await self.rig.gate.wait()
                return .ok(.unavailable)
            }
        }
        await waitUntil { rig.gate.holding == 1 }
        let request = rig.message()
        let task = Task { @MainActor in await flow.perform(request) }
        await settle()
        task.cancel()
        let outcome = await task.value
        #expect(outcome.isCleanCancel)
        rig.gate.open()
        _ = await holder.value
        await settle()
        // Nothing of the cancelled send ran: no read, no write.
        #expect(rig.log.isEmpty)
        #expect(rig.writes.isEmpty)
    }

    @Test func cancelWhileASendReadsTheSessionSendsNothing() async {
        rig.holdReads = [0]
        let flow = rig.flow
        let request = rig.message()
        let task = Task { @MainActor in await flow.perform(request) }
        await waitUntil { rig.gate.holding == 1 }
        task.cancel()
        let outcome = await task.value
        #expect(outcome.isCleanCancel)
        rig.gate.open()
        await settle()
        #expect(rig.writes.isEmpty)
    }

    @Test func cancelAfterAFileWentUpSaysHowManyAreInTheProject() async throws {
        let flow = rig.flow
        let request = rig.message(files: [try rig.file("a.csv")])
        // The re-read after the upload is the second read; hold it, and cancel there.
        rig.holdReads = [1]
        let task = Task { @MainActor in await flow.perform(request) }
        await waitUntil { rig.gate.holding == 1 }
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .failed(sentence: "Cancelled. 1 file was already in Made-up. Nothing was sent."))
        #expect(!outcome.isCleanCancel)
        rig.gate.open()
        await settle()
        #expect(rig.writes.isEmpty)
        #expect(rig.log.filter { $0 == "upload" }.count == 1)
    }

    @Test func cancelAfterTheSessionIsBeingMadeIsNotACancel() async {
        rig.holdCreate = true
        let flow = rig.flow
        let request = rig.newSession()
        var stages: [QuickStartFlow.Progress] = []
        let task = Task { @MainActor in await flow.perform(request, progress: { stages.append($0) }) }
        await waitUntil { rig.gate.holding == 1 }
        #expect(stages == [.committed])
        // Cancel arrives with the request already out: it can't be taken back, and the outcome says what happened.
        task.cancel()
        rig.gate.open()
        let outcome = await task.value
        #expect(outcome == .started(sessionID: newID, sentence: "Started in Made-up."))
        #expect(!outcome.sentence.localizedCaseInsensitiveContains("cancel"))
        #expect(rig.writes.count == 1)
    }

    @Test func cancelAfterTheMessageIsBeingSentIsNotACancelEither() async {
        rig.holdReads = []
        let flow = rig.flow
        let request = rig.message()
        var stages: [QuickStartFlow.Progress] = []
        let task = Task { @MainActor in await flow.perform(request, progress: { stages.append($0) }) }
        await waitUntil { stages == [.committed] }
        task.cancel()
        let outcome = await task.value
        // The write is out by then (the fake answers at once): a cancel after it changes nothing.
        #expect(outcome == .sent(.sent, sentence: "Sent."))
        #expect(rig.writes.count == 1)
    }

    @Test func theSentencesSayWhatWentUp() {
        typealias Said = QuickStartFlow.Sentence
        #expect(Said.cancelled(uploaded: 0, uploading: false, project: "P", starting: true) == "Cancelled. Nothing was sent.")
        #expect(Said.cancelled(uploaded: 1, uploading: false, project: "P", starting: true) == "Cancelled. 1 file was already in P. Nothing was started.")
        #expect(Said.cancelled(uploaded: 3, uploading: false, project: "P", starting: false) == "Cancelled. 3 files were already in P. Nothing was sent.")
        #expect(Said.cancelled(uploaded: 0, uploading: true, project: "P", starting: true) == "Cancelled. A file may already be in P. Nothing was started.")
        #expect(QuickStartFlow.Outcome.failed(sentence: Said.cancelled).isCleanCancel)
        #expect(!QuickStartFlow.Outcome.failed(sentence: Said.notStarted).isCleanCancel)
        #expect(!QuickStartFlow.Outcome.started(sessionID: newID, sentence: "Started in P.").isCleanCancel)
    }
}

// MARK: A write that gets no answer

@MainActor
struct QuickStartFlowUnknownTests {
    private let rig = FlowRig()

    @Test func aNewSessionWithNoAnswerThatTheDatabaseShowsIsStarted() async {
        rig.createReplies = [.unknown]
        rig.intents = [nil, newID]
        var stages: [QuickStartFlow.Progress] = []
        let outcome = await rig.flow.perform(rig.newSession(), progress: { stages.append($0) })
        #expect(outcome == .started(sessionID: newID, sentence: "Started in Made-up."))
        #expect(stages == [.committed, .checking])
        #expect(rig.writes.count == 1, "never sent again")
    }

    @Test func aNewSessionWithNoAnswerThatTheDatabaseDoesntShowCanBeStartedAgain() async {
        rig.createReplies = [.unknown]
        rig.intents = [nil, nil]
        var stages: [QuickStartFlow.Progress] = []
        let outcome = await rig.flow.perform(rig.newSession(), progress: { stages.append($0) })
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.startNotThere))
        #expect(stages == [.committed, .checking])
        #expect(rig.writes.count == 1)
    }

    @Test func withFilesTheSentenceSaysTheyAreInTheProject() async throws {
        rig.createReplies = [.unknown]
        rig.intents = [nil, nil]
        let outcome = await rig.flow.perform(rig.newSession(files: [try rig.file("a.csv")]))
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.savedStartNotThere(project: "Made-up")))
        #expect(rig.writes.count == 1)
    }

    @Test func aRetryUnderTheSameIntentFindsTheSessionTheFirstOneMade() async {
        rig.createReplies = [.unknown, RemoteWriteResult(status: 409, code: "intent_conflict")]
        rig.intents = [nil, nil, newID]
        let first = await rig.flow.perform(rig.newSession())
        #expect(first.succeeded == false)
        let again = await rig.flow.perform(rig.newSession())
        #expect(again == .started(sessionID: newID, sentence: "Started in Made-up."))
        #expect(rig.writes.count == 2)
    }

    @Test func aMessageWithNoAnswerThatTheSessionShowsIsSent() async {
        rig.writeReply = .unknown
        let turns = [SessionProjection.Turn(role: .you, at: rig.now.addingTimeInterval(1), text: "Add the second plate")]
        rig.reads = [FlowRig.session("completed"),
                     SessionProjection(status: "completed", agentName: "made-up-agent", projectID: "proj-1", turns: turns)]
        var stages: [QuickStartFlow.Progress] = []
        let outcome = await rig.flow.perform(rig.message(), progress: { stages.append($0) })
        #expect(outcome == .sent(.sent, sentence: "Sent."))
        #expect(stages == [.committed, .checking])
        #expect(rig.writes.count == 1)
        #expect(rig.log == ["read", "write", "turns"])
    }

    @Test func aMessageWithNoAnswerThatTheSessionDoesntShowCanBeSentAgain() async {
        rig.writeReply = .unknown
        rig.reads = [FlowRig.session("completed"), SessionProjection(status: "completed", agentName: "made-up-agent", projectID: "proj-1", turns: [])]
        let outcome = await rig.flow.perform(rig.message())
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.sendNotThere))
        #expect(rig.writes.count == 1)
    }

    @Test func aMessageWithNoAnswerThatCantBeLookedForIsUnknown() async {
        rig.writeReply = .unknown
        rig.reads = [FlowRig.session("completed"), nil]
        let outcome = await rig.flow.perform(rig.message())
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.sendUnsure))
        #expect(rig.writes.count == 1)
    }

    @Test func anUploadWithNoAnswerMayBeInTheProjectAndNothingIsStarted() async throws {
        rig.upload = .unknown
        let outcome = await rig.flow.perform(rig.newSession(files: [try rig.file("a.csv")]))
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.uploadUnsure("a.csv", project: "Made-up", starting: true)))
        #expect(outcome.sentence.contains("Not sure"))
        #expect(rig.writes.isEmpty)
        #expect(!rig.log.contains("create"))
    }

    @Test func anUploadThatNeverReturnsIsCutOffAndMayBeInTheProject() async throws {
        // The Swift side's own deadline for the upload, beyond the page's: nothing is started.
        rig.holdUploads = true
        rig.uploadsRunOutOfTime = true
        let outcome = await rig.flow.perform(rig.newSession(files: [try rig.file("a.csv")]))
        #expect(outcome == .failed(sentence: QuickStartFlow.Sentence.uploadUnsure("a.csv", project: "Made-up", starting: true)))
        #expect(rig.writes.isEmpty)
        rig.gate.open()
        for _ in 0..<60 { await Task.yield() }
    }

    @Test func aTurnThatStallsEndsUnknownAndTheNextMessageGoes() async {
        // The session read never returns: the turn is given up, and the next message is not held behind it.
        rig.holdReads = [0]
        rig.turnLimit = .milliseconds(60)
        let flow = rig.flow
        let stuck = Task { @MainActor in await flow.perform(rig.message("First")) }
        for _ in 0..<2_000 where rig.gate.holding == 0 { await Task.yield() }
        let next = Task { @MainActor in await flow.perform(rig.message("Second", intent: otherIntent)) }
        let first = await stuck.value
        #expect(first == .failed(sentence: QuickStartFlow.Sentence.sendUnsure))
        let second = await next.value
        #expect(second == .sent(.sent, sentence: "Sent."))
        #expect(rig.writes.count == 1, "only the second message was written")
        rig.gate.open()
        for _ in 0..<60 { await Task.yield() }
    }
}

// MARK: The panel over the real flow

/// The panel's Cancel and the flow's checkpoints, together: what the person presses and what is sent.
@MainActor
struct QuickStartPanelCancelTests {
    private let rig = FlowRig()
    private var closed = Counter()

    @MainActor
    private final class Counter {
        var count = 0
    }

    private func model(file: QuickStartFile? = nil) -> QuickStartModel {
        let counter = closed
        let made = QuickStartModel(dependencies: QuickStartModel.Dependencies(
            recipes: { [] },
            recentProjects: { [QuickStartProject(id: "proj-1", name: "Made-up")] },
            allProjects: { nil },
            viewed: { nil },
            sender: rig.flow,
            makeFile: { _ in file.map { .success($0) } ?? .failure(.unreadable("x")) },
            close: { counter.count += 1 },
            linger: .milliseconds(1),
            sleep: { _ in }))
        made.open()
        return made
    }

    private func settle() async {
        for _ in 0..<80 { await Task.yield() }
    }

    @Test func cancelBeforeAnythingWasSentClosesThePanelAndSendsNothing() async {
        rig.holdProjects = true
        let panel = model()
        await settle()
        panel.text = "QC this export"
        panel.submit()
        for _ in 0..<2_000 where rig.gate.holding == 0 { await Task.yield() }
        #expect(panel.phase == .sending)
        panel.cancel()
        // The panel waits for the flow to say nothing went; then it goes, with the words kept.
        for _ in 0..<2_000 where panel.phase == .sending { await Task.yield() }
        #expect(panel.phase == .editing)
        #expect(closed.count == 1)
        #expect(panel.text == "QC this export")
        rig.gate.open()
        await settle()
        #expect(rig.writes.isEmpty && rig.uploads.isEmpty)
    }

    @Test func cancelWithAnUploadOnItsWayKeepsThePanelAndSaysSoAndNothingStarts() async throws {
        rig.holdUploads = true
        let file = try rig.file("a.csv")
        let panel = model(file: file)
        await settle()
        panel.text = "QC this export"
        panel.addFiles([file.url])
        panel.submit()
        for _ in 0..<2_000 where rig.gate.holding == 0 { await Task.yield() }
        panel.cancel()
        for _ in 0..<2_000 where panel.phase == .sending { await Task.yield() }
        #expect(panel.phase == .failed("Cancelled. A file may already be in Made-up. Nothing was started."))
        #expect(closed.count == 0)
        #expect(panel.files.count == 1 && panel.text == "QC this export")
        rig.gate.open()
        await settle()
        #expect(rig.writes.isEmpty, "the upload is let go and no session follows it")
        // Cancel once more, with nothing sending: the panel goes.
        panel.cancel()
        #expect(closed.count == 1)
    }

    @Test func cancelOnceTheSessionIsBeingMadeShowsItStartedNotCancelled() async {
        rig.holdCreate = true
        let panel = model()
        await settle()
        panel.text = "QC this export"
        panel.submit()
        for _ in 0..<2_000 where rig.gate.holding == 0 { await Task.yield() }
        #expect(panel.progress == .committed)
        panel.cancel()
        #expect(panel.phase == .sending)
        #expect(panel.sendingLine == "Already sent. Waiting for Claude Science…")
        rig.gate.open()
        for _ in 0..<2_000 where panel.phase == .sending { await Task.yield() }
        #expect(panel.phase == .sent("Started in Made-up."))
        await settle()
        #expect(closed.count == 1)
        #expect(rig.writes.count == 1)
    }

    @Test func aWriteWithNoAnswerShowsTheLineThenAsksForARetryThePersonMakes() async {
        rig.createReplies = [.unknown]
        rig.intents = [nil, nil]
        let panel = model()
        await settle()
        panel.text = "QC this export"
        panel.submit()
        for _ in 0..<2_000 where panel.phase == .sending { await Task.yield() }
        #expect(panel.phase == .failed(QuickStartFlow.Sentence.startNotThere))
        #expect(rig.writes.count == 1, "nothing was sent again on its own")
        #expect(closed.count == 0)
        // The person presses Start again: the same intent id, so a session that did start is found.
        rig.createReplies = [RemoteWriteResult(status: 409, code: "intent_conflict")]
        rig.intents = [newID]
        panel.submit()
        for _ in 0..<2_000 where panel.phase == .sending || panel.phase == .failed(QuickStartFlow.Sentence.startNotThere) { await Task.yield() }
        #expect(panel.phase == .sent("Started in Made-up."))
        #expect(rig.writes.count == 2)
        #expect(rig.writes[0] == rig.writes[1], "the same request, the same intent id")
        await settle()
    }
}
