// MotilityScenes.swift
// ScienceStatus — how microbes and cells get about. Each draws in a unit
// square (see `UnitSquare`): flagella, pili and surfaces in the tint, the
// swimmer in clay.

import SwiftUI

/// A rod-shaped bacterium, clay, at `c` pointing along `heading` (radians).
private func rod(_ context: GraphicsContext, _ u: UnitSquare, _ c: (Double, Double), heading: Double, length: Double = 0.15, width: Double = 0.07) {
    var cell = context
    let p = u.pt(c.0, c.1)
    cell.translateBy(x: p.x, y: p.y)
    cell.rotate(by: .radians(heading))
    cell.fill(Path(roundedRect: CGRect(x: -u.len(length / 2), y: -u.len(width / 2), width: u.len(length), height: u.len(width)),
                   cornerRadius: u.len(width / 2)), with: .color(clay))
}

/// A wavy flagellum from `base` along `angle`, `length` long, its wave
/// running outwards with `phase`.
private func flagellum(_ context: GraphicsContext, _ u: UnitSquare, from base: (Double, Double), angle: Double, length: Double,
                       phase: Double, amplitude: Double = 0.018, color: Color) {
    let n = (-sin(angle), cos(angle))
    let points = stride(from: 0.0, through: 1.0, by: 0.04).map { s -> (Double, Double) in
        let w = amplitude * sin(s * 3 * 2 * .pi - phase) * min(1, s * 4)
        return (base.0 + cos(angle) * length * s + n.0 * w, base.1 + sin(angle) * length * s + n.1 * w)
    }
    u.stroke(context, u.polyline(points), color, 0.014)
}

/// E. coli's run and tumble: its flagella bundle behind it and it runs
/// straight; they fly apart, it tumbles to a new heading, and runs again,
/// its path left faintly behind.
enum RunAndTumble {
    static let duration = 4.8
    private static let speed = 0.26
    private static let legs: [(start: Double, heading: Double, length: Double)] = [(0.2, -25, 1.2), (1.9, -120, 1.2), (3.6, 30, 1.0)]

    private static func where_(_ t: Double) -> (p: (Double, Double), heading: Double, tumbling: Bool) {
        var p = (0.25, 0.72)
        var heading = legs[0].heading * .pi / 180
        for (k, leg) in legs.enumerated() {
            let h = leg.heading * .pi / 180
            if t < leg.start {
                if k > 0 {
                    let previous = legs[k - 1].heading * .pi / 180
                    let s = Ease.inOut((t - (leg.start - 0.5)) / 0.5)
                    return (p, previous + (h - previous) * s + 0.4 * sin(t * 25) * sin(.pi * s), true)
                }
                return (p, h, false)
            }
            let run = min(t - leg.start, leg.length)
            let q = (p.0 + cos(h) * speed * run, p.1 + sin(h) * speed * run)
            heading = h
            if t < leg.start + leg.length { return (q, h, false) }
            p = (p.0 + cos(h) * speed * leg.length, p.1 + sin(h) * speed * leg.length)
        }
        return (p, heading, false)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let trail = stride(from: 0.0, through: t, by: 0.05).map { where_($0).p }
        if trail.count > 1 {
            context.stroke(u.polyline(trail), with: .color(tint.opacity(0.35)),
                           style: StrokeStyle(lineWidth: u.len(0.012), lineCap: .round, dash: [u.len(0.015), u.len(0.02)]))
        }
        let now = where_(t)
        let back = (now.p.0 - cos(now.heading) * 0.1, now.p.1 - sin(now.heading) * 0.1)
        if now.tumbling {
            for k in 0..<4 {
                let a = now.heading + .pi + (Double(k) - 1.5) * 0.9
                flagellum(context, u, from: back, angle: a, length: 0.2, phase: t * 30 + Double(k), amplitude: 0.025, color: tint)
            }
        } else {
            for k in 0..<3 {
                let a = now.heading + .pi + (Double(k) - 1) * 0.1
                flagellum(context, u, from: back, angle: a, length: 0.26, phase: t * 30, amplitude: 0.03, color: tint)
            }
        }
        rod(context, u, now.p, heading: now.heading, length: 0.21, width: 0.1)
    }
}

