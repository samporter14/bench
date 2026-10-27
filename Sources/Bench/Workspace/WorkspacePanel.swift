// WorkspacePanel.swift — the Project Workspace panel's model and window
// (DESIGN.md, Project Workspaces → The panel). One compact window, on the 1.0
// windows' Solanum surface, that shows one project at a time: the main
// window's project when it is opened from the History menu, the project a
// Return was for, the reference's project from its ⋯ menu. Moving it to
// another project, or closing it, writes the note first. Titles are read from
// the database only when it opens on a project (read only, as Reference reads),
// and a look that comes back after it moved on is dropped.
import AppKit
import SwiftUI

/// What the panel reads and opens through. Tests stand fakes in.
struct WorkspacePanelDependencies {
    /// A session as the database has it (the panel's titles, and whether it has gone).
    var look: @Sendable (_ sessionID: String, _ projectID: String) async -> WorkspaceSessionLook
    /// The project's name from the database, when nothing nearer has it.
    var projectName: @Sendable (_ projectID: String) async -> String?
    /// The project's name from the sessions Capsid is already watching, if one of them is in it.
    var watchedName: @MainActor (_ projectID: String) -> String?
    /// The session last shown in the project (WorkspaceVisits), and where the project comes in that order.
    var lastSession: @MainActor (_ projectID: String) -> String?
    /// A pin's row was clicked: its reference window, at its reply.
    var openPin: @MainActor (_ pin: WorkspacePin, _ projectName: String) -> Void

    @MainActor
    static func live() -> WorkspacePanelDependencies {
        WorkspacePanelDependencies(
            look: { sessionID, projectID in await WorkspaceDatabase.look(sessionID: sessionID, projectID: projectID) },
            projectName: { await WorkspaceDatabase.projectName($0) },
            watchedName: { projectID in
                LabModel.shared.reads.sessions.first { $0.projectID == projectID }.map(\.projectName)
            },
            lastSession: { WorkspaceVisits().lastSession(in: $0) },
            openPin: { pin, projectName in
                guard Demo.mode == nil else { return }
                // As Return opens it: at its reply, and a reply that has gone is said in the window.
                Task { _ = await WorkspaceLanding.open(pin, projectName: projectName) }
            })
    }
}

@MainActor
final class WorkspacePanelModel: ObservableObject {
    let store: WorkspaceStore
    let returner: WorkspaceReturner
    private let dependencies: WorkspacePanelDependencies

    @Published private(set) var projectID: String?
    @Published private(set) var projectName = ""
    /// The last conversation here: its id, and what the database calls it (nil until it has said, or when it can't).
    @Published private(set) var lastSession: String?
    @Published private(set) var lastTitle: String?
    @Published private(set) var lastGone = false
    /// Pinned sessions the database no longer has in this project.
    @Published private(set) var gonePins: Set<String> = []
    /// The project had nothing when the panel came to it: the panel says what a workspace is for. Kept until the
    /// panel moves on, so the first words typed don't make the page jump.
    @Published private(set) var isFresh = false
    /// Why Clear Workspace… didn't clear, until the next try.
    @Published private(set) var clearProblem: String?
    /// Return found something it couldn't bring back: the window comes forward to say so.
    var problemsFound: @MainActor () -> Void = {}

    /// Bumped each time the panel comes to a project: a look begun for another lands on nothing.
    private var token = 0

    init(store: WorkspaceStore, returner: WorkspaceReturner, dependencies: WorkspacePanelDependencies) {
        self.store = store
        self.returner = returner
        self.dependencies = dependencies
    }

    // MARK: Moving

    /// Shows `projectID`. The note of the project it showed before is written now. The record is read, and the
    /// titles looked up, once per coming.
    @discardableResult
    func show(_ projectID: String, name: String? = nil) -> Task<Void, Never> {
        guard WorkspaceRules.isProjectID(projectID) else { return Task {} }
        if let shown = self.projectID, shown != projectID { store.flush(shown) }
        token += 1
        let token = token
        if self.projectID != projectID {
            clearProblem = nil
            lastTitle = nil
            lastGone = false
            gonePins = []
        }
        self.projectID = projectID
        let known = name.map(WorkspaceRules.clean).flatMap { $0.isEmpty ? nil : $0 }
            ?? dependencies.watchedName(projectID) ?? store.record(projectID)?.projectName
            ?? store.summaries[projectID]?.projectName
        projectName = known ?? ""
        lastSession = dependencies.lastSession(projectID)
        let loading = store.load(projectID, name: known)
        return Task { [weak self] in
            await loading.value
            guard let self, self.token == token else { return }
            self.isFresh = !(self.store.record(projectID)?.hasContent ?? true)
            await self.lookUpTitles(projectID, token: token)
        }
    }

    /// The window closed: the note is written now.
    @discardableResult
    func close() -> Task<Void, Never> {
        token += 1
        guard let projectID else { return Task {} }
        return store.flush(projectID)
    }

