// HistoryReaderGroundworkTests.swift — what a Mac-side reader needs of the
// history reader: a linear trim, rows per page, a nonce to abort by, a 2 MiB
// byte cap, a yield before the heavy steps and the page's own timing. The
// page scripts are the very JavaScript the page runs, in JavaScriptCore, with
// a made-up fetch that streams bodies; Swift's checks run on what comes back.
// Every id and row is invented; nothing reaches a daemon.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let ts = 1_791_833_000_000

private func jsLiteral(_ text: String) -> String {
    String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
}

private func rowsJSON(_ range: Range<Int>) -> String {
    "[" + range.map { ReaderFixture.userRow("Made-up row \($0)", at: ts + $0) }.joined(separator: ",") + "]"
}

/// One GET's answer: the rows `first..<first+count`, as the daemon sends them.
private func pageJSON(from: Int, total: Int, count: Int, first: Int? = nil) -> String {
    let start = first ?? from
    return #"{"frame_id": "\#(root)", "from": \#(from), "total": \#(total), "messages": \#(rowsJSON(start..<(start + count)))}"#
}

private func path(_ query: String) -> String { "/api/frames/\(root)/messages?\(query)" }

// MARK: 1. The linear trim

/// The trim loop as it was before: every row it dropped stringified the whole
/// remainder again. Kept here to prove the linear count keeps the same rows.
private let oldTrim = #"""
function oldTrim(out, MAX_ITEMS, MAX_BYTES) {
    const bytes = text => {
        let n = 0;
        for (const ch of text) { const c = ch.codePointAt(0); n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4; }
        return n;
    };
    let start = 0;
    const size = () => bytes(JSON.stringify(out.slice(start)));
    while (start < out.length && (out.length - start > MAX_ITEMS || size() > MAX_BYTES)) {
        const row = out[start].i;
        let next = start;
        while (next < out.length && out[next].i === row) { next += 1; }
        if (next >= out.length) { break; }
        start = next;
    }
    return start;
}
"""#

/// Builders for made-up items: `turn(i, text)`, and `exact(items, bytes)`, which
/// pads the last item so the items' JSON is exactly that many (ASCII) bytes.
private let trimHelpers = #"""
function turn(i, text) { return { i: i, role: "you", at: 1791833000000, text: text, cut: false, files: [] }; }
function exact(items, target) {
    var gap = target - JSON.stringify(items).length;
    items[items.length - 1].text += "x".repeat(gap);
    return items;
}
function repeated(count, make) { var list = []; for (var n = 0; n < count; n++) { list.push(make(n)); } return list; }
"""#

struct HistoryTrimFixture: Sendable, CustomTestStringConvertible {
    let name: String
    /// A JavaScript expression for the page's items.
    let items: String
    var testDescription: String { name }

    static let all: [HistoryTrimFixture] = [
        HistoryTrimFixture(name: "many small rows", items: #"repeated(500, function (n) { return { i: n, kind: "helper" }; })"#),
        HistoryTrimFixture(name: "many small rows over the bytes alone",
                    items: #"repeated(1500, function (n) { return { i: n, kind: "steps", line: "Ran a command", failed: false }; })"#),
        HistoryTrimFixture(name: "few large rows", items: #"repeated(12, function (n) { return turn(n, "界".repeat(6000)); })"#),
        HistoryTrimFixture(name: "a run of one row straddling the cap", items: #"""
            (function () {
                var items = [];
                for (var row = 0; row < 30; row++) { for (var k = 0; k < 6; k++) { items.push(turn(row, "é".repeat(1200))); } }
                return items;
            })()
            """#),
        HistoryTrimFixture(name: "exactly at the cap",
                    items: #"exact(repeated(40, function (n) { return turn(n, "a".repeat(1500)); }), 65536)"#),
        HistoryTrimFixture(name: "one byte over the cap",
                    items: #"exact(repeated(40, function (n) { return turn(n, "a".repeat(1500)); }), 65537)"#),
        HistoryTrimFixture(name: "one byte under the cap",
                    items: #"exact(repeated(40, function (n) { return turn(n, "a".repeat(1500)); }), 65535)"#),
        HistoryTrimFixture(name: "one row over the cap alone", items: #"repeated(5, function (n) { return turn(7, "界".repeat(30000)); })"#),
        HistoryTrimFixture(name: "a mix of one to four byte characters", items: #"""
            (function () {
                var seed = 12345, items = [], row = 0;
                var next = function () { seed = (seed * 1103515245 + 12345) % 2147483648; return seed; };
                var glyphs = ["a", "é", "界", "😀"];
                for (var n = 0; n < 160; n++) {
                    if (next() % 3 === 0) { row += 1; }
                    var text = "", length = 100 + next() % 900;
                    for (var k = 0; k < length; k++) { text += glyphs[next() % 4]; }
                    items.push(turn(row, text));
                }
                return items;
            })()
            """#),
        HistoryTrimFixture(name: "none at all", items: "[]"),
    ]
}

struct HistoryTrimAnswer: Decodable {
    let fresh: Int
    let old: Int
    let count: Int
    let length: Int
}

struct HistoryTrimTests {
    private func compare(_ items: String, maxItems: Int, maxBytes: Int) -> HistoryTrimAnswer? {
        let script = PageScript(HistoryReaderScript.trim + oldTrim + trimHelpers)
        let json = script.evaluate("""
        (function () {
            var out = \(items);
            return JSON.stringify({ fresh: benchTrimHistory(out, \(maxItems), \(maxBytes)),
                                    old: oldTrim(out, \(maxItems), \(maxBytes)), count: out.length, length: JSON.stringify(out).length });
        })()
        """)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        return json.flatMap { try? JSONDecoder().decode(HistoryTrimAnswer.self, from: Data($0.utf8)) }
    }

    @Test(arguments: HistoryTrimFixture.all)
    func theLinearTrimKeepsExactlyWhatTheOldRuleKept(_ fixture: HistoryTrimFixture) throws {
        for (maxItems, maxBytes) in [(60, 65536), (1_000_000, 65536), (1_000_000, 16384), (7, 65536), (1, 100)] {
            let both = try #require(compare(fixture.items, maxItems: maxItems, maxBytes: maxBytes), "\(maxItems) \(maxBytes)")
            #expect(both.fresh == both.old, "\(fixture.name) at \(maxItems) items, \(maxBytes) bytes")
        }
    }

    @Test func theCapIsInclusiveToTheByte() throws {
        let at = try #require(compare(HistoryTrimFixture.all[4].items, maxItems: 60, maxBytes: 65536))
        #expect(at.length == 65536 && at.fresh == 0 && at.old == 0, "exactly at the cap nothing goes")
        let over = try #require(compare(HistoryTrimFixture.all[5].items, maxItems: 60, maxBytes: 65536))
        #expect(over.length == 65537 && over.fresh == 1 && over.old == 1, "one byte over, the oldest row goes")
        let under = try #require(compare(HistoryTrimFixture.all[6].items, maxItems: 60, maxBytes: 65536))
        #expect(under.length == 65535 && under.fresh == 0)
        // Rows over the cap drop whole while a run of one row is never split.
        let straddle = try #require(compare(HistoryTrimFixture.all[3].items, maxItems: 1_000_000, maxBytes: 65536))
        #expect(straddle.fresh % 6 == 0 && straddle.fresh > 0)
        let alone = try #require(compare(HistoryTrimFixture.all[7].items, maxItems: 60, maxBytes: 65536))
        #expect(alone.fresh == 0 && alone.length > 65536, "the last row is kept however big")
        let many = try #require(compare(HistoryTrimFixture.all[0].items, maxItems: 60, maxBytes: 65536))
        #expect(many.fresh == 440)
    }

    /// Each item's JSON is counted once, and the remainder is never stringified.
    @Test func everyItemIsCountedOnceAndTheRemainderNever() throws {
        let script = PageScript(HistoryReaderScript.trim + trimHelpers)
        let json = script.evaluate("""
        (function () {
            var out = repeated(60, function (n) { return turn(n, "界".repeat(700)); });
            var calls = 0, arrays = 0, real = JSON.stringify;
            JSON.stringify = function (value) { calls += 1; if (Array.isArray(value)) { arrays += 1; } return real.apply(JSON, arguments); };
            var start = benchTrimHistory(out, 60, 65536);
            JSON.stringify = real;
            return real({ start: start, calls: calls, arrays: arrays, count: out.length });
        })()
        """)
        let answer = try #require(json.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Int] })
        #expect(answer["count"] == 60)
        #expect((answer["start"] ?? 0) > 20, "the bytes, not the count, trimmed it")
        #expect(answer["calls"] == 60, "one stringify for each item")
        #expect(answer["arrays"] == 0)
    }

    /// The whole projection, with the old rule swapped in for the new one.
    @Test func theProjectionIsByteIdenticalWithTheOldRule() throws {
        let wide = String(repeating: "界", count: 1990)
        let pages: [(rows: String, total: Int, base: Int)] = [
            ("[" + (0..<50).map { ReaderFixture.userRow("\($0) \(wide)", at: ts + $0) }.joined(separator: ",") + "]", 50, 0),
            ("[" + (0..<80).map { ReaderFixture.userRow("Made-up question \($0)", at: ts + $0) }.joined(separator: ",") + "]", 180, 100),
            ("[" + (0..<50).map { ReaderFixture.userRow("\($0) " + String(repeating: "é", count: 150 * ($0 % 14)), at: ts + $0) }.joined(separator: ",") + "]", 50, 0),
            ("[" + (0..<3).map { ReaderFixture.userRow("\($0) \(wide)", at: ts + $0) }.joined(separator: ",") + "]", 3, 0),
        ]
        var trimmed = 0
        for (rows, total, base) in pages {
            let script = PageScript(HistoryReaderScript.projection + oldTrim)
            script.set("__page", #"{"total": \#(total), "messages": \#(rows)}"#)
            let call = "JSON.stringify(benchProjectHistory(JSON.parse(__page), \(base)))"
            let fresh = try #require(script.evaluate(call))
            script.evaluate("benchTrimHistory = oldTrim;")
            let old = try #require(script.evaluate(call))
            #expect(script.exception == nil)
            #expect(fresh == old)
            #expect(fresh != "null")
            let from = (try? JSONSerialization.jsonObject(with: Data(fresh.utf8)) as? [String: Any])?["from"] as? Int
            if let from, from > base { trimmed += 1 }
        }
        #expect(trimmed == 3, "three of the pages were over a cap")
    }
}

// MARK: A made-up page that streams

/// A page with a fetch that streams (`body.getReader()` of `Uint8Array`s, a
/// `Content-Length`, `cancel`), the abort map's controller, a `TextDecoder`
/// that reads ASCII, and clocks and yields that can be switched on one by one.
/// Every body and reader records what was done to it.
private final class StreamPage {
    let script = PageScript(StreamPage.prelude)

    static let prelude = #"""
    var __events = [], __requests = [], __specs = {}, __pending = {}, __bodies = [], __results = {}, __queue = [];
    var __clock = 0, __fetchStep = 0, __parseStep = 0, __fromCalls = 0, __controllers = 0, __manual = false, __quiet = false;
    function __Signal() { this.aborted = false; this.listeners = []; }
    __Signal.prototype.addEventListener = function (type, listener) { if (type === "abort") { this.listeners.push(listener); } };
    __Signal.prototype.fire = function () {
        if (this.aborted) { return; }
        this.aborted = true;
        var all = this.listeners;
        this.listeners = [];
        for (var i = 0; i < all.length; i++) { all[i](); }
    };
    var AbortController = function () { __controllers += 1; this.signal = new __Signal(); };
    AbortController.prototype.abort = function () { this.signal.fire(); };
    var AbortSignal = function () {};
    AbortSignal.timeout = function () { return undefined; };
    AbortSignal.any = function (signals) {
        var either = new __Signal();
        for (var i = 0; i < signals.length; i++) { signals[i].addEventListener("abort", function () { either.fire(); }); }
        return either;
    };
    var document = { cookie: "" };
    // Reads ASCII; a big chunk stands for spaces.
    var TextDecoder = function () {};
    TextDecoder.prototype.decode = function (bytes) {
        if (!bytes) { return ""; }
        if (bytes.length > 65536) { return new Array(bytes.length + 1).join(" "); }
        var text = "";
        for (var i = 0; i < bytes.length; i++) { text += String.fromCharCode(bytes[i]); }
        return text;
    };
    // `spec`: {status, length (the Content-Length), chunks (a string, a count of bytes, or {raw}), noBody, hold}.
    function __response(spec) {
        var state = { gotReader: false, reads: 0, readerCancelled: false, bodyCancelled: false, textCalled: false };
        __bodies.push(state);
        var chunks = spec.chunks || [], next = 0;
        var bytes = function (chunk) {
            if (typeof chunk === "number") { return new Uint8Array(chunk); }
            if (chunk && chunk.raw !== undefined) { return chunk.raw; }
            var out = new Uint8Array(chunk.length);
            for (var i = 0; i < chunk.length; i++) { out[i] = chunk.charCodeAt(i); }
            return out;
        };
        var status = spec.status === undefined ? 200 : spec.status;
        return {
            status: status, ok: status >= 200 && status < 300,
            headers: { get: function (name) { return String(name).toLowerCase() === "content-length" && spec.length !== undefined ? String(spec.length) : null; } },
            body: spec.noBody ? null : {
                getReader: function () {
                    state.gotReader = true;
                    return {
                        read: function () {
                            state.reads += 1;
                            if (next >= chunks.length) { return Promise.resolve({ done: true, value: undefined }); }
                            return Promise.resolve({ done: false, value: bytes(chunks[next++]) });
                        },
                        cancel: function () { state.readerCancelled = true; return Promise.resolve(); }
                    };
                },
                cancel: function () { state.bodyCancelled = true; return Promise.resolve(); }
            },
            text: function () {
                state.textCalled = true;
                return Promise.resolve(chunks.map(function (c) { return typeof c === "number" ? " ".repeat(c) : c; }).join(""));
            }
        };
    }
    var fetch = function (path, init) {
        __requests.push({ path: path, cache: init && init.cache });
        var spec = __specs[path];
        return new Promise(function (resolve, reject) {
            if (spec === undefined) { reject(new Error("no answer for " + path)); return; }
            var signal = init && init.signal;
            var abort = function () { reject(new Error("AbortError")); };
            if (signal) { if (signal.aborted) { abort(); return; } signal.addEventListener("abort", abort); }
            var answer = function () { __clock += __fetchStep; resolve(__response(spec)); };
            if (spec.hold) { __pending[path] = answer; } else { answer(); }
        });
    };
    function __release(path) { var go = __pending[path]; delete __pending[path]; go(); }
    function __later(label, run) { __events.push(label); if (__manual) { __queue.push(run); } else { run(); } }
    function __tick() { var run = __queue.shift(); if (run) { run(); } return __queue.length; }
    function __useTimeout() { setTimeout = function (run, ms) { __later("timeout:" + ms, run); return 1; }; }
    function __useIdle() {
        requestIdleCallback = function (run, options) { __later("idle:" + (options && options.timeout), function () { run({ didTimeout: false }); }); return 1; };
    }
    function __useClock() {
        performance = { now: function () { return __clock; } };
        var from = Array.from;
        Array.from = function () { __fromCalls += 1; __clock += 1; return from.apply(Array, arguments); };
    }
    function __useLog() {
        var parse = JSON.parse, stringify = JSON.stringify;
        JSON.parse = function () { if (!__quiet) { __events.push("parse"); } __clock += __parseStep; return parse.apply(JSON, arguments); };
        JSON.stringify = function () { if (!__quiet) { __events.push("stringify"); } return stringify.apply(JSON, arguments); };
    }
    function __json(value) { __quiet = true; try { return JSON.stringify(value); } finally { __quiet = false; } }
    """#

    func give(_ requestPath: String, _ spec: String) {
        script.evaluate("__specs[\(jsLiteral(requestPath))] = \(spec);")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    /// The body of a GET, whole or in `pieces`, with a declared length when asked.
    func give(_ requestPath: String, body: String, pieces: Int = 1, length: Int? = nil, status: Int = 200) {
        let size = max(1, body.count / pieces)
        let chunks = stride(from: 0, to: body.count, by: size).map { start -> String in
            let from = body.index(body.startIndex, offsetBy: start)
            let to = body.index(from, offsetBy: min(size, body.count - start))
            return jsLiteral(String(body[from..<to]))
        }
        give(requestPath, "{ status: \(status), \(length.map { "length: \($0), " } ?? "")chunks: [\(chunks.joined(separator: ", "))] }")
    }

    func use(_ switches: String...) {
        for one in switches { script.evaluate("\(one)();") }
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    func manual(_ on: Bool = true) { script.evaluate("__manual = \(on);") }

    func set(_ name: String, _ number: Double) { script.evaluate("\(name) = \(number);") }

    /// Runs `body` as `callAsyncJavaScript` would, under `label`.
    func start(_ label: String = "a", body: String, arguments: [(String, String)]) {
        let names = arguments.map(\.0).joined(separator: ", ")
        let values = arguments.map(\.1).joined(separator: ", ")
        script.set("__label", label)
        script.evaluate("""
        (function (label) {
            __results[label] = null;
            (async function (\(names)) {
            \(body)
            })(\(values)).then(function (v) { __results[label] = v; }, function (e) { __results[label] = "threw: " + e; });
        })(__label);
        """)
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    func history(_ label: String = "a", before: String = "null", known: String = "null", rows: String = "null",
                 nonce: String = "null", frame: String = "\"\(root)\"") {
        start(label, body: HistoryReaderScript.pageBody,
              arguments: [("frameId", frame), ("before", before), ("knownTotal", known), ("rows", rows), ("nonce", nonce)])
    }

    func turn(_ label: String = "a", index: Int, nonce: String = "null") {
        start(label, body: HistoryReaderScript.turnBody, arguments: [("frameId", "\"\(root)\""), ("index", "\(index)"), ("nonce", nonce)])
    }

    func showing(_ label: String = "a", before: String, ids: [String], nonce: String = "null") {
        start(label, body: HistoryReaderScript.showingBody,
              arguments: [("frameId", "\"\(root)\""), ("before", before), ("versionIds", jsLiteralArray(ids)), ("nonce", nonce)])
    }

    private func jsLiteralArray(_ items: [String]) -> String { "[" + items.map(jsLiteral).joined(separator: ", ") + "]" }

    func result(_ label: String = "a") -> String? {
        script.set("__label", label)
        return script.evaluate("__results[__label]")
    }

    /// Runs the oldest waiting yield. The page goes on after it, in the same call.
    func tick() { script.evaluate("__tick();") }

    var waiting: Int { Int(script.evaluate("String(__queue.length)") ?? "") ?? -1 }

    private func list<T: Decodable>(_ expression: String, as type: T.Type) -> T? {
        script.evaluate("__json(\(expression))").flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    var events: [String] { list("__events", as: [String].self) ?? [] }
    var requests: [String] { list("__requests.map(function (r) { return r.path; })", as: [String].self) ?? [] }
    var filed: [String] { list("Object.keys(globalThis.\(ArtifactReaderScript.readsName) || {}).sort()", as: [String].self) ?? [] }
    var controllers: Int { Int(script.evaluate("String(__controllers)") ?? "") ?? -1 }
    var fromCalls: Int { Int(script.evaluate("String(__fromCalls)") ?? "") ?? -1 }

    struct Body: Decodable {
        let gotReader: Bool
        let reads: Int
        let readerCancelled: Bool
        let bodyCancelled: Bool
        let textCalled: Bool
    }

    var bodies: [Body] { list("__bodies", as: [Body].self) ?? [] }

    func release(_ requestPath: String) {
        script.set("__path", requestPath)
        script.evaluate("__release(__path);")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    func abort(_ nonce: String) -> String? {
        script.set("__nonce", nonce)
        script.evaluate("""
        __aborted = null;
        (async function (nonce) {
        \(ArtifactReaderScript.abort)
        })(__nonce).then(function (v) { __aborted = String(v); });
        """)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        return script.evaluate("__aborted")
    }
}

private func outcome(_ raw: String?) -> HistoryReaderScript.Outcome? {
    raw.map { HistoryReaderScript.outcome(of: Data($0.utf8)) }
}

// MARK: 2. Rows per page

struct HistoryRowsArgumentTests {
    private func reply(from: Int, total: Int, count: Int) -> PageScript.Answer {
        PageScript.Answer(status: 200, body: pageJSON(from: from, total: total, count: count))
    }

    private func run(before: String, rows: String?, answers: [String: [PageScript.Answer]])
        -> (raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        var arguments = [("frameId", "\"\(root)\""), ("before", before), ("knownTotal", "null")]
        if let rows { arguments.append(("rows", rows)) }
        let (raw, requests) = script.runPage(HistoryReaderScript.pageBody, arguments: arguments, answers: answers)
        #expect(script.exception == nil)
        return (raw, requests)
    }

    @Test func anEarlierPageIsTheRowsGivenBeforeIt() {
        // before 120: 50 rows from 70, 25 rows from 95, one row from 119.
        for (rows, from, limit) in [(50, 70, 50), (25, 95, 25), (1, 119, 1), (13, 107, 13)] {
            let (raw, requests) = run(before: "120", rows: "\(rows)",
                                      answers: [path("from=\(from)&limit=\(limit)"): [reply(from: from, total: 300, count: limit)]])
            #expect(requests.map(\.path) == [path("from=\(from)&limit=\(limit)")], "rows \(rows)")
            #expect(requests.allSatisfy { HistoryReaderScript.isAllowedPath($0.path) })
            guard case .read(let page, _)? = outcome(raw) else { Issue.record("not read: \(raw ?? "nil")"); continue }
            #expect(page.from == from && page.items.count == limit)
        }
        // Near the start the page stops at row 0, whatever `rows` is.
        for rows in [25, 50] {
            let (_, requests) = run(before: "20", rows: "\(rows)", answers: [path("from=0&limit=20"): [reply(from: 0, total: 300, count: 20)]])
            #expect(requests.map(\.path) == [path("from=0&limit=20")], "rows \(rows)")
        }
    }

    /// A page with `before` asks for exactly `rows`: a reply of more is no reply.
    @Test func aReplyOfMoreRowsThanAskedForIsUnreadable() {
        let (raw, _) = run(before: "120", rows: "25", answers: [path("from=95&limit=25"): [reply(from: 95, total: 300, count: 26)]])
        #expect(outcome(raw) == .unreadable)
    }

    /// The first read is the tail's `from=-12&limit=12` whatever `rows` is, and
    /// then the rows before it, up to 50: `rows` is for reads with `before`.
    @Test func theFirstReadIsTheTailWhateverRowsSays() {
        let answers = [path("from=-12&limit=12"): [reply(from: 88, total: 100, count: 12)],
                       path("from=50&limit=38"): [reply(from: 50, total: 100, count: 38)]]
        for rows in ["25", "50", "1", "null"] {
            let (raw, requests) = run(before: "null", rows: rows, answers: answers)
            #expect(requests.map(\.path) == [path("from=-12&limit=12"), path("from=50&limit=38")], "rows \(rows)")
            #expect(requests.allSatisfy { HistoryReaderScript.isAllowedPath($0.path) })
            guard case .read(let page, _)? = outcome(raw) else { Issue.record("not read: \(raw ?? "nil")"); continue }
            #expect(page.items.count == 50 && page.from == 50)
        }
    }

    @Test func noRowsAtAllReads50AsItAlwaysDid() {
        let answers = [path("from=70&limit=50"): [reply(from: 70, total: 300, count: 50)]]
        #expect(run(before: "120", rows: nil, answers: answers).requests.map(\.path) == [path("from=70&limit=50")])
        #expect(run(before: "120", rows: "null", answers: answers).requests.map(\.path) == [path("from=70&limit=50")])
    }

    @Test func rowsOutOfShapeAreRefusedBeforeAnyFetch() {
        for rows in ["0", "51", "-1", "1.5", "\"25\"", "true", "[25]", "1000000000"] {
            let (raw, requests) = run(before: "120", rows: rows, answers: [:])
            #expect(raw == #"{"outcome":"refused"}"#, "rows \(rows)")
            #expect(requests.isEmpty)
            #expect(outcome(raw) == .unreadable)
            // Nor does a first read ask for a thing.
            let first = run(before: "null", rows: rows, answers: [:])
            #expect(first.raw == #"{"outcome":"refused"}"# && first.requests.isEmpty, "first read, rows \(rows)")
        }
    }

    @Test func theArgumentsAreCheckedInSwiftToo() {
        let nonce = "nonce-1"
        func refused(frameID: String = root, before: Int? = nil, rows: Int = 50, nonce: String? = nil) -> Bool {
            do { try HistoryReaderScript.check(frameID: frameID, before: before, rows: rows, nonce: nonce); return false }
            catch WebAPIError.notAllowed { return true } catch { return false }
        }
        #expect(!refused() && !refused(before: 1, rows: 1) && !refused(before: 9_999_999, rows: 25, nonce: nonce))
        for rows in [0, 51, -1, 100, Int.max, Int.min] { #expect(refused(rows: rows), "rows \(rows)") }
        for before in [0, -1, 10_000_000] { #expect(refused(before: before), "before \(before)") }
        #expect(refused(frameID: "../../usage") && refused(frameID: String(root.dropLast())) && refused(frameID: ""))
        #expect(HistoryReaderScript.pageRows == 50)
    }
}

// MARK: 3. Abortable

struct HistoryAbortTests {
    private let heldHistory = path("from=70&limit=50")

    @Test func aNonceFilesTheControllerAndAnAbortEndsTheHistoryFetch() {
        let page = StreamPage()
        page.give(heldHistory, "{ hold: true }")
        page.history(before: "120", nonce: "\"nonce-history-1\"")
        #expect(page.filed == ["nonce-history-1"])
        #expect(page.controllers == 1)
        #expect(page.result() == nil, "the fetch is pending")
        #expect(page.abort("nonce-other") == "false" && page.filed == ["nonce-history-1"], "another nonce is let be")
        #expect(page.abort("nonce-history-1") == "true")
        #expect(page.result() == #"{"outcome":"cancelled"}"#)
        #expect(outcome(page.result()) == .cancelled)
        #expect(page.filed.isEmpty, "its entry is gone")
        #expect(page.abort("nonce-history-1") == "false")
    }

    @Test func theSameForTheTailAndTheEarlierPageOfAFirstRead() {
        let page = StreamPage()
        page.give(path("from=-12&limit=12"), body: pageJSON(from: 88, total: 100, count: 12))
        page.give(path("from=50&limit=38"), "{ hold: true }")
        page.history(nonce: "\"nonce-history-2\"")
        #expect(page.requests == [path("from=-12&limit=12"), path("from=50&limit=38")])
        #expect(page.result() == nil)
        #expect(page.abort("nonce-history-2") == "true")
        #expect(outcome(page.result()) == .cancelled)
        #expect(page.filed.isEmpty)
    }

    @Test func aNonceFilesTheControllerAndAnAbortEndsTheTurnFetch() {
        let page = StreamPage()
        page.give(path("from=7&limit=1"), "{ hold: true }")
        page.turn(index: 7, nonce: "\"nonce-turn-1\"")
        #expect(page.filed == ["nonce-turn-1"])
        #expect(page.result() == nil)
        #expect(page.abort("nonce-turn-1") == "true")
        #expect(outcome(page.result()) == .cancelled)
        #expect(page.filed.isEmpty)
    }

    @Test func aReadThatEndsTakesItsEntryOutAndAnswersAsItShould() {
        let page = StreamPage()
        page.give(heldHistory, body: pageJSON(from: 70, total: 300, count: 50))
        page.history("read", before: "120", nonce: "\"nonce-history-3\"")
        guard case .read(let read, _)? = outcome(page.result("read")) else { Issue.record("not read: \(page.result("read") ?? "nil")"); return }
        #expect(read.from == 70 && read.items.count == 50)
        #expect(page.filed.isEmpty)
        // Whatever ends a read takes its entry out: a refusal, a 401, a 500, a body too big, a refused argument.
        page.give(path("from=0&limit=1"), body: "{}", status: 401)
        page.history("lost", before: "1", nonce: "\"nonce-history-4\"")
        #expect(outcome(page.result("lost")) == .lost)
        page.give(path("from=0&limit=2"), body: "", status: 500)
        page.history("down", before: "2", nonce: "\"nonce-history-5\"")
        #expect(outcome(page.result("down")) == .unreadable)
        page.give(path("from=0&limit=3"), "{ length: 2097153, chunks: [] }")
        page.history("big", before: "3", nonce: "\"nonce-history-6\"")
        #expect(outcome(page.result("big")) == .tooBig)
        page.history("refused", before: "0", nonce: "\"nonce-history-7\"")
        #expect(page.result("refused") == #"{"outcome":"refused"}"#)
        page.history("badRows", before: "3", rows: "99", nonce: "\"nonce-history-8\"")
        #expect(page.result("badRows") == #"{"outcome":"refused"}"#)
        page.give(path("from=9&limit=1"), body: "{}", status: 401)
        page.turn("turnLost", index: 9, nonce: "\"nonce-turn-2\"")
        #expect(outcome(page.result("turnLost")) == .lost)
        page.turn("turnRefused", index: -1, nonce: "\"nonce-turn-3\"")
        #expect(page.result("turnRefused") == #"{"outcome":"refused"}"#)
        #expect(page.filed.isEmpty, "nothing is left filed: \(page.filed)")
    }

    @Test func aReadWithNoNonceOrAMalformedOneFilesNothingAndStillReads() {
        let page = StreamPage()
        page.give(heldHistory, body: pageJSON(from: 70, total: 300, count: 50))
        for (label, nonce) in [("none", "null"), ("bad", "\"../not-a-nonce\""), ("long", "\"\(String(repeating: "a", count: 65))\""),
                               ("number", "7"), ("empty", "\"\"")] {
            page.history(label, before: "120", nonce: nonce)
            #expect(page.filed.isEmpty, "\(label)")
            guard case .read? = outcome(page.result(label)) else { Issue.record("\(label): \(page.result(label) ?? "nil")"); continue }
        }
        #expect(page.controllers == 0)
        #expect(page.abort("../not-a-nonce") == "false")
        // No nonce argument at all, as the phone's reads and the tests before this one run it.
        page.start("absent", body: HistoryReaderScript.pageBody,
                   arguments: [("frameId", "\"\(root)\""), ("before", "120"), ("knownTotal", "null")])
        guard case .read? = outcome(page.result("absent")) else { Issue.record("absent: \(page.result("absent") ?? "nil")"); return }
        #expect(page.controllers == 0 && page.filed.isEmpty)
    }

    @Test func theNonceIsCheckedInSwiftBeforeThePageIsAsked() {
        func refused(_ nonce: String?) -> Bool {
            do { try HistoryReaderScript.check(frameID: root, nonce: nonce); return false }
            catch WebAPIError.notAllowed { return true } catch { return false }
        }
        #expect(!refused(nil) && !refused(ArtifactReadAbort.makeNonce()) && !refused("A-b-9") && !refused(String(repeating: "a", count: 64)))
        for bad in ["", "a b", "a/b", "ä", String(repeating: "a", count: 65), "a_b", "a\n", "../x"] {
            #expect(refused(bad), "\(bad)")
        }
    }
}

/// The Swift side of an abort: cancelling the task asks the page to abort the
/// nonce's fetch, and a cancelled task ends in `CancellationError`.
@MainActor
struct HistoryReadAbortTests {
    /// Stands in for the page: an answer that comes when it is let, and that
    /// doesn't care that the task was cancelled.
    @MainActor
    private final class Answer {
        private var waiting: CheckedContinuation<String, Never>?
        var aborted: [String] = []
        var asked = 0

        func ask() async -> String {
            asked += 1
            return await withCheckedContinuation { waiting = $0 }
        }

        func give(_ value: String) {
            waiting?.resume(returning: value)
            waiting = nil
        }

        var isWaiting: Bool { waiting != nil }
    }

    private func ready(_ answer: Answer) async {
        for _ in 0..<1_000 where !answer.isWaiting { await Task.yield() }
    }

    @Test func cancellingTheTaskAbortsItsNonceAndTheReadEndsInCancellation() async {
        let answer = Answer()
        let task = Task { @MainActor in
            try await HistoryReadAbort.run(nonce: "nonce-cancel-1", abort: { answer.aborted.append($0); answer.give("cancelled") }) {
                await answer.ask()
            }
        }
        await ready(answer)
        #expect(answer.isWaiting && answer.aborted.isEmpty)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("a cancelled read returned")
        } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect(answer.aborted == ["nonce-cancel-1"])
    }

    /// The page answered at the very moment of the cancel: still a cancelled read.
    @Test func aReadCancelledWhileThePageAnswersIsStillCancelled() async {
        let answer = Answer()
        let task = Task { @MainActor in
            try await HistoryReadAbort.run(nonce: "nonce-cancel-2", abort: { _ in }) { await answer.ask() }
        }
        await ready(answer)
        task.cancel()
        answer.give("a page")
        do {
            _ = try await task.value
            Issue.record("a cancelled read returned")
        } catch is CancellationError {} catch { Issue.record("\(error)") }
    }

    @Test func aTaskAlreadyCancelledReadsNothing() async {
        let answer = Answer()
        let task = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            return try await HistoryReadAbort.run(nonce: "nonce-cancel-3", abort: { answer.aborted.append($0) }) { await answer.ask() }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("a cancelled read returned")
        } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect(answer.asked == 0 && answer.aborted.isEmpty)
    }

    @Test func aReadThatIsNotCancelledReturnsAndAbortsNothing() async throws {
        let answer = Answer()
        let task = Task { @MainActor in
            try await HistoryReadAbort.run(nonce: "nonce-cancel-4", abort: { answer.aborted.append($0) }) { await answer.ask() }
        }
        await ready(answer)
        answer.give("a page")
        #expect(try await task.value == "a page")
        #expect(answer.aborted.isEmpty)
    }

    /// The phone's reads pass no nonce: nothing is aborted and cancelling changes nothing.
    @Test func withoutANonceCancellingLeavesTheReadAlone() async throws {
        let answer = Answer()
        let task = Task { @MainActor in
            try await HistoryReadAbort.run(nonce: nil, abort: { answer.aborted.append($0) }) { await answer.ask() }
        }
        await ready(answer)
        task.cancel()
        answer.give("a page")
        #expect(try await task.value == "a page")
        #expect(answer.aborted.isEmpty)
    }
}

// MARK: 4. The byte cap

struct HistoryByteCapTests {
    private let cap = 2_097_152
    private let onePage = pageJSON(from: 0, total: 1, count: 1)

    private func decoded(_ raw: String?) -> HistoryReaderScript.Outcome? { outcome(raw) }

    @Test func theCapIsTwoMebibytesInSwiftAndInThePage() {
        #expect(HistoryReaderScript.bodyCap == 2_097_152)
        let script = PageScript(HistoryReaderScript.fetcher)
        #expect(script.evaluate("String(BODY_CAP)") == "2097152")
    }

    @Test func aDeclaredLengthOverTheCapIsRefusedUnread() {
        let page = StreamPage()
        page.give(path("from=0&limit=1"), "{ length: \(cap + 1), chunks: [\(jsLiteral(onePage))] }")
        page.history(before: "1")
        #expect(page.result() == #"{"outcome":"tooBig"}"#)
        #expect(decoded(page.result()) == .tooBig)
        let body = page.bodies.first
        #expect(body?.gotReader == false && body?.reads == 0 && body?.textCalled == false, "none of it was read")
        #expect(body?.bodyCancelled == true, "the stream was let go")
        // The length it declares is all that is looked at: a header that isn't a number says nothing.
        let odd = StreamPage()
        odd.give(path("from=0&limit=1"), "{ length: \"lots\", chunks: [\(jsLiteral(onePage))] }")
        odd.history(before: "1")
        guard case .read? = decoded(odd.result()) else { Issue.record("not read: \(odd.result() ?? "nil")"); return }
    }

    @Test func aDeclaredLengthAtTheCapIsRead() {
        let page = StreamPage()
        page.give(path("from=0&limit=1"), body: onePage, length: cap)
        page.history(before: "1")
        guard case .read(let read, _)? = decoded(page.result()) else { Issue.record("not read: \(page.result() ?? "nil")"); return }
        #expect(read.items.count == 1)
        #expect(page.bodies.first?.gotReader == true)
    }

    @Test func aStreamedBodyIsStoppedAtTheCap() {
        let page = StreamPage()
        // No length declared; four 1 MiB chunks: the third would pass the cap.
        page.give(path("from=0&limit=1"), "{ chunks: [1048576, 1048576, 1048576, 1048576] }")
        page.history(before: "1")
        #expect(page.result() == #"{"outcome":"tooBig"}"#)
        let body = page.bodies.first
        #expect(body?.reads == 3, "the third chunk crossed the cap and nothing more was read")
        #expect(body?.readerCancelled == true)
        #expect(body?.textCalled == false)
    }

    @Test func aBodyOfExactlyTheCapIsReadAndOneByteMoreIsNot() {
        let page = StreamPage()
        // Valid JSON and then spaces to the very byte (a big chunk reads as spaces here).
        let padding = cap - onePage.utf8.count
        page.give(path("from=0&limit=1"), "{ chunks: [\(jsLiteral(onePage)), \(padding)] }")
        page.use("__useClock")
        page.history("exact", before: "1")
        guard case .read(_, let timing)? = decoded(page.result("exact")) else { Issue.record("not read: \(page.result("exact") ?? "nil")"); return }
        #expect(timing?.rawBytes == cap)
        let over = StreamPage()
        over.give(path("from=0&limit=1"), "{ chunks: [\(jsLiteral(onePage)), \(padding + 1)] }")
        over.history("over", before: "1")
        #expect(over.result("over") == #"{"outcome":"tooBig"}"#)
    }

    @Test func aBodyThatIsNotBytesIsUnreadableAndLetGo() {
        let page = StreamPage()
        page.give(path("from=0&limit=1"), #"{ chunks: [{ raw: "text, not bytes" }] }"#)
        page.history(before: "1")
        #expect(decoded(page.result()) == .unreadable)
        #expect(page.bodies.first?.readerCancelled == true)
    }

    @Test func theCapReachesEveryPageOfTheTailAndTheTurnAndTheShowingRead() {
        // The tail's second GET.
        let first = StreamPage()
        first.give(path("from=-12&limit=12"), body: pageJSON(from: 88, total: 100, count: 12))
        first.give(path("from=50&limit=38"), "{ length: \(cap + 1), chunks: [] }")
        first.history()
        #expect(decoded(first.result()) == .tooBig)
        #expect(first.requests == [path("from=-12&limit=12"), path("from=50&limit=38")])
        // A turn.
        let turn = StreamPage()
        turn.give(path("from=7&limit=1"), "{ length: \(cap + 1), chunks: [] }")
        turn.turn(index: 7)
        #expect(turn.result() == #"{"outcome":"tooBig"}"#)
        #expect(decoded(turn.result()) == .tooBig)
        // Keep's showing read shares the GET, and answers its own unreadable.
        let ids = ["1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"]
        let showing = StreamPage()
        showing.give(path("from=0&limit=1"), "{ length: \(cap + 1), chunks: [] }")
        showing.showing(before: "1", ids: ids)
        #expect(showing.result() == #"{"outcome":"tooBig"}"#)
        #expect(HistoryReaderScript.showingOutcome(of: Data((showing.result() ?? "").utf8), versions: ids) == .unreadable)
    }

    @Test func swiftTakesTooBigAndCancelledFromThePageAndNothingElseLikeThem() {
        #expect(HistoryReaderScript.outcome(of: Data(#"{"outcome":"tooBig"}"#.utf8)) == .tooBig)
        #expect(HistoryReaderScript.outcome(of: Data(#"{"outcome":"cancelled"}"#.utf8)) == .cancelled)
        for odd in [#"{"outcome":"toobig"}"#, #"{"outcome":"too big"}"#, #"{"outcome":5}"#, "[]", "nope", #"{"outcome":"refused"}"#] {
            #expect(HistoryReaderScript.outcome(of: Data(odd.utf8)) == .unreadable, "\(odd)")
        }
        #expect(RemoteBrowser.HistoryRead.tooBig != .unreadable)
    }
}

// MARK: 5. The yield

struct HistoryYieldTests {
    private let onePage = pageJSON(from: 0, total: 1, count: 1)

    private func onePageRead(_ page: StreamPage) {
        page.give(path("from=0&limit=1"), body: onePage)
    }

    @Test func anIdleCallbackWithAOneSecondTimeoutIsUsedWhenThereIsOne() {
        let page = StreamPage()
        onePageRead(page)
        page.use("__useLog", "__useTimeout", "__useIdle")
        page.manual()
        page.history(before: "1")
        // Waiting at the first yield, before the body is parsed.
        #expect(page.result() == nil && page.waiting == 1)
        #expect(page.events == ["idle:1000"])
        page.tick()
        #expect(page.waiting == 1, "parsed, and waiting again before the projection")
        #expect(page.result() == nil)
        #expect(page.events == ["idle:1000", "parse", "idle:1000"])
        page.tick()
        #expect(page.waiting == 0)
        guard case .read? = outcome(page.result()) else { Issue.record("not read: \(page.result() ?? "nil")"); return }
        let events = page.events
        #expect(events.prefix(3) == ["idle:1000", "parse", "idle:1000"])
        #expect(events.dropFirst(3).allSatisfy { $0 == "stringify" }, "nothing but the projection's own counting after the last yield")
        #expect(!events.contains { $0.hasPrefix("timeout") }, "the timer was not used")
    }

    @Test func setTimeoutZeroIsUsedWithoutAnIdleCallback() {
        let page = StreamPage()
        onePageRead(page)
        page.use("__useLog", "__useTimeout")
        page.manual()
        page.history(before: "1")
        #expect(page.result() == nil && page.events == ["timeout:0"])
        page.tick()
        #expect(page.result() == nil)
        page.tick()
        guard case .read? = outcome(page.result()) else { Issue.record("not read: \(page.result() ?? "nil")"); return }
        #expect(page.events.prefix(3) == ["timeout:0", "parse", "timeout:0"])
        #expect(!page.events.contains { $0.hasPrefix("idle") })
    }

    @Test func aFirstReadYieldsBeforeEachBodyIsParsedAndBeforeItProjects() {
        let page = StreamPage()
        page.give(path("from=-12&limit=12"), body: pageJSON(from: 88, total: 100, count: 12))
        page.give(path("from=50&limit=38"), body: pageJSON(from: 50, total: 100, count: 38))
        page.use("__useLog", "__useTimeout")
        page.manual()
        page.history()
        var steps = 0
        while page.result() == nil, steps < 10 { page.tick(); steps += 1 }
        #expect(steps == 3)
        #expect(page.events.prefix(5) == ["timeout:0", "parse", "timeout:0", "parse", "timeout:0"])
        guard case .read(let read, _)? = outcome(page.result()) else { Issue.record("not read"); return }
        #expect(read.items.count == 50)
    }

    @Test func aTurnYieldsBeforeItParsesToo() {
        let page = StreamPage()
        page.give(path("from=3&limit=1"), body: #"{"from": 3, "total": 10, "messages": [\#(ReaderFixture.userRow("Made-up turn", at: ts))]}"#)
        page.use("__useLog", "__useIdle")
        page.manual()
        page.turn(index: 3)
        #expect(page.result() == nil && page.events == ["idle:1000"])
        page.tick()
        guard case .turn(let turn)? = outcome(page.result()) else { Issue.record("not a turn: \(page.result() ?? "nil")"); return }
        #expect(turn.i == 3 && turn.text == "Made-up turn")
    }

    @Test func withNeitherTheReadGoesStraightThrough() {
        let page = StreamPage()
        onePageRead(page)
        page.use("__useLog")
        page.history(before: "1")
        guard case .read? = outcome(page.result()) else { Issue.record("not read: \(page.result() ?? "nil")"); return }
        #expect(page.events.first == "parse")
    }
}

// MARK: 6. Timing

struct HistoryTimingTests {
    private let tail = pageJSON(from: 88, total: 100, count: 12)
    private let earlier = pageJSON(from: 50, total: 100, count: 38)

    private func firstRead(_ page: StreamPage) {
        page.give(path("from=-12&limit=12"), body: tail, pieces: 3)
        page.give(path("from=50&limit=38"), body: earlier, pieces: 5)
    }

    @Test func thePageMeasuresItsFetchesParsesProjectionBytesAndRows() throws {
        let page = StreamPage()
        firstRead(page)
        page.use("__useClock", "__useLog")
        page.set("__fetchStep", 40.4)
        page.set("__parseStep", 5.2)
        page.history()
        let raw = try #require(page.result())
        guard case .read(let read, let timing?) = HistoryReaderScript.outcome(of: Data(raw.utf8)) else { Issue.record("not read with a timing: \(raw.prefix(80))"); return }
        #expect(read.items.count == 50)
        // Two GETs of 40.4 ms, two parses of 5.2 ms (80.8 and 10.4), each projection step a millisecond.
        #expect(timing == HistoryTiming(fetchMs: 81, parseMs: 10, projectMs: page.fromCalls,
                                        rawBytes: tail.utf8.count + earlier.utf8.count, rows: 50))
        #expect(timing.projectMs > 0)
        // Beside the page, whole numbers.
        let json = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        #expect(Set(json.keys) == ["outcome", "page", "timing"])
        let object = try #require(json["timing"] as? [String: Any])
        #expect(Set(object.keys) == ["fetchMs", "parseMs", "projectMs", "rawBytes", "rows"])
        #expect(raw.contains(#""fetchMs":81"#) && raw.contains(#""parseMs":10"#), "integers, as written: \(raw.suffix(120))")
    }

    @Test func anEarlierPageCountsItsOneGet() throws {
        let page = StreamPage()
        page.give(path("from=95&limit=25"), body: pageJSON(from: 95, total: 300, count: 25))
        page.use("__useClock", "__useLog")
        page.set("__fetchStep", 12.0)
        page.set("__parseStep", 3.0)
        page.history(before: "120", rows: "25")
        guard case .read(_, let timing?)? = outcome(page.result()) else { Issue.record("no timing: \(page.result() ?? "nil")"); return }
        #expect(timing.fetchMs == 12 && timing.parseMs == 3 && timing.rows == 25)
        #expect(timing.rawBytes == pageJSON(from: 95, total: 300, count: 25).utf8.count)
    }

    @Test func withoutAClockTheMillisecondsAreZeroAndTheCountsStayReal() throws {
        let page = StreamPage()
        firstRead(page)
        page.history()
        guard case .read(_, let timing?)? = outcome(page.result()) else { Issue.record("no timing: \(page.result() ?? "nil")"); return }
        #expect(timing == HistoryTiming(fetchMs: 0, parseMs: 0, projectMs: 0, rawBytes: tail.utf8.count + earlier.utf8.count, rows: 50))
        // The page that falls back to the whole text counts the text.
        let script = PageScript()
        let (raw, _) = script.runPage(HistoryReaderScript.pageBody,
                                      arguments: [("frameId", "\"\(root)\""), ("before", "null"), ("knownTotal", "null")],
                                      answers: [path("from=-12&limit=12"): [PageScript.Answer(status: 200, body: pageJSON(from: 0, total: 5, count: 5))]])
        guard case .read(_, let counted?)? = outcome(raw) else { Issue.record("no timing: \(raw ?? "nil")"); return }
        #expect(counted.rows == 5 && counted.rawBytes == pageJSON(from: 0, total: 5, count: 5).count)
    }

    @Test func rowsAreTheMessagesOfThePageNotItsItems() throws {
        // Twelve tool calls in a row fold into one line of steps.
        let calls = (0..<12).map { n in
            #"{"role": "assistant", "_ts": \#(ts + n), "content": [{"type": "tool_use", "id": "t\#(n)", "name": "bash", "input": {}}]}"#
        }.joined(separator: ",")
        let page = StreamPage()
        page.give(path("from=0&limit=12"), body: #"{"from": 0, "total": 12, "messages": [\#(calls)]}"#)
        page.history(before: "12")
        guard case .read(let read, let timing?)? = outcome(page.result()) else { Issue.record("no timing: \(page.result() ?? "nil")"); return }
        #expect(read.items.count == 1)
        #expect(timing.rows == 12)
    }

    // MARK: What Swift takes

    private let onePage = #"{"total":1,"from":0,"items":[{"i":0,"kind":"helper"}]}"#
    private let page = HistoryPage(total: 1, from: 0, items: [.helper(i: 0)])

    private func read(_ timing: String?) -> HistoryReaderScript.Outcome {
        let extra = timing.map { #","timing":\#($0)"# } ?? ""
        return HistoryReaderScript.outcome(of: Data(#"{"outcome":"read","page":\#(onePage)\#(extra)}"#.utf8))
    }

    @Test func aTimingInShapeIsParsedBesideThePage() {
        #expect(read(#"{"fetchMs":120,"parseMs":4,"projectMs":0,"rawBytes":812345,"rows":50}"#)
                == .read(page, timing: HistoryTiming(fetchMs: 120, parseMs: 4, projectMs: 0, rawBytes: 812_345, rows: 50)))
        #expect(read(#"{"fetchMs":0,"parseMs":0,"projectMs":0,"rawBytes":0,"rows":0,"more":"ignored"}"#)
                == .read(page, timing: HistoryTiming(fetchMs: 0, parseMs: 0, projectMs: 0, rawBytes: 0, rows: 0)))
        // A whole number written as 4.0 is one.
        #expect(read(#"{"fetchMs":4.0,"parseMs":4,"projectMs":4,"rawBytes":4,"rows":4}"#)
                == .read(page, timing: HistoryTiming(fetchMs: 4, parseMs: 4, projectMs: 4, rawBytes: 4, rows: 4)))
    }

    @Test func aMissingOrMalformedTimingIsNoTimingAndThePageStillReads() {
        let all = #""fetchMs":1,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5"#
        let bad: [String?] = [
            nil, "null", "[]", "5", #""timing""#, "{}",
            #"{"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":2,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":2,"projectMs":3,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":2,"projectMs":3,"rawBytes":4}"#,
            #"{"fetchMs":"1","parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1.5,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":-1,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":-2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":2,"projectMs":-3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":2,"projectMs":3,"rawBytes":-4,"rows":5}"#,
            #"{"fetchMs":1,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":-5}"#,
            #"{"fetchMs":true,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":null,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":[1],"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
            #"{"fetchMs":1e300,"parseMs":2,"projectMs":3,"rawBytes":4,"rows":5}"#,
        ]
        for timing in bad {
            #expect(read(timing) == .read(page, timing: nil), "\(timing ?? "missing")")
        }
        #expect(read(#"{\#(all)}"#) == .read(page, timing: HistoryTiming(fetchMs: 1, parseMs: 2, projectMs: 3, rawBytes: 4, rows: 5)))
        // The page itself is still checked: a page out of shape is unreadable, timing or not.
        #expect(HistoryReaderScript.outcome(of: Data(#"{"outcome":"read","page":{"total":1,"from":4,"items":[]},"timing":{\#(all)}}"#.utf8))
                == .unreadable)
    }

    @Test func theLoggedLineIsTheFiveNumbersAndNothingElse() {
        let line = HistoryTiming(fetchMs: 120, parseMs: 4, projectMs: 7, rawBytes: 812_345, rows: 50).line
        #expect(line == "history read: fetch 120 ms, parse 4 ms, project 7 ms, 812345 bytes, 50 rows")
        #expect(line.range(of: #"^history read: fetch \d+ ms, parse \d+ ms, project \d+ ms, \d+ bytes, \d+ rows$"#, options: .regularExpression) != nil)
    }
}

// MARK: The phone's routes take tooBig as they take unreadable

@MainActor
struct HistoryTooBigPhoneTests {
    @MainActor
    private final class Fake {
        var history: RemoteBrowser.HistoryRead = .unreadable
        private(set) var asked: [Int?] = []
        let now = Date(timeIntervalSince1970: 1_791_833_400)

        lazy var sessions = RemoteSessions(dependencies: RemoteSessions.Dependencies(
            actionsOn: { true }, known: { [unowned self] in [self.known] }, cardPlan: { _ in nil }, read: { _, _ in nil },
            readPlan: { _ in nil }, write: { _ in nil }, now: { [unowned self] in self.now }, browseOn: { true }, lookup: { _ in nil }))

        lazy var browser = RemoteBrowser(sessions: sessions, dependencies: RemoteBrowser.Dependencies(
            browseOn: { true }, actionsOn: { true }, projects: { nil }, sessions: { _, _, _ in nil },
            known: { [unowned self] in [self.known] },
            history: { [unowned self] _, before, _ in self.asked.append(before); return self.history },
            turn: { _, _ in .unreadable }, create: { _ in nil }, findIntent: { _, _ in nil }, listed: { _, _ in },
            now: { [unowned self] in self.now }, pause: {}))

        var known: SessionStatus { Fixture.session(root, .running) }

        func history(_ target: String = "/api/sessions/\(root)/history") async -> RemoteActionReply {
            let route = RemoteRoute.match(method: "GET", path: Substring(target.prefix { $0 != "?" }))
            guard case .found(let found) = route else { return RemoteActionReply(status: 404, body: Data()) }
            return await browser.respond(found, target: target, device: "device-1", body: Data())
        }
    }

    @Test func aReadOverTheCapAnswersThePhoneAsUnreadableAndKeepsNothing() async {
        let fake = Fake()
        fake.history = .unreadable
        let unreadable = await fake.history()
        #expect(unreadable.status == 503)
        fake.history = .tooBig
        let tooBig = await fake.history()
        #expect(tooBig == unreadable, "the same answer, byte for byte")
        let earlier = await fake.history("/api/sessions/\(root)/history?before=50")
        #expect(earlier == unreadable)
        // Nothing of it was kept: the next read goes to the page and a page is served.
        fake.history = .page(HistoryPage(total: 3, from: 0, items: [.helper(i: 1)]))
        let page = await fake.history()
        #expect(page.status == 200)
        #expect(fake.asked == [nil, nil, 50, nil])
    }
}
