// LifeBatchIScenes.swift
// ScienceStatus — life's patterns and tricks: saltatory conduction, Notch's
// checkerboard, the KaiC clock, the waggle dance, a tardigrade drying out and
// back, a Turing pattern, a Venus flytrap and a pollen tube. Each draws in a
// unit square (see `UnitSquare`): living structure in the tint, the signal,
// the pattern or the moment in clay.

import SwiftUI

/// Saltatory conduction: along a myelinated axon the impulse leaps from one
/// gap in the myelin to the next, each node flashing clay as it arrives.
enum SaltatoryConduction {
    static let duration = 4.6
    private static let nodes = [0.08, 0.31, 0.54, 0.77, 1.0]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let y = 0.6
        u.stroke(context, u.line((0.0, y - 0.045), (1.0, y - 0.045)), tint.opacity(0.6), 0.02)
        u.stroke(context, u.line((0.0, y + 0.045), (1.0, y + 0.045)), tint.opacity(0.6), 0.02)
        // Myelin wrapped between the nodes.
        for k in 0..<(nodes.count - 1) {
            let mid = (nodes[k] + nodes[k + 1]) / 2
            context.fill(u.capsule(mid, y, 0.18, 0.2, corner: 0.08), with: .color(tint))
        }
        // The impulse: one hop per 0.55 s, across and round again.
        let hop = 0.55
        let position = (t - 0.3) / hop
        for (k, x) in nodes.enumerated() {
            for pass in 0..<2 {
                let since = position - Double(k) - Double(pass) * 4.2
                let flash = since > 0 ? exp(-since / 0.45) : 0
                if flash > 0.03 { context.fill(u.circle(x, y, 0.04 + 0.035 * flash), with: .color(clay.opacity(flash))) }
            }
        }
        // The leap: an arc over the myelin to the next node, trailing.
        let local = position.truncatingRemainder(dividingBy: 4.2)
        let k = Int(local)
        guard position > 0, k < nodes.count - 1 else { return }
        let f = local - Double(k)
        let arc = stride(from: 0.0, through: f, by: 0.05).map { s -> (Double, Double) in
            (nodes[k] + (nodes[k + 1] - nodes[k]) * s, y - 0.12 - 0.14 * sin(.pi * s))
        }
        if arc.count > 1 { u.stroke(context, u.polyline(arc), clay.opacity(0.5), 0.02) }
        let head = (nodes[k] + (nodes[k + 1] - nodes[k]) * f, y - 0.12 - 0.14 * sin(.pi * f))
        context.fill(u.circle(head.0, head.1, 0.03), with: .color(clay))
    }
}

/// Notch lateral inhibition: a sheet of equal cells, each telling its
/// neighbours not to be what it is, resolves into a clay checkerboard.
enum NotchCheckerboard {
    static let duration = 5.0
    private static let side = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let resolve = Ease.inOut((t - 0.8) / 2.8)
        let cell = 0.84 / Double(side)
        for row in 0..<side {
            for col in 0..<side {
                let s = Double(row * side + col)
                let high = (row + col) % 2 == 0
                let noise = 0.12 * sin(t * 5 + s * 1.7) * (1 - resolve)
                let level = 0.45 + noise + (high ? 0.55 : -0.45) * resolve
                let rect = u.capsule(0.08 + cell * (Double(col) + 0.5), 0.08 + cell * (Double(row) + 0.5), cell * 0.86, cell * 0.86, corner: 0.018)
                context.fill(rect, with: .color(clay.opacity(max(0, min(1, level)))))
                u.stroke(context, rect, tint.opacity(0.35), 0.01)
            }
        }
    }
}

/// The cyanobacterial clock: through the day, KaiC's six subunits gain their
/// clay phosphates one by one; through the night they lose them again.
enum CircadianKaiC {
    static let duration = 5.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let phase = t.truncatingRemainder(dividingBy: duration) / duration
        // The day–night dial round the outside.
        var day = Path()
        day.addArc(center: u.pt(0.5, 0.5), radius: u.len(0.4), startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        u.stroke(context, day, clay.opacity(0.5), 0.02)
        var night = Path()
        night.addArc(center: u.pt(0.5, 0.5), radius: u.len(0.4), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        u.stroke(context, night, tint.opacity(0.35), 0.02)
        let hand = Double.pi + 2 * .pi * phase
        context.fill(u.circle(0.5 + 0.4 * cos(hand), 0.5 + 0.4 * sin(hand), 0.03), with: phase < 0.5 ? .color(clay) : .color(tint))
        // KaiC: six subunits, two phosphorylation sites each.
        let filled = phase < 0.5 ? Int(24 * phase) : Int(24 * (1 - phase))
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 - .pi / 2
            let c = (0.5 + 0.14 * cos(a), 0.5 + 0.14 * sin(a))
            context.fill(u.circle(c.0, c.1, 0.07), with: .color(tint.opacity(0.85)))
            for site in 0..<2 where k * 2 + site < filled {
                let b = a + (site == 0 ? -0.35 : 0.35)
                context.fill(u.circle(0.5 + 0.25 * cos(b), 0.5 + 0.25 * sin(b), 0.022), with: .color(clay))
            }
        }
    }
}

