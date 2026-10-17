// ShelfTransfers.swift — every read the results shelf makes, in one queue
// (DESIGN.md, Results): lists, thumbnails, Quick Look's and a drag's copies,
// Copy, Save and Save All. At most `limit` (two) run at once, whoever asked.
//
// A read is an operation, one per `ArtifactRead`: two askers of the same read
// share it, so a version is downloaded once. Each asker is a consumer with a
// token of its own. A consumer that stops waiting (its task cancelled) takes
// back only its own token and gets `.cancelled`; the others keep waiting. An
// operation nobody waits for any more never starts if it was queued, and is
// cancelled if it was running: its reader's task is cancelled, which for the
// page's reader also aborts the fetch (ArtifactReadAbort). Its slot stays
// taken until the reader has actually returned: a slot is held from a read's
// start until its reader comes back, never only until its waiters stop.
//
// Which goes next: what the person asked for (Quick Look, a drag, Copy,
// Save) before Save All, Save All before lists, lists before thumbnails, the
// oldest first within each. A queued read that has seen `promotion` others
// start ahead of it goes next whatever it is, so none waits for ever.
//
// The time limit counts from a read's start, not its wait in line. When it
// passes, every consumer gets `.timedOut` at once and the reader is
// cancelled; its slot is held until it returns.
import Foundation

/// What a shelf read came to, for one consumer.
enum ShelfTransferResult: Equatable, Sendable {
    /// The reader answered.
    case answered(ArtifactReadOutcome)
    /// The time limit passed first.
    case timedOut
    /// The page wasn't up when the read's turn came: nothing was read.
    case notReady
    /// This consumer stopped waiting, or the window closed.
    case cancelled
}

@MainActor
final class ShelfTransfers {
    /// Who a read is for, in the order reads go.
    enum Priority: Int, Comparable, Sendable {
        case thumbnail, list, saveAll, foreground

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// A queued read that has seen this many others start goes next.
    static let promotion = 8

    /// One caller waiting for a read.
    @MainActor
    private final class Consumer {
        let continuation: CheckedContinuation<ShelfTransferResult, Never>
        let priority: Priority
        /// Save: a read the person asked to keep goes on when the window closes.
        let keepsOnClose: Bool
        let started: (@MainActor () -> Void)?

        init(_ continuation: CheckedContinuation<ShelfTransferResult, Never>, priority: Priority,
             keepsOnClose: Bool, started: (@MainActor () -> Void)?) {
            self.continuation = continuation
            self.priority = priority
            self.keepsOnClose = keepsOnClose
            self.started = started
        }
    }

    /// One read, shared by everyone waiting for it.
    @MainActor
    private final class Operation {
        let key: ArtifactRead
        /// When it was queued: the oldest goes first.
        let order: Int
        var consumers: [Int: Consumer] = [:]
        /// Reads started while this one waited.
        var passedOver = 0
        /// From its start until its reader returns.
        var running = false
        var reader: Task<Void, Never>?
        var timer: Task<Void, Never>?

        init(key: ArtifactRead, order: Int) {
            self.key = key
            self.order = order
        }

        var priority: Priority { consumers.values.map(\.priority).max() ?? .thumbnail }
    }

    let limit: Int
    private let reader: @MainActor (ArtifactRead) async -> ArtifactReadOutcome
    private let isReady: @MainActor () -> Bool
    private let timeout: Duration
    private let wait: @MainActor (Duration) async -> Void

    /// Operations a new consumer can join: queued, or running and still wanted.
    private var live: [ArtifactRead: Operation] = [:]
    /// Waiting their turn.
    private var queue: [Operation] = []
    /// Every operation whose reader hasn't returned, wanted or not: the slots.
    private var readers: [ObjectIdentifier: Operation] = [:]
    /// Which operation each consumer's token is in.
    private var owners: [Int: Operation] = [:]
    private var nextToken = 0
    private var nextOrder = 0

    init(limit: Int, read: @escaping @MainActor (ArtifactRead) async -> ArtifactReadOutcome,
         isReady: @escaping @MainActor () -> Bool, timeout: Duration,
         wait: @escaping @MainActor (Duration) async -> Void) {
        self.limit = limit
        reader = read
        self.isReady = isReady
        self.timeout = timeout
        self.wait = wait
    }

    /// Reads under way, wanted or not: never more than `limit`.
    var active: Int { readers.count }
    /// The most that were ever under way at once.
    private(set) var mostActive = 0
    /// Reads under way that someone still waits for.
    var running: Int { readers.values.filter { !$0.consumers.isEmpty }.count }
    /// Reads waiting their turn.
    var queued: Int { queue.count }
    /// How many wait for a read that can still be joined: for tests.
    func waiting(for key: ArtifactRead) -> Int { live[key]?.consumers.count ?? 0 }

    // MARK: Asking

