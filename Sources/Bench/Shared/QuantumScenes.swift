// QuantumScenes.swift
// ScienceStatus — atoms and electrons, high voltage, and making a chip.
// Each draws in a unit square (see `UnitSquare`): levels, lobes of one
// phase and apparatus in the tint; the electron, the other phase, the red
// photon, sparks and the pattern in clay.

import SwiftUI

/// Hydrogen, excited: a photon lifts the clay electron from n = 1 to n = 3
/// on the true energy ladder; it falls back in two steps, giving off the
/// red Balmer-α photon (in clay) and then the ultraviolet Lyman-α.
enum ElectronExcitation {
    static let duration = 4.6

    private static func level(_ n: Double) -> Double { 0.12 + 0.72 / (n * n) }

    private static func packet(_ context: GraphicsContext, _ u: UnitSquare, centre: Double, y: Double, wavelength: Double, color: Color) {
        let wave = stride(from: centre - 0.14, through: centre + 0.14, by: 0.004).map { x -> (Double, Double) in
            let envelope = exp(-pow((x - centre) / 0.06, 2))
            return (x, y + 0.035 * envelope * sin(2 * .pi * (x - centre) / wavelength))
        }
        u.stroke(context, u.polyline(wave), color, 0.02)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for n in 1...4 { u.stroke(context, u.line((0.36, level(Double(n))), (0.84, level(Double(n)))), tint, n == 1 ? 0.035 : 0.025) }
        context.stroke(u.line((0.36, 0.12), (0.84, 0.12)), with: .color(tint.opacity(0.5)),
                       style: StrokeStyle(lineWidth: u.len(0.018), lineCap: .round, dash: [u.len(0.02), u.len(0.03)]))
        let n = Keyframes.value(t, [(0.7, 1), (0.9, 3), (1.7, 3), (1.9, 2), (2.7, 2), (2.9, 1)])
        let y = level(max(1, n))
        let e = (0.5, y)
        for (from, to, at) in [(1.0, 3.0, 0.7), (3.0, 2.0, 1.7), (2.0, 1.0, 2.7)] {
            let show = Ease.clamp((t - at) / 0.2) * (1 - Ease.clamp((t - at - 0.6) / 0.3))
            guard show > 0 else { continue }
            u.stroke(context, u.line((0.62, level(from)), (0.62, level(to))), tint.opacity(0.5 * show), 0.018)
            let head = level(to), dir = to > from ? 1.0 : -1.0
            u.stroke(context, u.line((0.6, head + 0.025 * dir), (0.62, head), (0.64, head + 0.025 * dir)), tint.opacity(0.5 * show), 0.018)
        }
        let incoming = Ease.clamp((t - 0.1) / 0.6)
        if incoming < 1 { packet(context, u, centre: 0.04 + 0.4 * incoming, y: level(1) - 0.05, wavelength: 0.016, color: tint) }
        let red = (t - 1.8) / 1.4
        if red > 0, red < 1 { packet(context, u, centre: 0.7 + 0.45 * red, y: 0.25, wavelength: 0.065, color: clay) }
        let uv = (t - 2.8) / 1.2
        if uv > 0, uv < 1 { packet(context, u, centre: 0.7 + 0.45 * uv, y: 0.56, wavelength: 0.019, color: tint) }
        context.fill(u.circle(e.0, e.1, 0.03), with: .color(clay))
    }
}

/// The s orbitals of hydrogen, 1s to 2s to 3s, as a slice through the
/// atom at their true sizes against each other: dots spread by the real
/// electron density, clay where the wave is positive and ink where
/// negative, with the nodes (2s at 2 a₀; 3s at 1.9 and 7.1 a₀) as clear
/// rings between.
enum SOrbitals {
    static let duration = 4.6
    private static let count = 120
    private static let reach: [Double] = [4.5, 12, 22]

    private static func radial(_ n: Int, _ r: Double) -> Double {
        switch n {
        case 1: return exp(-r)
        case 2: return (2 - r) * exp(-r / 2)
        default: return (27 - 18 * r + 2 * r * r) * exp(-r / 3)
        }
    }

