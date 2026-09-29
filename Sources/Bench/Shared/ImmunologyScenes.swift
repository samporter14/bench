// ImmunologyScenes.swift
// ScienceStatus — immunology, gene regulation, delivery, and two charts.
// Each draws in a unit square (see `UnitSquare`): cells, membranes and
// machinery in the tint, the antigen, the signal or the payload in clay.

import SwiftUI

/// Excitation and emission: the laser line lights, the excitation spectrum
/// rises round it, the clay emission answers to its right, and the
/// band-pass filter slides over the emission peak.
enum Spectra {
    static let duration = 4.4
    private static let base = 0.84, height = 0.56

    private static func excitation(_ s: Double) -> Double {
        exp(-pow((s - 0.36) / (s < 0.36 ? 0.14 : 0.07), 2))
    }

    private static func emission(_ s: Double) -> Double {
        exp(-pow((s - 0.52) / (s < 0.52 ? 0.07 : 0.16), 2))
    }

    private static func curve(_ f: (Double) -> Double, to end: Double) -> [(Double, Double)] {
        stride(from: 0.0, through: end, by: 0.01).map { s in (0.08 + 0.84 * s, base - height * f(s)) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 3.8) / 0.5)
        u.stroke(context, u.line((0.06, base), (0.94, base)), tint.opacity(0.4), 0.025)
        let filter = Ease.inOut((t - 2.3) / 0.5) * (1 - fade)
        if filter > 0 {
            let x = 0.08 + 0.84 * 0.5 + 0.5 * (1 - filter)
            context.fill(u.capsule(x + 0.05, (base + 0.2) / 2, 0.1, base - 0.2, corner: 0.01), with: .color(tint.opacity(0.12 * filter)))
        }
        let laser = sin(.pi * Ease.clamp((t - 0.2) / 0.6))
        if laser > 0 { u.stroke(context, u.line((0.08 + 0.84 * 0.36, base), (0.08 + 0.84 * 0.36, 0.16)), tint.opacity(laser), 0.02) }
        let ex = Ease.inOut((t - 0.4) / 0.8)
        if ex > 0 { u.stroke(context, u.polyline(curve(excitation, to: ex)), tint.opacity(1 - fade), 0.03) }
        let em = Ease.inOut((t - 1.3) / 0.8)
        if em > 0 {
            let points = curve(emission, to: em)
            var area = u.polyline(points + [(points[points.count - 1].0, base), (0.08, base)])
            area.closeSubpath()
            context.fill(area, with: .color(clay.opacity(0.25 * (1 - fade))))
            u.stroke(context, u.polyline(points), clay.opacity(1 - fade), 0.035)
        }
    }
}

/// A tree of life, drawn round a circle: from the root at the middle the
/// branches grow outward, split, and reach the leaves on the rim; then one
/// clade turns clay.
enum TreeOfLife {
    static let duration = 4.4
    private indirect enum Node { case leaf, branch([Node]) }
    private static let tree: Node = .branch([
        .branch([.branch([.leaf, .leaf]), .branch([.leaf, .branch([.leaf, .leaf])])]),
        .branch([.branch([.leaf, .leaf]), .branch([.leaf, .leaf])]),
        .branch([.leaf, .branch([.leaf, .leaf, .leaf])]),
    ])
    private static let leaves = 13, rim = 0.42
    private struct Segment { let arc: Bool; let r0: Double; let r1: Double; let a0: Double; let a1: Double; let clade: Bool }

    private static func radius(_ depth: Int) -> Double { 0.06 + 0.09 * Double(depth) }

    /// Lays the tree out: returns its angle, appends its segments.
    private static func layout(_ node: Node, depth: Int, next: inout Int, clade: Bool, into segments: inout [Segment]) -> Double {
        switch node {
        case .leaf:
            let a = Double(next) * 2 * .pi / Double(leaves)
            next += 1
            return a
        case .branch(let children):
            var angles: [Double] = []
            for (k, child) in children.enumerated() {
                let inClade = clade || (depth == 0 && k == 1)
                let a = layout(child, depth: depth + 1, next: &next, clade: inClade, into: &segments)
                angles.append(a)
                let end: Double
                if case .leaf = child { end = rim } else { end = radius(depth + 1) }
                segments.append(Segment(arc: false, r0: radius(depth), r1: end, a0: a, a1: a, clade: inClade))
            }
            let lo = angles.min() ?? 0, hi = angles.max() ?? 0
            segments.append(Segment(arc: true, r0: radius(depth), r1: radius(depth), a0: lo, a1: hi, clade: clade))
            return (lo + hi) / 2
        }
    }

