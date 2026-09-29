// NatureScenes.swift
// ScienceStatus — patterns in nature and physics: sand on a singing plate,
// pendulums in and out of step, light bent round a mass, a snowflake,
// an earthquake, a sunflower, the wood-wide web, tree rings, and cheese.
// Each draws in a unit square (see `UnitSquare`): matter in the tint, the
// driver, the light, the signal or the special year in clay.

import SwiftUI

/// A Chladni plate: scattered sand dances as the plate is driven, gathers
/// on the nodal lines where it stays still, then shifts to a finer figure
/// at a higher note.
enum Chladni {
    static let duration = 4.8
    private static let grains = 200

    private static func mode(_ k: Int, _ x: Double, _ y: Double) -> Double {
        k == 0 ? cos(.pi * x) * cos(3 * .pi * y) - cos(3 * .pi * x) * cos(.pi * y)
               : cos(2 * .pi * x) * cos(5 * .pi * y) + cos(5 * .pi * x) * cos(2 * .pi * y)
    }

    /// Places evenly spread along a figure's nodal lines, one per grain:
    /// points within a hair of a line, judged by distance rather than by
    /// value, so the sand doesn't heap where lines cross and the plate
    /// barely moves.
    private static func places(_ k: Int) -> [(Double, Double)] {
        var list: [(Double, Double)] = []
        let e = 0.001
        for i in 0..<160 {
            for j in 0..<160 {
                let x = (Double(i) + 0.5) / 160, y = (Double(j) + 0.5) / 160
                let f = mode(k, x, y)
                let gx = (mode(k, x + e, y) - mode(k, x - e, y)) / (2 * e)
                let gy = (mode(k, x, y + e) - mode(k, x, y - e)) / (2 * e)
                if abs(f) < 0.004 * hypot(gx, gy) { list.append((x, y)) }
            }
        }
        return (0..<grains).map { list[$0 * list.count / grains] }
    }

    /// Takes the free place nearest `p` out of `free`.
    private static func claim(_ p: (Double, Double), from free: inout [(Double, Double)]) -> (Double, Double) {
        var best = 0, bestD = 9.0
        for (j, q) in free.enumerated() where hypot(q.0 - p.0, q.1 - p.1) < bestD {
            bestD = hypot(q.0 - p.0, q.1 - p.1)
            best = j
        }
        return free.remove(at: best)
    }

    private static let paths: [(start: (Double, Double), first: (Double, Double), second: (Double, Double))] = {
        var a = places(0), b = places(1)
        return (0..<grains).map { k in
            let s = Double(k)
            let start = (BenchShapes.rand(s + 1), BenchShapes.rand(s + 400))
            let first = claim(start, from: &a)
            return (start, first, claim(first, from: &b))
        }
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.capsule(0.5, 0.5, 0.84, 0.84, corner: 0.01), tint, 0.03)
        let settle = Ease.inOut((t - 0.5) / 1.3), shift = Ease.inOut((t - 2.6) / 1.0)
        let buzz = Ease.clamp((t - 0.3) / 0.2)
        for (k, g) in paths.enumerated() {
            let s = Double(k)
            let a = (g.start.0 + (g.first.0 - g.start.0) * settle, g.start.1 + (g.first.1 - g.start.1) * settle)
            let p = (a.0 + (g.second.0 - a.0) * shift, a.1 + (g.second.1 - a.1) * shift)
            let still = shift > 0 ? 1 - sin(.pi * shift) : settle
            let jitter = 0.012 * buzz * (1 - still) * sin(t * 40 + s)
            scene.fill(u.circle(0.08 + 0.84 * p.0 + jitter, 0.08 + 0.84 * p.1 - jitter, 0.009), with: .color(tint))
        }
        let drive = 1 + 0.25 * sin(t * 30) * buzz
        scene.fill(u.circle(0.5, 0.5, 0.022 * drive), with: .color(clay))
    }
}

