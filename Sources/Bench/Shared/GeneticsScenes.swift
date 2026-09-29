// GeneticsScenes.swift
// ScienceStatus — lab scenes from genetics and molecular biology. Each
// draws in a unit square (see `UnitSquare`): DNA and machinery in the
// tint, what is being made, moved or changed in clay.

import SwiftUI

/// A stretch of double-stranded DNA: two strands and their base pairs.
enum Duplex {
    /// Draws strands at `top` and `bottom` from `x0` to `x1`, base pairs
    /// every `spacing` starting from `phase`.
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, from x0: Double, to x1: Double,
                     top: Double, bottom: Double, tint: Color, color: Color? = nil,
                     spacing: Double = 0.08, phase: Double = 0) {
        guard x1 > x0 else { return }
        let ink = color ?? tint
        var x = x0 + (phase - x0).truncatingRemainder(dividingBy: spacing)
        if x < x0 { x += spacing }
        while x < x1 - 0.005 {
            u.stroke(context, u.line((x, top), (x, bottom)), (color ?? tint).opacity(color == nil ? 0.5 : 1), 0.045)
            x += spacing
        }
        u.stroke(context, u.line((x0, top), (x1, top)), ink, 0.055)
        u.stroke(context, u.line((x0, bottom), (x1, bottom)), ink, 0.055)
    }
}

/// A nucleosome: clay DNA feeds in and wraps one and a half turns round
/// the histone core, leaving beside where it came in, and the wrap
/// tightens briefly.
enum Nucleosome {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let squeeze = 1 - 0.07 * sin(.pi * Ease.clamp((t - 2.8) / 0.5))
        let core = Ease.outBack(t / 0.4)
        for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            context.fill(u.circle(0.5 + 0.055 * dx * squeeze, 0.5 + 0.055 * dy * squeeze, 0.075 * core),
                         with: .color(tint))
        }

        // In along the bottom, one and a half turns, out along the top.
        var dna: [(Double, Double)] = [(0.02, 0.69)]
        let turns = 1.5, steps = 90
        for i in 0...steps {
            let s = Double(i) / Double(steps)
            let a = (90 - 360 * turns * s) * .pi / 180
            let r = (0.19 + 0.045 * s) * squeeze
            dna.append((0.5 + r * cos(a), 0.5 + r * sin(a)))
        }
        dna.append((0.02, dna[dna.count - 1].1))
        let fed = Ease.inOut((t - 0.2) / 2.4)
        if fed > 0 { u.stroke(context, u.polyline(dna).trimmedPath(from: 0, to: fed), clay, 0.055) }
    }
}

/// A helicase unzipping DNA: the double strand runs into a small ring,
/// driven by a clay motor going round it, and parts into two strands
/// behind it.
enum Helicase {
    static let duration = 3.6
    private static let ring = 0.44

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let feed = t * 0.12
        Duplex.draw(context, u, from: 0.02, to: ring, top: 0.46, bottom: 0.54, tint: tint, phase: -feed)
        for (y, end) in [(0.46, 0.2), (0.54, 0.8)] {
            var strand = Path()
            strand.move(to: u.pt(ring, y))
            strand.addQuadCurve(to: u.pt(0.98, end), control: u.pt(0.66, y))
            u.stroke(context, strand, tint, 0.055)
        }
        u.stroke(context, u.ellipse(ring, 0.5, 0.13, 0.32), tint, 0.06)
        let a = t * 2 * .pi / 0.9
        context.fill(u.circle(ring + 0.065 * cos(a), 0.5 + 0.16 * sin(a), 0.035), with: .color(clay))
    }
}

/// A CRISPR edit: Cas9, carrying its clay sgRNA (stem-loops showing out of
/// the top), slides along the DNA
/// and stops beside a PAM; the DNA unwinds and the guide pairs with one
/// strand; Cas9 cuts both strands just upstream of the PAM and lets go; a
/// donor template lines up over the break, the gap is filled in by copying
/// it, in clay, and the ends join.
enum CRISPR {
    static let duration = 4.6
    private static let top = 0.58, bottom = 0.66, site = 0.5, pam = (0.585, 0.64)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let slide = Ease.inOut(t / 1.0)
        let open = Ease.inOut((t - 1.05) / 0.45) * (t < 1.75 ? 1 : 0)
        let cut = t >= 1.75
        let part = cut ? 0.05 * Ease.out((t - 1.75) / 0.3) : 0
        let lift = Ease.inOut((t - 2.0) / 0.55)
        let donor = Keyframes.value(t, [(2.45, 0), (2.95, 1), (3.55, 1), (3.95, 0)])
        let fill = Ease.inOut((t - 3.05) / 0.5)

