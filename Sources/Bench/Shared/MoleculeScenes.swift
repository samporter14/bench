// MoleculeScenes.swift
// ScienceStatus — lab scenes at the scale of molecules. Each draws in a
// unit square (see `UnitSquare`): structure in the tint, the thing being
// made or carried in clay.

import SwiftUI

/// DNA polymerase copying a single strand: the enzyme slides along the
/// template, which is floppy ahead of it, and leaves a clay partner strand,
/// base-paired, behind it.
enum Polymerase {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = 0.16 + 0.68 * Ease.inOut(t / duration)
        let top = 0.34, bottom = 0.66

        // Template: straight where it has been copied, a loose wave ahead.
        let template = (0...36).map { i -> (Double, Double) in
            let xi = 0.04 + 0.92 * Double(i) / 36
            let ahead = Ease.clamp((xi - x) / 0.12)
            return (xi, bottom + 0.04 * sin(xi * 20 - t * 5) * ahead)
        }
        u.stroke(context, u.polyline(template), tint)

        // The new strand and its base pairs, up to the enzyme.
        if x > 0.1 {
            for xi in stride(from: 0.1, to: x - 0.06, by: 0.12) {
                u.stroke(context, u.line((xi, top), (xi, bottom)), tint.opacity(0.55), 0.05)
            }
            u.stroke(context, u.line((0.04, top), (x, top)), clay)
        }

        // The enzyme clamps both strands, bobbing a little as it goes.
        let bob = 0.015 * sin(t * 6)
        context.fill(u.capsule(x, 0.5 + bob, 0.28, 0.44, corner: 0.12), with: .color(tint))
    }
}

/// A ribosome translating: the mRNA threads between its two subunits and
/// slides through, codon by codon, while a clay chain of amino acids grows
/// out of the top.
enum Ribosome {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lane = 0.72

        // The message, its codons marked, moving right to left.
        u.stroke(context, u.line((0.03, lane), (0.97, lane)), tint)
        let shift = (t * 0.14).truncatingRemainder(dividingBy: 0.14)
        for k in 0..<8 {
            let xi = 0.08 + 0.14 * Double(k) - shift
            guard xi > 0.03, xi < 0.97 else { continue }
            u.stroke(context, u.line((xi, lane), (xi, lane + 0.08)), tint.opacity(0.55), 0.05)
        }

        // Large subunit above the message, small one below.
        context.fill(u.ellipse(0.5, lane - 0.2, 0.54, 0.32), with: .color(tint))
        context.fill(u.ellipse(0.5, lane + 0.12, 0.42, 0.15), with: .color(tint))

        // The chain: a bead every 0.6 s, each pushed up and out by the next,
        // strung on a thin strand back to the exit.
        let spacing = 0.1
        let exit = (0.5, 0.4)
        func place(_ d: Double) -> (Double, Double) {
            (0.5 + 0.07 * sin(d * 14 + 0.6) - 0.07 * sin(0.6), exit.1 - d)
        }
        var beads: [(point: (Double, Double), r: Double)] = []
        for k in 0..<8 {
            let age = t - 0.6 * Double(k) - 0.15
            guard age > 0 else { continue }
            let d = age / 0.6 * spacing
            guard d < 0.34 else { continue }
            beads.append((place(d), 0.052 * Ease.out(age / 0.25)))
        }
        if let oldest = beads.first {
            let strand = stride(from: 0.0, through: exit.1 - oldest.point.1, by: 0.02).map(place)
            u.stroke(context, u.polyline(strand), clay, 0.04)
        }
        for bead in beads {
            context.fill(u.circle(bead.point.0, bead.point.1, bead.r), with: .color(clay))
        }
    }
}

/// Kinesin walking hand over hand along a microtubule, towing a clay
/// vesicle that sways behind it. It stays in the middle while the track
/// slides back under it, so its stride can be long: two straight legs in
/// an upside-down V, the back foot swinging through in an arc to land a
/// stride ahead of the other.
enum Kinesin {
    static let duration = 4.0
    /// Eight steps per scene.
    private static let step = duration / 8
    private static let stride = 0.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let track = 0.88

