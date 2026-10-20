// BatchQCellScenes.swift
// ScienceStatus — cells making and moving parts: a megakaryocyte shedding platelets,
// a red cell pushing out its nucleus, a nanotube carrying cargo, a centriole copying itself
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// The square itself, so that things sliding in from outside it are cut off at its edge.
private func clipped(_ context: GraphicsContext, _ u: UnitSquare) -> GraphicsContext {
    var layer = context
    layer.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))
    return layer
}

/// Proplatelets: a big megakaryocyte (ink ring, a faint lobed nucleus) puts out three
/// long wavy arms from stubs, each with a few ink beads along it. A clay bead swells at the
/// tip of each arm; one arm at a time, the bead pinches off through a thinning neck and
/// drifts away, fading, and the arm draws back into the cell, so the loop ends on the stubs
/// it began with.
enum Proplatelets {
    static let duration = 5.0

    private static let cell = (x: 0.27, y: 0.5, r: 0.21)
    /// How much of an arm shows as a bud before it grows (of its full length).
    private static let bud = 0.3
    private static let samples = 18
    /// Each arm: which way it leaves the cell (degrees, clockwise on screen), how far it
    /// reaches and how it wavers, when it starts growing and when its bead pinches off.
    private static let arms: [(angle: Double, reach: Double, bow: Double, grows: Double, parts: Double)] = [
        (-44, 0.37, 0.04, 0.15, 2.2), (3, 0.42, -0.04, 0.0, 2.55), (46, 0.35, 0.04, 0.3, 2.9),
    ]
    /// Where the ink beads sit along an arm (of its full length).
    private static let beads = [0.38, 0.68]

    /// A point `s` of the way along arm `a` (0 at the cell, 1 at its tip).
    private static func point(_ a: Int, _ s: Double) -> (Double, Double) {
        let arm = arms[a]
        let th = arm.angle * .pi / 180
        let dx = cos(th), dy = sin(th)
        let wave = arm.bow * sin(2 * .pi * s)
        let sx = cell.x + 0.9 * cell.r * dx, sy = cell.y + 0.9 * cell.r * dy
        return (sx + dx * arm.reach * s - dy * wave, sy + dy * arm.reach * s + dx * wave)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = clipped(context, u)

        // The nucleus: two overlapping lobes, faint.
        var nucleus = Path()
        nucleus.addPath(u.circle(cell.x - 0.04, cell.y - 0.035, 0.075))
        nucleus.addPath(u.circle(cell.x + 0.035, cell.y + 0.05, 0.065))
        layer.fill(nucleus, with: .color(tint.opacity(0.28)))

        for (a, arm) in arms.enumerated() {
            let grow = Ease.inOut((t - arm.grows - 0.1) / 1.9)
            let draw = Ease.inOut((t - arm.parts - 0.25) / 1.7)
            let f = bud + (1 - bud) * grow * (1 - draw)

            u.stroke(layer, u.polyline((0...samples).map { point(a, f * Double($0) / Double(samples)) }), tint, 0.055)
            for s in beads where f > s + 0.02 {
                let p = point(a, s)
                layer.fill(u.circle(p.0, p.1, 0.04 * Ease.clamp((f - s) / 0.12)), with: .color(tint))
            }

            // The tip bead swells with the arm, then leaves along the arm's heading,
            // curving toward the right; a neck of ink stretches and thins behind it.
            let swell = 0.054 * Ease.clamp((grow - 0.4) / 0.5)
            let tip = point(a, 1)
            if t < arm.parts {
                let p = point(a, f)
                layer.fill(u.circle(p.0, p.1, swell), with: .color(clay))
            } else {
                let x = (t - arm.parts) / 1.8
                let heading = arm.angle * 0.55 * .pi / 180
                let away = 0.26 * Ease.inOut(x)
                let p = (tip.0 + cos(heading) * away, tip.1 + sin(heading) * away)
                let alpha = 1 - Ease.inOut((t - arm.parts - 0.9) / 1.2)
                if x < 0.4 {
                    u.stroke(layer, u.line(tip, p), tint, 0.05 * (1 - x / 0.4))
                }
                if alpha > 0 {
                    layer.fill(u.circle(p.0, p.1, swell), with: .color(clay.opacity(alpha)))
                }
            }
        }

        u.stroke(layer, u.circle(cell.x, cell.y, cell.r), tint, 0.075)
    }
}

/// Enucleation: an erythroblast (ink ring, clay nucleus in the middle) shifts its nucleus
/// to one side, which shrinks a little and takes a thin ink membrane around itself. The
/// package pushes out through the cell's wall, the wall closing behind it, and drifts off
/// to the right, leaving a round cell with a faint dimple at its middle. Then the whole
/// row slides left, the old cell and its package leaving the square as a new erythroblast
/// comes in from the right to take the first one's place.
enum Enucleation {
    static let duration = 5.0

