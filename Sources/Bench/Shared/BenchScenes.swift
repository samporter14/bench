// BenchScenes.swift
// ScienceStatus — lab scenes at the bench: instruments and results. Each
// draws in a unit square (see `UnitSquare`): kit in the tint, the sample
// or the result in clay.

import SwiftUI

/// A centrifuge from above: the rotor has six holes; clay tubes go in by
/// opposite pairs, balanced, then the rotor spins up, holds and spins down.
enum Centrifuge {
    static let duration = 4.6
    /// Top speed in turns a second. Six holes repeat every 60°, so at 30 fps
    /// anything past 2.5 would seem to turn backwards.
    private static let top = 1.8
    private static let spin = (start: 1.75, length: 2.5)
    /// Which holes fill, and when: each tube's partner goes in opposite it.
    private static let loads: [(hole: Int, at: Double)] = [(0, 0.2), (3, 0.5), (1, 0.85), (4, 1.15)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.42), tint, 0.05)

        // Speed rises and falls as sin² while it runs; the angle is its integral.
        let local = min(max(t - spin.start, 0), spin.length)
        let turns = top * (local / 2 - spin.length / (4 * .pi) * sin(2 * .pi * local / spin.length))
        let speed = t > spin.start && t < spin.start + spin.length ? pow(sin(.pi * local / spin.length), 2) : 0
        let angle = turns * 2 * .pi - .pi / 2
        func spot(_ hole: Int, _ r: Double = 0.26) -> (Double, Double) {
            let a = angle + Double(hole) * .pi / 3
            return (0.5 + r * cos(a), 0.5 + r * sin(a))
        }
        for hole in 0..<6 {
            let p = spot(hole)
            u.stroke(context, u.circle(p.0, p.1, 0.075), tint.opacity(0.55), 0.035)
        }
        for load in loads {
            let pop = Ease.outBack((t - load.at) / 0.3)
            guard pop > 0 else { continue }
            let p = spot(load.hole)
            context.fill(u.circle(p.0, p.1, 0.055 * pop), with: .color(clay))
        }
        context.fill(u.circle(0.5, 0.5, 0.06), with: .color(tint))

        // Speed lines just outside the rotor.
        if speed > 0.4 {
            let alpha = (speed - 0.4) / 0.6
            for k in 0..<2 {
                let a = angle * 0.35 + Double(k) * .pi
                var arc = Path()
                arc.addArc(center: u.pt(0.5, 0.5), radius: u.len(0.49),
                           startAngle: .radians(a), endAngle: .radians(a + 0.7), clockwise: false)
                u.stroke(context, arc, tint.opacity(alpha * 0.6), 0.04)
            }
        }
    }
}

/// Gel electrophoresis: three lanes; clay bands leave the wells and run
/// down the gel at their own speeds, then stop.
enum Gel {
    static let duration = 3.6
    /// Each lane's bands: where they stop, as a share of the run.
    private static let lanes: [(x: Double, stops: [Double])] = [
        (0.3, [0.35, 0.8]), (0.5, [0.5]), (0.7, [0.2, 0.62, 0.95]),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.52, 0.66, 0.8, corner: 0.08), tint)
        let wells = 0.24, bottom = 0.82
        for lane in lanes {
            u.stroke(context, u.line((lane.x - 0.05, wells), (lane.x + 0.05, wells)), tint, 0.06)
        }
        let run = Ease.out((t - 0.2) / 2.6)
        for lane in lanes {
            for stop in lane.stops {
                let y = wells + 0.07 + (bottom - wells - 0.07) * stop * run
                u.stroke(context, u.line((lane.x - 0.06, y), (lane.x + 0.06, y)), clay, 0.065)
            }
        }
    }
}

/// PCR, three cycles: each duplex melts into its two strands, a short clay
/// primer lands on each, and a polymerase runs along each strand laying the
/// new clay copy behind it, the two running opposite ways. The first cycle
/// plays large; then the two copies sit side by side and do the same, and
/// again: 1, 2, 4, 8.
enum PCR {
    static let duration = 6.6

