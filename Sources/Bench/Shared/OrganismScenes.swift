// OrganismScenes.swift
// ScienceStatus — lab scenes with model organisms. Each draws in a unit
// square (see `UnitSquare`). Animals are flat silhouettes in the tint with
// one clay detail, and no eyes or faces, per the house style.

import SwiftUI

/// A mouse in profile, facing right: body, a head tapering to a clay nose,
/// a round ear, whiskers and a tail.
enum MouseShape {
    /// Draws the mouse with its body centred on `at`, `scale` its size (1
    /// spans most of the square). `twitch` turns the whiskers (degrees),
    /// `nose` nudges the nose forward, `tail` swings the tail (-1 to 1),
    /// and `stride`, when given, draws running legs at that phase instead
    /// of feet.
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, at: (Double, Double), scale k: Double,
                     tint: Color, twitch: Double = 0, nose: Double = 0, tail: Double = 0, stride: Double? = nil) {
        var m = context
        let origin = u.pt(at.0, at.1)
        m.translateBy(x: origin.x, y: origin.y)
        m.scaleBy(x: k, y: k)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: u.len(x), y: u.len(y)) }
        func width(_ w: Double) -> StrokeStyle { StrokeStyle(lineWidth: u.len(w), lineCap: .round, lineJoin: .round) }

        var tailPath = Path()
        tailPath.move(to: p(-0.2, 0.05))
        tailPath.addQuadCurve(to: p(-0.46, -0.02 + 0.07 * tail), control: p(-0.36, 0.15))
        m.stroke(tailPath, with: .color(tint), style: width(0.035))

        if let phase = stride {
            for (x, sign) in [(0.1, 1.0), (-0.12, -1.0)] {
                var leg = Path()
                leg.move(to: p(x, 0.08))
                leg.addLine(to: p(x + 0.06 * sin(phase) * sign, 0.17))
                m.stroke(leg, with: .color(tint), style: width(0.04))
            }
        } else {
            for x in [-0.1, 0.09] {
                m.fill(Path(ellipseIn: CGRect(origin: p(x - 0.035, 0.12), size: CGSize(width: u.len(0.07), height: u.len(0.035)))),
                       with: .color(tint))
            }
        }

        m.fill(Path(ellipseIn: CGRect(origin: p(-0.23, -0.14), size: CGSize(width: u.len(0.46), height: u.len(0.28)))),
               with: .color(tint))
        var head = Path()
        head.move(to: p(0.12, -0.12))
        head.addQuadCurve(to: p(0.4, 0), control: p(0.32, -0.12))
        head.addQuadCurve(to: p(0.12, 0.1), control: p(0.3, 0.1))
        head.closeSubpath()
        m.fill(head, with: .color(tint))
        m.fill(Path(ellipseIn: CGRect(origin: p(0.105, -0.205), size: CGSize(width: u.len(0.13), height: u.len(0.13)))),
               with: .color(tint))

        var whiskers = m
        whiskers.translateBy(x: u.len(0.37), y: 0)
        whiskers.rotate(by: .degrees(twitch))
        for end in [(0.13, -0.06), (0.15, 0.0), (0.13, 0.06)] {
            var w = Path()
            w.move(to: .zero)
            w.addLine(to: p(end.0, end.1))
            whiskers.stroke(w, with: .color(tint), style: width(0.02))
        }
        m.fill(Path(ellipseIn: CGRect(origin: p(0.378 + nose, -0.028), size: CGSize(width: u.len(0.056), height: u.len(0.056)))),
               with: .color(clay))
    }
}

/// A mouse sniffing: bursts of quick twitches of nose and whiskers, the
/// tail answering with a small counter-movement.
enum MouseSniff {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.72), (0.96, 0.72)), tint.opacity(0.3), 0.04)
        // Three quick sniffs, then a rest, twice.
        var sniff = 0.0
        for burst in [0.3, 1.9] {
            for k in 0..<3 {
                let age = (t - burst - 0.18 * Double(k)) / 0.15
                if age > 0, age < 1 { sniff = max(sniff, sin(.pi * age)) }
            }
        }
        MouseShape.draw(context, u, at: (0.46, 0.55), scale: 0.95, tint: tint,
                        twitch: 8 * sniff, nose: 0.014 * sniff, tail: -0.5 * sniff + 0.15 * sin(t * 1.3))
    }
}

