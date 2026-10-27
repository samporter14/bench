// ShowSourceTests.swift — Show Where It Came From's Swift side (Shelf/ShowSource.swift,
// Shelf/SourceSeek.swift): which reply an item points at (the row its README names, else
// the reply found for its version, else none), the main window going to the session (or
// staying where it is), the page's steps checked word by word and logged as one line, and
// the ⋯ menu's Open as Reference, which is what the button was before. Every reach into
// the app and the page is a made-up one: no window, no daemon, no page.
import Foundation
import Testing
@testable import Bench

private let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
private let other = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
private let version = "6d1f0c2e-7a3b-4c8d-9e10-2b3c4d5e6f70"

/// A made-up app and page, and what they were asked.
@MainActor
final class SourceRig {
    var port: Int? = 8123
    var opened: [URL] = []
    var windows = 0
    var readOnly = false
    /// The session the main window is on, and whether its page is up.
    var onSession: String?
    var up = false
    /// The page comes up on the session this many polls after it is opened (none: never).
    var comesUpAfter: Int? = 1
    private var pending: String?
    private(set) var polls = 0
    /// What the look for a version's reply was asked, and what it answers.
    var looks: [(frame: String, versions: [String], near: Date?)] = []
    var lookAnswer: ShowingRead = .notFound
    var lookHangs = false
    /// What the page was asked, and the steps it answers.
    var seeks: [SourceSeekRequest] = []
    var seekAnswer: [SourceStep] = [.turnFound, .trayShown, .cardMarked]
    /// The page goes elsewhere while the look is under way.
    var leavesDuringLook = false
    var notes: [String] = []
    var breadcrumbs: [CompatMiss] = []

    func dependencies() -> ShowSourceDependencies {
        ShowSourceDependencies(
            port: { [unowned self] in port },
            open: { [unowned self] url in
                opened.append(url)
                windows += 1
                pending = url.pathComponents.last
                up = false
                polls = 0
            },
            showWindow: { [unowned self] in windows += 1 },
            readOnly: { [unowned self] in readOnly },
            isOn: { [unowned self] in onSession == $0 },
            isShowing: { [unowned self] in onSession == $0 && up },
            showing: { [unowned self] frame, versions, near in
                looks.append((frame, versions, near))
                if leavesDuringLook { up = false }
                if lookHangs {
                    try? await Task.sleep(for: .seconds(3_600))
                    return .unreadable
                }
                return lookAnswer
            },
            seek: { [unowned self] request in
                seeks.append(request)
                return seekAnswer
            },
            note: { [unowned self] in notes.append($0) },
            breadcrumb: { [unowned self] in breadcrumbs.append($0) },
            wait: { [unowned self] duration in
                if duration == .milliseconds(100) {
                    polls += 1
                    if let comesUpAfter, polls >= comesUpAfter, let pending {
                        onSession = pending
                        up = true
                    }
                    await Task.yield()
                } else if duration == ShowSourceRules.lookupTime && lookTimesOut {
                    await Task.yield()
                } else {
                    // A timer that is not wanted: it ends only when the work does, or the task is cancelled.
                    try? await Task.sleep(for: .seconds(3_600))
                }
            })
    }

    /// The look is given up on at its time.
    var lookTimesOut = false

    /// An app already on a session, with its page up.
    func alreadyOn(_ id: String) {
        onSession = id
        up = true
    }

    var line: String? { notes.last }
}

private func ask(row: Int? = nil, version: String? = version, name: String? = "z_prime.png", near: Date? = nil,
                 session id: String = session, project: String = "proj_a") -> SourceAsk {
    SourceAsk(sessionID: id, projectID: project, title: "Plate reader QC", projectName: "Assay development",
              row: row, version: version, name: name, near: near)
}

@MainActor
struct ShowSourceTests {
    private func showing(_ rig: SourceRig, _ ask: SourceAsk) async {
        await ShowSource(dependencies: rig.dependencies()).show(ask).value
    }

    private func found(_ row: Int) -> ShowingRead {
        .found(ShowingMessage(i: row, at: nil, text: "Here is the plot.", how: .image, v: version))
    }