/// A pendulum wave from above: twelve pendulums of graded lengths let go
/// together, drift into travelling snakes, a scramble, standing waves, and
/// come back into one line.
enum PendulumWave {
    static let duration = 6.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.5), (0.96, 0.5)), tint.opacity(0.3), 0.02)
        for k in 0..<12 {
            let x = 0.08 + 0.076 * Double(k)
            let swings = Double(5 + k)
            let y = 0.5 + 0.34 * cos(2 * .pi * swings * t / duration)
            u.stroke(context, u.line((x, 0.5), (x, y)), tint.opacity(0.6), 0.018)
            context.fill(u.circle(x, y, 0.028), with: .color(clay))
        }
    }
}

/// An Einstein ring: a background star passes behind a dark mass; its light
/// is bent into two images that stretch into arcs, close into a clay ring
/// at perfect alignment, and part again.
enum EinsteinRing {
    static let duration = 4.8
    private static let einstein = 0.24, source = 0.06

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = u.pt(0.5, 0.5)
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - u.len(einstein), y: centre.y - u.len(einstein), width: u.len(2 * einstein), height: u.len(2 * einstein))),
                       with: .color(tint.opacity(0.25)), style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.02), u.len(0.025)]))
        // The star's true place, which is never seen: only its two images are.
        let bx = Keyframes.value(t, [(0.2, -0.3), (2.0, 0), (2.8, 0), (4.6, 0.3)]), by = 0.0
        let beta = hypot(bx, by)
        let direction = atan2(by, bx)
        let root = sqrt(beta * beta + 4 * einstein * einstein)
        let outer = (beta + root) / 2, inner = (root - beta) / 2
        let spread = beta > source ? asin(min(1, source / beta)) : .pi
        for (r, a, alpha, width) in [(outer, direction, 1.0, 0.045), (inner, direction + .pi, 0.6, 0.03)] {
            var arc = Path()
            arc.addArc(center: centre, radius: u.len(r), startAngle: .radians(a - spread), endAngle: .radians(a + spread), clockwise: false)
            if spread < .pi { u.stroke(context, arc, clay.opacity(alpha), width) }
            else { u.stroke(context, u.circle(0.5, 0.5, r), clay.opacity(alpha), width) }
        }
        context.fill(u.circle(0.5, 0.5, 0.045), with: .color(tint))
    }
}

/// A snowflake growing: a small hexagonal plate, then six arms that grow
/// out in step, side branches budding off each at the same moments.
enum Snowflake {
    static let duration = 5.0
    private static let branches: [(at: Double, length: Double)] = [(0.12, 0.09), (0.19, 0.11), (0.26, 0.08), (0.32, 0.05)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.5) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let grow = Ease.out((t - 0.4) / 2.8)
        let plate = Ease.outBack(0.3 + t / 0.5)
        let arm = 0.4 * grow
        let turn = 0.08 * Ease.inOut((t - 3.3) / 1.2)
        let centre = (0.5, 0.5)
        if plate > 0 {
            var hex = u.polyline((0..<6).map { k in Rings.offset(centre, 0.06 * plate, 60 * Double(k) + turn * 180 / .pi) })
            hex.closeSubpath()
            u.stroke(scene, hex, tint, 0.035)
        }
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + turn
            let dir = (cos(a), sin(a))
            guard arm > 0.06 else { continue }
            u.stroke(scene, u.line((centre.0 + dir.0 * 0.06, centre.1 + dir.1 * 0.06), (centre.0 + dir.0 * arm, centre.1 + dir.1 * arm)), tint, 0.035)
            if grow < 0.98 { scene.fill(u.circle(centre.0 + dir.0 * arm, centre.1 + dir.1 * arm, 0.018), with: .color(clay)) }
            for b in branches where arm > b.at {
                let length = min(b.length, (arm - b.at) * 0.9)
                let base = (centre.0 + dir.0 * b.at, centre.1 + dir.1 * b.at)
                for side in [-1.0, 1.0] {
                    let ba = a + side * .pi / 3
                    let end = (base.0 + cos(ba) * length, base.1 + sin(ba) * length)
                    u.stroke(scene, u.line(base, end), tint, 0.028)
                    if length < b.length * 0.98 { scene.fill(u.circle(end.0, end.1, 0.012), with: .color(clay)) }
                }
            }
        }
    }
}

