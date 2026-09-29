// LabBatchIScenes.swift
// ScienceStatus — the serological pipette, mortar and pestle, Parafilm, a
// dialysis bag, an MRI, a tablet dissolving, a chemical garden, benzene's
// resonance and ferrofluid. Each draws in a unit square (see `UnitSquare`):
// kit in the tint, the liquid, the sample or the moving electrons in clay.

import SwiftUI

/// A serological pipette on its pipette-aid: it sips clay media up from the
/// bottle, bubbles rising, carries it over to the flask and lets it run out.
enum SerologicalPipette {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The bottle on the left, the flask on the right.
        u.stroke(context, u.line((0.18, 0.62), (0.18, 0.9), (0.42, 0.9), (0.42, 0.62)), tint, 0.03)
        let bottleLevel = 0.7 + 0.08 * Ease.inOut((t - 0.4) / 1.6)
        context.fill(Path(CGRect(x: u.pt(0.19, 0).x, y: u.pt(0, bottleLevel).y, width: u.len(0.22), height: u.len(0.89 - bottleLevel))),
                     with: .color(clay.opacity(0.5)))
        u.stroke(context, u.polyline([(0.66, 0.62), (0.66, 0.72), (0.56, 0.9), (0.9, 0.9), (0.8, 0.72), (0.8, 0.62)]), tint, 0.03)
        let flaskLevel = 0.9 - 0.08 * Ease.inOut((t - 3.0) / 1.2)
        if flaskLevel < 0.899 {
            var pool = u.polyline([(0.6 + 0.12 * (0.9 - flaskLevel), flaskLevel), (0.86 - 0.12 * (0.9 - flaskLevel), flaskLevel), (0.892, 0.89), (0.568, 0.89)])
            pool.closeSubpath()
            context.fill(pool, with: .color(clay.opacity(0.5)))
        }
        // Where the pipette is: in the bottle, lifted across, in the flask.
        let x = Keyframes.value(t, [(2.0, 0.3), (2.7, 0.73)])
        let lift = Keyframes.value(t, [(1.9, 0), (2.2, 1), (2.5, 1), (2.8, 0)])
        let tipY = 0.84 - 0.2 * lift
        let top = tipY - 0.62
        u.stroke(context, u.line((x - 0.018, top + 0.16), (x - 0.018, tipY - 0.03), (x, tipY), (x + 0.018, tipY - 0.03), (x + 0.018, top + 0.16)), tint, 0.022)
        for k in 0..<6 {
            let y = top + 0.22 + 0.06 * Double(k)
            u.stroke(context, u.line((x - 0.018, y), (x - 0.004, y)), tint.opacity(0.6), 0.01)
        }
        // The liquid column: up while drawing, down while dispensing.
        let drawn = Ease.inOut((t - 0.4) / 1.4) * (1 - Ease.inOut((t - 3.0) / 1.2))
        let column = 0.36 * drawn
        if column > 0.005 {
            context.fill(Path(CGRect(x: u.pt(x - 0.013, 0).x, y: u.pt(0, tipY - 0.03 - column).y, width: u.len(0.026), height: u.len(column))),
                         with: .color(clay))
        }
        // The pipette-aid.
        context.fill(u.capsule(x + 0.02, top + 0.08, 0.14, 0.16, corner: 0.04), with: .color(tint))
        context.fill(u.capsule(x + 0.1, top + 0.2, 0.05, 0.12, corner: 0.02), with: .color(tint))
        // Bubbles in the bottle while it draws.
        for k in 0..<3 where t > 0.4 && t < 1.9 {
            let s = (t * 1.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            u.stroke(context, u.circle(0.3 + 0.03 * sin(Double(k) * 2), 0.88 - (0.88 - bottleLevel) * s, 0.012), tint.opacity(0.8), 0.01)
        }
    }
}

