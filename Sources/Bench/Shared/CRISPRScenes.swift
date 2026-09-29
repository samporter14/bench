// CRISPRScenes.swift
// ScienceStatus — lab scenes of CRISPR at work, step by step. Each draws
// in a unit square (see `UnitSquare`): DNA and Cas9 in the tint, the
// guide, the PAM and every change in clay.

import SwiftUI

/// Cas9 drawn in outline round the DNA, so what happens inside shows.
private func cas9(_ context: GraphicsContext, _ u: UnitSquare, at x: Double, tint: Color, opacity: Double = 1) {
    u.stroke(context, u.capsule(x, 0.56, 0.3, 0.34, corner: 0.14), tint.opacity(0.7 * opacity), 0.04)
}

/// DNA with a bubble: the top strand arched up by `height` between `from`
/// and `to`, the bottom strand straight.
private func bubble(_ context: GraphicsContext, _ u: UnitSquare, from: Double, to: Double, height: Double, tint: Color,
                    top: Double = 0.52, bottom: Double = 0.62) {
    func arch(_ x: Double) -> Double {
        guard x > from, x < to, to > from else { return 0 }
        return height * sin(.pi * (x - from) / (to - from))
    }
    let xs = Array(stride(from: 0.02, through: 0.98, by: 0.01))
    u.stroke(context, u.polyline(xs.map { ($0, top - arch($0)) }), tint, 0.045)
    u.stroke(context, u.line((0.02, bottom), (0.98, bottom)), tint, 0.045)
    var x = 0.06
    while x < 0.97 {
        if arch(x) < 0.01 { u.stroke(context, u.line((x, top), (x, bottom)), tint.opacity(0.45), 0.02) }
        x += 0.05
    }
}

/// PAM patrol: Cas9 steps along the DNA checking each triplet, and stops
/// at the clay PAM, where the DNA opens a small bubble.
enum PAMPatrol {
    static let duration = 4.0
    private static let stops = [0.2, 0.32, 0.44, 0.56, 0.68]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.inOut((t - 2.7) / 0.5)
        bubble(context, u, from: 0.5, to: 0.68, height: 0.07 * open, tint: tint)
        for x in [0.72, 0.77, 0.82] { u.stroke(context, u.line((x, 0.52), (x, 0.62)), clay, 0.03) }
        var x = stops[0]
        for (i, stop) in stops.enumerated().dropFirst() {
            let hop = Ease.inOut((t - 0.3 - 0.5 * Double(i - 1)) / 0.2)
            x += (stop - stops[i - 1]) * hop
        }
        cas9(context, u, at: x + 0.08, tint: tint)
        u.stroke(context, u.line((x - 0.02, 0.46), (x + 0.12, 0.46)), clay, 0.035)
    }
}

/// The R-loop zipper: past the PAM, the clay guide pairs with the target
/// strand one base at a time while the other strand arches away; when the
/// zipper is complete, Cas9's HNH lobe swings into place.
enum RLoop {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let zip = Ease.clamp((t - 0.3) / 2.0)
        let from = 0.7 - 0.44 * zip
        bubble(context, u, from: from - 0.04, to: 0.72, height: 0.13 * min(1, zip * 3), tint: tint)
        for x in [0.76, 0.81, 0.86] { u.stroke(context, u.line((x, 0.52), (x, 0.62)), clay, 0.03) }
        if zip > 0 {
            u.stroke(context, u.line((from, 0.575), (0.7, 0.575)), clay, 0.035)
            var x = 0.69
            while x > from {
                u.stroke(context, u.line((x, 0.575), (x, 0.62)), clay.opacity(0.7), 0.02)
                x -= 0.03
            }
        }
        u.stroke(context, u.capsule(0.5, 0.56, 0.62, 0.42, corner: 0.18), tint.opacity(0.6), 0.04)
        let swing = Ease.outBack((t - 2.4) / 0.4)
        let lobe = (0.32 + 0.12 * swing, 0.3 + 0.06 * swing)
        context.fill(u.circle(lobe.0, lobe.1, 0.05), with: .color(tint))
        let flash = (t - 2.8) / 0.5
        if flash > 0, flash < 1 { u.stroke(context, u.circle(lobe.0, lobe.1, 0.06 + 0.06 * flash), clay.opacity(1 - flash), 0.03) }
    }
}

