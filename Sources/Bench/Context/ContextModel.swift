// ContextModel.swift — what the title bar's context ring knows: how full the
// shown session's context window is (DESIGN.md, Title-bar readouts). It reads
// Claude Science's own "Context usage" numbers through the page, when the
// shown session changes, when it finishes a turn, and when the popover opens.
// The endpoint scans the transcript, so nothing here polls.
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "context")

/// The two numbers the ring and the popover show, as a matching pair.
struct ContextFigures: Equatable {
    let used: Int
    let window: Int

    /// Nil unless there is a used count and a window above zero: with nothing
    /// to divide by there is nothing to show.
    init?(used: Int?, window: Int?) {
        guard let used, let window, window > 0 else { return nil }
        self.used = used
        self.window = window
    }

    /// Whole percent of the window, at most 100.
    var percent: Int { min(100, Int((Double(used) / Double(window) * 100).rounded())) }

    /// Past 80% the ring's fill and the percent turn full-strength clay.
    var isHigh: Bool { percent > 80 }

    /// "84K of 200K".
    var usedOfWindow: String { "\(ActivityMetric.compact(used)) of \(ActivityMetric.compact(window))" }
}

/// The parts of `token-series` the ring needs. Everything is optional and the
/// rest is ignored, so a Claude Science update that adds or drops a field
/// doesn't fail the read.
private struct TokenSeries: Decodable, Sendable {
    struct Turn: Decodable, Sendable {
        let ctxTotal: Int?
    }

    let window: Int?
    let turns: [Turn]?
    let truncated: Bool?
}

@MainActor
final class ContextModel: ObservableObject {
    static let shared = ContextModel()

    /// The session the numbers below belong to: the page's shown session as
    /// of the last change. Nil when the page shows none.
    @Published private(set) var frameID: String?
    /// The last turn's `ctx_total`.
    @Published private(set) var used: Int?
    /// The model's context window, in tokens.
    @Published private(set) var window: Int?
    /// `ctx_total` at each turn, oldest first: the popover's chart.
    @Published private(set) var turns: [Int] = []
    /// Claude Science cut the series short, so its tail may be stale.
    @Published private(set) var truncated = false
    @Published private(set) var loading = false
    /// A sentence for the last read if it failed; nil once one works.
    @Published private(set) var failure: String?

    /// What the ring shows, or nil while there is nothing to show: no session,
    /// no read yet, or a session with no turns. Whoever gates the toolbar item
    /// on this must also call `start()` themselves (see there).
    var figures: ContextFigures? { ContextFigures(used: used, window: window) }

    private var cancellables: Set<AnyCancellable> = []
    /// The ids in `LabModel.working` and `waiting` as of the last change, to
    /// tell a session that just left one from one that was never in it.
    private var workingIDs: Set<String> = []
    private var waitingIDs: Set<String> = []
    /// At most one read runs at a time. A request that comes in during one may
    /// predate what it saw, so it is asked again when the read ends.
    private var reading = false
    private var readAgain = false
    /// When the current session was last read (or tried), for the 15 s gap.
    private var lastAttempt: ContinuousClock.Instant?
    /// The one read put off until the gap is up.
    private var trailing: Task<Void, Never>?

    private static let minimumGap = Duration.seconds(15)

    private init() {}

    // MARK: Starting

    /// Starts watching. `ContextToolbarItem` calls it the first time it
    /// appears; calling it again does nothing. It is also the way in for a
    /// toolbar that only adds the item once there is a reading, since an item
    /// that isn't there can't start the read that would put it there.
    func start() {
        // A demo shows made-up numbers and reads nothing (Demo.swift).
        guard Demo.mode == nil, cancellables.isEmpty else { return }
        let web = WebContainer.shared
        let lab = LabModel.shared
        workingIDs = Set(lab.working.map(\.id))
        waitingIDs = Set(lab.waiting.map(\.id))

        // @Published announces a change just before it happens. Hopping to the
        // main queue lets each one land first, so a handler can look at the
        // objects themselves as well as at the value it was handed.
        web.$currentFrameID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.show($0) }
            .store(in: &cancellables)

