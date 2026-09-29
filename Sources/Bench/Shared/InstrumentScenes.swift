// InstrumentScenes.swift
// ScienceStatus — lab scenes at the instruments. Each draws in a unit
// square (see `UnitSquare`): the instrument in the tint, the sample and
// the signal in clay.

import SwiftUI

/// Column chromatography: one clay band runs down the column and pulls
/// apart into two, while eluent drips from the tip.
enum Column {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.4, 0.06), (0.4, 0.78), (0.47, 0.86), (0.47, 0.92)), tint, 0.05)
        u.stroke(context, u.line((0.6, 0.06), (0.6, 0.78), (0.53, 0.86), (0.53, 0.92)), tint, 0.05)
        let run = Ease.inOut((t - 0.3) / 3.1)
        for stop in [0.66, 0.42] {
            let y = 0.14 + (stop - 0.14) * run
            u.stroke(context, u.line((0.44, y), (0.56, y)), clay, 0.05)
        }
        for k in 0..<5 {
            let age = (t - 0.4 - 0.9 * Double(k)) / 0.5
            guard age > 0, age < 1 else { continue }
            context.fill(u.circle(0.5, 0.93 + 0.06 * age * age, 0.022), with: .color(tint.opacity(1 - age)))
        }
    }
}

/// A plate reader: its head scans the wells row by row, and each lights
/// in clay as it is read, leaving a small heat map.
enum PlateReader {
    static let duration = 3.6
    private static let columns = [0.23, 0.41, 0.59, 0.77], rows = [0.33, 0.5, 0.67]
    private static let values = [0.35, 0.8, 0.5, 1.0, 0.65, 0.3, 0.9, 0.45, 0.7, 0.4, 0.95, 0.55]
    /// The wells in reading order: along each row, back along the next.
    private static let order: [(Double, Double)] = rows.enumerated().flatMap { r, y in
        (r % 2 == 0 ? columns : columns.reversed()).map { ($0, y) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.5, 0.88, 0.64, corner: 0.06), tint, 0.05)
        let step = 0.26
        for (i, well) in order.enumerated() {
            let lit = Ease.out((t - 0.2 - step * Double(i)) / 0.2)
            if lit > 0 { context.fill(u.circle(well.0, well.1, 0.065), with: .color(clay.opacity(values[i] * lit))) }
            u.stroke(context, u.circle(well.0, well.1, 0.065), tint.opacity(0.55), 0.035)
        }
        let at = (t - 0.2) / step
        let i = max(0, min(order.count - 1, Int(floor(at))))
        let next = min(order.count - 1, i + 1)
        let k = Ease.inOut(max(0, min(1, (at - Double(i) - 0.5) * 2)))
        let head = (order[i].0 + (order[next].0 - order[i].0) * k, order[i].1 + (order[next].1 - order[i].1) * k)
        u.stroke(context, u.circle(head.0, head.1, 0.09), tint, 0.04)
    }
}

/// Focusing a microscope: out of focus, each cell is a spread of ghost
/// outlines; they close in, overshoot a touch, and settle into crisp cells
/// whose clay nuclei then appear.
enum Microscope {
    static let duration = 3.6
    private static let cells: [(x: Double, y: Double, r: Double)] = [
        (0.36, 0.38, 0.09), (0.6, 0.34, 0.075), (0.62, 0.61, 0.1), (0.37, 0.64, 0.07),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.42), tint, 0.06)
        let focus = Ease.outBack((t - 0.4) / 1.3)
        let blur = abs(1 - focus)
        for (i, c) in cells.enumerated() {
            if blur > 0.02 {
                for k in 0..<3 {
                    let a = Double(k) * 2 * .pi / 3 + Double(i)
                    u.stroke(context, u.circle(c.x + 0.05 * blur * cos(a), c.y + 0.05 * blur * sin(a), c.r * (1 + 0.3 * blur)),
                             tint.opacity(0.35 + 0.4 * (1 - blur)), 0.04)
                }
            } else {
                u.stroke(context, u.circle(c.x, c.y, c.r), tint, 0.05)
            }
            let nucleus = Ease.outBack((t - 1.8 - 0.1 * Double(i)) / 0.3)
            if nucleus > 0 { context.fill(u.circle(c.x, c.y, c.r * 0.35 * nucleus), with: .color(clay)) }
        }
    }
}

