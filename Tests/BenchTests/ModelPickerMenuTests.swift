// ModelPickerMenuTests.swift — "Ask Another Model…" in Claude Science's model
// menu (AskModel/ModelPickerMenu.swift), the Swift side: how the page script's
// messages are read, who is heard (the main window's page and no one else), what
// the page is told (may the item be offered), what each message does — a
// breadcrumb, a log line, the window — over a made-up window and nothing sent
// to Claude Science. The script itself runs in ModelMenuScriptTests; WebKit's
// own delivery of messages, and the menu as drawn, are checked by eye and by
// the snapshot test when asked (TESTING.md).
import AppKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct ModelPickerMenuTests {
    /// What a made-up menu was asked, said and did.
    @MainActor
    final class Rig {
        var wanted = true
        var ran: [String?] = []
        var traced: [String] = []
        let lines = ModelMenuLines()
        lazy var breadcrumbs = CompatBreadcrumbs(emit: { [lines] in lines.add($0) })
        lazy var menu = ModelPickerMenu(daemonPort: { 8123 }, mayOffer: { [unowned self] in wanted }, breadcrumbs: breadcrumbs,
                                        traced: { [unowned self] in traced.append($0) }, run: { [unowned self] in ran.append($0) })
    }

    // MARK: Reading the messages

    @Test func theMessagesAreReadByTheirShape() {
        #expect(ModelMenuMessage.isArmed(["armed": true]))
        #expect(!ModelMenuMessage.isArmed(["armed": false]))
        #expect(!ModelMenuMessage.isArmed(["armed": "yes"]))
        #expect(!ModelMenuMessage.isArmed(["ask": true]))
        #expect(!ModelMenuMessage.isArmed(nil))
        #expect(!ModelMenuMessage.isArmed("armed"))
        #expect(ModelMenuMessage.choice(in: ["ask": true, "draft": "Which buffer?"]) == .init(seed: "Which buffer?"))
        #expect(ModelMenuMessage.choice(in: ["ask": true]) == .init(seed: nil))
        #expect(ModelMenuMessage.choice(in: ["ask": false, "draft": "x"]) == nil)
        #expect(ModelMenuMessage.choice(in: ["armed": true]) == nil)
        #expect(ModelMenuMessage.choice(in: "ask") == nil)
        #expect(ModelMenuMessage.isUnplaced(["unplaced": true]))
        #expect(!ModelMenuMessage.isUnplaced(["unplaced": 1]))
        #expect(!ModelMenuMessage.isUnplaced(nil))
    }

    @Test func aDraftIsTheSeedOfTheQuestionTrimmedAndCut() {
        #expect(ModelMenuMessage.seed("  Which buffer?\n") == "Which buffer?")
        #expect(ModelMenuMessage.seed("") == nil)
        #expect(ModelMenuMessage.seed(" \n\t ") == nil)
        #expect(ModelMenuMessage.seed(NSNull()) == nil)
        #expect(ModelMenuMessage.seed(42) == nil)
        #expect(ModelMenuMessage.seed(nil) == nil)
        let long = String(repeating: "x", count: AskRules.maxQuestion * 2)
        #expect(ModelMenuMessage.seed(long)?.count == AskRules.maxQuestion)
        // The window takes it the same way: a blank seed is the session's last question.
        let viewed = ViewedSession(id: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC", projectID: "proj_a",
                                projectName: "Assay development")
        #expect(AskModelWindowController.subject(viewed, seed: "  HEPES at 25 mM?  ").seed == "HEPES at 25 mM?")
        #expect(AskModelWindowController.subject(viewed, seed: "   ").seed == nil)
        #expect(AskModelWindowController.subject(viewed, seed: nil).seed == nil)
    }

    @Test func aTraceIsReadAsTheScriptsFixedWordsAndNothingElse() {
        #expect(ModelMenuMessage.trace(in: ["trace": ["armed", "allowed", "menu-matched", "placed"]])
                == [.armed, .allowed, .menuMatched, .placed])
        // A word the script doesn't have, or not a word, is dropped: nothing from the page reaches the log.
        #expect(ModelMenuMessage.trace(in: ["trace": ["armed", "Large", 3, NSNull(), "menu-none"] as [Any]]) == [.armed, .menuNone])
        #expect(ModelMenuMessage.trace(in: ["trace": [String]()]) == [])
        #expect(ModelMenuMessage.trace(in: ["trace": Array(repeating: "armed", count: 50)])?.count == ModelMenuMessage.maxSteps)
        #expect(ModelMenuMessage.trace(in: ["trace": "armed"]) == nil)
        #expect(ModelMenuMessage.trace(in: ["armed": true]) == nil)
        #expect(ModelMenuMessage.trace(in: nil) == nil)
        // Every word the script can say is one of the steps.
        let said = ["armed", "allowed", "refused", "no-observer", "menu-matched", "menu-other", "menu-none", "placed", "unplaced", "interrupted"]
        #expect(Set(ModelMenuStep.allCases.map(\.rawValue)) == Set(said))
        for word in said {
            #expect(ModelPickerMenu.script.contains("\"\(word)\""), "the script never says \(word)")
        }
    }

    @Test func aTracesLineIsItsStepsInOrder() {
        #expect(ModelMenuMessage.line([.armed, .refused]) == "Model menu: armed → refused")
        #expect(ModelMenuMessage.line([]) == "Model menu: no steps")
    }

    // MARK: Who is heard

    @Test func onlyTheMainWebViewsMainFrameOnTheDaemonsOriginIsHeard() {
        // The rule the tab menu and the figure menu share: a pop-up shares the script and can be someone else's page.
        #expect(TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: false, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: false, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: false))
        // The daemon's origin is localhost or 127.0.0.1 on the daemon's own port, over http.
        #expect(WebRoute.isDaemonOrigin(scheme: "http", host: "localhost", port: 8123, daemonPort: 8123))
        #expect(WebRoute.isDaemonOrigin(scheme: "http", host: "127.0.0.1", port: 8123, daemonPort: 8123))
        #expect(!WebRoute.isDaemonOrigin(scheme: "http", host: "localhost", port: 9999, daemonPort: 8123))
        #expect(!WebRoute.isDaemonOrigin(scheme: "https", host: "localhost", port: 8123, daemonPort: 8123))
        #expect(!WebRoute.isDaemonOrigin(scheme: "http", host: "example.com", port: 8123, daemonPort: 8123))
        #expect(!WebRoute.isDaemonOrigin(scheme: "http", host: "localhost", port: 8123, daemonPort: nil))
    }

    @Test func theWiringAsksTheSenderBeforeAnythingIsHeard() throws {
        // The proxy the web view's controller holds calls `receive`, which works out who sent the message from the message
        // itself and hands `hear` the answer; no test builds a script message, so the wiring is read.
        let source = try #require(Self.source("AskModel/ModelPickerMenu.swift"))
        #expect(source.contains("isMainFrame: message.frameInfo.isMainFrame"))
        #expect(source.contains("fromMainWebView: message.webView != nil && message.webView === webView"))
        #expect(source.contains("isDaemonOrigin: WebRoute.isDaemonOrigin(scheme: origin.protocol, host: origin.host, port: origin.port,"))
        #expect(source.contains("return hear(message.body, accepted: accepted)"))
        // A proxy that has lost its menu still answers: the page waits on the answer.
        #expect(source.contains("replyHandler(menu?.receive(message) ?? [\"show\": false], nil)"))
        // The web view it is told it is the main window's.
        let container = try #require(Self.source("Web/WebContainer.swift"))
        #expect(container.contains("modelMenu.webView = view"))
        #expect(container.contains("modelMenu.install(on: configuration.userContentController)"))
        // The controller holds the handler's proxy weakly, so the container must keep the menu itself: a menu that is let
        // go answers every press with a no, and nothing in a test of the script would say so.
        #expect(container.contains("private let modelMenu: ModelPickerMenu"))
        #expect(container.contains("self.modelMenu = modelMenu"))
    }

    @Test func aMessageFromAnyoneElseIsNothingAndTheAnswerIsNo() {
        let rig = Rig()
        for body in [["armed": true], ["ask": true, "draft": "Which buffer?"], ["unplaced": true], ["trace": ["armed", "placed"]]] as [[String: Any]] {
            #expect(rig.menu.hear(body, accepted: false) == ["show": false])
        }
        #expect(rig.ran.isEmpty)
        #expect(rig.traced.isEmpty)
        #expect(rig.breadcrumbs.last == nil)
        #expect(rig.lines.all.isEmpty)
    }

    // MARK: What the page is told, and what each message does

    @Test func theAnswerToAPressIsWhetherTheItemIsWantedRightNow() {
        let rig = Rig()
        #expect(rig.menu.hear(["armed": true], accepted: true) == ["show": true])
        rig.wanted = false
        #expect(rig.menu.hear(["armed": true], accepted: true) == ["show": false])
        #expect(rig.ran.isEmpty)
    }

    @Test func theItemOpensTheWindowWithTheDraftOnlyWhileItIsStillWanted() {
        let rig = Rig()
        rig.menu.hear(["ask": true, "draft": "  Which buffer should the rerun use?  "], accepted: true)
        rig.menu.hear(["ask": true, "draft": ""], accepted: true)
        rig.menu.hear(["ask": true], accepted: true)
        #expect(rig.ran == ["Which buffer should the rerun use?", nil, nil])
        // Switched off while the menu was open (or the session left): nothing opens.
        rig.wanted = false
        rig.menu.hear(["ask": true, "draft": "Which buffer?"], accepted: true)
        #expect(rig.ran.count == 3)
    }

    @Test func anUnplacedMessageLeavesABreadcrumbAndNothingElse() {
        let rig = Rig()
        rig.menu.hear(["unplaced": true], accepted: false)
        #expect(rig.breadcrumbs.last == nil)
        rig.menu.hear(["unplaced": true], accepted: true)
        #expect(rig.breadcrumbs.last?.miss == .modelMenuNotUnderstood)
        #expect(rig.breadcrumbs.last?.miss.feature == .modelMenu)
        #expect(rig.lines.all == ["Claude Science may have changed: Ask Another Model in Claude Science's model menu: the model menu didn't look as Capsid expects"])
        #expect(rig.ran.isEmpty)
        #expect(rig.traced.isEmpty)
    }

    @Test func aTraceFromThePageIsLoggedAndNothingElseHappens() {
        let rig = Rig()
        rig.menu.hear(["trace": ["armed", "allowed", "menu-matched", "placed"]], accepted: true)
        #expect(rig.traced == ["Model menu: armed → allowed → menu-matched → placed"])
        rig.menu.hear(["trace": ["armed", "plate_map.png"] as [Any]], accepted: true)
        #expect(rig.traced.last == "Model menu: armed")
        #expect(rig.ran.isEmpty)
        #expect(rig.breadcrumbs.last == nil)
    }

    @Test func aMessageThatIsNoneOfTheFourIsHeardAsNothing() {
        let rig = Rig()
        for body in [nil, "armed", 5, ["kind": "image"], ["trace": 3], [:]] as [Any?] {
            #expect(rig.menu.hear(body, accepted: true) == ["show": false])
        }
        #expect(rig.ran.isEmpty && rig.traced.isEmpty && rig.breadcrumbs.last == nil)
    }

    @Test func theLogLineIsFixedWordsAndNeverTheDraft() {
        // Nothing from a draft can reach a line: the lines are the steps' words, and the draft goes to `run` alone.
        let rig = Rig()
        rig.menu.hear(["ask": true, "draft": "A made-up private question"], accepted: true)
        rig.menu.hear(["trace": ["armed", "A made-up private question"]], accepted: true)
        #expect(!(rig.traced + rig.lines.all).contains { $0.contains("private") })
    }

    @Test func itIsWantedWhileTheFeatureIsAvailableAndASessionIsShownAndNotInADemo() {
        // File's rule, shared: `ModelPickerMenu.isWanted` is `AskMenu.fileItem(...).enabled`.
        let source = Self.source("AskModel/ModelPickerMenu.swift") ?? ""
        #expect(source.contains("AskMenu.fileItem(available: AnotherModel.shared.isAvailable, session: WebContainer.shared.currentFrameID,"))
        #expect(source.contains("demo: Demo.mode != nil).enabled"))
    }

    private static func source(_ relative: String) -> String? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try? String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)
    }
}

/// The log lines a made-up breadcrumb store emitted.
final class ModelMenuLines: @unchecked Sendable {
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
