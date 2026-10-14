// BatchOMixedScenes.swift
// ScienceStatus — molecules and forces: RNase P, an azobenzene photoswitch, acoustic levitation.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// RNase P: a pre-tRNA, a flat cloverleaf with its acceptor stem pointing up and
/// to the right, hangs a short clay 5′ leader off that stem. RNase P, one big
/// rounded mass with a notch in its side and a small protein blob on its back,
/// slides in from the right and its notch closes over the stem's end and the
/// leader; a short clay spark marks the cut and the leader falls away and fades.
/// The enzyme lets go and leaves, the mature tRNA slides off to the left on a
/// belt, and the next pre-tRNA, leader and all, slides into its place.
enum RNasePCleavage {
    static let duration = 5.0

    private typealias Point = (Double, Double)

    /// The cloverleaf's junction; each arm leaves it at an angle (degrees, 0
    /// right, 90 down) the whole leaf tilted 10 degrees clockwise.
    private static let junction: Point = (0.33, 0.58)
    private static let acceptorAngle = -80.0, acceptorLength = 0.24, halfWidth = 0.05
    /// Where the leader joins the acceptor stem's 5′ strand, and where RNase P cuts.
    private static let cutSite: Point = {
        let a = acceptorAngle * .pi / 180
        return (junction.0 + acceptorLength * cos(a) - halfWidth * sin(a),
                junction.1 + acceptorLength * sin(a) + halfWidth * cos(a))
    }()
    /// How far the cloverleaf reaches left and right of its own origin: items
    /// fade as they near the frame's edge so the belt leaves no fragments.
    private static let reachLeft = 0.06, reachRight = 0.6
    /// How long the leader's wave takes to come round; it divides the loop.
    private static let wavePeriod = 2.5

    /// The whole tRNA as one strand traced round the leaf: up the acceptor
    /// stem's 5′ side, out and back along the T, anticodon and D arms, each
    /// ending in a round loop, and up the stem's 3′ side to a short overhang.
    private static let strand: [Point] = {
        let arms: [(angle: Double, stem: Double, loop: Bool)] = [
            (acceptorAngle, acceptorLength, false), (10, 0.1, true), (100, 0.14, true), (190, 0.1, true),
        ]
        let hw = halfWidth, gap = 0.06, bulb = 0.085
        func dir(_ k: Int) -> Point { let a = arms[k].angle * .pi / 180; return (cos(a), sin(a)) }
        func side(_ k: Int) -> Point { let d = dir(k); return (-d.1, d.0) }
        func at(_ k: Int, along: Double, across: Double) -> Point {
            (junction.0 + dir(k).0 * along + side(k).0 * across, junction.1 + dir(k).1 * along + side(k).1 * across)
        }
        var path: [Point] = [at(0, along: acceptorLength, across: hw), at(0, along: gap, across: hw)]
        for k in 1..<arms.count {
            path.append(at(k, along: gap, across: -hw))
            path.append(at(k, along: arms[k].stem, across: -hw))
            // The loop: a circle a little wider than the stem, round its far end.
            let neck = (bulb * bulb - hw * hw).squareRoot()
            let back = asin(hw / bulb)
            let centre = arms[k].stem + neck
            for j in 0...14 {
                let b = -(Double.pi - back) + 2 * (Double.pi - back) * Double(j) / 14
                path.append(at(k, along: centre + bulb * cos(b), across: bulb * sin(b)))
            }
            path.append(at(k, along: gap, across: hw))
        }
        path.append(at(0, along: gap, across: -hw))
        path.append(at(0, along: acceptorLength, across: -hw))
        path.append(at(0, along: acceptorLength + 0.055, across: -hw))
        return path
    }()

    /// How visible the tRNA is at belt position `shift`: fading near both edges.
    private static func fade(_ shift: Double) -> Double {
        min(Ease.clamp((reachRight + shift - 0.15) / 0.25), Ease.clamp((0.75 - reachLeft - shift) / 0.25))
    }

    private static func drawTRNA(_ context: GraphicsContext, _ u: UnitSquare, shift: Double, tint: Color) {
        var c = context
        c.opacity = fade(shift)
        c.translateBy(x: u.len(shift), y: 0)
        u.stroke(c, u.polyline(strand), tint, 0.045)
    }

    /// The 5′ leader: a loose strand that waves, more freely once cut.
    private static func leader(_ u: UnitSquare, shift: Double, free: Double, t: Double) -> Path {
        u.polyline((0...14).map { i in
            let s = Double(i) / 14
            let wave = 0.018 * (1 + 0.8 * free) * s * sin(2 * .pi * (1.5 * s - t / wavePeriod))
            return (cutSite.0 + shift + 0.22 * s, cutSite.1 - 0.13 * s + 0.1 * s * s + wave)
        })
    }

