// RNAScenes.swift
// ScienceStatus — lab scenes of famous RNA structures. Every RNA here is
// one molecule folding on itself (see `RNAFold`): the strand in the tint,
// its base pairs as rungs, and ligands, cuts and working parts in clay.

import SwiftUI

/// One helix of a folding RNA: a stretch where the strand pairs with
/// itself. It starts at `base` (for the outermost helix, where the
/// molecule's two ends are) and runs `length` along `angle` (degrees: 0
/// right, 90 down), turning `bend` degrees on the way. It ends in a hairpin
/// loop or, if it has `branches`, a junction they leave from, listed in
/// order round the junction from the helix's left-hand side.
struct RNAHelix {
    var base: (Double, Double) = (0.5, 0.5)
    var angle: Double
    var length: Double
    var width: Double = 0.06
    var bend: Double = 0
    /// How far it has zipped, 0 to 1, from its far end towards its base,
    /// both sides of the hairpin pairing at once.
    var zip: Double = 1
    var branches: [RNAHelix] = []
    /// Unpaired bases pushed out on the left-hand side: where along the
    /// helix (0 to 1) and how far.
    var bulge: (at: Double, size: Double)? = nil
}

/// RNA drawn as one strand that folds: it runs up the left-hand side of a
/// helix, round its loop or through its branches, and back down the right.
/// Where the two sides have zipped they sit a helix-width apart with base
/// pairs between; where they haven't they spread and sway.
enum RNAFold {
    struct Traced {
        var points: [(Double, Double)] = []
        /// Base pairs: the two bases, and how paired they are (0 to 1).
        var rungs: [((Double, Double), (Double, Double), Double)] = []
    }

    static let samples = 16

    static func trace(_ h: RNAHelix, t: Double, seed: Double = 0) -> Traced {
        var centre = [h.base], directions: [Double] = []
        for i in 0...samples {
            let a = (h.angle + h.bend * Double(i) / Double(samples)) * .pi / 180
            directions.append(a)
            if i < samples {
                let c = centre[i]
                centre.append((c.0 + h.length / Double(samples) * cos(a), c.1 + h.length / Double(samples) * sin(a)))
            }
        }
        let spread = min(0.12, 0.45 * h.length)
        var left: [(Double, Double)] = [], right: [(Double, Double)] = []
        var out = Traced()
        for i in 0...samples {
            let s = Double(i) / Double(samples)
            let paired = Ease.clamp((h.zip * 1.3 - (1 - s)) / 0.3)
            let loose = 1 - paired
            let sway = 0.012 * sin(s * 16 + t * 4 + seed) * loose
            var offsetLeft = h.width / 2 + spread * loose * (1 - 0.6 * s) + sway
            let offsetRight = h.width / 2 + spread * loose * (1 - 0.6 * s) - sway
            if let bulge = h.bulge { offsetLeft += bulge.size * exp(-pow((s - bulge.at) / 0.05, 2)) }
            let a = directions[i], n = (sin(a), -cos(a)), c = centre[i]
            left.append((c.0 + n.0 * offsetLeft, c.1 + n.1 * offsetLeft))
            right.append((c.0 - n.0 * offsetRight, c.1 - n.1 * offsetRight))
            if i % 2 == 1, paired > 0.05 { out.rungs.append((left[i], right[i], paired)) }
        }
        out.points = left
        let end = centre[samples], a = directions[samples]
        let d = (cos(a), sin(a)), n = (sin(a), -cos(a))
        if h.branches.isEmpty {
            // The loop, from the left-hand side round to the right.
            let reachLeft = hypot(left[samples].0 - end.0, left[samples].1 - end.1)
            let reachRight = hypot(right[samples].0 - end.0, right[samples].1 - end.1)
            for k in 1..<8 {
                let phi = Double(k) / 8 * .pi
                let lateral = cos(phi) >= 0 ? reachLeft * cos(phi) : reachRight * cos(phi)
                let forward = (0.035 + h.width / 2) * sin(phi)
                out.points.append((end.0 + n.0 * lateral + d.0 * forward, end.1 + n.1 * lateral + d.1 * forward))
            }
        } else {
            let junction = (end.0 + d.0 * 0.04, end.1 + d.1 * 0.04)
            for (k, branch) in h.branches.enumerated() {
                var b = branch
                let ba = b.angle * .pi / 180
                b.base = (junction.0 + 0.035 * cos(ba), junction.1 + 0.035 * sin(ba))
                let inner = trace(b, t: t, seed: seed + Double(k + 1) * 1.7)
                out.points += inner.points
                out.rungs += inner.rungs
            }
        }
        out.points += right.reversed()
        return out
    }

