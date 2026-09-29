// CollectiveScenes.swift
// ScienceStatus — behaviour that emerges from many at once: bacteria
// counting, building and evolving, a genetic clock, and a brain's map.
// Each draws in a unit square (see `UnitSquare`): cells and frames in the
// tint, the signal, the colony, the state that's on, or the firing in clay.

import SwiftUI

/// Quorum sensing: each bacterium puffs out clay signal molecules; as they
/// build up the meter climbs to its mark, and at that moment the whole
/// colony lights up together.
enum QuorumSensing {
    static let duration = 4.6
    private static let quorum = 2.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let lit = Ease.clamp((t - quorum) / 0.12)
        for i in 0..<12 {
            let s = Double(i)
            let c = (0.2 + 0.2 * Double(i % 4) + 0.05 * (BenchShapes.rand(s) - 0.5), 0.2 + 0.2 * Double(i / 4) + 0.05 * (BenchShapes.rand(s + 5) - 0.5))
            for j in 0..<7 {
                let age = t - 0.2 - 0.45 * Double(j) - 0.04 * s
                guard age > 0 else { continue }
                let a = 2 * .pi * BenchShapes.rand(s * 7 + Double(j))
                let d = min(0.16, 0.12 * age)
                scene.fill(u.circle(c.0 + d * cos(a), c.1 + d * sin(a), 0.009), with: .color(clay.opacity(0.75)))
            }
            var cell = scene
            let p = u.pt(c.0, c.1)
            cell.translateBy(x: p.x, y: p.y)
            cell.rotate(by: .radians(.pi * BenchShapes.rand(s + 11)))
            let rect = CGRect(x: -u.len(0.05), y: -u.len(0.024), width: u.len(0.1), height: u.len(0.048))
            let shape = Path(roundedRect: rect, cornerRadius: u.len(0.024))
            cell.fill(shape, with: .color(lit > 0 ? clay.opacity(lit) : tint.opacity(0.15)))
            cell.stroke(shape, with: .color(tint), lineWidth: max(u.len(0.018), UnitSquare.hairline))
        }
        let level = Ease.clamp((t - 0.2) / (quorum - 0.2))
        u.stroke(scene, u.line((0.1, 0.88), (0.9, 0.88)), tint.opacity(0.35), 0.025)
        u.stroke(scene, u.line((0.1, 0.88), (0.1 + 0.8 * level, 0.88)), clay, 0.035)
        u.stroke(scene, u.line((0.9, 0.85), (0.9, 0.91)), tint, 0.02)
        if lit > 0 && t < quorum + 0.8 {
            let ring = Ease.out((t - quorum) / 0.8)
            u.stroke(scene, u.circle(0.5, 0.4, 0.1 + 0.35 * ring), clay.opacity(1 - ring), 0.02)
        }
    }
}

/// A biofilm: swimming cells settle on the surface, grow into little
/// mounds, wrap themselves in matrix that rises into mushroom towers, and
/// a few cells break away from the caps to go and start again.
enum Biofilm {
    static let duration = 4.8
    private static let spots = [0.18, 0.4, 0.62, 0.84]
    private static let packing: [(Double, Double)] = [(0, 0), (-0.045, -0.055), (0.045, -0.055), (0, -0.11), (-0.04, -0.165), (0.04, -0.165)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.02, 0.88), (0.98, 0.88)), tint, 0.04)
        var above = scene
        above.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(0.88))))
        for (k, x) in spots.enumerated() {
            let tower = k % 2 == 0
            let grow = Ease.inOut((t - 2.0 - 0.15 * Double(k)) / 1.2)
            if grow > 0 {
                let scene = above
                if tower {
                    scene.fill(u.capsule(x, 0.86 - 0.18 * grow, 0.1, 0.36 * grow, corner: 0.04), with: .color(tint.opacity(0.22)))
                    scene.fill(u.ellipse(x, 0.86 - 0.44 * grow, 0.34 * grow, 0.22 * grow), with: .color(tint.opacity(0.22)))
                } else {
                    scene.fill(u.ellipse(x, 0.86, 0.22 * grow, 0.2 * grow), with: .color(tint.opacity(0.22)))
                }
            }
            let settle = Ease.out((t - 0.2 - 0.15 * Double(k)) / 0.7)
            guard settle > 0 else { continue }
            let base = (x, 0.83 - 0.7 * (1 - settle))
            let cells = Int(1 + 5 * Ease.clamp((t - 1.0 - 0.1 * Double(k)) / 1.2))
            for (j, o) in packing.prefix(cells).enumerated() {
                let lift = tower ? 0.26 * grow * Double(j) / 5 : 0
                scene.fill(u.capsule(base.0 + o.0 * (tower ? 1 + grow : 1), base.1 + o.1 - lift, 0.036, 0.06, corner: 0.018), with: .color(clay))
            }
        }
        for (j, x) in [0.2, 0.62, 0.2].enumerated() {
            let away = Ease.clamp((t - 3.4 - 0.25 * Double(j)) / 0.9)
            guard away > 0, away < 1 else { continue }
            scene.fill(u.capsule(x + 0.1 * away * (j == 1 ? 1 : -1), 0.38 - 0.3 * away, 0.036, 0.06, corner: 0.018), with: .color(clay.opacity(1 - away)))
        }
    }
}

