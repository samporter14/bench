// ScienceSwitchTests.swift — Capsid beside Claude Science's own app window
// (DESIGN.md, Daemon and sign-in; 1.0 spikes S1): which app is installed, what
// `status` says now, whether Capsid may start a daemon, where the tool is,
// which host the address uses, how it signs in and when it can't, the words it
// says, and the page's "now opens in its own window" dialog.
//
// Everything is the test's own: status JSON, bundle ids and which files
// "exist" are injected, so nothing here looks at this Mac's /Applications,
// runs the real `claude-science`, or starts, stops or restarts a daemon.
import Foundation
import JavaScriptCore
import Testing
@testable import Bench

// MARK: Made-up Macs

private let home = "/made-up/home"
private let tabApp = "/Applications/Claude Science.app"
private let userApp = home + "/Applications/Claude Science.app"
private let supportFolder = home + "/Library/Application Support/Claude Science"

/// A Mac with these apps (path to bundle id; nil is an app whose id can't be
/// read), and the support folder there or not. `asked` records every path the
/// detection looked at.
private final class MadeUpMac: @unchecked Sendable {
    private let apps: [String: String?]
    private let support: Bool
    private let lock = NSLock()
    private var asked: [String] = []

    init(apps: [String: String?] = [:], support: Bool = false) {
        self.apps = apps
        self.support = support
    }

    var looked: [String] {
        lock.lock(); defer { lock.unlock() }
        return asked
    }

    private func note(_ path: String) {
        lock.lock(); asked.append(path); lock.unlock()
    }

    var probe: ScienceInstallProbe {
        ScienceInstallProbe(
            home: home,
            appExists: { [self] path in note(path); return apps.keys.contains(path) },
            bundleID: { [self] path in note(path); return apps[path] ?? nil },
            folderExists: { [self] path in note(path); return support && path == supportFolder })
    }

    func install() -> ScienceInstall { ScienceInstall.detect(probe) }
}

private let operon = "com.anthropic.operon"
private let ownWindow = "com.anthropic.claudescience"
private let safariWebApp = "com.apple.Safari.WebApp.0A1B2C3D-0000-4000-8000-000000000001"

// MARK: Detection

struct ScienceInstallDetectionTests {
    @Test func theLauncherThatOpensATabIsABrowserTab() {
        let install = MadeUpMac(apps: [tabApp: operon]).install()
        #expect(install.opens == .browserTab)
        #expect(install.opensPhrase == "a browser tab")
        #expect(install.bundledCLI == nil)
    }

    @Test func theAppWithItsOwnWindowIsItsOwnWindow() {
        let install = MadeUpMac(apps: [tabApp: ownWindow]).install()
        #expect(install.opens == .ownWindow)
        #expect(install.opensPhrase == "its own window")
        #expect(install.bundledCLI == "/Applications/Claude Science.app/Contents/Resources/bin/claude-science")
    }

    @Test func aSafariWebAppOfThatNameIsNotAnthropicsApp() {
        let install = MadeUpMac(apps: [userApp: safariWebApp]).install()
        #expect(install.opens == .notAnthropics)
        #expect(install.opensPhrase == "not Anthropic's app")
        #expect(install.launchers.first?.isSafariWebApp == true)
        #expect(install.bundledCLI == nil)
        #expect(install.anthropicApp == nil)
    }

    @Test func anyOtherBundleIdIsNotAnthropicsAppEither() {
        #expect(MadeUpMac(apps: [tabApp: "com.example.other"]).install().opens == .notAnthropics)
        // An app whose id can't be read says nothing.
        #expect(MadeUpMac(apps: [tabApp: nil]).install().opens == .notAnthropics)
    }

    @Test func noAppIsNoApp() {
        let install = MadeUpMac().install()
        #expect(install.opens == .notInstalled)
        #expect(install.opensPhrase == "no Claude Science app found")
        #expect(install.anthropicApp == nil)
    }

    @Test func bothPlacesAreLookedAtAndTheOwnWindowAppWinsWherever() {
        // A Safari web app in the home folder doesn't hide the launcher.
        #expect(MadeUpMac(apps: [tabApp: operon, userApp: safariWebApp]).install().opens == .browserTab)
        // The app with its own window in either place means never starting a daemon.
        #expect(MadeUpMac(apps: [tabApp: operon, userApp: ownWindow]).install().opens == .ownWindow)
        #expect(MadeUpMac(apps: [tabApp: ownWindow, userApp: operon]).install().opens == .ownWindow)
        let both = MadeUpMac(apps: [tabApp: operon, userApp: ownWindow]).install()
        #expect(both.bundledCLI == userApp + "/Contents/Resources/bin/claude-science")
        #expect(both.anthropicApp?.path == userApp)
    }

    @Test func theTwoPlacesAreApplicationsThenTheHomeFoldersApplications() {
        #expect(ScienceInstall.appPaths(home: home) == [tabApp, userApp])
    }

    @Test func theSupportFolderIsOnlyLookedForNeverOpened() {
        let there = MadeUpMac(apps: [tabApp: operon], support: true)
        #expect(there.install().supportFolderPresent)
        #expect(!MadeUpMac(apps: [tabApp: operon]).install().supportFolderPresent)
        // The one folder, by presence: nothing is asked of anything inside it.
        #expect(there.looked.filter { $0.contains("Application Support") } == [supportFolder])
    }

    @Test func theLiveProbeReadsTheBundleIdFromThePlistNotFromTheBundleCache() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("Claude Science.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let write = { (id: String) throws in
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Info.plist"))
        }
        let path = folder.appendingPathComponent("Claude Science.app").path
        try write(operon)
        #expect(ScienceInstallProbe.live.bundleID(path) == operon)
        // The switch is an update in place: the next look sees the new id.
        try write(ownWindow)
        #expect(ScienceInstallProbe.live.bundleID(path) == ownWindow)
        #expect(ScienceInstallProbe.live.bundleID(folder.appendingPathComponent("Missing.app").path) == nil)
    }
}

// MARK: Diagnostics lines for the install

