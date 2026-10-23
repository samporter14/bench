// RemotePhotos.swift — sending a photo from the phone (DESIGN.md, Bench on
// your phone → Phase 4: Photos): `POST /api/sessions/<id>/photo` and
// `POST /api/projects/<pid>/photo`. Each one checks what the other writes
// check (actions on, six a minute, a session or project the phone may use),
// turns the picture into a clean JPEG (RemotePhoto.swift), uploads it to the
// project from inside the page (RemotePhotoUpload.swift), and then sends the
// message, or starts the session, exactly as the message and new-session
// routes do, with the attachment line after the text.
//
// The flow reuses their decisions rather than copying them: `RemoteDecide`
// and its replies for a session (the fresh read, the mode, the agent and the
// project from that read, the phone's id as the intent), and
// `RemoteBrowser.start` for a new one (the project list, `plan_mode`, the
// look for an intent whose answer was lost).
//
// The two daemon calls aren't atomic. A session that can't take the message
// is found out before anything is uploaded; past that, an upload that worked
// and a send that didn't is `unavailable` with its own sentence, and nothing
// is deleted. A retry of the same photo under the same intent id reuses the
// upload (kept ten minutes), so a send that didn't answer leaves one copy in
// the project, not one a try. Nothing here logs; the server logs the route's
// pattern and status.
import CryptoKit
import Foundation

@MainActor
final class RemotePhotos {
    static let shared = RemotePhotos(sessions: .shared, browser: .shared, dependencies: .live())

    enum Sentence {
        /// The upload wasn't made, or its answer wasn't what Bench expects.
        static let notAttached = "Couldn't attach the photo from here. Send it from your Mac."
        /// The upload went and the message didn't.
        static let savedNotSent = "The photo was saved to the project, but the message didn't send. Open it on your Mac."
        /// The upload went, the message got no answer, and the session doesn't show it.
        static let savedNotThere = "The photo was saved to the project, but the message didn't go through. Try again."
        /// The upload went, the message got no answer, and the session couldn't be read to see.
        static let savedUnsure = "The photo was saved to the project. Not sure the message went through: look at the session on your Mac before you try again."
        /// The upload got no answer: the photo may be in the project.
        static let uploadUnsure = "Not sure the photo reached the project. Nothing was sent. Try again, or send it from your Mac."
        /// The upload went, a new session's write got no answer, and none shows.
        static let startNotThere = "The photo was saved to the project, but no new session shows. Try again: it won't start twice."
    }

    struct Dependencies {
        /// The upload to a project: nil when it didn't complete.
        var upload: @MainActor (_ project: String, _ photo: PhotoFile) async -> PhotoUploadReply?

        static func live() -> Dependencies {
            Dependencies(upload: { project, photo in
                guard Demo.mode == nil else { return nil }
                return await WebContainer.shared.uploadAnswer(project: project, file: photo.upload)
            })
        }
    }

    /// How long an upload is remembered by its intent id.
    static let uploadedLifetime: TimeInterval = 10 * 60
    private static let uploadedLimit = 20

    /// An upload that went, for a retry of the same photo (the same intent id
    /// and the same bytes, to the same project).
    private struct Uploaded {
        let digest: SHA256Digest
        let project: String
        let attachment: PhotoAttachment
        let at: Date
    }

    let sessions: RemoteSessions
    let browser: RemoteBrowser
    private let dependencies: Dependencies
    private var uploaded: [String: Uploaded] = [:]

    init(sessions: RemoteSessions, browser: RemoteBrowser, dependencies: Dependencies) {
        self.sessions = sessions
        self.browser = browser
        self.dependencies = dependencies
    }

    func respond(_ route: RemotePhotoRoute, device: String, body: Data) async -> RemoteActionReply {
        switch route {
        case .session(let id): await sessionPhoto(id, device: device, body: body)
        case .project(let id): await projectPhoto(id, device: device, body: body)
        }
    }

    // MARK: A session

    /// Actions on (403), within the device's limit (429), a session the phone
    /// may open (404), a body that fits (400; 400 `reference`), a picture
    /// that is one (415, 413); then, one at a time per session with its other
    /// actions, the check, the upload and the send.
    private func sessionPhoto(_ id: String, device: String, body: Data) async -> RemoteActionReply {
        guard sessions.photoDependencies.actionsOn() else { return .actionsOff }
        guard sessions.allowAction(device: device) else { return .tooMany }
        guard await sessions.admitted(id) != nil else { return .notFound }
        let request: PhotoRequest
        switch await parse(body, project: false) {
        case .failure(let refusal): return refusal.reply
        case .success(let parsed): request = parsed
        }
        let photo: PhotoFile
        switch await process(request.image) {
        case .failure(let refusal): return refusal.reply
        case .success(let made): photo = made
        }
        let progress = Progress()
        return await sessions.actSerially(on: id, limit: WriteDeadline.turn(uploadBytes: [photo.data.count]),
                                          stalled: { progress.stalled }) { [weak self] in
            guard let self else { return .ok(.unavailable) }
            return await self.sendToSession(id, request: request, photo: photo, progress: progress)
        }
    }

