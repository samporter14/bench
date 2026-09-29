// PipettingScenes.swift
// ScienceStatus — pipetting and the benchwork round it. Each draws in a
// unit square (see `UnitSquare`): instruments in the tint, tips and samples
// in clay.

import SwiftUI

/// A micropipette drawn from its shaft end up: shaft, ejector sleeve,
/// handle, finger hook, ejector button, plunger. `press` and `eject` run
/// from 0 to 1.
enum Micropipette {
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, end: (Double, Double), press: Double, eject: Double, tint: Color) {
        let (x, y) = end
        context.fill(u.capsule(x, y - 0.045, 0.04, 0.09, corner: 0.015), with: .color(tint))
        context.fill(u.capsule(x, y - 0.015 + 0.025 * eject, 0.056, 0.03, corner: 0.01), with: .color(tint))
        context.fill(u.capsule(x, y - 0.21, 0.09, 0.24, corner: 0.04), with: .color(tint))
        u.stroke(context, u.line((x + 0.045, y - 0.29), (x + 0.085, y - 0.29), (x + 0.085, y - 0.25)), tint, 0.035)
        context.fill(u.capsule(x - 0.06, y - 0.3 + 0.02 * eject, 0.03, 0.045, corner: 0.012), with: .color(tint))
        u.stroke(context, u.line((x, y - 0.36 + 0.02 * press), (x, y - 0.33)), tint, 0.03)
        context.fill(u.capsule(x, y - 0.375 + 0.02 * press, 0.09, 0.03, corner: 0.012), with: .color(tint))
    }

    /// A clay tip whose top sits at `top`, `length` long, turned by `angle`
    /// degrees about its top.
    static func tip(_ context: GraphicsContext, _ u: UnitSquare, top: (Double, Double), length: Double = 0.18, angle: Double = 0) {
        var cone = context
        let p = u.pt(top.0, top.1)
        cone.translateBy(x: p.x, y: p.y)
        cone.rotate(by: .degrees(angle))
        var shape = Path()
        shape.move(to: CGPoint(x: -u.len(0.024), y: 0))
        shape.addLine(to: CGPoint(x: u.len(0.024), y: 0))
        shape.addLine(to: CGPoint(x: u.len(0.006), y: u.len(length)))
        shape.addLine(to: CGPoint(x: -u.len(0.006), y: u.len(length)))
        shape.closeSubpath()
        cone.fill(shape, with: .color(clay))
    }
}

/// Racking tips: row by row, fresh tips drop into the empty rack, and the
/// clay lid slides over them.
enum TipRacking {
    static let duration = 4.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let used = Ease.inOut((t - 3.7) / 0.4)
        u.stroke(context, u.capsule(0.5, 0.54, 0.8, 0.58, corner: 0.04), tint, 0.045)
        for r in 0..<4 {
            for c in 0..<6 {
                let x = 0.2 + 0.12 * Double(c), y = 0.34 + 0.13 * Double(r)
                u.stroke(context, u.circle(x, y, 0.035), tint.opacity(0.4), 0.02)
                let drop = Ease.out((t - 0.3 - 0.4 * Double(r) - 0.03 * Double(c)) / 0.3)
                guard drop > 0 else { continue }
                let scale = 1.6 - 0.6 * drop
                u.stroke(context, u.circle(x, y, 0.042 * scale), tint.opacity(drop * (1 - used)), 0.035)
                context.fill(u.circle(x, y, 0.014 * scale), with: .color(tint.opacity(drop * (1 - used))))
            }
        }
        let lid = Ease.inOut((t - 2.4) / 0.5)
        guard lid > 0 else { return }
        let y = 0.54 - 0.8 * (1 - lid) - 0.8 * used
        context.fill(u.capsule(0.5, y, 0.84, 0.62, corner: 0.05), with: .color(clay))
    }
}