    /// One cycle's timing, from its start: melt, prime, extend, let go.
    private struct Beats {
        var melt: (Double, Double), prime: (Double, Double), extend: (Double, Double), off: (Double, Double)
    }
    private static let first = Beats(melt: (0.35, 0.4), prime: (0.85, 0.25), extend: (1.15, 1.35), off: (2.5, 0.3))
    private static let quick = Beats(melt: (0.0, 0.25), prime: (0.28, 0.15), extend: (0.45, 0.7), off: (1.15, 0.2))

    /// One duplex going through a cycle at `centre`: `width` long, its two
    /// new duplexes ending `spread` above and below it, `gap` between paired
    /// strands. Each template keeps its colour; the new strands are clay.
    /// `local` is how far the cycle has run, in its own seconds.
    private static func cycle(_ context: GraphicsContext, _ u: UnitSquare, centre: (Double, Double), width: Double,
                              spread: Double, gap: Double, templates: (Color, Color), time local: Double,
                              beats b: Beats, tint: Color) {
        let melt = Ease.inOut((local - b.melt.0) / b.melt.1)
        let primed = Ease.out((local - b.prime.0) / b.prime.1)
        let extend = Ease.inOut((local - b.extend.0) / b.extend.1)
        let off = Ease.inOut((local - b.off.0) / b.off.1)
        let (x, y) = centre
        let left = x - width / 2, right = x + width / 2
        // The templates part, each to where its new duplex will sit.
        let upper = y - gap / 2 - spread * melt
        let lower = y + gap / 2 + spread * melt
        // The new strands grow along them from their primers, opposite ways.
        let reach = width * 0.14 + width * 0.86 * extend
        u.stroke(context, u.line((left, upper), (right, upper)), templates.0, 0.05)
        u.stroke(context, u.line((left, lower), (right, lower)), templates.1, 0.05)
        if primed > 0 {
            u.stroke(context, u.line((left, upper + gap), (left + reach, upper + gap)), clay.opacity(primed), 0.05)
            u.stroke(context, u.line((right - reach, lower - gap), (right, lower - gap)), clay.opacity(primed), 0.05)
        }
        // The polymerases, at the growing ends, lifting off at the end.
        if extend > 0 && off < 1 {
            let k = max(width / 0.72, 0.6)
            for (py, px) in [(upper + gap / 2, left + reach), (lower - gap / 2, right - reach)] {
                var enzyme = context
                let p = u.pt(px, py)
                enzyme.translateBy(x: p.x, y: p.y)
                enzyme.scaleBy(x: 1 - off, y: 1 - off)
                enzyme.translateBy(x: -p.x, y: -p.y)
                enzyme.opacity = min(1, extend * 6) * (1 - off)
                enzyme.fill(u.capsule(px, py, 0.12 * k, 0.2 * k, corner: 0.05 * k), with: .color(tint))
            }
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let gap = 0.08, small = 0.055, narrow = 0.34
        let second = 3.3, third = 4.8
        if t < 2.85 {
            cycle(context, u, centre: (0.5, 0.5), width: 0.72, spread: 0.12, gap: gap, templates: (tint, tint), time: t, beats: first, tint: tint)
            return
        }
        // The two copies slide side by side and shrink: the upper one old
        // strand on top, the lower one new strand on top.
        if t < second {
            let slide = Ease.inOut((t - 2.85) / 0.4)
            for (k, from) in [(0.0, 0.38), (1.0, 0.62)] {
                let x = 0.5 + (0.29 + 0.42 * k - 0.5) * slide
                let y = from + (0.5 - from) * slide
                let w = 0.72 + (narrow - 0.72) * slide, g = gap + (small - gap) * slide
                let colours = k == 0 ? (tint, clay) : (clay, tint)
                u.stroke(context, u.line((x - w / 2, y - g / 2), (x + w / 2, y - g / 2)), colours.0, 0.05)
                u.stroke(context, u.line((x - w / 2, y + g / 2), (x + w / 2, y + g / 2)), colours.1, 0.05)
            }
            return
        }
        if t < third {
            cycle(context, u, centre: (0.29, 0.5), width: narrow, spread: 0.22, gap: small, templates: (tint, clay), time: t - second, beats: quick, tint: tint)
            cycle(context, u, centre: (0.71, 0.5), width: narrow, spread: 0.22, gap: small, templates: (clay, tint), time: t - second, beats: quick, tint: tint)
            return
        }
        let fourth: [((Double, Double), (Color, Color))] = [
            ((0.29, 0.28), (tint, clay)), ((0.29, 0.72), (clay, clay)),
            ((0.71, 0.28), (clay, clay)), ((0.71, 0.72), (clay, tint)),
        ]
        for (centre, colours) in fourth {
            cycle(context, u, centre: centre, width: narrow, spread: 0.11, gap: small, templates: colours, time: t - third, beats: quick, tint: tint)
        }
    }
}

/// A result coming in: points land one by one on a saturating curve, then
/// the clay fit draws through them. Claude Science's own kind of moment.
enum CurveFit {
    static let duration = 4.0
    private static let xs: [Double] = [0.24, 0.33, 0.43, 0.54, 0.66, 0.78, 0.9]
    private static let jitter: [Double] = [0.02, -0.03, 0.025, -0.015, 0.02, -0.02, 0.01]

