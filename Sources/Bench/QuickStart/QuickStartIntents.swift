// QuickStartIntents.swift — Capsid in Shortcuts (DESIGN.md, Quick Start →
// Shortcuts). App Intents, with the Focus filter's precedent
// (App/PresentingFocusFilter.swift): Start Session, Run Recipe, Send Message,
// Sessions Needing Me, Open Session and Set Quiet While Presenting, with
// Project, Session and Recipe as entities Shortcuts can offer and look up.
//
// The entities are asked for from the database when Shortcuts asks and are
// never kept anywhere: not on disk, and not in memory past the answer. The
// recipes are the person's own settings.
//
// An intent that starts a session or sends a message does what Quick Start's
// Start does (QuickStartFlow), and asks first: `requestConfirmation`, unless
// Settings → General → Shortcuts → "Let Shortcuts start sessions and send
// messages" is on (`SettingsKey.shortcutsMayAct`, off by default). The ones
// that only read, open a session or set Quiet While Presenting don't ask.
//
// SwiftPM does not extract App Intents metadata the way Xcode does: System
// Settings and Shortcuts see these only if Scripts/appintents-metadata.sh has
// put Metadata.appintents into the app bundle (Scripts/build-app.sh does).
import AppIntents
import Foundation

// MARK: The database, asked for each time

/// Where the entities come from: the live database reads, or a test's.
struct IntentDatabase: Sendable {
    var projects: @Sendable () async -> [QuickStartProject]
    /// Sessions by name (every word in the title or project), newest first;
    /// no words, the recent ones.
    var sessions: @Sendable (_ words: [String]) async -> [IntentSession]
    var session: @Sendable (_ id: String) async -> IntentSession?

    static let live = IntentDatabase(
        projects: { await QuickStartProjects.fromDatabaseOffMain() ?? [] },
        sessions: { words in
            await Task.detached(priority: .userInitiated) { () -> [IntentSession] in
                guard let db = resolveDatabase() else { return [] }
                let rows = words.isEmpty ? ((try? fetchRecentSessions(db: db, after: nil)) ?? nil) ?? []
                    : (try? fetchSessionsNamed(db: db, words: words, limit: 30)) ?? []
                return rows.prefix(30).map(IntentSession.init)
            }.value
        },
        session: { id in
            await Task.detached(priority: .userInitiated) { () -> IntentSession? in
                guard PlanCheck.isFrameID(id), let db = resolveDatabase() else { return nil }
                return (try? fetchSession(db: db, id: id)).flatMap { $0 }.map(IntentSession.init)
            }.value
        })

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replacement: IntentDatabase?

    /// What the entities read: the live database, unless a test put its own here.
    static var current: IntentDatabase {
        get { lock.lock(); defer { lock.unlock() }; return replacement ?? .live }
        set { lock.lock(); replacement = newValue; lock.unlock() }
    }

    /// Back to the live reads.
    static func reset() {
        lock.lock()
        replacement = nil
        lock.unlock()
    }
}

/// A session as an entity needs it: no more than its row says.
struct IntentSession: Equatable, Sendable {
    let id: String
    let title: String
    let projectID: String
    let projectName: String
    let state: String

    init(id: String, title: String, projectID: String, projectName: String, state: String) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.projectName = projectName
        self.state = state
    }

    init(_ row: BrowseRow) {
        self.init(id: row.id, title: row.name, projectID: row.projectID, projectName: row.projectName,
                  state: SessionState(frameStatus: row.status).label)
    }
}

extension QuickStartProjects {
    /// `fromDatabase`, for a caller that isn't on the main actor.
    static func fromDatabaseOffMain() async -> [QuickStartProject]? {
        await Task.detached(priority: .utility) { () -> [QuickStartProject]? in
            guard let db = resolveDatabase(), let rows = try? fetchProjects(db: db) else { return nil }
            return rows.map { QuickStartProject(id: $0.id, name: $0.name.isEmpty ? "Untitled project" : $0.name) }
        }.value
    }
}