/// Tip on, tip off: the pipette comes down on a clay tip in the rack,
/// seats it with a push, carries it over the bin and ejects it; the tip drops
/// into the bin, out of sight.
enum TipOnOff {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = Keyframes.value(t, [(1.3, 0.3), (2.0, 0.7), (2.9, 0.7), (3.6, 0.3)])
        let y = Keyframes.value(t, [(0.3, 0.42), (0.7, 0.595), (0.85, 0.61), (1.3, 0.42)])
        let eject = Keyframes.value(t, [(2.1, 0), (2.25, 1), (2.5, 1), (2.7, 0)])
        let fresh = Ease.outBack((t - 3.7) / 0.4)

        // Tips in the rack, the middle one taken and later replaced.
        Micropipette.tip(context, u, top: (0.22, 0.6))
        Micropipette.tip(context, u, top: (0.38, 0.6))
        if t < 0.8 || fresh > 0 {
            var tip = context
            if t >= 0.8 {
                let p = u.pt(0.3, 0.7)
                tip.translateBy(x: p.x, y: p.y)
                tip.scaleBy(x: fresh, y: fresh)
                tip.translateBy(x: -p.x, y: -p.y)
            }
            Micropipette.tip(tip, u, top: (0.3, 0.6))
        }
        // The tip on the pipette, then dropping into the bin and staying.
        if t >= 0.8 && t < 2.25 {
            Micropipette.tip(context, u, top: (x, y + 0.01))
        } else if t >= 2.25 {
            let fall = Ease.clamp((t - 2.25) / 0.32)
            let drop = fall * fall
            if fall < 1 {
                Micropipette.tip(context, u, top: (0.7 + 0.01 * drop, (y + 0.01) + (0.76 - (y + 0.01)) * drop),
                                 angle: -12 * fall)
            }
        }
        context.fill(u.capsule(0.31, 0.79, 0.3, 0.26, corner: 0.02), with: .color(tint))
        var bin = u.line((0.58, 0.72), (0.82, 0.72), (0.79, 0.94), (0.61, 0.94))
        bin.closeSubpath()
        context.fill(bin, with: .color(tint))
        Micropipette.draw(context, u, end: (x, y), press: 0, eject: eject, tint: tint)
    }
}

/// A multichannel taking a fresh row of tips from the rack, then ejecting
/// the lot into the bin.
enum MultichannelTips {
    static let duration = 4.6
    private static let spacing = [-0.15, -0.05, 0.05, 0.15]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = Keyframes.value(t, [(1.3, 0.33), (2.0, 0.76), (2.9, 0.76), (3.6, 0.33)])
        let y = Keyframes.value(t, [(0.3, 0.44), (0.7, 0.595), (0.85, 0.61), (1.3, 0.44)])
        let eject = Keyframes.value(t, [(2.1, 0), (2.25, 1), (2.5, 1), (2.7, 0)])
        let fresh = Ease.outBack((t - 3.7) / 0.4)
        for dx in spacing {
            if t < 0.8 {
                Micropipette.tip(context, u, top: (0.33 + dx, 0.6))
            } else if t < 2.25 {
                Micropipette.tip(context, u, top: (x + dx, y + 0.01))
            } else {
                // Dropped into the bin, out of sight below its rim.
                let fall = Ease.clamp((t - 2.25 - 0.04 * (dx + 0.15) / 0.1) / 0.32)
                let drop = fall * fall
                if fall < 1 {
                    Micropipette.tip(context, u, top: (0.76 + dx * (1 - 0.15 * drop), (y + 0.01) + (0.76 - (y + 0.01)) * drop),
                                     angle: (dx > 0 ? -1 : 1) * 14 * fall)
                }
            }
            if fresh > 0 {
                var tip = context
                let p = u.pt(0.33 + dx, 0.7)
                tip.translateBy(x: p.x, y: p.y)
                tip.scaleBy(x: fresh, y: fresh)
                tip.translateBy(x: -p.x, y: -p.y)
                Micropipette.tip(tip, u, top: (0.33 + dx, 0.6))
            }
        }
        context.fill(u.capsule(0.33, 0.79, 0.46, 0.26, corner: 0.02), with: .color(tint))
        var bin = u.line((0.56, 0.72), (0.98, 0.72), (0.95, 0.96), (0.59, 0.96))
        bin.closeSubpath()
        context.fill(bin, with: .color(tint))
        for dx in spacing {
            context.fill(u.capsule(x + dx, y - 0.02, 0.03, 0.04, corner: 0.01), with: .color(tint))
        }
        context.fill(u.capsule(x, y - 0.005 + 0.025 * eject, 0.38, 0.02, corner: 0.01), with: .color(tint))
        context.fill(u.capsule(x, y - 0.06, 0.42, 0.06, corner: 0.025), with: .color(tint))
        context.fill(u.capsule(x, y - 0.23, 0.1, 0.26, corner: 0.04), with: .color(tint))
        context.fill(u.capsule(x, y - 0.385, 0.1, 0.03, corner: 0.012), with: .color(tint))
    }
}

