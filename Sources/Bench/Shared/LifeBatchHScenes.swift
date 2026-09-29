// LifeBatchHScenes.swift
// ScienceStatus — motors, coats, rings and signals: myosin V walking,
// a clathrin cage, actin treadmilling, the FtsZ ring, a calcium wave, an
// mRNA vaccine, a CAR-T cell, a heartbeat and insulin at work. Each draws
// in a unit square (see `UnitSquare`): structure in the tint, the moving
// part, the signal or the payload in clay.

import SwiftUI

/// Myosin V walking hand over hand along actin: the rear head lets go,
/// swings over on its long lever arm and lands a step ahead, cargo in tow.
enum MyosinV {
    static let duration = 4.8
    private static let step = 0.18, first = 0.24, rail = 0.7

    /// Where the two heads are: `back` and `front` on the rail, and the one
    /// swinging (0...1) between steps.
    private static func heads(_ t: Double) -> (Double, Double, swing: Double, swinger: Double) {
        let n = min(3, max(0, Int((t - 0.5) / 1.3)))
        let local = t - 0.5 - Double(n) * 1.3
        let swing = t < 0.5 ? 0 : Ease.inOut(local / 0.55)
        let back = first + step * Double(n), front = back + step
        return (back, front, n < 3 ? swing : 0, back)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        // Drawn upside down: walking the underside of the filament, the cargo
        // hanging below like a cable car.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let u = UnitSquare(size)
        for k in 0..<24 {
            let x = 0.02 + 0.04 * Double(k)
            context.fill(u.circle(x, rail + (k % 2 == 0 ? -0.012 : 0.012), 0.022), with: .color(tint.opacity(0.55)))
        }
        let (back, front, swing, _) = heads(t)
        // The swinging head arcs over the front one to land a step ahead.
        let from = back, to = front + step
        let sx = from + (to - from) * swing
        let sy = rail - 0.03 - 0.3 * sin(.pi * swing)
        let planted = (front, rail - 0.03)
        let moving = (sx, sy)
        let hipX = (planted.0 + moving.0) / 2
        let hip = (hipX, rail - 0.28 + 0.06 * sin(.pi * swing))
        for head in [planted, moving] {
            u.stroke(context, u.line(head, hip), tint, 0.03)
            context.fill(u.ellipse(head.0, head.1, 0.075, 0.05), with: .color(clay))
        }
        // The cargo, a vesicle hanging from the tail.
        let cargo = (hip.0 - 0.05, 0.2)
        u.stroke(context, u.polyline(Smooth.curve([hip, (hip.0 - 0.02, 0.36), (cargo.0, cargo.1 + 0.1)], samples: 5)), tint, 0.02)
        context.fill(u.circle(cargo.0, cargo.1, 0.1), with: .color(clay.opacity(0.35)))
        u.stroke(context, u.circle(cargo.0, cargo.1, 0.1), tint, 0.03)
    }
}

/// A clathrin cage: three-legged triskelions gather under a pit in the
/// membrane, knit into a cage, and the coated vesicle pinches off at a clay
/// collar and drops away.
enum ClathrinCage {
    static let duration = 5.0

