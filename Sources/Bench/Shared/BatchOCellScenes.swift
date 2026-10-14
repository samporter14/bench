// BatchOCellScenes.swift
// ScienceStatus — cells and chromatin: FRAP recovery, integrin activation, ATAC accessibility.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// A fixed pseudo-random number in 0...1 from an index and a salt, so a
/// scene's scatter is the same on every frame.
private func batchOScatter(_ i: Int, _ salt: Double) -> Double {
    let v = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
    return v - v.rounded(.down)
}

/// A rise at `up` (start, length) and a fall at `down`, both eased: 0 before,
/// 1 in between, 0 after. Where a scene's states come and go.
private func batchOBump(_ t: Double, up: (Double, Double), down: (Double, Double)) -> Double {
    Ease.inOut((t - up.0) / up.1) - Ease.inOut((t - down.0) / down.1)
}

/// FRAP recovery: a cell full of fluorescent dots, jiggling. A clay laser
/// ring comes down on one spot and flashes, and the dots inside go dark.
/// Then diffusion does the rest: dark dots wander out, bright ones wander in,
/// and the spot fills up again, all but one dot that is stuck. Under the
/// cell a clay trace is drawn as it happens: flat, a sharp drop at the
/// bleach, an exponential climb to a plateau short of the start. At the end
/// the last dark dots light up again, the ring fades and the trace is wiped
/// away from the left. Each dark dot has traded places with a bright one, so
/// once the dark ones light up the dots sit exactly as they began.
enum FRAPRecovery {
    static let duration = 5.0
    private static let bleachAt = 0.9
    /// The trace is drawn up to here and wiped away after it.
    private static let traceEnd = 4.2
    private static let spot: (x: Double, y: Double, r: Double) = (0.5, 0.35, 0.15)
    private static let cell: (x: Double, y: Double, a: Double, b: Double) = (0.5, 0.35, 0.44, 0.30)
    private static let dotRadius = 0.033

    /// The cell's edge: a rounded square-ish oval.
    private static let outline: [(Double, Double)] = (0..<72).map { k -> (Double, Double) in
        let a = Double(k) * 2 * Double.pi / 72
        let c = cos(a), s = sin(a)
        let p = 2.0 / 2.6
        let x: Double = cell.x + cell.a * (c < 0 ? -1 : 1) * pow(abs(c), p)
        let y: Double = cell.y + cell.b * (s < 0 ? -1 : 1) * pow(abs(s), p)
        return (x, y)
    }

    private struct Dot {
        /// Where it starts and where it trades to (the same for dots that stay).
        let from: (Double, Double), to: (Double, Double)
        /// When the trip starts, how long it takes, and how far it bulges sideways.
        let start: Double, span: Double, bow: Double
        /// Jiggle: a slow wander and a quick tremble, in unit lengths.
        let slow: Double, fast: Double
        /// 0 bystander, 1 partner (arrives bright), 2 bleached (leaves dark), 3 stuck (stays dark).
        let kind: Int
        let index: Int
        /// When its light comes back, after the loop's recovery.
        let regain: Double
    }

    private static let dots: [Dot] = {
        var list: [Dot] = []
        // Five dots round a stuck one in the middle of the spot, each trading
        // places with a partner outside it in the same direction.
        let inside: [(Double, Double)] = (0..<5).map { k -> (Double, Double) in
            let a = (Double(k) * 72 - 54) * Double.pi / 180
            return (spot.x + 0.085 * cos(a), spot.y + 0.085 * sin(a))
        }
        let outside: [(Double, Double)] = [(0.66, 0.14), (0.76, 0.43), (0.50, 0.58), (0.24, 0.43), (0.34, 0.14)]
        let leaves: [(start: Double, span: Double)] = [(0.95, 1.1), (1.15, 1.2), (1.4, 1.3), (1.8, 1.4), (2.4, 1.5)]
        for k in 0..<5 {
            let trip = leaves[k]
            list.append(Dot(from: inside[k], to: outside[k], start: trip.start, span: trip.span, bow: 0.04,
                            slow: 0.010, fast: 0.006, kind: 2, index: list.count, regain: 4.1 + 0.07 * Double(k)))
            list.append(Dot(from: outside[k], to: inside[k], start: trip.start, span: trip.span, bow: 0.04,
                            slow: 0.010, fast: 0.006, kind: 1, index: list.count, regain: 0))
        }
        list.append(Dot(from: (spot.x, spot.y), to: (spot.x, spot.y), start: 99, span: 1, bow: 0,
                        slow: 0.010, fast: 0.006, kind: 3, index: list.count, regain: 4.45))
        let rest: [(Double, Double)] = [(0.16, 0.35), (0.84, 0.35), (0.22, 0.21), (0.78, 0.21), (0.22, 0.50), (0.78, 0.50), (0.62, 0.58)]
        for p in rest {
            list.append(Dot(from: p, to: p, start: 99, span: 1, bow: 0,
                            slow: 0.012, fast: 0.007, kind: 0, index: list.count, regain: 0))
        }
        return list
    }()

