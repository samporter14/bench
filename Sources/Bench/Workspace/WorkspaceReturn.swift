// WorkspaceReturn.swift — Return to Project (DESIGN.md, Project Workspaces →
// Return to Project). One explicit action brings a project's things back
// together: the one main web view goes to the project's last conversation when
// the database still has it; each pinned reference opens (or the window already
// open is used) at its own reply; and the Shelf shows the project, by its id,
// when it has something on it. The three parts run side by side and none waits
// on another, so one that fails never holds the rest. What couldn't come back
// is a short list for the panel. Return only reads and opens: it never makes
// another web view, sends a message, starts a session, approves a plan or
// asks another model. Every part checks, after each wait, that it is still the
// latest Return: a Return to A followed by one to B leaves nothing of A's to
// land afterwards. The effects are injected, so the tests run it on fakes.
import Foundation

/// A session, as the database says when Return asks.
enum WorkspaceSessionLook: Equatable, Sendable {
    case known(title: String, projectName: String)
    /// Not in the database, or not in this project any more.
    case gone
    /// The database couldn't be read.
    case unreadable
}

/// How a pinned reference's window ended up.
enum WorkspacePinOutcome: Equatable, Sendable {
    /// On the pinned reply (or, for a pin with no reply, the newest).
    case landed
    /// The conversation is there, but the pinned reply isn't: the window says so too.
    case replyMissing
    /// The reply is further back than one look reads.
    case tooFar
    case failed(String)
    /// Still reading back when Return stopped waiting: it carries on in its window.
    case stillReading
}

/// One thing that couldn't come back, as the panel lists it.
struct WorkspaceReturnProblem: Equatable, Sendable, Identifiable {
    /// Its place in the list: the conversation, then the pins in their order, then the Shelf.
    let order: Int
    let sentence: String
    var id: Int { order }
}

/// What the last Return to a project came to.
struct WorkspaceReturnSummary: Equatable, Sendable {
    let projectID: String
    let problems: [WorkspaceReturnProblem]

    /// The panel's line: nothing when everything came back.
    var headline: String? {
        problems.isEmpty ? nil : problems.count == 1 ? "One thing couldn\u{2019}t come back:" : "Some things couldn\u{2019}t come back:"
    }
}

/// What Return acts through. Every piece reads or opens; none writes to Claude Science.
struct WorkspaceReturnDependencies {
    /// Whether the database has the session in this project, read only, off the main actor.
    var look: @Sendable (_ sessionID: String, _ projectID: String) async -> WorkspaceSessionLook
    /// Shows the main window and loads the session in its one web view. False when Capsid can't show it.
    var navigate: @MainActor (_ route: LastSession.Route) -> Bool
    /// Opens the pinned session's reference window at its reply, or brings the open one there, and says how it went.
    var openReference: @MainActor (_ pin: WorkspacePin, _ projectName: String) async -> WorkspacePinOutcome
    /// Whether the Shelf holds anything of this project, by its id, once the kept folders have been read.
    var shelfHas: @MainActor (_ projectID: String) async -> Bool
    /// Shows the Shelf on this project, by its id.
    var showShelf: @MainActor (_ projectID: String) -> Void
}

/// What a Return brings back: the ids as the workspace and the visits have them.
struct WorkspaceReturnPlan: Equatable, Sendable {
    let projectID: String
    let projectName: String
    /// The session last shown in the project, if one was.
    let lastSession: String?
    let pins: [WorkspacePin]
}

@MainActor
final class WorkspaceReturner: ObservableObject {
    /// The project a Return is bringing back, while it runs.
    @Published private(set) var returning: String?
    /// The last Return's summary, by project.
    @Published private(set) var summaries: [String: WorkspaceReturnSummary] = [:]

    private let dependencies: WorkspaceReturnDependencies
    /// Bumped by every Return: a part that finds it moved after a wait does nothing more.
    private(set) var generation = 0
    private var task: Task<Void, Never>?

    init(dependencies: WorkspaceReturnDependencies) {
        self.dependencies = dependencies
    }

    /// Brings the plan's project back. A Return already running stops where it is (its later steps see the new
    /// generation and do nothing). The task is the whole Return, for whoever waits on it.
    @discardableResult
    func bringBack(_ plan: WorkspaceReturnPlan) -> Task<Void, Never> {
        generation += 1
        let generation = generation
        task?.cancel()
        returning = plan.projectID
        summaries[plan.projectID] = nil
        let task = Task { [weak self] in
            guard let self else { return }
            let parts = await Self.waitForAll([
                Task { @MainActor in await self.conversation(plan, generation) },
                Task { @MainActor in await self.references(plan, generation) },
                Task { @MainActor in await self.shelf(plan, generation) },
            ])
            let problems = parts.flatMap { $0 }
            guard self.isCurrent(generation) else { return }
            self.summaries[plan.projectID] = WorkspaceReturnSummary(projectID: plan.projectID,
                                                                     problems: problems.sorted { $0.order < $1.order })
            self.returning = nil
        }
        self.task = task
        return task
    }

