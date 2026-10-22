// SinceYouLeftModel.swift — what changed while someone was away, kept for the
// sheet, the activity list, the panel's card and the phone (DESIGN.md, Since
// You Left). In memory only, like Recent: nothing about a session is written
// to disk.
//
// It has three jobs, none of which runs a timer of its own:
//   1. Away and back. The rule (AwayRule.swift) is fed whenever Capsid already
//      looks: after each read of the sessions, on a wake or an unlock, and when
//      Capsid or its window comes forward.
//   2. A return that counts becomes `pending`, the summary the sheet, the list
//      and the card show until Done. It is a view of the events Capsid saw
//      since the stretch began (`LabModel.eventRemembered`) and of the
//      sessions as they stand now, so it stays true as they change.
//   3. The details of its rows (Claude's last words for a finished session,
//      why one stopped, a figure or two) are read lazily: only once the sheet
//      or the list shows them, never while away, for at most six sessions and
//      one read at a time, through the typing gate (ReadingGate). The sentences
//      and pictures use the reads the panel's cards already use.
import AppKit
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "since-you-left")

/// Settings for Since You Left, kept apart from `SettingsKey`: one switch.
enum SinceYouLeftSettings {
    /// "Show this when I've been away 30 minutes or more": the sheet opens by
    /// itself on return. Off, the card and the list still carry it.
    static let sheetKey = "sinceYouLeftSheet"

    static func register(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [sheetKey: true])
    }

    static func sheetIsOn(_ defaults: UserDefaults = .standard) -> Bool {
        sheetIsOn(stored: defaults.object(forKey: sheetKey))
    }

    /// On unless the stored value says no (a bool, or the string a command-line `-sinceYouLeftSheet NO` gives).
    static func sheetIsOn(stored: Any?) -> Bool {
        switch stored {
        case let flag as Bool: flag
        case let text as String: !["no", "false", "0"].contains(text.lowercased())
        default: true
        }
    }
}

/// What a row knows beyond its session, once it has been read.
struct SinceYouLeftDetail: Equatable, Sendable {
    /// Claude's last words, a couple of lines of them (a finished session).
    var answer: String?
    /// Why it stopped, one sentence (a stopped one).
    var reason: String?
}

/// Everything that reaches outside the model, so tests can stand in for it.
struct SinceYouLeftDependencies {
    var now: @MainActor () -> Date = { Date() }
    /// Seconds since the last key, click or touch: the reader the specimens'
    /// hold uses (`MacPresence`).
    var idle: @MainActor () -> TimeInterval = { MacPresence.live.secondsSinceInput() }
    /// The screen is off: asleep, locked, or another user's session in front.
    var screenOff: @MainActor () -> Bool = { MacPresence.live.screenLocked() || CGDisplayIsAsleep(CGMainDisplayID()) != 0 }
    var calendar: Calendar = .current
    /// The 5-hour limit, as the plan model has it now.
    var usage: @MainActor () -> PlanLimit? = { PlanUsageModel.shared.limits.first { $0.kind == .session } }
    /// Reads the plan again unless it was read lately: on a return, so the
    /// figure the sheet shows is not five minutes old.
    var refreshUsage: @MainActor () -> Void = { PlanUsageModel.shared.readIfOlder(than: 60) }
    /// "Show a card" and "Show this when I've been away…" (the sheet).
    var cardsOn: @MainActor () -> Bool = { UserDefaults.standard.object(forKey: SettingsKey.showCards) as? Bool ?? true }
    var sheetOn: @MainActor () -> Bool = { SinceYouLeftSettings.sheetIsOn() }
    /// Capsid's main window is the key window: the sheet may open on it by itself.
    var mainWindowIsKey: @MainActor () -> Bool = { NSApp.isActive && MainWindowController.shared.windowIfLoaded?.isKeyWindow == true }
    /// Quiet While Presenting, and a Nidus focus session that holds finishes.
    var isQuiet: @MainActor () -> Bool = { PresentingMode.shared.isQuiet }
    var holdsFinishes: @MainActor () -> Bool = { NidusFocus.shared.holding }
    /// Opens the sheet on the main window.
    var showSheet: @MainActor () -> Void = { SinceYouLeftSheetController.shared.show() }
    var closeSheet: @MainActor () -> Void = { SinceYouLeftSheetController.shared.close() }
    /// The page is up and no demo runs: the details may be read.
    var canRead: @MainActor () -> Bool = { Demo.mode == nil && WebContainer.shared.status == .ready }
    /// Claude's last words in a finished session, as a couple of plain lines.
    var readAnswer: @MainActor (String) async -> String? = { await SinceYouLeftReads.answer(for: $0) }
    /// Why a stopped session stopped, its first line.
    var readReason: @MainActor (String) async -> String? = { await SinceYouLeftReads.reason(for: $0) }
    /// A reason already read for a failure card: no read needed.
    var knownReason: @MainActor (String) -> String? = { FailureReasoner.shared.reason(for: $0)?.line }
}

