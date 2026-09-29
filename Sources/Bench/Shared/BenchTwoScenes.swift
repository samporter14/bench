// BenchTwoScenes.swift
// ScienceStatus — more of the bench: the everyday kit and routines of a
// wet lab. Each draws in a unit square (see `UnitSquare`): glass, plastic
// and machines in the tint, the sample in clay.

import SwiftUI

/// Shapes and odds and ends the bench scenes share.
enum BenchShapes {
    /// A microcentrifuge tube's outline, open at the top: straight walls
    /// down from the rim, then a cone to a narrow tip.
    static func tube(_ u: UnitSquare, x: Double, rim: Double, shoulder: Double, tip: Double, half: Double) -> Path {
        u.line((x - half, rim), (x - half, shoulder), (x - 0.025, tip), (x + 0.025, tip), (x + half, shoulder), (x + half, rim))
    }

    /// Fills the vessel `outline` (closed up across its top) from `level`
    /// down to its bottom.
    static func fill(_ context: GraphicsContext, _ u: UnitSquare, _ outline: Path, from level: Double, _ color: Color) {
        var body = outline
        body.closeSubpath()
        var liquid = context
        liquid.clip(to: Path(CGRect(x: u.origin.x - u.side, y: u.pt(0, level).y, width: 3 * u.side, height: 2 * u.side)))
        liquid.fill(body, with: .color(color))
    }

    /// A steady scatter: the same number in 0..<1 for the same `k`.
    static func rand(_ k: Double) -> Double {
        let s = sin(k * 12.9898 + 78.233) * 43758.5453
        return s - floor(s)
    }
}

/// A microcentrifuge spin: cells hang through the sample; the tube spins
/// and they gather at its tip as a clay pellet, until a flick sends them
/// back up.
enum Microfuge {
    static let duration = 4.0
    private static let rim = 0.26, shoulder = 0.62, tip = 0.86, half = 0.13

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let on = Ease.clamp((t - 0.3) / 0.2) * (1 - Ease.clamp((t - 2.3) / 0.3))
        if on > 0.3 {
            for side in [-1.0, 1.0] {
                var arc = Path()
                arc.addArc(center: u.pt(0.5, 0.56), radius: u.len(0.32), startAngle: .degrees(side > 0 ? -25 : 155),
                           endAngle: .degrees(side > 0 ? 25 : 205), clockwise: false)
                u.stroke(context, arc, tint.opacity(0.5 * on), 0.035)
            }
        }
        let flick = sin(.pi * Ease.clamp((t - 3.2) / 0.5))
        var tube = context
        let pivot = u.pt(0.5, 0.5)
        tube.translateBy(x: pivot.x + u.len(0.006 * sin(t * 70) * on), y: pivot.y)
        tube.rotate(by: .degrees(-16 * flick))
        tube.translateBy(x: -pivot.x, y: -pivot.y)

        let outline = BenchShapes.tube(u, x: 0.5, rim: rim, shoulder: shoulder, tip: tip, half: half)
        BenchShapes.fill(tube, u, outline, from: 0.4, tint.opacity(0.15))
        var inside = tube
        var body = outline
        body.closeSubpath()
        inside.clip(to: body)
        var packed = 0.0
        for k in 0..<14 {
            let s = Double(k)
            let home = (0.5 + (BenchShapes.rand(s) - 0.5) * 0.2, 0.44 + BenchShapes.rand(s + 40) * 0.2)
            let settle = Ease.inOut((t - 0.5 - 0.08 * s) / 1.0) * (1 - Ease.inOut((t - 3.25 - 0.02 * s) / 0.5))
            let pelleted = Ease.clamp((settle - 0.8) / 0.2)
            packed += pelleted / 14
            let p = (home.0 + (0.5 - home.0) * settle, home.1 + (tip - 0.05 - home.1) * settle)
            if pelleted < 1 { inside.fill(u.circle(p.0, p.1, 0.02 * (1 - pelleted)), with: .color(clay)) }
        }
        if packed > 0 {
            inside.fill(u.ellipse(0.5, tip - 0.035, 0.08 * sqrt(packed), 0.055 * sqrt(packed)), with: .color(clay))
        }
        u.stroke(tube, outline, tint, 0.05)
        // The lid, shut, and its hinge.
        tube.fill(u.capsule(0.5, rim - 0.03, 2 * half + 0.05, 0.05, corner: 0.02), with: .color(tint))
        u.stroke(tube, u.line((0.5 + half + 0.02, rim - 0.03), (0.5 + half + 0.06, rim + 0.04)), tint, 0.04)
    }
}

