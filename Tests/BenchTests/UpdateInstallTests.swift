// UpdateInstallTests.swift — the native installer (App/UpdateInstall.swift,
// DESIGN.md Update check → Installing natively): its rules, the flow run
// with fakes for every step that would touch the network, the disk or the
// app, and what a launch after a swap does with what the script left. The
// script itself is tested in SwapScriptTests.
import Foundation
import Testing
@testable import Bench

private func version(_ text: String) throws -> BenchVersion {
    try #require(BenchVersion(text))
}

struct UpdateInstallRuleTests {
    @Test func aTagIsAVersionWithOrWithoutItsV() {
        #expect(UpdateInstallRules.isTag("v0.9.8"))
        #expect(UpdateInstallRules.isTag("0.9.8"))
        #expect(UpdateInstallRules.isTag("V1.0"))
        #expect(UpdateInstallRules.isTag("1"))
        #expect(!UpdateInstallRules.isTag(""))
        #expect(!UpdateInstallRules.isTag("latest"))
        #expect(!UpdateInstallRules.isTag("v0.9.8-beta"))
        #expect(!UpdateInstallRules.isTag("../../x"))
        #expect(!UpdateInstallRules.isTag("v0.9.8/../main"))
        #expect(!UpdateInstallRules.isTag("1.2.3.4.5"))
        #expect(!UpdateInstallRules.isTag("1234567"))
    }

