// FakeModelPage.swift — a made-up page for the model-menu script
// (AskModel/ModelPickerMenu.swift), run in JavaScriptCore on FakeFigurePage's
// small DOM: a session with a composer (a message box, and the model picker as
// the page draws it in its two shapes), a second composer, and a stand-in for
// the popup the page draws when the picker opens, with the markup and classes
// of Claude Science 0.1.70's design-system menu (index-DhEuR7nq.js: the menu
// `lge`, its list `Ame`, the model item `pR` through `eU`, the rule `OS`, the
// "More models" row `tU`). Nothing in it is a real page or a real name.
//
// The stand-in menu is guarded: any read of `textContent` on the page's own
// items throws, so a script that read an item's words would fail its tests.
// The page's reply to "may I?" is `__show` (true, false, or never).
import Foundation

enum FakeModelPage {
    /// The classes of the page's menu, list, items and rule, as the bundle spells them.
    static let popupClass = "cds-reset draggable-none relative flex flex-col min-w-[128px] max-w-[320px] max-h-[var(--available-height)] text-body text-primary outline-none focus-visible:outline-hidden max-w-[min(26rem,var(--available-width))]"
    static let listClass = "min-h-0 overflow-y-auto scroll-fade-y rounded-[inherit] border-b-[length:var(--cds-ring-inner)] border-transparent p-1"
    static let itemClass = "cds-reset flex w-full items-center gap-xs compact:px-2 comfortable:px-2.5 py-[calc((var(--cds-h-control)-var(--cds-leading-body))/2)] rounded text-body [--cds-shortcut-cap-ink:var(--cds-text-muted)] select-none outline-none focus-visible:outline-hidden data-[disabled]:opacity-disabled data-[disabled]:pointer-events-none text-primary data-[highlighted]:bg-fill-ghost-hover"
    /// An item with a second line (a model with its description) has the page's extra padding under it.
    static let secondLine = "pb-[calc((var(--cds-h-control)-var(--cds-font-size-body)-var(--cds-leading-footnote)+var(--cds-font-size-footnote))/2)]"
    static let submenuClass = itemClass + " justify-between data-[popup-open]:bg-fill-ghost-hover"
    static let ruleClass = "compact:mx-2 comfortable:mx-2.5 my-1 h-px bg-border"

    /// Evaluated after `FakeFigurePage.dom`; `__ITEM`, `__SECOND`, `__POPUP`, `__LIST`, `__SUBMENU` and `__RULE`
    /// are set before it runs.
    static let source = FakeFigurePage.dom + #"""
    // What the page answers when the script asks "may I?": true, false, "never" (no answer) or "refuse" (an error).
    var __show = true;
    var window = { webkit: { messageHandlers: { capsidAskMenu: { postMessage: function (m) {
      var copy = JSON.parse(JSON.stringify(m));
      __posted.push(copy);
      if (copy.armed !== true) { return Promise.resolve({ show: false }); }
      if (__show === "never") { return new Promise(function () {}); }
      if (__show === "refuse") { return Promise.reject(new Error("no")); }
      return Promise.resolve({ show: __show === true });
    } } } }, innerWidth: 1000, innerHeight: 700 };
    document.defaultView = window;
    var location = { protocol: "http:", hostname: "localhost", origin: "http://localhost:8123", href: "http://localhost:8123/" };

    // ---- A session: a reply, then the composer with its message box and its footer
    var __page = el("div", { id: "page" }, document.body);
    var __reply = el("p", {}, __page); text(__reply, "A sentence about plates.");
    var __composer = el("div", { "data-testid": "composer", "class": "relative flex flex-col gap-2 bg-bg-000 px-3 py-2 rounded-2xl" }, __page);
    var __box = el("div", { role: "textbox", "aria-multiline": "true", contenteditable: "true", "data-placeholder": "Reply" }, __composer);
    var __footer = el("div", { "class": "flex items-center gap-1 h-12" }, __composer);
    var __plus = el("button", { type: "button", "data-testid": "composer-plus-menu", "aria-haspopup": "menu" }, __footer);
    // The plain picker: a wrapper with the test id, the button in it.
    var __pickerWrap = el("div", { "data-testid": "model-selector", "class": "flex-shrink-0" }, __footer);
    var __picker = el("button", { type: "button", "aria-label": "Model: Large", "aria-haspopup": "menu", "aria-expanded": "false" }, __pickerWrap);
    var __pickerWords = el("span", {}, __picker); text(__pickerWords, "Large");

    // A second composer (the aside's), with a catalog picker whose button carries the test id itself, and its own box.
    var __aside = el("div", { "data-testid": "composer" }, document.body);
    var __asideBox = el("div", { role: "textbox", "aria-multiline": "true", contenteditable: "true" }, __aside);
    var __asideFooter = el("div", {}, __aside);
    var __asidePicker = el("button", { type: "button", "data-testid": "model-selector", "data-cds": "ModelSelector", "aria-haspopup": "menu" }, __asideFooter);
    var __asideWords = el("span", {}, __asidePicker); text(__asideWords, "Small");

    // A button outside the composer, to press.
    var __other = el("button", { type: "button", "aria-haspopup": "menu" }, __page);

    // The message box's content: words, a line break, a mention chip, a dictation ghost, an upload chip.
    function __type(box, parts) {
      box.childNodes.slice().forEach(function (c) { box.removeChild(c); });
      parts.forEach(function (part) {
        if (typeof part === "string") { text(box, part); return; }
        var node = el(part.tag, part.attrs || {}, box);
        if (part.words !== undefined) { text(node, part.words); }
        (part.children || []).forEach(function (c) {
          if (typeof c === "string") { text(node, c); } else { var inner = el(c.tag, c.attrs || {}, node); if (c.words !== undefined) { text(inner, c.words); } }
        });
      });
    }

