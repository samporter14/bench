// WaitingScenes.swift
// ScienceStatus — the glyphs for a session waiting on the user, drawn like
// the lab scenes (see `UnitSquare`): outlines in the tint, the thing asked
// of the user in clay. Each loops on its own `duration`, so the last frame
// runs straight back into the first.

import SwiftUI

enum WaitingScenes {
    static let duration = 2.4

    static func draw(_ glyph: WaitingGlyph, in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let phase = t.truncatingRemainder(dividingBy: duration) / duration
        switch glyph {
        case .plan: PlanWait.draw(in: &context, size: size, phase: phase, tint: tint)
        case .question: QuestionWait.draw(in: &context, size: size, phase: phase, tint: tint)
        case .permission: PermissionWait.draw(in: &context, size: size, phase: phase, tint: tint)
        }
    }
}

/// A plan to review: a clipboard with two rows ticked and the last box
/// blinking clay, waiting to be ticked.
enum PlanWait {
    static func draw(in context: inout GraphicsContext, size: CGSize, phase: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.54, 0.6, 0.76, corner: 0.08), tint, 0.065)
        context.fill(u.capsule(0.5, 0.17, 0.26, 0.12, corner: 0.04), with: .color(tint))
        let rows = [0.39, 0.56, 0.73]
        for (k, y) in rows.enumerated() {
            u.stroke(context, u.line((0.47, y), (0.7, y)), tint, 0.055)
            let box = u.capsule(0.35, y, 0.12, 0.12, corner: 0.025)
            if k < 2 {
                u.stroke(context, box, tint, 0.045)
                u.stroke(context, u.line((0.315, y), (0.345, y + 0.03), (0.39, y - 0.035)), tint, 0.045)
            } else {
                // Two blinks a loop, easing in and out.
                let blink = 0.5 - 0.5 * cos(4 * .pi * phase)
                context.fill(box, with: .color(clay.opacity(0.2 + 0.8 * blink)))
                u.stroke(context, box, clay, 0.05)
            }
        }
    }
}

/// A question: a speech bubble with a clay question mark bobbing in it.
enum QuestionWait {
    static func draw(in context: inout GraphicsContext, size: CGSize, phase: Double, tint: Color) {
        let u = UnitSquare(size)
        var tail = u.polyline([(0.27, 0.7), (0.21, 0.9), (0.45, 0.72)])
        tail.closeSubpath()
        context.fill(tail, with: .color(tint))
        u.stroke(context, u.capsule(0.5, 0.44, 0.76, 0.6, corner: 0.17), tint, 0.065)
        // Two gentle bobs a loop.
        let bob = -0.035 * sin(4 * .pi * phase)
        var mark = Path()
        let r = u.len(0.085)
        let hook = u.pt(0.5, 0.36 + bob)
        mark.addArc(center: hook, radius: r, startAngle: .degrees(190), endAngle: .degrees(60), clockwise: false)
        mark.addQuadCurve(to: u.pt(0.5, 0.52 + bob), control: u.pt(0.5, 0.45 + bob))
        u.stroke(context, mark, clay, 0.07)
        context.fill(u.circle(0.5, 0.61 + bob, 0.042), with: .color(clay))
    }
}

/// A permission to give: a padlock, clay keyhole, its shackle trying to
/// lift twice a loop and dropping back, as though someone is at the door.
enum PermissionWait {
    static func draw(in context: inout GraphicsContext, size: CGSize, phase: Double, tint: Color) {
        let u = UnitSquare(size)
        let lift = 0.075 * tries(phase)
        var shackle = Path()
        shackle.move(to: u.pt(0.34, 0.5 - lift))
        shackle.addLine(to: u.pt(0.34, 0.34 - lift))
        shackle.addArc(center: u.pt(0.5, 0.34 - lift), radius: u.len(0.16),
                       startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        shackle.addLine(to: u.pt(0.66, 0.5 - lift))
        u.stroke(context, shackle, tint, 0.075)
        context.fill(u.capsule(0.5, 0.67, 0.56, 0.42, corner: 0.08), with: .color(tint))
        context.fill(u.circle(0.5, 0.63, 0.055), with: .color(clay))
        context.fill(u.capsule(0.5, 0.71, 0.045, 0.1, corner: 0.02), with: .color(clay))
    }

    /// Up quickly, a beat held, down again: at a quarter and three quarters.
    private static func tries(_ phase: Double) -> Double {
        let local = (phase * 2).truncatingRemainder(dividingBy: 1)
        let up = Ease.out((local - 0.2) / 0.12)
        let down = Ease.inOut((local - 0.42) / 0.14)
        return up * (1 - down)
    }
}
