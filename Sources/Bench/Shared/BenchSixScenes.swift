// BenchSixScenes.swift
// ScienceStatus — the small routines: setting volumes, pouring plates,
// labelling, dropping off, measuring, drying, growing. Each draws in a unit
// square (see `UnitSquare`): kit in the tint, samples and readouts in clay.

import SwiftUI

/// Seven-segment digits, for instrument readouts.
enum SevenSegment {
    /// Segments a to g lit for each digit.
    static let digits: [String] = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg"]

    /// Draws `segments` in a cell centred at (x, y), `w` wide and `h` tall.
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, _ segments: String, x: Double, y: Double,
                     w: Double = 0.07, h: Double = 0.09, color: Color, width: Double = 0.016) {
        let hw = w / 2, hh = h / 2
        let ends: [Character: ((Double, Double), (Double, Double))] = [
            "a": ((-hw, -hh), (hw, -hh)), "b": ((hw, -hh), (hw, 0)), "c": ((hw, 0), (hw, hh)), "d": ((-hw, hh), (hw, hh)),
            "e": ((-hw, 0), (-hw, hh)), "f": ((-hw, -hh), (-hw, 0)), "g": ((-hw, 0), (hw, 0)),
        ]
        for s in segments {
            guard let e = ends[s] else { continue }
            u.stroke(context, u.line((x + e.0.0, y + e.0.1), (x + e.1.0, y + e.1.1)), color, width)
        }
    }
}

/// Setting a pipette's volume: the knob twists and the three-digit counter
/// in the handle rolls, 20 to 100 to 200 µL and back.
enum PipetteVolume {
    static let duration = 4.4
    private static let cell = 0.13

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let v = Keyframes.value(t, [(0.3, 20), (1.1, 100), (1.8, 100), (2.6, 200), (3.2, 200), (4.0, 20)])
        // An odometer: each wheel turns over only as the one below it wraps.
        let ones = v.truncatingRemainder(dividingBy: 10)
        let tens = floor(v / 10).truncatingRemainder(dividingBy: 10) + max(0, ones - 9)
        let hundreds = floor(v / 100).truncatingRemainder(dividingBy: 10) + max(0, v.truncatingRemainder(dividingBy: 100) - 99)
        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, 0.62, 0.36, 0.72, corner: 0.12), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.capsule(0.5, 0.6, 0.17, 0.43, corner: 0.025), with: .color(.black))
        }
        for (k, value) in [hundreds, tens, ones].enumerated() {
            let y = 0.47 + cell * Double(k)
            var wheel = context
            wheel.clip(to: u.capsule(0.5, y, 0.17, cell, corner: 0.01))
            let base = floor(value), frac = value - base
            for step in 0...1 {
                let digit = (Int(base) + step) % 10
                SevenSegment.draw(wheel, u, SevenSegment.digits[digit], x: 0.5, y: y + cell * (Double(step) - frac),
                                  w: 0.065, h: 0.09, color: clay, width: 0.018)
            }
        }
        // The knob on top, its ridges running round as it turns.
        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, 0.15, 0.26, 0.12, corner: 0.04), with: .color(tint))
            layer.blendMode = .destinationOut
            for k in 0..<5 {
                let a = v * 0.12 + Double(k) * 2 * .pi / 5
                guard cos(a) > 0.1 else { continue }
                u.stroke(layer, u.line((0.5 + 0.1 * sin(a), 0.11), (0.5 + 0.1 * sin(a), 0.19)), .black, 0.016)
            }
        }
        u.stroke(context, u.line((0.5, 0.21), (0.5, 0.27)), tint, 0.05)
        u.stroke(context, u.line((0.68, 0.36), (0.78, 0.36), (0.78, 0.44)), tint, 0.05)
    }
}

/// Pouring plates: an empty dish slides in; the bottle of molten clay agar
/// stands upright, tips over to pour, the agar level in it as it goes, and
/// stands up again; the lid goes on and the dish joins the stack; three
/// times over.
enum AgarPour {
    static let duration = 4.8
    private static let starts = [0.2, 1.6, 3.0]
    /// The bottle's mouth: where it stands, and where it pours from.
    private static let rest = (0.74, 0.12), pour = (0.6, 0.4)