    /// How far a photo's turn got, so that one that runs out of time can say
    /// what is known: nothing sent, a photo that may be in the project, one
    /// that is, or a message that may have gone.
    @MainActor
    private final class Progress {
        enum Stage { case reading, uploading, uploaded, sending }
        var stage = Stage.reading

        var stalled: RemoteActionReply {
            switch stage {
            case .reading: .ok(.notThere)
            case .uploading: .ok(.uploadUnsure)
            case .uploaded: .ok(.savedNotThere)
            case .sending: .ok(.savedUnsure)
            }
        }
    }

    private func sendToSession(_ id: String, request: PhotoRequest, photo: PhotoFile, progress: Progress) async -> RemoteActionReply {
        // First the check the message route makes, so that nothing is
        // uploaded for a session that can't take a message now (its status,
        // its agent and its project).
        let before = await sessions.photoDependencies.read(id, false)
        // A turn given up on while it read (it ran out of time, or its caller
        // went) uploads nothing: its answer has already been given.
        guard !Task.isCancelled else { return .ok(.notThere) }
        let probe = RemoteDecide.message(.message(text: PhotoText.title(text: request.text), intentID: request.intentID),
                                         session: id, fresh: before)
        let project: String
        switch probe {
        case .answer(let result): return .ok(result)
        case .write(.message(_, _, let named?, _, _, _)): project = named
        case .write: return .ok(.unavailable)
        }
        let attachment: PhotoAttachment, retried: Bool
        progress.stage = .uploading
        switch await attach(photo, request: request, to: project) {
        case .placed(let placed, let again): (attachment, retried) = (placed, again)
        case .failed: return .ok(.notAttached)
        case .unsure: return .ok(.uploadUnsure)
        case .notStarted: return .ok(.notThere)
        }
        progress.stage = .uploaded
        // Then the message route's own re-read, now the photo is up: the
        // status says send, queue or resume, and the agent is the one it names.
        let fresh = await sessions.photoDependencies.read(id, false)
        // Given up on while it read again: the photo is up, and the message never leaves (`send` holds it too).
        guard !Task.isCancelled else { return .ok(.savedNotThere) }
        let text = PhotoText.request(text: request.text, attachment: attachment)
        guard case .write(let write) = RemoteDecide.message(.message(text: text, intentID: request.intentID), session: id,
                                                            fresh: fresh, attachment: true),
              case .message(_, _, let sentTo?, _, _, _) = write, sentTo == project else { return .ok(.savedNotSent) }
        let delivered = await sessions.deliver(write, text: text, session: id, before: fresh, leaving: { progress.stage = .sending })
        var result = delivered.result
        // A retry the daemon refuses as a repeat (409): the first try went.
        if retried, delivered.reply?.status == 409 { result = RemoteActionResult(result: .sent, sentence: RemoteDecide.Sentence.sent) }
        switch result.result {
        case .sent, .queued, .resumed: return .ok(result)
        // Got no answer, and the session was read to see: it isn't there, or can't be told.
        case .retry: return .ok(.savedNotThere)
        case .unknown: return .ok(.savedUnsure)
        default: return .ok(.savedNotSent)
        }
    }

    // MARK: A new session

    /// The new-session route's order: browse on (403 `browseOff`), actions on
    /// (403), the limit (429), the body (400), a project the list shows (404,
    /// 503); then the picture, the upload and the session.
    private func projectPhoto(_ project: String, device: String, body: Data) async -> RemoteActionReply {
        guard browser.browseIsOn else { return RemoteBrowse.off }
        guard browser.actionsAreOn else { return .actionsOff }
        guard sessions.allowAction(device: device) else { return .tooMany }
        guard BrowseSQL.isProjectID(project) else { return .badRequest }
        let request: PhotoRequest
        switch await parse(body, project: true) {
        case .failure(let refusal): return refusal.reply
        case .success(let parsed): request = parsed
        }
        guard let projects = await browser.projectIDs() else { return RemoteBrowser.unreadable }
        guard projects.contains(project) else { return .notFound }
        let photo: PhotoFile
        switch await process(request.image) {
        case .failure(let refusal): return refusal.reply
        case .success(let made): photo = made
        }
        let attachment: PhotoAttachment
        switch await attach(photo, request: request, to: project) {
        case .placed(let placed, _): attachment = placed
        case .failed: return .ok(.notAttached)
        case .unsure: return .ok(.uploadUnsure)
        case .notStarted: return .ok(.notThere)
        }
        let started = NewSessionRequest(text: PhotoText.request(text: request.text, attachment: attachment),
                                        intentID: request.intentID, planFirst: request.planFirst, attachment: true)
        switch await browser.attempt(project, request: started, title: PhotoText.title(text: request.text)) {
        case .started(let reply): return reply
        case .notStarted: return .ok(.savedNotSent)
        case .notThere: return .ok(.startNotThere)
        }
    }

