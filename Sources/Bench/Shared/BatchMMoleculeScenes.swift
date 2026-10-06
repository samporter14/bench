// BatchMMoleculeScenes.swift
// ScienceStatus — molecules at work: a transposon jumping, a ubiquitin chain
// built link by link, an RNA folding into a pseudoknot. Each draws in a unit
// square (see `UnitSquare`).

import SwiftUI

/// Transposon jump: two transposase blobs clamp the ends of a clay stretch of
/// a DNA duplex, cut it out and lift it as an arch between them while the gap
/// behind it closes; the complex arcs over to the right, the DNA opens at a
/// new site and the clay drops in, and the transposases let go. The DNA
/// scrolls left by exactly the jump over the last stretch of the loop, so the
/// new site ends where the old one started.
enum TransposonJump {
    static let duration = 5.0

    // The rungs repeat every `pitch`. The transposon is three rungs long and
    // the new site five rungs to its right, so the scroll is a whole number
    // of periods and the loop closes.
    private static let pitch = 0.09
    private static let length = 0.27
    private static let jump = 0.45
    private static let start = 0.18
    private static let dnaY = 0.70, half = 0.055
    private static let steps = 18
    private static let archHalf = 0.125, archHeight = 0.16

    /// The transposon's centre line: straight in the DNA at `bend` 0, an arch at 1.
    private static func spine(centre cx: Double, endY ey: Double, bend m: Double) -> [(Double, Double)] {
        (0...steps).map { i -> (Double, Double) in
            let s = Double(i) / Double(steps)
            let sx = cx + (s - 0.5) * length
            let ax = cx + archHalf * cos(Double.pi * (1 - s))
            let ay = ey - archHeight * sin(Double.pi * s)
            return (sx + (ax - sx) * m, ey + (ay - ey) * m)
        }
    }

    /// A stretch of duplex with a rung at each of `rungs`.
    private static func duplex(_ c: GraphicsContext, _ u: UnitSquare, from a: Double, to b: Double, rungs: [Double], tint: Color) {
        guard b > a else { return }
        for side in [-1.0, 1.0] { u.stroke(c, u.line((a, dnaY + side * half), (b, dnaY + side * half)), tint, 0.05) }
        for x in rungs where x > a && x < b {
            u.stroke(c, u.line((x, dnaY - half), (x, dnaY + half)), tint.opacity(0.6), 0.035)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var c = context
        c.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))

        let close = Ease.inOut((t - 1.3) / 0.6)        // the gap behind the cut shuts
        let hop = Ease.inOut((t - 1.6) / 1.3)          // the complex travels along the DNA
        let open = Ease.inOut((t - 2.6) / 0.5)         // the new site opens
        let landing = Ease.inOut((t - 3.3) / 0.5)
        let bend = Ease.inOut((t - 0.7) / 0.6) * (1 - landing)
        let rise = 0.15 * Ease.inOut((t - 0.9) / 0.5) * (1 - landing) + 0.06 * sin(Double.pi * hop)
        let bind = Ease.outBack((t - 0.1) / 0.5)
        let leave = Ease.inOut((t - 3.85) / 0.45)
        let scroll = jump * Ease.inOut((t - 3.6) / 1.4)

        // Everything below is in DNA coordinates; the scroll slides them all.
        c.translateBy(x: -u.len(scroll), y: 0)

        // The DNA in three pieces: left of the transposon; from its far end
        // to the new site (it slides left to meet the first as the gap
        // closes); and beyond the site (it slides back right as the site opens).
        let shift = -length * close
        let leftRungs = (0..<2).map { start - (Double($0) + 0.5) * pitch }
        let midRungs = (0..<5).map { start + length + (Double($0) + 0.5) * pitch + shift }
        let farRungs = (0..<14).map { start + length + jump + (Double($0) + 0.5) * pitch + shift + length * open }
        duplex(c, u, from: -0.1, to: start, rungs: leftRungs, tint: tint)
        duplex(c, u, from: start + length + shift, to: start + length + jump + shift, rungs: midRungs, tint: tint)
        duplex(c, u, from: start + length + jump + shift + length * open, to: 2.0, rungs: farRungs, tint: tint)

        // The transposon: straight in the DNA, then an arch, then straight again.
        let cx = start + length / 2 + jump * hop
        let body = spine(centre: cx, endY: dnaY - rise, bend: bend)
        var near: [(Double, Double)] = [], far: [(Double, Double)] = []
        for i in body.indices {
            let p = body[max(i - 1, 0)], q = body[min(i + 1, body.count - 1)]
            let d = max(hypot(q.0 - p.0, q.1 - p.1), 1e-6)
            let nx = (q.1 - p.1) / d * half, ny = -(q.0 - p.0) / d * half
            near.append((body[i].0 + nx, body[i].1 + ny))
            far.append((body[i].0 - nx, body[i].1 - ny))
        }
        u.stroke(c, u.polyline(near), clay, 0.05)
        u.stroke(c, u.polyline(far), clay, 0.05)
        for i in [3, 9, 15] { u.stroke(c, u.line(near[i], far[i]), clay.opacity(0.8), 0.035) }

