// UsageModel.swift — what the Usage popover knows: a year of Claude Science
// activity (DESIGN.md, Usage). It is read when the popover opens, and again
// every ten minutes while it stays open. Nothing runs while it is closed.
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "usage")

@MainActor
final class UsageModel: ObservableObject {
    static let shared = UsageModel()

    /// The last read that worked. A later read that fails leaves it in place,
    /// as the Lab does: one failed read says nothing about the year before it.
    @Published private(set) var history: ActivityHistory?
    @Published private(set) var loading = false
    /// A sentence for the last read if it failed; nil once one works.
    @Published private(set) var failure: String?
    /// When `history` was read. Only a successful read sets it, so a failed
    /// one is tried again the next time the popover opens.
    private(set) var lastRead: Date?

    private let source = CombinedScienceSource()
    private var live: Task<Void, Never>?

    /// One column per week in the graph, and every day of the oldest.
    private static let days = 7 * 53
    private static let staleAfter: TimeInterval = 60
    private static let liveInterval: Duration = .seconds(600)

    private init() {}

    /// Reads unless the last read is recent: reopening the popover a few
    /// seconds later shows what it has instead of reading the database again.
    func refreshIfStale() {
        if let lastRead, Date().timeIntervalSince(lastRead) <= Self.staleAfter { return }
        refresh()
    }

    /// Reads now, unless a read is already running.
    func refresh() {
        // A demo has no activity to read (Demo.swift); the popover stays on its spinner.
        guard Demo.mode == nil, !loading else { return }
        loading = true
        failure = nil
        let source = source
        let days = Self.days
        Task { [weak self] in
            // The cold read takes a second or more (SQLite and a CLI call),
            // so it stays off the main thread.
            let result = await Task.detached(priority: .utility) {
                Result { try source.activityHistory(days: days) }
            }.value
            self?.finish(result)
        }
    }

    /// Reads every ten minutes until `stopLiveUpdates()`, so a popover left
    /// open stays true. The popover's own open does the first read.
    func startLiveUpdates() {
        guard Demo.mode == nil else { return }
        live?.cancel()
        live = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liveInterval, tolerance: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stopLiveUpdates() {
        live?.cancel()
        live = nil
    }

    private func finish(_ result: Result<ActivityHistory, any Error>) {
        loading = false
        switch result {
        case .success(let value):
            history = value
            lastRead = Date()
            failure = nil
        case .failure(let error):
            log.error("Couldn't read activity: \(String(describing: error), privacy: .public)")
            failure = Self.sentence(for: error)
        }
    }

    private static func sentence(for error: any Error) -> String {
        switch error as? ScienceError {
        case .databaseMissing?:
            "Can't find Claude Science's data on this Mac."
        case .unknownSchema?:
            "Claude Science changed how it keeps its data, so Bench can't read your activity yet."
        default:
            "Can't read your Claude Science activity right now."
        }
    }
}
