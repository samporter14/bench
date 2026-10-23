// CompanionSections.swift — what the home popover says, decided in one place
// and with no view in it (DESIGN.md, Menu bar home; board 1 of the Capsid 1.0
// mock-ups): the words, the counts, the order, what a row's buttons are, and
// what each section shows when it has nothing. The popover draws exactly this
// (CompanionHomeView.swift); tests read it.
//
// Pure: sessions, offers, a limit and today's files come in; titles, rows and
// lines come out. Nothing here reads a model, so a popover that is closed has
// nothing of this to ask for.
import Foundation

/// The popover's words, apart from the rows'.
enum CompanionText {
    static let name = "Capsid"
    static let quickStartPlaceholder = "Start a session…"
    static let nothingToDo = "Nothing needs you and nothing is working."
    static let showAll = "Show all"
    static let resultsTitle = "Results today"
    static let usageLabel = "5-hour limit"
    static let quietHelp = "Quiet while presenting"
    static let settingsHelp = "Settings"

    static func needs(_ n: Int) -> String { "Needs you · \(n)" }

    /// "Working · 2", or "Paused · 2" when a used-up limit holds every one.
    static func working(_ n: Int, paused: Bool) -> String { "\(paused ? "Paused" : "Working") · \(n)" }

    /// "Results today · 7"; "7+" while more sessions made files today than have been read.
    static func results(_ n: Int, partial: Bool) -> String { "Results today · \(n)\(partial ? "+" : "")" }

    static func more(_ n: Int) -> String { "\(n) more" }

    /// The foot's button. Capsid's window is always there; the board's "Open
    /// Claude Science" is for the day Capsid's window can be off.
    static func openButton(capsidWindowOn: Bool = true) -> String {
        capsidWindowOn ? "Open Capsid" : "Open Claude Science"
    }

    static func steps(_ n: Int) -> String { n == 1 ? "1 step" : "\(n) steps" }

    /// "RNA-seq pilot · 12 min", "Oxidative stress · 6 steps · 3 min": the project, the plan's
    /// steps when the card has read them, and how long it has waited.
    static func needDetail(project: String, steps: Int?, waitingSince: Date, now: Date) -> String {
        [project, steps.map(Self.steps), SinceYouLeftText.shortSpan(max(0, now.timeIntervalSince(waitingSince)))]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "Assay development", or "Assay development · Step 4 of 6" when its plan's progress is in memory.
    static func workingDetail(project: String, progress: PlanProgress?) -> String {
        guard let progress else { return project }
        return "\(project) · Step \(progress.step) of \(progress.total)"
    }

    /// "54% left · resets 11:12 AM", "All used · resets 11:12 AM". A reset that has passed is "resetting now".
    static func usageValue(_ limit: PlanLimit, now: Date, calendar: Calendar = .current,
                           locale: Locale = .autoupdatingCurrent) -> String {
        let head = limit.reached ? "All used" : "\(limit.leftPercent)% left"
        guard let resetsAt = limit.resetsAt else { return head }
        guard resetsAt > now else { return head + " · resetting now" }
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                       calendar: calendar, timeZone: calendar.timeZone))
        return head + " · resets " + time
    }

    /// The menu bar item as VoiceOver names it.
    static func itemLabel(needs: Int) -> String {
        needs > 0 ? "Capsid, \(SinceYouLeftText.needs(needs))" : "Capsid"
    }

    /// "⌃⌥⌘Space", or nothing when Quick Start has no key.
    static func quickStartKey(_ choice: GlobalHotKey.Choice) -> String? {
        choice == .none ? nil : choice.title
    }
}

// MARK: Needs you

struct CompanionNeedRow: Identifiable, Equatable {
    /// Which glyph and which words: a question, a plan, a request for permission, a stop.
    enum Kind: Equatable { case question, plan, request, stopped }

    /// One of the row's buttons.
    struct Pill: Identifiable, Equatable {
        enum Action: Equatable {
            /// What the card would do (`CardActions.perform`).
            case card(CardAction)
            /// Put it off five minutes, as the card's Later does.
            case later
        }

        let action: Action
        /// The lead, in the clay.
        let prominent: Bool

        var title: String {
            switch action {
            case .card(let card): card.title
            case .later: "Later"
            }
        }

        var id: String { title }
    }

    let session: SessionStatus
    let kind: Kind
    /// "Asked you a question", in clay words above the title.
    let caption: String
    /// A plan's steps, once its card has read the plan.
    let steps: Int?
    /// The card's own state: buttons, a spinner while it sends, or "Approved".
    let lead: CardOffer.Lead
    let pills: [Pill]
    /// Why a send didn't go, or that the request changed: a sentence under the buttons.
    let problem: String?

    var id: String { session.id }

    /// A plan, a request for permission, or a question. A wait with no reason Capsid knows ("Waiting for you")
    /// is a request once its card has read one (its answers are a request's: Review, Allow Once, Deny).
    static func kind(of reason: WaitingReason?, offer: CardOffer? = nil) -> Kind {
        switch reason ?? .other {
        case .plan: return .plan
        case .question: return .question
        case .web, .files, .delete, .tool, .license: return .request
        case .other:
            guard let offer else { return .question }
            if offer.hasDeny { return .request }
            if case .button(let lead) = offer.lead, lead == .review || lead == .allowOnce { return .request }
            return .question
        }
    }

