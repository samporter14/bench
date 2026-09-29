// MathPhysicsScenes.swift
// ScienceStatus — lab scenes from maths and physics. Each draws in a unit
// square (see `UnitSquare`): figures in the tint, the thing that moves or
// the answer in clay.

import SwiftUI

/// The unit circle unwinding into a sine wave: a point goes round, and its
/// height traces the wave out to the right.
enum SineWave {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = (0.23, 0.5), radius = 0.16
        let x0 = 0.46, x1 = 0.96
        u.stroke(context, u.circle(centre.0, centre.1, radius), tint, 0.06)
        u.stroke(context, u.line((x0, 0.5), (x1, 0.5)), tint.opacity(0.35), 0.035)

        let turn = t * 2 * .pi / 1.8
        let point = (centre.0 + radius * cos(turn), centre.1 - radius * sin(turn))
        u.stroke(context, u.line(centre, point), tint, 0.05)

        // One period in 0.45 of the width; the wave grows out, then scrolls.
        let k = 0.45 / (2 * .pi)
        let reach = min(x1 - x0, turn * k)
        if reach > 0.01 {
            let wave = stride(from: 0.0, through: reach, by: 0.01).map { s in
                (x0 + s, centre.1 - radius * sin(turn - s / k))
            }
            u.stroke(context, u.polyline(wave), clay, 0.06)
        }
        u.stroke(context, u.line(point, (x0, point.1)), tint.opacity(0.5), 0.035)
        context.fill(u.circle(point.0, point.1, 0.042), with: .color(clay))
        context.fill(u.circle(x0, point.1, 0.035), with: .color(clay))
    }
}

/// E = mc² writing itself, stroke by stroke, the square in clay.
enum Equation {
    static let duration = 4.0

