// BatchSDataScenes.swift
// Capsid — batch S: a Sanger trace, a model checked against its data, a drop at rest
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Sanger chromatogram: a sequencing trace runs left past a fixed read window, a row
/// of sharp, evenly spaced peaks of varied heights, each with fainter, slightly offset
/// traces of the other dyes beneath it. The peak standing in the window is the one
/// being called and turns clay, handing over to the next as it passes; once a peak
/// has crossed the window's middle a short tick for its base call pops in above it
/// and rides left with it. The peak heights repeat every five peaks and the trace
/// moves exactly five peaks a loop, so the end is the start again.
enum SangerChromatogram {
    static let duration = 5.0

    /// How far apart the peaks stand, how many peaks the height pattern runs
    /// before it repeats (and the trace moves in a loop), and where peak 0 stands at t = 0.
    private static let pitch = 0.14, period = 5, first = 0.2
    /// The trace's ends, its baseline, the height of the tallest peak, and the window's middle.
    private static let left = 0.07, right = 0.93, base = 0.84, tall = 0.5, readX = 0.54
    /// Peak heights for the main trace and the two fainter ones, as shares of `tall`.
    private static let heights: [Double] = [0.95, 0.56, 0.8, 0.4, 0.68]
    private static let bleedA: [Double] = [0.34, 0.5, 0.26, 0.42, 0.3]
    private static let bleedB: [Double] = [0.22, 0.3, 0.42, 0.2, 0.36]
    private static let step = 0.004
    private static let xs: [Double] = (0...Int(((right - left) / step).rounded())).map { left + step * Double($0) }
    /// The trace swells in from the right end and dwindles into the left, so no peak is cut off.
    private static let envelope: [Double] = xs.map { Ease.inOut(($0 - left) / 0.2) * Ease.inOut((right - $0) / 0.15) }

    private static func slot(_ k: Int) -> Int { ((k % period) + period) % period }

    /// One dye's peaks over one repeat of the pattern (`period` peaks), sampled finely once:
    /// the trace only slides, so each frame looks its heights up instead of summing peaks.
    private struct Profile {
        static let samples = 1400
        let heights: [Double]

        init(amps: [Double], shift: Double, width: Double) {
            let span = Double(SangerChromatogram.period) * SangerChromatogram.pitch
            heights = (0..<Self.samples).map { i in
                let s = span * Double(i) / Double(Self.samples)
                var y = 0.0
                for k in -3...(SangerChromatogram.period + 3) {
                    let d = (s - Double(k) * SangerChromatogram.pitch - shift) / width
                    if abs(d) < 3.5 { y += amps[SangerChromatogram.slot(k)] * exp(-d * d) }
                }
                return y
            }
        }

        /// The height `s` along the pattern, which repeats every `period` peaks.
        func height(at s: Double) -> Double {
            let span = Double(SangerChromatogram.period) * SangerChromatogram.pitch
            var f = s / span * Double(Self.samples)
            f -= floor(f / Double(Self.samples)) * Double(Self.samples)
            let i = Int(f), w = f - Double(i)
            return heights[i % Self.samples] * (1 - w) + heights[(i + 1) % Self.samples] * w
        }
    }
    private static let mainProfile = Profile(amps: heights, shift: 0, width: 0.024)
    private static let profileA = Profile(amps: bleedA, shift: 0.035, width: 0.034)
    private static let profileB = Profile(amps: bleedB, shift: -0.03, width: 0.038)