struct ScienceInstallLinesTests {
    @Test func aBrowserTabInstall() {
        let lines = MadeUpMac(apps: [tabApp: operon]).install().lines(home: home)
        #expect(lines == [
            "• Claude Science opens in: a browser tab",
            "  /Applications/Claude Science.app: Anthropic's launcher, which opens a browser tab",
            "  its app folder (~/Library/Application Support/Claude Science): not there",
        ])
    }

    @Test func anOwnWindowInstallWithItsFolder() {
        let lines = MadeUpMac(apps: [userApp: ownWindow], support: true).install().lines(home: home)
        #expect(lines == [
            "• Claude Science opens in: its own window",
            "  ~/Applications/Claude Science.app: Anthropic's app, with its own window",
            "  its app folder (~/Library/Application Support/Claude Science): there",
        ])
    }

    @Test func aSafariWebAppDoesNotPrintItsRandomId() {
        let lines = MadeUpMac(apps: [userApp: safariWebApp]).install().lines(home: home)
        #expect(lines.first == "• Claude Science opens in: not Anthropic's app")
        #expect(lines.contains("  ~/Applications/Claude Science.app: a Safari web app, not Anthropic's app"))
        #expect(!lines.joined().contains("0A1B2C3D"))
    }

    @Test func anotherAppNamesItsIdAndAnUnreadableOneSaysSo() {
        #expect(MadeUpMac(apps: [tabApp: "com.example.other"]).install().lines(home: home)
            .contains("  /Applications/Claude Science.app: not Anthropic's app (com.example.other)"))
        #expect(MadeUpMac(apps: [tabApp: nil]).install().lines(home: home)
            .contains("  /Applications/Claude Science.app: an app whose identity couldn't be read"))
    }

    @Test func noAppSaysSoAndStillSaysAboutTheFolder() {
        #expect(MadeUpMac().install().lines(home: home) == [
            "• Claude Science opens in: no Claude Science app found",
            "  its app folder (~/Library/Application Support/Claude Science): not there",
        ])
    }
}

// MARK: Opening the app

@MainActor
@Suite(.serialized)
struct ScienceAppOpeningTests {
    @Test func startingItsServerOpensTheAppInTheBackgroundAndShowingItBringsItForward() {
        let saved = ScienceApp.opener
        defer { ScienceApp.opener = saved }
        var opened: [(String, Bool)] = []
        ScienceApp.opener = { url, activates in opened.append((url.path, activates)) }
        let install = MadeUpMac(apps: [tabApp: ownWindow]).install()
        #expect(ScienceApp.open(.startServer, install: install))
        #expect(ScienceApp.open(.show, install: install))
        #expect(opened.map(\.0) == ["/Applications/Claude Science.app", "/Applications/Claude Science.app"])
        #expect(opened.map(\.1) == [false, true])
    }

    @Test func theOwnWindowAppIsOpenedBeforeTheLauncher() {
        let saved = ScienceApp.opener
        defer { ScienceApp.opener = saved }
        var paths: [String] = []
        ScienceApp.opener = { url, _ in paths.append(url.path) }
        ScienceApp.open(.show, install: MadeUpMac(apps: [tabApp: operon, userApp: ownWindow]).install())
        #expect(paths == [userApp])
    }

    @Test func aSafariWebAppOrNothingIsNeverOpened() {
        let saved = ScienceApp.opener
        defer { ScienceApp.opener = saved }
        var opened = 0
        ScienceApp.opener = { _, _ in opened += 1 }
        #expect(!ScienceApp.open(.show, install: MadeUpMac(apps: [userApp: safariWebApp]).install()))
        #expect(!ScienceApp.open(.startServer, install: MadeUpMac().install()))
        #expect(opened == 0)
    }
}

// MARK: What status says

struct StatusSwitchParsingTests {
    private func parse(_ json: String) throws -> CLIStatus {
        try parseCLIStatus(Data(json.utf8), exitStatus: 0)
    }