    /// Where a dot is: along its trip, plus a wander and a tremble of whole
    /// cycles per loop that start and end at nothing, so the loop closes.
    private static func place(_ d: Dot, _ t: Double) -> (Double, Double) {
        let s = Ease.inOut((t - d.start) / d.span)
        let dx = d.to.0 - d.from.0, dy = d.to.1 - d.from.1
        let n = max(hypot(dx, dy), 0.0001)
        let bulge = d.bow * sin(Double.pi * s)
        let w = 2 * Double.pi * t / duration
        let i = d.index
        let kx = 1.0 + Double(i % 2), ky = 1.0 + Double((i / 2) % 2)
        let fx = 5.0 + Double(i % 5), fy = 5.0 + Double((i + 2) % 5)
        let p1 = 2 * Double.pi * batchOScatter(i, 1), p2 = 2 * Double.pi * batchOScatter(i, 2)
        let p3 = 2 * Double.pi * batchOScatter(i, 3), p4 = 2 * Double.pi * batchOScatter(i, 4)
        let shakeX: Double = d.slow * (sin(w * kx + p1) - sin(p1)) + d.fast * (sin(w * fx + p3) - sin(p3))
        let shakeY: Double = d.slow * (sin(w * ky + p2) - sin(p2)) + d.fast * (sin(w * fy + p4) - sin(p4))
        let x: Double = d.from.0 + dx * s - dy / n * bulge + shakeX
        let y: Double = d.from.1 + dy * s + dx / n * bulge + shakeY
        return (x, y)
    }

    /// The trace's height (1 = before the bleach): a drop, a short lag, then
    /// an exponential climb that stops short of the start.
    private static func level(_ s: Double) -> Double {
        if s < bleachAt { return 1 }
        let floor = 0.04, plateau = 0.8
        if s < bleachAt + 0.04 { return 1 + (floor - 1) * (s - bleachAt) / 0.04 }
        return floor + (plateau - floor) * (1 - exp(-max(0, s - bleachAt - 0.35) / 0.9))
    }

    /// Times worth a vertex on the trace: an even step, and both ends of the drop.
    private static let marks: [Double] = (Array(stride(from: 0.0, through: traceEnd, by: 0.07)) + [bleachAt, bleachAt + 0.04]).sorted()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        var body = u.polyline(outline)
        body.closeSubpath()
        u.stroke(context, body, tint, 0.045)

        // The laser: a ring that comes down, flashes at the bleach and stays
        // faintly over the spot until the end.
        let pulse = max(0, 1 - abs(t - bleachAt) / 0.25)
        let come = Ease.clamp((t - 0.3) / 0.2) * (1 - Ease.inOut((t - 4.2) / 0.4))
        if come > 0 {
            let grow = 0.7 + 0.3 * Ease.outBack((t - 0.3) / 0.45)
            let ring = u.circle(spot.x, spot.y, spot.r * grow)
            context.fill(ring, with: .color(clay.opacity(0.3 * pulse * pulse * come)))
            u.stroke(context, ring, clay.opacity(come * (0.55 + 0.45 * pulse)), 0.04)
        }

        // The dots.
        let hit = Ease.clamp((t - bleachAt + 0.04) / 0.04) * (1 - Ease.clamp((t - bleachAt - 0.08) / 0.2))
        for d in dots {
            let p = place(d, t)
            var light = 1.0
            if d.kind >= 2 {
                let dark = Ease.clamp((t - bleachAt) / 0.15)
                light = 1 - dark * (1 - Ease.inOut((t - d.regain) / 0.4))
            }
            context.fill(u.circle(p.0, p.1, dotRadius), with: .color(tint.opacity(0.22 + 0.78 * light)))
            if d.kind >= 2, hit > 0 {
                context.fill(u.circle(p.0, p.1, dotRadius), with: .color(clay.opacity(hit)))
            }
        }

