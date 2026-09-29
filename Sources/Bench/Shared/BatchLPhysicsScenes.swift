// BatchLPhysicsScenes.swift
// ScienceStatus — physics: light split by a prism, a magnet through a coil,
// and a Van de Graaff sparking.
// Each draws in a unit square (see `UnitSquare`): the apparatus in the tint,
// the one thing each is about (red's ray, the north pole, the charge) in clay.

import SwiftUI

/// A prism splits white light: a single beam draws in from the left, bends
/// through a glass triangle and fans out into five rays that land as marks
/// on a thin screen. Red bends least, so it is the top ray, in clay; the
/// rest step down in tint. Then the source goes off and the light drains
/// away down its own path, and it goes again.
enum Prism {
    static let duration = 4.0

    private static let apexX = 0.38, apexY = 0.20, baseY = 0.578, halfBase = 0.218
    private static let beamY = 0.44, exitY = 0.47, screenX = 0.92
    /// How far below level each ray leaves the glass, in degrees: the
    /// glass bends violet most, so the fan opens downwards from red's ray.
    private static let bends: [Double] = [4, 14, 24, 34, 44]
    /// Each ray's ink, red's first; the rest are opacity steps of the tint.
    private static let steps: [Double] = [1, 0.9, 0.75, 0.62, 0.5]

    private static func leftFace(_ y: Double) -> Double { apexX - halfBase * (y - apexY) / (baseY - apexY) }
    private static func rightFace(_ y: Double) -> Double { apexX + halfBase * (y - apexY) / (baseY - apexY) }

    /// Where the beam meets the glass, and where the rays leave it.
    private static let entering: (Double, Double) = (leftFace(beamY), beamY)
    private static let leaving: (Double, Double) = (rightFace(exitY), exitY)
    /// Where each ray meets the screen.
    private static let landings: [(Double, Double)] = bends.map { (bend: Double) -> (Double, Double) in
        let drop: Double = (screenX - rightFace(exitY)) * tan(bend * .pi / 180)
        return (screenX, exitY + drop)
    }

    /// How far along a stretch of the light's path, from `lo` to `hi` of the
    /// whole, the front `s` has got.
    private static func part(_ s: Double, _ lo: Double, _ hi: Double) -> Double {
        Ease.clamp((s - lo) / (hi - lo))
    }

    /// The lit part of the straight run `a` to `b`, between the tail and the front.
    private static func lit(_ u: UnitSquare, _ a: (Double, Double), _ b: (Double, Double), tail: Double, head: Double) -> Path? {
        guard head > tail else { return nil }
        let from: (Double, Double) = (a.0 + (b.0 - a.0) * tail, a.1 + (b.1 - a.1) * tail)
        let to: (Double, Double) = (a.0 + (b.0 - a.0) * head, a.1 + (b.1 - a.1) * head)
        return u.line(from, to)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // The screen and the glass: always there, so the first frame is not empty.
        u.stroke(context, u.line((screenX, 0.46), (screenX, 0.89)), tint.opacity(0.55), 0.045)
        var glass = u.polyline([(apexX, apexY), (apexX - halfBase, baseY), (apexX + halfBase, baseY)])
        glass.closeSubpath()
        context.fill(glass, with: .color(tint.opacity(0.12)))
        u.stroke(context, glass, tint, 0.06)

        // The light runs the whole path at a steady pace (it doesn't ease);
        // when the source goes off the tail follows the same way.
        let head = Ease.clamp((t - 0.2) / 1.3)
        let tail = Ease.clamp((t - 2.65) / 1.1)

        // The beam in, then the short way through the glass.
        let source: (Double, Double) = (0.03, beamY)
        if let beam = lit(u, source, entering, tail: part(tail, 0, 0.3), head: part(head, 0, 0.3)) {
            u.stroke(context, beam, tint, 0.065)
        }
        if let inside = lit(u, entering, leaving, tail: part(tail, 0.3, 0.55), head: part(head, 0.3, 0.55)) {
            u.stroke(context, inside, tint.opacity(0.75), 0.05)
        }

        // The fan, and where it lands.
        let fanHead = part(head, 0.55, 1)
        let fanTail = part(tail, 0.55, 1)
        let pop = Ease.outBack((t - 1.5) / 0.2)
        let fade = 1 - Ease.clamp((fanTail - 0.6) / 0.4)
        for (k, landing) in landings.enumerated() {
            let ink: Color = k == 0 ? clay : tint.opacity(steps[k])
            if let ray = lit(u, leaving, landing, tail: fanTail, head: fanHead) {
                u.stroke(context, ray, ink, 0.045)
            }
            if pop > 0, fade > 0 {
                let width = 0.085 * min(1, pop)
                context.fill(u.capsule(screenX, landing.1, width, 0.045, corner: 0.012), with: .color(ink.opacity(fade)))
            }
        }
    }
}

