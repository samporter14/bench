// DataBatchKTwoScenes.swift
// ScienceStatus — figures from the lab and the genome: an enzyme's rates
// straightened into a line, a growth curve with its lag found, mutations as
// lollipops, a spike raster, a Hi-C map, a genome browser and a circular
// genome plot. Each draws in a unit square (see `UnitSquare`): kit and data
// in the tint, the thing the figure finds in clay.

import SwiftUI

/// Michaelis–Menten into Lineweaver–Burk: rates land against substrate and
/// the saturating curve draws through them, with Vmax and Km marked; then
/// the rates flip to their reciprocals, then the substrate does, the curve
/// straightens to a line, and its intercepts read Vmax and Km off in clay.
enum MichaelisMenten {
    static let duration = 6.8
    private static let bottom = 0.86
    private static let substrate = [0.4, 0.8, 1.5, 3.0, 6.0]

    private static func rate(_ s: Double) -> Double { s / (1 + s) }
    private static func direct(_ s: Double) -> (Double, Double) {
        (0.14 + 0.76 * s / 7, bottom - 0.7 * rate(s))
    }
    private static func reciprocal(_ s: Double) -> (Double, Double) {
        (0.42 + 0.2 / s, bottom - 0.22 / rate(s))
    }
    /// The rate's reciprocal first (`up`, sliding up and down), then the
    /// substrate's (`across`, sliding sideways).
    private static func blend(_ s: Double, up: Double, across: Double) -> (Double, Double) {
        let a = direct(s), b = reciprocal(s)
        return (a.0 + (b.0 - a.0) * across, a.1 + (b.1 - a.1) * up)
    }
    private static let samples: [Double] = (0...40).map { 0.4 * pow(7 / 0.4, Double($0) / 40) }
    /// The curve's start, near the origin, which the reciprocal plot has no room for.
    private static let tail: [Double] = (0...10).map { 0.02 + 0.38 * Double($0) / 10 }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let up = Ease.inOut((t - 3.7) / 0.9), across = Ease.inOut((t - 4.7) / 0.9)
        let axis = 0.14 + 0.28 * across
        u.stroke(context, u.line((0.14 - 0.06 * across, bottom), (0.94, bottom)), tint, 0.03)
        u.stroke(context, u.line((axis, 0.08), (axis, bottom)), tint, 0.03)
        let dash = StrokeStyle(lineWidth: max(u.len(0.02), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.03), u.len(0.03)])
        let fade = 1 - min(1, up * 3)

        let draw = Ease.inOut((t - 1.3) / 0.9)
        if draw > 0 {
            let tailPath = u.polyline(tail.map { direct($0) }).trimmedPath(from: 0, to: Ease.clamp(draw / 0.2))
            if fade > 0 { u.stroke(context, tailPath, tint.opacity(fade), 0.03) }
            let main = u.polyline(samples.map { blend($0, up: up, across: across) }).trimmedPath(from: 0, to: Ease.clamp((draw - 0.2) / 0.8))
            u.stroke(context, main, tint, 0.03)
        }
        for (k, s) in substrate.enumerated() {
            let land = Ease.outBack((t - 0.4 - 0.18 * Double(k)) / 0.3)
            guard land > 0 else { continue }
            let p = blend(s, up: up, across: across)
            context.fill(u.circle(p.0, p.1, 0.024 * min(1, land)), with: .color(clay))
        }
        // Vmax as a ceiling, and Km where half of it is reached.
        let ceiling = Ease.inOut((t - 2.1) / 0.5)
        if ceiling > 0 && fade > 0 {
            let vmax = bottom - 0.7
            context.stroke(u.line((0.14, vmax), (0.14 + 0.78 * ceiling, vmax)), with: .color(tint.opacity(0.6 * fade)), style: dash)
        }
        let half = Ease.inOut((t - 2.6) / 0.8)
        if half > 0 && fade > 0 {
            let km = direct(1)
            let level = bottom - 0.35
            context.stroke(u.line((0.14, level), (0.14 + (km.0 - 0.14) * min(1, half * 2), level)), with: .color(clay.opacity(fade)), style: dash)
            if half > 0.5 {
                let down = level + (bottom - level) * (half - 0.5) * 2
                context.stroke(u.line((km.0, level), (km.0, down)), with: .color(clay.opacity(fade)), style: dash)
            }
            if half >= 1 { context.fill(u.circle(km.0, bottom, 0.022), with: .color(clay.opacity(fade))) }
        }
        // The line runs on to where it meets the axes.
        let extend = Ease.inOut((t - 5.7) / 0.6)
        if extend > 0 {
            let from = reciprocal(7), to = (0.22, bottom)
            let end = (from.0 + (to.0 - from.0) * extend, from.1 + (to.1 - from.1) * extend)
            context.stroke(u.line(from, end), with: .color(tint.opacity(0.7)), style: dash)
        }
        let mark = Ease.outBack((t - 6.1) / 0.4)
        if mark > 0 {
            context.fill(u.circle(0.42, bottom - 0.22, 0.026 * min(1, mark)), with: .color(clay))
            context.fill(u.circle(0.22, bottom, 0.026 * min(1, mark)), with: .color(clay))
        }
    }
}