    private static func strokes(_ u: UnitSquare) -> [(path: Path, start: Double, length: Double, accent: Bool)] {
        var m = Path()
        m.move(to: u.pt(0.44, 0.5))
        m.addLine(to: u.pt(0.44, 0.62))
        m.move(to: u.pt(0.44, 0.56))
        m.addArc(center: u.pt(0.4775, 0.56), radius: u.len(0.0375),
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        m.addLine(to: u.pt(0.515, 0.62))
        m.move(to: u.pt(0.515, 0.56))
        m.addArc(center: u.pt(0.5525, 0.56), radius: u.len(0.0375),
                 startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        m.addLine(to: u.pt(0.59, 0.62))

        var c = Path()
        c.addArc(center: u.pt(0.7, 0.56), radius: u.len(0.058),
                 startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: true)

        var two = Path()
        two.move(to: u.pt(0.8, 0.37))
        two.addQuadCurve(to: u.pt(0.87, 0.375), control: u.pt(0.835, 0.31))
        two.addQuadCurve(to: u.pt(0.8, 0.455), control: u.pt(0.885, 0.415))
        two.addLine(to: u.pt(0.89, 0.455))

        return [
            (u.line((0.2, 0.38), (0.08, 0.38), (0.08, 0.62), (0.2, 0.62)), 0.2, 0.45, false),
            (u.line((0.08, 0.5), (0.18, 0.5)), 0.66, 0.14, false),
            (u.line((0.27, 0.46), (0.37, 0.46)), 0.9, 0.12, false),
            (u.line((0.27, 0.54), (0.37, 0.54)), 1.04, 0.12, false),
            (m, 1.25, 0.5, false),
            (c, 1.82, 0.32, false),
            (two, 2.25, 0.4, true),
            (u.line((0.08, 0.74), (0.9, 0.74)), 2.8, 0.4, true),
        ]
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for stroke in strokes(u) {
            let k = Ease.inOut((t - stroke.start) / stroke.length)
            guard k > 0 else { continue }
            u.stroke(context, stroke.path.trimmedPath(from: 0, to: k), stroke.accent ? clay : tint, 0.05)
        }
    }
}

/// Pythagoras, shown with areas: a right triangle, the squares on its
/// legs filling with clay, and their clay pouring into the square on the
/// hypotenuse, which fills exactly.
enum Pythagoras {
    static let duration = 4.0
    private static let a = (0.34, 0.6), b = (0.6, 0.6), c = (0.34, 0.4)
    private static let onBase = [a, b, (0.6, 0.86), (0.34, 0.86)]
    private static let onHeight = [c, a, (0.14, 0.6), (0.14, 0.4)]
    /// Built outwards from the hypotenuse, away from the right angle.
    private static let onHypotenuse = [b, c, (0.54, 0.14), (0.8, 0.34)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        func closed(_ points: [(Double, Double)]) -> Path {
            var path = u.polyline(points)
            path.closeSubpath()
            return path
        }
        func shrunk(_ points: [(Double, Double)], _ k: Double) -> [(Double, Double)] {
            let cx = points.map(\.0).reduce(0, +) / Double(points.count)
            let cy = points.map(\.1).reduce(0, +) / Double(points.count)
            return points.map { (cx + ($0.0 - cx) * k, cy + ($0.1 - cy) * k) }
        }

        // Fills first, so the outlines sit on top.
        let pour = Ease.inOut((t - 2.4) / 0.8)
        let legs = [(onBase, 1.6), (onHeight, 1.8)]
        for (square, at) in legs {
            let k = Ease.outBack((t - at) / 0.3) * (1 - pour)
            if k > 0.01 { context.fill(closed(shrunk(square, k)), with: .color(clay)) }
        }
        if pour > 0.01 { context.fill(closed(shrunk(onHypotenuse, pour)), with: .color(clay)) }

        u.stroke(context, closed([a, b, c]).trimmedPath(from: 0, to: Ease.inOut((t - 0.1) / 0.5)), tint)
        let outline = Ease.inOut((t - 0.6) / 0.5)
        if outline > 0 {
            u.stroke(context, closed(onBase).trimmedPath(from: 0, to: outline), tint.opacity(0.8), 0.05)
            u.stroke(context, closed(onHeight).trimmedPath(from: 0, to: outline), tint.opacity(0.8), 0.05)
        }
        let hypotenuse = Ease.inOut((t - 1.1) / 0.5)
        if hypotenuse > 0 {
            u.stroke(context, closed(onHypotenuse).trimmedPath(from: 0, to: hypotenuse), tint.opacity(0.8), 0.05)
        }
    }
}

/// Spacetime: a grid warped into a well round a mass, and a clay ball
/// orbiting down it, passing behind the mass and in front, a short trail
/// behind it.
enum Spacetime {
    static let duration = 4.0

    /// The well's cross-section at `rho` (1 at the rim, 0 at the bottom).
    private static func ring(_ rho: Double) -> (rx: Double, ry: Double, cy: Double) {
        (0.46 * rho, 0.15 * rho, 0.3 + 0.44 * pow(1 - rho, 1.8))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for rho in [1.0, 0.78, 0.56, 0.36, 0.2] {
            let r = ring(rho)
            u.stroke(context, u.ellipse(0.5, r.cy, 2 * r.rx, 2 * r.ry), tint.opacity(0.55), 0.045)
        }
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4
            let spoke = stride(from: 1.0, through: 0.1, by: -0.05).map { rho -> (Double, Double) in
                let r = ring(rho)
                return (0.5 + r.rx * cos(angle), r.cy + r.ry * sin(angle))
            }
            u.stroke(context, u.polyline(spoke), tint.opacity(0.3), 0.035)
        }

        let rho = 0.86 - 0.36 * Ease.inOut(t / duration)
        let phase = t * 2 * .pi / 1.4
        func position(_ phi: Double, _ rho: Double) -> (Double, Double) {
            let r = ring(rho)
            return (0.5 + r.rx * cos(phi), r.cy + r.ry * sin(phi))
        }
        let canvas = context
        let mass = { canvas.fill(u.circle(0.5, ring(0.1).cy - 0.035, 0.065), with: .color(tint)) }
        let ball = {
            for j in (1...5).reversed() {
                let p = position(phase - Double(j) * 0.2, rho + 0.012 * Double(j))
                canvas.fill(u.circle(p.0, p.1, 0.028), with: .color(clay.opacity(0.5 * (1 - Double(j) / 6))))
            }
            let p = position(phase, rho)
            canvas.fill(u.circle(p.0, p.1, 0.048), with: .color(clay))
        }
        // The far side of the orbit is the top half; draw it behind the mass.
        if sin(phase) < 0 { ball(); mass() } else { mass(); ball() }
    }
}

/// A pulsar: a star turning, two clay beams sweeping round like a
/// lighthouse, and a faint pulse going out each half turn.
enum Pulsar {
    static let duration = 3.2
    private static let period = 1.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<4 {
            let age = (t - period / 2 * Double(k) - 0.2) / 1.2
            guard age > 0, age < 1 else { continue }
            u.stroke(context, u.circle(0.5, 0.5, 0.1 + 0.34 * Ease.out(age)), tint.opacity(0.5 * (1 - age)), 0.04)
        }
        let spin = t * 2 * .pi / period
        for side in [0.0, Double.pi] {
            let a = spin + side
            var beam = Path()
            beam.move(to: u.pt(0.5, 0.5))
            beam.addLine(to: u.pt(0.5 + 0.44 * cos(a - 0.13), 0.5 + 0.44 * sin(a - 0.13)))
            beam.addLine(to: u.pt(0.5 + 0.44 * cos(a + 0.13), 0.5 + 0.44 * sin(a + 0.13)))
            beam.closeSubpath()
            context.fill(beam, with: .color(clay))
        }
        context.fill(u.circle(0.5, 0.5, 0.08), with: .color(tint))
        // An observer off in the corner sees a pulse each time a beam sweeps by.
        let observer = (0.88, 0.13)
        let facing = atan2(observer.1 - 0.5, observer.0 - 0.5)
        var seen = 0.0
        for side in [0.0, Double.pi] { seen = max(seen, (cos(spin + side - facing) - 0.9) / 0.1) }
        context.fill(u.circle(observer.0, observer.1, 0.035), with: .color(tint))
        if seen > 0 { u.stroke(context, u.circle(observer.0, observer.1, 0.055 + 0.03 * seen), clay.opacity(seen), 0.035) }
    }
}

