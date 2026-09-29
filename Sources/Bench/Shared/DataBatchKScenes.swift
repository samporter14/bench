// DataBatchKScenes.swift
// ScienceStatus — more of the plots a lab makes: a clustered heatmap, a
// violin with its significance bracket, a PCA, a forest plot, an ROC curve
// and a ridgeline. Each draws in a unit square (see `UnitSquare`): axes and
// data in the tint, the one thing the plot is about in clay. Values are steps
// of tint opacity, never a second hue.

import SwiftUI

/// A clustered heatmap: rows land in a jumble; they sort themselves so rows
/// that behave alike sit together, the blocks come up along the diagonal, and
/// a dendrogram grows out to the left to join them. One cluster is clay.
enum ClusteredHeatmap {
    static let duration = 5.2
    private static let rows = 6, columns = 6
    private static let left = 0.4, top = 0.12, cellWidth = 0.09, cellHeight = 0.126
    /// Which row is in each slot before sorting.
    private static let jumbled = [4, 1, 3, 5, 0, 2]
    /// A row's values: high in its cluster's two columns, low elsewhere, with
    /// a little noise to keep it a real matrix.
    private static let values: [[Double]] = (0..<6).map { row in
        (0..<6).map { column in
            let inside = column / 2 == row / 2
            let noise = BenchShapes.rand(Double(row * 7 + column) * 2.9)
            return inside ? 0.7 + 0.3 * noise : 0.3 * noise
        }
    }

    private static func opacity(_ v: Double) -> Double {
        v > 0.75 ? 0.9 : v > 0.5 ? 0.6 : v > 0.25 ? 0.3 : 0.12
    }

    /// The sorted slot of a row, and the row's slot as it moves from the
    /// jumble to there.
    private static func slot(of row: Int, sorted: Double) -> Double {
        let start = Double(jumbled.firstIndex(of: row) ?? row)
        return start + (Double(row) - start) * sorted
    }

    private static func y(ofSlot slot: Double) -> Double { top + cellHeight * (slot + 0.5) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sorted = Ease.inOut((t - 1.3) / 1.2)
        for row in 0..<rows {
            let land = Ease.outBack((t - 0.2 - 0.1 * Double(row)) / 0.4)
            guard land > 0 else { continue }
            let yy = y(ofSlot: slot(of: row, sorted: sorted))
            for column in 0..<columns {
                let v = values[row][column]
                let xx = left + cellWidth * (Double(column) + 0.5)
                let highlighted = row < 2 && column < 2 && sorted >= 1
                let color = highlighted ? clay.opacity(opacity(v)) : tint.opacity(opacity(v))
                context.fill(u.capsule(xx, yy, cellWidth * 0.86 * min(1, land), cellHeight * 0.84 * min(1, land), corner: 0.014),
                             with: .color(color))
            }
        }
        // The dendrogram: pairs first, then the pairs, then all.
        let pairY: [Double] = (0..<3).map { y(ofSlot: Double(2 * $0) + 0.5) }
        let leaf = left - 0.03, pairX = leaf - 0.07, joinX = pairX - 0.07, rootX = joinX - 0.07
        for pair in 0..<3 {
            let p = Ease.inOut((t - 2.7 - 0.12 * Double(pair)) / 0.5)
            guard p > 0 else { continue }
            let a = y(ofSlot: Double(2 * pair)), b = y(ofSlot: Double(2 * pair + 1))
            let color = pair == 0 ? clay : tint
            u.stroke(context, u.polyline([(leaf, a), (pairX, a), (pairX, b), (leaf, b)]).trimmedPath(from: 0, to: p), color, 0.024)
        }
        let join = Ease.inOut((t - 3.5) / 0.5)
        if join > 0 {
            let path = u.polyline([(pairX, pairY[0]), (joinX, pairY[0]), (joinX, pairY[1]), (pairX, pairY[1])])
            u.stroke(context, path.trimmedPath(from: 0, to: join), tint, 0.024)
        }
        let root = Ease.inOut((t - 4.0) / 0.5)
        if root > 0 {
            let middle = (pairY[0] + pairY[1]) / 2
            let path = u.polyline([(joinX, middle), (rootX, middle), (rootX, pairY[2]), (pairX, pairY[2])])
            u.stroke(context, path.trimmedPath(from: 0, to: root), tint, 0.024)
        }
    }
}

