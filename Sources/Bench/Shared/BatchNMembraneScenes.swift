// BatchNMembraneScenes.swift
// ScienceStatus — membranes taken apart and joined: SNAREs zipping a vesicle
// into a membrane, detergent lifting a protein out of one. Each draws in a
// unit square (see `UnitSquare`).

import SwiftUI

/// SNARE zipper: a vesicle hangs above the plasma membrane with a loose v-SNARE
/// strand trailing from it, and a loose t-SNARE strand rises from the membrane.
/// The strands reach for each other, meet at their free ends and zip together
/// towards the membranes as a tight clay coil that grows from the middle out,
/// pulling the vesicle down. The coil squeezes the membranes together, the
/// vesicle's bottom opens into a fusion pore and the vesicle flattens into the
/// membrane, which is a straight line again, while its clay cargo leaves below.
/// A fresh vesicle with unzipped strands descends into the starting place.
enum SNAREZipper {
    static let duration = 5.0

    private static let line = 0.8                  // the target membrane
    private static let r = 0.15                    // the vesicle's radius
    private static let cy0 = 0.19                  // the vesicle's centre at rest
    private static let g0 = 0.46                   // gap between vesicle and membrane at rest
    private static let g1 = 0.30                   // the gap once fully zipped
    private static let q0 = 0.25                   // how far apart the free ends start, in half-gaps
    private static let zipAt = 0.3, zipFor = 1.8   // the zip runs from the free ends meeting to the membranes
    private static let squeezeAt = 2.2, squeezeFor = 0.5
    private static let contact = 2.7, melt = 0.9   // the membranes touch; the vesicle flattens in `melt`
    private static let arrives = -1.7              // the fresh vesicle starts falling in this long before it is due
    private static let pitch = 0.14, amp = 0.05
    private static let wobble = 0.045, wavelength = 0.13

    /// The three cargo dots as offsets from the vesicle's centre, and where
    /// each settles below the membrane.
    private static let cargo: [(dx: Double, dy: Double)] = [(0, -0.05), (-0.055, 0.032), (0.055, 0.032)]
    private static let outlets: [(x: Double, y: Double)] = [(0.34, 0.91), (0.5, 0.93), (0.66, 0.91)]

    private static func smooth(_ x: Double) -> Double {
        let t = Ease.clamp(x)
        return t * t * (3 - 2 * t)
    }

    /// Where a vesicle is at age `tau` (0 is the loop's start, negative is on its way in):
    /// its centre, how far the zip has got (below zero the free ends are still
    /// apart; one is fully zipped) and the gap left to the membrane.
    private struct Pose { let cy: Double, q: Double, gap: Double }

    private static func pose(_ tau: Double) -> Pose {
        if tau < 0 {
            let cy = cy0 - 0.6 * (1 - Ease.out((tau - arrives) / -arrives))
            return Pose(cy: cy, q: -q0, gap: line - cy - r)
        }
        let q = -q0 + (1 + q0) * smooth((tau - zipAt) / zipFor)
        let squeeze = smooth((tau - squeezeAt) / squeezeFor)
        let gap = (g0 + (g1 - g0) * Ease.clamp(q)) * (1 - squeeze)
        return Pose(cy: line - gap - r, q: q, gap: gap)
    }

    /// The vesicle's centre height at any age, collapsing into the membrane once it has fused.
    private static func centreY(_ tau: Double) -> Double {
        tau < contact ? pose(tau).cy : line - rise(tau)
    }

    /// How high the vesicle's centre sits above the membrane while it fuses:
    /// r is a sphere resting on it, 0 a hemisphere, -r flat.
    private static func rise(_ tau: Double) -> Double {
        r * (1 - 2 * smooth((tau - contact) / melt))
    }

