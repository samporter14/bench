// BatchPCellScenes.swift
// ScienceStatus — cells: an epithelial cell squeezed out of its sheet, a myelin sheath wrapping an axon, a torn membrane patched
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Epithelial extrusion: a side view of a sheet of columnar cells, each with a
/// domed top and a nucleus, standing on a basement line and running off both
/// sides of the square. The middle cell (clay, its nucleus ivory) is crowded: its
/// neighbours lean in over its base, which narrows, and it is pinched up out of
/// the layer as a clay bulb while the neighbours' walls close from the bottom up
/// and seal the surface behind it. Its nucleus fades as the bulb pinches off, and
/// the bare ball drifts off the top of the square. At
/// once the cells to its right begin to slide left by one cell width, and the next
/// cell along narrows, turns clay and is crowded in its turn, just as the first was.
enum EpithelialExtrusion {
    static let duration = 5.0

    private static let ytop = 0.48, ybase = 0.84
    /// A cell's width, and the half width of a crowded cell at its top and at its base.
    private static let pitch = 0.26, topHalf = 0.085, neck = 0.035
    /// How far a cell's top domes up, and a nucleus's radius and height.
    private static let dome = 0.06, nucleus = 0.034, nucleusY = 0.72
    /// The bulb's radii, and how far its centre stands above the sheet when squeezed.
    private static let bulb = (rx: 0.1, ry: 0.095), stand = 0.055
    private static let samples = 12
    /// When the first cell has pinched off and the next one's turn begins.
    private static let pinchedAt = 1.5

    private static func smooth(_ x: Double) -> Double {
        let t = Ease.clamp(x)
        return t * t * (3 - 2 * t)
    }