/// A violin with its bracket: dots land for two groups, each is wrapped in
/// its violin, the median goes in, and a bracket rises over the pair to
/// carry its stars, in clay for the treated group.
enum ViolinAndBracket {
    static let duration = 5.4
    private static let groups: [(x: Double, mean: Double, spread: Double)] = [(0.34, 0.68, 0.075), (0.68, 0.5, 0.075)]
    private static let floor = 0.9, ceiling = 0.24

    /// Where the dots of a group sit, jittered inside the violin's width.
    private static let dots: [[(x: Double, y: Double)]] = groups.enumerated().map { g, group in
        (0..<12).map { k in
            let s = Double(g * 40 + k)
            let across = (BenchShapes.rand(s * 1.7) - 0.5) * 0.12
            let along = (BenchShapes.rand(s * 3.1) + BenchShapes.rand(s * 4.3) + BenchShapes.rand(s * 5.9) - 1.5) * 2.2
            return (group.x + across, group.mean + group.spread * along)
        }
    }

    private static func halfWidth(_ y: Double, of group: (x: Double, mean: Double, spread: Double)) -> Double {
        let z = (y - group.mean) / group.spread
        return 0.13 * exp(-z * z / 2)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.1, 0.16), (0.1, floor), (0.92, floor)), tint, 0.03)
        for (g, group) in groups.enumerated() {
            let color = g == 0 ? tint : clay
            for (k, dot) in dots[g].enumerated() {
                let land = Ease.outBack((t - 0.3 - 0.75 * Double(g) - 0.06 * Double(k)) / 0.3)
                guard land > 0 else { continue }
                context.fill(u.circle(dot.x, dot.y, 0.017 * min(1, land)), with: .color(color.opacity(0.85)))
            }
            let wrap = Ease.inOut((t - 2.0 - 0.3 * Double(g)) / 0.8)
            if wrap > 0 {
                let ys = stride(from: group.mean - 3 * group.spread, through: group.mean + 3 * group.spread, by: group.spread / 4).map { $0 }
                let right = ys.map { (group.x + halfWidth($0, of: group) * wrap, $0) }
                let leftSide = ys.reversed().map { (group.x - halfWidth($0, of: group) * wrap, $0) }
                var outline = u.polyline(right + leftSide)
                outline.closeSubpath()
                u.stroke(context, outline, color.opacity(0.9), 0.024)
            }
            let median = Ease.out((t - 2.9 - 0.2 * Double(g)) / 0.4)
            if median > 0 {
                u.stroke(context, u.line((group.x - 0.06 * median, group.mean), (group.x + 0.06 * median, group.mean)), color, 0.035)
            }
        }
        // The bracket over the pair, then its stars.
        let bracket = Ease.inOut((t - 3.6) / 0.7)
        if bracket > 0 {
            let path = u.polyline([(0.34, 0.2), (0.34, 0.13), (0.68, 0.13), (0.68, 0.2)])
            u.stroke(context, path.trimmedPath(from: 0, to: bracket), tint, 0.03)
        }
        for k in 0..<2 {
            let pop = Ease.outBack((t - 4.4 - 0.2 * Double(k)) / 0.35)
            guard pop > 0 else { continue }
            let center = (0.46 + 0.08 * Double(k), 0.075)
            let r = 0.04 * min(1, pop)
            for a in [0.0, .pi / 3, 2 * .pi / 3] {
                u.stroke(context, u.line((center.0 - r * cos(a), center.1 - r * sin(a)), (center.0 + r * cos(a), center.1 + r * sin(a))), clay, 0.026)
            }
        }
    }
}

