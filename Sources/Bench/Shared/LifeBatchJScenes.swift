// LifeBatchJScenes.swift
// ScienceStatus — more of what goes on in a cell: proteins made and folded
// in the ER, mRNA finished and sent out, chromatin opening, and two agents
// of disease and of the lab. Each draws in a unit square (see
// `UnitSquare`): membranes and machinery in the tint, the molecule the
// scene is about in clay.

import SwiftUI

/// A disulfide bond forming in the ER: a new chain wriggles in the lumen,
/// two of its clay cysteines far apart; PDI comes and holds them together,
/// the bond forms between them, and PDI lets go of a folded protein.
enum DisulfideBond {
    static let duration = 4.4
    private static let count = 13
    private static let cysteines = (3, 9)

    /// The fold: a loop closed by the bond, the chain's ends trailing off.
    private static let folded: [(Double, Double)] = (0..<count).map { i -> (Double, Double) in
        switch i {
        case 0..<3: return (0.2 + 0.085 * Double(i), 0.74 - 0.06 * Double(i))
        case 3...9:
            let a = (110 + 320 * Double(i - 3) / 6) * .pi / 180
            return (0.5 + 0.15 * cos(a), 0.42 + 0.15 * sin(a))
        default: return (0.64 + 0.085 * Double(i - 10), 0.62 + 0.06 * Double(i - 10))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for y in [0.1, 0.9] { u.stroke(context, u.line((0.02, y), (0.98, y)), tint.opacity(0.35), 0.03) }
        let fold = Ease.inOut((t - 1.3) / 1.0)
        let pdi = Keyframes.value(t, [(0.5, 0), (1.2, 1), (2.7, 1), (3.3, 0)])
        let bonded = Ease.out((t - 2.2) / 0.3)
        let points = (0..<count).map { i -> (Double, Double) in
            let s = Double(i)
            let open = (0.1 + 0.8 * s / Double(count - 1), 0.5 + 0.09 * sin(s * 1.1 + t * 2.6))
            let f = folded[i]
            let wobble = 0.006 * sin(t * 5 + s) * fold
            return (open.0 + (f.0 - open.0) * fold + wobble, open.1 + (f.1 - open.1) * fold)
        }
        // PDI slides in from the right, sits under the pair, and leaves.
        if pdi > 0 {
            let x = 1.15 + (0.5 - 1.15) * pdi
            context.fill(u.capsule(x, 0.66, 0.22, 0.09, corner: 0.045), with: .color(tint.opacity(0.75)))
        }
        u.stroke(context, u.polyline(Smooth.curve(points, samples: 4)), tint, 0.035)
        let a = points[cysteines.0], b = points[cysteines.1]
        if bonded > 0 {
            let mid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
            u.stroke(context, u.line((mid.0 + (a.0 - mid.0) * bonded, mid.1 + (a.1 - mid.1) * bonded),
                                     (mid.0 + (b.0 - mid.0) * bonded, mid.1 + (b.1 - mid.1) * bonded)), clay, 0.035)
        }
        for p in [a, b] { context.fill(u.circle(p.0, p.1, 0.032), with: .color(clay)) }
    }
}

/// Rough ER: ribosomes stud the ER membrane, strung along one mRNA; each
/// threads its growing clay chain through the membrane into the lumen,
/// where finished proteins fold up and float away.
enum RoughER {
    static let duration = 4.8
    private static let ribosomes = [0.2, 0.5, 0.8]
    private static let membrane = 0.5

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, membrane + 0.06).y, width: u.side, height: u.len(0.44))), with: .color(tint.opacity(0.07)))
        // The membrane, a gap at each ribosome where its chain goes through.
        for y in [membrane, membrane + 0.06] {
            var x = 0.0
            for r in ribosomes + [1.1] {
                u.stroke(context, u.line((x, y), (min(1, r - 0.025), y)), tint, 0.03)
                x = r + 0.025
            }
        }
        // The mRNA running through them, flowing as they read it.
        context.stroke(u.line((0.0, 0.33), (1.0, 0.33)), with: .color(tint.opacity(0.8)),
                       style: StrokeStyle(lineWidth: max(u.len(0.02), UnitSquare.hairline), lineCap: .round,
                                          dash: [u.len(0.05), u.len(0.02)], dashPhase: u.len(t * 0.2)))
        for (k, x) in ribosomes.enumerated() {
            let phase = (t / 2.4 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1)
            // The chain: down through the membrane, then coiling in the lumen.
            let chain = (0...30).map { i -> (Double, Double) in
                let s = Double(i) / 30
                if s < 0.35 { return (x, 0.43 + 0.2 * s / 0.35) }
                let c = (s - 0.35) / 0.65
                return (x + 0.05 * sin(c * 9), 0.63 + 0.18 * c)
            }
            u.stroke(context, u.polyline(chain).trimmedPath(from: 0, to: 0.12 + 0.88 * phase), clay, 0.03)
            // The one it just finished, folded, floating off.
            if phase < 0.35 {
                let f = phase / 0.35
                context.fill(u.circle(x + 0.06 * f, 0.84 + 0.08 * f, 0.035), with: .color(clay.opacity(1 - f)))
            }
            context.fill(u.capsule(x, 0.39, 0.17, 0.1, corner: 0.05), with: .color(tint))
            context.fill(u.capsule(x, 0.28, 0.12, 0.07, corner: 0.035), with: .color(tint.opacity(0.65)))
        }
    }
}