/// A mouse running in a wheel: the wheel turns under it, its legs go and
/// its tail bounces.
enum MouseWheel {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let hub = (0.5, 0.45), radius = 0.34
        // The stand, outside the wheel so nothing crosses the runner.
        u.stroke(context, u.line(Rings.offset(hub, radius, 125), (0.2, 0.95)), tint, 0.05)
        u.stroke(context, u.line(Rings.offset(hub, radius, 55), (0.8, 0.95)), tint, 0.05)
        u.stroke(context, u.line((0.14, 0.95), (0.86, 0.95)), tint, 0.05)

        let turn = t * 2 * .pi / 1.6
        u.stroke(context, u.circle(hub.0, hub.1, radius), tint, 0.05)
        for k in 0..<18 {
            let a = turn + Double(k) * 2 * .pi / 18
            let inner = Rings.offset(hub, radius - 0.045, a * 180 / .pi)
            let outer = Rings.offset(hub, radius, a * 180 / .pi)
            u.stroke(context, u.line(inner, outer), tint.opacity(0.6), 0.03)
        }
        for k in 0..<3 {
            let a = turn + Double(k) * 2 * .pi / 3
            u.stroke(context, u.line(hub, Rings.offset(hub, radius, a * 180 / .pi)), tint.opacity(0.45), 0.035)
        }
        context.fill(u.circle(hub.0, hub.1, 0.035), with: .color(tint))

        let run = t * 2 * .pi / 0.4
        MouseShape.draw(context, u, at: (0.5, 0.64 + 0.008 * sin(run * 2)), scale: 0.52, tint: tint,
                        tail: sin(run * 2), stride: run)
    }
}

/// A Y-maze from above: a clay mouse runs up the stem, stops at the fork,
/// looks both ways, and takes the right arm.
enum YMaze {
    static let duration = 4.0
    private static let fork = (0.5, 0.58)
    private static let rightArm = (0.84, 0.16)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let arms = u.line((0.5, 0.94), fork, (0.16, 0.16))
        let right = u.line(fork, rightArm)
        context.drawLayer { layer in
            u.stroke(layer, arms, tint, 0.22)
            u.stroke(layer, right, tint, 0.22)
            layer.blendMode = .destinationOut
            u.stroke(layer, arms, .black, 0.12)
            u.stroke(layer, right, .black, 0.12)
        }

        let up = Ease.inOut((t - 0.2) / 1.1)
        let choose = Ease.inOut((t - 2.3) / 0.25)
        let go = Ease.inOut((t - 2.5) / 1.0)
        let armAngle = atan2(rightArm.1 - fork.1, rightArm.0 - fork.0) * 180 / .pi
        var heading = -90.0
        if t > 1.3, t < 2.3 { heading += 30 * sin(2 * .pi * (t - 1.3) / 1.0) }
        heading += (armAngle + 90) * choose
        let position: (Double, Double) = t < 2.5
            ? (0.5, 0.86 + (fork.1 - 0.86) * up)
            : (fork.0 + (0.76 - fork.0) * go, fork.1 + (0.25 - fork.1) * go)

        var mouse = context
        let at = u.pt(position.0, position.1)
        mouse.translateBy(x: at.x, y: at.y)
        mouse.rotate(by: .degrees(heading))
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: u.len(x), y: u.len(y)) }
        var tail = Path()
        tail.move(to: p(-0.04, 0))
        tail.addQuadCurve(to: p(-0.13, 0.015 * sin(t * 9)), control: p(-0.09, -0.02))
        mouse.stroke(tail, with: .color(clay), style: StrokeStyle(lineWidth: u.len(0.022), lineCap: .round))
        mouse.fill(Path(ellipseIn: CGRect(origin: p(-0.05, -0.03), size: CGSize(width: u.len(0.1), height: u.len(0.06)))),
                   with: .color(clay))
        mouse.fill(Path(ellipseIn: CGRect(origin: p(0.03, -0.02), size: CGSize(width: u.len(0.05), height: u.len(0.04)))),
                   with: .color(clay))
    }
}

/// The fly climbing assay: a clay fly climbs the side of a vial, the vial
/// is tapped and the fly drops to the bottom, then it starts again.
enum FlyClimb {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tap = 0.03 * sin(.pi * Ease.clamp((t - 1.7) / 0.14))
        var vial = context
        vial.translateBy(x: 0, y: u.len(tap))
        u.stroke(vial, u.capsule(0.5, 0.52, 0.3, 0.8, corner: 0.1), tint)
        vial.fill(u.capsule(0.5, 0.15, 0.3, 0.07, corner: 0.03), with: .color(tint))