/// A multichannel pipette filling a plate: four tips come down into a row
/// of wells and fill the whole row at once with clay, lift, and move on to
/// the next row.
enum Multichannel {
    static let duration = 4.2
    private static let columns = [0.23, 0.41, 0.59, 0.77]
    private static let rows = [0.5, 0.64, 0.78]
    private static let starts = [0.3, 1.45, 2.6]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reset = Ease.inOut((t - 3.55) / 0.45)
        u.stroke(context, u.capsule(0.5, 0.64, 0.84, 0.44, corner: 0.05), tint, 0.045)
        for (r, y) in rows.enumerated() {
            for x in columns {
                let fill = Ease.inOut((t - starts[r] - 0.3) / 0.25) * (1 - reset)
                if fill > 0 { context.fill(u.ellipse(x, y, 0.12, 0.07), with: .color(clay.opacity(fill))) }
                u.stroke(context, u.ellipse(x, y, 0.12, 0.07), tint.opacity(0.5), 0.025)
            }
        }
        // Where the pipette is: over which row, how far down, and whether
        // its tips hold sample.
        var row = 0.0, down = 0.0, loaded = 1.0
        for (r, s) in starts.enumerated() {
            if r > 0 { row += Ease.inOut((t - s + 0.3) / 0.28) }
            down += Ease.inOut((t - s) / 0.25) - Ease.inOut((t - s - 0.6) / 0.25)
            loaded -= Ease.inOut((t - s - 0.3) / 0.25) - Ease.inOut((t - s - 0.9) / 0.2)
        }
        row -= 2 * reset
        let end = rows[0] + 0.14 * row - 0.13 + 0.125 * down
        let top = end - 0.13
        for x in columns {
            if loaded > 0 {
                var drop = u.line((x - 0.011, end - 0.07), (x, end), (x + 0.011, end - 0.07))
                drop.closeSubpath()
                context.fill(drop, with: .color(clay.opacity(loaded)))
            }
            var cone = u.line((x - 0.02, top), (x, end), (x + 0.02, top))
            cone.closeSubpath()
            u.stroke(context, cone, tint, 0.022)
        }
        context.fill(u.capsule(0.5, top - 0.03, 0.66, 0.06, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(0.5, top - 0.17, 0.11, 0.24, corner: 0.05), with: .color(tint))
    }
}

/// Developing a western blot: the substrate sweeps across the membrane and
/// the bands come up behind it, blurred at first and then sharp: a ladder,
/// a clay band that strengthens lane by lane, and a loading control.
enum BlotDevelop {
    static let duration = 4.2
    private static let lanes = [0.25, 0.42, 0.58, 0.75]
    private static let bands: [(lane: Int, y: Double, strength: Double, target: Bool)] = [
        (0, 0.3, 0.8, false), (0, 0.41, 0.8, false), (0, 0.54, 0.8, false), (0, 0.68, 0.8, false),
        (1, 0.47, 0.5, true), (2, 0.47, 0.8, true), (3, 0.47, 1.0, true),
        (1, 0.72, 0.9, false), (2, 0.72, 0.9, false), (3, 0.72, 0.9, false),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.6) / 0.5)
        u.stroke(context, u.capsule(0.5, 0.52, 0.76, 0.66, corner: 0.04), tint, 0.045)
        for band in bands {
            let x = lanes[band.lane]
            let passed = 0.2 + 1.2 * (x - 0.12) / 0.76
            let appear = Ease.clamp((t - passed) / 0.2)
            guard appear > 0 else { continue }
            let sharp = Ease.inOut((t - passed) / 1.0)
            let height = 0.04 + 0.05 * (1 - sharp)
            let alpha = band.strength * (0.25 + 0.75 * sharp) * appear * (1 - fade)
            context.fill(u.capsule(x, band.y, 0.13, height, corner: height / 2),
                         with: .color((band.target ? clay : tint).opacity(alpha)))
        }
        let sweep = Ease.inOut((t - 0.2) / 1.2)
        let glow = sin(.pi * sweep)
        if glow > 0 {
            let x = 0.12 + 0.76 * sweep
            u.stroke(context, u.line((x, 0.24), (x, 0.8)), clay.opacity(glow), 0.03)
        }
    }
}