    static func draw(_ context: GraphicsContext, _ u: UnitSquare, _ traced: Traced, color: Color, pairs: Color? = nil) {
        for rung in traced.rungs {
            u.stroke(context, u.line(rung.0, rung.1), (pairs ?? color).opacity((pairs == nil ? 0.55 : 1) * rung.2), 0.02)
        }
        u.stroke(context, u.polyline(traced.points), color, 0.032)
    }

    static func draw(_ context: GraphicsContext, _ u: UnitSquare, _ helix: RNAHelix, t: Double, color: Color,
                     pairs: Color? = nil) {
        draw(context, u, trace(helix, t: t), color: color, pairs: pairs)
    }
}

private func zipping(_ t: Double, from start: Double, over length: Double = 0.5) -> Double {
    Ease.inOut((t - start) / length)
}

/// The HCV IRES: one strand folds into its curved domain II, its branching
/// domain III and domain IV round a clay pseudoknot core, and the finished
/// IRES leans onto a small 40S subunit.
enum HCVIRES {
    static let duration = 4.0
    private static let junction = (0.42, 0.72)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.ellipse(0.74, 0.92, 0.5, 0.2), with: .color(tint.opacity(0.22)))
        let molecule = RNAHelix(base: (0.42, 0.86), angle: -90, length: 0.1, zip: zipping(t, from: 0.2), branches: [
            RNAHelix(angle: -165, length: 0.34, bend: 80, zip: zipping(t, from: 0.4)),
            RNAHelix(angle: -65, length: 0.16, zip: zipping(t, from: 0.8), branches: [
                RNAHelix(angle: -120, length: 0.16, width: 0.05, zip: zipping(t, from: 1.1)),
                RNAHelix(angle: -45, length: 0.16, width: 0.05, zip: zipping(t, from: 1.25)),
                RNAHelix(angle: 20, length: 0.11, width: 0.05, zip: zipping(t, from: 1.4)),
            ]),
            RNAHelix(angle: 25, length: 0.11, width: 0.05, zip: zipping(t, from: 1.55)),
        ])
        let lean = Ease.inOut((t - 2.4) / 0.6)
        var rna = context
        let pivot = u.pt(junction.0, junction.1)
        rna.translateBy(x: pivot.x, y: pivot.y)
        rna.rotate(by: .degrees(14 * lean))
        rna.translateBy(x: -pivot.x, y: -pivot.y)
        RNAFold.draw(rna, u, molecule, t: t, color: tint)
        let knot = Ease.outBack((t - 1.9) / 0.3)
        if knot > 0 { u.stroke(rna, u.circle(junction.0, junction.1, 0.045 * knot), clay, 0.035) }
        let touch = Ease.clamp((t - 3.0) / 0.3)
        if touch > 0 {
            for x in [0.6, 0.72] { context.fill(u.circle(x, 0.82, 0.022 * touch), with: .color(clay)) }
        }
    }
}

/// The CrPV IGR IRES, the RNA that pretends to be a tRNA, folding: its two
/// hairpins zip first, then the long curved arm of domain 3, then the stem
/// that brings the ends together; last the hairpin loops pair into a
/// pseudoknot, a clay arc, and the arm's tRNA-like tip lights in clay.
enum CrPVIRES {
    static let duration = 4.4
    private static let root = (0.48, 0.89)
    private static let rootLength = 0.12
    private static let hairpins: [(angle: Double, length: Double, at: Double)] = [(-150, 0.24, 0.0), (-95, 0.3, 0.2)]
    private static let arm = (angle: -40.0, length: 0.36, bend: 40.0, at: 0.45)