        let y: Double, fall: Bool
        if t < 1.7 {
            y = 0.82 - 0.46 * Ease.clamp((t - 0.2) / 1.4) + 0.01 * sin(t * 22)
            fall = false
        } else if t < 1.95 {
            let f = (t - 1.7) / 0.25
            y = 0.36 + (0.84 - 0.36) * f * f
            fall = true
        } else {
            y = 0.84 - 0.34 * Ease.clamp((t - 2.3) / 1.5) + (t > 2.3 ? 0.01 * sin(t * 22) : 0)
            fall = false
        }
        let x = 0.5 + 0.03 * sin(t * 6)
        let flap = fall ? 30 * sin(t * 60) : 0
        for side in [-1.0, 1.0] {
            var wing = context
            let root = u.pt(x, y - 0.01)
            wing.translateBy(x: root.x, y: root.y)
            wing.rotate(by: .degrees(side * (35 + flap)))
            wing.fill(Path(ellipseIn: CGRect(x: -u.len(0.022), y: 0, width: u.len(0.044), height: u.len(0.075))),
                      with: .color(tint.opacity(0.75)))
        }
        context.fill(u.ellipse(x, y, 0.05, 0.08), with: .color(clay))
        context.fill(u.circle(x, y - 0.052, 0.022), with: .color(clay))
    }
}

/// A compound eye: its ommatidia light in clay as a wave crosses it, twice.
enum FlyEye {
    static let duration = 3.6
    private static let cells: [(Double, Double)] = {
        let h = 0.075
        var centres: [(Double, Double)] = []
        for r in -4...4 {
            for q in -5...5 {
                let x = 0.5 + h * sqrt(3) * (Double(q) + Double(r) / 2)
                let y = 0.5 + h * 1.5 * Double(r)
                if hypot(x - 0.5, y - 0.5) < 0.33 { centres.append((x, y)) }
            }
        }
        return centres
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let wave = -0.15 + 1.3 * ((t / 1.8).truncatingRemainder(dividingBy: 1))
        for c in cells {
            var hex = u.polyline(Rings.hexagon(c, 0.066))
            hex.closeSubpath()
            let light = max(0, 1 - abs(c.0 + (c.1 - 0.5) * 0.4 - wave) / 0.16)
            if light > 0 { context.fill(hex, with: .color(clay.opacity(light))) }
            u.stroke(context, hex, tint.opacity(0.6), 0.03)
        }
        u.stroke(context, u.circle(0.5, 0.5, 0.41), tint)
    }
}

/// C. elegans crawling: a tapered worm swims forward on a clean sine wave
/// that runs back along its body, its pharynx a clay bulb near the head.
enum Worm {
    static let duration = 3.6
    private static let length = 0.6, wavelength = 0.42, amplitude = 0.07

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let head = 0.62 + 0.24 * t / duration
        let omega = 2 * .pi / 1.2
        func point(_ s: Double) -> (Double, Double) {
            (head - length * (1 - s), 0.5 + amplitude * sin(2 * .pi * s * length / wavelength + omega * t))
        }
        let steps = 36
        for i in 0..<steps {
            let s0 = Double(i) / Double(steps), s1 = Double(i + 1) / Double(steps)
            let w = 0.03 + 0.05 * pow(sin(.pi * (s0 + s1) / 2), 0.6)
            u.stroke(context, u.line(point(s0), point(s1)), tint, w)
        }
        let bulb = point(0.9)
        context.fill(u.circle(bulb.0, bulb.1, 0.026), with: .color(clay))
    }
}

/// A zebrafish swimming: a slim body with clay stripes along it, a forked
/// tail, and a wave running back through it as it swims.
enum Zebrafish {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let nose = 0.1, peduncle = 0.72
        let bob = 0.015 * sin(2 * .pi * t / duration)
        // The body's midline, waving more towards the tail, and its half-height.
        func mid(_ x: Double) -> Double {
            let back = (x - nose) / (peduncle - nose)
            return 0.5 + bob + 0.028 * back * back * sin(2 * .pi * 1.25 * t - 7 * x)
        }
        func half(_ x: Double) -> Double {
            let s = (x - nose) / (peduncle - nose)
            return 0.025 + 0.11 * pow(sin(.pi * min(1, s * 0.95 + 0.05)), 0.8) * (1 - 0.55 * s)
        }
        let xs = Array(stride(from: nose, through: peduncle, by: 0.02))
        var body = u.polyline(xs.map { ($0, mid($0) - half($0)) } + xs.reversed().map { ($0, mid($0) + half($0)) })
        body.closeSubpath()

