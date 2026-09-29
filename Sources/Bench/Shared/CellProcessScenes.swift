// CellProcessScenes.swift
// ScienceStatus — lab scenes of what goes on inside and around a cell.
// Each draws in a unit square (see `UnitSquare`): membranes and machinery
// in the tint, cargo and products in clay.

import SwiftUI

/// Phagocytosis: a clay particle settles against the cell, which cups it,
/// wraps two arms of its own membrane round it, closes them, and pulls the
/// particle inside in the pocket they make. One outline throughout: the
/// membrane stretches and folds, nothing appears from nowhere.
enum Phagocytosis {
    static let duration = 4.0
    private static let cell = (0.4, 0.6), radius = 0.25
    /// The way in, from the cell's centre towards the particle.
    private static let way = (0.81, -0.585)
    /// The pocket round the particle, and the arms' outer reach.
    private static let pocket = 0.085, reach = 0.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let arrive = Ease.out(t / 0.7)
        let wrap = Ease.inOut((t - 0.7) / 1.2)
        let take = Ease.inOut((t - 1.95) / 1.25)
        let distance = 0.58 + (0.325 - 0.58) * arrive + (0.08 - 0.325) * take
        let p = (cell.0 + way.0 * distance, cell.1 + way.1 * distance)

        // The arms: a wedge of membrane round the particle, opening from the
        // side facing the cell until it closes on the far side.
        let facing = atan2(-way.1, -way.0)
        let spread = Double.pi * wrap
        var arms = Path()
        if spread > 0.01 {
            let centre = u.pt(p.0, p.1)
            arms.move(to: centre)
            arms.addArc(center: centre, radius: u.len(reach), startAngle: .radians(facing - spread),
                        endAngle: .radians(facing + spread), clockwise: false)
            arms.closeSubpath()
            // Rounded fingertips.
            for end in [facing - spread, facing + spread] {
                let r = (pocket + reach) / 2
                arms.addPath(u.circle(p.0 + r * cos(end), p.1 + r * sin(end), (reach - pocket) / 2))
            }
        }
        let body = u.circle(cell.0, cell.1, radius).union(arms)
        let membrane = body.subtracting(u.circle(p.0, p.1, pocket))
        u.stroke(context, membrane, tint, 0.05)
        context.fill(u.circle(p.0, p.1, 0.06), with: .color(clay))
    }
}

/// Synaptic release: vesicles in the terminal dock at its membrane one
/// after another, open, and send clay transmitter across the cleft to
/// receptors that light as it lands.
enum Synapse {
    static let duration = 3.6
    private static let vesicles: [(x: Double, y: Double, at: Double)] = [
        (0.3, 0.22, 0.3), (0.5, 0.15, 1.2), (0.7, 0.24, 2.1),
    ]
    private static let receptors = [0.34, 0.5, 0.66]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var terminal = Path()
        terminal.move(to: u.pt(0.08, 0))
        terminal.addLine(to: u.pt(0.08, 0.3))
        terminal.addQuadCurve(to: u.pt(0.26, 0.44), control: u.pt(0.08, 0.44))
        terminal.addLine(to: u.pt(0.74, 0.44))
        terminal.addQuadCurve(to: u.pt(0.92, 0.3), control: u.pt(0.92, 0.44))
        terminal.addLine(to: u.pt(0.92, 0))
        u.stroke(context, terminal, tint)
        var target = Path()
        target.move(to: u.pt(0.08, 1))
        target.addLine(to: u.pt(0.08, 0.76))
        target.addQuadCurve(to: u.pt(0.26, 0.62), control: u.pt(0.08, 0.62))
        target.addLine(to: u.pt(0.74, 0.62))
        target.addQuadCurve(to: u.pt(0.92, 0.76), control: u.pt(0.92, 0.62))
        target.addLine(to: u.pt(0.92, 1))
        u.stroke(context, target, tint)

        // Receptors, lit while transmitter arrives.
        for x in receptors {
            var lit = 0.0
            for v in vesicles {
                let arrive = t - v.at - 0.75
                if abs(x - v.x) < 0.2, arrive > 0, arrive < 0.5 { lit = max(lit, 1 - arrive / 0.5) }
            }
            u.stroke(context, u.line((x, 0.6), (x, 0.56)), tint, 0.05)
            if lit > 0 { u.stroke(context, u.line((x, 0.6), (x, 0.56)), clay.opacity(lit), 0.05) }
        }

