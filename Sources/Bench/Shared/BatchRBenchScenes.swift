// BatchRBenchScenes.swift
// ScienceStatus — at the bench and on paper: bands running through a
// capillary, a microtome's ribbon of sections, a marker going twice round a
// Möbius strip, and a belief updated by evidence.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Capillary electrophoresis: the classic set-up, a thin capillary bridging two
/// open vials of buffer with its ends dipped in, and a small detector window
/// near the outlet end. A plug of sample enters at the inlet and pulls apart
/// into three bands, clay, ink and clay, each migrating at its own speed along
/// the capillary; as each crosses the window the pen beneath it draws a peak,
/// and the trace scrolls left, the old peaks dwindling into its left end. The
/// bands run down into the far vial and the next plug enters.
enum CapillaryElectrophoresis {
    static let duration = 5.0
    /// The capillary: its ends dip into the vials at `inlet` and `outlet`, its
    /// tips at `tip`; it runs along at `top` and turns its corners on `bend`.
    private static let inlet = 0.12, outlet = 0.88, top = 0.22, tip = 0.6, bend = 0.07
    private static let rise = tip - top - bend, arc = Double.pi * bend / 2, run = outlet - inlet - 2 * bend
    private static let length = 2 * rise + 2 * arc + run
    /// The vials: their rims, the buffer's level, and their bottoms.
    private static let rim = 0.44, buffer = 0.52, bottom = 0.66, cup = 0.085
    private static let detector = 0.74
    private static let reach = rise + arc + (detector - inlet - bend)
    /// When the plug enters, and the three bands: how long each takes to reach
    /// the window, whether it is clay or ink, and its peak's height.
    private static let injectAt = 0.3
    private static let bands: [(delay: Double, clay: Bool, height: Double)] = [
        (1.3, true, 0.17), (2.0, false, 0.12), (2.8, true, 0.15),
    ]
    private static let speeds: [Double] = bands.map { reach / $0.delay }
    /// The trace: its baseline, its left end, how many seconds of signal it
    /// shows, and how far in from its left end the peaks dwindle away.
    private static let base = 0.9, traceLeft = 0.08, window = 4.0, dwindle = 0.18
    /// The detector's signal over one loop, every `step` s; it wraps round, so the
    /// trace is periodic by construction. Later bands are broader, as in a real run.
    private static let step = 0.01
    private static let signal: [Double] = (0..<Int((duration / step).rounded())).map { i in
        let s = Double(i) * step
        var y = 0.0
        for (k, band) in bands.enumerated() {
            let width = 0.08 + 0.015 * Double(k)
            for n in -1...1 {
                let d = (s - injectAt - band.delay - Double(n) * duration) / width
                y += band.height * exp(-d * d)
            }
        }
        return y
    }

    private static func level(_ s: Double) -> Double {
        let count = Double(signal.count)
        var x = (s / step).truncatingRemainder(dividingBy: count)
        if x < 0 { x += count }
        let i = Int(x), f = x - Double(i)
        return signal[i % signal.count] * (1 - f) + signal[(i + 1) % signal.count] * f
    }

    /// The point `s` along the capillary from the inlet's tip, and its heading.
    private static func along(_ s: Double) -> (x: Double, y: Double, angle: Double) {
        if s < rise { return (inlet, tip - s, -.pi / 2) }
        var d = s - rise
        if d < arc {
            let a = d / bend
            return (inlet + bend - bend * cos(a), top + bend - bend * sin(a), a - .pi / 2)
        }
        d -= arc
        if d < run { return (inlet + bend + d, top, 0) }
        d -= run
        if d < arc {
            let a = d / bend
            return (outlet - bend + bend * sin(a), top + bend - bend * cos(a), a)
        }
        return (outlet, top + bend + d - arc, .pi / 2)
    }
    private static let capillary: [(Double, Double)] = (0...146).map { k in
        let p = along(length * Double(k) / 146)
        return (p.x, p.y)
    }

