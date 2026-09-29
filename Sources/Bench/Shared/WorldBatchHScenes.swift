// WorldBatchHScenes.swift
// ScienceStatus — chemistry, physics, the planet and the plots: the nylon
// rope trick, chemiluminescence, a laser, the Doppler effect, Brownian
// motion, the aurora, a mimosa, the water cycle, Fourier epicycles, a
// volcano plot and a Manhattan plot. Each draws in a unit square (see
// `UnitSquare`): apparatus and axes in the tint, the product, the light or
// the signal in clay.

import SwiftUI

/// The nylon rope trick: a clay thread of nylon is drawn from the boundary
/// between two liquids and wound onto a turning rod.
enum NylonRope {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let boundary = 0.66
        context.fill(Path(CGRect(x: u.pt(0.27, 0).x, y: u.pt(0, boundary).y, width: u.len(0.46), height: u.len(0.21))), with: .color(tint.opacity(0.16)))
        context.fill(Path(CGRect(x: u.pt(0.27, 0).x, y: u.pt(0, 0.5).y, width: u.len(0.46), height: u.len(boundary - 0.5))), with: .color(tint.opacity(0.07)))
        u.stroke(context, u.line((0.27, boundary), (0.73, boundary)), clay.opacity(0.7), 0.018)
        u.stroke(context, u.line((0.26, 0.4), (0.26, 0.88), (0.74, 0.88), (0.74, 0.4)), tint, 0.035)
        // The rod, turning, with rope wound on it.
        let wound = Ease.out((t - 0.8) / 3.8)
        context.fill(u.capsule(0.5, 0.16, 0.56, 0.04, corner: 0.02), with: .color(tint))
        let turns = Int(10 * wound)
        for k in 0..<turns {
            let x = 0.42 + 0.016 * Double(k)
            u.stroke(context, u.line((x, 0.13), (x + 0.012, 0.19)), clay, 0.022)
        }
        let spin = t * 5
        for side in [0.24, 0.76] {
            u.stroke(context, u.line((side, 0.16 - 0.03 * cos(spin)), (side, 0.16 + 0.03 * cos(spin))), tint, 0.02)
        }
        // The thread, from the boundary up through the top liquid to the rod.
        let lift = Ease.out((t - 0.2) / 0.6)
        let sway = 0.012 * sin(t * 3)
        let top = boundary - (boundary - 0.19) * lift
        u.stroke(context, u.polyline(Smooth.curve([(0.5, boundary), (0.5 + sway, (boundary + top) / 2), (0.5 + 0.02 * wound, top)], samples: 6)), clay, 0.028)
    }
}

/// Chemiluminescence: the oxidiser pours into the dark luminol solution and a
/// clay glow swirls through it, blooms, and slowly dims.
enum Chemiluminescence {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let glow = Ease.inOut((t - 1.0) / 0.9) * (1 - 0.6 * Ease.inOut((t - 2.8) / 1.6))
        // Rings of glow round the flask, no blur: just fainter clay further out.
        for k in 0..<3 where glow > 0 {
            u.stroke(context, u.circle(0.5, 0.66, 0.36 + 0.06 * Double(k)), clay.opacity(0.1 * glow / Double(k + 1)), 0.05)
        }
        var inside = context
        var liquid = u.polyline([(0.33, 0.58), (0.2, 0.84), (0.8, 0.84), (0.67, 0.58)])
        liquid.closeSubpath()
        inside.clip(to: liquid)
        inside.fill(liquid, with: .color(tint.opacity(0.1)))
        inside.fill(liquid, with: .color(clay.opacity(0.85 * glow)))
        // The swirl that spreads the glow.
        let swirl = Ease.clamp((t - 0.8) / 1.4)
        if swirl > 0, swirl < 1 {
            let spiral = stride(from: 0.0, through: 3 * .pi * swirl, by: 0.15).map { a in
                (0.5 + 0.014 * a * cos(a + t * 3), 0.72 + 0.006 * a * sin(a + t * 3))
            }
            inside.stroke(u.polyline(spiral), with: .color(clay), lineWidth: u.len(0.02))
        }
        u.stroke(context, u.polyline([(0.42, 0.2), (0.42, 0.42), (0.2, 0.84), (0.8, 0.84), (0.58, 0.42), (0.58, 0.2)]), tint, 0.035)
        // The oxidiser, poured in from a beaker at the top right.
        let tilt = Keyframes.value(t, [(0.2, 0), (0.6, 1), (1.2, 1), (1.5, 0)])
        var beaker = context
        let pivot = u.pt(0.66, 0.16)
        beaker.translateBy(x: pivot.x, y: pivot.y)
        beaker.rotate(by: .degrees(-70 * tilt))
        beaker.translateBy(x: -pivot.x, y: -pivot.y)
        beaker.stroke(u.polyline([(0.66, 0.06), (0.66, 0.18), (0.8, 0.18), (0.8, 0.06)]), with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.03), lineCap: .round, lineJoin: .round))
        if tilt > 0.9 {
            u.stroke(context, u.line((0.6, 0.16), (0.52, 0.62)), tint.opacity(0.7), 0.018)
        }
    }
}

