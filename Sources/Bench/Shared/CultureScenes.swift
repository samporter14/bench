// CultureScenes.swift
// ScienceStatus — tissue culture: the familiar cell lines settling and
// growing, and the routines and odds round them. Each draws in a unit
// square (see `UnitSquare`): cell outlines and kit in the tint, nuclei,
// fresh medium and readouts in clay.

import SwiftUI

/// A cell drawn as a closed outline from `radius(angle)`, nucleus in clay.
private func cellShape(_ context: GraphicsContext, _ u: UnitSquare, _ c: (Double, Double), nucleus: Double,
                       tint: Color, radius: (Double) -> Double) {
    let outline = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.2).map { a -> (Double, Double) in
        let r = radius(a)
        return (c.0 + r * cos(a), c.1 + r * sin(a))
    }
    var path = u.polyline(outline)
    path.closeSubpath()
    context.fill(path, with: .color(tint.opacity(0.1)))
    u.stroke(context, path, tint, 0.018)
    context.fill(u.circle(c.0, c.1, nucleus), with: .color(clay))
}

/// HEK 293 cells: loosely attached, they grow up in rounded clumps from
/// three seeds, piling on one another.
enum HEK293 {
    static let duration = 4.6
    private static let seeds: [(Double, Double)] = [(0.3, 0.38), (0.66, 0.34), (0.48, 0.7)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let offsets: [(Double, Double)] = [(0, 0), (0.07, 0.02), (-0.06, 0.04), (0.02, -0.07), (-0.04, -0.05), (0.06, -0.05), (0.0, 0.08)]
        for (s, seed) in seeds.enumerated() {
            for (k, o) in offsets.enumerated() {
                let grow = Ease.outBack((t - 0.2 - 0.45 * Double(k) - 0.15 * Double(s)) / 0.35)
                guard grow > 0 else { continue }
                let c = (seed.0 + o.0, seed.1 + o.1)
                let r = 0.048 * grow
                cellShape(scene, u, c, nucleus: 0.018 * grow, tint: tint) { a in r * (1 + 0.05 * sin(3 * a + Double(k))) }
            }
        }
    }
}

/// HeLa cells: round when they land, they spread flat into polygons and
/// fill in as a cobblestone sheet.
enum HeLa {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        for row in 0..<5 {
            for col in 0..<5 {
                let s = Double(row * 5 + col)
                let c = (0.16 + 0.17 * Double(col) + (row % 2 == 0 ? 0 : 0.085) + 0.02 * (BenchShapes.rand(s) - 0.5),
                         0.16 + 0.15 * Double(row) + 0.02 * (BenchShapes.rand(s + 50) - 0.5))
                guard c.0 < 0.92 else { continue }
                let distance = hypot(c.0 - 0.5, c.1 - 0.5)
                let land = Ease.out((t - 0.2 - distance * 3) / 0.3)
                guard land > 0 else { continue }
                let spread = Ease.inOut((t - 0.5 - distance * 3) / 0.8)
                cellShape(scene, u, c, nucleus: 0.02 * land, tint: tint) { a in
                    let hex = 1 / cos(((a + BenchShapes.rand(s + 7)).truncatingRemainder(dividingBy: .pi / 3)) - .pi / 6)
                    return (0.025 + 0.055 * spread) * (1 + (hex - 1) * spread * 0.8) * land
                }
            }
        }
    }
}

/// Fibroblasts: they settle, stretch out into spindles, and line up in
/// long flowing streams.
enum Fibroblasts {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        for k in 0..<14 {
            let s = Double(k)
            let c = (0.14 + 0.72 * BenchShapes.rand(s + 1), 0.14 + 0.72 * BenchShapes.rand(s + 21))
            let angle = 0.4 + 0.5 * sin(c.0 * 4 + c.1 * 3)
            let land = Ease.out((t - 0.2 - 0.12 * s) / 0.3)
            guard land > 0 else { continue }
            let stretch = Ease.inOut((t - 0.4 - 0.12 * s) / 1.0)
            let length = 0.035 + 0.17 * stretch
            let width = 0.045 - 0.012 * stretch
            let d = (cos(angle), sin(angle)), n = (-sin(angle), cos(angle))
            var spindle = u.polyline([
                (c.0 + d.0 * length / 2, c.1 + d.1 * length / 2), (c.0 + n.0 * width / 2, c.1 + n.1 * width / 2),
                (c.0 - d.0 * length / 2, c.1 - d.1 * length / 2), (c.0 - n.0 * width / 2, c.1 - n.1 * width / 2),
            ])
            spindle.closeSubpath()
            scene.fill(spindle, with: .color(tint.opacity(0.12 * land)))
            u.stroke(scene, spindle, tint.opacity(land), 0.016)
            var nucleus = scene
            let p = u.pt(c.0, c.1)
            nucleus.translateBy(x: p.x, y: p.y)
            nucleus.rotate(by: .radians(angle))
            nucleus.fill(Path(ellipseIn: CGRect(x: -u.len(0.022), y: -u.len(0.011), width: u.len(0.044), height: u.len(0.022))), with: .color(clay.opacity(land)))
        }
    }
}

