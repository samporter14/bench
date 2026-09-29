// WorldBatchIScenes.swift
// ScienceStatus — fields, waves, planets, weather and models: iron filings,
// standing waves, the JWST mirror, Saturn, an eruption, a tornado, a neural
// network and a Kaplan–Meier plot. Each draws in a unit square (see
// `UnitSquare`): the world in the tint, the field, the light or the signal
// in clay.

import SwiftUI

/// Iron filings: scattered at random round a bar magnet until a tap, when
/// they swing into the lines of its field; they shimmer, a second tap
/// shakes them, and they creep along the lines to crowd the poles.
enum IronFilings {
    static let duration = 4.8
    private static let filings: [(x: Double, y: Double, random: Double)] = (0..<150).compactMap { k in
        let s = Double(k)
        let x = 0.05 + 0.9 * BenchShapes.rand(s * 1.3), y = 0.08 + 0.84 * BenchShapes.rand(s * 2.9)
        guard !(abs(x - 0.5) < 0.2 && abs(y - 0.5) < 0.07) else { return nil }
        return (x, y, BenchShapes.rand(s * 7.1) * .pi)
    }

    /// The dipole field's direction at `p`, from poles at the magnet's ends.
    private static func field(_ p: (Double, Double)) -> Double {
        var bx = 0.0, by = 0.0
        for (pole, sign) in [((0.34, 0.5), 1.0), ((0.66, 0.5), -1.0)] {
            let dx = p.0 - pole.0, dy = p.1 - pole.1
            let r3 = pow(dx * dx + dy * dy, 1.5) + 1e-6
            bx += sign * dx / r3
            by += sign * dy / r3
        }
        return atan2(by, bx)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let align = Ease.inOut((t - 0.7) / 1.4)
        // Two taps, each setting the filings shivering.
        let tap = (t > 0.6 && t < 0.9) || (t > 2.7 && t < 3.0) ? 0.006 * sin(t * 90) : 0
        let creep = Ease.inOut((t - 2.2) / 2.2)
        for (k, f) in filings.enumerated() {
            var target = field((f.x, f.y))
            // Filings have no head or tail: turn the short way round.
            while target - f.random > .pi / 2 { target -= .pi }
            while f.random - target > .pi / 2 { target += .pi }
            let shimmer = 0.06 * align * sin(t * 5 + Double(k) * 1.7)
            let a = f.random + (target - f.random) * align + shimmer
            // After the second tap they creep along the lines towards the
            // nearer pole, crowding there.
            let pole = f.x < 0.5 ? (0.34, 0.5) : (0.66, 0.5)
            let along = (cos(target), sin(target))
            let toward = (pole.0 - f.x) * along.0 + (pole.1 - f.y) * along.1 > 0 ? 1.0 : -1.0
            let near = max(0, 1 - hypot(f.x - pole.0, f.y - pole.1) / 0.45)
            let x = f.x + toward * along.0 * 0.03 * creep * near + tap
            let y = f.y + toward * along.1 * 0.03 * creep * near
            let half = 0.016
            u.stroke(context, u.line((x - half * cos(a), y - half * sin(a)), (x + half * cos(a), y + half * sin(a))),
                     tint.opacity(0.85), 0.012)
        }
        context.fill(u.capsule(0.41, 0.5, 0.18, 0.1, corner: 0.012), with: .color(clay))
        context.fill(u.capsule(0.59, 0.5, 0.18, 0.1, corner: 0.012), with: .color(tint))
    }
}

