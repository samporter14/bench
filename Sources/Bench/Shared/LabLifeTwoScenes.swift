// LabLifeTwoScenes.swift
// ScienceStatus — more lab life: writing it up, the laptop, the gas, the
// mice, the little centrifuge, the microwave. Each draws in a unit square
// (see `UnitSquare`): things in the tint, the living or lit part in clay.

import SwiftUI

/// Writing the paper: keys go down in a typing rhythm, lines of text run
/// across the page above with the clay cursor at their end, and a figure
/// drops in.
enum Typing {
    static let duration = 4.4
    private static let lines: [(y: Double, length: Double)] = [(0.13, 0.2), (0.19, 0.42), (0.24, 0.4), (0.29, 0.36)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.0) / 0.35)
        var page = context
        page.opacity = 1 - fade
        u.stroke(page, u.capsule(0.5, 0.25, 0.56, 0.36, corner: 0.02), tint, 0.03)
        var cursor = (0.28, 0.13)
        for (k, line) in lines.enumerated() {
            let s = Ease.clamp((t - 0.2 - 0.6 * Double(k)) / 0.55)
            guard s > 0 else { continue }
            let end = 0.28 + line.length * s
            u.stroke(page, u.line((0.28, line.y), (end, line.y)), k == 0 ? tint : tint.opacity(0.55), k == 0 ? 0.03 : 0.02)
            cursor = (end + 0.015, line.y)
        }
        let figure = Ease.outBack((t - 2.7) / 0.4)
        if figure > 0 {
            u.stroke(page, u.capsule(0.5, 0.36, 0.2 * figure, 0.06 * figure, corner: 0.005), tint.opacity(0.6), 0.015)
            let curve = stride(from: 0.0, through: 1.0, by: 0.1).map { s -> (Double, Double) in
                let rise: Double = 1 - exp(-4 * s)
                return (0.41 + 0.18 * s * figure, 0.385 - 0.045 * rise * figure)
            }
            u.stroke(page, u.polyline(curve), clay, 0.018)
        }
        if t < 2.7 && sin(t * 14) > -0.3 { u.stroke(page, u.line((cursor.0, cursor.1 - 0.018), (cursor.0, cursor.1 + 0.018)), clay, 0.014) }

        // The keyboard.
        u.stroke(context, u.capsule(0.5, 0.72, 0.84, 0.36, corner: 0.03), tint, 0.03)
        let press = Int(t / 0.09)
        let typing = t > 0.2 && t < 2.6
        let rows: [(count: Int, y: Double, shift: Double)] = [(10, 0.61, 0), (9, 0.68, 0.035), (7, 0.75, 0.07)]
        for (r, row) in rows.enumerated() {
            for k in 0..<row.count {
                let x = 0.155 + row.shift + 0.077 * Double(k)
                let lit = typing && Int(BenchShapes.rand(Double(press)) * 26) == r * 10 + k
                context.fill(u.capsule(x, row.y, 0.06, 0.055, corner: 0.01), with: .color(lit ? clay : tint.opacity(0.35)))
            }
        }
        let space = typing && press % 6 == 5
        context.fill(u.capsule(0.5, 0.82, 0.36, 0.05, corner: 0.01), with: .color(space ? clay : tint.opacity(0.35)))
    }
}

/// A laptop covered in science stickers opens: the lid swings up, the
/// stickered back turning away to the screen, which lights up.
enum Laptop {
    static let duration = 4.6
    private static let elevation = 30.0 * .pi / 180
    private static let left = 0.2, right = 0.8, deep = 0.4, lid = 0.4, front = 0.8