/// Flow cytometry: cells run single file down the stream past the laser;
/// each flashes as it crosses and lands as a dot on the plot beside it,
/// and two populations build up, the bright ones in clay.
enum FlowCytometry {
    static let duration = 4.0
    private static let bright = [true, false, false, true, false, true, false, false, true, false, true, false, true, false]
    /// Where each cell's dot lands: bright ones up and right.
    private static let dots: [(Double, Double)] = bright.enumerated().map { k, lit in
        let jx = BenchShapes.rand(Double(k) * 3.3) - 0.5, jy = BenchShapes.rand(Double(k) * 7.1) - 0.5
        return lit ? (0.8 + 0.14 * jx, 0.4 + 0.14 * jy) : (0.6 + 0.14 * jx, 0.72 + 0.1 * jy)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.13, 0.02), (0.13, 0.98)), tint.opacity(0.45), 0.03)
        u.stroke(context, u.line((0.29, 0.02), (0.29, 0.98)), tint.opacity(0.45), 0.03)
        u.stroke(context, u.line((0.02, 0.5), (0.36, 0.5)), clay, 0.035)
        u.stroke(context, u.line((0.44, 0.16), (0.44, 0.9), (0.96, 0.9)), tint, 0.04)
        let fade = 1 - Ease.inOut((t - 3.6) / 0.35)
        for (k, lit) in bright.enumerated() {
            let crossing = 0.3 + 0.23 * Double(k)
            let y = 0.5 + 0.9 * (t - crossing)
            if y > -0.06, y < 1.06 {
                let flash = max(0, 1 - abs(t - crossing) / 0.12)
                if flash > 0 {
                    context.fill(u.circle(0.21, y, 0.045), with: .color((lit ? clay : tint.opacity(0.5)).opacity(flash)))
                }
                u.stroke(context, u.circle(0.21, y, 0.04), tint, 0.035)
            }
            let dot = Ease.outBack((t - crossing) / 0.25)
            if dot > 0 {
                context.fill(u.circle(dots[k].0, dots[k].1, 0.036 * dot), with: .color((lit ? clay : tint).opacity(fade)))
            }
        }
    }
}

/// Cell sorting: droplets leave the nozzle single file and cross the
/// laser; the fluorescent ones light up clay, and between the plates they
/// swing left into one tube while the rest carry on right into the other.
enum FACS {
    static let duration = 4.0
    private static let sorted = [true, false, false, true, false, true, true, false]
    private static let laser = 0.27

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var nozzle = u.line((0.44, 0.04), (0.56, 0.04), (0.52, 0.14), (0.48, 0.14))
        nozzle.closeSubpath()
        context.fill(nozzle, with: .color(tint))
        u.stroke(context, u.line((0.02, laser), (0.6, laser)), clay.opacity(0.9), 0.03)
        for x in [0.36, 0.64] { u.stroke(context, u.line((x, 0.38), (x, 0.56)), tint, 0.05) }
        for x in [0.28, 0.72] {
            var tube = Path()
            tube.move(to: u.pt(x - 0.07, 0.76))
            tube.addLine(to: u.pt(x - 0.07, 0.88))
            tube.addQuadCurve(to: u.pt(x + 0.07, 0.88), control: u.pt(x, 0.97))
            tube.addLine(to: u.pt(x + 0.07, 0.76))
            u.stroke(context, tube, tint, 0.05)
        }
        for (k, yes) in sorted.enumerated() {
            let age = t - 0.2 - 0.42 * Double(k)
            guard age > 0, age < 1.0 else { continue }
            let target = yes ? 0.28 : 0.72
            let p: (Double, Double)
            if age < 0.5 {
                p = (0.5, 0.14 + 0.31 * age / 0.5)
            } else {
                let s = (age - 0.5) / 0.5
                let a = (0.5, 0.45), c = (0.5, 0.62), b = (target, 0.84)
                p = ((1 - s) * (1 - s) * a.0 + 2 * (1 - s) * s * c.0 + s * s * b.0,
                     (1 - s) * (1 - s) * a.1 + 2 * (1 - s) * s * c.1 + s * s * b.1)
            }
            // Lit once it has crossed the laser, if it is fluorescent.
            let lit = yes && p.1 >= laser
            if lit {
                let flash = 1 - Ease.clamp((p.1 - laser) / 0.12)
                if flash > 0 { u.stroke(context, u.circle(p.0, p.1, 0.05 + 0.04 * (1 - flash)), clay.opacity(flash), 0.03) }
            }
            context.fill(u.circle(p.0, p.1, 0.035), with: .color(lit ? clay : tint))
        }
    }
}