/// Mortar and pestle: leaves ground under liquid nitrogen, fog curling out,
/// the clay leaves breaking down to a clay powder.
enum MortarPestle {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let grind = Ease.inOut((t - 0.4) / 3.2)
        // The bowl.
        var bowl = Path()
        bowl.addArc(center: u.pt(0.5, 0.6), radius: u.len(0.3), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        u.stroke(context, bowl, tint, 0.06)
        u.stroke(context, u.line((0.16, 0.6), (0.84, 0.6)), tint, 0.03)
        context.fill(u.capsule(0.5, 0.92, 0.24, 0.04, corner: 0.02), with: .color(tint))
        // Leaves, breaking up as the pestle works.
        var inside = context
        var clip = Path()
        clip.addArc(center: u.pt(0.5, 0.6), radius: u.len(0.28), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        inside.clip(to: clip)
        for k in 0..<6 {
            let s = Double(k)
            let p = (0.34 + 0.06 * s, 0.72 + 0.06 * sin(s * 2.1))
            let leaf = 1 - Ease.clamp(grind * 1.6 - 0.1 * s)
            if leaf > 0 {
                var l = inside
                let at = u.pt(p.0, p.1)
                l.translateBy(x: at.x, y: at.y)
                l.rotate(by: .radians(s * 1.1))
                l.fill(Path(ellipseIn: CGRect(x: -u.len(0.05) * leaf, y: -u.len(0.02) * leaf, width: u.len(0.1) * leaf, height: u.len(0.04) * leaf)), with: .color(clay))
            }
        }
        let powder = Int(40 * grind)
        for k in 0..<powder {
            let s = Double(k)
            let a = Double.pi * (0.1 + 0.8 * BenchShapes.rand(s * 2.3))
            let r = 0.2 + 0.07 * BenchShapes.rand(s * 4.9)
            inside.fill(u.circle(0.5 + r * cos(a), 0.6 + r * sin(a) * 0.9, 0.008), with: .color(clay))
        }
        // The pestle, circling as it grinds.
        let a = t * 4
        let head = (0.5 + 0.1 * cos(a), 0.78 + 0.02 * sin(a))
        u.stroke(context, u.line(head, (0.66 + 0.06 * cos(a), 0.2)), tint, 0.06)
        context.fill(u.circle(head.0, head.1, 0.04), with: .color(tint))
        // Nitrogen fog curling up over the rim.
        for k in 0..<7 {
            let s = (t * 0.35 + Double(k) / 7).truncatingRemainder(dividingBy: 1)
            let x = 0.24 + 0.52 * BenchShapes.rand(Double(k) * 3.7) + 0.04 * sin(s * 6 + Double(k))
            context.fill(u.circle(x, 0.56 - 0.3 * s, 0.03 + 0.04 * s), with: .color(tint.opacity(0.22 * (1 - s))))
        }
    }
}

/// Parafilm, as it behaves: pulled between two tabs the strip grows longer,
/// thinner and clearer; one end is pressed to the flask's cap where it meets
/// the neck, and the rest is wound round that seam under tension, the tail
/// going behind and coming back across the front, laying a band a little
/// higher over the cap each pass as it shortens, until the end is pressed
/// down.
enum Parafilm {
    static let duration = 4.8
    /// The cap and the seam below it, which the film seals.
    private static let lid = (left: 0.38, right: 0.62, x: 0.5, seam: 0.37)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.polyline([(0.42, 0.34), (0.42, 0.5), (0.22, 0.9), (0.78, 0.9), (0.58, 0.5), (0.58, 0.34)]), tint, 0.035)
        var broth = u.polyline([(0.3, 0.74), (0.22, 0.9), (0.78, 0.9), (0.7, 0.74)])
        broth.closeSubpath()
        context.fill(broth, with: .color(clay.opacity(0.4)))
        // The cap over the flask's mouth, drawn open so the film shows on it.
        u.stroke(context, u.capsule(lid.x, 0.31, lid.right - lid.left, 0.1, corner: 0.02), tint, 0.035)

