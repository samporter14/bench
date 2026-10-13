// RemoteController.swift — Bench on your phone, put together (DESIGN.md,
// Bench on your phone): the switch starts the loopback listener and adds
// Bench's Serve mapping; off stops the listener and removes that mapping
// only, keeping the paired devices. It publishes what Settings → Phone shows.
//
// Never in a demo but `--demo remote`, which serves made-up sessions on
// 127.0.0.1 with the fixed code 000000, and touches no Tailscale, Keychain or
// setting.
import AppKit
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "remote")

@MainActor
final class RemoteController: ObservableObject {
    static let shared = RemoteController(auth: RemoteAuth(store: KeychainDeviceStore()), bridge: .live())

    /// What Settings → Phone shows.
    struct Status: Equatable {
        enum Serve: Equatable {
            /// The switch is off.
            case off
            /// Turning on, or checking.
            case starting
            /// Tailscale isn't running or signed in yet.
            case waitingForTailscale
            case serving
            /// The tailnet hasn't HTTPS on; the page that turns it on, when
            /// Tailscale gave one.
            case httpsOff(URL?)
            /// 8443 is another Serve mapping's.
            case blocked
            /// The listener has no free port, or `serve` failed.
            case failed
        }

        /// Nil until the first check.
        var tailscale: TailscaleBridge.Check?
        var checking = false
        var serve: Serve = .off
        /// The loopback port, while listening.
        var port: UInt16?
        /// Tailscale is signed in as someone other than when the switch was
        /// turned on: Serve's identity check refuses the phone.
        var otherLogin = false

        var tailscaleStatus: TailscaleStatus? {
            if case .status(let status)? = tailscale { status } else { nil }
        }

        /// `https://<node>.<tailnet>.ts.net:8443/`, while serving.
        var url: URL? {
            serve == .serving ? tailscaleStatus?.url : nil
        }
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var status = Status()
    let auth: RemoteAuth

    private let bridge: TailscaleBridge
    private let defaults: UserDefaults
    private var server: RemoteServer?
    private let feed = RemoteFeed()
    /// The state last sent to the events streams, at a fixed moment, so a
    /// change that changes nothing the phone shows isn't sent.
    private var lastPushed: RemoteAPI.State?
    /// One change at a time: each waits for the last.
    private var pending: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var activation: AnyCancellable?

    init(auth: RemoteAuth, bridge: TailscaleBridge, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.bridge = bridge
        self.defaults = defaults
        enabled = defaults.bool(forKey: SettingsKey.remoteEnabled)
    }

    // MARK: The switch