/// MDCK islands: epithelial colonies grow out as tight round islands of
/// small cells and meet.
enum MDCKIslands {
    static let duration = 4.8
    private static let islands: [(Double, Double)] = [(0.3, 0.34), (0.7, 0.4), (0.44, 0.72)]
    private static let hexagon: [(Double, Double)] = (0..<6).map { k in
        let a = (30 + 60 * Double(k)) * .pi / 180
        return (cos(a), sin(a))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let reach = 0.03 + 0.2 * Ease.inOut((t - 0.2) / 3.4)
        let pitch = 0.05
        // All the cells go into one outline path and one nucleus path, so
        // the whole sheet is two draws rather than hundreds.
        var cells = Path(), nuclei = Path()
        var row = 0
        var y = 0.06
        while y < 0.96 {
            var x = 0.06 + (row % 2 == 0 ? 0 : pitch / 2)
            while x < 0.96 {
                var near = 1.0
                for island in islands { near = min(near, hypot(x - island.0, y - island.1)) }
                if near < reach {
                    let edge = Ease.clamp((reach - near) / 0.04)
                    var cell = u.polyline(Self.hexagon.map { (x + 0.022 * edge * $0.0, y + 0.022 * edge * $0.1) })
                    cell.closeSubpath()
                    cells.addPath(cell)
                    nuclei.addPath(u.circle(x, y, 0.009 * edge))
                }
                x += pitch
            }
            y += pitch * 0.87
            row += 1
        }
        // Filled cells with gaps between them read as a sheet at any size,
        // where outlines this small would close up.
        scene.fill(cells, with: .color(tint.opacity(0.45)))
        scene.fill(nuclei, with: .color(clay))
    }
}

/// Neurons in culture: from each cell body, neurites grow out and branch,
/// clay growth cones feeling the way at their tips, until they touch.
enum NeuronCulture {
    static let duration = 5.0
    private static let somas: [(Double, Double)] = [(0.26, 0.3), (0.7, 0.36), (0.44, 0.74)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let grow = Ease.inOut((t - 0.3) / 3.4)
        for (n, soma) in somas.enumerated() {
            for k in 0..<4 {
                let s = Double(n * 4 + k)
                let angle = Double(k) * .pi / 2 + 0.4 + 0.5 * BenchShapes.rand(s)
                let length = (k == 0 ? 0.32 : 0.18) * grow
                let path = stride(from: 0.0, through: 1.0, by: 0.1).map { q -> (Double, Double) in
                    let a = angle + 0.3 * sin(q * 3 + s)
                    return (soma.0 + cos(a) * length * q, soma.1 + sin(a) * length * q)
                }
                u.stroke(scene, u.polyline(path), tint, 0.016)
                let tip = path[path.count - 1]
                if grow > 0.5 {
                    let mid = path[6]
                    let b = angle + 0.8
                    let branch = (mid.0 + cos(b) * 0.07 * (grow - 0.5) * 2, mid.1 + sin(b) * 0.07 * (grow - 0.5) * 2)
                    u.stroke(scene, u.line(mid, branch), tint, 0.012)
                }
                if grow < 0.98 {
                    scene.fill(u.circle(tip.0, tip.1, 0.012), with: .color(clay))
                    for f in -1...1 {
                        let a = angle + 0.5 * Double(f)
                        u.stroke(scene, u.line(tip, (tip.0 + 0.025 * cos(a), tip.1 + 0.025 * sin(a))), clay, 0.008)
                    }
                }
            }
            scene.fill(u.circle(soma.0, soma.1, 0.045), with: .color(tint))
            scene.fill(u.circle(soma.0, soma.1, 0.018), with: .color(clay))
        }
    }
}

