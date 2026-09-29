// CellBioTwoScenes.swift
// ScienceStatus — viruses budding, trafficking, rotary motors, cell death,
// the cytoskeleton, and the hippocampus. Each draws in a unit square (see
// `UnitSquare`): membranes and machinery in the tint, cargo, genomes and
// signals in clay.

import SwiftUI

/// A membrane with a spherical bud rising out of it. `rise` runs from 0
/// (flat) through 1 (the bud just pinched off) and beyond (the particle
/// floating away).
struct Bud {
    let base: Double, radius: Double, rise: Double

    /// The particle's centre.
    var centre: (Double, Double) {
        let d = -radius + 2 * radius * min(rise, 1)
        return (0.5, base - d - 0.25 * max(0, rise - 1))
    }

    var attached: Bool { rise > 0 && rise < 1 }

    /// The membrane, flat except where it rises round the bud.
    var membrane: [(Double, Double)] {
        guard attached else { return [(0, base), (1, base)] }
        let c = centre, d = base - c.1
        let s = max(-1, min(1, d / radius))
        let from = Double.pi - asin(s), to = 2 * Double.pi + asin(s)
        let arc = stride(from: from, through: to, by: 0.08).map { a in (c.0 + radius * cos(a), c.1 + radius * sin(a)) }
        return [(0, base)] + arc + [(1, base)]
    }

    /// Whether an angle round the bud is above the membrane (part of it).
    func onBud(_ angle: Double) -> Bool {
        if !attached { return rise >= 1 }
        return centre.1 + radius * sin(angle) < base - 0.005
    }
}

/// HIV budding: Gag gathers under the membrane and bends it out into a
/// bud, which pinches off; outside, the particle matures: the Gag lining is
/// cut loose and gathers inward into the clay cone-shaped core.
enum BuddingHIV {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rise = 1.3 * Ease.inOut((t - 0.3) / 1.9) + 0.3 * Ease.inOut((t - 2.2) / 0.6)
        let bud = Bud(base: 0.68, radius: 0.17, rise: rise)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, 0.68).y, width: u.side, height: u.len(0.34))), with: .color(tint.opacity(0.08)))
        u.stroke(scene, u.polyline(bud.membrane), tint, 0.04)
        let c = bud.centre
        if rise >= 1 { u.stroke(scene, u.circle(c.0, c.1, bud.radius), tint, 0.04) }
        // Once free, the Gag lining is cut and gathers inward into the cone.
        let mature = Ease.inOut((t - 2.8) / 0.9)
        let narrow = (c.0 - 0.06, c.1 - 0.05), broad = (c.0 + 0.05, c.1 + 0.05)
        for k in 0..<18 {
            let a = Double(k) * 20 * .pi / 180
            guard bud.onBud(a) || (rise < 1 && abs(cos(a)) < 0.9 && sin(a) > 0.95), rise > 0.08 else { continue }
            let lining = (c.0 + (bud.radius - 0.03) * cos(a), c.1 + (bud.radius - 0.03) * sin(a))
            let f = Double(k) / 17
            let core = (narrow.0 + (broad.0 - narrow.0) * f, narrow.1 + (broad.1 - narrow.1) * f)
            let p = (lining.0 + (core.0 - lining.0) * mature, lining.1 + (core.1 - lining.1) * mature)
            scene.fill(u.circle(p.0, p.1, 0.016), with: .color(clay.opacity(1 - 0.8 * mature)))
        }
        for a in [-60.0, -90, -130, 20] where bud.onBud(a * .pi / 180) {
            let r = a * .pi / 180
            let foot = (c.0 + bud.radius * cos(r), c.1 + bud.radius * sin(r))
            let head = (c.0 + (bud.radius + 0.05) * cos(r), c.1 + (bud.radius + 0.05) * sin(r))
            u.stroke(scene, u.line(foot, head), tint, 0.025)
            scene.fill(u.circle(head.0, head.1, 0.018), with: .color(tint))
        }
        if mature > 0.4 {
            // The cone: narrow end up and left, broad end down and right.
            let mature = (mature - 0.4) / 0.6
            let axis = atan2(broad.1 - narrow.1, broad.0 - narrow.0)
            let n = axis + .pi / 2
            var cone = u.polyline([
                (narrow.0 + 0.022 * cos(n), narrow.1 + 0.022 * sin(n)), (broad.0 + 0.055 * cos(n), broad.1 + 0.055 * sin(n)),
                (broad.0 - 0.055 * cos(n), broad.1 - 0.055 * sin(n)), (narrow.0 - 0.022 * cos(n), narrow.1 - 0.022 * sin(n)),
            ])
            cone.closeSubpath()
            scene.fill(cone, with: .color(clay.opacity(mature)))
            scene.fill(u.circle(broad.0, broad.1, 0.055 * mature), with: .color(clay.opacity(mature)))
            scene.fill(u.circle(narrow.0, narrow.1, 0.022), with: .color(clay.opacity(mature)))
        }
        if rise > 0.85 && rise < 1.05 {
            let neck = (0.5, 0.68)
            u.stroke(scene, u.ellipse(neck.0, neck.1, 0.06, 0.02), tint, 0.02)
        }
    }
}

