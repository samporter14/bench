// PageScript.swift — runs Bench's in-page scripts in JavaScriptCore, the
// engine WebKit's pages run on, against made-up data. A fake `fetch` stands in
// for the daemon: it records every request and answers from a table, so the
// tests see exactly which paths and bodies a script would send. Nothing here
// reaches a real daemon.
import Foundation
import JavaScriptCore

final class PageScript {
    /// One fake answer: a status and a body.
    struct Answer: Encodable {
        let status: Int
        let body: String
    }

    /// One request the script made.
    struct Request: Equatable {
        let path: String
        let method: String
        let body: String?
        let csrf: String?
        let cache: String?
    }

    private let context: JSContext

    /// `source` is evaluated once: function declarations, or nothing.
    init(_ source: String = "") {
        context = JSContext()
        evaluate(source)
    }

    /// Timers that run when a test says the time is up (`__expire()`), and an
    /// AbortController that tells its listeners, as a page's does. JavaScriptCore
    /// has neither.
    static let timerShim = """
var __timers = [];
var setTimeout = function (fn, ms) { __timers.push({ fn: fn, ms: ms, live: true }); return __timers.length; };
var clearTimeout = function (id) { if (__timers[id - 1]) { __timers[id - 1].live = false; } };
var __expire = function () {
    for (var i = 0; i < __timers.length; i++) { if (__timers[i].live) { __timers[i].live = false; __timers[i].fn(); } }
};
var __signals = [];
var __Signal = function () { this.aborted = false; this.__listeners = []; __signals.push(this); };
__Signal.prototype.addEventListener = function (type, fn) { this.__listeners.push(fn); };
__Signal.prototype.removeEventListener = function (type, fn) {
    this.__listeners = this.__listeners.filter(function (f) { return f !== fn; });
};
var AbortController = function () { this.signal = new __Signal(); };
AbortController.prototype.abort = function () {
    if (this.signal.aborted) { return; }
    this.signal.aborted = true;
    this.signal.__listeners.slice().forEach(function (f) { f(); });
};
// A request that never answers: it rejects when its signal aborts (body "__hang__"), or it doesn't ("__hang-ignore__").
var __hangs = function (answer, init) {
    if (answer.body !== "__hang__" && answer.body !== "__hang-ignore__") { return null; }
    var signal = init && init.signal;
    return new Promise(function (resolve, reject) {
        if (answer.body === "__hang__" && signal) { signal.addEventListener("abort", function () { reject(new Error("aborted")); }); }
    });
};
"""

    /// Evaluates `script`; returns the value as a string, nil for an
    /// exception (recorded in `exception`).
    @discardableResult
    func evaluate(_ script: String) -> String? {
        context.exception = nil
        let value = context.evaluateScript(script)
        if let exception = context.exception {
            self.exception = exception.toString()
            context.exception = nil
            return nil
        }
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        return value.toString()
    }

    private(set) var exception: String?

    /// Sets a global string variable, so data never has to be quoted into source.
    func set(_ name: String, _ text: String) {
        context.setObject(text, forKeyedSubscript: name as NSString)
    }

    /// Calls `function(JSON.parse(argument), …)` and returns `JSON.stringify` of the result.
    func callJSON(_ function: String, _ arguments: [String?]) -> String? {
        var names: [String] = []
        for (index, argument) in arguments.enumerated() {
            let name = "__arg\(index)"
            if let argument {
                set(name, argument)
                names.append("JSON.parse(\(name))")
            } else {
                names.append("null")
            }
        }
        return evaluate("JSON.stringify(\(function)(\(names.joined(separator: ", "))))")
    }

    /// How many signals the script's controllers aborted.
    var abortedSignals: Int { Int(evaluate("String(__signals.filter(function (s) { return s.aborted; }).length)") ?? "") ?? 0 }
    /// How many timers are still waiting.
    var pendingTimers: Int { Int(evaluate("String(__timers.filter(function (t) { return t.live; }).length)") ?? "") ?? 0 }

    // MARK: Running an in-page body

    /// Runs `body` as `callAsyncJavaScript` would, as an async function of
    /// `arguments` (each a JSON value), with `fetch` answering from
    /// `answers` (by path, in turn: the last one repeats) and `document.cookie`
    /// as given. Returns what the body returned, and the requests it made.
    func runPage(_ body: String, arguments: [(String, String)], answers: [String: [Answer]],
                 cookie: String = "theme=dark; operon_csrf=secret-one", expire: Bool = false) -> (result: String?, requests: [Request]) {
        let table = (try? JSONEncoder().encode(answers)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        set("__answers", table)
        set("__cookie", cookie)
        evaluate("""
        var __requests = [];
        var __table = JSON.parse(__answers);
        var __seen = {};
        var document = { cookie: __cookie };
        var AbortSignal = function () {};
        AbortSignal.timeout = function () { return undefined; };
        \(Self.timerShim)
        var fetch = function (path, init) {
            init = init || {};
            var headers = init.headers || {};
            __requests.push({ path: path, method: init.method || "GET", body: typeof init.body === "string" ? init.body : null,
                              csrf: typeof headers["x-operon-csrf"] === "string" ? headers["x-operon-csrf"] : null,
                              cache: typeof init.cache === "string" ? init.cache : null });
            var list = __table[path];
            if (!list || list.length === 0) { return Promise.reject(new Error("no answer for " + path)); }
            var n = __seen[path] || 0;
            __seen[path] = n + 1;
            var answer = list[Math.min(n, list.length - 1)];
            var hung = __hangs(answer, init);
            if (hung) { return hung; }
            return Promise.resolve({ status: answer.status, ok: answer.status >= 200 && answer.status < 300,
                                     text: function () { return Promise.resolve(answer.body); } });
        };
        var __result = null;
        """)
        let names = arguments.map(\.0).joined(separator: ", ")
        for (index, argument) in arguments.enumerated() { set("__value\(index)", argument.1) }
        let values = arguments.indices.map { "JSON.parse(__value\($0))" }.joined(separator: ", ")
        evaluate("""
        (async function (\(names)) {
        \(body)
        })(\(values)).then(function (v) { __result = v; }, function (e) { __result = "threw: " + e; });
        """)
        // The time is up: every timer the script set goes off.
        if expire { evaluate("__expire()") }
        let result = evaluate("__result")
        let requestsJSON = evaluate("JSON.stringify(__requests)") ?? "[]"
        let list = (try? JSONSerialization.jsonObject(with: Data(requestsJSON.utf8))) as? [[String: Any]] ?? []
        let requests = list.map {
            Request(path: $0["path"] as? String ?? "", method: $0["method"] as? String ?? "",
                    body: $0["body"] as? String, csrf: $0["csrf"] as? String, cache: $0["cache"] as? String)
        }
        return (result, requests)
    }
}
