// CompanionSectionsTests.swift — what the home popover shows, from made-up
// sessions, offers, files and a limit: the titles and counts (one, many, none),
// the order of the blocks, what each row's buttons are, the words under a row,
// the caps with their "N more", the Results tiles, the Since You Left line, the
// 5-hour line, and the menu bar item's face. Pure: no view, no model, no window.
import Foundation
import Testing
@testable import Bench

private let now = Date(timeIntervalSince1970: 1_792_000_000)

private func session(_ id: String, _ title: String, _ project: String, _ state: SessionState,
                     waited: TimeInterval = 0, reason: WaitingReason? = nil) -> SessionStatus {
    SessionStatus(id: id, projectID: "p", projectName: project, title: title, state: state,
                  updatedAt: now.addingTimeInterval(-waited), startedAt: now.addingTimeInterval(-600), waitingReason: reason)
}

private let question = session("00000000-0000-4000-8000-000000000001", "Differential expression, KO vs WT", "RNA-seq pilot",
                               .needsInput, waited: 12 * 60, reason: .question)
private let plan = session("00000000-0000-4000-8000-000000000002", "Lipid peroxidation panel", "Oxidative stress",
                           .needsInput, waited: 3 * 60, reason: .plan)
private let stopped = session("00000000-0000-4000-8000-000000000003", "Figure 2 rebuild", "Manuscript figures", .error, waited: 60)
private let plate = session("00000000-0000-4000-8000-000000000004", "Plate reader QC", "Assay development", .running)
private let screen = session("00000000-0000-4000-8000-000000000005", "CRISPRi screen hits", "Screen analysis", .running)

private let ask = QuestionAsk(toolID: "t1", items: [
    .init(question: "Which buffer?", header: "Buffer", multi: false, options: [.init(label: "HEPES", detail: nil)]),
])
private let preview = PlanPreview(summary: "Lipid peroxidation panel", steps: 6, confidence: "high", versionID: "v1", artifactID: nil)

private func offerForQuestion(_ state: QuestionCardState? = .ready(ask), reply: ReplyPhase? = nil) -> CardOffer {
    CardOffer.of(reason: .question, plan: nil, question: state, reply: reply, permission: nil)
}

private func offerForPlan(_ state: PlanCardState?) -> CardOffer {
    CardOffer.of(reason: .plan, plan: state, question: nil, reply: nil, permission: nil)
}

private func entry(_ name: String, _ mime: String, version: String? = nil, at: Date? = now) -> ArtifactEntry {
    ArtifactEntry(version: version ?? "v-\(name)", artifact: nil, name: name, mime: mime, size: 1_000, at: at)
}

@MainActor
private func input(asks: [SessionStatus] = [], failed: [SessionStatus] = [], working: [SessionStatus] = [],
                   offers: [String: CardOffer] = [:], queued: Set<String>? = nil, steps: [String: Int] = [:],
                   pauses: [String: UsagePause] = [:], progress: [String: PlanProgress] = [:],
                   results: [ArtifactEntry] = [], partial: Bool = false, since: SinceYouLeftSummary? = nil,
                   usage: PlanLimit? = nil, problem: ScienceError? = nil,
                   showsAllNeeds: Bool = false, showsAllWorking: Bool = false) -> CompanionSections.Input {
    CompanionSections.Input(
        needs: NeedsYou(waiting: asks, snoozed: [], failed: failed), working: working,
        offer: { offers[$0.id] ?? CardOffer(lead: .button(.open)) },
        canLater: { queued?.contains($0.id) ?? true },
        planSteps: { steps[$0.id] }, pause: { pauses[$0.id] }, progress: { progress[$0.id] },
        results: results, resultsPartial: partial, since: since, usage: usage, problem: problem, now: now,
        showsAllNeeds: showsAllNeeds, showsAllWorking: showsAllWorking)
}

// MARK: Titles, counts and the order of the blocks

