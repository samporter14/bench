// SessionWriter.swift — the phone's three writes to Claude Science (DESIGN.md,
// Bench on your phone → Actions): approve a plan, answer (or cancel) a root
// question, and send a message. `apiPOST` stays as it is for the card; this is
// a separate writer, made from inside the page the same way, so the page's
// cookie session and CSRF secret carry it and Bench never holds either.
//
// The page builds each path and body itself from typed arguments, never from
// a string Swift put together, and checks the shape again there. Exactly three
// routes: `/frames/<36>/approve-plan` with `{}`, `/frames/<36>/resolve-input`
// and `/request`; and since Phase 3, a new session's
// `/projects/<id>/request`. Only the status and a few whitelisted fields come
// back. Phase 4's permission answer is the same `resolve-input` route, to the
// frame that holds the request, with its own body builder
// (Remote/RemotePermissions.swift): never a `scope`.
import Foundation
import WebKit

/// One write, as typed values. The page turns it into a path and a body.
enum RemoteWrite: Equatable, Sendable {
    /// `POST /api/frames/<frame>/approve-plan` with `{}`.
    case approvePlan(frame: String)
    /// `POST /api/frames/<frame>/resolve-input`:
    /// `{responses:[{tool_id, action:"answer", answers}]}`.
    case answer(frame: String, toolID: String, answers: [String: String])
    /// The same route: `{responses:[{tool_id, action:"cancel", answers:{}}]}`.
    case cancel(frame: String, toolID: String)
    /// `POST /api/request`: `{target_agent, root_frame_id, project_id?,
    /// input_data:{request}, intent_id, plan_mode:false}`.
    case message(frame: String, agent: String, projectID: String?, text: String, intentID: String)
    /// `POST /api/projects/<project>/request`: `{input_data:{request},
    /// plan_mode, intent_id}`, no `target_agent`: a new session. // Phase 3 browse
    case newSession(project: String, text: String, planMode: Bool, intentID: String)
    /// `POST /api/frames/<holder>/resolve-input`: `{responses:[{requestId,
    /// tool_id, approved, action}]}`, never a `scope`. // Phase 4 permissions
    case permission(frame: String, requestID: String, toolID: String, allow: Bool)

    /// The script's arguments: every name always there, null when unused.
    var arguments: [String: Any] {
        var all: [String: Any] = ["kind": "", "frameId": "", "toolId": NSNull(), "mode": NSNull(), "answers": NSNull(),
                                  "agent": NSNull(), "projectId": NSNull(), "text": NSNull(), "intentId": NSNull(),
                                  "planMode": NSNull()] // Phase 3 browse
        all["requestId"] = NSNull() // Phase 4 permissions
        all["decision"] = NSNull() // Phase 4 permissions
        switch self {
        case .approvePlan(let frame):
            all["kind"] = "approve"
            all["frameId"] = frame
        case .answer(let frame, let toolID, let answers):
            all["kind"] = "answer"
            all["frameId"] = frame
            all["toolId"] = toolID
            all["mode"] = "answer"
            all["answers"] = answers
        case .cancel(let frame, let toolID):
            all["kind"] = "answer"
            all["frameId"] = frame
            all["toolId"] = toolID
            all["mode"] = "cancel"
        case .message(let frame, let agent, let projectID, let text, let intentID):
            all["kind"] = "message"
            all["frameId"] = frame
            all["agent"] = agent
            all["projectId"] = projectID ?? NSNull()
            all["text"] = text
            all["intentId"] = intentID
        case .newSession(let project, let text, let planMode, let intentID): // Phase 3 browse
            all["kind"] = "newSession"
            all["projectId"] = project
            all["text"] = text
            all["planMode"] = planMode
            all["intentId"] = intentID
        case .permission(let frame, let requestID, let toolID, let allow): // Phase 4 permissions
            all["kind"] = "permission"
            all["frameId"] = frame
            all["toolId"] = toolID
            all["requestId"] = requestID
            all["decision"] = allow ? "allow" : "deny"
        }
        return all
    }
}

