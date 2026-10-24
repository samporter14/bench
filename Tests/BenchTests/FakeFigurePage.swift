// FakeFigurePage.swift — a made-up page for the figure-menu script
// (Shelf/ConversationMenu.swift), run in JavaScriptCore: a conversation with a
// tile, an inline figure and a card in the Generated tray, and a stand-in for
// the menu Claude Science draws when one of them is right-clicked. It is a
// small DOM, not a real one: elements with attributes, children, a selector
// engine for the shapes the script asks (tag, `[attr]`, `[attr="value"]`,
// joined, with commas and spaces), events that run capture, target and bubble,
// a MutationObserver whose records the test delivers (`__flush`, as a
// microtask would), timers on a virtual clock (`__advance`), and the few
// browser globals the script uses. Every class name in it is copied from
// Claude Science 0.1.70's bundle (index-DhEuR7nq.js, the menu `oG`); nothing
// in it is a real page or a real name.
//
// The stand-in menu is guarded: any read of `textContent` on the page's own
// items throws, so a script that read an item's words would fail its tests.
import Foundation

enum FakeFigurePage {
    /// The classes of the page's menu, items and rule, as the bundle spells them.
    static let menuClass = "fixed z-popover bg-bg-000 border-0.5 border-border-200 rounded-xl shadow-[0_4px_16px_hsl(var(--always-black)/10%)] p-1.5 min-w-[9rem] min-w-[200px] whitespace-nowrap"
    static let itemClass = "w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-text-100 hover:bg-bg-200 hover:text-text-000 transition-colors text-left"
    static let dangerClass = "w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm text-danger-000 hover:bg-danger-900 transition-colors text-left"
    static let ruleClass = "my-1 h-px bg-border-300 mx-1"

    /// The small DOM on its own: timers on a virtual clock, URL, events,
    /// mutation observers, a selector engine, nodes and a document (also what
    /// FakeModelPage is built on). Evaluated first; a page then defines its own
    /// `window` and `location` and builds what it needs.
    static let dom = #"""
    var __posted = [];

    // ---- Timers on a virtual clock
    var __now = 0, __timers = [], __timerSeq = 0;
    function setTimeout(fn, ms) { var t = { id: ++__timerSeq, at: __now + (ms || 0), fn: fn, live: true }; __timers.push(t); return t.id; }
    function clearTimeout(id) { __timers.forEach(function (t) { if (t.id === id) { t.live = false; } }); }
    function __advance(ms) {
      var until = __now + ms;
      for (;;) {
        var due = __timers.filter(function (t) { return t.live && t.at <= until; })
          .sort(function (a, b) { return a.at - b.at || a.id - b.id; })[0];
        if (!due) { break; }
        due.live = false;
        __now = Math.max(__now, due.at);
        due.fn();
        __flush();
      }
      __now = until;
    }
    function __liveTimers() { return __timers.filter(function (t) { return t.live; }).length; }

