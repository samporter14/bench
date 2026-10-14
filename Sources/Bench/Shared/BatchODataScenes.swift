// BatchODataScenes.swift
// ScienceStatus — data and spectra: gene-set enrichment, bootstrap resampling, an NMR spectrum.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Gene-set enrichment: a row of ticks along the bottom marks where one gene
/// set's members fall in a ranked gene list, bunched towards the top of the
/// list. A cursor sweeps the list and the running-sum line walks with it,
/// stepping up at each member and drifting down between them, so it climbs
/// early and falls back to the zero line at the far end. Then a clay dot marks
/// the peak (the enrichment score) with a dashed drop to the list, and the
/// ticks left of it, the leading edge, turn clay. After a hold the marks fade
/// and the line is wiped away from the left, back to the bare ticks.
enum GeneSetEnrichment {
    static let duration = 5.0

    private static let left = 0.1, right = 0.9
    private static let baseY = 0.62, gain = 1.05
    private static let tickTop = 0.8, tickBottom = 0.92
    /// Each member's place in the ranked list, 0 (top) to 1 (bottom).
    private static let hits: [Double] = [0.02, 0.08, 0.14, 0.21, 0.28, 0.36, 0.52, 0.80]
    /// How much of the list a step up takes, so a step is steep but not a spike.
    private static let rise = 0.014
    private static let samples = 400

    /// The running sum at a place in the list: a share up for each member passed,
    /// the same total drifting down over the list, so it ends back at zero.
    private static func running(_ f: Double) -> Double {
        var up = 0.0
        for h in hits { up += Ease.inOut((f - h) / rise + 0.5) }
        return up / Double(hits.count) - f
    }

    private static func point(_ f: Double) -> (Double, Double) {
        (left + (right - left) * f, baseY - gain * running(f))
    }

    private static let curve: [(Double, Double)] = (0...samples).map { point(Double($0) / Double(samples)) }

    /// The highest point of the line, and which members sit at or before it.
    private static let peak: Double = {
        let best = (0...samples).max { running(Double($0) / Double(samples)) < running(Double($1) / Double(samples)) } ?? 0
        return Double(best) / Double(samples)
    }()
    private static let leading = hits.filter { $0 <= peak }.count

    /// The line between two places in the list, ends worked out exactly.
    private static func trace(_ a: Double, _ b: Double) -> [(Double, Double)] {
        var pts = [point(a)]
        let lo = Int((a * Double(samples)).rounded(.up)), hi = Int((b * Double(samples)).rounded(.down))
        if lo <= hi { pts += curve[lo...hi] }
        pts.append(point(b))
        return pts
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sweep = Ease.clamp((t - 0.35) / 2.5)
        let head = sweep * sweep * (3 - 2 * sweep)
        let wipe = Ease.inOut((t - 4.2) / 0.6)
        // The marks come in as the sweep ends and go before the wipe starts.
        let marks = 1 - Ease.clamp((t - 3.85) / 0.3)

        u.stroke(context, u.line((left - 0.02, baseY), (right + 0.02, baseY)), tint.opacity(0.3), 0.03)

        // The ticks; the leading-edge ones turn clay one after another.
        for (k, h) in hits.enumerated() {
            let x = left + (right - left) * h
            let lit = k < leading ? Ease.clamp((t - 2.95 - 0.05 * Double(k)) / 0.2) * marks : 0
            let tick = u.line((x, tickTop), (x, tickBottom))
            u.stroke(context, tick, tint.opacity(1 - lit), 0.034)
            if lit > 0 { u.stroke(context, tick, clay.opacity(lit), 0.034) }
        }

        // The running sum, walking out with the cursor and wiped from the left.
        if head > 0.001 && wipe < 0.999 {
            let pts = trace(wipe, head)
            // The last of the line thins out as it is wiped, so it never ends as a dot.
            let fade = wipe > 0 ? Ease.clamp((head - wipe) / 0.15) : 1
            if pts.count > 1 { u.stroke(context, u.polyline(pts), tint.opacity(fade), 0.05) }
        }

        // The cursor: a dot on the line and a thin drop to the list.
        let cursor = Ease.clamp((t - 0.35) / 0.15) * (1 - Ease.clamp((t - 2.85) / 0.25))
        if cursor > 0 {
            let p = point(head)
            u.stroke(context, u.line((p.0, p.1), (p.0, tickTop - 0.04)), tint.opacity(0.35 * cursor), 0.025)
            context.fill(u.circle(p.0, p.1, 0.032), with: .color(tint.opacity(cursor)))
        }

        // The peak: a clay dot with a dashed drop to the ticks.
        let pop = Ease.outBack((t - 2.9) / 0.3) * marks
        if pop > 0 {
            let p = point(peak)
            let drop = Ease.out((t - 3.0) / 0.35) * marks
            let dash = StrokeStyle(lineWidth: max(u.len(0.025), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.035), u.len(0.035)])
            context.stroke(u.line((p.0, p.1 + 0.04), (p.0, p.1 + 0.04 + (tickTop - 0.04 - p.1 - 0.04) * drop)), with: .color(clay.opacity(0.9)), style: dash)
            context.fill(u.circle(p.0, p.1, 0.05 * pop), with: .color(clay))
        }
    }
}

