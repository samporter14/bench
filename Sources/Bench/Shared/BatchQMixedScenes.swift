// BatchQMixedScenes.swift
// ScienceStatus — glass, water and light
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Glassblowing: a glass tube turns above a clay torch flame (short marks ride
/// round its front face), the glass over the flame warms to clay and swells
/// into a round bulb, then cools as the whole tube slides one bulb-spacing
/// along; a fresh straight length takes the flame's place, and the finished
/// bulb has left the picture, so the loop closes on itself.
enum Glassblowing {
    static let duration = 5.0

    private static let cy = 0.38, hw = 0.085, bulbR = 0.20
    /// How far the glass slides, which is also the spacing of finished bulbs.
    private static let pitch = 0.72
    /// The tube runs past both edges of the square.
    private static let left = -0.05, right = 1.05
    private static let heatAt = 0.2, swellAt = 1.2, swellEnd = 3.2
    private static let coolAt = 3.5, slideAt = 3.6, slideEnd = 4.7
    /// Where the walls are sampled along the tube.
    private static let xs: [Double] = stride(from: left, through: right, by: 0.01).map { $0 }

    /// How much the wall stands out at `dx` from a bulb's middle, for a bulb
    /// grown to `s` (0 to 1): a ball whose joins to the tube are rounded off.
    private static func swell(_ dx: Double, _ s: Double) -> Double {
        guard s > 0 else { return 0 }
        let radius = 0.05 + (bulbR - 0.05) * s
        let ball = abs(dx) < radius ? (radius * radius - dx * dx).squareRoot() : 0
        let k = 0.05
        func smoothMax(_ a: Double, _ b: Double) -> Double { 0.5 * (a + b + ((a - b) * (a - b) + k * k).squareRoot()) }
        return (smoothMax(hw, ball) - smoothMax(hw, 0)) * min(1, s * 8)
    }

    /// The tube's half-height at x: the bulb being blown (middle, `slide` along)
    /// and the one finished before it.
    private static func wall(_ x: Double, slide: Double, grow: Double) -> Double {
        let now = 0.5 - slide
        return hw + max(swell(x - now, grow), swell(x - (now - pitch), 1))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let grow = Ease.inOut((t - swellAt) / (swellEnd - swellAt))
        let slide = pitch * Ease.inOut((t - slideAt) / (slideEnd - slideAt))
        let heat = Ease.inOut((t - heatAt) / (swellAt + 0.1 - heatAt)) * (1 - Ease.inOut((t - coolAt) / (slideEnd - coolAt)))
        let now = 0.5 - slide

        // The tube: two walls, the hot stretch of them redrawn in clay.
        let heights = xs.map { wall($0, slide: slide, grow: grow) }
        for side in [-1.0, 1.0] {
            let wallPts = zip(xs, heights).map { ($0, cy + side * $1) }
            u.stroke(context, u.polyline(wallPts), tint, 0.065)
            if heat > 0.01 {
                let hot = wallPts.filter { abs($0.0 - now) < 0.23 }
                if hot.count > 1 { u.stroke(context, u.polyline(hot), clay.opacity(heat), 0.065) }
            }
        }

        // Marks turning with the glass: each rides the surface as it comes round
        // the front, so it drifts down the face and slips away behind.
        let spin = 3 * t / duration
        for j in -4...5 {
            let x = 0.5 + pitch / 6 + Double(j) * pitch / 3 - slide
            let edge = Ease.clamp(min(x, 1 - x) / 0.12)
            guard edge > 0 else { continue }
            let angle = 2 * .pi * (spin + Double(j) / 3)
            let front = cos(angle)
            guard front > 0.15 else { continue }
            let h = wall(x, slide: slide, grow: grow)
            let y = cy + (h - 0.005) * sin(angle)
            u.stroke(context, u.line((x - 0.035, y), (x + 0.035, y)), tint.opacity(min(1, front * 1.4) * edge), 0.045)
        }

        // The flame under the middle, its tip a little below the glass there.
        let base = 0.90
        let flick = 1 + 0.04 * sin(2 * .pi * 11 * t / duration)
        let tipY = cy + wall(0.5, slide: slide, grow: grow) + 0.07
        let height = (base - tipY) * flick
        let tipX = 0.5 + 0.014 * sin(2 * .pi * 7 * t / duration)
        flame(context, u, x: 0.5, tipX: tipX, base: base, height: height, width: 0.21, color: clay)
        flame(context, u, x: 0.5, tipX: 0.5 + (tipX - 0.5) * 0.5, base: base, height: height * 0.5, width: 0.095, color: ivory)
        context.fill(u.capsule(0.5, 0.945, 0.27, 0.07, corner: 0.03), with: .color(tint))
    }

    /// A flat teardrop flame standing on `base`.
    private static func flame(_ context: GraphicsContext, _ u: UnitSquare, x: Double, tipX: Double, base: Double,
                              height: Double, width w: Double, color: Color) {
        let tip = base - height
        let belly = base - w * 0.5
        let rise = (belly - tip) * 0.55
        var p = Path()
        p.move(to: u.pt(tipX, tip))
        p.addQuadCurve(to: u.pt(x + w / 2, belly), control: u.pt(x + w / 2, belly - rise))
        p.addQuadCurve(to: u.pt(x, base), control: u.pt(x + w / 2, base))
        p.addQuadCurve(to: u.pt(x - w / 2, belly), control: u.pt(x - w / 2, base))
        p.addQuadCurve(to: u.pt(tipX, tip), control: u.pt(x - w / 2, belly - rise))
        context.fill(p, with: .color(color))
    }
}

/// Eyewash station: a bench eyewash, a shallow bowl on a pedestal with two
/// spray heads rising inside it and a flat push plate hanging on a short arm
/// off its right side; the plate swings out as it is pushed, a clay stream
/// leaves each head in an arc and the two meet in the middle above the bowl,
/// they hold with glints running up them, then the plate swings back and the
/// streams draw back to the meeting point and are gone.
enum EyewashStation {
    static let duration = 5.0

    private static let cx = 0.5
    private static let rimY = 0.64, rimHalf = 0.28, depth = 0.13
    private static let headDX = 0.12, headTop = 0.56, meetY = 0.20
    private static let plateHeight = 0.18

    /// One stream from its spray head to the meeting point; `side` is -1 for
    /// the left head, +1 for the right.
    private static func stream(_ u: UnitSquare, _ side: Double) -> Path {
        var p = Path()
        p.move(to: u.pt(cx + side * headDX, headTop - 0.02))
        p.addQuadCurve(to: u.pt(cx, meetY), control: u.pt(cx + side * 0.085, meetY + 0.05))
        return p
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let press = Ease.inOut((t - 0.3) / 0.5) * (1 - Ease.inOut((t - 3.2) / 0.6))
        let head = Ease.out((t - 0.8) / 1.0)
        let tail = Ease.inOut((t - 3.5) / 1.0)

        // The fixture: bench, pedestal, the shallow bowl, two spray heads inside it.
        u.stroke(context, u.line((0.08, 0.92), (0.92, 0.92)), tint, 0.06)
        u.stroke(context, u.line((cx, 0.92), (cx, rimY + depth)), tint, 0.075)
        // The bowl: its rim seen as a flat ellipse, its body curving down below.
        var bowl = Path()
        bowl.move(to: u.pt(cx - rimHalf, rimY))
        bowl.addQuadCurve(to: u.pt(cx + rimHalf, rimY), control: u.pt(cx, rimY + 2 * depth))
        u.stroke(context, bowl, tint, 0.07)
        u.stroke(context, u.ellipse(cx, rimY, 2 * rimHalf, 0.1), tint, 0.05)
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((cx + side * headDX, rimY + 0.01), (cx + side * headDX, headTop)), tint, 0.075)
        }

        // The push plate: a short arm off the bowl's right rim, a flat plate
        // hanging from its end that swings out when pushed.
        let hingeX = cx + rimHalf + 0.07, hingeY = rimY
        u.stroke(context, u.line((cx + rimHalf, rimY), (hingeX, hingeY)), tint, 0.06)
        let hinge = u.pt(hingeX, hingeY)
        let plate = Path(roundedRect: CGRect(x: hinge.x - u.len(0.035), y: hinge.y, width: u.len(0.07), height: u.len(plateHeight)),
                         cornerRadius: u.len(0.03))
        let swing = CGAffineTransform(translationX: hinge.x, y: hinge.y)
            .rotated(by: -press * 22 * .pi / 180)
            .translatedBy(x: -hinge.x, y: -hinge.y)
        context.fill(plate.applying(swing), with: .color(tint))

        // The water: each stream grows from its head, and later its tail
        // catches up with its head at the meeting point.
        guard head - tail > 0.02 && tail < 0.97 else { return }
        let width = 0.07 - 0.03 * tail
        for side in [-1.0, 1.0] {
            let path = stream(u, side)
            u.stroke(context, path.trimmedPath(from: tail, to: head), clay, width)
            // Glints running up the stream while it holds.
            guard head - tail > 0.3 else { continue }
            for g in 0..<2 {
                let phase = (t * 0.8 + Double(g) * 0.5).truncatingRemainder(dividingBy: 1)
                let s = tail + (head - tail - 0.1) * phase
                u.stroke(context, path.trimmedPath(from: s, to: s + 0.1), ivory, 0.03)
            }
        }
    }
}

