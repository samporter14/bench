// DaemonController.swift — finds or starts the Claude Science daemon and
// fetches sign-in codes (DESIGN.md, Daemon and sign-in). Every command
// blocks, so each runs on a background queue and the callers await it.
import Foundation
import os

/// Why the daemon couldn't be reached, as a sentence for the failure overlay.
enum DaemonError: Error {
    case cliMissing
    case statusFailed
    case launchFailed(String)
    case didNotStart

    var sentence: String {
        switch self {
        case .cliMissing:
            return "Can't find the claude-science tool. Install Claude Science, then try again."
        case .statusFailed:
            return "Can't read Claude Science's status. Try again in a moment."
        case .launchFailed(let reason):
            return "Couldn't start Claude Science: \(reason)"
        case .didNotStart:
            return "Claude Science didn't start within \(Int(DaemonController.startTimeout)) seconds."
        }
    }
}

enum DaemonController {
    static let startTimeout: TimeInterval = 20
    private static let pollInterval = Duration.milliseconds(500)

    /// The running daemon's status. If it isn't running, starts it once and
    /// polls until it is. `serve` is only ever run after `status` has said
    /// plainly that nothing is running: any other failure stops here, since a
    /// second daemon on top of a running one is worse than an error.
    static func ensureRunning() async throws -> CLIStatus {
        if let running = try await status() { return running }

        try await offMain { try launchDetached() }
        Logger.web.info("Started the daemon; waiting for it")

        let deadline = ContinuousClock.now + .seconds(startTimeout)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
            // A status command that fails while the daemon comes up is not
            // final, so only `cliMissing` ends the wait early.
            do {
                if let running = try await status() { return running }
            } catch DaemonError.statusFailed {
                continue
            }
        }
        throw DaemonError.didNotStart
    }

    /// A fresh single-use sign-in code, or nil when the CLI can't give one.
    static func freshNonce() async -> String? {
        try? await offMain { fetchLoginNonce() }
    }

    /// `nil` means "the daemon is not running".
    private static func status() async throws -> CLIStatus? {
        do {
            return try await offMain { try fetchCLIStatus() }
        } catch ScienceError.daemonNotRunning {
            return nil
        } catch ScienceError.cliMissing {
            throw DaemonError.cliMissing
        } catch {
            Logger.web.error("status failed: \(String(describing: error), privacy: .public)")
            throw DaemonError.statusFailed
        }
    }

    /// `claude-science serve --no-browser --detached`, with no other flags.
    ///
    /// This is a plain Process that nobody waits on or kills. `runProcess`
    /// would SIGTERM the CLI on a timeout, and if the detached daemon shared
    /// its pipe that timeout would fire, so it must never see this command.
    private static func launchDetached() throws {
        guard let cli = resolveCLI() else { throw DaemonError.cliMissing }
        let task = Process()
        task.executableURL = cli
        task.arguments = ["serve", "--no-browser", "--detached"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            throw DaemonError.launchFailed(error.localizedDescription)
        }
    }

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
