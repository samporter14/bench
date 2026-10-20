// BatchQLabScenes.swift
// ScienceStatus — small lab rituals: a tissue pulled from its box, a hand
// tally counter clicked and reset, and a bench levelled by its foot.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Kimwipe: a box of lab tissues seen from the front and a little above,
/// a clay sheet standing up through the slot in its top in a soft peak. The
/// sheet is pulled up and away, stretching to a point where it leaves the
/// slot, and the next sheet, drawn up behind it, rises through the slot,
/// overshoots a little and sways to rest in the same peak: the loop starts
/// again with a peak in the slot.
enum Kimwipe {
    static let duration = 4.6
    private static let pullAt = 0.5, pullFor = 1.3
    private static let riseAt = 1.0, riseFor = 1.5

    private static let slot: (x: Double, y: Double, w: Double, h: Double) = (0.5, 0.545, 0.42, 0.08)
    private static let mouth = 0.36, peak = 0.36, flop = 0.035
    private static let topFace: [(Double, Double)] = [(0.14, 0.66), (0.86, 0.66), (0.79, 0.42), (0.21, 0.42)]

    /// A soft peak of tissue: base `w` wide centred at `x` on `y`, rising to an
    /// apex at (`ax`, `ay`); the left side bulges and the right sags, so the tip
    /// flops over a little, and one ivory crease runs down from it.
    private static func sheet(_ context: GraphicsContext, _ u: UnitSquare, x: Double, y: Double, w: Double, ax: Double, ay: Double) {
        let h = y - ay
        let tip = max(0.012, 0.14 * w)
        var p = Path()
        p.move(to: u.pt(x - w / 2, y))
        p.addCurve(to: u.pt(ax, ay), control1: u.pt(x - w / 2 - 0.1 * w, y - h * 0.5),
                   control2: u.pt(ax - tip, ay + h * 0.08))
        p.addCurve(to: u.pt(x + w / 2, y), control1: u.pt(ax + tip * 0.8, ay + h * 0.25),
                   control2: u.pt(x + w / 2 - 0.12 * w, y - h * 0.4))
        p.closeSubpath()
        context.fill(p, with: .color(clay))
        // The crease fades as the sheet is drawn out to a point.
        let seen = Ease.clamp((w - 0.12) / 0.2)
        if seen > 0.01 && h > 0.1 {
            var crease = Path()
            crease.move(to: u.pt(ax - 0.01, ay + h * 0.16))
            crease.addQuadCurve(to: u.pt(x - w * 0.12, y - h * 0.06), control: u.pt(ax - 0.05 * w - 0.02, ay + h * 0.55))
            context.stroke(crease, with: .color(ivory.opacity(0.9 * seen)),
                           style: StrokeStyle(lineWidth: max(u.len(0.03), UnitSquare.hairline), lineCap: .round))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // The box: a lid with an oval slot, and a front.
        var lid = u.polyline(topFace)
        lid.closeSubpath()
        let front = u.capsule(0.5, 0.795, 0.76, 0.27, corner: 0.05)
        context.fill(front, with: .color(tint.opacity(0.16)))
        u.stroke(context, front, tint, 0.06)
        u.stroke(context, lid, tint, 0.06)
        context.fill(u.capsule(slot.x, slot.y, slot.w, slot.h, corner: slot.h / 2), with: .color(tint))

        // The sheet coming away: held taut by the next one, then free.
        let p = Ease.clamp((t - pullAt) / pullFor)
        if t < pullAt + pullFor {
            let taut = Ease.inOut(p / 0.35)
            let s = Ease.clamp((p - 0.35) / 0.65)
            let fly = 1.1 * s * s
            let w = mouth + (0.1 - mouth) * taut + 0.05 * s
            let bx = slot.x + 0.45 * fly
            sheet(context, u, x: bx, y: slot.y - fly, w: w,
                  ax: bx + flop + 0.05 * taut + 0.12 * fly, ay: slot.y - fly - peak - 0.08 * taut)
        }

        // The next one rising through the slot: past its height, then back,
        // swaying a little as it settles.
        let rise = Ease.outBack((t - riseAt) / riseFor)
        let settle = max(0, t - riseAt - 0.5)
        let lean = 0.03 * exp(-2.8 * settle) * sin(8 * settle)
        if rise > 0.01 {
            sheet(context, u, x: slot.x, y: slot.y, w: mouth, ax: slot.x + flop * min(1, rise) + lean, ay: slot.y - peak * rise)
        }
    }
}

/// Tally counter: a chunky hand counter with a finger ring hanging under it, a
/// clay thumb plunger on top and three number wheels in a window. The plunger
/// clicks down four times and the units wheel rolls on a digit with each click;
/// then the reset knob turns a full circle and the wheels whirl round to zero.
/// The counter is back at 000 for the loop.
enum TallyCounter {
    static let duration = 4.8
    private static let clicks: [Double] = [0.5, 0.95, 1.4, 1.85]
    private static let resetAt = 2.9, resetFor = 1.0