    /// An open vial at `x`: two walls and a rounded bottom.
    private static func vial(_ u: UnitSquare, _ x: Double) -> Path {
        var p = Path()
        p.move(to: u.pt(x - cup, rim))
        p.addLine(to: u.pt(x - cup, bottom - 0.05))
        p.addQuadCurve(to: u.pt(x + cup, bottom - 0.05), control: u.pt(x, bottom + 0.05))
        p.addLine(to: u.pt(x + cup, rim))
        return p
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let local = t.truncatingRemainder(dividingBy: duration)

        // The vials, with buffer in them.
        for x in [inlet, outlet] {
            var inside = context
            var body = vial(u, x)
            body.closeSubpath()
            inside.clip(to: body)
            inside.fill(Path(CGRect(x: u.pt(x - cup, 0).x, y: u.pt(0, buffer).y, width: u.len(2 * cup), height: u.len(1))),
                        with: .color(tint.opacity(0.2)))
            u.stroke(context, vial(u, x), tint, 0.045)
        }
        u.stroke(context, u.polyline(capillary), tint, 0.045)

        // The bands of this run and the last, as beads on the capillary, turned
        // with it; each broadens a little as it goes, swells in at the inlet's
        // tip and shrinks away at the outlet's.
        for runIndex in [-1.0, 0.0] {
            let age = local - injectAt - runIndex * duration
            guard age > 0 else { continue }
            for (k, band) in bands.enumerated() {
                let s = speeds[k] * age
                let swell = min(Ease.clamp(age / 0.25), Ease.clamp((length - s) / 0.08))
                guard swell > 0 else { continue }
                let p = along(s), at = u.pt(p.x, p.y)
                var bead = context
                bead.translateBy(x: at.x, y: at.y)
                bead.rotate(by: .radians(p.angle))
                let w = u.len((0.065 + 0.01 * age) * swell), h = u.len(0.12 * swell)
                bead.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: min(w, h) / 2.4),
                          with: .color(band.clay ? clay : tint))
            }
        }

        // The detector's window, a small frame round the capillary near the outlet.
        u.stroke(context, u.capsule(detector, top, 0.1, 0.15, corner: 0.025), tint, 0.035)

        // The electropherogram: the pen sits under the window and the paper runs
        // left, so each band's peak appears as it passes; towards the left end
        // the peaks dwindle into the baseline, so none is cut off there.
        let speed = (detector - traceLeft) / window
        let samples = 72
        let trace = (0...samples).map { i -> (Double, Double) in
            let x = traceLeft + (detector - traceLeft) * Double(i) / Double(samples)
            let fade = Ease.inOut((x - traceLeft) / dwindle)
            return (x, base - fade * level(local - (detector - x) / speed))
        }
        u.stroke(context, u.polyline(trace), tint, 0.035)
        context.fill(u.circle(detector, base - level(local), 0.03), with: .color(clay))
    }
}

/// Microtome ribbon: a paraffin block in its chuck, seen face on, rides down
/// behind the edge of a wedge-shaped knife four times. Each pass shaves one section, which
/// comes out in front of the edge joined to the last, pushing the clay ribbon
/// of sections down and round in a gentle curl; the ribbon sways a little and
/// settles while the block rises for the next pass. Each pass moves the ribbon
/// on by exactly one section, so it runs on out of the square like a conveyor.
enum MicrotomeRibbon {
    static let duration = 5.6
    private static let strokes = 4.0
    /// The knife's edge; a section's length along the ribbon (the block's
    /// height), the joint between sections, and half the ribbon's width.
    private static let edge = 0.40
    private static let section = 0.1, joint = 0.02, half = 0.12
    /// How far above the edge the block rests, and how far it travels.
    private static let clearance = 0.05
    private static let travel = clearance + section
    /// The ribbon's path: straight down from the edge, then a quarter turn to the right.
    private static let drop = 0.12, curl = 0.3

