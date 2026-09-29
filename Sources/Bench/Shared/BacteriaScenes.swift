// BacteriaScenes.swift
// ScienceStatus — bacteria worth watching: a magnetotactic spirillum, an
// Anabaena filament, Myxococcus building a fruiting body, Caulobacter
// dividing, Streptomyces sporulating and Bdellovibrio hunting. Each draws
// in a unit square (see `UnitSquare`): cells in the tint, what makes the
// species remarkable in clay.

import SwiftUI

/// A magnetotactic bacterium: a spiral cell with a chain of clay magnetosomes
/// down its middle. The magnet below turns an eighth, and the cell turns with
/// the field.
enum Magnetospirillum {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let turn = Ease.inOut((t - 1.8) / 0.9)
        let heading = -turn * .pi / 4
        // The magnet, turning a quarter.
        var magnet = context
        let pivot = u.pt(0.5, 0.86)
        magnet.translateBy(x: pivot.x, y: pivot.y)
        magnet.rotate(by: .radians(heading))
        magnet.translateBy(x: -pivot.x, y: -pivot.y)
        magnet.fill(u.capsule(0.42, 0.86, 0.16, 0.07, corner: 0.01), with: .color(clay))
        magnet.fill(u.capsule(0.58, 0.86, 0.16, 0.07, corner: 0.01), with: .color(tint))
        // Faint field lines along the magnet's axis.
        for k in -1...1 {
            let offset = 0.2 * Double(k)
            let a = (0.5 + offset * sin(-heading) - 0.45 * cos(heading), 0.42 + offset * cos(heading) - 0.45 * sin(heading))
            let b = (0.5 + offset * sin(-heading) + 0.45 * cos(heading), 0.42 + offset * cos(heading) + 0.45 * sin(heading))
            u.stroke(context, u.line(a, b), tint.opacity(0.15), 0.01)
        }
        // The cell: swims along its heading, the spiral body undulating.
        let travel = 0.06 * sin(t * 1.3)
        let centre = (0.5 + travel * cos(heading), 0.42 + travel * sin(heading))
        let body = stride(from: -1.0, through: 1.0, by: 0.04).map { s -> (Double, Double) in
            let along = 0.3 * s, across = 0.035 * sin(s * 3 * .pi - t * 8)
            return (centre.0 + along * cos(heading) - across * sin(heading), centre.1 + along * sin(heading) + across * cos(heading))
        }
        u.stroke(context, u.polyline(body), tint.opacity(0.9), 0.04)
        for k in 0..<7 {
            let along = -0.15 + 0.05 * Double(k)
            context.fill(u.capsule(centre.0 + along * cos(heading), centre.1 + along * sin(heading), 0.034, 0.034, corner: 0.006),
                         with: .color(clay))
        }
        // A flagellum at each end.
        for end in [-1.0, 1.0] {
            let tail = stride(from: 0.0, through: 1.0, by: 0.1).map { s -> (Double, Double) in
                let along = end * (0.3 + 0.12 * s), across = 0.02 * sin(s * 10 - t * 14)
                return (centre.0 + along * cos(heading) - across * sin(heading), centre.1 + along * sin(heading) + across * cos(heading))
            }
            u.stroke(context, u.polyline(tail), tint.opacity(0.7), 0.014)
        }
    }
}

