// SourceSeekScriptTests.swift — Show Where It Came From's page script
// (Shelf/SourceSeek.swift) run in JavaScriptCore on a made-up conversation
// (FakeConversationPage): a virtual list of rows that loads earlier messages when
// it is scrolled up, with a Generated tray under each turn that made files. The
// timers run on a virtual clock, so a run that takes seconds in a page takes
// microseconds here. Nothing reaches a real page, a daemon or a window.
import Foundation
import Testing
@testable import Bench

/// A made-up conversation and the script, run together.
final class SeekHarness {
    let page = PageScript()

    init(_ config: FakeConversationPage.Config = .init(), noAnimate: Bool = false) {
        page.evaluate(FakeFigurePage.dom)
        page.evaluate("var __runs = [];")
        page.evaluate(FakeConversationPage.source(config))
        if noAnimate { page.evaluate("FElement.prototype.animate = undefined;") }
        if let problem = page.exception { Issue.record("the made-up page: \(problem)") }
    }

    /// Starts the script as `callAsyncJavaScript` would, as an async function of the request's arguments.
    @discardableResult
    func start(_ request: SourceSeekRequest) -> Int {
        let slot = Int(page.evaluate("String(__runs.length)") ?? "") ?? 0
        let data = (try? JSONSerialization.data(withJSONObject: request.arguments)) ?? Data("{}".utf8)
        page.set("__request", String(decoding: data, as: UTF8.self))
        page.evaluate("""
        __runs.push(null);
        (function () {
          var a = JSON.parse(__request);
          (async function (mode, row, version, name, readyMs, seekMs, settleMs) {
          \(SourceSeek.body)
          })(a.mode, a.row, a.version, a.name, a.readyMs, a.seekMs, a.settleMs)
            .then(function (v) { __runs[\(slot)] = v; }, function (e) { __runs[\(slot)] = "threw: " + e; });
        })();
        """)
        if let problem = page.exception { Issue.record("the script: \(problem)") }
        return slot
    }

    /// Lets `ms` of the page's time go by, a little at a time (a promise's next step runs between calls).
    func pump(_ ms: Int, step: Int = 20) {
        var spent = 0
        while spent < ms {
            page.evaluate("__advance(\(step))")
            spent += step
        }
    }

    /// Lets time go by until the run answers, or `limit` milliseconds have.
    func answer(_ slot: Int, limit: Int = 60_000, step: Int = 20) -> String? {
        var spent = 0
        while spent < limit {
            if let done = page.evaluate("__runs[\(slot)]") { return done }
            page.evaluate("__advance(\(step))")
            spent += step
        }
        return page.evaluate("__runs[\(slot)]")
    }

    /// The steps a run answered; nil when it threw or never answered.
    func steps(_ slot: Int, limit: Int = 60_000) -> [SourceStep]? {
        answer(slot, limit: limit).flatMap { SourceSeek.steps(of: $0) }
    }

    /// Starts a request and waits for its steps.
    func run(_ request: SourceSeekRequest) -> [SourceStep]? {
        steps(start(request))
    }

    func number(_ expression: String) -> Double { Double(page.evaluate("String(\(expression))") ?? "") ?? .nan }
    func text(_ expression: String) -> String { page.evaluate("String(\(expression))") ?? "" }
    var now: Double { number("__now") }
    var top: Double { number("__top") }
    var bottom: Double { number("__maxTop()") }

    /// Who was outlined, as the page's animations were asked for it.
    struct Mark: Decodable {
        let testid: String?
        let src: String?
        let title: String?
        let frames: Int
        let ms: Double
    }

    var marks: [Mark] {
        (try? JSONDecoder().decode([Mark].self, from: Data(text("__marked()").utf8))) ?? []
    }

    /// The conversation of the harness, as most tests use it: 2,400 messages, the last 200 loaded.
    static let reply = FakeConversationPage.reply
    static let version = FakeConversationPage.version
}

struct SourceSeekScriptTests {
    private func reply(_ row: Int, version: String? = nil, name: String? = nil, settle: Int = 300) -> SourceSeekRequest {
        SourceSeekRequest(mode: .reply, row: row, version: version, name: name, readyMs: 2_000, seekMs: 8_000, settleMs: settle)
    }

    // MARK: Reaching the reply

