// AnotherModelTests.swift — Ask Another Model's setting and key (AskModel/
// AnotherModel.swift): off by default; the key in a file of its own, 0600 in a
// 0700 folder, never in the settings and never in a log line; Remove deletes
// it; the model list chooses the first model; and with the switch off or no key,
// none of the ways in shows. A made-up key, a throwaway settings suite, a
// temporary folder and the fake URLProtocol; nothing leaves the process.
import AppKit
import Combine
import Foundation
import Testing
@testable import Bench

@MainActor
private final class Rig {
    let defaults = ScratchDefaults.make(prefix: "another-model")
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("capsid-another-model-\(UUID().uuidString)", isDirectory: true)
    private(set) var lines: [String] = []
    let host: String

    init(answer: @escaping @Sendable (URLRequest) -> FakeModelProtocol.Answer = { request in
        request.url?.path().hasSuffix("/models") == true
            ? .reply(200, #"{"data":[{"id":"abliterated-model"},{"id":"abliterated-model-large"}]}"#)
            : .reply(200, #"{"choices":[{"message":{"content":"Rerun plate 3 with HEPES."}}]}"#)
    }) {
        host = FakeModelProtocol.host(answer)
        defaults.defaults.set("https://\(host)/v1", forKey: SettingsKey.anotherModelAddress)
    }

    lazy var store = FileDeviceStore(name: AnotherModelKey.fileName, folder: folder)

    lazy var model = AnotherModel(store: store, defaults: defaults.defaults,
                                  client: AnotherModelClient(configuration: FakeModelProtocol.configuration()),
                                  log: { [weak self] in self?.lines.append($0) })

    var keyFile: URL { folder.appendingPathComponent(AnotherModelKey.fileName) }

    func waitForList() async {
        for _ in 0..<300 {
            if case .loading = model.listing { try? await Task.sleep(for: .milliseconds(10)) } else { break }
        }
    }

    deinit {
        defaults.discard()
        try? FileManager.default.removeItem(at: folder)
    }
}

@MainActor
struct AnotherModelSettingTests {
    @Test func itIsOffByDefaultAndRegisteredSo() {
        let rig = Rig()
        #expect(rig.model.isOn == false)
        #expect(rig.model.isAvailable == false)
        SettingsKey.register()
        #expect(UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)[SettingsKey.askAnotherModel] as? Bool == false)
        #expect(UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)[SettingsKey.anotherModelAddress] as? String
            == "https://api.abliteration.ai/v1")
    }

    @Test func theKeyIsAFileOnlyTheUserCanReadInAFolderOnlyTheUserCanOpen() throws {
        let rig = Rig()
        #expect(rig.model.saveKey("  \(madeUpModelKey)\n"))
        #expect(rig.model.hasKey)
        let files = FileManager.default
        let file = try files.attributesOfItem(atPath: rig.keyFile.path)
        #expect((file[.posixPermissions] as? NSNumber)?.int16Value == 0o600)
        let folder = try files.attributesOfItem(atPath: rig.folder.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.int16Value == 0o700)
        // The file holds the key and nothing else, trimmed.
        #expect(try String(contentsOf: rig.keyFile, encoding: .utf8) == madeUpModelKey)
        #expect(rig.model.currentKey() == madeUpModelKey)
        // Only the key's own file is in the folder (no temporary copy left behind).
        #expect(try files.contentsOfDirectory(atPath: rig.folder.path) == [AnotherModelKey.fileName])
    }

    @Test func theDefaultFolderIsCapsidsOwnApplicationSupportFolder() {
        #expect(FileDeviceStore.folder.path.hasSuffix("Library/Application Support/Bench"))
    }

    @Test func theKeyIsInNoSettingAndNoLogLine() async {
        let rig = Rig()
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        _ = await rig.model.ask([ChatTurn(role: .user, text: "Which buffer?")])
        rig.model.removeKey()
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        // Not in the suite the feature writes to…
        let stored = rig.defaults.defaults.dictionaryRepresentation()
        #expect(!stored.values.contains { "\($0)".contains(madeUpModelKey) })
        #expect(!stored.values.contains { "\($0)".contains("sk-made-up") })
        // …nor in the app's own.
        #expect(!UserDefaults.standard.dictionaryRepresentation().values.contains { "\($0)".contains(madeUpModelKey) })
        // The log said what happened, in fixed words.
        #expect(rig.lines.contains("Another model: key saved"))
        #expect(rig.lines.contains("Another model: key removed"))
        #expect(rig.lines.contains("Another model: listed 2 models"))
        #expect(!rig.lines.contains { $0.contains(madeUpModelKey) || $0.contains("sk-") })
        #expect(!rig.lines.contains { $0.contains("abliterated") || $0.contains(rig.host) })
    }

    @Test func somethingThatIsNoKeyIsNotSaved() {
        let rig = Rig()
        #expect(rig.model.saveKey("not a key") == false)
        #expect(rig.model.hasKey == false)
        #expect(rig.model.keyProblem != nil)
        #expect(!FileManager.default.fileExists(atPath: rig.keyFile.path))
        // The problem names nothing of what was pasted.
        #expect(rig.model.keyProblem?.contains("not a key") == false)
    }

    @Test func removeDeletesTheKeysFileAndTheList() async {
        let rig = Rig()
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        rig.model.removeKey()
        #expect(rig.model.hasKey == false)
        #expect(rig.model.isAvailable == false)
        #expect(rig.model.listing == .idle)
        #expect(!FileManager.default.fileExists(atPath: rig.keyFile.path))
        #expect(rig.model.currentKey() == nil)
    }

    @Test func aSavedKeyIsFoundAgainAtTheNextLaunch() {
        let rig = Rig()
        rig.model.saveKey(madeUpModelKey)
        let again = AnotherModel(store: FileDeviceStore(name: AnotherModelKey.fileName, folder: rig.folder),
                                 defaults: rig.defaults.defaults, client: .init(configuration: FakeModelProtocol.configuration()),
                                 log: { _ in })
        #expect(again.hasKey)
    }

    @Test func theListChoosesTheFirstModelAndKeepsAChoiceItStillLists() async {
        let rig = Rig()
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        #expect(rig.model.listing == .listed(["abliterated-model", "abliterated-model-large"]))
        #expect(rig.model.model == "abliterated-model")
        rig.model.choose("abliterated-model-large")
        rig.model.listModels()
        await rig.waitForList()
        #expect(rig.model.model == "abliterated-model-large")
        // The model is a setting; the list is asked with the key.
        let request = FakeModelProtocol.seen(rig.host).requests.first
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer \(madeUpModelKey)")
    }

    @Test func aRefusedKeyIsSaidAndKept() async {
        let rig = Rig(answer: { _ in .reply(401, "{}") })
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        guard case .failed(let sentence) = rig.model.listing else {
            Issue.record("not failed: \(rig.model.listing)")
            return
        }
        // In Settings' own model row, where "Settings" is where the person already is.
        #expect(sentence == "\(rig.host) didn\u{2019}t accept your key. Remove it, then paste another.")
        // The key stays: the person may have pasted the right one for another address.
        #expect(rig.model.hasKey)
        #expect(rig.lines.contains("Another model: listing models failed, key not accepted"))
    }

    @Test func anAddressThatIsNotHttpsIsNeverSentTheKey() async {
        let rig = Rig()
        rig.defaults.defaults.set("http://\(rig.host)/v1", forKey: SettingsKey.anotherModelAddress)
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        #expect(rig.model.listing == .failed("That isn\u{2019}t an https address."))
        #expect(await rig.model.ask([ChatTurn(role: .user, text: "Which buffer?")]).result == .failure(.notSet(.address)))
        #expect(FakeModelProtocol.seen(rig.host).requests.isEmpty)
    }

    @Test func aKeyKeptWhileTheSwitchIsOffSendsNothing() async {
        let rig = Rig()
        // A key saved while it is off is kept, and the address is not asked anything.
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        #expect(rig.model.hasKey)
        #expect(rig.model.listing == .idle)
        #expect(FakeModelProtocol.seen(rig.host).requests.isEmpty)
        rig.model.setOn(true)
        await rig.waitForList()
        #expect(rig.model.listing == .listed(["abliterated-model", "abliterated-model-large"]))
        let before = FakeModelProtocol.seen(rig.host).requests.count
        rig.model.setOn(false)
        #expect(rig.model.isAvailable == false)
        #expect(await rig.model.ask([ChatTurn(role: .user, text: "Which buffer?")]).result == .failure(.notSet(.switchedOff)))
        #expect(FakeModelProtocol.seen(rig.host).requests.count == before)
    }

    @Test func editingTheAddressDropsTheListUntilItIsAskedForAgain() async {
        let rig = Rig()
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        #expect(rig.model.listing == .listed(["abliterated-model", "abliterated-model-large"]))
        let asked = FakeModelProtocol.seen(rig.host).requests.count
        rig.model.addressEdited()
        #expect(rig.model.listing == .idle)
        // The model chosen stays; nothing was sent to the address as it was typed.
        #expect(rig.model.model == "abliterated-model")
        #expect(FakeModelProtocol.seen(rig.host).requests.count == asked)
        // Return asks again.
        rig.model.listModels()
        await rig.waitForList()
        #expect(rig.model.listing == .listed(["abliterated-model", "abliterated-model-large"]))
        // With no key there is no list to drop.
        rig.model.removeKey()
        rig.model.addressEdited()
        #expect(rig.model.listing == .idle)
    }

    @Test func askingWithoutAKeyOrAModelSaysWhichIsMissing() async {
        let rig = Rig(answer: { _ in .reply(500, "{}") })
        let turns = [ChatTurn(role: .user, text: "Which buffer?")]
        // Off: nothing is sent, even to a window left open, and the sentence says why.
        #expect(await rig.model.ask(turns).result == .failure(.notSet(.switchedOff)))
        rig.model.setOn(true)
        #expect(await rig.model.ask(turns).result == .failure(.notSet(.key)))
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        // The list failed, so no model is chosen.
        #expect(rig.model.model == nil)
        #expect(await rig.model.ask(turns).result == .failure(.notSet(.model)))
        #expect(FakeModelProtocol.seen(rig.host).requests.count == 1)
    }
}

// MARK: Off hides every way in

@MainActor
struct AskEntryPointTests {
    @Test func theFileMenusItemIsThereOnlyWhileItIsOnWithAKey() {
        let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
        #expect(AskMenu.fileItem(available: false, session: session, demo: false) == (false, false))
        #expect(AskMenu.fileItem(available: true, session: session, demo: false) == (true, true))
        // On, but no session in the main window (or a demo): there, and dim.
        #expect(AskMenu.fileItem(available: true, session: nil, demo: false) == (true, false))
        #expect(AskMenu.fileItem(available: true, session: "not-a-frame", demo: false) == (true, false))
        #expect(AskMenu.fileItem(available: true, session: session, demo: true) == (true, false))
    }

