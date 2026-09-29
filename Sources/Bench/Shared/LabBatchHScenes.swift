// LabBatchHScenes.swift
// ScienceStatus — more of the bench: the glove box, the rotary evaporator,
// the freeze-dryer, a liquid nitrogen pour and the analytical balance. Each
// draws in a unit square (see `UnitSquare`): kit in the tint, the sample,
// the solvent or the reading that matters in clay.

import SwiftUI

/// A glove box: gloved hands push in through the ports, one fetches a clay
/// vial from the airlock and sets it down in the middle, and both withdraw.
enum GloveBox {
    static let duration = 5.0
    private static let ports = [(0.36, 0.6), (0.64, 0.6)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.14, 0.8), (0.14, 0.9)), tint, 0.03)
        u.stroke(context, u.line((0.86, 0.8), (0.86, 0.9)), tint, 0.03)
        context.fill(u.capsule(0.5, 0.49, 0.84, 0.62, corner: 0.05), with: .color(tint.opacity(0.08)))
        u.stroke(context, u.capsule(0.5, 0.49, 0.84, 0.62, corner: 0.05), tint, 0.035)
        // The airlock on the right wall, its inner door sliding up.
        let door = Keyframes.value(t, [(1.2, 0), (1.6, 1), (3.2, 1), (3.6, 0)])
        u.stroke(context, u.capsule(0.86, 0.4, 0.1, 0.16, corner: 0.015), tint, 0.022)
        u.stroke(context, u.line((0.81, 0.32 - 0.14 * door), (0.81, 0.48 - 0.14 * door)), tint, 0.03)
        // Where the vial is: in the airlock, in the hand, or set down.
        let carry = Keyframes.value(t, [(2.1, 0), (3.1, 1)])
        let vial: (Double, Double) = t < 2.1 ? (0.86, 0.42) : (0.86 - 0.36 * carry, 0.42 + 0.02 * carry)
        context.fill(u.capsule(vial.0, vial.1, 0.045, 0.09, corner: 0.012), with: .color(clay))
        // The hands: in, one reaching for the vial and back, then out.
        let reach = Keyframes.value(t, [(0.2, 0), (1.0, 1), (4.0, 1), (4.6, 0)])
        let left = (0.36, 0.6 - 0.12 * reach)
        let rightRest = (0.64, 0.6 - 0.12 * reach)
        let fetch = Keyframes.value(t, [(1.6, 0), (2.1, 1), (3.1, 0)])
        let right = (rightRest.0 + (0.8 - rightRest.0) * fetch, rightRest.1 + (0.46 - rightRest.1) * fetch)
        let rightHand = t >= 2.1 && t < 3.1 ? (vial.0 - 0.03, vial.1 + 0.04) : right
        for (port, hand) in [(ports[0], left), (ports[1], rightHand)] {
            u.stroke(context, u.circle(port.0, port.1, 0.085), tint, 0.03)
            guard reach > 0.02 else { continue }
            u.stroke(context, u.line(port, hand), tint, 0.075)
            context.fill(u.circle(hand.0, hand.1, 0.045), with: .color(tint))
        }
    }
}

/// A rotary evaporator: the flask turns in its warm bath, solvent rises as
/// vapour up the neck, condenses on the coil and drips, clay, into the
/// receiving flask, while the level in the turning flask falls.
enum RotaryEvaporator {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let progress = Ease.inOut((t - 0.3) / 4.2)
        // The bath.
        context.fill(u.capsule(0.34, 0.8, 0.38, 0.16, corner: 0.03), with: .color(tint.opacity(0.12)))
        u.stroke(context, u.line((0.15, 0.7), (0.15, 0.88), (0.53, 0.88), (0.53, 0.7)), tint, 0.03)
        // The turning flask, its level falling.
        let centre = (0.34, 0.62)
        var bulb = context
        bulb.clip(to: u.circle(centre.0, centre.1, 0.11))
        let level = 0.63 + 0.06 * progress
        bulb.fill(Path(CGRect(x: u.pt(0.2, level).x, y: u.pt(0.2, level).y, width: u.len(0.3), height: u.len(0.2))), with: .color(clay.opacity(0.85)))
        for k in 0..<3 {
            let a = t * 2.4 + Double(k) * .pi / 3
            let dx = cos(a) * 0.11, dy = sin(a) * 0.11
            bulb.stroke(u.line((centre.0 - dx, centre.1 - dy), (centre.0 + dx, centre.1 + dy)), with: .color(tint.opacity(0.3)), lineWidth: u.len(0.012))
        }
        u.stroke(context, u.circle(centre.0, centre.1, 0.11), tint, 0.03)
        // The neck, the motor and the condenser with its coil.
        u.stroke(context, u.line((0.4, 0.53), (0.58, 0.35)), tint, 0.035)
        context.fill(u.capsule(0.6, 0.33, 0.12, 0.09, corner: 0.02), with: .color(tint))
        u.stroke(context, u.capsule(0.76, 0.38, 0.12, 0.42, corner: 0.05), tint, 0.03)
        let coil = stride(from: 0.2, through: 0.56, by: 0.01).map { y in (0.76 + 0.035 * sin(y * 70), y) }
        u.stroke(context, u.polyline(coil), tint.opacity(0.6), 0.015)
        u.stroke(context, u.line((0.66, 0.33), (0.7, 0.33)), tint, 0.03)
        // Vapour climbing the neck.
        for k in 0..<4 {
            let s = (t * 0.7 + Double(k) / 4).truncatingRemainder(dividingBy: 1)
            let p = (0.42 + 0.3 * s, 0.51 - 0.18 * min(1, s * 1.1))
            context.fill(u.circle(p.0, p.1, 0.012), with: .color(tint.opacity(0.5 * (1 - s))))
        }
        // Drips, and the receiving flask filling.
        let drip = (t * 1.4).truncatingRemainder(dividingBy: 1)
        context.fill(u.circle(0.76, 0.6 + 0.12 * drip * drip, 0.014), with: .color(clay))
        var receiver = context
        receiver.clip(to: u.circle(0.76, 0.8, 0.08))
        let filled = 0.86 - 0.08 * progress
        receiver.fill(Path(CGRect(x: u.pt(0.66, filled).x, y: u.pt(0.66, filled).y, width: u.len(0.2), height: u.len(0.1))), with: .color(clay.opacity(0.85)))
        u.stroke(context, u.circle(0.76, 0.8, 0.08), tint, 0.03)
    }
}

