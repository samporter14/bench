// InsightReader.swift — what the specimens panel and the cards say about a
// session beyond its status: how far through its plan it is, and what the
// reviewer found (DESIGN.md, Lab → Plan progress, Reviewer counts; since 1.0).
// Like the history and session readers, the page runs the GETs and *projects*
// them itself, so Swift only ever receives a few integers, the status words
// already counted, and at most one step title:
//
//  - Plan progress: `GET /api/frames/<root>/trace-shallow?include_messages=false`,
//    the page's own lean tree. Its root is a "fat" frame that carries the whole
//    plan (every step's description) and each helper's claims repeat their
//    descriptions, so none of the tree may reach Swift. The projection takes
//    the plan's step titles in order, the root's `_step_statuses` and, for each
//    direct child of the root, the statuses of the titles its `_plan_claims`
//    list for the current plan version (Claude Science's own merge, DESIGN.md,
//    1.0 spikes, S3), counts as the page does, and answers `{step, total, title?}`.
//    Never a description, a note or a time.
//  - Reviewer counts: `GET /api/frames/<root>/verification?resolved_limit=0&actionable_limit=500`,
//    projected to `{standing, fixed, running, reviews}` by the rule the page
//    uses (S4). Never a claim, its evidence or a rebuttal.
//
// Both are plain JavaScript with no fetch and no DOM (the fetching is the
// body's), so the tests run the very same strings in JavaScriptCore on made-up
// trees. Swift checks every field again; anything that doesn't match is
// unreadable. The two paths are this file's own allowlist, checked in the page
// before each fetch (`isAllowedPath`) and by Swift before the page is asked;
// `WebContainer.apiGET`'s list is not widened, because it would hand the whole
// body to Swift. What is read lives in memory only, while the answer is built.
import Foundation
import WebKit

// MARK: The script

enum InsightReaderScript {
    /// A GET's body, at most this many bytes (the history reader's cap).
    static let bodyCap = HistoryReaderScript.bodyCap
    /// A plan of more steps than this is not read, and a tree of more
    /// children than `maxChildren`.
    static let maxSteps = 1_000
    static let maxChildren = 2_000
    /// A step title on the card, at most this many characters.
    static let titleLimit = 200
    /// How many findings a read of the verification route can count at most
    /// (`actionable_limit`).
    static let actionableLimit = 500

    // MARK: Paths

    /// The session's lean tree, which the phone's permission queue reads too.
    static func tracePath(_ frameID: String) -> String? {
        PlanCheck.isFrameID(frameID) ? "/api/frames/\(frameID)/trace-shallow?include_messages=false" : nil
    }

    /// The session's reviewer findings, asked for the way the page asks for
    /// its continuation pages: no resolved checks, up to 500 actionable ones.
    static func verificationPath(_ frameID: String) -> String? {
        PlanCheck.isFrameID(frameID)
            ? "/api/frames/\(frameID)/verification?resolved_limit=0&actionable_limit=\(actionableLimit)" : nil
    }

    /// The only two GETs these reads make, exactly:
    /// `^/api/frames/<36>/trace-shallow\?include_messages=false$` and
    /// `^/api/frames/<36>/verification\?resolved_limit=0&actionable_limit=500$`.
    /// The page checks the same before every fetch.
    static func isAllowedPath(_ path: String) -> Bool {
        let head = "/api/frames/"
        guard path.hasPrefix(head) else { return false }
        let rest = path.dropFirst(head.count)
        guard rest.count > 36, PlanCheck.isFrameID(String(rest.prefix(36))) else { return false }
        let tail = rest.dropFirst(36)
        return tail == "/trace-shallow?include_messages=false"
            || tail == "/verification?resolved_limit=0&actionable_limit=\(actionableLimit)"
    }

    // MARK: Projections