        // A session shown before sign-in finished couldn't be read yet.
        web.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, status == .ready, used == nil, !reading else { return }
                requestRead()
            }
            .store(in: &cancellables)

        // The first value is what was just read above. LabModel sets `working`
        // and then `waiting` in one update, so a session that stops to ask
        // something changes both; the debounce lets that arrive as one change
        // (and one read), and lands after both properties have changed.
        Publishers.CombineLatest(lab.$working, lab.$waiting)
            .dropFirst()
            .map { (Set($0.map(\.id)), Set($1.map(\.id))) }
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.sessionsChanged(working: $0.0, waiting: $0.1) }
            .store(in: &cancellables)
        log.info("Context ring started")
    }

    // MARK: Asked by the popover

    /// The popover opened: read unless the last read is under 15 s old.
    func popoverOpened() {
        requestRead()
    }

    /// Refresh and Retry. The person asked, so the 15 s gap doesn't apply.
    func refresh() {
        requestRead(force: true)
    }

    /// Shows made-up figures for a made-up session, with no read. Only Demo
    /// calls it.
    func showDemo(used: Int, window: Int, turns: [Int]) {
        frameID = "demo-1"
        self.used = used
        self.window = window
        self.turns = turns
        truncated = false
        loading = false
        failure = nil
    }

    // MARK: What changed

    /// The page shows another session, or none. What was read belongs to the
    /// old one, so it goes at once and the new one is read without waiting.
    private func show(_ frame: String?) {
        guard frame != frameID else { return }
        frameID = frame
        used = nil
        window = nil
        turns = []
        truncated = false
        failure = nil
        trailing?.cancel()
        trailing = nil
        lastAttempt = nil
        requestRead()
    }

    /// A turn has ended for the shown session when it leaves `working`, or
    /// appears in `waiting` (it stopped to ask something).
    private func sessionsChanged(working: Set<String>, waiting: Set<String>) {
        defer {
            workingIDs = working
            waitingIDs = waiting
        }
        guard let frame = frameID else { return }
        let stopped = workingIDs.contains(frame) && !working.contains(frame)
        let asking = !waitingIDs.contains(frame) && waiting.contains(frame)
        if stopped || asking { requestRead() }
    }

    // MARK: Reading

    /// Reads the shown session, unless a read is running (it is asked again
    /// after) or the last was under 15 s ago (it waits for the gap to be up,
    /// so a turn that ends just after a read still updates the ring).
    private func requestRead(force: Bool = false) {
        guard Demo.mode == nil, let frame = frameID, WebContainer.shared.status == .ready else { return }
        guard !reading else {
            readAgain = true
            return
        }
        if !force, let last = lastAttempt {
            let wait = Self.minimumGap - (ContinuousClock.now - last)
            if wait > .zero {
                readLater(after: wait)
                return
            }
        }
        trailing?.cancel()
        trailing = nil
        lastAttempt = .now
        reading = true
        loading = true
        failure = nil
        Task {
            await read(frame)
            reading = false
            loading = false
            if readAgain {
                readAgain = false
                requestRead()
            }
        }
    }

    /// One read at the end of the gap, however many requests come before it.
    private func readLater(after wait: Duration) {
        guard trailing == nil else { return }
        trailing = Task {
            try? await Task.sleep(for: wait, tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            trailing = nil
            requestRead()
        }
    }

    private func read(_ frame: String) async {
        do {
            let series = try await Self.fetch(frame)
            // The page moved on while this was reading.
            guard frame == frameID else { return }
            // A turn with no `ctx_total` (one still in progress, say) is
            // skipped, so the ring, the headline and the chart agree.
            turns = series.turns?.compactMap(\.ctxTotal) ?? []
            used = turns.last
            window = series.window
            truncated = series.truncated ?? false
        } catch WebAPIError.notReady {
            // Not signed in yet: the status observer reads once it is.
            lastAttempt = nil
        } catch {
            guard frame == frameID else { return }
            log.error("Couldn't read context: \(String(describing: error), privacy: .public)")
            failure = "Couldn't read context"
        }
    }

    private static func fetch(_ frame: String) async throws -> TokenSeries {
        // The id comes from the page's address, so it is made safe as one path segment.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let id = frame.addingPercentEncoding(withAllowedCharacters: unreserved) ?? frame
        let data = try await WebContainer.shared.apiGET("/frames/\(id)/token-series")
        // A long session's series can be large; decode it off the main thread.
        return try await Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(TokenSeries.self, from: data)
        }.value
    }
}
