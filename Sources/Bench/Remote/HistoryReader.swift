// HistoryReader.swift — a session's whole conversation for the phone, a page
// at a time (DESIGN.md, Capsid on your phone → Phase 3: History). Like the
// session reader, the page runs the GETs and *projects* them itself, so Swift
// only ever receives the items below: the user's and Claude's text turns, one
// line for each run of tool calls in the UI's own group phrases, a plan's step
// count, a question and its answer, the agent's messages to the user, a mark
// where a helper agent was asked, and the files a turn made (version id, name,
// content type, size). Never thinking, tool input or results beyond those,
// images, paths or hidden rows.
//
// The projection is plain JavaScript with no fetch and no DOM, so the tests
// run the very same strings in JavaScriptCore on made-up pages. Swift checks
// every field again (`HistoryPage`); anything that doesn't match is
// unreadable. What is read lives in memory only, while the answer is built.
//
// Keep (since 1.0) adds one more op beside these, on the same allowlisted GET:
// `benchFindShowingMessage` finds the assistant message that shows a figure
// (`ShowingRead`, below). It keeps the message's index, time and text and which
// of four ways it matched, and nothing else: never tool input, results beyond
// `artifacts[]`, thinking or images.
import Foundation
import WebKit

// MARK: The script

enum HistoryReaderScript {
    /// At most this many items, and this many bytes of JSON, a page.
    static let maxItems = 60
    static let maxBytes = 64 * 1024
    /// Rows a page covers.
    static let pageRows = 50
    /// A turn's text on a page; `turn` sends a cut one whole, up to `wholeTurn`.
    static let turnText = 2_000
    static let wholeTurn = 20_000
    /// The highest row index a path may name (`\d{1,7}`).
    static let maxIndex = 9_999_999

    /// The daemon GETs the reader may make, exactly:
    /// `^/frames/<36>/messages\?from=\d{1,7}&limit=([1-9]|[1-4]\d|50)$`, and
    /// the session reader's `from=-12&limit=12`. Under `/api`. The page checks
    /// the same before every fetch.
    static func isAllowedPath(_ path: String) -> Bool {
        let head = "/api/frames/", middle = "/messages?"
        guard path.hasPrefix(head) else { return false }
        let rest = path.dropFirst(head.count)
        guard rest.count > 36 else { return false }
        let id = rest.prefix(36)
        guard PlanCheck.isFrameID(String(id)), rest.dropFirst(36).hasPrefix(middle) else { return false }
        let query = rest.dropFirst(36 + middle.count)
        if query == "from=-12&limit=12" { return true }
        let pairs = query.split(separator: "&", omittingEmptySubsequences: false)
        guard pairs.count == 2, pairs[0].hasPrefix("from="), pairs[1].hasPrefix("limit=") else { return false }
        let from = pairs[0].dropFirst(5).utf8, limit = Array(pairs[1].dropFirst(6).utf8)
        let digit: (UInt8) -> Bool = { (0x30...0x39).contains($0) }
        guard (1...7).contains(from.count), from.allSatisfy(digit) else { return false }
        switch limit.count {
        case 1: return (0x31...0x39).contains(limit[0])
        case 2: return limit == Array("50".utf8) || ((0x31...0x34).contains(limit[0]) && digit(limit[1]))
        default: return false
        }
    }

