// CompanionModel.swift — the home popover's model (DESIGN.md, Menu bar home).
// It holds `CompanionSections` for the popover to draw, built from what the
// app already keeps in memory: LabModel (what needs you, what works, which
// cards are up), the card machinery (`CardActions`: what a row may offer),
// PlanUsageModel's session limit, Since You Left's pending summary, the plan
// progress the panel has read, and today's files (`CompanionResults`).
//
// It does nothing while the popover is closed. `open()` takes a look and
// starts to watch; `close()` stops watching and lets everything go. There is
// no timer: it looks again only when one of those things changes, and the
// clocks on the rows tick in the view. It starts no poll and calls no
// refresh: the plan's limit is shown as the toolbar's reading last left it.
//
// One thing is asked for on opening, as the activity list asks it: the cards'
// own reads (`CardActions.prepare`) for the rows shown, so a plan that isn't
// on top still offers Approve and a question Reply.
import Combine
import Foundation

@MainActor
final class CompanionModel: ObservableObject {
    struct Sources {
        var lab: LabModel
        var cards: CardActions
        var results: CompanionResults
        /// The session (5-hour) limit as the plan model has it.
        var usage: @MainActor () -> PlanLimit?
        /// The summary of a return that is waiting to be looked at.
        var since: @MainActor () -> SinceYouLeftSummary?
        /// What holds a session back, from a used-up limit.
        var pause: @MainActor (String) -> UsagePause?
        /// A working session's plan progress, when the panel has read it.
        var progress: @MainActor (String) -> PlanProgress?
        /// What each shown row's card reads when the popover opens.
        var prepare: @MainActor (SessionStatus) -> Void
        var quickStartKey: @MainActor () -> GlobalHotKey.Choice
        var now: @MainActor () -> Date = { Date() }
        /// The sessions in memory, whatever their state (the last read's, which Quick Open searches): Recent's.
        var recent: @MainActor () -> [SessionStatus] = { [] }
        /// What the "Start a session…" field reads and sends with (CompanionStart.swift); none given, it has no
        /// project and sends nothing.
        var start: CompanionStart.Dependencies? = nil
        /// What to watch while the popover is open; any of them firing looks again.
        var changes: @MainActor () -> [AnyPublisher<Void, Never>]

        @MainActor
        static func live() -> Sources {
            let lab = LabModel.shared
            let cards = CardActions.shared
            let usage = PlanUsageModel.shared
            return Sources(
                lab: lab, cards: cards, results: CompanionResults(dependencies: .live()),
                usage: { usage.limits.first { $0.kind == .session } },
                since: { SinceYouLeftModel.shared.display },
                pause: { UsagePauseModel.shared.pause(for: $0) },
                progress: { PanelInsights.shared.progress[$0] },
                prepare: { cards.prepare($0) },
                quickStartKey: { GlobalKeys.shared.choice(for: .quickStart) },
                recent: { lab.sessions },
                start: .live(),
                changes: {
                    func tell<P: Publisher>(_ publisher: P) -> AnyPublisher<Void, Never> where P.Failure == Never {
                        publisher.map { _ in () }.eraseToAnyPublisher()
                    }
                    return [
                        // Recent follows `latest`, which moves when the quiet sessions do, and not `reads`, which
                        // moves with every read of a working session's tokens.
                        tell(lab.$working), tell(lab.$waiting), tell(lab.$cards), tell(lab.$snoozed), tell(lab.$problem),
                        tell(lab.$latest),
                        tell(cards.plans.objectWillChange), tell(cards.questions.objectWillChange),
                        tell(usage.$limits), tell(SinceYouLeftModel.shared.$pending),
                        tell(UsagePauseModel.shared.objectWillChange), tell(PanelInsights.shared.$progress),
                    ]
                })
        }
    }

    @Published private(set) var sections = CompanionSections.empty
    @Published private(set) var isOpen = false
    /// "⌃⌥⌘Space", shown in the field; nothing when Quick Start has no key.
    @Published private(set) var quickStartKey: String?
    @Published private(set) var showsAllNeeds = false
    @Published private(set) var showsAllWorking = false
    /// The height the popover's middle may take, under the menu bar item it opens from (the panel sets it before
    /// it opens): Recent shows what fits in it. Nil, no limit.
    var room: CGFloat?

    let sources: Sources
    /// The "Start a session…" field: its words, its project, its send. It outlives a closing, so a send in flight
    /// goes on and says how it went at the next opening.
    let start: CompanionStart
    private var subscriptions: Set<AnyCancellable> = []
    private var scheduled = false

