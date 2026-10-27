// CompanionStartTests.swift — the home popover's two additions (DESIGN.md, Menu
// bar home): Recent (which sessions, in what order, what a click and an ⌥-click
// do, Copy Link's address) and the "Start a session…" field's project and send
// (the pill's default and menu, ↩ through Quick Start's flow with the chosen
// project, ⌘↩ handing the words and the project to Quick Start, the sending and
// outcome lines). On made-up sessions and a fake sender: nothing is sent, no
// window opens, nothing is read while the popover is closed.
import Combine
import Foundation
import Testing
@testable import Bench

private let now = Date(timeIntervalSince1970: 1_792_000_000)

private func session(_ n: Int, _ state: SessionState, minutesAgo: Double, project: String = "Assay development",
                     reason: WaitingReason? = nil) -> SessionStatus {
    SessionStatus(id: "00000000-0000-4000-8000-00000000c\(String(format: "%03d", n))", projectID: "proj_assay", projectName: project,
                  title: "Session \(n)", state: state, updatedAt: now.addingTimeInterval(-minutesAgo * 60),
                  startedAt: state == .running ? now.addingTimeInterval(-600) : nil, waitingReason: reason)
}

@MainActor
private func sections(asks: [SessionStatus] = [], failed: [SessionStatus] = [], working: [SessionStatus] = [],
                      snoozed: [SnoozedReminder] = [], recent: [SessionStatus]) -> CompanionSections {
    CompanionSections.make(CompanionSections.Input(
        needs: NeedsYou(waiting: asks + snoozed.map(\.session), snoozed: snoozed, failed: failed), working: working,
        offer: { _ in CardOffer(lead: .button(.open)) }, canLater: { _ in true }, planSteps: { _ in nil },
        pause: { _ in nil }, progress: { _ in nil }, results: [], resultsPartial: false, since: nil, usage: nil,
        problem: nil, now: now, recent: recent))
}

// MARK: Recent: which sessions, and in what order

@MainActor
struct CompanionRecentTests {
    @Test func recentLeavesOutEverySessionShownAboveItEvenOnesBehindNMore() {
        let asks = (1...5).map { session($0, .needsInput, minutesAgo: Double($0), reason: .question) }
        let stopped = session(6, .error, minutesAgo: 2)
        let working = [session(7, .running, minutesAgo: 1), session(8, .running, minutesAgo: 3)]
        let quiet = [session(9, .finished, minutesAgo: 4), session(10, .finished, minutesAgo: 30)]
        let made = sections(asks: asks, failed: [stopped], working: working, recent: asks + [stopped] + working + quiet)
        #expect(made.needsHidden > 0, "two asks are behind \"N more\"")
        #expect(made.recent.map(\.session.id) == quiet.map(\.id), "nothing that Needs you or Working holds, shown or not")
        #expect(made.recentTotal == 2 && made.recentHidden == 0)
    }