    /// The membrane with the fused vesicle open in it: a sphere minus its
    /// bottom chord while `rise` is near r, down to a flat line at -r.
    private static func bud(_ u: UnitSquare, rise: Double) -> Path {
        let rr = min(rise, r - 0.0002)
        let w = sqrt(max(0, r * r - rr * rr))
        let left = atan2(rr, -w), right = atan2(rr, w)
        var path = Path()
        path.move(to: u.pt(0.04, line))
        path.addLine(to: u.pt(0.5 - w, line))
        path.addArc(center: u.pt(0.5, line - rr), radius: u.len(r), startAngle: .radians(left),
                    endAngle: .radians(right <= left ? right + 2 * .pi : right), clockwise: false)
        path.addLine(to: u.pt(0.96, line))
        return path
    }

    /// A loose strand from `a` to `b` down the axis: a travelling wave that
    /// dies away at both ends, except at a free tip, which waves in full.
    private static func loose(_ context: GraphicsContext, _ u: UnitSquare, from a: Double, to b: Double,
                              free: Double, phase: Double, tint: Color) {
        let length = abs(b - a)
        guard length > 0.01 else { return }
        let n = max(4, Int(length / 0.012))
        let scale = min(1, length / 0.09)
        var points: [(Double, Double)] = []
        for i in 0...n {
            let s = Double(i) / Double(n)
            let env = sin(.pi * s * (1 - 0.5 * free))
            points.append((0.5 + wobble * scale * env * sin(2 * .pi * length * s / wavelength + phase), a + (b - a) * s))
        }
        u.stroke(context, u.polyline(points), tint, 0.045)
    }

    /// The two strands of one vesicle: loose at each end, a clay coil between.
    private static func strands(_ context: GraphicsContext, _ u: UnitSquare, tau: Double, tint: Color) {
        guard tau > arrives, tau < contact else { return }
        let p = pose(tau)
        let vb = p.cy + r
        let q = p.q
        // The fresh vesicle's strands unreel once it is in view (the t one from the membrane).
        let grow = tau < 0 ? smooth((tau + 1.2) / 0.7) : 1.0
        // Loose lengths: fixed until the ends meet, then whatever the coil leaves.
        let lv = q <= 0 ? g0 / 2 * (1 + q) * grow : (1 - q) * p.gap / 2
        let lt = lv
        let free = q < 0 ? Ease.clamp(-q / q0) : 0
        loose(context, u, from: vb, to: vb + lv, free: free, phase: 2 * .pi * 2 * tau / duration, tint: tint)
        loose(context, u, from: line, to: line - lt, free: free, phase: -2 * .pi * 3 * tau / duration + 1.7, tint: tint)

        guard q > 0 else { return }
        let top = vb + lv, bottom = line - lt
        let length = bottom - top
        guard length > 0.012 else { return }
        // The helix is anchored to the membrane, so the zip reveals it rather than
        // sliding it, and the vesicle sinks over it as it closes in.
        let scale = min(1, length / 0.07)
        let n = max(6, Int(length / 0.008))
        var one: [(Double, Double)] = [], other: [(Double, Double)] = []
        for i in 0...n {
            let y = top + length * Double(i) / Double(n)
            let taper = Ease.clamp(min(y - top, bottom - y) / 0.035)
            let dx = amp * scale * taper * sin(2 * .pi * (line - y) / pitch)
            one.append((0.5 + dx, y))
            other.append((0.5 - dx, y))
        }
        u.stroke(context, u.polyline(one), clay, 0.04)
        u.stroke(context, u.polyline(other), clay, 0.04)
    }