    init(sources: Sources) {
        self.sources = sources
        start = CompanionStart(dependencies: sources.start ?? .none)
    }

    // MARK: Opening and closing

    func open() {
        guard !isOpen else { return }
        isOpen = true
        // The files in memory first, so the first look has them.
        sources.results.open()
        start.open()
        watch()
        refresh()
        for row in sections.needs where row.kind != .stopped { sources.prepare(row.session) }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        subscriptions.removeAll()
        scheduled = false
        sources.results.close()
        start.close()
        sections = .empty
        showsAllNeeds = false
        showsAllWorking = false
    }

    /// "N more" under Needs you: every row.
    func showAllNeeds() {
        showsAllNeeds = true
        refresh()
    }

    func showAllWorking() {
        showsAllWorking = true
        refresh()
    }

    // MARK: Looking

    private func watch() {
        var publishers = sources.changes()
        publishers.append(sources.results.$revision.map { _ in () }.eraseToAnyPublisher())
        for publisher in publishers {
            // A change is told before it lands: look on the next turn, once for everything that changed.
            publisher.sink { [weak self] in self?.schedule() }.store(in: &subscriptions)
        }
    }

    private func schedule() {
        guard isOpen, !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.scheduled else { return }
                self.scheduled = false
                self.refresh()
            }
        }
    }

    /// Builds the sections from what is in memory now. Only an open popover does.
    func refresh() {
        guard isOpen else { return }
        let lab = sources.lab, cards = sources.cards
        let queued = Set(lab.cards.compactMap { card -> String? in
            if case .needsInput(let session) = card { session.id } else { nil }
        })
        let input = CompanionSections.Input(
            needs: NeedsYou(model: lab), working: lab.working,
            offer: { cards.offer(for: $0) }, canLater: { queued.contains($0.id) },
            planSteps: { Self.steps(of: cards.plans.state(for: $0.id)) },
            pause: { [sources] in sources.pause($0.id) }, progress: { [sources] in sources.progress($0.id) },
            results: sources.results.entries, resultsPartial: sources.results.partial,
            since: sources.since(), usage: sources.usage(), problem: lab.problem, now: sources.now(),
            showsAllNeeds: showsAllNeeds, showsAllWorking: showsAllWorking, recent: sources.recent(), room: room)
        let made = CompanionSections.make(input)
        if made != sections { sections = made }
        let key = CompanionText.quickStartKey(sources.quickStartKey())
        if key != quickStartKey { quickStartKey = key }
    }

    private static func steps(of state: PlanCardState?) -> Int? {
        switch state {
        case .ready(let preview)?, .approving(let preview)?, .approved(let preview)?, .problem(_, let preview)?: preview.steps
        default: nil
        }
    }
}

/// What the popover's buttons do. The app's own are `CompanionPanelController.actions`; a demo's and a
/// snapshot's do nothing that reaches anything.
struct CompanionActions {
    var perform: @MainActor (CardAction, SessionStatus) -> Void = { _, _ in }
    var later: @MainActor (SessionStatus) -> Void = { _ in }
    var open: @MainActor (SessionStatus) -> Void = { _ in }
    /// ⌥-click on a Recent row, or its menu's Open as Reference: the reader beside the work.
    var reference: @MainActor (SessionStatus) -> Void = { _ in }
    /// A Recent row's Copy Link: the `bench://` link that opens the session in Capsid.
    var copyLink: @MainActor (SessionStatus) -> Void = { _ in }
    /// Recent's "N more": Quick Open, which lists every session.
    var showQuickOpen: @MainActor () -> Void = {}
    /// ⌘↩ in the field (and ↩ with nothing typed): opens Quick Start with the words, the project, the plan setting
    /// and the retry identity. True when Quick Start took them; false when it is sending something of its own and
    /// keeps that, and then nothing is opened and the words stay in the field.
    var quickStart: @MainActor (CompanionStart.HandOff) -> Bool = { _ in true }
    /// Open beside "Started in …": the session the field just started (its id, its project's).
    var openStarted: @MainActor (String, String) -> Void = { _, _ in }
    var showResults: @MainActor () -> Void = {}
    var showSince: @MainActor () -> Void = {}
    var openCapsid: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}
    var toggleQuiet: @MainActor () -> Void = {}
    /// The popover steps aside (a button that opens a window of its own first closes it).
    var close: @MainActor () -> Void = {}

    static let none = CompanionActions()
}