/// A bacterial growth curve: readings land as the culture grows, flat in the
/// lag, climbing in clay through the exponential phase, levelling at the
/// plateau; then the steepest tangent is drawn, and where it meets the
/// baseline is the lag time.
enum GrowthCurve {
    static let duration = 5.6
    private static let left = 0.12, right = 0.92, top = 0.2, bottom = 0.84
    private static func growth(_ tau: Double) -> Double { 1 / (1 + exp(-(tau - 0.5) / 0.09)) }
    private static func point(_ tau: Double) -> (Double, Double) {
        (left + (right - left) * tau, bottom - (bottom - top) * growth(tau))
    }
    private static let curve: [(Double, Double)] = (0...100).map { point(Double($0) / 100) }
    private static let readings: [Double] = (0..<14).map { 0.03 + 0.94 * Double($0) / 13 }
    private static let tangent: (from: (Double, Double), to: (Double, Double)) = {
        let mid = point(0.5)
        let slope = -(bottom - top) * (0.25 / 0.09) / (right - left)
        return ((mid.0 + (bottom - mid.1) / slope, bottom), (mid.0 + (top - mid.1) / slope, top))
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((left, 0.08), (left, bottom), (right + 0.02, bottom)), tint, 0.03)
        let dash = StrokeStyle(lineWidth: max(u.len(0.02), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.03), u.len(0.03)])
        let progress = Ease.inOut((t - 0.4) / 2.6)
        if progress > 0 {
            let last = Int((progress * 100).rounded())
            u.stroke(context, u.polyline(Array(curve[0...last])), tint, 0.03)
            if last > 32 {
                u.stroke(context, u.polyline(Array(curve[32...min(last, 68)])), clay, 0.04)
            }
            for tau in readings {
                let land = Ease.outBack((progress - tau) / 0.06)
                guard land > 0 else { continue }
                let p = point(tau)
                let inLog = tau > 0.32 && tau < 0.68
                context.fill(u.circle(p.0, p.1, 0.02 * min(1, land)), with: .color(inLog ? clay : tint))
            }
        }
        // The plateau, and the steepest tangent down to the baseline.
        let plateau = Ease.inOut((t - 3.2) / 0.6)
        if plateau > 0 {
            context.stroke(u.line((left, top), (left + (right - left) * plateau, top)), with: .color(tint.opacity(0.45)), style: dash)
        }
        let find = Ease.inOut((t - 3.5) / 0.9)
        if find > 0 {
            let a = tangent.from, b = tangent.to
            let end = (a.0 + (b.0 - a.0) * find, a.1 + (b.1 - a.1) * find)
            context.stroke(u.line(a, end), with: .color(clay), style: dash)
        }
        let lag = Ease.outBack((t - 4.4) / 0.4)
        if lag > 0 {
            context.fill(u.circle(tangent.from.0, bottom, 0.03 * min(1, lag)), with: .color(clay))
        }
    }
}