    /// One trace: its profile slid left by `scroll`, peak 0 at `first` when it is nothing.
    private static func trace(_ u: UnitSquare, _ profile: Profile, scroll: Double) -> Path {
        u.polyline(xs.indices.map { i in (xs[i], base - tall * envelope[i] * profile.height(at: xs[i] - first + scroll)) })
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let local = t.truncatingRemainder(dividingBy: duration)
        let scroll = local / duration * Double(period) * pitch
        let speed = Double(period) * pitch / duration

        // The read window: a pale column over the middle of the trace.
        context.fill(u.capsule(readX, 0.5, pitch * 0.95, 0.8, corner: 0.03), with: .color(tint.opacity(0.13)))

        // The other dyes' traces, faint, then the called one.
        u.stroke(context, trace(u, profileB, scroll: scroll), tint.opacity(0.28), 0.032)
        u.stroke(context, trace(u, profileA, scroll: scroll), tint.opacity(0.5), 0.032)
        let main = trace(u, mainProfile, scroll: scroll)

        // The peak in the window is the one being called, clay over its own stretch of the
        // trace (half a pitch either side of it); it hands over to the next as it leaves.
        let lo = Int(floor((left - first + scroll) / pitch)), hi = Int(ceil((right - first + scroll) / pitch))
        var called: [(x: Double, share: Double)] = []
        for k in lo...hi {
            let x = first + Double(k) * pitch - scroll
            let share = Ease.clamp((0.5 - abs(x - readX) / pitch) / 0.08)
            if share > 0 { called.append((x, share)) }
        }
        func stretch(_ x: Double, inset: Double = 0) -> Path {
            Path(CGRect(x: u.pt(x - pitch / 2 + inset, 0).x, y: u.origin.y, width: u.len(pitch - 2 * inset), height: u.side))
        }
        // Ink everywhere else: one plain rectangle clip per gap between the called stretches
        // (an even-odd clip cut the same holes, but drawing through its mask cost far more).
        var from = u.origin.x
        for c in called.sorted(by: { $0.x < $1.x }) + [(x: Double.infinity, share: 0)] {
            let to = c.x.isFinite ? u.pt(c.x - pitch / 2 + 0.004, 0).x : u.origin.x + u.side
            if to > from {
                var inkLayer = context
                inkLayer.clip(to: Path(CGRect(x: from, y: u.origin.y, width: to - from, height: u.side)))
                u.stroke(inkLayer, main, tint, 0.036)
            }
            if c.x.isFinite { from = max(from, u.pt(c.x + pitch / 2 - 0.004, 0).x) }
        }
        for c in called {
            var layer = context
            layer.clip(to: stretch(c.x))
            if c.share < 1 { u.stroke(layer, main, tint.opacity(1 - c.share), 0.036) }
            u.stroke(layer, main, clay.opacity(c.share), 0.036)
        }

        for k in lo...hi {
            let x = first + Double(k) * pitch - scroll
            guard x > left, x < right else { continue }
            let swell = Ease.inOut((x - left) / 0.2) * Ease.inOut((right - x) / 0.15)

            // Its base call pops in above it once the window's middle has passed.
            let pop = Ease.outBack((readX - x) / speed / 0.3)
            if pop > 0.02 {
                let h = 0.12 * swell * pop
                context.fill(u.capsule(x, 0.16, 0.05, h, corner: 0.02), with: .color(tint))
            }
        }
    }
}

/// Posterior predictive check: a histogram of the observed data, a right-skewed
/// hump, stands on a baseline. Replicated datasets simulated from the fitted model
/// draw in over it one after another, each a thin density curve: the newest is clay
/// as it draws in left to right, then fades to faint ink as the next one starts, and
/// the oldest fade out, so four or five curves hug the bars at any moment. Eight
/// replicates make a loop and each is born exactly every eighth of it, so the picture
/// at the end is the picture at the start.
enum PosteriorPredictiveCheck {
    static let duration = 5.0

    private static let left = 0.08, right = 0.92, base = 0.82, tallest = 0.56
    private static let bins = 10, gap = 0.022, sampleSize = 300, replicateSize = 150
    /// How many replicates make a loop, how long each takes to draw in, and how long each lives.
    private static let count = 8, drawFor = 0.5
    private static let interval = duration / Double(count)
    private static let life = 5 * interval
    private static let grid = 64

    /// A small deterministic random source, so the data and the replicates are always the same.
    private struct Source {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// The model's density over 0...1 (not yet normalised): a skewed hump with a long
    /// right tail that tapers to nothing.
    private static func model(_ z: Double) -> Double {
        guard z > 0, z < 1 else { return 0 }
        return pow(z, 3.5) * exp(-z / 0.1) * Ease.clamp((1 - z) / 0.12)
    }
    private static let cumulative: [Double] = {
        var total = 0.0
        return (0...400).map { i in
            total += model(Double(i) / 400)
            return total
        }
    }()
    /// Height of a unit of probability density, so that the model's own peak is `tallest`.
    private static let unit: Double = {
        let area = (cumulative.last ?? 1) / 400
        let peak = ((0...400).map { model(Double($0) / 400) }.max() ?? 1) / area
        return tallest / peak
    }()

