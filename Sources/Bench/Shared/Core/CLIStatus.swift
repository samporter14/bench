// CLIStatus.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.

import Foundation

/// What `claude-science status` tells us. Documented, always exits 0,
/// no auth to manage.
public struct CLIStatus: Sendable, Equatable {
    public let running: Bool
    public let activeFrames: Int
    public let activeConversations: Int
    public let version: String
    /// The port the daemon serves on, or nil when `status` didn't say. Not
    /// 8765 then: the daemon in Claude Science's own app takes an ephemeral
    /// port, and a guess would reach another program.
    public let port: Int?
    /// The daemon's process, so later checks can ask the kernel whether it is
    /// still alive instead of running this command again.
    public let pid: Int32?
    /// Where the daemon keeps its data (`daemon.data_dir`), when it says.
    public let dataDir: String?
    /// Who started the daemon (`daemon.launch_context`): "app-child" when
    /// Claude Science's own app did. Nil for a status that doesn't say.
    public let launchContext: String?
    /// How far the daemon's start has come (`daemon.boot`): "serving" once up.
    public let boot: String?
    /// The host its address uses (`daemon.url_host`): "localhost" or "127.0.0.1".
    public let urlHost: String?
    /// Whether it insists on a token to sign in (`daemon.require_token`), when it says.
    public let requireToken: Bool?

    public init(running: Bool, activeFrames: Int, activeConversations: Int, version: String, port: Int?,
                pid: Int32? = nil, dataDir: String? = nil,
                launchContext: String? = nil, boot: String? = nil, urlHost: String? = nil, requireToken: Bool? = nil) {
        self.running = running
        self.activeFrames = activeFrames
        self.activeConversations = activeConversations
        self.version = version
        self.port = port
        self.pid = pid
        self.dataDir = dataDir
        self.launchContext = launchContext
        self.boot = boot
        self.urlHost = urlHost
        self.requireToken = requireToken
    }

    /// The daemon is Claude Science's own app's child: the app owns it, so
    /// Capsid never starts, stops or restarts one (DESIGN.md, 1.0 spikes S1).
    public var isAppChild: Bool { launchContext == CLIStatus.appChild }

    public static let appChild = "app-child"
}

/// Where the running daemon keeps its data, as its last `status` said. The
/// database is looked for there first: the daemon doesn't always use
/// ~/.claude-science (on a Mac with macOS 27 the folder there held an empty
/// database while the real one lived elsewhere). Bench's own addition.
enum ScienceDataDirectory {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: URL?

    static var current: URL? {
        lock.lock(); defer { lock.unlock() }
        return known
    }

    static func remember(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        known = URL(fileURLWithPath: path)
    }
}

/// The running daemon's process, as its last `status` said, so the Lab can
/// hear the moment it exits (Bench's own addition). Its write-ahead log going
/// away used to say so, but the log stays when another connection (Bench's)
/// is open as the daemon closes.
enum ScienceDaemonProcess {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: Int32?

    static var current: Int32? {
        lock.lock(); defer { lock.unlock() }
        return known
    }

    static func remember(_ pid: Int32?) {
        guard let pid, pid > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        known = pid
    }
}

/// How the daemon was started, as the last running `status` said (Bench's own
/// addition). `serve` is never run when it was Claude Science's own app, even
/// after the app has quit and `status` says nothing is running.
enum ScienceLaunchContext {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: String?

    static var current: String? {
        lock.lock(); defer { lock.unlock() }
        return known
    }

    /// Always replaces what was there, nil included: a daemon started some
    /// other way is not the app's.
    static func remember(_ context: String?) {
        lock.lock(); defer { lock.unlock() }
        known = context
    }
}

/// Where `claude-science` is looked for, in order. Pure: the places that hold
/// it and the install are given. Inside Claude Science's own app the tool
/// stops maintaining the `~/.local/bin` link, so once that app is installed
/// its own copy comes first; with the launcher that opens a tab, the order is
/// the one it always was.
func cliCandidates(home: String, install: ScienceInstall) -> [String] {
    (install.bundledCLI.map { [$0] } ?? []) + [
        home + "/.local/bin/claude-science",
        home + "/.claude-science/bin/claude-science",
        "/opt/homebrew/bin/claude-science",
        "/usr/local/bin/claude-science",
    ]
}

/// Locate the `claude-science` binary. Never writes, only resolves a path.
func resolveCLI(install: ScienceInstall = .current(),
                isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
    for path in cliCandidates(home: NSHomeDirectory(), install: install) where isExecutable(path) {
        return URL(fileURLWithPath: path)
    }
    // PATH fallback.
    guard
        let (_, data) = try? runProcess(URL(fileURLWithPath: "/usr/bin/which"), ["claude-science"], timeout: 3),
        let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !out.isEmpty, FileManager.default.isExecutableFile(atPath: out)
    else { return nil }
    return URL(fileURLWithPath: out)
}

