// TailscaleBridge.swift — what Bench asks of Tailscale (DESIGN.md, Bench on
// your phone → Transport and trust): whether it is installed, running and
// signed in, the node's name, whether the tailnet has HTTPS, and Bench's one
// Serve mapping, HTTPS 8443 → http://127.0.0.1:<port>.
//
// Bench reads `serve status --json` before every change and adds or removes
// only its own mapping: never `serve reset`, never Funnel, never another
// mapping. The parsing and the exact arguments are pure and tested on
// fixtures; running the CLI goes through one injectable runner, and the app's
// runs only a binary whose app bundle is signed by Tailscale Inc.
import AppKit
import Foundation
import OSLog
import Security

private let log = Logger(subsystem: "local.sam.bench", category: "remote")

// MARK: What Tailscale says

/// `tailscale status --json`, reduced to what Bench uses.
struct TailscaleStatus: Equatable, Sendable {
    /// `BackendState` is `Running`: connected and signed in.
    let running: Bool
    /// The signed-in user's login (`User[Self.UserID].LoginName`).
    let login: String?
    /// `Self.DNSName`, lowercased, without its trailing dot.
    let dnsName: String?
    /// `CertDomains` has something in it: the tailnet has HTTPS on.
    let httpsEnabled: Bool
    /// The other devices on the tailnet (`Peer`), for Settings → Phone's
    /// "Put Tailscale on your phone". Held in memory only, never logged.
    let peers: [TailscalePeer]

    init(running: Bool, login: String?, dnsName: String?, httpsEnabled: Bool, peers: [TailscalePeer] = []) {
        self.running = running
        self.login = login
        self.dnsName = dnsName
        self.httpsEnabled = httpsEnabled
        self.peers = peers
    }

    /// Nil unless the output is a JSON object with a `BackendState`.
    init?(json data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let backend = root["BackendState"] as? String else { return nil }
        running = backend == "Running"
        let me = root["Self"] as? [String: Any]
        let name = (me?["DNSName"] as? String)?.lowercased()
        let trimmed = name.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        dnsName = trimmed.flatMap { Self.isDNSName($0) ? $0 : nil }
        let users = root["User"] as? [String: Any] ?? [:]
        func loginName(_ userID: NSNumber?) -> String? {
            guard let userID, let user = users[userID.stringValue] as? [String: Any],
                  let login = user["LoginName"] as? String, !login.isEmpty else { return nil }
            return login
        }
        let myID = me?["UserID"] as? NSNumber
        let login = loginName(myID)
        self.login = login
        httpsEnabled = !((root["CertDomains"] as? [String]) ?? []).isEmpty
        // The same user: the same `UserID` as this Mac, or a user with the
        // same login. A `UserID` of 0 (none, or a tagged device) is nobody's.
        let mine = myID.map { $0.int64Value != 0 } ?? false
        peers = (root["Peer"] as? [String: Any] ?? [:]).values.compactMap { value in
            guard let peer = value as? [String: Any] else { return nil }
            let userID = peer["UserID"] as? NSNumber
            let owned = userID.map { $0.int64Value != 0 } ?? false
            let sameID = owned && mine && userID == myID
            let sameLogin = owned && login != nil && loginName(userID)?.lowercased() == login?.lowercased()
            return TailscalePeer(hostName: peer["HostName"] as? String ?? "", os: peer["OS"] as? String ?? "",
                                 online: peer["Online"] as? Bool ?? false, sameUser: sameID || sameLogin)
        }
    }

    /// A node name fit for a Host check and a URL: letters, digits, dashes
    /// and dots.
    static func isDNSName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 253 && name.contains(".") && name.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x2E
        }
    }

    /// `https://<node>.<tailnet>.ts.net:8443/`, once the name is known.
    var url: URL? {
        dnsName.flatMap { URL(string: "https://\($0):\(RemotePolicy.httpsPort)/") }
    }
}

