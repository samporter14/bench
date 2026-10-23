// ConversationMenu.swift — Add to Shelf, Keep with Data and Code…, Open as
// Reference and Show in Results in the right-click menu of a figure or a file
// link in Claude Science's page (DESIGN.md, Shelf → From the conversation;
// board 10). Two ways in, one script.
//
// The Mac's own menu. WebKit's menu says which kind of thing was clicked (its
// items are "Copy Image", "Copy Link"…) but never which address, and the
// address is what names the file; so a small user script, in a content world
// of its own, tells Swift what the last right-click was on, as `TabContextMenu`
// does for tabs, and the main window's web view adds the items when its menu
// opens. That is the way in for a plain picture or a link.
//
// The page's own menu. Claude Science draws a figure's menu itself (a tile, an
// inline picture, a card in the Generated tray, the side pane's image: one
// component, `role="menu"` named "Artifact actions") and cancels the Mac's, so
// `willOpenMenu` never runs for them. For those the same script waits, for two
// seconds after a right-click on a figure whose address names a version, for
// that menu to open, and adds a rule and the four items at its end (above its
// red item and that item's rule, when it has one, so the destructive item stays
// last, as on the Mac), drawn with the menu's own item classes. A click on one tells Swift, which runs the same
// action as the Mac menu's item, and the script closes the page's menu the way
// the page does (Escape on the document).
//
// The order of the first path is not an API guarantee (see TabContextMenu): the
// script posts from inside the `contextmenu` event and WebKit asks for the menu
// after it, over one connection. A message that came late is not fresh, and
// the menu simply has no Shelf items; the File menu's commands stay the way in
// from Results. Nothing read from the page is logged, and the script never
// reads the text of the page's own menu items.
import AppKit
import Foundation
import WebKit

// MARK: What was clicked

/// The four things the menu does with the clicked file. The raw values are
/// the words the page script posts when one of them is chosen in the page's
/// own menu.
enum ConversationAction: String, CaseIterable, Sendable {
    case addToShelf, keep, openAsReference, showInResults

    var title: String {
        switch self {
        case .addToShelf: ShelfWords.add
        case .keep: ShelfWords.keep
        case .openAsReference: "Open as Reference"
        case .showInResults: "Show in Results"
        }
    }
}

/// A figure or a file link the last right-click was on, once its address named
/// a version.
struct ConversationPick: Equatable, Sendable {
    enum Kind: String, Sendable { case image, link }
    let kind: Kind
    /// The version its address names.
    let version: String
    /// What the page called it (alt text, link text), or "Figure" and "File",
    /// until the daemon's facts give the file's name.
    let name: String
}

enum ConversationMenuMessage {
    /// A name longer than this is cut before it is read.
    static let maxName = 300

    /// The pick a message names: `{kind: "image" | "link", url, name}` whose
    /// address names a version on the daemon's origin. Everything else
    /// (`{kind: null}`, another shape, an address that isn't an artifact's) is
    /// no pick, which clears the last one.
    static func pick(in body: Any?, daemonPort: Int?) -> ConversationPick? {
        guard let body = body as? [String: Any], let word = body["kind"] as? String,
              let kind = ConversationPick.Kind(rawValue: word), let url = body["url"] as? String,
              let version = ShelfAddress.version(in: url, daemonPort: daemonPort) else { return nil }
        let hint = String(((body["name"] as? String) ?? "").prefix(maxName))
        return ConversationPick(kind: kind, version: version, name: ShelfAddress.name(hint: hint, isImage: kind == .image))
    }

    /// An item chosen in the page's own menu: the action, and the figure the
    /// script noted at the right-click.
    struct Choice: Equatable, Sendable {
        let action: ConversationAction
        let pick: ConversationPick
    }

