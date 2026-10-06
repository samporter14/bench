// BatchMCellScenes.swift
// ScienceStatus — inside the cell: a peroxisome chopping a fatty acid, the
// nuclear lamina holding a nucleus through a squeeze, a sugar tree built on a
// protein. Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Peroxisome: a long zigzag fatty-acid chain is fed through a gap in the
/// single membrane of a round organelle, towards the crystalloid core (a
/// small lattice). As each two-carbon unit reaches the core's face it turns
/// clay, snaps off the chain's leading end and drifts up or down inside the
/// organelle, fading, while the chain moves on. Four units go in per loop and
/// the chain's zigzag repeats every unit, so the end of the loop is the start.
enum Peroxisome {
    static let duration = 5.0

    /// Two-carbon units fed in, and snipped off, per loop.
    private static let units = 4

    private static let centre = 0.5, radius = 0.38
    /// The membrane is open this far either side of the chain's line.
    private static let mouth = 0.125
    private static let core = (x: 0.655, half: 0.12)
    /// The chain: one zigzag period is one two-carbon unit, `amp` is how far
    /// its carbons stand off its axis, `face` is where its leading end meets
    /// the core.
    private static let pitch = 0.18, amp = 0.055, face = 0.485
    /// Which way each unit's pair drifts (up is -1), so they fan out.
    private static let drift: [Double] = [-1, 1, -1, 1]

    /// The membrane: a circle open at the left, where the chain comes in.
    private static let membrane: [(Double, Double)] = {
        let open: Double = asin(mouth / radius)
        return (0...72).map { (i: Int) -> (Double, Double) in
            let a: Double = Double.pi + open + (2 * Double.pi - 2 * open) * Double(i) / 72
            return (centre + radius * cos(a), centre + radius * sin(a))
        }
    }()

    /// The chain's carbon `j`, counted back from its leading end.
    private static func carbon(_ j: Int, tip: Double) -> (Double, Double) {
        (tip - Double(j) * pitch / 2, centre + (j % 2 == 0 ? amp : -amp))
    }

    /// A snipped-off pair `age` units after the cut: it pops a little larger,
    /// turns as it drifts away from the chain's line, and fades inside.
    private static func pair(_ context: GraphicsContext, _ u: UnitSquare, age: Double, dir: Double) {
        let alpha = age < 0.8 ? 1 : 1 - Ease.clamp((age - 0.8) / 0.7)
        guard alpha > 0 else { return }
        let travel = Ease.out(age / 0.8)
        let pop = 1 + 0.3 * sin(.pi * Ease.clamp(age / 0.25))
        let turn = dir * 0.5 * travel
        let a = carbon(0, tip: face), b = carbon(1, tip: face)
        let mid: (Double, Double) = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
        func place(_ v: (Double, Double)) -> (Double, Double) {
            let dx = (v.0 - mid.0) * pop, dy = (v.1 - mid.1) * pop
            return (mid.0 + dx * cos(turn) - dy * sin(turn), mid.1 + dir * 0.2 * travel + dx * sin(turn) + dy * cos(turn))
        }
        let p = place(a), q = place(b)
        u.stroke(context, u.line(p, q), clay.opacity(alpha), 0.05)
        context.fill(u.circle(p.0, p.1, 0.045 * pop), with: .color(clay.opacity(alpha)))
        context.fill(u.circle(q.0, q.1, 0.045 * pop), with: .color(clay.opacity(alpha)))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let phase = t / duration * Double(units)
        let n = Int(phase.rounded(.down))
        let f = phase - Double(n)

        // The single membrane, and the crystalloid core: a square lattice.
        u.stroke(context, u.polyline(membrane), tint)
        // The gap's two edges stand a little proud, like the gate of a channel.
        for end in [membrane[0], membrane[membrane.count - 1]] {
            context.fill(u.circle(end.0, end.1, 0.056), with: .color(tint))
        }
        let c = core.x, hs = core.half
        u.stroke(context, u.capsule(c, centre, 2 * hs, 2 * hs, corner: 0.025), tint, 0.045)
        var lattice = Path()
        for side in [-1.0, 1.0] {
            let d = side * hs / 3
            lattice.addPath(u.line((c + d, centre - hs), (c + d, centre + hs)))
            lattice.addPath(u.line((c - hs, centre + d), (c + hs, centre + d)))
        }
        u.stroke(context, lattice, tint.opacity(0.85), 0.035)

        // The chain is pushed one unit towards the core, then rests a moment
        // with its leading pair fully clay; the next unit starts from the same
        // zigzag, so the pushes run on without a break.
        let push = Ease.inOut(f / 0.85)
        let tip = face - pitch + pitch * push
        var body: [(Double, Double)] = []
        var j = 2
        while true {
            let v = carbon(j, tip: tip)
            body.append(v)
            if v.0 < -0.05 { break }
            j += 1
        }
        u.stroke(context, u.polyline(body), tint, 0.05)

        // The leading pair turns clay as it nears the core, and the bond
        // behind it gives way just as the next loop's cut falls.
        let tagged = Ease.clamp((f - 0.68) / 0.2)
        let bond = 1 - Ease.clamp((f - 0.86) / 0.14)
        let (c0, c1, c2) = (carbon(0, tip: tip), carbon(1, tip: tip), carbon(2, tip: tip))
        u.stroke(context, u.line(c2, c1), tint.opacity(bond), 0.05)
        u.stroke(context, u.line(c1, c0), tint.opacity(1 - tagged), 0.05)
        u.stroke(context, u.line(c1, c0), clay.opacity(tagged), 0.05)
        context.fill(u.circle(c0.0, c0.1, 0.045), with: .color(clay.opacity(tagged)))
        context.fill(u.circle(c1.0, c1.1, 0.045), with: .color(clay.opacity(tagged)))

        // Pairs cut at the start of this unit and of the one before.
        for m in [n, n - 1] {
            let dir = drift[((m % units) + units) % units]
            pair(context, u, age: phase - Double(m), dir: dir)
        }
    }
}

