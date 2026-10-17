// TabContextMenuTests.swift — the right-click menu of a page tab, on made-up
// tabs: the user script that says which tab a right-click was on (run in
// JavaScriptCore against the fake strip), how its message is read and who it
// may come from, how long a tab is fresh, and the items put into an NSMenu.
// No web view is loaded and no menu is shown; WebKit's ordering of the message
// and the menu, and the menu itself, are checked by eye (TESTING.md).
import AppKit
import Foundation
import Testing
@testable import Bench

struct TabContextMenuTests {
    // MARK: Reading the message

    @Test func aMessageNamesATabOrNone() {
        #expect(TabMenuMessage.tab(in: ["tab": "t1"]) == "t1")
        #expect(TabMenuMessage.tab(in: ["tab": "t1", "extra": 5]) == "t1")
        #expect(TabMenuMessage.tab(in: ["tab": NSNull()]) == nil)
        #expect(TabMenuMessage.tab(in: [String: Any]()) == nil)
        #expect(TabMenuMessage.tab(in: ["tab": ""]) == nil)
        #expect(TabMenuMessage.tab(in: ["tab": 5]) == nil)
        #expect(TabMenuMessage.tab(in: ["tab": ["t1"]]) == nil)
        #expect(TabMenuMessage.tab(in: "t1") == nil)
        #expect(TabMenuMessage.tab(in: nil) == nil)
        #expect(TabMenuMessage.tab(in: ["tab": String(repeating: "a", count: TabMenuMessage.maxIDLength)]) != nil)
        #expect(TabMenuMessage.tab(in: ["tab": String(repeating: "a", count: TabMenuMessage.maxIDLength + 1)]) == nil)
    }

    @Test func onlyTheMainWebViewsMainFrameOnTheDaemonsOriginIsHeard() {
        #expect(TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: false, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: false, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: false))
    }

    // MARK: How long a tab is fresh

    private let start = ContinuousClock.now

    @Test func aTabIsFreshForASecondAndTakenOnce() {
        var target = TabMenuTarget()
        target.record("t1", at: start)
        #expect(target.take(at: start + .milliseconds(999)) == "t1")
        // Used: the next menu doesn't get it.
        #expect(target.take(at: start + .milliseconds(1000)) == nil)

        target.record("t2", at: start)
        #expect(target.take(at: start + .seconds(1)) == "t2")
    }

    @Test func aStaleTabIsNeverUsed() {
        var target = TabMenuTarget()
        target.record("t1", at: start)
        #expect(target.take(at: start + .milliseconds(1001)) == nil)
        // And it is forgotten, not kept for later.
        #expect(target.take(at: start + .milliseconds(10)) == nil)
        // Nothing recorded at all.
        var empty = TabMenuTarget()
        #expect(empty.take(at: start) == nil)
        // A clock that went backwards is not trusted.
        target.record("t3", at: start + .seconds(5))
        #expect(target.take(at: start) == nil)
    }

    @Test func aRightClickOnNoTabClearsTheLastOne() {
        var target = TabMenuTarget()
        target.record("t1", at: start)
        target.record(nil, at: start + .milliseconds(100))
        #expect(target.take(at: start + .milliseconds(200)) == nil)
    }

    // MARK: The items

