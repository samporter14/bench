// BioinformaticsScenes.swift
// ScienceStatus — lab scenes of sequence analysis and computational
// biology. Each draws in a unit square (see `UnitSquare`): sequences and
// structure in the tint, matches and answers in clay.

import SwiftUI

/// One residue or base as a small rounded square.
private func cell(_ u: UnitSquare, _ x: Double, _ y: Double, _ w: Double = 0.07, _ h: Double = 0.07) -> Path {
    u.capsule(x, y, w, h, corner: 0.015)
}

/// A multiple sequence alignment: rows slide sideways until their
/// conserved clay positions stack into one column, which pulses.
enum Alignment {
    static let duration = 3.6
    private static let rows: [(start: Double, length: Int, conserved: Int)] = [
        (0.12, 7, 4), (0.2, 6, 3), (0.04, 8, 5), (0.28, 5, 2), (0.12, 7, 4),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let align = Ease.inOut((t - 0.4) / 1.6)
        let pulse = sin(.pi * Ease.clamp((t - 2.3) / 0.5))
        let column = 0.12 + 0.09 * 4
        for (r, row) in rows.enumerated() {
            let y = 0.2 + 0.15 * Double(r)
            let aligned = column - 0.09 * Double(row.conserved)
            let jitter = [0.1, -0.12, 0.14, -0.08, 0.06][r]
            let x0 = aligned + jitter * (1 - align)
            for i in 0..<row.length {
                let x = x0 + 0.09 * Double(i)
                let conserved = i == row.conserved
                let grow = conserved ? 1 + 0.25 * pulse : 1
                context.fill(cell(u, x, y, 0.07 * grow, 0.07 * grow), with: .color(conserved ? clay : tint.opacity(0.5)))
            }
        }
    }
}

/// A homology search, the way BLAST shows it: a short query hops down a
/// stack of sequences, pausing just above each; match bars join the
/// positions that agree, both lit in clay, and one full match locks.
enum HomologySearch {
    static let duration = 3.8
    private static let hits: [[Bool]] = [
        [false, true, false, false], [false, false, false, false], [true, false, true, false],
        [false, false, false, true], [true, true, true, true],
    ]
    private static let rows = (0..<5).map { 0.3 + 0.15 * Double($0) }
    private static let lift = 0.095

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var frames: [(Double, Double)] = [(0, 0.12)]
        for (r, y) in rows.enumerated() {
            let at = 0.3 + 0.55 * Double(r)
            frames += [(at, y - lift), (at + 0.3, y - lift)]
        }
        let y = Keyframes.value(t, frames)
        let row = rows.firstIndex { abs($0 - lift - y) < 0.003 }
        for (r, rowY) in rows.enumerated() {
            for i in 0..<9 {
                let q = i - 3
                let lit = row == r && q >= 0 && q < 4 && hits[r][q]
                context.fill(cell(u, 0.12 + 0.095 * Double(i), rowY, 0.07, 0.055), with: .color(lit ? clay : tint.opacity(0.3)))
            }
        }
        for i in 0..<4 {
            let x = 0.12 + 0.095 * Double(i + 3)
            let match = row.map { hits[$0][i] } ?? false
            context.fill(cell(u, x, y, 0.07, 0.055), with: .color(match ? clay : tint))
            if match { u.stroke(context, u.line((x, y + 0.036), (x, y + lift - 0.036)), tint, 0.025) }
        }
    }
}

/// Read mapping: short reads drift down to the reference and snap into
/// place, stacking up, while clay coverage rises beneath from left to right.
enum ReadMapping {
    static let duration = 4.0
    private static let reads: [(x: Double, row: Int)] = [
        (0.1, 0), (0.28, 0), (0.46, 0), (0.64, 0), (0.2, 1), (0.38, 1), (0.56, 1), (0.74, 1), (0.3, 2), (0.5, 2),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reference = 0.66
        u.stroke(context, u.line((0.06, reference), (0.94, reference)), tint)
        for (k, read) in reads.enumerated() {
            let land = Ease.outBack((t - 0.3 - 0.25 * Double(k)) / 0.4)
            guard land > 0 else { continue }
            let target = (read.x + 0.08, reference - 0.07 - 0.07 * Double(read.row))
            let from = (read.x + 0.08 + 0.1 * sin(Double(k) * 2.3), 0.02)
            let p = (from.0 + (target.0 - from.0) * land, from.1 + (target.1 - from.1) * land)
            context.fill(u.capsule(p.0, p.1, 0.16, 0.035, corner: 0.017), with: .color(tint))
        }
        // Coverage: how many reads cover each point, as it builds.
        for x in stride(from: 0.08, through: 0.92, by: 0.02) {
            var depth = 0.0
            for (k, read) in reads.enumerated() where x >= read.x && x <= read.x + 0.16 {
                depth += Ease.clamp((t - 0.6 - 0.25 * Double(k)) / 0.3)
            }
            if depth > 0 { u.stroke(context, u.line((x, reference + 0.05), (x, reference + 0.05 + 0.045 * depth)), clay, 0.018) }
        }
    }
}

