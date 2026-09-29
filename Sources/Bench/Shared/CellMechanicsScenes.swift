// CellMechanicsScenes.swift
// ScienceStatus — super-resolution, muscle, motors, meiosis, fate and
// light. Each draws in a unit square (see `UnitSquare`): structures in the
// tint, the blinking, rowing, swapped or lit part in clay.

import SwiftUI

/// Super-resolution (STORM): the blurred spot of an ordinary image fades as
/// single molecules blink on in clay, one at a time, and each leaves a
/// point where it was; the points build a crisp eightfold nuclear-pore ring.
enum STORM {
    static let duration = 4.8
    private static let count = 160

    private static func spot(_ k: Int) -> (Double, Double) {
        let s = Double(k)
        let a = Double(k % 8) * .pi / 4 + 0.12 * (BenchShapes.rand(s) - 0.5)
        let r = 0.22 + 0.035 * (BenchShapes.rand(s + 9) - 0.5)
        return (0.5 + r * cos(a), 0.5 + r * sin(a))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let progress = Ease.clamp((t - 0.2) / 3.4)
        scene.fill(u.circle(0.5, 0.5, 0.3), with: .color(tint.opacity(0.2 * (1 - progress))))
        for k in 0..<count {
            let at = 0.2 + 3.4 * Double(k) / Double(count)
            guard t > at else { break }
            let p = spot(k)
            if t < at + 0.14 {
                scene.fill(u.circle(p.0, p.1, 0.028), with: .color(clay))
            } else {
                scene.fill(u.circle(p.0, p.1, 0.009), with: .color(tint))
            }
        }
    }
}

/// A sarcomere contracting: clay myosin heads row along the actin, the
/// Z-lines are drawn in together, and it relaxes again, twice.
enum Sarcomere {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let squeeze = 0.5 - 0.5 * cos(2 * .pi * t / 2)
        let half = 0.4 - 0.1 * squeeze
        for side in [-1.0, 1.0] {
            let z = 0.5 + side * half
            u.stroke(context, u.line((z, 0.22), (z, 0.78)), tint, 0.05)
            for y in [0.3, 0.5, 0.7] { u.stroke(context, u.line((z, y), (z - side * 0.27, y)), tint, 0.028) }
        }
        for y in [0.4, 0.6] {
            u.stroke(context, u.line((0.3, y), (0.7, y)), clay, 0.05)
            var x = 0.33
            while x < 0.68 {
                if abs(x - 0.5) > 0.03 {
                    let side = x < 0.5 ? -1.0 : 1.0
                    let lean = 0.35 + 0.5 * sin(2 * .pi * t * 2 + x * 20)
                    for dy in [-1.0, 1.0] {
                        u.stroke(context, u.line((x, y + 0.02 * dy), (x + side * 0.025 * lean, y + 0.06 * dy)), clay, 0.02)
                    }
                }
                x += 0.05
            }
        }
    }
}

/// The bacterial flagellar motor: in the cell envelope, the rotor turns
/// inside its clay stator units, driven by protons, and the filament turns
/// with it; a signal docks on the switch and the rotation reverses.
enum FlagellarMotor {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let switched = Ease.inOut((t - 2.2) / 0.3)
        let angle = 7 * min(t, 2.2) - 7 * max(0, t - 2.5) * switched
        for (y, gap) in [(0.3, 0.012), (0.62, 0.012)] {
            for dy in [-gap, gap] {
                u.stroke(context, u.line((0.02, y + dy), (0.4, y + dy)), tint.opacity(0.6), 0.018)
                u.stroke(context, u.line((0.6, y + dy), (0.98, y + dy)), tint.opacity(0.6), 0.018)
            }
        }
        context.stroke(u.line((0.02, 0.42), (0.98, 0.42)), with: .color(tint.opacity(0.4)),
                       style: StrokeStyle(lineWidth: u.len(0.02), dash: [u.len(0.02), u.len(0.02)]))
        for y in [0.3, 0.42] { u.stroke(context, u.ellipse(0.5, y, 0.16, 0.04), tint, 0.025) }
        u.stroke(context, u.line((0.5, 0.2), (0.5, 0.64)), tint, 0.04)
        u.stroke(context, u.ellipse(0.5, 0.62, 0.22, 0.05), tint, 0.025)
        u.stroke(context, u.ellipse(0.5, 0.74, 0.36, 0.08), tint, 0.03)
        for k in 0..<6 {
            let a = angle + Double(k) * .pi / 3
            let front = sin(a) > 0
            context.fill(u.circle(0.5 + 0.16 * cos(a), 0.74 + 0.035 * sin(a), 0.016), with: .color(tint.opacity(front ? 1 : 0.35)))
        }
        for x in [0.33, 0.67] {
            context.fill(u.capsule(x, 0.62, 0.06, 0.12, corner: 0.02), with: .color(clay))
            let flow = ((t * 2 + x * 3).truncatingRemainder(dividingBy: 1))
            context.fill(u.circle(x, 0.52 + 0.2 * flow, 0.012), with: .color(clay.opacity(1 - flow)))
        }
        var hook = Path()
        hook.move(to: u.pt(0.5, 0.2))
        hook.addQuadCurve(to: u.pt(0.6, 0.12), control: u.pt(0.5, 0.12))
        u.stroke(context, hook, tint, 0.035)
        let filament = stride(from: 0.0, through: 1.0, by: 0.04).map { s -> (Double, Double) in
            (0.6 + 0.38 * s, 0.12 + 0.03 * sin(s * 3 * 2 * .pi - angle * 1.5))
        }
        u.stroke(context, u.polyline(filament), tint, 0.025)
        let dock = Ease.out((t - 1.9) / 0.3) * (1 - Ease.inOut((t - 4.1) / 0.3))
        if dock > 0 { context.fill(u.circle(0.3 + 0.08 * dock, 0.86 - 0.08 * dock, 0.022), with: .color(clay)) }
    }
}