        // Where each foot is along the track, in track coordinates.
        let n = t / step
        let taken = floor(n)
        let swing = Ease.inOut(n - taken)
        func foot(_ which: Int) -> (x: Double, lift: Double) {
            let done = which == 0 ? ceil(taken / 2) : floor(taken / 2)
            var x = (which == 0 ? -stride / 2 : stride / 2) + 2 * stride * done
            var lift = 0.0
            if Int(taken) % 2 == which, t < duration {
                x += 2 * stride * swing
                lift = sin(.pi * swing)
            }
            return (x, lift)
        }
        let a = foot(0), b = foot(1)
        let body = (a.x + b.x) / 2

        // The microtubule slides back as the body goes forward.
        let offset = body.truncatingRemainder(dividingBy: 0.14)
        for k in -1..<8 {
            let x0 = 0.03 + 0.14 * Double(k) - offset
            let from = max(0.03, x0), to = min(0.97, x0 + 0.1)
            guard to > from else { continue }
            u.stroke(context, u.line((from, track), (to, track)), tint, 0.08)
        }

        let lifted = max(a.lift, b.lift)
        let hip = (0.5, 0.5 - 0.03 * lifted)
        // The planted leg first, so the swinging one passes in front.
        for f in (a.lift > b.lift ? [b, a] : [a, b]) {
            let heel = (0.5 + f.x - body, 0.79 - 0.16 * f.lift)
            u.stroke(context, u.line(hip, heel), tint)
            context.fill(u.ellipse(heel.0, heel.1, 0.11, 0.07), with: .color(tint))
        }

        // Stalk up to the cargo, a big vesicle that trails and sways.
        let cargo = (0.4 + 0.02 * sin(t * 4), 0.2)
        u.stroke(context, u.line(hip, (cargo.0, cargo.1 + 0.15)), tint, 0.06)
        context.fill(u.circle(cargo.0, cargo.1, 0.175), with: .color(clay))
    }
}

/// Two antibodies binding, one after the other. Each drifts in from its
/// side, upside down, swaying and tilting less as it nears, until both of
/// its arm tips rest on the heads of two clay antigens standing up from
/// the membrane; the heads swell once as it binds.
enum Antibody {
    static let duration = 4.0
    /// Where each antibody lands, which side it comes from, and when.
    private static let antibodies: [(x: Double, side: Double, lands: Double)] = [
        (0.28, -1, 1.5), (0.72, 1, 2.4),
    ]
    private static let spread = 0.13

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let membrane = 0.9, head = 0.06, neck = 0.76

        u.stroke(context, u.line((0.03, membrane), (0.97, membrane)), tint)

        // Antigens: a clay stalk with a round head, the epitope.
        for ab in antibodies {
            let bind = Ease.clamp((t - ab.lands) / 0.35)
            let swell = 1 + 0.3 * sin(.pi * bind)
            for dx in [-spread, spread] {
                let x = ab.x + dx
                u.stroke(context, u.line((x, membrane), (x, neck)), clay, 0.05)
                context.fill(u.circle(x, neck - head, head * swell), with: .color(clay))
            }
        }

        // The antibodies, arm tips landing on the tops of the heads.
        let settled = neck - 2 * head - 0.16
        for ab in antibodies {
            let start = ab.lands - 1.5
            let appear = start <= 0 ? 1 : Ease.clamp((t - start) / 0.3)
            guard appear > 0 else { continue }
            let fall = Ease.out((t - start) / 1.5)
            let loose = 1 - fall
            let x = ab.x + ab.side * 0.16 * loose + 0.03 * sin(t * 3.2) * loose
            let y = 0.16 + (settled - 0.16) * fall
            var y2 = context
            y2.opacity = appear
            y2.translateBy(x: u.pt(x, y).x, y: u.pt(x, y).y)
            y2.rotate(by: .degrees(ab.side * 22 * loose + 6 * sin(t * 2.6) * loose))
            var shape = Path()
            shape.move(to: CGPoint(x: 0, y: -u.len(0.18)))
            shape.addLine(to: .zero)
            shape.move(to: CGPoint(x: -u.len(spread), y: u.len(0.16)))
            shape.addLine(to: .zero)
            shape.addLine(to: CGPoint(x: u.len(spread), y: u.len(0.16)))
            y2.stroke(shape, with: .color(tint),
                      style: StrokeStyle(lineWidth: u.len(0.075), lineCap: .round, lineJoin: .round))
        }
    }
}

