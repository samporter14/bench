// SessionWriter.swift — the phone's three writes to Claude Science (DESIGN.md,
// Capsid on your phone → Actions): approve a plan, answer (or cancel) a root
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
//
// Every write here has a deadline (Remote/WriteDeadline.swift): in the page,
// one AbortController over the CSRF refresh, the POST and its answer, and in
// Swift another beyond it. A write that got no answer in time is not a failure
// and not a success but unknown: `RemoteWriteResult.unknown`.
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
    /// input_data:{request}, intent_id, plan_mode:false}`. `attachment` (a
    /// photo's: the text may end in the attachment line) is for the photo
    /// flow alone.
    case message(frame: String, agent: String, projectID: String?, text: String, intentID: String, attachment: Bool = false)
    /// `POST /api/projects/<project>/request`: `{input_data:{request},
    /// plan_mode, intent_id}`, no `target_agent`: a new session. `attachment`
    /// as above. // Phase 3 browse
    case newSession(project: String, text: String, planMode: Bool, intentID: String, attachment: Bool = false)
    /// `POST /api/frames/<holder>/resolve-input`: `{responses:[{requestId,
    /// tool_id, approved, action}]}`, never a `scope`. // Phase 4 permissions
    case permission(frame: String, requestID: String, toolID: String, allow: Bool)
    /// `POST /api/request` as `message`, but with no `plan_mode` at all: what
    /// to change in a plan waiting for approval. The daemon takes a message
    /// to such a session as a change request, and the session keeps its own
    /// plan mode; the plan stays unapproved until Approve. Plain text only.
    case planFeedback(frame: String, agent: String, projectID: String, text: String, intentID: String)
    /// `message`, whose text may end in one to eight attachment lines, one
    /// to a line, of files Quick Start uploaded first (QuickStart/QuickStartFlow.swift).
    /// Not a photo's: the page gives a photo's request and this one their own
    /// shapes.
    case messageWithFiles(frame: String, agent: String, projectID: String?, text: String, intentID: String)
    /// `newSession`, with the same room for the attachment lines.
    case newSessionWithFiles(project: String, text: String, planMode: Bool, intentID: String)

    /// The intent id a message or a new session goes with: what a turn of
    /// the session carries back (`MessageSeen`). Nil for the other writes.
    var intentID: String? {
        switch self {
        case .message(_, _, _, _, let intent, _), .newSession(_, _, _, let intent, _), .planFeedback(_, _, _, _, let intent),
             .messageWithFiles(_, _, _, _, let intent), .newSessionWithFiles(_, _, _, let intent):
            intent
        case .approvePlan, .answer, .cancel, .permission:
            nil
        }
    }

    /// The script's arguments: every name always there, null when unused.
    var arguments: [String: Any] {
        var all: [String: Any] = ["kind": "", "frameId": "", "toolId": NSNull(), "mode": NSNull(), "answers": NSNull(),
                                  "agent": NSNull(), "projectId": NSNull(), "text": NSNull(), "intentId": NSNull(),
                                  "planMode": NSNull(), "attachment": false, "files": false] // Phase 3 browse
        all["requestId"] = NSNull() // Phase 4 permissions
        all["decision"] = NSNull() // Phase 4 permissions
        // The whole write, the CSRF refresh and the POST, has this long in the page (WriteDeadline).
        all["timeoutMS"] = WriteDeadline.milliseconds(WriteDeadline.small)
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
        case .message(let frame, let agent, let projectID, let text, let intentID, let attachment):
            all["kind"] = "message"
            all["frameId"] = frame
            all["agent"] = agent
            all["projectId"] = projectID ?? NSNull()
            all["text"] = text
            all["intentId"] = intentID
            all["attachment"] = attachment
        case .newSession(let project, let text, let planMode, let intentID, let attachment): // Phase 3 browse
            all["kind"] = "newSession"
            all["projectId"] = project
            all["text"] = text
            all["planMode"] = planMode
            all["intentId"] = intentID
            all["attachment"] = attachment
        case .permission(let frame, let requestID, let toolID, let allow): // Phase 4 permissions
            all["kind"] = "permission"
            all["frameId"] = frame
            all["toolId"] = toolID
            all["requestId"] = requestID
            all["decision"] = allow ? "allow" : "deny"
        case .planFeedback(let frame, let agent, let projectID, let text, let intentID):
            all["kind"] = "planFeedback"
            all["frameId"] = frame
            all["agent"] = agent
            all["projectId"] = projectID
            all["text"] = text
            all["intentId"] = intentID
        case .messageWithFiles(let frame, let agent, let projectID, let text, let intentID):
            all["kind"] = "message"
            all["frameId"] = frame
            all["agent"] = agent
            all["projectId"] = projectID ?? NSNull()
            all["text"] = text
            all["intentId"] = intentID
            all["files"] = true
        case .newSessionWithFiles(let project, let text, let planMode, let intentID):
            all["kind"] = "newSession"
            all["projectId"] = project
            all["text"] = text
            all["planMode"] = planMode
            all["intentId"] = intentID
            all["files"] = true
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
    /// The write went out and no answer came back in time, or at all: it may
    /// or may not have been made. Neither done nor failed; the callers settle
    /// it with a fresh read, and never send it again on their own.
    let isUnknown: Bool

    /// What a write that got no answer is.
    static let unknown = RemoteWriteResult(status: 0, isJSON: false, isUnknown: true)

    init(status: Int, isJSON: Bool = true, code: String? = nil, bodyStatus: String? = nil, remaining: Int? = nil,
         noPlanAwaiting: Bool = false, askPending: Bool = false, staleInput: Bool = false, rootFrameID: String? = nil,
         isUnknown: Bool = false) {
        self.status = status
        self.isJSON = isJSON
        self.code = code
        self.bodyStatus = bodyStatus
        self.remaining = remaining
        self.noPlanAwaiting = noPlanAwaiting
        self.askPending = askPending
        self.staleInput = staleInput
        self.rootFrameID = rootFrameID
        self.isUnknown = isUnknown
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
        // Phase 4 photos: a photo's request (`a.attachment`, from the photo flow alone) is the text (4,000
        // at most), a blank line and one attachment line of exactly the shape Bench writes, or the line
        // alone, and a photo's text stays at 4,000 here whatever else is allowed. Every other request is
        // plain text at 32,000 (`RemoteActionRequest.macMessageLimit`: what a message made on the Mac may be),
        // and refuses what the UI would read as a reference (the same seven prefixes `PhotoText` refuses, as
        // they are or with their white space gone). The phone's own messages and new sessions stop at 4,000
        // before a write is built (`RemoteActionRequest.parse`, `NewSessionRequest.parse`), so the page is not
        // their limit and does not pretend to be.
        const REFERENCES = ['{{artifact:', '{"type":"artifact"', '{"type":"attachment"', '{"type":"skill"',
                            '{"type":"session"', '{"artifact_ref":', '{"file_path":'];
        const hasReference = v => {
            if (v.indexOf("{") < 0) { return false; }
            const squeezed = v.replace(/\s+/g, "");
            return REFERENCES.some(prefix => v.indexOf(prefix) >= 0 || squeezed.indexOf(prefix) >= 0);
        };
        const LINE = /\{"type":"attachment","id":"[0-9A-Fa-f-]{36}","version_id":"[0-9A-Fa-f-]{36}","filename":"phone-photo-[0-9]{8}-[0-9]{6}\.jpg","artifact_ref":"\{\{artifact:[0-9A-Fa-f-]{36}\}\}","content_type":"image\/jpeg","size_bytes":[0-9]{1,8}\}$/;
        // Quick Start's files: one to eight lines of the same shape, one to a line, after the text and a blank
        // line. A name has no quote, backslash, brace or control character; a type is `type/subtype`.
        const FILE_LINE = /\{"type":"attachment","id":"[0-9A-Fa-f-]{36}","version_id":"[0-9A-Fa-f-]{36}","filename":"[^"\\{}\u0000-\u001f\u007f]{1,120}","artifact_ref":"\{\{artifact:[0-9A-Fa-f-]{36}\}\}","content_type":"[a-z0-9][a-z0-9.+-]{0,60}\/[a-z0-9][a-z0-9.+-]{0,100}","size_bytes":[0-9]{1,9}\}/.source;
        const FILE_LINES = new RegExp("(?:" + FILE_LINE + ")(?:\\n(?:" + FILE_LINE + ")){0,7}$");
        const request = (v, attachment, files) => {
            if (typeof v !== "string") { return false; }
            if (attachment === true && files === true) { return false; }
            const most = attachment === true ? 4000 : 32000;
            const found = attachment === true ? LINE.exec(v) : (files === true ? FILE_LINES.exec(v) : null);
            if (found === null) { return text(v, 1, most) && !hasReference(v); }
            const head = v.slice(0, found.index);
            return head === "" || (head.endsWith("\n\n") && text(head.slice(0, -2), 1, most) && !hasReference(head));
        };
        // Phase 3 browse: a new session in a project, to the server's default agent.
        if (isObject(a) && a.kind === "newSession") {
            if (typeof a.projectId !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(a.projectId)) { return null; }
            if (!request(a.text, a.attachment, a.files) || typeof a.planMode !== "boolean") { return null; }
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
            if (!text(a.agent, 1, 200) || !request(a.text, a.attachment, a.files)) { return null; }
            if (typeof a.intentId !== "string"
                || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(a.intentId)) { return null; }
            if (a.projectId !== null && a.projectId !== undefined && !text(a.projectId, 1, 200)) { return null; }
            const body = { target_agent: a.agent, root_frame_id: a.frameId, input_data: { request: a.text },
                           intent_id: a.intentId, plan_mode: false };
            if (typeof a.projectId === "string") { body.project_id = a.projectId; }
            return { path: "/api/request", body: body };
        }
        // What to change in a plan that waits: a message with no plan_mode, so the
        // session's own stays as it is. Plain text, a project always.
        if (a.kind === "planFeedback") {
            if (!text(a.agent, 1, 200) || !request(a.text, false) || !text(a.projectId, 1, 200)) { return null; }
            if (typeof a.intentId !== "string"
                || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(a.intentId)) { return null; }
            return { path: "/api/request",
                     body: { target_agent: a.agent, root_frame_id: a.frameId, project_id: a.projectId,
                             input_data: { request: a.text }, intent_id: a.intentId } };
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
    /// `RemoteWrite.arguments` and `timeoutMS`. Answers a JSON string:
    /// `{"result":{…}}`, `{"refused":true}` (the arguments made no write) or
    /// `{"unknown":true}` (no answer came back in time, or at all: the write
    /// may have been made).
    ///
    /// The refresh after a stale secret and the POSTs share one deadline
    /// (`WriteScript.bounded`). If it passes while the refresh runs, the first
    /// POST's 403 is the answer: nothing was accepted. If it passes during a
    /// POST, or a POST fails with no answer, the write is unknown.
    static let body = WriteScript.bounded + "\n" + builder + "\n" + summarizer + #"""

    const write = benchBuildWrite({ kind: kind, frameId: frameId, toolId: toolId, mode: mode, answers: answers,
                                    agent: agent, projectId: projectId, text: text, intentId: intentId,
                                    planMode: planMode, attachment: attachment, // Phase 4 photos
                                    files: typeof files === "boolean" ? files : false, // Quick Start
                                    requestId: requestId, decision: decision }); // Phase 4 permissions
    if (write === null) { return JSON.stringify({ refused: true }); }
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
            let response;
            try {
                response = await fetch(write.path, {
                    method: "POST",
                    credentials: "include",
                    cache: "no-store",
                    headers: { "Content-Type": "application/json", "Accept": "application/json", "x-operon-csrf": secret() },
                    body: JSON.stringify(write.body),
                    signal: signal,
                });
            } catch (e) { return null; }
            let reply = "";
            try { reply = await response.text(); } catch (e) { if (signal && signal.aborted) { return null; } reply = ""; }
            if (signal && signal.aborted) { return null; }
            return benchSummarizeWrite(response.status, reply);
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

    /// The page's answer, checked again here.
    static func result(of data: Data) throws -> RemoteWriteResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw WebAPIError.badResponse
        }
        if Pick.bool(root["refused"]) == true { throw WebAPIError.notAllowed }
        if Pick.bool(root["unknown"]) == true { throw WebAPIError.timedOut }
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
    ///
    /// The whole write has `WriteDeadline.small` in the page and `grace` more
    /// in Swift. One that got no answer in time throws
    /// `WebAPIError.timedOut`: it may have been made.
    func writeSession(_ write: RemoteWrite) async throws -> RemoteWriteResult {
        guard status == .ready else { throw WebAPIError.notReady }
        let view = webView, kind = write
        let text: String? = try await WriteDeadline.bridge(WriteDeadline.small + WriteDeadline.grace) {
            try await view.callAsyncJavaScript(SessionWriterScript.body, arguments: kind.arguments,
                                               in: nil, contentWorld: .defaultClient) as? String
        }
        guard let text else { throw WebAPIError.badResponse }
        let result = try SessionWriterScript.result(of: Data(text.utf8))
        // Refused: the page's session didn't take. Sign in again.
        if result.status == 401 { sessionLost() }
        return result
    }
}

extension WebContainer {
    /// `writeSession`, as the writers' dependencies want it: nil for a write
    /// that was not made (the page isn't up, or refused the arguments), the
    /// daemon's answer, or `RemoteWriteResult.unknown` for anything that
    /// happened after it could have gone: no answer in time, a page that
    /// threw, an answer that isn't one. Those are settled by a fresh read
    /// (`RemoteSessions.settling`), not called failures.
    func writeAnswer(_ write: RemoteWrite) async -> RemoteWriteResult? {
        do {
            return try await writeSession(write)
        } catch WebAPIError.notReady {
            return nil
        } catch WebAPIError.notAllowed {
            return nil
        } catch {
            return .unknown
        }
    }
}
