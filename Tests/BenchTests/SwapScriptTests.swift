// SwapScriptTests.swift — Resources/swap.sh, the last step of a native update
// (DESIGN.md, Update check → Installing natively), run against a scratch
// folder with made-up app bundles. Nothing here touches /Applications, opens
// a real app or goes online: the script's test hooks stand in for `open` and
// for "the new copy is running".
import Foundation
import Testing
@testable import Bench

/// A scratch install: an "installed" Capsid.app, a "new" one in a state dir,
/// a launcher that runs the new copy's binary in the background, and a file
/// the binary creates when it starts (the script's `CAPSID_SWAP_RUNNING_FILE`).
private struct SwapFixture {
    let root: URL
    let app: URL
    let state: URL
    let new: URL
    let runningFile: URL
    let launcher: URL

    static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/swap.sh")

    init(installedVersion: String = "0.9.7", newVersion: String = "0.9.8", newStarts: Bool = true) throws {
        let files = FileManager.default
        root = files.temporaryDirectory.appendingPathComponent("bench-swap-\(UUID().uuidString)", isDirectory: true)
        app = root.appendingPathComponent("Applications/Capsid.app", isDirectory: true)
        state = root.appendingPathComponent("state", isDirectory: true)
        new = state.appendingPathComponent("v\(newVersion)/Capsid.app", isDirectory: true)
        runningFile = root.appendingPathComponent("running")
        launcher = root.appendingPathComponent("launch")
        try Self.makeApp(at: app, version: installedVersion, marks: nil)
        try Self.makeApp(at: new, version: newVersion, marks: newStarts ? runningFile : nil)
        try files.createDirectory(at: state, withIntermediateDirectories: true)
        // The launcher runs the app's binary detached, as `open` would.
        try "#!/bin/zsh\n\"$1/Contents/MacOS/Capsid\" </dev/null >/dev/null 2>&1 &\nexit 0\n"
            .write(to: launcher, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    }

    /// A bundle whose binary is a script: it creates `marks` (if any) and
    /// lingers a moment, as a launching app would.
    static func makeApp(at url: URL, version: String, marks: URL?) throws {
        let files = FileManager.default
        try files.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "local.sam.bench", "CFBundleShortVersionString": version]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        let body = marks.map { "#!/bin/zsh\ntouch \"\($0.path)\"\nsleep 3\n" } ?? "#!/bin/zsh\nexit 1\n"
        let binary = url.appendingPathComponent("Contents/MacOS/Capsid")
        try body.write(to: binary, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    /// Starts the script for a "running copy" that quits after `oldQuitsAfter`
    /// seconds (a sleep standing in for Capsid), with short waits, and returns
    /// at once with the two processes: the caller can act while it runs.
    func start(oldQuitsAfter: Double = 0.3, wait: Int = 2) throws -> (old: Process, swap: Process) {
        let old = Process()
        old.executableURL = URL(fileURLWithPath: "/bin/sleep")
        old.arguments = [String(oldQuitsAfter)]
        try old.run()

        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/zsh")
        swap.arguments = [Self.script.path, String(old.processIdentifier), app.path, new.path, state.path]
        swap.environment = [
            "PATH": "/usr/bin:/bin",
            "CAPSID_SWAP_WAIT": String(wait),
            "CAPSID_SWAP_LAUNCH": launcher.path,
            "CAPSID_SWAP_RUNNING_FILE": runningFile.path,
        ]
        swap.standardOutput = FileHandle.nullDevice
        swap.standardError = FileHandle.nullDevice
        try swap.run()
        return (old, swap)
    }

    /// Waits for a started script to end and reads what it left.
    func finish(_ started: (old: Process, swap: Process)) -> (status: Int32, marker: String?, log: String) {
        started.swap.waitUntilExit()
        if started.old.isRunning { started.old.terminate() }
        let marker = try? String(contentsOf: state.appendingPathComponent("marker"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let log = (try? String(contentsOf: state.appendingPathComponent("swap.log"), encoding: .utf8)) ?? ""
        return (started.swap.terminationStatus, marker, log)
    }

    /// Runs the script to its end.
    func run(oldQuitsAfter: Double = 0.3, wait: Int = 2) throws -> (status: Int32, marker: String?, log: String) {
        finish(try start(oldQuitsAfter: oldQuitsAfter, wait: wait))
    }

    func version(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    var previous: URL { URL(fileURLWithPath: app.path + ".previous") }

    func stateEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: state.path).sorted()
    }

    func tearDown() {
        // A read-only folder from an injected failure must open again first.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: new.deletingLastPathComponent().path)
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite(.serialized)
struct SwapScriptTests {
    @Test func theNewCopyGoesInPlaceAndTheOldOneWaitsForTheCleanUp() throws {
        let fixture = try SwapFixture()
        defer { fixture.tearDown() }
        let result = try fixture.run()
        #expect(result.status == 0, "\(result.log)")
        #expect(result.marker == "installed 0.9.8")
        #expect(fixture.version(of: fixture.app) == "0.9.8")
        // The old copy is kept beside it until the new Capsid removes it.
        #expect(fixture.version(of: fixture.previous) == "0.9.7")
        #expect(!FileManager.default.fileExists(atPath: fixture.new.path))
    }

    @Test func aNewCopyThatNeverStartsIsPutAwayAndTheOldOneComesBack() throws {
        let fixture = try SwapFixture(newStarts: false)
        defer { fixture.tearDown() }
        let result = try fixture.run()
        #expect(result.status == 1)
        #expect(result.marker == "failed: the new copy didn\u{2019}t open" || result.marker == "failed: the new copy didn't open")
        #expect(fixture.version(of: fixture.app) == "0.9.7")
        #expect(!FileManager.default.fileExists(atPath: fixture.previous.path))
        // The copy that didn't start is kept for a look, not deleted.
        #expect(try fixture.stateEntries().contains { $0.hasPrefix("broken-") && $0.hasSuffix(".app") })
    }

    /// The interaction the update's handshake exists for: the new Capsid
    /// reaches its launch clean-up (`UpdateAftermath.settle`) while swap.sh is
    /// still inside its two-second look, and then dies. swap.sh must find the
    /// old copy where it put it, so the rollback leaves a whole Capsid in
    /// Applications. The timing is real (the script's own `sleep 2`), so a
    /// run that missed the window, on a machine too busy to get from the
    /// running file to the clean-up in a second and a half, is tried again.
    @Test func aNewCopyThatCleansUpAndThenDiesStillLeavesTheOldOneBack() throws {
        for attempt in 1...3 {
            let fixture = try SwapFixture()
            defer { fixture.tearDown() }
            let started = try fixture.start(wait: 5)

            // The fake launch has made the running file: swap.sh is about to
            // sleep its two seconds and look again.
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: fixture.runningFile.path) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            #expect(FileManager.default.fileExists(atPath: fixture.runningFile.path), "the fake launch never ran")
            // The script looks for the file every quarter second: half a second
            // on, it has seen it and is inside its two-second sleep.
            Thread.sleep(forTimeInterval: 0.5)
            let seen = Date()

            // The new copy's launch clean-up, with the real removal, on the
            // paths the script is using; then the new copy dies.
            let outcome = UpdateAftermath.settle(
                stateFolder: fixture.state, installedApp: fixture.app, currentVersion: "0.9.8",
                bundleInfo: { ("local.sam.bench", fixture.version(of: $0)) },
                remove: { try? FileManager.default.removeItem(at: $0) })
            try? FileManager.default.removeItem(at: fixture.runningFile)
            let cleanedUpAfter = Date().timeIntervalSince(seen)

            let result = fixture.finish(started)
            if cleanedUpAfter > 1.5 || result.marker?.hasPrefix("installed") == true {
                // The two-second look ran before the crash: not this test's
                // interaction. Another attempt, unless this was the last.
                if attempt < 3 { continue }
                Issue.record("the clean-up never landed inside the script's two-second look (\(cleanedUpAfter) s)")
                return
            }

            #expect(outcome == .waiting, "the clean-up must wait for the marker, not remove the old copy")
            #expect(result.status == 1, "\(result.log)")
            // The old copy is back in Applications, whole.
            #expect(fixture.version(of: fixture.app) == "0.9.7", "\(result.log)")
            #expect(FileManager.default.fileExists(atPath: fixture.app.appendingPathComponent("Contents/MacOS/Capsid").path))
            #expect(!FileManager.default.fileExists(atPath: fixture.previous.path))
            #expect(result.marker?.hasPrefix("failed:") == true, "\(result.marker ?? "no marker")")
            #expect(result.marker?.contains("put back") != true, "\(result.marker ?? "no marker")")
            // The copy that died is kept for a look.
            #expect(try fixture.stateEntries().contains { $0.hasPrefix("broken-") && $0.hasSuffix(".app") })
            return
        }
    }

    /// The other half: a new copy that reaches its clean-up inside the look
    /// and stays up. The clean-up waits; once the script has written its
    /// marker, the next look removes the old copy and the state folder.
    @Test func aNewCopyThatStaysUpHasTheOldOneRemovedOnceTheMarkerIsThere() throws {
        let fixture = try SwapFixture()
        defer { fixture.tearDown() }
        let started = try fixture.start(wait: 5)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: fixture.runningFile.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        Thread.sleep(forTimeInterval: 0.5)
        func cleanUp() -> UpdateAftermath.Outcome {
            UpdateAftermath.settle(
                stateFolder: fixture.state, installedApp: fixture.app, currentVersion: "0.9.8",
                bundleInfo: { ("local.sam.bench", fixture.version(of: $0)) },
                remove: { try? FileManager.default.removeItem(at: $0) })
        }
        // Half a second in, the script is inside its two-second look: no marker.
        let early = cleanUp()
        #expect(early == .waiting)
        #expect(fixture.version(of: fixture.previous) == "0.9.7")
        let result = fixture.finish(started)
        #expect(result.status == 0, "\(result.log)")
        #expect(result.marker == "installed 0.9.8")
        let late = cleanUp()
        #expect(late == .installed(version: "0.9.8"))
        #expect(!FileManager.default.fileExists(atPath: fixture.previous.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.state.path))
        #expect(fixture.version(of: fixture.app) == "0.9.8")
    }

    @Test func aMoveThatFailsPutsTheOldCopyBack() throws {
        let fixture = try SwapFixture()
        defer { fixture.tearDown() }
        // The new copy can't leave its folder: mv needs to write the parent.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.new.deletingLastPathComponent().path)
        let result = try fixture.run()
        #expect(result.status == 1)
        #expect(result.marker?.hasPrefix("failed: couldn") == true, "\(result.marker ?? "no marker")")
        #expect(fixture.version(of: fixture.app) == "0.9.7")
        #expect(!FileManager.default.fileExists(atPath: fixture.previous.path))
        #expect(fixture.version(of: fixture.new) == "0.9.8")
    }

    @Test func aRunningCopyThatNeverQuitsIsLeftAlone() throws {
        let fixture = try SwapFixture()
        defer { fixture.tearDown() }
        let result = try fixture.run(oldQuitsAfter: 30, wait: 1)
        #expect(result.status == 1)
        #expect(result.marker?.hasPrefix("failed: the running copy didn") == true, "\(result.marker ?? "no marker")")
        #expect(fixture.version(of: fixture.app) == "0.9.7")
        #expect(fixture.version(of: fixture.new) == "0.9.8")
        #expect(!FileManager.default.fileExists(atPath: fixture.previous.path))
    }

    @Test func aStaleOldCopyIsMovedIntoTheStateFolderFirst() throws {
        let fixture = try SwapFixture()
        defer { fixture.tearDown() }
        try SwapFixture.makeApp(at: fixture.previous, version: "0.9.6", marks: nil)
        let result = try fixture.run()
        #expect(result.status == 0, "\(result.log)")
        #expect(fixture.version(of: fixture.app) == "0.9.8")
        #expect(fixture.version(of: fixture.previous) == "0.9.7")
        #expect(try fixture.stateEntries().contains { $0.hasPrefix("stale-previous-") })
    }

    @Test func theScriptRefusesBadArguments() throws {
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/zsh")
        swap.arguments = [SwapFixture.script.path, "1", "/nonexistent/a"]
        swap.standardError = FileHandle.nullDevice
        try swap.run()
        swap.waitUntilExit()
        #expect(swap.terminationStatus == 2)
    }

    @Test func theScriptIsShippedInTheBundleByTheBuildScript() throws {
        let root = SwapFixture.script.deletingLastPathComponent().deletingLastPathComponent()
        let build = try String(contentsOf: root.appendingPathComponent("Scripts/build-app.sh"), encoding: .utf8)
        #expect(build.contains("Resources/swap.sh"))
    }
}
