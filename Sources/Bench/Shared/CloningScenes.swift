// CloningScenes.swift
// ScienceStatus — getting DNA into bacteria and bacteria onto plates. Each
// draws in a unit square (see `UnitSquare`): cells, tubes and kit in the
// tint, plasmids, colonies and pellets in clay.

import SwiftUI

/// Heat-shock transformation: the tube of cells and clay plasmids sits on
/// ice, goes into the 42 °C bath for a moment, and the plasmids slip into
/// the cells; then back onto ice.
enum HeatShock {
    static let duration = 4.6
    private static let cells: [(Double, Double)] = [(-0.04, 0.0), (0.04, 0.05), (-0.03, 0.1), (0.035, -0.05)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for (k, x) in [0.1, 0.18, 0.26, 0.14, 0.22, 0.3].enumerated() {
            let y = k < 3 ? 0.86 : 0.8
            u.stroke(context, u.capsule(x, y, 0.06, 0.05, corner: 0.012), tint.opacity(0.6), 0.015)
        }
        u.stroke(context, u.line((0.04, 0.7), (0.06, 0.9), (0.36, 0.9), (0.38, 0.7)), tint, 0.03)
        let wave = stride(from: 0.62, through: 0.96, by: 0.02).map { x in (x, 0.72 + 0.008 * sin(x * 30 + t * 4)) }
        var water = u.polyline(wave + [(0.96, 0.9), (0.62, 0.9)])
        water.closeSubpath()
        context.fill(water, with: .color(tint.opacity(0.12)))
        u.stroke(context, u.line((0.62, 0.66), (0.62, 0.9), (0.96, 0.9), (0.96, 0.66)), tint, 0.03)
        let inBath = Keyframes.value(t, [(1.2, 0), (1.6, 1), (2.3, 1), (2.7, 0)])
        let lift = sin(.pi * Ease.clamp((t - 1.2) / 0.4)) + sin(.pi * Ease.clamp((t - 2.3) / 0.4))
        let x = 0.21 + (0.79 - 0.21) * inBath
        let top = 0.44 - 0.2 * lift
        let shock = Ease.clamp((t - 1.6) / 0.1) * (1 - Ease.clamp((t - 2.2) / 0.1))
        let jiggle = 0.006 * sin(t * 60) * shock
        let outline = BenchShapes.tube(u, x: x + jiggle, rim: top, shoulder: top + 0.3, tip: top + 0.42, half: 0.11)
        BenchShapes.fill(context, u, outline, from: top + 0.08, tint.opacity(0.12))
        u.stroke(context, outline, tint, 0.03)
        let entered = Ease.inOut((t - 1.8) / 0.4)
        for (k, c) in cells.enumerated() {
            let p = (x + jiggle + c.0, top + 0.18 + c.1)
            u.stroke(context, u.ellipse(p.0, p.1, 0.06, 0.035), tint, 0.015)
            let outside = (p.0 + (k % 2 == 0 ? -0.045 : 0.045), p.1 - 0.03)
            let q = (outside.0 + (p.0 - outside.0) * entered, outside.1 + (p.1 - outside.1) * entered)
            u.stroke(context, u.circle(q.0, q.1, 0.012), clay, 0.012)
        }
        for k in 0..<2 where shock > 0 {
            let rise = ((t * 2 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1))
            let s = stride(from: 0.0, through: 0.1, by: 0.01).map { d in (0.67 + 0.24 * Double(k) + 0.01 * sin(d * 60 - t * 8), 0.64 - d - 0.06 * rise) }
            u.stroke(context, u.polyline(s), clay.opacity(0.6 * (1 - rise)), 0.015)
        }
    }
}