/// SARS-CoV-2 budding into the ERGIC: spikes gather on the membrane, the
/// clay helical nucleocapsid presses in, and a particle wearing its crown
/// of spikes pinches off into the lumen.
enum BuddingSARS {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rise = 1.3 * Ease.inOut((t - 0.8) / 1.9) + 0.25 * Ease.inOut((t - 2.7) / 0.6)
        let bud = Bud(base: 0.7, radius: 0.16, rise: rise)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(0.7))), with: .color(tint.opacity(0.07)))
        u.stroke(scene, u.polyline(bud.membrane), tint, 0.04)
        let c = bud.centre
        if rise >= 1 { u.stroke(scene, u.circle(c.0, c.1, bud.radius), tint, 0.04) }
        // Spikes: gathering along the flat membrane, then crowning the bud.
        let gather = Ease.inOut((t - 0.2) / 0.7)
        for k in 0..<12 {
            let a = (-90 + 30 * Double(k)) * .pi / 180
            let onBud = bud.onBud(a)
            let foot: (Double, Double), dir: Double
            if onBud {
                foot = (c.0 + bud.radius * cos(a), c.1 + bud.radius * sin(a))
                dir = a
            } else {
                let spread = 0.12 + 0.3 * (1 - gather)
                foot = (0.5 + spread * (Double(k) - 5.5) / 5.5, 0.7)
                dir = -.pi / 2
                guard k % 2 == 0 || gather > 0.5 else { continue }
            }
            let head = (foot.0 + 0.055 * cos(dir), foot.1 + 0.055 * sin(dir))
            u.stroke(scene, u.line(foot, head), clay, 0.022)
            scene.fill(u.ellipse(head.0, head.1, 0.03, 0.03), with: .color(clay))
        }
        // The nucleocapsid: a clay coil, rising from the cytoplasm into the bud.
        let coil = stride(from: 0.0, through: 1.0, by: 0.01).map { s -> (Double, Double) in
            let a = s * 7 * 2 * .pi
            let loop = (0.07 * cos(a * 0.14) , 0.07 * sin(a * 0.14))
            return (loop.0 + 0.018 * cos(a), loop.1 + 0.018 * sin(a))
        }
        let rnp = rise > 0 ? c : (0.5, 0.86)
        let within = rise > 0 ? rnp : (0.5, 0.86 - 0.1 * Ease.inOut(t / 0.8))
        u.stroke(scene, u.polyline(coil.map { (within.0 + $0.0, within.1 + $0.1) }), clay, 0.018)
    }
}

