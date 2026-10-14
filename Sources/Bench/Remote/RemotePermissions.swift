// RemotePermissions.swift — answering a session's permission requests from the
// phone (DESIGN.md, Bench on your phone → Phase 4: Permission requests).
//
// Three parts, as the rest of the phone's reading and writing is built:
//
//  1. The page's projection (`PermissionScript.projection`): from the root's
//     shallow frame and `trace-shallow` (the children's frames) it picks the
//     head of the queue and projects only the plain fields the phone shows.
//     Plain JavaScript with no fetch and no DOM, so the tests run these very
//     strings in JavaScriptCore on made-up frames. Never credentials, never
//     an `input`, never a request's free text.
//  2. Swift's checks and decisions (`PermissionRequest`, `RemotePermission`,
//     `PermissionDecide`): every field again, then the table of kinds: what
//     may be allowed once, what may only be denied, what is only Open on Mac,
//     and the words for each. All pure.
//  3. The writer's body builder (`PermissionScript.writeBuilder`), added to
//     the phone's one writer: `resolve-input` to the holding frame with
//     exactly `{requestId, tool_id, approved, action}`, and never a `scope`
//     (an omitted scope is "once").
//
// Nothing here logs; what a session asks for is read in memory only.
import Foundation

// MARK: The kinds

/// Every kind of request the daemon makes of a user, besides `ask` (which has
/// its own route): the research's table of what the phone may do with each.
enum PermissionKind: String, CaseIterable, Sendable {
    case network, host
    case hostDelete = "host_delete"
    case artifactDelete = "artifact_delete"
    case mcpTool = "mcp_tool"
    case localExec = "local_exec"
    case remoteExec = "remote_exec"
    case remoteRead = "remote_read"
    case byocSubmit = "byoc_submit"
    case byocKernel = "byoc_kernel"
    case inferSubmit = "infer_submit"
    case customizeMutation = "customize_mutation"
    case managedEndpointRegister = "managed_endpoint_register"
    case credentialAccess = "credential_access"
    case skillLicense = "skill_license"
    case contactEmail = "contact_email"
    case credentialRequest = "credential_request"
    case sshPassword = "ssh_password"
    case usageCheckpoint = "usage_checkpoint"
    case setGoal = "set_goal"
    case grantScan = "grant_scan"
    case providerDiscovery = "provider_discovery"

    /// Whether a plain "no" is all a deny is. The rest are Open on Mac: a
    /// license or a usage checkpoint records its answer another way, an email
    /// or a password is typed, a goal or a scan changes what Claude may do.
    var canBeDenied: Bool {
        switch self {
        case .network, .host, .hostDelete, .artifactDelete, .mcpTool, .localExec, .remoteExec, .remoteRead,
             .byocSubmit, .byocKernel, .inferSubmit, .customizeMutation, .managedEndpointRegister, .credentialAccess:
            true
        case .skillLicense, .contactEmail, .credentialRequest, .sshPassword, .usageCheckpoint, .setGoal,
             .grantScan, .providerDiscovery:
            false
        }
    }

    /// The code languages `local_exec` may be allowed for.
    static let languages: Set<String> = ["python", "r", "bash", "powershell"]
    /// The sources an `mcp_tool` may be allowed from, when it says it only reads.
    static let readOnlySources: Set<String> = ["directory", "bundled", "antmcp"]
}

// MARK: The page's projection

