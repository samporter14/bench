// PageTabs.swift — Close Other Tabs and Close All Tabs for the artifact tabs
// in Claude Science's right-hand panel (DESIGN.md, Main window). The page has
// no such commands, so Capsid presses the tabs' own close buttons, one at a
// time, from inside the page. The page's own `closeTab` runs, so whatever it
// asks before discarding unsaved edits is still asked; nothing here closes a
// tab around it.
//
// The page script is plain JavaScript, in two parts: `benchTabsToClose`, the
// pure decision (which ids, keeping which), and the body that reads the strip
// and presses the buttons. The tests run these very strings in JavaScriptCore
// against a fake DOM. Nothing read from the page is logged or kept: not a tab's
// name, not its id.
//
// The markup it relies on is Claude Science 0.1.63's:
//   [data-testid="right-tab-strip"]                      the one strip
//     [role="toolbar"][aria-label="Open panels"]         where the tabs sit
//       [data-tab-id="<id>"]                             a tab
//         [data-tab-btn]                                 shows it; aria-current="true" when shown
//         button[data-tab-close]                         closes it
// If any of this is missing the script presses nothing and says so.
import AppKit
import Combine
import Foundation
import os
import WebKit

// MARK: What to close

/// Which of the strip's tabs a command closes.
enum PageTabsClose: Equatable, Sendable {
    /// Every tab but one. `nil` keeps the tab the page is showing.
    case others(keeping: String?)
    /// Every tab.
    case all
    /// This tab alone.
    case one(String)

    /// The script's arguments: both names always there, null when unused.
    var arguments: [String: Any] {
        switch self {
        case .others(let keep): ["mode": "others", "keep": keep ?? NSNull()]
        case .all: ["mode": "all", "keep": NSNull()]
        case .one(let id): ["mode": "one", "keep": id]
        }
    }
}

/// What a sweep came to, checked again in Swift.
enum PageTabsOutcome: Equatable, Sendable {
    /// The sweep ran. `closed` tabs are gone; `stayed` are still there, or
    /// were never reached because the sweep stops at the first tab that
    /// stays (see `PageTabsScript.body`). Both 0 when the strip has no tabs.
    case done(closed: Int, stayed: Int)
    /// The strip, its toolbar or a close button wasn't found, so nothing was
    /// pressed. No panel open looks the same as a page that changed its markup.
    case unavailable
    /// The tab to keep (or close) isn't in the strip, or no tab is shown to
    /// keep: nothing was pressed rather than guess.
    case refused

    /// The most tabs a reply may claim. A panel has a handful.
    static let cap = 10_000

    init?(parsing text: String) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let status = object["status"] as? String else { return nil }
        switch status {
        case "unavailable":
            self = .unavailable
        case "refused":
            self = .refused
        case "done":
            guard let closed = Self.count(object["closed"]), let stayed = Self.count(object["stayed"]) else { return nil }
            self = .done(closed: closed, stayed: stayed)
        default:
            return nil
        }
    }

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let count = number.intValue
        return (0...cap).contains(count) && number.doubleValue == Double(count) ? count : nil
    }

    /// What the script answered, as an outcome, noting for Diagnostics what the
    /// answer says of the page (CompatBreadcrumbs). An answer that isn't
    /// understood is nil, and noted. A page with no tab open (no strip) is not
    /// a change; a strip that is wrong, or a tab with no close button, is.
    static func read(_ value: Any?, breadcrumbs: CompatBreadcrumbs = .shared) -> PageTabsOutcome? {
        guard let text = value as? String, let outcome = PageTabsOutcome(parsing: text) else {
            breadcrumbs.record(.tabAnswerNotUnderstood)
            return nil
        }
        if let miss = PageTabsReason(parsing: text)?.miss { breadcrumbs.record(miss) }
        return outcome
    }
}