    /// The tip of a helix's loop, following its bend.
    private static func tip(from base: (Double, Double), angle: Double, length: Double, bend: Double = 0) -> (Double, Double) {
        var p = base
        let n = RNAFold.samples
        for i in 0..<n {
            let a = (angle + bend * Double(i) / Double(n)) * .pi / 180
            p = (p.0 + length / Double(n) * cos(a), p.1 + length / Double(n) * sin(a))
        }
        let a = (angle + bend) * .pi / 180
        return (p.0 + 0.06 * cos(a), p.1 + 0.06 * sin(a))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let molecule = RNAHelix(base: root, angle: -90, length: rootLength, zip: zipping(t, from: 1.05, over: 0.6), branches: [
            RNAHelix(angle: hairpins[0].angle, length: hairpins[0].length, width: 0.05, zip: zipping(t, from: hairpins[0].at)),
            RNAHelix(angle: hairpins[1].angle, length: hairpins[1].length, width: 0.05, zip: zipping(t, from: hairpins[1].at),
                     bulge: (at: 0.45, size: 0.03)),
            RNAHelix(angle: arm.angle, length: arm.length, width: 0.05, bend: arm.bend, zip: zipping(t, from: arm.at, over: 0.7)),
        ])
        RNAFold.draw(context, u, molecule, t: t, color: tint)

        let junction = (root.0, root.1 - rootLength - 0.04)
        func base(_ angle: Double) -> (Double, Double) {
            (junction.0 + 0.035 * cos(angle * .pi / 180), junction.1 + 0.035 * sin(angle * .pi / 180))
        }
        let loopA = tip(from: base(hairpins[0].angle), angle: hairpins[0].angle, length: hairpins[0].length)
        let loopB = tip(from: base(hairpins[1].angle), angle: hairpins[1].angle, length: hairpins[1].length)
        let loopC = tip(from: base(arm.angle), angle: arm.angle, length: arm.length, bend: arm.bend)
        // The pseudoknot: the two hairpin loops pairing, an arc between
        // them growing out from its middle.
        let arcs: [((Double, Double), (Double, Double), (Double, Double), Double)] = [
            (loopA, (0.24, 0.28), loopB, 1.85),
        ]
        for (a, control, b, at) in arcs {
            let snap = Ease.out((t - at) / 0.4)
            guard snap > 0 else { continue }
            var arc = Path()
            arc.move(to: u.pt(a.0, a.1))
            arc.addQuadCurve(to: u.pt(b.0, b.1), control: u.pt(control.0, control.1))
            u.stroke(context, arc.trimmedPath(from: 0.5 - snap / 2, to: 0.5 + snap / 2), clay, 0.03)
        }
        let lit = Ease.outBack((t - 2.3) / 0.35)
        if lit > 0 { context.fill(u.circle(loopC.0, loopC.1, 0.035 * lit), with: .color(clay)) }
    }
}

/// The coronavirus frameshift: the message itself folds, just ahead of the
/// ribosome, into a pseudoknot; the ribosome pauses, slips back a position
/// (its clay frame mark shifting) and carries on, unwinding it.
enum Frameshift {
    static let duration = 4.0
    private static let lane = 0.78

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let approach = Ease.inOut((t - 0.2) / 1.4)
        let slip = Ease.inOut((t - 2.0) / 0.35)
        let onward = Ease.inOut((t - 2.6) / 1.2)
        let x = 0.2 + 0.32 * approach - 0.07 * slip + 0.22 * onward
        let unwind = Ease.clamp((x - 0.5) / 0.22)

        // One strand: along the lane, up into the pseudoknot, back to the lane.
        let knot = RNAFold.trace(RNAHelix(base: (0.7, lane - 0.02), angle: -80, length: 0.4, zip: 1 - unwind), t: t)
        guard let first = knot.points.first, let last = knot.points.last else { return }
        u.stroke(context, u.line((0.02, lane), (first.0, lane), first), tint, 0.032)
        RNAFold.draw(context, u, knot, color: tint)
        u.stroke(context, u.line(last, (last.0 + 0.04, lane), (0.98, lane)), tint, 0.032)
        // The pseudoknot's second pairing: loop to the downstream message.
        if unwind < 0.6 {
            var reach = Path()
            reach.move(to: u.pt(0.78, 0.32))
            reach.addQuadCurve(to: u.pt(0.9, lane), control: u.pt(0.96, 0.46))
            u.stroke(context, reach, tint.opacity(0.5 * (1 - unwind / 0.6)), 0.025)
        }
        for k in 0..<14 {
            let tick = 0.04 + 0.07 * Double(k)
            u.stroke(context, u.line((tick, lane), (tick, lane + 0.035)), tint.opacity(0.4), 0.02)
        }
        context.fill(u.ellipse(x, lane - 0.11, 0.2, 0.15), with: .color(tint))
        context.fill(u.ellipse(x, lane + 0.065, 0.16, 0.07), with: .color(tint))
        let mark = 0.04 + 0.07 * floor((x - 0.04) / 0.07 + 0.5)
        u.stroke(context, u.line((mark, lane + 0.05), (mark, lane + 0.09)), clay, 0.04)
    }
}

