// BatchNStrandScenes.swift
// ScienceStatus — on the strand: a sliding clamp loaded and riding, an
// invading strand displacing another, a sequence logo growing. Each draws in
// a unit square (see `UnitSquare`).

import SwiftUI

/// Sliding clamp: a clamp loader brings a clay ring down onto the DNA as an
/// open C; the ring drops round the duplex, snaps shut with a small click,
/// and the loader lifts away. A polymerase docks behind the ring and rides
/// along with it, leaving a short run of clay new strand behind, until the
/// pair slides off the right edge as the next open ring comes down.
enum SlidingClamp {
    static let duration = 5.0
    private static let top = 0.58, bottom = 0.72, mid = 0.65
    /// Where the ring is loaded, its half-width and half-height, and how far
    /// above the DNA it waits.
    private static let loadX = 0.34, rx = 0.1, ry = 0.19, wait = 0.27
    /// How far the ring slides, and how much new strand trails the polymerase.
    private static let travel = 1.14, tail = 0.16
    /// The polymerase sits this far behind the ring, half this wide.
    private static let behind = 0.16, half = 0.1

    /// Everything about one ring (and what rides with it) at one moment.
    private struct Pose {
        var x = 0.0, y = 0.0
        var gap = 0.0       // half-opening of the C, in degrees
        var pulse = 1.0     // the little shudder as it shuts
        var click = 0.0     // 0...1 while the click marks show, else 0
        var lifted = 0.0    // how far the loader has lifted away, 0...1
        var dock = 0.0      // how far the polymerase has come in, 0...1
        var run: (from: Double, to: Double)?   // the clay new strand
        var polyX: Double { x - behind }
    }

    /// The ring's life from the moment it waits above the DNA (τ = 0); before
    /// that (τ < 0) it is still coming down from above.
    private static func pose(_ tau: Double) -> Pose {
        var p = Pose()
        let lowered = Ease.inOut((tau - 0.3) / 0.9)
        let arriving = tau < 0 ? -0.65 * (1 - Ease.out((tau + 1.3) / 1.0)) : 0
        p.y = mid - wait * (1 - lowered) + arriving
        let slide = Ease.clamp((tau - 2.3) / 2.7)
        p.x = loadX + travel * pow(slide, 1.6)
        // The gap closes faster and faster, then stops dead: a snap.
        let close = Ease.clamp((tau - 1.2) / 0.25)
        p.gap = 55 * (1 - close * close)
        let after = Ease.clamp((tau - 1.45) / 0.25)
        p.pulse = 1 + 0.08 * sin(.pi * after)
        let k = (tau - 1.45) / 0.35
        p.click = k > 0.04 && k < 0.96 ? k : 0
        p.lifted = Ease.inOut((tau - 1.6) / 0.7)
        p.dock = Ease.out((tau - 2.0) / 0.6)
        if p.dock > 0.9 {
            let edge = p.polyX - half
            let from = max(loadX - behind - half, edge - tail)
            if edge - from > 0.004 { p.run = (from, edge) }
        }
        return p
    }