    @Test func theReferenceWindowsRightClickItemIsAddedOnlyWhileItIsOnWithAKey() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))
        #expect(AskMenu.insert(into: menu, available: false) {} == false)
        #expect(menu.items.map(\.title) == ["Copy"])
        #expect(AskMenu.insert(into: menu, available: true) {})
        #expect(menu.items.first?.title == "Ask Another Model\u{2026}")
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items.last?.title == "Copy")
        // Not twice.
        #expect(AskMenu.insert(into: menu, available: true) {} == false)
        #expect(menu.items.filter { $0.title == "Ask Another Model\u{2026}" }.count == 1)
    }

    // MARK: The toolbar button and File's item

    private static let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

    /// Lets the main queue run: the commands hear their model and the page's address a turn later.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    @Test func theToolbarButtonAndFilesItemAreThereOnlyWhileItIsOnWithAKeyAndOnWithASession() async {
        let rig = Rig()
        let frames = CurrentValueSubject<String?, Never>(nil)
        var opened = 0
        let commands = AskCommands(model: rig.model, frames: frames, demo: false, open: { opened += 1 })
        await settle()
        // Off: neither shows.
        #expect(commands.isShown == false)
        #expect(commands.isEnabled == false)
        // On with no key: still neither.
        rig.model.setOn(true)
        await settle()
        #expect(commands.isShown == false)
        // A key: there, and dim with no session in the main window.
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        await settle()
        #expect(commands.isShown)
        #expect(commands.isEnabled == false)
        // A session: on. A page that is not a session's: dim again.
        frames.send(Self.session)
        await settle()
        #expect(commands.isShown)
        #expect(commands.isEnabled)
        frames.send("not-a-frame")
        await settle()
        #expect(commands.isShown)
        #expect(commands.isEnabled == false)
        frames.send(Self.session)
        await settle()
        #expect(commands.isEnabled)
        // One click opens the window for the session in the main window.
        commands.ask()
        #expect(opened == 1)
        // Switched off, or the key removed: gone.
        rig.model.setOn(false)
        await settle()
        #expect(commands.isShown == false)
        #expect(commands.isEnabled == false)
        rig.model.setOn(true)
        await settle()
        #expect(commands.isShown && commands.isEnabled)
        rig.model.removeKey()
        await settle()
        #expect(commands.isShown == false)
        #expect(commands.isEnabled == false)
    }

    @Test func aDemoShowsTheButtonDimAndOpensNothing() async {
        let rig = Rig()
        rig.model.setOn(true)
        rig.model.saveKey(madeUpModelKey)
        await rig.waitForList()
        let commands = AskCommands(model: rig.model, frames: CurrentValueSubject<String?, Never>(Self.session), demo: true, open: {})
        await settle()
        #expect(commands.isShown)
        #expect(commands.isEnabled == false)
    }

    @Test func theToolbarButtonIsDrawnLikeResultsIsAndNamedForVoiceOver() {
        #expect(AskToolbar.label == "Ask Another Model")
        #expect(AskToolbar.help.hasPrefix(AskToolbar.label))
        // Results' help is a name, a colon and what it is for; so is this.
        #expect(AskToolbar.help.contains(": "))
        #expect(NSImage(systemSymbolName: AskToolbar.symbol, accessibilityDescription: nil) != nil, "\(AskToolbar.symbol)")
        let source = Self.source("AskModel/AskToolbarButton.swift")
        #expect(source.contains(".buttonStyle(ReadoutButtonStyle())"))
        #expect(source.contains(".accessibilityLabel(AskToolbar.label)"))
        #expect(source.contains(".help(AskToolbar.help)"))
        #expect(source.contains(".disabled(!isEnabled)"))
    }

    @Test func theToolbarHoldsTheButtonFirstOfTheThreeAndWrapsTheItemInItsCondition() {
        // The condition wraps the item itself (an item with nothing in it still gets a glass capsule), and the button
        // comes before Results, so Results, the Shelf and Specimens stay where they are when it comes and goes.
        let toolbar = Self.source("App/BenchApp.swift")
        let ask = toolbar.range(of: "if ask.isShown {")
        let button = toolbar.range(of: "AskToolbarButton(isEnabled: ask.isEnabled)")
        let results = toolbar.range(of: "ResultsToolbarButton()")
        let spacer = toolbar.range(of: "ToolbarSpacer(.fixed)")
        #expect(ask != nil && button != nil && results != nil && spacer != nil)
        if let spacer, let ask, let button, let results {
            #expect(spacer.lowerBound < ask.lowerBound)
            #expect(ask.lowerBound < button.lowerBound)
            #expect(button.lowerBound < results.lowerBound)
        }
        #expect(toolbar.contains("ToolbarItem {\n                        AskToolbarButton("))
    }

    @Test func theMainWindowsRightClickMenuHasNoAskItemAnyMore() {
        for file in ["Web/WebContainer.swift", "Web/TabContextMenu.swift", "AskModel/AskModelWindow.swift"] {
            let text = Self.source(file)
            for gone in ["askMenu", "AskMenu.insert", "askFromPage", "SelectionScript", "selectedText(limit"] {
                #expect(!text.contains(gone), "\(file): \(gone)")
            }
        }
        // The reference window's right-click keeps it.
        #expect(Self.source("Reference/ReferenceWindow.swift").contains("AskMenu.insert(into: menu"))
    }

    private static func source(_ relative: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)) ?? ""
    }

    @Test func theItemDoesWhatItSays() throws {
        let menu = NSMenu()
        var fired = 0
        AskMenu.insert(into: menu, available: true) { fired += 1 }
        let item = try #require(menu.items.first)
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
        #expect(fired == 1)
    }

    @Test func theWindowDoesNotOpenWhileItIsOff() {
        let controller = AskModelWindowController(available: { false })
        let subject = AskSubject(sessionID: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", title: "Plate reader QC",
                                 projectName: "Assay development", seed: "Which buffer?")
        #expect(controller.show(subject) == false)
        #expect(controller.window(for: subject.sessionID) == nil)
    }

    @Test func theReferenceWindowsTextMenuHasTheItemOnlyWhileItIsOnWithAKey() {
        let coordinator = ReferenceTextView.Coordinator()
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        view.string = "Use HEPES at 25 mM for the rerun."
        view.setSelectedRange(NSRange(location: 4, length: 5))
        var asked: [String?] = []
        coordinator.ask = { asked.append($0) }

        coordinator.available = { false }
        let off = NSMenu()
        off.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))
        coordinator.addAsk(to: off, in: view)
        #expect(off.items.map(\.title) == ["Copy"])

        coordinator.available = { true }
        let on = NSMenu()
        on.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))
        coordinator.addAsk(to: on, in: view)
        #expect(on.items.first?.title == "Ask Another Model\u{2026}")
        if let item = on.items.first { _ = (item.target as? NSObject)?.perform(item.action, with: item) }
        // It starts from the selection.
        #expect(asked == ["HEPES"])

        // A text view with no ask (the Ask window's own answer, a document) never has it.
        let plain = ReferenceTextView.Coordinator()
        plain.available = { true }
        let menu = NSMenu()
        plain.addAsk(to: menu, in: view)
        #expect(menu.items.isEmpty)
    }
}

