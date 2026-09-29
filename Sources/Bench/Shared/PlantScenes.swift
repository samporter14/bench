// PlantScenes.swift
// ScienceStatus — lab scenes from botany. Each draws in a unit square
// (see `UnitSquare`): the plant in the tint, light and what it makes in
// clay.

import SwiftUI

/// A flower opening: five petals part from a bud and spread, showing a
/// clay centre, and the flower sways a little on its stem.
enum Bloom {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.outBack((t - 0.4) / 1.4)
        let sway = 0.03 * sin(t * 1.6)
        let head = (0.5 + sway, 0.4)

        var stem = Path()
        stem.move(to: u.pt(0.5, 0.95))
        stem.addQuadCurve(to: u.pt(head.0, head.1 + 0.08), control: u.pt(0.47, 0.7))
        u.stroke(context, stem, tint)
        var leaf = context
        leaf.translateBy(x: u.pt(0.5, 0.78).x, y: u.pt(0.5, 0.78).y)
        leaf.rotate(by: .degrees(-35))
        leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -u.len(0.035), width: u.len(0.16), height: u.len(0.07))),
                  with: .color(tint))

        for k in 0..<5 {
            let spread = Double(k - 2)
            let angle = (-90 + (9 + (72 - 9) * open) * spread) * .pi / 180
            let d = 0.05 + 0.09 * open
            let length = 0.14 + 0.07 * open, width = 0.08 + 0.04 * open
            var petal = context
            let at = u.pt(head.0 + d * cos(angle), head.1 + d * sin(angle))
            petal.translateBy(x: at.x, y: at.y)
            petal.rotate(by: .radians(angle))
            petal.fill(Path(ellipseIn: CGRect(x: -u.len(length / 2), y: -u.len(width / 2),
                                              width: u.len(length), height: u.len(width))),
                       with: .color(tint))
        }
        let centre = 0.075 * Ease.clamp(open)
        if centre > 0.005 { context.fill(u.circle(head.0, head.1, centre), with: .color(clay)) }
    }
}

/// A stoma from above: two guard cells swell and part to open the pore,
/// clay CO₂ drifts in and water vapour rises out, and the pore closes again.
enum Stomata {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.inOut((t - 0.4) / 0.9) - Ease.inOut((t - 2.7) / 0.7)
        let pore = 0.03 + 0.13 * open

        context.drawLayer { layer in
            layer.fill(u.ellipse(0.5, 0.5, 0.52 + 0.06 * open, 0.7), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.ellipse(0.5, 0.5, pore, 0.46), with: .color(.black))
            // Where the two guard cells meet, top and bottom.
            u.stroke(layer, u.line((0.5, 0.16), (0.5, 0.26)), .black, 0.035)
            u.stroke(layer, u.line((0.5, 0.74), (0.5, 0.84)), .black, 0.035)
            // Water vapour out while the pore is open: rings that show in the
            // ink over the pore and cut out of the guard cells as they pass.
            layer.blendMode = .xor
            for k in 0..<4 {
                let age = (t - 1.0 - 0.35 * Double(k)) / 1.0
                guard age > 0, age < 1 else { continue }
                let side = k % 2 == 0 ? 1.0 : -1.0
                u.stroke(layer, u.circle(0.5 + 0.3 * side * age, 0.46 - 0.34 * age, 0.028 + 0.02 * age),
                         tint.opacity((1 - age * age) * Ease.clamp((open - 0.2) / 0.3)), 0.028)
            }
        }

        // CO₂ drawn in while the pore is open, shrinking as it goes in.
        for k in 0..<5 {
            let age = (t - 1.1 - 0.3 * Double(k)) / 0.8
            guard age > 0, age < 1, open > 0.5 else { continue }
            let a = Double(k) * 1.3 + 0.4
            let d = 0.46 * (1 - Ease.inOut(age))
            context.fill(u.circle(0.5 + d * cos(a), 0.5 + d * sin(a) * 0.8, 0.038 * (1 - age * age)),
                         with: .color(clay))
        }
    }
}