/// The MEGA-plate: a clay front of bacteria sweeps across the antibiotic-
/// free end and stops dead at the next band, until one mutant lineage
/// breaks through and fans out, band after band of rising drug.
enum MegaPlate {
    static let duration = 5.0
    private static let edges = [0.06, 0.28, 0.5, 0.72, 0.94]
    private static let breaks: [(start: Double, y: Double)] = [(1.2, 0.44), (2.3, 0.62), (3.4, 0.36)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        for k in 0..<4 {
            scene.fill(u.capsule((edges[k] + edges[k + 1]) / 2, 0.5, edges[k + 1] - edges[k], 0.46, corner: 0.005),
                       with: .color(tint.opacity(0.03 + 0.08 * Double(k))))
        }
        var plate = scene
        plate.clip(to: u.capsule(0.5, 0.5, 0.88, 0.46, corner: 0.02))
        let front = edges[0] + (edges[1] - edges[0]) * Ease.inOut((t - 0.2) / 0.7)
        plate.fill(Path(CGRect(x: u.pt(edges[0], 0).x, y: u.pt(0, 0.27).y, width: u.len(front - edges[0]), height: u.len(0.46))), with: .color(clay.opacity(0.8)))
        for (k, b) in breaks.enumerated() {
            let fan = Ease.inOut((t - b.start) / 0.9)
            guard fan > 0 else { continue }
            let x0 = edges[k + 1], w = edges[k + 2] - x0
            var shape = u.polyline([(x0, b.y - 0.012), (x0 + w * fan, b.y - 0.34 * fan), (x0 + w * fan, b.y + 0.34 * fan), (x0, b.y + 0.012)])
            shape.closeSubpath()
            plate.fill(shape, with: .color(clay.opacity(0.8)))
            let filled = Ease.clamp((fan - 0.6) / 0.4)
            plate.fill(Path(CGRect(x: u.pt(x0, 0).x, y: u.pt(0, 0.27).y, width: u.len(w), height: u.len(0.46))), with: .color(clay.opacity(0.8 * filled)))
        }
        for x in edges.dropFirst().dropLast() {
            scene.stroke(u.line((x, 0.27), (x, 0.73)), with: .color(tint.opacity(0.5)),
                         style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.02), u.len(0.015)]))
        }
        u.stroke(scene, u.capsule(0.5, 0.5, 0.88, 0.46, corner: 0.02), tint, 0.03)
    }
}

/// The repressilator: three genes in a ring, each shutting the next one off,
/// so the clay "on" state chases round the triangle, and the reporter
/// traces the oscillation below.
enum Repressilator {
    static let duration = 4.4
    private static let period = 2.2
    private static let nodes: [(Double, Double)] = [(0.5, 0.18), (0.8, 0.62), (0.2, 0.62)]
    /// A represses B, B represses C, C represses A: A, then C, then B peak.
    private static let phases: [Double] = [0, -4 * .pi / 3, -2 * .pi / 3]