/// The double helix, turning: two strands, one tint and one clay, joined
/// by base pairs that sweep along as it twists.
enum Helix {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let turns = 1.5, left = 0.06, right = 0.94
        let k = 2 * .pi * turns / (right - left)
        let spin = t * 2 * .pi / 1.8
        func y(_ x: Double, _ offset: Double) -> Double { 0.5 + 0.22 * sin(k * (x - left) - spin + offset) }

        // Base pairs at a fixed pitch along the twist.
        let pitch = Double.pi / 4
        let first = ceil(-spin / pitch)
        var n = first
        while true {
            let x = left + (n * pitch + spin) / k
            if x > right - 0.02 { break }
            if x > left + 0.02 {
                u.stroke(context, u.line((x, y(x, 0)), (x, y(x, .pi))), tint.opacity(0.5), 0.05)
            }
            n += 1
        }
        let xs = stride(from: left, through: right, by: 0.02)
        u.stroke(context, u.polyline(xs.map { ($0, y($0, 0)) }), tint)
        u.stroke(context, u.polyline(xs.map { ($0, y($0, .pi)) }), clay)
    }
}

/// An enzyme at work: a clay substrate drifts into the cleft, the enzyme
/// closes on it, and two smaller products leave.
enum Enzyme {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let dock = Ease.out(t / 1.1)
        let hold = t >= 1.1 && t < 1.8
        let squeeze = hold ? 0.04 * sin(.pi * (t - 1.1) / 0.7) : 0

        // The enzyme: a rounded body with a cup cut into its right side.
        var body = context
        body.clip(to: u.circle(0.64, 0.5, 0.11 - squeeze), options: .inverse)
        body.fill(u.capsule(0.4, 0.5, 0.46, 0.48 - squeeze, corner: 0.16), with: .color(tint))

        if t < 1.8 {
            // Substrate in, and held.
            let x = 0.94 - (0.94 - 0.66) * dock
            context.fill(u.circle(x, 0.5 + 0.08 * (1 - dock) * sin(t * 5), 0.085), with: .color(clay))
        } else {
            // Two products leave, up and down to the right, fading.
            let go = Ease.out((t - 1.8) / 1.4)
            for dir in [-1.0, 1.0] {
                let x = 0.66 + 0.24 * go, y = 0.5 + dir * 0.28 * go
                context.fill(u.circle(x, y, 0.065), with: .color(clay.opacity(1 - 0.6 * go)))
            }
        }
    }
}

/// A phage landing on a cell: it settles on its legs, its tail contracts,
/// and its clay DNA runs from the head down into the cell.
enum Phage {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let membrane = 0.74
        u.stroke(context, u.line((0.04, membrane), (0.96, membrane)), tint)

        let land = Ease.out(t / 1.3)
        let contract = Ease.inOut((t - 1.5) / 0.4)
        let inject = Ease.inOut((t - 1.9) / 1.4)

        // Baseplate just above the membrane; tail and head above it.
        let base = membrane - 0.06 - 0.3 * (1 - land)
        let tail = 0.2 - 0.07 * contract
        let head = base - tail - 0.1

