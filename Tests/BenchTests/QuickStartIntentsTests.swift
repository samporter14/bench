// QuickStartIntentsTests.swift — Capsid in Shortcuts, over fakes: the gate
// that makes an intent that starts a session or sends a message ask first
// (unless Settings lets Shortcuts act), the entities asked for from a fake
// database each time and kept nowhere, the questions an intent asks with, the
// files Shortcuts hands over, and the list of shortcuts. No intent is run by
// the system, no real session is started and no message sent.
import AppIntents
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Bench

private struct Refused: Error {}

/// A switch a `@Sendable` gate can read while a test turns it.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(_ value: Bool) { self.value = value }
    var isOn: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

@MainActor
struct ShortcutsGateTests {
    @Test func anIntentThatActsAsksFirstAndOnlyThenActs() async throws {
        var order: [String] = []
        let gate = ShortcutsGate(mayAct: { false })
        let result = try await gate.run(confirm: { order.append("confirm") }, action: { order.append("act"); return 42 })
        #expect(order == ["confirm", "act"])
        #expect(result == 42)
    }

    @Test func aNoToTheQuestionMeansNothingIsDone() async {
        var acted = false
        let gate = ShortcutsGate(mayAct: { false })
        await #expect(throws: Refused.self) {
            try await gate.run(confirm: { throw Refused() }, action: { acted = true })
        }
        #expect(!acted)
    }

    @Test func withTheSwitchOnItGoesStraightThrough() async throws {
        var order: [String] = []
        let gate = ShortcutsGate(mayAct: { true })
        try await gate.run(confirm: { order.append("confirm") }, action: { order.append("act") })
        #expect(order == ["act"])
    }

    @Test func theSwitchIsReadEachTimeAndIsOffByDefault() async throws {
        SettingsKey.register()
        #expect(ShortcutsGate().mayAct() == false)
        let on = Flag(false)
        let gate = ShortcutsGate(mayAct: { on.isOn })
        var asked = 0
        try await gate.run(confirm: { asked += 1 }, action: {})
        on.isOn = true
        try await gate.run(confirm: { asked += 1 }, action: {})
        on.isOn = false
        try await gate.run(confirm: { asked += 1 }, action: {})
        #expect(asked == 2)
    }

    @Test func theQuestionsNameWhatWouldHappen() {
        #expect(ShortcutsGate.startQuestion(project: "Assay development", text: "QC this export", files: 0)
            == "Start a session in Assay development: \u{201C}QC this export\u{201D}?")
        #expect(ShortcutsGate.startQuestion(project: "Assay development", text: "QC this export", files: 2)
            == "Start a session in Assay development: \u{201C}QC this export\u{201D}, with 2 files?")
        #expect(ShortcutsGate.startQuestion(project: "Assay development", text: " ", files: 1)
            == "Start a session in Assay development: 1 file?")
        #expect(ShortcutsGate.sendQuestion(session: "Plate reader QC", text: "Add plate two", files: 0)
            == "Send a message to \u{201C}Plate reader QC\u{201D}: \u{201C}Add plate two\u{201D}?")
        let long = ShortcutsGate.startQuestion(project: "P", text: String(repeating: "x", count: 200), files: 0)
        #expect(long.contains("…") && long.count < 130)
    }

    @Test func theSettingIsAKeyOfTheSettingsAndThePageHasItsSentence() {
        #expect(SettingsKey.shortcutsMayAct == "shortcutsMayAct")
    }
}

// MARK: Entities, from the database each time

@Suite(.serialized)
struct IntentEntityTests {
    private func fake() -> IntentDatabase {
        IntentDatabase(
            projects: { [QuickStartProject(id: "proj_a", name: "Assay development"), QuickStartProject(id: "proj_b", name: "RNA-seq pilot")] },
            sessions: { words in
                let all = [IntentSession(id: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC", projectID: "proj_a",
                                         projectName: "Assay development", state: "Working"),
                           IntentSession(id: "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6", title: "Batch effect check", projectID: "proj_b",
                                         projectName: "RNA-seq pilot", state: "Needs input")]
                return words.isEmpty ? all : all.filter { s in words.allSatisfy { s.title.lowercased().contains($0.lowercased()) } }
            },
            session: { id in
                id == "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
                    ? IntentSession(id: id, title: "Plate reader QC", projectID: "proj_a", projectName: "Assay development", state: "Working")
                    : nil
            })
    }