/// Meiotic crossover: a pair of homologous chromosomes, one ink and one
/// clay, pairs up; at the chiasma their lower arms change places, and they
/// part as two new, mixed chromosomes.
enum MeioticCrossover {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let pair = Ease.inOut((t - 0.2) / 0.8) * (1 - Ease.inOut((t - 2.6) / 0.9))
        let swap = Ease.inOut((t - 1.3) / 0.9)
        let apart = 0.24 - 0.2 * pair
        let left = 0.5 - apart, right = 0.5 + apart
        // Upper arms keep their columns. While the pair lies together, each
        // lower arm crosses over to the other's column, so the two part as
        // mixed chromosomes.
        u.stroke(scene, u.line((left, 0.18), (left, 0.5)), tint, 0.075)
        u.stroke(scene, u.line((right, 0.18), (right, 0.5)), clay, 0.075)
        let inkLower = left + (right - left) * swap, clayLower = right + (left - right) * swap
        let bow = 0.05 * sin(.pi * swap)
        u.stroke(scene, u.polyline(Smooth.curve([(inkLower, 0.5), (inkLower - bow, 0.66), (inkLower, 0.82)], samples: 6)), tint, 0.075)
        u.stroke(scene, u.polyline(Smooth.curve([(clayLower, 0.5), (clayLower + bow, 0.66), (clayLower, 0.82)], samples: 6)), clay, 0.075)
        if pair > 0.8 && swap > 0 && swap < 1 {
            scene.fill(Sparkles.star(u, 0.5, 0.5, 0.06 * sin(.pi * swap)), with: .color(clay))
        }
    }
}

/// Cell fates: a stem cell stays in the middle, renewing itself, while
/// daughters bud off one at a time and become three kinds of cell: a neuron
/// growing its dendrites and axon, a clay red blood cell, dimpled, and a
/// long, striped muscle fibre.
enum CellFates {
    static let duration = 5.0
    private static let spots: [(Double, Double)] = [(0.24, 0.26), (0.76, 0.28), (0.5, 0.8)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.6) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let pulse = 1 + 0.04 * sin(t * 3)
        for (k, spot) in spots.enumerated() {
            let s = 0.5 + 1.1 * Double(k)
            let bud = Ease.inOut((t - s) / 0.6)
            guard bud > 0 else { continue }
            let become = Ease.inOut((t - s - 0.6) / 0.7)
            let p = (0.5 + (spot.0 - 0.5) * bud, 0.5 + (spot.1 - 0.5) * bud)
            switch k {
            case 0:
                // A neuron: dendrites and an axon grow out of the soma.
                for (i, a) in [200.0, 245, 290].enumerated() {
                    let r = a * .pi / 180
                    let tip = (p.0 + 0.13 * cos(r) * become, p.1 + 0.13 * sin(r) * become)
                    u.stroke(scene, u.line(p, tip), tint, 0.025)
                    if become > 0.6, i == 1 { u.stroke(scene, u.line(tip, (tip.0 - 0.03, tip.1 - 0.04)), tint, 0.02) }
                }
                u.stroke(scene, u.line(p, (p.0 + 0.2 * become, p.1 + 0.12 * become)), tint, 0.025)
                scene.fill(u.circle(p.0, p.1, 0.06 - 0.015 * become), with: .color(tint))
            case 1:
                // A red blood cell: flattens into a clay disc with a dimple.
                let w = 0.12 + 0.08 * become, h = 0.12 - 0.02 * become
                scene.fill(u.ellipse(p.0, p.1, w, h), with: .color(tint.opacity(1 - become)))
                scene.fill(u.ellipse(p.0, p.1, w, h), with: .color(clay.opacity(become)))
                scene.fill(u.ellipse(p.0, p.1, w * 0.45, h * 0.4), with: .color(ivory.opacity(0.5 * become)))
            default:
                // A muscle fibre: stretches long, striped across.
                let w = 0.12 + 0.46 * become
                scene.fill(u.capsule(p.0, p.1, w, 0.12 - 0.02 * become, corner: 0.05), with: .color(tint))
                if become > 0.2 {
                    for k in 0..<Int(10 * become) {
                        let x = p.0 - w / 2 + 0.06 + 0.046 * Double(k)
                        guard x < p.0 + w / 2 - 0.04 else { continue }
                        u.stroke(scene, u.line((x, p.1 - 0.035), (x, p.1 + 0.035)), clay, 0.018)
                    }
                }
            }
        }
        // The stem cell, renewing itself in the middle.
        u.stroke(scene, u.circle(0.5, 0.5, 0.09 * pulse), tint, 0.035)
        scene.fill(u.circle(0.5, 0.5, 0.04 * pulse), with: .color(clay))
    }
}