    /// Half width of the crowded cell at depth `d` (0 at the top of the sheet,
    /// 1 at the basement): `hw` at the top, pinching in towards a base of `neck`
    /// as `squeeze` goes to 1, and closed from the bottom up to a front that
    /// climbs as `pinch` goes to 1.
    private static func halfWidth(at d: Double, hw: Double, squeeze: Double, pinch: Double) -> Double {
        let base = hw + (neck - hw) * squeeze
        let front = 1.35 * (1 - pinch)
        return (hw + (base - hw) * d * d) * smooth((front - d) / 0.35)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let pinched = t >= pinchedAt
        let rise = pow(Ease.clamp((t - 1.4) / 0.9), 2)

        // The crowded cell's slot: where its middle is, how wide it is at the
        // top, how squeezed (s) and pinched shut (p) it is, how clay it is.
        let p: Double, s: Double, centre: Double, hw: Double, fill: Double
        if !pinched {
            p = Ease.inOut((t - 0.15) / 1.35)
            s = 1
            centre = 0.5
            hw = topHalf
            fill = 1
        } else {
            // The next cell: its walls slide left, its right one faster, so it
            // narrows and ends where the first one began.
            let x = Ease.clamp((t - pinchedAt) / 3.5)
            let slide = 1 - (1 - x) * (1 - x)
            let left = 0.5 - topHalf * slide, right = 0.5 + pitch - (pitch - topHalf) * slide
            p = 0
            s = slide
            centre = (left + right) / 2
            hw = (right - left) / 2
            fill = Ease.inOut((t - 1.6) / 1.0)
        }
        func g(_ d: Double) -> Double { halfWidth(at: d, hw: hw, squeeze: s, pinch: p) }
        let top = g(0)
        let xl = centre - top, xr = centre + top

        // The clay: the cell's body between its leaning walls, a short neck,
        // the bulb standing out of the sheet (which pinches off and rises)
        // and the nucleus, which is squeezed up into the bulb.
        let yb = ytop - stand * s - 0.12 * p - (pinched ? 0 : 0.75 * rise)
        let ny = nucleusY + (yb - nucleusY) * smooth(s)
        // The nucleus goes as the bulb pinches off: the free ball is bare clay.
        let kept = 1 - smooth((p - 0.55) / 0.35)
        // The bulb grows as the cell's own domed top gives way to it.
        let grown = Ease.clamp((s - 0.1) / 0.8)
        if fill > 0.01 {
            var tone = context
            tone.opacity = context.opacity * fill
            tone.drawLayer { layer in
                let reach = min(1, 1.35 * (1 - p))
                if reach > 0.02 {
                    var left: [(Double, Double)] = [], right: [(Double, Double)] = []
                    for i in 0...samples {
                        let d = reach * Double(i) / Double(samples)
                        let y = ytop + (ybase - ytop) * d
                        left.append((centre - g(d), y))
                        right.append((centre + g(d), y))
                    }
                    var cell = u.polyline(left + Array(right.reversed()))
                    cell.closeSubpath()
                    layer.fill(cell, with: .color(clay))
                }
                if top > 0.004 && yb < ytop - 0.004 {
                    layer.fill(u.polyline([(xl, ytop + 0.01), (xl, yb), (xr, yb), (xr, ytop + 0.01)]), with: .color(clay))
                }
                if grown > 0.02 && yb > -0.2 {
                    layer.fill(u.ellipse(centre, yb, 2 * bulb.rx * grown, 2 * bulb.ry * grown), with: .color(clay))
                }
                if kept > 0.01 && yb > -0.2 { layer.fill(u.circle(centre, ny, nucleus), with: .color(ivory.opacity(kept))) }
            }
        }
        // Before the cell has turned clay its nucleus is ink, like the rest.
        if fill < 0.99 {
            context.fill(u.circle(centre, ny, nucleus), with: .color(tint.opacity(1 - fill)))
        }
        // The first cell, free of the sheet, rising away.
        let ballY = ytop - stand - 0.12 - 0.75 * rise
        if pinched && ballY > -0.2 {
            context.fill(u.ellipse(0.5, ballY, 2 * bulb.rx, 2 * bulb.ry), with: .color(clay))
        }

        // The sheet: nuclei, walls between the cells (the crowded cell's two
        // leaning ones among them), domed tops and the basement line.
        for j in 0...2 {
            let reach = pitch * (Double(j) + 0.5)
            context.fill(u.circle(xl - reach, nucleusY, nucleus), with: .color(tint))
            context.fill(u.circle(xr + reach, nucleusY, nucleus), with: .color(tint))
        }
        var walls = Path()
        for j in 1...3 {
            let off = pitch * Double(j)
            walls.addPath(u.line((xl - off, ytop), (xl - off, ybase)))
            walls.addPath(u.line((xr + off, ytop), (xr + off, ybase)))
        }
        var leftWall: [(Double, Double)] = [], rightWall: [(Double, Double)] = []
        for i in 0...samples {
            let d = Double(i) / Double(samples)
            let y = ytop + (ybase - ytop) * d
            leftWall.append((centre - g(d), y))
            rightWall.append((centre + g(d), y))
        }
        walls.addPath(u.polyline(leftWall))
        walls.addPath(u.polyline(rightWall))
        u.stroke(context, walls, tint, 0.05)

        func arch(_ a: Double, _ b: Double) -> Path {
            var path = Path()
            path.move(to: u.pt(a, ytop))
            path.addQuadCurve(to: u.pt(b, ytop), control: u.pt((a + b) / 2, ytop - 2 * dome))
            return path
        }
        var lids = Path()
        for j in 0...2 {
            lids.addPath(arch(xl - pitch * Double(j + 1), xl - pitch * Double(j)))
            lids.addPath(arch(xr + pitch * Double(j), xr + pitch * Double(j + 1)))
        }
        u.stroke(context, lids, tint, 0.05)
        if grown < 0.99 && xr - xl > 0.01 {
            u.stroke(context, arch(xl, xr), tint.opacity(1 - grown), 0.05)
        }
        u.stroke(context, u.line((-0.1, ybase), (1.1, ybase)), tint, 0.075)
    }
}

/// Myelin wrapping: an axon in cross-section (a circle) with a glial cell's flat
/// process (clay) wrapping it. The process comes in tangentially from above and
/// its inner edge circles the axon, laying down a spiral that gains turn after
/// turn (about two and three quarters) as the earlier turns are pushed outwards,
/// the sheath thickening. The wrapped axon then slides off to the left and the
/// next, with its process just landing, slides in from the right to take its place.
enum MyelinWrapping {
    static let duration = 5.0

