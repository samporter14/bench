// BioinformaticsTwoScenes.swift
// ScienceStatus — more sequence analysis and genomics, and the fluorescent
// protein. Each draws in a unit square (see `UnitSquare`): data and
// structure in the tint, the answer in clay.

import SwiftUI

/// De Bruijn graph untangling: a tangled graph of overlapping nodes; its
/// dead ends and tangles fade, and the genome's one clean path lights up.
enum DeBruijn {
    static let duration = 4.0
    private static let path: [(Double, Double)] = [
        (0.08, 0.5), (0.22, 0.36), (0.36, 0.52), (0.5, 0.38), (0.64, 0.54), (0.78, 0.4), (0.92, 0.52),
    ]
    private static let spurs: [((Double, Double), (Double, Double))] = [
        ((0.22, 0.36), (0.18, 0.16)), ((0.36, 0.52), (0.34, 0.76)), ((0.5, 0.38), (0.58, 0.18)),
        ((0.64, 0.54), (0.6, 0.8)), ((0.22, 0.36), (0.5, 0.38)), ((0.5, 0.38), (0.78, 0.4)), ((0.36, 0.52), (0.64, 0.54)),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let grow = Ease.inOut((t - 0.1) / 0.8)
        let prune = Ease.inOut((t - 1.1) / 0.8)
        let light = Ease.inOut((t - 2.0) / 1.2)
        for (i, spur) in spurs.enumerated() {
            let fade = 1 - prune
            guard fade > 0 else { continue }
            let k = Ease.clamp(grow * 1.4 - Double(i) * 0.05)
            let end = (spur.0.0 + (spur.1.0 - spur.0.0) * k, spur.0.1 + (spur.1.1 - spur.0.1) * k)
            u.stroke(context, u.line(spur.0, end), tint.opacity(0.7 * fade), 0.03)
            if k >= 1 { u.stroke(context, u.circle(spur.1.0, spur.1.1, 0.03), tint.opacity(fade), 0.03) }
        }
        if grow > 0 { u.stroke(context, u.polyline(path).trimmedPath(from: 0, to: grow), tint, 0.035) }
        if light > 0 { u.stroke(context, u.polyline(path).trimmedPath(from: 0, to: light), clay, 0.05) }
        for p in path { u.stroke(context, u.circle(p.0, p.1, 0.035), tint, 0.035) }
    }
}

/// A pangenome bubble: the shared reference path opens into a bubble of
/// alternative alleles; one traveller after another takes a different
/// route through it, and they rejoin the shared path.
enum Pangenome {
    static let duration = 4.0
    private static let routes: [[(Double, Double)]] = [
        [(0.04, 0.5), (0.26, 0.5), (0.4, 0.28), (0.6, 0.28), (0.74, 0.5), (0.96, 0.5)],
        [(0.04, 0.5), (0.26, 0.5), (0.4, 0.5), (0.6, 0.5), (0.74, 0.5), (0.96, 0.5)],
        [(0.04, 0.5), (0.26, 0.5), (0.4, 0.72), (0.6, 0.72), (0.74, 0.5), (0.96, 0.5)],
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for route in routes {
            u.stroke(context, u.polyline(Smooth.curve(route, samples: 6)), tint.opacity(0.7), 0.035)
            for p in route[2...3] { context.fill(u.circle(p.0, p.1, 0.025), with: .color(tint)) }
        }
        for p in [(0.26, 0.5), (0.74, 0.5)] { context.fill(u.circle(p.0, p.1, 0.032), with: .color(tint)) }
        for (k, route) in routes.enumerated() {
            let go = Ease.inOut((t - 0.2 - 0.9 * Double(k)) / 1.6)
            guard go > 0, go < 1 else { continue }
            let p = Polyline.point(Smooth.curve(route, samples: 6), at: go)
            context.fill(u.circle(p.0, p.1, 0.035), with: .color(clay))
        }
    }
}