/// Nuclear lamina: a whole nucleus, its envelope in tint and the lamina a
/// band of clay criss-cross filaments just inside it, squeezes through the gap
/// between a pair of pillars. The pair scrolls right to left past the nucleus,
/// which stays put: the envelope pinches into an hourglass, the band thins and
/// its cells stretch along the neck, and the chromatin (faint strands, some
/// tethered to the band) is squeezed through; then the nucleus springs back to
/// its oval with a small wobble and rests until the next pair arrives. One pair
/// per loop, scrolling one spacing, so the pillars end where they began.
enum NuclearLamina {
    static let duration = 5.0

    private static let cx = 0.5, cy = 0.5, rx = 0.39, ry = 0.285
    /// The room a pillar takes in the envelope's way (half its width), how far
    /// its tip stands from the nucleus's axis, and the envelope's half height
    /// where it passes through the gap. The pillar itself is drawn as one
    /// round-ended line `pillar` thick.
    private static let post = (half: 0.07, gap: 0.205, neck: 0.14)
    private static let pillar = 0.065
    /// Distance between pairs of pillars, and where one starts, off to the right.
    private static let spacing = 1.5, first = 1.2
    /// Cells in the net round the rim, the net's distance in from the
    /// envelope, and how deep it is.
    private static let cells = 10
    private static let outer = 0.052, band = 0.07

    /// Where each of the net's nodes sits round the rim: evenly spaced along
    /// the resting oval, then carried with the envelope as it deforms.
    private static let nodePhi: [Double] = {
        let m = 720
        var along = [Double](repeating: 0, count: m + 1)
        var last: (Double, Double) = (rx, 0)
        for i in 1...m {
            let a: Double = 2 * Double.pi * Double(i) / Double(m)
            let p: (Double, Double) = (rx * cos(a), ry * sin(a))
            along[i] = along[i - 1] + hypot(p.0 - last.0, p.1 - last.1)
            last = p
        }
        return (0..<cells).map { (k: Int) -> Double in
            let target = along[m] * (Double(k) + 0.5) / Double(cells)
            let i = along.firstIndex(where: { $0 >= target }) ?? m
            return 2 * Double.pi * Double(i) / Double(m)
        }
    }()