/// Faraday's induction: a bar magnet, its north pole clay, slides along the
/// axis of a six-turn coil and back out. The galvanometer above, wired into a
/// circuit with the coil's two ends, swings one way as the magnet goes in and the other as it
/// comes out, by as much as it is moving, and rests at zero while it is still.
enum FaradayCoil {
    static let duration = 4.0

    /// The coil: `turns` of a helix along a horizontal axis, whose two ends
    /// are both at the top, where the leads leave.
    private static let axisY = 0.75, halfTall = 0.095
    private static let startX = 0.345, pitch = 0.09, turns = 6
    /// How far the helix leans, so each turn reads as a loop round the axis.
    private static let lean = 0.05
    private static let endX = startX + pitch * Double(turns)

    /// The meter is a round dial in the circuit's top rail; its needle
    /// pivots from a little below the middle of it.
    private static let railY = 0.36
    private static let pivotX = startX + pitch * Double(turns) / 2
    private static let dialR = 0.17, needle = 0.1
    private static let pivotY = railY + 0.05
    /// The ticks along the scale, in degrees either side of straight up.
    private static let ticks: [Double] = [-50, -25, 0, 25, 50]

    private static let magnetLength = 0.26, magnetHeight = 0.11
    private static let outside = 0.17, inside = pivotX
    /// In slowly, out quicker: the needle should swing further on the way
    /// out, and it can, being tied to speed.
    private static let slide: [(Double, Double)] = [(0.25, outside), (1.45, inside), (2.35, inside), (3.15, outside)]
    /// Radians of swing for each unit of magnet speed.
    private static let gain = 27.0 * Double.pi / 180

    /// Half a turn of the helix as points. Even halves come down the front of
    /// the coil, odd ones climb back up behind it.
    private static func half(_ index: Int) -> [(Double, Double)] {
        (0...10).map { (k: Int) -> (Double, Double) in
            let phi: Double = Double.pi * (Double(index) + Double(k) / 10)
            let x: Double = startX + pitch * phi / (2 * Double.pi) + lean * sin(phi)
            return (x, axisY - halfTall * cos(phi))
        }
    }
    private static let frontStrands: [[(Double, Double)]] = (0..<turns).map { half(2 * $0) }
    private static let backStrands: [[(Double, Double)]] = (0..<turns).map { half(2 * $0 + 1) }

    /// The wires: up from the coil's two ends and in to either side of the dial.
    private static let leads: [[(Double, Double)]] = [
        [(startX, axisY - halfTall), (startX, railY), (pivotX - dialR, railY)],
        [(endX, axisY - halfTall), (endX, railY), (pivotX + dialR, railY)],
    ]

