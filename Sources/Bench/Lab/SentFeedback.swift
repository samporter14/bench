// SentFeedback.swift — what you feel and hear when something you sent from
// Capsid lands (DESIGN.md, Look → Motion, and The panel's moments, "Sound"):
// a level-change tap on the trackpad and the quiet sent sound. The two Mac
// haptics Capsid uses are here, so each use is one call.
import AppKit

@MainActor
enum Haptics {
    /// Compare's Wipe divider meets the centre or an edge.
    static func alignment() { perform(.alignment) }
    /// An approval or a reply went through.
    static func levelChange() { perform(.levelChange) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

@MainActor
enum SentFeedback {
    /// An Approve or a Reply from a card went through: the tap and the sound.
    static func landed() {
        Haptics.levelChange()
        PanelSound.playSent()
    }
}
