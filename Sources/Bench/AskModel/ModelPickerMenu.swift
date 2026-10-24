// ModelPickerMenu.swift — "Ask Another Model…" at the end of Claude Science's
// own model menu, the one the picker beside the message box opens (DESIGN.md,
// Ask another model → Where it appears). Choosing it opens the Ask window for
// the session in the main window, starting from what is typed in the message
// box, if anything is, else from the session's last question.
//
// It is drawn into the page's menu, as Shelf/ConversationMenu.swift draws its
// items into the page's figure menu, because the page draws this menu itself.
// A small user script, in a content world of its own, waits for a press on the
// model picker (a real pointer-down, or Enter, Space or an arrow on it), asks
// Swift whether the item may be offered (the feature on with a key, a session
// in the main window), and, for two seconds, watches for the picker's menu to
// open. When it does, the script adds a rule and one item at the end of the
// menu, drawn with the menu's own classes (copied from one of its own items,
// never its words). Nothing is watched unless the picker was just pressed, and
// once the item is in, only that menu is, until it closes.
//
// If the menu doesn't look as Capsid expects (a menu opens after the picker is
// pressed but is not the picker's, or the picker's has nowhere to put the item)
// the item is simply not there, and a breadcrumb is left for Diagnostics
// (`CompatMiss.modelMenuNotUnderstood`). The toolbar button and File's item stay
// the way in. Only the main web view's main frame on the daemon's origin is
// heard. The draft is read when the item is chosen and goes to nothing but the
// Ask window's question field; nothing read from the page is logged, and the
// trace (in the feature's own log, `another-model`) is the script's fixed words.
import AppKit
import Foundation
import WebKit

// MARK: What the script says

/// One step of a press on the picker as the page script saw it, in the
/// script's fixed words, so one press says in Capsid's log where the item
/// stopped: the picker pressed; Swift said yes; the picker's menu found;
/// the item placed, or the menu had nowhere for it; another menu came instead,
/// or none; or the picker was pressed again first.
enum ModelMenuStep: String, CaseIterable, Sendable {
    case armed, allowed, refused
    case noObserver = "no-observer"
    case menuMatched = "menu-matched", menuOther = "menu-other", menuNone = "menu-none"
    case placed, unplaced, interrupted
}

enum ModelMenuMessage {
    /// The most steps a trace is read for; one press makes five at most.
    static let maxSteps = 8

    /// The picker was pressed and the page asks whether the item may be
    /// offered: `{armed: true}`.
    static func isArmed(_ body: Any?) -> Bool {
        guard let body = body as? [String: Any] else { return false }
        return body["armed"] as? Bool == true
    }

    /// What is typed in the message box, as a seed for the Ask window:
    /// trimmed, cut at the question's limit, and nil when empty.
    static func seed(_ draft: Any?) -> String? {
        guard let text = draft as? String else { return nil }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AskRules.maxQuestion))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The item was chosen: `{ask: true, draft: <string>}`.
    struct Choice: Equatable, Sendable {
        /// What was typed in the message box, as a seed; nil when nothing was.
        let seed: String?
    }

    static func choice(in body: Any?) -> Choice? {
        guard let body = body as? [String: Any], body["ask"] as? Bool == true else { return nil }
        return Choice(seed: seed(body["draft"]))
    }

    /// The menu opened and the item had nowhere to go: `{unplaced: true}`.
    static func isUnplaced(_ body: Any?) -> Bool {
        guard let body = body as? [String: Any] else { return false }
        return body["unplaced"] as? Bool == true
    }

    /// The steps a trace names, `{trace: [word, …]}`, as the script's own
    /// fixed words. Any other word is dropped, so nothing the page could put
    /// there is logged. Nil when the message isn't a trace.
    static func trace(in body: Any?) -> [ModelMenuStep]? {
        guard let body = body as? [String: Any], let words = body["trace"] as? [Any] else { return nil }
        return words.prefix(maxSteps).compactMap { ($0 as? String).flatMap(ModelMenuStep.init(rawValue:)) }
    }

    /// The log line for a trace: "Model menu: armed → allowed → …".
    static func line(_ steps: [ModelMenuStep]) -> String {
        "Model menu: " + (steps.isEmpty ? "no steps" : steps.map(\.rawValue).joined(separator: " → "))
    }
}