    // ---- Events
    function __press(target, options) {
      options = options || {};
      var event = new __Event(options.type || "pointerdown", { bubbles: true, cancelable: true, key: options.key });
      event.isTrusted = options.trusted !== false;
      if (options.button !== undefined) { event.button = options.button; }
      __dispatch(target, event);
      __flush();
      return event;
    }

    // ---- The popup, as the design system draws it
    var __popup = null, __layer = null, __list = null, __ignoreEscape = false;
    function __guarded(element) {
      element.__guard = true;
      element.childNodes.forEach(function (c) { if (c.nodeType === 1) { __guarded(c); } });
      return element;
    }
    function __modelItem(parent, label, options) {
      options = options || {};
      var item = el("div", { role: "menuitemradio", "aria-checked": options.checked ? "true" : "false", tabindex: "-1", "class": __ITEM + " " + __SECOND, "data-model-id": label.toLowerCase(), "data-label": label }, parent);
      var words = el("span", { "class": "flex min-w-0 flex-1 flex-col" }, item);
      var name = el("span", { "class": "truncate" }, words); text(name, label);
      var detail = el("span", { "class": "truncate text-footnote text-muted" }, words); text(detail, "A made-up description");
      return item;
    }
    function __rule(parent) { return el("div", { role: "separator", "aria-orientation": "horizontal", "class": __RULE }, parent); }
    // Options: variant ("catalog": data-cds on the popup; "plain": the data-testid), models, separators, more (a
    // "More models" row), note (a closing note), header (a flex wrapper with a header, as a popup header gives),
    // list (false: no list element), cds ("Menu": a popup with another name), role.
    function __openPopup(options) {
      options = options || {};
      __layer = el("div", { "class": "cds-root pointer-events-auto", "data-cds-portal": "" });
      var positioner = el("div", { role: "presentation" }, __layer);
      var attrs = { role: options.role || "menu", "aria-labelledby": "picker-id", "class": __POPUP, tabindex: "-1" };
      if (options.variant === "plain") { attrs["data-testid"] = "model-selector-popup"; } else { attrs["data-cds"] = options.cds || "ModelSelector"; }
      __popup = el("div", attrs, positioner);
      var holder = __popup;
      if (options.header) {
        holder = el("div", { "class": "flex min-h-0 flex-col overflow-hidden rounded-[inherit]" }, __popup);
        var header = el("div", { "class": "shrink-0 px-1 pt-1" }, holder);
        el("span", {}, header);
      }
      __list = options.list === false ? holder : el("div", { "class": __LIST, "data-cds-sheet-scroll": "" }, holder);
      var group = el("div", { role: "group" }, __list);
      (options.models || ["Large", "Medium", "Small"]).forEach(function (label, index) { __modelItem(group, label, { checked: index === 0 }); });
      if (options.separators !== false) { __rule(__list); }
      if (options.more !== false) {
        var more = el("div", { role: "menuitem", "aria-haspopup": "menu", tabindex: "-1", "class": __SUBMENU, "data-label": "More models" }, __list);
        var moreWords = el("span", { "class": "min-w-0 flex-1 truncate" }, more); text(moreWords, "More models");
      }
      if (options.note) { __rule(__list); var note = el("div", { role: "presentation", "class": "px-md py-1" }, __list); text(note, "A made-up note"); }
      __guarded(__popup);
      document.body.appendChild(__layer);
      __flush();
      return __popup;
    }
    function __closePopup() { if (__layer) { __layer.remove(); } __popup = null; __layer = null; __list = null; }
    // The design system's own hooks, on the document in the bubble phase as a library's are: Escape reaching it
    // (from the menu or not) closes the popup, and so does a pointer-down outside it.
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && __popup && !__ignoreEscape) { event.stopPropagation(); event.preventDefault(); __closePopup(); __flush(); }
    }, false);
    document.addEventListener("pointerdown", function (event) {
      if (__popup && !__popup.contains(event.target)) { __closePopup(); __flush(); }
    }, false);

    // What the list looks like now: the page's items by label, a rule, the page's note, Capsid's by words.
    function __shape(list) {
      return (list || __list).children.map(function (c) {
        if (c.__guard) {
          if (c.attrs.role === "group") { return "page-group:" + c.children.map(function (m) { return m.attrs["data-label"]; }).join("+"); }
          if (c.attrs.role === "separator") { return "page-rule"; }
          if (c.attrs.role === "presentation") { return "page-note"; }
          return "page:" + c.attrs["data-label"];
        }
        if (c.attrs.role === "separator") { return "rule"; }
        return "ours:" + c.textContent;
      });
    }
    function __ours() { return __list ? __list.children.filter(function (c) { return !c.__guard; }) : []; }
    function __click(node, trusted) {
      var event = new __Event("click", { bubbles: true, cancelable: true });
      event.isTrusted = trusted !== false;
      __dispatch(node, event);
      __flush();
      return event;
    }
    // The page draws the list again: its items are taken out and put back, in front of anything foreign.
    function __redraw() {
      var kids = __list.children.filter(function (c) { return c.__guard; });
      kids.forEach(function (c) { __list.removeChild(c); });
      kids.forEach(function (c) { __list.appendChild(c); });
      __flush();
    }
    // The page replaces the list element, with the same items (a popup header came or went).
    function __replaceList() {
      var fresh = el("div", { "class": __LIST, "data-cds-sheet-scroll": "" });
      __list.children.filter(function (c) { return c.__guard; }).forEach(function (c) { fresh.appendChild(c); });
      __list.parentNode.insertBefore(fresh, __list);
      __list.parentNode.removeChild(__list);
      __list = fresh;
      __flush();
    }
    """#
}