/// What a write answered: the HTTP status, and from the body only these.
struct RemoteWriteResult: Equatable, Sendable {
    let status: Int
    /// The body parsed as a JSON object.
    let isJSON: Bool
    /// The body's `code`, when it is a short identifier.
    let code: String?
    /// The body's `status`, when it is one Bench knows: `accepted`,
    /// `buffered`, `already_resolved`, `message_queued`, `already_delivered`,
    /// `already_retracted` or `partial` (a permission answer's).
    let bodyStatus: String?
    /// How many `remaining_tool_ids`, when the body lists them.
    let remaining: Int?
    /// The body's `root_frame_id`, when it is a full frame id: a new session's. // Phase 3 browse
    let rootFrameID: String?
    /// The body says "No plan awaiting approval…".
    let noPlanAwaiting: Bool
    /// The body says a question is pending ("Please answer the pending
    /// question(s)…").
    let askPending: Bool
    /// The body says the question isn't waiting any more ("Frame not awaiting
    /// user response", "No pending request with tool_id").
    let staleInput: Bool

    init(status: Int, isJSON: Bool = true, code: String? = nil, bodyStatus: String? = nil, remaining: Int? = nil,
         noPlanAwaiting: Bool = false, askPending: Bool = false, staleInput: Bool = false, rootFrameID: String? = nil) {
        self.status = status
        self.isJSON = isJSON
        self.code = code
        self.bodyStatus = bodyStatus
        self.remaining = remaining
        self.noPlanAwaiting = noPlanAwaiting
        self.askPending = askPending
        self.staleInput = staleInput
        self.rootFrameID = rootFrameID
    }

    static let knownBodyStatuses: Set<String> = [
        "accepted", "buffered", "already_resolved", "message_queued", "already_delivered", "already_retracted",
        "partial", // Phase 4 permissions
    ]

    /// The page's summary, checked again. Nil when it isn't one.
    init?(object: Any?) {
        guard let fields = object as? [String: Any], let status = Pick.int(fields["status"]), (100...599).contains(status),
              let isJSON = Pick.bool(fields["isJSON"]), let code = Pick.string(fields["code"]),
              let bodyStatus = Pick.string(fields["bodyStatus"]), let remaining = Pick.int(fields["remaining"]),
              let noPlanAwaiting = Pick.bool(fields["noPlanAwaiting"]), let askPending = Pick.bool(fields["askPending"]),
              let staleInput = Pick.bool(fields["staleInput"]) else { return nil }
        guard code.isEmpty || Self.isCode(code), bodyStatus.isEmpty || Self.knownBodyStatuses.contains(bodyStatus),
              remaining >= -1 else { return nil }
        // Phase 3 browse: a new session's id, "" when none.
        let root = fields["rootFrameId"] == nil ? "" : Pick.string(fields["rootFrameId"])
        guard let root, root.isEmpty || PlanCheck.isFrameID(root) else { return nil }
        self.init(status: status, isJSON: isJSON, code: code.isEmpty ? nil : code,
                  bodyStatus: bodyStatus.isEmpty ? nil : bodyStatus, remaining: remaining < 0 ? nil : remaining,
                  noPlanAwaiting: noPlanAwaiting, askPending: askPending, staleInput: staleInput,
                  rootFrameID: root.isEmpty ? nil : root)
    }

    /// `^[A-Za-z0-9_.-]{1,64}$`.
    static func isCode(_ text: String) -> Bool {
        (1...64).contains(text.utf8.count) && text.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
                || $0 == 0x5F || $0 == 0x2E || $0 == 0x2D
        }
    }

    /// The same answer as the card's `apiPOST` reports it, for `PlanCheck.outcome`.
    var asApproval: APIWriteResult {
        APIWriteResult(status: status, isJSON: isJSON, code: code, accepted: bodyStatus == "accepted",
                       noPlanAwaiting: noPlanAwaiting)
    }
}

