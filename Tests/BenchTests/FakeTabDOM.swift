// FakeTabDOM.swift — a minimal made-up page for the tab scripts, run in
// JavaScriptCore: a tab strip, its toolbar and tabs, as objects with the few
// DOM calls the scripts use (`querySelector`, `querySelectorAll`, `closest`,
// `getAttribute`, `dataset`, `click`). Selectors are tag, `[attr]` and
// `[attr="value"]`, joined, with a space for "inside". Every click is logged,
// and a close button's click asks the fake page to close its tab, which
// closes it at once, never, or after a delay on a virtual clock. Nothing here
// is a real page, and no tab name in it is real.
import Foundation
import Testing
@testable import Bench

enum FakeTabDOM {
    /// One tab of the fake strip.
    struct Tab: Encodable {
        var id: String
        var shown = false
        /// "now": the close button works at once. "refuse": it is pressed and
        /// nothing happens (the page is asking about unsaved edits). "none":
        /// the tab has no close button.
        var close = "now"
        /// Milliseconds of the fake clock the close takes, when "now".
        var delay = 0
        /// How the tab says it is shown: "aria" (`aria-current` on its
        /// button), "data" (`data-shown` on the tab) or "both".
        var shownVia = "aria"
    }

    /// The page: the strip's tabs and what else is around them.
    struct Page: Encodable {
        var tabs: [Tab]
        /// How many strips (0 for none, 2 for an ambiguous page).
        var strips = 1
        var toolbar = true
        /// Tabs and close buttons outside the strip, and a tab-like block
        /// inside the strip but outside the toolbar, none of them to be touched.
        var decoys = false
        /// Every re-render makes new elements for all tabs.
        var fresh = false
        /// The strip leaves the page when its last tab is closed.
        var unmount = true
    }

    static func tabs(_ ids: String..., shown: String? = nil) -> [Tab] {
        ids.map { Tab(id: $0, shown: $0 == shown) }
    }

    static let source = #"""
    var __log = [];
    var __timers = [];
    var __seq = 0;
    var __now = 0;
    var __model = [];
    var __strip = null;
    var __toolbar = null;
    var __fresh = false;
    var __unmount = true;

    function El(tag, attrs) {
        this.tag = tag;
        this.attrs = attrs || {};
        this.children = [];
        this.parent = null;
        this.nodeType = 1;
        this.onclick = null;
    }
    El.prototype.append = function (child) { child.parent = this; this.children.push(child); return child; };
    El.prototype.getAttribute = function (name) {
        return Object.prototype.hasOwnProperty.call(this.attrs, name) ? String(this.attrs[name]) : null;
    };
    El.prototype.hasAttribute = function (name) { return this.getAttribute(name) !== null; };
    Object.defineProperty(El.prototype, "dataset", {
        get: function () {
            var out = {};
            for (var key in this.attrs) {
                if (key.indexOf("data-") === 0) {
                    out[key.slice(5).replace(/-([a-z])/g, function (m, c) { return c.toUpperCase(); })] = String(this.attrs[key]);
                }
            }
            return out;
        }
    });
    El.prototype.querySelectorAll = function (selector) {
        var out = [];
        (function walk(node) {
            node.children.forEach(function (child) {
                if (__matches(child, selector)) { out.push(child); }
                walk(child);
            });
        })(this);
        return out;
    };
    El.prototype.querySelector = function (selector) { return this.querySelectorAll(selector)[0] || null; };
    El.prototype.closest = function (selector) {
        for (var node = this; node; node = node.parent) { if (__matches(node, selector)) { return node; } }
        return null;
    };
    El.prototype.click = function () {
        var attached = __attached(this);
        __log.push({ role: this.attrs["data-fake-role"] || this.tag, id: this.attrs["data-fake-id"] || null, detached: !attached });
        if (attached && this.onclick) { this.onclick(); }
    };