    private static let cx = 0.33, cy = 0.5, radius = 0.26
    /// The package's ring and the nucleus inside it, and the row's spacing.
    private static let ring = 0.14, ringWeight = 0.035, pitch = 1.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = clipped(context, u)

        let shift = Ease.inOut((t - 0.4) / 1.0)
        let leave = Ease.inOut((t - 1.4) / 1.6)
        let wrapped = Ease.clamp((t - 0.9) / 0.5)
        let dimple = Ease.inOut((t - 3.0) / 0.7)
        let slide = Ease.inOut((t - 3.9) / 1.0)
        let nucleus = 0.105 - 0.015 * Ease.inOut((t - 1.0) / 1.0)
        let off = 0.06 * shift + 0.44 * leave
        let x0 = cx - pitch * slide

        // The first cell. Its wall stops at the package's edge while the two overlap,
        // and closes up as the package goes.
        let px = x0 + off
        var outline = layer
        if wrapped > 0 {
            var hole = Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side))
            hole.addPath(u.circle(px, cy, ring + ringWeight / 2))
            outline.clip(to: hole, style: FillStyle(eoFill: true))
        }
        u.stroke(outline, u.circle(x0, cy, radius), tint, 0.075)
        u.stroke(layer, u.circle(x0, cy, 0.12), tint.opacity(0.5 * dimple), 0.04)

        layer.fill(u.circle(px, cy, nucleus), with: .color(clay))
        u.stroke(layer, u.circle(px, cy, ring), tint.opacity(wrapped), ringWeight)

        // The next cell, coming in from the right.
        let x1 = cx + pitch - pitch * slide
        u.stroke(layer, u.circle(x1, cy, radius), tint, 0.075)
        layer.fill(u.circle(x1, cy, 0.105), with: .color(clay))
    }
}

/// Tunneling nanotube: two cells, each faintly filled, joined by one thin tube of
/// membrane. A clay cargo vesicle sits in the left cell, slips out into the tube, slides
/// along it a little wider than the tube itself, and enters the right cell, where it is
/// released and shrinks away; as it goes, a new cargo grows in the left cell where the
/// first began, so the loop ends as it started.
enum TunnelingNanotube {
    static let duration = 5.0

    private static let left = (x: 0.22, y: 0.6, r: 0.17)
    private static let right = (x: 0.78, y: 0.4, r: 0.17)
    private static let tubeWeight = 0.04, cargo = 0.06

    /// Where the tube leaves each cell and the curve between, bowed a little upward.
    private static let mouth: ((Double, Double), (Double, Double)) = {
        let dx = right.x - left.x, dy = right.y - left.y
        let d = hypot(dx, dy)
        return ((left.x + dx / d * left.r, left.y + dy / d * left.r),
                (right.x - dx / d * right.r, right.y - dy / d * right.r))
    }()
    private static let bow = (x: 0.47, y: 0.43)

    private static func tube(_ s: Double) -> (Double, Double) {
        let a = (1 - s) * (1 - s), b = 2 * (1 - s) * s, c = s * s
        return (a * mouth.0.0 + b * bow.x + c * mouth.1.0, a * mouth.0.1 + b * bow.y + c * mouth.1.1)
    }

    private static let begin = (x: left.x - 0.03, y: left.y + 0.02)
    private static let end = (x: right.x + 0.03, y: right.y - 0.02)

    /// The cargo's whole route as a polyline: from its place in the left cell, through
    /// the mouth, along the tube, and in to its place in the right cell.
    private static let route: [(Double, Double)] = {
        var points: [(Double, Double)] = [(begin.x, begin.y), mouth.0]
        for i in 1..<24 { points.append(tube(Double(i) / 24)) }
        points.append(mouth.1)
        points.append((end.x, end.y))
        return points
    }()
    private static let lengths: [Double] = {
        var sums = [0.0]
        for i in 1..<route.count {
            sums.append(sums[i - 1] + hypot(route[i].0 - route[i - 1].0, route[i].1 - route[i - 1].1))
        }
        return sums
    }()