    @Test func anOldStatusStillParsesAndSaysNothingOfTheNewKeys() throws {
        let status = try parse(#"{"running": true, "port": 9100, "version": "0.1.63", "pid": 4321, "daemon": {"active_frames": 2, "data_dir": "/tmp/made-up"}}"#)
        #expect(status.port == 9100)
        #expect(status.pid == 4321)
        #expect(status.launchContext == nil)
        #expect(status.boot == nil)
        #expect(status.urlHost == nil)
        #expect(status.requireToken == nil)
        #expect(!status.isAppChild)
    }

    @Test func theAppsStatusIsReadInFull() throws {
        let status = try parse("""
        {"running": true, "port": 51234, "version": "0.1.70", "pid": 777,
         "daemon": {"launch_context": "app-child", "boot": "serving", "url_host": "127.0.0.1", "require_token": false,
                    "active_frames": 0, "active_conversations": 0, "data_dir": "/tmp/made-up"}}
        """)
        #expect(status.launchContext == "app-child")
        #expect(status.boot == "serving")
        #expect(status.urlHost == "127.0.0.1")
        #expect(status.requireToken == false)
        #expect(status.isAppChild)
        #expect(status.port == 51234)
    }

    @Test func aMissingPortIsUnknownNotTheOldDefault() throws {
        let status = try parse(#"{"running": true, "version": "0.1.70", "daemon": {"launch_context": "app-child"}}"#)
        #expect(status.port == nil)
    }

    @Test(arguments: [
        #""8765""#, "8765.5", "true", "false", "0", "-1", "65536", "70000", "null", "[]", #"{"n": 1}"#,
    ])
    func aPortThatIsNotAWholeNumberInRangeIsUnknown(_ port: String) throws {
        #expect(try parse(#"{"running": true, "port": \#(port)}"#).port == nil)
    }

    @Test(arguments: ["1", "80", "8765", "65535"])
    func aWholePortInRangeIsRead(_ port: String) throws {
        #expect(try parse(#"{"running": true, "port": \#(port)}"#).port == Int(port))
    }

    @Test func eachNewKeyIsOfExactlyItsTypeOrIgnored() throws {
        let wrong = try parse("""
        {"running": true, "port": 9100,
         "daemon": {"launch_context": 7, "boot": true, "url_host": ["127.0.0.1"], "require_token": "yes"}}
        """)
        #expect(wrong.launchContext == nil && wrong.boot == nil && wrong.urlHost == nil && wrong.requireToken == nil)
        // A number is not a boolean, whatever Foundation does with 0 and 1.
        #expect(try parse(#"{"running": true, "daemon": {"require_token": 1}}"#).requireToken == nil)
        #expect(try parse(#"{"running": true, "daemon": {"require_token": 0}}"#).requireToken == nil)
        #expect(try parse(#"{"running": true, "daemon": {"require_token": true}}"#).requireToken == true)
        #expect(try parse(#"{"running": true, "daemon": {"require_token": false}}"#).requireToken == false)
        // Wrong typing doesn't stop the rest from being read.
        #expect(wrong.port == 9100)
    }

    @Test func theWordsAreShortPrintableAndLowercased() throws {
        let status = try parse(#"{"running": true, "daemon": {"launch_context": "App-Child", "url_host": " LOCALHOST "}}"#)
        #expect(status.launchContext == "app-child")
        #expect(status.urlHost == "localhost")
        #expect(status.isAppChild)
        let junk = try parse(#"{"running": true, "daemon": {"launch_context": "two words", "boot": "", "url_host": "\#(String(repeating: "a", count: 41))"}}"#)
        #expect(junk.launchContext == nil && junk.boot == nil && junk.urlHost == nil)
        #expect(try parse(#"{"running": true, "daemon": {"boot": "café"}}"#).boot == nil)
    }

    @Test func aStoppedDaemonStillSaysNotRunningWhateverElseItCarries() {
        #expect(throws: ScienceError.daemonNotRunning) {
            try parseCLIStatus(Data(#"{"running": false, "daemon": {"launch_context": "app-child"}}"#.utf8), exitStatus: 0)
        }
    }
}

// MARK: Starting a daemon

struct StartPlanTests {
    private static func running(_ context: String? = nil, port: Int? = 8765) -> CLIStatus {
        CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "0.1.70", port: port, launchContext: context)
    }

    private static let installs: [ScienceInstall.Opens] = [.browserTab, .ownWindow, .notAnthropics, .notInstalled]
    private static let contexts: [String?] = [nil, "app-child", "cli", "detached"]

    @Test func aRunningDaemonIsSignedInToAndNothingIsStarted() {
        for install in Self.installs {
            for context in Self.contexts {
                for handover in [false, true] {
                    let status = Self.running(context)
                    #expect(StartPlan.decide(.running(status), install: install, lastLaunchContext: context, handoverSeen: handover)
                            == .attach(status), "\(install) \(String(describing: context)) \(handover)")
                }
            }
        }
    }

    @Test func aStatusThatCouldNotBeReadStartsNothing() {
        for install in Self.installs {
            for context in Self.contexts {
                #expect(StartPlan.decide(.failed, install: install, lastLaunchContext: context, handoverSeen: false) == .giveUp)
            }
        }
    }

    @Test func theLauncherThatOpensATabStillStartsOneWhenNothingRuns() {
        for install in [ScienceInstall.Opens.browserTab, .notAnthropics, .notInstalled] {
            #expect(StartPlan.decide(.notRunning, install: install, lastLaunchContext: nil, handoverSeen: false) == .serve, "\(install)")
            // A daemon some other way started, before, is no reason to wait.
            #expect(StartPlan.decide(.notRunning, install: install, lastLaunchContext: "cli", handoverSeen: false) == .serve)
        }
    }

    @Test func theOwnWindowAppMeansNeverStartingOne() {
        for context in Self.contexts {
            for handover in [false, true] {
                #expect(StartPlan.decide(.notRunning, install: .ownWindow, lastLaunchContext: context, handoverSeen: handover)
                        == .waitForApp(.ownWindowApp))
            }
        }
    }

    @Test func aDaemonThatWasTheAppsChildMeansNeverStartingOneEvenAfterTheAppQuit() {
        for install in [ScienceInstall.Opens.browserTab, .notAnthropics, .notInstalled] {
            #expect(StartPlan.decide(.notRunning, install: install, lastLaunchContext: "app-child", handoverSeen: false)
                    == .waitForApp(.appChild))
        }
    }

    @Test func theHandoverDialogMeansNeverStartingOneThisRun() {
        for install in [ScienceInstall.Opens.browserTab, .notAnthropics, .notInstalled] {
            #expect(StartPlan.decide(.notRunning, install: install, lastLaunchContext: nil, handoverSeen: true) == .waitForApp(.handover))
        }
    }

    @Test func serveIsPlannedOnlyWhenNothingElseSaysNo() {
        // Every combination, against a plain restatement of the rule.
        let answers: [StatusAnswer] = [.running(Self.running()), .notRunning, .failed]
        for answer in answers {
            for install in Self.installs {
                for context in Self.contexts {
                    for handover in [false, true] {
                        let plan = StartPlan.decide(answer, install: install, lastLaunchContext: context, handoverSeen: handover)
                        let mayServe = answer == .notRunning && install != .ownWindow && context != "app-child" && !handover
                        #expect((plan == .serve) == mayServe, "\(answer) \(install) \(String(describing: context)) \(handover)")
                    }
                }
            }
        }
    }

    @Test func theAppOwnsTheServerAnswerIsTemporaryAndSaysWhatToDo() {
        #expect(DaemonError.appOwnsServer.sentence == "Claude Science runs its own server now. Open Claude Science to start it.")
        #expect(DaemonError.appOwnsServer.isTemporary)
        // A daemon with no port is one still coming up; Capsid guesses no port.
        #expect(DaemonError.noPort.isTemporary)
        #expect(DaemonError.noPort.sentence == "Claude Science is running but hasn't said which port it uses yet.")
        // The old failures keep their old rules.
        #expect(!DaemonError.cliMissing.isTemporary && !DaemonError.launchFailed("no").isTemporary)
    }
}

// MARK: Where the tool is

struct CLIPathOrderTests {
    private let userBin = home + "/.local/bin/claude-science"
    private let dataBin = home + "/.claude-science/bin/claude-science"
    private let brewBin = "/opt/homebrew/bin/claude-science"
    private let localBin = "/usr/local/bin/claude-science"

    @Test func withTheLauncherThatOpensATabTheOrderIsWhatItAlwaysWas() {
        let tab = MadeUpMac(apps: [tabApp: operon]).install()
        #expect(cliCandidates(home: home, install: tab) == [userBin, dataBin, brewBin, localBin])
        #expect(cliCandidates(home: home, install: MadeUpMac().install()) == [userBin, dataBin, brewBin, localBin])
        #expect(cliCandidates(home: home, install: MadeUpMac(apps: [userApp: safariWebApp]).install()) == [userBin, dataBin, brewBin, localBin])
    }

