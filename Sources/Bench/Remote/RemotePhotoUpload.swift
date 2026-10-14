// RemotePhotoUpload.swift — the photo's upload to Claude Science, made from
// inside the page the way the other writes are (SessionWriter.swift): the
// page's cookie session and CSRF secret carry it, and Bench never holds
// either. One route and no other, `POST /api/projects/<pid>/attachments`
// (the composer's paperclip), multipart with one `file` part.
//
// The page builds the path and the form from typed arguments, never from a
// string Swift put together, and checks them again there: a project id of
// the shape `^[A-Za-z0-9_-]{1,64}$`, the one file name Bench gives a photo,
// `image/jpeg`, and base64 whose length agrees with the size. The reply is
// held to the same gate before anything comes back: 200, JSON, UUID `id` and
// `version_id`, the same file name and content type, and `size_bytes` equal
// to what was sent. Only those five fields reach Swift. `file_path` (an
// absolute path on the Mac) and `root_frame_id` (the project's hidden uploads
// frame, not a session) are dropped.
import Foundation
import WebKit

// MARK: What the page says

/// What an upload answered: the HTTP status, and, only when it passed the
/// gate, what the daemon says it stored.
struct PhotoUploadReply: Equatable, Sendable {
    let status: Int
    /// The body's `code`, when it is a short identifier.
    let code: String?
    let upload: PhotoAttachment?

    init(status: Int, code: String? = nil, upload: PhotoAttachment? = nil) {
        self.status = status
        self.code = code
        self.upload = upload
    }

    /// The page's summary, checked again against what was sent. Nil when it
    /// isn't one; an upload that doesn't match what was sent is a reply with
    /// none.
    init?(object: Any?, sent: PhotoFile) {
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
    /// no DOM. `MAX_BYTES` is `PhotoImage.maxBytes` (3 MiB), a test holds
    /// the two together.
    static let builder = #"""
    function benchBuildUpload(a) {
        "use strict";
        const MAX_BYTES = 3145728;
        if (a === null || typeof a !== "object" || Array.isArray(a)) { return null; }
        if (typeof a.projectId !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(a.projectId)) { return null; }
        if (typeof a.filename !== "string" || !/^phone-photo-[0-9]{8}-[0-9]{6}\.jpg$/.test(a.filename)) { return null; }
        if (a.contentType !== "image/jpeg") { return null; }
        if (typeof a.size !== "number" || !Number.isInteger(a.size) || a.size < 1 || a.size > MAX_BYTES) { return null; }
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
    /// `contentType`, `data` (base64) and `size`. Answers a JSON string:
    /// `{"result":{…}}`, `{"refused":true}` (the arguments make no upload) or
    /// `{"failed":true}` (the request didn't complete).
    ///
    /// The form is built again for the retry after a stale CSRF secret, and
    /// `Content-Type` is left to `fetch`, which adds the boundary.
    static let body = builder + "\n" + summarizer + #"""

    const build = benchBuildUpload({ projectId: projectId, filename: filename, contentType: contentType,
                                     data: data, size: size });
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
    const signal = () => typeof AbortSignal === "function" && typeof AbortSignal.timeout === "function"
        ? AbortSignal.timeout(60000) : undefined;
    const send = async () => {
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
                signal: signal(),
            });
        } catch (e) { return null; }
        let reply = "";
        try { reply = await response.text(); } catch (e) { reply = ""; }
        return benchSummarizeUpload(response.status, reply, build);
    };
    let result = await send();
    if (result !== null && result.status === 403 && result.code === "csrf_stale") {
        try { await fetch("/api/csrf", { credentials: "include", cache: "no-store" }); } catch (e) { }
        result = await send();
    }
    return JSON.stringify(result === null ? { failed: true } : { result: result });
    """#

    /// The script's arguments for a photo going to `project`.
    static func arguments(project: String, photo: PhotoFile) -> [String: Any] {
        ["projectId": project, "filename": photo.name, "contentType": photo.contentType,
         "data": photo.data.base64EncodedString(), "size": photo.data.count]
    }

    /// The page's answer, checked again here against what was sent.
    static func result(of data: Data, sent: PhotoFile) throws -> PhotoUploadReply {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw WebAPIError.badResponse
        }
        if Pick.bool(root["refused"]) == true { throw WebAPIError.notAllowed }
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
        guard status == .ready else { throw WebAPIError.notReady }
        let value = try await webView.callAsyncJavaScript(PhotoUploadScript.body,
                                                          arguments: PhotoUploadScript.arguments(project: project, photo: photo),
                                                          in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        let reply = try PhotoUploadScript.result(of: Data(text.utf8), sent: photo)
        if reply.status == 401 { sessionLost() }
        return reply
    }
}
