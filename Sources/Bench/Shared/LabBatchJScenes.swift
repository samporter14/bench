// LabBatchJScenes.swift
// ScienceStatus — more bench scenes. Each draws in a unit square (see
// `UnitSquare`): kit in the tint, the sample or the signal in clay.

import SwiftUI

/// Western blot detection, antibody by antibody: the clay target protein
/// sits on the membrane; the primary antibody comes down arms first and
/// binds it; the secondary, carrying HRP in clay, grips the primary's tail;
/// then ECL substrate reaches the HRP and it gives off light, pulse after
/// pulse.
enum ECLDetection {
    static let duration = 5.0
    private static let membrane = 0.86, antigen = (0.5, 0.8)

    /// An antibody as a Y: its stem from `tail`, two arms from the fork,
    /// `down` when the arms point down.
    private static func antibody(_ context: GraphicsContext, _ u: UnitSquare, fork: (Double, Double), down: Bool, color: Color) {
        let s = down ? 1.0 : -1.0
        let tail = (fork.0, fork.1 - 0.13 * s)
        u.stroke(context, u.line(fork, tail), color, 0.035)
        for side in [-1.0, 1.0] {
            let arm = (fork.0 + side * 0.055, fork.1 + 0.085 * s)
            u.stroke(context, u.line(fork, arm), color, 0.035)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, membrane), (0.96, membrane)), tint.opacity(0.6), 0.03)
        context.fill(u.circle(antigen.0, antigen.1, 0.045), with: .color(clay))

        // The primary: down onto the antigen, arms first.
        let primary = Ease.out((t - 0.3) / 0.9)
        let primaryFork = (antigen.0, 0.72 - 0.6 * (1 - primary))
        antibody(context, u, fork: primaryFork, down: true, color: tint)
        let primaryTail = (primaryFork.0, primaryFork.1 - 0.13)
        // The secondary: onto the primary's tail, arms first, HRP on top.
        let secondary = Ease.out((t - 1.5) / 0.9)
        if secondary > 0 {
            let fork = (primaryTail.0, primaryTail.1 - 0.09 - 0.6 * (1 - secondary))
            antibody(context, u, fork: fork, down: true, color: tint.opacity(0.7))
            let hrp = (fork.0, fork.1 - 0.16)
            context.fill(u.circle(hrp.0, hrp.1, 0.04), with: .color(clay))
            // Substrate drifts in to the HRP, which lights, pulse by pulse.
            for k in 0..<4 {
                let s = Double(k)
                let arrive = Ease.inOut((t - 2.7 - 0.45 * s) / 0.4)
                guard arrive > 0, arrive < 1 else { continue }
                let from = (hrp.0 + (k % 2 == 0 ? -0.3 : 0.3), hrp.1 - 0.1 + 0.05 * s)
                context.fill(u.circle(from.0 + (hrp.0 - from.0) * arrive, from.1 + (hrp.1 - from.1) * arrive, 0.014),
                             with: .color(tint.opacity(0.7)))
            }
            for k in 0..<4 {
                let glow = (t - 3.05 - 0.45 * Double(k)) / 0.6
                guard glow > 0, glow < 1 else { continue }
                u.stroke(context, u.circle(hrp.0, hrp.1, 0.05 + 0.14 * glow), clay.opacity(1 - glow), 0.025)
                for r in 0..<6 {
                    let a = Double(r) * .pi / 3 + 0.3
                    let inner = 0.07 + 0.08 * glow, outer = inner + 0.04
                    u.stroke(context, u.line((hrp.0 + inner * cos(a), hrp.1 + inner * sin(a)),
                                             (hrp.0 + outer * cos(a), hrp.1 + outer * sin(a))), clay.opacity(1 - glow), 0.02)
                }
            }
        }
    }
}
