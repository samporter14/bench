// SamplerScenes.swift
// ScienceStatus — a sampler of physics, chemistry and medicine. Each
// draws in a unit square (see `UnitSquare`): the setting in the tint, the
// particle, the reacting part or the cargo in clay.

import SwiftUI

/// Quantum tunnelling: a clay wave packet runs at a thin barrier; most of
/// it reflects, a faint part appears beyond, and gathers into a particle.
enum Tunneling {
    static let duration = 3.6
    private static let base = 0.6

    private static func packet(_ u: UnitSquare, centre: Double, amplitude: Double, t: Double) -> Path {
        u.polyline(stride(from: max(0.02, centre - 0.2), through: min(0.98, centre + 0.2), by: 0.005).map { x in
            (x, base - amplitude * exp(-pow((x - centre) / 0.07, 2)) * cos((x - centre) * 70 - t * 12))
        })
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, base), (0.98, base)), tint.opacity(0.3), 0.03)
        context.fill(u.capsule(0.56, 0.52, 0.035, 0.44, corner: 0.01), with: .color(tint))
        if t < 1.3 {
            u.stroke(context, packet(u, centre: 0.14 + 0.3 * Ease.inOut(t / 1.3), amplitude: 0.12, t: t), clay, 0.035)
        } else {
            let k = Ease.inOut((t - 1.3) / 1.2)
            u.stroke(context, packet(u, centre: 0.44 - 0.28 * k, amplitude: 0.11, t: t), clay, 0.035)
            let gather = Ease.clamp((t - 2.5) / 0.4)
            if gather < 1 {
                u.stroke(context, packet(u, centre: 0.66 + 0.18 * k, amplitude: 0.035, t: t), clay.opacity(1 - gather), 0.03)
            }
            if gather > 0 { context.fill(u.circle(0.84, base, 0.035 * Ease.outBack(gather)), with: .color(clay)) }
        }
    }
}

/// A gravitational-wave chirp: two compact objects spiral in, faster and
/// faster; the clay waveform beneath grows to a peak at the merger, then
/// rings down.
enum Chirp {
    static let duration = 4.0
    private static let merger = 2.8

    private static func phase(_ t: Double) -> Double { -24 * pow(max(0.0001, 1 - t / merger), 5.0 / 8) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = (0.5, 0.34)
        if t < merger {
            let r = 0.17 * pow(1 - t / merger, 0.25)
            let a = phase(t)
            for side in [0.0, Double.pi] {
                context.fill(u.circle(centre.0 + r * cos(a + side), centre.1 + r * 0.6 * sin(a + side), 0.04), with: .color(tint))
            }
        } else {
            context.fill(u.circle(centre.0, centre.1, 0.055), with: .color(tint))
            let ring = (t - merger) / 0.8
            if ring < 1 {
                for k in 0..<2 {
                    let r = 0.08 + 0.25 * min(1, ring + 0.3 * Double(k))
                    u.stroke(context, u.ellipse(centre.0, centre.1, 2 * r, 1.2 * r), tint.opacity(0.4 * (1 - ring)), 0.03)
                }
            }
        }
        u.stroke(context, u.line((0.06, 0.78), (0.94, 0.78)), tint.opacity(0.3), 0.025)
        let wave = stride(from: 0.0, through: min(t, duration), by: 0.01).map { s -> (Double, Double) in
            let x = 0.06 + 0.88 * s / duration
            let y: Double
            if s < merger {
                y = 0.78 + min(0.16, 0.025 * pow(max(0.02, 1 - s / merger), -0.3)) * sin(2 * phase(s))
            } else {
                y = 0.78 + 0.16 * exp(-(s - merger) * 7) * sin((s - merger) * 60)
            }
            return (x, y)
        }
        if wave.count > 1 { u.stroke(context, u.polyline(wave), clay, 0.035) }
    }
}

/// The SN2 umbrella flip: a clay nucleophile comes in from behind, the
/// leaving group goes out the front, and the three remaining bonds turn
/// inside out like an umbrella.
enum SN2 {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let come = Ease.inOut((t - 0.2) / 1.3)
        let flip = Ease.inOut((t - 1.3) / 1.0)
        let go = Ease.inOut((t - 1.7) / 0.9)
        let carbon = (0.5, 0.5)
        let lean = 1 - 2 * flip
        for (dx, dy) in [(0.1, -0.2), (0.1, 0.2), (0.14, 0.02)] {
            let end = (carbon.0 - dx * lean, carbon.1 + dy * (1 - 0.15 * abs(lean) + 0.15))
            u.stroke(context, u.line(carbon, end), tint, 0.045)
            context.fill(u.circle(end.0, end.1, 0.035), with: .color(tint))
        }
        let nucleophile = (0.06 + (0.3 - 0.06) * come, 0.5)
        let bond = Ease.clamp((t - 1.2) / 0.5)
        if bond > 0 { u.stroke(context, u.line(nucleophile, carbon), clay.opacity(bond), 0.045) }
        let leaving = (0.72 + 0.2 * go, 0.5)
        if go < 0.6 { u.stroke(context, u.line(carbon, leaving), tint.opacity(1 - go / 0.6), 0.045) }
        context.fill(u.circle(leaving.0, leaving.1, 0.055), with: .color(tint.opacity(1 - 0.5 * go)))
        context.fill(u.circle(carbon.0, carbon.1, 0.045), with: .color(tint))
        context.fill(u.circle(nucleophile.0, nucleophile.1, 0.05), with: .color(clay))
    }
}

