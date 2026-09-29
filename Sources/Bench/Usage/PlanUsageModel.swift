// PlanUsageModel.swift — how much of the plan's limits are left (DESIGN.md,
// Title-bar readouts). It reads Claude Science's own `GET /api/usage`, from
// inside the page through WebContainer.apiGET, so the page's sign-in carries
// the request and Bench never holds the session.
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "usage")

/// One limit on the plan: how much of it is used, and when it starts over.
struct PlanLimit: Identifiable, Equatable {
    enum Kind {
        case session, week, weekOpus, weekSonnet

        /// The row's name in the popover.
        var title: String {
            switch self {
            case .session: "Current session"
            case .week: "Weekly · all models"
            case .weekOpus: "Weekly · Opus"
            case .weekSonnet: "Weekly · Sonnet"
            }
        }

        /// The name in the toolbar, where every point counts.
        var shortTitle: String {
            switch self {
            case .session: "5h"
            case .week: "Week"
            case .weekOpus: "Opus week"
            case .weekSonnet: "Sonnet week"
            }
        }
    }

    let kind: Kind
    /// Percent used, rounded, 0 through 100. What is left is worked out from
    /// this, so the two always add up to what the label says.
    let usedPercent: Int
    let resetsAt: Date?

    var id: Kind { kind }
    var leftPercent: Int { 100 - usedPercent }
    /// Under a fifth left is when the toolbar turns clay.
    var isLow: Bool { leftPercent < 20 }
}

/// Extra usage, when the plan has it switched on. Its percent is of the
/// monthly limit; nil when Claude Science doesn't say.
struct PlanExtraUsage: Equatable {
    let usedPercent: Int?
}

@MainActor
final class PlanUsageModel: ObservableObject {
    static let shared = PlanUsageModel()

    /// The limits Claude Science reports, in the order of `PlanLimit.Kind`.
    /// A limit with no utilization is left out.
    @Published private(set) var limits: [PlanLimit] = []
    @Published private(set) var extra: PlanExtraUsage?
    @Published private(set) var loading = false
    /// A sentence for the last read if it failed; nil once one works. The
    /// last good `limits` stay, so the popover can show them as stale.
    @Published private(set) var failure: String?
    /// When `limits` were read; only a successful read sets it.
    @Published private(set) var lastRead: Date?

    /// The limit with the least left, which is the one the toolbar shows.
    var tightest: PlanLimit? {
        limits.min { $0.leftPercent < $1.leftPercent }
    }

    private var tasks: [Task<Void, Never>] = []
    private var trailing: Task<Void, Never>?
    /// Reads again just after the next limit starts over, so the toolbar
    /// doesn't sit on "resets now" with the old percent.
    private var atReset: Task<Void, Never>?
    private var lastAttempt: Date?

    private static let staleAfter: TimeInterval = 60
    private static let interval: Duration = .seconds(300)
    /// Automatic reads after a finished turn keep this far apart.
    private static let turnSpacing: TimeInterval = 30

    private init() {}