/// Mixing by pipetting: the tip sits in a tube with a clay layer at the
/// bottom; the plunger goes up and down, the tip fills and empties, and
/// with each stroke the clay spreads until the tube is evenly mixed.
enum PipetteMixing {
    static let duration = 4.4
    private static let rim = 0.5, shoulder = 0.78, tip = 0.91, half = 0.1

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let press = Keyframes.value(t, [(0.3, 1), (0.6, 0), (0.95, 1), (1.3, 0), (1.65, 1), (2.0, 0), (2.35, 1), (2.7, 0), (3.05, 1)])
        let mixed = Ease.clamp((t - 0.3) / 2.75) * (1 - Ease.inOut((t - 3.7) / 0.5))
        let level = 0.62 + 0.03 * (1 - press)
        let outline = BenchShapes.tube(u, x: 0.5, rim: rim, shoulder: shoulder, tip: tip, half: half)
        BenchShapes.fill(context, u, outline, from: level, clay.opacity(0.15 + 0.5 * mixed))
        BenchShapes.fill(context, u, outline, from: tip - 0.14 * (1 - mixed), clay)
        u.stroke(context, outline, tint, 0.045)

        var pipette = context
        let top = u.pt(0.5, 0)
        pipette.translateBy(x: top.x, y: top.y + u.len(0.04))
        pipette.scaleBy(x: 0.8, y: 0.8)
        pipette.translateBy(x: -top.x, y: -top.y)
        Pipette.drawInstrument(in: pipette, u, tint: tint, press: press, emptied: 0.35 + 0.65 * press)
    }
}

/// An aspirator: the dish is tipped so the clay medium pools in one corner,
/// the glass pipette follows it down there and draws it off, leaving the
/// cells; the dish is set flat and fresh medium pours in.
enum Aspirator {
    static let duration = 4.4
    private static let pivot = (0.5, 0.84)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // Tipped left side down, then set flat again.
        let tilt = -11 * Keyframes.value(t, [(0.15, 0), (0.55, 1), (2.3, 1), (2.65, 0)])
        let corner = rotated((0.12, 0.84), by: tilt)
        let flat = 0.62, empty = 0.838
        // The surface stays level: it sinks towards the low corner as the
        // medium is drawn off, and rises again with the fresh medium.
        let drained = Keyframes.value(t, [(0.7, 0), (2.2, 1)])
        let refill = Keyframes.value(t, [(2.9, 0), (3.7, 1)])
        let low = corner.1 - 0.006
        let surface = t < 2.65
            ? flat + (low - flat) * Ease.inOut(drained)
            : empty + (flat - empty) * Ease.inOut(refill)

        var dish = context
        let p = u.pt(pivot.0, pivot.1)
        dish.translateBy(x: p.x, y: p.y)
        dish.rotate(by: .degrees(tilt))
        dish.translateBy(x: -p.x, y: -p.y)
        var inside = u.line((0.12, 0.5), (0.12, 0.84), (0.88, 0.84), (0.88, 0.5))
        inside.closeSubpath()
        var liquid = context
        liquid.clip(to: inside.applying(transform(u, tilt)))
        liquid.fill(Path(CGRect(x: 0, y: u.pt(0, surface).y, width: size.width, height: size.height)), with: .color(clay))
        for k in 0..<12 {
            dish.fill(u.ellipse(0.17 + 0.06 * Double(k), 0.832, 0.05, 0.022), with: .color(tint.opacity(0.7)))
        }
        u.stroke(dish, u.line((0.12, 0.54), (0.12, 0.84), (0.88, 0.84), (0.88, 0.54)), tint, 0.045)

