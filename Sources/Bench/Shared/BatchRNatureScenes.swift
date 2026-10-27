// BatchRNatureScenes.swift
// ScienceStatus — small natural forms: two drops joining, a slime mold
// network finding its way through a maze, a fern uncoiling and a diatom
// turning its shell.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// The square itself, so that things sliding in from outside it are cut off at its edge.
private func rClipped(_ context: GraphicsContext, _ u: UnitSquare) -> GraphicsContext {
    var layer = context
    layer.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))
    return layer
}

/// Droplet coalescence: two clay drops drift together, touch, and a neck opens between them.
/// One outline then carries the pair, a peanut that draws in on itself (its area held fixed,
/// so the drop never seems to swell), rings once as an oval and settles into a single round
/// drop. The whole row then slides left, the merged drop leaving as a fresh pair arrives from
/// the right to take the first pair's place.
enum DropletCoalescence {
    static let duration = 5.0

    private static let radius = 0.15
    /// How far each drop starts from the middle, and when they touch, how long the pair
    /// takes to draw in, when the ringing begins and when the row slides.
    private static let apart = 0.25
    private static let touchAt = 1.1, drawInFor = 2.4, ringAt = 2.6, slideAt = 3.9
    private static let rays = 72
    /// The two drops' area, which the merged outline keeps.
    private static let target = 2 * Double.pi * radius * radius
    private static let direction: [(c: Double, s: Double)] = (0..<72).map {
        (cos(Double($0) * 2 * .pi / 72), sin(Double($0) * 2 * .pi / 72))
    }

    /// A smooth minimum of two distances: the union of two discs with a fillet in the crook
    /// between them, `k` wide.
    private static func smoothMin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k / 4
    }

    /// The merged outline about the middle of the square, with the drops' centres `d` either
    /// side of it, a neck fillet `k` wide, and an oval ringing of amplitude `ring` (positive
    /// is long across, negative tall). Each ray from the middle is bisected for where it
    /// leaves the shape, and the whole is rescaled to the two drops' area.
    private static func merged(gap d: Double, neck k: Double, ring: Double) -> [(Double, Double)] {
        var out = [Double](repeating: 0, count: rays)
        for (i, dir) in direction.enumerated() {
            var lo = 0.0, hi = 0.5
            for _ in 0..<18 {
                let m = (lo + hi) / 2
                let x = m * dir.c, y = m * dir.s
                let f = smoothMin(hypot(x - d, y) - radius, hypot(x + d, y) - radius, k)
                if f < 0 { lo = m } else { hi = m }
            }
            out[i] = lo * (1 + ring * (dir.c * dir.c - dir.s * dir.s))
        }
        var area = 0.0
        let step = 2 * Double.pi / Double(rays)
        for i in 0..<rays { area += 0.5 * out[i] * out[(i + 1) % rays] * sin(step) }
        let scale = sqrt(target / area)
        return (0..<rays).map { (0.5 + scale * out[$0] * direction[$0].c, 0.5 + scale * out[$0] * direction[$0].s) }
    }

    /// Two drops, `d` either side of `x`.
    private static func pair(_ context: GraphicsContext, _ u: UnitSquare, x: Double, gap d: Double, tint: Color) {
        for side in [-1.0, 1.0] {
            let drop = u.circle(x + side * d, 0.5, radius)
            context.fill(drop, with: .color(clay))
            u.stroke(context, drop, tint, 0.06)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let layer = rClipped(context, u)
        let slide = Ease.inOut((t - slideAt) / (duration - slideAt))

        if t < touchAt {
            // They draw together, faster as they near.
            let p = t / touchAt
            pair(layer, u, x: 0.5 - slide, gap: apart - (apart - radius) * p * p, tint: tint)
        } else {
            let s = Ease.clamp((t - touchAt) / drawInFor)
            let neck = 0.13 * Ease.out((t - touchAt) / 0.7)
            // After the pair has drawn in, the drop rings once as an oval and settles.
            let ring = t > ringAt ? -0.085 * exp(-(t - ringAt) / 0.55) * sin(2 * .pi * (t - ringAt) / 1.2) : 0
            var drop = u.polyline(merged(gap: radius * (1 - s) * (1 - s), neck: neck, ring: ring).map { ($0.0 - slide, $0.1) })
            drop.closeSubpath()
            layer.fill(drop, with: .color(clay))
            u.stroke(layer, drop, tint, 0.06)
        }
        if slide > 0 { pair(layer, u, x: 1.5 - slide, gap: apart, tint: tint) }
    }
}

