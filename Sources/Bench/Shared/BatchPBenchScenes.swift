// BatchPBenchScenes.swift
// ScienceStatus — at the bench: laser capture microdissection, fishing a crystal from its drop, embedding tissue in paraffin
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Odds and ends the three scenes below share.
private enum BPKit {
    /// `Ease.inOut` over the window `from...to`: 0 before it, 1 after.
    static func step(_ t: Double, _ from: Double, _ to: Double) -> Double { Ease.inOut((t - from) / (to - from)) }

    /// A straight run over the window `from...to`: 0 before it, 1 after.
    static func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double { Ease.clamp((t - from) / (to - from)) }

    /// The closed shape through `points`, for filling.
    static func polygon(_ u: UnitSquare, _ points: [(Double, Double)]) -> Path {
        var path = u.polyline(points)
        path.closeSubpath()
        return path
    }

    /// A point turned about the origin by `angle` radians, clockwise on screen.
    static func turn(_ p: (Double, Double), by angle: Double) -> (Double, Double) {
        let c = cos(angle), s = sin(angle)
        return (p.0 * c - p.1 * s, p.0 * s + p.1 * c)
    }

    /// The scene's own square, so what slides in and out of it stops at the edge.
    static func clipped(_ context: GraphicsContext, _ u: UnitSquare) -> GraphicsContext {
        var layer = context
        layer.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))
        return layer
    }
}

/// Laser capture: a tissue section lies on a slide, a few cells to each patch,
/// with a collection cap above it. A clay laser spot traces a closed cut round
/// the three cells under it, the cut piece fills clay and lifts off the slide
/// into the cap, and then slide and cap rack shuffle along together by one
/// patch, so the next patch is under the beam and the cut one, its hole
/// outlined, slides away to the left with its cap.
enum LaserCapture {
    static let duration = 5.0

    /// How far the slide moves between cuts, and the row the patches sit on.
    private static let pitch = 0.66, rowY = 0.69
    /// Where the cut piece comes to rest inside its cap, and how small it gets.
    private static let chipY = 0.225, chipScale = 0.42
    private static let appear = 0.3, traceStart = 0.55, traceEnd = 2.3
    private static let liftStart = 2.55, liftEnd = 3.3
    private static let slideStart = 3.55, slideEnd = 4.6

    /// The cut: a slightly lumpy ring round the patch's middle, starting at the top.
    private static let ring: [(Double, Double)] = (0..<48).map { (i: Int) -> (Double, Double) in
        let a: Double = -Double.pi / 2 + Double(i) * 2 * Double.pi / 48
        let r: Double = 0.15 + 0.012 * sin(3 * a + 0.5)
        return (r * cos(a), 0.95 * r * sin(a))
    }
    /// The three cells inside it, and the cells that sit between patches.
    private static let patchCells: [(dx: Double, dy: Double, w: Double, h: Double)] = [
        (-0.058, 0.045, 0.1, 0.092), (0.06, 0.04, 0.095, 0.1), (0.0, -0.062, 0.1, 0.09),
    ]
    private static let fillerCells: [(dx: Double, dy: Double, w: Double, h: Double)] = [
        (0.3, -0.07, 0.09, 0.085), (0.36, 0.09, 0.085, 0.09),
    ]

    /// The cut as far as the laser has got, `q` of the way round: the ring up to
    /// the point it has reached, which is the last point returned.
    private static func traced(_ q: Double) -> [(Double, Double)] {
        let n = ring.count
        if q >= 1 { return ring + [ring[0]] }
        let f = q * Double(n)
        let k = min(n - 1, Int(f))
        let m = f - Double(k)
        let a = ring[k], b = ring[(k + 1) % n]
        return Array(ring[0...k]) + [(a.0 + (b.0 - a.0) * m, a.1 + (b.1 - a.1) * m)]
    }