        // The glass pipette, tip riding the surface into the low corner.
        let down = Keyframes.value(t, [(0.25, 0), (0.6, 1), (2.25, 1), (2.6, 0)])
        let target = (corner.0 + 0.07, min(surface + 0.014, corner.1 - 0.03))
        let tip = (0.24 + (target.0 - 0.24) * down, 0.2 + (target.1 - 0.2) * down)
        let far = (tip.0 + 0.3, tip.1 - 0.52)
        u.stroke(context, u.line(tip, far), tint, 0.035)
        var hose = Path()
        hose.move(to: u.pt(far.0, far.1))
        hose.addQuadCurve(to: u.pt(1.05, far.1 - 0.05), control: u.pt(far.0 + 0.2, far.1 - 0.2))
        u.stroke(context, hose, tint.opacity(0.6), 0.035)
        if t > 0.7 && t < 2.2 {
            let period = 0.08
            context.stroke(u.line(tip, far), with: .color(clay),
                           style: StrokeStyle(lineWidth: u.len(0.02), lineCap: .round, dash: [u.len(0.03), u.len(0.05)],
                                              dashPhase: u.len(period - (t * 0.3).truncatingRemainder(dividingBy: period))))
        }
        // Fresh medium from a serological pipette, down the far wall.
        let pipette = Keyframes.value(t, [(2.65, 0), (2.85, 1), (3.8, 1), (4.1, 0)])
        if pipette > 0 {
            let y = 0.42 - 0.6 * (1 - pipette)
            u.stroke(context, u.line((0.78, y), (0.82, y - 0.5)), tint, 0.035)
            if t > 2.9 && t < 3.75 { u.stroke(context, u.line((0.78, y + 0.01), (0.78, surface)), clay, 0.025) }
        }
    }

    /// Where a point of the dish lands, tipped by `degrees` about its pivot.
    private static func rotated(_ point: (Double, Double), by degrees: Double) -> (Double, Double) {
        let a = degrees * .pi / 180
        let dx = point.0 - pivot.0, dy = point.1 - pivot.1
        return (pivot.0 + dx * cos(a) - dy * sin(a), pivot.1 + dx * sin(a) + dy * cos(a))
    }

    private static func transform(_ u: UnitSquare, _ degrees: Double) -> CGAffineTransform {
        let p = u.pt(pivot.0, pivot.1)
        return CGAffineTransform(translationX: -p.x, y: -p.y)
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
    }
}

/// A liquid-handling robot: the head runs along its gantry, dips into the
/// clay reservoir, and fills the wells of a plate one by one.
enum LiquidHandler {
    static let duration = 4.6
    private static let wells = [0.46, 0.58, 0.7, 0.82]
    private static let starts = [0.2, 1.5, 2.8]

