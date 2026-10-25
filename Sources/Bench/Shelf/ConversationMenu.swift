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
// A file with no picture (Markdown, CSV, text) gets the same menu from the page
// but its tile carries no address, only the name it shows: the Generated tray's
// card has it as the `title` of its file-name label, and an open tile as the
// text of the first span in its header. The script then notes the name, adds
// the same four items, and a click posts `{action, kind: "document", name}`;
// Swift finds the file of that name among the session's files
// (ShelfDocuments.swift), and refuses a name two different files have.
//
// The selected words. On a right-click that left a selection alone (the
// selection was the same when the button went down as when the menu was asked
// for: WebKit selects the word under the pointer on a right-click outside the
// selection, which is not a passage anyone chose), the script adds the count of
// its characters, `selected`, to its message. The words stay in the page: Swift
// asks for them with `window.getSelection()` only when "Add Selection to Shelf"
// is chosen, never logs them, and writes them only to a note on the shelf.
//
// The order of the first path is not an API guarantee (see TabContextMenu): the
// script posts from inside the `contextmenu` event and WebKit asks for the menu
// after it, over one connection. A message that came late is not fresh, and
// the menu simply has no Shelf items; the File menu's commands stay the way in
// from Results. Nothing read from the page is logged, and the script never
// reads the text of the page's own menu items.
import AppKit
import Foundation
import os
import WebKit

private let log = Logger(subsystem: "local.sam.bench", category: "figure-menu")

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

    /// An item chosen in the page's own menu for a file with no picture: the
    /// action and the name its tile showed. There is no version to name.
    struct DocumentChoice: Equatable, Sendable {
        let action: ConversationAction
        let name: String
    }

    /// The choice a message names for a tile of a file with no picture:
    /// `{action, kind: "document", name}` with no `version` (a message that has
    /// one is a figure's, read by `choice(in:)`). The name is read as
    /// `ShelfDocument.name` has it; one with nothing left in it is no choice.
    static func documentChoice(in body: Any?) -> DocumentChoice? {
        guard let body = body as? [String: Any], body["kind"] as? String == "document", body["version"] == nil,
              let word = body["action"] as? String, let action = ConversationAction(rawValue: word),
              let name = (body["name"] as? String).flatMap({ ShelfDocument.name(hint: String($0.prefix(maxName))) }) else { return nil }
        return DocumentChoice(action: action, name: name)
    }

    /// How many characters the right-click left selected: the message's
    /// `selected`, a whole number above zero. The words are not in the message.
    static func selection(in body: Any?) -> Int? {
        guard let body = body as? [String: Any], let count = body["selected"] as? Int, count > 0 else { return nil }
        return count
    }

    /// The page's menu opened after a right-click on a figure, and the script
    /// could not put the items in it: `{unplaced: true}`.
    static func isUnplaced(_ body: Any?) -> Bool {
        guard let body = body as? [String: Any] else { return false }
        return body["unplaced"] as? Bool == true
    }

    /// The most steps a trace is read for; one right-click makes five at most.
    static let maxSteps = 8

    /// The steps a trace names, `{trace: [word, …]}`, as the script's own
    /// fixed words. Any other word is dropped, so nothing the page could put
    /// there is logged. Nil when the message isn't a trace.
    static func trace(in body: Any?) -> [FigureMenuStep]? {
        guard let body = body as? [String: Any], let words = body["trace"] as? [Any] else { return nil }
        return words.prefix(maxSteps).compactMap { ($0 as? String).flatMap(FigureMenuStep.init(rawValue:)) }
    }

    /// The log line for a trace: "Figure menu: contextmenu → figure-image → …".
    static func line(_ steps: [FigureMenuStep]) -> String {
        "Figure menu: " + (steps.isEmpty ? "no steps" : steps.map(\.rawValue).joined(separator: " → "))
    }
}