/// One of `tailscale status --json`'s `Peer` entries, reduced to what
/// Settings → Phone asks: is there a phone or tablet signed in as this Mac's
/// user?
struct TailscalePeer: Equatable, Sendable {
    /// `HostName`, as Tailscale shows it ("iPhone").
    let hostName: String
    /// `OS`: "iOS" (iPhones and iPads), "android", "macOS", "windows"…
    let os: String
    /// `Online`. An offline phone still counts: it is set up.
    let online: Bool
    /// Signed in as this Mac's user (`UserID`, or the same `LoginName`).
    let sameUser: Bool
}

/// `tailscale serve status --json`, reduced to Bench's question: whose is
/// HTTPS port 8443?
struct ServeStatus: Equatable, Sendable {
    enum Port: Equatable, Sendable {
        /// Nothing serves on 8443.
        case free
        /// Only Bench's mapping: `/` proxied to http://127.0.0.1:<port>.
        case bench(port: UInt16)
        /// Someone else's mapping, or more than Bench's: left alone.
        case other
    }

    let port8443: Port
    /// Any mapping that isn't Bench's, on any port: never touched.
    let hasOtherMappings: Bool

    init(port8443: Port, hasOtherMappings: Bool) {
        self.port8443 = port8443
        self.hasOtherMappings = hasOtherMappings
    }

    /// Nil unless the output is a JSON object (`{}` when nothing is served).
    init?(json data: Data) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let port = Self.port8443(in: root)
        // Foreground serves and Funnel are always someone else's; so is any
        // port but 8443, and 8443 itself unless it is Bench's alone.
        let tcp = root["TCP"] as? [String: Any] ?? [:]
        let web = root["Web"] as? [String: Any] ?? [:]
        let elsewhere = tcp.keys.contains { $0 != "\(RemotePolicy.httpsPort)" }
            || web.keys.contains { !$0.hasSuffix(":\(RemotePolicy.httpsPort)") }
        let extras = ["Services", "Foreground", "AllowFunnel"].contains { key in
            (root[key] as? [String: Any]).map { !$0.isEmpty } ?? false
        }
        port8443 = port
        hasOtherMappings = elsewhere || extras || port == .other
    }

    private static func port8443(in root: [String: Any]) -> Port {
        let key = "\(RemotePolicy.httpsPort)"
        let suffix = ":\(key)"
        let tcp = (root["TCP"] as? [String: Any])?[key]
        let webs = (root["Web"] as? [String: Any] ?? [:]).filter { $0.key.hasSuffix(suffix) }
        let foreground = (root["Foreground"] as? [String: Any] ?? [:]).values.contains { value in
            guard let config = value as? [String: Any] else { return true }
            let fgTCP = (config["TCP"] as? [String: Any])?[key] != nil
            let fgWeb = (config["Web"] as? [String: Any] ?? [:]).keys.contains { $0.hasSuffix(suffix) }
            return fgTCP || fgWeb
        }
        let funnel = (root["AllowFunnel"] as? [String: Any] ?? [:]).contains { $0.key.hasSuffix(suffix) && ($0.value as? Bool ?? true) }
        if tcp == nil, webs.isEmpty, !foreground, !funnel { return .free }
        guard !foreground, !funnel,
              let handler = tcp as? [String: Any], handler["HTTPS"] as? Bool == true,
              (handler["TCPForward"] as? String ?? "").isEmpty, handler["HTTP"] as? Bool != true,
              webs.count == 1, let config = webs.first?.value as? [String: Any],
              let handlers = config["Handlers"] as? [String: Any], handlers.count == 1,
              let mount = handlers["/"] as? [String: Any], mount.count == 1,
              let proxy = mount["Proxy"] as? String, let port = TailscaleCommands.benchPort(proxy) else { return .other }
        return .bench(port: port)
    }
}

// MARK: The commands

/// The exact arguments Bench gives the CLI, and what it reads back.
enum TailscaleCommands {
    static let status = ["status", "--json"]
    static let serveStatus = ["serve", "status", "--json"]