/// A laser: the flash lamp pumps the atoms clay, photons bounce between the
/// mirrors knocking out more photons each pass, and a beam breaks out through
/// the half-silvered end.
enum Laser {
    static let duration = 5.0
    private static let atoms: [(Double, Double)] = (0..<14).map { k -> (Double, Double) in
        let s = Double(k)
        let x: Double = 0.28 + 0.4 * BenchShapes.rand(s * 2.3)
        let y: Double = 0.46 + 0.08 * BenchShapes.rand(s * 5.1)
        return (x, y)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // Mirrors, the rod and the lamp.
        u.stroke(context, u.line((0.14, 0.34), (0.14, 0.66)), tint, 0.045)
        context.stroke(u.line((0.84, 0.34), (0.84, 0.66)), with: .color(tint),
                       style: StrokeStyle(lineWidth: u.len(0.03), dash: [u.len(0.03), u.len(0.02)]))
        u.stroke(context, u.capsule(0.48, 0.5, 0.48, 0.16, corner: 0.03), tint.opacity(0.7), 0.022)
        let flash = t < 1.6 ? max(0, sin(t * 14)) : 0
        let coil = stride(from: 0.26, through: 0.7, by: 0.01).map { x in (x, 0.3 + 0.02 * sin(x * 90)) }
        u.stroke(context, u.polyline(coil), flash > 0.5 ? clay : tint.opacity(0.6), 0.018)
        // Atoms: pumped up by the lamp, knocked down as the light builds.
        let pumped = Ease.clamp(t / 1.4)
        for (k, a) in atoms.enumerated() {
            let excited = BenchShapes.rand(Double(k) * 9.1 + floor(t * 3)) < pumped * (t < 2.4 ? 0.9 : 0.55)
            context.fill(u.circle(a.0, a.1, 0.014), with: .color(excited ? clay : tint.opacity(0.5)))
        }
        // Photons: little wave packets between the mirrors, doubling each pass.
        let passes = max(0, (t - 1.2) / 0.45)
        let count = min(8, Int(pow(2, floor(passes))))
        for k in 0..<(t > 1.2 ? count : 0) {
            let phase = passes + Double(k) * 0.13
            let tri = abs((phase.truncatingRemainder(dividingBy: 2)) - 1)
            let x = 0.18 + 0.62 * (1 - tri)
            let y = 0.44 + 0.12 * BenchShapes.rand(Double(k) * 3.3)
            let packet = stride(from: -0.03, through: 0.03, by: 0.004).map { d in (x + d, y + 0.012 * sin(d * 200)) }
            u.stroke(context, u.polyline(packet), clay, 0.012)
        }
        // The beam.
        let beam = Ease.out((t - 2.6) / 0.6)
        if beam > 0 { u.stroke(context, u.line((0.85, 0.5), (0.85 + 0.13 * beam, 0.5)), clay, 0.02 + 0.03 * beam) }
    }
}

