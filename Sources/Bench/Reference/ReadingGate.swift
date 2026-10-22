// ReadingGate.swift — when the reference reader may read (DESIGN.md,
// Reference). Its reads run in the Claude Science page, on the page's main
// thread, so each one costs the user a few milliseconds of typing. The gate
// keeps them out of the way: one read at a time, none starting within 400 ms
// of a key press in the main window, and a read waits at most 2 s for the
// typing to pause before it goes anyway.
import AppKit

@MainActor
final class ReadingGate {
    static let shared = ReadingGate()

    /// No read starts within this long of a key press in the main window.
    nonisolated static let quiet: Duration = .milliseconds(400)
    /// A read waits at most this long, all told, for the typing to pause.
    nonisolated static let patience: Duration = .seconds(2)

    private let now: @Sendable () -> Date
    private let sleep: @MainActor (Duration) async -> Void
    private var lastKey: Date?
    private var monitor: Any?
    /// The last read queued: the next waits for it.
    private var tail: Task<Void, Never>?
    /// Reads whose body is running, for tests: never more than one.
    private(set) var inFlight = 0
    private(set) var mostInFlight = 0

    init(now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.now = now
        self.sleep = sleep
    }

    /// Watches key presses in the main window. The event always goes on.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.window != nil, event.window === MainWindowController.shared.windowIfLoaded {
                self?.noteKey()
            }
            return event
        }
    }

    /// A key was pressed in the main window (now, or at `date` for tests).
    func noteKey(at date: Date? = nil) {
        lastKey = date ?? now()
    }

    /// How much longer a read should wait, or nil to start now: within `quiet`
    /// of the last key press, the rest of that quiet, but never past `patience`
    /// of waiting all told. In whole milliseconds, so a wait is never a sliver
    /// a clock can't advance by.
    nonisolated static func pause(lastKey: Date?, now: Date, waited: Duration) -> Duration? {
        guard let lastKey, waited < patience else { return nil }
        let since = now.timeIntervalSince(lastKey)
        // A key press in the future (a clock that moved) counts as just now.
        let elapsed = since < 0 ? 0 : Int((since * 1_000).rounded())
        let quiet = Int((Self.quiet / .milliseconds(1)).rounded())
        let patience = Int((Self.patience / .milliseconds(1)).rounded())
        let waited = Int((waited / .milliseconds(1)).rounded())
        guard elapsed < quiet else { return nil }
        return .milliseconds(min(quiet - elapsed, patience - waited))
    }

    /// Runs `body` in its turn, once the typing has paused. Cancelling the
    /// calling task cancels the wait and `body` with it.
    func perform<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            await self.waitForQuiet()
            try Task.checkCancellation()
            self.inFlight += 1
            self.mostInFlight = max(self.mostInFlight, self.inFlight)
            defer { self.inFlight -= 1 }
            return try await body()
        }
        tail = Task { @MainActor in _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func waitForQuiet() async {
        var waited: Duration = .zero
        while !Task.isCancelled, let pause = Self.pause(lastKey: lastKey, now: now(), waited: waited) {
            await sleep(pause)
            waited += pause
        }
    }
}
