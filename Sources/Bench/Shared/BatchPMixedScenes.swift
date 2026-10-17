// BatchPMixedScenes.swift
// ScienceStatus — a lipid flipped across the bilayer, ring-opening polymerization, an Archimedes screw lifting water
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Lipid flip: a bilayer seen side-on, each lipid a head dot on a short tail, with one
/// flippase block standing across it on the right. A lipid waits in the outer leaflet beside
/// the flippase, clay and a little larger than the rest. It swings round through the
/// flippase, head first, to the inner leaflet and rests there. Then the bilayer slides along
/// by one lipid, the outer leaflet towards the flippase and the inner leaflet away from it: the
/// lipid that was flipped drifts off and fades back to the ordinary ink, and the next one
/// arrives at the flippase and turns clay. The protein darkens while it carries a lipid.
enum LipidFlip {
    static let duration = 5.0

    /// Seconds: rest, the swing through the flippase, rest, the slide along (then rest until the loop's end).
    private static let flipAt = 0.5, flipFor = 1.5, slideAt = 2.5, slideFor = 1.7

    private static let mid = 0.5
    /// How far a lipid's head and the end of its tail sit from the bilayer's midline.
    private static let headReach = 0.165, tailReach = 0.065
    /// Where a lipid waits beside the flippase, and the spacing of lipids along a leaflet.
    private static let station = 0.56, spacing = 0.22
    private static let proteinX = 0.78, proteinW = 0.18, proteinH = 0.5

    /// One lipid with its pivot at `x` on the midline, turned `turn` radians from head up
    /// (so `.pi` is head down), with `share` of clay in it: clay lipids are bigger.
    private static func lipid(_ context: GraphicsContext, _ u: UnitSquare, x: Double, turn: Double, share: Double, tint: Color) {
        let dir = (sin(turn), -cos(turn))
        let head = (x + headReach * dir.0, mid + headReach * dir.1)
        let tail = (x + tailReach * dir.0, mid + tailReach * dir.1)
        u.stroke(context, u.line(tail, head), tint, 0.06)
        context.fill(u.circle(head.0, head.1, 0.062), with: .color(tint))
        if share > 0 {
            u.stroke(context, u.line(tail, head), clay.opacity(share), 0.06 + 0.012 * share)
            context.fill(u.circle(head.0, head.1, 0.062 + 0.016 * share), with: .color(clay.opacity(share)))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let flip = Ease.inOut((t - flipAt) / flipFor)
        let slide = Ease.inOut((t - slideAt) / slideFor)
        let busy = sin(.pi * Ease.clamp((t - flipAt) / flipFor))

        // The flippase: a block across the bilayer, filled more darkly while a lipid goes through.
        let block = u.capsule(proteinX, mid, proteinW, proteinH, corner: 0.04)
        context.fill(block, with: .color(tint.opacity(0.14 + 0.22 * busy)))
        u.stroke(context, block, tint, 0.05)

        // The outer leaflet slides towards the flippase; the first lipid to reach it turns clay.
        for k in 1...3 {
            lipid(context, u, x: station - Double(k) * spacing + slide * spacing, turn: 0, share: k == 1 ? slide : 0, tint: tint)
        }
        // The inner leaflet slides away from it; the one that leaves the left edge is out of sight.
        for k in 1...2 {
            lipid(context, u, x: station - Double(k) * spacing - slide * spacing, turn: .pi, share: 0, tint: tint)
        }

        // The clay lipid turns about its pivot, head first towards and through the flippase, then drifts off down the inner leaflet.
        lipid(context, u, x: station - slide * spacing, turn: .pi * flip, share: t < slideAt ? 1 : 1 - slide, tint: tint)
    }
}

/// Ring-opening polymerization: a chain, a zigzag, runs up the square's diagonal
/// from the bottom left and ends in a clay dot, its active end. A ring (a hexagon of
/// bonds) drifts in from the top right, turning, and meets the end. A bond forms
/// between them, the ring's own bond next to it breaks, and the ring unwinds into
/// a zigzag, one more unit on the chain, with the clay end now at its far tip. The
/// chain then scrolls back down its length by one unit while the next ring drifts in, so the end is back where it began.
enum RingOpening {
    static let duration = 5.0

