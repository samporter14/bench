// BenchThreeScenes.swift
// ScienceStatus — still more of the bench. Each draws in a unit square
// (see `UnitSquare`): glass, plastic and machines in the tint, the sample
// in clay.

import SwiftUI

/// A NanoDrop reading: a clay drop goes on the pedestal, the arm comes down
/// and draws it into a column, and the spectrum traces out, peaking at
/// 260 nm.
enum NanoDrop {
    static let duration = 4.4
    private static let pedestal = (0.3, 0.667)

    /// Absorbance across 220 to 340 nm (`s` from 0 to 1): the steep rise
    /// at the short end, the dip at 230 and the peak at 260.
    private static func absorbance(_ s: Double) -> Double {
        0.85 * exp(-pow((s - 0.33) / 0.13, 2)) + 0.7 * exp(-pow(s / 0.05, 2))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let closed = Ease.inOut((t - 0.8) / 0.4) - Ease.inOut((t - 3.4) / 0.4)
        let wiped = Ease.clamp((t - 3.7) / 0.25)
        let fade = Ease.inOut((t - 3.7) / 0.5)

        context.fill(u.capsule(0.28, 0.74, 0.44, 0.09, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(pedestal.0, 0.685, 0.08, 0.04, corner: 0.012), with: .color(tint))
        // The drop: falls, sits, is drawn into a column under the arm.
        let fall = Ease.clamp((t - 0.25) / 0.35)
        if fall > 0, wiped < 1 {
            if fall < 1 {
                context.fill(u.circle(pedestal.0, 0.1 + (0.63 - 0.1) * fall * fall, 0.03), with: .color(clay))
            } else {
                let column = Ease.clamp(closed)
                let top = 0.63 - 0.03 * column
                let height = pedestal.1 - top
                let width = 0.07 - 0.02 * column
                context.fill(u.capsule(pedestal.0, top + height / 2, width, height, corner: min(width, height) / 2 * (1 - 0.5 * column)),
                             with: .color(clay.opacity(1 - wiped)))
            }
        }
        // The arm, hinged at the back.
        var arm = context
        let hinge = u.pt(0.08, 0.57)
        arm.translateBy(x: hinge.x, y: hinge.y)
        arm.rotate(by: .degrees(-55 * (1 - closed)))
        arm.translateBy(x: -hinge.x, y: -hinge.y)
        arm.fill(u.capsule(0.21, 0.57, 0.3, 0.05, corner: 0.02), with: .color(tint))
        arm.fill(u.capsule(pedestal.0, 0.6, 0.06, 0.04, corner: 0.012), with: .color(tint))
        u.stroke(context, u.line((0.08, 0.57), (0.08, 0.72)), tint, 0.045)

        // The spectrum.
        u.stroke(context, u.line((0.56, 0.4), (0.56, 0.8), (0.94, 0.8)), tint.opacity(0.3 * (1 - fade)), 0.02)
        let drawn = Ease.clamp((t - 1.4) / 1.2)
        guard drawn > 0 else { return }
        let curve = stride(from: 0.0, through: drawn, by: 0.02).map { s in (0.58 + 0.36 * s, 0.79 - 0.36 * absorbance(s)) }
        u.stroke(context, u.polyline(curve), tint.opacity(1 - fade), 0.03)
        if drawn > 0.33 {
            let peak = (0.58 + 0.36 * 0.33, 0.79 - 0.36 * absorbance(0.33))
            context.fill(u.circle(peak.0, peak.1, 0.026 * Ease.outBack((drawn - 0.33) / 0.1)), with: .color(clay.opacity(1 - fade)))
        }
    }
}

/// An ELISA developing: across a strip of wells run as a dilution series,
/// colour comes up in a wave, deep clay where there's most antigen and
/// fading to nearly clear at the end of the row.
enum ELISA {
    static let duration = 4.0
    private static let strengths = [1.0, 0.78, 0.56, 0.38, 0.22, 0.1]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.4) / 0.5)
        u.stroke(context, u.capsule(0.5, 0.51, 0.9, 0.46, corner: 0.06), tint, 0.045)
        // The stop solution: a small pulse through every well at once.
        let stop = sin(.pi * Ease.clamp((t - 2.4) / 0.3))
        for y in [0.4, 0.62] {
            for (c, strength) in strengths.enumerated() {
                let x = 0.17 + 0.132 * Double(c)
                let colour = strength * Ease.inOut((t - 0.3 - 0.14 * Double(c)) / 1.5) * (1 - fade)
                if colour > 0 { context.fill(u.circle(x, y, 0.056 * (1 + 0.1 * stop)), with: .color(clay.opacity(colour))) }
                u.stroke(context, u.circle(x, y, 0.056), tint.opacity(0.5), 0.025)
            }
        }
    }
}

