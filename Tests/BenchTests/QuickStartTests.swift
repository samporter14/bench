// QuickStartTests.swift — Quick Start apart from the flow: recipes (storage and
// ⌘1 to ⌘9), the global keys (choice parsing, registering over a fake, a key
// another app holds), what the panel holds and says (the foot's sentence for
// each mode, the chips, a recipe filling it, a send's states, a retry's intent
// id), Finder's Services and the Info.plist that declares them. No window is
// opened, no key registered with the system, and nothing is sent.
import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Bench

/// Settings in memory, so a test leaves no preferences file behind.
private final class MemorySettings: SettingsStoring {
    private var values: [String: Any] = [:]
    func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

// MARK: Recipes

struct RecipeStoreTests {
    private func suite() -> (MemorySettings, String) { (MemorySettings(), "memory") }

    private let list = [
        Recipe(id: "r1", name: "QC a plate-reader export", project: "proj_a", text: "QC this export, flag edge effects", planFirst: true),
        Recipe(id: "r2", name: "Re-run the last analysis", project: nil, text: "Re-run it on these files.", planFirst: false),
    ]

    @Test func recipesRoundTripThroughSettingsAsOneJSONString() {
        let (defaults, name) = suite()
        let store = RecipeStore(defaults: defaults)
        #expect(store.recipes.isEmpty)
        store.recipes = list
        #expect(store.recipes == list)
        let stored = defaults.string(forKey: SettingsKey.recipes)
        #expect(stored != nil)
        // JSON in a stable order, with a project's id and nil as no project at all.
        #expect(stored == RecipeStore.encode(list))
        #expect(stored?.contains(#""project":"proj_a""#) == true)
        let object = (try? JSONSerialization.jsonObject(with: Data(stored!.utf8))) as? [[String: Any]]
        #expect(object?.count == 2)
        #expect(object?[1]["project"] == nil)
        #expect(Set(object?[0].keys.map { $0 } ?? []) == ["id", "name", "project", "text", "planFirst"])
        // The order is the person's.
        store.recipes = list.reversed()
        #expect(store.recipes.map(\.id) == ["r2", "r1"])
    }

