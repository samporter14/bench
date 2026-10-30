// OnceMotion.swift — the small motions that answer something that just
// happened (DESIGN.md, Look → Motion): a count that rolls to its new figure,
// and a glyph that hops once when more needs you or the Shelf gains something.
// Each plays once, never loops, and is off under Reduce Motion and in a still
// picture of a view (`stillSpecimens`).
import SwiftUI

extension View {
    /// The figure rolls to its new value, the digits that changed turning up
    /// or down. For counts and percentages that change, never a clock.
    func rollingDigits(_ value: Double) -> some View {
        modifier(RollingDigits(value: value))
    }

    /// A short hop, once each time `count` goes up; nothing when it goes down.
    /// For a glyph that is not an SF Symbol (a scene, a drawn shape), where
    /// `.symbolEffect(.bounce)` would do nothing.
    func hopsWhenItGrows(_ count: Int) -> some View {
        modifier(HopsWhenItGrows(count: count))
    }
}

/// Whether motion of this kind may play in a view: not under Reduce Motion,
/// not in a still picture.
private struct MotionAllowed {
    let reduceMotion: Bool
    let still: Bool
    var moves: Bool { !(reduceMotion || still) }
}

private struct RollingDigits: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillSpecimens) private var still

    func body(content: Content) -> some View {
        let moves = MotionAllowed(reduceMotion: reduceMotion, still: still).moves
        content
            .contentTransition(moves ? .numericText(value: value) : .identity)
            .animation(moves ? Theme.spring : nil, value: value)
    }
}

private struct HopsWhenItGrows: ViewModifier {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillSpecimens) private var still
    /// Counts the hops: the keyframes play once each time it changes.
    @State private var hops = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: hops) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.28, duration: 0.14, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.34, spring: .bouncy)
            }
            .onChange(of: count) { old, new in
                if new > old, MotionAllowed(reduceMotion: reduceMotion, still: still).moves { hops += 1 }
            }
    }
}

/// The checkmark of a confirmation ("Approved ✓"), drawn on once as it comes.
/// Under Reduce Motion, or in a still picture, it is there at once.
struct DrawnCheckmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillSpecimens) private var still
    /// Drawn off until the view is on screen, then drawn on.
    @State private var waiting = true

    var body: some View {
        let moves = MotionAllowed(reduceMotion: reduceMotion, still: still).moves
        Image(systemName: "checkmark")
            .symbolEffect(.drawOn, options: .nonRepeating, isActive: moves && waiting)
            .task { waiting = false }
    }
}
