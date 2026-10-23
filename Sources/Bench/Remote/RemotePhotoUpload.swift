// RemotePhotoUpload.swift — an upload to Claude Science, made from inside the
// page the way the other writes are (SessionWriter.swift): the page's cookie
// session and CSRF secret carry it, and Bench never holds either. One route
// and no other, `POST /api/projects/<pid>/attachments` (the composer's
// paperclip), multipart with one `file` part.
//
// Two kinds go up. A phone's photo (the default, and the only kind before
// Quick Start): the one file name Bench gives a photo and `image/jpeg`, 3 MiB
// at most. A file from the Mac (`kind: "file"`, Quick Start): a name of up to
// 120 characters with no path, brace, quote or control character in it, a
// content type of the shape `type/subtype`, 20 MiB at most. Which types Quick
// Start sends is Swift's rule (QuickStart/AttachmentRules.swift); the page
// holds the shape.
//
// The page builds the path and the form from typed arguments, never from a
// string Swift put together, and checks them again there: a project id of
// the shape `^[A-Za-z0-9_-]{1,64}$`, the kind's name and type, and base64
// whose length agrees with the size. The reply is held to the same gate
// before anything comes back: 200, JSON, UUID `id` and `version_id`, the same
// file name and content type, and `size_bytes` equal to what was sent. Only
// those five fields reach Swift. `file_path` (an absolute path on the Mac) and
// `root_frame_id` (the project's hidden uploads frame, not a session) are
// dropped.
//
// The whole upload has a deadline (Remote/WriteDeadline.swift): in the page,
// one AbortController over the CSRF refresh, the POST and its answer, sized by
// the file; in Swift, a little more. An upload that got no answer in time may
// or may not be in the project: `PhotoUploadReply.unknown`.
import Foundation
import WebKit

// MARK: What goes up

/// A file as the upload sends it: its bytes, the name it will have in the
/// project and its content type.
struct UploadFile: Equatable, Sendable {
    enum Kind: String, Sendable {
        /// A phone's photo: `PhotoImage`'s JPEG, named by `PhotoImage.fileName`.
        case photo
        /// A file from the Mac, as Quick Start sends one.
        case file
    }

    let data: Data
    let name: String
    let contentType: String
    let kind: Kind

    /// The most a file from the Mac may be: `FILE_MAX` in the page's script,
    /// which a test holds to this.
    static let maxFileBytes = 20 * 1024 * 1024
}

extension PhotoFile {
    var upload: UploadFile { UploadFile(data: data, name: name, contentType: contentType, kind: .photo) }
}

// MARK: What the page says

/// What an upload answered: the HTTP status, and, only when it passed the
/// gate, what the daemon says it stored.
struct PhotoUploadReply: Equatable, Sendable {
    let status: Int
    /// The body's `code`, when it is a short identifier.
    let code: String?
    let upload: PhotoAttachment?
    /// The upload went out and no answer came back in time, or at all: the
    /// file may be in the project. Nothing in Claude Science can be asked
    /// whether it is, so a caller says so and leaves the next try to the person.
    let isUnknown: Bool

    /// What an upload that got no answer is.
    static let unknown = PhotoUploadReply(status: 0, isUnknown: true)

    init(status: Int, code: String? = nil, upload: PhotoAttachment? = nil, isUnknown: Bool = false) {
        self.status = status
        self.code = code
        self.upload = upload
        self.isUnknown = isUnknown
    }

    /// The page's summary, checked again against what was sent. Nil when it
    /// isn't one; an upload that doesn't match what was sent is a reply with
    /// none.
    init?(object: Any?, sent: PhotoFile) {
        self.init(object: object, sent: sent.upload)
    }