    /// Radii (as a share of the orbital's reach) at even steps through the
    /// density in a plane through the nucleus, r|R(r)|².
    private static func radii(_ n: Int) -> [Double] {
        let steps = 1500
        var cdf: [Double] = [0], total = 0.0
        for i in 1...steps {
            let r = reach[n - 1] * Double(i) / Double(steps)
            let psi = radial(n, r)
            total += r * psi * psi
            cdf.append(total)
        }
        var out: [Double] = [], i = 0
        for k in 0..<count {
            let target = total * (Double(k) + 0.5) / Double(count)
            while i < steps && cdf[i] < target { i += 1 }
            out.append(Double(i) / Double(steps))
        }
        return out
    }
    private static let shells: [[Double]] = [radii(1), radii(2), radii(3)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let first = Ease.inOut((t - 1.2) / 0.6), second = Ease.inOut((t - 2.8) / 0.6)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        let grow = Ease.out(t / 0.4)
        for k in 0..<count {
            // Radii in Bohr radii, so each orbital shows at its true size
            // against the others: 3s fills the frame, 1s is small.
            let r1 = shells[0][k] * reach[0], r2 = shells[1][k] * reach[1], r3 = shells[2][k] * reach[2]
            let bohr = (r1 + (r2 - r1) * first) * (1 - second) + r3 * second
            let n = second > 0.5 ? 3 : (first > 0.5 ? 2 : 1)
            let positive = radial(n, bohr) >= 0
            let r = bohr / reach[2]
            let a = Double(k) * 2.39996
            let p = (0.5 + 0.44 * r * grow * cos(a), 0.5 + 0.44 * r * grow * sin(a))
            context.fill(u.circle(p.0, p.1, 0.016), with: .color((positive ? clay : tint).opacity(1 - fade)))
        }
        context.fill(u.circle(0.5, 0.5, 0.012), with: .color(tint.opacity(1 - fade)))
    }
}

/// A turning view of 3-D lobes, for the p and d orbitals.
enum Lobes {
    struct Lobe { let axis: (Double, Double, Double); let positive: Bool; let length: Double; let width: Double; let offset: Double }

    static func turn(_ v: (Double, Double, Double), yaw: Double, pitch: Double) -> (Double, Double, Double) {
        let x = v.0 * cos(yaw) + v.2 * sin(yaw)
        let z = -v.0 * sin(yaw) + v.2 * cos(yaw)
        return (x, v.1 * cos(pitch) - z * sin(pitch), v.1 * sin(pitch) + z * cos(pitch))
    }

    /// Draws lobes back to front round the nucleus at `centre`, scaled by `scale`.
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, _ lobes: [Lobe], yaw: Double, pitch: Double, scale: Double,
                     centre: (Double, Double) = (0.5, 0.5), tint: Color, nucleus: Bool = true) {
        let placed = lobes.map { lobe -> (Lobe, (Double, Double, Double), (Double, Double, Double)) in
            let d = turn(lobe.axis, yaw: yaw, pitch: pitch)
            return (lobe, d, (d.0 * lobe.offset * scale, d.1 * lobe.offset * scale, d.2 * lobe.offset * scale))
        }
        let order = placed.sorted { $0.2.2 < $1.2.2 }
        var drewNucleus = !nucleus
        for (lobe, d, c) in order {
            if !drewNucleus && c.2 > 0 {
                context.fill(u.circle(centre.0, centre.1, 0.02), with: .color(tint))
                drewNucleus = true
            }
            let flat = min(1, hypot(d.0, d.1))
            let major = sqrt(pow(lobe.length * flat, 2) + pow(lobe.width * (1 - flat), 2) + 0.000001) * scale
            let minor = lobe.width * scale
            guard major > 0.002 else { continue }
            var shape = context
            let at = u.pt(centre.0 + c.0, centre.1 - c.1)
            shape.translateBy(x: at.x, y: at.y)
            shape.rotate(by: .radians(atan2(-d.1, d.0)))
            let rect = CGRect(x: -u.len(major), y: -u.len(minor), width: u.len(2 * major), height: u.len(2 * minor))
            shape.fill(Path(ellipseIn: rect), with: .color(lobe.positive ? clay.opacity(0.92) : tint.opacity(0.3)))
            shape.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.8)), lineWidth: u.len(0.014))
        }
        if !drewNucleus { context.fill(u.circle(centre.0, centre.1, 0.02), with: .color(tint)) }
    }
}

/// The three p orbitals appear one at a time, each a pair of lobes on its
/// own axis, clay and ink for the two phases, turning slowly in space.
enum POrbitals {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        var lobes: [Lobes.Lobe] = []
        let axes: [(Double, Double, Double)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]
        for (k, axis) in axes.enumerated() {
            let grow = Ease.outBack((t - 0.2 - 1.0 * Double(k)) / 0.45)
            guard grow > 0 else { continue }
            let size = 0.17 * grow
            lobes.append(.init(axis: axis, positive: true, length: size, width: size * 0.6, offset: size))
            lobes.append(.init(axis: (-axis.0, -axis.1, -axis.2), positive: false, length: size, width: size * 0.6, offset: size))
        }
        Lobes.draw(scene, u, lobes, yaw: 0.6 + t * 0.5, pitch: 0.35, scale: 1, tint: tint)
    }
}

