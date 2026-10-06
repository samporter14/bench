// BatchNBenchScenes.swift
// ScienceStatus — small jobs at the bench: a weigh boat filled from a
// spatula, a tube snapped open and shut, a vacuum desiccator drying a sample.
// Each draws in a unit square (see `UnitSquare`): plastic, glass and tools in
// the tint, the powder, the sample or the colour that changes in clay.

import SwiftUI

/// Odds and ends the three scenes below share.
private enum BNKit {
    /// `Ease.inOut` over the window `from...to`: 0 before it, 1 after.
    static func step(_ t: Double, _ from: Double, _ to: Double) -> Double { Ease.inOut((t - from) / (to - from)) }

    /// A point turned about `pivot` by `angle` radians, clockwise on screen.
    static func turn(_ p: (Double, Double), about pivot: (Double, Double), by angle: Double) -> (Double, Double) {
        let c = cos(angle), s = sin(angle)
        let dx = p.0 - pivot.0, dy = p.1 - pivot.1
        return (pivot.0 + dx * c - dy * s, pivot.1 + dx * s + dy * c)
    }

    /// The closed shape through `points`, for filling.
    static func polygon(_ u: UnitSquare, _ points: [(Double, Double)]) -> Path {
        var path = u.polyline(points)
        path.closeSubpath()
        return path
    }

    /// A smooth mound standing on a base line: from `origin`, `along` the base
    /// from `from` to `to`, rising `height` along `up` at its middle.
    static func mound(_ u: UnitSquare, origin: (Double, Double), along: (Double, Double), up: (Double, Double),
                      from: Double, to: Double, height: Double) -> Path {
        let steps = 10
        let pts: [(Double, Double)] = (0...steps).map { i in
            let f = Double(i) / Double(steps)
            let s = from + (to - from) * f
            let h = height * pow(max(0, 1 - (2 * f - 1) * (2 * f - 1)), 0.85)
            return (origin.0 + along.0 * s + up.0 * h, origin.1 + along.1 * s + up.1 * h)
        }
        return polygon(u, pts)
    }
}

/// Weigh boat: a plastic boat sits on the balance pan while a spatula comes
/// in from the upper right with a heap of clay powder on its blade. It tilts
/// and taps four times, each tap jiggling the blade and sending a short
/// stream of grains down, and the heap in the boat grows as the one on the
/// blade shrinks. The spatula withdraws, the full boat slides out to the left
/// while an empty one slides in from the right, and the spatula, reloaded,
/// returns to where it began.
enum WeighBoat {
    static let duration = 5.0
    private static let panY = 0.84, centre = 0.46, gap = 0.95, floorY = 0.75
    /// The far end of the spatula's handle (off the frame), and its lengths.
    private static let hand = (1.08, -0.02), reach = 0.75, blade = 0.24
    private static let boat: [(Double, Double)] = [(-0.35, 0.6), (-0.3, 0.6), (-0.17, 0.78), (0.17, 0.78), (0.3, 0.6), (0.35, 0.6)]
    private static let taps = [1.0, 1.45, 1.9, 2.35]
    private static let fall = 0.3
    /// Each grain: when it leaves the blade, and how far it strays from the stream's line.
    private static let grains: [(release: Double, spread: Double)] = taps.flatMap { tap in
        (0..<4).map { m in (release: tap + 0.045 * Double(m), spread: [-0.015, 0.01, -0.005, 0.018][m]) }
    }

    /// How much of the powder has landed in the boat, 0...1.
    private static func landed(_ t: Double) -> Double {
        grains.reduce(0) { $0 + BNKit.step(t, $1.release + fall, $1.release + fall + 0.1) } / Double(grains.count)
    }

