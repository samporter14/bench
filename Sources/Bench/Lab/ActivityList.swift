// ActivityList.swift — every session at once (DESIGN.md, Activity list): what
// needs you, what works and what happened lately, each a row that opens its
// session. The toolbar capsule shows it in a popover and the Dock icon's menu
// lists the same; both read LabModel, so nothing else polls.
import AppKit
import SwiftUI

struct ActivityList: View {
    let close: () -> Void
    @ObservedObject private var model = LabModel.shared
    @ObservedObject private var usagePause = UsagePauseModel.shared
    /// What a card has read of a plan or a question: a row offers what its card would.
    @ObservedObject private var plans = PlanApprover.shared
    @ObservedObject private var questions = QuestionReplier.shared
    /// A working session's plan progress, under its project (Lab/PanelInsights.swift).
    @ObservedObject private var insights = PanelInsights.shared
    @Environment(\.colorScheme) private var colorScheme

    /// What a card offers and does (Lab/CardActions.swift), over the same model and states.
    private var cardActions: CardActions { CardActions(model: model, plans: plans, questions: questions) }

    /// Whether "N more" under Needs you has been pressed: all of its rows show.
    @State private var showsAllNeeds = false

    var body: some View {
        let height = ActivitySizing.currentHeightLimit()
        let needs = NeedsYou(model: model)
        // Working keeps its room: a long Needs you shows what fits, and the rest wait behind "N more".
        let (shown, hidden) = needs.capped(
            to: showsAllNeeds ? nil : ActivitySizing.needsRowLimit(height: height, workingRows: model.working.count))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let problem = model.problem {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not updating: \(problem.label)")
                            if let since = model.staleSince {
                                Text("Last checked at \(since.formatted(date: .omitted, time: .shortened))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }
                if !needs.isEmpty {
                    // What asks first, the longest wait on top; then what stopped with an
                    // error; then, under their own title, what is put off with Later.
                    VStack(alignment: .leading, spacing: 2) {
                        needsYouTitle(hasAsks: !needs.asks.isEmpty)
                        ForEach(shown.asks) { askRow($0) }
                        ForEach(shown.failed) { session in
                            row(session, line: "Stopped with an error", accent: true) {
                                symbol("exclamationmark.triangle")
                            }
                        }
                        if !shown.later.isEmpty {
                            Text("Later")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                                .padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(shown.later) { snoozedRow($0) }
                        }
                        if hidden > 0 { moreRow(hidden) }
                    }
                }
                if !model.working.isEmpty {
                    // A session a used-up limit holds: no specimen and no clock, but
                    // when it resumes. The section says so when it holds them all.
                    section(usagePause.holdsAll(model.working) ? "Paused · usage limit" : "Working") {
                        ForEach(model.working) { session in
                            row(session, line: nil, accent: false, progress: insights.progress[session.id]) {
                                if usagePause.pause(for: session.id) != nil {
                                    Image(systemName: "pause.circle").foregroundStyle(.secondary)
                                } else {
                                    WorkingGlyph(tint: colorScheme.sceneInk, rotation: SceneSettings.shared.rotation)
                                }
                            } trailing: {
                                if let pause = usagePause.pause(for: session.id) {
                                    Text(pause.sentence())
                                        .foregroundStyle(.secondary)
                                } else if let since = session.startedAt {
                                    TimelineView(.periodic(from: since, by: 1)) { context in
                                        Text(ElapsedClock.format(context.date.timeIntervalSince(since)))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if !model.recent.isEmpty {
                    section("Recent") {
                        ForEach(model.recent) { event in
                            recentRow(event)
                        }
                    }
                }
                // Until something happens while Bench is open, the sessions
                // active last, as the Dock menu lists them.
                if model.recent.isEmpty, !model.latest.isEmpty {
                    section("Latest") {
                        ForEach(model.latest) { session in
                            row(session, line: nil, accent: false) {
                                symbol("clock")
                            }
                        }
                    }
                }
                if needs.isEmpty, model.working.isEmpty, model.recent.isEmpty, model.latest.isEmpty,
                   model.problem == nil {
                    Text("Nothing yet. Sessions show up here while they work, and what they did stays under Recent.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .frame(width: ActivitySizing.width)
        .frame(maxHeight: height)
        .fixedSize(horizontal: false, vertical: true)
        // A list too tall for the screen scrolls: a soft edge says there is more below.
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // A popover that nothing has made key draws a prominent button dimmed (as the
        // panel's, which never is key, would): the row's buttons are meant to look live.
        .environment(\.appearsActive, true)
        // What each shown ask's card would offer is read as the list opens (once per card:
        // a card on top has it already), so a row's buttons are there when the pointer is.
        .onAppear { shown.asks.forEach(cardActions.prepare) }
        // The working sessions the list shows are read for their progress, while it is open.
        .onAppear { insights.showing(model.working, from: .list) }
        .onChange(of: model.working) { _, working in insights.showing(working, from: .list) }
        .onDisappear { insights.showing([], from: .list) }
    }

    // MARK: Parts

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .padding(.leading, 6)
                .padding(.bottom, 2)
            content()
        }
    }

    /// Needs you's title, and at its end the way to step through the asks:
    /// Next Waiting Session and its keys. A press does what the menu item does.
    private func needsYouTitle(hasAsks: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Needs you")
                .font(.headline)
            Spacer(minLength: 8)
            if hasAsks {
                Button {
                    NextWaiting.shared.openNext()
                    close()
                } label: {
                    HStack(spacing: 5) {
                        Text(NextWaiting.title)
                        Text(NextWaiting.keysHint)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open the session that has waited longest, then the next. Option-Command-Down Arrow.")
                .accessibilityLabel(NextWaiting.title)
                .accessibilityHint("Opens the session that has waited longest, then the next")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.bottom, 2)
    }

    private func row<Glyph: View>(_ session: SessionStatus, line: String?, accent: Bool,
                                  @ViewBuilder glyph: () -> Glyph) -> some View {
        row(session, line: line, accent: accent, glyph: glyph) { EmptyView() }
    }

    /// Open as Reference, in every session row's context menu: the reader
    /// beside the work (Reference/ReferenceWindow.swift). It leaves the
    /// session's cards and reminder as they are.
    private func referenceAction(_ session: SessionStatus) -> RowAction {
        RowAction(title: "Open as Reference", help: nil, prominent: false) {
            close()
            ReferenceWindowController.shared.show(session)
        }
    }

    private func row<Glyph: View, Trailing: View>(_ session: SessionStatus, line: String?, accent: Bool,
                                                  note: String? = nil, progress: PlanProgress? = nil,
                                                  actions: [RowAction] = [],
                                                  engaged: @escaping () -> Void = {}, showsActions: Bool = false,
                                                  @ViewBuilder glyph: () -> Glyph,
                                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        ActivityRow(action: {
            model.open(session)
            close()
        }, actions: actions, menuActions: [referenceAction(session)], engaged: engaged, showsActions: showsActions) {
            HStack(spacing: 10) {
                glyph()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    if let line {
                        Text(line)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent ? AnyShapeStyle(Theme.clayText) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                    Text(session.displayTitle)
                        .lineLimit(1)
                    Text(session.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // How far its plan has got: the card's line, and a hairline of a bar.
                    if let progress {
                        Text(verbatim: progress.line)
                            .font(.caption)
                            .lineLimit(1)
                        PanelProgressBar(fraction: progress.fraction, height: 2)
                            .padding(.top, 2)
                    }
                    // Why a send didn't go, as the card says it.
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.clayText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
        }
        .accessibilityLabel([line, session.displayTitle, session.projectName, progress?.line, note].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the session")
    }

    /// A session that waits for you now. On hover or keyboard focus its row offers what
    /// its card would (`CardOffer`: Reply…, Approve, Request changes…, Allow Once, Deny,
    /// Review…), by the card's own calls (`CardActions`); sending shows a spinner and a
    /// send that went its line, as on the card. A session whose card isn't in the queue
    /// (put off, or dismissed) has no state to offer from, and its row only opens it.
    private func askRow(_ session: SessionStatus) -> some View {
        let reason = session.waitingReason ?? .other
        let offer = cardActions.offer(for: session)
        let actions = offer.rowActions.map { action in
            RowAction(title: action.rowTitle, help: action.help, prominent: action.isPrimary) {
                perform(action, for: session)
            }
        }
        return row(session, line: reason.sentence, accent: true, note: offer.problem, actions: actions,
                   engaged: { cardActions.prepare(session) },
                   showsActions: Demo.showsActions(for: session)) {
            PlayedLoop(glyph: reason.glyph, tint: colorScheme.sceneInk)
        } trailing: {
            switch offer.lead {
            case .sending(let label):
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(label)
            case .done(let text):
                HStack(spacing: 4) {
                    Text(text)
                    Image(systemName: "checkmark")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.clayText)
                .accessibilityElement(children: .combine)
            case .button:
                EmptyView()
            }
        }
    }

    /// What a row's button does. Those that open the reply window close the list first,
    /// as that window opens beside the panel; Approve, Allow Once and Deny leave it open,
    /// so the row shows how the send goes.
    private func perform(_ action: CardAction, for session: SessionStatus) {
        if action.opensWindow { close() }
        cardActions.perform(action, for: session)
    }

    /// "3 more" at the end of a long Needs you: a press shows the rest.
    private func moreRow(_ count: Int) -> some View {
        ActivityRow(action: { showsAllNeeds = true }) {
            HStack(spacing: 4) {
                Text("\(count) more")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 36)
        }
        .accessibilityLabel("\(count) more that need you")
        .accessibilityHint("Shows them")
    }

    /// A waiting session whose card is put off with Later: the reminder in
    /// place of the reason, a clock on its glyph, and Show Now and Cancel
    /// Reminder as buttons on the row and in its context menu. Clicking the
    /// row still opens the session, which clears the reminder.
    private func snoozedRow(_ snoozed: SnoozedReminder) -> some View {
        let session = snoozed.session
        return row(session, line: Self.line(for: snoozed), accent: false) {
            PlayedLoop(glyph: (session.waitingReason ?? .other).glyph, tint: colorScheme.sceneInk)
                .opacity(0.55)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(1.5)
                        .background(.regularMaterial, in: .circle)
                        .offset(x: 3, y: 3)
                }
        } trailing: {
            // Room for the buttons below, which sit over the row so that
            // they don't open the session.
            Color.clear.frame(width: 44, height: 1)
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                rowButton("Show Now", symbol: "bell") { model.showNow(session.id) }
                rowButton("Cancel Reminder", symbol: "bell.slash") { model.cancelReminder(session.id) }
            }
            .padding(.trailing, 6)
        }
        .contextMenu {
            Button("Show Now") { model.showNow(session.id) }
            Button("Cancel Reminder") { model.cancelReminder(session.id) }
        }
    }

    private func rowButton(_ title: String, symbol name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func recentRow(_ event: LabEvent) -> some View {
        let when = event.at.formatted(.relative(presentation: .named))
        switch event.kind {
        case .saved(let url):
            let exists = FileManager.default.fileExists(atPath: url.path)
            ActivityRow(action: {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                close()
            }) {
                recentLabel(symbol: "arrow.down.circle", line: "Saved", title: url.lastPathComponent,
                            detail: exists ? when : "\(when) · no longer there")
            }
            .disabled(!exists)
            .accessibilityLabel("Saved \(url.lastPathComponent), \(when)")
        default:
            if let session = event.session {
                ActivityRow(action: {
                    model.open(session)
                    close()
                }, menuActions: [referenceAction(session)]) {
                    recentLabel(symbol: Self.symbol(for: event.kind), line: Self.line(for: event.kind),
                                title: session.displayTitle, detail: "\(session.projectName) · \(when)")
                }
                .accessibilityLabel("\(Self.line(for: event.kind)), \(session.displayTitle), \(when)")
                .accessibilityHint("Opens the session")
            }
        }
    }

    private func recentLabel(symbol name: String, line: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            symbol(name)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(line)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
    }

    /// Past tense: these are what happened, not what waits now (that is
    /// Needs you).
    static func line(for kind: LabEvent.Kind) -> String {
        switch kind {
        case .needsInput(let reason):
            switch reason ?? .other {
            case .plan: "Had a plan for you to review"
            case .web, .files, .delete, .tool, .license: "Asked for your permission"
            default: "Asked you a question"
            }
        case .failed: "Stopped with an error"
        case .finished: "Finished"
        case .saved: "Saved"
        }
    }

    /// What a put-off session's row says in place of its reason: when the
    /// reminder comes, or that it waits for the focus session.
    static func line(for reminder: SnoozedReminder) -> String {
        guard let due = reminder.due else { return "Reminds you after your focus session" }
        return "Reminds you at \(due.formatted(date: .omitted, time: .shortened))"
    }

    static func symbol(for kind: LabEvent.Kind) -> String {
        switch kind {
        case .needsInput: "questionmark.bubble"
        case .failed: "exclamationmark.triangle"
        case .finished: "checkmark.circle"
        case .saved: "arrow.down.circle"
        }
    }
}

/// One of the answers a row offers on hover: its title and tooltip, and what it does.
private struct RowAction: Identifiable {
    let title: String
    let help: String?
    /// The one the card makes its primary: in the clay. The others are plain.
    let prominent: Bool
    let perform: () -> Void

    var id: String { title }
}

/// A row that highlights under the pointer, as a menu's items do, and opens
/// on click or Return. A row with `actions` also shows them, over its right
/// end, while the pointer or the keyboard focus is on it, and offers them in
/// its context menu and to VoiceOver, so they are there without hovering.
private struct ActivityRow<Label: View>: View {
    let action: () -> Void
    var actions: [RowAction] = []
    /// Offered in the context menu and to VoiceOver only, never as a button on the row.
    var menuActions: [RowAction] = []
    /// The pointer or the focus came to the row: a chance to read what its actions need.
    var engaged: () -> Void = {}
    /// Shows the actions as if the pointer were there (a demo's capture).
    var showsActions = false
    @ViewBuilder let label: Label
    @State private var hovering = false
    @State private var actionsWidth: CGFloat = 0
    @FocusState private var focus: Focus?
    @Environment(\.isEnabled) private var isEnabled

    private enum Focus: Hashable {
        case row
        case action(String)
    }

    private var offersActions: Bool {
        !actions.isEmpty && (hovering || focus != nil || showsActions)
    }

    var body: some View {
        // The buttons are the row's siblings, not inside its button, and the pointer's
        // tracking covers both, so moving onto them leaves the row hovered.
        ZStack(alignment: .trailing) {
            Button(action: action) {
                label
                    // The text gives way to the buttons rather than going under them.
                    .padding(.trailing, offersActions ? actionsWidth + 6 : 0)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(highlighted ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .focused($focus, equals: .row)
            if offersActions {
                buttons
                    .padding(.trailing, 6)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { inside in
            hovering = inside
            if inside { engaged() }
        }
        .onChange(of: focus) { _, now in
            if now != nil { engaged() }
        }
        .modifier(RowActionsMenu(actions: actions + menuActions))
    }

    private var highlighted: Bool {
        (hovering || showsActions) && isEnabled
    }

    /// A small column at the row's right end: the answer the card would make its primary
    /// in the clay, the rest plain, all as wide as the widest. A column, so the row's own
    /// lines keep most of their width.
    private var buttons: some View {
        VStack(spacing: 3) {
            ForEach(actions) { item in
                if item.prominent {
                    Button(action: item.perform) { Text(item.title).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                        .help(item.help ?? "")
                        .focused($focus, equals: .action(item.id))
                } else {
                    Button(action: item.perform) { Text(item.title).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .help(item.help ?? "")
                        .focused($focus, equals: .action(item.id))
                }
            }
        }
        .controlSize(.small)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
    }
}

/// The same actions in a row's context menu and as VoiceOver's actions, for a row that has any.
private struct RowActionsMenu: ViewModifier {
    let actions: [RowAction]

    @ViewBuilder
    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content
                .contextMenu {
                    ForEach(actions) { item in
                        Button(item.title, action: item.perform)
                    }
                }
                .accessibilityActions {
                    ForEach(actions) { item in
                        Button(item.title, action: item.perform)
                    }
                }
        }
    }
}