    private static func curve(_ x: Double) -> Double {
        let s = x - 0.14
        return 0.84 - 0.62 * s / (0.16 + s)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.14, 0.1), (0.14, 0.86), (0.94, 0.86)), tint, 0.07)

        for (i, x) in xs.enumerated() {
            let appear = Ease.outBack((t - 0.2 - 0.22 * Double(i)) / 0.25)
            guard appear > 0 else { continue }
            context.fill(u.circle(x, curve(x) + jitter[i], 0.04 * appear), with: .color(tint))
        }

        let draw = Ease.inOut((t - 1.95) / 1.25)
        guard draw > 0 else { return }
        let fit = stride(from: 0.16, through: 0.92, by: 0.02).map { ($0, curve($0)) }
        u.stroke(context, u.polyline(fit).trimmedPath(from: 0, to: draw), clay, 0.07)
    }
}

/// A beaker on a stirrer: the clay stir bar spins up and the surface
/// draws down into a vortex.
enum StirBar {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var beaker = Path()
        beaker.move(to: u.pt(0.16, 0.14))
        beaker.addLine(to: u.pt(0.2, 0.18))
        beaker.addLine(to: u.pt(0.2, 0.78))
        beaker.addQuadCurve(to: u.pt(0.28, 0.86), control: u.pt(0.2, 0.86))
        beaker.addLine(to: u.pt(0.72, 0.86))
        beaker.addQuadCurve(to: u.pt(0.8, 0.78), control: u.pt(0.8, 0.86))
        beaker.addLine(to: u.pt(0.8, 0.14))
        u.stroke(context, beaker, tint)

        let speed = Ease.inOut(t / 1.4)
        let depth = 0.2 * speed + 0.01 * sin(t * 7) * speed
        let surface = stride(from: 0.26, through: 0.74, by: 0.02).map { x in
            (x, 0.36 + depth * exp(-pow((x - 0.5) / 0.13, 2)))
        }
        u.stroke(context, u.polyline(surface), tint, 0.06)

        // The bar seen from the side: its length follows the turn.
        let turn = 3 * (t - 0.7 * speed) * 2 * .pi
        let half = 0.04 + 0.12 * abs(cos(turn))
        u.stroke(context, u.line((0.5 - half, 0.77), (0.5 + half, 0.77)), clay, 0.08)
    }
}

/// A Bunsen burner lighting and burning: a clay flame that flickers.
enum Bunsen {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.34, 0.88), (0.66, 0.88)), tint, 0.08)
        u.stroke(context, u.line((0.5, 0.86), (0.5, 0.58)), tint, 0.1)
        u.stroke(context, u.line((0.5, 0.74), (0.6, 0.74)), tint, 0.06)

        let light = Ease.outBack(t / 0.4)
        guard light > 0 else { return }
        let height = (0.3 + 0.03 * sin(t * 9) + 0.02 * sin(t * 23)) * light
        let lean = 0.025 * sin(t * 7) + 0.01 * sin(t * 17)
        let width = 0.1 * min(1, light)
        let base = 0.52
        var flame = Path()
        flame.move(to: u.pt(0.5 + lean, base - height))
        flame.addQuadCurve(to: u.pt(0.5 + width, base - 0.05), control: u.pt(0.5 + width, base - height * 0.45))
        flame.addArc(center: u.pt(0.5, base - 0.05), radius: u.len(width),
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        flame.addQuadCurve(to: u.pt(0.5 + lean, base - height), control: u.pt(0.5 - width, base - height * 0.45))
        context.fill(flame, with: .color(clay))
    }
}