    private static func keys() -> (x: [(Double, Double)], z: [(Double, Double)], load: [(Double, Double)]) {
        var x: [(Double, Double)] = [], z: [(Double, Double)] = [], load: [(Double, Double)] = []
        for (j, s) in starts.enumerated() {
            x += [(s, j == 0 ? 0.5 : wells[j - 1]), (s + 0.3, 0.2), (s + 0.75, 0.2), (s + 1.0, wells[j])]
            z += [(s + 0.3, 0.5), (s + 0.42, 0.8), (s + 0.55, 0.8), (s + 0.7, 0.5), (s + 1.0, 0.5), (s + 1.1, 0.8), (s + 1.2, 0.8), (s + 1.3, 0.5)]
            load += [(s + 0.42, 0), (s + 0.55, 1), (s + 1.1, 1), (s + 1.2, 0)]
        }
        x += [(4.1, wells[2]), (4.5, 0.5)]
        return (x, z, load)
    }
    private static let choreography = keys()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reset = Ease.inOut((t - 4.1) / 0.4)
        u.stroke(context, u.line((0.06, 0.9), (0.06, 0.12), (0.94, 0.12), (0.94, 0.9)), tint, 0.04)
        u.stroke(context, u.line((0.04, 0.9), (0.96, 0.9)), tint, 0.045)
        let trough = u.line((0.12, 0.7), (0.12, 0.87), (0.28, 0.87), (0.28, 0.7))
        BenchShapes.fill(context, u, trough, from: 0.76, clay)
        u.stroke(context, trough, tint, 0.035)
        for (j, w) in wells.enumerated() {
            let cup = u.line((w - 0.045, 0.74), (w - 0.045, 0.86), (w + 0.045, 0.86), (w + 0.045, 0.74))
            let fill = j < starts.count ? Ease.inOut((t - starts[j] - 1.1) / 0.1) * (1 - reset) : 0
            if fill > 0 { BenchShapes.fill(context, u, cup, from: 0.86 - 0.08 * fill, clay) }
            u.stroke(context, cup, tint, 0.03)
        }
        let x = Keyframes.value(t, choreography.x)
        let z = Keyframes.value(t, choreography.z)
        let load = Keyframes.value(t, choreography.load)
        context.fill(u.capsule(x, 0.12, 0.12, 0.07, corner: 0.02), with: .color(tint))
        context.fill(u.capsule(x, (0.12 + z - 0.14) / 2, 0.04, z - 0.14 - 0.12, corner: 0.015), with: .color(tint))
        var cone = u.line((x - 0.02, z - 0.14), (x - 0.004, z), (x + 0.004, z), (x + 0.02, z - 0.14))
        cone.closeSubpath()
        if load > 0 {
            var liquid = context
            liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, z - 0.1 * load).y, width: u.side, height: u.side)))
            liquid.fill(cone, with: .color(clay))
        }
        u.stroke(context, cone, tint, 0.022)
    }
}

/// A gel on the transilluminator: the gel slides onto the glass, the light
/// comes on, and the bands glow clay, lane by lane, before it goes dark.
enum GelImager {
    static let duration = 4.4
    private static let lanes: [[Double]] = [[0.2, 0.3, 0.42, 0.56, 0.72], [0.36, 0.6], [0.36, 0.5], [0.28, 0.6], [0.45]]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let light = Keyframes.value(t, [(0.9, 0), (1.0, 1), (3.3, 1), (3.4, 0)])
        u.stroke(context, u.capsule(0.5, 0.56, 0.86, 0.66, corner: 0.05), tint, 0.045)
        context.fill(u.capsule(0.5, 0.56, 0.68, 0.5, corner: 0.02), with: .color(tint.opacity(0.06 + 0.2 * light)))
        context.fill(u.circle(0.86, 0.3, 0.018), with: .color(clay.opacity(0.3 + 0.7 * light)))
        let x = Keyframes.value(t, [(0, -0.4), (0.6, 0.5), (3.6, 0.5), (4.2, 1.4)])
        u.stroke(context, u.capsule(x, 0.56, 0.52, 0.42, corner: 0.015), tint, 0.03)
        for (k, bands) in lanes.enumerated() {
            let lx = x - 0.18 + 0.09 * Double(k)
            u.stroke(context, u.line((lx - 0.025, 0.39), (lx + 0.025, 0.39)), tint, 0.025)
            let glow = light * Ease.clamp((t - 1.0 - 0.15 * Double(k)) / 0.2)
            guard glow > 0 else { continue }
            for b in bands {
                context.fill(u.capsule(lx, 0.35 + 0.4 * b, 0.06, 0.022, corner: 0.011), with: .color(clay.opacity(glow)))
            }
        }
    }
}

/// A cuvette reading: the clay cuvette drops into the photometer, the lid
/// shuts, the display scrambles and settles on its reading, and the
/// cuvette comes back out.
enum Cuvette {
    static let duration = 4.6
    /// Segments a to g of each digit, as on a seven-segment display.
    private static let digits: [String] = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg"]