    /// The ring's ellipse between two angles, clockwise from the right.
    private static func arc(_ p: Pose, from a: Double, to b: Double) -> [(Double, Double)] {
        let n = max(2, Int(abs(b - a) / 6))
        return (0...n).map { i in
            let d = (a + (b - a) * Double(i) / Double(n)) * .pi / 180
            return (p.x + rx * p.pulse * cos(d), p.y + ry * p.pulse * sin(d))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The ring that has just slid on, and the next one coming down for the loop.
        var poses = [pose(t)]
        if t > duration - 1.3 { poses.append(pose(t - duration)) }

        // Behind the DNA: the loader and the ring's back half.
        for p in poses {
            if p.lifted < 1 {
                let lift = -0.5 * p.lifted
                let hw = 0.2, bottomY = p.y - ry - 0.005 + lift, topY = bottomY - 0.13, r = 0.08
                var cap = Path()
                cap.move(to: u.pt(p.x - hw, bottomY))
                cap.addLine(to: u.pt(p.x - hw, topY + r))
                cap.addQuadCurve(to: u.pt(p.x - hw + r, topY), control: u.pt(p.x - hw, topY))
                cap.addLine(to: u.pt(p.x + hw - r, topY))
                cap.addQuadCurve(to: u.pt(p.x + hw, topY + r), control: u.pt(p.x + hw, topY))
                cap.addLine(to: u.pt(p.x + hw, bottomY))
                cap.closeSubpath()
                context.fill(cap, with: .color(tint))
            }
            u.stroke(context, u.polyline(arc(p, from: 90 + p.gap, to: 270)), clay, 0.065)
        }

        // The DNA: two strands and rungs, the rungs and top strand clay
        // where new strand has been made.
        for k in 0...10 {
            let x = 0.05 + 0.1 * Double(k)
            let made = poses.contains { p in p.run.map { x >= $0.from && x <= $0.to } ?? false }
            u.stroke(context, u.line((x, top), (x, bottom)), made ? clay : tint.opacity(0.5), 0.045)
        }
        u.stroke(context, u.line((-0.05, top), (1.05, top)), tint, 0.045)
        u.stroke(context, u.line((-0.05, bottom), (1.05, bottom)), tint, 0.045)
        for p in poses {
            if let run = p.run { u.stroke(context, u.line((run.from, top), (run.to, top)), clay, 0.055) }
        }

        // The polymerase, a blob that wraps the DNA just behind its ring.
        for p in poses where p.dock > 0 {
            context.fill(u.capsule(p.polyX, mid + 0.5 * (1 - p.dock), 2 * half, 0.32, corner: 0.09), with: .color(tint))
        }

        // In front of the DNA: the ring's front half, and the click.
        for p in poses {
            u.stroke(context, u.polyline(arc(p, from: 270, to: 450 - p.gap)), clay, 0.065)
            if p.click > 0 {
                let out = sin(.pi * p.click)
                let bottomPoint = (p.x, p.y + ry * p.pulse)
                for angle in [48.0, 90, 132] {
                    let a = angle * .pi / 180
                    let from = 0.045, to = 0.045 + 0.055 * out
                    u.stroke(context, u.line((bottomPoint.0 + from * cos(a), bottomPoint.1 + from * sin(a)),
                                             (bottomPoint.0 + to * cos(a), bottomPoint.1 + to * sin(a))), clay, 0.04)
                }
            }
        }
    }
}

/// Strand displacement: a template with an incumbent strand paired along it
/// and a short toehold left bare. A clay invader drifts in, drops its end on
/// the toehold, and takes over the pairing rung by rung while the incumbent
/// peels away behind the branch point and drifts off, leaving the invader
/// fully paired. Then the film runs backwards, the incumbent coming home and
/// the invader lifting away, so the loop closes.
enum StrandDisplacement {
    static let duration = 5.6
    private static let templateY = 0.72, pairedY = 0.56
    private static let spacing = 0.088
    /// Ten rungs: the first two sit on the toehold, the other eight under the incumbent.
    private static let rungs: [Double] = (0..<10).map { 0.1 + 0.088 * Double($0) }
    private static let incumbentLeft = 0.232, incumbentRight = 0.936, invaderLeft = 0.056
    /// The free ends leave the branch point at 30 degrees.
    private static let lean = (c: cos(Double.pi / 6), s: sin(Double.pi / 6))

    private static func mix(_ a: (Double, Double), _ b: (Double, Double), _ k: Double) -> (Double, Double) {
        (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tau = t < duration / 2 ? t : duration - t
        let come = Ease.inOut((tau - 0.25) / 0.65)
        // The branch point hops one rung at a time.
        var hops = 0.0
        for i in 0..<8 { hops += Ease.inOut((tau - 1.25 - 0.125 * Double(i)) / 0.1) }
        let branch = incumbentLeft + spacing * hops
        let release = Ease.inOut((tau - 2.25) / 0.45)

        // The template, and the rungs: clay where the invader has taken over.
        u.stroke(context, u.line((0.03, templateY), (0.97, templateY)), tint, 0.06)
        for (k, x) in rungs.enumerated() {
            if k < 2 {
                let grown = Ease.out((tau - 0.9 - 0.1 * Double(k)) / 0.2)
                if grown > 0 { u.stroke(context, u.line((x, pairedY), (x, pairedY + (templateY - pairedY) * grown)), clay, 0.045) }
            } else {
                u.stroke(context, u.line((x, pairedY), (x, templateY)), x < branch ? clay : tint.opacity(0.55), 0.045)
            }
        }

        // The incumbent: paired to the right of the branch point, peeled up
        // and away to the left of it; once free it drifts up and off.
        let peeled = branch - incumbentLeft
        let incumbent: [(Double, Double)] = [(branch - peeled * lean.c, pairedY - peeled * lean.s), (branch, pairedY), (incumbentRight, pairedY)]
        let drift = -0.78 * release
        u.stroke(context, u.polyline(incumbent.map { ($0.0, $0.1 + drift) }), tint, 0.055)

        // The invader: a free strand above, its left end swinging down to the
        // toehold; its unpaired part leaves the branch point at the other slant.
        let ahead = incumbentRight - branch
        let docked: [(Double, Double)] = [(invaderLeft, pairedY), (branch, pairedY), (branch + ahead * lean.c, pairedY - ahead * lean.s)]
        let freeStart = (-0.2, 0.2), freeEnd = (0.66, 0.1)
        let bob = 0.012 * sin(tau * 4.5) * (1 - come)
        let free = [freeStart, mix(freeStart, freeEnd, (incumbentLeft - invaderLeft) / (incumbentRight - invaderLeft)), freeEnd]
        let invader = zip(free, docked).map { f, d in mix(f, d, come) }.map { ($0.0, $0.1 + bob) }
        u.stroke(context, u.polyline(invader), clay, 0.055)
    }
}

/// Sequence logo: the axis and baseline stand empty; five columns grow up
/// from the baseline one after another, each stack building letter by
/// letter with the commonest on top in clay (the conserved columns one tall
/// letter, the mixed ones several short ones). They hold, then shrink back
/// to the baseline.
enum SequenceLogo {
    static let duration = 5.0