/// A lollipop plot: a protein's bar draws, its two domains shade in, and
/// mutations rise off it one by one, each a stem and a dot, tallest where
/// it happens most, in clay.
enum LollipopPlot {
    static let duration = 5.2
    private static let barY = 0.82, from = 0.1, to = 0.9
    private static let sites: [(x: Double, height: Double)] = [
        (0.16, 0.16), (0.25, 0.3), (0.32, 0.2), (0.4, 0.26), (0.5, 0.56), (0.6, 0.24), (0.7, 0.36), (0.79, 0.18), (0.87, 0.24),
    ]
    private static let hotspot = 4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let width = (to - from) * Ease.out(t / 0.9)
        if width > 0 {
            u.stroke(context, u.capsule(from + width / 2, barY, width, 0.06, corner: 0.03), tint, 0.024)
        }
        let shade = Ease.clamp((t - 0.8) / 0.6)
        if shade > 0 {
            context.fill(u.capsule(0.31, barY, 0.22, 0.06, corner: 0.03), with: .color(tint.opacity(0.55 * shade)))
            context.fill(u.capsule(0.67, barY, 0.26, 0.06, corner: 0.03), with: .color(tint.opacity(0.55 * shade)))
        }
        for (i, site) in sites.enumerated() {
            let start = 1.5 + 0.25 * Double(i)
            let stem = Ease.out((t - start) / 0.35)
            guard stem > 0 else { continue }
            let hot = i == hotspot
            let color = hot ? clay : tint
            let base = barY - 0.03, top = base - site.height * stem
            u.stroke(context, u.line((site.x, base), (site.x, top)), color, 0.022)
            let pop = Ease.outBack((t - start - 0.3) / 0.3)
            if pop > 0 {
                context.fill(u.circle(site.x, top, (hot ? 0.05 : 0.032) * min(1, pop)), with: .color(color))
            }
            if hot {
                let ring = (t - start - 0.6) / 0.9
                if ring > 0 && ring < 1 {
                    u.stroke(context, u.circle(site.x, top, 0.05 + 0.1 * ring), clay.opacity(1 - ring), 0.02)
                }
            }
        }
    }
}

/// A spike raster: a cursor sweeps across five neurons' rows, each spike
/// ticking in as it passes; under them a histogram counts the spikes in each
/// slice of time, and where they all fire together the bar climbs in clay.
enum SpikeRaster {
    static let duration = 5.2
    private static let rows = 5, bins = 10
    private static let left = 0.1, width = 0.8, floor = 0.88
    private static let spikes: [[Double]] = (0..<5).map { row in
        let background: [Double] = (0..<6).map { BenchShapes.rand(Double(row * 11 + $0) * 3.7 + 0.5) }
        let burst: [Double] = (0..<2).map { 0.61 + 0.07 * BenchShapes.rand(Double(row * 5 + $0) * 6.1 + 1.3) }
        return (background + burst).sorted()
    }
    private static let burstBin = 6
    /// The tallest bar's count once every spike has fired.
    private static let peak: Double = {
        var counts = [Double](repeating: 0, count: 10)
        for row in spikes { for s in row { counts[min(9, Int(s * 10))] += 1 } }
        return counts.max() ?? 1
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tau = Ease.clamp((t - 0.4) / 3.8)
        var counts = [Double](repeating: 0, count: bins)
        for (row, times) in spikes.enumerated() {
            let y = 0.13 + 0.1 * Double(row)
            for s in times {
                let pop = Ease.out((tau - s) / 0.03)
                guard pop > 0 else { continue }
                counts[min(bins - 1, Int(s * Double(bins)))] += pop
                let burst = s >= 0.6 && s <= 0.7
                let x = left + width * s
                u.stroke(context, u.line((x, y - 0.03 * pop), (x, y + 0.03 * pop)), burst ? clay : tint, 0.022)
            }
        }
        u.stroke(context, u.line((left, floor + 0.015), (left + width, floor + 0.015)), tint.opacity(0.7), 0.02)
        for bin in 0..<bins where counts[bin] > 0 {
            let h = 0.26 * counts[bin] / peak
            let x = left + width * (Double(bin) + 0.5) / Double(bins)
            context.fill(u.capsule(x, floor - h / 2, 0.058, h, corner: 0.01),
                         with: .color(bin == burstBin ? clay : tint.opacity(0.75)))
        }
        // The cursor, until it has crossed.
        let alpha = 1 - Ease.clamp((t - 4.3) / 0.4)
        if tau > 0 && alpha > 0 {
            let x = left + width * tau
            u.stroke(context, u.line((x, 0.08), (x, floor + 0.015)), tint.opacity(0.6 * alpha), 0.02)
        }
    }
}