// MARK: The script

enum SessionWriterScript {
    /// `benchBuildWrite(args)` → `{path, body}`, or null when the arguments
    /// don't make one of the writes. Pure: no fetch, no DOM.
    static let builder = #"""
    function benchBuildWrite(a) {
        "use strict";
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const points = text => Array.from(text).length;
        const text = (v, min, max) => typeof v === "string" && v.trim() !== "" && points(v) >= min && points(v) <= max;
        // Phase 4 permissions: resolve-input for a request, built in its own function.
        if (isObject(a) && a.kind === "permission") { return benchBuildPermissionWrite(a); }
        // Phase 3 browse: a new session in a project, to the server's default agent.
        if (isObject(a) && a.kind === "newSession") {
            if (typeof a.projectId !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(a.projectId)) { return null; }
            if (!text(a.text, 1, 4000) || typeof a.planMode !== "boolean") { return null; }
            if (typeof a.intentId !== "string"
                || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(a.intentId)) { return null; }
            return { path: "/api/projects/" + a.projectId + "/request",
                     body: { input_data: { request: a.text }, plan_mode: a.planMode, intent_id: a.intentId } };
        }
        if (!isObject(a) || typeof a.frameId !== "string" || !/^[0-9a-f-]{36}$/.test(a.frameId)) { return null; }
        const frame = "/api/frames/" + a.frameId;
        if (a.kind === "approve") {
            return { path: frame + "/approve-plan", body: {} };
        }
        if (a.kind === "answer") {
            if (!text(a.toolId, 1, 200)) { return null; }
            if (a.mode === "cancel") {
                return { path: frame + "/resolve-input",
                         body: { responses: [{ tool_id: a.toolId, action: "cancel", answers: {} }] } };
            }
            if (a.mode !== "answer" || !isObject(a.answers)) { return null; }
            const keys = Object.keys(a.answers);
            if (keys.length < 1 || keys.length > 10) { return null; }
            const entries = [];
            for (const key of keys) {
                const value = a.answers[key];
                if (!text(key, 1, 2000) || !text(value, 1, 1000)) { return null; }
                entries.push([key, value]);
            }
            return { path: frame + "/resolve-input",
                     body: { responses: [{ tool_id: a.toolId, action: "answer", answers: Object.fromEntries(entries) }] } };
        }
        if (a.kind === "message") {
            if (!text(a.agent, 1, 200) || !text(a.text, 1, 4000)) { return null; }
            if (typeof a.intentId !== "string"
                || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(a.intentId)) { return null; }
            if (a.projectId !== null && a.projectId !== undefined && !text(a.projectId, 1, 200)) { return null; }
            const body = { target_agent: a.agent, root_frame_id: a.frameId, input_data: { request: a.text },
                           intent_id: a.intentId, plan_mode: false };
            if (typeof a.projectId === "string") { body.project_id = a.projectId; }
            return { path: "/api/request", body: body };
        }
        return null;
    }
    """# + "\n" + PermissionScript.writeBuilder // Phase 4 permissions

    /// `benchSummarizeWrite(status, text)`: the whitelisted fields of an answer.
    static let summarizer = #"""
    function benchSummarizeWrite(status, raw) {
        "use strict";
        const KNOWN = ["accepted", "buffered", "already_resolved", "message_queued", "already_delivered", "already_retracted",
                       "partial"];
        const text = typeof raw === "string" ? raw : "";
        let json = null;
        try { json = JSON.parse(text); } catch (e) { json = null; }
        const isObject = json !== null && typeof json === "object" && !Array.isArray(json);
        return {
            status: typeof status === "number" ? status : 0,
            isJSON: isObject,
            code: isObject && typeof json.code === "string" && /^[A-Za-z0-9_.-]{1,64}$/.test(json.code) ? json.code : "",
            bodyStatus: isObject && typeof json.status === "string" && KNOWN.indexOf(json.status) >= 0 ? json.status : "",
            remaining: isObject && Array.isArray(json.remaining_tool_ids) ? json.remaining_tool_ids.length : -1,
            noPlanAwaiting: text.indexOf("No plan awaiting") >= 0,
            askPending: /pending question/i.test(text),
            staleInput: /not awaiting user response|no pending request|no pending input request|live_approval_stale|frame state changed while resolving/i.test(text),
            rootFrameId: isObject && typeof json.root_frame_id === "string" && /^[0-9a-f-]{36}$/.test(json.root_frame_id)
                ? json.root_frame_id : "",
        };
    }
    """#

    /// What `callAsyncJavaScript` runs, with the arguments of
    /// `RemoteWrite.arguments`. Answers a JSON string: `{"result":{…}}`,
    /// `{"refused":true}` (the arguments made no write) or `{"failed":true}`
    /// (the request didn't complete).
    static let body = builder + "\n" + summarizer + #"""

