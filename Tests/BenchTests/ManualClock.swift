// ManualClock.swift — a clock a test sets off. A deadline that waits on it ends when
// the test says the time is up, not after however long a loaded machine takes, so a
// test of "the turn ran out of time" can't be beaten by the work it is waiting for.
import Foundation

@MainActor
final class ManualClock {
    private var waiters: [UUID: (duration: Duration, continuation: CheckedContinuation<Void, Never>)] = [:]

    /// How many deadlines are waiting on it, of `duration` when given.
    func waiting(_ duration: Duration? = nil) -> Int {
        waiters.values.filter { duration == nil || $0.duration == duration }.count
    }

    /// Waits until `fire()`, or until the waiting task is cancelled (a deadline whose work finished).
    func wait(_ duration: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiters[id] = (duration, $0) }
        } onCancel: {
            Task { @MainActor in self.waiters.removeValue(forKey: id)?.continuation.resume() }
        }
    }

    /// The time is up for every deadline waiting now, or only those of `duration`.
    func fire(_ duration: Duration? = nil) {
        for (id, waiter) in waiters where duration == nil || waiter.duration == duration {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    /// Lets the test wait until `count` deadlines are waiting.
    func until(waiting count: Int, _ duration: Duration? = nil) async {
        for _ in 0..<4_000 where waiting(duration) < count { await Task.yield() }
    }
}