/// The waggle dance: a bee runs straight, shaking, at the angle to the food,
/// loops back one way, runs again, loops back the other; the runs in clay.
enum WaggleDance {
    static let duration = 5.0
    private static let angle = -0.5

    /// Where the bee is `s` (0...1) through one figure of eight.
    private static func path(_ s: Double) -> (Double, Double, heading: Double) {
        let run = 0.36
        let dir = (sin(angle), -cos(angle))
        let start = (0.5 - dir.0 * run / 2, 0.52 - dir.1 * run / 2)
        let lap = s < 0.5 ? s * 2 : (s - 0.5) * 2
        let side = s < 0.5 ? 1.0 : -1.0
        if lap < 0.45 {
            let f = lap / 0.45
            return (start.0 + dir.0 * run * f, start.1 + dir.1 * run * f, atan2(dir.1, dir.0))
        }
        // The return loop: a half circle back to the start.
        let f = (lap - 0.45) / 0.55
        // Half an ellipse from the run's end back to its start, off to one side.
        let end = (start.0 + dir.0 * run, start.1 + dir.1 * run)
        let middle = ((start.0 + end.0) / 2, (start.1 + end.1) / 2)
        let normal = (-dir.1 * side, dir.0 * side)
        let a = .pi * f
        let p = (middle.0 + dir.0 * (run / 2) * cos(a) + normal.0 * 0.16 * sin(a),
                 middle.1 + dir.1 * (run / 2) * cos(a) + normal.1 * 0.16 * sin(a))
        let tangent = (-dir.0 * sin(a) + normal.0 * cos(a), -dir.1 * sin(a) + normal.1 * cos(a))
        return (p.0, p.1, atan2(tangent.1, tangent.0))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The comb, faintly.
        for row in 0..<7 {
            for col in 0..<7 {
                let c = (0.1 + 0.13 * Double(col) + (row % 2 == 0 ? 0 : 0.065), 0.12 + 0.113 * Double(row))
                var hex = u.polyline((0..<6).map { k in Rings.offset(c, 0.07, 30 + 60 * Double(k)) })
                hex.closeSubpath()
                u.stroke(context, hex, tint.opacity(0.12), 0.01)
            }
        }
        let s = (t / 2.5).truncatingRemainder(dividingBy: 1)
        // The whole figure of eight, faint, and the straight run in clay.
        let loop = stride(from: 0.0, through: 1.0, by: 0.01).map { v -> (Double, Double) in let p = path(v); return (p.0, p.1) }
        u.stroke(context, u.polyline(loop), tint.opacity(0.25), 0.012)
        let dir = (sin(angle), -cos(angle))
        let run = 0.36
        let start = (0.5 - dir.0 * run / 2, 0.52 - dir.1 * run / 2)
        u.stroke(context, u.line(start, (start.0 + dir.0 * run, start.1 + dir.1 * run)), clay.opacity(0.7), 0.035)
        var (x, y, heading) = path(s)
        let lap = s < 0.5 ? s * 2 : (s - 0.5) * 2
        if lap < 0.45 {
            let waggle = 0.018 * sin(t * 40)
            x += waggle * cos(heading + .pi / 2)
            y += waggle * sin(heading + .pi / 2)
        }
        // The bee: body along her heading, wings behind.
        var bee = context
        let at = u.pt(x, y)
        bee.translateBy(x: at.x, y: at.y)
        bee.rotate(by: .radians(heading))
        for side in [-1.0, 1.0] {
            bee.fill(Path(ellipseIn: CGRect(x: -u.len(0.05), y: side > 0 ? u.len(0.015) : -u.len(0.07), width: u.len(0.06), height: u.len(0.055))),
                     with: .color(tint.opacity(0.4)))
        }
        bee.fill(Path(ellipseIn: CGRect(x: -u.len(0.075), y: -u.len(0.035), width: u.len(0.15), height: u.len(0.07))), with: .color(tint))
        for k in 0..<2 {
            bee.fill(Path(CGRect(x: -u.len(0.03) + u.len(0.035) * Double(k), y: -u.len(0.035), width: u.len(0.014), height: u.len(0.07))),
                     with: .color(clay))
        }
    }
}