    @Test func onceTheOwnWindowAppIsInstalledItsOwnCopyComesFirst() {
        let own = MadeUpMac(apps: [tabApp: ownWindow]).install()
        #expect(cliCandidates(home: home, install: own) == [tabApp + "/Contents/Resources/bin/claude-science", userBin, dataBin, brewBin, localBin])
        let inHome = MadeUpMac(apps: [userApp: ownWindow]).install()
        #expect(cliCandidates(home: home, install: inHome).first == userApp + "/Contents/Resources/bin/claude-science")
    }

    @Test func theFirstExecutableOneIsTheTool() {
        let own = MadeUpMac(apps: [tabApp: ownWindow]).install()
        let bundled = tabApp + "/Contents/Resources/bin/claude-science"
        // Everything exists: the app's copy wins with the own-window app, the old place with the launcher.
        #expect(resolveCLI(install: own, isExecutable: { _ in true })?.path == bundled)
        let tab = MadeUpMac(apps: [tabApp: operon]).install()
        #expect(resolveCLI(install: tab, isExecutable: { _ in true })?.path == NSHomeDirectory() + "/.local/bin/claude-science")
        // The app's copy missing falls back to the old place.
        #expect(resolveCLI(install: own, isExecutable: { $0 != bundled })?.path == NSHomeDirectory() + "/.local/bin/claude-science")
        // Only the app's copy exists with the launcher: it isn't looked for there.
        #expect(resolveCLI(install: tab, isExecutable: { $0 == tabApp + "/Contents/Resources/bin/claude-science" || $0 == "/opt/homebrew/bin/claude-science" })?.path
                == "/opt/homebrew/bin/claude-science")
    }
}

// MARK: The host

/// Settings kept in memory: `LastSession` only reads, writes and removes
/// strings, so these tests need no suite on disk (a suite leaves a plist in
/// ~/Library/Preferences).
private final class MemoryDefaults: UserDefaults {
    nonisolated(unsafe) private var store: [String: Any] = [:]

    convenience init() { self.init(suiteName: nil)! }

    override func string(forKey defaultName: String) -> String? { store[defaultName] as? String }
    override func set(_ value: Any?, forKey defaultName: String) { store[defaultName] = value }
    override func removeObject(forKey defaultName: String) { store.removeValue(forKey: defaultName) }
}

@MainActor
struct CanonicalHostTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func theDaemonThatMovedTo127001IsLoadedFromThere() {
        #expect(WebContainer.canonical(url("http://localhost:51234/projects/p/frames/f?x=1#top"), host: "127.0.0.1").absoluteString
                == "http://127.0.0.1:51234/projects/p/frames/f?x=1#top")
    }

    @Test func andOneOnLocalhostIsLoadedFromLocalhost() {
        #expect(WebContainer.canonical(url("http://127.0.0.1:8765/"), host: "localhost").absoluteString == "http://localhost:8765/")
        // As it always was, with no host named.
        #expect(WebContainer.canonical(url("http://127.0.0.1:8765/a")).absoluteString == "http://localhost:8765/a")
    }

    @Test func aLoopbackAddressAlreadyOnTheHostIsLeftAlone() {
        #expect(WebContainer.canonical(url("http://localhost:8765/a"), host: "localhost").absoluteString == "http://localhost:8765/a")
        #expect(WebContainer.canonical(url("http://127.0.0.1:8765/a"), host: "127.0.0.1").absoluteString == "http://127.0.0.1:8765/a")
    }

    @Test func nothingThatIsNotLoopbackIsRewritten() {
        for text in ["https://example.com/a", "http://localhost.example.com:8765/", "http://192.168.1.2:8765/", "bench://open?url=x"] {
            #expect(WebContainer.canonical(url(text), host: "127.0.0.1") == url(text), "\(text)")
            #expect(WebContainer.canonical(url(text), host: "localhost") == url(text), "\(text)")
        }
    }

    @Test func theHostComesFromTheStatusWhenItNamesOneOfTheTwoLoopbackNames() {
        #expect(DaemonHost.name(for: nil) == "localhost")
        #expect(DaemonHost.name(for: "localhost") == "localhost")
        #expect(DaemonHost.name(for: "127.0.0.1") == "127.0.0.1")
        #expect(DaemonHost.name(for: "LOCALHOST") == "localhost")
        for other in ["0.0.0.0", "::1", "[::1]", "my-mac.local", "example.com", ""] {
            #expect(DaemonHost.name(for: other) == "localhost", "\(other)")
        }
    }

    @Test func aLinkBuiltForTheOldHostAndPortMovesToTheNewOnes() {
        let early = url("http://localhost:8765/projects/p/frames/f")
        let moved = WebContainer.moving(early, toPort: 51234)
        #expect(WebContainer.canonical(moved, host: "127.0.0.1").absoluteString == "http://127.0.0.1:51234/projects/p/frames/f")
    }

    @Test func theRememberedSessionReopensOnTheDaemonsHost() async throws {
        let defaults = MemoryDefaults()
        let id = madeUpID(3)
        defaults.set("proj_a/\(id)", forKey: SettingsKey.lastSession)
        let last = LastSession(defaults: defaults, isDemo: false)
        let onNumeric = await last.reopenURL(port: 51234, host: "127.0.0.1", isKnown: { _ in true })
        #expect(onNumeric?.absoluteString == "http://127.0.0.1:51234/projects/proj_a/frames/\(id)")
        let usual = await last.reopenURL(port: 8765, isKnown: { _ in true })
        #expect(usual?.absoluteString == "http://localhost:8765/projects/proj_a/frames/\(id)")
    }

    @Test func theSignInStepIsNotWhereTheUserIs() async throws {
        let defaults = MemoryDefaults()
        let id = madeUpID(4)
        let last = LastSession(defaults: defaults, isDemo: false)
        last.note(url: URL(string: "http://127.0.0.1:51234/projects/proj_a/frames/\(id)"), daemonPort: 51234)
        #expect(last.route == .init(projectID: "proj_a", frameID: id))
        // Passing through the daemon's own sign-in page forgets nothing.
        last.note(url: URL(string: "http://127.0.0.1:51234/api/me"), daemonPort: 51234)
        #expect(last.route == .init(projectID: "proj_a", frameID: id))
        // Home does, as before.
        last.note(url: URL(string: "http://127.0.0.1:51234/"), daemonPort: 51234)
        #expect(last.route == nil)
    }

    @Test func eitherNameIsTheDaemonsOwnOriginToTheRouter() {
        // The router classifies both names as the daemon's, so a daemon on
        // 127.0.0.1 is still "Claude Science" and never a link to a Browser window.
        #expect(WebRoute.classify(url("http://127.0.0.1:51234/"), daemonPort: 51234) == .daemon)
        #expect(WebRoute.classify(url("http://localhost:51234/"), daemonPort: 51234) == .daemon)
    }
}

