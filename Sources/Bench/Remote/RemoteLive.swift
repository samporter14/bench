// RemoteLive.swift — a working session's text as it is written (DESIGN.md,
// Bench on your phone → Phase 4: Live text). `GET /api/sessions/<id>/live`
// answers `{"working", "text", "activity"}`.
//
// As the session reader does, the page makes the GETs itself and hands Swift
// only what the route needs: whether the root is `processing`, the current
// model call's `text` (never `thinking`, never `tool_stdout`) cut to its last
// 4,000 characters, and an activity line chosen from a fixed list of the UI's
// own words. The activity is worked out from the pending requests of the root
// and its helpers and from the last assistant message's unresolved tool
// *names*, and only the word for their class leaves the page: not a tool's
// name, not its input.
//
// The scripts are plain JavaScript; the tests run these very strings in
// JavaScriptCore against a fake `fetch`. Swift checks every answer again
// (`LiveRead`). Nothing read is logged or saved.
import Foundation
import WebKit

// MARK: The script

enum LiveScript {
    /// The words the activity line may be (Claude Science's own, from its
    /// working indicator), the only strings that leave the page about what
    /// the session is doing.
    enum Activity {
        static let approval = "Waiting for your approval"
        static let executing = "Executing code"
        static let waiting = "Waiting on subagents"
        static let tool = "Running a tool"
        static let working = "Working"

        static let all: Set<String> = [approval, executing, waiting, tool, working]
    }

    /// The most of the text kept: the last 4,000 characters.
    static let textLimit = 4_000

    /// `benchLiveText(raw)` → `{ok, text}`: the streaming buffer's `text`
    /// only, the last 4,000 characters, null when there is none; `ok` false
    /// when the shape isn't the daemon's (`null`, or an object with a string
    /// `text`, a string `thinking` and an array `tool_stdout`). Pure.
    static let text = #"""
    function benchLiveText(raw) {
        "use strict";
        if (raw === null) { return { ok: true, text: null }; }
        if (typeof raw !== "object" || Array.isArray(raw)) { return { ok: false, text: null }; }
        if (typeof raw.text !== "string" || typeof raw.thinking !== "string" || !Array.isArray(raw.tool_stdout)) {
            return { ok: false, text: null };
        }
        // The last 4,000 code points: the buffer is the current call's, and the
        // end of it is what is being written.
        const all = Array.from(raw.text);
        const tail = all.length > 4000 ? all.slice(all.length - 4000).join("") : raw.text;
        return { ok: true, text: tail.trim() === "" ? null : tail };
    }
    """#

    /// `benchPendingTools(rows)` → the names of the tool calls the last
    /// assistant message made that have no result yet, as Claude Science's own
    /// working indicator counts them: a user row that is only tool results (or
    /// a marker row) doesn't end the walk, a visible user row does. Pure.
    static let tools = #"""
    function benchPendingTools(rows) {
        "use strict";
        if (!Array.isArray(rows)) { return []; }
        const FLAGS = ["_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent", "_from_aside",
                       "_harness_notice"];
        const MARKERS = ["[System]", "[compute]", "[Memory]", "[Auditor]", "[image:", "[document:",
                         "You are reviewing work an agent did in frame "];
        const isResult = block => benchIsObject(block) && block.type === "tool_result";
        const marked = text => MARKERS.some(marker => text.startsWith(marker));
        // A user row the UI doesn't count as the user speaking.
        const hidden = row => {
            if (FLAGS.some(flag => Boolean(row[flag]))) { return true; }
            const content = row.content;
            if (typeof content === "string") { return marked(content); }
            if (!Array.isArray(content)) { return false; }
            if (content.length === 0 || content.every(isResult)) { return true; }
            const texts = content.filter(block => benchIsObject(block) && block.type === "text"
                                         && typeof block.text === "string").map(block => block.text);
            return texts.length > 0 && texts.length === content.length && texts.every(marked);
        };
        const resolved = new Set();
        for (const row of rows) {
            if (benchIsObject(row) && row.role === "user" && Array.isArray(row.content)) {
                for (const block of row.content) {
                    if (isResult(block) && typeof block.tool_use_id === "string") { resolved.add(block.tool_use_id); }
                }
            }
        }
        for (let i = rows.length - 1; i >= 0; i--) {
            const row = rows[i];
            if (!benchIsObject(row)) { continue; }
            if (row.role === "user" && !hidden(row)) { return []; }
            // Too big for the daemon to send: nothing to read.
            if (row.role !== "assistant" || !Array.isArray(row.content) || !benchIsAbsent(row._oversized_bytes)) { continue; }
            const names = [];
            for (const block of row.content) {
                if (benchIsObject(block) && block.type === "tool_use" && typeof block.name === "string"
                    && !resolved.has(block.id)) { names.push(block.name); }
            }
            if (names.length > 0) { return names; }
        }
        return [];
    }
    """#

    /// `benchLiveActivity(working, pending, rows)` → one of the five words, or
    /// null when the root isn't working. The UI's own order: a pending request
    /// first; then, from the unresolved tool names (names only), "Waiting on
    /// subagents" when every one is a wait (`delegate`,
    /// `wait_for_notification`), "Executing code" when any runs code (`bash`,
    /// `powershell`, `python`, `r`), "Running a tool" for any other that
    /// isn't a meta tool; else "Working". Pure.
    static let activity = #"""
    function benchLiveActivity(working, pending, rows) {
        "use strict";
        if (working !== true) { return null; }
        if (pending === true) { return "Waiting for your approval"; }
        const META = ["boundary", "request_review", "send_user_message", "update_step_status"];
        const WAIT = ["delegate", "wait_for_notification"];
        const CODE = ["bash", "powershell", "python", "r"];
        const names = benchPendingTools(rows).filter(name => META.indexOf(name) < 0);
        if (names.length === 0) { return "Working"; }
        if (names.every(name => WAIT.indexOf(name) >= 0)) { return "Waiting on subagents"; }
        if (names.some(name => CODE.indexOf(name) >= 0)) { return "Executing code"; }
        return "Running a tool";
    }
    """#

    /// The projections together, with what they share.
    static let projections = PermissionScript.helpers + "\n" + PermissionScript.paths + "\n" + PermissionScript.queue
        + "\n" + text + "\n" + tools + "\n" + activity

    /// What `callAsyncJavaScript` runs, with the arguments `frameId`,
    /// `wantActivity`, `wantText` and `mayWait`: the shallow frame, then (when
    /// the root is `processing`) the streaming buffer, and when the activity is
    /// wanted its pending requests and the last messages. The root's requests
    /// are in its shallow frame; the helpers' come through `trace-shallow` (up
    /// to 2,000 frames), read only while a helper may hold one: `mayWait`
    /// (Bench's own database read says the session waits on the user, which
    /// counts a visible helper's request), or the root has an open call that
    /// waits on helpers (a hidden helper's request shows nowhere else; a helper
    /// asks inside the root's open `delegate` call). Answers a JSON string:
    /// `{"outcome":"read","live":{…}}`, `"unreadable"`, `"lost"` (a 401) or
    /// `"refused"` (an id that isn't one).
    static let body = projections + #"""

