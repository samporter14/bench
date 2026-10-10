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
/// seconds; the prefix alone when the turn's start is not known.
struct TurnClockText: View {
    let prefix: String
    let since: Date?

    var body: some View {
        if let since {
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("\(prefix) · \(ElapsedClock.format(context.date.timeIntervalSince(since)))")
                    .monospacedDigit()
            }
        } else {
            Text(prefix)
        }
    }
}

/// "Kinesin · A motor protein on a microtubule": the specimen that's playing,
/// on one quiet line. It follows the rotation as the panel's well does, by the
/// clock, and ticks only when the rotation moves on. One line, cut at its end,
/// so the panel keeps its size however long a caption is. Under Reduce Motion
/// the well is a still flask, so the line names that.
struct SpecimenCaptionLine: View {
    let rotation: Rotation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            line(WorkingGlyph.still)
        } else {
            TimelineView(SceneBoundarySchedule(rotation: rotation)) { timeline in
                line(rotation.scenes[rotation.scene(at: timeline.date.timeIntervalSinceReferenceDate).index])
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
    /// Reports the window size the content wants, whenever it changes.
    let onFit: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.showPanel) private var showWorking = true
    @AppStorage(SettingsKey.showCards) private var showCards = true
    @AppStorage(SettingsKey.showSpecimenCaption) private var showSpecimenCaption = false
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

        /// The panel grows and shrinks with the scene well: 336 or 360 at the
        /// default 88 pt, plus however much larger or smaller the well is.
        func width(well: CGFloat) -> CGFloat {
            let base: CGFloat = switch self {
            case .working: 336
            case .card: 360
            }
            return base + (well - Theme.sceneSize)
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
        if showWorking, !model.workingHidden, let session = model.working.first {
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
        }
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
        .animation(reduceMotion ? nil : Theme.spring, value: face.motionKey)
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
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.panelCorner))
            .contentShape(.rect(cornerRadius: Theme.panelCorner))
            .onTapGesture { open(face) }
            .accessibilityAction(named: "Open") { open(face) }
            .modifier(PlayingSpecimenMenu(active: face.isWorking && model.problem == nil, rotation: settings.rotation))
        }
    }

    private func open(_ face: Face) {
        switch face {
        case .working(let session, _): model.open(session)
        case .card(let card, _): model.open(card)
        }
    }

    /// A small glass × at the top left: dismisses the top card, or hides the
    /// working panel until the set of working sessions changes.
    private func dismissButton(_ face: Face) -> some View {
        Button {
            switch face {
            case .working: model.dismissWorking()
            case .card(let card, _): model.dismiss(card)
            }
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
            cardContent(card, count: count)
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
        } else {
            Row(side: wellSide, well: WorkingGlyph(tint: colorScheme.sceneInk, rotation: settings.rotation)) {
                caption("Working", dot: true, trailing: others > 0 ? "+\(others) more" : nil, showsEvery: true)
                title(session.displayTitle)
                TurnClockText(prefix: session.projectName, since: session.startedAt)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showSpecimenCaption {
                    SpecimenCaptionLine(rotation: settings.rotation)
                }
            }
        }
    }

    @ViewBuilder
    private func cardContent(_ card: LabCard, count: Int) -> some View {
        let position = count > 1 ? "1 of \(count)" : nil
        switch card {
        case .needsInput(let session):
            let reason = session.waitingReason ?? .other
            // Only a plan's card has one, and only while the setting is on.
            let plan = reason == .plan ? plans.state(for: session.id) : nil
            Row(side: wellSide, well: PlayedLoop(glyph: reason.glyph, tint: colorScheme.sceneInk)) {
                caption(reason.sentence, style: Theme.clay, weight: .semibold, trailing: position)
                title(session.displayTitle)
                detail(session.projectName)
                if let plan { planLines(plan, sessionID: session.id) }
                needsInputActions(card, session: session, plan: plan)
            }
        case .failed(let session):
            Row(side: wellSide, well: symbol("exclamationmark.triangle")) {
                caption("Stopped with an error", style: Theme.clay, weight: .semibold, trailing: position)
                title(session.displayTitle)
                detail(session.projectName)
                buttons {
                    Button("Open") { model.open(card) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.clay)
                    Button("Dismiss") { model.dismiss(card) }
                        .buttonStyle(.glass)
                }
            }
        case .finished(let session):
            Row(side: wellSide, well: finishedFlask) {
                caption("Finished", trailing: position)
                title(session.displayTitle)
                detail(Self.summary(of: session))
                buttons {
                    Button("Open") { model.open(card) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.clay)
                }
            }
        case .web(let notification):
            // Claude Science's title is the caption; a notification with no
            // body has nothing under it, so its title takes the body's place.
            let hasBody = !notification.body.isEmpty
            Row(side: wellSide, well: symbol("bell")) {
                caption(hasBody ? notification.title : "Claude Science", trailing: position)
                title(hasBody ? notification.body : notification.title)
                buttons {
                    Button("Open") { model.open(card) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.clay)
                }
            }
        case .notice(let notice):
            Row(side: wellSide, well: symbol(notice.symbol)) {
                caption(notice.caption, trailing: position)
                title(notice.title)
                if !notice.detail.isEmpty { detail(notice.detail) }
                if case .openSession = notice.action {
                    buttons {
                        Button("Open") { model.open(card) }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.clay)
                    }
                }
            }
        case .saved(let url):
            Row(side: wellSide, well: symbol("arrow.down.circle")) {
                caption("Saved", trailing: position)
                title(url.lastPathComponent)
                buttons {
                    Button("Show in Finder") { model.open(card) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.clay)
                }
            }
        }
    }

    /// The plan under the title: its summary in two lines, then its steps
    /// and feasibility, with the steps' titles a click away, or why it
    /// couldn't be approved here.
    @ViewBuilder
    private func planLines(_ plan: PlanCardState, sessionID: String) -> some View {
        switch plan {
        case .loading:
            detail("Loading the plan…")
                .padding(.top, 4)
        case .unavailable:
            EmptyView()
        case .ready(let preview), .approving(let preview), .approved(let preview):
            planSummary(preview.summary)
            stepsLine(preview)
            if let list = preview.stepList { stepsDisclosure(list, sessionID: sessionID) }
        case .problem(let message, let preview):
            planSummary(preview.summary)
            detail(message)
        }
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
        let isOpen = plans.isShowingSteps(sessionID)
        Button {
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
        .padding(.top, 2)
        if isOpen {
            stepRows(list)
        }
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
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    /// Open and Later, as on every needs-input card. A plan that is ready
    /// adds Approve in front, the primary action, and Open steps back to
    /// plain glass. Pressed, Approve becomes a spinner; approved, the row is
    /// "Approved ✓" until the card goes.
    @ViewBuilder
    private func needsInputActions(_ card: LabCard, session: SessionStatus, plan: PlanCardState?) -> some View {
        switch plan {
        case .approved?:
            HStack(spacing: 4) {
                Text("Approved")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.clay)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        case .ready?:
            buttons {
                Button("Approve") { plans.approve(session.id) }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.clay)
                    .help("Approve this plan. Bench checks it's still the same plan first.")
                Button("Open") { model.open(card) }
                    .buttonStyle(.glass)
                later(card)
            }
        case .approving?:
            buttons {
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 64)
                    .accessibilityLabel("Approving")
                Button("Open") { model.open(card) }
                    .buttonStyle(.glass)
                later(card)
            }
        default:
            buttons {
                Button("Open") { model.open(card) }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.clay)
                later(card)
            }
        }
    }

    /// Later, a native split pull-down: a click on the title is the five
    /// minute reminder, the arrow offers the others and Dismiss, which is for
    /// good, as the × is.
    private func later(_ card: LabCard) -> some View {
        Menu("Later") {
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
                    .clipShape(.rect(cornerRadius: Theme.panelCorner - Theme.panelPadding))
                VStack(alignment: .leading, spacing: 3) {
                    column
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The finished flask's settled still: `elapsed` far past its animation.
    private var finishedFlask: some View {
        Canvas { context, size in
            FinishGlyph.draw(in: &context, size: size, elapsed: 10, tint: colorScheme.sceneInk)
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
                         weight: Font.Weight = .medium, trailing: String? = nil, showsEvery: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(Theme.clay).frame(width: 6, height: 6)
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
        .font(.system(size: 11, weight: weight))
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

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .controlSize(.small)
            .padding(.top, 8)
    }

    /// "12 min · 1.2M tokens": what the turn took, when known.
    private static func summary(of session: SessionStatus) -> String {
        let parts = [
            session.duration.map(spoken),
            session.tokens.flatMap { $0 > 0 ? ActivityMetric.tokens.describe($0) : nil },
        ].compactMap { $0 }
        return parts.isEmpty ? session.projectName : parts.joined(separator: " · ")
    }

    /// Whole minutes and hours, but seconds under a minute, which would
    /// otherwise read "0 min".
    private static func spoken(_ duration: TimeInterval) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = duration < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(max(0, duration)).formatted(
            .units(allowed: units, width: .abbreviated, maximumUnitCount: 2))
    }
}