/// Phototropism: a shoot under a clay sun bends towards the light, its
/// leaves turning to face it.
enum Phototropism {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sun = (0.8, 0.2)
        let glow = 1 + 0.15 * sin(t * 3)
        context.fill(u.circle(sun.0, sun.1, 0.07), with: .color(clay))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            let from = Rings.offset(sun, 0.1, a * 180 / .pi)
            let to = Rings.offset(sun, 0.1 + 0.04 * glow, a * 180 / .pi)
            u.stroke(context, u.line(from, to), clay, 0.04)
        }

        u.stroke(context, u.line((0.14, 0.88), (0.6, 0.88)), tint)
        let bend = 0.95 * Ease.inOut((t - 0.3) / 2.6)
        var p = (0.34, 0.88)
        var stem = [p]
        for i in 1...20 {
            let s = Double(i) / 20
            let a = bend * s * s
            p = (p.0 + 0.025 * sin(a), p.1 - 0.025 * cos(a))
            stem.append(p)
        }
        u.stroke(context, u.polyline(stem), tint)
        // Two leaves at the tip, turned with it; one lower down.
        for (point, turn) in [(stem[20], bend), (stem[9], bend * 0.3)] {
            for side in [-1.0, 1.0] {
                var leaf = context
                let at = u.pt(point.0, point.1)
                leaf.translateBy(x: at.x, y: at.y)
                leaf.rotate(by: .radians(turn - .pi / 2 + side * 0.9))
                leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -u.len(0.03), width: u.len(0.13), height: u.len(0.06))),
                          with: .color(tint))
            }
        }
    }
}

/// Roots finding their way down: under a small shoot, a main root grows
/// into the soil and side roots branch off it in turn, each clay tip
/// leading the way.
enum Roots {
    static let duration = 4.0
    private static let soil = 0.24
    private static let branches: [(at: Double, side: Double, reach: Double)] = [
        (0.22, -1, 0.26), (0.38, 1, 0.3), (0.55, -1, 0.24), (0.72, 1, 0.18),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.06, soil), (0.94, soil)), tint)
        u.stroke(context, u.line((0.5, soil), (0.5, soil - 0.1)), tint, 0.06)
        for side in [-1.0, 1.0] {
            var leaf = context
            let at = u.pt(0.5, soil - 0.1)
            leaf.translateBy(x: at.x, y: at.y)
            leaf.rotate(by: .degrees(side > 0 ? -25 : 205))
            leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -u.len(0.025), width: u.len(0.1), height: u.len(0.05))),
                      with: .color(tint))
        }

        func main(_ s: Double) -> (Double, Double) { (0.5 + 0.03 * sin(s * 7), soil + 0.02 + 0.66 * s) }
        let grow = Ease.out((t - 0.2) / 2.4)
        let taproot = stride(from: 0.0, through: 1.0, by: 0.04).map(main)
        if grow > 0 {
            u.stroke(context, u.polyline(taproot).trimmedPath(from: 0, to: grow), tint, 0.06)
            let tip = main(grow)
            context.fill(u.circle(tip.0, tip.1, 0.03), with: .color(clay))
        }
        for branch in branches {
            let reached = (grow - branch.at) / 0.4
            guard reached > 0 else { continue }
            let g = Ease.out(reached)
            let root = main(branch.at)
            let side = stride(from: 0.0, through: 1.0, by: 0.1).map { s in
                (root.0 + branch.side * branch.reach * s, root.1 + 0.1 * s + 0.06 * s * s)
            }
            u.stroke(context, u.polyline(side).trimmedPath(from: 0, to: g), tint, 0.045)
            let end = side[min(side.count - 1, Int(g * Double(side.count - 1)))]
            context.fill(u.circle(end.0, end.1, 0.024), with: .color(clay))
        }
    }
}

/// A dandelion clock: its seeds let go one at a time, turn parachute-up and
/// drift off on the wind, each with its small clay seed.
enum Dandelion {
    static let duration = 4.0
    private static let count = 12
    private static let order = [3, 9, 1, 6, 11, 4, 0, 8, 2, 10, 5, 7]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let head = (0.4, 0.46)
        var stem = Path()
        stem.move(to: u.pt(0.45, 0.96))
        stem.addQuadCurve(to: u.pt(head.0, head.1), control: u.pt(0.47, 0.7))
        u.stroke(context, stem, tint, 0.05)