/// Bootstrap resampling: a sample of six dots sits along a number line. Each
/// round draws six dots from it with replacement; each pick lights clay and a
/// copy drops to the row below, so a dot picked twice stacks and one never
/// picked is missed. The resample's mean falls from the row as a clay dot and
/// adds a block to one bar of the histogram below. After three rounds the
/// histogram fills out to a rough bell, a clay bracket marks the middle span
/// (the confidence interval) and the outer bars dim; then the bracket goes and
/// the bars drain back to the empty axis.
enum BootstrapResampling {
    static let duration = 6.0

    private struct Round {
        let picks: [Int]
        let mean: Double
        let bin: Int
        let start: Double
        /// For each pick, how many earlier picks of the same dot it sits on.
        let level: [Int]
    }

    /// Where the six dots lie on the number line, and their small fixed jitter.
    private static let values: [Double] = [0.19, 0.31, 0.44, 0.56, 0.69, 0.82]
    private static let jitter: [Double] = [0.02, -0.025, 0.012, -0.02, 0.026, -0.012]
    private static let sampleY = 0.13, rowY = 0.38, stack = 0.105, dotR = 0.05
    private static let axisY = 0.88, barBase = 0.87, unit = 0.045
    private static let binFirst = 0.2, binPitch = 0.1
    /// How tall each bar ends up, in blocks: a rough bell around the sample's mean.
    private static let finalCounts: [Double] = [1, 3, 5, 8, 6, 3, 1]

    private static let roundLength = 1.05, firstRound = 0.25
    private static let growStart = 3.45, bracketStart = 4.3, drainStart = 5.25

    private static let rounds: [Round] = [[3, 1, 3, 5, 2, 4], [0, 2, 2, 1, 4, 3], [1, 4, 4, 3, 0, 2]].enumerated().map { r, picks in
        let mean = picks.reduce(0.0) { $0 + values[$1] } / Double(picks.count)
        var seen = [Int](repeating: 0, count: values.count)
        let level = picks.map { i -> Int in seen[i] += 1; return seen[i] - 1 }
        let bin = max(0, min(finalCounts.count - 1, Int((mean - (binFirst - binPitch / 2)) / binPitch)))
        return Round(picks: picks, mean: mean, bin: bin, start: firstRound + roundLength * Double(r), level: level)
    }

    private static func binX(_ b: Int) -> Double { binFirst + binPitch * Double(b) }

