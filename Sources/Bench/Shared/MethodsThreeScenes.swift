// MethodsThreeScenes.swift
// ScienceStatus — more ways of looking and measuring: the patch pipette,
// the sequencer's flow cell, the AFM tip, the light sheet and the TLC
// plate. Each draws in a unit square (see `UnitSquare`): instruments and
// traces in the tint, the seal, the signal and the sample in clay.

import SwiftUI

/// Patch clamp: the pipette comes in to the cell, its test pulses shrink
/// as the clay seal forms, and on breaking in the whole-cell transients
/// spring up on the trace.
enum PatchClamp {
    static let duration = 4.8
    private static let contact = (0.52, 0.29), axis = -25.0 * .pi / 180

    private static func current(_ s: Double) -> Double {
        let phase = s.truncatingRemainder(dividingBy: 0.4)
        let on = phase < 0.2 ? 1.0 : 0.0
        let open = 1 - Ease.inOut((s - 1.1) / 0.3)
        if s < 2.2 { return on * (0.08 * open + 0.004) }
        let edge = phase < 0.2 ? phase : phase - 0.2
        let sign = phase < 0.2 ? 1.0 : -1.0
        return sign * 0.1 * exp(-edge / 0.02) + on * 0.01
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = (0.36, 0.36)
        let broken = t > 2.2
        var outline = Path()
        let contactAngle = atan2(contact.1 - centre.1, contact.0 - centre.0)
        let gap = broken ? 0.12 : 0.0
        outline.addArc(center: u.pt(centre.0, centre.1), radius: u.len(0.18), startAngle: .radians(contactAngle + gap),
                       endAngle: .radians(contactAngle - gap + 2 * .pi), clockwise: false)
        context.fill(u.circle(centre.0, centre.1, 0.18), with: .color(tint.opacity(0.1)))
        u.stroke(context, outline, tint, 0.03)
        context.fill(u.circle(centre.0 - 0.03, centre.1 + 0.02, 0.05), with: .color(tint.opacity(0.4)))
        let approach = Ease.inOut((t - 0.2) / 0.9)
        let back = 0.22 * (1 - approach)
        let tip = (contact.0 + cos(axis) * back, contact.1 + sin(axis) * back)
        let far = (tip.0 + cos(axis) * 0.5, tip.1 + sin(axis) * 0.5)
        let n = (-sin(axis), cos(axis))
        u.stroke(context, u.line((tip.0 + n.0 * 0.008, tip.1 + n.1 * 0.008), (far.0 + n.0 * 0.05, far.1 + n.1 * 0.05)), tint, 0.022)
        u.stroke(context, u.line((tip.0 - n.0 * 0.008, tip.1 - n.1 * 0.008), (far.0 - n.0 * 0.05, far.1 - n.1 * 0.05)), tint, 0.022)
        u.stroke(context, u.line((tip.0 + cos(axis) * 0.12, tip.1 + sin(axis) * 0.12), far), tint.opacity(0.6), 0.012)
        let seal = Ease.clamp((t - 1.2) / 0.3)
        if seal > 0 { u.stroke(context, u.circle(contact.0, contact.1, 0.025), clay.opacity(seal), 0.02) }
        let flash = sin(.pi * Ease.clamp((t - 2.2) / 0.3))
        if flash > 0 { context.fill(Sparkles.star(u, contact.0, contact.1, 0.05 * flash), with: .color(clay)) }
        // The current trace, scrolling.
        u.stroke(context, u.line((0.06, 0.8), (0.94, 0.8)), tint.opacity(0.25), 0.012)
        let trace = stride(from: max(0, t - 2.4), through: t, by: 0.005).map { s in (0.94 - 0.88 * (t - s) / 2.4, 0.8 - 1.2 * current(s)) }
        if trace.count > 1 { u.stroke(context, u.polyline(trace), broken ? clay : tint, 0.02) }
    }
}

/// Sequencing by synthesis: the clusters on the flow cell light up together
/// each cycle, one of four marks for each base, and one cluster's read
/// builds, a base a cycle, down the side.
enum Illumina {
    static let duration = 4.8
    private static let cycle = 0.7

