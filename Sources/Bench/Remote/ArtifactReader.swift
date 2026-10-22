// ArtifactReader.swift — reading a session's artifacts for the phone (DESIGN.md,
// Capsid on your phone → Phase 3: Artifacts), the in-page part. As the session
// reader does, the page makes the GET itself and hands Swift only what the
// route needs: the list projected to `{v, a, name, mime, size, at}`, a
// thumbnail's or a download's bytes as base64, or a text's first 256 KB
// decoded as UTF-8. Never `file_path`, `ref_host_path` or any other field.
//
// Exactly three GET shapes for the phone and the results shelf, and three more
// for Keep (since 1.0), built in the page from typed arguments and checked there
// against the allowlist before anything is fetched:
//   /api/frames/<36>/artifacts
//   /api/artifacts/versions/<v>?thumbnail=<120|800>
//   /api/artifacts/versions/<v>
//   /api/artifacts/<36>/versions                          (Keep: every version)
//   /api/artifacts/versions/<36>?include_metadata=true    (Keep: one version's facts)
//   /api/artifacts/versions/<36>/lineage?slim=1           (Keep: what it was drawn from)
// Keep's three are projected in the page too: `file_path`, `agent_name` and
// everything else the daemon adds never reach Swift, and the lineage read is
// refused whole when it carries the conversation, the environment snapshot or
// the executed cells (they are null under `slim=1`).
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
    /// `GET /api/artifacts/<artifact>/versions`: every version of one artifact,
    /// oldest first, projected (Keep). Ids here are 36-character UUIDs.
    case versions(artifact: String)
    /// `GET /api/artifacts/versions/<v>?include_metadata=true`: one version's
    /// name, size, checksum, reproduction code and environment (Keep). The
    /// answer must be for `<v>` itself: an artifact's id in that slot serves
    /// the artifact's latest version.
    case facts(version: String)
    /// `GET /api/artifacts/versions/<v>/lineage?slim=1`: the script and the
    /// inputs a version was drawn from (Keep). Reading it can start Claude
    /// Science's own code reconstruction, so Diagnostics never does.
    case lineage(version: String)

    static let widths: Set<Int> = [120, 800]

    /// The script's arguments: every name always there, null when unused.
    var arguments: [String: Any] {
        switch self {
        case .list(let frame): Self.arguments("list", frame: frame)
        case .thumb(let version, let width): Self.arguments("thumb", version: version, width: width)
        case .text(let version): Self.arguments("text", version: version)
        case .download(let version): Self.arguments("download", version: version)
        case .versions(let artifact): Self.arguments("versions", artifact: artifact)
        case .facts(let version): Self.arguments("facts", version: version)
        case .lineage(let version): Self.arguments("lineage", version: version)
        }
    }

    private static func arguments(_ op: String, frame: String? = nil, version: String? = nil, width: Int? = nil,
                                  artifact: String? = nil) -> [String: Any] {
        ["op": op, "frameId": frame ?? NSNull(), "versionId": version ?? NSNull(), "width": width ?? NSNull(),
         "artifactId": artifact ?? NSNull()]
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
        case .versions(let artifact):
            guard PlanCheck.isUUIDLike(artifact) else { return nil }
            path = "/api/artifacts/\(artifact)/versions"
        case .facts(let version):
            guard PlanCheck.isUUIDLike(version) else { return nil }
            path = "/api/artifacts/versions/\(version)?include_metadata=true"
        case .lineage(let version):
            guard PlanCheck.isUUIDLike(version) else { return nil }
            path = "/api/artifacts/versions/\(version)/lineage?slim=1"
        }
        return Self.isAllowedPath(path) ? path : nil
    }

    /// The allowlist, byte by byte: the three shapes of the phone and the
    /// shelf, Keep's three, and nothing else.
    static func isAllowedPath(_ path: String) -> Bool {
        let frames = "/api/frames/", artifacts = "/artifacts", versions = "/api/artifacts/versions/"
        if path.hasPrefix(frames), path.hasSuffix(artifacts),
           path.utf8.count == frames.utf8.count + 36 + artifacts.utf8.count {
            return PlanCheck.isFrameID(String(path.dropFirst(frames.count).dropLast(artifacts.count)))
        }
        // Keep's reads: exactly 36 characters of id between the fixed parts, so
        // `/api/artifacts/<id>/versions` can never be `/api/artifacts/versions/…`
        // (8 characters, not 36), and the lineage is checked before the
        // single-id branch below, which refuses a slash in an id.
        for (head, tail) in [("/api/artifacts/", "/versions"), (versions, "?include_metadata=true"),
                             (versions, "/lineage?slim=1")]
        where path.hasPrefix(head) && path.hasSuffix(tail) && path.utf8.count == head.utf8.count + 36 + tail.utf8.count {
            return PlanCheck.isUUIDLike(String(path.dropFirst(head.count).dropLast(tail.count)))
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

extension PlanCheck {
    /// An id as the daemon writes artifact, version and frame ids: exactly 36
    /// lowercase hex digits and dashes. Keep's reads take only these, which
    /// keeps `/api/artifacts/<id>/versions` from ever being read as
    /// `/api/artifacts/versions/…`. (`isVersionID`, which the older reads
    /// keep, takes any path-safe id.)
    static func isUUIDLike(_ id: String) -> Bool {
        isFrameID(id)
    }
}

// MARK: What Keep reads

/// One version of an artifact, from `/api/artifacts/<artifact>/versions`:
/// `file_path`, `agent_name` and `language` stay in the page.
struct ArtifactVersion: Equatable, Sendable {
    /// `version_id`.
    let v: String
    /// `version_number`.
    let n: Int
    /// The frame that saved it, when the daemon says (a copied artifact or a
    /// user's edit has none).
    let frame: String?
    let mime: String?
    let size: Int
    let at: Date?
    /// `parent_version_id`.
    let parent: String?
}

/// A version's environment snapshot: the name, the Python and the packages.
struct ArtifactEnvironment: Equatable, Sendable {
    let name: String?
    let python: String?
    let packages: [(name: String, version: String)]

    static func == (lhs: ArtifactEnvironment, rhs: ArtifactEnvironment) -> Bool {
        lhs.name == rhs.name && lhs.python == rhs.python && lhs.packages.count == rhs.packages.count
            && zip(lhs.packages, rhs.packages).allSatisfy { $0.name == $1.name && $0.version == $1.version }
    }
}

/// One version's own facts, from `…/versions/<v>?include_metadata=true`.
struct ArtifactFacts: Equatable, Sendable {
    /// The version the answer is for: Swift refuses an answer for another.
    let v: String
    /// The artifact's id.
    let a: String?
    let n: Int?
    /// The file name's last segment: the artifact's name now, not then.
    let name: String?
    let mime: String?
    let size: Int?
    let at: Date?
    /// The sha256 of the bytes, 64 hex digits, or nil (a file read from the
    /// Mac may have none).
    let sha: String?
    /// `is_user_upload`: a file the user added has no inputs and no script.
    let isUpload: Bool
    /// `reproduction_code`, at most 256 KB of UTF-8.
    let code: String?
    /// The code was longer and was cut.
    let codeCut: Bool
    let environment: ArtifactEnvironment?
}

/// One input of a version, from the lineage's `dependency_mappings.inputs[]`.
struct LineageInput: Equatable, Sendable {
    /// The input's version and artifact ids, when it was saved in Claude Science.
    let v: String?
    let a: String?
    let name: String?
    /// The last segment of its workspace path, never the path.
    let file: String?
    /// `consensus`: runtime, source_literal, both, haiku_only or ast_only.
    let how: String?
    /// Found by static analysis only: "may not have contributed".
    let inferred: Bool
    var fetchable: Bool { v != nil && a != nil }
}

/// The script behind a version and what it was drawn from, from
/// `…/versions/<v>/lineage?slim=1`.
struct ArtifactLineage: Equatable, Sendable {
    let v: String
    /// `code`, at most 256 KB of UTF-8: Claude Science's own reconstruction.
    let code: String?
    let codeCut: Bool
    /// `code_description`, at most 2,000 characters.
    let description: String?
    let language: String?
    /// Claude Science is still working it out.
    let pending: Bool
    let unavailableModel: String?
    let unavailableReason: String?
    let hasCells: Bool
    let hasEnvironment: Bool
    /// `dependency_mappings.mapping_status`: complete or pending.
    let mappingStatus: String?
    let inputs: [LineageInput]
}

/// What a read came to, checked again in Swift.
enum ArtifactReadOutcome: Equatable, Sendable {
    case list([ArtifactEntry])
    /// An artifact's versions, oldest first (Keep).
    case versions([ArtifactVersion])
    /// One version's facts, for the version asked (Keep).
    case facts(ArtifactFacts)
    /// One version's script and inputs, for the version asked (Keep).
    case lineage(ArtifactLineage)
    /// A thumbnail's or a download's bytes, within the cap.
    case bytes(Data)
    /// The text's first 256 KB, decoded; `truncated` when the file is longer.
    case text(String, truncated: Bool)
    /// A NUL in the first 8 KB: not text.
    case binary
    /// Over the cap (4 MB for a thumbnail, 8 MB for a download, 1 or 2 MB for
    /// Keep's JSON reads).
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
        /// Keep's reads: the versions of an artifact (kept newest-first past
        /// this many rows) and the bodies the page will read.
        static let versionRows = 500
        static let versionsBody = 1024 * 1024
        static let factsBody = 2 * 1024 * 1024
        static let lineageBody = 2 * 1024 * 1024
        /// Reproduction code, in UTF-8 bytes; cut there with a flag.
        static let code = 256 * 1024
        static let description = 2_000
        static let inputs = 200
        static let packages = 2_000
        static let word = 64
    }

    /// `benchArtifactPath(op, frameId, versionId, width, artifactId)`: the
    /// path, or null when the arguments make none. Pure.
    static let pathBuilder = #"""
    function benchArtifactPath(op, frameId, versionId, width, artifactId) {
        "use strict";
        const FRAME = /^[0-9a-f-]{36}$/, VERSION = /^[A-Za-z0-9_-]{1,128}$/;
        // The allowlist, exactly: whatever was built must be one of these.
        const ALLOWED = [/^\/api\/frames\/[0-9a-f-]{36}\/artifacts$/,
                         /^\/api\/artifacts\/versions\/[A-Za-z0-9_-]{1,128}\?thumbnail=(120|800)$/,
                         /^\/api\/artifacts\/versions\/[A-Za-z0-9_-]{1,128}$/,
                         /^\/api\/artifacts\/[0-9a-f-]{36}\/versions$/,
                         /^\/api\/artifacts\/versions\/[0-9a-f-]{36}\?include_metadata=true$/,
                         /^\/api\/artifacts\/versions\/[0-9a-f-]{36}\/lineage\?slim=1$/];
        const version = typeof versionId === "string" && VERSION.test(versionId) ? versionId : null;
        // Keep's reads take 36-character ids only.
        const uuid = typeof versionId === "string" && FRAME.test(versionId) ? versionId : null;
        const artifact = typeof artifactId === "string" && FRAME.test(artifactId) ? artifactId : null;
        let path = null;
        if (op === "list" && typeof frameId === "string" && FRAME.test(frameId)) {
            path = "/api/frames/" + frameId + "/artifacts";
        } else if (op === "thumb" && version !== null && (width === 120 || width === 800)) {
            path = "/api/artifacts/versions/" + version + "?thumbnail=" + width;
        } else if ((op === "text" || op === "download") && version !== null) {
            path = "/api/artifacts/versions/" + version;
        } else if (op === "versions" && artifact !== null) {
            path = "/api/artifacts/" + artifact + "/versions";
        } else if (op === "facts" && uuid !== null) {
            path = "/api/artifacts/versions/" + uuid + "?include_metadata=true";
        } else if (op === "lineage" && uuid !== null) {
            path = "/api/artifacts/versions/" + uuid + "/lineage?slim=1";
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

    /// Keep's three projections, pure: no fetch, no DOM. Each keeps only the
    /// fields Swift types and nothing else (`file_path`, `agent_name`, the
    /// workspace paths and everything the daemon adds are dropped here), and
    /// returns null when a shape doesn't match.
    ///   `benchProjectVersions(raw, cap)`: the bare array of versions, oldest
    ///   first, the newest `cap` of them.
    ///   `benchProjectFacts(raw, versionId)`: one version's facts; null unless
    ///   the answer is for `versionId` itself.
    ///   `benchProjectLineage(raw, versionId)`: a slim lineage; null unless it
    ///   is for `versionId` and its `messages`, `environment_snapshot` and
    ///   `interactions` are null (they are, under `slim=1`).
    static let keepProjection = #"""
    function benchKeepKit() {
        "use strict";
        const EARLIEST = 946684800000, LATEST = 4102444800000;
        const UUID = /^[0-9a-f-]{36}$/, ID = /^[A-Za-z0-9_-]{1,128}$/, SHA = /^[0-9a-f]{64}$/;
        const MEDIA = /^[a-z0-9][a-z0-9!#$&^_.+-]{0,126}\/[a-z0-9][a-z0-9!#$&^_.+-]{0,126}$/;
        const WORD = /^[A-Za-z0-9_.+#-]{1,64}$/;
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const isAbsent = v => v === undefined || v === null;
        const cut = (text, limit) => {
            const all = Array.from(text);
            return all.length <= limit ? text : all.slice(0, limit - 1).join("") + "…";
        };
        // Control characters and direction overrides never reach a screen or a file name.
        const clean = text => text.replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, "");
        const time = v => {
            let ms = null;
            if (typeof v === "number" && isFinite(v)) { ms = v < 1e11 ? v * 1000 : v; }
            else if (typeof v === "string") { const parsed = Date.parse(v); if (isFinite(parsed)) { ms = parsed; } }
            return ms !== null && ms >= EARLIEST && ms <= LATEST ? Math.round(ms) : null;
        };
        // A file's own name: the last part of whatever path it came with.
        const name = v => {
            if (typeof v !== "string") { return null; }
            const last = clean(v.split(/[\\/]/).pop()).trim();
            return last === "" ? null : cut(last, 255);
        };
        const mime = v => {
            if (typeof v !== "string") { return null; }
            const media = v.split(";")[0].trim().toLowerCase();
            return MEDIA.test(media) ? media : null;
        };
        const whole = (v, low, high) => typeof v === "number" && isFinite(v) && v >= low && v <= high && Math.floor(v) === v;
        const size = v => typeof v === "number" && isFinite(v) && v >= 0 && v <= 1e15 ? Math.floor(v) : null;
        const uuid = v => typeof v === "string" && UUID.test(v) ? v : null;
        const id = v => typeof v === "string" && ID.test(v) ? v : null;
        const word = v => typeof v === "string" && WORD.test(v) ? v : null;
        // A line of text from the daemon: no controls, cut at `limit` characters.
        const line = (v, limit) => {
            if (typeof v !== "string") { return null; }
            const one = clean(v).trim();
            return one === "" ? null : cut(one, limit);
        };
        // At most `limit` bytes of UTF-8, never half a character.
        const cutBytes = (text, limit) => {
            let bytes = 0, end = 0;
            for (const ch of text) {
                const c = ch.codePointAt(0);
                const n = c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
                if (bytes + n > limit) { return { text: text.slice(0, end), cut: true }; }
                bytes += n;
                end += ch.length;
            }
            return { text: text, cut: false };
        };
        const code = (v, limit) => {
            if (typeof v !== "string" || v === "") { return { text: null, cut: false }; }
            return cutBytes(v, limit);
        };
        return { isObject, isAbsent, cut, clean, time, name, mime, whole, size, uuid, id, word, line, code, MEDIA, SHA };
    }

    function benchProjectVersions(raw, cap) {
        "use strict";
        const K = benchKeepKit();
        if (!Array.isArray(raw)) { return null; }
        const kept = [];
        for (const row of raw) {
            if (!K.isObject(row)) { return null; }
            // The shape gate: a 36-character version id, a version number, a
            // type and a size; the rest is optional.
            if (K.uuid(row.version_id) === null || !K.whole(row.version_number, 0, 1e9)
                || typeof row.content_type !== "string" || K.size(row.size_bytes) === null) { return null; }
            kept.push({
                v: row.version_id,
                n: row.version_number,
                frame: K.uuid(row.frame_id),
                mime: K.mime(row.content_type),
                size: K.size(row.size_bytes),
                at: K.time(row.created_at),
                parent: K.uuid(row.parent_version_id),
            });
        }
        // Oldest first: the newest are kept.
        return kept.slice(Math.max(0, kept.length - cap));
    }

    function benchProjectFacts(raw, versionId) {
        "use strict";
        const K = benchKeepKit();
        const CODE = 262144, PACKAGES = 2000;
        if (!K.isObject(raw) || typeof versionId !== "string") { return null; }
        // An artifact's id in the version's place serves the artifact's latest
        // version: only an answer for the very version asked is taken.
        if (K.uuid(raw.version_id) === null || raw.version_id !== versionId) { return null; }
        if (typeof raw.is_user_upload !== "boolean") { return null; }
        const sha = typeof raw.checksum === "string" ? raw.checksum.toLowerCase() : null;
        const reproduction = K.code(raw.reproduction_code, CODE);
        let env = null;
        const snapshot = raw.environment;
        if (K.isObject(snapshot)) {
            const packages = [];
            if (Array.isArray(snapshot.packages)) {
                for (const one of snapshot.packages) {
                    if (packages.length >= PACKAGES) { break; }
                    if (!K.isObject(one)) { continue; }
                    const name = K.line(one.name, 255);
                    if (name === null) { continue; }
                    packages.push({ name: name, version: typeof one.version === "string" ? K.cut(K.clean(one.version).trim(), 100) : "" });
                }
            }
            env = { name: K.line(snapshot.environment_name, 200), python: K.line(snapshot.python_version, 50), packages: packages };
        }
        return {
            v: raw.version_id,
            a: K.uuid(raw.artifact_id),
            n: K.whole(raw.version_number, 0, 1e9) ? raw.version_number : null,
            name: K.name(raw.filename),
            mime: K.mime(raw.content_type),
            size: K.size(raw.size_bytes),
            at: K.time(raw.created_at),
            sha: sha !== null && K.SHA.test(sha) ? sha : null,
            upload: raw.is_user_upload,
            code: reproduction.text,
            codeCut: reproduction.cut,
            env: env,
        };
    }

    function benchProjectLineage(raw, versionId) {
        "use strict";
        const K = benchKeepKit();
        const CODE = 262144, DESCRIPTION = 2000, INPUTS = 200;
        if (!K.isObject(raw) || typeof versionId !== "string") { return null; }
        if (K.uuid(raw.version_id) === null || raw.version_id !== versionId) { return null; }
        // The conversation, the environment snapshot and the executed cells
        // are null under slim=1 (and absent from an older daemon's answer):
        // a body that carries any of them is not the read Capsid asked for.
        if (!K.isAbsent(raw.messages) || !K.isAbsent(raw.environment_snapshot) || !K.isAbsent(raw.interactions)) { return null; }
        const reproduction = K.code(raw.code, CODE);
        const description = K.line(raw.code_description, DESCRIPTION);
        let unavailable = null;
        if (K.isObject(raw.code_unavailable)) {
            unavailable = { model: K.line(raw.code_unavailable.model, 100), reason: K.word(raw.code_unavailable.reason) };
        }
        const mappings = K.isObject(raw.dependency_mappings) ? raw.dependency_mappings : null;
        const inputs = [];
        if (mappings !== null && Array.isArray(mappings.inputs)) {
            for (const one of mappings.inputs) {
                if (inputs.length >= INPUTS) { break; }
                if (!K.isObject(one)) { continue; }
                const v = K.id(one.version_id), a = K.id(one.artifact_id);
                const name = K.name(one.filename), file = K.name(one.workspace_path);
                if (v === null && name === null && file === null) { continue; }
                const how = K.word(one.consensus);
                inputs.push({ v: v, a: a, name: name, file: file, how: how, inferred: how === "ast_only", fetchable: v !== null && a !== null });
            }
        }
        return {
            v: raw.version_id,
            code: reproduction.text,
            codeCut: reproduction.cut,
            desc: description,
            lang: K.word(raw.language),
            pending: raw.pending === true,
            unavailable: unavailable,
            cells: raw.has_cell_sources === true,
            env: raw.has_environment === true,
            mapping: mappings !== null ? K.word(mappings.mapping_status) : null,
            inputs: inputs,
        };
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
    /// null or absent for the phone's). `artifactId` may be absent too: only
    /// Keep's versions read has one. Answers a JSON string:
    /// `{"outcome":"list", "artifacts":[…]}`, `"bytes"` with `base64`,
    /// `"text"` with `text` and `truncated`, Keep's `"versions"` with
    /// `versions`, `"facts"` with `facts` and `"lineage"` with `lineage`
    /// (each read through a capped stream and projected), `"binary"`,
    /// `"tooBig"`, `"unreadable"`, `"lost"` (a 401), `"refused"` (the
    /// arguments made no allowed path) or `"cancelled"` (`benchAbortRead`
    /// aborted it).
    ///
    /// With a nonce, the read files an AbortController under it in
    /// `globalThis.benchArtifactReads` before its fetch and takes it out when
    /// it ends, whatever the end. The fetch's signal is that controller's and
    /// the deadline's together (`AbortSignal.any`, or a third controller
    /// where that is missing), so the 10 s and 20 s deadlines still hold; a
    /// read the deadline stopped is `unreadable`, one the abort stopped is
    /// `cancelled`. Without a nonce nothing is filed and every answer is as
    /// before.
    static let body = pathBuilder + "\n" + projection + "\n" + keepProjection + "\n" + codecs + #"""

    const CAP = { list: \#(Cap.list), thumb: \#(Cap.thumb), text: \#(Cap.text), download: \#(Cap.download), sniff: \#(Cap.sniff),
                  versions: \#(Cap.versionsBody), facts: \#(Cap.factsBody), lineage: \#(Cap.lineageBody), versionRows: \#(Cap.versionRows) };
    const answer = value => JSON.stringify(value);
    // `typeof`: the phone's and the shelf's reads pass no artifact id.
    const path = benchArtifactPath(op, frameId, versionId, width, typeof artifactId === "string" ? artifactId : null);
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
    const keep = op === "versions" || op === "facts" || op === "lineage";
    const headers = { "Accept": op === "list" || keep ? "application/json" : "*/*" };
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

    // Keep's reads: the capped body, decoded and projected in the page.
    if (keep) {
        if (read.more) { return answer({ outcome: "tooBig" }); }
        let projected = null;
        try {
            // The page's own decoder for a body this size: the hand-written one
            // would hold its main thread.
            const body = typeof TextDecoder === "function" ? new TextDecoder("utf-8").decode(read.bytes) : benchDecodeUTF8(read.bytes, false);
            const parsed = JSON.parse(body);
            projected = op === "versions" ? benchProjectVersions(parsed, CAP.versionRows)
                : op === "facts" ? benchProjectFacts(parsed, versionId) : benchProjectLineage(parsed, versionId);
        } catch (e) { projected = null; }
        if (projected === null) { return failed(); }
        return answer(op === "versions" ? { outcome: "versions", versions: projected }
                      : op === "facts" ? { outcome: "facts", facts: projected } : { outcome: "lineage", lineage: projected });
    }

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
        case ("versions", .versions):
            return versions(root["versions"]).map(ArtifactReadOutcome.versions) ?? .unreadable
        case ("facts", .facts(let version)):
            return facts(root["facts"], asked: version).map(ArtifactReadOutcome.facts) ?? .unreadable
        case ("lineage", .lineage(let version)):
            return lineage(root["lineage"], asked: version).map(ArtifactReadOutcome.lineage) ?? .unreadable
        case ("bytes", .thumb), ("bytes", .download):
            guard let base64 = Pick.string(root["base64"]), let bytes = Data(base64Encoded: base64) else { return .unreadable }
            let cap = if case .thumb = read { Cap.thumb } else { Cap.download }
            return bytes.count <= cap ? .bytes(bytes) : .tooBig
        case ("tooBig", .thumb), ("tooBig", .download), ("tooBig", .versions), ("tooBig", .facts), ("tooBig", .lineage):
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

    // MARK: Keep's reads, checked again

    /// The projected versions: at most 500, each id 36 characters and listed
    /// once, the numbers whole, the checks the list's rows get.
    static func versions(_ value: Any?) -> [ArtifactVersion]? {
        guard let rows = value as? [Any], rows.count <= Cap.versionRows else { return nil }
        var versions: [ArtifactVersion] = [], seen = Set<String>()
        for raw in rows {
            guard let row = raw as? [String: Any],
                  let v = Pick.string(row["v"]), PlanCheck.isUUIDLike(v),
                  let n = Pick.int(row["n"]), (0...1_000_000_000).contains(n),
                  let frame = optionalID(row["frame"]),
                  let mime = Pick.optionalText(row["mime"], limit: Cap.mime), mime.value.map(isMediaType) ?? true,
                  let size = Pick.int(row["size"]), size >= 0,
                  let at = Pick.optionalTime(row["at"]),
                  let parent = optionalID(row["parent"]) else { return nil }
            guard seen.insert(v).inserted else { continue }
            versions.append(ArtifactVersion(v: v, n: n, frame: frame.value, mime: mime.value, size: size, at: at,
                                            parent: parent.value))
        }
        return versions
    }

    /// One version's facts, for the version asked: the answer's own `v` must
    /// be that version, a checksum is 64 hex digits or nil, the code is within
    /// 256 KB of UTF-8, the packages within 2,000.
    static func facts(_ value: Any?, asked: String) -> ArtifactFacts? {
        guard let row = value as? [String: Any],
              let v = Pick.string(row["v"]), PlanCheck.isUUIDLike(v), v == asked,
              let a = optionalID(row["a"]),
              let n = optionalInt(row["n"], limit: 1_000_000_000),
              let name = Pick.optionalText(row["name"], limit: Cap.name), name.value.map(isClean) ?? true,
              let mime = Pick.optionalText(row["mime"], limit: Cap.mime), mime.value.map(isMediaType) ?? true,
              let size = optionalInt(row["size"], limit: 1_000_000_000_000_000),
              let at = Pick.optionalTime(row["at"]),
              let sha = optionalDigest(row["sha"]),
              let upload = Pick.bool(row["upload"]),
              let code = optionalCode(row["code"]), let codeCut = Pick.bool(row["codeCut"]), !codeCut || code.value != nil,
              let environment = environment(row["env"]) else { return nil }
        return ArtifactFacts(v: v, a: a.value, n: n.value, name: name.value, mime: mime.value, size: size.value, at: at,
                             sha: sha.value, isUpload: upload, code: code.value, codeCut: codeCut,
                             environment: environment.value)
    }

    /// A slim lineage, for the version asked.
    static func lineage(_ value: Any?, asked: String) -> ArtifactLineage? {
        guard let row = value as? [String: Any],
              let v = Pick.string(row["v"]), PlanCheck.isUUIDLike(v), v == asked,
              let code = optionalCode(row["code"]), let codeCut = Pick.bool(row["codeCut"]), !codeCut || code.value != nil,
              let description = Pick.optionalText(row["desc"], limit: Cap.description), description.value.map(isClean) ?? true,
              let language = optionalWord(row["lang"]),
              let pending = Pick.bool(row["pending"]),
              let unavailable = unavailable(row["unavailable"]),
              let hasCells = Pick.bool(row["cells"]), let hasEnvironment = Pick.bool(row["env"]),
              let mapping = optionalWord(row["mapping"]),
              let raw = row["inputs"] as? [Any], raw.count <= Cap.inputs else { return nil }
        var inputs: [LineageInput] = []
        for one in raw {
            guard let input = lineageInput(one) else { return nil }
            inputs.append(input)
        }
        return ArtifactLineage(v: v, code: code.value, codeCut: codeCut, description: description.value,
                               language: language.value, pending: pending, unavailableModel: unavailable.model,
                               unavailableReason: unavailable.reason, hasCells: hasCells, hasEnvironment: hasEnvironment,
                               mappingStatus: mapping.value, inputs: inputs)
    }

    private static func lineageInput(_ value: Any) -> LineageInput? {
        guard let row = value as? [String: Any],
              let v = optionalVersionID(row["v"]), let a = optionalVersionID(row["a"]),
              let name = Pick.optionalText(row["name"], limit: Cap.name), name.value.map(isClean) ?? true,
              let file = Pick.optionalText(row["file"], limit: Cap.name), file.value.map(isClean) ?? true,
              let how = optionalWord(row["how"]),
              let inferred = Pick.bool(row["inferred"]), inferred == (how.value == "ast_only"),
              let fetchable = Pick.bool(row["fetchable"]), fetchable == (v.value != nil && a.value != nil),
              v.value != nil || name.value != nil || file.value != nil else { return nil }
        return LineageInput(v: v.value, a: a.value, name: name.value, file: file.value, how: how.value, inferred: inferred)
    }

    private static func environment(_ value: Any?) -> Pick.Maybe<ArtifactEnvironment>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let row = value as? [String: Any],
              let name = Pick.optionalText(row["name"], limit: 200), name.value.map(isClean) ?? true,
              let python = Pick.optionalText(row["python"], limit: 50), python.value.map(isClean) ?? true,
              let raw = row["packages"] as? [Any], raw.count <= Cap.packages else { return nil }
        var packages: [(name: String, version: String)] = []
        for one in raw {
            guard let package = one as? [String: Any],
                  let name = Pick.text(package["name"], limit: Cap.name), isClean(name),
                  let version = Pick.string(package["version"]), version.unicodeScalars.count <= 100,
                  isClean(version) else { return nil }
            packages.append((name, version))
        }
        return Pick.Maybe(value: ArtifactEnvironment(name: name.value, python: python.value, packages: packages))
    }

    /// `{model, reason}` or null: both null reads as "not unavailable".
    private static func unavailable(_ value: Any?) -> (model: String?, reason: String?)? {
        if Pick.isNull(value) { return (nil, nil) }
        guard let row = value as? [String: Any],
              let model = Pick.optionalText(row["model"], limit: 100), model.value.map(isClean) ?? true,
              let reason = optionalWord(row["reason"]) else { return nil }
        return (model.value, reason.value)
    }

    /// A 36-character id or null.
    private static func optionalID(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let id = Pick.string(value), PlanCheck.isUUIDLike(id) else { return nil }
        return Pick.Maybe(value: id)
    }

    /// A path-safe id or null: an input's, which is only ever downloaded.
    private static func optionalVersionID(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let id = Pick.string(value), PlanCheck.isVersionID(id) else { return nil }
        return Pick.Maybe(value: id)
    }

    /// A short word of letters, digits and `_.+#-`, or null.
    private static func optionalWord(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let word = Pick.string(value), (1...Cap.word).contains(word.utf8.count), word.utf8.allSatisfy({
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || "_.+#-".utf8.contains($0)
        }) else { return nil }
        return Pick.Maybe(value: word)
    }

    private static func optionalInt(_ value: Any?, limit: Int) -> Pick.Maybe<Int>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let number = Pick.int(value), (0...limit).contains(number) else { return nil }
        return Pick.Maybe(value: number)
    }

    /// A sha256 as hex: 64 lowercase hex digits, or null.
    private static func optionalDigest(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let digest = Pick.string(value), isDigest(digest) else { return nil }
        return Pick.Maybe(value: digest)
    }

    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// Reproduction code: any text, up to 256 KB of UTF-8, or null.
    private static func optionalCode(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let code = Pick.string(value), !code.isEmpty, code.utf8.count <= Cap.code else { return nil }
        return Pick.Maybe(value: code)
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