/// Casting a gel: molten agarose runs into the tray round the clay comb,
/// sets, and the comb lifts out to leave a row of wells.
enum GelCasting {
    static let duration = 4.4
    private static let wells = [0.27, 0.385, 0.5, 0.615, 0.73]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tray = u.capsule(0.5, 0.56, 0.8, 0.56, corner: 0.04)
        let poured = Ease.inOut((t - 0.2) / 1.3)
        let set = Ease.inOut((t - 1.6) / 0.6)
        let lifted = Ease.inOut((t - 2.5) / 0.6)
        let reset = Ease.inOut((t - 3.8) / 0.4)
        context.drawLayer { layer in
            layer.clip(to: tray)
            let front = 0.1 + 0.82 * poured
            let edge = stride(from: 0.26, through: 0.86, by: 0.03).map { y in (front + 0.02 * sin(y * 30 + t * 6) * (1 - set), y) }
            var gel = u.polyline([(0.0, 0.26)] + edge + [(0.0, 0.86)])
            gel.closeSubpath()
            layer.fill(gel, with: .color(tint.opacity((0.18 + 0.22 * set) * (1 - reset))))
            layer.blendMode = .destinationOut
            for x in wells {
                layer.fill(u.capsule(x, 0.4, 0.075, 0.035, corner: 0.012), with: .color(.black.opacity(lifted)))
            }
        }
        u.stroke(context, tray, tint, 0.045)
        let comb = max(1 - lifted, reset)
        let y = 0.4 - 0.3 * lifted * (1 - reset)
        context.fill(u.capsule(0.5, y, 0.7, 0.045, corner: 0.02), with: .color(clay.opacity(comb)))
        for x in [0.15, 0.85] { context.fill(u.capsule(x, y, 0.05, 0.1, corner: 0.02), with: .color(clay.opacity(comb))) }
    }
}

/// Spooling DNA: where the cold ethanol meets the sample, clay threads of
/// DNA come out of solution and wind onto a glass rod, which lifts them out.
enum DNASpooling {
    static let duration = 4.4
    private static let interface = 0.62
    private static let threads = [0.3, 0.38, 0.46, 0.56, 0.64, 0.7]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let beaker = u.line((0.22, 0.26), (0.24, 0.3), (0.24, 0.88), (0.76, 0.88), (0.76, 0.26))
        BenchShapes.fill(context, u, beaker, from: 0.38, tint.opacity(0.07))
        BenchShapes.fill(context, u, beaker, from: interface, tint.opacity(0.18))
        u.stroke(context, u.line((0.24, interface), (0.76, interface)), tint.opacity(0.5), 0.02)