    @Test func recentIsTheFiveMostRecentlyActiveNewestFirstOnceEach() {
        let quiet = [30, 2, 400, 9, 61, 5000, 45].enumerated().map { session($0.offset + 1, .finished, minutesAgo: Double($0.element)) }
        let made = sections(recent: quiet + [quiet[1]])
        #expect(made.recentTotal == CompanionSections.recentLimit)
        #expect(made.recent.map(\.session.title) == ["Session 2", "Session 4", "Session 1", "Session 7", "Session 5"],
                "the newest first, five at most, a session listed once")
    }

    @Test func aBusyPopoverShowsThreeAndSaysHowManyMoreAQuietOneShowsAllFive() {
        let quiet = (1...7).map { session($0, .finished, minutesAgo: Double($0) * 10) }
        let busy = sections(working: [session(20, .running, minutesAgo: 1)], recent: quiet)
        #expect(busy.recent.count == CompanionSections.rowLimit && busy.recentHidden == 2 && busy.recentTotal == 5)
        let calm = sections(recent: quiet)
        #expect(calm.isQuiet && calm.recent.count == 5 && calm.recentHidden == 0)
        #expect(CompanionSections.recentShown(2, quiet: false) == 2 && CompanionSections.recentShown(9, quiet: true) == 5)
    }

    @Test func recentKeepsToTheRoomUnderTheMenuBarButNeverToFewerThanTwo() {
        #expect(CompanionSections.recentShown(5, quiet: false) == 3, "no room known: the lists' three")
        #expect(CompanionSections.recentShown(5, quiet: false, room: 2000, used: 400) == 3)
        #expect(CompanionSections.recentShown(5, quiet: true, room: 2000, used: 36) == 5)
        // Two rows' worth: the title, the hairline, "N more" and two rows.
        let two: CGFloat = 26 + 13 + 24 + 2 * 44
        #expect(CompanionSections.recentShown(5, quiet: false, room: 400 + two, used: 400) == 2)
        #expect(CompanionSections.recentShown(5, quiet: false, room: 100, used: 400) == 2, "never fewer than two")
        #expect(CompanionSections.recentShown(1, quiet: false, room: 100, used: 400) == 1)
        // Board 1's state in a 900-point room: two Needs you rows, two working, the files.
        let files = (1...4).map { ArtifactEntry(version: "v\($0)", artifact: nil, name: "f\($0).png", mime: "image/png", size: 1, at: now) }
        let quiet = (1...6).map { session($0, .finished, minutesAgo: Double($0) * 10) }
        let made = CompanionSections.make(CompanionSections.Input(
            needs: NeedsYou(waiting: [session(10, .needsInput, minutesAgo: 3, reason: .question),
                                      session(11, .needsInput, minutesAgo: 9, reason: .plan)], snoozed: [], failed: []),
            working: [session(12, .running, minutesAgo: 1), session(13, .running, minutesAgo: 2)],
            offer: { _ in CardOffer(lead: .button(.open)) }, canLater: { _ in true }, planSteps: { _ in nil },
            pause: { _ in nil }, progress: { _ in nil }, results: files, resultsPartial: false, since: nil, usage: nil,
            problem: nil, now: now, recent: quiet, room: 900 - CompanionHomeView.pinnedHeight))
        #expect(made.recent.count == 2 && made.recentHidden == 3 && made.recentTotal == 5,
                "Recent takes what the other blocks leave; the rest are behind \"3 more\"")
    }

    @Test func aSessionPutOffWithLaterIsRecentAndItsDotSaysItStillWaits() {
        let putOff = session(1, .needsInput, minutesAgo: 3, reason: .question)
        let made = sections(snoozed: [SnoozedReminder(session: putOff, due: now.addingTimeInterval(300))],
                            recent: [putOff, session(2, .finished, minutesAgo: 9)])
        #expect(made.needsTotal == 0)
        #expect(made.recent.map(\.waits) == [true, false])
    }

    @Test func recentSitsAfterWorkingAndBeforeResultsAndIsLeftOutWhenEmpty() {
        let files = [ArtifactEntry(version: "v1", artifact: nil, name: "volcano.png", mime: "image/png", size: 1, at: now)]
        var input = CompanionSections.Input(
            needs: NeedsYou(waiting: [session(1, .needsInput, minutesAgo: 5, reason: .question)], snoozed: [], failed: []),
            working: [session(2, .running, minutesAgo: 1)], offer: { _ in CardOffer(lead: .button(.open)) },
            canLater: { _ in true }, planSteps: { _ in nil }, pause: { _ in nil }, progress: { _ in nil },
            results: files, resultsPartial: false, since: nil, usage: nil, problem: nil, now: now,
            recent: [session(3, .finished, minutesAgo: 20)])
        #expect(CompanionSections.make(input).blocks == [.needs, .working, .recent, .results])
        input.recent = []
        #expect(CompanionSections.make(input).blocks == [.needs, .working, .results])
        #expect(sections(recent: [session(4, .finished, minutesAgo: 1)]).blocks == [.quiet, .recent])
    }

    @Test func aRowSaysItsProjectAndWhenInTheShelfsWords() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let locale = Locale(identifier: "en_US")
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 8, minute: 47))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: morning)!
        #expect(CompanionText.recentDetail(project: "Assay development", at: morning, now: today, calendar: calendar, locale: locale)
            == "Assay development · 8:47\u{202F}AM")
        #expect(CompanionText.recentDetail(project: "Cloning", at: yesterday, now: today, calendar: calendar, locale: locale)
            == "Cloning · Yesterday")
        let row = sections(recent: [session(1, .finished, minutesAgo: 12)]).recent.first
        #expect(row?.detail == CompanionText.recentDetail(project: "Assay development", at: now.addingTimeInterval(-720), now: now))
    }
}

// MARK: Recent: what a press does

@MainActor
private final class Pressed {
    var log: [String] = []

    var actions: CompanionActions {
        var actions = CompanionActions()
        actions.close = { [self] in log.append("close") }
        actions.open = { [self] in log.append("open \($0.title)") }
        actions.reference = { [self] in log.append("reference \($0.title)") }
        actions.copyLink = { [self] in log.append("copy \($0.title)") }
        actions.quickStart = { [self] in
            log.append("quick start \($0.text) in \($0.project?.name ?? "none"), plan \($0.planFirst)")
            return true
        }
        return actions
    }
}

