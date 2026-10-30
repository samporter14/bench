// CompanionGlyphs.swift — the small drawings of the menu bar home: the Capsid
// glyph in the menu bar (board 1's five nodes round a centre, the nodes in
// clay), the rows' 28-point line drawings (a speech bubble with a "?", a plan
// page, a lock, a warning triangle), and what the status item shows
// (`MenuBarItemView`). Drawn in code, so they are sharp at any size and paint
// in an offscreen picture as they do in the menu bar.
import SwiftUI

/// The five-node glyph. The lines take the ink they are given, which for the
/// menu bar is the menu bar's own (white on a dark one, black on a light one);
/// the nodes are Capsid's clay.
struct CompanionMark: View {
    var ink: Color = Solanum.ink

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            let centre = point(12, 12)
            let nodes = [point(12, 4), point(19.6, 9.5), point(16.7, 18.5), point(7.3, 18.5), point(4.4, 9.5)]
            var lines = Path()
            for node in nodes {
                lines.move(to: centre)
                lines.addLine(to: node)
            }
            context.stroke(lines, with: .color(ink), lineWidth: 1.8 * scale)
            for node in nodes {
                let r = 2.4 * scale
                context.fill(Path(ellipseIn: CGRect(x: node.x - r, y: node.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(Theme.clay))
            }
        }
        .accessibilityHidden(true)
    }
}

/// What a row in Needs you is about, as the board draws it: 28 points, a 2-point line in ink and one
/// touch of clay.
struct NeedGlyph: View {
    let kind: CompanionNeedRow.Kind

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 28
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
            }
            let line = 2 * scale
            let ink = GraphicsContext.Shading.color(Solanum.ink), clay = GraphicsContext.Shading.color(Theme.clay)
            switch kind {
            case .question:
                // A speech bubble with its tail at the lower left, and a clay "?".
                var bubble = Path()
                bubble.move(to: at(5, 5))
                bubble.addLine(to: at(23, 5))
                bubble.addQuadCurve(to: at(25, 7), control: at(25, 5))
                bubble.addLine(to: at(25, 18))
                bubble.addQuadCurve(to: at(23, 20), control: at(25, 20))
                bubble.addLine(to: at(12, 20))
                bubble.addLine(to: at(7, 24))
                bubble.addLine(to: at(7, 20))
                bubble.addLine(to: at(5, 20))
                bubble.addQuadCurve(to: at(3, 18), control: at(3, 20))
                bubble.addLine(to: at(3, 7))
                bubble.addQuadCurve(to: at(5, 5), control: at(3, 5))
                bubble.closeSubpath()
                context.stroke(bubble, with: ink, lineWidth: line)
                context.draw(Text("?").font(.system(size: 12 * scale, weight: .bold)).foregroundColor(Theme.clay),
                             at: at(14, 12.5))
            case .plan:
                // A page with three lines, the first of them marked in clay.
                context.stroke(Path(roundedRect: rect(6, 4, 16, 21), cornerRadius: 2 * scale), with: ink, lineWidth: line)
                var lines = Path()
                lines.move(to: at(10, 10)); lines.addLine(to: at(18, 10))
                lines.move(to: at(10, 14)); lines.addLine(to: at(18, 14))
                lines.move(to: at(10, 18)); lines.addLine(to: at(15, 18))
                context.stroke(lines, with: ink, lineWidth: line)
                context.fill(Path(rect(9, 17, 3, 3)), with: clay)
            case .request:
                // A padlock with a clay keyhole.
                var shackle = Path()
                shackle.move(to: at(10, 12))
                shackle.addLine(to: at(10, 9))
                shackle.addArc(center: at(14, 9), radius: 4 * scale, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                shackle.addLine(to: at(18, 12))
                context.stroke(shackle, with: ink, lineWidth: line)
                context.stroke(Path(roundedRect: rect(6, 12, 16, 12), cornerRadius: 2 * scale), with: ink, lineWidth: line)
                context.fill(Path(ellipseIn: rect(12.2, 16.2, 3.6, 3.6)), with: clay)
            case .stopped:
                // A triangle with an exclamation mark whose dot is clay.
                var triangle = Path()
                triangle.move(to: at(14, 4))
                triangle.addLine(to: at(25, 23))
                triangle.addLine(to: at(3, 23))
                triangle.closeSubpath()
                context.stroke(triangle, with: ink, style: StrokeStyle(lineWidth: line, lineJoin: .round))
                var mark = Path()
                mark.move(to: at(14, 11)); mark.addLine(to: at(14, 16.5))
                context.stroke(mark, with: ink, lineWidth: line)
                context.fill(Path(ellipseIn: rect(12.5, 18.6, 3, 3)), with: clay)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What the status item shows (`MenuBarFace`): the glyph, the specimen while a session works, or a still
/// pause mark when a used-up limit holds every session, and the count of what needs you. The ink is the
/// menu bar's, not Capsid's Ivory or Slate.
struct MenuBarItemView: View {
    let face: MenuBarFace
    let dark: Bool
    @ObservedObject private var settings = SceneSettings.shared

    private var ink: Color { dark ? .white : .black }
    /// The count in clay words, the darker clay on a light menu bar and the lighter on a dark one.
    private var count: Color { Color(nsColor: dark ? Theme.clayTextDark : Theme.clayTextLight) }

    var body: some View {
        HStack(spacing: 3) {
            switch face.mark {
            case .capsid:
                CompanionMark(ink: ink).frame(width: 16, height: 16)
            case .specimen:
                WorkingGlyph(tint: ink, rotation: settings.rotation).frame(width: 17, height: 17)
            case .paused:
                Image(systemName: "pause.circle").font(.system(size: 14)).foregroundStyle(ink)
            }
            if let text = face.countText {
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(count)
                    .rollingDigits(Double(face.needs))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
