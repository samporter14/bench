// LabLifeScenes.swift
// ScienceStatus — the life of a lab round the experiments: coffee, the
// notebook, gloves, the waste, and the big shared machines. Each draws in a
// unit square (see `UnitSquare`): kit in the tint, what matters in clay.

import SwiftUI

/// The value at `t` along a list of (time, value) keys, easing in and out
/// between each pair and held before the first and after the last. For
/// scenes with a lot of choreography.
enum Keyframes {
    static func value(_ t: Double, _ keys: [(Double, Double)]) -> Double {
        guard let first = keys.first else { return 0 }
        if t <= first.0 { return first.1 }
        for i in 1..<keys.count where t < keys[i].0 {
            let a = keys[i - 1], b = keys[i]
            return a.1 + (b.1 - a.1) * Ease.inOut((t - a.0) / (b.0 - a.0))
        }
        return keys[keys.count - 1].1
    }
}

/// Another cup of coffee: an empty mug slides in, the pot tips in and fills
/// it with clay coffee, it steams a moment, and slides off to be drunk.
enum Coffee {
    static let duration = 4.4
    private static let spout = (0.45, 0.19)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let slide = -0.8 * (1 - Ease.out(t / 0.4)) + 0.8 * Ease.inOut((t - 3.8) / 0.45)
        let filled = Ease.inOut((t - 0.95) / 1.05)
        let level = 0.86 - 0.24 * filled

        var mug = context
        mug.translateBy(x: u.len(slide), y: 0)
        var cup = Path()
        cup.move(to: u.pt(0.36, 0.56))
        cup.addLine(to: u.pt(0.37, 0.82))
        cup.addQuadCurve(to: u.pt(0.41, 0.87), control: u.pt(0.37, 0.87))
        cup.addLine(to: u.pt(0.59, 0.87))
        cup.addQuadCurve(to: u.pt(0.63, 0.82), control: u.pt(0.63, 0.87))
        cup.addLine(to: u.pt(0.64, 0.56))
        if filled > 0 { BenchShapes.fill(mug, u, cup, from: level, clay) }
        u.stroke(mug, cup, tint, 0.045)
        var handle = Path()
        handle.addArc(center: u.pt(0.64, 0.7), radius: u.len(0.075), startAngle: .degrees(-75), endAngle: .degrees(75), clockwise: false)
        u.stroke(mug, handle, tint, 0.045)
        for (k, x) in [0.45, 0.51, 0.57].enumerated() {
            let life = Ease.clamp((t - 2.4 - 0.2 * Double(k)) / 1.3)
            guard life > 0, life < 1 else { continue }
            let wisp = stride(from: 0.0, through: 0.18, by: 0.015).map { d in
                (x + 0.018 * sin(d * 40 - t * 5 + Double(k)), 0.52 - d - 0.08 * life)
            }
            u.stroke(mug, u.polyline(wisp), tint.opacity(0.5 * sin(.pi * life)), 0.028)
        }

        // The pot comes in from the top left, tips about its spout, pours.
        let away = 1 - Ease.out((t - 0.2) / 0.4) + Ease.inOut((t - 2.35) / 0.4)
        let tilt = Ease.inOut((t - 0.6) / 0.35) - Ease.inOut((t - 2.0) / 0.35)
        guard away < 1 else { return }
        var pot = context
        let tip = u.pt(spout.0, spout.1)
        pot.translateBy(x: u.len(-0.5 * away), y: u.len(-0.5 * away))
        pot.translateBy(x: tip.x, y: tip.y)
        pot.rotate(by: .degrees(50 * tilt))
        pot.translateBy(x: -tip.x, y: -tip.y)
        pot.fill(u.capsule(0.26, 0.36, 0.24, 0.28, corner: 0.05), with: .color(tint))
        var nose = u.line((0.35, 0.23), (spout.0, spout.1), (0.37, 0.3))
        nose.closeSubpath()
        pot.fill(nose, with: .color(tint))
        u.stroke(pot, u.capsule(0.11, 0.36, 0.08, 0.16, corner: 0.035), tint, 0.04)
        let pour = Ease.clamp((tilt - 0.8) / 0.2)
        if pour > 0, away == 0 {
            u.stroke(context, u.line((spout.0 + 0.01, spout.1 + 0.02), (spout.0 + 0.01, level)), clay, 0.03 * pour)
        }
    }
}