    // MARK: Which reply

    @Test func theRowAnItemNamesIsUsedAsItStandsAndNothingIsLookedFor() async {
        let rig = SourceRig()
        await showing(rig, ask(row: 41))
        #expect(rig.looks.isEmpty)
        #expect(rig.seeks == [SourceSeekRequest(mode: .reply, row: 41, version: version, name: "z_prime.png")])
        #expect(rig.line == "Source: opened → row-known → turn-found → tray-shown → card-marked")
    }

    @Test func withNoRowTheReplyThatShowsTheVersionIsLookedForAndUsed() async {
        let rig = SourceRig()
        rig.lookAnswer = found(57)
        await showing(rig, ask(row: nil))
        #expect(rig.looks.count == 1)
        #expect(rig.looks.first?.frame == session && rig.looks.first?.versions == [version] && rig.looks.first?.near == nil)
        #expect(rig.seeks.map(\.row) == [57] && rig.seeks.map(\.mode) == [.reply])
        #expect(rig.line?.contains("opened → row-found → turn-found") == true)
    }

    @Test func aFoundFileAsksForTheReplyNoEarlierThanTheFile() async {
        let rig = SourceRig()
        rig.lookAnswer = found(9)
        let made = Date(timeIntervalSince1970: 1_791_833_000)
        await showing(rig, ask(near: made))
        #expect(rig.looks.first?.near == made)
    }

    @Test func aVersionNoReplyWasFoundForOpensTheSessionAtItsNewestReplyAndSaysNothingMore() async {
        for answer in [ShowingRead.notFound, .unreadable] {
            let rig = SourceRig()
            rig.seekAnswer = [.newest]
            rig.lookAnswer = answer
            await showing(rig, ask(row: nil))
            #expect(rig.seeks == [SourceSeekRequest(mode: .newest, row: nil, version: nil, name: nil)], "\(answer)")
            #expect(rig.line == "Source: opened → row-none → newest", "\(answer)")
        }
    }

    @Test func aLookThatHangsIsGivenUpOnAtItsTime() async {
        let rig = SourceRig()
        rig.lookHangs = true
        rig.lookTimesOut = true
        await showing(rig, ask(row: nil))
        #expect(rig.seeks.map(\.mode) == [.newest])
        #expect(rig.line?.contains("row-none") == true)
    }

    @Test func aNoteHasNoReplyAndNothingIsLookedFor() async {
        let rig = SourceRig()
        rig.seekAnswer = [.newest]
        await showing(rig, ask(row: nil, version: nil, name: "note.md"))
        #expect(rig.looks.isEmpty)
        #expect(rig.seeks == [SourceSeekRequest(mode: .newest, row: nil, version: nil, name: nil)])
        #expect(rig.line == "Source: opened → row-none → newest")
    }

    @Test func aRowTheHistoryCannotHaveIsNoRowAndTheVersionIsLookedForInstead() async {
        for row in [-1, HistoryReaderScript.maxIndex + 1] {
            let rig = SourceRig()
            rig.lookAnswer = found(12)
            await showing(rig, ask(row: row))
            #expect(rig.looks.count == 1, "\(row)")
            #expect(rig.seeks.map(\.row) == [12], "\(row)")
        }
        let zero = SourceRig()
        await showing(zero, ask(row: 0))
        #expect(zero.looks.isEmpty && zero.seeks.map(\.row) == [0], "row 0 is a row")
    }

    @Test func aVersionThatIsNotAnIdIsNeverSentToTheDaemonOrThePage() async {
        let rig = SourceRig()
        await showing(rig, ask(row: nil, version: "../../etc"))
        #expect(rig.looks.isEmpty)
        #expect(rig.seeks == [SourceSeekRequest(mode: .newest, row: nil, version: nil, name: nil)])
        let withRow = SourceRig()
        await showing(withRow, ask(row: 5, version: "not an id"))
        #expect(withRow.seeks.first?.version == nil && withRow.seeks.first?.row == 5)
    }

    // MARK: The window

