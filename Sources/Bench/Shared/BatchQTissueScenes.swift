// BatchQTissueScenes.swift
// ScienceStatus — tissues reshaping: four cells trading neighbours, a hollow opening in a rosette, an osteoclast digging into bone
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Eases between keyframes (time, value), flat where two values match, so a
/// loop that starts and ends on the same value closes exactly.
private func tissueKeyed(_ t: Double, _ keys: [(Double, Double)]) -> Double {
    guard let first = keys.first, let last = keys.last else { return 0 }
    if t <= first.0 { return first.1 }
    if t >= last.0 { return last.1 }
    for i in 1..<keys.count where t <= keys[i].0 {
        let (t0, v0) = keys[i - 1], (t1, v1) = keys[i]
        return v0 + (v1 - v0) * Ease.inOut((t - t0) / (t1 - t0))
    }
    return last.1
}

/// Neighbour exchange: a patch of four epithelial cells (top, bottom, left,
/// right), irregular polygons inside an uneven border, meeting at a junction. The
/// edge the top and bottom cells share (clay; the pair that touch are shaded
/// darker) shrinks to a point, where all four cells meet at one vertex; it holds
/// there a moment, and a new edge opens at right angles, so now the left and
/// right cells touch. The exchange then runs backwards through the four-way
/// vertex to the start, so the loop closes.
enum NeighborExchange {
    static let duration = 5.0

    private typealias P = (x: Double, y: Double)
    /// The border, fixed while the middle moves: four corners where the arms of
    /// the junction land, and the uneven runs of border between them.
    private static let ul: P = (0.17, 0.30), ur: P = (0.70, 0.17)
    private static let dr: P = (0.84, 0.70), dl: P = (0.33, 0.83)
    private static let topRun: [P] = [(0.40, 0.08)]
    private static let rightRun: [P] = [(0.91, 0.33), (0.95, 0.52)]
    private static let bottomRun: [P] = [(0.62, 0.93)]
    private static let leftRun: [P] = [(0.10, 0.72), (0.06, 0.50)]
    /// The shared edge's longest half length, and the nuclei (top, bottom, left, right).
    private static let half = 0.14
    private static let nuclei: [P] = [(0.44, 0.22), (0.57, 0.78), (0.21, 0.52), (0.79, 0.46)]
    /// How far across (1 horizontal edge, -1 vertical edge) at each moment.
    private static let beats: [(Double, Double)] = [
        (0, 1), (0.3, 1), (1.2, 0), (1.55, 0), (2.45, -1), (2.95, -1), (3.85, 0), (4.1, 0), (5, 1),
    ]

    private static func polygon(_ u: UnitSquare, _ points: [P]) -> Path {
        var path = u.polyline(points.map { ($0.x, $0.y) })
        path.closeSubpath()
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sigma = tissueKeyed(t, beats)
        let h = half * abs(sigma)
        let flat = sigma >= 0
        // The two middle vertices: apart sideways, or one above the other.
        let a: P = flat ? (0.5 - h, 0.5) : (0.5, 0.5 - h)
        let b: P = flat ? (0.5 + h, 0.5) : (0.5, 0.5 + h)

        // The four cells (top, bottom, left, right), each its corners and the
        // run of border between them; the pair that touch are shaded darker.
        let cells: [[P]] = flat
            ? [[ul] + topRun + [ur, b, a], [dr] + bottomRun + [dl, a, b], [ul, a, dl] + leftRun, [ur] + rightRun + [dr, b]]
            : [[ul] + topRun + [ur, a], [dr] + bottomRun + [dl, b], [ul, a, b, dl] + leftRun, [ur] + rightRun + [dr, b, a]]
        let shade: [Double] = [max(sigma, 0), max(sigma, 0), max(-sigma, 0), max(-sigma, 0)]
        for (i, cell) in cells.enumerated() {
            context.fill(polygon(u, cell), with: .color(tint.opacity(0.07 + 0.14 * shade[i])))
        }
        for n in nuclei { context.fill(u.circle(n.x, n.y, 0.034), with: .color(tint)) }

        // Walls: the border, then the four arms of the middle junction.
        u.stroke(context, polygon(u, [ul] + topRun + [ur] + rightRun + [dr] + bottomRun + [dl] + leftRun), tint, 0.06)
        let arms: [(P, P)] = flat ? [(a, ul), (a, dl), (b, ur), (b, dr)] : [(a, ul), (a, ur), (b, dl), (b, dr)]
        var walls = Path()
        for (from, to) in arms { walls.addPath(u.line((from.x, from.y), (to.x, to.y))) }
        u.stroke(context, walls, tint, 0.05)

        // The shared edge, with a dot so the accent holds at the four-way vertex.
        if h > 0.004 { u.stroke(context, u.line((a.x, a.y), (b.x, b.y)), clay, 0.075) }
        context.fill(u.circle(0.5, 0.5, 0.0375), with: .color(clay))
    }
}

