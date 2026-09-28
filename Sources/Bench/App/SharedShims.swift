// SharedShims.swift — the few types the shared droplet files expect from the
// droplet's DroppyKit side, defined here with system colours instead.
import SwiftUI

/// Mirrors the droplet's ActivityPalette (ScienceStatusDroplet.swift).
struct ActivityPalette {
    let empty: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let selectedFill: Color
    let hoverFill: Color

    /// On system materials, following light or dark appearance.
    static var standard: ActivityPalette {
        ActivityPalette(
            empty: Color.primary.opacity(0.08),
            primary: .primary,
            secondary: .secondary,
            tertiary: Color.secondary.opacity(0.75),
            selectedFill: Color.primary.opacity(0.12),
            hoverFill: Color.primary.opacity(0.06))
    }
}
