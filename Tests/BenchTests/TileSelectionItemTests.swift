// TileSelectionItemTests.swift — "Add Selection to Shelf" in the page's own
// menu for a Markdown or text tile (since 1.0.6; Shelf/ConversationMenu.swift).
// The script half runs in JavaScriptCore against the made-up page
// (FakeFigurePage): the item comes first in Capsid's group only for a
// passage selected wholly inside the tile's preview region and left alone by
// the right-click, and for nothing else; a click on it puts the selection back,
// keeps the words in the script's own world for the one read and posts the
// count, never the words. The Swift half runs on made-up menus, sessions and a
// made-up shelf: the message, the sender checks and that choosing it saves the
// note by the same call as the Mac's item. How it looks in a real WebKit view is
// FigureMenuSnapshotTests; the real page's own menu is only checked by a real
// right-click (TESTING.md).
import AppKit
import Foundation
import Testing
@testable import Bench

struct TileSelectionScriptTests {
    static let version = ShelfAddressTests.version
    static let words = FigureMenuScriptTests.words
    static let passage = DocumentTileScriptTests.passage
    static let item = "Add Selection to Shelf"
    /// What a menu holding Capsid's group looks like for a passage in a tile: the item first.
    static let grouped = ["page:Copy image", "page:Open in split view", "rule", "ours:" + item] + words.map { "ours:" + $0 }
    static let plain = ["page:Copy image", "page:Open in split view"]

    private func page(path: String? = nil) -> PageScript {
        let script = PageScript()
        script.set("__VERSION", Self.version)
        script.set("__MENU", FakeFigurePage.menuClass)
        script.set("__ITEM", FakeFigurePage.itemClass)
        script.set("__DANGER", FakeFigurePage.dangerClass)
        script.set("__RULE", FakeFigurePage.ruleClass)
        script.set("__WORDS", Self.passage)
        script.evaluate(FakeFigurePage.source)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        if let path { script.set("__PATH", path); script.evaluate("location.pathname = __PATH;") }
        script.evaluate(ConversationMenu.script)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        return script
    }