/// Haplotype phasing: tangled reads sort themselves onto two parallel
/// chromosomes by the variants they share, clay on one copy, ink on the other.
enum Phasing {
    static let duration = 4.0
    private static let reads: [(x: Double, top: Bool)] = [
        (0.14, true), (0.3, false), (0.46, true), (0.62, false), (0.2, false), (0.52, true), (0.7, true), (0.38, false),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sort = Ease.inOut((t - 0.6) / 1.6)
        let lines = Ease.clamp((t - 2.0) / 0.5)
        for y in [0.36, 0.68] { u.stroke(context, u.line((0.06, y), (0.94, y)), tint.opacity(0.35 * lines), 0.03) }
        for (k, read) in reads.enumerated() {
            let s = Double(k)
            let loose = (0.2 + 0.6 * abs(sin(s * 1.9 + 0.5)), 0.2 + 0.6 * abs(cos(s * 1.3 + 0.2)))
            let row = read.top ? 0.36 : 0.68
            let spot = (read.x + 0.1, row - 0.06 + (k % 2 == 0 ? 0 : 0.0))
            let p = (loose.0 + (spot.0 - loose.0) * sort, loose.1 + (spot.1 - loose.1) * sort)
            let angle = (s * 40 + t * 20) * (1 - sort)
            var r = context
            let at = u.pt(p.0, p.1)
            r.translateBy(x: at.x, y: at.y)
            r.rotate(by: .degrees(angle))
            r.fill(Path(roundedRect: CGRect(x: -u.len(0.09), y: -u.len(0.018), width: u.len(0.18), height: u.len(0.036)),
                        cornerRadius: u.len(0.018)), with: .color(tint.opacity(0.55)))
            r.fill(Path(ellipseIn: CGRect(x: -u.len(0.02), y: -u.len(0.02), width: u.len(0.04), height: u.len(0.04))),
                   with: .color(read.top ? clay : tint))
        }
    }
}

/// Metagenomic binning: anonymous contigs drift in a dish and gather into
/// genome bins by coverage and composition, one bin in clay.
enum Binning {
    static let duration = 4.0
    private static let bins = [(0.34, 0.36), (0.64, 0.38), (0.48, 0.66)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.43), tint, 0.05)
        let gather = Ease.inOut((t - 0.8) / 1.5)
        for k in 0..<15 {
            let s = Double(k)
            let bin = k % 3
            let drift = (0.5 + 0.3 * sin(s * 2.3 + t * 0.6), 0.5 + 0.3 * cos(s * 1.7 + t * 0.5))
            let c = bins[bin]
            // Members of a bin spread round its centre, not stacked.
            let member = Double(k / 3)
            let spot = (c.0 + 0.075 * cos(member * 1.26 + Double(bin)), c.1 + 0.065 * sin(member * 1.26 + Double(bin)))
            let p = (drift.0 + (spot.0 - drift.0) * gather, drift.1 + (spot.1 - drift.1) * gather)
            var contig = context
            let at = u.pt(p.0, p.1)
            contig.translateBy(x: at.x, y: at.y)
            contig.rotate(by: .degrees(s * 37 * (1 - gather) + Double(bin) * 60 * gather))
            let w = 0.05 + 0.03 * abs(sin(s * 3))
            contig.fill(Path(roundedRect: CGRect(x: -u.len(w / 2), y: -u.len(0.014), width: u.len(w), height: u.len(0.028)),
                             cornerRadius: u.len(0.014)), with: .color(bin == 2 && gather > 0.6 ? clay : tint))
        }
    }
}