        let stretch = Ease.inOut((t - 0.3) / 0.9)
        let carry = Ease.inOut((t - 1.3) / 0.45)
        let wind = Ease.inOut((t - 1.8) / 2.0)
        let passes = 3.0
        // Stretching: longer, thinner, clearer.
        let length = 0.2 + 0.46 * stretch
        let thick = 0.05 - 0.022 * stretch
        let film = tint.opacity(0.7 - 0.3 * stretch)
        if carry < 1 {
            let y = 0.12 + (lid.seam - 0.12) * carry
            let left = 0.5 - length / 2 + (lid.left - (0.5 - length / 2)) * carry
            context.fill(u.capsule(left + length / 2, y, length, thick, corner: 0.01), with: .color(film))
            context.fill(u.capsule(left - 0.02, y, 0.04, 0.06, corner: 0.012), with: .color(tint))
            context.fill(u.capsule(left + length + 0.02, y, 0.04, 0.06, corner: 0.012), with: .color(tint))
            return
        }
        // Winding: each pass lays a band across the seam, a little higher,
        // over the cap's skirt.
        let laid = passes * wind
        for k in 0..<Int(laid) {
            let y = lid.seam - 0.028 * Double(k)
            u.stroke(context, u.line((lid.left - 0.005, y + 0.01), (lid.right + 0.005, y - 0.01)), film, thick)
        }
        // The taut tail from the neck to the tab, orbiting the neck and
        // shortening as it goes; behind the neck it's dimmer.
        if wind < 1 {
            let phase = laid * 2 * .pi
            let y = lid.seam - 0.028 * laid
            let reach = 0.06 + (length - 0.06) * (1 - wind)
            let front = cos(phase) > 0
            let from = (lid.x + 0.12 * sin(phase), y)
            let tab = (lid.x + (0.12 + reach) * sin(phase), y - 0.02 * cos(phase))
            u.stroke(context, u.line(from, tab), film.opacity(front ? 1 : 0.45), thick)
            context.fill(u.capsule(tab.0, tab.1, 0.04, 0.06, corner: 0.012), with: .color(tint.opacity(front ? 1 : 0.5)))
        } else {
            let press = Ease.clamp((t - 3.9) / 0.3)
            context.fill(Sparkles.star(u, 0.68, 0.34, 0.035 * press * (1 - Ease.clamp((t - 4.4) / 0.3))), with: .color(clay))
        }
    }
}

/// A dialysis bag: small clay molecules leak out through the membrane into
/// the stirred beaker; the big ones stay put.
enum DialysisBag {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.14, 0.2), (0.14, 0.9), (0.86, 0.9), (0.86, 0.2)), tint, 0.035)
        context.fill(Path(CGRect(x: u.pt(0.15, 0).x, y: u.pt(0, 0.3).y, width: u.len(0.7), height: u.len(0.59))), with: .color(tint.opacity(0.07)))
        // The bag on its clip.
        let bag = u.capsule(0.5, 0.52, 0.2, 0.48, corner: 0.1)
        u.stroke(context, bag, tint, 0.025)
        context.fill(u.capsule(0.5, 0.26, 0.26, 0.04, corner: 0.01), with: .color(tint))
        for k in 0..<5 {
            let p = (0.46 + 0.08 * BenchShapes.rand(Double(k) * 2.2), 0.36 + 0.3 * BenchShapes.rand(Double(k) * 5.5))
            u.stroke(context, u.circle(p.0, p.1, 0.028), tint, 0.02)
        }
        // Small molecules diffusing out.
        let out = Ease.out((t - 0.4) / 3.8)
        for k in 0..<22 {
            let s = Double(k)
            let start = (0.44 + 0.12 * BenchShapes.rand(s * 1.7), 0.32 + 0.4 * BenchShapes.rand(s * 3.1))
            let end = (0.18 + 0.64 * BenchShapes.rand(s * 4.3), 0.34 + 0.52 * BenchShapes.rand(s * 6.7))
            let leave = k % 5 == 0 ? 0 : out
            let wobble = 0.01 * sin(t * 3 + s)
            context.fill(u.circle(start.0 + (end.0 - start.0) * leave + wobble, start.1 + (end.1 - start.1) * leave, 0.011), with: .color(clay))
        }
        // The stir bar turning.
        let a = t * 5
        u.stroke(context, u.line((0.5 - 0.06 * cos(a), 0.86 - 0.012 * sin(a)), (0.5 + 0.06 * cos(a), 0.86 + 0.012 * sin(a))), tint, 0.035)
    }
}