/// A principal component analysis: a tilted cloud of points; the axis it
/// stretches along is found, in clay, and the cloud turns to lay it flat;
/// then every point drops onto that axis: many dimensions into one.
enum PrincipalComponents {
    static let duration = 5.4
    private static let tilt = -0.62
    private static let points: [(a: Double, b: Double)] = (0..<42).map { k in
        let s = Double(k)
        let a = (BenchShapes.rand(s * 1.3) + BenchShapes.rand(s * 2.7) + BenchShapes.rand(s * 4.1) - 1.5) * 0.7
        let b = (BenchShapes.rand(s * 5.3) + BenchShapes.rand(s * 6.7) + BenchShapes.rand(s * 7.9) - 1.5) * 0.24
        return (max(-0.37, min(0.37, a)), b)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.08, 0.1), (0.08, 0.9), (0.92, 0.9)), tint.opacity(0.5), 0.025)
        let turn = Ease.inOut((t - 2.6) / 1.1)
        let project = Ease.inOut((t - 3.9) / 0.9)
        let angle = tilt * (1 - turn)
        let c = cos(angle), s = sin(angle)
        func place(_ a: Double, _ b: Double) -> (Double, Double) {
            (0.5 + a * c - b * s, 0.5 + a * s + b * c)
        }
        for (k, p) in points.enumerated() {
            let land = Ease.outBack((t - 0.2 - 0.03 * Double(k)) / 0.35)
            guard land > 0 else { continue }
            let q = place(p.a, p.b * (1 - project))
            context.fill(u.circle(q.0, q.1, 0.017 * min(1, land)), with: .color(tint.opacity(0.85)))
        }
        // The axes found: the long one in clay, the short one in the tint.
        let find = Ease.out((t - 1.6) / 0.7)
        if find > 0 {
            let long = place(0.42 * find, 0), longBack = place(-0.42 * find, 0)
            u.stroke(context, u.line(longBack, long), clay, 0.03)
            let arm = (0.42 * find - 0.05, 0.04), armWing = (0.42 * find - 0.05, -0.04)
            let head = u.line(place(arm.0, arm.1), long, place(armWing.0, armWing.1))
            u.stroke(context, head, clay, 0.03)
            if project < 1 {
                let short = place(0, 0.2 * find * (1 - project)), shortBack = place(0, -0.2 * find * (1 - project))
                u.stroke(context, u.line(shortBack, short), tint.opacity(0.7), 0.022)
            }
        }
    }
}

/// A forest plot: study by study, a marker lands sized by its weight and
/// its interval stretches out either side of it; the dashed line of no
/// effect stands behind them; at the bottom the pooled diamond opens in clay.
enum ForestPlot {
    static let duration = 5.0
    private static let studies: [(center: Double, half: Double, weight: Double)] = [
        (0.42, 0.2, 0.026), (0.32, 0.15, 0.034), (0.4, 0.1, 0.044), (0.28, 0.2, 0.024), (0.35, 0.08, 0.05),
    ]
    private static let null = 0.66, pooled = (center: 0.36, half: 0.1)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let dash = StrokeStyle(lineWidth: max(u.len(0.02), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.03), u.len(0.03)])
        let stand = Ease.out(t / 0.6)
        context.stroke(u.line((null, 0.08), (null, 0.08 + 0.84 * stand)), with: .color(tint.opacity(0.6)), style: dash)
        for (i, study) in studies.enumerated() {
            let row = 0.14 + 0.12 * Double(i)
            let arrive = Ease.inOut((t - 0.5 - 0.4 * Double(i)) / 0.5)
            guard arrive > 0 else { continue }
            let reach = study.half * arrive
            u.stroke(context, u.line((study.center - reach, row), (study.center + reach, row)), tint, 0.024)
            let size = study.weight * min(1, Ease.outBack((t - 0.7 - 0.4 * Double(i)) / 0.35))
            if size > 0 {
                context.fill(u.capsule(study.center, row, 2 * size, 2 * size, corner: 0.01), with: .color(tint))
            }
        }
        u.stroke(context, u.line((0.1, 0.75), (0.9, 0.75)), tint.opacity(0.45), 0.02)
        let open = Ease.outBack((t - 2.9) / 0.7)
        if open > 0 {
            let half = pooled.half * min(1.1, open), rise = 0.06 * min(1, open)
            var diamond = u.line((pooled.center - half, 0.86), (pooled.center, 0.86 - rise), (pooled.center + half, 0.86),
                                 (pooled.center, 0.86 + rise))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(clay))
        }
    }
}

