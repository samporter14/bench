// FigureMenuScriptTests.swift — Capsid's items inside Claude Science's own
// figure menu (Shelf/ConversationMenu.swift, the page side), run in
// JavaScriptCore against a made-up page (FakeFigurePage): a right-click on a
// figure, the page's menu opening after it, the rule and four items added at
// its end, a click on one and the menu closing; and everything that must add
// nothing. The page's menu in that fake is guarded, so a script that read the
// words of its items would fail here. How the menu looks is checked by eye
// (FigureMenuSnapshotTests); the real page's behaviour only by a real
// right-click (TESTING.md).
import Foundation
import Testing
@testable import Bench

struct FigureMenuScriptTests {
    static let version = ShelfAddressTests.version
    static let words = ["Add to Shelf", "Keep with Data and Code\u{2026}", "Open as Reference", "Show in Results"]
    static let actions = ["addToShelf", "keep", "openAsReference", "showInResults"]
    /// What a menu holding Capsid's group looks like, after the page's two items.
    static let grouped = ["page:Copy image", "page:Open in split view", "rule"] + words.map { "ours:" + $0 }

    /// A page with the script loaded.
    private func page(ruleClass: String = FakeFigurePage.ruleClass) -> PageScript {
        let script = PageScript()
        script.set("__VERSION", Self.version)
        script.set("__MENU", FakeFigurePage.menuClass)
        script.set("__ITEM", FakeFigurePage.itemClass)
        script.set("__DANGER", FakeFigurePage.dangerClass)
        script.set("__RULE", ruleClass)
        script.evaluate(FakeFigurePage.source)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        script.evaluate(ConversationMenu.script)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        return script
    }

    private func json(_ script: PageScript, _ expression: String) -> Any? {
        let text = script.evaluate("JSON.stringify(\(expression))") ?? "null"
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    private func posted(_ script: PageScript) -> [[String: Any]] {
        (json(script, "__posted") as? [[String: Any]]) ?? []
    }

    private func shape(_ script: PageScript) -> [String] {
        (json(script, "__shape()") as? [String]) ?? []
    }

    private func watching(_ script: PageScript) -> Int {
        Int(script.evaluate("String(__watching())") ?? "") ?? -1
    }

    // MARK: The items, after a right-click on a figure

    @Test func aRightClickOnATileThenThePagesMenuGetsTheFourItems() {
        let script = page()
        script.evaluate("__rightClick(__tileImg, { under: [__layer, __tileImg, __tileBox, __tile] })")
        // The old message is still sent: the Mac's menu is a way in as well.
        let first = posted(script)
        #expect(first.count == 1)
        #expect(first.first?["kind"] as? String == "image")
        #expect(first.first?["url"] as? String == Self.address("?v=" + Self.version))
        #expect(first.first?["name"] as? String == "plate_map.png")
        #expect(watching(script) == 1)
        script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
        #expect(shape(script) == Self.grouped)
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test(arguments: [
        ("the picture", "__tileImg", "[__tileImg, __tileBox, __tile]"),
        ("the layer over it", "__layer", "[__layer, __tileImg, __tileBox, __tile]"),
        ("a marker in the layer", "__marker", "[__marker, __layer, __tileImg, __tileBox, __tile]"),
        ("an inline figure", "__inlineImg", "[__inlineImg, __inline, __page]"),
        ("the surface over an inline figure", "__surface", "[__surface, __inlineImg, __inline, __page]"),
        ("the layer in that surface", "__inlineLayer", "[__inlineLayer, __surface, __inlineImg, __inline, __page]"),
        ("a tray thumbnail", "__thumb", "[__thumb, __thumbBox, __card, __cardWrap, __tray]"),
        ("a tray card's words", "__captionText", "[__captionText, __caption, __card, __cardWrap, __tray]"),
    ])
    func everyPlaceAFigureCanBeRightClickedGetsTheItems(_ place: String, _ target: String, _ under: String) {
        let script = page()
        script.evaluate("__rightClick(\(target), { under: \(under) })")
        script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
        #expect(shape(script) == Self.grouped, "\(place)")
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["action"] as? String == "addToShelf", "\(place)")
        #expect(sent?["version"] as? String == Self.version, "\(place)")
        #expect(sent?["kind"] as? String == "image", "\(place)")
        #expect(script.exception == nil, "\(place): \(script.exception ?? "")")
    }

    @Test func aFigureIsNamedByItsAltText() {
        let script = page()
        script.evaluate("__rightClick(__inlineImg, { under: [__inlineImg] })")
        script.evaluate("__openMenu()")
        script.evaluate("__click(__ours()[2])")
        #expect(posted(script).last?["name"] as? String == "Z prime by plate")
        #expect(posted(script).last?["action"] as? String == "keep")
    }

    @Test func aFileLinkWithAVersionAlsoGetsThemInAPageMenu() {
        let script = page()
        script.evaluate("__rightClick(__link)")
        script.evaluate("__openMenu()")
        #expect(shape(script) == Self.grouped)
        script.evaluate("__click(__ours()[4])")
        let sent = posted(script).last
        #expect(sent?["action"] as? String == "showInResults")
        #expect(sent?["kind"] as? String == "link")
        #expect(sent?["name"] as? String == "qc_notes.md")
    }

    // MARK: How the items look

    @Test func theItemsAreDrawnWithTheMenusOwnClasses() {
        // The red item comes first here: the copy is of the first one that isn't.
        let script = page(ruleClass: "page-made-rule")
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['!Delete', 'Copy image', '-', 'Open in split view'])")
        let drawn = json(script, """
            __ours().map(function (b) {
              return { tag: b.localName, role: b.attrs.role, type: b.attrs.type, cls: b.className,
                       box: b.children.length ? b.children[0].attrs : null,
                       drawn: b.children.length ? b.children[0].children.map(function (c) { return c.localName; }) : null,
                       boxText: b.children.length ? b.children[0].textContent : null,
                       own: b.childNodes.length };
            })
            """) as? [[String: Any]]
        #expect(drawn?.count == 5)
        let rule = drawn?.first
        #expect(rule?["tag"] as? String == "div")
        // The page has a rule in this menu, so it is the one copied.
        #expect(rule?["cls"] as? String == "page-made-rule")
        for item in drawn?.dropFirst() ?? [] {
            #expect(item["tag"] as? String == "button")
            #expect(item["role"] as? String == "menuitem")
            #expect(item["type"] as? String == "button")
            #expect(item["cls"] as? String == FakeFigurePage.itemClass)
            // The icon box is the page's own, emptied: its attributes, no glyph, one drawing of Capsid's.
            let box = item["box"] as? [String: Any]
            #expect(box?["data-cds"] as? String == "Icon")
            #expect(box?["aria-hidden"] as? String == "true")
            #expect(box?["style"] as? String == "font-size: 16px; font-weight: 400;")
            #expect(item["drawn"] as? [String] == ["svg"])
            #expect(item["boxText"] as? String == "")
            #expect(item["own"] as? Int == 2)
        }
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aMenuWithNoRuleGetsThePagesOwnClassesByTheirNames() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image'])")
        #expect(script.evaluate("__ours()[0].className") == FakeFigurePage.ruleClass)
    }