    // ---- URL (JavaScriptCore has none)
    function URL(text) {
      var m = /^(https?:)\/\/([^\/?#]+)(\/[^?#]*)?(\?[^#]*)?(#.*)?$/.exec(String(text));
      if (!m) { throw new TypeError("Invalid URL"); }
      this.protocol = m[1];
      this.host = m[2];
      this.origin = m[1] + "//" + m[2];
      this.pathname = m[3] || "/";
      this.search = m[4] || "";
      var pairs = [];
      (m[4] ? m[4].slice(1) : "").split("&").forEach(function (part) {
        if (!part) { return; }
        var i = part.indexOf("=");
        var key = i < 0 ? part : part.slice(0, i), value = i < 0 ? "" : part.slice(i + 1);
        pairs.push([decodeURIComponent(key.replace(/\+/g, " ")), decodeURIComponent(value.replace(/\+/g, " "))]);
      });
      this.searchParams = pairs;
    }

    // ---- Events
    function __Event(type, init) {
      init = init || {};
      this.type = type;
      this.bubbles = !!init.bubbles;
      this.cancelable = !!init.cancelable;
      this.key = init.key;
      this.code = init.code;
      this.clientX = init.clientX || 0;
      this.clientY = init.clientY || 0;
      this.isTrusted = false;
      this.defaultPrevented = false;
      this.__stopped = false;
      this.target = null;
    }
    __Event.prototype.preventDefault = function () { this.defaultPrevented = true; };
    __Event.prototype.stopPropagation = function () { this.__stopped = true; };
    function KeyboardEvent(type, init) { return new __Event(type, init); }
    function PointerEvent(type, init) { return new __Event(type, init); }

    function __dispatch(target, event) {
      event.target = target;
      var path = [];
      for (var n = target; n; n = n.parentNode) { path.push(n); }
      function run(node, phase) {
        (node.__listeners || []).slice().forEach(function (l) {
          if (event.__stopped) { return; }
          if (l.type !== event.type) { return; }
          if (phase === "capture" && !l.capture) { return; }
          if (phase === "bubble" && l.capture) { return; }
          l.fn(event);
        });
      }
      for (var i = path.length - 1; i >= 1 && !event.__stopped; i--) { run(path[i], "capture"); }
      if (!event.__stopped) { run(path[0], "target"); }
      if (event.bubbles) { for (var j = 1; j < path.length && !event.__stopped; j++) { run(path[j], "bubble"); } }
      return !event.defaultPrevented;
    }

    // ---- Mutation observers (records are delivered by __flush)
    var __observers = [];
    function MutationObserver(callback) { this.callback = callback; this.targets = []; this.records = []; this.active = false; this.deliveries = 0; __observers.push(this); }
    MutationObserver.prototype.observe = function (node, options) { this.targets.push({ node: node, options: options || {} }); this.active = true; };
    MutationObserver.prototype.disconnect = function () { this.active = false; this.targets = []; this.records = []; };
    MutationObserver.prototype.takeRecords = function () { var r = this.records; this.records = []; return r; };
    function __flush() {
      for (var guard = 0; guard < 50; guard++) {
        var pending = __observers.filter(function (o) { return o.active && o.records.length; });
        if (pending.length === 0) { return; }
        pending.forEach(function (o) { var r = o.records; o.records = []; o.deliveries++; o.callback(r, o); });
      }
      throw new Error("observers never settled");
    }
    function __watching() { return __observers.filter(function (o) { return o.active; }).length; }
    function __record(parent, added, removed) {
      __observers.forEach(function (o) {
        if (!o.active) { return; }
        for (var i = 0; i < o.targets.length; i++) {
          var t = o.targets[i];
          if (t.node === parent || (t.options.subtree && t.node.contains(parent))) {
            o.records.push({ type: "childList", target: parent, addedNodes: added, removedNodes: removed });
            return;
          }
        }
      });
    }

    // ---- Selectors
    function __split(text, separator) {
      var parts = [], current = "", depth = 0, quote = null;
      for (var i = 0; i < text.length; i++) {
        var c = text[i];
        if (quote) { current += c; if (c === quote) { quote = null; } continue; }
        if (c === '"' || c === "'") { quote = c; current += c; continue; }
        if (c === "[") { depth++; }
        if (c === "]") { depth--; }
        if (depth === 0 && (separator === " " ? /\s/.test(c) : c === separator)) {
          if (current.trim() !== "") { parts.push(current.trim()); }
          current = "";
          continue;
        }
        current += c;
      }
      if (current.trim() !== "") { parts.push(current.trim()); }
      return parts;
    }
    function __compound(element, text) {
      var parsed = /^([a-z0-9*]*)((?:\[[^\]]*\])*)$/i.exec(text);
      if (!parsed) { throw new Error("fake DOM: unsupported selector " + text); }
      if (parsed[1] && parsed[1] !== "*" && element.localName !== parsed[1].toLowerCase()) { return false; }
      var pattern = /\[([\w-]+)(?:=(?:"([^"]*)"|'([^']*)'))?(?:\s*)\]/g, found;
      while ((found = pattern.exec(parsed[2])) !== null) {
        var value = element.getAttribute(found[1]);
        if (value === null) { return false; }
        var want = found[2] !== undefined ? found[2] : found[3];
        if (want !== undefined && value !== want) { return false; }
      }
      return true;
    }
    function __matches(element, selector) {
      return __split(selector, ",").some(function (alternative) {
        var chain = __split(alternative, " ");
        var node = element;
        if (!__compound(node, chain[chain.length - 1])) { return false; }
        var at = chain.length - 2;
        for (node = node.parentNode; at >= 0 && node && node.nodeType === 1; node = node.parentNode) {
          if (__compound(node, chain[at])) { at--; }
        }
        return at < 0;
      });
    }

    // ---- Nodes
    class FNode {
      constructor(nodeType) { this.nodeType = nodeType; this.parentNode = null; this.childNodes = []; this.__listeners = []; }
      get ownerDocument() { return document; }
      get firstChild() { return this.childNodes[0] || null; }
      get parentElement() { return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null; }
      get isConnected() { var n = this; while (n.parentNode) { n = n.parentNode; } return n === document; }
      contains(other) { for (var n = other; n; n = n.parentNode) { if (n === this) { return true; } } return false; }
      appendChild(child) { return this.insertBefore(child, null); }
      insertBefore(child, reference) {
        if (child.parentNode) { child.parentNode.removeChild(child); }
        var at = reference ? this.childNodes.indexOf(reference) : this.childNodes.length;
        this.childNodes.splice(at < 0 ? this.childNodes.length : at, 0, child);
        child.parentNode = this;
        __record(this, [child], []);
        return child;
      }
      removeChild(child) {
        var at = this.childNodes.indexOf(child);
        if (at < 0) { throw new Error("not a child"); }
        this.childNodes.splice(at, 1);
        child.parentNode = null;
        __record(this, [], [child]);
        return child;
      }
      remove() { if (this.parentNode) { this.parentNode.removeChild(this); } }
      addEventListener(type, fn, capture) {
        this.__listeners.push({ type: type, fn: fn, capture: capture === true || (capture && capture.capture === true) });
      }
      dispatchEvent(event) { return __dispatch(this, event); }
    }
    class FText extends FNode {
      constructor(data) { super(3); this.data = String(data); }
      get textContent() { return this.data; }
      cloneNode() { return new FText(this.data); }
    }
    class FElement extends FNode {
      constructor(localName) { super(1); this.localName = localName; this.tagName = localName.toUpperCase(); this.attrs = {}; this.style = {}; this.__guard = false; this.__size = null; }
      get className() { return this.attrs["class"] || ""; }
      set className(value) { this.attrs["class"] = String(value); }
      get type() { return this.attrs.type; }
      get href() { return this.attrs.href || ""; }
      get src() { return this.attrs.src || ""; }
      get currentSrc() { return this.attrs["data-current-src"] || this.attrs.src || ""; }
      get alt() { return this.attrs.alt || ""; }
      get title() { return this.attrs.title || ""; }
      get download() { return this.attrs.download || ""; }
      setAttribute(name, value) { this.attrs[name] = String(value); }
      removeAttribute(name) { delete this.attrs[name]; }
      getAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attrs, name) ? this.attrs[name] : null; }
      hasAttribute(name) { return this.getAttribute(name) !== null; }
      get children() { return this.childNodes.filter(function (n) { return n.nodeType === 1; }); }
      get lastElementChild() { var kids = this.children; return kids[kids.length - 1] || null; }
      get textContent() {
        if (this.__guard) { throw new Error("read the text of the page's own menu"); }
        return this.childNodes.map(function (n) { return n.textContent; }).join("");
      }
      set textContent(value) { this.childNodes = [new FText(value)]; this.childNodes[0].parentNode = this; }
      cloneNode(deep) {
        var copy = new FElement(this.localName);
        for (var key in this.attrs) { copy.attrs[key] = this.attrs[key]; }
        for (var s in this.style) { copy.style[s] = this.style[s]; }
        if (deep) { this.childNodes.forEach(function (c) { var d = c.cloneNode(true); d.parentNode = copy; copy.childNodes.push(d); }); }
        return copy;
      }
      matches(selector) { return __matches(this, selector); }
      closest(selector) { for (var n = this; n && n.nodeType === 1; n = n.parentNode) { if (__matches(n, selector)) { return n; } } return null; }
      querySelectorAll(selector) {
        var out = [];
        (function walk(node) {
          node.childNodes.forEach(function (child) {
            if (child.nodeType === 1) { if (__matches(child, selector)) { out.push(child); } walk(child); }
          });
        })(this);
        return out;
      }
      querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
      getBoundingClientRect() {
        var left = parseFloat(this.style.left) || 0, top = parseFloat(this.style.top) || 0;
        var width = 0, height = 0;
        if (this.__size) {
          var kids = this.children;
          width = this.__size.width;
          height = 12 + kids.filter(function (k) { return k.localName === "button"; }).length * 32
            + kids.filter(function (k) { return k.localName === "div" && !k.firstChild; }).length * 9;
          // A box is no taller than its `max-height`, as CSS has it (what is past it scrolls, or spills).
          var cap = parseFloat(this.style.maxHeight);
          if (isFinite(cap)) { height = Math.min(height, cap); }
        }
        return { left: left, top: top, width: width, height: height, right: left + width, bottom: top + height };
      }
    }
    class FDocument extends FNode {
      constructor() {
        super(9);
        this.documentElement = new FElement("html");
        this.body = new FElement("body");
        this.defaultView = null;
        this.__stack = [];
        this.appendChild(this.documentElement);
        this.documentElement.appendChild(this.body);
      }
      get ownerDocument() { return this; }
      createElement(tag) { return new FElement(tag); }
      createElementNS(ns, tag) { return new FElement(tag); }
      createTextNode(text) { return new FText(text); }
      elementsFromPoint(x, y) { return this.__stack.slice(); }
      querySelector(selector) { return this.documentElement.querySelector(selector); }
    }
    var document = new FDocument();

