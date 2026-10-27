// BatchSLifeScenes.swift
// Capsid — batch S: optical sections, a visit to a flower, a ciliate swimming
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// Confocal z-stack: five thin slabs seen at a gentle slant, stacked one over another, each
/// waiting to receive its section of a rounded cell. A clay focal plane steps down through the
/// stack, stopping at each slab; as it stops, that slab's outline of the cell draws in (small
/// near the top, largest in the middle, small again at the bottom, as slices of a ball would
/// be), clay while the plane is on it and ink once it has moved on. With the last section in,
/// the plane rises back to the top and the outlines fade out as it passes, ready for the next stack.
enum ConfocalZStack {
    static let duration = 5.4

    private static let count = 5
    /// The slabs: middle x, the top slab's middle y, the step between slabs, and a slab's half
    /// width, half shear (how far the back edge leans right) and half depth (up the page).
    private static let cx = 0.5, topY = 0.215, step = 0.16
    private static let halfW = 0.26, halfShear = 0.085, halfDepth = 0.07
    /// Where the plane rests above the stack.
    private static let restY = 0.125
    private static func midY(_ k: Int) -> Double { topY + step * Double(k) }

    /// When the plane arrives at each slab, and when it leaves again (the last waits longest).
    private static let arrive: [Double] = (0..<5).map { 0.75 + 0.7 * Double($0) }
    private static let leave: [Double] = (0..<5).map { (k: Int) -> Double in
        k < 4 ? arrive[k] + 0.3 : 4.05
    }
    private static let returnAt = 4.05, returnEnd = 5.15

    /// The plane's height over time: a hop between slabs, each eased, with a dwell at each.
    private static let route: [(t: Double, y: Double)] = {
        var stops: [(t: Double, y: Double)] = [(0.2, restY)]
        for k in 0..<5 {
            stops.append((arrive[k], midY(k)))
            stops.append((leave[k], midY(k)))
        }
        stops.append((returnEnd, restY))
        return stops
    }()

    private static func planeY(_ t: Double) -> Double {
        guard t > route[0].t else { return route[0].y }
        for i in 0..<(route.count - 1) where t < route[i + 1].t {
            let f = Ease.inOut((t - route[i].t) / (route[i + 1].t - route[i].t))
            return route[i].y + (route[i + 1].y - route[i].y) * f
        }
        return route[route.count - 1].y
    }

