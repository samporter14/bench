// PageTabsTests.swift — Close Other Tabs and Close All Tabs, on a made-up page:
// the decision of which tabs to close, the page script run in JavaScriptCore
// against a fake tab strip (FakeTabDOM.swift), the answer it gives, one sweep
// at a time, and when the menu commands are on. Nothing here loads a web
// view, reaches the daemon, or reads a real page; every tab is made up. What
// the real page does with the pressed buttons is checked by eye (TESTING.md).
import Foundation
import Testing
@testable import Bench

struct PageTabsTests {
    // MARK: The decision

    private let decision = PageScript(PageTabsScript.decision)

    /// `benchTabsToClose` for tabs `ids` (the one named `shown` is shown),
    /// or nil for "can't be met".
    private func decide(_ mode: String, _ ids: [String], shown: String? = nil, keep: String? = nil) -> [String]? {
        let tabs = ids.map { #"{"id":\#(FakeTabPage.json($0)),"shown":\#($0 == shown)}"# }.joined(separator: ",")
        let keepJSON = keep.map { FakeTabPage.json($0) }
        guard let text = decision.callJSON("benchTabsToClose", [FakeTabPage.json(mode), "[\(tabs)]", keepJSON]),
              text != "null", let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    @Test func othersKeepsTheGivenTabWhereverItSits() {
        let ids = ["a", "b", "c", "d"]
        #expect(decide("others", ids, keep: "a") == ["b", "c", "d"])
        #expect(decide("others", ids, keep: "b") == ["a", "c", "d"])
        #expect(decide("others", ids, keep: "d") == ["a", "b", "c"])
    }

    @Test func othersWithTheOnlyTabClosesNothing() {
        #expect(decide("others", ["only"], keep: "only") == [])
        #expect(decide("others", ["only"], shown: "only") == [])
    }

    @Test func othersWithoutAnIdKeepsTheShownTab() {
        #expect(decide("others", ["a", "b", "c"], shown: "c") == ["a", "b"])
        #expect(decide("others", ["a", "b", "c"], shown: "a") == ["b", "c"])
        // An id that is given wins over the shown tab.
        #expect(decide("others", ["a", "b", "c"], shown: "c", keep: "a") == ["b", "c"])
    }

    @Test func othersWithNoSingleShownTabRefusesRatherThanGuess() {
        #expect(decide("others", ["a", "b"]) == nil)
        let two = PageScript(PageTabsScript.decision)
        let text = two.callJSON("benchTabsToClose", [FakeTabPage.json("others"),
                                                       #"[{"id":"a","shown":true},{"id":"b","shown":true}]"#, nil])
        #expect(text == "null")
    }

    @Test func anUnknownKeptIdClosesNothing() {
        #expect(decide("others", ["a", "b"], keep: "zz") == nil)
        #expect(decide("others", ["a", "b"], shown: "a", keep: "zz") == nil)
        #expect(decide("others", ["a", "b"], keep: "") == nil)
        #expect(decide("one", ["a", "b"], keep: "zz") == nil)
    }

    @Test func allClosesEveryTabInOrder() {
        #expect(decide("all", ["c", "a", "b"]) == ["c", "a", "b"])
        #expect(decide("all", ["only"]) == ["only"])
        // The tab to keep is ignored.
        #expect(decide("all", ["a", "b"], keep: "a") == ["a", "b"])
    }

    @Test func oneClosesJustThatTab() {
        #expect(decide("one", ["a", "b", "c"], keep: "b") == ["b"])
        #expect(decide("one", ["a", "b", "c"], shown: "a") == nil)
    }

    @Test func anEmptyStripHasNothingToClose() {
        #expect(decide("all", []) == [])
        #expect(decide("others", []) == [])
        #expect(decide("others", [], keep: "a") == nil)
    }

    @Test func anotherModeOrAKeepThatIsNotAStringIsRefused() {
        #expect(decide("most", ["a", "b"], keep: "a") == nil)
        #expect(decision.callJSON("benchTabsToClose", [FakeTabPage.json("others"), #"[{"id":"a","shown":true}]"#, "5"]) == "null")
    }

    @Test func aRepeatedIdIsClosedOnce() {
        #expect(decide("all", ["a", "b", "a"]) == ["a", "b"])
    }

    // MARK: The script on a fake strip

    private func done(_ closed: Int, _ stayed: Int) -> PageTabsOutcome { .done(closed: closed, stayed: stayed) }

    @Test func closeOthersKeepsTheShownTabAndPressesOnlyTheOthersCloseButtons() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", "t4", shown: "t3")))
        #expect(page.run("others") == done(3, 0))
        #expect(page.clicks == "close:t1,close:t2,close:t4")
        #expect(page.remaining == "t3")
        #expect(page.script.exception == nil)
    }

    @Test func closeOthersKeepsTheTabItIsToldTo() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", shown: "t1")))
        #expect(page.run("others", keep: "t3") == done(2, 0))
        #expect(page.clicks == "close:t1,close:t2")
        #expect(page.remaining == "t3")
    }

    @Test func keepingTheFirstOrTheLastOrTheOnlyTab() {
        let first = FakeTabPage(.init(tabs: FakeTabDOM.tabs("a", "b", "c", shown: "b")))
        #expect(first.run("others", keep: "a") == done(2, 0))
        #expect(first.remaining == "a")
        let last = FakeTabPage(.init(tabs: FakeTabDOM.tabs("a", "b", "c", shown: "b")))
        #expect(last.run("others", keep: "c") == done(2, 0))
        #expect(last.remaining == "c")
        let only = FakeTabPage(.init(tabs: FakeTabDOM.tabs("a", shown: "a")))
        #expect(only.run("others") == done(0, 0))
        #expect(only.clicks == "")
        #expect(only.remaining == "a")
    }

    @Test func closeAllPressesEveryCloseButtonAndTheStripGoesWithTheLastTab() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", shown: "t2")))
        #expect(page.run("all") == done(3, 0))
        #expect(page.clicks == "close:t1,close:t2,close:t3")
        #expect(page.remaining == "")
        #expect(!page.stripPresent)
    }

    @Test func closeAllWhenTheStripStaysWithNoTabs() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2"), unmount: false))
        #expect(page.run("all") == done(2, 0))
        #expect(page.stripPresent)
    }

