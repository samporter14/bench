// EMScenes.swift
// ScienceStatus — electron microscopy, and the plots of qPCR and titration.
// Each draws in a unit square (see `UnitSquare`): columns, grids, axes and
// curves in the tint, electrons, picks, the sample and the readout in clay.

import SwiftUI

/// A transmission electron microscope: electrons stream from the gun down
/// the column, are focused by the lenses through the specimen, and the
/// image comes up on the screen at the bottom.
enum TEMColumn {
    static let duration = 4.6

    /// A ray's path down the column: gun, crossover, specimen, screen.
    private static func ray(_ side: Double) -> [(Double, Double)] {
        [(0.5, 0.12), (0.5 + 0.05 * side, 0.3), (0.5, 0.44), (0.5 + 0.035 * side, 0.57), (0.5 + 0.16 * side, 0.84)]
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.3, 0.08), (0.3, 0.8)), tint.opacity(0.5), 0.025)
        u.stroke(context, u.line((0.7, 0.08), (0.7, 0.8)), tint.opacity(0.5), 0.025)
        for y in [0.3, 0.44, 0.66] {
            for x in [0.34, 0.66] { context.fill(u.capsule(x, y, 0.08, 0.05, corner: 0.02), with: .color(tint)) }
        }
        u.stroke(context, u.line((0.47, 0.06), (0.5, 0.11), (0.53, 0.06)), clay, 0.025)
        let on = Ease.clamp((t - 0.3) / 0.3)
        for side in [-1.0, 1.0] { u.stroke(context, u.polyline(ray(side)), tint.opacity(0.35 * on), 0.012) }
        u.stroke(context, u.line((0.42, 0.57), (0.58, 0.57)), tint, 0.02)
        context.fill(u.circle(0.5, 0.565, 0.012), with: .color(clay))
        // Electrons streaming down.
        for k in 0..<10 where on > 0 {
            let life = ((t * 0.8 + Double(k) / 10).truncatingRemainder(dividingBy: 1))
            let path = ray(k % 2 == 0 ? -1 : 1)
            let p = Polyline.point(path, at: life)
            context.fill(u.circle(p.0, p.1, 0.012), with: .color(clay.opacity(on)))
        }
        // The screen and the image that forms on it.
        let image = Ease.inOut((t - 1.2) / 1.2) * (1 - Ease.inOut((t - 4.1) / 0.4))
        u.stroke(context, u.ellipse(0.5, 0.88, 0.44, 0.1), tint, 0.025)
        for (x, y, r) in [(0.42, 0.87, 0.02), (0.52, 0.89, 0.025), (0.6, 0.87, 0.018)] {
            u.stroke(context, u.ellipse(x, y, 2 * r * 1.6, 2 * r * 0.6), tint.opacity(image), 0.014)
            context.fill(u.ellipse(x, y, r * 1.2, r * 0.45), with: .color(clay.opacity(image)))
        }
    }
}

/// Negative stain: a copper grid, then one of its squares up close, where
/// particles show pale in the stain; the clay rings pick them one by one.
enum NegativeStain {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let zoom = Ease.inOut((t - 1.0) / 0.8)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        if zoom < 1 {
            var grid = context
            let c = u.pt(0.58, 0.42)
            grid.translateBy(x: c.x, y: c.y)
            grid.scaleBy(x: 1 + 5 * zoom, y: 1 + 5 * zoom)
            grid.translateBy(x: -c.x, y: -c.y)
            grid.opacity = 1 - zoom
            grid.clip(to: u.circle(0.5, 0.5, 0.4))
            var x = 0.14
            while x < 0.9 { u.stroke(grid, u.line((x, 0.0), (x, 1.0)), tint, 0.02); x += 0.08 }
            var y = 0.14
            while y < 0.9 { u.stroke(grid, u.line((0.0, y), (1.0, y)), tint, 0.02); y += 0.08 }
            u.stroke(context, u.circle(0.5, 0.5, 0.4), tint.opacity(1 - zoom), 0.04)
        }
        guard zoom > 0 else { return }
        let particles: [(Double, Double, Bool)] = [(0.26, 0.3, true), (0.5, 0.24, false), (0.74, 0.34, true), (0.34, 0.56, false),
                                                  (0.62, 0.58, true), (0.26, 0.78, true), (0.5, 0.76, false), (0.78, 0.74, false)]
        context.drawLayer { layer in
            layer.opacity = zoom * (1 - fade)
            layer.fill(u.capsule(0.5, 0.5, 0.84, 0.84, corner: 0.02), with: .color(tint.opacity(0.4)))
            layer.blendMode = .destinationOut
            for p in particles {
                if p.2 {
                    layer.fill(u.circle(p.0, p.1, 0.06), with: .color(.black))
                } else {
                    for k in 0..<7 {
                        let a = Double(k) * 2 * .pi / 7
                        layer.fill(u.circle(p.0 + 0.04 * cos(a), p.1 + 0.04 * sin(a), 0.016), with: .color(.black))
                    }
                }
            }
        }
        for (k, p) in particles.enumerated() {
            let pick = Ease.outBack((t - 2.2 - 0.22 * Double(k)) / 0.3)
            guard pick > 0 else { continue }
            u.stroke(context, u.circle(p.0, p.1, 0.085 * min(1.2, pick)), clay.opacity(1 - fade), 0.02)
        }
    }
}