    /// At launch: back on if it was on. Never in a demo.
    func start() {
        guard Demo.mode == nil, activation == nil else { return }
        PushCenter.shared.start() // Phase 2 push
        // Back from turning HTTPS on in the browser, or from opening
        // Tailscale: check again.
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.enabled, self.status.serve != .serving else { return }
                    self.refresh()
                }
            }
        if enabled { enqueue { await self.turnOn(recordingLogin: false) } }
    }

    /// The switch in Settings.
    func setEnabled(_ on: Bool) {
        guard Demo.mode == nil, on != enabled else { return }
        enabled = on
        defaults.set(on, forKey: SettingsKey.remoteEnabled)
        enqueue { on ? await self.turnOn(recordingLogin: true) : await self.turnOff() }
    }

    /// Check Again, the Phone tab appearing, Bench coming to the front.
    func refresh() {
        guard Demo.mode == nil else { return }
        enqueue {
            await self.checkTailscale(recordingLogin: false)
            if self.enabled { await self.serveIfReady() }
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pending
        pending = Task {
            await previous?.value
            await work()
        }
    }

    private func turnOn(recordingLogin: Bool) async {
        guard enabled else { return }
        auth.load()
        status.serve = .starting
        let server = server ?? makeServer()
        self.server = server
        server.push = PushCenter.shared // Phase 2 push
        do {
            let port = try await server.start(candidates: RemoteServer.candidates(
                remembered: defaults.object(forKey: SettingsKey.remotePort) as? Int))
            defaults.set(Int(port), forKey: SettingsKey.remotePort)
            status.port = port
        } catch {
            log.error("Remote has no free port from 47280 to 47290")
            status.serve = .failed
            return
        }
        feed.start(lab: .shared, usage: .shared, approver: .shared) { [weak self] in self?.pushState() }
        await checkTailscale(recordingLogin: recordingLogin)
        await serveIfReady()
        if status.serve == .waitingForTailscale { scheduleRetry(attempt: 0) }
    }

    private func turnOff() async {
        retry?.cancel()
        retry = nil
        feed.stop()
        server?.stop()
        lastPushed = nil
        status.port = nil
        status.serve = .off
        auth.withdrawCode()
        // Bench's own mapping only; any other stays as it is.
        if bridge.isInstalled, await !bridge.stopServing() {
            log.error("Couldn't remove Bench's Serve mapping")
        }
    }

    // MARK: Tailscale

    /// Reads `tailscale status`, records the login when the switch was just
    /// turned on (or none is recorded), and sets who the server lets in.
    private func checkTailscale(recordingLogin: Bool) async {
        status.checking = true
        let check = await bridge.status()
        status.checking = false
        status.tailscale = check
        var recorded = defaults.string(forKey: SettingsKey.remoteLogin)
        if enabled, case .status(let tailscale) = check, let login = tailscale.login,
           recordingLogin || recorded == nil {
            defaults.set(login, forKey: SettingsKey.remoteLogin)
            recorded = login
        }
        let current = status.tailscaleStatus
        status.otherLogin = enabled && current?.login.map { login in
            recorded.map { $0.caseInsensitiveCompare(login) != .orderedSame } ?? false
        } ?? false
        if let current, current.running, let name = current.dnsName, let recorded {
            server?.policy = .tailnet(dnsName: name, login: recorded)
        } else {
            server?.policy = .closed
        }
    }

    /// Adds Bench's mapping once Tailscale is up and signed in.
    private func serveIfReady() async {
        guard enabled, let port = status.port else { return }
        guard let tailscale = status.tailscaleStatus, tailscale.running, tailscale.login != nil,
              tailscale.dnsName != nil else {
            status.serve = .waitingForTailscale
            return
        }
        switch await bridge.serve(port: port) {
        case .serving:
            status.serve = .serving
            log.notice("Remote serving over Tailscale")
        case .httpsOff(let url):
            status.serve = .httpsOff(url)
        case .blocked:
            status.serve = .blocked
        case .failed:
            status.serve = tailscale.httpsEnabled ? .failed : .httpsOff(nil)
        }
    }

    /// Tailscale may start after Bench at login: a few more looks, then
    /// none until Bench comes to the front or Settings asks.
    private func scheduleRetry(attempt: Int) {
        let waits: [Duration] = [.seconds(15), .seconds(60), .seconds(300)]
        retry?.cancel()
        retry = nil
        guard attempt < waits.count else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: waits[attempt])
            guard !Task.isCancelled, let self, self.enabled, self.status.serve == .waitingForTailscale else { return }
            self.enqueue {
                await self.checkTailscale(recordingLogin: false)
                await self.serveIfReady()
                if self.status.serve == .waitingForTailscale { self.scheduleRetry(attempt: attempt + 1) }
            }
        }
    }

    // MARK: Pairing and devices

    /// The code Settings shows, new when the last has gone.
    func issueCode() {
        guard enabled || Demo.mode == .remote else { return }
        auth.issueCode()
    }

    func remove(_ device: RemoteDevice) {
        auth.remove(device.id)
        server?.closeStreams(of: device.id)
    }

    func removeAll() {
        auth.removeAll()
        server?.closeAllStreams()
    }

    // MARK: The server

    private func makeServer() -> RemoteServer {
        RemoteServer(policy: .closed, auth: auth, backend: RemoteBackend(
            state: { Self.stateJSON() },
            session: { await RemoteSessions.shared.sessionJSON($0) }, // Phase 2 actions
            open: { id in
                guard let session = RemoteAPI.knownSessions(lab: .shared).first(where: { $0.id == id })
                        ?? RemoteSessions.shared.heldSession(id) else { return false } // Phase 3 browse
                LabModel.shared.open(session)
                return true
            },
            version: RemoteAPI.benchVersion,
            act: { await RemoteSessions.shared.act($0, session: $1, device: $2, body: $3) }, // Phase 2 actions
            files: { await RemoteArtifacts.shared.respond($0, target: $1, device: $2).response }, // Phase 3 files
            browse: { await RemoteBrowser.shared.respond($0, target: $1, device: $2, body: $3) })) // Phase 3 browse
    }

    private static func state(now: Date = Date()) -> RemoteAPI.State {
        RemoteAPI.state(RemoteAPI.input(lab: .shared, usage: .shared, bench: RemoteAPI.benchVersion, now: now))
    }

    private static func stateJSON() -> Data {
        RemoteAPI.encode(state())
    }

    /// The models changed: the state goes to the events streams, if it
    /// changed what they show.
    private func pushState() {
        guard let server, server.streamCount > 0 else { return }
        let now = Date()
        let state = Self.state(now: now)
        let fixed = state.at(.distantPast)
        guard fixed != lastPushed else { return }
        lastPushed = fixed
        server.broadcast(RemoteAPI.encode(state))
    }

    // MARK: `--demo remote`

    private static var demoServer: RemoteServer?
    private static var demoFeed: RemoteFeed?

    /// Serves the made-up sessions Demo shows on http://127.0.0.1:<port>,
    /// with the code 000000, and prints where. Nothing is saved anywhere.
    /// `reads` are the sessions' made-up replies, turns and questions; the
    /// demo's actions answer as the daemon would and touch no web view.
    static func startDemo(reads: [String: SessionProjection] = [:]) {
        guard Demo.mode == .remote, demoServer == nil else { return }
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        let store = DemoBrowseStore(nowSessions: RemoteAPI.knownSessions(lab: .shared), reads: reads) // Phase 3 browse
        let sessions = RemoteSessions.demo(reads: reads, lookup: { store.lookup($0) }, more: { store.read($0) }) // Phase 2 actions
        let browser = RemoteBrowser.demo(sessions: sessions, store: store) // Phase 3 browse
        let artifacts = RemoteArtifacts.demo(listed: .shared, info: .shared) // Phase 3 files
        let server = RemoteServer(policy: .closed, auth: auth, backend: RemoteBackend(
            state: { Self.stateJSON() },
            session: { await sessions.sessionJSON($0) }, // Phase 2 actions
            // Made up: nothing to open, and no window to open it in.
            open: { id in RemoteAPI.knownSessions(lab: .shared).contains { $0.id == id } || sessions.heldSession(id) != nil },
            version: RemoteAPI.benchVersion,
            act: { await sessions.act($0, session: $1, device: $2, body: $3) }, // Phase 2 actions
            files: { await artifacts.respond($0, target: $1, device: $2).response }, // Phase 3 files
            browse: { await browser.respond($0, target: $1, device: $2, body: $3) })) // Phase 3 browse
        demoServer = server
        server.push = PushCenter.demo(auth: auth) // Phase 2 push
        Task {
            guard let port = try? await server.start(candidates: Array(RemoteServer.ports)) else {
                FileHandle.standardError.write(Data("Bench: no free port from 47280 to 47290\n".utf8))
                exit(1)
            }
            server.policy = .demo(port: port)
            let feed = RemoteFeed()
            feed.start(lab: .shared, usage: .shared, approver: .shared) {
                server.broadcast(RemoteAPI.encode(Self.state()))
            }
            demoFeed = feed
            FileHandle.standardOutput.write(Data("Bench remote demo: http://127.0.0.1:\(port)/ (pairing code 000000)\n".utf8))
        }
    }
}