/// Run `claude-science status` with a timeout and parse the fields we need.
/// Throws `ScienceError.daemonNotRunning` when `.running` is false.
///
/// It costs about 0.3 s of CPU, so callers check the daemon's pid between
/// runs rather than calling this on every refresh.
public func fetchCLIStatus(timeout: TimeInterval = 5) throws -> CLIStatus {
    guard let cli = resolveCLI() else { throw ScienceError.cliMissing }
    let data: Data
    let status: Int32
    do {
        (status, data) = try runProcess(cli, ["status"], timeout: timeout)
    } catch SubprocessFailure.timedOut {
        throw ScienceError.cliFailed("timed out")
    } catch {
        throw ScienceError.cliFailed("\(error)")
    }
    let parsed = try parseCLIStatus(data, exitStatus: status)
    ScienceDataDirectory.remember(parsed.dataDir)
    ScienceDaemonProcess.remember(parsed.pid)
    ScienceLaunchContext.remember(parsed.launchContext)
    return parsed
}

/// The fields Bench needs from `claude-science status`'s JSON. Only an
/// explicit `"running": false` throws `daemonNotRunning`, the one answer that
/// lets Bench start a daemon; anything else unexpected is `cliFailed`.
func parseCLIStatus(_ data: Data, exitStatus status: Int32) throws -> CLIStatus {
    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw ScienceError.cliFailed("unparseable output") }

    // Only an explicit `"running": false` means stopped, and so permission
    // to start one. Anything else (an error reply, a missing field) is a
    // failed check: starting a daemon then could make a second one.
    guard let running = json["running"] as? Bool else {
        throw ScienceError.cliFailed("no running field (exit \(status))")
    }
    guard running else { throw ScienceError.daemonNotRunning }
    let daemon = json["daemon"] as? [String: Any] ?? [:]
    // active_frames lives inside daemon; fall back to 0 (idle) when absent.
    let activeFrames = (daemon["active_frames"] as? Int)
        ?? (daemon["activeFrames"] as? Int) ?? 0
    let activeConversations = (daemon["active_conversations"] as? Int)
        ?? (daemon["activeConversations"] as? Int) ?? 0
    let version = (json["version"] as? String) ?? "unknown"
    // No port is "unknown", not 8765 (see `CLIStatus.port`).
    let port = strictInt(json["port"]).flatMap { (1...65535).contains($0) ? $0 : nil }
    let dataDir = daemon["data_dir"] as? String
    // The four keys Claude Science's own app added, each of exactly its type
    // or ignored, and none needed: an older status parses as it always did.
    return CLIStatus(
        running: true,
        activeFrames: activeFrames,
        activeConversations: activeConversations,
        version: version,
        port: port,
        pid: (json["pid"] as? Int).map(Int32.init),
        dataDir: dataDir,
        launchContext: strictWord(daemon["launch_context"]),
        boot: strictWord(daemon["boot"]),
        urlHost: strictWord(daemon["url_host"]),
        requireToken: strictBool(daemon["require_token"])
    )
}

/// A JSON number that is a whole number, not a boolean (which Foundation
/// would also hand over as 0 or 1) and not a fraction.
private func strictInt(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let whole = number.intValue
    return number.doubleValue == Double(whole) ? whole : nil
}

/// A JSON true or false and nothing else: not 1, not "true".
private func strictBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

/// A short word from the daemon (a launch context, a boot stage, a host):
/// a string of printable ASCII up to 40 characters, lowercased, else nil.
private func strictWord(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased(),
          !text.isEmpty, text.utf8.count <= 40,
          text.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { return nil }
    return text
}

/// Whether a process is still alive: `kill` with signal 0 sends nothing, it
/// only checks. Microseconds, where the status command takes 0.3 s.
func processIsAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

/// A fresh single-use sign-in code from `claude-science url`, the same code
/// its own `open` command uses. It expires in about three minutes.
func fetchLoginNonce(timeout: TimeInterval = 5) -> String? {
    guard
        let cli = resolveCLI(),
        let result = try? runProcess(cli, ["url"], timeout: timeout), result.status == 0,
        let text = String(data: result.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        let url = URLComponents(string: text)
    else { return nil }
    return url.queryItems?.first(where: { $0.name == "nonce" })?.value
}

/// `url` with a sign-in code attached. The daemon accepts the code on any of
/// its pages: signed-in browsers go straight there, others see one Sign in
/// button that lands on the same page.
public func addingLoginNonce(_ nonce: String, to url: URL) -> URL {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    var items = (parts.queryItems ?? []).filter { $0.name != "nonce" }
    items.append(URLQueryItem(name: "nonce", value: nonce))
    parts.queryItems = items
    return parts.url ?? url
}