        for k in 0..<count {
            let rest = Double(k) / Double(count) * 2 * .pi - .pi / 2
            let age = t - 0.4 - 0.24 * Double(order[k])
            var base = (head.0 + 0.03 * cos(rest), head.1 + 0.03 * sin(rest))
            var angle = rest
            var fade = 1.0
            if age > 0 {
                base = (base.0 + 0.3 * age, base.1 - 0.16 * age + 0.03 * sin(age * 5 + Double(k)))
                var turn = -Double.pi / 2 - rest
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                angle = rest + turn * Ease.inOut(age / 0.6)
                fade = 1 - Ease.clamp((age - 1.1) / 0.6)
                guard fade > 0 else { continue }
            }
            let top = (base.0 + 0.1 * cos(angle), base.1 + 0.1 * sin(angle))
            u.stroke(context, u.line(base, top), tint.opacity(fade), 0.02)
            for spread in [-0.5, 0.0, 0.5] {
                let tip = (top.0 + 0.035 * cos(angle + spread), top.1 + 0.035 * sin(angle + spread))
                u.stroke(context, u.line(top, tip), tint.opacity(fade), 0.02)
            }
            context.fill(u.circle(base.0, base.1, 0.014), with: .color(clay.opacity(fade)))
        }
        context.fill(u.circle(head.0, head.1, 0.03), with: .color(tint))
    }
}

/// Photosynthesis: clay light falls on a leaf, carbon dioxide drifts in
/// from below, and oxygen rises off it in small bubbles.
enum Photosynthesis {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var leaf = Path()
        leaf.move(to: u.pt(0.18, 0.62))
        leaf.addQuadCurve(to: u.pt(0.84, 0.44), control: u.pt(0.44, 0.22))
        leaf.addQuadCurve(to: u.pt(0.18, 0.62), control: u.pt(0.54, 0.8))
        leaf.closeSubpath()
        context.drawLayer { layer in
            layer.fill(leaf, with: .color(tint))
            layer.blendMode = .destinationOut
            u.stroke(layer, u.line((0.22, 0.61), (0.78, 0.46)), .black, 0.02)
            for (from, to) in [((0.36, 0.57), (0.42, 0.46)), ((0.5, 0.53), (0.57, 0.42)), ((0.4, 0.56), (0.46, 0.65)),
                               ((0.56, 0.52), (0.62, 0.6))] {
                u.stroke(layer, u.line(from, to), .black, 0.015)
            }
        }
        u.stroke(context, u.line((0.18, 0.62), (0.07, 0.72)), tint, 0.045)

        // Light: clay dashes coming in from the top left.
        for k in 0..<3 {
            let s = (t / 1.2 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let from = (0.06 + 0.1 * Double(k), 0.02), to = (0.34 + 0.1 * Double(k), 0.4)
            let x = from.0 + (to.0 - from.0) * s, y = from.1 + (to.1 - from.1) * s
            u.stroke(context, u.line((x - 0.04, y - 0.05), (x, y)), clay.opacity(1 - s * s), 0.05)
        }
        // Carbon dioxide in from below; oxygen up and away.
        for k in 0..<3 {
            let s = (t / 1.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            context.fill(u.circle(0.3 + 0.12 * Double(k) + 0.04 * s, 0.96 - 0.3 * s, 0.022), with: .color(tint.opacity(1 - s)))
            let o = (t / 1.4 + Double(k) / 3 + 0.15).truncatingRemainder(dividingBy: 1)
            u.stroke(context, u.circle(0.66 + 0.1 * Double(k) * 0.6 + 0.08 * o, 0.4 - 0.32 * o, 0.025), tint.opacity(1 - o), 0.03)
        }
    }
}

/// A mushroom puffing its spores: the cap gives, a cloud of clay spores
/// drifts out from under it and settles, twice.
enum Mushroom {
    static let duration = 3.6
    private static let puffs = [0.6, 2.0]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var squeeze = 0.0
        for p in puffs { squeeze = max(squeeze, sin(.pi * Ease.clamp((t - p) / 0.25))) }
        u.stroke(context, u.line((0.08, 0.9), (0.92, 0.9)), tint)
        var stem = Path()
        stem.move(to: u.pt(0.44, 0.5))
        stem.addQuadCurve(to: u.pt(0.42, 0.9), control: u.pt(0.42, 0.72))
        stem.addLine(to: u.pt(0.58, 0.9))
        stem.addQuadCurve(to: u.pt(0.56, 0.5), control: u.pt(0.58, 0.72))
        stem.closeSubpath()
        context.fill(stem, with: .color(tint))
        // The cap, domed, its gills fanning underneath.
        var cap = Path()
        cap.move(to: u.pt(0.14, 0.5))
        cap.addCurve(to: u.pt(0.86, 0.5), control1: u.pt(0.16, 0.12 + 0.03 * squeeze), control2: u.pt(0.84, 0.12 + 0.03 * squeeze))
        cap.addQuadCurve(to: u.pt(0.14, 0.5), control: u.pt(0.5, 0.44))
        cap.closeSubpath()
        context.fill(cap, with: .color(tint))
        for x in stride(from: 0.2, through: 0.8, by: 0.075) {
            u.stroke(context, u.line((x, 0.51), (0.5 + (x - 0.5) * 0.35, 0.56)), tint.opacity(0.55), 0.025)
        }