// MARK: Signing in

struct SignInPlanTests {
    @Test func aDaemonThatRequiresATokenIsOnlyReadBesideTheAppWithNoCode() {
        #expect(SignInPlan.decide(requireToken: true, appOwned: true, nonce: nil) == .readOnly(.tokenRequired))
        // With a code, beside the app, its own page signs in.
        #expect(SignInPlan.decide(requireToken: true, appOwned: true, nonce: "code-1") == .apiMe(nonce: "code-1"))
    }

    @Test func theTabDaemonThatReportsATokenStillSignsInAsItAlwaysDid() {
        // Found on Sam's Mac: the browser-tab daemon says `require_token: true`,
        // and the first cut went read-only on it.
        #expect(SignInPlan.decide(requireToken: true, appOwned: false, nonce: "code-1") == .page(nonce: "code-1"))
        #expect(SignInPlan.decide(requireToken: true, appOwned: false, nonce: nil) == .page(nonce: nil))
    }

    @Test func theLauncherThatOpensATabSignsInAsItAlwaysDid() {
        for token in [nil, false] as [Bool?] {
            #expect(SignInPlan.decide(requireToken: token, appOwned: false, nonce: "code-1") == .page(nonce: "code-1"))
            // With no code it loads anyway: the cookie from last time may still work.
            #expect(SignInPlan.decide(requireToken: token, appOwned: false, nonce: nil) == .page(nonce: nil))
        }
    }

    @Test func aDaemonTheAppStartedSignsInThroughItsOwnPageWhenItGivesACode() {
        for token in [nil, false] as [Bool?] {
            #expect(SignInPlan.decide(requireToken: token, appOwned: true, nonce: "code-1") == .apiMe(nonce: "code-1"))
        }
    }

    @Test func withoutACodeTheAppsDaemonIsTriedWithTheCookieOnce() {
        #expect(SignInPlan.decide(requireToken: nil, appOwned: true, nonce: nil) == .page(nonce: nil))
    }

    @Test func aRefusalWithNoCodeToTryAgainWithEndsInReadOnlyBesideTheAppAndInARetryOtherwise() {
        #expect(SignInPlan.outcomeWithoutCode(appOwned: true) == .readOnly(.noCode))
        #expect(SignInPlan.outcomeWithoutCode(appOwned: false) == .retryLater)
    }

    @Test func whoOwnsTheDaemon() {
        let child = CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "1", port: 1, launchContext: "app-child")
        let plain = CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "1", port: 1)
        #expect(SignInPlan.appOwned(daemon: child, install: .browserTab, handoverSeen: false))
        #expect(SignInPlan.appOwned(daemon: plain, install: .ownWindow, handoverSeen: false))
        #expect(SignInPlan.appOwned(daemon: plain, install: .browserTab, handoverSeen: true))
        #expect(SignInPlan.appOwned(daemon: nil, install: .ownWindow, handoverSeen: false))
        #expect(!SignInPlan.appOwned(daemon: plain, install: .browserTab, handoverSeen: false))
        #expect(!SignInPlan.appOwned(daemon: nil, install: .notInstalled, handoverSeen: false))
        #expect(!SignInPlan.appOwned(daemon: plain, install: .notAnthropics, handoverSeen: false))
    }

    @Test func theSignInPageIsAskedForOnTheDaemonsHostAndPort() throws {
        #expect(SignInPlan.apiMeURL(host: "127.0.0.1", port: 51234, nonce: "abc-123")?.absoluteString
                == "http://127.0.0.1:51234/api/me?nonce=abc-123")
        let url = try #require(SignInPlan.apiMeURL(host: "localhost", port: 8765, nonce: "x"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "nonce", value: "x")])
    }

    @Test func onlyThatOneAddressOnTheLoopbackIsTheSignInStep() {
        for text in ["http://localhost:8765/api/me", "http://127.0.0.1:51234/api/me?nonce=abc", "http://localhost:8765/api/me#x"] {
            #expect(SignInPlan.isSignInStep(URL(string: text)), "\(text)")
        }
        for text in ["http://localhost:8765/api/mex", "http://localhost:8765/api/me/other", "http://localhost:8765/", "http://localhost:8765/api/usage",
                     "https://example.com/api/me", "http://192.168.1.2:8765/api/me"] {
            #expect(!SignInPlan.isSignInStep(URL(string: text)), "\(text)")
        }
        #expect(!SignInPlan.isSignInStep(nil))
    }

    @Test func theReasonsAreSaidPlainly() {
        #expect(ReadOnlyReason.tokenRequired.phrase == "the daemon requires a token")
        #expect(ReadOnlyReason.noCode.phrase == "the daemon gave no sign-in code")
    }
}

// MARK: The words

struct CompanionTextTests {
    @Test func theSentencesAreTheBriefsWords() {
        #expect(CompanionSentence.waitingForApp == "Claude Science runs its own server now. Open Claude Science to start it.")
        #expect(CompanionSentence.readOnly
                == "Capsid can't sign in to Claude Science's own server. Everything from your sessions' database keeps working; actions open Claude Science.")
        #expect(CompanionSentence.handover == "Claude Science now opens in its own window. Capsid keeps working beside it.")
        #expect(CompanionSentence.openButton == "Open Claude Science")
    }

    @Test func theHandoverCardSaysWhatStaysAndWhatChanged() {
        let notice = Handover.notice
        #expect(notice.id == "handover-own-window")
        #expect(notice.caption == "Claude Science")
        #expect(notice.title == "Claude Science now opens in its own window")
        #expect(notice.detail == "Capsid keeps working beside it. It no longer starts Claude Science's server: open Claude Science to start it.")
        #expect(notice.action == .none)
        #expect(notice.lifetime == .seconds(20))
    }

    @Test func theReadOnlyCardSaysItOnceInTwoLines() {
        let notice = CompanionSentence.readOnlyNotice
        #expect(notice.title == "Capsid can't sign in to Claude Science's own server")
        #expect(notice.detail == "Everything from your sessions' database keeps working; actions open Claude Science.")
        #expect(notice.action == .none)
    }

    @Test func theVoiceIsPlainNoExclamationMarksSentenceCase() {
        let all = [CompanionSentence.waitingForApp, CompanionSentence.readOnly, CompanionSentence.handover,
                   CompanionSentence.handoverChanged, CompanionSentence.openButton, DaemonError.noPort.sentence]
        for sentence in all {
            #expect(!sentence.contains("!"), "\(sentence)")
            #expect(sentence.first?.isUppercase == true, "\(sentence)")
        }
    }
}