    @Test func theDownloadIsTheTagsZipAndNothingElseSteersIt() {
        #expect(UpdateInstallRules.assetURL(tag: "v0.9.8")?.absoluteString
            == "https://github.com/samporter14/bench/releases/download/v0.9.8/Bench.zip")
        #expect(UpdateInstallRules.assetURL(tag: "latest") == nil)
        #expect(UpdateInstallRules.assetURL(tag: "v0.9.8?x=1") == nil)
    }

    @Test func anUpdateCarriesItsTagOrMakesOneFromItsVersion() throws {
        let update = AvailableUpdate(version: try version("0.9.8"), notesURL: UpdateRules.releasesPage)
        #expect(update.tag == "v0.9.8")
        let tagged = AvailableUpdate(version: try version("0.9.8"), notesURL: UpdateRules.releasesPage, tag: "0.9.8")
        #expect(tagged.tag == "0.9.8")
        // Something that isn't a tag is not kept.
        let odd = AvailableUpdate(version: try version("0.9.8"), notesURL: UpdateRules.releasesPage, tag: "latest")
        #expect(odd.tag == "v0.9.8")
    }

    @Test func aParsedReleaseKeepsItsTagForTheDownload() throws {
        let json = """
        {"tag_name": "v0.9.8", "html_url": "https://github.com/samporter14/bench/releases/tag/v0.9.8",
         "assets": [{"name": "Bench.zip"}]}
        """
        let release = try #require(UpdateRules.parse(Data(json.utf8)))
        #expect(release.tag == "v0.9.8")
        let update = try #require(UpdateRules.offer(release, current: try version("0.9.7")))
        #expect(update.tag == "v0.9.8")
        // A remembered version uses its remembered tag when it is that version's.
        if case .available(let restored) = UpdateRules.restoredState(newest: "0.9.8", tag: "v0.9.8", current: "0.9.7", hasChecked: true) {
            #expect(restored.tag == "v0.9.8")
        } else {
            Issue.record("not restored")
        }
        if case .available(let restored) = UpdateRules.restoredState(newest: "0.9.8", tag: "v0.9.9", current: "0.9.7", hasChecked: true) {
            #expect(restored.tag == "v0.9.8")
        } else {
            Issue.record("not restored")
        }
    }

    @Test func theCopyMustBeCapsidAtTheOfferedVersion() throws {
        let offered = try version("0.9.8")
        #expect(UpdateInstallRules.checkBundle(id: "local.sam.bench", version: "0.9.8", offered: offered) == nil)
        #expect(UpdateInstallRules.checkBundle(id: "local.sam.bench", version: "0.9.6", offered: offered) == .version(found: "0.9.6"))
        #expect(UpdateInstallRules.checkBundle(id: "local.sam.bench", version: nil, offered: offered) == .version(found: "nothing"))
        #expect(UpdateInstallRules.checkBundle(id: "com.example.other", version: "0.9.8", offered: offered) == .signature)
    }

    @Test func theMarkerSaysWhatTheSwapDid() {
        #expect(UpdateInstallRules.parseMarker("installed 0.9.8\n") == .installed(version: "0.9.8"))
        #expect(UpdateInstallRules.parseMarker("failed: the new copy didn\u{2019}t open") == .failed(reason: "the new copy didn\u{2019}t open"))
        #expect(UpdateInstallRules.parseMarker("") == nil)
        #expect(UpdateInstallRules.parseMarker("something else") == nil)
        #expect(UpdateInstallRules.failure(forReason: "the new copy didn't open") == .didNotOpen)
        #expect(UpdateInstallRules.failure(forReason: "the running copy didn't quit") == .didNotQuit)
        #expect(UpdateInstallRules.failure(forReason: "couldn't put the new copy in place: mv: no") == .swap("couldn't put the new copy in place: mv: no"))
    }

    @Test func onlyAnOlderCopyIsRemovedAfterASwap() {
        #expect(UpdateInstallRules.shouldRemovePrevious(previousVersion: "0.9.7", current: "0.9.8"))
        #expect(!UpdateInstallRules.shouldRemovePrevious(previousVersion: "0.9.8", current: "0.9.8"))
        #expect(!UpdateInstallRules.shouldRemovePrevious(previousVersion: "0.9.9", current: "0.9.8"))
        #expect(!UpdateInstallRules.shouldRemovePrevious(previousVersion: nil, current: "0.9.8"))
        #expect(!UpdateInstallRules.shouldRemovePrevious(previousVersion: "0.9.7", current: ""))
    }

    @Test func theScriptsTestHooksNeverReachTheRealSwap() {
        let environment = ["PATH": "/usr/bin", "CAPSID_SWAP_LAUNCH": "/tmp/x", "CAPSID_SWAP_WAIT": "1", "HOME": "/tmp/home"]
        let scrubbed = UpdateInstallRules.swapEnvironment(environment)
        #expect(scrubbed == ["PATH": "/usr/bin", "HOME": "/tmp/home"])
    }

    @Test func theProgressSentenceSharesTheUnit() throws {
        let v = try version("0.9.8")
        #expect(UpdateInstallRules.progressSentence(version: v, received: 3_100_000, expected: 9_400_000)
            == "Downloading Capsid 0.9.8\u{2026} 3.1 of 9.4 MB")
        #expect(UpdateInstallRules.progressSentence(version: v, received: 900_000, expected: 9_400_000)
            == "Downloading Capsid 0.9.8\u{2026} 900 KB of 9.4 MB")
        #expect(UpdateInstallRules.progressSentence(version: v, received: 0, expected: nil)
            == "Downloading Capsid 0.9.8\u{2026}")
        #expect(UpdateInstallRules.progressSentence(version: v, received: 2_000_000, expected: nil)
            == "Downloading Capsid 0.9.8\u{2026} 2 MB")
    }

    @Test func eachFailureHasItsSentenceAndItsButtons() throws {
        let offered = try version("0.9.8")
        let all: [UpdateInstallFailure] = [
            .download("x"), .noRoom(needed: 200 * 1024 * 1024), .noApp, .quarantined, .signature,
            .version(found: "0.9.6"), .swap("mv: no"), .didNotOpen, .didNotQuit, .cancelled,
        ]
        for failure in all {
            let text = failure.message(offered: offered, current: "0.9.7")
            #expect(text.hasSuffix("."), "\(failure)")
            // Every sentence that leaves the old copy in place says which one you have.
            if failure != .swap("mv: no"), failure != .didNotQuit {
                #expect(text.contains("0.9.7"), "\(failure)")
            }
        }
        #expect(UpdateInstallFailure.version(found: "0.9.6").message(offered: offered, current: "0.9.7")
            == "The downloaded copy says it is 0.9.6, not 0.9.8, so Capsid deleted it without opening it. You still have 0.9.7.")
        #expect(UpdateInstallFailure.swap("mv: no").message(offered: offered, current: "0.9.7")
            == "Capsid couldn\u{2019}t put the new copy in Applications: mv: no. The copy you had is back where it was.")
        #expect(UpdateInstallFailure.download("x").canRetry)
        #expect(!UpdateInstallFailure.signature.canRetry)
        #expect(UpdateInstallFailure.signature.offersNotes)
        #expect(UpdateInstallFailure.didNotOpen.offersNotes)
        #expect(!UpdateInstallFailure.download("x").offersNotes)
        #expect(UpdateInstallFailure.cancelled.isCancellation)
    }

    @Test func theInstalledCardTellsAndTimesOut() {
        let notice = UpdateInstallRules.installedNotice(version: "0.9.8")
        #expect(notice.title == "Capsid 0.9.8 is installed")
        #expect(notice.caption == "Updated")
        #expect(notice.action == .none)
        #expect(notice.lifetime == .seconds(15))
    }
}