/// A western transfer: bands leave the gel sideways, one after another,
/// and land on the membrane beside it, the current running across.
enum WesternTransfer {
    static let duration = 3.6
    private static let bands = [0.26, 0.4, 0.52, 0.7]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.27, 0.5, 0.34, 0.76, corner: 0.03), tint, 0.05)
        context.fill(u.capsule(0.73, 0.5, 0.34, 0.76, corner: 0.03), with: .color(tint.opacity(0.12)))
        u.stroke(context, u.capsule(0.73, 0.5, 0.34, 0.76, corner: 0.03), tint, 0.05)
        for y in [0.33, 0.63] {
            let k = (t / 0.6).truncatingRemainder(dividingBy: 1)
            let x = 0.47 + 0.05 * k
            u.stroke(context, u.line((x - 0.02, y - 0.025), (x, y), (x - 0.02, y + 0.025)), tint.opacity(1 - k), 0.035)
        }
        for (i, y) in bands.enumerated() {
            let move = Ease.inOut((t - 0.4 - 0.25 * Double(i)) / 1.4)
            let x = 0.27 + (0.73 - 0.27) * move
            u.stroke(context, u.line((x - 0.08, y), (x + 0.08, y)), clay, 0.06)
        }
    }
}

/// A crystal growing: a clay seed, then facets, layer on layer, each
/// earlier face left as a faint growth ring, and a small glint at the end.
enum Crystal {
    static let duration = 4.0
    private static let sizes = [0.1, 0.16, 0.23, 0.3, 0.37]
    private static let times = [0.5, 1.0, 1.5, 2.0, 2.5]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        func hexagon(_ r: Double) -> Path {
            var path = u.polyline(Rings.hexagon((0.5, 0.5), r))
            path.closeSubpath()
            return path
        }
        var current = 0.05
        for (i, s) in sizes.enumerated() {
            let grow = Ease.outBack((t - times[i]) / 0.3)
            guard grow > 0 else { break }
            let previous = i == 0 ? 0.05 : sizes[i - 1]
            if grow >= 1, i < sizes.count - 1, t > times[i + 1] {
                u.stroke(context, hexagon(s), tint.opacity(0.3), 0.035)
            }
            current = previous + (s - previous) * grow
        }
        for v in Rings.hexagon((0.5, 0.5), current) {
            u.stroke(context, u.line((0.5, 0.5), v), tint.opacity(0.4), 0.035)
        }
        u.stroke(context, hexagon(current), tint, 0.06)
        var seed = u.polyline(Rings.hexagon((0.5, 0.5), 0.05))
        seed.closeSubpath()
        context.fill(seed, with: .color(clay))

        let glint = (t - 3.0) / 0.7
        if glint > 0, glint < 1 {
            let v = Rings.hexagon((0.5, 0.5), current)[1]
            context.fill(Sparkles.star(u, v.0, v.1, 0.08 * sin(.pi * glint)), with: .color(clay))
        }
    }
}

