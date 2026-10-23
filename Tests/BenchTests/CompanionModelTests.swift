// CompanionModelTests.swift — the home popover's model, on a made-up lab and
// fakes: it looks at nothing while the popover is closed, looks and watches
// while it is open, and stops when it closes. Plus the setting that decides
// whether the menu bar item is there, and where the popover goes.
import AppKit
import Combine
import Foundation
import Testing
@testable import Bench

/// Counts what the model asks for.
@MainActor
private final class Asked {
    var usage = 0
    var since = 0
    var pause = 0
    var progress = 0
    var prepared: [String] = []
    var total: Int { usage + since + pause + progress }
}

@MainActor
private struct Rig {
    let lab = LabModel()
    let asked = Asked()
    let results: CompanionResults
    let model: CompanionModel
    private(set) var resultsAsked = ResultsAsked()

    final class ResultsAsked {
        var held = 0
        var candidates = 0
    }

    init() {
        let asked = asked, probe = resultsAsked
        let results = CompanionResults(dependencies: CompanionResults.Dependencies(
            candidates: { probe.candidates += 1; return [] }, held: { probe.held += 1; return [:] }, picture: { _ in nil },
            reader: .init(read: { _ in .unreadable }, isReady: { false }), gate: { _ in .cancelled }, readsLists: false))
        self.results = results
        let plans = PlanApprover(model: lab, dependencies: PlanApprover.Dependencies(
            isEnabled: { false }, isReady: { false }, get: { _ in throw WebAPIError.notAllowed },
            post: { _ in throw WebAPIError.notAllowed }, approvedPause: .milliseconds(10)))
        let questions = QuestionReplier(model: lab, dependencies: QuestionReplier.Dependencies(
            isEnabled: { false }, isReady: { false }, read: { _ in nil }, respond: { _, _ in .unavailable }))
        let cards = CardActions(model: lab, plans: plans, questions: questions, showReply: { _, _ in })
        let lab = lab
        model = CompanionModel(sources: CompanionModel.Sources(
            lab: lab, cards: cards, results: results,
            usage: { asked.usage += 1; return PlanLimit(kind: .session, usedPercent: 46, resetsAt: nil) },
            since: { asked.since += 1; return nil },
            pause: { _ in asked.pause += 1; return nil },
            progress: { _ in asked.progress += 1; return nil },
            prepare: { asked.prepared.append($0.id) },
            quickStartKey: { .controlOptionCommandSpace },
            changes: { [lab.$working.map { _ in () }.eraseToAnyPublisher(), lab.$cards.map { _ in () }.eraseToAnyPublisher()] }))
    }

    static func session(_ n: Int, _ state: SessionState, reason: WaitingReason? = nil) -> SessionStatus {
        SessionStatus(id: "00000000-0000-4000-8000-00000000a\(String(format: "%03d", n))", projectID: "p", projectName: "Example project",
                      title: "Session \(n)", state: state, updatedAt: Date().addingTimeInterval(-Double(n) * 60),
                      startedAt: Date().addingTimeInterval(-300), waitingReason: reason)
    }

    /// Lets a change land: the model looks on the next turn.
    static func settle() async {
        try? await Task.sleep(for: .milliseconds(60))
    }
}

@MainActor
struct CompanionModelTests {
    @Test func aClosedPopoverLooksAtNothing() async {
        let rig = Rig()
        rig.lab.showDemo(working: [Rig.session(1, .running)], cards: [.needsInput(Rig.session(2, .needsInput, reason: .question))])
        rig.model.refresh()
        await Rig.settle()
        #expect(rig.asked.total == 0, "nothing is read while the popover is closed, whatever the lab does")
        #expect(rig.model.sections == .empty && !rig.model.isOpen)
        #expect(rig.asked.prepared.isEmpty)
        #expect(rig.results.isOpen == false && rig.resultsAsked.held == 0 && rig.resultsAsked.candidates == 0)
    }

    @Test func openingLooksOnceAndFillsTheSections() async {
        let rig = Rig()
        let ask = Rig.session(2, .needsInput, reason: .question)
        rig.lab.showDemo(working: [Rig.session(1, .running)], cards: [.needsInput(ask)])
        rig.model.open()
        #expect(rig.model.isOpen)
        #expect(rig.model.sections.needsTotal == 1 && rig.model.sections.workingTotal == 1)
        #expect(rig.model.sections.usage?.value == "54% left")
        #expect(rig.model.quickStartKey == "⌃⌥⌘Space")
        #expect(rig.asked.usage >= 1 && rig.asked.since >= 1)
        #expect(rig.results.isOpen, "Results today starts with the popover")
    }