    /// `benchProjectHistory(page, base)`: `{total, from, items}`, or null when
    /// a shape doesn't match. `page` is `{total, messages}` whose first message
    /// is row `base`. Pure: no fetch, no DOM, no globals.
    static let projection = #"""
    function benchProjectHistory(page, base) {
        "use strict";
        const MAX_ITEMS = 60, MAX_BYTES = 65536, TEXT = 2000, LINE = 300, NAME = 255, FILES = 20;
        // User rows Claude Science's own UI hides.
        const HIDDEN_FLAGS = ["_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent",
                              "_from_aside", "_harness_notice"];
        const HIDDEN_STARTS = ["[System]", "[compute]", "[Memory]", "[image:", "[document:"];
        // A version or artifact id fit for a path, as PlanCheck.isVersionID.
        const ID = /^[A-Za-z0-9_-]{1,128}$/;
        const EARLIEST = 946684800000, LATEST = 4102444800000;
        // The UI's step groups: a tool's name says which, and nothing of its input is read.
        const GROUPS = {
            bash: "run", powershell: "run", python: "run", r: "run", repl: "run", operon: "run",
            compute_provider: "run", code_execution: "run",
            read_file: "read", read_artifact_lineage: "read",
            web_search: "search", search_skills: "search", tool_search_tool_regex: "search",
            web_fetch: "fetch", fetch_article_fulltext: "fetch",
            save_artifacts: "save", edit_file: "edit", write_file: "edit", skill: "skill",
            manage_environments: "env", manage_packages: "env",
        };
        const PHRASES = {
            run: ["ran a command", "ran {n} commands"], read: ["read a file", "read {n} files"],
            search: ["ran a search", "ran {n} searches"], fetch: ["fetched a page", "fetched {n} pages"],
            save: ["saved artifacts", "saved artifacts"], edit: ["edited a file", "edited {n} files"],
            skill: ["loaded a skill", "loaded {n} skills"], env: ["set up an environment", "set up {n} environments"],
            other: ["made a call", "made {n} calls"],
        };
        // Tools whose results list the files they made.
        const MAKES_FILES = ["run", "save"];
        const HELPERS = ["explore_data", "execute_claude_code", "send_message"];
        const SKIPPED = ["wait_for_notification", "update_step_status", "request_review", "boundary"];

        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const isAbsent = v => v === undefined || v === null;
        const cut = (text, limit) => {
            const all = Array.from(text);
            return all.length <= limit ? text : all.slice(0, limit - 1).join("") + "…";
        };
        const line = (v, limit) => {
            if (typeof v !== "string") { return null; }
            const one = v.split(/\s+/).filter(Boolean).join(" ");
            return one ? cut(one, limit) : null;
        };
        const time = v => {
            let ms = null;
            if (typeof v === "number" && isFinite(v)) { ms = v < 1e11 ? v * 1000 : v; }
            else if (typeof v === "string") { const parsed = Date.parse(v); if (isFinite(parsed)) { ms = parsed; } }
            return ms !== null && ms >= EARLIEST && ms <= LATEST ? Math.round(ms) : null;
        };
        // UTF-8 bytes, counted by hand: JavaScriptCore has no TextEncoder.
        const bytes = text => {
            let n = 0;
            for (const ch of text) { const c = ch.codePointAt(0); n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4; }
            return n;
        };
        // A file's own name: the last part of whatever path it came with.
        const fileName = v => {
            if (typeof v !== "string") { return null; }
            const last = v.split(/[\\/]/).pop().trim();
            return last ? cut(last, NAME) : null;
        };
        const file = (v, a, name, mime, size) => {
            if (typeof v !== "string" || !ID.test(v)) { return null; }
            const named = fileName(name);
            if (named === null) { return null; }
            return {
                v: v,
                a: typeof a === "string" && ID.test(a) ? a : null,
                name: named,
                mime: typeof mime === "string" && mime.length <= 100 ? mime : null,
                size: typeof size === "number" && isFinite(size) && size >= 0 && size < 1e15 ? Math.round(size) : null,
            };
        };
        // `{artifact_id, version_id, filename, content_type, size_bytes}` items.
        const listed = list => {
            const out = [];
            if (!Array.isArray(list)) { return out; }
            for (const f of list.slice(0, 50)) {
                if (!isObject(f)) { continue; }
                const one = file(f.version_id, f.artifact_id, f.filename, f.content_type, f.size_bytes);
                if (one !== null) { out.push(one); }
            }
            return out;
        };
        // A message's attachment lines (Claude Science's own upload format, one
        // JSON object per line: `{"type":"attachment","id","version_id","filename",…}`)
        // become files; the rest is the message's text.
        const attached = raw => {
            const kept = [], found = [];
            for (const line of raw.split("\n")) {
                const t = line.trim();
                if (t.startsWith('{"type":"attachment"') && t.length <= 2000) {
                    let o = null;
                    try { o = JSON.parse(t); } catch (e) { o = null; }
                    if (isObject(o) && o.type === "attachment") {
                        const one = file(o.version_id, o.id, o.filename, o.content_type, o.size_bytes);
                        if (one !== null) { found.push(one); continue; }
                    }
                }
                kept.push(line);
            }
            return { rest: kept.join("\n").trim(), found: found.slice(0, 10) };
        };
        // A tool result as JSON: its text, parsed, when it is an object of reasonable size.
        const resultJSON = content => {
            let text = null;
            if (typeof content === "string") { text = content; }
            else if (Array.isArray(content)) {
                const parts = [];
                for (const block of content) {
                    if (isObject(block) && block.type === "text" && typeof block.text === "string") { parts.push(block.text); }
                }
                text = parts.join("");
            } else if (isObject(content)) { return content; }
            if (text === null || text.length > 524288) { return null; }
            try { const parsed = JSON.parse(text); return isObject(parsed) ? parsed : null; } catch (e) { return null; }
        };
        const answerText = answers => {
            if (!isObject(answers)) { return null; }
            const parts = [];
            for (const key of Object.keys(answers)) {
                const value = answers[key];
                if (typeof value === "string") { parts.push(value); }
                else if (Array.isArray(value)) { parts.push(value.filter(x => typeof x === "string").join(", ")); }
            }
            return line(parts.filter(Boolean).join("; "), LINE);
        };

        if (!isObject(page) || typeof page.total !== "number" || !Array.isArray(page.messages)
            || typeof base !== "number" || base < 0) { return null; }

        const items = [];
        const calls = {};
        const pools = [];
        let fold = null;
        let turn = 0;
        const pool = t => { if (!pools[t]) { pools[t] = []; } return pools[t]; };
        const add = item => { fold = null; item.turn = turn; items.push(item); return item; };
        const step = (group, i) => {
            if (fold === null) {
                fold = { i: i, kind: "steps", counts: {}, order: [], failed: false, turn: turn };
                items.push(fold);
            }
            if (!(group in fold.counts)) { fold.counts[group] = 0; fold.order.push(group); }
            fold.counts[group] += 1;
            return fold;
        };
        const text = (role, i, at, joined) => {
            const all = Array.from(joined);
            return add({ i: i, role: role, at: at, text: cut(joined, TEXT), cut: all.length > TEXT, files: [] });
        };

        const call = (block, i) => {
            if (typeof block.name !== "string") { return false; }
            const name = block.name.toLowerCase();
            const id = typeof block.id === "string" ? block.id : null;
            const input = isObject(block.input) ? block.input : {};
            let entry = { name: name, turn: turn };
            if (SKIPPED.indexOf(name) >= 0) {
                // Bookkeeping the UI hides.
            } else if (name === "generate_plan") {
                const steps = Array.isArray(input.steps) ? input.steps.length
                    : isObject(input.plan) && Array.isArray(input.plan.steps) ? input.plan.steps.length : null;
                add({ i: i, kind: "plan", steps: steps });
            } else if (name === "ask_user") {
                let q = typeof input.question === "string" ? input.question : null;
                if (q === null && Array.isArray(input.questions) && isObject(input.questions[0])) { q = input.questions[0].question; }
                entry.item = add({ i: i, kind: "ask", q: line(q, LINE), a: null });
            } else if (name === "send_user_message") {
                const message = typeof input.message === "string" ? input.message.trim() : "";
                entry.item = add({ i: i, kind: "toYou", text: cut(message, TEXT), files: [] });
            } else if (name.startsWith("delegate") || HELPERS.indexOf(name) >= 0) {
                add({ i: i, kind: "helper" });
            } else {
                entry.group = GROUPS[name] || "other";
                entry.fold = step(entry.group, i);
            }
            if (id !== null) { calls[id] = entry; }
            return true;
        };

        const result = block => {
            const entry = typeof block.tool_use_id === "string" ? calls[block.tool_use_id] : undefined;
            if (entry === undefined) { return; }
            if (block.is_error === true && entry.fold) { entry.fold.failed = true; }
            if (entry.name === "ask_user" && entry.item) {
                const r = resultJSON(block.content);
                if (r !== null && r.status === "answered") { entry.item.a = answerText(r.answers); }
            } else if (entry.name === "send_user_message" && entry.item) {
                const r = resultJSON(block.content);
                if (r !== null) { entry.item.files.push(...listed(r.attachments)); }
            } else if (MAKES_FILES.indexOf(entry.group) >= 0 && block.is_error !== true) {
                const r = resultJSON(block.content);
                if (r !== null) { pool(entry.turn).push(...listed(r.artifacts)); }
            }
        };

        for (let k = 0; k < page.messages.length; k++) {
            const i = base + k, m = page.messages[k];
            if (!isObject(m)) { return null; }
            if (m.role !== "user" && m.role !== "assistant") { continue; }
            let blocks;
            if (typeof m.content === "string") { blocks = [{ type: "text", text: m.content }]; }
            else if (Array.isArray(m.content)) { blocks = m.content; }
            else { return null; }
            for (const block of blocks) {
                if (!isObject(block) || typeof block.type !== "string") { return null; }
                if (block.type === "text" && typeof block.text !== "string") { return null; }
            }
            // Too big for the daemon to send: a placeholder.
            if (!isAbsent(m._oversized_bytes)) { continue; }
            const at = time(m._ts);
            if (m.role === "user") {
                if (HIDDEN_FLAGS.some(flag => Boolean(m[flag]))) { continue; }
                for (const block of blocks) { if (block.type === "tool_result") { result(block); } }
                const joined = blocks.filter(b => b.type === "text").map(b => b.text).join("\n\n").trim();
                if (joined !== "" && !HIDDEN_STARTS.some(start => joined.startsWith(start))) {
                    const { rest, found } = attached(joined);
                    // Notes the daemon adds inside a message ("[System] Attached file: …") stay hidden.
                    const own = rest.split("\n").filter(l => !HIDDEN_STARTS.some(s => l.trim().startsWith(s))).join("\n").trim();
                    turn += 1;
                    const item = text("you", i, at, own);
                    if (item !== null && found.length > 0) { item.files.push(...found); }
                }
            } else {
                let texts = [];
                const say = () => {
                    const joined = texts.join("\n\n").trim();
                    texts = [];
                    if (joined !== "") { text("claude", i, at, joined); }
                };
                for (const block of blocks) {
                    if (block.type === "text") { texts.push(block.text); }
                    else if (block.type === "tool_use" || block.type === "server_tool_use") {
                        say();
                        if (!call(block, i)) { return null; }
                    }
                    // Thinking, images and inline results: never read.
                }
                say();
                // `{"<filename>": {artifact_id, version_id}}`: the turn's files.
                const refs = m._artifact_refs;
                if (isObject(refs)) {
                    for (const name of Object.keys(refs).slice(0, 50)) {
                        const ref = refs[name];
                        if (!isObject(ref)) { continue; }
                        const one = file(ref.version_id, ref.artifact_id, name, null, null);
                        if (one !== null) { pool(turn).push(one); }
                    }
                }
            }
        }

        // A turn's files go under its last reply (the UI's tray), else its
        // last line of steps.
        for (let t = 0; t < pools.length; t++) {
            if (!pools[t] || pools[t].length === 0) { continue; }
            const mine = items.filter(item => item.turn === t);
            const target = mine.filter(item => item.role === "claude").pop() || mine.filter(item => item.kind === "steps").pop();
            if (target) {
                target.files = target.files || [];
                target.files.push(...pools[t]);
            }
        }

        const phrase = (group, n) => {
            const forms = PHRASES[group] || PHRASES.other;
            return n === 1 ? forms[0] : forms[1].replace("{n}", String(n));
        };
        const out = items.map(item => {
            let files = null;
            if (Array.isArray(item.files)) {
                const seen = new Set();
                files = [];
                for (const f of item.files) {
                    if (seen.has(f.v) || files.length >= FILES) { continue; }
                    seen.add(f.v);
                    files.push(f);
                }
            }
            if (item.kind === "steps") {
                const groups = item.order.slice().sort((x, y) => item.counts[y] - item.counts[x] || item.order.indexOf(x) - item.order.indexOf(y));
                let words = groups.slice(0, 3).map(g => phrase(g, item.counts[g])).join(", ");
                if (groups.length > 3) { words += " +" + (groups.length - 3) + " more"; }
                words = words.charAt(0).toUpperCase() + words.slice(1);
                const steps = { i: item.i, kind: "steps", line: words, failed: item.failed };
                if (files && files.length > 0) { steps.files = files; }
                return steps;
            }
            if (item.role) {
                return { i: item.i, role: item.role, at: item.at, text: item.text, cut: item.cut, files: files || [] };
            }
            if (item.kind === "plan") { return { i: item.i, kind: "plan", steps: item.steps }; }
            if (item.kind === "ask") { return { i: item.i, kind: "ask", q: item.q, a: item.a }; }
            if (item.kind === "toYou") { return { i: item.i, kind: "toYou", text: item.text, files: files || [] }; }
            return { i: item.i, kind: "helper" };
        });

        // At most 60 items and 64 KB: the oldest rows go whole, and `from`
        // moves up to the first row kept, so the next page starts there.
        let start = 0;
        const size = () => bytes(JSON.stringify(out.slice(start)));
        while (start < out.length && (out.length - start > MAX_ITEMS || size() > MAX_BYTES)) {
            const row = out[start].i;
            let next = start;
            while (next < out.length && out[next].i === row) { next += 1; }
            if (next >= out.length) { break; }
            start = next;
        }
        const kept = out.slice(start);
        return { total: page.total, from: start === 0 ? base : kept[0].i, items: kept };
    }
    """#

    /// `benchProjectTurn(page, index)`: one row's text whole (≤ 20,000), as
    /// `{i, role, at, text}`; null when the row is no turn the history shows.
    static let turnProjection = #"""
    function benchProjectTurn(page, index) {
        "use strict";
        const HIDDEN_FLAGS = ["_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent",
                              "_from_aside", "_harness_notice"];
        const HIDDEN_STARTS = ["[System]", "[compute]", "[Memory]", "[image:", "[document:"];
        const EARLIEST = 946684800000, LATEST = 4102444800000, WHOLE = 20000;
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        if (!isObject(page) || page.from !== index || !Array.isArray(page.messages) || page.messages.length !== 1) { return null; }
        const m = page.messages[0];
        if (!isObject(m) || (m.role !== "user" && m.role !== "assistant")) { return null; }
        if (m._oversized_bytes !== undefined && m._oversized_bytes !== null) { return null; }
        if (m.role === "user" && HIDDEN_FLAGS.some(flag => Boolean(m[flag]))) { return null; }
        let texts = [];
        if (typeof m.content === "string") { texts = [m.content]; }
        else if (Array.isArray(m.content)) {
            for (const block of m.content) {
                if (!isObject(block) || typeof block.type !== "string") { return null; }
                if (block.type === "text") {
                    if (typeof block.text !== "string") { return null; }
                    texts.push(block.text);
                }
            }
        } else { return null; }
        const joined = m.role === "assistant" ? texts.map(t => t.trim()).filter(Boolean).join("\n\n") : texts.join("\n\n").trim();
        if (joined === "") { return null; }
        if (m.role === "user" && HIDDEN_STARTS.some(start => joined.startsWith(start))) { return null; }
        // Attachment lines (the upload format) are shown as files in the page, not as text.
        const plain = joined.split("\n").filter(line => {
            const t = line.trim();
            if (!t.startsWith('{"type":"attachment"')) { return true; }
            try { const o = JSON.parse(t); return !(isObject(o) && o.type === "attachment"); } catch (e) { return true; }
        }).filter(line => m.role !== "user" || !HIDDEN_STARTS.some(s => line.trim().startsWith(s))).join("\n").trim();
        let at = null;
        if (typeof m._ts === "number" && isFinite(m._ts)) {
            const ms = m._ts < 1e11 ? m._ts * 1000 : m._ts;
            if (ms >= EARLIEST && ms <= LATEST) { at = Math.round(ms); }
        }
        const all = Array.from(plain);
        const text = all.length <= WHOLE ? plain : all.slice(0, WHOLE - 1).join("") + "…";
        return { i: index, role: m.role === "user" ? "you" : "claude", at: at, text: text };
    }
    """#

    /// The page's own fetch: only paths `isAllowedPath` allows, `no-store`,
    /// 15 s each. Answers `{json}`, `{lost}` (401) or `{failed}`. `get(path,
    /// stop)` takes an optional AbortController too (Keep's showing read files
    /// one under its nonce, so `benchAbortRead` can end the fetch); without
    /// one, as the phone's reads, the 15 s is the only signal.
    static let fetcher = #"""
    const ALLOWED = /^\/api\/frames\/[0-9a-f-]{36}\/messages\?(from=-12&limit=12|from=\d{1,7}&limit=([1-9]|[1-4]\d|50))$/;
    const signal = stop => {
        const limit = typeof AbortSignal === "function" && typeof AbortSignal.timeout === "function"
            ? AbortSignal.timeout(15000) : undefined;
        if (!stop) { return limit; }
        if (limit === undefined) { return stop.signal; }
        if (typeof AbortSignal.any === "function") { return AbortSignal.any([stop.signal, limit]); }
        // No AbortSignal.any: a third controller, aborted by either.
        const either = new AbortController();
        const end = () => { try { either.abort(); } catch (e) { } };
        for (const one of [stop.signal, limit]) {
            if (one.aborted) { end(); } else if (typeof one.addEventListener === "function") { one.addEventListener("abort", end); }
        }
        return either.signal;
    };
    const get = async (path, stop) => {
        if (!ALLOWED.test(path)) { return { failed: true }; }
        let response;
        try {
            response = await fetch(path, { credentials: "include", cache: "no-store",
                                           headers: { "Accept": "application/json" }, signal: signal(stop) });
        } catch (e) { return { failed: true }; }
        if (response.status === 401) { return { lost: true }; }
        if (!response.ok) { return { failed: true }; }
        try { return { json: JSON.parse(await response.text()) }; } catch (e) { return { failed: true }; }
    };
    const isPage = v => v !== null && typeof v === "object" && typeof v.from === "number" && typeof v.total === "number"
        && Array.isArray(v.messages) && Number.isInteger(v.total) && v.total >= 0;
    """#

    /// `readRows(frameId, before, knownTotal, stop)`: the rows a page covers,
    /// as `{messages, base, total}`, or `{outcome}` when the read ended
    /// early: `refused` (an id or an index out of shape; nothing fetched),
    /// `lost` (a 401), `unreadable`, or `same` (only without `before`: the
    /// history is as long as `knownTotal`). Without `before` the session
    /// reader's `from=-12&limit=12` says how many rows there are, and one more
    /// GET reads the 38 before them; with it, one GET reads the 50 before it.
    /// The history page's body and Keep's showing body share it.
    static let rowReader = #"""
    const readRows = async (frameId, before, knownTotal, stop) => {
        if (typeof frameId !== "string" || !/^[0-9a-f-]{36}$/.test(frameId)) { return { outcome: "refused" }; }
        const hasBefore = before !== null && before !== undefined;
        if (hasBefore && (typeof before !== "number" || !Number.isInteger(before) || before < 1 || before > 9999999)) {
            return { outcome: "refused" };
        }
        const path = (from, limit) => "/api/frames/" + frameId + "/messages?from=" + from + "&limit=" + limit;
        const unreadable = { outcome: "unreadable" };
        let messages, base, total;
        if (hasBefore) {
            const from = Math.max(0, before - 50), limit = before - from;
            const reply = await get(path(from, limit), stop);
            if (reply.lost) { return { outcome: "lost" }; }
            if (reply.failed || !isPage(reply.json) || reply.json.from !== from || reply.json.messages.length > limit) { return unreadable; }
            messages = reply.json.messages;
            base = from;
            total = reply.json.total;
        } else {
            const tail = await get("/api/frames/" + frameId + "/messages?from=-12&limit=12", stop);
            if (tail.lost) { return { outcome: "lost" }; }
            // The last rows: they end at `total`, whether the reply's `from` says
            // where they start or echoes the -12 it was asked for.
            if (tail.failed || !isPage(tail.json) || tail.json.messages.length > 12
                || tail.json.messages.length > tail.json.total) { return unreadable; }
            total = tail.json.total;
            base = total - tail.json.messages.length;
            if (tail.json.from !== base && tail.json.from !== -12) { return unreadable; }
            // As long as Bench already holds: no more to read, nothing to project.
            if (typeof knownTotal === "number" && Number.isInteger(knownTotal) && knownTotal === total) {
                return { outcome: "same", total: total };
            }
            messages = tail.json.messages;
            const from = Math.max(0, total - 50), limit = base - from;
            if (limit > 0) {
                const earlier = await get(path(from, limit), stop);
                if (earlier.lost) { return { outcome: "lost" }; }
                if (earlier.failed || !isPage(earlier.json) || earlier.json.from !== from
                    || earlier.json.messages.length !== limit) { return unreadable; }
                messages = earlier.json.messages.concat(messages);
                base = from;
            }
        }
        return { messages: messages, base: base, total: total };
    };
    """#

    /// What `callAsyncJavaScript` runs, with `frameId`, `before` (a row
    /// index, or null for the last page) and `knownTotal` (the row count of
    /// the last page Bench already holds, or null). Without `before`, the
    /// session reader's `from=-12&limit=12` says how many rows there are: the
    /// same as `knownTotal` answers `{"outcome":"same","total":n}` and reads
    /// nothing more; otherwise one more GET reads the 38 before them. Answers
    /// a JSON string: `{"outcome":"read","page":{…}}`, `"same"`,
    /// `"unreadable"`, `"lost"` or `"refused"`.
    static let pageBody = projection + "\n" + fetcher + "\n" + rowReader + #"""