    /// The cargo: held in the vesicle until the pore opens, then through the
    /// pore one by one and out below the membrane, where it fades.
    private static func dots(_ context: GraphicsContext, _ u: UnitSquare, tau: Double) {
        guard tau > arrives, tau < 4.5 else { return }
        let alpha = 1 - smooth((tau - 3.9) / 0.5)
        for (k, c) in cargo.enumerated() {
            let kk = Double(k)
            let start = contact + 0.05 + 0.08 * kk
            let e = smooth((tau - start) / 0.65)
            let jx = 0.006 * sin(2 * .pi * 3 * tau / duration + 2.1 * kk)
            let jy = 0.006 * cos(2 * .pi * 2 * tau / duration + 1.3 * kk)
            // Where it sits in the vesicle (frozen once it sets off), through the pore, out.
            let inside = (0.5 + c.dx + jx, centreY(min(tau, start)) + c.dy + jy)
            let pore = (0.5, line)
            let out = (outlets[k].x, outlets[k].y + 0.02 * smooth((tau - start - 0.65) / 0.6))
            let a = (1 - e) * (1 - e), b = 2 * e * (1 - e), d = e * e
            let x = a * inside.0 + b * pore.0 + d * out.0
            let y = a * inside.1 + b * pore.1 + d * out.1
            context.fill(u.circle(x, y, 0.032), with: .color(clay.opacity(alpha)))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The vesicle's life at its own age, and the next one's, falling in from above.
        let ages = [t, t - duration]
        for tau in ages { strands(context, u, tau: tau, tint: tint) }

        // The membrane, drawn once, over the strands' feet.
        if t >= contact && t < contact + melt {
            u.stroke(context, bud(u, rise: rise(t)), tint)
        } else {
            u.stroke(context, u.line((0.04, line), (0.96, line)), tint)
        }
        for tau in ages where tau > arrives && tau < contact {
            u.stroke(context, u.circle(0.5, pose(tau).cy, r), tint)
        }
        for tau in ages { dots(context, u, tau: tau) }
    }
}

/// Detergent solubilization: a short stretch of lipid bilayer with a clay
/// membrane protein across it. Rings of detergent drift in from each side,
/// the bilayer's edge curls up into a mixed micelle that drifts off, and a
/// second ring settles round the protein, leaving it alone in a belt of
/// detergent. The loop then runs the other way: the belt lets go, the mixed
/// micelles drift back and the lipids flow into a bilayer again around the protein.
enum DetergentSolubilization {
    static let duration = 5.0
    /// Seconds of the forward half, and the rests and hold around it. The
    /// whole loop is a function of one clock that runs up and straight back.
    private static let forward = 1.95, restIn = 0.1, hold = 0.9

    private static let barrel = (w: 0.18, h: 0.40, corner: 0.07)
    /// Lipid columns on the left (outer, then inner), and the bilayer's rows.
    private static let columns = [0.25, 0.345]
    private static let upperHead = 0.355, lowerHead = 0.645, lipidTail = 0.075
    private static let headR = 0.03
    /// A ring of six detergent heads at the bilayer's edge, and what it becomes
    /// once it has taken in the first two columns: ten heads on a larger ring.
    private static let dock = 0.115, ringStart = 0.08, ringEnd = 0.115
    private static let pureAngles: [Double] = [0, 60, 120, 180, 240, 300]
    private static let mixedAngles: [Double] = [0, 36, 144, 180, 216, 324]
    private static let lipidAngles: [Double] = [-108, -72, 108, 72]
    /// The second ring settles on the barrel's left: each of its heads goes to
    /// one of these places on the belt (angles on an ellipse round the protein).
    private static let beltAngles: [Double] = [195, 135, 105, 165, 255, 225]
    private static let beltRx = 0.17, beltRy = 0.29, settle = 0.19

    private static func smooth(_ x: Double) -> Double {
        let t = Ease.clamp(x)
        return t * t * (3 - 2 * t)
    }

    /// The clock: rests, runs forward, holds on the wrapped protein, runs back.
    private static func progress(_ t: Double) -> Double {
        if t < restIn { return 0 }
        if t < restIn + forward { return t - restIn }
        if t < restIn + forward + hold { return forward }
        return max(0, forward - (t - (restIn + forward + hold)))
    }