    private func menu(_ titles: [String] = ["Copy", "Inspect Element"]) -> NSMenu {
        let menu = NSMenu()
        for title in titles { menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        return menu
    }

    /// Titles in order, "-" for a separator.
    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    @MainActor
    @Test func theThreeItemsGoAtTheTopInASeparatedGroup() {
        let menu = menu()
        TabContextMenu.insertItems(into: menu, for: "t2") { _ in }
        #expect(titles(menu) == ["Close Tab", "Close Other Tabs", "Close All Tabs", "-", "Copy", "Inspect Element"])
        #expect(TabContextMenu.titles == ["Close Tab", "Close Other Tabs", "Close All Tabs"])
        // They have no shortcut of their own.
        #expect(menu.items.prefix(3).allSatisfy { $0.keyEquivalent.isEmpty })
    }

    @MainActor
    @Test func theItemsAreNotAddedTwice() {
        let menu = menu()
        TabContextMenu.insertItems(into: menu, for: "t2") { _ in }
        TabContextMenu.insertItems(into: menu, for: "t2") { _ in }
        #expect(titles(menu) == ["Close Tab", "Close Other Tabs", "Close All Tabs", "-", "Copy", "Inspect Element"])
    }

    @MainActor
    @Test func anEmptyMenuGetsTheGroupToo() {
        let menu = menu([])
        TabContextMenu.insertItems(into: menu, for: "t2") { _ in }
        #expect(titles(menu) == ["Close Tab", "Close Other Tabs", "Close All Tabs", "-"])
    }

    @MainActor
    @Test func eachItemAsksForItsOwnSweepRelativeToTheRightClickedTab() {
        var requests: [PageTabsClose] = []
        let menu = menu()
        TabContextMenu.insertItems(into: menu, for: "t2") { requests.append($0) }
        for item in menu.items.prefix(3) {
            guard let target = item.target as? NSObject, let action = item.action else {
                Issue.record("An item has no target or action")
                continue
            }
            _ = target.perform(action, with: item)
        }
        #expect(requests == [.one("t2"), .others(keeping: "t2"), .all])
    }

    // MARK: Only after a right-click on a tab, just now

    @MainActor
    private func makeMenu(clock: @escaping () -> ContinuousClock.Instant) -> TabContextMenu {
        TabContextMenu(now: clock, daemonPort: { 8765 }, run: { _ in })
    }

    @MainActor
    @Test func aFreshTabAddsTheItemsOnce() {
        var now = start
        let tabMenu = makeMenu { now }
        tabMenu.record("t1")
        now = start + .milliseconds(400)
        let first = menu()
        tabMenu.addItems(to: first)
        #expect(Array(titles(first).prefix(3)) == ["Close Tab", "Close Other Tabs", "Close All Tabs"])
        // The next menu, with no right-click on a tab since, is left alone.
        let second = menu()
        tabMenu.addItems(to: second)
        #expect(titles(second) == ["Copy", "Inspect Element"])
    }

    @MainActor
    @Test func aStaleOrMissingTabAddsNoItems() {
        var now = start
        let tabMenu = makeMenu { now }
        // Nothing recorded.
        let none = menu()
        tabMenu.addItems(to: none)
        #expect(titles(none) == ["Copy", "Inspect Element"])
        // Recorded, but the menu came a long time after.
        tabMenu.record("t1")
        now = start + .seconds(3)
        let stale = menu()
        tabMenu.addItems(to: stale)
        #expect(titles(stale) == ["Copy", "Inspect Element"])
        // A right-click on a tab and then on something else.
        now = start + .seconds(10)
        tabMenu.record("t1")
        tabMenu.record(nil)
        let other = menu()
        tabMenu.addItems(to: other)
        #expect(titles(other) == ["Copy", "Inspect Element"])
    }

    // MARK: The user script

    /// The script in a fake page with a message handler that records what it is sent.
    private func listener(page: FakeTabDOM.Page = .init(tabs: FakeTabDOM.tabs("t1", "t2", shown: "t1")),
                          protocolName: String = "http:", host: String = "localhost",
                          withHandler: Bool = true) -> PageScript {
        let script = FakeTabDOM.context(page)
        let window = withHandler
            ? #"{ webkit: { messageHandlers: { capsidTabMenu: { postMessage: function (m) { __posted.push(JSON.stringify(m)); } } } } }"#
            : "{}"
        script.evaluate("""
        var __posted = [];
        var location = { protocol: "\(protocolName)", hostname: "\(host)" };
        var window = \(window);
        function __fire(target, trusted) {
            document.listeners.forEach(function (l) {
                if (l.type === "contextmenu") { l.fn({ type: "contextmenu", target: target, isTrusted: trusted !== false }); }
            });
        }
        """)
        script.evaluate(TabContextMenu.script)
        return script
    }

    private func posted(_ script: PageScript) -> String {
        script.evaluate("__posted.join(' ')") ?? "?"
    }

    @Test func itListensForContextMenusInTheCapturePhase() {
        let script = listener()
        #expect(script.evaluate("document.listeners.map(function (l) { return l.type + ':' + l.capture; }).join(',')")
                == "contextmenu:true")
        #expect(script.exception == nil)
    }

    @Test func aRightClickOnATabNamesIt() {
        let script = listener()
        script.evaluate(#"__fire(__find("tab-btn", "t2"))"#)
        script.evaluate(#"__fire(__find("overflow", "t1"))"#)
        #expect(posted(script) == #"{"tab":"t2"} {"tab":"t1"}"#)
        #expect(script.exception == nil)
    }

    @Test func aRightClickOnTextInATabNamesItToo() {
        let script = listener()
        script.evaluate(#"__fire({ nodeType: 3, parentElement: __find("tab-btn", "t2") })"#)
        #expect(posted(script) == #"{"tab":"t2"}"#)
    }

    @Test func aRightClickAnywhereElseSaysNoTab() {
        let script = listener(page: .init(tabs: FakeTabDOM.tabs("t1", "t2", shown: "t1"), decoys: true))
        // A tab-like thing outside the strip, the strip's own bare part, the
        // page's body, a text node with nothing around it and no target.
        script.evaluate(#"__fire(__find("decoy-btn", "t1"))"#)
        script.evaluate(#"__fire(document.querySelector('[data-testid="right-tab-strip"]'))"#)
        script.evaluate("__fire(document.body)")
        script.evaluate("__fire({ nodeType: 3, parentElement: null })")
        script.evaluate("__fire(null)")
        #expect(posted(script) == Array(repeating: #"{"tab":null}"#, count: 5).joined(separator: " "))
        #expect(script.exception == nil)
    }

    @Test func aTabWithNoIdSaysNoTab() {
        let script = listener()
        script.evaluate(#"__find("tab-btn", "t1").parent.attrs["data-tab-id"] = "";"#)
        script.evaluate(#"__fire(__find("tab-btn", "t1"))"#)
        #expect(posted(script) == #"{"tab":null}"#)
    }

    @Test func aMadeUpEventIsIgnored() {
        let script = listener()
        script.evaluate(#"__fire(__find("tab-btn", "t2"), false)"#)
        #expect(posted(script) == "")
    }

    @Test func itDoesNothingOutsideTheDaemonsPageOrWithoutItsHandler() {
        #expect(listener(host: "example.com").evaluate("String(document.listeners.length)") == "0")
        #expect(listener(protocolName: "https:").evaluate("String(document.listeners.length)") == "0")
        #expect(listener(withHandler: false).evaluate("String(document.listeners.length)") == "0")
        #expect(listener(host: "127.0.0.1").evaluate("String(document.listeners.length)") == "1")
    }
}
