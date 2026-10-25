// DocumentTileScriptTests.swift — the figure-menu script's two newer jobs
// (Shelf/ConversationMenu.swift, the page side), run in JavaScriptCore against
// the made-up page (FakeFigurePage): Capsid's four items in the page's menu for
// a file with no picture, found by the name its tile or card shows, and the
// count of what a right-click left selected, for "Add Selection to Shelf".
// Everything that must add nothing or post nothing is here too: a tile with no
// button, a header of the page's own, a page that is not a session's, a click
// the page made up, a selection the right-click itself made, and the selected
// words, which are never in a message. The real page's own markup is only
// checked by a real right-click (TESTING.md).
import Foundation
import Testing
@testable import Bench

struct DocumentTileScriptTests {
    static let version = ShelfAddressTests.version
    static let words = FigureMenuScriptTests.words
    static let grouped = FigureMenuScriptTests.grouped
    static let plain = ["page:Copy image", "page:Open in split view"]

    private func page(path: String? = nil) -> PageScript {
        let script = PageScript()
        script.set("__VERSION", Self.version)
        script.set("__MENU", FakeFigurePage.menuClass)
        script.set("__ITEM", FakeFigurePage.itemClass)
        script.set("__DANGER", FakeFigurePage.dangerClass)
        script.set("__RULE", FakeFigurePage.ruleClass)
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

    private func watching(_ script: PageScript) -> Int {
        Int(script.evaluate("String(__watching())") ?? "") ?? -1
    }

    // MARK: The items, for a file with no picture

    @Test(arguments: [
        ("the tile's words", "__docText", "plan_notes.md"),
        ("its preview region", "__docBody", "plan_notes.md"),
        ("its header's name", "__docName", "plan_notes.md"),
        ("the version stepper in its header", "__docStep", "plan_notes.md"),
        ("its More actions button", "__docActions", "plan_notes.md"),
        ("a link out in its words", "__docLink", "plan_notes.md"),
        ("a card's words", "__captionText2", "notes.md"),
        ("a card's label", "__label2", "notes.md"),
        ("a card's preview", "__previewText2", "notes.md"),
    ])
    func everyPlaceATileOrCardOfAFileWithNoPictureCanBeRightClickedGetsTheItems(_ place: String, _ target: String, _ name: String) {
        let script = page()
        script.evaluate("__rightClick(\(target))")
        #expect(watching(script) == 1, "\(place)")
        script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
        #expect(shape(script) == Self.grouped, "\(place)")
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["action"] as? String == "addToShelf", "\(place)")
        #expect(sent?["kind"] as? String == "document", "\(place)")
        #expect(sent?["name"] as? String == name, "\(place)")
        // There is no address to name a version by; the name stands for it.
        #expect(sent?["version"] == nil, "\(place)")
        #expect(sent?["url"] == nil, "\(place)")
        #expect(script.exception == nil, "\(place): \(script.exception ?? "")")
    }

    @Test func choosingEachItemPostsTheActionAndTheNameAndClosesThePagesMenu() {
        for (index, action) in FigureMenuScriptTests.actions.enumerated() {
            let script = page()
            script.evaluate("__rightClick(__docText)")
            script.evaluate("__openMenu()")
            script.evaluate("var __e = __click(__ours()[\(index + 1)])")
            let sent = posted(script).last
            #expect(sent?["action"] as? String == action)
            #expect(sent?["kind"] as? String == "document")
            #expect(sent?["name"] as? String == "plan_notes.md")
            #expect(sent?["version"] == nil)
            #expect(script.evaluate("String(__menu === null)") == "true", "\(action)")
            #expect(watching(script) == 0, "\(action)")
            #expect(script.evaluate("String(__e.defaultPrevented)") == "true")
            script.evaluate("__advance(200)")
            #expect(script.evaluate("String(__liveTimers())") == "0", "nothing left running: \(action)")
            #expect(script.exception == nil, "\(script.exception ?? "")")
        }
    }