/// A cryo-ET tilt series: the specimen tips from one side to the other
/// under the beam, each tilt casting its shadow on the detector; then the
/// shadows are cast back and cross where the clay object was.
enum TiltSeries {
    static let duration = 5.0
    private static let tilts: [Double] = [-50, -25, 0, 25, 50]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let angle = Keyframes.value(t, [(0.2, -50), (2.6, 50), (3.0, 0)])
        let back = Ease.inOut((t - 3.0) / 1.0)
        for x in stride(from: 0.3, through: 0.7, by: 0.08) { u.stroke(scene, u.line((x, 0.04), (x, 0.26)), tint.opacity(0.3), 0.012) }
        var slab = scene
        let c = u.pt(0.5, 0.36)
        slab.translateBy(x: c.x, y: c.y)
        slab.rotate(by: .degrees(angle))
        slab.fill(Path(roundedRect: CGRect(x: -u.len(0.26), y: -u.len(0.05), width: u.len(0.52), height: u.len(0.1)), cornerRadius: u.len(0.02)),
                  with: .color(tint.opacity(0.3)))
        slab.fill(Path(ellipseIn: CGRect(x: u.len(0.05), y: -u.len(0.03), width: u.len(0.06), height: u.len(0.06))), with: .color(clay))
        u.stroke(scene, u.line((0.1, 0.62), (0.9, 0.62)), tint, 0.03)
        // The shadow of the object for each tilt taken so far.
        let object = (0.08, 0.0)
        for (k, a) in tilts.enumerated() {
            let taken = Ease.clamp((t - 0.2 - 0.6 * Double(k)) / 0.1)
            guard taken > 0 else { continue }
            let r = a * .pi / 180
            let x = 0.5 + object.0 * cos(r) - object.1 * sin(r)
            scene.fill(u.capsule(x, 0.66 + 0.04 * Double(k), 0.05, 0.02, corner: 0.01), with: .color(clay.opacity(0.8 * taken)))
            if back > 0 {
                let from = (x, 0.66 + 0.04 * Double(k))
                let to = (0.58, 0.36)
                let tip = (from.0 + (to.0 - from.0) * back, from.1 + (to.1 - from.1) * back)
                u.stroke(scene, u.line(from, tip), clay.opacity(0.4), 0.012)
            }
        }
        if back > 0.9 { scene.fill(u.circle(0.58, 0.36, 0.035), with: .color(clay)) }
    }
}

/// qPCR amplification: four ten-fold dilutions climb their sigmoids cycle
/// by cycle, and where each crosses the threshold its clay Ct drops to the
/// axis, about three and a third cycles apart.
enum QPCRCurves {
    static let duration = 4.8
    private static let cts = [15.0, 18.3, 21.6, 25.0]

    private static func signal(_ cycle: Double, ct: Double) -> Double { 1 / (1 + exp(-(cycle - ct - 2.2) / 1.5)) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.1, 0.12), (0.1, 0.86), (0.92, 0.86)), tint.opacity(0.5), 0.02)
        let threshold = 0.86 - 0.72 * 0.1
        scene.stroke(u.line((0.1, threshold), (0.92, threshold)), with: .color(tint.opacity(0.6)),
                     style: StrokeStyle(lineWidth: u.len(0.014), dash: [u.len(0.02), u.len(0.02)]))
        let run = 40 * Ease.clamp((t - 0.2) / 3.6)
        func point(_ c: Double, _ ct: Double) -> (Double, Double) { (0.1 + 0.82 * c / 40, 0.86 - 0.72 * signal(c, ct: ct)) }
        for ct in cts {
            let curve = stride(from: 0.0, through: run, by: 0.4).map { point($0, ct) }
            if curve.count > 1 { u.stroke(scene, u.polyline(curve), tint, 0.022) }
            let crossing = ct + 2.2 - 1.5 * log(9)
            let drop = Ease.out((run - crossing) / 2)
            guard drop > 0 else { continue }
            let x = 0.1 + 0.82 * crossing / 40
            u.stroke(scene, u.line((x, threshold), (x, threshold + (0.86 - threshold) * drop)), clay, 0.018)
            scene.fill(u.circle(x, threshold, 0.016), with: .color(clay))
        }
    }
}