@MainActor
final class SinceYouLeftModel: ObservableObject {
    static let shared: SinceYouLeftModel = SinceYouLeftModel(lab: .shared, finished: FinishedResults(dependencies: .live()), dependencies: .init())

    /// A pending summary is dropped this long after the return: nothing old.
    static let lifetime: TimeInterval = 12 * 60 * 60
    /// How many events are kept to group.
    static let eventLimit = 200
    /// The card stays on the panel this long.
    static let cardLifetime: Duration = .seconds(30)

    /// A return that counted: the summary is built from it as the sessions stand.
    struct Pending: Equatable {
        let since: Date
        let back: Date
        /// The 5-hour limit when the stretch began, for what the stretch used.
        let baseline: PlanLimit?
    }

    @Published private(set) var pending: Pending?
    /// A stretch is under way: the phone shows what has happened so far.
    @Published private(set) var awaySince: Date?
    @Published private(set) var details: [String: SinceYouLeftDetail] = [:]
    /// The sheet is up.
    @Published private(set) var sheetShown = false
    private(set) var rule = AwayRule()

    let lab: LabModel
    let finished: FinishedResults
    let dependencies: SinceYouLeftDependencies
    private var events: [LabEvent] = []
    private var baseline: PlanLimit?
    private var started = false
    /// Sessions whose details have been asked for since this return: never read twice.
    private(set) var asked: Set<String> = []
    /// Reads started, for tests: sessions read for their answers or reasons.
    private(set) var readsStarted = 0
    private var loading: Task<Void, Never>?
    /// The card was due but a focus session or a presentation holds it.
    private(set) var cardHeld = false
    private var cardID: String?
    private var systemAsleep = false
    private var displayAsleep = false
    private var observers: [any NSObjectProtocol] = []
    private var distributed: [any NSObjectProtocol] = []

    init(lab: LabModel, finished: FinishedResults, dependencies: SinceYouLeftDependencies) {
        self.lab = lab
        self.finished = finished
        self.dependencies = dependencies
    }

    // MARK: Starting