/// One step of a right-click as the page script saw it, in the script's fixed
/// words, so one right-click says in Capsid's log where the items stopped
/// (since 1.0.1, after a retry that showed nothing and logged nothing):
/// heard; the figure found under it (a picture, a link, a tray card's
/// thumbnail, the picture beside a layer over it) or none; a version in its
/// address or none (and then a tile or card of a file with no picture, by its
/// name: `figure-document`); the page's menu matched, some other menu, or no menu in
/// the two seconds; the items placed or not; or another right-click first.
enum FigureMenuStep: String, CaseIterable, Sendable {
    case contextmenu
    case figureImage = "figure-image", figureLink = "figure-link", figureCard = "figure-card"
    case figureBeside = "figure-beside", figureNone = "figure-none"
    /// A file with no picture, found by the name its tile or card shows.
    case figureDocument = "figure-document"
    case versionOK = "version-ok", versionNone = "version-none", noObserver = "no-observer"
    case menuMatched = "menu-matched", menuOther = "menu-other", menuNone = "menu-none"
    case placed, unplaced, interrupted
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

/// Whether the last right-click left words selected, within a second of the
/// message, for one menu: the same rule as the pick. Only the count is kept.
struct SelectionTarget: Equatable {
    private var count: Int?
    private var recordedAt: ContinuousClock.Instant?

    mutating func record(_ count: Int?, at instant: ContinuousClock.Instant) {
        self.count = count
        recordedAt = instant
    }

    /// The count, if it was recorded within `freshFor` before `instant`.
    /// Either way it is forgotten.
    mutating func take(at instant: ContinuousClock.Instant) -> Int? {
        defer {
            count = nil
            recordedAt = nil
        }
        guard let count, let recordedAt, instant >= recordedAt, instant - recordedAt <= ConversationTarget.freshFor else { return nil }
        return count
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
    private var selection = SelectionTarget()
    private let now: () -> ContinuousClock.Instant
    private let daemonPort: @MainActor () -> Int?
    private let run: @MainActor (ConversationAction, ConversationPick) -> Void
    private let runDocument: @MainActor (ConversationAction, String) -> Void
    private let isSession: @MainActor () -> Bool
    private let shelveSelection: @MainActor () -> Void
    private let breadcrumbs: CompatBreadcrumbs
    private let traced: @MainActor (String) -> Void

    /// `run` is what an item does, in the Mac's menu and in the page's own;
    /// `runDocument` what it does for a file with no picture, named by its
    /// tile (only the page's menu has those). `isSession` says the main
    /// window is on a session's page, and `shelveSelection` is what "Add
    /// Selection to Shelf" does. `now` is the clock, which tests replace,
    /// `breadcrumbs` is where "the figure menu didn't look as Capsid expects"
    /// goes, and `traced` where a right-click's steps go (the log).
    init(now: @escaping () -> ContinuousClock.Instant = { .now },
         daemonPort: @escaping @MainActor () -> Int?,
         breadcrumbs: CompatBreadcrumbs = .shared,
         traced: @escaping @MainActor (String) -> Void = ConversationMenu.logTrace,
         isSession: @escaping @MainActor () -> Bool = { false },
         shelveSelection: @escaping @MainActor () -> Void = {},
         runDocument: @escaping @MainActor (ConversationAction, String) -> Void = { _, _ in },
         run: @escaping @MainActor (ConversationAction, ConversationPick) -> Void) {
        self.now = now
        self.daemonPort = daemonPort
        self.breadcrumbs = breadcrumbs
        self.traced = traced
        self.isSession = isSession
        self.shelveSelection = shelveSelection
        self.runDocument = runDocument
        self.run = run
    }

    /// A trace's line, kept: fixed words only, so it is public.
    static func logTrace(_ line: String) {
        log.notice("\(line, privacy: .public)")
    }

    /// Adds the user script and its message handler. The controller keeps a
    /// strong reference to the handler, so it gets a proxy that only holds
    /// this object weakly.
    func install(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: Self.world))
        controller.add(WeakConversationHandler(menu: self), contentWorld: Self.world, name: Self.handlerName)
    }

