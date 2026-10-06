// BatchMJunctionScenes.swift
// ScienceStatus — where cells meet: a gap junction passing small molecules, a
// tight junction holding back dye, a desmosome taking a pull. Each draws in a
// unit square (see `UnitSquare`).

import SwiftUI

/// Gap junction: two whole cells, rounded outlines one above the other, face
/// each other across a narrow gap, their flat facing sides the membranes.
/// Three upright capsules (connexons) stand through both walls, each split
/// down its middle by an open pore. Clay ions fall in single file down three
/// vertical lanes, start inside the upper cell, pass through a pore and fade
/// out inside the lower cell, evenly spaced and endlessly repeating. Part way
/// round the middle pore's walls close on it and the ions above queue; it
/// reopens, they go through in turn, and the lanes are as they began.
enum GapJunction {
    static let duration = 5.5

    private static let upperY = 0.42
    private static let lanes: [Double] = [0.25, 0.5, 0.75]
    /// A connexon: a capsule from `capTop` to `capBottom`, `halfWidth` out
    /// from its axis, with an open pore `openPore` out to each side of it.
    private static let capTop = 0.31, capBottom = 0.69
    private static let halfWidth = 0.085, openPore = 0.027
    private static let dotRadius = 0.031

    private static let ionsPerLane = 4
    /// When each lane's first ion reaches its capsule's top (seconds), staggered.
    private static let phases: [Double] = [0.2, 0.7, 1.15]
    /// Ions appear at `topY` inside the upper cell, fall at one speed and have
    /// faded out by `bottomY` inside the lower.
    private static let topY = 0.115, bottomY = 0.885
    private static let speed = 0.3
    /// The lane that closes, and when: pinching from `closeAt`, shut until
    /// `reopenAt`; the ions held back are let go from `releaseAt`, 0.3 s apart.
    private static let gated = 1
    private static let closeAt = 2.3, reopenAt = 3.9, releaseAt = 4.2
    private static let transit = (capBottom - capTop) / speed

    /// The two walls of a capsule at `cx` with the pore `pore` out to each
    /// side: each wall is the capsule's rounded outline cut along the pore.
    private static func walls(_ u: UnitSquare, cx: Double, pore: Double) -> Path {
        let w = halfWidth
        let domeY = capTop + w
        let rise = sqrt(max(w * w - pore * pore, 0))
        let start = atan2(-rise, -pore)
        var left: [(Double, Double)] = []
        for k in 0...8 {
            let th = start + (-Double.pi - start) * Double(k) / 8
            left.append((cx + w * cos(th), domeY + w * sin(th)))
        }
        // The foot of the capsule mirrors its top.
        left += left.reversed().map { ($0.0, capTop + capBottom - $0.1) }
        var path = Path()
        for side in [1.0, -1.0] {
            path.addLines(left.map { u.pt(cx + side * ($0.0 - cx), $0.1) })
            path.closeSubpath()
        }
        return path
    }

    /// A cell's outline, the upper one or (`lower`) its mirror image: a big
    /// rounded rectangle whose flat facing side is open where the capsules
    /// stand, with a stretch of membrane between each pair of them.
    private static func cell(_ u: UnitSquare, lower: Bool) -> Path {
        let x0 = 0.06, x1 = 0.94, top = 0.05, c = 0.12
        var pts: [(Double, Double)] = []
        func corner(_ cx: Double, _ cy: Double, _ from: Double, _ to: Double) {
            for k in 0...6 {
                let th = from + (to - from) * Double(k) / 6
                pts.append((cx + c * cos(th), cy + c * sin(th)))
            }
        }
        corner(x0 + c, upperY - c, .pi / 2, .pi)
        corner(x0 + c, top + c, .pi, 1.5 * .pi)
        corner(x1 - c, top + c, 1.5 * .pi, 2 * .pi)
        corner(x1 - c, upperY - c, 0, .pi / 2)
        func y(_ v: Double) -> Double { lower ? 1 - v : v }
        var path = u.polyline(pts.map { ($0.0, y($0.1)) })
        for k in 0..<(lanes.count - 1) {
            path.addPath(u.line((lanes[k] + halfWidth + 0.01, y(upperY)), (lanes[k + 1] - halfWidth - 0.01, y(upperY))))
        }
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let pinch = Ease.inOut((t - closeAt) / 0.5) - Ease.inOut((t - reopenAt) / 0.5)

        // The two cells, the membranes their facing sides.
        u.stroke(context, cell(u, lower: false), tint, 0.075)
        u.stroke(context, cell(u, lower: true), tint, 0.075)

        // The connexons; at the gated one the pore's walls close on it.
        for (k, cx) in lanes.enumerated() {
            let pore = k == gated ? openPore * (1 - pinch) - 0.004 * pinch : openPore
            context.fill(walls(u, cx: cx, pore: pore), with: .color(tint))
        }

        // The ions. Each reaches its capsule's top on a fixed beat; at the
        // gated lane, those that come while the pore is closing wait in a
        // queue above it and go through one after another once it opens.
        for (k, cx) in lanes.enumerated() {
            var releases: [Double] = []
            for j in 0..<ionsPerLane {
                let arrive = phases[k] + Double(j) * duration / Double(ionsPerLane)
                var release = arrive
                if k == gated {
                    if arrive > closeAt - transit && arrive < releaseAt { release = releaseAt }
                    if let last = releases.last { release = max(release, last + 0.3) }
                }
                let ahead = releases.filter { $0 > arrive }.count
                releases.append(release)

                // Seconds since it reached the capsule's top, wrapped into this loop.
                let lead = (capTop - topY) / speed
                var w = (t - arrive + lead).truncatingRemainder(dividingBy: duration)
                if w < 0 { w += duration }
                w -= lead

                let delay = release - arrive
                let slot = capTop - 0.07 - 0.068 * Double(ahead)
                var y = capTop + speed * w
                if delay >= 0.001 {
                    if w < delay {
                        y = min(y, slot)
                    } else {
                        // Let go: close the gap to where it would have been, easing out.
                        y = capTop + speed * (w - delay) - (capTop - slot) * (1 - Ease.inOut((w - delay) / 0.5))
                    }
                }
                let alpha = Ease.clamp((y - topY) / 0.05) * Ease.clamp((bottomY - y) / 0.07)
                guard alpha > 0.01 else { continue }
                context.fill(u.circle(cx, y, dotRadius), with: .color(clay.opacity(alpha)))
            }
        }
    }
}