/// Anabaena: a gently curving chain of bead cells glides along; a clay,
/// thick-walled heterocyst fixes nitrogen and passes it to its neighbours,
/// and a new cell divides at the growing end.
enum Anabaena {
    static let duration = 4.8
    private static let cells = 13, heterocyst = 6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let glide = 0.03 * sin(t * 1.2)
        let grow = Ease.inOut((t - 2.2) / 1.2)
        let count = cells + (grow >= 1 ? 1 : 0)
        func centre(_ k: Double) -> (Double, Double) {
            let s = k / Double(cells)
            return (0.06 + 0.88 * s + glide, 0.52 + 0.14 * sin(s * .pi * 1.4 + 0.4 + t * 0.6))
        }
        for k in 0..<count {
            let p = centre(Double(k))
            if k == heterocyst {
                context.fill(u.circle(p.0, p.1, 0.042), with: .color(clay.opacity(0.35)))
                u.stroke(context, u.circle(p.0, p.1, 0.042), clay, 0.03)
                u.stroke(context, u.circle(p.0, p.1, 0.056), clay.opacity(0.5), 0.012)
            } else {
                context.fill(u.circle(p.0, p.1, 0.034), with: .color(tint))
            }
        }
        // The dividing end cell: a waist that pinches in.
        if grow > 0, grow < 1 {
            let p = centre(Double(cells))
            let w = 0.034 * (0.5 + 0.5 * grow)
            context.fill(u.circle(p.0 - 0.02 * grow, p.1, w), with: .color(tint))
            context.fill(u.circle(p.0 + 0.02 * grow, p.1, w), with: .color(tint))
        }
        // Nitrogen in, fixed nitrogen out to the neighbours.
        let hp = centre(Double(heterocyst))
        for k in 0..<3 {
            let s = (t * 0.7 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let inbound = (hp.0 - 0.1 + 0.1 * s, hp.1 - 0.16 + 0.16 * s)
            u.stroke(context, u.line((inbound.0 - 0.01, inbound.1), (inbound.0 + 0.01, inbound.1)), tint.opacity(1 - s), 0.016)
            for side in [-1.0, 1.0] {
                let q = centre(Double(heterocyst) + side * (0.6 + 1.6 * s))
                context.fill(u.circle(q.0, q.1 - 0.05, 0.01), with: .color(clay.opacity(1 - s)))
            }
        }
    }
}

/// Myxococcus: rods stream in from all sides, spiralling into one spot, and
/// a mound rises there into a fruiting body full of clay spores.
enum Myxococcus {
    static let duration = 5.0
    private static let rods = 34

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = (0.5, 0.56)
        var arrived = 0
        for k in 0..<rods {
            let s = Double(k)
            let start = 0.1 + 0.08 * BenchShapes.rand(s * 2.3)
            let progress = Ease.inOut((t - start - 0.08 * s) / 2.6)
            if progress >= 1 { arrived += 1; continue }
            let a0 = BenchShapes.rand(s * 4.7) * 2 * .pi
            let r = 0.42 * (1 - progress) + 0.04
            let a = a0 + 2.4 * progress
            let p = (centre.0 + r * cos(a), centre.1 + 0.8 * r * sin(a))
            let heading = a + .pi / 2 + 0.6
            let half = 0.03
            u.stroke(context, u.line((p.0 - half * cos(heading), p.1 - half * sin(heading)), (p.0 + half * cos(heading), p.1 + half * sin(heading))),
                     tint, 0.03)
        }
        // The mound, growing with every arrival; spores ripen inside.
        let reach = 0.04 + 0.13 * Double(arrived) / Double(rods)
        guard arrived > 0 else { return }
        var mound = Path()
        mound.addArc(center: u.pt(centre.0, centre.1 + 0.02), radius: u.len(reach), startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        mound.closeSubpath()
        context.fill(mound, with: .color(tint.opacity(0.3)))
        u.stroke(context, mound, tint, 0.03)
        let ripe = Ease.clamp((t - 3.6) / 0.8)
        for k in 0..<9 where ripe > 0 {
            let a = Double.pi + Double(k) * .pi / 9 + 0.15
            let d = reach * (0.35 + 0.35 * BenchShapes.rand(Double(k) * 3.9))
            context.fill(u.circle(centre.0 + d * cos(a), centre.1 + 0.02 + d * sin(a), 0.014 * ripe), with: .color(clay))
        }
    }
}

/// Caulobacter: a stalked, crescent cell holds to the surface by a clay
/// holdfast; it grows a flagellum at its far pole, divides unevenly, and
/// the swimmer daughter spins away while the stalked mother stays put.
enum Caulobacter {
    static let duration = 5.2