    /// Bench's target: the loopback listener.
    static func target(port: UInt16) -> String {
        "http://127.0.0.1:\(port)"
    }

    static func add(port: UInt16) -> [String] {
        ["serve", "--bg", "--https=\(RemotePolicy.httpsPort)", target(port: port)]
    }

    /// Only when 8443 serves Bench's target and nothing else: `off` takes
    /// every handler on the port.
    static func remove(_ serve: ServeStatus) -> [String]? {
        guard case .bench = serve.port8443 else { return nil }
        return ["serve", "--https=\(RemotePolicy.httpsPort)", "off"]
    }

    /// The listener's port, when `proxy` is Bench's target for one in
    /// Bench's range: a mapping from an earlier run on another port is still
    /// Bench's.
    static func benchPort(_ proxy: String) -> UInt16? {
        var text = proxy
        if text.hasSuffix("/") { text.removeLast() }
        let prefix = "http://127.0.0.1:"
        guard text.hasPrefix(prefix), let port = UInt16(text.dropFirst(prefix.count)),
              RemoteServer.ports.contains(port) else { return nil }
        return port
    }

    enum Plan: Equatable {
        /// Bench's mapping is there, for this port.
        case nothing
        /// Each in turn.
        case run([[String]])
        /// 8443 is someone else's: Bench won't take it.
        case blocked
    }

    /// What it takes to serve the listener on `port`.
    static func plan(_ serve: ServeStatus, port: UInt16) -> Plan {
        switch serve.port8443 {
        case .free: .run([add(port: port)])
        case .bench(let served) where served == port: .nothing
        // An earlier run's port: its mapping goes, this one comes.
        case .bench: .run([remove(serve)!, add(port: port)])
        case .other: .blocked
        }
    }

    /// The page `serve` prints when the tailnet hasn't HTTPS (or Serve) on
    /// yet, which an admin opens to turn it on. Only a Tailscale login page
    /// counts: the button opens it in a browser.
    static func enableURL(in output: String) -> URL? {
        for word in output.split(whereSeparator: \.isWhitespace) {
            guard word.hasPrefix("https://"), let url = URL(string: String(word)),
                  url.scheme == "https", let host = url.host?.lowercased(),
                  host == "login.tailscale.com" else { continue }
            return url
        }
        return nil
    }
}

/// When Bench removes its mapping though nobody turned the switch off:
/// when it quits, and when it launches with the switch off. What it then
/// runs is `TailscaleCommands.remove`: `off` only when 8443 is Bench's alone.
enum ServeCleanup {
    /// Whether to ask Tailscale at all: never in a demo, and only when Bench
    /// may have made a mapping (`everServed`).
    static func shouldLook(demo: Bool, everServed: Bool) -> Bool {
        !demo && everServed
    }
}

// MARK: Running the CLI

/// One run of the CLI.
struct TailscaleRun: Equatable, Sendable {
    /// Nil when it was stopped (timed out, or stopped early).
    var exitStatus: Int32?
    /// Standard output and error together.
    var output: String
    var timedOut = false
    /// Nothing ran: no Tailscale CLI signed by Tailscale is installed.
    var notInstalled = false

    static let none = TailscaleRun(exitStatus: nil, output: "", notInstalled: true)
}

/// Runs the CLI. The app's runs the real binary; the tests' are fakes.
protocol TailscaleRunner: Sendable {
    /// `stopWhen` ends the run early once the output so far satisfies it.
    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun
}

