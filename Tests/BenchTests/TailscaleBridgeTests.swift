// TailscaleBridgeTests.swift — what Bench reads from Tailscale and the exact
// commands it would run, on fixtures and a fake runner. Nothing here runs
// the real CLI or touches a real Serve config. The fixtures follow the shape
// of `tailscale status --json` and `serve status --json` (1.104), with
// made-up names throughout.
import Foundation
import Testing
@testable import Bench

/// Fixture JSON, scrubbed: every name, key and address is made up.
enum TailscaleFixture {
    static func status(backend: String = "Running", certDomains: String = "null") -> String {
        """
        {
          "Version": "1.104.1-example",
          "TUN": false,
          "BackendState": "\(backend)",
          "HaveNodeKey": true,
          "AuthURL": "",
          "TailscaleIPs": ["100.64.0.10", "fd7a:115c:a1e0::a"],
          "Self": {
            "ID": "nExampleNode1",
            "NodeID": 1234567,
            "PublicKey": "nodekey:0000000000000000000000000000000000000000000000000000000000000000",
            "HostName": "Studio Mac",
            "DNSName": "studio-mac.example-tailnet.ts.net.",
            "OS": "macOS",
            "UserID": 4242424242,
            "TailscaleIPs": ["100.64.0.10", "fd7a:115c:a1e0::a"],
            "Online": true,
            "Capabilities": ["https://tailscale.com/cap/is-owner"],
            "CapMap": {"tailnet-display-name": ["example-tailnet"]},
            "KeyExpiry": "2027-04-01T00:00:00Z"
          },
          "Health": [],
          "MagicDNSSuffix": "example-tailnet.ts.net",
          "CurrentTailnet": {"Name": "pat@example.com", "StableID": "TExample", "MagicDNSSuffix": "example-tailnet.ts.net", "MagicDNSEnabled": true},
          "CertDomains": \(certDomains),
          "ExtraRecords": null,
          "Peer": {
            "nodekey:1111111111111111111111111111111111111111111111111111111111111111": {
              "HostName": "Pat's iPhone", "DNSName": "pats-iphone.example-tailnet.ts.net.", "UserID": 4242424242
            }
          },
          "User": {
            "4242424242": {"ID": 4242424242, "LoginName": "pat@example.com", "DisplayName": "Pat Example", "ProfilePicURL": ""}
          },
          "ClientVersion": null
        }
        """
    }

    static let loggedOut = """
        {"Version": "1.104.1-example", "BackendState": "NeedsLogin", "AuthURL": "", "Self": {"ID": "", "UserID": 0, "DNSName": ""},
         "CertDomains": null, "User": null}
        """

    static let serveEmpty = "{}"

    static func serveBench(port: Int = 47280, extra: String = "") -> String {
        """
        {
          "TCP": {"8443": {"HTTPS": true}\(extra.isEmpty ? "" : ", " + extra)},
          "Web": {"studio-mac.example-tailnet.ts.net:8443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:\(port)"}}}}
        }
        """
    }

    /// Someone's own app on 443, and Bench's on 8443.
    static let serveBenchAndMine = """
        {
          "TCP": {"443": {"HTTPS": true}, "8443": {"HTTPS": true}},
          "Web": {
            "studio-mac.example-tailnet.ts.net:443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:3000"}}},
            "studio-mac.example-tailnet.ts.net:8443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:47280"}}}
          }
        }
        """

    /// Someone else's app on 8443.
    static let serveOther8443 = """
        {"TCP": {"8443": {"HTTPS": true}},
         "Web": {"studio-mac.example-tailnet.ts.net:8443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:3000"}}}}}
        """

    /// Bench's target, and a second mount on the same port.
    static let serveBenchPlusMount = """
        {"TCP": {"8443": {"HTTPS": true}},
         "Web": {"studio-mac.example-tailnet.ts.net:8443": {"Handlers": {
            "/": {"Proxy": "http://127.0.0.1:47280"}, "/files": {"Path": "/Users/example/Public"}}}}}
        """