/// tRNA folding: one strand zips into the flat cloverleaf, which draws its
/// arms in to the compact L; a clay amino acid lands on its 3′ end, and it
/// opens out again.
enum TRNAFold {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let l = Ease.inOut((t - 1.3) / 0.8) * (1 - Ease.inOut((t - 3.1) / 0.7))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * l }
        let molecule = RNAHelix(base: (mix(0.5, 0.7), 0.1), angle: 90, length: 0.2, zip: zipping(t, from: 0.1, over: 0.45),
                                branches: [
            RNAHelix(angle: mix(0, 60), length: mix(0.14, 0.07), width: 0.05, zip: zipping(t, from: 0.7, over: 0.4)),
            RNAHelix(angle: mix(90, 180), length: mix(0.2, 0.34), width: 0.05, zip: zipping(t, from: 0.5, over: 0.4)),
            RNAHelix(angle: mix(180, 225), length: mix(0.14, 0.07), width: 0.05, zip: zipping(t, from: 0.3, over: 0.4)),
        ])
        let traced = RNAFold.trace(molecule, t: t)
        RNAFold.draw(context, u, traced, color: tint)
        let charged = Ease.outBack((t - 2.2) / 0.4) * (1 - Ease.clamp((t - 3.0) / 0.4))
        if charged > 0, let end = traced.points.first {
            context.fill(u.circle(end.0 + 0.02, end.1 - 0.04, 0.04 * charged), with: .color(clay))
        }
    }
}

/// The hammerhead ribozyme: one strand zips its three stems round the
/// junction, the catalytic core tightens and flashes, and the strand cuts
/// itself: the clay 3′ piece comes away.
enum Hammerhead {
    static let duration = 4.0
    private static let junction = (0.43, 0.45)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tighten = 1 - 0.05 * Ease.inOut((t - 1.4) / 0.4)
        let away = Ease.inOut((t - 2.1) / 0.9)
        let molecule = RNAHelix(base: (0.16, 0.18), angle: 45, length: 0.3 * tighten, zip: zipping(t, from: 0.6) * (1 - away),
                                branches: [
            RNAHelix(angle: -30, length: 0.28 * tighten, zip: zipping(t, from: 0.2)),
            RNAHelix(angle: 100, length: 0.3 * tighten, zip: zipping(t, from: 0.4)),
        ])
        let traced = RNAFold.trace(molecule, t: t)
        let cut = traced.points.count - (RNAFold.samples + 1)
        if t < 2.1 {
            RNAFold.draw(context, u, traced, color: tint)
        } else {
            var kept = RNAFold.Traced()
            kept.points = Array(traced.points[..<(cut + 1)])
            kept.rungs = traced.rungs
            RNAFold.draw(context, u, kept, color: tint)
            var piece = context
            piece.translateBy(x: -u.len(0.1 * away), y: -u.len(0.08 * away))
            u.stroke(piece, u.polyline(Array(traced.points[cut...])), clay.opacity(1 - 0.8 * away), 0.035)
        }
        let flash = (t - 1.8) / 0.5
        if flash > 0, flash < 1 {
            u.stroke(context, u.circle(junction.0, junction.1, 0.05 + 0.07 * flash), clay.opacity(1 - flash), 0.03)
        }
    }
}

