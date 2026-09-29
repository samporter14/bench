// WetLabScenes.swift
// ScienceStatus — the wet lab, week in, week out: gel extraction, sealing a
// plate, scraping a glycerol stock, spread and bead plating, a Coomassie
// destain, a Bradford assay, a colony formation assay, a Gram stain, replica
// plating and sorting flies. Each draws in a unit square (see `UnitSquare`):
// kit in the tint, the sample, the stain or the thing selected in clay.

import SwiftUI

/// Gel extraction: on the blue-light box the scalpel cuts round the one clay
/// band wanted, and the slice is lifted out into a tube, leaving its hole.
enum GelExtraction {
    static let duration = 5.0
    private static let lanes = [0.22, 0.36, 0.5, 0.64, 0.78]
    private static let target = (0.5, 0.62)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.capsule(0.5, 0.6, 0.8, 0.56, corner: 0.02), with: .color(tint.opacity(0.1)))
        u.stroke(context, u.capsule(0.5, 0.6, 0.8, 0.56, corner: 0.02), tint, 0.025)
        let lift = Ease.inOut((t - 2.6) / 0.9)
        for (k, x) in lanes.enumerated() {
            context.fill(u.capsule(x, 0.37, 0.08, 0.025, corner: 0.006), with: .color(tint.opacity(0.5)))
            let bands: [Double] = k == 0 ? [0.44, 0.5, 0.56, 0.62, 0.7, 0.8] : [0.5 + 0.04 * Double(k), 0.62 + (k == 2 ? 0 : 0.08)]
            for y in bands {
                let isTarget = k == 2 && abs(y - target.1) < 0.001
                if isTarget && lift > 0 { continue }
                context.fill(u.capsule(x, y, 0.08, 0.018, corner: 0.006), with: .color(clay.opacity(isTarget ? 1 : 0.6)))
            }
        }
        // The cut: four strokes round the band, the scalpel on the go.
        let cut = Ease.clamp((t - 0.5) / 1.8)
        let box = [(target.0 - 0.06, target.1 - 0.03), (target.0 + 0.06, target.1 - 0.03), (target.0 + 0.06, target.1 + 0.03), (target.0 - 0.06, target.1 + 0.03), (target.0 - 0.06, target.1 - 0.03)]
        if cut > 0 {
            let path = u.polyline(box).trimmedPath(from: 0, to: cut)
            u.stroke(context, path, tint, 0.014)
        }
        if lift > 0 {
            context.fill(u.capsule(target.0, target.1, 0.12, 0.06, corner: 0.006), with: .color(Color.black.opacity(0.35)))
            u.stroke(context, u.capsule(target.0, target.1, 0.12, 0.06, corner: 0.006), tint.opacity(0.6), 0.012)
            // The slice, on its way to the tube.
            let p = (target.0 + (0.8 - target.0) * lift, target.1 + (0.16 - target.1) * lift)
            if lift < 1 {
                context.fill(u.capsule(p.0, p.1, 0.12 * (1 - 0.4 * lift), 0.06, corner: 0.006), with: .color(tint.opacity(0.35)))
                context.fill(u.capsule(p.0, p.1, 0.08 * (1 - 0.4 * lift), 0.018, corner: 0.006), with: .color(clay))
            }
        }
        // The tube waiting at the top right, clay once the slice is in.
        u.stroke(context, u.line((0.74, 0.06), (0.74, 0.18), (0.8, 0.26), (0.86, 0.18), (0.86, 0.06)), tint, 0.02)
        if lift >= 1 { context.fill(u.capsule(0.8, 0.18, 0.05, 0.04, corner: 0.01), with: .color(clay)) }
        // The scalpel.
        let index = min(3, Int(cut * 4))
        let a = box[index], b = box[index + 1]
        let f = cut * 4 - Double(index)
        let tip = t < 2.4 ? (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f) : (target.0 + 0.3 * lift, target.1 - 0.3 * lift - 0.1)
        var blade = u.polyline([tip, (tip.0 + 0.02, tip.1 - 0.08), (tip.0 + 0.05, tip.1 - 0.07)])
        blade.closeSubpath()
        context.fill(blade, with: .color(tint))
        u.stroke(context, u.line((tip.0 + 0.035, tip.1 - 0.075), (tip.0 + 0.1, tip.1 - 0.24)), tint, 0.035)
    }
}

