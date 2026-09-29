// LabModel.swift — what the Lab half knows: which sessions work or wait, and
// the queue of cards the panel shows (DESIGN.md, Lab). A port of the droplet's
// watching loop with no DroppyKit: read the Science database the moment the
// daemon writes to it, with a slow timer as a fallback, and let the shared
// engine say what changed.
import AppKit
import Combine
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "lab")

enum LabCard: Identifiable, Equatable {
    case needsInput(SessionStatus)
    case finished(SessionStatus)
    case web(WebNotification)
    case saved(URL)

    var id: String {
        switch self {
        case .needsInput(let s): "needs-\(s.id)"
        case .finished(let s): "finished-\(s.id)"
        case .web(let n): "web-\(n.id)"
        case .saved(let url): "saved-\(url.path)"
        }
    }
}

private extension LabCard {
    /// Where the card queues: needs-input first, then page notifications,
    /// then the moments that pass on their own.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .web: 1
        case .finished, .saved: 2
        }
    }

    /// How long it stays when nobody acts on it. Nil means until it stops
    /// being true: a session waits until it doesn't, a page notification that
    /// requires interaction until it is clicked or dismissed.
    var lifetime: Duration? {
        switch self {
        case .needsInput: nil
        case .finished: .seconds(6)
        case .web(let n): n.requireInteraction ? nil : .seconds(8)
        case .saved: .seconds(5)
        }
    }

    var session: SessionStatus? {
        switch self {
        case .needsInput(let s), .finished(let s): s
        case .web, .saved: nil
        }
    }
}

@MainActor
final class LabModel: ObservableObject {
    static let shared = LabModel()

    /// Sessions running, the most recently active first.
    @Published private(set) var working: [SessionStatus] = []
    /// Sessions parked on the user, the most recently active first.
    @Published private(set) var waiting: [SessionStatus] = []
    /// What the panel shows; the first card is on top.
    @Published private(set) var cards: [LabCard] = []
    /// The user hid the working panel. It comes back when the set of working
    /// sessions changes, so the next session to start is not missed.
    @Published private(set) var workingHidden = false

    private let source = CombinedScienceSource()
    private var engine = ScienceEngine(minDuration: LabModel.minDuration)
    private var watcher: DatabaseWatcher?
    private var watched: URL?
    private var fallback: Task<Void, Never>?
    private var expiries: [LabCard.ID: Task<Void, Never>] = [:]
    /// When each session last raised a needs-input or finished card, so the
    /// page's own notification for the same moment can be dropped.
    private var sessionCardAt: [String: Date] = [:]

    private var started = false
    /// The first read after start: sessions already waiting then get their
    /// cards, but no chime each, which at launch would be a burst of sounds.
    private var firstRead = true
    private var reading = false
    private var changedDuringRead = false
    /// Bumped by start() and stop(): a read or a watcher callback that lands
    /// after either belongs to a run that is over.
    private var generation = 0

    private static let minDuration: TimeInterval = 30
    /// A page notification and a session card within this long of each other
    /// are the same moment (DESIGN.md, Notification bridge).
    private static let sameMoment: TimeInterval = 10

    private init() {}

    /// Starts watching; registers Router.webNotificationArrived and
    /// Router.downloadSaved.
    func start() {
        guard !started else { return }
        started = true
        firstRead = true
        generation += 1
        Router.shared.webNotificationArrived = { [weak self] in self?.receive($0) }
        Router.shared.downloadSaved = { [weak self] in self?.raise(.saved($0)) }
        log.info("Lab started")
        read()
    }

    func stop() {
        guard started else { return }
        started = false
        generation += 1
        watcher?.stop()
        watcher = nil
        watched = nil
        fallback?.cancel()
        fallback = nil
        expiries.values.forEach { $0.cancel() }
        expiries = [:]
        sessionCardAt = [:]
        reading = false
        changedDuringRead = false
        Router.shared.webNotificationArrived = { _ in }
        Router.shared.downloadSaved = { _ in }
        engine = ScienceEngine(minDuration: LabModel.minDuration)
        working = []
        waiting = []
        cards = []
        workingHidden = false
        NSApp.dockTile.badgeLabel = nil
        log.info("Lab stopped")
    }