    /// The cut piece of the patch centred at (x, y), `scale` of its true size.
    private static func piece(_ context: GraphicsContext, _ u: UnitSquare, x: Double, y: Double, scale: Double, fill: Double) {
        let outline = BPKit.polygon(u, ring.map { (x + scale * $0.0, y + scale * $0.1) })
        context.fill(outline, with: .color(clay.opacity(fill)))
        u.stroke(context, outline, clay, 0.045 * (0.5 + 0.5 * scale))
        // The cells show through only while the piece is big enough to hold them.
        let shown = fill * Ease.clamp((scale - 0.55) / 0.35)
        guard shown > 0.02 else { return }
        for c in patchCells {
            u.stroke(context, u.ellipse(x + scale * c.dx, y + scale * c.dy, scale * c.w, scale * c.h), ivory.opacity(shown), 0.03)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = BPKit.clipped(context, u)

        let shift = pitch * BPKit.step(t, slideStart, slideEnd)
        let lift = BPKit.step(t, liftStart, liftEnd)
        let q = 0.5 * BPKit.ramp(t, traceStart, traceEnd) + 0.5 * BPKit.step(t, traceStart, traceEnd)
        let patches = Array(-2...2)
        // Patch j is the one that is under the beam when j = 0 and the slide is at rest.
        func centre(_ j: Int) -> Double { 0.5 + pitch * Double(j) - shift }
        func isCut(_ j: Int) -> Bool { j < 0 || (j == 0 && t >= liftStart) }

        // The tissue, with the cut patches taken out of it.
        var holes = Path()
        for j in patches where isCut(j) {
            holes.addPath(BPKit.polygon(u, ring.map { (centre(j) + $0.0, rowY + $0.1) }))
        }
        var tissue = layer
        if !holes.isEmpty { tissue.clip(to: holes, options: .inverse) }
        tissue.fill(BPKit.polygon(u, [(-0.1, 0.53), (1.1, 0.53), (1.1, 0.85), (-0.1, 0.85)]), with: .color(tint.opacity(0.13)))
        for j in patches {
            let x = centre(j)
            guard x > -0.4, x < 1.4 else { continue }
            for c in fillerCells {
                u.stroke(tissue, u.ellipse(x + c.dx, rowY + c.dy, c.w, c.h), tint.opacity(0.3), 0.035)
            }
            if !isCut(j) {
                for c in patchCells { u.stroke(tissue, u.ellipse(x + c.dx, rowY + c.dy, c.w, c.h), tint.opacity(0.85), 0.04) }
            }
        }

        // The slide's long edges (the lower one faint), and the cut edge left round each hole.
        u.stroke(layer, u.line((-0.05, 0.46), (1.05, 0.46)), tint, 0.032)
        u.stroke(layer, u.line((-0.05, 0.92), (1.05, 0.92)), tint.opacity(0.3), 0.04)
        for j in patches where isCut(j) {
            let edge = j < 0 ? 1.0 : BPKit.ramp(t, liftStart, liftStart + 0.2)
            u.stroke(layer, BPKit.polygon(u, ring.map { (centre(j) + $0.0, rowY + $0.1) }), tint.opacity(0.6 * edge), 0.035)
        }

        // The cut being made: a clay line following the spot round the cells.
        let cut = traced(q)
        if t > traceStart, t < traceEnd { u.stroke(layer, u.polyline(cut.map { (centre(0) + $0.0, rowY + $0.1) }), clay, 0.05) }

        // Cut pieces: the one just made lifts into its cap, earlier ones sit in theirs.
        for j in patches {
            let x = centre(j)
            guard x > -0.4, x < 1.4, j < 0 || (j == 0 && t >= traceEnd) else { continue }
            let rise = j < 0 ? 1.0 : lift
            let fill = j < 0 ? 1.0 : BPKit.ramp(t, traceEnd, traceEnd + 0.2)
            piece(layer, u, x: x, y: rowY + (chipY - rowY) * rise, scale: 1 + (chipScale - 1) * rise, fill: fill)
        }

        // The laser spot: a clay dot in a pulsing ring, at the end of the cut.
        let spot = BPKit.step(t, appear, appear + 0.25) * (1 - BPKit.ramp(t, traceEnd, traceEnd + 0.2))
        if spot > 0.05, let tip = cut.last {
            let at = (centre(0) + tip.0, rowY + tip.1)
            layer.fill(u.circle(at.0, at.1, 0.045 * spot), with: .color(clay))
            u.stroke(layer, u.circle(at.0, at.1, (0.088 + 0.012 * sin(t * 2 * Double.pi * 4)) * spot), clay.opacity(0.6), 0.03)
        }

        // The cap rack above the slide, one cap over each patch.
        for j in patches {
            let x = centre(j)
            guard x > -0.4, x < 1.4 else { continue }
            u.stroke(layer, u.line((x - 0.13, 0.3), (x - 0.13, 0.13), (x + 0.13, 0.13), (x + 0.13, 0.3)), tint, 0.05)
        }
    }
}

/// Crystal fishing: a drop on its plate, seen from above, holds four small
/// crystals, one of them clay. A nylon loop on a pin swings in from the upper
/// right, dips round the clay crystal (a ripple spreads), then lifts it out of
/// the drop and away off the corner. The plate shifts along: the picked drop
/// leaves to the left and the next one, with its crystals, slides in as the
/// loop returns to where it began.
enum CrystalFishing {
    static let duration = 5.0