/// Macrophages: settled and spread, they ruffle their edges and put out
/// and draw in their probing filopodia as they wander.
enum Macrophages {
    static let duration = 4.6
    private static let homes: [(Double, Double)] = [(0.3, 0.3), (0.7, 0.34), (0.32, 0.7), (0.7, 0.72)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let spread = Ease.out((t - 0.2) / 0.8)
        for (k, home) in homes.enumerated() {
            let s = Double(k)
            let c = (home.0 + 0.03 * sin(t * 0.7 + s), home.1 + 0.03 * cos(t * 0.6 + s * 2))
            cellShape(scene, u, c, nucleus: 0.03, tint: tint) { a in
                let ruffle = 0.012 * sin(7 * a + t * 4 + s) + 0.008 * sin(11 * a - t * 3)
                return (0.04 + 0.06 * spread) + ruffle * spread
            }
            for f in 0..<3 {
                let a = s + Double(f) * 2.1 + 0.3 * sin(t + Double(f))
                let out = max(0, sin(t * 1.5 + Double(f) * 2 + s))
                let r = 0.1 * spread
                u.stroke(scene, u.line((c.0 + r * cos(a), c.1 + r * sin(a)), (c.0 + (r + 0.05 * out) * cos(a), c.1 + (r + 0.05 * out) * sin(a))), tint, 0.01)
            }
        }
    }
}

/// Changing the medium in a flask: the cap comes off, the pale spent medium
/// is drawn off, fresh clay medium goes in, and the cap goes back on.
enum MediaChange {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let old = Keyframes.value(t, [(0.9, 1), (2.0, 0)])
        let fresh = Keyframes.value(t, [(2.4, 0), (3.5, 1)])
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let flask = u.capsule(0.42, 0.62, 0.62, 0.34, corner: 0.03)
        var inside = scene
        inside.clip(to: flask)
        let oldLevel = 0.79 - 0.12 * old
        inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, oldLevel).y, width: u.side, height: u.side)), with: .color(tint.opacity(0.35)))
        let newLevel = 0.79 - 0.12 * fresh
        if fresh > 0 { inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, newLevel).y, width: u.side, height: u.side)), with: .color(clay.opacity(0.8))) }
        for k in 0..<12 { u.stroke(inside, u.line((0.16 + 0.05 * Double(k), 0.775), (0.19 + 0.05 * Double(k), 0.775)), tint, 0.014) }
        u.stroke(scene, flask, tint, 0.03)
        u.stroke(scene, u.line((0.73, 0.54), (0.82, 0.5), (0.82, 0.6), (0.73, 0.64)), tint, 0.03)
        let cap = Keyframes.value(t, [(0.3, 0), (0.6, 1), (3.9, 1), (4.2, 0)])
        scene.fill(u.capsule(0.86 + 0.08 * cap, 0.55 - 0.18 * cap, 0.06, 0.14, corner: 0.015), with: .color(tint))
        let aspirate = Keyframes.value(t, [(0.6, 0), (0.9, 1), (2.0, 1), (2.3, 0)])
        if aspirate > 0 {
            let tip = (0.2 + 0.7 * (1 - aspirate), 0.77)
            u.stroke(scene, u.line(tip, (tip.0 + 0.7, tip.1 - 0.3)), tint, 0.02)
        }
        let pour = Keyframes.value(t, [(2.3, 0), (2.5, 1), (3.5, 1), (3.8, 0)])
        if pour > 0 {
            let tip = (0.62 + 0.3 * (1 - pour), 0.66)
            u.stroke(scene, u.line(tip, (tip.0 + 0.5, tip.1 - 0.5)), tint, 0.03)
            if t > 2.5 && t < 3.5 { u.stroke(scene, u.line(tip, (tip.0 - 0.02, newLevel)), clay, 0.02) }
        }
    }
}

