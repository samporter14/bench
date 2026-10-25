// TabContextMenu.swift — Close Tab, Close Other Tabs and Close All Tabs in the
// right-click menu of a tab in Claude Science's right-hand panel (DESIGN.md,
// Main window). WebKit's menu is built outside the page and says nothing of
// which element it is for, so a small user script, in a content world of its
// own, tells Swift which tab a right-click was on; the main window's web view
// adds the items when its menu opens.
//
// The order of the two is not an API guarantee. The script posts from inside
// the `contextmenu` event, before the page process asks the app to show the
// menu, and both travel one connection in order, so the message should land
// first. If it didn't, or came late, the tab would not be fresh and the menu
// would simply have no extra items: the File menu's commands are the main path.
// Nothing read from the page is logged.
import AppKit
import Foundation
import WebKit

// MARK: Which tab, and for how long

/// The tab the last right-click was on. A right-click on anything else
/// records "no tab", so an older tab is never used for it; and a tab is taken
/// once, within a second, so it can't be used for a later menu either.
struct TabMenuTarget: Equatable {
    /// How long after the message a menu may still use it.
    static let freshFor: Duration = .seconds(1)

    private var tab: String?
    private var recordedAt: ContinuousClock.Instant?

    mutating func record(_ tab: String?, at instant: ContinuousClock.Instant) {
        self.tab = tab
        recordedAt = instant
    }

    /// The tab, if it was recorded within `freshFor` before `instant`. Either
    /// way it is forgotten.
    mutating func take(at instant: ContinuousClock.Instant) -> String? {
        defer {
            tab = nil
            recordedAt = nil
        }
        guard let tab, let recordedAt, instant >= recordedAt, instant - recordedAt <= Self.freshFor else { return nil }
        return tab
    }
}

enum TabMenuMessage {
    /// A longer id than any real one is not taken.
    static let maxIDLength = 512

    /// The tab a message names, or nil for "no tab" and for anything that isn't
    /// `{tab: <non-empty string>}`.
    static func tab(in body: Any?) -> String? {
        guard let body = body as? [String: Any], let id = body["tab"] as? String,
              !id.isEmpty, id.utf8.count <= maxIDLength else { return nil }
        return id
    }

    /// Only the main web view's main frame, on the daemon's own origin: a
    /// pop-up shares the script and the handler, and can be someone else's page.
    static func isAccepted(isMainFrame: Bool, fromMainWebView: Bool, isDaemonOrigin: Bool) -> Bool {
        isMainFrame && fromMainWebView && isDaemonOrigin
    }
}

// MARK: The menu

@MainActor
final class TabContextMenu {
    static let handlerName = "capsidTabMenu"
    /// Its own world: the page can't see the script, or reach its handler.
    static let world = WKContentWorld.world(name: "capsid-tabs")

    static let titles = ["Close Tab", "Close Other Tabs", "Close All Tabs"]
    static let itemID = NSUserInterfaceItemIdentifier("capsid.tabMenu")

    /// The web view the messages must come from.
    weak var webView: WKWebView?

    private var target = TabMenuTarget()
    private let now: () -> ContinuousClock.Instant
    private let daemonPort: @MainActor () -> Int?
    private let run: @MainActor (PageTabsClose) -> Void

    /// `run` is what an item does: the sweep for a request. `now` is the clock,
    /// which tests replace.
    init(now: @escaping () -> ContinuousClock.Instant = { .now },
         daemonPort: @escaping @MainActor () -> Int?,
         run: @escaping @MainActor (PageTabsClose) -> Void) {
        self.now = now
        self.daemonPort = daemonPort
        self.run = run
    }

