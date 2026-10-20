// PhoneSetupTests.swift — Settings → Phone's checklist (PhoneSetup.swift):
// finding the phone in `tailscale status --json`, every step's transition,
// Skip, Pair Another Device, the rule that a pairing code is issued only while
// "Pair your phone" is the step open, the demo's steps, and the look the tab
// takes every few seconds. Made-up names throughout; nothing reaches Tailscale.
import AppKit
import Foundation
import Testing
@testable import Bench

/// `tailscale status --json` with several devices on the tailnet, as the real
/// CLI shapes its `Peer` map (key names checked against 1.104). Made up.
private enum PeersFixture {
    static func status(peers: String) -> String {
        """
        {
          "BackendState": "Running",
          "Self": {"HostName": "Studio Mac", "DNSName": "studio-mac.example-tailnet.ts.net.", "OS": "macOS", "UserID": 1001},
          "CertDomains": ["studio-mac.example-tailnet.ts.net"],
          "Peer": {\(peers)},
          "User": {
            "1001": {"ID": 1001, "LoginName": "pat@example.com", "DisplayName": "Pat Example"},
            "1002": {"ID": 1002, "LoginName": "sam@example.org", "DisplayName": "Sam Example"},
            "1003": {"ID": 1003, "LoginName": "PAT@example.com", "DisplayName": "Pat Again"}
          }
        }
        """
    }

    static func peer(_ key: String, host: String, os: String, user: Int, online: Bool = true) -> String {
        #""nodekey:\#(key)": {"HostName": "\#(host)", "DNSName": "x.example-tailnet.ts.net.", "OS": "\#(os)", "UserID": \#(user), "Online": \#(online)}"#
    }

    static let crowd = [
        peer("a", host: "Laptop", os: "macOS", user: 1001),
        peer("b", host: "Sam's iPhone", os: "iOS", user: 1002),
        peer("c", host: "Tagged iPhone", os: "iOS", user: 0),
        peer("d", host: "Pat's iPad", os: "iOS", user: 1001, online: false),
        peer("e", host: "Pixel", os: "android", user: 1003),
        peer("f", host: "Desktop", os: "windows", user: 1001),
    ].joined(separator: ",\n")
}

struct PhoneSetupTests {
    private typealias Step = PhoneSetup.Step

    private func status(_ json: String) throws -> TailscaleStatus {
        try #require(TailscaleStatus(json: Data(json.utf8)))
    }

    private func peer(_ host: String, _ os: String, online: Bool = true, same: Bool = true) -> TailscalePeer {
        TailscalePeer(hostName: host, os: os, online: online, sameUser: same)
    }

    private let url = URL(string: "https://studio-mac.example-tailnet.ts.net:8443/")!

    /// Everything done: one device paired.
    private var ready: PhoneSetup.Input {
        PhoneSetup.Input(installed: true, login: "pat@example.com", httpsEnabled: true,
                         peers: [peer("iPhone", "iOS")], servingURL: url, devices: 1)
    }

    // MARK: Finding the phone

    @Test func peersAreReadWithWhoseTheyAre() throws {
        let peers = try status(PeersFixture.status(peers: PeersFixture.crowd)).peers
        func find(_ host: String) -> TailscalePeer? { peers.first { $0.hostName == host } }
        #expect(peers.count == 6)
        #expect(find("Laptop") == peer("Laptop", "macOS"))
        // Another user's phone, and a tagged one (user 0), aren't this Mac's user's.
        #expect(find("Sam's iPhone")?.sameUser == false)
        #expect(find("Tagged iPhone")?.sameUser == false)
        #expect(find("Pat's iPad") == peer("Pat's iPad", "iOS", online: false))
        // Another user id with the same login (any case) is the same person.
        #expect(find("Pixel")?.sameUser == true)
    }

    @Test func thePhoneIsTheSameUsersPhoneOrTablet() throws {
        let peers = try status(PeersFixture.status(peers: PeersFixture.crowd)).peers
        // The android phone is online; the iPad is not, so it comes second.
        #expect(PhoneSetup.phone(in: peers)?.hostName == "Pixel")
        #expect(PhoneSetup.phone(in: peers.filter { $0.hostName != "Pixel" })?.hostName == "Pat's iPad")
    }

    @Test func anOfflinePhoneStillCounts() throws {
        let alone = PeersFixture.peer("a", host: "iPhone", os: "iOS", user: 1001, online: false)
        let peers = try status(PeersFixture.status(peers: alone)).peers
        #expect(PhoneSetup.phone(in: peers)?.hostName == "iPhone")
    }