    /// When the plane, rising again, passes each slab (found by bisection on the return).
    private static let passes: [Double] = (0..<5).map { (k: Int) -> Double in
        var lo = returnAt, hi = returnEnd
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if planeY(mid) > midY(k) { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// A point on a slab, `a` across and `b` back into the depth (both -1 to 1), about height `cy`.
    private static func spot(_ a: Double, _ b: Double, _ cy: Double) -> (Double, Double) {
        (cx + a * halfW + b * halfShear, cy - b * halfDepth)
    }

    /// A slab's outline, at `scale` times its size.
    private static func slab(_ u: UnitSquare, _ cy: Double, scale s: Double = 1) -> Path {
        var path = u.polyline([spot(-s, -s, cy), spot(s, -s, cy), spot(s, s, cy), spot(-s, s, cy)])
        path.closeSubpath()
        return path
    }

    /// Each section's outline of the cell: the radius of a slice of a ball at that depth.
    private static let sections: [[(Double, Double)]] = (0..<5).map { k in
        let z = Double(k - 2) * 0.4
        let r = 0.78 * sqrt(max(0, 1 - z * z / 0.9025))
        return (0...48).map { i in
            let a = Double.pi + Double(i) / 48 * 2 * Double.pi
            return spot(r * cos(a), r * sin(a), topY + step * Double(k))
        }
    }

    /// The first `f` of a polyline, to draw a line in.
    private static func trimmed(_ points: [(Double, Double)], _ f: Double) -> [(Double, Double)] {
        let n = points.count - 1
        let x = f * Double(n)
        let whole = min(n, Int(x))
        var out = Array(points[0...whole])
        if whole < n {
            let r = x - Double(whole)
            let a = points[whole], b = points[whole + 1]
            out.append((a.0 + (b.0 - a.0) * r, a.1 + (b.1 - a.1) * r))
        }
        return out
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in 0..<count {
            let outline = slab(u, midY(k))
            context.fill(outline, with: .color(tint.opacity(0.05)))
            u.stroke(context, outline, tint.opacity(0.32), 0.03)
        }

        // The focal plane, a little larger than the slabs.
        let py = planeY(t)
        let plane = slab(u, py, scale: 1.14)
        context.fill(plane, with: .color(clay.opacity(0.22)))
        u.stroke(context, plane, clay.opacity(0.85), 0.04)

        // The sections: drawn in as the plane arrives, faded out as it rises past on its way back.
        for k in 0..<count {
            let drawn = Ease.out((t - (arrive[k] - 0.05)) / 0.5)
            let wipe = t >= returnAt ? Ease.clamp((t - passes[k]) / 0.3) : 0
            let f = drawn
            guard f > 0.04, wipe < 1 else { continue }
            let ink = Ease.clamp((t - leave[k]) / 0.25)
            let fill = Ease.clamp((f - 0.6) / 0.4) * (1 - wipe)
            if fill > 0 {
                var body = u.polyline(sections[k])
                body.closeSubpath()
                context.fill(body, with: .color(clay.opacity(0.2 * fill * (1 - ink))))
                context.fill(body, with: .color(tint.opacity(0.14 * fill * ink)))
            }
            let line = u.polyline(trimmed(sections[k], f))
            let fade = 1 - wipe
            if ink < 1 { u.stroke(context, line, clay.opacity((1 - ink) * fade), 0.038) }
            if ink > 0 { u.stroke(context, line, tint.opacity(ink * fade), 0.038) }
        }
    }
}

/// Pollination: a bee hovers beside the first flower's left anther and loads clay pollen from it,
/// flies over to the second flower, brushes its stigma and leaves the pollen there. The view then
/// pans so the second flower takes the first one's place (its stigma dusted, its anthers still full)
/// as a fresh flower arrives behind it, and the bee rides over to the first flower's spot, ready to
/// begin again. Every flower is alike, so the loop is a conveyor.
enum Pollination {
    static let duration = 5.4

    /// The pan, how far apart the flowers stand, where the first one stands, and the height of a cup's base.
    private static let panAt = 3.5, panFor = 1.6
    private static let gap = 0.5, first = 0.33
    private static let head = 0.72
    /// Parts of a flower, from the middle of its cup's base: the left anther the bee works, the
    /// right anther, the stigma, and where the pollen sits on the stigma.
    private static let anther = (-0.05, -0.2), other = (0.055, -0.17)
    private static let stigma = (0.0, -0.285)
    private static let grains: [(Double, Double)] = [(-0.034, -0.318), (0.008, -0.334), (0.042, -0.312)]
    /// Where the bee hovers at the anther and at the stigma, from a flower's cup.
    private static let atAnther = (-0.18, -0.31), atStigma = (0.05, -0.385)
    /// The pollen as the bee carries it, in the bee's own frame.
    private static let load: [(Double, Double)] = [(-0.1, 0.035), (-0.06, 0.068), (-0.02, 0.05)]
    /// When each grain leaves the anther for the bee, and when it leaves the bee for the stigma.
    private static let pickUp: [Double] = [0.4, 0.62, 0.84]
    private static let putDown: [Double] = [2.95, 3.1, 3.25]
    private static let pickFor = 0.4, putFor = 0.3

    private static func pan(_ t: Double) -> Double { Ease.inOut((t - panAt) / panFor) }
    private static func flowerX(_ i: Int, _ t: Double) -> Double { first + gap * Double(i) - gap * pan(t) }

    /// One flower seen from the side: a stem with one small leaf low down, and a cup of three
    /// petals that opens upward. Inside the cup are two stamens with clay anthers, and the pistil
    /// rises between them to a stigma knob just above the rim.
    private static func flower(_ context: GraphicsContext, _ u: UnitSquare, x: Double, tint: Color,
                               spent: Double, grainsOn: [Bool]) {
        var stem = Path()
        stem.move(to: u.pt(x, 1.0))
        stem.addQuadCurve(to: u.pt(x, head + 0.03), control: u.pt(x - 0.03, 0.88))
        u.stroke(context, stem, tint)
        var leaf = context
        let lp = u.pt(x - 0.01, 0.94)
        leaf.translateBy(x: lp.x, y: lp.y)
        leaf.rotate(by: .degrees(-148))
        leaf.fill(Path(ellipseIn: CGRect(x: 0, y: -u.len(0.03), width: u.len(0.12), height: u.len(0.06))), with: .color(tint))

        // The column first, so the petals close round its base.
        u.stroke(context, u.line((x, head), (x, head + stigma.1 + 0.02)), tint, 0.04)
        context.fill(u.ellipse(x + stigma.0, head + stigma.1, 0.09, 0.055), with: .color(tint))
        for (side, a) in [(-1.0, anther), (1.0, other)] {
            u.stroke(context, u.line((x + side * 0.012, head - 0.03), (x + a.0, head + a.1 + 0.02)), tint, 0.03)
        }

        func petal(_ deg: Double, _ d: Double, _ length: Double, _ width: Double) {
            var p = context
            let a = (-90 + deg) * .pi / 180
            let at = u.pt(x + d * cos(a), head + d * sin(a))
            p.translateBy(x: at.x, y: at.y)
            p.rotate(by: .radians(a))
            p.fill(Path(ellipseIn: CGRect(x: -u.len(length / 2), y: -u.len(width / 2),
                                          width: u.len(length), height: u.len(width))), with: .color(tint))
        }
        petal(-32, 0.115, 0.23, 0.105)
        petal(32, 0.115, 0.23, 0.105)
        petal(0, 0.055, 0.12, 0.13)

        for (side, a, loaded) in [(-1.0, anther, 1 - spent), (1.0, other, 1.0)] {
            var sac = context
            let at = u.pt(x + a.0, head + a.1)
            sac.translateBy(x: at.x, y: at.y)
            sac.rotate(by: .degrees(side * 14))
            let shape = Path(ellipseIn: CGRect(x: -u.len(0.03), y: -u.len(0.045), width: u.len(0.06), height: u.len(0.09)))
            sac.fill(shape, with: .color(clay.opacity(loaded)))
            sac.fill(shape, with: .color(tint.opacity(0.45 * (1 - loaded))))
        }
        for (k, g) in grains.enumerated() where grainsOn[k] {
            context.fill(u.circle(x + g.0, head + g.1, 0.027), with: .color(clay))
        }
    }

    /// The bee's place and tilt (degrees, nose down positive) at `t`.
    private static func bee(_ t: Double) -> (x: Double, y: Double, tilt: Double) {
        let wobble = (0.005 * sin(2 * .pi * 2 * t / duration + 1), 0.007 * sin(2 * .pi * 3 * t / duration))
        let f1 = flowerX(0, t), f2 = flowerX(1, t)
        let a = (f1 + atAnther.0, head + atAnther.1)
        let b = (f2 + atStigma.0, head + atStigma.1)
        var p: (Double, Double), tilt: Double
        if t < 1.3 {
            p = a
            tilt = -4 + 3 * sin(2 * .pi * 2 * t / duration)
        } else if t < 2.8 {
            // Up and over: a cubic from the first flower to the second.
            let s = Ease.inOut((t - 1.3) / 1.5)
            let c1 = (a.0 + 0.06, a.1 - 0.2), c2 = (b.0 - 0.12, b.1 - 0.16)
            let m = 1 - s
            p = (m * m * m * a.0 + 3 * m * m * s * c1.0 + 3 * m * s * s * c2.0 + s * s * s * b.0,
                 m * m * m * a.1 + 3 * m * m * s * c1.1 + 3 * m * s * s * c2.1 + s * s * s * b.1)
            tilt = -12 + 24 * s
        } else {
            // On the second flower, then riding it as the view pans, lifting over its stigma to the first spot.
            let q = pan(t)
            let from = (atStigma.0, atStigma.1), to = (atAnther.0, atAnther.1), c = (-0.07, -0.48)
            let m = 1 - q
            p = (f2 + m * m * from.0 + 2 * m * q * c.0 + q * q * to.0,
                 head + m * m * from.1 + 2 * m * q * c.1 + q * q * to.1)
            tilt = 12 - 16 * q
        }
        return (p.0 + wobble.0, p.1 + wobble.1, tilt)
    }

    /// A grain in the bee's frame, as a point in the square.
    private static func carried(_ k: Int, _ pose: (x: Double, y: Double, tilt: Double)) -> (Double, Double) {
        let a = pose.tilt * .pi / 180
        return (pose.x + load[k].0 * cos(a) - load[k].1 * sin(a), pose.y + load[k].0 * sin(a) + load[k].1 * cos(a))
    }

    private static func drawBee(_ context: GraphicsContext, _ u: UnitSquare, pose: (x: Double, y: Double, tilt: Double),
                                t: Double, tint: Color, carrying: [Bool]) {
        var b = context
        let at = u.pt(pose.x, pose.y)
        b.translateBy(x: at.x, y: at.y)
        b.rotate(by: .degrees(pose.tilt))
        let flap = 13 * sin(2 * .pi * 22 * t / duration)
        // Two wings, swept back and up from the back of the thorax.
        for base in [-100.0, -142.0] {
            var wing = b
            wing.translateBy(x: -u.len(0.01), y: -u.len(0.045))
            wing.rotate(by: .degrees(base + flap * (base < -120 ? 0.8 : 1)))
            wing.fill(Path(ellipseIn: CGRect(x: 0, y: -u.len(0.027), width: u.len(0.13), height: u.len(0.054))),
                      with: .color(tint.opacity(0.5)))
        }
        // The body, striped by cutting bands out of it.
        b.drawLayer { layer in
            layer.fill(Path(ellipseIn: CGRect(x: -u.len(0.115), y: -u.len(0.06), width: u.len(0.23), height: u.len(0.12))),
                       with: .color(tint))
            layer.blendMode = .destinationOut
            for sx in [-0.065, -0.005, 0.055] {
                layer.fill(Path(CGRect(x: u.len(sx - 0.012), y: -u.len(0.08), width: u.len(0.024), height: u.len(0.16))),
                           with: .color(.black))
            }
        }
        for (k, on) in carrying.enumerated() where on {
            let r = max(u.len(0.027), 0.4)
            b.fill(Path(ellipseIn: CGRect(x: u.len(load[k].0) - r, y: u.len(load[k].1) - r, width: 2 * r, height: 2 * r)),
                   with: .color(clay))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var scene = context
        scene.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.side)))

        // The first flower gives up its pollen to the bee; the second takes it; a third waits.
        let spent = Ease.clamp((t - pickUp[2]) / 0.25)
        let landed = (0..<3).map { t >= putDown[$0] + putFor }
        flower(scene, u, x: flowerX(0, t), tint: tint, spent: spent, grainsOn: [true, true, true])
        flower(scene, u, x: flowerX(1, t), tint: tint, spent: 0, grainsOn: landed)
        flower(scene, u, x: flowerX(2, t), tint: tint, spent: 0, grainsOn: [false, false, false])

        let pose = bee(t)
        // Grains still on the bee, and in flight between the anther and the bee or the bee and the stigma.
        var carrying = [false, false, false]
        for k in 0..<3 {
            let pick = (t - pickUp[k]) / pickFor
            let put = (t - putDown[k]) / putFor
            if pick >= 1 && put < 0 {
                carrying[k] = true
            } else if pick > 0 && pick < 1 {
                let from = (flowerX(0, t) + anther.0, head + anther.1)
                let to = carried(k, pose)
                let e = Ease.inOut(pick)
                scene.fill(u.circle(from.0 + (to.0 - from.0) * e, from.1 + (to.1 - from.1) * e - 0.03 * sin(.pi * pick), 0.027),
                           with: .color(clay))
            } else if put > 0 && put < 1 {
                let from = carried(k, pose)
                let to = (flowerX(1, t) + grains[k].0, head + grains[k].1)
                let e = Ease.inOut(put)
                scene.fill(u.circle(from.0 + (to.0 - from.0) * e, from.1 + (to.1 - from.1) * e, 0.027), with: .color(clay))
            }
        }
        drawBee(scene, u, pose: pose, t: t, tint: tint, carrying: carrying)
    }
}