/// A Hi-C map: contacts between stretches of the genome as a triangle, dense
/// along the diagonal and thinning with distance; then the domains show,
/// stretches that touch themselves more than their neighbours, and one, in
/// clay, has its loop, the corner where its two ends meet.
enum HiCMap {
    static let duration = 5.4
    private static let bins = 10, cell = 0.08, left = 0.1, baseline = 0.72
    private static let domainEdge = 6   // bins 0..<6 are one domain, 6..<10 the next

    private static func sameDomain(_ i: Int, _ j: Int) -> Bool {
        (i < domainEdge) == (j < domainEdge)
    }

    /// Contact frequency of a pair: falling with distance, and higher inside a domain.
    private static func contact(_ i: Int, _ j: Int) -> (base: Double, boost: Double) {
        let d = Double(j - i)
        let base = 0.95 * exp(-d / 2.4)
        let boost = sameDomain(i, j) ? 0.32 * exp(-d / 4) : -0.08
        // The loop: the domain's two ends, touching, at full strength.
        return (base, i == 0 && j == 5 ? 1 - base : boost)
    }

    private static func center(_ i: Int, _ j: Int) -> (Double, Double) {
        let gi = left + cell * (Double(i) + 0.5), gj = left + cell * (Double(j) + 0.5)
        return ((gi + gj) / 2, baseline - cell / 2 - (gj - gi) / 2)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reveal = Ease.inOut((t - 2.6) / 0.8)
        let half = cell * 0.46
        for d in 0..<bins {
            let appear = Ease.out((t - 0.2 - 0.22 * Double(d)) / 0.5)
            guard appear > 0 else { continue }
            for i in 0..<(bins - d) {
                let j = i + d
                let value = contact(i, j)
                let v = max(0, min(1, value.base + value.boost * reveal))
                let c = center(i, j)
                let s = half * min(1, appear)
                var diamond = u.line((c.0 - s, c.1), (c.0, c.1 - s), (c.0 + s, c.1), (c.0, c.1 + s))
                diamond.closeSubpath()
                let loop = i == 0 && j == 5
                context.fill(diamond, with: .color(loop && reveal >= 1 ? clay : tint.opacity(0.05 + 0.88 * v)))
            }
        }
        // The genome the map is of, and the domains as outlines above it.
        u.stroke(context, u.line((left, baseline + 0.05), (left + cell * Double(bins), baseline + 0.05)), tint, 0.024)
        let edge = left + cell * Double(domainEdge)
        u.stroke(context, u.line((edge, baseline + 0.035), (edge, baseline + 0.065)), tint, 0.024)
        let outline = Ease.inOut((t - 3.5) / 0.8)
        if outline > 0 {
            let y = baseline - cell / 2
            let bigApex = (left + cell * 3, y - cell * 3)
            var big = u.line((left, y), bigApex, (left + cell * 6, y))
            big.closeSubpath()
            u.stroke(context, big.trimmedPath(from: 0, to: outline), clay, 0.022)
            let smallApex = (edge + cell * 2, y - cell * 2)
            var small = u.line((edge, y), smallApex, (left + cell * 10, y))
            small.closeSubpath()
            u.stroke(context, small.trimmedPath(from: 0, to: outline), tint.opacity(0.8), 0.022)
        }
        let ring = Ease.outBack((t - 4.4) / 0.5)
        if ring > 0 {
            let c = center(0, 5)
            u.stroke(context, u.circle(c.0, c.1, 0.05 * min(1, ring)), clay, 0.024)
        }
    }
}

