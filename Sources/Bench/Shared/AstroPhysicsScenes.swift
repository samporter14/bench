// AstroPhysicsScenes.swift
// ScienceStatus — more physics and astronomy. Each draws in a unit square
// (see `UnitSquare`): apparatus, fields and bodies in the tint, the
// particle, the probe or the subject in clay.

import SwiftUI

/// Optical tweezers: a clay bead wanders until the focused light catches
/// it at the focus, jiggles there, and drifts off when the light blinks out.
enum OpticalTweezers {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let light = 1 - Ease.clamp((t - 2.8) / 0.15) + Ease.clamp((t - 3.5) / 0.2)
        let focus = (0.5, 0.5)
        var cone = u.line((0.3, 0.02), (0.7, 0.02), (0.5, 0.5), (0.7, 0.98), (0.3, 0.98), (0.5, 0.5))
        cone.closeSubpath()
        context.fill(cone, with: .color(tint.opacity(0.12 * light)))
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((0.5 + 0.2 * side, 0.02), focus, (0.5 + 0.2 * side, 0.98)), tint.opacity(0.6 * light), 0.03)
        }
        let free = (0.28 + 0.1 * sin(t * 1.7) + 0.12 * Ease.inOut((t - 2.9) / 0.8), 0.7 + 0.07 * cos(t * 2.3))
        let held = Ease.inOut((t - 1.0) / 0.6) * (1 - Ease.inOut((t - 2.85) / 0.4))
        let jiggle = (focus.0 + 0.012 * sin(t * 13), focus.1 + 0.01 * cos(t * 11))
        let p = (free.0 + (jiggle.0 - free.0) * held, free.1 + (jiggle.1 - free.1) * held)
        context.fill(u.circle(p.0, p.1, 0.055), with: .color(clay))
    }
}

/// A vortex street: flow past a cylinder rolls up into vortices, shed from
/// its top and its bottom in turn, that spin opposite ways as they drift
/// off downstream: clay above, ink below.
enum VortexStreet {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<4 {
            // Vortex k is shed at second k of the loop, top and bottom by turns.
            let life = (t - Double(k) + duration).truncatingRemainder(dividingBy: duration)
            let top = k % 2 == 0
            let centre = (0.3 + 0.17 * life, top ? 0.37 : 0.63)
            let r = 0.05 + 0.03 * min(life, 2.5)
            let turn = (top ? 1.0 : -1.0) * life * 3
            let spiral = stride(from: 0.0, through: 2.6 * .pi, by: 0.25).map { th -> (Double, Double) in
                let a = (top ? -th : th) + turn
                return (centre.0 + r * th / (2.6 * .pi) * cos(a), centre.1 + r * th / (2.6 * .pi) * sin(a))
            }
            let fade = Ease.clamp(life / 0.4) * Ease.clamp((duration - life) / 0.5)
            u.stroke(context, u.polyline(spiral), (top ? clay : tint).opacity(fade), 0.045)
        }
        context.fill(u.circle(0.15, 0.5, 0.1), with: .color(tint))
    }
}

/// The Meissner effect: a clay magnet rests on a disc; the disc cools into
/// a superconductor and pushes the magnet's field out, so the magnet rises
/// and floats above it, until the disc warms and lets it back down.
enum Meissner {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let cold = Ease.inOut((t - 0.3) / 0.7) - Ease.inOut((t - 3.5) / 0.5)
        let lift = Ease.outBack((t - 1.0) / 0.7) - Ease.inOut((t - 3.6) / 0.6)
        let bob = 0.012 * sin(t * 3) * Ease.clamp(lift)
        let magnet = (0.5, 0.66 - 0.28 * lift + bob)

        context.fill(u.ellipse(0.5, 0.76, 0.64, 0.16), with: .color(tint.opacity(cold)))
        u.stroke(context, u.ellipse(0.5, 0.76, 0.64, 0.16), tint, 0.05)
        // The field: a loop either side of the magnet, which the cold disc
        // won't let in, so the loops flatten above it.
        let floor = 0.66
        for side in [-1.0, 1.0] {
            for (reach, height) in [(0.13, 0.09), (0.19, 0.15)] {
                let centre = (magnet.0 + side * (reach - 0.03), magnet.1)
                let loop = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.2).map { a -> (Double, Double) in
                    let y = centre.1 + height * sin(a)
                    return (centre.0 + reach * cos(a), y + (min(y, floor) - y) * cold)
                }
                u.stroke(context, u.polyline(loop), tint.opacity(0.5), 0.03)
            }
        }
        // Nitrogen boiling off while it cools.
        for (k, x) in [0.24, 0.42, 0.6, 0.78].enumerated() {
            let age = (t - 0.4 - 0.18 * Double(k)) / 0.8
            guard age > 0, age < 1 else { continue }
            u.stroke(context, u.circle(x, 0.72 - 0.22 * age, 0.02 + 0.01 * age), tint.opacity(1 - age), 0.025)
        }
        context.fill(u.capsule(magnet.0, magnet.1, 0.2, 0.12, corner: 0.025), with: .color(clay))
    }
}