    /// RNase P: a kidney of a mass whose notch faces the stem; as it grips the
    /// notch narrows round the stem's end. The protein subunit rides on its back.
    private static func drawEnzyme(_ context: GraphicsContext, _ u: UnitSquare, dx: Double, grip: Double, tint: Color) {
        var c = context
        c.opacity = Ease.clamp((0.4 - dx) / 0.2)
        c.translateBy(x: u.len(dx), y: 0)
        let centre: Point = (0.62, 0.28), rx = 0.2, ry = 0.21
        let notch = 165.0 * Double.pi / 180
        let width = 0.85 - 0.3 * grip, depth = 0.62 - 0.08 * grip
        let outline: [Point] = (0..<96).map { i in
            let a = Double(i) / 96 * 2 * .pi
            let off = atan2(sin(a - notch), cos(a - notch))
            let k = 1 - depth * exp(-pow(off / width, 2))
            return (centre.0 + rx * cos(a) * k, centre.1 + ry * sin(a) * k)
        }
        var body = u.polyline(outline)
        body.closeSubpath()
        c.fill(body, with: .color(tint.opacity(0.2)))
        u.stroke(c, body, tint, 0.06)
        let a = -28.0 * Double.pi / 180
        c.fill(u.circle(centre.0 + (rx + 0.04) * cos(a), centre.1 + (ry + 0.04) * sin(a), 0.06), with: .color(tint))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let belt = Ease.inOut((t - 3.0) / 1.8)
        let cutAt = 1.8

        // The enzyme comes in, grips, lets go and goes back out.
        let gone = 1 - Ease.inOut((t - 0.15) / 1.15) + Ease.inOut((t - 2.6) / 1.0)
        let grip = Ease.inOut((t - 1.15) / 0.5) * (1 - Ease.inOut((t - 2.3) / 0.5))
        drawEnzyme(context, u, dx: 0.8 * gone, grip: grip, tint: tint)

        // Two tRNAs on the belt: the one being trimmed, and the next in line.
        drawTRNA(context, u, shift: -belt, tint: tint)
        if belt > 0 { drawTRNA(context, u, shift: 1 - belt, tint: tint) }
        if t < cutAt { u.stroke(context, leader(u, shift: -belt, free: 0, t: t), clay, 0.04) }
        if belt > 0 {
            var next = context
            next.opacity = fade(1 - belt)
            u.stroke(next, leader(u, shift: 1 - belt, free: 0, t: t), clay, 0.04)
        }

        // The cut leader falls away and fades.
        let fall = Ease.inOut((t - cutAt) / 1.0)
        if t >= cutAt, fall < 1 {
            var piece = context
            piece.translateBy(x: u.len(0.08 * fall), y: u.len(0.3 * fall))
            u.stroke(piece, leader(u, shift: 0, free: fall, t: t), clay.opacity(1 - fall), 0.04)
        }

        // The snip: a short burst at the cut.
        let snip = (t - 1.75) / 0.4
        if snip > 0, snip < 1 {
            for k in 0..<6 {
                let a = (60.0 * Double(k) + 20) * .pi / 180
                let near = 0.035 + 0.04 * snip, far = near + 0.045 * (1 - snip)
                u.stroke(context, u.line((cutSite.0 + near * cos(a), cutSite.1 + near * sin(a)),
                                         (cutSite.0 + far * cos(a), cutSite.1 + far * sin(a))), clay.opacity(1 - snip), 0.03)
            }
        }
    }
}

/// Azobenzene switch: trans-azobenzene lies extended, a phenyl ring either side
/// of a clay N=N bond. A short, closely waved UV photon comes down onto the
/// N=N, flashes, and the second ring swings round the nitrogen into the bent
/// cis shape, the whole molecule turning a little to sit square. It holds, then
/// a longer, lazier visible photon comes down between the two rings and the
/// ring swings back to the starting trans pose.
enum AzobenzeneSwitch {
    static let duration = 5.0

    private typealias Point = (Double, Double)
    /// Every bond, and every ring's radius.
    private static let bond = 0.132

    private struct Molecule {
        let ringA: [Point], ringB: [Point]
        let n1: Point, n2: Point
    }