    private static let segments: [Segment] = {
        var all: [Segment] = [], next = 0
        _ = layout(tree, depth: 0, next: &next, clade: false, into: &all)
        return all
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let grow = 0.06 + (rim - 0.06) * Ease.inOut((t - 0.2) / 2.0)
        let clade = Ease.inOut((t - 2.6) / 0.4)
        let fade = Ease.inOut((t - 3.8) / 0.5)
        let centre = u.pt(0.5, 0.5)
        context.fill(u.circle(0.5, 0.5, 0.02), with: .color(tint.opacity(1 - fade)))
        for s in segments {
            guard grow > s.r0 else { continue }
            var path = Path()
            if s.arc {
                let spread = Ease.clamp((grow - s.r0) / 0.04)
                let mid = (s.a0 + s.a1) / 2, half = (s.a1 - s.a0) / 2 * spread
                path.addArc(center: centre, radius: u.len(s.r0), startAngle: .radians(mid - half), endAngle: .radians(mid + half), clockwise: false)
            } else {
                let r = min(s.r1, grow)
                path.move(to: CGPoint(x: centre.x + u.len(s.r0) * cos(s.a0), y: centre.y + u.len(s.r0) * sin(s.a0)))
                path.addLine(to: CGPoint(x: centre.x + u.len(r) * cos(s.a0), y: centre.y + u.len(r) * sin(s.a0)))
            }
            u.stroke(context, path, tint.opacity(1 - fade), 0.03)
            if s.clade && clade > 0 { u.stroke(context, path, clay.opacity(clade * (1 - fade)), 0.035) }
            if !s.arc && s.r1 == rim && grow >= rim - 0.001 {
                let p = (0.5 + rim * cos(s.a0), 0.5 + rim * sin(s.a0))
                context.fill(u.circle(p.0, p.1, 0.02), with: .color((s.clade && clade > 0.5 ? clay : tint).opacity(1 - fade)))
            }
        }
    }
}

/// A T cell reading its targets: its receptor tries a self peptide, passes
/// on, finds the clay one, docks, and a clay signal runs up into the cell.
enum TCellReceptor {
    static let duration = 4.4
    private static let mhc: [(x: Double, foreign: Bool)] = [(0.2, false), (0.5, true), (0.8, false)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = Keyframes.value(t, [(0.9, 0.2), (1.4, 0.5), (3.7, 0.5), (4.2, 0.8)])
        let membrane = Keyframes.value(t, [(0.3, 0.22), (0.55, 0.42), (0.8, 0.28), (1.4, 0.28), (1.8, 0.52), (3.4, 0.52), (3.8, 0.22)])
        // The antigen-presenting cell below, its MHCs holding peptides.
        context.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, 0.82).y, width: u.side, height: u.len(0.2))), with: .color(tint.opacity(0.08)))
        u.stroke(context, u.line((0.0, 0.82), (1.0, 0.82)), tint, 0.045)
        for m in mhc {
            for side in [-1.0, 1.0] { context.fill(u.capsule(m.x + 0.035 * side, 0.76, 0.035, 0.12, corner: 0.017), with: .color(tint)) }
            context.fill(u.capsule(m.x, 0.695, 0.06, 0.022, corner: 0.011), with: .color(m.foreign ? clay : tint.opacity(0.5)))
        }
        // The T cell above, its receptor's two chains hanging from it.
        context.fill(Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(membrane))), with: .color(tint.opacity(0.08)))
        u.stroke(context, u.line((0.0, membrane), (1.0, membrane)), tint, 0.045)
        for side in [-1.0, 1.0] {
            context.fill(u.capsule(x + 0.025 * side, membrane + 0.08, 0.035, 0.16, corner: 0.017), with: .color(tint))
            u.stroke(context, u.line((x + 0.03 * side, membrane), (x + 0.04 * side, membrane - 0.12)), tint, 0.025)
        }
        let signal = Ease.clamp((t - 2.0) / 0.3) * (1 - Ease.clamp((t - 3.4) / 0.3))
        if signal > 0 {
            for side in [-1.0, 1.0] {
                for k in 0..<2 { context.fill(u.circle(x + 0.037 * side, membrane - 0.05 - 0.05 * Double(k), 0.016), with: .color(clay.opacity(signal))) }
            }
            for k in 0..<3 {
                let age = ((t - 2.3 - 0.3 * Double(k)).truncatingRemainder(dividingBy: 0.9)) / 0.9
                guard t > 2.3 + 0.3 * Double(k), age > 0 else { continue }
                var arc = Path()
                arc.addArc(center: u.pt(x, membrane - 0.12), radius: u.len(0.05 + 0.15 * age), startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                u.stroke(context, arc, clay.opacity(signal * (1 - age)), 0.025)
            }
        }
    }
}