    /// Forgets a project's summary (the panel was cleared, or shown again later).
    func dismissSummary(for projectID: String) {
        summaries[projectID] = nil
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && !Task.isCancelled
    }

    /// Waits for each task, which runs side by side with the others, and gives their values in order. Cancelling the
    /// task that waits cancels them all, so a Return that is let go leaves nothing waiting behind it.
    private static func waitForAll<Value: Sendable>(_ tasks: [Task<Value, Never>]) async -> [Value] {
        await withTaskCancellationHandler {
            var values: [Value] = []
            for task in tasks { values.append(await task.value) }
            return values
        } onCancel: {
            for task in tasks { task.cancel() }
        }
    }

    // MARK: The parts

    /// The main web view, to the last conversation, if the database still has it there.
    private func conversation(_ plan: WorkspaceReturnPlan, _ generation: Int) async -> [WorkspaceReturnProblem] {
        guard let frame = plan.lastSession else { return [] }
        let look = await dependencies.look(frame, plan.projectID)
        guard isCurrent(generation) else { return [] }
        switch look {
        case .known:
            guard dependencies.navigate(LastSession.Route(projectID: plan.projectID, frameID: frame)) else {
                return [.init(order: 0, sentence: WorkspaceReturnWords.cantShow)]
            }
            return []
        case .gone:
            return [.init(order: 0, sentence: WorkspaceReturnWords.conversationGone)]
        case .unreadable:
            return [.init(order: 0, sentence: WorkspaceReturnWords.databaseUnreadable)]
        }
    }

    /// Each pinned reference: looked up first (a session that has gone is said, and no window opens on it), then
    /// opened, all at once, each landing on its reply in its own window.
    private func references(_ plan: WorkspaceReturnPlan, _ generation: Int) async -> [WorkspaceReturnProblem] {
        var problems: [WorkspaceReturnProblem] = []
        var opening: [(order: Int, pin: WorkspacePin)] = []
        for (index, pin) in plan.pins.enumerated() {
            let look = await dependencies.look(pin.sessionID, plan.projectID)
            guard isCurrent(generation) else { return [] }
            let order = 1 + index
            switch look {
            case .known(let title, _):
                var pin = pin
                let clean = WorkspaceRules.clean(title)
                if !clean.isEmpty { pin.title = clean }
                opening.append((order, pin))
            case .gone:
                problems.append(.init(order: order, sentence: WorkspaceReturnWords.pinGone(pin.title)))
            case .unreadable:
                problems.append(.init(order: order, sentence: WorkspaceReturnWords.pinUnreadable(pin.title)))
            }
        }
        let outcomes = await Self.waitForAll(opening.map { order, pin in
            Task { @MainActor () -> WorkspaceReturnProblem? in
                // A newer Return began while this one was looking: this window isn't opened.
                guard self.isCurrent(generation) else { return nil }
                let outcome = await self.dependencies.openReference(pin, plan.projectName)
                return WorkspaceReturnWords.sentence(for: outcome, title: pin.title).map { .init(order: order, sentence: $0) }
            }
        })
        guard isCurrent(generation) else { return [] }
        return problems + outcomes.compactMap { $0 }
    }

    /// The Shelf, on the project, when it has something of the project's; otherwise it is left as it is.
    private func shelf(_ plan: WorkspaceReturnPlan, _ generation: Int) async -> [WorkspaceReturnProblem] {
        let has = await dependencies.shelfHas(plan.projectID)
        guard isCurrent(generation), has else { return [] }
        dependencies.showShelf(plan.projectID)
        return []
    }
}

/// What the summary says. Titles are quoted as they were kept; nothing here reaches a log.
enum WorkspaceReturnWords {
    static let conversationGone = "Your last conversation here is gone."
    static let databaseUnreadable = "Claude Science\u{2019}s sessions couldn\u{2019}t be read."
    static let cantShow = "Capsid can\u{2019}t show conversations right now."

    static func pinGone(_ title: String) -> String {
        "\u{201C}\(short(title))\u{201D} is gone from Claude Science."
    }

    static func pinUnreadable(_ title: String) -> String {
        "\u{201C}\(short(title))\u{201D} couldn\u{2019}t be looked up."
    }

    static func sentence(for outcome: WorkspacePinOutcome, title: String) -> String? {
        switch outcome {
        case .landed: nil
        case .replyMissing: "The pinned reply in \u{201C}\(short(title))\u{201D} isn\u{2019}t there any more."
        case .tooFar: "The pinned reply in \u{201C}\(short(title))\u{201D} is too far back to reach at once."
        case .failed: "\u{201C}\(short(title))\u{201D} couldn\u{2019}t be read."
        case .stillReading: "\u{201C}\(short(title))\u{201D} is still finding its reply."
        }
    }

    /// A title in a sentence: 40 characters at most.
    static func short(_ title: String) -> String {
        let title = title.isEmpty ? "Untitled" : title
        return title.count > 40 ? String(title.prefix(39)) + "\u{2026}" : title
    }
}