/// The Doppler effect: a clay source moves across, its wavefronts bunched
/// ahead and stretched behind; below, the pitch heard on each side.
enum DopplerEffect {
    static let duration = 4.8
    private static let speed = 0.12, sound = 0.3, every = 0.3

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sourceX = { (s: Double) in 0.22 + speed * s }
        var emitted = 0.0
        while emitted <= t {
            let r = sound * (t - emitted)
            if r > 0.005, r < 0.5 {
                u.stroke(context, u.circle(sourceX(emitted), 0.42, r), tint.opacity(0.8 * (1 - r / 0.5)), 0.018)
            }
            emitted += every
        }
        context.fill(u.circle(sourceX(t), 0.42, 0.03), with: .color(clay))
        // What each side hears: longer waves behind, shorter ahead.
        let behind = sound + speed, ahead = sound - speed
        let low = stride(from: 0.06, through: 0.44, by: 0.004).map { x in (x, 0.86 + 0.035 * sin((x * 8 * .pi) * 0.3 / behind - t * 12)) }
        let high = stride(from: 0.56, through: 0.94, by: 0.004).map { x in (x, 0.86 + 0.035 * sin((x * 8 * .pi) * 0.3 / ahead - t * 12)) }
        u.stroke(context, u.polyline(low), tint, 0.018)
        u.stroke(context, u.polyline(high), clay, 0.018)
    }
}

/// Brownian motion: a pollen grain jitters, knocked about by molecules too
/// small to see but for their dots, and its clay track draws a random walk.
enum BrownianMotion {
    static let duration = 4.8

    /// The grain's walk: small smoothed random steps from the centre.
    private static let walk: [(Double, Double)] = {
        var p = (0.5, 0.5)
        var out = [p]
        for k in 0..<48 {
            let a = BenchShapes.rand(Double(k) * 5.7) * 2 * .pi
            let d = 0.02 + 0.03 * BenchShapes.rand(Double(k) * 3.3)
            p = (min(0.78, max(0.22, p.0 + cos(a) * d)), min(0.78, max(0.22, p.1 + sin(a) * d)))
            out.append(p)
        }
        return out
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<40 {
            let s = Double(k)
            let vx = (BenchShapes.rand(s * 1.3) - 0.5) * 0.6, vy = (BenchShapes.rand(s * 2.7) - 0.5) * 0.6
            let x = (BenchShapes.rand(s * 4.1) + vx * t).truncatingRemainder(dividingBy: 1)
            let y = (BenchShapes.rand(s * 6.3) + vy * t).truncatingRemainder(dividingBy: 1)
            context.fill(u.circle(x < 0 ? x + 1 : x, y < 0 ? y + 1 : y, 0.007), with: .color(tint.opacity(0.45)))
        }
        let progress = Ease.clamp(t / 4.4) * Double(walk.count - 1)
        let whole = Int(progress)
        var track = Array(walk.prefix(whole + 1))
        if whole + 1 < walk.count {
            let a = walk[whole], b = walk[whole + 1], f = progress - Double(whole)
            track.append((a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f))
        }
        if track.count > 1 { u.stroke(context, u.polyline(track), clay.opacity(0.7), 0.016) }
        let grain = track.last ?? (0.5, 0.5)
        let jitter = (0.004 * sin(t * 53), 0.004 * cos(t * 47))
        u.stroke(context, u.circle(grain.0 + jitter.0, grain.1 + jitter.1, 0.06), tint, 0.03)
        for k in 0..<5 {
            let a = Double(k) * 1.26
            context.fill(u.circle(grain.0 + jitter.0 + 0.03 * cos(a), grain.1 + jitter.1 + 0.03 * sin(a), 0.008), with: .color(tint.opacity(0.6)))
        }
    }
}