/// The lab notebook: the lab marker writes three lines in clay on the right
/// page and underlines the last, then the page turns over for tomorrow.
enum Notebook {
    static let duration = 4.6
    private static let lines = [0.34, 0.46, 0.58]
    private static let lengths = [0.3, 0.26, 0.2]
    private static let spine = 0.5

    /// The handwriting on line `k`, `s` from 0 to 1: loops along the line.
    private static func hand(_ k: Int, _ s: Double) -> (Double, Double) {
        let phase = s * 40 + Double(k)
        return (0.57 + lengths[k] * s + 0.012 * sin(phase), lines[k] - 0.016 - 0.014 * cos(phase) + 0.004 * sin(s * 13))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.5, 0.86, 0.62, corner: 0.03), tint, 0.045)
        u.stroke(context, u.line((spine, 0.19), (spine, 0.81)), tint, 0.035)
        for (k, y) in [0.32, 0.42, 0.52, 0.62, 0.72].enumerated() {
            u.stroke(context, u.line((0.14, y), (0.44 - 0.05 * Double(k % 3), y)), tint.opacity(0.3), 0.025)
        }

        // The page: written on, then turned about the spine.
        let turn = Ease.inOut((t - 3.6) / 0.7)
        let scale = cos(.pi * turn)
        var page = context
        let hinge = u.pt(spine, 0.5)
        page.translateBy(x: hinge.x, y: hinge.y)
        page.scaleBy(x: max(abs(scale), 0.001) * (scale < 0 ? -1 : 1), y: 1)
        page.translateBy(x: -hinge.x, y: -hinge.y)
        if turn > 0 { u.stroke(page, u.capsule(0.71, 0.5, 0.42, 0.62, corner: 0.03), tint, 0.035) }
        var pen = (0.9, 0.1)
        if scale > 0 {
            for k in 0..<lines.count {
                let s = Ease.clamp((t - 0.3 - 0.9 * Double(k)) / 0.8)
                guard s > 0 else { continue }
                let written = stride(from: 0.0, through: s, by: 0.005).map { hand(k, $0) }
                u.stroke(page, u.polyline(written), clay, 0.022)
                if s < 1 { pen = hand(k, s) }
            }
            let under = Ease.inOut((t - 3.0) / 0.3)
            if under > 0 {
                let y = lines[2] + 0.02
                u.stroke(page, u.line((0.57, y), (0.57 + 0.24 * under, y)), clay, 0.025)
                if under < 1 { pen = (0.57 + 0.24 * under, y) }
            }
        }
        // The marker: at the writing, gliding between lines, then away.
        let writing = t > 0.3 && t < 3.3
        let between = (0...2).contains { k in
            let end = 0.3 + 0.9 * Double(k) + 0.8
            return t >= end && t < end + 0.1
        }
        if writing && !between && turn == 0 {
            var marker = context
            let at = u.pt(pen.0, pen.1)
            marker.translateBy(x: at.x, y: at.y)
            marker.rotate(by: .degrees(-58))
            marker.fill(Path(roundedRect: CGRect(x: u.len(0.02), y: -u.len(0.025), width: u.len(0.3), height: u.len(0.05)),
                             cornerRadius: u.len(0.02)), with: .color(tint))
            var nib = Path()
            nib.move(to: .zero)
            nib.addLine(to: CGPoint(x: u.len(0.025), y: -u.len(0.02)))
            nib.addLine(to: CGPoint(x: u.len(0.025), y: u.len(0.02)))
            nib.closeSubpath()
            marker.fill(nib, with: .color(clay))
        }
    }
}

/// Gloving up: a clay glove pulls on over the hand from the fingertips to
/// the cuff, the fingers flex, then it peels back off inside out and drops.
enum Gloves {
    static let duration = 4.4
    private static let fingers: [(x: Double, top: Double)] = [(0.39, 0.22), (0.47, 0.16), (0.55, 0.18), (0.63, 0.24)]