/// Optogenetics: an optical fibre flashes clay light onto a neuron made to
/// carry light-gated channels; each flash lights the cell and fires a spike
/// that runs down its axon, and the trace below shows one spike for every
/// flash, each over its stimulus mark.
enum Optogenetics {
    static let duration = 4.4
    private static let flashes = [0.5, 1.5, 2.5, 3.5]
    private static let soma = (0.32, 0.42)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lit = flashes.map { max(0, 1 - abs(t - $0 - 0.06) / 0.12) }.max() ?? 0
        // The fibre, and the cone of light from its tip when it flashes.
        u.stroke(context, u.line((soma.0, 0.02), (soma.0, 0.17)), tint, 0.05)
        if lit > 0 {
            var cone = u.polyline([(soma.0 - 0.02, 0.18), (soma.0 + 0.02, 0.18), (soma.0 + 0.11, 0.36), (soma.0 - 0.11, 0.36)])
            cone.closeSubpath()
            context.fill(cone, with: .color(clay.opacity(0.55 * lit)))
        }
        // The neuron: dendrites, soma, axon.
        for a in [150.0, 200, 235] {
            let r = a * .pi / 180
            u.stroke(context, u.line(soma, (soma.0 + 0.16 * cos(r), soma.1 + 0.12 * sin(r))), tint, 0.025)
        }
        var axon = Path()
        axon.move(to: u.pt(soma.0, soma.1))
        axon.addQuadCurve(to: u.pt(0.94, 0.4), control: u.pt(0.62, 0.52))
        u.stroke(context, axon, tint, 0.028)
        context.fill(u.circle(soma.0, soma.1, 0.065), with: .color(tint))
        if lit > 0 { context.fill(u.circle(soma.0, soma.1, 0.065), with: .color(clay.opacity(lit))) }
        // The spike running down the axon after each flash.
        for f in flashes {
            let run = (t - f - 0.1) / 0.45
            guard run > 0, run < 1 else { continue }
            let s = run
            let x = (1 - s) * (1 - s) * soma.0 + 2 * (1 - s) * s * 0.62 + s * s * 0.94
            let y = (1 - s) * (1 - s) * soma.1 + 2 * (1 - s) * s * 0.52 + s * s * 0.4
            context.fill(u.circle(x, y, 0.028), with: .color(clay))
        }
        // The trace: flat, a spike for each flash, stimulus marks beneath.
        let base = 0.8, left = 0.08, right = 0.92
        let now = left + (right - left) * min(1, t / duration)
        var trace: [(Double, Double)] = []
        for x in stride(from: left, through: now, by: 0.004) {
            let at = (x - left) / (right - left) * duration
            let spike = flashes.map { f -> Double in
                let d = at - f - 0.1
                return d > 0 && d < 0.12 ? sin(.pi * d / 0.12) : 0
            }.max() ?? 0
            trace.append((x, base - 0.15 * spike))
        }
        if trace.count > 1 { u.stroke(context, u.polyline(trace), tint, 0.025) }
        for f in flashes where f <= t {
            let x = left + (right - left) * f / duration
            u.stroke(context, u.line((x, base + 0.07), (x + 0.03, base + 0.07)), clay, 0.03)
        }
    }
}