    // ---- Building a page
    function el(tag, attrs, parent) {
      var e = new FElement(tag);
      for (var key in (attrs || {})) { e.attrs[key] = attrs[key]; }
      if (parent) { parent.appendChild(e); }
      return e;
    }
    function text(parent, words) { var t = new FText(words); parent.appendChild(t); return t; }
    """#

    /// Evaluated first. `__V` is the version every address in the page names,
    /// set before this runs.
    static let source = dom + #"""
    var __V = __VERSION;
    var __log = [];
    var window = { webkit: { messageHandlers: { capsidShelfMenu: { postMessage: function (m) { __posted.push(JSON.parse(JSON.stringify(m))); } } } },
                   innerWidth: 1000, innerHeight: 700 };
    document.defaultView = window;
    var location = { protocol: "http:", hostname: "localhost", origin: "http://localhost:8123", href: "http://localhost:8123/" };

    // ---- Building the conversation
    function __address(tail) { return "http://localhost:8123/api/artifacts/versions/" + __V + (tail || ""); }

    // A paragraph and a link to a file with no version in its address.
    var __page = el("div", { id: "page" }, document.body);
    var __paragraph = el("p", {}, __page); text(__paragraph, "A sentence about plates.");
    var __link = el("a", { href: "http://localhost:8123/projects/p1/artifacts/a1?v=" + __V }, __page); text(__link, "qc_notes.md");
    var __plainLink = el("a", { href: "https://example.com/paper" }, __page); text(__plainLink, "a paper");