/// mRNA export: a finished mRNA, clay cap leading and its poly(A) tail
/// trailing, winds through the nucleus to a pore, threads out through it cap
/// first, and in the cytoplasm a ribosome takes hold of the cap.
enum MRNAExport {
    static let duration = 4.6
    /// The way out, resampled once into evenly spaced points so finding a
    /// place along it is a lookup, not a walk.
    private static let route: [(Double, Double)] = {
        let curve = Smooth.curve([(0.04, 0.84), (0.18, 0.72), (0.12, 0.56), (0.28, 0.46), (0.42, 0.5),
                                  (0.5, 0.5), (0.6, 0.5), (0.72, 0.42), (0.86, 0.36), (0.97, 0.3)], samples: 8)
        return (0...400).map { Polyline.point(curve, at: Double($0) / 400) }
    }()
    private static let length = 0.42

    private static func along(_ f: Double) -> (Double, Double) {
        route[Int((max(0, min(1, f)) * 400).rounded())]
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.len(0.47), height: u.side)), with: .color(tint.opacity(0.07)))
        // The envelope: two membranes, broken by the pore and its rim.
        for x in [0.47, 0.53] {
            u.stroke(context, u.line((x, 0.02), (x, 0.43)), tint, 0.03)
            u.stroke(context, u.line((x, 0.57), (x, 0.98)), tint, 0.03)
        }
        for y in [0.42, 0.58] { context.fill(u.capsule(0.5, y, 0.13, 0.05, corner: 0.02), with: .color(tint)) }

        let head = 0.44 + (1 - length - 0.44 + 0.38) * Ease.inOut((t - 0.4) / 3.0)
        let from = max(0, head - length), to = min(1, head)
        let strand = stride(from: from, through: to, by: 0.01).map(along)
        u.stroke(context, u.polyline(strand), tint, 0.03)
        // The poly(A) tail at the back, A by A.
        for k in 0..<5 {
            let p = along(from + 0.012 * Double(k))
            context.fill(u.circle(p.0, p.1, 0.014), with: .color(clay))
        }
        let cap = along(to)
        context.fill(u.circle(cap.0, cap.1, 0.032), with: .color(clay))
        // Out in the cytoplasm a ribosome finds the cap.
        let find = Ease.inOut((t - 3.5) / 0.6)
        if find > 0 {
            let at = (cap.0 + (0.95 - cap.0) * (1 - find), cap.1 - 0.07 + (0.08 - cap.1 + 0.07) * (1 - find))
            context.fill(u.capsule(at.0, at.1, 0.14, 0.08, corner: 0.04), with: .color(tint))
            context.fill(u.capsule(at.0, at.1 + 0.065, 0.1, 0.05, corner: 0.025), with: .color(tint.opacity(0.65)))
        }
    }
}