    function __attached(element) {
        var top = element;
        while (top.parent) { top = top.parent; }
        return top === document.body;
    }
    function __tokens(selector) { return selector.match(/(?:[^\s\[]|\[[^\]]*\])+/g) || []; }
    function __compound(element, text) {
        var parsed = /^([a-z0-9]*)((?:\[[^\]]*\])*)$/i.exec(text);
        if (!parsed) { throw new Error("fake DOM: unsupported selector " + text); }
        if (parsed[1] && element.tag !== parsed[1]) { return false; }
        var pattern = /\[([\w-]+)(?:="([^"]*)")?\]/g, found;
        while ((found = pattern.exec(parsed[2])) !== null) {
            var value = element.getAttribute(found[1]);
            if (value === null) { return false; }
            if (found[2] !== undefined && value !== found[2]) { return false; }
        }
        return true;
    }
    function __matches(element, selector) {
        var parts = __tokens(selector), index = parts.length - 1;
        if (!__compound(element, parts[index])) { return false; }
        var node = element.parent;
        index -= 1;
        while (index >= 0 && node) {
            if (__compound(node, parts[index])) { index -= 1; }
            node = node.parent;
        }
        return index < 0;
    }

    var document = {
        body: null,
        listeners: [],
        querySelectorAll: function (selector) { return document.body ? document.body.querySelectorAll(selector) : []; },
        querySelector: function (selector) { return document.querySelectorAll(selector)[0] || null; },
        addEventListener: function (type, fn, capture) { document.listeners.push({ type: type, fn: fn, capture: capture }); }
    };

    function __schedule(fn, ms) { __timers.push({ due: __now + ms, seq: __seq++, fn: fn }); }
    function __enableTimers() {
        this.setTimeout = function (fn, ms) { __schedule(fn, ms || 0); return __seq; };
    }
    function __pump() {
        if (__timers.length === 0) { return false; }
        var best = 0;
        for (var i = 1; i < __timers.length; i++) {
            var a = __timers[i], b = __timers[best];
            if (a.due < b.due || (a.due === b.due && a.seq < b.seq)) { best = i; }
        }
        var timer = __timers.splice(best, 1)[0];
        __now = timer.due;
        timer.fn();
        return true;
    }

    function __remove(id) {
        __model = __model.filter(function (tab) { return tab.id !== id; });
        __render();
    }
    function __pressed(tab) {
        if (tab.close === "refuse") { return; }
        if (tab.delay > 0) { __schedule(function () { __remove(tab.id); }, tab.delay); } else { __remove(tab.id); }
    }
    function __tabElement(tab) {
        var shownAria = tab.shownVia === "aria" || tab.shownVia === "both";
        var shownData = tab.shownVia === "data" || tab.shownVia === "both";
        var attrs = { "data-tab-id": tab.id, "data-testid": "right-tab" };
        if (tab.shown && shownData) { attrs["data-shown"] = "true"; }
        var element = new El("div", attrs);
        var button = { "data-tab-btn": "", "data-fake-role": "tab-btn", "data-fake-id": tab.id };
        if (tab.shown && shownAria) { button["aria-current"] = "true"; }
        element.append(new El("button", button));
        element.append(new El("button", { "data-fake-role": "overflow", "data-fake-id": tab.id, "aria-label": "Close menu" }));
        if (tab.close !== "none") {
            var close = element.append(new El("button", { "data-tab-close": "", "data-testid": "right-tab-close",
                "aria-label": "Close tab", "data-fake-role": "close", "data-fake-id": tab.id }));
            close.onclick = function () { __pressed(tab); };
        }
        return element;
    }
    function __render() {
        if (!__toolbar) { return; }
        __toolbar.children.forEach(function (child) { child.parent = null; });
        __toolbar.children = [];
        __model.forEach(function (tab) {
            if (__fresh || !tab.element) { tab.element = __tabElement(tab); }
            __toolbar.append(tab.element);
        });
        if (__model.length === 0 && __unmount && __strip && __strip.parent) {
            var parent = __strip.parent;
            parent.children = parent.children.filter(function (child) { return child !== __strip; });
            __strip.parent = null;
        }
    }
    function __build(spec) {
        var body = new El("body", {});
        document.body = body;
        __log = []; __timers = []; __seq = 0; __now = 0;
        __fresh = !!spec.fresh;
        __unmount = spec.unmount !== false;
        __model = spec.tabs.map(function (tab) { return JSON.parse(JSON.stringify(tab)); });
        if (spec.decoys) {
            var side = body.append(new El("div", { "data-testid": "left-panel" }));
            ["t1", "t2", "t3", "zzz"].forEach(function (id) {
                var tab = side.append(new El("div", { "data-tab-id": id }));
                tab.append(new El("button", { "data-tab-btn": "", "aria-current": "true", "data-fake-role": "decoy-btn", "data-fake-id": id }));
                tab.append(new El("button", { "data-tab-close": "", "data-fake-role": "decoy-close", "data-fake-id": id }));
            });
            side.append(new El("button", { "data-tab-close": "", "aria-label": "Close Files", "data-fake-role": "decoy-close" }));
        }
        __strip = null; __toolbar = null;
        for (var i = 0; i < (spec.strips === undefined ? 1 : spec.strips); i++) {
            var strip = body.append(new El("div", { "data-testid": "right-tab-strip" }));
            var bar = strip.append(spec.toolbar === false ? new El("div", {})
                : new El("div", { role: "toolbar", "aria-label": "Open panels" }));
            if (i === 0) { __strip = strip; __toolbar = bar; }
            if (spec.decoys && i === 0) {
                var block = strip.append(new El("div", { "data-tab-id": "strip-decoy" }));
                block.append(new El("button", { "data-tab-close": "", "data-fake-role": "strip-decoy-close", "data-fake-id": "strip-decoy" }));
            }
        }
        __render();
    }

    function __clicks() {
        return __log.map(function (entry) { return entry.role + ":" + (entry.id || "") + (entry.detached ? "!detached" : ""); }).join(",");
    }
    function __remaining() { return __model.map(function (tab) { return tab.id; }).join(","); }
    function __stripPresent() { return document.querySelector('[data-testid="right-tab-strip"]') !== null; }
    function __find(role, id) {
        return document.querySelector('[data-fake-role="' + role + '"][data-fake-id="' + id + '"]');
    }
    """#

    /// A script context with the fake page built from `page`.
    static func context(_ page: Page, timers: Bool = false) -> PageScript {
        let script = PageScript(source)
        let data = (try? JSONEncoder().encode(page)) ?? Data()
        script.set("__spec", String(decoding: data, as: UTF8.self))
        script.evaluate("__build(JSON.parse(__spec));")
        if timers { script.evaluate("__enableTimers();") }
        return script
    }
}

/// The fake page and a tab sweep run against it.
final class FakeTabPage {
    let script: PageScript

    init(_ page: FakeTabDOM.Page, timers: Bool = false) {
        script = FakeTabDOM.context(page, timers: timers)
    }

    /// Runs `PageTabsScript.body` as `callAsyncJavaScript` would, with the
    /// fake clock's timers pumped until it answers, and returns its answer.
    func run(_ mode: String, keep: String? = nil) -> PageTabsOutcome? {
        script.set("__mode", mode)
        script.set("__keep", keep.map { Self.json($0) } ?? "null")
        script.evaluate("""
        var __out = null;
        (async function (mode, keep) {
        \(PageTabsScript.body)
        })(__mode, JSON.parse(__keep)).then(function (v) { __out = v; }, function (e) { __out = "threw: " + e; });
        """)
        for _ in 0..<500 {
            if script.evaluate("__out") != nil { break }
            if script.evaluate("String(__pump())") != "true" { break }
        }
        return script.evaluate("__out").flatMap { PageTabsOutcome(parsing: $0) }
    }

    /// The raw answer of the last run.
    var answer: String? { script.evaluate("__out") }
    /// Every click, in order, as `role:id`.
    var clicks: String { script.evaluate("__clicks()") ?? "?" }
    /// The ids the fake page still has, in order.
    var remaining: String { script.evaluate("__remaining()") ?? "?" }
    var stripPresent: Bool { script.evaluate("String(__stripPresent())") == "true" }

    static func json(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text])
        let array = data.map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