    // MARK: Acting on what the panel shows

    /// The card's own action: open its session or notification, or show the
    /// file. A card that has been acted on has done its job, so it goes.
    func open(_ card: LabCard) {
        switch card {
        case .needsInput(let session), .finished(let session): Router.shared.open(session)
        case .web(let notification): Router.shared.open(notification)
        case .saved(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        dismiss(card)
    }

    /// Opens a session, and clears its cards: the user is looking at it now.
    func open(_ session: SessionStatus) {
        Router.shared.open(session)
        for card in cards where card.session?.id == session.id { dismiss(card) }
    }

    func dismiss(_ card: LabCard) {
        expiries.removeValue(forKey: card.id)?.cancel()
        if cards.contains(where: { $0.id == card.id }) {
            cards.removeAll { $0.id == card.id }
        }
    }

    /// Hides the working panel until the set of working sessions changes.
    func dismissWorking() {
        if !working.isEmpty { workingHidden = true }
    }

    /// Shows made-up sessions and cards, with no reading. Only Demo calls it.
    func showDemo(working: [SessionStatus], cards: [LabCard]) {
        self.working = working
        self.cards = cards
        waiting = cards.compactMap(\.session).filter { $0.state == .needsInput }
    }

    // MARK: Reading

    /// One read's worth, resolved together off the main thread: the database
    /// path is a few file reads, and finding it late is how a Mac without
    /// Claude Science yet starts watching once it appears.
    private struct Readout: Sendable {
        let snapshot: ScienceSnapshot
        let database: URL?
    }

    /// The daemon wrote, or a page notification says it is about to: read now,
    /// or once more after the read under way, which may predate the change.
    private func readSoon() {
        if reading {
            changedDuringRead = true
        } else {
            read()
        }
    }

    private func read() {
        guard started, !reading else { return }
        reading = true
        fallback?.cancel()
        fallback = nil
        let epoch = generation
        let source = source
        Task { [weak self] in
            let readout = await Task.detached(priority: .utility) { () -> Readout in
                let snapshot = (try? source.snapshot()) ?? ScienceSnapshot(
                    runningCount: nil, daemonVersion: nil, sessions: [],
                    readError: .databaseUnreadable("read failed"))
                return Readout(snapshot: snapshot, database: source.database)
            }.value
            guard let self, self.generation == epoch else { return }
            self.apply(readout)
        }
    }

    private func apply(_ readout: Readout) {
        reading = false
        watch(readout.database)
        let snapshot = readout.snapshot
        // A read that failed outright says nothing about the sessions: keep
        // what was known, as the engine does. The exception is a daemon that
        // is not running, which says plainly that nothing works.
        let failed = snapshot.readError != nil && snapshot.sessions.isEmpty
        if !failed || snapshot.readError == .daemonNotRunning {
            update(from: snapshot)
        }
        if changedDuringRead {
            changedDuringRead = false
            read()
        } else {
            scheduleFallback()
        }
    }

    /// Watches the database once it is known, and again if the active org
    /// (and so its database) changes.
    private func watch(_ database: URL?) {
        guard let database, database != watched else { return }
        watcher?.stop()
        watched = database
        let epoch = generation
        watcher = DatabaseWatcher(database: database) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == epoch else { return }
                self.readSoon()
            }
        }
        log.info("Watching the Science database")
    }

    /// The timer only backs up the watcher: quick while something works, so
    /// the clock and states stay true even if a write is missed, and slow when
    /// idle. Nothing else runs while nothing happens.
    private func scheduleFallback() {
        let busy = !working.isEmpty || !waiting.isEmpty
        let wait: Duration = busy ? .seconds(3) : .seconds(30)
        fallback?.cancel()
        fallback = Task { [weak self] in
            try? await Task.sleep(for: wait, tolerance: busy ? .milliseconds(500) : .seconds(5))
            guard !Task.isCancelled else { return }
            self?.read()
        }
    }