    @Test func aReplyOnTheScreenIsFoundAtOnceAndItsTrayAndCardShown() throws {
        let page = SeekHarness()
        // Exchange 298 is near the end: its turn made one picture.
        let steps = page.run(reply(SeekHarness.reply(298), version: SeekHarness.version(298, 0)))
        #expect(steps == [.turnFound, .trayShown, .cardMarked])
        #expect(page.number("__inFrame(__tray(298)) ? 1 : 0") == 1)
        let marks = page.marks
        #expect(marks.count == 1)
        let one = try #require(marks.first)
        #expect(one.testid == "turn-tray-card")
        #expect(one.src?.contains(SeekHarness.version(298, 0)) == true)
        #expect(one.frames == 3 && one.ms == 2400, "an outline that holds, then fades")
        #expect(page.number("__loads") == 0, "nothing earlier was asked for")
    }

    @Test func aReplyBeyondTheLoadedMessagesIsReachedByScrollingUpAndLettingThePageLoad() {
        let page = SeekHarness()
        // Exchange 150's closing text is message 1206; the page has 2200 to 2399.
        let steps = page.run(reply(SeekHarness.reply(150), version: SeekHarness.version(150, 0)))
        #expect(steps == [.topReached, .turnFound, .trayShown, .cardMarked])
        #expect(page.number("__loads") >= 5, "\(page.number("__loads")) pages")
        #expect(page.number("__inFrame(__tray(150)) ? 1 : 0") == 1)
        #expect(page.marks.count == 1)
        // A few seconds, not many: the virtual clock says how long the page would have been scrolled.
        #expect(page.now < 8_000, "\(page.now) ms")
    }

    @Test func aPageThatDoesNotKeepTheScreenWhereItWasAfterALoadIsReachedToo() {
        let page = SeekHarness(.init(anchor: false))
        let steps = page.run(reply(SeekHarness.reply(180), version: SeekHarness.version(180, 0)))
        #expect(steps == [.topReached, .turnFound, .trayShown, .cardMarked])
        #expect(page.number("__inFrame(__tray(180)) ? 1 : 0") == 1)
    }

    @Test func aReplyBelowWhereTheScreenIsIsReachedByScrollingDown() {
        let page = SeekHarness()
        // Start near the top of what is loaded; the reply is lower.
        page.page.evaluate("scroller.scrollTop = 0;")
        page.pump(500)
        let steps = page.run(reply(SeekHarness.reply(290), version: SeekHarness.version(290, 0)))
        // Scrolling to the top loaded more on the way; whatever came, it ended on the reply.
        #expect(Array(steps?.suffix(3) ?? []) == [.turnFound, .trayShown, .cardMarked])
        #expect(page.number("__inFrame(__tray(290)) ? 1 : 0") == 1)
    }

    @Test func placeholdersThatLastLongerThanTheScriptsPauseAreWaitedOut() {
        // A fast scroll draws placeholders (no message numbers) for 900 ms.
        let page = SeekHarness(.init(seekMs: 900))
        let steps = page.run(reply(SeekHarness.reply(160), version: SeekHarness.version(160, 0)))
        #expect(steps == [.topReached, .turnFound, .trayShown, .cardMarked])
    }

    // MARK: Where the tray goes

    @Test func aTurnThatFitsIsShownWholeFromNearTheTop() {
        let page = SeekHarness()
        _ = page.run(reply(SeekHarness.reply(298), version: SeekHarness.version(298, 0)))
        let turn = page.number("__fraction(__cache['t298'])")
        #expect(abs(turn - 0.07) < 0.05, "the turn starts \(turn) of the way down")
        #expect(page.number("__inFrame(__tray(298)) ? 1 : 0") == 1)
    }

    @Test func aTurnTallerThanTheScreenPutsItsTrayTwoFifthsDown() {
        let page = SeekHarness(.init(tall: 150))
        let steps = page.run(reply(SeekHarness.reply(150), version: SeekHarness.version(150, 0)))
        #expect(steps == [.topReached, .turnFound, .trayShown, .cardMarked])
        let tray = page.number("__fraction(__tray(150))")
        #expect(abs(tray - 0.4) < 0.06, "the tray is \(tray) of the way down")
    }

    @Test func aTurnWithNoTrayIsScrolledToByItsReplyAQuarterDown() {
        let page = SeekHarness()
        // Exchange 296 (296 % 5 == 1) made nothing.
        let steps = page.run(reply(SeekHarness.reply(296), version: SeekHarness.version(296, 0)))
        #expect(steps == [.turnFound, .trayNone])
        #expect(page.marks.isEmpty)
        let fraction = page.number("__fraction(__replyElement(296))")
        #expect(abs(fraction - 0.25) < 0.06, "\(fraction)")
    }