        // Legs splay as it lands.
        let splay = 0.06 + 0.1 * land
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((0.5 + side * 0.03, base), (0.5 + side * splay, base + 0.06)), tint, 0.055)
        }
        u.stroke(context, u.line((0.5, base), (0.5, base - tail)), tint, 0.075)

        // Head: a hexagon, full of clay DNA that drains as it injects.
        let hexagon = (0..<6).map { k -> (Double, Double) in
            let a = Double(k) * .pi / 3 - .pi / 2
            return (0.5 + 0.12 * cos(a), head + 0.12 * sin(a))
        }
        let inside = hexagon.map { (0.5 + ($0.0 - 0.5) * 0.55 * (1 - inject), head + ($0.1 - head) * 0.55 * (1 - inject)) }
        if inject < 1 {
            var fill = u.polyline(inside)
            fill.closeSubpath()
            context.fill(fill, with: .color(clay))
        }
        var outline = u.polyline(hexagon)
        outline.closeSubpath()
        u.stroke(context, outline, tint)

        // DNA entering the cell below the membrane.
        if inject > 0 {
            let strand = stride(from: 0.0, through: 1.0, by: 0.05).map { s in
                (0.5 + 0.06 * sin(s * 9), membrane + 0.02 + 0.2 * s)
            }
            u.stroke(context, u.polyline(strand).trimmedPath(from: 0, to: inject), clay, 0.06)
        }
    }
}

/// A protein folding, in three stages: the extended chain jiggles, its
/// oily residues in clay; it collapses into a loose globule with them
/// tucked inside; then it snaps into a three-helix bundle, the clay core
/// packed between the helices and the polar residues facing out.
enum Folding {
    static let duration = 5.2
    private static let count = 24
    /// The oily residues: the helices' inward faces in the native fold.
    private static let oily: Set<Int> = [1, 4, 5, 9, 12, 13, 17, 20, 21]

    /// The native bundle: three helices (seven residues each, drawn as a
    /// zigzag, the projection of a coil) joined by short loops.
    private static let native: [(Double, Double)] = (0..<count).map { i -> (Double, Double) in
        func helix(_ k: Int, x: Double, down: Bool, inward: Double) -> (Double, Double) {
            let y = down ? 0.24 + 0.087 * Double(k) : 0.76 - 0.087 * Double(k)
            let face = oily.contains(i) ? inward : -inward
            return (x + 0.04 * face, y)
        }
        switch i {
        case 0...6: return helix(i, x: 0.3, down: true, inward: 1)
        case 7: return (0.4, 0.86)
        case 8...14: return helix(i - 8, x: 0.5, down: false, inward: i % 2 == 0 ? 1 : -1)
        case 15: return (0.6, 0.14)
        case 16...22: return helix(i - 16, x: 0.7, down: true, inward: -1)
        default: return (0.76, 0.86)
        }
    }

    /// The molten globule: the fold's own path, shrunk and loose, so the
    /// chain collapses without crossing itself and then firms up.
    private static let globule: [(Double, Double)] = native.enumerated().map { i, n -> (Double, Double) in
        let s = Double(i)
        let dx = 0.03 * (BenchShapes.rand(s * 3.1) - 0.5), dy = 0.03 * (BenchShapes.rand(s * 5.7) - 0.5)
        return (0.5 + 0.55 * (n.0 - 0.5) + dx, 0.5 + 0.55 * (n.1 - 0.5) + dy)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let collapse = Ease.inOut((t - 0.9) / 1.3)
        let settle = Ease.inOut((t - 2.5) / 1.4)
        let residues = (0..<count).map { i -> (Double, Double) in
            let s = Double(i)
            let open = (0.06 + 0.88 * s / Double(count - 1), 0.5 + 0.12 * sin(s * 0.8 + t * 1.6) * (0.6 + 0.4 * sin(s * 0.3)))
            let g = globule[i], n = native[i]
            let a = (open.0 + (g.0 - open.0) * collapse, open.1 + (g.1 - open.1) * collapse)
            let p = (a.0 + (n.0 - a.0) * settle, a.1 + (n.1 - a.1) * settle)
            // A tremble at every stage, least once folded.
            let jiggle = (0.01 - 0.006 * settle) * sin(t * 8 + s * 2.1)
            return (p.0 + jiggle, p.1 - jiggle)
        }
        u.stroke(context, u.polyline(Smooth.curve(residues, samples: 4)), tint, 0.03)
        for (i, p) in residues.enumerated() {
            if oily.contains(i) {
                context.fill(u.circle(p.0, p.1, 0.032), with: .color(clay))
            } else {
                context.fill(u.circle(p.0, p.1, 0.022), with: .color(tint))
            }
        }
    }
}

