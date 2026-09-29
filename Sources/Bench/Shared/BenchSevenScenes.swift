// BenchSevenScenes.swift
// ScienceStatus — second takes on bench classics: the vortex from above,
// a full bead cleanup, a Kirby–Bauer plate, a flow plot and its gate, and a
// sort with its purity check. Each draws in a unit square (see
// `UnitSquare`): kit, axes and ordinary events in the tint, the sample, the
// antibiotic and the gated population in clay.

import SwiftUI

/// The vortex from above: looking down into the tube as it shakes, the clay
/// liquid winds into a vortex with a dimple at its heart, then settles.
enum VortexTop {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let on = Keyframes.value(t, [(0.3, 0), (0.6, 1), (2.8, 1), (3.3, 0)])
        let wobble = (0.02 * cos(t * 40) * on, 0.02 * sin(t * 40) * on)
        let c = (0.5 + wobble.0, 0.5 + wobble.1)
        context.fill(u.circle(c.0, c.1, 0.3), with: .color(clay.opacity(0.85)))
        for k in 0..<2 {
            let spiral = stride(from: 0.0, through: 2.2 * .pi, by: 0.1).map { a -> (Double, Double) in
                let r = 0.03 + 0.24 * a / (2.2 * .pi)
                let turn = a * 1.0 * on - t * 9 * on + Double(k) * .pi
                return (c.0 + r * cos(turn + a), c.1 + r * sin(turn + a))
            }
            u.stroke(context, u.polyline(spiral), ivory.opacity(0.7 * on), 0.018)
        }
        context.fill(u.circle(c.0, c.1, 0.045 * on), with: .color(ivory.opacity(0.9 * on)))
        u.stroke(context, u.circle(c.0, c.1, 0.3), tint, 0.05)
        u.stroke(context, u.circle(c.0, c.1, 0.36), tint.opacity(0.4), 0.02)
    }
}

/// A bead cleanup on the magnet: clay beads carrying DNA are pulled to the
/// wall; the liquid goes, ethanol washes in and out; off the magnet the
/// elution buffer frees them; back on, and the clear, clay eluate is the
/// purified DNA.
enum BeadCleanup {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let magnet = Keyframes.value(t, [(0.5, 0), (0.8, 1), (2.9, 1), (3.1, 0), (3.6, 0), (3.8, 1)])
        let level = Keyframes.value(t, [(1.2, 0.36), (1.6, 0.8), (1.9, 0.8), (2.1, 0.5), (2.5, 0.5), (2.8, 0.8), (3.2, 0.8), (3.4, 0.62)])
        let ethanol = t > 1.9 && t < 2.8
        let eluate = t > 3.2
        let outline = BenchShapes.tube(u, x: 0.42, rim: 0.2, shoulder: 0.7, tip: 0.86, half: 0.13)
        if level < 0.8 {
            BenchShapes.fill(scene, u, outline, from: level, eluate ? clay.opacity(0.35 * Ease.clamp((t - 4.0) / 0.4) + 0.12) : tint.opacity(ethanol ? 0.25 : 0.15))
        }
        u.stroke(scene, outline, tint, 0.035)
        scene.fill(u.capsule(0.62 + 0.2 * (1 - magnet), 0.52, 0.08, 0.34, corner: 0.02), with: .color(tint))
        for k in 0..<14 {
            let s = Double(k)
            let loose = (0.34 + 0.16 * BenchShapes.rand(s) + 0.01 * sin(t * 5 + s), 0.4 + 0.3 * BenchShapes.rand(s + 9))
            let held = (0.535 - 0.008 * BenchShapes.rand(s + 3), 0.44 + 0.18 * BenchShapes.rand(s + 17))
            let pull = Ease.inOut((magnet - 0.02 * s) / 0.8)
            let p = (loose.0 + (held.0 - loose.0) * pull, loose.1 + (held.1 - loose.1) * pull)
            scene.fill(u.circle(p.0, p.1, 0.014), with: .color(clay))
        }
        // The tip that takes the liquid off, and the ethanol going in.
        let tip = Keyframes.value(t, [(1.0, 0), (1.2, 1), (1.6, 1), (1.8, 0), (2.4, 0), (2.5, 1), (2.8, 1), (2.9, 0)])
        if tip > 0 {
            let y = 0.1 + 0.62 * tip
            u.stroke(scene, u.line((0.38, y), (0.38, y - 0.4)), tint, 0.025)
        }
    }
}