/// 5′ capping: RNA polymerase II runs along the DNA, the new RNA spooling out
/// behind it; while the RNA is still short the capping enzyme meets its 5′
/// end and a clay cap snaps on, joined back to front by its three
/// phosphates; the enzyme leaves and the capped RNA keeps growing.
enum FivePrimeCap {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for y in [0.8, 0.86] { u.stroke(context, u.line((0.0, y), (1.0, y)), tint.opacity(0.6), 0.028) }
        let x = 0.26 + 0.12 * t
        // The RNA from the polymerase's exit, up and back to its 5′ end.
        let length = 0.14 + 0.1 * t
        let exit = (x - 0.03, 0.72)
        let rna = stride(from: 0.0, through: length, by: 0.01).map { s -> (Double, Double) in
            (exit.0 - 0.55 * s - 0.02 * sin(s * 30), exit.1 - 0.75 * s)
        }
        u.stroke(context, u.polyline(rna), tint, 0.03)
        let end = rna[rna.count - 1]
        context.fill(u.capsule(x, 0.77, 0.2, 0.15, corner: 0.06), with: .color(tint))
        // The capping enzyme comes to the 5′ end while it's short, then goes.
        let enzyme = Keyframes.value(t, [(0.4, 0), (1.1, 1), (1.9, 1), (2.5, 0)])
        if enzyme > 0 {
            context.fill(u.capsule(end.0 - 0.04 - 0.4 * (1 - enzyme), end.1 + 0.02, 0.12, 0.09, corner: 0.04),
                         with: .color(tint.opacity(0.7 * enzyme)))
        }
        let cap = Ease.outBack((t - 1.4) / 0.35)
        if cap > 0 {
            let dir = (-0.55, -0.75), n = hypot(dir.0, dir.1)
            let c = (end.0 + dir.0 / n * 0.07, end.1 + dir.1 / n * 0.07)
            for k in 1...3 {
                let f = Double(k) / 4
                context.fill(u.circle(end.0 + (c.0 - end.0) * f, end.1 + (c.1 - end.1) * f, 0.01 * min(1, cap)), with: .color(tint))
            }
            context.fill(u.circle(c.0, c.1, 0.035 * cap), with: .color(clay))
        }
    }
}

/// The 3′ poly(A) tail: a capped pre-mRNA runs on past its
/// polyadenylation signal; it's cut just downstream, the spare end drifts
/// away, and poly(A) polymerase adds A after A in clay, the tail growing
/// long before the polymerase lets go.
enum PolyATail {
    static let duration = 4.6
    private static let cut = 0.5, y = 0.5, step = 0.034

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.08, y), (cut, y)), tint, 0.03)
        context.fill(u.circle(0.06, y, 0.03), with: .color(clay))
        // The signal: a stretch marked just upstream of the cut.
        for k in 0..<3 { u.stroke(context, u.line((0.37 + 0.03 * Double(k), y - 0.05), (0.37 + 0.03 * Double(k), y - 0.025)), tint, 0.02) }
        // The spare end, cut off and drifting away.
        let away = Ease.inOut((t - 1.0) / 0.8)
        if away < 1 {
            let dx = 0.12 * away, dy = 0.2 * away
            u.stroke(context, u.line((cut + 0.02 + dx, y + dy), (0.86 + dx, y + dy + 0.02 * away)), tint.opacity(1 - away), 0.03)
        }
        let snip = (t - 0.85) / 0.35
        if snip > 0, snip < 1 { u.stroke(context, u.circle(cut + 0.01, y, 0.03 + 0.05 * snip), clay.opacity(1 - snip), 0.025) }
        // The tail, A by A, and the polymerase at its end.
        let added = min(12, max(0, Int((t - 1.4) / 0.19)))
        for k in 0..<added {
            context.fill(u.circle(cut + 0.03 + step * Double(k), y, 0.016), with: .color(clay))
        }
        let leave = Ease.inOut((t - 3.9) / 0.4)
        if t > 1.2, leave < 1 {
            let x = cut + 0.03 + step * Double(added) + 0.03
            context.fill(u.capsule(x, y - 0.3 * leave, 0.1, 0.12, corner: 0.04), with: .color(tint.opacity(1 - leave)))
        }
    }
}