// MARK: Source checks

/// What the AskModel folder's code does with the key, read from its text (comments left out): the checks that a
/// run can't make, since a line that logs the key or reaches the Keychain would only show when it ran.
struct AskSourceTests {
    private static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Bench/AskModel")

    /// Each file's code lines, by name.
    private static func code() -> [String: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Dictionary(uniqueKeysWithValues: names.filter { $0.hasSuffix(".swift") }.map { name in
            let text = (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            return (name, lines.joined(separator: "\n"))
        })
    }

    @Test func theFolderIsThere() {
        #expect(Set(Self.code().keys) == ["AnotherModel.swift", "AnotherModelClient.swift", "AnotherModelStream.swift",
                                          "AskModel.swift", "AskModelMenu.swift", "AskModelWindow.swift",
                                          "AskScrollFollow.swift", "AskToolbarButton.swift", "ModelPickerMenu.swift"])
    }

    @Test func nothingHereReachesTheKeychain() {
        for (name, text) in Self.code() {
            #expect(!text.contains("Keychain") && !text.contains("SecItem") && !text.contains("kSec"), "\(name)")
        }
    }

    @Test func theKeyIsInOneHeaderOfOneFileAndNoOtherFileNamesIt() {
        let named = Self.code().filter { $0.value.contains("Authorization") }.keys
        #expect(Set(named) == ["AnotherModelClient.swift"])
    }

    @Test func onlyOneLoggerExistsAndItPrintsWhatItIsGiven() {
        let code = Self.code()
        for (name, text) in code {
            #expect(!text.contains("print(") && !text.contains("NSLog(") && !text.contains("os_log(") && !text.contains("dump("), "\(name)")
            // The one Logger, in the one file, with one call.
            #expect(text.components(separatedBy: "Logger(").count - 1 == (name == "AnotherModel.swift" ? 1 : 0), "\(name)")
        }
        #expect(code["AnotherModel.swift"]?.components(separatedBy: "anotherModelLog.").count == 2)
    }

    @Test func theWindowAndTheRulesNeverHandTheKeyAnywhere() {
        // The key is read in `AnotherModel` for a request and goes no further than the client.
        for name in ["AskModel.swift", "AskModelWindow.swift", "AskModelMenu.swift", "AskToolbarButton.swift", "ModelPickerMenu.swift",
                     "AnotherModelStream.swift", "AskScrollFollow.swift"] {
            let text = Self.code()[name] ?? ""
            #expect(!text.contains("currentKey") && !text.contains("AnotherModelKey"), "\(name)")
        }
    }
}