        let down = 1 - Ease.inOut((t - 2.8) / 0.6) + Ease.inOut((t - 3.9) / 0.4)
        let tip = (0.54 + (0.5 - 0.54) * down, 0.22 + (interface - 0.22) * down)
        let reset = Ease.inOut((t - 3.9) / 0.4)
        var wound = 0.0
        for (k, x) in threads.enumerated() {
            let s = Double(k)
            let appear = Ease.clamp((t - 0.3 - 0.12 * s) / 0.4)
            let pull = Ease.inOut((t - 1.2 - 0.2 * s) / 0.6)
            wound += pull / Double(threads.count)
            guard appear > 0, pull < 1 else { continue }
            let strand = stride(from: -0.05, through: 0.05, by: 0.01).map { d -> (Double, Double) in
                let p = (x + d, interface + 0.012 * sin(d * 90 + s * 2 + t * 3))
                return (p.0 + (tip.0 - p.0) * pull, p.1 + (tip.1 - p.1) * pull)
            }
            u.stroke(context, u.polyline(strand), clay.opacity(appear * (1 - pull)), 0.025)
        }
        let rod = (tip.0 + 0.2, tip.1 - 0.62)
        u.stroke(context, u.line(tip, rod), tint, 0.035)
        if wound > 0, reset < 1 {
            let g = sqrt(wound)
            context.fill(u.ellipse(tip.0, tip.1 - 0.02, 0.1 * g, 0.075 * g), with: .color(clay.opacity(1 - reset)))
        }
        u.stroke(context, beaker, tint, 0.045)
    }
}

/// A Dounce homogenizer: the pestle drives down the tube, and each stroke
/// breaks the clay tissue into finer pieces until it's a fine suspension.
enum Homogenizer {
    static let duration = 4.0
    private static let start = 0.2, stroke = 1.05
    /// Pieces after each stroke, and how big they are.
    private static let pieces = [1, 3, 6, 12]
    private static let sizes = [0.075, 0.042, 0.03, 0.018]

    private static func head(_ t: Double) -> Double {
        let x = (t - start) / stroke
        guard x > 0, x < 3 else { return 0.36 }
        return 0.36 + 0.4 * (0.5 - 0.5 * cos(2 * .pi * x))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var glass = Path()
        glass.move(to: u.pt(0.38, 0.14))
        glass.addLine(to: u.pt(0.38, 0.8))
        glass.addQuadCurve(to: u.pt(0.62, 0.8), control: u.pt(0.5, 0.94))
        glass.addLine(to: u.pt(0.62, 0.14))
        BenchShapes.fill(context, u, glass, from: 0.3, tint.opacity(0.15))

        // Which pieces are showing: each stroke's bottom breaks them finer.
        let breaks = (0..<3).map { start + stroke * (Double($0) + 0.5) }
        for (level, count) in pieces.enumerated() {
            let arrive = level == 0 ? 1 - Ease.clamp((t - 3.6) / 0.3) : Ease.clamp((t - breaks[level - 1]) / 0.15)
            let leave = level < 3 ? Ease.clamp((t - breaks[level]) / 0.15) : Ease.clamp((t - 3.4) / 0.4)
            let shown = level == 0 ? 1 - leave * arrive : arrive * (1 - leave)
            guard shown > 0.01 else { continue }
            for i in 0..<count {
                let s = Double(level * 20 + i)
                let p = level == 0 ? (0.5, 0.74) : (0.43 + 0.14 * BenchShapes.rand(s), 0.34 + 0.44 * BenchShapes.rand(s + 50))
                let r = sizes[level] * shown
                if level == 0 {
                    let blob = (0..<7).map { j -> (Double, Double) in
                        let a = Double(j) * 2 * .pi / 7
                        let reach = r * (0.8 + 0.4 * BenchShapes.rand(Double(j) + 90))
                        return (p.0 + reach * cos(a), p.1 + reach * 0.8 * sin(a))
                    }
                    var chunk = u.polyline(blob)
                    chunk.closeSubpath()
                    context.fill(chunk, with: .color(clay))
                } else {
                    context.fill(u.circle(p.0, p.1, r), with: .color(clay))
                }
            }
        }
        let y = head(t)
        u.stroke(context, u.line((0.5, y - 0.9), (0.5, y)), tint, 0.05)
        context.fill(u.capsule(0.5, y + 0.02, 0.2, 0.08, corner: 0.035), with: .color(tint))
        u.stroke(context, glass, tint, 0.045)
    }
}