    private static func pieces(_ u: UnitSquare, flex: Double, grow: Double) -> [Path] {
        var parts = [u.capsule(0.51, 0.6, 0.32 + grow, 0.3 + grow, corner: 0.09), u.capsule(0.5, 0.82, 0.22 + grow, 0.24, corner: 0.04)]
        for (k, f) in fingers.enumerated() {
            let top = f.top + flex * (k % 2 == 0 ? 1 : -1) - grow / 2
            parts.append(u.capsule(f.x, (top + 0.56) / 2, 0.075 + grow, 0.56 - top, corner: 0.037 + grow / 2))
        }
        parts.append(u.line((0.38, 0.66), (0.26, 0.5)).strokedPath(StrokeStyle(lineWidth: u.len(0.075 + grow), lineCap: .round)))
        return parts
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let flex = 0.02 * sin((t - 1.3) * 12) * sin(.pi * Ease.clamp((t - 1.3) / 1.1))
        for piece in pieces(u, flex: flex, grow: 0) { context.fill(piece, with: .color(tint)) }

        let on = Ease.inOut((t - 0.3) / 0.9)
        let off = Ease.inOut((t - 2.6) / 0.7)
        let edge = 0.1 + 0.84 * on - 0.78 * off
        if on > 0, off < 1 {
            var glove = context
            glove.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(edge))))
            for piece in pieces(u, flex: flex, grow: 0.012) { glove.fill(piece, with: .color(clay)) }
            let cuff = off > 0 ? 0.06 : 0.035
            if edge > 0.2 { context.fill(u.capsule(0.5, edge, 0.28, cuff, corner: cuff / 2), with: .color(clay)) }
        }
        let drop = Ease.clamp((t - 3.3) / 0.5)
        if drop > 0 {
            context.fill(u.circle(0.5 + 0.35 * drop, 0.18 + 1.0 * drop * drop, 0.07), with: .color(clay))
        }
    }
}

/// Biohazard waste: used tips and tubes drop into the clay bag in its bin;
/// the bag is gathered and knotted, lifted out, and a fresh one goes in.
enum Biohazard {
    static let duration = 4.6

    private static func bag(_ context: GraphicsContext, _ u: UnitSquare, tie: Double, lift: Double) {
        var sack = context
        sack.translateBy(x: 0, y: u.len(-lift))
        let left = (0.255 + (0.46 - 0.255) * tie, 0.44 - 0.1 * tie)
        let right = (0.745 + (0.54 - 0.745) * tie, 0.44 - 0.1 * tie)
        var body = u.polyline([(0.31, 0.88), (0.69, 0.88), (0.73 + 0.01 * tie, 0.62), right, left, (0.27 - 0.01 * tie, 0.62)])
        body.closeSubpath()
        sack.fill(body, with: .color(clay))
        if tie < 0.2 {
            for side in [-1.0, 1.0] {
                var flap = u.polyline([(0.5 + 0.245 * side, 0.44), (0.5 + 0.28 * side, 0.5), (0.5 + 0.24 * side, 0.5)])
                flap.closeSubpath()
                sack.fill(flap, with: .color(clay.opacity(1 - tie * 5)))
            }
        }
        if tie > 0 {
            sack.fill(u.circle(0.5, 0.31, 0.03 * tie), with: .color(clay))
            for side in [-1.0, 1.0] {
                var ear = u.polyline([(0.5, 0.31), (0.5 + 0.07 * side, 0.24), (0.5 + 0.03 * side, 0.22)])
                ear.closeSubpath()
                sack.fill(ear, with: .color(clay.opacity(tie)))
            }
        }
        // The biohazard mark, in ivory on the bag.
        for k in 0..<3 {
            let a = (-90 + 120 * Double(k)) * .pi / 180
            u.stroke(sack, u.circle(0.5 + 0.035 * cos(a), 0.68 + 0.035 * sin(a), 0.04), ivory, 0.018)
        }
        sack.fill(u.circle(0.5, 0.68, 0.014), with: .color(ivory))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for (k, at) in [0.3, 0.8, 1.3].enumerated() {
            let fall = Ease.clamp((t - at) / 0.45)
            guard fall > 0, fall < 1 else { continue }
            let x = 0.42 + 0.08 * Double(k), y = -0.1 + 0.8 * fall * fall
            var item = context
            let p = u.pt(x, y)
            item.translateBy(x: p.x, y: p.y)
            item.rotate(by: .degrees(40 * Double(k) - 30 + 120 * fall))
            item.scaleBy(x: 1.5, y: 1.5)
            if k == 1 {
                item.stroke(Path(roundedRect: CGRect(x: -u.len(0.03), y: -u.len(0.07), width: u.len(0.06), height: u.len(0.14)),
                                 cornerRadius: u.len(0.02)), with: .color(tint), lineWidth: u.len(0.025))
            } else {
                var tip = Path()
                tip.move(to: CGPoint(x: -u.len(0.025), y: -u.len(0.07)))
                tip.addLine(to: CGPoint(x: u.len(0.025), y: -u.len(0.07)))
                tip.addLine(to: CGPoint(x: u.len(0.004), y: u.len(0.08)))
                tip.addLine(to: CGPoint(x: -u.len(0.004), y: u.len(0.08)))
                tip.closeSubpath()
                item.fill(tip, with: .color(tint))
            }
        }
        if t < 3.4 {
            bag(context, u, tie: Ease.inOut((t - 1.9) / 0.6), lift: 0.95 * Ease.inOut((t - 2.7) / 0.6))
        } else {
            bag(context, u, tie: 0, lift: 0.9 * (1 - Ease.out((t - 3.6) / 0.5)))
        }
        u.stroke(context, u.line((0.24, 0.42), (0.3, 0.9), (0.7, 0.9), (0.76, 0.42)), tint, 0.05)
    }
}

