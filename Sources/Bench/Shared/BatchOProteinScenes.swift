// BatchOProteinScenes.swift
// ScienceStatus — proteins at work: a targeted degrader, an allosteric switch, the collagen braid.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

private func BatchOMix(_ a: Double, _ b: Double, _ e: Double) -> Double { a + (b - a) * e }

/// Targeted degrader: a small clay dumbbell floats inside the arch of an E3 ligase, a clamp hanging open
/// side down, with a target protein waiting below. The dumbbell drops out of the arch and docks one head in a
/// pocket on top of the target, then lifts the target up into the clamp and seats its other head in the
/// clamp's own pocket, so the three sit together. Three ubiquitin dots pop onto the target one by one into a
/// short chain. The
/// dumbbell lets go, drifts back up into the arch, and the tagged target drops out of the clamp and slides
/// off to the right while a fresh target slides in from the left to wait: the same picture as the start.
enum TargetedDegrader {
    static let duration = 6.0

    private static let railX = 0.5, railY = 0.68      // where a target waits, under the clamp
    private static let tr = 0.125                      // target radius
    private static let e3 = (x: 0.5, y: 0.345)          // the clamp's centre
    private static let e3Outer = 0.325, e3Inner = 0.195
    private static let mouth = 85.0 * Double.pi / 180  // half-angle of the clamp's opening, which faces down
    private static let pocketDepth = 0.03
    private static let sep = 0.14, headR = 0.046       // dumbbell: head spacing and head radius
    private static let pocketLift = 0.036              // head centre above a pocket's floor
    private static let floatY = e3.y + 0.015

    /// The target's outline round its centre: lumpy, with a pocket in the top.
    private static func targetR(_ a: Double) -> Double {
        let wobble = 1 + 0.05 * sin(3 * a + 0.9) + 0.03 * sin(5 * a + 2.1)
        return tr * wobble - pocketDepth * exp(-pow((a + Double.pi / 2) / 0.4, 2))
    }
    private static let target: [(Double, Double)] = (0..<72).map { i -> (Double, Double) in
        let a = -Double.pi + 2 * Double.pi * Double(i) / 72
        return (targetR(a) * cos(a), targetR(a) * sin(a))
    }
    private static let floorR = targetR(-Double.pi / 2)

    /// The E3: a thick C hanging open-side down, with a pocket in the middle of its ceiling.
    private static let clamp: [(Double, Double)] = {
        let a0 = Double.pi / 2 + mouth, a1 = 2.5 * Double.pi - mouth
        let mid = (e3Outer + e3Inner) / 2, cap = (e3Outer - e3Inner) / 2
        var pts: [(Double, Double)] = []
        for i in 0...40 {
            let a = a0 + (a1 - a0) * Double(i) / 40
            pts.append((e3Outer * cos(a), e3Outer * sin(a)))
        }
        for i in 1..<12 {
            let p = a1 + Double.pi * Double(i) / 12
            pts.append((mid * cos(a1) + cap * cos(p), mid * sin(a1) + cap * sin(p)))
        }
        for i in 0...40 {
            let a = a1 - (a1 - a0) * Double(i) / 40
            let r = e3Inner + pocketDepth * exp(-pow((a - 1.5 * Double.pi) / 0.26, 2))
            pts.append((r * cos(a), r * sin(a)))
        }
        for i in 1..<12 {
            let p = a0 + Double.pi + Double.pi * Double(i) / 12
            pts.append((mid * cos(a0) + cap * cos(p), mid * sin(a0) + cap * sin(p)))
        }
        return pts
    }()

    /// Where the target sits once the dumbbell has seated its upper head in the clamp's pocket.
    private static let liftedY: Double = {
        let ceiling = e3.y - e3Inner - pocketDepth
        return ceiling + pocketLift + sep + floorR + pocketLift
    }()

    /// The tagged target: waits under the clamp, is lifted into it, drops out again and slides off right.
    private static func tagged(_ t: Double) -> (x: Double, y: Double) {
        let lift = Ease.inOut((t - 1.4) / 1.0)
        let drop = Ease.inOut((t - 3.75) / 0.75)
        return (railX + 0.8 * Ease.inOut((t - 4.3) / 1.0), railY + (liftedY - railY) * (lift - drop))
    }

    /// The dumbbell free: drifting and tilting a little inside the arch.
    private static func floating(_ t: Double) -> (x: Double, y: Double, a: Double) {
        let w = 2 * Double.pi * t / duration
        return (railX + 0.02 * sin(w), floatY + 0.012 * sin(2 * w), -0.25 + 0.1 * sin(2 * w + 1.2))
    }

    /// The dumbbell upright over a target at height `ty`: lower head in its pocket, upper head above.
    private static func docked(_ ty: Double) -> (x: Double, y: Double, a: Double) {
        (railX, ty - floorR - pocketLift - sep / 2, -Double.pi / 2)
    }