enum PermissionScript {
    /// The small pure helpers the projections share. Top-level functions with
    /// the `bench` prefix: no state, no fetch, no DOM.
    static let helpers = #"""
    function benchIsObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }
    function benchIsAbsent(v) { return v === undefined || v === null; }
    // An object, or a string holding one; null when absent; undefined for anything else.
    function benchObjectOrNull(v) {
        if (benchIsAbsent(v)) { return null; }
        if (benchIsObject(v)) { return v; }
        if (typeof v === "string") {
            try { const parsed = JSON.parse(v); if (benchIsObject(parsed)) { return parsed; } } catch (e) { }
        }
        return undefined;
    }
    // Lengths in code points, as Swift's unicodeScalars count them.
    function benchPoints(text) { return Array.from(text).length; }
    function benchCut(text, limit) {
        const all = Array.from(text);
        return all.length <= limit ? text : all.slice(0, limit - 1).join("") + "…";
    }
    // One line, with control characters and direction overrides gone: white
    // space runs become one space. Null when empty or not a string.
    function benchLine(v, limit) {
        if (typeof v !== "string") { return null; }
        const spaced = v.split(/\s+/).join(" ");
        const clean = spaced.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "");
        const one = clean.split(/\s+/).filter(Boolean).join(" ");
        return one ? benchCut(one, limit) : null;
    }
    // Milliseconds since 1970 between 2000 and 2100, from milliseconds, seconds or a date string.
    function benchTime(v) {
        let ms = null;
        if (typeof v === "number" && isFinite(v)) { ms = v < 1e11 ? v * 1000 : v; }
        else if (typeof v === "string") { const parsed = Date.parse(v); if (isFinite(parsed)) { ms = parsed; } }
        return ms !== null && ms >= 946684800000 && ms <= 4102444800000 ? Math.round(ms) : null;
    }
    """#

    /// `benchReadPath(op, frameId)`: the one place the permission and live
    /// reads' paths are made, each checked against its strict rule before it
    /// is returned. Null when the arguments make none. Pure.
    static let paths = #"""
    function benchReadPath(op, frameId) {
        "use strict";
        // The allowlist, exactly: whatever was built must be one of these.
        const ALLOWED = [/^\/api\/frames\/[0-9a-f-]{36}\/trace-shallow\?include_messages=false$/,
                         /^\/api\/frames\/[0-9a-f-]{36}\/streaming$/];
        let path = null;
        if (typeof frameId === "string" && /^[0-9a-f-]{36}$/.test(frameId)) {
            if (op === "trace") { path = "/api/frames/" + frameId + "/trace-shallow?include_messages=false"; }
            else if (op === "streaming") { path = "/api/frames/" + frameId + "/streaming"; }
        }
        return path !== null && ALLOWED.some(rule => rule.test(path)) ? path : null;
    }
    """#

    /// `benchPendingQueue(shallow, trace, rootId)`: every pending request of
    /// the root and of the frames under it, earliest first, each as
    /// `{request, frame:{id, chain}, at, key}`; or null when a shape doesn't
    /// match. `trace` is the root's `trace-shallow` tree (frames nested under
    /// `children`). Pure.
    static let queue = #"""
    function benchPendingQueue(shallow, trace, rootId) {
        "use strict";
        const FRAME = /^[0-9a-f-]{36}$/;
        // The daemon's frame statuses, and the two in which a frame holds a
        // request (a parked one waits on the user, a live one is processing).
        const STATUSES = ["processing", "awaiting_user_response", "awaiting_plan_approval", "completed",
                          "success", "cancelled", "replaced", "failed"];
        const HOLDING = ["processing", "awaiting_user_response"];
        const MAX_FRAMES = 2000, MAX_DEPTH = 16, MAX_REQUESTS = 200;

        if (!benchIsObject(shallow) || !benchIsObject(trace) || typeof rootId !== "string" || !FRAME.test(rootId)) { return null; }
        if (trace.id !== rootId || typeof shallow.status !== "string" || STATUSES.indexOf(shallow.status) < 0) { return null; }
        const rootOutput = benchObjectOrNull(shallow.output_data);
        if (rootOutput === undefined) { return null; }

        // Every frame under the root, each with the ids from itself up to the root.
        const frames = [{ id: rootId, chain: [rootId], status: shallow.status, output: rootOutput }];
        let failed = false, visited = 0;
        const walk = (children, parent, chain) => {
            if (benchIsAbsent(children)) { return; }
            if (!Array.isArray(children)) { failed = true; return; }
            if (children.length === 0) { return; }
            if (chain.length > MAX_DEPTH) { failed = true; return; }
            for (const child of children) {
                if (failed) { return; }
                visited += 1;
                if (visited > MAX_FRAMES || !benchIsObject(child) || typeof child.id !== "string" || !FRAME.test(child.id)
                    || child.parent_frame_id !== parent || typeof child.status !== "string"
                    || STATUSES.indexOf(child.status) < 0) { failed = true; return; }
                const own = [child.id].concat(chain);
                // Only the frames that hold requests are read closely.
                if (HOLDING.indexOf(child.status) >= 0) {
                    const output = benchObjectOrNull(child.output_data);
                    if (output === undefined) { failed = true; return; }
                    frames.push({ id: child.id, chain: own, status: child.status, output: output });
                }
                walk(child.children, child.id, own);
            }
        };
        walk(trace.children, rootId, [rootId]);
        if (failed) { return null; }

        const queue = [];
        for (const frame of frames) {
            if (HOLDING.indexOf(frame.status) < 0 || frame.output === null) { continue; }
            const pending = frame.output.pending_input_requests;
            if (benchIsAbsent(pending)) { continue; }
            if (!Array.isArray(pending)) { return null; }
            for (const request of pending) {
                if (!benchIsObject(request)) { continue; }
                const rid = typeof request.requestId === "string" ? request.requestId
                    : typeof request.tool_id === "string" ? request.tool_id : "";
                // A request with no readable time can't be ordered: it goes first,
                // so nothing behind it is offered.
                queue.push({ request: request, frame: frame, at: benchTime(request.createdAt), key: rid });
                if (queue.length > MAX_REQUESTS) { return null; }
            }
        }
        // Earliest first by `createdAt`, then by id, then by frame, as Claude Science's own UI orders them.
        queue.sort((a, b) => {
            const x = a.at === null ? -Infinity : a.at, y = b.at === null ? -Infinity : b.at;
            if (x !== y) { return x < y ? -1 : 1; }
            if (a.key !== b.key) { return a.key < b.key ? -1 : 1; }
            return a.frame.id < b.frame.id ? -1 : a.frame.id > b.frame.id ? 1 : 0;
        });
        return queue;
    }
    """#

    /// `benchProjectPermission(shallow, trace, rootId)`: the head of the
    /// queue of pending requests across the root and its children, projected,
    /// or null (nothing waiting, the head is the root's own question, or a
    /// shape doesn't match). A helper's question is projected as kind `ask`,
    /// to be shown and never answered. Pure: no fetch, no DOM, no globals.
    static let projection = #"""
    function benchProjectPermission(shallow, trace, rootId) {
        "use strict";
        const KINDS = ["network", "host", "host_delete", "artifact_delete", "mcp_tool", "local_exec", "remote_exec",
                       "remote_read", "byoc_submit", "byoc_kernel", "infer_submit", "customize_mutation",
                       "managed_endpoint_register", "credential_access", "skill_license", "contact_email",
                       "credential_request", "ssh_password", "usage_checkpoint", "set_goal", "grant_scan",
                       "provider_discovery"];
        const CODE_LIMIT = 4000;
        // What the phone can show whole: a line of at most 160 characters, and 60 lines.
        const LINE_LIMIT = 160, LINES_LIMIT = 60;
        // A control character (a lone CR included), a zero-width or joining
        // character, a soft hyphen, a line or paragraph separator, a variation
        // selector or a direction override: the code on the screen could differ
        // from the code that runs. A tab and a line feed are fine.
        const ODD = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u00ad\u180e\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060\u2066-\u2069\u3164\ufe00-\ufe0f\ufeff]|[\u{e0100}-\u{e01ef}]/u;
        // An id sent back as it is: printable ASCII, no spaces, at most 200.
        const ident = v => typeof v === "string" && /^[\x21-\x7e]{1,200}$/.test(v) ? v : null;
        // A short lower-case word: a kind, a language, a source.
        const word = v => typeof v === "string" && /^[a-z][a-z0-9_-]{0,39}$/.test(v) ? v : null;
        const line = benchLine;

        const queue = benchPendingQueue(shallow, trace, rootId);
        if (queue === null || queue.length === 0) { return null; }
        const head = queue[0], request = head.request;
        // The root's own question is the root question's business; a helper's is shown, not answered.
        if (request.kind === "ask" && head.frame.chain.length < 2) { return null; }

        const kind = word(request.kind) || "unknown";
        const requestId = ident(request.requestId), toolId = ident(request.tool_id);
        const mode = request.mode === "live" || request.mode === "parked" ? request.mode : null;
        const out = { target: null, access: null, count: null, tool: null, server: null, source: null,
                      provider: null, name: null };
        let readOnly = false, sharedEnv = false, code = null, codeProblem = null;
        // The shape the daemon validates for each kind (the research's gate).
        let shape = KINDS.indexOf(kind) >= 0 && mode !== null && head.at !== null
            && (requestId !== null || toolId !== null);
        switch (kind) {
        case "network":
            out.target = line(request.target, 200);
            if (out.target === null) { shape = false; }
            break;
        case "host":
            out.target = line(request.target, 400);
            out.access = request.requested_mode === "rw" ? "rw" : request.requested_mode === "ro" ? "ro" : null;
            if (out.target === null) { shape = false; }
            break;
        case "host_delete":
            if (!Array.isArray(request.paths) || request.paths.length === 0
                || !Array.isArray(request.covering_roots) || request.covering_roots.length === 0) { shape = false; break; }
            out.target = line(request.paths[0], 400);
            out.count = Math.min(request.paths.length, 100000);
            if (out.target === null) { shape = false; }
            break;
        case "artifact_delete":
            if (!Array.isArray(request.items) || request.items.length === 0) { shape = false; break; }
            out.count = Math.min(request.items.length, 100000);
            break;
        case "mcp_tool":
            if (typeof request.server_id !== "string" || request.server_id.trim() === "") { shape = false; }
            out.server = line(request.server_name, 200);
            out.tool = line(request.tool_name, 200);
            out.source = word(request.server_source);
            if (out.server === null || out.tool === null || out.source === null) { shape = false; }
            readOnly = request.read_only === true;
            break;
        case "local_exec":
            out.tool = word(request.tool);
            if (out.tool === null || typeof request.code !== "string") { shape = false; break; }
            // Absent or false: not shared. Anything else is taken to be shared.
            sharedEnv = !(benchIsAbsent(request.shared_env) || request.shared_env === false);
            if (request.code.trim() === "") { break; }
            if (benchPoints(request.code) > CODE_LIMIT) { codeProblem = "long"; }
            else if (ODD.test(request.code)) { codeProblem = "odd"; }
            else {
                const rows = request.code.split("\n");
                if (rows[rows.length - 1] === "") { rows.pop(); }
                if (rows.length > LINES_LIMIT || rows.some(row => benchPoints(row) > LINE_LIMIT)) { codeProblem = "lines"; }
                else { code = request.code; }
            }
            break;
        case "remote_exec":
        case "byoc_submit":
        case "byoc_kernel":
        case "infer_submit":
            out.provider = line(request.provider, 100);
            break;
        case "remote_read":
            out.provider = line(request.provider, 100);
            out.target = line(request.remote_path, 400);
            break;
        case "customize_mutation":
            out.name = line(request.label, 200);
            break;
        case "managed_endpoint_register":
        case "credential_access":
            out.name = line(request.name, 200);
            break;
        case "skill_license":
            out.name = line(request.skill_name, 200);
            break;
        case "credential_request":
            out.name = line(request.label, 100);
            break;
        case "ssh_password":
            out.target = line(request.host, 200);
            break;
        default:
            break;
        }
        // Another request anywhere in the queue with this `tool_id`: an answer
        // naming it may resolve that one too, which the person didn't see.
        const toolIdShared = typeof request.tool_id === "string"
            && queue.some(other => other !== head && other.request.tool_id === request.tool_id);
        return {
            requestId: requestId, toolId: toolId, mode: mode, kind: kind, frame: head.frame.id, chain: head.frame.chain,
            toolIdShared: toolIdShared, shape: shape, target: out.target, access: out.access, count: out.count,
            tool: out.tool, server: out.server, source: out.source, provider: out.provider, name: out.name,
            readOnly: readOnly, sharedEnv: sharedEnv, code: code, codeProblem: codeProblem,
        };
    }
    """#

    /// Whether a frame's status means a request may be waiting under it: the
    /// page reads `trace-shallow` only then.
    static let needsTrace = #"""
    function benchNeedsTrace(shallow) {
        "use strict";
        return shallow !== null && typeof shallow === "object" && !Array.isArray(shallow)
            && (shallow.status === "processing" || shallow.status === "awaiting_user_response");
    }
    """#

    /// `benchBuildPermissionWrite(a)` → `{path, body}`, or null. The body is
    /// exactly `{responses:[{requestId, tool_id, approved, action}]}`: never a
    /// `scope`, never a `mode`, `text` or `redirect`. Pure.
    static let writeBuilder = #"""
    function benchBuildPermissionWrite(a) {
        "use strict";
        const ID = /^[\x21-\x7e]{1,200}$/;
        if (a === null || typeof a !== "object" || Array.isArray(a) || a.kind !== "permission") { return null; }
        if (typeof a.frameId !== "string" || !/^[0-9a-f-]{36}$/.test(a.frameId)) { return null; }
        if (typeof a.requestId !== "string" || !ID.test(a.requestId)) { return null; }
        if (typeof a.toolId !== "string" || !ID.test(a.toolId)) { return null; }
        if (a.decision !== "allow" && a.decision !== "deny") { return null; }
        const allow = a.decision === "allow";
        return { path: "/api/frames/" + a.frameId + "/resolve-input",
                 body: { responses: [{ requestId: a.requestId, tool_id: a.toolId, approved: allow,
                                       action: allow ? "allow" : "deny" }] } };
    }
    """#

    /// All of it together, for a script that reads: the helpers, the path
    /// builder, the queue, the projection and the trace test.
    static let reading = helpers + "\n" + paths + "\n" + queue + "\n" + projection + "\n" + needsTrace
}

/// The two read paths, in Swift: the same rules as the script's
/// `benchReadPath`, byte by byte.
enum PermissionPaths {
    /// `GET /api/frames/<root>/trace-shallow?include_messages=false`.
    static func trace(_ frame: String) -> String? {
        PlanCheck.isFrameID(frame) ? "/api/frames/\(frame)/trace-shallow?include_messages=false" : nil
    }

    /// `GET /api/frames/<root>/streaming`.
    static func streaming(_ frame: String) -> String? {
        PlanCheck.isFrameID(frame) ? "/api/frames/\(frame)/streaming" : nil
    }

    /// `^/api/frames/[0-9a-f-]{36}/(trace-shallow\?include_messages=false|streaming)$`.
    static func isAllowed(_ path: String) -> Bool {
        let head = "/api/frames/"
        guard path.hasPrefix(head) else { return false }
        let rest = path.dropFirst(head.count)
        for tail in ["/trace-shallow?include_messages=false", "/streaming"] where rest.hasSuffix(tail) {
            return rest.utf8.count == 36 + tail.utf8.count && PlanCheck.isFrameID(String(rest.dropLast(tail.count)))
        }
        return false
    }
}

// MARK: What Swift receives

/// The head of a session's queue as the page projected it, every field
/// checked again. Nil from `init(object:)` at the first thing that doesn't
/// match; the session is then read without a permission.
struct PermissionRequest: Equatable, Sendable {
    enum CodeProblem: String, Sendable {
        /// Over 4,000 characters: not shown whole, so not allowed.
        case long
        /// A control character (a lone CR too), a zero-width or joining
        /// character, a soft hyphen, a line separator, a variation selector or
        /// a direction override in it.
        case odd
        /// A line over 160 characters or more than 60 lines: more than the
        /// phone can show to be read.
        case lines
    }

    enum CodeLimit {
        static let line = 160
        static let lines = 60
    }

    /// What the page's own check holds to, again: whether `code` is fit to be
    /// shown whole, and if not, why. Only a tab and a line feed are white space
    /// that moves nothing; every other character that is invisible, joins or
    /// breaks a line differently is "odd".
    static func problem(withCode code: String) -> CodeProblem? {
        if code.unicodeScalars.count > Limit.code { return .long }
        if code.unicodeScalars.contains(where: isOdd) { return .odd }
        var rows = code.split(separator: "\n", omittingEmptySubsequences: false)
        if rows.last?.isEmpty == true { rows.removeLast() }
        return rows.count > CodeLimit.lines || rows.contains { $0.unicodeScalars.count > CodeLimit.line } ? .lines : nil
    }

    private static func isOdd(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0B...0x1F, 0x7F...0x9F, 0xAD, 0x180E, 0x200B...0x200F, 0x2028, 0x2029, 0x202A...0x202E,
             0x2060, 0x2066...0x2069, 0x3164, 0xFE00...0xFE0F, 0xFEFF, 0xE0100...0xE01EF:
            true
        default:
            false
        }
    }

    enum Limit {
        static let id = 200
        static let name = 200
        static let path = 400
        static let provider = 100
        static let code = 4_000
        static let chain = 17
        static let count = 100_000
    }

    /// The request's own id, and its `tool_id`: both are sent back.
    let requestID: String?
    let toolID: String?
    /// "live" or "parked"; nil when the daemon said neither.
    let mode: String?
    /// The daemon's word for the kind, lower case; known or not.
    let kind: String
    /// The frame that holds it: the root, or a helper (sub-agent) under it.
    let frame: String
    /// The ids from `frame` up to the session's root: `[root]` for the root's own.
    let chain: [String]
    /// Another pending request in the queue has the same `tool_id`: an answer
    /// naming it may resolve that one too.
    let toolIdShared: Bool
    /// The daemon's own shape for this kind held (the research's gate).
    let shape: Bool
    let target: String?
    /// "ro" or "rw" for a host request.
    let access: String?
    let count: Int?
    /// A language (`local_exec`) or an MCP tool's name.
    let tool: String?
    let server: String?
    let source: String?
    let provider: String?
    let name: String?
    let readOnly: Bool
    let sharedEnv: Bool
    let code: String?
    let codeProblem: CodeProblem?

    init(requestID: String?, toolID: String?, mode: String? = "live", kind: String, frame: String, chain: [String]? = nil,
         toolIdShared: Bool = false, shape: Bool = true, target: String? = nil, access: String? = nil, count: Int? = nil,
         tool: String? = nil, server: String? = nil, source: String? = nil, provider: String? = nil, name: String? = nil,
         readOnly: Bool = false, sharedEnv: Bool = false, code: String? = nil, codeProblem: CodeProblem? = nil) {
        self.requestID = requestID
        self.toolID = toolID
        self.mode = mode
        self.kind = kind
        self.frame = frame
        self.chain = chain ?? [frame]
        self.toolIdShared = toolIdShared
        self.shape = shape
        self.target = target
        self.access = access
        self.count = count
        self.tool = tool
        self.server = server
        self.source = source
        self.provider = provider
        self.name = name
        self.readOnly = readOnly
        self.sharedEnv = sharedEnv
        self.code = code
        self.codeProblem = codeProblem
    }

    /// A sub-agent holds it.
    var helper: Bool { chain.count > 1 }

    /// A helper's question, which the page projects when it is the head of the
    /// queue: shown, never answered from the phone.
    var isHelperAsk: Bool { kind == "ask" && helper }

    /// The id the phone shows and sends back.
    var id: String { requestID ?? toolID ?? "unidentified" }

    /// The kind, when Bench knows it.
    var known: PermissionKind? { PermissionKind(rawValue: kind) }

    // MARK: Checking what the page sent

    init?(object: Any?) {
        guard let root = object as? [String: Any],
              let requestID = Self.identifier(root["requestId"]), let toolID = Self.identifier(root["toolId"]),
              let mode = Pick.optionalText(root["mode"], limit: 10), mode.value == nil || ["live", "parked"].contains(mode.value),
              let kind = Pick.string(root["kind"]), Self.isWord(kind),
              let frame = Pick.string(root["frame"]), PlanCheck.isFrameID(frame),
              let rawChain = root["chain"] as? [Any], (1...Limit.chain).contains(rawChain.count),
              let toolIdShared = Pick.bool(root["toolIdShared"]), let shape = Pick.bool(root["shape"]),
              let target = Pick.optionalText(root["target"], limit: Limit.path),
              let access = Pick.optionalText(root["access"], limit: 2), access.value == nil || ["ro", "rw"].contains(access.value),
              let count = Self.optionalCount(root["count"]),
              let tool = Pick.optionalText(root["tool"], limit: Limit.name),
              let server = Pick.optionalText(root["server"], limit: Limit.name),
              let source = Pick.optionalText(root["source"], limit: 40),
              let provider = Pick.optionalText(root["provider"], limit: Limit.provider),
              let name = Pick.optionalText(root["name"], limit: Limit.name),
              let readOnly = Pick.bool(root["readOnly"]), let sharedEnv = Pick.bool(root["sharedEnv"]),
              let code = Pick.optionalText(root["code"], limit: Limit.code),
              let problem = Self.optionalProblem(root["codeProblem"]) else { return nil }
        var chain: [String] = []
        for raw in rawChain {
            guard let id = Pick.string(raw), PlanCheck.isFrameID(id), !chain.contains(id) else { return nil }
            chain.append(id)
        }
        guard chain.first == frame else { return nil }
        // The page withholds a code that isn't fit to be shown whole; Swift holds
        // it to the same rule, whatever the page said.
        var shownCode = code.value, shownProblem = problem.value
        if let text = shownCode, let found = Self.problem(withCode: text) {
            shownCode = nil
            shownProblem = shownProblem ?? found
        }
        self.init(requestID: requestID.value, toolID: toolID.value, mode: mode.value, kind: kind, frame: frame, chain: chain,
                  toolIdShared: toolIdShared, shape: shape, target: target.value, access: access.value, count: count.value,
                  tool: tool.value, server: server.value, source: source.value, provider: provider.value, name: name.value,
                  readOnly: readOnly, sharedEnv: sharedEnv, code: shownCode, codeProblem: shownProblem)
    }

    /// An id sent back whole: printable ASCII without spaces, 1…200, or null.
    static func identifier(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let id = Pick.string(value), isIdentifier(id) else { return nil }
        return Pick.Maybe(value: id)
    }

    static func isIdentifier(_ text: String) -> Bool {
        (1...Limit.id).contains(text.utf8.count) && text.utf8.allSatisfy { (0x21...0x7E).contains($0) }
    }

    /// `^[a-z][a-z0-9_-]{0,39}$`.
    static func isWord(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard (1...40).contains(bytes.count), (0x61...0x7A).contains(bytes[0]) else { return false }
        return bytes.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x5F || $0 == 0x2D }
    }

    private static func optionalCount(_ value: Any?) -> Pick.Maybe<Int>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let number = Pick.int(value), (0...Limit.count).contains(number) else { return nil }
        return Pick.Maybe(value: number)
    }

    private static func optionalProblem(_ value: Any?) -> Pick.Maybe<CodeProblem>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let word = Pick.string(value), let problem = CodeProblem(rawValue: word) else { return nil }
        return Pick.Maybe(value: problem)
    }
}

// MARK: What the phone is told

extension RemoteAPI {
    /// `permission` in `/api/sessions/<id>` (version 2, since Phase 4).
    struct Permission: Encodable, Equatable {
        /// The request's id: the phone sends it back.
        let id: String
        let kind: String
        let title: String
        let detail: String
        /// The code for a `local_exec` request, whole; null for any other.
        let code: String?
        /// A helper (sub-agent) is the one asking.
        let helper: Bool
        let canAllow: Bool
        let canDeny: Bool
        /// Why it can't be allowed, when it can't.
        let why: String?

        private enum CodingKeys: String, CodingKey { case id, kind, title, detail, code, helper, canAllow, canDeny, why }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
            try c.encode(title, forKey: .title)
            try c.encode(detail, forKey: .detail)
            try c.encode(code, forKey: .code)
            try c.encode(helper, forKey: .helper)
            try c.encode(canAllow, forKey: .canAllow)
            try c.encode(canDeny, forKey: .canDeny)
            try c.encode(why, forKey: .why)
        }
    }
}

// MARK: The table of kinds

/// What the phone may do with a request, and how it says so. Pure.
enum RemotePermission {
    enum Why {
        static let lasting = "Allowing this from your phone would give lasting access. Open it on your Mac."
        static let onMac = "This one has to be answered on your Mac."
        static let unknown = "Bench doesn't know this kind of request. Open it on your Mac."
        static let unreadable = "Bench can't read this request well enough. Open it on your Mac."
        static let language = "Bench only offers Python, R, Bash and PowerShell code from your phone. Open it on your Mac."
        static let shared = "This code would run in a shared environment. Open it on your Mac."
        static let codeLong = "The code is too long to read on your phone. Open it on your Mac."
        static let codeOdd = "The code has characters Bench can't show safely. Open it on your Mac."
        static let codeLines = "Too long to read on your phone. Open it on your Mac."
        static let toolIdShared = "This needs more than one approval. Open it on your Mac."
        /// A helper's question: shown so the phone says what waits, never answered from it.
        static let helperAsked = "A helper agent asked a question. Answer it on your Mac."
        static let noCode = "Bench can't see the code to run. Open it on your Mac."
        static let notReadOnly = "This tool isn't marked as read-only. Open it on your Mac."
        static let source = "Allowing this from your phone would give lasting access. Open it on your Mac."
    }

    /// The `permission` object for a request: title, detail, code and what
    /// may be done. `actionsOn` false (Settings → Phone) offers nothing.
    static func describe(_ request: PermissionRequest, actionsOn: Bool) -> RemoteAPI.Permission {
        let words = words(for: request)
        let decision = decide(request, actionsOn: actionsOn)
        return RemoteAPI.Permission(id: request.id, kind: request.kind, title: words.title, detail: words.detail,
                                    code: request.known == .localExec && request.shape ? request.code : nil,
                                    helper: request.helper, canAllow: decision.canAllow, canDeny: decision.canDeny,
                                    why: decision.canAllow ? nil : decision.why)
    }

    struct Decision: Equatable {
        let canAllow: Bool
        let canDeny: Bool
        /// Why not an allow, when it can't be one.
        let why: String?
    }

    /// The table. An allow is offered only for `local_exec` in a language Bench
    /// lists, in no shared environment, with its code shown whole, and for an
    /// `mcp_tool` that says it only reads, from a source Bench lists: only
    /// those are truly once. A deny only for kinds whose "no" is a plain no.
    /// Either needs a request the daemon's own shape holds for, with both ids.
    static func decide(_ request: PermissionRequest, actionsOn: Bool) -> Decision {
        if request.isHelperAsk { return Decision(canAllow: false, canDeny: false, why: Why.helperAsked) }
        guard actionsOn else { return Decision(canAllow: false, canDeny: false, why: RemoteCan.Why.actionsOff) }
        guard let kind = request.known else { return Decision(canAllow: false, canDeny: false, why: Why.unknown) }
        guard request.shape, request.requestID != nil, request.toolID != nil, request.mode != nil else {
            return Decision(canAllow: false, canDeny: false, why: Why.unreadable)
        }
        let canDeny = kind.canBeDenied
        switch kind {
        case .localExec:
            let why: String? = if !PermissionKind.languages.contains(request.tool ?? "") {
                Why.language
            } else if request.sharedEnv {
                Why.shared
            } else if request.toolIdShared {
                Why.toolIdShared
            } else if let problem = request.codeProblem {
                switch problem {
                case .long: Why.codeLong
                case .odd: Why.codeOdd
                case .lines: Why.codeLines
                }
            } else if request.code == nil {
                Why.noCode
            } else {
                nil
            }
            return Decision(canAllow: why == nil, canDeny: canDeny, why: why)
        case .mcpTool:
            let why: String? = if !request.readOnly {
                Why.notReadOnly
            } else if !PermissionKind.readOnlySources.contains(request.source ?? "") {
                Why.source
            } else if request.toolIdShared {
                Why.toolIdShared
            } else {
                nil
            }
            return Decision(canAllow: why == nil, canDeny: canDeny, why: why)
        default:
            return Decision(canAllow: false, canDeny: canDeny, why: canDeny ? Why.lasting : Why.onMac)
        }
    }

    /// The title and the detail, each a plain line from the request's own
    /// fields. Nothing the agent wrote itself is passed on.
    static func words(for request: PermissionRequest) -> (title: String, detail: String) {
        if request.isHelperAsk { return ("Has a question for you", "") } // the card says a helper asks, and `why` where to answer
        guard let kind = request.known, request.shape else {
            return ("Wants your permission", "Bench can't show this request. Open it on your Mac.")
        }
        func some(_ text: String?, _ fallback: String) -> String { text ?? fallback }
        switch kind {
        case .localExec:
            let language = switch request.tool {
            case "python": "Python"
            case "r": "R"
            case "bash": "Bash"
            case "powershell": "PowerShell"
            default: some(request.tool, "code")
            }
            return ("Run \(language) code", "Claude wants to run this code on your Mac.")
        case .mcpTool:
            return ("Use \(some(request.tool, "a tool")) from \(some(request.server, "a connector"))",
                    request.readOnly ? "The tool says it only reads." : "Claude wants to use a connector's tool.")
        case .network:
            return ("Wants to reach \(some(request.target, "a site"))", "Claude is asking to connect to this site.")
        case .host:
            let title = switch request.access {
            case "rw": "Wants to read and change \(some(request.target, "a folder"))"
            case "ro": "Wants to read \(some(request.target, "a folder"))"
            default: "Wants to use \(some(request.target, "a folder"))"
            }
            return (title, "Claude is asking for access to files on your Mac.")
        case .hostDelete:
            let count = request.count ?? 1
            let title = count > 1 ? "Wants to delete \(count) files" : "Wants to delete \(some(request.target, "a file"))"
            return (title, count > 1 ? "Starting with \(some(request.target, "a file")). On your Mac." : "A file on your Mac.")
        case .artifactDelete:
            let count = request.count ?? 1
            return (count > 1 ? "Wants to delete \(count) project files" : "Wants to delete a project file",
                    "Files in the project, not on your Mac.")
        case .remoteExec:
            return ("Wants to run a command on \(some(request.provider, "another computer"))",
                    "A command on a computer that isn't this Mac.")
        case .remoteRead:
            return ("Wants to read \(some(request.target, "a file")) on \(some(request.provider, "another computer"))",
                    "A file on a computer that isn't this Mac.")
        case .byocSubmit:
            return ("Wants to start a paid job on \(some(request.provider, "a provider"))",
                    "It is billed, and it uses saved credentials.")
        case .byocKernel:
            return ("Wants to start a paid session on \(some(request.provider, "a provider"))", "It is billed.")
        case .inferSubmit:
            return ("Wants to run a paid model on \(some(request.provider, "a provider"))", "It is billed.")
        case .customizeMutation:
            return ("Wants to change \(some(request.name, "a setting"))", "A lasting change to this project.")
        case .managedEndpointRegister:
            return ("Wants to add the endpoint \(some(request.name, "a new one"))", "It runs scripts on your Mac.")
        case .credentialAccess:
            return ("Wants to use the saved credential \(some(request.name, "a credential"))",
                    "It would be handed to Claude.")
        case .skillLicense:
            return ("Wants a license accepted for \(some(request.name, "a skill"))", "Read it on your Mac first.")
        case .contactEmail:
            return ("Wants your email address", "Type it on your Mac.")
        case .credentialRequest:
            return ("Wants a password or key\(request.name.map { " (\($0))" } ?? "")", "Type it on your Mac.")
        case .sshPassword:
            return ("Wants an SSH password\(request.target.map { " for \($0)" } ?? "")", "Type it on your Mac.")
        case .usageCheckpoint:
            return ("Reached a usage checkpoint", "Choose to keep going or hold on your Mac.")
        case .setGoal:
            return ("Wants to set a goal", "Look at it on your Mac.")
        case .grantScan:
            return ("Wants access to more files", "Look at it on your Mac.")
        case .providerDiscovery:
            return ("Wants to choose a provider", "Answer it on your Mac.")
        }
    }
}

// MARK: Answering

/// Every decision about a permission answer, pure: check the fresh read, say
/// what to write, and what the daemon's reply means.
enum PermissionDecide {
    enum Sentence {
        static let allowed = "Allowed once. Claude is carrying on."
        static let denied = "Denied. Claude is carrying on without it."
        static let changed = "The request changed. Look at it again."
        static let alreadyHandled = "It was already handled."
    }

    /// The checks, in this order: a fresh read, the same request still the
    /// head (and of the same kind, when the phone said which), its holder's
    /// chain reaching this session's root, and an allow that may be one (or
    /// a deny that may be one). Then `resolve-input` to the holder.
    static func decide(_ request: RemoteActionRequest, session: String, fresh: SessionProjection?) -> RemoteDecide.Step {
        guard case .permission(let id, let allow, let kind) = request, let fresh else { return .answer(.unavailable) }
        let changed = RemoteActionResult(result: .changed, sentence: Sentence.changed)
        guard let head = fresh.permission, head.id == id, kind == nil || kind == head.kind else { return .answer(changed) }
        // The holder is the root or a frame under it: the chain says so, and the
        // page built it from the tree, never from what a frame says of itself.
        guard head.chain.last == session, head.chain.first == head.frame, PlanCheck.isFrameID(head.frame) else {
            return .answer(changed)
        }
        let decision = RemotePermission.decide(head, actionsOn: true)
        guard allow ? decision.canAllow : decision.canDeny, let requestID = head.requestID, let toolID = head.toolID else {
            return .answer(RemoteActionResult(result: .unavailable, sentence: decision.why ?? RemotePermission.Why.onMac))
        }
        return .write(.permission(frame: head.frame, requestID: requestID, toolID: toolID, allow: allow))
    }

    /// The daemon's reply: `accepted`, `buffered` and `partial` are done,
    /// `already_resolved` and the stale 400s mean someone got there first.
    static func answered(_ reply: RemoteWriteResult?, allow: Bool) -> RemoteActionResult {
        guard let reply else { return .unavailable }
        switch (reply.status, reply.bodyStatus) {
        case (200, "accepted"?), (200, "buffered"?), (200, "partial"?):
            guard reply.isJSON else { return .unavailable }
            return allow ? RemoteActionResult(result: .allowed, sentence: Sentence.allowed)
                : RemoteActionResult(result: .denied, sentence: Sentence.denied)
        case (200, "already_resolved"?):
            return RemoteActionResult(result: .changed, sentence: Sentence.alreadyHandled)
        case (400, _) where reply.staleInput:
            return RemoteActionResult(result: .changed, sentence: Sentence.changed)
        default:
            return .unavailable
        }
    }
}

extension RemoteActionRequest {
    /// A permission answer: its read needs the trace too.
    var isPermission: Bool {
        if case .permission = self { true } else { false }
    }

    /// `{"id","decision":"allow"|"deny"}`, and optionally `"kind"`: the kind the
    /// phone showed, which must still be the request's.
    static func parsePermission(_ root: [String: Any]) -> RemoteActionRequest? {
        guard let id = Pick.string(root["id"]), PermissionRequest.isIdentifier(id),
              let decision = Pick.string(root["decision"]), decision == "allow" || decision == "deny" else { return nil }
        var kind: String?
        if root["kind"] != nil {
            guard let word = Pick.string(root["kind"]), PermissionRequest.isWord(word) else { return nil }
            kind = word
        }
        return .permission(id: id, allow: decision == "allow", kind: kind)
    }
}
