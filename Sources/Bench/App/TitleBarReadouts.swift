// TitleBarReadouts.swift — the context ring and usage remaining as one glass
// capsule in the toolbar (DESIGN.md, Title-bar readouts), split by a hairline
// like the Scenes button. Each half is its own button with its own popover.
import SwiftUI

struct TitleBarReadouts: View {
    @ObservedObject private var context = ContextModel.shared

    var body: some View {
        HStack(spacing: 0) {
            if context.figures != nil {
                ContextToolbarItem()
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 14)
                    .accessibilityHidden(true)
            }
            UsageToolbarButton()
        }
    }
}

/// A readout inside the capsule: a glyph and a figure on one line, padded
/// off the capsule's edges, with a faint pill behind it on hover and press.
/// The toolbar's glass is the chrome, so it draws none of its own.
struct ReadoutButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ReadoutBody(configuration: configuration)
    }

    private struct ReadoutBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
                        .padding(.horizontal, 2)
                }
                .contentShape(.capsule)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