    /// The choice a message names: `{action, version, name}` (and `kind`,
    /// "image" unless it says "link": the menu is a figure's). The action must
    /// be one of the four, and the version a full id as the daemon writes it
    /// (`PlanCheck.isFrameID`), which is all the script could have found in an
    /// address: nothing else is acted on, and no address comes with it.
    static func choice(in body: Any?) -> Choice? {
        guard let body = body as? [String: Any], let word = body["action"] as? String,
              let action = ConversationAction(rawValue: word),
              let version = body["version"] as? String, PlanCheck.isFrameID(version) else { return nil }
        let kind = (body["kind"] as? String).flatMap(ConversationPick.Kind.init(rawValue:)) ?? .image
        let hint = String(((body["name"] as? String) ?? "").prefix(maxName))
        return Choice(action: action, pick: ConversationPick(kind: kind, version: version,
                                                             name: ShelfAddress.name(hint: hint, isImage: kind == .image)))
    }

    /// The page's menu opened after a right-click on a figure, and the script
    /// could not put the items in it: `{unplaced: true}`.
    static func isUnplaced(_ body: Any?) -> Bool {
        guard let body = body as? [String: Any] else { return false }
        return body["unplaced"] as? Bool == true
    }
}

/// The pick the last right-click made, for one menu, within a second of the
/// message: the same rule as `TabMenuTarget`.
struct ConversationTarget: Equatable {
    static let freshFor: Duration = .seconds(1)

    private var pick: ConversationPick?
    private var recordedAt: ContinuousClock.Instant?

    mutating func record(_ pick: ConversationPick?, at instant: ContinuousClock.Instant) {
        self.pick = pick
        recordedAt = instant
    }

    /// The pick, if it was recorded within `freshFor` before `instant`. Either
    /// way it is forgotten.
    mutating func take(at instant: ContinuousClock.Instant) -> ConversationPick? {
        defer {
            pick = nil
            recordedAt = nil
        }
        guard let pick, let recordedAt, instant >= recordedAt, instant - recordedAt <= Self.freshFor else { return nil }
        return pick
    }
}

// MARK: The menu

@MainActor
final class ConversationMenu {
    static let handlerName = "capsidShelfMenu"
    /// Its own world: the page can't see the script, or reach its handler.
    static let world = WKContentWorld.world(name: "capsid-shelf")
    static let itemID = NSUserInterfaceItemIdentifier("capsid.shelfMenu")

    /// The web view the messages must come from.
    weak var webView: WKWebView?

    private var target = ConversationTarget()
    private let now: () -> ContinuousClock.Instant
    private let daemonPort: @MainActor () -> Int?
    private let run: @MainActor (ConversationAction, ConversationPick) -> Void
    private let breadcrumbs: CompatBreadcrumbs

    /// `run` is what an item does, in the Mac's menu and in the page's own.
    /// `now` is the clock, which tests replace, and `breadcrumbs` is where
    /// "the figure menu didn't look as Capsid expects" goes.
    init(now: @escaping () -> ContinuousClock.Instant = { .now },
         daemonPort: @escaping @MainActor () -> Int?,
         breadcrumbs: CompatBreadcrumbs = .shared,
         run: @escaping @MainActor (ConversationAction, ConversationPick) -> Void) {
        self.now = now
        self.daemonPort = daemonPort
        self.breadcrumbs = breadcrumbs
        self.run = run
    }