    /// One side, drawn in its own left-hand coordinates and mirrored for the right.
    private static func side(_ context: GraphicsContext, _ u: UnitSquare, s: Double, mirror: Bool, tint: Color) {
        // A lipid or detergent molecule: its head at (x, y), its tail running along (dx, dy).
        func put(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double, _ tail: Double) {
            let n = max(hypot(dx, dy), 0.0001)
            let hx = mirror ? 1 - x : x
            let ex = hx + (mirror ? -dx : dx) / n * tail, ey = y + dy / n * tail
            u.stroke(context, u.line((hx, y), (ex, ey)), tint, 0.04)
            context.fill(u.circle(hx, y, headR), with: .color(tint))
        }

        // The first ring arrives, takes the two outer columns round itself, and leaves.
        let arrive = smooth(s / 0.45)
        let sigma = smooth((s - 0.40) / 0.45)
        let leave = smooth((s - 0.85) / 0.40)
        // The ring grows towards the barrel so it stays on the canvas.
        let px = -0.25 + (dock + 0.25) * arrive + 0.03 * sigma - (0.30 + dock + 0.03) * leave
        let ring = ringStart + (ringEnd - ringStart) * sigma
        for i in 0..<6 {
            let a = (pureAngles[i] + (mixedAngles[i] - pureAngles[i]) * sigma) * .pi / 180
            put(px + ring * cos(a), 0.5 + ring * sin(a), -cos(a), -sin(a), 0.03 + 0.01 * sigma)
        }
        for (k, deg) in lipidAngles.enumerated() {
            let upper = k < 2
            let a = deg * .pi / 180
            let from = (columns[k % 2], upper ? upperHead : lowerHead)
            let to = (px + ring * cos(a), 0.5 + ring * sin(a))
            put(from.0 + (to.0 - from.0) * sigma, from.1 + (to.1 - from.1) * sigma,
                -cos(a) * sigma, (upper ? 1 : -1) * (1 - sigma) - sin(a) * sigma, lipidTail - 0.01 * sigma)
        }

        // The second ring arrives once the first has gone and opens out round the barrel.
        let qArrive = smooth((s - 1.10) / 0.45)
        let wrap = smooth((s - 1.50) / 0.40)
        let qx = -0.25 + (settle + 0.25) * qArrive
        for i in 0..<6 {
            let a = pureAngles[i] * .pi / 180
            let b = beltAngles[i] * .pi / 180
            let from = (qx + ringStart * cos(a), 0.5 + ringStart * sin(a))
            let slot = (0.5 + beltRx * cos(b), 0.5 + beltRy * sin(b))
            // The tail turns from pointing at the ring's middle to pointing at the barrel's.
            let dx = -cos(a) * (1 - wrap) + (0.5 - slot.0) / max(hypot(0.5 - slot.0, 0.5 - slot.1), 0.0001) * wrap
            let dy = -sin(a) * (1 - wrap) + (0.5 - slot.1) / max(hypot(0.5 - slot.0, 0.5 - slot.1), 0.0001) * wrap
            put(from.0 + (slot.0 - from.0) * wrap, from.1 + (slot.1 - from.1) * wrap, dx, dy, 0.03 + 0.02 * wrap)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let s = progress(t)
        // Drawn a third larger about the middle: a whole micelle has to dock
        // inside the square, which leaves the bilayer small at the menu
        // bar's size; the micelles drifting off are cut at the edge instead.
        var layer = context
        layer.translateBy(x: size.width / 2, y: size.height / 2)
        layer.scaleBy(x: zoom, y: zoom)
        layer.translateBy(x: -size.width / 2, y: -size.height / 2)
        layer.fill(u.capsule(0.5, 0.5, barrel.w, barrel.h, corner: barrel.corner), with: .color(clay))
        side(layer, u, s: s, mirror: false, tint: tint)
        side(layer, u, s: s, mirror: true, tint: tint)
    }

    private static let zoom = 1.35
}