/// Slime mold maze: a square maze, an outer wall with a gap at the left (the entrance) and one at
/// the right (the exit) and short walls inside, with a clay seed on a food dot at the entrance
/// and a second clay food dot at the exit. Wavy tubes of varying girth flood the corridors from
/// the seed, the winding route to the exit and the blind corridors alike, with small twigs
/// fanning off them. When the first tube reaches the exit its dot swells; then the blind
/// branches and twigs thin and draw back to where they began while the tube along the route
/// thickens. It holds, then fades, leaving the seed and the two food dots again.
enum SlimeMoldMaze {
    static let duration = 7.0

    private static let fadeAt = 6.0

    /// The middle of the cell in column `c` and row `r` of the four-by-four maze.
    private static func cell(_ c: Int, _ r: Int) -> (Double, Double) { (0.2 + 0.2 * Double(c), 0.2 + 0.2 * Double(r)) }
    private static let seed = cell(0, 1)
    private static let food = cell(3, 1)

    /// The walls: the outer one with its two gaps, then the walls inside.
    private static let walls: [[(Double, Double)]] = [
        [(0.1, 0.3), (0.1, 0.1), (0.9, 0.1), (0.9, 0.3)],
        [(0.9, 0.5), (0.9, 0.9), (0.1, 0.9), (0.1, 0.5)],
        [(0.7, 0.1), (0.7, 0.3), (0.5, 0.3), (0.5, 0.7), (0.7, 0.7)],
        [(0.5, 0.5), (0.3, 0.5), (0.3, 0.3)],
        [(0.7, 0.5), (0.9, 0.5)],
        [(0.3, 0.7), (0.3, 0.9)],
    ]

    /// A lumpy blob, the slime's body, `r` across.
    private static func blob(_ u: UnitSquare, _ at: (Double, Double), _ r: Double) -> Path {
        var path = u.polyline((0...36).map { k in
            let a = Double(k) * 2 * .pi / 36
            let rr = r * (1 + 0.1 * sin(3 * a + 0.6) + 0.06 * sin(5 * a + 1.9))
            return (at.0 + rr * cos(a), at.1 + rr * sin(a))
        })
        path.closeSubpath()
        return path
    }

    /// A winding path with its length so far at each point.
    private struct Route {
        let points: [(Double, Double)]
        let reached: [Double]
        var length: Double { reached[reached.count - 1] }

        init(dense: [(Double, Double)]) {
            points = dense
            var sums = [0.0]
            for i in 1..<dense.count { sums.append(sums[i - 1] + hypot(dense[i].0 - dense[i - 1].0, dense[i].1 - dense[i - 1].1)) }
            reached = sums
        }

        /// The same line wavering sideways by up to `wave` (and not at all at either end).
        init(waving dense: [(Double, Double)], wave: Double, phase: Double) {
            var sums = [0.0]
            for i in 1..<dense.count { sums.append(sums[i - 1] + hypot(dense[i].0 - dense[i - 1].0, dense[i].1 - dense[i - 1].1)) }
            let total = sums[sums.count - 1]
            var waved = dense
            for i in 0..<dense.count {
                let before = dense[max(i - 1, 0)], after = dense[min(i + 1, dense.count - 1)]
                let run = max(hypot(after.0 - before.0, after.1 - before.1), 0.0001)
                let ends = Ease.clamp(min(sums[i], total - sums[i]) / 0.06)
                let off = wave * ends * ends * (3 - 2 * ends) * sin(2 * .pi * sums[i] / 0.27 + phase)
                waved[i] = (dense[i].0 - (after.1 - before.1) / run * off, dense[i].1 + (after.0 - before.0) / run * off)
            }
            self.init(dense: waved)
        }