    private static func dish(_ context: GraphicsContext, _ u: UnitSquare, x: Double, y: Double, fill: Double, lid: Double, tint: Color) {
        let base = u.line((x - 0.17, y - 0.07), (x - 0.17, y), (x + 0.17, y), (x + 0.17, y - 0.07))
        if fill > 0 { BenchShapes.fill(context, u, base, from: y - 0.05 * fill, clay) }
        u.stroke(context, base, tint, 0.035)
        if lid > 0 {
            let top = y - 0.085 - 0.2 * (1 - lid)
            u.stroke(context, u.line((x - 0.19, top + 0.055), (x - 0.19, top), (x + 0.19, top), (x + 0.19, top + 0.055)), tint.opacity(lid), 0.035)
        }
    }

    /// The bottle with its mouth at the origin, standing upright: neck,
    /// shoulders, body down to its base.
    private static func bottle() -> [(Double, Double)] {
        [(-0.05, 0), (-0.05, 0.07), (-0.125, 0.14), (-0.125, 0.42), (0.125, 0.42), (0.125, 0.14), (0.05, 0.07), (0.05, 0)]
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        var tilt = 0.0
        for (j, s) in starts.enumerated() {
            let arrive = Ease.out((t - s) / 0.3)
            guard arrive > 0 else { continue }
            let fill = Ease.inOut((t - s - 0.45) / 0.5)
            let lid = Ease.out((t - s - 0.95) / 0.15)
            let stack = Ease.inOut((t - s - 1.1) / 0.3)
            let x = 1.3 + (0.58 - 1.3) * arrive + (0.22 - 0.58) * stack
            let y = 0.88 + (0.88 - 0.11 * Double(j) - 0.88) * stack
            dish(scene, u, x: x, y: y, fill: fill, lid: lid, tint: tint)
            tilt = max(tilt, sin(.pi * Ease.clamp((t - s - 0.25) / 0.8)))
            if fill > 0, fill < 1 { u.stroke(scene, u.line((pour.0, pour.1 + 0.02), (pour.0, 0.87 - 0.04 * fill)), clay, 0.035) }
        }
        // The bottle: upright at rest, tipped mouth-down over the dish to pour.
        let k = Ease.inOut(tilt)
        let mouth = (rest.0 + (pour.0 - rest.0) * k, rest.1 + (pour.1 - rest.1) * k)
        let angle = -140 * k * .pi / 180
        let m = u.pt(mouth.0, mouth.1)
        let place = CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: m.x, y: m.y))
        var outline = Path()
        outline.addLines(bottle().map { CGPoint(x: u.len($0.0), y: u.len($0.1)) })
        let glass = outline.applying(place)
        var body = outline
        body.closeSubpath()
        // The agar keeps a level surface however the bottle tips.
        var agar = scene
        agar.clip(to: body.applying(place))
        let level = 0.32 + (0.33 - 0.32) * k
        agar.fill(Path(CGRect(x: 0, y: u.pt(0, level).y, width: size.width, height: size.height)), with: .color(clay))
        scene.stroke(glass, with: .color(tint), style: StrokeStyle(lineWidth: max(u.len(0.03), UnitSquare.hairline), lineCap: .round, lineJoin: .round))
    }
}

