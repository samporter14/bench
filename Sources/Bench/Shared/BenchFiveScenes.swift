// BenchFiveScenes.swift
// ScienceStatus — flies, slides, sections, stains, cold storage. Each draws
// in a unit square (see `UnitSquare`): kit in the tint, the living or
// stained part in clay.

import SwiftUI

/// Flipping flies: the old vial's plug comes out, it turns over onto a
/// fresh vial of clay food, two taps knock the flies down into it, and the
/// new vial is plugged.
enum FlyFlip {
    static let duration = 4.6
    private static let half = 0.08, length = 0.44

    /// A vial centred at `c`, turned `angle` degrees, with food and plug.
    private static func vial(_ context: GraphicsContext, _ u: UnitSquare, _ c: (Double, Double), angle: Double,
                             food: Double, plugged: Double, tint: Color) {
        var v = context
        let p = u.pt(c.0, c.1)
        v.translateBy(x: p.x, y: p.y)
        v.rotate(by: .degrees(angle))
        let w = u.len(half), h = u.len(length / 2)
        v.fill(Path(roundedRect: CGRect(x: -w, y: h - u.len(food), width: 2 * w, height: u.len(food)), cornerRadius: u.len(0.02)), with: .color(clay))
        var glass = Path()
        glass.move(to: CGPoint(x: -w, y: -h))
        glass.addLine(to: CGPoint(x: -w, y: h - u.len(0.02)))
        glass.addQuadCurve(to: CGPoint(x: w, y: h - u.len(0.02)), control: CGPoint(x: 0, y: h + u.len(0.02)))
        glass.addLine(to: CGPoint(x: w, y: -h))
        v.stroke(glass, with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.035), lineCap: .round, lineJoin: .round))
        if plugged > 0 {
            v.fill(Path(roundedRect: CGRect(x: -w * 1.05, y: -h - u.len(0.05) - u.len(0.1) * (1 - plugged), width: 2.1 * w, height: u.len(0.08)),
                        cornerRadius: u.len(0.02)), with: .color(tint.opacity(plugged)))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let over = Keyframes.value(t, [(0.6, 0), (1.3, 1), (2.2, 1), (2.9, 0)])
        let tap = 0.03 * (sin(.pi * Ease.clamp((t - 1.45) / 0.15)) + sin(.pi * Ease.clamp((t - 1.75) / 0.15)))
        let a = (0.28 + (0.7 - 0.28) * over, 0.68 + (0.24 - 0.68) * over + tap)
        let angle = 180 * over
        let bottle = (0.7, 0.68 + tap)
        vial(context, u, bottle, angle: 0, food: 0.1, plugged: Ease.out((t - 3.0) / 0.3), tint: tint)
        vial(context, u, a, angle: angle, food: 0.08, plugged: 1 - Ease.clamp((t - 0.3) / 0.25), tint: tint)
        // The flies: in the old vial, knocked down into the new one.
        let rad = angle * .pi / 180
        for k in 0..<8 {
            let s = Double(k)
            let local = ((BenchShapes.rand(s) - 0.5) * 0.11, -0.16 + 0.24 * BenchShapes.rand(s + 20))
            let jitter = (0.01 * sin(t * 7 + s * 2), 0.01 * cos(t * 5 + s))
            let inOld = (a.0 + local.0 * cos(rad) - local.1 * sin(rad), a.1 + local.0 * sin(rad) + local.1 * cos(rad))
            let inNew = (bottle.0 + (BenchShapes.rand(s + 40) - 0.5) * 0.11, bottle.1 - 0.12 + 0.18 * BenchShapes.rand(s + 60))
            let fall = Ease.inOut((t - 1.5 - 0.04 * s) / 0.35)
            let p = (inOld.0 + (inNew.0 - inOld.0) * fall + jitter.0, inOld.1 + (inNew.1 - inOld.1) * fall + jitter.1)
            context.fill(u.circle(p.0, p.1, 0.013), with: .color(tint))
            u.stroke(context, u.line((p.0 - 0.014, p.1 - 0.012), (p.0 + 0.014, p.1 - 0.012)), tint.opacity(0.5), 0.012)
        }
    }
}