/// d orbitals: the four-leaf clover of d_xy turns forty-five degrees into
/// d_x²−y², then gives way to d_z², two clay lobes through an ink ring.
enum DOrbitals {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.35) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let pitch = 0.9, yaw = 0.25
        let clover = Ease.outBack((t - 0.2) / 0.4) * (1 - Ease.inOut((t - 2.2) / 0.3))
        if clover > 0 {
            let spin = .pi / 4 * Ease.inOut((t - 1.0) / 0.8)
            let lobes = (0..<4).map { k -> Lobes.Lobe in
                let a = .pi / 4 + Double(k) * .pi / 2 - spin
                return .init(axis: (cos(a), 0, sin(a)), positive: k % 2 == 0, length: 0.15 * clover, width: 0.085 * clover, offset: 0.16 * clover)
            }
            Lobes.draw(scene, u, lobes, yaw: yaw, pitch: pitch, scale: 1.2, tint: tint)
        }
        let z2 = Ease.outBack((t - 2.4) / 0.45)
        guard z2 > 0 else { return }
        let ring = 0.14 * z2, tilt = sin(0.45)
        let ellipse = { (from: Double, to: Double) -> [(Double, Double)] in
            stride(from: from, through: to, by: 0.1).map { a in (0.5 + ring * cos(a), 0.5 + ring * tilt * sin(a)) }
        }
        u.stroke(scene, u.polyline(ellipse(.pi, 2 * .pi)), tint.opacity(0.45), 0.06)
        let lobes: [Lobes.Lobe] = [
            .init(axis: (0, 1, 0), positive: true, length: 0.2 * z2, width: 0.1 * z2, offset: 0.2 * z2),
            .init(axis: (0, -1, 0), positive: true, length: 0.2 * z2, width: 0.1 * z2, offset: 0.2 * z2),
        ]
        Lobes.draw(scene, u, lobes, yaw: 0, pitch: 0.45, scale: 1, tint: tint)
        u.stroke(scene, u.polyline(ellipse(0, .pi)), tint.opacity(0.45), 0.06)
    }
}

/// A Tesla coil: the secondary climbs to its toroid, and clay sparks
/// crackle off it, branching, new ones every instant.
enum TeslaCoil {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.capsule(0.5, 0.9, 0.44, 0.08, corner: 0.02), with: .color(tint))
        for k in 0..<3 { u.stroke(context, u.ellipse(0.5, 0.83, 0.2 + 0.07 * Double(k), 0.04 + 0.012 * Double(k)), tint.opacity(0.6), 0.015) }
        u.stroke(context, u.capsule(0.5, 0.6, 0.1, 0.46, corner: 0.02), tint, 0.03)
        var y = 0.4
        while y < 0.82 { u.stroke(context, u.line((0.455, y), (0.545, y)), tint.opacity(0.5), 0.012); y += 0.025 }
        context.fill(u.ellipse(0.5, 0.33, 0.38, 0.1), with: .color(tint))
        let slot = Int(t / 0.13)
        let life = (t / 0.13).truncatingRemainder(dividingBy: 1)
        for k in 0..<3 {
            let seed = Double(slot * 7 + k)
            let a = -.pi * (0.05 + 0.9 * BenchShapes.rand(seed))
            var p = (0.5 + 0.19 * cos(a), 0.33 + 0.05 * sin(a))
            var heading = a
            var bolt = [p], fork: [(Double, Double)] = []
            for step in 0..<7 {
                heading += (BenchShapes.rand(seed * 3 + Double(step)) - 0.5) * 1.1
                p = (p.0 + 0.045 * cos(heading), p.1 + 0.045 * sin(heading))
                bolt.append(p)
                if step == 3 { fork = [p] }
                if step >= 3 && step < 6 {
                    let f = fork[fork.count - 1]
                    let h = heading + 0.7 * (BenchShapes.rand(seed + 50) > 0.5 ? 1 : -1)
                    fork.append((f.0 + 0.04 * cos(h), f.1 + 0.04 * sin(h)))
                }
            }
            let alpha = 1 - 0.6 * life
            u.stroke(context, u.polyline(bolt), clay.opacity(alpha), 0.022)
            if fork.count > 1 { u.stroke(context, u.polyline(fork), clay.opacity(alpha * 0.8), 0.015) }
        }
    }
}

/// Photolithography: resist spins on, UV through the mask exposes it, the
/// exposed resist washes off, the wafer is etched and stripped, and the
/// finished die turns out to carry a familiar little flask.
enum Lithography {
    static let duration = 5.0
    private static let gaps = [0.25, 0.4, 0.55, 0.7]

