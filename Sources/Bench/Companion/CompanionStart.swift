// CompanionStart.swift — the home popover's "Start a session…" field
// (DESIGN.md, Menu bar home): the words, the project they start in (a small
// pill in the field), and the send. ↩ starts the session from the popover,
// through Quick Start's own path (`QuickStartFlow`: its checks, its bounded
// writes, an intent id kept across a retry of the same request), so the two
// can't differ in what they send or what they say. ⌘↩ hands the words and the
// project to the Quick Start panel instead, for files and recipes.
//
// The projects are Quick Start's: the projects of the sessions Capsid knows,
// the most recent first (`QuickStartProjects.recent`), so the project you last
// worked in, or last started a session in, is the one the pill shows; then the
// rest from the database Capsid already reads, once per opening. "Ask for a
// plan first" is what Quick Start's box last said (on until it has been
// unticked there). Nothing is kept on disk.
//
// It reads nothing while the popover is closed. A send in flight when the
// popover closes goes on, and its outcome is there at the next opening; any
// other opening starts clean, as Quick Start's does.
import Foundation

@MainActor
final class CompanionStart: ObservableObject {
    enum Phase: Equatable {
        case editing
        case sending
        /// It went: the session (nil when the flow didn't name it) and "Started in Assay development."
        case started(sessionID: String?, projectID: String, sentence: String)
        /// It didn't, or Capsid can't tell: the flow's sentence. The words stay in the field.
        case failed(String)
    }

    /// The line under the field.
    enum Line: Equatable {
        /// While something is typed: what ↩ does.
        case hint(String)
        /// While it goes: "Starting…", or "Not sure that went through. Checking…".
        case sending(String)
        case started(String)
        case failed(String)
    }

    /// What ⌘↩ hands Quick Start.
    struct HandOff: Equatable {
        let text: String
        let project: QuickStartProject?
        let planFirst: Bool
    }

    struct Dependencies {
        /// The projects of the sessions Capsid knows, the most recent first (Quick Start's).
        var recentProjects: @MainActor () -> [QuickStartProject]
        /// Every project, from the database; nil when it can't be read.
        var allProjects: @MainActor () async -> [QuickStartProject]?
        /// Quick Start's "Ask for a plan first", as it last had it.
        var planFirst: @MainActor () -> Bool
        var sender: QuickStartSending

        /// Nothing to start in and nothing sent: a test's or a snapshot's default.
        @MainActor
        static var none: Dependencies {
            Dependencies(recentProjects: { [] }, allProjects: { nil }, planFirst: { true }, sender: RefusingSender())
        }

        /// What the app holds: the Lab's sessions, the database, Quick Start's box and its flow.
        @MainActor
        static func live() -> Dependencies {
            Dependencies(recentProjects: { QuickStartProjects.recent(from: LabModel.shared.sessions) },
                         allProjects: { await QuickStartProjects.fromDatabase() },
                         planFirst: { QuickStartController.shared.model?.planFirst ?? true },
                         sender: QuickStartFlow.shared)
        }
    }

    /// How many projects the menu lists before "Other Projects", as Quick Start shows that many chips.
    static let menuCount = QuickStartModel.chipCount

    @Published var text = "" {
        didSet {
            guard text != oldValue else { return }
            // Typing again: what the last send said no longer stands.
            switch phase {
            case .failed, .started: phase = .editing
            default: break
            }
        }
    }
    @Published private(set) var projectID: String?
    @Published private(set) var recents: [QuickStartProject] = []
    @Published private(set) var allProjects: [QuickStartProject] = []
    @Published private(set) var planFirst = true
    @Published private(set) var phase: Phase = .editing
    @Published private(set) var progress: QuickStartFlow.Progress?
    @Published private(set) var isOpen = false

    private let dependencies: Dependencies
    private var ledger = IntentLedger()
    /// The pill was used since the popover opened.
    private var projectChosen = false
    private var loading: Task<Void, Never>?
    private var sending: Task<Void, Never>?
    /// A send that ended while the popover was closed: its outcome hasn't been seen.
    private var outcomeUnseen = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: Opening and closing

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let underway = phase == .sending
        if !underway && !outcomeUnseen {
            // A fresh start, as Quick Start's is.
            text = ""
            phase = .editing
            progress = nil
            projectChosen = false
            projectID = nil
            ledger.sent()
        }
        outcomeUnseen = false
        recents = dependencies.recentProjects()
        if !underway { planFirst = dependencies.planFirst() }
        if projectID == nil || known(projectID ?? "") == nil { projectID = recents.first?.id }
        let load = dependencies.allProjects
        loading = Task { [weak self] in
            let all = await load()
            guard let self, self.isOpen, !Task.isCancelled, let all else { return }
            self.allProjects = all
            if self.projectID == nil { self.projectID = all.first?.id }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        loading?.cancel()
        loading = nil
    }

    // MARK: The project

    var project: QuickStartProject? { projectID.flatMap(known) }

    func known(_ id: String) -> QuickStartProject? {
        recents.first { $0.id == id } ?? allProjects.first { $0.id == id }
    }

