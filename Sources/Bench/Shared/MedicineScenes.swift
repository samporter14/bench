// MedicineScenes.swift
// ScienceStatus — lab scenes from medicine and physiology. Each draws in a
// unit square (see `UnitSquare`): cells and tissue in the tint, the
// microbe, the signal or the cargo in clay.

import SwiftUI

/// The membrane attack complex: complement pieces arrive one by one and
/// set into a bacterial membrane as the two walls of a pore; the pore
/// opens and clay contents leak out through it.
enum MembraneAttack {
    static let duration = 4.0
    private static let staves = [0.38, 0.62, 0.41, 0.59, 0.44, 0.56]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.clamp((t - 2.1) / 0.3)
        for y in [0.46, 0.6] {
            u.stroke(context, u.line((0.02, y), (0.36, y)), tint, 0.04)
            u.stroke(context, u.line((0.64, y), (0.98, y)), tint, 0.04)
            if open < 1 { u.stroke(context, u.line((0.36, y), (0.64, y)), tint.opacity(1 - open), 0.04) }
        }
        for (k, x) in staves.enumerated() {
            let set = Ease.outBack((t - 0.2 - 0.3 * Double(k)) / 0.4)
            guard set > 0 else { continue }
            let y = 0.53 - 0.4 * (1 - min(1, set))
            context.fill(u.capsule(x, y, 0.028, 0.22, corner: 0.014), with: .color(tint))
        }
        for k in 0..<5 {
            let age = (t - 2.4 - 0.25 * Double(k)) / 1.0
            let p: (Double, Double)
            if age <= 0 {
                p = (0.3 + 0.1 * Double(k), 0.8 + 0.04 * sin(t * 2 + Double(k)))
            } else if age < 1 {
                let k2 = Ease.inOut(age)
                let start = (0.3 + 0.1 * Double(k), 0.8)
                p = (start.0 + (0.5 + 0.1 * sin(Double(k) * 2) * k2 - start.0) * k2, start.1 - 0.62 * k2)
            } else { continue }
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(clay))
        }
    }
}

/// A neutrophil casting its NET: a clay microbe comes close, the
/// neutrophil's lobed nucleus loosens and a fine web of chromatin spreads
/// out round the microbe and holds it.
enum NETosis {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let release = Ease.inOut((t - 1.4) / 1.2)
        let cell = (0.3, 0.56)
        u.stroke(context, u.circle(cell.0, cell.1, 0.18), tint, 0.045)
        for (k, lobe) in [(-0.05, -0.03), (0.02, 0.03), (0.07, -0.04)].enumerated() {
            u.stroke(context, u.circle(cell.0 + lobe.0, cell.1 + lobe.1, 0.04 + 0.003 * Double(k)), tint.opacity(1 - 0.7 * release), 0.03)
        }
        let arrive = Ease.out((t - 0.2) / 1.0)
        let trapped = Ease.clamp((t - 2.3) / 0.3)
        let wiggle = 0.02 * sin(t * 9) * (1 - 0.7 * trapped)
        let microbe = (0.92 + (0.68 - 0.92) * arrive + wiggle, 0.26 + (0.4 - 0.26) * arrive)
        if release > 0 {
            for k in 0..<6 {
                let a = (-50 + Double(k) * 18) * .pi / 180
                let from = (cell.0 + 0.18 * cos(a), cell.1 + 0.18 * sin(a))
                let bend = 0.04 * sin(Double(k) * 1.7)
                let to = (microbe.0 + 0.1 * cos(Double(k)), microbe.1 + 0.1 * sin(Double(k)))
                let strand = Smooth.curve([from, ((from.0 + to.0) / 2 + bend, (from.1 + to.1) / 2 - bend), to])
                u.stroke(context, u.polyline(strand).trimmedPath(from: 0, to: release), tint.opacity(0.6), 0.02)
            }
            if release > 0.6 {
                for k in 0..<3 {
                    let a = Double(k) * 1.2
                    let p = (microbe.0 + 0.08 * cos(a), microbe.1 + 0.08 * sin(a))
                    let q = (microbe.0 + 0.08 * cos(a + 2.2), microbe.1 + 0.08 * sin(a + 2.2))
                    u.stroke(context, u.line(p, q), tint.opacity(0.5 * (release - 0.6) / 0.4), 0.02)
                }
            }
        }
        var bug = context
        let at = u.pt(microbe.0, microbe.1)
        bug.translateBy(x: at.x, y: at.y)
        bug.rotate(by: .degrees(20 + 15 * sin(t * 4) * (1 - trapped)))
        bug.fill(Path(roundedRect: CGRect(x: -u.len(0.05), y: -u.len(0.025), width: u.len(0.1), height: u.len(0.05)),
                      cornerRadius: u.len(0.025)), with: .color(clay))
    }
}

