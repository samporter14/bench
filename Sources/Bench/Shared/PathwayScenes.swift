// PathwayScenes.swift
// ScienceStatus — biochemical pathways, protein traffic and processing,
// and an immune overreaction. Each draws in a unit square (see
// `UnitSquare`): molecules and machinery in the tint, the carbon that
// moves, the phosphate, the chain or the signal in clay.

import SwiftUI

/// Glycolysis, carbon by carbon: glucose's six carbons take two
/// phosphates (two ATP spent), become fructose bisphosphate, split into two
/// threes, and run down to two pyruvates, paying back four ATP.
enum Glycolysis {
    static let duration = 5.0

    private static func atp(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), alpha: Double, tint: Color) {
        context.fill(u.circle(p.0, p.1, 0.042), with: .color(clay.opacity(alpha)))
        u.stroke(context, u.line((p.0 + 0.04, p.1), (p.0 + 0.1, p.1)), clay.opacity(alpha), 0.03)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let ring = Ease.inOut((t - 1.0) / 0.4)
        let split = Ease.inOut((t - 1.9) / 0.5)
        let down = Ease.inOut((t - 2.5) / 1.2)
        // The carbons: a hexagon, then a pentagon with one out, then two
        // threes that slide apart and down, straightening into chains.
        let centre = (0.5, 0.26)
        for k in 0..<6 {
            let hex = Rings.offset(centre, 0.11, -90 + 60 * Double(k))
            let pent = k < 5 ? Rings.offset(centre, 0.1, -90 + 72 * Double(k)) : (centre.0 + 0.18, centre.1 - 0.06)
            let joined = (hex.0 + (pent.0 - hex.0) * ring, hex.1 + (pent.1 - hex.1) * ring)
            let half = k < 3 ? -1.0 : 1.0
            let chain = (0.5 + half * 0.24 + 0.075 * (Double(k % 3) - 1), 0.78)
            let apart = (joined.0 + half * 0.2 * split, joined.1 + 0.12 * split)
            let p = (apart.0 + (chain.0 - apart.0) * down, apart.1 + (chain.1 - apart.1) * down)
            scene.fill(u.circle(p.0, p.1, 0.045), with: .color(tint))
        }
        // Phosphates on, then carried by each half down to the payoff.
        for (k, at) in [(0, 0.5), (1, 1.4)].enumerated() {
            let on = Ease.clamp((t - at.1) / 0.3)
            guard on > 0, down < 0.9 else { continue }
            let side = k == 0 ? -1.0 : 1.0
            let base = (0.5 + side * (0.13 + 0.2 * split), 0.26 + 0.12 * split + 0.4 * down)
            scene.fill(u.circle(base.0 + side * 0.05, base.1 - 0.07, 0.04 * on), with: .color(clay))
            let arrive = Ease.inOut((t - at.1 + 0.4) / 0.4)
            if arrive < 1 { atp(scene, u, at: (0.06 + (base.0 - 0.06) * arrive, 0.08), alpha: 1 - arrive, tint: tint) }
        }
        // The payoff: four ATP out, two from each side.
        for k in 0..<4 {
            let out = Ease.out((t - 3.0 - 0.2 * Double(k)) / 0.6)
            guard out > 0, out < 1 else { continue }
            let side = k % 2 == 0 ? -1.0 : 1.0
            atp(scene, u, at: (0.5 + side * (0.24 + 0.16 * out) - 0.045, 0.66 + 0.07 * Double(k / 2) - 0.2 * out), alpha: 1 - out * out, tint: tint)
        }
        if down > 0.95 {
            for side in [-1.0, 1.0] { u.stroke(scene, u.line((0.5 + side * 0.165, 0.78), (0.5 + side * 0.315, 0.78)), tint.opacity(0.5), 0.02) }
        }
    }
}