    /// Screen position of a point `depth` back and `height` up.
    private static func at(_ x: Double, _ depth: Double, _ height: Double) -> (Double, Double) {
        (x, front - depth * sin(elevation) - height * cos(elevation))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let angle = Keyframes.value(t, [(1.0, 0), (2.0, 105), (3.7, 105), (4.3, 0)]) * .pi / 180
        // The base: its top, keys and trackpad, and a sliver of its front.
        var base = u.polyline([at(left, 0, 0), at(right, 0, 0), at(right, deep, 0), at(left, deep, 0)])
        base.closeSubpath()
        context.fill(base, with: .color(tint.opacity(0.18)))
        u.stroke(context, base, tint, 0.025)
        context.fill(u.capsule(0.5, front + 0.012, right - left, 0.024, corner: 0.008), with: .color(tint))
        if angle > 0.3 {
            for r in 0..<3 {
                let depth = 0.3 - 0.06 * Double(r)
                u.stroke(context, u.line(at(0.26, depth, 0), at(0.74, depth, 0)), tint.opacity(0.35), 0.02)
            }
            var pad = u.polyline([at(0.42, 0.05, 0), at(0.58, 0.05, 0), at(0.58, 0.13, 0), at(0.42, 0.13, 0)])
            pad.closeSubpath()
            u.stroke(context, pad, tint.opacity(0.35), 0.015)
        }
        // The lid, as a transform of its own unit square: x along the
        // hinge, y from the hinge to its free edge.
        let hingeLeft = at(left, deep, 0.012), hingeRight = at(right, deep, 0.012)
        let freeLeft = at(left, deep - lid * cos(angle), 0.012 + lid * sin(angle))
        var face = context
        let o = u.pt(hingeLeft.0, hingeLeft.1), xAxis = u.pt(hingeRight.0, hingeRight.1), yAxis = u.pt(freeLeft.0, freeLeft.1)
        face.concatenate(CGAffineTransform(a: xAxis.x - o.x, b: xAxis.y - o.y, c: yAxis.x - o.x, d: yAxis.y - o.y, tx: o.x, ty: o.y))
        // The lid's own unit square: a transformed space, so no point floors.
        let unit = UnitSquare(CGSize(width: 1, height: 1), floors: false)
        if angle < elevation {
            face.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 1, height: 1), cornerRadius: 0.04), with: .color(tint))
            // Stickers on the back of the lid.
            face.fill(unit.circle(0.2, 0.45, 0.1), with: .color(clay))
            face.fill(unit.circle(0.2, 0.45, 0.04), with: .color(tint))
            var flask = unit.line((0.46, 0.2), (0.46, 0.38), (0.38, 0.68), (0.62, 0.68), (0.54, 0.38), (0.54, 0.2))
            flask.closeSubpath()
            face.fill(flask, with: .color(clay))
            for side in [-1.0, 1.0] {
                let strand = stride(from: 0.0, through: 1.0, by: 0.05).map { s in (0.76 + 0.05 * side * sin(s * 4 * .pi), 0.2 + 0.5 * s) }
                unit.stroke(face, unit.polyline(strand), clay, 0.035)
            }
            for k in 0..<3 {
                var orbit = face
                orbit.translateBy(x: 0.36, y: 0.82)
                orbit.rotate(by: .degrees(60 * Double(k)))
                orbit.stroke(Path(ellipseIn: CGRect(x: -0.08, y: -0.03, width: 0.16, height: 0.06)), with: .color(clay), lineWidth: 0.02)
            }
            face.fill(unit.capsule(0.66, 0.84, 0.16, 0.1, corner: 0.03), with: .color(clay.opacity(0.8)))
        } else {
            // The screen, cut into the lid, lighting up.
            let lit = Ease.clamp((t - 2.0) / 0.3) * (1 - Ease.clamp((t - 3.7) / 0.2))
            face.drawLayer { bezel in
                bezel.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 1, height: 1), cornerRadius: 0.04), with: .color(tint))
                bezel.blendMode = .destinationOut
                bezel.fill(Path(roundedRect: CGRect(x: 0.05, y: 0.06, width: 0.9, height: 0.88), cornerRadius: 0.02), with: .color(.black))
            }
            if lit > 0 {
                for k in 0..<3 {
                    unit.stroke(face, unit.line((0.14, 0.72 - 0.12 * Double(k)), (0.14 + [0.5, 0.36, 0.44][k], 0.72 - 0.12 * Double(k))), tint.opacity(lit), 0.03)
                }
                let curve = stride(from: 0.0, through: 1.0, by: 0.1).map { s -> (Double, Double) in
                    let rise: Double = 1 - exp(-4 * s)
                    return (0.62 + 0.26 * s, 0.2 + 0.26 * rise)
                }
                unit.stroke(face, unit.polyline(curve), clay.opacity(lit), 0.035)
            }
        }
    }
}