    private static func die(_ context: GraphicsContext, _ u: UnitSquare, tint: Color) {
        u.stroke(context, u.capsule(0.5, 0.5, 0.6, 0.6, corner: 0.02), tint, 0.03)
        for k in 0..<4 {
            let s = 0.3 + 0.133 * Double(k)
            for pad in [(s, 0.26), (s, 0.74), (0.26, s), (0.74, s)] {
                context.fill(u.capsule(pad.0, pad.1, 0.035, 0.035, corner: 0.005), with: .color(tint))
            }
        }
        for (a, b) in [((0.3, 0.26), (0.36, 0.36)), ((0.7, 0.74), (0.62, 0.62)), ((0.26, 0.7), (0.36, 0.62)), ((0.74, 0.3), (0.64, 0.38))] {
            u.stroke(context, u.line(a, (b.0, a.1), b), clay.opacity(0.6), 0.012)
        }
        var ring = Path()
        ring.addArc(center: u.pt(0.5, 0.5), radius: u.len(0.15), startAngle: .degrees(-60), endAngle: .degrees(250), clockwise: false)
        u.stroke(context, ring, clay, 0.022)
        var flask = u.line((0.48, 0.41), (0.48, 0.47), (0.42, 0.58), (0.58, 0.58), (0.52, 0.47), (0.52, 0.41))
        flask.closeSubpath()
        u.stroke(context, flask, clay, 0.02)
        let tip = (0.5 + 0.15 * cos(-60 * .pi / 180), 0.5 + 0.15 * sin(-60 * .pi / 180))
        context.fill(u.circle(tip.0, tip.1, 0.025), with: .color(clay))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let toDie = Ease.inOut((t - 3.1) / 0.4)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        if toDie < 1 {
            let etched = Ease.inOut((t - 2.2) / 0.4)
            let coat = Ease.out((t - 0.2) / 0.3)
            let stripped = Ease.inOut((t - 2.7) / 0.3)
            let exposed = Ease.inOut((t - 1.0) / 0.6)
            let developed = Ease.inOut((t - 1.8) / 0.3)
            let mask = Keyframes.value(t, [(0.6, -0.9), (0.9, 0), (1.7, 0), (2.0, 0.9)])
            context.drawLayer { side in
                side.opacity = 1 - toDie
                // The wafer, its etched trenches cut out.
                side.drawLayer { wafer in
                    wafer.fill(u.capsule(0.5, 0.85, 0.76, 0.06, corner: 0.005), with: .color(tint))
                    wafer.blendMode = .destinationOut
                    for g in gaps { wafer.fill(u.capsule(g, 0.832, 0.06, 0.036 * etched, corner: 0.003), with: .color(.black)) }
                }
                // The resist: exposed where the light fell, washed out of
                // those windows when developed, stripped at the end.
                if coat > 0, stripped < 1 {
                    side.drawLayer { resist in
                        resist.fill(u.capsule(0.5, 0.8, 0.76 * coat, 0.04, corner: 0.005), with: .color(clay.opacity(1 - stripped)))
                        for g in gaps { resist.fill(u.capsule(g, 0.8, 0.06, 0.04, corner: 0.003), with: .color(tint.opacity(0.8 * exposed))) }
                        resist.blendMode = .destinationOut
                        for g in gaps { resist.fill(u.capsule(g, 0.8, 0.062, 0.044, corner: 0.003), with: .color(.black.opacity(developed))) }
                    }
                }
                // The mask, open over each window.
                if mask < 0.9 {
                    let edges = [0.1] + gaps.flatMap { [$0 - 0.03, $0 + 0.03] } + [0.9]
                    for k in stride(from: 0, to: edges.count, by: 2) {
                        let a = edges[k] + mask, b = edges[k + 1] + mask
                        side.fill(u.capsule((a + b) / 2, 0.42, b - a, 0.04, corner: 0.004), with: .color(tint))
                    }
                }
                if t > 1.0 && t < 1.7 {
                    for g in gaps {
                        for dx in [-0.015, 0.015] { u.stroke(side, u.line((g + dx, 0.06), (g + dx, 0.78)), tint.opacity(0.45), 0.012) }
                    }
                }
            }
        }
        guard toDie > 0 else { return }
        var top = context
        top.opacity = toDie * (1 - fade)
        let c = u.pt(0.5, 0.5)
        top.translateBy(x: c.x, y: c.y)
        top.scaleBy(x: 0.6 + 0.4 * toDie, y: 0.6 + 0.4 * toDie)
        top.translateBy(x: -c.x, y: -c.y)
        die(top, u, tint: tint)
    }
}