    private static func mark(_ context: GraphicsContext, _ u: UnitSquare, _ base: Int, at p: (Double, Double), r: Double, alpha: Double, tint: Color) {
        switch base {
        case 0: context.fill(u.circle(p.0, p.1, r), with: .color(clay.opacity(alpha)))
        case 1: context.fill(u.circle(p.0, p.1, r), with: .color(tint.opacity(alpha)))
        case 2: u.stroke(context, u.circle(p.0, p.1, r * 0.8), clay.opacity(alpha), 0.018)
        default: u.stroke(context, u.circle(p.0, p.1, r * 0.8), tint.opacity(alpha), 0.018)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.36, 0.5, 0.56, 0.84, corner: 0.06), tint, 0.03)
        let n = max(0, Int((t - 0.3) / cycle))
        let local = t - 0.3 - Double(n) * cycle
        let glow = t > 0.3 ? 1 - Ease.clamp(local / 0.55) : 0
        func cluster(_ row: Int, _ col: Int) -> (Double, Double) {
            let s = Double(row * 4 + col)
            return (0.18 + 0.12 * Double(col) + 0.02 * (BenchShapes.rand(s) - 0.5), 0.17 + 0.11 * Double(row) + 0.02 * (BenchShapes.rand(s + 3) - 0.5))
        }
        for row in 0..<7 {
            for col in 0..<4 {
                let p = cluster(row, col)
                u.stroke(context, u.circle(p.0, p.1, 0.034), tint.opacity(0.25), 0.014)
                if glow > 0 {
                    let base = Int(BenchShapes.rand(Double(row * 4 + col) * 13 + Double(n)) * 4)
                    mark(context, u, base, at: p, r: 0.032, alpha: glow, tint: tint)
                }
            }
        }
        let chosen = cluster(3, 1)
        u.stroke(context, u.circle(chosen.0, chosen.1, 0.054), clay, 0.018)
        let read = min(6, t > 0.3 ? n + 1 : 0)
        for k in 0..<read {
            let base = Int(BenchShapes.rand(Double(3 * 4 + 1) * 13 + Double(k)) * 4)
            mark(context, u, base, at: (0.82, 0.16 + 0.12 * Double(k)), r: 0.04, alpha: 1, tint: tint)
        }
    }
}

/// Atomic force microscopy: the cantilever's tip rasters across the surface,
/// riding up over whatever is there, and line by line the image above
/// fills in until a clay strand of DNA lies revealed.
enum AFMScan {
    static let duration = 5.0
    private static let rows = 14
    private static let rowTime = 0.24
    private static let strand: [(Double, Double)] = Smooth.curve([(0.2, 0.14), (0.34, 0.3), (0.5, 0.2), (0.62, 0.36), (0.78, 0.26), (0.72, 0.46)], samples: 8)

    /// Where the strand crosses the scan line at height `y`.
    private static func crossings(at y: Double) -> [Double] {
        zip(strand, strand.dropFirst()).compactMap { a, b in
            guard (a.1 - y) * (b.1 - y) <= 0, a.1 != b.1 else { return nil }
            return a.0 + (b.0 - a.0) * (y - a.1) / (b.1 - a.1)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let progress = max(0, (t - 0.3) / rowTime)
        let row = min(Double(rows), progress)
        let scanned = 0.08 + 0.42 * row / Double(rows)
        u.stroke(scene, u.capsule(0.5, 0.29, 0.74, 0.44, corner: 0.01), tint.opacity(0.5), 0.015)
        var image = scene
        image.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, 0.07).y, width: u.side, height: u.len(scanned - 0.07))))
        image.fill(u.capsule(0.5, 0.29, 0.74, 0.44, corner: 0.01), with: .color(tint.opacity(0.12)))
        u.stroke(image, u.polyline(strand), clay, 0.03)
        // The side view: surface, the strand's bumps on this line, the tip.
        let y = scanned
        let bumps = crossings(at: y)
        let within = progress - floor(progress)
        let forward = Int(progress) % 2 == 0
        let x = row < Double(rows) ? 0.14 + 0.72 * (forward ? within : 1 - within) : 0.86
        // Where the tip is, on the image it is making.
        if row < Double(rows) {
            u.stroke(scene, u.line((0.14, y), (0.86, y)), tint.opacity(0.5), 0.012)
            scene.fill(u.circle(x, y, 0.02), with: .color(tint))
        }
        func height(_ x: Double) -> Double { bumps.reduce(0) { $0 + 0.035 * exp(-pow(($1 - x) / 0.02, 2)) } }
        let surface = stride(from: 0.1, through: 0.9, by: 0.01).map { sx in (sx, 0.82 - height(sx)) }
        u.stroke(scene, u.polyline(surface), tint, 0.03)
        for b in bumps { scene.fill(u.ellipse(b, 0.82 - 0.012, 0.03, 0.026), with: .color(clay)) }
        let tipY = 0.8 - height(x)
        var tip = u.polyline([(x - 0.025, tipY - 0.06), (x, tipY), (x + 0.025, tipY - 0.06)])
        tip.closeSubpath()
        scene.fill(tip, with: .color(tint))
        u.stroke(scene, u.line((x - 0.02, tipY - 0.07), (0.96, tipY - 0.09)), tint, 0.03)
    }
}