// MARK: The menu

@MainActor
final class ModelPickerMenu {
    nonisolated static let handlerName = "capsidAskMenu"
    /// Its own world: the page can't see the script, or reach its handler.
    static let world = WKContentWorld.world(name: "capsid-ask")

    /// The web view the messages must come from.
    weak var webView: WKWebView?

    private let daemonPort: @MainActor () -> Int?
    private let mayOffer: @MainActor () -> Bool
    private let run: @MainActor (String?) -> Void
    private let breadcrumbs: CompatBreadcrumbs
    private let traced: @MainActor (String) -> Void

    /// `mayOffer` says whether the item is wanted now (the feature on with a
    /// key, a session in the main window), and is asked again when the item is
    /// chosen; `run` is what the item does, with the message box's draft;
    /// `breadcrumbs` is where "the model menu didn't look as Capsid expects"
    /// goes, and `traced` where a press's steps go (the log).
    init(daemonPort: @escaping @MainActor () -> Int?,
         mayOffer: @escaping @MainActor () -> Bool,
         breadcrumbs: CompatBreadcrumbs = .shared,
         traced: @escaping @MainActor (String) -> Void = AnotherModel.writeLog,
         run: @escaping @MainActor (String?) -> Void) {
        self.daemonPort = daemonPort
        self.mayOffer = mayOffer
        self.breadcrumbs = breadcrumbs
        self.traced = traced
        self.run = run
    }

    /// The item is wanted while the feature is on with a key and a session
    /// is in the main window, outside a demo: File's rule.
    static func isWanted() -> Bool {
        AskMenu.fileItem(available: AnotherModel.shared.isAvailable, session: WebContainer.shared.currentFrameID,
                         demo: Demo.mode != nil).enabled
    }