// MARK: Entities

struct ProjectEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Project")
    static let defaultQuery = ProjectEntityQuery()

    let id: String
    @Property(title: "Name")
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ project: QuickStartProject) {
        self.init(id: project.id, name: project.name)
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProjectEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let all = await IntentDatabase.current.projects()
        return identifiers.compactMap { id in all.first { $0.id == id }.map(ProjectEntity.init) }
    }

    func entities(matching string: String) async throws -> [ProjectEntity] {
        let words = string.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        let all = await IntentDatabase.current.projects()
        return all.filter { project in words.allSatisfy { project.name.lowercased().contains($0) } }.map(ProjectEntity.init)
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        await IntentDatabase.current.projects().prefix(25).map(ProjectEntity.init)
    }
}

struct SessionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Session")
    static let defaultQuery = SessionEntityQuery()

    let id: String
    @Property(title: "Title")
    var title: String
    @Property(title: "Project")
    var projectName: String
    @Property(title: "State")
    var state: String
    let projectID: String

    init(id: String, title: String, projectID: String, projectName: String, state: String) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.projectName = projectName
        self.state = state
    }

    init(_ session: IntentSession) {
        self.init(id: session.id, title: session.title, projectID: session.projectID,
                  projectName: session.projectName, state: session.state)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title.isEmpty ? projectName : title)", subtitle: "\(projectName) · \(state)")
    }
}

struct SessionEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [SessionEntity] {
        var found: [SessionEntity] = []
        for id in identifiers {
            if let session = await IntentDatabase.current.session(id) { found.append(SessionEntity(session)) }
        }
        return found
    }

    func entities(matching string: String) async throws -> [SessionEntity] {
        // As Quick Open looks sessions up: a few words, each cut short, and not a single letter.
        let words = string.split(whereSeparator: \.isWhitespace).prefix(BrowseSQL.searchWordLimit)
            .map { String($0.prefix(BrowseSQL.searchWordLength)) }
        guard words.reduce(0, { $0 + $1.count }) >= 2 else { return [] }
        return await IntentDatabase.current.sessions(words).map(SessionEntity.init)
    }

    func suggestedEntities() async throws -> [SessionEntity] {
        await IntentDatabase.current.sessions([]).map(SessionEntity.init)
    }
}

struct RecipeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recipe")
    static let defaultQuery = RecipeEntityQuery()

    let id: String
    @Property(title: "Name")
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ recipe: Recipe) {
        self.init(id: recipe.id, name: recipe.name)
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct RecipeEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [String]) async throws -> [RecipeEntity] {
        let all = RecipeStore().recipes
        return identifiers.compactMap { id in all.first { $0.id == id }.map(RecipeEntity.init) }
    }

    func entities(matching string: String) async throws -> [RecipeEntity] {
        let words = string.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        return RecipeStore().recipes.filter { recipe in words.allSatisfy { recipe.name.lowercased().contains($0) } }
            .map(RecipeEntity.init)
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        RecipeStore().recipes.map(RecipeEntity.init)
    }
}

// MARK: Asking first

/// Whether an intent that acts may go straight through, and the words it asks
/// with when it may not. The one place `SettingsKey.shortcutsMayAct` is read.
struct ShortcutsGate: Sendable {
    var mayAct: @Sendable () -> Bool

    init(mayAct: @escaping @Sendable () -> Bool = { UserDefaults.standard.bool(forKey: SettingsKey.shortcutsMayAct) }) {
        self.mayAct = mayAct
    }

    /// Asks first (`confirm`, which throws when the person says no) unless the
    /// switch is on, then does `action`. When `confirm` throws, `action` never runs.
    @MainActor
    func run<T>(confirm: () async throws -> Void, action: () async throws -> T) async throws -> T {
        if !mayAct() { try await confirm() }
        return try await action()
    }