/// Diels–Alder: a diene and a dienophile line up, two clay bonds form as
/// the double bonds shift, closing a six-membered ring, which then springs
/// open again.
enum DielsAlder {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let close = Ease.inOut((t - 0.5) / 1.2) * (1 - Ease.inOut((t - 3.0) / 0.8))
        let ring = Rings.hexagon((0.46, 0.5), 0.2)
        let centre = (0.46, 0.5)
        // Diene: top, upper left, lower left, bottom; dienophile on the right.
        let apart = 1 - close
        let diene = [ring[0], ring[5], ring[4], ring[3]].map { p in (p.0, p.1 + (p.1 - 0.5) * 0.15 * apart) }
        let dienophile = [ring[1], ring[2]].map { ($0.0 + 0.2 * apart, $0.1) }
        func inner(_ a: (Double, Double), _ b: (Double, Double), _ strength: Double) {
            guard strength > 0.02 else { return }
            let mid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
            let towards = (centre.0 - mid.0, centre.1 - mid.1)
            let length = max(hypot(towards.0, towards.1), 0.0001)
            let o = (towards.0 / length * 0.04, towards.1 / length * 0.04)
            let from = (a.0 + (b.0 - a.0) * 0.2 + o.0, a.1 + (b.1 - a.1) * 0.2 + o.1)
            let to = (a.0 + (b.0 - a.0) * 0.8 + o.0, a.1 + (b.1 - a.1) * 0.8 + o.1)
            u.stroke(context, u.line(from, to), tint.opacity(strength), 0.035)
        }
        u.stroke(context, u.polyline(diene), tint, 0.045)
        u.stroke(context, u.line(dienophile[0], dienophile[1]), tint, 0.045)
        inner(diene[0], diene[1], apart)
        inner(diene[2], diene[3], apart)
        inner(diene[1], diene[2], close)
        inner(dienophile[0], dienophile[1], apart)
        if close > 0.05 {
            u.stroke(context, u.line(diene[0], dienophile[0]), clay.opacity(close), 0.045)
            u.stroke(context, u.line(diene[3], dienophile[1]), clay.opacity(close), 0.045)
        }
    }
}

/// Crystal nucleation: molecules jostle about; the first few find the
/// right way round and lock into a clay seed, and the rest are drawn in to
/// an orderly lattice.
enum Nucleation {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<9 {
            let s = Double(k)
            let slot = (0.36 + 0.14 * Double(k % 3), 0.38 + 0.12 * Double(k / 3))
            let order = [4, 3, 5, 1, 7, 0, 2, 6, 8][k]
            let lock = Ease.outBack((t - 0.6 - 0.3 * Double(order)) / 0.35)
            let loose = (0.5 + 0.38 * sin(s * 2.3 + 0.8) + 0.02 * sin(t * 4 + s),
                         0.5 + 0.38 * cos(s * 1.7 + 0.3) + 0.02 * cos(t * 3.5 + s))
            let p = (loose.0 + (slot.0 - loose.0) * lock, loose.1 + (slot.1 - loose.1) * lock)
            let spin = (s * 47 + t * 60 * (1 - min(1, lock))) * (1 - min(1, lock))
            var m = context
            let at = u.pt(p.0, p.1)
            m.translateBy(x: at.x, y: at.y)
            m.rotate(by: .degrees(spin))
            let seed = order < 3 && lock >= 1
            m.fill(Path(roundedRect: CGRect(x: -u.len(0.05), y: -u.len(0.022), width: u.len(0.1), height: u.len(0.044)),
                        cornerRadius: u.len(0.022)), with: .color(seed ? clay : tint))
        }
    }
}