/// Paramecium: a slipper-shaped ciliate, blunt at the front and tapering behind, swims slowly
/// about the middle of the square, weaving a little on its way. An even fringe of short cilia round
/// the outline leans and straightens in a wave that runs back along the body, and an oral groove
/// sweeps in from the front on the underside. Two contractile vacuoles, each a round clay vesicle
/// with tapering canals radiating from it, fill and empty in turn. The wave, the weave and the vacuole cycles all repeat a whole
/// number of times in the loop, so it closes by construction.
enum Paramecium {
    static let duration = 5.0

    private static let length = 0.8, halfWidth = 0.125
    /// The body's half width at `s` of the way from the tail to the blunt front.
    private static func profile(_ s: Double) -> Double {
        let peak = 0.62
        return halfWidth * pow(s, 0.85) * pow(1 - s, 0.52) / (pow(peak, 0.85) * pow(1 - peak, 0.52))
    }

    private static let segments = 36
    /// The outline in the body's own frame: along the body (tail to front), then across (back
    /// on top, belly below), in one closed loop from the tail over the top and back under.
    private static let outline: [(Double, Double)] = {
        let n = segments
        func s(_ i: Int) -> Double { (1 - cos(Double.pi * Double(i) / Double(n))) / 2 }
        let top = (0...n).map { ((s($0) - 0.5) * length, -profile(s($0))) }
        let belly = (1..<n).reversed().map { ((s($0) - 0.5) * length, profile(s($0))) }
        return top + belly
    }()