/// The glmS ribozyme: its fold is already set; a small clay sugar settles
/// into the pocket at its junction, the site lights, and the backbone
/// beside it snaps.
enum GlmS {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let molecule = RNAHelix(base: (0.5, 0.94), angle: -90, length: 0.14, branches: [
            RNAHelix(angle: -125, length: 0.34),
            RNAHelix(angle: -55, length: 0.34),
        ])
        let traced = RNAFold.trace(molecule, t: t)
        let snap = Ease.out((t - 1.9) / 0.3)
        let split = (RNAFold.samples + 1) + (2 * (RNAFold.samples + 1) + 7)
        var first = RNAFold.Traced(), second = RNAFold.Traced()
        first.points = Array(traced.points[..<split])
        second.points = Array(traced.points[split...])
        first.rungs = traced.rungs
        RNAFold.draw(context, u, first, color: tint)
        var shifted = context
        shifted.translateBy(x: u.len(0.02 * snap), y: u.len(0.01 * snap))
        RNAFold.draw(shifted, u, second, color: tint)

        let enter = Ease.out((t - 0.3) / 1.0)
        let sugar = (0.86 + (0.5 - 0.86) * enter, 0.92 + (0.7 - 0.92) * enter)
        var ring = u.polyline(Rings.hexagon(sugar, 0.035))
        ring.closeSubpath()
        context.fill(ring, with: .color(clay))
        let lit = (t - 1.5) / 0.5
        if lit > 0, lit < 1 { u.stroke(context, u.circle(0.5, 0.7, 0.06 + 0.05 * lit), clay.opacity(1 - lit), 0.03) }
    }
}

/// The SAM-I riboswitch: one strand folds into a four-way junction; a small
/// clay SAM docks in the middle, the stems draw in round it, and the
/// switch helix zips into place.
enum SAMRiboswitch {
    static let duration = 4.0
    private static let centre = (0.42, 0.62)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let bind = Ease.inOut((t - 1.4) / 0.6)
        let flip = Ease.inOut((t - 2.2) / 0.7)
        let molecule = RNAHelix(base: (0.18, 0.86), angle: -45, length: 0.3, width: 0.05, zip: zipping(t, from: 0.2),
                                branches: [
            RNAHelix(angle: -150 + 15 * bind, length: 0.22, width: 0.05, zip: zipping(t, from: 0.4)),
            RNAHelix(angle: -70 - 15 * bind, length: 0.24, width: 0.05, zip: zipping(t, from: 0.6)),
            RNAHelix(angle: 20, length: 0.14 + 0.1 * flip, width: 0.05, zip: 0.3 + 0.7 * flip),
        ])
        RNAFold.draw(context, u, molecule, t: t, color: tint)
        let enter = Ease.out((t - 0.8) / 0.7)
        let ligand = (0.9 + (centre.0 - 0.9) * enter, 0.1 + (centre.1 - 0.1) * enter)
        for k in 0..<3 {
            context.fill(u.circle(ligand.0 + 0.025 * Double(k - 1), ligand.1 + (k == 1 ? -0.02 : 0.01), 0.021), with: .color(clay))
        }
    }
}

/// HIV-1 TAR: one strand zips into a slim hairpin with its three-base
/// bulge, bending gently; a clay Tat peptide docks at the bulge and the
/// RNA straightens into its bound shape.
enum TAR {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let bound = Ease.inOut((t - 1.8) / 0.6)
        let hairpin = RNAHelix(base: (0.5, 0.94), angle: -90, length: 0.58, bend: 16 * sin(t * 2.2) * (1 - bound),
                               zip: zipping(t, from: 0.1, over: 0.9), bulge: (at: 0.4, size: 0.045 * (1 - 0.6 * bound)))
        RNAFold.draw(context, u, hairpin, t: t, color: tint)
        let dock = Ease.out((t - 0.9) / 1.0)
        let tat = (0.08 + (0.36 - 0.08) * dock, 0.5 + (0.71 - 0.5) * dock)
        context.fill(u.capsule(tat.0, tat.1, 0.1, 0.04, corner: 0.02), with: .color(clay))
        u.stroke(context, u.line((tat.0 - 0.05, tat.1), (tat.0 - 0.12, tat.1 + 0.03 * sin(t * 4))), clay, 0.025)
    }
}