/// Hooking up the CO₂: the regulator goes on, the valve wheel turns, the
/// clay needles rise on its gauges, and gas runs down the line to the
/// incubator, whose reading climbs.
enum GasCylinders {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for x in [0.16, 0.36] {
            u.stroke(context, u.capsule(x, 0.62, 0.15, 0.6, corner: 0.07), tint, 0.03)
            u.stroke(context, u.line((x - 0.075, 0.44), (x + 0.075, 0.44)), tint.opacity(0.5), 0.02)
        }
        u.stroke(context, u.line((0.04, 0.5), (0.48, 0.5)), tint.opacity(0.4), 0.018)
        let on = Ease.out((t - 0.3) / 0.4)
        let wheel = Ease.inOut((t - 0.9) / 0.5)
        let pressure = Ease.inOut((t - 1.4) / 0.6)
        context.fill(u.capsule(0.36, 0.29, 0.04, 0.06, corner: 0.01), with: .color(tint))
        var valve = context
        let v = u.pt(0.36, 0.25)
        valve.translateBy(x: v.x, y: v.y)
        valve.scaleBy(x: cos(wheel * 2 * .pi) * 0.8 + 0.2, y: 1)
        valve.fill(Path(ellipseIn: CGRect(x: -u.len(0.05), y: -u.len(0.012), width: u.len(0.1), height: u.len(0.024))), with: .color(tint))
        let reg = (0.36 + 0.1 * (1 - on), 0.3 - 0.2 * (1 - on))
        context.fill(u.capsule(reg.0 + 0.05, reg.1, 0.1, 0.05, corner: 0.012), with: .color(tint))
        for (k, g) in [(reg.0 + 0.05, reg.1 - 0.08), (reg.0 + 0.14, reg.1)].enumerated() {
            u.stroke(context, u.circle(g.0, g.1, 0.04), tint, 0.02)
            let a = (-220 + 200 * pressure * (k == 0 ? 1 : 0.6)) * .pi / 180
            u.stroke(context, u.line(g, (g.0 + 0.03 * cos(a), g.1 + 0.03 * sin(a))), clay, 0.015)
        }
        // The line to the incubator.
        let line = [(reg.0 + 0.18, reg.1), (0.66, 0.3), (0.66, 0.46)]
        u.stroke(context, u.polyline(line), tint.opacity(0.6), 0.02)
        if pressure > 0.5 && t < 4.0 {
            let period = 0.07
            context.stroke(u.polyline(line), with: .color(clay),
                           style: StrokeStyle(lineWidth: u.len(0.014), lineCap: .round, dash: [u.len(0.02), u.len(0.05)],
                                              dashPhase: u.len(period - (t * 0.2).truncatingRemainder(dividingBy: period))))
        }
        u.stroke(context, u.capsule(0.77, 0.66, 0.34, 0.44, corner: 0.03), tint, 0.03)
        let level = Ease.inOut((t - 2.0) / 1.6) * (1 - Ease.inOut((t - 4.1) / 0.4))
        u.stroke(context, u.capsule(0.77, 0.52, 0.2, 0.05, corner: 0.01), tint.opacity(0.5), 0.015)
        if level > 0 { context.fill(u.capsule(0.67 + 0.1 * level, 0.52, 0.2 * level, 0.035, corner: 0.008), with: .color(clay)) }
    }
}