    @Test func aWindowOnAnotherPageIsTakenToTheSessionAndTheScrollWaitsForIt() async {
        let rig = SourceRig()
        rig.comesUpAfter = 5
        await showing(rig, ask(row: 3))
        #expect(rig.opened == [URL(string: "http://localhost:8123/projects/proj_a/frames/\(session)")!])
        #expect(rig.polls >= 5)
        #expect(rig.seeks.count == 1)
    }

    @Test func aWindowAlreadyOnTheSessionIsNotReloaded() async {
        let rig = SourceRig()
        rig.alreadyOn(session)
        await showing(rig, ask(row: 3))
        #expect(rig.opened.isEmpty && rig.windows == 1, "brought forward, not loaded again")
        #expect(rig.line?.hasPrefix("Source: already-there → row-known") == true)
        #expect(rig.seeks.count == 1)
    }

    @Test func aWindowOnAnotherSessionIsTakenToThisOne() async {
        let rig = SourceRig()
        rig.alreadyOn(other)
        await showing(rig, ask(row: 3))
        #expect(rig.opened.count == 1)
        #expect(rig.line?.hasPrefix("Source: opened →") == true)
    }

    @Test func aPageThatDoesNotComeUpIsLeftAloneAndSaidSo() async {
        let rig = SourceRig()
        rig.comesUpAfter = nil
        await showing(rig, ask(row: 3))
        #expect(rig.opened.count == 1 && rig.seeks.isEmpty && rig.looks.isEmpty)
        #expect(rig.line == "Source: opened → not-ready")
        #expect(rig.polls == Int(ShowSourceRules.pageWait / .milliseconds(100)))
    }

    @Test func aPageThatWentElsewhereWhileTheReplyWasLookedForIsNotScrolled() async {
        let rig = SourceRig()
        rig.leavesDuringLook = true
        rig.lookAnswer = found(4)
        await showing(rig, ask(row: nil))
        #expect(rig.seeks.isEmpty)
        #expect(rig.line == "Source: opened → row-found → not-ready")
    }

    @Test func aReadOnlyCapsidOpensClaudeSciencesOwnAppAndStops() async {
        let rig = SourceRig()
        rig.readOnly = true
        await showing(rig, ask(row: 3))
        #expect(rig.opened.count == 1 && rig.seeks.isEmpty && rig.looks.isEmpty)
        #expect(rig.line == "Source: read-only")
    }

    @Test func idsThatAreNotASessionOnlyBringTheWindowForward() async {
        for made in [ask(row: 3, project: "../proj"), ask(row: 3, session: "not-a-session")] {
            let rig = SourceRig()
            await showing(rig, made)
            #expect(rig.opened.isEmpty && rig.windows == 1 && rig.seeks.isEmpty)
            #expect(rig.line == "Source: no-address")
        }
    }

    @Test func aNewerClickReplacesAnOlderOne() async {
        let rig = SourceRig()
        // The first click's page never comes up; the second finds it up.
        rig.comesUpAfter = nil
        let shower = ShowSource(dependencies: rig.dependencies())
        let first = shower.show(ask(row: 1))
        await Task.yield()
        rig.comesUpAfter = 1
        let second = shower.show(ask(row: 2))
        await first.value
        await second.value
        #expect(rig.seeks.map(\.row) == [2], "only the newer click scrolled")
        #expect(rig.notes.count == 2)
        #expect(rig.notes.contains("Source: opened"), "the older one logged how far it got, and no reason it didn't finish")
        #expect(rig.notes.contains("Source: opened → row-known → turn-found → tray-shown → card-marked"))
    }

    // MARK: The page's answer

    @Test func aPageWithNoConversationLeavesABreadcrumb() async {
        let rig = SourceRig()
        rig.seekAnswer = [.noScroller]
        await showing(rig, ask(row: 3))
        #expect(rig.breadcrumbs == [.showSourceNoConversation])
        #expect(rig.line == "Source: opened → row-known → no-scroller")
        for steps in [[SourceStep.turnNotFound], [.userMoved], [.gaveUp], [.turnFound, .trayNone]] {
            let quiet = SourceRig()
            quiet.seekAnswer = steps
            await showing(quiet, ask(row: 3))
            #expect(quiet.breadcrumbs.isEmpty, "\(steps)")
        }
    }