    @Test func onlyPhonesAndTabletsCount() {
        for os in ["iOS", "ios", "iPadOS", "android", "Android"] {
            #expect(PhoneSetup.phone(in: [peer("Device", os)]) != nil, "\(os)")
        }
        for os in ["macOS", "windows", "linux", "", "tvOS"] {
            #expect(PhoneSetup.phone(in: [peer("Device", os)]) == nil, "\(os)")
        }
        #expect(PhoneSetup.phone(in: [peer("Someone's", "iOS", same: false)]) == nil)
        #expect(PhoneSetup.phone(in: []) == nil)
    }

    @Test func noPeersWhenLoggedOutOrMissing() throws {
        #expect(try status(TailscaleFixture.loggedOut).peers.isEmpty)
        let none = #"{"BackendState": "Running", "Self": {"UserID": 1001}, "User": {"1001": {"LoginName": "pat@example.com"}}}"#
        #expect(try status(none).peers.isEmpty)
        // Logged out (no user of its own): no peer is this Mac's user's.
        let orphan = #"{"BackendState": "NeedsLogin", "Self": {"UserID": 0}, "Peer": {"k": {"HostName": "iPhone", "OS": "iOS", "UserID": 0}}}"#
        #expect(try status(orphan).peers.allSatisfy { !$0.sameUser })
    }

    // MARK: The steps, one transition at a time

    @Test func beforeTheFirstLookNothingIsKnown() {
        let state = PhoneSetup.state(PhoneSetup.Input(installed: nil, devices: 3))
        #expect(state.isChecking)
        #expect(state.expanded == nil)
        #expect(state.done.isEmpty)
        #expect(!state.isReady)
        #expect(!state.showsPairing)
    }