/// An orbital shaker: the platform circles and two flasks ride on it, the
/// clay culture in each sloshing round a beat behind.
enum OrbitalShaker {
    static let duration = 3.6
    private static let period = 0.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let a = t * 2 * .pi / period
        let shift = (0.025 * cos(a), 0.01 * sin(a))
        context.fill(u.capsule(0.5, 0.88, 0.76, 0.12, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(0.5 + shift.0, 0.785 + shift.1, 0.86, 0.045, corner: 0.02), with: .color(tint))
        for x0 in [0.29, 0.71] {
            let x = x0 + shift.0, base = 0.76 + shift.1
            let flask = u.line((x - 0.035, base - 0.4), (x - 0.035, base - 0.28), (x - 0.15, base), (x + 0.15, base),
                               (x + 0.035, base - 0.28), (x + 0.035, base - 0.4))
            var body = flask
            body.closeSubpath()
            var inside = context
            inside.clip(to: body)
            let tilt = 0.05 * sin(a - .pi / 2)
            let level = base - 0.13
            var liquid = u.line((x - 0.2, level + tilt), (x + 0.2, level - tilt), (x + 0.2, base + 0.05), (x - 0.2, base + 0.05))
            liquid.closeSubpath()
            inside.fill(liquid, with: .color(clay))
            u.stroke(context, flask, tint, 0.045)
            context.fill(u.capsule(x, base - 0.41, 0.1, 0.045, corner: 0.02), with: .color(tint))
        }
    }
}

/// A culture flask from above: a few clay cells settle, spread and divide
/// until they cover the floor, then round up and wash out to be passaged.
enum CultureFlask {
    static let duration = 4.6
    /// When each cell of the five-by-four floor appears: two seeded, the
    /// rest filling in around them.
    private static let born: [Double] = [
        1.6, 1.1, 1.5, 2.2, 2.5,
        1.2, 0.2, 1.0, 1.8, 2.3,
        1.7, 1.3, 1.9, 0.6, 1.4,
        2.4, 2.0, 1.6, 1.1, 2.1,
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let body = u.capsule(0.42, 0.52, 0.64, 0.5, corner: 0.05)
        context.fill(body, with: .color(tint.opacity(0.1)))
        var floor = context
        floor.clip(to: body)
        let round = Ease.inOut((t - 3.3) / 0.4)
        let gone = Ease.inOut((t - 3.8) / 0.5)
        for (k, at) in born.enumerated() {
            let s = Double(k)
            let grow = Ease.outBack((t - at) / 0.35)
            guard grow > 0, gone < 1 else { continue }
            let col = Double(k % 5), row = Double(k / 5)
            let x = 0.17 + 0.125 * col + 0.04 * (BenchShapes.rand(s) - 0.5) + 0.36 * gone
            let y = 0.33 + 0.125 * row + 0.04 * (BenchShapes.rand(s + 9) - 0.5)
            let w = (0.105 + (0.06 - 0.105) * round) * grow
            let h = (0.058 + (0.06 - 0.058) * round) * grow
            var cell = floor
            let c = u.pt(x, y)
            cell.translateBy(x: c.x, y: c.y)
            cell.rotate(by: .radians(.pi * BenchShapes.rand(s + 3)))
            cell.fill(Path(ellipseIn: CGRect(x: -u.len(w / 2), y: -u.len(h / 2), width: u.len(w), height: u.len(h))),
                      with: .color(clay.opacity(1 - gone)))
        }
        u.stroke(context, body, tint, 0.045)
        u.stroke(context, u.line((0.74, 0.42), (0.83, 0.46), (0.83, 0.58), (0.74, 0.62)), tint, 0.045)
        context.fill(u.capsule(0.88, 0.52, 0.08, 0.16, corner: 0.02), with: .color(tint))
    }
}