/// Chromatin opening and closing: nucleosomes on their DNA, loose like
/// beads on a string, pack into a tight zigzag fibre; then clay marks
/// appear on them and the fibre loosens open again.
enum ChromatinBreathing {
    static let duration = 5.0
    private static let count = 9

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let packed = Ease.inOut((t - 0.5) / 1.1) * (1 - Ease.inOut((t - 3.2) / 1.1))
        let marked = Ease.outBack((t - 2.6) / 0.4) * (1 - Ease.inOut((t - 4.5) / 0.4))
        let beads = (0..<count).map { k -> (Double, Double) in
            let s = Double(k)
            let open = (0.1 + 0.1 * s, 0.5 + 0.13 * sin(s * 1.3 + 0.4))
            let tight = (0.5 + (k % 2 == 0 ? -0.055 : 0.055), 0.28 + 0.055 * s)
            return (open.0 + (tight.0 - open.0) * packed, open.1 + (tight.1 - open.1) * packed)
        }
        // The DNA: in from one side, through every bead, out the other.
        let first = beads[0], last = beads[count - 1]
        let ends = [(first.0 - 0.1 * (1 - packed) - 0.02, first.1 - 0.1 * packed)] + beads + [(last.0 + 0.1 * (1 - packed) + 0.02, last.1 + 0.1 * packed)]
        u.stroke(context, u.polyline(Smooth.curve(ends, samples: 5)), tint.opacity(0.7), 0.022)
        for p in beads {
            context.fill(u.circle(p.0, p.1, 0.042), with: .color(tint))
            if marked > 0 { context.fill(u.circle(p.0 + 0.035, p.1 - 0.035, 0.016 * marked), with: .color(clay)) }
        }
    }
}

/// Prion disease, a protein misfolding: normal prion protein, a tint coil
/// (its α-helix), meets the fibril of the misfolded form and refolds on
/// contact into a clay zigzag (a β-strand), stacking onto the fibril's end;
/// the fibril breaks in two, and each piece goes on converting.
enum Prion {
    static let duration = 5.0
    /// Each normal protein: where it comes from, where it joins, and when.
    private static let joins: [(from: (Double, Double), at: Double, slot: Int)] = [
        ((0.9, 0.2), 0.6, 1), ((0.1, 0.25), 1.1, -1), ((0.88, 0.82), 1.6, 2), ((0.12, 0.8), 2.1, -2),
        ((0.1, 0.1), 3.4, 10), ((0.92, 0.92), 3.8, 11),
    ]
    private static let gap = 0.068

    /// Where a slab of the fibril sits: its place along it, shifted apart
    /// once the fibril breaks.
    private static func slab(_ slot: Int, broken: Double) -> (Double, Double) {
        switch slot {
        case 10: return (0.534 - 0.14 * broken, 0.5 - 0.14 * broken)
        case 11: return (0.466 + 0.14 * broken, 0.5 + 0.14 * broken)
        default:
            let x = 0.5 + gap * (Double(slot) - 0.5)
            let side = slot <= 0 ? -1.0 : 1.0
            return (x + side * 0.14 * broken, 0.5 + side * 0.14 * broken)
        }
    }

    /// One protein, drawn by its fold: the normal one a tint coil, the
    /// α-helix; as `m` runs to 1 it refolds into the prion's clay zigzag,
    /// a β-strand that stacks with the others into the fibril.
    private static func protein(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), misfold m: Double, tint: Color) {
        let n = 24
        let points = (0...n).map { i -> (Double, Double) in
            let s = Double(i) / Double(n)
            let y = p.1 - 0.075 + 0.15 * s
            let a = 2 * .pi * 3 * s
            let coil = (p.0 + 0.032 * sin(a), y + 0.016 * cos(a))
            let x = 3 * s
            let zig = (p.0 + 0.026 * (2 * abs(2 * (x - (x + 0.5).rounded(.down))) - 1), y)
            return (coil.0 + (zig.0 - coil.0) * m, coil.1 + (zig.1 - coil.1) * m)
        }
        if m < 1 { u.stroke(context, u.polyline(points), tint.opacity(1 - m), 0.028) }
        if m > 0 { u.stroke(context, u.polyline(points), clay.opacity(m), 0.028) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let broken = Ease.inOut((t - 2.7) / 0.5)
        let snap = (t - 2.7) / 0.4
        if snap > 0, snap < 1 { u.stroke(context, u.circle(0.5, 0.5, 0.04 + 0.06 * snap), clay.opacity(1 - snap), 0.025) }
        for seed in [0, 1] {
            protein(context, u, at: slab(seed, broken: broken), misfold: 1, tint: tint)
        }
        for j in joins {
            let come = Ease.inOut((t - j.at) / 0.5)
            guard come > 0 else { continue }
            let to = slab(j.slot, broken: broken)
            let p = (j.from.0 + (to.0 - j.from.0) * come, j.from.1 + (to.1 - j.from.1) * come)
            protein(context, u, at: p, misfold: Ease.inOut((t - j.at - 0.4) / 0.25), tint: tint)
        }
    }
}