        /// A path through the middles of the cells, its corners rounded, and wavering.
        init(cells: [(Int, Int)], wave: Double, phase: Double) {
            let corners = cells.map { SlimeMoldMaze.cell($0.0, $0.1) }
            var coarse = [corners[0]]
            if corners.count > 2 {
                for i in 1..<(corners.count - 1) {
                    let a = corners[i - 1], b = corners[i], c = corners[i + 1]
                    let ab = hypot(a.0 - b.0, a.1 - b.1), bc = hypot(c.0 - b.0, c.1 - b.1)
                    let r = min(0.075, ab / 2, bc / 2)
                    let from = (b.0 + (a.0 - b.0) / ab * r, b.1 + (a.1 - b.1) / ab * r)
                    let to = (b.0 + (c.0 - b.0) / bc * r, b.1 + (c.1 - b.1) / bc * r)
                    for k in 0...6 {
                        let s = Double(k) / 6
                        let w0 = (1 - s) * (1 - s), w1 = 2 * (1 - s) * s, w2 = s * s
                        coarse.append((w0 * from.0 + w1 * b.0 + w2 * to.0, w0 * from.1 + w1 * b.1 + w2 * to.1))
                    }
                }
            }
            coarse.append(corners[corners.count - 1])
            var sums = [0.0]
            for i in 1..<coarse.count { sums.append(sums[i - 1] + hypot(coarse[i].0 - coarse[i - 1].0, coarse[i].1 - coarse[i - 1].1)) }
            let total = sums[sums.count - 1]
            let n = max(2, Int(total / 0.012))
            var dense: [(Double, Double)] = []
            var j = 1
            for k in 0...n {
                let s = total * Double(k) / Double(n)
                while j < coarse.count - 1 && sums[j] < s { j += 1 }
                let span = sums[j] - sums[j - 1]
                let f = span > 0 ? (s - sums[j - 1]) / span : 0
                dense.append((coarse[j - 1].0 + (coarse[j].0 - coarse[j - 1].0) * f, coarse[j - 1].1 + (coarse[j].1 - coarse[j - 1].1) * f))
            }
            self.init(waving: dense, wave: wave, phase: phase)
        }

        /// The point `f` of the way along and the way it runs there.
        func at(_ f: Double) -> (x: Double, y: Double, run: Double) {
            let goal = f * length
            var i = 1
            while i < points.count - 1 && reached[i] < goal { i += 1 }
            let before = points[i - 1], after = points[min(i + 1, points.count - 1)]
            return (points[i].0, points[i].1, atan2(after.1 - before.1, after.0 - before.0))
        }

        /// How far along the point nearest `p` is, as a length.
        func nearest(_ p: (Double, Double)) -> Double {
            var best = 0, bestD = Double.infinity
            for (i, q) in points.enumerated() where hypot(q.0 - p.0, q.1 - p.1) < bestD {
                bestD = hypot(q.0 - p.0, q.1 - p.1)
                best = i
            }
            return reached[best]
        }

        /// The first `f` of the way along, each point with its length so far.
        func samples(upTo f: Double) -> [(x: Double, y: Double, s: Double)] {
            let end = f * length
            var out = [(x: points[0].0, y: points[0].1, s: 0.0)]
            for i in 1..<points.count {
                if reached[i] <= end {
                    out.append((points[i].0, points[i].1, reached[i]))
                } else {
                    let span = reached[i] - reached[i - 1]
                    let k = span > 0 ? (end - reached[i - 1]) / span : 0
                    out.append((points[i - 1].0 + (points[i].0 - points[i - 1].0) * k, points[i - 1].1 + (points[i].1 - points[i - 1].1) * k, end))
                    break
                }
            }
            return out
        }
    }

    /// One tube of the network: when it starts to grow and how fast, when it draws back and how
    /// long that takes (the route to the exit never does), and its girth.
    private struct Tendril {
        let route: Route
        let starts: Double, pace: Double
        let pullAt: Double, takes: Double
        let keeps: Bool
        let girth: Double, phase: Double
        /// Whether it is left out at small sizes.
        let minor: Bool
    }