@MainActor
struct CompanionTitlesTests {
    @Test func theBoardsCountsAreInTheTitles() {
        let files = ["volcano.png", "heatmap.pdf", "z_prime.png", "hits_ranked.csv", "a.md", "b.md", "c.md"]
            .map { entry($0, "application/octet-stream") }
        let sections = CompanionSections.make(input(asks: [question, plan], working: [plate, screen], results: files))
        #expect(sections.needsTitle == "Needs you · 2")
        #expect(sections.workingTitle == "Working · 2")
        #expect(sections.results?.title == "Results today · 7")
    }

    @Test func oneIsOneAndNoneIsNoTitle() {
        let one = CompanionSections.make(input(asks: [question], working: [plate], results: [entry("a.png", "image/png")]))
        #expect(one.needsTitle == "Needs you · 1" && one.workingTitle == "Working · 1" && one.results?.title == "Results today · 1")
        let none = CompanionSections.make(input())
        #expect(none.needsTitle == nil && none.workingTitle == nil && none.results == nil && none.since == nil && none.usage == nil)
    }

    @Test func aStoppedSessionCountsWithWhatAsksAndThereIsNoOtherWayToBePutOff() {
        let sections = CompanionSections.make(input(asks: [question], failed: [stopped]))
        #expect(sections.needsTotal == 2 && sections.needsTitle == "Needs you · 2")
        #expect(sections.needs.map(\.kind) == [.question, .stopped], "what asks first, then what stopped")
    }

    @Test func theLongestWaitIsOnTop() {
        let sections = CompanionSections.make(input(asks: [plan, question]))
        #expect(sections.needs.map(\.session.id) == [question.id, plan.id])
    }

    @Test func aHeldSetOfSessionsSaysPaused() {
        let pause = UsagePause(limit: .session, until: now.addingTimeInterval(3600))
        let all = CompanionSections.make(input(working: [plate, screen], pauses: [plate.id: pause, screen.id: pause]))
        #expect(all.workingTitle == "Paused · 2" && all.allPaused)
        let some = CompanionSections.make(input(working: [plate, screen], pauses: [plate.id: pause]))
        #expect(some.workingTitle == "Working · 2" && !some.allPaused)
        #expect(some.working[0].pause?.hasPrefix("Resumes") == true && some.working[1].pause == nil, "only a held row loses its clock")
    }

    @Test func theBlocksComeInTheBoardsOrder() {
        let files = [entry("volcano.png", "image/png")]
        let since = SinceYouLeftSummary.make(since: now.addingTimeInterval(-3600), back: now, events: [
            LabEvent(.finished, session: plate, at: now.addingTimeInterval(-1800)),
        ], waiting: [], working: [])
        let board = CompanionSections.make(input(asks: [question, plan], working: [plate, screen], results: files))
        #expect(board.blocks == [.needs, .working, .results])
        let returned = CompanionSections.make(input(asks: [question], working: [plate], results: files, since: since))
        #expect(returned.blocks == [.needs, .working, .results, .since], "Since you left follows Results today")
        #expect(CompanionSections.make(input()).blocks == [.quiet])
        #expect(CompanionSections.make(input(results: files)).blocks == [.quiet, .results])
        #expect(CompanionSections.make(input(working: [plate])).blocks == [.working])
    }

    @Test func nothingToDoSaysSoInOneLine() {
        let quiet = CompanionSections.make(input())
        #expect(quiet.isQuiet && quiet == CompanionSections.make(input()))
        #expect(CompanionText.nothingToDo == "Nothing needs you and nothing is working.")
        #expect(!CompanionSections.make(input(working: [plate])).isQuiet)
    }

    @Test func aReadThatFailsSaysSoAtTheTop() {
        let sections = CompanionSections.make(input(problem: .daemonNotRunning))
        #expect(sections.problem == "Not updating: Claude Science isn't running")
        #expect(CompanionSections.make(input()).problem == nil)
    }