/// Lentivirus production: three plasmids go into a packaging cell, the
/// transfer plasmid carrying the gene in clay; the cell makes the virus's
/// parts, and particles bud from its surface, each studded with envelope
/// spikes around a clay genome, and drift off into the medium to be
/// collected.
enum Lentivirus {
    static let duration = 5.2
    private static let cell = (centre: (0.5, 0.7), radius: 0.3)
    private static let plasmids: [(from: (Double, Double), to: (Double, Double), gene: Bool)] = [
        ((0.2, 0.08), (0.43, 0.72), false), ((0.5, 0.04), (0.5, 0.66), true), ((0.8, 0.08), (0.57, 0.72), false),
    ]
    private static let buds: [(angle: Double, at: Double)] = [(-120, 2.0), (-70, 2.7), (-95, 3.4)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(cell.centre.0, cell.centre.1, cell.radius), tint, 0.035)
        context.fill(u.circle(0.5, 0.74, 0.1), with: .color(tint.opacity(0.18)))
        // Transfection: the plasmids come in and go to the nucleus.
        for p in plasmids {
            let go = Ease.inOut((t - 0.2) / 1.0)
            let gone = Ease.inOut((t - 1.3) / 0.4)
            guard gone < 1 else { continue }
            let at = (p.from.0 + (p.to.0 - p.from.0) * go, p.from.1 + (p.to.1 - p.from.1) * go)
            u.stroke(context, u.circle(at.0, at.1, 0.045 * (1 - 0.5 * gone)), (p.gene ? clay : tint).opacity(1 - gone), 0.025)
        }
        // Expression: the virus's parts gather where each particle will bud.
        for bud in buds {
            let a = bud.angle * .pi / 180
            let rim = (cell.centre.0 + cell.radius * cos(a), cell.centre.1 + cell.radius * sin(a))
            let gather = Ease.inOut((t - 1.4) / 0.6)
            let out = Ease.inOut((t - bud.at) / 0.8)
            let drift = Ease.inOut((t - bud.at - 0.8) / 1.2)
            if out == 0 {
                for k in 0..<4 {
                    let s = Double(k)
                    let start = (0.5 + 0.12 * cos(s * 1.7), 0.72 + 0.08 * sin(s * 2.3))
                    let end = (rim.0 - 0.06 * cos(a) + 0.03 * cos(s * 2), rim.1 - 0.06 * sin(a) + 0.03 * sin(s * 2))
                    context.fill(u.circle(start.0 + (end.0 - start.0) * gather, start.1 + (end.1 - start.1) * gather, 0.012),
                                 with: .color(tint.opacity(gather)))
                }
                continue
            }
            let reach = cell.radius - 0.02 + 0.12 * out
            let c = (cell.centre.0 + reach * cos(a) + 0.08 * drift * cos(a), cell.centre.1 + reach * sin(a) - 0.25 * drift)
            let fade = 1 - Ease.clamp((t - bud.at - 1.6) / 0.4)
            guard fade > 0 else { continue }
            var particle = context
            particle.opacity = fade
            u.stroke(particle, u.circle(c.0, c.1, 0.06), tint, 0.025)
            for k in 0..<8 {
                let b = Double(k) * .pi / 4
                u.stroke(particle, u.line((c.0 + 0.06 * cos(b), c.1 + 0.06 * sin(b)), (c.0 + 0.085 * cos(b), c.1 + 0.085 * sin(b))), tint, 0.02)
            }
            for dy in [-0.015, 0.015] { u.stroke(particle, u.line((c.0 - 0.025, c.1 + dy), (c.0 + 0.025, c.1 + dy)), clay, 0.018) }
        }
    }
}
