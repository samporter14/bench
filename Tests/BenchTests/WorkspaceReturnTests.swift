// WorkspaceReturnTests.swift — Return to Project on a made-up app: it uses the
// one main web view (through a Router of its own, as the app's does) and does
// nothing but read and open; what can't come back is said, part by part, and
// never holds the rest back; a repeated Return makes no second window and
// leaves nothing waiting; and a Return to A followed by one to B leaves
// nothing of A's to land afterwards. The landings themselves are a real
// reference model's, on the demo's made-up history: a pinned reply lands on
// its row, a reply that has gone is said and never taken for a success, and a
// window already open is moved rather than made again.
import Foundation
import Testing
@testable import Bench

@MainActor
struct WorkspaceReturnTests {
    private static let alpha = "proj-alpha"
    private static let beta = "proj-beta"

    private func pin(_ n: Int, project: String = WorkspaceReturnTests.alpha, row: Int? = 19) -> WorkspacePin {
        WorkspacePin(sessionID: madeUpID(n), projectID: project, row: row, title: "Run \(n)", pinnedAt: Date())
    }

    private func plan(_ project: String = WorkspaceReturnTests.alpha, last: Int? = 100, pins: [WorkspacePin]) -> WorkspaceReturnPlan {
        WorkspaceReturnPlan(projectID: project, projectName: "Assay development", lastSession: last.map(madeUpID), pins: pins)
    }

    // MARK: One main web view, reads and opens only

    @Test func returnBringsEachPartBackThroughTheOneMainWebView() async {
        let app = FakeWorkspaceApp()
        app.sessions[madeUpID(100)] = .known(title: "Plate reader QC", projectName: "Assay development")
        app.sessions[madeUpID(1)] = .known(title: "Dose response", projectName: "Assay development")
        app.sessions[madeUpID(2)] = .known(title: "Z\u{2032} by plate", projectName: "Assay development")
        app.shelfProjects = [Self.alpha]
        let returner = WorkspaceReturner(dependencies: app.dependencies)
        await returner.bringBack(plan(pins: [pin(1, row: 19), pin(2, row: nil)])).value
        #expect(app.navigations == [LastSession.Route(projectID: Self.alpha, frameID: madeUpID(100))])
        #expect(app.openings.map(\.session) == [madeUpID(1), madeUpID(2)])
        #expect(app.openings.map(\.row) == [19, nil])
        #expect(app.shelfShown == [Self.alpha])
        #expect(returner.summaries[Self.alpha]?.problems == [])
        #expect(returner.summaries[Self.alpha]?.headline == nil)
        #expect(returner.returning == nil)
    }

    @Test func theMainWindowIsLoadedThroughTheRouterOnceAndOnlyWhenItCanBe() {
        let router = Router()
        var loads: [URL] = []
        var shows = 0
        var scienceOpened = 0
        router.navigate = { loads.append($0) }
        router.showWindow = { shows += 1 }
        let route = LastSession.Route(projectID: Self.alpha, frameID: madeUpID(100))
        #expect(WorkspaceNavigation.go(to: route, router: router, port: 8765, showing: nil))
        #expect(loads == [URL(string: "http://localhost:8765/projects/proj-alpha/frames/\(madeUpID(100))")!] && shows == 1)
        // Already on show: shown again, not loaded again.
        #expect(WorkspaceNavigation.go(to: route, router: router, port: 8765, showing: route))
        #expect(loads.count == 1 && shows == 2)
        // While Capsid only reads, nothing is opened, and Return says so.
        router.openInScience = { scienceOpened += 1 }
        #expect(!WorkspaceNavigation.go(to: route, router: router, port: 8765, showing: nil))
        #expect(loads.count == 1 && shows == 2 && scienceOpened == 0)
    }