/// Variant calling: reads pile up under the reference; in one column the
/// same clay base keeps turning up, and the variant is called above it.
enum VariantCalling {
    static let duration = 4.0
    private static let columns = 9
    private static let reads: [(start: Int, end: Int, variant: Bool)] = [
        (0, 5, true), (2, 8, false), (1, 7, true), (3, 8, true), (0, 4, false), (2, 6, true),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let variant = 4
        func x(_ i: Int) -> Double { 0.12 + 0.095 * Double(i) }
        for i in 0..<columns { context.fill(cell(u, x(i), 0.24), with: .color(tint)) }
        for (r, read) in reads.enumerated() {
            let appear = Ease.out((t - 0.3 - 0.3 * Double(r)) / 0.3)
            guard appear > 0 else { continue }
            let y = 0.4 + 0.09 * Double(r)
            for i in read.start...read.end {
                let alt = read.variant && i == variant
                context.fill(cell(u, x(i), y, 0.07, 0.05), with: .color(alt ? clay.opacity(appear) : tint.opacity(0.35 * appear)))
            }
        }
        let call = Ease.outBack((t - 2.4) / 0.4)
        if call > 0 {
            var mark = u.line((x(variant) - 0.04, 0.08), (x(variant) + 0.04, 0.08), (x(variant), 0.14))
            mark.closeSubpath()
            context.fill(mark, with: .color(clay.opacity(min(1, call))))
            u.stroke(context, u.capsule(x(variant), 0.56, 0.1, 0.72, corner: 0.03), clay.opacity(0.6 * min(1, call)), 0.025)
        }
    }
}

/// Genome assembly: fragments shuffle, find their overlapping ends and
/// line up into one contig, joined in clay; it rolls on and comes apart.
enum Assembly {
    static let duration = 4.0
    private static let count = 5

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let join = Ease.inOut((t - 0.8) / 1.2) * (1 - Ease.inOut((t - 3.2) / 0.6))
        let roll = 0.04 * Ease.inOut((t - 2.2) / 0.8)
        for k in 0..<count {
            let s = Double(k)
            let loose = (0.2 + 0.6 * abs(sin(s * 2.1 + 0.4)), 0.2 + 0.6 * abs(cos(s * 1.7 + 0.2 * sin(t + s))))
            let placed = (0.14 + 0.18 * s + roll, 0.5 + (k % 2 == 0 ? -0.025 : 0.025) * (1 - Ease.clamp((join - 0.8) / 0.2)))
            let p = (loose.0 + (placed.0 - loose.0) * join, loose.1 + (placed.1 - loose.1) * join)
            context.fill(u.capsule(p.0, p.1, 0.22, 0.04, corner: 0.02), with: .color(tint))
            if k > 0, join > 0.9 {
                context.fill(u.circle(0.14 + 0.18 * s - 0.09 + roll, 0.5, 0.022), with: .color(clay.opacity((join - 0.9) / 0.1)))
            }
        }
    }
}