@MainActor
struct CompanionRecentRoutingTests {
    @Test func aClickOpensTheSessionAndAnOptionClickOpensItAsAReference() {
        #expect(CompanionRecentRow.route(option: false) == .open)
        #expect(CompanionRecentRow.route(option: true) == .reference)
        let pressed = Pressed()
        let row = session(1, .finished, minutesAgo: 5)
        CompanionHomeView.press(row, option: false, actions: pressed.actions)
        CompanionHomeView.press(row, option: true, actions: pressed.actions)
        #expect(pressed.log == ["close", "open Session 1", "close", "reference Session 1"],
                "the popover steps aside, then the window or the reader")
    }

    @Test func copyLinkIsTheBenchAddressKeepWritesAndTheRouterOpens() {
        let row = session(1, .finished, minutesAgo: 5)
        let link = CompanionLinks.session(projectID: row.projectID, sessionID: row.id)
        #expect(link == KeepRules.deepLink(row))
        #expect(link == "bench://session?project=proj_assay&frame=00000000-0000-4000-8000-00000000c001")
    }
}

// MARK: The field: its project and its send

/// Takes the field's request and answers what it is told to; sends nothing.
@MainActor
private final class FakeSender: QuickStartSending {
    var outcomes: [QuickStartFlow.Outcome] = [.started(sessionID: "00000000-0000-4000-8000-0000000000d1",
                                                       sentence: "Started in Assay development.")]
    private(set) var requests: [QuickStartFlow.Request] = []
    var stages: [QuickStartFlow.Progress] = []
    var hold = false
    private var gate: CheckedContinuation<Void, Never>?

    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome {
        await perform(request, progress: { _ in })
    }

    func perform(_ request: QuickStartFlow.Request,
                 progress: @escaping @MainActor (QuickStartFlow.Progress) -> Void) async -> QuickStartFlow.Outcome {
        requests.append(request)
        for stage in stages { progress(stage) }
        if hold { await withCheckedContinuation { gate = $0 } }
        return outcomes[min(requests.count - 1, outcomes.count - 1)]
    }

    func release() { gate?.resume(); gate = nil }
}

@MainActor
private final class StartRig {
    let sender = FakeSender()
    var recents = [QuickStartProject(id: "proj_assay", name: "Assay development"), QuickStartProject(id: "proj_rna", name: "RNA-seq pilot"),
                   QuickStartProject(id: "proj_screen", name: "Screen analysis"), QuickStartProject(id: "proj_clone", name: "Cloning")]
    var everything: [QuickStartProject]? = [
        QuickStartProject(id: "proj_old", name: "Old pilot"), QuickStartProject(id: "proj_rna", name: "RNA-seq pilot"),
        QuickStartProject(id: "proj_assay", name: "Assay development"), QuickStartProject(id: "proj_figs", name: "Manuscript figures"),
    ]
    var planFirst = true
    var read = (recents: 0, everything: 0, plan: 0)

    lazy var start = CompanionStart(dependencies: CompanionStart.Dependencies(
        recentProjects: { [self] in read.recents += 1; return recents },
        allProjects: { [self] in read.everything += 1; return everything },
        planFirst: { [self] in read.plan += 1; return planFirst },
        sender: sender))

    func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    func waitForSend() async {
        for _ in 0..<200 where start.phase == .sending { await Task.yield() }
        await settle()
    }
}