    @Test func aLongListShowsWhatFitsAndSaysHowManyMore() {
        let many = (1...5).map { session("00000000-0000-4000-8000-00000000010\($0)", "Question \($0)", "Project", .needsInput,
                                         waited: Double($0) * 60, reason: .question) }
        let capped = CompanionSections.make(input(asks: many, working: many.map { _ in plate }))
        #expect(capped.needs.count == 3 && capped.needsHidden == 2 && capped.needsTotal == 5)
        #expect(capped.working.count == 3 && capped.workingHidden == 2)
        let shown = CompanionSections.make(input(asks: many, showsAllNeeds: true))
        #expect(shown.needs.count == 5 && shown.needsHidden == 0)
        #expect(CompanionText.more(2) == "2 more")
    }
}

// MARK: What a row says and offers

@MainActor
struct CompanionRowsTests {
    private func pills(_ offer: CardOffer, canLater: Bool = true) -> [String] {
        CompanionNeedRow.pills(for: offer, canLater: canLater).map(\.title)
    }

    private func prominent(_ offer: CardOffer) -> [String] {
        CompanionNeedRow.pills(for: offer, canLater: true).filter(\.prominent).map(\.title)
    }

    @Test func aQuestionOffersReplyOpenAndLater() {
        let offer = offerForQuestion()
        #expect(pills(offer) == ["Reply", "Open", "Later"])
        #expect(prominent(offer) == ["Reply"], "the lead is the one in clay")
    }

    @Test func aPlanOffersApproveAndRequestChanges() {
        let offer = offerForPlan(.ready(preview))
        #expect(pills(offer) == ["Approve", "Request changes…"])
        #expect(prominent(offer) == ["Approve"])
        #expect(pills(offerForPlan(.problem("The plan changed.", preview))) == ["Open", "Request changes…"])
    }

    @Test func aPlanNotReadYetOffersOpenAndLater() {
        for state in [nil, .loading, .unavailable] as [PlanCardState?] {
            #expect(pills(offerForPlan(state)) == ["Open", "Later"])
        }
    }

    @Test func aRequestOffersItsLeadDenyAndLaterAndTheTitleOpensTheSession() {
        let tool = PermissionRequest(requestID: "r1", toolID: "t1", mode: "parked", kind: "mcp_tool", frame: "f1",
                                     tool: "search_made_up_papers", server: "Made-up Library", source: "directory", readOnly: true)
        let offer = CardOffer.of(reason: .tool, plan: nil, question: .permission(tool), reply: nil, permission: nil)
        #expect(pills(offer) == ["Allow Once", "Deny", "Later"])
        let code = PermissionRequest(requestID: "r2", toolID: "t2", kind: "local_exec", frame: "f2", tool: "python", code: "print(1)")
        let review = CardOffer.of(reason: .other, plan: nil, question: .permission(code), reply: nil, permission: nil)
        #expect(pills(review).first == "Review")
    }

    @Test func aRowWhoseCardIsNotUpHasNoLater() {
        #expect(pills(offerForQuestion(), canLater: false) == ["Reply", "Open"])
        #expect(pills(offerForPlan(nil), canLater: false) == ["Open"])
    }

    @Test func aSendOnItsWayAndAnAnswerSentTakeTheButtonsPlace() {
        let sending = offerForQuestion(.ready(ask), reply: .sending)
        #expect(sending.lead == .sending("Sending the answer") && pills(sending) == ["Open", "Later"])
        let approved = offerForPlan(.approved(preview))
        #expect(approved.lead == .done("Approved") && pills(approved).isEmpty)
        let sent = offerForQuestion(.ready(ask), reply: .sent("Sent"))
        #expect(sent.lead == .done("Sent") && pills(sent).isEmpty)
    }