/// B cell receptors meeting antigen: a clay particle lands on one
/// receptor, the neighbours gather to bind it too, and the membrane draws
/// the cluster in.
enum BCellReceptor {
    static let duration = 4.4
    private static let starts = [0.14, 0.32, 0.5, 0.68, 0.86]
    private static let ends = [0.34, 0.41, 0.5, 0.59, 0.66]
    private static let tilts = [-38.0, -22, 0, 22, 38]

    private static func membrane(_ x: Double, dip: Double) -> Double { 0.8 + 0.2 * dip * exp(-pow((x - 0.5) / 0.14, 2)) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let land = Ease.out((t - 0.2) / 0.8)
        let gather = Ease.inOut((t - 1.2) / 0.9)
        let dip = Ease.inOut((t - 2.4) / 1.0)
        let fade = Ease.inOut((t - 3.8) / 0.5)
        var scene = context
        scene.opacity = 1 - fade
        let line = stride(from: 0.0, through: 1.0, by: 0.02).map { x in (x, membrane(x, dip: dip)) }
        var inside = u.polyline(line + [(1.0, 1.05), (0.0, 1.05)])
        inside.closeSubpath()
        scene.fill(inside, with: .color(tint.opacity(0.08)))
        u.stroke(scene, u.polyline(line), tint, 0.045)
        let particle = (0.5, -0.12 + (0.49 + 0.2 * dip + 0.12) * land)
        for k in 0..<5 {
            let x = starts[k] + (ends[k] - starts[k]) * gather
            let base = (x, membrane(x, dip: dip))
            var y = scene
            let p = u.pt(base.0, base.1)
            y.translateBy(x: p.x, y: p.y)
            y.rotate(by: .degrees(tilts[k] * gather))
            let stem = u.len(0.1), arm = u.len(0.06)
            var shape = Path()
            shape.move(to: .zero)
            shape.addLine(to: CGPoint(x: 0, y: -stem))
            shape.addLine(to: CGPoint(x: -arm * 0.8, y: -stem - arm))
            shape.move(to: CGPoint(x: 0, y: -stem))
            shape.addLine(to: CGPoint(x: arm * 0.8, y: -stem - arm))
            y.stroke(shape, with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.035), lineCap: .round, lineJoin: .round))
        }
        scene.fill(u.circle(particle.0, particle.1, 0.09), with: .color(clay))
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            scene.fill(u.circle(particle.0 + 0.1 * cos(a), particle.1 + 0.1 * sin(a), 0.02), with: .color(clay))
        }
    }
}

/// Clonal expansion: antigen docks on one B cell, which divides, and its
/// daughters divide, one to two to four to eight; the clone then sends out
/// clay antibodies.
enum ClonalExpansion {
    static let duration = 4.6
    private static let divisions = [0.7, 1.4, 2.1]
    private static let radii = [0.13, 0.11, 0.085, 0.065]

    /// Where the cells of generation `g` sit.
    private static func cells(_ g: Int) -> [(Double, Double)] {
        switch g {
        case 0: return [(0.5, 0.5)]
        case 1: return [(0.36, 0.5), (0.64, 0.5)]
        case 2: return [(0.36, 0.37), (0.36, 0.63), (0.64, 0.37), (0.64, 0.63)]
        default: return [(0.29, 0.37), (0.43, 0.37), (0.29, 0.63), (0.43, 0.63), (0.57, 0.37), (0.71, 0.37), (0.57, 0.63), (0.71, 0.63)]
        }
    }