    private static func triskelion(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), size: Double, turn: Double, tint: Color) {
        for k in 0..<3 {
            let a = turn + Double(k) * 2 * .pi / 3
            let knee = (p.0 + cos(a) * size * 0.6, p.1 + sin(a) * size * 0.6)
            let foot = (knee.0 + cos(a + 0.6) * size * 0.5, knee.1 + sin(a + 0.6) * size * 0.5)
            u.stroke(context, u.line(p, knee, foot), tint, 0.022)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let deepen = Ease.inOut((t - 0.3) / 2.2)
        let pinch = Ease.inOut((t - 2.8) / 0.6)
        let drop = Ease.inOut((t - 3.5) / 1.1)
        let r = 0.13
        let centre = (0.5, 0.3 + 0.13 * deepen + 0.2 * drop)
        // The membrane: flat, then dimpled round the bud, then healed.
        let mouth = 0.14 * (1 - pinch)
        var membrane = u.line((0.02, 0.3), (0.5 - mouth - 0.06, 0.3))
        membrane.addPath(u.line((0.5 + mouth + 0.06, 0.3), (0.98, 0.3)))
        if pinch >= 1 { membrane = u.line((0.02, 0.3), (0.98, 0.3)) }
        u.stroke(context, membrane, tint, 0.03)
        if pinch < 1, deepen > 0 {
            u.stroke(context, u.line((0.5 - mouth - 0.06, 0.3), (0.5 - mouth * 0.7, 0.3 + 0.08 * deepen)), tint, 0.03)
            u.stroke(context, u.line((0.5 + mouth + 0.06, 0.3), (0.5 + mouth * 0.7, 0.3 + 0.08 * deepen)), tint, 0.03)
        }
        // The vesicle, its cargo, and the cage knitting round it.
        u.stroke(context, u.circle(centre.0, centre.1, r * 0.7 * max(0.3, deepen)), tint, 0.025)
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + 0.4
            context.fill(u.circle(centre.0 + cos(a) * 0.04 * deepen, centre.1 + sin(a) * 0.04 * deepen, 0.012), with: .color(clay))
        }
        let knit = Ease.clamp((t - 1.2) / 1.4)
        if knit > 0 {
            let cage = tint.opacity(knit)
            u.stroke(context, u.circle(centre.0, centre.1, r), cage, 0.025)
            let pentagon = (0..<5).map { k -> (Double, Double) in
                let a = -Double.pi / 2 + Double(k) * 2 * .pi / 5
                return (centre.0 + cos(a) * r * 0.42, centre.1 + sin(a) * r * 0.42)
            }
            var ring = u.polyline(pentagon)
            ring.closeSubpath()
            u.stroke(context, ring, cage, 0.022)
            for p in pentagon {
                let a = atan2(p.1 - centre.1, p.0 - centre.0)
                u.stroke(context, u.line(p, (centre.0 + cos(a) * r, centre.1 + sin(a) * r)), cage, 0.022)
            }
        }
        // Triskelions drifting in from below to join.
        for k in 0..<3 where knit < 1 {
            let arrive = Ease.out((t - 0.2 - 0.3 * Double(k)) / 1.2)
            let start = (0.2 + 0.3 * Double(k), 0.9)
            let p = (start.0 + (centre.0 - start.0) * arrive, start.1 + (centre.1 + 0.05 - start.1) * arrive)
            triskelion(context, u, at: p, size: 0.08 * (1 - 0.5 * arrive), turn: t * 0.8 + Double(k), tint: tint.opacity(1 - knit))
        }
        // The clay collar that pinches the neck.
        if t > 2.5, pinch < 1 {
            context.fill(u.capsule(0.5, 0.33 + 0.06 * deepen, 0.1 * (1 - pinch) + 0.03, 0.03, corner: 0.012), with: .color(clay))
        }
    }
}

/// Actin treadmilling at a cell's leading edge: filaments grow and branch
/// against the membrane, their clay tips adding subunits, while the network
/// flows back and falls apart behind, and the edge creeps forward.
enum ActinTreadmill {
    static let duration = 4.8
    private static let count = 26

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let edge = 0.8 + 0.06 * t / duration
        var membrane = Path()
        membrane.addArc(center: u.pt(edge - 0.7, 0.5), radius: u.len(0.72), startAngle: .degrees(-44), endAngle: .degrees(44), clockwise: false)
        u.stroke(context, membrane, tint, 0.035)
        for k in 0..<count {
            let s = Double(k)
            // Each filament is born at the edge and flows back from there.
            let born = -3.0 + 0.3 * s
            let age = t - born
            guard age > 0 else { continue }
            let y = 0.14 + 0.72 * BenchShapes.rand(s * 1.7)
            let tipX = edge - 0.02 - 0.03 * BenchShapes.rand(s * 2.9) - 0.1 * age
            let angle = (BenchShapes.rand(s * 4.1) - 0.5) * 1.2
            let length = min(0.2, 0.25 * age)
            let fade = 1 - Ease.clamp((0.4 - tipX) / 0.2)
            guard fade > 0 else { continue }
            let tail = (tipX - cos(angle) * length, y - sin(angle) * length)
            u.stroke(context, u.line(tail, (tipX, y)), tint.opacity(0.8 * fade), 0.02)
            // A daughter branch off at seventy degrees.
            if k % 3 == 0, length > 0.1 {
                let base = (tipX - cos(angle) * length * 0.5, y - sin(angle) * length * 0.5)
                let branch = angle + 1.22
                u.stroke(context, u.line(base, (base.0 + cos(branch) * 0.07, base.1 + sin(branch) * 0.07)), tint.opacity(0.7 * fade), 0.018)
            }
            if tipX > edge - 0.12 {
                context.fill(u.circle(tipX, y, 0.013), with: .color(clay))
            }
        }
    }
}

/// The FtsZ ring: a clay ring treadmills round a bacterium's middle and
/// tightens, the cell pinching in two, one nucleoid to each half.
enum FtsZRing {
    static let duration = 5.0
    private static let radius = 0.18

