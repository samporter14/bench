// CellScenes.swift
// ScienceStatus — lab scenes at the scale of cells. Each draws in a unit
// square (see `UnitSquare`): membranes in the tint, what's inside in clay.

import SwiftUI

/// A cell dividing: its nucleus condenses into chromosomes that line up,
/// split and are pulled apart, and the cell pinches into two, each with a
/// nucleus of its own.
enum Mitosis {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let p = t / duration

        // The membrane: one circle that becomes two, joined by a narrowing
        // waist until they part.
        let split = Ease.inOut((p - 0.45) / 0.5)
        let d = 0.25 * split
        let r = 0.36 - 0.13 * split
        u.stroke(context, membrane(u, d: d, r: r), tint)

        // Nucleus, then chromosomes on the midline.
        let condense = Ease.clamp((p - 0.18) / 0.12)
        if condense < 1 {
            context.fill(u.circle(0.5, 0.5, 0.13 * (1 - condense)), with: .color(clay))
        }
        let apart = 0.03 + 0.22 * Ease.inOut((p - 0.4) / 0.45)
        let gather = Ease.clamp((p - 0.82) / 0.13)
        if condense > 0 {
            for dy in [-0.12, 0.0, 0.12] {
                for side in [-1.0, 1.0] {
                    let x = 0.5 + side * apart
                    let y = 0.5 + dy * (1 - gather)
                    let half = 0.045 * condense
                    u.stroke(context, u.line((x - half, y), (x + half, y)),
                             clay.opacity(1 - gather), 0.075)
                }
            }
        }
        // Daughter nuclei.
        if gather > 0 {
            for side in [-1.0, 1.0] {
                context.fill(u.circle(0.5 + side * apart, 0.5, 0.08 * gather), with: .color(clay))
            }
        }
    }

    /// Two circles of radius `r`, centres `d` either side of the middle,
    /// outlined as one shape while they overlap.
    private static func membrane(_ u: UnitSquare, d: Double, r: Double) -> Path {
        guard d > 0.0001 else { return u.circle(0.5, 0.5, r) }
        guard d < r else {
            var both = u.circle(0.5 - d, 0.5, r)
            both.addPath(u.circle(0.5 + d, 0.5, r))
            return both
        }
        let a = atan2(sqrt(r * r - d * d), d)
        var path = Path()
        path.addArc(center: u.pt(0.5 - d, 0.5), radius: u.len(r),
                    startAngle: .radians(-a), endAngle: .radians(a), clockwise: true)
        path.addArc(center: u.pt(0.5 + d, 0.5), radius: u.len(r),
                    startAngle: .radians(.pi - a), endAngle: .radians(a - .pi), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A rod-shaped bacterium dividing: its clay chromosome copies and the
/// copies move apart, the cell grows long, pinches at the middle and
/// becomes two.
enum Fission {
    static let duration = 3.6
    private static let radius = 0.14

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let p = t / duration
        let width = 0.56 + 0.3 * Ease.inOut((p - 0.1) / 0.45)
        let pinch = Ease.inOut((p - 0.5) / 0.3)
        let gap = 0.06 * Ease.out((p - 0.8) / 0.2)

        if pinch < 1 {
            u.stroke(context, waisted(u, centre: (0.5, 0.5), width: width, radius: radius, pinch: pinch), tint)
        } else {
            let half = (width - gap) / 2
            for side in [-1.0, 1.0] {
                let cx = 0.5 + side * (half + gap) / 2
                u.stroke(context, u.capsule(cx, 0.5, half, 2 * radius, corner: radius), tint)
            }
        }

        // Chromosome: one ring that becomes two, each moving to its half.
        let copy = Ease.inOut((p - 0.15) / 0.35)
        for side in [-1.0, 1.0] {
            let x = 0.5 + side * (width + gap) / 4 * copy
            u.stroke(context, u.circle(x, 0.5, 0.05), clay, 0.06)
        }
    }

    /// A capsule `width` wide and `2 radius` tall whose top and bottom dip
    /// at the middle; at `pinch` 1 the dips meet. Shared with the
    /// mitochondria, which fuse and divide the same way.
    static func waisted(_ u: UnitSquare, centre: (Double, Double), width: Double, radius r: Double,
                        pinch: Double) -> Path {
        let cx = centre.0, cy = centre.1
        let x0 = cx - width / 2, x1 = cx + width / 2
        let top = cy - r, bottom = cy + r, dip = r * pinch
        let soft = min(r, width / 2 - r)
        var path = Path()
        path.move(to: u.pt(x0 + r, top))
        path.addLine(to: u.pt(cx - soft, top))
        path.addQuadCurve(to: u.pt(cx, top + dip), control: u.pt(cx - soft * 0.3, top))
        path.addQuadCurve(to: u.pt(cx + soft, top), control: u.pt(cx + soft * 0.3, top))
        path.addLine(to: u.pt(x1 - r, top))
        path.addArc(center: u.pt(x1 - r, cy), radius: u.len(r),
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: u.pt(cx + soft, bottom))
        path.addQuadCurve(to: u.pt(cx, bottom - dip), control: u.pt(cx + soft * 0.3, bottom))
        path.addQuadCurve(to: u.pt(cx - soft, bottom), control: u.pt(cx - soft * 0.3, bottom))
        path.addLine(to: u.pt(x0 + r, bottom))
        path.addArc(center: u.pt(x0 + r, cy), radius: u.len(r),
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// A neuron firing twice: the cell body flashes clay, a pulse runs down
/// the axon and splits at its ends, and small clay vesicles leave.
enum Neuron {
    static let duration = 3.2
    private static let spikes = [0.25, 1.65]
    private static let soma = (0.24, 0.5)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let branch = 0.78
        let ends = [(0.92, 0.38), (0.92, 0.62)]

        // Dendrites from the body's edge, a fork on each; the axon and its
        // two terminals.
        for tip in [(0.1, 0.26), (0.05, 0.54), (0.16, 0.78)] {
            let dx = tip.0 - soma.0, dy = tip.1 - soma.1
            let length = sqrt(dx * dx + dy * dy)
            let edge = (soma.0 + 0.12 * dx / length, soma.1 + 0.12 * dy / length)
            let fork = (edge.0 + (tip.0 - edge.0) * 0.55, edge.1 + (tip.1 - edge.1) * 0.55)
            u.stroke(context, u.line(edge, tip), tint, 0.055)
            u.stroke(context, u.line(fork, (fork.0 - 0.07 * dy / length + 0.03 * dx / length,
                                            fork.1 + 0.07 * dx / length + 0.03 * dy / length)), tint, 0.05)
        }
        var flash = 0.0
        for s in spikes where t >= s { flash = max(flash, 1 - Ease.clamp((t - s) / 0.45)) }
        context.fill(u.circle(soma.0, soma.1, 0.12), with: .color(clay.opacity(flash)))
        u.stroke(context, u.circle(soma.0, soma.1, 0.12), tint)
        u.stroke(context, u.line((0.36, 0.5), (branch, 0.5)), tint, 0.06)
        for end in ends {
            u.stroke(context, u.line((branch, 0.5), end), tint, 0.06)
        }

        for s in spikes {
            let run = (t - s) / 0.55
            if run > 0, run < 1 {
                // Down the axon.
                let x = 0.36 + (branch - 0.36) * Ease.inOut(run)
                u.stroke(context, u.line((max(0.36, x - 0.1), 0.5), (x, 0.5)), clay, 0.1)
            }
            let split = (t - s - 0.55) / 0.2
            if split > 0, split < 1 {
                for end in ends {
                    let x = branch + (end.0 - branch) * split, y = 0.5 + (end.1 - 0.5) * split
                    context.fill(u.circle(x, y, 0.05), with: .color(clay))
                }
            }
            let release = (t - s - 0.75) / 0.5
            if release > 0, release < 1 {
                for end in ends {
                    let dy = end.1 < 0.5 ? -1.0 : 1.0
                    let x = end.0 + 0.05 * release, y = end.1 + dy * 0.08 * release
                    context.fill(u.circle(x, y, 0.035), with: .color(clay.opacity(1 - release)))
                }
            }
        }
    }
}

/// A seed in the soil sends up a stem that unfolds two clay leaves, then
/// sways a little.
enum Seedling {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.1, 0.78), (0.9, 0.78)), tint)
        context.fill(u.ellipse(0.5, 0.88, 0.16, 0.1), with: .color(clay))

        let grow = Ease.out((t - 0.3) / 1.7)
        let sway = 0.02 * sin(t * 2.2) * Ease.clamp((t - 2.4) / 0.4)
        func stem(_ s: Double) -> (Double, Double) {
            (0.5 + 0.045 * sin(s * .pi) + sway * s, 0.78 - 0.42 * s)
        }
        if grow > 0 {
            let points = stride(from: 0.0, through: grow, by: 0.05).map(stem) + [stem(grow)]
            u.stroke(context, u.polyline(points), tint)
        }

        let open = Ease.outBack((t - 1.9) / 0.7)
        guard open > 0 else { return }
        let top = stem(1)
        for side in [-1.0, 1.0] {
            var leaf = context
            leaf.translateBy(x: u.pt(top.0, top.1).x, y: u.pt(top.0, top.1).y)
            leaf.rotate(by: .degrees(-side * (35 + 4 * sin(t * 2.2))))
            leaf.scaleBy(x: open, y: open)
            leaf.fill(Path(ellipseIn: CGRect(x: side > 0 ? 0 : -u.len(0.22), y: -u.len(0.055),
                                             width: u.len(0.22), height: u.len(0.11))),
                      with: .color(clay))
        }
    }
}