/// Chloroplast movement: a tall plant cell (wall and a thin membrane just
/// inside it) with six lens-shaped chloroplasts lying flat in two rows along
/// its top face, under a faint clay beam of light from above. The light
/// strengthens (the beam brightens and widens) and the chloroplasts turn
/// edge-on and slide to the two side walls out of its way (the avoidance
/// response); as the light dims they lie back across the top face (the
/// accumulation response), ready to start again.
enum ChloroplastMovement {
    static let duration = 5.0

    /// Where each rests in weak light (ax, ay) and in strong (vx, vy).
    private static let plasts: [(ax: Double, ay: Double, vx: Double, vy: Double)] = [
        (0.38, 0.25, 0.355, 0.37), (0.50, 0.25, 0.355, 0.50), (0.38, 0.36, 0.355, 0.63),
        (0.62, 0.25, 0.645, 0.37), (0.50, 0.36, 0.645, 0.50), (0.62, 0.36, 0.645, 0.63),
    ]
    private static let lensA = 0.055, lensB = 0.04

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let light = Ease.inOut((t - 0.5) / 1.0) * (1 - Ease.inOut((t - 3.1) / 0.9))

        // The beam, behind the cell: a clay band from the top, brighter and wider in strong light.
        let top = 0.045 + 0.03 * light, bottom = 0.055 + 0.04 * light
        var beam = Path()
        beam.addLines([u.pt(0.5 - top, 0), u.pt(0.5 + top, 0), u.pt(0.5 + bottom, 0.9), u.pt(0.5 - bottom, 0.9)])
        beam.closeSubpath()
        context.fill(beam, with: .color(clay.opacity(0.15 + 0.38 * light)))