/// Standing waves: a string pinned at both ends vibrates in its first,
/// second and third harmonics, the still nodes marked in clay.
enum StandingWaves {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let mode = min(3, Int(t / 1.6) + 1)
        let local = t - Double(mode - 1) * 1.6
        let fade = min(Ease.clamp(local / 0.2), 1 - Ease.clamp((local - 1.4) / 0.2))
        let swing = cos(t * 2 * .pi * (1.2 + 0.6 * Double(mode)))
        for x in [0.08, 0.92] {
            context.fill(u.capsule(x, 0.5, 0.03, 0.2, corner: 0.01), with: .color(tint))
        }
        // The envelope, faint, and the string itself.
        let envelope = stride(from: 0.0, through: 1.0, by: 0.01).map { s in (0.08 + 0.84 * s, 0.5 - 0.22 * sin(Double(mode) * .pi * s)) }
        let mirror = envelope.map { ($0.0, 1 - $0.1) }
        u.stroke(context, u.polyline(envelope), tint.opacity(0.15 * fade), 0.01)
        u.stroke(context, u.polyline(mirror), tint.opacity(0.15 * fade), 0.01)
        let string = stride(from: 0.0, through: 1.0, by: 0.01).map { s in
            (0.08 + 0.84 * s, 0.5 - 0.22 * sin(Double(mode) * .pi * s) * swing * fade)
        }
        u.stroke(context, u.polyline(string), tint, 0.025)
        for k in 0...mode {
            let x = 0.08 + 0.84 * Double(k) / Double(mode)
            context.fill(u.circle(x, 0.5, 0.022), with: .color(clay))
        }
    }
}

/// The JWST mirror: eighteen hexagonal segments, each off on its own, step
/// into place one by one; eighteen star images close into one clay star.
enum JWSTMirror {
    static let duration = 5.0
    private static let segments: [(Double, Double)] = {
        let s = 0.105
        let w = s * sqrt(3)
        var list: [(Double, Double)] = []
        for q in -2...2 {
            for r in -2...2 {
                let z = -q - r
                guard max(abs(q), abs(r), abs(z)) <= 2, !(q == 0 && r == 0) else { continue }
                list.append((0.42 + w * (Double(q) + Double(r) / 2), 0.55 + s * 1.5 * Double(r)))
            }
        }
        return list
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var focusSpread = 0.0
        for (k, c) in segments.enumerated() {
            let s = Double(k)
            let settle = Ease.inOut((t - 0.4 - 0.15 * s) / 0.5)
            let off = (0.02 * (BenchShapes.rand(s * 2.2) - 0.5) * (1 - settle), 0.02 * (BenchShapes.rand(s * 3.3) - 0.5) * (1 - settle))
            let turn = 12 * (BenchShapes.rand(s * 4.4) - 0.5) * (1 - settle)
            var hex = u.polyline((0..<6).map { j in Rings.offset((c.0 + off.0, c.1 + off.1), 0.095, 30 + 60 * Double(j) + turn) })
            hex.closeSubpath()
            context.fill(hex, with: .color(tint.opacity(0.18 + 0.5 * settle)))
            u.stroke(context, hex, tint, 0.014)
            // This segment's image of the star, drifting in as it aligns.
            let image = (0.86 + 0.12 * (BenchShapes.rand(s * 5.5) - 0.5) * (1 - settle), 0.16 + 0.12 * (BenchShapes.rand(s * 6.6) - 0.5) * (1 - settle))
            if settle < 1 { context.fill(u.circle(image.0, image.1, 0.008), with: .color(clay.opacity(0.8))) }
            focusSpread += settle
        }
        let focused = focusSpread / Double(segments.count)
        if focused > 0.95 {
            context.fill(Sparkles.star(u, 0.86, 0.16, 0.06 * Ease.outBack((focused - 0.95) / 0.05)), with: .color(clay))
        }
    }
}

/// Saturn: the planet turns inside its rings, a gap in them, a moon on its
/// way round; the far side of the rings passes behind.
enum Saturn {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let c = (0.5, 0.5), r = 0.2
        let tilt = -0.28
        func ring(_ radius: Double, _ width: Double, _ color: Color, front: Bool) {
            var arc = Path()
            let start = front ? 0.0 : 180.0
            arc.addArc(center: .zero, radius: u.len(radius), startAngle: .degrees(start), endAngle: .degrees(start + 180), clockwise: false)
            var tr = context
            let at = u.pt(c.0, c.1)
            tr.translateBy(x: at.x, y: at.y)
            tr.rotate(by: .radians(tilt))
            tr.scaleBy(x: 1, y: 0.3)
            tr.stroke(arc, with: .color(color), lineWidth: u.len(width) / 0.6)
        }
        // Behind the planet.
        ring(0.38, 0.04, tint.opacity(0.7), front: false)
        ring(0.31, 0.05, clay.opacity(0.8), front: false)
        // The planet and its drifting bands.
        context.fill(u.circle(c.0, c.1, r), with: .color(tint))
        var bands = context
        bands.clip(to: u.circle(c.0, c.1, r))
        for k in 0..<4 {
            let y = c.1 - 0.12 + 0.07 * Double(k)
            let drift = 0.02 * sin(t * 1.3 + Double(k))
            bands.stroke(u.line((c.0 - r + drift, y), (c.0 + r + drift, y + 0.03)), with: .color(Color.black.opacity(0.18)), lineWidth: u.len(0.02))
        }
        // In front.
        ring(0.38, 0.04, tint.opacity(0.7), front: true)
        ring(0.31, 0.05, clay.opacity(0.8), front: true)
        // A moon, going round.
        let a = t * 2 * .pi / duration
        let moon = (c.0 + 0.44 * cos(a), c.1 + 0.44 * sin(a) * 0.3 * cos(tilt) + 0.44 * cos(a) * sin(tilt) * 0.5)
        if sin(a) > 0 || hypot(moon.0 - c.0, moon.1 - c.1) > r {
            context.fill(u.circle(moon.0, moon.1, 0.02), with: .color(tint))
        }
    }
}

