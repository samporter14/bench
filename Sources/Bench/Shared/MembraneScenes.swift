// MembraneScenes.swift
// ScienceStatus — lab scenes at a cell's membrane: things crossing it,
// leaving it and signalling through it. Each draws in a unit square (see
// `UnitSquare`): membranes and proteins in the tint, cargo in clay.

import SwiftUI

/// Vesicle budding: a clay cargo gathers under the membrane, which bulges
/// around it and pinches off a vesicle. The vesicle wanders out and back,
/// fuses again, and the cargo returns to where it began.
enum VesicleBudding {
    static let duration = 4.0
    private static let line = 0.62
    private static let radius = 0.12

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let r = radius
        // How far the bud's centre sits above the membrane: below it the
        // bud is a shallow bulge; at r it has pinched off.
        let bud = Ease.inOut((t - 0.3) / 1.2) - Ease.inOut((t - 3.0) / 0.5)
        let rise = -0.7 * r + 1.7 * r * bud
        let free = t > 1.5 && t < 3.0

        // The vesicle's wander after pinching off: up and round, and back.
        let s = Ease.inOut((t - 1.5) / 1.5)
        let home = (0.5, line - r)
        let centre = free
            ? (0.5 + 0.18 * sin(2 * .pi * s), home.1 - 0.24 * sin(.pi * s))
            : (0.5, line - rise)

        if free || rise >= r {
            u.stroke(context, u.line((0.04, line), (0.96, line)), tint)
            u.stroke(context, u.circle(centre.0, centre.1, r), tint)
        } else {
            u.stroke(context, membrane(u, rise: rise), tint)
        }

        // The cargo: up from below into the bud, and back down at the end.
        let gather = Ease.out(t / 0.8)
        let back = Ease.inOut((t - 3.4) / 0.5)
        let start = (0.5, 0.86)
        let inside = centre
        let x = start.0 + (inside.0 - start.0) * gather * (1 - back)
        let y = start.1 + (inside.1 - start.1) * gather * (1 - back)
        context.fill(u.circle(x, y, 0.06), with: .color(clay))
    }

    private static func membrane(_ u: UnitSquare, rise: Double) -> Path {
        MembraneShape.bud(u, line: line, radius: radius, rise: rise)
    }
}

/// A flat membrane with a round bud in it, shared by budding and fusion.
enum MembraneShape {
    /// The membrane at `line`, with a bud of radius `radius` whose centre is
    /// `rise` above it: a shallow bulge while `rise` is below zero, a
    /// sphere on a narrowing neck as it nears `radius`.
    static func bud(_ u: UnitSquare, line: Double, radius r: Double, rise: Double) -> Path {
        let w = sqrt(max(0, r * r - rise * rise))
        var path = Path()
        path.move(to: u.pt(0.04, line))
        path.addLine(to: u.pt(0.5 - w, line))
        if w > 0.0005 {
            let left = atan2(rise, -w), right = atan2(rise, w)
            path.addArc(center: u.pt(0.5, line - rise), radius: u.len(r), startAngle: .radians(left),
                        endAngle: .radians(right < left ? right + 2 * .pi : right), clockwise: false)
        }
        path.addLine(to: u.pt(0.96, line))
        return path
    }
}

/// A receptor signalling: a clay ligand drifts down into the receptor's
/// cup, the cup closes on it, and clay pulses run down its tail through the
/// membrane, each setting off a small signal inside.
enum Receptor {
    static let duration = 3.6
    private static let pulses = [1.3, 2.2]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let membrane = 0.5
        u.stroke(context, u.line((0.04, membrane), (0.96, membrane)), tint)

        let dock = Ease.out(t / 1.1)
        let cupRadius = 0.11 - 0.02 * Ease.inOut((t - 1.0) / 0.3)
        var cup = Path()
        cup.addArc(center: u.pt(0.5, 0.3), radius: u.len(cupRadius),
                   startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        u.stroke(context, cup, tint)
        u.stroke(context, u.line((0.5, 0.3 + cupRadius), (0.5, 0.84)), tint)

        let ligand = (0.66 - 0.16 * dock + 0.03 * sin(t * 5) * (1 - dock), 0.04 + 0.26 * dock)
        context.fill(u.circle(ligand.0, ligand.1, 0.065), with: .color(clay))

        for p in pulses {
            let run = (t - p) / 0.45
            if run > 0, run < 1 {
                let y = 0.42 + 0.42 * Ease.inOut(run)
                u.stroke(context, u.line((0.5, max(0.42, y - 0.1)), (0.5, y)), clay, 0.1)
            }
            let signal = (t - p - 0.45) / 0.5
            if signal > 0, signal < 1 {
                for side in [-1.0, 1.0] {
                    let x = 0.5 + side * 0.14 * Ease.out(signal), y = 0.86 + 0.04 * signal
                    context.fill(u.circle(x, y, 0.045), with: .color(clay.opacity(1 - signal)))
                }
            }
        }
    }
}

