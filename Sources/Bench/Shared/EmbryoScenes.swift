// EmbryoScenes.swift
// ScienceStatus — model embryos, microinjection, and a fossil. Each draws
// in a unit square (see `UnitSquare`): embryos and kit in the tint,
// nuclei, the clock, the injected dye and the fossil in clay.

import SwiftUI

/// Zebrafish somitogenesis: along the embryo's body, clay waves of the
/// segmentation clock run forward from the tail, and each one that reaches
/// the front leaves a new pair of somites behind it.
enum ZebrafishSomites {
    static let duration = 4.8
    private static let period = 0.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.ellipse(0.42, 0.7, 0.66, 0.34), tint.opacity(0.5), 0.025)
        let tail = 0.8 + 0.06 * Ease.clamp(t / duration)
        u.stroke(scene, u.capsule((0.1 + tail) / 2, 0.4, tail - 0.1 + 0.08, 0.24, corner: 0.12), tint, 0.035)
        scene.fill(u.circle(0.17, 0.37, 0.035), with: .color(tint))
        let formed = 3 + Int(t / period)
        let front = 0.27 + 0.05 * Double(formed)
        for k in 0..<formed {
            let x = 0.27 + 0.05 * Double(k)
            let fresh = k == formed - 1 ? Ease.outBack((t.truncatingRemainder(dividingBy: period)) / 0.25) : 1
            u.stroke(scene, u.line((x + 0.025, 0.32), (x - 0.012, 0.4), (x + 0.025, 0.48)), tint.opacity(fresh), 0.026)
        }
        // The clock: waves sweeping forward through the unsegmented tissue.
        let phase = (t / period).truncatingRemainder(dividingBy: 1)
        for j in 0..<2 {
            let p = (phase + Double(j) * 0.5).truncatingRemainder(dividingBy: 1)
            let x = tail - (tail - front) * p
            guard x > front - 0.01 else { continue }
            scene.fill(u.capsule(x, 0.4, 0.03 + 0.03 * (1 - p), 0.16, corner: 0.015), with: .color(clay.opacity(0.4 + 0.6 * p)))
        }
    }
}

/// Xenopus gastrulation: at the blastopore's lip, clay cells roll inwards
/// under the roof of the embryo, the gut cavity opens behind them and the
/// blastocoel shrinks away, and the lip closes round the yolk plug.
enum XenopusGastrulation {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let go = Ease.inOut((t - 0.4) / 3.2)
        let c = (0.5, 0.5), r = 0.38
        scene.fill(u.circle(c.0, c.1, r), with: .color(tint.opacity(0.1)))
        for k in 0..<14 {
            let a = (-160 + 140 * Double(k) / 13) * .pi / 180
            scene.fill(u.circle(c.0 + 0.33 * cos(a), c.1 + 0.33 * sin(a), 0.028), with: .color(tint.opacity(0.5)))
        }
        for k in 0..<5 {
            scene.fill(u.circle(0.36 + 0.07 * Double(k), 0.74 - 0.03 * sin(Double(k)), 0.05), with: .color(tint.opacity(0.35)))
        }
        // The blastocoel, shrinking as the gut cavity takes its place.
        u.stroke(scene, u.ellipse(0.46 - 0.08 * go, 0.42, 0.34 * (1 - 0.6 * go), 0.2 * (1 - 0.5 * go)), tint.opacity(0.6), 0.02)
        let lip = (0.8, 0.66)
        let gut = stride(from: 0.0, through: go, by: 0.02).map { s -> (Double, Double) in
            let a = (40 - 200 * s) * .pi / 180
            return (c.0 + 0.24 * cos(a) * (0.7 + 0.3 * s), c.1 + 0.18 * sin(a) + 0.04)
        }
        if gut.count > 1 { u.stroke(scene, u.polyline(gut), clay, 0.04) }
        for k in 0..<6 {
            let s = max(0, go - 0.08 * Double(k))
            let a = (40 - 200 * s) * .pi / 180
            let p = s > 0 ? (c.0 + 0.28 * cos(a) * (0.7 + 0.3 * s), c.1 + 0.22 * sin(a) + 0.04) : (lip.0 + 0.03 * Double(k), lip.1 + 0.02 * Double(k))
            scene.fill(u.circle(p.0, p.1, 0.022), with: .color(clay))
        }
        u.stroke(scene, u.circle(c.0, c.1, r), tint, 0.035)
        let closing = 0.12 * (1 - 0.7 * go)
        u.stroke(scene, u.line((lip.0 - closing, lip.1 + 0.1), lip, (lip.0 + 0.04, lip.1 - closing)), clay, 0.035)
    }
}