/// A printer: a page feeds out of the slot, printed line by line with a
/// clay plot on it, and drops away into the tray.
enum Printer {
    static let duration = 4.2
    private static let slot = 0.39

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let feed = Ease.clamp((t - 0.3) / 2.4)
        let steps = feed + 0.012 * sin(feed * 60)
        let away = Ease.inOut((t - 3.1) / 0.6)
        let top = slot - 0.5 + 0.5 * steps + 0.25 * away

        var sheet = context
        sheet.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, slot).y, width: u.side, height: u.side)))
        sheet.opacity = 1 - away
        if feed > 0 {
            u.stroke(sheet, u.capsule(0.5, top + 0.25, 0.46, 0.5, corner: 0.015), tint, 0.03)
            u.stroke(sheet, u.line((0.32, top + 0.06), (0.54, top + 0.06)), tint, 0.035)
            u.stroke(sheet, u.line((0.32, top + 0.12), (0.32, top + 0.3), (0.68, top + 0.3)), tint.opacity(0.5), 0.02)
            let curve = stride(from: 0.0, through: 1.0, by: 0.05).map { s in (0.33 + 0.34 * s, top + 0.29 - 0.15 * (1 - exp(-4 * s))) }
            u.stroke(sheet, u.polyline(curve), clay, 0.03)
            for (k, w) in [0.34, 0.3, 0.2].enumerated() {
                let y = top + 0.37 + 0.045 * Double(k)
                u.stroke(sheet, u.line((0.32, y), (0.32 + w, y)), tint.opacity(0.5), 0.022)
            }
        }
        context.fill(u.capsule(0.5, 0.26, 0.8, 0.26, corner: 0.05), with: .color(tint))
        context.fill(u.capsule(0.5, 0.075, 0.5, 0.06, corner: 0.015), with: .color(tint.opacity(0.4)))
        let busy = feed > 0 && feed < 1
        context.fill(u.circle(0.8, 0.2, 0.022), with: .color(busy && sin(t * 12) > 0 ? clay : clay.opacity(0.35)))
    }
}