    /// The pinned sessions' and the last conversation's titles, and the project's name, as the database has them now.
    private func lookUpTitles(_ projectID: String, token: Int) async {
        var titles: [String: String] = [:]
        var gone: Set<String> = []
        var databaseName: String?
        if let last = lastSession {
            let look = await dependencies.look(last, projectID)
            guard self.token == token else { return }
            switch look {
            case .known(let title, let name):
                lastTitle = WorkspaceRules.clean(title)
                databaseName = databaseName ?? name
            case .gone:
                lastGone = true
            case .unreadable:
                break
            }
        }
        for pin in store.record(projectID)?.pins ?? [] {
            let look = await dependencies.look(pin.sessionID, projectID)
            guard self.token == token else { return }
            switch look {
            case .known(let title, let name):
                titles[pin.sessionID] = title
                databaseName = databaseName ?? name
            case .gone:
                gone.insert(pin.sessionID)
            case .unreadable:
                break
            }
        }
        if databaseName == nil, projectName.isEmpty { databaseName = await dependencies.projectName(projectID) }
        guard self.token == token else { return }
        gonePins = gone
        store.retitle(projectID, titles: titles)
        if let databaseName, !WorkspaceRules.clean(databaseName).isEmpty {
            projectName = WorkspaceRules.clean(databaseName)
            store.rename(projectID, to: projectName)
        }
    }

    // MARK: What is shown

    var record: WorkspaceRecord? { projectID.flatMap { store.record($0) } }
    var standing: WorkspaceStore.Standing? { projectID.flatMap { store.standing($0) } }
    var save: WorkspaceStore.SaveState { projectID.map { store.save($0) } ?? .init() }
    var summary: WorkspaceReturnSummary? { projectID.flatMap { returner.summaries[$0] } }
    var isReturning: Bool { projectID != nil && returner.returning == projectID }
    var displayName: String { projectName.isEmpty ? "This project" : projectName }

    /// The quiet line by Return to Project: the conversation it will open.
    var returnLine: String {
        if lastSession == nil { return "No conversation here yet" }
        if lastGone { return "Last conversation gone" }
        if let lastTitle, !lastTitle.isEmpty { return "Opens \u{201C}\(lastTitle)\u{201D}" }
        return "Opens the last conversation"
    }

    /// The full title, for the line's tooltip.
    var returnLineHelp: String {
        lastTitle.map { "Return to Project opens \u{201C}\($0)\u{201D} in the main window" }
            ?? "Return to Project opens the last conversation you had here"
    }

    // MARK: Acting

    func edit(_ text: String) {
        guard let projectID else { return }
        store.setNote(text, for: projectID)
    }

    func refuseEdit() {
        guard let projectID else { return }
        store.refuseNote(for: projectID)
    }

    func retry() {
        guard let projectID else { return }
        store.retry(projectID)
    }

    func open(_ pin: WorkspacePin) {
        dependencies.openPin(pin, displayName)
    }

    func unpin(_ pin: WorkspacePin) {
        guard let projectID else { return }
        Task { await store.unpin(sessionID: pin.sessionID, projectID: projectID) }
    }

    /// Return to Project, for the project shown: what the record and the visits know, once the record is read.
    @discardableResult
    func returnToProject() -> Task<Void, Never> {
        guard let projectID else { return Task {} }
        store.flush(projectID)
        let token = token
        return Task { [weak self] in
            guard let self else { return }
            _ = await self.store.ready(projectID)
            guard self.token == token, self.projectID == projectID else { return }
            let plan = WorkspaceReturnPlan(projectID: projectID, projectName: displayName,
                                           lastSession: dependencies.lastSession(projectID),
                                           pins: store.record(projectID)?.pins ?? [])
            await returner.bringBack(plan).value
            if self.projectID == projectID, let summary = returner.summaries[projectID], !summary.problems.isEmpty {
                problemsFound()
            }
        }
    }

    /// Clear Workspace…, once confirmed.
    @discardableResult
    func clear() -> Task<Void, Never> {
        guard let projectID else { return Task {} }
        clearProblem = nil
        return Task { [weak self] in
            guard let self else { return }
            let problem = await store.clear(projectID)
            guard self.projectID == projectID else { return }
            clearProblem = problem
            if problem == nil {
                isFresh = true
                gonePins = []
                returner.dismissSummary(for: projectID)
            }
        }
    }

    /// Whether Clear Workspace… has anything to clear.
    var canClear: Bool {
        guard projectID != nil else { return false }
        switch standing {
        case .damaged, .newer: return true
        case .ready: return record?.hasContent ?? false
        default: return false
        }
    }
}

/// The panel's window: one, moved between projects.
@MainActor
final class WorkspacePanelController: NSObject, NSWindowDelegate {
    static let shared = WorkspacePanelController()
    /// The window's size before the user resizes it, and the least it may be.
    static let size = NSSize(width: 400, height: 580)
    static let minimum = NSSize(width: 360, height: 500)
    private static let frameName = "CapsidWorkspace"

    private(set) lazy var model: WorkspacePanelModel = {
        let model = WorkspacePanelModel(store: .shared, returner: WorkspaceReturner(dependencies: .live()),
                                        dependencies: .live())
        model.problemsFound = { [weak self] in self?.window?.orderFront(nil) }
        return model
    }()
    private var window: NSWindow?

    /// The panel on `projectID`, brought forward.
    func show(projectID: String, name: String? = nil) {
        model.show(projectID, name: name)
        let window = window ?? makeWindow()
        WorkspaceScreens.keepReachable(window)
        Demo.activateUnlessQuiet()
        if Demo.isQuiet { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil) }
    }

    /// Return to Project from the menu: the panel on that project, then the Return.
    func returnTo(projectID: String) {
        show(projectID: projectID)
        model.returnToProject()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: WorkspaceView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.title = "Project Workspace"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = Solanum.pageColor
        window.setContentSize(Self.size)
        window.contentMinSize = Self.minimum
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.close()
    }
}