    private static func cell(_ context: GraphicsContext, _ u: UnitSquare, _ p: (Double, Double), _ r: Double, tint: Color) {
        u.stroke(context, u.circle(p.0, p.1, r), tint, 0.035)
        context.fill(u.circle(p.0, p.1, r * 0.42), with: .color(clay))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.1) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        var gen = 0
        for (g, at) in divisions.enumerated() where t >= at { gen = g + 1 }
        if gen < 3 || t < divisions[2] + 0.45 {
            let g = gen == 0 ? 0 : gen - 1
            let progress = gen == 0 ? 0 : Ease.inOut((t - divisions[g]) / 0.45)
            let parents = cells(g), children = cells(g + 1)
            if gen == 0 {
                cell(scene, u, parents[0], radii[0], tint: tint)
            } else {
                for (i, c) in children.enumerated() {
                    let p = parents[i / 2]
                    let at = (p.0 + (c.0 - p.0) * progress, p.1 + (c.1 - p.1) * progress)
                    cell(scene, u, at, radii[g] + (radii[g + 1] - radii[g]) * progress, tint: tint)
                }
            }
        } else {
            for c in cells(3) { cell(scene, u, c, radii[3], tint: tint) }
        }
        let dock = Ease.out((t - 0.1) / 0.4)
        if t < divisions[0] {
            scene.fill(u.circle(0.5 + 0.13 + 0.3 * (1 - dock), 0.5 - 0.13 * dock - 0.3 * (1 - dock), 0.025), with: .color(clay))
        }
        for k in 0..<10 {
            let age = (t - 2.7 - 0.1 * Double(k)) / 1.1
            guard age > 0, age < 1 else { continue }
            let a = Double(k) * 2 * .pi / 10 + 0.3
            let d = 0.2 + 0.25 * Ease.out(age)
            var y = scene
            let p = u.pt(0.5 + d * cos(a), 0.5 + d * sin(a) * 0.9)
            y.translateBy(x: p.x, y: p.y)
            y.rotate(by: .radians(a + .pi / 2))
            let s = u.len(0.03)
            var shape = Path()
            shape.move(to: CGPoint(x: 0, y: s))
            shape.addLine(to: .zero)
            shape.addLine(to: CGPoint(x: -s * 0.7, y: -s * 0.8))
            shape.move(to: .zero)
            shape.addLine(to: CGPoint(x: s * 0.7, y: -s * 0.8))
            y.stroke(shape, with: .color(clay.opacity(1 - age * age)), style: StrokeStyle(lineWidth: u.len(0.02), lineCap: .round))
        }
    }
}

/// A blood draw: the needle goes into the clay vein, a tube pushes onto the
/// holder and fills, comes away, and the needle comes out.
enum BloodDraw {
    static let duration = 4.6
    private static let angle = 22.0
    private static let target = (0.64, 0.588)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.drawLayer { layer in
            layer.fill(u.capsule(0.5, 0.66, 1.3, 0.3, corner: 0.15), with: .color(tint))
            layer.blendMode = .destinationOut
            for x in [0.105, 0.195] { u.stroke(layer, u.line((x, 0.48), (x, 0.84)), .black, 0.018) }
            layer.blendMode = .normal
            layer.fill(u.capsule(0.15, 0.66, 0.07, 0.36, corner: 0.02), with: .color(tint))
        }
        u.stroke(context, u.line((0.14, 0.48), (0.08, 0.38)), tint, 0.04)
        u.stroke(context, u.line((0.16, 0.48), (0.22, 0.4)), tint, 0.04)
        u.stroke(context, u.line((0.22, 0.6), (0.3, 0.588), (1.05, 0.585)), clay, 0.035)
        let inserted = Keyframes.value(t, [(0.2, 0), (0.7, 1), (3.3, 1), (3.7, 0)])
        let away = Keyframes.value(t, [(3.7, 0), (4.1, 1)])
        let tubeIn = Keyframes.value(t, [(0.9, 0), (1.25, 1), (2.7, 1), (3.1, 0)])
        let tubeGone = Keyframes.value(t, [(3.0, 0), (3.3, 1)])
        let filled = Keyframes.value(t, [(1.35, 0), (2.5, 1)])
        let a = angle * .pi / 180
        let back = 0.2 * (1 - inserted) + 0.4 * away
        let tip = (target.0 - back * cos(a), target.1 - back * sin(a))