    private func json(_ script: PageScript, _ expression: String) -> Any? {
        let text = script.evaluate("JSON.stringify(\(expression))") ?? "null"
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    private func posted(_ script: PageScript) -> [[String: Any]] {
        ((json(script, "__posted") as? [[String: Any]]) ?? []).filter { $0["trace"] == nil }
    }

    private func traces(_ script: PageScript) -> [[String]] {
        ((json(script, "__posted") as? [[String: Any]]) ?? []).compactMap { $0["trace"] as? [String] }
    }

    private func shape(_ script: PageScript) -> [String] {
        (json(script, "__shape()") as? [String]) ?? []
    }

    private func held(_ script: PageScript) -> String? {
        json(script, "window.capsidHeldSelection") as? String
    }

    // MARK: When the item appears

    @Test(arguments: [
        ("the tile's words", "__docText"),
        ("its preview region", "__docBody"),
        ("a link out in its words", "__docLink"),
    ])
    func aPassageSelectedInTheTileAndRightClickedThereGetsTheItemFirstInCapsidsGroup(_ place: String, _ target: String) {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(\(target))")
        script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
        #expect(shape(script) == Self.grouped, "\(place)")
        #expect(script.exception == nil, "\(place): \(script.exception ?? "")")
    }

    @Test func theItemComesAfterThePagesItemsAndAboveTheRedOneWhichStaysLast() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText)")
        script.evaluate("__openMenu(['Open in split view', 'Copy link', '-', '!Delete'])")
        let menu = shape(script)
        #expect(menu == ["page:Open in split view", "page:Copy link", "rule", "ours:" + Self.item]
                + Self.words.map { "ours:" + $0 } + ["page-rule", "page:Delete"])
    }

    @Test func theItemIsDrawnWithTheMenusOwnItemClassesAndAnIconBox() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        #expect(script.evaluate("__ours()[1].className") == FakeFigurePage.itemClass)
        #expect(script.evaluate("__ours()[1].attrs.role") == "menuitem")
        #expect(script.evaluate("String(__ours()[1].children.length)") == "1", "its icon box, as the others have")
        // The page's own words are never read.
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func theTraceSaysTheItemWasOffered() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        #expect(traces(script) == [["contextmenu", "figure-document", "menu-matched", "selection-offered", "placed"]])
        for trace in traces(script) {
            #expect(ConversationMenuMessage.trace(in: ["trace": trace])?.map(\.rawValue) == trace)
        }
    }

    // MARK: When it does not

    @Test func noSelectionNoItem() {
        let script = page()
        script.evaluate("__rightClick(__docText); __openMenu();")
        #expect(shape(script) == DocumentTileScriptTests.grouped)
        let blanks = page()
        blanks.evaluate("__select(' \\n\\t ', __docText); __rightClick(__docText); __openMenu();")
        #expect(shape(blanks) == DocumentTileScriptTests.grouped)
    }

    @Test(arguments: [
        ("a reply's words", "__paragraph"),
        ("the tile's own header", "__docName"),
        ("a card's words in the tray", "__captionText2"),
        ("another header of the page", "__pageTitle"),
    ])
    func aSelectionOutsideTheTilesBodyGetsNoItemEvenOnATile(_ place: String, _ node: String) {
        // Right-clicked on the tile, but the passage is elsewhere: it is not the tile's.
        let script = page()
        script.evaluate("__select(__WORDS, \(node)); __rightClick(__docText)")
        script.evaluate("__openMenu()")
        #expect(shape(script) == DocumentTileScriptTests.grouped, "\(place)")
        #expect(!(traces(script).last ?? []).contains("selection-offered"), "\(place)")
    }

    @Test func aSelectionThatLeavesTheTileAtEitherEndGetsNoItem() {
        let anchor = page()
        anchor.evaluate("__select(__WORDS, __paragraph, __docText); __rightClick(__docText); __openMenu();")
        #expect(shape(anchor) == DocumentTileScriptTests.grouped, "it starts outside")
        let focus = page()
        focus.evaluate("__select(__WORDS, __docText, __paragraph); __rightClick(__docText); __openMenu();")
        #expect(shape(focus) == DocumentTileScriptTests.grouped, "it ends outside")
    }

    @Test func aSelectionWithNoPlaceInThePageGetsNoItem() {
        // The browser says no node for the selection's ends: nothing is known to be inside.
        let script = page()
        script.evaluate("__select(__WORDS, null); __rightClick(__docText); __openMenu();")
        #expect(shape(script) == DocumentTileScriptTests.grouped)
    }

    @Test func aSelectionInATrayCardOrOnAFigureGetsNoItem() {
        // A card has no body of words; a figure's menu is not a tile's.
        let card = page()
        card.evaluate("__select(__WORDS, __previewText2); __rightClick(__previewText2); __openMenu();")
        #expect(shape(card) == DocumentTileScriptTests.grouped)
        let figure = page()
        figure.evaluate("__select(__WORDS, __docText); __rightClick(__tileImg, { under: [__layer, __tileImg, __tileBox, __tile] }); __openMenu();")
        #expect(shape(figure) == FigureMenuScriptTests.grouped)
    }

    @Test func aSelectionTheRightClickChangedGetsNoItem() {
        // WebKit selects the word under the pointer when the click lands outside the passage.
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText, { word: 'plate' })")
        script.evaluate("__openMenu()")
        #expect(shape(script) == DocumentTileScriptTests.grouped)
        #expect(posted(script).first?["selected"] == nil)
    }

    @Test func aSelectionThatChangedBetweenTheRightClickAndTheMenuGetsNoItem() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __select('Plate', __docText);")
        script.evaluate("__openMenu()")
        #expect(shape(script) == DocumentTileScriptTests.grouped)
    }

    @Test func aMenuAskedForByTheKeyboardWithNoButtonGetsNoItem() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText, { down: false }); __openMenu();")
        #expect(shape(script) == DocumentTileScriptTests.grouped)
    }

    @Test(arguments: ["/", "/projects/p1", "/settings", "/projects/p1/frames/short"])
    func nothingIsOfferedOnAPageThatIsNotASession(_ path: String) {
        let script = page(path: path)
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        #expect(shape(script) == Self.plain, "\(path)")
    }

    // MARK: Untrusted events

    @Test func aRightClickTheBrowserDidNotMakeOffersNothing() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText, { trusted: false }); __openMenu();")
        #expect(shape(script) == Self.plain)
        #expect(posted(script).isEmpty)
    }

    @Test func aButtonPressTheBrowserDidNotMakeKeepsNothingSoThereIsNoItem() {
        // The contextmenu is real, the mouse-down was made up: nothing was kept at the button, so nothing is a passage.
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText, { downTrusted: false }); __openMenu();")
        #expect(shape(script) == DocumentTileScriptTests.grouped)
        #expect(posted(script).first?["selected"] == nil)
    }

    @Test func aClickThePageMadeUpOnTheItemDoesNothing() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        script.evaluate("__click(__ours()[1], false)")
        #expect(posted(script).allSatisfy { $0["action"] == nil }, "nothing was chosen")
        #expect(held(script) == nil, "and no words were kept")
        #expect(script.evaluate("String(__menu !== null)") == "true")
        #expect(shape(script) == Self.grouped)
        script.evaluate("__click(__ours()[1])")
        #expect(posted(script).last?["action"] as? String == "addSelection")
    }

    @Test func aMouseDownTheBrowserDidNotMakeDoesNotDropTheKeptWords() {
        // Only a real press ends what an earlier choice kept; a made-up one is not heard.
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[1]);")
        #expect(held(script) == Self.passage)
        script.evaluate("var __made = new __Event('mousedown', { bubbles: true, button: 2 }); __dispatch(__page, __made);")
        #expect(held(script) == Self.passage)
    }

    // MARK: Choosing it

    @Test func choosingItPostsTheCountAndNeverTheWordsAndClosesThePagesMenu() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); var __e = __click(__ours()[1]);")
        let sent = posted(script).last
        #expect(sent?["action"] as? String == "addSelection")
        #expect(sent?["selected"] as? Int == Self.passage.count)
        #expect(Set(sent?.keys.map { $0 } ?? []) == ["action", "selected"], "no name, no version, no address, no words")
        let everything = script.evaluate("JSON.stringify(__posted)") ?? ""
        #expect(!everything.contains("drifts") && !everything.contains("midpoint"))
        #expect(script.evaluate("String(__menu === null)") == "true")
        #expect(script.evaluate("String(__watching())") == "0")
        #expect(script.evaluate("String(__e.defaultPrevented)") == "true")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func theMessageIsOneTheMessageParserReadsAndNoOtherReading() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[1]);")
        let sent = posted(script).last
        #expect(ConversationMenuMessage.selectionChoice(in: sent) == Self.passage.count)
        #expect(ConversationMenuMessage.choice(in: sent) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: sent) == nil)
        #expect(ConversationMenuMessage.selection(in: sent) == Self.passage.count, "the count key is the one the Mac path reads too")
    }

    @Test func theOtherFourItemsStillPostTheirOwnMessagesWithAPassageSelected() {
        for (index, action) in FigureMenuScriptTests.actions.enumerated() {
            let script = page()
            script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[\(index + 2)]);")
            let sent = posted(script).last
            #expect(sent?["action"] as? String == action)
            #expect(sent?["kind"] as? String == "document")
            #expect(sent?["name"] as? String == "plan_notes.md")
            #expect(held(script) == nil, "\(action): no words are kept for another item")
        }
    }

    @Test func aPressOnTheItemDoesNotTakeTheSelectionAwayAndAPressOnAnotherDoes() {
        // The browser takes the selection from the press of a button unless the press is cancelled.
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        script.evaluate("var __d = __press(__ours()[1]);")
        #expect(script.evaluate("String(__d.defaultPrevented)") == "true")
        #expect(script.evaluate("__selected") == Self.passage)
        script.evaluate("var __o = __press(__ours()[2]);")
        #expect(script.evaluate("String(__o.defaultPrevented)") == "false")
    }

    @Test func aSelectionTheClickCollapsedIsPutBackAndItsWordsAreKeptForTheRead() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        // Whatever happened to it between the right-click and the click (the page took focus, a re-render).
        script.evaluate("__select('', null)")
        script.evaluate("__click(__ours()[1])")
        #expect(script.evaluate("__selected") == Self.passage, "put back from the range taken at the button")
        #expect(script.evaluate("String(__selectedIn === __docText)") == "true")
        #expect(held(script) == Self.passage)
        #expect(posted(script).last?["action"] as? String == "addSelection")
    }

    @Test func aSelectionThatIsStillThereIsLeftAlone() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu();")
        script.evaluate("var __ranges = 0; var __was = __selection.addRange; __selection.addRange = function (r) { __ranges++; __was(r); };")
        script.evaluate("__click(__ours()[1])")
        #expect(script.evaluate("String(__ranges)") == "0")
        #expect(held(script) == Self.passage)
    }

    @Test func theKeptWordsGoWhenAnythingElseIsPressedOrTheTimeIsUp() {
        let timed = page()
        timed.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[1]);")
        #expect(held(timed) == Self.passage)
        timed.evaluate("__advance(9_999)")
        #expect(held(timed) == Self.passage)
        timed.evaluate("__advance(2)")
        #expect(held(timed) == nil, "after ten seconds")
        let pressed = page()
        pressed.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[1]);")
        pressed.evaluate("__press(__page)")
        #expect(held(pressed) == nil, "a later press")
        let again = page()
        again.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[1]);")
        again.evaluate("__closeMenu(); __select('x', __docText); __rightClick(__docText, { down: false })")
        #expect(held(again) == nil, "a later right-click")
    }

    @Test func nothingIsLeftRunningOnceTheKeptWordsAreGone() {
        let script = page()
        script.evaluate("__select(__WORDS, __docText); __rightClick(__docText); __openMenu(); __click(__ours()[1]);")
        script.evaluate("__advance(10_500)")
        #expect(script.evaluate("String(__liveTimers())") == "0")
        #expect(script.evaluate("String(__watching())") == "0")
    }

    @Test func theScriptKeepsTheWordsInItsOwnWorldAndPostsOnlyTheirCount() {
        let text = ConversationMenu.script
        #expect(text.contains("window.capsidHeldSelection"))
        #expect(text.contains("Array.from(passage.text).length"))
        #expect(!text.contains("selected: passage.text") && !text.contains("selected: view.passage.text"))
        #expect(text.contains(ConversationMenu.selectionTitle))
        #expect(text.contains(ConversationMenuMessage.selectionAction))
    }
}