/// Mounting a coverslip: a drop of mountant goes on the clay section, the
/// coverslip is lowered from one edge, and the drop spreads flat under it
/// as a bubble works its way out.
enum CoverslipMount {
    static let duration = 4.2
    private static let deck = 0.62

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.7) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        scene.fill(u.capsule(0.5, deck + 0.035, 0.86, 0.07, corner: 0.012), with: .color(tint))
        scene.fill(u.capsule(0.52, deck - 0.01, 0.22, 0.022, corner: 0.01), with: .color(clay))
        let drop = Ease.clamp((t - 0.2) / 0.3)
        let lower = Ease.inOut((t - 0.9) / 0.9)
        let spread = Ease.clamp((lower - 0.55) / 0.45)
        if drop > 0 {
            if drop < 1 {
                scene.fill(u.circle(0.52, 0.2 + (deck - 0.24) * drop * drop, 0.035), with: .color(tint.opacity(0.35)))
            } else {
                let w = 0.1 + 0.28 * spread, h = 0.07 - 0.055 * spread
                scene.fill(u.ellipse(0.52, deck - h / 2 + 0.002, w, h), with: .color(tint.opacity(0.35)))
            }
        }
        let bubble = Ease.inOut((t - 1.9) / 0.6)
        if bubble > 0, bubble < 1 { u.stroke(scene, u.circle(0.5 + 0.2 * bubble, deck - 0.012, 0.01), tint, 0.012) }
        let hinge = (0.32, deck - 0.018)
        let a = -40 * (1 - lower) * .pi / 180
        u.stroke(scene, u.line(hinge, (hinge.0 + 0.4 * cos(a), hinge.1 + 0.4 * sin(a))), tint, 0.028)
        if lower < 1 {
            let grip = (hinge.0 + 0.4 * cos(a), hinge.1 + 0.4 * sin(a))
            u.stroke(scene, u.line(grip, (grip.0 + 0.2, grip.1 - 0.16)), tint.opacity(0.7), 0.03)
        }
    }
}

/// Into the freezer box: cryovials drop into the box's slots, the lid goes
/// on, and the box slides away into its rack in the freezer.
enum FreezerBox {
    static let duration = 4.6
    private static let slots = [0.17, 0.3, 0.43, 0.56]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.7, 0.1), (0.7, 0.9)), tint.opacity(0.5), 0.03)
        for y in [0.28, 0.46, 0.64, 0.82] { u.stroke(context, u.line((0.7, y), (0.96, y)), tint.opacity(0.5), 0.03) }
        let away = Ease.inOut((t - 2.2) / 0.7)
        let gone = Ease.inOut((t - 4.1) / 0.4)
        var box = context
        let from = u.pt(0.37, 0.7), to = u.pt(0.83, 0.55)
        box.translateBy(x: from.x + (to.x - from.x) * away, y: from.y + (to.y - from.y) * away)
        box.scaleBy(x: 1 - 0.55 * away, y: 1 - 0.55 * away)
        box.translateBy(x: -from.x, y: -from.y)
        box.opacity = 1 - gone
        for (k, x) in slots.enumerated() {
            let drop = Ease.outBack((t - 0.2 - 0.25 * Double(k)) / 0.35)
            guard drop > 0 else { continue }
            let top = 0.44 - 0.5 * (1 - min(1, drop))
            box.fill(u.capsule(x, top + 0.14, 0.07, 0.2, corner: 0.02), with: .color(tint.opacity(0.3)))
            box.fill(u.capsule(x, top + 0.02, 0.08, 0.05, corner: 0.012), with: .color(clay))
        }
        u.stroke(box, u.line((0.1, 0.56), (0.1, 0.86), (0.64, 0.86), (0.64, 0.56)), tint, 0.045)
        for x in [0.235, 0.365, 0.495] { u.stroke(box, u.line((x, 0.62), (x, 0.86)), tint.opacity(0.5), 0.02) }
        let lid = Ease.out((t - 1.4) / 0.35)
        if lid > 0 { box.fill(u.capsule(0.37, 0.53 - 0.4 * (1 - lid), 0.6, 0.06, corner: 0.02), with: .color(tint)) }
        for k in 0..<4 {
            let age = (t - 2.8 - 0.08 * Double(k)) / 0.7
            guard age > 0, age < 1 else { continue }
            u.stroke(context, u.circle(0.72 + 0.05 * Double(k % 2), 0.5 - 0.1 * age + 0.03 * Double(k), 0.015 + 0.015 * age),
                     tint.opacity(0.6 * (1 - age)), 0.02)
        }
    }
}