/// A Kirby–Bauer plate: clay antibiotic discs go down on the fresh lawn, it
/// grows in, and clear zones open round the discs, each its own size; one
/// disc has none at all.
enum KirbyBauer {
    static let duration = 4.6
    private static let discs: [(x: Double, y: Double, zone: Double)] = [(0.34, 0.36, 0.13), (0.66, 0.36, 0.09), (0.34, 0.66, 0.06), (0.66, 0.66, 0.0)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let grown = Ease.inOut((t - 1.4) / 1.6)
        context.drawLayer { layer in
            layer.opacity = 1 - fade
            layer.clip(to: u.circle(0.5, 0.51, 0.39))
            layer.fill(u.circle(0.5, 0.51, 0.39), with: .color(tint.opacity(0.08 + 0.3 * grown)))
            var y = 0.14
            while y < 0.9 {
                u.stroke(layer, u.line((0.1, y), (0.9, y + 0.02)), tint.opacity(0.1 + 0.2 * grown), 0.012)
                y += 0.05
            }
            layer.blendMode = .destinationOut
            for d in discs where d.zone > 0 {
                layer.fill(u.circle(d.x, d.y, d.zone * grown), with: .color(.black))
            }
        }
        u.stroke(scene, u.circle(0.5, 0.51, 0.41), tint, 0.04)
        for (k, d) in discs.enumerated() {
            let placed = Ease.outBack((t - 0.2 - 0.25 * Double(k)) / 0.3)
            guard placed > 0 else { continue }
            scene.fill(u.circle(d.x, d.y, 0.035 * placed), with: .color(clay))
        }
        let measure = Ease.inOut((t - 3.1) / 0.4)
        if measure > 0 {
            let d = discs[0]
            let half = d.zone * measure
            u.stroke(scene, u.line((d.x - half, d.y + 0.16), (d.x + half, d.y + 0.16)), clay, 0.018)
            for x in [d.x - half, d.x + half] { u.stroke(scene, u.line((x, d.y + 0.14), (x, d.y + 0.18)), clay, 0.018) }
        }
    }
}

/// A flow plot filling in: events land by size and granularity into their
/// populations, then a clay gate is drawn round the lymphocytes and the
/// events inside it light up.
enum FlowDotPlot {
    static let duration = 4.8
    private static let populations: [(x: Double, y: Double, spread: Double, count: Int)] = [(0.36, 0.7, 0.05, 40), (0.58, 0.56, 0.06, 18), (0.66, 0.3, 0.07, 28), (0.2, 0.82, 0.04, 10)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.12, 0.1), (0.12, 0.9), (0.92, 0.9)), tint.opacity(0.6), 0.02)
        let shown = Ease.clamp((t - 0.2) / 2.2)
        let gate = Ease.inOut((t - 2.6) / 0.6)
        var index = 0
        for (p, pop) in populations.enumerated() {
            for _ in 0..<pop.count {
                let s = Double(index)
                index += 1
                guard BenchShapes.rand(s + 400) < shown else { continue }
                let gx = (BenchShapes.rand(s) + BenchShapes.rand(s + 100) + BenchShapes.rand(s + 200) - 1.5) * pop.spread * 1.4
                let gy = (BenchShapes.rand(s + 300) + BenchShapes.rand(s + 500) + BenchShapes.rand(s + 600) - 1.5) * pop.spread
                let lit = p == 0 && gate > 0.95
                scene.fill(u.circle(pop.x + gx, pop.y + gy, 0.011), with: .color(lit ? clay : tint.opacity(0.8)))
            }
        }
        if gate > 0 {
            let outline = stride(from: 0.0, through: 2 * .pi * gate, by: 0.1).map { a in (0.36 + 0.11 * cos(a), 0.7 + 0.08 * sin(a)) }
            if outline.count > 1 { u.stroke(scene, u.polyline(outline), clay, 0.022) }
        }
    }
}

/// Sorting and the purity check: on the left, the mixed sample and a clay
/// gate round the wanted cells; they're sorted across, and the re-run on
/// the right is nearly all clay.
enum SortPurity {
    static let duration = 4.8

    private static func dot(_ s: Double, clayPopulation: Bool) -> (Double, Double) {
        let spread = 0.06
        let gx = (BenchShapes.rand(s) + BenchShapes.rand(s + 100) - 1) * spread
        let gy = (BenchShapes.rand(s + 300) + BenchShapes.rand(s + 500) - 1) * spread
        return clayPopulation ? (0.3 + gx, 0.34 + gy) : (0.16 + gx, 0.66 + gy)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        for x0 in [0.06, 0.54] {
            u.stroke(scene, u.line((x0, 0.14), (x0, 0.86), (x0 + 0.4, 0.86)), tint.opacity(0.6), 0.02)
        }
        let shown = Ease.clamp((t - 0.2) / 1.2)
        let gate = Ease.inOut((t - 1.4) / 0.5)
        let sort = Ease.inOut((t - 2.0) / 1.0)
        for k in 0..<36 {
            let s = Double(k)
            guard BenchShapes.rand(s + 900) < shown else { continue }
            let wanted = k % 2 == 0
            let p = dot(s, clayPopulation: wanted)
            if wanted && sort > 0 {
                let to = (p.0 + 0.48, p.1)
                let q = (p.0 + (to.0 - p.0) * sort, p.1 + (to.1 - p.1) * sort - 0.15 * sin(.pi * sort))
                scene.fill(u.circle(q.0, q.1, 0.013), with: .color(clay))
            } else {
                scene.fill(u.circle(p.0, p.1, 0.013), with: .color(wanted && gate > 0.9 ? clay : tint.opacity(0.8)))
            }
        }
        if sort > 0.9 { scene.fill(u.circle(0.66, 0.62, 0.013), with: .color(tint.opacity(0.8))) }
        if gate > 0 {
            let box = u.capsule(0.3, 0.34, 0.2 * gate, 0.2 * gate, corner: 0.02)
            u.stroke(scene, box, clay, 0.02)
        }
        let purity = Ease.clamp((t - 3.1) / 0.4)
        if purity > 0 {
            scene.fill(u.capsule(0.74 + 0.08 * purity, 0.08, 0.16 * purity, 0.03, corner: 0.01), with: .color(clay))
            u.stroke(scene, u.capsule(0.82, 0.08, 0.16, 0.03, corner: 0.01), tint.opacity(0.5), 0.012)
        }
    }
}
