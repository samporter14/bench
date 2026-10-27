// WorkspaceCommands.swift — the ways into Project Workspaces (DESIGN.md,
// Project Workspaces → Where it is): History → Project Workspace (⌥⌘P) for the
// project in the main window, History → Return to Project ▸ with each project
// that has a pin or a note, the most recently shown first, and Pin to Project
// / Unpin from Project in a reference window's ⋯. The main web view's address
// reaches here through the same watch as reopen-where-you-were, which is how
// the last conversation of each project is remembered and how the menu knows
// the project on show.
import Combine
import SwiftUI

/// A line of the Return to Project menu.
struct WorkspaceMenuItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

@MainActor
final class WorkspaceCommands: ObservableObject {
    static let shared = WorkspaceCommands()

    /// The project the main window shows, from its address; nil on the home page.
    @Published private(set) var currentProjectID: String?
    /// The Return to Project menu's lines.
    @Published private(set) var returnable: [WorkspaceMenuItem] = []

    private let visits: WorkspaceVisits
    private let store: WorkspaceStore
    private var subscription: AnyCancellable?

    init(visits: WorkspaceVisits = WorkspaceVisits(), store: WorkspaceStore = .shared) {
        self.visits = visits
        self.store = store
        subscription = store.$summaries.sink { [weak self] _ in
            // `summaries` is about to change: the list is made again once it has.
            Task { @MainActor in self?.refresh() }
        }
    }

    /// The main web view's address changed (Web/WebContainer.swift, beside `LastSession.note`). A page that isn't
    /// the daemon's says nothing about where the user is.
    func note(url: URL?, daemonPort: Int?) {
        visits.note(url: url, daemonPort: daemonPort)
        guard WebRoute.classify(url, daemonPort: daemonPort) == .daemon else { return }
        let project = WorkspaceVisits.project(url: url, daemonPort: daemonPort)
        if currentProjectID != project { currentProjectID = project }
        refresh()
    }

    var canShowWorkspace: Bool { Demo.mode == nil && currentProjectID != nil }

    /// History → Project Workspace: the panel on the main window's project.
    func showWorkspace() {
        guard Demo.mode == nil, let projectID = currentProjectID else { return }
        WorkspacePanelController.shared.show(projectID: projectID)
    }

    /// History → Return to Project ▸ a project.
    func returnTo(_ projectID: String) {
        guard Demo.mode == nil else { return }
        WorkspacePanelController.shared.returnTo(projectID: projectID)
    }

    private func refresh() {
        let items = store.returnable(recency: { [visits] in visits.recency(of: $0) })
            .map { WorkspaceMenuItem(id: $0.id, title: $0.title) }
        if items != returnable { returnable = items }
    }
}

/// The reference window's ⋯ (Reference/ReferenceWindow.swift's foot): Pin to Project or Unpin from Project, for the
/// reference's own project, and the workspace itself. What pinning came to, when it is worth a word, goes into
/// `sentence`, which the window shows over its foot for a few seconds.
struct WorkspacePinMenu: View {
    let session: SessionStatus
    /// The reply on the page, by its last row: what a pin lands on later.
    let row: Int?
    @Binding var sentence: String?
    @ObservedObject private var store = WorkspaceStore.shared

    private var canPin: Bool {
        Demo.mode == nil && WorkspaceRules.isProjectID(session.projectID) && PlanCheck.isFrameID(session.id)
    }

    var body: some View {
        let pinned = store.isPinned(session.id, in: session.projectID)
        Menu {
            if pinned {
                Button("Unpin from Project") { unpin() }
            } else {
                Button("Pin to Project") { pin() }
            }
            Divider()
            Button("Show Project Workspace") {
                WorkspacePanelController.shared.show(projectID: session.projectID, name: session.projectName)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(SolanumMoreStyle())
        .fixedSize()
        .disabled(!canPin)
        .help(pinned ? "Unpin from Project, Show Project Workspace" : "Pin to Project, Show Project Workspace")
        .accessibilityLabel("More for this reference")
    }

    private func pin() {
        let session = session, row = row
        Task { @MainActor in
            let outcome = await WorkspaceStore.shared.pin(sessionID: session.id, projectID: session.projectID, row: row,
                                                          title: session.displayTitle, projectName: session.projectName)
            say(WorkspacePinWords.sentence(for: outcome))
        }
    }

    private func unpin() {
        let session = session
        Task { @MainActor in
            await WorkspaceStore.shared.unpin(sessionID: session.id, projectID: session.projectID)
            say(nil)
        }
    }

    private func say(_ words: String?) {
        sentence = words
        guard let words else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if sentence == words { sentence = nil }
        }
    }
}

enum WorkspacePinWords {
    /// What pinning came to, in a sentence, or nil when the menu's own change says it.
    static func sentence(for outcome: WorkspaceStore.PinOutcome) -> String? {
        switch outcome {
        case .pinned, .alreadyPinned: nil
        case .full(let name):
            "\u{201C}\(WorkspaceReturnWords.short(name.isEmpty ? "This project" : name))\u{201D} has four pinned references already. Unpin one in its workspace (\u{22EF} \u{203A} Show Project Workspace), then pin this one."
        case .unsaved(let failure):
            "Pinned, but the workspace couldn\u{2019}t be saved: \(failure) Its panel has Retry."
        case .unavailable(let sentence):
            sentence
        }
    }
}
