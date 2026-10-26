// ViewerFigureTests.swift — a picture open large in Claude Science's own viewer
// (the side pane, a tab, the fullscreen tile), and a file with no picture open
// in the right-hand panel: Capsid's items in the page's menu for them
// (Shelf/ConversationMenu.swift, the page side), run in JavaScriptCore against
// the made-up page (FakeFigurePage), whose viewer is drawn as the 0.1.70 bundle
// draws it (ArtifactTile-DmtoiOPx.js, ImagePreview-C0f3P6Gf.js, index.esm-
// D4jRnBIq.js).
//
// What the bundle does, and the first version of the script missed: the viewer
// draws its picture inside a zoom-and-pan wrapper whose stylesheet gives its
// images `pointer-events: none`, so the picture is never what a right-click
// lands on, nor in the list of what is under the pointer (`elementsFromPoint`).
// The click lands on the annotation layer over it, the box round it or the
// wrapper's empty space. Every test here gives the script the stack the browser
// gives (`__vStack`, with no picture in it). A tile of that panel also has no
// name in its header (the panel's tab has it), so the first span in the header
// was the version stepper's, or nothing.
//
// The name lookup's log lines (counts only) are tested at the end. The real
// page is only checked by a real right-click (TESTING.md); FigureMenuSnapshotTests
// draws the viewer in WebKit.
import Foundation
import Testing
@testable import Bench

struct ViewerFigureScriptTests {
    static let version = ShelfAddressTests.version
    /// The viewer's picture is another version than the page's others (FakeFigurePage's `__VV`).
    static let viewerVersion = String(version.dropLast()) + (version.hasSuffix("0") ? "1" : "0")
    static let words = FigureMenuScriptTests.words
    static let actions = FigureMenuScriptTests.actions
    /// The viewer's menu: the page's image items and no red one, so Capsid's group is at its end.
    static let pageItems = "['Copy image', 'Save image', '-', 'Download']"
    static let grouped = ["page:Copy image", "page:Save image", "page-rule", "page:Download", "rule"] + words.map { "ours:" + $0 }

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

    /// The viewer's own address for its picture.
    static var address: String { "http://localhost:8123/api/artifacts/versions/\(viewerVersion)?v=\(viewerVersion)" }

    // MARK: A picture in the viewer

