// ActivityGraph.swift — the year graph, ported from the Science Status
// droplet (ActivityGridView, ActivityLegend and their helpers in
// ScienceStatusDroplet.swift): a column per week, the days down each column,
// four clay steps, and a glass label for the day under the pointer. The
// droplet's Droppy colours are the system's here (ActivityPalette.standard).
import SwiftUI

/// One metric's year: the graph, then the total and the legend under it.
struct ActivityGraph: View {
    let history: ActivityHistory
    let metric: ActivityMetric

    static let cell: CGFloat = 11
    static let gap: CGFloat = 3
    /// 53 columns come to 739pt, one point inside the popover's 740.
    static let weeks = 53

    private let palette = ActivityPalette.standard

    var body: some View {
        if let counts = history[metric] {
            let grid = ActivityGrid(counts: counts, today: Date(), weeks: Self.weeks)
            VStack(alignment: .leading, spacing: 10) {
                ActivityGridView(grid: grid, history: history, cell: Self.cell, gap: Self.gap)
                    .id(metric)
                    .transition(.opacity)
                    // The hover label can reach past the squares. The footer
                    // comes after the graph, so without this it would draw
                    // over the label.
                    .zIndex(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(metric.describe(grid.total)) in the last year, \(metric.describe(grid.thisWeek)) this week")
                HStack(spacing: 10) {
                    Text("\(metric.describe(grid.total)) in the last year")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    ActivityLegend()
                }
            }
        }
    }
}

/// The squares, with one label for the day under the pointer.
struct ActivityGridView: View {
    let grid: ActivityGrid
    /// Every metric, so hovering a day tells the whole of it, not only the
    /// metric shaded.
    let history: ActivityHistory
    let cell: CGFloat
    let gap: CGFloat
    @State private var hovered: Date?

    private let palette = ActivityPalette.standard

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        if let day = week[row] {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(activityFill(day.level))
                                .overlay {
                                    if hovered == day.day {
                                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                            .strokeBorder(palette.primary, lineWidth: 1.5)
                                    }
                                }
                                .frame(width: cell, height: cell)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        // One tracking area for the whole graph, not one per square: the
        // pointer's spot picks the square, gaps included, so the label
        // doesn't flicker between squares.
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = grid.day(at: point, cell: cell, gap: gap)
            case .ended: hovered = nil
            }
        }
        .overlay(alignment: .topLeading) { label }
    }

    /// Where a day sits in the grid, and its square.
    private func locate(_ day: Date) -> (column: Int, row: Int, entry: ActivityCell)? {
        for (column, week) in grid.weeks.enumerated() {
            for (row, entry) in week.enumerated() {
                if let entry, entry.day == day { return (column, row, entry) }
            }
        }
        return nil
    }

    /// "Tue, Sep 14", with the year when it isn't this one, then the day's
    /// sessions, messages and tokens: the ones that could be read.
    private func describe(_ day: ActivityCell) -> (date: String, stats: [String]) {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        if !Calendar.current.isDate(day.day, equalTo: Date(), toGranularity: .year) { style = style.year() }
        let date = day.day.formatted(style)
        let known = ActivityMetric.allCases.compactMap { metric in
            history[metric].map { (metric, $0.count(on: day.day)) }
        }
        guard known.contains(where: { $0.1 > 0 }) else { return (date, ["No activity"]) }
        return (date, known.map { $0.0.describe($0.1) })
    }

    /// The label for the day under the pointer: above its square, below it
    /// when there's no room above, and kept within the graph's width. It
    /// never takes the pointer itself. The guides sit outside the `if` in
    /// `bubble`: inside it SwiftUI drops them and the label lands top-left.
    private var label: some View {
        let spot = hovered.flatMap(locate)
        let width = CGFloat(grid.weeks.count) * (cell + gap) - gap
        let centre = CGFloat(spot?.column ?? 0) * (cell + gap) + cell / 2
        let top = CGFloat(spot?.row ?? 0) * (cell + gap)
        let height = 7 * (cell + gap) - gap
        return bubble(spot?.entry)
            .alignmentGuide(.leading) { d in
                -min(max(0, centre - d.width / 2), width - d.width)
            }
            .alignmentGuide(.top) { d in
                let above = top - d.height - 4
                let below = top + cell + 4
                if above >= 0 { return -above }
                if below + d.height <= height { return -below }
                return -(top > height - top - cell ? above : below)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func bubble(_ day: ActivityCell?) -> some View {
        if let day {
            let text = describe(day)
            VStack(alignment: .leading, spacing: 1) {
                Text(text.date)
                    .font(.system(size: 11, weight: .semibold))
                Text(text.stats.joined(separator: " · "))
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            .fixedSize()
        }
    }
}

/// "Less" to "More": the empty square, then the four clay steps.
private struct ActivityLegend: View {
    private let palette = ActivityPalette.standard

    var body: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(activityFill(level))
                    .frame(width: 9, height: 9)
            }
            Text("More")
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.tertiary)
        .accessibilityHidden(true)
    }
}

/// Level 0 is a quiet square; 1 through 4 are clay, denser as the day is busier.
private func activityFill(_ level: Int) -> Color {
    switch level {
    case 0: ActivityPalette.standard.empty
    case 1: Theme.clay.opacity(0.3)
    case 2: Theme.clay.opacity(0.5)
    case 3: Theme.clay.opacity(0.75)
    default: Theme.clay
    }
}

private extension ActivityGrid {
    /// The day under a point in the drawn graph, measured from its top-left
    /// corner: the square's column and row, a gap counting with the square
    /// before it. Nil off the graph or on a day not yet come.
    func day(at point: CGPoint, cell: CGFloat, gap: CGFloat) -> Date? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / (cell + gap))
        let row = Int(point.y / (cell + gap))
        guard weeks.indices.contains(column), (0..<7).contains(row) else { return nil }
        return weeks[column][row]?.day
    }
}