/// An MRI: the table slides into the bore, the coils pulse, and axial slices
/// of the head stack up one by one.
enum MRIScan {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let slide = Ease.inOut((t - 0.2) / 1.3)
        // The table and the patient, head first into the bore.
        let shift = -0.2 * slide
        context.fill(u.capsule(0.62 + shift, 0.66, 0.6, 0.04, corner: 0.02), with: .color(tint.opacity(0.6)))
        context.fill(u.capsule(0.66 + shift, 0.6, 0.44, 0.08, corner: 0.04), with: .color(tint.opacity(0.9)))
        context.fill(u.circle(0.42 + shift, 0.58, 0.05), with: .color(tint.opacity(0.9)))
        // The bore: a thick ring, pulsing clay while it scans.
        u.stroke(context, u.circle(0.3, 0.58, 0.2), tint, 0.08)
        let scanning = t > 1.6 && t < 4.4
        if scanning {
            let pulse = 0.5 + 0.5 * sin(t * 18)
            u.stroke(context, u.circle(0.3, 0.58, 0.15), clay.opacity(0.3 + 0.5 * pulse), 0.02)
        }
        // The slices, stacking at the top right.
        let slices = scanning ? Int((t - 1.6) / 0.45) + 1 : (t >= 4.4 ? 7 : 0)
        for k in 0..<min(7, slices) {
            let y = 0.34 - 0.04 * Double(k)
            let w = 0.24 - 0.012 * abs(Double(k) - 3)
            u.stroke(context, u.ellipse(0.74, y, w, 0.06), tint, 0.018)
            context.fill(u.ellipse(0.74, y, w * 0.5, 0.025), with: .color(clay.opacity(0.7)))
        }
    }
}

/// A tablet dissolving: it drops into the water and sinks, its coating
/// cracks, and the clay drug disperses up and out as it shrinks.
enum TabletDissolving {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.22, 0.24), (0.26, 0.9), (0.74, 0.9), (0.78, 0.24)), tint, 0.035)
        let water = 0.34
        context.fill(u.polyline([(0.235, water), (0.765, water), (0.74, 0.89), (0.26, 0.89)]).close(), with: .color(tint.opacity(0.08)))
        u.stroke(context, u.line((0.235, water), (0.765, water)), tint.opacity(0.5), 0.015)
        // The tablet: falls, sinks, shrinks.
        let fall = Ease.inOut((t - 0.1) / 0.9)
        let y = 0.12 + (0.84 - 0.12) * fall
        let shrink = 1 - 0.8 * Ease.inOut((t - 1.6) / 2.6)
        let crack = Ease.clamp((t - 1.2) / 0.4)
        context.fill(u.capsule(0.5, y, 0.14 * shrink, 0.06 * shrink, corner: 0.03 * shrink), with: .color(clay))
        if crack > 0, shrink > 0.3 {
            u.stroke(context, u.capsule(0.5, y, 0.14 * shrink + 0.01, 0.06 * shrink + 0.01, corner: 0.035 * shrink), tint.opacity(1 - crack), 0.018)
        } else if crack == 0 {
            u.stroke(context, u.capsule(0.5, y, 0.15, 0.07, corner: 0.035), tint, 0.018)
        }
        // The drug spreading out through the water.
        let spread = Ease.out((t - 1.5) / 3.0)
        for k in 0..<30 where spread > 0 {
            let s = Double(k)
            let a = Double.pi + Double.pi * BenchShapes.rand(s * 2.9)
            let r = 0.36 * spread * (0.3 + 0.7 * BenchShapes.rand(s * 5.3))
            let p = (0.5 + r * cos(a), min(0.87, 0.84 + r * 1.2 * sin(a)))
            context.fill(u.circle(p.0, max(water + 0.02, p.1), 0.009), with: .color(clay.opacity(0.85 * (1 - 0.4 * spread))))
        }
        // Fizz.
        for k in 0..<4 where t > 1.0 && t < 4.2 {
            let s = (t * 0.9 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
            u.stroke(context, u.circle(0.44 + 0.04 * Double(k), 0.82 - (0.82 - water) * s, 0.01), tint.opacity(0.7 * (1 - s)), 0.01)
        }
    }
}

private extension Path {
    /// The path with its last subpath closed.
    func close() -> Path {
        var copy = self
        copy.closeSubpath()
        return copy
    }
}