    static let serveTCPForward = """
        {"TCP": {"8443": {"TCPForward": "127.0.0.1:22"}}}
        """

    static let serveFunnel = """
        {"TCP": {"8443": {"HTTPS": true}},
         "Web": {"studio-mac.example-tailnet.ts.net:8443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:47280"}}}},
         "AllowFunnel": {"studio-mac.example-tailnet.ts.net:8443": true}}
        """

    static let serveForeground = """
        {"Foreground": {"session-1": {"TCP": {"8443": {"HTTPS": true}},
          "Web": {"studio-mac.example-tailnet.ts.net:8443": {"Handlers": {"/": {"Text": "hello"}}}}}}}
        """

    /// What `serve` prints when the tailnet hasn't HTTPS on, then waits.
    static let httpsOff = """

        HTTPS is not enabled on your tailnet.
        To enable, visit:

                 https://login.tailscale.com/f/serve?node=nExampleNode1

        Waiting...
        """

    static let served = """
        Available within your tailnet:

        https://studio-mac.example-tailnet.ts.net:8443/
        |-- proxy http://127.0.0.1:47280

        Serve started and running in the background.
        To disable the proxy, run: tailscale serve --https=8443 off
        """
}

/// Answers each command with the next of its outputs, and records it.
final class FakeTailscaleRunner: TailscaleRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [[String]: [TailscaleRun]]
    private(set) var calls: [[String]] = []

    init(_ outputs: [[String]: [TailscaleRun]]) {
        self.outputs = outputs
    }

    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun {
        lock.withLock {
            calls.append(arguments)
            guard var queue = outputs[arguments], !queue.isEmpty else { return TailscaleRun(exitStatus: 1, output: "unexpected") }
            let next = queue.removeFirst()
            // The last answer stands for any more calls.
            outputs[arguments] = queue.isEmpty ? [next] : queue
            return next
        }
    }

    var changes: [[String]] {
        lock.withLock { calls.filter { $0 != TailscaleCommands.status && $0 != TailscaleCommands.serveStatus } }
    }
}

struct TailscaleBridgeTests {
    private func ok(_ output: String) -> TailscaleRun {
        TailscaleRun(exitStatus: 0, output: output)
    }

    private func serve(_ json: String) -> ServeStatus? {
        ServeStatus(json: Data(json.utf8))
    }

    // MARK: Status

    @Test func statusSaysTheNodeAndLogin() throws {
        let status = try #require(TailscaleStatus(json: Data(TailscaleFixture.status().utf8)))
        #expect(status.running)
        #expect(status.login == "pat@example.com")
        #expect(status.dnsName == "studio-mac.example-tailnet.ts.net")
        #expect(!status.httpsEnabled)
        #expect(status.url?.absoluteString == "https://studio-mac.example-tailnet.ts.net:8443/")
    }

    @Test func certDomainsMeanHTTPSIsOn() throws {
        let on = try #require(TailscaleStatus(json: Data(TailscaleFixture.status(certDomains: #"["studio-mac.example-tailnet.ts.net"]"#).utf8)))
        #expect(on.httpsEnabled)
        let empty = try #require(TailscaleStatus(json: Data(TailscaleFixture.status(certDomains: "[]").utf8)))
        #expect(!empty.httpsEnabled)
    }

    @Test func aLoggedOutTailscaleIsNotRunning() throws {
        let status = try #require(TailscaleStatus(json: Data(TailscaleFixture.loggedOut.utf8)))
        #expect(!status.running)
        #expect(status.login == nil)
        #expect(status.dnsName == nil)
        #expect(TailscaleStatus(json: Data("failed to connect to local tailscaled".utf8)) == nil)
    }