        // The two transposases, lumpy tint blobs that drop onto the ends and let go again.
        let grow = max(bind * (1 - leave), 0)
        if grow > 0.01 {
            let drop = -0.07 * ((1 - Ease.out((t - 0.1) / 0.5)) + leave)
            for (end, side) in [(body[0], -1.0), (body[steps], 1.0)] {
                c.fill(u.ellipse(end.0, end.1 + drop, 0.09 * grow, 0.15 * grow), with: .color(tint))
                c.fill(u.circle(end.0 + side * 0.025 * grow, end.1 + drop + 0.05 * grow, 0.035 * grow), with: .color(tint))
            }
        }
    }
}

/// Ubiquitin chain: a lumpy substrate sits in the cup of an E3 ligase while
/// four small E2 enzymes come in from the right one after another, each
/// carrying a clay ubiquitin that it hands to the end of the growing zigzag
/// chain before it leaves. Then the tagged substrate lifts out of the cup and
/// slides off to the right as a bare one slides in from the left and settles.
enum UbiquitinChain {
    static let duration = 6.0

    private static let grip = (x: 0.38, y: 0.58)       // where the substrate sits in the E3
    private static let reach = 0.17                    // substrate radius
    private static let slide = 0.95, lift = 0.16
    private static let cycle = 0.95                    // one E2: in, hand over, out
    private static let carry = 0.085                   // bead centre to E2 centre

    /// The E3: a shallow cup under the substrate.
    private static let cup: [(Double, Double)] = (0...32).map { i -> (Double, Double) in
        let a = (30 + 120 * Double(i) / 32) * Double.pi / 180
        return (grip.x + 0.28 * cos(a), 0.55 + 0.28 * sin(a))
    }

    /// The substrate's lumpy outline, round its middle.
    private static let blob: [(Double, Double)] = (0..<48).map { i -> (Double, Double) in
        let a = Double(i) / 48 * 2 * Double.pi
        let r = reach * (1 + 0.09 * sin(3 * a + 0.6) + 0.05 * sin(5 * a + 2.0))
        return (r * cos(a), r * sin(a))
    }

    /// Where the chain leaves the substrate, and its four beads in a zigzag
    /// running up and to the right, all measured from the substrate's middle.
    private static let heading = -48 * Double.pi / 180
    private static let root: (Double, Double) = (0.15 * cos(heading), 0.15 * sin(heading))
    private static let chain: [(Double, Double)] = (0..<4).map { k -> (Double, Double) in
        let s = reach + 0.015 + 0.075 * Double(k)
        let z = (k % 2 == 0 ? -1.0 : 1.0) * 0.028
        return (s * cos(heading) - z * sin(heading), s * sin(heading) + z * cos(heading))
    }

    private static func substrate(_ c: GraphicsContext, _ u: UnitSquare, _ tint: Color, at p: (Double, Double)) {
        var shape = u.polyline(blob.map { (p.0 + $0.0, p.1 + $0.1) })
        shape.closeSubpath()
        c.fill(shape, with: .color(tint.opacity(0.16)))
        u.stroke(c, shape, tint, 0.05)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var c = context
        c.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))

        u.stroke(c, u.polyline(cup), tint, 0.075)

        // The tagged substrate lifts out of the cup and slides right; a bare
        // one slides in from the left at the same height, then drops in.
        let lifted = Ease.inOut((t - 4.3) / 0.4)
        let glide = Ease.inOut((t - 4.45) / 0.95)
        let settle = Ease.inOut((t - 5.3) / 0.45)
        substrate(c, u, tint, at: (grip.x - slide + slide * glide, grip.y - lift * (1 - settle)))
        let at = (x: grip.x + slide * glide, y: grip.y - lift * lifted)
        substrate(c, u, tint, at: at)

        // The chain, link by link, riding on the tagged substrate.
        var previous = (at.x + root.0, at.y + root.1)
        for k in 0..<4 {
            let s = 0.35 + cycle * Double(k)
            let bead = (at.x + chain[k].0, at.y + chain[k].1)
            let landed = Ease.clamp((t - s - 0.4) / 0.2)
            if landed > 0 {
                u.stroke(c, u.line(previous, (previous.0 + (bead.0 - previous.0) * landed, previous.1 + (bead.1 - previous.1) * landed)), clay, 0.03)
            }
            previous = bead

            // The E2 comes in from the right with the bead on its leading
            // end, waits a moment, and leaves without it.
            let inward = t < s + 0.55 ? 1 - Ease.out((t - s) / 0.4) : 0
            let outward = Ease.inOut((t - s - 0.55) / 0.4)
            if t > s && t < s + cycle {
                let x = bead.0 + carry + 0.8 * (inward + outward)
                c.fill(u.capsule(x, bead.1, 0.18, 0.095, corner: 0.047), with: .color(tint))
            }
            if t > s { c.fill(u.circle(bead.0 + 0.8 * inward, bead.1, 0.04), with: .color(clay)) }
        }
    }
}