        // The forked tail, flicking with the wave.
        let root = (peduncle, mid(peduncle))
        let flick = 0.06 * sin(2 * .pi * 1.25 * t - 7 * peduncle - 0.6)
        var tail = u.polyline([
            (root.0 - 0.02, root.1 - 0.03), (0.92, root.1 - 0.13 + flick), (0.85, root.1 + flick),
            (0.92, root.1 + 0.13 + flick), (root.0 - 0.02, root.1 + 0.03),
        ])
        tail.closeSubpath()
        context.fill(tail, with: .color(tint))
        // Dorsal and anal fins.
        for (x, side) in [(0.48, -1.0), (0.52, 1.0)] {
            var fin = u.polyline([(x - 0.07, mid(x - 0.07) + side * half(x - 0.07) * 0.9),
                                  (x + 0.02, mid(x) + side * (half(x) + 0.07)),
                                  (x + 0.07, mid(x + 0.07) + side * half(x + 0.07) * 0.9)])
            fin.closeSubpath()
            context.fill(fin, with: .color(tint))
        }
        context.fill(body, with: .color(tint))
        // The stripes: clay bands running the length of the body.
        var stripes = context
        stripes.clip(to: body)
        for k in [-0.5, 0.0, 0.5] {
            let line = xs.filter { $0 > nose + 0.08 }.map { ($0, mid($0) + k * half($0) * 0.95) }
            u.stroke(stripes, u.polyline(line), clay, 0.035)
        }
    }
}

/// Planarian regeneration: the flatworm is cut in two, the halves part,
/// and each regrows its missing half in clay, which then settles into the
/// ink colour: two whole worms.
enum Planaria {
    static let duration = 4.0
    private static let x0 = 0.2, length = 0.6

    /// Width along the body, tail (0) to head (1): broad and flat, then the
    /// arrow of the head with its two side lobes.
    private static func width(_ s: Double) -> Double {
        if s > 0.8 {
            let h = (s - 0.8) / 0.2
            return 0.15 * (1 - h) + 0.05 * exp(-pow((s - 0.85) / 0.03, 2))
        }
        return 0.14 * pow(max(0, sin(.pi * min(1, s / 0.8) / 2)), 0.5) + 0.01
    }

    private static func body(_ context: GraphicsContext, _ u: UnitSquare, from s0: Double, to s1: Double,
                             y: Double, color: Color, t: Double) {
        guard s1 > s0 + 0.005 else { return }
        let steps = max(2, Int((s1 - s0) * 40))
        for i in 0..<steps {
            let a = s0 + (s1 - s0) * Double(i) / Double(steps)
            let b = s0 + (s1 - s0) * Double(i + 1) / Double(steps)
            let w = width((a + b) / 2)
            guard w > 0.004 else { continue }
            let pa = (x0 + length * a, y + 0.006 * sin(a * 10 + t * 3))
            let pb = (x0 + length * b, y + 0.006 * sin(b * 10 + t * 3))
            u.stroke(context, u.line(pa, pb), color, w)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let part = Ease.inOut((t - 0.8) / 0.5)
        let grow = Ease.inOut((t - 1.4) / 1.8)
        let settle = Ease.clamp((t - 3.2) / 0.4)
        let headY = 0.5 - 0.17 * part, tailY = 0.5 + 0.17 * part
        let fresh = clay.opacity(1 - settle)

        body(context, u, from: 0.5, to: 1, y: headY, color: tint, t: t)
        body(context, u, from: 0, to: 0.5, y: tailY, color: tint, t: t)
        if grow > 0 {
            for (from, to, y) in [(0.5 - 0.5 * grow, 0.5, headY), (0.5, 0.5 + 0.5 * grow, tailY)] {
                body(context, u, from: from, to: to, y: y, color: tint, t: t)
                body(context, u, from: from, to: to, y: y, color: fresh, t: t)
            }
        }
        let cut = Ease.inOut((t - 0.45) / 0.3) * (1 - Ease.clamp((t - 0.8) / 0.3))
        if cut > 0 {
            let x = x0 + length * 0.5
            u.stroke(context, u.line((x, 0.36), (x, 0.36 + 0.28 * cut)), clay, 0.035)
        }
    }
}

/// A frog embryo cleaving: one cell, two, four, eight, each division a
/// cell parting into two smaller ones, clay nuclei inside, within the
/// faint envelope.
enum FrogEmbryo {
    static let duration = 3.6
    private static let stages: [[(Double, Double, Double)]] = [
        [(0.5, 0.5, 0.3)],
        [(0.36, 0.5, 0.2), (0.64, 0.5, 0.2)],
        [(0.36, 0.36, 0.14), (0.36, 0.64, 0.14), (0.64, 0.36, 0.14), (0.64, 0.64, 0.14)],
        [(0.29, 0.36, 0.066), (0.43, 0.36, 0.066), (0.29, 0.64, 0.066), (0.43, 0.64, 0.066),
         (0.57, 0.36, 0.066), (0.71, 0.36, 0.066), (0.57, 0.64, 0.066), (0.71, 0.64, 0.066)],
    ]
    private static let divisions = [0.5, 1.4, 2.3]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.38), tint.opacity(0.3), 0.035)
        let done = divisions.filter { t >= $0 + 0.45 }.count
        let dividing = done < divisions.count && t >= divisions[done]
        let cells: [(Double, Double, Double)]
        if dividing {
            let k = Ease.inOut((t - divisions[done]) / 0.45)
            cells = stages[done + 1].enumerated().map { i, child in
                let parent = stages[done][i / 2]
                return (parent.0 + (child.0 - parent.0) * k, parent.1 + (child.1 - parent.1) * k,
                        parent.2 + (child.2 - parent.2) * k)
            }
        } else {
            cells = stages[done]
        }
        for c in cells {
            u.stroke(context, u.circle(c.0, c.1, c.2), tint, 0.05)
            context.fill(u.circle(c.0, c.1, c.2 * 0.22), with: .color(clay))
        }
    }
}