    private static let tendrils: [Tendril] = {
        let route = Tendril(
            route: Route(cells: [(0, 1), (0, 2), (1, 2), (1, 3), (2, 3), (3, 3), (3, 2), (2, 2), (2, 1), (3, 1)], wave: 0.007, phase: 0.3),
            starts: 0.25, pace: 0.55, pullAt: 0, takes: 1, keeps: true, girth: 0.04, phase: 0.4, minor: false)
        let reaches = route.starts + route.route.length / route.pace
        // The blind corridors: up from the entrance and along the top, where it forks, and a spur below.
        let top = Tendril(route: Route(cells: [(0, 1), (0, 0), (1, 0)], wave: 0.006, phase: 1.1),
                          starts: 0.3, pace: 0.3, pullAt: reaches + 0.5, takes: 0.8, keeps: false, girth: 0.034, phase: 1.9, minor: false)
        let forks = top.starts + top.route.length / top.pace
        let pocket = Tendril(route: Route(cells: [(1, 0), (1, 1)], wave: 0.006, phase: 2.2),
                             starts: forks, pace: 0.3, pullAt: reaches + 0.2, takes: 0.5, keeps: false, girth: 0.03, phase: 0.7, minor: false)
        let along = Tendril(route: Route(cells: [(1, 0), (2, 0)], wave: 0.006, phase: 3.0),
                            starts: forks, pace: 0.3, pullAt: reaches + 0.3, takes: 0.5, keeps: false, girth: 0.03, phase: 2.6, minor: false)
        let spur = Tendril(route: Route(cells: [(0, 2), (0, 3)], wave: 0.006, phase: 4.2),
                           starts: route.starts + route.route.nearest(cell(0, 2)) / route.pace, pace: 0.3,
                           pullAt: reaches + 0.4, takes: 0.5, keeps: false, girth: 0.03, phase: 3.4, minor: false)
        var all = [route, top, pocket, along, spur]

        // Small twigs fanning off the tubes midway along a corridor, which probe a little and draw back.
        let twigs: [(parent: Int, at: Double, side: Double, length: Double)] = [
            (0, 0.167, 1, 0.055), (0, 0.389, -1, 0.06), (0, 0.611, 1, 0.055), (0, 0.833, -1, 0.06),
            (1, 0.25, -1, 0.05), (1, 0.75, 1, 0.05),
        ]
        for (i, twig) in twigs.enumerated() {
            let parent = all[twig.parent]
            let here = parent.route.at(twig.at)
            let first = here.run + twig.side * 50 * .pi / 180
            var pts = [(here.x, here.y)]
            for k in 1...5 {
                let turn = first - twig.side * 0.7 * Double(k) / 5
                pts.append((pts[k - 1].0 + cos(turn) * twig.length / 5, pts[k - 1].1 + sin(turn) * twig.length / 5))
            }
            all.append(Tendril(route: Route(dense: pts), starts: parent.starts + twig.at * parent.route.length / parent.pace, pace: 0.22,
                               pullAt: reaches + 0.1 + 0.1 * Double(i), takes: 0.45, keeps: false, girth: 0.026, phase: Double(i), minor: true))
        }
        return all
    }()
    /// When the route's tube reaches the exit.
    private static let found = tendrils[0].starts + tendrils[0].route.length / tendrils[0].pace

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let small = u.side < 30
        let floorWidth = Double(UnitSquare.hairline) / Double(u.side)

        // At small sizes the walls go finer than the usual hairline so that the clay route stands out.
        let fine = UnitSquare(size, floors: false)
        for (i, wall) in walls.enumerated() {
            if small { fine.stroke(context, fine.polyline(wall), tint, 0.032) }
            else { u.stroke(context, u.polyline(wall), tint, i < 2 ? 0.055 : 0.05) }
        }

        let fade = 1 - Ease.inOut((t - fadeAt) / 0.9)
        let thick = Ease.inOut((t - (found + 0.2)) / 1.6)

        // Each tube is a ribbon that thins toward its tip and bulges here and there.
        for tube in tendrils where !(small && tube.minor) {
            let grown = Ease.clamp((t - tube.starts) * tube.pace / tube.route.length)
            let pull = tube.keeps ? 0 : Ease.inOut((t - tube.pullAt) / tube.takes)
            let f = grown * (1 - pull)
            let alpha = tube.keeps ? fade : 1
            guard f > 0.003 && alpha > 0 else { continue }
            let scale = tube.keeps ? 1 + 0.55 * thick : 1 - 0.4 * pull
            let marks = tube.route.samples(upTo: f)
            let end = f * tube.route.length
            var left: [(Double, Double)] = [], right: [(Double, Double)] = []
            var tip = (x: 0.0, y: 0.0, r: 0.0)
            for (i, m) in marks.enumerated() {
                let before = marks[max(i - 1, 0)], after = marks[min(i + 1, marks.count - 1)]
                let run = max(hypot(after.x - before.x, after.y - before.y), 0.0001)
                let bulge = 1 + 0.16 * sin(2 * .pi * m.s / 0.2 + tube.phase)
                let narrowing = 1 - 0.3 * m.s / tube.route.length
                let point = 0.5 + 0.5 * Ease.clamp((end - m.s) / 0.05)
                let w = max(tube.girth * scale * bulge * narrowing * point, floorWidth) / 2
                left.append((m.x - (after.y - before.y) / run * w, m.y + (after.x - before.x) / run * w))
                right.append((m.x + (after.y - before.y) / run * w, m.y - (after.x - before.x) / run * w))
                tip = (m.x, m.y, w)
            }
            var path = u.polyline(left + right.reversed())
            path.closeSubpath()
            context.fill(path, with: .color(clay.opacity(alpha)))
            context.fill(u.circle(tip.x, tip.y, tip.r), with: .color(clay.opacity(alpha)))
        }