/// Scraping a dish: the scraper sweeps down the clay monolayer in three
/// passes, heaping the cells at the rim, and the lawn grows back.
enum DishScrape {
    static let duration = 4.4
    private static let passes = [0.34, 0.5, 0.66]

    private static func swept(_ k: Int, _ t: Double) -> Double { 0.14 + 0.7 * Ease.inOut((t - 0.3 - 0.9 * Double(k)) / 0.7) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let regrow = Ease.inOut((t - 3.8) / 0.5)
        var y = 0.16
        var row = 0
        while y < 0.86 {
            var x = 0.14 + (row % 2 == 0 ? 0 : 0.025)
            while x < 0.87 {
                if hypot(x - 0.5, y - 0.5) < 0.35 {
                    var cleared = false
                    for (k, px) in passes.enumerated() where abs(x - px) < 0.08 && y < swept(k, t) { cleared = true }
                    let alpha = cleared ? regrow : 1
                    if alpha > 0 { context.fill(u.circle(x, y, 0.012), with: .color(clay.opacity(alpha))) }
                }
                x += 0.05
            }
            y += 0.045
            row += 1
        }
        for (k, px) in passes.enumerated() {
            let heap = Ease.clamp((swept(k, t) - 0.3) / 0.54) * (1 - regrow)
            if heap > 0 { context.fill(u.ellipse(px, 0.84, 0.12 * heap, 0.05 * heap), with: .color(clay)) }
        }
        u.stroke(context, u.circle(0.5, 0.5, 0.4), tint, 0.045)
        for (k, px) in passes.enumerated() {
            let start = 0.3 + 0.9 * Double(k)
            guard t > start - 0.15, t < start + 0.85 else { continue }
            let y = swept(k, t)
            u.stroke(context, u.line((px - 0.08, y), (px + 0.08, y)), tint, 0.035)
            u.stroke(context, u.line((px, y), (px + 0.16, y - 0.5)), tint, 0.04)
        }
    }
}

/// A plaque assay: stain floods each well of the plate in turn, showing
/// the clear plaques in the clay lawn, fewer down the dilutions, and the
/// ones in a well get counted.
enum PlaqueAssay {
    static let duration = 4.4
    private static let counts = [34, 16, 8, 4, 2, 1]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.9) / 0.4)
        u.stroke(context, u.capsule(0.5, 0.51, 0.9, 0.62, corner: 0.05), tint, 0.045)
        for (w, count) in counts.enumerated() {
            let c = (0.22 + 0.28 * Double(w % 3), 0.36 + 0.3 * Double(w / 3))
            let stain = Ease.inOut((t - 0.3 - 0.25 * Double(w)) / 0.5) * (1 - fade)
            if stain > 0 {
                context.drawLayer { layer in
                    layer.fill(u.circle(c.0, c.1, 0.115), with: .color(clay.opacity(stain)))
                    layer.blendMode = .destinationOut
                    for k in 0..<count {
                        let s = Double(w * 50 + k)
                        let r = 0.09 * sqrt(BenchShapes.rand(s)), a = 2 * .pi * BenchShapes.rand(s + 7)
                        layer.fill(u.circle(c.0 + r * cos(a), c.1 + r * sin(a), 0.01 + 0.008 * BenchShapes.rand(s + 3)), with: .color(.black))
                    }
                }
            }
            u.stroke(context, u.circle(c.0, c.1, 0.12), tint, 0.03)
            // Counting the plaques in the fourth well.
            if w == 3 {
                for k in 0..<count where t > 2.5 + 0.3 * Double(k) {
                    let s = Double(w * 50 + k)
                    let r = 0.09 * sqrt(BenchShapes.rand(s)), a = 2 * .pi * BenchShapes.rand(s + 7)
                    u.stroke(context, u.circle(c.0 + r * cos(a), c.1 + r * sin(a), 0.028), tint.opacity(1 - fade), 0.018)
                }
            }
        }
    }
}