/// Where the CLI is: the app's own binary, run with arguments, and only from
/// an app bundle Tailscale Inc signed.
enum TailscaleCLI {
    static let standardApp = URL(fileURLWithPath: "/Applications/Tailscale.app")
    static let standard = binary(in: standardApp)
    /// The standalone app and the Mac App Store app.
    static let bundleIDs = ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]

    /// Tailscale Inc's Developer ID (team W5364U7YZB), as the standalone app
    /// is signed; or the Mac App Store's signature on Tailscale's own app,
    /// whose leaf certificate is Apple's and names no team, so it is known by
    /// the store's marker and its identifier, as its designated requirement
    /// does.
    static let requirement = #"(anchor apple generic and certificate leaf[subject.OU] = "W5364U7YZB")"#
        + #" or (anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists"#
        + #" and identifier "io.tailscale.ipn.macos")"#

    static func binary(in app: URL) -> URL {
        app.appendingPathComponent("Contents/MacOS/Tailscale")
    }

    /// `/Applications/Tailscale.app` first (both installs put it there),
    /// then wherever else Launch Services knows the app: app bundles.
    static func candidates(appURLs: [URL]) -> [URL] {
        var list = [standardApp]
        for app in appURLs where !list.contains(where: { $0.standardizedFileURL == app.standardizedFileURL }) {
            list.append(app)
        }
        return list
    }

    /// The first candidate's binary that can run and whose bundle passes
    /// `isTrusted`. One that fails is passed over as if it weren't there:
    /// an app that only borrows Tailscale's bundle id never runs. Launch
    /// Services is asked only when `/Applications` has none.
    static func locate(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
                       isTrusted: (URL) -> Bool = TailscaleSignature.shared.isTrusted,
                       apps: () -> [URL] = { bundleIDs.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) } })
        -> URL? {
        func usable(_ app: URL) -> Bool { isExecutable(binary(in: app).path) && isTrusted(app) }
        if usable(standardApp) { return standard }
        return candidates(appURLs: apps()).dropFirst().first(where: usable).map(binary(in:))
    }
}

/// Whether an app bundle is Tailscale's own, by its code signature
/// (`SecStaticCodeCheckValidity` against `TailscaleCLI.requirement`),
/// remembered per bundle path and modification date, so an app replaced in
/// place is checked again. The check is injected for the tests, which never
/// run a binary.
final class TailscaleSignature: @unchecked Sendable {
    static let shared = TailscaleSignature(check: TailscaleSignature.verify, stamp: TailscaleSignature.modified)

    private let lock = NSLock()
    private var known: [String: (stamp: [Date?], trusted: Bool)] = [:]
    private let check: @Sendable (URL) -> Bool
    private let stamp: @Sendable (URL) -> [Date?]

    init(check: @escaping @Sendable (URL) -> Bool, stamp: @escaping @Sendable (URL) -> [Date?]) {
        self.check = check
        self.stamp = stamp
    }

    func isTrusted(_ app: URL) -> Bool {
        let path = app.standardizedFileURL.path
        let mark = stamp(app)
        if let cached = lock.withLock({ known[path] }), cached.stamp == mark { return cached.trusted }
        let trusted = check(app)
        lock.withLock { known[path] = (mark, trusted) }
        if !trusted { log.error("A Tailscale app that Tailscale didn't sign was passed over") }
        return trusted
    }

    /// The bundle's and its binary's modification dates.
    @Sendable static func modified(_ app: URL) -> [Date?] {
        [app, TailscaleCLI.binary(in: app)].map {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }
    }

    /// The app's code signature, valid and meeting the requirement.
    @Sendable static func verify(_ app: URL) -> Bool {
        meets(app, requirement: TailscaleCLI.requirement)
    }