    /// "Start a session in Assay development: “QC this plate-reader export…”?"
    static func startQuestion(project: String, text: String, files: Int) -> String {
        "Start a session in \(project)\(summary(text: text, files: files))?"
    }

    /// "Send a message to “Plate reader QC”: “Add the second plate…”?"
    static func sendQuestion(session: String, text: String, files: Int) -> String {
        "Send a message to \u{201C}\(session)\u{201D}\(summary(text: text, files: files))?"
    }

    private static func summary(text: String, files: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.count > 90 ? String(trimmed.prefix(90)) + "…" : trimmed
        var out = words.isEmpty ? "" : ": \u{201C}\(words)\u{201D}"
        if files > 0 { out += (words.isEmpty ? ": " : ", with ") + (files == 1 ? "1 file" : "\(files) files") }
        return out
    }
}

/// What an intent says when it can't do its work: Shortcuts shows the sentence.
struct ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    let sentence: String
    var localizedStringResource: LocalizedStringResource { "\(sentence)" }
}

// MARK: Doing it

/// What the intents do beyond the asking: the same flow as Quick Start's
/// Start, with files given by Shortcuts, and the wait for Claude Science's
/// page when Shortcuts launched Capsid just now.
@MainActor
enum ShortcutsActions {
    /// The flow's sender: the live one, or a test's.
    static var sender: QuickStartSending = QuickStartFlow.shared
    /// Waits for the page to be ready, at most this long.
    static let readyWait: Duration = .seconds(20)
    static var isReady: @MainActor () -> Bool = { Demo.mode == nil && WebContainer.shared.status == .ready }
    static var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// Capsid was just launched by Shortcuts: the page takes a moment.
    static func waitUntilReady() async {
        var waited = Duration.zero
        while !isReady(), waited < readyWait {
            await sleep(.milliseconds(500))
            waited += .milliseconds(500)
        }
    }

    /// Start a session. The outcome, or the sentence it failed with.
    static func start(project: QuickStartProject, text: String, files: [QuickStartFile], planFirst: Bool) async throws -> SessionEntity {
        await waitUntilReady()
        let request = QuickStartFlow.Request(target: .newSession(project: project.id), projectName: project.name, text: text,
                                             files: files, planFirst: planFirst, intentID: IntentLedger.newID())
        switch await sender.perform(request) {
        case .started(let id, _):
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return SessionEntity(id: id, title: String(title.prefix(50)), projectID: project.id, projectName: project.name,
                                 state: SessionState.running.label)
        case .sent: throw ShortcutError(sentence: QuickStartFlow.Sentence.notStarted)
        case .failed(let sentence): throw ShortcutError(sentence: sentence)
        }
    }

    /// Send a message to a session. The sentence it ended with, or an error.
    static func send(session: SessionEntity, text: String, files: [QuickStartFile]) async throws -> String {
        await waitUntilReady()
        let request = QuickStartFlow.Request(target: .session(id: session.id), projectName: session.projectName, text: text,
                                             files: files, planFirst: false, intentID: IntentLedger.newID())
        switch await sender.perform(request) {
        case .sent(_, let sentence), .started(_, let sentence): return sentence
        case .failed(let sentence): throw ShortcutError(sentence: sentence)
        }
    }