    /// Chromatin: wavy strands in the nucleus's own coordinates, `a` along
    /// its length and `b` across the room inside the net, both -1 to 1.
    private static let strands: [[(Double, Double)]] = [
        (-0.85, 0.35, -0.6, 0.2, 2.0), (-0.45, 0.85, 0.0, 0.2, 1.7), (-0.85, 0.45, 0.6, 0.2, 2.3),
    ].map { (from: Double, to: Double, base: Double, amp: Double, waves: Double) -> [(Double, Double)] in
        (0...24).map { (i: Int) -> (Double, Double) in
            let s: Double = Double(i) / 24
            return (from + (to - from) * s, base + amp * sin(2 * Double.pi * waves * s))
        }
    }
    /// The two strands tethered to the net: which strand, how far along it,
    /// and whether it holds to the top of the net (else the bottom).
    private static let tethers: [(strand: Int, at: Int, top: Bool)] = [(0, 6, true), (0, 19, true), (2, 12, false)]

    private static func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k / 4
    }

    /// The nucleus at one moment: its oval, pinched wherever a pair of pillars
    /// stands across it.
    private struct Nucleus {
        let pairs: [Double]
        let rx: Double, ry: Double

        init(p: Double) {
            pairs = (-1...1).map { NuclearLamina.first + Double($0) * NuclearLamina.spacing - NuclearLamina.spacing * p }
            // The nucleus lengthens a little while it is squeezed, and wobbles back to its oval afterwards.
            let near = pairs.map { abs($0 - NuclearLamina.cx) }.min() ?? 1
            let s = Ease.clamp((0.47 - near) / 0.2)
            let engaged = s * s * (3 - 2 * s)
            let q = Ease.clamp((p - 0.74) / 0.26)
            let wobble = 0.07 * (1 - q) * (1 - q) * sin(2 * Double.pi * 1.5 * q)
            rx = NuclearLamina.rx * (1 + 0.08 * engaged - 0.5 * wobble)
            ry = NuclearLamina.ry * (1 + 0.06 * engaged + wobble)
        }

        func oval(_ x: Double) -> Double {
            let s = (x - NuclearLamina.cx) / rx
            return abs(s) < 1 ? ry * (1 - s * s).squareRoot() : 0
        }

        /// The envelope's half height at `x`: the oval, held in by a funnel
        /// round each pair's gap.
        func half(_ x: Double) -> Double {
            var h = oval(x)
            for px in pairs {
                let d = abs(x - px) - NuclearLamina.post.half
                let cap = NuclearLamina.post.neck + 0.5 * (d + (d * d + 0.0009).squareRoot())
                h = NuclearLamina.smin(h, cap, 0.04)
            }
            return h
        }

        /// A point on the envelope, `phi` being the angle it would have on a plain oval.
        func rim(_ phi: Double) -> (Double, Double) {
            let x = NuclearLamina.cx + rx * cos(phi)
            let h = half(x)
            return (x, NuclearLamina.cy + (sin(phi) >= 0 ? h : -h))
        }

        /// A point of the net: `v` 0 is its outer edge, 1 its inner edge. The
        /// net thins where the envelope is pinched, so its cells stretch.
        func lamina(_ phi: Double, _ v: Double) -> (Double, Double) {
            let p = rim(phi), a = rim(phi - 0.01), b = rim(phi + 0.01)
            let m = max(hypot(b.0 - a.0, b.1 - a.1), 0.000001)
            let tx = (b.0 - a.0) / m, ty = (b.1 - a.1) / m
            let o = oval(p.0)
            let squeeze = o > 0.0001 ? min(1, half(p.0) / o) : 1
            let off = NuclearLamina.outer + v * NuclearLamina.band * squeeze
            return (p.0 - ty * off, p.1 + tx * off)
        }

        /// A point in the room inside the net.
        func inside(_ a: Double, _ b: Double) -> (Double, Double) {
            let x = NuclearLamina.cx + a * (rx - 0.2)
            let room = max(half(x) - (NuclearLamina.outer + NuclearLamina.band + 0.03), 0.015)
            return (x, NuclearLamina.cy + b * room)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let p = t / duration
        let nuc = Nucleus(p: p)

        // The pillars scroll past; a pair is two round-ended posts reaching in from the top and bottom.
        for pairX in nuc.pairs where pairX > -0.2 && pairX < 1.2 {
            for side in [-1.0, 1.0] {
                let tipY = cy + side * (post.gap + pillar / 2)
                u.stroke(context, u.line((pairX, side < 0 ? -0.1 : 1.1), (pairX, tipY)), tint, pillar)
            }
        }

        // Chromatin, squeezed with the nucleus.
        let paths = strands.map { strand -> [(Double, Double)] in strand.map { nuc.inside($0.0, $0.1) } }
        for strand in paths {
            u.stroke(context, u.polyline(strand), tint.opacity(0.3), 0.04)
        }

        // The lamina: criss-cross filaments in a band just inside the envelope.
        var net = Path()
        var inner: [(Double, Double)] = []
        for i in 0..<cells {
            let a = nodePhi[i], b = nodePhi[(i + 1) % cells] + (i == cells - 1 ? 2 * Double.pi : 0)
            // Each filament runs across the band, bending with the envelope.
            let down = (0...6).map { (k: Int) -> (Double, Double) in nuc.lamina(a + (b - a) * Double(k) / 6, Double(k) / 6) }
            let up = (0...6).map { (k: Int) -> (Double, Double) in nuc.lamina(a + (b - a) * Double(k) / 6, 1 - Double(k) / 6) }
            net.addPath(u.polyline(down))
            net.addPath(u.polyline(up))
            inner.append(nuc.lamina(a, 1))
        }
        u.stroke(context, net, clay, 0.035)

        // Tethers from the band's inner nodes to the chromatin.
        var ties = Path()
        for tie in tethers {
            let from = paths[tie.strand][tie.at]
            var best = 0, gap = Double.infinity
            for (i, node) in inner.enumerated() where (sin(nodePhi[i]) < 0) == tie.top {
                if abs(node.0 - from.0) < gap { gap = abs(node.0 - from.0); best = i }
            }
            ties.addPath(u.line(from, inner[best]))
        }
        u.stroke(context, ties, clay, 0.035)

        // The envelope.
        var envelope = u.polyline((0..<120).map { nuc.rim(2 * Double.pi * Double($0) / 120) })
        envelope.closeSubpath()
        u.stroke(context, envelope, tint)
    }
}