/// A magnetic bead pull: a clay magnet slides up to the tube and the
/// beads, jostling at first, snap across to its wall in a clean wave,
/// nearest first.
enum MagneticBeads {
    static let duration = 3.6
    private static let beads: [(Double, Double)] = [
        (0.34, 0.24), (0.47, 0.3), (0.38, 0.4), (0.5, 0.48), (0.33, 0.55),
        (0.44, 0.6), (0.36, 0.72), (0.49, 0.74), (0.41, 0.84), (0.46, 0.18), (0.35, 0.33),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.42, 0.52, 0.26, 0.8, corner: 0.1), tint, 0.05)

        let slide = Ease.out((t - 0.5) / 0.5)
        var magnet = Path()
        let dx = 0.22 * (1 - slide)
        magnet.move(to: u.pt(0.66 + dx, 0.38))
        magnet.addLine(to: u.pt(0.8 + dx, 0.38))
        magnet.addArc(center: u.pt(0.8 + dx, 0.52), radius: u.len(0.14),
                      startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        magnet.addLine(to: u.pt(0.66 + dx, 0.66))
        u.stroke(context, magnet, clay, 0.09)

        for (i, b) in beads.enumerated() {
            let distance = hypot(0.66 - b.0, 0.52 - b.1)
            let pull = Ease.outBack((t - 1.0 - 1.4 * (distance - 0.15)) / 0.35)
            let spot = (0.52 - 0.03 * Double(i % 2), 0.4 + 0.024 * Double(i))
            let jostle = (0.008 * sin(t * 5 + Double(i) * 2), 0.008 * sin(t * 4 + Double(i) * 3))
            let from = (b.0 + jostle.0, b.1 + jostle.1)
            context.fill(u.circle(from.0 + (spot.0 - from.0) * pull, from.1 + (spot.1 - from.1) * pull, 0.028),
                         with: .color(tint))
        }
    }
}

/// A spectrophotometer: a clay beam crosses the cuvette while its sample
/// darkens, the light getting through dims, and the absorbance trace
/// below rises and levels off.
enum Spectrophotometer {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let s = Ease.inOut((t - 0.4) / 2.6)
        let absorbance = 1 - exp(-3 * s)

        context.fill(u.capsule(0.12, 0.26, 0.12, 0.14, corner: 0.02), with: .color(tint))
        context.fill(u.capsule(0.88, 0.26, 0.12, 0.14, corner: 0.02), with: .color(tint))
        context.fill(u.capsule(0.5, 0.28, 0.12, 0.18, corner: 0.01), with: .color(clay.opacity(0.15 + 0.6 * absorbance)))
        u.stroke(context, u.capsule(0.5, 0.26, 0.16, 0.26, corner: 0.02), tint, 0.045)
        u.stroke(context, u.line((0.18, 0.26), (0.42, 0.26)), clay, 0.04)
        u.stroke(context, u.line((0.58, 0.26), (0.82, 0.26)), clay.opacity(1 - 0.75 * absorbance), 0.04)

        u.stroke(context, u.line((0.14, 0.5), (0.14, 0.9), (0.9, 0.9)), tint, 0.045)
        if s > 0 {
            let trace = stride(from: 0.0, through: 1.0, by: 0.02).map { (x: Double) -> (Double, Double) in
                let rise: Double = 1 - exp(-3 * x)
                return (0.16 + 0.72 * x, 0.88 - 0.32 * rise)
            }
            u.stroke(context, u.polyline(trace).trimmedPath(from: 0, to: s), clay, 0.055)
        }
    }
}