/// An ion channel: clay ions drift to a pore in the membrane and pass
/// through it one at a time, its walls giving a little as each goes by.
enum IonChannel {
    static let duration = 3.6
    /// When each ion reaches the pore, and where it starts and ends up.
    private static let ions: [(at: Double, from: Double, to: Double)] = [
        (0.6, 0.18, 0.72), (1.3, 0.8, 0.3), (2.0, 0.3, 0.84), (2.7, 0.7, 0.2),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // Which ion is in the pore, if any, to widen it.
        var give = 0.0
        for ion in ions {
            let d = abs(t - ion.at - 0.15)
            give = max(give, 0.015 * max(0, 1 - d / 0.2))
        }
        for y in [0.42, 0.58] {
            u.stroke(context, u.line((0.04, y), (0.36, y)), tint)
            u.stroke(context, u.line((0.64, y), (0.96, y)), tint)
        }
        for side in [-1.0, 1.0] {
            let x = 0.5 + side * (0.09 + give)
            context.fill(u.capsule(x, 0.5, 0.08, 0.34, corner: 0.04), with: .color(tint))
        }

        for ion in ions {
            let d = t - ion.at
            let point: (Double, Double)
            if d < -0.6 { continue }
            if d < 0 {
                let k = Ease.inOut((d + 0.6) / 0.6)
                point = (ion.from + (0.5 - ion.from) * k, 0.1 + 0.18 * k)
            } else if d < 0.3 {
                point = (0.5, 0.28 + 0.44 * (d / 0.3))
            } else if d < 1.0 {
                let k = Ease.out((d - 0.3) / 0.7)
                point = (0.5 + (ion.to - 0.5) * k, 0.72 + 0.16 * k)
            } else {
                point = (ion.to, 0.88)
            }
            context.fill(u.circle(point.0, point.1, 0.045), with: .color(clay))
        }
    }
}

/// Nanopore sequencing: a clay strand threads down through a pore in the
/// membrane, coiled above and straight below, and short read marks appear
/// beside it as it passes, travelling down with it.
enum Nanopore {
    static let duration = 4.0
    private static let speed = 0.16

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let membrane = 0.46
        let fed = speed * t

        // The strand above: loose coils drawn in towards the pore.
        let above = stride(from: 0.0, through: 1.0, by: 0.025).map { s -> (Double, Double) in
            let y = 0.04 + (membrane - 0.04) * s
            let loose = 1 - s
            return (0.5 + 0.13 * loose * sin(s * 13 + fed * 40), y)
        }
        u.stroke(context, u.polyline(above), clay, 0.06)
        // Below: straight, as far as it has been fed.
        let bottom = min(0.94, membrane + 0.06 + fed)
        u.stroke(context, u.line((0.5, membrane), (0.5, bottom)), clay, 0.06)

        // Read marks: one for each base read, riding down with the strand.
        let lengths = [0.05, 0.09, 0.04, 0.07, 0.1, 0.05, 0.08, 0.06, 0.04, 0.09, 0.07]
        for (k, length) in lengths.enumerated() {
            let y = membrane + 0.08 + fed - Double(k) * 0.065
            guard y > membrane + 0.07, y < 0.94 else { continue }
            u.stroke(context, u.line((0.56, y), (0.56 + length, y)), tint.opacity(0.75), 0.05)
        }

        // The membrane, and the pore protein it holds.
        u.stroke(context, u.line((0.04, membrane), (0.4, membrane)), tint)
        u.stroke(context, u.line((0.6, membrane), (0.96, membrane)), tint)
        u.stroke(context, u.ellipse(0.5, membrane, 0.18, 0.1), tint)
    }
}

/// Viral fusion: an enveloped virus, spikes all round, drifts down to a
/// cell, docks on its spikes, and its envelope merges into the membrane,
/// which opens and flattens as the clay genome slips inside.
enum ViralFusion {
    static let duration = 4.0
    private static let line = 0.64, radius = 0.13, spike = 0.05

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let r = radius
        let arrive = Ease.out(t / 1.2)
        let dock = Ease.inOut((t - 1.2) / 0.3)
        let fuse = Ease.inOut((t - 1.5) / 1.1)
        let enter = Ease.inOut((t - 1.9) / 1.3)

        // Before fusing, the virus is its own circle; after, the bud.
        let touching = line - r - spike
        let centreY = t < 1.5
            ? 0.12 + (touching - 0.12) * arrive + spike * dock
            : line - (r - 2 * r * fuse)
        if t < 1.5 {
            u.stroke(context, u.line((0.04, line), (0.96, line)), tint)
            u.stroke(context, u.circle(0.5, centreY, r), tint)
        } else {
            u.stroke(context, MembraneShape.bud(u, line: line, radius: r, rise: r - 2 * r * fuse), tint)
        }

        // Spikes: all round while it drifts; the ones below fold in as it
        // docks, and the rest fade as the envelopes merge.
        let fade = 1 - Ease.clamp(fuse * 2)
        if fade > 0 {
            for k in 0..<10 {
                let a = Double(k) * .pi / 5 + .pi / 10
                let below = sin(a) > 0.3
                let length = spike * (below ? 1 - dock : 1)
                guard length > 0.004 else { continue }
                let from = (0.5 + r * cos(a), centreY + r * sin(a))
                let tip = (0.5 + (r + length) * cos(a), centreY + (r + length) * sin(a))
                u.stroke(context, u.line(from, tip), tint.opacity(fade), 0.045)
                context.fill(u.circle(tip.0, tip.1, 0.022), with: .color(tint.opacity(fade)))
            }
        }

        // The genome: a short clay coil, going in and loosening.
        let gx = 0.5, gy = centreY + (0.84 - centreY) * enter
        let half = 0.06 + 0.06 * enter
        let coil = stride(from: -half, through: half, by: 0.01).map { dx in
            (gx + dx, gy + 0.025 * sin(dx * 60))
        }
        u.stroke(context, u.polyline(coil), clay, 0.055)
    }
}