    static func meets(_ app: URL, requirement text: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
}

/// The app's runner: finds the CLI before each run (`TailscaleCLI.locate`,
/// its signature checks remembered), off the main thread, and runs it.
/// Without one, nothing runs and the run says so.
struct LiveTailscaleRunner: TailscaleRunner {
    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun {
        guard let executable = TailscaleCLI.locate() else { return .none }
        return await ProcessTailscaleRunner(executable: executable).run(arguments, timeout: timeout, stopWhen: stopWhen)
    }
}

/// The real runner: the binary with stdout and stderr in one pipe, read as
/// it comes, stopped at the timeout or once `stopWhen` holds.
struct ProcessTailscaleRunner: TailscaleRunner {
    let executable: URL

    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun {
        await withCheckedContinuation { continuation in
            let run = ProcessRun(continuation: continuation, stopWhen: stopWhen)
            run.start(executable, arguments, timeout: timeout)
        }
    }
}

/// One process, its output and its single answer: given once the output
/// has ended and the process has exited, or a moment after it was killed.
private final class ProcessRun: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TailscaleRun, Never>?
    private let stopWhen: (@Sendable (String) -> Bool)?
    private let process = Process()
    private var output = Data()
    private var ended = false
    private var exitStatus: Int32?
    private var timedOut = false
    private var stoppedEarly = false
    /// The most output kept: status JSON with many peers is the largest.
    private static let outputLimit = 4 * 1024 * 1024

    init(continuation: CheckedContinuation<TailscaleRun, Never>, stopWhen: (@Sendable (String) -> Bool)?) {
        self.continuation = continuation
        self.stopWhen = stopWhen
    }

    func start(_ executable: URL, _ arguments: [String], timeout: TimeInterval) {
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                lock.withLock { ended = true }
                finishIfDone()
                return
            }
            let text: String? = lock.withLock {
                if output.count < Self.outputLimit { output.append(chunk) }
                return stopWhen == nil || stoppedEarly ? nil : String(decoding: output, as: UTF8.self)
            }
            if let text, let stopWhen, stopWhen(text) {
                lock.withLock { stoppedEarly = true }
                stop()
            }
        }
        process.terminationHandler = { [self] process in
            let status = process.terminationStatus
            lock.withLock { exitStatus = status }
            finishIfDone()
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            finish()
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
            let running = lock.withLock { () -> Bool in
                guard continuation != nil else { return false }
                timedOut = true
                return true
            }
            if running { stop() }
        }
    }

    /// SIGTERM, SIGKILL a second later for one that ignores it, and the
    /// answer a second after that whatever still holds the pipe.
    private func stop() {
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in finish() }
        }
    }

    private func finishIfDone() {
        let done = lock.withLock { ended && exitStatus != nil }
        if done { finish() }
    }

    private func finish() {
        let answer: (CheckedContinuation<TailscaleRun, Never>, TailscaleRun)? = lock.withLock {
            guard let continuation else { return nil }
            self.continuation = nil
            let stopped = timedOut || stoppedEarly
            return (continuation, TailscaleRun(exitStatus: stopped ? nil : exitStatus,
                                               output: String(decoding: output, as: UTF8.self), timedOut: timedOut))
        }
        if let (continuation, run) = answer { continuation.resume(returning: run) }
    }
}

// MARK: The bridge

/// Bench's questions and its two changes, through the runner.
struct TailscaleBridge: Sendable {
    /// Nil when Tailscale isn't installed.
    let runner: (any TailscaleRunner)?

    /// The CLI is looked for, and its signature checked, when it is first
    /// needed: never for someone who never turns Remote on.
    static func live() -> TailscaleBridge {
        TailscaleBridge(runner: LiveTailscaleRunner())
    }

    var isInstalled: Bool { runner != nil }

    enum Check: Equatable, Sendable {
        case notInstalled
        /// The CLI ran but couldn't reach Tailscale, or said nothing usable.
        case notRunning
        case status(TailscaleStatus)
    }

    func status() async -> Check {
        guard let runner else { return .notInstalled }
        let run = await runner.run(TailscaleCommands.status, timeout: 10, stopWhen: nil)
        if run.notInstalled { return .notInstalled }
        // Status can exit non-zero while it still prints JSON (logged out,
        // say); what it printed decides.
        guard let status = TailscaleStatus(json: Data(Self.json(in: run.output).utf8)) else { return .notRunning }
        return .status(status)
    }

    func serveStatus(timeout: TimeInterval = 10) async -> ServeStatus? {
        await readServeStatus(timeout: timeout).status
    }