    /// Adds the user script and its message handler. The controller keeps a
    /// strong reference to the handler, so it gets a proxy that only holds
    /// this object weakly. The handler answers every message (the page asks
    /// "may I?" and waits). `script` is the app's own; a test that has to make
    /// its clicks with script lifts a check from a copy.
    func install(on controller: WKUserContentController, script: String = ModelPickerMenu.script) {
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.world))
        controller.addScriptMessageHandler(WeakModelMenuHandler(menu: self), contentWorld: Self.world, name: Self.handlerName)
    }

    fileprivate func receive(_ message: WKScriptMessage) -> [String: Bool] {
        let origin = message.frameInfo.securityOrigin
        let accepted = TabMenuMessage.isAccepted(
            isMainFrame: message.frameInfo.isMainFrame,
            fromMainWebView: message.webView != nil && message.webView === webView,
            isDaemonOrigin: WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port,
                                                    daemonPort: daemonPort()))
        return hear(message.body, accepted: accepted)
    }

    /// What a message from the page means, once its sender is known to be the
    /// main window's own page (`accepted`), and what the page is told back
    /// (`{show: true}` when the item may be offered). Four shapes:
    /// - `{armed: true}`: the picker was pressed; the answer is whether the
    ///   item is wanted now;
    /// - `{ask: true, draft}`: the item was chosen; the Ask window opens, if
    ///   the item is still wanted;
    /// - `{unplaced: true}`: the picker's menu opened and the item had nowhere
    ///   to go, a change in Claude Science worth a breadcrumb;
    /// - `{trace: [...]}`: a press's steps, logged.
    /// From anyone else a message is nothing, and the answer is no.
    @discardableResult
    func hear(_ body: Any?, accepted: Bool) -> [String: Bool] {
        guard accepted else { return ["show": false] }
        if ModelMenuMessage.isArmed(body) {
            return ["show": mayOffer()]
        } else if let choice = ModelMenuMessage.choice(in: body) {
            if mayOffer() { run(choice.seed) }
        } else if ModelMenuMessage.isUnplaced(body) {
            breadcrumbs.record(.modelMenuNotUnderstood)
        } else if let steps = ModelMenuMessage.trace(in: body) {
            traced(ModelMenuMessage.line(steps))
        }
        return ["show": false]
    }

    // MARK: The page's side

    /// The script: `template` below with the item's words put in, so the page
    /// shows exactly the words File's item does.
    nonisolated static let script: String = {
        let data = (try? JSONSerialization.data(withJSONObject: [AskMenu.title], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return template.replacingOccurrences(of: "__TITLE__", with: String(decoding: data, as: UTF8.self))
    }()

    /// A capturing listener for real presses on the model picker
    /// (`data-testid="model-selector"`: the button, or the wrapper round it).
    /// A press posts `{armed: true}` and gets back whether the item may be
    /// offered; meanwhile, for two seconds, a MutationObserver looks for the
    /// picker's menu (`role="menu"` with `data-cds="ModelSelector"`, or the
    /// plain picker's `data-testid="model-selector-popup"`) among the nodes
    /// added. When it has the menu and the answer, it adds a rule and one item
    /// at the end of the menu's list (the element with `data-cds-sheet-scroll`
    /// that holds its items), made from the menu's own first item (its tag and
    /// classes, less the extra padding of an item with a second line; never its
    /// words) and its own rule. From then on only that menu is watched, for as
    /// long as it is open (or two minutes), to put the group back last if the
    /// page draws the list again. The item lights on the pointer as the page's
    /// own do (`data-highlighted`); the page's arrow keys do not reach it. A
    /// real click on it posts `{ask: true, draft}`, the draft being the text
    /// typed in the message box of the composer the picker sits in, and closes
    /// the menu with Escape (and a pointer-down outside, if it is still there
    /// 80 ms later). If a menu opens that is not the picker's, or the picker's
    /// has no item and no list to copy, it posts `{unplaced: true}`. Once a
    /// press is done with it posts its steps, `{trace}`, in the fixed words of
    /// `ModelMenuStep`; when the answer is no, it posts nothing more.
    private nonisolated static let template = #"""
    (() => {
      "use strict";
      if (location.protocol !== "http:" || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capsidAskMenu;
      if (!handler) return;

      // The item's words, as File's item has them.
      const TITLE = __TITLE__[0];
      // How long the page has to open its menu after the picker is pressed.
      const WAIT_MS = 2000;
      // The longest the item is looked after once it is in a menu.
      const HOLD_MS = 120000;
      // How long the page has to close its menu on Escape before the click outside.
      const CLOSE_MS = 80;
      // The most of a draft that is read.
      const MAX_DRAFT = 32000;
      // The keys that open the picker.
      const KEYS = ["Enter", " ", "ArrowDown", "ArrowUp"];
      // The page's own rule between groups, if the menu has none to copy.
      const RULE_CLASS = "compact:mx-2 comfortable:mx-2.5 my-1 h-px bg-border";
      // The padding the page adds under an item that has a second line; ours has one.
      const SECOND_LINE = "pb-[calc(";

      function post(message) {
        try { return handler.postMessage(message); } catch (error) { return null; }
      }

      // The steps of one press, in fixed words only (never anything read from
      // the page), posted once as `{trace}` when it ends.
      let trail = null;

      function step(word) {
        if (trail) trail.push(word);
      }

      function report(word) {
        if (!trail) return;
        trail.push(word);
        post({ trace: trail });
        trail = null;
      }

      let watch = null;
      // The click that follows a press which closed the open menu is the same press.
      let swallowClick = false;

      function stopWatch() {
        const view = watch;
        watch = null;
        if (!view) return;
        if (view.observer) view.observer.disconnect();
        if (view.timer) clearTimeout(view.timer);
        if (view.hold) clearTimeout(view.hold);
      }

      function elementOf(node) {
        return node && node.nodeType === 1 ? node : (node && node.parentElement) || null;
      }

      // The picker's menu among the nodes just added, if it is there.
      function menuIn(records) {
        for (const record of records) {
          for (const added of record.addedNodes) {
            if (!added || added.nodeType !== 1) continue;
            const menu = (added.closest && added.closest('[role="menu"][data-cds="ModelSelector"], [role="menu"][data-testid="model-selector-popup"]'))
              || (added.querySelector && added.querySelector('[role="menu"][data-cds="ModelSelector"], [role="menu"][data-testid="model-selector-popup"]'));
            if (menu) return menu;
          }
        }
        return null;
      }

      // Whether any menu at all, the picker's or not, is among the nodes just added.
      function anyMenuIn(records) {
        for (const record of records) {
          for (const added of record.addedNodes) {
            if (!added || added.nodeType !== 1) continue;
            if ((added.closest && added.closest('[role="menu"]')) || (added.querySelector && added.querySelector('[role="menu"]'))) return true;
          }
        }
        return false;
      }

      // A press on the picker: a real pointer-down, Enter, Space or an arrow, or a click with nothing watched.
      function pressed(event) {
        if (!event.isTrusted) return;
        if (event.type === "pointerdown" && event.button > 0) return;
        if (event.type === "keydown" && KEYS.indexOf(event.key) < 0) return;
        const element = elementOf(event.target);
        const picker = element && element.closest ? element.closest('[data-testid="model-selector"]') : null;
        if (!picker) {
          // A press somewhere else, before the picker's menu came, means it is not coming for that press.
          if (event.type === "pointerdown" && watch && !watch.menu) { report("interrupted"); stopWatch(); }
          return;
        }
        // The click after a pointer-down, or after Enter, is the same press.
        if (event.type === "click") {
          const same = watch !== null || swallowClick;
          swallowClick = false;
          if (same) return;
          arm(picker);
          return;
        }
        swallowClick = false;
        // The picker pressed again while its menu is open closes it: nothing more to watch, and not its click.
        if (watch && watch.menu && watch.menu.isConnected) { stopWatch(); swallowClick = true; return; }
        arm(picker);
      }

      function arm(picker) {
        // A press before the last one's menu came ends that one's trace.
        report("interrupted");
        stopWatch();
        trail = ["armed"];
        if (typeof MutationObserver !== "function") { report("no-observer"); return; }
        const view = {
          composer: picker.closest('[data-testid="composer"]'),
          menu: null, found: null, allowed: null, other: false,
          rule: null, item: null, container: null, observer: null, timer: null, hold: null
        };
        view.observer = new MutationObserver((records) => changed(view, records));
        view.observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
        view.timer = setTimeout(() => timedOut(view), WAIT_MS);
        watch = view;
        Promise.resolve(post({ armed: true })).then(
          (reply) => decided(view, !!reply && reply.show === true),
          () => decided(view, false));
      }

      function timedOut(view) {
        view.timer = null;
        if (watch !== view || view.menu) return;
        // A menu that opened and closed again before it could be given the item is not a miss.
        if (view.found && !view.found.isConnected) view.found = null;
        if (view.found && view.allowed === true) {
          post({ unplaced: true });
          report("unplaced");
        } else if (view.found) {
          report("refused");
        } else if (view.other) {
          post({ unplaced: true });
          report("menu-other");
        } else {
          report("menu-none");
        }
        stopWatch();
      }

      // Swift's answer: no, and nothing more is watched or said; yes, and the menu, once it is here, gets the item.
      function decided(view, yes) {
        if (watch !== view) return;
        if (!yes) {
          trail = null;
          stopWatch();
          return;
        }
        step("allowed");
        view.allowed = true;
        tryPlace(view);
      }

      function changed(view, records) {
        if (watch !== view) return;
        if (view.menu) {
          if (!view.menu.isConnected) { stopWatch(); return; }
          restore(view);
          return;
        }
        if (!view.found) {
          const menu = menuIn(records);
          if (menu) {
            step("menu-matched");
            view.found = menu;
          } else {
            if (!view.other && anyMenuIn(records)) view.other = true;
            return;
          }
        }
        tryPlace(view);
      }

      // The menu's own first item, for its tag and classes.
      function templateIn(menu) {
        return menu.querySelector('[role="menuitemradio"], [role="menuitem"]');
      }

      function plainClasses(name) {
        return String(name || "").split(/\s+/).filter((token) => token !== "" && token.indexOf(SECOND_LINE) !== 0).join(" ");
      }

      // Puts the rule and the item at the end of the menu's list, once the answer is yes and the list is drawn.
      function tryPlace(view) {
        const menu = view.found;
        if (view.allowed !== true || !menu || !menu.isConnected) return;
        const template = templateIn(menu);
        const container = menu.querySelector('[data-cds-sheet-scroll]');
        if (!template || !container || !container.contains(template)) return;
        const doc = menu.ownerDocument || document;
        const separator = menu.querySelector('[role="separator"]');
        const rule = doc.createElement("div");
        rule.setAttribute("role", "separator");
        rule.className = separator && separator.className ? separator.className : RULE_CLASS;
        const item = doc.createElement(String(template.tagName).toLowerCase());
        item.setAttribute("role", "menuitem");
        item.setAttribute("tabindex", "-1");
        item.className = plainClasses(template.className);
        item.appendChild(doc.createTextNode(TITLE));
        item.addEventListener("click", (event) => choose(view, event));
        // The page lights its own items with `data-highlighted`, which its list sets on the ones it knows.
        item.addEventListener("pointerenter", () => item.setAttribute("data-highlighted", ""));
        item.addEventListener("pointerleave", () => item.removeAttribute("data-highlighted"));
        view.rule = rule;
        view.item = item;
        view.container = container;
        view.menu = menu;
        if (view.timer) { clearTimeout(view.timer); view.timer = null; }
        view.hold = setTimeout(() => { if (watch === view) stopWatch(); }, HOLD_MS);
        container.appendChild(rule);
        container.appendChild(item);
        report("placed");
        // From here the page's whole body is not watched: only the menu.
        view.observer.disconnect();
        view.observer.observe(menu, { childList: true, subtree: true });
      }

      // Whether the rule and the item are the last two things in the list.
      function inPlace(view) {
        const container = view.container;
        if (!container || !container.isConnected || !view.menu.contains(container)) return false;
        const kids = Array.prototype.slice.call(container.children);
        return kids[kids.length - 1] === view.item && kids[kids.length - 2] === view.rule;
      }

      // React drew the list again and left the group out, or put an item of its own after it: put the group back, last.
      function restore(view) {
        if (inPlace(view)) return;
        const container = view.menu.querySelector('[data-cds-sheet-scroll]');
        if (!container) return;
        view.container = container;
        container.appendChild(view.rule);
        container.appendChild(view.item);
        view.observer.takeRecords();
      }

      // What is typed in the message box: its text, a line break for each <br> and each block after the first, without the
      // dictation ghost or an upload's chip. The page's own reader does the same walk (and turns mentions into references).
      function plain(node) {
        let out = "";
        const children = Array.prototype.slice.call(node.childNodes);
        for (const child of children) {
          if (child.nodeType === 3) { out += child.textContent; continue; }
          if (child.nodeType !== 1) continue;
          if (child.hasAttribute("data-voice-ghost") || child.hasAttribute("data-upload-status")) continue;
          const tag = String(child.tagName).toUpperCase();
          if (tag === "BR") { out += "\n"; continue; }
          if ((tag === "DIV" || tag === "P") && out !== "" && out.charAt(out.length - 1) !== "\n") out += "\n";
          out += plain(child);
        }
        return out;
      }

      function draftOf(composer) {
        if (!composer || !composer.isConnected) return "";
        const box = composer.querySelector('[role="textbox"]');
        if (!box) return "";
        return plain(box).trim().slice(0, MAX_DRAFT);
      }

      function choose(view, event) {
        if (!event.isTrusted) return;
        event.preventDefault();
        event.stopPropagation();
        post({ ask: true, draft: draftOf(view.composer) });
        const menu = view.menu;
        if (watch === view) stopWatch();
        dismiss(menu);
      }

      // Closes the page's menu as a key press would: Escape from inside it, which its own list hears and so does the
      // document; if it is still there a moment later, a pointer-down outside it.
      function dismiss(menu) {
        if (!menu) return;
        const doc = menu.ownerDocument || document;
        menu.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", bubbles: true, cancelable: true }));
        setTimeout(() => {
          if (!menu.isConnected) return;
          (doc.body || doc.documentElement).dispatchEvent(new PointerEvent("pointerdown", {
            bubbles: true, cancelable: true, composed: true, pointerType: "mouse", isPrimary: true
          }));
        }, CLOSE_MS);
      }

      document.addEventListener("pointerdown", pressed, true);
      document.addEventListener("keydown", pressed, true);
      document.addEventListener("click", pressed, true);
    })();
    """#
}

/// What the user content controller holds in place of the menu object. It
/// answers every message, as the page waits on the answer to its first.
@MainActor
private final class WeakModelMenuHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var menu: ModelPickerMenu?

    init(menu: ModelPickerMenu) {
        self.menu = menu
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        replyHandler(menu?.receive(message) ?? ["show": false], nil)
    }
}