/// An RNA's possible structures: the same strand flickers between one
/// hairpin, two competing hairpins and a pseudoknot, faint, until the
/// lowest-energy hairpin settles with its pairs in clay.
enum RNAEnsemble {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let settle = Ease.inOut((t - 2.4) / 0.6)
        let turn = Int(t / 0.8) % 3
        func weight(_ i: Int) -> Double {
            let live = (i == turn ? 0.6 : 0.2) * (1 - settle)
            return i == 0 ? live + settle : live
        }
        // One long hairpin.
        RNAFold.draw(context, u, RNAHelix(base: (0.5, 0.9), angle: -90, length: 0.52), t: t,
                     color: tint.opacity(weight(0)), pairs: settle > 0.5 ? clay.opacity(settle) : nil)
        // Two hairpins, joined along the bottom.
        if weight(1) > 0.01 {
            let a = RNAFold.trace(RNAHelix(base: (0.28, 0.9), angle: -90, length: 0.34), t: t)
            let b = RNAFold.trace(RNAHelix(base: (0.72, 0.9), angle: -90, length: 0.34), t: t, seed: 2)
            RNAFold.draw(context, u, a, color: tint.opacity(weight(1)))
            RNAFold.draw(context, u, b, color: tint.opacity(weight(1)))
            if let end = a.points.last, let start = b.points.first {
                u.stroke(context, u.line(end, start), tint.opacity(weight(1)), 0.032)
            }
        }
        // A pseudoknot: a hairpin whose loop pairs with the strand beyond it.
        if weight(2) > 0.01 {
            let hairpin = RNAFold.trace(RNAHelix(base: (0.4, 0.9), angle: -90, length: 0.36), t: t, seed: 4)
            RNAFold.draw(context, u, hairpin, color: tint.opacity(weight(2)))
            if let end = hairpin.points.last {
                u.stroke(context, u.line(end, (0.72, 0.9), (0.72, 0.44)), tint.opacity(weight(2)), 0.032)
            }
            for y in [0.46, 0.5, 0.54] {
                u.stroke(context, u.line((0.47, y), (0.72, y)), tint.opacity(0.55 * weight(2)), 0.02)
            }
        }
    }
}

/// Covariation: in a hairpin's helix, one base changes and its partner
/// changes with it to keep the pair, twice; the helix holds, the changed
/// pairs in clay.
enum Covariation {
    static let duration = 3.6
    private static let pairs: [(Int, Int)] = [(0, 1), (2, 3), (3, 2), (1, 0), (2, 3)]
    private static let mutations: [(pair: Int, to: (Int, Int), at: Double)] = [(1, (0, 1), 0.8), (3, (3, 2), 2.0)]