/// A rocker washing a blot: the platform tips gently back and forth and the
/// wash sloshes over the clay membrane in its tray.
enum RockerBlot {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var base = u.line((0.3, 0.9), (0.44, 0.68), (0.56, 0.68), (0.7, 0.9))
        base.closeSubpath()
        context.fill(base, with: .color(tint))
        u.stroke(context, u.line((0.1, 0.9), (0.9, 0.9)), tint, 0.04)
        let tilt = 10 * sin(2 * .pi * t / 2)
        let lag = 10 * sin(2 * .pi * (t - 0.25) / 2)
        var tray = context
        let pivot = u.pt(0.5, 0.66)
        tray.translateBy(x: pivot.x, y: pivot.y)
        tray.rotate(by: .degrees(tilt))
        tray.translateBy(x: -pivot.x, y: -pivot.y)
        tray.fill(u.capsule(0.5, 0.645, 0.8, 0.03, corner: 0.01), with: .color(tint))
        let walls = u.line((0.18, 0.46), (0.18, 0.62), (0.82, 0.62), (0.82, 0.46))
        var inside = walls
        inside.closeSubpath()
        var wash = tray
        wash.clip(to: inside)
        // The wash stays nearly level in the world, so in the tray it tips back.
        let slope = tan((lag - tilt) * 0.8 * .pi / 180)
        var liquid = u.line((0.1, 0.54 - 0.4 * slope), (0.9, 0.54 + 0.4 * slope), (0.9, 0.7), (0.1, 0.7))
        liquid.closeSubpath()
        wash.fill(liquid, with: .color(tint.opacity(0.25)))
        tray.fill(u.capsule(0.5, 0.6, 0.4, 0.025, corner: 0.006), with: .color(clay))
        u.stroke(tray, walls, tint, 0.035)
    }
}

/// Labelling tubes: the marker writes on a microfuge tube, then down the
/// side of a 15 mL conical, in clay.
enum TubeLabels {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.9) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let micro = BenchShapes.tube(u, x: 0.28, rim: 0.36, shoulder: 0.7, tip: 0.84, half: 0.09)
        u.stroke(scene, micro, tint, 0.035)
        scene.fill(u.capsule(0.28, 0.33, 0.22, 0.04, corner: 0.012), with: .color(tint))
        let conical = BenchShapes.tube(u, x: 0.68, rim: 0.2, shoulder: 0.78, tip: 0.9, half: 0.1)
        u.stroke(scene, conical, tint, 0.035)
        scene.fill(u.capsule(0.68, 0.16, 0.24, 0.07, corner: 0.015), with: .color(tint))
        for y in [0.32, 0.44, 0.56, 0.68] { u.stroke(scene, u.line((0.6, y), (0.64, y)), tint.opacity(0.5), 0.015) }

        func hand(_ s: Double, x0: Double, y0: Double, length: Double, seed: Double) -> (Double, Double) {
            let phase = s * 30 + seed
            return (x0 + length * s + 0.01 * sin(phase), y0 - 0.012 * cos(phase) + 0.004 * sin(s * 11 + seed))
        }
        let lines: [(x0: Double, y0: Double, length: Double, start: Double)] = [
            (0.22, 0.5, 0.12, 0.3), (0.22, 0.58, 0.09, 0.9), (0.63, 0.4, 0.11, 1.6), (0.63, 0.5, 0.1, 2.2), (0.63, 0.6, 0.08, 2.8),
        ]
        var pen: (Double, Double)? = nil
        for (k, line) in lines.enumerated() {
            let s = Ease.clamp((t - line.start) / 0.5)
            guard s > 0 else { continue }
            let written = stride(from: 0.0, through: s, by: 0.01).map { hand($0, x0: line.x0, y0: line.y0, length: line.length, seed: Double(k)) }
            u.stroke(scene, u.polyline(written), clay, 0.018)
            if s < 1 { pen = hand(s, x0: line.x0, y0: line.y0, length: line.length, seed: Double(k)) }
        }
        if let p = pen {
            var marker = scene
            let at = u.pt(p.0, p.1)
            marker.translateBy(x: at.x, y: at.y)
            marker.rotate(by: .degrees(-55))
            marker.fill(Path(roundedRect: CGRect(x: u.len(0.02), y: -u.len(0.025), width: u.len(0.28), height: u.len(0.05)), cornerRadius: u.len(0.02)),
                        with: .color(tint))
            var nib = Path()
            nib.move(to: .zero)
            nib.addLine(to: CGPoint(x: u.len(0.025), y: -u.len(0.018)))
            nib.addLine(to: CGPoint(x: u.len(0.025), y: u.len(0.018)))
            nib.closeSubpath()
            marker.fill(nib, with: .color(clay))
        }
    }
}