/// Staining slides: the rack dips through the jars — alcohol, clay stain,
/// water — bobbing in each, and the slides come out stained.
enum SlideStaining {
    static let duration = 4.8
    private static let jars = [0.2, 0.5, 0.8]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for (k, x) in jars.enumerated() {
            let jar = u.line((x - 0.11, 0.5), (x - 0.11, 0.9), (x + 0.11, 0.9), (x + 0.11, 0.5))
            BenchShapes.fill(context, u, jar, from: 0.6, k == 1 ? clay.opacity(0.85) : tint.opacity(0.15))
        }
        let x = Keyframes.value(t, [(1.2, 0.2), (1.5, 0.5), (2.7, 0.5), (3.0, 0.8), (4.2, 0.8), (4.6, 0.2)])
        let bottom = Keyframes.value(t, [
            (0.2, 0.44), (0.45, 0.84), (0.65, 0.78), (0.8, 0.84), (1.0, 0.84), (1.2, 0.44),
            (1.5, 0.44), (1.75, 0.84), (2.45, 0.84), (2.7, 0.44),
            (3.0, 0.44), (3.25, 0.84), (3.55, 0.78), (3.7, 0.84), (3.95, 0.84), (4.2, 0.44),
        ])
        let stained = Ease.inOut((t - 1.8) / 0.4) * (1 - Ease.inOut((t - 4.3) / 0.3))
        for dx in [-0.035, 0.035] {
            context.fill(u.capsule(x + dx, bottom - 0.17, 0.028, 0.34, corner: 0.006), with: .color(tint.opacity(0.5)))
            if stained > 0 { context.fill(u.capsule(x + dx, bottom - 0.08, 0.028, 0.16, corner: 0.006), with: .color(clay.opacity(stained))) }
        }
        u.stroke(context, u.line((x - 0.08, bottom - 0.34), (x + 0.08, bottom - 0.34)), tint, 0.04)
        u.stroke(context, u.line((x, bottom - 0.34), (x, bottom - 0.44)), tint, 0.03)
        for x in jars { u.stroke(context, u.line((x - 0.11, 0.5), (x - 0.11, 0.9), (x + 0.11, 0.9), (x + 0.11, 0.5)), tint, 0.04) }
    }
}