/// A chemical garden: seed crystals in waterglass send hollow tubes up, each
/// with a clay tip still growing, some forking on the way.
enum ChemicalGarden {
    static let duration = 5.2
    private static let seeds: [(x: Double, height: Double, lean: Double, delay: Double)] = [
        (0.28, 0.5, -0.04, 0.2), (0.4, 0.62, 0.02, 0.5), (0.52, 0.42, 0.05, 0.3), (0.62, 0.66, -0.03, 0.7), (0.72, 0.48, 0.04, 0.4),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.18, 0.1), (0.18, 0.9), (0.82, 0.9), (0.82, 0.1)), tint, 0.035)
        context.fill(Path(CGRect(x: u.pt(0.19, 0).x, y: u.pt(0, 0.16).y, width: u.len(0.62), height: u.len(0.73))), with: .color(tint.opacity(0.06)))
        for (k, seed) in seeds.enumerated() {
            let grow = Ease.out((t - seed.delay) / 3.2)
            context.fill(u.capsule(seed.x, 0.87, 0.05, 0.03, corner: 0.006), with: .color(clay))
            guard grow > 0 else { continue }
            let length = seed.height * grow
            let tube = stride(from: 0.0, through: 1.0, by: 0.05).map { s -> (Double, Double) in
                (seed.x + seed.lean * s * 3 * length + 0.008 * sin(s * 20 + Double(k)), 0.86 - length * s)
            }
            u.stroke(context, u.polyline(tube), tint, 0.035)
            u.stroke(context, u.polyline(tube), tint.opacity(0.3), 0.012)
            let tip = tube.last!
            context.fill(u.circle(tip.0, tip.1, 0.018), with: .color(clay))
            if k % 2 == 1, grow > 0.5 {
                let fork = tube[tube.count / 2]
                let f = Ease.out((grow - 0.5) / 0.5)
                let end = (fork.0 + 0.08 * f * (k == 1 ? -1 : 1), fork.1 - 0.12 * f)
                u.stroke(context, u.line(fork, end), tint, 0.028)
                context.fill(u.circle(end.0, end.1, 0.014), with: .color(clay))
            }
        }
    }
}

/// Benzene's resonance: the ring's three double bonds shift round by one,
/// and back, and in between blur into the clay circle of the shared ring.
enum BenzeneResonance {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let r = 0.24
        let corners = (0..<6).map { k in Rings.offset((0.5, 0.5), r, 30 + 60 * Double(k)) }
        // Hydrogens out from each carbon.
        for c in corners {
            let a = atan2(c.1 - 0.5, c.0 - 0.5)
            u.stroke(context, u.line((0.5 + (r + 0.03) * cos(a), 0.5 + (r + 0.03) * sin(a)), (0.5 + (r + 0.11) * cos(a), 0.5 + (r + 0.11) * sin(a))), tint.opacity(0.6), 0.022)
            context.fill(u.circle(0.5 + (r + 0.13) * cos(a), 0.5 + (r + 0.13) * sin(a), 0.022), with: .color(tint.opacity(0.6)))
        }
        var ring = u.polyline(corners)
        ring.closeSubpath()
        u.stroke(context, ring, tint, 0.035)
        // Which Kekulé form shows: one, the shared ring, the other, back.
        let phase = t.truncatingRemainder(dividingBy: duration) / duration
        let first = 1 - Ease.clamp((phase - 0.18) / 0.1) + Ease.clamp((phase - 0.9) / 0.1)
        let second = Ease.clamp((phase - 0.5) / 0.1) * (1 - Ease.clamp((phase - 0.68) / 0.1))
        let shared = max(0, 1 - first - second)
        for k in 0..<6 {
            let a = corners[k], b = corners[(k + 1) % 6]
            let inset = 0.72
            let p = (0.5 + (a.0 - 0.5) * inset, 0.5 + (a.1 - 0.5) * inset)
            let q = (0.5 + (b.0 - 0.5) * inset, 0.5 + (b.1 - 0.5) * inset)
            let weight = k % 2 == 0 ? first : second
            if weight > 0.01 { u.stroke(context, u.line(p, q), clay.opacity(weight), 0.035) }
        }
        if shared > 0.01 { u.stroke(context, u.circle(0.5, 0.5, r * 0.62), clay.opacity(shared), 0.035) }
        for c in corners { context.fill(u.circle(c.0, c.1, 0.03), with: .color(tint)) }
    }
}