    private static func level(_ k: Int, _ t: Double) -> Double { 0.5 + 0.5 * sin(2 * .pi * t / period + phases[k]) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<3 {
            let a = nodes[k], b = nodes[(k + 1) % 3]
            let d = (b.0 - a.0, b.1 - a.1), len = hypot(d.0, d.1)
            let dir = (d.0 / len, d.1 / len)
            let from = (a.0 + dir.0 * 0.1, a.1 + dir.1 * 0.1), to = (b.0 - dir.0 * 0.11, b.1 - dir.1 * 0.11)
            u.stroke(context, u.line(from, to), tint.opacity(0.4 + 0.5 * level(k, t)), 0.025)
            u.stroke(context, u.line((to.0 - dir.1 * 0.035, to.1 + dir.0 * 0.035), (to.0 + dir.1 * 0.035, to.1 - dir.0 * 0.035)), tint.opacity(0.4 + 0.5 * level(k, t)), 0.025)
        }
        for (k, n) in nodes.enumerated() {
            context.fill(u.circle(n.0, n.1, 0.08), with: .color(clay.opacity(level(k, t))))
            u.stroke(context, u.circle(n.0, n.1, 0.08), tint, 0.03)
        }
        let trace = stride(from: max(0, t - 2.2), through: t, by: 0.02).map { s in (0.92 - 0.84 * (t - s) / 2.2, 0.94 - 0.1 * level(0, s)) }
        if trace.count > 1 { u.stroke(context, u.polyline(trace), clay, 0.022) }
    }
}

/// Grid cells, the figure that won a Nobel: a dot runs about its box,
/// leaving a faint trail; wherever the cell fires, a clay spike lands; the
/// spikes gather into fields on a triangular grid, and at the end its lines
/// draw in between them, hexagon by hexagon.
enum GridCells {
    static let duration = 5.0
    private static let runs = 3.8

    private static func position(_ s: Double) -> (Double, Double) {
        (0.5 + 0.33 * sin(2 * .pi * 1.1 * s) + 0.05 * sin(2 * .pi * 5.3 * s),
         0.5 + 0.33 * sin(2 * .pi * 1.63 * s + 0.7) + 0.05 * cos(2 * .pi * 4.1 * s))
    }

    /// The firing fields: a triangular lattice inside the box.
    private static let fields: [(Double, Double)] = {
        var out: [(Double, Double)] = []
        for j in 0..<5 {
            for i in 0..<5 {
                let p = (0.14 + 0.2 * Double(i) + (j % 2 == 0 ? 0 : 0.1), 0.16 + 0.173 * Double(j))
                if p.0 < 0.88, p.1 < 0.88 { out.append(p) }
            }
        }
        return out
    }()

    /// Where and when it fired: sampled along the run, near a field.
    private static let spikes: [(at: Double, p: (Double, Double))] = {
        var out: [(at: Double, p: (Double, Double))] = []
        var last = -1.0
        for k in 0...1400 {
            let s = Double(k) / 1400
            let p = position(s)
            guard fields.contains(where: { hypot($0.0 - p.0, $0.1 - p.1) < 0.045 }), s - last > 0.004 else { continue }
            out.append((s, p))
            last = s
        }
        return out
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.5, 0.86, 0.86, corner: 0.02), tint.opacity(0.6), 0.03)
        let s = min(1, t / runs)
        let reveal = Ease.inOut((t - runs) / 0.7)
        // The trail so far.
        let trail = stride(from: 0, through: s, by: 0.004).map(position)
        if trail.count > 1 { u.stroke(context, u.polyline(trail), tint.opacity(0.22 * (1 - reveal)), 0.012) }
        // The grid, drawn in at the end between neighbouring fields.
        if reveal > 0 {
            for (i, a) in fields.enumerated() {
                for b in fields[(i + 1)...] where abs(hypot(a.0 - b.0, a.1 - b.1) - 0.2) < 0.01 {
                    u.stroke(context, u.line(a, b), tint.opacity(0.5 * reveal), 0.015)
                }
            }
        }
        for spike in spikes where spike.at <= s {
            context.fill(u.circle(spike.p.0, spike.p.1, 0.014), with: .color(clay))
        }
        if reveal < 1 {
            let p = position(s)
            context.fill(u.circle(p.0, p.1, 0.024), with: .color(tint.opacity(1 - reveal)))
        }
    }
}