    func record(_ pick: ConversationPick?, selected: Int? = nil) {
        target.record(pick, at: now())
        selection.record(selected, at: now())
    }

    /// Adds the items to `menu` if the last right-click was on an artifact's
    /// figure or link, just now. Otherwise the menu is left as WebKit made it.
    func addItems(to menu: NSMenu) {
        guard let pick = target.take(at: now()) else { return }
        Self.insertItems(into: menu, for: pick, run: run)
    }

    /// "Add Selection to Shelf" in the Mac's menu on words the user selected
    /// and right-clicked: only when the right-click left a selection alone
    /// (a count came with its message, just now), the main window is on a
    /// session's page, and the menu is not one that has Capsid's items already
    /// (a tab's, a figure's or a file link's keep theirs). True when it was added.
    @discardableResult
    func addSelectionItem(to menu: NSMenu) -> Bool {
        let selected = selection.take(at: now())
        guard Self.mayOfferSelection(selected: selected, onSession: isSession(), menu: menu) else { return false }
        Self.insertSelectionItem(into: menu, run: shelveSelection)
        return true
    }

    static let selectionTitle = "Add Selection to Shelf"
    static let selectionID = NSUserInterfaceItemIdentifier("capsid.shelfSelection")
    /// WebKit's own identifier for "Copy" in a menu on selected text.
    private static let copyID = "WKMenuItemIdentifierCopy"

    /// Whether the item is offered: some words are selected, on a session's
    /// page, in a menu with none of Capsid's items and not this one already.
    static func mayOfferSelection(selected: Int?, onSession: Bool, menu: NSMenu) -> Bool {
        guard let selected, selected > 0, onSession else { return false }
        let ours: Set<NSUserInterfaceItemIdentifier> = [itemID, selectionID, TabContextMenu.itemID]
        return !menu.items.contains { $0.identifier.map(ours.contains) == true }
    }