/// Pseudoknot: an RNA strand with base ticks lies straight across the lower
/// middle. Its left part folds up into a hairpin: the loop lifts and the
/// paired rungs (stem 1, tint) zip closed down to the base; then the clay 3′ tail swings up and over and
/// pairs with the hairpin's loop, stem 2 with clay rungs stacked on the first,
/// the loops crossing between them. It holds, then melts: the tail comes
/// away, the hairpin unzips from its base, and the strand lies straight again.
enum Pseudoknot {
    static let duration = 6.0

    // The strand is one run of points that move between three arrangements:
    // `flat` along the baseline, `hairpin` (stem 1 and a bulb of a loop) and
    // `knot` (stem 2 on top of stem 1). Its parts, in order from the 5′ end:
    // strand A up the left of stem 1, then the loop (L1, C, L2), strand B
    // down the right of stem 1, then the tail (L3, D) with D coming down the
    // left of stem 2 to pair with C.
    private static let nA = 9, nL1 = 6, nC = 10, nL2 = 24, nB = 9, nL3 = 48, nD = 10
    private static let loopEnd = nA + nL1 + nC + nL2
    private static let tailStart = loopEnd + nB
    private static let count = tailStart + nL3 + nD
    private static let baseY = 0.74, left = 0.22, right = 0.40

    /// A smooth path through `corners` (corners rounded by cutting them
    /// three times), as `n` points evenly spaced along it.
    private static func route(_ corners: [(Double, Double)], _ n: Int) -> [(Double, Double)] {
        var pts = corners
        for _ in 0..<3 {
            var next = [pts[0]]
            for i in 0..<(pts.count - 1) {
                let p = pts[i], q = pts[i + 1]
                next.append((0.75 * p.0 + 0.25 * q.0, 0.75 * p.1 + 0.25 * q.1))
                next.append((0.25 * p.0 + 0.75 * q.0, 0.25 * p.1 + 0.75 * q.1))
            }
            next.append(pts[pts.count - 1])
            pts = next
        }
        var along = [0.0]
        for i in 1..<pts.count { along.append(along[i - 1] + hypot(pts[i].0 - pts[i - 1].0, pts[i].1 - pts[i - 1].1)) }
        var out: [(Double, Double)] = []
        var j = 0
        for k in 0..<n {
            let d = along[along.count - 1] * Double(k) / Double(n - 1)
            while j < pts.count - 2 && along[j + 1] < d { j += 1 }
            let f = (d - along[j]) / max(along[j + 1] - along[j], 1e-9)
            out.append((pts[j].0 + (pts[j + 1].0 - pts[j].0) * f, pts[j].1 + (pts[j + 1].1 - pts[j].1) * f))
        }
        return out
    }

    private static let flat: [(Double, Double)] = (0..<count).map { i -> (Double, Double) in
        (0.04 + 0.92 * Double(i) / Double(count - 1), baseY)
    }

    private static let hairpin: [(Double, Double)] = {
        var p = route([(left, baseY), (left, 0.54)], nA)
        p += route([(left, 0.54), (0.20, 0.46), (0.15, 0.38), (0.17, 0.28), (0.31, 0.22),
                    (0.45, 0.28), (0.47, 0.38), (0.42, 0.46), (right, 0.54)], nL1 + nC + nL2)
        p += route([(right, 0.54), (right, baseY)], nB)
        p += route([(right, baseY), (0.96, baseY)], nL3 + nD)
        return p
    }()

    private static let knot: [(Double, Double)] = {
        var p = route([(left, baseY), (left, 0.54)], nA)
        p += route([(left, 0.54), (left + 0.01, 0.51), (right - 0.01, 0.47), (right, 0.44)], nL1)
        p += route([(right, 0.44), (right, 0.22)], nC)
        p += route([(right, 0.22), (right, 0.19), (0.445, 0.165), (0.485, 0.21), (0.49, 0.36), (0.48, 0.48), (0.45, 0.54), (right, 0.54)], nL2)
        p += route([(right, 0.54), (right, baseY)], nB)
        p += route([(right, baseY), (0.6, baseY), (0.6, 0.06), (left, 0.06), (left, 0.22)], nL3)
        p += route([(left, 0.22), (left, 0.44)], nD)
        return p
    }()