/// A seismograph: from the clay epicentre the P wave and then the slower S
/// wave spread out across the map; as each reaches the station the drum
/// trace shows it, then the big surface waves roll in and die away.
enum Seismograph {
    static let duration = 5.0
    private static let epicentre = (0.18, 0.24), station = (0.8, 0.24)
    private static let start = 0.3, pSpeed = 0.5, sSpeed = 0.28
    private static var distance: Double { hypot(station.0 - epicentre.0, station.1 - epicentre.1) }

    private static func ground(_ s: Double) -> Double {
        let p = start + distance / pSpeed, sw = start + distance / sSpeed, rayleigh = sw + 0.5
        var v = 0.004 * sin(s * 90)
        if s > p { v += 0.035 * exp(-(s - p) / 0.6) * sin((s - p) * 70) }
        if s > sw { v += 0.07 * exp(-(s - sw) / 0.6) * sin((s - sw) * 38) }
        if s > rayleigh { v += 0.1 * exp(-(s - rayleigh) / 0.9) * sin((s - rayleigh) * 14) }
        return v
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(Sparkles.star(u, epicentre.0, epicentre.1, 0.075), with: .color(clay))
        var mark = u.polyline([(station.0, station.1 - 0.05), (station.0 + 0.042, station.1 + 0.035), (station.0 - 0.042, station.1 + 0.035)])
        mark.closeSubpath()
        scene.fill(mark, with: .color(tint))
        for (speed, width) in [(pSpeed, 0.015), (sSpeed, 0.03)] {
            let r = speed * (t - start)
            guard r > 0, r < distance + 0.2 else { continue }
            var ring = scene
            ring.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(0.5))))
            u.stroke(ring, u.circle(epicentre.0, epicentre.1, r), tint.opacity(0.6 * (1 - r / (distance + 0.2))), width)
        }
        // The drum's paper, the trace scrolling across it to the pen.
        u.stroke(scene, u.capsule(0.5, 0.74, 0.88, 0.3, corner: 0.03), tint.opacity(0.35), 0.015)
        let window = 3.0
        let trace = stride(from: max(0, t - window), through: t, by: 0.004).map { s in (0.86 - 0.8 * (t - s) / window, 0.73 - ground(s)) }
        if trace.count > 1 { u.stroke(scene, u.polyline(trace), tint, 0.018) }
        scene.fill(u.circle(0.86, 0.73 - ground(t), 0.018), with: .color(clay))
        for arrival in [start + distance / pSpeed, start + distance / sSpeed] where arrival < t && t - arrival < window {
            let x = 0.86 - 0.8 * (t - arrival) / window
            u.stroke(scene, u.line((x, 0.845), (x, 0.87)), clay, 0.018)
        }
    }
}

/// Phyllotaxis: seeds set down one after another, each 137.5° round from the
/// last, build a sunflower head; then one family of its spirals is picked
/// out in clay.
enum Phyllotaxis {
    static let duration = 5.0
    private static let seeds = 240

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.5) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let shown = Int(Double(seeds) * Ease.clamp((t - 0.2) / 3.0))
        let highlight = Ease.inOut((t - 3.3) / 0.5)
        for n in 1...max(1, shown) where shown > 0 {
            let a = Double(n) * 137.508 * .pi / 180
            let r = 0.026 * sqrt(Double(n))
            let family = (n % 21) % 3 == 0
            let color = family && highlight > 0 ? clay.opacity(0.35 + 0.65 * highlight) : tint
            scene.fill(u.circle(0.5 + r * cos(a), 0.5 + r * sin(a), 0.011 + 0.008 * Double(n) / Double(seeds)), with: .color(color))
        }
    }
}