/// Influenza budding: HA and NA stud the membrane, the eight clay genome
/// segments, rods of different lengths, gather into a bundle hanging from
/// the tip of the bud, and the particle buds off.
enum BuddingFlu {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rise = 1.3 * Ease.inOut((t - 1.0) / 1.8) + 0.3 * Ease.inOut((t - 2.8) / 0.6)
        let bud = Bud(base: 0.66, radius: 0.17, rise: rise)
        let fade = Ease.inOut((t - 4.1) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, 0.66).y, width: u.side, height: u.len(0.36))), with: .color(tint.opacity(0.08)))
        u.stroke(scene, u.polyline(bud.membrane), tint, 0.04)
        let c = bud.centre
        if rise >= 1 { u.stroke(scene, u.circle(c.0, c.1, bud.radius), tint, 0.04) }
        for k in 0..<12 {
            let a = (-90 + 30 * Double(k)) * .pi / 180
            guard bud.onBud(a) else { continue }
            let foot = (c.0 + bud.radius * cos(a), c.1 + bud.radius * sin(a))
            let head = (c.0 + (bud.radius + 0.055) * cos(a), c.1 + (bud.radius + 0.055) * sin(a))
            if k % 3 == 0 {
                u.stroke(scene, u.line(foot, head), tint, 0.02)
                scene.fill(u.circle(head.0, head.1, 0.016), with: .color(tint))
            } else {
                u.stroke(scene, u.line(foot, head), tint, 0.03)
            }
        }
        for x in [0.08, 0.16, 0.84, 0.92] {
            u.stroke(scene, u.line((x, 0.66), (x, 0.605)), tint, 0.03)
        }
        // The eight segments, rods of different lengths: scattered at first,
        // then lined up side by side, hanging from the tip of the bud.
        let gather = Ease.inOut((t - 0.3) / 0.8)
        let lengths = [0.11, 0.1, 0.1, 0.09, 0.08, 0.075, 0.065, 0.055]
        for k in 0..<8 {
            let s = Double(k)
            let start = (0.2 + 0.6 * BenchShapes.rand(s), 0.76 + 0.14 * BenchShapes.rand(s + 9))
            let tilt = (BenchShapes.rand(s + 4) - 0.5) * 2.4 * (1 - gather)
            // Four in front, four behind between them, fainter.
            let front = k % 2 == 0
            let slot = -0.07 + 0.045 * Double(k / 2) + (front ? 0 : 0.0225)
            let top = rise > 0.05 ? (c.0 + slot, c.1 - 0.1) : (0.5 + slot, 0.72)
            let p = (start.0 + (top.0 - start.0) * gather, start.1 + (top.1 - start.1) * gather)
            let end = (p.0 + lengths[k] * sin(tilt), p.1 + lengths[k] * cos(tilt))
            u.stroke(scene, u.line(p, end), clay.opacity(front ? 1 : 0.4 + 0.6 * (1 - gather)), 0.02)
        }
    }
}