/// An autoclave: the round door swings shut on a clay bottle, the wheel
/// turns to lock it, the gauge climbs as steam vents, then it all unwinds
/// and the door opens.
enum Autoclave {
    static let duration = 4.8
    private static let centre = (0.44, 0.56), radius = 0.22

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.54, 0.84, 0.72, corner: 0.06), tint, 0.05)
        let open = 1 - Ease.inOut((t - 0.2) / 0.5) + Ease.inOut((t - 4.1) / 0.5)
        let lock = Ease.inOut((t - 0.75) / 0.35) - Ease.inOut((t - 3.7) / 0.35)
        let pressure = Ease.inOut((t - 1.2) / 0.8) - Ease.inOut((t - 3.0) / 0.8)

        context.fill(u.circle(centre.0, centre.1, radius), with: .color(tint.opacity(0.1)))
        u.stroke(context, u.line((0.28, 0.66), (0.6, 0.66)), tint.opacity(0.5), 0.025)
        context.fill(u.capsule(centre.0, 0.58, 0.1, 0.13, corner: 0.025), with: .color(clay))
        context.fill(u.capsule(centre.0, 0.495, 0.05, 0.05, corner: 0.01), with: .color(clay))

        // The door, hinged on the left, seen foreshortened as it swings.
        let squash = cos(80 * open * .pi / 180)
        let hinge = centre.0 - radius
        context.drawLayer { layer in
            let c = u.pt(hinge + radius * squash, centre.1)
            layer.translateBy(x: c.x, y: c.y)
            layer.scaleBy(x: max(squash, 0.02), y: 1)
            let r = u.len(radius)
            layer.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(tint))
            layer.blendMode = .destinationOut
            let hub = u.len(0.035)
            layer.stroke(Path(ellipseIn: CGRect(x: -hub, y: -hub, width: 2 * hub, height: 2 * hub)), with: .color(.black), lineWidth: u.len(0.025))
            for k in 0..<3 {
                let a = (Double(k) * 120 + 150 * lock) * .pi / 180
                var spoke = Path()
                spoke.move(to: CGPoint(x: hub * cos(a), y: hub * sin(a)))
                spoke.addLine(to: CGPoint(x: u.len(0.12) * cos(a), y: u.len(0.12) * sin(a)))
                layer.stroke(spoke, with: .color(.black), style: StrokeStyle(lineWidth: u.len(0.03), lineCap: .round))
            }
        }

        // The gauge, and steam from the vent while it's up to pressure.
        u.stroke(context, u.circle(0.79, 0.3, 0.07), tint, 0.035)
        let needle = (-210 + 240 * pressure) * .pi / 180
        u.stroke(context, u.line((0.79, 0.3), (0.79 + 0.05 * cos(needle), 0.3 + 0.05 * sin(needle))), clay, 0.03)
        for k in 0..<3 {
            let age = ((t - 1.4 - 0.4 * Double(k)).truncatingRemainder(dividingBy: 1.2)) / 1.2
            guard t > 1.4 + 0.4 * Double(k), t < 3.4, age > 0 else { continue }
            u.stroke(context, u.circle(0.24 + 0.03 * sin(age * 6), 0.15 - 0.12 * age, 0.02 + 0.02 * age),
                     tint.opacity(0.6 * (1 - age)), 0.025)
        }
    }
}

/// A CO₂ incubator: the door swings open on shelves of clay flasks and
/// dishes, warm air shimmers out, the alarm light blinks, and it closes.
enum Incubator {
    static let duration = 4.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.inOut((t - 0.3) / 0.6) - Ease.inOut((t - 3.2) / 0.6)
        context.fill(u.capsule(0.5, 0.5, 0.58, 0.72, corner: 0.02), with: .color(tint.opacity(0.08)))
        for y in [0.42, 0.66] { u.stroke(context, u.line((0.22, y), (0.78, y)), tint.opacity(0.5), 0.025) }
        for x in [0.34, 0.6] {
            context.fill(u.capsule(x, 0.37, 0.18, 0.08, corner: 0.015), with: .color(clay))
            context.fill(u.capsule(x + 0.11, 0.36, 0.05, 0.035, corner: 0.01), with: .color(clay))
        }
        for k in 0..<3 {
            context.fill(u.capsule(0.36, 0.635 - 0.03 * Double(k), 0.18, 0.02, corner: 0.01), with: .color(clay))
            context.fill(u.capsule(0.64, 0.635 - 0.03 * Double(k), 0.18, 0.02, corner: 0.01), with: .color(clay))
        }
        context.fill(u.capsule(0.5, 0.8, 0.22, 0.09, corner: 0.015), with: .color(clay))
        for (k, x) in [0.32, 0.5, 0.68].enumerated() {
            let life = ((t - 1.0 - 0.3 * Double(k)) / 1.2)
            guard open > 0.5, life > 0, life < 1 else { continue }
            let wisp = stride(from: 0.0, through: 0.14, by: 0.014).map { d in (x + 0.015 * sin(d * 45 - t * 6), 0.3 - d - 0.08 * life) }
            u.stroke(context, u.polyline(wisp), tint.opacity(0.45 * sin(.pi * life)), 0.025)
        }

