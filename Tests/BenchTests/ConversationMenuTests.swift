// ConversationMenuTests.swift — the Shelf items in the right-click menu of a
// figure or a file link (Shelf/ConversationMenu.swift), on made-up pages and
// menus: the user script that says what a right-click was on (run in
// JavaScriptCore against a tiny fake page), how its message is read, how long
// a pick is fresh, the items put into an NSMenu and only when the click was on
// an artifact's figure or link, and what each item does — over a made-up shelf,
// session and toast, with nothing sent to Claude Science. WebKit's own ordering
// of message and menu, and the menu as drawn, are checked by eye (TESTING.md).
import AppKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct ConversationMenuTests {
    static let version = ShelfAddressTests.version
    static let port = 8123
    static let address = "http://localhost:8123/api/artifacts/versions/\(version)"

    @Test func theFourItemsAreTheBoardsWords() {
        #expect(ConversationAction.allCases.map(\.title)
            == ["Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results"])
    }

    // MARK: Reading the message

    @Test func aMessageNamesAFigureOrALink() {
        let image = ConversationMenuMessage.pick(in: ["kind": "image", "url": Self.address, "name": "Z prime by plate"],
                                                 daemonPort: Self.port)
        #expect(image == ConversationPick(kind: .image, version: Self.version, name: "Z prime by plate"))
        let link = ConversationMenuMessage.pick(in: ["kind": "link", "url": Self.address + "?v=\(Self.version)", "name": "qc_notes.md"],
                                                daemonPort: Self.port)
        #expect(link == ConversationPick(kind: .link, version: Self.version, name: "qc_notes.md"))
    }

    @Test func aMessageWithoutAWordForItsNameGetsANoun() {
        #expect(ConversationMenuMessage.pick(in: ["kind": "image", "url": Self.address], daemonPort: Self.port)?.name == "Figure")
        #expect(ConversationMenuMessage.pick(in: ["kind": "link", "url": Self.address, "name": ""], daemonPort: Self.port)?.name == "File")
    }

    @Test func anythingElseIsNoPick() {
        let port = Self.port
        #expect(ConversationMenuMessage.pick(in: ["kind": NSNull()], daemonPort: port) == nil)
        #expect(ConversationMenuMessage.pick(in: ["kind": "video", "url": Self.address], daemonPort: port) == nil)
        #expect(ConversationMenuMessage.pick(in: ["kind": "image"], daemonPort: port) == nil)
        #expect(ConversationMenuMessage.pick(in: ["kind": "image", "url": 5], daemonPort: port) == nil)
        #expect(ConversationMenuMessage.pick(in: ["url": Self.address], daemonPort: port) == nil)
        #expect(ConversationMenuMessage.pick(in: Self.address, daemonPort: port) == nil)
        #expect(ConversationMenuMessage.pick(in: nil, daemonPort: port) == nil)
        // An address that is not an artifact's: an avatar, a link out, a blob.
        for url in ["http://localhost:8123/static/avatar.png", "https://example.com/api/artifacts/versions/\(Self.version)",
                    "blob:http://localhost:8123/\(Self.version)", "http://localhost:9999/api/artifacts/versions/\(Self.version)"] {
            #expect(ConversationMenuMessage.pick(in: ["kind": "image", "url": url], daemonPort: port) == nil, "\(url)")
        }
        // Nor on a page whose port isn't known.
        #expect(ConversationMenuMessage.pick(in: ["kind": "image", "url": Self.address], daemonPort: nil) == nil)
    }

    @Test func aLongNameIsCutBeforeItIsRead() {
        let long = String(repeating: "n", count: ConversationMenuMessage.maxName * 3)
        let pick = ConversationMenuMessage.pick(in: ["kind": "link", "url": Self.address, "name": long], daemonPort: Self.port)
        // Cut at the message's limit, then at a file name's.
        #expect(pick?.name.count == HistoryFile.nameLimit)
        #expect(HistoryFile.nameLimit <= ConversationMenuMessage.maxName)
    }

    @Test func onlyTheMainWebViewsMainFrameOnTheDaemonsOriginIsHeard() {
        // The same rule as the tab menu's: a pop-up shares the script and can be someone else's page.
        #expect(TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: false, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: false, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: false))
    }

    // MARK: How long a pick is fresh

    private let start = ContinuousClock.now
    private let pick = ConversationPick(kind: .image, version: ConversationMenuTests.version, name: "Figure")

    @Test func aPickIsFreshForASecondAndTakenOnce() {
        var target = ConversationTarget()
        target.record(pick, at: start)
        #expect(target.take(at: start + .milliseconds(999)) == pick)
        #expect(target.take(at: start + .milliseconds(1000)) == nil)
        target.record(pick, at: start)
        #expect(target.take(at: start + .seconds(1)) == pick)
    }

    @Test func aStaleOrMissingPickIsNeverUsed() {
        var target = ConversationTarget()
        target.record(pick, at: start)
        #expect(target.take(at: start + .milliseconds(1001)) == nil)
        #expect(target.take(at: start + .milliseconds(10)) == nil)
        var empty = ConversationTarget()
        #expect(empty.take(at: start) == nil)
        // A clock that went backwards is not trusted.
        var backwards = ConversationTarget()
        backwards.record(pick, at: start + .seconds(5))
        #expect(backwards.take(at: start) == nil)
    }

    @Test func aRightClickOnNothingClearsTheLastPick() {
        var target = ConversationTarget()
        target.record(pick, at: start)
        target.record(nil, at: start)
        #expect(target.take(at: start) == nil)
    }

    // MARK: The items

    private func menu(_ titles: String...) -> NSMenu {
        let menu = NSMenu()
        for title in titles {
            menu.addItem(title == "-" ? .separator() : NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        return menu
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private let shelfGroup = ["Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "-", "Show in Results"]

    @Test func theItemsFollowTheBoardsMenu() {
        // WebKit's figure items, a separator, then Capsid's group, a separator, WebKit's rest.
        let figure = menu("Open Image in New Window", "Copy Image", "-", "Inspect Element")
        ConversationMenu.insertItems(into: figure, for: pick, run: { _, _ in })
        #expect(titles(figure) == ["Open Image in New Window", "Copy Image", "-"] + shelfGroup + ["-", "Inspect Element"])
    }

    @Test func aMenuWithNoSeparatorGetsTheGroupAtItsEnd() {
        let link = menu("Open Link", "Copy Link")
        ConversationMenu.insertItems(into: link, for: pick, run: { _, _ in })
        #expect(titles(link) == ["Open Link", "Copy Link", "-"] + shelfGroup)
        let empty = NSMenu()
        ConversationMenu.insertItems(into: empty, for: pick, run: { _, _ in })
        #expect(titles(empty) == shelfGroup)
    }

    @Test func aSeparatorAtTheEndNeedsNoSecondOne() {
        let ends = menu("Copy Image", "-")
        ConversationMenu.insertItems(into: ends, for: pick, run: { _, _ in })
        #expect(titles(ends) == ["Copy Image", "-"] + shelfGroup)
        let starts = menu("-", "Inspect Element")
        ConversationMenu.insertItems(into: starts, for: pick, run: { _, _ in })
        #expect(titles(starts) == shelfGroup + ["-", "Inspect Element"])
    }

    @Test func theItemsAreNotAddedTwice() {
        let figure = menu("Copy Image", "-", "Inspect Element")
        ConversationMenu.insertItems(into: figure, for: pick, run: { _, _ in })
        let once = titles(figure)
        ConversationMenu.insertItems(into: figure, for: pick, run: { _, _ in })
        #expect(titles(figure) == once)
    }

    @Test func addToShelfShowsItsKeyAndTheOthersShowNone() {
        let figure = menu("Copy Image")
        ConversationMenu.insertItems(into: figure, for: pick, run: { _, _ in })
        let add = figure.items.first { $0.title == "Add to Shelf" }
        #expect(add?.keyEquivalent == "s")
        #expect(add?.keyEquivalentModifierMask == [.command, .option])
        for item in figure.items where item.title != "Add to Shelf" && !item.isSeparatorItem && item.title != "Copy Image" {
            #expect(item.keyEquivalent.isEmpty, "\(item.title)")
        }
    }

    @Test func eachItemRunsItsOwnActionOnThePick() {
        var ran: [String] = []
        let figure = menu("Copy Image")
        ConversationMenu.insertItems(into: figure, for: pick, run: { action, picked in
            ran.append("\(action.title)|\(picked.version)")
        })
        for item in figure.items where item.identifier == ConversationMenu.itemID && !item.isSeparatorItem {
            _ = item.target?.perform(item.action, with: item)
        }
        #expect(ran == ["Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results"]
            .map { "\($0)|\(Self.version)" })
    }

    // MARK: When the items appear

    private func clickedMenu(on pick: ConversationPick?, at offset: Duration) -> NSMenu {
        var now = start
        let shelfMenu = ConversationMenu(now: { now }, daemonPort: { Self.port }, run: { _, _ in })
        shelfMenu.record(pick)
        now = start + offset
        let figure = menu("Copy", "Inspect Element")
        shelfMenu.addItems(to: figure)
        return figure
    }

    @Test func aFreshPickAddsTheItems() {
        // No separator in this made-up menu: the group goes at its end.
        #expect(titles(clickedMenu(on: pick, at: .milliseconds(300))) == ["Copy", "Inspect Element", "-"] + shelfGroup)
    }

    @Test func aStaleOrMissingPickAddsNothing() {
        #expect(titles(clickedMenu(on: pick, at: .seconds(3))) == ["Copy", "Inspect Element"])
        #expect(titles(clickedMenu(on: nil, at: .milliseconds(10))) == ["Copy", "Inspect Element"])
    }

    // MARK: The user script

    /// A tiny page: elements with a tag, a few properties and a parent, and
    /// `closest` that knows the one selector the script asks.
    private static let page = #"""
    var __posted = [];
    var location = { protocol: "http:", hostname: "localhost" };
    var window = { webkit: { messageHandlers: { capsidShelfMenu: { postMessage: function (m) { __posted.push(JSON.stringify(m)); } } } } };
    var document = { listeners: [], addEventListener: function (type, fn, capture) { this.listeners.push({ type: type, fn: fn, capture: capture }); } };
    function El(tag, props, parent) {
      this.tagName = tag; this.nodeType = 1; this.parentElement = parent || null;
      for (var key in props) { this[key] = props[key]; }
    }
    El.prototype.closest = function (selector) {
      if (selector !== "img, a[href]") { throw new Error("unexpected selector " + selector); }
      for (var node = this; node; node = node.parentElement) {
        var tag = String(node.tagName).toLowerCase();
        if (tag === "img" || (tag === "a" && node.href)) { return node; }
      }
      return null;
    };
    function __fire(target, trusted) {
      document.listeners.forEach(function (l) {
        if (l.type === "contextmenu") { l.fn({ type: "contextmenu", target: target, isTrusted: trusted !== false }); }
      });
    }
    var __body = new El("BODY", {});
    var __link = new El("A", { href: "http://localhost:8123/api/artifacts/versions/V", textContent: "qc_notes.md", title: "" }, __body);
    var __inLink = new El("SPAN", {}, __link);
    var __img = new El("IMG", { currentSrc: "http://localhost:8123/api/artifacts/versions/V?thumbnail=800", src: "http://localhost:8123/x", alt: "Z prime by plate", title: "" }, __body);
    var __imgInLink = new El("IMG", { currentSrc: "", src: "http://localhost:8123/api/artifacts/versions/V", alt: "", title: "A plot" }, __link);
    var __bare = new El("A", { textContent: "no address" }, __body);
    var __text = { nodeType: 3, parentElement: __link };
    """#

    private func listener(protocolName: String = "http:", host: String = "localhost", withHandler: Bool = true) -> PageScript {
        let script = PageScript(Self.page.replacingOccurrences(of: "V", with: Self.version))
        if protocolName != "http:" || host != "localhost" {
            script.evaluate("location.protocol = \"\(protocolName)\"; location.hostname = \"\(host)\";")
        }
        if !withHandler { script.evaluate("window = {};") }
        script.evaluate(ConversationMenu.script)
        return script
    }

    private func posted(_ script: PageScript) -> [[String: Any]] {
        let text = script.evaluate("'[' + __posted.join(',') + ']'") ?? "[]"
        return ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]]) ?? []
    }

    @Test func itListensForContextMenusInTheCapturePhase() {
        let script = listener()
        #expect(script.evaluate("document.listeners.map(function (l) { return l.type + ':' + l.capture; }).join(',')") == "contextmenu:true")
        #expect(script.exception == nil)
    }

    @Test func aRightClickOnAFigureNamesItsAddressAndAlt() {
        let script = listener()
        script.evaluate("__fire(__img)")
        let sent = posted(script)
        #expect(sent.count == 1)
        #expect(sent.first?["kind"] as? String == "image")
        #expect(sent.first?["url"] as? String == Self.address + "?thumbnail=800")
        #expect(sent.first?["name"] as? String == "Z prime by plate")
        #expect(script.exception == nil)
    }

    @Test func aFigureWithNoCurrentSourceUsesItsSrcAndTitle() {
        let script = listener()
        script.evaluate("__fire(__imgInLink)")
        let sent = posted(script)
        // The picture, not the link around it.
        #expect(sent.first?["kind"] as? String == "image")
        #expect(sent.first?["url"] as? String == Self.address)
        #expect(sent.first?["name"] as? String == "A plot")
    }

    @Test func aRightClickOnALinkOrItsTextNamesTheLink() {
        let script = listener()
        script.evaluate("__fire(__link)")
        script.evaluate("__fire(__inLink)")
        script.evaluate("__fire(__text)")
        let sent = posted(script)
        #expect(sent.count == 3)
        for message in sent {
            #expect(message["kind"] as? String == "link")
            #expect(message["url"] as? String == Self.address)
            #expect(message["name"] as? String == "qc_notes.md")
        }
    }

    @Test func aRightClickAnywhereElseSaysNone() {
        let script = listener()
        script.evaluate("__fire(__body)")
        script.evaluate("__fire(__bare)")
        script.evaluate("__fire({ nodeType: 3, parentElement: null })")
        script.evaluate("__fire(null)")
        let sent = posted(script)
        #expect(sent.count == 4)
        for message in sent { #expect(message["kind"] is NSNull) }
        #expect(script.exception == nil)
    }

    @Test func aMadeUpEventIsIgnored() {
        let script = listener()
        script.evaluate("__fire(__img, false)")
        #expect(posted(script).isEmpty)
    }

    @Test func itDoesNothingOutsideTheDaemonsPageOrWithoutItsHandler() {
        #expect(listener(host: "example.com").evaluate("String(document.listeners.length)") == "0")
        #expect(listener(protocolName: "https:").evaluate("String(document.listeners.length)") == "0")
        #expect(listener(withHandler: false).evaluate("String(document.listeners.length)") == "0")
        #expect(listener(host: "127.0.0.1").evaluate("String(document.listeners.length)") == "1")
    }

    @Test func theScriptNamesItsHandlerAndOnlyReadsProperties() {
        // The handler the page script posts to is the one Swift installs.
        #expect(ConversationMenu.script.contains("messageHandlers.\(ConversationMenu.handlerName)"))
        // One selector, so the inventory holds one hook for it (CompatInventoryTests).
        #expect(!ConversationMenu.script.contains("getAttribute"))
        #expect(!ConversationMenu.script.contains("querySelector"))
        #expect(!ConversationMenu.script.contains("fetch("))
    }
}
