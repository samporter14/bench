// WriteDeadline.swift — every write to Claude Science ends (DESIGN.md, Bounded
// writes). A write that goes into the page and never comes back used to hold
// its card, its queue behind it and its panel for as long as the page cared to
// stay silent. Now each one has a deadline in the page (an AbortController
// covering the CSRF refresh, the POST and its body), a deadline in Swift beyond
// that (the page itself may be stuck), and, where a session's actions queue up,
// a deadline for the whole turn.
//
// A write that ran out of time is neither done nor failed: it is *unknown*. The
// callers say so ("Not sure that went through. Checking…"), ask the session with
// one fresh read whether it landed, and then show it done or offer Retry. They
// never send it again on their own.
//
// Nothing here runs a script in the page: the three call sites (WebAPI.swift,
// SessionWriter.swift, RemotePhotoUpload.swift) pass theirs in as a closure.
import Foundation

enum WriteDeadline {
    // MARK: How long

    /// A small write, as the page runs it from its first byte to its last:
    /// approving a plan, answering a question, answering a permission request,
    /// sending a message, starting a session. The CSRF refresh, the POST and
    /// reading its answer share this one deadline.
    static let small: Duration = .seconds(20)

    /// An upload of `bytes`: a minute for a photo, more for a large file (5 s
    /// a MiB over 30 s, at most three minutes).
    static func upload(bytes: Int) -> Duration {
        let mebibytes = (max(0, bytes) + 1_048_575) / 1_048_576
        return .seconds(min(180, max(60, 30 + 5 * mebibytes)))
    }

    /// Swift waits this much longer than the page, so the page normally says
    /// first, and says why.
    static let grace: Duration = .seconds(5)

    /// One fresh read that settles an unknown write.
    static let settleRead: Duration = .seconds(20)

    /// One session's turn in the queue (`RemoteSessions.runSerially`): the read
    /// before the write, the write, the read after it, and the uploads the turn
    /// makes. Every step has a deadline of its own; this is the one beneath
    /// them, so that a turn that is stuck somewhere nobody thought of still
    /// lets the next one start.
    static func turn(uploadBytes: [Int] = []) -> Duration {
        let steps = settleRead + small + grace + settleRead + settleRead
        return uploadBytes.reduce(steps) { $0 + upload(bytes: $1) + grace }
    }

    /// A duration as the milliseconds a page script is given.
    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: The wait

    /// How a timed wait ended.
    enum Raced<Value: Sendable>: Sendable {
        case finished(Value)
        case timedOut
        /// The caller was cancelled first (`Cancel.finish`).
        case cancelled
    }

    /// What the caller's cancellation does to a wait.
    enum Cancel: Sendable {
        /// Ends the wait at once with `.cancelled`, and cancels the work.
        case finish
        /// Cancels the work and keeps waiting for it: it is under way and
        /// can't be taken back, but it can stop at its next step.
        case propagate
        /// Nothing: a write that has gone is waited for as it is.
        case ignore
    }

    /// The default wait: real time.
    static let sleep: @MainActor @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// The first of `work` and the timer to finish answers, exactly once, and
    /// cancels the other. Work that outlives its deadline is not stopped (a
    /// page script can't be), only cancelled: its late answer goes nowhere.
    /// `limit` nil is no timer.
    @MainActor
    static func race<Value: Sendable>(_ limit: Duration?, wait: @escaping @MainActor (Duration) async -> Void = WriteDeadline.sleep,
                                      cancel: Cancel = .finish,
                                      _ work: @escaping @MainActor () async -> Value) async -> Raced<Value> {
        let state = RaceState<Value>()
        let started: @MainActor () async -> Raced<Value> = {
            await withCheckedContinuation { continuation in
                state.continuation = continuation
                state.work = Task { @MainActor in state.finish(.finished(await work())) }
                if let limit {
                    state.timer = Task { @MainActor in
                        await wait(limit)
                        state.finish(.timedOut)
                    }
                }
            }
        }
        switch cancel {
        case .ignore:
            return await started()
        case .finish:
            return await withTaskCancellationHandler {
                await started()
            } onCancel: {
                Task { @MainActor in state.finish(.cancelled) }
            }
        case .propagate:
            return await withTaskCancellationHandler {
                await started()
            } onCancel: {
                Task { @MainActor in state.work?.cancel() }
            }
        }
    }

    /// Awaits a call into the page for `limit` at most (the page's own deadline
    /// and `grace`). The call's error comes back as it is; no answer in time
    /// is `WebAPIError.timedOut`: the page may have sent it.
    @MainActor
    static func bridge<Value: Sendable>(_ limit: Duration, wait: @escaping @MainActor (Duration) async -> Void = WriteDeadline.sleep,
                                        _ call: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let raced = await race(limit, wait: wait, cancel: .ignore) { () async -> Result<Value, any Error> in
            do { return .success(try await call()) } catch { return .failure(error) }
        }
        switch raced {
        case .finished(let result): return try result.get()
        case .timedOut, .cancelled: throw WebAPIError.timedOut
        }
    }
}

@MainActor
private final class RaceState<Value: Sendable> {
    var continuation: CheckedContinuation<WriteDeadline.Raced<Value>, Never>?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?

    func finish(_ value: WriteDeadline.Raced<Value>) {
        guard let continuation else { return }
        self.continuation = nil
        work?.cancel()
        timer?.cancel()
        work = nil
        timer = nil
        continuation.resume(returning: value)
    }
}