        // The seed on its food at the entrance, and the dot at the exit, which swells when reached.
        context.fill(blob(u, seed, 0.06), with: .color(clay))
        let swell = Ease.outBack((t - found) / 0.5) * fade
        context.fill(blob(u, food, 0.04 + 0.03 * max(0, swell)), with: .color(clay))
    }
}

/// Fern unfurling: a fiddlehead, a stem with a clay spiral at its top, slowly unrolls from the
/// base of the coil outwards, the coil shrinking toward the tip until the frond arches over,
/// and its clay leaflets then open along it, base first. The open frond fades as a new
/// fiddlehead fades in.
enum FernUnfurling {
    static let duration = 6.4

    private static let length = 1.6, stipe = 0.42
    private static let segments = 80
    /// When the unrolling starts, how long it takes to reach the tip, and how long each
    /// stretch takes to loosen.
    private static let startsAt = 0.3, sweeps = 2.9, loosens = 1.0
    private static let fadeAt = 5.6
    /// The coil's radius where it starts and at its tip.
    private static let outer = 0.21, inner = 0.06
    private static let tighten = (outer - inner) / (length - stipe)
    /// The foot of the stem, and how far the frond is magnified: a fiddlehead is shown large and
    /// the open frond smaller, so each fills the square.
    private static let foot = (x: 0.28, y: 0.9), zoomIn = 1.3, zoomOut = 0.68

    /// How tightly the frond turns at arc length `s` while coiled, and when open.
    private static func curl(_ s: Double) -> Double {
        s < stipe ? 0.35 : 1 / (outer - tighten * min(s - stipe, (length - stipe) * 0.999))
    }
    private static func arch(_ s: Double) -> Double { s < stipe ? 0.35 : 1.4 }
    /// When the frond at `s` has unrolled.
    private static func opens(_ s: Double) -> Double { startsAt + sweeps * max(0, s - stipe) / (length - stipe) }

    /// The leaflets: where each pair sits along the frond and how long it grows.
    private static let leaflets: [(s: Double, reach: Double)] = (0..<9).map { j in
        let x = (Double(j) + 0.5) / 9
        return (stipe + 0.12 + (length - stipe - 0.2) * x,
                0.34 * pow(sin(.pi * (0.12 + 0.88 * pow(x, 0.8))), 0.8) * (1 - 0.5 * x))
    }

    /// The frond's spine at time `t`, from its foot up, in frond units, with its heading at each point.
    private static func spine(_ t: Double) -> (p: [(Double, Double)], a: [Double]) {
        let ds = length / Double(segments)
        var x = 0.0, y = 0.0, a = 0.0
        var p = [(0.0, 0.0)], heads = [0.0]
        for i in 0..<segments {
            let s = (Double(i) + 0.5) * ds
            let loose = Ease.inOut((t - opens(s)) / loosens)
            let k = curl(s) + (arch(s) - curl(s)) * loose
            a += k * ds / 2
            x += sin(a) * ds
            y -= cos(a) * ds
            a += k * ds / 2
            p.append((x, y))
            heads.append(a)
        }
        return (p, heads)
    }

