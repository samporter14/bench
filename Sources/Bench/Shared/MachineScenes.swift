// MachineScenes.swift
// ScienceStatus — lab scenes of molecular machines at work. Each draws in
// a unit square (see `UnitSquare`): DNA, membranes and machinery in the
// tint, what they act on or make in clay.

import SwiftUI

/// Topoisomerase: overwound DNA twists tighter, the enzyme nicks one
/// strand (its clay ends showing), the helix swivels round and relaxes,
/// and the nick reseals.
enum Topoisomerase {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let wind = Ease.inOut(t / 1.0)
        let relax = Ease.inOut((t - 1.4) / 1.3)
        let turns = 26 + 18 * wind - 30 * relax
        let spin = t * 1.5 + relax * 8
        let nicked = t > 1.2 && t < 2.9
        func strand(_ sign: Double) -> [(Double, Double)] {
            stride(from: 0.04, through: 0.96, by: 0.008).map { x in (x, 0.5 + sign * 0.1 * sin(turns * x + spin)) }
        }
        let a = strand(1), b = strand(-1)
        u.stroke(context, u.polyline(b), tint.opacity(0.6), 0.045)
        if nicked {
            let left = a.filter { $0.0 < 0.47 }, right = a.filter { $0.0 > 0.53 }
            u.stroke(context, u.polyline(left), tint, 0.045)
            u.stroke(context, u.polyline(right), tint, 0.045)
            for end in [left.last, right.first].compactMap({ $0 }) { context.fill(u.circle(end.0, end.1, 0.025), with: .color(clay)) }
        } else {
            u.stroke(context, u.polyline(a), tint, 0.045)
        }
        u.stroke(context, u.capsule(0.5, 0.5, 0.16, 0.36, corner: 0.08), tint.opacity(0.7), 0.04)
        for at in [1.2, 2.9] {
            let k = (t - at) / 0.4
            if k > 0, k < 1 { u.stroke(context, u.circle(0.5, 0.5, 0.05 + 0.08 * k), clay.opacity(1 - k), 0.03) }
        }
    }
}

/// Proteasome threading: a folded protein with its clay ubiquitin tag is
/// caught at the cap; the tag is taken off, the chain unfolds and is drawn
/// down through the barrel, and short pieces tumble out below.
enum ProteasomeThreading {
    static let duration = 4.0
    private static let count = 22

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.62, 0.24, 0.38, corner: 0.06), tint, 0.045)
        for y in [0.53, 0.62, 0.71] { u.stroke(context, u.line((0.4, y), (0.6, y)), tint.opacity(0.5), 0.025) }
        context.fill(u.capsule(0.5, 0.4, 0.34, 0.08, corner: 0.04), with: .color(tint))

        let arrive = Ease.inOut(t / 1.1)
        let unfold = Ease.inOut((t - 1.1) / 0.6)
        let pull = Ease.inOut((t - 1.5) / 1.6)
        let centre = (0.2 + 0.26 * arrive, 0.14 + 0.08 * arrive)
        let chain = (0..<count).map { i -> (Double, Double) in
            let a = Double(i) * 0.8
            let r = 0.02 + 0.004 * Double(i)
            let folded = (centre.0 + r * cos(a), centre.1 + r * sin(a))
            let straight = (0.5, 0.36 - 0.02 * Double(count - 1 - i) + 0.44 * pull)
            return (folded.0 + (straight.0 - folded.0) * unfold, folded.1 + (straight.1 - folded.1) * unfold)
        }
        var outside = context
        outside.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(0.37))))
        u.stroke(outside, u.polyline(chain), tint, 0.035)

        // The tag rides in on the chain and is left at the cap.
        let tagFade = 1 - Ease.clamp((t - 2.2) / 0.5)
        if tagFade > 0 {
            let anchor = t < 1.2 ? chain[0] : (0.34, 0.34)
            for k in 0..<3 {
                context.fill(u.circle(anchor.0 - 0.03 * Double(k), anchor.1 - 0.02 * Double(k), 0.022), with: .color(clay.opacity(tagFade)))
            }
        }
        for k in 0..<5 {
            let age = (t - 1.9 - 0.35 * Double(k)) / 0.9
            guard age > 0, age < 1 else { continue }
            let p = (0.5 + 0.12 * sin(Double(k) * 2.3) * age, 0.82 + 0.14 * age)
            var piece = context
            let at = u.pt(p.0, p.1)
            piece.translateBy(x: at.x, y: at.y)
            piece.rotate(by: .degrees(Double(k) * 50 + age * 200))
            piece.stroke(Path(CGRect(x: -u.len(0.025), y: 0, width: u.len(0.05), height: 0.001)),
                         with: .color(tint.opacity(1 - age)), lineWidth: u.len(0.03))
        }
    }
}