/// Label tape: a strip wraps round a 50 mL tube, then a glass culture tube,
/// and clay writing goes on each.
enum LabelTape {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.9) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let falcon = BenchShapes.tube(u, x: 0.3, rim: 0.2, shoulder: 0.74, tip: 0.88, half: 0.14)
        u.stroke(scene, falcon, tint, 0.035)
        scene.fill(u.capsule(0.3, 0.16, 0.32, 0.08, corner: 0.02), with: .color(tint))
        var culture = Path()
        culture.move(to: u.pt(0.68, 0.24))
        culture.addLine(to: u.pt(0.68, 0.82))
        culture.addQuadCurve(to: u.pt(0.8, 0.82), control: u.pt(0.74, 0.9))
        culture.addLine(to: u.pt(0.8, 0.24))
        u.stroke(scene, culture, tint, 0.035)
        scene.fill(u.capsule(0.74, 0.2, 0.16, 0.08, corner: 0.02), with: .color(tint))

        for (k, tape) in [(x: 0.3, half: 0.14, y: 0.44, h: 0.14, at: 0.3), (x: 0.74, half: 0.06, y: 0.48, h: 0.12, at: 1.9)].enumerated() {
            let wrap = Ease.inOut((t - tape.at) / 0.6)
            guard wrap > 0 else { continue }
            let right = tape.x + tape.half + 0.02, width = (2 * tape.half + 0.04) * wrap
            scene.fill(u.capsule(right - width / 2, tape.y, width, tape.h, corner: 0.008), with: .color(tint.opacity(0.85)))
            let write = Ease.clamp((t - tape.at - 0.7) / 0.6)
            if write > 0 {
                for row in 0..<2 {
                    let y0 = tape.y - tape.h * 0.2 + tape.h * 0.4 * Double(row)
                    let length = (2 * tape.half - 0.04) * (row == 0 ? 1 : 0.6)
                    let s = Ease.clamp(write * 2 - Double(row))
                    guard s > 0 else { continue }
                    let squiggle = stride(from: 0.0, through: s, by: 0.02).map { f in
                        (tape.x - tape.half + 0.02 + length * f + 0.006 * sin(f * 40 + Double(k)), y0 - 0.008 * cos(f * 40 + Double(k)))
                    }
                    u.stroke(scene, u.polyline(squiggle), clay, 0.016)
                }
            }
        }
    }
}

/// The sequencing drop-off: a bag of clay-capped tubes goes in at the
/// dropbox's slot, the flap swings, and the box's light says received.
enum SequencingDropbox {
    static let duration = 4.2
    private static let slot = 0.34

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let drop = Keyframes.value(t, [(0.3, 0), (1.0, 0.6), (1.4, 1.0)])
        var bag = context
        bag.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.pt(0, slot).y - u.origin.y)))
        let top = -0.02 + 0.5 * drop
        bag.fill(u.capsule(0.5, top + 0.12, 0.3, 0.24, corner: 0.02), with: .color(tint.opacity(0.2)))
        u.stroke(bag, u.capsule(0.5, top + 0.12, 0.3, 0.24, corner: 0.02), tint, 0.025)
        for k in 0..<4 {
            let x = 0.41 + 0.06 * Double(k)
            bag.fill(u.capsule(x, top + 0.1, 0.04, 0.05, corner: 0.01), with: .color(clay))
            u.stroke(bag, BenchShapes.tube(u, x: x, rim: top + 0.12, shoulder: top + 0.19, tip: top + 0.22, half: 0.02), tint, 0.015)
        }
        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, 0.62, 0.64, 0.6, corner: 0.04), with: .color(tint))
            layer.blendMode = .destinationOut
            for side in [-1.0, 1.0] {
                let strand = stride(from: 0.0, through: 1.0, by: 0.04).map { s in (0.5 + 0.045 * side * sin(s * 4 * .pi), 0.55 + 0.18 * s) }
                u.stroke(layer, u.polyline(strand), .black, 0.02)
            }
        }
        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, slot + 0.02, 0.4, 0.05, corner: 0.012), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.capsule(0.5, slot + 0.02, 0.34, 0.02, corner: 0.01), with: .color(.black))
        }
        let swing = sin(.pi * Ease.clamp((t - 0.9) / 0.8))
        var flap = context
        let hinge = u.pt(0.5, slot + 0.01)
        flap.translateBy(x: hinge.x, y: hinge.y)
        flap.scaleBy(x: 1, y: 1 - 0.8 * swing)
        flap.translateBy(x: -hinge.x, y: -hinge.y)
        u.stroke(flap, u.line((0.34, slot + 0.05), (0.66, slot + 0.05)), tint.opacity(0.5), 0.02)
        // The received light.
        let got = Ease.clamp((t - 1.6) / 0.2) * (1 - Ease.clamp((t - 3.7) / 0.3))
        context.fill(u.circle(0.74, 0.46, 0.025), with: .color(clay.opacity(0.25 + 0.75 * got)))
    }
}