    /// The ribbon's centre line `s` along from the edge, and the way across it.
    private static func spine(_ s: Double) -> (x: Double, y: Double, nx: Double, ny: Double) {
        if s <= drop { return (0.5, edge + s, -1, 0) }
        let arc = curl * .pi / 2
        if s <= drop + arc {
            let phi = .pi - (s - drop) / curl
            return (0.5 + curl + curl * cos(phi), edge + drop + curl * sin(phi), cos(phi), sin(phi))
        }
        return (0.5 + curl + (s - drop - arc), edge + drop + curl, 0, 1)
    }

    /// One section, from `a` to `b` along the ribbon; `sway` bends the ribbon
    /// about where it leaves the edge, more the further along it is.
    private static func piece(_ u: UnitSquare, from a: Double, to b: Double, sway: Double) -> Path {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for j in 0...4 {
            let s = a + (b - a) * Double(j) / 4
            let p = spine(s)
            let angle = sway * min(1, s / 0.8)
            let c = cos(angle), sn = sin(angle)
            func turned(_ x: Double, _ y: Double) -> CGPoint {
                let dx = x - 0.5, dy = y - edge
                return u.pt(0.5 + dx * c - dy * sn, edge + dx * sn + dy * c)
            }
            left.append(turned(p.x + half * p.nx, p.y + half * p.ny))
            right.append(turned(p.x - half * p.nx, p.y - half * p.ny))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let period = duration / strokes
        let tau = t.truncatingRemainder(dividingBy: period)
        let down = Ease.inOut((tau - 0.1) / 0.6), up = Ease.inOut((tau - 0.85) / 0.45)
        // How much of this pass's section is out past the edge; the ribbon
        // only moves while the block is crossing it.
        let cut = Ease.clamp((travel * down - clearance) / section)
        // A small sway once the push is done, back to nothing by the next pass.
        let settle = Ease.clamp((tau - 0.7) / 0.7)
        let sway = settle > 0 && settle < 1 ? 0.04 * sin(2 * .pi * settle) * (1 - settle) : 0

        // The chuck on its arm, and the block it holds, hidden behind the
        // knife once it is past the edge.
        let top = edge - travel + travel * (down - up)
        u.stroke(context, u.line((0.5, -0.1), (0.5, top - 0.06)), tint, 0.075)
        context.fill(u.capsule(0.5, top - 0.04, 0.36, 0.08, corner: 0.02), with: .color(tint))
        var above = context
        above.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: u.pt(0, edge).y)))
        let block = u.capsule(0.5, top + section / 2, 2 * half, section, corner: 0.012)
        above.fill(block, with: .color(tint.opacity(0.18)))
        u.stroke(above, block, tint, 0.04)

        // The knife: a long wedge, its edge along the top, thick at the left
        // where it is held and tapering to a point at the right.
        var knife = Path()
        knife.addLines([u.pt(0.08, edge), u.pt(0.92, edge), u.pt(0.08, edge + 0.1)])
        knife.closeSubpath()
        context.fill(knife, with: .color(tint))

        // The ribbon: section 0 is the one coming off the edge now.
        for i in 0..<11 {
            let a = (Double(i) - 1 + cut) * section, b = (Double(i) + cut) * section - joint
            guard b > 0 else { continue }
            context.fill(piece(u, from: max(0, a), to: b, sway: sway), with: .color(clay))
        }
    }
}