/// A single polar flagellum: the curved cell swims forward, backs up, then
/// its flagellum flicks it round a quarter turn and it sets off anew.
enum PolarFlagellum {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = Keyframes.value(t, [(0.2, 0.2), (1.6, 0.62), (1.8, 0.62), (2.6, 0.48), (2.9, 0.48), (4.3, 0.48)])
        let y = Keyframes.value(t, [(2.9, 0.62), (4.3, 0.24)])
        let heading = Keyframes.value(t, [(2.6, 0), (2.9, -.pi / 2)])
        let backing = t > 1.8 && t < 2.6
        let trail = stride(from: 0.0, through: t, by: 0.05).map { s in
            (Keyframes.value(s, [(0.2, 0.2), (1.6, 0.62), (1.8, 0.62), (2.6, 0.48), (2.9, 0.48), (4.3, 0.48)]), Keyframes.value(s, [(2.9, 0.62), (4.3, 0.24)]))
        }
        if trail.count > 1 {
            context.stroke(u.polyline(trail), with: .color(tint.opacity(0.35)),
                           style: StrokeStyle(lineWidth: u.len(0.012), lineCap: .round, dash: [u.len(0.015), u.len(0.02)]))
        }
        let back = (x - cos(heading) * 0.11, y - sin(heading) * 0.11)
        let flick = sin(.pi * Ease.clamp((t - 2.6) / 0.3))
        flagellum(context, u, from: back, angle: heading + .pi + 0.9 * flick, length: 0.28, phase: (backing ? -1 : 1) * t * 28, amplitude: 0.032, color: tint)
        var cell = context
        let p = u.pt(x, y)
        cell.translateBy(x: p.x, y: p.y)
        cell.rotate(by: .radians(heading))
        var comma = Path()
        comma.move(to: CGPoint(x: -u.len(0.1), y: u.len(0.015)))
        comma.addQuadCurve(to: CGPoint(x: u.len(0.1), y: u.len(0.015)), control: CGPoint(x: 0, y: -u.len(0.07)))
        cell.stroke(comma, with: .color(clay), style: StrokeStyle(lineWidth: u.len(0.09), lineCap: .round))
    }
}

/// A spirochete: its whole body a corkscrew, the wave running back along
/// it as it bores forward past the drifting particles.
enum Spirochete {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<10 {
            let s = Double(k)
            let x = (0.05 + BenchShapes.rand(s) * 0.9 - 0.05 * t + 1).truncatingRemainder(dividingBy: 1)
            context.fill(u.circle(x, 0.1 + 0.8 * BenchShapes.rand(s + 3), 0.01), with: .color(tint.opacity(0.4)))
        }
        let head = 0.2 + 0.14 * t
        let body = stride(from: 0.0, through: 1.0, by: 0.01).map { s -> (Double, Double) in
            let x = head - 0.62 * s
            let taper = min(1, min(s, 1 - s) * 8)
            return (x, 0.5 + 0.045 * taper * sin((x - head) / 0.12 * 2 * .pi + t * 14) + 0.06 * sin(t * 0.8))
        }
        u.stroke(context, u.polyline(body), clay, 0.035)
    }
}

/// Twitching motility: the rod reaches type IV pili out along the surface,
/// they catch hold and pull in, and it lurches forward, again and again.
enum Twitching {
    static let duration = 4.6
    private static let pulls = [0.4, 1.7, 3.0]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.64), (0.98, 0.64)), tint, 0.035)
        for k in 0..<12 { u.stroke(context, u.line((0.04 + 0.08 * Double(k), 0.66), (0.02 + 0.08 * Double(k), 0.7)), tint.opacity(0.35), 0.012) }
        var x = 0.16
        for p in pulls { x += 0.18 * Ease.inOut((t - p - 0.7) / 0.35) }
        let fade = Ease.inOut((t - 4.3) / 0.3)
        var scene = context
        scene.opacity = 1 - fade
        for (k, p) in pulls.enumerated() {
            let reach = Ease.out((t - p) / 0.5) * (1 - Ease.inOut((t - p - 0.7) / 0.35))
            guard reach > 0 else { continue }
            let base = (x + 0.1, 0.56)
            let tip = (base.0 + 0.24 * reach, 0.62 - 0.02 * Double(k % 2))
            u.stroke(scene, u.line(base, tip), tint, 0.016)
            if t > p + 0.5 { scene.fill(u.circle(tip.0, tip.1, 0.016), with: .color(tint)) }
        }
        rod(scene, u, (x, 0.56), heading: 0, length: 0.23, width: 0.11)
    }
}