    /// How many blocks bar `b` holds: those landed so far, then the fill-out, then the drain.
    private static func blocks(_ b: Int, at t: Double) -> Double {
        var landed = 0.0, count = 0.0
        for r in rounds where r.bin == b {
            landed += Ease.out((t - r.start - 0.94) / 0.15)
            count += 1
        }
        let away = Double(abs(b - 3))
        let grow = Ease.out((t - growStart - 0.07 * away) / 0.5)
        let drain = Ease.inOut((t - drainStart - 0.04 * away) / 0.4)
        return (landed + (finalCounts[b] - count) * grow) * (1 - drain)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // The original sample; a dot lights clay for a moment whenever it is picked.
        var flash = [Double](repeating: 0, count: values.count)
        for r in rounds {
            for (k, i) in r.picks.enumerated() {
                let at = r.start + 0.085 * Double(k)
                let f = Ease.clamp((t - at) / 0.05) * (1 - Ease.clamp((t - at - 0.1) / 0.3))
                flash[i] = max(flash[i], f)
            }
        }
        for (i, x) in values.enumerated() {
            let dot = u.circle(x, sampleY + jitter[i], dotR)
            context.fill(dot, with: .color(tint))
            if flash[i] > 0 { context.fill(dot, with: .color(clay.opacity(flash[i]))) }
        }

        // The resample row: copies drop from the sample, clay turning to ink as they land.
        for r in rounds {
            let fade = 1 - Ease.clamp((t - r.start - 0.74) / 0.16)
            guard t > r.start, fade > 0 else { continue }
            for (k, i) in r.picks.enumerated() {
                let prog = Ease.clamp((t - r.start - 0.085 * Double(k)) / 0.26)
                guard prog > 0 else { continue }
                let e = Ease.inOut(prog)
                let y0 = sampleY + jitter[i], y1 = rowY + jitter[i] - stack * Double(r.level[k])
                let dot = u.circle(values[i], y0 + (y1 - y0) * e, dotR)
                context.fill(dot, with: .color(tint.opacity(fade * e)))
                context.fill(dot, with: .color(clay.opacity(fade * (1 - e))))
            }
            // The resample's mean pops out below the row, then falls into its bar.
            let pop = Ease.outBack((t - r.start - 0.64) / 0.14)
            let land = r.start + 0.94
            if pop > 0 && t < land {
                var before = 0.0
                for o in rounds where o.bin == r.bin && o.start < r.start { before += 1 }
                let fall = Ease.clamp((t - r.start - 0.74) / 0.2)
                let y0 = rowY + 0.1, y1 = barBase - before * unit - 0.042
                context.fill(u.circle(r.mean + (binX(r.bin) - r.mean) * fall * fall, y0 + (y1 - y0) * fall * fall, 0.042 * min(1, pop)), with: .color(clay))
            }
        }

        // The histogram: bars of blocks on an axis, outer bars dimming under the bracket.
        u.stroke(context, u.line((0.12, axisY), (0.88, axisY)), tint.opacity(0.3), 0.035)
        let bracket = Ease.out((t - bracketStart) / 0.5) * (1 - Ease.inOut((t - drainStart) / 0.25))
        for b in 0..<finalCounts.count {
            let h = blocks(b, at: t) * unit
            guard h > 0.004 else { continue }
            let dim = (b == 0 || b == finalCounts.count - 1) ? 1 - 0.6 * bracket : 1
            context.fill(u.capsule(binX(b), barBase - h / 2, 0.082, h, corner: min(0.012, h / 2)), with: .color(tint.opacity(0.9 * dim)))
        }

        // The confidence interval: a clay bracket under the middle five bars.
        if bracket > 0.001 {
            let mid = 0.5, half = 0.25 * bracket
            u.stroke(context, u.line((mid - half, 0.915), (mid - half, 0.96), (mid + half, 0.96), (mid + half, 0.915)), clay, 0.05)
        }
    }
}