// MARK: The words, as Swift reads them

struct SelectedWordsReadTests {
    private func read(held: String?, live: String, limit: Int = 32_000) -> String? {
        let script = PageScript()
        script.set("__LIVE", live)
        script.evaluate("var window = { getSelection: function () { return { toString: function () { return __LIVE; } }; } };")
        if let held {
            script.set("__HELD", held)
            script.evaluate("window.capsidHeldSelection = __HELD;")
        }
        let run = script.runPage(SelectedWordsScript.read, arguments: [("limit", String(limit))], answers: [:])
        let after = script.evaluate("String(window.capsidHeldSelection)")
        #expect(held == nil || after == "null", "the kept words are used once")
        return run.result
    }

    @Test func theKeptWordsAreReadInPlaceOfTheLiveSelectionAndOnlyOnce() {
        let script = PageScript()
        script.set("__LIVE", "")
        script.set("__HELD", DocumentTileScriptTests.passage)
        script.evaluate("var window = { capsidHeldSelection: __HELD, getSelection: function () { return { toString: function () { return __LIVE; } }; } };")
        let first = script.runPage(SelectedWordsScript.read, arguments: [("limit", "32000")], answers: [:])
        #expect(first.result == DocumentTileScriptTests.passage)
        let second = script.runPage(SelectedWordsScript.read, arguments: [("limit", "32000")], answers: [:])
        #expect(second.result == "", "nothing selected and nothing kept")
    }