/// Electroporation: cells and clay plasmids sit between the cuvette's
/// plates; the pulse fires, the membranes open for an instant and the
/// plasmids get in, and the cells seal up.
enum Electroporation {
    static let duration = 4.4
    private static let cells: [(Double, Double)] = [(0.5, 0.36), (0.44, 0.52), (0.56, 0.62), (0.47, 0.76)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.0) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.32, 0.16), (0.32, 0.88), (0.68, 0.88), (0.68, 0.16)), tint, 0.03)
        for x in [0.36, 0.64] { scene.fill(u.capsule(x, 0.56, 0.035, 0.6, corner: 0.01), with: .color(tint)) }
        scene.fill(u.capsule(0.5, 0.14, 0.4, 0.06, corner: 0.015), with: .color(tint.opacity(0.6)))
        let pulse = Ease.clamp((t - 1.4) / 0.05) * (1 - Ease.clamp((t - 1.55) / 0.2))
        let open = Ease.clamp((t - 1.45) / 0.1) * (1 - Ease.inOut((t - 2.3) / 0.5))
        let entered = Ease.inOut((t - 1.5) / 0.6)
        for (k, c) in cells.enumerated() {
            if open > 0.1 {
                scene.stroke(u.ellipse(c.0, c.1, 0.11, 0.07), with: .color(tint),
                             style: StrokeStyle(lineWidth: u.len(0.018), dash: [u.len(0.02), u.len(0.012 * open)]))
            } else {
                u.stroke(scene, u.ellipse(c.0, c.1, 0.11, 0.07), tint, 0.018)
            }
            let outside = (c.0 + (k % 2 == 0 ? 0.07 : -0.07), c.1 - 0.04)
            let q = (outside.0 + (c.0 - outside.0) * entered, outside.1 + (c.1 - outside.1) * entered)
            u.stroke(scene, u.circle(q.0, q.1, 0.014), clay, 0.013)
        }
        if pulse > 0 {
            for y in [0.3, 0.46, 0.62, 0.78] {
                let zig = stride(from: 0.38, through: 0.62, by: 0.03).map { x in (x, y + 0.012 * (Int(x * 100) % 2 == 0 ? 1 : -1)) }
                u.stroke(scene, u.polyline(zig), clay.opacity(pulse), 0.015)
            }
        }
    }
}

/// Bacterial conjugation: the donor reaches its pilus to a neighbour and
/// draws it in; one strand of the clay plasmid runs across and is made
/// whole, and now both carry it.
enum Conjugation {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.35) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let reach = Ease.inOut((t - 0.3) / 0.6)
        let pull = Ease.inOut((t - 1.0) / 0.6)
        let apart = Ease.inOut((t - 3.4) / 0.6)
        let donor = (0.28 + 0.08 * pull - 0.06 * apart, 0.5), recipient = (0.76 - 0.08 * pull + 0.06 * apart, 0.52)
        u.stroke(scene, u.capsule(donor.0, donor.1, 0.3, 0.16, corner: 0.08), tint, 0.03)
        u.stroke(scene, u.capsule(recipient.0, recipient.1, 0.3, 0.16, corner: 0.08), tint, 0.03)
        let from = (donor.0 + 0.15, donor.1), to = (recipient.0 - 0.15, recipient.1)
        if apart < 1 {
            let tip = (from.0 + (to.0 - from.0) * reach, from.1 + (to.1 - from.1) * reach)
            u.stroke(scene, u.line(from, tip), tint.opacity(1 - apart), pull > 0.5 ? 0.05 : 0.018)
        }
        u.stroke(scene, u.circle(donor.0 - 0.03, donor.1, 0.045), clay, 0.02)
        let run = Ease.inOut((t - 1.7) / 1.0)
        if run > 0 && run < 1 {
            let strand = stride(from: 0.0, through: run, by: 0.05).map { s in (from.0 - 0.03 + (to.0 + 0.06 - from.0) * s, from.1 + 0.005 * sin(s * 20)) }
            if strand.count > 1 { u.stroke(scene, u.polyline(strand), clay, 0.016) }
        }
        let whole = Ease.inOut((t - 2.7) / 0.5)
        if whole > 0 { u.stroke(scene, u.circle(recipient.0 + 0.03, recipient.1, 0.045 * whole), clay, 0.02) }
    }
}

/// Transduction: a phage lands on a bacterium and injects the clay stretch
/// of DNA it carried from its last host, which is recombined into the
/// chromosome.
enum Transduction {
    static let duration = 4.6

    /// A point on the bacterium's chromosome, `a` radians round it.
    private static func chromosome(_ a: Double) -> (Double, Double) {
        let wobble: Double = 0.02 * sin(5 * a)
        return (0.5 + 0.2 * cos(a) + wobble, 0.72 + 0.09 * sin(a))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.capsule(0.5, 0.7, 0.72, 0.36, corner: 0.18), tint, 0.03)
        let loop = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.1).map(chromosome)
        u.stroke(scene, u.polyline(loop), tint.opacity(0.6), 0.02)
        let land = Ease.out((t - 0.2) / 0.8)
        let head = (0.5, 0.12 + 0.24 * land)
        var capsid = u.polyline((0..<6).map { k in Rings.offset(head, 0.07, 30 + 60 * Double(k)) })
        capsid.closeSubpath()
        scene.fill(capsid, with: .color(tint))
        u.stroke(scene, u.line((head.0, head.1 + 0.07), (head.0, head.1 + 0.16)), tint, 0.03)
        for side in [-1.0, 1.0] { u.stroke(scene, u.line((head.0, head.1 + 0.16), (head.0 + 0.06 * side, head.1 + 0.2)), tint, 0.015) }
        let inject = Ease.inOut((t - 1.2) / 0.8)
        let recombine = Ease.inOut((t - 2.2) / 0.8)
        if inject < 1 {
            scene.fill(u.circle(head.0, head.1, 0.035 * (1 - inject)), with: .color(clay))
        }
        if inject > 0 {
            let start = (0.5, 0.52), end = (0.5 + 0.02, 0.63)
            let p = (start.0 + (end.0 - start.0) * min(1, inject), start.1 + (end.1 - start.1) * min(1, inject))
            let arcStart = -0.9, arcEnd = -0.3
            let inserted: [(Double, Double)] = stride(from: arcStart, through: arcEnd, by: 0.06).map(chromosome)
            let loose: [(Double, Double)] = stride(from: 0.0, through: 1.0, by: 0.1).map { (s: Double) -> (Double, Double) in
                (p.0 - 0.05 + 0.1 * s, p.1 + 0.015 * sin(s * 9))
            }
            let piece: [(Double, Double)] = zip(loose, inserted).map { (a: (Double, Double), b: (Double, Double)) -> (Double, Double) in
                (a.0 + (b.0 - a.0) * recombine, a.1 + (b.1 - a.1) * recombine)
            }
            u.stroke(scene, u.polyline(piece), clay, 0.03)
        }
    }
}

