// DataBatchJScenes.swift
// ScienceStatus — the figures a lab makes: curves fitted to points and a
// blot marked up for a paper. Each draws in a unit square (see
// `UnitSquare`): axes and fits in the tint, data and highlights in clay.

import SwiftUI

/// A dose–response curve: on a log-dose axis, clay points land one dose at
/// a time, each with its error bar, falling from full response to none; the
/// fitted sigmoid draws through them, and dashed lines find the IC50.
enum DoseResponse {
    static let duration = 4.4
    private static let top = 0.2, bottom = 0.8, left = 0.14, right = 0.92
    private static let doses = (0..<8).map { 0.2 + 0.095 * Double($0) }

    private static func response(_ x: Double) -> Double {
        top + (bottom - top) / (1 + exp(-(x - 0.53) / 0.06))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((left, 0.1), (left, 0.88), (right, 0.88)), tint, 0.035)
        for x in stride(from: 0.24, through: 0.88, by: 0.16) { u.stroke(context, u.line((x, 0.88), (x, 0.91)), tint.opacity(0.5), 0.02) }
        for (i, x) in doses.enumerated() {
            let land = Ease.outBack((t - 0.3 - 0.2 * Double(i)) / 0.3)
            guard land > 0 else { continue }
            let y = response(x) + 0.025 * (BenchShapes.rand(Double(i) * 4.1) - 0.5)
            let bar = 0.025 + 0.015 * BenchShapes.rand(Double(i) * 2.3)
            u.stroke(context, u.line((x, y - bar * land), (x, y + bar * land)), tint.opacity(0.6), 0.015)
            context.fill(u.circle(x, y, 0.024 * min(1, land)), with: .color(clay))
        }
        let fit = Ease.inOut((t - 2.0) / 0.9)
        if fit > 0 {
            let curve = stride(from: left + 0.02, through: right - 0.02, by: 0.01).map { ($0, response($0)) }
            u.stroke(context, u.polyline(curve).trimmedPath(from: 0, to: fit), tint, 0.03)
        }
        // The IC50: across from half the response, down to the dose.
        let find = Ease.inOut((t - 3.0) / 0.6)
        if find > 0 {
            let half = (top + bottom) / 2, ic50 = 0.53
            let dash = StrokeStyle(lineWidth: max(u.len(0.018), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.025), u.len(0.025)])
            let across = left + (ic50 - left) * min(1, find * 2)
            context.stroke(u.line((left, half), (across, half)), with: .color(tint.opacity(0.7)), style: dash)
            if find > 0.5 {
                let down = half + (0.88 - half) * (find - 0.5) * 2
                context.stroke(u.line((ic50, half), (ic50, down)), with: .color(tint.opacity(0.7)), style: dash)
            }
            if find >= 1 { context.fill(u.circle(ic50, 0.88, 0.022), with: .color(clay)) }
        }
    }
}

/// A clonogenic survival curve: surviving fraction on a log axis against
/// radiation dose; points land for the untreated cells, which bend down
/// after a shoulder, and in clay for cells given a radiosensitiser, which
/// fall faster; the linear-quadratic fit draws through each.
enum ClonogenicSurvival {
    static let duration = 4.6
    private static let top = 0.16, height = 0.66, left = 0.14, right = 0.92
    private static let doses = [0.0, 2, 4, 6, 8]

    /// Where surviving fraction S = exp(-(αD + βD²)) sits on a log axis
    /// spanning three decades.
    private static func y(_ dose: Double, alpha: Double, beta: Double) -> Double {
        let log10S = -(alpha * dose + beta * dose * dose) / log(10)
        return top + height * min(1, -log10S / 3)
    }
    private static func x(_ dose: Double) -> Double { left + 0.04 + (right - left - 0.08) * dose / 8 }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((left, 0.1), (left, 0.86), (right, 0.86)), tint, 0.035)
        for k in 1...3 {
            let yy = top + height * Double(k) / 3
            u.stroke(context, u.line((left, yy), (right, yy)), tint.opacity(0.18), 0.015)
        }
        let arms: [(alpha: Double, beta: Double, color: Color, at: Double)] = [
            (0.15, 0.035, tint, 0.3), (0.35, 0.06, clay, 1.6),
        ]
        for arm in arms {
            for (i, d) in doses.enumerated() {
                let land = Ease.outBack((t - arm.at - 0.16 * Double(i)) / 0.3)
                guard land > 0 else { continue }
                let p = (x(d), y(d, alpha: arm.alpha, beta: arm.beta))
                u.stroke(context, u.line((p.0, p.1 - 0.025 * land), (p.0, p.1 + 0.025 * land)), arm.color.opacity(0.55), 0.015)
                context.fill(u.circle(p.0, p.1, 0.022 * min(1, land)), with: .color(arm.color))
            }
            let fit = Ease.inOut((t - arm.at - 0.9) / 0.8)
            if fit > 0 {
                let curve = stride(from: 0.0, through: 8, by: 0.1).map { (x($0), y($0, alpha: arm.alpha, beta: arm.beta)) }
                u.stroke(context, u.polyline(curve).trimmedPath(from: 0, to: fit), arm.color, 0.028)
            }
        }
    }
}