    private static let body: (x: Double, y: Double, w: Double, h: Double) = (0.5, 0.50, 0.64, 0.44)
    private static let window: (x: Double, y: Double, w: Double, h: Double) = (0.5, 0.45, 0.50, 0.20)
    private static let pitch = 0.17
    private static let knob: (x: Double, y: Double, r: Double) = (0.70, 0.64, 0.05)
    private static let ring: (x: Double, y: Double, w: Double, h: Double) = (0.44, 0.835, 0.2, 0.18)
    private static let stemX = 0.60

    /// Seven-segment strokes, corner to corner on a glyph from (-1, -1) to (1, 1).
    private static let segments: [((Double, Double), (Double, Double))] = [
        ((-1, -1), (1, -1)), ((1, -1), (1, 0)), ((1, 0), (1, 1)), ((-1, 1), (1, 1)),
        ((-1, 0), (-1, 1)), ((-1, -1), (-1, 0)), ((-1, 0), (1, 0)),
    ]
    private static let lit: [[Int]] = [
        [0, 1, 2, 3, 4, 5], [1, 2], [0, 1, 6, 4, 3], [0, 1, 6, 2, 3], [5, 6, 1, 2],
        [0, 5, 6, 2, 3], [0, 5, 6, 4, 3, 2], [0, 1, 2], [0, 1, 2, 3, 4, 5, 6], [0, 1, 2, 3, 5, 6],
    ]

    private static func digit(_ u: UnitSquare, _ n: Int, x: Double, y: Double) -> Path {
        var path = Path()
        for s in lit[((n % 10) + 10) % 10] {
            let (a, b) = segments[s]
            path.move(to: u.pt(x + a.0 * 0.035, y + a.1 * 0.06))
            path.addLine(to: u.pt(x + b.0 * 0.035, y + b.1 * 0.06))
        }
        return path
    }

    /// One wheel reading `value` (a digit and the fraction rolled towards the next).
    private static func wheel(_ context: GraphicsContext, _ u: UnitSquare, x: Double, value: Double, color: Color) {
        let base = Int(value.rounded(.down))
        for k in (base - 1)...(base + 2) {
            let y = window.y + (Double(k) - value) * pitch
            guard abs(y - window.y) < 0.15 else { continue }
            u.stroke(context, digit(u, k, x: x, y: y), color, 0.032)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // How far down the plunger is, and how many digits the units wheel has rolled.
        var press = 0.0, counted = 0.0
        for c in clicks {
            let x = t - c
            press = max(press, x < 0 ? 0 : x < 0.08 ? x / 0.08 : 1 - Ease.out((x - 0.08) / 0.22))
            counted += Ease.out((x - 0.04) / 0.2)
        }
        let whirl = { (delay: Double) in Ease.inOut((t - resetAt - delay) / (resetFor - 0.2)) }
        let units = counted + (10 - Double(clicks.count)) * whirl(0.2)
        let tens = 10 * whirl(0.1), hundreds = 10 * whirl(0)

        // The finger ring hanging under the body, then the body.
        u.stroke(context, u.ellipse(ring.x, ring.y, ring.w, ring.h), tint, 0.035)
        let shell = u.capsule(body.x, body.y, body.w, body.h, corner: 0.13)
        context.fill(shell, with: .color(tint.opacity(0.1)))
        u.stroke(context, shell, tint, 0.045)

        // The plunger: a stem and a clay cap that goes down on each click.
        let capY = 0.14 + 0.055 * press
        let top = body.y - body.h / 2
        u.stroke(context, u.line((stemX, capY), (stemX, top)), tint, 0.045)
        context.fill(u.capsule(stemX, capY, 0.32, 0.10, corner: 0.05), with: .color(clay))

        // The window and its three wheels.
        let glass = u.capsule(window.x, window.y, window.w, window.h, corner: 0.05)
        context.fill(glass, with: .color(tint.opacity(0.28)))
        var inside = context
        inside.clip(to: glass)
        let step = (window.w - 0.045) / 3
        for (i, v) in [hundreds, tens, units].enumerated() {
            wheel(inside, u, x: window.x + (Double(i) - 1) * step, value: v, color: i == 2 ? clay : tint)
        }
        // The reset knob: a small disc with a tick, which goes once round.
        let turn = 2 * .pi * Ease.inOut((t - resetAt) / resetFor) - .pi / 4
        u.stroke(context, u.circle(knob.x, knob.y, knob.r), tint, 0.03)
        u.stroke(context, u.line((knob.x, knob.y), (knob.x + 0.04 * cos(turn), knob.y + 0.04 * sin(turn))), tint, 0.03)
    }
}

/// Bench level: a long spirit level lying on the top of a bench, which tilts
/// about its left post, the bubble held off to the high end. A nut on a short
/// stud under the right end turns and winds the bench up level, and the bubble
/// glides to rest between the marks, overshooting a little; then the nut turns
/// back, the bench settles to its first slope and the bubble drifts off again.
enum BenchLevel {
    static let duration = 5.0
    private static let pivot = (x: 0.08, y: 0.60)
    private static let length = 0.84
    private static let tilt = 0.113
    private static let floorY = 0.93
    private static let footX = 0.81
    private static let drift = -0.12
    private static let nutH = 0.07, pitch = 0.04

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lift = Ease.inOut((t - 0.5) / 1.5) - Ease.inOut((t - 3.0) / 1.5)
        let phi = tilt * (1 - lift)
        let settled = Ease.outBack((t - 0.7) / 1.4) * (1 - Ease.inOut((t - 3.2) / 1.4))
        let bubble = drift * (1 - settled)