    private static func crescent(_ u: UnitSquare, from a: (Double, Double), to b: (Double, Double), bow: Double) -> Path {
        let mid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2 - bow)
        return u.polyline(Smooth.curve([a, mid, b], samples: 8))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.86), (0.96, 0.86)), tint.opacity(0.5), 0.02)
        // The holdfast, the stalk, and the mother cell.
        context.fill(u.ellipse(0.2, 0.855, 0.05, 0.02), with: .color(clay))
        u.stroke(context, u.line((0.2, 0.85), (0.24, 0.66)), tint, 0.016)
        let grow = Ease.inOut((t - 0.3) / 1.6)
        let split = Ease.inOut((t - 2.2) / 0.6)
        let swim = Ease.inOut((t - 2.8) / 2.0)
        let far = (0.44 + 0.22 * grow, 0.5 - 0.06 * grow)
        let mid = (0.24 + (far.0 - 0.24) * 0.55, 0.66 + (far.1 - 0.66) * 0.55)
        // Mother: stalk end to the division site.
        u.stroke(context, crescent(u, from: (0.24, 0.66), to: split > 0 ? mid : far, bow: 0.03), tint, 0.075)
        // Daughter: from the division site to the far pole, then away.
        let away = (0.3 * swim, -0.3 * swim)
        let dFrom = (mid.0 + 0.03 * split + away.0, mid.1 - 0.02 * split + away.1)
        let dTo = (far.0 + away.0, far.1 + away.1)
        if split > 0 {
            u.stroke(context, crescent(u, from: dFrom, to: dTo, bow: 0.02), tint, 0.075)
        }
        // The division site pinching, in clay.
        if grow > 0.6, split < 1 {
            context.fill(u.circle(mid.0, mid.1, 0.02 * (1 - split)), with: .color(clay))
        }
        // The flagellum at the far pole, spinning once free.
        let whip = Ease.clamp((t - 1.2) / 0.5)
        if whip > 0 {
            let axis = atan2(dTo.1 - dFrom.1, dTo.0 - dFrom.0)
            let tail = stride(from: 0.0, through: 1.0, by: 0.1).map { s -> (Double, Double) in
                let along = 0.1 * s * whip, across = 0.018 * sin(s * 12 - t * 16)
                return (dTo.0 + along * cos(axis) - across * sin(axis), dTo.1 + along * sin(axis) + across * cos(axis))
            }
            u.stroke(context, u.polyline(tail), clay, 0.016)
        }
    }
}

/// Streptomyces: a clay spore on the agar sends branching hyphae spreading
/// through the surface; aerial hyphae rise from them, their tips curl into
/// coils, and the coils bead up into chains of clay spores, a few of which
/// drift away.
enum Streptomyces {
    static let duration = 5.0
    private static let surface = 0.72
    /// The substrate mycelium: a main hypha each way from the spore, with
    /// branches angling down into the agar.
    private static let hyphae: [[(Double, Double)]] = [
        [(0.3, 0.73), (0.45, 0.75), (0.6, 0.74), (0.75, 0.76), (0.9, 0.75)],
        [(0.3, 0.73), (0.2, 0.75), (0.08, 0.74)],
        [(0.48, 0.75), (0.52, 0.82), (0.58, 0.88)],
        [(0.7, 0.755), (0.66, 0.83), (0.68, 0.9)],
        [(0.18, 0.75), (0.2, 0.83), (0.15, 0.9)],
    ]
    private static let aerial = [0.38, 0.58, 0.78]

    /// An aerial hypha from the surface at `x`: up, then a coil at its tip.
    private static func riser(_ x: Double) -> [(Double, Double)] {
        var points: [(Double, Double)] = []
        for k in 0...10 { let f = Double(k) / 10; points.append((x + 0.015 * sin(f * 3), surface - (surface - 0.36) * f)) }
        let centre = (x + 0.05, 0.36)
        for k in 1...30 {
            let f = Double(k) / 30
            let a = Double.pi + 3 * .pi * f
            let r = 0.05 * (1 - 0.45 * f)
            points.append((centre.0 + r * cos(a), centre.1 + r * sin(a)))
        }
        return points
    }
    private static let risers = aerial.map(riser)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, surface).y, width: u.side, height: u.len(1 - surface))), with: .color(tint.opacity(0.07)))
        u.stroke(context, u.line((0.02, surface), (0.98, surface)), tint.opacity(0.5), 0.025)
        let spread = Ease.inOut((t - 0.3) / 1.3)
        for (k, hypha) in hyphae.enumerated() {
            let grown = Ease.clamp((spread * 1.4 - (k < 2 ? 0 : 0.35)) / (k < 2 ? 1.4 : 1.05))
            if grown > 0 { u.stroke(context, u.polyline(Smooth.curve(hypha, samples: 5)).trimmedPath(from: 0, to: grown), tint, 0.03) }
        }
        context.fill(u.circle(0.3, 0.72, 0.03), with: .color(clay))
        for (k, path) in risers.enumerated() {
            let rise = Ease.inOut((t - 1.5 - 0.2 * Double(k)) / 1.4)
            guard rise > 0 else { continue }
            let line = u.polyline(path)
            let coiled = Double(11) / Double(path.count)
            let sporing = Ease.clamp((t - 3.0 - 0.15 * Double(k)) / 0.8)
            u.stroke(context, line.trimmedPath(from: 0, to: rise), tint.opacity(1 - 0.5 * sporing), 0.03)
            // Spores bead the coil, from the tip back.
            if sporing > 0 {
                let beads = 9
                for b in 0..<beads {
                    let f = 1 - Double(b) / Double(beads)
                    guard Double(b) / Double(beads) < sporing else { continue }
                    let p = Polyline.point(path, at: coiled + (1 - coiled) * f)
                    let drift = b == 0 ? Ease.inOut((t - 4.1 - 0.1 * Double(k)) / 0.6) : 0
                    context.fill(u.circle(p.0 + 0.05 * drift, p.1 - 0.12 * drift, 0.016), with: .color(clay.opacity(1 - drift)))
                }
            }
        }
    }
}