    @Test func aLayoutThatMovesAfterLandingIsFollowedForAMoment() {
        let page = SeekHarness()
        let slot = page.start(reply(SeekHarness.reply(298), version: SeekHarness.version(298, 0), settle: 1_500))
        // Landed once the outline is drawn.
        var spent = 0
        while page.marks.isEmpty && spent < 5_000 { page.pump(20); spent += 20 }
        #expect(page.marks.count == 1)
        // Something above the turn grows (a picture arrives): the page's scroll position is no longer the one aimed for.
        page.page.evaluate("scroller.scrollTop = scroller.scrollTop - 300;")
        page.pump(400)
        let turn = page.number("__fraction(__cache['t298'])")
        #expect(abs(turn - 0.07) < 0.05, "put back: \(turn)")
        #expect(page.steps(slot) == [.turnFound, .trayShown, .cardMarked])
    }

    // MARK: The card

    @Test func aCardInThePlusMoreIsNotOpenedAndTheTrayIsOutlinedInstead() throws {
        let page = SeekHarness(.init(total: 400, bigTray: 30))
        // Eight files: five cards and "+3 more"; the seventh is a picture, in the folded part.
        let steps = page.run(reply(SeekHarness.reply(30), version: SeekHarness.version(30, 6)))
        #expect(Array(steps?.suffix(2) ?? []) == [.trayShown, .cardHidden])
        let one = try #require(page.marks.first)
        #expect(page.marks.count == 1 && one.testid == "turn-artifact-tray")
        #expect(page.number("__clicks.length") == 0, "the page's own button is left alone")
    }

    @Test func aFileWithNoPictureIsFoundByItsNameWhenExactlyOneCardHasIt() throws {
        let page = SeekHarness(.init(total: 800))
        let steps = page.run(reply(SeekHarness.reply(39), version: nil, name: "notes_39_1.md"))
        #expect(Array(steps?.suffix(3) ?? []) == [.turnFound, .trayShown, .cardMarked])
        let one = try #require(page.marks.first)
        #expect(one.testid == "turn-tray-card" && one.title == "notes_39_1.md")
    }

    @Test func anotherDraftOfTheSameFigureIsFoundByItsNameWhenItsVersionIsNotThere() throws {
        let page = SeekHarness(.init(total: 800))
        // The reply went on to a later version of plot_39_0.png: the version asked for names no card.
        let steps = page.run(reply(SeekHarness.reply(39), version: "ffffffff-0000-4000-8000-000000000001", name: "plot_39_0.png"))
        #expect(steps?.last == .cardMarked)
        let one = try #require(page.marks.first)
        #expect(one.title == "plot_39_0.png" && one.src?.contains(SeekHarness.version(39, 0)) == true)
    }

    @Test func twoCardsWithOneNameAreNotGuessedBetween() throws {
        let page = SeekHarness(.init(total: 400, bigTray: 30, sameNames: true))
        // Two Markdown files in the first five cards are both called notes.md.
        let steps = page.run(reply(SeekHarness.reply(30), version: nil, name: "notes.md"))
        #expect(steps?.last == .cardHidden)
        #expect(try #require(page.marks.first).testid == "turn-artifact-tray")
    }

    // MARK: Hands

    @Test func theUsersOwnWheelTouchKeyOrPressEndsItAndLeavesThePageWhereTheyPutIt() {
        for kind in ["wheel", "touchstart", "keydown", "mousedown"] {
            let page = SeekHarness()
            let slot = page.start(reply(SeekHarness.reply(100), version: SeekHarness.version(100, 0)))
            page.pump(700)
            let where_ = page.top
            page.page.evaluate("__input('\(kind)', true)")
            let steps = page.steps(slot)
            #expect(steps?.last == .userMoved && steps?.contains(.turnFound) == false, "\(kind): \(String(describing: steps))")
            #expect(page.top <= where_ + 1 && page.top < page.bottom, "\(kind): it did not scroll on, or put the page back")
            #expect(page.marks.isEmpty)
        }
    }

    @Test func eventsThePageMakesItselfAreNotTheUsersHands() {
        let page = SeekHarness()
        let slot = page.start(reply(SeekHarness.reply(150), version: SeekHarness.version(150, 0)))
        for kind in ["wheel", "touchstart", "keydown", "mousedown"] {
            page.pump(200)
            page.page.evaluate("__input('\(kind)', false)")
        }
        #expect(page.steps(slot) == [.topReached, .turnFound, .trayShown, .cardMarked])
    }