/// Nanopore basecalling: the strand feeds through the pore while the
/// current squiggle runs beneath it, each step resolving into one of four
/// clay base shapes.
enum Basecalling {
    static let duration = 4.0
    private static let levels = [0.66, 0.6, 0.7, 0.62, 0.72, 0.58, 0.68, 0.64]
    private static let bases = [0, 2, 1, 3, 2, 0, 3, 1]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.3), (0.42, 0.3)), tint)
        u.stroke(context, u.line((0.58, 0.3), (0.96, 0.3)), tint)
        u.stroke(context, u.ellipse(0.5, 0.3, 0.16, 0.08), tint, 0.05)
        let feed = t * 0.08
        u.stroke(context, u.polyline(stride(from: 0.02, through: 0.3, by: 0.02).map { y in
            (0.5 + 0.06 * sin(y * 30 + feed * 60) * (0.3 - y) / 0.3, y) }), clay, 0.045)
        u.stroke(context, u.line((0.5, 0.3), (0.5, 0.42)), clay, 0.045)

        // The squiggle: a step for each base, drawn as it is read.
        let shown = Ease.clamp((t - 0.3) / 3.0) * Double(levels.count)
        var trace: [(Double, Double)] = []
        for (i, level) in levels.enumerated() where Double(i) < shown {
            let x0 = 0.08 + 0.105 * Double(i)
            let x1 = x0 + 0.105 * min(1, shown - Double(i))
            trace.append((x0, level))
            trace.append((x1, level + 0.015 * sin(Double(i) * 3)))
        }
        if trace.count > 1 { u.stroke(context, u.polyline(trace), tint, 0.035) }
        for (i, base) in bases.enumerated() {
            let pop = Ease.outBack(shown - Double(i) - 0.6)
            guard pop > 0 else { continue }
            let p = (0.08 + 0.105 * Double(i) + 0.052, 0.86)
            let r = 0.026 * min(1, pop)
            switch base {
            case 0: context.fill(u.circle(p.0, p.1, r), with: .color(clay))
            case 1: context.fill(u.capsule(p.0, p.1, 2 * r, 2 * r, corner: 0.004), with: .color(clay))
            case 2:
                var tri = u.line((p.0, p.1 - r * 1.2), (p.0 + r * 1.1, p.1 + r * 0.8), (p.0 - r * 1.1, p.1 + r * 0.8))
                tri.closeSubpath()
                context.fill(tri, with: .color(clay))
            default:
                var diamond = u.line((p.0, p.1 - r * 1.3), (p.0 + r * 1.1, p.1), (p.0, p.1 + r * 1.3), (p.0 - r * 1.1, p.1))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(clay))
            }
        }
    }
}

/// Single-cell clustering: an even cloud of cells gathers into three
/// compact clusters that breathe, one of them the clay population.
enum SingleCell {
    static let duration = 3.6
    private static let centres = [(0.3, 0.32), (0.7, 0.36), (0.48, 0.72)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let gather = Ease.inOut((t - 0.4) / 1.4)
        for i in 0..<30 {
            let s = Double(i)
            let cluster = i % 3
            let c = centres[cluster]
            let breathe = 1 + 0.06 * sin(t * 3 + Double(cluster) * 2)
            let spot = (c.0 + 0.09 * breathe * cos(s * 2.4) * sqrt(s / 30 + 0.2),
                        c.1 + 0.09 * breathe * sin(s * 2.4) * sqrt(s / 30 + 0.2))
            let even = (0.12 + 0.76 * (Double(i % 6) + 0.5) / 6 + 0.03 * sin(s), 0.14 + 0.72 * (Double(i / 6) + 0.5) / 5)
            let p = (even.0 + (spot.0 - even.0) * gather, even.1 + (spot.1 - even.1) * gather)
            let highlighted = cluster == 2 && gather > 0.5
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(highlighted ? clay : tint))
        }
    }
}

/// Phylogenetic inference: from a clay ancestor the tree grows out to its
/// leaves; two pairs swap places until the best-supported shape settles,
/// and that clade turns clay.
enum Phylogeny {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let grow = Ease.inOut((t - 0.3) / 1.2)
        let swap = Ease.inOut((t - 1.8) / 0.7)
        var leaves = [0.16, 0.32, 0.5, 0.68, 0.84]
        (leaves[1], leaves[2]) = (leaves[1] + (0.5 - 0.32) * swap, leaves[2] + (0.32 - 0.5) * swap)
        let clade = Ease.clamp((t - 2.7) / 0.4)
        // Rectangular tree: root, two inner nodes, leaves.
        let root = (0.1, 0.5)
        let upper = (0.36, (leaves[0] + leaves[1] + leaves[2]) / 3)
        let lower = (0.5, (leaves[3] + leaves[4]) / 2)
        var branches: [((Double, Double), (Double, Double), Bool)] = [
            ((root.0, upper.1), (upper.0, upper.1), false), ((root.0, lower.1), (lower.0, lower.1), true),
            ((root.0, upper.1), (root.0, lower.1), false),
        ]
        for (i, y) in leaves.enumerated() {
            let node = i < 3 ? upper : lower
            branches.append(((node.0, y), (0.86, y), i >= 3))
            branches.append(((node.0, node.1), (node.0, y), i >= 3))
        }
        for (a, b, inClade) in branches {
            let end = (a.0 + (b.0 - a.0) * grow, a.1 + (b.1 - a.1) * grow)
            u.stroke(context, u.line(a, end), (inClade && clade > 0) ? clay.opacity(0.4 + 0.6 * clade) : tint, 0.04)
        }
        context.fill(u.capsule(root.0 - 0.02, root.1, 0.06, 0.1, corner: 0.02), with: .color(clay))
        if grow >= 1 {
            for y in leaves { context.fill(u.circle(0.88, y, 0.026), with: .color(tint)) }
        }
    }
}