/// Red-cell oxygen exchange: a clay red cell squeezes along a capillary,
/// picking up oxygen beside the air sac and handing it over at the tissue.
enum OxygenExchange {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.28, 0.2, 0.13), tint)
        u.stroke(context, u.circle(0.72, 0.82, 0.12), tint)
        u.stroke(context, u.line((0.02, 0.44), (0.98, 0.44)), tint, 0.045)
        u.stroke(context, u.line((0.02, 0.58), (0.98, 0.58)), tint, 0.045)

        let x = 0.08 + 0.84 * Ease.inOut((t - 0.1) / 3.4)
        let squeeze = 1 + 0.12 * sin(x * 20)
        context.fill(u.ellipse(x, 0.51, 0.15 * squeeze, 0.09 / squeeze), with: .color(clay))
        for k in 0..<3 {
            let pick = Ease.inOut((t - 0.7 - 0.15 * Double(k)) / 0.5)
            let drop = Ease.inOut((t - 2.4 - 0.15 * Double(k)) / 0.5)
            let air = (0.24 + 0.04 * Double(k), 0.18 + 0.03 * Double(k % 2))
            let carried = (x - 0.04 + 0.04 * Double(k), 0.51)
            let tissue = (0.68 + 0.04 * Double(k), 0.82)
            var p = (air.0 + (carried.0 - air.0) * pick, air.1 + (carried.1 - air.1) * pick)
            if pick >= 1 { p = carried }
            if drop > 0 { p = (carried.0 + (tissue.0 - carried.0) * drop, carried.1 + (tissue.1 - carried.1) * drop) }
            u.stroke(context, u.circle(p.0, p.1, 0.02), tint, 0.025)
        }
    }
}

/// The immune synapse: a T cell meets its target, receptor pairs gather
/// into the middle of the contact, and clay granules move up and cross.
enum ImmuneSynapse {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let meet = Ease.inOut(t / 1.0)
        let tcell = (0.2 + 0.1 * meet, 0.5), target = (0.8 - 0.06 * meet, 0.5)
        u.stroke(context, u.circle(tcell.0, tcell.1, 0.2), tint)
        u.stroke(context, u.circle(target.0, target.1, 0.2), tint)
        let gather = Ease.inOut((t - 1.2) / 1.0)
        if meet >= 1 {
            for k in 0..<6 {
                let spread = [-0.14, -0.09, -0.04, 0.04, 0.09, 0.14][k]
                let y = 0.5 + spread * (1 - 0.6 * gather)
                u.stroke(context, u.line((0.485, y), (0.52, y)), tint, 0.03)
            }
        }
        for k in 0..<3 {
            let move = Ease.inOut((t - 2.2 - 0.15 * Double(k)) / 0.8)
            let cross = Ease.out((t - 3.1 - 0.1 * Double(k)) / 0.5)
            let start = (tcell.0 - 0.06 + 0.03 * Double(k), 0.44 + 0.06 * Double(k))
            var p = (start.0 + (0.46 - start.0) * move, start.1 + (0.5 - start.1) * move)
            if cross > 0 { p = (0.46 + 0.14 * cross, 0.5 + 0.05 * Double(k - 1) * cross) }
            context.fill(u.circle(p.0, p.1, 0.028), with: .color(clay.opacity(1 - 0.5 * cross)))
        }
    }
}

/// Nephron filtration: a mixed stream runs past the filter; small drops
/// pass through into the tubule, large proteins stay in the vessel, and
/// one useful clay molecule is taken back up.
enum Nephron {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.2), (0.98, 0.2)), tint, 0.045)
        u.stroke(context, u.line((0.02, 0.42), (0.3, 0.42)), tint, 0.045)
        u.stroke(context, u.line((0.7, 0.42), (0.98, 0.42)), tint, 0.045)
        var x = 0.3
        while x < 0.7 {
            u.stroke(context, u.line((x, 0.42), (x + 0.03, 0.42)), tint, 0.045)
            x += 0.06
        }
        u.stroke(context, u.line((0.02, 0.62), (0.98, 0.62)), tint, 0.045)
        u.stroke(context, u.line((0.02, 0.84), (0.98, 0.84)), tint, 0.045)

        for k in 0..<3 {
            let bx = ((t * 0.22 + 0.33 * Double(k)).truncatingRemainder(dividingBy: 1.1)) - 0.05
            u.stroke(context, u.circle(bx, 0.31, 0.04), tint, 0.03)
        }
        for k in 0..<4 {
            let age = (t - 0.3 - 0.6 * Double(k)) / 1.6
            guard age > 0, age < 1 else { continue }
            let x0 = 0.36 + 0.08 * Double(k)
            let fall = Ease.inOut(age / 0.5)
            let along = Ease.inOut((age - 0.5) / 0.5)
            context.fill(u.circle(x0 - 0.3 * along, 0.3 + (0.73 - 0.3) * fall, 0.017), with: .color(tint))
        }
        let down = Ease.inOut((t - 0.5) / 0.8)
        let slide = Ease.inOut((t - 1.3) / 0.9)
        let back = Ease.inOut((t - 2.4) / 0.8)
        let gx = 0.5 + 0.3 * slide
        let gy = 0.3 + (0.73 - 0.3) * down - (0.73 - 0.3) * back
        context.fill(u.circle(gx, gy, 0.024), with: .color(clay))
    }
}