/// Sealing a plate: the film goes on over the clay samples and the roller
/// runs across it, pressing it flat well by well.
enum PlateSealing {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.54, 0.84, 0.56, corner: 0.02), tint, 0.03)
        let roll = Ease.inOut((t - 1.0) / 2.6)
        let front = 0.1 + 0.8 * roll
        for row in 0..<8 {
            for col in 0..<12 {
                let x = 0.16 + 0.062 * Double(col), y = 0.32 + 0.063 * Double(row)
                context.fill(u.circle(x, y, 0.016), with: .color(clay.opacity(0.8)))
                u.stroke(context, u.circle(x, y, 0.024), tint.opacity(x < front ? 0.8 : 0.35), 0.01)
            }
        }
        // The film: laid on, rippled until the roller has pressed it.
        let laid = Ease.inOut((t - 0.2) / 0.6)
        if laid > 0 {
            context.fill(u.capsule(0.5, 0.54 - 0.3 * (1 - laid), 0.8, 0.52, corner: 0.012), with: .color(tint.opacity(0.14)))
            for k in 0..<4 where laid >= 1 {
                let y = 0.36 + 0.12 * Double(k)
                let wave = stride(from: max(front, 0.1), through: 0.9, by: 0.01).map { x in (x, y + 0.008 * sin(x * 60 + Double(k))) }
                if wave.count > 1 { u.stroke(context, u.polyline(wave), tint.opacity(0.35), 0.01) }
            }
        }
        // The roller.
        if laid >= 1, t < 4.1 {
            context.fill(u.capsule(front, 0.54, 0.05, 0.56, corner: 0.025), with: .color(tint))
            u.stroke(context, u.line((front, 0.26), (front + 0.1, 0.1)), tint, 0.03)
        }
    }
}

/// Scraping a glycerol stock: the tip scratches a little from the frozen clay
/// stock in its frosted vial, never letting it thaw, and swirls it into the
/// culture tube.
enum GlycerolStock {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The cryovial, frosted, with the frozen stock.
        u.stroke(context, u.capsule(0.32, 0.64, 0.14, 0.4, corner: 0.03), tint, 0.03)
        context.fill(u.capsule(0.32, 0.43, 0.18, 0.06, corner: 0.012), with: .color(tint))
        context.fill(u.capsule(0.32, 0.74, 0.1, 0.18, corner: 0.02), with: .color(clay.opacity(0.85)))
        for k in 0..<10 {
            let s = Double(k)
            let side = k % 2 == 0 ? -1.0 : 1.0
            let y = 0.5 + 0.34 * BenchShapes.rand(s * 2.9)
            let x = 0.32 + side * 0.07
            u.stroke(context, u.line((x, y), (x + side * 0.025, y - 0.01)), tint.opacity(0.6), 0.01)
        }
        // Cold breath curling off the top once the cap is off.
        for k in 0..<3 {
            let s = (t * 0.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            context.fill(u.circle(0.3 + 0.04 * sin(s * 5 + Double(k)), 0.62 - 0.2 * s, 0.02 + 0.02 * s), with: .color(tint.opacity(0.18 * (1 - s))))
        }
        // The culture tube on the right.
        u.stroke(context, u.capsule(0.72, 0.66, 0.12, 0.36, corner: 0.05), tint, 0.03)
        let broth = Ease.clamp((t - 3.4) / 0.8)
        context.fill(u.capsule(0.72, 0.74, 0.08, 0.18, corner: 0.03), with: .color(tint.opacity(0.18)))
        if broth > 0 { context.fill(u.capsule(0.72, 0.74, 0.08, 0.18, corner: 0.03), with: .color(clay.opacity(0.35 * broth))) }
        // The tip: down to scrape, across, down to swirl.
        let x = Keyframes.value(t, [(1.5, 0.32), (2.3, 0.72)])
        let depth = Keyframes.value(t, [(0.3, 0), (0.7, 1), (1.3, 1), (1.6, 0), (2.4, 0), (2.8, 0.9), (3.6, 0.9), (4.0, 0)])
        let tipY = 0.4 + 0.24 * depth
        let wiggle = (t > 0.7 && t < 1.3) ? 0.012 * sin(t * 40) : ((t > 2.8 && t < 3.6) ? 0.018 * sin(t * 12) : 0)
        u.stroke(context, u.line((x + wiggle - 0.012, tipY - 0.2), (x + wiggle, tipY), (x + wiggle + 0.012, tipY - 0.2)), tint, 0.022)
        if t > 1.0 && t < 3.2 { context.fill(u.circle(x + wiggle, tipY - 0.01, 0.01), with: .color(clay)) }
    }
}