/// A probe sonicator: in pulses, ripples ring out from the probe's tip and
/// the clay cells round it burst, one after another.
enum Sonicator {
    static let duration = 4.0
    private static let pulses = [0.3, 1.5, 2.7]
    private static let cells: [(x: Double, y: Double, burst: Double)] = [
        (0.42, 0.68, 0.45), (0.58, 0.64, 0.75), (0.46, 0.8, 1.65), (0.54, 0.77, 1.95), (0.41, 0.52, 2.85), (0.6, 0.5, 3.1),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let outline = u.line((0.36, 0.1), (0.36, 0.7), (0.47, 0.9), (0.53, 0.9), (0.64, 0.7), (0.64, 0.1))
        BenchShapes.fill(context, u, outline, from: 0.34, tint.opacity(0.15))
        var body = outline
        body.closeSubpath()
        var liquid = context
        liquid.clip(to: body)
        liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, 0.34).y, width: u.side, height: u.side)))

        let on = pulses.reduce(0.0) { $0 + Ease.clamp((t - $1) / 0.05) - Ease.clamp((t - $1 - 0.8) / 0.05) }
        for p in pulses {
            for k in 0..<7 {
                let age = (t - p - 0.12 * Double(k)) / 0.35
                guard age > 0, age < 1 else { continue }
                u.stroke(liquid, u.circle(0.5, 0.52, 0.03 + 0.2 * age), tint.opacity(0.5 * (1 - age)), 0.025)
            }
        }
        let back = Ease.clamp((t - 3.6) / 0.3)
        for (k, c) in cells.enumerated() {
            let after = t - c.burst
            if after < 0 || back > 0 {
                liquid.fill(u.circle(c.x, c.y, 0.035 * (after < 0 ? 1 : back)), with: .color(clay))
            }
            guard after > 0, after < 0.8 else { continue }
            for j in 0..<3 {
                let a = Double(j) * 2.1 + Double(k)
                let d = 0.02 + 0.05 * Ease.out(after / 0.3)
                liquid.fill(u.circle(c.x + d * cos(a), c.y + d * sin(a), 0.014), with: .color(clay.opacity(1 - after / 0.8)))
            }
        }
        let jitter = 0.004 * sin(t * 90) * on
        context.fill(u.capsule(0.5 + jitter, 0.23, 0.07, 0.6, corner: 0.035), with: .color(tint))
        u.stroke(context, outline, tint, 0.045)
    }
}