    private static func target(_ c: GraphicsContext, _ u: UnitSquare, _ tint: Color, at p: (Double, Double)) {
        var shape = u.polyline(target.map { (p.0 + $0.0, p.1 + $0.1) })
        shape.closeSubpath()
        c.fill(shape, with: .color(tint.opacity(0.16)))
        u.stroke(c, shape, tint, 0.055)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var c = context
        c.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))
        c.translateBy(x: 0, y: u.len(0.09))    // the scene is laid out high; this centres arch and target

        var ligase = u.polyline(clamp.map { (e3.x + $0.0, e3.y + $0.1) })
        ligase.closeSubpath()
        c.fill(ligase, with: .color(tint.opacity(0.16)))
        u.stroke(c, ligase, tint, 0.055)

        // The tagged target, with its ubiquitin dots chained to one side, then the fresh one sliding in.
        let at = tagged(t)
        if at.x < 1.25 {
            target(c, u, tint, at: (at.x, at.y))
            let heading = 26.0 * Double.pi / 180
            for k in 0..<3 {
                let grow = Ease.outBack((t - 2.5 - 0.4 * Double(k)) / 0.3)
                guard grow > 0 else { continue }
                let d = targetR(heading) + 0.038 + 0.068 * Double(k)
                let zig = (k % 2 == 0 ? -1.0 : 1.0) * 0.014
                let x = at.x + d * cos(heading) - zig * sin(heading)
                let y = at.y + d * sin(heading) + zig * cos(heading)
                c.fill(u.circle(x, y, 0.045 * grow), with: .color(tint))
            }
        }
        let fresh = railX - 0.78 + 0.78 * Ease.inOut((t - 4.7) / 1.0)
        if t > 4.6 { target(c, u, tint, at: (fresh, railY)) }

        // The dumbbell: riding the target while it is held, hanging from the clamp as the target leaves, free
        // before and after.
        let free = floating(t)
        var pose = free
        if t < 1.4 {
            let e = Ease.inOut((t - 0.5) / 0.9)
            let d = docked(railY)
            pose = (BatchOMix(free.x, d.x, e), BatchOMix(free.y, d.y, e), BatchOMix(free.a, d.a, e))
        } else if t < 4.0 {
            pose = docked(t < 3.75 ? at.y : liftedY)
        } else if t < 4.8 {
            let e = Ease.inOut((t - 4.0) / 0.8)
            let d = docked(liftedY)
            pose = (BatchOMix(d.x, free.x, e), BatchOMix(d.y, free.y, e), BatchOMix(d.a, free.a, e))
        }
        let h = sep / 2
        let lower = (pose.x - h * cos(pose.a), pose.y - h * sin(pose.a))
        let upper = (pose.x + h * cos(pose.a), pose.y + h * sin(pose.a))
        u.stroke(c, u.line(lower, upper), clay, 0.04)
        c.fill(u.circle(lower.0, lower.1, headR), with: .color(clay))
        c.fill(u.circle(upper.0, upper.1, headR), with: .color(clay))
    }
}

/// Allosteric switch: one protein of two lobes on a hinge, a narrow slit between them at the top; a substrate
/// dot waits above, too big for it. A clay effector docks in a notch on the far side of the right lobe, a
/// ripple runs out through the protein from it, and the lobes swing apart about the hinge so the slit opens
/// into a pocket. The substrate drops in. The effector leaves, the lobes relax shut, the substrate is
/// squeezed out and flicked away down the left, and a new substrate drifts in from the right to wait above
/// the slit.
enum AllostericSwitch {
    static let duration = 6.0

    private static let hx = 0.47, hy = 0.79            // the hinge
    private static let swing = 16.0 * Double.pi / 180  // how far each lobe turns when open
    private static let face = 0.014                    // inner faces sit this far from the hinge line
    private static let top = -0.50, bottom = 0.03      // a lobe's top and bottom, from the hinge
    private static let rightW = 0.30, leftW = 0.26
    private static let dotR = 0.048
    private static let hover = (x: 0.47, y: 0.14)      // where the substrate waits
    private static let perch = (x: 0.92, y: 0.40)      // where the effector waits
    private static let siteY = -0.24                   // height of the notch on the right lobe