    /// `n` values drawn from the model by inverting its cumulative curve.
    private static func sample(_ n: Int, seed: UInt64) -> [Double] {
        var source = Source(state: seed)
        let top = cumulative[cumulative.count - 1]
        return (0..<n).map { _ in
            let target = source.next() * top
            var i = 0
            while i < cumulative.count - 1 && cumulative[i] < target { i += 1 }
            return Double(i) / 400
        }
    }

    /// The observed data's histogram bars, as heights.
    private static let observed: [Double] = {
        var counts = [Double](repeating: 0, count: bins)
        for z in sample(sampleSize, seed: 11) { counts[min(bins - 1, Int(z * Double(bins)))] += 1 }
        return counts.map { $0 * Double(bins) / Double(sampleSize) * unit }
    }()

    /// Each replicate: a smoothed density of a fresh sample from the model.
    private static let replicates: [[(Double, Double)]] = (0..<count).map { j in
        let data = sample(replicateSize, seed: UInt64(101 + 37 * j))
        let bandwidth = 0.06
        return (0...grid).map { i in
            let z = Double(i) / Double(grid)
            var sum = 0.0
            for s in data { let d = (z - s) / bandwidth; sum += exp(-d * d / 2) }
            let density = sum / (Double(replicateSize) * bandwidth * 2.5066)
            return (left + (right - left) * z, base - density * unit)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let local = t.truncatingRemainder(dividingBy: duration)

        // The observed data: a histogram on its baseline.
        let width = (right - left) / Double(bins)
        for (i, h) in observed.enumerated() where h > 0.01 {
            let x = left + width * Double(i) + gap / 2
            context.fill(Path(CGRect(x: u.pt(x, 0).x, y: u.pt(0, base - h).y, width: u.len(width - gap), height: u.len(h))),
                         with: .color(tint.opacity(0.4)))
        }
        u.stroke(context, u.line((left - 0.02, base), (right + 0.02, base)), tint, 0.05)

        // The replicates, oldest first so the newest lies on top.
        for j in -5..<count {
            let age = local - Double(j) * interval
            guard age >= 0, age < life else { continue }
            let points = replicates[((j % count) + count) % count]
            let drawn = Ease.inOut(age / drawFor)
            let out = 1 - Ease.clamp((age - (life - interval)) / interval)
            let fresh = 1 - Ease.inOut((age - 0.45) / 0.17)
            let curve = u.polyline(points).trimmedPath(from: 0, to: drawn)
            if fresh < 1 { u.stroke(context, curve, tint.opacity(0.36 * (1 - fresh) * out), 0.035) }
            if fresh > 0 { u.stroke(context, curve, clay.opacity(fresh * out), 0.05) }
        }
    }
}

/// Contact angle: a goniometer's side view. A short blunt needle with a pear-shaped bead
/// hanging from its tip lowers it to the surface; the bead touches, spreads into a cap
/// with a damped wobble (the cap's volume kept the same) while the needle follows its
/// top down, then lifts away and the thread snaps, leaving a drop at a contact angle of
/// 118 degrees. The clay tangent, a line through the drop's right contact point that
/// crosses the surface, draws in, then the clay arc between surface and tangent. After
/// a hold the stage slides the drop out to the right while the next bead grows on the
/// needle, which is where the loop began; the marks on the stage move exactly two spacings.
enum ContactAngle {
    static let duration = 5.0

    private static let surface = 0.86
    /// The hanging bead's radius, the gap from needle tip to its top, and where the needle rests.
    private static let bead = 0.28, hang = 0.02, tip0 = 0.18
    private static let theta = 118.0 * Double.pi / 180
    /// The settled drop's radius (the same volume as the bead) and how high its centre stands.
    private static let settledR = bead * cbrt(4 / ((1 - cos(theta)) * (1 - cos(theta)) * (2 + cos(theta))))
    private static let settledB = -settledR * cos(theta)
    /// Where the needle's tip is when the bead first touches, and when the cap has spread and
    /// the needle has followed its top down.
    private static let tipTouch = surface - 2 * bead - hang
    private static let tipHold = surface - settledR - settledB - hang
    /// The story's times: the needle sets off, the bead touches, the needle lifts away and
    /// the thread snaps, the tangent and arc draw in, the stage slides.
    private static let setOff = 0.3, touch = 1.0, lift = 1.3, snap = 1.6
    private static let tangentAt = 2.0, arcAt = 2.4, slideAt = 3.9, growAt = 4.1
    private static let slide = 0.9, spacing = 0.45, tube = 0.055