/// An eruption: the volcano throws up an ash column that spreads into an
/// umbrella, lava fountains and bombs arc out in clay, and a flow runs down.
enum Eruption {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let erupt = Ease.clamp((t - 0.3) / 0.4)
        // The ash column and umbrella.
        for k in 0..<16 where erupt > 0 {
            let s = Double(k)
            let age = ((t - 0.3) * 0.5 + s / 16).truncatingRemainder(dividingBy: 1)
            let rise = age
            let spread = max(0, rise - 0.6) / 0.4
            let side = BenchShapes.rand(s * 2.7) - 0.5
            let x = 0.5 + side * (0.06 + 0.5 * spread)
            let y = 0.46 - 0.34 * min(rise, 0.7) / 0.7
            context.fill(u.circle(x, y, 0.035 + 0.04 * rise), with: .color(tint.opacity(0.35 * (1 - 0.5 * spread))))
        }
        // The cone.
        var cone = u.polyline([(0.08, 0.9), (0.42, 0.5), (0.58, 0.5), (0.92, 0.9)])
        cone.closeSubpath()
        context.fill(cone, with: .color(tint))
        // The lava flow down the right flank.
        let flow = Ease.out((t - 1.2) / 2.8)
        if flow > 0 {
            let path = Smooth.curve([(0.56, 0.52), (0.64, 0.62), (0.7, 0.72), (0.8, 0.86)], samples: 6)
            let shown = Array(path.prefix(max(2, Int(Double(path.count) * flow))))
            u.stroke(context, u.polyline(shown), clay, 0.035)
        }
        // Bombs on their arcs.
        for k in 0..<6 where erupt > 0 {
            let s = Double(k)
            let age = ((t - 0.3) * 0.8 + s / 6).truncatingRemainder(dividingBy: 1)
            let vx = (BenchShapes.rand(s * 4.1) - 0.5) * 0.5
            let x = 0.5 + vx * age, y = 0.5 - 0.5 * age + 0.6 * age * age
            if y < 0.52 { context.fill(u.circle(x, y, 0.016), with: .color(clay)) }
        }
        context.fill(u.ellipse(0.5, 0.5, 0.16, 0.03), with: .color(clay.opacity(erupt)))
    }
}

/// A tornado: under a heavy cloud base the funnel lowers, sways and touches
/// down, a clay swirl of debris spinning where it meets the ground.
enum Tornado {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        CloudShape.draw(context, u, puffs: [(0.24, 0.14, 0.12), (0.44, 0.1, 0.14), (0.64, 0.12, 0.13), (0.82, 0.16, 0.1)], color: tint.opacity(0.9))
        u.stroke(context, u.line((0.04, 0.9), (0.96, 0.9)), tint.opacity(0.5), 0.02)
        let lower = Ease.inOut((t - 0.2) / 1.4)
        let reach = 0.2 + 0.7 * lower
        // The funnel: stacked, spinning rings, narrower going down.
        for k in 0..<14 {
            let f = Double(k) / 13
            let y = 0.2 + (reach - 0.2) * f
            let sway = 0.05 * sin(t * 1.4 + f * 2) * f
            let w = 0.2 * (1 - 0.8 * f) + 0.02
            let spin = t * 6 + f * 5
            u.stroke(context, u.ellipse(0.5 + sway + 0.01 * cos(spin), y, w, 0.03), tint.opacity(0.7), 0.018)
        }
        // Debris at the ground once it touches.
        let touch = Ease.clamp((t - 1.5) / 0.4)
        for k in 0..<10 where touch > 0 {
            let a = t * 5 + Double(k) * 0.63
            let r = 0.05 + 0.05 * BenchShapes.rand(Double(k))
            let sway = 0.05 * sin(t * 1.4 + 2)
            context.fill(u.circle(0.5 + sway + r * cos(a), 0.87 - 0.05 * BenchShapes.rand(Double(k) * 3) + 0.02 * sin(a), 0.011 * touch), with: .color(clay))
        }
    }
}