    @Test func whatCantBeReadIsNoneAndWhatCantBeUsedIsLeftOut() {
        #expect(RecipeStore.decode(nil).isEmpty)
        #expect(RecipeStore.decode("").isEmpty)
        #expect(RecipeStore.decode("not json").isEmpty)
        #expect(RecipeStore.decode(#"{"id":"x"}"#).isEmpty)
        #expect(RecipeStore.decode(#"[{"id":"x"}]"#).isEmpty)
        let json = #"""
        [{"id":"a","name":"Good","text":"Do it","planFirst":true},
         {"id":"b","name":"  ","text":"No name","planFirst":true},
         {"id":"c","name":"No text","text":" ","planFirst":false},
         {"id":"a","name":"Same id","text":"Twice","planFirst":true},
         {"id":"d","name":"Braces","text":"Do {it}","planFirst":true}]
        """#
        #expect(RecipeStore.decode(json).map(\.id) == ["a", "d"])
    }

    @Test func aRecipeIsUsableWithinTheLimits() {
        #expect(Recipe(name: "a", text: "b").isUsable)
        #expect(!Recipe(name: "", text: "b").isUsable)
        #expect(!Recipe(name: String(repeating: "n", count: 81), text: "b").isUsable)
        #expect(Recipe(name: String(repeating: "n", count: 80), text: String(repeating: "界", count: 4000)).isUsable)
        #expect(!Recipe(name: "a", text: String(repeating: "界", count: 4001)).isUsable)
        #expect(Recipe(name: "a", text: "b").planFirst, "plan first by default, as the panel's box is")
        #expect(RecipeStore.limit == 60)
        let many = (0..<80).map { Recipe(id: "r\($0)", name: "n\($0)", text: "t") }
        #expect(RecipeStore.decode(RecipeStore.encode(many)).count == 60)
    }

    @Test func commandNumbersPickTheNthOfTheFirstNine() {
        let recipes = (1...12).map { Recipe(id: "r\($0)", name: "n\($0)", text: "t\($0)") }
        for number in 1...9 { #expect(RecipeKeys.recipe(for: number, in: recipes)?.id == "r\(number)") }
        for number in [0, 10, -1, 99] { #expect(RecipeKeys.recipe(for: number, in: recipes) == nil) }
        #expect(RecipeKeys.recipe(for: 3, in: Array(recipes.prefix(2))) == nil)
        #expect(RecipeKeys.recipe(for: 2, in: Array(recipes.prefix(2)))?.id == "r2")
        #expect(RecipeKeys.keyed(recipes).map(\.id) == (1...9).map { "r\($0)" })
        #expect(RecipeStore.keyed == 9)
    }
}

// MARK: The global keys

@MainActor
private final class FakeBackend: HotKeyBackend {
    var refuse: [GlobalHotKey.Choice: OSStatus] = [:]
    private(set) var registered: [GlobalHotKey.Slot: (code: UInt32, modifiers: UInt32)] = [:]
    private(set) var log: [String] = []

    func register(_ slot: GlobalHotKey.Slot, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        let choice = GlobalHotKey.Choice.allCases.first { $0.keyCode == keyCode && $0.carbonModifiers == modifiers }
        log.append("register \(slot.rawValue) \(choice?.rawValue ?? "?")")
        if let choice, let status = refuse[choice] { return status }
        registered[slot] = (keyCode, modifiers)
        return noErr
    }

    func unregister(_ slot: GlobalHotKey.Slot) {
        if registered.removeValue(forKey: slot) != nil { log.append("unregister \(slot.rawValue)") }
    }
}

@MainActor
struct GlobalHotKeyTests {
    @Test func theChoicesAreNoneAndFourKeysEachWithItsCodeAndModifiers() {
        #expect(GlobalHotKey.Choice.allCases.map(\.rawValue) == [
            "none", "controlOptionCommandSpace", "controlOptionSpace", "controlOptionCommandR", "controlOptionCommandN",
        ])
        let control = UInt32(controlKey), option = UInt32(optionKey), command = UInt32(cmdKey)
        #expect(GlobalHotKey.Choice.none.keyCode == nil && GlobalHotKey.Choice.none.carbonModifiers == 0)
        #expect(GlobalHotKey.Choice.controlOptionCommandSpace.keyCode == UInt32(kVK_Space))
        #expect(GlobalHotKey.Choice.controlOptionCommandSpace.carbonModifiers == control | option | command)
        #expect(GlobalHotKey.Choice.controlOptionSpace.keyCode == UInt32(kVK_Space))
        #expect(GlobalHotKey.Choice.controlOptionSpace.carbonModifiers == control | option)
        #expect(GlobalHotKey.Choice.controlOptionCommandR.keyCode == UInt32(kVK_ANSI_R))
        #expect(GlobalHotKey.Choice.controlOptionCommandN.keyCode == UInt32(kVK_ANSI_N))
        #expect(GlobalHotKey.Choice.allCases.map(\.title) == ["None", "⌃⌥⌘Space", "⌃⌥Space", "⌃⌥⌘R", "⌃⌥⌘N"])
        // No two choices are the same key.
        let pairs = GlobalHotKey.Choice.allCases.compactMap { c in c.keyCode.map { "\($0)/\(c.carbonModifiers)" } }
        #expect(Set(pairs).count == pairs.count)
        #expect(GlobalHotKey.Choice.controlOptionSpace.mayBeTheInputSourceKey)
        #expect(!GlobalHotKey.Choice.controlOptionCommandSpace.mayBeTheInputSourceKey)
        #expect(GlobalHotKey.Choice.none.menuShortcut == nil)
        #expect(GlobalHotKey.Choice.controlOptionCommandSpace.menuShortcut != nil)
    }

    @Test func aStoredChoiceIsParsedAndAnythingElseFallsBack() {
        #expect(GlobalHotKey.Choice.parse("controlOptionCommandN", fallback: .none) == .controlOptionCommandN)
        #expect(GlobalHotKey.Choice.parse("none", fallback: .controlOptionCommandR) == GlobalHotKey.Choice.none)
        #expect(GlobalHotKey.Choice.parse("hyperSpace", fallback: .controlOptionCommandR) == .controlOptionCommandR)
        #expect(GlobalHotKey.Choice.parse(nil, fallback: .controlOptionCommandSpace) == .controlOptionCommandSpace)
        #expect(GlobalHotKey.Choice.parse("", fallback: .controlOptionCommandSpace) == .controlOptionCommandSpace)
        #expect(GlobalHotKey.Slot.quickStart.fallback.rawValue == "controlOptionCommandSpace")
        #expect(GlobalHotKey.Slot.reply.fallback.rawValue == "controlOptionCommandR")
        #expect(GlobalHotKey.Slot.quickStart.setting == SettingsKey.quickStartKey)
        #expect(GlobalHotKey.Slot.reply.setting == SettingsKey.replyKey)
    }

    private func keys(_ settings: [String: String] = [:]) -> (GlobalKeys, FakeBackend, MemorySettings, String) {
        let (defaults, name) = (MemorySettings(), "memory")
        for (key, value) in settings { defaults.set(value, forKey: key) }
        let backend = FakeBackend()
        return (GlobalKeys(backend: backend, defaults: defaults), backend, defaults, name)
    }

    @Test func eachKeyIsRegisteredFromItsSettingAndTheDefaultsAreTheDefaults() {
        let (keys, backend, defaults, name) = keys()
        keys.apply()
        #expect(backend.registered[.quickStart]?.code == UInt32(kVK_Space))
        #expect(backend.registered[.reply]?.code == UInt32(kVK_ANSI_R))
        #expect(keys.active[.quickStart] == .controlOptionCommandSpace)
        #expect(keys.problems.isEmpty)
        // Applied again with nothing changed, nothing is registered twice.
        let before = backend.log.count
        keys.apply()
        #expect(backend.log.count == before)
    }

    @Test func changingAKeyLetsGoOfTheOldOneAndNoneRegistersNothing() {
        let (keys, backend, defaults, name) = keys()
        keys.apply()
        defaults.set("controlOptionCommandN", forKey: SettingsKey.quickStartKey)
        keys.apply()
        #expect(backend.registered[.quickStart]?.code == UInt32(kVK_ANSI_N))
        defaults.set("none", forKey: SettingsKey.quickStartKey)
        keys.apply()
        #expect(backend.registered[.quickStart] == nil)
        #expect(keys.active[.quickStart] == GlobalHotKey.Choice.none)
        #expect(keys.problems[.quickStart] == nil)
        #expect(backend.registered[.reply] != nil, "the other key is left as it was")
    }

    @Test func aKeyAnotherAppHoldsIsSaidSoAndTheOtherKeyStillWorks() {
        let (keys, backend, defaults, name) = keys()
        backend.refuse[.controlOptionCommandSpace] = OSStatus(eventHotKeyExistsErr)
        keys.apply()
        #expect(backend.registered[.quickStart] == nil)
        #expect(keys.problems[.quickStart] == "Another app already uses ⌃⌥⌘Space. Pick another key.")
        #expect(backend.registered[.reply] != nil)
        #expect(keys.problems[.reply] == nil)
        // Not asked again at every settings change, but at a change of its own.
        let before = backend.log.count
        keys.apply()
        #expect(backend.log.count == before)
        defaults.set("controlOptionCommandN", forKey: SettingsKey.quickStartKey)
        keys.apply()
        #expect(backend.registered[.quickStart] != nil)
        #expect(keys.problems.isEmpty)
        // Another reason says the system's number.
        backend.refuse[.controlOptionSpace] = -50
        defaults.set("controlOptionSpace", forKey: SettingsKey.replyKey)
        keys.apply()
        #expect(keys.problems[.reply] == "macOS wouldn't take ⌃⌥Space (error -50). Pick another key.")
    }

    @Test func twoSlotsNeverHoldTheSameKeyAndTheSecondSaysWhoHasIt() {
        let (keys, backend, defaults, name) = keys(["quickStartKey": "controlOptionCommandR", "replyKey": "controlOptionCommandR"])
        keys.apply()
        #expect(backend.registered[.quickStart] != nil)
        #expect(backend.registered[.reply] == nil)
        #expect(keys.problems[.reply] == "⌃⌥⌘R is already Quick Start's key. Pick another.")
        // Quick Start lets go of it: Reply takes it at the next change.
        defaults.set("controlOptionCommandN", forKey: SettingsKey.quickStartKey)
        keys.apply()
        #expect(backend.registered[.reply]?.code == UInt32(kVK_ANSI_R))
        #expect(keys.problems.isEmpty)
    }

    @Test func twoKeysCanSwapInOneChange() {
        let (keys, backend, defaults, name) = keys(["quickStartKey": "controlOptionCommandN", "replyKey": "controlOptionCommandR"])
        keys.apply()
        defaults.set("controlOptionCommandR", forKey: SettingsKey.quickStartKey)
        defaults.set("controlOptionCommandN", forKey: SettingsKey.replyKey)
        keys.apply()
        #expect(backend.registered[.quickStart]?.code == UInt32(kVK_ANSI_R))
        #expect(backend.registered[.reply]?.code == UInt32(kVK_ANSI_N))
        #expect(keys.problems.isEmpty)
    }

    @Test func aPressRunsItsActionOnceEvenIfTheKeyRepeats() {
        let defaults = MemorySettings()
        var clock = Date(timeIntervalSince1970: 1_000)
        let keys = GlobalKeys(backend: FakeBackend(), defaults: defaults, now: { clock })
        var presses: [String] = []
        keys.actions = [.quickStart: { presses.append("quick") }, .reply: { presses.append("reply") }]
        keys.fire(.quickStart)
        clock = clock.addingTimeInterval(0.1)
        keys.fire(.quickStart)
        keys.fire(.reply)
        clock = clock.addingTimeInterval(1)
        keys.fire(.quickStart)
        #expect(presses == ["quick", "reply", "quick"])
    }

    @Test func replysKeyOpensTheTopNeedsInputCardAndNothingWhenNoneWaits() {
        func session(_ id: String, _ reason: WaitingReason) -> SessionStatus {
            SessionStatus(id: id, projectID: "p", projectName: "P", title: "T", state: .needsInput, updatedAt: Date(), waitingReason: reason)
        }
        let finished = SessionStatus(id: "f", projectID: "p", projectName: "P", title: "T", state: .finished, updatedAt: Date())
        var shown: [(String, Bool)] = []
        let none = ReplyKey.openTopCard(cards: [.finished(finished), .failed(finished)]) { shown.append(($0, $1)) }
        #expect(!none && shown.isEmpty)
        #expect(!ReplyKey.openTopCard(cards: []) { shown.append(($0, $1)) })
        let opened = ReplyKey.openTopCard(cards: [.finished(finished), .needsInput(session("q", .question)), .needsInput(session("p", .plan))]) {
            shown.append(($0, $1))
        }
        #expect(opened)
        #expect(shown.count == 1 && shown[0].0 == "q" && shown[0].1 == false)
        // A plan opens what to change in it, never an approval.
        _ = ReplyKey.openTopCard(cards: [.needsInput(session("p", .plan))]) { shown.append(($0, $1)) }
        #expect(shown.last?.0 == "p" && shown.last?.1 == true)
    }

    @Test func theKeysAreRegisteredByDefaultAndShortcutsMayNotActUntilTold() {
        SettingsKey.register()
        let defaults = UserDefaults.standard
        #expect(defaults.string(forKey: SettingsKey.quickStartKey) != nil)
        #expect(defaults.string(forKey: SettingsKey.replyKey) != nil)
        #expect(defaults.object(forKey: SettingsKey.shortcutsMayAct) != nil)
        #expect(defaults.bool(forKey: SettingsKey.shortcutsMayAct) == false)
    }
}

// MARK: The panel's model

@MainActor
private final class FakeSender: QuickStartSending {
    var outcomes: [QuickStartFlow.Outcome] = [.started(sessionID: "00000000-0000-4000-8000-000000000002", sentence: "Started in Assay development.")]
    private(set) var requests: [QuickStartFlow.Request] = []
    var gate: CheckedContinuation<Void, Never>?
    var hold = false

    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome {
        requests.append(request)
        if hold { await withCheckedContinuation { gate = $0 } }
        return outcomes[min(requests.count - 1, outcomes.count - 1)]
    }

    func release() { gate?.resume(); gate = nil }
}

@MainActor
private final class ModelRig {
    let sender = FakeSender()
    var recipes: [Recipe] = [
        Recipe(id: "recipe-1", name: "QC a plate-reader export", project: "proj_assay", text: "QC this plate-reader export, flag edge effects", planFirst: true),
        Recipe(id: "recipe-2", name: "Summarize a new paper", project: "proj_read", text: "Summarize this paper for journal club.", planFirst: false),
        Recipe(id: "recipe-3", name: "Re-run the last analysis", project: nil, text: "Re-run it on these files.", planFirst: true),
    ]
    var recents = [QuickStartProject(id: "proj_assay", name: "Assay development"), QuickStartProject(id: "proj_rna", name: "RNA-seq pilot"),
                   QuickStartProject(id: "proj_screen", name: "Screen analysis"), QuickStartProject(id: "proj_read", name: "Reading group")]
    var everything: [QuickStartProject]? = [
        QuickStartProject(id: "proj_assay", name: "Assay development"), QuickStartProject(id: "proj_rna", name: "RNA-seq pilot"),
        QuickStartProject(id: "proj_screen", name: "Screen analysis"), QuickStartProject(id: "proj_read", name: "Reading group"),
        QuickStartProject(id: "proj_old", name: "Old pilot"),
    ]
    var viewed: ViewedSession? = ViewedSession(id: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC",
                                               projectID: "proj_assay", projectName: "Assay development")
    private(set) var closed = 0
    private(set) var lingered: [Duration] = []

    lazy var model = QuickStartModel(dependencies: QuickStartModel.Dependencies(
        recipes: { [unowned self] in self.recipes },
        recentProjects: { [unowned self] in self.recents },
        allProjects: { [unowned self] in self.everything },
        viewed: { [unowned self] in self.viewed },
        sender: sender,
        makeFile: { url in QuickStartFile.make(url: url, size: url.lastPathComponent.hasPrefix("big") ? 30_000_000 : 1_000, isFolder: false) },
        close: { [unowned self] in self.closed += 1 },
        linger: .milliseconds(1600),
        sleep: { [unowned self] in self.lingered.append($0) }))

    /// Lets the lookups the panel starts when it opens land.
    func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    func waitForSend() async {
        for _ in 0..<200 where model.phase == .sending { await Task.yield() }
        for _ in 0..<30 { await Task.yield() }
    }

    func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/capsid-demo/" + name) }
}

@MainActor
struct QuickStartFooterTests {
    private let project = QuickStartProject(id: "p", name: "Assay development")
    private let viewed = ViewedSession(id: "s", title: "Plate reader QC", projectID: "p", projectName: "Assay development")

    @Test func aNewSessionNamesTheProjectAndSaysItRunsOnYourPlan() {
        #expect(QuickStartFooter.sentence(shift: false, project: project, viewed: viewed)
            == "A new session in Assay development, on your plan. ⇧↩ sends it to the session you're viewing.")
    }

    @Test func theShiftHintIsLeftOutWhenNoSessionIsOpen() {
        #expect(QuickStartFooter.sentence(shift: false, project: project, viewed: nil) == "A new session in Assay development, on your plan.")
        #expect(QuickStartFooter.sentence(shift: false, project: nil, viewed: nil) == "Choose a project to start in.")
        #expect(QuickStartFooter.sentence(shift: false, project: nil, viewed: viewed)
            == "Choose a project to start in. ⇧↩ sends it to the session you're viewing.")
    }

    @Test func withShiftDownItIsAMessageToTheSessionInViewInItsProjectOnYourPlan() {
        #expect(QuickStartFooter.sentence(shift: true, project: project, viewed: viewed)
            == "A message to \u{201C}Plate reader QC\u{201D} in Assay development, on your plan. It waits its turn if Claude is busy.")
        let untitled = ViewedSession(id: "s", title: "", projectID: "p", projectName: "Assay development")
        #expect(QuickStartFooter.sentence(shift: true, project: nil, viewed: untitled)
            == "A message to the session you're viewing in Assay development, on your plan. It waits its turn if Claude is busy.")
        #expect(QuickStartFooter.sentence(shift: true, project: project, viewed: nil)
            == "No session is open to send to. Let go of ⇧ to start a new one.")
    }

    @Test func theModelsFooterFollowsShift() async {
        let rig = ModelRig()
        rig.model.open()
        await rig.settle()
        #expect(rig.model.footer.hasPrefix("A new session in Assay development, on your plan."))
        #expect(rig.model.buttonTitle == "Start ↩")
        rig.model.shiftHeld = true
        #expect(rig.model.footer.hasPrefix("A message to \u{201C}Plate reader QC\u{201D} in Assay development, on your plan."))
        #expect(rig.model.buttonTitle == "Send ⇧↩")
    }
}

@MainActor
struct QuickStartModelTests {
    private let rig = ModelRig()
    private var model: QuickStartModel { rig.model }

    @Test func itOpensOnTheMostRecentProjectAndTheSessionInViewsProjectWins() async {
        model.open()
        #expect(model.projectID == "proj_assay")
        #expect(model.recipes.map(\.id) == ["recipe-1", "recipe-2", "recipe-3"])
        rig.viewed = ViewedSession(id: "s", title: "T", projectID: "proj_screen", projectName: "Screen analysis")
        model.open()
        await rig.settle()
        #expect(model.projectID == "proj_screen")
        #expect(model.viewed?.id == "s")
        // A project nobody knows isn't taken.
        rig.viewed = ViewedSession(id: "s", title: "T", projectID: "proj_nowhere", projectName: "Nowhere")
        model.open()
        await rig.settle()
        #expect(model.projectID == "proj_assay")
        // And a project chosen before the lookup landed stays.
        rig.viewed = ViewedSession(id: "s", title: "T", projectID: "proj_screen", projectName: "Screen analysis")
        model.open()
        model.choose(rig.recents[1])
        await rig.settle()
        #expect(model.projectID == "proj_rna")
    }

    @Test func theChipsAreTheThreeMostRecentAndTheChosenOneJoinsThem() async {
        model.open()
        await rig.settle()
        #expect(model.chips.map(\.name) == ["Assay development", "RNA-seq pilot", "Screen analysis"])
        #expect(model.otherProjects.map(\.id) == ["proj_read", "proj_old"])
        // From Other…: it takes the first place and the last chip makes room.
        model.choose(QuickStartProject(id: "proj_old", name: "Old pilot"))
        #expect(model.chips.map(\.name) == ["Old pilot", "Assay development", "RNA-seq pilot"])
        #expect(model.project?.name == "Old pilot")
        #expect(!model.otherProjects.contains { $0.id == "proj_old" })
    }

    @Test func aRecipeFillsThePanelAndPicksItsProjectAndAnyProjectKeepsTheChosenOne() async {
        model.open()
        await rig.settle()
        model.applyRecipe(number: 2)
        #expect(model.text.hasPrefix("Summarize this paper"))
        #expect(model.planFirst == false)
        #expect(model.projectID == "proj_read")
        #expect(model.appliedRecipe == "recipe-2")
        model.choose(rig.recents[0])
        model.applyRecipe(number: 3)
        #expect(model.projectID == "proj_assay", "a recipe for any project leaves the chosen one")
        #expect(model.planFirst == true)
        // Typing past a recipe's words ends its tint.
        model.text += " Also the controls."
        #expect(model.appliedRecipe == nil)
        // No recipe on a number past the end, and no change.
        let before = model.text
        model.applyRecipe(number: 7)
        model.applyRecipe(number: 0)
        #expect(model.text == before)
        #expect(model.projectLabel(for: rig.recipes[0]) == "Assay development")
        #expect(model.projectLabel(for: rig.recipes[2]) == "Any project")
        #expect(model.projectLabel(for: Recipe(name: "x", project: "proj_gone", text: "t")) == "Unknown project")
    }

    @Test func onlyTheFirstNineRecipesHaveKeys() {
        rig.recipes = (1...12).map { Recipe(id: "r\($0)", name: "n\($0)", text: "t\($0)") }
        model.open()
        #expect(model.recipes.count == 9)
    }

    @Test func filesAreAddedOnceAndTurnedAwayWithTheFirstSentence() async {
        model.open(files: [rig.file("a.csv"), rig.file("a.csv"), rig.file("setup.dmg"), rig.file("big one.csv"), rig.file("b.pdf")])
        #expect(model.files.map(\.name) == ["a.csv", "b.pdf"], "the repeat, the .dmg and the big one are out")
        guard case .failed(let sentence) = model.phase else { Issue.record("no sentence"); return }
        #expect(sentence.hasPrefix("\u{201C}setup.dmg\u{201D} is a .dmg file."))
        // A new word clears it; the files stay.
        model.text = "QC these"
        #expect(model.phase == .editing)
        #expect(model.files.count == 2)
        model.remove(model.files[0])
        #expect(model.files.map(\.name) == ["b.pdf"])
        // The ninth file is refused with the count.
        model.addFiles((0..<9).map { rig.file("f\($0).csv") })
        #expect(model.files.count == 8)
        #expect(model.phase == .failed(AttachmentRefusal.tooMany.sentence))
    }

    @Test func aServiceOrShortcutOpensItWithFilesAndTextAndAReopenKeepsWhatWasTyped() {
        model.open(files: [rig.file("a.csv")], text: "From a selection")
        #expect(model.text == "From a selection" && model.files.count == 1)
        model.text = "Edited"
        model.open(files: [rig.file("b.csv")], text: nil, keeping: true)
        #expect(model.text == "Edited")
        #expect(model.files.map(\.name) == ["a.csv", "b.csv"])
        model.open()
        #expect(model.text == "" && model.files.isEmpty && model.appliedRecipe == nil && model.planFirst)
    }

    @Test func startNeedsSomethingToSayAndSomewhereToSayIt() async {
        model.open()
        await rig.settle()
        #expect(!model.canSubmit(toViewed: false))
        model.text = "  "
        #expect(!model.canSubmit(toViewed: false))
        model.text = "QC this"
        #expect(model.canSubmit(toViewed: false) && model.canSubmit(toViewed: true))
        rig.viewed = nil
        model.open()
        await rig.settle()
        model.text = "QC this"
        #expect(model.canSubmit(toViewed: false) && !model.canSubmit(toViewed: true))
        model.submit(toViewed: true)
        #expect(rig.sender.requests.isEmpty, "⇧↩ with no session open sends nothing")
        // Files alone are something to say.
        model.text = ""
        model.addFiles([rig.file("a.csv")])
        #expect(model.canSubmit(toViewed: false))
    }

    @Test func returnStartsASessionInTheChosenProjectWithThePlanSwitch() async {
        model.open()
        await rig.settle()
        model.text = "QC this export"
        model.planFirst = false
        model.submit(toViewed: false)
        #expect(model.phase == .sending)
        await rig.waitForSend()
        let request = rig.sender.requests.first
        #expect(request?.target == .newSession(project: "proj_assay"))
        #expect(request?.projectName == "Assay development")
        #expect(request?.text == "QC this export")
        #expect(request?.planFirst == false)
        #expect(RemoteActionRequest.isUUIDv4(request?.intentID ?? ""))
        #expect(model.phase == .sent("Started in Assay development."))
        // Sent: the panel is put away after a moment, not before.
        #expect(rig.lingered == [.milliseconds(1600)])
        #expect(rig.closed == 1)
        #expect(!model.canSubmit(toViewed: false), "nothing is sent twice")
    }

    @Test func shiftReturnSendsAMessageToTheSessionInView() async {
        rig.sender.outcomes = [.sent(.queued, sentence: "Queued. Claude reads it at the next safe point.")]
        model.open()
        await rig.settle()
        model.text = "Add the second plate"
        model.addFiles([rig.file("a.csv")])
        model.submit(toViewed: true)
        await rig.waitForSend()
        let request = rig.sender.requests.first
        #expect(request?.target == .session(id: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"))
        #expect(request?.planFirst == false)
        #expect(request?.files.map(\.name) == ["a.csv"])
        #expect(model.phase == .sent("Queued. Claude reads it at the next safe point."))
    }

    @Test func aFailureKeepsEverythingAndARetryKeepsItsIntentIdUntilSomethingChanges() async {
        rig.sender.outcomes = [.failed(sentence: "Couldn't start the session. Your request is still here."),
                               .failed(sentence: "Couldn't start the session. Your request is still here."),
                               .failed(sentence: "Couldn't start the session. Your request is still here."),
                               .started(sessionID: "00000000-0000-4000-8000-000000000002", sentence: "Started in Assay development.")]
        model.open()
        await rig.settle()
        model.text = "QC this export"
        model.addFiles([rig.file("a.csv")])
        model.submit()
        await rig.waitForSend()
        #expect(model.phase == .failed("Couldn't start the session. Your request is still here."))
        #expect(model.text == "QC this export" && model.files.count == 1)
        #expect(rig.closed == 0)
        // Again, unchanged: the same intent id, so a session that did start is found, not made twice.
        model.submit()
        await rig.waitForSend()
        #expect(rig.sender.requests.count == 2)
        #expect(rig.sender.requests[0].intentID == rig.sender.requests[1].intentID)
        // Edited: a new request, a new id.
        model.text = "QC this export, then flag edge effects"
        model.submit()
        await rig.waitForSend()
        #expect(rig.sender.requests[2].intentID != rig.sender.requests[1].intentID)
        // Once it went, the next request is new whatever it holds.
        model.submit()
        await rig.waitForSend()
        #expect(rig.sender.requests.count == 4)
        #expect(rig.sender.requests[3].intentID == rig.sender.requests[2].intentID)
        model.open()
        await rig.settle()
        model.text = "QC this export, then flag edge effects"
        model.submit()
        await rig.waitForSend()
        #expect(rig.sender.requests.last?.intentID != rig.sender.requests[3].intentID)
    }

    @Test func aSendInHandIsNotSentAgainByASecondReturn() async {
        rig.sender.hold = true
        model.open()
        await rig.settle()
        model.text = "QC this"
        model.submit()
        await Task.yield()
        model.submit()
        model.submit(toViewed: true)
        for _ in 0..<10 { await Task.yield() }
        #expect(rig.sender.requests.count == 1)
        #expect(model.phase == .sending)
        #expect(model.buttonTitle == "Starting…")
        rig.sender.hold = false
        rig.sender.release()
        await rig.waitForSend()
        #expect(model.phase == .sent("Started in Assay development."))
    }

    @Test func cancelPutsThePanelAwayAndSendsNothing() async {
        model.open()
        await rig.settle()
        model.text = "QC this"
        model.cancel()
        #expect(rig.closed == 1)
        #expect(rig.sender.requests.isEmpty)
    }

    @Test func theMadeUpDemoSendsNothingAndAnswersStarted() async throws {
        let demo = QuickStartDemo.model()
        for _ in 0..<30 { await Task.yield() }
        #expect(demo.text.hasPrefix("QC this plate-reader export"))
        #expect(demo.files.map(\.name) == ["plate_reader_2026-10-22.xlsx"])
        #expect(demo.project?.name == "Assay development" && demo.appliedRecipe == "demo-recipe-1")
        demo.submit()
        for _ in 0..<400 where demo.phase == .sending { try await Task.sleep(for: .milliseconds(10)) }
        #expect(demo.phase == .sent("Started in Assay development."))
    }
}

// MARK: Services

@MainActor
struct QuickStartServicesTests {
    private func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("capsid-services-test-\(UUID().uuidString)"))
    }

    @Test func fileURLsAreReadInOrderWithRepeatsDropped() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        let urls = [URL(fileURLWithPath: "/tmp/b.csv"), URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.csv")]
        board.writeObjects(urls as [NSURL])
        #expect(QuickStartServices.fileURLs(on: board).map(\.path) == ["/tmp/b.csv", "/tmp/a.pdf"])
        board.clearContents()
        board.setString("https://example.com", forType: .URL)
        #expect(QuickStartServices.fileURLs(on: board).isEmpty)
    }

    @Test func selectedTextIsTrimmedAndCutToWhatARequestMayHold() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("  What does the edge effect look like?\n", forType: .string)
        #expect(QuickStartServices.text(on: board) == "What does the edge effect look like?")
        board.clearContents()
        board.setString(String(repeating: "界", count: 5000), forType: .string)
        #expect(QuickStartServices.text(on: board)?.unicodeScalars.count == QuickStartFlow.textLimit)
        board.clearContents()
        board.setString(" \n ", forType: .string)
        #expect(QuickStartServices.text(on: board) == nil)
    }

    @Test func theFilesServiceOpensQuickStartWithTheFilesAndStartsNothing() {
        let services = QuickStartServices()
        var opened: [([URL], String?)] = []
        services.open = { opened.append(($0, $1)) }
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/plate.xlsx")] as [NSURL])
        var error: NSString = ""
        services.startSessionWithFiles(board, userData: nil, error: &error)
        #expect(opened.count == 1 && opened[0].0.map(\.path) == ["/tmp/plate.xlsx"] && opened[0].1 == nil)
        // Nothing to take: the system is told, and the panel isn't opened.
        board.clearContents()
        services.startSessionWithFiles(board, userData: nil, error: &error)
        #expect(opened.count == 1)
        #expect(error == "Capsid couldn't find any files in that selection.")
    }

    @Test func theTextServiceOpensQuickStartWithTheSelection() {
        let services = QuickStartServices()
        var opened: [([URL], String?)] = []
        services.open = { opened.append(($0, $1)) }
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("Why is column 12 low?", forType: .string)
        var error: NSString = ""
        services.startSessionWithText(board, userData: nil, error: &error)
        #expect(opened.count == 1 && opened[0].0.isEmpty && opened[0].1 == "Why is column 12 low?")
        board.clearContents()
        services.startSessionWithText(board, userData: nil, error: &error)
        #expect(opened.count == 1)
        #expect(error == "Capsid couldn't find any text in that selection.")
    }

    @Test func theInfoPlistDeclaresBothServicesAndTheProviderAnswersTheirSelectors() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let info = try #require(PropertyListSerialization.propertyList(from: try Data(contentsOf: plist), format: nil) as? [String: Any])
        let services = try #require(info["NSServices"] as? [[String: Any]])
        #expect(services.count == 2)
        let byMessage = Dictionary(uniqueKeysWithValues: services.compactMap { service in
            (service["NSMessage"] as? String).map { ($0, service) }
        })
        let files = try #require(byMessage[QuickStartServices.filesMessage])
        let text = try #require(byMessage[QuickStartServices.textMessage])
        #expect((files["NSMenuItem"] as? [String: String])?["default"] == "Start Session in Capsid…")
        #expect((files["NSSendFileTypes"] as? [String])?.contains("public.item") == true)
        #expect(files["NSSendTypes"] == nil)
        #expect((text["NSSendTypes"] as? [String])?.contains("NSStringPboardType") == true)
        #expect(text["NSSendFileTypes"] == nil)
        // The port is the app's name, which is what the system looks the provider up by.
        for service in services { #expect(service["NSPortName"] as? String == info["CFBundleName"] as? String) }
        let provider = QuickStartServices.shared
        for message in [QuickStartServices.filesMessage, QuickStartServices.textMessage] {
            #expect(provider.responds(to: Selector("\(message):userData:error:")), "\(message)")
        }
    }
}
