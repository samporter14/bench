// PhoneAppHarness.swift — runs the phone app's own script (the embedded
// /app.js, as Bench serves it) in JavaScriptCore, with a small made-up page
// around it: a DOM that builds real trees and answers simple selectors,
// timers that run only when a test moves the clock, a `fetch` that answers
// from a table, and an events stream a test speaks for. Nothing real is
// reached, and every name and session in the tests is made up.
import Foundation
import JavaScriptCore
@testable import Bench

final class PhoneAppHarness {
    enum Missing: Error { case app }

    private let context: JSContext
    /// Exceptions the script threw, uncaught.
    private(set) var exceptions: [String] = []

    /// Loads the app at `hash` with the clock at `now`; `answers` maps a
    /// path to the JSON it answers with (status 200). Paths not in it never
    /// answer, which leaves whatever asked waiting. `beforeApp` can install
    /// a test's additional browser API shims before the served script loads.
    init(hash: String, now: Date, answers: [String: String], beforeApp: String = "") throws {
        context = JSContext()
        context.exceptionHandler = { [weak self] _, value in
            self?.exceptions.append(value?.toString() ?? "unknown")
        }
        set("__answersJSON", String(decoding: try JSONSerialization.data(withJSONObject: answers), as: UTF8.self))
        evaluate("var __now = \(Int(now.timeIntervalSince1970 * 1000)); var __hash = \(Self.quoted(hash));")
        evaluate(Self.page)
        if !beforeApp.isEmpty { evaluate(beforeApp) }
        guard let app = RemoteWebApp.files["/app.js"]?.body else { throw Missing.app }
        evaluate(app)
    }

    @discardableResult
    func evaluate(_ script: String) -> JSValue? {
        context.evaluateScript(script)
    }

    func set(_ name: String, _ text: String) {
        context.setObject(text, forKeyedSubscript: name as NSString)
    }

    func string(_ script: String) -> String? {
        guard let value = evaluate(script), !value.isUndefined, !value.isNull else { return nil }
        return value.toString()
    }

    /// Moves the clock on by `ms`, running every timer that falls due, in order.
    func advance(_ ms: Int) {
        evaluate("__advance(\(ms))")
    }

    /// Sends a `state` event down the events stream, as Bench does when the
    /// state changes. The app's listener drops a frame that throws, so a
    /// throw would hide here: `stateFailures` counts them.
    func sendState(_ json: String) {
        set("__stateJSON", json)
        evaluate("""
            (function () {
                var before = gotState;
                gotState = function (st) { try { return before(st); } catch (e) { __stateFailures.push(String(e)); throw e; } };
                try {
                    __sources.filter((s) => !s.closed).forEach((s) => (s.listeners.state || []).forEach((f) => f({ data: __stateJSON })));
                } finally { gotState = before; }
            })()
            """)
    }

    /// What threw while a sent state was handled.
    var stateFailures: [String] {
        (evaluate("__stateFailures")?.toArray() ?? []).map { "\($0)" }
    }

    /// How many requests went to `path`.
    func requests(to path: String) -> Int {
        Int(evaluate("__requests.filter((p) => p === \(Self.quoted(path))).length")?.toInt32() ?? -1)
    }

    /// How many requests to `path` were aborted by their signal, and how many carried one.
    func aborted(_ path: String) -> Int {
        Int(evaluate("__inits.filter((r) => r.path === \(Self.quoted(path)) && r.signal && r.signal.aborted).length")?.toInt32() ?? -1)
    }

    func signalled(_ path: String) -> Int {
        Int(evaluate("__inits.filter((r) => r.path === \(Self.quoted(path)) && r.signal).length")?.toInt32() ?? -1)
    }

    /// The text of the first element matching `selector` in the page, or nil.
    func text(_ selector: String) -> String? {
        string("(function () { const el = document.getElementById('root').querySelector(\(Self.quoted(selector))); return el ? el.textContent : null; })()")
    }