/// A tardigrade: it ambles through a drop of water; the water dries and it
/// curls into a tun; a clay drop falls, and it unfurls and walks again.
enum Tardigrade {
    static let duration = 5.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let dry = Keyframes.value(t, [(0.9, 0), (1.6, 1), (3.5, 1), (4.2, 0)])
        // The water film, shrinking away and coming back.
        let pool = 0.4 * (1 - dry) + 0.02
        context.fill(u.ellipse(0.5, 0.72, 2 * pool + 0.1, 0.12), with: .color(tint.opacity(0.1 * (1 - dry) + 0.02)))
        u.stroke(context, u.line((0.06, 0.78), (0.94, 0.78)), tint.opacity(0.4), 0.018)
        // The drop that revives it.
        let fall = Ease.clamp((t - 3.1) / 0.4)
        if fall > 0, fall < 1 {
            context.fill(u.circle(0.5, 0.1 + 0.52 * fall * fall, 0.03), with: .color(clay))
        }
        // The body: long and segmented, or curled into a barrel.
        let length = 0.42 - 0.24 * dry
        let height = 0.14 + 0.02 * dry
        let walk = (1 - dry) * t * 6
        let cx = 0.5 + 0.04 * sin(t * 0.8) * (1 - dry)
        context.fill(u.capsule(cx, 0.62, length, height, corner: height / 2), with: .color(tint))
        for k in 1..<4 where dry < 0.95 {
            let x = cx - length / 2 + length * Double(k) / 4
            u.stroke(context, u.line((x, 0.62 - height / 2 + 0.01), (x, 0.62 + height / 2 - 0.01)), Color.black.opacity(0.25 * (1 - dry)), 0.01)
        }
        // Eight stubby legs, drawn in as it dries.
        for k in 0..<4 {
            let x = cx - length / 2 + length * (Double(k) + 0.5) / 4
            let swing = 0.012 * sin(walk + Double(k) * 1.6)
            let leg = 0.06 * (1 - dry)
            guard leg > 0.005 else { continue }
            u.stroke(context, u.line((x, 0.62 + height / 2), (x + swing, 0.62 + height / 2 + leg)), tint, 0.03)
            context.fill(u.circle(x + swing + 0.01, 0.62 + height / 2 + leg, 0.008), with: .color(clay))
        }
    }
}

/// A Turing pattern: from a speckle of noise, clay spots grow at their own
/// spacing, each holding the next one off, until the field is spotted.
enum TuringPattern {
    static let duration = 5.0
    private static let spots: [(Double, Double, Double)] = {
        var list: [(Double, Double, Double)] = []
        for row in 0..<5 {
            for col in 0..<5 {
                let s = Double(row * 5 + col)
                let x = 0.14 + 0.18 * Double(col) + (row % 2 == 0 ? 0 : 0.09) + 0.03 * (BenchShapes.rand(s * 2.1) - 0.5)
                let y = 0.14 + 0.18 * Double(row) + 0.03 * (BenchShapes.rand(s * 3.7) - 0.5)
                guard x < 0.92 else { continue }
                list.append((x, y, 0.4 + 1.6 * BenchShapes.rand(s * 5.3)))
            }
        }
        return list
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let settle = Ease.inOut((t - 0.4) / 2.6)
        for k in 0..<90 {
            let s = Double(k)
            let x = 0.06 + 0.88 * BenchShapes.rand(s * 1.9), y = 0.06 + 0.88 * BenchShapes.rand(s * 4.1)
            let flicker = 0.5 + 0.5 * sin(t * 6 + s)
            context.fill(u.circle(x, y, 0.009), with: .color(tint.opacity(0.5 * flicker * (1 - settle))))
        }
        for spot in spots {
            let grow = Ease.outBack((t - spot.2) / 1.1)
            guard grow > 0 else { continue }
            context.fill(u.circle(spot.0, spot.1, 0.055 * grow), with: .color(clay))
            u.stroke(context, u.circle(spot.0, spot.1, 0.085 * grow), tint.opacity(0.15 * grow), 0.012)
        }
    }
}

/// A Venus flytrap: two lobes open in a V, their clay insides showing, teeth
/// along the rims; a fly lands, brushes one trigger hair and then a second,
/// and the lobes snap shut into an upright pod, the teeth interlocking.
enum VenusFlytrap {
    static let duration = 5.0
    private static let hinge = (0.5, 0.7)