    @Test func anOddNodeNameIsNoName() {
        #expect(TailscaleStatus.isDNSName("studio-mac.example-tailnet.ts.net"))
        #expect(!TailscaleStatus.isDNSName("studio mac.ts.net"))
        #expect(!TailscaleStatus.isDNSName("evil.example/path"))
        #expect(!TailscaleStatus.isDNSName("localhost"))
    }

    // MARK: Serve status

    @Test func nothingServedLeaves8443Free() {
        #expect(serve(TailscaleFixture.serveEmpty) == ServeStatus(port8443: .free, hasOtherMappings: false))
    }

    @Test func benchsMappingIsRecognized() {
        #expect(serve(TailscaleFixture.serveBench()) == ServeStatus(port8443: .bench(port: 47280), hasOtherMappings: false))
        #expect(serve(TailscaleFixture.serveBench(port: 47283))?.port8443 == .bench(port: 47283))
    }

    @Test func otherMappingsAreSeenAndLeftAlone() {
        #expect(serve(TailscaleFixture.serveBenchAndMine) == ServeStatus(port8443: .bench(port: 47280), hasOtherMappings: true))
        #expect(serve(TailscaleFixture.serveOther8443) == ServeStatus(port8443: .other, hasOtherMappings: true))
        #expect(serve(TailscaleFixture.serveBenchPlusMount)?.port8443 == .other)
        #expect(serve(TailscaleFixture.serveTCPForward)?.port8443 == .other)
        #expect(serve(TailscaleFixture.serveFunnel)?.port8443 == .other)
        #expect(serve(TailscaleFixture.serveForeground)?.port8443 == .other)
        // A proxy outside Bench's ports isn't Bench's.
        #expect(serve(TailscaleFixture.serveBench(port: 47291))?.port8443 == .other)
        #expect(serve("not json") == nil)
    }

    // MARK: Commands

    @Test func theExactArguments() {
        #expect(TailscaleCommands.add(port: 47280) == ["serve", "--bg", "--https=8443", "http://127.0.0.1:47280"])
        #expect(TailscaleCommands.remove(serve(TailscaleFixture.serveBench())!) == ["serve", "--https=8443", "off"])
        #expect(TailscaleCommands.status == ["status", "--json"])
        #expect(TailscaleCommands.serveStatus == ["serve", "status", "--json"])
    }

    @Test func removeOnlyWhen8443IsBenchs() {
        #expect(TailscaleCommands.remove(serve(TailscaleFixture.serveEmpty)!) == nil)
        #expect(TailscaleCommands.remove(serve(TailscaleFixture.serveOther8443)!) == nil)
        #expect(TailscaleCommands.remove(serve(TailscaleFixture.serveBenchPlusMount)!) == nil)
        #expect(TailscaleCommands.remove(serve(TailscaleFixture.serveFunnel)!) == nil)
        #expect(TailscaleCommands.remove(serve(TailscaleFixture.serveBenchAndMine)!) == ["serve", "--https=8443", "off"])
    }

