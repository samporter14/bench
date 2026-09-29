// BatchLPhysicsTwoScenes.swift
// ScienceStatus — physics: nuclei decaying by halves, a gyroscope
// precessing, and Newton's rings.
// Each draws in a unit square (see `UnitSquare`): the apparatus in the tint,
// the thing each one is about in clay.

import SwiftUI

/// Radioactive half-life: sixteen nuclei on the left, a decay curve drawing
/// itself on the right. Each nucleus that decays turns from a solid dot into
/// a dim ring and a particle flies off it; they go at the rate the curve
/// falls, so the count is 8 at one half-life, 4 at two and 2 at three, and a
/// clay dot lands on the curve at each halving. Then the curve winds back
/// and the nuclei refill for a clean loop.
enum HalfLife {
    static let duration = 5.0

    private static let gridX = 0.12, gridY = 0.32, pitch = 0.115
    /// The chart: its axes, and how far along them the curve reaches.
    private static let axisX = 0.62, axisTop = 0.12, axisBase = 0.86, axisRight = 0.95
    private static let curveTop = 0.18, curveRight = 0.93
    /// One half-life in seconds, when the curve starts, and how many
    /// half-lives it runs for before it stops.
    private static let halfLife = 1.0, start = 0.25, span = 3.6
    /// The curve winds back from here, and the nuclei refill as it does.
    private static let rewind = 3.95, rewindLength = 0.6

    /// The nuclei in the order they decay, as grid indices (row by row): the
    /// first eight are the first half-life's, then four, then two, leaving
    /// two far apart to stand. Scattered, so neighbours don't go in a row.
    private static let order: [Int] = [10, 1, 15, 4, 7, 12, 2, 9, 3, 14, 5, 8, 13, 6]

    /// When each nucleus decays, or nil for the two that survive. The k-th
    /// decay lands where the curve reaches (16 - k) / 16, so the count and
    /// the curve agree, and the 8th, 12th and 14th fall on the halvings.
    private static let decays: [Double?] = (0..<16).map { nucleus -> Double? in
        guard let slot = order.firstIndex(of: nucleus) else { return nil }
        let remaining: Double = 16 - Double(slot + 1)
        return start + halfLife * log2(16 / remaining)
    }

    /// Where a nucleus sits, and the way its particle leaves: outwards along
    /// the diagonal, through the gaps between its neighbours.
    private static func nucleus(_ index: Int) -> (x: Double, y: Double, dx: Double, dy: Double) {
        let column = index % 4, row = index / 4
        let out: Double = 0.7071
        return (gridX + pitch * Double(column), gridY + pitch * Double(row),
                column < 2 ? -out : out, row < 2 ? -out : out)
    }

    /// The curve's point after `tau` half-lives.
    private static func point(_ tau: Double) -> (Double, Double) {
        let share: Double = pow(2, -tau)
        return (axisX + (curveRight - axisX) * tau / span, axisBase - (axisBase - curveTop) * share)
    }

    /// How many half-lives the pen has drawn: it runs steadily, then winds
    /// back to the start.
    private static func pen(_ t: Double) -> Double {
        let forward: Double = min(span, max(0, (t - start) / halfLife))
        return forward * (1 - Ease.inOut((t - rewind) / rewindLength))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // The nuclei: solid until they decay, a dim ring after, solid again
        // as the rewind refills them.
        for index in 0..<16 {
            let n = nucleus(index)
            var gone = 0.0
            if let at = decays[index] {
                let slot = order.firstIndex(of: index) ?? 0
                let refill = rewind + 0.35 * Double(slot) / 13
                gone = Ease.out((t - at) / 0.2) * (1 - Ease.inOut((t - refill) / 0.25))
                // The particle leaves along its diagonal and fades.
                let flight = (t - at) / 0.6
                if flight > 0 && flight < 1 {
                    let away = 0.05 + 0.075 * Ease.out(flight)
                    let fade = 1 - Ease.clamp((flight - 0.4) / 0.6)
                    context.fill(u.circle(n.x + n.dx * away, n.y + n.dy * away, 0.03),
                                 with: .color(tint.opacity(fade)))
                }
            }
            if gone < 0.75 {
                context.fill(u.circle(n.x, n.y, 0.045 * (1 - gone)), with: .color(tint))
            }
            if gone > 0 {
                u.stroke(context, u.circle(n.x, n.y, 0.043), tint.opacity(0.5 * gone), 0.03)
            }
        }

        // The axes, and the curve behind the pen.
        u.stroke(context, u.line((axisX, axisTop), (axisX, axisBase), (axisRight, axisBase)), tint.opacity(0.6), 0.035)
        let tau = pen(t)
        var curve: [(Double, Double)] = stride(from: 0.0, to: tau, by: 0.05).map { point($0) }
        curve.append(point(tau))
        if curve.count > 1 { u.stroke(context, u.polyline(curve), tint, 0.05) }
        let head = point(tau)
        context.fill(u.circle(head.0, head.1, 0.035), with: .color(tint))

        // A clay dot as the pen reaches each halving; it goes as the pen winds back past it.
        for halving in 1...3 {
            let pop = Ease.outBack((tau - Double(halving)) / 0.25)
            guard pop > 0 else { continue }
            let at = point(Double(halving))
            context.fill(u.circle(at.0, at.1, 0.052 * pop), with: .color(clay))
        }
    }
}

