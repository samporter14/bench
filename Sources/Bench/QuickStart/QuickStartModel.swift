// QuickStartModel.swift — what the Quick Start panel holds and does (DESIGN.md,
// Quick Start). The request in words, the files dropped on it, the project it
// starts in, whether to ask for a plan first, the recipes under it, and the
// state of the send: editing, sending, sent, or failed (with everything kept).
// ↩ starts a session in the chosen project; ⇧↩ sends the same words to the
// session in the main window instead, as a message (queued when Claude is busy).
//
// Everything outside the panel is injected (`Dependencies`): the recipes, the
// projects, the session in view, the sender, closing, and the wait before the
// panel goes once it has sent. The live ones read what the app already reads;
// the tests and `--demo quick-start` stand in for them. Nothing here sends
// anything on its own.
//
// Cancel while sending stops what is unsent and waits for the flow to say how
// far it got (QuickStart/QuickStartFlow.swift): nothing sent, and the panel
// goes; some files up, and the panel says which; or the request already out,
// which no Cancel takes back, and then the panel says what happened to it.
import Foundation

struct QuickStartProject: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// The session the main window is showing: where ⇧↩ sends.
struct ViewedSession: Equatable, Sendable {
    let id: String
    let title: String
    let projectID: String
    let projectName: String
}

/// The sentence at the foot of the panel for what ↩ (or ⇧↩) will do now.
enum QuickStartFooter {
    /// "A new session in Assay development, on your plan. ⇧↩ sends it to the
    /// session you're viewing." Always names the project, and says it runs on
    /// the plan. With ⇧ down it is the message instead, and says it waits its
    /// turn when Claude is busy. `viewed` is nil when no session is open.
    static func sentence(shift: Bool, project: QuickStartProject?, viewed: ViewedSession?) -> String {
        if shift {
            guard let viewed else { return "No session is open to send to. Let go of ⇧ to start a new one." }
            let title = viewed.title.isEmpty ? "the session you're viewing" : "\u{201C}\(viewed.title)\u{201D}"
            let place = viewed.projectName.isEmpty ? "" : " in \(viewed.projectName)"
            return "A message to \(title)\(place), on your plan. It waits its turn if Claude is busy."
        }
        let hint = viewed == nil ? "" : " ⇧↩ sends it to the session you're viewing."
        guard let project else { return "Choose a project to start in." + hint }
        return "A new session in \(project.name), on your plan." + hint
    }
}

@MainActor
final class QuickStartModel: ObservableObject {
    enum Phase: Equatable {
        case editing
        case sending
        /// It went: the sentence says how.
        case sent(String)
        /// It didn't, or part of it didn't: the sentence says what happened,
        /// and the request is still here.
        case failed(String)
    }

    struct Dependencies {
        var recipes: @MainActor () -> [Recipe]
        /// The projects of the sessions Capsid knows, the most recent first.
        var recentProjects: @MainActor () -> [QuickStartProject]
        /// Every project in the database, for "Other…". Nil when unreadable.
        var allProjects: @MainActor () async -> [QuickStartProject]?
        /// The session the main window shows now, or nil.
        var viewed: @MainActor () async -> ViewedSession?
        var sender: QuickStartSending
        /// What a dropped URL becomes (or why it can't).
        var makeFile: @MainActor (URL) -> Result<QuickStartFile, AttachmentRefusal> = { QuickStartFile.make(url: $0) }
        var close: @MainActor () -> Void
        /// How long the panel stays up once it has sent.
        var linger: Duration = .milliseconds(1600)
        var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    /// How many projects show as chips, before "Other…".
    static let chipCount = 3