/// Spatial transcriptomics into a UMAP: a tissue fills with spots, the
/// spots resolve into cell-type territories, then lift out into three
/// clusters of an embedding.
enum SpatialUMAP {
    static let duration = 4.0
    private static let spots: [(Double, Double)] = {
        var out: [(Double, Double)] = []
        for r in 0..<7 {
            for q in 0..<7 {
                let x = 0.22 + 0.095 * Double(q) + (r % 2 == 0 ? 0 : 0.0475)
                let y = 0.22 + 0.085 * Double(r)
                let inside = pow((x - 0.5) / 0.34, 2) + pow((y - 0.48) / 0.3, 2) < 1
                if inside { out.append((x, y)) }
            }
        }
        return out
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fill = Ease.clamp((t - 0.1) / 0.8)
        let resolve = Ease.inOut((t - 1.0) / 0.6)
        let lift = Ease.inOut((t - 2.1) / 0.8)
        let tissue = (0..<24).map { i -> (Double, Double) in
            let a = Double(i) / 24 * 2 * .pi
            return (0.5 + (0.38 + 0.03 * sin(3 * a)) * cos(a), 0.48 + (0.33 + 0.03 * cos(2 * a)) * sin(a))
        }
        var outline = u.polyline(Smooth.curve(tissue + [tissue[0], tissue[1]], samples: 4))
        outline.closeSubpath()
        u.stroke(context, outline, tint.opacity(1 - lift), 0.04)
        let centres = [(0.28, 0.3), (0.72, 0.34), (0.5, 0.74)]
        for (i, s) in spots.enumerated() {
            guard Double(i) / Double(spots.count) < fill else { continue }
            let type = s.0 < 0.42 ? 0 : (s.0 > 0.6 ? 1 : 2)
            let c = centres[type]
            let embed = (c.0 + 0.09 * cos(Double(i) * 2.4) * sqrt(Double(i % 7) / 7 + 0.2),
                         c.1 + 0.08 * sin(Double(i) * 2.4) * sqrt(Double(i % 7) / 7 + 0.2))
            let p = (s.0 + (embed.0 - s.0) * lift, s.1 + (embed.1 - s.1) * lift)
            let pulse = 1 + 0.15 * sin(t * 3 + Double(type) * 2) * resolve
            let color: Color = type == 0 ? clay.opacity(0.35 + 0.65 * resolve) : tint.opacity(type == 1 ? 1 : 1 - 0.55 * resolve)
            context.fill(u.circle(p.0, p.1, 0.022 * pulse), with: .color(color))
        }
    }
}

/// Protein structural alignment: two copies of a fold, turned and set
/// apart, rotate and slide until their shared core lies as one.
enum StructuralAlignment {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let align = Ease.inOut((t - 0.4) / 1.8)
        let chain = Fold.ribbon(Fold.compact).map { (0.5 + ($0.0 - 0.5) * 0.8, 0.5 + ($0.1 - 0.5) * 0.8) }
        func placed(_ angle: Double, _ offset: (Double, Double)) -> [(Double, Double)] {
            chain.map { p in
                let x = p.0 - 0.5, y = p.1 - 0.5
                return (0.5 + x * cos(angle) - y * sin(angle) + offset.0, 0.5 + x * sin(angle) + y * cos(angle) + offset.1)
            }
        }
        let first = placed(-0.9 * (1 - align), (-0.14 * (1 - align), 0.06 * (1 - align)))
        let second = placed(0.7 * (1 - align), (0.14 * (1 - align), -0.05 * (1 - align)))
        u.stroke(context, u.polyline(first), tint, 0.05)
        u.stroke(context, u.polyline(second), clay.opacity(0.85), 0.035)
    }
}

/// Synteny: the gene blocks of a second chromosome reorder themselves
/// until conserved neighbourhoods line up with the first; the links
/// between them straighten.
enum Synteny {
    static let duration = 4.0
    private static let tones: [Double] = [1, 0.35, 0.7, 0.5, 0.85]
    private static let shuffled = [3, 0, 4, 1, 2]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sort = Ease.inOut((t - 0.8) / 1.6)
        func x(_ slot: Double) -> Double { 0.16 + 0.17 * slot }
        for i in 0..<5 {
            let top = x(Double(i))
            let from = Double(shuffled.firstIndex(of: i) ?? i)
            let bottom = x(from + (Double(i) - from) * sort)
            u.stroke(context, u.line((top, 0.33), (bottom, 0.67)), tint.opacity(0.3), 0.025)
            let color: Color = i == 0 ? clay : tint.opacity(tones[i])
            context.fill(u.capsule(top, 0.3, 0.13, 0.07, corner: 0.02), with: .color(color))
            context.fill(u.capsule(bottom, 0.7, 0.13, 0.07, corner: 0.02), with: .color(color))
        }
    }
}