    /// The radius of a cap whose centre stands `b` above the surface, with the bead's volume.
    private static func radius(centreHeight b: Double) -> Double {
        guard b < bead else { return bead }
        let target = 4 * bead * bead * bead
        var lo = bead, hi = bead * 1.6
        for _ in 0..<30 {
            let m = (lo + hi) / 2
            if (m + b) * (m + b) * (2 * m - b) < target { lo = m } else { hi = m }
        }
        return (lo + hi) / 2
    }

    /// A circle's points between two angles (y down, so angles run clockwise on screen).
    private static func arc(cx: Double, cy: Double, r: Double, from a: Double, to b: Double) -> [(Double, Double)] {
        let n = max(2, Int(abs(b - a) / (6 * Double.pi / 180)))
        return (0...n).map { i in
            let s = a + (b - a) * Double(i) / Double(n)
            return (cx + r * cos(s), cy + r * sin(s))
        }
    }

    /// A drop: the circle `r` about (cx, cy), cut off by the surface, and hanging from the
    /// needle's tip by a short thread when `thread` is above zero (its neck narrowing to
    /// nothing as it goes). Returns the area and the outline.
    private static func drop(_ u: UnitSquare, cx: Double, cy: Double, r: Double, tip: Double, thread k: Double) -> (area: Path, edge: [Path]) {
        let b = surface - cy
        var from = Double.pi / 2, to = 2.5 * Double.pi
        if b < r {
            let a = (r * r - b * b).squareRoot()
            from = atan2(b, -a)
            to = 2 * Double.pi + atan2(b, a)
        }
        guard k > 0.001 else {
            let pts = arc(cx: cx, cy: cy, r: r, from: from, to: to)
            var area = u.polyline(pts)
            area.closeSubpath()
            return (area, [u.polyline(pts)])
        }
        // The thread: from a joint some way round each side of the top, narrowing to the needle's
        // tip: the bead is a pear while it hangs.
        let alpha = 62.0 * Double.pi / 180, w = 0.0 * k
        let top = cy - r
        let tipY = top + (tip - top) * k
        let leftJoint = 1.5 * Double.pi - alpha, rightJoint = 1.5 * Double.pi + alpha
        let jl = (cx + r * cos(leftJoint), cy + r * sin(leftJoint))
        let jr = (cx + r * cos(rightJoint), cy + r * sin(rightJoint))
        let reach = max(0.01, jl.1 - tipY)
        func side(_ sign: Double) -> [(Double, Double)] {
            // From the joint to the tip: leave along the circle, arrive going straight up.
            let j = sign < 0 ? jl : jr
            let angle = sign < 0 ? leftJoint : rightJoint
            let dir = sign < 0 ? (-sin(angle), cos(angle)) : (sin(angle), -cos(angle))
            let c1 = (j.0 + dir.0 * reach * 0.45, j.1 + dir.1 * reach * 0.45)
            let end = (cx + sign * w, tipY)
            let c2 = (end.0, end.1 + reach * 0.5)
            return (0...12).map { i in
                let s = Double(i) / 12, m = 1 - s
                return (m * m * m * j.0 + 3 * m * m * s * c1.0 + 3 * m * s * s * c2.0 + s * s * s * end.0,
                        m * m * m * j.1 + 3 * m * m * s * c1.1 + 3 * m * s * s * c2.1 + s * s * s * end.1)
            }
        }
        let leftSide = side(-1), rightSide = side(1)
        let leftArc = arc(cx: cx, cy: cy, r: r, from: from, to: leftJoint)
        let rightArc = arc(cx: cx, cy: cy, r: r, from: rightJoint, to: to)
        var area = u.polyline(leftArc + leftSide + rightSide.reversed() + rightArc)
        area.closeSubpath()
        return (area, [u.polyline(leftArc + leftSide), u.polyline(rightSide.reversed() + rightArc)])
    }