@MainActor
struct CompanionStartTests {
    @Test func thePillStartsInTheLastUsedProjectAndItsMenuIsQuickStartsChipsThenTheRest() async {
        let rig = StartRig()
        rig.start.open()
        await rig.settle()
        #expect(rig.start.project?.name == "Assay development", "the project of the session active last, as Quick Start's first chip")
        #expect(rig.start.pillTitle == "Assay development")
        #expect(rig.start.menuProjects.map(\.name) == ["Assay development", "RNA-seq pilot", "Screen analysis"])
        #expect(rig.start.otherProjects.map(\.name) == ["Cloning", "Old pilot", "Manuscript figures"],
                "the other recent ones, then the database's in its order, each once")
        rig.start.choose(QuickStartProject(id: "proj_figs", name: "Manuscript figures"))
        #expect(rig.start.project?.name == "Manuscript figures")
        #expect(rig.start.menuProjects.map(\.name) == ["Manuscript figures", "Assay development", "RNA-seq pilot"],
                "the chosen one leads the menu when it isn't among the recent, as Quick Start's chips do")
    }

    @Test func withNoSessionToGoByThePillTakesTheDatabasesFirstOrAsksForOne() async {
        let rig = StartRig()
        rig.recents = []
        rig.start.open()
        #expect(rig.start.project == nil && rig.start.pillTitle == "Choose a project")
        await rig.settle()
        #expect(rig.start.project?.name == "Old pilot")
        let none = StartRig()
        none.recents = []
        none.everything = nil
        none.start.open()
        await none.settle()
        none.start.text = "Compare the plates"
        #expect(!none.start.start() && none.sender.requests.isEmpty, "no project, nothing sent")
    }

    @Test func returnStartsASessionInTheChosenProjectThroughQuickStartsFlow() async throws {
        let rig = StartRig()
        rig.planFirst = false
        rig.start.open()
        await rig.settle()
        rig.start.choose(id: "proj_screen")
        rig.start.text = "Rank the screen hits"
        #expect(rig.start.start())
        await rig.waitForSend()
        let request = try #require(rig.sender.requests.first)
        #expect(request.target == .newSession(project: "proj_screen") && request.projectName == "Screen analysis")
        #expect(request.text == "Rank the screen hits" && request.files.isEmpty)
        #expect(request.planFirst == false, "Quick Start's box, as it last had it")
        #expect(RemoteActionRequest.isUUIDv4(request.intentID))
        #expect(QuickStartFlow.check(request) == nil, "a request the flow takes as it takes Quick Start's")
    }

    /// The field's words go to Quick Start's flow whole, and the flow takes up to 32,000 of them (the Mac's
    /// limit), refusing one more in its own sentence.
    @Test func thirtyTwoThousandCharactersInTheFieldReachTheFlowWholeAndItTakesThem() async throws {
        let rig = StartRig()
        rig.start.open()
        await rig.settle()
        rig.start.choose(id: "proj_screen")
        let most = String(repeating: "界", count: 32_000)
        rig.start.text = most
        #expect(rig.start.start())
        await rig.waitForSend()
        let request = try #require(rig.sender.requests.first)
        #expect(request.text == most)
        #expect(QuickStartFlow.check(request) == nil)
        var over = request
        over.text = most + "界"
        #expect(QuickStartFlow.check(over) == QuickStartFlow.Sentence.tooLong)
    }

    @Test func nothingTypedSendsNothingAndASecondReturnWhileSendingSendsNothingTwice() async {
        let rig = StartRig()
        rig.start.open()
        rig.start.text = "   "
        #expect(!rig.start.start() && rig.sender.requests.isEmpty)
        rig.sender.hold = true
        rig.start.text = "QC the plate"
        #expect(rig.start.start())
        await rig.settle()
        #expect(!rig.start.start(), "one send at a time")
        rig.start.choose(id: "proj_rna")
        #expect(rig.start.project?.id == "proj_assay", "the pill holds still while it goes")
        #expect(rig.start.handOff() == nil, "and ⌘↩ waits too")
        rig.sender.release()
        await rig.waitForSend()
        #expect(rig.sender.requests.count == 1)
    }

    @Test func aRetryOfTheSameRequestKeepsItsIntentAndAnEditOrASuccessMakesANewOne() async {
        let rig = StartRig()
        rig.sender.outcomes = [.failed(sentence: QuickStartFlow.Sentence.startNotThere), .failed(sentence: "No."),
                               .started(sessionID: "00000000-0000-4000-8000-0000000000d1", sentence: "Started in Assay development."),
                               .started(sessionID: "00000000-0000-4000-8000-0000000000d2", sentence: "Started in Assay development.")]
        rig.start.open()
        rig.start.text = "QC the plate"
        rig.start.start()
        await rig.waitForSend()
        rig.start.start()
        await rig.waitForSend()
        rig.start.text = "QC the plate again"
        rig.start.start()
        await rig.waitForSend()
        rig.start.text = "QC the plate again"
        rig.start.start()
        await rig.waitForSend()
        let ids = rig.sender.requests.map(\.intentID)
        #expect(ids.count == 4)
        #expect(ids[0] == ids[1], "the same request, sent again: the daemon finds it, nothing starts twice")
        #expect(ids[2] != ids[1], "an edit is a new request")
        #expect(ids[3] != ids[2], "after a start, the same words are a new session")
    }

    @Test func theLineSaysWhatReturnDoesThenStartingThenWhatHappened() async {
        let rig = StartRig()
        rig.start.open()
        #expect(rig.start.line == nil, "nothing typed, no line")
        rig.start.text = "QC the plate"
        #expect(rig.start.line == .hint("↩ starts it with a plan first"))
        rig.sender.hold = true
        rig.start.start()
        #expect(rig.start.line == .sending("Starting…"))
        await rig.settle()
        rig.sender.release()
        await rig.waitForSend()
        #expect(rig.start.line == .started("Started in Assay development."))
        #expect(rig.start.started?.sessionID == "00000000-0000-4000-8000-0000000000d1" && rig.start.started?.projectID == "proj_assay")
        #expect(rig.start.text.isEmpty, "the words went: the field is clear")
        rig.start.text = "Next"
        #expect(rig.start.phase == .editing && rig.start.started == nil, "typing again puts the outcome away")
    }

    @Test func aStartCapsidCantConfirmSaysSoAndKeepsTheWords() async {
        let rig = StartRig()
        rig.sender.outcomes = [.failed(sentence: QuickStartFlow.Sentence.startNotThere)]
        rig.sender.stages = [.committed, .checking]
        rig.sender.hold = true
        rig.start.open()
        rig.start.text = "QC the plate"
        rig.start.start()
        await rig.settle()
        #expect(rig.start.line == .sending(RemoteDecide.Sentence.checking), "\"Not sure that went through. Checking…\"")
        rig.sender.release()
        await rig.waitForSend()
        #expect(rig.start.line == .failed(QuickStartFlow.Sentence.startNotThere))
        #expect(rig.start.text == "QC the plate")
        let unplanned = StartRig()
        unplanned.planFirst = false
        unplanned.start.open()
        unplanned.start.text = "Go"
        #expect(unplanned.start.line == .hint("↩ starts it without a plan first"))
    }

    @Test func thePlanSettingIsQuickStartsBoxAsItLastWasAndOnBeforeItHasOpened() {
        #expect(CompanionStart.planFirst(of: nil), "Quick Start hasn't opened: its box's own default, on")
        let model = QuickStartModel(dependencies: QuickStartModel.Dependencies(
            recipes: { [] }, recentProjects: { [] }, allProjects: { nil }, viewed: { nil }, sender: FakeSender(), close: {}))
        model.planFirst = false
        #expect(CompanionStart.planFirst(of: model) == false)
    }

    @Test func commandReturnHandsTheWordsTheProjectAndThePlanToQuickStart() async {
        #expect(CompanionStart.onReturn(command: true, hasText: true) == .quickStart)
        #expect(CompanionStart.onReturn(command: false, hasText: true) == .start)
        #expect(CompanionStart.onReturn(command: false, hasText: false) == .quickStart, "↩ on an empty field opens Quick Start, as it did")
        let rig = StartRig()
        rig.planFirst = false
        rig.start.open()
        await rig.settle()
        rig.start.choose(id: "proj_figs")
        rig.start.text = "Rebuild figure 2 with these files"
        let handOff = rig.start.handOff()
        #expect(handOff == CompanionStart.HandOff(text: "Rebuild figure 2 with these files",
                                                  project: QuickStartProject(id: "proj_figs", name: "Manuscript figures"),
                                                  planFirst: false))
        #expect(rig.sender.requests.isEmpty, "⌘↩ sends nothing")
    }

    @Test func quickStartOpensOnTheProjectAndPlanItIsHandedEvenOneNotYetListed() async {
        let sender = FakeSender()
        let model = QuickStartModel(dependencies: QuickStartModel.Dependencies(
            recipes: { [] }, recentProjects: { [QuickStartProject(id: "proj_assay", name: "Assay development")] },
            allProjects: { nil },
            viewed: { ViewedSession(id: "00000000-0000-4000-8000-0000000000d9", title: "Plate reader QC", projectID: "proj_assay",
                                    projectName: "Assay development") },
            sender: sender, close: {}, sleep: { _ in }))
        model.open(text: "Rebuild figure 2", project: QuickStartProject(id: "proj_figs", name: "Manuscript figures"), planFirst: false)
        for _ in 0..<40 { await Task.yield() }
        #expect(model.text == "Rebuild figure 2")
        #expect(model.project?.name == "Manuscript figures", "the handed project, not the viewed session's")
        #expect(model.chips.first?.name == "Manuscript figures")
        #expect(model.planFirst == false)
        model.cancel()
        model.open()
        #expect(model.project?.name == "Assay development" && model.planFirst, "a fresh opening starts clean")
    }

    @Test func aSendThatEndsWhileThePopoverIsClosedIsThereAtTheNextOpeningAndOnlyThen() async {
        let rig = StartRig()
        rig.sender.hold = true
        rig.start.open()
        rig.start.text = "QC the plate"
        rig.start.start()
        rig.start.close()
        await rig.settle()
        rig.sender.release()
        await rig.waitForSend()
        rig.start.open()
        #expect(rig.start.line == .started("Started in Assay development."), "the outcome waited")
        rig.start.close()
        rig.start.open()
        #expect(rig.start.line == nil && rig.start.text.isEmpty, "seen once, then a clean field")
    }

    @Test func theFieldReadsNothingUntilThePopoverOpens() async {
        let rig = StartRig()
        _ = rig.start
        await rig.settle()
        #expect(rig.read.recents == 0 && rig.read.everything == 0 && rig.read.plan == 0)
        rig.start.open()
        await rig.settle()
        #expect(rig.read.recents == 1 && rig.read.everything == 1 && rig.read.plan == 1, "one look each per opening")
        rig.start.close()
        await rig.settle()
        #expect(rig.read.recents == 1 && rig.read.everything == 1 && rig.read.plan == 1)
    }

    // MARK: ⌘↩ and Quick Start's own ledger and send

    /// A Quick Start panel on the same made-up projects, with its own sender.
    private func quickStart(_ rig: StartRig, sender: FakeSender = FakeSender()) -> QuickStartModel {
        QuickStartModel(dependencies: QuickStartModel.Dependencies(
            recipes: { [] }, recentProjects: { rig.recents }, allProjects: { nil }, viewed: { nil }, sender: sender, close: {},
            sleep: { _ in }))
    }

    @Test func aStartThatMayHaveGoneThroughKeepsItsIntentWhenMovedToQuickStartUnchanged() async throws {
        let rig = StartRig()
        rig.sender.outcomes = [.failed(sentence: QuickStartFlow.Sentence.startNotThere)]
        rig.start.open()
        await rig.settle()
        rig.start.text = "QC the plate"
        rig.start.start()
        await rig.waitForSend()
        let sent = try #require(rig.sender.requests.first)
        let handOff = try #require(rig.start.handOff())
        let panel = quickStart(rig)
        panel.open(text: handOff.text, project: handOff.project, planFirst: handOff.planFirst, retry: handOff.retry)
        await rig.settle()
        let retry = try #require(panel.request(toViewed: false))
        #expect(retry.signature == sent.signature, "the same request")
        #expect(retry.intentID == sent.intentID, "so the daemon finds the first one and nothing starts twice")
    }

    @Test func anEditAfterTheHandOffOrASuccessMakesANewIntent() async throws {
        let rig = StartRig()
        rig.sender.outcomes = [.failed(sentence: QuickStartFlow.Sentence.startNotThere)]
        rig.start.open()
        await rig.settle()
        rig.start.text = "QC the plate"
        rig.start.start()
        await rig.waitForSend()
        let sent = try #require(rig.sender.requests.first)
        let handOff = try #require(rig.start.handOff())
        let panel = quickStart(rig)
        panel.open(text: handOff.text, project: handOff.project, planFirst: handOff.planFirst, retry: handOff.retry)
        await rig.settle()
        panel.text = "QC the plate again"
        let edited = try #require(panel.request(toViewed: false))
        #expect(edited.intentID != sent.intentID, "an edit is a new request")
        // Edited back, it is the new request's again, not the first one's.
        panel.text = "QC the plate"
        #expect(panel.request(toViewed: false)?.intentID != sent.intentID)
        // A start that went through leaves nothing to carry.
        let done = StartRig()
        done.start.open()
        await done.settle()
        done.start.text = "QC the plate"
        done.start.start()
        await done.waitForSend()
        done.start.text = "QC the plate"
        let fresh = try #require(done.start.handOff())
        #expect(fresh.retry == nil, "a start that worked leaves nothing waiting on an answer")
        let other = quickStart(done)
        other.open(text: fresh.text, project: fresh.project, planFirst: fresh.planFirst, retry: fresh.retry)
        await done.settle()
        let again = try #require(other.request(toViewed: false))
        #expect(again.intentID != done.sender.requests[0].intentID, "the same words after a start are a new session")
    }

    @Test func theHandOffCarriesTheIntentOfARequestWaitingOnAnAnswerAndNothingElse() async throws {
        let rig = StartRig()
        rig.sender.outcomes = [.failed(sentence: QuickStartFlow.Sentence.startNotThere),
                               .started(sessionID: "00000000-0000-4000-8000-0000000000d1", sentence: "Started in Assay development.")]
        rig.start.open()
        await rig.settle()
        rig.start.text = "QC the plate"
        #expect(rig.start.handOff()?.retry == nil, "nothing has been sent")
        rig.start.start()
        await rig.waitForSend()
        let first = try #require(rig.sender.requests.first)
        let waiting = try #require(rig.start.handOff()?.retry)
        #expect(waiting.id == first.intentID && waiting.signature == first.signature)
        // Edited, the field still holds the first request's identity: the receiver compares signatures.
        rig.start.text = "QC the plate again"
        #expect(rig.start.handOff()?.retry == waiting)
        // Sent again and it worked: nothing is waiting any more.
        rig.start.text = "QC the plate"
        rig.start.start()
        await rig.waitForSend()
        #expect(rig.sender.requests[1].intentID == first.intentID, "the same request, retried")
        rig.start.text = "QC the plate"
        #expect(rig.start.handOff()?.retry == nil)
    }

    @Test func aLedgerAdoptsTheRequestAnotherCouldNotConfirm() throws {
        var menu = IntentLedger()
        #expect(menu.pending == nil)
        let id = menu.id(for: "new:proj_assay\u{1F}QC the plate\u{1F}plan")
        let waiting = try #require(menu.pending)
        #expect(waiting == IntentLedger.Pending(id: id, signature: "new:proj_assay\u{1F}QC the plate\u{1F}plan"))
        var quick = IntentLedger()
        quick.adopt(waiting)
        #expect(quick.id(for: waiting.signature) == id, "the same request keeps the id")
        #expect(quick.id(for: waiting.signature + "!") != id, "a changed request has a new one")
        menu.sent()
        #expect(menu.pending == nil)
    }

    /// ⌘↩ as the app does it: Quick Start takes the words if it can (`QuickStartController.receive` and `show`).
    private func hand(_ rig: StartRig, to panel: QuickStartModel) -> Bool {
        rig.start.handOver { handOff in
            guard panel.accepts(handOff) else { return false }
            panel.open(text: handOff.text.isEmpty ? nil : handOff.text, project: handOff.project, planFirst: handOff.planFirst,
                       retry: handOff.retry)
            return true
        }
    }

    /// A Quick Start panel with a request of its own on its way.
    private func sendingPanel(_ rig: StartRig) async -> (panel: QuickStartModel, sender: FakeSender) {
        let sender = FakeSender()
        sender.hold = true
        let panel = quickStart(rig, sender: sender)
        panel.open(text: "First request")
        await rig.settle()
        panel.submit(toViewed: false)
        await rig.settle()
        return (panel, sender)
    }

    @Test func wordsQuickStartCantTakeWhileItSendsStayInTheFieldAndSayWhy() async throws {
        let rig = StartRig()
        rig.start.open()
        await rig.settle()
        let (panel, busy) = await sendingPanel(rig)
        #expect(panel.phase == .sending)
        rig.start.text = "Second request"
        #expect(rig.start.line == .hint("↩ starts it with a plan first"))
        // ⌘↩ while Quick Start sends: not taken, nothing leaves the field, and the field says so.
        #expect(!hand(rig, to: panel))
        #expect(rig.start.text == "Second request")
        #expect(rig.start.line == .kept("Quick Start is sending; your words are kept here."))
        #expect(panel.text == "First request" && busy.requests.count == 1, "Quick Start keeps the request on its way")
        // The popover goes before it is read, and comes back: the words are there once, with the line.
        rig.start.close()
        rig.start.open()
        await rig.settle()
        #expect(rig.start.text == "Second request" && rig.start.line == .kept("Quick Start is sending; your words are kept here."))
        // Any later opening is clean, as it always was.
        rig.start.close()
        rig.start.open()
        #expect(rig.start.text.isEmpty && rig.start.line == nil)
        busy.release()
    }

    @Test func theLineGoesWhenTheWordsChangeAndTheWordsGoWhenQuickStartTakesThem() async throws {
        let rig = StartRig()
        rig.start.open()
        await rig.settle()
        let (panel, busy) = await sendingPanel(rig)
        rig.start.text = "Second request"
        #expect(!hand(rig, to: panel))
        // Typing on takes the line away.
        rig.start.text = "Second request, longer"
        #expect(rig.start.line == .hint("↩ starts it with a plan first"))
        rig.start.text = "Second request"
        #expect(!hand(rig, to: panel))
        // Quick Start finishes its own; the same press now hands them over, and only now does the field clear.
        busy.release()
        for _ in 0..<200 where panel.phase == .sending { await Task.yield() }
        await rig.settle()
        #expect(hand(rig, to: panel))
        #expect(rig.start.text.isEmpty && rig.start.line == nil)
        #expect(panel.text == "Second request")
        #expect(busy.requests.count == 1, "nothing was sent by the hand-over")
    }

    @Test func aHandOverWithNoWordsLosesNothingAndIsTakenEvenWhileQuickStartSends() async throws {
        let rig = StartRig()
        rig.start.open()
        await rig.settle()
        let (panel, busy) = await sendingPanel(rig)
        rig.start.text = "   "
        #expect(hand(rig, to: panel), "↩ on an empty field only opens Quick Start")
        #expect(rig.start.line == nil)
        #expect(panel.text == "First request", "its own request is still what it holds")
        #expect(panel.accepts(CompanionStart.HandOff(text: "", project: nil, planFirst: true)))
        #expect(!panel.accepts(CompanionStart.HandOff(text: "Words", project: nil, planFirst: true)))
        busy.release()
    }

    @Test func anAcceptedHandOverTakesTheRetryIdentityOutOfTheField() async throws {
        let rig = StartRig()
        rig.sender.outcomes = [.failed(sentence: QuickStartFlow.Sentence.startNotThere)]
        rig.start.open()
        await rig.settle()
        rig.start.text = "QC the plate"
        rig.start.start()
        await rig.waitForSend()
        let sent = try #require(rig.sender.requests.first)
        let panel = quickStart(rig)
        #expect(hand(rig, to: panel))
        #expect(rig.start.text.isEmpty && rig.start.handOff()?.retry == nil, "the id is Quick Start's now")
        #expect(panel.request(toViewed: false)?.intentID == sent.intentID)
    }

}