    /// Base pairs between two points of the strand: stem 1 pairs A with B,
    /// stem 2 pairs C with D.
    private static let stem1 = [1, 4, 7].map { (a: $0, b: loopEnd + nB - 1 - $0) }
    private static let stem2 = [1, 4, 7].map { (a: nA + nL1 + $0, b: tailStart + nL3 + nD - 1 - $0) }

    /// How late each point moves (s) when the hairpin zips and the tail
    /// swings, and when they come undone again: the loop leads and the legs
    /// close down to the base, and it all runs backwards on the way out.
    private static func delays() -> (zip: [Double], unzip: [Double], swing: [Double], melt: [Double]) {
        var zip: [Double] = [], unzip: [Double] = [], swing: [Double] = [], melt: [Double] = []
        for i in 0..<count {
            let height: Double      // 0 at the base of stem 1, 1 at its top
            if i < nA { height = Double(i) / Double(nA - 1) }
            else if i < loopEnd { height = 1 }
            else if i < tailStart { height = 1 - Double(i - loopEnd) / Double(nB - 1) }
            else { height = 0 }
            let along = i < tailStart ? 0 : Double(i - tailStart) / Double(count - tailStart - 1)
            let isLoop = i >= nA && i < loopEnd, isTail = i >= tailStart
            zip.append(isLoop ? 0 : isTail ? 0.2 : 0.65 * (1 - height))
            unzip.append(isLoop ? 0.55 : isTail ? 0.3 : 0.55 * height)
            swing.append(isTail ? 0.8 * along : isLoop ? 0.1 : 0)
            melt.append(isTail ? 0.7 * (1 - along) : isLoop ? 0.3 : 0)
        }
        return (zip, unzip, swing, melt)
    }
    private static let late = delays()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // Where each point is: flat, then folded up, then knotted, then back.
        var pos: [(Double, Double)] = []
        var moved: [Double] = [], tied: [Double] = []
        for i in 0..<count {
            let fold = Ease.inOut((t - 0.4 - late.zip[i]) / 0.6) * (1 - Ease.inOut((t - 4.6 - late.unzip[i]) / 0.5))
            let tie = Ease.inOut((t - 1.9 - late.swing[i]) / 0.75) * (1 - Ease.inOut((t - 3.9 - late.melt[i]) / 0.6))
            let base = (flat[i].0 + (hairpin[i].0 - flat[i].0) * fold, flat[i].1 + (hairpin[i].1 - flat[i].1) * fold)
            pos.append((base.0 + (knot[i].0 - base.0) * tie, base.1 + (knot[i].1 - base.1) * tie))
            moved.append(max(fold, tie))
            tied.append(tie)
        }

        // Base ticks on the free strand, gone once a base has left the line.
        for i in stride(from: 3, to: count - 1, by: 6) {
            let alpha = 1 - Ease.clamp(3 * moved[i])
            guard alpha > 0.02 else { continue }
            let p = pos[i - 1], q = pos[i + 1]
            let d = max(hypot(q.0 - p.0, q.1 - p.1), 1e-6)
            let n = ((q.1 - p.1) / d * 0.04, -(q.0 - p.0) / d * 0.04)
            u.stroke(context, u.line(pos[i], (pos[i].0 + n.0, pos[i].1 + n.1)), (i < tailStart ? tint : clay).opacity(0.7 * alpha), 0.03)
        }

        // Base pairs, rungs that appear as the two bases come together.
        for (pairs, colour, width) in [(stem1, tint.opacity(0.75), 0.032), (stem2, clay, 0.04)] {
            for pair in pairs {
                let a = pos[pair.a], b = pos[pair.b]
                let together = Ease.clamp((right - left + 0.06 - hypot(a.0 - b.0, a.1 - b.1)) / 0.05)
                if together > 0.02 { u.stroke(context, u.line(a, b), colour.opacity(together), width) }
            }
        }

        // The strand: tint up to the end of the hairpin, the clay tail after it.
        u.stroke(context, u.polyline(Array(pos[0...tailStart])), tint, 0.05)
        u.stroke(context, u.polyline(Array(pos[tailStart...])), clay, 0.05)
        // Strand C, stem 2's other side, takes the tail's clay as the two pair.
        let c0 = nA + nL1, c1 = c0 + nC
        u.stroke(context, u.polyline(Array(pos[c0..<c1])), clay.opacity(tied[c0 + nC / 2]), 0.05)
    }
}