/// Why a sweep did nothing, when the script says. Most are the page not being
/// as Capsid reads it; only `noStrip` and `tabMissing` are ordinary (no panel
/// with tabs is open; the tab right-clicked closed meanwhile).
enum PageTabsReason: String, Equatable, Sendable {
    case noStrip = "no-strip"
    case severalStrips = "several-strips"
    case noToolbar = "no-toolbar"
    case noCloseButton = "no-close-button"
    case noShownTab = "no-shown-tab"
    case tabMissing = "tab-missing"

    /// The script's `reason`, when it gave one Capsid knows.
    init?(parsing text: String) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let reason = object["reason"] as? String else { return nil }
        self.init(rawValue: reason)
    }

    /// The breadcrumb it earns (CompatBreadcrumbs), nil for the ordinary states.
    var miss: CompatMiss? {
        switch self {
        case .noStrip, .tabMissing: nil
        case .severalStrips: .severalTabStrips
        case .noToolbar: .tabStripWithoutToolbar
        case .noCloseButton: .tabWithoutCloseButton
        case .noShownTab: .noTabMarkedShown
        }
    }
}

// MARK: The script

enum PageTabsScript {
    /// `benchTabsToClose(mode, tabs, keep)`: the ids to close, in the strip's
    /// order, or null when the request can't be met. Pure.
    ///
    /// `tabs` is `[{id, shown}]`. "all" closes every tab. "others" closes
    /// every tab but `keep`, or but the shown one when `keep` is null. "one"
    /// closes `keep` alone. A `keep` that is not in the strip, no single
    /// shown tab to keep, or another mode, is null: nothing is guessed. An
    /// empty list is a fine answer ("nothing to close"), null is not.
    static let decision = #"""
    function benchTabsToClose(mode, tabs, keep) {
        "use strict";
        const ids = [];
        for (const tab of tabs) { if (!ids.includes(tab.id)) { ids.push(tab.id); } }
        if (mode === "all") { return ids; }
        if (mode !== "others" && mode !== "one") { return null; }
        let target = keep;
        if (target !== null && target !== undefined && typeof target !== "string") { return null; }
        if (target === null || target === undefined) {
            if (mode === "one") { return null; }
            if (ids.length === 0) { return []; }
            const shown = tabs.filter(tab => tab.shown);
            if (shown.length !== 1) { return null; }
            target = shown[0].id;
        }
        if (!ids.includes(target)) { return null; }
        return mode === "one" ? [target] : ids.filter(id => id !== target);
    }
    """#

    /// `benchReadStrip()`: `{state, tabs}`. `state` is "ok" with the strip's tabs
    /// in order, `[{id, shown, button, close}]` (`button` is whether the tab has
    /// the button that shows it, `close` its own close button or null), or one
    /// of "none" (no strip: no panel with tabs is open), "several" (more than
    /// one strip) and "no-toolbar" (a strip without the toolbar the tabs sit
    /// in), each with `tabs` null. Looks only inside the strip. Diagnostics runs
    /// this very function (`probe`), so what it reports is what the commands see.
    ///
    /// `benchReadTabs()` is its `tabs`: null unless there is exactly one strip
    /// with its toolbar.
    static let reader = #"""
    function benchReadStrip() {
        "use strict";
        const strips = Array.from(document.querySelectorAll('[data-testid="right-tab-strip"]'));
        if (strips.length === 0) { return { state: "none", tabs: null }; }
        if (strips.length !== 1) { return { state: "several", tabs: null }; }
        const bar = strips[0].querySelector('[role="toolbar"][aria-label="Open panels"]');
        if (!bar) { return { state: "no-toolbar", tabs: null }; }
        const tabs = [];
        for (const element of Array.from(bar.querySelectorAll("[data-tab-id]"))) {
            const id = element.getAttribute("data-tab-id");
            if (typeof id !== "string" || id === "") { continue; }
            const button = element.querySelector("[data-tab-btn]");
            const shown = (button !== null && button.getAttribute("aria-current") === "true")
                || element.getAttribute("data-shown") !== null;
            tabs.push({ id: id, shown: shown, button: button !== null, close: element.querySelector("button[data-tab-close]") });
        }
        return { state: "ok", tabs: tabs };
    }
    function benchReadTabs() { return benchReadStrip().tabs; }
    """#

    /// What Diagnostics runs in the page, read-only: how the strip looks, as
    /// counts only (never an id or a name). `{strip, tabs, withButton,
    /// withClose, shown}`, `strip` being `benchReadStrip`'s state.
    static let probe = reader + #"""