/// A ball-and-stick molecule turning: a clay centre and four tint atoms
/// on a tetrahedron, nearer atoms drawn larger and in front.
enum Molecule {
    static let duration = 3.6
    private static let corners: [(Double, Double, Double)] = [
        (1, 1, 1), (1, -1, -1), (-1, 1, -1), (-1, -1, 1),
    ].map { ($0.0 / sqrt(3), $0.1 / sqrt(3), $0.2 / sqrt(3)) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let spin = t * 2 * .pi / duration
        let tilt = 0.35
        let atoms = corners.map { c -> (x: Double, y: Double, z: Double) in
            // Turn about the vertical, then tip towards the viewer.
            let x = c.0 * cos(spin) + c.2 * sin(spin)
            let z = -c.0 * sin(spin) + c.2 * cos(spin)
            let y = c.1 * cos(tilt) - z * sin(tilt)
            let z2 = c.1 * sin(tilt) + z * cos(tilt)
            return (0.5 + 0.32 * x, 0.5 + 0.32 * y, z2)
        }.sorted { $0.z < $1.z }

        func atom(_ a: (x: Double, y: Double, z: Double)) {
            u.stroke(context, u.line((0.5, 0.5), (a.x, a.y)), tint, 0.05)
            context.fill(u.circle(a.x, a.y, 0.075 * (1 + 0.2 * a.z)), with: .color(tint))
        }
        for a in atoms where a.z < 0 { atom(a) }
        context.fill(u.circle(0.5, 0.5, 0.11), with: .color(clay))
        for a in atoms where a.z >= 0 { atom(a) }
    }
}

/// A chaperonin at work, side on: an unfolded clay chain drops into the top
/// chamber of the barrel, the lid caps it, the walls flex while the chain
/// folds inside, and the lid lifts to let the folded protein go.
enum Chaperone {
    static let duration = 4.4
    private static let count = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let enter = Ease.inOut((t - 0.2) / 0.9)
        let capped = Keyframes.value(t, [(1.05, 0), (1.35, 1), (2.55, 1), (2.85, 0)])
        let fold = Ease.inOut((t - 1.45) / 0.9)
        let flex = sin(.pi * Ease.clamp((t - 1.35) / 1.2))
        let leave = Ease.inOut((t - 2.85) / 0.9)

        // The barrel: two rings stacked, each a pair of wall blocks, the top
        // ring's walls bowing out while it works.
        let bow = 0.025 * flex
        for (y, h, out) in [(0.52, 0.22, bow), (0.76, 0.22, 0.0)] {
            context.fill(u.capsule(0.31 - out, y, 0.09, h, corner: 0.035), with: .color(tint))
            context.fill(u.capsule(0.69 + out, y, 0.09, h, corner: 0.035), with: .color(tint))
        }
        u.stroke(context, u.line((0.36, 0.64), (0.64, 0.64)), tint.opacity(0.5), 0.03)

        // The chain: loose above, dropping into the chamber, folding into a
        // compact knot, then rising out and away.
        let beads = (0..<count).map { i -> (Double, Double) in
            let f = Double(i)
            let loose = (0.26 + 0.08 * f, 0.14 + 0.05 * sin(f * 1.7 + t * 3))
            let inside = (0.38 + 0.04 * f, 0.52 + 0.06 * sin(f * 1.9 + t * 3) * (1 - fold))
            let a = f * 2.2
            let knot = (0.5 + (0.02 + 0.011 * f) * cos(a), 0.52 + (0.02 + 0.011 * f) * sin(a))
            var p = (loose.0 + (inside.0 - loose.0) * enter, loose.1 + (inside.1 - loose.1) * enter)
            p = (p.0 + (knot.0 - p.0) * fold, p.1 + (knot.1 - p.1) * fold)
            return (p.0 + 0.3 * leave, p.1 - 0.4 * leave)
        }
        u.stroke(context, u.polyline(beads), clay, 0.045)
        for bead in beads {
            context.fill(u.circle(bead.0, bead.1, 0.042), with: .color(clay))
        }