/// A streak plate: the loop streaks inoculum across the agar in three
/// zigzags, each thinner, and clay colonies grow up along them, crowded
/// at first and single by the last.
enum StreakPlate {
    static let duration = 4.0
    private static let path: [(Double, Double)] = [
        (0.3, 0.2), (0.7, 0.24), (0.3, 0.28), (0.68, 0.32), (0.34, 0.35),
        (0.6, 0.3), (0.8, 0.42), (0.62, 0.45), (0.8, 0.53), (0.66, 0.57),
        (0.72, 0.52), (0.56, 0.76), (0.47, 0.62), (0.37, 0.8), (0.28, 0.66),
    ]
    private static let colonies: [(k: Double, size: Double)] = [
        (0.03, 0.02), (0.07, 0.02), (0.11, 0.022), (0.15, 0.02), (0.19, 0.022), (0.23, 0.02), (0.27, 0.02),
        (0.4, 0.025), (0.47, 0.025), (0.55, 0.028), (0.62, 0.028), (0.74, 0.035), (0.86, 0.035), (0.96, 0.038),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.circle(0.5, 0.5, 0.39), with: .color(tint.opacity(0.1)))
        u.stroke(context, u.circle(0.5, 0.5, 0.42), tint, 0.06)

        let streak = Ease.inOut((t - 0.2) / 2.2)
        if streak > 0 { u.stroke(context, u.polyline(path).trimmedPath(from: 0, to: streak), clay.opacity(0.75), 0.028) }
        for (i, c) in colonies.enumerated() {
            let grow = Ease.outBack((t - 2.5 - 0.05 * Double(i)) / 0.3)
            guard grow > 0 else { continue }
            let p = Polyline.point(path, at: c.k)
            context.fill(u.circle(p.0 + 0.01 * sin(Double(i) * 3), p.1 + 0.01 * cos(Double(i) * 5), c.size * grow),
                         with: .color(clay))
        }
        if streak > 0, streak < 1 {
            let tip = Polyline.point(path, at: streak)
            u.stroke(context, u.line(tip, (tip.0 + 0.2, tip.1 - 0.2)), tint, 0.03)
            u.stroke(context, u.circle(tip.0, tip.1, 0.022), tint, 0.03)
        }
    }
}

/// A serial dilution: every tube but the first starts with clear diluent;
/// the pipette dips into the clay stock, carries a little into the next
/// tube and lets it go, the tube turns a paler clay, and on down the row.
enum SerialDilution {
    static let duration = 4.2
    private static let tubes = [0.14, 0.32, 0.5, 0.68, 0.86]
    private static let strength = [1.0, 0.62, 0.38, 0.22, 0.11]
    private static let step = 0.85

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for (i, x) in tubes.enumerated() {
            let mixed = i == 0 ? 1 : Ease.inOut((t - 0.25 - step * Double(i - 1) - 0.62) / 0.3)
            let outline = u.line((x - 0.055, 0.56), (x - 0.055, 0.78), (x - 0.015, 0.88), (x + 0.015, 0.88),
                                 (x + 0.055, 0.78), (x + 0.055, 0.56))
            var body = outline
            body.closeSubpath()
            var liquid = context
            liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, 0.66).y, width: u.side, height: u.side)))
            // Clear diluent, turning clay as the transfer mixes in.
            liquid.fill(body, with: .color(tint.opacity(0.2 * (1 - mixed))))
            liquid.fill(body, with: .color(clay.opacity(strength[i] * mixed)))
            u.stroke(context, outline, tint, 0.045)
        }

        // The pipette: into tube k, up, over to tube k + 1, in, out.
        var x = tubes[0], dip = 0.0, emptied = 1.0, press = 0.0
        for k in 0..<4 {
            let s = 0.25 + step * Double(k)
            guard t >= s else { break }
            let move = Ease.inOut((t - s - 0.25) / 0.25)
            x = tubes[k] + (tubes[k + 1] - tubes[k]) * move
            dip = Keyframes.value(t, [(s, 0), (s + 0.08, 1), (s + 0.18, 1), (s + 0.25, 0),
                                      (s + 0.5, 0), (s + 0.56, 1), (s + 0.68, 1), (s + 0.76, 0)])
            emptied = Keyframes.value(t, [(s + 0.08, 1), (s + 0.18, 0.35), (s + 0.58, 0.35), (s + 0.66, 1)])
            press = Keyframes.value(t, [(s + 0.06, 0), (s + 0.08, 1), (s + 0.18, 0), (s + 0.58, 0), (s + 0.62, 1), (s + 0.68, 0)])
        }
        var pipette = context
        let anchor = u.pt(0.5, 0), target = u.pt(x, 0.2 + 0.1 * dip)
        pipette.translateBy(x: target.x, y: target.y)
        pipette.scaleBy(x: 0.42, y: 0.42)
        pipette.translateBy(x: -anchor.x, y: -anchor.y)
        Pipette.drawInstrument(in: pipette, u, tint: tint, press: press, emptied: emptied)
    }
}