    @Test func aMenuWithItemsThatHaveNoIconBoxGetsItemsWithNone() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image', 'Open in split view'], { icons: false })")
        #expect(script.evaluate("String(__ours().slice(1).every(function (b) { return b.children.length === 0; }))") == "true")
        #expect(shape(script) == Self.grouped)
    }

    @Test func theScriptNeverReadsTheWordsOfThePagesItems() {
        // The fake throws on any read of an item's text. Prove it does, then
        // that a whole round (open, place, restore, click) never trips it.
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image', '!Delete'])")
        script.evaluate("__ours().forEach(function (b) { b.remove(); }); __flush();")
        script.evaluate("__click(__ours()[1])")
        #expect(script.exception == nil, "\(script.exception ?? "")")
        #expect(script.evaluate("""
            (function () { try { __wrapper.querySelector('[role="menuitem"]'); } catch (e) {}
            var probe = el("button", {}, null); probe.__guard = true;
            try { probe.textContent; return "readable"; } catch (e) { return "guarded"; } })()
            """) == "guarded")
    }

    @Test func theMenuIsKeptOnScreenWithTheNewItemsIn() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        // Placed by the page to fit two items; four more and a rule run it off the bottom and the right.
        script.evaluate("__openMenu(['Copy image', 'Open in split view'], { top: 610, left: 900 })")
        #expect(script.evaluate("__menu.style.top") == "479px")
        #expect(script.evaluate("__menu.style.left") == "772px")
        #expect(script.evaluate("String(__menu.getBoundingClientRect().bottom <= 692 && __menu.getBoundingClientRect().right <= 992)") == "true")
        // One high on the screen is left where the page put it.
        let high = page()
        high.evaluate("__rightClick(__tileImg)")
        high.evaluate("__openMenu(['Copy image', 'Open in split view'])")
        #expect(high.evaluate("__menu.style.top") == "60px")
        #expect(high.evaluate("__menu.style.left") == "40px")
    }

    // MARK: A short window, or a page zoomed

    /// The page's menu for a figure with every item it has, a red Delete last: 7 buttons and 2 rules of its own,
    /// which with Capsid's rule and four items make a box 391 CSS pixels tall in the fake (the review's number).
    static let full = "['Copy image', 'Open in Artifact Viewer', '-', 'Open in split view', 'Provenance', 'Copy link', 'Download', '-', '!Delete']"
    static let fullGrouped = ["page:Copy image", "page:Open in Artifact Viewer", "page-rule", "page:Open in split view", "page:Provenance",
                              "page:Copy link", "page:Download", "rule"] + words.map { "ours:" + $0 } + ["page-rule", "page:Delete"]

    /// A page whose window is `height` CSS pixels tall (a short window, or one at 200 to 300% page zoom, which is the
    /// same thing in CSS pixels) with a figure right-clicked and the full menu open at `top`; `own` is what the page
    /// itself put on the menu's style, if anything (`maxHeight: "500px"`).
    private func menuInWindow(height: Int, top: Int = 60, own: String = "") -> PageScript {
        let script = page()
        script.evaluate("window.innerHeight = \(height)")
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(\(Self.full), { top: \(top)\(own.isEmpty ? "" : ", " + own) })")
        #expect(script.exception == nil, "\(script.exception ?? "")")
        return script
    }

    private struct Box { var top = -1.0, bottom = -1.0, maxHeight = "?", overflowY = "?" }

    private func box(_ script: PageScript, _ menu: String = "__menu") -> Box {
        let found = json(script, """
            (function () { var r = \(menu).getBoundingClientRect();
              return { top: r.top, bottom: r.bottom, maxHeight: \(menu).style.maxHeight || "", overflowY: \(menu).style.overflowY || "" }; })()
            """) as? [String: Any]
        return Box(top: found?["top"] as? Double ?? -1, bottom: found?["bottom"] as? Double ?? -1,
                   maxHeight: found?["maxHeight"] as? String ?? "?", overflowY: found?["overflowY"] as? String ?? "?")
    }

    @Test func aShortWindowGivesTheMenuAMaximumHeightAndScrolling() {
        // The review's case: a window 280 tall, where the menu came out at top 8, height 391, bottom 399.
        let script = menuInWindow(height: 280)
        let found = box(script)
        #expect(found.maxHeight == "264px", "the window's height less 8 above and 8 below")
        #expect(found.overflowY == "auto")
        #expect(found.top == 8)
        #expect(found.bottom <= 272, "all of it is in the window: \(found)")
        // Every item is still there, in order, the red one last.
        #expect(shape(script) == Self.fullGrouped)
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aTallWindowLeavesTheMenusHeightAlone() {
        let script = menuInWindow(height: 700)
        let found = box(script)
        #expect(found.maxHeight == "" && found.overflowY == "", "nothing is set when the menu fits: \(found)")
        #expect(found.top == 60)
        #expect(shape(script) == Self.fullGrouped)
    }

    @Test func theLimitFollowsTheWindowToTheLastPixel() {
        for height in [200, 300, 390] {
            let found = box(menuInWindow(height: height))
            #expect(found.maxHeight == "\(height - 16)px", "\(height)")
            #expect(found.top >= 8 && found.bottom <= Double(height - 8), "\(height): \(found)")
        }
        // 391 tall with 8 above and 8 below fits a window of 407 and no less.
        #expect(box(menuInWindow(height: 407)).maxHeight == "")
        #expect(box(menuInWindow(height: 406)).maxHeight == "390px")
    }

    @Test func theLimitIsGivenUpWhenTheMenuGoesAndTheNewMenuGetsItsOwn() {
        let script = menuInWindow(height: 280)
        script.evaluate("var __old = __menu")
        // The page draws the menu again, as a new element, in the same turn as the old one goes.
        script.evaluate("__wrapper.remove(); __openMenu(\(Self.full), { top: 60 });")
        #expect(script.evaluate("String(__old.isConnected)") == "false")
        #expect(box(script, "__old").maxHeight == "" && box(script, "__old").overflowY == "", "the old element keeps nothing of Capsid's")
        #expect(box(script).maxHeight == "264px" && box(script).overflowY == "auto" && box(script).top == 8)
        // It closes: nothing is left on it either.
        script.evaluate("var __second = __menu; __closeMenu(); __flush();")
        #expect(box(script, "__second").maxHeight == "" && box(script, "__second").overflowY == "")
        #expect(watching(script) == 0)
    }

    @Test func aMenuThePageDrawsAgainWithoutTheItemsGetsThemBackAndStillScrolls() {
        let script = menuInWindow(height: 280)
        script.evaluate("__ours().forEach(function (b) { b.remove(); }); __flush();")
        #expect(shape(script) == Self.fullGrouped)
        let found = box(script)
        #expect(found.maxHeight == "264px" && found.overflowY == "auto")
        #expect(found.top == 8 && found.bottom <= 272)
    }

    @Test func aHeightTheMenuHadIsGivenBackAndOneThatAlreadyFitsIsLeft() {
        // A limit the page put on the menu itself, larger than the window: ours replaces it, and it comes back.
        let script = menuInWindow(height: 280, own: "maxHeight: '500px'")
        #expect(box(script).maxHeight == "264px")
        script.evaluate("var __kept = __menu; __closeMenu(); __flush();")
        #expect(box(script, "__kept").maxHeight == "500px", "what the page had is what is left")
        // One smaller than the window already keeps the menu inside it: not touched.
        let small = menuInWindow(height: 280, own: "maxHeight: '200px', overflowY: 'scroll'")
        let found = box(small)
        #expect(found.maxHeight == "200px" && found.overflowY == "scroll", "\(found)")
        #expect(found.bottom <= 272)
    }

    @Test func theLimitStaysWhileTheItemsAreInTheMenuEvenAfterTheWatchEnds() {
        let script = menuInWindow(height: 280)
        // The longest the items are looked after (two minutes): the menu is still open with them in it.
        script.evaluate("__advance(120001)")
        #expect(watching(script) == 0)
        #expect(box(script).maxHeight == "264px", "let go now, the menu would spill over the window again")
    }

    @Test func theKeyboardReachesTheItemsThroughThePagesOwnArrowKeys() {
        // The page's arrow keys stop at every `[role='menuitem']` in the menu
        // (and every enabled button), looked up at each key press; Enter on a
        // focused button is a real click. Both are true of Capsid's buttons.
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
        #expect(script.evaluate("String(__arrowStops(__menu).length)") == "6")
        #expect(script.evaluate("String(__ours().slice(1).every(function (b) { return __arrowStops(__menu).indexOf(b) >= 0 && b.localName === 'button'; }))") == "true")
    }

    // MARK: Choosing

    @Test func choosingEachItemTellsSwiftWhichAndClosesThePagesMenu() {
        for (index, action) in Self.actions.enumerated() {
            let script = page()
            script.evaluate("__rightClick(__tileImg)")
            script.evaluate("__openMenu()")
            script.evaluate("var __e = __click(__ours()[\(index + 1)])")
            let sent = posted(script).last
            #expect(sent?["action"] as? String == action)
            #expect(sent?["version"] as? String == Self.version)
            #expect(sent?["name"] as? String == "plate_map.png")
            #expect(sent?["kind"] as? String == "image")
            // The page's own hook closed it (Escape on the document), and the watch is over.
            #expect(script.evaluate("String(__menu === null)") == "true", "\(action)")
            #expect(watching(script) == 0, "\(action)")
            #expect(script.evaluate("String(__e.defaultPrevented)") == "true")
            script.evaluate("__advance(200)")
            #expect(script.evaluate("String(__liveTimers())") == "0", "nothing left running: \(action)")
            #expect(script.exception == nil, "\(script.exception ?? "")")
        }
    }

    @Test func ifEscapeDoesNotCloseTheMenuAClickOutsideDoes() {
        let script = page()
        script.evaluate("__ignoreEscape = true")
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        script.evaluate("__click(__ours()[1])")
        #expect(script.evaluate("String(__menu !== null)") == "true")
        script.evaluate("__advance(79)")
        #expect(script.evaluate("String(__menu !== null)") == "true")
        script.evaluate("__advance(2)")
        #expect(script.evaluate("String(__menu === null)") == "true")
    }

    @Test func aClickThatIsNotARealOneDoesNothing() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        script.evaluate("__click(__ours()[1], false)")
        #expect(posted(script).count == 1, "only the right-click's own message")
        #expect(script.evaluate("String(__menu !== null)") == "true")
        #expect(shape(script) == Self.grouped)
        // And a real one afterwards still works.
        script.evaluate("__click(__ours()[1])")
        #expect(posted(script).last?["action"] as? String == "addToShelf")
    }

    @Test func choosingAFigureAfterAnotherUsesTheLatestOne() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        // Another figure: the page closes the old menu on the pointer-down.
        script.evaluate("__closeMenu(); __flush();")
        script.evaluate("__rightClick(__inlineImg)")
        script.evaluate("__openMenu()")
        script.evaluate("__click(__ours()[3])")
        #expect(posted(script).last?["name"] as? String == "Z prime by plate")
        #expect(posted(script).last?["action"] as? String == "openAsReference")
    }

    // MARK: Nothing added

    @Test func aRightClickElsewhereAddsNothing() {
        let script = page()
        for target in ["__paragraph", "__page", "__plainLink", "__avatar", "__elsewhere", "__card2", "__captionText2"] {
            script.evaluate("__rightClick(\(target))")
            #expect(watching(script) == 0, "\(target)")
            script.evaluate("__openMenu(['Copy image', 'Open in split view'])")
            #expect(shape(script) == ["page:Copy image", "page:Open in split view"], "\(target)")
            script.evaluate("__closeMenu(); __flush();")
        }
        let sent = posted(script)
        // Every one was heard, and the pictures and links among them said what they were.
        #expect(sent.count == 7)
        #expect(sent.filter { $0["kind"] is NSNull }.count == 4)
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aTileWithNoKnownVersionAddsNothing() {
        // A picture whose address names no version, in the same layers as a tile's.
        let script = page()
        script.evaluate("__tileImg.attrs.src = 'http://localhost:8123/static/chart.png'")
        script.evaluate("__rightClick(__layer, { under: [__layer, __tileImg, __tileBox, __tile] })")
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"])
        // A markdown tile has no picture of its own at all.
        let text = page()
        text.evaluate("__rightClick(__modalText, { under: [__modalText, __modal] })")
        text.evaluate("__openMenu()")
        #expect(shape(text) == ["page:Copy image", "page:Open in split view"])
    }

    @Test func aPopUpOverTheConversationDoesNotTakeAFigureBeneathIt() {
        // The pointer is over the pop-up's text, with a tile's picture under it in the stack.
        let script = page()
        script.evaluate("__rightClick(__modalText, { under: [__modalText, __modal, __layer, __tileImg, __tileBox, __tile, __page] })")
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"])
        #expect(posted(script).count == 1)
        #expect(posted(script).first?["kind"] is NSNull)
    }

    @Test func aMenuThatComesAfterTwoSecondsGetsNothing() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__advance(1999)")
        #expect(watching(script) == 1)
        script.evaluate("__advance(2)")
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"])
        #expect(script.evaluate("String(__liveTimers())") == "0")
        // Just inside the two seconds is in time.
        let inTime = page()
        inTime.evaluate("__rightClick(__tileImg)")
        inTime.evaluate("__advance(1999)")
        inTime.evaluate("__openMenu()")
        #expect(shape(inTime) == Self.grouped)
    }

    @Test func aRightClickAnywhereElseEndsTheWatch() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        #expect(watching(script) == 1)
        script.evaluate("__rightClick(__paragraph)")
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"])
        // The same once the items are in: the next right-click ends the care of the old menu.
        let placed = page()
        placed.evaluate("__rightClick(__tileImg)")
        placed.evaluate("__openMenu()")
        placed.evaluate("__rightClick(__paragraph)")
        #expect(watching(placed) == 0)
        placed.evaluate("__ours().forEach(function (b) { b.remove(); }); __flush();")
        #expect(shape(placed) == ["page:Copy image", "page:Open in split view"], "not put back once the watch is over")
    }

    @Test func aMadeUpRightClickStartsNothingAndEndsNothing() {
        let script = page()
        script.evaluate("__rightClick(__tileImg, { trusted: false })")
        #expect(posted(script).isEmpty)
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"])
        // And one made up by the page doesn't end a real one's watch.
        let real = page()
        real.evaluate("__rightClick(__tileImg)")
        real.evaluate("__rightClick(__paragraph, { trusted: false })")
        #expect(watching(real) == 1)
        real.evaluate("__openMenu()")
        #expect(shape(real) == Self.grouped)
    }

    @Test func theScriptDoesNothingOffTheDaemonsPageOrWithoutItsHandler() {
        func listeners(_ setup: String) -> String? {
            let script = PageScript()
            script.set("__VERSION", Self.version)
            script.set("__MENU", FakeFigurePage.menuClass)
            script.set("__ITEM", FakeFigurePage.itemClass)
            script.set("__DANGER", FakeFigurePage.dangerClass)
            script.set("__RULE", FakeFigurePage.ruleClass)
            script.evaluate(FakeFigurePage.source)
            script.evaluate(setup)
            script.evaluate(ConversationMenu.script)
            return script.evaluate("String(document.__listeners.filter(function (l) { return l.type === 'contextmenu'; }).length)")
        }
        #expect(listeners("") == "1")
        #expect(listeners("location.hostname = '127.0.0.1';") == "1")
        #expect(listeners("location.hostname = 'example.com';") == "0")
        #expect(listeners("location.protocol = 'https:';") == "0")
        #expect(listeners("window.webkit = undefined;") == "0")
        #expect(listeners("window.webkit.messageHandlers = {};") == "0")
    }

    // MARK: The page's menu comes back

    @Test func aMenuDrawnAgainWithoutTheItemsGetsThemBack() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        script.evaluate("var __first = __ours();")
        // The page redraws the menu's children and leaves Capsid's out.
        script.evaluate("__ours().forEach(function (b) { b.remove(); }); __flush();")
        #expect(shape(script) == Self.grouped)
        script.evaluate("__ours().slice(0, 2).forEach(function (b) { b.remove(); }); __flush();")
        #expect(shape(script) == Self.grouped)
        // The same four buttons, so a click still means the same thing.
        #expect(script.evaluate("String(__ours().every(function (b, i) { return b === __first[i]; }))") == "true")
        script.evaluate("__click(__ours()[4])")
        #expect(posted(script).last?["action"] as? String == "showInResults")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aMenuDrawnAgainAsANewOneGetsTheItems() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        // The page throws the menu away and draws another, in one go.
        script.evaluate("__closeMenu(); __openMenu(['Copy image']);")
        #expect(shape(script) == ["page:Copy image", "rule"] + Self.words.map { "ours:" + $0 })
        script.evaluate("__click(__ours()[2])")
        #expect(posted(script).last?["action"] as? String == "keep")
    }

    @Test func anItemTheRedrawAddsAfterOursPutsTheGroupBackLast() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        script.evaluate("__guarded(__item(__menu, 'Late item')); __flush();")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view", "page:Late item", "rule"] + Self.words.map { "ours:" + $0 })
        script.evaluate("__click(__ours()[3])")
        #expect(posted(script).last?["action"] as? String == "openAsReference")
    }

    // MARK: With a red item in the page's menu

    /// The words of Capsid's group, after its own rule.
    private static let group = ["rule"] + words.map { "ours:" + $0 }

    @Test func aMenuWithADeleteGetsTheGroupAboveItsRuleAndIt() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image', 'Open in split view', '-', '!Delete'])")
        // …, Open in split view, [our rule], the four, [the page's rule], Delete.
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"] + Self.group + ["page-rule", "page:Delete"])
        script.evaluate("__click(__ours()[3])")
        #expect(posted(script).last?["action"] as? String == "openAsReference")
    }

    @Test func aDeleteWithNoRuleAboveItGetsTheGroupJustBeforeIt() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image', '!Delete'])")
        #expect(shape(script) == ["page:Copy image"] + Self.group + ["page:Delete"])
    }

    @Test func aRedItemFirstGetsTheGroupBeforeItAndTheTemplateIsNotRed() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['!Delete', 'Copy image', '-', 'Open in split view'])")
        #expect(shape(script) == Self.group + ["page:Delete", "page:Copy image", "page-rule", "page:Open in split view"])
        #expect(script.evaluate("String(__ours().slice(1).every(function (b) { return b.className === \(FakeFigurePage.itemClass.debugDescription); }))") == "true")
    }

    @Test func aDeleteGroupDrawnAgainGetsTheGroupBackAboveIt() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Copy image', 'Open in split view', '-', '!Delete'])")
        let placed = ["page:Copy image", "page:Open in split view"] + Self.group + ["page-rule", "page:Delete"]
        script.evaluate("var __first = __ours();")
        // The page redraws and leaves Capsid's out: they come back above the page's rule, the same buttons.
        script.evaluate("__ours().forEach(function (b) { b.remove(); }); __flush();")
        #expect(shape(script) == placed)
        #expect(script.evaluate("String(__ours().every(function (b, i) { return b === __first[i]; }))") == "true")
        // An item the page adds after Delete leaves the group where it is.
        script.evaluate("__guarded(__item(__menu, 'After delete')); __flush();")
        #expect(shape(script) == placed + ["page:After delete"])
        // One it puts between the group and the rule above Delete: the group goes after it.
        script.evaluate("var __late = __guarded(__item(__menu, 'Late')); __menu.insertBefore(__late, __menu.children[__menu.children.length - 4]); __flush();")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view", "page:Late"] + Self.group + ["page-rule", "page:Delete", "page:After delete"])
        // And one it puts between Capsid's items: the group is made one run again.
        script.evaluate("var __mid = __guarded(__item(__menu, 'Middle')); __menu.insertBefore(__mid, __ours()[3]); __flush();")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view", "page:Late", "page:Middle"] + Self.group + ["page-rule", "page:Delete", "page:After delete"])
        script.evaluate("__click(__ours()[2])")
        #expect(posted(script).last?["action"] as? String == "keep")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func onceTheItemsAreInOnlyTheMenuAndWhatItSitsInAreWatched() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        // Looking for the menu, the whole page is watched; each mutation anywhere is looked at.
        #expect(script.evaluate("String(__observers.filter(function (o) { return o.active; })[0].targets[0].options.subtree)") == "true")
        script.evaluate("__openMenu()")
        #expect(watching(script) == 1)
        // Then three places, one level each: no mutation elsewhere in the conversation is looked at.
        #expect(script.evaluate("String(__observers.filter(function (o) { return o.active; })[0].targets.length)") == "3")
        #expect(script.evaluate("String(__observers.filter(function (o) { return o.active; })[0].targets.every(function (t) { return !t.options.subtree; }))") == "true")
        let before = script.evaluate("String(__observers.filter(function (o) { return o.active; })[0].deliveries)")
        script.evaluate("el('span', {}, __page); el('span', {}, __paragraph); __flush();")
        #expect(script.evaluate("String(__observers.filter(function (o) { return o.active; })[0].deliveries)") == before)
        #expect(shape(script) == Self.grouped)
    }

    @Test func whenTheMenuClosesTheWatchEndsAndALaterMenuGetsNothing() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        #expect(watching(script) == 1)
        script.evaluate("__closeMenu(); __flush();")
        #expect(watching(script) == 0)
        script.evaluate("__openMenu()")
        #expect(shape(script) == ["page:Copy image", "page:Open in split view"])
        #expect(script.evaluate("String(__liveTimers())") == "0")
    }

    @Test func itLooksAfterAMenuOnlyForTwoMinutes() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu()")
        script.evaluate("__advance(119999)")
        #expect(watching(script) == 1)
        script.evaluate("__advance(2)")
        #expect(watching(script) == 0)
        // The items it put in stay in the menu that is still open.
        #expect(shape(script) == Self.grouped)
    }

    // MARK: A menu that isn't the figure's, or has nothing to copy

    @Test func aMenuWithNothingToCopyIsAMissAndTheItemsGoNowhere() {
        for items in ["[]", "['!Delete']"] {
            let script = page()
            script.evaluate("__rightClick(__tileImg)")
            script.evaluate("__openMenu(\(items))")
            #expect(posted(script).last?["unplaced"] as? Bool == true, "\(items)")
            #expect(shape(script) == (items == "[]" ? [] : ["page:Delete"]), "\(items)")
            #expect(watching(script) == 0, "\(items)")
        }
    }

    @Test func anotherMenuIsLeftAloneAndIsNoMiss() {
        let script = page()
        script.evaluate("__rightClick(__tileImg)")
        script.evaluate("__openMenu(['Settings', 'Sign out'], { label: 'Account' })")
        #expect(shape(script) == ["page:Settings", "page:Sign out"])
        #expect(posted(script).count == 1, "no breadcrumb for a menu that isn't the figure's")
        // The watch goes on for the figure's own menu until the two seconds are up.
        #expect(watching(script) == 1)
        script.evaluate("__closeMenu(); __flush(); __openMenu();")
        #expect(shape(script) == Self.grouped)
    }

    // MARK: What the script says to Swift, as before

    @Test func itListensForContextMenusInTheCapturePhase() {
        let script = page()
        #expect(script.evaluate("document.__listeners.filter(function (l) { return l.type === 'contextmenu'; }).map(function (l) { return l.type + ':' + l.capture; }).join(',')") == "contextmenu:true")
    }

    @Test func aRightClickOnAFigureNamesItsAddressAndAlt() {
        let script = page()
        script.evaluate("__rightClick(__thumb)")
        let sent = posted(script)
        #expect(sent.count == 1)
        #expect(sent.first?["kind"] as? String == "image")
        #expect(sent.first?["url"] as? String == Self.address("?thumbnail=400"))
        #expect(sent.first?["name"] as? String == "z_prime.png")
        #expect(script.exception == nil)
    }

    @Test func aFigureWithNoCurrentSourceUsesItsSrcAndTitle() {
        let script = page()
        script.evaluate("""
            var __l2 = el("a", { href: __address() }, __page);
            var __i2 = el("img", { src: __address(), title: "A plot" }, __l2);
            __rightClick(__i2);
            """)
        // The picture, not the link around it.
        #expect(posted(script).first?["kind"] as? String == "image")
        #expect(posted(script).first?["url"] as? String == Self.address())
        #expect(posted(script).first?["name"] as? String == "A plot")
    }

    @Test func aRightClickOnALinkOrItsTextNamesTheLink() {
        let script = page()
        script.evaluate("""
            var __inLink = el("span", {}, __link);
            __rightClick(__link); __rightClick(__inLink); __rightClick(__link.childNodes[0]);
            """)
        let sent = posted(script)
        #expect(sent.count == 3)
        for message in sent {
            #expect(message["kind"] as? String == "link")
            #expect(message["url"] as? String == "http://localhost:8123/projects/p1/artifacts/a1?v=\(Self.version)")
            #expect(message["name"] as? String == "qc_notes.md")
        }
    }

    @Test func aRightClickAnywhereElseSaysNone() {
        let script = page()
        script.evaluate("__rightClick(document.body); __rightClick(__paragraph); __rightClick(__paragraph.childNodes[0]);")
        script.evaluate("__direct(null); __direct({ nodeType: 3, parentElement: null });")
        let sent = posted(script)
        #expect(sent.count == 5)
        for message in sent { #expect(message["kind"] is NSNull) }
        #expect(script.exception == nil)
    }

    // MARK: The same address rule as Swift's

    @Test func theScriptFindsTheVersionsSwiftWould() {
        let v = Self.version
        let upper = v.uppercased()
        let table = [
            "/api/artifacts/versions/\(v)", "/api/artifacts/versions/\(v)?thumbnail=800", "/api/artifacts/versions/\(v)?v=\(v)",
            "/api/artifacts/versions/\(v)/download", "/api/artifacts/versions/\(v)/raw", "/api/artifacts/versions/\(v)/content",
            "/api/artifacts/versions/\(v)/file", "/api/artifacts/versions/\(v)/thumbnail", "/api/artifacts/versions/\(v)/lineage",
            "/api/artifacts/versions/\(v)/", "/api/artifacts/versions/\(v)/download/x", "/api/artifacts/versions/",
            "/api/artifacts/versions", "/api/artifacts/versions/\(upper)", "/api/artifacts/versions/1c8d3a5f",
            "/api/artifacts/\(v)/thumbnail", "/projects/p/artifacts/a?v=\(v)", "/x?version=\(v)", "/x?version_id=\(v)",
            "/x?versionId=\(v)", "/x?foo=\(v)", "/x?v=short&v=\(v)", "/x?v=short", "/x?v=\(upper)", "/static/avatar.png", "/",
        ]
        for tail in table {
            let address = "http://localhost:8123" + tail
            let expected = ShelfAddress.version(in: address, daemonPort: 8123)
            let script = page()
            script.set("__ADDRESS", address)
            script.evaluate("__avatar.attrs.src = __ADDRESS; __rightClick(__avatar); __openMenu();")
            let found = chosenVersion(script)
            #expect(found == expected, "\(tail)")
            #expect(script.exception == nil, "\(tail): \(script.exception ?? "")")
        }
        // On another origin the script says no; Swift would too for these.
        for address in ["http://localhost:9999/api/artifacts/versions/\(v)", "https://localhost:8123/api/artifacts/versions/\(v)",
                        "https://example.com/api/artifacts/versions/\(v)", "blob:http://localhost:8123/\(v)", "data:image/png;base64,AAAA"] {
            let script = page()
            script.set("__ADDRESS", address)
            script.evaluate("__avatar.attrs.src = __ADDRESS; __rightClick(__avatar); __openMenu();")
            #expect(chosenVersion(script) == nil, "\(address)")
            #expect(ShelfAddress.version(in: address, daemonPort: 8123) == nil, "\(address)")
        }
        // A very long address is nobody's.
        let script = page()
        script.set("__ADDRESS", "http://localhost:8123/api/artifacts/versions/\(v)?pad=" + String(repeating: "a", count: 4_100))
        script.evaluate("__avatar.attrs.src = __ADDRESS; __rightClick(__avatar); __openMenu();")
        #expect(chosenVersion(script) == nil)
    }

    /// The version the first of Capsid's items posts when chosen, or nil if the menu has none.
    private func chosenVersion(_ script: PageScript) -> String? {
        guard script.evaluate("String(__ours().length)") != "0" else { return nil }
        script.evaluate("__click(__ours()[1])")
        return posted(script).last?["version"] as? String
    }

    // MARK: Where the page's words are

    @Test func theScriptOnlyReadsTheNamesOfTheMenuAndNeverItsWords() {
        let text = ConversationMenu.script
        #expect(!text.contains("fetch("))
        #expect(!text.contains("innerHTML"))
        #expect(!text.contains("outerHTML"))
        #expect(!text.contains("eval("))
        // The only textContent it reads is a file link's own name; nothing of a menu item.
        #expect(text.components(separatedBy: "textContent").count == 2)
        #expect(text.contains("found.textContent"))
        #expect(!text.contains("innerText"))
        // The four words are the ones the Mac's menu has.
        for word in Self.words { #expect(text.contains(word)) }
    }

    private static func address(_ tail: String = "") -> String {
        "http://localhost:8123/api/artifacts/versions/\(version)\(tail)"
    }
}