/// Lumen formation: a rosette of six wedge-shaped epithelial cells inside a round
/// outline, their walls meeting at a tiny clay dot at the centre. A hollow opens
/// there (the clay disc swells), pushing the cells' pointed ends outwards while
/// their nuclei shift towards the outer side, the whole rosette twisting a
/// little and the outline swelling; it holds open, then the lumen shrinks back
/// to the dot, so the loop closes.
enum LumenFormation {
    static let duration = 5.0

    private static let n = 6
    /// Each wall's angle: sixty degrees apart, nudged so the cells aren't identical.
    private static let nudge: [Double] = [0.07, -0.1, 0.12, -0.06, 0.1, -0.13]
    private static let walls: [Double] = (0..<6).map { (k: Int) -> Double in
        -Double.pi / 2 + Double(k) * Double.pi / 3 + LumenFormation.nudge[k]
    }
    private static let smallest = 0.035, largest = 0.165
    /// How open the lumen is (0 to 1) at each moment.
    private static let beats: [(Double, Double)] = [(0, 0), (0.4, 0), (2.3, 1), (3.0, 1), (4.7, 0), (5, 0)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = tissueKeyed(t, beats)
        let lumen: Double = smallest + (largest - smallest) * open
        let outer: Double = 0.36 + 0.04 * open
        let nucleusRing: Double = 0.21 + 0.09 * open
        let twist: Double = 0.22 * open
        func at(_ angle: Double, _ radius: Double) -> (Double, Double) {
            (0.5 + radius * cos(angle), 0.5 + radius * sin(angle))
        }

        var spokes = Path()
        for k in 0..<n {
            let a0: Double = walls[k] + twist
            let a1: Double = walls[(k + 1) % n] + twist + (k == n - 1 ? 2 * Double.pi : 0)
            // The cell: a wedge from the lumen out to the ring.
            var rim: [(Double, Double)] = []
            for j in 0...6 { rim.append(at(a0 + (a1 - a0) * Double(j) / 6, lumen)) }
            for j in 0...6 { rim.append(at(a1 + (a0 - a1) * Double(j) / 6, outer)) }
            var wedge = u.polyline(rim)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(tint.opacity(0.1)))
            let nucleus = at((a0 + a1) / 2, nucleusRing)
            context.fill(u.circle(nucleus.0, nucleus.1, 0.032), with: .color(tint))
            spokes.addPath(u.line(at(a0, lumen), at(a0, outer)))
        }
        u.stroke(context, spokes, tint, 0.045)
        u.stroke(context, u.circle(0.5, 0.5, outer), tint, 0.05)
        context.fill(u.circle(0.5, 0.5, lumen), with: .color(clay))
    }
}

/// Bone resorption: a side view of a slab of bone, a bold surface line with a
/// light tint below it and a row of slanting hatch marks inside. An osteoclast,
/// a wide dome with three nuclei, sits on the surface, the underside of the dome
/// a ruffled border of three lobes. Beneath the lobes the surface itself is eaten
/// into a scalloped hollow, its edge turning clay, which deepens while the lobes
/// reach down into it. The lobes then draw in and the bone slides off to the
/// left, carrying the pit away while the cell stays, so it moves on along the
/// surface; fresh flat bone slides in under it (the slide is a whole number of
/// hatch marks, so the loop closes).
enum BoneResorption {
    static let duration = 5.0

    private static let surface = 0.46
    /// The pit's extent, its scallops, its greatest depth.
    private static let mouth: (left: Double, right: Double) = (0.25, 0.75)
    private static let scallops = 3
    private static let deepest = 0.17
    private static let slide = 1.35, pitch = 0.225
    /// The dome: half width and height; and where its nuclei sit.
    private static let dome = (rx: 0.32, ry: 0.32)
    private static let nuclei: [(Double, Double)] = [(0.37, 0.33), (0.51, 0.25), (0.63, 0.34)]