/// Glycosylation: a folded protein sits low in the square, a lumpy blob with
/// a helix drawn in it. From one point on its surface, a clay asparagine, a
/// sugar tree grows up sugar by sugar, each popping in: two squares for the
/// stalk, a circle, two circle arms, and a clay diamond on each of the arms'
/// four tips. The finished tree holds, then the dressed protein drifts away up
/// and to the right while a bare one drifts in from the bottom left and takes
/// its place, ready for the next tree.
enum Glycosylation {
    static let duration = 5.0

    private static let leaveAt = 3.4, arriveAt = 3.85, leaveFor = 1.2, arriveFor = 1.15

    /// The protein's outline at angle `a`: wider than tall, with lumps.
    private static func edge(_ a: Double) -> (Double, Double) {
        let wobble: Double = 1 + 0.07 * sin(3 * a + 1.4) + 0.05 * sin(5 * a + 0.3) + 0.04 * sin(2 * a + 0.8)
        return (0.5 + 0.33 * wobble * cos(a), 0.82 + 0.125 * wobble * sin(a))
    }
    private static let outline: [(Double, Double)] = (0...60).map { edge(Double($0) * 2 * .pi / 60) }
    /// The asparagine, on the top of the protein.
    private static let asparagine = edge(-.pi / 2)
    private static let asparagineRadius = 0.052
    /// A short helix inside the fold.
    private static let helix: [(Double, Double)] = (0...24).map { (i: Int) -> (Double, Double) in
        let s: Double = Double(i) / 24
        return (0.32 + 0.3 * s, 0.84 + 0.03 * sin(2 * Double.pi * 3 * s))
    }

    private enum Kind {
        case square, circle, diamond

        /// How far its edge reaches from its middle, for the links between sugars.
        var reach: Double {
            switch self {
            case .square: return 0.052
            case .circle: return 0.062
            case .diamond: return 0.078
            }
        }
    }