    @Published var text = "" {
        didSet {
            guard text != oldValue else { return }
            if let id = appliedRecipe, recipes.first(where: { $0.id == id })?.text != text { appliedRecipe = nil }
            edited()
        }
    }
    @Published private(set) var files: [QuickStartFile] = []
    @Published private(set) var projectID: String?
    @Published var planFirst = true {
        didSet { if planFirst != oldValue { edited() } }
    }
    @Published private(set) var recipes: [Recipe] = []
    /// The recipe whose words are in the field, drawn tinted.
    @Published private(set) var appliedRecipe: String?
    /// ⇧ is down: the footer and the button say what ⇧↩ will do.
    @Published var shiftHeld = false
    @Published private(set) var phase: Phase = .editing
    /// While sending: how far the request has got. Nil until it is going.
    @Published private(set) var progress: QuickStartFlow.Progress?
    /// Cancel was pressed while sending.
    @Published private(set) var stopRequested = false
    @Published private(set) var recents: [QuickStartProject] = []
    @Published private(set) var allProjects: [QuickStartProject] = []
    @Published private(set) var viewed: ViewedSession?
    /// Bumped when the panel opens, so the field takes focus again.
    @Published private(set) var openCount = 0

    private let dependencies: Dependencies
    private var ledger = IntentLedger()
    /// A project was chosen (a chip, "Other…" or a recipe) since the panel opened.
    private var projectChosen = false
    private var sending: Task<Void, Never>?
    private var lingering: Task<Void, Never>?
    /// Whose outcome counts: a send that a newer one or `open` has replaced is
    /// let go quietly.
    private var sendToken: UUID?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: Opening

    /// The panel opens (or opens again with something new): the recipes are
    /// read afresh, the projects and the session in view looked up, and
    /// `files` and `text` filled when something handed them over. Everything
    /// the person had typed is kept when `keeping`.
    func open(files urls: [URL] = [], text start: String? = nil, keeping: Bool = false) {
        openCount += 1
        lingering?.cancel()
        // A request on its way isn't taken back by opening the panel again: it
        // finishes, and the panel keeps showing it.
        let underway = phase == .sending
        if !underway {
            sending?.cancel()
            sendToken = nil
        }
        if !keeping && !underway {
            self.text = ""
            files = []
            appliedRecipe = nil
            projectID = nil
            projectChosen = false
            planFirst = true
            phase = .editing
            progress = nil
            stopRequested = false
            ledger.sent()
        } else if case .sent = phase {
            phase = .editing
        }
        recipes = RecipeKeys.keyed(dependencies.recipes())
        recents = dependencies.recentProjects()
        if projectID == nil { projectID = recents.first?.id }
        if let start { self.text = start }
        addFiles(urls)
        Task { [weak self] in
            guard let self else { return }
            let loadAll = dependencies.allProjects, loadViewed = dependencies.viewed
            async let everything = loadAll()
            async let current = loadViewed()
            let all = await everything
            let session = await current
            if let all { allProjects = all }
            viewed = session
            // A panel nobody has chosen a project in yet starts in the project of
            // the session in view, when that is one it knows.
            if !projectChosen, let session, known(session.projectID) != nil { projectID = session.projectID }
        }
    }

    // MARK: What it holds

    /// The project of the chip row's selection, by name.
    var project: QuickStartProject? {
        guard let projectID else { return nil }
        return known(projectID)
    }

    func known(_ id: String) -> QuickStartProject? {
        recents.first { $0.id == id } ?? allProjects.first { $0.id == id }
    }

    /// The chips: the most recent projects, the chosen one among them (first,
    /// when it wasn't recent), then "Other…" apart.
    var chips: [QuickStartProject] {
        var shown = Array(recents.prefix(Self.chipCount))
        if let projectID, !shown.contains(where: { $0.id == projectID }), let chosen = known(projectID) {
            shown = [chosen] + shown.prefix(Self.chipCount - 1)
        }
        return shown
    }

    /// The rest of the projects, for the "Other…" menu: all but the chips.
    var otherProjects: [QuickStartProject] {
        let shown = Set(chips.map(\.id))
        return allProjects.filter { !shown.contains($0.id) }
    }

    /// The name a recipe's row shows for its project.
    func projectLabel(for recipe: Recipe) -> String {
        guard let id = recipe.project else { return "Any project" }
        return known(id)?.name ?? "Unknown project"
    }

