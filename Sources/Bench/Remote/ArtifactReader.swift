// ArtifactReader.swift — reading a session's artifacts for the phone (DESIGN.md,
// Capsid on your phone → Phase 3: Artifacts), the in-page part. As the session
// reader does, the page makes the GET itself and hands Swift only what the
// route needs: the list projected to `{v, a, name, mime, size, at}`, a
// thumbnail's or a download's bytes as base64, or a text's first 256 KB
// decoded as UTF-8. Never `file_path`, `ref_host_path` or any other field.
//
// Exactly three GET shapes, built in the page from typed arguments and checked
// there against the allowlist before anything is fetched:
//   /api/frames/<36>/artifacts
//   /api/artifacts/versions/<v>?thumbnail=<120|800>
//   /api/artifacts/versions/<v>
// The scripts are plain JavaScript; the tests run these very strings in
// JavaScriptCore against a fake `fetch`. Swift checks every answer again
// (`ArtifactReaderScript.outcome`). Nothing read is logged or saved.
import Foundation
import WebKit

/// One read, as typed values. The page turns it into a path.
enum ArtifactRead: Hashable, Sendable {
    /// `GET /api/frames/<frame>/artifacts`: the session's list.
    case list(frame: String)
    /// `GET /api/artifacts/versions/<v>?thumbnail=<width>`: WebP, 120 or 800.
    case thumb(version: String, width: Int)
    /// `GET /api/artifacts/versions/<v>` with `Range: bytes=0-262143`.
    case text(version: String)
    /// `GET /api/artifacts/versions/<v>`, whole, up to 8 MB.
    case download(version: String)

    static let widths: Set<Int> = [120, 800]

    /// The script's arguments: every name always there, null when unused.
    var arguments: [String: Any] {
        switch self {
        case .list(let frame): ["op": "list", "frameId": frame, "versionId": NSNull(), "width": NSNull()]
        case .thumb(let version, let width): ["op": "thumb", "frameId": NSNull(), "versionId": version, "width": width]
        case .text(let version): ["op": "text", "frameId": NSNull(), "versionId": version, "width": NSNull()]
        case .download(let version): ["op": "download", "frameId": NSNull(), "versionId": version, "width": NSNull()]
        }
    }

    /// The path the page will GET, or nil when the arguments make none:
    /// the same rule as the script's `benchArtifactPath`.
    var path: String? {
        let path: String
        switch self {
        case .list(let frame):
            guard PlanCheck.isFrameID(frame) else { return nil }
            path = "/api/frames/\(frame)/artifacts"
        case .thumb(let version, let width):
            guard PlanCheck.isVersionID(version), Self.widths.contains(width) else { return nil }
            path = "/api/artifacts/versions/\(version)?thumbnail=\(width)"
        case .text(let version), .download(let version):
            guard PlanCheck.isVersionID(version) else { return nil }
            path = "/api/artifacts/versions/\(version)"
        }
        return Self.isAllowedPath(path) ? path : nil
    }

    /// The allowlist, byte by byte: the three shapes and nothing else.
    static func isAllowedPath(_ path: String) -> Bool {
        let frames = "/api/frames/", artifacts = "/artifacts", versions = "/api/artifacts/versions/"
        if path.hasPrefix(frames), path.hasSuffix(artifacts),
           path.utf8.count == frames.utf8.count + 36 + artifacts.utf8.count {
            return PlanCheck.isFrameID(String(path.dropFirst(frames.count).dropLast(artifacts.count)))
        }
        guard path.hasPrefix(versions) else { return false }
        let rest = path.dropFirst(versions.count)
        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard PlanCheck.isVersionID(String(parts[0])) else { return false }
        return parts.count == 1 || parts[1] == "thumbnail=120" || parts[1] == "thumbnail=800"
    }
}

/// One listed artifact, as the page projected it and Swift checked it.
struct ArtifactEntry: Equatable, Sendable {
    /// `version_id`: what `/api/files/<v>/…` names.
    let version: String
    /// The artifact's own id, when it was a usable one.
    let artifact: String?
    /// The file name's last segment, at most 255 characters.
    let name: String
    /// The media type alone (no parameters), lowercased, when it looked like one.
    let mime: String?
    /// `size_bytes`, as the list says (never trusted alone: downloads check again).
    let size: Int
    let at: Date?