        if !cut {
            // Whole; a bubble opens where the guide pairs, upstream of the PAM.
            func bubble(_ x: Double) -> Double { exp(-pow((x - (site - 0.04)) / 0.075, 2)) * open }
            let xs = Array(stride(from: 0.02, through: 0.98, by: 0.01))
            u.stroke(context, u.polyline(xs.map { ($0, top - 0.07 * bubble($0)) }), tint, 0.05)
            u.stroke(context, u.polyline(xs.map { ($0, bottom + 0.06 * bubble($0)) }), tint, 0.05)
            var x = 0.06
            while x < 0.97 {
                if bubble(x) < 0.3 { u.stroke(context, u.line((x, top), (x, bottom)), tint.opacity(0.5), 0.04) }
                x += 0.08
            }
            // The guide paired along the lower strand inside the bubble.
            if open > 0.05 {
                let guide = xs.filter { abs($0 - (site - 0.04)) < 0.09 }.map { ($0, bottom + 0.06 * bubble($0) - 0.035) }
                u.stroke(context, u.polyline(guide), clay.opacity(open), 0.04)
            }
        } else {
            // Cut through both strands at the same place: blunt ends.
            Duplex.draw(context, u, from: 0.02, to: site - part, top: top, bottom: bottom, tint: tint, phase: 0.06)
            Duplex.draw(context, u, from: site + part, to: 0.98, top: top, bottom: bottom, tint: tint, phase: 0.06)
            // The gap filled from the donor: the edit, in clay.
            if fill > 0 {
                let w = part * fill
                Duplex.draw(context, u, from: site - w, to: site + w, top: top, bottom: bottom, tint: tint,
                            color: clay, spacing: 0.04, phase: site)
            }
        }
        // The PAM, a short raised mark on the upper strand.
        u.stroke(context, u.line((pam.0, top - 0.035), (pam.1, top - 0.035)), tint, 0.045)

        // The cut, and later the joins, as small clay rings.
        for (at, xs) in [(1.75, [site]), (3.6, [site - 0.05, site + 0.05])] {
            let k = (t - at) / 0.4
            guard k > 0, k < 1 else { continue }
            for x in xs { u.stroke(context, u.circle(x, 0.62, 0.04 + 0.06 * k), clay.opacity(1 - k), 0.035) }
        }

        // The donor template: arms that match the DNA either side of the
        // break, the new sequence in clay between them.
        if donor > 0 {
            let y = 0.48 - 0.3 * (1 - donor) - (t > 3.55 ? 0.15 * (1 - donor) : 0)
            var d = context
            d.opacity = donor
            u.stroke(d, u.line((0.3, y), (site - 0.05, y)), tint, 0.045)
            u.stroke(d, u.line((site - 0.05, y), (site + 0.05, y)), clay, 0.045)
            u.stroke(d, u.line((site + 0.05, y), (0.7, y)), tint, 0.045)
        }

        // Cas9 slides in along the DNA, sits over the site, and lifts away.
        if lift < 1 {
            let x = -0.2 + (site - 0.02 + 0.2) * slide
            let y = 0.4 - 0.35 * lift
            var cas = context
            cas.opacity = 1 - lift
            cas.fill(u.capsule(x, y, 0.3, 0.2, corner: 0.08), with: .color(tint))
            // Its sgRNA, in clay: the scaffold's stem-loops out of the top,
            // the spacer along the bottom, reaching down to pair with the
            // target strand once the DNA opens.
            var scaffold = Path()
            scaffold.move(to: u.pt(x - 0.02, y + 0.06))
            scaffold.addLine(to: u.pt(x + 0.08, y + 0.06))
            scaffold.addQuadCurve(to: u.pt(x + 0.13, y - 0.13), control: u.pt(x + 0.2, y - 0.02))
            u.stroke(cas, scaffold, clay, 0.035)
            u.stroke(cas, u.circle(x + 0.12, y - 0.165, 0.035), clay, 0.03)
            u.stroke(cas, u.line((x + 0.02, y - 0.08), (x + 0.02, y - 0.14)), clay, 0.035)
            u.stroke(cas, u.circle(x + 0.02, y - 0.17, 0.03), clay, 0.03)
            if open > 0.05 && lift == 0 {
                u.stroke(cas, u.line((x - 0.02, y + 0.06), (site - 0.04, bottom + 0.06 * open - 0.035)), clay.opacity(open), 0.035)
            }
        }
    }
}

