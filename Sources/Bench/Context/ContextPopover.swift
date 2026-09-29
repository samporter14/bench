// ContextPopover.swift — what the context ring's click opens (DESIGN.md,
// Title-bar readouts): the numbers, and a small line chart of the context at
// each turn, on one glass card like the Usage popover's.
import SwiftUI

struct ContextPopover: View {
    let figures: ContextFigures
    @ObservedObject private var model = ContextModel.shared

    var body: some View {
        // Laid out like the Usage popover: a header with its button, then
        // one glass card.
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Context")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                if model.loading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(model.failure == nil ? "Refresh" : "Retry") { model.refresh() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(model.loading)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(figures.percent)%")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(figures.isHigh ? Theme.clay : Color.primary)
                    Text("\(figures.usedOfWindow) tokens")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(model.turns.count == 1 ? "1 turn" : "\(model.turns.count.formatted()) turns")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()

                // On the card's glass, not its own: no glass on glass.
                ContextChart(turns: model.turns, window: figures.window)
                    .frame(height: 90)

                if model.truncated || model.failure != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        if let failure = model.failure {
                            Text(failure)
                        }
                        if model.truncated {
                            Text("Long session: the tail may be stale")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// `ctx_total` per turn as a clay line with a faint area under it, and the
/// window as a dashed line. Drawn with Path, not Swift Charts, to stay light.
private struct ContextChart: View {
    let turns: [Int]
    let window: Int

    var body: some View {
        Canvas { context, size in
            guard !turns.isEmpty else { return }
            // Room above the plot for the "window" label, and a margin around.
            let plot = CGRect(x: 12, y: 26, width: size.width - 24, height: size.height - 38)
            // A turn past the window (it can happen) stays in frame.
            let ceiling = CGFloat(max(window, turns.max() ?? 0))
            func y(_ tokens: Int) -> CGFloat { plot.maxY - plot.height * CGFloat(tokens) / ceiling }

            let last = turns.count - 1
            let points = turns.enumerated().map { index, tokens in
                // One turn has no width to spread over, so it takes the middle.
                let x = last > 0 ? plot.minX + plot.width * CGFloat(index) / CGFloat(last) : plot.midX
                return CGPoint(x: x, y: y(tokens))
            }

            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: points[last].x, y: plot.maxY))
            area.addLine(to: CGPoint(x: points[0].x, y: plot.maxY))
            area.closeSubpath()
            context.fill(area, with: .color(Theme.clay.opacity(0.12)))

            let top = y(window)
            var limit = Path()
            limit.move(to: CGPoint(x: plot.minX, y: top))
            limit.addLine(to: CGPoint(x: plot.maxX, y: top))
            context.stroke(limit, with: .color(Color.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            context.draw(
                Text("window").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.secondary),
                at: CGPoint(x: plot.maxX, y: top - 3), anchor: .bottomTrailing)

            context.stroke(line, with: .color(Theme.clay), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            // The latest turn, and the only mark a single turn can make.
            let end = points[last]
            context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)),
                         with: .color(Theme.clay))
        }
        .accessibilityLabel("Context used at each turn")
    }
}