    /// A cilium's root on the outline, which way is out, which way is back along the body, and
    /// how far along the body it stands (for the phase of the wave).
    private struct Root {
        let x: Double, y: Double, nx: Double, ny: Double, bx: Double, by: Double, along: Double
    }
    private static let cilia = 38
    private static let roots: [Root] = {
        let pts = outline + [outline[0]]
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].0 - pts[i - 1].0, pts[i].1 - pts[i - 1].1)) }
        let total = cum[cum.count - 1]
        var out: [Root] = []
        var seg = 0
        for k in 0..<cilia {
            let at = (Double(k) + 0.5) * total / Double(cilia)
            while seg < pts.count - 2 && cum[seg + 1] < at { seg += 1 }
            let a = pts[seg], b = pts[seg + 1]
            let run = max(cum[seg + 1] - cum[seg], 1e-9)
            let f = (at - cum[seg]) / run
            let tx = (b.0 - a.0) / run, ty = (b.1 - a.1) / run
            // Outward is the tangent turned a quarter; "back" runs tailwards along the body's side.
            let onTop = seg < segments
            out.append(Root(x: a.0 + (b.0 - a.0) * f, y: a.1 + (b.1 - a.1) * f, nx: ty, ny: -tx,
                            bx: onTop ? -tx : tx, by: onTop ? -ty : ty,
                            along: (a.0 + (b.0 - a.0) * f) / length + 0.5))
        }
        return out
    }()

    private static let beats = 6.0, waves = 2.5
    /// The oral groove: one curve sweeping in from the belly edge near the front, then flattening towards the middle.
    private static let groove: [(Double, Double)] = (0...16).map { k in
        let f = Double(k) / 16, m = 1 - f
        let p0 = (0.25, profile(0.81)), p1 = (0.18, 0.095), p2 = (0.12, 0.06), p3 = (0.03, 0.05)
        return (m * m * m * p0.0 + 3 * m * m * f * p1.0 + 3 * m * f * f * p2.0 + f * f * f * p3.0,
                m * m * m * p0.1 + 3 * m * m * f * p1.1 + 3 * m * f * f * p2.1 + f * f * f * p3.1)
    }

    private static func vacuole(_ context: GraphicsContext, _ u: UnitSquare, at c: (Double, Double), turn: Double, phase p: Double) {
        // Canals fill and reach out, then empty into the round vesicle, which swells and finally empties.
        let reach: Double, hub: Double
        if p < 0.6 {
            reach = 0.55 + 0.45 * Ease.out(p / 0.6)
            hub = 0.04
        } else if p < 0.85 {
            let e = Ease.inOut((p - 0.6) / 0.25)
            reach = 1 - 0.45 * e
            hub = 0.04 + 0.016 * e
        } else {
            let e = Ease.inOut((p - 0.85) / 0.15)
            reach = 0.55
            hub = 0.056 - 0.016 * e
        }
        // Six canals, each tapering from the vesicle's edge to a point.
        for k in 0..<6 {
            let a = turn + Double(k) * .pi / 3
            let out = (cos(a), sin(a)), across = (-sin(a), cos(a))
            let tip = hub + 0.012 + 0.04 * reach
            var canal = Path()
            canal.move(to: u.pt(c.0 + out.0 * hub * 0.6 + across.0 * 0.011, c.1 + out.1 * hub * 0.6 + across.1 * 0.011))
            canal.addLine(to: u.pt(c.0 + out.0 * tip, c.1 + out.1 * tip))
            canal.addLine(to: u.pt(c.0 + out.0 * hub * 0.6 - across.0 * 0.011, c.1 + out.1 * hub * 0.6 - across.1 * 0.011))
            canal.closeSubpath()
            context.fill(canal, with: .color(clay))
        }
        context.fill(u.circle(c.0, c.1, hub), with: .color(clay))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let w = 2 * Double.pi * t / duration
        // Heading rocks a little about 18 degrees up the page, and the whole body weaves.
        let psi = (-20 + 5 * sin(w + 1)) * Double.pi / 180
        let centre = (0.5 + 0.03 * sin(w), 0.5 + 0.02 * sin(2 * w + 0.7))
        let cs = cos(psi), sn = sin(psi)
        func place(_ p: (Double, Double)) -> (Double, Double) {
            (centre.0 + p.0 * cs - p.1 * sn, centre.1 + p.0 * sn + p.1 * cs)
        }

        var body = u.polyline(outline.map(place))
        body.closeSubpath()
        context.fill(body, with: .color(tint.opacity(0.1)))
        u.stroke(context, body, tint, 0.05)

        for r in roots {
            let phi = 2 * Double.pi * (beats * t / duration + waves * r.along)
            let tilt = 0.4 + 0.4 * sin(phi)
            let len = 0.052 * (0.97 + 0.03 * cos(phi))
            func dir(_ a: Double) -> (Double, Double) { (r.nx * cos(a) + r.bx * sin(a), r.ny * cos(a) + r.by * sin(a)) }
            let mid = dir(tilt * 0.6), end = dir(tilt)
            let root = place((r.x, r.y))
            var hair = Path()
            hair.move(to: u.pt(root.0, root.1))
            let c = place((r.x + 0.5 * len * mid.0, r.y + 0.5 * len * mid.1))
            let e = place((r.x + len * end.0, r.y + len * end.1))
            hair.addQuadCurve(to: u.pt(e.0, e.1), control: u.pt(c.0, c.1))
            u.stroke(context, hair, tint, 0.03)
        }

        u.stroke(context, u.polyline(groove.map(place)), tint, 0.045)

        let front = place((0.15, -0.03)), tail = place((-0.19, -0.02))
        vacuole(context, u, at: front, turn: psi + 0.26, phase: (2 * t / duration).truncatingRemainder(dividingBy: 1))
        vacuole(context, u, at: tail, turn: psi + 0.26, phase: (2 * t / duration + 0.5).truncatingRemainder(dividingBy: 1))
    }
}
