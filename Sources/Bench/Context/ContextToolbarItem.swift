// ContextToolbarItem.swift — the toolbar's context ring (DESIGN.md,
// Title-bar readouts): a small ring and a percent for how full the shown
// session's context window is. Its click opens ContextPopover.
import SwiftUI

/// The ring and the percent, or nothing while no session is shown or no
/// reading has arrived. The left half of TitleBarReadouts' capsule.
struct ContextToolbarItem: View {
    @ObservedObject private var model = ContextModel.shared

    var body: some View {
        // A stack rather than a Group: with nothing in it there is still a
        // view in the hierarchy, so `onAppear` fires and the first read can
        // start. It only starts watching once.
        HStack(spacing: 0) {
            if let figures = model.figures {
                ContextButton(figures: figures)
            }
        }
        .onAppear { model.start() }
    }
}

private struct ContextButton: View {
    let figures: ContextFigures
    // Kept here rather than in ContextToolbarItem: when the reading goes, this
    // view goes with it and the popover does not reopen with the next one.
    @State private var showing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                ContextRing(fraction: Double(figures.percent) / 100)
                    .animation(reduceMotion ? nil : Theme.spring, value: figures.percent)
                Text("\(figures.percent)%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(figures.isHigh ? Theme.clay : Color.secondary)
            }
        }
        .buttonStyle(ReadoutButtonStyle())
        .help("Context: \(figures.percent)% (\(figures.usedOfWindow))")
        .accessibilityLabel("Context")
        .accessibilityValue("\(figures.percent) percent")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ContextPopover(figures: figures)
        }
        // The binding also flips when a click outside dismisses the popover,
        // which a button action would not see.
        .onChange(of: showing) { _, open in
            if open { ContextModel.shared.popoverOpened() }
        }
    }
}

/// A 14 pt ring: a quiet track, and a clay fill that starts at the top. The
/// figure beside it is what turns clay when the window is nearly full.
private struct ContextRing: View {
    let fraction: Double

    private static let lineWidth: CGFloat = 2.5

    var body: some View {
        // Inset by half the line, so the stroke stays inside the 14 pt.
        let circle = Circle().inset(by: Self.lineWidth / 2)
        ZStack {
            circle.stroke(Color.primary.opacity(0.15), lineWidth: Self.lineWidth)
            // Not drawn at 0%: a round cap on nothing would still leave a dot.
            if fraction > 0 {
                circle.trim(from: 0, to: fraction)
                    .stroke(Theme.clay, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 14, height: 14)
    }
}