/// Phototransduction: a clay photon strikes the retinal inside an opsin,
/// the retinal straightens, a relay passes the signal along, and the
/// membrane's channels close.
enum Phototransduction {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, 0.28), (0.98, 0.28)), tint.opacity(0.5), 0.03)
        u.stroke(context, u.line((0.02, 0.5), (0.98, 0.5)), tint.opacity(0.5), 0.03)
        for i in 0..<7 {
            context.fill(u.capsule(0.2 + 0.04 * Double(i), 0.39, 0.03, 0.26, corner: 0.015), with: .color(tint))
        }
        let hit = Ease.clamp((t - 0.9) / 0.2)
        let photon = Ease.inOut((t - 0.2) / 0.7)
        if hit < 1 {
            let wave = stride(from: 0.0, through: 0.18, by: 0.01).map { d -> (Double, Double) in
                let s = photon * 0.28 - d
                return (0.06 + s * 0.9 + 0.012 * sin(d * 70), 0.04 + s * 0.9)
            }
            u.stroke(context, u.polyline(wave), clay, 0.03)
        }
        let straight = Ease.inOut((t - 1.0) / 0.3)
        u.stroke(context, u.line((0.28, 0.36), (0.31, 0.4 - 0.04 * straight), (0.34, 0.42 - 0.06 * straight)), hit > 0 ? clay : tint.opacity(0.6), 0.03)
        let relay = [(0.5, 0.6), (0.64, 0.66), (0.78, 0.6)]
        for (k, p) in relay.enumerated() {
            let lit = sin(.pi * Ease.clamp((t - 1.3 - 0.3 * Double(k)) / 0.5))
            context.fill(u.circle(p.0, p.1, 0.035), with: .color(tint))
            if lit > 0 { context.fill(u.circle(p.0, p.1, 0.035), with: .color(clay.opacity(lit))) }
        }
        let close = Ease.inOut((t - 2.3) / 0.6)
        u.stroke(context, u.line((0.02, 0.84), (0.98, 0.84)), tint, 0.04)
        for x in [0.3, 0.5, 0.7] {
            let gap = 0.035 * (1 - close) + 0.008
            context.fill(u.capsule(x - gap, 0.84, 0.03, 0.12, corner: 0.012), with: .color(tint))
            context.fill(u.capsule(x + gap, 0.84, 0.03, 0.12, corner: 0.012), with: .color(tint))
        }
    }
}

/// Mucociliary clearance: a row of cilia beats in a travelling wave under
/// the mucus, which carries a trapped clay particle steadily along.
enum Mucociliary {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let base = 0.86
        u.stroke(context, u.line((0.02, base), (0.98, base)), tint)
        var tips: [(Double, Double)] = []
        for k in 0..<6 {
            let x0 = 0.12 + 0.15 * Double(k)
            let phase = (t / 1.0 + Double(k) * 0.14).truncatingRemainder(dividingBy: 1)
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
            for i in 1...10 {
                let a = theta * .pi / 180 + bend * Double(i) / 10
                p = (p.0 + 0.3 / 10 * sin(a), p.1 - 0.3 / 10 * cos(a))
                points.append(p)
            }
            tips.append(p)
            u.stroke(context, u.polyline(points), tint, 0.045)
        }
        let under = stride(from: 0.02, through: 0.98, by: 0.02).map { x -> (Double, Double) in (x, 0.54 + 0.02 * sin(x * 20 - t * 3)) }
        var mucus = u.polyline(under + [(0.98, 0.3), (0.02, 0.3)])
        mucus.closeSubpath()
        context.fill(mucus, with: .color(tint.opacity(0.14)))
        u.stroke(context, u.polyline(under), tint.opacity(0.5), 0.025)
        let x = 0.08 + 0.84 * (t / duration)
        context.fill(u.circle(x, 0.42 + 0.01 * sin(t * 3), 0.045), with: .color(clay))
    }
}