        // The wall and, just inside it, the membrane.
        u.stroke(context, u.capsule(0.5, 0.5, 0.54, 0.80, corner: 0.09), tint, 0.05)
        u.stroke(context, u.capsule(0.5, 0.5, 0.41, 0.67, corner: 0.055), tint.opacity(0.34), 0.03)

        for (i, c) in plasts.enumerated() {
            let go = Ease.inOut((t - (1.0 + 0.05 * Double(i))) / 1.3)
            let back = Ease.inOut((t - (3.3 + 0.04 * Double(i))) / 1.3)
            let m = go * (1 - back)
            let x = c.ax + (c.vx - c.ax) * m, y = c.ay + (c.vy - c.ay) * m
            // Flat to the light on the top, turned edge-on against the walls.
            let turn = m * .pi / 2
            let cs = cos(turn), sn = sin(turn)
            func at(_ lx: Double, _ ly: Double) -> CGPoint { u.pt(x + lx * cs - ly * sn, y + lx * sn + ly * cs) }
            var lens = Path()
            lens.move(to: at(-lensA, 0))
            lens.addQuadCurve(to: at(lensA, 0), control: at(0, -2 * lensB))
            lens.addQuadCurve(to: at(-lensA, 0), control: at(0, 2 * lensB))
            context.fill(lens, with: .color(clay))
            // A thylakoid hint: a short line down the middle.
            var vein = Path()
            vein.move(to: at(-lensA * 0.55, 0))
            vein.addLine(to: at(lensA * 0.55, 0))
            context.stroke(vein, with: .color(ivory), style: StrokeStyle(lineWidth: u.len(0.022), lineCap: .round))
        }
    }
}