    /// The needle: a short blunt tube coming down off the top of the square to its tip.
    private static func needle(_ context: GraphicsContext, _ u: UnitSquare, tip: Double, tint: Color) {
        context.fill(Path(CGRect(x: u.pt(0.5 - tube / 2, 0).x, y: u.pt(0, -0.2).y, width: u.len(tube), height: u.len(tip + 0.2))),
                     with: .color(tint))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let local = t.truncatingRemainder(dividingBy: duration)
        var layer = context
        layer.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))
        let shift = slide * Ease.inOut((local - slideAt) / (duration - slideAt - 0.1))

        // The stage: the surface, and marks beneath it that move with the drop.
        u.stroke(layer, u.line((0.04, surface), (0.96, surface)), tint, 0.07)
        for m in -2...3 {
            let x = 0.14 + spacing * Double(m) + shift
            let fade = Ease.inOut((x - 0.06) / 0.12) * Ease.inOut((0.94 - x) / 0.12)
            if fade > 0.02 { u.stroke(layer, u.line((x - 0.05, 0.94), (x + 0.05, 0.94)), tint.opacity(0.5 * fade), 0.04) }
        }

        // The needle and what it carries: first the bead it lowers, later the next one growing.
        var tip = tip0
        if local >= setOff && local < touch { tip = tip0 + (tipTouch - tip0) * Ease.inOut((local - setOff) / (touch - setOff)) }
        if local >= touch && local < lift { tip = tipTouch + (tipHold - tipTouch) * Ease.inOut((local - touch) / 0.3) }
        if local >= lift { tip = tipHold - (tipHold - tip0) * Ease.inOut((local - lift) / 0.7) }

        func paint(_ d: (area: Path, edge: [Path])) {
            layer.fill(d.area, with: .color(tint.opacity(0.15)))
            for e in d.edge { u.stroke(layer, e, tint, 0.06) }
        }
        if local < touch {
            paint(drop(u, cx: 0.5, cy: tip + hang + bead, r: bead, tip: tip, thread: 1))
        } else if local >= growAt {
            let grow = Ease.inOut((local - growAt) / 0.85)
            if grow > 0.1 { paint(drop(u, cx: 0.5, cy: tip0 + (hang + bead) * grow, r: bead * grow, tip: tip0, thread: 1)) }
        }

        // The drop on the surface: the bead spreading to its contact angle with a damped wobble.
        if local >= touch {
            let age = local - touch
            let b = settledB + (bead - settledB) * exp(-age / 0.35) * cos(2 * Double.pi * age / 1.2)
            let r = radius(centreHeight: b)
            let cx = 0.5 + shift, cy = surface - b
            let thread = 1 - Ease.clamp((local - snap) / 0.15)
            let d = drop(u, cx: cx, cy: cy, r: r, tip: tip, thread: thread)
            layer.fill(d.area, with: .color(tint.opacity(0.15)))

            // The contact angle at the right contact point: the tangent, a line through it that
            // crosses the surface, then the arc inside the drop between surface and tangent. The
            // angle is shaded under the drop's outline so the two don't muddy each other.
            let half = (r * r - b * b).squareRoot()
            let foot = (cx + half, surface)
            let angle = acos(-b / r)
            let dir = (-cos(angle), -sin(angle))
            let around = Ease.inOut((local - arcAt) / 0.5)
            var arcPoints: [(Double, Double)] = []
            if around > 0.01 {
                arcPoints = (0...16).map { i -> (Double, Double) in
                    let s = angle * around * Double(i) / 16
                    return (foot.0 - 0.15 * cos(s), foot.1 - 0.15 * sin(s))
                }
                var wedge = u.polyline([foot] + arcPoints)
                wedge.closeSubpath()
                var shade = layer
                shade.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(surface - 0.035))))
                shade.fill(wedge, with: .color(clay.opacity(0.45)))
            }
            for e in d.edge { u.stroke(layer, e, tint, 0.06) }
            let along = Ease.inOut((local - tangentAt) / 0.45)
            if along > 0 {
                let lower = (foot.0 - dir.0 * 0.12, foot.1 - dir.1 * 0.12)
                u.stroke(layer, u.line(lower, (lower.0 + dir.0 * 0.34 * along, lower.1 + dir.1 * 0.34 * along)), clay, 0.05)
            }
            if !arcPoints.isEmpty { u.stroke(layer, u.polyline(arcPoints), clay, 0.05) }
        }
        needle(layer, u, tip: tip, tint: tint)
    }
}