/// An ROC curve: a threshold slides along, drawing the curve out from the
/// corner as it goes, the area under it fills in clay, and the dot comes to
/// rest at the best trade-off, with the rates it gives dashed to the axes.
enum ROCCurve {
    static let duration = 5.0
    private static let left = 0.16, right = 0.88, top = 0.12, bottom = 0.84

    private static func rate(_ f: Double) -> Double { 1 - pow(1 - f, 3.2) }
    private static func point(_ f: Double) -> (Double, Double) {
        (left + (right - left) * f, bottom - (bottom - top) * rate(f))
    }
    private static let curve: [(Double, Double)] = stride(from: 0.0, through: 1.0, by: 0.02).map { point($0) }
    private static let best = 0.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((left, top - 0.02), (left, bottom), (right + 0.02, bottom)), tint, 0.03)
        let dash = StrokeStyle(lineWidth: max(u.len(0.02), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.03), u.len(0.03)])
        context.stroke(u.line((left, bottom), (right, top)), with: .color(tint.opacity(0.45)), style: dash)
        let slide = Ease.inOut((t - 0.5) / 2.0)
        let last = Int((slide * Double(curve.count - 1)).rounded())
        if slide > 0 {
            u.stroke(context, u.polyline(Array(curve[0...last])), tint, 0.035)
        }
        let fill = Ease.inOut((t - 2.5) / 0.8)
        if fill > 0 {
            var area = u.polyline(curve)
            area.addLine(to: u.pt(right, bottom))
            area.closeSubpath()
            context.fill(area, with: .color(clay.opacity(0.28 * fill)))
        }
        // The dot leads the curve out, then rests at the best trade-off.
        let rest = Ease.inOut((t - 3.2) / 0.7)
        let f = slide < 1 ? Double(last) / Double(curve.count - 1) : 1 + (best - 1) * rest
        let p = point(f)
        if slide > 0 {
            if slide >= 1 && rest > 0 {
                let guide = min(1, rest * 1.5)
                context.stroke(u.line((left, p.1), (left + (p.0 - left) * guide, p.1)), with: .color(clay.opacity(0.8)), style: dash)
                context.stroke(u.line((p.0, bottom), (p.0, bottom + (p.1 - bottom) * guide)), with: .color(clay.opacity(0.8)), style: dash)
            }
            context.fill(u.circle(p.0, p.1, 0.032), with: .color(clay))
        }
    }
}

/// A ridgeline: distributions stack as lines, one behind the next, each
/// front line hiding the ones behind it, and the peaks drift across as
/// the conditions go on; one ridge, in clay, is the one that matters.
enum Ridgeline {
    static let duration = 5.2
    private static let count = 6
    private static let left = 0.1, right = 0.9

    private static func baseline(_ i: Int) -> Double { 0.3 + 0.11 * Double(i) }

    private static func density(_ x: Double, ridge i: Int) -> Double {
        let center = 0.36 + 0.055 * Double(i)
        let a = (x - center) / 0.085, b = (x - center - 0.17) / 0.06
        return 0.19 * (exp(-a * a) + 0.45 * exp(-b * b))
    }

    /// The x positions each line is sampled at, and every ridge's density
    /// there, worked out once.
    private static let xs: [Double] = stride(from: left, through: right, by: 0.0125).map { $0 }
    private static let table: [[Double]] = (0..<6).map { i in xs.map { density($0, ridge: i) } }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rise: [Double] = (0..<count).map { Ease.out((t - 0.3 - 0.5 * Double($0)) / 0.9) }
        func height(_ k: Int, _ i: Int) -> Double { baseline(i) - table[i][k] * rise[i] }
        for i in 0..<count where rise[i] > 0 {
            var runs: [[(Double, Double)]] = []
            var run: [(Double, Double)] = []
            for (k, x) in xs.enumerated() {
                let y = height(k, i)
                // Hidden where a nearer line stands higher than this one.
                let hidden = ((i + 1)..<count).contains { j in rise[j] > 0 && y > height(k, j) }
                if hidden {
                    if run.count > 1 { runs.append(run) }
                    run = []
                } else {
                    run.append((x, y))
                }
            }
            if run.count > 1 { runs.append(run) }
            var path = Path()
            for r in runs { path.addPath(u.polyline(r)) }
            u.stroke(context, path, i == 2 ? clay : tint.opacity(0.9), 0.028)
        }
    }
}