    /// The two halves overlap less as the ring closes; their union is the cell.
    private static func halfLength(_ p: Double) -> Double { 0.41 + 0.23 * (1 - p) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let p = Ease.inOut((t - 1.0) / 2.6)
        let apart = 0.025 * Ease.out((t - 3.7) / 0.6)
        let length = halfLength(p)
        let left = u.capsule(0.09 + length / 2 - apart, 0.5, length, 2 * radius, corner: radius)
        let right = u.capsule(0.91 - length / 2 + apart, 0.5, length, 2 * radius, corner: radius)
        let cell = left.union(right)
        context.fill(cell, with: .color(tint.opacity(0.1)))
        u.stroke(context, cell, tint, 0.035)
        // Nucleoids moving apart.
        let split = Ease.inOut((t - 0.2) / 0.9)
        for side in [-1.0, 1.0] {
            let x = 0.5 + side * (0.02 + 0.2 * split)
            let blob = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.3).map { a in
                (x + 0.07 * cos(a) * (1 + 0.15 * sin(3 * a)), 0.5 + 0.06 * sin(a) * (1 + 0.15 * cos(2 * a)))
            }
            u.stroke(context, u.polyline(blob), tint.opacity(0.6), 0.018)
        }
        // The ring at the waist, its clay filaments running round.
        let overlap = 2 * length - 0.82
        let waist = overlap >= 2 * radius ? radius : sqrt(max(0, radius * radius - pow(radius - overlap / 2, 2)))
        guard waist > 0.004, t < 3.8 else { return }
        u.stroke(context, u.ellipse(0.5, 0.5, 0.05, 2 * waist), clay.opacity(0.35), 0.02)
        for k in 0..<5 {
            let a = t * 3 + Double(k) * 2 * .pi / 5
            let y0 = 0.5 + waist * sin(a), y1 = 0.5 + waist * sin(a + 0.5)
            let x0 = 0.5 + 0.025 * cos(a), x1 = 0.5 + 0.025 * cos(a + 0.5)
            u.stroke(context, u.line((x0, y0), (x1, y1)), clay, 0.03)
        }
    }
}

/// A calcium wave: one cell flashes clay and the flash passes cell to cell
/// through the gap junctions, out across the sheet.
enum CalciumWave {
    static let duration = 4.8
    private static let origin = (0.22, 0.5), speed = 0.28

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let r = 0.075
        for row in 0..<7 {
            for col in 0..<7 {
                let x = 0.1 + 0.13 * Double(col) + (row % 2 == 0 ? 0 : 0.065)
                let y = 0.12 + 0.113 * Double(row)
                guard x < 0.95 else { continue }
                var hex = u.polyline((0..<6).map { k in Rings.offset((x, y), r, 30 + 60 * Double(k)) })
                hex.closeSubpath()
                let arrival = 0.4 + hypot(x - origin.0, y - origin.1) / speed
                let since = t - arrival
                let flash = since > 0 ? Ease.clamp(since / 0.12) * exp(-max(0, since - 0.12) / 0.6) : 0
                if flash > 0.02 { context.fill(hex, with: .color(clay.opacity(flash))) }
                u.stroke(context, hex, tint.opacity(0.6), 0.018)
            }
        }
    }
}

/// An mRNA vaccine: a lipid nanoparticle crosses into the cell and lets its
/// clay message go; ribosomes read it, and clay spikes rise on the surface.
enum MRNAVaccine {
    static let duration = 5.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let top = 0.46
        u.stroke(context, u.line((0.02, top), (0.98, top)), tint, 0.03)
        // The particle arrives, fuses, and its shell falls away.
        let arrive = Ease.inOut((t - 0.2) / 1.0)
        let enter = Ease.inOut((t - 1.2) / 0.8)
        let shell = 1 - Ease.clamp((t - 1.8) / 0.4)
        let p = (0.5, 0.12 + (top - 0.12) * arrive + 0.2 * enter)
        if shell > 0 {
            for k in 0..<14 {
                let a = Double(k) * 2 * .pi / 14
                context.fill(u.circle(p.0 + cos(a) * 0.075, p.1 + sin(a) * 0.075, 0.013), with: .color(tint.opacity(shell)))
            }
        }
        // The message: a clay squiggle, unrolling once free.
        let unroll = Ease.inOut((t - 1.9) / 0.7)
        let span = 0.05 + 0.3 * unroll
        let mrna = stride(from: -1.0, through: 1.0, by: 0.05).map { s in
            (p.0 + span * s, p.1 + 0.015 * sin(s * 12 + t * 2))
        }
        u.stroke(context, u.polyline(mrna), clay, 0.022)
        // Ribosomes reading along it.
        if t > 2.5 {
            for k in 0..<2 {
                let s = Ease.clamp((t - 2.6 - 0.5 * Double(k)) / 1.6)
                guard s > 0, s < 1 else { continue }
                let x = p.0 - span + 2 * span * s
                context.fill(u.ellipse(x, p.1 - 0.02, 0.06, 0.045), with: .color(tint))
                context.fill(u.ellipse(x, p.1 + 0.025, 0.07, 0.04), with: .color(tint))
            }
        }
        // Spike proteins rising on the surface, one after another.
        for k in 0..<6 {
            let rise = Ease.outBack((t - 3.2 - 0.18 * Double(k)) / 0.4)
            guard rise > 0 else { continue }
            let x = 0.12 + 0.15 * Double(k)
            let head = top - 0.08 * rise
            u.stroke(context, u.line((x, top), (x, head)), tint, 0.022)
            context.fill(u.circle(x, head - 0.02, 0.025 * rise), with: .color(clay))
        }
    }
}