    @Test func closeTabClosesJustThatOne() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", shown: "t1")))
        #expect(page.run("one", keep: "t2") == done(1, 0))
        #expect(page.clicks == "close:t2")
        #expect(page.remaining == "t1,t3")
    }

    @Test func itLooksOnlyInsideTheStripAndPressesOnlyCloseButtons() {
        // Tabs with the same ids and close buttons outside the strip, one more
        // beside the toolbar inside it, an "overflow" button in every tab and
        // a "Close Files" button elsewhere: none of them is pressed.
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", shown: "t2"), decoys: true))
        #expect(page.run("all") == done(3, 0))
        #expect(page.clicks == "close:t1,close:t2,close:t3")
        let other = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", shown: "t2"), decoys: true))
        #expect(other.run("others") == done(2, 0))
        #expect(other.clicks == "close:t1,close:t3")
        // An id that is only outside the strip is not in it.
        let outside = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2"), decoys: true))
        #expect(outside.run("others", keep: "zzz") == .refused)
        #expect(outside.clicks == "")
    }

    @Test func itReadsTheStripAfterEveryPressInsteadOfKeepingElements() {
        // Every re-render makes new elements. A script that kept the first
        // read's buttons would press detached ones, which do nothing.
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", "t3", "t4", shown: "t4"), fresh: true))
        #expect(page.run("others") == done(3, 0))
        #expect(page.clicks == "close:t1,close:t2,close:t3")
        #expect(page.remaining == "t4")
    }

    @Test func aTabThatIsAskedAboutStaysAndTheSweepStopsThere() {
        // The page keeps t2 (unsaved edits, a question pending). A second
        // close needing an answer would replace that question, so t3 and t4
        // are not pressed.
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", "t4", shown: "t1")
        tabs[1].close = "refuse"
        let page = FakeTabPage(.init(tabs: tabs))
        #expect(page.run("all") == done(1, 3))
        #expect(page.clicks == "close:t1,close:t2")
        #expect(page.remaining == "t2,t3,t4")
    }

    @Test func aRefusalOnTheFirstTabClosesNone() {
        var tabs = FakeTabDOM.tabs("t1", "t2")
        tabs[0].close = "refuse"
        let page = FakeTabPage(.init(tabs: tabs))
        #expect(page.run("all") == done(0, 2))
        #expect(page.clicks == "close:t1")
    }

    @Test func aRefusedTabIsCountedAsStayedForTheOthersToo() {
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", shown: "t3")
        tabs[0].close = "refuse"
        let page = FakeTabPage(.init(tabs: tabs))
        #expect(page.run("others") == done(0, 2))
        #expect(page.remaining == "t1,t2,t3")
    }

    @Test func aTabThatClosesALittleLaterCountsAsClosed() {
        // The page takes 100 ms (fake clock) to take the tab out; the script
        // waits for it, in short steps, and goes on.
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", shown: "t3")
        tabs[1].delay = 100
        let page = FakeTabPage(.init(tabs: tabs), timers: true)
        #expect(page.run("others") == done(2, 0))
        #expect(page.clicks == "close:t1,close:t2")
        #expect(page.remaining == "t3")
    }

    @Test func aTabThatTakesTooLongCountsAsStayed() {
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", shown: "t3")
        tabs[0].delay = 400
        let page = FakeTabPage(.init(tabs: tabs), timers: true)
        #expect(page.run("others") == done(0, 2))
        #expect(page.clicks == "close:t1")
    }

    @Test func aShownTabCanBeMarkedOnTheTabItself() {
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", shown: "t2")
        for index in tabs.indices { tabs[index].shownVia = "data" }
        let page = FakeTabPage(.init(tabs: tabs))
        #expect(page.run("others") == done(2, 0))
        #expect(page.remaining == "t2")
    }

    @Test func tabIdsAreNeverBuiltIntoSelectors() {
        let odd = FakeTabDOM.tabs(#"a"b"#, "x y", "c]d", #"e\f"#, shown: "x y")
        let page = FakeTabPage(.init(tabs: odd))
        #expect(page.run("others") == done(3, 0))
        #expect(page.remaining == "x y")
        #expect(page.script.exception == nil)
    }

    // MARK: When the page isn't as expected, nothing is pressed

    @Test func withoutAStripItDoesNothingAndSaysSo() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", shown: "t1"), strips: 0))
        #expect(page.run("all") == .unavailable)
        #expect(page.run("others") == .unavailable)
        #expect(page.clicks == "")
    }

    @Test func withoutTheToolbarItDoesNothingAndSaysSo() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", shown: "t1"), toolbar: false))
        #expect(page.run("all") == .unavailable)
        #expect(page.clicks == "")
        #expect(page.remaining == "t1,t2")
    }

    @Test func twoStripsAreAmbiguousSoItDoesNothing() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", shown: "t1"), strips: 2))
        #expect(page.run("all") == .unavailable)
        #expect(page.clicks == "")
    }

    @Test func aTabWithoutACloseButtonMeansNoPressAtAll() {
        // t3 to be closed has no button: not even t1's is pressed first.
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", shown: "t1")
        tabs[2].close = "none"
        let page = FakeTabPage(.init(tabs: tabs))
        #expect(page.run("all") == .unavailable)
        #expect(page.run("others") == .unavailable)
        #expect(page.clicks == "")
        #expect(page.remaining == "t1,t2,t3")
    }

    @Test func theTabToKeepNeedsNoCloseButton() {
        var tabs = FakeTabDOM.tabs("t1", "t2", "t3", shown: "t3")
        tabs[2].close = "none"
        let page = FakeTabPage(.init(tabs: tabs))
        #expect(page.run("others") == done(2, 0))
        #expect(page.remaining == "t3")
    }

    @Test func aKeptTabThatIsNotThereRefusesAndPressesNothing() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2", shown: "t1")))
        #expect(page.run("others", keep: "gone") == .refused)
        #expect(page.run("one", keep: "gone") == .refused)
        #expect(page.clicks == "")
    }

    @Test func noShownTabMeansNothingToKeepSoOthersRefuses() {
        let page = FakeTabPage(.init(tabs: FakeTabDOM.tabs("t1", "t2")))
        #expect(page.run("others") == .refused)
        #expect(page.clicks == "")
    }

    @Test func anEmptyStripDoesNothing() {
        let page = FakeTabPage(.init(tabs: [], unmount: false))
        #expect(page.run("all") == done(0, 0))
        #expect(page.run("others") == done(0, 0))
        #expect(page.clicks == "")
    }

    // MARK: Its answer

    @Test func theAnswerIsCheckedAgain() {
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":2,"stayed":1}"#) == .done(closed: 2, stayed: 1))
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":0,"stayed":0}"#) == .done(closed: 0, stayed: 0))
        #expect(PageTabsOutcome(parsing: #"{"status":"unavailable","closed":0,"stayed":0}"#) == .unavailable)
        #expect(PageTabsOutcome(parsing: #"{"status":"refused","closed":0,"stayed":0}"#) == .refused)
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":-1,"stayed":0}"#) == nil)
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":1.5,"stayed":0}"#) == nil)
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":true,"stayed":0}"#) == nil)
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":99999,"stayed":0}"#) == nil)
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":"2","stayed":0}"#) == nil)
        #expect(PageTabsOutcome(parsing: #"{"status":"done","closed":2}"#) == nil)
        #expect(PageTabsOutcome(parsing: #"{"status":"closed"}"#) == nil)
        #expect(PageTabsOutcome(parsing: "threw: ReferenceError") == nil)
        #expect(PageTabsOutcome(parsing: "") == nil)
    }

    @Test func eachRequestMakesItsArguments() {
        func pair(_ request: PageTabsClose) -> String {
            let arguments = request.arguments
            let keep = arguments["keep"].map { $0 is NSNull ? "null" : "\($0)" } ?? "missing"
            return "\(arguments["mode"] ?? "missing"):\(keep)"
        }
        #expect(pair(.others(keeping: nil)) == "others:null")
        #expect(pair(.others(keeping: "t2")) == "others:t2")
        #expect(pair(.all) == "all:null")
        #expect(pair(.one("t2")) == "one:t2")
    }

    // MARK: One sweep at a time

    /// A sweep that waits until it is let go.
    @MainActor
    private final class Gate {
        var calls: [PageTabsClose] = []
        var release: CheckedContinuation<Void, Never>?

        func perform(_ request: PageTabsClose) async -> PageTabsOutcome {
            calls.append(request)
            await withCheckedContinuation { release = $0 }
            return .done(closed: 1, stayed: 0)
        }
    }

    @MainActor
    @Test func aSecondSweepWhileOneRunsIsDropped() async {
        let gate = Gate()
        let closer = PageTabCloser { await gate.perform($0) }
        let first = Task { await closer.close(.all) }
        while gate.release == nil { await Task.yield() }
        #expect(closer.isRunning)
        #expect(await closer.close(.others(keeping: nil)) == nil)
        #expect(gate.calls == [.all])
        gate.release?.resume()
        #expect(await first.value == .done(closed: 1, stayed: 0))
        #expect(!closer.isRunning)
        // And the next one runs.
        gate.release = nil
        let second = Task { await closer.close(.others(keeping: nil)) }
        while gate.release == nil { await Task.yield() }
        gate.release?.resume()
        #expect(await second.value == .done(closed: 1, stayed: 0))
        #expect(gate.calls == [.all, .others(keeping: nil)])
    }

    // MARK: When the commands are on

    @Test func theCommandsAreOnOnlyForTheMainWindowWithAReadyPage() {
        let statuses: [WebContainer.Status] = [.starting, .ready, .failed("Made up")]
        for status in statuses {
            #expect(PageTabCommands.canClose(mainWindowIsKey: true, status: status) == (status == .ready))
            #expect(!PageTabCommands.canClose(mainWindowIsKey: false, status: status))
        }
    }

    @MainActor
    @Test func theCommandsFollowTheWindowAndThePage() {
        let commands = PageTabCommands()
        #expect(!commands.isEnabled)
        commands.update(mainWindowIsKey: true, status: .starting)
        #expect(!commands.isEnabled)
        commands.update(mainWindowIsKey: true, status: .ready)
        #expect(commands.isEnabled)
        // Settings, a Browser window or a sheet in front.
        commands.update(mainWindowIsKey: false, status: .ready)
        #expect(!commands.isEnabled)
        commands.update(mainWindowIsKey: true, status: .ready)
        commands.update(mainWindowIsKey: true, status: .failed("Made up"))
        #expect(!commands.isEnabled)
    }
}