    private static func digit(_ context: GraphicsContext, _ u: UnitSquare, _ segments: String, x: Double, y: Double, color: Color) {
        let w = 0.035, h = 0.045
        let ends: [Character: ((Double, Double), (Double, Double))] = [
            "a": ((-w, -h), (w, -h)), "b": ((w, -h), (w, 0)), "c": ((w, 0), (w, h)), "d": ((-w, h), (w, h)),
            "e": ((-w, 0), (-w, h)), "f": ((-w, -h), (-w, 0)), "g": ((-w, 0), (w, 0)),
        ]
        for s in segments {
            guard let e = ends[s] else { continue }
            u.stroke(context, u.line((x + e.0.0, y + e.0.1), (x + e.1.0, y + e.1.1)), color, 0.016)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let bottom = Keyframes.value(t, [(0.2, 0.36), (0.7, 0.8), (3.5, 0.8), (4.0, 0.36)])
        context.fill(u.capsule(0.28, bottom - 0.12, 0.1, 0.16, corner: 0.01), with: .color(clay))
        u.stroke(context, u.capsule(0.28, bottom - 0.14, 0.1, 0.28, corner: 0.01), tint, 0.03)

        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, 0.7, 0.84, 0.36, corner: 0.04), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.capsule(0.28, 0.54, 0.12, 0.04, corner: 0.01), with: .color(.black))
            layer.fill(u.capsule(0.66, 0.72, 0.4, 0.16, corner: 0.02), with: .color(.black))
        }
        let shut = Keyframes.value(t, [(0.8, 0), (1.1, 1), (3.2, 1), (3.5, 0)])
        var lid = context
        let hinge = u.pt(0.37, 0.51)
        lid.translateBy(x: hinge.x, y: hinge.y)
        lid.rotate(by: .degrees(110 * (1 - shut)))
        lid.translateBy(x: -hinge.x, y: -hinge.y)
        lid.fill(u.capsule(0.28, 0.51, 0.18, 0.035, corner: 0.012), with: .color(tint))

        // The display: dashes when idle, scrambling, then the reading.
        let reading = [0, 4, 2]
        for k in 0..<3 {
            let x = 0.54 + 0.1 * Double(k), y = 0.72
            let segments: String
            if t < 1.3 || t > 3.6 {
                segments = "g"
            } else if t < 2.3 {
                segments = digits[(Int(t * 14) * 7 + k * 3) % 10]
            } else {
                segments = digits[reading[k]]
            }
            digit(context, u, segments, x: x, y: y, color: clay)
        }
        if t >= 2.3 && t <= 3.6 { context.fill(u.circle(0.59, 0.765, 0.01), with: .color(clay)) }
    }
}

/// Building a transfer sandwich: sponge, paper, gel, the clay membrane,
/// paper and sponge go down one by one; a roller chases out the bubbles,
/// and the cassette clamps shut.
enum TransferSandwich {
    static let duration = 4.8
    private enum Kind { case sponge, paper, gel, membrane }
    private static let layers: [(y: Double, h: Double, kind: Kind, at: Double)] = [
        (0.8, 0.09, .sponge, 0.2), (0.735, 0.03, .paper, 0.55), (0.695, 0.045, .gel, 0.9),
        (0.664, 0.016, .membrane, 1.25), (0.64, 0.03, .paper, 2.2), (0.575, 0.09, .sponge, 2.55),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let out = Ease.inOut((t - 4.1) / 0.5)
        var stack = context
        stack.translateBy(x: u.len(0.9 * out), y: 0)
        u.stroke(stack, u.line((0.1, 0.87), (0.9, 0.87)), tint, 0.05)
        for layer in layers {
            let drop = Ease.outBack((t - layer.at) / 0.35)
            guard drop > 0 else { continue }
            let y = layer.y - 0.5 * (1 - min(1, drop))
            switch layer.kind {
            case .sponge:
                u.stroke(stack, u.capsule(0.5, y, 0.72, layer.h, corner: 0.02), tint, 0.03)
                for k in 0..<9 { stack.fill(u.circle(0.2 + 0.075 * Double(k), y + 0.012 * sin(Double(k) * 2), 0.01), with: .color(tint.opacity(0.6))) }
            case .paper:
                stack.fill(u.capsule(0.5, y, 0.7, layer.h, corner: 0.008), with: .color(tint))
            case .gel:
                stack.fill(u.capsule(0.5, y, 0.66, layer.h, corner: 0.01), with: .color(tint.opacity(0.4)))
            case .membrane:
                stack.fill(u.capsule(0.5, y, 0.66, layer.h, corner: 0.006), with: .color(clay))
            }
        }
        // Bubbles under the membrane, and the roller that chases them out.
        let roll = Ease.inOut((t - 1.6) / 0.5)
        let rx = 0.14 + 0.72 * roll
        if t > 1.4 && t < 2.2 {
            for k in 0..<4 {
                let bx = 0.26 + 0.16 * Double(k)
                if bx > rx { u.stroke(stack, u.circle(bx, 0.655, 0.012), tint, 0.015) }
            }
            if t > 1.5 {
                u.stroke(stack, u.circle(rx, 0.62, 0.035), tint, 0.03)
                u.stroke(stack, u.line((rx, 0.62), (rx + 0.1, 0.42)), tint, 0.03)
            }
        }
        // The cassette's top comes down and clamps.
        let clamp = Ease.out((t - 3.0) / 0.5)
        if clamp > 0 {
            let y = 0.51 - 0.5 * (1 - clamp)
            u.stroke(stack, u.line((0.1, y), (0.9, y)), tint, 0.05)
            u.stroke(stack, u.line((0.9, y), (0.93, (y + 0.87) / 2), (0.9, 0.87)), tint.opacity(clamp), 0.035)
        }
    }
}

