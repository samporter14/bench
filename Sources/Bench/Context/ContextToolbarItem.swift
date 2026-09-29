// ContextToolbarItem.swift — the toolbar's context ring (DESIGN.md,
// Title-bar readouts): a small ring and a percent for how full the shown
// session's context window is. Its click opens ContextPopover.
import SwiftUI

/// The ring and the percent, or nothing while no session is shown or no
/// reading has arrived. Plain-styled, so the toolbar's own glass is the chrome.
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
            HStack(spacing: 5) {
                ContextRing(fraction: Double(figures.percent) / 100, isHigh: figures.isHigh)
                    .animation(reduceMotion ? nil : Theme.spring, value: figures.percent)
                Text("\(figures.percent)%")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(figures.isHigh ? Theme.clay : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

/// A 16 pt ring: a quiet track, and a clay fill that starts at the top.
private struct ContextRing: View {
    let fraction: Double
    let isHigh: Bool

    private static let lineWidth: CGFloat = 2.5

    var body: some View {
        // Inset by half the line, so the stroke stays inside the 16 pt.
        let circle = Circle().inset(by: Self.lineWidth / 2)
        ZStack {
            circle.stroke(Color.primary.opacity(0.15), lineWidth: Self.lineWidth)
            // Not drawn at 0%: a round cap on nothing would still leave a dot.
            if fraction > 0 {
                circle.trim(from: 0, to: fraction)
                    .stroke(Theme.clay.opacity(isHigh ? 1 : 0.7),
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 16, height: 16)
    }
}