    /// A lobe's outline, relative to the hinge: a rounded box with a flat inner face and a slight bulge
    /// on the outer side; the right lobe also has a round notch in its outer wall for the effector.
    private static func lobe(width x1: Double, notch: Bool) -> [(Double, Double)] {
        let x0 = face, y0 = top, y1 = bottom
        let rTL = 0.05, rTR = 0.15, rBR = 0.14, rBL = 0.02
        func arc(_ cx: Double, _ cy: Double, _ r: Double, from a: Double, to b: Double) -> [(Double, Double)] {
            (0...10).map { i -> (Double, Double) in
                let s = (a + (b - a) * Double(i) / 10) * Double.pi / 180
                return (cx + r * cos(s), cy + r * sin(s))
            }
        }
        var p: [(Double, Double)] = []
        p += arc(x0 + rTL, y0 + rTL, rTL, from: 180, to: 270)
        p += arc(x1 - rTR, y0 + rTR, rTR, from: 270, to: 360)
        if notch {
            let r = 0.062, d = 0.012, h = (r * r - d * d).squareRoot()
            let s = atan2(-h, -d), e = atan2(h, -d) - 2 * Double.pi
            for i in 0...14 {
                let a = s + (e - s) * Double(i) / 14
                p.append((x1 + d + r * cos(a), siteY + r * sin(a)))
            }
        }
        p += arc(x1 - rBR, y1 - rBR, rBR, from: 0, to: 90)
        p += arc(x0 + rBL, y1 - rBL, rBL, from: 90, to: 180)
        return p.map { bulge($0, width: x1) }
    }
    private static func bulge(_ q: (Double, Double), width x1: Double) -> (Double, Double) {
        let along = (q.0 - face) / (x1 - face), down = (q.1 - top) / (bottom - top)
        return (q.0 + 0.025 * along * sin(Double.pi * down), q.1)
    }
    private static let right = lobe(width: rightW, notch: true)
    private static let left = lobe(width: leftW, notch: false).map { (-$0.0, $0.1) }
    /// The notch's centre on the right lobe.
    private static let site = bulge((rightW + 0.006, siteY), width: rightW)

    private static func turn(_ p: (Double, Double), by a: Double) -> (Double, Double) {
        (hx + p.0 * cos(a) - p.1 * sin(a), hy + p.0 * sin(a) + p.1 * cos(a))
    }

    // Timeline.
    private static let relaxStart = 3.7, relaxLength = 1.0
    private static func openness(_ t: Double) -> Double {
        Ease.inOut((t - 1.1) / 1.0) - Ease.inOut((t - relaxStart) / relaxLength)
    }
    /// How high above the hinge a dot sits wedged in the slit when the lobes are turned by `a`.
    private static func wedge(_ a: Double) -> Double { (dotR + 0.03 - face) / sin(max(a, 0.01)) }
    private static let cap = 0.58                       // the height at which a squeezed dot pops free
    private static let popAt: Double = {                // the moment it does
        var lo = relaxStart, hi = relaxStart + relaxLength
        for _ in 0..<40 {
            let m = (lo + hi) / 2
            let a = swing * (1 - Ease.inOut((m - relaxStart) / relaxLength))
            if wedge(a) < cap { lo = m } else { hi = m }
        }
        return hi
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var c = context
        c.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))

        let a = swing * openness(t)
        let w = 2 * Double.pi * t / duration
        let notch = turn(site, by: a)

        // Both lobes, each turned about the hinge: the right clockwise, the left the other way.
        var lobes: [Path] = []
        for (points, turnBy) in [(left, -a), (right, a)] {
            var shape = u.polyline(points.map { turn($0, by: turnBy) })
            shape.closeSubpath()
            lobes.append(shape)
        }
        for shape in lobes { c.fill(shape, with: .color(tint.opacity(0.16))) }

        // The ripple: two rings of darker tint spread out through both lobes from the notch.
        let spread = (t - 1.0) / 1.3
        if spread > 0 && spread < 1 {
            for shape in lobes {
                var inside = c
                inside.clip(to: shape)
                for lag in [0.0, 0.14] {
                    let r = 0.03 + 0.85 * Ease.out(spread) - lag
                    if r > 0.03 {
                        u.stroke(inside, u.circle(notch.0, notch.1, r), tint.opacity(0.5 * (1 - spread)), 0.035)
                    }
                }
            }
        }
        for shape in lobes { u.stroke(c, shape, tint, 0.06) }
        c.fill(u.circle(hx, hy, 0.034), with: .color(tint))

        // The effector: rides the right lobe's notch while docked.
        let waiting = (perch.x + 0.006 * sin(w), perch.y + 0.012 * sin(2 * w + 2.4))
        var effector = waiting
        if t < 1.15 {
            let e = Ease.inOut((t - 0.45) / 0.7)
            effector = (BatchOMix(waiting.0, notch.0, e), BatchOMix(waiting.1, notch.1, e))
        } else if t < 3.9 {
            let e = Ease.inOut((t - 3.2) / 0.7)
            effector = (BatchOMix(notch.0, waiting.0, e), BatchOMix(notch.1, waiting.1, e))
        }
        c.fill(u.circle(effector.0, effector.1, 0.055), with: .color(clay))

        // The substrate: waits above the slit, drops into the opened pocket, is squeezed out and flicked
        // away to the left as it closes; a new one drifts in from the right to wait.
        let wait = (hover.x + 0.012 * sin(w), hover.y + 0.011 * sin(2 * w + 0.7))
        var dot = wait
        if t >= 2.2 && t < popAt {
            if t < 2.9 {
                let e = Ease.inOut((t - 2.2) / 0.7)
                dot = (BatchOMix(wait.0, hx, e), BatchOMix(wait.1, hy - wedge(swing), e))
            } else {
                dot = (hx, hy - wedge(a))
            }
        } else if t >= popAt {
            let f = t - popAt
            dot = (hx - 0.75 * f, hy - cap - 0.30 * f + 0.5 * 1.9 * f * f)
            if t >= 4.9 {
                let e = Ease.out((t - 4.9) / 0.9)
                c.fill(u.circle(BatchOMix(1.08, wait.0, e), BatchOMix(-0.06, wait.1, e), dotR), with: .color(tint))
            }
        }
        c.fill(u.circle(dot.0, dot.1, dotR), with: .color(tint))
    }
}