    var footer: String {
        QuickStartFooter.sentence(shift: shiftHeld, project: project, viewed: viewed)
    }

    /// What the primary button says: Start, or Send while ⇧ is down, and the
    /// state of the send.
    var buttonTitle: String {
        switch phase {
        case .sending: shiftHeld ? "Sending…" : "Starting…"
        case .sent: "Done"
        default: shiftHeld ? "Send ⇧↩" : "Start ↩"
        }
    }

    /// The sentence at the foot while sending: what is going on, and, after a
    /// Cancel that came too late, that it is.
    var sendingLine: String {
        switch progress {
        case .checking?: return RemoteDecide.Sentence.checking
        case .committed? where stopRequested: return "Already sent. Waiting for Claude Science…"
        default: return shiftHeld ? "Sending…" : "Starting…"
        }
    }

    /// Whether ↩ (or ⇧↩) could send now: something to say, and somewhere to
    /// say it.
    func canSubmit(toViewed: Bool) -> Bool {
        switch phase {
        case .sending, .sent: return false
        default: break
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty else { return false }
        return toViewed ? viewed != nil : project != nil
    }

    /// For the button: what ⇧ says it does.
    var canSubmitNow: Bool { canSubmit(toViewed: shiftHeld) }

    // MARK: Editing

    func choose(_ project: QuickStartProject) {
        projectChosen = true
        guard projectID != project.id else { return }
        projectID = project.id
        edited()
    }

    func apply(_ recipe: Recipe) {
        text = recipe.text
        planFirst = recipe.planFirst
        if let id = recipe.project {
            projectID = id
            projectChosen = true
        }
        appliedRecipe = recipe.id
        phase = .editing
    }

    /// ⌘`number` in the panel.
    func applyRecipe(number: Int) {
        guard let recipe = RecipeKeys.recipe(for: number, in: recipes) else { return }
        apply(recipe)
    }

    /// Dropped files, a Service's, a Shortcut's: each that can go joins, the
    /// rest are turned away, the first of them with its sentence.
    func addFiles(_ urls: [URL]) {
        var first: String?
        for url in urls {
            if files.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { continue }
            switch dependencies.makeFile(url) {
            case .failure(let refusal):
                first = first ?? refusal.sentence
            case .success(let file):
                if let refusal = AttachmentRules.checkAdding(size: file.size, to: files) {
                    first = first ?? refusal.sentence
                } else {
                    files.append(file)
                }
            }
        }
        if let first { phase = .failed(first) } else if !urls.isEmpty { edited() }
    }

    func remove(_ file: QuickStartFile) {
        files.removeAll { $0.id == file.id }
        edited()
    }

    /// Something in the request changed: an old failure no longer says anything.
    private func edited() {
        if case .failed = phase { phase = .editing }
    }

    // MARK: Sending

    /// The request ↩ (or ⇧↩) makes, for the flow: nil without a project (or a
    /// session in view) to send to. The intent id is the same as the last
    /// try's while nothing in the request changed.
    func request(toViewed: Bool) -> QuickStartFlow.Request? {
        var request: QuickStartFlow.Request
        if toViewed {
            guard let viewed else { return nil }
            request = .init(target: .session(id: viewed.id), projectName: viewed.projectName, text: text, files: files,
                            planFirst: false, intentID: "")
        } else {
            guard let project else { return nil }
            request = .init(target: .newSession(project: project.id), projectName: project.name, text: text, files: files,
                            planFirst: planFirst, intentID: "")
        }
        request.intentID = ledger.id(for: request.signature)
        return request
    }

    /// ↩ starts a session; ⇧↩ sends to the session in view.
    func submit(toViewed: Bool) {
        guard canSubmit(toViewed: toViewed), let request = request(toViewed: toViewed) else { return }
        phase = .sending
        progress = nil
        stopRequested = false
        let token = UUID()
        sendToken = token
        sending = Task { [weak self] in
            guard let self else { return }
            let outcome = await dependencies.sender.perform(request, progress: { [weak self] stage in
                guard let self, self.sendToken == token else { return }
                self.progress = stage
            })
            guard sendToken == token else { return }
            finish(outcome)
        }
    }

    func submit() { submit(toViewed: shiftHeld) }

    private func finish(_ outcome: QuickStartFlow.Outcome) {
        sendToken = nil
        progress = nil
        switch outcome {
        case .failed(let sentence):
            if stopRequested && outcome.isCleanCancel {
                // Cancel, before anything was sent: nothing to say, and the panel goes.
                stopRequested = false
                phase = .editing
                dependencies.close()
            } else {
                phase = .failed(sentence)
            }
        case .started(_, let sentence), .sent(_, let sentence):
            // It went, whatever Cancel said: the panel says what happened.
            phase = .sent(sentence)
            ledger.sent()
            lingering = Task { [weak self] in
                guard let self else { return }
                await dependencies.sleep(dependencies.linger)
                guard !Task.isCancelled else { return }
                dependencies.close()
            }
        }
        stopRequested = false
    }

    /// Cancel and Esc. Not sending, the panel goes. Sending, what is unsent is
    /// stopped and the flow says how far it got (`finish`); once the request is
    /// out, there is nothing to stop, and the panel says so.
    func cancel() {
        lingering?.cancel()
        guard phase == .sending else {
            sending?.cancel()
            sendToken = nil
            dependencies.close()
            return
        }
        stopRequested = true
        if progress == nil { sending?.cancel() }
    }
}

// MARK: Live

extension QuickStartModel.Dependencies {
    /// What the app reads: the recipes in settings, the projects of the Lab's
    /// recent sessions, every project from the database, and the session the
    /// main window shows.
    @MainActor
    static func live(sender: QuickStartSending = QuickStartFlow.shared, close: @escaping @MainActor () -> Void) -> Self {
        Self(recipes: { RecipeStore().recipes },
             recentProjects: { QuickStartProjects.recent(from: LabModel.shared.sessions) },
             allProjects: { await QuickStartProjects.fromDatabase() },
             viewed: { await QuickStartProjects.viewedSession() },
             sender: sender, close: close)
    }
}

enum QuickStartProjects {
    /// The projects of these sessions, most recently active first, one each.
    static func recent(from sessions: [SessionStatus]) -> [QuickStartProject] {
        var seen = Set<String>()
        var out: [QuickStartProject] = []
        for session in sessions.sorted(by: { $0.updatedAt > $1.updatedAt })
        where !session.projectID.isEmpty && BrowseSQL.isProjectID(session.projectID) && !session.projectName.isEmpty {
            if seen.insert(session.projectID).inserted { out.append(QuickStartProject(id: session.projectID, name: session.projectName)) }
        }
        return out
    }