/// Trypsinising: the enzyme falls on the spread cells, their clay-dotted
/// footholds let go, they round up, and a tap on the flask lifts them off.
enum Trypsinisation {
    static let duration = 4.6
    private static let cells: [Double] = [0.16, 0.34, 0.52, 0.7, 0.88]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let tap = 0.012 * sin(t * 50) * Ease.clamp((t - 2.6) / 0.05) * (1 - Ease.clamp((t - 2.9) / 0.05))
        u.stroke(scene, u.line((0.02 + tap, 0.74), (0.98 + tap, 0.74)), tint, 0.035)
        for k in 0..<10 {
            let fall = Ease.clamp((t - 0.3 - 0.1 * Double(k)) / 0.8)
            guard fall > 0, fall < 1 else { continue }
            scene.fill(u.circle(0.06 + 0.09 * Double(k), 0.1 + 0.6 * fall, 0.01), with: .color(clay.opacity(1 - fall * 0.5)))
        }
        for (k, x) in cells.enumerated() {
            let s = Double(k)
            let loose = Ease.clamp((t - 1.0 - 0.12 * s) / 0.4)
            let round = Ease.inOut((t - 1.4 - 0.1 * s) / 0.6)
            let lift = Ease.inOut((t - 2.6 - 0.08 * s) / 1.0)
            let w = 0.16 - 0.06 * round, h = 0.045 + 0.055 * round
            let y = 0.74 - h / 2 - 0.4 * lift + 0.02 * sin(t * 3 + s) * lift
            scene.fill(u.ellipse(x, y, w, h), with: .color(tint.opacity(0.15)))
            u.stroke(scene, u.ellipse(x, y, w, h), tint, 0.016)
            scene.fill(u.circle(x, y, 0.015), with: .color(clay))
            for f in [-0.05, 0.0, 0.05] where loose < 1 {
                scene.fill(u.circle(x + f, 0.735, 0.008), with: .color(clay.opacity(1 - loose)))
            }
        }
    }
}

/// The sharps bin: a used syringe turns needle-down, drops through the lid's
/// slot, and the flap closes behind it.
enum SharpsBin {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.0) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let x = Keyframes.value(t, [(0.2, 0.86), (0.9, 0.5)])
        let y = Keyframes.value(t, [(0.2, 0.12), (0.9, 0.2), (1.0, 0.2), (1.5, 0.62)])
        let turn = Keyframes.value(t, [(0.2, -60), (0.9, 0)])
        var syringe = scene
        syringe.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(0.44))))
        let p = u.pt(x, y)
        syringe.translateBy(x: p.x, y: p.y)
        syringe.rotate(by: .degrees(turn))
        syringe.fill(Path(roundedRect: CGRect(x: -u.len(0.03), y: -u.len(0.16), width: u.len(0.06), height: u.len(0.16)), cornerRadius: u.len(0.01)),
                     with: .color(tint.opacity(0.4)))
        syringe.stroke(Path(roundedRect: CGRect(x: -u.len(0.03), y: -u.len(0.16), width: u.len(0.06), height: u.len(0.16)), cornerRadius: u.len(0.01)),
                       with: .color(tint), lineWidth: u.len(0.015))
        var needle = Path()
        needle.move(to: .zero)
        needle.addLine(to: CGPoint(x: 0, y: u.len(0.1)))
        syringe.stroke(needle, with: .color(tint), lineWidth: u.len(0.01))
        var plunger = Path()
        plunger.move(to: CGPoint(x: 0, y: -u.len(0.16)))
        plunger.addLine(to: CGPoint(x: 0, y: -u.len(0.22)))
        syringe.stroke(plunger, with: .color(tint), lineWidth: u.len(0.015))
        // The bin: clay body, fill line and mark in ivory, the lid and flap.
        scene.fill(u.capsule(0.5, 0.68, 0.5, 0.44, corner: 0.03), with: .color(clay))
        scene.stroke(u.line((0.3, 0.56), (0.7, 0.56)), with: .color(ivory.opacity(0.8)),
                     style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.02), u.len(0.015)]))
        for k in 0..<3 {
            let a = (-90 + 120 * Double(k)) * .pi / 180
            u.stroke(scene, u.circle(0.5 + 0.035 * cos(a), 0.72 + 0.035 * sin(a), 0.04), ivory, 0.016)
        }
        scene.fill(u.circle(0.5, 0.72, 0.012), with: .color(ivory))
        scene.fill(u.capsule(0.5, 0.45, 0.54, 0.06, corner: 0.02), with: .color(tint))
        let open = Keyframes.value(t, [(0.9, 0), (1.0, 1), (1.6, 1), (1.8, 0)])
        u.stroke(scene, u.line((0.42, 0.42), (0.42 + 0.16 * cos(-open * 1.2), 0.42 + 0.16 * sin(-open * 1.2))), tint, 0.03)
    }
}

/// Opening a PFA ampoule: snapped at the clay dot on its neck, the top
/// breaks away, fumes rise, and the pipette draws the fixative up.
enum PFAAmpoule {
    static let duration = 4.8

