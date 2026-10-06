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
    case failed(SessionStatus)
    case finished(SessionStatus)
    case web(WebNotification)
    case saved(URL)
    case notice(LabNotice)

    var id: String {
        switch self {
        case .needsInput(let s): "needs-\(s.id)"
        case .failed(let s): "failed-\(s.id)"
        case .finished(let s): "finished-\(s.id)"
        case .web(let n): "web-\(n.id)"
        case .saved(let url): "saved-\(url.path)"
        case .notice(let n): "notice-\(n.id)"
        }
    }
}

private extension LabCard {
    /// Where the card queues: needs-input first, then a session that failed,
    /// then page notifications, then the moments that pass on their own.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .failed: 1
        case .web: 2
        case .finished, .saved: 3
        case .notice: 4
        }
    }

    /// How long it stays on top when nobody acts on it. Nil means until it
    /// stops being true: a session waits until it doesn't, a failure until it
    /// is opened, dismissed or the session runs again, a page notification
    /// that requires interaction until it is clicked, dismissed or closed.
    var lifetime: Duration? {
        switch self {
        case .needsInput, .failed: nil
        case .finished: .seconds(6)
        case .web(let n): n.requireInteraction ? nil : .seconds(8)
        case .saved: .seconds(5)
        case .notice(let n): n.lifetime
        }
    }

}

extension LabCard {
    /// The session a card is about, if it is about one.
    var session: SessionStatus? {
        switch self {
        case .needsInput(let s), .failed(let s), .finished(let s): s
        case .web, .saved, .notice: nil
        }
    }
}

/// When a needs-input card put off with Later should come back.
enum LabReminder: Equatable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    /// When the Nidus focus session that is on now ends.
    case afterFocus

    /// How long a timed reminder waits; nil for one that waits for focus to end.
    var delay: Duration? {
        switch self {
        case .fiveMinutes: .seconds(5 * 60)
        case .fifteenMinutes: .seconds(15 * 60)
        case .afterFocus: nil
        }
    }
}

private enum PendingReminder {
    /// Wakes when the task's sleep ends.
    case timer(Task<Void, Never>)
    /// Wakes when the focus session that is on ends.
    case focus

    func cancel() {
        if case .timer(let task) = self { task.cancel() }
    }

    var waitsForFocus: Bool {
        if case .focus = self { true } else { false }
    }
}