    @Test func thePlan() {
        #expect(TailscaleCommands.plan(serve(TailscaleFixture.serveEmpty)!, port: 47281)
                == .run([["serve", "--bg", "--https=8443", "http://127.0.0.1:47281"]]))
        #expect(TailscaleCommands.plan(serve(TailscaleFixture.serveBench())!, port: 47280) == .nothing)
        #expect(TailscaleCommands.plan(serve(TailscaleFixture.serveBench())!, port: 47282)
                == .run([["serve", "--https=8443", "off"], ["serve", "--bg", "--https=8443", "http://127.0.0.1:47282"]]))
        #expect(TailscaleCommands.plan(serve(TailscaleFixture.serveOther8443)!, port: 47280) == .blocked)
    }

    @Test func benchsTarget() {
        #expect(TailscaleCommands.benchPort("http://127.0.0.1:47280") == 47280)
        #expect(TailscaleCommands.benchPort("http://127.0.0.1:47290/") == 47290)
        #expect(TailscaleCommands.benchPort("http://127.0.0.1:3000") == nil)
        #expect(TailscaleCommands.benchPort("http://localhost:47280") == nil)
        #expect(TailscaleCommands.benchPort("https://127.0.0.1:47280") == nil)
        #expect(TailscaleCommands.benchPort("http://127.0.0.1:47280/api") == nil)
    }

    @Test func theEnableURLIsFound() {
        #expect(TailscaleCommands.enableURL(in: TailscaleFixture.httpsOff)?.absoluteString
                == "https://login.tailscale.com/f/serve?node=nExampleNode1")
        // The node's own address isn't a page to open.
        #expect(TailscaleCommands.enableURL(in: TailscaleFixture.served) == nil)
        #expect(TailscaleCommands.enableURL(in: "visit https://evil.example/login.tailscale.com") == nil)
        #expect(TailscaleCommands.enableURL(in: "") == nil)
    }

    @Test func theCLIIsLookedForInTheApp() {
        let other = URL(fileURLWithPath: "/Users/example/Applications/Tailscale.app")
        let list = TailscaleCLI.candidates(appURLs: [URL(fileURLWithPath: "/Applications/Tailscale.app"), other])
        #expect(list.map(\.path) == ["/Applications/Tailscale.app", "/Users/example/Applications/Tailscale.app"])
        #expect(TailscaleCLI.binary(in: other).path == "/Users/example/Applications/Tailscale.app/Contents/MacOS/Tailscale")
        #expect(TailscaleCLI.locate(isExecutable: { _ in false }, isTrusted: { _ in true }, apps: { [other] }) == nil)
    }

    @Test func jsonIsFoundPastAWarning() {
        #expect(TailscaleBridge.json(in: "Warning: client version differs\n{\"a\": 1}\n") == "{\"a\": 1}")
        #expect(TailscaleBridge.json(in: "no json") == "")
    }

    // MARK: The bridge, with a fake runner

    @Test func notInstalled() async {
        let bridge = TailscaleBridge(runner: nil)
        #expect(await bridge.status() == .notInstalled)
        #expect(await bridge.serve(port: 47280).outcome == .failed)
        #expect(await !bridge.stopServing())
    }

    @Test func statusThroughTheRunner() async {
        let runner = FakeTailscaleRunner([TailscaleCommands.status: [ok(TailscaleFixture.status())]])
        guard case .status(let status) = await TailscaleBridge(runner: runner).status() else {
            Issue.record("no status")
            return
        }
        #expect(status.login == "pat@example.com")
        let down = FakeTailscaleRunner([TailscaleCommands.status: [TailscaleRun(exitStatus: 1, output: "failed to connect")]])
        #expect(await TailscaleBridge(runner: down).status() == .notRunning)
    }

    @Test func servingAddsOnlyBenchsMapping() async {
        let add = TailscaleCommands.add(port: 47280)
        let runner = FakeTailscaleRunner([
            TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveEmpty), ok(TailscaleFixture.serveBench())],
            add: [ok(TailscaleFixture.served)],
        ])
        #expect(await TailscaleBridge(runner: runner).serve(port: 47280).outcome == .serving)
        #expect(runner.changes == [add])
    }

    @Test func alreadyServingChangesNothing() async {
        let runner = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBenchAndMine)]])
        #expect(await TailscaleBridge(runner: runner).serve(port: 47280).outcome == .serving)
        #expect(runner.changes.isEmpty)
    }

    @Test func someoneElses8443IsNeverTaken() async {
        let runner = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveOther8443)]])
        #expect(await TailscaleBridge(runner: runner).serve(port: 47280).outcome == .blocked)
        #expect(await TailscaleBridge(runner: runner).stopServing())
        #expect(runner.changes.isEmpty)
    }

    @Test func httpsOffGivesTheEnableURL() async {
        let add = TailscaleCommands.add(port: 47280)
        let runner = FakeTailscaleRunner([
            TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveEmpty)],
            add: [TailscaleRun(exitStatus: nil, output: TailscaleFixture.httpsOff)],
        ])
        let outcome = await TailscaleBridge(runner: runner).serve(port: 47280).outcome
        #expect(outcome == .httpsOff(URL(string: "https://login.tailscale.com/f/serve?node=nExampleNode1")))
    }

    @Test func aFailedServeIsFailed() async {
        let add = TailscaleCommands.add(port: 47280)
        let runner = FakeTailscaleRunner([
            TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveEmpty)],
            add: [TailscaleRun(exitStatus: 1, output: "error: something")],
        ])
        #expect(await TailscaleBridge(runner: runner).serve(port: 47280).outcome == .failed)
    }

    @Test func stoppingRemovesOnlyBenchsMapping() async {
        let remove = ["serve", "--https=8443", "off"]
        let runner = FakeTailscaleRunner([
            TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBenchAndMine)],
            remove: [ok("")],
        ])
        #expect(await TailscaleBridge(runner: runner).stopServing())
        #expect(runner.changes == [remove])

        let empty = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveEmpty)]])
        #expect(await TailscaleBridge(runner: empty).stopServing())
        #expect(empty.changes.isEmpty)
    }

    @Test func anUnreadableServeStatusChangesNothing() async {
        let runner = FakeTailscaleRunner([TailscaleCommands.serveStatus: [TailscaleRun(exitStatus: 1, output: "")]])
        #expect(await TailscaleBridge(runner: runner).serve(port: 47280).outcome == .failed)
        #expect(await !TailscaleBridge(runner: runner).stopServing())
        #expect(runner.changes.isEmpty)
    }
}