/// Spread plating: a clay drop in the middle of the plate, the turntable
/// spinning, the L-shaped spreader working it out to the edge, then the
/// colonies coming up evenly.
enum SpreadPlating {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let spin = Ease.inOut((t - 0.4) / 0.4) * (1 - Ease.inOut((t - 2.6) / 0.4))
        let turned = t * 4 * spin
        // The turntable under the plate, its one clay notch going round.
        context.fill(u.circle(0.5, 0.52, 0.43), with: .color(tint.opacity(0.14)))
        context.fill(u.circle(0.5 + 0.395 * cos(turned), 0.52 + 0.395 * sin(turned), 0.018), with: .color(clay))
        u.stroke(context, u.circle(0.5, 0.52, 0.34), tint, 0.03)
        // The culture spreading from the drop.
        let spread = Ease.out((t - 0.6) / 1.9)
        context.fill(u.circle(0.5, 0.52, 0.03 + 0.28 * spread), with: .color(clay.opacity(0.4 - 0.25 * spread)))
        // Colonies, evenly once it dries.
        let grow = Ease.out((t - 3.0) / 1.4)
        for k in 0..<40 where grow > 0 {
            let s = Double(k)
            let a = BenchShapes.rand(s * 2.1) * 2 * .pi
            let r = 0.3 * BenchShapes.rand(s * 3.9).squareRoot()
            context.fill(u.circle(0.5 + r * cos(a), 0.52 + r * sin(a), 0.012 * grow), with: .color(tint))
        }
        // The spreader: its foot flat on the agar, the handle bent up and
        // away off the plate, held still while the plate turns under it.
        let down = Ease.inOut((t - 0.3) / 0.4) * (1 - Ease.inOut((t - 2.6) / 0.4))
        if down > 0.01 {
            let lift = 0.25 * (1 - down)
            let foot = [(0.3, 0.6 - lift), (0.6, 0.6 - lift)]
            u.stroke(context, u.line(foot[0], foot[1]), tint, 0.04)
            u.stroke(context, u.line(foot[1], (0.72, 0.5 - lift), (0.96, 0.08 - lift)), tint, 0.03)
        }
    }
}