    @Test func theStepsArePassedWordByWordAndNothingElseIsLogged() {
        let answer = #"{"steps":["top-reached","turn-found","<script>","/home/someone/plates.png","tray-shown",7,null,"card-marked"]}"#
        #expect(SourceSeek.steps(of: answer) == [.topReached, .turnFound, .trayShown, .cardMarked])
        #expect(SourceSeek.steps(of: #"{"steps":[]}"#) == [])
        #expect(SourceSeek.steps(of: "not json") == nil)
        #expect(SourceSeek.steps(of: #"{"steps":"turn-found"}"#) == nil)
        #expect(SourceSeek.steps(of: nil) == nil && SourceSeek.steps(of: 5) == nil)
        let many = "{\"steps\":[" + Array(repeating: "\"newest\"", count: 40).joined(separator: ",") + "]}"
        #expect(SourceSeek.steps(of: many)?.count == SourceSeek.maxSteps)
        #expect(SourceSeek.line([.opened, .rowKnown, .turnFound, .trayShown]) == "Source: opened → row-known → turn-found → tray-shown")
        #expect(SourceSeek.line([]) == "Source: no steps")
    }

    @Test func everyStepIsAFixedWordWithNoSpaceOrDigitInIt() {
        for step in SourceStep.allCases {
            #expect(step.rawValue.allSatisfy { $0.isLowercase || $0 == "-" }, "\(step)")
        }
        #expect(Set(SourceStep.allCases.map(\.rawValue)).count == SourceStep.allCases.count)
    }

    @Test func theRequestSendsTheModeAndOnlyWhatTheScriptNeeds() {
        let reply = SourceSeekRequest(mode: .reply, row: 41, version: version, name: String(repeating: "n", count: 500))
        let arguments = reply.arguments
        #expect(arguments["mode"] as? String == "reply" && arguments["row"] as? Int == 41 && arguments["version"] as? String == version)
        #expect((arguments["name"] as? String)?.count == SourceSeek.maxName, "a long name is cut")
        #expect(arguments["readyMs"] as? Int == SourceSeek.readyMs && arguments["seekMs"] as? Int == SourceSeek.seekMs)
        let newest = SourceSeekRequest(mode: .newest, row: 41, version: nil, name: nil).arguments
        #expect(newest["mode"] as? String == "newest" && newest["row"] is NSNull, "a row is no use to the newest reply")
        #expect(newest["version"] is NSNull && newest["name"] is NSNull)
    }

    // MARK: What asks

    @Test func aShelvedItemAsksWithItsRowItsVersionAndItsName() {
        let made = KeptRecord(
            name: "z", keptAt: Date(timeIntervalSince1970: 1_791_833_000), projectID: "proj_a", projectName: "Assay development",
            sessionID: session, sessionTitle: "Plate reader QC",
            figure: KeptFile(path: "z_prime.png", role: .figure, artifact: "a", version: version, index: 1, of: nil, sha256: nil, bytes: 10),
            files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0.7", sourceRow: 41, question: nil, answerAt: nil)
        let result = KeptResult(folder: URL(fileURLWithPath: "/made-up/Kept/z", isDirectory: true), collection: "Assay development",
                                record: made, text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
        let item = ShelfItem(result: result, others: [])
        #expect(SourceAsk(item) == SourceAsk(sessionID: session, projectID: "proj_a", title: "Plate reader QC", projectName: "Assay development",
                                              row: 41, version: version, name: "z_prime.png", near: nil))
        var note = made
        note.figure = KeptFile(path: "note.md", role: .figure, artifact: nil, version: nil, index: nil, of: nil, sha256: nil, bytes: 4)
        note.sourceRow = nil
        let noteItem = ShelfItem(result: KeptResult(folder: result.folder, collection: "Assay development", record: note, text: result.text), others: [])
        #expect(SourceAsk(noteItem).version == nil && SourceAsk(noteItem).row == nil, "a note has no reply to look for")
    }