/// A pH meter: the probe dips into the beaker and the reading settles on
/// 7.40; drops of acid go in, and it falls to 6.80.
enum PHMeter {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let beaker = u.line((0.1, 0.46), (0.12, 0.5), (0.12, 0.9), (0.56, 0.9), (0.56, 0.46))
        let acid = Ease.clamp((t - 2.3) / 0.9)
        BenchShapes.fill(context, u, beaker, from: 0.6, clay.opacity(0.15 + 0.3 * acid))
        u.stroke(context, beaker, tint, 0.04)
        let dip = Keyframes.value(t, [(0.2, 0), (0.6, 1), (3.8, 1), (4.2, 0)])
        let tip = 0.44 + 0.36 * dip
        u.stroke(context, u.line((0.34, tip - 0.5), (0.34, tip - 0.04)), tint, 0.045)
        context.fill(u.circle(0.34, tip - 0.02, 0.03), with: .color(tint))
        for k in 0..<3 {
            let fall = Ease.clamp((t - 2.3 - 0.3 * Double(k)) / 0.3)
            guard fall > 0, fall < 1 else { continue }
            context.fill(u.circle(0.2, 0.3 + 0.3 * fall * fall, 0.018), with: .color(clay))
        }
        if t > 2.2 && t < 3.3 { u.stroke(context, u.line((0.2, 0.1), (0.2, 0.26)), tint, 0.03) }

        // The meter.
        let reading: [Int]?
        if dip < 0.9 {
            reading = nil
        } else if t < 1.4 {
            reading = [(Int(t * 13) % 3) + 6, Int(t * 29) % 10, Int(t * 17) % 10]
        } else {
            let value = 740 - Int(60 * acid)
            reading = [value / 100, (value / 10) % 10, value % 10]
        }
        context.drawLayer { layer in
            layer.fill(u.capsule(0.78, 0.36, 0.34, 0.3, corner: 0.03), with: .color(tint))
            layer.blendMode = .destinationOut
            layer.fill(u.capsule(0.78, 0.31, 0.28, 0.13, corner: 0.012), with: .color(.black))
        }
        for k in 0..<3 {
            let segments = reading.map { SevenSegment.digits[$0[k]] } ?? "g"
            SevenSegment.draw(context, u, segments, x: 0.7 + 0.08 * Double(k), y: 0.31, w: 0.045, h: 0.07, color: clay, width: 0.013)
        }
        if reading != nil { context.fill(u.circle(0.74, 0.345, 0.007), with: .color(clay)) }
        var lead = Path()
        lead.move(to: u.pt(0.34, tip - 0.5))
        lead.addQuadCurve(to: u.pt(0.7, 0.5), control: u.pt(0.4, 0.62))
        u.stroke(context, lead, tint.opacity(0.4), 0.018)
    }
}

/// A drying rack: washed glassware goes onto the pegs upside down, one
/// piece at a time, and drips.
enum DryingRack {
    static let duration = 4.4
    private static let pegs: [(Double, Double)] = [(0.26, 0.42), (0.5, 0.42), (0.74, 0.42), (0.38, 0.78), (0.62, 0.78)]

