// SeparationScenes.swift
// ScienceStatus — separating things: ultracentrifugation, gradients,
// fractions, chromatography and mass spectrometry. Each draws in a unit
// square (see `UnitSquare`): hardware in the tint, the sample and its
// signal in clay.

import SwiftUI

/// An SW 41 swinging-bucket rotor: its six long, thin tubes, each with a
/// clay band on its gradient, fly into the buckets hanging from the rotor;
/// it spins up, the buckets swing out level, the bands sediment down their
/// tubes, and it winds down again.
enum SwingingBucket {
    static let duration = 5.0
    private static let hook = 0.24, reach = 0.24, length = 0.44

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let speed = Keyframes.value(t, [(2.0, 0), (2.8, 1), (3.8, 1), (4.5, 0)])
        // Integrate the spin by hand: the angle is the area under speed.
        let spinTime = max(0, min(t, 2.8) - 2.0) * 0.5 + max(0, min(t, 3.8) - 2.8) + max(0, min(t, 4.5) - 3.8) * 0.5
        let phase = 0.3 + spinTime * 9
        let swing = speed * .pi / 2
        let settled = Ease.inOut((t - 2.5) / 1.6)
        struct Bucket { let x: Double; let depth: Double; let end: (Double, Double); let k: Int }
        let buckets = (0..<6).map { k -> Bucket in
            let a = phase + Double(k) * .pi / 3
            let x = 0.5 + reach * cos(a)
            let out = cos(a) * length * sin(swing)
            return Bucket(x: x, depth: sin(a), end: (x + out, hook + length * cos(swing)), k: k)
        }
        func drawBucket(_ b: Bucket) {
            var layer = scene
            layer.opacity = b.depth < 0 ? 0.45 : 1
            let p = u.pt(b.x, hook)
            let dx = b.end.0 - b.x, dy = b.end.1 - hook
            let reachLength = max(0.08, hypot(dx, dy))
            layer.translateBy(x: p.x, y: p.y)
            layer.rotate(by: .radians(atan2(dy, dx)))
            // The bucket, open at the hook end, and its long thin tube.
            let w = u.len(0.045)
            let shell = Path(roundedRect: CGRect(x: 0, y: -w, width: u.len(reachLength), height: 2 * w), cornerRadius: w)
            layer.fill(shell, with: .color(tint.opacity(0.18)))
            layer.stroke(shell, with: .color(tint), lineWidth: u.len(0.025))
            let loaded = Ease.out((t - 0.3 - 0.22 * Double(b.k)) / 0.35)
            guard loaded > 0 else { return }
            let lift = u.len(0.6 * (1 - loaded))
            var tube = layer
            // Before it lands, the tube sits back out of the bucket's mouth.
            tube.translateBy(x: -lift, y: 0)
            let tw = u.len(0.022)
            let body = Path(roundedRect: CGRect(x: u.len(0.03), y: -tw, width: u.len(reachLength - 0.05), height: 2 * tw), cornerRadius: tw)
            tube.fill(body, with: .color(tint.opacity(0.35)))
            // The band sediments down the tube while it spins.
            let along = 0.3 + 0.52 * settled
            tube.fill(Path(ellipseIn: CGRect(x: u.len(0.03 + (reachLength - 0.05) * along) - tw, y: -tw, width: 2 * tw, height: 2 * tw)), with: .color(clay))
        }
        for b in buckets where b.depth < 0 { drawBucket(b) }
        scene.fill(u.capsule(0.5, hook - 0.02, 0.56, 0.07, corner: 0.03), with: .color(tint))
        scene.fill(u.capsule(0.5, hook - 0.09, 0.12, 0.08, corner: 0.02), with: .color(tint))
        for b in buckets where b.depth >= 0 { drawBucket(b) }
        if speed > 0.5 {
            for side in [-1.0, 1.0] {
                var arc = Path()
                arc.addArc(center: u.pt(0.5, 0.5), radius: u.len(0.46), startAngle: .degrees(side > 0 ? -20 : 160), endAngle: .degrees(side > 0 ? 20 : 200), clockwise: false)
                u.stroke(scene, arc, tint.opacity(0.5 * speed), 0.025)
            }
        }
    }
}