/// Möbius strip: a broad band seen from in front and a little above, with one
/// half twist: it lies flat round the back and left and turns over gradually
/// across the front and round to the right, and right at the front it is seen
/// edge on, its edges crossing. Its near parts hide its far ones, worked out
/// once, so a frame is a fill, a stroke and the marker. A clay marker runs
/// steadily along the centre line with a tick standing out from the face it
/// is on. After one lap it is back where it started with the tick on the
/// other face; only after the second lap does the tick come back to where it
/// began, and the loop is those two laps. A faint ghost of the marker shows
/// through the band while the band hides it.
enum MobiusStrip {
    static let duration = 6.0
    private typealias Vector = (Double, Double, Double)
    private static let radius = 0.3, halfWidth = 0.13
    /// The view: from in front and `tilt` above.
    private static let tilt = 0.55
    /// The half twist, spread `spread` either side of `twistAt` round from the
    /// front. `twistAt` is set so the band is seen edge on, its edges crossing,
    /// right at the front: that happens where it has turned by `tilt`.
    private static let spread = 2.0
    private static let twistAt = -(2 * spread / .pi) * asin(2 * tilt / .pi - 1)
    private static let pieces = 96
    /// Where the marker starts, round from the front: at the back, right of centre.
    private static let markerFrom = 2.4

    /// How far the band has turned about its centre line, `along` round from the
    /// front (−π to π): 0 lying flat, π flat again but the other way up; and how
    /// fast it is turning there.
    private static func twist(_ along: Double) -> (angle: Double, rate: Double) {
        let x = (along - twistAt) / spread
        if x <= -1 { return (0, 0) }
        if x >= 1 { return (.pi, 0) }
        return (.pi * (0.5 + 0.5 * sin(.pi * x / 2)), .pi * .pi / 4 * cos(.pi * x / 2) / spread)
    }

    /// The band at `along` (any number of laps; each turns it over once more):
    /// the way out from the ring's centre, the way across the band, and its normal.
    private static func frame(_ along: Double) -> (out: Vector, across: Vector, normal: Vector) {
        let laps = ((along + .pi) / (2 * .pi)).rounded(.down)
        let wrapped = along - 2 * .pi * laps
        let phi = wrapped - .pi / 2, a = twist(wrapped).angle + .pi * laps
        let out = (cos(phi), sin(phi), 0.0)
        return (out, (cos(a) * out.0, cos(a) * out.1, sin(a)), (sin(a) * out.0, sin(a) * out.1, -cos(a)))
    }

    /// A point on the band in space: `along` round it, `across` from its centre line.
    private static func point(_ along: Double, _ across: Double) -> Vector {
        let f = frame(along)
        return (radius * f.out.0 + across * f.across.0, radius * f.out.1 + across * f.across.1, across * f.across.2)
    }

    /// How near a point or direction is to the eye, and how high it stands on screen.
    private static func nearness(_ p: Vector) -> Double { -p.1 * cos(tilt) + p.2 * sin(tilt) }
    private static func height(_ p: Vector) -> Double { p.1 * sin(tilt) + p.2 * cos(tilt) }

    /// Where the band's middle goes on screen: its outline's box, centred.
    private static let centre: (x: Double, y: Double) = {
        var x0 = 1.0, x1 = -1.0, y0 = 1.0, y1 = -1.0
        for k in 0..<240 {
            for across in [-halfWidth, halfWidth] {
                let p = point(2 * .pi * Double(k) / 240, across)
                x0 = min(x0, p.0); x1 = max(x1, p.0)
                y0 = min(y0, -height(p)); y1 = max(y1, -height(p))
            }
        }
        return (0.5 - (x0 + x1) / 2, 0.5 - (y0 + y1) / 2)
    }()

    /// Where a point in space lands in the square, and how near it is (larger is nearer).
    private static func screen(_ p: Vector) -> (x: Double, y: Double, depth: Double) {
        (centre.x + p.0, centre.y - height(p), nearness(p))
    }