/// A thermocycler: the lid comes down on the tubes and the block steps
/// through three cycles, hot, cool and warm, glowing clay when it's hot,
/// while the temperature trace draws out beneath it.
enum Thermocycler {
    static let duration = 4.8
    private static let cycle = 1.1, first = 0.7, warm = 0.43

    /// The block's temperature, as a share of the way from 55 to 95 °C.
    private static func heat(_ t: Double) -> Double {
        let x = t - first
        guard x > 0, x < 3 * cycle else { return warm }
        let s = x.truncatingRemainder(dividingBy: cycle) / cycle
        if s < 0.33 { return warm + (1 - warm) * Ease.clamp(s / 0.06) }
        if s < 0.66 { return 1 - Ease.clamp((s - 0.33) / 0.06) }
        return warm * Ease.clamp((s - 0.66) / 0.06)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let closed = Ease.inOut((t - 0.15) / 0.45) - Ease.inOut((t - 4.2) / 0.45)
        let fade = Ease.inOut((t - 4.2) / 0.5)
        for k in 0..<5 {
            u.stroke(context, u.capsule(0.3 + 0.1 * Double(k), 0.35, 0.05, 0.06, corner: 0.015), tint, 0.03)
        }
        context.fill(u.capsule(0.5, 0.18 + 0.12 * closed, 0.74, 0.07, corner: 0.025), with: .color(tint))
        let hot = heat(t)
        context.fill(u.capsule(0.5, 0.4, 0.62, 0.05, corner: 0.015), with: .color(tint.opacity(0.35)))
        context.fill(u.capsule(0.5, 0.4, 0.62, 0.05, corner: 0.015), with: .color(clay.opacity(hot * hot)))
        context.fill(u.capsule(0.5, 0.52, 0.76, 0.18, corner: 0.04), with: .color(tint))

        u.stroke(context, u.line((0.1, 0.9), (0.9, 0.9)), tint.opacity(0.25 * (1 - fade)), 0.02)
        let end = min(t, first + 3 * cycle)
        guard end > first else { return }
        let trace = stride(from: first, through: end, by: 0.01).map { s in
            (0.1 + 0.8 * (s - first) / (3 * cycle), 0.9 - 0.18 * heat(s))
        }
        u.stroke(context, u.polyline(trace), tint.opacity(1 - fade), 0.03)
        if let pen = trace.last { context.fill(u.circle(pen.0, pen.1, 0.026), with: .color(clay.opacity(1 - fade))) }
    }
}

/// A tube rack: tubes of clay sample drop into their places one by one
/// and snap their lids shut, then lift away together.
enum TubeRack {
    static let duration = 4.4
    private static let slots = [0.22, 0.41, 0.59, 0.78]
    private static let rim = 0.34, shoulder = 0.68, tip = 0.8, half = 0.06

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lift = Ease.inOut((t - 3.6) / 0.5)
        for (k, x) in slots.enumerated() {
            let s = Double(k)
            let drop = Ease.outBack((t - 0.2 - 0.45 * s) / 0.45)
            guard drop > 0 else { continue }
            var tube = context
            tube.translateBy(x: 0, y: u.len(-0.7 * (1 - drop) - 0.9 * lift))
            let outline = BenchShapes.tube(u, x: x, rim: rim, shoulder: shoulder, tip: tip, half: half)
            BenchShapes.fill(tube, u, outline, from: 0.58, clay)
            u.stroke(tube, outline, tint, 0.04)
            // The lid swings over from its hinge and snaps shut.
            let shut = Ease.out((t - 2.2 - 0.18 * s) / 0.25)
            let hinge = u.pt(x + half, rim)
            var lid = tube
            lid.translateBy(x: hinge.x, y: hinge.y)
            lid.rotate(by: .degrees(120 * (1 - shut)))
            lid.translateBy(x: -hinge.x, y: -hinge.y)
            u.stroke(lid, u.line((x + half, rim - 0.015), (x - half - 0.01, rim - 0.015)), tint, 0.045)
        }
        // The rack: a top plate the tubes stand through, a floor, two ends.
        context.fill(u.capsule(0.5, 0.52, 0.88, 0.05, corner: 0.02), with: .color(tint))
        context.fill(u.capsule(0.5, 0.88, 0.88, 0.04, corner: 0.02), with: .color(tint))
        u.stroke(context, u.line((0.08, 0.52), (0.08, 0.88)), tint, 0.045)
        u.stroke(context, u.line((0.92, 0.52), (0.92, 0.88)), tint, 0.045)
    }
}

