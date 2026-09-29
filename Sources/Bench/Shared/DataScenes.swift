// DataScenes.swift
// ScienceStatus — lab scenes of data coming in and being made sense of.
// Each draws in a unit square (see `UnitSquare`): axes and points in the
// tint, the signal and the answer in clay.

import SwiftUI

/// The point `k` (0 to 1) of the way along a polyline, by length.
enum Polyline {
    static func point(_ points: [(Double, Double)], at k: Double) -> (Double, Double) {
        let segments = zip(points, points.dropFirst()).map { a, b in (a, b, hypot(b.0 - a.0, b.1 - a.1)) }
        var left = max(0, min(1, k)) * segments.reduce(0) { $0 + $1.2 }
        for (a, b, length) in segments {
            if left <= length, length > 0 {
                let f = left / length
                return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)
            }
            left -= length
        }
        return points[points.count - 1]
    }
}

/// An action potential being recorded: the clay trace runs along, rises
/// to threshold, spikes, dips below rest and recovers, twice.
enum ActionPotential {
    static let duration = 3.6
    private static let spikes = [0.4, 0.72]

    private static func voltage(_ x: Double) -> Double {
        var v = 0.66
        for x0 in spikes {
            v -= 0.44 * exp(-pow((x - x0) / 0.022, 2))
            v += 0.08 * exp(-pow((x - x0 - 0.06) / 0.035, 2))
            v -= 0.05 * exp(-pow((x - x0 + 0.04) / 0.03, 2))
        }
        return v
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.08, 0.1), (0.08, 0.9), (0.94, 0.9)), tint, 0.045)
        var x = 0.1
        while x < 0.92 {
            u.stroke(context, u.line((x, 0.56), (x + 0.03, 0.56)), tint.opacity(0.4), 0.03)
            x += 0.06
        }
        let run = Ease.clamp((t - 0.2) / 2.8)
        guard run > 0 else { return }
        let end = 0.1 + 0.82 * run
        let trace = stride(from: 0.1, through: end, by: 0.004).map { ($0, voltage($0)) }
        if trace.count > 1 { u.stroke(context, u.polyline(trace), clay, 0.045) }
        context.fill(u.circle(end, voltage(end), 0.03), with: .color(clay))
    }
}

/// k-means: loose points, three clay centroids that start in the wrong
/// places and hop to their clusters in three steps, each point tethered
/// to its nearest.
enum KMeans {
    static let duration = 4.0
    private static let points: [(Double, Double)] = {
        let centres = [(0.27, 0.3), (0.72, 0.32), (0.5, 0.74)]
        let offsets = [(-0.07, -0.04), (0.06, -0.06), (0.02, 0.07), (-0.05, 0.06), (0.08, 0.03), (-0.01, -0.09)]
        return centres.flatMap { c in offsets.map { (c.0 + $0.0, c.1 + $0.1) } }
    }()
    /// Where the centroids stand at the start and after each step.
    private static let steps: [[(Double, Double)]] = {
        var centroids = [(0.18, 0.78), (0.52, 0.16), (0.86, 0.62)]
        var history = [centroids]
        for _ in 0..<3 {
            var sums = Array(repeating: (0.0, 0.0, 0.0), count: centroids.count)
            for p in points {
                let nearest = centroids.indices.min { hypot(p.0 - centroids[$0].0, p.1 - centroids[$0].1) <
                    hypot(p.0 - centroids[$1].0, p.1 - centroids[$1].1) } ?? 0
                sums[nearest] = (sums[nearest].0 + p.0, sums[nearest].1 + p.1, sums[nearest].2 + 1)
            }
            centroids = centroids.indices.map { sums[$0].2 > 0 ? (sums[$0].0 / sums[$0].2, sums[$0].1 / sums[$0].2) : centroids[$0] }
            history.append(centroids)
        }
        return history
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let times = [0.8, 1.8, 2.8]
        var centroids = steps[0]
        for (i, start) in times.enumerated() {
            let k = Ease.inOut((t - start) / 0.45)
            guard k > 0 else { break }
            centroids = centroids.indices.map { j in
                (steps[i][j].0 + (steps[i + 1][j].0 - steps[i][j].0) * k, steps[i][j].1 + (steps[i + 1][j].1 - steps[i][j].1) * k)
            }
        }
        let tether = Ease.clamp((t - 0.3) / 0.3)
        for p in points {
            if tether > 0 {
                let c = centroids.min { hypot(p.0 - $0.0, p.1 - $0.1) < hypot(p.0 - $1.0, p.1 - $1.1) } ?? p
                u.stroke(context, u.line(p, c), tint.opacity(0.3 * tether), 0.02)
            }
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(tint))
        }
        for c in centroids {
            u.stroke(context, u.circle(c.0, c.1, 0.045), clay, 0.04)
            context.fill(u.circle(c.0, c.1, 0.015), with: .color(clay))
        }
    }
}
