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
        case .needsInput(let s): SessionKind.needsInput.cardID(s.id)
        case .failed(let s): SessionKind.failed.cardID(s.id)
        case .finished(let s): SessionKind.finished.cardID(s.id)
        case .web(let n): "web-\(n.id)"
        case .saved(let url): "saved-\(url.path)"
        case .notice(let n): "notice-\(n.id)"
        }
    }

    /// What a card about one session says of it. The raw value is the start
    /// of the card's id, which is also the identifier of its Mac
    /// notification: how a notification that outlived a launch is told what
    /// it was about (`NotificationRules.Delivered`).
    enum SessionKind: String, CaseIterable, Sendable {
        case needsInput = "needs-"
        case failed = "failed-"
        case finished = "finished-"

        func cardID(_ sessionID: String) -> String { rawValue + sessionID }
    }
}

/// What one read says of the sessions, in the terms a card's reason is told
/// in: which wait for the user and which stopped with an error. The one test
/// of whether a card still tells the truth, for a card on the panel and for
/// the Mac notification of a card that outlived a launch (DESIGN.md, Mac
/// notifications → Taken back).
struct SessionStanding: Equatable, Sendable {
    let waiting: Set<String>
    let failed: Set<String>

    init(_ sessions: [SessionStatus]) {
        waiting = Set(sessions.filter { $0.state == .needsInput }.map(\.id))
        failed = Set(sessions.filter { $0.state == .error }.map(\.id))
    }