    private typealias Point = (Double, Double)

    /// One bond is `e` long; a chain bond leans `zig` from horizontal, so a six-bond unit is `unitWidth` wide.
    private static let e = 0.12
    private static let zig = 40.0 * Double.pi / 180
    private static let dx = e * cos(zig), dy = e * sin(zig)
    private static let unitWidth = 6 * dx
    /// The chain's active end at rest.
    private static let end: Point = (0.36, 0.55)
    private static let dotR = 0.068, bondW = 0.07

    /// The clock for the ring that is joining (seconds since the loop began; negative is on its way in):
    /// it arrives, the bond forms, the ring's own bond breaks, it unwinds, the chain scrolls.
    private static let comesIn = -2.0, arrives = 0.5, bonds = 0.45
    private static let cuts = 1.0, cutFor = 0.28
    private static let unwinds = 1.25, unwindFor = 1.5
    private static let scrollAt = 3.0, scrollFor = 1.5

    /// Where the ring starts, how far short of the end it first stops, and how far it turns on the way.
    private static let start: Point = (1.35, -0.05)
    private static let pause = 0.35 * e
    private static let spin = 100.0 * Double.pi / 180
    private static let tilt = 18.0

    /// The bond from the end to the ring's first atom leaves up and to the right.
    private static let first: Point = (end.0 + dx, end.1 - dy)
    private static let dock: Point = (first.0 + 0.866 * e, first.1 - 0.5 * e)

    /// Each of the ring's bonds points a little further round than the last; the unit's
    /// bonds lean up and down in turn. The ring unwinds by turning each bond from one to the other.
    private static let ringBond: [Double] = (0..<5).map { (270.0 + 60.0 * Double($0)) * Double.pi / 180 }
    private static let swing: [Double] = (0..<5).map { i in
        let to = (i % 2 == 0 ? zig : -zig)
        var d = (to - ringBond[i]).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }

    /// The ring's six atoms at age `tau`: a hexagon until it has bonded, then unwinding from its first atom.
    private static func atoms(_ tau: Double) -> [Point] {
        if tau < unwinds {
            let come = Ease.out((tau - comesIn) / (arrives - comesIn))
            let snap = Ease.inOut((tau - arrives) / bonds)
            let pauseAt = (dock.0 + pause * cos(-zig), dock.1 + pause * sin(-zig))
            let c = (start.0 + (pauseAt.0 - start.0) * come + (dock.0 - pauseAt.0) * snap,
                     start.1 + (pauseAt.1 - start.1) * come + (dock.1 - pauseAt.1) * snap)
            let turned = spin * (1 - come)
            return (0..<6).map { k in
                let a = (150.0 + 60.0 * Double(k)) * Double.pi / 180 + turned
                return (c.0 + e * cos(a), c.1 + e * sin(a))
            }
        }
        let s = Ease.inOut((tau - unwinds) / unwindFor)
        var pts: [Point] = [first]
        for i in 0..<5 {
            let a = ringBond[i] + s * swing[i]
            pts.append((pts[i].0 + e * cos(a), pts[i].1 + e * sin(a)))
        }
        return pts
    }