// MARK: The flow, with fakes

/// Every step as a fake: what it was asked, and what it answers. Its knobs
/// are set before a run and read during it, never both at once, so it is a
/// plain class the flow's closures can reach from any context.
private final class FakeSteps: @unchecked Sendable {
    let root: URL
    var free: Int64? = 1_000_000_000
    var downloadFails = false
    var downloadHangs = false
    var zipHoldsApp = true
    var quarantined = false
    var signatureOK = true
    var codesignOK = true
    var bundle: (id: String?, version: String?) = ("local.sam.bench", "0.9.8")
    var hasScript = true
    var downloaded: [URL] = []
    var swaps: [SwapRequest] = []
    var terminated = 0
    var swapExit: (@MainActor @Sendable (String?) -> Void)?

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bench-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/zsh\n".write(to: root.appendingPathComponent("bundled-swap.sh"), atomically: true, encoding: .utf8)
    }

    var state: URL { root.appendingPathComponent("state", isDirectory: true) }

    func tearDown() { try? FileManager.default.removeItem(at: root) }

    func dependencies() -> UpdateInstallDependencies {
        UpdateInstallDependencies(
            stateFolder: state,
            installedApp: root.appendingPathComponent("Applications/Capsid.app", isDirectory: true),
            freeBytes: { [self] _ in free },
            download: { [self] url, destination, progress in
                downloaded.append(url)
                if downloadHangs {
                    // Hangs until cancelled, as a stalled connection would.
                    try await Task.sleep(for: .seconds(30))
                }
                if downloadFails { throw UpdateInstallFailure.download("stopped") }
                progress(5, 10)
                progress(10, 10)
                try Data("zip".utf8).write(to: destination)
            },
            unzip: { [self] _, folder in
                if zipHoldsApp {
                    let app = folder.appendingPathComponent("Capsid.app/Contents", isDirectory: true)
                    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
                }
            },
            isQuarantined: { [self] _ in quarantined },
            meetsRequirement: { [self] _ in signatureOK },
            codesignVerifies: { [self] _ in codesignOK },
            bundleInfo: { [self] _ in bundle },
            bundledScript: hasScript ? root.appendingPathComponent("bundled-swap.sh") : nil,
            pid: 4242,
            launchSwap: { [self] request, onExit in
                swaps.append(request)
                swapExit = onExit
            },
            terminate: { [self] in terminated += 1 })
    }
}

@MainActor
struct UpdateInstallFlowTests {
    private func update() throws -> AvailableUpdate {
        AvailableUpdate(version: try version("0.9.8"), notesURL: UpdateRules.releasesPage, tag: "v0.9.8")
    }

    private func run(_ steps: FakeSteps) async throws -> (failure: UpdateInstallFailure?, phases: [InstallPhase]) {
        var phases: [InstallPhase] = []
        let flow = UpdateInstallFlow(dependencies: steps.dependencies()) { phases.append($0) }
        let failure = await flow.run(try update()) { _ in }
        // Progress is relayed on a later turn of the main actor.
        await Task.yield()
        return (failure, phases)
    }

