// PageSleep.swift — Claude Science's page can sleep while the main window is
// closed (DESIGN.md, Daemon and sign-in, "The page asleep"). With Settings →
// General → "Keep Claude Science loaded when its window is closed" on (the
// default) nothing here ever unloads anything, and Capsid behaves as it always
// did. Off, the page is unloaded for real a short while after the window
// closes, and comes back where it was when the window shows again, when the
// setting is turned back on, or for as long as an action needs it (Approve on
// a card, a reply, a phone request, …).
//
// This file is the rule and its timing, and nothing else: whether the page is
// up, how it is unloaded and how it is woken come in as closures, so the rules
// are tested without a web view (PageSleepTests). `WebContainer` owns the one
// the app uses.
import Foundation

/// When the page sleeps and when it wakes.
enum PageSleepRule {
    /// How long a closed window keeps its page before it sleeps. Long enough
    /// that closing the window and opening it again costs nothing, short
    /// enough that a window closed for the evening frees its memory soon.
    static let grace = Duration.seconds(45)

    /// The page as the rule sees it.
    enum Page: Equatable {
        /// Up and showing Claude Science (`WebContainer.Status.ready`).
        case loaded
        /// Starting, signing in, waking or failed: never unloaded from here.
        /// A start or sign-in under way finishes first; a failure has nothing
        /// loaded, and its quiet tries sign in, after which the page is `loaded`.
        case busy
        /// Unloaded on purpose (`WebContainer.Status.asleep`).
        case asleep
    }

    enum Decision: Equatable {
        /// Leave the page as it is.
        case keep
        /// Unload it once `grace` has passed with nothing changing.
        case sleepAfterGrace
        /// Load it again now.
        case wake
    }

    /// - `keepLoaded`: the Settings switch (on is today's behaviour).
    /// - `windowOpen`: the main window is open (shown or minimised, not closed).
    /// - `uses`: actions that need the page right now (a write through it, a
    ///   phone request, a reply), each held from before it asks to after it ends.
    static func decide(keepLoaded: Bool, windowOpen: Bool, uses: Int, page: Page) -> Decision {
        let wanted = keepLoaded || windowOpen || uses > 0
        switch page {
        case .asleep: return wanted ? .wake : .keep
        case .loaded: return wanted ? .keep : .sleepAfterGrace
        case .busy: return .keep
        }
    }
}

/// The page's sleep, for the one web view (`WebContainer.sleeper`). Told about
/// every change to its inputs, it unloads the page after the grace or wakes it
/// at once, and never does either twice.
@MainActor
final class PageSleep {
    private(set) var keepLoaded: Bool
    private(set) var windowOpen: Bool
    /// Actions holding the page awake.
    private(set) var uses = 0
    /// Calls into the page under way (a read, a write, a file's chunks). They
    /// neither wake the page nor start the grace over, but the page never
    /// sleeps under one: when the grace ends it waits for them to finish.
    private(set) var inFlight = 0

    private let page: () -> PageSleepRule.Page
    private let unload: () -> Void
    private let wake: () -> Void
    private let wait: (Duration) async -> Void

    private var graceTask: Task<Void, Never>?
    static let drainPoll = Duration.milliseconds(500)
    /// Bumped whenever the grace is cancelled, so a wait that was under way
    /// when something changed ends without unloading.
    private var generation = 0

    /// The app's `WebContainer` makes one; tests make their own.
    init(keepLoaded: Bool, windowOpen: Bool,
         page: @escaping () -> PageSleepRule.Page,
         unload: @escaping () -> Void,
         wake: @escaping () -> Void,
         wait: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0, tolerance: .seconds(2)) }) {
        self.keepLoaded = keepLoaded
        self.windowOpen = windowOpen
        self.page = page
        self.unload = unload
        self.wake = wake
        self.wait = wait
    }

    /// The window or the switch wants the page, not just an action.
    var wantsPageForItself: Bool { keepLoaded || windowOpen }

    /// The grace is running: the page will sleep unless something changes.
    var isCountingDown: Bool { graceTask != nil }

    func setKeepLoaded(_ value: Bool) {
        guard value != keepLoaded else { return }
        keepLoaded = value
        evaluate()
    }

    func setWindowOpen(_ value: Bool) {
        guard value != windowOpen else { return }
        windowOpen = value
        evaluate()
    }

    /// The page's status changed (it came up, failed, or went to sleep).
    func pageChanged() { evaluate() }

    /// An action that needs the page starts: it wakes a sleeping page and keeps
    /// it from sleeping until `endUse`.
    func beginUse() {
        uses += 1
        evaluate()
    }

    func endUse() {
        uses = max(0, uses - 1)
        evaluate()
    }

    /// A call into the page starts (see `inFlight`).
    func beginCall() { inFlight += 1 }
    func endCall() { inFlight = max(0, inFlight - 1) }

    private var decision: PageSleepRule.Decision {
        PageSleepRule.decide(keepLoaded: keepLoaded, windowOpen: windowOpen, uses: uses, page: page())
    }

    private func evaluate() {
        switch decision {
        case .keep:
            cancelGrace()
        case .wake:
            cancelGrace()
            wake()
        case .sleepAfterGrace:
            guard graceTask == nil else { return }
            let mine = generation
            graceTask = Task { [weak self] in await self?.countDown(mine) }
        }
    }

    private func countDown(_ mine: Int) async {
        await wait(PageSleepRule.grace)
        // Never under a call into the page: it finishes first (each has its own deadline).
        while inFlight > 0, generation == mine {
            await wait(Self.drainPoll)
        }
        guard generation == mine else { return }
        graceTask = nil
        // Asked again: anything that changed meanwhile has already cancelled
        // this wait, but the page itself may have changed without a word.
        guard decision == .sleepAfterGrace else { return }
        unload()
    }

    private func cancelGrace() {
        guard graceTask != nil else { return }
        generation += 1
        graceTask?.cancel()
        graceTask = nil
    }
}

/// Runs an action with the page held awake (`WebContainer.withPage`), for the
/// features' `Dependencies`: tests pass `PageHold.none`, which just runs it.
typealias PageHold = @MainActor (@MainActor () async -> Void) async -> Void

enum PageHolds {
    static let live: PageHold = { body in await WebContainer.shared.withPage { await body() } }
    static let none: PageHold = { body in await body() }
}

/// The Settings switch, General → "Keep Claude Science loaded when its window
/// is closed". Unset is on.
enum PageSleepSetting {
    static func keepsLoaded(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.keepPageLoaded) as? Bool ?? true
    }
}

/// A window that reads through the page while it is open: the page is held
/// awake for it (`WebContainer.readerWindowsChanged`), and wakes if it slept.
@MainActor
protocol PageReadingWindow: AnyObject {}

extension ResultsWindowController: PageReadingWindow {}
extension KeptWindowController: PageReadingWindow {}
extension CompareWindowController: PageReadingWindow {}
extension ReferenceWindowController: PageReadingWindow {}
extension AskModelWindowController: PageReadingWindow {}