/// Loading a gel: the tip dips into a well under the buffer and lets out
/// its dense clay sample, which sinks and settles; then the next well.
enum GelLoading {
    static let duration = 4.4
    private static let wells = [0.25, 0.4, 0.55, 0.7]
    private static let starts = [0.2, 1.3, 2.4]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reset = Ease.inOut((t - 3.8) / 0.5)
        let tank = u.line((0.06, 0.3), (0.06, 0.9), (0.94, 0.9), (0.94, 0.3))
        BenchShapes.fill(context, u, tank, from: 0.42, tint.opacity(0.1))
        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, 0.72, 0.8, 0.28, corner: 0.01), with: .color(tint.opacity(0.35)))
            layer.blendMode = .destinationOut
            for w in wells { layer.fill(u.capsule(w, 0.62, 0.06, 0.08, corner: 0.008), with: .color(.black)) }
        }
        for (j, w) in wells.enumerated() where j < starts.count {
            let fill = Ease.inOut((t - starts[j] - 0.55) / 0.3) * (1 - reset)
            if fill > 0 { context.fill(u.capsule(w, 0.66 - 0.035 * fill, 0.05, 0.07 * fill, corner: 0.008), with: .color(clay)) }
        }
        u.stroke(context, tank, tint, 0.045)

        var xs: [(Double, Double)] = [(0, 0.12)], ys: [(Double, Double)] = [(0, 0.3)], held: [(Double, Double)] = [(0, 1)]
        for (j, s) in starts.enumerated() {
            xs += [(s + 0.3, wells[j]), (s + 1.1, wells[j])]
            ys += [(s + 0.3, 0.3), (s + 0.5, 0.6), (s + 0.85, 0.6), (s + 1.05, 0.3)]
            held += [(s + 0.5, 1), (s + 0.8, 0), (s + 1.1, 1)]
        }
        xs += [(4.0, 0.12)]
        let x = Keyframes.value(t, xs), end = Keyframes.value(t, ys), loaded = Keyframes.value(t, held)
        var cone = u.line((x - 0.022, end - 0.2), (x - 0.005, end), (x + 0.005, end), (x + 0.022, end - 0.2))
        cone.closeSubpath()
        var liquid = context
        liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, end - 0.1 * loaded).y, width: u.side, height: u.side)))
        if loaded > 0.02 { liquid.fill(cone, with: .color(clay)) }
        u.stroke(context, cone, tint, 0.022)
        context.fill(u.capsule(x, end - 0.3, 0.04, 0.2, corner: 0.015), with: .color(tint))
    }
}
