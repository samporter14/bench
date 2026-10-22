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

    /// Runs the script for a "running copy" that quits after `oldQuitsAfter`
    /// seconds (a sleep standing in for Capsid), with short waits.
    func run(oldQuitsAfter: Double = 0.3, wait: Int = 2) throws -> (status: Int32, marker: String?, log: String) {
        let old = Process()
        old.executableURL = URL(fileURLWithPath: "/bin/sleep")
        old.arguments = [String(oldQuitsAfter)]
        try old.run()
        defer { if old.isRunning { old.terminate() } }

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
        swap.waitUntilExit()
        let marker = try? String(contentsOf: state.appendingPathComponent("marker"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let log = (try? String(contentsOf: state.appendingPathComponent("swap.log"), encoding: .utf8)) ?? ""
        return (swap.terminationStatus, marker, log)
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