/// A freeze-dryer: under vacuum, frost blooms on the condenser coil while the
/// clay ice cakes in the vials shrink down to powder.
enum FreezeDryer {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let dry = Ease.inOut((t - 0.4) / 3.8)
        // The chamber, two shelves of vials.
        u.stroke(context, u.capsule(0.3, 0.52, 0.38, 0.68, corner: 0.04), tint, 0.03)
        for shelf in [0.5, 0.76] {
            u.stroke(context, u.line((0.13, shelf), (0.47, shelf)), tint.opacity(0.6), 0.02)
            for x in [0.19, 0.3, 0.41] {
                u.stroke(context, u.line((x - 0.035, shelf - 0.15), (x - 0.035, shelf), (x + 0.035, shelf), (x + 0.035, shelf - 0.15)), tint, 0.022)
                let cake = 0.1 * (1 - 0.8 * dry)
                context.fill(Path(CGRect(x: u.pt(x - 0.03, 0).x, y: u.pt(0, shelf - cake).y, width: u.len(0.06), height: u.len(cake))),
                             with: .color(clay.opacity(0.9 - 0.4 * dry)))
            }
        }
        // The pipe across, vapour moving along it.
        u.stroke(context, u.line((0.49, 0.26), (0.62, 0.26)), tint, 0.03)
        for k in 0..<3 {
            let s = (t * 0.9 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            if dry < 0.98 { context.fill(u.circle(0.5 + 0.12 * s, 0.26, 0.011), with: .color(tint.opacity(0.6 * (1 - s)))) }
        }
        // The condenser: a coil that frosts over.
        u.stroke(context, u.capsule(0.75, 0.55, 0.26, 0.6, corner: 0.04), tint, 0.03)
        let coil = stride(from: 0.3, through: 0.8, by: 0.008).map { y in (0.75 + 0.07 * sin(y * 44), y) }
        u.stroke(context, u.polyline(coil), tint.opacity(0.7), 0.02)
        let frost = Int(46 * Ease.out((t - 0.6) / 3.6))
        for k in 0..<frost {
            let y = 0.31 + 0.49 * BenchShapes.rand(Double(k) * 3.1)
            let x = 0.75 + 0.07 * sin(y * 44) + 0.03 * (BenchShapes.rand(Double(k) * 7.7) - 0.5)
            context.fill(u.circle(x, y, 0.009 + 0.006 * BenchShapes.rand(Double(k))), with: .color(tint))
        }
        // The vacuum gauge, its needle falling.
        u.stroke(context, u.circle(0.75, 0.14, 0.06), tint, 0.022)
        let angle = (-30 - 120 * Ease.out((t - 0.2) / 1.6)) * .pi / 180
        u.stroke(context, u.line((0.75, 0.14), (0.75 + 0.045 * cos(angle), 0.14 + 0.045 * sin(angle))), clay, 0.02)
    }
}