/// A toy gyroscope on its pedestal: a rotor with one bold line across it
/// spinning fast on an axle that rests on the post at one end and rises
/// towards a free end in clay, inside a thin hoop. The whole thing
/// precesses slowly about the vertical, the free end tracing its circle
/// exactly once a loop, so the rotor turns from a full round face (axle
/// towards you) to a slim sliver (axle away). Unlike Precession's arrow it
/// is drawn in 3D, from well above so the rotor keeps some width even then.
enum Gyroscope {
    static let duration = 4.0

    private struct Vec {
        let x: Double, y: Double, z: Double
        func scaled(_ k: Double) -> Vec { Vec(x: x * k, y: y * k, z: z * k) }
        func plus(_ o: Vec) -> Vec { Vec(x: x + o.x, y: y + o.y, z: z + o.z) }
    }

    /// The viewing elevation, and how far the axle rises above the horizontal.
    private static let elevation = 45.0 * Double.pi / 180
    private static let rise = 34.0 * Double.pi / 180
    private static let cosElevation = cos(elevation), sinElevation = sin(elevation)
    /// The pivot on top of the post, the hoop's and the rotor's radii, how far
    /// the axle sticks out past the hoop on the post's side, and how far it
    /// reaches from the pivot to its free end.
    private static let pivot = (x: 0.5, y: 0.6)
    private static let hoopRadius = 0.19, rotorRadius = 0.13, pin = 0.05, reach = 0.44
    /// Turns of the rotor in one loop (a whole number, so it loops), and the
    /// heading at the start of it.
    private static let spins = 7
    private static let heading = -35.0 * Double.pi / 180

    /// A point in the scene on screen: an orthographic view from above.
    private static func screen(_ p: Vec) -> (Double, Double) {
        let height: Double = p.z * cosElevation + p.y * sinElevation
        return (pivot.x + p.x, pivot.y - height)
    }

    /// A circle round `centre` in the plane of `first` and `second`, as screen points.
    private static func circle(_ centre: Vec, _ radius: Double, _ first: Vec, _ second: Vec) -> [(Double, Double)] {
        (0...36).map { k -> (Double, Double) in
            let angle: Double = 2 * .pi * Double(k) / 36
            let offset = first.scaled(cos(angle) * radius).plus(second.scaled(sin(angle) * radius))
            return screen(centre.plus(offset))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let turn: Double = heading + 2 * .pi * t / duration
        let spin: Double = 2 * .pi * Double(spins) * t / duration

        // Along the axle, up across it in the vertical plane through it, and
        // sideways across it. The hoop lies in the first two, the rotor in the last two.
        let along = Vec(x: cos(rise) * cos(turn), y: cos(rise) * sin(turn), z: sin(rise))
        let up = Vec(x: -sin(rise) * cos(turn), y: -sin(rise) * sin(turn), z: cos(rise))
        let side = Vec(x: -sin(turn), y: cos(turn), z: 0)
        let origin = Vec(x: 0, y: 0, z: 0)
        let centre = along.scaled(hoopRadius + pin)
        let hoopEnd = along.scaled(2 * hoopRadius + pin)
        let tip = along.scaled(reach)

        // The circle the free end traces, behind everything else.
        let flat: Double = reach * cos(rise)
        let level = Vec(x: 0, y: 0, z: reach * sin(rise))
        let trace = circle(level, flat, Vec(x: 1, y: 0, z: 0), Vec(x: 0, y: 1, z: 0))
        u.stroke(context, u.polyline(trace), tint.opacity(0.4), 0.03)

        // The pedestal: a post up to the pivot, on a foot.
        let base = 0.9
        u.stroke(context, u.line((pivot.x, pivot.y), (pivot.x, base)), tint, 0.06)
        u.stroke(context, u.line((pivot.x - 0.15, base), (pivot.x + 0.15, base)), tint, 0.06)

        // The hoop and the axle, kept light so the rotor is what you see.
        u.stroke(context, u.polyline(circle(centre, hoopRadius, along, up)), tint.opacity(0.45), 0.03)
        u.stroke(context, u.line(screen(origin), screen(hoopEnd)), tint, 0.045)

        // The rotor: a disc with one line across it, which is what spins.
        var disc = u.polyline(circle(centre, rotorRadius, side, up))
        disc.closeSubpath()
        context.fill(disc, with: .color(tint.opacity(0.3)))
        u.stroke(context, disc, tint, 0.05)
        let across = side.scaled(cos(spin) * rotorRadius).plus(up.scaled(sin(spin) * rotorRadius))
        let from = screen(centre.plus(across.scaled(-1))), to = screen(centre.plus(across))
        u.stroke(context, u.line(from, to), tint, 0.045)

        // The free end in clay, and the pivot it turns on.
        u.stroke(context, u.line(screen(hoopEnd), screen(tip)), clay, 0.055)
        context.fill(u.circle(screen(tip).0, screen(tip).1, 0.05), with: .color(clay))
        context.fill(u.circle(pivot.x, pivot.y, 0.04), with: .color(tint))
    }
}

/// Newton's rings: seen from above, the fringes round a clay contact spot,
/// crowding together outwards (their radii go as the square roots of 1, 2,
/// 3...). Underneath, a side view: a lens rests on a flat plate, lifts a
/// little and settles back. As it lifts the air gap grows and the rings
/// draw in and vanish into the spot; as it presses down they open out from
/// it again.
enum NewtonsRings {
    static let duration = 4.0