    // MARK: Shared

    /// The body read (5 MB of JSON and base64), off the main thread.
    private func parse(_ body: Data, project: Bool) async -> Result<PhotoRequest, PhotoRefusal> {
        await Task.detached(priority: .userInitiated) { PhotoRequest.parse(body, project: project) }.value
    }

    /// The picture decoded and drawn again, off the main thread.
    private func process(_ image: Data) async -> Result<PhotoFile, PhotoRefusal> {
        let now = sessions.photoDependencies.now()
        return await Task.detached(priority: .userInitiated) { PhotoImage.process(image, at: now) }.value
    }

    /// Where a photo ended up in the project.
    private enum Attached {
        /// Its place there, and whether an earlier try of this intent put it there.
        case placed(PhotoAttachment, retried: Bool)
        /// The upload wasn't made, or its answer wasn't what Bench expects.
        case failed
        /// The upload got no answer: the photo may be in the project.
        case unsure
        /// Its caller had been given up on before the upload began: nothing went.
        case notStarted
    }

    /// The photo's place in the project: what an earlier try of this intent
    /// uploaded (the same bytes, the same project, within ten minutes, and
    /// `retried`), else a new upload, which is remembered.
    private func attach(_ photo: PhotoFile, request: PhotoRequest, to project: String) async -> Attached {
        let now = sessions.photoDependencies.now()
        uploaded = uploaded.filter { $0.value.at <= now && now.timeIntervalSince($0.value.at) < Self.uploadedLifetime }
        let digest = SHA256.hash(data: request.image)
        if let earlier = uploaded[request.intentID], earlier.digest == digest, earlier.project == project {
            return .placed(earlier.attachment, retried: true)
        }
        switch await upload(photo, to: project) {
        case .failed: return .failed
        case .unsure: return .unsure
        case .notStarted: return .notStarted
        case .placed(let made, _):
            uploaded[request.intentID] = Uploaded(digest: digest, project: project, attachment: made, at: now)
            while uploaded.count > Self.uploadedLimit, let oldest = uploaded.min(by: { $0.value.at < $1.value.at }) {
                uploaded[oldest.key] = nil
            }
            return .placed(made, retried: false)
        }
    }

    /// The upload, and what the daemon says it stored; `failed` unless it
    /// passed the page's gate and is the 200 the gate wants.
    private func upload(_ photo: PhotoFile, to project: String) async -> Attached {
        // The last moment to stop: a caller given up on starts no upload.
        guard !Task.isCancelled else { return .notStarted }
        guard BrowseSQL.isProjectID(project), let reply = await dependencies.upload(project, photo) else { return .failed }
        if reply.isUnknown { return .unsure }
        guard reply.status == 200, let upload = reply.upload,
              upload.filename == photo.name, upload.contentType == photo.contentType, upload.sizeBytes == photo.data.count
        else { return .failed }
        return .placed(upload, retried: false)
    }

    // MARK: `--demo remote`

    /// An upload that goes nowhere: the picture is still checked and drawn
    /// again, so a garbage photo is refused in the demo too, and the
    /// daemon's answer is made up. No web view is touched.
    static func demo(sessions: RemoteSessions, browser: RemoteBrowser) -> RemotePhotos {
        RemotePhotos(sessions: sessions, browser: browser, dependencies: Dependencies(upload: { _, photo in
            PhotoUploadReply(status: 200, upload: PhotoAttachment(
                id: UUID().uuidString.lowercased(), versionID: UUID().uuidString.lowercased(), filename: photo.name,
                contentType: photo.contentType, sizeBytes: photo.data.count))
        }))
    }
}

extension RemoteActionResult {
    static let notAttached = RemoteActionResult(result: .unavailable, sentence: RemotePhotos.Sentence.notAttached)
    static let savedNotSent = RemoteActionResult(result: .unavailable, sentence: RemotePhotos.Sentence.savedNotSent)
    static let savedNotThere = RemoteActionResult(result: .retry, sentence: RemotePhotos.Sentence.savedNotThere)
    static let savedUnsure = RemoteActionResult(result: .unknown, sentence: RemotePhotos.Sentence.savedUnsure)
    static let uploadUnsure = RemoteActionResult(result: .unknown, sentence: RemotePhotos.Sentence.uploadUnsure)
    static let startNotThere = RemoteActionResult(result: .retry, sentence: RemotePhotos.Sentence.startNotThere)
}