    @Test func aGoodDownloadIsCheckedThenSwappedAndCapsidQuits() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        let result = try await run(steps)
        #expect(result.failure == nil)
        #expect(steps.downloaded == [UpdateInstallRules.assetURL(tag: "v0.9.8")!])
        #expect(result.phases.first == .downloading(received: 0, expected: nil))
        #expect(result.phases.contains(.checking))
        #expect(result.phases.last == .installing)
        #expect(steps.terminated == 1)
        let swap = try #require(steps.swaps.first)
        #expect(swap.pid == 4242)
        #expect(swap.installedApp == steps.root.appendingPathComponent("Applications/Capsid.app", isDirectory: true))
        #expect(swap.newApp.path == steps.state.appendingPathComponent("v0.9.8/unpacked/Capsid.app").path)
        #expect(swap.state == steps.state)
        // The script runs from a copy in the state folder, not the bundle.
        #expect(swap.script == steps.state.appendingPathComponent("swap.sh"))
        #expect(FileManager.default.fileExists(atPath: swap.script.path))
        // The unpacked copy is still there for the script.
        #expect(FileManager.default.fileExists(atPath: swap.newApp.path))
    }

    @Test func aDownloadThatStopsLeavesNothingBehindAndCanBeTriedAgain() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.downloadFails = true
        let result = try await run(steps)
        #expect(result.failure == .download("stopped"))
        #expect(result.failure?.canRetry == true)
        #expect(steps.swaps.isEmpty && steps.terminated == 0)
        #expect(!FileManager.default.fileExists(atPath: steps.state.appendingPathComponent("v0.9.8").path))
    }

    @Test func noRoomStopsBeforeAnythingIsDownloaded() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.free = 10 * 1024 * 1024
        let result = try await run(steps)
        #expect(result.failure == .noRoom(needed: UpdateInstallRules.minimumFreeBytes))
        #expect(steps.downloaded.isEmpty)
    }

    @Test func aZipWithoutCapsidIsRefused() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.zipHoldsApp = false
        let result = try await run(steps)
        #expect(result.failure == .noApp)
        #expect(steps.swaps.isEmpty)
    }

    @Test func aCopySignedAnotherWayIsDeletedWithoutBeingOpened() async throws {
        for (signature, codesign) in [(false, true), (true, false)] {
            let steps = try FakeSteps()
            defer { steps.tearDown() }
            steps.signatureOK = signature
            steps.codesignOK = codesign
            let result = try await run(steps)
            #expect(result.failure == .signature)
            #expect(steps.swaps.isEmpty && steps.terminated == 0)
            #expect(!FileManager.default.fileExists(atPath: steps.state.appendingPathComponent("v0.9.8").path))
        }
    }

    @Test func aQuarantinedCopyIsRefused() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.quarantined = true
        let result = try await run(steps)
        #expect(result.failure == .quarantined)
        #expect(steps.swaps.isEmpty)
    }

    @Test func aCopyOfAnotherVersionOrAnotherAppIsRefused() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.bundle = ("local.sam.bench", "0.9.6")
        #expect(try await run(steps).failure == .version(found: "0.9.6"))
        steps.bundle = ("com.example.other", "0.9.8")
        #expect(try await run(steps).failure == .signature)
        #expect(steps.swaps.isEmpty)
    }

    @Test func aCopyWithoutTheSwapScriptStopsShort() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.hasScript = false
        let result = try await run(steps)
        #expect(result.failure == .swap("this copy has no swap script"))
        #expect(steps.terminated == 0)
    }

    @Test func cancellingTheDownloadCleansUpAndTouchesNothing() async throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        steps.downloadHangs = true
        let flow = UpdateInstallFlow(dependencies: steps.dependencies()) { _ in }
        let update = try update()
        let task = Task { await flow.run(update) { _ in } }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let failure = await task.value
        #expect(failure == .cancelled)
        #expect(steps.swaps.isEmpty && steps.terminated == 0)
        #expect(!FileManager.default.fileExists(atPath: steps.state.appendingPathComponent("v0.9.8").path))
    }
}

// MARK: The checker's part

@MainActor
struct UpdateCheckerInstallTests {
    /// A checker with an update known, in a scratch defaults suite, whose
    /// install steps are the fakes.
    private func checker(_ steps: FakeSteps, failed: @escaping @MainActor (AvailableUpdate, UpdateInstallFailure) -> Void = { _, _ in })
        -> UpdateChecker {
        let suite = "UpdateCheckerInstallTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("0.9.8", forKey: "updateNewestVersion")
        defaults.set("v0.9.8", forKey: "updateNewestTag")
        defaults.set(Date().timeIntervalSince1970, forKey: "updateLastChecked")
        return UpdateChecker(defaults: defaults, currentVersion: "0.9.7", fetch: { _ in throw CheckFailure.unreachable },
                             isDemo: false, post: { _ in }, installDependencies: { steps.dependencies() },
                             installFailed: failed, settle: {})
    }

