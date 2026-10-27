// WorkspaceLive.swift — Return to Project and the panel on the real app
// (DESIGN.md, Project Workspaces): the database read the way Capsid always
// reads it (read only, off the main actor, two seconds at most), the main
// window through the Router, the reference windows through their controller
// (one per session, so an open one is used again), and the Shelf by the
// project's id. A reference's landing is watched until it ends, for half a
// minute at most, and a pinned reply that isn't there any more is said in
// its window as well as in the panel, never shown as if it were.
import AppKit
import Foundation

/// The database, as the panel and Return ask it.
enum WorkspaceDatabase {
    /// Whether the database has `sessionID` as a session of `projectID`, and what it calls them now.
    nonisolated static func look(sessionID: String, projectID: String) async -> WorkspaceSessionLook {
        guard PlanCheck.isFrameID(sessionID), BrowseSQL.isProjectID(projectID) else { return .gone }
        return await Task.detached(priority: .userInitiated) { () -> WorkspaceSessionLook in
            guard let db = resolveDatabase() else { return .unreadable }
            do {
                guard let row = try fetchSession(db: db, id: sessionID, timeout: 2), row.projectID == projectID else { return .gone }
                return .known(title: row.name, projectName: row.projectName)
            } catch {
                return .unreadable
            }
        }.value
    }

    /// The project's name as the database has it, when it can be read.
    nonisolated static func projectName(_ projectID: String) async -> String? {
        guard BrowseSQL.isProjectID(projectID) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard let db = resolveDatabase(), let names = try? fetchProjectNames(db: db) else { return nil }
            return names[projectID]
        }.value
    }
}

/// How a reference window's landing ended, from what its model shows.
@MainActor
enum WorkspaceLanding {
    /// The landing is over: it found a reply, found none, stopped short, or a read failed.
    static func isSettled(_ model: ReferenceModel) -> Bool {
        if case .failed = model.phase { return true }
        return !model.isLanding && model.phase != .reading
    }

    /// Waits for the landing to end, `timeout` at most, checking a few times a second (only while Return waits).
    static func wait(for model: ReferenceModel, timeout: Duration = .seconds(30)) async {
        let deadline = ContinuousClock.now + timeout
        while !isSettled(model), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// A pinned reference's window, opened (or the one already open), on a reachable screen, at its reply; and how
    /// the landing ended. A reply that has gone is said in the window too, so the reply it shows instead is never
    /// taken for the pinned one.
    static func open(_ pin: WorkspacePin, projectName: String) async -> WorkspacePinOutcome {
        guard Demo.mode == nil,
              let model = ReferenceWindowController.shared.showPinned(sessionID: pin.sessionID, projectID: pin.projectID,
                                                                     title: pin.title, projectName: projectName, row: pin.row)
        else { return .failed(ReferenceRules.failureSentence) }
        WorkspaceScreens.keepReachable(ReferenceWindowController.shared.window(for: pin.sessionID))
        await wait(for: model)
        let outcome = outcome(of: model, row: pin.row)
        if outcome == .replyMissing { model.notePinnedReplyGone() }
        return outcome
    }

    static func outcome(of model: ReferenceModel, row: Int?) -> WorkspacePinOutcome {
        outcome(phase: model.phase, landing: model.isLanding, current: model.current, note: model.landingNote, row: row)
    }

    /// Pure: on the reply that holds the pinned row, or what else happened. With no row (pinned with no reply on
    /// the page) any reply is the right one.
    static func outcome(phase: ReferenceModel.Phase, landing: Bool, current: ReferenceAnswer?, note: String?,
                        row: Int?) -> WorkspacePinOutcome {
        if case .failed(let sentence) = phase { return .failed(sentence) }
        if landing || phase == .reading { return .stillReading }
        if note == ReferenceModel.tooFarSentence { return .tooFar }
        guard let row else { return .landed }
        guard let current, holds(current, row: row) else { return .replyMissing }
        return .landed
    }

    /// The reply runs from its first row to its last: the row before the next message of the user's, or for the
    /// newest reply the last row read. A row past the end of the history is in no reply.
    static func holds(_ answer: ReferenceAnswer, row: Int) -> Bool {
        answer.start <= row && row <= (answer.rowEnd ?? answer.id)
    }
}

extension WorkspaceReturnDependencies {
    @MainActor
    static func live() -> WorkspaceReturnDependencies {
        WorkspaceReturnDependencies(
            look: { sessionID, projectID in await WorkspaceDatabase.look(sessionID: sessionID, projectID: projectID) },
            navigate: { route in
                guard Demo.mode == nil else { return false }
                let container = WebContainer.shared
                return WorkspaceNavigation.go(to: route, router: .shared, port: container.port,
                                              showing: NidusTaskSelection.route(url: container.webView.url, daemonPort: container.port))
            },
            openReference: { pin, projectName in await WorkspaceLanding.open(pin, projectName: projectName) },
            shelfHas: { projectID in
                let index = Shelf.shared.index
                await index.refreshAndWait()
                return index.results.contains { $0.record.projectID == projectID }
            },
            showShelf: { projectID in
                Shelf.shared.show()
                KeptWindowController.shared.model?.show(projectID: projectID)
            })
    }
}

/// The main window, to a session, through the Router: the one web view's `load`, never another view.
@MainActor
enum WorkspaceNavigation {
    /// Loads `route` in the main web view and shows the window. A session already on show is only shown, not
    /// loaded again, so a second Return reloads nothing. While Capsid only reads, an Open would open Claude
    /// Science's own window rather than the session: nothing is done, and false says so.
    static func go(to route: LastSession.Route, router: Router, port: Int?, showing: LastSession.Route?) -> Bool {
        guard router.openInScience == nil else { return false }
        if showing == route {
            router.showWindow()
            return true
        }
        guard let url = URL(string: "http://localhost:\(port ?? 8765)/projects/\(route.projectID)/frames/\(route.frameID)") else {
            return false
        }
        router.open(url)
        return true
    }
}

/// Windows Return brings forward stay where a person can reach them: a remembered frame on a screen that has gone
/// is moved onto the main screen. The frames themselves are each window's own (`setFrameUsingName`).
@MainActor
enum WorkspaceScreens {
    /// `frame`, or `frame` moved into `visible` (the screen's visible frame) when it is on none of `screens`.
    static func reachable(_ frame: NSRect, screens: [NSRect], visible: NSRect) -> NSRect {
        // A title bar's worth on some screen is reachable.
        let grip = NSRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        if screens.contains(where: { $0.intersection(grip).width >= 40 }) { return frame }
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    static func keepReachable(_ window: NSWindow?) {
        guard let window, let main = NSScreen.main else { return }
        let moved = reachable(window.frame, screens: NSScreen.screens.map(\.visibleFrame), visible: main.visibleFrame)
        if moved != window.frame { window.setFrame(moved, display: true) }
    }
}