// MARK: The handover

@MainActor
struct HandoverTests {
    private final class Effects {
        var stops = 0
        var posted: [LabNotice] = []
        var watches = 0
    }

    private func make(_ effects: Effects) -> Handover {
        Handover(stopRetries: { effects.stops += 1 }, post: { effects.posted.append($0) }, watchForDaemon: { effects.watches += 1 })
    }

    @Test func theDialogStopsTheTriesPostsOneCardAndWatchesForTheNewDaemon() {
        let effects = Effects()
        let handover = make(effects)
        #expect(!handover.seen && !handover.waitingForNewDaemon)
        handover.dialogShown()
        #expect(handover.seen && handover.waitingForNewDaemon)
        #expect(effects.stops == 1)
        #expect(effects.posted.map(\.id) == ["handover-own-window"])
        #expect(effects.watches == 1)
    }

    @Test func theDialogShownAgainChangesNothing() {
        let effects = Effects()
        let handover = make(effects)
        handover.dialogShown()
        handover.waitingForNewDaemon = false
        for _ in 0..<5 { handover.dialogShown() }
        #expect(effects.stops == 1 && effects.posted.count == 1 && effects.watches == 1)
        #expect(!handover.waitingForNewDaemon)
    }

    @Test func aDaemonIsNewWhenItsProcessPortOrStarterChanged() {
        func status(pid: Int32?, port: Int?, context: String?) -> CLIStatus {
            CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "1", port: port, pid: pid, launchContext: context)
        }
        let old = status(pid: 100, port: 8765, context: nil)
        #expect(!Handover.isNewDaemon(old, than: old))
        #expect(Handover.isNewDaemon(status(pid: 101, port: 8765, context: nil), than: old))
        #expect(Handover.isNewDaemon(status(pid: 100, port: 51234, context: nil), than: old))
        #expect(Handover.isNewDaemon(status(pid: 100, port: 8765, context: "app-child"), than: old))
        #expect(Handover.isNewDaemon(old, than: nil))
    }

    @Test func theWatchSignsInToTheNewDaemonOnceAndSkipsTheOldOneStillShuttingDown() async {
        func status(pid: Int32, port: Int, context: String? = nil) -> CLIStatus {
            CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "1", port: port, pid: pid, launchContext: context)
        }
        let signedIn = status(pid: 100, port: 8765)
        let newOne = status(pid: 200, port: 51234, context: "app-child")
        var answers: [CLIStatus?] = [signedIn, nil, signedIn, newOne, newOne]
        var attached: [CLIStatus] = []
        var waits: [Duration] = []
        var pending = true
        // The same shape the window builds: the status asked for, kept only when it is a different daemon.
        let watch = StartRetry(
            probe: {
                guard !answers.isEmpty, let now = answers.removeFirst() else { return nil }
                return Handover.isNewDaemon(now, than: signedIn) ? now : nil
            },
            wait: { waits.append($0); await Task.yield() },
            stillFailed: { pending },
            attach: { attached.append($0); pending = false })
        watch.begin()
        for _ in 0..<500 where watch.isTrying { await Task.yield() }
        #expect(attached == [newOne])
        #expect(waits == [.seconds(5), .seconds(10), .seconds(20), .seconds(40)])
        // It asked four times, and not again once it had signed in.
        #expect(answers.count == 1)
        #expect(!watch.isTrying)
    }

    @Test func aMessageCountsOnlyFromTheDaemonsOwnMainFrameSayingShown() {
        func accepts(main: Bool = true, scheme: String? = "http", host: String? = "localhost", port: Int? = 8765,
                     daemon: Int? = 8765, body: Any = ["shown": true]) -> Bool {
            HandoverWatch.accepts(isMainFrame: main, scheme: scheme, host: host, port: port, daemonPort: daemon, body: body)
        }
        #expect(accepts())
        #expect(accepts(host: "127.0.0.1"))
        #expect(!accepts(main: false))
        #expect(!accepts(scheme: "https"))
        #expect(!accepts(host: "example.com"))
        #expect(!accepts(port: 9000))
        #expect(!accepts(daemon: nil))
        #expect(!accepts(body: ["shown": false]))
        #expect(!accepts(body: ["shown": "yes"]))
        #expect(!accepts(body: ["other": true]))
        #expect(!accepts(body: "shown"))
    }
}

// MARK: The page's side, in JavaScriptCore

/// The watch script on a made-up page: a `document` whose dialog is there or
/// not, a `MutationObserver` the test fires, and timers it runs by hand.
private final class HandoverPage {
    let context = JSContext()!

    init(host: String = "localhost", scheme: String = "http:", withHandler: Bool = true, dialogThere: Bool = false) {
        context.exceptionHandler = { _, exception in Issue.record("script threw: \(exception?.toString() ?? "?")") }
        context.evaluateScript("""
        var __posts = [], __timers = [], __observers = [], __asked = [];
        var __dialog = \(dialogThere ? "'\(HandoverPage.handoverText)'" : "null");
        var window = { webkit: { messageHandlers: \(withHandler ? "{ benchHandover: { postMessage: function (m) { __posts.push(JSON.stringify(m)); } } }" : "{}") } };
        var location = { protocol: "\(scheme)", hostname: "\(host)" };
        var document = {
          documentElement: {},
          querySelector: function (s) { __asked.push(s); return (s === '[data-testid="restarting-dialog"]' && __dialog) ? { textContent: __dialog } : null; }
        };
        function MutationObserver(cb) { this.cb = cb; this.on = false; __observers.push(this); }
        MutationObserver.prototype.observe = function () { this.on = true; };
        MutationObserver.prototype.disconnect = function () { this.on = false; };
        function setTimeout(f, ms) { __timers.push({ f: f, ms: ms }); return __timers.length; }
        function __mutate() { __observers.forEach(function (o) { if (o.on) o.cb([]); }); }
        function __runTimers() { var t = __timers; __timers = []; t.forEach(function (x) { x.f(); }); }
        """)
    }