/// The Golgi: clay cargo buds off the ER, joins the cis face, and works up
/// through the stack of separate sacs, riding a vesicle from each to the
/// next, then leaves the trans face for the cell surface.
enum Golgi {
    static let duration = 4.8
    private static let cisternae = [0.66, 0.56, 0.46, 0.36]
    private static let path: [(Double, Double)] = [(0.18, 0.86), (0.36, 0.72), (0.44, 0.66), (0.5, 0.56), (0.56, 0.46), (0.62, 0.36), (0.74, 0.24), (0.84, 0.1)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let er = stride(from: 0.0, through: 0.5, by: 0.02).map { x in (x, 0.9 + 0.02 * sin(x * 30)) }
        u.stroke(context, u.polyline(er), tint.opacity(0.6), 0.03)
        u.stroke(context, u.line((0.4, 0.07), (1.0, 0.07)), tint, 0.04)
        for (k, y) in cisternae.enumerated() {
            let w = 0.22 - 0.02 * Double(k)
            var sac = Path()
            sac.move(to: u.pt(0.5 - w, y + 0.03))
            sac.addQuadCurve(to: u.pt(0.5 + w, y + 0.03), control: u.pt(0.5, y - 0.05))
            u.stroke(context, sac, tint, 0.045)
            context.fill(u.circle(0.5 - w, y + 0.03, 0.025), with: .color(tint))
            context.fill(u.circle(0.5 + w, y + 0.03, 0.025), with: .color(tint))
        }
        for k in 0..<3 {
            let s = Ease.clamp((t - 0.2 - 1.1 * Double(k)) / 2.6)
            guard s > 0, s < 1 else { continue }
            let p = Polyline.point(path, at: s)
            // The sacs are separate: between them the cargo rides in a vesicle.
            let inSac = cisternae.contains { abs(p.1 - ($0 - 0.005)) < 0.028 }
            if !inSac { u.stroke(context, u.circle(p.0, p.1, 0.045), tint, 0.025) }
            context.fill(u.circle(p.0, p.1, 0.026), with: .color(clay))
        }
    }
}

/// ATP synthase from above: the ring of c-subunits turns past the stator,
/// each picking up a clay proton as it leaves and handing it over on its
/// way back, with the central stalk turning in the middle.
enum ATPRotor {
    static let duration = 4.0
    private static let count = 10

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let turn = t / duration * 2 * .pi
        context.fill(u.capsule(0.82, 0.5, 0.14, 0.26, corner: 0.05), with: .color(tint.opacity(0.35)))
        u.stroke(context, u.capsule(0.82, 0.5, 0.14, 0.26, corner: 0.05), tint, 0.03)
        for k in 0..<count {
            let a = turn + Double(k) * 2 * .pi / Double(count)
            let angle = a.truncatingRemainder(dividingBy: 2 * .pi)
            let p = (0.46 + 0.24 * cos(a), 0.5 + 0.24 * sin(a))
            context.fill(u.circle(p.0, p.1, 0.055), with: .color(tint))
            let loaded = angle > 0.3 && angle < 2 * .pi - 0.3
            if loaded { context.fill(u.circle(p.0 + 0.03 * cos(a), p.1 + 0.03 * sin(a), 0.018), with: .color(clay)) }
        }
        // Protons in below the stator, out above it.
        let step = 2 * .pi / Double(count) / (2 * .pi / duration)
        let phase = (t / step).truncatingRemainder(dividingBy: 1)
        let entering = (0.98 - 0.25 * phase, 0.66 - 0.08 * phase)
        let leaving = (0.73 + 0.25 * phase, 0.42 - 0.08 * phase)
        context.fill(u.circle(entering.0, entering.1, 0.016), with: .color(clay.opacity(min(1, phase * 4))))
        context.fill(u.circle(leaving.0, leaving.1, 0.016), with: .color(clay.opacity(1 - phase)))
        // The central stalk, lopsided so its turning shows.
        var stalk = context
        let c = u.pt(0.46, 0.5)
        stalk.translateBy(x: c.x, y: c.y)
        stalk.rotate(by: .radians(turn))
        var shape = Path()
        shape.addEllipse(in: CGRect(x: -u.len(0.06), y: -u.len(0.06), width: u.len(0.12), height: u.len(0.12)))
        shape.addEllipse(in: CGRect(x: u.len(0.02), y: -u.len(0.035), width: u.len(0.1), height: u.len(0.07)))
        stalk.fill(shape, with: .color(tint.opacity(0.5)))
    }
}