/// A wind tunnel: an aerofoil rocking gently in the flow, streamlines
/// bending round it, and clay smoke running along them, faster over the
/// top than underneath.
enum WindTunnel {
    static let duration = 3.6
    private static let lines: [(y: Double, bend: Double, speed: Double)] = [
        (0.16, -0.05, 0.5), (0.31, -0.1, 0.62), (0.7, 0.05, 0.36), (0.85, 0.03, 0.32),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for line in lines {
            func y(_ x: Double) -> Double { line.y + line.bend * exp(-pow((x - 0.52) / 0.2, 2)) }
            let flow = stride(from: 0.02, through: 0.98, by: 0.02).map { ($0, y($0)) }
            u.stroke(context, u.polyline(flow), tint.opacity(0.25), 0.035)
            let offset = (t * line.speed).truncatingRemainder(dividingBy: 0.32)
            for k in 0..<4 {
                let start = 0.02 + offset + 0.32 * Double(k) - 0.32
                guard start > 0.02, start < 0.88 else { continue }
                let dash = stride(from: start, through: start + 0.08, by: 0.02).map { ($0, y($0)) }
                u.stroke(context, u.polyline(dash), clay, 0.06)
            }
        }

        var wing = context
        let pivot = u.pt(0.5, 0.5)
        wing.translateBy(x: pivot.x, y: pivot.y)
        wing.rotate(by: .degrees(4 * sin(t * 1.3)))
        wing.translateBy(x: -pivot.x, y: -pivot.y)
        var foil = Path()
        foil.move(to: u.pt(0.18, 0.5))
        foil.addCurve(to: u.pt(0.84, 0.53), control1: u.pt(0.2, 0.37), control2: u.pt(0.58, 0.39))
        foil.addCurve(to: u.pt(0.18, 0.5), control1: u.pt(0.58, 0.58), control2: u.pt(0.2, 0.6))
        foil.closeSubpath()
        wing.fill(foil, with: .color(tint))
    }
}