/// Light-sheet microscopy: a clay sheet of light, pinched to its waist at
/// the embryo, sweeps down through it and lights one row of cells at a
/// time, while the recorded slices stack up alongside into its outline.
enum LightSheet {
    static let duration = 4.6
    private static let centre = (0.44, 0.56), radius = 0.27
    private static let top = centre.1 - radius + 0.05, depth = 2 * radius - 0.1

    /// The embryo's cells, packed in staggered rows inside its edge.
    private static let cells: [(Double, Double)] = (0..<7).flatMap { row -> [(Double, Double)] in
        let y = centre.1 - 0.234 + 0.078 * Double(row)
        return (-3...3).map { col in (centre.0 + 0.09 * Double(col) + (row % 2 == 0 ? 0 : 0.045), y) }
            .filter { hypot($0.0 - centre.0, $0.1 - centre.1) < radius - 0.045 }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sweep = Ease.inOut((t - 0.3) / 3.4)
        let y = top + depth * sweep
        let on = t > 0.3 && t < 3.8
        if on {
            var sheet = u.polyline([(0.08, y - 0.045), (centre.0, y - 0.012), (0.78, y - 0.04),
                                    (0.78, y + 0.04), (centre.0, y + 0.012), (0.08, y + 0.045)])
            sheet.closeSubpath()
            context.fill(sheet, with: .color(clay.opacity(0.3)))
        }
        for c in cells {
            if on && abs(c.1 - y) < 0.039 {
                context.fill(u.circle(c.0, c.1, 0.034), with: .color(clay))
            } else {
                u.stroke(context, u.circle(c.0, c.1, 0.034), tint.opacity(0.5), 0.018)
            }
        }
        u.stroke(context, u.circle(centre.0, centre.1, radius), tint, 0.035)
        // The illumination objective rides with the sheet; the detection
        // objective looks down from above.
        context.fill(u.capsule(0.05, y, 0.07, 0.13, corner: 0.015), with: .color(tint))
        context.fill(u.capsule(centre.0, 0.13, 0.15, 0.1, corner: 0.02), with: .color(tint))
        // The slices recorded so far, each as wide as the embryo was there.
        let planes = Int(sweep * 11)
        for k in 0...planes where sweep > 0 {
            let py = top + depth * Double(k) / 11
            let dy = (py - centre.1) / radius
            let half = 0.075 * sqrt(max(0, 1 - dy * dy))
            u.stroke(context, u.line((0.89 - half, py), (0.89 + half, py)), tint.opacity(0.75), 0.022)
        }
    }
}

/// Thin-layer chromatography: the solvent climbs the plate, and the single
/// spotted mixture pulls apart into three spots at their own fractions of
/// the front, which are then marked off.
enum TLCPlate {
    static let duration = 4.8
    private static let fractions = [0.25, 0.55, 0.82]
    private static let origin = 0.76

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.2, 0.08), (0.2, 0.92), (0.8, 0.92), (0.8, 0.08)), tint.opacity(0.6), 0.025)
        scene.fill(u.capsule(0.5, 0.88, 0.56, 0.07, corner: 0.01), with: .color(tint.opacity(0.2)))
        let front = 0.8 - (0.8 - 0.18) * Ease.out((t - 0.4) / 2.8)
        scene.fill(u.capsule(0.5, (front + 0.86) / 2, 0.3, 0.86 - front, corner: 0.005), with: .color(tint.opacity(0.1)))
        u.stroke(scene, u.capsule(0.5, 0.48, 0.32, 0.8, corner: 0.01), tint, 0.03)
        scene.stroke(u.line((0.37, origin), (0.63, origin)), with: .color(tint.opacity(0.5)),
                     style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.015), u.len(0.012)]))
        let marked = Ease.clamp((t - 3.4) / 0.4)
        for (k, rf) in fractions.enumerated() {
            let travel = max(0, origin - front)
            let y = origin - rf * travel
            let stretch = 0.012 + 0.012 * rf * Ease.clamp(travel / 0.5)
            let color: Color = k == 0 ? clay : (k == 1 ? clay.opacity(0.6) : tint)
            scene.fill(u.ellipse(0.5, y, 0.06, 0.04 + stretch), with: .color(color))
            if marked > 0 { u.stroke(scene, u.ellipse(0.5, y, 0.1, 0.08 + stretch), tint.opacity(marked), 0.012) }
        }
        if marked > 0 { u.stroke(scene, u.line((0.36, front), (0.64, front)), tint.opacity(marked), 0.015) }
    }
}