    /// The buttons a card's offer comes to in the popover (board 1): a question offers Reply, Open and Later; a
    /// plan its two answers, Approve and Request changes…; a request its lead, Deny and Later. A button the
    /// card keeps in a menu or leaves to the row (Open on a request, whose title opens the session) isn't a pill.
    static func pills(for offer: CardOffer, canLater: Bool) -> [Pill] {
        var pills: [Pill] = []
        switch offer.lead {
        case .done: return []
        case .button(let lead): pills.append(Pill(action: .card(lead), prominent: true))
        case .sending: break
        }
        if offer.canRequestChanges {
            pills.append(Pill(action: .card(.requestChanges), prominent: false))
            return pills
        }
        if offer.hasOpen { pills.append(Pill(action: .card(.open), prominent: false)) }
        if offer.hasDeny { pills.append(Pill(action: .card(.deny), prominent: false)) }
        if canLater { pills.append(Pill(action: .later, prominent: false)) }
        return pills
    }
}

// MARK: Working

struct CompanionWorkingRow: Identifiable, Equatable {
    let session: SessionStatus
    /// The project, and the plan's step when it is in memory.
    let detail: String
    /// When a used-up limit holds it, when it resumes; the clock stops.
    let pause: String?
    var id: String { session.id }
}

// MARK: Results, Since You Left, the limit

struct CompanionTile: Identifiable, Equatable {
    /// The file's version id.
    let version: String
    let name: String
    /// The kind tile's word ("CSV") for a file that has no picture.
    let label: String
    /// An image: a picture is read for it.
    let isPicture: Bool
    var id: String { version }
}

struct CompanionResultsSection: Equatable {
    /// Files made today in the sessions looked at.
    let count: Int
    let partial: Bool
    let tiles: [CompanionTile]
    /// "Results today · 7"; just "Results today" when sessions made today are not in memory and none of their
    /// files are known.
    var title: String { count == 0 ? CompanionText.resultsTitle : CompanionText.results(count, partial: partial) }

    /// Tiles on the board's row.
    static let tileLimit = 4

    /// The newest pictures first, then the other files, four in all. With no file known the section is only
    /// its title and "Show all" when sessions made today haven't been looked at, and nothing when none were.
    @MainActor
    static func make(entries: [ArtifactEntry], partial: Bool) -> CompanionResultsSection? {
        guard !entries.isEmpty else {
            return partial ? CompanionResultsSection(count: 0, partial: true, tiles: []) : nil
        }
        let pictures = entries.filter { ArtifactGate.thumb(kind: $0.kind) == nil }
        let others = entries.filter { ArtifactGate.thumb(kind: $0.kind) != nil }
        let tiles = (pictures + others).prefix(tileLimit).map {
            CompanionTile(version: $0.version, name: $0.name, label: SinceTile.label(for: $0),
                          isPicture: ArtifactGate.thumb(kind: $0.kind) == nil)
        }
        return CompanionResultsSection(count: entries.count, partial: partial, tiles: tiles)
    }
}

struct CompanionSinceSection: Equatable {
    /// "Since you left · 2 h 14 min".
    let title: String
    /// "3 finished, 1 stopped".
    let headline: String
}

struct CompanionUsageLine: Equatable {
    let label: String
    let value: String
    /// How much is used, for the bar: the board fills what is used while the words say what is left.
    let used: Double
    /// Under a fifth left: the words turn clay.
    let isLow: Bool
}

// MARK: The whole

struct CompanionSections: Equatable {
    /// "Not updating: Claude Science isn't running" while the sessions can't be read.
    var problem: String?
    var needsTotal = 0
    var needs: [CompanionNeedRow] = []
    var needsHidden = 0
    var workingTotal = 0
    var working: [CompanionWorkingRow] = []
    var workingHidden = 0
    var allPaused = false
    var results: CompanionResultsSection?
    var since: CompanionSinceSection?
    var usage: CompanionUsageLine?

    static let empty = CompanionSections()

    /// The blocks the popover draws between its field and its foot, in the board's order. A hairline
    /// separates one from the next.
    enum Block: Hashable {
        /// "Nothing needs you and nothing is working."
        case quiet
        case needs, working, results, since
    }

    /// The blocks that have something to show, top to bottom.
    var blocks: [Block] {
        var blocks: [Block] = []
        if isQuiet { blocks.append(.quiet) }
        if needsTotal > 0 { blocks.append(.needs) }
        if workingTotal > 0 { blocks.append(.working) }
        if results != nil { blocks.append(.results) }
        if since != nil { blocks.append(.since) }
        return blocks
    }

    /// How many rows each list shows before "N more".
    static let rowLimit = 3

