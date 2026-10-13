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

    // MARK: Running an in-page body

    /// Runs `body` as `callAsyncJavaScript` would, as an async function of
    /// `arguments` (each a JSON value), with `fetch` answering from
    /// `answers` (by path, in turn: the last one repeats) and `document.cookie`
    /// as given. Returns what the body returned, and the requests it made.
    func runPage(_ body: String, arguments: [(String, String)], answers: [String: [Answer]],
                 cookie: String = "theme=dark; operon_csrf=secret-one") -> (result: String?, requests: [Request]) {
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