/// Fertilisation: sperm swim in towards the egg; the first through sets
/// off a clay ring as the envelope lifts, the others stop at it, and the
/// sperm's nucleus moves in to meet the egg's.
enum Fertilisation {
    static let duration = 4.0
    private static let egg = (0.64, 0.5), radius = 0.26
    private static let swimmers: [(y: Double, angle: Double, arrives: Double)] = [
        (0.18, 205, 2.3), (0.46, 178, 2.0), (0.7, 158, 2.5), (0.9, 140, 2.7),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lifted = Ease.out((t - 2.0) / 0.5)
        u.stroke(context, u.circle(egg.0, egg.1, radius), tint)
        u.stroke(context, u.circle(egg.0, egg.1, radius + 0.04 + 0.03 * lifted), tint.opacity(0.35 + 0.65 * lifted), 0.035)
        let ring = (t - 2.0) / 0.7
        if ring > 0, ring < 1 {
            u.stroke(context, u.circle(egg.0, egg.1, radius + 0.07 + 0.08 * ring), clay.opacity(1 - ring), 0.04)
        }
        let meet = Ease.inOut((t - 2.3) / 1.1)
        context.fill(u.circle(0.68, 0.46, 0.045), with: .color(clay))

        for (k, s) in swimmers.enumerated() {
            let a = s.angle * .pi / 180
            let gate = (egg.0 + (radius + 0.08) * cos(a), egg.1 + (radius + 0.08) * sin(a))
            let start = (-0.05, s.y)
            let winner = k == 1
            let arrive = winner ? s.arrives : min(s.arrives, 2.15 + 0.1 * Double(k))
            let go = Ease.clamp(t / arrive)
            var head = (start.0 + (gate.0 - start.0) * go, start.1 + (gate.1 - start.1) * go)
            if winner, t > s.arrives {
                head = (gate.0 + (0.6 - gate.0) * meet, gate.1 + (0.47 - gate.1) * meet)
            }
            let fade = winner ? 1 : 1 - Ease.clamp((t - 2.6) / 0.6)
            guard fade > 0 else { continue }
            let heading = atan2(gate.1 - start.1, gate.0 - start.0)
            let swimming = winner ? t < s.arrives : t < arrive
            let tail = stride(from: 0.0, through: 0.12, by: 0.01).map { d -> (Double, Double) in
                let wave = swimming ? 0.016 * sin(d * 50 - t * 30) * (d / 0.12) : 0
                return (head.0 - d * cos(heading) - wave * sin(heading), head.1 - d * sin(heading) + wave * cos(heading))
            }
            if !(winner && t > s.arrives + 0.3) {
                u.stroke(context, u.polyline(tail), tint.opacity(fade), 0.02)
            }
            context.fill(u.circle(head.0, head.1, 0.025), with: .color(winner && t > s.arrives ? clay : tint.opacity(fade)))
        }
    }
}
