// StartRetry.swift — the main window reconnects on its own (DESIGN.md, Daemon
// and sign-in, "Reconnecting"). When Claude Science stops answering for a
// while (a cold start after an update on a busy Mac froze it for over a
// minute twice, 2026-10-21), the window used to show the failure and wait for
// Try again, and a press while it was still frozen failed again after 5 s.
// Now a failure that may pass is retried with a growing wait.
//
// An automatic try only asks `claude-science status`, with nothing changing on
// screen, and only a daemon that answers "running" is signed in to. It never
// starts one: during an update `status` can say "not running" while the new
// daemon waits for the port, and a second daemon on top of it is worse than a
// failure. Starting one stays with Try again and the app's launch.
//
// This file is the timing and nothing else. The status, the wait and what the
// window is doing come in as closures, so the rules are tested without a
// daemon; `WebContainer` owns the two this app uses: the window's own, and the
// one that waits for the daemon Claude Science's own app starts after the page
// shows its "now opens in its own window" dialog (Web/HandoverWatch.swift).
// Neither starts anything. Whether Capsid may start a daemon at all is
// `StartPlan`'s rule (Web/DaemonPolicy.swift): never beside that app.
import Foundation

@MainActor
final class StartRetry {
    /// Waits before each try, in seconds: quick at first, for a daemon that
    /// is only slow, then once a minute for about a quarter of an hour, then
    /// every five minutes. Each try costs `status` about 0.3 s of CPU, so a
    /// Claude Science that was stopped on purpose costs almost nothing.
    static let firstWaits = [5, 10, 20, 40]
    static let minuteTries = 15

    static func wait(before attempt: Int) -> Duration {
        if attempt < firstWaits.count { return .seconds(firstWaits[attempt]) }
        if attempt < firstWaits.count + minuteTries { return .seconds(60) }
        return .seconds(300)
    }

    /// A main-frame failure that means the daemon didn't answer, rather than
    /// a page it refused: what a retry can fix.
    static func isUnreachable(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut, NSURLErrorCannotFindHost].contains(error.code)
    }

    /// The daemon's status when it says it is running, else nil. Never starts it.
    private let probe: () async -> CLIStatus?
    private let wait: (Duration) async -> Void
    /// The window still shows the failure and no start is under way. Asked
    /// after every wait, since Try again may have been pressed meanwhile.
    private let stillFailed: () -> Bool
    /// Signs in to the daemon that answered.
    private let attach: (CLIStatus) -> Void

    /// Tries made since the last success or Try again: it picks the wait.
    private(set) var attempt = 0
    private var trying: Task<Void, Never>?
    /// Bumped by every `stop`, so a try that was waiting when it came ends
    /// without touching a newer one.
    private var generation = 0

    /// The app's `WebContainer` makes one; tests make their own.
    init(probe: @escaping () async -> CLIStatus? = { await DaemonController.runningStatus() },
         wait: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0, tolerance: .seconds(1)) },
         stillFailed: @escaping () -> Bool,
         attach: @escaping (CLIStatus) -> Void) {
        self.probe = probe
        self.wait = wait
        self.stillFailed = stillFailed
        self.attach = attach
    }

    /// Whether a try is waiting or asking.
    var isTrying: Bool { trying != nil }

    /// A failure that may pass: try again after the next wait, and keep
    /// trying until the daemon answers. A second call while trying does
    /// nothing.
    func begin() {
        guard trying == nil else { return }
        let mine = generation
        trying = Task { [weak self] in await self?.run(mine) }
    }

    /// The page is up, Try again was pressed, or the failure is one a retry
    /// can't fix. `resetting` starts the waits over, for a success or a press.
    func stop(resetting: Bool) {
        generation += 1
        trying?.cancel()
        trying = nil
        if resetting { attempt = 0 }
    }

    private func run(_ mine: Int) async {
        while generation == mine {
            let pause = Self.wait(before: attempt)
            attempt += 1
            await wait(pause)
            guard generation == mine, stillFailed() else { break }
            guard let daemon = await probe() else { continue }
            guard generation == mine, stillFailed() else { break }
            // Cleared before signing in, so if that fails too the failure can
            // begin trying again.
            trying = nil
            attach(daemon)
            return
        }
        if generation == mine { trying = nil }
    }
}