/// Tandem mass spectrometry: a five-residue peptide flies in and is broken
/// by a collision into fragments one, two, three and four residues long;
/// each flies to its peak on the m/z axis, the small ones to the left, the
/// whole peptide's peak at the right.
enum MassSpec {
    static let duration = 4.2
    private static let axis = 0.86
    /// Each fragment's length in residues, where its peak sits, and how tall.
    private static let fragments: [(size: Int, x: Double, h: Double)] = [
        (1, 0.2, 0.2), (2, 0.36, 0.34), (3, 0.52, 0.26), (4, 0.68, 0.4), (5, 0.84, 0.16),
    ]

    private static func chain(_ context: GraphicsContext, _ u: UnitSquare, _ n: Int, at c: (Double, Double), tint: Color) {
        let gap = 0.045
        let left = c.0 - gap * Double(n - 1) / 2
        if n > 1 { u.stroke(context, u.line((left, c.1), (left + gap * Double(n - 1), c.1)), tint, 0.025) }
        for k in 0..<n { context.fill(u.circle(left + gap * Double(k), c.1, 0.018), with: .color(tint)) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.1, axis), (0.92, axis)), tint, 0.04)
        for x in stride(from: 0.2, through: 0.84, by: 0.16) { u.stroke(context, u.line((x, axis), (x, axis + 0.03)), tint.opacity(0.5), 0.02) }
        let fly = Ease.out(t / 0.7)
        let hit = (t - 0.75) / 0.4
        if hit > 0, hit < 1 { u.stroke(context, u.circle(0.5, 0.2, 0.05 + 0.08 * hit), clay.opacity(1 - hit), 0.03) }
        if t < 0.8 {
            chain(context, u, 5, at: (0.12 + 0.38 * fly, 0.2), tint: tint)
        }
        for (i, f) in fragments.enumerated() {
            let burst = Ease.out((t - 0.8) / 0.4)
            let travel = Ease.inOut((t - 1.3 - 0.12 * Double(i)) / 0.7)
            let rise = Ease.outBack((t - 1.9 - 0.12 * Double(i)) / 0.35)
            if rise > 0 { u.stroke(context, u.line((f.x, axis), (f.x, axis - f.h * min(1, rise))), clay, 0.04) }
            guard t >= 0.8 else { continue }
            let scattered = (0.5 + 0.12 * cos(Double(i) * 1.3 + 0.4) * burst, 0.2 + 0.08 * sin(Double(i) * 2.1) * burst)
            let above = (f.x, axis - f.h - 0.08)
            let p = (scattered.0 + (above.0 - scattered.0) * travel, scattered.1 + (above.1 - scattered.1) * travel)
            chain(context, u, f.size, at: p, tint: tint)
        }
    }
}

/// Barcode demultiplexing: reads with small barcode tabs stream in and
/// sort into three sample wells by their tab.
enum Demultiplex {
    static let duration = 3.6
    private static let wells = [0.24, 0.5, 0.76]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for y in wells {
            u.stroke(context, u.line((0.94, y - 0.08), (0.76, y - 0.08), (0.76, y + 0.08), (0.94, y + 0.08)), tint, 0.04)
        }
        for k in 0..<9 {
            let barcode = [0, 2, 1, 1, 0, 2, 2, 0, 1][k]
            let age = (t - 0.15 - 0.35 * Double(k)) / 1.0
            guard age > 0, age < 1.2 else { continue }
            let go = Ease.inOut(min(1, age))
            let from = (0.04, 0.5), to = (0.84, wells[barcode])
            let p = (from.0 + (to.0 - from.0) * go, from.1 + (to.1 - from.1) * Ease.inOut((go - 0.3) / 0.7))
            context.fill(u.capsule(p.0, p.1, 0.12, 0.03, corner: 0.015), with: .color(tint.opacity(0.6)))
            let tab: Color = barcode == 0 ? clay : tint.opacity(barcode == 1 ? 1 : 0.45)
            context.fill(u.capsule(p.0 - 0.07, p.1, 0.03, 0.045, corner: 0.01), with: .color(tab))
        }
    }
}