/// Bead plating: the plate is shaken and glass beads roll back and forth,
/// leaving clay trails of culture, are tipped off, and colonies follow.
enum BeadPlating {
    static let duration = 4.8
    private static let beads = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let shake = 0.04 * sin(t * 9) * (t > 0.3 && t < 2.8 ? 1 : 0)
        let c = (0.5 + shake, 0.52)
        u.stroke(context, u.circle(c.0, c.1, 0.36), tint, 0.03)
        let roll = Ease.clamp((t - 0.3) / 2.5)
        let off = Ease.inOut((t - 2.9) / 0.5)
        var dish = context
        dish.clip(to: u.circle(c.0, c.1, 0.35))
        for k in 0..<beads {
            let s = Double(k)
            // Each bead's track: back and forth across the plate.
            let track = stride(from: 0.0, through: roll, by: 0.02).map { v -> (Double, Double) in
                (c.0 + 0.26 * sin(v * 9 + s * 2.1), c.1 + 0.26 * cos(v * 5 + s * 1.3))
            }
            if track.count > 1 { dish.stroke(u.polyline(track), with: .color(clay.opacity(0.3)), lineWidth: u.len(0.03)) }
            guard off < 1 else { continue }
            let at = track.last ?? (c.0, c.1)
            let p = (at.0 + (0.9 - at.0) * off, at.1)
            dish.fill(u.circle(p.0, p.1, 0.032), with: .color(tint))
            dish.fill(u.circle(p.0 - 0.01, p.1 - 0.01, 0.008), with: .color(Color.black.opacity(0.25)))
        }
        let grow = Ease.out((t - 3.4) / 1.2)
        for k in 0..<34 where grow > 0 {
            let s = Double(k)
            let a = BenchShapes.rand(s * 5.1) * 2 * .pi
            let r = 0.3 * BenchShapes.rand(s * 7.7).squareRoot()
            context.fill(u.circle(c.0 + r * cos(a), c.1 + r * sin(a), 0.012 * grow), with: .color(tint))
        }
    }
}

/// A Coomassie destain: the gel starts solid clay on its rocking tray, the
/// background clears, and the bands stay; the knotted wipe drinks the dye.
enum CoomassieDestain {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rock = 0.03 * sin(t * 2.2)
        var tray = context
        let centre = u.pt(0.5, 0.56)
        tray.translateBy(x: centre.x, y: centre.y)
        tray.rotate(by: .radians(rock))
        tray.translateBy(x: -centre.x, y: -centre.y)
        tray.stroke(u.capsule(0.5, 0.56, 0.86, 0.66, corner: 0.04), with: .color(tint), lineWidth: u.len(0.03))
        let clear = Ease.inOut((t - 0.4) / 3.6)
        let gel = u.capsule(0.46, 0.56, 0.56, 0.5, corner: 0.012)
        tray.fill(gel, with: .color(clay.opacity(0.9 - 0.8 * clear)))
        tray.stroke(gel, with: .color(tint.opacity(0.5)), lineWidth: u.len(0.012))
        for (k, x) in [0.26, 0.36, 0.46, 0.56, 0.66].enumerated() {
            let bands: [Double] = k == 0 ? [0.38, 0.44, 0.5, 0.58, 0.68, 0.78] : [0.42 + 0.03 * Double(k), 0.56, 0.7 - 0.02 * Double(k)]
            for y in bands {
                tray.fill(u.capsule(x, y, 0.07, 0.016, corner: 0.005), with: .color(clay))
            }
        }
        // The destain sloshing, and the wipe knot taking up dye.
        let slosh = stride(from: 0.1, through: 0.9, by: 0.01).map { x in (x, 0.28 + 0.01 * sin(x * 20 - t * 4)) }
        tray.stroke(u.polyline(slosh), with: .color(tint.opacity(0.4)), lineWidth: u.len(0.012))
        tray.fill(u.circle(0.83, 0.56, 0.05), with: .color(tint))
        tray.fill(u.circle(0.83, 0.56, 0.035), with: .color(clay.opacity(0.9 * clear)))
    }
}