    @Test func whatCantComeBackIsSaidAndTheRestStillComes() async throws {
        let app = FakeWorkspaceApp()
        // The last conversation has gone; one pin's session too; one pin's reply; the last pin lands.
        app.sessions[madeUpID(2)] = .known(title: "Reply gone", projectName: "Assay development")
        app.sessions[madeUpID(3)] = .known(title: "Lands", projectName: "Assay development")
        app.landings[madeUpID(2)] = .replyMissing
        app.shelfProjects = [Self.alpha]
        let returner = WorkspaceReturner(dependencies: app.dependencies)
        await returner.bringBack(plan(pins: [pin(1), pin(2), pin(3)])).value
        let summary = try #require(returner.summaries[Self.alpha])
        #expect(summary.problems.map(\.order) == [0, 1, 2])
        #expect(summary.problems[0].sentence == WorkspaceReturnWords.conversationGone)
        #expect(summary.problems[1].sentence == WorkspaceReturnWords.pinGone("Run 1"))
        #expect(summary.problems[2].sentence.contains("isn\u{2019}t there any more"))
        #expect(summary.headline != nil)
        // Nothing gone was opened, the main window stayed, and the rest came back.
        #expect(app.navigations.isEmpty)
        #expect(app.openings.map(\.session) == [madeUpID(2), madeUpID(3)])
        #expect(app.shelfShown == [Self.alpha])
    }

    @Test func aProjectWithNothingOnTheShelfLeavesTheShelfAlone() async {
        let app = FakeWorkspaceApp()
        app.shelfProjects = [Self.beta]
        let returner = WorkspaceReturner(dependencies: app.dependencies)
        await returner.bringBack(plan(last: nil, pins: [])).value
        #expect(app.shelfShown.isEmpty && app.navigations.isEmpty && app.openings.isEmpty)
        #expect(returner.summaries[Self.alpha]?.problems == [])
    }

    @Test func anUnreadableDatabaseOrAMainWindowThatCantShowIsSaid() async {
        let app = FakeWorkspaceApp()
        app.sessions[madeUpID(100)] = .unreadable
        let returner = WorkspaceReturner(dependencies: app.dependencies)
        await returner.bringBack(plan(pins: [])).value
        #expect(returner.summaries[Self.alpha]?.problems.map(\.sentence) == [WorkspaceReturnWords.databaseUnreadable])
        app.sessions[madeUpID(100)] = .known(title: "x", projectName: "x")
        app.canNavigate = false
        await returner.bringBack(plan(pins: [])).value
        #expect(returner.summaries[Self.alpha]?.problems.map(\.sentence) == [WorkspaceReturnWords.cantShow])
    }

    // MARK: Again, and A then B