/// The Krebs cycle: two clay carbons of acetyl join the four of
/// oxaloacetate, and the six ride round the wheel; two leave as CO₂ and
/// the turn throws off NADH, GTP and FADH₂ before the four are ready again.
enum KrebsCycle {
    static let duration = 5.0
    private static let radius = 0.3

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.circle(0.5, 0.52, radius), tint.opacity(0.4), 0.025)
        for k in 0..<8 {
            let a = (-90 + 45 * Double(k)) * .pi / 180
            scene.fill(u.circle(0.5 + radius * cos(a), 0.52 + radius * sin(a), 0.022), with: .color(tint.opacity(0.6)))
        }
        let join = Ease.inOut((t - 0.2) / 0.5)
        let travel = Ease.inOut((t - 0.8) / 3.4)
        let angle = (-90 + 360 * travel) * .pi / 180
        let at = (0.5 + radius * cos(angle), 0.52 + radius * sin(angle))
        let lost = (travel > 0.28 ? 1 : 0) + (travel > 0.42 ? 1 : 0)
        let carbons = 4 + (join > 0.9 ? 2 : 0) - (travel >= 1 ? 0 : lost) - (travel >= 1 ? 2 : 0)
        for k in 0..<max(0, carbons) {
            let a = Double(k) * 2 * .pi / Double(max(1, carbons))
            scene.fill(u.circle(at.0 + 0.05 * cos(a), at.1 + 0.05 * sin(a), 0.024), with: .color(k < 2 && join > 0.9 && travel < 0.3 ? clay : tint))
        }
        if join < 0.95 {
            for j in 0..<2 {
                let p = (0.5 + 0.05 * Double(j) - 0.025, 0.02 + (0.22 - 0.02) * join)
                scene.fill(u.circle(p.0, p.1, 0.024), with: .color(clay))
            }
        }
        // What comes off, and where on the turn.
        let products: [(at: Double, kind: Int)] = [(0.3, 0), (0.3, 1), (0.44, 0), (0.44, 1), (0.6, 2), (0.74, 3), (0.9, 1)]
        for (k, p) in products.enumerated() {
            let off = Ease.out((travel - p.at) / 0.12)
            guard off > 0, off < 1 else { continue }
            let a = (-90 + 360 * p.at) * .pi / 180 + (k % 2 == 0 ? 0.15 : -0.15)
            let r = radius + 0.05 + 0.12 * off
            let q = (0.5 + r * cos(a), 0.52 + r * sin(a))
            switch p.kind {
            case 0: u.stroke(scene, u.circle(q.0, q.1, 0.024), tint.opacity(1 - off), 0.016)
            case 1: scene.fill(u.capsule(q.0, q.1, 0.045, 0.045, corner: 0.008), with: .color(clay.opacity(1 - off)))
            case 2: scene.fill(u.circle(q.0, q.1, 0.026), with: .color(tint.opacity(1 - off)))
            default: u.stroke(scene, u.capsule(q.0, q.1, 0.045, 0.045, corner: 0.008), clay.opacity(1 - off), 0.016)
            }
        }
    }
}