    @Test func eachStepOpensOnceTheOnesBeforeAreDone() {
        var input = PhoneSetup.Input(installed: false)
        func check(_ expanded: Step, _ facts: [Step: String], sourceLocation: SourceLocation = #_sourceLocation) {
            let state = PhoneSetup.state(input)
            #expect(state.expanded == expanded, sourceLocation: sourceLocation)
            #expect(state.facts == facts, sourceLocation: sourceLocation)
            #expect(state.done == Set(facts.keys), sourceLocation: sourceLocation)
            #expect(!state.isReady, sourceLocation: sourceLocation)
            #expect(Step.allCases.filter(state.isLater) == Step.allCases.filter { $0.rawValue > expanded.rawValue },
                    sourceLocation: sourceLocation)
        }
        check(.install, [:])
        input.installed = true
        check(.signIn, [.install: "Installed"])
        input.login = "pat@example.com"
        check(.https, [.install: "Installed", .signIn: "pat@example.com"])
        input.httpsEnabled = true
        check(.phone, [.install: "Installed", .signIn: "pat@example.com", .https: "On"])
        input.peers = [peer("Pat's iPhone", "iOS")]
        check(.turnOn, [.install: "Installed", .signIn: "pat@example.com", .https: "On", .phone: "Found: Pat's iPhone"])
        input.servingURL = url
        check(.pair, [.install: "Installed", .signIn: "pat@example.com", .https: "On", .phone: "Found: Pat's iPhone",
                      .turnOn: "https://studio-mac.example-tailnet.ts.net:8443"])
        input.devices = 1
        let state = PhoneSetup.state(input)
        #expect(state.isReady)
        #expect(state.expanded == nil)
        #expect(state.done == Set(Step.allCases))
        #expect(state.facts[.pair] == "1 device")
        #expect(state.summary == "Ready · 1 device · https://studio-mac.example-tailnet.ts.net:8443")
        input.devices = 2
        #expect(PhoneSetup.state(input).summary == "Ready · 2 devices · https://studio-mac.example-tailnet.ts.net:8443")
    }

    @Test func skipCountsAsTheStepDone() {
        var input = ready
        input.peers = []
        #expect(PhoneSetup.state(input).expanded == .phone)
        input.skippedPhone = true
        let state = PhoneSetup.state(input)
        #expect(state.isReady)
        #expect(state.facts[.phone] == "Skipped")
        // A phone that turns up later is named rather than "Skipped".
        input.peers = [peer("iPhone", "iOS", online: false)]
        #expect(PhoneSetup.state(input).facts[.phone] == "Found: iPhone")
    }

    @Test func aStepThatComesUndoneOpensAgain() {
        // Tailscale signed out: the steps after it wait, dimmed, and a later
        // one still done keeps its tick.
        var input = ready
        input.login = nil
        input.peers = []
        input.servingURL = nil
        let state = PhoneSetup.state(input)
        #expect(state.expanded == .signIn)
        #expect(state.done == [.install, .https, .pair])
        #expect(state.isLater(.https) && state.isLater(.pair))
        #expect(!state.isLater(.install))
        #expect(!state.isReady)
    }

    @Test func turningTheSwitchOffOpensItsStepAgain() {
        var input = ready
        input.servingURL = nil
        let state = PhoneSetup.state(input)
        #expect(state.expanded == .turnOn)
        #expect(state.done.contains(.pair))
        #expect(state.isLater(.pair))
        #expect(!state.showsPairing)
    }

    @Test func pairAnotherDeviceOpensTheLastStepUntilOneMorePairs() {
        var input = ready
        input.pairingAnotherFrom = 1
        var state = PhoneSetup.state(input)
        #expect(state.isReady)
        #expect(state.expanded == .pair)
        #expect(state.showsPairing)
        input.devices = 2
        state = PhoneSetup.state(input)
        #expect(state.expanded == nil)
        #expect(!state.showsPairing)
    }

    @Test func pairAnotherDeviceOpensNothingWhileSetupIsntDone() {
        var input = ready
        input.pairingAnotherFrom = 1
        input.servingURL = nil
        let state = PhoneSetup.state(input)
        #expect(state.expanded == .turnOn)
        #expect(!state.showsPairing)
    }

    // MARK: The code only while "Pair your phone" is open

    @Test func aCodeIsIssuedOnlyWhileThePairingStepIsOpen() {
        // Every combination of what the checklist goes by.
        var pairing = 0
        for installed in [nil, false, true] as [Bool?] {
            for login in [nil, "pat@example.com"] {
                for https in [false, true] {
                    for peers in [[], [peer("iPhone", "iOS")]] {
                        for skipped in [false, true] {
                            for serving in [nil, url] {
                                for devices in [0, 1, 2] {
                                    for another in [nil, 0, 1] as [Int?] {
                                        let input = PhoneSetup.Input(
                                            installed: installed, login: login, httpsEnabled: https, peers: peers,
                                            skippedPhone: skipped, servingURL: serving, devices: devices,
                                            pairingAnotherFrom: another)
                                        let state = PhoneSetup.state(input)
                                        #expect(state.showsPairing == (state.expanded == .pair))
                                        guard state.showsPairing else { continue }
                                        pairing += 1
                                        // Only with the page served and every step before done.
                                        #expect(serving != nil)
                                        #expect(Set([Step.install, .signIn, .https, .phone, .turnOn]).isSubset(of: state.done))
                                        // First time: no device yet; again: one more to come.
                                        #expect(devices == 0 || another.map { devices <= $0 } == true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(pairing > 0)
    }

    // MARK: From what the tab knows

    @Test @MainActor func theInputComesFromTheControllersStatus() {
        var status = RemoteController.Status()
        #expect(PhoneSetup.Input(status: status, enabled: false, skippedPhone: false, devices: 0).installed == nil)
        status.tailscale = .notInstalled
        #expect(PhoneSetup.Input(status: status, enabled: false, skippedPhone: false, devices: 0).installed == false)
        status.tailscale = .notRunning
        let notRunning = PhoneSetup.Input(status: status, enabled: false, skippedPhone: false, devices: 0)
        #expect(notRunning.installed == true)
        #expect(notRunning.login == nil)
        // Signed in but disconnected: not signed in, for the checklist.
        status.tailscale = .status(TailscaleStatus(running: false, login: "pat@example.com", dnsName: nil, httpsEnabled: false))
        #expect(PhoneSetup.Input(status: status, enabled: false, skippedPhone: false, devices: 0).login == nil)
        status.tailscale = .status(TailscaleStatus(running: true, login: "pat@example.com",
                                                   dnsName: "studio-mac.example-tailnet.ts.net", httpsEnabled: true,
                                                   peers: [peer("iPhone", "iOS")]))
        status.serve = .serving
        let on = PhoneSetup.Input(status: status, enabled: true, skippedPhone: true, devices: 2, pairingAnotherFrom: 2)
        #expect(on == PhoneSetup.Input(installed: true, login: "pat@example.com", httpsEnabled: true,
                                       peers: [peer("iPhone", "iOS")], skippedPhone: true, servingURL: url,
                                       devices: 2, pairingAnotherFrom: 2))
        // The switch off: not served, whatever the status last said.
        #expect(PhoneSetup.Input(status: status, enabled: false, skippedPhone: false, devices: 0).servingURL == nil)
    }

    @Test func theSwitchsLineSaysWhatItWaitsFor() {
        #expect(PhoneSetup.turnOnDetail(.off, port: nil) == nil)
        #expect(PhoneSetup.turnOnDetail(.serving, port: 47280) == nil)
        #expect(PhoneSetup.turnOnDetail(.waitingForTailscale, port: 47280) == "Waiting for Tailscale to connect.")
        #expect(PhoneSetup.turnOnDetail(.blocked, port: 47280)?.hasPrefix("Port 8443") == true)
        #expect(PhoneSetup.turnOnDetail(.failed, port: nil) == "Capsid couldn't listen on a port from 47280 to 47290.")
        #expect(PhoneSetup.turnOnDetail(.failed, port: 47280) == "Tailscale couldn't serve Capsid.")
    }

    @Test func aLongOrOddHostNameIsMadeFitToShow() {
        let odd = peer("Pat's\niPhone\u{7}" + String(repeating: "x", count: 100), "iOS")
        let fact = PhoneSetup.state(PhoneSetup.Input(installed: true, peers: [odd])).facts[.phone]
        #expect(fact == "Found: " + RemoteDevice.cleanName(odd.hostName))
        #expect(fact?.contains("\n") == false)
        #expect((fact?.count ?? 0) <= "Found: ".count + RemoteDevice.nameLimit)
    }

    // MARK: `--demo phone-settings`

    @Test @MainActor func theDemoOpensTheStepItIsGiven() {
        for step in 1...6 {
            let model = Demo.phoneSettings(step: step)
            let state = PhoneSetup.state(model.input())
            #expect(state.expanded?.rawValue == step, "step \(step)")
            #expect(state.done == Set(Step.allCases.filter { $0.rawValue < step }), "step \(step)")
        }
        let ready = Demo.phoneSettings(step: 7)
        let state = PhoneSetup.state(ready.input())
        #expect(state.isReady)
        #expect(state.summary == "Ready · 1 device · https://your-mac.your-tailnet.ts.net:8443")
        #expect(state.facts[.signIn] == "you@example.com")
        #expect(state.facts[.phone] == "Found: iPhone")
        #expect(ready.devices.map(\.name) == ["iPhone"])
        #expect(ready.code?.digits == "123456")
    }
}

// MARK: The look every few seconds

@MainActor
struct PhoneSetupPollTests {
    private func withDefaults(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let name = "bench.tests.phone.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func aLookReadsStatusOnlyAndOneAtATime() async throws {
        try await withDefaults { defaults in
            let runner = FakeTailscaleRunner([TailscaleCommands.status: [TailscaleRun(exitStatus: 0, output: TailscaleFixture.status())]])
            let remote = RemoteController(auth: RemoteAuth(store: MemoryDeviceStore()), bridge: TailscaleBridge(runner: runner),
                                          defaults: defaults, isDemo: false)
            remote.poll()
            // Asked again before the first look is done: skipped.
            remote.poll()
            await remote.settle()
            #expect(runner.calls == [TailscaleCommands.status])
            #expect(remote.status.tailscaleStatus?.login == "pat@example.com")
            #expect(PhoneSetup.phone(in: remote.status.tailscaleStatus?.peers ?? [])?.hostName == "Pat's iPhone")
            // Once it's done, the next one goes.
            remote.poll()
            await remote.settle()
            #expect(runner.calls == [TailscaleCommands.status, TailscaleCommands.status])
        }
    }

    @Test func aDemoLooksAtNothing() async throws {
        try await withDefaults { defaults in
            let runner = FakeTailscaleRunner([:])
            let remote = RemoteController(auth: RemoteAuth(store: MemoryDeviceStore()), bridge: TailscaleBridge(runner: runner),
                                          defaults: defaults, isDemo: true)
            remote.poll()
            await remote.settle()
            #expect(runner.calls.isEmpty)
        }
    }
}

/// Copy Link on the ready row: the private address goes to the pasteboard it is
/// given, as a URL and as plain text. Always a private pasteboard here, never
/// the general one.
struct LinkCopyTests {
    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("capsid-test-\(UUID().uuidString)"))
    }

    private let address = URL(string: "https://your-mac.your-tailnet.ts.net:8443/")!

    @Test func theAddressIsCopiedAsAURLAndAsText() throws {
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        LinkCopy.copy(address, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "https://your-mac.your-tailnet.ts.net:8443/")
        #expect(pasteboard.string(forType: .URL) == "https://your-mac.your-tailnet.ts.net:8443/")
        let read = try #require(NSURL(from: pasteboard))
        #expect(read as URL == address)
        #expect(pasteboard.types?.contains(.URL) == true && pasteboard.types?.contains(.string) == true)
    }

    @Test func whatWasOnThePasteboardBeforeIsReplaced() {
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let stale = NSPasteboard.PasteboardType("com.example.stale")
        pasteboard.clearContents()
        pasteboard.setString("something else", forType: .string)
        pasteboard.setString("older still", forType: stale)
        LinkCopy.copy(address, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == address.absoluteString)
        // Not added to what was there: the old kinds of content are gone.
        #expect(pasteboard.string(forType: stale) == nil)
        #expect(pasteboard.types?.contains(stale) == false)
        // And a second press leaves the same one thing, not two.
        LinkCopy.copy(address, to: pasteboard)
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    @Test func theConfirmationLastsAMoment() {
        #expect(LinkCopy.confirmation >= .seconds(1) && LinkCopy.confirmation <= .seconds(3))
    }
}