    private static func magnetX(_ t: Double) -> Double { Keyframes.value(t, slide) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // The wires, and the galvanometer between them with its ticks.
        for lead in leads { u.stroke(context, u.polyline(lead), tint, 0.04) }
        context.fill(u.circle(pivotX, railY, dialR), with: .color(tint.opacity(0.1)))
        u.stroke(context, u.circle(pivotX, railY, dialR), tint, 0.05)
        for deg in ticks {
            let a: Double = deg * .pi / 180
            let inner: (Double, Double) = (pivotX + 0.13 * sin(a), pivotY - 0.13 * cos(a))
            let outer: (Double, Double) = (pivotX + 0.16 * sin(a), pivotY - 0.16 * cos(a))
            u.stroke(context, u.line(inner, outer), tint.opacity(0.6), 0.03)
        }

        // The needle follows the magnet's speed: the slope of its own
        // position, so it is still whenever the magnet is, and the sign
        // flips between going in and coming out.
        let h = 0.02
        let speed: Double = (magnetX(t + h) - magnetX(t - h)) / (2 * h)
        let swing: Double = speed * gain
        let tip: (Double, Double) = (pivotX + needle * sin(swing), pivotY - needle * cos(swing))
        u.stroke(context, u.line((pivotX, pivotY), tip), tint, 0.045)
        context.fill(u.circle(pivotX, pivotY, 0.035), with: .color(tint))

        // The coil: the back strands dim, and gone behind the magnet; then
        // the magnet; then the front strands over it, so it reads as inside.
        let mx = magnetX(t)
        let body = u.capsule(mx, axisY, magnetLength, magnetHeight, corner: 0.025)
        context.drawLayer { back in
            for strand in backStrands { u.stroke(back, u.polyline(strand), tint.opacity(0.5), 0.04) }
            back.blendMode = .destinationOut
            back.fill(body, with: .color(.black))
        }
        // The south half is the tint at a step down, so the front strands still show across it.
        let middle = u.pt(mx, 0).x
        var south = context
        south.clip(to: Path(CGRect(x: u.origin.x - u.side, y: u.origin.y, width: middle - u.origin.x + u.side, height: u.side)))
        south.fill(body, with: .color(tint.opacity(0.6)))
        var north = context
        north.clip(to: Path(CGRect(x: middle, y: u.origin.y, width: u.side, height: u.side)))
        north.fill(body, with: .color(clay))
        for strand in frontStrands { u.stroke(context, u.polyline(strand), tint, 0.05) }
    }
}

/// A Van de Graaff generator: a belt runs up inside the column and carries
/// charge to the dome, where clay dots gather one by one. When the dome is
/// full a jagged clay spark leaps to the grounded sphere beside it, the
/// charge is gone, and it starts to fill again.
enum VanDeGraaff {
    static let duration = 4.4

    private static let dome: (x: Double, y: Double) = (0.31, 0.28)
    private static let domeR = 0.2, halfColumn = 0.08
    private static let sphere: (x: Double, y: Double) = (0.83, 0.28)
    private static let sphereR = 0.075
    /// Where the belt's charge comes off at the top, and its roller at the foot.
    private static let rollerTop = 0.40, rollerBottom = 0.75
    /// One belt dash moves up a pitch every `beat` seconds, which divides
    /// the scene evenly so the belt is where it began when it loops.
    private static let pitch = 0.1, beat = 0.55
    /// When the spark strikes: the last charge has settled, and a beat is spent looking at the full dome.
    private static let zap = 3.34

    /// Where the column's sides meet the dome.
    private static let joinY: Double = dome.y + (domeR * domeR - halfColumn * halfColumn).squareRoot()

    /// Where the seven charges settle on the dome, in the order they arrive:
    /// six round its wall and one in the middle.
    private static let slots: [(Double, Double)] = {
        let order: [Int] = [2, 4, 0, 3, 5, 1, 6]
        let ring: [Double] = [165, 208, 251, 294, 337, 20]
        return order.map { (index: Int) -> (Double, Double) in
            guard index < ring.count else { return (dome.x, dome.y) }
            let a: Double = ring[index] * .pi / 180
            return (dome.x + 0.12 * cos(a), dome.y + 0.12 * sin(a))
        }
    }()

    /// The spark's flickering shapes, each a zigzag between the dome and the
    /// sphere: how far along, and how far off line, each of its corners is.
    private static let sparks: [[(Double, Double)]] = {
        let start: Double = dome.x + domeR - 0.01
        let end: Double = sphere.x - sphereR + 0.01
        let corners: [[(Double, Double)]] = [
            [(0.20, -0.06), (0.40, 0.05), (0.62, -0.07), (0.80, 0.05)],
            [(0.18, 0.06), (0.45, -0.06), (0.58, 0.07), (0.82, -0.05)],
            [(0.25, -0.05), (0.38, 0.07), (0.66, -0.05), (0.78, 0.06)],
        ]
        return corners.map { (shape: [(Double, Double)]) -> [(Double, Double)] in
            var points: [(Double, Double)] = [(start, dome.y)]
            for corner in shape {
                let x: Double = start + (end - start) * corner.0
                points.append((x, dome.y + corner.1))
            }
            points.append((end, sphere.y))
            return points
        }
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)