/// The aurora: the clay Sun blows particles out; the Earth's field lines
/// catch them and funnel them down to the poles, where clay ovals shimmer.
enum Aurora {
    static let duration = 5.0
    private static let earth = (0.66, 0.5), radius = 0.12

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The Sun at the edge.
        context.fill(u.circle(-0.06, 0.5, 0.16), with: .color(clay))
        // Field lines: dipole loops, pressed in on the Sun's side.
        for k in 1...3 {
            let scale = 1 + 0.6 * Double(k)
            for side in [-1.0, 1.0] {
                let squash = side < 0 ? 0.75 : 1.25
                let loop = stride(from: 0.3, through: .pi - 0.3, by: 0.05).map { th -> (Double, Double) in
                    let rr = scale * radius * pow(sin(th), 2)
                    return (earth.0 + side * squash * rr * sin(th), earth.1 - rr * cos(th))
                }
                u.stroke(context, u.polyline(loop), tint.opacity(0.4), 0.016)
            }
        }
        context.fill(u.circle(earth.0, earth.1, radius), with: .color(tint))
        // The wind: particles out from the Sun, caught and spiralling down.
        for k in 0..<12 {
            let s = ((t * 0.3) + Double(k) / 12).truncatingRemainder(dividingBy: 1)
            let north = k % 2 == 0
            let lane = (north ? -1.0 : 1.0) * (0.18 + 0.1 * BenchShapes.rand(Double(k) * 3.3))
            let pole = (earth.0 - 0.02, earth.1 + (north ? -radius : radius))
            let x: Double, y: Double
            if s < 0.6 {
                x = 0.12 + (0.42 - 0.12) * s / 0.6
                y = earth.1 + lane
            } else {
                let f = (s - 0.6) / 0.4
                x = 0.42 + (pole.0 - 0.42) * f + 0.018 * sin(f * 26)
                y = earth.1 + lane + (pole.1 - earth.1 - lane) * f
            }
            context.fill(u.circle(x, y, 0.014), with: .color(clay))
        }
        // The ovals at both poles, shimmering.
        for north in [true, false] {
            let shimmer = 0.6 + 0.4 * sin(t * 6 + (north ? 0 : 1.3))
            u.stroke(context, u.ellipse(earth.0, earth.1 + (north ? -radius - 0.012 : radius + 0.012), 0.17, 0.045), clay.opacity(shimmer), 0.035)
        }
    }
}

/// A mimosa: a touch at the tip and the leaflets fold shut in pairs down the
/// leaf, the stalk droops, then slowly everything opens again.
enum Mimosa {
    static let duration = 5.0
    private static let pairs = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let droop = Keyframes.value(t, [(1.7, 0), (2.1, 1), (3.2, 1), (4.5, 0)])
        let base = (0.18, 0.86)
        let angle = (-50 + 18 * droop) * .pi / 180
        let length = 0.78
        let tip = (base.0 + cos(angle) * length, base.1 + sin(angle) * length)
        u.stroke(context, u.line(base, tip), tint, 0.03)
        // The touch.
        let touch = Ease.clamp((t - 0.35) / 0.35)
        if touch > 0, touch < 1 {
            u.stroke(context, u.circle(tip.0, tip.1, 0.02 + 0.06 * touch), clay.opacity(1 - touch), 0.02)
        }
        for k in 0..<pairs {
            let along = 0.25 + 0.7 * Double(k) / Double(pairs - 1)
            let p = (base.0 + cos(angle) * length * along, base.1 + sin(angle) * length * along)
            // Fold from the tip down, a pair at a time; reopen together.
            let order = Double(pairs - 1 - k)
            let fold = Ease.inOut((t - 0.6 - 0.14 * order) / 0.25) * (1 - Ease.inOut((t - 3.3) / 1.2))
            for side in [-1.0, 1.0] {
                let open = angle + side * 1.15
                let shut = angle - 0.25
                let a = open + (shut - open) * fold
                var leaf = context
                let at = u.pt(p.0, p.1)
                leaf.translateBy(x: at.x, y: at.y)
                leaf.rotate(by: .radians(a))
                leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -u.len(0.018), width: u.len(0.1), height: u.len(0.036))), with: .color(tint))
            }
        }
    }
}