    /// A lobe tipped `angle` from upright, towards `side`, its clay inner
    /// face showing as much as `inside` says (none once shut).
    private static func lobe(_ context: GraphicsContext, _ u: UnitSquare, angle: Double, side: Double, inside: Double, tint: Color) {
        var leaf = context
        let at = u.pt(hinge.0, hinge.1)
        leaf.translateBy(x: at.x, y: at.y)
        leaf.rotate(by: .radians(side * angle))
        let length = u.len(0.4), width = u.len(0.16)
        let shape = Path(ellipseIn: CGRect(x: side > 0 ? 0 : -width, y: -length, width: width, height: length))
        leaf.fill(shape, with: .color(tint))
        // The clay inner face, towards the middle.
        let inner = Path(ellipseIn: CGRect(x: side > 0 ? u.len(0.015) : -width * 0.55, y: -length * 0.92, width: width * 0.55, height: length * 0.84))
        if inside > 0.01 { leaf.fill(inner, with: .color(clay.opacity(inside))) }
        // Teeth along the outer rim, pointing up and out.
        for k in 0..<7 {
            let f = 0.15 + 0.12 * Double(k)
            let y = -length * f
            let x = side * width * 0.5 * (1 + sqrt(max(0, 1 - pow(1 - 2 * f, 2))))
            leaf.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + side * u.len(0.04), y: y - u.len(0.035)))
            }, with: .color(tint), lineWidth: max(u.len(0.012), UnitSquare.hairline))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let snap = Ease.out((t - 2.5) / 0.22)
        let angle = 0.62 * (1 - snap) + 0.05 * snap
        u.stroke(context, u.line(hinge, (0.5, 0.96)), tint, 0.035)
        lobe(context, u, angle: angle, side: -1, inside: 1 - snap, tint: tint)
        lobe(context, u, angle: angle, side: 1, inside: 1 - snap, tint: tint)
        // Trigger hairs on the inner faces, flashing at each touch.
        if snap < 0.5 {
            for (k, side) in [(0, -1.0), (1, 1.0)] {
                let touched = k == 0 ? (t > 1.1 && t < 1.5) : (t > 2.1 && t < 2.5)
                let base = (hinge.0 + side * 0.1, hinge.1 - 0.16)
                u.stroke(context, u.line(base, (base.0 - side * 0.02, base.1 - 0.06)), touched ? ivory : tint.opacity(0.8), 0.014)
            }
        }
        // The fly: in, landing, a step, caught.
        if t < 2.55 {
            let land = Ease.inOut((t - 0.2) / 0.8)
            let step = Ease.inOut((t - 1.6) / 0.4)
            let p = (0.1 + (0.44 - 0.1) * land + 0.1 * step, 0.12 + (0.5 - 0.12) * land - 0.04 * sin(.pi * step))
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(tint))
            for side in [-1.0, 1.0] {
                context.fill(u.ellipse(p.0 + side * 0.024, p.1 - 0.02, 0.034, 0.02), with: .color(tint.opacity(0.45)))
            }
        }
    }
}

/// A pollen tube: a pollen grain lands on the stigma and its clay tube grows
/// down the style to the ovule, where fertilisation flashes.
enum PollenTube {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The pistil: stigma, style, ovary with its ovule.
        u.stroke(context, u.capsule(0.5, 0.14, 0.24, 0.08, corner: 0.04), tint, 0.03)
        u.stroke(context, u.line((0.46, 0.18), (0.46, 0.62)), tint, 0.025)
        u.stroke(context, u.line((0.54, 0.18), (0.54, 0.62)), tint, 0.025)
        u.stroke(context, u.circle(0.5, 0.76, 0.16), tint, 0.03)
        u.stroke(context, u.circle(0.5, 0.8, 0.06), tint, 0.022)
        // The pollen grain landing.
        let land = Ease.out((t - 0.1) / 0.6)
        let grain = (0.44 + 0.2 * (1 - land), 0.07 - 0.12 * (1 - land))
        context.fill(u.circle(grain.0, grain.1, 0.035), with: .color(tint))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            u.stroke(context, u.line((grain.0 + 0.035 * cos(a), grain.1 + 0.035 * sin(a)), (grain.0 + 0.05 * cos(a), grain.1 + 0.05 * sin(a))), tint, 0.012)
        }
        // The tube, down the style and round to the ovule.
        let grow = Ease.inOut((t - 0.8) / 2.6)
        if grow > 0 {
            let path = Smooth.curve([grain, (0.49, 0.2), (0.51, 0.38), (0.49, 0.56), (0.5, 0.68), (0.5, 0.76)], samples: 8)
            let shown = Array(path.prefix(max(2, Int(Double(path.count) * grow))))
            u.stroke(context, u.polyline(shown), clay, 0.022)
            context.fill(u.circle(shown.last!.0, shown.last!.1, 0.016), with: .color(clay))
        }
        let flash = Ease.clamp((t - 3.5) / 0.3) * (1 - Ease.clamp((t - 4.4) / 0.4))
        if flash > 0 {
            context.fill(u.circle(0.5, 0.8, 0.06), with: .color(clay.opacity(0.6 * flash)))
            u.stroke(context, u.circle(0.5, 0.8, 0.06 + 0.06 * flash), clay.opacity(1 - flash), 0.02)
        }
    }
}