    private static let centre = (x: 0.46, y: 0.54)
    private static let axonRadius = 0.115
    /// Radius of the first turn and the gap between turns.
    private static let inner = 0.18, pitch = 0.08
    /// Where the outer edge of the process leaves the sheath (the right-hand side),
    /// and the turns it has made at the start and when finished.
    private static let rootAngle = -0.17
    private static let first = 0.55, last = 2.75

    /// One axon with its sheath of `turns`, `shift` to the side of its place.
    private static func axon(_ context: GraphicsContext, _ u: UnitSquare, shift: Double, turns: Double, tint: Color) {
        let cx = centre.x + shift, cy = centre.y
        context.fill(u.circle(cx, cy, axonRadius), with: .color(tint.opacity(0.14)))
        u.stroke(context, u.circle(cx, cy, axonRadius), tint, 0.06)

        // The spiral, from the process's outer edge inwards: the angle runs on
        // round the axon while the radius falls by one pitch a turn, so the
        // inner end is the edge that is still circling the axon.
        let total = 2 * Double.pi * turns
        let n = max(8, Int(turns * 90))
        var points: [(Double, Double)] = []
        for k in 0...n {
            let psi = total * Double(k) / Double(n)
            let a = rootAngle + psi
            let rho = inner + pitch * (turns - psi / (2 * .pi))
            points.append((cx + rho * cos(a), cy + rho * sin(a)))
        }
        // The process itself carries on from the outer edge along its tangent
        // and away off the top of the square.
        let rho0 = inner + pitch * turns
        let root = (cx + rho0 * cos(rootAngle), cy + rho0 * sin(rootAngle))
        let heading = (sin(rootAngle), -cos(rootAngle))
        let tail = (root.0 + heading.0 * 0.7, root.1 + heading.1 * 0.7)
        u.stroke(context, u.polyline(points), clay, 0.05)
        u.stroke(context, u.line(root, tail), clay, 0.06)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let wrap = Ease.inOut((t - 0.25) / 3.2)
        let slide = Ease.inOut((t - 3.85) / 1.15)
        // The one before, finished; the one being wrapped; the one waiting.
        axon(context, u, shift: -1 - slide, turns: last, tint: tint)
        axon(context, u, shift: -slide, turns: first + (last - first) * wrap, tint: tint)
        axon(context, u, shift: 1 - slide, turns: first, tint: tint)
    }
}

/// Membrane repair: a cell's membrane, the top of a big circle, is torn open, its
/// two edges frayed and pulled apart. Four clay vesicles drift up from the
/// cytoplasm, line up in the gap and fuse with each other into a patch, a clay
/// stretch of membrane, while the frayed edges draw together and join it. The whole
/// cell then turns about its middle, carrying the patched stretch off to the left
/// and bringing a fresh tear, with its vesicles waiting below, round from the right.
enum MembraneRepair {
    static let duration = 5.0

    private static let radius = 0.95, top = 0.42
    private static let hub = (x: 0.5, y: 0.42 + 0.95)
    /// The angle between one tear and the next.
    private static let turn = 1.3
    /// Half the gap, as an angle, and the membrane's weight.
    private static let halfGap = 0.23, weight = 0.12
    /// The ragged teeth at a torn edge: each spans a part of the membrane's
    /// thickness (`low` to `high` above its middle) and points `reach` (an angle)
    /// into the gap, its tip at `tip` above the middle.
    private static let teeth: [(low: Double, high: Double, reach: Double, tip: Double)] = [
        (-0.06, -0.015, 0.07, -0.045), (-0.03, 0.03, 0.14, 0.0), (0.015, 0.06, 0.09, 0.05),
    ]
    /// Where each vesicle waits (angle from the tear, depth below the membrane)
    /// and the angle between the slots it fuses into.
    private static let waits: [(angle: Double, depth: Double)] = [(-0.3, 0.26), (-0.1, 0.42), (0.1, 0.18), (0.3, 0.36)]
    private static let slotStep = 0.19

    private static func at(_ angle: Double, _ rho: Double) -> (Double, Double) {
        (hub.x + rho * sin(angle), hub.y - rho * cos(angle))
    }