    var kind: ArtifactKind { ArtifactKind.classify(name: name, mime: mime) }
}

/// What a read came to, checked again in Swift.
enum ArtifactReadOutcome: Equatable, Sendable {
    case list([ArtifactEntry])
    /// A thumbnail's or a download's bytes, within the cap.
    case bytes(Data)
    /// The text's first 256 KB, decoded; `truncated` when the file is longer.
    case text(String, truncated: Bool)
    /// A NUL in the first 8 KB: not text.
    case binary
    /// Over the cap (4 MB for a thumbnail, 8 MB for a download).
    case tooBig
    /// Anything unexpected: a failed fetch, another status, a shape that
    /// doesn't match.
    case unreadable
    /// A 401: the page's session didn't take.
    case lost
    /// A 404 or 410: the version (or the session's list) isn't there any
    /// more, deleted or expired. The phone's routes answer it as
    /// `unreadable`; the results shelf says which.
    case missing
    /// The results shelf withdrew the read and the page aborted its fetch
    /// (`benchAbortRead`). Never a failure, and never the phone's: its reads
    /// carry no nonce, so nothing can abort them.
    case cancelled
}

// MARK: The script

enum ArtifactReaderScript {
    /// The caps, shared by the script (passed in as numbers) and Swift's checks.
    enum Cap {
        static let list = 300
        static let thumb = 4 * 1024 * 1024
        static let text = 256 * 1024
        static let download = 8 * 1024 * 1024
        /// A NUL in this many first bytes means binary.
        static let sniff = 8 * 1024
        static let name = 255
        static let artifactID = 128
        static let mime = 255
    }

