// FakeConversationPage.swift — a made-up conversation for Show Where It Came From's
// script (Shelf/SourceSeek.swift), run in JavaScriptCore on the small DOM of
// FakeFigurePage. It is modelled on what the 0.1.70 bundle draws (index-DhEuR7nq.js),
// read from its files only; nothing in it is a real page, a real session or a real name:
//
// - a scroller, `[data-testid="conversation-scroll"]`, and in it a sizer holding a top
//   spacer, the rows near the screen and a bottom spacer: a virtual list, so a row far from
//   the screen is not in the page. A row is a `div` with `data-index` and `data-rs-index`.
//   A user's message is one row; Claude's turn is another, a carousel that holds its
//   messages (each a `div` with `data-msg-idx`, the message's number in the history; a run
//   of tool calls carries several) and, last, the Generated tray under them.
// - the tray, `[data-testid="turn-artifact-tray"]`: "GENERATED · n" over a card
//   (`turn-tray-card`) for each file, five at most before a "+n more" button. A picture's
//   card holds a thumbnail whose address names the version; a file with no picture, a
//   preview; both a file-name label whose title is the name. A turn that made nothing has none.
// - only the last `seed` messages are loaded. A scroll that goes up, with the scroll
//   position under 1800 pixels, loads `page` more a moment later (`loadMs`), and by default
//   the page keeps what is on the screen where it was (`anchor`); `floor` is the first
//   message that can be loaded (a session continued from another folds the rest away).
// - a jump of more than three screens draws placeholders (`conversation-seek-placeholder`,
//   no message numbers) for `seekMs`, as the page does for a fast scroll.
// - the text the page draws is guarded: a read of its `textContent` throws, so a script
//   that read the words of the conversation would fail its tests.
// - every element has `animate`, which records what it was asked (`__marks`).
//
// The messages of an exchange `e` are 8e (the user's), 8e+1 (a tool call), 8e+2 (its result,
// which is no element), 8e+3 (text), 8e+4 (a tool call), 8e+5 (its result), 8e+6 (the
// closing text, which a test goes to) and 8e+7 (not drawn). A turn's files: none when
// `e % 5 == 1`; else two when `e % 3 == 0` (a picture, then a Markdown file) and one
// (a picture) otherwise; eight at `bigTray`. The turn at `tall` has a closing text of 900
// pixels, taller than the screen. The frame starts 100 pixels down the page.
import Foundation

enum FakeConversationPage {
    struct Config: Encodable {
        /// Messages in the history: a multiple of 8.
        var total = 2400
        /// Messages loaded at first, and loaded by each scroll up.
        var seed = 200
        var page = 200
        /// The first message that can be loaded.
        var floor = 0
        /// The height of the scroller.
        var view = 700
        /// How long a long jump draws placeholders, and how long a load takes (milliseconds).
        var seekMs = 250
        var loadMs = 150
        /// Whether a load keeps what is on the screen where it was.
        var anchor = true
        /// Whether a load fails.
        var failLoads = false
        /// The exchange with eight files, and the one with a closing text taller than the screen.
        var bigTray = 12
        var tall = 7
        /// Whether every file with no picture is called notes.md.
        var sameNames = false
        /// The scroller is not there at all.
        var empty = false
    }