    /// Listens to the sessions' reads and to the Mac going to sleep and
    /// waking. Never in a demo. Safe to call again.
    func start() {
        guard !started, Demo.mode == nil else { return }
        started = true
        SinceYouLeftSettings.register()
        // The typing rule for the reads of the rows (Reference/ReadingGate.swift).
        ReadingGate.shared.start()
        attach()
        let workspace = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ change: @escaping @MainActor (SinceYouLeftModel) -> Void) {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { change(self); self.observe() } }
            })
        }
        watch(NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        watch(NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        watch(NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        watch(NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        watch(NSWorkspace.sessionDidBecomeActiveNotification) { _ in }
        watch(NSWorkspace.sessionDidResignActiveNotification) { _ in }
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            distributed.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.observe() }
            })
        }
        // Coming back to Capsid is a moment to look: the window may be the
        // one the sheet opens on.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.observe() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let window = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let window, let main = MainWindowController.shared.windowIfLoaded, window == ObjectIdentifier(main) else { return }
                self.observe()
            }
        })
    }

    /// Wires the model to its lab: the events it remembers, each read it
    /// makes, the card that replaces the batched finish card, and the card's
    /// own Open. Tests call it on their own lab.
    func attach() {
        lab.eventRemembered = { [weak self] event in self?.remember(event) }
        lab.readObserved = { [weak self] in self?.observe() }
        lab.sinceCard = { [weak self] in self?.cardInPlaceOfHeld() }
        lab.showSinceYouLeft = { [weak self] in self?.showSheet() }
    }

    // MARK: Events

    func remember(_ event: LabEvent) {
        guard event.session != nil else { return }
        events.append(event)
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
        // Nothing old: what happened before the last day is never grouped.
        let cutoff = dependencies.now().addingTimeInterval(-2 * Self.lifetime)
        events.removeAll { $0.at < cutoff }
    }

    /// For tests: the events kept.
    var eventCount: Int { events.count }

    // MARK: Away and back

    /// One look: the rule takes the idle time and the screen's state, and a
    /// return that counts makes the summary.
    func observe() {
        let now = dependencies.now()
        expire(now: now)
        let screenOff = systemAsleep || displayAsleep || dependencies.screenOff()
        let before = rule.stretch
        let ret = rule.observe(now: now, idle: dependencies.idle(), screenOff: screenOff, calendar: dependencies.calendar)
        if let ret { returned(ret, baseline: baseline) }
        // The limit when a stretch begins: what it used is the difference.
        if rule.stretch == nil {
            baseline = nil
        } else if rule.stretch != before {
            baseline = dependencies.usage()
        }
        let ongoing = rule.stretch?.since
        if awaySince != ongoing { awaySince = ongoing }
        releaseHeldCard()
    }

    private func returned(_ ret: AwayRule.Return, baseline: PlanLimit?) {
        log.notice("Back after \(Int(ret.duration / 60), privacy: .public) minutes")
        let summary = SinceYouLeftSummary.make(since: ret.since, back: ret.back, events: events, waiting: lab.waiting,
                                               working: lab.working, putOff: Set(lab.snoozed.map(\.id)))
        guard !summary.isEmpty else { return }
        // A return not yet answered is replaced: this one covers what it did.
        endPending(clearCard: true)
        pending = Pending(since: ret.since, back: ret.back, baseline: baseline)
        dependencies.refreshUsage()
        if opensByItself {
            showSheet()
        } else if dependencies.cardsOn() {
            if holds { cardHeld = true } else { postCard() }
        }
    }

    /// Finishes or a presentation hold the panel back; so does this.
    private var holds: Bool { dependencies.holdsFinishes() || dependencies.isQuiet() }

    /// The sheet opens by itself: it is on, Capsid's main window is the key
    /// window, and nothing holds back.
    private var opensByItself: Bool {
        dependencies.sheetOn() && dependencies.mainWindowIsKey() && !holds
    }

    private func expire(now: Date) {
        if let pending, now.timeIntervalSince(pending.back) > Self.lifetime { endPending(clearCard: true) }
    }

    // MARK: What is shown

    /// The summary a person sees after a return, as the sessions stand now.
    var display: SinceYouLeftSummary? {
        guard let pending else { return nil }
        let summary = SinceYouLeftSummary.make(since: pending.since, back: pending.back, events: events, waiting: lab.waiting,
                                               working: lab.working, putOff: Set(lab.snoozed.map(\.id)))
        return summary.isEmpty ? nil : summary
    }

    /// What the phone shows: the summary after a return, or while a stretch
    /// of 30 minutes or more is still on, what has happened so far.
    func forPhone(now: Date? = nil) -> SinceYouLeftSummary? {
        if let display { return display }
        let now = now ?? dependencies.now()
        guard let since = rule.stretch?.since, now.timeIntervalSince(since) >= AwayRule.threshold else { return nil }
        let summary = SinceYouLeftSummary.make(since: since, back: nil, events: events, waiting: lab.waiting, working: lab.working,
                                               putOff: Set(lab.snoozed.map(\.id)))
        return summary.isEmpty ? nil : summary
    }

    /// What the stretch used of the 5-hour limit, when it can be said.
    func usage() -> UsageWhileAway? {
        UsageWhileAway.between(baseline: pending?.baseline, current: dependencies.usage())
    }

    /// How long they were away, in seconds.
    var awayDuration: TimeInterval? {
        pending.map { $0.back.timeIntervalSince($0.since) }
    }

    // MARK: The card

    static let cardIDPrefix = "since-you-left-"

    /// The card for a summary: its counts, how long, and Show.
    static func notice(for summary: SinceYouLeftSummary, now: Date) -> LabNotice? {
        guard let phrase = SinceYouLeftText.headline(finished: summary.finished.count, stopped: summary.stopped.count, needs: 0) else { return nil }
        return LabNotice(
            id: cardIDPrefix + String(Int(summary.since.timeIntervalSince1970)), symbol: "clock.arrow.circlepath",
            caption: SinceYouLeftText.title, title: phrase, detail: SinceYouLeftText.span(summary.away(now: now)),
            lifetime: cardLifetime, action: .sinceYouLeft)
    }

    private func postCard() {
        guard let summary = display, let notice = Self.notice(for: summary, now: dependencies.now()) else { return }
        cardHeld = false
        cardID = LabCard.notice(notice).id
        lab.post(notice)
    }

    /// A focus session or a presentation ended and its held finishes are
    /// released: if a return is waiting for the card, it comes in their place.
    private func cardInPlaceOfHeld() -> LabNotice? {
        guard cardHeld, let summary = display, let notice = Self.notice(for: summary, now: dependencies.now()) else { return nil }
        cardHeld = false
        cardID = LabCard.notice(notice).id
        return notice
    }

    /// The hold lifted without finishes to release: the card comes alone.
    private func releaseHeldCard() {
        guard cardHeld, !holds else { return }
        postCard()
    }

    // MARK: The sheet

    /// Opens the sheet on the main window, for the card's Show, the list's
    /// row and a return that opens it by itself.
    func showSheet() {
        guard display != nil else { return }
        sheetShown = true
        dependencies.showSheet()
    }

    /// The sheet went away (Done, Esc, or another way). Done and Esc clear
    /// the summary; the others leave it for the card and the list.
    func sheetClosed() {
        sheetShown = false
    }

    /// Done, Esc: the summary is cleared, its card goes, and what was read for
    /// it is let go.
    func done() {
        endPending(clearCard: true)
        dependencies.closeSheet()
        sheetShown = false
    }

    private func endPending(clearCard: Bool) {
        loading?.cancel()
        loading = nil
        pending = nil
        cardHeld = false
        if clearCard, let id = cardID, let card = lab.cards.first(where: { $0.id == id }) { lab.dismiss(card) }
        cardID = nil
        for id in asked { finished.forget(id) }
        asked = []
        details = [:]
    }

    // MARK: Reading the details

    /// The sheet or the list shows the rows: read what they need, now and no
    /// earlier. At most six sessions, one read at a time, and none while away.
    /// Reading a session twice is never needed: it is asked for once per return.
    func loadDetails(cardActions: CardActions? = nil) {
        guard loading == nil, pending != nil, !rule.isAway, dependencies.canRead(), let summary = display else { return }
        let rows = summary.readOrder().filter { !asked.contains($0.id) }
        guard !rows.isEmpty else { return }
        let actions = cardActions ?? CardActions(model: lab, plans: .shared, questions: .shared)
        let needsIDs = Set(summary.needs.map(\.id)), stoppedIDs = Set(summary.stopped.map(\.id))
        loading = Task { [weak self] in
            guard let self else { return }
            for row in rows {
                if Task.isCancelled || self.rule.isAway || self.pending == nil { break }
                self.asked.insert(row.id)
                if needsIDs.contains(row.id) {
                    // The card's own reads: the question and its choices.
                    actions.prepare(row.session)
                } else if stoppedIDs.contains(row.id) {
                    if let known = self.dependencies.knownReason(row.id) {
                        self.details[row.id, default: .init()].reason = known
                    } else {
                        self.readsStarted += 1
                        let reason = await self.dependencies.readReason(row.id)
                        if Task.isCancelled { break }
                        self.details[row.id, default: .init()].reason = reason
                    }
                } else {
                    self.readsStarted += 1
                    let answer = await self.dependencies.readAnswer(row.id)
                    if Task.isCancelled { break }
                    self.details[row.id, default: .init()].answer = answer
                    // The pictures: the list of its files, then up to three thumbnails.
                    await self.finished.load(row.session)
                }
            }
            self.loading = nil
        }
    }

    /// Waits for the reads under way, for tests.
    func settled() async {
        await loading?.value
    }

    // MARK: Made up

    /// Shows a made-up return and reads nothing: a demo's, a snapshot's.
    func showDemo(since: Date, back: Date, events: [LabEvent], baseline: PlanLimit?, details: [String: SinceYouLeftDetail] = [:]) {
        self.events = events
        pending = Pending(since: since, back: back, baseline: baseline)
        self.details = details
        asked = Set(details.keys)
    }
}