/// Pouring a sucrose gradient: the gradient maker's heavy clay chamber is
/// stirred and fed from the light one as it drains into the tube, and the
/// tube fills in bands, densest at the bottom.
enum SucroseGradient {
    static let duration = 4.6
    private static let bands = 8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let poured = Ease.clamp((t - 0.4) / 3.2) * (1 - Ease.inOut((t - 4.1) / 0.35))
        // The maker: two chambers joined at the bottom.
        for (k, x) in [0.14, 0.34].enumerated() {
            let chamber = u.line((x - 0.07, 0.2), (x - 0.07, 0.6), (x + 0.07, 0.6), (x + 0.07, 0.2))
            let level = 0.3 + 0.26 * poured
            BenchShapes.fill(context, u, chamber, from: level, k == 0 ? tint.opacity(0.2) : clay.opacity(0.9 - 0.5 * poured))
            u.stroke(context, chamber, tint, 0.03)
        }
        u.stroke(context, u.line((0.21, 0.56), (0.27, 0.56)), tint, 0.02)
        let spin = t * 12
        u.stroke(context, u.line((0.34 - 0.03 * cos(spin), 0.575), (0.34 + 0.03 * cos(spin), 0.575)), tint, 0.02)
        var line = Path()
        line.move(to: u.pt(0.41, 0.58))
        line.addQuadCurve(to: u.pt(0.74, 0.12), control: u.pt(0.62, 0.62))
        u.stroke(context, line, tint.opacity(0.6), 0.018)
        // The tube, filling from the bottom up in bands.
        let tube = u.line((0.7, 0.14), (0.7, 0.86), (0.8, 0.86), (0.8, 0.14))
        var body = tube
        body.closeSubpath()
        var inside = context
        inside.clip(to: body)
        let filled = Int(Double(bands) * poured)
        for k in 0..<bands where k < filled || (k == filled && poured > 0) {
            let part = k < filled ? 1 : Double(bands) * poured - Double(filled)
            let bottom = 0.86 - 0.08 * Double(k)
            inside.fill(Path(CGRect(x: u.pt(0.7, 0).x, y: u.pt(0, bottom - 0.08 * part).y, width: u.len(0.1), height: u.len(0.08 * part))),
                        with: .color(clay.opacity(0.9 - 0.1 * Double(k))))
        }
        u.stroke(context, tube, tint, 0.03)
        if poured > 0 && poured < 1 {
            let surface = 0.86 - 0.64 * poured
            u.stroke(context, u.line((0.74, 0.14), (0.74, surface)), clay.opacity(0.6), 0.012)
        }
    }
}

/// Collecting fractions: the tube is pierced at the bottom and drips into a
/// row of tubes that steps along; the clay band comes out into two of them.
enum FractionCollection {
    static let duration = 4.8
    private static let step = 0.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let drained = Ease.clamp((t - 0.3) / 3.6)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let tube = u.line((0.45, 0.06), (0.45, 0.46), (0.5, 0.52), (0.55, 0.46), (0.55, 0.06))
        let top = 0.1 + 0.4 * drained
        var body = tube
        body.closeSubpath()
        var inside = scene
        inside.clip(to: body)
        inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, top).y, width: u.side, height: u.side)), with: .color(tint.opacity(0.2)))
        let band = 0.24 + 0.4 * drained
        if band < 0.52 { inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, band - 0.025).y, width: u.side, height: u.len(0.05))), with: .color(clay)) }
        u.stroke(scene, tube, tint, 0.03)
        u.stroke(scene, u.line((0.5, 0.52), (0.5, 0.58)), tint, 0.015)
        // Which fraction each drop goes to, and the tubes stepping along.
        let current = Int(t / step)
        let shift = Double(current) + Ease.inOut((t.truncatingRemainder(dividingBy: step) - step + 0.15) / 0.15)
        for k in 0..<10 {
            let x = 0.5 + 0.13 * (Double(k) - shift)
            guard x > -0.1, x < 1.1 else { continue }
            let cup = u.line((x - 0.04, 0.7), (x - 0.04, 0.88), (x + 0.04, 0.88), (x + 0.04, 0.7))
            let fill = k < current ? 1.0 : (k == current ? (t.truncatingRemainder(dividingBy: step)) / step : 0)
            if fill > 0 {
                let banded = (3...4).contains(k)
                BenchShapes.fill(scene, u, cup, from: 0.88 - 0.1 * fill, banded ? clay : tint.opacity(0.3))
            }
            u.stroke(scene, cup, tint, 0.022)
        }
        if drained < 1 {
            let fall = (t * 3).truncatingRemainder(dividingBy: 1)
            let banded = (3...4).contains(current)
            scene.fill(u.circle(0.5, 0.6 + 0.14 * fall * fall, 0.013), with: .color(banded ? clay : tint.opacity(0.6)))
        }
    }
}