    private static func glass(_ u: UnitSquare) -> Path {
        u.line((0.48, 0.38), (0.48, 0.42), (0.41, 0.48), (0.41, 0.86), (0.59, 0.86), (0.59, 0.48), (0.52, 0.42), (0.52, 0.38))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let drawn = Keyframes.value(t, [(2.7, 0), (3.6, 1)])
        BenchShapes.fill(scene, u, glass(u), from: 0.54 + 0.26 * drawn, tint.opacity(0.3))
        u.stroke(scene, glass(u), tint, 0.025)
        // The top: on, then snapped away.
        let snap = Ease.inOut((t - 1.2) / 0.7)
        if snap < 1 {
            var top = scene
            let hinge = u.pt(0.52, 0.38)
            top.translateBy(x: hinge.x + u.len(0.2 * snap), y: hinge.y + u.len(0.3 * snap * snap))
            top.rotate(by: .degrees(70 * snap))
            top.translateBy(x: -hinge.x, y: -hinge.y)
            top.opacity = 1 - snap
            u.stroke(top, u.line((0.48, 0.38), (0.48, 0.34), (0.45, 0.3), (0.45, 0.22), (0.5, 0.16), (0.55, 0.22), (0.55, 0.3), (0.52, 0.34), (0.52, 0.38)), tint, 0.025)
        }
        if t < 1.2 { scene.fill(u.circle(0.5, 0.38, 0.018), with: .color(clay)) }
        let crack = sin(.pi * Ease.clamp((t - 1.15) / 0.3))
        if crack > 0 { scene.fill(Sparkles.star(u, 0.5, 0.38, 0.06 * crack), with: .color(clay)) }
        for k in 0..<2 {
            let rise = ((t - 1.4 - 0.4 * Double(k)) / 1.2)
            guard rise > 0, rise < 1 else { continue }
            let wisp = stride(from: 0.0, through: 0.12, by: 0.012).map { d in (0.5 + 0.015 * sin(d * 50 - t * 6 + Double(k)), 0.34 - d - 0.12 * rise) }
            u.stroke(scene, u.polyline(wisp), tint.opacity(0.5 * (1 - rise)), 0.014)
        }
        let dip = Keyframes.value(t, [(2.2, 0), (2.6, 1), (3.7, 1), (4.1, 0)])
        if dip > 0 {
            let tipY = 0.08 + 0.72 * dip
            u.stroke(scene, u.line((0.5, tipY), (0.5, tipY - 0.5)), tint, 0.022)
            let held = drawn * 0.3
            if held > 0 { u.stroke(scene, u.line((0.5, tipY - 0.02), (0.5, tipY - 0.02 - held)), tint.opacity(0.5), 0.022) }
        }
    }
}

/// Digital calipers: the sliding jaw closes on the clay sample, the reading
/// runs down and settles at 16.0 mm, and the jaw opens again.
enum Calipers {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let slider = Keyframes.value(t, [(0.3, 0.64), (1.4, 0.3), (2.8, 0.3), (3.7, 0.64)])
        scene.fill(u.capsule(0.52, 0.3, 0.86, 0.05, corner: 0.01), with: .color(tint))
        var fixed = u.line((0.1, 0.28), (0.14, 0.28), (0.14, 0.64), (0.12, 0.66), (0.1, 0.62))
        fixed.closeSubpath()
        scene.fill(fixed, with: .color(tint))
        scene.fill(u.circle(0.22, 0.52, 0.08), with: .color(clay))
        var moving = u.line((slider, 0.28), (slider + 0.04, 0.28), (slider + 0.04, 0.62), (slider + 0.02, 0.66), (slider, 0.64))
        moving.closeSubpath()
        scene.fill(moving, with: .color(tint))
        scene.drawLayer { layer in
            layer.fill(u.capsule(slider + 0.13, 0.26, 0.24, 0.14, corner: 0.02), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.capsule(slider + 0.13, 0.25, 0.19, 0.08, corner: 0.01), with: .color(.black))
        }
        let tenths = Int(((slider - 0.14) * 100 * 10).rounded())
        let digits = [(tenths / 100) % 10, (tenths / 10) % 10, tenths % 10]
        for (k, d) in digits.enumerated() {
            SevenSegment.draw(scene, u, SevenSegment.digits[d], x: slider + 0.07 + 0.055 * Double(k), y: 0.25, w: 0.03, h: 0.05, color: clay, width: 0.01)
        }
        scene.fill(u.circle(slider + 0.15, 0.275, 0.005), with: .color(clay))
    }
}