    /// Every project, newest activity first, from the database Capsid already
    /// reads (off the main thread); nil when it can't be read.
    @MainActor
    static func fromDatabase() async -> [QuickStartProject]? {
        guard Demo.mode == nil else { return nil }
        let untitled = BrowseAPI.untitledProject
        return await Task.detached(priority: .utility) { () -> [QuickStartProject]? in
            guard let db = resolveDatabase(), let rows = try? fetchProjects(db: db) else { return nil }
            return rows.map { QuickStartProject(id: $0.id, name: $0.name.isEmpty ? untitled : $0.name) }
        }.value
    }

    /// The session in the main window: the page's own address, named from the
    /// Lab's sessions or, for an older one, the database.
    @MainActor
    static func viewedSession() async -> ViewedSession? {
        guard Demo.mode == nil, let id = WebContainer.shared.currentFrameID, PlanCheck.isFrameID(id) else { return nil }
        if let known = LabModel.shared.sessions.first(where: { $0.id == id }) {
            return ViewedSession(id: id, title: known.displayTitle, projectID: known.projectID, projectName: known.projectName)
        }
        guard let found = await RemoteBrowser.lookUp(id) else { return nil }
        return ViewedSession(id: id, title: found.displayTitle, projectID: found.projectID, projectName: found.projectName)
    }
}