/// A double pendulum: two arms swinging chaotically, the clay bob drawing
/// a fading trail. The motion is integrated once, then played back.
enum DoublePendulum {
    static let duration = 4.0
    private static let rate = 120.0
    /// Both angles at `rate` samples a second over the scene.
    private static let angles: [(Double, Double)] = {
        var a1 = 2.2, a2 = 2.6, w1 = 0.0, w2 = 0.0
        let g = 9.0, dt = 1.0 / 960
        var out: [(Double, Double)] = []
        for step in 0...Int(duration * 960) + 16 {
            if step % 8 == 0 { out.append((a1, a2)) }
            let d = a1 - a2
            let den = 3 - cos(2 * d)
            let acc1 = (-3 * g * sin(a1) - g * sin(a1 - 2 * a2) - 2 * sin(d) * (w2 * w2 + w1 * w1 * cos(d))) / den
            let acc2 = 2 * sin(d) * (2 * w1 * w1 + 2 * g * cos(a1) + w2 * w2 * cos(d)) / den
            w1 += acc1 * dt
            w2 += acc2 * dt
            a1 += w1 * dt
            a2 += w2 * dt
        }
        return out
    }()

    private static func bobs(at t: Double) -> ((Double, Double), (Double, Double)) {
        let f = max(0, min(Double(angles.count - 2), t * rate))
        let i = Int(f), k = f - Double(i)
        let a1 = angles[i].0 + (angles[i + 1].0 - angles[i].0) * k
        let a2 = angles[i].1 + (angles[i + 1].1 - angles[i].1) * k
        let first = (0.5 + 0.22 * sin(a1), 0.46 + 0.22 * cos(a1))
        return (first, (first.0 + 0.22 * sin(a2), first.1 + 0.22 * cos(a2)))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var previous = bobs(at: max(0, t - 0.9)).1
        for j in stride(from: 0.87, through: 0.0, by: -0.03) {
            let p = bobs(at: max(0, t - j)).1
            u.stroke(context, u.line(previous, p), clay.opacity(0.7 * (1 - j / 0.9)), 0.03)
            previous = p
        }
        let (first, second) = bobs(at: t)
        u.stroke(context, u.line((0.5, 0.46), first, second), tint, 0.05)
        context.fill(u.circle(0.5, 0.46, 0.025), with: .color(tint))
        context.fill(u.circle(first.0, first.1, 0.04), with: .color(tint))
        context.fill(u.circle(second.0, second.1, 0.045), with: .color(clay))
    }
}

/// A Lissajous figure: a clay point traces a 3:2 curve whose phase slowly
/// turns, the whole figure faint behind it.
enum Lissajous {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let phase = Double.pi / 2 + 0.5 * t
        func point(_ s: Double) -> (Double, Double) { (0.5 + 0.36 * sin(3 * s + phase), 0.5 + 0.36 * sin(2 * s)) }
        let figure = stride(from: 0.0, through: 2 * .pi + 0.05, by: 0.05).map(point)
        u.stroke(context, u.polyline(figure), tint.opacity(0.3), 0.035)
        let head = t * 2 * .pi / 1.8
        var previous = point(head - 1.6)
        for s in stride(from: head - 1.56, through: head, by: 0.04) {
            let p = point(s)
            u.stroke(context, u.line(previous, p), clay.opacity(Ease.clamp(1 - (head - s) / 1.6)), 0.05)
            previous = p
        }
        let p = point(head)
        context.fill(u.circle(p.0, p.1, 0.035), with: .color(clay))
    }
}