/// A quadrant streak: the loop is flamed clay-hot between quadrants, each
/// streak dragged from the last, and colonies come up crowded in the first
/// quadrant and one by one in the last.
enum QuadrantStreak {
    static let duration = 5.0
    private static let dish = (0.6, 0.55), radius = 0.34
    private static let flame = (0.12, 0.62)
    private static let starts = [0.2, 1.0, 1.8, 2.6]

    /// The zigzag for quadrant `q`, `s` from 0 to 1.
    private static func streak(_ q: Int, _ s: Double) -> (Double, Double) {
        let a0 = (200.0 + 90 * Double(q)) * .pi / 180
        let across = a0 + .pi / 4 + 0.35 * sin(s * .pi * 7)
        let r = radius * (0.25 + 0.6 * s)
        return (dish.0 + r * cos(across), dish.1 + r * sin(across))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.circle(dish.0, dish.1, radius - 0.02), with: .color(tint.opacity(0.1)))
        u.stroke(scene, u.circle(dish.0, dish.1, radius), tint, 0.035)
        // The burner's flame.
        let flicker = 0.01 * sin(t * 17)
        var fire = Path()
        fire.move(to: u.pt(flame.0 - 0.04, flame.1 + 0.08))
        fire.addQuadCurve(to: u.pt(flame.0 + flicker, flame.1 - 0.1), control: u.pt(flame.0 - 0.05, flame.1 - 0.02))
        fire.addQuadCurve(to: u.pt(flame.0 + 0.04, flame.1 + 0.08), control: u.pt(flame.0 + 0.05, flame.1 - 0.02))
        fire.closeSubpath()
        scene.fill(fire, with: .color(clay.opacity(0.8)))
        scene.fill(u.capsule(flame.0, flame.1 + 0.2, 0.06, 0.24, corner: 0.02), with: .color(tint))
        // Streaks, and the colonies that grow on them later.
        for (q, start) in starts.enumerated() {
            let drawn = Ease.clamp((t - start - 0.35) / 0.4)
            guard drawn > 0 else { continue }
            let path = stride(from: 0.0, through: drawn, by: 0.02).map { streak(q, $0) }
            u.stroke(scene, u.polyline(path), tint.opacity(0.4), 0.012)
            let grow = Ease.outBack((t - 3.4 - 0.1 * Double(q)) / 0.5)
            guard grow > 0 else { continue }
            let count = [18, 9, 5, 3][q]
            for k in 0..<count {
                let p = streak(q, (Double(k) + 0.5) / Double(count))
                scene.fill(u.circle(p.0, p.1, (q == 0 ? 0.016 : 0.022) * grow), with: .color(clay))
            }
        }
        // The loop: flamed, then streaking.
        var at = flame
        var hot = 0.0
        for (q, start) in starts.enumerated() {
            if t >= start && t < start + 0.35 {
                at = (flame.0, flame.1 - 0.06)
                hot = 1
            } else if t >= start + 0.35 && t < start + 0.8 {
                at = streak(q, Ease.clamp((t - start - 0.35) / 0.4))
            }
        }
        if t >= starts[3] + 0.8 { at = (flame.0 + 0.2, 0.2) }
        u.stroke(scene, u.line((at.0, at.1), (at.0 + 0.16, at.1 - 0.3)), tint, 0.02)
        u.stroke(scene, u.circle(at.0, at.1 + 0.015, 0.018), hot > 0 ? clay : tint, 0.018)
    }
}