/// The water cycle: the clay sun lifts water off the sea, it gathers into a
/// cloud that drifts over the hills and rains, and the river runs back down.
enum WaterCycle {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // Sun, sea and hills.
        context.fill(u.circle(0.14, 0.14, 0.06), with: .color(clay))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4 + t * 0.4
            u.stroke(context, u.line((0.14 + 0.085 * cos(a), 0.14 + 0.085 * sin(a)), (0.14 + 0.11 * cos(a), 0.14 + 0.11 * sin(a))), clay, 0.018)
        }
        let sea = stride(from: 0.02, through: 0.5, by: 0.01).map { x in (x, 0.8 + 0.012 * sin(x * 40 - t * 3)) }
        u.stroke(context, u.polyline(sea), tint, 0.025)
        var hills = u.polyline([(0.46, 0.9), (0.62, 0.56), (0.72, 0.66), (0.84, 0.48), (0.98, 0.72), (0.98, 0.9)])
        hills.closeSubpath()
        context.fill(hills, with: .color(tint.opacity(0.25)))
        u.stroke(context, u.polyline([(0.46, 0.9), (0.62, 0.56), (0.72, 0.66), (0.84, 0.48), (0.98, 0.72)]), tint, 0.025)
        // The river, flowing down to the sea.
        let river = Smooth.curve([(0.82, 0.54), (0.74, 0.72), (0.6, 0.8), (0.48, 0.82)], samples: 8)
        u.stroke(context, u.polyline(river), tint.opacity(0.6), 0.02)
        for k in 0..<4 {
            let s = (t * 0.4 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
            let p = Polyline.point(river, at: s)
            context.fill(u.circle(p.0, p.1, 0.011), with: .color(tint))
        }
        // Rising vapour.
        for k in 0..<5 {
            let s = (t * 0.5 + Double(k) / 5).truncatingRemainder(dividingBy: 1)
            let x = 0.12 + 0.07 * Double(k)
            context.fill(u.circle(x + 0.01 * sin(s * 9), 0.76 - 0.34 * s, 0.009), with: .color(tint.opacity(0.7 * (1 - s))))
        }
        // The cloud builds, drifts inland and rains.
        let drift = Ease.inOut((t - 1.4) / 1.6)
        let grow = Ease.out(t / 1.4)
        let cx = 0.3 + 0.44 * drift
        CloudShape.draw(context, u, puffs: [(cx - 0.07, 0.34, 0.05 * grow), (cx, 0.3, 0.07 * grow), (cx + 0.07, 0.34, 0.05 * grow)], color: tint)
        let rain = Ease.clamp((t - 3.0) / 0.3) * (1 - Ease.clamp((t - 4.4) / 0.4))
        for k in 0..<6 where rain > 0 {
            let s = (t * 2.2 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
            let x = cx - 0.08 + 0.032 * Double(k)
            u.stroke(context, u.line((x, 0.4 + 0.16 * s), (x - 0.01, 0.43 + 0.16 * s)), tint.opacity(rain), 0.016)
        }
    }
}

/// Fourier epicycles: circles turning on circles, odd harmonics only, trace a
/// square wave that scrolls away to the right.
enum FourierEpicycles {
    static let duration = 5.0
    private static let omega = 2 * Double.pi / 2.5
    private static let harmonics = [1, 3, 5, 7]

    private static func chain(_ s: Double) -> [(Double, Double)] {
        var p = (0.26, 0.5)
        var points = [p]
        for n in harmonics {
            let r = 0.14 * 4 / (.pi * Double(n))
            let a = Double(n) * omega * s
            p = (p.0 + r * cos(a), p.1 - r * sin(a))
            points.append(p)
        }
        return points
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let points = chain(t)
        for (k, n) in harmonics.enumerated() {
            let r = 0.14 * 4 / (.pi * Double(n))
            u.stroke(context, u.circle(points[k].0, points[k].1, r), tint.opacity(0.3), 0.012)
            u.stroke(context, u.line(points[k], points[k + 1]), tint, 0.02)
        }
        let tip = points.last!
        // The wave: the tip's height over the last two seconds, scrolling right.
        let wave = stride(from: 0.0, through: 2.0, by: 0.01).map { back -> (Double, Double) in
            (0.56 + 0.2 * back, chain(t - back).last!.1)
        }
        u.stroke(context, u.line(tip, (0.56, tip.1)), tint.opacity(0.4), 0.012)
        u.stroke(context, u.polyline(wave), clay, 0.022)
        context.fill(u.circle(tip.0, tip.1, 0.016), with: .color(clay))
    }
}