/// The double cut: inside Cas9 the two nuclease sites pulse on opposite
/// strands, the DNA breaks through both, the ends part, and it resets.
enum DoubleCut {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let split = 0.07 * Ease.out((t - 1.8) / 0.4) * (1 - Ease.inOut((t - 2.9) / 0.5))
        var left = context, right = context
        left.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.len(0.5), height: u.side)))
        right.clip(to: Path(CGRect(x: u.pt(0.5, 0).x, y: u.origin.y, width: u.len(0.5), height: u.side)))
        left.translateBy(x: -u.len(split), y: 0)
        right.translateBy(x: u.len(split), y: 0)
        for side in [left, right] {
            bubble(side, u, from: 0.3, to: 0.7, height: 0.12, tint: tint)
            u.stroke(side, u.line((0.32, 0.575), (0.68, 0.575)), clay, 0.035)
        }
        if split > 0.005 {
            for side in [-1.0, 1.0] {
                let x = 0.5 + side * split
                u.stroke(context, u.line((x, 0.47), (x, 0.64)), clay, 0.035)
            }
        }
        u.stroke(context, u.capsule(0.5, 0.56, 0.62, 0.42, corner: 0.18), tint.opacity(0.6 * (1 - split / 0.07 * 0.5)), 0.04)
        for (x, y, at) in [(0.5, 0.4, 1.0), (0.5, 0.66, 1.25)] {
            let pulse = sin(.pi * Ease.clamp((t - at) / 0.35))
            context.fill(u.circle(x, y, 0.03 + 0.02 * pulse), with: .color(clay.opacity(0.5 + 0.5 * pulse)))
        }
    }
}

/// Base editing: Cas9 holds a small bubble open; one exposed base flips
/// out, changes, clay, and flips back into the helix. Nothing is cut.
enum BaseEdit {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        bubble(context, u, from: 0.34, to: 0.66, height: 0.1, tint: tint)
        cas9(context, u, at: 0.5, tint: tint)
        let out = Ease.inOut((t - 0.6) / 0.5) * (1 - Ease.inOut((t - 2.4) / 0.5))
        let changed = t >= 1.6
        var base = context
        let root = u.pt(0.5, 0.42)
        base.translateBy(x: root.x, y: root.y)
        base.rotate(by: .degrees(-150 * out))
        let r = u.len(0.028)
        base.stroke(Path(CGRect(x: -u.len(0.004), y: 0, width: u.len(0.008), height: u.len(0.07))), with: .color(tint), lineWidth: u.len(0.02))
        let head = CGRect(x: -r, y: u.len(0.07), width: 2 * r, height: 2 * r)
        base.fill(changed ? Path(roundedRect: head, cornerRadius: r * 0.3) : Path(ellipseIn: head), with: .color(changed ? clay : tint))
        let flash = (t - 1.6) / 0.4
        if flash > 0, flash < 1 {
            // Where the flipped-out base sits.
            u.stroke(context, u.circle(0.55, 0.334, 0.04 + 0.04 * flash), clay.opacity(1 - flash), 0.03)
        }
    }
}

/// Prime editing: the nickase opens the target and nicks one strand; the
/// pegRNA's template curls alongside, reverse transcriptase writes a clay
/// patch from it, and the old flap peels away.
enum PrimeEdit {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let peel = Ease.inOut((t - 2.6) / 0.8)
        let write = Ease.inOut((t - 1.4) / 1.1)
        // The top strand, nicked at 0.5; its old flap to the right peels up.
        u.stroke(context, u.line((0.02, 0.52), (0.5, 0.52)), tint, 0.045)
        var flap = Path()
        flap.move(to: u.pt(0.62, 0.52))
        flap.addQuadCurve(to: u.pt(0.98, 0.52 - 0.3 * peel), control: u.pt(0.8, 0.52 - 0.1 * peel))
        u.stroke(context, flap, tint.opacity(1 - peel), 0.045)
        u.stroke(context, u.line((0.02, 0.62), (0.98, 0.62)), tint, 0.045)
        if peel > 0.9 { u.stroke(context, u.line((0.62, 0.52), (0.98, 0.52)), tint.opacity((peel - 0.9) / 0.1), 0.045) }

        let nick = (t - 0.6) / 0.4
        if nick > 0, nick < 1 { u.stroke(context, u.circle(0.5, 0.52, 0.03 + 0.04 * nick), clay.opacity(1 - nick), 0.03) }
        // The pegRNA: guide plus a template curling back over the nick.
        let curl = Ease.inOut((t - 0.8) / 0.6)
        var peg = Path()
        peg.move(to: u.pt(0.34, 0.3))
        peg.addQuadCurve(to: u.pt(0.5 + 0.16 * curl, 0.46), control: u.pt(0.62, 0.26))
        u.stroke(context, peg, clay.opacity(0.6), 0.03)
        if write > 0 { u.stroke(context, u.line((0.5, 0.52), (0.5 + 0.12 * write, 0.52)), clay, 0.05) }
        u.stroke(context, u.capsule(0.52, 0.5, 0.42, 0.4, corner: 0.16), tint.opacity(0.6), 0.04)
        context.fill(u.circle(0.5 + 0.12 * write, 0.44, 0.035), with: .color(tint))
    }
}