    const write = benchBuildWrite({ kind: kind, frameId: frameId, toolId: toolId, mode: mode, answers: answers,
                                    agent: agent, projectId: projectId, text: text, intentId: intentId,
                                    planMode: planMode,
                                    requestId: requestId, decision: decision }); // Phase 4 permissions
    if (write === null) { return JSON.stringify({ refused: true }); }
    const secret = () => {
        const entry = document.cookie.split(";").map(part => part.trim())
            .find(part => part.startsWith("operon_csrf="));
        if (!entry) { return ""; }
        const value = entry.slice("operon_csrf=".length);
        try { return decodeURIComponent(value); } catch (e) { return value; }
    };
    const signal = () => typeof AbortSignal === "function" && typeof AbortSignal.timeout === "function"
        ? AbortSignal.timeout(15000) : undefined;
    const send = async () => {
        let response;
        try {
            response = await fetch(write.path, {
                method: "POST",
                credentials: "include",
                cache: "no-store",
                headers: { "Content-Type": "application/json", "Accept": "application/json", "x-operon-csrf": secret() },
                body: JSON.stringify(write.body),
                signal: signal(),
            });
        } catch (e) { return null; }
        let reply = "";
        try { reply = await response.text(); } catch (e) { reply = ""; }
        return benchSummarizeWrite(response.status, reply);
    };
    let result = await send();
    if (result !== null && result.status === 403 && result.code === "csrf_stale") {
        try { await fetch("/api/csrf", { credentials: "include", cache: "no-store" }); } catch (e) { }
        result = await send();
    }
    return JSON.stringify(result === null ? { failed: true } : { result: result });
    """#

    /// The page's answer, checked again here.
    static func result(of data: Data) throws -> RemoteWriteResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw WebAPIError.badResponse
        }
        if Pick.bool(root["refused"]) == true { throw WebAPIError.notAllowed }
        guard let result = RemoteWriteResult(object: root["result"]) else { throw WebAPIError.badResponse }
        return result
    }
}

// MARK: Writing through the page

extension WebContainer {
    /// Makes one of the phone's writes from inside the page, as Claude
    /// Science's own UI does: the `operon_csrf` cookie's value as
    /// `x-operon-csrf`, the page's `Origin`, a 403 `csrf_stale` refreshed with
    /// `GET /api/csrf` and retried once. Any status comes back as a result;
    /// a 401 also starts signing in again.
    func writeSession(_ write: RemoteWrite) async throws -> RemoteWriteResult {
        guard status == .ready else { throw WebAPIError.notReady }
        let value = try await webView.callAsyncJavaScript(SessionWriterScript.body, arguments: write.arguments,
                                                          in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        let result = try SessionWriterScript.result(of: Data(text.utf8))
        // Refused: the page's session didn't take. Sign in again.
        if result.status == 401 { sessionLost() }
        return result
    }
}
