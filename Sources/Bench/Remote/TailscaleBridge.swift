// TailscaleBridge.swift — what Bench asks of Tailscale (DESIGN.md, Bench on
// your phone → Transport and trust): whether it is installed, running and
// signed in, the node's name, whether the tailnet has HTTPS, and Bench's one
// Serve mapping, HTTPS 8443 → http://127.0.0.1:<port>.
//
// Bench reads `serve status --json` before every change and adds or removes
// only its own mapping: never `serve reset`, never Funnel, never another
// mapping. The parsing and the exact arguments are pure and tested on
// fixtures; running the CLI goes through one injectable runner.
import AppKit
import Foundation
import OSLog

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

    init(running: Bool, login: String?, dnsName: String?, httpsEnabled: Bool) {
        self.running = running
        self.login = login
        self.dnsName = dnsName
        self.httpsEnabled = httpsEnabled
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
        var login: String?
        if let userID = me?["UserID"] as? NSNumber, let users = root["User"] as? [String: Any],
           let user = users[userID.stringValue] as? [String: Any] {
            login = user["LoginName"] as? String
        }
        self.login = login?.isEmpty == false ? login : nil
        httpsEnabled = !((root["CertDomains"] as? [String]) ?? []).isEmpty
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

// MARK: Running the CLI

/// One run of the CLI.
struct TailscaleRun: Equatable, Sendable {
    /// Nil when it was stopped (timed out, or stopped early).
    var exitStatus: Int32?
    /// Standard output and error together.
    var output: String
    var timedOut = false
}

/// Runs the CLI. The app's runs the real binary; the tests' are fakes.
protocol TailscaleRunner: Sendable {
    /// `stopWhen` ends the run early once the output so far satisfies it.
    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun
}

/// Where the CLI is: the app's own binary, run with arguments.
enum TailscaleCLI {
    static let standard = URL(fileURLWithPath: "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
    /// The standalone app and the Mac App Store app.
    static let bundleIDs = ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]

    /// `/Applications/Tailscale.app` first (both installs put it there),
    /// then wherever else Launch Services knows the app.
    static func candidates(appURLs: [URL]) -> [URL] {
        var list = [standard]
        for app in appURLs {
            let binary = app.appendingPathComponent("Contents/MacOS/Tailscale")
            if !list.contains(binary) { list.append(binary) }
        }
        return list
    }

    static func locate(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        let apps = bundleIDs.flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
        return candidates(appURLs: apps).first { isExecutable($0.path) }
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

    static func live() -> TailscaleBridge {
        TailscaleBridge(runner: TailscaleCLI.locate().map(ProcessTailscaleRunner.init(executable:)))
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
        // Status can exit non-zero while it still prints JSON (logged out,
        // say); what it printed decides.
        guard let status = TailscaleStatus(json: Data(Self.json(in: run.output).utf8)) else { return .notRunning }
        return .status(status)
    }

    func serveStatus() async -> ServeStatus? {
        guard let runner else { return nil }
        let run = await runner.run(TailscaleCommands.serveStatus, timeout: 10, stopWhen: nil)
        guard run.exitStatus == 0 else { return nil }
        return ServeStatus(json: Data(Self.json(in: run.output).utf8))
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

    /// Adds Bench's mapping for the listener on `port`, unless it is there.
    func serve(port: UInt16) async -> Outcome {
        guard let runner, let current = await serveStatus() else { return .failed }
        switch TailscaleCommands.plan(current, port: port) {
        case .nothing:
            return .serving
        case .blocked:
            return .blocked
        case .run(let commands):
            for arguments in commands {
                // `serve` waits for HTTPS to be turned on once it has printed
                // the page that does it: stop there, and say where it is.
                let run = await runner.run(arguments, timeout: 30) { TailscaleCommands.enableURL(in: $0) != nil }
                if let url = TailscaleCommands.enableURL(in: run.output) { return .httpsOff(url) }
                guard run.exitStatus == 0 else {
                    log.error("tailscale serve failed (\(run.timedOut ? "timed out" : "exit \(run.exitStatus ?? -1)", privacy: .public))")
                    return .failed
                }
            }
            guard let after = await serveStatus(), after.port8443 == .bench(port: port) else { return .failed }
            return .serving
        }
    }

    /// Removes Bench's mapping, and only Bench's. True when none is left.
    func stopServing() async -> Bool {
        guard let runner, let current = await serveStatus() else { return false }
        guard let arguments = TailscaleCommands.remove(current) else { return true }
        let run = await runner.run(arguments, timeout: 15, stopWhen: nil)
        return run.exitStatus == 0
    }

    /// The JSON object in the output: from the first `{` to the last `}`,
    /// past any warning the CLI printed around it.
    static func json(in output: String) -> String {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end else { return "" }
        return String(output[start...end])
    }
}