/// A Bradford assay: the dye goes into the standards and they turn from pale
/// to deep clay with the protein; the points fall on a line, and the unknown
/// is read off it.
enum BradfordAssay {
    static let duration = 5.0
    private static let standards = [0.0, 0.15, 0.3, 0.45, 0.6, 0.75]
    private static let unknown = 0.52

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The wells: six standards and the unknown.
        let levels = standards + [unknown]
        for (k, level) in levels.enumerated() {
            let x = 0.14 + 0.12 * Double(k)
            let dyed = Ease.clamp((t - 0.3 - 0.15 * Double(k)) / 0.4)
            context.fill(u.circle(x, 0.18, 0.045), with: .color(clay.opacity((0.12 + 0.85 * level) * dyed)))
            u.stroke(context, u.circle(x, 0.18, 0.045), k == levels.count - 1 ? clay : tint, 0.018)
        }
        // The plot.
        u.stroke(context, u.line((0.12, 0.36), (0.12, 0.88), (0.9, 0.88)), tint, 0.022)
        for (k, level) in standards.enumerated() {
            let appear = Ease.outBack((t - 1.5 - 0.15 * Double(k)) / 0.3)
            guard appear > 0 else { continue }
            let p = (0.16 + 0.95 * level, 0.86 - 0.62 * level)
            context.fill(u.circle(p.0, p.1, 0.018 * appear), with: .color(tint))
        }
        let fit = Ease.inOut((t - 2.6) / 0.6)
        if fit > 0 {
            u.stroke(context, u.line((0.14, 0.87), (0.14 + 0.74 * fit, 0.87 - 0.48 * fit)), tint.opacity(0.6), 0.014)
        }
        // Reading the unknown off the line.
        let read = Ease.inOut((t - 3.3) / 0.8)
        if read > 0 {
            let y = 0.86 - 0.62 * unknown
            let x = 0.16 + 0.95 * unknown
            let dash = StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.02), u.len(0.014)])
            context.stroke(u.line((0.12, y), (0.12 + (x - 0.12) * read, y)), with: .color(clay), style: dash)
            if read >= 1 {
                context.stroke(u.line((x, y), (x, 0.88)), with: .color(clay), style: dash)
                context.fill(u.circle(x, y, 0.02), with: .color(clay))
            }
        }
    }
}

/// A colony formation assay: single cells in a 6-well plate grow into
/// colonies, fewer as the dose rises across the plate, then crystal violet
/// stains them clay.
enum ColonyFormation {
    static let duration = 5.0
    private static let wells: [(Double, Double)] = [0.36, 0.64].flatMap { y in [0.27, 0.5, 0.73].map { x in (x, y) } }
    private static let counts = [14, 12, 9, 6, 3, 1]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var body = u.polyline([(0.1, 0.18), (0.86, 0.18), (0.9, 0.22), (0.9, 0.82), (0.1, 0.82)])
        body.closeSubpath()
        u.stroke(context, body, tint, 0.03)
        let grow = Ease.out((t - 0.4) / 2.6)
        let stain = Ease.inOut((t - 3.2) / 0.6)
        for (k, w) in wells.enumerated() {
            u.stroke(context, u.circle(w.0, w.1, 0.1), tint, 0.022)
            if stain > 0 { context.fill(u.circle(w.0, w.1, 0.1), with: .color(clay.opacity(0.12 * stain))) }
            for j in 0..<counts[k] {
                let s = Double(k * 20 + j)
                let a = BenchShapes.rand(s * 2.3) * 2 * .pi
                let r = 0.075 * BenchShapes.rand(s * 4.1).squareRoot()
                let blob = 0.004 + 0.016 * grow * (0.6 + 0.4 * BenchShapes.rand(s * 6.7))
                let colour = stain > 0 ? clay.opacity(0.4 + 0.6 * stain) : tint
                context.fill(u.circle(w.0 + r * cos(a), w.1 + r * sin(a), blob), with: .color(colour))
            }
        }
    }
}