/// A genome browser: a ruler, a gene with its three exons and the arrow of
/// where it starts, the reads piled over it that rise where the exons are,
/// and a clay peak of protein binding at the start; a dashed line links the
/// peak to the gene across the tracks.
enum GenomeBrowser {
    static let duration = 5.2
    private static let exons: [(from: Double, to: Double)] = [(0.24, 0.32), (0.44, 0.52), (0.66, 0.84)]
    private static let bars: [(x: Double, height: Double)] = (0..<25).map { k in
        let x = 0.1 + 0.8 * Double(k) / 24
        let inside = exons.contains { x >= $0.from - 0.015 && x <= $0.to + 0.015 }
        let r = BenchShapes.rand(Double(k) * 2.3 + 0.7)
        return (x, inside ? 0.12 + 0.1 * r : 0.008 + 0.02 * r)
    }
    private static let focus = 0.24

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The ruler.
        let ruler = Ease.inOut(t / 0.7)
        u.stroke(context, u.line((0.08, 0.1), (0.08 + 0.84 * ruler, 0.1)), tint, 0.024)
        for k in 0...16 {
            let x = 0.08 + 0.84 * Double(k) / 16
            guard x <= 0.08 + 0.84 * ruler else { break }
            let major = k % 4 == 0
            u.stroke(context, u.line((x, 0.1), (x, major ? 0.155 : 0.13)), tint.opacity(major ? 0.9 : 0.5), 0.02)
        }
        // The gene: exons pop in, introns draw between them, chevrons on the way.
        let gene = 0.3
        for (i, exon) in exons.enumerated() {
            let pop = Ease.outBack((t - 0.7 - 0.25 * Double(i)) / 0.35)
            if i > 0 {
                let previous = exons[i - 1].to
                let run = Ease.inOut((t - 0.7 - 0.25 * Double(i)) / 0.4)
                if run > 0 {
                    u.stroke(context, u.line((previous, gene), (previous + (exon.from - previous) * run, gene)), tint.opacity(0.7), 0.02)
                    if run >= 1 {
                        let mid = (previous + exon.from) / 2
                        u.stroke(context, u.line((mid - 0.014, gene - 0.02), (mid + 0.008, gene), (mid - 0.014, gene + 0.02)), tint.opacity(0.7), 0.02)
                    }
                }
            }
            guard pop > 0 else { continue }
            let w = (exon.to - exon.from) * min(1, pop)
            context.fill(u.capsule((exon.from + exon.to) / 2, gene, w, 0.07, corner: 0.015), with: .color(tint))
        }
        let start = Ease.inOut((t - 1.4) / 0.4)
        if start > 0 {
            let top = gene - 0.035 - 0.07 * start
            u.stroke(context, u.line((exons[0].from, gene - 0.035), (exons[0].from, top)), tint, 0.022)
            if start >= 1 {
                u.stroke(context, u.line((exons[0].from, top), (exons[0].from + 0.045, top)), tint, 0.022)
                u.stroke(context, u.line((exons[0].from + 0.03, top - 0.02), (exons[0].from + 0.05, top), (exons[0].from + 0.03, top + 0.02)), tint, 0.022)
            }
        }
        // The reads piled up: tall over the exons, thin elsewhere.
        let floor = 0.66
        u.stroke(context, u.line((0.08, floor + 0.012), (0.92, floor + 0.012)), tint.opacity(0.4), 0.018)
        for (k, bar) in bars.enumerated() {
            let grow = Ease.out((t - 1.6 - 0.05 * Double(k)) / 0.4)
            guard grow > 0 else { continue }
            let h = bar.height * grow
            context.fill(u.capsule(bar.x, floor - h / 2, 0.024, max(h, 0.012), corner: 0.01), with: .color(tint.opacity(0.75)))
        }
        // The binding peak at the start of the gene, in clay.
        let peak = Ease.out((t - 3.2) / 0.7)
        if peak > 0 {
            let base = 0.9
            let curve: [(Double, Double)] = stride(from: 0.1, through: 0.38, by: 0.01).map { x in
                let z = (x - focus) / 0.045
                return (x, base - 0.19 * peak * exp(-z * z))
            }
            var area = u.polyline(curve)
            area.addLine(to: u.pt(0.38, base))
            area.addLine(to: u.pt(0.1, base))
            area.closeSubpath()
            context.fill(area, with: .color(clay.opacity(0.3)))
            u.stroke(context, u.polyline(curve), clay, 0.026)
        }
        let link = Ease.inOut((t - 4.1) / 0.7)
        if link > 0 {
            let dash = StrokeStyle(lineWidth: max(u.len(0.018), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.025), u.len(0.03)])
            context.stroke(u.line((focus, 0.17), (focus, 0.17 + 0.71 * link)), with: .color(clay.opacity(0.8)), style: dash)
        }
    }
}

