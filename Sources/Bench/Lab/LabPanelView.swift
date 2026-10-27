// LabPanelView.swift — the panel's content (DESIGN.md, Lab, "The panel"): one
// Liquid Glass shape holding the working session, or the top card of the
// queue. Clay marks only the live dot, "needs you" and the primary button.
import SwiftUI

/// Whether the pointer is over the panel. Fed by the hosting view's own
/// tracking area: SwiftUI's `onHover` may never fire in a window that is
/// never key, in an app that is not active, and the panel is both.
@MainActor
final class PanelHover: ObservableObject {
    @Published var isInside = false
}

extension ColorScheme {
    /// The scenes' ink. Passed as an explicit colour rather than `.primary`:
    /// it then changes with the appearance as a value the scene views see,
    /// so they are sure to redraw, and it reads the same as `.primary`.
    var sceneInk: Color {
        self == .dark ? .white : Color(red: 0.08, green: 0.08, blue: 0.075)
    }
}

/// "<prefix> · m:ss" for a turn's running clock, ticking on the turn's own
/// seconds; the prefix alone when the turn's start is not known. While the Mac
/// is left alone (SpecimenHold) it ticks on the turn's own minutes: nobody
/// reads the seconds, and a tick a second keeps the whole panel awake.
struct TurnClockText: View {
    let prefix: String
    let since: Date?
    /// False draws the clock alone, for a row with room for nothing else.
    var showsPrefix = true
    @ObservedObject private var hold = SpecimenHold.shared

    var body: some View {
        // The ZStack keeps this view's identity when the timeline below is
        // swapped, so the watching starts and stops with the clock.
        ZStack {
            if let since {
                TimelineView(.periodic(from: since, by: hold.holds ? 60 : 1)) { context in
                    let clock = ElapsedClock.format(context.date.timeIntervalSince(since))
                    Text(showsPrefix ? "\(prefix) · \(clock)" : clock)
                        .monospacedDigit()
                }
                // A new timeline, so the clock is right at once when the hold ends.
                .id(hold.holds)
            } else {
                Text(prefix)
            }
        }
        .modifier(WatchesHold(active: since != nil))
    }
}