    /// The item goes right after WebKit's Copy, or at the end of the menu
    /// (after a separator, when the menu has items) if there is no Copy.
    static func insertSelectionItem(into menu: NSMenu, run: @escaping @MainActor () -> Void) {
        let handler = ConversationSelectionAction(run: run)
        let item = NSMenuItem(title: selectionTitle, action: #selector(ConversationSelectionAction.fire(_:)), keyEquivalent: "")
        item.target = handler
        // The item holds its target weakly; this keeps it alive as long as the item.
        item.representedObject = handler
        item.identifier = selectionID
        if let copy = menu.items.firstIndex(where: { $0.identifier?.rawValue == copyID }) {
            menu.insertItem(item, at: copy + 1)
        } else {
            if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) }
            menu.addItem(item)
        }
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
    /// main window's own page (`accepted`). Five shapes:
    /// - `{kind, url, name}`: what the last right-click was on, kept a second
    ///   for the Mac's menu (anything else clears it), and `selected`, the
    ///   count of characters the right-click left selected, with it when there
    ///   were any;
    /// - `{action, version, name}`: an item chosen in the page's own menu, run
    ///   at once (that menu can stay open far longer than a second);
    /// - `{action, kind: "document", name}`: the same for a file with no
    ///   picture, which Swift finds by its name;
    /// - `{unplaced: true}`: the page's menu opened and the items had nowhere
    ///   to go, which is a change in Claude Science worth a breadcrumb;
    /// - `{trace: [...]}`: a right-click's steps, logged, and leaving the pick
    ///   as it is (it can come before WebKit asks for the Mac's menu).
    /// From anyone else a message is nothing, and clears the last pick.
    func hear(_ body: Any?, accepted: Bool) {
        guard accepted else {
            record(nil)
            return
        }
        if let choice = ConversationMenuMessage.choice(in: body) {
            run(choice.action, choice.pick)
        } else if let choice = ConversationMenuMessage.documentChoice(in: body) {
            runDocument(choice.action, choice.name)
        } else if ConversationMenuMessage.isUnplaced(body) {
            breadcrumbs.record(.figureMenuNotUnderstood)
        } else if let steps = ConversationMenuMessage.trace(in: body) {
            traced(ConversationMenuMessage.line(steps))
        } else {
            record(ConversationMenuMessage.pick(in: body, daemonPort: daemonPort()),
                   selected: ConversationMenuMessage.selection(in: body))
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
    /// older pick is never taken for this click; and, when the right-click left
    /// words selected that were selected before it (a capturing `mousedown`
    /// listener keeps them, in the script only, for a right-click or a
    /// control-click), `selected`, their count, in the same message. A picture can be under a
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
    /// `{unplaced: true}`. A file with no picture has no address: on a
    /// session's page, when the right-click was on a Generated card with no
    /// picture, in an open tile's body or in its header, or on a link or
    /// picture in a tile that names no version, the script takes the name the
    /// card or tile shows (the title of the card's file-name label; the first
    /// span of the tile's header, which holds the button for its menu), watches
    /// for the menu the same way and posts `{action, kind: "document", name}`
    /// when an item is chosen. Once a right-click is done with (no figure, no
    /// version, the items placed or not, no menu in the two seconds, or
    /// another right-click first) it posts its steps, `{trace}`, in the fixed
    /// words of `FigureMenuStep`.
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
      // A session's own page: where there is a conversation to put a file or some of its words on the shelf from.
      const SESSION_PAGE = /^\/projects\/[^\/]+\/frames\/[0-9a-f-]{36}\/?$/;
      // The longest name read from a tile.
      const NAME_MAX = 300;
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

      // The steps of one right-click, in fixed words only (never anything read
      // from the page), posted once as `{trace}` when it ends, so that Capsid's
      // log says how far it got.
      let trail = null;

      function step(word) {
        if (trail) trail.push(word);
      }

      function report(word) {
        if (!trail) return;
        trail.push(word);
        handler.postMessage({ trace: trail });
        trail = null;
      }

      // The figure or the link a right-click was on.
      function figureAt(event) {
        const node = event.target;
        const element = node && node.nodeType === 1 ? node : (node && node.parentElement) || null;
        if (!element || !element.closest) return null;
        const found = element.closest("img, a[href]");
        if (found) {
          step(isImage(found) ? "figure-image" : "figure-link");
          return found;
        }
        const card = element.closest('[data-testid="turn-tray-card"]');
        const thumbnail = card ? card.querySelector("img") : pictureBeside(element, event);
        if (thumbnail) step(card ? "figure-card" : "figure-beside");
        return thumbnail;
      }

      // A name read from a tile: its last part if it is given as a path, one line, no control characters.
      function nameFrom(text) {
        const last = String(text || "").split(/[\\/]/).pop();
        return last.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, "").trim().slice(0, NAME_MAX);
      }

      // A file with no picture (Markdown, a table, text), found by the name its card or tile shows, on a session's
      // page; "" if it is neither. A card in the Generated tray labels itself with the whole name as the title of its
      // file-name label. An open tile (the side pane's, a tab's) shows it as the first span of its header, and the
      // header also holds the button for the tile's menu, which is how the tile is told from any other header.
      function documentAt(event) {
        if (!SESSION_PAGE.test(String(location.pathname || ""))) return "";
        const node = event.target;
        const element = node && node.nodeType === 1 ? node : (node && node.parentElement) || null;
        if (!element || !element.closest) return "";
        const card = element.closest('[data-testid="turn-tray-card"]');
        if (card) {
          const label = card.querySelector('[data-testid="middle-truncated-filename"]');
          return label ? nameFrom(label.title) : "";
        }
        let start = element.closest('[data-testid="artifact-preview-region"]');
        if (!start) {
          const bar = element.closest("header");
          if (bar && bar.querySelector('[data-testid="artifact-actions"]')) start = bar;
        }
        for (let up = start && start.parentElement; up && up !== document.body && up !== document.documentElement; up = up.parentElement) {
          const bar = up.querySelector("header");
          if (bar && bar.querySelector('[data-testid="artifact-actions"]')) {
            const label = bar.querySelector("span");
            return label ? nameFrom(label.textContent) : "";
          }
        }
        return "";
      }

      // The words selected in the page, as the browser has them. They are read here and compared, and only their
      // count is ever posted.
      function selectedText() {
        const selection = typeof window.getSelection === "function" ? window.getSelection() : null;
        return selection ? String(selection) : "";
      }

      // What was selected when the button went down for a right-click (or a control-click, which is one on a Mac).
      // WebKit selects the word under the pointer when a right-click lands outside the selection, before the
      // contextmenu event, so only a selection the same at the menu as at the button is one the user chose.
      let before = "";

      document.addEventListener("mousedown", (event) => {
        if (!event.isTrusted) return;
        before = event.button === 2 || (event.button === 0 && event.ctrlKey) ? selectedText() : "";
      }, true);

      // How many characters the right-click left selected, if it left them alone on a session's page; else 0.
      function selectionLeft() {
        const kept = before;
        before = "";
        if (kept === "" || !SESSION_PAGE.test(String(location.pathname || ""))) return 0;
        const now = selectedText();
        return now === kept && now.trim() !== "" ? Array.from(now).length : 0;
      }

      // A message to Swift; with the count of what the right-click left selected, if there was any.
      function tell(message, selected) {
        if (selected > 0) message.selected = selected;
        handler.postMessage(message);
      }

      // Whether any menu at all, named or not, is among the nodes just added.
      function anyMenuIn(records) {
        for (const record of records) {
          for (const added of record.addedNodes) {
            if (!added || added.nodeType !== 1) continue;
            if ((added.closest && added.closest('[role="menu"]')) || (added.querySelector && added.querySelector('[role="menu"]'))) return true;
          }
        }
        return false;
      }

      let watch = null;

      function stopWatch() {
        const view = watch;
        watch = null;
        if (!view) return;
        // The menu stays as tall as it is while the items are in it, however long it is open; with them gone
        // (or the menu) the height Capsid gave it goes too.
        if (!holds(view)) release(view);
        if (view.observer) view.observer.disconnect();
        if (view.timer) clearTimeout(view.timer);
        if (view.hold) clearTimeout(view.hold);
      }

      function startWatch(figure) {
        if (typeof MutationObserver !== "function") { report("no-observer"); return; }
        const view = { figure: figure, menu: null, nodes: [], observer: null, timer: null, hold: null, held: null, other: false };
        view.observer = new MutationObserver((records) => changed(view, records));
        view.observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
        view.timer = setTimeout(() => {
          if (watch !== view || view.menu) return;
          report(view.other ? "menu-other" : "menu-none");
          stopWatch();
        }, WAIT_MS);
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
          else if (!view.other && anyMenuIn(records)) view.other = true;
          return;
        }
        if (view.menu.isConnected) { restore(view); return; }
        // The menu closed, or the page drew it again as a new one.
        release(view);
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
        step("menu-matched");
        // The first item that isn't the red one, for its classes and its icon box.
        let template = null;
        const items = menu.querySelectorAll('[role="menuitem"]');
        for (let index = 0; index < items.length && !template; index++) {
          if (String(items[index].className).indexOf("danger") < 0) template = items[index];
        }
        if (!template) {
          handler.postMessage({ unplaced: true });
          report("unplaced");
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
        fit(view);
        report("placed");
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
        fit(view);
        view.observer.takeRecords();
      }

      // Whether the group is in the menu, all of it, as the menu holds it now.
      function holds(view) {
        const menu = view.menu;
        if (!menu || !menu.isConnected || view.nodes.length === 0) return false;
        for (let index = 0; index < view.nodes.length; index++) {
          if (view.nodes[index].parentNode !== menu) return false;
        }
        return true;
      }

      // The page placed its menu to fit without the new items: keep it on screen. A window too short for the menu
      // with them in it (a small window, or a page zoomed to 200 or 300%, which makes the window that much shorter
      // in CSS pixels) gets the menu as tall as the window less the margin, scrolling: the page's own menu element
      // takes `max-height` and `overflow-y` for as long as the items are in it, and gives back what it had when they
      // are not (`release`). Then it is moved, as before, so that what it has of height is inside the window.
      function fit(view) {
        const menu = view.menu;
        const win = (menu.ownerDocument && menu.ownerDocument.defaultView) || window;
        const margin = 8;
        // Measured as the page sized it, with the items in.
        release(view);
        let box = menu.getBoundingClientRect();
        const room = win.innerHeight - 2 * margin;
        if (room > 0 && box.height > room) {
          view.held = { maxHeight: menu.style.maxHeight, overflowY: menu.style.overflowY };
          menu.style.maxHeight = room + "px";
          menu.style.overflowY = "auto";
          box = menu.getBoundingClientRect();
        }
        const below = box.bottom - (win.innerHeight - margin);
        if (below > 0) menu.style.top = Math.max(margin, box.top - below) + "px";
        const beyond = box.right - (win.innerWidth - margin);
        if (beyond > 0) menu.style.left = Math.max(margin, box.left - beyond) + "px";
      }

      // What `fit` put on the menu goes, and the menu's own settings come back.
      function release(view) {
        const held = view.held;
        view.held = null;
        if (!held || !view.menu) return;
        view.menu.style.maxHeight = held.maxHeight;
        view.menu.style.overflowY = held.overflowY;
      }

      function choose(view, entry, event) {
        if (!event.isTrusted) return;
        event.preventDefault();
        event.stopPropagation();
        const message = { action: entry.action, name: view.figure.name, kind: view.figure.kind };
        if (view.figure.version) message.version = view.figure.version;
        handler.postMessage(message);
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
        // A right-click before the last one's menu came ends that one's trace.
        report("interrupted");
        stopWatch();
        trail = ["contextmenu"];
        const selected = selectionLeft();
        const found = figureAt(event);
        if (!found) {
          tell({ kind: null }, selected);
          const named = documentAt(event);
          if (named === "") {
            report("figure-none");
            return;
          }
          step("figure-document");
          startWatch({ kind: "document", version: null, name: named });
          return;
        }
        const image = isImage(found);
        const address = String((image ? (found.currentSrc || found.src) : found.href) || "");
        const hint = image ? (found.alt || found.title) : (found.download || found.textContent || found.title);
        const name = String(hint || "").trim().slice(0, 300);
        const kind = image ? "image" : "link";
        tell({ kind: kind, url: address.slice(0, 4096), name: name }, selected);
        const version = versionOf(address);
        if (!version) {
          // A link or a picture in a Markdown tile names no file; the tile may.
          const named = documentAt(event);
          if (named === "") {
            report("version-none");
            return;
          }
          step("version-none");
          step("figure-document");
          startWatch({ kind: "document", version: null, name: named });
          return;
        }
        step("version-ok");
        startWatch({ kind: kind, version: version, name: name });
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

/// What "Add Selection to Shelf" does when it is chosen.
@MainActor
private final class ConversationSelectionAction: NSObject {
    private let run: @MainActor () -> Void

    init(run: @escaping @MainActor () -> Void) {
        self.run = run
    }

    @objc func fire(_ sender: Any?) {
        run()
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

/// Add Selection to Shelf's one look at the page, run in Capsid's own content
/// world when the item is chosen: the selection's text, cut at `limit`
/// characters. No element, no selector, no fetch; nothing is posted.
enum ShelfSelectionScript {
    static let read = #"""
    const selection = window.getSelection();
    const text = selection ? String(selection) : "";
    return Array.from(text).slice(0, Math.max(0, limit)).join("");
    """#
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
        /// The session's files, as its list gives them (the list Results
        /// reads); nil when they couldn't be read. For a tile that shows only
        /// a name.
        var files: @MainActor (String) async -> [ArtifactEntry]? = { _ in nil }
        /// The words selected in the page, at most this many characters, or
        /// nil when there are none (or the page doesn't answer).
        var selection: @MainActor (Int) async -> String? = { _ in nil }

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
                results: { ResultsWindowController.shared.show(focusing: $0) },
                files: { frame in
                    guard Demo.mode == nil,
                          case .answered(.list(let entries)) = await ResultsShelf.shared.transfers.read(
                            .list(frame: frame), priority: .foreground, keepsOnClose: true) else { return nil }
                    return entries
                },
                selection: { limit in await WebContainer.shared.selectedText(limit: limit) })
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
        await perform(action, on: entry, in: session)
    }

    /// An item chosen for a tile of a file with no picture, which carries only
    /// the name it shows. Capsid finds the file of that name among the files of
    /// the session in the main window (`ShelfDocument.match`) and does what it
    /// does for a figure; a name no file has, or two different files have, is a
    /// sentence on the toast and nothing else, never a guess. Show in Results
    /// needs no file, only the session, so it does not wait for the list.
    func run(_ action: ConversationAction, named name: String) async {
        let toast = dependencies.toast
        guard let route = dependencies.route() else {
            toast.show(.failed(Self.noSession))
            return
        }
        if action == .addToShelf { toast.show(.adding) }
        let session = await dependencies.session(route)
        if action == .showInResults {
            dependencies.results(session)
            return
        }
        guard let files = await dependencies.files(session.id) else {
            toast.show(.failed(ShelfDocument.unreadable))
            return
        }
        switch ShelfDocument.match(name: name, in: files) {
        case .found(let entry): await perform(action, on: entry, in: session)
        case .none: toast.show(.failed(ShelfDocument.notFound(name)))
        case .several: toast.show(.failed(ShelfDocument.several(name)))
        }
    }

    /// What an item does with a file, once it is known which: `entry` is the
    /// version, with what is known of its name (a picture's words, or a
    /// listing's facts).
    private func perform(_ action: ConversationAction, on entry: ArtifactEntry, in session: SessionStatus) async {
        let toast = dependencies.toast
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
            let facts = await dependencies.facts(entry.version)
            let known = facts.map {
                ArtifactEntry(version: entry.version, artifact: $0.a, name: $0.name ?? entry.name, mime: $0.mime,
                              size: $0.size ?? 0, at: $0.at)
            }
            // The version is the user's pick: it stays the selection, whichever
            // newer answer shows another, and whether or not its answer is found.
            dependencies.keep(KeepSubject(session: session, entry: known ?? entry, selectsItsVersion: true))
        case .openAsReference:
            dependencies.reference(session, entry.version)
        case .showInResults:
            dependencies.results(session)
        }
    }

    /// Add Selection to Shelf: the words selected in the page become a note on
    /// the shelf (`Shelf.addNote`), with the session they were selected in.
    /// What was selected is read now, from the page, and goes only to the
    /// note's folder: never to the log, never to the toast.
    func shelveSelection() async {
        let toast = dependencies.toast
        guard let route = dependencies.route() else {
            toast.show(.failed(Self.noSession))
            return
        }
        toast.show(.adding)
        guard let text = await dependencies.selection(ShelfSelectionNote.limit).flatMap({ ShelfSelectionNote.clean($0) }) else {
            toast.show(.failed(ShelfSelectionNote.nothingSelected))
            return
        }
        let session = await dependencies.session(route)
        switch await dependencies.shelf.addNote(ShelfSelectionNote(session: session, text: text)) {
        case .added(let placement): toast.show(.added(placement))
        case .alreadyOnShelf(let placement): toast.show(.already(placement))
        case .failed(let sentence): toast.show(.failed(sentence))
        }
    }
}