/// A histology slide under a loupe: the lens slides along the glass from
/// the label to the clay section, and in it the tissue comes up: a gland,
/// its cells ringed round the lumen.
enum HistologySlide {
    static let duration = 4.4
    private static let tissue = (0.64, 0.5)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lens = (Keyframes.value(t, [(0.2, 0.2), (1.3, tissue.0), (3.3, tissue.0), (4.1, 0.2)]), tissue.1 + 0.02 * sin(t * 1.3))
        let r = 0.2, zoom = 4.0
        context.drawLayer { layer in
            u.stroke(layer, u.capsule(0.5, 0.5, 0.88, 0.3, corner: 0.02), tint, 0.035)
            layer.fill(u.capsule(0.17, 0.5, 0.18, 0.26, corner: 0.012), with: .color(tint.opacity(0.3)))
            var blob = u.polyline((0..<9).map { k in
                let a = Double(k) * 2 * .pi / 9
                let reach = 0.07 * (0.85 + 0.3 * BenchShapes.rand(Double(k) + 5))
                return (tissue.0 + reach * cos(a), tissue.1 + reach * 0.9 * sin(a))
            })
            blob.closeSubpath()
            layer.fill(blob, with: .color(clay))
            layer.blendMode = .destinationOut
            layer.fill(u.circle(lens.0, lens.1, r), with: .color(.black))
        }
        var view = context
        view.clip(to: u.circle(lens.0, lens.1, r))
        view.fill(u.circle(lens.0, lens.1, r), with: .color(tint.opacity(0.08)))
        func mag(_ p: (Double, Double)) -> (Double, Double) { (lens.0 + zoom * (p.0 - lens.0), lens.1 + zoom * (p.1 - lens.1)) }
        for ring in 0..<2 {
            let count = ring == 0 ? 10 : 16
            let reach = ring == 0 ? 0.028 : 0.05
            for k in 0..<count {
                let a = Double(k) * 2 * .pi / Double(count) + Double(ring) * 0.2
                let p = mag((tissue.0 + reach * cos(a), tissue.1 + reach * sin(a)))
                u.stroke(view, u.circle(p.0, p.1, zoom * (ring == 0 ? 0.008 : 0.01)), tint, 0.015)
                let n = mag((tissue.0 + (reach + 0.004) * cos(a), tissue.1 + (reach + 0.004) * sin(a)))
                view.fill(u.circle(n.0, n.1, zoom * 0.004), with: .color(clay))
            }
        }
        u.stroke(context, u.circle(lens.0, lens.1, r), tint, 0.04)
        u.stroke(context, u.line((lens.0 + r * 0.7, lens.1 + r * 0.7), (lens.0 + r * 0.7 + 0.14, lens.1 + r * 0.7 + 0.14)), tint, 0.05)
    }
}

/// A cryostat: the frozen block rides down past the blade, and each pass
/// lays a thin section with its clay tissue flat on the stage.
enum Cryosection {
    static let duration = 4.2
    private static let edge = 0.46, stage = 0.5, stroke = 1.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let cycle = t / stroke
        let phase = cycle.truncatingRemainder(dividingBy: 1)
        let down = phase < 0.5 ? Ease.inOut(phase / 0.5) : 1 - Ease.inOut((phase - 0.5) / 0.5)
        let top = 0.12 + 0.44 * down
        // The sections, each pushed along by the next.
        let cuts = Int(cycle) + (phase > 0.05 ? 1 : 0)
        for k in 0..<cuts {
            let progress = k == cuts - 1 ? Ease.clamp((phase - 0.05) / 0.45) : 1
            let shift = 0.25 * Double(cuts - 1 - k) + (k < cuts - 1 ? 0.25 * Ease.inOut((phase - 0.05) / 0.45) : 0)
            let x0 = edge + 0.01 + shift
            let w = 0.24 * progress
            guard x0 < 1 else { continue }
            context.fill(u.capsule(x0 + w / 2, stage - 0.018, w, 0.032, corner: 0.01), with: .color(tint.opacity(0.4)))
            context.fill(u.capsule(x0 + w * 0.5, stage - 0.018, w * 0.5, 0.032, corner: 0.01), with: .color(clay))
        }
        var blade = u.line((edge, stage), (0.98, stage), (0.98, stage + 0.08), (edge + 0.12, stage + 0.08))
        blade.closeSubpath()
        context.fill(blade, with: .color(tint))
        context.fill(u.capsule(0.3, top + 0.12, 0.3, 0.24, corner: 0.02), with: .color(tint.opacity(0.35)))
        context.fill(u.ellipse(0.34, top + 0.12, 0.14, 0.12), with: .color(clay))
        context.fill(u.capsule(0.2, top + 0.12, 0.12, 0.3, corner: 0.02), with: .color(tint))
    }
}