/// A copy-number profile: along a flat chromosome trace, one stretch rises
/// into an amplification and another sinks into a deletion, in clay, then
/// both settle back.
enum CopyNumber {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let change = Ease.inOut((t - 0.5) / 0.8) * (1 - Ease.inOut((t - 2.8) / 0.6))
        func level(_ x: Double) -> Double {
            var y = 0.55
            if x > 0.24, x < 0.44 { y -= 0.2 * change }
            if x > 0.6, x < 0.78 { y += 0.18 * change }
            return y
        }
        for i in 0..<40 {
            let x = 0.08 + 0.84 * Double(i) / 39
            let jitter = 0.03 * sin(Double(i) * 12.9898) * sin(Double(i) * 4.1)
            context.fill(u.circle(x, level(x) + jitter, 0.014), with: .color(tint.opacity(0.7)))
        }
        u.stroke(context, u.line((0.08, 0.55), (0.92, 0.55)), tint.opacity(0.3), 0.025)
        if change > 0.05 {
            u.stroke(context, u.line((0.24, level(0.34)), (0.44, level(0.34))), clay, 0.045)
            u.stroke(context, u.line((0.6, level(0.69)), (0.78, level(0.69))), clay, 0.045)
        }
    }
}

/// A fluorescent protein: its strands fold into a barrel round a clay
/// chromophore; the exciting light comes in, and clay light shines out.
enum Fluorescence {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = (0.5, 0.5)
        for k in 0..<9 {
            let a = Double(k) / 9 * .pi
            let x = centre.0 + 0.16 * cos(a + .pi)
            let form = Ease.outBack((t - 0.2 - 0.12 * Double(k)) / 0.3)
            guard form > 0 else { continue }
            let h = 0.3 * min(1, form)
            u.stroke(context, u.line((x, centre.1 - h / 2), (x, centre.1 + h / 2)), tint.opacity(0.5 + 0.5 * sin(a)), 0.035)
        }
        let barrel = Ease.clamp((t - 1.3) / 0.3)
        if barrel > 0 {
            u.stroke(context, u.ellipse(0.5, 0.35, 0.34, 0.08), tint.opacity(barrel), 0.035)
            u.stroke(context, u.ellipse(0.5, 0.65, 0.34, 0.08), tint.opacity(barrel), 0.035)
        }
        let mature = Ease.outBack((t - 1.5) / 0.3)
        if mature > 0 {
            var ring = u.polyline(Rings.hexagon(centre, 0.035 * min(1, mature)))
            ring.closeSubpath()
            context.fill(ring, with: .color(clay))
        }
        // The exciting light, in from the left as a dashed beam.
        let beam = Ease.clamp((t - 1.9) / 0.3) * (1 - Ease.clamp((t - 3.3) / 0.3))
        if beam > 0 {
            var x = 0.04 + (t * 0.4).truncatingRemainder(dividingBy: 0.06)
            while x < 0.3 {
                u.stroke(context, u.line((x, 0.5), (x + 0.03, 0.5)), tint.opacity(beam), 0.03)
                x += 0.06
            }
        }
        // Emission: clay rings and rays.
        let glow = Ease.clamp((t - 2.2) / 0.2) * (1 - Ease.clamp((t - 3.4) / 0.4))
        if glow > 0 {
            for k in 0..<2 {
                let r = ((t * 0.5 + 0.5 * Double(k)).truncatingRemainder(dividingBy: 1))
                u.stroke(context, u.circle(0.5, 0.5, 0.2 + 0.24 * r), clay.opacity(glow * (1 - r)), 0.03)
            }
            for k in 0..<6 {
                let a = Double(k) * 60 - 60
                let from = Rings.offset(centre, 0.26, a), to = Rings.offset(centre, 0.33, a)
                u.stroke(context, u.line(from, to), clay.opacity(glow), 0.035)
            }
        }
    }
}