    /// Reads `key` in its turn, sharing a read of the same key already
    /// queued or running. `started` is called when the read starts (at
    /// once, if it is running). Cancelling the calling task withdraws this
    /// consumer only, and it gets `.cancelled`.
    func read(_ key: ArtifactRead, priority: Priority, keepsOnClose: Bool = false,
              started: (@MainActor () -> Void)? = nil) async -> ShelfTransferResult {
        let token = nextToken
        nextToken += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                join(key, token: token, Consumer(continuation, priority: priority, keepsOnClose: keepsOnClose,
                                                 started: started))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.withdraw(token) }
        }
    }

    /// The window closed: every consumer but a Save's gets `.cancelled` now.
    /// What nobody waits for any more never starts, or is cancelled; its slot
    /// stays held until its reader returns.
    func close() {
        for operation in live.values.sorted(by: { $0.order < $1.order }) {
            let leaving = operation.consumers.filter { !$0.value.keepsOnClose }.sorted { $0.key < $1.key }
            for (token, consumer) in leaving {
                operation.consumers[token] = nil
                owners[token] = nil
                consumer.continuation.resume(returning: .cancelled)
            }
            if operation.consumers.isEmpty { abandon(operation) }
        }
    }

    // MARK: The queue

    private func join(_ key: ArtifactRead, token: Int, _ consumer: Consumer) {
        let operation: Operation
        if let existing = live[key] {
            operation = existing
        } else {
            operation = Operation(key: key, order: nextOrder)
            nextOrder += 1
            live[key] = operation
            queue.append(operation)
        }
        operation.consumers[token] = consumer
        owners[token] = operation
        if operation.running { consumer.started?() }
        pump()
    }

    /// One consumer stops waiting: it alone gets `.cancelled`.
    private func withdraw(_ token: Int) {
        guard let operation = owners.removeValue(forKey: token),
              let consumer = operation.consumers.removeValue(forKey: token) else { return }
        consumer.continuation.resume(returning: .cancelled)
        if operation.consumers.isEmpty { abandon(operation) }
    }

    /// Nobody waits for it: a queued one never starts; a running one is
    /// cancelled and keeps its slot until its reader returns.
    private func abandon(_ operation: Operation) {
        if live[operation.key] === operation { live[operation.key] = nil }
        queue.removeAll { $0 === operation }
        operation.timer?.cancel()
        operation.timer = nil
        operation.reader?.cancel()
        operation.reader = nil
    }

    private func pump() {
        while readers.count < limit, let next = nextInLine() {
            queue.removeAll { $0 === next }
            for other in queue { other.passedOver += 1 }
            start(next)
        }
    }

    /// A read that has waited out `promotion` starts, else the highest
    /// priority; the oldest first either way.
    private func nextInLine() -> Operation? {
        if let promoted = queue.filter({ $0.passedOver >= Self.promotion }).min(by: { $0.order < $1.order }) {
            return promoted
        }
        return queue.max { a, b in a.priority == b.priority ? a.order > b.order : a.priority < b.priority }
    }

    private func start(_ operation: Operation) {
        guard isReady() else {
            if live[operation.key] === operation { live[operation.key] = nil }
            resumeAll(operation, .notReady)
            return
        }
        operation.running = true
        readers[ObjectIdentifier(operation)] = operation
        mostActive = max(mostActive, readers.count)
        let key = operation.key
        let reader = reader, wait = wait, timeout = timeout
        operation.reader = Task { [weak self] in
            let outcome = await reader(key)
            self?.finished(operation, outcome)
        }
        operation.timer = Task { [weak self] in
            await wait(timeout)
            guard !Task.isCancelled else { return }
            self?.timedOut(operation)
        }
        for (_, consumer) in operation.consumers.sorted(by: { $0.key < $1.key }) { consumer.started?() }
    }

    /// The reader returned: its slot is free, and whoever still waits gets the answer.
    private func finished(_ operation: Operation, _ outcome: ArtifactReadOutcome) {
        readers[ObjectIdentifier(operation)] = nil
        operation.running = false
        operation.reader = nil
        operation.timer?.cancel()
        operation.timer = nil
        if live[operation.key] === operation { live[operation.key] = nil }
        resumeAll(operation, outcome == .cancelled ? .cancelled : .answered(outcome))
        pump()
    }

    /// The time limit passed: everyone waiting gets `.timedOut` now, and the
    /// reader is cancelled. Its slot is freed only when it returns.
    private func timedOut(_ operation: Operation) {
        guard operation.running, operation.timer != nil else { return }
        operation.timer = nil
        if live[operation.key] === operation { live[operation.key] = nil }
        resumeAll(operation, .timedOut)
        operation.reader?.cancel()
        operation.reader = nil
    }

    /// Each consumer is resumed once, in the order it came, and forgotten.
    private func resumeAll(_ operation: Operation, _ result: ShelfTransferResult) {
        let consumers = operation.consumers.sorted { $0.key < $1.key }
        operation.consumers = [:]
        for (token, consumer) in consumers {
            owners[token] = nil
            consumer.continuation.resume(returning: result)
        }
    }
}