    @Test(arguments: [
        ("the annotation layer over the picture", "__vLayer"),
        ("a marker in that layer", "__vMarker"),
        ("the box round the picture", "__vBox"),
        ("the wrapper's content, beside the picture", "__vContent"),
        ("the zoom-and-pan wrapper", "__vWrapper"),
        ("the viewer's root", "__vRoot"),
        ("the tile's preview region", "__vRegion"),
        ("the tile's header", "__vHeader"),
        ("the version stepper in its header", "__vStep"),
        ("its More actions button", "__vActions"),
    ])
    func aRightClickAnywhereInTheViewerGetsTheFourItemsOnThePicturesVersion(_ place: String, _ target: String) {
        let script = page()
        // The stack under the pointer has the layer and the boxes and not the picture, which takes no pointer events.
        script.evaluate("__rightClick(\(target), { under: __vStack })")
        // The Mac's menu is told what was clicked, as for any figure.
        let first = posted(script)
        #expect(first.count == 1, "\(place)")
        #expect(first.first?["kind"] as? String == "image", "\(place)")
        #expect(first.first?["url"] as? String == Self.address, "\(place)")
        #expect(first.first?["name"] as? String == "scatter_plot.png", "\(place)")
        #expect(watching(script) == 1, "\(place)")
        script.evaluate("__openMenu(\(Self.pageItems))")
        #expect(shape(script) == Self.grouped, "\(place)")
        #expect(traces(script) == [["contextmenu", "figure-viewer", "version-ok", "menu-matched", "placed"]], "\(place)")
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["action"] as? String == "addToShelf", "\(place)")
        #expect(sent?["kind"] as? String == "image", "\(place)")
        // The viewer's version, not the page's others.
        #expect(sent?["version"] as? String == Self.viewerVersion, "\(place)")
        #expect(sent?["name"] as? String == "scatter_plot.png", "\(place)")
        #expect(sent?["url"] == nil, "no address goes with a chosen item: \(place)")
        #expect(script.evaluate("String(__menu === null)") == "true", "the page's menu closed: \(place)")
        #expect(script.exception == nil, "\(place): \(script.exception ?? "")")
    }

    @Test func eachItemPostsTheActionOnTheViewersPicture() {
        for (index, action) in Self.actions.enumerated() {
            let script = page()
            script.evaluate("__rightClick(__vLayer, { under: __vStack })")
            script.evaluate("__openMenu(\(Self.pageItems))")
            script.evaluate("__click(__ours()[\(index + 1)])")
            let sent = posted(script).last
            #expect(sent?["action"] as? String == action)
            #expect(sent?["version"] as? String == Self.viewerVersion, "\(action)")
            #expect(watching(script) == 0, "\(action)")
        }
    }

    @MainActor
    @Test func aClickRunsTheActionOnTheViewersVersionInSwift() {
        var ran: [String] = []
        let menu = ConversationMenu(daemonPort: { 8123 }, breadcrumbs: CompatBreadcrumbs(), traced: { _ in },
                                    run: { action, pick in ran.append("\(action.rawValue)|\(pick.kind.rawValue)|\(pick.version)|\(pick.name)") })
        for index in 1...4 {
            let script = page()
            script.evaluate("__rightClick(__vLayer, { under: __vStack }); __openMenu(\(Self.pageItems)); __click(__ours()[\(index)]);")
            if let message = posted(script).last { menu.hear(message, accepted: true) }
        }
        #expect(ran == Self.actions.map { "\($0)|image|\(Self.viewerVersion)|scatter_plot.png" })
    }

    @Test func aViewerMenuWithARedItemKeepsItLastAndOneWithoutTakesTheItemsAtItsEnd() {
        // The menu `ImagePreview` opens has no Delete (the other tests); the tile's own menu has one, and the group goes above it.
        let script = page()
        script.evaluate("__rightClick(__vLayer, { under: __vStack })")
        script.evaluate("__openMenu(['Copy image', '-', 'Open in split view', '-', '!Delete'])")
        #expect(shape(script) == ["page:Copy image", "page-rule", "page:Open in split view", "rule"] + Self.words.map { "ours:" + $0 } + ["page-rule", "page:Delete"])
    }

    @Test func theViewerIsFoundFromTheTileWhateverIsUnderThePointer() {
        // Neither a stack with the picture in it nor an empty one changes it; the old path (the stack) is not needed.
        for under in ["__vStack", "[]", "[__vImg].concat(__vStack)"] {
            let script = page()
            script.evaluate("__rightClick(__vLayer, { under: \(under) })")
            script.evaluate("__openMenu(\(Self.pageItems))")
            #expect(shape(script) == Self.grouped, "\(under)")
            #expect(traces(script).last == ["contextmenu", "figure-viewer", "version-ok", "menu-matched", "placed"], "\(under)")
        }
    }

    @Test func aMadeUpRightClickInTheViewerIsIgnored() {
        let script = page()
        script.evaluate("__rightClick(__vLayer, { under: __vStack, trusted: false })")
        #expect(posted(script).isEmpty)
        #expect(traces(script).isEmpty)
        #expect(watching(script) == 0)
        script.evaluate("__openMenu(\(Self.pageItems))")
        #expect(shape(script) == ["page:Copy image", "page:Save image", "page-rule", "page:Download"])
    }

    @Test func aMadeUpClickOnAnItemInTheViewersMenuPostsNothing() {
        let script = page()
        script.evaluate("__rightClick(__vLayer, { under: __vStack })")
        script.evaluate("__openMenu(\(Self.pageItems))")
        script.evaluate("__click(__ours()[1], false)")
        #expect(posted(script).filter { $0["action"] != nil }.isEmpty)
    }

    // MARK: A viewer whose picture names no version

    @Test func aViewerPictureWithNoVersionInItsAddressIsFoundByTheTabsName() {
        let script = page()
        script.evaluate(#"__vImg.attrs.src = "blob:http://localhost:8123/5a1c0d9e";"#)
        script.evaluate("__rightClick(__vLayer, { under: __vStack })")
        #expect(watching(script) == 1)
        script.evaluate("__openMenu(\(Self.pageItems))")
        #expect(shape(script) == Self.grouped)
        #expect(traces(script) == [["contextmenu", "figure-viewer", "version-none", "figure-document", "name-from-tab", "menu-matched", "placed"]])
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["kind"] as? String == "document")
        #expect(sent?["name"] as? String == "scatter_plot.png")
        #expect(sent?["version"] == nil)
        #expect(ConversationMenuMessage.documentChoice(in: sent)?.name == "scatter_plot.png")
    }

    @Test func aViewerPictureOnAnotherOriginIsNotTakenForTheFilesVersion() {
        let script = page()
        script.evaluate(#"__vImg.attrs.src = "https://example.com/api/artifacts/versions/" + __VV + "?v=" + __VV;"#)
        script.evaluate("__rightClick(__vLayer, { under: __vStack })")
        script.evaluate("__openMenu(\(Self.pageItems))")
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["version"] == nil, "an address on another origin names no version")
        #expect(sent?["kind"] as? String == "document")
    }

    // MARK: A viewer picture that can't be identified adds nothing

    @Test(arguments: [
        ("no tab strip at all", #"__strip.remove();"#),
        ("two shown tabs", #"__tabOther.attrs["data-shown"] = "true";"#),
        ("no shown tab", #"delete __tabShown.attrs["data-shown"]; delete __tabShown.children[0].attrs["aria-current"];"#),
        ("a shown tab with no label", #"__tabShown.children[0].childNodes.pop();"#),
        ("a shown tab with a blank label", #"__showTab("   ");"#),
        ("a tile outside the right-hand panel", #"document.body.appendChild(__vTile);"#),
    ])
    func aViewerPictureWithNoVersionAndNoNameAddsNothing(_ why: String, _ setup: String) {
        let script = page()
        script.evaluate(#"__vImg.attrs.src = "blob:http://localhost:8123/5a1c0d9e";"#)
        script.evaluate(setup)
        script.evaluate("__rightClick(__vLayer, { under: __vStack })")
        #expect(watching(script) == 0, "\(why)")
        #expect(traces(script) == [["contextmenu", "figure-viewer", "version-none", "tile-unnamed"]], "\(why)")
        // Even if the page opens a menu, there is nothing to put in it.
        script.evaluate("__openMenu(\(Self.pageItems))")
        #expect(shape(script) == ["page:Copy image", "page:Save image", "page-rule", "page:Download"], "\(why)")
        #expect(posted(script).filter { $0["action"] != nil }.isEmpty, "\(why)")
    }

    @Test func aFileOnTheHostsDiskGetsNothingEvenInTheSameViewer() {
        // The same zoom-and-pan wrapper, in a tab for a file on disk: no preview region, no button for an artifact's menu.
        for (target, trace) in [("__fLayer", ["contextmenu", "figure-none"]),
                                ("__fImg", ["contextmenu", "figure-image", "version-none"])] {
            let script = page()
            script.evaluate("__rightClick(\(target), { under: [__fLayer, __fBox, __fContent, __fWrapper, __fRoot] })")
            #expect(watching(script) == 0, "\(target)")
            #expect(traces(script) == [trace], "\(target)")
            script.evaluate("__openMenu(\(Self.pageItems))")
            #expect(shape(script) == ["page:Copy image", "page:Save image", "page-rule", "page:Download"], "\(target)")
        }
    }

    @Test func twoPicturesInTheViewerAreNeitherTakenForTheFile() {
        let script = page()
        script.evaluate(#"el("img", { src: "http://localhost:8123/api/artifacts/versions/" + __V, alt: "other.png" }, __vBox);"#)
        script.evaluate("__rightClick(__vLayer, { under: __vStack })")
        // Not a viewer's picture: the tile's name (its tab's) stands for the file.
        script.evaluate("__openMenu(\(Self.pageItems))")
        #expect(traces(script) == [["contextmenu", "figure-document", "name-from-tab", "menu-matched", "placed"]])
        script.evaluate("__click(__ours()[1])")
        #expect(posted(script).last?["kind"] as? String == "document")
        #expect(posted(script).last?["version"] == nil)
    }

    @Test func aMarkdownTileWithOnePictureIsNotAViewer() {
        // The tile's words are not the picture, whatever is in the body with them.
        let script = page()
        script.evaluate(#"__showTab("plan_notes.md"); __rightClick(__wText, { under: [__wText, __wRegion] });"#)
        script.evaluate("__openMenu()")
        #expect(traces(script) == [["contextmenu", "figure-document", "name-from-tab", "menu-matched", "placed"]])
        script.evaluate("__click(__ours()[1])")
        #expect(posted(script).last?["name"] as? String == "plan_notes.md")
        #expect(posted(script).last?["kind"] as? String == "document")
        // And the picture itself, which does take clicks there, is its own version as before.
        let other = page()
        other.evaluate("__rightClick(__wImg, { under: [__wImg, __wRegion] })")
        other.evaluate("__openMenu()")
        #expect(traces(other) == [["contextmenu", "figure-image", "version-ok", "menu-matched", "placed"]])
        other.evaluate("__click(__ours()[1])")
        #expect(posted(other).last?["version"] as? String == Self.version)
        #expect(posted(other).last?["kind"] as? String == "image")
    }

    // MARK: The conversation's figures are as they were

    @Test func theConversationsFiguresAreFoundAsBeforeAndTraceTheSameWords() {
        let cases: [(String, String, [String])] = [
            ("an inline figure's surface", "__rightClick(__surface, { under: [__surface, __inlineImg, __inline, __page] })",
             ["contextmenu", "figure-beside", "version-ok", "menu-matched", "placed"]),
            ("an inline figure", "__rightClick(__inlineImg, { under: [__inlineImg, __inline, __page] })",
             ["contextmenu", "figure-image", "version-ok", "menu-matched", "placed"]),
            ("a tray card's words", "__rightClick(__captionText, { under: [__captionText, __caption, __card, __cardWrap, __tray] })",
             ["contextmenu", "figure-card", "version-ok", "menu-matched", "placed"]),
            ("a picture under a layer", "__rightClick(__layer, { under: [__layer, __tileImg, __tileBox, __tile] })",
             ["contextmenu", "figure-beside", "version-ok", "menu-matched", "placed"]),
        ]
        for (place, click, trace) in cases {
            let script = page()
            script.evaluate(click)
            script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
            #expect(traces(script) == [trace], "\(place)")
            #expect(shape(script) == FigureMenuScriptTests.grouped, "\(place)")
            #expect(posted(script).last?["kind"] as? String == "image", "\(place)")
        }
    }

    @Test func aLinkInATileStillNamesItsVersionAndAPlainLinkNothing() {
        let script = page()
        script.evaluate("__rightClick(__docFileLink)")
        script.evaluate("__openMenu()")
        #expect(traces(script) == [["contextmenu", "figure-link", "version-ok", "menu-matched", "placed"]])
        let plain = page()
        plain.evaluate("__rightClick(__plainLink)")
        #expect(traces(plain) == [["contextmenu", "figure-link", "version-none"]])
    }

    // MARK: A file with no picture in the right-hand panel

    @Test func aTileOfThePanelIsNamedByTheShownTabNotByTheVersionStepper() {
        // The panel's tile has no name in its header, only a stepper whose text is "v2 (old)" (a button in it).
        let script = page()
        script.evaluate(#"__showTab("plan_notes.md"); __rightClick(__wText);"#)
        script.evaluate("__openMenu()")
        #expect(traces(script) == [["contextmenu", "figure-document", "name-from-tab", "menu-matched", "placed"]])
        for (index, action) in Self.actions.enumerated() {
            let again = page()
            again.evaluate(#"__showTab("plan_notes.md"); __rightClick(__wText); __openMenu(); __click(__ours()[\#(index + 1)]);"#)
            let sent = posted(again).last
            #expect(sent?["action"] as? String == action)
            #expect(sent?["kind"] as? String == "document")
            #expect(sent?["name"] as? String == "plan_notes.md")
            #expect(sent?["version"] == nil)
            #expect(ConversationMenuMessage.documentChoice(in: sent)?.name == "plan_notes.md")
        }
    }

    @Test func aTilesOwnNameIsUsedAndTheTabIsNotLookedAt() {
        // A tile that shows its name (a conversation's, not the panel's) keeps it, whatever the panel's tab says.
        let script = page()
        script.evaluate(#"__showTab("something_else.md"); __rightClick(__docText);"#)
        script.evaluate("__openMenu()")
        #expect(traces(script) == [["contextmenu", "figure-document", "menu-matched", "placed"]])
        script.evaluate("__click(__ours()[1])")
        #expect(posted(script).last?["name"] as? String == "plan_notes.md")
    }

    @Test func theTabsNameIsReadLikeATilesNameACleanLastPartOfAPath() {
        let script = page()
        script.evaluate(#"__showTab("results/plan\u0007_notes.md"); __rightClick(__wText); __openMenu(); __click(__ours()[1]);"#)
        #expect(posted(script).last?["name"] as? String == "plan_notes.md")
    }

    @Test(arguments: [
        ("no tab strip", #"__strip.remove();"#),
        ("two shown tabs", #"__tabOther.attrs["data-shown"] = "true";"#),
        ("no shown tab", #"delete __tabShown.attrs["data-shown"]; delete __tabShown.children[0].attrs["aria-current"];"#),
        ("a shown tab with a blank label", #"__showTab("");"#),
        ("a tile outside the right-hand panel", #"document.body.appendChild(__wTile);"#),
    ])
    func aTileOfThePanelWithNoNameToBeHadGetsNothing(_ why: String, _ setup: String) {
        let script = page()
        script.evaluate(setup)
        script.evaluate("__rightClick(__wText)")
        #expect(watching(script) == 0, "\(why)")
        #expect(traces(script) == [["contextmenu", "figure-none", "tile-unnamed"]], "\(why)")
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"], "\(why)")
    }

    @Test func theProvenanceBreadcrumbInATilesHeaderIsNotItsName() {
        // With the provenance drawer open the page replaces the name with a breadcrumb (a nav with buttons, and a span
        // "Provenance" after them). Not a name, so a tile outside the panel gets nothing.
        let script = page()
        script.evaluate(#"""
            __docTitleBox.childNodes = [];
            var __nav = el("nav", { "aria-label": "Artifact breadcrumb" }, __docTitleBox);
            var __back = el("button", { type: "button" }, __nav); text(__back, "plan_notes.md");
            var __current = el("span", { "aria-current": "page" }, __nav); text(__current, "Provenance");
            __rightClick(__docText);
            """#)
        #expect(traces(script) == [["contextmenu", "figure-none", "tile-unnamed"]])
        #expect(watching(script) == 0)
    }

    @Test func aTileInThePanelWithTheBreadcrumbIsStillNamedByItsTab() {
        let script = page()
        script.evaluate(#"""
            __showTab("plan_notes.md");
            var __nav = el("nav", { "aria-label": "Artifact breadcrumb" }, __wTitleBox);
            var __current = el("span", { "aria-current": "page" }, __nav); text(__current, "Provenance");
            __rightClick(__wText); __openMenu(); __click(__ours()[1]);
            """#)
        #expect(posted(script).last?["name"] as? String == "plan_notes.md")
    }

    @Test func aTileOnAPageThatIsNotASessionsGetsNothingByName() {
        for path in ["/", "/projects/p1", "/projects/p1/artifacts/a1"] {
            let script = page(path: path)
            script.evaluate(#"__showTab("plan_notes.md"); __rightClick(__wText);"#)
            #expect(watching(script) == 0, "\(path)")
            #expect(traces(script) == [["contextmenu", "figure-none"]], "\(path)")
        }
    }

    // MARK: The steps

    @Test func theNewStepsAreWordsSwiftKnowsAndTheLineReadsThemInOrder() {
        #expect(FigureMenuStep(rawValue: "figure-viewer") == .figureViewer)
        #expect(FigureMenuStep(rawValue: "name-from-tab") == .nameFromTab)
        #expect(FigureMenuStep(rawValue: "tile-unnamed") == .tileUnnamed)
        let steps = ConversationMenuMessage.trace(in: ["trace": ["contextmenu", "figure-viewer", "version-ok", "menu-matched", "placed"]])
        #expect(steps.map(ConversationMenuMessage.line) == "Figure menu: contextmenu \u{2192} figure-viewer \u{2192} version-ok \u{2192} menu-matched \u{2192} placed")
        // The longest right-click there can be is read whole.
        let longest = ["contextmenu", "figure-viewer", "version-none", "figure-document", "name-from-tab", "menu-matched", "selection-offered", "placed"]
        #expect(ConversationMenuMessage.trace(in: ["trace": longest])?.map(\.rawValue) == longest)
        // A word the script doesn't have is dropped, so nothing the page writes reaches the log.
        #expect(ConversationMenuMessage.trace(in: ["trace": ["contextmenu", "figure-viewer", "scatter_plot.png"]])?.map(\.rawValue) == ["contextmenu", "figure-viewer"])
    }

    @Test func everyTraceTheViewerTestsMakeIsReadWholeBySwift() {
        let script = page()
        script.evaluate(#"""
            __rightClick(__vLayer, { under: __vStack });
            __vImg.attrs.src = "blob:http://localhost:8123/5a1c"; __rightClick(__vLayer, { under: __vStack });
            __strip.remove(); __rightClick(__vLayer, { under: __vStack });
            __rightClick(__fLayer);
            __advance(2001);
            """#)
        let all = traces(script)
        #expect(all.count == 4)
        for trace in all {
            #expect(ConversationMenuMessage.trace(in: ["trace": trace])?.map(\.rawValue) == trace)
        }
    }
}

// MARK: The log for a name's lookup

@MainActor
struct NameLookupLogTests {
    final class Lines {
        var all: [String] = []
        var files: [ArtifactEntry]? = []
        var picks: [ShelfDocument.Candidate] = []
    }

    private static func entry(_ name: String, _ number: Int, at: Double) -> ArtifactEntry {
        ArtifactEntry(version: String(format: "bbbbbbbb-0000-4000-8000-%012d", number), artifact: String(format: "cccccccc-0000-4000-8000-%012d", number),
                      name: name, mime: "text/markdown", size: 1_200, at: Date(timeIntervalSince1970: at))
    }

    private func make(route: NidusTaskSelection.Route? = ShelfDocumentActionTests.route) -> (ConversationShelf, Lines) {
        let fake = MadeShelf()
        let lines = Lines()
        let toast = ShelfToastModel(shelf: fake.access, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, announce: { _ in })
        let shelf = ConversationShelf(dependencies: .init(
            route: { route },
            session: { _ in ShelfDocumentActionTests.session },
            facts: { _ in nil },
            shelf: fake.access, toast: toast,
            keep: { _ in }, reference: { _, _ in }, results: { _ in },
            files: { _ in lines.files },
            chooseFile: { _, candidates in
                lines.picks = candidates
                return nil
            },
            note: { lines.all.append($0) }))
        return (shelf, lines)
    }

    // The name is made up and unlike any word in the fixed lines, so a line that held it would show.
    static let name = "quarterly_plate_review.md"

    @Test func oneFileOfThatNameIsOneMatch() async {
        let (shelf, lines) = make()
        lines.files = [Self.entry(Self.name, 1, at: 10), Self.entry("other.md", 2, at: 20)]
        await shelf.run(.keep, named: Self.name)
        #expect(lines.all == ["Figure menu: name matched 1"])
    }

    @Test func aNameNoFileHasSaysNotFound() async {
        let (shelf, lines) = make()
        lines.files = [Self.entry("other.md", 2, at: 20)]
        await shelf.run(.addToShelf, named: Self.name)
        #expect(lines.all == ["Figure menu: name not found"])
        // The name was "v2 (old)" before the header was read right: a name no file has.
        lines.all = []
        await shelf.run(.addToShelf, named: "v2 (old)")
        #expect(lines.all == ["Figure menu: name not found"])
    }

    @Test func twoFilesOfThatNameSayHowManyAndAskWhich() async {
        let (shelf, lines) = make()
        lines.files = [Self.entry(Self.name, 1, at: 10), Self.entry(Self.name, 2, at: 20)]
        await shelf.run(.openAsReference, named: Self.name)
        #expect(lines.all == ["Figure menu: name matched 2"])
        #expect(lines.picks.count == 2, "and the question is asked as before")
        lines.all = []
        lines.files = [Self.entry(Self.name, 1, at: 10), Self.entry(Self.name, 2, at: 20), Self.entry(Self.name, 3, at: 30)]
        await shelf.run(.openAsReference, named: Self.name)
        #expect(lines.all == ["Figure menu: name matched 3"])
    }

    @Test func oneFileListedAtSeveralVersionsIsStillOneMatch() async {
        let (shelf, lines) = make()
        let first = Self.entry(Self.name, 1, at: 10)
        let later = ArtifactEntry(version: "bbbbbbbb-0000-4000-8000-000000000099", artifact: first.artifact, name: Self.name,
                                  mime: "text/markdown", size: 1_300, at: Date(timeIntervalSince1970: 40))
        lines.files = [first, later]
        await shelf.run(.keep, named: Self.name)
        #expect(lines.all == ["Figure menu: name matched 1"])
    }

    @Test func aListThatCouldntBeReadSaysSo() async {
        let (shelf, lines) = make()
        lines.files = nil
        await shelf.run(.keep, named: Self.name)
        #expect(lines.all == ["Figure menu: files not read"])
    }

    @Test func showInResultsAndAPageNotOnASessionLookNothingUpAndSayNothing() async {
        let (shelf, lines) = make()
        lines.files = [Self.entry(Self.name, 1, at: 10)]
        await shelf.run(.showInResults, named: Self.name)
        #expect(lines.all.isEmpty)
        let (elsewhere, other) = make(route: nil)
        other.files = [Self.entry(Self.name, 1, at: 10)]
        await elsewhere.run(.keep, named: Self.name)
        #expect(other.all.isEmpty)
    }

    @Test func noLineHoldsTheNameOnlyFixedWordsAndACount() async {
        let (shelf, lines) = make()
        for files in [[Self.entry("other.md", 2, at: 20)], [Self.entry(Self.name, 1, at: 10)],
                      [Self.entry(Self.name, 1, at: 10), Self.entry(Self.name, 2, at: 20)], nil] {
            lines.files = files
            await shelf.run(.keep, named: Self.name)
        }
        #expect(lines.all.count == 4)
        let allowed = #/^Figure menu: (name not found|name matched [0-9]+|files not read)$/#
        for line in lines.all {
            #expect(!line.contains("quarterly") && !line.contains(".md"), "\(line)")
            #expect(line.wholeMatch(of: allowed) != nil, "\(line)")
        }
    }

    @Test func theLinesAreTheLookupsOwnAndFixed() {
        #expect(ShelfDocument.lookupLine(nil) == "Figure menu: files not read")
        #expect(ShelfDocument.lookupLine(.some(.none)) == "Figure menu: name not found")
        #expect(ShelfDocument.lookupLine(.some(.found(Self.entry(Self.name, 1, at: 1)))) == "Figure menu: name matched 1")
        let several = ShelfDocument.Match.several((1...3).map { ShelfDocument.Candidate(entry: Self.entry(Self.name, $0, at: Double($0)), versions: 1) })
        #expect(ShelfDocument.lookupLine(several) == "Figure menu: name matched 3")
    }
}