    /// One sugar: what it is, where it sits relative to the asparagine, which
    /// sugar it hangs from (-1 is the asparagine itself) and when it pops in.
    private struct Sugar {
        let kind: Kind
        let dx: Double, dy: Double
        let parent: Int
        let at: Double
    }
    private static let tree: [Sugar] = [
        Sugar(kind: .square, dx: 0, dy: -0.105, parent: -1, at: 0.5),
        Sugar(kind: .square, dx: 0, dy: -0.215, parent: 0, at: 0.75),
        Sugar(kind: .circle, dx: 0, dy: -0.335, parent: 1, at: 1.0),
        Sugar(kind: .circle, dx: -0.19, dy: -0.44, parent: 2, at: 1.3),
        Sugar(kind: .circle, dx: 0.19, dy: -0.44, parent: 2, at: 1.5),
        Sugar(kind: .diamond, dx: -0.29, dy: -0.585, parent: 3, at: 2.0),
        Sugar(kind: .diamond, dx: -0.1, dy: -0.585, parent: 3, at: 2.12),
        Sugar(kind: .diamond, dx: 0.1, dy: -0.585, parent: 4, at: 2.24),
        Sugar(kind: .diamond, dx: 0.29, dy: -0.585, parent: 4, at: 2.36),
    ]

    /// The protein, and the tree grown on it `time` seconds into the loop
    /// (nil for the bare protein waiting its turn).
    private static func protein(_ context: GraphicsContext, _ u: UnitSquare, grown time: Double?, tint: Color) {
        var body = u.polyline(outline)
        body.closeSubpath()
        u.stroke(context, body, tint)
        u.stroke(context, u.polyline(helix), tint.opacity(0.5), 0.04)
        let ax = asparagine.0, ay = asparagine.1
        context.fill(u.circle(ax, ay, asparagineRadius), with: .color(clay))
        guard let time else { return }

        func place(_ i: Int) -> (Double, Double) {
            i < 0 ? (ax, ay) : (ax + tree[i].dx, ay + tree[i].dy)
        }

        // Links first, from edge to edge so they never cross a hollow circle.
        for (i, sugar) in tree.enumerated() {
            let grow = Ease.out((time - sugar.at + 0.1) / 0.3)
            guard grow > 0 else { continue }
            let a = place(sugar.parent), b = place(i)
            let dist = hypot(b.0 - a.0, b.1 - a.1)
            let dir = ((b.0 - a.0) / dist, (b.1 - a.1) / dist)
            let r0 = sugar.parent < 0 ? asparagineRadius : tree[sugar.parent].kind.reach
            let length = dist - r0 - sugar.kind.reach
            guard length > 0.012 else { continue }
            let from = (a.0 + dir.0 * r0, a.1 + dir.1 * r0)
            let to = (from.0 + dir.0 * length * grow, from.1 + dir.1 * length * grow)
            u.stroke(context, u.line(from, to), tint, 0.04)
        }

        for (i, sugar) in tree.enumerated() {
            let pop = Ease.outBack((time - sugar.at) / 0.4)
            guard pop > 0 else { continue }
            let (x, y) = place(i)
            switch sugar.kind {
            case .square:
                let h = 0.052 * pop
                context.fill(u.capsule(x, y, 2 * h, 2 * h, corner: 0.012), with: .color(tint))
            case .circle:
                u.stroke(context, u.circle(x, y, 0.042 * pop), tint, 0.04 * pop)
            case .diamond:
                let d = 0.078 * pop
                var shape = u.line((x, y - d), (x + d, y), (x, y + d), (x - d, y))
                shape.closeSubpath()
                context.fill(shape, with: .color(clay))
            }
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The dressed protein leaves; the bare one comes in behind it.
        let leaveBy = Ease.clamp((t - leaveAt) / leaveFor)
        let leave = leaveBy * leaveBy
        let arrive = Ease.out((t - arriveAt) / arriveFor)

        var dressed = context
        dressed.translateBy(x: u.len(leave), y: u.len(-leave))
        protein(dressed, u, grown: t, tint: tint)

        if arrive > 0 {
            var bare = context
            bare.translateBy(x: u.len(-0.9 * (1 - arrive)), y: u.len(0.55 * (1 - arrive)))
            protein(bare, u, grown: nil, tint: tint)
        }
    }
}