    // The Generated tray: a card for a picture, one for a file with no picture in it.
    var __tray = el("div", { "data-testid": "turn-artifact-tray" }, __page);
    var __cardWrap = el("div", { "class": "group relative shrink-0 w-32" }, __tray);
    var __card = el("button", { "data-testid": "turn-tray-card", "class": "flex w-full flex-col" }, __cardWrap);
    var __thumbBox = el("div", { "class": "min-h-0 flex-1 overflow-hidden" }, __card);
    var __thumb = el("img", { src: __address("?thumbnail=400"), alt: "z_prime.png", "class": "h-full w-full object-cover" }, __thumbBox);
    var __caption = el("div", { "class": "shrink-0 px-2 py-1" }, __card);
    var __captionText = el("span", {}, __caption); text(__captionText, "z_prime.png");
    var __cardWrap2 = el("div", { "class": "group relative shrink-0 w-32" }, __tray);
    var __card2 = el("button", { "data-testid": "turn-tray-card" }, __cardWrap2);
    var __captionText2 = el("span", {}, __card2); text(__captionText2, "notes.md");

    // A tile's picture, with the annotation layer over it.
    var __tile = el("div", { "class": "relative flex items-center justify-center h-full overflow-hidden" }, document.body);
    var __tileBox = el("div", { "class": "relative" }, __tile);
    var __tileImg = el("img", { src: __address("?v=" + __V), alt: "plate_map.png" }, __tileBox);
    var __layer = el("div", { "class": "absolute inset-0 pointer-events-auto cursor-crosshair" }, __tileBox);
    var __marker = el("span", {}, __layer);

    // An inline figure in a reply: the picture and a surface over it, a layer in that.
    var __inline = el("span", { "data-testid": "inline-annotated-image", "class": "relative inline-block" }, __page);
    var __inlineImg = el("img", { src: __address(), alt: "Z prime by plate" }, __inline);
    var __surface = el("span", { "data-annotated-image-surface": "", "class": "absolute inset-0" }, __inline);
    var __inlineLayer = el("span", { "class": "absolute inset-0" }, __surface);

    // Pictures that name no version.
    var __avatar = el("img", { src: "http://localhost:8123/static/avatar.png", alt: "Sam" }, __page);
    var __elsewhere = el("img", { src: "https://example.com/api/artifacts/versions/" + __V, alt: "remote" }, __page);