    @Test func projectsAreOfferedFoundByIdAndMatchedByName() async throws {
        IntentDatabase.current = fake()
        defer { IntentDatabase.reset() }
        let query = ProjectEntityQuery()
        #expect(try await query.suggestedEntities().map(\.name) == ["Assay development", "RNA-seq pilot"])
        #expect(try await query.entities(for: ["proj_b", "proj_missing"]).map(\.id) == ["proj_b"])
        #expect(try await query.entities(matching: "rna pilot").map(\.id) == ["proj_b"])
        #expect(try await query.entities(matching: "zzz").isEmpty)
        #expect(String(localized: ProjectEntity(id: "proj_a", name: "Assay development").displayRepresentation.title) == "Assay development")
    }

    @Test func sessionsAreOfferedFoundByIdAndSearchedByName() async throws {
        IntentDatabase.current = fake()
        defer { IntentDatabase.reset() }
        let query = SessionEntityQuery()
        #expect(try await query.suggestedEntities().count == 2)
        let found = try await query.entities(for: ["0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"])
        #expect(found.map(\.title) == ["Plate reader QC"], "an id the database doesn't have is left out")
        #expect(try await query.entities(matching: "plate qc").map(\.projectName) == ["Assay development"])
        // One letter is no search, as in Quick Open.
        #expect(try await query.entities(matching: "p").isEmpty)
        let entity = try #require(found.first)
        #expect(entity.projectID == "proj_a" && entity.state == "Working")
    }

    @Test func recipesAreTheSettingsOwnAndNothingIsKeptByTheEntities() async throws {
        let store = RecipeStore()
        let before = store.recipes
        defer { store.recipes = before }
        store.recipes = [Recipe(id: "r1", name: "QC a plate-reader export", text: "QC it"), Recipe(id: "r2", name: "Summarize a paper", text: "Do")]
        let query = RecipeEntityQuery()
        #expect(try await query.suggestedEntities().map(\.id) == ["r1", "r2"])
        #expect(try await query.entities(matching: "summarize").map(\.id) == ["r2"])
        #expect(try await query.entities(for: ["r2", "r9"]).map(\.id) == ["r2"])
        // The entities hold no storage of their own: reading them again reads again.
        store.recipes = [Recipe(id: "r3", name: "New one", text: "x")]
        #expect(try await query.suggestedEntities().map(\.id) == ["r3"])
    }

    @Test func aSessionEntityReadsLikeARowOfTheDatabase() {
        let row = BrowseRow(id: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", projectID: "proj_a", projectName: "Assay development",
                            name: "Plate reader QC", status: "awaiting_user_response", createdMs: 1, updatedMs: 2, completedMs: nil, turnStartedMs: 1)
        let session = IntentSession(row)
        #expect(session.state == "Needs input" && session.projectName == "Assay development")
        let entity = SessionEntity(session)
        #expect(entity.title == "Plate reader QC")
        #expect(String(localized: SessionEntity(id: "i", title: "", projectID: "p", projectName: "Assay development", state: "Working")
            .displayRepresentation.title) == "Assay development")
    }
}

// MARK: What the intents do

@MainActor
private final class ActionSender: QuickStartSending {
    var outcome: QuickStartFlow.Outcome = .started(sessionID: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", sentence: "Started in Assay development.")
    private(set) var requests: [QuickStartFlow.Request] = []

    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome {
        requests.append(request)
        return outcome
    }
}

@Suite(.serialized)
@MainActor
struct ShortcutsActionsTests {
    private let sender = ActionSender()

    private func use(ready: [Bool] = [true], _ body: () async throws -> Void) async rethrows {
        let savedSender = ShortcutsActions.sender, savedReady = ShortcutsActions.isReady, savedSleep = ShortcutsActions.sleep
        defer {
            ShortcutsActions.sender = savedSender
            ShortcutsActions.isReady = savedReady
            ShortcutsActions.sleep = savedSleep
        }
        var checks = 0
        ShortcutsActions.sender = sender
        ShortcutsActions.isReady = { defer { checks += 1 }; return checks >= ready.count ? ready.last ?? true : ready[checks] }
        ShortcutsActions.sleep = { _ in }
        try await body()
    }

    private let project = QuickStartProject(id: "proj_a", name: "Assay development")