/// Condensin loop extrusion: a clay ring grips the chromatin and reels it
/// in from both sides, so a loop of it grows steadily above the ring.
enum Condensin {
    static let duration = 4.0
    private static let ring = (0.5, 0.76)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let grow = Ease.inOut((t - 0.3) / 3.2)
        let r = 0.03 + 0.2 * grow
        let loop = (0.5, ring.1 - 0.03 - r)
        u.stroke(context, u.line((0.02, ring.1), (0.46, ring.1)), tint, 0.035)
        u.stroke(context, u.line((0.54, ring.1), (0.98, ring.1)), tint, 0.035)
        u.stroke(context, u.line((0.46, ring.1), (0.48, loop.1 + r)), tint, 0.035)
        u.stroke(context, u.line((0.54, ring.1), (0.52, loop.1 + r)), tint, 0.035)
        u.stroke(context, u.circle(loop.0, loop.1, r), tint, 0.035)

        let flow = t * 0.1
        for k in 0..<7 {
            let x = 0.02 + (0.064 * Double(k) + flow).truncatingRemainder(dividingBy: 0.44)
            context.fill(u.circle(x, ring.1, 0.018), with: .color(tint))
            context.fill(u.circle(1 - x, ring.1, 0.018), with: .color(tint))
        }
        if r > 0.06 {
            let beads = Int(r / 0.025)
            for k in 0..<beads {
                let a = Double(k) / Double(beads) * 2 * .pi + flow * 6
                context.fill(u.circle(loop.0 + r * sin(a), loop.1 + r * cos(a), 0.018), with: .color(tint))
            }
        }
        u.stroke(context, u.circle(ring.0, ring.1, 0.045), clay, 0.035)
    }
}

/// Nuclear import: cargo with a clay localisation tag rides its carrier to
/// a pore, slips through the pore's waving filaments, and lets go of the
/// carrier inside the nucleus.
enum NuclearImport {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(Path(CGRect(x: u.pt(0.6, 0).x, y: u.origin.y, width: u.len(0.4), height: u.side)),
                     with: .color(tint.opacity(0.08)))
        for x in [0.54, 0.6] {
            u.stroke(context, u.line((x, 0.02), (x, 0.36)), tint, 0.035)
            u.stroke(context, u.line((x, 0.64), (x, 0.98)), tint, 0.035)
        }
        u.stroke(context, u.line((0.54, 0.36), (0.6, 0.36)), tint, 0.035)
        u.stroke(context, u.line((0.54, 0.64), (0.6, 0.64)), tint, 0.035)

        let pass = Ease.inOut((t - 0.3) / 1.8)
        let x = 0.18 + 0.62 * pass
        let parting = max(0, 1 - abs(x - 0.57) / 0.12)
        for (k, wall) in [0.36, 0.64].enumerated() {
            let dir = k == 0 ? 1.0 : -1.0
            for j in 0..<2 {
                let x0 = 0.555 + 0.03 * Double(j)
                let tip = (x0 + 0.01 * sin(t * 5 + Double(j + k)), wall + dir * (0.08 - 0.05 * parting))
                u.stroke(context, u.line((x0, wall), tip), tint.opacity(0.6), 0.02)
            }
        }
        let release = Ease.inOut((t - 2.4) / 0.8)
        let cargo = (x + 0.06 * release, 0.5 - 0.14 * release)
        let carrier = (x - 0.05 * release, 0.5 + 0.12 * release)
        var arc = Path()
        arc.addArc(center: u.pt(carrier.0, carrier.1), radius: u.len(0.075), startAngle: .degrees(110),
                   endAngle: .degrees(250), clockwise: false)
        u.stroke(context, arc, tint, 0.04)
        context.fill(u.circle(cargo.0, cargo.1, 0.05), with: .color(tint))
        context.fill(u.capsule(cargo.0 - 0.05, cargo.1, 0.04, 0.03, corner: 0.012), with: .color(clay))
    }
}