/// A vortex mixer: the tube on its cup shakes in a tight circle, its clay
/// liquid pulled down into a vortex, then it stops and settles.
enum Vortex {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.capsule(0.5, 0.84, 0.6, 0.16, corner: 0.05), with: .color(tint))
        context.fill(u.ellipse(0.5, 0.74, 0.2, 0.06), with: .color(tint))
        let on = Ease.clamp((t - 0.4) / 0.2) * (1 - Ease.clamp((t - 2.6) / 0.3))
        let spin = t * 2 * .pi * 9
        let offset = (0.012 * cos(spin) * on, 0.006 * sin(spin) * on)
        let depth = 0.1 * on

        var tube = context
        tube.translateBy(x: u.len(offset.0), y: u.len(offset.1))
        let left = 0.43, right = 0.57, top = 0.16, bottom = 0.7
        var liquid = Path()
        liquid.move(to: u.pt(left + 0.01, 0.48))
        liquid.addLine(to: u.pt(0.5, 0.48 + depth))
        liquid.addLine(to: u.pt(right - 0.01, 0.48))
        liquid.addLine(to: u.pt(right - 0.01, bottom - 0.05))
        liquid.addQuadCurve(to: u.pt(left + 0.01, bottom - 0.05), control: u.pt(0.5, bottom + 0.02))
        liquid.closeSubpath()
        tube.fill(liquid, with: .color(clay))
        var glass = Path()
        glass.move(to: u.pt(left, top))
        glass.addLine(to: u.pt(left, bottom - 0.05))
        glass.addQuadCurve(to: u.pt(right, bottom - 0.05), control: u.pt(0.5, bottom + 0.03))
        glass.addLine(to: u.pt(right, top))
        u.stroke(tube, glass, tint, 0.045)

        if on > 0.5 {
            for side in [-1.0, 1.0] {
                var arc = Path()
                arc.addArc(center: u.pt(0.5, 0.72), radius: u.len(0.17), startAngle: .degrees(side > 0 ? -20 : 160),
                           endAngle: .degrees(side > 0 ? 20 : 200), clockwise: false)
                u.stroke(context, arc, tint.opacity(0.5 * on), 0.03)
            }
        }
    }
}

/// A haemocytometer count under the microscope: the counting grid, cells
/// scattered on it, each turning clay as it is counted, in reading order.
enum Hemocytometer {
    static let duration = 3.6
    private static let cells: [(Double, Double)] = [
        (0.33, 0.3), (0.46, 0.34), (0.62, 0.29), (0.7, 0.4), (0.56, 0.45), (0.38, 0.44),
        (0.3, 0.58), (0.47, 0.6), (0.64, 0.57), (0.72, 0.68), (0.53, 0.71), (0.36, 0.7),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.43), tint, 0.06)
        for k in 0...4 {
            let v = 0.26 + 0.12 * Double(k)
            let heavy = k == 0 || k == 4
            u.stroke(context, u.line((v, 0.26), (v, 0.74)), tint.opacity(heavy ? 0.9 : 0.45), heavy ? 0.04 : 0.025)
            u.stroke(context, u.line((0.26, v), (0.74, v)), tint.opacity(heavy ? 0.9 : 0.45), heavy ? 0.04 : 0.025)
        }
        for (i, c) in cells.enumerated() {
            let counted = Ease.outBack((t - 0.5 - 0.2 * Double(i)) / 0.2)
            if counted > 0 { context.fill(u.circle(c.0, c.1, 0.03 * counted), with: .color(clay)) }
            u.stroke(context, u.circle(c.0, c.1, 0.03), tint, 0.03)
        }
    }
}