        // The dome on its column, the base, and the grounded sphere on its own stand.
        let column = CGRect(x: u.pt(dome.x - halfColumn, 0).x, y: u.pt(0, dome.y + domeR).y, width: u.len(2 * halfColumn), height: u.len(0.84 - dome.y - domeR))
        context.fill(Path(column), with: .color(tint.opacity(0.1)))
        context.fill(u.circle(dome.x, dome.y, domeR), with: .color(tint.opacity(0.1)))
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((dome.x + side * halfColumn, joinY), (dome.x + side * halfColumn, 0.84)), tint, 0.05)
        }
        u.stroke(context, u.circle(dome.x, dome.y, domeR), tint, 0.06)
        context.fill(u.capsule(dome.x, 0.865, 0.46, 0.09, corner: 0.03), with: .color(tint))
        context.fill(u.circle(sphere.x, sphere.y, sphereR), with: .color(tint.opacity(0.1)))
        u.stroke(context, u.circle(sphere.x, sphere.y, sphereR), tint, 0.06)
        u.stroke(context, u.line((sphere.x, sphere.y + sphereR), (sphere.x, 0.84)), tint, 0.05)
        context.fill(u.capsule(sphere.x, 0.865, 0.2, 0.09, corner: 0.03), with: .color(tint))
        // The ground wire linking the two bases.
        u.stroke(context, u.line((dome.x + 0.23, 0.865), (sphere.x - 0.1, 0.865)), tint.opacity(0.55), 0.03)

        // The belt: a roller at the foot and dashes travelling up the column into the dome.
        u.stroke(context, u.circle(dome.x, rollerBottom, 0.035), tint.opacity(0.6), 0.03)
        let phase: Double = (t / beat).truncatingRemainder(dividingBy: 1)
        for k in 0..<4 {
            let y: Double = rollerBottom - (Double(k) + phase) * pitch
            // Fade in as it leaves the roller and out as it enters the dome.
            let rise: Double = Ease.clamp((rollerBottom - 0.03 - y) / 0.05)
            let leave: Double = Ease.clamp((y - rollerTop) / 0.05)
            let alpha: Double = min(rise, leave)
            guard alpha > 0 else { continue }
            u.stroke(context, u.line((dome.x, y - 0.025), (dome.x, y + 0.025)), tint.opacity(alpha), 0.045)
        }

        // Charge the belt lifts spreads over the dome, one dot at a time;
        // when the spark strikes it is drawn out to it and gone.
        let drawn: Double = Ease.inOut((t - zap) / 0.16)
        let mouth: (Double, Double) = (dome.x + domeR - 0.03, dome.y)
        for (n, slot) in slots.enumerated() {
            let born: Double = 0.1 + 0.43 * Double(n)
            guard t > born, drawn < 1 else { continue }
            let fly: Double = Ease.out((t - born) / 0.35)
            let x: Double = dome.x + (slot.0 - dome.x) * fly
            let y: Double = rollerTop + (slot.1 - rollerTop) * fly
            let r: Double = (0.03 + 0.017 * fly) * (1 - drawn)
            context.fill(u.circle(x + (mouth.0 - x) * drawn, y + (mouth.1 - y) * drawn, r), with: .color(clay))
        }

        // The spark: drawn in fast, flickering between shapes, then out.
        let strike = t - zap
        if strike > 0, strike < 0.28 {
            let shape: Int = strike < 0.05 ? 0 : Int((strike - 0.05) / 0.045) % sparks.count
            let reach: Double = Ease.clamp(strike / 0.05)
            let alpha: Double = 1 - Ease.clamp((strike - 0.22) / 0.06)
            let path: Path = u.polyline(sparks[shape]).trimmedPath(from: 0, to: reach)
            u.stroke(context, path, clay.opacity(alpha), 0.05)
        }
    }
}