// MARK: The popover reads nothing while closed

@MainActor
struct CompanionClosedReadsTests {
    @Test func aClosedPopoverReadsNeitherRecentNorTheFieldsProjects() async {
        let lab = LabModel()
        final class Count { var recent = 0, recents = 0, everything = 0, plan = 0 }
        let count = Count()
        let plans = PlanApprover(model: lab, dependencies: PlanApprover.Dependencies(
            isEnabled: { false }, isReady: { false }, get: { _ in throw WebAPIError.notAllowed },
            post: { _ in throw WebAPIError.notAllowed }, approvedPause: .milliseconds(10)))
        let questions = QuestionReplier(model: lab, dependencies: QuestionReplier.Dependencies(
            isEnabled: { false }, isReady: { false }, read: { _ in nil }, respond: { _, _, _ in .unavailable }))
        let results = CompanionResults(dependencies: .made(entries: [], pictures: [:], now: now))
        let quiet = [session(1, .finished, minutesAgo: 5)]
        let model = CompanionModel(sources: CompanionModel.Sources(
            lab: lab, cards: CardActions(model: lab, plans: plans, questions: questions, showReply: { _, _ in }), results: results,
            usage: { nil }, since: { nil }, pause: { _ in nil }, progress: { _ in nil }, prepare: { _ in },
            quickStartKey: { .none }, now: { now },
            recent: { count.recent += 1; return quiet },
            start: CompanionStart.Dependencies(
                recentProjects: { count.recents += 1; return [QuickStartProject(id: "proj_assay", name: "Assay development")] },
                allProjects: { count.everything += 1; return nil },
                planFirst: { count.plan += 1; return true }, sender: FakeSender()),
            changes: { [lab.$working.map { _ in () }.eraseToAnyPublisher(), lab.$latest.map { _ in () }.eraseToAnyPublisher()] }))
        lab.showDemo(working: [session(2, .running, minutesAgo: 1)], cards: [])
        model.refresh()
        for _ in 0..<40 { await Task.yield() }
        #expect(count.recent == 0 && count.recents == 0 && count.everything == 0 && count.plan == 0,
                "nothing is read while the popover is closed")
        #expect(model.sections.recent.isEmpty)
        model.open()
        for _ in 0..<40 { await Task.yield() }
        #expect(count.recent >= 1 && count.recents == 1 && count.everything == 1 && count.plan == 1)
        #expect(model.sections.recent.map(\.session.title) == ["Session 1"])
        #expect(model.start.project?.name == "Assay development")
        model.close()
        let seen = (count.recent, count.recents, count.everything, count.plan)
        lab.showDemo(working: [], cards: [])
        model.refresh()
        for _ in 0..<40 { await Task.yield() }
        #expect(count.recent == seen.0 && count.recents == seen.1 && count.everything == seen.2 && count.plan == seen.3,
                "and nothing after it closes")
    }
}