/// A circular genome plot: the chromosomes lay out as arcs of a ring, one
/// after the next, and chords swing through the middle to join places on
/// them that meet; the last, in clay, is the one that matters.
enum CircularGenomePlot {
    static let duration = 5.6
    private static let radius = 0.4, inner = 0.31, gap = 0.16
    private static let shares: [Double] = [0.2, 0.18, 0.16, 0.15, 0.17, 0.14]
    /// Each chromosome's start and end angle round the ring.
    private static let segments: [(start: Double, end: Double)] = {
        let total = 2 * Double.pi - gap * Double(shares.count)
        var angle = -Double.pi / 2 + gap / 2
        var result: [(start: Double, end: Double)] = []
        for share in shares {
            let span = total * share
            result.append((angle, angle + span))
            angle += span + gap
        }
        return result
    }()
    private static let arcs: [[(Double, Double)]] = segments.map { seg in
        (0...14).map { k in
            let a = seg.start + (seg.end - seg.start) * Double(k) / 14
            return (0.5 + radius * cos(a), 0.5 + radius * sin(a))
        }
    }
    private static let links: [(a: Int, at: Double, b: Int, to: Double)] = [
        (0, 0.3, 3, 0.6), (1, 0.7, 4, 0.2), (2, 0.4, 5, 0.7), (0, 0.8, 2, 0.1), (3, 0.3, 5, 0.3),
    ]
    private static let marked: (a: Int, at: Double, b: Int, to: Double) = (1, 0.3, 4, 0.8)

    private static func inside(_ segment: Int, _ at: Double) -> (Double, Double) {
        let s = segments[segment]
        let a = s.start + (s.end - s.start) * at
        return (0.5 + inner * cos(a), 0.5 + inner * sin(a))
    }

    private static func chord(_ u: UnitSquare, _ link: (a: Int, at: Double, b: Int, to: Double)) -> Path {
        let from = inside(link.a, link.at), to = inside(link.b, link.to)
        let mid = ((from.0 + to.0) / 2, (from.1 + to.1) / 2)
        let control = (0.5 + (mid.0 - 0.5) * 0.45, 0.5 + (mid.1 - 0.5) * 0.45)
        var path = Path()
        path.move(to: u.pt(from.0, from.1))
        path.addQuadCurve(to: u.pt(to.0, to.1), control: u.pt(control.0, control.1))
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for (i, arc) in arcs.enumerated() {
            let p = Ease.inOut((t - 0.2 - 0.22 * Double(i)) / 0.5)
            guard p > 0 else { continue }
            u.stroke(context, u.polyline(arc).trimmedPath(from: 0, to: p), tint, 0.045)
        }
        for (k, link) in links.enumerated() {
            let p = Ease.inOut((t - 1.9 - 0.35 * Double(k)) / 0.7)
            guard p > 0 else { continue }
            u.stroke(context, chord(u, link).trimmedPath(from: 0, to: p), tint.opacity(0.65), 0.02)
        }
        let p = Ease.inOut((t - 4.1) / 0.8)
        if p > 0 {
            u.stroke(context, chord(u, marked).trimmedPath(from: 0, to: p), clay, 0.032)
        }
    }
}
