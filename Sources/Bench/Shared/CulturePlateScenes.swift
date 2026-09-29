// CulturePlateScenes.swift
// ScienceStatus — tissue culture plates from above: plating a 6-well plate,
// a dose series across a 12-well plate, and a scratch assay in a 24-well
// plate. Each draws in a unit square (see `UnitSquare`): plastic and cells
// in the tint, the media, the drug or the wound in clay.

import SwiftUI

private enum CulturePlate {
    /// The plate's outline, with its notched corner.
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, tint: Color) {
        var body = u.polyline([(0.1, 0.18), (0.86, 0.18), (0.9, 0.22), (0.9, 0.82), (0.1, 0.82)])
        body.closeSubpath()
        context.fill(body, with: .color(tint.opacity(0.06)))
        u.stroke(context, body, tint, 0.03)
    }

    /// Cells in a well: `count` dots scattered inside radius `r`.
    static func cells(_ context: GraphicsContext, _ u: UnitSquare, at c: (Double, Double), r: Double,
                      count: Int, seed: Double, color: Color) {
        for k in 0..<count {
            let s = seed + Double(k)
            let a = BenchShapes.rand(s * 3.7) * 2 * .pi
            let d = r * 0.85 * BenchShapes.rand(s * 5.9).squareRoot()
            context.fill(u.circle(c.0 + d * cos(a), c.1 + d * sin(a), 0.008), with: .color(color))
        }
    }
}

/// Plating a 6-well plate: the tip fills each well with clay media in turn,
/// then the cells settle and multiply towards confluence.
enum SixWellPlate {
    static let duration = 5.0
    private static let wells: [(Double, Double)] = [0.36, 0.64].flatMap { y in [0.27, 0.5, 0.73].map { x in (x, y) } }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        CulturePlate.draw(context, u, tint: tint)
        let growth = Ease.inOut((t - 2.2) / 2.2)
        for (k, w) in wells.enumerated() {
            let filled = Ease.clamp((t - 0.3 - 0.3 * Double(k)) / 0.25)
            if filled > 0 { context.fill(u.circle(w.0, w.1, 0.1), with: .color(clay.opacity(0.35 * filled))) }
            u.stroke(context, u.circle(w.0, w.1, 0.1), tint, 0.025)
            let count = filled >= 1 && t > 2.0 ? Int(8 + 44 * growth) : 0
            CulturePlate.cells(context, u, at: w, r: 0.1, count: count, seed: Double(k) * 100, color: tint)
        }
        // The tip, visiting each well in turn, then lifting away.
        let visit = min(Double(wells.count - 1), max(0, (t - 0.2) / 0.3))
        let lower = Int(visit), upper = min(wells.count - 1, lower + 1), f = visit - Double(lower)
        let at = (wells[lower].0 + (wells[upper].0 - wells[lower].0) * f, wells[lower].1 + (wells[upper].1 - wells[lower].1) * f)
        let away = Ease.inOut((t - 2.0) / 0.4)
        if away < 1 {
            let tip = (at.0 + 0.3 * away, at.1 - 0.4 * away)
            var cone = u.polyline([(tip.0 - 0.02, tip.1 - 0.16), (tip.0, tip.1), (tip.0 + 0.02, tip.1 - 0.16)])
            cone.closeSubpath()
            context.fill(cone, with: .color(tint))
        }
    }
}

/// A dose series across a 12-well plate: the multichannel adds more clay drug
/// column by column, and the cells thin out where the dose is high.
enum TwelveWellDose {
    static let duration = 5.0
    private static let doses = [0.1, 0.3, 0.55, 0.85]
    private static let survival = [1.0, 0.75, 0.35, 0.08]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        CulturePlate.draw(context, u, tint: tint)
        let kill = Ease.inOut((t - 2.0) / 2.2)
        for col in 0..<4 {
            let dosed = Ease.clamp((t - 0.4 - 0.35 * Double(col)) / 0.25)
            for row in 0..<3 {
                let w = (0.23 + 0.18 * Double(col), 0.31 + 0.19 * Double(row))
                if dosed > 0 { context.fill(u.circle(w.0, w.1, 0.075), with: .color(clay.opacity(doses[col] * 0.6 * dosed))) }
                u.stroke(context, u.circle(w.0, w.1, 0.075), tint, 0.022)
                let alive = 1 - (1 - survival[col]) * kill
                CulturePlate.cells(context, u, at: w, r: 0.075, count: Int(26 * alive), seed: Double(col * 3 + row) * 50, color: tint)
            }
        }
        // The multichannel's three tips, stepping across the columns.
        let step = min(3, max(0, (t - 0.3) / 0.35))
        let away = Ease.inOut((t - 1.8) / 0.4)
        if away < 1 {
            let x = 0.23 + 0.18 * step + 0.2 * away
            for row in 0..<3 {
                let y = 0.31 + 0.19 * Double(row) - 0.3 * away
                var cone = u.polyline([(x - 0.015, y - 0.1), (x, y), (x + 0.015, y - 0.1)])
                cone.closeSubpath()
                context.fill(cone, with: .color(tint))
            }
            u.stroke(context, u.line((x, 0.21 - 0.3 * away), (x, 0.11 - 0.3 * away)), tint, 0.04)
        }
    }
}

/// A scratch assay in a 24-well plate: a tip drags a clean line through each
/// confluent well, and the cells crawl in until the clay wound closes.
enum ScratchAssay {
    static let duration = 5.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        CulturePlate.draw(context, u, tint: tint)
        let close = Ease.inOut((t - 2.2) / 2.4)
        for row in 0..<4 {
            for col in 0..<6 {
                let w = (0.19 + 0.13 * Double(col), 0.28 + 0.14 * Double(row))
                let r = 0.058
                let order = Double(row * 6 + col)
                let scratched = t > 0.3 + 0.06 * order
                var well = context
                well.clip(to: u.circle(w.0, w.1, r))
                // Confluent cells either side of the wound, which narrows shut.
                let gap = scratched ? 0.05 * (1 - close) : 0
                let top = u.pt(0, w.1 - r).y, height = u.len(2 * r)
                well.fill(Path(CGRect(x: u.pt(w.0 - r, 0).x, y: top, width: u.len(r - gap / 2), height: height)), with: .color(tint.opacity(0.5)))
                well.fill(Path(CGRect(x: u.pt(w.0 + gap / 2, 0).x, y: top, width: u.len(r - gap / 2), height: height)), with: .color(tint.opacity(0.5)))
                if gap > 0.001 {
                    well.fill(Path(CGRect(x: u.pt(w.0 - gap / 2, 0).x, y: top, width: u.len(gap), height: height)), with: .color(clay.opacity(0.7)))
                }
                u.stroke(context, u.circle(w.0, w.1, r), tint, 0.018)
            }
        }
        // The scratching tip, working through the wells in order.
        let reach = (t - 0.3) / 0.06
        if reach >= 0, reach < 24 {
            let order = Int(reach), f = reach - Double(order)
            let x = 0.19 + 0.13 * Double(order % 6)
            let y = 0.28 + 0.14 * Double(order / 6) - 0.05 + 0.1 * f
            u.stroke(context, u.line((x, y - 0.12), (x, y)), tint, 0.03)
            context.fill(u.circle(x, y, 0.01), with: .color(clay))
        }
    }
}