    private static func cross(_ a: Vector, _ b: Vector) -> Vector {
        (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
    }

    /// Where across the band, at `along`, it is seen edge on (its normal square
    /// to the view), or nil if nowhere: there it folds over on screen and its
    /// outline needs drawing. The normal there is linear in `across`, so this
    /// is one division.
    private static func fold(_ along: Double) -> Double? {
        let phi = along - .pi / 2
        let (a, rate) = twist(along)
        let out = (cos(phi), sin(phi), 0.0), round = (-sin(phi), cos(phi), 0.0)
        let rung = (cos(a) * out.0, cos(a) * out.1, sin(a))
        // How the way across turns as it goes: with the ring, and about the centre line.
        let turning = (-rate * sin(a) * out.0 + cos(a) * round.0, -rate * sin(a) * out.1 + cos(a) * round.1, rate * cos(a))
        let fixed = nearness(cross((radius * round.0, radius * round.1, 0), rung)), lean = nearness(cross(turning, rung))
        guard abs(lean) > 1e-9 else { return nil }
        let across = -fixed / lean
        return abs(across) <= halfWidth ? across : nil
    }

    /// A cover: pieces of the band, their areas and their edges, laid over the
    /// marker to hide what of it lies behind them.
    private struct Cover {
        let areas: Path
        let edges: Path
        let isEmpty: Bool
    }

    /// Everything about the band that does not move, worked out once, in the
    /// square's own units. The band is cut across its width into `pieces`;
    /// each edge is kept only where no nearer piece (its near neighbours aside)
    /// lies over it, which is what painting the pieces back to front would
    /// show, and the kept stretches are joined into a few long lines. The face
    /// is one path: runs of pieces that lie the same way up as single
    /// outlines, and where the band folds over on screen, triangles, all wound
    /// the same way so the overlaps fill once. For the marker on each piece,
    /// what is painted over its dot (nearer pieces outside the seven round it)
    /// and over its tick when the tick points away (those seven as well).
    private struct Shape {
        let face: Path
        let outline: Path
        let over: [Cover]
        let behind: [Cover]
    }

    private static let shape: Shape = {
        typealias Point = (x: Double, y: Double)
        let n = pieces
        func flat(_ p: (x: Double, y: Double, depth: Double)) -> Point { (p.x, p.y) }
        func wind(_ a: Point, _ b: Point, _ c: Point) -> Double { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
        func at(_ i: Int) -> Double { -.pi + 2 * .pi * Double(i) / Double(n) }
        func cg(_ p: Point) -> CGPoint { CGPoint(x: p.x, y: p.y) }
        func add(_ points: [Point], to path: inout Path, closed: Bool) {
            path.move(to: cg(points[0]))
            for p in points.dropFirst() { path.addLine(to: cg(p)) }
            if closed { path.closeSubpath() }
        }

        var quads: [[Point]] = [], depths: [Double] = [], triangles: [[[Point]]] = [], edges: [[[Point]]] = []
        for i in 0..<n {
            let a = at(i), b = at(i + 1)
            let q = [screen(point(a, -halfWidth)), screen(point(b, -halfWidth)), screen(point(b, halfWidth)), screen(point(a, halfWidth))]
            let c = q.map(flat)
            quads.append(c)
            depths.append(q.reduce(0) { $0 + $1.depth } / 4)
            triangles.append([[c[0], c[1], c[2]], [c[0], c[2], c[3]]].map { wind($0[0], $0[1], $0[2]) < 0 ? [$0[0], $0[2], $0[1]] : $0 })
            var lines = [[c[0], c[1]], [c[3], c[2]]]
            // The fold, traced in finer steps and out to where it meets the edge.
            var run: [Point] = []
            var last: (t: Double, v: Double?) = (a, nil)
            for s in 0...4 {
                let t = a + (b - a) * Double(s) / 4, v = fold(t)
                if s > 0, (v == nil) != (last.v == nil) {
                    let from = last.v != nil
                    var lo = last.t, hi = t
                    for _ in 0..<30 {
                        let m = (lo + hi) / 2
                        if (fold(m) != nil) == from { lo = m } else { hi = m }
                    }
                    let end = from ? lo : hi
                    if let w = fold(end) { run.append(flat(screen(point(end, w)))) }
                    if from {
                        if run.count > 1 { lines.append(run) }
                        run = []
                    }
                }
                if let v { run.append(flat(screen(point(t, v)))) }
                last = (t, v)
            }
            if run.count > 1 { lines.append(run) }
            edges.append(lines)
        }

        // Where each edge shows: sampled, and each change refined by halving.
        func inside(_ p: Point, _ j: Int) -> Bool {
            triangles[j].contains { wind($0[0], $0[1], p) > 1e-12 && wind($0[1], $0[2], p) > 1e-12 && wind($0[2], $0[0], p) > 1e-12 }
        }
        func hidden(_ p: Point, _ i: Int) -> Bool {
            (0..<n).contains { j in
                min((i - j + n) % n, (j - i + n) % n) > 2 && depths[j] > depths[i] && inside(p, j)
            }
        }
        var shown: [[Point]] = []
        for i in 0..<n {
            for line in edges[i] {
                for (p, q) in zip(line, line.dropFirst()) {
                    func on(_ s: Double) -> Point { s >= 1 ? q : (x: p.x + (q.x - p.x) * s, y: p.y + (q.y - p.y) * s) }
                    var was = !hidden(p, i), from: Double? = was ? 0 : nil, s0 = 0.0
                    for step in 1...12 {
                        let s1 = Double(step) / 12, now = !hidden(on(s1), i)
                        if now != was {
                            var lo = s0, hi = s1
                            for _ in 0..<24 {
                                let m = (lo + hi) / 2
                                if !hidden(on(m), i) == was { lo = m } else { hi = m }
                            }
                            if let start = from { shown.append([on(start), on(lo)]); from = nil } else { from = hi }
                        }
                        was = now
                        s0 = s1
                    }
                    if let start = from { shown.append([on(start), q]) }
                }
            }
        }

        // The shown stretches joined end to end into lines.
        func same(_ a: Point, _ b: Point) -> Bool { abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
        var outline = Path()
        var loose = shown
        while var chain = loose.popLast() {
            var grew = true
            while grew {
                grew = false
                if let k = loose.firstIndex(where: { same($0[0], chain[chain.count - 1]) }) {
                    chain.append(loose.remove(at: k)[1]); grew = true
                } else if let k = loose.firstIndex(where: { same($0[1], chain[chain.count - 1]) }) {
                    chain.append(loose.remove(at: k)[0]); grew = true
                } else if let k = loose.firstIndex(where: { same($0[1], chain[0]) }) {
                    chain.insert(loose.remove(at: k)[0], at: 0); grew = true
                } else if let k = loose.firstIndex(where: { same($0[0], chain[0]) }) {
                    chain.insert(loose.remove(at: k)[1], at: 0); grew = true
                }
            }
            let closed = chain.count > 2 && same(chain[0], chain[chain.count - 1])
            add(closed ? Array(chain.dropLast()) : chain, to: &outline, closed: closed)
        }

        // The face: which way up each piece lies on screen, 0 where it folds.
        var face = Path()
        let way = quads.map { c -> Int in
            let w1 = wind(c[0], c[1], c[2]), w2 = wind(c[0], c[2], c[3])
            return w1 > 0 && w2 > 0 ? 1 : w1 < 0 && w2 < 0 ? -1 : 0
        }
        var i = 0
        while i < n {
            guard way[i] != 0 else {
                for t in triangles[i] { add(t, to: &face, closed: true) }
                i += 1
                continue
            }
            var j = i
            while j + 1 < n && way[j + 1] == way[i] { j += 1 }
            let ring = [quads[i][0]] + (i...j).map { quads[$0][1] } + [quads[j][2]] + (i...j).reversed().map { quads[$0][3] }
            add(way[i] > 0 ? ring : ring.reversed(), to: &face, closed: true)
            i = j + 1
        }

        // The covers for the marker on each piece, kept to the pieces that come near it.
        func box(_ points: [Point], _ m: Double) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
            (points.map(\.x).min()! - m, points.map(\.y).min()! - m, points.map(\.x).max()! + m, points.map(\.y).max()! + m)
        }
        let reach = quads.map { box($0, 0.04) }
        func cover(_ members: [Int]) -> Cover {
            var areas = Path(), lines = Path()
            for j in members {
                for t in triangles[j] { add(t, to: &areas, closed: true) }
                for line in edges[j] { add(line, to: &lines, closed: false) }
            }
            return Cover(areas: areas, edges: lines, isEmpty: members.isEmpty)
        }
        var over: [Cover] = [], behind: [Cover] = []
        for k in 0..<n {
            let round = (-3...3).map { (k + $0 + n) % n }
            let high = round.map { depths[$0] }.max()!, low = round.map { depths[$0] }.min()!
            let marker = box([at(k), (at(k) + at(k + 1)) / 2, at(k + 1)].map { flat(screen(point($0, 0))) }, 0.14)
            let near = (0..<n).filter {
                let r = reach[$0]
                return r.x0 < marker.x1 && marker.x0 < r.x1 && r.y0 < marker.y1 && marker.y0 < r.y1
            }
            over.append(cover(near.filter { !round.contains($0) && depths[$0] > high }))
            behind.append(cover(near.filter { round.contains($0) || depths[$0] >= low }))
        }
        return Shape(face: face, outline: outline, over: over, behind: behind)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The band is kept in the square's units and laid down scaled, as it is.
        let square = CGAffineTransform(a: u.side, b: 0, c: 0, d: u.side, tx: u.origin.x, ty: u.origin.y)
        let line = StrokeStyle(lineWidth: max(0.06, UnitSquare.hairline / u.side), lineCap: .round, lineJoin: .round)

        // The marker on the centre line, twice round in a loop, its tick along
        // the band's normal: the normal comes back to itself only after two laps.
        let along = markerFrom + 4 * .pi * t / duration
        let p = point(along, 0), normal = frame(along).normal
        let at = screen(p)
        let tip = screen((p.0 + 0.11 * normal.0, p.1 + 0.11 * normal.1, p.2 + 0.11 * normal.2))
        let facing = tip.depth >= at.depth
        let wrapped = along - 2 * .pi * ((along + .pi) / (2 * .pi)).rounded(.down)
        let k = Int((wrapped + .pi) / (2 * .pi) * Double(pieces)) % pieces
        let over = shape.over[k]
        func tick(_ c: GraphicsContext, _ alpha: Double) {
            u.stroke(c, u.line((at.x, at.y), (tip.x, tip.y)), clay.opacity(alpha), 0.035)
        }
        func dot(_ c: GraphicsContext, _ alpha: Double) {
            c.fill(u.circle(at.x, at.y, 0.045), with: .color(clay.opacity(alpha)))
        }
        func hide(_ c: GraphicsContext, _ cover: Cover) {
            var erase = c
            erase.concatenate(square)
            erase.blendMode = .destinationOut
            erase.fill(cover.areas, with: .color(.black))
            erase.stroke(cover.edges, with: .color(.black), style: line)
        }

        // The band: its face one faint tone, then its edges.
        var band = context
        band.concatenate(square)
        band.fill(shape.face, with: .color(tint.opacity(0.14)))
        let shows = facing && over.isEmpty
        // A ghost of the marker, seen through the band when the band hides it.
        if !shows {
            tick(context, 0.35)
            dot(context, 0.35)
        }
        band.stroke(shape.outline, with: .color(tint), style: line)
        if shows {
            tick(context, 1)
            dot(context, 1)
            return
        }
        // Otherwise the marker is drawn in a small layer and the pieces over
        // it are cleared from it: over a tick pointing away, the pieces round
        // it as well as the nearer ones.
        let corner = u.pt(min(at.x, tip.x) - 0.06, min(at.y, tip.y) - 0.06)
        var small = context
        small.clip(to: Path(CGRect(x: corner.x, y: corner.y, width: u.len(abs(at.x - tip.x) + 0.12), height: u.len(abs(at.y - tip.y) + 0.12))))
        small.drawLayer { layer in
            tick(layer, 1)
            if !facing { hide(layer, shape.behind[k]) }
            dot(layer, 1)
            if !over.isEmpty { hide(layer, over) }
        }
    }
}

/// Bayesian update: a faint ink prior, Beta(2, 2), over a baseline. Six
/// observations land one by one in a row beneath it, filled for a success and
/// open for a failure, and after each the clay posterior, Beta(2 + k, 2 + n − k),
/// moves to its new shape; with this evidence it drifts right and grows taller
/// and narrower. It holds, then the dots fade and the posterior settles back
/// onto the prior and fades into it.
enum BayesianUpdate {
    static let duration = 5.6
    /// The evidence in order: 1 a success, 0 a failure.
    private static let observations = [1, 1, 0, 1, 1, 1]
    private static let arrive: [Double] = observations.indices.map { 0.5 + 0.45 * Double($0) }
    private static let resetAt = 4.2, resetFor = 0.9
    private static let left = 0.08, right = 0.92, base = 0.74, tallest = 0.5, row = 0.87
    private static let grid = 80

    /// The Beta(a, b) density at x; for a, b > 1 it is zero at both ends.
    private static func density(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard x > 0, x < 1 else { return 0 }
        return exp(lgamma(a + b) - lgamma(a) - lgamma(b) + (a - 1) * log(x) + (b - 1) * log(1 - x))
    }

    /// The prior, then the posterior after each observation, as heights on the
    /// grid, all on one scale: the tallest peak is `tallest` high.
    private static let curves: [[Double]] = {
        var params: [(a: Double, b: Double)] = [(2, 2)]
        for o in observations {
            let p = params[params.count - 1]
            params.append((p.a + Double(o), p.b + Double(1 - o)))
        }
        let raw = params.map { p in (0...grid).map { density(p.a, p.b, Double($0) / Double(grid)) } }
        let peak = raw.map { $0.max() ?? 1 }.max() ?? 1
        return raw.map { $0.map { tallest * $0 / peak } }
    }()

    private static func curve(_ u: UnitSquare, _ heights: [Double]) -> Path {
        u.polyline(heights.enumerated().map { j, h in (left + (right - left) * Double(j) / Double(grid), base - h) })
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // How far through the evidence the posterior is (k after k observations),
        // how far it has gone back to the prior, and how much it shows.
        var progress = 0.0
        for a in arrive { progress += Ease.inOut((t - a - 0.08) / 0.4) }
        let back = Ease.inOut((t - resetAt) / resetFor)
        let shown = Ease.clamp((t - arrive[0] - 0.05) / 0.3) * (1 - Ease.clamp((t - 4.95) / 0.3))
        let i = min(Int(progress), observations.count - 1), f = progress - Double(i)
        let posterior = curves[0].indices.map { j in
            let h = curves[i][j] * (1 - f) + curves[i + 1][j] * f
            return h * (1 - back) + curves[0][j] * back
        }

        u.stroke(context, u.line((left, base), (right, base)), tint, 0.045)
        u.stroke(context, curve(u, curves[0]), tint.opacity(0.5), 0.04)
        if shown > 0 { u.stroke(context, curve(u, posterior), clay.opacity(shown), 0.06) }

        // The observations, popping in one by one and fading at the reset.
        let fade = 1 - Ease.clamp((t - resetAt) / 0.5)
        for (k, o) in observations.enumerated() {
            let grow = Ease.outBack((t - arrive[k]) / 0.25)
            guard grow > 0.01, fade > 0 else { continue }
            let x = 0.5 + (Double(k) - 2.5) * 0.12
            if o == 1 {
                context.fill(u.circle(x, row, 0.036 * grow), with: .color(tint.opacity(fade)))
            } else {
                u.stroke(context, u.circle(x, row, 0.03 * grow), tint.opacity(fade), 0.03)
            }
        }
    }
}