    @Test func withNothingKeptTheLiveSelectionIsRead() {
        #expect(read(held: nil, live: "Plate 7 drifts") == "Plate 7 drifts")
        #expect(read(held: nil, live: "") == "")
    }

    @Test func theKeptWordsWinOverADifferentLiveSelection() {
        #expect(read(held: "Plate 7 drifts", live: "plate") == "Plate 7 drifts")
    }

    @Test func theLimitCutsTheKeptWordsAsItCutsTheLiveOnes() {
        #expect(read(held: "Plate 7 drifts", live: "", limit: 7) == "Plate 7")
        #expect(read(held: nil, live: "Plate 7 drifts", limit: 7) == "Plate 7")
    }
}

// MARK: What Swift does with the message

@MainActor
struct TileSelectionChoiceTests {
    static let start = ContinuousClock.Instant.now
    static let message: [String: Any] = ["action": "addSelection", "selected": 62]

    private func menu(onSession: Bool = true, shelve: @escaping @MainActor () -> Void,
                      ran: @escaping @MainActor (ConversationAction, ConversationPick) -> Void = { _, _ in }) -> ConversationMenu {
        ConversationMenu(now: { Self.start }, daemonPort: { 8123 }, breadcrumbs: CompatBreadcrumbs(), traced: { _ in },
                         isSession: { onSession }, shelveSelection: shelve, run: ran)
    }

    @Test func theMessageNamesAPassageByItsCount() {
        #expect(ConversationMenuMessage.selectionChoice(in: Self.message) == 62)
        #expect(ConversationMenuMessage.selectionAction == "addSelection")
        #expect(ConversationAction(rawValue: "addSelection") == nil, "it is not one of the four")
    }