    /// Adds the user script and its message handler. The controller keeps a
    /// strong reference to the handler, so it gets a proxy that only holds
    /// this object weakly.
    func install(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.world))
        controller.add(WeakTabMenuHandler(menu: self), contentWorld: Self.world, name: Self.handlerName)
    }

    func record(_ tab: String?) {
        target.record(tab, at: now())
    }

    /// Adds the items at the top of `menu` if the last right-click was on a
    /// tab, just now. Otherwise the menu is left as WebKit made it.
    func addItems(to menu: NSMenu) {
        guard let tab = target.take(at: now()) else { return }
        Self.insertItems(into: menu, for: tab, run: run)
    }

    /// Close Tab, Close Other Tabs (keeping `tab`), Close All Tabs and a
    /// separator, at the top of `menu`. Not added twice.
    static func insertItems(into menu: NSMenu, for tab: String, run: @escaping @MainActor (PageTabsClose) -> Void) {
        guard menu.items.first?.identifier != itemID else { return }
        let requests: [PageTabsClose] = [.one(tab), .others(keeping: tab), .all]
        for (index, (title, request)) in zip(titles, requests).enumerated() {
            let action = TabMenuAction(request: request, run: run)
            let item = NSMenuItem(title: title, action: #selector(TabMenuAction.fire(_:)), keyEquivalent: "")
            item.target = action
            // The item holds its target weakly; this keeps it alive as long as the item.
            item.representedObject = action
            item.identifier = itemID
            menu.insertItem(item, at: index)
        }
        let separator = NSMenuItem.separator()
        separator.identifier = itemID
        menu.insertItem(separator, at: requests.count)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        let accepted = TabMenuMessage.isAccepted(
            isMainFrame: message.frameInfo.isMainFrame,
            fromMainWebView: message.webView != nil && message.webView === webView,
            isDaemonOrigin: WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port,
                                                    daemonPort: daemonPort()))
        record(accepted ? TabMenuMessage.tab(in: message.body) : nil)
    }

    // MARK: The page's side

    /// A capturing `contextmenu` listener: posts `{tab: <id>}` when the
    /// right-click is on a tab in the strip, and `{tab: null}` on anything
    /// else, so an older tab is never taken for this one. Only real clicks,
    /// and only on the daemon's own page.
    nonisolated static let script = #"""
    (() => {
      "use strict";
      if (location.protocol !== "http:" || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capsidTabMenu;
      if (!handler) return;
      document.addEventListener("contextmenu", (event) => {
        if (!event.isTrusted) return;
        const node = event.target;
        const element = node && node.nodeType === 1 ? node : (node && node.parentElement) || null;
        const tab = element && element.closest
          ? element.closest('[data-testid="right-tab-strip"] [data-tab-id]') : null;
        const id = tab ? tab.getAttribute("data-tab-id") : null;
        handler.postMessage({ tab: typeof id === "string" && id !== "" ? id : null });
      }, true);
    })();
    """#
}

/// What one item does when it is chosen.
@MainActor
private final class TabMenuAction: NSObject {
    private let request: PageTabsClose
    private let run: @MainActor (PageTabsClose) -> Void

    init(request: PageTabsClose, run: @escaping @MainActor (PageTabsClose) -> Void) {
        self.request = request
        self.run = run
    }

    @objc func fire(_ sender: Any?) {
        run(request)
    }
}

/// What the user content controller holds in place of the menu object.
@MainActor
private final class WeakTabMenuHandler: NSObject, WKScriptMessageHandler {
    private weak var menu: TabContextMenu?

    init(menu: TabContextMenu) {
        self.menu = menu
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        menu?.receive(message)
    }
}

// MARK: The main window's web view

/// The main window's web view, a plain `WKWebView` that adds the tab items to
/// its context menu when the right-click was on a tab, and the Shelf items
/// (Shelf/ConversationMenu.swift) when it was on a figure or a file link; on
/// words the user selected, in a menu with neither, it adds Add Selection to
/// Shelf.
final class TabMenuWebView: WKWebView {
    var tabMenu: TabContextMenu?
    var shelfMenu: ConversationMenu?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        tabMenu?.addItems(to: menu)
        shelfMenu?.addItems(to: menu)
        shelfMenu?.addSelectionItem(to: menu)
    }
}