        // The recovery trace, drawn as time passes and then wiped from the left.
        u.stroke(context, u.line((0.1, 0.72), (0.1, 0.95), (0.92, 0.95)), tint.opacity(0.35), 0.03)
        let hi = min(t, traceEnd)
        let lo = max(0, (t - traceEnd) / 0.65) * traceEnd
        if hi - lo > 0.02 {
            func spotOn(_ s: Double) -> (Double, Double) { (0.16 + 0.74 * s / traceEnd, 0.93 - 0.19 * level(s)) }
            var times: [Double] = [lo]
            times += marks.filter { $0 > lo && $0 < hi }
            times.append(hi)
            u.stroke(context, u.polyline(times.map(spotOn)), clay, 0.045)
            let head = spotOn(hi)
            let seen = Ease.clamp(t / 0.25) * (1 - Ease.clamp((t - 4.2) / 0.4))
            context.fill(u.circle(head.0, head.1, 0.035), with: .color(clay.opacity(seen)))
        }
    }
}

/// Integrin activation: the integrin lies folded like a closed penknife: its
/// two legs run up side by side from the membrane to a knee, and fold back
/// down together on one side, ending in one round head that sits low beside
/// them. A clay talin blob rises from the cytoplasm and takes hold of the
/// beta tail, the tails part below the membrane, the legs unfold at the knee
/// and straighten upward, and the head opens a little and grips the fibre of
/// the matrix, which flashes clay at the bond. Then talin lets go, the head
/// lets go of the fibre and the legs fold back down as they began.
enum IntegrinActivation {
    static let duration = 5.5
    private static let fibreY = 0.092
    private static let membraneTop = 0.63, membraneBottom = 0.70, tailY = 0.81
    /// Where the legs stand, and the size of a lobe of the head.
    private static let axis = 0.43
    private static let lobe = 0.045
    /// Talin's resting place down in the cytoplasm.
    private static let talinRest = (x: 0.76, y: 0.93)

    /// One leg from its root on the membrane: a calf straight up, a knee that
    /// turns clockwise through `180 * (1 - unfold)` degrees (a hairpin when
    /// folded, straight when open), then a short thigh in the new heading.
    /// The calf lengthens as it opens, as a folded leg is foreshortened.
    private static func leg(root: Double, unfold: Double) -> [(Double, Double)] {
        let calf = 0.12 + 0.035 * unfold, thigh = 0.04
        let turn = Double.pi * (1 - unfold), arc = 0.28
        var x = root, y = membraneTop - calf
        var points: [(Double, Double)] = [(x, y)]
        var heading = 0.0
        let steps = 10
        for _ in 0..<steps {
            let mid = heading + turn / Double(steps) / 2
            x += arc / Double(steps) * sin(mid)
            y -= arc / Double(steps) * cos(mid)
            heading += turn / Double(steps)
            points.append((x, y))
        }
        points.append((x + thigh * sin(heading), y - thigh * cos(heading)))
        return points
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let w = 2 * Double.pi * t / duration

        // The story, in the order it reads: talin comes up and holds on, the
        // tails part, the legs unfold, the head opens and grips; then the same back.
        let bind = batchOBump(t, up: (0.3, 0.9), down: (3.05, 0.8))
        let apart = batchOBump(t, up: (1.15, 0.6), down: (4.3, 0.6))
        let unfold = batchOBump(t, up: (1.7, 1.0), down: (3.7, 1.0))
        let spread = batchOBump(t, up: (2.5, 0.35), down: (3.5, 0.3))
        let grip = Ease.clamp((t - 2.8) / 0.15) - Ease.clamp((t - 3.45) / 0.3)

        // The matrix fibre, with the bond lit in clay between the two heads.
        u.stroke(context, u.line((0.04, fibreY), (0.96, fibreY)), tint, 0.045)
        if grip > 0 { u.stroke(context, u.line((axis - 0.07, fibreY), (axis + 0.07, fibreY)), clay.opacity(grip), 0.06) }

        // The membrane: two thin lines.
        for y in [membraneTop, membraneBottom] {
            u.stroke(context, u.line((0.02, y), (0.98, y)), tint, 0.035)
        }

        // The two legs, alpha (left) and beta (right), each from its tail up
        // through the membrane and along the leg, and a lobe of the head on the end.
        let reach = 0.0325 + 0.0175 * unfold + 0.012 * spread
        let lobeSize = lobe
        var betaTail = (0.0, 0.0)
        for side in [-1.0, 1.0] {
            let root = axis + side * reach
            let tailX = root + (side < 0 ? -0.045 : 0.07) * apart
            let upper = leg(root: root, unfold: unfold)
            let path: [(Double, Double)] = [(tailX, tailY), (root, membraneBottom), (root, membraneTop)] + upper
            u.stroke(context, u.polyline(path), tint, 0.048)
            let head = upper[upper.count - 1]
            context.fill(u.circle(head.0, head.1, lobeSize), with: .color(tint))
            if side > 0 { betaTail = (tailX, tailY) }
        }

        // The flash as the head takes hold.
        let age = (t - 2.85) / 0.5
        if age > 0, age < 1 {
            u.stroke(context, u.circle(axis, fibreY + 0.01, 0.05 + 0.13 * Ease.out(age)), clay.opacity(1 - age), 0.035)
        }

        // Talin: bobbing in the cytoplasm, then under the beta tail, which it
        // pulls aside as it goes; it lets go and drifts back down.
        let held = (betaTail.0 + 0.005, tailY + 0.045)
        let bob = 1 - bind
        let tx: Double = talinRest.x + (held.0 - talinRest.x) * bind + 0.012 * bob * cos(w * 2)
        let ty: Double = talinRest.y + (held.1 - talinRest.y) * bind + 0.012 * bob * sin(w * 3)
        context.fill(u.ellipse(tx, ty, 0.15, 0.105), with: .color(clay))
    }
}

