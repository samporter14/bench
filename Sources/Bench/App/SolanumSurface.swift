// SolanumSurface.swift — the 1.0 windows' surfaces, after the Capsid 1.0
// mock-ups (DESIGN.md, Look → The 1.0 windows): Solanum's ivory page and
// white raised cards (slate and its raised grey in the dark), hairline edges
// instead of shadows, ink and muted ink for words, and two controls, a pill
// and a round button, both white with a strong hairline. Settings, menus and
// popovers stay the system's own; these are for the feature windows
// (Reference first). Every colour follows the appearance it is drawn in, so
// the Ivory and Slate setting reaches them with nothing passed down.
import AppKit
import SwiftUI

enum Solanum {
    // MARK: Colours (the design system's tokens, light and dark)

    /// The page: ivory, or slate. Never pure white beside ivory.
    static let pageColor = dynamic(light: rgb(0xFA, 0xF9, 0xF5), dark: rgb(0x14, 0x14, 0x13))
    /// Cards and controls on the page: white, or the raised grey.
    static let raisedColor = dynamic(light: rgb(0xFF, 0xFF, 0xFF), dark: rgb(0x26, 0x26, 0x24))
    /// The title bar's band, a shade off the page.
    static let barColor = dynamic(light: NSColor(srgbRed: 246 / 255, green: 245 / 255, blue: 240 / 255, alpha: 0.92),
                                  dark: NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1B / 255, alpha: 0.92))
    static let inkColor = dynamic(light: rgb(0x14, 0x14, 0x13), dark: rgb(0xFA, 0xF9, 0xF5))
    /// Captions, labels and secondary sentences.
    static let mutedColor = dynamic(light: rgb(0x5E, 0x5D, 0x59), dark: rgb(0xB0, 0xAE, 0xA5))
    /// Card and panel edges.
    static let hairlineColor = dynamic(light: NSColor(srgbRed: 31 / 255, green: 30 / 255, blue: 29 / 255, alpha: 0.15),
                                       dark: NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.18))
    /// A selected row's ground: ink at a tenth (never the accent).
    static let selectionColor = dynamic(light: NSColor(srgbRed: 31 / 255, green: 30 / 255, blue: 29 / 255, alpha: 0.1),
                                        dark: NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.12))
    /// Control edges, where 3:1 is the floor.
    static let strongColor = dynamic(light: NSColor(srgbRed: 31 / 255, green: 30 / 255, blue: 29 / 255, alpha: 0.3),
                                     dark: NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.32))

    /// Words on a clay fill: slate in both appearances (the mock-ups' Keep,
    /// Start and Reply).
    static let slateInk = Color(nsColor: NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255, alpha: 1))
    /// The one accent, as a fill.
    static let clayFill = Theme.clay

    static let page = Color(nsColor: pageColor)
    static let raised = Color(nsColor: raisedColor)
    static let bar = Color(nsColor: barColor)
    static let ink = Color(nsColor: inkColor)
    static let muted = Color(nsColor: mutedColor)
    static let hairline = Color(nsColor: hairlineColor)
    static let strong = Color(nsColor: strongColor)
    static let selection = Color(nsColor: selectionColor)

    // MARK: Type (the system font at the mock-ups' sizes)

    /// Reading text: 14 on 21.
    static let bodySize: CGFloat = 14
    static let bodyLeading: CGFloat = 21
    /// Captions and section labels.
    static let captionSize: CGFloat = 12

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// A pill: white (raised) with a strong hairline, ink words. Regular (30
/// points) for a window's foot, medium (28) for a row of actions, small (26)
/// under a figure.
struct SolanumPillStyle: ButtonStyle {
    enum Size { case regular, medium, small }
    var size: Size = .regular
    /// The one action that asks (Keep, Start): a clay fill with ink words,
    /// semibold, no edge. One per view.
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ size: Size = .regular, prominent: Bool = false) {
        self.size = size
        self.prominent = prominent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .regular ? 13 : 12, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AnyShapeStyle(Solanum.slateInk) : AnyShapeStyle(Solanum.ink))
            .lineLimit(1)
            .padding(.horizontal, size == .small ? 10 : size == .medium ? 12 : prominent ? 16 : 14)
            .frame(height: size == .small ? 26 : size == .medium ? 28 : 30)
            .background(Capsule().fill(prominent ? Solanum.clayFill : Solanum.raised))
            .overlay(Capsule().fill(Solanum.hairline).opacity(configuration.isPressed ? 1 : 0))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Solanum.strong, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// A round button, 28 points, white with a strong hairline: the reader's
/// chevrons. Its glyph dims with the button.
struct SolanumRoundStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isEnabled ? Solanum.ink : Solanum.muted)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Solanum.raised))
            .overlay(Circle().fill(Solanum.hairline).opacity(configuration.isPressed ? 1 : 0))
            .overlay(Circle().strokeBorder(Solanum.strong, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(Circle())
    }
}