/// Thawing a cryovial: the frozen vial dips into the water bath and swirls,
/// its frost melting away to leave the clay sample liquid, then lifts out.
enum CryovialThaw {
    static let duration = 4.4
    private static let surface = 0.56
    private static let frost: [(Double, Double)] = [(0.47, 0.46), (0.53, 0.54), (0.47, 0.62), (0.53, 0.7), (0.5, 0.78)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let dip = Ease.inOut((t - 0.2) / 0.5) - Ease.inOut((t - 3.2) / 0.5)
        let thaw = Ease.inOut((t - 0.8) / 1.8) - Ease.inOut((t - 3.8) / 0.5)
        let dx = 0.02 * sin(t * 5) * dip, dy = -0.3 * (1 - dip)

        var vial = context
        vial.translateBy(x: u.len(dx), y: u.len(dy))
        var glass = Path()
        glass.move(to: u.pt(0.42, 0.3))
        glass.addLine(to: u.pt(0.42, 0.76))
        glass.addQuadCurve(to: u.pt(0.58, 0.76), control: u.pt(0.5, 0.86))
        glass.addLine(to: u.pt(0.58, 0.3))
        BenchShapes.fill(vial, u, glass, from: 0.4, clay.opacity(0.55 + 0.45 * thaw))
        for (k, p) in frost.enumerated() {
            let r = 0.028 * (1 - thaw)
            guard r > 0.002 else { continue }
            for j in 0..<3 {
                let a = Double(j) * .pi / 3 + Double(k)
                u.stroke(vial, u.line((p.0 - r * cos(a), p.1 - r * sin(a)), (p.0 + r * cos(a), p.1 + r * sin(a))), tint, 0.018)
            }
        }
        u.stroke(vial, glass, tint, 0.04)
        vial.fill(u.capsule(0.5, 0.26, 0.2, 0.09, corner: 0.025), with: .color(tint))

        // The bath, drawn over the vial so what's under the water sits behind it.
        let bath = u.line((0.06, 0.38), (0.06, 0.92), (0.94, 0.92), (0.94, 0.38))
        let wave = stride(from: 0.06, through: 0.94, by: 0.02).map { x in (x, surface + 0.008 * sin(x * 25 + t * 4)) }
        var water = u.polyline(wave + [(0.94, 0.92), (0.06, 0.92)])
        water.closeSubpath()
        context.fill(water, with: .color(tint.opacity(0.12)))
        u.stroke(context, u.polyline(wave), tint.opacity(0.5), 0.025)
        for (k, at) in [0.45, 0.6].enumerated() {
            let age = (t - at) / 0.7
            guard age > 0, age < 1 else { continue }
            let w = 0.24 + 0.4 * age + 0.1 * Double(k)
            u.stroke(context, u.ellipse(0.5, surface, w, 0.05 + 0.04 * age), tint.opacity(0.6 * (1 - age)), 0.02)
        }
        for k in 0..<2 {
            let age = (t - 3.55 - 0.2 * Double(k)) / 0.35
            guard age > 0, age < 1 else { continue }
            context.fill(u.circle(0.5 + dx, 0.54 + dy + 0.1 * age * age, 0.014), with: .color(tint.opacity(1 - age)))
        }
        u.stroke(context, bath, tint, 0.045)
    }
}

/// Vacuum filtration: the pump draws the liquid down through the paper in a
/// Büchner funnel, drips gather in the flask below, and a clay cake is left
/// behind on the filter.
enum VacuumFiltration {
    static let duration = 4.4
    private static let plate = 0.36

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reset = Ease.inOut((t - 3.6) / 0.5)
        let drained = Ease.inOut((t - 0.4) / 2.2) * (1 - reset)
        let on = Ease.clamp((t - 0.3) / 0.2) * (1 - Ease.clamp((t - 2.8) / 0.3))

        let flask = u.line((0.45, 0.5), (0.45, 0.6), (0.24, 0.92), (0.76, 0.92), (0.55, 0.6), (0.55, 0.5))
        BenchShapes.fill(context, u, flask, from: 0.92 - 0.12 * drained, tint.opacity(0.3))
        u.stroke(context, flask, tint, 0.045)
        u.stroke(context, u.line((0.55, 0.55), (0.68, 0.55)), tint, 0.045)
        context.stroke(u.line((0.68, 0.55), (0.98, 0.55)), with: .color(tint.opacity(0.6)),
                       style: StrokeStyle(lineWidth: u.len(0.03), lineCap: .round,
                                          dash: [u.len(0.03), u.len(0.05)], dashPhase: -u.len(0.08) * (t * 3 * on)))