/// A CAR-T cell: the engineered T cell rolls up to a tumour cell, its clay
/// receptors lock on, it delivers its granules, and the tumour cell shrinks
/// and breaks apart.
enum CARTCell {
    static let duration = 5.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let approach = Ease.inOut((t - 0.2) / 1.0)
        let tCell = (0.14 + 0.16 * approach, 0.5)
        let bind = Ease.clamp((t - 1.2) / 0.4)
        // The tumour: lumpy, then shrinking into fragments.
        let die = Ease.inOut((t - 2.8) / 1.3)
        let tumour = (0.72, 0.5)
        if die < 0.95 {
            let outline = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.12).map { a -> (Double, Double) in
                let r = (0.17 + 0.012 * sin(7 * a)) * (1 - 0.45 * die)
                return (tumour.0 + r * cos(a), tumour.1 + r * sin(a))
            }
            u.stroke(context, u.polyline(outline), tint.opacity(1 - die), 0.035)
            for k in 0..<5 {
                let a = Double(k) * 1.3 + 2.4
                let r = 0.17 * (1 - 0.45 * die)
                context.fill(u.capsule(tumour.0 + r * cos(a), tumour.1 + r * sin(a), 0.03, 0.03, corner: 0.006), with: .color(tint.opacity(1 - die)))
            }
        }
        for k in 0..<6 where die > 0.3 {
            let a = Double(k) * 1.05
            let d = 0.1 + 0.12 * die
            context.fill(u.circle(tumour.0 + d * cos(a), tumour.1 + d * sin(a), 0.028 * (1 - 0.5 * die)), with: .color(tint.opacity(0.7 * (1 - Ease.clamp((t - 4.4) / 0.5)))))
        }
        // The T cell and its receptors facing the tumour.
        u.stroke(context, u.circle(tCell.0, tCell.1, 0.15), tint, 0.035)
        context.fill(u.circle(tCell.0 - 0.02, tCell.1, 0.06), with: .color(tint.opacity(0.35)))
        for k in -2...2 {
            let a = Double(k) * 0.28
            let base = (tCell.0 + 0.15 * cos(a), tCell.1 + 0.15 * sin(a))
            let tip = (tCell.0 + (0.21 + 0.03 * bind) * cos(a), tCell.1 + (0.21 + 0.03 * bind) * sin(a))
            u.stroke(context, u.line(base, tip), tint, 0.022)
            context.fill(u.circle(tip.0, tip.1, 0.018), with: .color(clay))
        }
        // Granules crossing the synapse.
        for k in 0..<4 {
            let s = Ease.inOut((t - 1.7 - 0.2 * Double(k)) / 0.8)
            guard s > 0, s < 1 else { continue }
            let y = tCell.1 + 0.06 * (Double(k) - 1.5) * (1 - s)
            context.fill(u.circle(tCell.0 + 0.08 + (tumour.0 - 0.1 - tCell.0 - 0.08) * s, y, 0.02), with: .color(clay))
        }
    }
}

/// A heartbeat: the heart squeezes in time with its clay ECG, P wave, QRS
/// and T, at seventy-five beats a minute.
enum Heartbeat {
    static let duration = 4.8
    private static let beat = 0.8