/// Colonies into wells: a tip takes one clay colony at a time off the plate
/// and dips it into its own well, and the wells cloud up with growth.
enum ColonyToWells {
    static let duration = 4.8
    private static let colonies: [(Double, Double)] = [(0.2, 0.4), (0.3, 0.62), (0.16, 0.7)]
    private static let wells = [0.58, 0.72, 0.86]
    private static let starts = [0.2, 1.3, 2.4]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.circle(0.24, 0.56, 0.2), with: .color(tint.opacity(0.1)))
        u.stroke(scene, u.circle(0.24, 0.56, 0.22), tint, 0.03)
        for (k, c) in colonies.enumerated() where t < starts[k] + 0.55 {
            scene.fill(u.circle(c.0, c.1, 0.035), with: .color(clay))
        }
        for (k, c) in [(0.3, 0.45), (0.2, 0.55)].enumerated() { scene.fill(u.circle(c.0, c.1, 0.022 + 0.005 * Double(k)), with: .color(clay)) }
        for (k, x) in wells.enumerated() {
            let cup = u.line((x - 0.05, 0.6), (x - 0.05, 0.78), (x + 0.05, 0.78), (x + 0.05, 0.6))
            BenchShapes.fill(scene, u, cup, from: 0.66, tint.opacity(0.12))
            let cloud = Ease.inOut((t - starts[k] - 0.9) / 1.2)
            if cloud > 0 { BenchShapes.fill(scene, u, cup, from: 0.66, clay.opacity(0.6 * cloud)) }
            u.stroke(scene, cup, tint, 0.025)
        }
        var xs: [(Double, Double)] = [(0, 0.4)], ys: [(Double, Double)] = [(0, 0.2)]
        for (k, s) in starts.enumerated() {
            xs += [(s + 0.3, colonies[k].0), (s + 0.6, colonies[k].0), (s + 0.9, wells[k]), (s + 1.05, wells[k])]
            ys += [(s + 0.3, colonies[k].1 - 0.06), (s + 0.45, colonies[k].1), (s + 0.6, colonies[k].1 - 0.08), (s + 0.9, 0.5), (s + 0.97, 0.7), (s + 1.05, 0.5)]
        }
        xs += [(4.0, 0.5)]
        ys += [(4.0, 0.2)]
        let x = Keyframes.value(t, xs), y = Keyframes.value(t, ys)
        var cone = u.line((x - 0.024, y - 0.3), (x - 0.006, y), (x + 0.006, y), (x + 0.024, y - 0.3))
        cone.closeSubpath()
        scene.fill(cone, with: .color(tint))
        let carrying = starts.enumerated().contains { k, s in t > s + 0.45 && t < s + 0.97 }
        if carrying { scene.fill(u.circle(x, y + 0.005, 0.016), with: .color(clay)) }
    }
}

/// Resuspending a pellet: the tip goes down to the clay pellet and pipettes
/// up and down; the pellet breaks up and clouds the whole tube evenly.
enum PelletResuspend {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let outline = BenchShapes.tube(u, x: 0.5, rim: 0.34, shoulder: 0.72, tip: 0.9, half: 0.14)
        let broken = Ease.inOut((t - 0.8) / 2.4) * (1 - Ease.inOut((t - 4.1) / 0.4))
        BenchShapes.fill(context, u, outline, from: 0.44, tint.opacity(0.1))
        BenchShapes.fill(context, u, outline, from: 0.44, clay.opacity(0.55 * broken))
        var body = outline
        body.closeSubpath()
        var inside = context
        inside.clip(to: body)
        inside.fill(u.ellipse(0.5, 0.87, 0.1 * (1 - broken), 0.06 * (1 - broken)), with: .color(clay))
        for k in 0..<10 {
            let s = Double(k)
            let lift = broken * (0.3 + 0.7 * BenchShapes.rand(s))
            let p = (0.5 + 0.1 * (BenchShapes.rand(s + 5) - 0.5) + 0.02 * sin(t * 4 + s), 0.86 - 0.36 * lift)
            let r = 0.012 * (1 - broken) + 0.004
            if broken > 0.05 && broken < 0.95 { inside.fill(u.circle(p.0, p.1, r * 2), with: .color(clay)) }
        }
        u.stroke(context, outline, tint, 0.035)
        let press = Keyframes.value(t, [(0.8, 1), (1.1, 0), (1.4, 1), (1.7, 0), (2.0, 1), (2.3, 0), (2.6, 1), (2.9, 0), (3.2, 1)])
        let down = Keyframes.value(t, [(0.2, 0), (0.7, 1), (3.3, 1), (3.8, 0)])
        var pipette = context
        let top = u.pt(0.5, 0)
        pipette.translateBy(x: top.x, y: top.y + u.len(0.08 + 0.16 * down))
        pipette.scaleBy(x: 0.8, y: 0.8)
        pipette.translateBy(x: -top.x, y: -top.y)
        Pipette.drawInstrument(in: pipette, u, tint: tint, press: press, emptied: 0.4 + 0.6 * press)
    }
}