    const rows = await readRows(frameId, before, knownTotal, null);
    if (rows.outcome !== undefined) { return JSON.stringify(rows); }
    let page = null;
    try { page = benchProjectHistory({ total: rows.total, messages: rows.messages }, rows.base); } catch (e) { page = null; }
    return page === null ? JSON.stringify({ outcome: "unreadable" }) : JSON.stringify({ outcome: "read", page: page });
    """#

    /// With `frameId` and `index`: one row, `from=<index>&limit=1`. Answers
    /// `{"outcome":"turn","turn":{…}}`, `"none"` (no turn there), `"unreadable"`,
    /// `"lost"` or `"refused"`.
    static let turnBody = turnProjection + "\n" + fetcher + #"""

    if (typeof frameId !== "string" || !/^[0-9a-f-]{36}$/.test(frameId)
        || typeof index !== "number" || !Number.isInteger(index) || index < 0 || index > 9999999) {
        return JSON.stringify({ outcome: "refused" });
    }
    const reply = await get("/api/frames/" + frameId + "/messages?from=" + index + "&limit=1");
    if (reply.lost) { return JSON.stringify({ outcome: "lost" }); }
    if (reply.failed || !isPage(reply.json)) { return JSON.stringify({ outcome: "unreadable" }); }
    if (reply.json.messages.length === 0) { return JSON.stringify({ outcome: "none" }); }
    let turn = null;
    try { turn = benchProjectTurn(reply.json, index); } catch (e) { turn = null; }
    return JSON.stringify(turn === null ? { outcome: "none" } : { outcome: "turn", turn: turn });
    """#

    /// Keep's showing op, pure: no fetch, no DOM, no globals.
    ///
    /// `benchFindShowingMessage(page, base, versionIds)`: of one page of raw
    /// rows (`page` is `{total, messages}`, its first message row `base`), the
    /// NEWEST assistant message that shows any of `versionIds` (an artifact's
    /// version ids, oldest first), as `{i, at, text, how, v}`, or null when none
    /// does. Throws when a shape doesn't match, or the ids are none (the body
    /// answers that as unreadable). `how` is the first of four ways that fits
    /// the message, in this order:
    ///   `inline`  `{{artifact:<v>}}` or `?v=<v>` in its text;
    ///   `image`   an `_artifact_refs` value for an id, whose key is the last
    ///             segment of a `![…](src)` in its text;
    ///   `mention` any `_artifact_refs` value for an id;
    ///   `saved`   a `tool_use` of a save or run tool whose result's
    ///             `artifacts[]` lists an id: the message is the next assistant
    ///             text after the result, before the user's next turn, else the
    ///             message holding the tool call itself.
    /// Each message gets its best way, and the newest message with one wins.
    /// When one message names several ids the same way, `v` is the one latest
    /// in `versionIds`. `text` is the message's text blocks joined (≤ 20,000);
    /// `at` its `_ts` in milliseconds or null. Read: text blocks, `tool_use`
    /// names and ids, a save or run result's `artifacts[].version_id`, and
    /// `_artifact_refs`. Never read: thinking, tool input, any other result,
    /// images.
    ///
    /// `benchNewestTs(messages)`: the largest `_ts` of a page, in milliseconds,
    /// or null when no row has one.
    static let showingProjection = #"""
    function benchFindShowingMessage(page, base, versionIds) {
        "use strict";
        const WHOLE = 20000, MAX_IDS = 600, MAX_REFS = 500;
        const EARLIEST = 946684800000, LATEST = 4102444800000;
        // The history's own lists: rows its UI hides, and the tools whose
        // results list the files they made (its "run" and "save" groups).
        const HIDDEN_FLAGS = ["_task_boundary", "_rolling_summary", "_harness_prompt", "_from_agent",
                              "_from_aside", "_harness_notice"];
        const HIDDEN_STARTS = ["[System]", "[compute]", "[Memory]", "[image:", "[document:"];
        const SAVERS = ["save_artifacts", "bash", "powershell", "python", "r", "repl", "operon", "compute_provider", "code_execution"];
        const ID = /^[A-Za-z0-9_-]{1,128}$/;
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const isAbsent = v => v === undefined || v === null;
        const fail = () => { throw new Error("shape"); };
        const time = v => {
            let ms = null;
            if (typeof v === "number" && isFinite(v)) { ms = v < 1e11 ? v * 1000 : v; }
            else if (typeof v === "string") { const parsed = Date.parse(v); if (isFinite(parsed)) { ms = parsed; } }
            return ms !== null && ms >= EARLIEST && ms <= LATEST ? Math.round(ms) : null;
        };
        if (!isObject(page) || !Array.isArray(page.messages) || typeof base !== "number" || !Number.isInteger(base) || base < 0) { fail(); }
        if (!Array.isArray(versionIds) || versionIds.length === 0 || versionIds.length > MAX_IDS
            || !versionIds.every(v => typeof v === "string" && ID.test(v))) { fail(); }
        // Later in the list is newer.
        const rank = new Map();
        versionIds.forEach((v, n) => rank.set(v, n));
        const newer = (a, b) => b === null || rank.get(a) > rank.get(b);
        const cut = text => {
            const all = Array.from(text);
            return all.length <= WHOLE ? text : all.slice(0, WHOLE - 1).join("") + "…";
        };
        // A tool result as JSON: its text, parsed, when it is an object of reasonable size.
        const resultJSON = content => {
            let text = null;
            if (typeof content === "string") { text = content; }
            else if (Array.isArray(content)) {
                text = content.filter(b => isObject(b) && b.type === "text" && typeof b.text === "string").map(b => b.text).join("");
            } else if (isObject(content)) { return content; }
            if (text === null || text.length > 524288) { return null; }
            try { const parsed = JSON.parse(text); return isObject(parsed) ? parsed : null; } catch (e) { return null; }
        };
        // The last part of a path or an image's source, without its query.
        const lastSegment = src => {
            let seg = src.split(/[?#]/)[0].split("/").pop();
            try { seg = decodeURIComponent(seg); } catch (e) { }
            return seg;
        };
        // The newest of `rank`'s ids that `text` writes as `{{artifact:<v>}}` or `?v=<v>`.
        const inline = text => {
            let best = null, found;
            for (const re of [/\{\{artifact:([A-Za-z0-9_-]{1,128})\}\}/g, /[?&]v=([A-Za-z0-9_-]{1,128})/g]) {
                while ((found = re.exec(text)) !== null) {
                    if (rank.has(found[1]) && newer(found[1], best)) { best = found[1]; }
                }
            }
            return best;
        };
        // The file names `text` shows as `![…](src)`: the source's last segment
        // and, as the page reads one, without a `v<hex>_` prefix.
        const images = text => {
            const names = new Set();
            const re = /!\[[^\]]*\]\(\s*<?([^)\s>]+)/g;
            let found;
            while ((found = re.exec(text)) !== null) {
                const seg = lastSegment(found[1]);
                names.add(seg);
                names.add(seg.replace(/^v[0-9a-f]+_/, ""));
            }
            return names;
        };

        const rows = [];
        const calls = Object.create(null);
        const saves = [];
        const turns = [];
        for (let k = 0; k < page.messages.length; k++) {
            const i = base + k, m = page.messages[k];
            if (!isObject(m)) { fail(); }
            if (m.role !== "user" && m.role !== "assistant") { continue; }
            let blocks;
            if (typeof m.content === "string") { blocks = [{ type: "text", text: m.content }]; }
            else if (Array.isArray(m.content)) { blocks = m.content; }
            else { fail(); }
            for (const block of blocks) {
                if (!isObject(block) || typeof block.type !== "string") { fail(); }
                if (block.type === "text" && typeof block.text !== "string") { fail(); }
            }
            // Too big for the daemon to send: a placeholder.
            if (!isAbsent(m._oversized_bytes)) { continue; }
            const texts = blocks.filter(b => b.type === "text").map(b => b.text);
            if (m.role === "user") {
                if (HIDDEN_FLAGS.some(flag => Boolean(m[flag]))) { continue; }
                for (const block of blocks) {
                    if (block.type !== "tool_result" || typeof block.tool_use_id !== "string" || block.is_error === true) { continue; }
                    const call = calls[block.tool_use_id];
                    if (call === undefined || !call.saver) { continue; }
                    const result = resultJSON(block.content);
                    if (result === null || !Array.isArray(result.artifacts)) { continue; }
                    let listed = null;
                    for (const one of result.artifacts.slice(0, 50)) {
                        if (isObject(one) && typeof one.version_id === "string" && rank.has(one.version_id) && newer(one.version_id, listed)) {
                            listed = one.version_id;
                        }
                    }
                    if (listed !== null) { saves.push({ after: i, tool: call.row, v: listed }); }
                }
                const own = texts.join("\n\n").trim();
                if (own !== "" && !HIDDEN_STARTS.some(start => own.startsWith(start))) { turns.push(i); }
            } else {
                const row = { i: i, at: time(m._ts), text: texts.map(t => t.trim()).filter(Boolean).join("\n\n"), refs: [] };
                for (const block of blocks) {
                    // A call's name and id only: its input is never looked at.
                    if ((block.type === "tool_use" || block.type === "server_tool_use") && typeof block.name === "string"
                        && typeof block.id === "string") {
                        calls[block.id] = { row: rows.length, saver: SAVERS.indexOf(block.name.toLowerCase()) >= 0 };
                    }
                }
                // `{"<filename>": {artifact_id, version_id}}`.
                if (isObject(m._artifact_refs)) {
                    for (const name of Object.keys(m._artifact_refs).slice(0, MAX_REFS)) {
                        const ref = m._artifact_refs[name];
                        if (isObject(ref) && typeof ref.version_id === "string" && rank.has(ref.version_id)) {
                            row.refs.push({ name: name, v: ref.version_id });
                        }
                    }
                }
                rows.push(row);
            }
        }

        // Each message's own way of showing an id.
        const hits = new Map();
        rows.forEach((row, n) => {
            const written = inline(row.text);
            if (written !== null) { hits.set(n, { how: "inline", v: written }); return; }
            if (row.refs.length === 0) { return; }
            const shown = images(row.text);
            let image = null, mention = null;
            for (const ref of row.refs) {
                if (shown.has(lastSegment(ref.name)) && newer(ref.v, image)) { image = ref.v; }
                if (newer(ref.v, mention)) { mention = ref.v; }
            }
            hits.set(n, image !== null ? { how: "image", v: image } : { how: "mention", v: mention });
        });
        // A save: the next assistant text after its result, before the user's
        // next turn, else the message that made the call.
        for (const save of saves) {
            const turn = turns.find(t => t > save.after);
            let target = save.tool;
            for (let n = 0; n < rows.length; n++) {
                if (rows[n].i > save.after && (turn === undefined || rows[n].i < turn) && rows[n].text !== "") { target = n; break; }
            }
            const have = hits.get(target);
            if (have === undefined || (have.how === "saved" && newer(save.v, have.v))) { hits.set(target, { how: "saved", v: save.v }); }
        }

        let best = -1;
        for (const n of hits.keys()) { if (n > best) { best = n; } }
        if (best < 0) { return null; }
        const row = rows[best], hit = hits.get(best);
        return { i: row.i, at: row.at, text: cut(row.text), how: hit.how, v: hit.v };
    }

    function benchNewestTs(messages) {
        "use strict";
        const EARLIEST = 946684800000, LATEST = 4102444800000;
        let newest = null;
        if (!Array.isArray(messages)) { return null; }
        for (const m of messages) {
            if (m === null || typeof m !== "object" || typeof m._ts !== "number" || !isFinite(m._ts)) { continue; }
            const ms = m._ts < 1e11 ? m._ts * 1000 : m._ts;
            if (ms >= EARLIEST && ms <= LATEST && (newest === null || ms > newest)) { newest = Math.round(ms); }
        }
        return newest;
    }
    """#

    /// What `callAsyncJavaScript` runs for one page of Keep's showing read,
    /// with `frameId`, `before` (a row index, or null for the last page),
    /// `versionIds` and `nonce`. The same GETs as the history page, the same
    /// 15 s each, and with a nonce the page files an AbortController under it
    /// in `globalThis.benchArtifactReads` (the artifact reader's own map, in
    /// the same content world), so `abortArtifactRead(nonce)` ends the fetch.
    /// Answers `{"outcome":"read","total","from","newest","found"}` (`found`
    /// null or `benchFindShowingMessage`'s answer; `newest` the page's
    /// largest `_ts`), `"unreadable"`, `"lost"`, `"refused"` or `"cancelled"`.
    static let showingBody = showingProjection + "\n" + fetcher + "\n" + rowReader + #"""

    // `typeof`: no AbortController (the tests' page) means a read that can't be aborted.
    const readID = typeof nonce === "string" && /^[A-Za-z0-9-]{1,64}$/.test(nonce) ? nonce : null;
    const controller = readID !== null && typeof AbortController === "function" ? new AbortController() : null;
    const reads = controller === null ? null
        : (globalThis.\#(ArtifactReaderScript.readsName) = globalThis.\#(ArtifactReaderScript.readsName) || Object.create(null));
    if (controller !== null) { reads[readID] = controller; }
    const aborted = () => controller !== null && controller.signal.aborted === true;
    try {
        const rows = await readRows(frameId, before, null, controller);
        if (aborted()) { return JSON.stringify({ outcome: "cancelled" }); }
        if (rows.outcome !== undefined) { return JSON.stringify(rows); }
        let found = null;
        try { found = benchFindShowingMessage({ total: rows.total, messages: rows.messages }, rows.base, versionIds); }
        catch (e) { return JSON.stringify({ outcome: "unreadable" }); }
        return JSON.stringify({ outcome: "read", total: rows.total, from: rows.base, newest: benchNewestTs(rows.messages), found: found });
    } finally {
        if (controller !== null && reads[readID] === controller) { delete reads[readID]; }
    }
    """#

    /// What the page said.
    enum Outcome: Equatable {
        case read(HistoryPage)
        /// The history has `total` rows, as many as the page Bench holds.
        case same(total: Int)
        case turn(HistoryTurn)
        /// No turn at that index.
        case none
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
        case "none": return .none
        case "read": return HistoryPage(object: root["page"]).map(Outcome.read) ?? .unreadable
        case "same":
            guard let total = Pick.int(root["total"]), (0...maxIndex + 1).contains(total) else { return .unreadable }
            return .same(total: total)
        case "turn": return HistoryTurn(object: root["turn"]).map(Outcome.turn) ?? .unreadable
        default: return .unreadable
        }
    }

    // MARK: Keep's showing read

    /// The page's answer to one page of the showing read, checked again here:
    /// the page's own `from` and `total`, a `newest` time in range, and a
    /// message whose index is on the page, whose `how` is one of the four and
    /// whose `v` is one of `versions`. Anything else is unreadable.
    static func showingOutcome(of data: Data, versions: [String]) -> ShowingPageRead {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let outcome = Pick.string(root["outcome"]) else { return .unreadable }
        switch outcome {
        case "lost": return .lost
        case "cancelled": return .cancelled
        case "read":
            guard let total = Pick.int(root["total"]), (0...maxIndex + 1).contains(total),
                  let from = Pick.int(root["from"]), (0...total).contains(from),
                  let newest = Pick.optionalTime(root["newest"]) else { return .unreadable }
            if Pick.isNull(root["found"]) { return .page(ShowingPage(total: total, from: from, newest: newest, found: nil)) }
            guard let found = ShowingMessage(object: root["found"], rows: from..<total, versions: versions) else { return .unreadable }
            return .page(ShowingPage(total: total, from: from, newest: newest, found: found))
        default: return .unreadable
        }
    }
}

// MARK: What Swift receives

/// A file a turn made, as the phone may know it: `{v, a, name, kind, size}`.
struct HistoryFile: Equatable, Sendable {
    let v: String
    let a: String?
    let name: String
    let kind: ArtifactKind
    let size: Int?

    static let nameLimit = 255

    init(v: String, a: String?, name: String, kind: ArtifactKind, size: Int?) {
        self.v = v
        self.a = a
        self.name = name
        self.kind = kind
        self.size = size
    }

    /// The page's `{v, a, name, mime, size}`; the kind is decided here.
    init?(object: Any?) {
        guard let file = object as? [String: Any], let v = Pick.string(file["v"]), PlanCheck.isVersionID(v),
              let a = Pick.optionalPlanID(file["a"]),
              let name = Pick.text(file["name"], limit: Self.nameLimit) else { return nil }
        let mime: String?
        if Pick.isNull(file["mime"]) {
            mime = nil
        } else {
            guard let given = Pick.string(file["mime"]), given.utf8.count <= 100 else { return nil }
            mime = given
        }
        let size: Int?
        if Pick.isNull(file["size"]) {
            size = nil
        } else {
            guard let given = Pick.int(file["size"]), given >= 0 else { return nil }
            size = given
        }
        self.init(v: v, a: a.value, name: name, kind: ArtifactKind.classify(name: name, mime: mime), size: size)
    }
}

/// One line of a session's history.
enum HistoryItem: Equatable, Sendable {
    enum Role: String, Sendable { case you, claude }

    case turn(i: Int, role: Role, at: Date?, text: String, cut: Bool, files: [HistoryFile])
    /// A run of tool calls, in the UI's group phrases.
    case steps(i: Int, line: String, failed: Bool, files: [HistoryFile])
    /// Drafted a plan of this many steps, when known.
    case plan(i: Int, steps: Int?)
    /// Asked the user `q`; `a` is the answer, once given.
    case ask(i: Int, q: String?, a: String?)
    /// A message the agent sent the user mid-run.
    case toYou(i: Int, text: String, files: [HistoryFile])
    /// Asked a helper agent.
    case helper(i: Int)

    var index: Int {
        switch self {
        case .turn(let i, _, _, _, _, _), .steps(let i, _, _, _), .plan(let i, _), .ask(let i, _, _),
             .toYou(let i, _, _), .helper(let i): i
        }
    }

    var files: [HistoryFile] {
        switch self {
        case .turn(_, _, _, _, _, let files), .steps(_, _, _, let files), .toYou(_, _, let files): files
        default: []
        }
    }

    static let filesLimit = 20
    static let lineLimit = 300

    init?(object: Any?) {
        guard let item = object as? [String: Any], let i = Pick.int(item["i"]), (0...HistoryReaderScript.maxIndex).contains(i) else {
            return nil
        }
        func files() -> [HistoryFile]? {
            if item["files"] == nil { return [] }
            guard let raw = item["files"] as? [Any], raw.count <= Self.filesLimit else { return nil }
            var list: [HistoryFile] = []
            for one in raw {
                guard let file = HistoryFile(object: one) else { return nil }
                list.append(file)
            }
            return list
        }
        func optionalLine(_ key: String) -> String?? {
            if Pick.isNull(item[key]) { return .some(nil) }
            guard let text = Pick.text(item[key], limit: Self.lineLimit) else { return nil }
            return .some(text)
        }
        if let roleWord = Pick.string(item["role"]) {
            guard let role = Role(rawValue: roleWord), let at = Pick.optionalTime(item["at"]),
                  let cut = Pick.bool(item["cut"]), let files = files() else { return nil }
            // A message that was only an attachment (a photo) has files and no text.
            let empty = Pick.string(item["text"]) == "" && !files.isEmpty
            guard let text = empty ? "" : Pick.text(item["text"], limit: HistoryReaderScript.turnText) else { return nil }
            self = .turn(i: i, role: role, at: at, text: text, cut: cut, files: files)
            return
        }
        switch Pick.string(item["kind"]) {
        case "steps":
            guard let line = Pick.text(item["line"], limit: Self.lineLimit), let failed = Pick.bool(item["failed"]),
                  let files = files() else { return nil }
            self = .steps(i: i, line: line, failed: failed, files: files)
        case "plan":
            if Pick.isNull(item["steps"]) {
                self = .plan(i: i, steps: nil)
            } else {
                guard let steps = Pick.int(item["steps"]), (0...10_000).contains(steps) else { return nil }
                self = .plan(i: i, steps: steps)
            }
        case "ask":
            guard let q = optionalLine("q"), let a = optionalLine("a") else { return nil }
            self = .ask(i: i, q: q, a: a)
        case "toYou":
            guard let text = Pick.string(item["text"]), text.unicodeScalars.count <= HistoryReaderScript.turnText,
                  let files = files() else { return nil }
            self = .toYou(i: i, text: text, files: files)
        case "helper":
            self = .helper(i: i)
        default:
            return nil
        }
    }
}

/// One page of a session's history: rows `from` up to the page's end, of
/// `total`, oldest first.
struct HistoryPage: Equatable, Sendable {
    let total: Int
    let from: Int
    let items: [HistoryItem]

    init(total: Int, from: Int, items: [HistoryItem]) {
        self.total = total
        self.from = from
        self.items = items
    }

    init?(object: Any?) {
        guard let page = object as? [String: Any], let total = Pick.int(page["total"]),
              (0...HistoryReaderScript.maxIndex + 1).contains(total), let from = Pick.int(page["from"]),
              (0...total).contains(from), let raw = page["items"] as? [Any],
              raw.count <= HistoryReaderScript.maxItems else { return nil }
        var items: [HistoryItem] = []
        for one in raw {
            guard let item = HistoryItem(object: one), item.index >= from, item.index < total,
                  item.index >= (items.last?.index ?? 0) else { return nil }
            items.append(item)
        }
        self.init(total: total, from: from, items: items)
    }

    /// Every version id the page lists.
    var versions: [String] {
        files.map(\.v)
    }

    /// Every file the page lists.
    var files: [HistoryFile] {
        items.flatMap(\.files)
    }

    /// Within `maxItems` and `maxBytes` of JSON as Swift writes it: the
    /// oldest rows go whole, and `from` moves to the first row kept.
    func capped(maxItems: Int = HistoryReaderScript.maxItems, maxBytes: Int = HistoryReaderScript.maxBytes,
                encode: (HistoryPage) -> Data) -> HistoryPage {
        var page = self
        while page.items.count > 1, page.items.count > maxItems || encode(page).count > maxBytes {
            let row = page.items[0].index
            let rest = Array(page.items.drop { $0.index == row })
            guard let first = rest.first else { break }
            page = HistoryPage(total: total, from: first.index, items: rest)
        }
        return page
    }
}

/// A cut turn, whole: `{i, role, at, text}`.
struct HistoryTurn: Equatable, Sendable {
    let i: Int
    let role: HistoryItem.Role
    let at: Date?
    let text: String

    init(i: Int, role: HistoryItem.Role, at: Date?, text: String) {
        self.i = i
        self.role = role
        self.at = at
        self.text = text
    }

    init?(object: Any?) {
        guard let turn = object as? [String: Any], let i = Pick.int(turn["i"]), (0...HistoryReaderScript.maxIndex).contains(i),
              let role = Pick.string(turn["role"]).flatMap(HistoryItem.Role.init(rawValue:)),
              let at = Pick.optionalTime(turn["at"]),
              let text = Pick.text(turn["text"], limit: HistoryReaderScript.wholeTurn) else { return nil }
        self.init(i: i, role: role, at: at, text: text)
    }
}

// MARK: Keep: the message that shows a figure

/// How a message showed a version, from the surest way down.
enum ShowingHow: String, Sendable {
    /// `{{artifact:<v>}}` or `?v=<v>` is in its text.
    case inline
    /// It names the file in an image its text shows.
    case image
    /// It names the file, with no image of it in its text.
    case mention
    /// Claude saved the version in the step before it: the reply after the save,
    /// which may show a newer version.
    case saved
}

/// The assistant message that shows one of an artifact's versions.
struct ShowingMessage: Equatable, Sendable {
    /// Its row in the session's history.
    let i: Int
    /// When it was sent, when the row says.
    let at: Date?
    /// Its text, at most 20,000 characters.
    let text: String
    let how: ShowingHow
    /// The version it shows.
    let v: String

    static let textLimit = 20_000

    init(i: Int, at: Date?, text: String, how: ShowingHow, v: String) {
        self.i = i
        self.at = at
        self.text = text
        self.how = how
        self.v = v
    }

    /// The page's `{i, at, text, how, v}`; the row must be one of `rows` and the
    /// version one of `versions`.
    init?(object: Any?, rows: Range<Int>, versions: [String]) {
        guard let message = object as? [String: Any], let i = Pick.int(message["i"]), rows.contains(i),
              let at = Pick.optionalTime(message["at"]),
              let text = Pick.string(message["text"]), text.unicodeScalars.count <= Self.textLimit,
              let how = Pick.string(message["how"]).flatMap(ShowingHow.init(rawValue:)),
              let v = Pick.string(message["v"]), versions.contains(v) else { return nil }
        self.init(i: i, at: at, text: text, how: how, v: v)
    }
}

/// What looking for the message that shows a version came to.
enum ShowingRead: Equatable, Sendable {
    case found(ShowingMessage)
    /// The walk ended, or reached messages older than the versions, with none.
    case notFound
    /// A page couldn't be read, or wasn't the shape Capsid reads.
    case unreadable
}

/// One page of the showing read, as the page answered it.
struct ShowingPage: Equatable, Sendable {
    let total: Int
    /// The first row of the page.
    let from: Int
    /// The largest `_ts` on the page, when any row has one.
    let newest: Date?
    let found: ShowingMessage?
}

enum ShowingPageRead: Equatable, Sendable {
    case page(ShowingPage)
    case unreadable
    /// A 401: the page's session didn't take.
    case lost
    /// The read's nonce was aborted.
    case cancelled
}

/// The walk behind `WebContainer.readShowing`: pages from the newest back,
/// each asked for by `read(before)` (nil for the last page). Pure of the page.
enum HistoryShowing {
    /// At most this many pages of 50 rows.
    static let pages = 6
    /// Each older page covers this many rows of the one before it again, so the
    /// reply after a save that the earlier page ended on is on this one.
    static let overlap = 6
    /// Most version ids one read takes.
    static let maxVersions = 600

    /// A nonce as the page files it: letters, digits and dashes, 1 to 64.
    static func isNonce(_ text: String) -> Bool {
        (1...64).contains(text.utf8.count) && text.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D
        }
    }

    /// The newest message that shows a version, else `.notFound` when six
    /// pages, the start of the history or a page whose newest `_ts` is older
    /// than `near` (the oldest version's time: the reply that shows a figure
    /// follows its save) ends the walk. Throws `CancellationError` when the
    /// task is cancelled or a page was aborted.
    @MainActor
    static func walk(near: Date?, read: @MainActor (_ before: Int?) async throws -> ShowingPageRead) async throws -> ShowingRead {
        var before: Int?
        for _ in 0..<pages {
            try Task.checkCancellation()
            switch try await read(before) {
            case .unreadable, .lost: return .unreadable
            case .cancelled: throw CancellationError()
            case .page(let page):
                if let found = page.found { return .found(found) }
                if let near, let newest = page.newest, newest < near { return .notFound }
                guard page.from > 0 else { return .notFound }
                before = min(page.from + overlap, page.total)
            }
        }
        return .notFound
    }
}

// MARK: Reading through the page

extension WebContainer {
    /// A page of a session's history (`HistoryReaderScript.pageBody`): the 50
    /// rows before `before`, or the last 50; for the last, `.same` when the
    /// history still has `knownTotal` rows. Unreadable when it can't be read
    /// or doesn't match; throws when the page isn't up or the id isn't a full
    /// frame id.
    func readHistory(_ frameID: String, before: Int?, knownTotal: Int? = nil) async throws -> RemoteBrowser.HistoryRead {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID) else { throw WebAPIError.notAllowed }
        if let before, !(1...HistoryReaderScript.maxIndex).contains(before) { throw WebAPIError.notAllowed }
        let value = try await webView.callAsyncJavaScript(
            HistoryReaderScript.pageBody,
            arguments: ["frameId": frameID, "before": before.map { $0 as Any } ?? NSNull(),
                        "knownTotal": knownTotal.map { $0 as Any } ?? NSNull()],
            in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        switch HistoryReaderScript.outcome(of: Data(text.utf8)) {
        case .read(let page): return .page(page)
        case .same(let total): return .same(total: total)
        case .lost:
            sessionLost()
            return .unreadable
        default: return .unreadable
        }
    }

    /// One row's text whole. `.none` when the row is no turn the history shows.
    func readTurn(_ frameID: String, index: Int) async throws -> HistoryReaderScript.Outcome {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID), (0...HistoryReaderScript.maxIndex).contains(index) else {
            throw WebAPIError.notAllowed
        }
        let value = try await webView.callAsyncJavaScript(
            HistoryReaderScript.turnBody, arguments: ["frameId": frameID, "index": index],
            in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        let outcome = HistoryReaderScript.outcome(of: Data(text.utf8))
        if outcome == .lost { sessionLost() }
        return outcome
    }

    /// Keep's read: the newest assistant message of the session that shows any
    /// of `versions` (an artifact's version ids, oldest first), walking the
    /// history's pages back from the end (`HistoryShowing.walk`), one
    /// allowlisted GET and one `HistoryReaderScript.showingBody` run for each.
    /// `near` is the oldest version's time. `nonce` is the caller's own: the
    /// page files a controller under it, and `abortArtifactRead(nonce)` or
    /// cancelling the task ends the walk with a `CancellationError`. Throws
    /// when the page isn't up or an argument is out of shape (a frame id that
    /// isn't 36 characters, no versions or more than 600, a version id that
    /// isn't path-safe, a malformed nonce).
    func readShowing(frameID: String, versions: [String], near: Date?, nonce: String) async throws -> ShowingRead {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID), HistoryShowing.isNonce(nonce),
              (1...HistoryShowing.maxVersions).contains(versions.count),
              versions.allSatisfy(PlanCheck.isVersionID) else { throw WebAPIError.notAllowed }
        return try await withTaskCancellationHandler {
            try await HistoryShowing.walk(near: near) { before in
                let value = try await self.webView.callAsyncJavaScript(
                    HistoryReaderScript.showingBody,
                    arguments: ["frameId": frameID, "before": before.map { $0 as Any } ?? NSNull(),
                                "versionIds": versions, "nonce": nonce],
                    in: nil, contentWorld: .defaultClient)
                guard let text = value as? String else { throw WebAPIError.badResponse }
                let page = HistoryReaderScript.showingOutcome(of: Data(text.utf8), versions: versions)
                if page == .lost { self.sessionLost() }
                return page
            }
        } onCancel: {
            Task { @MainActor in await self.abortArtifactRead(nonce) }
        }
    }
}