    /// The molecule at `swing` (0 trans, 1 cis); `flex` rocks the second ring
    /// a few degrees about its nitrogen. Ring A and the N=N stay put in the
    /// molecule's own frame; the frame itself turns and slides a little so
    /// the bent cis shape sits in the middle of the square too.
    private static func molecule(swing p: Double, flex: Double) -> Molecule {
        let b = bond, rad = Double.pi / 180
        let c30 = cos(30 * rad), s30 = sin(30 * rad)
        let n1: Point = (-0.5 * b * c30, 0.5 * b * s30)
        let n2: Point = (0.5 * b * c30, -0.5 * b * s30)
        let centreA: Point = (n1.0 - 2 * b * c30, n1.1 - 2 * b * s30)
        let swung = 30 - 120 * p + flex
        let centreB: Point = (n2.0 + 2 * b * cos(swung * rad), n2.1 + 2 * b * sin(swung * rad))
        let turn = 30 * p * rad
        let origin: Point = (0.5, 0.5 + 0.15 * p)
        func place(_ q: Point) -> Point {
            (origin.0 + q.0 * cos(turn) - q.1 * sin(turn), origin.1 + q.0 * sin(turn) + q.1 * cos(turn))
        }
        func ring(_ c: Point, _ first: Double) -> [Point] {
            (0..<6).map { j in
                let a = (first + 60 * Double(j)) * rad
                return place((c.0 + b * cos(a), c.1 + b * sin(a)))
            }
        }
        return Molecule(ringA: ring(centreA, 30), ringB: ring(centreB, swung + 180), n1: place(n1), n2: place(n2))
    }

    /// A wavy arrow: a sine packet that tapers in behind, with a two-stroke
    /// head on the tip. `travel` is +1 going down, -1 going up.
    private static func photon(_ context: GraphicsContext, _ u: UnitSquare, tip: Double, travel: Double,
                               length: Double, wavelength: Double, amp: Double, tint: Color, opacity: Double) {
        guard length > 0.02, opacity > 0 else { return }
        let samples = 28
        let wave: [Point] = (0...samples).map { i in
            let s = Double(i) / Double(samples)
            return (0.5 + amp * Ease.clamp(s * 4) * sin(2 * .pi * (1 - s) * length / wavelength),
                    tip - travel * length * (1 - s))
        }
        u.stroke(context, u.polyline(wave), tint.opacity(opacity), 0.03)
        u.stroke(context, u.line((0.5 - 0.05, tip - travel * 0.07), (0.5, tip), (0.5 + 0.05, tip - travel * 0.07)),
                 tint.opacity(opacity), 0.035)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // 0 trans, 1 cis: out on the UV photon, back on the visible one.
        let swing = Ease.inOut((t - 1.2) / 1.0) * (1 - Ease.inOut((t - 3.75) / 1.0))
        let flex = 2.0 * sin(2 * .pi * 2 * t / duration)
        let m = molecule(swing: swing, flex: flex)

        // The two rings: outline, with a shorter inner line on every other edge.
        for ring in [m.ringA, m.ringB] {
            var outline = u.polyline(ring)
            outline.closeSubpath()
            u.stroke(context, outline, tint, 0.045)
            let cx = ring.map(\.0).reduce(0, +) / 6, cy = ring.map(\.1).reduce(0, +) / 6
            for j in [1, 3, 5] {
                let a = ring[j], c = ring[(j + 1) % 6]
                let mid = ((a.0 + c.0) / 2, (a.1 + c.1) / 2)
                let inward = max(hypot(cx - mid.0, cy - mid.1), 0.0001)
                let o = ((cx - mid.0) / inward * 0.052, (cy - mid.1) / inward * 0.052)
                u.stroke(context, u.line((a.0 + (c.0 - a.0) * 0.3 + o.0, a.1 + (c.1 - a.1) * 0.3 + o.1),
                                         (a.0 + (c.0 - a.0) * 0.7 + o.0, a.1 + (c.1 - a.1) * 0.7 + o.1)), tint, 0.034)
            }
        }
        u.stroke(context, u.line(m.ringA[0], m.n1), tint, 0.05)
        u.stroke(context, u.line(m.n2, m.ringB[0]), tint, 0.05)

        // The N=N bond, in clay, a dot on each nitrogen.
        let along = (m.n2.0 - m.n1.0, m.n2.1 - m.n1.1)
        let long = max(hypot(along.0, along.1), 0.0001)
        let side = (-along.1 / long * 0.024, along.0 / long * 0.024)
        for s in [-1.0, 1.0] {
            u.stroke(context, u.line((m.n1.0 + side.0 * s, m.n1.1 + side.1 * s), (m.n2.0 + side.0 * s, m.n2.1 + side.1 * s)), clay, 0.04)
        }
        context.fill(u.circle(m.n1.0, m.n1.1, 0.04), with: .color(clay))
        context.fill(u.circle(m.n2.0, m.n2.1, 0.04), with: .color(clay))

        // The UV photon, tightly waved, comes down onto the trans N=N...
        let uvTip = -0.2 + 0.65 * Ease.clamp((t - 0.35) / 0.8)
        let uvGone = Ease.clamp((t - 1.15) / 0.15)
        photon(context, u, tip: uvTip, travel: 1, length: 0.3 * (1 - uvGone), wavelength: 0.07, amp: 0.03, tint: tint,
               opacity: Ease.clamp((t - 0.35) / 0.15))
        // ...and a visible-light photon, a longer wave, comes down between the
        // two rings onto the cis one.
        let visTip = -0.2 + 0.785 * Ease.clamp((t - 2.75) / 0.97)
        let visGone = Ease.clamp((t - 3.72) / 0.15)
        photon(context, u, tip: visTip, travel: 1, length: 0.3 * (1 - visGone), wavelength: 0.14, amp: 0.045, tint: tint,
               opacity: Ease.clamp((t - 2.75) / 0.15))

        // Each photon is taken up with a ring of clay at the N=N.
        let mid = ((m.n1.0 + m.n2.0) / 2, (m.n1.1 + m.n2.1) / 2)
        for start in [1.15, 3.72] {
            let f = (t - start) / 0.4
            if f > 0, f < 1 { u.stroke(context, u.circle(mid.0, mid.1, 0.07 + 0.07 * f), clay.opacity(1 - f), 0.03) }
        }
    }
}