/// Marking up a western blot for a figure: size ticks come out from the
/// ladder, an arrow slides in to the band of interest, a clay box traces
/// round it in the lane that matters, and below, bars rise for each lane's
/// band against its loading control.
enum BlotAnnotation {
    static let duration = 4.6
    private static let lanes = [0.36, 0.5, 0.64, 0.78]
    private static let strength = [0.35, 0.6, 1.0, 0.8]
    private static let ladder = [0.14, 0.22, 0.3, 0.4, 0.5]
    private static let target = 0.3, control = 0.52

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.52, 0.34, 0.66, 0.5, corner: 0.02), tint.opacity(0.5), 0.025)
        for y in ladder { u.stroke(context, u.line((0.22, y), (0.28, y)), tint.opacity(0.75), 0.022) }
        for (i, x) in lanes.enumerated() {
            u.stroke(context, u.line((x - 0.045, target), (x + 0.045, target)), clay.opacity(strength[i]), 0.04)
            u.stroke(context, u.line((x - 0.045, control), (x + 0.045, control)), tint.opacity(0.85), 0.035)
        }
        // Size ticks out from the ladder.
        let ticks = Ease.inOut((t - 0.4) / 0.7)
        for (k, y) in ladder.enumerated() where Ease.clamp(ticks * 5 - Double(k)) > 0 {
            let grow = Ease.clamp(ticks * 5 - Double(k))
            u.stroke(context, u.line((0.18 - 0.08 * grow, y), (0.18, y)), tint, 0.02)
        }
        // The arrow, in from the right to the target band's row.
        let arrow = Ease.out((t - 1.2) / 0.5)
        if arrow > 0 {
            let x = 1.1 - (1.1 - 0.9) * arrow
            var head = u.line((x, target), (x + 0.05, target - 0.03), (x + 0.05, target + 0.03))
            head.closeSubpath()
            context.fill(head, with: .color(clay))
            u.stroke(context, u.line((x + 0.04, target), (x + 0.1, target)), clay, 0.025)
        }
        // The box, tracing round the band in the third lane.
        let box = Ease.inOut((t - 1.8) / 0.7)
        if box > 0 {
            u.stroke(context, u.capsule(lanes[2], target, 0.14, 0.09, corner: 0.012).trimmedPath(from: 0, to: box), clay, 0.022)
        }
        // Below: each lane's band against its loading control.
        u.stroke(context, u.line((0.28, 0.93), (0.86, 0.93)), tint, 0.025)
        for (i, x) in lanes.enumerated() {
            let rise = Ease.outBack((t - 2.6 - 0.15 * Double(i)) / 0.35)
            guard rise > 0 else { continue }
            let h = 0.2 * strength[i] * min(1, rise)
            context.fill(u.capsule(x, 0.93 - h / 2, 0.07, h, corner: 0.008), with: .color(i == 2 ? clay : tint.opacity(0.7)))
        }
    }
}

/// A blot figure made in a vector editor: the pointer picks the blot, and
/// its box and handles appear; a corner is dragged in to crop off the messy
/// lane; the text tool labels each lane + or −; the line tool draws a
/// bracket over two lanes; and size marks go down the left side.
enum BlotFigure {
    static let duration = 5.2
    private static let lanes = [0.33, 0.45, 0.57, 0.69, 0.84]
    private static let strength = [0.95, 0.3, 0.9, 0.35, 0.6]
    private static let tools = [0.22, 0.32, 0.42, 0.52]