/// HPLC: the injected clay sample runs into the column and pulls apart into
/// three bands; each crosses the detector as a peak on the chromatogram.
enum HPLC {
    static let duration = 4.6
    private static let speeds = [0.4, 0.28, 0.2]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.capsule(0.06, 0.3, 0.07, 0.12, corner: 0.02), with: .color(tint))
        u.stroke(scene, u.line((0.1, 0.3), (0.16, 0.3)), tint, 0.02)
        u.stroke(scene, u.capsule(0.48, 0.3, 0.62, 0.1, corner: 0.05), tint, 0.03)
        scene.fill(u.capsule(0.88, 0.3, 0.08, 0.14, corner: 0.02), with: .color(tint))
        // Bands running down the column at their own speeds.
        for (k, v) in speeds.enumerated() {
            let x = 0.18 + v * max(0, t - 0.3)
            if x < 0.8 { scene.fill(u.capsule(x, 0.3, 0.04 + 0.02 * Double(k), 0.07, corner: 0.02), with: .color(clay.opacity(0.9 - 0.2 * Double(k)))) }
        }
        // The chromatogram.
        u.stroke(scene, u.line((0.1, 0.86), (0.92, 0.86)), tint.opacity(0.4), 0.02)
        let now = min(t, 4.1)
        let trace = stride(from: 0.0, through: now, by: 0.02).map { s -> (Double, Double) in
            var y = 0.0
            for (k, v) in speeds.enumerated() {
                let arrive = 0.3 + (0.84 - 0.18) / v
                y += [0.3, 0.22, 0.16][k] * exp(-pow((s - arrive) / 0.12, 2))
            }
            return (0.1 + 0.82 * s / 4.1, 0.86 - y)
        }
        if trace.count > 1 { u.stroke(scene, u.polyline(trace), tint, 0.025) }
        if let pen = trace.last { scene.fill(u.circle(pen.0, pen.1, 0.018), with: .color(clay)) }
    }
}

/// MALDI-TOF: the laser flashes on the sample spot, ions lift off and race
/// down the flight tube, lightest first, and each lands as a peak.
enum MALDI {
    static let duration = 4.2
    private static let ions: [(size: Double, speed: Double)] = [(0.014, 1.2), (0.02, 0.8), (0.026, 0.6)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.8) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.capsule(0.08, 0.36, 0.04, 0.3, corner: 0.01), with: .color(tint))
        scene.fill(u.circle(0.11, 0.36, 0.02), with: .color(clay))
        u.stroke(scene, u.line((0.14, 0.26), (0.9, 0.26)), tint.opacity(0.6), 0.02)
        u.stroke(scene, u.line((0.14, 0.46), (0.9, 0.46)), tint.opacity(0.6), 0.02)
        scene.fill(u.capsule(0.92, 0.36, 0.04, 0.24, corner: 0.01), with: .color(tint))
        let flash = 1 - Ease.clamp((t - 0.3) / 0.25)
        if t > 0.3 && flash > 0 { u.stroke(scene, u.line((0.3, 0.06), (0.12, 0.34)), clay.opacity(flash), 0.02) }
        u.stroke(scene, u.line((0.1, 0.84), (0.92, 0.84)), tint.opacity(0.4), 0.02)
        for (k, ion) in ions.enumerated() {
            let flight = max(0, t - 0.35) * ion.speed
            let x = 0.13 + flight * 0.6
            if x < 0.9 && t > 0.35 {
                for j in 0..<3 {
                    scene.fill(u.circle(x - 0.02 * Double(j), 0.33 + 0.03 * Double(j) + 0.005 * Double(k), ion.size), with: .color(tint))
                }
            }
            let arrival = 0.35 + (0.9 - 0.13) / 0.6 / ion.speed
            let peak = Ease.outBack((t - arrival) / 0.25)
            guard peak > 0 else { continue }
            let px = [0.24, 0.46, 0.7][k]
            u.stroke(scene, u.line((px, 0.84), (px, 0.84 - [0.3, 0.2, 0.25][k] * peak)), clay, 0.03)
        }
    }
}