/// An exoplanet transit: a small planet crosses its clay star, and the
/// light curve beneath dips smoothly while it's in front.
enum Transit {
    static let duration = 4.0
    private static let star = (0.5, 0.32), radius = 0.22, planet = 0.05

    private static func planetX(_ t: Double) -> Double { 0.06 + 0.88 * Ease.clamp((t - 0.2) / 3.4) }

    private static func dip(_ t: Double) -> Double {
        let d = abs(planetX(t) - star.0)
        return Ease.clamp((radius + planet - d) / (2 * planet))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.circle(star.0, star.1, radius), with: .color(clay))
        context.fill(u.circle(planetX(t), 0.34, planet), with: .color(tint))
        u.stroke(context, u.line((0.08, 0.8), (0.92, 0.8)), tint.opacity(0.25), 0.02)
        let curve = stride(from: 0.0, through: t, by: 0.02).map { s in (0.08 + 0.84 * s / duration, 0.8 + 0.12 * dip(s)) }
        if curve.count > 1 { u.stroke(context, u.polyline(curve), tint, 0.035) }
        if let pen = curve.last { context.fill(u.circle(pen.0, pen.1, 0.028), with: .color(clay)) }
    }
}

/// Spin precession: a clay spin arrow circles round the field direction,
/// tipping further over and then standing back up.
enum Precession {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let base = (0.5, 0.64), length = 0.38
        var y = 0.92
        while y > 0.1 {
            u.stroke(context, u.line((0.5, y), (0.5, y - 0.03)), tint.opacity(0.45), 0.025)
            y -= 0.06
        }
        u.stroke(context, u.line((0.47, 0.13), (0.5, 0.08), (0.53, 0.13)), tint.opacity(0.45), 0.025)
        let tilt = (12 + 38 * sin(.pi * Ease.clamp(t / duration))) * .pi / 180
        let spin = t * 2 * .pi / 1.1
        let height = base.1 - length * cos(tilt)
        u.stroke(context, u.ellipse(0.5, height, 2 * length * sin(tilt), 0.5 * length * sin(tilt)), tint.opacity(0.35), 0.025)
        let tip = (0.5 + length * sin(tilt) * cos(spin), height + 0.25 * length * sin(tilt) * sin(spin))
        u.stroke(context, u.line(base, tip), clay, 0.055)
        let back = atan2(base.1 - tip.1, base.0 - tip.0)
        u.stroke(context, u.line((tip.0 + 0.06 * cos(back - 0.5), tip.1 + 0.06 * sin(back - 0.5)), tip,
                                 (tip.0 + 0.06 * cos(back + 0.5), tip.1 + 0.06 * sin(back + 0.5))), clay, 0.05)
        context.fill(u.circle(base.0, base.1, 0.03), with: .color(tint))
    }
}

/// A Lagrange-point companion: a planet orbits its star, and a small clay
/// satellite keeps station sixty degrees behind it, swaying gently.
enum Lagrange {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let star = (0.5, 0.5), radius = 0.32
        u.stroke(context, u.circle(star.0, star.1, radius), tint.opacity(0.35), 0.02)
        let a = t * 2 * .pi / duration - .pi / 2
        let planet = (star.0 + radius * cos(a), star.1 + radius * sin(a))
        let b = a - (60 + 6 * sin(t * 3)) * .pi / 180
        let r = radius + 0.012 * sin(t * 2)
        let satellite = (star.0 + r * cos(b), star.1 + r * sin(b))
        var triangle = u.polyline([star, planet, satellite])
        triangle.closeSubpath()
        u.stroke(context, triangle, tint.opacity(0.3), 0.02)
        context.fill(u.circle(star.0, star.1, 0.08), with: .color(tint))
        context.fill(u.circle(planet.0, planet.1, 0.045), with: .color(tint))
        context.fill(u.circle(satellite.0, satellite.1, 0.03), with: .color(clay))
    }
}
