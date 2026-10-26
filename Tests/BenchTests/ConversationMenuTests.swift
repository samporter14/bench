// ConversationMenuTests.swift — the Shelf items in the right-click menu of a
// figure or a file link (Shelf/ConversationMenu.swift), on made-up menus: how
// the page script's messages are read (a pick for the Mac's menu, a choice
// made in the page's own menu, a miss), how long a pick is fresh, the items
// put into an NSMenu and only when the click was on an artifact's figure or
// link, and what each item does — over a made-up shelf, session and toast, with
// nothing sent to Claude Science. The script itself is run in
// FigureMenuScriptTests. WebKit's own ordering of message and menu, and the
// menu as drawn, are checked by eye (TESTING.md).
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

    // MARK: Choosing in the page's own menu

    private func shelfMenu(accepting: Bool = true, port: Int? = ConversationMenuTests.port,
                           breadcrumbs: CompatBreadcrumbs = CompatBreadcrumbs(),
                           traced: @escaping @MainActor (String) -> Void = { _ in },
                           ran: @escaping @MainActor (ConversationAction, ConversationPick) -> Void)
        -> ConversationMenu {
        ConversationMenu(now: { self.start }, daemonPort: { port }, breadcrumbs: breadcrumbs, traced: traced, run: ran)
    }

    @Test func theActionsHaveTheWordsTheScriptPosts() {
        #expect(ConversationAction.allCases.map(\.rawValue) == ["addToShelf", "keep", "openAsReference", "showInResults"])
        for action in ConversationAction.allCases { #expect(ConversationAction(rawValue: action.rawValue) == action) }
        #expect(ConversationAction(rawValue: "delete") == nil)
    }

    @Test func aChoiceNamesTheActionAndTheFigure() {
        let choice = ConversationMenuMessage.choice(in: ["action": "keep", "version": Self.version, "name": "Z prime by plate", "kind": "image"])
        #expect(choice == ConversationMenuMessage.Choice(
            action: .keep, pick: ConversationPick(kind: .image, version: Self.version, name: "Z prime by plate")))
        let link = ConversationMenuMessage.choice(in: ["action": "showInResults", "version": Self.version, "name": "qc_notes.md", "kind": "link"])
        #expect(link?.pick == ConversationPick(kind: .link, version: Self.version, name: "qc_notes.md"))
        // The page's menu is a figure's: no kind is an image, a word that isn't one too.
        #expect(ConversationMenuMessage.choice(in: ["action": "addToShelf", "version": Self.version, "name": "x"])?.pick.kind == .image)
        #expect(ConversationMenuMessage.choice(in: ["action": "addToShelf", "version": Self.version, "kind": "video"])?.pick.kind == .image)
        for action in ConversationAction.allCases {
            #expect(ConversationMenuMessage.choice(in: ["action": action.rawValue, "version": Self.version])?.action == action)
        }
    }

    @Test func aChoiceWithoutAWordForItsNameGetsANounAndALongNameIsCut() {
        #expect(ConversationMenuMessage.choice(in: ["action": "keep", "version": Self.version])?.pick.name == "Figure")
        #expect(ConversationMenuMessage.choice(in: ["action": "keep", "version": Self.version, "name": "", "kind": "link"])?.pick.name == "File")
        let long = String(repeating: "n", count: ConversationMenuMessage.maxName * 3)
        #expect(ConversationMenuMessage.choice(in: ["action": "keep", "version": Self.version, "name": long])?.pick.name.count == HistoryFile.nameLimit)
    }

    @Test func anythingElseIsNoChoice() {
        let v = Self.version
        #expect(ConversationMenuMessage.choice(in: nil) == nil)
        #expect(ConversationMenuMessage.choice(in: v) == nil)
        #expect(ConversationMenuMessage.choice(in: ["version": v]) == nil)
        #expect(ConversationMenuMessage.choice(in: ["action": "keep"]) == nil)
        #expect(ConversationMenuMessage.choice(in: ["action": 3, "version": v]) == nil)
        #expect(ConversationMenuMessage.choice(in: ["action": "keep", "version": 3]) == nil)
        // An action Capsid doesn't have, however it is spelt.
        for word in ["delete", "Keep", "add", "addtoshelf", "", "keep ", "Add to Shelf"] {
            #expect(ConversationMenuMessage.choice(in: ["action": word, "version": v]) == nil, "\(word)")
        }
        // A version that is not a full id as the daemon writes it: the script
        // could only have found one in an address, and Swift takes nothing else.
        for version in ["", "short", String(v.dropLast()), v + "0", v.uppercased(), "../" + String(v.dropFirst(3)),
                        "\(v.prefix(35))/", "1c8d3a5f 2b3c 4d4e 9f00 b1c2d3e4f5a6", "\(v.prefix(35))\u{0}"] {
            #expect(ConversationMenuMessage.choice(in: ["action": "keep", "version": version]) == nil, "\(version)")
        }
        // A pick message is not a choice, nor a choice a pick.
        #expect(ConversationMenuMessage.choice(in: ["kind": "image", "url": Self.address, "name": "x"]) == nil)
        #expect(ConversationMenuMessage.pick(in: ["action": "keep", "version": v], daemonPort: Self.port) == nil)
    }

    @Test func anUnplacedMessageIsOnlyThatExactly() {
        #expect(ConversationMenuMessage.isUnplaced(["unplaced": true]))
        #expect(!ConversationMenuMessage.isUnplaced(["unplaced": false]))
        #expect(!ConversationMenuMessage.isUnplaced(["unplaced": 1]))
        #expect(!ConversationMenuMessage.isUnplaced(["unplaced": "true"]))
        #expect(!ConversationMenuMessage.isUnplaced(["kind": NSNull()]))
        #expect(!ConversationMenuMessage.isUnplaced(true))
        #expect(!ConversationMenuMessage.isUnplaced(nil))
    }

    @Test func aChoiceFromThePageRunsTheActionOnThePickAtOnce() {
        var ran: [String] = []
        let menu = shelfMenu { action, picked in ran.append("\(action.rawValue)|\(picked.version)|\(picked.name)|\(picked.kind.rawValue)") }
        for action in ConversationAction.allCases {
            menu.hear(["action": action.rawValue, "version": Self.version, "name": "Z prime by plate", "kind": "image"], accepted: true)
        }
        #expect(ran == ConversationAction.allCases.map { "\($0.rawValue)|\(Self.version)|Z prime by plate|image" })
    }

    @Test func aChoiceFromAnyoneElseIsNothing() {
        var ran = 0
        let menu = shelfMenu { _, _ in ran += 1 }
        menu.hear(["action": "keep", "version": Self.version, "name": "x"], accepted: false)
        menu.hear(["action": "nonsense", "version": Self.version], accepted: true)
        menu.hear(["action": "keep", "version": "short"], accepted: true)
        menu.hear(nil, accepted: true)
        #expect(ran == 0)
    }

    @Test func aChoiceDoesNotSpendOrClearThePickForTheMacsMenu() {
        // The Mac's menu is a second way in; the page's menu can be open longer than a second.
        var ran = 0
        let menu = shelfMenu { _, _ in ran += 1 }
        menu.hear(["kind": "image", "url": Self.address, "name": "Figure"], accepted: true)
        menu.hear(["action": "keep", "version": Self.version], accepted: true)
        #expect(ran == 1)
        let figure = self.menu("Copy", "Inspect Element")
        menu.addItems(to: figure)
        #expect(titles(figure).contains("Add to Shelf"))
    }

    @Test func theMessagesTheMacsMenuHearsAreStillHeard() {
        var ran = 0
        let menu = shelfMenu { _, _ in ran += 1 }
        menu.hear(["kind": "image", "url": Self.address, "name": "Z prime by plate"], accepted: true)
        let figure = self.menu("Copy", "Inspect Element")
        menu.addItems(to: figure)
        #expect(titles(figure) == ["Copy", "Inspect Element", "-"] + shelfGroup)
        // A message from anyone else clears the pick, as before.
        menu.hear(["kind": "image", "url": Self.address], accepted: true)
        menu.hear(["kind": "image", "url": Self.address], accepted: false)
        let none = self.menu("Copy")
        menu.addItems(to: none)
        #expect(titles(none) == ["Copy"])
        #expect(ran == 0)
    }

    @Test func anUnplacedMessageLeavesABreadcrumbAndNothingElse() {
        let lines = LoggedLines()
        let store = CompatBreadcrumbs(emit: { lines.add($0) })
        var ran = 0
        let menu = shelfMenu(breadcrumbs: store) { _, _ in ran += 1 }
        menu.hear(["unplaced": true], accepted: false)
        #expect(store.last == nil)
        menu.hear(["unplaced": true], accepted: true)
        #expect(store.last?.miss == .figureMenuNotUnderstood)
        #expect(store.last?.miss.feature == .shelfMenu)
        #expect(lines.all == ["Claude Science may have changed: Add to Shelf from a figure, file link or document tile: the figure menu didn't look as Capsid expects"])
        #expect(ran == 0)
    }

    // MARK: The trace

    @Test func aTraceIsReadAsTheScriptsFixedWordsAndNothingElse() {
        #expect(ConversationMenuMessage.trace(in: ["trace": ["contextmenu", "figure-image", "version-ok", "menu-matched", "placed"]])
                == [.contextmenu, .figureImage, .versionOK, .menuMatched, .placed])
        // A word the script doesn't have, or not a word, is dropped: nothing from the page reaches the log.
        #expect(ConversationMenuMessage.trace(in: ["trace": ["contextmenu", "plate_map.png", 3, NSNull(), "figure-none"] as [Any]])
                == [.contextmenu, .figureNone])
        #expect(ConversationMenuMessage.trace(in: ["trace": [String]()]) == [])
        #expect(ConversationMenuMessage.trace(in: ["trace": Array(repeating: "contextmenu", count: 50)])?.count == ConversationMenuMessage.maxSteps)
        // Other shapes aren't traces.
        #expect(ConversationMenuMessage.trace(in: ["trace": "contextmenu"]) == nil)
        #expect(ConversationMenuMessage.trace(in: ["kind": NSNull()]) == nil)
        #expect(ConversationMenuMessage.trace(in: ["unplaced": true]) == nil)
        #expect(ConversationMenuMessage.trace(in: nil) == nil)
    }

    @Test func aTracesLineIsItsStepsInOrder() {
        #expect(ConversationMenuMessage.line([.contextmenu, .figureLink, .versionNone]) == "Figure menu: contextmenu → figure-link → version-none")
        #expect(ConversationMenuMessage.line([]) == "Figure menu: no steps")
    }

    @Test func aTraceFromThePageIsLoggedAndLeavesThePickForTheMacsMenu() {
        // A plain picture's trace comes right after its pick, before WebKit asks for the Mac's menu.
        var lines: [String] = []
        var ran = 0
        let menu = shelfMenu(traced: { lines.append($0) }) { _, _ in ran += 1 }
        menu.hear(["kind": "image", "url": Self.address, "name": "Figure"], accepted: true)
        menu.hear(["trace": ["contextmenu", "figure-image", "version-ok", "menu-none"]], accepted: true)
        #expect(lines == ["Figure menu: contextmenu → figure-image → version-ok → menu-none"])
        let figure = self.menu("Copy", "Inspect Element")
        menu.addItems(to: figure)
        #expect(titles(figure).contains("Add to Shelf"))
        #expect(ran == 0)
        // From anyone else it is nothing, as every message is, and is not logged.
        menu.hear(["trace": ["contextmenu", "figure-none"]], accepted: false)
        #expect(lines.count == 1)
    }

    @Test func theMainWindowHandsTheMessagesStraightToTheMenusOneEntry() {
        // The web view's message handler is a proxy that calls `hear` once the
        // sender is known; no test builds a script message, so the wiring is read.
        let source = try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/Shelf/ConversationMenu.swift"), encoding: .utf8)
        #expect(source?.contains("hear(message.body, accepted: accepted)") == true)
        #expect(source?.contains("breadcrumbs.record(.figureMenuNotUnderstood)") == true)
    }

    @Test func theScriptNamesItsHandlerAndTheWordsOfTheItems() {
        // The handler the page script posts to is the one Swift installs.
        #expect(ConversationMenu.script.contains("messageHandlers.\(ConversationMenu.handlerName)"))
        #expect(!ConversationMenu.script.contains("__ENTRIES__"))
        for action in ConversationAction.allCases {
            #expect(ConversationMenu.script.contains("\"action\":\"\(action.rawValue)\""), "\(action)")
            #expect(ConversationMenu.script.contains(action.title), "\(action)")
        }
        #expect(!ConversationMenu.script.contains("fetch("))
    }
}

/// The log lines a made-up breadcrumb store emitted.
private final class LoggedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}