    const strip = benchReadStrip();
    const tabs = strip.tabs === null ? [] : strip.tabs;
    return JSON.stringify({
        strip: strip.state,
        tabs: tabs.length,
        withButton: tabs.filter(tab => tab.button).length,
        withClose: tabs.filter(tab => tab.close !== null).length,
        shown: tabs.filter(tab => tab.shown).length,
    });
    """#

    /// What `callAsyncJavaScript` runs, with the arguments `mode` ("others",
    /// "all" or "one") and `keep` (an id or null). Answers a JSON string:
    /// `{"status":"done"|"unavailable"|"refused", "closed":n, "stayed":n}`, and
    /// for the last two a `reason` (`PageTabsReason`) saying which hook it
    /// didn't find, so Capsid can tell a page with no tabs open from a page
    /// that changed.
    ///
    /// Before any press, every tab to close must have its close button: if
    /// one doesn't, nothing is pressed. Then, one tab at a time, in order, it
    /// reads the strip afresh (React re-renders it after every close), presses
    /// that tab's close button and waits, up to 300 ms in four short steps,
    /// for the tab to leave the strip. A strip that is gone altogether
    /// (closing the last tab may remove the panel) means the tab left.
    ///
    /// A tab that is still there after its wait stays. The sweep then stops:
    /// in 0.1.63 a tab with unsaved edits does not ask with `confirm`; the
    /// page raises its own dialog and keeps the tab until it is answered, and
    /// a second close that needs an answer would replace that dialog.
    /// `stayed` is that tab and every one not reached. A tab the page closed
    /// by itself meanwhile counts as closed.
    static let body = decision + "\n" + reader + #"""

    async function benchTabGone(id) {
        "use strict";
        for (const ms of [0, 50, 100, 150]) {
            await new Promise(resolve => {
                if (typeof setTimeout === "function") { setTimeout(resolve, ms); } else { resolve(); }
            });
            const tabs = benchReadTabs();
            if (tabs === null || !tabs.some(tab => tab.id === id)) { return true; }
        }
        return false;
    }