    private static func pointer(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), tint: Color) {
        var arrow = u.polyline([(p.0, p.1), (p.0, p.1 + 0.1), (p.0 + 0.025, p.1 + 0.076), (p.0 + 0.044, p.1 + 0.11),
                                (p.0 + 0.058, p.1 + 0.103), (p.0 + 0.04, p.1 + 0.07), (p.0 + 0.07, p.1 + 0.068)])
        arrow.closeSubpath()
        context.fill(arrow, with: .color(tint))
    }

    private static func beam(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), tint: Color) {
        u.stroke(context, u.line((p.0, p.1 - 0.04), (p.0, p.1 + 0.04)), tint, 0.018)
        for dy in [-0.04, 0.04] { u.stroke(context, u.line((p.0 - 0.015, p.1 + dy), (p.0 + 0.015, p.1 + dy)), tint, 0.015) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The toolbar, the tool in use outlined in clay.
        let active = t < 1.85 ? 0 : (t < 3.45 ? 1 : 2)
        for (k, y) in tools.enumerated() {
            u.stroke(context, u.capsule(0.07, y, 0.06, 0.06, corner: 0.01), (k == active ? clay : tint.opacity(0.35)), 0.018)
        }
        // The blot, cropped as the corner is dragged in.
        let crop = Ease.inOut((t - 1.0) / 0.6)
        let right = 0.92 - 0.14 * crop, bottom = 0.7 - 0.04 * crop
        let box = Path(CGRect(x: u.pt(0.26, 0.38).x, y: u.pt(0.26, 0.38).y, width: u.len(right - 0.26), height: u.len(bottom - 0.38)))
        var blot = context
        blot.clip(to: box)
        blot.fill(box, with: .color(tint.opacity(0.12)))
        for (i, x) in lanes.enumerated() {
            u.stroke(blot, u.line((x - 0.04, 0.47), (x + 0.04, 0.47)), clay.opacity(strength[i]), 0.035)
            u.stroke(blot, u.line((x - 0.04, 0.58), (x + 0.04, 0.58)), tint.opacity(i == 4 ? 0.4 : 0.8), 0.03)
        }
        // Selected: its box and handles.
        let selected = t > 0.6 && t < 1.85
        if selected {
            u.stroke(context, u.capsule((0.26 + right) / 2, (0.38 + bottom) / 2, right - 0.26, bottom - 0.38, corner: 0), clay, 0.012)
            for x in [0.26, (0.26 + right) / 2, right] {
                for y in [0.38, (0.38 + bottom) / 2, bottom] where !(x == (0.26 + right) / 2 && y == (0.38 + bottom) / 2) {
                    u.stroke(context, u.capsule(x, y, 0.024, 0.024, corner: 0), clay, 0.012)
                }
            }
        }
        // Lane labels, + and −, typed one by one.
        for k in 0..<4 {
            guard t > 2.3 + 0.28 * Double(k) else { continue }
            let x = lanes[k]
            u.stroke(context, u.line((x - 0.02, 0.3), (x + 0.02, 0.3)), tint, 0.02)
            if k % 2 == 0 { u.stroke(context, u.line((x, 0.28), (x, 0.32)), tint, 0.02) }
        }
        // The bracket over the first two lanes.
        let bracket = Ease.inOut((t - 3.75) / 0.4)
        if bracket > 0 {
            var path = Path()
            path.addLines([u.pt(0.3, 0.24), u.pt(0.3, 0.21), u.pt(0.48, 0.21), u.pt(0.48, 0.24)])
            u.stroke(context, path.trimmedPath(from: 0, to: bracket), clay, 0.02)
        }
        // Size marks down the left side.
        for (k, y) in [0.44, 0.52, 0.6].enumerated() {
            let mark = Ease.out((t - 4.2 - 0.12 * Double(k)) / 0.25)
            guard mark > 0 else { continue }
            u.stroke(context, u.line((0.22, y), (0.25, y)), tint, 0.018)
            u.stroke(context, u.line((0.21 - 0.06 * mark, y), (0.19, y)), tint.opacity(0.6), 0.018)
        }
        // The pointer: pick, drag the corner, to the text tool, label the
        // lanes, to the line tool, draw the bracket, away.
        let x = Keyframes.value(t, [(0.3, 0.95), (0.6, 0.55), (0.85, 0.92), (1.6, 0.78), (1.85, 0.07), (2.2, lanes[0]),
                                    (2.3, lanes[0]), (2.58, lanes[1]), (2.86, lanes[2]), (3.14, lanes[3]), (3.45, 0.07),
                                    (3.75, 0.3), (4.15, 0.48), (4.6, 0.95)])
        let y = Keyframes.value(t, [(0.3, 0.95), (0.6, 0.52), (0.85, 0.7), (1.6, 0.66), (1.85, 0.32), (2.2, 0.3),
                                    (3.14, 0.3), (3.45, 0.42), (3.75, 0.21), (4.15, 0.21), (4.6, 0.95)])
        if active == 1 && t > 1.95 {
            beam(context, u, at: (x + 0.03, y), tint: tint)
        } else {
            pointer(context, u, at: (x, y), tint: tint)
        }
        let click = [0.6, 0.85, 1.85, 3.45, 3.75].map { max(0, 1 - abs(t - $0) / 0.12) }.max() ?? 0
        if click > 0 { u.stroke(context, u.circle(x, y, 0.03 + 0.03 * (1 - click)), clay.opacity(click), 0.015) }
    }
}