/// A Gram stain on a slide of rods and cocci: crystal violet stains them all,
/// iodine fixes it, the alcohol rinse strips the rods, and safranin stains
/// them the second colour. Gram-positive cocci stay clay.
enum GramStain {
    static let duration = 5.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.6, 0.84, 0.44, corner: 0.02), tint, 0.03)
        // The four steps, one dropper each.
        let step = min(4, max(0, Int((t - 0.3) / 1.1) + 1))
        let local = t - 0.3 - Double(step - 1) * 1.1
        let violet = Ease.clamp((t - 0.6) / 0.4)
        let rinse = Ease.clamp((t - 2.9) / 0.4)
        let counter = Ease.clamp((t - 4.0) / 0.4)
        for k in 0..<10 {
            let s = Double(k)
            let p = (0.2 + 0.1 * Double(k % 5) * 1.3 + 0.03 * BenchShapes.rand(s * 2.1), 0.5 + 0.2 * Double(k / 5) + 0.04 * BenchShapes.rand(s * 3.3))
            let coccus = k % 2 == 0
            if coccus {
                context.fill(u.circle(p.0 - 0.02, p.1, 0.026), with: .color(clay.opacity(0.25 + 0.75 * violet)))
                context.fill(u.circle(p.0 + 0.025, p.1, 0.026), with: .color(clay.opacity(0.25 + 0.75 * violet)))
            } else {
                let stained = violet * (1 - rinse)
                let rod = u.capsule(p.0, p.1, 0.1, 0.036, corner: 0.018)
                context.fill(rod, with: .color(clay.opacity(0.25 * (1 - violet) + stained)))
                context.fill(rod, with: .color(tint.opacity(0.75 * counter)))
                u.stroke(context, rod, tint.opacity(0.5), 0.01)
            }
        }
        // The dropper for this step, a drop falling.
        if t > 0.3 && t < 4.7 {
            let x = 0.3 + 0.12 * Double(step - 1)
            context.fill(u.capsule(x, 0.12, 0.05, 0.14, corner: 0.02), with: .color(tint))
            u.stroke(context, u.line((x, 0.19), (x, 0.26)), tint, 0.02)
            let fall = Ease.clamp(local / 0.4)
            if fall < 1 { context.fill(u.circle(x, 0.28 + 0.14 * fall * fall, 0.014), with: .color(step == 3 ? tint.opacity(0.6) : clay)) }
        }
        // Progress: four dots, one per step.
        for k in 0..<4 {
            context.fill(u.circle(0.74 + 0.045 * Double(k), 0.12, 0.012), with: .color(k < step ? clay : tint.opacity(0.3)))
        }
    }
}

/// Replica plating: the velvet block takes an imprint of the master plate's
/// colonies and prints it onto a selective plate, where some fail to grow.
enum ReplicaPlating {
    static let duration = 5.0
    private static let colonies: [(Double, Double)] = (0..<12).map { k in
        let s = Double(k)
        let a = BenchShapes.rand(s * 2.7) * 2 * .pi
        let r = 0.11 * BenchShapes.rand(s * 4.9).squareRoot()
        return (r * cos(a), r * sin(a))
    }
    private static let failing: Set<Int> = [2, 5, 9]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let master = (0.26, 0.64), replica = (0.74, 0.64)
        for plate in [master, replica] { u.stroke(context, u.circle(plate.0, plate.1, 0.16), tint, 0.03) }
        for c in colonies { context.fill(u.circle(master.0 + c.0, master.1 + c.1, 0.018), with: .color(tint)) }
        // The block: down onto the master, up and across, down onto the replica.
        let x = Keyframes.value(t, [(1.4, master.0), (2.3, replica.0)])
        let press = Keyframes.value(t, [(0.3, 0), (0.8, 1), (1.1, 1), (1.4, 0), (2.3, 0), (2.8, 1), (3.1, 1), (3.4, 0)])
        let inked = t > 0.9
        let printed = t > 2.9
        // What grows on the replica afterwards: all but the failing ones.
        let grow = Ease.out((t - 3.5) / 0.9)
        for (k, c) in colonies.enumerated() where printed {
            let p = (replica.0 + c.0, replica.1 + c.1)
            if failing.contains(k) {
                if grow > 0 { context.stroke(u.circle(p.0, p.1, 0.022), with: .color(clay.opacity(grow)), style: StrokeStyle(lineWidth: u.len(0.01), dash: [u.len(0.012), u.len(0.01)])) }
            } else {
                context.fill(u.circle(p.0, p.1, 0.008 + 0.01 * grow), with: .color(tint))
            }
        }
        let y = 0.3 + 0.2 * press
        context.fill(u.capsule(x, y - 0.08, 0.1, 0.14, corner: 0.02), with: .color(tint))
        context.fill(u.capsule(x, y + 0.01, 0.3, 0.04, corner: 0.02), with: .color(tint.opacity(0.7)))
        if inked, !printed || press > 0 {
            for c in colonies { context.fill(u.circle(x + c.0, y + 0.03, 0.008), with: .color(clay)) }
        }
    }
}