    /// The ECG at `s` seconds: P, QRS and T in each beat.
    private static func ecg(_ s: Double) -> Double {
        let x = s.truncatingRemainder(dividingBy: beat) / beat
        func bump(_ c: Double, _ w: Double, _ h: Double) -> Double { h * exp(-pow((x - c) / w, 2)) }
        return bump(0.12, 0.035, 0.025) - bump(0.27, 0.01, 0.02) + bump(0.3, 0.012, 0.16) - bump(0.33, 0.012, 0.04) + bump(0.58, 0.06, 0.045)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = t.truncatingRemainder(dividingBy: beat) / beat
        let squeeze = 1 - 0.1 * exp(-pow((x - 0.34) / 0.07, 2))
        // The heart: two lobes and a point.
        var heart = context
        let c = u.pt(0.5, 0.32)
        heart.translateBy(x: c.x, y: c.y)
        heart.scaleBy(x: squeeze, y: squeeze)
        heart.translateBy(x: -c.x, y: -c.y)
        var shape = Path()
        shape.move(to: u.pt(0.5, 0.52))
        shape.addCurve(to: u.pt(0.3, 0.24), control1: u.pt(0.38, 0.44), control2: u.pt(0.28, 0.34))
        shape.addCurve(to: u.pt(0.5, 0.2), control1: u.pt(0.33, 0.12), control2: u.pt(0.46, 0.13))
        shape.addCurve(to: u.pt(0.7, 0.24), control1: u.pt(0.54, 0.13), control2: u.pt(0.67, 0.12))
        shape.addCurve(to: u.pt(0.5, 0.52), control1: u.pt(0.72, 0.34), control2: u.pt(0.62, 0.44))
        heart.fill(shape, with: .color(clay))
        // The trace, scrolling to the pen.
        let window = 2.4
        let trace = stride(from: max(0, t - window), through: t, by: 0.004).map { s in (0.9 - 0.82 * (t - s) / window, 0.76 - ecg(s)) }
        u.stroke(context, u.line((0.06, 0.76), (0.94, 0.76)), tint.opacity(0.15), 0.01)
        if trace.count > 1 { u.stroke(context, u.polyline(trace), tint, 0.02) }
        context.fill(u.circle(0.9, 0.76 - ecg(t), 0.016), with: .color(clay))
    }
}

/// Insulin at work: insulin docks on its receptor, the receptor lights, clay
/// transporter vesicles rise and fuse into the membrane, and glucose pours
/// in through them.
enum InsulinSignal {
    static let duration = 5.0
    private static let membrane = 0.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.02, membrane), (0.98, membrane)), tint, 0.03)
        u.stroke(context, u.line((0.02, membrane + 0.05), (0.98, membrane + 0.05)), tint, 0.03)
        // The receptor, its halves spanning the membrane.
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((0.2 + 0.03 * side, membrane - 0.1), (0.2 + 0.02 * side, membrane + 0.14)), tint, 0.035)
        }
        let dock = Ease.inOut((t - 0.3) / 0.8)
        context.fill(u.circle(0.2, 0.08 + (membrane - 0.13 - 0.08) * dock, 0.03), with: .color(clay))
        let lit = Ease.clamp((t - 1.1) / 0.2) * (1 - Ease.clamp((t - 4.5) / 0.4))
        if lit > 0 { context.fill(u.circle(0.2, membrane + 0.16, 0.025), with: .color(clay.opacity(lit))) }
        // Transporter vesicles rising to fuse; once in, they are channels.
        let slots = [0.44, 0.62, 0.8]
        for (k, x) in slots.enumerated() {
            let rise = Ease.inOut((t - 1.5 - 0.3 * Double(k)) / 0.9)
            if rise < 1 {
                let y = 0.84 - (0.84 - membrane - 0.08) * rise
                u.stroke(context, u.circle(x, y, 0.055), tint, 0.022)
                context.fill(u.capsule(x, y, 0.025, 0.05, corner: 0.01), with: .color(clay))
            } else {
                context.fill(u.capsule(x, membrane + 0.025, 0.04, 0.09, corner: 0.012), with: .color(clay))
            }
            // Glucose through each open channel.
            for g in 0..<3 where rise >= 1 {
                let s = ((t - 2.8 - 0.3 * Double(k)) * 0.8 + Double(g) / 3).truncatingRemainder(dividingBy: 1)
                guard t > 2.8 + 0.3 * Double(k) else { continue }
                let y = 0.08 + 0.8 * s
                var hex = u.polyline((0..<6).map { j in Rings.offset((x + 0.03 * sin(s * 6), y), 0.018, 60 * Double(j)) })
                hex.closeSubpath()
                u.stroke(context, hex, tint, 0.014)
            }
        }
    }
}