/// Tight junction: three tall cells stand on a baseline with their tops in
/// the lumen above and a thin slit between each pair of neighbours. Clay
/// stitches zip the neighbours' membranes together from the top down, sealing
/// the slit. Dye drifts down from the lumen and settles on the cell tops and
/// in the notches over the seals, but none goes down the slit. Then the dye
/// drifts back up, the stitches unzip, and the cells are as they began.
enum TightJunction {
    static let duration = 5.8

    private static let baseY = 0.9, topY = 0.34
    private static let cellWidth = 0.19, corner = 0.075
    private static let lefts: [Double] = [0.1, 0.405, 0.71]
    private static let stitchYs: [Double] = [0.47, 0.56, 0.65]
    /// How far each membrane leans in at a stitch, and over how much height.
    private static let leanDepth = 0.04, leanSpan = 0.045
    private static let dyeRadius = 0.035

    private static let wallYs: [Double] = stride(from: baseY, through: topY + corner, by: -0.02).map { $0 }

    /// Where each dye particle hangs in the lumen and where it settles: on a
    /// cell's top, or in the notch above a seal, two deep.
    private static let dyeStart: [(Double, Double)] = [
        (0.14, 0.10), (0.30, 0.17), (0.40, 0.07), (0.53, 0.16), (0.60, 0.08), (0.72, 0.18), (0.86, 0.10),
    ]
    private static let dyeEnd: [(Double, Double)] = [
        (0.195, 0.278), (0.3475, 0.385), (0.3475, 0.32), (0.5, 0.278), (0.6525, 0.385), (0.6525, 0.32), (0.805, 0.278),
    ]

    /// How far a wall at height `y` is drawn in towards its neighbour.
    private static func lean(at y: Double, _ zip: [Double]) -> Double {
        var shift = 0.0
        for (k, sy) in stitchYs.enumerated() {
            let s = abs(y - sy) / leanSpan
            if s < 1 { shift += leanDepth * zip[k] * 0.5 * (1 + cos(.pi * s)) }
        }
        return shift
    }