        for v in vesicles {
            let d = t - v.at
            let dock = Ease.inOut(d / 0.35)
            let open = Ease.clamp((d - 0.35) / 0.15)
            if open < 1 {
                let y = v.y + (0.37 - v.y) * dock
                u.stroke(context, u.circle(v.x, y, 0.065 * (1 - 0.4 * open)), tint.opacity(1 - open), 0.045)
                for k in 0..<3 {
                    let a = Double(k) * 2.1 + 0.4
                    context.fill(u.circle(v.x + 0.028 * cos(a), y + 0.028 * sin(a), 0.017), with: .color(clay))
                }
            }
            let cross = (d - 0.4) / 0.45
            if cross > 0, cross < 1.3 {
                for k in 0..<3 {
                    let spread = Double(k - 1) * 0.07
                    let x = v.x + spread * Ease.out(cross)
                    let y = 0.45 + 0.13 * Ease.out(min(cross, 1))
                    context.fill(u.circle(x, y, 0.02), with: .color(clay.opacity(1 - Ease.clamp((cross - 1) / 0.3))))
                }
            }
        }
    }
}

/// An autophagosome forming: a double membrane curls round clay cargo, its
/// cup deepening until the rim closes into a ring.
enum Autophagosome {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let close = Ease.inOut((t - 0.3) / 2.0)
        let span = 100 + 260 * close
        let settle = 1 - 0.04 * sin(.pi * Ease.clamp((t - 2.4) / 0.5))
        let r = 0.26 * settle

        var cargo = context
        let c = u.pt(0.5, 0.5)
        cargo.translateBy(x: c.x, y: c.y)
        cargo.rotate(by: .degrees(20))
        cargo.fill(Path(roundedRect: CGRect(x: -u.len(0.1), y: -u.len(0.05), width: u.len(0.2), height: u.len(0.1)),
                        cornerRadius: u.len(0.05)), with: .color(clay))
        context.fill(u.circle(0.42, 0.6, 0.03), with: .color(clay))
        context.fill(u.circle(0.6, 0.38, 0.025), with: .color(clay))

        // The double membrane: a thick stroke with its middle cut out.
        var arc = Path()
        if span >= 359 {
            arc = u.circle(0.5, 0.5, r)
        } else {
            arc.addArc(center: u.pt(0.5, 0.5), radius: u.len(r), startAngle: .degrees(180 - span / 2),
                       endAngle: .degrees(180 + span / 2), clockwise: false)
        }
        context.drawLayer { layer in
            u.stroke(layer, arc, tint, 0.11)
            layer.blendMode = .destinationOut
            u.stroke(layer, arc, .black, 0.035)
        }
    }
}

/// The powerhouse of the cell: a mitochondrion, its inner membrane folded
/// into cristae, humming as clay bolts of energy rise out of it.
enum Mitochondria {
    static let duration = 4.0
    /// When each bolt leaves, and where along the top.
    private static let bolts: [(at: Double, x: Double)] = [(0.35, 0.36), (1.2, 0.6), (2.05, 0.45), (2.9, 0.66)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // A small swell as each bolt leaves.
        let hum = bolts.map { Keyframes.value(t, [($0.at - 0.12, 0), ($0.at, 1), ($0.at + 0.3, 0)]) }.max() ?? 0
        var body = context
        let c = u.pt(0.5, 0.62)
        body.translateBy(x: c.x, y: c.y)
        body.scaleBy(x: 1 + 0.03 * hum, y: 1 + 0.05 * hum)
        body.translateBy(x: -c.x, y: -c.y)
        u.stroke(body, u.capsule(0.5, 0.62, 0.76, 0.38, corner: 0.19), tint, 0.06)
        // Cristae: folds of the inner membrane, from the top and the bottom
        // in turn.
        for (k, x) in [0.27, 0.385, 0.5, 0.615, 0.73].enumerated() {
            let fromTop = k % 2 == 0
            let (a, b) = fromTop ? (0.49, 0.67) : (0.75, 0.57)
            u.stroke(body, u.line((x, a), (x, b)), tint.opacity(0.75), 0.045)
        }
        for bolt in bolts {
            let rise = Ease.clamp((t - bolt.at) / 0.9)
            guard rise > 0, rise < 1 else { continue }
            let pop = Ease.outBack(min(1, rise / 0.25))
            let alpha = rise < 0.6 ? 1 : 1 - (rise - 0.6) / 0.4
            var spark = context
            let base = u.pt(bolt.x, 0.3 - 0.14 * Ease.out(rise))
            spark.translateBy(x: base.x, y: base.y)
            spark.scaleBy(x: pop, y: pop)
            spark.translateBy(x: -base.x, y: -base.y)
            spark.opacity = alpha
            spark.fill(boltPath(u, centre: (bolt.x, 0.3 - 0.14 * Ease.out(rise)), size: 1.35), with: .color(clay))
        }
    }

    /// A lightning bolt, 0.11 by 0.19 at `size` 1.
    private static func boltPath(_ u: UnitSquare, centre: (Double, Double), size k: Double) -> Path {
        let (x, y) = centre
        var path = u.polyline([
            (x + 0.02 * k, y - 0.095 * k), (x - 0.05 * k, y + 0.012 * k), (x - 0.002 * k, y + 0.012 * k),
            (x - 0.025 * k, y + 0.095 * k), (x + 0.055 * k, y - 0.018 * k), (x + 0.006 * k, y - 0.018 * k),
        ])
        path.closeSubpath()
        return path
    }
}

