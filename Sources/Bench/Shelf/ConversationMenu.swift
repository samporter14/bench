// ConversationMenu.swift — Add to Shelf, Keep with Data and Code…, Open as
// Reference and Show in Results in the right-click menu of a figure or a file
// link in Claude Science's page (DESIGN.md, Shelf → From the conversation;
// board 10). WebKit's menu says which kind of thing was clicked (its items are
// "Copy Image", "Copy Link"…) but never which address, and the address is what
// names the file; so a small user script, in a content world of its own, tells
// Swift what the last right-click was on, as `TabContextMenu` does for tabs.
// The main window's web view adds the items when its menu opens.
//
// The order of the two is not an API guarantee (see TabContextMenu): the
// script posts from inside the `contextmenu` event and WebKit asks for the menu
// after it, over one connection. A message that came late is not fresh, and
// the menu simply has no Shelf items; the File menu's commands stay the way in
// from Results. Nothing read from the page is logged.
import AppKit
import Foundation
import WebKit

// MARK: What was clicked

/// The four things the menu does with the clicked file.
enum ConversationAction: CaseIterable, Sendable {
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

    /// `run` is what an item does. `now` is the clock, which tests replace.
    init(now: @escaping () -> ContinuousClock.Instant = { .now },
         daemonPort: @escaping @MainActor () -> Int?,
         run: @escaping @MainActor (ConversationAction, ConversationPick) -> Void) {
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
        let port = daemonPort()
        let accepted = TabMenuMessage.isAccepted(
            isMainFrame: message.frameInfo.isMainFrame,
            fromMainWebView: message.webView != nil && message.webView === webView,
            isDaemonOrigin: WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port,
                                                    daemonPort: port))
        record(accepted ? ConversationMenuMessage.pick(in: message.body, daemonPort: port) : nil)
    }

    // MARK: The page's side

    /// A capturing `contextmenu` listener: posts `{kind, url, name}` for the
    /// nearest picture or link under the right-click (its address as the
    /// browser resolved it, a picture's alt text or a link's text), and
    /// `{kind: null}` for anything else, so an older pick is never taken for
    /// this click. Only real clicks, and only on the daemon's own page.
    nonisolated static let script = #"""
    (() => {
      "use strict";
      if (location.protocol !== "http:" || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capsidShelfMenu;
      if (!handler) return;
      document.addEventListener("contextmenu", (event) => {
        if (!event.isTrusted) return;
        const node = event.target;
        const element = node && node.nodeType === 1 ? node : (node && node.parentElement) || null;
        const found = element && element.closest ? element.closest("img, a[href]") : null;
        if (!found) { handler.postMessage({ kind: null }); return; }
        const image = String(found.tagName).toLowerCase() === "img";
        const url = image ? (found.currentSrc || found.src) : found.href;
        const hint = image ? (found.alt || found.title) : (found.download || found.textContent || found.title);
        handler.postMessage({ kind: image ? "image" : "link", url: String(url || "").slice(0, 4096),
                              name: String(hint || "").trim().slice(0, 300) });
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