    /// The dialog's words for the handover, and for any other restart (0.1.70's bundle).
    static let handoverText = "Claude Science now opens in its own windowYou can close this tab."
    static let restartText = "Restarting Claude Science\u{2026}Applying update."

    func load() { context.evaluateScript(HandoverWatch.script) }
    func set(dialog: Bool) { context.evaluateScript(dialog ? "__dialog = '\(Self.handoverText)';" : "__dialog = null;") }
    func set(dialogText: String) { context.evaluateScript("__dialog = '\(dialogText)';") }
    func mutate() { context.evaluateScript("__mutate();") }
    func runTimers() { context.evaluateScript("__runTimers();") }
    var posts: [String] { (context.evaluateScript("__posts")?.toArray() as? [String]) ?? [] }
    var asked: [String] { (context.evaluateScript("__asked")?.toArray() as? [String]) ?? [] }
    var timers: Int { Int(context.evaluateScript("__timers.length")?.toInt32() ?? -1) }
    var watching: Int { Int(context.evaluateScript("__observers.filter(function (o) { return o.on; }).length")?.toInt32() ?? -1) }
    var timerDelays: [Int] { (context.evaluateScript("__timers.map(function (t) { return t.ms; })")?.toArray() as? [NSNumber])?.map(\.intValue) ?? [] }
}

struct HandoverScriptTests {
    private static let dialog = #"[data-testid="restarting-dialog"]"#

    @Test func theDialogAppearingLaterIsSaidOnceAndTheWatchStops() {
        let page = HandoverPage()
        page.load()
        #expect(page.watching == 1)
        #expect(page.posts.isEmpty)
        // The page changes, the dialog isn't there: nothing.
        page.mutate(); page.runTimers()
        #expect(page.posts.isEmpty)
        // It appears.
        page.set(dialog: true)
        page.mutate(); page.runTimers()
        #expect(page.posts == [#"{"shown":true}"#])
        #expect(page.watching == 0)
        // And nothing more, however the page goes on changing.
        page.mutate(); page.runTimers(); page.mutate(); page.runTimers()
        #expect(page.posts.count == 1)
    }

    @Test func anyOtherRestartsDialogIsNotTheHandover() {
        let page = HandoverPage()
        page.load()
        // An update, a sign-out, another organisation: the same dialog, titled "Restarting Claude Science…".
        page.set(dialogText: HandoverPage.restartText)
        page.mutate(); page.runTimers()
        #expect(page.posts.isEmpty)
        #expect(page.watching == 1)
        // The handover's own title, later on the same page, is still heard.
        page.set(dialog: true)
        page.mutate(); page.runTimers()
        #expect(page.posts == [#"{"shown":true}"#])
    }

    @Test func aDialogAlreadyThereWhenTheScriptRunsIsSaidAtOnce() {
        let page = HandoverPage(dialogThere: true)
        page.load()
        #expect(page.posts == [#"{"shown":true}"#])
    }

    @Test func manyChangesAreOneCheckASecondLater() {
        let page = HandoverPage()
        page.load()
        for _ in 0..<50 { page.mutate() }
        #expect(page.timers == 1)
        #expect(page.timerDelays == [1000])
        page.runTimers()
        #expect(page.timers == 0)
        // And the next change schedules the next check.
        page.mutate()
        #expect(page.timers == 1)
    }

    @Test func itLooksForOneSelectorAndNothingElse() {
        let page = HandoverPage()
        page.load()
        page.mutate(); page.runTimers()
        let asked = Set(page.asked)
        #expect(asked == [Self.dialog])
        #expect(ScriptSelectors.in(HandoverWatch.script) == [Self.dialog])
    }

    @Test func itDoesNothingOffTheDaemonsOwnAddressOrWithoutItsHandler() {
        let remote = HandoverPage(host: "example.com", dialogThere: true)
        remote.load()
        #expect(remote.posts.isEmpty && remote.watching == 0)
        let secure = HandoverPage(scheme: "https:", dialogThere: true)
        secure.load()
        #expect(secure.posts.isEmpty && secure.watching == 0)
        let bare = HandoverPage(withHandler: false, dialogThere: true)
        bare.load()
        #expect(bare.posts.isEmpty && bare.watching == 0)
        let numeric = HandoverPage(host: "127.0.0.1", dialogThere: true)
        numeric.load()
        #expect(numeric.posts.count == 1)
    }

    @Test func runningItAgainOnTheSamePageDoesNotWatchTwice() {
        let page = HandoverPage()
        page.load()
        page.load()
        #expect(page.watching == 1)
    }
}

/// The same extraction the inventory tests use, kept here so this file stands alone.
private enum ScriptSelectors {
    static func `in`(_ script: String) -> Set<String> {
        let expression = try! NSRegularExpression(pattern: #"(?:querySelectorAll|querySelector|closest|getAttribute|hasAttribute)\(\s*(['"])(.*?)\1\s*\)"#)
        let range = NSRange(script.startIndex..., in: script)
        return Set(expression.matches(in: script, range: range).compactMap { found in
            Range(found.range(at: 2), in: script).map { String(script[$0]) }
        })
    }
}

// MARK: Opening while only reading

@MainActor
struct OpenWhileReadingTests {
    private func session(_ link: String?) -> SessionStatus {
        let now = Date()
        return SessionStatus(id: madeUpID(5), projectID: "proj_a", projectName: "Assay development", title: "Plate reader QC",
                             state: .needsInput, updatedAt: now, startedAt: now.addingTimeInterval(-60),
                             deepLink: link.flatMap(URL.init(string:)))
    }

    private final class Calls {
        var shown = 0, navigated: [URL] = [], clicked: [String] = [], inScience = 0
    }

    private func router(_ calls: Calls) -> Router {
        let router = Router()
        router.showWindow = { calls.shown += 1 }
        router.navigate = { calls.navigated.append($0) }
        router.clickWebNotification = { calls.clicked.append($0) }
        return router
    }