        // The slurry in the funnel, draining, and the cake it leaves.
        let cup = u.line((0.28, 0.16), (0.3, plate), (0.7, plate), (0.72, 0.16))
        let level = 0.2 + (plate - 0.2) * drained
        if level < plate - 0.005 { BenchShapes.fill(context, u, cup, from: level, tint.opacity(0.25)) }
        for k in 0..<10 {
            let s = Double(k)
            let home = (0.34 + 0.32 * BenchShapes.rand(s + 3), 0.22 + 0.12 * BenchShapes.rand(s + 11))
            let settled = Ease.clamp((drained - 0.1 * BenchShapes.rand(s)) / 0.7)
            let y = home.1 + (plate - 0.02 - home.1) * settled
            if settled < 1 { context.fill(u.circle(home.0, max(y, level + 0.015), 0.016), with: .color(clay)) }
        }
        if drained > 0 {
            let cake = 0.035 * drained
            context.fill(u.capsule(0.5, plate - 0.01 - cake / 2, 0.38, cake, corner: cake / 2), with: .color(clay))
        }
        if drained > 0.02, drained < 0.98 {
            let phase = (t * 4.5).truncatingRemainder(dividingBy: 1)
            let pool = 0.92 - 0.12 * drained
            context.fill(u.circle(0.5, 0.6 + (pool - 0.61) * phase * phase, 0.014), with: .color(tint.opacity(0.6)))
        }
        u.stroke(context, cup, tint, 0.045)
        u.stroke(context, u.line((0.3, plate), (0.47, 0.44), (0.47, 0.58)), tint, 0.04)
        u.stroke(context, u.line((0.7, plate), (0.53, 0.44), (0.53, 0.58)), tint, 0.04)
        context.fill(u.capsule(0.5, 0.5, 0.16, 0.05, corner: 0.015), with: .color(tint))
    }
}

/// A wash bottle: squeezed, it shoots a clay stream from its bent spout;
/// let go, it springs back; twice over.
enum WashBottle {
    static let duration = 3.6
    private static let squeezes = [0.35, 1.75]

    private static func stream(_ s: Double) -> (Double, Double) { (0.7 + 0.36 * s, 0.2 + 0.1 * s + 0.45 * s * s) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var squeeze = 0.0, used = 0.0
        for s in squeezes {
            squeeze += Ease.inOut((t - s) / 0.2) - Ease.inOut((t - s - 0.8) / 0.3)
            used += Ease.clamp((t - s - 0.1) / 0.7)
        }
        used *= 1 - Ease.inOut((t - 3.1) / 0.4)
        var body = Path()
        body.move(to: u.pt(0.34, 0.42))
        body.addQuadCurve(to: u.pt(0.28, 0.5), control: u.pt(0.28, 0.42))
        body.addQuadCurve(to: u.pt(0.28, 0.84), control: u.pt(0.28 + 0.1 * squeeze, 0.67))
        body.addQuadCurve(to: u.pt(0.34, 0.9), control: u.pt(0.28, 0.9))
        body.addLine(to: u.pt(0.58, 0.9))
        body.addQuadCurve(to: u.pt(0.64, 0.84), control: u.pt(0.64, 0.9))
        body.addQuadCurve(to: u.pt(0.64, 0.5), control: u.pt(0.64 - 0.1 * squeeze, 0.67))
        body.addQuadCurve(to: u.pt(0.58, 0.42), control: u.pt(0.64, 0.42))
        body.closeSubpath()
        var inside = context
        inside.clip(to: body)
        inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, 0.6 + 0.04 * used).y, width: u.side, height: u.side)), with: .color(clay))
        u.stroke(context, body, tint, 0.045)
        context.fill(u.capsule(0.46, 0.39, 0.16, 0.06, corner: 0.02), with: .color(tint))
        var spout = Path()
        spout.move(to: u.pt(0.46, 0.36))
        spout.addLine(to: u.pt(0.46, 0.22))
        spout.addQuadCurve(to: u.pt(0.58, 0.14), control: u.pt(0.46, 0.13))
        spout.addLine(to: u.pt(0.7, 0.2))
        u.stroke(context, spout, tint, 0.035)

        for s in squeezes {
            let head = Ease.out((t - s - 0.1) / 0.3)
            let tail = Ease.inOut((t - s - 0.8) / 0.35)
            guard head > 0, tail < 1 else { continue }
            let jet = stride(from: tail, through: head, by: 0.02).map(stream)
            if jet.count > 1 { u.stroke(context, u.polyline(jet), clay, 0.035) }
        }
    }
}