        // The door, hinged on the right, with its handle cut into it.
        let squash = cos(82 * open * .pi / 180)
        context.drawLayer { layer in
            let width = 0.6 * max(squash, 0.02)
            layer.fill(u.capsule(0.8 - width / 2, 0.5, width, 0.78, corner: 0.02 * max(squash, 0.3)), with: .color(tint))
            layer.blendMode = .destinationOut
            let x = 0.8 - width + 0.05 * squash
            u.stroke(layer, u.line((x, 0.44), (x, 0.56)), .black, 0.03 * max(squash, 0.2))
        }
        u.stroke(context, u.capsule(0.5, 0.5, 0.66, 0.84, corner: 0.04), tint, 0.045)
        let alarm = open > 0.5 && sin(t * 10) > 0
        context.fill(u.circle(0.5, 0.045, 0.02), with: .color(clay.opacity(alarm ? 1 : 0.3)))
    }
}

/// Defrosting the minus-eighty: a scraper runs along the frosted top of the
/// freezer, the frost comes away in flakes above the clay boxes, and slowly
/// creeps back.
enum FreezerFrost {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.54, 0.8, 0.76, corner: 0.03), tint, 0.05)
        for y in [0.5, 0.72] { u.stroke(context, u.line((0.14, y), (0.86, y)), tint.opacity(0.5), 0.025) }
        for y in [0.44, 0.66, 0.86] {
            for x in [0.26, 0.42, 0.58, 0.74] where !(y == 0.86 && x == 0.74) {
                context.fill(u.capsule(x, y, 0.12, 0.1, corner: 0.012), with: .color(clay))
            }
        }
        let scraped = 0.14 + 0.72 * Ease.inOut((t - 0.4) / 2.0)
        let regrow = Ease.inOut((t - 3.0) / 1.2)
        var edge: [(Double, Double)] = [(0.14, 0.2)]
        for (k, x) in stride(from: 0.14, through: 0.86, by: 0.03).enumerated() {
            edge.append((x, 0.25 + (k % 2 == 0 ? 0.0 : 0.035) + 0.01 * sin(x * 37)))
        }
        edge.append((0.86, 0.2))
        var frost = u.polyline(edge)
        frost.closeSubpath()
        var left = context
        left.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.len(scraped), height: u.side)))
        left.fill(frost, with: .color(tint.opacity(0.85 * regrow)))
        var right = context
        right.clip(to: Path(CGRect(x: u.pt(scraped, 0).x, y: u.origin.y, width: u.side, height: u.side)))
        right.fill(frost, with: .color(tint.opacity(0.85)))

        let scraping = t > 0.4 && t < 2.4
        for k in 0..<10 {
            let born = 0.45 + 0.2 * Double(k)
            let age = (t - born) / 0.7
            guard age > 0, age < 1 else { continue }
            let x0 = 0.14 + 0.72 * Ease.inOut((born - 0.4) / 2.0)
            context.fill(u.circle(x0 - 0.03 * age, 0.3 + 0.35 * age * age, 0.014), with: .color(tint.opacity(1 - age)))
        }
        if scraping || (t > 0.2 && t < 2.7) {
            let x = scraped
            u.stroke(context, u.line((x, 0.19), (x, 0.31)), tint, 0.04)
            u.stroke(context, u.line((x, 0.3), (x + 0.12, 0.48)), clay, 0.055)
        }
    }
}