    /// Draws the frond as it stands at time `t` of its unfurling, at `alpha`.
    private static func frond(_ context: GraphicsContext, _ u: UnitSquare, at t: Double, alpha: Double, tint: Color) {
        let small = u.side < 30
        let ds = length / Double(segments)
        let smooth = Ease.clamp((t - 0.4) / 2.8)
        let z = zoomOut + (zoomIn - zoomOut) * (1 - smooth * smooth * (3 - 2 * smooth))
        let (p, heads) = spine(t)
        let floorWidth = Double(UnitSquare.hairline) / Double(u.side)
        let place = { (i: Int) -> (Double, Double) in (foot.x + z * p[i].0, foot.y + z * p[i].1) }

        // Leaflets first, so the spine lies over their feet.
        for (j, leaf) in leaflets.enumerated() where !small || j % 2 == 0 {
            let open = Ease.inOut((t - opens(leaf.s) - 0.5) / 0.9)
            if small && open < 0.2 { continue }
            let i = min(segments, Int((leaf.s / ds).rounded()))
            let from = (foot.x + z * p[i].0, foot.y + z * p[i].1)
            for side in [-1.0, 1.0] {
                // The side the frond curls toward is crowded, so its leaflets are shorter.
                let long = leaf.reach * z * (0.2 + 0.8 * open) * (side > 0 ? 0.68 : 1)
                let width = max(long * (small ? 0.5 : 0.36), floorWidth)
                let turn = heads[i] + side * (12 + 58 * open) * .pi / 180
                let d = (sin(turn), -cos(turn))
                let tip = (from.0 + long * d.0, from.1 + long * d.1)
                let mid = (from.0 + long * d.0 / 2, from.1 + long * d.1 / 2)
                var leaflet = Path()
                leaflet.move(to: u.pt(from.0, from.1))
                leaflet.addQuadCurve(to: u.pt(tip.0, tip.1), control: u.pt(mid.0 - d.1 * width, mid.1 + d.0 * width))
                leaflet.addQuadCurve(to: u.pt(from.0, from.1), control: u.pt(mid.0 + d.1 * width, mid.1 - d.0 * width))
                context.fill(leaflet, with: .color(clay.opacity(alpha)))
            }
        }

        // The spine as a ribbon that thins toward the tip: ink where it has unrolled, clay
        // where it is still coiled.
        let cut = min(length, stipe + max(0, t - startsAt - loosens / 2) / sweeps * (length - stipe))
        func ribbon(_ from: Double, _ to: Double) -> Path {
            func at(_ s: Double) -> (x: Double, y: Double, a: Double, s: Double) {
                let f = min(s / ds, Double(segments) - 1e-9)
                let i = Int(f), r = f - Double(i)
                return (foot.x + z * (p[i].0 + (p[i + 1].0 - p[i].0) * r), foot.y + z * (p[i].1 + (p[i + 1].1 - p[i].1) * r),
                        heads[i] + (heads[i + 1] - heads[i]) * r, s)
            }
            var marks = [at(from)]
            for i in 0...segments {
                let s = Double(i) * ds
                if s > from + 1e-9 && s < to - 1e-9 { marks.append((foot.x + z * p[i].0, foot.y + z * p[i].1, heads[i], s)) }
            }
            marks.append(at(to))
            var left: [(Double, Double)] = [], right: [(Double, Double)] = []
            for m in marks {
                let w = max(0.075 - 0.03 * pow(m.s / length, 1.5), floorWidth) / 2
                left.append((m.x + cos(m.a) * w, m.y + sin(m.a) * w))
                right.append((m.x - cos(m.a) * w, m.y - sin(m.a) * w))
            }
            var path = u.polyline(left + right.reversed())
            path.closeSubpath()
            return path
        }
        if cut > 0.001 { context.fill(ribbon(0, cut), with: .color(tint.opacity(alpha))) }
        if cut >= length - 0.001 {
            let end = place(segments)
            context.fill(u.circle(end.0, end.1, max(0.045, floorWidth) / 2), with: .color(tint.opacity(alpha)))
        }
        if cut < length - 0.001 { context.fill(ribbon(max(0, cut - 0.004), length), with: .color(clay.opacity(alpha))) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // At the end the open frond fades as the next fiddlehead, which is the start, fades in.
        let swap = Ease.clamp((t - fadeAt) / (duration - fadeAt))
        if swap < 1 { frond(context, u, at: t, alpha: 1 - swap, tint: tint) }
        if swap > 0 { frond(context, u, at: 0, alpha: swap, tint: tint) }
    }
}

/// Diatom: a pennate diatom, a boat-shaped silica shell of two overlapping halves, turns on its
/// long axis through a half turn: the face with its central line and ribs narrows and slides
/// to one side as the shell shows its rim, which stands as a plain band with the seam between
/// the halves, and then the other half comes round. The two halves are alike, so a half turn
/// ends where it began.
enum Diatom {
    static let duration = 5.0