    private enum Base { case a, c, g, t }
    /// Each column's letters from the bottom up, with their heights.
    private static let columns: [[(base: Base, height: Double)]] = [
        [(.c, 0.64)],
        [(.g, 0.08), (.t, 0.11), (.a, 0.24)],
        [(.t, 0.07), (.g, 0.58)],
        [(.c, 0.08), (.g, 0.1), (.a, 0.12), (.t, 0.18)],
        [(.c, 0.08), (.a, 0.6)],
    ]
    private static let left = 0.135, pitch = 0.165, width = 0.14, floor = 0.875, gap = 0.012

    /// A closed polygon, wound the same way whichever way it was given, so
    /// that overlapping pieces of one letter fill as one shape.
    private static func add(_ path: inout Path, _ u: UnitSquare, _ points: [(Double, Double)]) {
        var area = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            area += a.0 * b.1 - b.0 * a.1
        }
        let ordered = area < 0 ? Array(points.reversed()) : points
        path.move(to: u.pt(ordered[0].0, ordered[0].1))
        for p in ordered.dropFirst() { path.addLine(to: u.pt(p.0, p.1)) }
        path.closeSubpath()
    }

    /// An elliptical band (the body of a C or a G) between two angles,
    /// clockwise from the right.
    private static func band(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rxIn: Double, _ ryIn: Double,
                             from a: Double, to b: Double) -> [(Double, Double)] {
        let n = max(4, Int(abs(b - a) / 8))
        func at(_ i: Int, _ rx: Double, _ ry: Double) -> (Double, Double) {
            let d = (a + (b - a) * Double(i) / Double(n)) * .pi / 180
            return (cx + rx * cos(d), cy + ry * sin(d))
        }
        return (0...n).map { at($0, rx, ry) } + (0...n).reversed().map { at($0, rxIn, ryIn) }
    }

    /// A bold letter stretched to fill the box, its strokes kept to a steady weight.
    private static func letter(_ base: Base, _ u: UnitSquare, x: Double, top: Double, w: Double, h: Double) -> Path {
        var p = Path()
        let bottom = top + h
        let stem = 0.4 * w, bar = min(0.3 * h, 0.07)
        let cx = x + w / 2, cy = top + h / 2
        switch base {
        case .t:
            add(&p, u, [(x, top), (x + w, top), (x + w, top + bar), (x, top + bar)])
            add(&p, u, [(cx - stem / 2, top), (cx + stem / 2, top), (cx + stem / 2, bottom), (cx - stem / 2, bottom)])
        case .a:
            let apex = stem * 0.45, leg = stem * 0.7
            add(&p, u, [(x, bottom), (cx - apex, top), (cx + apex, top), (x + leg, bottom)])
            add(&p, u, [(x + w, bottom), (cx + apex, top), (cx - apex, top), (x + w - leg, bottom)])
            // The crossbar spans between the legs' outer edges.
            let f0 = 0.6, f1 = min(0.6 + bar / h * 0.8, 0.95)
            func edge(_ f: Double) -> (Double, Double) { (cx - apex + (x - cx + apex) * f, cx + apex + (x + w - cx - apex) * f) }
            add(&p, u, [(edge(f0).0, top + f0 * h), (edge(f0).1, top + f0 * h), (edge(f1).1, top + f1 * h), (edge(f1).0, top + f1 * h)])
        case .c:
            let ryIn = max(0.004, h / 2 - bar)
            add(&p, u, band(cx, cy, w / 2, h / 2, w / 2 - stem, ryIn, from: 38, to: 322))
        case .g:
            let ryIn = max(0.004, h / 2 - bar)
            add(&p, u, band(cx, cy, w / 2, h / 2, w / 2 - stem, ryIn, from: 0, to: 305))
            add(&p, u, [(cx, cy - bar / 2), (x + w, cy - bar / 2), (x + w, cy + bar / 2), (cx, cy + bar / 2)])
        }
        return p
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The y axis with its ticks, and the baseline.
        u.stroke(context, u.line((0.075, 0.13), (0.075, 0.9)), tint.opacity(0.7), 0.045)
        for y in [0.13, 0.515] { u.stroke(context, u.line((0.035, y), (0.075, y)), tint.opacity(0.7), 0.045) }
        u.stroke(context, u.line((0.075, 0.9), (0.965, 0.9)), tint, 0.045)

        for (c, stack) in columns.enumerated() {
            let x = left + pitch * Double(c)
            var y = floor
            for (j, item) in stack.enumerated() {
                // Letters rise one above another; at the end the top one goes first.
                let rise = Ease.outBack((t - 0.35 - 0.3 * Double(c) - 0.16 * Double(j)) / 0.55)
                let fall = Ease.inOut((t - 3.55 - 0.07 * Double(c) - 0.06 * Double(stack.count - 1 - j)) / 0.5)
                let scale = rise * (1 - fall)
                let h = item.height * scale
                guard h > 0.004 else { continue }
                let color = j == stack.count - 1 ? clay : tint
                context.fill(letter(item.base, u, x: x, top: y - h, w: width, h: h), with: .color(color))
                y -= h + gap * min(1, scale)
            }
        }
    }
}