/// A biosafety cabinet: the sash rises, the light and the downflow come on,
/// a clay flask is worked on inside, and the sash comes back down.
enum BiosafetyCabinet {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let raised = Ease.inOut((t - 0.2) / 0.6) - Ease.inOut((t - 3.4) / 0.6)
        let on = Ease.clamp((t - 0.8) / 0.1) * (1 - Ease.clamp((t - 3.3) / 0.1))
        context.fill(u.capsule(0.5, 0.18, 0.86, 0.12, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(0.5, 0.255, 0.7, 0.025, corner: 0.012), with: .color(clay.opacity(0.25 + 0.75 * on)))
        if on > 0 {
            for x in [0.2, 0.35, 0.5, 0.65, 0.8] {
                context.stroke(u.line((x, 0.3), (x, 0.74)), with: .color(tint.opacity(0.35 * on)),
                               style: StrokeStyle(lineWidth: u.len(0.02), lineCap: .round,
                                                  dash: [u.len(0.04), u.len(0.06)], dashPhase: -u.len(0.1) * t * 3))
            }
        }
        let flask = Ease.inOut((t - 1.2) / 0.4) - Ease.inOut((t - 2.8) / 0.4)
        let fx = 1.15 - 0.65 * flask
        var body = u.line((fx - 0.035, 0.54), (fx - 0.035, 0.62), (fx - 0.11, 0.765), (fx + 0.11, 0.765), (fx + 0.035, 0.62), (fx + 0.035, 0.54))
        body.closeSubpath()
        context.fill(body, with: .color(clay))
        u.stroke(context, u.line((0.07, 0.77), (0.93, 0.77)), tint, 0.045)
        let top = 0.44 - 0.18 * raised
        context.fill(u.capsule(0.5, top + 0.17, 0.76, 0.34, corner: 0.02), with: .color(tint.opacity(0.14)))
        u.stroke(context, u.capsule(0.5, top + 0.17, 0.76, 0.34, corner: 0.02), tint, 0.03)
        u.stroke(context, u.capsule(0.5, 0.52, 0.86, 0.8, corner: 0.04), tint, 0.05)
    }
}

/// A bottle of media, the square kind with its neck set off to one side at
/// an angle: the cap twists off along the neck, a serological pipette goes
/// in the same way and draws the clay medium up, lifts away, and the cap
/// goes back on.
enum MediaBottle {
    static let duration = 4.6
    /// The neck: where it leaves the shoulder, and which way it points.
    private static let neck = (0.38, 0.33)
    private static let tilt = -20.0 * .pi / 180
    private static let axis = (sin(tilt), -cos(tilt))
    private static let side = (cos(tilt), sin(tilt))

    private static func along(_ from: (Double, Double), _ d: Double, _ s: Double = 0) -> (Double, Double) {
        (from.0 + axis.0 * d + side.0 * s, from.1 + axis.1 * d + side.1 * s)
    }

    private static func bottle(_ u: UnitSquare) -> Path {
        let half = 0.065, length = 0.12
        var p = Path()
        let topLeft = along(neck, length, -half), baseLeft = along(neck, 0, -half)
        let baseRight = along(neck, 0, half), topRight = along(neck, length, half)
        p.move(to: u.pt(topLeft.0, topLeft.1))
        p.addLine(to: u.pt(baseLeft.0, baseLeft.1))
        p.addQuadCurve(to: u.pt(0.28, 0.44), control: u.pt(0.28, 0.37))
        p.addLine(to: u.pt(0.28, 0.86))
        p.addQuadCurve(to: u.pt(0.32, 0.9), control: u.pt(0.28, 0.9))
        p.addLine(to: u.pt(0.68, 0.9))
        p.addQuadCurve(to: u.pt(0.72, 0.86), control: u.pt(0.72, 0.9))
        p.addLine(to: u.pt(0.72, 0.47))
        p.addQuadCurve(to: u.pt(baseRight.0, baseRight.1), control: u.pt(0.72, 0.36))
        p.addLine(to: u.pt(topRight.0, topRight.1))
        return p
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let drawn = Ease.inOut((t - 1.5) / 0.9) * (1 - Ease.inOut((t - 3.9) / 0.5))
        let glass = bottle(u)
        BenchShapes.fill(context, u, glass, from: 0.5 + 0.1 * drawn, clay)
        context.fill(u.capsule(0.5, 0.72, 0.4, 0.14, corner: 0.01), with: .color(tint))
        for (k, w) in [0.2, 0.14].enumerated() {
            u.stroke(context, u.line((0.35, 0.7 + 0.04 * Double(k)), (0.35 + w, 0.7 + 0.04 * Double(k))), clay, 0.022)
        }
        u.stroke(context, glass, tint, 0.045)

        // The serological pipette, in and out along the neck's line.
        let depth = Keyframes.value(t, [(0.9, -0.9), (1.4, 0.42), (2.5, 0.42), (3.0, -0.95)])
        if depth > -0.9 {
            let tip = along(neck, -depth)
            let far = along(tip, 0.9)
            let column = 0.3 * drawn
            if drawn > 0 {
                u.stroke(context, u.line(along(tip, 0.02), along(tip, 0.02 + column)), clay, 0.03)
            }
            u.stroke(context, u.line(tip, far), tint, 0.035)
            for k in 1...6 {
                let mark = along(tip, 0.07 * Double(k))
                u.stroke(context, u.line(along(mark, 0, 0.015), along(mark, 0, 0.035)), tint, 0.015)
            }
        }
        // The cap: twists up off the neck, sets aside, comes back.
        let lifted = Keyframes.value(t, [(0.2, 0), (0.6, 1), (3.4, 1), (3.8, 0)])
        let aside = Keyframes.value(t, [(0.6, 0), (0.9, 1), (3.1, 1), (3.4, 0)])
        let twist = 4 * .pi * lifted
        let seat = along(neck, 0.15 + 0.1 * lifted)
        let centre = (seat.0 + 0.36 * aside, seat.1 + 0.1 * aside)
        let turn = tilt * (1 - aside)
        context.drawLayer { layer in
            let c = u.pt(centre.0, centre.1)
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: .radians(turn))
            layer.translateBy(x: -c.x, y: -c.y)
            layer.fill(u.capsule(centre.0, centre.1, 0.17, 0.08, corner: 0.02), with: .color(tint))
            layer.blendMode = .destinationOut
            for k in 0..<4 {
                let a = twist + Double(k) * .pi / 2
                guard cos(a) > 0 else { continue }
                u.stroke(layer, u.line((centre.0 + 0.065 * sin(a), centre.1 - 0.02), (centre.0 + 0.065 * sin(a), centre.1 + 0.02)), .black, 0.015)
            }
        }
    }
}