    /// Whether a card of this kind about this session is still true. A
    /// session the read doesn't have is neither waiting nor failed. A finish
    /// is a record: it stays true.
    func holds(_ kind: LabCard.SessionKind, for sessionID: String) -> Bool {
        switch kind {
        case .needsInput: waiting.contains(sessionID)
        case .failed: failed.contains(sessionID)
        case .finished: true
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

extension SessionStatus {
    /// Whether everything shown of a working session is the same: all but
    /// its tokens and the time of its last write. Of a working session, the
    /// panel shows the title, the project and the turn's clock (which ticks
    /// on its own); the activity list, the Dock menu, the capsule and the
    /// menu bar specimen the same or less; `/api/state` the id, the title,
    /// the project and the turn's start; and opening one takes its link.
    func drawsTheSame(as other: SessionStatus) -> Bool {
        id == other.id && projectID == other.projectID && projectName == other.projectName
            && title == other.title && state == other.state && startedAt == other.startedAt
            && deepLink == other.deepLink && waitingReason == other.waitingReason
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

/// A needs-input card put off with Later, as the activity list and the Dock
/// menu show it. In memory only, like the reminder it describes.
struct SnoozedReminder: Identifiable, Equatable {
    /// The session that waits, as the last read left it.
    let session: SessionStatus
    /// When the reminder wakes; nil for one that waits for the focus session
    /// to end.
    let due: Date?

    var id: String { session.id }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

private enum PendingReminder {
    /// Wakes when the task's sleep ends, at `due`.
    case timer(Task<Void, Never>, due: Date)
    /// Wakes when the focus session that is on ends.
    case focus

    func cancel() {
        if case .timer(let task, _) = self { task.cancel() }
    }

    var waitsForFocus: Bool {
        if case .focus = self { true } else { false }
    }

    var due: Date? {
        if case .timer(_, let due) = self { due } else { nil }
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

/// Every session of the last read (the ~25 most recently active), whatever
/// its state, its tokens and last write included: what Quick Open searches
/// and shows. An object of its own, so a read that moves only a working
/// session's tokens or last write redraws Quick Open, when it is open, and
/// not the panel and the lists, which observe `LabModel` (Fable's review of
/// 0.5.0, P2). In memory only, like Recent.
@MainActor
final class LabReads: ObservableObject {
    @Published fileprivate(set) var sessions: [SessionStatus] = []
}

@MainActor
final class LabModel: ObservableObject {
    static let shared = LabModel()

    /// Sessions running, the most recently active first. Reassigned only
    /// when something drawn of them changes (`drawsTheSame`), not for a
    /// session's tokens or the time of its last write, which move with
    /// nearly every read while it works: each publish redraws the panel's
    /// glass. `workingAsRead` has those as read.
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
    /// say so rather than staying quiet (`Capsid --diagnose` has the details).
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
    /// The last read's sessions (`LabReads`), published on their own.
    let reads = LabReads()
    /// Every session of the last read (the ~25 most recently active), whatever
    /// its state: what Quick Open searches. In memory only, like Recent.
    var sessions: [SessionStatus] { reads.sessions }

    /// `working` as the last read has it, tokens and last write included.
    var workingAsRead: [SessionStatus] {
        let read = Dictionary(reads.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return working.map { read[$0.id] ?? $0 }
    }
    /// The waiting sessions whose cards are put off with Later and when each
    /// comes back, in the order they wait: the activity list and the Dock menu
    /// show them. In memory only, like Recent.
    @Published private(set) var snoozed: [SnoozedReminder] = []
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
    /// Whether Capsid is keeping quiet while the user presents
    /// (`PresentingMode`); tests set their own. Quiet, the panel isn't shown
    /// (LabPanelController), finishes are held with a Nidus focus session's,
    /// and no sound plays or Mac notification is made.
    var isQuiet: () -> Bool = { PresentingMode.shared.isQuiet }
    /// Plays the sound of what happened (a question, a plan, a failure, a
    /// finish: `PanelSound`), when the setting is on; tests count them.
    var playSound: (PanelSound) -> Void = { PanelSound.play($0) }
    /// Finishes held during a focus session or while presenting, shown as one
    /// card after it.
    private(set) var heldFinishes: [SessionStatus] = []
    /// Mac notifications (MacNotifications.swift): told of each card that
    /// comes, new or asking something new, and of each that goes because it
    /// was dealt with or stopped being true. Not of one that only timed out:
    /// its notification stays in Notification Center. They do nothing until
    /// `MacNotifications.start()` sets them, so tests and demos never notify.
    var cardRaised: (LabCard) -> Void = { _ in }
    var cardWithdrawn: (LabCard) -> Void = { _ in }
    /// Mac notifications: told what each read that worked and found sessions
    /// says of them, the first of a run included. That first one is when the
    /// notifications that outlived a quit are checked (MacNotifications.swift,
    /// Notifications that outlived a quit); a failed read, a daemon that isn't
    /// running and a read with no sessions at all are never told, so none of
    /// them can take a notification back.
    var sessionsRead: (SessionStanding) -> Void = { _ in }
    /// Phase 2 push: the same moments, for paired devices (PushCenter.swift).
    var pushRaised: (LabCard) -> Void = { _ in }

    private let source = CombinedScienceSource()
    private var engine = ScienceEngine(minDuration: LabModel.minDuration)
    private var watcher: DatabaseWatcher?
    private var watched: URL?
    /// The daemon's process, watched for its exit (ProcessExitWatcher.swift).
    private var daemonExit: ProcessExitWatcher?
    private var fallback: Task<Void, Never>?
    private var expiries: [LabCard.ID: Task<Void, Never>] = [:]
    /// Needs-input cards put off with Later, by session id. Kept apart from
    /// `expiries`, which `armFrontCard` prunes to the front card. In memory
    /// only, like Recent.
    private var reminders: [String: PendingReminder] = [:] {
        didSet { syncSnoozed() }
    }
    /// When each session last raised a needs-input or finished card, so the
    /// page's own notification for the same moment can be dropped.
    private var sessionCardAt: [String: Date] = [:]
    /// Sessions whose plan is being approved from its card (`PlanApprover`):
    /// the card stays up through the approval and its "Approved" moment, even
    /// once the session runs on, until `releasePlanCard`. A new request from
    /// the session, or the card going, lets it go.
    private var planHolds: Set<String> = []

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
        daemonExit?.stop()
        daemonExit = nil
        fallback?.cancel()
        fallback = nil
        expiries.values.forEach { $0.cancel() }
        expiries = [:]
        reminders.values.forEach { $0.cancel() }
        reminders = [:]
        sessionCardAt = [:]
        planHolds = []
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
            switch notice.action {
            case .openSession(let session):
                Router.shared.open(session)
                forgetReminder(session.id)
            case .installUpdate(let update):
                // After the card is dismissed (below): the alert is modal and
                // would hold the card on screen while it runs.
                Task { @MainActor in UpdatePrompts.offer(update) }
            case .none:
                break
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
        let due = Date().addingTimeInterval(scaled.seconds)
        reminders[id] = .timer(Task { [weak self] in
            try? await Task.sleep(for: scaled)
            guard !Task.isCancelled else { return }
            self?.wake(id)
        }, due: due)
    }

    /// Show Now: a reminder's time brought forward to this moment. The card
    /// returns if the session still waits, quietly, as the user asked for it.
    func showNow(_ sessionID: String) {
        guard let pending = reminders[sessionID] else { return }
        // Its timer must not outlive it: a later Later on the same session
        // would be woken by the old one.
        pending.cancel()
        wake(sessionID, chiming: false)
    }

    /// Cancel Reminder: the reminder goes, silently, and the card does not
    /// return. The session stays dismissed, as after Dismiss, until it asks
    /// something new.
    func cancelReminder(_ sessionID: String) {
        forgetReminder(sessionID)
    }

    /// The sessions whose cards are put off, for tests.
    var remindedSessionIDs: Set<String> { Set(reminders.keys) }

    func dismiss(_ card: LabCard) {
        cardWithdrawn(card)
        remove(card)
    }

    /// A plan approved from its card (`PlanApprover`): keeps the session's
    /// needs-input card up while the approval is sent and for its "Approved"
    /// moment, even once the session stops waiting.
    func holdPlanCard(_ sessionID: String) {
        guard needsInputCard(for: sessionID) != nil else { return }
        planHolds.insert(sessionID)
    }

    /// Whether the session's card is held for an approval.
    func holdsPlanCard(_ sessionID: String) -> Bool {
        planHolds.contains(sessionID)
    }

    /// The approval is over. Approved, the card goes as Open would take it,
    /// without opening the session. Otherwise it stays only while the session
    /// still waits. Nothing happens if the hold went already: a new request
    /// from the session replaced the card, or the card was dismissed.
    func releasePlanCard(_ sessionID: String, approved: Bool) {
        guard planHolds.remove(sessionID) != nil, let card = needsInputCard(for: sessionID) else { return }
        if approved {
            forgetReminder(sessionID)
            dismiss(card)
        } else if !waiting.contains(where: { $0.id == sessionID }) {
            dismiss(card)
        }
    }

    private func needsInputCard(for sessionID: String) -> LabCard? {
        cards.first { if case .needsInput(let session) = $0 { session.id == sessionID } else { false } }
    }

    /// Takes a card off the queue without telling Mac notifications.
    private func remove(_ card: LabCard) {
        if case .needsInput(let session) = card { planHolds.remove(session.id) }
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
                  recent: [LabEvent] = [], snoozed: [SnoozedReminder] = []) {
        self.working = working
        self.cards = cards
        self.recent = recent
        self.snoozed = snoozed
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
        watchDaemon(ScienceDaemonProcess.current)
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

    /// Hears the daemon's exit the moment it happens, and reads: the read finds
    /// its process gone and says Claude Science isn't running. A new process
    /// (a restart, as the next status says) is watched in its place.
    private func watchDaemon(_ pid: Int32?) {
        guard started, let pid, pid != daemonExit?.pid else { return }
        daemonExit?.stop()
        let epoch = generation
        daemonExit = ProcessExitWatcher(pid: pid) { [weak self] in
            guard let self, self.generation == epoch else { return }
            self.readSoon()
        }
    }

    /// The timer only backs up the watcher. Nothing else runs while nothing
    /// happens.
    private func scheduleFallback() {
        let busy = !working.isEmpty || !waiting.isEmpty
        let wait = Self.fallbackInterval(busy: busy, watching: watcher?.isWatching == true)
        fallback?.cancel()
        fallback = Task { [weak self] in
            try? await Task.sleep(for: wait, tolerance: wait < .seconds(30) ? .milliseconds(500) : .seconds(5))
            guard !Task.isCancelled else { return }
            self?.read()
        }
    }

    /// How long the fallback timer waits. While the watcher has the write-ahead
    /// log open, every write is reported within a second, so the timer only
    /// covers what no write tells: a daemon that stopped without a word,
    /// another org's database taking over. Without the watcher (no database
    /// yet, the log gone), it is quick while something works, so the states
    /// stay true, and slow when idle.
    nonisolated static func fallbackInterval(busy: Bool, watching: Bool) -> Duration {
        busy && !watching ? .seconds(3) : .seconds(30)
    }

    // MARK: Turning a snapshot into state and cards

    /// Internal for tests, which feed it made-up snapshots.
    func update(from snapshot: ScienceSnapshot) {
        // The sounds of the cards this read raises: one is played, the most urgent.
        var sounds: [PanelSound] = []
        for transition in engine.advance(to: snapshot) {
            switch transition {
            case .needsInput(let session):
                // A new kind of request shows at once, whatever was put off,
                // and whatever approval its card was held for.
                forgetReminder(session.id)
                planHolds.remove(session.id)
                supersedePageNotifications(by: session)
                if let sound = raiseWithSound(.needsInput(session)) { sounds.append(sound) }
                remember(LabEvent(.needsInput(session.waitingReason), session: session))
            case .failed(let session):
                supersedePageNotifications(by: session)
                if let sound = raiseWithSound(.failed(session)) { sounds.append(sound) }
                remember(LabEvent(.failed, session: session))
            case .finished(let session):
                supersedePageNotifications(by: session)
                remember(LabEvent(.finished, session: session))
                if holdsFinishes() || isQuiet() {
                    if !heldFinishes.contains(where: { $0.id == session.id }) { heldFinishes.append(session) }
                } else if let sound = raiseWithSound(.finished(session)) {
                    sounds.append(sound)
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
        // A daemon that isn't running says nothing works, so nothing is shown
        // working; but a session waiting for you still waits when it comes
        // back, and the engine keeps its baseline over the gap, so it won't
        // announce them again. Its cards, reminders and lists stay until a
        // read that works says otherwise.
        let daemonDown = snapshot.readError == .daemonNotRunning
        // Assign only real changes: each one redraws the panel and re-fits the window.
        let quiet = snapshot.sessions.filter { $0.state != .running && $0.state != .needsInput }
        let newest = Array(quiet.sorted(by: recentFirst).prefix(Self.latestLimit))
        // What the Dock menu and the lists show of each is the same title, project and state, so a rename in place
        // publishes too, not only a change of which sessions or in what order (`drawsTheSame`).
        if !daemonDown, !latest.elementsEqual(newest, by: { $0.drawsTheSame(as: $1) }) { latest = newest }
        if !daemonDown, reads.sessions != snapshot.sessions { reads.sessions = snapshot.sessions }
        if workingHidden, Set(running.map(\.id)) != Set(working.map(\.id)) { workingHidden = false }
        if !working.elementsEqual(running, by: { $0.drawsTheSame(as: $1) }) { working = running }
        if !daemonDown, waiting != parked {
            waiting = parked
            NSApplication.shared.dockTile.badgeLabel = parked.isEmpty ? nil : String(parked.count)
        }

        // A needs-input card is true for as long as its session waits, and says
        // what it waits for now: a question can become a plan to approve. One
        // held for a plan approved from it stays until the approval lets it go.
        let parkedByID = Dictionary(parked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let standing = SessionStanding(snapshot.sessions)
        if daemonDown {
            if !firstRead { chime(sounds) }
            return
        }
        for case .needsInput(let session) in cards {
            if standing.holds(.needsInput, for: session.id) {
                if let now = parkedByID[session.id], now != session { raise(.needsInput(now)) }
            } else if !planHolds.contains(session.id) {
                dismiss(.needsInput(session))
            }
        }
        // A reminder is dropped, silently, once its session stops waiting.
        for id in Array(reminders.keys) where parkedByID[id] == nil {
            forgetReminder(id)
        }
        syncSnoozed()
        // A failure card goes once its session runs or waits again.
        for case .failed(let session) in cards where !standing.holds(.failed, for: session.id) {
            dismiss(.failed(session))
        }

        if !firstRead { chime(sounds) }
        // Only a read that worked ends the first one: Bench may start before
        // the daemon, and what waits then is not news when it first reads it.
        if snapshot.readError == nil {
            firstRead = false
            // A read that worked but found no session at all is not trusted to
            // say that nothing waits or failed: it may be a database caught
            // empty, and what it would take back can't be sent again.
            if !snapshot.sessions.isEmpty { sessionsRead(standing) }
        }
    }

    /// The sound of this read's most urgent card (`PanelSound.loudest`), when
    /// Capsid isn't quiet. The setting is the sound's own to check.
    private func chime(_ sounds: [PanelSound]) {
        guard !isQuiet(), let sound = PanelSound.loudest(sounds) else { return }
        playSound(sound)
    }

    /// Raises a card; its sound if it is new, or none.
    private func raiseWithSound(_ card: LabCard) -> PanelSound? {
        raise(card) ? PanelSound.sound(for: card) : nil
    }

    // MARK: Cards

    /// Adds a card, or replaces the one with its id where it stands: a repeat
    /// neither reorders the queue nor counts as new. Says whether it is new.
    /// `announcing` false keeps it off Mac notifications: for a card the user
    /// just asked to see (Show Now), which is no news to them.
    @discardableResult
    private func raise(_ card: LabCard, announcing: Bool = true) -> Bool {
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
        if (isNew || asksSomethingNew), !firstRead, announcing { cardRaised(card); pushRaised(card) } // Phase 2 push
        return isNew
    }

    /// Only the card on top counts down. One queued behind another (a finish
    /// behind a question) would otherwise run out without ever being seen;
    /// its time starts when it reaches the top.
    private func armFrontCard() {
        // Nothing counts down out of sight: while Capsid is quiet the panel
        // isn't shown, so a card's time starts when it can be seen
        // (`quietChanged`).
        let front = isQuiet() ? nil : cards.first
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
    private func wake(_ id: String, chiming: Bool = true) {
        guard reminders.removeValue(forKey: id) != nil else { return }
        guard let session = waiting.first(where: { $0.id == id }) else { return }
        // Show Now (`chiming` false) is the user asking: no sound, no notification.
        let card = LabCard.needsInput(session)
        if raise(card, announcing: chiming), chiming, let sound = PanelSound.sound(for: card) { chime([sound]) }
    }

    private func forgetReminder(_ id: String) {
        reminders.removeValue(forKey: id)?.cancel()
    }

    /// Rebuilds `snoozed` from the reminders and the sessions that wait. A
    /// reminder whose session isn't in the last read is left out: the read
    /// that dropped the session drops it too.
    private func syncSnoozed() {
        let next = waiting.compactMap { session in
            reminders[session.id].map { SnoozedReminder(session: session, due: $0.due) }
        }
        if snoozed != next { snoozed = next }
    }

    /// `PresentingMode` changed. Quiet, no card counts down; no longer quiet,
    /// the card on top starts its time, and what finished meanwhile comes as
    /// one card unless a Nidus focus session still holds it.
    func quietChanged() {
        if !isQuiet() { releaseHeldFinishes(reason: .presenting) }
        armFrontCard()
    }

    /// The focus session ended: the reminders that waited for it come back,
    /// and what finished during it comes as one card (unless a presentation
    /// still holds it).
    func focusEnded() {
        let due = Set(reminders.filter { $0.value.waitsForFocus }.keys)
        due.forEach(forgetReminder)
        // The most recently active session first, as the queue is. One that
        // no longer waits has nothing to come back for.
        var sounds: [PanelSound] = []
        for session in waiting where due.contains(session.id) {
            if let sound = raiseWithSound(.needsInput(session)) { sounds.append(sound) }
        }
        chime(sounds)
        releaseHeldFinishes()
    }

    /// What finished during the focus session or while presenting, as one
    /// card worded for `reason`, the hold that lifted. Nothing while either
    /// still holds: the other one's end brings it.
    func releaseHeldFinishes(reason: NoticeRules.HoldReason = .focus) {
        guard !holdsFinishes(), !isQuiet(), let notice = NoticeRules.held(heldFinishes, reason: reason) else { return }
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