/// "Kinesin · A motor protein on a microtubule": the specimen that's playing,
/// on one quiet line. It follows the rotation as the panel's well does, by the
/// clock, and ticks only when the rotation moves on. One line, cut at its end,
/// so the panel keeps its size however long a caption is. Under Reduce Motion
/// the well is a still flask, so the line names that.
struct SpecimenCaptionLine: View {
    let rotation: Rotation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.stillSpecimens) private var stillSpecimens
    private var reduceMotion: Bool { systemReduceMotion || stillSpecimens }
    /// While the specimen holds a still (SpecimenHold) the line names it.
    @ObservedObject private var hold = SpecimenHold.shared

    var body: some View {
        if reduceMotion {
            line(WorkingGlyph.still(in: rotation))
        } else {
            TimelineView(SceneBoundarySchedule(rotation: rotation)) { timeline in
                line(hold.scene(in: rotation, at: timeline.date))
            }
        }
    }

    /// The name, then its caption: two lines at most, since the column is
    /// too narrow for both on one and a cut caption says little.
    private func line(_ scene: LabScene?) -> some View {
        let caption = scene.flatMap { SpecimenGuide.note(for: $0.name)?.caption }
        let name = Text(scene?.name ?? "").fontWeight(.medium)
        let rest = Text(caption.map { " · \($0)" } ?? "")
        return Text("\(name)\(rest)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2, reservesSpace: true)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LabPanelView: View {
    /// Clear space round the glass, so its own shadow and highlights are not
    /// cut off at the window's edge. The controller places the window so the
    /// glass, not the window, sits `Theme.panelInset` from the corner.
    static let margin: CGFloat = 16

    @ObservedObject var model: LabModel
    @ObservedObject var hover: PanelHover
    /// The chosen size and rotation: a change resizes the live panel.
    @ObservedObject private var settings = SceneSettings.shared
    /// Whether a Nidus focus session is on: Later offers to wait for its end.
    @ObservedObject private var focus = NidusFocus.shared
    /// A plan's card: its summary, and Approve (Lab/PlanApproval.swift).
    @ObservedObject private var plans = PlanApprover.shared
    /// A question's card: what it asks, and Reply (Lab/QuestionReply.swift).
    @ObservedObject private var questions = QuestionReplier.shared
    /// A failure card's reason, and Copy (Lab/FailureReason.swift).
    @ObservedObject private var failures = FailureReasoner.shared
    @ObservedObject private var usagePause = UsagePauseModel.shared
    /// A plan's progress, a reviewer's findings, a note Claude sent
    /// (Lab/PanelInsights.swift).
    @ObservedObject private var insights: PanelInsights
    /// The Finished card's files and pictures (Lab/FinishedResults.swift).
    @ObservedObject private var finished: FinishedResults
    /// The closing gestures planned for this run's finishes (Lab/FinishingGestures.swift).
    private let gestures: FinishingGestures
    /// The shelf the Finished card's one figure is added to (Shelf/ShelfAccess.swift).
    @ObservedObject private var onShelf: ShelfAccess = .live
    /// Why the last Add to Shelf of a figure failed, by version, when it did.
    @State private var shelfProblems: [String: String] = [:]
    /// What a card offers and does (Lab/CardActions.swift), over the same model and states.
    private var actions: CardActions { CardActions(model: model, plans: plans, questions: questions) }
    /// Reports the window size the content wants, whenever it changes.
    let onFit: (CGSize) -> Void

    init(model: LabModel, hover: PanelHover, insights: PanelInsights = .shared, finished: FinishedResults = .shared,
         gestures: FinishingGestures = .shared, onFit: @escaping (CGSize) -> Void) {
        self.model = model
        self.hover = hover
        self.insights = insights
        self.finished = finished
        self.gestures = gestures
        self.onFit = onFit
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.showPanel) private var showWorking = true
    @AppStorage(SettingsKey.showCards) private var showCards = true
    @AppStorage(SettingsKey.showSpecimenCaption) private var showSpecimenCaption = false
    @AppStorage(SettingsKey.matchSpecimenToSession) private var matchSpecimen = true
    @AppStorage(SettingsKey.panelCorner) private var corner = PanelCorner.bottomRight
    @Environment(\.colorScheme) private var colorScheme
    @State private var entered = false
    /// The last thing shown, so the panel keeps its look while it fades out
    /// instead of collapsing as its content goes.
    @State private var held: Face?

    /// What the panel shows right now.
    private enum Face: Equatable {
        case working(SessionStatus, others: Int)
        case card(LabCard, count: Int)

        var isWorking: Bool {
            if case .working = self { true } else { false }
        }

        /// A question or a plan uses the full width for its text. Its compact
        /// status glyph doesn't follow specimen size. Faces with a well
        /// (working, finished, stopped with an error) grow and shrink with it.
        func width(well: CGFloat) -> CGFloat {
            switch self {
            case .working: 336 + (well - Theme.sceneSize)
            case .card(.needsInput, _): 360
            case .card: 360 + (well - Theme.sceneSize)
            }
        }

        /// Changes when the panel should move: a different card, a different
        /// number of cards or working sessions. Not on every clock tick or write.
        var motionKey: String {
            switch self {
            case .working(let session, let others): "working-\(session.id)-\(others)"
            case .card(let card, let count): "\(card.id)-\(count)"
            }
        }
    }

    private var current: Face? {
        if showCards, let card = model.cards.first { return .card(card, count: model.cards.count) }
        // A session still working goes on top of one a used-up limit holds.
        if showWorking, !model.workingHidden, let session = usagePause.head(of: model.working) {
            return .working(session, others: model.working.count - 1)
        }
        return nil
    }

    /// The scene well's side, from the size setting.
    private var wellSide: CGFloat { settings.size.points }

    var body: some View {
        Group {
            if let face = current ?? held {
                panel(face)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        .onChange(of: current, initial: true) { _, face in
            if let face { held = face }
            // The running session the panel shows is read for its progress.
            if case .working(let session, _)? = face {
                insights.showing([session], from: .panel)
            } else {
                insights.showing([], from: .panel)
            }
        }
        // A card that needs you has come to the top: VoiceOver says so.
        .onChange(of: showCards ? model.cards.first.flatMap(PanelSpeech.announcement(for:)) : nil, initial: true) { _, text in
            if let text { PanelAnnouncer.announce(text) }
        }
        .onDisappear { insights.showing([], from: .panel) }
        // The panel is never the key window, and a prominent button greys out
        // in one that is not; it is meant to look live.
        .environment(\.appearsActive, true)
    }

    // MARK: The panel

    private func panel(_ face: Face) -> some View {
        VStack(spacing: 3) {
            glass(face)
            if case .card(_, let count) = face, count > 1 {
                // The queue's edges, peeking out below the top card. Plain
                // shapes: the panel keeps its one glass shape.
                ForEach(1...min(count - 1, 2), id: \.self) { depth in
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: face.width(well: wellSide) - 28 * CGFloat(depth), height: 6)
                }
            }
        }
        .padding(Self.margin)
        .fixedSize()
        .animation(reduceMotion ? nil : Theme.spring, value: face.motionKey + (stackIsOpen(face) ? "-open" : ""))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onFit($0) }
        .scaleEffect(entered || reduceMotion ? 1 : 0.94, anchor: corner.anchor)
        .onAppear {
            withAnimation(reduceMotion ? nil : Theme.spring) { entered = true }
        }
    }

    private func glass(_ face: Face) -> some View {
        GlassEffectContainer {
            ZStack(alignment: .topLeading) {
                content(face)
                    .padding(Theme.panelPadding)
                    .frame(width: face.width(well: wellSide))
                if hover.isInside {
                    dismissButton(face)
                }
            }
            .modifier(PanelSurface(corner: Theme.panelCorner))
            .contentShape(.rect(cornerRadius: Theme.panelCorner))
            .onTapGesture { open(face) }
            .accessibilityAction(named: "Open") { open(face) }
            .accessibilityAction(named: "Dismiss") { dismiss(face) }
            .modifier(PlayingSpecimenMenu(active: face.isWorking && model.problem == nil, rotation: rotation(of: face)))
        }
    }

    /// The rotation the face plays: a session's own specimen, picked for its
    /// words when one fits (Lab/SessionSpecimen.swift), else what the user chose.
    private func rotation(of face: Face) -> Rotation {
        if case .working(let session, _) = face { return SessionSpecimen.of(session, matching: matchSpecimen).rotation }
        return settings.rotation
    }

    /// Whether the working panel is open into a row per session: two or more
    /// work, and the pointer is over it.
    private func stackIsOpen(_ face: Face) -> Bool {
        guard case .working(_, let others) = face, model.problem == nil else { return false }
        return PanelStack.expands(working: others + 1, hovering: hover.isInside)
    }

    private func open(_ face: Face) {
        switch face {
        case .working(let session, _): model.open(session)
        case .card(let card, _): model.open(card)
        }
    }

    private func dismiss(_ face: Face) {
        switch face {
        case .working: model.dismissWorking()
        case .card(let card, _): model.dismiss(card)
        }
    }

    /// A small glass × at the top left: dismisses the top card, or hides the
    /// working panel until the set of working sessions changes.
    private func dismissButton(_ face: Face) -> some View {
        Button {
            dismiss(face)
        } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .padding(6)
        .accessibilityLabel("Dismiss")
    }

    // MARK: Contents

    @ViewBuilder
    private func content(_ face: Face) -> some View {
        switch face {
        case .working(let session, let others):
            workingContent(session, others: others)
        case .card(let card, let count):
            // Each card is its own view. When the top card changes straight from one to another of a kind
            // (Finished to Finished), SwiftUI would keep the view: `.onDisappear { finished.forget }` would
            // never run for the first, and the plate's `settled` would stay true for the second.
            cardContent(card, count: count)
                .id(card.id)
        }
    }

    @ViewBuilder
    private func workingContent(_ session: SessionStatus, others: Int) -> some View {
        if model.problem != nil {
            // The last read failed: say so, rather than count on as if the
            // session were still known to be working.
            Row(side: wellSide, well: symbol("exclamationmark.triangle")) {
                caption("Not updating", trailing: others > 0 ? "+\(others) more" : nil)
                title(session.displayTitle)
                detail(model.staleSince.map { "Last checked at \($0.formatted(date: .omitted, time: .shortened))" }
                       ?? "Can't check right now")
            }
        } else if let pause = usagePause.pause(for: session.id) {
            // A used-up limit holds it: no specimen, since nothing is happening
            // in it, and when it starts again.
            Row(side: wellSide, well: symbol("pause.circle")) {
                caption("Paused · usage limit", trailing: others > 0 ? "+\(others) more" : nil)
                title(session.displayTitle)
                detail(pause.sentence())
            }
        } else if PanelStack.expands(working: others + 1, hovering: hover.isInside) {
            stackContent(session)
        } else {
            let specimen = SessionSpecimen.of(session, matching: matchSpecimen)
            let progress = insights.progress[session.id]
            VStack(alignment: .leading, spacing: 12) {
                Row(side: wellSide, well: WorkingGlyph(tint: colorScheme.sceneInk, rotation: specimen.rotation)) {
                    caption("Working", dot: true, trailing: others > 0 ? "+\(others) more" : nil)
                    title(session.displayTitle)
                    TurnClockText(prefix: session.projectName, since: session.startedAt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // Under the well, across the card: how far the plan has got,
                // and which specimen is playing and why.
                if progress != nil || showSpecimenCaption {
                    VStack(alignment: .leading, spacing: 6) {
                        if let progress { PanelProgressBlock(progress: progress) }
                        if showSpecimenCaption { specimenCaption(specimen) }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PanelSpeech.working(
                title: session.displayTitle, project: session.projectName, since: session.startedAt, others: others,
                progress: progress, specimen: showSpecimenCaption ? specimen.picked?.caption : nil))
            .accessibilityAction(named: "Show every session") { showEverySession() }
        }
    }

    /// The specimen that's playing: the reason it was picked for this
    /// session, or its name and a few words about it, following the rotation.
    @ViewBuilder
    private func specimenCaption(_ specimen: SessionSpecimen) -> some View {
        if let picked = specimen.picked {
            Text(verbatim: picked.caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            SpecimenCaptionLine(rotation: specimen.rotation)
        }
    }

    /// Two or more work and the pointer is over the panel: a row for each,
    /// which opens it, in place of the one and its "+N more".
    private func stackContent(_ head: SessionStatus) -> some View {
        let sessions = [head] + model.working.filter { $0.id != head.id }
        return VStack(alignment: .leading, spacing: 8) {
            caption("Working", dot: true, trailing: "\(sessions.count) sessions")
            PanelStackRows(sessions: sessions, tint: colorScheme.sceneInk, matching: matchSpecimen,
                           open: { model.open($0) }, showAll: showEverySession)
        }
    }

    /// The Dock's activity menu, under the pointer, without bringing Capsid forward.
    private func showEverySession() {
        ActivityMenu.shared.make().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @ViewBuilder
    private func cardContent(_ card: LabCard, count: Int) -> some View {
        let position = count > 1 ? "1 of \(count)" : nil
        switch card {
        case .needsInput(let session):
            let reason = session.waitingReason ?? .other
            // Only a plan's card has one, and only while the setting is on.
            let plan = reason == .plan ? plans.state(for: session.id) : nil
            // Any other wait's (a question, a permission request), under the same setting.
            let question = QuestionCardState.reads(reason) ? questions.cardState(for: session.id) : nil
            // What the card offers, from those states: the one rule the activity list's rows
            // read too (Lab/CardActions.swift).
            let offer = actions.offer(for: session)
            actionCard(session, heading: reason.sentence, position: position) {
                PlayedLoop(glyph: reason.glyph, tint: colorScheme.sceneInk)
            } content: {
                if let plan { planLines(plan, session: session) }
                if let question { questionLines(question, sessionID: session.id, offer: offer) }
                needsInputButtons(offer, card: card, session: session)
            }
            // One sentence, its buttons named actions.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PanelSpeech.asking(
                heading: reason.sentence, title: session.displayTitle, project: session.projectName,
                detail: [Self.spokenAsk(plan: plan, question: question), offer.problem, Self.spokenDone(offer)]
                    .compactMap { $0 }.joined(separator: ". ")))
            .accessibilityActions { needsInputActions(offer, card: card, session: session) }
        case .failed(let session):
            // Why it stopped, once it has been read; until then, or when
            // there is none, the card is as it always was.
            let reason = failures.reason(for: session.id)
            VStack(alignment: .leading, spacing: 12) {
                Row(side: wellSide, well: ContaminatedPlateWell(tint: colorScheme.sceneInk)) {
                    caption("Stopped with an error", style: Theme.clayText, weight: .semibold, trailing: position)
                    title(session.displayTitle)
                    detail(Self.ranFor(session))
                }
                if let reason { reasonLine(reason) }
                buttons(top: 0, size: .large) {
                    Button("Open") { model.open(card) }
                        .panelButton(prominent: true)
                    if reason != nil {
                        CopyReasonButton { failures.copy(session.id) }
                    }
                    Button("Dismiss") { model.dismiss(card) }
                        .panelButton()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PanelSpeech.failed(title: session.displayTitle, project: session.projectName,
                                                  duration: session.duration, reason: reason?.line))
            .accessibilityAction(named: "Copy") { _ = failures.copy(session.id) }
        case .finished(let session):
            finishedCard(session, card: card, position: position)
        case .web(let notification):
            // Claude Science's title is the caption; a notification with no
            // body has nothing under it, so its title takes the body's place.
            let hasBody = !notification.body.isEmpty
            Row(side: wellSide, well: symbol("bell")) {
                caption(hasBody ? notification.title : "Claude Science", trailing: position)
                title(hasBody ? notification.body : notification.title)
                buttons {
                    Button("Open") { model.open(card) }
                        .panelButton(prominent: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasBody ? "\(notification.title). \(notification.body)" : "Claude Science. \(notification.title)")
        case .notice(let notice) where notice.midRunNote != nil:
            noteCard(notice, card: card, position: position)
        case .notice(let notice):
            Row(side: wellSide, well: symbol(notice.symbol)) {
                caption(notice.caption, trailing: position)
                title(notice.title)
                if !notice.detail.isEmpty { detail(notice.detail) }
                if case .openSession = notice.action {
                    buttons {
                        Button("Open") { model.open(card) }
                            .panelButton(prominent: true)
                    }
                } else if case .installUpdate = notice.action {
                    buttons {
                        Button("Install\u{2026}") { model.open(card) }
                            .panelButton(prominent: true)
                    }
                } else if case .sinceYouLeft = notice.action {
                    // Since You Left: Show opens its sheet (SinceYouLeft/SinceYouLeftSheet.swift).
                    buttons {
                        Button("Show") { model.open(card) }
                            .panelButton(prominent: true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([notice.caption, notice.title, notice.detail].filter { !$0.isEmpty }.joined(separator: ". "))
            .accessibilityActions {
                if case .installUpdate = notice.action { Button("Install\u{2026}") { model.open(card) } }
                if case .sinceYouLeft = notice.action { Button("Show") { model.open(card) } }
            }
        case .saved(let url):
            Row(side: wellSide, well: symbol("arrow.down.circle")) {
                caption("Saved", trailing: position)
                title(url.lastPathComponent)
                buttons {
                    Button("Show in Finder") { model.open(card) }
                        .panelButton(prominent: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saved. \(url.lastPathComponent)")
            .accessibilityAction(named: "Show in Finder") { model.open(card) }
        }
    }

    /// What a question or plan card asks, in words, for VoiceOver.
    private static func spokenAsk(plan: PlanCardState?, question: QuestionCardState?) -> String? {
        switch plan {
        case .ready(let preview)?, .approving(let preview)?, .checking(let preview)?, .approved(let preview)?,
             .problem(_, let preview)?, .retry(_, let preview)?:
            return preview.summary
        default: break
        }
        switch question {
        case .ready(let ask)?: return ask.items.first?.question
        case .permission(let request)?: return RemotePermission.words(for: request).title
        default: return nil
        }
    }

    /// "Approved", "Sent": what a card says in place of its buttons once it went.
    private static func spokenDone(_ offer: CardOffer) -> String? {
        if case .done(let text) = offer.lead { return text }
        return nil
    }

    /// A needs-input card's buttons as VoiceOver's named actions, from what it
    /// offers (`CardOffer`), by the same calls as the buttons. Open is the
    /// whole panel's own named action, so it is not offered twice.
    @ViewBuilder
    private func needsInputActions(_ offer: CardOffer, card: LabCard, session: SessionStatus) -> some View {
        if case .button(let lead) = offer.lead, lead != .open, lead != .openInCapsid {
            Button(lead.title) { actions.perform(lead, for: session) }
        }
        if offer.hasDeny { Button(CardAction.deny.title) { actions.perform(.deny, for: session) } }
        if offer.canRequestChanges { Button(CardAction.requestChanges.title) { actions.perform(.requestChanges, for: session) } }
        Button("Later") { model.remind(card, .fiveMinutes) }
    }

    /// The first line of why a session stopped, as a paragraph under the
    /// card's head, 13 on 19 across its whole width, up to three lines; the
    /// tooltip shows more of it, and Copy all of it.
    private func reasonLine(_ reason: FailureReason) -> some View {
        Text(verbatim: reason.line)
            .font(.system(size: 13))
            .lineSpacing(Self.reasonLeading - Self.reasonNaturalLeading)
            .lineLimit(3)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .help(reason.tooltip)
    }

    /// The board's 13-point text on 19 points of line, and the 15.5 the
    /// system font gives 13 points by itself.
    static let reasonLeading: CGFloat = 19
    static let reasonNaturalLeading: CGFloat = 15.5

    /// "Example project · 7:58": the project, and how long it ran before it stopped.
    static func ranFor(_ session: SessionStatus) -> String {
        session.duration.map { "\(session.projectName) · \(ElapsedClock.format($0))" } ?? session.projectName
    }

    /// The Finished card (Lab/FinishedResults.swift): the plate that fills, the
    /// session's pictures and file count, what the reviewer found, and Results,
    /// Open and, when there is one figure, Add to Shelf (then On Shelf ✓);
    /// Keep with Data and Code… is VoiceOver's action and Results' own.
    private func finishedCard(_ session: SessionStatus, card: LabCard, position: String?) -> some View {
        let listing = finished.listing(for: session.id)
        let offer = FinishedOffer.of(listing)
        let files = FinishedCardText.files(listing)
        let reviewer = insights.reviewers[session.id]?.line
        var pictures: [ArtifactEntry] = []
        if case .loaded(let entries) = listing { pictures = FinishedResults.pictures(in: entries) }
        return VStack(alignment: .leading, spacing: 12) {
            Row(side: wellSide, well: FinishedWell(session: session, tint: colorScheme.sceneInk, gestures: gestures)) {
                caption("Finished", style: Theme.clayText, weight: .semibold, trailing: position)
                title(session.displayTitle)
                detail(FinishedCardText.meta(project: session.projectName, duration: session.duration))
            }
            if FinishedMediaRow.shows(pictures: pictures, files: files, reviewer: reviewer) {
                FinishedMediaRow(pictures: pictures, store: finished.thumbnails, files: files, reviewer: reviewer)
                    .padding(.horizontal, 4)
            }
            buttons(top: 0, size: .large) {
                if offer.lead == .results {
                    resultsButton(session).panelButton(prominent: true)
                    Button("Open") { model.open(card) }.panelButton()
                } else {
                    Button("Open") { model.open(card) }.panelButton(prominent: true)
                    if offer.hasResults { resultsButton(session).panelButton() }
                }
                if let entry = offer.keepable { shelfButton(entry, of: session) }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            if let entry = offer.keepable, let problem = shelfProblems[entry.version] {
                detail(problem).padding(.horizontal, 4)
            }
        }
        // Only the card on top is here, so only its files are read.
        .task(id: session.id) {
            insights.wantReviewers(for: session)
            await finished.load(session)
        }
        .onDisappear { finished.forget(session.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FinishedCardText.spoken(
            title: session.displayTitle, project: session.projectName, duration: session.duration,
            files: files, reviewer: reviewer))
        .accessibilityAction(named: "Results") { showResults(session) }
        .accessibilityAction(named: ShelfWords.add) { if let entry = offer.keepable { addToShelf(entry, of: session) } }
        .accessibilityAction(named: ShelfWords.keep) { if let entry = offer.keepable { keep(entry, of: session) } }
    }

    /// Add to Shelf, one click as in Results; "Adding…" while it is added, then On Shelf ✓, which shows the shelf.
    @ViewBuilder
    private func shelfButton(_ entry: ArtifactEntry, of session: SessionStatus) -> some View {
        switch ShelfMark(entry.version, in: onShelf) {
        case .off:
            Button(ShelfWords.add) { addToShelf(entry, of: session) }
                .panelButton()
                .help("Add this figure to your shelf, with what Claude said about it and where it came from")
        case .adding:
            Button(ShelfWords.adding) {}.panelButton().disabled(true)
        case .on:
            Button(ShelfWords.on) { if Demo.mode == nil { onShelf.show(nil) } }
                .panelButton()
                .help("Show the Shelf")
        }
    }

    private func addToShelf(_ entry: ArtifactEntry, of session: SessionStatus) {
        guard Demo.mode == nil, ShelfMark(entry.version, in: onShelf) == .off else { return }
        shelfProblems[entry.version] = nil
        Task { @MainActor in
            if case .failed(let sentence) = await onShelf.add(ShelfSource(session: session, entry: entry)) {
                shelfProblems[entry.version] = sentence
            }
        }
    }

    private func resultsButton(_ session: SessionStatus) -> some View {
        // The files it made, in Results, on this session.
        Button("Results") { showResults(session) }
            .help("Show the files this session made")
    }

    /// A demo reads and opens nothing.
    private func showResults(_ session: SessionStatus) {
        guard Demo.mode == nil else { return }
        ResultsWindowController.shared.show(focusing: session)
    }

    private func keep(_ entry: ArtifactEntry, of session: SessionStatus) {
        guard Demo.mode == nil else { return }
        KeepFromCardController.shared.show(KeepSubject(session: session, entry: entry))
    }

    /// A note Claude sent while it worked: quiet, timed, with Open.
    private func noteCard(_ notice: LabNotice, card: LabCard, position: String?) -> some View {
        let note = notice.midRunNote
        let text = note?.text ?? notice.title
        return Row(side: wellSide, well: symbol(notice.symbol)) {
            caption(notice.caption, trailing: position)
            Text(verbatim: text)
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            detail(notice.detail)
            buttons {
                Button("Open") { model.open(card) }
                    .panelButton()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PanelSpeech.note(text: text, detail: notice.detail))
    }

    /// The plan under the title: its summary in three lines, then its steps
    /// and feasibility, with the steps' titles a click away, or why it
    /// couldn't be approved here.
    @ViewBuilder
    private func planLines(_ plan: PlanCardState, session: SessionStatus) -> some View {
        switch plan {
        case .loading:
            detail("Loading the plan…")
                .padding(.top, 4)
        case .unavailable:
            EmptyView()
        case .ready(let preview):
            planSummary(preview.summary)
            stepsLine(preview)
            HStack(spacing: 10) {
                if let list = preview.stepList { stepsToggle(list, sessionID: session.id) }
                requestChangesLink(session)
            }
            .padding(.top, 2)
            if let list = preview.stepList, plans.isShowingSteps(session.id) { stepRows(list) }
        case .approving(let preview), .approved(let preview):
            planSummary(preview.summary)
            stepsLine(preview)
            if let list = preview.stepList { stepsDisclosure(list, sessionID: session.id) }
        case .checking(let preview):
            // The approval got no answer; the plan is being read to see whether it landed.
            planSummary(preview.summary)
            note(PlanApprover.Sentence.checking, tint: Theme.clayText)
            if let list = preview.stepList { stepsDisclosure(list, sessionID: session.id) }
        case .retry(let message, let preview):
            // Read again: it didn't land (or couldn't be told). Approve is offered again.
            planSummary(preview.summary)
            note(message, tint: Theme.clayText)
            HStack(spacing: 10) {
                if let list = preview.stepList { stepsToggle(list, sessionID: session.id) }
                requestChangesLink(session)
            }
            .padding(.top, 2)
            if let list = preview.stepList, plans.isShowingSteps(session.id) { stepRows(list) }
        case .problem(let message, let preview):
            planSummary(preview.summary)
            detail(message)
            requestChangesLink(session)
                .padding(.top, 2)
        }
    }

    /// "Request changes…": what to change in the plan, typed in the reply
    /// window (Lab/ReplyWindow.swift) and sent as the session's own composer
    /// would, so Claude revises it and it waits for approval again.
    private func requestChangesLink(_ session: SessionStatus) -> some View {
        Button {
            actions.perform(.requestChanges, for: session)
        } label: {
            Text(CardAction.requestChanges.title)
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(CardAction.requestChanges.help ?? "")
    }

    /// The question under the title: what it asks, in three lines, and how it
    /// is answered ("3 choices"), or that it's one to answer in Capsid. A
    /// permission request: what it wants, then what it is or why it can't be
    /// answered here, or how its answer went.
    @ViewBuilder
    private func questionLines(_ question: QuestionCardState, sessionID: String, offer: CardOffer) -> some View {
        switch question {
        case .loading:
            detail("Loading…")
                .padding(.top, 4)
        case .ready(let ask):
            planSummary(ask.items.first?.question ?? "")
            detail(QuestionCardState.shape(ask))
            // An answer that got no answer, being looked for in the session.
            if let problem = offer.problem { note(problem, tint: Theme.clayText) }
        case .permission(let request):
            let words = RemotePermission.words(for: request)
            let decision = RemotePermission.decideOnMac(request)
            planSummary(words.title)
            // How a send went (changed, failed, closed) in place of what the request is.
            if let problem = offer.problem {
                note(problem, tint: Theme.clayText)
            } else {
                if decision.canAllow || decision.canDeny, !words.detail.isEmpty {
                    note(words.detail)
                }
                if !decision.canAllow, let why = decision.why { note(why) }
            }
        case .unsupported:
            detail("Answer this one in Capsid")
                .padding(.top, 4)
        case .unavailable:
            EmptyView()
        }
    }

    /// A line or three of smaller text: what a request is, or why not here.
    private func note(_ text: String, tint: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    /// "6 steps · feasibility: high". The word "feasibility" is Claude's own
    /// estimate, which the tooltip says: the column has no room to.
    @ViewBuilder
    private func stepsLine(_ preview: PlanPreview) -> some View {
        if let line = preview.detail {
            if preview.confidence != nil {
                detail(line).help(PlanPreview.feasibilityHelp)
            } else {
                detail(line)
            }
        }
    }

    /// "Show steps" / "Hide steps", a small chevron button, and when open the
    /// first few step titles. Closed unless opened, for this card alone
    /// (`PlanApprover.stepsOpen`).
    @ViewBuilder
    private func stepsDisclosure(_ list: PlanStepList, sessionID: String) -> some View {
        stepsToggle(list, sessionID: sessionID)
            .padding(.top, 2)
        if plans.isShowingSteps(sessionID) {
            stepRows(list)
        }
    }

    private func stepsToggle(_ list: PlanStepList, sessionID: String) -> some View {
        let isOpen = plans.isShowingSteps(sessionID)
        return Button {
            withAnimation(reduceMotion ? nil : Theme.spring) { plans.toggleSteps(sessionID) }
        } label: {
            HStack(spacing: 3) {
                Text(isOpen ? "Hide steps" : "Show steps")
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The titles as a compact numbered list, one line each and cut at the
    /// end, then "and N more…". The list is capped (`PlanStepList.limit`), so
    /// the card stays a size a laptop screen holds.
    private func stepRows(_ list: PlanStepList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.shown.enumerated()), id: \.offset) { index, title in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 14, alignment: .trailing)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityElement(children: .combine)
            }
            if let more = list.moreLine {
                Text(more)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
            }
        }
        .font(.system(size: 11))
        .padding(.top, 2)
    }

    private func planSummary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .lineLimit(3)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    /// The card's buttons, from what it offers (`CardOffer`): the primary action
    /// (Approve, Reply, Review, Allow Once, else Open), then Open as plain glass
    /// where there is room, Deny, and Later. An answer on its way is a spinner;
    /// one sent is "Sent ✓", "Approved ✓", "Allowed once ✓" or "Denied ✓" until the
    /// card goes. Reply and Review open the reply window (Lab/ReplyWindow.swift):
    /// the panel itself never takes the keyboard.
    @ViewBuilder
    private func needsInputButtons(_ offer: CardOffer, card: LabCard, session: SessionStatus) -> some View {
        switch offer.lead {
        case .done(let text):
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "checkmark")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.clayText)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        case .sending(let label):
            buttons {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 64)
                    .accessibilityLabel(label)
                if offer.hasOpen {
                    Button("Open") { model.open(card) }
                        .panelButton()
                }
                later(card)
            }
        case .button(let lead):
            buttons {
                switch lead {
                case .open, .openInCapsid:
                    Button(lead.title) { model.open(card) }
                        .panelButton(prominent: true)
                default:
                    Button(lead.title) { actions.perform(lead, for: session) }
                        .panelButton(prominent: true)
                        .help(lead.help ?? "")
                }
                if offer.hasOpen {
                    Button("Open") { model.open(card) }
                        .panelButton()
                }
                if offer.hasDeny {
                    Button(CardAction.deny.title) { actions.perform(.deny, for: session) }
                        .panelButton()
                        .help(CardAction.deny.help ?? "")
                }
                later(card, withOpen: offer.laterHasOpen)
            }
        }
    }

    /// Later, a native split pull-down: a click on the title is the five
    /// minute reminder, the arrow offers the others and Dismiss, which is for
    /// good, as the × is.
    private func later(_ card: LabCard, withOpen: Bool = false) -> some View {
        Menu("Later") {
            if withOpen {
                // Where the row has no room for Open of its own.
                Button("Open in Capsid") { model.open(card) }
            }
            if let session = card.session {
                // The reader beside the work (Reference/ReferenceWindow.swift);
                // the card stays.
                Button("Open as Reference") { ReferenceWindowController.shared.show(session) }
            }
            if withOpen || card.session != nil {
                Divider()
            }
            Button("In 5 Minutes") { model.remind(card, .fiveMinutes) }
            Button("In 15 Minutes") { model.remind(card, .fifteenMinutes) }
            if focus.focusing {
                Button("After My Focus Session") { model.remind(card, .afterFocus) }
            }
            Divider()
            Button("Dismiss") { model.dismiss(card) }
        } primaryAction: {
            model.remind(card, .fiveMinutes)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help("Remind me in 5 minutes")
    }

    // MARK: Parts

    /// Decisions get the card's whole text width. The status stays visible
    /// beside a small glyph; the large specimen well belongs to the working
    /// face, where it is the content rather than competing with a question.
    private func actionCard<Glyph: View, Content: View>(
        _ session: SessionStatus, heading: String, position: String?,
        @ViewBuilder glyph: () -> Glyph, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                glyph()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                caption(heading, style: Theme.clayText, weight: .semibold, trailing: position)
            }
            VStack(alignment: .leading, spacing: 3) {
                title(session.displayTitle)
                detail(session.projectName)
            }
            VStack(alignment: .leading, spacing: 3, content: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The scene well on the left, `side` points square, and the text column
    /// on the right.
    private struct Row<Well: View, Column: View>: View {
        let side: CGFloat
        let well: Well
        @ViewBuilder let column: Column

        init(side: CGFloat, well: Well, @ViewBuilder column: () -> Column) {
            self.side = side
            self.well = well
            self.column = column()
        }

        var body: some View {
            HStack(spacing: 14) {
                well
                    .frame(width: side, height: side)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(.rect(cornerRadius: side * 0.2))
                VStack(alignment: .leading, spacing: 3) {
                    column
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 30 * wellSide / Theme.sceneSize, weight: .light))
            .foregroundStyle(.secondary)
    }

    /// The 11 pt caption row: an optional live dot, the text, and at the end
    /// what else is queued or working.
    /// `showsEvery` makes the trailing text ("+2 more") a button that lists
    /// every session, the Dock's menu, under the pointer: the panel can't
    /// show them all, and the app needn't come to the front to.
    private func caption(_ text: String, dot: Bool = false, style: some ShapeStyle = .secondary,
                         weight: Font.Weight = .semibold, trailing: String? = nil, showsEvery: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dot {
                Circle().fill(Theme.clay).frame(width: 8, height: 8)
            }
            Text(text)
                .foregroundStyle(style)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            if let trailing, showsEvery {
                Button {
                    ActivityMenu.shared.make().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                } label: {
                    HStack(spacing: 2) {
                        Text(trailing)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Show every session")
            } else if let trailing {
                Text(trailing)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 12, weight: weight))
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// A row of buttons. The cards that ask keep them small; the three
    /// moments with a well (working, finished, stopped) set them as the
    /// board does, 28 points tall in 13-point words.
    private func buttons<Content: View>(top: CGFloat = 8, size: ControlSize = .small,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .controlSize(size)
            .font(size == .large ? .system(size: 13) : nil)
            .padding(.top, top)
    }

    /// Copy, on a failure card that has a reason: it says "Copied" for a moment.
    private struct CopyReasonButton: View {
        /// Puts the whole reason on the pasteboard; false if there was none.
        let copy: () -> Bool
        @State private var copied = false

        var body: some View {
            Button(copied ? "Copied" : "Copy") {
                if copy() { copied = true }
            }
            .panelButton()
            .help("Copy the whole error")
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }
}