    /// `benchProjectProgress(tree, rootId)`: `{outcome: "progress", step, total,
    /// title, processing, children, reported, unknown}` or `{outcome: "idle", why,
    /// processing, children, reported, unknown}`, or null when a shape doesn't
    /// match. `tree` is the root's `trace-shallow` (frames nested under
    /// `children`). Pure: no fetch, no DOM, no globals.
    ///
    /// The page's own arithmetic (DESIGN.md, 1.0 spikes, S3): a plan is read
    /// only once approved (`context_data._plan_approved` is the JSON `true`,
    /// context only), with a version id fit for a path and a plan with `phases`;
    /// its steps are `phases[].delegations[].steps[]` in order, `total` their
    /// count; the statuses are the root's `_step_statuses`, then, for each
    /// DIRECT child of the root, that child's status for every title in its
    /// `_plan_claims` entries whose `plan_version_id` is the current version
    /// (a child's statuses are never copied to the root, and a helper's helper
    /// is not looked at); `done` is the number of the plan's titles whose
    /// merged status is `completed` or `skipped` (`blocked` is not done);
    /// `step` is `min(done + 1, total)`. Stricter than the page, on purpose:
    /// nothing until at least one step has reported `in_progress`, `completed`,
    /// `blocked` or `skipped` (a model that never reports leaves the page
    /// saying "step 1" for ever), nothing once `done >= total`, and a status
    /// word the page doesn't know counts as no status (`unknown` says how many).
    /// The title comes only when exactly one title is `in_progress`, that
    /// title is the plan's alone, and its place in the plan is `step`.
    ///   `why` of an idle answer: `not-approved`, `no-plan` (no version, no
    ///   `phases`, no steps or too many), `plan-missing` (approved, but the tree
    ///   carries no `_plan_json`), `no-statuses`, `complete`.
    static let progressProjection = #"""
    function benchProjectProgress(tree, rootId) {
        "use strict";
        const FRAME = /^[0-9a-f-]{36}$/;
        const VERSION = /^[A-Za-z0-9_-]{1,128}$/;
        const KNOWN = ["pending", "in_progress", "completed", "blocked", "skipped"];
        const MAX_STEPS = \#(maxSteps), MAX_CHILDREN = \#(maxChildren), TITLE = \#(titleLimit);
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const isAbsent = v => v === undefined || v === null;
        const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
        // An object, or a string holding one; null when absent; undefined for anything else.
        const objectOrNull = v => {
            if (isAbsent(v)) { return null; }
            if (isObject(v)) { return v; }
            if (typeof v === "string") {
                try { const parsed = JSON.parse(v); if (isObject(parsed)) { return parsed; } } catch (e) { }
            }
            return undefined;
        };
        // One line, control characters gone, cut at TITLE characters; null when nothing is left.
        const oneLine = text => {
            const clean = text.replace(/[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g, " ");
            const line = clean.split(/\s+/).filter(Boolean).join(" ");
            if (line === "") { return null; }
            const all = Array.from(line);
            return all.length <= TITLE ? line : all.slice(0, TITLE - 1).join("") + "…";
        };

        if (!isObject(tree) || typeof rootId !== "string" || !FRAME.test(rootId) || tree.id !== rootId
            || typeof tree.status !== "string") { return null; }
        const processing = tree.status === "processing";
        let children = 0, reported = 0, unknown = 0;
        const idle = why => ({ outcome: "idle", why: why, processing: processing, children: children, reported: reported, unknown: unknown });

        const context = objectOrNull(tree.context_data);
        if (context === undefined) { return null; }
        if (context === null || context._plan_approved !== true) { return idle("not-approved"); }
        const output = objectOrNull(tree.output_data);
        const rawVersion = isAbsent(context._plan_version_id) ? (isObject(output) ? output.plan_version_id : undefined)
                                                              : context._plan_version_id;
        if (typeof rawVersion !== "string" || !VERSION.test(rawVersion)) { return idle("no-plan"); }
        const version = rawVersion;

        // The plan's steps, in order: a title (exact, as the statuses are keyed) or null.
        const plan = objectOrNull(context._plan_json);
        if (isAbsent(plan)) { return idle("plan-missing"); }
        if (!Array.isArray(plan.phases)) { return idle("no-plan"); }
        const steps = [];
        for (const phase of plan.phases) {
            if (!isObject(phase) || !Array.isArray(phase.delegations)) { continue; }
            for (const delegation of phase.delegations) {
                if (!isObject(delegation) || !Array.isArray(delegation.steps)) { continue; }
                for (const step of delegation.steps) {
                    steps.push(isObject(step) && typeof step.title === "string" && step.title.trim() !== "" ? step.title : null);
                    if (steps.length > MAX_STEPS) { return idle("no-plan"); }
                }
            }
        }
        if (steps.length === 0) { return idle("no-plan"); }
        const total = steps.length;
        // How many times each title is in the plan, and where it first is.
        const times = new Map(), first = new Map();
        steps.forEach((title, at) => {
            if (title === null) { return; }
            times.set(title, (times.get(title) || 0) + 1);
            if (!first.has(title)) { first.set(title, at); }
        });

        const word = entry => isObject(entry) && typeof entry.status === "string" ? entry.status : null;
        const rootStatuses = objectOrNull(context._step_statuses);
        if (rootStatuses === undefined) { return null; }
        const merged = Object.create(null);
        if (rootStatuses !== null) {
            for (const title of first.keys()) {
                if (own(rootStatuses, title)) { const w = word(rootStatuses[title]); if (w !== null) { merged[title] = w; } }
            }
        }
        const below = tree.children;
        if (!isAbsent(below)) {
            if (!Array.isArray(below) || below.length > MAX_CHILDREN) { return null; }
            for (const child of below) {
                if (!isObject(child)) { continue; }
                children += 1;
                if (typeof child.parent_frame_id === "string" && child.parent_frame_id !== rootId) { continue; }
                const claimed = objectOrNull(child.context_data);
                if (!isObject(claimed) || !Array.isArray(claimed._plan_claims)) { continue; }
                const statuses = objectOrNull(claimed._step_statuses);
                if (!isObject(statuses)) { continue; }
                for (const claim of claimed._plan_claims) {
                    if (!isObject(claim) || claim.plan_version_id !== version || !Array.isArray(claim.steps)) { continue; }
                    for (const step of claim.steps) {
                        const title = typeof step === "string" ? step : isObject(step) && typeof step.title === "string" ? step.title : null;
                        if (title === null || !own(statuses, title)) { continue; }
                        const w = word(statuses[title]);
                        if (w !== null) { merged[title] = w; }
                    }
                }
            }
        }

        let done = 0;
        const going = [];
        for (const title of first.keys()) {
            if (!(title in merged)) { continue; }
            const w = merged[title];
            if (KNOWN.indexOf(w) < 0) { unknown += 1; continue; }
            if (w === "pending") { continue; }
            reported += 1;
            if (w === "completed" || w === "skipped") { done += 1; }
            else if (w === "in_progress") { going.push(title); }
        }
        if (reported === 0) { return idle("no-statuses"); }
        if (done >= total) { return idle("complete"); }
        const current = Math.min(done + 1, total);
        let shown = null;
        if (going.length === 1 && times.get(going[0]) === 1 && first.get(going[0]) + 1 === current) { shown = oneLine(going[0]); }
        return { outcome: "progress", step: current, total: total, title: shown, processing: processing,
                 children: children, reported: reported, unknown: unknown };
    }
    """#

    /// `benchProjectReviewers(body)`: `{outcome: "counts", standing, fixed,
    /// running, reviews}`, or null when a shape doesn't match. `body` is the
    /// verification route's answer. Pure.
    ///
    /// The page's rule (DESIGN.md, 1.0 spikes, S4): a finding is a check whose
    /// `verdict` is `fail` or `warn` (a `pass` or an `inconclusive` is never
    /// one). It stands while its `status` is `open` or `claimed`, or
    /// `unaddressed` (what an open finding becomes when the turn ends) unless
    /// withdrawn: `unaddressed` with a rebuttal and fewer than four re-flags.
    /// It is fixed once `resolved`: the answer counts those apart
    /// (`resolved_by_verdict`, since no resolved check is asked for), or, as
    /// the checks list them, whichever is more. `running` is the reviews under
    /// way, `reviews` the answer's `completed_review_count`.
    static let reviewerProjection = #"""
    function benchProjectReviewers(body) {
        "use strict";
        const LIMIT = 1000000;
        const isObject = v => v !== null && typeof v === "object" && !Array.isArray(v);
        const isAbsent = v => v === undefined || v === null;
        // A whole number from 0 to LIMIT; `fallback` when absent; null for anything else.
        const count = (v, fallback) => {
            if (isAbsent(v)) { return fallback; }
            return typeof v === "number" && isFinite(v) && v >= 0 && v <= LIMIT && Math.floor(v) === v ? v : null;
        };
        if (!isObject(body) || !Array.isArray(body.checks) || !Array.isArray(body.running)) { return null; }
        let standing = 0, resolved = 0;
        for (const check of body.checks) {
            if (!isObject(check) || typeof check.verdict !== "string" || typeof check.status !== "string") { return null; }
            if (check.verdict !== "fail" && check.verdict !== "warn") { continue; }
            if (check.status === "resolved") { resolved += 1; }
            else if (check.status === "open" || check.status === "claimed") { standing += 1; }
            else if (check.status === "unaddressed") {
                const rebutted = typeof check.rebuttal === "string" && check.rebuttal.trim() !== "";
                const reflags = typeof check.reflag_count === "number" && isFinite(check.reflag_count) ? check.reflag_count : 0;
                if (!(rebutted && reflags < 4)) { standing += 1; }
            }
        }
        let fixed = resolved;
        if (!isAbsent(body.resolved_by_verdict)) {
            if (!isObject(body.resolved_by_verdict)) { return null; }
            const failed = count(body.resolved_by_verdict.fail, 0), warned = count(body.resolved_by_verdict.warn, 0);
            if (failed === null || warned === null) { return null; }
            fixed = Math.max(resolved, failed + warned);
        }
        const reviews = count(body.completed_review_count, 0);
        if (reviews === null) { return null; }
        return { outcome: "counts", standing: standing, fixed: fixed, running: body.running.length, reviews: reviews };
    }
    """#

    // MARK: Fetching

    /// The page's own fetch, for these two reads only: `no-store`, 15 s each,
    /// the body streamed and stopped at `bodyCap` bytes, and the page yields
    /// (an idle callback with a 1 s timeout, else `setTimeout(0)`, else not at
    /// all) before `JSON.parse` so its own typing isn't held. `get(path, stop)`
    /// answers `{json}`, `{lost}` (401), `{missing}` (404 or 410), `{tooBig}` or
    /// `{failed}`; `stop` is an optional AbortController (a read with a nonce
    /// files one, so `abortArtifactRead` ends the fetch).
    static let fetcher = #"""
    const ALLOWED = [/^\/api\/frames\/[0-9a-f-]{36}\/trace-shallow\?include_messages=false$/,
                     /^\/api\/frames\/[0-9a-f-]{36}\/verification\?resolved_limit=0&actionable_limit=\#(actionableLimit)$/];
    const BODY_CAP = \#(bodyCap);
    const pause = () => new Promise(resolve => {
        if (typeof requestIdleCallback === "function") { requestIdleCallback(resolve, { timeout: 1000 }); }
        else if (typeof setTimeout === "function") { setTimeout(resolve, 0); }
        else { resolve(); }
    });
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
    // The response's body as text: `{text}`, `{tooBig}` or null (no way to read it).
    const readBody = async response => {
        let declared = null;
        try {
            const header = response.headers && response.headers.get("content-length");
            if (typeof header === "string" && /^\d{1,16}$/.test(header)) { declared = Number(header); }
        } catch (e) { declared = null; }
        const body = response.body;
        const cancel = async target => { try { if (target && typeof target.cancel === "function") { await target.cancel(); } } catch (e) { } };
        if (declared !== null && declared > BODY_CAP) { await cancel(body); return { tooBig: true }; }
        if (!body || typeof body.getReader !== "function") {
            // No stream to read (not a page's response): the whole text, counted as it comes.
            const whole = await response.text();
            if (typeof whole !== "string") { return null; }
            return whole.length > BODY_CAP ? { tooBig: true } : { text: whole };
        }
        if (typeof TextDecoder !== "function") { await cancel(body); return null; }
        const reader = body.getReader();
        const decoder = new TextDecoder("utf-8");
        const parts = [];
        let total = 0;
        for (;;) {
            const step = await reader.read();
            if (step.done) { break; }
            const chunk = step.value;
            if (!ArrayBuffer.isView(chunk)) { await cancel(reader); return null; }
            if (total + chunk.byteLength > BODY_CAP) { await cancel(reader); return { tooBig: true }; }
            total += chunk.byteLength;
            parts.push(decoder.decode(chunk, { stream: true }));
        }
        parts.push(decoder.decode());
        return { text: parts.join("") };
    };
    const get = async (path, stop) => {
        if (!ALLOWED.some(rule => rule.test(path))) { return { failed: true }; }
        let response;
        try {
            response = await fetch(path, { credentials: "include", cache: "no-store",
                                           headers: { "Accept": "application/json" }, signal: signal(stop) });
        } catch (e) { return { failed: true }; }
        if (response.status === 401) { return { lost: true }; }
        if (response.status === 404 || response.status === 410) { return { missing: true }; }
        if (!response.ok) { return { failed: true }; }
        let read;
        try { read = await readBody(response); } catch (e) { return { failed: true }; }
        if (read === null) { return { failed: true }; }
        if (read.tooBig) { return { tooBig: true }; }
        try { await pause(); } catch (e) { }
        try { return { json: JSON.parse(read.text) }; } catch (e) { return { failed: true }; }
    };
    """#

    /// What `callAsyncJavaScript` runs for a session's plan progress, with
    /// `frameId` and `nonce` (a read's own: the page files an AbortController
    /// under it in `globalThis.benchArtifactReads`, so `abortArtifactRead(nonce)`
    /// ends the fetch). Answers a JSON string: `benchProjectProgress`'s answer,
    /// or `{"outcome":"unreadable"}`, `"lost"` (a 401), `"missing"` (404 or
    /// 410), `"tooBig"`, `"refused"` or `"cancelled"`.
    static let progressBody = progressProjection + "\n" + fetcher + "\n" + HistoryReaderScript.abortable + #"""

    try {
        if (typeof frameId !== "string" || !/^[0-9a-f-]{36}$/.test(frameId)) { return JSON.stringify({ outcome: "refused" }); }
        const reply = await get("/api/frames/" + frameId + "/trace-shallow?include_messages=false", controller);
        if (aborted()) { return JSON.stringify({ outcome: "cancelled" }); }
        if (reply.lost) { return JSON.stringify({ outcome: "lost" }); }
        if (reply.missing) { return JSON.stringify({ outcome: "missing" }); }
        if (reply.tooBig) { return JSON.stringify({ outcome: "tooBig" }); }
        if (reply.failed) { return JSON.stringify({ outcome: "unreadable" }); }
        let answer = null;
        try { answer = benchProjectProgress(reply.json, frameId); } catch (e) { answer = null; }
        return JSON.stringify(answer === null ? { outcome: "unreadable" } : answer);
    } finally {
        if (controller !== null && reads[readID] === controller) { delete reads[readID]; }
    }
    """#

    /// The same for a session's reviewer counts: `benchProjectReviewers`'s
    /// answer, or one of the outcomes above.
    static let reviewerBody = reviewerProjection + "\n" + fetcher + "\n" + HistoryReaderScript.abortable + #"""

    try {
        if (typeof frameId !== "string" || !/^[0-9a-f-]{36}$/.test(frameId)) { return JSON.stringify({ outcome: "refused" }); }
        const reply = await get("/api/frames/" + frameId + "/verification?resolved_limit=0&actionable_limit=\#(actionableLimit)", controller);
        if (aborted()) { return JSON.stringify({ outcome: "cancelled" }); }
        if (reply.lost) { return JSON.stringify({ outcome: "lost" }); }
        if (reply.missing) { return JSON.stringify({ outcome: "missing" }); }
        if (reply.tooBig) { return JSON.stringify({ outcome: "tooBig" }); }
        if (reply.failed) { return JSON.stringify({ outcome: "unreadable" }); }
        let answer = null;
        try { answer = benchProjectReviewers(reply.json); } catch (e) { answer = null; }
        return JSON.stringify(answer === null ? { outcome: "unreadable" } : answer);
    } finally {
        if (controller !== null && reads[readID] === controller) { delete reads[readID]; }
    }
    """#

    // MARK: What Swift receives

    /// The page's answer to a progress read, checked again here. Anything
    /// unexpected is unreadable.
    static func progressOutcome(of data: Data) -> PlanProgressRead {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let outcome = Pick.string(root["outcome"]) else { return .unreadable }
        switch outcome {
        case "lost": return .lost
        case "missing": return .missing
        case "tooBig": return .tooBig
        case "cancelled": return .cancelled
        case "progress", "idle":
            guard let processing = Pick.bool(root["processing"]),
                  let children = Pick.int(root["children"]), (0...maxChildren).contains(children),
                  let reported = Pick.int(root["reported"]), (0...maxSteps).contains(reported),
                  let unknown = Pick.int(root["unknown"]), (0...maxSteps).contains(unknown) else { return .unreadable }
            let facts = PlanProgressFacts(running: processing, children: children, reported: reported, unknown: unknown)
            if outcome == "idle" {
                guard let why = Pick.string(root["why"]).flatMap(PlanProgressWhy.init(rawValue:)) else { return .unreadable }
                return .idle(why, facts)
            }
            guard let total = Pick.int(root["total"]), (1...maxSteps).contains(total),
                  let step = Pick.int(root["step"]), (1...total).contains(step), reported >= 1, reported <= total else {
                return .unreadable
            }
            let title: String?
            if Pick.isNull(root["title"]) {
                title = nil
            } else {
                // One line of at most `titleLimit` characters, with something in it.
                guard let line = Pick.text(root["title"], limit: titleLimit),
                      !line.contains(where: \.isNewline), line == line.trimmingCharacters(in: .whitespaces) else { return .unreadable }
                title = line
            }
            return .progress(PlanProgress(step: step, total: total, title: title), facts)
        default: return .unreadable
        }
    }

    /// The page's answer to a reviewer read, checked again here.
    static func reviewerOutcome(of data: Data) -> ReviewerRead {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let outcome = Pick.string(root["outcome"]) else { return .unreadable }
        switch outcome {
        case "lost": return .lost
        case "missing": return .missing
        case "tooBig": return .tooBig
        case "cancelled": return .cancelled
        case "counts":
            let limit = 1_000_000
            guard let standing = Pick.int(root["standing"]), (0...limit).contains(standing),
                  let fixed = Pick.int(root["fixed"]), (0...limit).contains(fixed),
                  let running = Pick.int(root["running"]), (0...limit).contains(running),
                  let reviews = Pick.int(root["reviews"]), (0...limit).contains(reviews) else { return .unreadable }
            return .counts(ReviewerCounts(standing: standing, fixed: fixed, running: running, reviews: reviews))
        default: return .unreadable
        }
    }
}

/// Why a session shows no step progress even though the read was understood.
enum PlanProgressWhy: String, Equatable, Sendable {
    /// The plan isn't approved (or the session has none).
    case notApproved = "not-approved"
    /// No version, no `phases` (an older, flat plan: the page shows nothing
    /// either), no steps, or too many.
    case noPlan = "no-plan"
    /// Approved, but the tree doesn't carry the plan.
    case planMissing = "plan-missing"
    /// No step has reported a status yet.
    case noStatuses = "no-statuses"
    /// Every step is done.
    case complete
}

/// What a progress read counted besides the progress itself.
struct PlanProgressFacts: Equatable, Sendable {
    /// The root frame's own status is `processing`.
    let running: Bool
    /// The frames directly under the root.
    let children: Int
    /// Plan steps with a status that says something (not `pending`).
    let reported: Int
    /// Plan steps whose status word isn't one the page knows.
    let unknown: Int
}

/// What a plan-progress read gave.
enum PlanProgressRead: Equatable, Sendable {
    case progress(PlanProgress, PlanProgressFacts)
    /// Understood, and nothing to show.
    case idle(PlanProgressWhy, PlanProgressFacts)
    /// Not the shape Capsid reads.
    case unreadable
    /// A 401: the page's session didn't take.
    case lost
    /// A 404 or 410: the route or the session is gone.
    case missing
    case tooBig
    case cancelled
}

/// What a reviewer read gave.
enum ReviewerRead: Equatable, Sendable {
    case counts(ReviewerCounts)
    case unreadable
    case lost
    case missing
    case tooBig
    case cancelled
}

// MARK: Reading through the page

extension WebContainer {
    /// How far through its plan a running session is (`InsightReaderScript.progressBody`).
    /// Throws `WebAPIError.notReady` when the page isn't up and `notAllowed` for an
    /// id that isn't a full frame id or a malformed `nonce`. With a `nonce` (letters,
    /// digits and dashes, 1 to 64) the page files a controller under it, so
    /// cancelling the task ends the fetch and the read throws `CancellationError`.
    func readPlanProgress(_ frameID: String, nonce: String? = nil) async throws -> PlanProgressRead {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID), nonce.map(HistoryShowing.isNonce) ?? true else { throw WebAPIError.notAllowed }
        let text = try await HistoryReadAbort.run(nonce: nonce, abort: { await self.abortArtifactRead($0) }) {
            let value = try await self.webView.callAsyncJavaScript(
                InsightReaderScript.progressBody, arguments: ["frameId": frameID, "nonce": nonce ?? NSNull()],
                in: nil, contentWorld: .defaultClient)
            guard let text = value as? String else { throw WebAPIError.badResponse }
            return text
        }
        let outcome = InsightReaderScript.progressOutcome(of: Data(text.utf8))
        if outcome == .cancelled { throw CancellationError() }
        if outcome == .lost { sessionLost() }
        return outcome
    }

    /// What the reviewer found in a session, as four counts
    /// (`InsightReaderScript.reviewerBody`). Throws as `readPlanProgress` does.
    func readReviewerCounts(_ frameID: String, nonce: String? = nil) async throws -> ReviewerRead {
        guard status == .ready else { throw WebAPIError.notReady }
        guard PlanCheck.isFrameID(frameID), nonce.map(HistoryShowing.isNonce) ?? true else { throw WebAPIError.notAllowed }
        let text = try await HistoryReadAbort.run(nonce: nonce, abort: { await self.abortArtifactRead($0) }) {
            let value = try await self.webView.callAsyncJavaScript(
                InsightReaderScript.reviewerBody, arguments: ["frameId": frameID, "nonce": nonce ?? NSNull()],
                in: nil, contentWorld: .defaultClient)
            guard let text = value as? String else { throw WebAPIError.badResponse }
            return text
        }
        let outcome = InsightReaderScript.reviewerOutcome(of: Data(text.utf8))
        if outcome == .cancelled { throw CancellationError() }
        if outcome == .lost { sessionLost() }
        return outcome
    }
}