/// The wood-wide web: under the soil, fungal threads join a big tree's
/// roots to a seedling's, and clay nutrients run along them until the
/// seedling puts out its leaves.
enum Mycorrhizal {
    static let duration = 5.0
    private static let hyphae: [[(Double, Double)]] = [
        [(0.18, 0.74), (0.34, 0.8), (0.52, 0.74), (0.7, 0.66)],
        [(0.3, 0.84), (0.48, 0.88), (0.64, 0.8), (0.78, 0.64)],
        [(0.36, 0.66), (0.5, 0.6), (0.64, 0.62), (0.74, 0.58)],
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.02, 0.46), (0.98, 0.46)), tint, 0.03)
        scene.fill(u.capsule(0.26, 0.36, 0.05, 0.2, corner: 0.02), with: .color(tint))
        // The crown as one shape, so its lobes don't double up as it fades.
        var crown = Path()
        for (x, y, r) in [(0.18, 0.25, 0.08), (0.34, 0.25, 0.08), (0.26, 0.16, 0.095)] { crown.addPath(u.circle(x, y, r)) }
        scene.fill(crown, with: .color(tint))
        for end in [(0.12, 0.7), (0.2, 0.8), (0.32, 0.86), (0.38, 0.68)] {
            u.stroke(scene, u.polyline(Smooth.curve([(0.26, 0.46), ((0.26 + end.0) / 2, (0.46 + end.1) / 2 + 0.03), end], samples: 5)), tint, 0.025)
        }
        let perk = Ease.outBack((t - 3.0) / 0.8)
        let bud = (0.76, 0.36 - 0.05 * perk)
        u.stroke(scene, u.line((0.76, 0.46), bud), tint, 0.028)
        for side in [-1.0, 1.0] {
            var leaf = scene
            let p = u.pt(bud.0, bud.1)
            leaf.translateBy(x: p.x, y: p.y)
            leaf.rotate(by: .degrees(side * (60 - 25 * perk)))
            let w = u.len(0.045 + 0.04 * perk), h = u.len(0.026 + 0.014 * perk)
            leaf.fill(Path(ellipseIn: CGRect(x: side > 0 ? 0 : -w, y: -h / 2, width: w, height: h)), with: .color(tint))
        }
        for end in [(0.7, 0.6), (0.8, 0.62), (0.76, 0.56)] { u.stroke(scene, u.line((0.76, 0.46), end), tint, 0.018) }
        let reach = Ease.inOut((t - 0.3) / 1.2)
        for (k, h) in hyphae.enumerated() {
            let curve = Smooth.curve(h, samples: 8)
            let shown = Array(curve.prefix(max(2, Int(Double(curve.count) * reach))))
            u.stroke(scene, u.polyline(shown), tint.opacity(0.6), 0.016)
            for j in 0..<3 {
                let s = ((t - 1.6 - 0.25 * Double(j) - 0.15 * Double(k)) / 1.4)
                guard s > 0, s < 1, t < 4.2 else { continue }
                let p = Polyline.point(curve, at: s)
                scene.fill(u.circle(p.0, p.1, 0.02), with: .color(clay))
            }
        }
    }
}