    if (typeof frameId !== "string" || !/^[0-9a-f-]{36}$/.test(frameId)) { return JSON.stringify({ outcome: "refused" }); }
    // A Bool through `callAsyncJavaScript` may arrive as a 1 (as the session reader's `withTurns` may).
    const needText = wantText === true || wantText === 1;
    const needActivity = wantActivity === true || wantActivity === 1;
    const signal = () => typeof AbortSignal === "function" && typeof AbortSignal.timeout === "function"
        ? AbortSignal.timeout(8000) : undefined;
    // no-store: nothing read here stays in WebKit's cache.
    const fetchRaw = async path => {
        let response;
        try {
            response = await fetch(path, { credentials: "include", cache: "no-store",
                                           headers: { "Accept": "application/json" }, signal: signal() });
        } catch (e) { return { failed: true }; }
        if (response.status === 401) { return { lost: true }; }
        let body = "";
        try { body = await response.text(); } catch (e) { return { failed: true }; }
        return { status: response.status, ok: response.ok, body: body };
    };
    const getJSON = async path => {
        const raw = await fetchRaw(path);
        if (raw.lost || raw.failed) { return raw; }
        if (!raw.ok) { return { failed: true }; }
        try { return { json: JSON.parse(raw.body) }; } catch (e) { return { failed: true }; }
    };
    const frame = await getJSON("/api/frames/" + frameId + "?shallow=true");
    if (frame.lost) { return JSON.stringify({ outcome: "lost" }); }
    if (frame.failed || !benchIsObject(frame.json) || typeof frame.json.status !== "string") {
        return JSON.stringify({ outcome: "unreadable" });
    }
    const working = frame.json.status === "processing";
    const live = { working: working, text: null, activity: null, streaming: "skipped" };
    if (!working) { return JSON.stringify({ outcome: "read", live: live }); }