/// A spin column: the sample drains through the silica membrane, its clay
/// DNA staying behind on it while the rest drips through below.
enum SpinColumn {
    static let duration = 4.4
    private static let membrane = 0.52

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let reset = Ease.inOut((t - 3.7) / 0.5)
        let drained = Ease.inOut((t - 0.5) / 1.8) * (1 - reset)
        // The collection tube, with the flow-through rising in it.
        let outer = u.line((0.33, 0.34), (0.33, 0.8), (0.4, 0.9), (0.6, 0.9), (0.67, 0.8), (0.67, 0.34))
        let pool = 0.9 - 0.12 * drained
        BenchShapes.fill(context, u, outer, from: pool, tint.opacity(0.3))
        u.stroke(context, outer, tint, 0.045)
        // The sample in the column, falling to the membrane.
        let column = u.line((0.39, 0.18), (0.39, 0.56), (0.47, 0.64), (0.53, 0.64), (0.61, 0.56), (0.61, 0.18))
        let level = 0.28 + (membrane - 0.28) * drained
        var sample = context
        sample.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, level).y, width: u.side, height: u.len(membrane - level))))
        BenchShapes.fill(sample, u, column, from: level, tint.opacity(0.18))
        for k in 0..<8 {
            let s = Double(k)
            let home = (0.43 + 0.14 * BenchShapes.rand(s + 5), 0.31 + 0.18 * BenchShapes.rand(s + 17))
            let y = home.1 + (membrane - 0.015 - home.1) * drained
            let bound = Ease.clamp((drained - 0.85) / 0.15)
            if bound < 1 { context.fill(u.circle(home.0, max(y, level + 0.02), 0.018 * (1 - bound)), with: .color(clay)) }
        }
        // Drips from the column's outlet into the tube below.
        if drained > 0.02, drained < 0.98 {
            let phase = (t * 4).truncatingRemainder(dividingBy: 1)
            context.fill(u.circle(0.5, 0.66 + (pool - 0.68) * phase * phase, 0.015), with: .color(tint.opacity(0.6)))
        }
        u.stroke(context, column, tint, 0.045)
        u.stroke(context, u.line((0.3, 0.3), (0.39, 0.3)), tint, 0.045)
        u.stroke(context, u.line((0.61, 0.3), (0.7, 0.3)), tint, 0.045)
        u.stroke(context, u.line((0.41, membrane), (0.59, membrane)), tint, 0.04)
        u.stroke(context, u.line((0.41, membrane), (0.59, membrane)), clay.opacity(drained), 0.04)
    }
}

/// A separating funnel: freshly shaken, the two liquids are a cloud of clay
/// drops; left to stand, the drops sink and gather into a clean lower
/// layer, until the funnel is shaken again.
enum PhaseSeparation {
    static let duration = 4.4
    private static let bottom = 0.76, interface = 0.58, surface = 0.36