/// Tree rings: year by year the trunk adds a ring, wide in good years and
/// thin in hard ones; the drought year stands out in clay, and the bark
/// closes it round.
enum TreeRings {
    static let duration = 5.0
    private static let widths: [Double] = [0.034, 0.03, 0.04, 0.026, 0.032, 0.012, 0.036, 0.03, 0.028, 0.032]
    private static let drought = 5

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.circle(0.5, 0.5, 0.03), with: .color(tint))
        var radius = 0.03
        for (k, w) in widths.enumerated() {
            let grow = Ease.out((t - 0.3 - 0.32 * Double(k)) / 0.28)
            guard grow > 0 else { break }
            radius += w * grow
            let ring = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.08).map { a -> (Double, Double) in
                let r = radius + 0.004 * sin(5 * a + Double(k)) + 0.003 * cos(3 * a)
                return (0.5 + r * cos(a), 0.5 + r * sin(a))
            }
            u.stroke(scene, u.polyline(ring), k == drought ? clay : tint.opacity(0.75), k == drought ? 0.02 : 0.014)
        }
        let bark = Ease.inOut((t - 3.6) / 0.5)
        if bark > 0 {
            let outline = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.06).map { a -> (Double, Double) in
                let r = radius + 0.03 + 0.008 * sin(17 * a)
                return (0.5 + r * cos(a), 0.5 + r * sin(a))
            }
            u.stroke(scene, u.polyline(outline), tint.opacity(bark), 0.045)
        }
    }
}

/// Making cheese, seen from above: clay rennet drips into the vat and
/// ripples out, the milk sets to curd, the knife cuts it one way and then
/// the other, and the cubes draw in and round off as the whey runs from them.
enum CheeseMaking {
    static let duration = 5.0
    private static let columns = 6, rows = 4
    private static let x0 = 0.15, y0 = 0.24, w = 0.7, h = 0.52
    private static let drops: [(x: Double, y: Double, at: Double)] = [(0.34, 0.38, 0.15), (0.64, 0.34, 0.35), (0.5, 0.62, 0.55)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let set = Ease.inOut((t - 1.0) / 0.6)
        let across = Ease.inOut((t - 1.7) / 0.55), down = Ease.inOut((t - 2.35) / 0.55)
        let shrink = Ease.inOut((t - 3.0) / 1.2)
        let cellW = w / Double(columns), cellH = h / Double(rows)
        let curd = tint.opacity(0.14 + 0.36 * set)
        if t < 3.0 {
            // One slab, with the knife's cuts taken out of it as it passes.
            scene.drawLayer { layer in
                layer.fill(u.capsule(x0 + w / 2, y0 + h / 2, w, h, corner: 0.02), with: .color(curd))
                layer.blendMode = .destinationOut
                for c in 1..<columns where across * w > cellW * Double(c) {
                    let x = x0 + cellW * Double(c)
                    layer.stroke(u.line((x, y0 - 0.01), (x, y0 + h + 0.01)), with: .color(.black), lineWidth: u.len(0.016))
                }
                for r in 1..<rows where down * h > cellH * Double(r) {
                    let y = y0 + cellH * Double(r)
                    layer.stroke(u.line((x0 - 0.01, y), (x0 + w + 0.01, y)), with: .color(.black), lineWidth: u.len(0.016))
                }
            }
        } else {
            let inset = 0.008 + 0.012 * shrink
            for c in 0..<columns {
                for r in 0..<rows {
                    let cx = x0 + cellW * (Double(c) + 0.5), cy = y0 + cellH * (Double(r) + 0.5)
                    scene.fill(u.capsule(cx, cy, cellW - 2 * inset, cellH - 2 * inset, corner: 0.004 + 0.014 * shrink), with: .color(curd))
                }
            }
        }
        u.stroke(scene, u.capsule(0.5, 0.5, 0.8, 0.64, corner: 0.06), tint, 0.035)
        for d in drops {
            let age = (t - d.at) / 0.8
            guard age > 0, age < 1 else { continue }
            scene.fill(u.circle(d.x, d.y, 0.026 * (1 - age)), with: .color(clay))
            u.stroke(scene, u.circle(d.x, d.y, 0.03 + 0.1 * Ease.out(age)), clay.opacity(1 - age), 0.015)
        }
        if across > 0 && across < 1 { u.stroke(scene, u.line((x0 + w * across, 0.14), (x0 + w * across, 0.86)), tint, 0.03) }
        if down > 0 && down < 1 { u.stroke(scene, u.line((0.06, y0 + h * down), (0.94, y0 + h * down)), tint, 0.03) }
    }
}