    @Test func eachRowKnowsItsKindAndItsWords() {
        let sections = CompanionSections.make(input(
            asks: [question, plan], failed: [stopped],
            offers: [question.id: offerForQuestion(), plan.id: offerForPlan(.ready(preview))], steps: [plan.id: 6]))
        let rows = Dictionary(uniqueKeysWithValues: sections.needs.map { ($0.session.id, $0) })
        #expect(rows[question.id]?.kind == .question && rows[question.id]?.caption == "Asked you a question")
        #expect(rows[plan.id]?.kind == .plan && rows[plan.id]?.caption == "Plan ready for your review")
        #expect(rows[plan.id]?.steps == 6)
        #expect(rows[stopped.id]?.kind == .stopped && rows[stopped.id]?.caption == "Stopped with an error")
        #expect(rows[stopped.id]?.pills.map(\.title) == ["Open"])
        #expect(CompanionNeedRow.kind(of: .web) == .request && CompanionNeedRow.kind(of: .license) == .request)
        #expect(CompanionNeedRow.kind(of: .other) == .question && CompanionNeedRow.kind(of: nil) == .question)
    }

    @Test func aWaitWithNoKnownReasonIsARequestOnceItsCardHasReadOne() {
        let code = PermissionRequest(requestID: "r2", toolID: "t2", kind: "local_exec", frame: "f2", tool: "python", code: "print(1)")
        let review = CardOffer.of(reason: .other, plan: nil, question: .permission(code), reply: nil, permission: nil)
        #expect(CompanionNeedRow.kind(of: .other, offer: review) == .request)
        let site = PermissionRequest(requestID: "r3", toolID: "t3", mode: "parked", kind: "network", frame: "f3", target: "genomes.example.org")
        let deny = CardOffer.of(reason: .other, plan: nil, question: .permission(site), reply: nil, permission: nil)
        #expect(CompanionNeedRow.kind(of: .other, offer: deny) == .request, "a plain deny is a request's answer too")
        #expect(CompanionNeedRow.kind(of: .other, offer: offerForQuestion()) == .question)
        #expect(CompanionNeedRow.kind(of: .other, offer: CardOffer(lead: .button(.open))) == .question, "not read: as a question")
        #expect(CompanionNeedRow.kind(of: .plan, offer: review) == .plan, "a known reason is not second-guessed")
    }

    @Test func aProblemWithASendIsKeptForUnderTheButtons() {
        let offer = offerForPlan(.problem("The plan changed.", preview))
        let sections = CompanionSections.make(input(asks: [plan], offers: [plan.id: offer]))
        #expect(sections.needs.first?.problem == "The plan changed.")
    }

    @Test func theLineUnderATitleIsTheProjectTheStepsAndTheWait() {
        let base = now.addingTimeInterval(-12 * 60)
        #expect(CompanionText.needDetail(project: "RNA-seq pilot", steps: nil, waitingSince: base, now: now) == "RNA-seq pilot · 12 min")
        #expect(CompanionText.needDetail(project: "Oxidative stress", steps: 6, waitingSince: now.addingTimeInterval(-180), now: now)
                == "Oxidative stress · 6 steps · 3 min")
        #expect(CompanionText.needDetail(project: "P", steps: 1, waitingSince: now.addingTimeInterval(-3900), now: now) == "P · 1 step · 1 h 5 min")
        #expect(CompanionText.needDetail(project: "P", steps: nil, waitingSince: now, now: now) == "P · 1 min", "never 0 min")
        #expect(CompanionText.needDetail(project: "P", steps: nil, waitingSince: now.addingTimeInterval(60), now: now) == "P · 1 min",
                "a clock that moved back is not a negative wait")
    }

    @Test func aWorkingRowNamesTheProjectAndTheStepWhenThePanelHasRead() {
        #expect(CompanionText.workingDetail(project: "Assay development", progress: nil) == "Assay development")
        let progress = PlanProgress(step: 4, total: 6, title: "Check against published screens")
        #expect(CompanionText.workingDetail(project: "Assay development", progress: progress) == "Assay development · Step 4 of 6")
        let sections = CompanionSections.make(input(working: [plate], progress: [plate.id: progress]))
        #expect(sections.working.first?.detail == "Assay development · Step 4 of 6")
    }
}

// MARK: Results, Since You Left and the limit