    /// Files Shortcuts hands over, as Quick Start's: a file with a place on
    /// disk is read there; one with only bytes is written to a temporary
    /// folder first. The folder is `cleanup`'s to delete. A file Quick Start
    /// would turn away is an error naming it.
    static func files(from given: [IntentFile]?) throws -> (files: [QuickStartFile], cleanup: @Sendable () -> Void) {
        guard let given, !given.isEmpty else { return ([], {}) }
        var made: [QuickStartFile] = []
        var folder: URL?
        for item in given {
            let url: URL
            if let place = item.fileURL {
                url = place
            } else {
                let directory = folder ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("capsid-shortcut-\(UUID().uuidString)", isDirectory: true)
                folder = directory
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                url = directory.appendingPathComponent(AttachmentRules.safeName(item.filename))
                try item.data.write(to: url)
            }
            switch QuickStartFile.make(url: url) {
            case .success(let file):
                if let refusal = AttachmentRules.checkAdding(size: file.size, to: made) { throw ShortcutError(sentence: refusal.sentence) }
                made.append(file)
            case .failure(let refusal):
                throw ShortcutError(sentence: refusal.sentence)
            }
        }
        let cleanup: @Sendable () -> Void = { [folder] in if let folder { try? FileManager.default.removeItem(at: folder) } }
        return (made, cleanup)
    }

    /// The project a recipe with none starts in: the one chosen in the
    /// shortcut, else the Lab's most recent.
    static func fallbackProject(chosen: ProjectEntity?) throws -> QuickStartProject {
        if let chosen { return QuickStartProject(id: chosen.id, name: chosen.name) }
        if let recent = QuickStartProjects.recent(from: LabModel.shared.sessions).first { return recent }
        throw ShortcutError(sentence: "This recipe has no project. Choose one in the shortcut.")
    }
}

// MARK: Intents

struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription(
        "Starts a session in a project, with files if you give it any. It asks first, unless Capsid's settings let Shortcuts act.",
        categoryName: "Sessions")

    @Parameter(title: "Project")
    var project: ProjectEntity

    @Parameter(title: "Request")
    var text: String

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]?

    @Parameter(title: "Ask for a plan first", default: true)
    var planFirst: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Start a session in \(\.$project): \(\.$text)") {
            \.$files
            \.$planFirst
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SessionEntity> & ProvidesDialog {
        let given = try ShortcutsActions.files(from: files)
        defer { given.cleanup() }
        let question = ShortcutsGate.startQuestion(project: project.name, text: text, files: given.files.count)
        let started = try await ShortcutsGate().run(
            confirm: { try await requestConfirmation(actionName: .start, dialog: IntentDialog(stringLiteral: question)) },
            action: {
                try await ShortcutsActions.start(project: QuickStartProject(id: project.id, name: project.name), text: text,
                                                 files: given.files, planFirst: planFirst)
            })
        return .result(value: started, dialog: IntentDialog(stringLiteral: QuickStartFlow.Sentence.started(project: project.name)))
    }
}

struct RunRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Recipe"
    static let description = IntentDescription(
        "Starts a session from one of your Quick Start recipes, with files if you give it any. It asks first, unless Capsid's settings let Shortcuts act.",
        categoryName: "Sessions")

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]?

    @Parameter(title: "Project (for a recipe with none)")
    var project: ProjectEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$recipe)") {
            \.$files
            \.$project
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SessionEntity> & ProvidesDialog {
        guard let made = RecipeStore().recipes.first(where: { $0.id == recipe.id }) else {
            throw ShortcutError(sentence: "That recipe isn't in Capsid's settings any more.")
        }
        let projects = await IntentDatabase.current.projects()
        let target: QuickStartProject
        if let id = made.project {
            guard let found = projects.first(where: { $0.id == id }) else {
                throw ShortcutError(sentence: QuickStartFlow.Sentence.projectGone)
            }
            target = found
        } else {
            target = try ShortcutsActions.fallbackProject(chosen: project)
        }
        let given = try ShortcutsActions.files(from: files)
        defer { given.cleanup() }
        let question = ShortcutsGate.startQuestion(project: target.name, text: made.text, files: given.files.count)
        let started = try await ShortcutsGate().run(
            confirm: { try await requestConfirmation(actionName: .run, dialog: IntentDialog(stringLiteral: question)) },
            action: {
                try await ShortcutsActions.start(project: target, text: made.text, files: given.files, planFirst: made.planFirst)
            })
        return .result(value: started, dialog: IntentDialog(stringLiteral: QuickStartFlow.Sentence.started(project: target.name)))
    }
}