    @Test func openingAsksTheCardsOwnReadsForTheRowsShownOnly() async {
        let rig = Rig()
        let asks = (1...5).map { Rig.session($0, .needsInput, reason: .question) }
        let failed = Rig.session(9, .error)
        rig.lab.showDemo(working: [], cards: asks.map(LabCard.needsInput) + [.failed(failed)])
        rig.model.open()
        let shown = rig.model.sections.needs.filter { $0.kind != .stopped }.map(\.session.id)
        #expect(Set(rig.asked.prepared) == Set(shown), "the rows on screen, none of the ones behind \"N more\", none of a stop")
        #expect(rig.asked.prepared.count == CompanionSections.rowLimit)
    }

    @Test func anOpenPopoverFollowsTheLab() async {
        let rig = Rig()
        rig.lab.showDemo(working: [Rig.session(1, .running)], cards: [])
        rig.model.open()
        #expect(rig.model.sections.workingTotal == 1 && rig.model.sections.needsTotal == 0)
        rig.lab.showDemo(working: [Rig.session(1, .running), Rig.session(3, .running)],
                         cards: [.needsInput(Rig.session(2, .needsInput, reason: .plan))])
        await Rig.settle()
        #expect(rig.model.sections.workingTotal == 2 && rig.model.sections.needsTotal == 1)
    }

    @Test func closingStopsLookingAndLetsGo() async {
        let rig = Rig()
        rig.lab.showDemo(working: [Rig.session(1, .running)], cards: [])
        rig.model.open()
        rig.model.close()
        #expect(!rig.model.isOpen && rig.model.sections == .empty && !rig.results.isOpen)
        let before = rig.asked.total
        rig.lab.showDemo(working: [], cards: [.needsInput(Rig.session(2, .needsInput, reason: .question))])
        rig.model.refresh()
        await Rig.settle()
        #expect(rig.asked.total == before, "no look after the popover closed")
        #expect(rig.model.sections == .empty)
    }

    @Test func reopeningStartsAgainFromWhatIsThereNow() async {
        let rig = Rig()
        rig.lab.showDemo(working: [Rig.session(1, .running)], cards: [])
        rig.model.open()
        rig.model.close()
        rig.lab.showDemo(working: [], cards: [.needsInput(Rig.session(2, .needsInput, reason: .question))])
        rig.model.open()
        #expect(rig.model.sections.needsTotal == 1 && rig.model.sections.workingTotal == 0)
    }

    @Test func nMoreShowsTheRestAndAClosedPopoverForgetsThatItDid() async {
        let rig = Rig()
        let asks = (1...5).map { Rig.session($0, .needsInput, reason: .question) }
        rig.lab.showDemo(working: [], cards: asks.map(LabCard.needsInput))
        rig.model.open()
        #expect(rig.model.sections.needs.count == 3 && rig.model.sections.needsHidden == 2)
        rig.model.showAllNeeds()
        #expect(rig.model.sections.needs.count == 5 && rig.model.sections.needsHidden == 0)
        rig.model.close()
        rig.model.open()
        #expect(rig.model.sections.needs.count == 3, "each opening starts short")
    }

    @Test func aRowOffersLaterOnlyWhileItsCardIsInTheQueue() async {
        let rig = Rig()
        let queued = Rig.session(1, .needsInput, reason: .question)
        rig.lab.showDemo(working: [], cards: [.needsInput(queued)])
        rig.model.open()
        #expect(rig.model.sections.needs.first?.pills.map(\.title).contains("Later") == true)
    }
}

// MARK: The setting