    /// The same for any file.
    init?(object: Any?, sent: UploadFile) {
        guard let fields = object as? [String: Any], let status = Pick.int(fields["status"]), (100...599).contains(status),
              let code = Pick.string(fields["code"]) else { return nil }
        guard code.isEmpty || RemoteWriteResult.isCode(code) else { return nil }
        var upload: PhotoAttachment?
        if !Pick.isNull(fields["upload"]) {
            guard let given = fields["upload"] as? [String: Any], let id = Pick.string(given["id"]),
                  let version = Pick.string(given["version_id"]), let name = Pick.string(given["filename"]),
                  let type = Pick.string(given["content_type"]), let size = Pick.int(given["size_bytes"]),
                  PhotoAttachment.isUUID(id), PhotoAttachment.isUUID(version), name == sent.name, type == sent.contentType,
                  size == sent.data.count, status == 200 else { return nil }
            upload = PhotoAttachment(id: id, versionID: version, filename: name, contentType: type, sizeBytes: size)
        }
        self.init(status: status, code: code.isEmpty ? nil : code, upload: upload)
    }
}

// MARK: The script

enum PhotoUploadScript {
    /// `benchBuildUpload(args)` → `{path, filename, contentType, size, data}`,
    /// or null when the arguments don't make the one upload. Pure: no fetch,
    /// no DOM. `MAX_BYTES` is `PhotoImage.maxBytes` (3 MiB) and `FILE_MAX` is
    /// `UploadFile.maxFileBytes` (20 MiB); a test holds each pair together.
    static let builder = #"""
    function benchBuildUpload(a) {
        "use strict";
        const MAX_BYTES = 3145728;
        const FILE_MAX = 20971520;
        if (a === null || typeof a !== "object" || Array.isArray(a)) { return null; }
        if (typeof a.projectId !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(a.projectId)) { return null; }
        // No kind is a photo: what every caller before Quick Start sends.
        const kind = a.kind === undefined ? "photo" : a.kind;
        let max = MAX_BYTES;
        if (kind === "photo") {
            if (typeof a.filename !== "string" || !/^phone-photo-[0-9]{8}-[0-9]{6}\.jpg$/.test(a.filename)) { return null; }
            if (a.contentType !== "image/jpeg") { return null; }
        } else if (kind === "file") {
            max = FILE_MAX;
            if (typeof a.filename !== "string" || a.filename === "." || a.filename === ".." || a.filename !== a.filename.trim()
                || !/^[^\/\\"{}:*?<>|\u0000-\u001f\u007f]{1,120}$/.test(a.filename)) { return null; }
            if (typeof a.contentType !== "string"
                || !/^[a-z0-9][a-z0-9.+-]{0,60}\/[a-z0-9][a-z0-9.+-]{0,100}$/.test(a.contentType)) { return null; }
        } else {
            return null;
        }
        if (typeof a.size !== "number" || !Number.isInteger(a.size) || a.size < 1 || a.size > max) { return null; }
        if (typeof a.data !== "string" || a.data.length !== 4 * Math.ceil(a.size / 3)
            || !/^[A-Za-z0-9+\/]+={0,2}$/.test(a.data)) { return null; }
        return { path: "/api/projects/" + a.projectId + "/attachments", filename: a.filename,
                 contentType: a.contentType, size: a.size, data: a.data };
    }
    """#

    /// `benchSummarizeUpload(status, text, sent)`: `{status, code, upload}`,
    /// where `upload` is null unless the reply passes the gate.
    static let summarizer = #"""
    function benchSummarizeUpload(status, raw, sent) {
        "use strict";
        const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        const text = typeof raw === "string" ? raw : "";
        let json = null;
        try { json = JSON.parse(text); } catch (e) { json = null; }
        const isObject = json !== null && typeof json === "object" && !Array.isArray(json);
        const code = isObject && typeof json.code === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(json.code) ? json.code : "";
        let upload = null;
        if (status === 200 && isObject
            && typeof json.id === "string" && UUID.test(json.id)
            && typeof json.version_id === "string" && UUID.test(json.version_id)
            && json.filename === sent.filename && json.content_type === sent.contentType
            && typeof json.size_bytes === "number" && json.size_bytes === sent.size) {
            upload = { id: json.id, version_id: json.version_id, filename: json.filename,
                       content_type: json.content_type, size_bytes: json.size_bytes };
        }
        return { status: typeof status === "number" ? status : 0, code: code, upload: upload };
    }
    """#

    /// What `callAsyncJavaScript` runs, with `projectId`, `filename`,
    /// `contentType`, `data` (base64), `size` and `timeoutMS`. Answers a JSON
    /// string: `{"result":{…}}`, `{"refused":true}` (the arguments make no
    /// upload), `{"failed":true}` (the file couldn't be put together) or
    /// `{"unknown":true}` (no answer came back in time, or at all).
    ///
    /// The form is built again for the retry after a stale CSRF secret, and
    /// `Content-Type` is left to `fetch`, which adds the boundary. The refresh
    /// and the POSTs share one deadline (`WriteScript.bounded`); as for the
    /// other writers, a deadline that passes during the refresh leaves the
    /// first POST's 403 as the answer.
    static let body = WriteScript.bounded + "\n" + builder + "\n" + summarizer + #"""

    // `kind` is only there for a file from the Mac; a photo's callers leave it out.
    const build = benchBuildUpload({ projectId: projectId, filename: filename, contentType: contentType,
                                     data: data, size: size, kind: typeof kind === "string" ? kind : "photo" });
    if (build === null) { return JSON.stringify({ refused: true }); }
    let blob = null;
    try {
        const binary = atob(build.data);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
        blob = new Blob([bytes], { type: build.contentType });
    } catch (e) { return JSON.stringify({ failed: true }); }
    if (blob.size !== build.size) { return JSON.stringify({ refused: true }); }
    const secret = () => {
        const entry = document.cookie.split(";").map(part => part.trim())
            .find(part => part.startsWith("operon_csrf="));
        if (!entry) { return ""; }
        const value = entry.slice("operon_csrf=".length);
        try { return decodeURIComponent(value); } catch (e) { return value; }
    };
    let refused = null;
    const outcome = await benchBounded(timeoutMS, async (signal) => {
        const send = async () => {
            if (signal && signal.aborted) { return null; }
            const form = new FormData();
            form.append("file", blob, build.filename);
            let response;
            try {
                response = await fetch(build.path, {
                    method: "POST",
                    credentials: "include",
                    cache: "no-store",
                    headers: { "Accept": "application/json", "x-operon-csrf": secret() },
                    body: form,
                    signal: signal,
                });
            } catch (e) { return null; }
            let reply = "";
            try { reply = await response.text(); } catch (e) { if (signal && signal.aborted) { return null; } reply = ""; }
            if (signal && signal.aborted) { return null; }
            return benchSummarizeUpload(response.status, reply, build);
        };
        let result = await send();
        if (result !== null && result.status === 403 && result.code === "csrf_stale") {
            refused = result;
            try { await fetch("/api/csrf", { credentials: "include", cache: "no-store", signal: signal }); } catch (e) { }
            if (signal && signal.aborted) { return null; }
            refused = null;
            result = await send();
        }
        return result === null ? { unknown: true } : { result: result };
    });
    if (outcome === null || outcome.timedOut === true || outcome.unknown === true) {
        return JSON.stringify(refused !== null ? { result: refused } : { unknown: true });
    }
    return JSON.stringify(outcome);
    """#

    /// The script's arguments for a photo going to `project`.
    static func arguments(project: String, photo: PhotoFile) -> [String: Any] {
        arguments(project: project, file: photo.upload)
    }

    /// The script's arguments for any file going to `project`.
    static func arguments(project: String, file: UploadFile) -> [String: Any] {
        ["projectId": project, "filename": file.name, "contentType": file.contentType,
         "data": file.data.base64EncodedString(), "size": file.data.count, "kind": file.kind.rawValue,
         "timeoutMS": WriteDeadline.milliseconds(WriteDeadline.upload(bytes: file.data.count))]
    }

    /// The page's answer, checked again here against what was sent.
    static func result(of data: Data, sent: PhotoFile) throws -> PhotoUploadReply {
        try result(of: data, sent: sent.upload)
    }

    /// The same for any file.
    static func result(of data: Data, sent: UploadFile) throws -> PhotoUploadReply {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw WebAPIError.badResponse
        }
        if Pick.bool(root["refused"]) == true { throw WebAPIError.notAllowed }
        if Pick.bool(root["unknown"]) == true { throw WebAPIError.timedOut }
        guard let reply = PhotoUploadReply(object: root["result"], sent: sent) else { throw WebAPIError.badResponse }
        return reply
    }
}

// MARK: Uploading through the page

extension WebContainer {
    /// Uploads a photo to a project from inside the page, as Claude Science's
    /// own composer does: the `operon_csrf` cookie's value as `x-operon-csrf`,
    /// the page's `Origin`, a 403 `csrf_stale` refreshed with `GET /api/csrf`
    /// and tried once more. Any status comes back as a reply; a 401 also
    /// starts signing in again.
    func uploadPhoto(project: String, photo: PhotoFile) async throws -> PhotoUploadReply {
        try await uploadFile(project: project, file: photo.upload)
    }

    /// The same for any file (`UploadFile`): a photo, or a file Quick Start
    /// sends from the Mac. Its deadline is sized by the file
    /// (`WriteDeadline.upload(bytes:)`); an upload that got no answer in time
    /// throws `WebAPIError.timedOut`. A caller already given up on starts
    /// nothing in the page (`PhotoUploadScript.upload`).
    func uploadFile(project: String, file: UploadFile) async throws -> PhotoUploadReply {
        guard status == .ready else { throw WebAPIError.notReady }
        let view = webView
        let reply = try await PhotoUploadScript.upload(file) {
            try await view.callAsyncJavaScript(PhotoUploadScript.body,
                                               arguments: PhotoUploadScript.arguments(project: project, file: file),
                                               in: nil, contentWorld: .defaultClient)
        }
        if reply.status == 401 { sessionLost() }
        return reply
    }
}

extension WebContainer {
    /// `uploadFile`, as the uploaders' dependencies want it: nil for an upload
    /// that was not made, the daemon's reply, or `PhotoUploadReply.unknown` for
    /// one that may have been (no answer in time, a page that threw).
    func uploadAnswer(project: String, file: UploadFile) async -> PhotoUploadReply? {
        await PhotoUploadScript.answer { try await self.uploadFile(project: project, file: file) }
    }
}

extension PhotoUploadScript {
    /// An upload as `WebContainer.uploadFile` makes it, `run` being the call
    /// into the page. A caller that has already been given up on (a turn that
    /// ran out of time, a Cancel) starts nothing there: `CancellationError`,
    /// before `run`. Once it has started, the call is waited for as any write
    /// is (`WriteDeadline.bridge`, which its caller's cancel doesn't take back),
    /// and no answer in time is `WebAPIError.timedOut`; so is a cancellation
    /// from inside the call, which may have sent it.
    @MainActor
    static func upload(_ file: UploadFile, wait: @escaping @MainActor (Duration) async -> Void = WriteDeadline.sleep,
                       run: @escaping @MainActor () async throws -> Any?) async throws -> PhotoUploadReply {
        guard !Task.isCancelled else { throw CancellationError() }
        let limit = WriteDeadline.upload(bytes: file.data.count) + WriteDeadline.grace
        let text: String?
        do {
            text = try await WriteDeadline.bridge(limit, wait: wait) { try await run() as? String }
        } catch is CancellationError {
            throw WebAPIError.timedOut
        }
        guard let text else { throw WebAPIError.badResponse }
        return try result(of: Data(text.utf8), sent: file)
    }

    /// How an upload ended, as its callers want it: nil for one that was not
    /// made (the page isn't up, it refused the arguments, or the caller had
    /// been given up on before it started), the daemon's reply, or
    /// `PhotoUploadReply.unknown` for one that may have been.
    @MainActor
    static func answer(_ attempt: @MainActor () async throws -> PhotoUploadReply) async -> PhotoUploadReply? {
        do {
            return try await attempt()
        } catch WebAPIError.notReady {
            return nil
        } catch WebAPIError.notAllowed {
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return .unknown
        }
    }
}