    /// `benchArtifactPath(op, frameId, versionId, width)`: the path, or null
    /// when the arguments make none. Pure.
    static let pathBuilder = #"""
    function benchArtifactPath(op, frameId, versionId, width) {
        "use strict";
        const FRAME = /^[0-9a-f-]{36}$/, VERSION = /^[A-Za-z0-9_-]{1,128}$/;
        // The allowlist, exactly: whatever was built must be one of these.
        const ALLOWED = [/^\/api\/frames\/[0-9a-f-]{36}\/artifacts$/,
                         /^\/api\/artifacts\/versions\/[A-Za-z0-9_-]{1,128}\?thumbnail=(120|800)$/,
                         /^\/api\/artifacts\/versions\/[A-Za-z0-9_-]{1,128}$/];
        const version = typeof versionId === "string" && VERSION.test(versionId) ? versionId : null;
        let path = null;
        if (op === "list" && typeof frameId === "string" && FRAME.test(frameId)) {
            path = "/api/frames/" + frameId + "/artifacts";
        } else if (op === "thumb" && version !== null && (width === 120 || width === 800)) {
            path = "/api/artifacts/versions/" + version + "?thumbnail=" + width;
        } else if ((op === "text" || op === "download") && version !== null) {
            path = "/api/artifacts/versions/" + version;
        }
        return path !== null && ALLOWED.some(rule => rule.test(path)) ? path : null;
    }
    """#

    /// `benchProjectArtifacts(raw, cap)`: the list as `{v, a, name, mime,
    /// size, at}`, the newest `cap` the UI shows, or null when a shape doesn't
    /// match. Pure: no fetch, no DOM.
    static let projection = #"""
    function benchProjectArtifacts(raw, cap) {
        "use strict";
        const VERSION = /^[A-Za-z0-9_-]{1,128}$/;
        // A media type, before any parameters.
        const MEDIA = /^[a-z0-9][a-z0-9!#$&^_.+-]{0,126}\/[a-z0-9][a-z0-9!#$&^_.+-]{0,126}$/;
        const EARLIEST = 946684800000, LATEST = 4102444800000;
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const cut = (text, limit) => {
            const all = Array.from(text);
            return all.length <= limit ? text : all.slice(0, limit - 1).join("") + "…";
        };
        // Control characters and direction overrides never reach a screen or a header.
        const clean = text => text.replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, "");
        const time = v => {
            let ms = null;
            if (typeof v === "number" && isFinite(v)) { ms = v < 1e11 ? v * 1000 : v; }
            else if (typeof v === "string") { const parsed = Date.parse(v); if (isFinite(parsed)) { ms = parsed; } }
            return ms !== null && ms >= EARLIEST && ms <= LATEST ? Math.round(ms) : null;
        };

        const rows = Array.isArray(raw) ? raw : isObject(raw) && Array.isArray(raw.artifacts) ? raw.artifacts : null;
        if (rows === null) { return null; }
        const kept = [];
        for (const row of rows) {
            if (!isObject(row)) { return null; }
            // The research's shape gate: a string id, a version id fit for a
            // path, a string name and type, a numeric size.
            if (typeof row.id !== "string" || typeof row.version_id !== "string" || !VERSION.test(row.version_id)
                || typeof row.filename !== "string" || typeof row.content_type !== "string"
                || typeof row.size_bytes !== "number" || !isFinite(row.size_bytes)
                || row.size_bytes < 0 || row.size_bytes > 1e15) { return null; }
            // What Claude Science's own UI hides.
            if (row.is_intermediate === true || row.priority === "user_hidden") { continue; }
            const base = row.filename.split(/[\\/]/).pop();
            if (/^plan.*\.json$/.test(base) || /^goal_.*\.html$/.test(base)) { continue; }
            const name = cut(clean(base).trim(), 255);
            const id = cut(clean(row.id).trim(), 128);
            const media = row.content_type.split(";")[0].trim().toLowerCase();
            kept.push({
                v: row.version_id,
                a: id === "" ? null : id,
                name: name === "" ? "file" : name,
                mime: MEDIA.test(media) ? media : null,
                size: Math.floor(row.size_bytes),
                at: time(row.created_at),
            });
        }
        // The list is oldest first: the newest are kept.
        return kept.slice(Math.max(0, kept.length - cap));
    }
    """#

    /// `benchBase64(bytes)` and `benchDecodeUTF8(bytes, truncated)`: the page
    /// has `btoa` and `TextDecoder`, but these are written out so the tests
    /// run the same code in JavaScriptCore, which has neither.
    /// `benchBase64Chunked(bytes)` encodes ~512 KB at a time and lets the
    /// page's main thread go between pieces: it also draws the user's own
    /// Claude Science UI, and 8 MB in one go held it ~50 ms (Fable's review
    /// of 0.5.0, P3).
    static let codecs = #"""
    function benchBase64(bytes) {
        "use strict";
        const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const codes = new Uint8Array(64);
        for (let i = 0; i < 64; i++) { codes[i] = ALPHABET.charCodeAt(i); }
        const n = bytes.length, out = new Uint8Array(Math.ceil(n / 3) * 4);
        let o = 0, i = 0;
        for (; i + 2 < n; i += 3) {
            const v = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
            out[o++] = codes[v >> 18]; out[o++] = codes[(v >> 12) & 63];
            out[o++] = codes[(v >> 6) & 63]; out[o++] = codes[v & 63];
        }
        if (i < n) {
            const two = i + 1 < n;
            const v = (bytes[i] << 16) | ((two ? bytes[i + 1] : 0) << 8);
            out[o++] = codes[v >> 18]; out[o++] = codes[(v >> 12) & 63];
            out[o++] = two ? codes[(v >> 6) & 63] : 61; out[o++] = 61;
        }
        const pieces = [];
        for (let at = 0; at < out.length; at += 32768) {
            pieces.push(String.fromCharCode.apply(null, out.subarray(at, at + 32768)));
        }
        return pieces.join("");
    }

    async function benchBase64Chunked(bytes) {
        "use strict";
        // A whole number of 3-byte groups (524,286 bytes, just under 512 KB):
        // each piece ends without padding, so the pieces join into the whole.
        const CHUNK = 3 * 174762;
        const pieces = [];
        for (let at = 0; at < bytes.length; at += CHUNK) {
            if (at > 0) {
                // A task's turn for the page in between (JavaScriptCore, in the
                // tests, has no timers: a microtask there).
                await (typeof setTimeout === "function" ? new Promise(r => setTimeout(r, 0)) : Promise.resolve());
            }
            pieces.push(benchBase64(bytes.subarray(at, at + CHUNK)));
        }
        return pieces.join("");
    }