/// A fly embryo's syncytium: the clay nuclei divide in step, 1 to 2 to 4 to
/// 32, spread out to the rim, and membranes grow in between them to make
/// cells, while the pole cells bud off at the back.
enum DrosophilaSyncytium {
    static let duration = 5.0

    private static func nuclei(_ generation: Int) -> [(Double, Double)] {
        var points = [(0.5, 0.5)]
        for g in 0..<generation {
            let d = 0.16 / pow(1.35, Double(g))
            let horizontal = g % 2 == 0
            points = points.flatMap { p -> [(Double, Double)] in
                horizontal ? [(p.0 - d * 1.4, p.1), (p.0 + d * 1.4, p.1)] : [(p.0, p.1 - d * 0.7), (p.0, p.1 + d * 0.7)]
            }
        }
        return points
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let (w, h) = (0.8, 0.44)
        u.stroke(scene, u.ellipse(0.5, 0.5, w, h), tint, 0.03)
        let gen = min(5, Int(max(0, t - 0.2) / 0.45))
        let within = Ease.inOut((max(0, t - 0.2) - 0.45 * Double(gen)) / 0.3)
        let rim = Ease.inOut((t - 2.8) / 0.6)
        let before = nuclei(gen), after = nuclei(min(5, gen + 1))
        let dividing = gen < 5 && t > 0.2
        let count = dividing ? after.count : before.count
        for k in 0..<count {
            var p = dividing ? after[k] : before[k]
            if dividing {
                let parent = before[k / 2]
                p = (parent.0 + (p.0 - parent.0) * within, parent.1 + (p.1 - parent.1) * within)
            }
            // Kept inside the embryo, however far the grid spreads.
            let reach = pow((p.0 - 0.5) / (w / 2 - 0.05), 2) + pow((p.1 - 0.5) / (h / 2 - 0.045), 2)
            if reach > 1 {
                let k = 1 / sqrt(reach)
                p = (0.5 + (p.0 - 0.5) * k, 0.5 + (p.1 - 0.5) * k)
            }
            if rim > 0 {
                let a = Double(k) / Double(count) * 2 * .pi
                let edge = (0.5 + (w / 2 - 0.05) * cos(a), 0.5 + (h / 2 - 0.04) * sin(a))
                p = (p.0 + (edge.0 - p.0) * rim, p.1 + (edge.1 - p.1) * rim)
            }
            scene.fill(u.circle(p.0, p.1, 0.018), with: .color(clay))
        }
        let walls = Ease.inOut((t - 3.5) / 0.7)
        if walls > 0 {
            for k in 0..<32 {
                let a = (Double(k) + 0.5) / 32 * 2 * .pi
                let outer = (0.5 + (w / 2) * cos(a), 0.5 + (h / 2) * sin(a))
                let inner = (0.5 + (w / 2 - 0.08 * walls) * cos(a), 0.5 + (h / 2 - 0.08 * walls) * sin(a))
                u.stroke(scene, u.line(outer, inner), tint.opacity(0.7), 0.012)
            }
        }
        let poles = Ease.outBack((t - 2.4) / 0.5)
        if poles > 0 {
            // The pole cells, budding at the posterior tip.
            for k in 0..<3 { scene.fill(u.circle(0.89 + 0.012 * Double(k % 2), 0.46 + 0.04 * Double(k), 0.022 * poles), with: .color(tint)) }
        }
    }
}

/// The worm's first divisions: the clay pronuclei meet, the posterior
/// cortex is marked in clay, and the zygote splits unequally into a large
/// AB and a small P1, which then divide in turn into the four-cell diamond.
enum ElegansDivision {
    static let duration = 4.8