/// An atom: a clay nucleus and three electrons on tilted orbits.
enum Atom {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for (k, tilt) in [0.0, 60.0, 120.0].enumerated() {
            var orbit = context
            orbit.translateBy(x: u.pt(0.5, 0.5).x, y: u.pt(0.5, 0.5).y)
            orbit.rotate(by: .degrees(tilt))
            let a = u.len(0.42), b = u.len(0.15)
            orbit.stroke(Path(ellipseIn: CGRect(x: -a, y: -b, width: 2 * a, height: 2 * b)),
                         with: .color(tint.opacity(0.5)), lineWidth: u.len(0.05))
            let phase = t * 2 * .pi * (0.6 + 0.15 * Double(k)) + Double(k) * 2
            let e = CGPoint(x: a * cos(phase), y: b * sin(phase))
            let r = u.len(0.05)
            orbit.fill(Path(ellipseIn: CGRect(x: e.x - r, y: e.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(tint))
        }
        context.fill(u.circle(0.5, 0.5, 0.1), with: .color(clay))
    }
}

/// Newton's cradle: the clay end balls take turns swinging out and
/// knocking back through the three at rest.
enum Cradle {
    static let duration = 3.2
    private static let period = 1.6
    private static let pivots = [0.26, 0.38, 0.5, 0.62, 0.74]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let top = 0.16, length = 0.5, amplitude = 0.6
        u.stroke(context, u.line((0.12, top), (0.88, top)), tint)

        let phase = (t / period).truncatingRemainder(dividingBy: 1)
        let swingLeft = phase < 0.5 ? -amplitude * sin(2 * .pi * phase) : 0
        let swingRight = phase >= 0.5 ? amplitude * sin(2 * .pi * (phase - 0.5)) : 0
        for (i, x) in pivots.enumerated() {
            let angle = i == 0 ? swingLeft : (i == pivots.count - 1 ? swingRight : 0)
            let ball = (x + length * sin(angle), top + length * cos(angle))
            u.stroke(context, u.line((x, top), ball), tint.opacity(0.7), 0.05)
            let end = i == 0 || i == pivots.count - 1
            context.fill(u.circle(ball.0, ball.1, 0.058), with: end ? .color(clay) : .color(tint))
        }
    }
}

/// Microfluidics: a clay droplet runs along a channel, splits in two round
/// an island, and the halves meet again and carry on as one.
enum Microfluidic {
    static let duration = 3.6
    private static let main = 0.13, branch = 0.09, wall = 0.055

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let upper: [(Double, Double)] = [(0.3, 0.5), (0.4, 0.3), (0.6, 0.3), (0.7, 0.5)]
        let lower: [(Double, Double)] = [(0.3, 0.5), (0.4, 0.7), (0.6, 0.7), (0.7, 0.5)]

        // Channel walls: the tubes drawn wide, their insides cut away.
        context.drawLayer { layer in
            u.stroke(layer, u.line((0.02, 0.5), (0.3, 0.5)), tint, main + 2 * wall)
            u.stroke(layer, u.line((0.7, 0.5), (0.98, 0.5)), tint, main + 2 * wall)
            u.stroke(layer, u.polyline(upper), tint, branch + 2 * wall)
            u.stroke(layer, u.polyline(lower), tint, branch + 2 * wall)
            layer.blendMode = .destinationOut
            u.stroke(layer, u.line((0.02, 0.5), (0.3, 0.5)), .black, main)
            u.stroke(layer, u.line((0.7, 0.5), (0.98, 0.5)), .black, main)
            u.stroke(layer, u.polyline(upper), .black, branch)
            u.stroke(layer, u.polyline(lower), .black, branch)
        }