    private static let dropAt = (x: 0.42, y: 0.6), dropR = 0.33, pitch = 1.0
    private static let rest = (x: 0.85, y: 0.21)
    /// The far end of the pin, out beyond the corner; the loop's stem always points at it.
    private static let pivot = (x: 1.2, y: -0.3)
    private static let loopR = 0.115
    /// Crystals: centre relative to the drop's, size, number of sides (6 hexagon, 4 diamond), turn.
    private static let target: (dx: Double, dy: Double, r: Double) = (0.08, -0.02, 0.065)
    private static let others: [(dx: Double, dy: Double, r: Double, sides: Int, turn: Double)] = [
        (-0.14, -0.13, 0.08, 4, 0.35), (-0.13, 0.12, 0.06, 6, 0.2), (0.08, 0.2, 0.05, 4, -0.5),
    ]
    private static let dipAt = 1.35, grabAt = 1.95, liftEnd = 3.2, backStart = 3.7

    private static func outline(_ u: UnitSquare, x: Double, y: Double, r: Double, sides: Int, turn: Double) -> Path {
        let pts: [(Double, Double)] = (0..<sides).map { (k: Int) -> (Double, Double) in
            let a: Double = turn + Double.pi / 2 + Double(k) * 2 * Double.pi / Double(sides)
            let stretch: Double = sides == 4 ? (k % 2 == 0 ? 1 : 0.62) : 1
            return (x + r * stretch * cos(a), y - r * stretch * sin(a))
        }
        return BPKit.polygon(u, pts)
    }