    @Test func theMessagesTheMessageParserReadsAreTheOnesTheScriptPosts() {
        var messages: [[String: Any]] = []
        for index in 1...4 {
            let script = page()
            script.evaluate("__rightClick(__docText); __openMenu(); __click(__ours()[\(index)]);")
            messages += posted(script).filter { $0["action"] != nil }
        }
        #expect(messages.count == 4)
        for message in messages {
            let choice = ConversationMenuMessage.documentChoice(in: message)
            #expect(choice?.name == "plan_notes.md")
            // And a figure's reading of the same message finds no version in it.
            #expect(ConversationMenuMessage.choice(in: message) == nil)
        }
    }

    @Test func aLinkWithAVersionInATileStillNamesItsVersionAndNotTheTile() {
        let script = page()
        script.evaluate("__rightClick(__docFileLink)")
        script.evaluate("__openMenu()")
        script.evaluate("__click(__ours()[4])")
        let sent = posted(script).last
        #expect(sent?["kind"] as? String == "link")
        #expect(sent?["version"] as? String == Self.version)
        #expect(sent?["name"] as? String == "qc_notes.md")
    }

    @Test func aFigureStillGetsItsVersionAndNotItsName() {
        let script = page()
        script.evaluate("__rightClick(__tileImg, { under: [__layer, __tileImg, __tileBox, __tile] })")
        script.evaluate("__openMenu()")
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["kind"] as? String == "image")
        #expect(sent?["version"] as? String == Self.version)
    }

    // MARK: The name

    @Test func aNameIsReadFromTheTitleOfACardAndTheTextOfATile() {
        let card = page()
        card.evaluate("__label2.attrs.title = 'results/summary table.csv'")
        card.evaluate("__rightClick(__captionText2); __openMenu(); __click(__ours()[2]);")
        // The last part of a path is the file's name, as the list gives it.
        #expect(posted(card).last?["name"] as? String == "summary table.csv")
        let tile = page()
        tile.evaluate("__docName.childNodes[0].data = '  outputs\\\\plan_notes.md \\n'")
        tile.evaluate("__rightClick(__docText); __openMenu(); __click(__ours()[2]);")
        #expect(posted(tile).last?["name"] as? String == "plan_notes.md")
        // The page's own control characters are dropped, and a long name is cut.
        let odd = page()
        odd.evaluate("__docName.childNodes[0].data = 'plan\\u0007_notes.md'")
        odd.evaluate("__rightClick(__docText); __openMenu(); __click(__ours()[2]);")
        #expect(posted(odd).last?["name"] as? String == "plan_notes.md")
        let long = page()
        long.evaluate("__docName.childNodes[0].data = 'a'.repeat(400)")
        long.evaluate("__rightClick(__docText); __openMenu(); __click(__ours()[2]);")
        #expect((posted(long).last?["name"] as? String)?.count == 300)
    }

    @Test func aTileOrCardWithNoNameAddsNothing() {
        let tile = page()
        tile.evaluate("__docName.childNodes[0].data = '   '")
        tile.evaluate("__rightClick(__docText)")
        #expect(watching(tile) == 0)
        tile.evaluate("__openMenu()")
        #expect(shape(tile) == Self.plain)
        #expect(traces(tile) == [["contextmenu", "figure-none"]])
        let card = page()
        card.evaluate("__label2.attrs.title = ''")
        card.evaluate("__rightClick(__captionText2)")
        #expect(watching(card) == 0)
        let bare = page()
        bare.evaluate("__label2.remove()")
        bare.evaluate("__rightClick(__previewText2)")
        #expect(watching(bare) == 0)
    }

    // MARK: What is not a tile

    @Test func aHeaderWithNoButtonForATilesMenuIsNotATile() {
        let script = page()
        script.evaluate("__rightClick(__pageTitle)")
        #expect(watching(script) == 0)
        script.evaluate("__docActions.remove(); __rightClick(__docName)")
        #expect(watching(script) == 0, "a tile's header without its button is any header")
        script.evaluate("__openMenu()")
        #expect(shape(script) == Self.plain)
    }

    @Test func aPreviewRegionNotInAHeaderedTileIsNotOne() {
        // A region whose ancestors hold no header with the button gets nothing.
        let script = page()
        script.evaluate("__docActions.remove(); __rightClick(__docText)")
        #expect(watching(script) == 0)
        #expect(traces(script) == [["contextmenu", "figure-none"]])
    }

    @Test func aPopUpOverATileDoesNotTakeTheTileBeneathIt() {
        let script = page()
        script.evaluate("__rightClick(__modalText, { under: [__modalText, __modal, __docText, __docBody] })")
        #expect(watching(script) == 0)
    }

    @Test(arguments: ["/", "/projects/p1", "/projects/p1/frames", "/projects/p1/frames/short", "/projects/p1/frames/x/extra", "/settings"])
    func nothingIsAddedForAFileOnAPageThatIsNotASession(_ path: String) {
        let script = page(path: path)
        script.evaluate("__rightClick(__docText)")
        script.evaluate("__rightClick(__captionText2)")
        #expect(watching(script) == 0, "\(path)")
        script.evaluate("__openMenu()")
        #expect(shape(script) == Self.plain, "\(path)")
        #expect(traces(script).allSatisfy { !$0.contains("figure-document") }, "\(path)")
    }

    @Test func aRightClickTheBrowserDidNotMakeStartsNothing() {
        let script = page()
        script.evaluate("__rightClick(__docText, { trusted: false })")
        #expect(posted(script).isEmpty)
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == Self.plain)
    }

    @Test func aClickThePageMadeUpOnADocumentItemDoesNothing() {
        let script = page()
        script.evaluate("__rightClick(__docText); __openMenu();")
        script.evaluate("__click(__ours()[1], false)")
        #expect(posted(script).allSatisfy { $0["action"] == nil }, "nothing was chosen")
        #expect(script.evaluate("String(__menu !== null)") == "true")
        #expect(shape(script) == Self.grouped)
        script.evaluate("__click(__ours()[1])")
        #expect(posted(script).last?["action"] as? String == "addToShelf")
    }

    @Test func aMenuThatComesAfterTwoSecondsGetsNothingForADocumentEither() {
        let script = page()
        script.evaluate("__rightClick(__docText)")
        script.evaluate("__advance(2001)")
        script.evaluate("__openMenu()")
        #expect(shape(script) == Self.plain)
        #expect(traces(script) == [["contextmenu", "figure-document", "menu-none"]])
    }

    // MARK: The trace

    @Test func theTraceSaysTheFileWasFoundByItsName() {
        let tile = page()
        tile.evaluate("__rightClick(__docText); __openMenu();")
        #expect(traces(tile) == [["contextmenu", "figure-document", "menu-matched", "placed"]])
        let card = page()
        card.evaluate("__rightClick(__captionText2); __openMenu();")
        #expect(traces(card) == [["contextmenu", "figure-document", "menu-matched", "placed"]])
        // A link out in the tile's words is no file, so the trace says so, then goes on to the tile.
        let link = page()
        link.evaluate("__rightClick(__docLink); __openMenu();")
        #expect(traces(link) == [["contextmenu", "figure-link", "version-none", "figure-document", "menu-matched", "placed"]])
        for trace in traces(link) + traces(card) {
            #expect(ConversationMenuMessage.trace(in: ["trace": trace])?.map(\.rawValue) == trace)
        }
        #expect(FigureMenuStep(rawValue: "figure-document") == .figureDocument)
    }

    // MARK: The selected words

    static let passage = "Plate 7 drifts after the midpoint, and the edge wells run low."

    @Test func aRightClickInsideASelectionSaysHowManyCharactersAreSelected() {
        let script = page()
        script.set("__WORDS", Self.passage)
        script.evaluate("__selected = __WORDS; __rightClick(__paragraph)")
        let sent = posted(script)
        #expect(sent.count == 1)
        #expect(sent.first?["kind"] is NSNull)
        #expect(sent.first?["selected"] as? Int == Self.passage.count)
        #expect(ConversationMenuMessage.selection(in: sent.first) == Self.passage.count)
        // The words themselves are in no message, and not in the trace.
        let everything = script.evaluate("JSON.stringify(__posted)") ?? ""
        #expect(!everything.contains("drifts") && !everything.contains("midpoint"))
    }

    @Test func aControlClickInsideASelectionIsAlsoOne() {
        let script = page()
        script.set("__WORDS", Self.passage)
        script.evaluate("__selected = __WORDS; __rightClick(__paragraph, { control: true })")
        #expect(posted(script).first?["selected"] as? Int == Self.passage.count)
    }

    @Test func aSelectionAmongFiguresAndLinksIsReportedWithTheirMessages() {
        let script = page()
        script.set("__WORDS", Self.passage)
        script.evaluate("__selected = __WORDS; __rightClick(__tileImg, { under: [__tileImg] })")
        #expect(posted(script).first?["kind"] as? String == "image")
        #expect(posted(script).first?["selected"] as? Int == Self.passage.count)
        script.evaluate("__closeMenu(); __selected = __WORDS; __rightClick(__plainLink)")
        #expect(posted(script).last?["kind"] as? String == "link")
        #expect(posted(script).last?["selected"] as? Int == Self.passage.count)
    }

    @Test func theWordTheRightClickSelectedItselfIsNotAPassage() {
        // WebKit selects the word under the pointer when a right-click lands outside the selection.
        let script = page()
        script.evaluate("__selected = ''; __rightClick(__paragraph, { word: 'plates' })")
        #expect(posted(script).first?["selected"] == nil)
        // The same when the right-click lands outside a passage that was selected: the word replaces it.
        let outside = page()
        outside.set("__WORDS", Self.passage)
        outside.evaluate("__selected = __WORDS; __rightClick(__paragraph, { word: 'plates' })")
        #expect(posted(outside).first?["selected"] == nil)
        // A word that was selected before and is left alone by the click is a selection like any other.
        let same = page()
        same.evaluate("__selected = 'plates'; __rightClick(__paragraph, { word: 'plates' })")
        #expect(posted(same).first?["selected"] as? Int == 6)
    }

    @Test func noSelectionOrOneOfBlanksIsNoCount() {
        let none = page()
        none.evaluate("__rightClick(__paragraph)")
        #expect(posted(none).first?["selected"] == nil)
        let blanks = page()
        blanks.evaluate("__selected = ' \\n\\t '; __rightClick(__paragraph)")
        #expect(posted(blanks).first?["selected"] == nil)
    }

    @Test func aMenuAskedForByTheKeyboardWithNoButtonHasNoCount() {
        let script = page()
        script.set("__WORDS", Self.passage)
        script.evaluate("__selected = __WORDS; __rightClick(__paragraph, { down: false })")
        #expect(posted(script).first?["selected"] == nil)
    }

    @Test func aSelectionKeptFromAnEarlierClickIsNotUsedAgain() {
        let script = page()
        script.set("__WORDS", Self.passage)
        script.evaluate("__selected = __WORDS; __rightClick(__paragraph)")
        script.evaluate("__rightClick(__paragraph, { down: false })")
        #expect(posted(script).last?["selected"] == nil, "what was kept at one button-down is spent by the menu")
    }

    @Test func noCountOnAPageThatIsNotASession() {
        for path in ["/", "/projects/p1", "/settings"] {
            let script = page(path: path)
            script.set("__WORDS", Self.passage)
            script.evaluate("__selected = __WORDS; __rightClick(__paragraph)")
            #expect(posted(script).first?["selected"] == nil, "\(path)")
        }
    }

    @Test func aClickThePageMadeUpReadsNoSelectionAndPostsNoMessage() {
        let script = page()
        script.set("__WORDS", Self.passage)
        script.evaluate("__selected = __WORDS; __rightClick(__paragraph, { trusted: false })")
        #expect(posted(script).isEmpty)
        #expect(traces(script).isEmpty)
    }

    @Test func theScriptNeverPostsWhatWasSelected() {
        let text = ConversationMenu.script
        // The selection is read in the script and compared; only its length is posted.
        #expect(text.contains("window.getSelection"))
        #expect(!text.contains("selected: now") && !text.contains("selected: kept") && !text.contains("selected: selectedText"))
        #expect(text.contains("Array.from(now).length"))
        // The one place the words are read by Swift is a script of its own, run when the item is chosen, which posts nothing.
        #expect(!SelectedWordsScript.read.contains("postMessage"))
        #expect(SelectedWordsScript.read.contains("getSelection"))
    }
}