    private static func cell(_ context: GraphicsContext, _ u: UnitSquare, _ c: (Double, Double), _ w: Double, _ h: Double, tint: Color, posterior: Bool = false) {
        u.stroke(context, u.ellipse(c.0, c.1, w, h), tint, 0.025)
        context.fill(u.circle(c.0, c.1, 0.028), with: .color(clay))
        if posterior {
            var arc = Path()
            arc.addEllipse(in: CGRect(x: u.pt(c.0 - w / 2, 0).x, y: u.pt(0, c.1 - h / 2).y, width: u.len(w), height: u.len(h)))
            var right = context
            right.clip(to: Path(CGRect(x: u.pt(c.0 + w * 0.1, 0).x, y: u.origin.y, width: u.side, height: u.side)))
            right.stroke(arc, with: .color(clay), lineWidth: u.len(0.03))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.ellipse(0.5, 0.5, 0.84, 0.56), tint.opacity(0.4), 0.02)
        let first = Ease.inOut((t - 1.4) / 0.6)
        let ab = Ease.inOut((t - 2.4) / 0.5), p1 = Ease.inOut((t - 3.2) / 0.5)
        if first == 0 {
            let meet = Ease.inOut((t - 0.3) / 0.9)
            u.stroke(scene, u.ellipse(0.5, 0.5, 0.76, 0.48), tint, 0.025)
            var right = scene
            right.clip(to: Path(CGRect(x: u.pt(0.56, 0).x, y: u.origin.y, width: u.side, height: u.side)))
            u.stroke(right, u.ellipse(0.5, 0.5, 0.76, 0.48), clay, 0.03)
            scene.fill(u.circle(0.24 + 0.32 * meet, 0.5, 0.035), with: .color(clay))
            scene.fill(u.circle(0.8 - 0.2 * meet, 0.5, 0.035), with: .color(clay))
            if meet > 0.9 { u.stroke(scene, u.line((0.44, 0.5), (0.7, 0.5)), tint.opacity(0.6), 0.015) }
            return
        }
        // AB (anterior, larger) and P1 (posterior, smaller), then their daughters.
        let abCentre = (0.38 - 0.02 * first, 0.5), p1Centre = (0.7 + 0.02 * first, 0.5)
        if ab < 0.05 {
            cell(scene, u, abCentre, 0.44 * (0.6 + 0.4 * first), 0.46, tint: tint)
        } else {
            cell(scene, u, (abCentre.0, 0.5 - 0.12 * ab), 0.42, 0.46 - 0.22 * ab, tint: tint)
            cell(scene, u, (abCentre.0 - 0.04 * ab, 0.5 + 0.12 * ab), 0.42, 0.46 - 0.22 * ab, tint: tint)
        }
        if p1 < 0.05 {
            cell(scene, u, p1Centre, 0.3 * (0.6 + 0.4 * first), 0.36, tint: tint, posterior: true)
        } else {
            cell(scene, u, (p1Centre.0 - 0.06 * p1, 0.5 + 0.02 * p1), 0.22, 0.3, tint: tint)
            cell(scene, u, (p1Centre.0 + 0.1 * p1, 0.5 - 0.02 * p1), 0.18, 0.26, tint: tint, posterior: true)
        }
    }
}

/// Microinjection: a row of eggs slides along the trough, and the fine
/// glass needle pierces each one and leaves a clay bolus in the yolk.
enum Microinjection {
    static let duration = 4.8
    private static let every = 1.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.8), (0.98, 0.8)), tint.opacity(0.5), 0.02)
        let step = floor(t / every)
        let local = t - step * every
        let slide = Ease.inOut((local - 0.9) / 0.3)
        for k in -1...4 {
            let x = 0.5 + 0.3 * (Double(k) - slide)
            guard x > -0.2, x < 1.2 else { continue }
            u.stroke(context, u.circle(x, 0.62, 0.15), tint.opacity(0.5), 0.015)
            context.fill(u.circle(x, 0.66, 0.1), with: .color(tint.opacity(0.25)))
            context.fill(u.ellipse(x, 0.54, 0.12, 0.05), with: .color(tint.opacity(0.5)))
            let injected = k < 0 || (k == 0 && local > 0.5)
            if injected {
                let grow = k < 0 ? 1 : Ease.out((local - 0.5) / 0.2)
                context.fill(u.circle(x + 0.02, 0.62, 0.035 * grow), with: .color(clay))
            }
        }
        let reach = Keyframes.value(local, [(0.1, 0), (0.45, 1), (0.7, 1), (0.9, 0)])
        let tip = (0.52 + 0.3 * (1 - reach), 0.6 - 0.3 * (1 - reach))
        u.stroke(context, u.line(tip, (tip.0 + 0.4, tip.1 - 0.4)), tint, 0.018)
        u.stroke(context, u.line((tip.0 + 0.1, tip.1 - 0.1), (tip.0 + 0.4, tip.1 - 0.4)), tint, 0.04)
        if reach > 0.9 { context.fill(u.circle(tip.0, tip.1, 0.008), with: .color(clay)) }
    }
}

