// SessionReader.swift — reading one session for the phone (DESIGN.md, Bench on
// your phone → Reading a session). The page runs the two GETs and *projects*
// them itself, so Swift only ever receives the fields below: the status, its
// line, the last reply, a few short turns, the agent's messages to the user,
// the root's own question and the plan fields Approve uses. Never thinking,
// tool calls or results, images, paths, attachments, sub-agents or artifacts.
// A turn of yours also carries its intent id and its attachment lines' file
// ids, which tell a message just sent from another (WriteSettle.swift) and go
// no further than that.
// Phase 4 adds one thing to a full read: the head of the queue of permission
// requests, the root's and its helpers' (Remote/RemotePermissions.swift), as
// its plain fields only.
//
// The projection is plain JavaScript with no fetch and no DOM, so the tests
// run the very same string in JavaScriptCore on made-up frames. Swift checks
// every field again (`SessionProjection`); anything that doesn't match makes
// the session "unreadable", and the phone shows its status and Open on Mac.
//
// What is read lives in memory only, while the phone's answer is built (and
// in RemoteSessions' 5-second cache). It is never logged or saved.
import Foundation
import WebKit

// MARK: The script

enum SessionReaderScript {
    /// `benchProjectSession(shallow, page, withTurns)`: the projection, or null
    /// when a shape doesn't match. Pure: no fetch, no DOM, no globals.
    static let projection = #"""
    function benchProjectSession(shallow, page, withTurns, trace, rootId) {
        "use strict";
        // The daemon's frame statuses. Anything else is a daemon Bench doesn't know.
        const KNOWN = ["processing", "awaiting_user_response", "awaiting_plan_approval", "completed",
                       "success", "cancelled", "replaced", "failed"];
        // User rows Claude Science's own UI hides.
        const HIDDEN_FLAGS = ["_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent",
                              "_from_aside", "_harness_notice"];
        const HIDDEN_STARTS = ["[System]", "[compute]", "[Memory]", "[image:", "[document:"];
        // A plan version or artifact id fit for a path, as PlanCheck.isVersionID.
        const PLAN_ID = /^[A-Za-z0-9_-]{1,128}$/;
        // 2000 to 2100, in milliseconds: a time outside it is no time.
        const EARLIEST = 946684800000, LATEST = 4102444800000;
        // A user row's `_intent_id` (uuid v4, as a phone or Capsid makes one), and an attachment line's file id:
        // only to tell one message of yours from another (WriteSettle.swift), never shown.
        const INTENT = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
        const FILE_ID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const isAbsent = v => v === undefined || v === null;
        // An object, or a string holding one; null when absent; undefined for anything else.
        const objectOrNull = v => {
            if (isAbsent(v)) { return null; }
            if (isObject(v)) { return v; }
            if (typeof v === "string") {
                try { const parsed = JSON.parse(v); if (isObject(parsed)) { return parsed; } } catch (e) { }
            }
            return undefined;
        };
        // Lengths in code points, as Swift's unicodeScalars count them.
        const points = text => Array.from(text).length;
        const cut = (text, limit) => {
            const all = Array.from(text);
            return all.length <= limit ? text : all.slice(0, limit - 1).join("") + "…";
        };
        // One line: white space runs become one space. Null when empty or not a string.
        const line = (v, limit) => {
            if (typeof v !== "string") { return null; }
            const one = v.split(/\s+/).filter(Boolean).join(" ");
            return one ? cut(one, limit) : null;
        };
        // A string kept whole, or null: for values sent back as they are.
        const whole = (v, limit) => typeof v === "string" && v.trim() !== "" && points(v) <= limit ? v : null;
        // Milliseconds since 1970, from milliseconds, seconds or a date string.
        const time = v => {
            let ms = null;
            if (typeof v === "number" && isFinite(v)) { ms = v < 1e11 ? v * 1000 : v; }
            else if (typeof v === "string") { const parsed = Date.parse(v); if (isFinite(parsed)) { ms = parsed; } }
            return ms !== null && ms >= EARLIEST && ms <= LATEST ? Math.round(ms) : null;
        };

        // The plan, as PlanFrame reads it: the context's value, else the
        // output's when the context has none at all.
        const pick = (context, output) => isAbsent(context) ? output : context;
        const planID = v => typeof v === "string" && PLAN_ID.test(v) ? v : null;
        const approval = values => {
            let yes = false, unclear = false;
            for (const v of values) {
                if (isAbsent(v)) { continue; }
                if (typeof v !== "boolean") { unclear = true; } else if (v) { yes = true; }
            }
            return yes ? "yes" : unclear ? "unclear" : "no";
        };

        // A root `ask`, or null when its shape doesn't match.
        const ask = request => {
            const toolId = whole(request.tool_id, 200);
            const questions = request.questions;
            if (toolId === null || !Array.isArray(questions) || questions.length === 0 || questions.length > 10) { return null; }
            const items = [], seen = new Set();
            for (const q of questions) {
                if (!isObject(q)) { return null; }
                // Sent back whole as the answer's key, so never cut.
                const question = whole(q.question, 2000);
                if (question === null || seen.has(question)) { return null; }
                seen.add(question);
                const options = isAbsent(q.options) ? [] : q.options;
                if (!Array.isArray(options) || options.length > 26) { return null; }
                const choices = [];
                for (const o of options) {
                    if (!isObject(o)) { return null; }
                    const label = whole(o.label, 500);
                    if (label === null) { return null; }
                    choices.push({ label: label, detail: line(o.description, 1000) });
                }
                items.push({ question: question, header: line(q.header, 200) || "", multi: q.multi_select === true, options: choices });
            }
            return { toolId: toolId, items: items };
        };

        // The last turns: user and assistant rows, text blocks only. Null
        // when a shape doesn't match.
        const readTurns = page => {
            if (!isObject(page) || typeof page.from !== "number" || typeof page.total !== "number"
                || !Array.isArray(page.messages)) { return null; }
            const turns = [];
            for (const m of page.messages) {
                if (!isObject(m)) { return null; }
                if (m.role !== "user" && m.role !== "assistant") { continue; }
                const texts = [];
                if (typeof m.content === "string") {
                    texts.push(m.content);
                } else if (Array.isArray(m.content)) {
                    for (const block of m.content) {
                        if (!isObject(block) || typeof block.type !== "string") { return null; }
                        if (block.type !== "text") { continue; }
                        if (typeof block.text !== "string") { return null; }
                        texts.push(block.text);
                    }
                } else {
                    return null;
                }
                // Too big for the daemon to send: a placeholder.
                if (!isAbsent(m._oversized_bytes)) { continue; }
                // Attachment lines (Claude Science's upload format) read as their file names, and their ids are kept apart.
                let text = texts.join("\n\n").trim();
                const files = [];
                if (text.indexOf('{"type":"attachment"') >= 0) {
                    const names = [];
                    text = text.split("\n").filter(line => {
                        const t = line.trim();
                        if (!t.startsWith('{"type":"attachment"')) { return true; }
                        let o = null;
                        try { o = JSON.parse(t); } catch (e) { return true; }
                        if (!isObject(o) || o.type !== "attachment") { return true; }
                        if (typeof o.filename === "string" && o.filename.length <= 255) { names.push(o.filename); }
                        if (typeof o.id === "string" && FILE_ID.test(o.id) && files.length < 20) { files.push(o.id.toLowerCase()); }
                        return false;
                    }).join("\n").trim();
                    if (names.length > 0) { text = (text === "" ? "" : text + "\n\n") + "Attached: " + names.join(", "); }
                }
                if (m.role === "user") {
                    if (HIDDEN_FLAGS.some(flag => Boolean(m[flag]))) { continue; }
                    if (HIDDEN_STARTS.some(start => text.startsWith(start))) { continue; }
                    // Notes the daemon adds inside a message ("[System] Attached file: …") stay hidden.
                    text = text.split("\n").filter(l => !HIDDEN_STARTS.some(s => l.trim().startsWith(s))).join("\n").trim();
                }
                // Tool calls or results only, or nothing.
                if (text === "") { continue; }
                // Rows may carry no `_ts` (seen on the daemon in October):
                // the turn shows without a time.
                const at = typeof m._ts === "number" ? time(m._ts) : null;
                const intent = m.role === "user" && typeof m._intent_id === "string" && INTENT.test(m._intent_id) ? m._intent_id : null;
                turns.push({ role: m.role === "user" ? "you" : "claude", at: at, text: cut(text, 2000), intent: intent, files: files });
            }
            return turns.slice(-12);
        };

        if (!isObject(shallow)) { return null; }
        const status = shallow.status;
        if (typeof status !== "string" || KNOWN.indexOf(status) < 0) { return null; }
        const context = objectOrNull(shallow.context_data), output = objectOrNull(shallow.output_data);
        if (context === undefined || output === undefined) { return null; }
        const ctx = context || {}, out = output || {};

        const response = out.response;
        if (!isAbsent(response) && typeof response !== "string") { return null; }
        const reply = typeof response === "string" && response.trim() !== "" ? cut(response.trim(), 4000) : null;

        const sent = ctx._sent_user_messages;
        if (!isAbsent(sent) && !Array.isArray(sent)) { return null; }
        const notes = [];
        for (const note of sent || []) {
            if (!isObject(note) || typeof note.text !== "string") { return null; }
            if (note.text.trim() !== "") { notes.push({ text: cut(note.text.trim(), 2000), at: time(note.at) }); }
        }

        const queuedList = shallow.queued_user_messages;
        if (!isAbsent(queuedList) && !Array.isArray(queuedList)) { return null; }

        const pending = out.pending_input_requests;
        if (!isAbsent(pending) && !Array.isArray(pending)) { return null; }
        const asks = [];
        for (const request of pending || []) {
            if (isObject(request) && request.kind === "ask" && asks.length < 4) { asks.push(ask(request)); }
        }

        let turns = null;
        if (withTurns === true) {
            turns = readTurns(page);
            if (turns === null) { return null; }
        }

        // Phase 4 permissions: the head of the queue across the root and its helpers.
        const permission = isObject(trace) ? benchProjectPermission(shallow, trace, rootId) : null;

        return {
            status: status,
            agentName: whole(shallow.agent_name, 200),
            projectId: whole(shallow.project_id, 200),
            statusLine: line(shallow.status_description, 200),
            reply: reply,
            replyAt: reply === null ? null : time(shallow.updated_at),
            toYou: notes.slice(-5),
            queued: queuedList ? queuedList.length : 0,
            asks: asks,
            plan: {
                version: planID(pick(ctx._plan_version_id, out.plan_version_id)),
                artifact: planID(pick(ctx._plan_artifact_id, out.plan_artifact_id)),
                approval: approval([ctx._plan_approved, out.plan_approved]),
            },
            turns: turns,
            permission: permission,
        };
    }
    """# + "\n" + PermissionScript.reading // Phase 4 permissions

    /// What `callAsyncJavaScript` runs, with the arguments `frameId` and
    /// `withTurns`: the projection, then the two GETs, exactly. Answers a
    /// JSON string: `{"outcome":"read","session":{…}}`, `"unreadable"`,
    /// `"lost"` (a 401) or `"refused"` (an id that isn't one).
    static let body = projection + #"""