    /// Adds the user script and its message handler. The controller keeps a
    /// strong reference to the handler, so it gets a proxy that only holds
    /// this object weakly.
    func install(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.world))
        controller.add(WeakConversationHandler(menu: self), contentWorld: Self.world, name: Self.handlerName)
    }

    func record(_ pick: ConversationPick?) {
        target.record(pick, at: now())
    }

    /// Adds the items to `menu` if the last right-click was on an artifact's
    /// figure or link, just now. Otherwise the menu is left as WebKit made it.
    func addItems(to menu: NSMenu) {
        guard let pick = target.take(at: now()) else { return }
        Self.insertItems(into: menu, for: pick, run: run)
    }

    /// Board 10's menu: the element's own items, a separator, Add to Shelf
    /// (⌥⌘S), Keep with Data and Code…, Open as Reference, a separator, Show in
    /// Results, and a separator before the rest of WebKit's menu. Not added
    /// twice. With no separator in WebKit's menu the group goes at its end.
    static func insertItems(into menu: NSMenu, for pick: ConversationPick,
                            run: @escaping @MainActor (ConversationAction, ConversationPick) -> Void) {
        guard !menu.items.contains(where: { $0.identifier == itemID }) else { return }
        func item(_ action: ConversationAction) -> NSMenuItem {
            let handler = ConversationMenuAction(action: action, pick: pick, run: run)
            let item = NSMenuItem(title: action.title, action: #selector(ConversationMenuAction.fire(_:)), keyEquivalent: "")
            item.target = handler
            // The item holds its target weakly; this keeps it alive as long as the item.
            item.representedObject = handler
            item.identifier = itemID
            if action == .addToShelf {
                item.keyEquivalent = "s"
                item.keyEquivalentModifierMask = [.command, .option]
            }
            return item
        }
        func separator() -> NSMenuItem {
            let separator = NSMenuItem.separator()
            separator.identifier = itemID
            return separator
        }
        let group = [item(.addToShelf), item(.keep), item(.openAsReference), separator(), item(.showInResults)]
        if let split = menu.items.firstIndex(where: \.isSeparatorItem) {
            var at = split == 0 ? 0 : split + 1
            for entry in group {
                menu.insertItem(entry, at: at)
                at += 1
            }
            // Between the group and what WebKit puts after it.
            if at < menu.items.count, !menu.items[at].isSeparatorItem { menu.insertItem(separator(), at: at) }
        } else {
            if !menu.items.isEmpty { menu.addItem(separator()) }
            for entry in group { menu.addItem(entry) }
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        let accepted = TabMenuMessage.isAccepted(
            isMainFrame: message.frameInfo.isMainFrame,
            fromMainWebView: message.webView != nil && message.webView === webView,
            isDaemonOrigin: WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port,
                                                    daemonPort: daemonPort()))
        hear(message.body, accepted: accepted)
    }

    /// What a message from the page means, once its sender is known to be the
    /// main window's own page (`accepted`). Three shapes:
    /// - `{kind, url, name}`: what the last right-click was on, kept a second
    ///   for the Mac's menu (anything else clears it);
    /// - `{action, version, name}`: an item chosen in the page's own menu, run
    ///   at once (that menu can stay open far longer than a second);
    /// - `{unplaced: true}`: the page's menu opened and the items had nowhere
    ///   to go, which is a change in Claude Science worth a breadcrumb.
    /// From anyone else a message is nothing, and clears the last pick.
    func hear(_ body: Any?, accepted: Bool) {
        guard accepted else {
            record(nil)
            return
        }
        if let choice = ConversationMenuMessage.choice(in: body) {
            run(choice.action, choice.pick)
        } else if ConversationMenuMessage.isUnplaced(body) {
            breadcrumbs.record(.figureMenuNotUnderstood)
        } else {
            record(ConversationMenuMessage.pick(in: body, daemonPort: daemonPort()))
        }
    }

    // MARK: The page's side

    /// The script: `template` below with the four items' actions and words
    /// put in, so the page shows exactly the words the Mac's menu does.
    nonisolated static let script: String = {
        let entries = ConversationAction.allCases.map { ["action": $0.rawValue, "title": $0.title] }
        let data = (try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        return template.replacingOccurrences(of: "__ENTRIES__", with: String(decoding: data, as: UTF8.self))
    }()

    /// A capturing `contextmenu` listener for real clicks on the daemon's own
    /// page. It posts `{kind, url, name}` for the picture or link under the
    /// right-click (its address as the browser resolved it, a picture's alt
    /// text or a link's text), and `{kind: null}` for anything else, so an
    /// older pick is never taken for this click. A picture can be under a
    /// transparent layer (the page's annotation layer sits over every figure
    /// it draws), so when the click isn't on one the picture beside the thing
    /// clicked, under the pointer, is the figure; and a card in the Generated
    /// tray stands for its thumbnail.
    ///
    /// When the address names a version it also watches, for two seconds, for
    /// the page's own menu (`role="menu"` named "Artifact actions"): a
    /// MutationObserver that ends the moment it has placed the items, or at
    /// the end of the two seconds, and that then only looks after the menu
    /// until it closes. The items are a rule and four buttons, at the menu's end
    /// or, when it has a red item, just above that item's own rule, made from the
    /// menu's own first item (its classes, its icon box; never its words), with
    /// an icon of Capsid's own drawing in the box. A real click on one posts
    /// `{action, version, name, kind}` and closes the menu with Escape on the
    /// document, which is what the page listens for, else a pointer-down
    /// outside the menu. If the menu opens and has nothing to copy it posts
    /// `{unplaced: true}`.
    private nonisolated static let template = #"""
    (() => {
      "use strict";
      if (location.protocol !== "http:" || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capsidShelfMenu;
      if (!handler) return;

      // The four items, in order: what is posted for each, and its words.
      const ENTRIES = __ENTRIES__;
      // How long the page has to open its own menu after a right-click on a figure.
      const WAIT_MS = 2000;
      // The longest the items are looked after once they are in a menu.
      const HOLD_MS = 120000;
      // How long the page has to close its menu on Escape before the click outside.
      const CLOSE_MS = 80;
      // The page's own rule between groups, if the menu has none to copy.
      const RULE_CLASS = "my-1 h-px bg-border-300 mx-1";
      const SVG = "http://www.w3.org/2000/svg";
      // Capsid's own 16-point line icons, one stroke each.
      const ICONS = {
        addToShelf: "M4 2.75h8a.5.5 0 0 1 .5.5v10.2L8 10.55l-4.5 2.9V3.25a.5.5 0 0 1 .5-.5z",
        keep: "M2.75 3.25h10.5v2.5H2.75zM3.75 5.75v6.5a1 1 0 0 0 1 1h6.5a1 1 0 0 0 1-1v-6.5M6.5 8.5h3",
        openAsReference: "M8 4.5C7 3.5 5.4 3.1 2.75 3.25v8.5C5.4 11.6 7 12 8 13c1-1 2.6-1.4 5.25-1.25v-8.5C10.6 3.1 9 3.5 8 4.5zM8 4.5V13",
        showInResults: "M2.75 3.5h10.5v9H2.75zM2.75 6.75h10.5M6.5 6.75v5.75"
      };
      const VERSION = /^[0-9a-f-]{36}$/;
      const TAILS = ["download", "raw", "content", "file", "thumbnail"];
      const QUERY_NAMES = ["v", "version", "version_id", "versionId"];

      // The version an address on this page names: the same rule as Swift's
      // ShelfAddress.version, which has the last word.
      function versionOf(address) {
        const text = String(address || "");
        if (text.length === 0 || text.length > 4096) return null;
        let url;
        try { url = new URL(text); } catch (error) { return null; }
        if (url.origin !== location.origin) return null;
        if (url.pathname.indexOf("/api/artifacts/versions/") === 0) {
          const parts = url.pathname.split("/");
          if (!VERSION.test(parts[4])) return null;
          if (parts.length === 5) return parts[4];
          return parts.length === 6 && TAILS.indexOf(parts[5]) >= 0 ? parts[4] : null;
        }
        for (const pair of url.searchParams) {
          if (QUERY_NAMES.indexOf(pair[0]) >= 0 && VERSION.test(pair[1])) return pair[1];
        }
        return null;
      }

      function isImage(node) {
        return !!node && String(node.tagName).toLowerCase() === "img";
      }

      // The picture under a transparent layer: one of the pictures under the
      // pointer that sits beside the thing clicked, or beside what it is in
      // (a marker in the layer). Never as far out as the body, or a pop-up over
      // the conversation would take a figure beneath it.
      function pictureBeside(element, event) {
        if (typeof document.elementsFromPoint !== "function") return null;
        const stack = document.elementsFromPoint(event.clientX || 0, event.clientY || 0) || [];
        let node = element;
        for (let depth = 0; node && depth < 2; depth++, node = node.parentElement) {
          const parent = node.parentElement;
          if (!parent || parent === document.body || parent === document.documentElement) return null;
          for (let index = 0; index < stack.length; index++) {
            if (isImage(stack[index]) && parent.contains(stack[index])) return stack[index];
          }
        }
        return null;
      }

      // The figure or the link a right-click was on.
      function figureAt(event) {
        const node = event.target;
        const element = node && node.nodeType === 1 ? node : (node && node.parentElement) || null;
        if (!element || !element.closest) return null;
        const found = element.closest("img, a[href]");
        if (found) return found;
        const card = element.closest('[data-testid="turn-tray-card"]');
        if (card) return card.querySelector("img");
        return pictureBeside(element, event);
      }

      let watch = null;

      function stopWatch() {
        const view = watch;
        watch = null;
        if (!view) return;
        if (view.observer) view.observer.disconnect();
        if (view.timer) clearTimeout(view.timer);
        if (view.hold) clearTimeout(view.hold);
      }

      function startWatch(figure) {
        if (typeof MutationObserver !== "function") return;
        const view = { figure: figure, menu: null, nodes: [], observer: null, timer: null, hold: null };
        view.observer = new MutationObserver((records) => changed(view, records));
        view.observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
        view.timer = setTimeout(() => { if (watch === view && !view.menu) stopWatch(); }, WAIT_MS);
        watch = view;
      }

      // The page's menu among the nodes just added, if it is there.
      function menuIn(records) {
        for (const record of records) {
          for (const added of record.addedNodes) {
            if (!added || added.nodeType !== 1) continue;
            const menu = (added.closest && added.closest('[role="menu"][aria-label="Artifact actions"]'))
              || (added.querySelector && added.querySelector('[role="menu"][aria-label="Artifact actions"]'));
            if (menu) return menu;
          }
        }
        return null;
      }

      function changed(view, records) {
        if (watch !== view) return;
        if (!view.menu) {
          const menu = menuIn(records);
          if (menu) place(view, menu);
          return;
        }
        if (view.menu.isConnected) { restore(view); return; }
        // The menu closed, or the page drew it again as a new one.
        view.menu = null;
        view.nodes = [];
        const next = menuIn(records);
        if (next) place(view, next); else stopWatch();
      }

      function icon(doc, action) {
        const svg = doc.createElementNS(SVG, "svg");
        svg.setAttribute("viewBox", "0 0 16 16");
        svg.setAttribute("width", "1em");
        svg.setAttribute("height", "1em");
        svg.setAttribute("fill", "none");
        svg.setAttribute("stroke", "currentColor");
        svg.setAttribute("stroke-width", "1.25");
        svg.setAttribute("stroke-linecap", "round");
        svg.setAttribute("stroke-linejoin", "round");
        svg.setAttribute("aria-hidden", "true");
        const path = doc.createElementNS(SVG, "path");
        path.setAttribute("d", ICONS[action]);
        svg.appendChild(path);
        return svg;
      }

      function place(view, menu) {
        const doc = menu.ownerDocument || document;
        // The first item that isn't the red one, for its classes and its icon box.
        let template = null;
        const items = menu.querySelectorAll('[role="menuitem"]');
        for (let index = 0; index < items.length && !template; index++) {
          if (String(items[index].className).indexOf("danger") < 0) template = items[index];
        }
        if (!template) {
          handler.postMessage({ unplaced: true });
          stopWatch();
          return;
        }
        const box = template.querySelector('[data-cds="Icon"]');
        let ruleClass = RULE_CLASS;
        const children = Array.prototype.slice.call(menu.children);
        for (let index = 0; index < children.length; index++) {
          if (String(children[index].tagName).toLowerCase() === "div" && !children[index].firstChild && children[index].className) {
            ruleClass = children[index].className;
            break;
          }
        }
        const nodes = [];
        const rule = doc.createElement("div");
        rule.className = ruleClass;
        nodes.push(rule);
        ENTRIES.forEach((entry) => {
          const button = doc.createElement("button");
          button.setAttribute("type", "button");
          button.setAttribute("role", "menuitem");
          button.className = template.className;
          if (box) {
            const holder = box.cloneNode(false);
            holder.appendChild(icon(doc, entry.action));
            button.appendChild(holder);
          }
          button.appendChild(doc.createTextNode(entry.title));
          button.addEventListener("click", (event) => choose(view, entry, event));
          nodes.push(button);
        });
        view.menu = menu;
        view.nodes = nodes;
        if (view.timer) { clearTimeout(view.timer); view.timer = null; }
        view.hold = setTimeout(() => { if (watch === view) stopWatch(); }, HOLD_MS);
        nodes.forEach((node) => menu.insertBefore(node, anchorIn(menu, nodes)));
        fit(menu);
        // From here the page's whole body is not watched: only the menu, what
        // it sits in and what that sits in, one level each (the menu's items
        // dropped, the menu drawn again or taken away).
        view.observer.disconnect();
        view.observer.observe(menu, { childList: true });
        const holder = menu.parentNode;
        if (holder) {
          view.observer.observe(holder, { childList: true });
          if (holder.parentNode) view.observer.observe(holder.parentNode, { childList: true });
        }
      }

      // What the group goes in front of: the page's rule right above its red
      // item, else the red item itself, else nothing (the end). The group's own
      // nodes don't count; "red" is the page's own word for it, `danger`, in
      // its classes.
      function anchorIn(menu, nodes) {
        const kids = Array.prototype.slice.call(menu.children).filter((kid) => nodes.indexOf(kid) < 0);
        for (let index = 0; index < kids.length; index++) {
          if (String(kids[index].tagName).toLowerCase() !== "button" || String(kids[index].className).indexOf("danger") < 0) continue;
          const above = index > 0 ? kids[index - 1] : null;
          const isRule = !!above && String(above.tagName).toLowerCase() === "div" && !above.firstChild;
          return isRule ? above : kids[index];
        }
        return null;
      }

      // Whether the rule and the four items sit one after another, in order, in
      // front of what they belong in front of (or last, with no red item).
      function inPlace(view) {
        const kids = Array.prototype.slice.call(view.menu.children);
        const first = kids.indexOf(view.nodes[0]);
        if (first < 0) return false;
        for (let index = 0; index < view.nodes.length; index++) {
          if (kids[first + index] !== view.nodes[index]) return false;
        }
        return (kids[first + view.nodes.length] || null) === anchorIn(view.menu, view.nodes);
      }

      // React drew the menu again and left the items out, or put an item of its
      // own among or after them: put the group back where it belongs.
      function restore(view) {
        const menu = view.menu;
        if (inPlace(view)) return;
        view.nodes.forEach((node) => menu.insertBefore(node, anchorIn(menu, view.nodes)));
        fit(menu);
        view.observer.takeRecords();
      }

      // The page placed its menu to fit without the new items: keep it on screen.
      function fit(menu) {
        const view = (menu.ownerDocument && menu.ownerDocument.defaultView) || window;
        const margin = 8;
        const box = menu.getBoundingClientRect();
        const below = box.bottom - (view.innerHeight - margin);
        if (below > 0) menu.style.top = Math.max(margin, box.top - below) + "px";
        const beyond = box.right - (view.innerWidth - margin);
        if (beyond > 0) menu.style.left = Math.max(margin, box.left - beyond) + "px";
      }

      function choose(view, entry, event) {
        if (!event.isTrusted) return;
        event.preventDefault();
        event.stopPropagation();
        handler.postMessage({ action: entry.action, version: view.figure.version, name: view.figure.name, kind: view.figure.kind });
        const menu = view.menu;
        stopWatch();
        dismiss(menu);
      }

      // Closes the page's menu the way the page's own hook does: Escape on the
      // document; if it is still there a moment later, a pointer-down outside it.
      function dismiss(menu) {
        if (!menu) return;
        const doc = menu.ownerDocument || document;
        doc.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", bubbles: true, cancelable: true }));
        setTimeout(() => {
          if (!menu.isConnected) return;
          (doc.body || doc.documentElement).dispatchEvent(new PointerEvent("pointerdown", {
            bubbles: true, cancelable: true, composed: true, pointerType: "mouse", isPrimary: true
          }));
        }, CLOSE_MS);
      }

      document.addEventListener("contextmenu", (event) => {
        if (!event.isTrusted) return;
        stopWatch();
        const found = figureAt(event);
        if (!found) { handler.postMessage({ kind: null }); return; }
        const image = isImage(found);
        const address = String((image ? (found.currentSrc || found.src) : found.href) || "");
        const hint = image ? (found.alt || found.title) : (found.download || found.textContent || found.title);
        const name = String(hint || "").trim().slice(0, 300);
        const kind = image ? "image" : "link";
        handler.postMessage({ kind: kind, url: address.slice(0, 4096), name: name });
        const version = versionOf(address);
        if (version) startWatch({ kind: kind, version: version, name: name });
      }, true);
    })();
    """#
}

/// What one item does when it is chosen.
@MainActor
private final class ConversationMenuAction: NSObject {
    private let action: ConversationAction
    private let pick: ConversationPick
    private let run: @MainActor (ConversationAction, ConversationPick) -> Void

    init(action: ConversationAction, pick: ConversationPick,
         run: @escaping @MainActor (ConversationAction, ConversationPick) -> Void) {
        self.action = action
        self.pick = pick
        self.run = run
    }

    @objc func fire(_ sender: Any?) {
        run(action, pick)
    }
}

/// What the user content controller holds in place of the menu object.
@MainActor
private final class WeakConversationHandler: NSObject, WKScriptMessageHandler {
    private weak var menu: ConversationMenu?

    init(menu: ConversationMenu) {
        self.menu = menu
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        menu?.receive(message)
    }
}

// MARK: What the items do

/// The Keep sheet for a file picked in the conversation: the main window
/// presents it (Web/BrowserView.swift).
@MainActor
final class ShelfSheetHost: ObservableObject {
    static let shared = ShelfSheetHost()
    @Published var keeping: KeepModel?

    /// Puts a Keep sheet up unless one is up already: a second click on Keep…,
    /// or Keep… on another figure, must not replace a sheet in use (a keep under
    /// way, or a name half typed). The sheet is made only when it is put up.
    @discardableResult
    func present(_ make: () -> KeepModel) -> Bool {
        guard keeping == nil else { return false }
        keeping = make()
        return true
    }
}

/// The four actions, over the session the main window is showing. Every
/// reach into the app or the page is a dependency, so the tests run it all on
/// made-up sessions and a made-up shelf; nothing here writes to Claude Science.
@MainActor
final class ConversationShelf {
    static let shared = ConversationShelf(dependencies: .live())

    /// Said when the page isn't on a session's address.
    static let noSession = "Capsid couldn\u{2019}t tell which conversation that is in."

    struct Dependencies {
        /// The session the main window shows, from its address.
        var route: @MainActor () -> NidusTaskSelection.Route?
        /// The session for a route: Capsid's own list, else the database,
        /// else built from the ids.
        var session: @MainActor (NidusTaskSelection.Route) async -> SessionStatus
        /// The file's own facts (its name, type, size and artifact), read
        /// through the Results shelf's queue; nil when they couldn't be.
        var facts: @MainActor (String) async -> ArtifactFacts?
        var shelf: ShelfAccess
        var toast: ShelfToastModel
        var keep: @MainActor (KeepSubject) -> Void
        /// The reference reader on a session, at the reply that shows `mark`.
        var reference: @MainActor (SessionStatus, String) -> Void
        var results: @MainActor (SessionStatus) -> Void

        @MainActor
        static func live() -> Dependencies {
            Dependencies(
                route: { NidusTaskSelection.route(url: WebContainer.shared.webView.url, daemonPort: WebContainer.shared.port) },
                session: { route in await ConversationShelf.liveSession(route) },
                facts: { version in
                    guard Demo.mode == nil,
                          case .answered(.facts(let facts)) = await ResultsShelf.shared.transfers.read(
                            .facts(version: version), priority: .foreground, keepsOnClose: true),
                          facts.v == version else { return nil }
                    return facts
                },
                shelf: .live,
                toast: .shared,
                keep: { subject in
                    ShelfSheetHost.shared.present { KeepModel(subject: subject, dependencies: .live(shelf: .shared)) }
                },
                reference: { session, version in
                    ReferenceWindowController.shared.show(session, at: nil, mark: version)
                },
                results: { ResultsWindowController.shared.show(focusing: $0) })
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// The session behind a route, from what Capsid knows of it.
    static func liveSession(_ route: NidusTaskSelection.Route) async -> SessionStatus {
        if let known = LabModel.shared.sessions.first(where: { $0.id == route.frameID && $0.projectID == route.projectID }) {
            return known
        }
        if let found = await RemoteBrowser.lookUp(route.frameID), found.projectID == route.projectID { return found }
        return built(route, port: WebContainer.shared.port)
    }

    /// A session made from its ids alone, when nothing knows its name.
    static func built(_ route: NidusTaskSelection.Route, port: Int?) -> SessionStatus {
        SessionStatus(id: route.frameID, projectID: route.projectID, projectName: "Claude Science", title: "",
                      state: .finished, updatedAt: Date(),
                      deepLink: URL(string: "http://localhost:\(port ?? 8765)/projects/\(route.projectID)/frames/\(route.frameID)"))
    }

    func run(_ action: ConversationAction, on pick: ConversationPick) async {
        let toast = dependencies.toast
        guard let route = dependencies.route() else {
            toast.show(.failed(Self.noSession))
            return
        }
        if action == .addToShelf { toast.show(.adding) }
        let session = await dependencies.session(route)
        let entry = ShelfAddress.entry(version: pick.version, name: pick.name, isImage: pick.kind == .image)
        switch action {
        case .addToShelf:
            switch await dependencies.shelf.add(ShelfSource(session: session, entry: entry)) {
            case .added(let placement): toast.show(.added(placement))
            case .alreadyOnShelf(let placement): toast.show(.already(placement))
            case .failed(let sentence): toast.show(.failed(sentence))
            }
        case .keep:
            // The sheet proposes the file's own name for the folder, and takes it
            // from the entry it is given: the picture's alt text is not that.
            let facts = await dependencies.facts(pick.version)
            let known = facts.map {
                ArtifactEntry(version: pick.version, artifact: $0.a, name: $0.name ?? entry.name, mime: $0.mime,
                              size: $0.size ?? 0, at: $0.at)
            }
            // The version is the user's pick: it stays the selection, whichever
            // newer answer shows another, and whether or not its answer is found.
            dependencies.keep(KeepSubject(session: session, entry: known ?? entry, selectsItsVersion: true))
        case .openAsReference:
            dependencies.reference(session, pick.version)
        case .showInResults:
            dependencies.results(session)
        }
    }
}