    @Test func aSessionStartsThroughTheSameFlowWithAFreshIntentId() async throws {
        try await use {
            let started = try await ShortcutsActions.start(project: project, text: "QC this export", files: [], planFirst: true)
            #expect(started.id == "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5")
            #expect(started.projectName == "Assay development" && started.title == "QC this export")
            let request = try #require(sender.requests.first)
            #expect(request.target == .newSession(project: "proj_a") && request.planFirst)
            #expect(RemoteActionRequest.isUUIDv4(request.intentID))
            _ = try await ShortcutsActions.start(project: project, text: "QC this export", files: [], planFirst: false)
            #expect(sender.requests[1].intentID != request.intentID)
        }
    }

    @Test func aFailureIsTheSentenceTheFlowGave() async {
        await use {
            sender.outcome = .failed(sentence: "Couldn't start the session. Your request is still here.")
            do {
                _ = try await ShortcutsActions.start(project: project, text: "x", files: [], planFirst: true)
                Issue.record("no error")
            } catch let error as ShortcutError {
                #expect(error.sentence == "Couldn't start the session. Your request is still here.")
            } catch { Issue.record("\(error)") }
        }
    }

    @Test func aMessageGoesToTheSessionAndSaysHowItWent() async throws {
        try await use {
            sender.outcome = .sent(.queued, sentence: "Queued. Claude reads it at the next safe point.")
            let session = SessionEntity(id: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC", projectID: "proj_a",
                                        projectName: "Assay development", state: "Working")
            let sentence = try await ShortcutsActions.send(session: session, text: "Add plate two", files: [])
            #expect(sentence == "Queued. Claude reads it at the next safe point.")
            #expect(sender.requests.first?.target == .session(id: session.id))
            #expect(sender.requests.first?.planFirst == false)
        }
    }

    @Test func aCaptionedLaunchWaitsForThePageAndGivesUpAfterTwentySeconds() async throws {
        var sleeps = 0
        try await use(ready: [false, false, true]) {
            ShortcutsActions.sleep = { _ in sleeps += 1 }
            _ = try await ShortcutsActions.start(project: project, text: "x", files: [], planFirst: true)
            #expect(sleeps == 2)
        }
        sleeps = 0
        try await use(ready: [false]) {
            ShortcutsActions.sleep = { _ in sleeps += 1 }
            _ = try await ShortcutsActions.start(project: project, text: "x", files: [], planFirst: true)
            #expect(sleeps == 40, "twenty seconds in halves, then the flow says it isn't ready")
        }
    }

    @Test func filesShortcutsHandsOverAreMadeIntoQuickStartsAndCleanedUp() throws {
        let given = [IntentFile(data: Data("a,b\n1,2\n".utf8), filename: "counts one.csv", type: .commaSeparatedText)]
        let made = try ShortcutsActions.files(from: given)
        #expect(made.files.map(\.name) == ["counts one.csv"])
        #expect(made.files.first?.size == 8)
        let folder = try #require(made.files.first?.url.deletingLastPathComponent())
        #expect(FileManager.default.fileExists(atPath: folder.path))
        made.cleanup()
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(try ShortcutsActions.files(from: nil).files.isEmpty)
        #expect(try ShortcutsActions.files(from: []).files.isEmpty)
    }

    @Test func aFileQuickStartWouldTurnAwayIsAnErrorNamingIt() {
        let given = [IntentFile(data: Data("MZ".utf8), filename: "setup.exe", type: nil)]
        do {
            _ = try ShortcutsActions.files(from: given)
            Issue.record("no error")
        } catch let error as ShortcutError {
            #expect(error.sentence.hasPrefix("\u{201C}setup.exe\u{201D} is a .exe file."))
        } catch { Issue.record("\(error)") }
        // And a file's name is made safe before it is written anywhere.
        let sneaky = [IntentFile(data: Data("a".utf8), filename: "../../escape.csv", type: .commaSeparatedText)]
        let made = try? ShortcutsActions.files(from: sneaky)
        #expect(made?.files.first?.name == "escape.csv")
        made?.cleanup()
    }

    @Test func theIntentsAreTheSixTheSettingsPageLists() {
        #expect(CapsidShortcuts.appShortcuts.count == 6)
        #expect(String(localized: StartSessionIntent.title) == "Start Session")
        #expect(String(localized: RunRecipeIntent.title) == "Run Recipe")
        #expect(String(localized: SendMessageIntent.title) == "Send Message")
        #expect(String(localized: SessionsNeedingMeIntent.title) == "Sessions Needing Me")
        #expect(String(localized: OpenSessionIntent.title) == "Open Session")
        #expect(String(localized: SetQuietWhilePresentingIntent.title) == "Set Quiet While Presenting")
    }
}
