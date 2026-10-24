// ModelMenuScriptTests.swift — "Ask Another Model…" inside Claude Science's own
// model menu (AskModel/ModelPickerMenu.swift, the page side), run in
// JavaScriptCore against a made-up page (FakeModelPage): a press on the model
// picker, the page's popup opening after it, a rule and one item added at the
// end of its list, a click on the item with the message box's draft, and the
// popup closing; and everything that must add nothing. The page's popup in that
// fake is guarded, so a script that read the words of its items would fail
// here. How the menu looks is checked by eye (ModelMenuSnapshotTests); the real
// page's behaviour only by a real click (TESTING.md).
import Foundation
import Testing
@testable import Bench

struct ModelMenuScriptTests {
    static let title = "Ask Another Model\u{2026}"
    /// What the made-up popup's list looks like before the item: the models in one group, a rule, "More models".
    static let before = ["page-group:Large+Medium+Small", "page-rule", "page:More models"]
    /// …and after it.
    static let after = before + ["rule", "ours:" + title]

    /// A page with the script loaded. `host` is where it is served from, `show` what Swift will answer.
    private func page(host: String = "localhost", show: String = "true", handler: Bool = true,
                      ruleClass: String = FakeModelPage.ruleClass) -> PageScript {
        let script = PageScript()
        script.set("__ITEM", FakeModelPage.itemClass)
        script.set("__SECOND", FakeModelPage.secondLine)
        script.set("__POPUP", FakeModelPage.popupClass)
        script.set("__LIST", FakeModelPage.listClass)
        script.set("__SUBMENU", FakeModelPage.submenuClass)
        script.set("__RULE", ruleClass)
        script.evaluate(FakeModelPage.source)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        script.evaluate("__show = \(show);")
        script.evaluate("location = { protocol: 'http:', hostname: '\(host)', origin: 'http://\(host):8123', href: 'http://\(host):8123/' };")
        if !handler { script.evaluate("window.webkit = undefined;") }
        script.evaluate(ModelPickerMenu.script)
        #expect(script.exception == nil, "\(script.exception ?? "")")
        return script
    }