struct CompanionSettingsTests {
    @Test func theItemIsOnUnlessTheStoredValueSaysNo() {
        #expect(CompanionSettings.resolve(stored: nil), "an install from before 1.0 has no value: it gets the item")
        #expect(CompanionSettings.resolve(stored: true))
        #expect(!CompanionSettings.resolve(stored: false))
        for off in ["NO", "no", "false", "False", "0"] { #expect(!CompanionSettings.resolve(stored: off), "-showCapsidInMenuBar \(off)") }
        for on in ["YES", "true", "1"] { #expect(CompanionSettings.resolve(stored: on)) }
        #expect(CompanionSettings.resolve(stored: 42), "a value that isn't a switch is no reason to hide it")
    }

    @MainActor
    @Test func theDefaultIsRegisteredOn() {
        CompanionSettings.register()
        #expect(UserDefaults.standard.object(forKey: SettingsKey.showMenuBarHome) as? Bool != false)
        #expect(SettingsKey.showMenuBarHome == "showCapsidInMenuBar")
        #expect(CompanionSettings.key == SettingsKey.showMenuBarHome)
    }

    @Test func theOlderSwitchKeepsItsKeyAndItsDefault() {
        #expect(SettingsKey.showMenuBarSpecimen == "showMenuBarSpecimen")
    }

    @Test func turningTheSpecimenOnTurnsTheItemOnToo() {
        // Off to on, with the item off: the item follows.
        #expect(CompanionSettings.homeAfter(specimenWas: false, specimenNow: true, home: false))
        // Already on and the item then turned off by hand: it stays off.
        #expect(!CompanionSettings.homeAfter(specimenWas: true, specimenNow: true, home: false))
        // Turning the specimen off leaves the item as it was.
        #expect(CompanionSettings.homeAfter(specimenWas: true, specimenNow: false, home: true))
        #expect(!CompanionSettings.homeAfter(specimenWas: true, specimenNow: false, home: false))
        #expect(!CompanionSettings.homeAfter(specimenWas: false, specimenNow: false, home: false))
    }
}

// MARK: Where the popover goes

struct CompanionPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 870)
    private let size = CGSize(width: 400, height: 640)

    @Test func itHangsUnderTheItemSixPointsBelowTheMenuBar() {
        let item = CGRect(x: 1300, y: 870, width: 36, height: 24)
        let frame = CompanionPlacement.frame(size: size, anchor: item, visible: screen)
        #expect(frame.maxY == 870 - CompanionPlacement.gap, "the menu bar's foot is the visible area's top")
        #expect(frame.height == 640 && frame.width == 400)
    }

    @Test func itIsKeptInsideTheScreenAtTheRight() {
        let item = CGRect(x: 1400, y: 870, width: 36, height: 24)
        let frame = CompanionPlacement.frame(size: size, anchor: item, visible: screen)
        #expect(frame.maxX == screen.maxX - CompanionPlacement.margin)
    }

    @Test func itIsKeptInsideTheScreenAtTheLeft() {
        let item = CGRect(x: 4, y: 870, width: 36, height: 24)
        #expect(CompanionPlacement.frame(size: size, anchor: item, visible: screen).minX == CompanionPlacement.margin)
    }

    @Test func itIsCentredUnderAnItemInTheMiddle() {
        let item = CGRect(x: 700, y: 870, width: 40, height: 24)
        let frame = CompanionPlacement.frame(size: size, anchor: item, visible: screen)
        #expect(abs(frame.midX - item.midX) < 0.5)
    }

    @Test func itIsNoTallerThanTheRoomBelowTheMenuBar() {
        let short = CGRect(x: 0, y: 0, width: 1440, height: 500)
        let item = CGRect(x: 1300, y: 500, width: 36, height: 24)
        let frame = CompanionPlacement.frame(size: size, anchor: item, visible: short)
        #expect(frame.height == CompanionPlacement.maxHeight(anchor: item, visible: short))
        #expect(frame.minY >= short.minY + CompanionPlacement.margin - 0.5)
        #expect(CompanionPlacement.maxHeight(anchor: item, visible: CGRect(x: 0, y: 0, width: 1440, height: 100)) == 200, "never absurdly short")
    }

    @Test func aMenuBarThatHidesPutsItUnderTheItem() {
        // The visible area runs to the top of the screen; the item sits lower than that, shown by hovering.
        let item = CGRect(x: 1300, y: 846, width: 36, height: 24)
        let frame = CompanionPlacement.frame(size: size, anchor: item, visible: CGRect(x: 0, y: 0, width: 1440, height: 870))
        #expect(frame.maxY == 846 - CompanionPlacement.gap)
    }
}