    @Test func aRememberedUpdateKeepsItsTag() throws {
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        let updates = checker(steps)
        #expect(updates.newest?.tag == "v0.9.8")
        #expect(updates.installPhase == nil)
        #expect(!updates.installing)
    }

    @Test func installOnlyRunsFromApplications() throws {
        // The test runner isn't /Applications/Capsid.app, so nothing starts.
        let steps = try FakeSteps()
        defer { steps.tearDown() }
        let updates = checker(steps)
        updates.install()
        #expect(updates.installPhase == nil)
        #expect(steps.downloaded.isEmpty)
    }
}

// MARK: After a launch

struct UpdateAftermathTests {
    private struct Scratch {
        let root: URL
        let state: URL
        let app: URL
        var previous: URL { URL(fileURLWithPath: app.path + ".previous", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("bench-aftermath-\(UUID().uuidString)", isDirectory: true)
            state = root.appendingPathComponent("state", isDirectory: true)
            app = root.appendingPathComponent("Applications/Capsid.app", isDirectory: true)
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        }

        func marker(_ text: String) throws { try text.write(to: state.appendingPathComponent("marker"), atomically: true, encoding: .utf8) }
        func tagFolder(_ tag: String) throws {
            try FileManager.default.createDirectory(at: state.appendingPathComponent(tag), withIntermediateDirectories: true)
        }
        func makePrevious() throws { try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true) }
        func tearDown() { try? FileManager.default.removeItem(at: root) }
    }

    private func settle(_ scratch: Scratch, previousVersion: String? = "0.9.7", current: String = "0.9.8")
        -> (outcome: UpdateAftermath.Outcome, removed: [URL]) {
        var removed: [URL] = []
        let outcome = UpdateAftermath.settle(
            stateFolder: scratch.state, installedApp: scratch.app, currentVersion: current,
            bundleInfo: { _ in ("local.sam.bench", previousVersion) }, remove: { removed.append($0) })
        return (outcome, removed)
    }

    @Test func nothingToDoOnAnOrdinaryLaunch() throws {
        let scratch = try Scratch()
        defer { scratch.tearDown() }
        let result = settle(scratch)
        #expect(result.outcome == .nothing)
        #expect(result.removed.isEmpty)
    }

    @Test func theOldCopyGoesOnceTheNewOneIsRunning() throws {
        let scratch = try Scratch()
        defer { scratch.tearDown() }
        try scratch.marker("installed 0.9.8")
        try scratch.makePrevious()
        let result = settle(scratch)
        #expect(result.outcome == .installed(version: "0.9.8"))
        #expect(result.removed == [scratch.previous, scratch.state])
    }

    @Test func aCopyBesideThisOneThatIsNotOlderIsLeftAlone() throws {
        let scratch = try Scratch()
        defer { scratch.tearDown() }
        try scratch.marker("installed 0.9.8")
        try scratch.makePrevious()
        let result = settle(scratch, previousVersion: "0.9.9")
        #expect(result.outcome == .nothing)
        #expect(result.removed == [scratch.state])
    }

    @Test func aFailedSwapIsReportedByTheCopyThatWasPutBack() throws {
        let scratch = try Scratch()
        defer { scratch.tearDown() }
        try scratch.marker("failed: the new copy didn\u{2019}t open")
        try scratch.tagFolder("v0.9.8")
        let result = settle(scratch, previousVersion: nil, current: "0.9.7")
        #expect(result.outcome == .failed(.didNotOpen, offered: "v0.9.8"))
        #expect(result.removed == [scratch.state])
    }

    @Test func aMarkerAloneCountsAsAnInstallToo() throws {
        let scratch = try Scratch()
        defer { scratch.tearDown() }
        try scratch.marker("installed 0.9.8")
        let result = settle(scratch, previousVersion: nil)
        #expect(result.outcome == .installed(version: "0.9.8"))
        #expect(result.removed == [scratch.state])
    }
}