/// Checking for radioactivity: a Geiger probe sweeps the bench, and over the
/// labelled clay tube the needle leaps and it clicks.
enum Radiolabel {
    static let duration = 4.4
    private static let tube = 0.66

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.88), (0.96, 0.88)), tint, 0.04)
        let outline = BenchShapes.tube(u, x: tube, rim: 0.62, shoulder: 0.8, tip: 0.87, half: 0.06)
        BenchShapes.fill(context, u, outline, from: 0.72, clay.opacity(0.5))
        u.stroke(context, outline, tint, 0.03)
        context.fill(u.circle(tube, 0.7, 0.035), with: .color(clay))
        context.fill(u.circle(tube, 0.7, 0.006), with: .color(ivory))
        for k in 0..<3 {
            var blade = Path()
            let c = u.pt(tube, 0.7)
            let a = Double(k) * 120 - 90
            blade.move(to: c)
            blade.addArc(center: c, radius: u.len(0.028), startAngle: .degrees(a - 30), endAngle: .degrees(a + 30), clockwise: false)
            blade.closeSubpath()
            var inner = Path()
            inner.addEllipse(in: CGRect(x: c.x - u.len(0.01), y: c.y - u.len(0.01), width: u.len(0.02), height: u.len(0.02)))
            context.fill(blade.subtracting(inner), with: .color(ivory))
        }

        let x = Keyframes.value(t, [(0.2, 0.18), (1.6, tube), (2.8, tube), (3.9, 0.9)])
        let count = exp(-pow((x - tube) / 0.1, 2))
        let flicker = count * (0.85 + 0.15 * sin(t * 37))
        // The dial.
        var arc = Path()
        arc.addArc(center: u.pt(0.24, 0.34), radius: u.len(0.16), startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        u.stroke(context, arc, tint, 0.035)
        let needle = (200 + 140 * min(1, flicker)) * .pi / 180
        u.stroke(context, u.line((0.24, 0.34), (0.24 + 0.14 * cos(needle), 0.34 + 0.14 * sin(needle))), clay, 0.03)
        context.fill(u.circle(0.24, 0.34, 0.02), with: .color(tint))
        // The probe on its cable, clicking over the tube.
        var cable = Path()
        cable.move(to: u.pt(0.24, 0.36))
        cable.addQuadCurve(to: u.pt(x - 0.12, 0.5), control: u.pt(0.24, 0.52))
        u.stroke(context, cable, tint.opacity(0.5), 0.02)
        context.fill(u.capsule(x, 0.5, 0.24, 0.07, corner: 0.03), with: .color(tint))
        if count > 0.3 {
            for side in [-1.0, 1.0] where sin(t * 23 + side) > 0 {
                u.stroke(context, u.line((x + 0.14 * side, 0.44), (x + 0.18 * side, 0.4)), clay.opacity(count), 0.022)
            }
        }
    }
}

/// Filling the ice bucket: two scoops of ice tumble in and pile up, and
/// three clay-capped tubes are pushed down into it.
enum IceBucket {
    static let duration = 4.6