/// A kinase cascade: a clay ligand binds its receptor, and the signal
/// doubles at each tier, kinase phosphorylating kinase, until the gene in
/// the nucleus switches on.
enum KinaseCascade {
    static let duration = 4.6
    private static let tiers = [0.32, 0.46, 0.6, 0.74]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.02, 0.14), (0.98, 0.14)), tint, 0.035)
        u.stroke(scene, u.line((0.5, 0.14), (0.5, 0.22)), tint, 0.03)
        u.stroke(scene, u.line((0.5, 0.14), (0.46, 0.08)), tint, 0.03)
        u.stroke(scene, u.line((0.5, 0.14), (0.54, 0.08)), tint, 0.03)
        let bound = Ease.out((t - 0.1) / 0.3)
        scene.fill(u.circle(0.5, 0.02 + 0.04 * bound, 0.025), with: .color(clay))
        var nucleus = Path()
        nucleus.addArc(center: u.pt(0.5, 1.3), radius: u.len(0.44), startAngle: .degrees(235), endAngle: .degrees(305), clockwise: false)
        u.stroke(scene, nucleus, tint, 0.03)
        for (level, y) in tiers.enumerated() {
            let count = 1 << level
            let lit = Ease.clamp((t - 0.5 - 0.55 * Double(level)) / 0.25)
            for k in 0..<count {
                let x = 0.5 + 0.84 * (Double(k) + 0.5 - Double(count) / 2) / Double(max(count, 2)) * (level == 0 ? 0 : 1)
                if level > 0 {
                    let parent = 0.5 + 0.84 * (Double(k / 2) + 0.5 - Double(count / 2) / 2) / Double(max(count / 2, 2)) * (level == 1 ? 0 : 1)
                    u.stroke(scene, u.line((parent, tiers[level - 1] + 0.03), (x, y - 0.03)), (lit > 0 ? clay : tint).opacity(0.5), 0.012)
                }
                let r = 0.045 - 0.006 * Double(level)
                scene.fill(u.circle(x, y, r), with: .color(lit > 0.5 ? clay : tint))
                if lit > 0.5 { scene.fill(u.circle(x + r, y - r, 0.01), with: .color(ivory)) }
            }
        }
        let gene = Ease.clamp((t - 2.9) / 0.3)
        scene.fill(u.capsule(0.5, 0.9, 0.2, 0.03, corner: 0.01), with: .color(gene > 0 ? clay.opacity(gene) : tint.opacity(0.4)))
    }
}

/// The Sec61 translocon: a ribosome docks on the channel, its clay chain
/// threads through into the ER, the signal peptide is snipped off in the
/// membrane, and the protein folds up inside.
enum Sec61 {
    static let duration = 4.8
    private static let membrane = 0.56

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, membrane + 0.03).y, width: u.side, height: u.len(0.5))), with: .color(tint.opacity(0.08)))
        for y in [membrane - 0.03, membrane + 0.03] {
            u.stroke(scene, u.line((0.02, y), (0.4, y)), tint, 0.025)
            u.stroke(scene, u.line((0.6, y), (0.98, y)), tint, 0.025)
        }
        for x in [0.44, 0.56] { scene.fill(u.capsule(x, membrane, 0.07, 0.12, corner: 0.02), with: .color(tint)) }
        let dock = Ease.out((t - 0.2) / 0.6)
        let ribo = (0.5, 0.36 - 0.2 * (1 - dock) - 0.25 * Ease.inOut((t - 4.0) / 0.4))
        scene.fill(u.ellipse(ribo.0, ribo.1 - 0.08, 0.26, 0.14), with: .color(tint.opacity(0.85)))
        scene.fill(u.ellipse(ribo.0, ribo.1 + 0.03, 0.18, 0.08), with: .color(tint.opacity(0.85)))
        let thread = Ease.clamp((t - 0.8) / 2.4)
        let fold = Ease.inOut((t - 3.2) / 0.6)
        let cut = t > 1.6
        if thread > 0 {
            let length = 0.5 * thread
            var chain: [(Double, Double)] = []
            var s = 0.0
            while s <= length {
                let y = ribo.1 + 0.07 + s
                let p: (Double, Double)
                if y < membrane + 0.06 {
                    p = (0.5, y)
                } else {
                    let d = y - membrane - 0.06
                    p = (0.5 + 0.08 * sin(d * 30) * (1 - fold), membrane + 0.06 + d * (1 - 0.7 * fold))
                }
                chain.append(p)
                s += 0.01
            }
            if chain.count > 1 { u.stroke(scene, u.polyline(chain), clay, 0.025) }
            if fold > 0 { scene.fill(u.circle(0.5, membrane + 0.16, 0.07 * fold), with: .color(clay.opacity(fold))) }
        }
        if cut {
            scene.fill(u.capsule(0.62, membrane, 0.02, 0.07, corner: 0.01), with: .color(clay))
            let snap = sin(.pi * Ease.clamp((t - 1.6) / 0.3))
            if snap > 0 { scene.fill(Sparkles.star(u, 0.58, membrane + 0.05, 0.05 * snap), with: .color(clay)) }
        }
    }
}

