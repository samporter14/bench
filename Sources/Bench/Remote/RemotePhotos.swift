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
// is deleted. Nothing here logs; the server logs the route's pattern and
// status.
import Foundation

@MainActor
final class RemotePhotos {
    static let shared = RemotePhotos(sessions: .shared, browser: .shared, dependencies: .live())

    enum Sentence {
        /// The upload wasn't made, or its answer wasn't what Bench expects.
        static let notAttached = "Couldn't attach the photo from here. Send it from your Mac."
        /// The upload went and the message didn't.
        static let savedNotSent = "The photo was saved to the project, but the message didn't send. Open it on your Mac."
    }

    struct Dependencies {
        /// The upload to a project: nil when it didn't complete.
        var upload: @MainActor (_ project: String, _ photo: PhotoFile) async -> PhotoUploadReply?

        static func live() -> Dependencies {
            Dependencies(upload: { project, photo in
                guard Demo.mode == nil else { return nil }
                return try? await WebContainer.shared.uploadPhoto(project: project, photo: photo)
            })
        }
    }

    let sessions: RemoteSessions
    let browser: RemoteBrowser
    private let dependencies: Dependencies

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
        return await sessions.actSerially(on: id) { [weak self] in
            guard let self else { return .ok(.unavailable) }
            return await self.sendToSession(id, request: request, photo: photo)
        }
    }

    private func sendToSession(_ id: String, request: PhotoRequest, photo: PhotoFile) async -> RemoteActionReply {
        // First the check the message route makes, so that nothing is
        // uploaded for a session that can't take a message now (its status,
        // its agent and its project).
        let before = await sessions.photoDependencies.read(id, false)
        let probe = RemoteDecide.message(.message(text: PhotoText.title(text: request.text), intentID: request.intentID),
                                         session: id, fresh: before)
        let project: String
        switch probe {
        case .answer(let result): return .ok(result)
        case .write(.message(_, _, let named?, _, _)): project = named
        case .write: return .ok(.unavailable)
        }
        guard let attachment = await upload(photo, to: project) else { return .ok(.notAttached) }
        // Then the message route's own re-read, now the photo is up: the
        // status says send, queue or resume, and the agent is the one it names.
        let fresh = await sessions.photoDependencies.read(id, false)
        let text = PhotoText.request(text: request.text, attachment: attachment)
        guard case .write(let write) = RemoteDecide.message(.message(text: text, intentID: request.intentID), session: id, fresh: fresh),
              case .message(_, _, let sentTo?, _, _) = write, sentTo == project else { return .ok(.savedNotSent) }
        let result = RemoteDecide.messaged(await sessions.photoDependencies.write(write), status: fresh?.status ?? "")
        switch result.result {
        case .sent, .queued, .resumed: return .ok(result)
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
        guard let attachment = await upload(photo, to: project) else { return .ok(.notAttached) }
        let started = NewSessionRequest(text: PhotoText.request(text: request.text, attachment: attachment),
                                        intentID: request.intentID, planFirst: request.planFirst)
        return await browser.start(project, request: started, title: PhotoText.title(text: request.text))
            ?? .ok(.savedNotSent)
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

    /// The upload, and what the daemon says it stored; nil unless it passed
    /// the page's gate and is the 200 the gate wants.
    private func upload(_ photo: PhotoFile, to project: String) async -> PhotoAttachment? {
        guard BrowseSQL.isProjectID(project),
              let reply = await dependencies.upload(project, photo), reply.status == 200, let upload = reply.upload,
              upload.filename == photo.name, upload.contentType == photo.contentType, upload.sizeBytes == photo.data.count
        else { return nil }
        return upload
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
}