    private static let disc = (x: 0.5, y: 0.36, r: 0.31)
    /// Fringe edges out to the rim: radius goes as the square root, so this
    /// many gives three bright fringes with the dim ones between.
    private static let edges = 6
    /// How many fringes' worth the rings move in as the lens lifts.
    private static let travel = 2.0
    /// The plate's height in the side view, and the lens's size on it.
    private static let plateY = 0.945, lensHalf = 0.25, lensSag = 0.1, hop = 0.06

    /// How far the lens has lifted, 0 resting on the plate to 1 raised.
    private static func lifted(_ t: Double) -> Double {
        Keyframes.value(t, [(0.0, 0), (0.3, 0), (1.5, 1), (2.1, 1), (3.5, 0), (4.0, 0)])
    }

    /// The ring between two radii, in units of the rim's radius.
    private static func band(_ inner: Double, _ outer: Double, in u: UnitSquare) -> Path {
        var path = Path()
        path.addPath(u.circle(disc.x, disc.y, outer * disc.r))
        if inner > 0 { path.addPath(u.circle(disc.x, disc.y, inner * disc.r)) }
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lift = lifted(t)
        let shift: Double = travel * lift
        let rim: Double = Double(edges).squareRoot()

        // Fringes as bands between successive square-root radii, alternating
        // bright and dim, each sliding in as the lens lifts.
        for j in 0...(edges + 2) {
            let inner: Double = max(0, Double(j) - shift).squareRoot() / rim
            let outer: Double = min(rim, max(0, Double(j + 1) - shift).squareRoot()) / rim
            guard outer > inner, inner < 1 else { continue }
            let bright = j % 2 == 1
            context.fill(band(inner, outer, in: u), with: .color(tint.opacity(bright ? 0.95 : 0.3)), style: FillStyle(eoFill: true))
        }
        u.stroke(context, u.circle(disc.x, disc.y, disc.r), tint, 0.035)

        // The contact spot, biggest when the lens is pressed hardest.
        let spot: Double = disc.r * (0.75 + 0.25 * (1 - lift)) / rim
        context.fill(u.circle(disc.x, disc.y, spot), with: .color(clay))

        // The side view: a plate, and a lens with its flat face up and its
        // curved face down, touching it at the middle.
        let apex: Double = plateY - 0.045 - hop * lift
        let top: Double = apex - lensSag
        u.stroke(context, u.line((0.14, plateY), (0.86, plateY)), tint, 0.045)
        var lens = Path()
        lens.move(to: u.pt(0.5 - lensHalf, top))
        lens.addLine(to: u.pt(0.5 + lensHalf, top))
        lens.addQuadCurve(to: u.pt(0.5 - lensHalf, top), control: u.pt(0.5, top + 2 * lensSag))
        lens.closeSubpath()
        context.fill(lens, with: .color(tint.opacity(0.2)))
        u.stroke(context, lens, tint, 0.045)
        context.fill(u.circle(0.5, apex, 0.04), with: .color(clay))
    }
}