    // MARK: Turning a snapshot into state and cards

    private func update(from snapshot: ScienceSnapshot) {
        var alert = false
        for transition in engine.advance(to: snapshot) {
            switch transition {
            case .needsInput(let session):
                supersedePageNotifications(by: session)
                if raise(.needsInput(session)) { alert = true }
            case .finished(let session):
                supersedePageNotifications(by: session)
                raise(.finished(session))
            case .started:
                break
            }
        }

        let recentFirst = { (a: SessionStatus, b: SessionStatus) in a.updatedAt > b.updatedAt }
        var running = snapshot.sessions.filter { $0.state == .running }.sorted(by: recentFirst)
        let parked = snapshot.sessions.filter { $0.state == .needsInput }.sorted(by: recentFirst)
        // The head stays the head while it works. Sessions running side by
        // side write in turn, and the panel's title and clock would otherwise
        // swap to the other one each time it does.
        if let head = working.first, let index = running.firstIndex(where: { $0.id == head.id }), index > 0 {
            running.insert(running.remove(at: index), at: 0)
        }
        // Assign only real changes: each one redraws the panel and re-fits the window.
        if workingHidden, Set(running.map(\.id)) != Set(working.map(\.id)) { workingHidden = false }
        if working != running { working = running }
        if waiting != parked {
            waiting = parked
            NSApp.dockTile.badgeLabel = parked.isEmpty ? nil : String(parked.count)
        }

        // A needs-input card is true for as long as its session waits.
        let parkedIDs = Set(parked.map(\.id))
        for case .needsInput(let session) in cards where !parkedIDs.contains(session.id) {
            dismiss(.needsInput(session))
        }

        if alert, !firstRead, UserDefaults.standard.bool(forKey: SettingsKey.soundOnNeedsInput) {
            NSSound(named: "Glass")?.play()
        }
        firstRead = false
    }

    // MARK: Cards

    /// Adds a card, or replaces the one with its id where it stands: a repeat
    /// neither reorders the queue nor counts as new. Says whether it is new.
    @discardableResult
    private func raise(_ card: LabCard) -> Bool {
        var next = cards
        let isNew: Bool
        if let index = next.firstIndex(where: { $0.id == card.id }) {
            next[index] = card
            isNew = false
        } else {
            next.insert(card, at: next.firstIndex { $0.rank > card.rank } ?? next.endIndex)
            isNew = true
        }
        if cards != next { cards = next }
        expiries.removeValue(forKey: card.id)?.cancel()
        if let lifetime = card.lifetime {
            expiries[card.id] = Task { [weak self] in
                try? await Task.sleep(for: lifetime)
                guard !Task.isCancelled else { return }
                self?.dismiss(card)
            }
        }
        return isNew
    }

    /// The page hears of a session's state change a moment before the
    /// database does, so its notification may already be up when the session
    /// card arrives; the card says it better, and the notification goes.
    private func supersedePageNotifications(by session: SessionStatus) {
        let now = Date()
        sessionCardAt = sessionCardAt.filter { now.timeIntervalSince($0.value) < Self.sameMoment }
        sessionCardAt[session.id] = now
        for case .web(let notification) in cards
        where notification.frameID == session.id
            && now.timeIntervalSince(notification.receivedAt) < Self.sameMoment {
            dismiss(.web(notification))
        }
    }

    private func receive(_ notification: WebNotification) {
        if let frame = notification.frameID, let at = sessionCardAt[frame],
           Date().timeIntervalSince(at) < Self.sameMoment {
            return
        }
        raise(.web(notification))
        // Read now rather than at the next database write, so a session card
        // for the same moment can replace this one at once.
        readSoon()
    }
}