/// The double slit: plane waves reach a barrier, spread in rings from its
/// two slits, and clay fringes build up on the screen where they agree.
enum DoubleSlit {
    static let duration = 3.6
    private static let wall = 0.36, screen = 0.9, lambda = 0.08
    private static let slits = [0.4, 0.6]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let travel = (t * 0.16).truncatingRemainder(dividingBy: lambda)
        var x = 0.04 + travel
        while x < wall - 0.01 {
            u.stroke(context, u.line((x, 0.14), (x, 0.86)), tint.opacity(0.45), 0.035)
            x += lambda
        }
        u.stroke(context, u.line((wall, 0.04), (wall, 0.37)), tint, 0.05)
        u.stroke(context, u.line((wall, 0.43), (wall, 0.57)), tint, 0.05)
        u.stroke(context, u.line((wall, 0.63), (wall, 0.96)), tint, 0.05)
        for y0 in slits {
            var r = travel + 0.02
            while r < screen - wall {
                var arc = Path()
                arc.addArc(center: u.pt(wall, y0), radius: u.len(r), startAngle: .degrees(-70),
                           endAngle: .degrees(70), clockwise: false)
                u.stroke(context, arc, tint.opacity(0.45 * (1 - r / (screen - wall))), 0.03)
                r += lambda
            }
        }
        u.stroke(context, u.line((screen, 0.04), (screen, 0.96)), tint, 0.04)
        let build = Ease.clamp((t - 0.6) / 1.2)
        for y in stride(from: 0.06, through: 0.94, by: 0.02) {
            let d1 = hypot(screen - wall, y - slits[0]), d2 = hypot(screen - wall, y - slits[1])
            let bright = pow(cos(.pi * (d1 - d2) / lambda), 2) * build
            guard bright > 0.08 else { continue }
            u.stroke(context, u.line((screen + 0.045, y - 0.008), (screen + 0.045, y + 0.008)), clay.opacity(bright), 0.05)
        }
    }
}

/// A spiral galaxy turning: two arms of stars round a clay core, the inner
/// stars running ahead of the outer ones.
enum Galaxy {
    static let duration = 4.0
    private static let stars: [(r: Double, a: Double, size: Double)] = {
        var list: [(Double, Double, Double)] = []
        for arm in 0..<2 {
            for i in 0..<22 {
                let r = 0.07 + 0.34 * Double(i) / 21
                let wobble = 0.18 * sin(Double(i * 7 + arm * 3))
                list.append((r, Double(arm) * .pi + log(r / 0.07) * 2.1 + wobble, 0.012 + 0.012 * abs(sin(Double(i * 5 + arm)))))
            }
        }
        for i in 0..<12 {
            list.append((0.1 + 0.3 * abs(sin(Double(i) * 1.7)), Double(i) * 2.4, 0.01))
        }
        return list
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for s in stars {
            let a = s.a + t * 0.9 * sqrt(0.07 / s.r)
            let p = (0.5 + s.r * cos(a), 0.5 + s.r * sin(a) * 0.62)
            context.fill(u.circle(p.0, p.1, s.size), with: .color(tint.opacity(1 - 0.5 * s.r / 0.41)))
        }
        u.stroke(context, u.ellipse(0.5, 0.5, 0.2, 0.13), tint.opacity(0.35), 0.03)
        context.fill(u.ellipse(0.5, 0.5, 0.13, 0.09), with: .color(clay))
    }
}

/// Orbital dynamics: a planet on an eccentric orbit whips round close to
/// its clay star and dawdles far out; the fading trail behind it is long
/// where it's fast and short where it's slow (Kepler's second law).
enum Orbit {
    static let duration = 4.0
    private static let a = 0.4, e = 0.6

    private static func position(_ t: Double) -> (Double, Double) {
        let mean = 2 * .pi * t / duration
        var anomaly = mean
        for _ in 0..<8 { anomaly -= (anomaly - e * sin(anomaly) - mean) / (1 - e * cos(anomaly)) }
        let b = a * sqrt(1 - e * e)
        return (0.55 - a * cos(anomaly), 0.5 - b * sin(anomaly))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let b = a * sqrt(1 - e * e)
        u.stroke(context, u.ellipse(0.55, 0.5, 2 * a, 2 * b), tint.opacity(0.3), 0.035)
        context.fill(u.circle(0.31, 0.5, 0.07), with: .color(clay))
        // The trail: where it was over the last half second, fading.
        let steps = 14
        for k in 0..<steps {
            let s0 = t - 0.5 * Double(steps - k) / Double(steps)
            let s1 = t - 0.5 * Double(steps - k - 1) / Double(steps)
            let p0 = position(s0), p1 = position(s1)
            u.stroke(context, u.line(p0, p1), tint.opacity(0.7 * Double(k + 1) / Double(steps)), 0.045)
        }
        let p = position(t)
        context.fill(u.circle(p.0, p.1, 0.042), with: .color(tint))
    }
}