        var kit = context
        let p = u.pt(tip.0, tip.1)
        kit.translateBy(x: p.x, y: p.y)
        kit.rotate(by: .radians(a))
        func rect(_ x0: Double, _ x1: Double, _ half: Double) -> Path {
            Path(roundedRect: CGRect(x: u.len(x0), y: -u.len(half), width: u.len(x1 - x0), height: u.len(2 * half)), cornerRadius: u.len(min(half, 0.02)))
        }
        if tubeGone < 1 {
            let front = -0.18 - 0.22 * (1 - tubeIn) - 0.5 * tubeGone
            var tube = kit
            tube.clip(to: rect(front - 0.28, front, 0.04))
            tube.fill(rect(front - 0.28 * filled, front, 0.04), with: .color(clay))
            kit.stroke(rect(front - 0.28, front, 0.04), with: .color(tint), lineWidth: u.len(0.03))
        }
        kit.stroke(rect(-0.4, -0.16, 0.06), with: .color(tint), lineWidth: u.len(0.035))
        var needle = Path()
        needle.move(to: CGPoint(x: -u.len(0.16), y: 0))
        needle.addLine(to: .zero)
        kit.stroke(needle, with: .color(tint), style: StrokeStyle(lineWidth: u.len(0.018), lineCap: .round))
        kit.fill(rect(-0.18, -0.14, 0.02), with: .color(tint))
        let spot = Ease.clamp((t - 3.6) / 0.2) * (1 - Ease.clamp((t - 4.2) / 0.3))
        if spot > 0 { context.fill(u.circle(0.47, 0.515, 0.022), with: .color(clay.opacity(spot))) }
    }
}

/// Lipofection: lipids gather round a clay plasmid into a shell, the
/// complex drifts down to the cell, fuses, and the plasmid slips inside.
enum Lipofection {
    static let duration = 4.6
    private static let count = 16

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let descend = Ease.inOut((t - 1.9) / 0.7)
        let fuse = Ease.inOut((t - 2.6) / 0.7)
        let centre = (0.5, 0.4 + 0.26 * descend)
        for y in [0.84, 0.88] { u.stroke(context, u.line((0.0, y), (1.0, y)), tint.opacity(0.6), 0.02) }
        context.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, 0.88).y, width: u.side, height: u.len(0.14))), with: .color(tint.opacity(0.08)))

        for k in 0..<count {
            let s = Double(k)
            let a = s * 2 * .pi / Double(count)
            let startAngle = a + 2.2 * (BenchShapes.rand(s) - 0.5)
            let start = (0.5 + 0.75 * cos(startAngle), 0.45 + 0.75 * sin(startAngle))
            let arrive = Ease.inOut((t - 0.2 - 0.06 * s) / 0.8)
            let ring = (centre.0 + 0.17 * cos(a), centre.1 + 0.17 * sin(a))
            let slot = (0.5 + (s - 7.5) * 0.045, 0.86)
            var head = (start.0 + (ring.0 - start.0) * arrive, start.1 + (ring.1 - start.1) * arrive)
            head = (head.0 + (slot.0 - head.0) * fuse, head.1 + (slot.1 - head.1) * fuse)
            let facing = (a + .pi) * arrive + (startAngle + 1.5 * BenchShapes.rand(s + 3)) * (1 - arrive)
            let turned = facing + (.pi / 2 - facing) * fuse
            let alpha = 1 - Ease.clamp((fuse - 0.6) / 0.4)
            guard alpha > 0 else { continue }
            u.stroke(context, u.line(head, (head.0 + 0.05 * cos(turned), head.1 + 0.05 * sin(turned))), tint.opacity(alpha), 0.02)
            context.fill(u.circle(head.0, head.1, 0.02), with: .color(tint.opacity(alpha)))
        }
        let sink = Ease.inOut((t - 2.8) / 0.6)
        let fresh = Ease.inOut((t - 3.8) / 0.5)
        let plasmid = t < 3.6 ? (0.5, centre.1 + 0.3 * sink) : (0.5, 0.4)
        let alpha = t < 3.6 ? 1 - Ease.clamp((sink - 0.5) / 0.5) : fresh
        let loop = stride(from: 0.0, through: 2 * .pi + 0.01, by: 0.15).map { th -> (Double, Double) in
            let r = 0.085 + 0.012 * sin(5 * th + t * 2)
            return (plasmid.0 + r * cos(th), plasmid.1 + r * sin(th) * 0.8)
        }
        u.stroke(context, u.polyline(loop), clay.opacity(alpha), 0.035)
    }
}