    private static let cubes: [(Double, Double)] = {
        var list: [(Double, Double)] = []
        var y = 0.83
        var row = 0
        while y > 0.52 {
            var x = 0.26 + (row % 2 == 0 ? 0 : 0.04)
            while x < 0.76 {
                list.append((x + 0.02 * (BenchShapes.rand(x * 9 + y) - 0.5), y))
                x += 0.08
            }
            y -= 0.065
            row += 1
        }
        return list
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.1) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let half = cubes.count / 2
        for (k, c) in cubes.enumerated() {
            let scoop = k < half ? 0.5 : 1.6
            let fall = Ease.clamp((t - scoop - 0.03 * Double(k % half)) / 0.4)
            guard fall > 0 else { continue }
            let p = (0.7 + (c.0 - 0.7) * fall, 0.2 + (c.1 - 0.2) * fall * fall)
            var cube = scene
            let at = u.pt(p.0, p.1)
            cube.translateBy(x: at.x, y: at.y)
            cube.rotate(by: .degrees(40 * BenchShapes.rand(Double(k)) - 20))
            let s = u.len(0.03)
            let shape = Path(roundedRect: CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s), cornerRadius: s * 0.35)
            cube.fill(shape, with: .color(tint.opacity(0.18)))
            cube.stroke(shape, with: .color(tint), lineWidth: u.len(0.018))
        }
        for (k, x) in [0.36, 0.5, 0.64].enumerated() {
            let push = Ease.inOut((t - 2.6 - 0.3 * Double(k)) / 0.4)
            guard push > 0 else { continue }
            let top = 0.3 + 0.14 * push - 0.3 * (1 - push)
            let outline = BenchShapes.tube(u, x: x, rim: top, shoulder: top + 0.14, tip: top + 0.2, half: 0.035)
            BenchShapes.fill(scene, u, outline, from: top + 0.08, clay.opacity(0.6))
            u.stroke(scene, outline, tint, 0.025)
            scene.fill(u.capsule(x, top - 0.01, 0.08, 0.03, corner: 0.01), with: .color(clay))
        }
        u.stroke(scene, u.line((0.18, 0.44), (0.22, 0.9), (0.78, 0.9), (0.82, 0.44)), tint, 0.055)
        // The scoop, tipping each load in.
        for s in [0.3, 1.4] {
            let tip = sin(.pi * Ease.clamp((t - s) / 0.7))
            guard tip > 0 else { continue }
            var scoop = scene
            let at = u.pt(0.74, 0.2)
            scoop.translateBy(x: at.x, y: at.y)
            scoop.rotate(by: .degrees(-70 * tip))
            scoop.stroke(Path(roundedRect: CGRect(x: -u.len(0.02), y: -u.len(0.06), width: u.len(0.16), height: u.len(0.1)), cornerRadius: u.len(0.02)),
                         with: .color(tint), lineWidth: u.len(0.03))
            var handle = Path()
            handle.move(to: CGPoint(x: u.len(0.14), y: 0))
            handle.addLine(to: CGPoint(x: u.len(0.26), y: 0))
            scoop.stroke(handle, with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.04), lineCap: .round))
        }
    }
}

/// A plate reader taking a plate: the drawer slides out, the plate is set
/// on it, it slides in, and the readout builds on the front panel.
enum PlateReaderDrawer {
    static let duration = 4.6
    private static let deck = 0.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let out = Keyframes.value(t, [(0.2, 0), (0.6, 1), (1.4, 1), (1.8, 0), (3.6, 0), (4.0, 1), (4.2, 1), (4.5, 0)])
        let placed = Ease.out((t - 0.8) / 0.35)
        let taken = Ease.inOut((t - 4.0) / 0.25)
        let tray = 0.34 - 0.3 * out
        context.fill(u.capsule(tray + 0.1, deck + 0.04, 0.3, 0.025, corner: 0.01), with: .color(tint))
        if placed > 0, taken < 1 {
            let y = deck + 0.005 - 0.3 * (1 - placed) - 0.3 * taken
            let plate = u.line((tray - 0.02, y), (tray - 0.02, y - 0.06), (tray + 0.22, y - 0.06), (tray + 0.22, y))
            u.stroke(context, plate, tint, 0.025)
            for k in 0..<6 { context.fill(u.circle(tray + 0.016 + 0.034 * Double(k), y - 0.03, 0.012), with: .color(clay)) }
        }
        context.drawLayer { layer in
            layer.fill(u.capsule(0.64, 0.5, 0.6, 0.44, corner: 0.04), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.capsule(0.36, deck + 0.02, 0.04, 0.1, corner: 0.01), with: .color(.black))
            layer.fill(u.capsule(0.68, 0.42, 0.36, 0.18, corner: 0.015), with: .color(.black))
        }
        let reading = Ease.clamp((t - 2.0) / 1.4) * (1 - Ease.clamp((t - 4.3) / 0.2))
        for k in 0..<12 {
            let col = k % 6, row = k / 6
            let lit = Ease.clamp(reading * 12 - Double(k))
            guard lit > 0 else { continue }
            let strength = 0.3 + 0.7 * BenchShapes.rand(Double(k) + 13)
            context.fill(u.capsule(0.55 + 0.052 * Double(col), 0.39 + 0.06 * Double(row), 0.04, 0.045, corner: 0.008),
                         with: .color(clay.opacity(lit * strength)))
        }
        let busy = t > 1.9 && t < 3.5
        context.fill(u.circle(0.89, 0.66, 0.018), with: .color(clay.opacity(busy && sin(t * 12) > 0 ? 1 : 0.3)))
    }
}