    private static func glass(_ kind: Int, _ u: UnitSquare) -> Path {
        switch kind {
        case 0: // a flask, neck down
            return u.line((-0.025, 0), (-0.025, -0.06), (-0.1, -0.2), (0.1, -0.2), (0.025, -0.06), (0.025, 0))
        case 1: // a graduated cylinder
            return u.line((-0.03, 0), (-0.03, -0.26), (0.03, -0.26), (0.03, 0))
        case 2: // a beaker, upside down
            return u.line((-0.07, 0), (-0.07, -0.16), (0.07, -0.16), (0.07, 0))
        default: // a bottle
            return u.line((-0.02, 0), (-0.02, -0.04), (-0.06, -0.08), (-0.06, -0.2), (0.06, -0.2), (0.06, -0.08), (0.02, -0.04), (0.02, 0))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.48, 0.84, 0.86, corner: 0.03), tint, 0.04)
        for p in pegs { u.stroke(context, u.line(p, (p.0, p.1 - 0.06)), tint, 0.035) }
        let fade = Ease.inOut((t - 3.9) / 0.4)
        for (k, p) in pegs.enumerated() {
            let hang = Ease.outBack((t - 0.2 - 0.5 * Double(k)) / 0.4)
            guard hang > 0 else { continue }
            var item = context
            item.opacity = 1 - fade
            let at = u.pt(p.0, p.1 - 0.04 - 0.3 * (1 - min(1, hang)))
            item.translateBy(x: at.x - u.origin.x, y: at.y - u.origin.y)
            let shape = glass(k % 4, u)
            var outline = shape
            if k % 4 != 1 { outline.closeSubpath() }
            item.fill(outline, with: .color(tint.opacity(0.15)))
            u.stroke(item, shape, tint, 0.03)
            let age = ((t - 0.6 - 0.5 * Double(k)).truncatingRemainder(dividingBy: 0.9)) / 0.9
            if t > 0.6 + 0.5 * Double(k), age > 0 {
                context.fill(u.circle(p.0, p.1 - 0.02 + 0.12 * age * age, 0.012), with: .color(clay.opacity((1 - age) * (1 - fade))))
            }
        }
    }
}

/// Inoculating a culture: the loop picks up a clay colony, lifts clear, the
/// tube's cap comes off, the loop goes in through the mouth, swirls in the
/// broth and comes back out, and over the next while the broth clouds.
enum Inoculation {
    static let duration = 4.6
    private static let tube = (left: 0.64, right: 0.8, mouth: 0.24)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.06, 0.78), (0.06, 0.86), (0.4, 0.86), (0.4, 0.78)), tint, 0.03)
        scene.fill(u.capsule(0.23, 0.83, 0.32, 0.05, corner: 0.01), with: .color(tint.opacity(0.2)))
        let picked = t > 0.85
        for (k, x) in [0.14, 0.23, 0.32].enumerated() where !(k == 1 && picked) {
            scene.fill(u.ellipse(x, 0.8, 0.05, 0.03), with: .color(clay))
        }
        let walls = u.line((tube.left, tube.mouth), (tube.left, 0.84), (tube.right, 0.84), (tube.right, tube.mouth))
        let grown = Ease.inOut((t - 2.8) / 1.2)
        BenchShapes.fill(scene, u, walls, from: 0.5, tint.opacity(0.12))
        BenchShapes.fill(scene, u, walls, from: 0.5, clay.opacity(0.55 * grown))
        u.stroke(scene, walls, tint, 0.03)
        // The cap: off to the side while the loop is in, then back on.
        let off = Keyframes.value(t, [(1.0, 0), (1.25, 1), (2.6, 1), (2.85, 0)])
        scene.fill(u.capsule(0.72 + 0.18 * off, 0.2 - 0.06 * off, 0.2, 0.06, corner: 0.015), with: .color(tint.opacity(1 - 0.5 * off)))

        // The loop: down to the colony, up clear of everything, across above
        // the tube, down through its mouth into the broth, and out again.
        let x = Keyframes.value(t, [(0.3, 0.4), (0.7, 0.23), (1.25, 0.23), (1.6, 0.72), (2.55, 0.72), (2.9, 0.97)])
        let y = Keyframes.value(t, [(0.3, 0.4), (0.7, 0.78), (0.95, 0.78), (1.25, 0.12), (1.6, 0.12), (1.8, 0.66), (2.3, 0.66), (2.55, 0.12), (2.9, 0.04)])
        let swirl = sin(.pi * Ease.clamp((t - 1.8) / 0.5))
        let loop = (x + 0.02 * swirl * sin(t * 18), y)
        // Over the tube the handle stands upright, so it leaves by the mouth.
        let upright = Ease.clamp((0.14 - abs(x - 0.72)) / 0.08)
        let handle = (0.22 + (0.02 - 0.22) * upright, -0.36 + (-0.42 + 0.36) * upright)
        u.stroke(scene, u.line(loop, (loop.0 + handle.0, loop.1 + handle.1)), tint, 0.022)
        u.stroke(scene, u.circle(loop.0, loop.1 + 0.02, 0.022), tint, 0.02)
        if picked && t < 1.9 { scene.fill(u.circle(loop.0, loop.1 + 0.02, 0.014), with: .color(clay)) }
        if grown > 0 {
            for k in 0..<Int(4 + 10 * grown) {
                let s = Double(k)
                scene.fill(u.circle(0.66 + 0.12 * BenchShapes.rand(s), 0.54 + 0.28 * BenchShapes.rand(s + 30), 0.008), with: .color(clay))
            }
        }
    }
}

