// AskScrollFollow.swift — where the Ask window's answer is read while it streams
// in (DESIGN.md, Ask another model → The window). The view follows the end of the
// text as words arrive, until the reader scrolls up; it follows again when the
// reader scrolls back to the end. Pure: the scroll view's readings in, "go to the
// end now" out, so the rules are tested without a window.
//
// The one trap: when the text grows, the scroll view reports a bigger content
// height with the reader's offset unchanged, and that is not the reader scrolling
// up. Only the top of the visible part moving up, away from the end, is.
import CoreGraphics

/// A reading of the scroll view, in content points.
struct AskScrollMetrics: Equatable, Sendable {
    /// The top and bottom of what is visible.
    var top: CGFloat
    var bottom: CGFloat
    /// The height of the whole text.
    var content: CGFloat

    var distanceToEnd: CGFloat { content - bottom }
}

struct AskScrollFollow: Equatable, Sendable {
    /// Whether the view goes to the end as the text grows.
    private(set) var following = true

    /// Within this of the end counts as at the end.
    static let nearEnd: CGFloat = 12
    /// A move smaller than this is not a move.
    static let slack: CGFloat = 2

    /// A new reading. True when the view should go to the end now: following,
    /// and the end is out of reach (the text grew, or the window below shrank).
    mutating func update(from old: AskScrollMetrics, to new: AskScrollMetrics) -> Bool {
        if new.top < old.top - Self.slack, new.distanceToEnd > Self.nearEnd {
            // Scrolled up, away from the end: the reader is reading, so stop following.
            following = false
        } else if new.top > old.top + Self.slack, new.distanceToEnd <= Self.nearEnd {
            // Scrolled down to the end: follow again.
            following = true
        }
        return following && new.distanceToEnd > Self.nearEnd
    }
}