/// Pushing flies: asleep on the CO₂ pad, they are brushed into two piles,
/// the curly-winged balancer flies (clay wings) to one side.
enum FlyPushing {
    static let duration = 5.0
    private static let flies: [(x: Double, y: Double, curly: Bool, turn: Double)] = (0..<10).map { k in
        let s = Double(k)
        return (0.3 + 0.4 * BenchShapes.rand(s * 2.3), 0.42 + 0.3 * BenchShapes.rand(s * 3.9), k % 3 != 1, BenchShapes.rand(s * 5.1) * 2 * .pi)
    }

    private static func fly(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), turn: Double, curly: Bool, tint: Color) {
        var f = context
        let at = u.pt(p.0, p.1)
        f.translateBy(x: at.x, y: at.y)
        f.rotate(by: .radians(turn))
        f.scaleBy(x: 1.35, y: 1.35)
        let wing = curly ? clay : tint.opacity(0.45)
        for side in [-1.0, 1.0] {
            if curly {
                var arc = Path()
                arc.addArc(center: CGPoint(x: -u.len(0.02), y: side * u.len(0.01)), radius: u.len(0.025),
                           startAngle: .degrees(side > 0 ? 200 : 100), endAngle: .degrees(side > 0 ? 300 : 200), clockwise: false)
                f.stroke(arc, with: .color(wing), lineWidth: max(u.len(0.014), UnitSquare.hairline))
            } else {
                f.fill(Path(ellipseIn: CGRect(x: -u.len(0.045), y: side > 0 ? 0 : -u.len(0.022), width: u.len(0.04), height: u.len(0.022))), with: .color(wing))
            }
        }
        f.fill(Path(ellipseIn: CGRect(x: -u.len(0.03), y: -u.len(0.012), width: u.len(0.05), height: u.len(0.024))), with: .color(tint))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The pad, porous, with a faint hiss of gas.
        context.fill(u.capsule(0.5, 0.58, 0.8, 0.52, corner: 0.03), with: .color(tint.opacity(0.08)))
        u.stroke(context, u.capsule(0.5, 0.58, 0.8, 0.52, corner: 0.03), tint, 0.025)
        for k in 0..<30 {
            context.fill(u.circle(0.14 + 0.72 * BenchShapes.rand(Double(k) * 1.7), 0.35 + 0.46 * BenchShapes.rand(Double(k) * 2.9), 0.005), with: .color(tint.opacity(0.3)))
        }
        u.stroke(context, u.line((0.5, 0.34), (0.5, 0.82)), tint.opacity(0.15), 0.01)
        // One fly after another is brushed to its side.
        var brush = (0.5, 0.3)
        for (k, f) in flies.enumerated() {
            let push = Ease.inOut((t - 0.3 - 0.4 * Double(k)) / 0.35)
            let target = (f.curly ? 0.2 : 0.8) + 0.06 * BenchShapes.rand(Double(k) * 7.3) * (f.curly ? 1 : -1)
            let p = (f.x + (target - f.x) * push, f.y)
            fly(context, u, at: p, turn: f.turn, curly: f.curly, tint: tint)
            if push > 0, push < 1 { brush = (p.0 + (f.curly ? 0.04 : -0.04), p.1) }
        }
        // The brush.
        u.stroke(context, u.line((brush.0, brush.1 - 0.02), (brush.0 + 0.12, brush.1 - 0.3)), tint, 0.03)
        var bristles = u.polyline([(brush.0 - 0.02, brush.1), (brush.0 + 0.02, brush.1), (brush.0 + 0.015, brush.1 - 0.05), (brush.0 - 0.005, brush.1 - 0.05)])
        bristles.closeSubpath()
        context.fill(bristles, with: .color(tint.opacity(0.7)))
    }
}