@MainActor
struct CompanionFootTests {
    @Test func theTilesAreFourWithPicturesFirst() {
        let files = [entry("hits_ranked.csv", "text/csv"), entry("volcano.png", "image/png"), entry("heatmap.pdf", "application/pdf"),
                     entry("z_prime.png", "image/png"), entry("notes.md", "text/markdown"), entry("plates.xlsx", "application/vnd.ms-excel")]
        let section = CompanionSections.make(input(results: files)).results
        #expect(section?.count == 6)
        #expect(section?.tiles.map(\.name) == ["volcano.png", "z_prime.png", "hits_ranked.csv", "heatmap.pdf"])
        #expect(section?.tiles.map(\.isPicture) == [true, true, false, false])
        #expect(section?.tiles.map(\.label).suffix(2) == ["CSV", "PDF"], "a file that has no picture is a tile naming its kind")
    }

    @Test func aCountThatIsNotWholeSaysSo() {
        let files = [entry("a.png", "image/png"), entry("b.png", "image/png")]
        #expect(CompanionSections.make(input(results: files, partial: true)).results?.title == "Results today · 2+")
        #expect(CompanionSections.make(input(results: files, partial: false)).results?.title == "Results today · 2")
        #expect(CompanionSections.make(input(results: [], partial: false)).results == nil, "no session made files today: no section")
        let unknown = CompanionSections.make(input(results: [], partial: true)).results
        #expect(unknown?.title == "Results today" && unknown?.tiles.isEmpty == true,
                "sessions made files today and none is in memory: the title and Show all, which opens Results")
        #expect(CompanionSections.make(input(results: [], partial: true)).blocks == [.quiet, .results])
    }

    @Test func sinceYouLeftIsItsTitleAndHeadline() {
        let away = SinceYouLeftDemo.made(now: now)
        let summary = SinceYouLeftSummary.make(since: away.since, back: away.back, events: away.events, waiting: [away.ask], working: [])
        let section = CompanionSections.make(input(since: summary)).since
        #expect(section?.title == "Since you left · 2 h 14 min")
        #expect(section?.headline == "3 finished, 1 stopped, 1 needs you")
        #expect(CompanionSections.make(input(since: nil)).since == nil)
    }

    @Test func theLimitLineSaysWhatIsLeftAndWhenItStartsOver() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US")
        let resets = Date(timeIntervalSince1970: 1_792_000_000 + 87 * 60)
        let limit = PlanLimit(kind: .session, usedPercent: 46, resetsAt: resets)
        let value = CompanionText.usageValue(limit, now: now, calendar: calendar, locale: locale)
        #expect(value.hasPrefix("54% left · resets ") && (value.hasSuffix("AM") || value.hasSuffix("PM")))
        #expect(CompanionText.usageValue(PlanLimit(kind: .session, usedPercent: 46, resetsAt: nil), now: now) == "54% left")
        #expect(CompanionText.usageValue(PlanLimit(kind: .session, usedPercent: 100, resetsAt: nil, reached: true), now: now) == "All used")
        let over = PlanLimit(kind: .session, usedPercent: 46, resetsAt: now.addingTimeInterval(-5))
        #expect(CompanionText.usageValue(over, now: now) == "54% left · resetting now")
    }

    @Test func theBarFillsWhatIsUsedWhileTheWordsSayWhatIsLeft() {
        let line = CompanionSections.make(input(usage: PlanLimit(kind: .session, usedPercent: 46, resetsAt: nil))).usage
        #expect(line?.label == "5-hour limit" && line?.used == 0.46 && line?.isLow == false)
        let low = CompanionSections.make(input(usage: PlanLimit(kind: .session, usedPercent: 85, resetsAt: nil))).usage
        #expect(low?.isLow == true && low?.value == "15% left", "under a fifth left turns the words clay")
        #expect(CompanionSections.make(input()).usage == nil, "no reading, no line")
    }

    @Test func theFootButtonSaysCapsidUntilCapsidsWindowCanBeOff() {
        #expect(CompanionText.openButton() == "Open Capsid")
        #expect(CompanionText.openButton(capsidWindowOn: true) == "Open Capsid")
        #expect(CompanionText.openButton(capsidWindowOn: false) == "Open Claude Science")
    }

    @Test func theFieldShowsQuickStartsKeyAndNothingWhenItHasNone() {
        #expect(CompanionText.quickStartKey(.controlOptionCommandSpace) == "⌃⌥⌘Space")
        #expect(CompanionText.quickStartKey(.controlOptionSpace) == "⌃⌥Space")
        #expect(CompanionText.quickStartKey(.none) == nil)
        #expect(CompanionText.quickStartPlaceholder == "Start a session…")
    }
}