    /// The scallop centres, and how deep each is relative to the deepest: the
    /// middle ones deepest, so the pit is a bowl.
    private static let width: Double = 0.5 / 3
    private static let centres: [Double] = (0..<3).map { (k: Int) -> Double in
        0.25 + (Double(k) + 0.5) * 0.5 / 3
    }
    private static let bowl: [Double] = centres.map { (c: Double) -> Double in
        let off: Double = (c - 0.5) / 0.25
        return 1 - 0.5 * off * off
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let ys = surface
        let dig = Ease.inOut((t - 0.35) / 2.1)
        let d: Double = deepest * dig
        let lobes: Double = 1 - Ease.inOut((t - 3.0) / 0.6)
        let moved: Double = slide * Ease.inOut((t - 3.4) / 1.45)
        let seen = Ease.clamp(d / 0.02)

        // The pit: half-ellipse scallops side by side, meeting in cusps at the
        // surface; it travels with the bone.
        var pit: [(Double, Double)] = []
        for k in 0..<scallops {
            for j in 0...8 {
                let w: Double = -1 + 2 * Double(j) / 8
                let x: Double = centres[k] - moved + w * width / 2
                let y: Double = ys + d * bowl[k] * (1 - w * w).squareRoot()
                pit.append((x, y))
            }
        }

        // The bone: a light slab under the surface, whose top edge dips into the pit.
        let gapL = mouth.left - moved, gapR = mouth.right - moved
        let edge = min(-0.3, gapL - 0.05)
        var slab = u.polyline([(edge, ys)] + pit + [(1.3, ys), (1.3, 1.1), (edge, 1.1)])
        slab.closeSubpath()
        context.fill(slab, with: .color(tint.opacity(0.13)))
        var hatch = Path()
        for i in -2...12 {
            let x: Double = 0.11 + pitch * Double(i) - moved
            if x > -0.12 && x < 1.1 { hatch.addPath(u.line((x, 0.72), (x + 0.05, 0.84))) }
        }
        u.stroke(context, hatch, tint, 0.045)

        // The surface line, bold, in two pieces round the pit; the pit's own
        // edge turns from ink to clay as it forms, and the hollow takes a little clay.
        if gapL > -0.3 { u.stroke(context, u.line((-0.3, ys), (gapL, ys)), tint, 0.075) }
        u.stroke(context, u.line((gapR, ys), (1.3, ys)), tint, 0.075)
        if seen < 0.99 { u.stroke(context, u.polyline(pit), tint.opacity(1 - seen), 0.075) }
        if seen > 0.01 {
            var hollow = u.polyline(pit)
            hollow.closeSubpath()
            context.fill(hollow, with: .color(clay.opacity(0.22 * seen)))
            u.stroke(context, u.polyline(pit), clay.opacity(seen), 0.065)
        }

        // The cell: the dome, and underneath it the ruffled border, lobes that
        // reach down into the hollow as it deepens and wave a little.
        var body: [(Double, Double)] = []
        for j in 0...28 {
            let th: Double = Double.pi * (1 - Double(j) / 28)
            body.append((0.5 + dome.rx * cos(th), ys - dome.ry * pow(sin(th), 0.8)))
        }
        var ruffle: [(Double, Double)] = [(mouth.left, ys)]
        var lobeLines = Path()
        for k in 0..<scallops {
            var lobe: [(Double, Double)] = []
            let wave: Double = 1 + 0.14 * sin(2 * Double.pi * 2 * t / duration + 1.7 * Double(k))
            let reach: Double = 0.012 + 0.4 * deepest * dig * bowl[k] * lobes * wave
            for j in 0...8 {
                let w: Double = -1 + 2 * Double(j) / 8
                let point: (Double, Double) = (centres[k] + w * 0.06, ys + reach * (1 - w * w).squareRoot())
                ruffle.append(point)
                lobe.append(point)
            }
            lobeLines.addPath(u.polyline(lobe))
        }
        ruffle.append((mouth.right, ys))
        var cell = u.polyline(body + ruffle.reversed())
        cell.closeSubpath()
        context.fill(cell, with: .color(tint.opacity(0.1)))
        u.stroke(context, u.polyline(body), tint, 0.06)
        // Only the lobes are stroked: between them the hollow is open to the bone.
        u.stroke(context, lobeLines, tint, 0.045)
        for n in nuclei { context.fill(u.circle(n.0, n.1, 0.045), with: .color(tint)) }
    }
}