/// Something that happened to a session, kept for the activity list after its
/// card is gone. In memory only: nothing about sessions is written to disk.
struct LabEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case needsInput(WaitingReason?)
        case failed
        case finished
        case saved(URL)
    }

    /// The kind, the session and its turn: one turn's finish is one event,
    /// however many times the database or the page reports it.
    let id: String
    let kind: Kind
    let session: SessionStatus?
    let at: Date

    init(_ kind: Kind, session: SessionStatus?, at: Date = Date()) {
        self.kind = kind
        self.session = session
        self.at = at
        let turn = session?.startedAt.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        let what: String = switch kind {
        case .needsInput(let reason): "needs-\(reason?.rawValue ?? "")"
        case .failed: "failed"
        case .finished: "finished"
        case .saved(let url): "saved-\(url.path)"
        }
        id = "\(what)-\(session?.id ?? "")-\(turn)"
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
    /// Why the sessions can't be seen, while they can't. Without them there
    /// are no scenes and no needs-input cards, so the Scenes menu and Settings
    /// say so rather than staying quiet (`Bench --diagnose` has the details).
    @Published private(set) var problem: ScienceError?
    /// While `problem` stands, when the sessions were last read: the panel
    /// says it is not updating, rather than counting on as if it were.
    @Published private(set) var staleSince: Date?
    private var lastGoodRead: Date?
    /// The sessions active most recently that neither work nor wait, from
    /// the last read: the Dock menu's Latest, so it has something to open
    /// even right after Bench starts.
    @Published private(set) var latest: [SessionStatus] = []
    static let latestLimit = 5
    /// Every session of the last read (the ~25 most recently active), whatever
    /// its state: what Quick Open searches. In memory only, like Recent.
    @Published private(set) var sessions: [SessionStatus] = []
    /// What happened lately, newest first: the activity list's Recent.
    @Published private(set) var recent: [LabEvent] = []
    static let recentLimit = 30
    /// Tests shorten the cards' lifetimes, and the reminders' waits, with this.
    var lifetimeScale = 1.0
    /// Whether a Nidus focus session is on and finishes should wait for it
    /// (`NidusFocus`); tests set their own.
    var holdsFinishes: () -> Bool = { NidusFocus.shared.holding }
    /// Whether a Nidus focus session is on, for "After My Focus Session"
    /// (`NidusFocus`); tests set their own. Unlike `holdsFinishes`, it doesn't
    /// depend on the setting that holds finishes.
    var isFocusing: () -> Bool = { NidusFocus.shared.focusing }
    /// Finishes held during a focus session, shown as one card after it.
    private(set) var heldFinishes: [SessionStatus] = []
    /// Mac notifications (MacNotifications.swift): told of each card that
    /// comes, new or asking something new, and of each that goes because it
    /// was dealt with or stopped being true. Not of one that only timed out:
    /// its notification stays in Notification Center. They do nothing until
    /// `MacNotifications.start()` sets them, so tests and demos never notify.
    var cardRaised: (LabCard) -> Void = { _ in }
    var cardWithdrawn: (LabCard) -> Void = { _ in }

    private let source = CombinedScienceSource()
    private var engine = ScienceEngine(minDuration: LabModel.minDuration)
    private var watcher: DatabaseWatcher?
    private var watched: URL?
    private var fallback: Task<Void, Never>?
    private var expiries: [LabCard.ID: Task<Void, Never>] = [:]
    /// Needs-input cards put off with Later, by session id. Kept apart from
    /// `expiries`, which `armFrontCard` prunes to the front card. In memory
    /// only, like Recent.
    private var reminders: [String: PendingReminder] = [:]
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

    /// The app uses `shared`; tests make their own.
    init() {}

    /// Starts watching; registers Router.webNotificationArrived and
    /// Router.downloadSaved.
    func start() {
        guard !started else { return }
        started = true
        firstRead = true
        generation += 1
        Router.shared.webNotificationArrived = { [weak self] in self?.receive($0) }
        Router.shared.downloadSaved = { [weak self] in
            self?.raise(.saved($0))
            self?.remember(LabEvent(.saved($0), session: nil))
        }
        Router.shared.webNotificationClosed = { [weak self] in self?.closeWebNotification($0) }
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
        reminders.values.forEach { $0.cancel() }
        reminders = [:]
        sessionCardAt = [:]
        reading = false
        changedDuringRead = false
        Router.shared.webNotificationArrived = { _ in }
        Router.shared.downloadSaved = { _ in }
        Router.shared.webNotificationClosed = { _ in }
        engine = ScienceEngine(minDuration: LabModel.minDuration)
        working = []
        waiting = []
        cards = []
        workingHidden = false
        NSApplication.shared.dockTile.badgeLabel = nil
        log.info("Lab stopped")
    }

    // MARK: Acting on what the panel shows

    /// The card's own action: open its session or notification, or show the
    /// file. A card that has been acted on has done its job, so it goes.
    func open(_ card: LabCard) {
        switch card {
        case .needsInput(let session), .failed(let session), .finished(let session):
            Router.shared.open(session)
            forgetReminder(session.id)
        case .web(let notification):
            Router.shared.open(notification)
            if let frame = notification.frameID { forgetReminder(frame) }
        case .saved(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .notice(let notice):
            if case .openSession(let session) = notice.action {
                Router.shared.open(session)
                forgetReminder(session.id)
            }
        }
        dismiss(card)
    }

    /// Opens a session, and clears its cards and reminder: the user is
    /// looking at it now.
    func open(_ session: SessionStatus) {
        Router.shared.open(session)
        forgetReminder(session.id)
        for card in cards where card.session?.id == session.id { dismiss(card) }
    }

    /// Later: the needs-input card leaves the queue now and comes back when
    /// its time comes, if its session still waits. A question that changes
    /// kind meanwhile shows at once instead (`update(from:)`).
    func remind(_ card: LabCard, _ when: LabReminder) {
        // A card that is already gone was dismissed, opened or answered:
        // a late click on its menu must not bring it back.
        guard case .needsInput(let session) = card, cards.contains(where: { $0.id == card.id }) else { return }
        // A focus session that ended since the menu opened has nothing to wait for.
        let when = when == .afterFocus && !isFocusing() ? .fiveMinutes : when
        dismiss(card)
        forgetReminder(session.id)
        guard let delay = when.delay else {
            reminders[session.id] = .focus
            return
        }
        let scaled = delay * lifetimeScale
        let id = session.id
        reminders[id] = .timer(Task { [weak self] in
            try? await Task.sleep(for: scaled)
            guard !Task.isCancelled else { return }
            self?.wake(id)
        })
    }

    /// The sessions whose cards are put off, for tests.
    var remindedSessionIDs: Set<String> { Set(reminders.keys) }

    func dismiss(_ card: LabCard) {
        cardWithdrawn(card)
        remove(card)
    }

    /// Takes a card off the queue without telling Mac notifications.
    private func remove(_ card: LabCard) {
        expiries.removeValue(forKey: card.id)?.cancel()
        if cards.contains(where: { $0.id == card.id }) {
            cards.removeAll { $0.id == card.id }
        }
        armFrontCard()
    }

    /// Hides the working panel until the set of working sessions changes.
    func dismissWorking() {
        if !working.isEmpty { workingHidden = true }
    }

    /// Shows made-up sessions and cards, with no reading. Only Demo calls it.
    func showDemo(working: [SessionStatus], cards: [LabCard], problem: ScienceError? = nil, staleSince: Date? = nil,
                  recent: [LabEvent] = []) {
        self.working = working
        self.cards = cards
        self.recent = recent
        self.problem = problem
        self.staleSince = staleSince
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
                let snapshot: ScienceSnapshot
                do {
                    snapshot = try source.snapshot()
                } catch {
                    snapshot = ScienceSnapshot(
                        runningCount: nil, daemonVersion: nil, sessions: [],
                        readError: (error as? ScienceError) ?? .databaseUnreadable("\(error)"))
                }
                return Readout(snapshot: snapshot, database: source.database)
            }.value
            guard let self, self.generation == epoch else { return }
            self.apply(readout)
        }
    }

    /// Takes a snapshot as if it had just been read. Tests feed it made-up
    /// ones; the app's reads come through `read()`.
    func ingest(_ snapshot: ScienceSnapshot) {
        apply(Readout(snapshot: snapshot, database: nil))
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
        if !failed { lastGoodRead = Date() }
        let problem = failed ? snapshot.readError : nil
        let stale = problem == nil ? nil : (staleSince ?? lastGoodRead)
        if stale != staleSince { staleSince = stale }
        if problem != self.problem {
            if let problem {
                log.error("Can't see the sessions: \(String(describing: problem), privacy: .public)")
            } else if self.problem != nil {
                log.info("Sessions readable again")
            }
            self.problem = problem
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

    /// Internal for tests, which feed it made-up snapshots.
    func update(from snapshot: ScienceSnapshot) {
        var alert = false
        for transition in engine.advance(to: snapshot) {
            switch transition {
            case .needsInput(let session):
                // A new kind of request shows at once, whatever was put off.
                forgetReminder(session.id)
                supersedePageNotifications(by: session)
                if raise(.needsInput(session)) { alert = true }
                remember(LabEvent(.needsInput(session.waitingReason), session: session))
            case .failed(let session):
                supersedePageNotifications(by: session)
                if raise(.failed(session)) { alert = true }
                remember(LabEvent(.failed, session: session))
            case .finished(let session):
                supersedePageNotifications(by: session)
                remember(LabEvent(.finished, session: session))
                if holdsFinishes() {
                    if !heldFinishes.contains(where: { $0.id == session.id }) { heldFinishes.append(session) }
                } else {
                    raise(.finished(session))
                }
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
        let quiet = snapshot.sessions.filter { $0.state != .running && $0.state != .needsInput }
        let newest = Array(quiet.sorted(by: recentFirst).prefix(Self.latestLimit))
        if latest.map(\.id) != newest.map(\.id) { latest = newest }
        if sessions != snapshot.sessions { sessions = snapshot.sessions }
        if workingHidden, Set(running.map(\.id)) != Set(working.map(\.id)) { workingHidden = false }
        if working != running { working = running }
        if waiting != parked {
            waiting = parked
            NSApplication.shared.dockTile.badgeLabel = parked.isEmpty ? nil : String(parked.count)
        }

        // A needs-input card is true for as long as its session waits, and says
        // what it waits for now: a question can become a plan to approve.
        let parkedByID = Dictionary(parked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for case .needsInput(let session) in cards {
            if let now = parkedByID[session.id] {
                if now != session { raise(.needsInput(now)) }
            } else {
                dismiss(.needsInput(session))
            }
        }
        // A reminder is dropped, silently, once its session stops waiting.
        for id in Array(reminders.keys) where parkedByID[id] == nil {
            forgetReminder(id)
        }
        // A failure card goes once its session runs or waits again.
        let failedIDs = Set(snapshot.sessions.filter { $0.state == .error }.map(\.id))
        for case .failed(let session) in cards where !failedIDs.contains(session.id) {
            dismiss(.failed(session))
        }

        if alert, !firstRead { chime() }
        firstRead = false
    }

    /// The needs-input sound, when the setting is on.
    private func chime() {
        if UserDefaults.standard.bool(forKey: SettingsKey.soundOnNeedsInput) {
            NSSound(named: "Glass")?.play()
        }
    }

    // MARK: Cards

    /// Adds a card, or replaces the one with its id where it stands: a repeat
    /// neither reorders the queue nor counts as new. Says whether it is new.
    @discardableResult
    private func raise(_ card: LabCard) -> Bool {
        var next = cards
        let isNew: Bool
        var asksSomethingNew = false
        if let index = next.firstIndex(where: { $0.id == card.id }) {
            // A question that becomes a plan to approve is news again.
            asksSomethingNew = next[index].session?.waitingReason != card.session?.waitingReason
            next[index] = card
            isNew = false
        } else {
            next.insert(card, at: next.firstIndex { $0.rank > card.rank } ?? next.endIndex)
            isNew = true
        }
        if cards != next { cards = next }
        // A repeat on top starts its time again.
        expiries.removeValue(forKey: card.id)?.cancel()
        armFrontCard()
        // Not on the first read: what already waits at launch is not news.
        if (isNew || asksSomethingNew), !firstRead { cardRaised(card) }
        return isNew
    }

    /// Only the card on top counts down. One queued behind another (a finish
    /// behind a question) would otherwise run out without ever being seen;
    /// its time starts when it reaches the top.
    private func armFrontCard() {
        let front = cards.first
        for id in Array(expiries.keys) where id != front?.id {
            expiries.removeValue(forKey: id)?.cancel()
        }
        guard let front, let lifetime = front.lifetime, expiries[front.id] == nil else { return }
        let scaled = lifetime * lifetimeScale
        expiries[front.id] = Task { [weak self] in
            try? await Task.sleep(for: scaled)
            guard !Task.isCancelled else { return }
            self?.remove(front)
        }
    }

    /// A notice from elsewhere in Bench (plan, context, the week, Nidus):
    /// queued after the session cards, with no sound.
    func post(_ notice: LabNotice) {
        log.notice("Notice: \(notice.caption, privacy: .public)")
        raise(.notice(notice))
    }

    /// A reminder's time has come: the card returns if its session still
    /// waits, and says what it waits for now. If it doesn't, the reminder is
    /// dropped without a word.
    private func wake(_ id: String) {
        guard reminders.removeValue(forKey: id) != nil else { return }
        guard let session = waiting.first(where: { $0.id == id }) else { return }
        if raise(.needsInput(session)) { chime() }
    }

    private func forgetReminder(_ id: String) {
        reminders.removeValue(forKey: id)?.cancel()
    }

    /// The focus session ended: the reminders that waited for it come back,
    /// and what finished during it comes as one card.
    func focusEnded() {
        let due = Set(reminders.filter { $0.value.waitsForFocus }.keys)
        due.forEach(forgetReminder)
        // The most recently active session first, as the queue is. One that
        // no longer waits has nothing to come back for.
        var alert = false
        for session in waiting where due.contains(session.id) {
            if raise(.needsInput(session)) { alert = true }
        }
        if alert { chime() }
        releaseHeldFinishes()
    }

    /// What finished during the focus session, as one card.
    func releaseHeldFinishes() {
        guard let notice = NoticeRules.held(heldFinishes) else { return }
        heldFinishes = []
        post(notice)
    }

    /// Adds an event to Recent, once: a repeat of the same one (the same
    /// turn's finish, read again) is not news.
    private func remember(_ event: LabEvent) {
        guard !recent.contains(where: { $0.id == event.id }) else { return }
        recent = Array(([event] + recent).prefix(Self.recentLimit))
    }

    /// The page closed one of its notifications: its card goes too.
    func closeWebNotification(_ id: String) {
        for case .web(let notification) in cards where notification.id == id {
            dismiss(.web(notification))
        }
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

    /// Internal for tests; the Router calls it in the app.
    func receive(_ notification: WebNotification) {
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
