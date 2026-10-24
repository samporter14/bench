// AskToolbarButton.swift — the toolbar's Ask Another Model button (DESIGN.md,
// Ask another model → Where it appears): one glyph beside Results and the
// Shelf, drawn like Results is (`ReadoutButtonStyle`, a symbol, a help line),
// and there only while the feature is on with a key. It is on while a session
// is in the main window, and dim otherwise (the readout style draws a disabled
// button as it does an enabled one, so the glyph dims itself); a click opens the
// window for that session, as File → Ask Another Model… does (the same rule,
// `AskCommands`).
import SwiftUI

enum AskToolbar {
    /// The VoiceOver label and the first words of the help.
    static let label = "Ask Another Model"
    /// Another voice in the conversation: two speech bubbles.
    static let symbol = "bubble.left.and.bubble.right"
    static let help = "Ask Another Model: put a question to a model at another provider"
    /// How much of the glyph shows while no session is in the main window.
    static let dimmed = 0.35
}

struct AskToolbarButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: AskToolbar.symbol)
                .opacity(isEnabled ? 1 : AskToolbar.dimmed)
                .accessibilityLabel(AskToolbar.label)
        }
        .buttonStyle(ReadoutButtonStyle())
        .help(AskToolbar.help)
        .disabled(!isEnabled)
    }
}