// MARK: Whose CLI runs, and what removing the mapping came to (since the 0.4.0 review)

/// A runner with no CLI behind it, as the app's is without Tailscale.
private struct NoCLIRunner: TailscaleRunner {
    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun { .none }
}

/// Records the bundles a signature check was asked about.
private final class Checks: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var stamps: [String: Date] = [:]

    var asked: [String] { lock.withLock { paths } }
    func ask(_ url: URL) { lock.withLock { paths.append(url.path) } }
    func stamp(_ url: URL) -> [Date?] { lock.withLock { [stamps[url.path]] } }
    func touch(_ url: URL, _ date: Date) { lock.withLock { stamps[url.path] = date } }
}

struct TailscaleSignatureTests {
    private let mine = URL(fileURLWithPath: "/Applications/Tailscale.app")
    private let lookalike = URL(fileURLWithPath: "/Volumes/Example/Tailscale.app")

    @Test func theRequirementIsTailscalesTeamOrItsOwnStoreApp() {
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(TailscaleCLI.requirement as CFString, [], &requirement) == errSecSuccess)
        #expect(TailscaleCLI.requirement.hasPrefix(#"(anchor apple generic and certificate leaf[subject.OU] = "W5364U7YZB")"#))
        #expect(TailscaleCLI.requirement.contains(#"identifier "io.tailscale.ipn.macos""#))
    }

    @Test func appsTailscaleDidntSignAreNotTailscale() throws {
        // Apple's own, signed but not by Tailscale.
        #expect(!TailscaleSignature.verify(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        #expect(!TailscaleSignature.verify(URL(fileURLWithPath: "/nonexistent/Tailscale.app")))
        // A look-alike bundle, never signed (and never run).
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bench-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("Tailscale.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho made-up\n".utf8).write(to: TailscaleCLI.binary(in: app))
        try Data(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>io.tailscale.ipn.macsys</string><key>CFBundleExecutable</key><string>Tailscale</string></dict></plist>"#.utf8)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        #expect(!TailscaleSignature.verify(app))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Applications/Tailscale.app")))
    func theInstalledTailscaleIsTailscales() {
        #expect(TailscaleSignature.verify(TailscaleCLI.standardApp))
    }

    @Test func theCheckIsRememberedPerPathAndModificationDate() {
        let checks = Checks()
        let mine = self.mine
        let signature = TailscaleSignature(check: { checks.ask($0); return $0 == mine }, stamp: { checks.stamp($0) })
        #expect(signature.isTrusted(mine))
        #expect(signature.isTrusted(mine))
        #expect(!signature.isTrusted(lookalike))
        #expect(!signature.isTrusted(lookalike))
        #expect(checks.asked == [mine.path, lookalike.path])
        // Replaced in place: checked again.
        checks.touch(mine, Date(timeIntervalSince1970: 1_800_000_000))
        #expect(signature.isTrusted(mine))
        #expect(checks.asked == [mine.path, lookalike.path, mine.path])
    }

    @Test func anAppThatOnlyBorrowsTheBundleIDNeverRuns() {
        let elsewhere = URL(fileURLWithPath: "/Users/example/Applications/Tailscale.app")
        // /Applications holds one Tailscale didn't sign: passed over for a signed one elsewhere.
        #expect(TailscaleCLI.locate(isExecutable: { _ in true }, isTrusted: { $0 == elsewhere }, apps: { [lookalike, elsewhere] })
                == TailscaleCLI.binary(in: elsewhere))
        // None signed: as if Tailscale weren't installed.
        #expect(TailscaleCLI.locate(isExecutable: { _ in true }, isTrusted: { _ in false }, apps: { [lookalike, elsewhere] }) == nil)
        // A signed one in /Applications: Launch Services isn't asked.
        var asked = false
        #expect(TailscaleCLI.locate(isExecutable: { _ in true }, isTrusted: { _ in true }, apps: { asked = true; return [lookalike] })
                == TailscaleCLI.standard)
        #expect(!asked)
    }
}