    /// The point `q` (0 to 1) of the way along the route, by length.
    private static func along(_ q: Double) -> (Double, Double) {
        let target = lengths[lengths.count - 1] * Ease.clamp(q)
        var i = 1
        while i < lengths.count - 1 && lengths[i] < target { i += 1 }
        let span = max(lengths[i] - lengths[i - 1], 0.0001)
        let f = (target - lengths[i - 1]) / span
        return (route[i - 1].0 + (route[i].0 - route[i - 1].0) * f, route[i - 1].1 + (route[i].1 - route[i - 1].1) * f)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        context.fill(u.circle(left.x, left.y, left.r), with: .color(tint.opacity(0.14)))
        context.fill(u.circle(right.x, right.y, right.r), with: .color(tint.opacity(0.14)))

        var tubePath = Path()
        tubePath.move(to: u.pt(mouth.0.0, mouth.0.1))
        tubePath.addQuadCurve(to: u.pt(mouth.1.0, mouth.1.1), control: u.pt(bow.x, bow.y))
        u.stroke(context, tubePath, tint, tubeWeight)
        u.stroke(context, u.circle(left.x, left.y, left.r), tint, 0.06)
        u.stroke(context, u.circle(right.x, right.y, right.r), tint, 0.06)

        // The first cargo crosses; the new one grows where it started as it is released.
        let q = Ease.inOut((t - 0.5) / 3.0)
        let release = Ease.inOut((t - 3.5) / 0.7)
        let fresh = Ease.out((t - 3.7) / 0.7)
        let p = along(q)
        context.fill(u.circle(p.0, p.1, cargo * (1 - release)), with: .color(clay))
        if fresh > 0 {
            context.fill(u.circle(begin.x, begin.y, cargo * fresh), with: .color(clay))
        }
    }
}

/// Centriole duplication: a mother centriole, a chunky barrel drawn as an ink outline with a
/// faint fill and a short line near each end, lies flat. A daughter barrel in clay, drawn the
/// same way, grows out of the mother's side near her left end at a right angle until it is
/// nearly as long as she is, and holds, so the two make an L. Then the daughter lifts clear,
/// tips away to the left about her foot and fades, leaving the mother alone in the pose
/// she began in.
enum CentrioleDuplication {
    static let duration = 5.0

    private static let weight = 0.07
    /// The mother's outer size and place, the daughter's outer width and how far she
    /// finally stands above the mother's top edge.
    private static let mother = (x: 0.5, y: 0.73, w: 0.64, h: 0.26)
    private static let daughter = (x: 0.34, w: 0.24, reach: 0.5)
    /// How far the daughter's foot starts inside the mother.
    private static let sunk = 0.05

    /// A barrel's body: a faint fill and the outline, `w` by `h` outside.
    private static func body(_ context: GraphicsContext, _ u: UnitSquare, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                             ink: Color) {
        let shape = u.capsule(x, y, w - weight, h - weight, corner: 0.06)
        context.fill(shape, with: .color(ink.opacity(0.4)))
        u.stroke(context, shape, ink, weight)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = clipped(context, u)

        let grow = Ease.inOut((t - 0.1) / 2.4)
        let a = Ease.inOut((t - 3.0) / 1.6)

        // The daughter first, so that the mother is drawn over her foot: she is cut off
        // at the mother's outer edge while she stands in it.
        let foot = mother.y - mother.h / 2 + sunk
        let length = (daughter.reach + sunk - weight / 2) * grow
        if length > 0.03 && a < 1 {
            var d = layer
            var cut = Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side))
            cut.addPath(u.capsule(mother.x, mother.y, mother.w, mother.h, corner: 0.09))
            d.clip(to: cut, style: FillStyle(eoFill: true))
            d.opacity = 1 - Ease.inOut((a - 0.45) / 0.55)
            // Lift clear first, then tip away about the foot.
            let lift = -0.12 * Ease.clamp(a / 0.35)
            let pivot = u.pt(daughter.x, foot + lift)
            d.translateBy(x: -0.04 * a * u.side, y: lift * u.side)
            d.translateBy(x: pivot.x, y: pivot.y - lift * u.side)
            d.rotate(by: .degrees(-38 * Ease.inOut((a - 0.2) / 0.8)))
            d.translateBy(x: -pivot.x, y: -(pivot.y - lift * u.side))

            body(d, u, daughter.x, foot - length / 2, daughter.w, length + weight, ink: clay)
            let marks = Ease.clamp((length - 0.3) / 0.1)
            if marks > 0 {
                var ticks = Path()
                for y in [foot - length + 0.1, foot - 0.17] {
                    ticks.addPath(u.line((daughter.x - 0.045, y), (daughter.x + 0.045, y)))
                }
                u.stroke(d, ticks, clay.opacity(0.85 * marks), 0.035)
            }
        }

        body(layer, u, mother.x, mother.y, mother.w, mother.h, ink: tint)
        var ends = Path()
        for side in [-1.0, 1.0] {
            let x = mother.x + side * (mother.w / 2 - 0.12)
            ends.addPath(u.line((x, mother.y - 0.045), (x, mother.y + 0.045)))
        }
        u.stroke(layer, ends, tint.opacity(0.85), 0.035)
    }
}