        // One droplet, then two, then one again.
        let s = Ease.inOut((t - 0.2) / 3.0)
        let x = -0.02 + 1.04 * s
        if x < 0.3 || x > 0.7 {
            context.fill(u.circle(x, 0.5, main / 2 - 0.005), with: .color(clay))
        } else {
            let k = (x - 0.3) / 0.4
            let near = min(1, min(k, 1 - k) / 0.15)
            for path in [upper, lower] {
                let p = point(on: path, at: k)
                context.fill(u.circle(p.0, p.1, branch / 2 - 0.005 + 0.012 * (1 - near)), with: .color(clay))
            }
        }
    }

    /// The point `k` of the way along a polyline, by length.
    private static func point(on path: [(Double, Double)], at k: Double) -> (Double, Double) {
        let segments = zip(path, path.dropFirst()).map { a, b in (a, b, hypot(b.0 - a.0, b.1 - a.1)) }
        var left = k * segments.reduce(0) { $0 + $1.2 }
        for (a, b, length) in segments {
            if left <= length {
                let f = left / length
                return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
            }
            left -= length
        }
        return path[path.count - 1]
    }
}

/// Aliquoting: a row of tubes slides under a micropipette, one at a time.
/// Each gets a clay drop and fills; the filled tube moves off to the left
/// as the next comes in from the right. Tubes stay large by leaving the
/// frame instead of shrinking to fit, and the scene starts and ends with a
/// filled tube under the tip, so the loop has no seam.
enum Aliquot {
    static let duration = 4.0
    /// When each round starts: a slide, then a press and a drop.
    private static let rounds: [Double] = [0.1, 1.4, 2.7]
    private static let spacing = 0.34
    /// The pipette is drawn at this share of its own scene's size.
    private static let scale = 0.7
    private static let rim = 0.6, shoulder = 0.8, bottom = 0.93, half = 0.09

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let slid = rounds.reduce(0) { $0 + Ease.inOut((t - $1) / 0.4) }

        // Tubes: -1 was filled last time round; 0, 1, 2 fill now.
        for j in -2...4 {
            let x = 0.5 + spacing * (Double(j) + 1 - slid)
            guard x > -0.3, x < 1.3 else { continue }
            let fill: Double
            if j < 0 { fill = 1 } else if j < rounds.count {
                fill = Ease.inOut((t - rounds[j] - 0.95) / 0.25)
            } else { fill = 0 }
            tube(context, u, x: x, fill: fill, tint: tint)
        }

        // The pipette, smaller, hanging from the top edge.
        let presses = rounds.map { $0 + 0.45 }
        var pipette = context
        let top = u.pt(0.5, 0)
        pipette.translateBy(x: top.x, y: top.y)
        pipette.scaleBy(x: scale, y: scale)
        pipette.translateBy(x: -top.x, y: -top.y)
        let emptied = presses.reduce(0) { $0 + Ease.inOut((t - $1) / 0.25) } / Double(presses.count) * 0.75
        Pipette.drawInstrument(in: pipette, u, tint: tint, press: Pipette.plunger(at: t, presses: presses),
                               emptied: emptied)

        // A drop per round: swells at the tip, falls into the tube.
        let tip = Pipette.tipEnd * scale
        let r = 0.04
        for p in presses {
            let d = t - p
            if d < 0.05 || d > 0.75 { continue }
            if d < 0.25 {
                let g = r * Ease.out((d - 0.05) / 0.2)
                context.fill(u.circle(0.5, tip + g, g), with: .color(clay))
            } else {
                let fall = (d - 0.25) / 0.5
                let y = tip + r + (bottom - 0.05 - tip - r) * fall * fall
                context.fill(u.circle(0.5, y, r), with: .color(clay))
            }
        }
    }

    /// A microcentrifuge tube: straight walls, a conical bottom, its lid
    /// open to the right; clay liquid rises in it as `fill` goes to 1.
    private static func tube(_ context: GraphicsContext, _ u: UnitSquare, x: Double, fill: Double, tint: Color) {
        let outline = u.line((x - half, rim), (x - half, shoulder), (x - 0.025, bottom),
                             (x + 0.025, bottom), (x + half, shoulder), (x + half, rim))
        if fill > 0 {
            let level = bottom - (bottom - shoulder + 0.03) * fill
            var body = outline
            body.closeSubpath()
            var liquid = context
            liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, level).y, width: u.side, height: u.side)))
            liquid.fill(body, with: .color(clay))
        }
        u.stroke(context, outline, tint, 0.05)
        u.stroke(context, u.line((x + half, rim), (x + half + 0.07, rim - 0.07)), tint, 0.05)
    }
}