    var needsTitle: String? { needsTotal > 0 ? CompanionText.needs(needsTotal) : nil }
    var workingTitle: String? { workingTotal > 0 ? CompanionText.working(workingTotal, paused: allPaused) : nil }
    /// Nothing needs you and nothing works: the popover says so in a line.
    var isQuiet: Bool { needsTotal == 0 && workingTotal == 0 }

    /// What needs you, as the menu bar item counts it: sessions that wait for you now and sessions that stopped
    /// with an error. A session put off with Later isn't asking until its reminder comes.
    static func needsCount(_ needs: NeedsYou) -> Int { needs.asks.count + needs.failed.count }

    /// Everything the sections are made from, as plain values and lookups.
    struct Input {
        var needs: NeedsYou
        var working: [SessionStatus]
        /// What a session's card offers now, and whether Later may put it off.
        var offer: (SessionStatus) -> CardOffer
        var canLater: (SessionStatus) -> Bool
        var planSteps: (SessionStatus) -> Int?
        var pause: (SessionStatus) -> UsagePause?
        var progress: (SessionStatus) -> PlanProgress?
        /// Today's files, newest first, and whether more sessions made files than were looked at.
        var results: [ArtifactEntry]
        var resultsPartial: Bool
        var since: SinceYouLeftSummary?
        var usage: PlanLimit?
        var problem: ScienceError?
        var now: Date
        var showsAllNeeds = false
        var showsAllWorking = false
    }

    @MainActor
    static func make(_ input: Input) -> CompanionSections {
        var sections = CompanionSections()
        sections.problem = input.problem.map { "Not updating: \($0.label)" }

        // Needs you: what asks first, the longest wait on top, then what stopped.
        let rows = input.needs.asks.map { session -> CompanionNeedRow in
            let offer = input.offer(session)
            let reason = session.waitingReason ?? .other
            return CompanionNeedRow(session: session, kind: CompanionNeedRow.kind(of: reason, offer: offer), caption: reason.sentence,
                                    steps: input.planSteps(session), lead: offer.lead,
                                    pills: CompanionNeedRow.pills(for: offer, canLater: input.canLater(session)),
                                    problem: offer.problem)
        } + input.needs.failed.map { session in
            CompanionNeedRow(session: session, kind: .stopped, caption: "Stopped with an error", steps: nil,
                             lead: .button(.open),
                             pills: [.init(action: .card(.open), prominent: true)], problem: nil)
        }
        sections.needsTotal = rows.count
        let needsShown = input.showsAllNeeds ? rows.count : min(rows.count, rowLimit)
        sections.needs = Array(rows.prefix(needsShown))
        sections.needsHidden = rows.count - needsShown

        // Working: the model's order, a held session without its clock.
        let working = input.working.map { session in
            CompanionWorkingRow(session: session,
                                detail: CompanionText.workingDetail(project: session.projectName, progress: input.progress(session)),
                                pause: input.pause(session)?.sentence(now: input.now))
        }
        sections.workingTotal = working.count
        sections.allPaused = !working.isEmpty && working.allSatisfy { $0.pause != nil }
        let workingShown = input.showsAllWorking ? working.count : min(working.count, rowLimit)
        sections.working = Array(working.prefix(workingShown))
        sections.workingHidden = working.count - workingShown

        sections.results = CompanionResultsSection.make(entries: input.results, partial: input.resultsPartial)

        if let since = input.since, let headline = since.headline {
            sections.since = CompanionSinceSection(
                title: SinceYouLeftText.listTitle(since.away(now: input.now)), headline: headline)
        }

        if let limit = input.usage {
            sections.usage = CompanionUsageLine(
                label: CompanionText.usageLabel, value: CompanionText.usageValue(limit, now: input.now),
                used: Double(limit.usedPercent) / 100, isLow: limit.isLow)
        }
        return sections
    }
}

// MARK: The menu bar item

/// What the status item shows: the quiet Capsid glyph, or while a session works (and the older switch is on)
/// the specimen, and the count of what needs you beside either. Hidden when the item's own switch is off.
struct MenuBarFace: Equatable {
    enum Mark: Equatable {
        /// The five-node glyph.
        case capsid
        /// The working specimen.
        case specimen
        /// Every working session is held by a used-up limit: a still pause mark.
        case paused
    }

    var visible: Bool
    var mark: Mark
    var needs: Int

    static let hidden = MenuBarFace(visible: false, mark: .capsid, needs: 0)

    static func of(homeOn: Bool, specimenOn: Bool, working: Int, allPaused: Bool, needs: Int) -> MenuBarFace {
        guard homeOn else { return .hidden }
        let mark: Mark = specimenOn && working > 0 ? (allPaused ? .paused : .specimen) : .capsid
        return MenuBarFace(visible: true, mark: mark, needs: max(0, needs))
    }

    /// "2", or "99+": a count has to fit the item.
    var countText: String? {
        needs > 0 ? (needs > 99 ? "99+" : "\(needs)") : nil
    }

    /// The item's width: the glyph, and room for a count.
    var width: CGFloat {
        24 + (countText.map { 6 + CGFloat($0.count) * 7 } ?? 0)
    }

    var accessibilityLabel: String { CompanionText.itemLabel(needs: needs) }
}
