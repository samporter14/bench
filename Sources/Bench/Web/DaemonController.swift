// DaemonController.swift — finds or starts the Claude Science daemon and
// fetches sign-in codes (DESIGN.md, Daemon and sign-in). Every command
// blocks, so each runs on a background queue and the callers await it.
import Foundation
import os

/// Why the daemon couldn't be reached, as a sentence for the failure overlay.
enum DaemonError: Error, Equatable {
    case cliMissing
    case statusFailed
    case launchFailed(String)
    case didNotStart
    /// Claude Science's own app starts its daemon; Capsid waits for it
    /// (`StartPlan.waitForApp`).
    case appOwnsServer
    /// The daemon runs but `status` names no port, and Capsid doesn't guess.
    case noPort

    var sentence: String {
        switch self {
        case .cliMissing:
            return "Can't find the claude-science tool. Install Claude Science, then try again."
        case .statusFailed:
            return "Can't read Claude Science's status."
        case .launchFailed(let reason):
            return "Couldn't start Claude Science: \(reason)"
        case .didNotStart:
            return "Claude Science didn't start within \(Int(DaemonController.startTimeout)) seconds."
        case .appOwnsServer:
            return CompanionSentence.waitingForApp
        case .noPort:
            return "Claude Science is running but hasn't said which port it uses yet."
        }
    }

    /// Whether it may pass by itself, so the window keeps trying
    /// (Web/StartRetry.swift): a daemon too busy to answer, or one still
    /// coming up. A missing tool or a failed launch needs the user.
    var isTemporary: Bool {
        switch self {
        case .statusFailed, .didNotStart, .appOwnsServer, .noPort: true
        case .cliMissing, .launchFailed: false
        }
    }
}

enum DaemonController {
    static let startTimeout: TimeInterval = 20
    private static let pollInterval = Duration.milliseconds(500)

    /// The running daemon's status. If it isn't running, starts it once and
    /// polls until it is. `serve` is only ever run after `status` has said
    /// plainly that nothing is running, and never beside Claude Science's own
    /// app (`StartPlan`): any other failure stops here, since a second daemon
    /// on top of a running one is worse than an error. `handoverSeen`: the page
    /// showed the dialog that says Claude Science now opens in its own window.
    static func ensureRunning(handoverSeen: Bool = false) async throws -> CLIStatus {
        let answer = try await statusAnswer()
        let install = await installedOpens()
        let plan = StartPlan.decide(answer, install: install, lastLaunchContext: ScienceLaunchContext.current,
                                    handoverSeen: handoverSeen)
        switch plan {
        case .attach(let running):
            return running
        case .giveUp:
            throw DaemonError.statusFailed
        case .waitForApp(let reason):
            Logger.web.info("Not starting a daemon: Claude Science's app starts its own (\(String(describing: reason), privacy: .public))")
            throw DaemonError.appOwnsServer
        case .serve:
            break
        }

        try await offMain { try launchDetached() }
        Logger.web.info("Started the daemon; waiting for it")

        let deadline = ContinuousClock.now + .seconds(startTimeout)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
            // A status command that fails while the daemon comes up is not
            // final, so only `cliMissing` ends the wait early. One that runs
            // without a port isn't up yet.
            do {
                if let running = try await status(), running.port != nil { return running }
            } catch DaemonError.statusFailed {
                continue
            }
        }
        throw DaemonError.didNotStart
    }

    /// How Claude Science opens on this Mac, looked at off the main thread.
    static func installedOpens() async -> ScienceInstall.Opens {
        await offMainValue { ScienceInstall.current().opens }
    }

    /// A fresh single-use sign-in code, or nil when the CLI can't give one.
    static func freshNonce() async -> String? {
        try? await offMain { fetchLoginNonce() }
    }

    /// The daemon's status when it answers that it is running, else nil (not
    /// running, or no answer). Never starts one: the window's automatic
    /// retries use this, and during an update `status` can say "not running"
    /// while the new daemon waits for the port.
    static func runningStatus() async -> CLIStatus? {
        try? await status()
    }

    /// `nil` means "the daemon is not running".
    private static func status() async throws -> CLIStatus? {
        switch try await statusAnswer() {
        case .running(let running): return running
        case .notRunning, .failed: return nil
        }
    }

    /// Asks `status`: running, plainly not running, or an error.
    private static func statusAnswer() async throws -> StatusAnswer {
        do {
            return .running(try await offMain { try fetchCLIStatus() })
        } catch ScienceError.daemonNotRunning {
            return .notRunning
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

    private static func offMainValue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