    @Test func aFoundFileAsksWithNoRowAndItsTime() {
        let file = FoundFile(version: version, artifact: "a", name: "z_prime.png", mime: "image/png", size: 10, createdMs: 1_791_833_000_000,
                             number: 2, sessionID: session, sessionTitle: "Plate reader QC", projectID: "proj_a", projectName: "Assay development")
        let made = SourceAsk(file)
        #expect(made.row == nil && made.version == version && made.name == "z_prime.png")
        #expect(made.near == Date(timeIntervalSince1970: 1_791_833_000 - 60), "less a minute for the two clocks")
    }

    @Test func theAddressIsTheSessionsAndNothingElse() {
        #expect(ShowSourceRules.address(ask(), port: 8123)?.absoluteString == "http://localhost:8123/projects/proj_a/frames/\(session)")
        #expect(ShowSourceRules.address(ask(project: "a/../b"), port: 8123) == nil)
        #expect(ShowSourceRules.address(ask(session: "xyz"), port: 8123) == nil)
    }

    // MARK: Open as Reference

    @Test func theDetailAndTheGridCardOfferOpenAsReferenceAndTheButtonGoesToTheConversation() throws {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let actions = try #require(view.range(of: "enum ShelfActions {"))
        let body = String(view[actions.lowerBound...].prefix(upTo: view.range(of: "/// The file on the pasteboard at once")!.lowerBound))
        // The button: the conversation. The old behaviour: the reference reader, under its own name.
        #expect(body.contains("static func showWhereItCameFrom(_ item: ShelfItem) {\n        ShowSource.shared.show(SourceAsk(item))\n    }"))
        #expect(body.contains("static func openAsReference(_ item: ShelfItem) {"))
        #expect(body.contains("ReferenceWindowController.shared.show(sessionID: record.sessionID"))
        #expect(body.contains("at: record.sourceRow, mark: record.figure.version"))
        // The grid card's menu: Show Where It Came From, then Open as Reference, then Quick Look, the first two off in a demo.
        let card = try #require(view.range(of: "private func card(_ item: ShelfItem)"))
        let menu = String(view[card.lowerBound...].prefix(upTo: view.range(of: "// MARK: Nothing to show")!.lowerBound))
        let show = try #require(menu.range(of: #"Button("Show Where It Came From") { ShelfActions.showWhereItCameFrom(item) }"#))
        let reference = try #require(menu.range(of: "Button(ConversationAction.openAsReference.title) { ShelfActions.openAsReference(item) }"))
        let quick = try #require(menu.range(of: #"Button("Quick Look")"#))
        #expect(show.upperBound < reference.lowerBound && reference.upperBound < quick.lowerBound)
        #expect(menu[show.upperBound..<reference.lowerBound].contains(".disabled(Demo.mode != nil)"))
        #expect(menu[reference.upperBound..<quick.lowerBound].contains(".disabled(Demo.mode != nil)"))
        // The detail's ⋯ item runs it, and is off in a demo as Show Where It Came From is.
        let perform = try #require(view.range(of: "private func perform(_ entry: ShelfRules.MoreItem)"))
        let performs = String(view[perform.lowerBound...].prefix(900))
        #expect(performs.contains("case .openAsReference:\n            guard Demo.mode == nil else { return }\n            ShelfActions.openAsReference(item)"))
        #expect(view.contains(".disabled((entry == .keepWithDataAndCode || entry == .openAsReference) && Demo.mode != nil)"))
    }

    @Test func findsShowWhereGoesToTheConversationToo() {
        let actions = FindRepo.source("Find/FindActions.swift")
        #expect(actions.contains("show: { file in ShowSource.shared.show(SourceAsk(file)) },"))
        #expect(!actions.contains("ReferenceWindowController.shared.show"))
    }

    @Test func openAsReferenceIsTheWordsTheConversationMenuHas() {
        #expect(ShelfRules.MoreItem.openAsReference.title == ConversationAction.openAsReference.title)
        #expect(ShelfRules.MoreItem.openAsReference.spoken == "Open as Reference")
    }
}