    /// `serve status`, and whether the CLI was there to ask.
    private func readServeStatus(timeout: TimeInterval) async -> (status: ServeStatus?, installed: Bool) {
        guard let runner else { return (nil, false) }
        let run = await runner.run(TailscaleCommands.serveStatus, timeout: timeout, stopWhen: nil)
        if run.notInstalled { return (nil, false) }
        guard run.exitStatus == 0 else { return (nil, true) }
        return (ServeStatus(json: Data(Self.json(in: run.output).utf8)), true)
    }

    enum Outcome: Equatable, Sendable {
        case serving
        /// The tailnet hasn't HTTPS on: the page that turns it on, when
        /// `serve` printed one.
        case httpsOff(URL?)
        /// 8443 is someone else's.
        case blocked
        case failed
    }

    /// What `serve` did, and whether Serve has anything else on this node
    /// (`ServeStatus.hasOtherMappings`): Settings warns that such a site
    /// shares Bench's address, and so its devices' sign-in cookie.
    struct Served: Equatable, Sendable {
        let outcome: Outcome
        let othersShare: Bool
    }

    /// Adds Bench's mapping for the listener on `port`, unless it is there.
    func serve(port: UInt16) async -> Served {
        guard let runner, let current = await serveStatus() else { return Served(outcome: .failed, othersShare: false) }
        let others = current.hasOtherMappings
        switch TailscaleCommands.plan(current, port: port) {
        case .nothing:
            return Served(outcome: .serving, othersShare: others)
        case .blocked:
            return Served(outcome: .blocked, othersShare: others)
        case .run(let commands):
            for arguments in commands {
                // `serve` waits for HTTPS to be turned on once it has printed
                // the page that does it: stop there, and say where it is.
                let run = await runner.run(arguments, timeout: 30) { TailscaleCommands.enableURL(in: $0) != nil }
                if let url = TailscaleCommands.enableURL(in: run.output) { return Served(outcome: .httpsOff(url), othersShare: others) }
                guard run.exitStatus == 0 else {
                    log.error("tailscale serve failed (\(run.timedOut ? "timed out" : "exit \(run.exitStatus ?? -1)", privacy: .public))")
                    return Served(outcome: .failed, othersShare: others)
                }
            }
            guard let after = await serveStatus(), after.port8443 == .bench(port: port) else {
                return Served(outcome: .failed, othersShare: others)
            }
            return Served(outcome: .serving, othersShare: after.hasOtherMappings)
        }
    }

    /// What removing Bench's mapping came to.
    enum Removal: Equatable, Sendable {
        /// None of Bench's is left (or there was none).
        case none
        /// No Tailscale CLI: with no Tailscale, nothing is served.
        case notInstalled
        /// `serve status` couldn't be read (Tailscale not running, say), so
        /// whether Bench's mapping is there isn't known.
        case unreadable
        /// `serve … off` failed.
        case failed
    }

    /// Removes Bench's mapping, and only Bench's: `off` runs only when
    /// `serve status` says 8443 is Bench's alone (`TailscaleCommands.remove`).
    func removeMapping(statusTimeout: TimeInterval = 10, offTimeout: TimeInterval = 15) async -> Removal {
        guard let runner else { return .notInstalled }
        let (current, installed) = await readServeStatus(timeout: statusTimeout)
        guard installed else { return .notInstalled }
        guard let current else { return .unreadable }
        guard let arguments = TailscaleCommands.remove(current) else { return .none }
        let run = await runner.run(arguments, timeout: offTimeout, stopWhen: nil)
        return run.exitStatus == 0 ? .none : .failed
    }

    /// True when none of Bench's mapping is left.
    func stopServing() async -> Bool {
        await removeMapping() == .none
    }

    /// The JSON object in the output: from the first `{` to the last `}`,
    /// past any warning the CLI printed around it.
    static func json(in output: String) -> String {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end else { return "" }
        return String(output[start...end])
    }
}