    /// The spatula at time `t`: where its tip is, its angle above horizontal in
    /// radians, and how far it is tipped (0...1).
    private static func pose(_ t: Double) -> (tip: (Double, Double), angle: Double, tilt: Double) {
        let tilt = BNKit.step(t, 0.45, 0.95) - BNKit.step(t, 2.85, 3.25)
        var a = 26.0 + 8.0 * tilt
        for tap in taps where t > tap {
            let dt = t - tap
            a -= 3.2 * exp(-9 * dt) * sin(38 * dt)
        }
        let away = 0.9 * (BNKit.step(t, 3.15, 3.75) - BNKit.step(t, 4.15, 4.85))
        let r = a * .pi / 180
        let d = (cos(r), -sin(r))
        return ((hand.0 + (away - reach) * d.0, hand.1 + (away - reach) * d.1), r, tilt)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let powder = landed(t)
        let heap = pow(powder, 0.75)

        // The pan and its post.
        u.stroke(context, u.line((0.04, panY), (0.96, panY)), tint, 0.05)
        u.stroke(context, u.line((centre, panY), (centre, 0.95)), tint, 0.05)

        // Two boats sliding along it: the filled one out, an empty one in.
        let slide = BNKit.step(t, 3.5, 4.5)
        for (x, load) in [(centre - gap * slide, heap), (centre + gap * (1 - slide), 0.0)] {
            if load > 0.01 {
                let m = BNKit.mound(u, origin: (x, floorY), along: (1, 0), up: (0, -1), from: -0.16 * load, to: 0.16 * load, height: 0.13 * load)
                context.fill(m, with: .color(clay))
            }
            u.stroke(context, u.polyline(boat.map { (x + $0.0, $0.1) }), tint, 0.06)
        }

        // The spatula: handle, then the blade, with its heap riding on top.
        let (tip, angle, tilt) = pose(t)
        let d = (cos(angle), -sin(angle)), n = (-sin(angle), -cos(angle))
        let neck = (tip.0 + blade * d.0, tip.1 + blade * d.1)
        u.stroke(context, u.line(neck, (tip.0 + reach * d.0, tip.1 + reach * d.1)), tint, 0.045)
        u.stroke(context, u.line(tip, neck), tint, 0.07)
        let left = grains.reduce(0) { $0 + BNKit.step(t, $1.release, $1.release + 0.12) } / Double(grains.count)
        let reload = BNKit.step(t, 3.8, 4.1)
        let load = 1 - 0.88 * left + 0.88 * reload * left
        if load > 0.02 {
            let shift = -0.03 * tilt
            let m = BNKit.mound(u, origin: (tip.0 + 0.03 * n.0, tip.1 + 0.03 * n.1), along: d, up: n,
                                from: 0.03 + shift, to: 0.2 + shift, height: 0.09 * load)
            context.fill(m, with: .color(clay))
        }

        // The stream: grains leave the tip and drop onto the heap.
        let land = floorY - 0.13 * heap
        for g in grains {
            let p = (t - g.release) / fall
            guard p >= 0, p < 1 else { continue }
            let from = pose(g.release).tip
            let x = (from.0 - 0.01 + g.spread * 0.5) + (centre + g.spread - (from.0 - 0.01 + g.spread * 0.5)) * p
            let y = (from.1 + 0.03) + (land - (from.1 + 0.03)) * p * p
            context.fill(u.circle(x, y, 0.026), with: .color(clay))
        }
    }
}

/// Tube uncapping: a 1.5 mL tube with a little clay liquid in its tip. The
/// snap cap pops open about its hinge strap, swinging past its resting angle
/// and settling back, with pop ticks at the rim and a ripple in the liquid.
/// It hangs open a beat, then swings shut and clicks home with a small
/// settle and a last pair of ticks.
enum TubeUncapping {
    static let duration = 4.2
    private static let rim = 0.42, level = 0.79
    private static let hinge = (0.6, 0.375)
    private static let open = 128.0
    private static let popStart = 0.45, shutStart = 2.3, shutEnd = 2.85
    private static let outline: [(Double, Double)] = [(0.305, 0.42), (0.305, 0.7), (0.39, 0.94), (0.47, 0.94), (0.555, 0.7), (0.555, 0.42)]
    /// The cap in its shut pose, as shapes that turn about the hinge: the
    /// lid, its thumb tab and the plug that sits inside the tube.
    private static let capParts: [[(Double, Double)]] = [
        [(0.29, 0.345), (0.597, 0.345), (0.597, 0.4), (0.29, 0.4)],
        [(0.255, 0.375), (0.29, 0.375), (0.29, 0.4), (0.255, 0.4)],
        [(0.355, 0.42), (0.505, 0.42), (0.505, 0.445), (0.355, 0.445)],
    ]
    private static let tickDirs: [(Double, Double)] = [(-0.82, -0.57), (-0.42, -0.91), (-0.98, -0.2)]