// MARK: The menu bar item

@MainActor
struct MenuBarFaceTests {
    @Test func theItemIsThereOnlyWhenItsSwitchIsOn() {
        let off = MenuBarFace.of(homeOn: false, specimenOn: true, working: 2, allPaused: false, needs: 3)
        #expect(off == .hidden && !off.visible)
        #expect(MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 0).visible)
    }

    @Test func itIsTheQuietGlyphWhateverWorksUnlessTheOlderSwitchIsOn() {
        let quiet = MenuBarFace.of(homeOn: true, specimenOn: false, working: 3, allPaused: false, needs: 0)
        #expect(quiet.mark == .capsid && quiet.countText == nil)
        let idle = MenuBarFace.of(homeOn: true, specimenOn: true, working: 0, allPaused: false, needs: 0)
        #expect(idle.mark == .capsid, "the specimen plays only while a session works")
    }

    @Test func theSpecimenTakesTheGlyphsPlaceWhileASessionWorksAndTheOlderSwitchIsOn() {
        #expect(MenuBarFace.of(homeOn: true, specimenOn: true, working: 1, allPaused: false, needs: 0).mark == .specimen)
        #expect(MenuBarFace.of(homeOn: true, specimenOn: true, working: 2, allPaused: true, needs: 0).mark == .paused,
                "every working session held by a used-up limit is a still mark")
    }

    @Test func theCountIsBesideEitherAndIsWhatNeedsYou() {
        let glyph = MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 2)
        #expect(glyph.countText == "2" && glyph.mark == .capsid)
        let specimen = MenuBarFace.of(homeOn: true, specimenOn: true, working: 1, allPaused: false, needs: 2)
        #expect(specimen.countText == "2" && specimen.mark == .specimen)
        #expect(MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 140).countText == "99+")
        #expect(MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: -1).needs == 0)
    }

    @Test func theCountIsWhatAsksAndWhatStoppedNotWhatIsPutOff() {
        let putOff = SnoozedReminder(session: question, due: now.addingTimeInterval(300))
        let needs = NeedsYou(waiting: [question, plan], snoozed: [putOff], failed: [stopped])
        #expect(needs.count == 3 && CompanionSections.needsCount(needs) == 2, "the put-off one is not asking now")
        #expect(CompanionSections.needsCount(NeedsYou(waiting: [], snoozed: [], failed: [])) == 0)
    }

    @Test func theItemReadsTheLabsNeedsAndWork() {
        let lab = LabModel()
        lab.showDemo(working: [plate], cards: [.needsInput(question), .needsInput(plan), .failed(stopped)])
        let face = MenuBarHome.face(model: lab, pauses: UsagePauseModel(), homeOn: true)
        #expect(face.visible && face.needs == 3 && face.mark == .capsid, "two ask and one stopped; the older switch is off here")
        #expect(MenuBarHome.face(model: lab, pauses: UsagePauseModel(), homeOn: false) == .hidden)
        lab.showDemo(working: [], cards: [])
        #expect(MenuBarHome.face(model: lab, pauses: UsagePauseModel(), homeOn: true).needs == 0)
    }

    @Test func itIsNamedForVoiceOverWithTheCountInWords() {
        #expect(MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 0).accessibilityLabel == "Capsid")
        #expect(MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 1).accessibilityLabel == "Capsid, 1 needs you")
        #expect(MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 2).accessibilityLabel == "Capsid, 2 need you")
    }

    @Test func theItemMakesRoomForTheCount() {
        let none = MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 0).width
        let one = MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 2).width
        let many = MenuBarFace.of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 14).width
        #expect(none == 24 && one > none && many > one)
    }
}