    static func quoted(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: [text]), as: UTF8.self).dropFirst().dropLast().description
    }

    /// The page around the script. The DOM keeps a real tree, so what the app
    /// draws can be read back; its selectors are the few shapes the app uses
    /// (tags, classes, `[attr="value"]`, descendant and `>`, `:scope`).
    private static let page = #"""
    var __requests = [];
    var __answers = JSON.parse(__answersJSON);
    var __timers = [];
    var __timerSeq = 0;
    var __sources = [];
    var __stateFailures = [];
    var __inits = [];
    Date.now = function () { return __now; };
    globalThis.window = globalThis;
    globalThis.setTimeout = function (fn, ms) { var id = ++__timerSeq; __timers.push({ id: id, fn: fn, at: __now + Math.max(0, ms || 0), every: 0 }); return id; };
    globalThis.setInterval = function (fn, ms) { var id = ++__timerSeq; __timers.push({ id: id, fn: fn, at: __now + ms, every: ms }); return id; };
    globalThis.clearTimeout = function (id) { __timers = __timers.filter(function (t) { return t.id !== id; }); };
    globalThis.clearInterval = globalThis.clearTimeout;
    globalThis.queueMicrotask = function (fn) { Promise.resolve().then(fn); };
    globalThis.requestAnimationFrame = function (fn) { return setTimeout(fn, 16); };
    globalThis.cancelAnimationFrame = globalThis.clearTimeout;
    function __advance(ms) {
        var end = __now + ms;
        for (;;) {
            var due = __timers.filter(function (t) { return t.at <= end; }).sort(function (a, b) { return a.at - b.at || a.id - b.id; })[0];
            if (!due) break;
            __now = Math.max(__now, due.at);
            if (due.every) due.at += due.every; else __timers = __timers.filter(function (t) { return t !== due; });
            due.fn();
        }
        __now = end;
    }

    function __compound(text) {
        var c = { tag: null, classes: [], attrs: [], scope: false };
        var re = /(:scope)|\.([\w-]+)|\[([\w-]+)(?:="([^"]*)")?\]|^([\w*-]+)/g, m;
        while ((m = re.exec(text))) {
            if (m[1]) c.scope = true;
            else if (m[2]) c.classes.push(m[2]);
            else if (m[3]) c.attrs.push([m[3], m[4] === undefined ? null : m[4]]);
            else if (m[5]) c.tag = m[5].toLowerCase();
        }
        return c;
    }
    function __selectors(text) {
        return text.split(',').map(function (one) {
            var parts = [], comb = ' ';
            one.trim().replace(/\s*>\s*/g, ' > ').split(/\s+/).forEach(function (t) {
                if (t === '>') { comb = '>'; return; }
                parts.push({ comb: comb, c: __compound(t) });
                comb = ' ';
            });
            return parts;
        });
    }
    function __is(el, c) {
        if (!el || !el.__el || c.scope) return false;
        if (c.tag && c.tag !== '*' && el.tagName !== c.tag) return false;
        var classes = (el.getAttribute('class') || '').split(/\s+/);
        for (var i = 0; i < c.classes.length; i++) if (classes.indexOf(c.classes[i]) < 0) return false;
        for (var j = 0; j < c.attrs.length; j++) {
            var have = el.getAttribute(c.attrs[j][0]);
            if (have == null || (c.attrs[j][1] != null && have !== c.attrs[j][1])) return false;
        }
        return true;
    }
    function __matches(el, parts, scope) {
        var i = parts.length - 1;
        if (!__is(el, parts[i].c)) return false;
        var node = el;
        for (; i > 0; i--) {
            var comb = parts[i].comb, want = parts[i - 1].c;
            if (want.scope) return comb === '>' ? node.parentNode === scope : scope.contains(node);
            if (comb === '>') { node = node.parentNode; if (!__is(node, want)) return false; continue; }
            var up = node.parentNode;
            while (up && !__is(up, want)) up = up.parentNode;
            if (!up) return false;
            node = up;
        }
        return true;
    }
    function __text(value) { return { __textNode: true, data: String(value), parentNode: null, get textContent() { return this.data; } }; }
    function __El(tag) {
        this.__el = true;
        this.tagName = String(tag).toLowerCase();
        this.childNodes = [];
        this.parentNode = null;
        this.attributes = Object.create(null);
        this.style = {};
        this.hidden = false;
        this.scrollTop = 0;
        this.value = '';
        var self = this;
        this.dataset = new Proxy({}, {
            get: function (_, key) { return typeof key === 'string' ? self.getAttribute('data-' + key.replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); })) ?? undefined : undefined; },
            set: function (_, key, v) { self.setAttribute('data-' + key.replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); }), v); return true; },
        });
        this.classList = {
            contains: function (k) { return (self.getAttribute('class') || '').split(/\s+/).indexOf(k) >= 0; },
            add: function (k) { if (!this.contains(k)) self.className = ((self.getAttribute('class') || '') + ' ' + k).trim(); },
            remove: function (k) { self.className = (self.getAttribute('class') || '').split(/\s+/).filter(function (x) { return x !== k; }).join(' '); },
            toggle: function (k, on) { var want = on === undefined ? !this.contains(k) : !!on; if (want) this.add(k); else this.remove(k); return want; },
        };
        if (this.tagName === 'template') {
            var holder = this;
            this.content = { firstElementChild: null };
            Object.defineProperty(this, 'innerHTML', { set: function (html) {
                var svg = new __El('svg');
                var cls = /class="([^"]*)"/.exec(html);
                if (cls) svg.setAttribute('class', cls[1]);
                svg.setAttribute('data-markup', html);
                holder.content.firstElementChild = svg;
            } });
        }
    }
    __El.prototype = {
        setAttribute: function (k, v) { this.attributes[k] = String(v); },
        getAttribute: function (k) { return k in this.attributes ? this.attributes[k] : null; },
        removeAttribute: function (k) { delete this.attributes[k]; },
        hasAttribute: function (k) { return k in this.attributes; },
        get className() { return this.getAttribute('class') || ''; },
        set className(v) { this.setAttribute('class', v); },
        get id() { return this.getAttribute('id') || ''; },
        set id(v) { this.setAttribute('id', v); },
        get children() { return this.childNodes.filter(function (n) { return n.__el; }); },
        get parentElement() { return this.parentNode && this.parentNode.__el ? this.parentNode : null; },
        get firstElementChild() { return this.children[0] || null; },
        get isConnected() { return true; },
        get textContent() { return this.childNodes.map(function (n) { return n.textContent; }).join(''); },
        set textContent(v) { this.replaceChildren(__text(v)); },
        appendChild: function (n) { this.append(n); return n; },
        append: function () {
            for (var i = 0; i < arguments.length; i++) {
                var n = arguments[i];
                if (n == null) continue;
                if (typeof n !== 'object') n = __text(n);
                if (n.parentNode && n.parentNode.childNodes) n.parentNode.childNodes = n.parentNode.childNodes.filter(function (x) { return x !== n; });
                n.parentNode = this;
                this.childNodes.push(n);
            }
        },
        prepend: function () { var keep = this.childNodes; this.childNodes = []; this.append.apply(this, arguments); this.append.apply(this, keep); },
        replaceChildren: function () { this.childNodes.forEach(function (n) { n.parentNode = null; }); this.childNodes = []; this.append.apply(this, arguments); },
        replaceWith: function (n) { var p = this.parentNode; if (!p) return; var at = p.childNodes.indexOf(this); if (typeof n !== 'object') n = __text(n); n.parentNode = p; p.childNodes[at] = n; this.parentNode = null; },
        insertBefore: function (n, ref) { this.append(n); if (ref) { this.childNodes.pop(); this.childNodes.splice(this.childNodes.indexOf(ref), 0, n); } return n; },
        removeChild: function (n) { this.childNodes = this.childNodes.filter(function (x) { return x !== n; }); n.parentNode = null; return n; },
        remove: function () { if (this.parentNode) this.parentNode.removeChild(this); },
        before: function (n) { var p = this.parentNode; if (p) p.insertBefore(n, this); },
        after: function (n) { var p = this.parentNode; if (!p) return; var at = p.childNodes.indexOf(this); p.append(n); p.childNodes.pop(); p.childNodes.splice(at + 1, 0, n); },
        contains: function (n) { while (n) { if (n === this) return true; n = n.parentNode; } return false; },
        querySelectorAll: function (selector) {
            var lists = __selectors(selector), out = [], scope = this;
            (function walk(el) {
                el.children.forEach(function (child) {
                    if (lists.some(function (parts) { return __matches(child, parts, scope); })) out.push(child);
                    walk(child);
                });
            })(this);
            return out;
        },
        querySelector: function (selector) { return this.querySelectorAll(selector)[0] || null; },
        matches: function (selector) { var self = this; return __selectors(selector).some(function (parts) { return __matches(self, parts, null); }); },
        closest: function (selector) { var n = this; while (n && n.__el) { if (n.matches(selector)) return n; n = n.parentNode; } return null; },
        addEventListener: function () {}, removeEventListener: function () {},
        focus: function () {}, blur: function () {}, click: function () {},
        scrollTo: function () {}, scrollIntoView: function () {}, scrollBy: function () {},
        getBoundingClientRect: function () { return { top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0 }; },
        get scrollHeight() { return 0; }, get clientHeight() { return 0; }, get offsetHeight() { return 0; },
    };
    var __root = new __El('div'); __root.id = 'root';
    var __pill = new __El('div'); __pill.id = 'pill'; __pill.hidden = true;
    globalThis.document = {
        hidden: false, activeElement: null, title: '', visibilityState: 'visible',
        documentElement: new __El('html'), body: new __El('body'),
        createElement: function (tag) { return new __El(tag); },
        createTextNode: function (t) { return __text(t); },
        createDocumentFragment: function () { return new __El('#fragment'); },
        getElementById: function (id) { return id === 'root' ? __root : id === 'pill' ? __pill : __root.querySelector('[id="' + id + '"]'); },
        querySelector: function (s) { return __root.querySelector(s); },
        querySelectorAll: function (s) { return __root.querySelectorAll(s); },
        addEventListener: function () {}, removeEventListener: function () {},
    };
    globalThis.location = { get hash() { return __hash; }, set hash(v) { __hash = v; }, pathname: '/', search: '', origin: 'https://bench.test', href: 'https://bench.test/', reload: function () {}, replace: function () {} };
    globalThis.history = { replaceState: function () {}, pushState: function () {}, back: function () {} };
    globalThis.navigator = { userAgent: 'BenchTests', standalone: true, onLine: true };
    globalThis.matchMedia = function () { return { matches: false, addEventListener: function () {}, removeEventListener: function () {} }; };
    globalThis.addEventListener = function () {};
    globalThis.removeEventListener = function () {};
    globalThis.localStorage = { getItem: function () { return null; }, setItem: function () {}, removeItem: function () {} };
    globalThis.sessionStorage = globalThis.localStorage;
    globalThis.CSS = { escape: function (s) { return String(s); }, supports: function () { return false; } };
    globalThis.scrollTo = function () {};
    globalThis.EventSource = function (url) { this.url = url; this.listeners = {}; this.readyState = 1; this.closed = false; __sources.push(this); };
    globalThis.EventSource.CLOSED = 2;
    globalThis.EventSource.prototype = {
        addEventListener: function (type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); },
        close: function () { this.closed = true; this.readyState = 2; },
    };
    // JavaScriptCore has no AbortController. This one is just enough for the app's reads: a signal that says whether it
    // aborted, tells its listeners once, and lets one be removed.
    globalThis.AbortSignal = function AbortSignal() { this.aborted = false; this.__listeners = []; };
    AbortSignal.prototype.addEventListener = function (type, fn) { if (type === 'abort') this.__listeners.push(fn); };
    AbortSignal.prototype.removeEventListener = function (type, fn) { this.__listeners = this.__listeners.filter(function (f) { return f !== fn; }); };
    globalThis.AbortController = function AbortController() { this.signal = new AbortSignal(); };
    AbortController.prototype.abort = function () {
        var signal = this.signal;
        if (signal.aborted) return;
        signal.aborted = true;
        signal.__listeners.slice().forEach(function (fn) { fn({ type: 'abort' }); });
    };
    // A request is kept with its method and signal (`__inits`). One that is not in the answers table never answers, but
    // fails as an aborted fetch does once its signal fires.
    globalThis.fetch = function (path, init) {
        __requests.push(path);
        var signal = (init && init.signal) || null;
        __inits.push({ path: path, method: (init && init.method) || 'GET', signal: signal });
        if (!(path in __answers)) return new Promise(function (resolve, reject) {
            if (!signal) return;
            var fail = function () { reject(Object.assign(new Error('aborted'), { name: 'AbortError' })); };
            if (signal.aborted) fail(); else signal.addEventListener('abort', fail);
        });
        var body = __answers[path];
        return Promise.resolve({
            status: 200, ok: true,
            headers: { get: function () { return null; } },
            json: function () { return Promise.resolve(JSON.parse(body)); },
            text: function () { return Promise.resolve(body); },
        });
    };
    """#
}