/// Collagen braid: three strands, one clay and two tint, wound round each other into a triple helix that
/// runs across the square. Each is a sine wave a third of a turn behind the last; the half of a strand
/// that is nearer the viewer is drawn on top, with a gap cut in whatever it crosses. The helix is loose
/// and wavy at the left and winds tighter toward the right, and the whole thing scrolls along its axis
/// by exactly one turn a loop.
enum CollagenBraid {
    static let duration = 5.0

    private static let steps = 150
    private static let from = -0.06, to = 1.06
    private static let body = 0.08, gap = 0.032

    private static func swell(_ x: Double) -> Double { 0.215 - 0.06 * x }
    private static func turns(_ x: Double) -> Double { 2 * Double.pi * (1.0 * x + 0.5 * 0.5 * x * x) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var c = context
        c.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))
        let phase = 2 * Double.pi * t / duration
        let inks: [Color] = [clay, tint, tint.opacity(0.55)]

        // Each strand is cut where its depth passes through zero into far arcs and near arcs.
        var whole: [Path] = []
        var fars: [[Path]] = []
        var nears: [[Path]] = []
        for k in 0..<3 {
            var all = Path()
            var far: [Path] = [], near: [Path] = []
            var run = Path()
            var runNear = false
            var last: (x: Double, y: Double, z: Double)? = nil
            for i in 0...steps {
                let x = from + (to - from) * Double(i) / Double(steps)
                let a = turns(x) - phase - 2 * Double.pi * Double(k) / 3
                let p = (x: x, y: 0.5 + swell(x) * sin(a), z: cos(a))
                if let q = last {
                    if (q.z > 0) != (p.z > 0) {
                        let s = q.z / (q.z - p.z)
                        let m = u.pt(q.x + (p.x - q.x) * s, q.y + (p.y - q.y) * s)
                        run.addLine(to: m)
                        if runNear { near.append(run) } else { far.append(run) }
                        run = Path()
                        run.move(to: m)
                        runNear.toggle()
                    }
                    all.addLine(to: u.pt(p.x, p.y))
                    run.addLine(to: u.pt(p.x, p.y))
                } else {
                    all.move(to: u.pt(p.x, p.y))
                    run.move(to: u.pt(p.x, p.y))
                    runNear = p.z > 0
                }
                last = p
            }
            if runNear { near.append(run) } else { far.append(run) }
            whole.append(all)
            fars.append(far)
            nears.append(near)
        }

        // Far arcs first (a solid strand whole, since drawing it twice changes nothing; a see-through one in
        // its far arcs only); then a gap is cut round each near arc and the arc is drawn again on top.
        // The gap has square ends and a solid strand's redraw round ones, so no seam shows where an arc stops.
        let round = StrokeStyle(lineWidth: u.len(body), lineCap: .round, lineJoin: .round)
        let flat = StrokeStyle(lineWidth: u.len(body), lineCap: .butt, lineJoin: .round)
        let halo = StrokeStyle(lineWidth: u.len(body + 2 * gap), lineCap: .butt, lineJoin: .round)
        c.drawLayer { layer in
            for k in 0..<3 {
                if k < 2 { layer.stroke(whole[k], with: .color(inks[k]), style: round) }
                else { for p in fars[k] { layer.stroke(p, with: .color(inks[k]), style: flat) } }
            }
            layer.blendMode = .destinationOut
            for k in 0..<3 { for p in nears[k] { layer.stroke(p, with: .color(.black), style: halo) } }
            layer.blendMode = .normal
            for k in 0..<3 { for p in nears[k] { layer.stroke(p, with: .color(inks[k]), style: k < 2 ? round : flat) } }
        }
    }
}