    /// Starts reading: once Claude Science is signed in, every five minutes,
    /// after a session finishes a turn, and when a limit starts over. Safe to
    /// call again.
    func start() {
        // A demo shows made-up limits and reads nothing (Demo.swift).
        guard Demo.mode == nil, tasks.isEmpty else { return }
        tasks = [
            // Watching the status instead of polling: it reads the moment the
            // page is signed in, and again if Claude Science comes back after
            // a failure, with no timer running while nothing has changed.
            Task { [weak self] in
                for await status in WebContainer.shared.$status.removeDuplicates().values where status == .ready {
                    self?.read(fresh: false)
                }
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.interval, tolerance: .seconds(30))
                    guard !Task.isCancelled else { return }
                    self?.read(fresh: false)
                }
            },
            // A session leaving the working set has finished a turn (or is
            // waiting on the user), and the plan's numbers have moved.
            Task { [weak self] in
                var before: Set<String>?
                for await working in LabModel.shared.$working.values {
                    let now = Set(working.map(\.id))
                    if let before, !before.isSubset(of: now) { self?.readAfterTurn() }
                    before = now
                }
            },
        ]
    }

    /// Reads if the last read is old: reopening the popover soon after shows
    /// what it has.
    func refreshIfStale() {
        if let lastRead, Date().timeIntervalSince(lastRead) <= Self.staleAfter { return }
        read(fresh: false)
    }

    /// The Refresh button: asks Claude Science to bypass its cache.
    func refresh() {
        read(fresh: true)
    }

    /// Shows made-up limits, with no read. Only Demo calls it.
    func showDemo(limits: [PlanLimit]) {
        self.limits = limits
        extra = nil
        loading = false
        failure = nil
        lastRead = Date()
    }

    // MARK: Reading

    /// Reads now, or once the spacing since the last read has passed. Reads
    /// that land inside it share one, so the turn that ends a burst is still
    /// counted.
    private func readAfterTurn() {
        let wait = Self.turnSpacing - Date().timeIntervalSince(lastAttempt ?? .distantPast)
        if wait <= 0 {
            read(fresh: false)
        } else if trailing == nil {
            trailing = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.trailing = nil
                self?.read(fresh: false)
            }
        }
    }

    private func read(fresh: Bool) {
        // Every automatic read, the Refresh button and the popover come here.
        guard Demo.mode == nil, !loading else { return }
        loading = true
        lastAttempt = Date()
        Task { [weak self] in
            do {
                let data = try await WebContainer.shared.apiGET(fresh ? "/usage?fresh=1" : "/usage")
                let payload = try Payload.decode(data)
                self?.apply(payload)
            } catch WebAPIError.notReady {
                // Still signing in is not a failure: the status watcher reads
                // as soon as it is. Signing in having failed is one, or the
                // popover would show its spinner for good.
                if case .failed = WebContainer.shared.status {
                    self?.fail(WebAPIError.notReady)
                } else {
                    self?.loading = false
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    private func apply(_ payload: Payload) {
        loading = false
        limits = [
            limit(.session, payload.fiveHour),
            limit(.week, payload.sevenDay),
            limit(.weekOpus, payload.sevenDayOpus),
            limit(.weekSonnet, payload.sevenDaySonnet),
        ].compactMap { $0 }
        extra = payload.extraUsage?.isEnabled == true
            ? PlanExtraUsage(usedPercent: payload.extraUsage?.utilization.map(Self.percent))
            : nil
        lastRead = Date()
        failure = nil
        scheduleReadAtReset()
    }

    private func scheduleReadAtReset() {
        atReset?.cancel()
        let now = Date()
        guard let next = limits.compactMap(\.resetsAt).filter({ $0 > now }).min() else { return }
        // A few seconds late, so Claude Science has the new window.
        let wait = next.timeIntervalSince(now) + 5
        atReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.read(fresh: true)
        }
    }

    private func fail(_ error: any Error) {
        loading = false
        log.error("Couldn't read plan usage: \(String(describing: error), privacy: .public)")
        failure = "Couldn't read plan usage"
    }

    private func limit(_ kind: PlanLimit.Kind, _ window: Payload.Window?) -> PlanLimit? {
        guard let utilization = window?.utilization else { return nil }
        return PlanLimit(kind: kind, usedPercent: Self.percent(utilization), resetsAt: Self.date(window?.resetsAt))
    }

    private static func percent(_ utilization: Double) -> Int {
        Int(min(max(utilization, 0), 100).rounded())
    }

    /// With and without fractional seconds: the API has sent both.
    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: The API's JSON

    enum PlanUsageError: Error { case refused }

    /// `GET /api/usage`. Any key can be missing or null, and one that has
    /// changed shape is treated as missing, so it doesn't take the others with it.
    private struct Payload: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?
        }

        struct Extra: Decodable {
            let isEnabled: Bool?
            let utilization: Double?
        }

        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?
        let sevenDaySonnet: Window?
        let extraUsage: Extra?

        private enum Keys: String, CodingKey {
            case fiveHour, sevenDay, sevenDayOpus, sevenDaySonnet, extraUsage
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            fiveHour = try? container.decodeIfPresent(Window.self, forKey: .fiveHour)
            sevenDay = try? container.decodeIfPresent(Window.self, forKey: .sevenDay)
            sevenDayOpus = try? container.decodeIfPresent(Window.self, forKey: .sevenDayOpus)
            sevenDaySonnet = try? container.decodeIfPresent(Window.self, forKey: .sevenDaySonnet)
            extraUsage = try? container.decodeIfPresent(Extra.self, forKey: .extraUsage)
        }

        /// Claude Science answers `{"ok": true, "data": {…}}` (its own Usage
        /// panel reads `.ok` and `.data`); a bare object is read too.
        static func decode(_ data: Data) throws -> Payload {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let inner = top["data"] as? [String: Any]
                log.info("Plan usage keys: \(top.keys.sorted().joined(separator: ","), privacy: .public); data: \(inner?.keys.sorted().joined(separator: ",") ?? "none", privacy: .public)")
                if let ok = top["ok"] as? Bool, !ok {
                    throw PlanUsageError.refused
                }
                if let inner {
                    return try decoder.decode(Payload.self, from: JSONSerialization.data(withJSONObject: inner))
                }
            }
            return try decoder.decode(Payload.self, from: data)
        }
    }
}