/// Mitophagy: a crescent double membrane grows round a damaged, clay-marked
/// mitochondrion, seals into a closed vesicle, and carries it away.
enum Mitophagy {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let close = Ease.inOut((t - 0.3) / 1.8)
        let away = Ease.inOut((t - 2.6) / 1.0)
        var scene = context
        scene.translateBy(x: u.len(0.34 * away), y: -u.len(0.1 * away))
        scene.opacity = 1 - 0.9 * away
        u.stroke(scene, u.capsule(0.5, 0.5, 0.28, 0.14, corner: 0.07), tint, 0.04)
        var zigzag: [(Double, Double)] = []
        var x = 0.4, up = true
        while x <= 0.6 {
            zigzag.append((x, up ? 0.47 : 0.53))
            x += 0.033
            up.toggle()
        }
        u.stroke(scene, u.polyline(zigzag), clay, 0.03)
        let span = 90 + 270 * close
        var membrane = Path()
        if span >= 359 {
            membrane = u.circle(0.5, 0.5, 0.26)
        } else {
            membrane.addArc(center: u.pt(0.5, 0.5), radius: u.len(0.26), startAngle: .degrees(180 - span / 2),
                            endAngle: .degrees(180 + span / 2), clockwise: false)
        }
        scene.drawLayer { layer in
            u.stroke(layer, membrane, tint, 0.11)
            layer.blendMode = .destinationOut
            u.stroke(layer, membrane, .black, 0.035)
        }
    }
}

/// A biomolecular condensate: scattered molecules gather into clay
/// droplets; two of them touch and fuse into one, and then the droplets
/// dissolve back into single molecules.
enum Condensate {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let form = Ease.inOut((t - 0.4) / 1.2)
        let fuse = Ease.inOut((t - 2.0) / 0.7)
        let dissolve = Ease.inOut((t - 3.2) / 0.7)
        let gather = form * (1 - dissolve)
        let a = (0.3 + 0.16 * fuse, 0.37), b = (0.64 - 0.18 * fuse, 0.37), c = (0.5, 0.7)
        let radius = 0.1 * gather
        func droplet(_ p: (Double, Double), _ r: Double, _ alpha: Double) {
            guard r > 0.005, alpha > 0.01 else { return }
            context.fill(u.circle(p.0, p.1, r), with: .color(clay.opacity(0.22 * alpha)))
            u.stroke(context, u.circle(p.0, p.1, r), clay.opacity(0.6 * alpha), 0.025)
        }
        let merged = Ease.clamp((fuse - 0.8) / 0.2)
        droplet(a, radius, 1 - merged)
        droplet(b, radius, 1 - merged)
        droplet((0.46, 0.37), radius * 1.41, merged)
        droplet(c, radius, 1)
        for i in 0..<30 {
            let s = Double(i)
            let loose = (0.5 + 0.4 * sin(s * 2.7 + 0.3 * sin(t + s)), 0.5 + 0.4 * cos(s * 1.9 + 0.3 * cos(t * 1.2 + s)))
            let home = [a, b, c][i % 3]
            let fusedHome = i % 3 == 2 ? home : (home.0 + (0.46 - home.0) * merged, home.1)
            let spread = (i % 3 == 2 ? 1.0 : 1 + 0.41 * merged) * 0.07
            let target = (fusedHome.0 + spread * cos(s * 2.4), fusedHome.1 + spread * sin(s * 2.4))
            let p = (loose.0 + (target.0 - loose.0) * gather, loose.1 + (target.1 - loose.1) * gather)
            context.fill(u.circle(p.0, p.1, 0.016), with: .color(tint))
        }
    }
}