    function benchDecodeUTF8(bytes, truncated) {
        "use strict";
        let end = bytes.length;
        // A sequence the range cut in two is dropped, not shown as U+FFFD.
        if (truncated) {
            let back = 0;
            while (back < 3 && back < end && (bytes[end - 1 - back] & 0xC0) === 0x80) { back++; }
            if (back < end) {
                const lead = bytes[end - 1 - back];
                const need = lead >= 0xF0 && lead <= 0xF4 ? 4 : lead >= 0xE0 && lead <= 0xEF ? 3
                    : lead >= 0xC2 && lead <= 0xDF ? 2 : 1;
                if (need > back + 1) { end = end - 1 - back; }
            }
        }
        // The WHATWG decoder: each bad sequence becomes one U+FFFD.
        const pieces = [], points = [];
        const flush = () => { pieces.push(String.fromCodePoint.apply(null, points)); points.length = 0; };
        let need = 0, seen = 0, cp = 0, lower = 0x80, upper = 0xBF;
        for (let i = 0; i < end; i++) {
            const b = bytes[i];
            if (need === 0) {
                if (b <= 0x7F) { points.push(b); }
                else if (b >= 0xC2 && b <= 0xDF) { need = 1; cp = b & 0x1F; }
                else if (b >= 0xE0 && b <= 0xEF) {
                    if (b === 0xE0) { lower = 0xA0; } else if (b === 0xED) { upper = 0x9F; }
                    need = 2; cp = b & 0x0F;
                } else if (b >= 0xF0 && b <= 0xF4) {
                    if (b === 0xF0) { lower = 0x90; } else if (b === 0xF4) { upper = 0x8F; }
                    need = 3; cp = b & 0x07;
                } else { points.push(0xFFFD); }
            } else if (b < lower || b > upper) {
                need = 0; seen = 0; cp = 0; lower = 0x80; upper = 0xBF;
                points.push(0xFFFD);
                // This byte starts something new.
                i--;
            } else {
                lower = 0x80; upper = 0xBF;
                cp = (cp << 6) | (b & 0x3F);
                if (++seen === need) { points.push(cp); need = 0; seen = 0; cp = 0; }
            }
            if (points.length >= 8192) { flush(); }
        }
        if (need !== 0) { points.push(0xFFFD); }
        flush();
        return pieces.join("");
    }
    """#

    /// The page-side map of the shelf's reads under way, nonce → AbortController,
    /// on `globalThis` of the reader's content world (never the page's own).
    static let readsName = "benchArtifactReads"

    /// What `callAsyncJavaScript` runs, with the arguments of
    /// `ArtifactRead.arguments` and `nonce` (a string for the shelf's reads,
    /// null or absent for the phone's). Answers a JSON string:
    /// `{"outcome":"list", "artifacts":[…]}`, `"bytes"` with `base64`,
    /// `"text"` with `text` and `truncated`, `"binary"`, `"tooBig"`,
    /// `"unreadable"`, `"lost"` (a 401), `"refused"` (the arguments made no
    /// allowed path) or `"cancelled"` (`benchAbortRead` aborted it).
    ///
    /// With a nonce, the read files an AbortController under it in
    /// `globalThis.benchArtifactReads` before its fetch and takes it out when
    /// it ends, whatever the end. The fetch's signal is that controller's and
    /// the deadline's together (`AbortSignal.any`, or a third controller
    /// where that is missing), so the 10 s and 20 s deadlines still hold; a
    /// read the deadline stopped is `unreadable`, one the abort stopped is
    /// `cancelled`. Without a nonce nothing is filed and every answer is as
    /// before.
    static let body = pathBuilder + "\n" + projection + "\n" + codecs + #"""