/// An amoeba on the move: a pseudopod bulges out, the clay granules stream
/// into it, the body follows, and the next one reaches a little off to the
/// side.
enum Amoeboid {
    static let duration = 4.8
    private static let headings: [Double] = [-0.3, 0.4, -0.2]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let step = min(2, Int(t / 1.5))
        let local = t - 1.5 * Double(step)
        var centre = (0.34, 0.55)
        for k in 0..<step { centre = (centre.0 + 0.1 * cos(headings[k]), centre.1 + 0.1 * sin(headings[k])) }
        let heading = headings[step]
        let bulge = Ease.inOut(local / 0.8)
        let follow = Ease.inOut((local - 0.7) / 0.7)
        let c = (centre.0 + 0.1 * cos(heading) * follow, centre.1 + 0.1 * sin(heading) * follow)
        let outline = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.1).map { a -> (Double, Double) in
            let d = atan2(sin(a - heading), cos(a - heading))
            let lobe: Double = 0.12 * bulge * (1 - follow) * exp(-d * d / 0.25)
            let side: Double = 0.03 * exp(-pow(atan2(sin(a - heading - 2), cos(a - heading - 2)), 2) / 0.2)
            let r: Double = 0.19 + 1.2 * lobe + side + 0.01 * sin(5 * a + t * 3)
            return (c.0 + r * cos(a), c.1 + r * sin(a))
        }
        var cell = u.polyline(outline)
        cell.closeSubpath()
        scene.fill(cell, with: .color(tint.opacity(0.1)))
        u.stroke(scene, cell, tint, 0.03)
        scene.fill(u.circle(c.0 - 0.04 * cos(heading), c.1 - 0.04 * sin(heading), 0.045), with: .color(tint.opacity(0.6)))
        for k in 0..<8 {
            let s = Double(k)
            let flow = ((t * 0.6 + BenchShapes.rand(s)).truncatingRemainder(dividingBy: 1))
            let lateral = (BenchShapes.rand(s + 4) - 0.5) * 0.12
            let along = -0.08 + 0.2 * flow * bulge
            let p = (c.0 + along * cos(heading) - lateral * sin(heading), c.1 + along * sin(heading) + lateral * cos(heading))
            scene.fill(u.circle(p.0, p.1, 0.014), with: .color(clay))
        }
    }
}

/// Chlamydomonas swimming breaststroke: its two flagella sweep back
/// together, straight, in the power stroke, then come forward bent in the
/// recovery, and the cell surges ahead with each stroke.
enum Chlamydomonas {
    static let duration = 4.4
    private static let beat = 0.55

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let strokes = t / beat
        let phase = strokes.truncatingRemainder(dividingBy: 1)
        let progress = floor(strokes) + Ease.inOut(min(1, phase / 0.45))
        let c = (0.5, 0.8 - 0.06 * progress)
        let y = c.1 > 0.2 ? c.1 : c.1 + 0.6
        u.stroke(context, u.ellipse(c.0, y, 0.22, 0.28), tint, 0.04)
        var cup = Path()
        cup.addArc(center: u.pt(c.0, y + 0.015), radius: u.len(0.09), startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
        u.stroke(context, cup, clay, 0.055)
        let apex = (c.0, y - 0.14)
        for side in [-1.0, 1.0] {
            let power = phase < 0.45
            let s = power ? Ease.inOut(phase / 0.45) : 1 - Ease.inOut((phase - 0.45) / 0.55)
            let base = (-100 + 170 * s) * .pi / 180
            let bend = power ? 0.0 : 1.4 * sin(.pi * (phase - 0.45) / 0.55)
            var p = apex
            var points = [p]
            for i in 1...10 {
                let a = side < 0 ? .pi - base + bend * Double(i) / 10 : base - bend * Double(i) / 10
                p = (p.0 + 0.032 * cos(a), p.1 + 0.032 * sin(a))
                points.append(p)
            }
            u.stroke(context, u.polyline(points), tint, 0.03)
        }
    }
}