    private func json(_ script: PageScript, _ expression: String) -> Any? {
        let text = script.evaluate("JSON.stringify(\(expression))") ?? "null"
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    private func all(_ script: PageScript) -> [[String: Any]] {
        (json(script, "__posted") as? [[String: Any]]) ?? []
    }

    /// What the script posted, its traces left out (they are `traces`).
    private func posted(_ script: PageScript) -> [[String: Any]] {
        all(script).filter { $0["trace"] == nil }
    }

    /// The traces the script posted, one list of words per press.
    private func traces(_ script: PageScript) -> [[String]] {
        all(script).compactMap { $0["trace"] as? [String] }
    }

    private func shape(_ script: PageScript) -> [String] {
        (json(script, "__shape()") as? [String]) ?? []
    }

    private func watching(_ script: PageScript) -> Int {
        Int(script.evaluate("String(__watching())") ?? "") ?? -1
    }

    private func timers(_ script: PageScript) -> Int {
        Int(script.evaluate("String(__liveTimers())") ?? "") ?? -1
    }

    private func armed(_ script: PageScript) -> Int {
        posted(script).filter { $0["armed"] != nil }.count
    }

    /// The draft the last choice carried.
    private func draft(_ script: PageScript) -> String? {
        posted(script).last(where: { $0["ask"] != nil })?["draft"] as? String
    }

    // MARK: The item, after a press on the picker

    @Test func aPressOnThePickerThenItsMenuOpeningGetsTheItemLast() {
        let script = page()
        #expect(watching(script) == 0, "nothing is watched until the picker is pressed")
        script.evaluate("__press(__picker)")
        #expect(armed(script) == 1)
        #expect(watching(script) == 1)
        script.evaluate("__openPopup()")
        #expect(shape(script) == Self.after)
        #expect(traces(script) == [["armed", "allowed", "menu-matched", "placed"]])
        // From here only the menu is watched, and nothing waits for the two seconds any more.
        #expect(watching(script) == 1)
        #expect(script.evaluate("String(__liveTimers())") == "1", "the two minutes' hold, and no more")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aMenuThatOpensBeforeTheAnswerComesGetsTheItemWhenItDoes() {
        let script = page()
        // One turn of the page: the press, the menu, and only then the answer (a promise, run when the turn ends).
        script.evaluate("__press(__picker); __openPopup();")
        #expect(shape(script) == Self.after)
        #expect(traces(script) == [["armed", "menu-matched", "allowed", "placed"]])
    }

    @Test(arguments: [
        ("the plain picker's menu", "{ variant: 'plain' }"),
        ("the catalog picker's menu", "{ variant: 'catalog' }"),
        ("a menu with a header above its list", "{ header: true }"),
        ("a menu with a closing note", "{ note: true }"),
        ("a menu with one model and no rule", "{ models: ['Large'], separators: false, more: false }"),
    ])
    func everyShapeOfThePickersMenuGetsTheItemAtTheEndOfItsList(_ name: String, _ options: String) {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup(\(options))")
        let ours = (json(script, "__ours().map(function (c) { return c.attrs.role || c.localName; })") as? [String]) ?? []
        #expect(ours == ["separator", "menuitem"], "\(name)")
        // Last in the page's list, and the list is the scrolling element, not the popup.
        #expect(script.evaluate("String(__list.children[__list.children.length - 1] === __ours()[1])") == "true", "\(name)")
        #expect(script.evaluate("String(__ours()[1].parentNode === __list && __list.hasAttribute('data-cds-sheet-scroll'))") == "true", "\(name)")
        #expect(script.exception == nil, "\(name): \(script.exception ?? "")")
    }

    @Test func thePickerOfAnotherComposerGetsItToo() {
        // The aside's picker is the button with the test id itself, not a wrapper round it.
        let script = page()
        script.evaluate("__press(__asidePicker)")
        script.evaluate("__openPopup()")
        #expect(shape(script) == Self.after)
    }

    // MARK: How the item looks

    @Test func theItemIsDrawnWithTheMenusOwnClasses() {
        let script = page(ruleClass: "page-made-rule")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        let drawn = json(script, """
            __ours().map(function (b) {
              return { tag: b.localName, role: b.attrs.role, tabindex: b.attrs.tabindex, cls: b.className,
                       own: b.childNodes.length, text: b.textContent, orientation: b.attrs["aria-orientation"] || null };
            })
            """) as? [[String: Any]]
        #expect(drawn?.count == 2)
        // The page has a rule in this menu, so it is the one copied.
        #expect(drawn?.first?["tag"] as? String == "div")
        #expect(drawn?.first?["role"] as? String == "separator")
        #expect(drawn?.first?["cls"] as? String == "page-made-rule")
        let item = drawn?.last
        // A div with the role of an item, the page's item classes less the padding of an item with a second line.
        #expect(item?["tag"] as? String == "div")
        #expect(item?["role"] as? String == "menuitem")
        #expect(item?["tabindex"] as? String == "-1")
        #expect(item?["cls"] as? String == FakeModelPage.itemClass)
        #expect((item?["cls"] as? String)?.contains("pb-[calc(") == false)
        #expect(item?["own"] as? Int == 1)
        #expect(item?["text"] as? String == Self.title)
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aMenuWithNoRuleGetsThePagesUsualClasses() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup({ separators: false })")
        #expect(script.evaluate("__ours()[0].className") == FakeModelPage.ruleClass)
    }

    @Test func theItemTakesTheClassesOfTheFirstItemEvenWhenItIsTheMoreModelsRow() {
        // No models at all: the first item is the row that opens a submenu.
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup({ models: [] })")
        #expect(shape(script).suffix(2) == ["rule", "ours:" + Self.title])
        #expect(script.evaluate("__ours()[1].className") == FakeModelPage.submenuClass)
    }

    @Test func theItemLightsUnderThePointerAsThePagesDo() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        #expect(script.evaluate("String(__ours()[1].hasAttribute('data-highlighted'))") == "false")
        script.evaluate("__dispatch(__ours()[1], new __Event('pointerenter', {}))")
        #expect(script.evaluate("String(__ours()[1].getAttribute('data-highlighted'))") == "")
        script.evaluate("__dispatch(__ours()[1], new __Event('pointerleave', {}))")
        #expect(script.evaluate("String(__ours()[1].hasAttribute('data-highlighted'))") == "false")
    }