/// ATAC accessibility: a stretch of DNA wrapped round three nucleosomes, two
/// close together and one apart, with a wide open gap between. Tn5 units
/// (small clay dimers carrying adapters) drop in from above: the ones that
/// hit a nucleosome bounce off, the ones that land in the open gap cut the
/// DNA, split and stay as clay adapter tags on the ends, and the tagged
/// fragment between the two cuts lifts away. Underneath, a coverage track
/// grows a clay peak exactly under the gap. Then the whole thing slides off
/// to the right on a conveyor and the next, untouched stretch takes its place.
enum ATACAccessibility {
    static let duration = 5.5
    private static let dnaY = 0.47
    /// The nucleosomes along one stretch, and the open gap's middle.
    private static let beads: [Double] = [0.115, 0.335, 0.885]
    private static let gapMiddle = 0.61
    private static let coreRadius = 0.055
    /// The DNA wraps one and a half turns, in from the left and out to the right.
    private static let wrapIn = 0.1, wrapOut = 0.068
    private static let wrap: [(Double, Double)] = (0...48).map { i -> (Double, Double) in
        let s = Double(i) / 48
        let a: Double = Double.pi * (1 + 3 * s)
        let r: Double = wrapIn + (wrapOut - wrapIn) * s
        return (r * cos(a), r * sin(a))
    }
    /// The two units that get in: where each cuts, when it cuts, and when it falls.
    private static let cuts: [(x: Double, at: Double, fall: Double)] = [(0.53, 1.7, 0.9), (0.69, 3.05, 2.3)]
    /// A unit's lobes, and what they shrink to as tags on the cut ends.
    private static let lobeOffset = 0.032, lobeRadius = 0.032
    private static let tagOffset = 0.04, tagRadius = 0.027
    private static let trackY = 0.92, peakHeight = 0.28
    private static let slideAt = 3.9