    /// A cell's outline, open at the bottom: up the left wall, over the
    /// rounded top and down the right, each wall pulled in at the stitches.
    private static func outline(_ i: Int, _ zip: [Double]) -> [(Double, Double)] {
        let a = lefts[i], b = a + cellWidth
        let hasLeft = i > 0, hasRight = i < lefts.count - 1
        var pts: [(Double, Double)] = []
        for y in wallYs { pts.append((a + (hasLeft ? lean(at: y, zip) : 0), y)) }
        for step in 1...5 {
            let th = Double.pi * (1 + 0.5 * Double(step) / 5)
            pts.append((a + corner + corner * cos(th), topY + corner + corner * sin(th)))
        }
        for step in 0...4 {
            let th = Double.pi * (1.5 + 0.5 * Double(step) / 5)
            pts.append((b - corner + corner * cos(th), topY + corner + corner * sin(th)))
        }
        for y in wallYs.reversed() { pts.append((b - (hasRight ? lean(at: y, zip) : 0), y)) }
        return pts
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // Each stitch zips in from the top down, and unzips from the bottom up.
        var zip: [Double] = []
        for k in 0..<3 {
            let down = Ease.inOut((t - 0.15 - 0.32 * Double(k)) / 0.5)
            let up = Ease.inOut((t - 4.5 - 0.27 * Double(2 - k)) / 0.45)
            zip.append(down - up)
        }

        u.stroke(context, u.line((0.06, baseY), (0.94, baseY)), tint, 0.05)
        for i in lefts.indices {
            context.fill(u.ellipse(lefts[i] + cellWidth / 2, 0.76, 0.1, 0.15), with: .color(tint.opacity(0.2)))
            u.stroke(context, u.polyline(outline(i, zip)), tint, 0.045)
        }

        // The kissing points: clay across the slit where the membranes meet.
        for i in 0..<(lefts.count - 1) {
            let xc = (lefts[i] + cellWidth + lefts[i + 1]) / 2
            for (k, y) in stitchYs.enumerated() where zip[k] > 0.01 {
                let h = 0.028 * zip[k]
                u.stroke(context, u.line((xc - h, y), (xc + h, y)), clay, 0.05)
            }
        }

        // The dye: hangs in the lumen, settles, and lifts away again.
        for k in dyeStart.indices {
            let down = Ease.inOut((t - 1.0 - 0.1 * Double(k)) / 1.3)
            let up = Ease.inOut((t - 3.3 - 0.08 * Double((k * 3) % 7)) / 1.3)
            let e = down - up
            let from = dyeStart[k], to = dyeEnd[k]
            let phase = 2 * .pi * (2 * t / duration + Double(k) * 0.29)
            let loose = 0.012 - 0.008 * e
            // A sideways bow on the way, so the particles don't fall in straight lines.
            let bow = 0.03 * sin(.pi * e) * (k % 2 == 0 ? 1.0 : -1.0)
            let x = from.0 + (to.0 - from.0) * e + bow + loose * sin(phase)
            let y = from.1 + (to.1 - from.1) * e + loose * cos(phase)
            context.fill(u.circle(x, y, dyeRadius), with: .color(tint))
        }
    }
}

/// Desmosome: two cells meet along a vertical seam, a dense plaque on the
/// inside of each membrane and cadherins bridging the gap to meet and grip
/// along a clay midline. Keratin filaments are hairpin loops, round end out
/// in the cytoplasm and both strands running into the plaque. The cells are
/// pulled apart: each side moves outward, the loops tighten into narrower,
/// straighter U's and the cadherins stretch, but the clay midline holds.
/// Then it all relaxes back.
enum Desmosome {
    static let duration = 5.0

    private static let membraneX = 0.40, pull = 0.04
    private static let hairpinYs: [Double] = [0.34, 0.66]
    private static let cadherinYs: [Double] = [0.34, 0.66]

    /// One keratin loop, drawn on the left: two strands from inside the
    /// plaque out to a round end at `apex`, `gap` across. While there is
    /// slack the strands belly outward.
    private static func hairpin(_ yh: Double, plaqueX: Double, apex: Double, gap: Double, slack: Double) -> [(Double, Double)] {
        let r = gap / 2, bendX = apex + r
        func strand(_ side: Double, _ p: Double) -> (Double, Double) {
            (plaqueX + (bendX - plaqueX) * p, yh + side * (r + 0.012 * slack * sin(.pi * p)))
        }
        var pts: [(Double, Double)] = []
        for k in 0...10 { pts.append(strand(-1, Double(k) / 10)) }
        for k in 1..<8 {
            let th = -Double.pi / 2 - Double.pi * Double(k) / 8
            pts.append((bendX + r * cos(th), yh + r * sin(th)))
        }
        for k in (0...10).reversed() { pts.append(strand(1, Double(k) / 10)) }
        return pts
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tension = Ease.inOut((t - 0.7) / 1.2) - Ease.inOut((t - 3.1) / 1.3)
        let xl = membraneX - pull * tension
        let slack = 1 - tension

        for side in [1.0, -1.0] {
            // The right side is the left one mirrored.
            func mx(_ x: Double) -> Double { side > 0 ? x : 1 - x }
            let xm = mx(xl)
            let plaqueX = xl - 0.07

            context.fill(u.capsule(mx(plaqueX), 0.5, 0.08, 0.62, corner: 0.04), with: .color(tint.opacity(0.7)))
            // The cell body is pulled out further than the plaque, which the
            // cadherins hold back, so the loops are drawn out and narrowed.
            for yh in hairpinYs {
                let pts = hairpin(yh, plaqueX: plaqueX, apex: 0.13 - 0.095 * tension, gap: 0.16 - 0.065 * tension, slack: slack)
                u.stroke(context, u.polyline(pts.map { (mx($0.0), $0.1) }), tint, 0.045)
            }
            u.stroke(context, u.line((xm, 0.08), (xm, 0.92)), tint, 0.055)

            // Cadherins reach in from the membrane to the midline, bowed
            // while slack and straight when stretched.
            var reach = Path()
            for (k, y) in cadherinYs.enumerated() {
                let bow = 0.022 * slack * (k % 2 == 0 ? 1.0 : -1.0)
                reach.move(to: u.pt(xm, y))
                reach.addQuadCurve(to: u.pt(mx(0.515), y), control: u.pt((xm + mx(0.515)) / 2, y + bow))
            }
            u.stroke(context, reach, tint, 0.045)
        }

        // The adhesive core, which does not move.
        u.stroke(context, u.line((0.5, 0.17), (0.5, 0.83)), clay, 0.055)
    }
}