/// A lab mouse at the water bottle: it trots over, rears up to the sipper
/// and drinks, and bubbles rise into the bottle.
enum MouseWater {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.88), (0.98, 0.88)), tint, 0.035)
        for k in 0..<10 { context.fill(u.circle(0.06 + 0.1 * Double(k), 0.87, 0.018), with: .color(tint.opacity(0.35))) }
        u.stroke(context, u.line((0.02, 0.1), (0.98, 0.1)), tint.opacity(0.5), 0.02)
        for k in 0..<9 { u.stroke(context, u.line((0.1 * Double(k) + 0.1, 0.1), (0.1 * Double(k) + 0.1, 0.16)), tint.opacity(0.4), 0.015) }
        // The bottle, through the lid at a slant, and its sipper.
        var bottle = context
        let b = u.pt(0.78, 0.2)
        bottle.translateBy(x: b.x, y: b.y)
        bottle.rotate(by: .degrees(35))
        bottle.translateBy(x: -b.x, y: -b.y)
        let drunk = Ease.clamp((t - 2.0) / 1.8) * (1 - Ease.clamp((t - 4.2) / 0.3))
        let glass = u.line((0.7, 0.28), (0.7, -0.12), (0.86, -0.12), (0.86, 0.28))
        BenchShapes.fill(bottle, u, glass, from: -0.06 + 0.06 * drunk, tint.opacity(0.25))
        u.stroke(bottle, glass, tint, 0.03)
        bottle.fill(u.capsule(0.78, 0.3, 0.18, 0.04, corner: 0.01), with: .color(tint))
        u.stroke(bottle, u.line((0.78, 0.32), (0.78, 0.62)), tint, 0.025)
        for k in 0..<3 {
            let rise = ((t * 1.2 + Double(k) / 3).truncatingRemainder(dividingBy: 1))
            guard t > 2.1, t < 3.9 else { continue }
            bottle.fill(u.circle(0.78 + 0.02 * sin(Double(k) * 2), 0.26 - 0.3 * rise, 0.012 + 0.008 * rise), with: .color(clay.opacity(1 - rise * 0.5)))
        }
        // The mouse: over, up, drinking, down.
        let x = Keyframes.value(t, [(0.2, 0.16), (1.3, 0.45), (4.0, 0.45), (4.5, 0.38)])
        let rear = Keyframes.value(t, [(1.4, 0), (1.8, 1), (3.8, 1), (4.2, 0)])
        var mouse = context
        let feet = u.pt(x - 0.08, 0.84)
        mouse.translateBy(x: feet.x, y: feet.y)
        mouse.rotate(by: .degrees(-48 * rear))
        mouse.translateBy(x: -feet.x, y: -feet.y)
        let walking = t > 0.2 && t < 1.3
        MouseShape.draw(mouse, u, at: (x, 0.78), scale: 0.5, tint: tint, twitch: 8 * sin(t * 9), nose: rear > 0.9 ? 0.02 * sin(t * 20) : 0,
                        tail: sin(t * 3), stride: walking ? t * 18 : nil)
    }
}

/// The bubble centrifuge: the clear dome drops on, the little rotor spins
/// its two tubes up and down, and the clay drops are all at the bottom
/// after. The tubes sit as they do in a fixed-angle rotor, caps leaning in
/// to the spindle and bottoms out, all inside the dome.
enum BubbleCentrifuge {
    static let duration = 4.0
    private static let cap = (r: 0.06, y: 0.53), bottom = (r: 0.17, y: 0.64)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.capsule(0.5, 0.8, 0.6, 0.14, corner: 0.07), with: .color(tint))
        let spin = Keyframes.value(t, [(0.8, 0), (1.3, 1), (2.6, 1), (3.1, 0)])
        let angle = 0.35 + t * 30 * spin
        let spun = Ease.clamp((t - 1.3) / 0.8)
        context.fill(u.ellipse(0.5, 0.665, 0.42, 0.06), with: .color(tint.opacity(0.45)))
        // Back tube first, then the spindle, then the front one.
        let tubes = (0..<2).map { k -> (a: Double, depth: Double) in
            let a = angle + Double(k) * .pi
            return (a, sin(a))
        }.sorted { $0.depth < $1.depth }
        for (i, tube) in tubes.enumerated() {
            let out = cos(tube.a)
            let top = (0.5 + cap.r * out, cap.y), end = (0.5 + bottom.r * out, bottom.y)
            let alpha = tube.depth < 0 ? 0.5 : 1
            u.stroke(context, u.line(top, end), tint.opacity(alpha), 0.075)
            // The drop: on the wall before, collected in the bottom after.
            let at = spun > 0.5 ? 0.86 : 0.45
            let p = (top.0 + (end.0 - top.0) * at, top.1 + (end.1 - top.1) * at)
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(clay.opacity(alpha)))
            context.fill(u.circle(top.0, top.1, 0.03), with: .color(tint.opacity(alpha)))
            if i == 0 { context.fill(u.capsule(0.5, 0.6, 0.05, 0.12, corner: 0.02), with: .color(tint)) }
        }
        let lid = Keyframes.value(t, [(0.2, 1), (0.6, 0), (3.3, 0), (3.7, 1)])
        var dome = Path()
        dome.addArc(center: u.pt(0.5, 0.74 - 0.3 * lid), radius: u.len(0.28), startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        dome.closeSubpath()
        context.fill(dome, with: .color(tint.opacity(0.1)))
        u.stroke(context, dome, tint, 0.025)
        if spin > 0.5 {
            for side in [-1.0, 1.0] {
                var arc = Path()
                arc.addArc(center: u.pt(0.5, 0.62), radius: u.len(0.34), startAngle: .degrees(side > 0 ? -30 : 150),
                           endAngle: .degrees(side > 0 ? 10 : 190), clockwise: false)
                u.stroke(context, arc, tint.opacity(0.5 * spin), 0.025)
            }
        }
    }
}