/// Mismatch repair: a clamp scans along the DNA, bumps into a mispaired
/// clay base, cuts out the stretch of strand around it, and fills the gap
/// with a new, correctly paired clay patch.
enum MismatchRepair {
    static let duration = 4.0
    private static let top = 0.44, bottom = 0.58
    private static let patch = (0.5, 0.74)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let excise = Ease.inOut((t - 1.9) / 0.4)
        let fill = Ease.inOut((t - 2.5) / 0.8)
        u.stroke(context, u.line((0.02, bottom), (0.98, bottom)), tint, 0.045)
        u.stroke(context, u.line((0.02, top), (patch.0, top)), tint, 0.045)
        u.stroke(context, u.line((patch.1, top), (0.98, top)), tint, 0.045)
        if excise < 1 { u.stroke(context, u.line((patch.0, top), (patch.1, top)), tint.opacity(1 - excise), 0.045) }
        if fill > 0 { u.stroke(context, u.line((patch.0, top), (patch.0 + (patch.1 - patch.0) * fill, top)), clay, 0.05) }
        var x = 0.05
        while x < 0.97 {
            let inPatch = x > patch.0 && x < patch.1
            let filled = patch.0 + (patch.1 - patch.0) * fill >= x
            if abs(x - 0.62) < 0.01 {
                if fill < 0.7 {
                    u.stroke(context, u.line((x, top), (x - 0.015, (top + bottom) / 2)), clay.opacity(inPatch ? 1 - excise : 1), 0.03)
                    u.stroke(context, u.line((x + 0.015, (top + bottom) / 2), (x, bottom)), clay, 0.03)
                } else {
                    u.stroke(context, u.line((x, top), (x, bottom)), tint.opacity(0.5), 0.025)
                }
            } else if !inPatch || excise < 1 || filled {
                u.stroke(context, u.line((x, top), (x, bottom)), tint.opacity(inPatch && !filled ? 0.5 * (1 - excise) : 0.5), 0.025)
            }
            x += 0.06
        }
        let scan = Ease.inOut((t - 0.2) / 1.4)
        let bump = 0.02 * sin(.pi * Ease.clamp((t - 1.6) / 0.25))
        let clampX = 0.12 + (0.54 - 0.12) * scan - bump
        u.stroke(context, u.ellipse(clampX, 0.51, 0.12, 0.3), tint.opacity(1 - 0.6 * Ease.clamp((t - 2.4) / 0.4)), 0.04)
    }
}

/// Homologous recombination: a broken end, its clay-coated overhang out in
/// front, searches along an intact duplex and invades it where the
/// sequence matches, opening a small loop.
enum Recombination {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let coat = Ease.clamp((t - 0.2) / 0.6)
        let search = Ease.inOut((t - 0.9) / 1.2)
        let invade = Ease.inOut((t - 2.2) / 0.8)

        // The intact duplex, its top strand lifted where it is invaded.
        func lifted(_ x: Double) -> Double {
            guard x > 0.46, x < 0.76 else { return 0.66 }
            return 0.66 - 0.09 * invade * sin(.pi * (x - 0.46) / 0.3)
        }
        u.stroke(context, u.polyline(stride(from: 0.02, through: 0.98, by: 0.01).map { ($0, lifted($0)) }), tint, 0.04)
        u.stroke(context, u.line((0.02, 0.76), (0.98, 0.76)), tint, 0.04)
        var x = 0.05
        while x < 0.97 {
            if lifted(x) > 0.655 { u.stroke(context, u.line((x, lifted(x)), (x, 0.76)), tint.opacity(0.45), 0.02) }
            x += 0.06
        }