/// The lac operon: lactose finds the repressor sitting on the operator and
/// lifts it off; RNA polymerase runs through the genes trailing clay mRNA;
/// then the repressor settles back.
enum LacOperon {
    static let duration = 4.6
    private static let dna = 0.7

    private static func sugar(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), alpha: Double) {
        for dx in [-0.02, 0.02] {
            let ring = (0..<6).map { k -> (Double, Double) in
                let a = Double(k) * .pi / 3 + .pi / 6
                return (p.0 + 1.3 * dx + 0.027 * cos(a), p.1 + (dx > 0 ? 0.01 : -0.01) + 0.027 * sin(a))
            }
            var hex = u.polyline(ring)
            hex.closeSubpath()
            context.fill(hex, with: .color(clay.opacity(alpha)))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.line((0.03, dna), (0.97, dna)), tint, 0.035)
        for (x, w) in [(0.14, 0.12), (0.27, 0.1)] {
            context.fill(u.capsule(x, dna, w, 0.07, corner: 0.015), with: .color(tint.opacity(0.4)))
        }
        for (x, w) in [(0.46, 0.24), (0.7, 0.18), (0.88, 0.12)] {
            u.stroke(context, u.capsule(x, dna, w, 0.09, corner: 0.02), tint, 0.03)
        }
        // Lactose drifts in and binds; the repressor lets go and leaves.
        let arrive = Ease.inOut((t - 0.3) / 0.9)
        let off = Ease.inOut((t - 1.3) / 0.7)
        let back = Ease.out((t - 3.9) / 0.5)
        let bound = (0.27, 0.53)
        let lactose = (0.85 + (bound.0 - 0.85) * arrive + 0.03 * sin(arrive * 9) * (1 - arrive), 0.08 + (bound.1 - 0.08) * arrive)
        var repressor = context
        let rp = t < 3.6 ? (0.27 - 0.12 * off, 0.61 - 0.45 * off) : (0.27, 0.61 - 0.55 * (1 - back))
        let alpha = t < 3.6 ? 1 - Ease.clamp((off - 0.5) / 0.5) : back
        let at = u.pt(rp.0, rp.1)
        repressor.translateBy(x: at.x, y: at.y)
        repressor.rotate(by: .degrees(t < 3.6 ? -30 * off : 0))
        repressor.translateBy(x: -at.x, y: -at.y)
        repressor.fill(u.capsule(rp.0, rp.1, 0.17, 0.13, corner: 0.04), with: .color(tint.opacity(alpha)))
        if t < 3.6 {
            let onIt = (lactose.0 + (rp.0 - 0.27), lactose.1 + (rp.1 - 0.61))
            sugar(repressor, u, at: t < 1.3 ? lactose : onIt, alpha: t < 1.3 ? 1 : alpha)
        }
        // RNA polymerase reads through, trailing the message.
        let run = Ease.inOut((t - 2.0) / 1.6)
        let px = 0.14 + (0.93 - 0.14) * run
        let polAlpha = 1 - Ease.clamp((t - 3.7) / 0.3) + Ease.clamp((t - 4.2) / 0.3)
        if px > 0.34 {
            let message = stride(from: 0.34, through: px, by: 0.01).map { x in
                (x, dna - 0.11 - 0.45 * (px - x) + 0.015 * sin(x * 50))
            }
            u.stroke(context, u.polyline(message), clay.opacity(1 - Ease.clamp((t - 3.7) / 0.4)), 0.03)
        }
        let showX = t > 3.95 ? 0.14 : px
        context.fill(u.ellipse(showX, dna - 0.015, 0.17, 0.15), with: .color(tint.opacity(min(1, polAlpha))))
    }
}