        // The lid comes down onto the top ring and lifts off again.
        if capped > 0 {
            let y = 0.37 - 0.25 * (1 - capped)
            var lid = context
            lid.opacity = capped
            lid.fill(u.capsule(0.5, y, 0.5, 0.075, corner: 0.035), with: .color(tint))
            lid.fill(u.ellipse(0.5, y - 0.035, 0.26, 0.07), with: .color(tint))
        }
    }
}

/// RNA splicing: the clay intron between two tint exons loops out, the loop
/// pops free and floats away, and the exons slide together and join.
enum Splicing {
    static let duration = 3.3
    private static let lane = 0.64
    private static let radius = 0.14

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let r = radius
        let loop = Ease.inOut((t - 0.2) / 1.1)
        let pop = Ease.out((t - 1.5) / 1.1)
        let join = Ease.inOut((t - 1.8) / 0.5)

        // The intron's ends draw in as it loops, leaving a gap that the
        // exons close once it has gone.
        let a = 0.34 + 0.1 * loop, b = 0.66 - 0.1 * loop
        let left = t < 1.5 ? a : a + 0.06 * join
        let right = t < 1.5 ? b : b - 0.06 * join
        u.stroke(context, u.line((0.05, lane), (left, lane)), tint)
        u.stroke(context, u.line((right, lane), (0.95, lane)), tint)

        if t < 1.5 {
            // A straight stretch bending into a loop that stands on the line.
            let intron = stride(from: 0.0, through: 1.0, by: 0.025).map { s -> (Double, Double) in
                let straight = (a + (b - a) * s, lane)
                let angle = .pi / 2 + 2 * .pi * s
                let ring = (0.5 + r * cos(angle) + (s - 0.5) * 0.12, lane - r + r * sin(angle))
                return (straight.0 + (ring.0 - straight.0) * loop, straight.1 + (ring.1 - straight.1) * loop)
            }
            u.stroke(context, u.polyline(intron), clay)
        } else if pop < 1 {
            // Free: a closed loop floating up and away, fading out.
            let centre = (0.5 + 0.08 * pop, lane - r - 0.3 * pop)
            let fade = 1 - Ease.clamp((pop - 0.4) / 0.6)
            u.stroke(context, u.circle(centre.0, centre.1, r * (1 - 0.35 * pop)), clay.opacity(fade))
        }

        // A small clay ring where the exons meet.
        let mark = sin(.pi * Ease.clamp((t - 2.2) / 0.5))
        if mark > 0 {
            u.stroke(context, u.circle(0.5, lane, 0.05 + 0.04 * mark), clay.opacity(mark), 0.05)
        }
    }
}

/// The proteasome: a wiggly clay protein feeds into a small barrel from
/// the left, and short clay pieces come out of the right.
enum Proteasome {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let mouth = 0.36, exit = 0.64
        // The tail end of the protein moves in as it is fed.
        let tail = 0.03 + (mouth - 0.05 - 0.03) * Ease.inOut((t - 0.2) / 2.8)
        if tail < mouth - 0.05 {
            let protein = stride(from: tail, through: mouth, by: 0.015).map { x -> (Double, Double) in
                let loose = (mouth - x) / (mouth - 0.03)
                return (x, 0.5 + 0.09 * loose * sin(x * 38 + t * 6))
            }
            u.stroke(context, u.polyline(protein), clay, 0.06)
        }

        // Pieces: one every 0.45 s, fanning out to the right and fading.
        for k in 0..<7 {
            let age = (t - 0.7 - 0.45 * Double(k)) / 1.1
            guard age > 0, age < 1 else { continue }
            let spread = [-0.14, 0.1, -0.04, 0.16, -0.12, 0.05, 0.13][k]
            let x = exit + 0.04 + 0.26 * Ease.out(age), y = 0.5 + spread * Ease.out(age)
            u.stroke(context, u.line((x, y), (x + 0.05, y)), clay.opacity(1 - age * age), 0.06)
        }

        // The barrel: four stacked rings seen side on.
        u.stroke(context, u.capsule(0.5, 0.5, exit - mouth, 0.28, corner: 0.06), tint)
        for x in [0.43, 0.5, 0.57] {
            u.stroke(context, u.line((x, 0.37), (x, 0.63)), tint, 0.05)
        }
    }
}