    private static func lerp(_ a: Point, _ b: Point, _ f: Double) -> Point {
        (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
    }

    /// A ring still on its way in: a closed hexagon.
    private static func drifting(_ context: GraphicsContext, _ u: UnitSquare, tau: Double, tint: Color) {
        guard tau > comesIn else { return }
        var hexagon = u.polyline(atoms(tau))
        hexagon.closeSubpath()
        u.stroke(context, hexagon, tint, bondW)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The whole scene is tilted so the chain runs up the square's diagonal.
        var layer = context
        layer.translateBy(x: size.width / 2, y: size.height / 2)
        layer.rotate(by: .degrees(-tilt))
        layer.translateBy(x: -size.width / 2, y: -size.height / 2)

        // The next ring, still coming in while the chain scrolls.
        drifting(layer, u, tau: t - duration, tint: tint)

        // The chain, the ring it is opening, and the clay end, all carried along together.
        let scroll = Ease.inOut((t - scrollAt) / scrollFor)
        var group = layer
        group.translateBy(x: u.len(-unitWidth * scroll), y: 0)

        // The chain behind the end, a zigzag running off the bottom left.
        let behind: [Point] = (-9...0).map { j in (end.0 + Double(j) * dx, end.1 - (abs(j) % 2 == 1 ? dy : 0)) }
        let ring = atoms(t)
        let bond = Ease.inOut((t - arrives) / bonds)
        let cut = Ease.inOut((t - cuts) / cutFor)

        if t < arrives {
            u.stroke(group, u.polyline(behind), tint, bondW)
            var hexagon = u.polyline(ring)
            hexagon.closeSubpath()
            u.stroke(group, hexagon, tint, bondW)
        } else {
            // The new bond grows from the end to the ring's first atom; once it is whole it is part of the chain.
            if bond < 1 {
                u.stroke(group, u.polyline(behind), tint, bondW)
                let reach = lerp(end, ring[0], bond)
                u.stroke(group, u.line(end, reach), tint, bondW)
                u.stroke(group, u.polyline(ring), tint, bondW)
            } else {
                u.stroke(group, u.polyline(behind + ring), tint, bondW)
            }
            // The ring's own bond, between its last atom and its first, breaks from the middle outwards.
            if cut < 1 {
                let half = (1 - cut) / 2
                u.stroke(group, u.line(ring[0], lerp(ring[0], ring[5], half)), tint, bondW)
                u.stroke(group, u.line(ring[5], lerp(ring[5], ring[0], half)), tint, bondW)
            }
        }

        // The clay dot is the active end: it passes from the old end to the ring's last atom as the ring's bond breaks.
        let pass = Ease.inOut((t - cuts) / cutFor)
        if pass < 1 { group.fill(u.circle(end.0, end.1, dotR * (1 - pass)), with: .color(clay)) }
        if pass > 0 { group.fill(u.circle(ring[5].0, ring[5].1, dotR * pass), with: .color(clay)) }
    }
}

/// Archimedes screw: a tube inclined up to the right, drawn as two light walls, with its
/// foot in a clay pool. The helix inside is a bold sine-wave flight, the near half of each
/// turn thick and the far half thin, and it slips steadily up the tube as the screw turns
/// twice a loop; each crest moves on by one pitch, so the picture repeats. In each hollow
/// of the flight a clay pocket of water sits on the tube's low wall with a level surface,
/// rides up with it, shrinks away near the top and spills out of the mouth as drops
/// that fall and fade.
enum ArchimedesScrew {
    static let duration = 5.0

    private typealias Point = (Double, Double)

    private static let turns = 2.0
    private static let beta = 33.0 * Double.pi / 180
    private static let centre: Point = (0.47, 0.50)
    private static let length = 0.8, half = 0.1, pitch = 0.36
    private static let wallW = 0.045, nearW = 0.075, farW = 0.05
    /// The tube's axis (up the slope) and its normal (towards the low wall), in the square.
    private static let along: Point = (cos(beta), -sin(beta))
    private static let across: Point = (sin(beta), cos(beta))

    /// Where a pocket's water surface sits above the tube's axis at its middle (a surface level in the
    /// world slopes by tan(beta) in the tube's frame).
    private static let surface = -0.4 * half
    private static let poolTop = 0.75

    /// A drop's path: where it leaves the mouth and how it flies.
    private static let spillRate = 0.5, spillLife = 1.0
    private static let launch: Point = world(length, 0.5 * half)
    private static let fling: Point = (0.1, -0.03)
    private static let gravity = 1.2