/// Acoustic levitation: an ultrasonic transducer, a dish with a row of small
/// elements, arcs over the top and a plain reflector dish under the bottom;
/// between them the standing sound wave shows as its pressure envelope, a chain
/// of faint lobes pinched at the still pressure nodes, breathing gently. Three
/// clay droplets hang at the waists, bobbing a little. The wave's phase slips,
/// the lobes slide up and carry the droplets with them like a lift; then it
/// slips back and they come down to where they started.
enum AcousticLevitation {
    static let duration = 5.0
    /// Pressure nodes are half a wavelength apart; the antinodes sit on the plates.
    private static let half = 0.186
    private static let firstNode = 0.2205
    private static let top = 0.15, bottom = 0.85

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let lift = 0.12 * (Ease.inOut((t - 0.7) / 1.3) - Ease.inOut((t - 3.0) / 1.3))
        let pulse = cos(2 * .pi * 4 * t / duration)

        // The envelope |sin| of the pressure, mirrored about the axis; the
        // samples include each node so the waists close exactly.
        let width = 0.2 * (0.9 + 0.1 * pulse)
        let nodes = (-1...5).map { firstNode + half * Double($0) - lift }
        let ys = (stride(from: top, through: bottom, by: 0.01).map { $0 } + nodes.filter { $0 > top && $0 < bottom }).sorted()
        func envelope(_ y: Double) -> Double {
            width * abs(sin(.pi * (y - firstNode + lift) / half)) * Ease.clamp(min(y - top, bottom - y) / 0.07)
        }
        u.stroke(context, u.polyline(ys.map { (0.5 + envelope($0), $0) }), tint.opacity(0.35), 0.035)
        u.stroke(context, u.polyline(ys.map { (0.5 - envelope($0), $0) }), tint.opacity(0.35), 0.035)

        // The droplets, caught at three of the waists.
        for i in 0..<3 {
            let phase = Double(i)
            let y = firstNode + half * Double(i + 1) - lift + 0.007 * sin(2 * .pi * 3 * t / duration + 2.1 * phase)
            let x = 0.5 + 0.005 * sin(2 * .pi * 2 * t / duration + 1.7 * phase)
            context.fill(u.ellipse(x, y, 0.13, 0.105), with: .color(clay))
        }

        // The transducer above, the reflector below: two shallow dishes, the
        // upper one carrying a row of elements on its face.
        var upper = Path(), lower = Path()
        upper.move(to: u.pt(0.16, 0.17))
        upper.addQuadCurve(to: u.pt(0.84, 0.17), control: u.pt(0.5, 0.01))
        lower.move(to: u.pt(0.16, 0.83))
        lower.addQuadCurve(to: u.pt(0.84, 0.83), control: u.pt(0.5, 0.99))
        u.stroke(context, upper, tint, 0.075)
        u.stroke(context, lower, tint, 0.075)
        for k in 0..<5 {
            let s = 0.2 + 0.15 * Double(k)
            let x = 0.16 + 0.68 * s, y = 0.17 - 0.32 * s * (1 - s)
            let slope = -0.32 * (1 - 2 * s) / 0.68
            let n = (-slope, 1.0), len = hypot(n.0, n.1)
            context.fill(u.circle(x + n.0 / len * 0.075, y + n.1 / len * 0.075, 0.026), with: .color(tint))
        }
    }
}