/// Into the water bath: a float of three clay tubes is set on the water,
/// bobs and settles among ripples, warms there, and lifts out.
enum WaterBath {
    static let duration = 4.2
    private static let surface = 0.56

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let land = 0.6
        var y = 0.55 - 0.5 * (1 - Ease.inOut((t - 0.2) / 0.4)) - 0.55 * Ease.inOut((t - 3.3) / 0.5)
        if t > land { y += 0.025 * exp(-(t - land) * 3) * sin((t - land) * 12) }
        for x in [0.38, 0.5, 0.62] {
            let outline = BenchShapes.tube(u, x: x, rim: y - 0.1, shoulder: y + 0.06, tip: y + 0.13, half: 0.04)
            BenchShapes.fill(context, u, outline, from: y - 0.03, clay)
            u.stroke(context, outline, tint, 0.03)
        }
        context.fill(u.capsule(0.5, y, 0.5, 0.06, corner: 0.02), with: .color(tint))

        let wave = stride(from: 0.06, through: 0.94, by: 0.02).map { x in (x, surface + 0.008 * sin(x * 25 + t * 3)) }
        var water = u.polyline(wave + [(0.94, 0.9), (0.06, 0.9)])
        water.closeSubpath()
        context.fill(water, with: .color(tint.opacity(0.12)))
        u.stroke(context, u.polyline(wave), tint.opacity(0.5), 0.025)
        for k in 0..<2 {
            let age = (t - land - 0.25 * Double(k)) / 0.9
            guard age > 0, age < 1 else { continue }
            u.stroke(context, u.ellipse(0.5, surface, 0.56 + 0.34 * age, 0.05 + 0.05 * age), tint.opacity(0.6 * (1 - age)), 0.02)
        }
        for k in 0..<4 {
            let age = (t - land) / 0.5
            guard age > 0, age < 1 else { continue }
            let side = k % 2 == 0 ? -1.0 : 1.0
            let spread = 0.28 + 0.06 * Double(k / 2)
            context.fill(u.circle(0.5 + side * spread * (0.9 + 0.2 * age), surface - 0.12 * sin(.pi * age), 0.013),
                         with: .color(tint.opacity(1 - age)))
        }
        for x in [0.14, 0.86] {
            let shimmer = stride(from: 0.0, through: 0.14, by: 0.014).map { d in (x + 0.012 * sin(d * 50 - t * 5), surface - 0.05 - d) }
            u.stroke(context, u.polyline(shimmer), tint.opacity(0.3), 0.022)
        }
        u.stroke(context, u.line((0.06, 0.36), (0.06, 0.9), (0.94, 0.9), (0.94, 0.36)), tint, 0.05)
    }
}