    const CAP = { list: \#(Cap.list), thumb: \#(Cap.thumb), text: \#(Cap.text), download: \#(Cap.download), sniff: \#(Cap.sniff) };
    const answer = value => JSON.stringify(value);
    const path = benchArtifactPath(op, frameId, versionId, width);
    if (path === null) { return answer({ outcome: "refused" }); }
    // `typeof`: the phone's reads may not pass a nonce at all.
    const readID = typeof nonce === "string" && /^[A-Za-z0-9-]{1,64}$/.test(nonce) ? nonce : null;
    const controller = readID !== null && typeof AbortController === "function" ? new AbortController() : null;
    const reads = controller === null ? null
        : (globalThis.\#(readsName) = globalThis.\#(readsName) || Object.create(null));
    if (controller !== null) { reads[readID] = controller; }
    const aborted = () => controller !== null && controller.signal.aborted === true;
    const failed = () => answer({ outcome: aborted() ? "cancelled" : "unreadable" });
    const signal = ms => {
        const deadline = typeof AbortSignal === "function" && typeof AbortSignal.timeout === "function"
            ? AbortSignal.timeout(ms) : undefined;
        if (controller === null) { return deadline; }
        if (deadline === undefined) { return controller.signal; }
        if (typeof AbortSignal.any === "function") { return AbortSignal.any([controller.signal, deadline]); }
        // No AbortSignal.any: a third controller, aborted by either.
        const either = new AbortController();
        const stop = () => { try { either.abort(); } catch (e) { } };
        for (const one of [controller.signal, deadline]) {
            if (one.aborted) { stop(); } else if (typeof one.addEventListener === "function") { one.addEventListener("abort", stop); }
        }
        return either.signal;
    };
    try {
    // no-store: nothing read here stays in WebKit's cache.
    const headers = { "Accept": op === "list" ? "application/json" : "*/*" };
    if (op === "text") { headers["Range"] = "bytes=0-" + (CAP.text - 1); }
    let response;
    try {
        response = await fetch(path, { credentials: "include", cache: "no-store", headers: headers,
                                       signal: signal(op === "download" ? 20000 : 10000) });
    } catch (e) { return failed(); }
    if (response.status === 401) { return answer({ outcome: "lost" }); }
    const header = name => {
        try { const value = response.headers && response.headers.get(name); return typeof value === "string" ? value : null; }
        catch (e) { return null; }
    };
    const drop = async () => { try { if (response.body && response.body.cancel) { await response.body.cancel(); } } catch (e) { } };
    // Not there any more: a version deleted or expired, or a session gone.
    if (response.status === 404 || response.status === 410) { await drop(); return answer({ outcome: "missing" }); }

    if (op === "list") {
        if (response.status !== 200) { return answer({ outcome: "unreadable" }); }
        let list = null;
        try { list = benchProjectArtifacts(JSON.parse(await response.text()), CAP.list); } catch (e) { list = null; }
        return list === null ? failed() : answer({ outcome: "list", artifacts: list });
    }

    // An empty file has no first byte to give.
    if (op === "text" && response.status === 416) { await drop(); return answer({ outcome: "text", text: "", truncated: false }); }
    if (response.status !== 200 && !(op === "text" && response.status === 206)) {
        await drop();
        return answer({ outcome: "unreadable" });
    }
    const cap = CAP[op];
    // Too big by its own say-so: not read at all.
    const declared = /^\d{1,16}$/.test(header("content-length") || "") ? Number(header("content-length")) : null;
    if (op !== "text" && declared !== null && declared > cap) { await drop(); return answer({ outcome: "tooBig" }); }

    // At most `cap` bytes are read, whatever the body holds: a daemon that
    // ignores the Range still sends only what is read.
    const readCapped = async () => {
        const body = response.body;
        if (!body || typeof body.getReader !== "function") { return null; }
        const reader = body.getReader();
        const parts = [];
        let total = 0, more = false;
        for (;;) {
            let step;
            try { step = await reader.read(); } catch (e) { return null; }
            if (step.done) { break; }
            const value = step.value;
            if (!ArrayBuffer.isView(value)) { try { await reader.cancel(); } catch (e) { } return null; }
            const chunk = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
            if (total + chunk.length > cap) {
                parts.push(chunk.subarray(0, cap - total));
                total = cap;
                more = true;
                try { await reader.cancel(); } catch (e) { }
                break;
            }
            parts.push(chunk);
            total += chunk.length;
        }
        const bytes = new Uint8Array(total);
        let at = 0;
        for (const part of parts) { bytes.set(part, at); at += part.length; }
        return { bytes: bytes, more: more };
    };
    const read = await readCapped();
    if (read === null) { return failed(); }
    // Aborted after the last bytes came: nothing more is done with them.
    if (aborted()) { return failed(); }

    if (op !== "text") {
        return answer(read.more ? { outcome: "tooBig" } : { outcome: "bytes", base64: await benchBase64Chunked(read.bytes) });
    }

    let truncated = read.more;
    if (response.status === 206) {
        const range = /^bytes\s+(\d+)-(\d+)\/(\d+|\*)$/i.exec((header("content-range") || "").trim());
        if (range !== null && Number(range[1]) !== 0) { return answer({ outcome: "unreadable" }); }
        if (range !== null && range[3] !== "*") { truncated = truncated || Number(range[3]) > read.bytes.length; }
        else { truncated = truncated || read.bytes.length >= cap; }
    }
    for (let i = 0; i < Math.min(CAP.sniff, read.bytes.length); i++) {
        if (read.bytes[i] === 0) { return answer({ outcome: "binary" }); }
    }
    return answer({ outcome: "text", text: benchDecodeUTF8(read.bytes, truncated), truncated: truncated });
    } finally {
        if (controller !== null && reads[readID] === controller) { delete reads[readID]; }
    }
    """#

    /// `benchAbortRead(nonce)`: aborts the one read filed under `nonce`, and
    /// answers whether there was one. An unknown nonce is let be; no other
    /// request of the page is touched. Run in the reads' own content world.
    static let abortFunction = #"""
    function benchAbortRead(nonce) {
        "use strict";
        const reads = globalThis.\#(readsName);
        const controller = reads && typeof nonce === "string" ? reads[nonce] : undefined;
        if (!controller || typeof controller.abort !== "function") { return false; }
        controller.abort();
        return true;
    }
    """#

    /// What `callAsyncJavaScript` runs to abort a read, with `nonce`.
    static let abort = abortFunction + "\nreturn benchAbortRead(nonce);"

    // MARK: Checking what the page sent

    /// The page's answer to `read`, checked again here. Anything unexpected,
    /// or an answer of another read's kind, is unreadable.
    static func outcome(of data: Data, for read: ArtifactRead) -> ArtifactReadOutcome {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let outcome = Pick.string(root["outcome"]) else { return .unreadable }
        switch (outcome, read) {
        case ("lost", _):
            return .lost
        case ("missing", _):
            return .missing
        case ("cancelled", _):
            return .cancelled
        case ("list", .list):
            return entries(root["artifacts"]).map(ArtifactReadOutcome.list) ?? .unreadable
        case ("bytes", .thumb), ("bytes", .download):
            guard let base64 = Pick.string(root["base64"]), let bytes = Data(base64Encoded: base64) else { return .unreadable }
            let cap = if case .thumb = read { Cap.thumb } else { Cap.download }
            return bytes.count <= cap ? .bytes(bytes) : .tooBig
        case ("tooBig", .thumb), ("tooBig", .download):
            return .tooBig
        case ("text", .text):
            guard let text = Pick.string(root["text"]), let truncated = Pick.bool(root["truncated"]),
                  text.unicodeScalars.count <= Cap.text else { return .unreadable }
            return text.utf8.prefix(Cap.sniff).contains(0) ? .binary : .text(text, truncated: truncated)
        case ("binary", .text):
            return .binary
        default:
            return .unreadable
        }
    }

    /// The projected list, every field checked: at most 300, each version id
    /// fit for a path and listed once, a name with no control characters.
    static func entries(_ value: Any?) -> [ArtifactEntry]? {
        guard let rows = value as? [Any], rows.count <= Cap.list else { return nil }
        var entries: [ArtifactEntry] = [], seen = Set<String>()
        for raw in rows {
            guard let row = raw as? [String: Any],
                  let version = Pick.string(row["v"]), PlanCheck.isVersionID(version),
                  let artifact = Pick.optionalText(row["a"], limit: Cap.artifactID),
                  let name = Pick.text(row["name"], limit: Cap.name), isClean(name),
                  let mime = Pick.optionalText(row["mime"], limit: Cap.mime),
                  let size = Pick.int(row["size"]), size >= 0,
                  let at = Pick.optionalTime(row["at"]) else { return nil }
            guard artifact.value.map(isClean) ?? true, mime.value.map(isMediaType) ?? true else { return nil }
            guard seen.insert(version).inserted else { continue }
            entries.append(ArtifactEntry(version: version, artifact: artifact.value, name: name, mime: mime.value,
                                         size: size, at: at))
        }
        return entries
    }

    /// No C0 or C1 control characters and no direction overrides.
    static func isClean(_ text: String) -> Bool {
        !text.unicodeScalars.contains {
            $0.value < 0x20 || (0x7F...0x9F).contains($0.value) || $0.value == 0x200E || $0.value == 0x200F
                || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
        }
    }

    /// `type/subtype`, lowercase tokens, as the page keeps them.
    static func isMediaType(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            (1...127).contains(part.utf8.count) && part.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x61...0x7A).contains($0) || "!#$&^_.+-".utf8.contains($0)
            } && part.utf8.first.map { (0x30...0x39).contains($0) || (0x61...0x7A).contains($0) } == true
        }
    }
}

// MARK: Reading through the page

extension WebContainer {
    /// One artifact read, made from inside the page (`ArtifactReaderScript`)
    /// and checked again. Throws when the page isn't up or the read makes no
    /// allowed path; a 401 also starts signing in again. `nonce` is the
    /// shelf's alone (ArtifactReadAbort): with it, `abortArtifactRead` can
    /// stop this read's fetch. The phone's routes pass none.
    func readArtifact(_ read: ArtifactRead, nonce: String? = nil) async throws -> ArtifactReadOutcome {
        guard status == .ready else { throw WebAPIError.notReady }
        guard read.path != nil else { throw WebAPIError.notAllowed }
        var arguments = read.arguments
        arguments["nonce"] = nonce ?? NSNull()
        let value = try await webView.callAsyncJavaScript(ArtifactReaderScript.body, arguments: arguments,
                                                          in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        let outcome = ArtifactReaderScript.outcome(of: Data(text.utf8), for: read)
        // Refused: the page's session didn't take. Sign in again.
        if outcome == .lost { sessionLost() }
        return outcome
    }

    /// Aborts the page's fetch for the read made with `nonce`, in the reads'
    /// own content world, and nothing else. Only the results shelf calls it.
    func abortArtifactRead(_ nonce: String) async {
        _ = try? await webView.callAsyncJavaScript(ArtifactReaderScript.abort, arguments: ["nonce": nonce],
                                                   in: nil, contentWorld: .defaultClient)
    }
}

/// A read the page drops when the task awaiting it is cancelled: the results
/// shelf's reads go through this, the phone's don't. Each gets a nonce of its
/// own; cancelling the task asks the page to abort that read's fetch
/// (`benchAbortRead`). Swift's cancellation alone never reaches a fetch, and
/// is never taken for proof that one stopped: the read still returns when
/// the page answers, and the queue keeps its slot until then, or until the
/// read's time limit passes (ShelfTransfers).
enum ArtifactReadAbort {
    /// A fresh nonce, as the script accepts it.
    static func makeNonce() -> String { UUID().uuidString.lowercased() }

    @MainActor
    static func abortable(_ read: ArtifactRead, nonce: String = makeNonce(),
                          perform: @MainActor (ArtifactRead, String) async -> ArtifactReadOutcome,
                          abort: @escaping @Sendable @MainActor (String) async -> Void) async -> ArtifactReadOutcome {
        guard !Task.isCancelled else { return .cancelled }
        return await withTaskCancellationHandler {
            await perform(read, nonce)
        } onCancel: {
            Task { @MainActor in await abort(nonce) }
        }
    }
}