/// A fossil coming out of the rock: the brush sweeps to and fro, dust flies,
/// and a clay ammonite, its spiral and chambers, comes clear.
enum Fossil {
    static let duration = 5.0

    private static func spiral(_ s: Double) -> (Double, Double) {
        let a = s * 3.2 * 2 * .pi
        let r = 0.02 * exp(0.155 * a)
        return (0.48 + r * cos(a), 0.54 + r * sin(a))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        // Where the brush has been: the rock is gone there, and only there
        // does the clay ammonite show.
        let brushed = Ease.clamp((t - 0.3) / 3.0)
        var cleared = Path()
        for k in 0..<Int(brushed * 40) {
            let s = Double(k) / 40
            cleared.addPath(u.circle(0.48 + 0.26 * sin(s * 18), 0.3 + 0.48 * s, 0.1))
        }
        var shown = scene
        shown.clip(to: cleared)
        let shell = stride(from: 0.0, through: 1.0, by: 0.005).map(spiral)
        u.stroke(shown, u.polyline(shell), clay, 0.03)
        for k in 1..<22 {
            let s = 0.3 + 0.7 * Double(k) / 22
            let p = spiral(s), q = spiral(max(0, s - 1 / 3.2))
            u.stroke(shown, u.line(p, (p.0 + (q.0 - p.0) * 0.8, p.1 + (q.1 - p.1) * 0.8)), clay.opacity(0.6), 0.012)
        }
        context.drawLayer { layer in
            layer.opacity = 1 - fade
            layer.fill(u.capsule(0.5, 0.54, 0.88, 0.72, corner: 0.04), with: .color(tint.opacity(0.55)))
            for k in 0..<5 {
                let y = 0.26 + 0.14 * Double(k)
                u.stroke(layer, u.line((0.08, y), (0.92, y + 0.02 * sin(Double(k)))), tint.opacity(0.2), 0.012)
            }
            layer.blendMode = .destinationOut
            layer.fill(cleared, with: .color(.black))
        }
        u.stroke(scene, u.capsule(0.5, 0.54, 0.88, 0.72, corner: 0.04), tint, 0.03)
        guard brushed > 0, brushed < 1 else { return }
        let s = brushed
        let at = (0.48 + 0.26 * sin(s * 18), 0.3 + 0.48 * s)
        var brush = scene
        let p = u.pt(at.0, at.1)
        brush.translateBy(x: p.x, y: p.y)
        brush.rotate(by: .degrees(-30 + 20 * sin(s * 18)))
        for k in 0..<5 {
            var bristle = Path()
            bristle.move(to: CGPoint(x: u.len(-0.04 + 0.02 * Double(k)), y: 0))
            bristle.addLine(to: CGPoint(x: u.len(-0.04 + 0.02 * Double(k)), y: -u.len(0.06)))
            brush.stroke(bristle, with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.012), lineCap: .round))
        }
        brush.fill(Path(roundedRect: CGRect(x: -u.len(0.05), y: -u.len(0.1), width: u.len(0.1), height: u.len(0.045)), cornerRadius: u.len(0.01)), with: .color(tint))
        var handle = Path()
        handle.move(to: CGPoint(x: 0, y: -u.len(0.1)))
        handle.addLine(to: CGPoint(x: 0, y: -u.len(0.3)))
        brush.stroke(handle, with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.03), lineCap: .round))
        for k in 0..<4 {
            let d = ((t * 3 + Double(k) / 4).truncatingRemainder(dividingBy: 1))
            scene.fill(u.circle(at.0 + 0.1 * d * (k % 2 == 0 ? 1 : -1), at.1 - 0.12 * d, 0.01), with: .color(tint.opacity(1 - d)))
        }
    }
}