    @Test func anythingElseIsNoChoiceOfIt() {
        let nothing: [Any?] = [
            nil, 62, ["action": "addSelection"], ["action": "addSelection", "selected": 0], ["action": "addSelection", "selected": -1],
            ["action": "addSelection", "selected": "62"], ["action": "addSelection", "selected": NSNull()],
            ["action": "addselection", "selected": 62], ["action": "keep", "selected": 62], ["selected": 62],
            ["action": "addSelection", "selected": 62, "version": ShelfAddressTests.version],
        ]
        for body in nothing { #expect(ConversationMenuMessage.selectionChoice(in: body) == nil, "\(String(describing: body))") }
        // A count on a pick is the Mac's, and is no choice.
        #expect(ConversationMenuMessage.selectionChoice(in: ["kind": NSNull(), "selected": 62]) == nil)
    }

    @Test func aChoiceFromThePageShelvesTheSelectionAtOnce() {
        var shelved = 0
        menu(shelve: { shelved += 1 }).hear(Self.message, accepted: true)
        #expect(shelved == 1)
    }

    @Test func aChoiceFromAnyoneElseIsNothing() {
        var shelved = 0
        let shelf = menu(shelve: { shelved += 1 })
        shelf.hear(Self.message, accepted: false)
        shelf.hear(["action": "addSelection", "selected": 0], accepted: true)
        shelf.hear(["action": "addSelection"], accepted: true)
        #expect(shelved == 0)
    }

    @Test func notOnASessionsPageNothingIsShelved() {
        var shelved = 0
        menu(onSession: false, shelve: { shelved += 1 }).hear(Self.message, accepted: true)
        #expect(shelved == 0)
    }

    @Test func aChoiceRunsNoFileActionAndKeepsThePickForTheMacsMenu() {
        // The page's menu can be open longer than a second; the Mac's menu is a second way in.
        var ran = 0, shelved = 0
        let shelf = menu(shelve: { shelved += 1 }, ran: { _, _ in ran += 1 })
        let pick = ConversationPick(kind: .image, version: ShelfAddressTests.version, name: "Figure")
        shelf.record(pick, selected: 62)
        shelf.hear(Self.message, accepted: true)
        #expect(ran == 0 && shelved == 1)
        let mac = NSMenu()
        mac.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))
        shelf.addItems(to: mac)
        #expect(mac.items.contains { $0.identifier == ConversationMenu.itemID }, "the pick is still there")
    }

    // MARK: Saving the note

    /// The menu and the shelf wired as the app wires them: the message ends in `ConversationShelf.shelveSelection`.
    private func wired(words: String?) -> (ConversationMenu, MadeNotes, ShelfToastModel, WireBox) {
        let notes = MadeNotes()
        let toast = ShelfToastModel(shelf: notes.access, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, announce: { _ in })
        let shelf = ConversationShelf(dependencies: .init(
            route: { ConversationShelfTests.route },
            session: { _ in ShelfSelectionActionTests.session },
            facts: { _ in nil },
            shelf: notes.access, toast: toast,
            keep: { _ in }, reference: { _, _ in }, results: { _ in },
            selection: { _ in words }))
        let box = WireBox()
        let menu = ConversationMenu(now: { Self.start }, daemonPort: { 8123 }, breadcrumbs: CompatBreadcrumbs(), traced: { _ in },
                                    isSession: { true }, shelveSelection: { box.task = Task { await shelf.shelveSelection() } }, run: { _, _ in })
        return (menu, notes, toast, box)
    }

    final class WireBox { var task: Task<Void, Never>? }

    @Test func choosingItSavesTheNoteForTheSessionWithTheSameToastAsTheMacsItem() async {
        let (menu, notes, toast, box) = wired(words: "  Plate 7 drifts after the midpoint.\n")
        menu.hear(Self.message, accepted: true)
        await box.task?.value
        #expect(notes.notes == [ShelfSelectionNote(session: ShelfSelectionActionTests.session, text: "Plate 7 drifts after the midpoint.")])
        #expect(toast.state == .added(MadeShelf.placement("Plate 7 drifts after the midpoint")))
    }

    @Test func choosingItWhenTheWordsAreGoneSaysSoAndSavesNothing() async {
        let (menu, notes, toast, box) = wired(words: nil)
        menu.hear(Self.message, accepted: true)
        await box.task?.value
        #expect(notes.notes.isEmpty)
        #expect(toast.state == .failed(ShelfSelectionNote.nothingSelected))
    }

    @Test func theMacsItemAndThePagesItemEndInTheSameCall() throws {
        // Both are the one closure the web view gives the menu; the wiring is read, as for the Mac's item.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let container = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Web/WebContainer.swift"), encoding: .utf8)
        #expect(container.components(separatedBy: "ConversationShelf.shared.shelveSelection()").count == 2, "one entry point")
        let menu = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Shelf/ConversationMenu.swift"), encoding: .utf8)
        #expect(menu.components(separatedBy: "shelveSelection()").count >= 3)
    }
}