    /// Half the shell's length, the face's half width, and half its depth (from one half to the other).
    private static let a = 0.38, halfWidth = 0.14, depth = 0.1
    private static let tilt = -22.0 * Double.pi / 180
    private static let along: [Double] = (0...32).map { -a + 2 * a * Double($0) / 32 }
    /// The striae, evenly spaced either side of the middle (where the nodule is).
    private static let ribs: [Double] = [-0.8, -0.6, -0.4, -0.2, 0.2, 0.4, 0.6, 0.8].map { $0 * a }
    private static let ribsSmall: [Double] = [-0.65, -0.25, 0.25, 0.65].map { $0 * a }
    /// Where the overlap between the halves lies on the rim.
    private static let seam = 0.06

    /// A point along the shell and across it, `x` and `y`, placed in the square.
    private static func place(_ x: Double, _ y: Double) -> (Double, Double) {
        (0.5 + x * cos(tilt) - y * sin(tilt), 0.5 + x * sin(tilt) + y * cos(tilt))
    }
    /// The face's half width at `x` along the shell.
    private static func width(_ x: Double) -> Double { halfWidth * pow(max(0, 1 - (x / a) * (x / a)), 0.8) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let small = u.side < 30
        let x = t / duration
        // A half turn, slowing a little as each face comes square on.
        let turn = Double.pi * (x - 0.55 / (2 * Double.pi) * sin(2 * Double.pi * x))
        let across = abs(cos(turn)), rim = depth * abs(sin(turn))
        // Whichever half faces us stands nearer and the other behind it; either way the faces
        // sit a rim's depth up and down from the middle.
        let front = cos(turn) >= 0 ? 1.0 : -1.0
        let nearOffset = -front * depth * sin(turn), farOffset = -nearOffset

        func face(_ offset: Double) -> Path {
            let edge = along.map { place($0, offset - width($0) * across) } + along.reversed().map { place($0, offset + width($0) * across) }
            var path = u.polyline(edge)
            path.closeSubpath()
            return path
        }
        // The whole shell's outline: the faces' outer edges joined across at the ends.
        let outline = along.map { place($0, -(rim + width($0) * across)) } + along.reversed().map { place($0, rim + width($0) * across) }
        var shell = u.polyline(outline)
        shell.closeSubpath()
        let near = face(nearOffset)

        context.drawLayer { layer in
            layer.fill(shell, with: .color(clay))
            u.stroke(layer, shell, tint, 0.055)
            u.stroke(layer, face(farOffset), tint.opacity(0.5), 0.04)
            // The seam between the halves, seen on the rim.
            let seen = sin(turn) * sin(turn)
            for at in [seam - 0.035, seam + 0.035] {
                let reach = rim + width(at) * across
                u.stroke(layer, u.line(place(at, -reach), place(at, reach)), ivory.opacity(0.9 * seen), 0.03)
            }

            // The near half over all of that: clear what lies behind it, then clay and linework.
            layer.blendMode = .destinationOut
            layer.fill(near, with: .color(.black))
            layer.blendMode = .normal
            layer.fill(near, with: .color(clay))
            u.stroke(layer, near, tint, 0.055)
            // The markings stay inside the face and fade as it turns edge on.
            var marks = layer
            marks.clip(to: near)
            marks.opacity = Ease.clamp((across - 0.2) / 0.3)
            let o = nearOffset
            // Striae run straight across from the raphe to near the margin, parallel to one another.
            for rx in small ? ribsSmall : ribs {
                let near = 0.14 * width(rx) * across, far = 0.9 * width(rx) * across
                for side in [-1.0, 1.0] {
                    u.stroke(marks, u.line(place(rx, o + side * near), place(rx, o + side * far)), tint, small ? 0.036 : 0.026)
                }
            }
            u.stroke(marks, u.line(place(-0.8 * a, o), place(0.8 * a, o)), ivory, 0.026)
            u.stroke(marks, u.line(place(-0.05, o), place(0.05, o)), ivory, 0.06)
        }
    }
}