/// A neural network: activations flow from the inputs through two hidden
/// layers, edges carrying clay pulses, until one output lights up.
enum NeuralNetwork {
    static let duration = 4.8
    private static let layers = [3, 5, 5, 2]

    private static func node(_ layer: Int, _ k: Int) -> (Double, Double) {
        let n = layers[layer]
        return (0.14 + 0.24 * Double(layer), 0.5 + (Double(k) - Double(n - 1) / 2) * 0.16)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let wave = (t - 0.3) / 0.7
        for layer in 0..<(layers.count - 1) {
            for a in 0..<layers[layer] {
                for b in 0..<layers[layer + 1] {
                    let p = node(layer, a), q = node(layer + 1, b)
                    let weight = BenchShapes.rand(Double(layer * 100 + a * 10 + b) * 1.7)
                    u.stroke(context, u.line(p, q), tint.opacity(0.12 + 0.2 * weight), 0.01)
                    let f = wave - Double(layer)
                    if f > 0, f < 1, weight > 0.5 {
                        let x = p.0 + (q.0 - p.0) * f, y = p.1 + (q.1 - p.1) * f
                        context.fill(u.circle(x, y, 0.01), with: .color(clay.opacity(weight)))
                    }
                }
            }
        }
        for layer in 0..<layers.count {
            for k in 0..<layers[layer] {
                let p = node(layer, k)
                let lit = Ease.clamp(wave - Double(layer) + 0.2)
                let strength = layer == layers.count - 1 ? (k == 0 ? 1.0 : 0.2) : BenchShapes.rand(Double(layer * 10 + k) * 3.1)
                context.fill(u.circle(p.0, p.1, 0.04), with: .color(clay.opacity(lit * strength)))
                u.stroke(context, u.circle(p.0, p.1, 0.04), tint, 0.018)
            }
        }
    }
}

/// A Kaplan–Meier plot: two survival curves step down across the follow-up,
/// the treated arm in clay staying higher, censored patients ticked off.
enum KaplanMeier {
    static let duration = 5.0

    private static func steps(_ seed: Double, rate: Double) -> [(Double, Double)] {
        var y = 1.0, x = 0.0
        var points: [(Double, Double)] = [(0, 1)]
        for k in 0..<14 {
            x += 0.05 + 0.04 * BenchShapes.rand(seed + Double(k))
            points.append((x, y))
            y *= 1 - rate * (0.6 + 0.8 * BenchShapes.rand(seed + Double(k) * 2.3))
            points.append((x, y))
        }
        return points
    }

    private static let treated = steps(11, rate: 0.035)
    private static let control = steps(29, rate: 0.085)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.1, 0.12), (0.1, 0.86), (0.92, 0.86)), tint, 0.025)
        let reveal = Ease.inOut((t - 0.3) / 3.4)
        for (curve, color) in [(control, tint), (treated, clay)] {
            let scaled = curve.map { (0.1 + 0.8 * min($0.0, 1), 0.14 + 0.7 * (1 - $0.1)) }
            let shown = scaled.filter { $0.0 <= 0.1 + 0.8 * reveal }
            guard shown.count > 1 else { continue }
            u.stroke(context, u.polyline(shown), color, 0.028)
            // Censor ticks on some of the flat stretches.
            for (k, p) in shown.enumerated() where k % 6 == 3 {
                u.stroke(context, u.line((p.0 - 0.01, p.1 - 0.02), (p.0 - 0.01, p.1 + 0.02)), color, 0.015)
            }
        }
    }
}