/// ATP synthase: its ring turns in the membrane, and the head above it
/// sends clay ATP off, one after another.
enum ATPSynthase {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.56), (0.96, 0.56)), tint, 0.05)
        u.stroke(context, u.line((0.04, 0.7), (0.96, 0.7)), tint, 0.05)

        // The ring: turning, shown by slits sliding across its front.
        let spin = t * 2 * .pi / 1.2
        context.drawLayer { layer in
            layer.fill(u.ellipse(0.5, 0.63, 0.3, 0.14), with: .color(tint))
            layer.blendMode = .destinationOut
            for k in 0..<8 {
                let a = spin + Double(k) * .pi / 4
                guard sin(a) > 0.1 else { continue }
                let x = 0.5 + 0.12 * cos(a)
                u.stroke(layer, u.line((x, 0.6), (x, 0.66)), .black, 0.025)
            }
        }
        u.stroke(context, u.line((0.5, 0.57), (0.5, 0.36)), tint, 0.06)
        var stator = Path()
        stator.move(to: u.pt(0.76, 0.58))
        stator.addQuadCurve(to: u.pt(0.64, 0.25), control: u.pt(0.8, 0.3))
        u.stroke(context, stator, tint, 0.045)
        for k in 0..<3 {
            let a = (Double(k) * 120 - 90) * .pi / 180
            context.fill(u.circle(0.5 + 0.07 * cos(a), 0.27 + 0.07 * sin(a), 0.08), with: .color(tint))
        }

        // ATP: one every 0.6 s, leaving the head outwards and fading.
        for k in 0..<6 {
            let age = (t - 0.3 - 0.6 * Double(k)) / 0.8
            guard age > 0, age < 1 else { continue }
            let a = (Double(k % 3) * 120 - 60 + 10) * .pi / 180
            let d = 0.15 + 0.14 * Ease.out(age)
            context.fill(u.circle(0.5 + d * cos(a), 0.27 + d * sin(a), 0.035), with: .color(clay.opacity(1 - age * age)))
        }
    }
}

/// Cilia beating: three on a cell's surface, each a stiff power stroke
/// and a curled recovery, a little out of step with the next, moving a
/// clay particle along above them.
enum Cilia {
    static let duration = 3.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let base = 0.84
        u.stroke(context, u.line((0.04, base), (0.96, base)), tint)
        for (k, x0) in [0.27, 0.5, 0.73].enumerated() {
            let phase = (t / 1.0 + Double(k) * 0.12).truncatingRemainder(dividingBy: 1)
            let theta: Double, bend: Double
            if phase < 0.35 {
                theta = -30 + 60 * Ease.inOut(phase / 0.35)
                bend = 0.2
            } else {
                let r = (phase - 0.35) / 0.65
                theta = 30 - 60 * Ease.inOut(r)
                bend = 0.2 + 1.1 * sin(.pi * r)
            }
            var p = (x0, base)
            var points = [p]
            for i in 1...14 {
                let s = Double(i) / 14
                let a = theta * .pi / 180 + bend * s
                p = (p.0 + 0.38 / 14 * sin(a), p.1 - 0.38 / 14 * cos(a))
                points.append(p)
            }
            u.stroke(context, u.polyline(points), tint, 0.055)
        }
        let x = 0.1 + 0.8 * t / duration
        context.fill(u.circle(x, 0.34 + 0.015 * sin(t * 2 * .pi), 0.05), with: .color(clay))
    }
}

/// A cell crawling: it pushes a pseudopod out ahead, flows forward into
/// it and draws its rear in after, twice, carrying its clay nucleus along.
enum CellMigration {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let cycle = min(1, floor(t / 2.0))
        let p = t / 2.0 - cycle
        let move = Ease.inOut((p - 0.35) / 0.45)
        let cx = 0.36 + 0.12 * (cycle + move)
        let front = 0.12 * Ease.out(p / 0.35) * (1 - move)
        let rear = 0.07 * sin(.pi * Ease.clamp((p - 0.35) / 0.6))

        func near(_ a: Double, _ b: Double) -> Double {
            var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d -= 2 * .pi }
            if d < -.pi { d += 2 * .pi }
            return exp(-pow(d / 0.55, 2))
        }
        let outline = (0..<64).map { i -> (Double, Double) in
            let a = Double(i) / 64 * 2 * .pi
            let r = 0.19 + front * near(a, 0) + rear * near(a, .pi)
            return (cx + r * cos(a), 0.5 + 0.85 * r * sin(a))
        }
        var cell = u.polyline(outline)
        cell.closeSubpath()
        u.stroke(context, cell, tint)
        context.fill(u.circle(cx - 0.03, 0.5, 0.07), with: .color(clay))
    }
}