/// DNA repair: a gap in one strand is filled one clay unit at a time, and
/// the two nicks are sealed.
enum DNARepair {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let top = 0.44, bottom = 0.6
        u.stroke(context, u.line((0.04, bottom), (0.96, bottom)), tint, 0.055)
        u.stroke(context, u.line((0.04, top), (0.34, top)), tint, 0.055)
        u.stroke(context, u.line((0.66, top), (0.96, top)), tint, 0.055)
        for x in stride(from: 0.08, through: 0.93, by: 0.08) where x < 0.33 || x > 0.67 {
            u.stroke(context, u.line((x, top), (x, bottom)), tint.opacity(0.5), 0.045)
        }
        for k in 0..<4 {
            let drop = Ease.outBack((t - 0.4 - 0.45 * Double(k)) / 0.35)
            guard drop > 0 else { continue }
            let x0 = 0.34 + 0.08 * Double(k), y = top - 0.28 * (1 - drop)
            u.stroke(context, u.line((x0, y), (x0 + 0.08, y)), clay, 0.055)
            u.stroke(context, u.line((x0 + 0.04, y), (x0 + 0.04, y + bottom - top)), clay, 0.045)
        }
        let seal = (t - 2.4) / 0.5
        if seal > 0, seal < 1 {
            for x in [0.34, 0.66] { u.stroke(context, u.circle(x, top, 0.03 + 0.06 * seal), clay.opacity(1 - seal), 0.04) }
        }
    }
}

/// tRNA charging: the folded cloverleaf, one strand, takes a clay amino
/// acid on its 3′ end, and the charged tRNA sets off.
enum TRNA {
    static let duration = 3.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let go = Ease.inOut((t - 1.7) / 1.1)
        var molecule = context
        molecule.translateBy(x: u.len(0.46 * go), y: -u.len(0.18 * go))
        molecule.opacity = 1 - go
        let cloverleaf = RNAHelix(base: (0.5, 0.2), angle: 90, length: 0.18, branches: [
            RNAHelix(angle: 0, length: 0.13, width: 0.05),
            RNAHelix(angle: 90, length: 0.18, width: 0.05),
            RNAHelix(angle: 180, length: 0.13, width: 0.05),
        ])
        let traced = RNAFold.trace(cloverleaf, t: t)
        RNAFold.draw(molecule, u, traced, color: tint)
        guard let end = traced.points.first else { return }
        let site = (end.0 + 0.02, end.1 - 0.04)
        let land = Ease.out((t - 0.3) / 1.0)
        let arc = (0.12 + (site.0 - 0.12) * land, 0.08 + (site.1 - 0.08) * land - 0.1 * sin(.pi * land))
        let bounce = 0.02 * sin(.pi * Ease.clamp((t - 1.3) / 0.25))
        molecule.fill(u.circle(arc.0, arc.1 - bounce, 0.045), with: .color(clay))
    }
}