/// A volcano plot: genes rise into a volcano as their significance comes in;
/// past both thresholds, the hits light clay.
enum VolcanoPlot {
    static let duration = 4.8
    private static let genes: [(x: Double, y: Double, delay: Double)] = (0..<130).map { k in
        let s = Double(k)
        let fold = (BenchShapes.rand(s * 1.9) - 0.5) * 2 * (0.4 + 0.6 * BenchShapes.rand(s * 3.7))
        let significance = min(1, pow(abs(fold), 1.4) * (0.7 + 0.6 * BenchShapes.rand(s * 5.3)))
        return (fold, significance, 0.2 + 1.8 * BenchShapes.rand(s * 7.1))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.08, 0.1), (0.08, 0.88), (0.94, 0.88)), tint, 0.025)
        let threshold = 0.88 - 0.72 * 0.45
        let dash = StrokeStyle(lineWidth: u.len(0.01), dash: [u.len(0.02), u.len(0.015)])
        context.stroke(u.line((0.08, threshold), (0.94, threshold)), with: .color(tint.opacity(0.4)), style: dash)
        for x in [0.51 - 0.19, 0.51 + 0.19] {
            context.stroke(u.line((x, 0.1), (x, 0.88)), with: .color(tint.opacity(0.4)), style: dash)
        }
        for g in genes {
            let rise = Ease.out((t - g.delay) / 1.2)
            let x = 0.51 + 0.4 * g.x
            let y = 0.86 - 0.72 * g.y * rise
            let hit = rise > 0.99 && g.y > 0.45 && abs(g.x) > 0.19 / 0.4
            context.fill(u.circle(x, y, hit ? 0.014 : 0.01), with: .color(hit ? clay : tint.opacity(0.45)))
        }
    }
}

/// A Manhattan plot: chromosome by chromosome the skyline rises, and one peak
/// climbs clear of the genome-wide line in clay.
enum ManhattanPlot {
    static let duration = 5.0
    private static let chromosomes = 12
    private static let peakChromosome = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.06, 0.1), (0.06, 0.88), (0.95, 0.88)), tint, 0.025)
        let line = 0.3
        context.stroke(u.line((0.06, line), (0.95, line)), with: .color(clay.opacity(0.6)),
                       style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.02), u.len(0.015)]))
        let width = 0.87 / Double(chromosomes)
        for c in 0..<chromosomes {
            let rise = Ease.out((t - 0.2 - 0.2 * Double(c)) / 0.6)
            guard rise > 0 else { continue }
            let x0 = 0.07 + width * Double(c)
            for k in 0..<14 {
                let s = Double(c * 14 + k)
                let within = (Double(k) + 0.5) / 14
                var height = 0.08 + 0.2 * pow(BenchShapes.rand(s * 2.3), 2)
                if c == peakChromosome {
                    height += 0.5 * exp(-pow((within - 0.5) / 0.16, 2)) * Ease.out((t - 2.8) / 0.8)
                }
                let y = 0.87 - height * rise
                let significant = y < line
                context.fill(u.circle(x0 + width * within, y, 0.011),
                             with: .color(significant ? clay : tint.opacity(c % 2 == 0 ? 0.8 : 0.4)))
            }
        }
        if t > 3.5 {
            let x = 0.07 + width * (Double(peakChromosome) + 0.5)
            context.fill(Sparkles.star(u, x, 0.14, 0.04 * Ease.outBack((t - 3.5) / 0.4)), with: .color(clay))
        }
    }
}