    /// A burst of short lines fanning from the rim, `p` running 0...1.
    private static func burst(_ context: GraphicsContext, _ u: UnitSquare, _ tint: Color, p: Double, scale: Double, skip: Int?) {
        guard p > 0, p < 1 else { return }
        let centre = (0.36, 0.39)
        let length = 0.1 * scale * min(1, 4 * p, 3 * (1 - p)), mid = 0.09 + 0.08 * p
        for (i, dir) in tickDirs.enumerated() where i != skip {
            let a = (centre.0 + dir.0 * (mid - length / 2), centre.1 + dir.1 * (mid - length / 2))
            let b = (centre.0 + dir.0 * (mid + length / 2), centre.1 + dir.1 * (mid + length / 2))
            u.stroke(context, u.line(a, b), tint, 0.05)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The cap's angle: popped open with a little overshoot, held, then
        // swung shut and pressed home.
        let angle: Double
        if t < shutStart {
            angle = open * Ease.outBack((t - popStart) / 0.5)
        } else {
            angle = open * (1 - Ease.inOut((t - shutStart) / (shutEnd - shutStart)))
        }
        let press = 0.012 * sin(.pi * Ease.clamp((t - shutEnd) / 0.25))

        // The liquid, its surface tilting as the cap pops and clicks.
        var wobble = 0.0
        for event in [popStart + 0.1, shutEnd] where t > event {
            let dt = t - event
            wobble += 0.014 * exp(-6 * dt) * sin(34 * dt)
        }
        var inside = context
        inside.clip(to: BNKit.polygon(u, outline))
        inside.fill(BNKit.polygon(u, [(0.25, level - wobble), (0.65, level + wobble), (0.65, 1.1), (0.25, 1.1)]), with: .color(clay))

        // The tube, its rim and the strap that holds the cap.
        u.stroke(context, u.polyline(outline), tint, 0.07)
        u.stroke(context, u.line((0.275, rim), (0.585, rim)), tint, 0.05)
        u.stroke(context, u.line((0.59, rim), hinge), tint, 0.045)

        // The cap turns about the hinge: every point is rotated about it.
        for part in capParts {
            let moved = part.map { p -> (Double, Double) in
                let q = BNKit.turn(p, about: hinge, by: angle * .pi / 180)
                return (q.0, q.1 + press)
            }
            let shape = BNKit.polygon(u, moved)
            context.fill(shape, with: .color(tint))
            u.stroke(context, shape, tint, 0.03)
        }

        burst(context, u, tint, p: (t - popStart) / 0.5, scale: 1, skip: nil)
        burst(context, u, tint, p: (t - shutEnd) / 0.35, scale: 0.75, skip: 1)
    }
}

/// Vacuum desiccator: a glass pot with a domed lid, a perforated plate, a
/// sample dish and a bed of silica gel. The stopcock handle turns open, most
/// of the air drifts up the neck and out, and the handle turns shut. Moisture
/// lifts off the dish, arcs down through the plate and is soaked up by the
/// gel, which turns from tint outline to clay, grain by grain. Then the
/// stopcock opens again, air returns, the lid lifts a little and settles, and
/// the gel fades back to its outline before the handle turns shut.
enum VacuumDesiccator {
    static let duration = 6.0
    private static let flange = 0.553
    private static let plate = 0.67
    private static let dome: [(Double, Double)] = (0...24).map { i in
        let a = Double.pi + Double.pi * Double(i) / 24
        return (0.5 + 0.37 * cos(a), 0.5 + 0.27 * sin(a))
    }
    private static let pot: [(Double, Double)] = [(0.17, flange), (0.17, 0.86), (0.21, 0.9), (0.79, 0.9), (0.83, 0.86), (0.83, flange)]
    /// The plate's holes, which the moisture falls through, and its solid stretches between them.
    private static let plateSpans: [(Double, Double)] = [(0.2, 0.23), (0.32, 0.38), (0.47, 0.53), (0.62, 0.68), (0.77, 0.8)]
    private static let granules: [(x: Double, y: Double)] =
        [0.275, 0.425, 0.575, 0.725].map { (x: $0, y: 0.735) } + [0.35, 0.5, 0.65].map { (x: $0, y: 0.825) }
    /// Air: where each dot rests, whether it leaves under vacuum, and the
    /// slow circuits it jiggles on (whole cycles per loop, so they close).
    private static let air: [(home: (Double, Double), leaves: Bool, fx: Double, fy: Double, phase: Double)] = [
        ((0.5, 0.4), true, 2, 3, 0.0), ((0.37, 0.33), true, 3, 2, 1.3), ((0.63, 0.33), true, 2, 2, 2.6),
        ((0.27, 0.44), true, 3, 3, 3.9), ((0.73, 0.44), true, 2, 3, 5.2), ((0.3, 0.58), true, 3, 2, 0.7),
        ((0.69, 0.56), false, 2, 2, 2.0), ((0.34, 0.51), false, 3, 3, 4.4),
    ]
    /// Moisture: where it leaves the dish, which hole it goes through (and
    /// so which grain it lands on), and when it sets off.
    private static let drops: [(from: Double, to: Double, release: Double)] = [
        (0.47, 0.425, 2.05), (0.53, 0.575, 2.2), (0.46, 0.275, 2.35), (0.54, 0.725, 2.5),
    ]
    private static let travel = 0.9