        // Left support: the post the bench turns on, with its pad.
        let leftTop = pivot.y + 0.07 * tan(phi)
        u.stroke(context, u.line((0.15, leftTop), (0.15, floorY)), tint, 0.05)
        u.stroke(context, u.line((0.09, floorY), (0.21, floorY)), tint, 0.05)

        // Right foot: a stud standing on its pad, and a nut that rides up it
        // as it turns, carrying the bench's underside.
        let nutTop = pivot.y + (footX - pivot.x) * tan(phi) + 0.035
        let nut = u.capsule(footX, nutTop + nutH / 2, 0.14, nutH, corner: 0.015)
        context.fill(nut, with: .color(tint.opacity(0.12)))
        u.stroke(context, nut, tint, 0.035)
        let turns = 2 * .pi * (tilt * (footX - pivot.x) / pitch) * lift
        for k in -2...3 {
            let a = turns + Double(k) * .pi / 3
            if cos(a) > 0.05 {
                let x = footX + 0.07 * sin(a)
                u.stroke(context, u.line((x, nutTop + 0.015), (x, nutTop + nutH - 0.015)), tint, 0.03)
            }
        }
        u.stroke(context, u.line((footX, nutTop + nutH), (footX, floorY)), tint, 0.04)
        var k = 0
        while true {
            let y = floorY - 0.05 - pitch * Double(k)
            if y < nutTop + nutH + 0.03 { break }
            u.stroke(context, u.line((footX - 0.04, y), (footX + 0.04, y)), tint, 0.03)
            k += 1
        }
        u.stroke(context, u.line((footX - 0.07, floorY), (footX + 0.07, floorY)), tint, 0.05)

        // The bench top and the level on it, turned about the left end.
        var c = context
        let origin = u.pt(pivot.x, pivot.y)
        c.translateBy(x: origin.x, y: origin.y)
        c.rotate(by: .radians(phi))
        let v = UnitSquare(CGSize(width: u.side, height: u.side))
        v.stroke(c, v.line((0, 0), (length, 0)), tint, 0.055)

        let shell = v.capsule(0.43, -0.145, 0.80, 0.21, corner: 0.07)
        c.fill(shell, with: .color(tint.opacity(0.12)))
        v.stroke(c, shell, tint, 0.045)
        c.fill(v.capsule(0.43, -0.145, 0.46, 0.105, corner: 0.0525), with: .color(tint.opacity(0.3)))
        for m in [-0.09, 0.09] {
            v.stroke(c, v.line((0.43 + m, -0.145 - 0.0525), (0.43 + m, -0.145 + 0.0525)), tint, 0.03)
        }
        c.fill(v.capsule(0.43 + bubble, -0.145, 0.12, 0.06, corner: 0.03), with: .color(clay))
    }
}