    if (needText) {
        const path = benchReadPath("streaming", frameId);
        const raw = path === null ? { failed: true } : await fetchRaw(path);
        if (raw.lost) { return JSON.stringify({ outcome: "lost" }); }
        if (raw.failed) {
            live.streaming = "failed";
        } else if (raw.ok) {
            let json;
            try { json = JSON.parse(raw.body); } catch (e) { json = undefined; }
            const projected = json === undefined ? { ok: false, text: null } : benchLiveText(json);
            live.streaming = projected.ok ? "ok" : "off";
            live.text = projected.text;
        } else if (raw.status >= 400 && raw.status < 500 && raw.status !== 408 && raw.status !== 429) {
            // Not there (404, 405) or refused in a way Bench doesn't know: off for this daemon.
            live.streaming = "off";
        } else {
            live.streaming = "failed";
        }
    }

    if (needActivity) {
        // A pending request, in the root or under it. The root's are in its
        // frame. The helpers' come through `trace-shallow` (up to 2,000
        // frames), read only while a helper may hold one: Bench's own reading
        // says the session waits (`mayWait`), or the root has an open call
        // that waits on helpers (`delegate`, `wait_for_notification`).
        const rootOnly = { id: frameId, children: [] };
        let queue = benchPendingQueue(frame.json, rootOnly, frameId);
        let pending = queue !== null && queue.length > 0;
        let traced = false;
        const readHelpers = async () => {
            traced = true;
            const tracePath = benchReadPath("trace", frameId);
            const read = tracePath === null ? { failed: true } : await getJSON(tracePath);
            if (read.lost) { return false; }
            if (!read.failed) {
                const all = benchPendingQueue(frame.json, read.json, frameId);
                if (all !== null) { queue = all; pending = all.length > 0; }
            }
            return true;
        };
        const helpersMayAsk = typeof mayWait !== "undefined" && (mayWait === true || mayWait === 1);
        if (!pending && helpersMayAsk && !(await readHelpers())) { return JSON.stringify({ outcome: "lost" }); }
        let rows = null;
        if (!pending) {
            const messages = await getJSON("/api/frames/" + frameId + "/messages?from=-12&limit=12");
            if (messages.lost) { return JSON.stringify({ outcome: "lost" }); }
            if (!messages.failed && benchIsObject(messages.json) && Array.isArray(messages.json.messages)) {
                rows = messages.json.messages;
            }
            const WAIT = ["delegate", "wait_for_notification"];
            if (!traced && benchPendingTools(rows).some(name => WAIT.indexOf(name) >= 0)
                && !(await readHelpers())) { return JSON.stringify({ outcome: "lost" }); }
        }
        live.activity = benchLiveActivity(true, pending, rows);
    }
    return JSON.stringify({ outcome: "read", live: live });
    """#

    /// What the page said.
    enum Outcome: Equatable {
        case read(LiveRead)
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
        case "read": return LiveRead(object: root["live"]).map(Outcome.read) ?? .unreadable
        default: return .unreadable
        }
    }
}

// MARK: What Swift receives

/// One live read as the page projected it, every field checked again.
struct LiveRead: Equatable, Sendable {
    /// How the streaming read went: `off` (the daemon has no such route, or
    /// answers something Bench doesn't know) is remembered for a while.
    enum Streaming: String, Sendable {
        case ok, off, failed, skipped
    }

    /// The root is `processing`.
    let working: Bool
    /// The current call's text, its last 4,000 characters.
    let text: String?
    /// One of `LiveScript.Activity.all`, when asked for.
    let activity: String?
    let streaming: Streaming

    init(working: Bool, text: String? = nil, activity: String? = nil, streaming: Streaming = .ok) {
        self.working = working
        self.text = text
        self.activity = activity
        self.streaming = streaming
    }

    init?(object: Any?) {
        guard let root = object as? [String: Any], let working = Pick.bool(root["working"]),
              let text = Pick.optionalText(root["text"], limit: LiveScript.textLimit),
              let activity = Pick.optionalText(root["activity"], limit: 40),
              activity.value == nil || LiveScript.Activity.all.contains(activity.value ?? ""),
              let streaming = Pick.string(root["streaming"]).flatMap(Streaming.init(rawValue:)) else { return nil }
        self.init(working: working, text: text.value, activity: activity.value, streaming: streaming)
    }
}

// MARK: What the phone is told

extension RemoteAPI {
    /// `GET /api/sessions/<id>/live`: `{"working", "text", "activity"}`.
    struct Live: Encodable, Equatable {
        let working: Bool
        let text: String?
        let activity: String?

        private enum CodingKeys: String, CodingKey { case working, text, activity }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(working, forKey: .working)
            try c.encode(text, forKey: .text)
            try c.encode(activity, forKey: .activity)
        }
    }
}

// MARK: Keeping what the route needs between asks

/// The live route's own state: the activity line is worked out from the
/// pending requests and the last messages, which is more than a poll every
/// 1.5 s should read, so it is kept 4 seconds and the text alone is read in
/// between. A daemon without the streaming route is left alone for 10 minutes.
@MainActor
final class RemoteLive {
    /// The page's read: the session's id, whether its activity is wanted,
    /// whether its text is, and whether Bench's own reading says the session
    /// waits on the user (so its helpers' requests are worth reading). Nil
    /// when it can't be read.
    typealias Reader = @MainActor (_ id: String, _ activity: Bool, _ text: Bool, _ mayWait: Bool) async -> LiveRead?

    static let activityLifetime: TimeInterval = 4
    static let streamingRetry: TimeInterval = 10 * 60
    static let kept = 64

    private let read: Reader
    private let now: @MainActor () -> Date
    private let known: @MainActor () -> [SessionStatus]
    private var activities: [String: (activity: String?, at: Date)] = [:]
    private var streamingOffUntil: Date?
    private var reading: [String: Task<RemoteAPI.Live, Never>] = [:]

    init(read: @escaping Reader, now: @escaping @MainActor () -> Date,
         known: @escaping @MainActor () -> [SessionStatus] = { [] }) {
        self.read = read
        self.now = now
        self.known = known
    }

    /// The JSON for a session the phone may open. A read that fails answers
    /// from what Bench knows of the session: working or not, nothing more.
    func json(_ id: String, extra: [SessionStatus]) async -> Data {
        if let task = reading[id] { return RemoteAPI.encode(await task.value) }
        let task = Task { [weak self] () -> RemoteAPI.Live in
            guard let self else { return RemoteAPI.Live(working: false, text: nil, activity: nil) }
            let live = await self.compose(id, extra: extra)
            self.reading[id] = nil
            return live
        }
        reading[id] = task
        return RemoteAPI.encode(await task.value)
    }

    private func compose(_ id: String, extra: [SessionStatus]) async -> RemoteAPI.Live {
        let moment = now()
        let cached = activities[id]
        let fresh = cached.map { $0.at <= moment && moment.timeIntervalSince($0.at) < Self.activityLifetime } ?? false
        let wantText = streamingOffUntil.map { moment >= $0 } ?? true
        // Bench's own reading counts a helper's request: the root's frame
        // alone doesn't show one.
        let benchsOwn = (known() + extra).first { $0.id == id }
        guard let read = await read(id, !fresh, wantText, benchsOwn?.state == .needsInput) else {
            return RemoteAPI.Live(working: benchsOwn?.state == .running, text: nil, activity: nil)
        }
        if read.streaming == .off { streamingOffUntil = moment.addingTimeInterval(Self.streamingRetry) }
        guard read.working else {
            activities[id] = nil
            return RemoteAPI.Live(working: false, text: nil, activity: nil)
        }
        let activity: String?
        if fresh {
            activity = cached?.activity
        } else {
            activity = read.activity
            remember(id, activity, at: moment)
        }
        // The UI's own order: a pending request first, then the text, which
        // needs no label of its own.
        let shown = read.text != nil && activity != LiveScript.Activity.approval ? nil : activity
        return RemoteAPI.Live(working: true, text: read.text, activity: shown)
    }

    private func remember(_ id: String, _ activity: String?, at moment: Date) {
        activities[id] = (activity, moment)
        guard activities.count > Self.kept else { return }
        activities = activities.filter { moment.timeIntervalSince($0.value.at) < 60 }
        while activities.count > Self.kept, let oldest = activities.min(by: { $0.value.at < $1.value.at }) {
            activities[oldest.key] = nil
        }
    }
}

extension RemoteSessions {
    /// `GET /api/sessions/<id>/live` for a session the phone may open (the
    /// same admission as the session itself); nil: 404.
    func liveJSON(_ id: String) async -> Data? {
        guard let found = await admitted(id) else { return nil }
        return await live.json(id, extra: found)
    }
}

// MARK: Reading through the page

extension WebContainer {
    /// One session's live read, through the page (`LiveScript`). Nil when it
    /// can't be read or doesn't match; throws when the page isn't up or the id
    /// isn't a full frame id.
    func readLive(_ frameID: String, activity: Bool, text: Bool, mayWait: Bool) async throws -> LiveRead? {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID) else { throw WebAPIError.notAllowed }
        let value = try await webView.callAsyncJavaScript(
            LiveScript.body, arguments: ["frameId": frameID, "wantActivity": activity, "wantText": text, "mayWait": mayWait],
            in: nil, contentWorld: .defaultClient)
        guard let reply = value as? String else { throw WebAPIError.badResponse }
        switch LiveScript.outcome(of: Data(reply.utf8)) {
        case .read(let read):
            return read
        case .unreadable:
            return nil
        case .lost:
            // Refused: the page's session didn't take. Sign in again.
            sessionLost()
            return nil
        }
    }
}