    @Test func aRepeatedReturnMakesNoSecondWindowAndLeavesNothingWaiting() async {
        let app = FakeWorkspaceApp()
        app.sessions[madeUpID(100)] = .known(title: "Plate reader QC", projectName: "Assay development")
        app.sessions[madeUpID(1)] = .known(title: "Run 1", projectName: "Assay development")
        app.sessions[madeUpID(2)] = .known(title: "Run 2", projectName: "Assay development")
        app.shelfProjects = [Self.alpha]
        let returner = WorkspaceReturner(dependencies: app.dependencies)
        let returnPlan = plan(pins: [pin(1), pin(2)])
        await returner.bringBack(returnPlan).value
        let first = returner.summaries[Self.alpha]
        await returner.bringBack(returnPlan).value
        // Pressed twice in a row, the second while the first runs.
        returner.bringBack(returnPlan)
        await returner.bringBack(returnPlan).value
        #expect(app.windows.count == 2)
        #expect(!app.navigations.isEmpty
                && app.navigations.allSatisfy { $0 == LastSession.Route(projectID: Self.alpha, frameID: madeUpID(100)) })
        #expect(Set(app.shelfShown) == [Self.alpha])
        #expect(returner.summaries[Self.alpha] == first)
        await untilWorkspace { app.waiting == 0 }
        #expect(app.waiting == 0 && returner.returning == nil)
    }

    @Test func aReturnToAThenBLeavesNothingOfAsToLandAfterwards() async {
        let app = FakeWorkspaceApp()
        app.sessions[madeUpID(100)] = .known(title: "A's last", projectName: "Assay development")
        app.sessions[madeUpID(1)] = .known(title: "A's pin", projectName: "Assay development")
        app.sessions[madeUpID(200)] = .known(title: "B's last", projectName: "Plate reader QC")
        app.sessions[madeUpID(2)] = .known(title: "B's pin", projectName: "Plate reader QC")
        app.shelfProjects = [Self.alpha, Self.beta]
        // A's looks, and its look at the Shelf, are held until after B has finished.
        app.holding = [madeUpID(100), madeUpID(1), "shelf:" + Self.alpha]
        let returner = WorkspaceReturner(dependencies: app.dependencies)
        let toA = returner.bringBack(plan(Self.alpha, last: 100, pins: [pin(1, project: Self.alpha)]))
        await untilWorkspace { app.heldLooks == 3 }
        await returner.bringBack(plan(Self.beta, last: 200, pins: [pin(2, project: Self.beta)])).value
        #expect(app.navigations == [LastSession.Route(projectID: Self.beta, frameID: madeUpID(200))])
        app.release(madeUpID(100))
        app.release(madeUpID(1))
        app.release("shelf:" + Self.alpha)
        await toA.value
        for _ in 0..<100 { await Task.yield() }
        // Nothing moved back to A: no load, no window, no Shelf, no summary.
        #expect(app.navigations == [LastSession.Route(projectID: Self.beta, frameID: madeUpID(200))])
        #expect(app.openings.map(\.session) == [madeUpID(2)])
        #expect(app.shelfShown == [Self.beta])
        #expect(returner.summaries[Self.alpha] == nil && returner.summaries[Self.beta] != nil)
        #expect(returner.returning == nil && app.waiting == 0)
    }

    // MARK: The panel

    @Test func thePanelReturnsWithWhatItsRecordAndTheVisitsKnowAndComesForwardForAProblem() async {
        let disk = FakeWorkspaceDisk()
        let store = WorkspaceStore(disk: disk)
        _ = await store.pin(sessionID: madeUpID(1), projectID: Self.alpha, row: 19, title: "Run 1", projectName: "Assay development")
        let app = FakeWorkspaceApp()
        app.sessions[madeUpID(100)] = .known(title: "Plate reader QC", projectName: "Assay development")
        let model = WorkspacePanelModel(store: store, returner: WorkspaceReturner(dependencies: app.dependencies),
                                        dependencies: WorkspacePanelDependencies(
                                            look: { _, _ in .known(title: "Plate reader QC", projectName: "Assay development") },
                                            projectName: { _ in nil }, watchedName: { _ in nil },
                                            lastSession: { $0 == Self.alpha ? madeUpID(100) : nil }, openPin: { _, _ in }))
        var cameForward = 0
        model.problemsFound = { cameForward += 1 }
        await model.show(Self.alpha).value
        #expect(model.returnLine == "Opens \u{201C}Plate reader QC\u{201D}")
        // Run 1's session is gone from the made-up database: that is said, and the panel comes forward.
        await model.returnToProject().value
        #expect(app.navigations == [LastSession.Route(projectID: Self.alpha, frameID: madeUpID(100))])
        #expect(model.summary?.problems.map(\.sentence) == [WorkspaceReturnWords.pinGone("Plate reader QC")])
        #expect(cameForward == 1)
    }

    // MARK: Landing on a pinned reply (a real reference model, the demo's history)

    private func reference() -> ReferenceModel {
        ReferenceModel(session: ReferenceDemo.session, dependencies: ReferenceDemo.dependencies(delay: .zero),
                       gate: ReadingGate(now: { Date() }, sleep: { _ in }))
    }

    private func settle(_ model: ReferenceModel) async throws {
        for _ in 0..<400 where !WorkspaceLanding.isSettled(model) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(WorkspaceLanding.isSettled(model))
    }

    @Test func aPinnedHistoricalReplyLandsOnItsOwnRow() async throws {
        let model = reference()
        defer { model.close() }
        // The demo's middle reply runs from row 10 (the question) to row 19.
        model.open(at: 19, mark: nil)
        try await settle(model)
        #expect(WorkspaceLanding.outcome(of: model, row: 19) == .landed)
        #expect(model.current?.start == 10 && model.current?.id == 19)
        #expect(model.landingNote == nil)
    }

    @Test func aReplyThatIsntThereIsSaidAndNeverTakenForSuccess() async throws {
        let model = reference()
        defer { model.close() }
        // The history ends at row 33: row 50 is in no reply. The model shows the newest, but that isn't the pinned one.
        model.open(at: 50, mark: nil)
        try await settle(model)
        #expect(model.current != nil)
        #expect(WorkspaceLanding.outcome(of: model, row: 50) == .replyMissing)
        model.notePinnedReplyGone()
        #expect(model.landingNote == ReferenceModel.pinnedReplyGoneSentence)
        // The outcome reads the model, not the words: a reply that holds the row is a landing.
        #expect(WorkspaceLanding.outcome(phase: .idle, landing: false, current: model.current, note: nil, row: 25) == .landed)
        #expect(WorkspaceLanding.outcome(phase: .idle, landing: false, current: nil, note: nil, row: 25) == .replyMissing)
        #expect(WorkspaceLanding.outcome(phase: .idle, landing: true, current: model.current, note: nil, row: 25) == .stillReading)
        #expect(WorkspaceLanding.outcome(phase: .failed("x"), landing: true, current: nil, note: nil, row: 25) == .failed("x"))
        #expect(WorkspaceLanding.outcome(phase: .idle, landing: false, current: model.current, note: ReferenceModel.tooFarSentence,
                                         row: 2) == .tooFar)
    }

    @Test func aWindowAlreadyOpenIsMovedToThePinnedReplyNotMadeAgain() async throws {
        let model = reference()
        defer { model.close() }
        model.open()
        try await settle(model)
        #expect(model.current?.id == 33)
        // What the controller does with a window already open on the session: the same model lands again.
        model.land(at: 5, mark: nil)
        try await settle(model)
        #expect(WorkspaceLanding.outcome(of: model, row: 5) == .landed)
        #expect(model.current?.start == 0 && model.current?.id == 9)
        // And again, idempotently.
        model.land(at: 5, mark: nil)
        try await settle(model)
        #expect(model.current?.id == 9)
    }

    @Test func aConversationThatCantBeReadIsAFailureNotALanding() async throws {
        let model = ReferenceModel(session: ReferenceDemo.session, dependencies: ReferenceDemo.dependencies(failing: true, delay: .zero),
                                   gate: ReadingGate(now: { Date() }, sleep: { _ in }))
        defer { model.close() }
        model.open(at: 19, mark: nil)
        try await settle(model)
        #expect(WorkspaceLanding.outcome(of: model, row: 19) == .failed(ReferenceRules.failureSentence))
    }

    // MARK: Screens

    @Test func aWindowOnAScreenThatHasGoneComesBackToTheMainScreen() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let onScreen = NSRect(x: 100, y: 100, width: 400, height: 580)
        #expect(WorkspaceScreens.reachable(onScreen, screens: [main], visible: main) == onScreen)
        let gone = NSRect(x: 3000, y: 100, width: 400, height: 580)
        let moved = WorkspaceScreens.reachable(gone, screens: [main], visible: main)
        #expect(main.contains(moved) && moved.size == gone.size)
        // A window taller than the screen is cut to it.
        let tall = WorkspaceScreens.reachable(NSRect(x: 4000, y: 0, width: 400, height: 2000), screens: [main], visible: main)
        #expect(tall.height == main.height)
    }
}