    @Test func theScriptNeverReadsTheWordsOfThePagesItems() {
        // The fake throws on any read of an item's text. Prove it does, then that a
        // whole round (press, place, redraw, choose) never trips it.
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__redraw(); __click(__ours()[1]);")
        #expect(script.exception == nil, "\(script.exception ?? "")")
        #expect(script.evaluate("""
            (function () { var probe = el("div", {}, null); probe.__guard = true;
            try { probe.textContent; return "readable"; } catch (e) { return "guarded"; } })()
            """) == "guarded")
    }

    // MARK: Choosing it

    @Test func aClickOnTheItemPostsTheDraftAndClosesTheMenu() {
        let script = page()
        script.evaluate("__type(__box, ['Which buffer', { tag: 'br' }, 'should the rerun use?'])")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__click(__ours()[1])")
        let sent = posted(script).last
        #expect(sent?["ask"] as? Bool == true)
        #expect(sent?["draft"] as? String == "Which buffer\nshould the rerun use?")
        // Escape from inside the menu reaches the page's own hook, and the menu goes.
        #expect(script.evaluate("String(__popup === null)") == "true")
        // The press is done with: nothing is watched, and the pointer-down after 80 ms has nothing to do.
        #expect(watching(script) == 0)
        script.evaluate("__advance(200)")
        #expect(timers(script) == 0)
        #expect(script.evaluate("String(__popup === null)") == "true")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func aMenuThatIgnoresEscapeIsClosedByThePointerDownOutsideItEightyMillisecondsLater() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__ignoreEscape = true; __click(__ours()[1]);")
        #expect(script.evaluate("String(__popup !== null)") == "true")
        script.evaluate("__advance(79)")
        #expect(script.evaluate("String(__popup !== null)") == "true")
        script.evaluate("__advance(1)")
        #expect(script.evaluate("String(__popup === null)") == "true")
    }

    @Test(arguments: [
        ("nothing typed", "[]", ""),
        ("words", "['a question']", "a question"),
        ("a line break between words", "['one', { tag: 'br' }, 'two']", "one\ntwo"),
        ("a trailing line break", "['hello', { tag: 'br' }]", "hello"),
        ("spaces round it", "['  hello  ']", "hello"),
        ("blocks, one to a line", "[{ tag: 'div', words: 'first' }, { tag: 'div', words: 'second' }]", "first\nsecond"),
        ("a block after words", "['first', { tag: 'div', words: 'second' }]", "first\nsecond"),
        ("a chip for a file", "['see ', { tag: 'span', attrs: { contenteditable: 'false', 'data-mention-id': 'm1' }, words: '@plate_map.png' }, ' please']",
         "see @plate_map.png please"),
        ("the dictation not yet kept", "['kept ', { tag: 'span', attrs: { 'data-voice-ghost': 'true' }, words: 'ghost' }]", "kept"),
        ("an upload's chip", "['look ', { tag: 'span', attrs: { 'data-upload-status': 'uploading' }, words: 'plate.png 40%' }]", "look"),
        ("words inside a span", "[{ tag: 'span', children: ['in ', { tag: 'b', words: 'bold' }] }]", "in bold"),
    ])
    func theDraftIsWhatIsTypedInTheMessageBox(_ name: String, _ parts: String, _ expected: String) {
        let script = page()
        script.evaluate("__type(__box, \(parts))")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__click(__ours()[1])")
        #expect(draft(script) == expected, "\(name)")
        #expect(script.exception == nil, "\(name): \(script.exception ?? "")")
    }

    @Test func aLongDraftIsCutAtTheQuestionsLimit() {
        let script = page()
        script.set("__long", String(repeating: "x", count: AskRules.maxQuestion * 2))
        script.evaluate("__type(__box, [__long])")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__click(__ours()[1])")
        #expect(draft(script)?.count == AskRules.maxQuestion)
        #expect(ModelPickerMenu.script.contains("const MAX_DRAFT = \(AskRules.maxQuestion);"))
    }

    @Test func theDraftIsFromTheComposerThePressedPickerSitsIn() {
        let script = page()
        script.evaluate("__type(__box, ['the main box']); __type(__asideBox, ['the aside box']);")
        script.evaluate("__press(__asidePicker)")
        script.evaluate("__openPopup()")
        script.evaluate("__click(__ours()[1])")
        #expect(draft(script) == "the aside box")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__click(__ours()[1])")
        #expect(draft(script) == "the main box")
    }

    // MARK: What must add nothing

    @Test func aMadeUpPressOrClickIsIgnored() {
        let script = page()
        script.evaluate("__press(__picker, { trusted: false })")
        script.evaluate("__press(__picker, { type: 'keydown', key: 'Enter', trusted: false })")
        script.evaluate("__press(__picker, { type: 'click', trusted: false })")
        #expect(all(script).isEmpty)
        #expect(watching(script) == 0)
        // And a made-up click on the item chooses nothing and leaves the menu open.
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__click(__ours()[1], false)")
        #expect(posted(script).filter { $0["ask"] != nil }.isEmpty)
        #expect(script.evaluate("String(__popup !== null)") == "true")
        #expect(shape(script) == Self.after)
    }

    @Test func onlyAPressOnThePickerStartsAnythingAndOnlyTheOpeningKeysDo() {
        let script = page()
        for target in ["__other", "__plus", "__box", "__reply", "__footer"] {
            script.evaluate("__press(\(target))")
            script.evaluate("__press(\(target), { type: 'keydown', key: 'Enter' })")
            script.evaluate("__press(\(target), { type: 'click' })")
        }
        #expect(all(script).isEmpty)
        #expect(watching(script) == 0)
        // On the picker: a letter, Escape or Tab don't, nor does the right button; Enter, Space and the arrows do.
        for key in ["a", "Escape", "Tab", "Shift"] {
            script.evaluate("__press(__picker, { type: 'keydown', key: '\(key)' })")
        }
        script.evaluate("__press(__picker, { button: 2 })")
        #expect(all(script).isEmpty)
        #expect(watching(script) == 0)
        for key in ["Enter", " ", "ArrowDown", "ArrowUp"] {
            let fresh = page()
            fresh.evaluate("__press(__picker, { type: 'keydown', key: '\(key)' })")
            #expect(armed(fresh) == 1, "\(key)")
            #expect(watching(fresh) == 1, "\(key)")
        }
        // A press on what is inside the picker counts as a press on the picker.
        let inside = page()
        inside.evaluate("__press(__pickerWords)")
        #expect(armed(inside) == 1)
    }

    @Test func theClickThatFollowsAPressIsTheSamePressButAClickAloneIsOne() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__press(__picker, { type: 'click' })")
        #expect(armed(script) == 1)
        let alone = page()
        alone.evaluate("__press(__picker, { type: 'click' })")
        #expect(armed(alone) == 1)
        #expect(watching(alone) == 1)
    }

    @Test func aNoFromSwiftMeansNothingIsAddedOrWatchedOrSaid() {
        for answer in ["false", "'refuse'"] {
            let script = page(show: answer)
            script.evaluate("__press(__picker)")
            // The answer has come: the watch is over, whatever opens next.
            #expect(watching(script) == 0, "\(answer)")
            #expect(timers(script) == 0, "\(answer)")
            script.evaluate("__openPopup()")
            #expect(shape(script) == Self.before, "\(answer)")
            #expect(posted(script).count == 1, "only the question: \(answer)")
            #expect(traces(script).isEmpty, "\(answer)")
            script.evaluate("__advance(5000)")
            #expect(traces(script).isEmpty, "\(answer)")
        }
    }

    @Test func noAnswerAtAllLeavesTheMenuAloneAndSaysSoOnce() {
        let script = page(show: "'never'")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        #expect(shape(script) == Self.before)
        script.evaluate("__advance(2000)")
        #expect(shape(script) == Self.before)
        #expect(traces(script) == [["armed", "menu-matched", "refused"]])
        #expect(posted(script).filter { $0["unplaced"] != nil }.isEmpty)
        #expect(watching(script) == 0)
        #expect(timers(script) == 0)
    }

    @Test func noMenuInTwoSecondsEndsTheWatchWithoutABreadcrumb() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__advance(1999)")
        #expect(watching(script) == 1)
        script.evaluate("__advance(1)")
        #expect(traces(script) == [["armed", "allowed", "menu-none"]])
        #expect(posted(script).filter { $0["unplaced"] != nil }.isEmpty)
        #expect(watching(script) == 0)
        #expect(timers(script) == 0)
        // Late: the menu comes after the watch ended, and gets nothing.
        script.evaluate("__openPopup()")
        #expect(shape(script) == Self.before)
    }

    @Test func aMenuThatIsNotThePickersLeavesABreadcrumbAndIsLeftAlone() {
        let script = page()
        script.evaluate("__press(__picker)")
        // Another name for the popup: the design system's default.
        script.evaluate("__openPopup({ cds: 'Menu' })")
        #expect(shape(script) == Self.before)
        #expect(posted(script).filter { $0["unplaced"] != nil }.isEmpty, "not before the two seconds are up")
        script.evaluate("__advance(2000)")
        #expect(posted(script).filter { $0["unplaced"] as? Bool == true }.count == 1)
        #expect(traces(script) == [["armed", "allowed", "menu-other"]])
        #expect(shape(script) == Self.before)
        #expect(watching(script) == 0)
    }

    @Test func aNodeWithThePickersNameThatIsNotAMenuIsNotTheMenu() {
        // The picker's button carries data-cds="ModelSelector" too: only a menu with it is the popup.
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup({ role: 'dialog' })")
        script.evaluate("__advance(2000)")
        #expect(shape(script) == Self.before)
        #expect(traces(script) == [["armed", "allowed", "menu-none"]])
    }

    @Test(arguments: [
        ("a menu with no list element", "{ list: false }"),
        ("a menu with no item at all", "{ models: [], more: false }"),
    ])
    func aPickersMenuWithNothingToCopyLeavesABreadcrumbAndGetsNoItem(_ name: String, _ options: String) {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup(\(options))")
        script.evaluate("__advance(2000)")
        #expect(script.evaluate("String(__ours().length)") == "0", "\(name)")
        #expect(posted(script).filter { $0["unplaced"] as? Bool == true }.count == 1, "\(name)")
        #expect(traces(script) == [["armed", "allowed", "menu-matched", "unplaced"]], "\(name)")
        #expect(watching(script) == 0, "\(name)")
    }

    @Test func aMenuThatAppearsAndGoesBeforeItCouldBeGivenTheItemIsNotAMiss() {
        let script = page(show: "'never'")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup(); __closePopup();")
        script.evaluate("__advance(2000)")
        #expect(posted(script).filter { $0["unplaced"] != nil }.isEmpty)
        #expect(traces(script) == [["armed", "menu-matched", "menu-none"]])
    }

    @Test func theScriptDoesNothingOnAPageThatIsNotTheDaemons() {
        for host in ["example.com", "192.168.1.5"] {
            let script = page(host: host)
            script.evaluate("__press(__picker)")
            script.evaluate("__press(__picker, { type: 'keydown', key: 'Enter' })")
            #expect(all(script).isEmpty, "\(host)")
            #expect(watching(script) == 0, "\(host)")
        }
        // Nor without its handler.
        let bare = page(handler: false)
        bare.evaluate("__press(__picker)")
        #expect(watching(bare) == 0)
        #expect(bare.exception == nil)
    }

    // MARK: A press done with, and the page drawing again

    @Test func pressingThePickerAgainWhileItsMenuIsOpenClosesItAndStartsNothing() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__press(__picker)")
        // The click that ends the same press is not a new one.
        script.evaluate("__press(__picker, { type: 'click' })")
        #expect(armed(script) == 1)
        #expect(watching(script) == 0)
        #expect(timers(script) == 0)
        #expect(traces(script) == [["armed", "allowed", "menu-matched", "placed"]], "nothing more is said of the close")
        #expect(script.evaluate("String(__popup === null)") == "true", "the page closed it on the press")
        // The next press is a new one.
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        #expect(armed(script) == 2)
        #expect(shape(script) == Self.after)
    }

    @Test func aPressSomewhereElseBeforeTheMenuCameEndsTheWatch() {
        // The picker was pressed and nothing opened (it is disabled, or still loading); then the plus menu is pressed and
        // opens: that menu is not a miss of the picker's.
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__press(__plus)")
        #expect(watching(script) == 0)
        script.evaluate("__openPopup({ cds: 'Menu' })")
        script.evaluate("__advance(5000)")
        #expect(posted(script).filter { $0["unplaced"] != nil }.isEmpty)
        #expect(traces(script) == [["armed", "allowed", "interrupted"]])
        // A press elsewhere once the item is in leaves it be: only closing the menu or the two minutes end that watch.
        let placed = page()
        placed.evaluate("__press(__picker)")
        placed.evaluate("__openPopup()")
        placed.evaluate("__press(__plus)")
        #expect(watching(placed) == 1)
    }

    @Test func aPressBeforeTheLastOnesMenuCameEndsThatOnesTrace() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__press(__picker, { type: 'keydown', key: 'Enter' })")
        #expect(traces(script) == [["armed", "allowed", "interrupted"]])
        #expect(armed(script) == 2)
        #expect(watching(script) == 1)
    }

    @Test func aMenuClosedAndOpenedAgainGetsTheItemAgain() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__closePopup()")
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        #expect(shape(script) == Self.after)
        #expect(armed(script) == 2)
        #expect(traces(script).count == 2)
    }

    @Test func theHoldEndsTwoMinutesAfterTheItemWentIn() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__closePopup()")
        script.evaluate("__advance(119999)")
        #expect(watching(script) == 1)
        script.evaluate("__advance(1)")
        #expect(watching(script) == 0)
        #expect(timers(script) == 0)
    }

    @Test func aListDrawnAgainGetsTheItemBackLast() {
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("__redraw()")
        #expect(shape(script) == Self.after)
        // And a list the page replaced altogether.
        script.evaluate("__replaceList()")
        #expect(shape(script) == Self.after)
        script.evaluate("__click(__ours()[1])")
        #expect(draft(script) == "")
        #expect(script.exception == nil, "\(script.exception ?? "")")
    }

    @Test func anItemThePageAddsAfterOursIsPutBeforeThem() {
        // The page adds an item of its own after ours: ours go last again.
        let script = page()
        script.evaluate("__press(__picker)")
        script.evaluate("__openPopup()")
        script.evaluate("""
            var late = el("div", { role: "menuitem", "data-label": "Late", "class": __ITEM }, __list);
            __guarded(late); __flush();
            """)
        #expect(shape(script) == Self.before + ["page:Late", "rule", "ours:" + Self.title])
    }

    // MARK: The script as text

    @Test func theScriptNamesItsHandlerAndTheWordsOfTheItem() {
        #expect(ModelPickerMenu.script.contains("messageHandlers.\(ModelPickerMenu.handlerName)"))
        #expect(!ModelPickerMenu.script.contains("__TITLE__"))
        #expect(ModelPickerMenu.script.contains(Self.title))
        #expect(AskMenu.title == Self.title)
        #expect(!ModelPickerMenu.script.contains("fetch("))
        #expect(!ModelPickerMenu.script.contains("innerText"))
        #expect(!ModelPickerMenu.script.contains("localStorage"))
    }

    @Test func theScriptChecksThatAPressAndAClickAreRealOnes() {
        // One check in the press, one in the choice; the snapshot test lifts exactly these two.
        #expect(ModelPickerMenu.script.components(separatedBy: "if (!event.isTrusted) return;").count == 3)
    }

    @Test func theScriptWritesNothingToThePageBeyondItsOwnItem() {
        // It adds one rule and one item, moves them, and lights the item; no write to the message box, no click on the page.
        let source = ModelPickerMenu.script
        for call in ["innerHTML", "outerHTML", ".remove()", ".click(", "execCommand", "insertText", "value =", ".focus("] {
            #expect(!source.contains(call), "\(call)")
        }
    }
}