    if (typeof frameId !== "string" || !/^[0-9a-f-]{36}$/.test(frameId)) { return JSON.stringify({ outcome: "refused" }); }
    const wantTurns = withTurns === true || withTurns === 1;
    const signal = () => typeof AbortSignal === "function" && typeof AbortSignal.timeout === "function"
        ? AbortSignal.timeout(8000) : undefined;
    // no-store: nothing read here stays in WebKit's cache.
    const get = async path => {
        let response;
        try {
            response = await fetch(path, { credentials: "include", cache: "no-store",
                                           headers: { "Accept": "application/json" }, signal: signal() });
        } catch (e) { return { failed: true }; }
        if (response.status === 401) { return { lost: true }; }
        if (!response.ok) { return { failed: true }; }
        try { return { json: JSON.parse(await response.text()) }; } catch (e) { return { failed: true }; }
    };
    const frame = await get("/api/frames/" + frameId + "?shallow=true");
    if (frame.lost) { return JSON.stringify({ outcome: "lost" }); }
    if (frame.failed) { return JSON.stringify({ outcome: "unreadable" }); }
    let page = null;
    if (wantTurns) {
        const messages = await get("/api/frames/" + frameId + "/messages?from=-12&limit=12");
        if (messages.lost) { return JSON.stringify({ outcome: "lost" }); }
        if (messages.failed) { return JSON.stringify({ outcome: "unreadable" }); }
        page = messages.json;
    }
    // Phase 4 permissions: a frame that may hold requests has its children read too.
    let trace = null;
    if (wantTurns && benchNeedsTrace(frame.json)) {
        const tracePath = benchReadPath("trace", frameId);
        if (tracePath !== null) {
            const traced = await get(tracePath);
            if (traced.lost) { return JSON.stringify({ outcome: "lost" }); }
            trace = traced.failed ? null : traced.json;
        }
    }
    let session = null;
    try { session = benchProjectSession(frame.json, page, wantTurns, trace, frameId); } catch (e) { session = null; }
    return JSON.stringify(session === null ? { outcome: "unreadable" } : { outcome: "read", session: session });
    """#

    /// What the page said.
    enum Outcome: Equatable {
        case read(SessionProjection)
        case unreadable
        /// A 401: the page's session didn't take.
        case lost
    }

    /// The page's answer, checked again here. Anything unexpected is unreadable.
    static func outcome(of data: Data) -> Outcome {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let outcome = Pick.string(root["outcome"]) else { return .unreadable }
        switch outcome {
        case "lost": return .lost
        case "read": return SessionProjection(object: root["session"]).map(Outcome.read) ?? .unreadable
        default: return .unreadable
        }
    }
}

// MARK: What Swift receives

/// One session as the page projected it, every field checked again. Nil
/// from `init(object:)` at the first thing that doesn't match.
struct SessionProjection: Equatable, Sendable {
    /// The daemon's eight frame statuses.
    static let knownStatuses: Set<String> = [
        "processing", "awaiting_user_response", "awaiting_plan_approval", "completed",
        "success", "cancelled", "replaced", "failed",
    ]

    /// The limits, in code points, the page cuts or refuses at.
    enum Limit {
        static let statusLine = 200
        static let reply = 4_000
        static let note = 2_000
        static let notes = 5
        static let turn = 2_000
        static let turns = 12
        static let question = 2_000
        static let questions = 10
        static let header = 200
        static let label = 500
        static let options = 26
        static let detail = 1_000
        static let toolID = 200
        static let asks = 4
        static let name = 200
        /// A turn's attachment ids.
        static let files = 20
    }

    /// A message the agent sent the user mid-run ("Message to you").
    struct Note: Equatable, Sendable {
        let text: String
        let at: Date?
    }

    struct Turn: Equatable, Sendable {
        enum Role: String, Sendable { case you, claude }
        let role: Role
        let at: Date?
        let text: String
        /// A turn of yours: the intent id it was sent with (the row's
        /// `_intent_id`), when it has one. Only to tell one message from
        /// another (`MessageSeen`); never sent to the phone.
        let intent: String?
        /// The ids of the files its attachment lines named, lowercased, in
        /// order. The same use, and the same rule.
        let files: [String]

        init(role: Role, at: Date?, text: String, intent: String? = nil, files: [String] = []) {
            self.role = role
            self.at = at
            self.text = text
            self.intent = intent
            self.files = files
        }
    }

    struct Option: Equatable, Sendable {
        let label: String
        let detail: String?
    }

    struct Question: Equatable, Sendable {
        let question: String
        let header: String
        let multi: Bool
        let options: [Option]
    }

    /// A root `ask` waiting for the user.
    struct Ask: Equatable, Sendable {
        let toolID: String
        let items: [Question]
    }

    let status: String
    /// The root's `agent_name`: a message goes to it, and only it.
    let agentName: String?
    let projectID: String?
    let statusLine: String?
    let reply: String?
    let replyAt: Date?
    let toYou: [Note]
    let queued: Int
    /// The root's own `ask` requests, in order; nil for one whose shape
    /// doesn't match.
    let asks: [Ask?]
    /// The plan fields, as `PlanFrame` reads them from the whole frame.
    let planFrame: PlanFrame
    /// Oldest first. Nil when only the frame was read (an action's check).
    let turns: [Turn]?
    /// The head of the queue of the root's and its helpers' permission
    /// requests, when there is one and it could be read: only in a full read
    /// (with turns). Phase 4 permissions.
    let permission: PermissionRequest?

    init(status: String, agentName: String?, projectID: String?, statusLine: String? = nil, reply: String? = nil,
         replyAt: Date? = nil, toYou: [Note] = [], queued: Int = 0, asks: [Ask?] = [],
         planVersion: String? = nil, planArtifact: String? = nil, approval: PlanFrame.Approval = .no,
         turns: [Turn]? = nil, permission: PermissionRequest? = nil) {
        self.status = status
        self.agentName = agentName
        self.projectID = projectID
        self.statusLine = statusLine
        self.reply = reply
        self.replyAt = replyAt
        self.toYou = toYou
        self.queued = queued
        self.asks = asks
        planFrame = PlanFrame(status: status, versionID: planVersion, artifactID: planArtifact, approval: approval)
        self.turns = turns
        self.permission = permission
    }

    /// The first root question, when it is readable. A first one that isn't
    /// is not passed over for a later one.
    var question: Ask? {
        asks.first ?? nil
    }

    // MARK: Checking what the page sent

    init?(object: Any?) {
        guard let root = object as? [String: Any],
              let status = Pick.string(root["status"]), Self.knownStatuses.contains(status),
              let agentName = Pick.optionalText(root["agentName"], limit: Limit.name),
              let projectID = Pick.optionalText(root["projectId"], limit: Limit.name),
              let statusLine = Pick.optionalText(root["statusLine"], limit: Limit.statusLine),
              let reply = Pick.optionalText(root["reply"], limit: Limit.reply),
              let replyAt = Pick.optionalTime(root["replyAt"]),
              let queued = Pick.int(root["queued"]), (0...100_000).contains(queued),
              let rawNotes = root["toYou"] as? [Any], rawNotes.count <= Limit.notes,
              let rawAsks = root["asks"] as? [Any], rawAsks.count <= Limit.asks,
              let plan = root["plan"] as? [String: Any],
              let planVersion = Pick.optionalPlanID(plan["version"]),
              let planArtifact = Pick.optionalPlanID(plan["artifact"]),
              let approval = Pick.string(plan["approval"]).flatMap(Self.approval) else { return nil }
        var notes: [Note] = []
        for raw in rawNotes {
            guard let note = raw as? [String: Any], let text = Pick.text(note["text"], limit: Limit.note),
                  let at = Pick.optionalTime(note["at"]) else { return nil }
            notes.append(Note(text: text, at: at))
        }
        var asks: [Ask?] = []
        for raw in rawAsks {
            if Pick.isNull(raw) {
                asks.append(nil)
                continue
            }
            guard let ask = Self.ask(raw) else { return nil }
            asks.append(ask)
        }
        var turns: [Turn]?
        if !Pick.isNull(root["turns"]) {
            guard let rawTurns = root["turns"] as? [Any], rawTurns.count <= Limit.turns else { return nil }
            var list: [Turn] = []
            for raw in rawTurns {
                guard let turn = raw as? [String: Any],
                      let role = Pick.string(turn["role"]).flatMap(Turn.Role.init(rawValue:)),
                      let at = Pick.optionalTime(turn["at"]),
                      let text = Pick.text(turn["text"], limit: Limit.turn),
                      let intent = Self.intent(turn["intent"]), let files = Self.files(turn["files"]) else { return nil }
                list.append(Turn(role: role, at: at, text: text, intent: intent.value, files: files))
            }
            turns = list
        }
        // Phase 4 permissions: one that doesn't match is left out, not a reason to refuse the session.
        let permission = Pick.isNull(root["permission"]) ? nil : PermissionRequest(object: root["permission"])
        self.init(status: status, agentName: agentName.value, projectID: projectID.value,
                  statusLine: statusLine.value, reply: reply.value, replyAt: replyAt, toYou: notes, queued: queued,
                  asks: asks, planVersion: planVersion.value, planArtifact: planArtifact.value, approval: approval,
                  turns: turns, permission: permission)
    }

    /// A turn's intent id: absent or null is none; anything but a uuid v4 is
    /// a mismatch.
    private static func intent(_ value: Any?) -> Pick.Maybe<String>? {
        if Pick.isNull(value) { return Pick.Maybe(value: nil) }
        guard let id = Pick.string(value), RemoteActionRequest.isUUIDv4(id) else { return nil }
        return Pick.Maybe(value: id)
    }

    /// A turn's attachment ids: absent or null is none; each a lowercase
    /// uuid, at most `Limit.files`.
    private static func files(_ value: Any?) -> [String]? {
        if Pick.isNull(value) { return [] }
        guard let raw = value as? [Any], raw.count <= Limit.files else { return nil }
        var ids: [String] = []
        for item in raw {
            guard let id = Pick.string(item), PhotoAttachment.isUUID(id), id == id.lowercased() else { return nil }
            ids.append(id)
        }
        return ids
    }

    private static func approval(_ word: String) -> PlanFrame.Approval? {
        switch word {
        case "no": .no
        case "yes": .yes
        case "unclear": .unclear
        default: nil
        }
    }

    private static func ask(_ raw: Any) -> Ask? {
        guard let ask = raw as? [String: Any], let toolID = Pick.text(ask["toolId"], limit: Limit.toolID),
              let rawItems = ask["items"] as? [Any], (1...Limit.questions).contains(rawItems.count) else { return nil }
        var items: [Question] = []
        for raw in rawItems {
            guard let item = raw as? [String: Any],
                  let question = Pick.text(item["question"], limit: Limit.question),
                  !items.contains(where: { $0.question == question }),
                  let header = Pick.string(item["header"]), header.unicodeScalars.count <= Limit.header,
                  let multi = Pick.bool(item["multi"]),
                  let rawOptions = item["options"] as? [Any], rawOptions.count <= Limit.options else { return nil }
            var options: [Option] = []
            for raw in rawOptions {
                guard let option = raw as? [String: Any], let label = Pick.text(option["label"], limit: Limit.label),
                      let detail = Pick.optionalText(option["detail"], limit: Limit.detail) else { return nil }
                options.append(Option(label: label, detail: detail.value))
            }
            items.append(Question(question: question, header: header, multi: multi, options: options))
        }
        return Ask(toolID: toolID, items: items)
    }
}

/// Strict reads of parsed JSON: a value of the wrong type is a mismatch, not
/// a default. Shared by the reader and the writer.
enum Pick {
    /// A value that may be null: `.some(nil)` for null, nil for a mismatch.
    struct Maybe<T> {
        let value: T?
    }

    static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    /// A JSON string, and nothing else (a number is not one).
    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNumber) else { return nil }
        return value as? String
    }

    /// A JSON `true` or `false`, and nothing else (a 1 or a 0 is not one).
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A whole JSON number, not a boolean.
    static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) < 1e15 else { return nil }
        return Int(double)
    }

    /// A string with something in it, at most `limit` code points.
    static func text(_ value: Any?, limit: Int) -> String? {
        guard let text = string(value), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.unicodeScalars.count <= limit else { return nil }
        return text
    }

    static func optionalText(_ value: Any?, limit: Int) -> Maybe<String>? {
        if isNull(value) { return Maybe(value: nil) }
        return text(value, limit: limit).map { Maybe(value: $0) }
    }

    /// Milliseconds since 1970, between 2000 and 2100, or null.
    static func optionalTime(_ value: Any?) -> Date?? {
        if isNull(value) { return .some(nil) }
        guard let ms = int(value), (946_684_800_000...4_102_444_800_000).contains(ms) else { return nil }
        return .some(Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    static func optionalPlanID(_ value: Any?) -> Maybe<String>? {
        if isNull(value) { return Maybe(value: nil) }
        guard let id = string(value), PlanCheck.isVersionID(id) else { return nil }
        return Maybe(value: id)
    }
}

// MARK: Reading through the page

extension WebContainer {
    /// One session's projection, read through the page (`SessionReaderScript`):
    /// the shallow frame, and with `turns` its last 12 messages too. Nil when
    /// it can't be read or doesn't match; throws when the page isn't up or the
    /// id isn't a full frame id.
    func readSession(_ frameID: String, turns: Bool) async throws -> SessionProjection? {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID) else { throw WebAPIError.notAllowed }
        let value = try await webView.callAsyncJavaScript(
            SessionReaderScript.body, arguments: ["frameId": frameID, "withTurns": turns],
            in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        switch SessionReaderScript.outcome(of: Data(text.utf8)) {
        case .read(let projection):
            return projection
        case .unreadable:
            return nil
        case .lost:
            // Refused: the page's session didn't take. Sign in again.
            sessionLost()
            return nil
        }
    }
}