    private static func base(_ u: UnitSquare, _ kind: Int, _ x: Double, _ y: Double) -> Path {
        let r = 0.026
        switch kind {
        case 0: return u.circle(x, y, r)
        case 1: return u.capsule(x, y, 2 * r, 2 * r, corner: 0.005)
        case 2:
            var tri = u.line((x, y - r * 1.2), (x + r * 1.1, y + r * 0.8), (x - r * 1.1, y + r * 0.8))
            tri.closeSubpath()
            return tri
        default:
            var diamond = u.line((x, y - r * 1.3), (x + r * 1.1, y), (x, y + r * 1.3), (x - r * 1.1, y))
            diamond.closeSubpath()
            return diamond
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var strand = Path()
        strand.move(to: u.pt(0.34, 0.94))
        strand.addLine(to: u.pt(0.34, 0.3))
        strand.addArc(center: u.pt(0.5, 0.3), radius: u.len(0.16), startAngle: .degrees(180), endAngle: .degrees(360),
                      clockwise: false)
        strand.addLine(to: u.pt(0.66, 0.94))
        u.stroke(context, strand, tint, 0.035)
        for (i, pair) in pairs.enumerated() {
            let y = 0.38 + 0.12 * Double(i)
            var left = pair.0, right = pair.1
            var leftChanged = false, rightChanged = false
            for m in mutations where m.pair == i {
                if t >= m.at { left = m.to.0; leftChanged = true }
                if t >= m.at + 0.3 { right = m.to.1; rightChanged = true }
            }
            u.stroke(context, u.line((0.34, y), (0.66, y)), tint.opacity(0.45), 0.02)
            context.fill(base(u, left, 0.43, y), with: .color(leftChanged ? clay : tint))
            context.fill(base(u, right, 0.57, y), with: .color(rightChanged ? clay : tint))
        }
    }
}

/// Dicer: a folded pre-miRNA hairpin slides into Dicer until its end sits
/// in place, Dicer measures along it and clips off the loop, and the
/// short clay duplex is released.
enum Dicer {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.55, 0.5, 0.66, 0.32, corner: 0.14), tint.opacity(0.7), 0.045)
        for k in 0..<6 {
            let x = 0.3 + 0.064 * Double(k)
            u.stroke(context, u.line((x, 0.62), (x, 0.6)), tint.opacity(0.5), 0.02)
        }
        let enter = Ease.inOut((t - 0.2) / 1.2)
        let x0 = -0.3 + 0.58 * enter
        let traced = RNAFold.trace(RNAHelix(base: (x0, 0.5), angle: 0, length: 0.52, width: 0.07), t: t)
        let cutAt = 11, s = RNAFold.samples
        if t < 1.8 {
            RNAFold.draw(context, u, traced, color: tint)
        } else {
            let release = Ease.inOut((t - 2.2) / 1.0)
            let fall = Ease.out((t - 1.9) / 0.8)
            let loopStart = cutAt, loopEnd = traced.points.count - 1 - cutAt
            var duplex = context
            duplex.translateBy(x: -u.len(0.34 * release), y: 0)
            u.stroke(duplex, u.polyline(Array(traced.points[0...cutAt])), clay, 0.032)
            u.stroke(duplex, u.polyline(Array(traced.points[loopEnd...])), clay, 0.032)
            for rung in traced.rungs.prefix(cutAt / 2) { u.stroke(duplex, u.line(rung.0, rung.1), clay.opacity(0.7), 0.02) }
            var loop = context
            loop.translateBy(x: u.len(0.1 * fall), y: u.len(0.2 * fall))
            u.stroke(loop, u.polyline(Array(traced.points[loopStart...loopEnd])), tint.opacity(1 - fall), 0.032)
            for rung in traced.rungs.suffix((s / 2) - cutAt / 2) {
                u.stroke(loop, u.line(rung.0, rung.1), tint.opacity(0.55 * (1 - fall)), 0.02)
            }
        }
        let snip = (t - 1.8) / 0.4
        if snip > 0, snip < 1 { u.stroke(context, u.circle(0.64, 0.5, 0.05 + 0.06 * snip), clay.opacity(1 - snip), 0.03) }
    }
}

/// The HDV ribozyme: one strand folds its nested double pseudoknot round
/// the catalytic pocket, tightens, flashes, and cuts itself once, letting
/// go of its clay 5′ leader.
enum HDV {
    static let duration = 4.0
    private static let pocket = (0.45, 0.45)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tighten = 1 - 0.06 * Ease.inOut((t - 1.8) / 0.4)
        let molecule = RNAHelix(base: (0.24, 0.24), angle: 45, length: 0.26 * tighten, width: 0.055,
                                zip: zipping(t, from: 0.2), branches: [
            RNAHelix(angle: -40, length: 0.22 * tighten, width: 0.05, zip: zipping(t, from: 0.6)),
            RNAHelix(angle: 60, length: 0.22 * tighten, width: 0.05, zip: zipping(t, from: 0.8)),
            RNAHelix(angle: 150, length: 0.22 * tighten, width: 0.05, zip: zipping(t, from: 0.4)),
        ])
        let traced = RNAFold.trace(molecule, t: t)
        RNAFold.draw(context, u, traced, color: tint)
        // The nested pseudoknot: two loops pairing beneath the pocket.
        let knot = Ease.clamp((t - 1.3) / 0.4)
        if knot > 0 {
            var arc = Path()
            arc.move(to: u.pt(0.56, 0.68))
            arc.addQuadCurve(to: u.pt(0.26, 0.6), control: u.pt(0.42, 0.86))
            u.stroke(context, arc, tint.opacity(0.6 * knot), 0.025)
        }
        let flash = (t - 2.3) / 0.5
        if flash > 0, flash < 1 { u.stroke(context, u.circle(pocket.0, pocket.1, 0.05 + 0.07 * flash), clay.opacity(1 - flash), 0.03) }
        if let start = traced.points.first {
            let away = Ease.inOut((t - 2.5) / 0.9)
            let leader = [(start.0 - 0.12 - 0.12 * away, start.1 - 0.02 - 0.12 * away),
                          (start.0 - 0.06 - 0.1 * away, start.1 + 0.02 - 0.1 * away),
                          (start.0 - 0.1 * away, start.1 - 0.1 * away)]
            u.stroke(context, u.polyline(Smooth.curve(leader)), clay.opacity(1 - 0.8 * away), 0.032)
        }
    }
}