/// A melt curve: the temperature climbs, the double-stranded signal falls
/// away as the product melts, and its clay derivative peak rises at the
/// melting point, a small primer-dimer bump beside it.
enum MeltCurve {
    static let duration = 4.6

    private static func fluorescence(_ x: Double) -> Double { 0.9 / (1 + exp((x - 0.66) / 0.03)) + 0.08 / (1 + exp((x - 0.42) / 0.03)) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.1, 0.1), (0.1, 0.9), (0.92, 0.9)), tint.opacity(0.5), 0.02)
        let ramp = Ease.clamp((t - 0.2) / 3.4)
        let top = stride(from: 0.0, through: ramp, by: 0.01).map { x in (0.1 + 0.82 * x, 0.46 - 0.34 * fluorescence(x)) }
        if top.count > 1 { u.stroke(scene, u.polyline(top), tint, 0.022) }
        let derivative = stride(from: 0.0, through: ramp, by: 0.01).map { x -> (Double, Double) in
            let d = (fluorescence(x) - fluorescence(x + 0.005)) / 0.005
            return (0.1 + 0.82 * x, 0.9 - 0.045 * d)
        }
        if derivative.count > 1 { u.stroke(scene, u.polyline(derivative), clay, 0.025) }
        u.stroke(scene, u.line((0.1 + 0.82 * ramp, 0.1), (0.1 + 0.82 * ramp, 0.9)), tint.opacity(0.3 * (1 - Ease.clamp((t - 3.6) / 0.3))), 0.012)
        if ramp > 0.7 {
            let x = 0.1 + 0.82 * 0.66
            scene.stroke(u.line((x, 0.5), (x, 0.9)), with: .color(clay.opacity(0.6)),
                         style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.015), u.len(0.015)]))
        }
    }
}

/// A titration curve: drops fall from the burette, the pH climbs slowly,
/// then leaps at the equivalence point, where the flask turns clay.
enum TitrationCurve {
    static let duration = 4.8

    private static func pH(_ v: Double) -> Double { 7 + 5.2 * tanh((v - 0.55) / 0.035) + 1.2 * (v - 0.55) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let added = Ease.clamp((t - 0.2) / 3.6)
        u.stroke(scene, u.capsule(0.18, 0.24, 0.05, 0.36, corner: 0.02), tint, 0.022)
        let level = 0.08 + 0.3 * added
        scene.fill(u.capsule(0.18, (level + 0.41) / 2, 0.03, 0.41 - level, corner: 0.01), with: .color(tint.opacity(0.35)))
        u.stroke(scene, u.line((0.18, 0.42), (0.18, 0.48)), tint, 0.015)
        scene.fill(u.capsule(0.18, 0.44, 0.07, 0.02, corner: 0.01), with: .color(tint))
        let fall = (t * 2.4).truncatingRemainder(dividingBy: 1)
        if added > 0 && added < 1 { scene.fill(u.circle(0.18, 0.5 + 0.16 * fall * fall, 0.012), with: .color(tint)) }
        let turned = Ease.clamp((pH(added) - 7.5) / 1.5)
        let flask = u.line((0.15, 0.62), (0.15, 0.68), (0.07, 0.88), (0.29, 0.88), (0.21, 0.68), (0.21, 0.62))
        BenchShapes.fill(scene, u, flask, from: 0.78, clay.opacity(0.1 + 0.8 * turned))
        u.stroke(scene, flask, tint, 0.025)
        // The plot.
        u.stroke(scene, u.line((0.42, 0.14), (0.42, 0.86), (0.94, 0.86)), tint.opacity(0.5), 0.02)
        let curve = stride(from: 0.0, through: added, by: 0.01).map { v in (0.42 + 0.52 * v, 0.86 - 0.72 * pH(v) / 14) }
        if curve.count > 1 { u.stroke(scene, u.polyline(curve), tint, 0.025) }
        if let pen = curve.last { scene.fill(u.circle(pen.0, pen.1, 0.018), with: .color(clay)) }
        if added > 0.56 {
            let x = 0.42 + 0.52 * 0.55
            scene.stroke(u.line((x, 0.86), (x, 0.86 - 0.72 * 0.5)), with: .color(clay.opacity(0.6)),
                         style: StrokeStyle(lineWidth: u.len(0.012), dash: [u.len(0.015), u.len(0.015)]))
        }
    }
}