        for p in puffs {
            for k in 0..<10 {
                let age = (t - p - 0.02 * Double(k)) / 1.3
                guard age > 0, age < 1 else { continue }
                let side = Double(k % 2 == 0 ? -1 : 1)
                let spread = 0.12 + 0.03 * Double(k % 5)
                let x = 0.5 + side * (0.12 + (spread + 0.08) * Ease.out(age)) + 0.02 * sin(age * 9 + Double(k))
                let y = 0.56 - 0.1 * sin(.pi * Ease.out(age) * 0.6) + 0.24 * age * age
                context.fill(u.circle(x, y, 0.02), with: .color(clay.opacity(1 - age)))
            }
        }
    }
}

/// Subduction: an ocean plate creeps under a continent, and a clay bead of
/// magma rises off it through the crust to the volcano, which erupts.
enum Subduction {
    static let duration = 4.0
    private static let slab: [(Double, Double)] = [(0.0, 0.5), (0.4, 0.5), (0.55, 0.575), (0.67, 0.72), (0.75, 0.97)]
    private static let crust: [(Double, Double)] = [(0.44, 0.47), (0.52, 0.41), (0.61, 0.41), (0.7, 0.22), (0.79, 0.41),
                                                    (1.02, 0.41), (1.02, 0.55), (0.6, 0.55)]
    private static let throws_: [(Double, Double)] = [(-0.12, 0.5), (0.08, 0.56), (-0.05, 0.6), (0.13, 0.48), (-0.15, 0.44), (0.03, 0.52)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.42), (0.44, 0.42)), tint.opacity(0.3), 0.025)
        // The slab, dashed so it's seen to creep down into the trench.
        let period = 0.14
        let creep = period - (t / duration * 2 * period).truncatingRemainder(dividingBy: period)
        context.stroke(u.polyline(Smooth.curve(slab, samples: 8)), with: .color(tint),
                       style: StrokeStyle(lineWidth: u.len(0.06), lineCap: .round, lineJoin: .round,
                                          dash: [u.len(0.04), u.len(0.1)], dashPhase: u.len(creep)))
        var land = u.polyline(crust)
        land.closeSubpath()
        context.fill(land, with: .color(tint))
        let rise = Ease.inOut((t - 0.5) / 1.4)
        if rise > 0, rise < 1 {
            context.fill(u.circle(0.66 + 0.04 * rise, 0.68 - 0.42 * rise, 0.035 - 0.008 * rise), with: .color(clay))
        }
        let erupt = sin(.pi * Ease.clamp((t - 1.9) / 1.7))
        if erupt > 0 {
            var cap = u.line((0.675, 0.275), (0.7, 0.22), (0.725, 0.275))
            cap.closeSubpath()
            context.fill(cap, with: .color(clay.opacity(erupt)))
        }
        for (j, v) in throws_.enumerated() {
            let age = (t - 1.95 - 0.16 * Double(j)) / 0.9
            guard age > 0, age < 1 else { continue }
            let p = (0.7 + v.0 * age, 0.22 - v.1 * age + 0.45 * age * age)
            context.fill(u.circle(p.0, p.1, 0.026), with: .color(clay.opacity(Ease.clamp((1 - age) / 0.3))))
        }
    }
}