/// Ferrofluid: a clay magnet rises under the dish and the black puddle
/// stands up in spikes, then settles flat as it drops away.
enum Ferrofluid {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let near = Keyframes.value(t, [(0.3, 0), (1.5, 1), (3.4, 1), (4.4, 0)])
        u.stroke(context, u.ellipse(0.5, 0.66, 0.8, 0.2), tint, 0.03)
        context.fill(u.ellipse(0.5, 0.66, 0.56 + 0.04 * near, 0.12), with: .color(tint))
        // Spikes: a back row, then a front row, each taller as the magnet nears.
        for (y, count, scale) in [(0.63, 6, 0.8), (0.69, 7, 1.0)] {
            for k in 0..<count {
                let x = 0.5 + (Double(k) - Double(count - 1) / 2) * 0.075
                let fromCentre = abs(x - 0.5) / 0.3
                let height = 0.3 * scale * near * (1 - 0.6 * fromCentre * fromCentre) * (0.95 + 0.05 * sin(t * 7 + Double(k)))
                guard height > 0.005 else { continue }
                var spike = u.polyline([(x - 0.03, y), (x, y - height), (x + 0.03, y)])
                spike.closeSubpath()
                context.fill(spike, with: .color(tint))
            }
        }
        context.fill(u.capsule(0.5, 0.94 - 0.08 * near, 0.22, 0.07, corner: 0.012), with: .color(clay))
    }
}

/// A round coverslip, seen from above: forceps carry it in tilted, lower it
/// onto the clay drop of mountant on the slide, the drop spreads out under
/// it into a disc, and the forceps let go and draw back.
enum RoundCoverslip {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The slide, with its frosted label end.
        u.stroke(context, u.capsule(0.5, 0.6, 0.84, 0.34, corner: 0.02), tint, 0.03)
        context.fill(u.capsule(0.16, 0.6, 0.14, 0.32, corner: 0.012), with: .color(tint.opacity(0.35)))
        for k in 0..<3 {
            u.stroke(context, u.line((0.11, 0.53 + 0.05 * Double(k)), (0.2, 0.53 + 0.05 * Double(k))), tint.opacity(0.5), 0.01)
        }
        let centre = (0.56, 0.6)
        // The drop, then the disc it spreads into under the coverslip.
        let spread = Ease.out((t - 2.5) / 0.9)
        context.fill(u.circle(centre.0, centre.1, 0.03 + 0.1 * spread), with: .color(clay.opacity(0.9 - 0.25 * spread)))
        // The coverslip: carried in from the upper right, tilted (an ellipse),
        // flattening to a circle as it comes down.
        let carry = Ease.inOut((t - 0.3) / 1.3)
        let lower = Ease.inOut((t - 1.7) / 0.8)
        let tilt = 1 - lower
        let p = (centre.0 + 0.28 * (1 - carry), centre.1 - 0.4 * (1 - carry) - 0.04 * tilt)
        let r = 0.13
        let slip = u.ellipse(p.0, p.1, 2 * r * (1 - 0.35 * tilt), 2 * r)
        context.fill(slip, with: .color(tint.opacity(0.12)))
        u.stroke(context, slip, tint, 0.02)
        // The forceps: two prongs meeting at the coverslip's edge, then
        // opening and drawing back once it is down.
        let release = Ease.inOut((t - 2.7) / 0.4)
        let back = Ease.inOut((t - 3.1) / 0.8)
        let grip = (p.0 + r * (1 - 0.35 * tilt) * 0.9 + 0.3 * back, p.1 - 0.02 - 0.3 * back)
        let handle = (grip.0 + 0.3, grip.1 - 0.28)
        let open = 0.012 + 0.03 * release
        for side in [-1.0, 1.0] {
            let tip = (grip.0 + side * open * 0.7, grip.1 + side * open)
            u.stroke(context, u.line(tip, (handle.0 + side * 0.03, handle.1 + side * 0.02)), tint, 0.03)
        }
    }
}