struct TailscaleRemovalTests {
    private func ok(_ output: String) -> TailscaleRun {
        TailscaleRun(exitStatus: 0, output: output)
    }

    private let off = ["serve", "--https=8443", "off"]

    @Test func withoutTailscalesCLINothingRuns() async {
        let bridge = TailscaleBridge(runner: NoCLIRunner())
        #expect(await bridge.status() == .notInstalled)
        #expect(await bridge.serveStatus() == nil)
        #expect(await bridge.removeMapping() == .notInstalled)
        #expect(await bridge.serve(port: 47280).outcome == .failed)
    }

    @Test func removingSaysWhatItCameTo() async {
        let benchs = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBench())], off: [ok("")]])
        #expect(await TailscaleBridge(runner: benchs).removeMapping() == .none)
        #expect(benchs.changes == [off])

        let someoneElses = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveOther8443)]])
        #expect(await TailscaleBridge(runner: someoneElses).removeMapping() == .none)
        #expect(someoneElses.changes.isEmpty)

        let down = FakeTailscaleRunner([TailscaleCommands.serveStatus: [TailscaleRun(exitStatus: 1, output: "failed to connect")]])
        #expect(await TailscaleBridge(runner: down).removeMapping() == .unreadable)
        #expect(down.changes.isEmpty)

        let refused = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBench())],
                                           off: [TailscaleRun(exitStatus: 1, output: "error")]])
        #expect(await TailscaleBridge(runner: refused).removeMapping() == .failed)
    }

    @Test func servingSaysWhetherOtherSitesShareTheAddress() async {
        let shared = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBenchAndMine)]])
        let served = await TailscaleBridge(runner: shared).serve(port: 47280)
        #expect(served == TailscaleBridge.Served(outcome: .serving, othersShare: true))
        let alone = FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBench())]])
        #expect(await TailscaleBridge(runner: alone).serve(port: 47280).othersShare == false)
        // Added now: what Serve says after.
        let add = TailscaleCommands.add(port: 47280)
        let added = FakeTailscaleRunner([
            TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveEmpty), ok(TailscaleFixture.serveBenchAndMine)],
            add: [ok(TailscaleFixture.served)],
        ])
        #expect(await TailscaleBridge(runner: added).serve(port: 47280) == TailscaleBridge.Served(outcome: .serving, othersShare: true))
    }
}