/// A viral polyprotein being processed: the clay protease cuts itself out of
/// the chain, then works along it, and the proteins it frees drift apart.
enum Polyprotein {
    static let duration = 4.8
    private static let cuts: [(link: Int, at: Double)] = [(2, 0.7), (3, 0.95), (0, 1.6), (1, 2.1), (4, 2.6)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        var freed = Array(repeating: 0.0, count: 6)
        for c in cuts {
            let f = Ease.inOut((t - c.at) / 0.5)
            freed[c.link] = max(freed[c.link], f)
            freed[c.link + 1] = max(freed[c.link + 1], f)
        }
        let drift: [(Double, Double)] = [(-0.02, -0.16), (0.0, 0.14), (0.0, -0.2), (0.02, 0.18), (0.0, -0.14), (0.02, 0.15)]
        var centres: [(Double, Double)] = []
        for k in 0..<6 {
            let base = (0.1 + 0.16 * Double(k), 0.5)
            let away = k == 3 ? 0 : freed[k]
            centres.append((base.0 + drift[k].0 * away, base.1 + drift[k].1 * away))
        }
        for k in 0..<5 {
            let cutDone = cuts.contains { $0.link == k && t > $0.at }
            guard !cutDone else { continue }
            u.stroke(scene, u.line(centres[k], centres[k + 1]), tint.opacity(0.5), 0.02)
        }
        for (k, c) in centres.enumerated() where k != 3 {
            var domain = scene
            let p = u.pt(c.0, c.1)
            domain.translateBy(x: p.x, y: p.y)
            domain.rotate(by: .degrees(25 * freed[k] * (k % 2 == 0 ? 1 : -1)))
            let rect = CGRect(x: -u.len(0.06), y: -u.len(0.045), width: u.len(0.12), height: u.len(0.09))
            domain.fill(Path(roundedRect: rect, cornerRadius: u.len(0.03)), with: .color(tint))
        }
        // The protease: out of the chain, then along it to each cut.
        let px = Keyframes.value(t, [(0.95, 0.58), (1.4, 0.18), (1.9, 0.34), (2.4, 0.74), (3.0, 0.58)])
        let py = Keyframes.value(t, [(0.95, 0.5), (1.3, 0.36), (2.8, 0.36), (3.2, 0.5)])
        scene.fill(u.capsule(px, py, 0.12, 0.09, corner: 0.03), with: .color(clay))
        for c in cuts {
            let snip = sin(.pi * Ease.clamp((t - c.at) / 0.3))
            guard snip > 0 else { continue }
            let x = 0.18 + 0.16 * Double(c.link)
            scene.fill(Sparkles.star(u, x, 0.5, 0.05 * snip), with: .color(clay))
        }
    }
}

/// A cytokine storm: one activated cell releases clay cytokines, they set
/// off its neighbours, who release more, and the wave runs out of control
/// across the tissue.
enum CytokineStorm {
    static let duration = 4.6
    private static let cells: [(Double, Double)] = [
        (0.5, 0.5), (0.3, 0.36), (0.68, 0.34), (0.34, 0.68), (0.66, 0.66), (0.14, 0.52), (0.86, 0.5),
        (0.5, 0.16), (0.5, 0.86), (0.16, 0.16), (0.84, 0.18), (0.18, 0.86), (0.84, 0.84),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        for (k, c) in cells.enumerated() {
            let lit = 0.3 + hypot(c.0 - 0.5, c.1 - 0.5) / 0.22 + 0.1 * BenchShapes.rand(Double(k))
            let on = t > lit
            if on {
                for j in 0..<7 {
                    let a = Double(j) * 2 * .pi / 7 + Double(k)
                    let age = ((t - lit) / 0.9).truncatingRemainder(dividingBy: 1)
                    let d = 0.04 + 0.16 * age
                    scene.fill(u.circle(c.0 + d * cos(a), c.1 + d * sin(a), 0.01), with: .color(clay.opacity(1 - age)))
                }
            }
            scene.fill(u.circle(c.0, c.1, 0.05), with: .color(on ? clay : tint.opacity(0.2)))
            u.stroke(scene, u.circle(c.0, c.1, 0.05), tint, 0.02)
        }
    }
}
