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

struct LabPanelView: View {
    /// Clear space round the glass, so its own shadow and highlights are not
    /// cut off at the window's edge. The controller places the window so the
    /// glass, not the window, sits `Theme.panelInset` from the corner.
    static let margin: CGFloat = 16

    @ObservedObject var model: LabModel
    @ObservedObject var hover: PanelHover
    /// The chosen size and rotation: a change resizes the live panel.
    @ObservedObject private var settings = SceneSettings.shared
    /// Reports the window size the content wants, whenever it changes.
    let onFit: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKey.showPanel) private var showWorking = true
    @AppStorage(SettingsKey.showCards) private var showCards = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var entered = false
    /// The last thing shown, so the panel keeps its look while it fades out
    /// instead of collapsing as its content goes.
    @State private var held: Face?

    /// What the panel shows right now.
    private enum Face: Equatable {
        case working(SessionStatus, others: Int)
        case card(LabCard, count: Int)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
        .scaleEffect(entered || reduceMotion ? 1 : 0.94, anchor: .bottomTrailing)
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
                caption("Working", dot: true, trailing: others > 0 ? "+\(others) more" : nil)
                title(session.displayTitle)
                TurnClockText(prefix: session.projectName, since: session.startedAt)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func cardContent(_ card: LabCard, count: Int) -> some View {
        let position = count > 1 ? "1 of \(count)" : nil
        switch card {
        case .needsInput(let session):
            let reason = session.waitingReason ?? .other
            Row(side: wellSide, well: PlayedLoop(glyph: reason.glyph, tint: colorScheme.sceneInk)) {
                caption(reason.sentence, style: Theme.clay, weight: .semibold, trailing: position)
                title(session.displayTitle)
                detail(session.projectName)
                buttons {
                    Button("Open") { model.open(card) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.clay)
                    Button("Later") { model.dismiss(card) }
                        .buttonStyle(.glass)
                }
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
    private func caption(_ text: String, dot: Bool = false, style: some ShapeStyle = .secondary,
                         weight: Font.Weight = .medium, trailing: String? = nil) -> some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(Theme.clay).frame(width: 6, height: 6)
            }
            Text(text)
                .foregroundStyle(style)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            if let trailing {
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