/// An NMR spectrum, from the signal to the answer: a free induction decay,
/// a full-width wave that rings and dies away, draws in from the left. A
/// Fourier transform then turns it, left to right, into the spectrum on the
/// same baseline: a quartet, a singlet and a triplet of sharp lines, with the
/// quartet in clay. After a hold the sweep runs back to the decay, which is
/// wiped away to the right.
enum NMRSpectrum {
    static let duration = 5.6

    private static let n = 420
    private static let left = 0.08, right = 0.92, base = 0.64
    private static let cycles = 4.0, decay = 0.36, amplitude = 0.25

    /// The ethyl acetate pattern, as ppm falls to the right: a quartet (1:3:3:1),
    /// a singlet, a triplet (1:2:1), as (centre, height) of each line.
    private static let lines: [(Double, Double)] = {
        var l: [(Double, Double)] = []
        for (k, h) in [0.115, 0.34, 0.34, 0.115].enumerated() { l.append((0.25 + 0.07 * (Double(k) - 1.5), h)) }
        l.append((0.56, 0.42))
        for (k, h) in [0.19, 0.38, 0.19].enumerated() { l.append((0.8 + 0.07 * (Double(k) - 1), h)) }
        return l
    }()
    private static let quartet = (from: 0.12, to: 0.38)

    private static func x(_ i: Int) -> Double { left + (right - left) * Double(i) / Double(n) }

    /// The two polylines share an x for every sample, so the morph is a blend of heights.
    private static let fid: [Double] = (0...n).map { i in
        let s = Double(i) / Double(n)
        return base - amplitude * exp(-s / decay) * cos(2 * .pi * cycles * s)
    }
    private static let spectrum: [Double] = (0...n).map { i in
        var y = 0.0
        for (c, h) in lines { let d = (x(i) - c) / 0.009; y += h * exp(-d * d) }
        return base - y
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // 0 is the decay, 1 the spectrum; the change runs along the trace, left to right.
        let g = Ease.clamp((t - 2.0) / 1.0) - Ease.clamp((t - 3.9) / 0.8)
        func height(_ i: Int) -> Double {
            let m = Ease.inOut(g * 1.5 - 0.5 * Double(i) / Double(n))
            return fid[i] + (spectrum[i] - fid[i]) * m
        }
        func at(_ pos: Double) -> (Double, Double) {
            let i = min(n - 1, Int(pos)), f = pos - Double(i)
            return (left + (right - left) * pos / Double(n), height(i) + (height(i + 1) - height(i)) * f)
        }

        u.stroke(context, u.line((left, base), (right, base)), tint.opacity(0.3), 0.03)

        // The trace draws in from the left and is wiped away from the left.
        let hi = Ease.inOut((t - 0.2) / 1.4) * Double(n)
        let lo = Ease.inOut((t - 4.8) / 0.55) * Double(n)
        guard hi - lo > 0.5 else { return }
        var pts = [at(lo)]
        let first = Int(lo.rounded(.up)), last = Int(hi.rounded(.down))
        if first <= last { for i in first...last { pts.append((x(i), height(i))) } }
        pts.append(at(hi))
        // Thinner lines for the spectrum, so the splitting shows; the tail thins out as it is wiped.
        let width = 0.06 - 0.02 * g
        let thin = lo > 0 ? Ease.clamp((hi - lo) / (0.15 * Double(n))) : 1
        u.stroke(context, u.polyline(pts), tint.opacity(thin), width)

        // The quartet over the spectrum, in clay.
        let clayAlpha = Ease.clamp((g - 0.35) / 0.5)
        if clayAlpha > 0 {
            let a = Int(((quartet.from - left) / (right - left) * Double(n)).rounded())
            let b = Int(((quartet.to - left) / (right - left) * Double(n)).rounded())
            let part = (a...b).map { (x($0), height($0)) }
            context.stroke(u.polyline(part), with: .color(clay.opacity(clayAlpha)),
                           style: StrokeStyle(lineWidth: max(u.len(width), UnitSquare.hairline), lineCap: .round, lineJoin: .round))
        }
    }
}