/// An RNA helicase: a ring runs along a folded hairpin from its base,
/// separating its two sides behind it into loose, waving single strands.
enum RNAHelicase {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let along = 0.02 + 0.8 * Ease.inOut((t - 0.2) / 3.0)
        let hairpin = RNAHelix(base: (0.06, 0.5), angle: 0, length: 0.78, width: 0.08, zip: 1 - along)
        RNAFold.draw(context, u, hairpin, t: t, color: tint)
        let x = 0.06 + 0.78 * along
        u.stroke(context, u.ellipse(x, 0.5, 0.1, 0.22), tint, 0.045)
        let a = t * 2 * .pi / 0.9
        context.fill(u.circle(x + 0.05 * cos(a), 0.5 + 0.11 * sin(a), 0.03), with: .color(clay))
    }
}

/// A G-quadruplex: one guanine-rich strand folds so its four runs of G
/// stack into three square quartets round a clay ion, then relaxes again.
enum GQuadruplex {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fold = Ease.inOut((t - 0.3) / 1.4) * (1 - Ease.inOut((t - 3.1) / 0.7))
        // Folded: four runs round the quartets (left, back, right, front),
        // each three high; the strand goes down, up, down, up.
        let columns: [(x: Double, lift: Double)] = [(0.3, 0), (0.5, -0.07), (0.7, 0), (0.5, 0.07)]
        let layers = [0.36, 0.5, 0.64]
        var folded: [(Double, Double)] = []
        for (c, column) in columns.enumerated() {
            let order = c % 2 == 0 ? layers : layers.reversed()
            for y in order { folded.append((column.x, y + column.lift)) }
        }
        let loose = (0..<12).map { i -> (Double, Double) in
            (0.1 + 0.8 * Double(i) / 11, 0.5 + 0.1 * sin(Double(i) * 0.9 + t * 1.5))
        }
        let guanines = (0..<12).map { i in
            (loose[i].0 + (folded[i].0 - loose[i].0) * fold, loose[i].1 + (folded[i].1 - loose[i].1) * fold)
        }
        // Loops between the runs, folded out of the way.
        let loopsFolded = [(0.38, 0.74), (0.62, 0.24), (0.62, 0.78)]
        let loopsLoose = [(0.33, 0.62), (0.6, 0.38), (0.84, 0.62)]
        let loops = (0..<3).map { k in
            (loopsLoose[k].0 + (loopsFolded[k].0 - loopsLoose[k].0) * fold,
             loopsLoose[k].1 + (loopsFolded[k].1 - loopsLoose[k].1) * fold)
        }
        var strand: [(Double, Double)] = [(0.04, guanines[0].1 + 0.08)]
        for (i, g) in guanines.enumerated() {
            strand.append(g)
            if i % 3 == 2, i / 3 < 3 { strand.append(loops[i / 3]) }
        }
        strand.append((0.96, guanines[11].1 - 0.08))
        // The quartets first: three stacked square planes, one per layer.
        if fold > 0.3 {
            let k = (fold - 0.3) / 0.7
            for layer in 0..<3 {
                var quartet = u.polyline([0, 1, 2, 3].map { c -> (Double, Double) in
                    let run = c * 3
                    return guanines[run + (c % 2 == 0 ? layer : 2 - layer)]
                })
                quartet.closeSubpath()
                context.fill(quartet, with: .color(tint.opacity(0.14 * k)))
                u.stroke(context, quartet, tint.opacity(0.6 * k), 0.025)
            }
        }
        u.stroke(context, u.polyline(Smooth.curve(strand, samples: 6)), tint.opacity(0.8), 0.026)
        for g in guanines { context.fill(u.capsule(g.0, g.1, 0.05, 0.05, corner: 0.01), with: .color(tint)) }
        if fold > 0.5 { context.fill(u.circle(0.5, 0.5, 0.035 * Ease.outBack((fold - 0.5) / 0.5)), with: .color(clay)) }
    }
}