struct SendMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Message"
    static let description = IntentDescription(
        "Sends a message to a session. It waits its turn if Claude is busy. It asks first, unless Capsid's settings let Shortcuts act.",
        categoryName: "Sessions")

    @Parameter(title: "Session")
    var session: SessionEntity

    @Parameter(title: "Message")
    var text: String

    @Parameter(title: "Files", supportedContentTypes: [.item])
    var files: [IntentFile]?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$text) to \(\.$session)") {
            \.$files
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let given = try ShortcutsActions.files(from: files)
        defer { given.cleanup() }
        let question = ShortcutsGate.sendQuestion(session: session.title.isEmpty ? session.projectName : session.title,
                                                  text: text, files: given.files.count)
        let sentence = try await ShortcutsGate().run(
            confirm: { try await requestConfirmation(actionName: .send, dialog: IntentDialog(stringLiteral: question)) },
            action: { try await ShortcutsActions.send(session: session, text: text, files: given.files) })
        return .result(dialog: IntentDialog(stringLiteral: sentence))
    }
}

struct SessionsNeedingMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Sessions Needing Me"
    static let description = IntentDescription(
        "The sessions that wait for you now, the one that has waited longest first.",
        categoryName: "Sessions")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[SessionEntity]> {
        let waiting = NeedsYou(model: .shared).asks
        return .result(value: waiting.map {
            SessionEntity(id: $0.id, title: $0.title, projectID: $0.projectID, projectName: $0.projectName,
                          state: SessionState.needsInput.label)
        })
    }
}

struct OpenSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Session"
    static let description = IntentDescription("Opens a session in Capsid's window.", categoryName: "Sessions")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Session")
    var session: SessionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$session)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard PlanCheck.isFrameID(session.id), BrowseSQL.isProjectID(session.projectID) else {
            throw ShortcutError(sentence: "Capsid can't open that session.")
        }
        Router.shared.handle(benchURL: URL(string: "bench://session?project=\(session.projectID)&frame=\(session.id)")!,
                             port: WebContainer.shared.port)
        return .result()
    }
}

struct SetQuietWhilePresentingIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Quiet While Presenting"
    static let description = IntentDescription(
        "Keeps Capsid's panel, cards, sounds and notifications out of sight, or lets them come back. The same switch as the menu's.",
        categoryName: "Capsid")

    @Parameter(title: "Quiet", default: true)
    var quiet: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set Quiet While Presenting to \(\.$quiet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // A demo is made-up data and starts nothing real.
        guard Demo.mode == nil else { return .result() }
        PresentingMode.shared.setManual(quiet)
        return .result()
    }
}

// MARK: The shortcuts Shortcuts lists

struct CapsidShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSessionIntent(), phrases: ["Start a session in \(.applicationName)"],
                    shortTitle: "Start Session", systemImageName: "plus.bubble")
        AppShortcut(intent: RunRecipeIntent(), phrases: ["Run a recipe in \(.applicationName)"],
                    shortTitle: "Run Recipe", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: SendMessageIntent(), phrases: ["Send a message in \(.applicationName)"],
                    shortTitle: "Send Message", systemImageName: "paperplane")
        AppShortcut(intent: SessionsNeedingMeIntent(), phrases: ["Which sessions need me in \(.applicationName)"],
                    shortTitle: "Sessions Needing Me", systemImageName: "bell.badge")
        AppShortcut(intent: OpenSessionIntent(), phrases: ["Open a session in \(.applicationName)"],
                    shortTitle: "Open Session", systemImageName: "arrow.up.forward.app")
        AppShortcut(intent: SetQuietWhilePresentingIntent(), phrases: ["Set quiet while presenting in \(.applicationName)"],
                    shortTitle: "Quiet While Presenting", systemImageName: "moon")
    }
}