    /// The menu's first group: the most recent projects, and the chosen one first when it isn't among them
    /// (Quick Start's chips). With no session to go by, the database's first.
    var menuProjects: [QuickStartProject] {
        let base = recents.isEmpty ? allProjects : recents
        var shown = Array(base.prefix(Self.menuCount))
        if let project, !shown.contains(where: { $0.id == project.id }) {
            shown = [project] + shown.prefix(Self.menuCount - 1)
        }
        return shown
    }

    /// "Other Projects": every other project, recent ones first, then the database's order.
    var otherProjects: [QuickStartProject] {
        var seen = Set(menuProjects.map(\.id))
        return (recents + allProjects).filter { seen.insert($0.id).inserted }
    }

    var pillTitle: String { project?.name ?? CompanionText.chooseProject }

    func choose(_ project: QuickStartProject) {
        guard !inFlight else { return }
        projectChosen = true
        guard projectID != project.id else { return }
        projectID = project.id
        if case .failed = phase { phase = .editing }
    }

    func choose(id: String) {
        if let project = known(id) { choose(project) }
    }

    // MARK: Sending

    /// A request is on its way: nothing in the field changes and ↩ sends nothing a second time.
    var inFlight: Bool { phase == .sending || sending != nil }

    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The request ↩ makes: a new session in the pill's project, with Quick Start's plan setting. The intent id
    /// is the last try's while nothing in it changed, so a retry after a lost answer doesn't start it twice.
    func request() -> QuickStartFlow.Request? {
        guard let project else { return nil }
        var request = QuickStartFlow.Request(target: .newSession(project: project.id), projectName: project.name,
                                             text: text, files: [], planFirst: planFirst, intentID: "")
        request.intentID = ledger.id(for: request.signature)
        return request
    }

    /// ↩: starts the session. Nothing happens with no words, no project, or a send already on its way.
    @discardableResult
    func start() -> Bool {
        guard !inFlight, hasText, let request = request() else { return false }
        phase = .sending
        progress = nil
        let sender = dependencies.sender
        sending = Task { [weak self] in
            let outcome = await sender.perform(request, progress: { [weak self] stage in
                guard let self, self.phase == .sending else { return }
                self.progress = stage
            })
            self?.finish(outcome, project: request)
        }
        return true
    }

    private func finish(_ outcome: QuickStartFlow.Outcome, project request: QuickStartFlow.Request) {
        sending = nil
        progress = nil
        outcomeUnseen = !isOpen
        guard case .newSession(let projectID) = request.target else { return }
        switch outcome {
        case .started(let id, let sentence):
            ledger.sent()
            // The words went: the field is clear for the next one (before the phase, which typing resets).
            text = ""
            phase = .started(sessionID: id, projectID: projectID, sentence: sentence)
        case .sent(_, let sentence):
            ledger.sent()
            text = ""
            phase = .started(sessionID: nil, projectID: projectID, sentence: sentence)
        case .failed(let sentence):
            phase = .failed(sentence)
        }
    }

    /// What a Return in the field does.
    enum ReturnAction: Equatable {
        /// Start the session from the popover.
        case start
        /// Open Quick Start with the words and the project.
        case quickStart
    }

    /// ↩ starts what is typed; ⌘↩ opens Quick Start, and so does ↩ with nothing typed (as the field always did).
    static func onReturn(command: Bool, hasText: Bool) -> ReturnAction {
        command || !hasText ? .quickStart : .start
    }

    /// ⌘↩ (and ↩ on an empty field): the words, the project and the plan setting, for Quick Start. Nil while
    /// a send is on its way.
    func handOff() -> HandOff? {
        guard !inFlight else { return nil }
        return HandOff(text: text, project: project, planFirst: planFirst)
    }

    /// The line under the field, or nil for none (nothing typed, nothing sent).
    var line: Line? {
        switch phase {
        case .sending:
            return .sending(progress == .checking ? RemoteDecide.Sentence.checking : CompanionText.starting)
        case .started(_, _, let sentence):
            return .started(sentence)
        case .failed(let sentence):
            return .failed(sentence)
        case .editing:
            return hasText ? .hint(CompanionText.startHint(planFirst: planFirst)) : nil
        }
    }

    /// The session the last send started, for Open.
    var started: (sessionID: String, projectID: String)? {
        if case .started(let id?, let project, _) = phase { (id, project) } else { nil }
    }

    // MARK: Demos and pictures

    /// Puts the field in a state without sending anything. Only demos and snapshots call it.
    func showDemo(text: String, phase: Phase, progress: QuickStartFlow.Progress? = nil) {
        self.text = text
        self.phase = phase
        self.progress = progress
    }
}

/// A sender that sends nothing and says so: the default where no flow is given.
@MainActor
final class RefusingSender: QuickStartSending {
    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome {
        .failed(sentence: QuickStartFlow.Sentence.notReady)
    }
}

/// The `bench://` address of a session (`KeepRules.deepLink`'s), from its ids alone: `Router` opens it.
enum CompanionLinks {
    static func session(projectID: String, sessionID: String) -> String {
        "bench://session?project=\(projectID)&frame=\(sessionID)"
    }
}