    // A modal over the conversation, its text above the tile's picture.
    var __modal = el("div", { "class": "fixed inset-0" }, document.body);
    var __modalText = el("p", {}, __modal); text(__modalText, "A file's words");

    // ---- A right-click, as the browser makes it: the event runs through the
    // document's capture listeners, then the observers deliver (a microtask).
    function __rightClick(target, options) {
      options = options || {};
      document.__stack = options.under || [];
      var event = new __Event("contextmenu", { bubbles: true, cancelable: true, clientX: options.x || 40, clientY: options.y || 60 });
      event.isTrusted = options.trusted !== false;
      __dispatch(target, event);
      __flush();
      return event;
    }

    // A right-click on something with no place in the page (a node with no parent, nothing at all).
    function __direct(target) {
      document.__listeners.filter(function (l) { return l.type === "contextmenu"; }).forEach(function (l) {
        l.fn({ type: "contextmenu", target: target, isTrusted: true, clientX: 0, clientY: 0 });
      });
      __flush();
    }

    // ---- The page's menu, as the bundle's component draws it
    var __menu = null, __wrapper = null, __ignoreEscape = false;
    function __guarded(element) {
      element.__guard = true;
      element.childNodes.forEach(function (c) { if (c.nodeType === 1) { __guarded(c); } });
      return element;
    }
    function __item(parent, label, options) {
      options = options || {};
      var button = el("button", { type: "button", role: "menuitem", "class": options.danger ? __DANGER : __ITEM, "data-label": label }, parent);
      if (options.icon !== false) {
        var box = el("span", { "data-cds": "Icon", "aria-hidden": "true", "style": "font-size: 16px; font-weight: 400;", "class": "icon-box" }, button);
        text(box, "");
      }
      text(button, label);
      return button;
    }
    // items: labels; "-" is a rule; "!x" is a red item. Options: label, size, left, top, icons, maxHeight and
    // overflowY (what the page itself put on the menu's style).
    function __openMenu(items, options) {
      options = options || {};
      __wrapper = el("div", { "class": "contents", "data-cds": "CdsLayerVarBridge" });
      __menu = el("div", { role: "menu", "aria-label": options.label === undefined ? "Artifact actions" : options.label, "class": __MENU }, __wrapper);
      __menu.style.left = (options.left === undefined ? 40 : options.left) + "px";
      __menu.style.top = (options.top === undefined ? 60 : options.top) + "px";
      __menu.__size = { width: 220 };
      if (options.maxHeight) { __menu.style.maxHeight = options.maxHeight; }
      if (options.overflowY) { __menu.style.overflowY = options.overflowY; }
      (items || ["Copy image", "Open in split view"]).forEach(function (label) {
        if (label === "-") { el("div", { "class": __RULE }, __menu); }
        else if (label[0] === "!") { __item(__menu, label.slice(1), { danger: true, icon: options.icons !== false }); }
        else { __item(__menu, label, { icon: options.icons !== false }); }
      });
      __guarded(__menu);
      document.body.appendChild(__wrapper);
      __flush();
      return __menu;
    }
    function __closeMenu() { if (__wrapper) { __wrapper.remove(); } __menu = null; __wrapper = null; }
    // The page's own hook: Escape on the document, or a pointer-down outside the menu.
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && __menu && !__ignoreEscape) { event.stopPropagation(); event.preventDefault(); __closeMenu(); __flush(); }
    }, true);
    document.addEventListener("pointerdown", function (event) {
      if (__menu && !__menu.contains(event.target)) { __closeMenu(); __flush(); }
    }, true);

    // What the menu looks like now: the page's items by label, a rule, Capsid's by words.
    function __shape(menu) {
      return (menu || __menu).children.map(function (c) {
        if (c.__guard) { return c.localName === "button" ? "page:" + c.attrs["data-label"] : "page-rule"; }
        if (c.localName === "div" && !c.firstChild) { return "rule"; }
        return "ours:" + c.textContent;
      });
    }
    function __ours() { return __menu ? __menu.children.filter(function (c) { return !c.__guard; }) : []; }
    function __click(button, trusted) {
      var event = new __Event("click", { bubbles: true, cancelable: true });
      event.isTrusted = trusted !== false;
      __dispatch(button, event);
      __flush();
      return event;
    }
    // The page's own arrow keys: every menu item or enabled button in the menu.
    function __arrowStops(menu) { return menu.querySelectorAll("[role='menuitem']"); }
    """#
}