    /// A point `q` (0 at home, 1 out of the stopcock) of the way along an air dot's path up the neck.
    private static func airPoint(_ home: (Double, Double), _ q: Double) -> (Double, Double) {
        let a = (0.5, 0.31), b = (0.5, 0.19)
        let l1 = hypot(a.0 - home.0, a.1 - home.1), l2 = a.1 - b.1
        let d = q * (l1 + l2)
        if d <= l1 {
            let f = d / l1
            return (home.0 + (a.0 - home.0) * f, home.1 + (a.1 - home.1) * f)
        }
        return (a.0, a.1 - (d - l1))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        // Drawn at nine tenths about the centre, so the wide pot stays light at 16 pt.
        var scaled = context
        scaled.translateBy(x: size.width / 2, y: size.height / 2)
        scaled.scaleBy(x: 0.9, y: 0.9)
        scaled.translateBy(x: -size.width / 2, y: -size.height / 2)
        scene(scaled, size: size, time: t, tint: tint)
    }

    private static func scene(_ context: GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The stopcock handle: turned open (0 to 1), seen end-on when open.
        let opening = BNKit.step(t, 0.25, 0.6) - BNKit.step(t, 1.6, 1.95) + BNKit.step(t, 4.05, 4.4) - BNKit.step(t, 5.3, 5.65)
        let lift = 0.05 * (Ease.out((t - 4.35) / 0.25) - BNKit.step(t, 4.9, 5.2))

        // The pot, its flange and the perforated plate.
        u.stroke(context, u.polyline(pot), tint, 0.05)
        u.stroke(context, u.line((0.08, flange), (0.17, flange)), tint, 0.04)
        u.stroke(context, u.line((0.83, flange), (0.92, flange)), tint, 0.04)
        for span in plateSpans { u.stroke(context, u.line((span.0, plate), (span.1, plate)), tint, 0.035) }

        // The sample dish, its damp sample a faint mound.
        context.fill(u.ellipse(0.5, 0.6, 0.12, 0.06), with: .color(tint.opacity(0.45)))
        u.stroke(context, u.polyline([(0.41, 0.58), (0.44, 0.64), (0.56, 0.64), (0.59, 0.58)]), tint, 0.04)

        // The gel: each grain turns clay once moisture reaches it (nearest
        // seeds first), and fades back to its outline while the air returns.
        for (k, g) in granules.enumerated() {
            var start = Double.infinity
            for d in drops {
                start = min(start, d.release + travel + 1.8 * hypot(g.x - d.to, g.y - 0.735))
            }
            let soak = BNKit.step(t, start, start + 0.3) * (1 - BNKit.step(t, 4.3 + 0.04 * Double(k), 4.8 + 0.04 * Double(k)))
            if soak > 0.01 { context.fill(u.circle(g.x, g.y, 0.05), with: .color(clay.opacity(soak))) }
            if soak < 0.99 { u.stroke(context, u.circle(g.x, g.y, 0.043), tint.opacity(1 - soak), 0.025) }
        }

        // Moisture: lifts off the dish, arcs out and drops through a hole.
        for d in drops {
            let p = (t - d.release) / travel
            guard p > 0, p < 1 else { continue }
            let e = 0.5 * (p + Ease.inOut(p))
            let m = 1 - e
            let c1 = (d.from, 0.44), c2 = (d.to, 0.5), p0 = (d.from, 0.575), p3 = (d.to, 0.7)
            let x = m * m * m * p0.0 + 3 * m * m * e * c1.0 + 3 * m * e * e * c2.0 + e * e * e * p3.0
            let y = m * m * m * p0.1 + 3 * m * m * e * c1.1 + 3 * m * e * e * c2.1 + e * e * e * p3.1
            let r = 0.032 * min(1, p / 0.12) * min(1, (1 - p) / 0.12)
            context.fill(u.circle(x, y, r), with: .color(tint))
        }

        // The air: leaves up the neck while the stopcock is open, comes back
        // in when it opens again.
        for (i, a) in air.enumerated() {
            var q = 0.0
            if a.leaves {
                let k = Double(i)
                q = BNKit.step(t, 0.5 + 0.1 * k, 1.05 + 0.1 * k) - BNKit.step(t, 4.2 + 0.08 * k, 4.75 + 0.08 * k)
            }
            guard q < 0.999 else { continue }
            let at = airPoint(a.home, q)
            let sway = 1 - q
            let x = at.0 + 0.012 * sway * sin(2 * .pi * a.fx * t / duration + a.phase)
            let y = at.1 + 0.012 * sway * cos(2 * .pi * a.fy * t / duration + a.phase)
            let alpha = q < 0.75 ? 1 : 1 - (q - 0.75) / 0.25
            context.fill(u.circle(x, y, 0.028), with: .color(tint.opacity(0.7 * alpha)))
        }

        // The lid, which lifts a little on venting: dome, lip, neck and handle.
        var lid = context
        lid.translateBy(x: 0, y: -u.len(lift))
        u.stroke(lid, u.polyline(dome), tint, 0.05)
        u.stroke(lid, u.line((0.08, 0.5), (0.15, 0.5)), tint, 0.04)
        u.stroke(lid, u.line((0.85, 0.5), (0.92, 0.5)), tint, 0.04)
        u.stroke(lid, u.line((0.445, 0.15), (0.445, 0.24)), tint, 0.035)
        u.stroke(lid, u.line((0.555, 0.15), (0.555, 0.24)), tint, 0.035)
        u.stroke(lid, u.line((0.44, 0.15), (0.56, 0.15)), tint, 0.035)
        u.stroke(lid, u.line((0.5, 0.15), (0.5, 0.1)), tint, 0.05)
        let half = 0.03 + 0.075 * abs(cos(.pi / 2 * opening))
        u.stroke(lid, u.line((0.5 - half, 0.09), (0.5 + half, 0.09)), tint, 0.05)
    }
}