    const reply = (status, closed, stayed, reason) => JSON.stringify({ status: status, closed: closed, stayed: stayed, reason: reason });
    const strip = benchReadStrip();
    const first = strip.tabs;
    if (first === null) {
        return reply("unavailable", 0, 0,
            strip.state === "none" ? "no-strip" : strip.state === "several" ? "several-strips" : "no-toolbar");
    }
    const targets = benchTabsToClose(mode, first.map(tab => ({ id: tab.id, shown: tab.shown })), keep);
    if (targets === null) {
        const noneShown = mode === "others" && (keep === null || keep === undefined)
            && first.filter(tab => tab.shown).length !== 1;
        return reply("refused", 0, 0, noneShown ? "no-shown-tab" : "tab-missing");
    }
    for (const id of targets) {
        const tab = first.find(item => item.id === id);
        if (!tab || !tab.close) { return reply("unavailable", 0, 0, "no-close-button"); }
    }
    let closed = 0;
    for (const id of targets) {
        const now = benchReadTabs();
        const tab = now === null ? undefined : now.find(item => item.id === id);
        if (tab === undefined) { closed += 1; continue; }
        if (!tab.close) { return reply("unavailable", closed, targets.length - closed, "no-close-button"); }
        tab.close.click();
        if (!(await benchTabGone(id))) { break; }
        closed += 1;
    }
    return reply("done", closed, targets.length - closed);
    """#
}

// MARK: Running it

/// One sweep at a time: a second request while one is under way (⌥⌘W twice,
/// a menu item pressed meanwhile) is dropped, since the first one is still
/// reading the strip and waiting on the page.
@MainActor
final class PageTabCloser {
    private let perform: @MainActor (PageTabsClose) async -> PageTabsOutcome
    private(set) var isRunning = false

    init(perform: @escaping @MainActor (PageTabsClose) async -> PageTabsOutcome) {
        self.perform = perform
    }

    /// The sweep's outcome, or nil when another one was under way.
    @discardableResult
    func close(_ request: PageTabsClose) async -> PageTabsOutcome? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        return await perform(request)
    }
}

extension WebContainer {
    /// Presses the page's tab close buttons for `request`, in the one main web
    /// view. Never throws: a page that isn't up, or a script that fails, is
    /// `unavailable`. Logs only what happened, never a tab.
    func closeTabs(_ request: PageTabsClose) async -> PageTabsOutcome {
        guard status == .ready else { return .unavailable }
        let outcome: PageTabsOutcome
        do {
            let value = try await webView.callAsyncJavaScript(PageTabsScript.body, arguments: request.arguments,
                                                              in: nil, contentWorld: .defaultClient)
            guard let parsed = PageTabsOutcome.read(value) else {
                Logger.web.error("Close tabs: the page's answer wasn't understood")
                return .unavailable
            }
            outcome = parsed
        } catch {
            Logger.web.error("Close tabs: the script failed")
            return .unavailable
        }
        switch outcome {
        case .unavailable: Logger.web.notice("Close tabs: the strip or a close button wasn't found")
        case .refused: Logger.web.notice("Close tabs: the tab to keep wasn't in the strip")
        case .done: break
        }
        return outcome
    }
}

extension WebContainer {
    /// How the page's tab strip looks right now, as the commands would read
    /// it (`PageTabsScript.probe`): a JSON string of counts. Presses nothing.
    func readTabStrip() async throws -> String {
        guard status == .ready else { throw WebAPIError.notReady }
        let value = try await webView.callAsyncJavaScript(PageTabsScript.probe, arguments: [:],
                                                          in: nil, contentWorld: .defaultClient)
        guard let text = value as? String else { throw WebAPIError.badResponse }
        return text
    }
}

// MARK: The File menu's commands

/// Whether Close Other Tabs and Close All Tabs can be used, and what they
/// do. They act on the main window's page only, never on `ActiveWebPage`'s
/// choice, and only while the main window is the key window and the page is
/// ready: a Browser window, Settings or a sheet in front dims them.
@MainActor
final class PageTabCommands: ObservableObject {
    static let shared = PageTabCommands()

    @Published private(set) var isEnabled = false
    private var observers: [AnyCancellable] = []

    init() {
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification]
        // A turn later, as ActiveWebPage does: during the notification for the
        // old window, `keyWindow` can still be empty.
        observers = names.map { name in
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }
    }

    /// The rule: the main window is key, and the page is ready.
    nonisolated static func canClose(mainWindowIsKey: Bool, status: WebContainer.Status) -> Bool {
        mainWindowIsKey && status == .ready
    }

    func update(mainWindowIsKey: Bool, status: WebContainer.Status) {
        let enabled = Self.canClose(mainWindowIsKey: mainWindowIsKey, status: status)
        if isEnabled != enabled { isEnabled = enabled }
    }

    /// Reads the windows and the page. The web container is only asked while
    /// the main window is key, so a demo, which has none, never makes one.
    func refresh() {
        let main = MainWindowController.shared.windowIfLoaded
        let isKey = main != nil && NSApp?.keyWindow === main
        update(mainWindowIsKey: isKey, status: isKey ? WebContainer.shared.status : .starting)
    }

    func closeOthers() { start(.others(keeping: nil)) }
    func closeAll() { start(.all) }

    private func start(_ request: PageTabsClose) {
        // Asked afresh: the key window may have changed since the menu was drawn.
        refresh()
        guard isEnabled else { return }
        Task { await WebContainer.shared.tabCloser.close(request) }
    }
}
