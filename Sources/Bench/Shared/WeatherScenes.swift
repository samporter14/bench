// WeatherScenes.swift
// ScienceStatus — meteorology. Each draws in a unit square (see
// `UnitSquare`): air, cloud and ground in the tint, fronts, the eye, the
// bolt and the needle in clay.

import SwiftUI

/// Draws a cloud: a flat base with puffs heaped on it.
enum CloudShape {
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, puffs: [(Double, Double, Double)], color: Color) {
        for p in puffs where p.2 > 0.002 { context.fill(u.circle(p.0, p.1, p.2), with: .color(color)) }
    }
}

/// A cold front in cross-section: the wedge of cold air noses in under the
/// warm air and lifts it; cloud builds over the front, rain falls, and the
/// clay triangles of the front's map symbol ride along its edge.
enum ColdFront {
    static let duration = 4.6
    private static let ground = 0.88

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = 0.12 + 0.46 * Ease.inOut((t - 0.3) / 3.4)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let surface = Smooth.curve([(x, ground), (x - 0.06, 0.72), (x - 0.18, 0.58), (x - 0.36, 0.5)], samples: 8)
        var wedge = u.polyline(surface + [(-0.05, 0.47), (-0.05, ground)])
        wedge.closeSubpath()
        scene.fill(wedge, with: .color(tint.opacity(0.14)))
        u.stroke(scene, u.polyline(surface), tint, 0.03)
        for k in 0..<3 {
            let p = Polyline.point(surface, at: 0.08 + 0.3 * Double(k))
            let q = Polyline.point(surface, at: 0.08 + 0.3 * Double(k) + 0.14)
            let dir = atan2(q.1 - p.1, q.0 - p.0)
            let n = dir - .pi / 2
            var tri = u.polyline([(p.0, p.1), (q.0, q.1), ((p.0 + q.0) / 2 + 0.065 * cos(n + .pi), (p.1 + q.1) / 2 + 0.065 * sin(n + .pi))])
            tri.closeSubpath()
            scene.fill(tri, with: .color(clay))
        }
        // Warm air lifted up the front.
        for k in 0..<4 {
            let phase = ((t * 0.6 + Double(k) / 4).truncatingRemainder(dividingBy: 1))
            let p = (x + 0.2 - 0.18 * phase, 0.8 - 0.5 * phase)
            u.stroke(scene, u.line((p.0, p.1), (p.0 - 0.02, p.1 - 0.04)), tint.opacity(0.6 * (1 - phase)), 0.02)
        }
        let grow = Ease.out((t - 0.8) / 1.6)
        CloudShape.draw(scene, u, puffs: [(x - 0.1, 0.3, 0.07 * grow), (x, 0.24, 0.1 * grow), (x + 0.1, 0.28, 0.08 * grow), (x + 0.02, 0.33, 0.08 * grow)], color: tint)
        if grow > 0.6 {
            for k in 0..<7 {
                let fall = ((t * 1.8 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1))
                let rx = x - 0.12 + 0.035 * Double(k)
                let y = 0.4 + (ground - 0.42) * fall
                u.stroke(scene, u.line((rx, y), (rx - 0.01, y + 0.035)), tint.opacity(0.6), 0.015)
            }
        }
        u.stroke(scene, u.line((0.0, ground), (1.0, ground)), tint, 0.04)
    }
}

/// A hurricane from above: its bands spiral in anticlockwise round a clear
/// clay eye as the storm drifts along its track.
enum Hurricane {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let drift = (0.54 - 0.06 * t / duration, 0.54 - 0.06 * t / duration)
        let spin = -t / duration * 2 * .pi * 0.5
        for k in 0..<3 {
            var previous: (Double, Double)?
            for step in 0..<40 {
                let th = Double(step) * 0.09
                let r = 0.08 * exp(0.42 * th)
                guard r < 0.5 else { break }
                let a = -th + spin + Double(k) * 2 * .pi / 3
                let p = (drift.0 + r * cos(a), drift.1 + r * sin(a))
                if let q = previous {
                    u.stroke(context, u.line(q, p), tint.opacity(0.9 - 0.5 * Double(step) / 40), 0.06 * (1 - Double(step) / 50))
                }
                previous = p
            }
        }
        u.stroke(context, u.circle(drift.0, drift.1, 0.07), tint, 0.05)
        context.fill(u.circle(drift.0, drift.1, 0.035), with: .color(clay))
        let track = stride(from: 0.0, through: 1.0, by: 0.1).map { s in (drift.0 + 0.3 + 0.2 * s, drift.1 + 0.3 + 0.12 * s * s) }
        context.stroke(u.polyline(track), with: .color(clay.opacity(0.6)),
                       style: StrokeStyle(lineWidth: u.len(0.02), lineCap: .round, dash: [u.len(0.02), u.len(0.03)]))
    }
}