    @Test func withoutTheHookOpeningIsWhatItAlwaysWas() {
        let calls = Calls()
        let router = router(calls)
        router.open(session("http://localhost:8765/projects/proj_a/frames/\(madeUpID(5))"))
        router.open(URL(string: "http://localhost:8765/")!)
        router.open(WebNotification(id: "n1", title: "t", body: "b", tag: nil, requireInteraction: false, receivedAt: Date()))
        #expect(calls.shown == 3)
        #expect(calls.navigated.count == 2)
        #expect(calls.clicked == ["n1"])
    }

    @Test func whileOnlyReadingEveryOpenOpensClaudeScienceAndNothingElse() {
        let calls = Calls()
        let router = router(calls)
        router.openInScience = { calls.inScience += 1 }
        router.open(session("http://localhost:8765/projects/proj_a/frames/\(madeUpID(5))"))
        router.open(session(nil))
        router.open(URL(string: "http://localhost:8765/")!)
        router.open(WebNotification(id: "n1", title: "t", body: "b", tag: nil, requireInteraction: false, receivedAt: Date()))
        #expect(calls.inScience == 4)
        // Capsid's own window is not brought forward to show a note: the app is what opens.
        #expect(calls.shown == 0 && calls.navigated.isEmpty && calls.clicked.isEmpty)
    }

    @Test func clearingTheHookRestoresOpening() {
        let calls = Calls()
        let router = router(calls)
        router.openInScience = { calls.inScience += 1 }
        router.openInScience = nil
        router.open(URL(string: "http://localhost:8765/")!)
        #expect(calls.inScience == 0 && calls.navigated.count == 1)
    }
}

// MARK: Diagnostics

@Suite(.serialized)
struct ScienceSwitchDiagnosticsTests {
    private func status(context: String? = nil, boot: String? = nil, host: String? = nil, token: Bool? = nil, port: Int? = 8765) -> CLIStatus {
        CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "0.1.70", port: port,
                  launchContext: context, boot: boot, urlHost: host, requireToken: token)
    }

    @Test func theAppsStatusIsShownInFull() {
        let lines = Diagnose.daemonLines(status: status(context: "app-child", boot: "serving", host: "127.0.0.1", token: false),
                                         install: .ownWindow)
        #expect(lines == [
            "  started by: Claude Science's own app (its child)",
            "  boot: serving",
            "  address host: 127.0.0.1",
            "  requires a token to sign in: no",
            "• Capsid starts Claude Science's server: never, its own app starts it",
            "• Signing in: through the daemon's own page with a code from claude-science url; with none, Capsid only reads the database",
        ])
    }

    @Test func anOldStatusSaysNotReportedAndTheOldWay() {
        let lines = Diagnose.daemonLines(status: status(), install: .browserTab)
        #expect(lines == [
            "  started by: not reported",
            "  boot: not reported",
            "  address host: localhost (it names none)",
            "  requires a token to sign in: not reported",
            "• Capsid starts Claude Science's server: only when none is running, and waits for it",
            "• Signing in: with a code from claude-science url",
        ])
    }

    @Test func aTokenRequiredBesideTheAppIsSaidAsOnlyReadingWithoutACode() {
        let lines = Diagnose.daemonLines(status: status(context: "app-child", token: true), install: .ownWindow)
        #expect(lines.last == "• Signing in: through the daemon's own page with a code from claude-science url; with none (it requires a token), Capsid only reads the database")
        #expect(lines.contains("  requires a token to sign in: yes"))
    }

    @Test func aTabDaemonThatRequiresATokenStillSignsInWithACode() {
        // Sam's Mac, 2026-10-22: the launcher's daemon says it requires a token.
        let lines = Diagnose.daemonLines(status: status(context: nil, token: true), install: .browserTab)
        #expect(lines.last == "• Signing in: with a code from claude-science url")
    }

    @Test func aHostCapsidCantUseIsSaidAndReplaced() {
        let lines = Diagnose.daemonLines(status: status(host: "my-mac.local"), install: .browserTab)
        #expect(lines.contains("  address host: localhost (it names my-mac.local; Capsid uses localhost)"))
    }

    @Test func aDaemonSomeOtherWayStartedIsNamedByItsWord() {
        #expect(Diagnose.daemonLines(status: status(context: "cli"), install: .browserTab).first == "  started by: not the app (cli)")
    }

    @Test func whatCapsidDoesAboutStartingWhenNothingRuns() {
        let saved = ScienceLaunchContext.current
        defer { ScienceLaunchContext.remember(saved) }
        ScienceLaunchContext.remember(nil)
        #expect(Diagnose.startLine(status: nil, install: .ownWindow) == "• Capsid starts Claude Science's server: never, its own app starts it")
        #expect(Diagnose.startLine(status: nil, install: .browserTab) == "• Capsid starts Claude Science's server: only when none is running, and waits for it")
        // A daemon that was the app's child, remembered from the last status.
        ScienceLaunchContext.remember("app-child")
        #expect(Diagnose.startLine(status: nil, install: .browserTab) == "• Capsid starts Claude Science's server: never, its own app starts it")
    }

    @Test func theLaunchContextIsRememberedAndReplacedNilIncluded() {
        let saved = ScienceLaunchContext.current
        defer { ScienceLaunchContext.remember(saved) }
        ScienceLaunchContext.remember("app-child")
        #expect(ScienceLaunchContext.current == "app-child")
        ScienceLaunchContext.remember(nil)
        #expect(ScienceLaunchContext.current == nil)
    }

    @MainActor
    @Test func theWindowSaysWhatItIsDoing() {
        #expect(Diagnose.windowLines(companion: .none) == ["", "• The main window: signed in, or signing in"])
        #expect(Diagnose.windowLines(companion: .waitingForApp).last == "• The main window: waiting for Claude Science's own app to start its server")
        #expect(Diagnose.windowLines(companion: .readOnly(.noCode)).last
                == "• The main window: only reading the database (the daemon gave no sign-in code)")
    }

    @Test func noLineNamesAProjectASessionOrAHomeFolder() {
        let text = (Diagnose.daemonLines(status: status(context: "app-child", boot: "serving", host: "127.0.0.1", token: false), install: .ownWindow)
                    + MadeUpMac(apps: [userApp: ownWindow], support: true).install().lines(home: home)).joined(separator: "\n")
        #expect(!text.contains(home))
    }
}