    private static func outline(_ u: UnitSquare) -> Path {
        let left = Smooth.curve([(0.45, 0.16), (0.45, 0.22), (0.3, 0.32), (0.25, 0.45), (0.32, 0.6), (0.47, bottom)], samples: 6)
        let right = left.reversed().map { (1 - $0.0, $0.1) }
        return u.polyline(left + right)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let shaking = Ease.clamp((t - 3.5) / 0.1) * (1 - Ease.clamp((t - 4.2) / 0.15))
        var funnel = context
        let pivot = u.pt(0.5, 0.45)
        funnel.translateBy(x: pivot.x, y: pivot.y)
        funnel.rotate(by: .degrees(12 * shaking * sin((t - 3.5) * 2 * .pi * 3)))
        funnel.translateBy(x: -pivot.x, y: -pivot.y)

        let glass = outline(u)
        var body = glass
        body.closeSubpath()
        var inside = funnel
        inside.clip(to: body)
        inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, surface).y, width: u.side, height: u.side)), with: .color(tint.opacity(0.15)))
        let remix = Ease.inOut((t - 3.6) / 0.5)
        var gathered = 0.0
        var drops: [(Double, Double, Double)] = []
        for k in 0..<18 {
            let s = Double(k)
            let y0 = 0.4 + 0.26 * BenchShapes.rand(s + 2)
            let narrow = 1 - 3.5 * max(0, y0 - 0.55)
            let x0 = 0.5 + (BenchShapes.rand(s + 30) - 0.5) * 0.3 * narrow
            let sink = Ease.inOut((t - 0.3 - 0.1 * s) / 1.0) * (1 - remix)
            let merged = Ease.clamp((sink - 0.85) / 0.15)
            gathered += merged / 18
            drops.append((x0 + (0.5 - x0) * sink * 0.3, y0 + (0.7 - y0) * sink, 0.022 * (1 - merged)))
        }
        let layer = bottom - (bottom - interface) * gathered
        inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, layer).y, width: u.side, height: u.side)), with: .color(clay))
        for d in drops where d.2 > 0.001 { inside.fill(u.circle(d.0, d.1, d.2), with: .color(clay)) }
        u.stroke(funnel, glass, tint, 0.045)
        u.stroke(funnel, u.line((0.5, bottom), (0.5, 0.94)), tint, 0.04)
        funnel.fill(u.capsule(0.5, 0.82, 0.14, 0.04, corner: 0.02), with: .color(tint))
        funnel.fill(u.capsule(0.5, 0.13, 0.13, 0.06, corner: 0.02), with: .color(tint))
    }
}

/// Colony picking: a tip comes down on one clay colony at a time, lifts it
/// off the agar and carries it away; three picks, and the plate regrows.
enum ColonyPicking {
    static let duration = 4.4
    private static let colonies: [(x: Double, y: Double, r: Double)] = [
        (0.3, 0.47, 0.045), (0.52, 0.36, 0.035), (0.62, 0.64, 0.05), (0.38, 0.72, 0.035),
        (0.72, 0.46, 0.03), (0.47, 0.56, 0.03), (0.26, 0.62, 0.028),
    ]
    private static let picks = [0, 2, 3]
    private static let starts = [0.2, 1.45, 2.7]
    private static let away = (1.1, 0.02)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.circle(0.48, 0.56, 0.35), with: .color(tint.opacity(0.12)))
        u.stroke(context, u.circle(0.48, 0.56, 0.38), tint, 0.045)
        let regrow = Ease.inOut((t - 3.9) / 0.4)
        for (k, c) in colonies.enumerated() {
            var scale = 1.0
            if let j = picks.firstIndex(of: k) {
                scale = 1 - Ease.inOut((t - starts[j] - 0.55) / 0.12) * (1 - regrow)
            }
            if scale > 0.01 { context.fill(u.circle(c.x, c.y, c.r * scale), with: .color(clay)) }
        }
        // The tip: where it is, and whether it carries a colony.
        var at = away, carrying = false
        for (j, s) in starts.enumerated() where t >= s && t < s + 1.25 {
            let c = colonies[picks[j]]
            let hover = (c.x, c.y - 0.07)
            let come = Ease.inOut((t - s) / 0.45)
            let dip = Ease.inOut((t - s - 0.45) / 0.12) - Ease.inOut((t - s - 0.62) / 0.15)
            let go = Ease.inOut((t - s - 0.8) / 0.4)
            let over = (away.0 + (hover.0 - away.0) * come, away.1 + (hover.1 - away.1) * come)
            at = (over.0 + (away.0 - over.0) * go, over.1 + 0.07 * dip + (away.1 - over.1) * go)
            carrying = t > s + 0.55
        }
        var cone = u.line((at.0 - 0.045, at.1 - 0.34), (at.0 - 0.009, at.1), (at.0 + 0.009, at.1), (at.0 + 0.045, at.1 - 0.34))
        cone.closeSubpath()
        context.fill(cone, with: .color(tint))
        if carrying { context.fill(u.circle(at.0, at.1 + 0.008, 0.028), with: .color(clay)) }
    }
}