/// Apoptosis: the cell shrinks and blebs, its clay nucleus condenses and
/// breaks up, and it comes apart into tidy apoptotic bodies.
enum Apoptosis {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let shrink = Ease.inOut((t - 0.3) / 0.8)
        let bleb = Ease.inOut((t - 0.9) / 0.8)
        let condense = Ease.inOut((t - 1.3) / 0.6)
        let split = Ease.inOut((t - 2.0) / 0.6)
        let bodies = Ease.inOut((t - 2.8) / 0.8)
        let fade = Ease.inOut((t - 4.1) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let radius = 0.32 - 0.06 * shrink
        if bodies < 1 {
            let outline = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.05).map { a -> (Double, Double) in
                let big: Double = 0.035 * bleb * max(0, sin(5 * a + 1))
                let small: Double = 0.02 * bleb * max(0, sin(7 * a + t * 3))
                let r: Double = radius + big + small
                return (0.5 + r * cos(a), 0.5 + r * sin(a))
            }
            var cell = scene
            cell.opacity = 1 - bodies
            u.stroke(cell, u.polyline(outline), tint, 0.04)
        }
        // The nucleus: whole, condensed, then in pieces.
        if split < 1 {
            scene.fill(u.circle(0.5, 0.5, (0.13 - 0.05 * condense) * (1 - split)), with: .color(clay))
        }
        let pieces: [(Double, Double)] = [(-0.07, -0.05), (0.07, -0.03), (0.0, 0.07), (-0.05, 0.05)]
        let homes: [(Double, Double)] = [(0.24, 0.3), (0.76, 0.32), (0.56, 0.8), (0.26, 0.72)]
        for (k, piece) in pieces.enumerated() where split > 0 {
            let near = (0.5 + piece.0 * split, 0.5 + piece.1 * split)
            let p = (near.0 + (homes[k].0 - near.0) * bodies, near.1 + (homes[k].1 - near.1) * bodies)
            scene.fill(u.circle(p.0, p.1, 0.035), with: .color(clay))
            if bodies > 0 { u.stroke(scene, u.circle(p.0, p.1, 0.035 + 0.05 * bodies), tint.opacity(bodies), 0.03) }
        }
    }
}

/// Microtubule dynamic instability: the α/β lattice grows at its plus end
/// under a clay GTP cap, dimers joining from the solution; the cap is lost,
/// the end frays into curling protofilaments and it shrinks fast, shedding
/// dimers; then the cap comes back and it grows again.
enum Microtubule {
    static let duration = 4.6
    private static let minus = 0.08, spacing = 0.04
    private static let rows: [(y: Double, curl: Double)] = [(0.42, -1), (0.5, -0.5), (0.58, 1)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let end = Keyframes.value(t, [(0, 0.5), (1.5, 0.84), (1.7, 0.84), (2.9, 0.4), (3.1, 0.4), (4.4, 0.66)])
        let shrinking = t > 1.7 && t < 2.95
        let capped = t < 1.6 || t > 3.05
        let rescue = Ease.outBack((t - 3.0) / 0.3)
        let n = Int((end - minus) / spacing)
        let fray = shrinking ? min(1, (t - 1.7) / 0.25) : 0
        for (r, row) in rows.enumerated() {
            for k in 0..<n {
                var p = (minus + spacing * Double(k), row.y)
                // The last few curl away as it shrinks: ram's horns.
                let fromEnd = n - 1 - k
                if fray > 0, fromEnd < 4 {
                    let j = Double(4 - fromEnd)
                    let phi = 0.5 * j * fray
                    let base = minus + spacing * Double(n - 5)
                    p = (base + 0.06 * sin(phi) * j * 0.6 + spacing * 0.5, row.y + row.curl * 0.06 * (1 - cos(phi)) * j * 0.6)
                }
                let alpha = (k + r) % 2 == 0
                let cap = capped && fromEnd < 3 && !(t > 3.0 && t < 3.3 && rescue < 1)
                let colour: Color = cap ? clay : tint.opacity(alpha ? 1 : 0.55)
                context.fill(u.circle(p.0, p.1, 0.017), with: .color(colour))
            }
        }
        // Dimers in solution: joining while it grows, shed while it shrinks.
        for d in 0..<3 {
            let phase = (t * 0.9 + Double(d) * 0.33).truncatingRemainder(dividingBy: 1)
            let growing = !shrinking
            let from = growing ? (end + 0.12, 0.3 + 0.2 * Double(d)) : (end, 0.46 + 0.04 * Double(d))
            let to = growing ? (end + 0.01, 0.46 + 0.04 * Double(d)) : (end + 0.1, 0.25 + 0.25 * Double(d))
            let p = (from.0 + (to.0 - from.0) * phase, from.1 + (to.1 - from.1) * phase)
            let alpha = sin(.pi * phase)
            context.fill(u.circle(p.0, p.1, 0.014), with: .color(tint.opacity(0.8 * alpha)))
            context.fill(u.circle(p.0 + 0.028, p.1, 0.014), with: .color(tint.opacity(0.45 * alpha)))
        }
        context.fill(u.capsule(minus - 0.02, 0.5, 0.03, 0.22, corner: 0.012), with: .color(tint.opacity(0.5)))
    }
}