/// Electrospray: the liquid at the needle's tip is drawn into a Taylor
/// cone, a fine jet breaks into a plume of clay droplets, and they shrink
/// and split on their way to the inlet.
enum Electrospray {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.46), (0.22, 0.46)), tint, 0.035)
        u.stroke(context, u.line((0.02, 0.54), (0.22, 0.54)), tint, 0.035)
        var cone = u.polyline([(0.22, 0.46), (0.3, 0.5), (0.22, 0.54)])
        cone.closeSubpath()
        context.fill(cone, with: .color(clay.opacity(0.9)))
        u.stroke(context, u.line((0.3, 0.5), (0.38, 0.5)), clay, 0.01)
        let inlet = u.polyline([(0.94, 0.32), (0.86, 0.47), (0.86, 0.53), (0.94, 0.68)])
        context.fill(inlet, with: .color(tint))
        for k in 0..<22 {
            let s = Double(k)
            let life = ((t / 1.4 + BenchShapes.rand(s)).truncatingRemainder(dividingBy: 1))
            let spread = (BenchShapes.rand(s + 7) - 0.5) * 0.36 * sin(.pi * min(1, life * 1.4))
            let x = 0.38 + 0.46 * life
            let y = 0.5 + spread
            let r = 0.02 * (1 - 0.6 * life)
            context.fill(u.circle(x, y, r), with: .color(clay.opacity(1 - 0.3 * life)))
            if life > 0.55 && k % 3 == 0 { context.fill(u.circle(x + 0.02, y + 0.02, r * 0.6), with: .color(clay)) }
        }
    }
}

/// An Orbitrap: clay ions circle the spindle while swinging along it, each
/// kind at its own pace, and the trace they induce resolves into peaks.
enum Orbitrap {
    static let duration = 4.4
    private static let packets: [Double] = [3.1, 4.3, 5.6]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.0) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        var barrel = Path()
        barrel.move(to: u.pt(0.1, 0.32))
        barrel.addQuadCurve(to: u.pt(0.9, 0.32), control: u.pt(0.5, 0.12))
        barrel.move(to: u.pt(0.1, 0.62))
        barrel.addQuadCurve(to: u.pt(0.9, 0.62), control: u.pt(0.5, 0.82))
        u.stroke(scene, barrel, tint, 0.03)
        var spindle = Path()
        spindle.move(to: u.pt(0.12, 0.47))
        spindle.addQuadCurve(to: u.pt(0.88, 0.47), control: u.pt(0.5, 0.39))
        spindle.addQuadCurve(to: u.pt(0.12, 0.47), control: u.pt(0.5, 0.55))
        scene.fill(spindle, with: .color(tint))
        var trace: [Double] = Array(repeating: 0, count: 60)
        for (k, f) in packets.enumerated() {
            let axial = sin(f * t + Double(k))
            let orbit = t * 7 + Double(k) * 2
            let x = 0.5 + 0.3 * axial
            let y = 0.47 + 0.1 * sin(orbit) * (1 - 0.3 * abs(axial))
            scene.fill(u.circle(x, y, 0.02), with: .color(clay.opacity(cos(orbit) > 0 ? 1 : 0.4)))
            for i in 0..<trace.count {
                let s = t - Double(trace.count - i) * 0.03
                trace[i] += 0.03 * sin(f * s + Double(k))
            }
        }
        let resolve = Ease.inOut((t - 2.8) / 0.6)
        let signal = trace.enumerated().map { i, v in (0.1 + 0.8 * Double(i) / Double(trace.count - 1), 0.88 - 0.05 + v * (1 - resolve)) }
        u.stroke(scene, u.polyline(signal), tint.opacity(1 - resolve), 0.018)
        if resolve > 0 {
            for (k, _) in packets.enumerated() {
                let x = 0.25 + 0.25 * Double(k)
                u.stroke(scene, u.line((x, 0.88), (x, 0.88 - 0.1 * resolve * [1, 0.7, 0.85][k])), clay, 0.03)
            }
        }
    }
}

/// A quadrupole: ions ride between the rods; the wrong masses wobble
/// wider and wider and are lost, and only the clay one comes through.
enum Quadrupole {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for y in [0.34, 0.66] { context.fill(u.capsule(0.5, y, 0.8, 0.06, corner: 0.03), with: .color(tint)) }
        context.fill(u.capsule(0.95, 0.5, 0.04, 0.2, corner: 0.01), with: .color(tint))
        for k in 0..<9 {
            let kind = k % 3
            let life = ((t / 1.6 + Double(k) / 9).truncatingRemainder(dividingBy: 1))
            let x = 0.06 + 0.88 * life
            let growth = kind == 0 ? 0.0 : (kind == 1 ? 4.0 : 6.0)
            let wobble = 0.03 * exp(growth * life) * sin(life * 40 + Double(k))
            guard abs(wobble) < 0.14 else { continue }
            let color: Color = kind == 0 ? clay : tint.opacity(0.8)
            context.fill(u.circle(x, 0.5 + min(0.14, wobble), 0.018), with: .color(color))
        }
    }
}