    static func source(_ config: Config = Config()) -> String {
        let data = (try? JSONEncoder().encode(config)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "var __cfg = \(data);\n" + body
    }

    /// The version of file `k` of exchange `e` (for a test to ask for).
    static func version(_ e: Int, _ k: Int) -> String {
        "aaaaaaaa-0000-4000-8000-" + String(format: "%012d", e * 10 + k)
    }

    /// The closing text's message number of exchange `e`: the reply a test goes to.
    static func reply(_ e: Int) -> Int { 8 * e + 6 }

    private static let body = #"""
    var performance = { now: function () { return __now; } };
    var FRAME_TOP = 100, VIEW = __cfg.view, HEADER = 40, FOOT = 120, OVER = 600, USER_H = 70, PER = 8;
    var __top = 0, __first = 0, __lastE = __cfg.total / PER - 1;
    var __loading = false, __failed = false, __seeking = false, __loads = 0, __renders = 0, __peak = 0;
    var __marks = [], __clicks = [];
    var __cache = {};
    FElement.prototype.animate = function (keyframes, options) { __marks.push({ target: this, keyframes: keyframes, options: options }); return {}; };

    function pad(n) { return ("000000000000" + n).slice(-12); }
    function versionOf(e, k) { return "aaaaaaaa-0000-4000-8000-" + pad(e * 10 + k); }
    function addressOf(v, tail) { return "http://localhost:8123/api/artifacts/versions/" + v + (tail || ""); }
    function box(top, height) { return { left: 0, top: top, width: 600, height: height, right: 600, bottom: top + height }; }

    // What an exchange holds.
    function plan(e) {
      var count = e === __cfg.bigTray ? 8 : (e % 5 === 1 ? 0 : (e % 3 === 0 ? 2 : 1));
      var text2 = e === __cfg.tall ? 900 : 150 + (e % 4) * 20;
      var tray = count > 0 ? 24 + 100 + 14 : 0;
      return { e: e, count: count, text2: text2, tray: tray, turn: 20 + 36 + 120 + 36 + text2 + tray + 28 };
    }
    function hasOlder() { return __first * PER > __cfg.floor; }
    function rowsList() {
      var out = [], y = hasOlder() ? HEADER : 0;
      for (var e = __first; e <= __lastE; e++) {
        var p = plan(e);
        out.push({ key: "u" + e, kind: "user", e: e, h: USER_H, y: y }); y += USER_H;
        out.push({ key: "t" + e, kind: "turn", e: e, h: p.turn, y: y, plan: p }); y += p.turn;
      }
      out.end = y + FOOT;
      return out;
    }

    // An element with a place: its row, and how far down the row it is.
    function put(element, row, off, h) {
      element.__row = row; element.__off = off; element.__h = h;
      element.getBoundingClientRect = function () {
        var base = element.__row ? element.__row.__y : element.__y;
        return box(FRAME_TOP + base + element.__off - __top, element.__h);
      };
      return element;
    }
    function words(parent, said) { var holder = el("p", {}, parent); text(holder, said); holder.__guard = true; return holder; }

    function buildUser(r) {
      var row = put(el("div", { "data-index": r.key, "data-rs-index": r.key }), null, 0, r.h);
      var message = put(el("div", { "data-testid": "user-message", "data-msg-idx": String(PER * r.e) }, row), row, 0, r.h);
      words(message, "Plot the plates.");
      return row;
    }
    function buildCard(tray, row, off, e, k) {
      var wrap = put(el("div", { "class": "group relative shrink-0 w-32" }, tray), row, off, 80);
      var card = put(el("button", { "data-testid": "turn-tray-card", type: "button", "class": "flex w-full flex-col" }, wrap), row, off, 80);
      var inner = el("div", { "class": "min-h-0 flex-1 overflow-hidden" }, card);
      var caption = el("div", { "class": "shrink-0 px-2 py-1" }, card);
      var name;
      if (k % 2 === 0) {
        el("img", { src: addressOf(versionOf(e, k), "?thumbnail=400"), alt: "plot_" + e + "_" + k + ".png" }, inner);
        name = "plot_" + e + "_" + k + ".png";
      } else {
        words(inner, "Plate 7 drifts.");
        name = __cfg.sameNames ? "notes.md" : "notes_" + e + "_" + k + ".md";
      }
      // Every card has the file-name label, whose title is the whole name.
      var label = el("span", { "data-testid": "middle-truncated-filename", "class": "flex min-w-0 overflow-hidden", title: name }, caption);
      var shown = el("span", { "class": "truncate" }, label); text(shown, name); shown.__guard = true;
      return card;
    }
    function buildTray(rel, row, off, p) {
      var tray = put(el("div", { "data-testid": "turn-artifact-tray", "class": "mt-3.5" }, rel), row, off, p.tray);
      var label = put(el("div", { "class": "mb-1.5 text-[10.5px]" }, tray), row, off, 24);
      text(label, "GENERATED · " + p.count); label.__guard = true;
      var line = put(el("div", { "class": "flex flex-wrap gap-2" }, tray), row, off + 24, 100);
      var visible = p.count > 6 ? 5 : p.count;
      for (var k = 0; k < visible; k++) { buildCard(line, row, off + 24, p.e, k); }
      if (p.count > 6) {
        var more = put(el("button", { "data-testid": "turn-tray-overflow", type: "button" }, line), row, off + 24, 80);
        more.addEventListener("click", function () { __clicks.push("overflow"); });
        text(more, "+" + (p.count - 5) + " more"); more.__guard = true;
      }
      return tray;
    }
    function buildTurn(r) {
      var p = r.plan, e = p.e, off = 10;
      var row = put(el("div", { "data-index": r.key, "data-rs-index": r.key }), null, 0, r.h);
      var carousel = el("div", { "class": "group/carousel relative text-sm" }, row);
      var rel = el("div", { "class": "relative" }, carousel);
      function section(msg, h, said) {
        var d = put(el("div", { "data-msg-idx": String(msg), "class": "relative mb-4" }, rel), row, off, h);
        words(d, said); off += h;
        return d;
      }
      section(PER * e + 1, 36, "Ran a script.");
      section(PER * e + 3, 120, "Plate 7 drifts after the midpoint.");
      section(PER * e + 4, 36, "Ran another.");
      section(PER * e + 6, p.text2, "The edge wells run low.");
      if (p.count > 0) { buildTray(rel, row, off, p); off += p.tray; }
      put(el("div", { "class": "mt-2 flex" }, rel), row, off, 28);
      return row;
    }
    function realRow(r) {
      if (!__cache[r.key]) { __cache[r.key] = r.kind === "user" ? buildUser(r) : buildTurn(r); }
      return __cache[r.key];
    }
    function placeholder(r) {
      var key = "p" + r.key;
      if (!__cache[key]) { __cache[key] = put(el("div", { "data-index": r.key, "data-testid": "conversation-seek-placeholder" }), null, 0, r.h); }
      return __cache[key];
    }
    function spacer(height) { var s = el("div", { "aria-hidden": "true" }); s.style.height = height + "px"; return s; }

    var scroller = el("div", { "data-testid": "conversation-scroll", tabindex: "0", "class": "relative overflow-y-auto" }, __cfg.empty ? null : document.body);
    var sizer = el("div", { "data-testid": "conversation-sizer", "class": "relative w-full" }, scroller);
    scroller.getBoundingClientRect = function () { return box(FRAME_TOP, VIEW); };
    Object.defineProperty(scroller, "clientHeight", { get: function () { return VIEW; } });
    Object.defineProperty(scroller, "scrollHeight", { get: function () { return rowsList().end; } });
    Object.defineProperty(scroller, "scrollTop", { get: function () { return __top; }, set: function (v) { __scrollTo(Number(v)); } });

    function __maxTop() { return Math.max(0, rowsList().end - VIEW); }
    // The page draws the rows near the screen: what it had drawn is reused, not made again.
    function __render() {
      __renders++;
      var rows = rowsList(), first = -1, last = -1;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].y + rows[i].h >= __top - OVER && rows[i].y <= __top + VIEW + OVER) { if (first < 0) { first = i; } last = i; }
      }
      var children = [spacer(first < 0 ? 0 : rows[first].y)];
      for (i = first; first >= 0 && i <= last; i++) {
        var drawn = __seeking ? placeholder(rows[i]) : realRow(rows[i]);
        drawn.__y = rows[i].y;
        children.push(drawn);
      }
      children.push(spacer(rows.end - (last >= 0 ? rows[last].y + rows[last].h : 0)));
      sizer.childNodes.forEach(function (c) { c.parentNode = null; });
      sizer.childNodes = children;
      children.forEach(function (c) { c.parentNode = sizer; });
    }
    // The page's own scroll handler: a scroll that goes up, near the top, loads earlier messages.
    function __scrollTo(v) {
      var next = Math.max(0, Math.min(__maxTop(), v)), before = __top;
      if (next === before) { return; }
      __top = next;
      if (Math.abs(next - before) > 3 * VIEW && __cfg.seekMs > 0) {
        __seeking = true;
        setTimeout(function () { __seeking = false; __render(); }, __cfg.seekMs);
      }
      if (!(next > before) && next < 1800 && hasOlder() && !__loading && !__failed) { __loadOlder(); }
      __render();
    }
    function __loadOlder() {
      __loading = true;
      setTimeout(function () {
        __loading = false;
        if (__cfg.failLoads) { __failed = true; return; }
        var oldEnd = rowsList().end;
        __first -= Math.min(__cfg.page / PER, __first - Math.ceil(__cfg.floor / PER));
        __loads++;
        if (__cfg.anchor) { __top += rowsList().end - oldEnd; }
        __render();
      }, __cfg.loadMs);
    }
    __first = (__cfg.total - __cfg.seed) / PER;
    __top = __maxTop();
    __render();

    // ---- What a test asks about
    function __messages() {
      var found = [];
      scroller.querySelectorAll("[data-msg-idx]").forEach(function (e) { found.push(e.getAttribute("data-msg-idx")); });
      return found;
    }
    function __tray(e) { var turn = __cache["t" + e]; return turn ? turn.querySelector("[data-testid='turn-artifact-tray']") : null; }
    function __replyElement(e) {
      var turn = __cache["t" + e];
      return turn ? turn.querySelectorAll("[data-msg-idx]").filter(function (x) { return x.getAttribute("data-msg-idx") === String(PER * e + 6); })[0] : null;
    }
    // Where an element is in the frame, as a fraction of its height down from the frame's top.
    function __fraction(element) { return (element.getBoundingClientRect().top - FRAME_TOP) / VIEW; }
    function __inFrame(element) {
      var b = element.getBoundingClientRect();
      return b.bottom > FRAME_TOP && b.top < FRAME_TOP + VIEW;
    }
    function __marked() {
      return JSON.stringify(__marks.map(function (m) {
        var picture = m.target.querySelector("img"), label = m.target.querySelector("[data-testid='middle-truncated-filename']");
        return { testid: m.target.getAttribute("data-testid"), src: picture ? picture.getAttribute("src") : null,
                 title: label ? label.getAttribute("title") : null, frames: m.keyframes.length, ms: m.options.duration };
      }));
    }
    // A turn made again from the plan, to compare what the script touched with what was made.
    function __fresh(e) { return buildTurn({ key: "fresh" + e, plan: plan(e), h: plan(e).turn }).querySelector("[data-testid='turn-artifact-tray']"); }
    function __attributesOf(element) {
      var all = [];
      (function walk(node) {
        all.push(node.localName + JSON.stringify(node.attrs));
        node.children.forEach(walk);
      })(element);
      return all.join("|");
    }
    // The scroller's listeners and the capture listeners the script leaves on the document.
    function __documentListeners() { return document.__listeners.length; }
    // A real wheel, touch, key or press (the browser made it) or one the page made.
    function __input(type, trusted) {
      var event = new __Event(type, { bubbles: true, cancelable: true });
      event.isTrusted = trusted;
      __dispatch(document.body, event);
    }
    """#
}