/// An endosome acidifying: its pumps turn, clay protons pour in and the
/// lumen deepens in colour, and the cargo lets go of its receptor.
enum EndosomeAcid {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let acid = Ease.inOut((t - 0.3) / 3.0)
        let fade = Ease.inOut((t - 4.1) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.circle(0.5, 0.5, 0.28), with: .color(clay.opacity(0.35 * acid)))
        u.stroke(scene, u.circle(0.5, 0.5, 0.28), tint, 0.045)
        for a in [200.0, 330.0] {
            let r = a * .pi / 180
            let p = (0.5 + 0.28 * cos(r), 0.5 + 0.28 * sin(r))
            scene.fill(u.circle(p.0, p.1, 0.045), with: .color(tint))
            let out = (0.5 + 0.38 * cos(r), 0.5 + 0.38 * sin(r))
            u.stroke(scene, u.line(p, out), tint, 0.035)
            scene.fill(u.circle(out.0, out.1, 0.035), with: .color(tint))
            let spin = t * 8
            u.stroke(scene, u.line((p.0 - 0.03 * cos(spin), p.1 - 0.03 * sin(spin)), (p.0 + 0.03 * cos(spin), p.1 + 0.03 * sin(spin))), clay, 0.015)
            let phase = (t * 1.5 + a).truncatingRemainder(dividingBy: 1)
            let start = (0.5 + 0.46 * cos(r + 0.25), 0.5 + 0.46 * sin(r + 0.25))
            let inside = (0.5 + 0.18 * cos(r - 0.2), 0.5 + 0.18 * sin(r - 0.2))
            if t < 3.6 {
                let q = (start.0 + (inside.0 - start.0) * phase, start.1 + (inside.1 - start.1) * phase)
                scene.fill(u.circle(q.0, q.1, 0.014), with: .color(clay))
            }
        }
        let count = Int(22 * acid)
        for k in 0..<count {
            let s = Double(k)
            let r = 0.2 * sqrt(BenchShapes.rand(s)), a = 2 * .pi * BenchShapes.rand(s + 5) + 0.3 * sin(t + s)
            scene.fill(u.circle(0.5 + r * cos(a), 0.5 + r * sin(a), 0.011), with: .color(clay))
        }
        // The receptor at the bottom, and its cargo letting go.
        let foot = (0.5, 0.78)
        u.stroke(scene, u.line(foot, (0.5, 0.7)), tint, 0.03)
        u.stroke(scene, u.line((0.5, 0.7), (0.47, 0.66)), tint, 0.03)
        u.stroke(scene, u.line((0.5, 0.7), (0.53, 0.66)), tint, 0.03)
        let release = Ease.inOut((t - 2.4) / 0.8)
        scene.fill(u.circle(0.5 + 0.08 * release, 0.64 - 0.2 * release, 0.028), with: .color(clay))
    }
}