/// Pouring liquid nitrogen: the dewar tips, a stream runs into the box, the
/// clay liquid boils, and fog spills over the rim and rolls along the bench.
enum NitrogenPour {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.04, 0.88), (0.96, 0.88)), tint, 0.03)
        let tip = Keyframes.value(t, [(0.3, 0), (1.0, 1), (3.0, 1), (3.6, 0)])
        let pouring = tip > 0.9
        // The dewar, tipping about its base corner.
        var dewar = context
        let pivot = u.pt(0.42, 0.62)
        dewar.translateBy(x: pivot.x, y: pivot.y)
        dewar.rotate(by: .degrees(55 * tip))
        dewar.translateBy(x: -pivot.x, y: -pivot.y)
        dewar.fill(u.capsule(0.3, 0.46, 0.22, 0.32, corner: 0.05), with: .color(tint))
        dewar.stroke(u.line((0.36, 0.3), (0.42, 0.3)), with: .color(tint), lineWidth: u.len(0.04))
        // The stream from the lip into the box.
        let fill = Ease.inOut((t - 1.0) / 2.2)
        if pouring {
            u.stroke(context, u.polyline(Smooth.curve([(0.56, 0.44), (0.62, 0.52), (0.66, 0.66)], samples: 6)), tint.opacity(0.8), 0.025)
        }
        // The foam box and its boiling clay liquid.
        u.stroke(context, u.line((0.56, 0.62), (0.56, 0.88), (0.9, 0.88), (0.9, 0.62)), tint, 0.035)
        let surface = 0.86 - 0.16 * fill
        context.fill(Path(CGRect(x: u.pt(0.58, surface).x, y: u.pt(0, surface).y, width: u.len(0.3), height: u.len(0.86 - surface))),
                     with: .color(tint.opacity(0.18)))
        for k in 0..<6 where fill > 0.05 {
            let phase = (t * 2.2 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
            context.fill(u.circle(0.61 + 0.045 * Double(k), surface + 0.02 - 0.02 * phase, 0.012 * (1 - phase)), with: .color(clay))
        }
        // Fog: puffs over the rim that roll out along the bench and fade.
        let fog = Ease.clamp((t - 1.1) / 0.6) * (1 - Ease.clamp((t - 4.2) / 0.5))
        for k in 0..<14 {
            let born = 1.1 + 0.2 * Double(k)
            let age = t - born
            guard age > 0, fog > 0 else { continue }
            let side = k % 2 == 0 ? -1.0 : 1.0
            let x = (side < 0 ? 0.6 : 0.86) + side * 0.12 * min(age, 2.5)
            let y = 0.62 + 0.24 * Ease.out(age / 1.2)
            let r = 0.045 + 0.03 * min(age, 2)
            context.fill(u.circle(x, min(y, 0.84), r), with: .color(tint.opacity(0.32 * fog * max(0, 1 - age / 2.8))))
        }
    }
}

/// An analytical balance: the weighing boat lowers through the open door,
/// the door slides shut, the reading flickers and settles, and the clay
/// stability mark comes on.
enum AnalyticalBalance {
    static let duration = 4.8
    private static let reading = [1, 0, 4, 8, 2]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The body and its display.
        context.fill(u.capsule(0.5, 0.8, 0.76, 0.14, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(0.5, 0.8, 0.44, 0.08, corner: 0.015), with: .color(Color.black.opacity(0.7)))
        // The draft shield: a glass box whose left door slides shut.
        u.stroke(context, u.capsule(0.5, 0.47, 0.6, 0.46, corner: 0.02), tint.opacity(0.7), 0.022)
        let door = Keyframes.value(t, [(0.2, 1), (0.4, 1), (1.4, 0)])
        u.stroke(context, u.line((0.22 - 0.18 * door, 0.26), (0.22 - 0.18 * door, 0.68)), tint, 0.03)
        // The pan, and the boat with its clay powder coming down onto it.
        u.stroke(context, u.line((0.4, 0.66), (0.6, 0.66)), tint, 0.03)
        u.stroke(context, u.line((0.5, 0.66), (0.5, 0.72)), tint, 0.03)
        let lower = Ease.inOut((t - 0.3) / 0.8)
        let boatY = 0.42 + 0.21 * lower
        let boatX = 0.3 + 0.2 * lower
        var boat = u.polyline([(boatX - 0.07, boatY - 0.03), (boatX - 0.05, boatY), (boatX + 0.05, boatY), (boatX + 0.07, boatY - 0.03)])
        boat.closeSubpath()
        context.fill(boat, with: .color(tint.opacity(0.5)))
        context.fill(u.ellipse(boatX, boatY - 0.018, 0.07, 0.03), with: .color(clay))
        // The reading: nothing, then flickering, then settled.
        let settled = t > 2.6
        for (k, digit) in reading.enumerated() {
            let shown: Int
            if t < 1.0 { shown = 0 }
            else if settled || k < 2 { shown = digit }
            else { shown = Int(BenchShapes.rand(Double(k) * 17 + floor(t * 12)) * 10) }
            SevenSegment.draw(context, u, SevenSegment.digits[shown], x: 0.35 + 0.065 * Double(k), y: 0.8,
                              w: 0.04, h: 0.05, color: ivory, width: 0.01)
        }
        context.fill(u.circle(0.415, 0.822, 0.006), with: .color(ivory))
        if settled {
            let on = Ease.clamp((t - 2.6) / 0.2)
            context.fill(u.circle(0.68, 0.8, 0.014), with: .color(clay.opacity(on)))
        }
    }
}