        // The broken duplex, coming down to search.
        let dx = 0.05 * sin((t - 0.9) * 5) * search * (1 - invade)
        let dy = 0.24 * search
        let y0 = 0.2 + dy, y1 = 0.28 + dy
        u.stroke(context, u.line((0.04 + dx, y0), (0.4 + dx, y0)), tint, 0.04)
        u.stroke(context, u.line((0.04 + dx, y1), (0.4 + dx, y1)), tint, 0.04)
        var r = 0.07
        while r < 0.4 {
            u.stroke(context, u.line((r + dx, y0), (r + dx, y1)), tint.opacity(0.45), 0.02)
            r += 0.06
        }
        // The overhang: straight out, then down into the matching stretch.
        let straight: [(Double, Double)] = [(0.4 + dx, y1), (0.53 + dx, y1), (0.66 + dx, y1)]
        let invaded: [(Double, Double)] = [(0.4 + dx, y1), (0.5, 0.71), (0.72, 0.71)]
        let overhang = (0..<3).map { k in
            (straight[k].0 + (invaded[k].0 - straight[k].0) * invade, straight[k].1 + (invaded[k].1 - straight[k].1) * invade)
        }
        let path = Smooth.curve(overhang, samples: 8)
        u.stroke(context, u.polyline(path), tint, 0.035)
        if coat > 0 {
            for k in stride(from: 0.1, through: 0.95, by: 0.14) {
                let p = Polyline.point(path, at: k)
                context.fill(u.circle(p.0, p.1, 0.02 * coat), with: .color(clay))
            }
        }
    }
}

/// GPCR activation, the textbook picture: the receptor snakes through the
/// membrane seven times; a clay ligand docks in its pocket at the top, the
/// sixth helix swings out underneath, and the G protein's α subunit takes a
/// clay GTP and breaks away from βγ.
enum GPCR {
    static let duration = 4.4
    private static let helices = [0.26, 0.33, 0.4, 0.47, 0.54, 0.61, 0.68]
    private static let top = 0.27, bottom = 0.59, turn = 0.035

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let dock = Ease.out((t - 0.2) / 0.9)
        let swing = Ease.inOut((t - 1.15) / 0.45)
        let gtp = Ease.outBack((t - 1.85) / 0.3)
        let split = Ease.inOut((t - 2.25) / 0.7)

        // The membrane.
        context.fill(u.capsule(0.5, (top + bottom) / 2, 1.04, bottom - top - 0.04, corner: 0.01), with: .color(tint.opacity(0.1)))
        for y in [top + 0.02, bottom - 0.02] { u.stroke(context, u.line((0.0, y), (1.0, y)), tint.opacity(0.45), 0.025) }

        // The receptor: down, up, down… seven crossings, with loops above and
        // below. The sixth helix's lower end swings out as it activates.
        var snake = Path()
        snake.move(to: u.pt(0.2, 0.16))
        snake.addQuadCurve(to: u.pt(helices[0], top), control: u.pt(helices[0], 0.18))
        for (i, x) in helices.enumerated() {
            let out = i >= 5 ? 0.05 * swing : 0
            let down = i % 2 == 0
            let to = down ? bottom : top
            let lower = x + out
            snake.addLine(to: u.pt(down ? lower : x, to))
            if i < helices.count - 1 {
                let next = helices[i + 1] + (i + 1 >= 5 ? 0.05 * swing : 0)
                let y = down ? bottom + turn : top - turn
                let end = down ? (next, bottom) : (helices[i + 1], top)
                snake.addQuadCurve(to: u.pt(end.0, end.1), control: u.pt((down ? lower : x) / 2 + end.0 / 2, y + (down ? turn : -turn)))
            }
        }
        snake.addQuadCurve(to: u.pt(0.78, 0.7), control: u.pt(helices[6] + 0.05 * swing, 0.68))
        u.stroke(context, snake, tint, 0.04)

        // The ligand, docking into the pocket among the top loops.
        context.fill(u.circle(0.44, 0.04 + (0.235 - 0.04) * dock, 0.04), with: .color(clay))

        // The G protein beneath: α with its GTP, then βγ; α breaks away.
        let alpha = (0.42 - 0.14 * split, 0.76 + 0.1 * split)
        context.fill(u.ellipse(alpha.0, alpha.1, 0.2, 0.13), with: .color(tint))
        if gtp > 0 { context.fill(u.circle(alpha.0 - 0.03, alpha.1, 0.028 * gtp), with: .color(clay)) }
        context.fill(u.ellipse(0.6, 0.78, 0.15, 0.12), with: .color(tint.opacity(0.65)))
        context.fill(u.ellipse(0.69, 0.71, 0.07, 0.06), with: .color(tint.opacity(0.65)))
    }
}