    /// The loop's centre and its apparent size: in from the corner, down into
    /// the drop (it gets smaller going away), up (larger, coming close) and out,
    /// then back to the corner.
    private static func loop(_ t: Double) -> (x: Double, y: Double, scale: Double) {
        let tx = dropAt.x + target.dx, ty = dropAt.y + target.dy
        if t < 3.4 {
            let come = BPKit.step(t, 0.3, dipAt)
            let away = BPKit.step(t, 2.05, liftEnd)
            let scale = 1 - 0.14 * BPKit.step(t, dipAt, 1.8) + 0.42 * BPKit.step(t, 2.05, 2.75)
            let hx = rest.x + (tx - rest.x) * come, hy = rest.y + (ty - rest.y) * come
            return (hx + (1.3 - hx) * away, hy + (-0.2 - hy) * away, scale)
        }
        let back = BPKit.step(t, backStart, 4.75)
        return (1.3 + (rest.x - 1.3) * back, -0.2 + (rest.y + 0.2) * back, 1)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = BPKit.clipped(context, u)
        let shift = pitch * BPKit.step(t, 2.85, 3.85)
        let grabbed = t >= grabAt

        // Two drops on the plate: the one being fished, and the next in line.
        for j in 0...1 {
            let x = dropAt.x + pitch * Double(j) - shift
            guard x > -0.4, x < 1.4 else { continue }
            layer.fill(u.circle(x, dropAt.y, dropR), with: .color(tint.opacity(0.1)))
            u.stroke(layer, u.circle(x, dropAt.y, dropR), tint, 0.06)
            for c in others {
                u.stroke(layer, outline(u, x: x + c.dx, y: dropAt.y + c.dy, r: c.r, sides: c.sides, turn: c.turn), tint, 0.035)
            }
            if !(j == 0 && grabbed) {
                let shape = outline(u, x: x + target.dx, y: dropAt.y + target.dy, r: target.r, sides: 6, turn: 0.15)
                layer.fill(shape, with: .color(clay))
                u.stroke(layer, shape, clay, 0.02)
            }
        }

        // Ripples spreading from where the loop goes in.
        for k in 0..<2 {
            let p = BPKit.ramp(t, dipAt + 0.05 + 0.3 * Double(k), dipAt + 1.0 + 0.3 * Double(k))
            guard p > 0, p < 1 else { continue }
            let x = dropAt.x + target.dx - shift, y = dropAt.y + target.dy
            u.stroke(layer, u.circle(x, y, 0.1 + 0.15 * p), tint.opacity(0.6 * (1 - p)), 0.03)
        }

        // The loop on its pin: the stem always points to the pin's far end.
        let c = loop(t)
        let dx = pivot.x - c.x, dy = pivot.y - c.y
        let d = max(hypot(dx, dy), 0.0001)
        let r = loopR * c.scale
        let film = BPKit.step(t, dipAt + 0.3, 1.85) * (1 - BPKit.ramp(t, 3.0, 3.2))
        if film > 0.01 { layer.fill(u.circle(c.x, c.y, r), with: .color(tint.opacity(0.16 * film))) }
        if grabbed, t < 3.45 {
            let shape = outline(u, x: c.x, y: c.y, r: target.r * c.scale / 0.86, sides: 6, turn: 0.15)
            layer.fill(shape, with: .color(clay))
            u.stroke(layer, shape, clay, 0.02)
        }
        u.stroke(layer, u.line((c.x + r * dx / d, c.y + r * dy / d), (pivot.x, pivot.y)), tint, 0.04)
        u.stroke(layer, u.circle(c.x, c.y, r), tint, 0.04)
    }
}

/// Paraffin embedding: a metal mould with a flat piece of clay tissue on its
/// floor. A cup of molten paraffin tips over it and the wax level rises round
/// the tissue; the cup swings away, a cassette is pressed on top, the wax sets,
/// and the block, tissue inside, lifts out under the cassette. It slides off
/// to the left above its emptied mould while a fresh mould, tissue in place,
/// slides in under the cup as it comes back.
enum ParaffinEmbedding {
    static let duration = 5.6

    private static let pitch = 1.0
    /// The mould's walls (line centres) and its floor, and the inner faces and bed the wax fills.
    private static let wallL = 0.22, wallR = 0.78, rimY = 0.58, floorY = 0.84
    private static let faceL = 0.255, faceR = 0.745, bedY = 0.808, fullY = 0.605
    private static let tissueY = 0.77
    /// The pouring cup's lip, which it turns about, and its outline when upright.
    private static let lip = (x: 0.33, y: 0.27)
    private static let cup: [(Double, Double)] = [(-0.21, -0.02), (-0.18, 0.2), (-0.03, 0.2), (0.0, 0.0)]
    private static let outBy = 0.3
    private static let tipStart = 0.2, pourStart = 0.45, fillStart = 0.6, fillEnd = 2.0
    private static let cassetteIn = 2.3, cassetteSeat = 3.0, setStart = 3.15, setEnd = 3.65
    private static let liftStart = 3.7, liftEnd = 4.3, slideStart = 4.4, slideEnd = 5.3

    /// The paraffin's top at time `t`.
    private static func level(_ t: Double) -> Double { bedY - (bedY - fullY) * BPKit.ramp(t, fillStart, fillEnd) }

    private static func mould(_ context: GraphicsContext, _ u: UnitSquare, x: Double, tint: Color) {
        let tray = u.line((x - 0.34, rimY), (x - 0.28, rimY), (x - 0.28, floorY), (x + 0.28, floorY), (x + 0.28, rimY), (x + 0.34, rimY))
        u.stroke(context, tray, tint, 0.065)
    }