    /// One Tn5 unit: a clay dimer of two touching lobes, joined by a bridge.
    /// `apart` splits it into the two tags of a cut; the lobes can be lifted
    /// separately, and `alpha` fades it in and out.
    private static func dimer(_ context: GraphicsContext, _ u: UnitSquare, x: Double, y: Double,
                              apart: Double = 0, bridge: Double = 1, alpha: Double = 1, lifts: (Double, Double) = (0, 0)) {
        var layer = context
        layer.opacity = context.opacity * alpha
        if bridge > 0.02 {
            layer.fill(u.capsule(x, y, 0.07 * bridge, 0.04 * bridge, corner: 0.02 * bridge), with: .color(clay))
        }
        let off = lobeOffset + (tagOffset - lobeOffset) * apart
        let r = lobeRadius + (tagRadius - lobeRadius) * apart
        layer.fill(u.circle(x - off, y - lifts.0, r), with: .color(clay))
        layer.fill(u.circle(x + off, y - lifts.1, r), with: .color(clay))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var scene = context
        scene.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))

        // The conveyor: the stretch with the cuts slides off to the right and
        // an untouched one takes its place.
        let slide = Ease.inOut((t - slideAt) / 1.3)
        let cut = cuts.map { Ease.inOut((t - $0.at) / 0.3) }
        let gaps = cut.map { 2 * tagOffset * $0 }
        let parted = gaps[0] > 0 && gaps[1] > 0
        let lift = parted ? 0.09 * Ease.inOut((t - 3.4) / 0.5) : 0
        let fragment = (cuts[0].x + slide + gaps[0] / 2, cuts[1].x + slide - gaps[1] / 2)

        // The DNA, in pieces: everywhere except where it wraps a nucleosome
        // and where it is cut; the fragment between the cuts lifts away.
        var holes: [(Double, Double)] = []
        for shift in [slide - 1, slide] {
            for b in beads { holes.append((b + shift - wrapIn, b + shift + wrapOut)) }
        }
        for (k, c) in cuts.enumerated() where gaps[k] > 0 {
            holes.append((c.x + slide - gaps[k] / 2, c.x + slide + gaps[k] / 2))
        }
        if parted { holes.append(fragment) }
        var at = 0.0
        var pieces: [(Double, Double)] = []
        for hole in holes.sorted(by: { $0.0 < $1.0 }) {
            if hole.0 > at { pieces.append((at, hole.0)) }
            at = max(at, hole.1)
        }
        if at < 1 { pieces.append((at, 1)) }
        for p in pieces where p.1 - p.0 > 0.002 {
            u.stroke(scene, u.line((p.0, dnaY), (p.1, dnaY)), tint, 0.04)
        }
        if parted { u.stroke(scene, u.line((fragment.0, dnaY - lift), (fragment.1, dnaY - lift)), tint, 0.04) }

        // The nucleosomes: a disc of histone core with the DNA wrapped round it.
        for shift in [slide - 1, slide] {
            for b in beads where b + shift > -0.25 && b + shift < 1.25 {
                let cx = b + shift
                scene.fill(u.circle(cx, dnaY, coreRadius), with: .color(tint.opacity(0.55)))
                u.stroke(scene, u.polyline(wrap.map { (cx + $0.0, dnaY + $0.1) }), tint, 0.028)
            }
        }

        // The coverage track: a baseline, and a clay peak that grows under
        // the gap as the cuts are made.
        let rise = 0.5 * Ease.inOut((t - 1.8) / 0.5) + 0.5 * Ease.inOut((t - 3.15) / 0.5)
        if rise > 0.001 {
            let centre = gapMiddle + slide, half = 0.27
            var peak = Path()
            peak.move(to: u.pt(centre - half, trackY))
            for k in 0...28 {
                let f = Double(k) / 28
                let bell = sin(Double.pi * f)
                peak.addLine(to: u.pt(centre - half + 2 * half * f, trackY - peakHeight * rise * bell * bell))
            }
            peak.closeSubpath()
            scene.fill(peak, with: .color(clay))
        }
        u.stroke(scene, u.line((0.0, trackY), (1.0, trackY)), tint, 0.035)

        // The units. Two fall onto nucleosomes, bounce up and fade; two fall
        // into the gap, sit on the DNA, and split into the tags of the cuts.
        // Each fades in just below the top, so it is whole inside the frame.
        let bouncers: [(x: Double, fall: Double, drift: Double)] = [(0.335, 0.3, -0.3), (0.885, 1.5, -0.12)]
        let bounceY = dnaY - 0.143
        for b in bouncers {
            let drop = (t - b.fall) / 0.55
            if drop > 0, drop < 1 {
                dimer(scene, u, x: b.x, y: 0.07 + (bounceY - 0.07) * drop * drop, alpha: Ease.clamp(drop / 0.25))
            } else if drop >= 1 {
                let s = t - b.fall - 0.55
                let fade = 1 - Ease.clamp((s - 0.3) / 0.5)
                if fade > 0 { dimer(scene, u, x: b.x + b.drift * s, y: bounceY - 0.9 * s + s * s, alpha: fade) }
            }
        }
        for (k, c) in cuts.enumerated() {
            let drop = (t - c.fall) / 0.55
            guard drop > 0 else { continue }
            let landY = dnaY - 0.02 - lobeRadius
            let y: Double = drop < 1 ? 0.07 + (landY - 0.07) * drop * drop : landY + (dnaY - landY) * cut[k]
            dimer(scene, u, x: c.x + slide, y: y, apart: cut[k], bridge: 1 - cut[k], alpha: Ease.clamp(drop / 0.25),
                  lifts: (k == 1 ? lift : 0, k == 0 ? lift : 0))
        }
    }
}