    @Test func aNewerRunPutsAnOlderOneAside() {
        let page = SeekHarness()
        let first = page.start(reply(SeekHarness.reply(100), version: SeekHarness.version(100, 0)))
        page.pump(600)
        let second = page.start(SourceSeekRequest(mode: .newest, row: nil, version: nil, name: nil, readyMs: 2_000, seekMs: 8_000, settleMs: 300))
        #expect(page.steps(second) == [.newest])
        let older = page.steps(first)
        #expect(older?.last == .gaveUp && older?.contains(.turnFound) == false, "\(String(describing: older))")
        page.pump(2_000)
        #expect(page.top == page.bottom, "the older run did not scroll the page away again")
    }

    // MARK: Giving up

    @Test func aReplyThePageDrawsNoElementForIsGivenUpOnAndThePageIsPutBack() {
        let page = SeekHarness()
        // Message 2322 is a tool's result: inside what is drawn, and no element.
        let steps = page.run(reply(2322, version: SeekHarness.version(290, 0)))
        #expect(steps == [.turnNotFound])
        #expect(page.top == page.bottom, "the page is as it was opened: at the newest reply")
        #expect(page.marks.isEmpty)
    }

    @Test func aReplyOlderThanAnythingThatCanBeLoadedIsGivenUpOnWithinTheTime() {
        // A session continued from another: the first 1000 messages are folded away and never load.
        let page = SeekHarness(.init(floor: 1_000))
        let steps = page.run(reply(500, version: SeekHarness.version(60, 0)))
        #expect(steps == [.topReached, .turnNotFound])
        #expect(page.top == page.bottom, "back at the newest reply")
        #expect(page.now <= 10_000, "\(page.now) ms")
        #expect(page.marks.isEmpty)
    }

    @Test func earlierMessagesThatFailToLoadAreGivenUpOn() {
        let page = SeekHarness(.init(failLoads: true))
        let steps = page.run(reply(SeekHarness.reply(100), version: SeekHarness.version(100, 0)))
        #expect(steps == [.topReached, .turnNotFound])
        #expect(page.top == page.bottom)
    }

    @Test func aSessionPageWithNoConversationIsNoScrollerWithinTheWait() {
        let page = SeekHarness(.init(empty: true))
        let steps = page.run(SourceSeekRequest(mode: .reply, row: 40, version: nil, name: nil, readyMs: 500, seekMs: 8_000, settleMs: 300))
        #expect(steps == [.noScroller])
        #expect(page.now < 1_000, "\(page.now) ms")
    }

    // MARK: No reply

    @Test func theNewestReplyIsTheEndOfTheConversation() {
        let page = SeekHarness()
        page.page.evaluate("scroller.scrollTop = 1000;")
        page.pump(500)
        let steps = page.run(SourceSeekRequest(mode: .newest, row: nil, version: SeekHarness.version(299, 0), name: nil, readyMs: 2_000, seekMs: 8_000, settleMs: 300))
        #expect(steps == [.newest])
        #expect(page.top == page.bottom)
        #expect(page.marks.isEmpty, "no reply is known, so no card is outlined")
    }

    // MARK: What it leaves

    @Test func nothingOfThePageIsChangedAndNothingIsLeftListeningOrWatching() {
        let page = SeekHarness()
        let listeners = page.number("__documentListeners()")
        _ = page.run(reply(SeekHarness.reply(298), version: SeekHarness.version(298, 0)))
        // The tray it outlined is the tray as it was made: no attribute, class or style of the page's own changed.
        #expect(page.text("__attributesOf(__tray(298))") == page.text("__attributesOf(__fresh(298))"))
        #expect(page.number("__documentListeners()") == listeners, "the four listeners are taken off")
        #expect(page.number("__watching()") == 0, "no observer")
        #expect(page.text("globalThis.capsidSourceSeek") == "null", "and its mark in the page's world is taken down")
    }

    @Test func withoutTheBrowsersAnimationsNothingIsClaimedDrawn() {
        let page = SeekHarness(noAnimate: true)
        let steps = page.run(reply(SeekHarness.reply(298), version: SeekHarness.version(298, 0)))
        #expect(steps == [.turnFound, .trayShown])
    }
}