/// Melting agarose: the flask turns on the microwave's plate, the flakes
/// go and it bubbles, the timer counts down in clay, and it dings.
enum MicrowaveAgarose {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.52, 0.88, 0.64, corner: 0.04), tint, 0.04)
        context.fill(u.capsule(0.4, 0.52, 0.56, 0.5, corner: 0.02), with: .color(tint.opacity(0.08)))
        u.stroke(context, u.capsule(0.4, 0.52, 0.56, 0.5, corner: 0.02), tint.opacity(0.6), 0.02)
        u.stroke(context, u.ellipse(0.4, 0.72, 0.36, 0.06), tint.opacity(0.5), 0.02)
        let heating = Ease.clamp(t / 0.2) * (1 - Ease.clamp((t - 3.4) / 0.1))
        let turn = t * 1.6
        let x = 0.4 + 0.08 * sin(turn)
        let flask = u.line((x - 0.03, 0.42), (x - 0.03, 0.5), (x - 0.1, 0.7), (x + 0.1, 0.7), (x + 0.03, 0.5), (x + 0.03, 0.42))
        let melted = Ease.inOut((t - 0.3) / 2.6)
        BenchShapes.fill(context, u, flask, from: 0.6, tint.opacity(0.35 - 0.15 * melted))
        for k in 0..<8 where melted < 1 {
            let s = Double(k)
            context.fill(u.circle(x - 0.07 + 0.14 * BenchShapes.rand(s), 0.63 + 0.06 * BenchShapes.rand(s + 3), 0.008), with: .color(tint.opacity(1 - melted)))
        }
        for k in 0..<5 where melted > 0.4 && heating > 0 {
            let rise = ((t * 2 + Double(k) / 5).truncatingRemainder(dividingBy: 1))
            context.fill(u.circle(x - 0.06 + 0.03 * Double(k), 0.69 - 0.08 * rise, 0.01), with: .color(clay.opacity(1 - rise)))
        }
        u.stroke(context, flask, tint, 0.025)
        // The panel: a clay countdown and a keypad.
        let left = max(0, 45 - Int(t / 3.4 * 45))
        let digits = [0, left / 10, left % 10]
        for (k, d) in digits.enumerated() {
            SevenSegment.draw(context, u, SevenSegment.digits[d], x: 0.78 + 0.05 * Double(k), y: 0.3, w: 0.03, h: 0.05, color: clay, width: 0.01)
        }
        for r in 0..<3 {
            for c in 0..<2 { context.fill(u.capsule(0.8 + 0.07 * Double(c), 0.44 + 0.08 * Double(r), 0.045, 0.045, corner: 0.01), with: .color(tint.opacity(0.4))) }
        }
        let ding = Ease.clamp((t - 3.4) / 0.4) * (1 - Ease.clamp((t - 4.1) / 0.3))
        if ding > 0 {
            for k in 0..<2 {
                var arc = Path()
                arc.addArc(center: u.pt(0.86, 0.12), radius: u.len(0.04 + 0.03 * Double(k)), startAngle: .degrees(-60), endAngle: .degrees(60), clockwise: false)
                u.stroke(context, arc, clay.opacity(ding), 0.02)
            }
        }
    }
}