    /// A stretch of membrane from angle `a` to `b`, its ends frayed by `tearA`
    /// and `tearB` (0 whole, 1 fully torn).
    private static func membrane(_ context: GraphicsContext, _ u: UnitSquare, from a: Double, to b: Double,
                                 tearA: Double, tearB: Double, tint: Color) {
        guard b - a > 0.02 else { return }
        // Points on a fixed grid of angles, so a stretch of membrane is drawn
        // the same whichever tears it happens to lie between.
        let step = 0.03
        var angles = [a]
        var k = (a / step).rounded(.down) + 1
        while k * step < b - 0.005 {
            angles.append(k * step)
            k += 1
        }
        angles.append(b)
        u.stroke(context, u.polyline(angles.map { at($0, radius) }), tint, weight)

        // The torn ends: a ragged edge of teeth of uneven length pointing into the gap.
        func point(_ angle: Double, _ rho: Double) -> CGPoint {
            let q = at(angle, rho)
            return u.pt(q.0, q.1)
        }
        for end in [(a, -1.0, tearA), (b, 1.0, tearB)] where end.2 > 0.02 {
            let c = end.2
            let inside = end.0 - end.1 * 0.02
            for tooth in teeth {
                var shard = Path()
                shard.move(to: point(inside, radius + tooth.low))
                shard.addLine(to: point(inside, radius + tooth.high))
                shard.addLine(to: point(end.0 + end.1 * tooth.reach * c, radius + tooth.tip * c))
                shard.closeSubpath()
                context.fill(shard, with: .color(tint))
            }
        }
    }

    /// The vesicles at one tear, at angle `tear`: coming in from `start` and
    /// fused `fuse` of the way into a patch.
    private static func vesicles(_ context: GraphicsContext, _ u: UnitSquare, tear: Double, time t: Double,
                                 start: Double, fuse: Double) {
        var slots: [(Double, Double)] = []
        for (i, w) in waits.enumerated() {
            let slot = at(tear + (Double(i) - 1.5) * slotStep, radius)
            slots.append(slot)
            // They bob where they wait (whole cycles a loop), then come straight in.
            let k = Double(i)
            let wait = at(tear + w.angle, radius - w.depth)
            let bobX = 0.012 * sin(2 * .pi * (1 + k.truncatingRemainder(dividingBy: 2)) * t / duration + 1.3 * k)
            let bobY = 0.012 * cos(2 * .pi * (2 + k.truncatingRemainder(dividingBy: 3)) * t / duration + 0.7 * k)
            let come = Ease.inOut((t - start - 0.2 * k) / 1.3)
            let x = (wait.0 + bobX * (1 - come)) * (1 - come) + slot.0 * come
            let y = (wait.1 + bobY * (1 - come)) * (1 - come) + slot.1 * come
            context.fill(u.circle(x, y, 0.085 - 0.025 * fuse), with: .color(clay))
        }
        // Fusing: the beads join along the membrane into one clay stretch.
        if fuse > 0.02 {
            u.stroke(context, u.polyline(slots), clay, weight * fuse)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fuse = Ease.inOut((t - 2.2) / 0.9)
        let seal = Ease.inOut((t - 2.8) / 0.7)
        let slide = Ease.inOut((t - 3.8) / 1.2)

        // The tear being mended, and the next one coming round.
        let mended = -slide * turn
        let fresh = mended + turn
        // The frayed edges stir a little (whole cycles a loop).
        let open = 1 + 0.12 * sin(2 * .pi * 2 * t / duration)
        let edge = (1 - seal) * open

        // The cell, and its membrane in three stretches between the tears.
        context.fill(u.circle(hub.x, hub.y, radius), with: .color(tint.opacity(0.1)))
        membrane(context, u, from: mended - 1.4, to: mended - halfGap, tearA: 0, tearB: edge, tint: tint)
        membrane(context, u, from: mended + halfGap, to: fresh - halfGap, tearA: edge, tearB: open, tint: tint)
        membrane(context, u, from: fresh + halfGap, to: fresh + 1.4, tearA: open, tearB: 0, tint: tint)

        vesicles(context, u, tear: mended, time: t, start: 0.15, fuse: fuse)
        vesicles(context, u, tear: fresh, time: t, start: 100, fuse: 0)
    }
}