/// A thunderstorm: a cumulus tower climbs and flattens into an anvil, rain
/// falls from it, and a clay bolt strikes, twice.
enum Thunderstorm {
    static let duration = 4.6

    private static let bolt: [(Double, Double)] = [(0.5, 0.64), (0.46, 0.72), (0.52, 0.74), (0.45, 0.83), (0.5, 0.84), (0.44, 0.92)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let tower = Ease.out((t - 0.2) / 2.0)
        let anvil = Ease.inOut((t - 1.8) / 0.8)
        u.stroke(scene, u.line((0.0, 0.93), (1.0, 0.93)), tint, 0.035)
        if anvil > 0 {
            var top = u.polyline([(0.5 - 0.34 * anvil, 0.2), (0.5 + 0.38 * anvil, 0.2), (0.5 + 0.3 * anvil, 0.26), (0.58, 0.3), (0.42, 0.3), (0.5 - 0.26 * anvil, 0.26)])
            top.closeSubpath()
            scene.fill(top, with: .color(tint))
        }
        let puffs: [(Double, Double, Double, Double)] = [
            (0.38, 0.6, 0.08, 0.0), (0.5, 0.58, 0.1, 0.0), (0.62, 0.6, 0.08, 0.05),
            (0.45, 0.47, 0.09, 0.3), (0.56, 0.45, 0.09, 0.4), (0.5, 0.36, 0.09, 0.6), (0.52, 0.28, 0.07, 0.8),
        ]
        CloudShape.draw(scene, u, puffs: puffs.map { p in (p.0, p.1, p.2 * Ease.outBack((tower - p.3) / 0.25)) }, color: tint)
        if anvil > 0.5 {
            for k in 0..<9 {
                let fall = ((t * 2 + Double(k) * 0.29).truncatingRemainder(dividingBy: 1))
                let x = 0.34 + 0.035 * Double(k)
                let y = 0.68 + 0.24 * fall
                u.stroke(scene, u.line((x, y), (x - 0.012, y + 0.035)), tint.opacity(0.55), 0.015)
            }
        }
        for strike in [2.8, 3.35] {
            let flash = 1 - Ease.clamp((t - strike) / 0.25)
            guard t > strike, flash > 0 else { continue }
            u.stroke(scene, u.polyline(bolt), clay.opacity(flash), 0.035)
        }
    }
}

/// An aneroid barometer: the clay needle falls from fair towards rain as
/// the pressure drops, leaving the set hand behind; then it clears.
enum Barometer {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let c = (0.5, 0.52)
        u.stroke(context, u.circle(c.0, c.1, 0.4), tint, 0.045)
        for k in 0...12 {
            let a = (210 + 10 * Double(k)) * .pi / 180
            let inner = k % 3 == 0 ? 0.28 : 0.31
            u.stroke(context, u.line((c.0 + inner * cos(a), c.1 + inner * sin(a)), (c.0 + 0.34 * cos(a), c.1 + 0.34 * sin(a))), tint.opacity(0.7), 0.018)
        }
        // Fair on the right, rain on the left.
        let sun = (0.72, 0.62)
        context.fill(u.circle(sun.0, sun.1, 0.03), with: .color(tint))
        for k in 0..<6 {
            let a = Double(k) * .pi / 3
            u.stroke(context, u.line((sun.0 + 0.045 * cos(a), sun.1 + 0.045 * sin(a)), (sun.0 + 0.06 * cos(a), sun.1 + 0.06 * sin(a))), tint, 0.015)
        }
        CloudShape.draw(context, u, puffs: [(0.25, 0.63, 0.025), (0.29, 0.61, 0.03), (0.33, 0.63, 0.025)], color: tint)
        let raining = Ease.clamp((t - 2.4) / 0.2) * (1 - Ease.clamp((t - 3.8) / 0.2))
        for k in 0..<3 where raining > 0 {
            let fall = ((t * 2 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1))
            context.fill(u.circle(0.26 + 0.035 * Double(k), 0.67 + 0.06 * fall, 0.008), with: .color(clay.opacity(raining)))
        }
        let setHand = 300.0 * .pi / 180
        u.stroke(context, u.line(c, (c.0 + 0.3 * cos(setHand), c.1 + 0.3 * sin(setHand))), tint.opacity(0.4), 0.018)
        let angle = Keyframes.value(t, [(0.6, 300), (2.6, 228), (3.8, 228), (4.3, 300)]) * .pi / 180
        u.stroke(context, u.line((c.0 - 0.06 * cos(angle), c.1 - 0.06 * sin(angle)), (c.0 + 0.3 * cos(angle), c.1 + 0.3 * sin(angle))), clay, 0.03)
        context.fill(u.circle(c.0, c.1, 0.03), with: .color(tint))
    }
}