/// Bdellovibrio: the small clay hunter darts at a larger rod, bores in, the
/// prey rounds up, the hunter grows long inside it, splits into several,
/// and they burst out and swim off.
enum Bdellovibrio {
    static let duration = 5.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let prey = (0.6, 0.5)
        let round = Ease.inOut((t - 1.4) / 0.6)
        let burst = Ease.clamp((t - 4.1) / 0.3)
        // The prey: a rod that rounds into a sphere, then bursts.
        if burst < 1 {
            let w = 0.44 - 0.12 * round, h = 0.2 + 0.12 * round
            u.stroke(context, u.capsule(prey.0, prey.1, w, h, corner: h / 2), tint.opacity(1 - burst), 0.035)
        }
        // The hunter, before it is inside.
        let dart = Ease.inOut((t - 0.1) / 0.9)
        if t < 1.3 {
            let p = (0.08 + (prey.0 - 0.2 - 0.08) * dart, 0.3 + (prey.1 - 0.3) * dart)
            let comma = u.polyline(Smooth.curve([(p.0 - 0.035, p.1 - 0.01), (p.0, p.1 + 0.012), (p.0 + 0.035, p.1 - 0.008)], samples: 5))
            u.stroke(context, comma, clay, 0.04)
            let tail = stride(from: 0.0, through: 1.0, by: 0.1).map { s in (p.0 - 0.035 - 0.07 * s, p.1 - 0.01 + 0.012 * sin(s * 10 - t * 16)) }
            u.stroke(context, u.polyline(tail), clay.opacity(0.7), 0.012)
        }
        // Inside: it grows into a long coil, then splits into four.
        if t >= 1.3, burst < 1 {
            let lengthen = Ease.inOut((t - 1.9) / 1.3)
            let coil = stride(from: 0.0, through: 1.0, by: 0.02).map { s -> (Double, Double) in
                let a = s * (1.2 + 4 * lengthen) * .pi
                let r = 0.02 + 0.06 * s * lengthen
                return (prey.0 + r * cos(a), prey.1 + r * sin(a))
            }
            let split = Ease.clamp((t - 3.3) / 0.5)
            if split < 1 {
                u.stroke(context, u.polyline(coil), clay, 0.035)
            }
            for k in 0..<4 where split > 0 {
                let a = Double(k) * .pi / 2 + 0.4
                let p = (prey.0 + 0.06 * cos(a) * split, prey.1 + 0.06 * sin(a) * split)
                u.stroke(context, u.line((p.0 - 0.025 * sin(a), p.1 + 0.025 * cos(a)), (p.0 + 0.025 * sin(a), p.1 - 0.025 * cos(a))), clay, 0.04)
            }
        }
        // The progeny, swimming out.
        for k in 0..<4 where burst > 0 {
            let a = Double(k) * .pi / 2 + 0.4
            let d = 0.06 + 0.3 * Ease.out((t - 4.1) / 0.9)
            let p = (prey.0 + d * cos(a), prey.1 + d * sin(a))
            u.stroke(context, u.line((p.0 - 0.025 * sin(a), p.1 + 0.025 * cos(a)), (p.0 + 0.025 * sin(a), p.1 - 0.025 * cos(a))), clay, 0.04)
        }
    }
}