/// A roller drum: culture tubes ride round a slowly turning drum, and the
/// clay culture in each runs to whichever end is lower.
enum RollerDrum {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let turn = t / duration * 2 * .pi / 3
        u.stroke(context, u.circle(0.5, 0.5, 0.1), tint, 0.04)
        u.stroke(context, u.circle(0.5, 0.5, 0.42), tint.opacity(0.4), 0.025)
        for k in 0..<6 {
            let a = turn + Double(k) * .pi / 3
            let inner = (0.5 + 0.12 * cos(a), 0.5 + 0.12 * sin(a))
            let outer = (0.5 + 0.38 * cos(a), 0.5 + 0.38 * sin(a))
            // The liquid: the lower third of the tube, in the world's sense.
            let low = inner.1 > outer.1 ? inner : outer, high = inner.1 > outer.1 ? outer : inner
            let wet = (low.0 + (high.0 - low.0) * 0.4, low.1 + (high.1 - low.1) * 0.4)
            u.stroke(context, u.line(low, wet), clay, 0.07)
            u.stroke(context, u.line(inner, outer), tint, 0.03)
            var capped = context
            let c = u.pt(outer.0, outer.1)
            capped.translateBy(x: c.x, y: c.y)
            capped.rotate(by: .radians(a))
            capped.fill(Path(roundedRect: CGRect(x: 0, y: -u.len(0.045), width: u.len(0.05), height: u.len(0.09)), cornerRadius: u.len(0.015)),
                        with: .color(tint))
        }
        context.fill(u.circle(0.5, 0.5, 0.03), with: .color(tint))
    }
}

/// A shaking incubator's platform from above: it circles, and the clay
/// culture swirls round each flask a beat behind.
enum ShakerPlatform {
    static let duration = 3.6
    private static let flasks: [(Double, Double)] = [(0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let a = t * 2 * .pi / 0.6
        let shift = (0.015 * cos(a), 0.015 * sin(a))
        u.stroke(context, u.capsule(0.5 + shift.0, 0.5 + shift.1, 0.88, 0.88, corner: 0.06), tint.opacity(0.5), 0.03)
        for f in flasks {
            let c = (f.0 + shift.0, f.1 + shift.1)
            var glass = context
            glass.clip(to: u.circle(c.0, c.1, 0.15))
            let swirl = a - 2.2
            glass.fill(u.circle(c.0 + 0.04 * cos(swirl), c.1 + 0.04 * sin(swirl), 0.13), with: .color(clay))
            u.stroke(context, u.circle(c.0, c.1, 0.15), tint, 0.035)
            context.fill(u.circle(c.0, c.1, 0.045), with: .color(tint))
            u.stroke(context, u.circle(c.0, c.1, 0.17), tint.opacity(0.4), 0.02)
        }
    }
}