/// A restriction digest: an enzyme comes to its clay site on a plasmid and
/// cuts each strand a few bases apart, so when the circle relaxes open into
/// a straight duplex, each end keeps a short single-stranded clay overhang:
/// sticky ends.
enum Digest {
    static let duration = 3.8
    private static let radius = 0.13
    /// How far apart the two strands are cut, as a share of the circle.
    private static let stagger = 0.075

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.inOut((t - 1.4) / 1.2)
        let cut = t >= 1.1
        // Unrolling: the duplex keeps its length while its curve relaxes,
        // a circle, then a C opening upwards, then a straight line. s runs
        // round it from the site at the top (±0.5); the bottom is s = 0.
        let length = 2 * .pi * radius
        let sweep = 2 * .pi * (1 - open)
        let middle = 0.64 - 0.14 * open
        let shift = length * stagger / 2 * open
        func centre(_ s: Double) -> (Double, Double) {
            guard sweep > 0.001 else { return (0.5 + shift + length * s, middle) }
            let r = length / sweep, a = sweep * s
            return (0.5 + shift + r * sin(a), middle - r + r * cos(a))
        }
        /// One strand from `a` to `b` along s, `side` 1 outside, -1 inside.
        func strand(_ a: Double, _ b: Double, side: Double) -> Path {
            u.polyline(stride(from: a, through: b + 0.0001, by: 0.005).map { s in
                let p = centre(s), before = centre(s - 0.002), after = centre(s + 0.002)
                let dx = after.0 - before.0, dy = after.1 - before.1, l = max(hypot(dx, dy), 1e-6)
                return (p.0 - dy / l * 0.024 * side, p.1 + dx / l * 0.024 * side)
            })
        }
        if cut {
            // The outer strand is cut at the site, the inner one `stagger`
            // further round, so each end has one strand running on alone.
            u.stroke(context, strand(-0.5 + stagger, 0.5, side: 1), tint, 0.035)
            u.stroke(context, strand(-0.5 + stagger, 0.5, side: -1), tint, 0.035)
            u.stroke(context, strand(-0.5, -0.5 + stagger, side: 1), clay, 0.035)
            u.stroke(context, strand(0.5, 0.5 + stagger, side: -1), clay, 0.035)
        } else {
            u.stroke(context, strand(-0.5, 0.5, side: 1), tint, 0.035)
            u.stroke(context, strand(-0.5, 0.5, side: -1), tint, 0.035)
            // The recognition site, both strands.
            u.stroke(context, strand(0.5 - stagger / 2, 0.5 + stagger / 2, side: 1), clay, 0.035)
            u.stroke(context, strand(0.5 - stagger / 2, 0.5 + stagger / 2, side: -1), clay, 0.035)
        }

        // The enzyme comes to the site, cuts, and leaves.
        let siteY = 0.64 - 2 * radius
        let come = Ease.out((t - 0.2) / 0.8)
        let leave = Ease.inOut((t - 1.2) / 0.5)
        if leave < 1 {
            let at = (0.82 - (0.82 - 0.5) * come + 0.3 * leave, 0.1 + (siteY - 0.1 - 0.075) * come - 0.2 * leave)
            context.fill(u.circle(at.0, at.1, 0.06), with: .color(tint.opacity(1 - leave)))
        }
        let snip = (t - 1.1) / 0.4
        if snip > 0, snip < 1 {
            u.stroke(context, u.circle(0.5, siteY, 0.03 + 0.05 * snip), clay.opacity(1 - snip), 0.04)
        }
    }
}

/// A virus-like particle assembling itself: six triangular capsid pieces
/// fly in, clay while they travel, settle into place one after another,
/// and the finished shell gives a small pulse.
enum VLP {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let corners = (0..<6).map { k -> (Double, Double) in
            let a = (Double(k) * 60 - 90) * .pi / 180
            return (0.5 + 0.3 * cos(a), 0.5 + 0.3 * sin(a))
        }
        let done = sin(.pi * Ease.clamp((t - 2.4) / 0.4))
        for k in 0..<6 {
            let a = corners[k], b = corners[(k + 1) % 6]
            let centroid = ((0.5 + a.0 + b.0) / 3, (0.5 + a.1 + b.1) / 3)
            let piece = [(0.5, 0.5), a, b].map { (centroid.0 + ($0.0 - centroid.0) * 0.86,
                                                  centroid.1 + ($0.1 - centroid.1) * 0.86) }
            let arrive = Ease.outBack((t - 0.2 - 0.32 * Double(k)) / 0.5)
            let docked = Ease.clamp((t - 0.55 - 0.32 * Double(k)) / 0.15)
            let out = (centroid.0 - 0.5, centroid.1 - 0.5)
            let away = 1 - arrive
            let grow = 1 + 0.06 * done
            var p = context
            let c = u.pt(0.5 + (centroid.0 - 0.5) * grow + out.0 * 3 * away,
                         0.5 + (centroid.1 - 0.5) * grow + out.1 * 3 * away)
            p.translateBy(x: c.x, y: c.y)
            p.rotate(by: .degrees(120 * away))
            var shape = Path()
            shape.addLines(piece.map { CGPoint(x: u.len($0.0 - centroid.0), y: u.len($0.1 - centroid.1)) })
            shape.closeSubpath()
            if docked < 1 { p.fill(shape, with: .color(clay.opacity(1 - docked))) }
            if docked > 0 { p.fill(shape, with: .color(tint.opacity(docked))) }
        }
        let ring = (t - 2.4) / 0.6
        if ring > 0, ring < 1 {
            u.stroke(context, u.circle(0.5, 0.5, 0.34 + 0.1 * ring), clay.opacity(1 - ring), 0.04)
        }
    }
}