    private static func tissue(_ context: GraphicsContext, _ u: UnitSquare, x: Double, y: Double) {
        context.fill(u.capsule(x, y, 0.21, 0.08, corner: 0.04), with: .color(clay))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = BPKit.clipped(context, u)
        let slide = BPKit.step(t, slideStart, slideEnd)
        let here = -pitch * slide                    // how far the mould being filled has moved from centre
        let next = pitch * (1 - slide)               // the fresh one coming in
        let lift = BPKit.step(t, liftStart, liftEnd)

        // The bench the moulds slide along, and the fresh mould with its tissue.
        u.stroke(layer, u.line((-0.05, 0.935), (1.05, 0.935)), tint, 0.04)
        mould(layer, u, x: 0.5 + next, tint: tint)
        tissue(layer, u, x: 0.5 + next, y: tissueY)

        // The mould being filled.
        let x = 0.5 + here
        mould(layer, u, x: x, tint: tint)
        let top = level(t)
        let up = -outBy * lift              // how far the block has been lifted
        let cool = BPKit.ramp(t, setStart, setEnd)
        let pouring = min(BPKit.ramp(t, fillStart - 0.05, fillStart + 0.1), 1 - BPKit.ramp(t, fillEnd - 0.1, fillEnd + 0.2))

        if top < bedY - 0.002 {
            layer.fill(BPKit.polygon(u, [(x + faceL - 0.5, top + up), (x + faceR - 0.5, top + up), (x + faceR - 0.5, bedY + up), (x + faceL - 0.5, bedY + up)]),
                       with: .color(tint.opacity(0.14 + 0.16 * cool)))
            let wave: [(Double, Double)] = (0...12).map { (i: Int) -> (Double, Double) in
                let f = Double(i) / 12
                return (x + faceL - 0.5 + (faceR - faceL) * f, top + up + 0.008 * pouring * sin(f * 30 + t * 14))
            }
            u.stroke(layer, u.polyline(wave), tint.opacity(0.8), 0.035)
        }
        // The block's own edges, once it has left the mould's walls.
        if lift > 0.05 {
            let sides = u.line((x + faceL - 0.5, top + up), (x + faceL - 0.5, bedY + up), (x + faceR - 0.5, bedY + up), (x + faceR - 0.5, top + up))
            u.stroke(layer, sides, tint.opacity(Ease.clamp(lift * 3)), 0.045)
        }
        tissue(layer, u, x: x, y: tissueY + up)

        // The cassette comes in from the upper right, is pressed home and goes with the block.
        let come = BPKit.step(t, cassetteIn, cassetteSeat)
        if come > 0.001 {
            let press = 0.012 * BPKit.step(t, cassetteSeat, cassetteSeat + 0.15)
            let cx = x + 0.45 * (1 - come), cy = 0.5 - 0.5 * (1 - come) + press + up
            let body = u.capsule(cx, cy, 0.44, 0.145, corner: 0.025)
            u.stroke(layer, body, tint, 0.05)
            for dx in [-0.07, 0.0, 0.07] {
                u.stroke(layer, u.line((cx + dx, cy - 0.025), (cx + dx, cy + 0.025)), tint, 0.035)
            }
        }

        // The cup tips over its lip and the stream drops in, stands, and is cut off;
        // then the cup rights itself and swings away up and to the left.
        let tip = 70 * (BPKit.step(t, tipStart, 0.55) - BPKit.step(t, 1.95, 2.4)) * Double.pi / 180
        let gone = BPKit.step(t, 2.4, 2.9) - BPKit.step(t, 4.5, 5.1)
        let origin = (lip.x - 0.6 * gone, lip.y - 0.2 * gone)
        let body = cup.map { (p: (Double, Double)) -> (Double, Double) in
            let q = BPKit.turn(p, by: tip)
            return (origin.0 + q.0, origin.1 + q.1)
        }
        layer.fill(BPKit.polygon(u, body), with: .color(tint.opacity(0.3)))
        u.stroke(layer, u.polyline(body), tint, 0.05)
        let head = origin.1 + 0.015 + (top - origin.1 - 0.015) * BPKit.ramp(t, pourStart, pourStart + 0.15)
        let tail = origin.1 + 0.015 + (top - origin.1 - 0.015) * BPKit.ramp(t, fillEnd - 0.05, fillEnd + 0.1)
        if head - tail > 0.01, t < 2.3 {
            u.stroke(layer, u.line((lip.x + 0.015, tail), (lip.x + 0.015, head)), tint.opacity(0.8), 0.045)
        }
    }
}