    /// A point `a` up the tube and `b` towards its low wall.
    private static func world(_ a: Double, _ b: Double) -> Point {
        let s = a - length / 2
        return (centre.0 + s * along.0 + b * across.0, centre.1 + s * along.1 + b * across.1)
    }

    private static func smooth(_ x: Double) -> Double {
        let v = Ease.clamp(x)
        return v * v * (3 - 2 * v)
    }

    /// Half a turn of the flight that starts `a` up the tube, seen side-on as half a sine wave: the
    /// near half crosses from the high wall to the low wall, the far half crosses back. Cut off at the tube's ends.
    private static func turn(from a: Double, far: Bool) -> [Point]? {
        let start = far ? Double.pi : 0
        let lo = max(start, -a / pitch * 2 * .pi), hi = min(start + .pi, (length - a) / pitch * 2 * .pi)
        guard hi - lo > 0.05 else { return nil }
        let n = 20
        return (0...n).map { i in
            let phi = lo + (hi - lo) * Double(i) / Double(n)
            return world(a + pitch * phi / (2 * .pi), -half * cos(phi))
        }
    }

    /// The flight's edge at `a` when the screw has turned `f` times: a sine wave
    /// from wall to wall with one crest a pitch.
    private static func edge(_ a: Double, _ f: Double) -> Double {
        -half * cos(2 * .pi * (a / pitch - f))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let f = turns * t / duration
        let slope = tan(beta)

        // The pool the foot stands in.
        context.fill(u.capsule(0.26, poolTop + 0.07, 0.46, 0.14, corner: 0.045), with: .color(clay))

        // The water: a pocket in each hollow of the flight, between the dams it makes on the low wall.
        // A pocket is small as it comes out of the pool and as it nears the mouth.
        for k in -2...4 {
            let centreA = pitch * (f + Double(k))
            let a0 = max(0, centreA - pitch / 2), a1 = min(length, centreA + pitch / 2)
            guard a1 - a0 > 0.004 else { continue }
            let fill = smooth((centreA + 0.05) / 0.2) * (1 - smooth((centreA - (length - 0.25)) / 0.3))
            guard fill > 0.01 else { continue }
            let n = 30
            var top: [Point] = []
            for i in 0...n {
                let a = a0 + (a1 - a0) * Double(i) / Double(n)
                var b = max(edge(a, f), surface + slope * (a - centreA))
                b += (half - b) * (1 - fill)
                top.append(world(a, min(b, half)))
            }
            var pocket = u.polyline([world(a0, half)] + top + [world(a1, half)])
            pocket.closeSubpath()
            context.fill(pocket, with: .color(clay))
        }

        // The tube's two walls, lighter than the flight inside.
        let wall = tint.opacity(0.65)
        u.stroke(context, u.polyline([world(0, -half), world(length, -half)]), wall, wallW)
        u.stroke(context, u.polyline([world(0, half), world(length, half)]), wall, wallW)

        // The flight: the far half of each turn thinner, the near half bold.
        for k in -2...4 {
            let a = pitch * (f + Double(k))
            if let far = turn(from: a, far: true) { u.stroke(context, u.polyline(far), tint.opacity(0.85), farW) }
            if let near = turn(from: a, far: false) { u.stroke(context, u.polyline(near), tint, nearW) }
        }

        // Drops leave the mouth in a steady stream and fall in an arc, fading.
        let cycle = (t / spillRate).truncatingRemainder(dividingBy: 1) * spillRate
        for m in 0..<2 {
            let s = cycle + Double(m) * spillRate
            let x = launch.0 + fling.0 * s
            let y = launch.1 + fling.1 * s + 0.5 * gravity * s * s
            let alpha = 1 - smooth((s - 0.55) / (spillLife - 0.55))
            let grow = smooth(s / 0.12)
            context.fill(u.circle(x, y, 0.042 * grow), with: .color(clay.opacity(alpha)))
        }
    }
}
