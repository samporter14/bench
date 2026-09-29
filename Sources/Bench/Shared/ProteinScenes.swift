// ProteinScenes.swift
// ScienceStatus — lab scenes of protein structure and design. Each draws
// in a unit square (see `UnitSquare`): chains in the tint, what is
// designed, uncertain or binding in clay.

import SwiftUI

/// A smooth curve through points (Catmull–Rom), for drawing chains.
enum Smooth {
    static func curve(_ points: [(Double, Double)], samples: Int = 8) -> [(Double, Double)] {
        guard points.count > 2 else { return points }
        var out: [(Double, Double)] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            for k in 0..<samples {
                let t = Double(k) / Double(samples), t2 = t * t, t3 = t2 * t
                func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                out.append((blend(p0.0, p1.0, p2.0, p3.0), blend(p0.1, p1.1, p2.1, p3.1)))
            }
        }
        out.append(points[points.count - 1])
        return out
    }
}

/// A small protein fold, drawn the cartoon way: a chain whose helices
/// are tight coils.
enum Fold {
    static let compact: [(Double, Double)] = [
        (0.2, 0.26), (0.44, 0.16), (0.7, 0.24), (0.78, 0.44), (0.58, 0.52), (0.36, 0.46),
        (0.2, 0.6), (0.32, 0.8), (0.58, 0.84), (0.8, 0.7),
    ]
    /// Where along the chain (0 to 1) the helices run.
    static let helices: [(Double, Double)] = [(0.06, 0.3), (0.62, 0.9)]

    /// The chain through `points`, coiled over `helices`.
    static func ribbon(_ points: [(Double, Double)], helices: [(Double, Double)] = helices,
                       amplitude: Double = 0.035, turns: Double = 4) -> [(Double, Double)] {
        let path = Smooth.curve(points, samples: 12)
        guard path.count > 2 else { return path }
        return path.enumerated().map { i, p in
            let s = Double(i) / Double(path.count - 1)
            guard let helix = helices.first(where: { s >= $0.0 && s <= $0.1 }) else { return p }
            let local = (s - helix.0) / (helix.1 - helix.0)
            let envelope = sin(.pi * local)
            let a = path[max(0, i - 1)], b = path[min(path.count - 1, i + 1)]
            let dx = b.0 - a.0, dy = b.1 - a.1
            let length = max(hypot(dx, dy), 0.0001)
            let offset = amplitude * envelope * sin(2 * .pi * turns * local)
            return (p.0 - dy / length * offset, p.1 + dx / length * offset)
        }
    }
}

/// Structure prediction, confidence bloom: a cloud of faint conformations
/// wavers, then settles into one crisp chain whose ends stay loose and
/// clay (low confidence, as AlphaFold colours it), and dissolves again.
enum ConfidenceBloom {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let settle = Ease.inOut((t - 0.8) / 1.2) * (1 - Ease.inOut((t - 3.2) / 0.6))
        func conformation(_ c: Double, _ looseness: Double) -> [(Double, Double)] {
            Fold.compact.enumerated().map { i, p in
                let s = Double(i)
                let ends = (i < 2 || i > Fold.compact.count - 3) ? 1.0 : 0
                let amp = 0.07 * looseness + 0.035 * ends * sin(t * 2 + s)
                return (p.0 + amp * sin(s * 1.9 + c * 2.1 + t * 1.6), p.1 + amp * cos(s * 1.3 + c * 2.7 + t * 1.3))
            }
        }
        if settle < 1 {
            for c in 0..<3 {
                u.stroke(context, u.polyline(Fold.ribbon(conformation(Double(c), 1))), tint.opacity(0.3 * (1 - settle)), 0.04)
            }
        }
        if settle > 0 {
            let chain = Fold.ribbon(conformation(0, 1 - settle))
            u.stroke(context, u.polyline(chain), tint.opacity(settle), 0.055)
            let cut = chain.count / 6
            u.stroke(context, u.polyline(Array(chain.prefix(cut + 1))), clay.opacity(settle), 0.055)
            u.stroke(context, u.polyline(Array(chain.suffix(cut + 1))), clay.opacity(settle), 0.055)
        }
    }
}

/// Generative binder design, binder swarm: three candidate binders form
/// out of noise round a still target and circle it; two dissolve, and the
/// best one clicks onto the clay epitope.
enum BinderSwarm {
    static let duration = 4.0
    private static let target = (0.36, 0.5)

    private static func binder(_ context: GraphicsContext, _ u: UnitSquare, at p: (Double, Double), angle: Double,
                               color: Color) {
        var b = context
        let c = u.pt(p.0, p.1)
        b.translateBy(x: c.x, y: c.y)
        b.rotate(by: .radians(angle))
        for dy in [-0.03, 0.03] {
            b.stroke(Path(roundedRect: CGRect(x: -u.len(0.07), y: u.len(dy - 0.018), width: u.len(0.14), height: u.len(0.036)),
                          cornerRadius: u.len(0.018)), with: .color(color), lineWidth: u.len(0.03))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The target: a lumpy protein, its epitope in clay.
        let lumps = (0..<24).map { i -> (Double, Double) in
            let a = Double(i) / 24 * 2 * .pi
            let r = 0.2 + 0.02 * sin(a * 5) + 0.015 * cos(a * 3)
            return (target.0 + r * cos(a), target.1 + r * sin(a))
        }
        var body = u.polyline(Smooth.curve(lumps + [lumps[0]], samples: 4))
        body.closeSubpath()
        context.fill(body, with: .color(tint))
        context.fill(u.ellipse(target.0 + 0.19, target.1 - 0.02, 0.07, 0.14), with: .color(clay))

        let form = Ease.inOut((t - 0.4) / 0.6)
        for k in 0..<3 {
            let base = Double(k) * 2 * .pi / 3
            let orbit = base + 2 * .pi * Ease.inOut((t - 1.0) / 1.4)
            var p = (target.0 + 0.38 * cos(orbit), target.1 + 0.34 * sin(orbit))
            var angle = orbit + .pi / 2
            if k == 0 {
                let dock = Ease.inOut((t - 2.4) / 0.5)
                let site = (target.0 + 0.3, target.1 - 0.02)
                p = (p.0 + (site.0 - p.0) * dock, p.1 + (site.1 - p.1) * dock)
                angle += (.pi / 2 - angle.truncatingRemainder(dividingBy: .pi)) * dock
                if t < 1.0 {
                    noise(context, u, around: p, form: form, seed: Double(k))
                } else {
                    binder(context, u, at: p, angle: angle, color: tint)
                }
            } else {
                let fade = 1 - Ease.clamp((t - 2.2) / 0.4)
                guard fade > 0 else { continue }
                if t < 1.0 {
                    noise(context, u, around: p, form: form, seed: Double(k))
                } else {
                    binder(context, u, at: p, angle: angle, color: tint.opacity(fade))
                }
            }
        }
        let click = (t - 2.9) / 0.5
        if click > 0, click < 1 {
            u.stroke(context, u.circle(target.0 + 0.3, target.1 - 0.02, 0.08 + 0.08 * click), clay.opacity(1 - click), 0.04)
        }
    }

    private static func noise(_ context: GraphicsContext, _ u: UnitSquare, around p: (Double, Double), form: Double, seed: Double) {
        for i in 0..<7 {
            let a = Double(i) * 2.4 + seed
            let r = 0.12 * (1 - form)
            context.fill(u.circle(p.0 + r * cos(a) + 0.03 * sin(a * 3), p.1 + r * sin(a), 0.014), with: .color(clay.opacity(0.4 + 0.6 * form)))
        }
    }
}

/// Affinity optimisation, interface polish: two proteins meet with gaps;
/// three side chains turn into the pockets opposite, the surfaces close up,
/// and a clay glow runs along the new contact.
enum InterfacePolish {
    static let duration = 3.6
    private static let pockets = [0.3, 0.5, 0.7]
    private static let start = [35.0, -30.0, 25.0]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fit = Ease.inOut((t - 0.5) / 1.6)
        let close = 0.05 * (1 - fit)

        context.fill(u.capsule(0.27, 0.5, 0.38, 0.8, corner: 0.17), with: .color(tint))
        for (i, y) in pockets.enumerated() {
            var chain = context
            let root = u.pt(0.45, y)
            chain.translateBy(x: root.x, y: root.y)
            chain.rotate(by: .degrees(start[i] * (1 - fit)))
            chain.fill(Path(roundedRect: CGRect(x: 0, y: -u.len(0.03), width: u.len(0.09), height: u.len(0.06)),
                            cornerRadius: u.len(0.03)), with: .color(tint))
        }
        context.drawLayer { layer in
            layer.fill(u.capsule(0.73 + close, 0.5, 0.38, 0.8, corner: 0.17), with: .color(tint))
            layer.blendMode = .destinationOut
            for y in pockets {
                layer.fill(u.circle(0.54 + close, y, 0.045), with: .color(.black))
            }
        }
        let glow = (t - 2.3) / 0.9
        if glow > 0, glow < 1 {
            context.fill(u.circle(0.5, 0.14 + 0.72 * glow, 0.035), with: .color(clay))
        }
    }
}

/// Inverse folding: the target fold waits as a dashed outline; below it a
/// sequence is picked residue by residue, each trying shapes before it
/// settles in clay; then the chain rises and folds onto the target, which
/// goes solid: a sequence designed to take that shape.
enum InverseFolding {
    static let duration = 4.4
    private static let count = 10

    private static func glyph(_ u: UnitSquare, _ kind: Int, at p: (Double, Double), _ r: Double) -> Path {
        switch kind % 4 {
        case 0: return u.circle(p.0, p.1, r)
        case 1: return Path(CGRect(x: u.pt(p.0 - r, p.1 - r).x, y: u.pt(p.0 - r, p.1 - r).y, width: u.len(2 * r), height: u.len(2 * r)))
        case 2:
            var tri = u.line((p.0, p.1 - r * 1.2), (p.0 + r * 1.1, p.1 + r * 0.8), (p.0 - r * 1.1, p.1 + r * 0.8))
            tri.closeSubpath()
            return tri
        default:
            var diamond = u.line((p.0, p.1 - r * 1.3), (p.0 + r * 1.1, p.1), (p.0, p.1 + r * 1.3), (p.0 - r * 1.1, p.1))
            diamond.closeSubpath()
            return diamond
        }
    }

    /// The target: the shared fold, shrunk into the top of the square to
    /// leave room for the sequence below. Fixed, so worked out once.
    private static func fitted(_ p: (Double, Double)) -> (Double, Double) {
        (0.5 + (p.0 - 0.5) * 0.78, 0.1 + (p.1 - 0.16) * 0.78)
    }
    private static let backbone = Fold.ribbon(Fold.compact).map(fitted)
    private static let slots: [(Double, Double)] = (0..<count).map { Polyline.point(backbone, at: (Double($0) + 0.5) / Double(count)) }
    private static let kinds = [2, 0, 3, 1, 1, 3, 0, 2, 3, 1]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fold = Ease.inOut((t - 2.1) / 1.0)
        let solid = Ease.clamp((t - 3.0) / 0.35)

        // The target, dashed until the chain lands on it.
        let target = u.polyline(backbone)
        if solid < 1 {
            context.stroke(target, with: .color(tint.opacity(0.45 * (1 - solid))),
                           style: StrokeStyle(lineWidth: max(u.len(0.035), UnitSquare.hairline), lineCap: .round,
                                              dash: [u.len(0.035), u.len(0.04)]))
        }
        // The designed sequence: residues along a row, then folded up.
        let residues = (0..<count).map { i -> (Double, Double) in
            let row = (0.14 + 0.08 * Double(i), 0.87)
            let slot = slots[i]
            let lag = Ease.inOut(fold * 1.25 - 0.025 * Double(i))
            return (row.0 + (slot.0 - row.0) * lag, row.1 + (slot.1 - row.1) * lag)
        }
        let picked = residues.indices.filter { t >= 0.35 + 0.16 * Double($0) }
        if picked.count > 1 {
            let chain = picked.map { residues[$0] }
            u.stroke(context, u.polyline(chain), tint.opacity(1 - solid), 0.035)
        }
        if solid > 0 { u.stroke(context, target, tint.opacity(solid), 0.045) }
        for i in residues.indices where t >= 0.35 + 0.16 * Double(i) - 0.3 {
            // Each tries a few shapes, then settles.
            let settled = t >= 0.35 + 0.16 * Double(i)
            let kind = settled ? kinds[i] : Int(t * 12) + i
            context.fill(glyph(u, kind, at: residues[i], 0.028), with: .color(settled ? clay : tint.opacity(0.6)))
        }
    }
}

/// Diffusion design: a loose cloud of points condenses into a new compact
/// backbone, drawn in clay, then dissolves back into noise.
enum DiffusionDesign {
    static let duration = 4.0
    private static let points = 44
    /// Where each point ends up on the folded backbone: fixed, so worked
    /// out once rather than every frame.
    private static let targets: [(Double, Double)] = {
        let backbone = Fold.ribbon(Fold.compact)
        return (0..<points).map { Polyline.point(backbone, at: Double($0) / Double(points - 1)) }
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let denoise = Ease.inOut((t - 0.4) / 1.6) * (1 - Ease.inOut((t - 3.1) / 0.7))
        let placed = (0..<points).map { i -> (Double, Double) in
            let target = targets[i]
            let s = Double(i)
            let noise = (0.5 + 0.38 * sin(s * 2.7 + 0.3 * sin(t + s)), 0.5 + 0.38 * cos(s * 1.9 + 0.3 * cos(t * 1.2 + s)))
            return (noise.0 + (target.0 - noise.0) * denoise, noise.1 + (target.1 - noise.1) * denoise)
        }
        if denoise > 0.3 {
            u.stroke(context, u.polyline(placed), clay.opacity(Ease.clamp((denoise - 0.3) / 0.5)), 0.05)
        }
        for p in placed {
            context.fill(u.circle(p.0, p.1, 0.018), with: .color(tint.opacity(1 - 0.6 * denoise)))
        }
    }
}

/// Multimer prediction: four copies of one subunit, two in the tint and two
/// in clay as a model colours its chains, drift in wobbling, try a fit,
/// turn and close up until they touch, bound into a symmetric ring; the
/// finished complex turns slowly.
enum Multimer {
    static let duration = 4.2

    /// A kidney-shaped subunit, its flatter side facing its partner.
    private static func subunit(_ context: GraphicsContext, _ u: UnitSquare, centre: (Double, Double), angle: Double,
                                facing: Double, wobble: Double, t: Double, size: Double, color: Color) {
        let outline = (0..<20).map { i -> (Double, Double) in
            let a = Double(i) / 20 * 2 * .pi
            var r = 0.14 + 0.025 * sin(2 * a + 0.6) + 0.02 * cos(3 * a) + wobble * 0.012 * sin(t * 3 + Double(i))
            // Flatten the side that meets the partner.
            let toward = cos(a) * facing
            if toward > 0.5 { r *= 1 - 0.35 * (toward - 0.5) }
            r *= size
            let x = r * cos(a), y = r * sin(a) * 1.15
            let ca = cos(angle), sa = sin(angle)
            return (centre.0 + x * ca - y * sa, centre.1 + x * sa + y * ca)
        }
        var shape = u.polyline(Smooth.curve(outline + [outline[0], outline[1]], samples: 4))
        shape.closeSubpath()
        context.fill(shape, with: .color(color))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // In, a little back off, then docked.
        let distance = Keyframes.value(t, [(0, 0.44), (1.1, 0.24), (1.45, 0.27), (2.1, 0.118)])
        let turn = Ease.inOut((t - 1.45) / 0.65)
        let settled = Ease.clamp((t - 2.1) / 0.3)
        let spin = 0.45 * Ease.inOut((t - 2.4) / 1.6)
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4 + spin
            let centre = (0.5 + distance * cos(a), 0.5 + distance * sin(a))
            // Flat side towards the middle once it has turned into place.
            subunit(context, u, centre: centre, angle: a + .pi + 1.1 * (1 - turn), facing: 1,
                    wobble: 1 - settled, t: t + Double(k), size: 0.72, color: k % 2 == 0 ? tint : clay)
        }
    }
}

/// Cryo-EM: a micrograph of many copies of one particle, frozen in ice at
/// every angle; circles pick them out; they fly to the middle turning to line
/// up, and their average comes out sharp: a density map, a clay chain
/// fitted inside it.
enum CryoEM {
    static let duration = 4.8
    private static let particles: [(x: Double, y: Double, angle: Double)] = [
        (0.2, 0.2, 0.4), (0.52, 0.15, 2.1), (0.82, 0.24, 4.0), (0.14, 0.55, 1.2),
        (0.86, 0.6, 5.3), (0.28, 0.85, 3.1), (0.7, 0.84, 0.9),
    ]
    private static let shape: [(Double, Double)] = [(-0.5, -0.65), (0.15, -0.7), (0.25, -0.1), (0.7, 0.1), (0.6, 0.6), (-0.2, 0.55), (-0.6, 0.1)]
    private static let specks: [(Double, Double)] = (0..<46).map { (BenchShapes.rand(Double($0) * 3.7), BenchShapes.rand(Double($0) * 8.3)) }

    private static func blob(_ u: UnitSquare, at c: (Double, Double), angle: Double, scale k: Double) -> Path {
        let turned = shape.map { p -> (Double, Double) in
            (c.0 + k * (p.0 * cos(angle) - p.1 * sin(angle)), c.1 + k * (p.0 * sin(angle) + p.1 * cos(angle)))
        }
        var path = u.polyline(Smooth.curve(turned + [turned[0], turned[1]], samples: 5))
        path.closeSubpath()
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let gather = Ease.inOut((t - 1.7) / 1.0)
        let sharp = Ease.inOut((t - 2.5) / 0.6)
        let chain = Ease.inOut((t - 3.1) / 0.8)
        // The ice's grain, fading as the average takes over.
        for p in specks {
            context.fill(u.circle(0.05 + 0.9 * p.0, 0.05 + 0.9 * p.1, 0.008), with: .color(tint.opacity(0.25 * (1 - sharp))))
        }
        for (i, p) in particles.enumerated() {
            let pick = Ease.outBack((t - 0.5 - 0.13 * Double(i)) / 0.3)
            let at = (p.x + (0.5 - p.x) * gather, p.y + (0.5 - p.y) * gather)
            let angle = p.angle * (1 - gather)
            let k = 0.075 + (0.2 - 0.075) * gather
            context.fill(blob(u, at: at, angle: angle, scale: k), with: .color(tint.opacity(0.6 * (1 - sharp) * (gather > 0 ? 0.7 : 1))))
            if pick > 0, gather < 1 {
                u.stroke(context, u.circle(at.0, at.1, 0.1 * min(1, pick)), clay.opacity(1 - gather), 0.022)
            }
        }
        if sharp > 0 {
            let map = blob(u, at: (0.5, 0.5), angle: 0, scale: 0.3)
            context.fill(map, with: .color(tint.opacity(0.14 * sharp)))
            u.stroke(context, map, tint.opacity(sharp), 0.035)
            u.stroke(context, blob(u, at: (0.52, 0.5), angle: 0, scale: 0.2), tint.opacity(0.45 * sharp), 0.025)
        }
        if chain > 0 {
            let trace: [(Double, Double)] = [(0.38, 0.34), (0.52, 0.32), (0.5, 0.44), (0.62, 0.5), (0.66, 0.62), (0.52, 0.64), (0.42, 0.56), (0.36, 0.48)]
            u.stroke(context, u.polyline(Smooth.curve(trace, samples: 5)).trimmedPath(from: 0, to: chain), clay, 0.035)
        }
    }
}

/// Sheets and helices: an extended chain zips into a hairpin, then a third
/// strand, making a β-sheet; the rest coils into an α-helix alongside. All
/// one smooth line: the turns are round, the helix coils out of the chain
/// itself, and the strands thicken into clay ribbons with arrowheads.
enum SheetsAndHelices {
    static let duration = 5.0

    /// The folded chain, dense enough to stay smooth, and where its strands
    /// and helix lie along it.
    private static let layout: (points: [(Double, Double)], strands: [Range<Int>], helix: Range<Int>) = {
        var points: [(Double, Double)] = []
        func line(_ a: (Double, Double), _ b: (Double, Double), _ n: Int) {
            for k in 0..<n { let f = Double(k) / Double(n); points.append((a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f)) }
        }
        func arc(_ c: (Double, Double), _ r: Double, from a0: Double, to a1: Double, _ n: Int) {
            for k in 0..<n {
                let a = (a0 + (a1 - a0) * Double(k) / Double(n)) * .pi / 180
                points.append((c.0 + r * cos(a), c.1 + r * sin(a)))
            }
        }
        var strands: [Range<Int>] = []
        var start = points.count
        line((0.2, 0.8), (0.2, 0.36), 10); strands.append(start..<points.count)
        arc((0.26, 0.36), 0.06, from: 180, to: 360, 8)
        start = points.count
        line((0.32, 0.36), (0.32, 0.8), 10); strands.append(start..<points.count)
        arc((0.38, 0.8), 0.06, from: 180, to: 0, 8)
        start = points.count
        line((0.44, 0.8), (0.44, 0.36), 10); strands.append(start..<points.count)
        // A curving link over to the top of the helix.
        for k in 0..<10 {
            let f = Double(k) / 10
            let a = (0.44, 0.36), c = (0.5, 0.18), b = (0.72, 0.33)
            points.append(((1 - f) * (1 - f) * a.0 + 2 * (1 - f) * f * c.0 + f * f * b.0,
                           (1 - f) * (1 - f) * a.1 + 2 * (1 - f) * f * c.1 + f * f * b.1))
        }
        start = points.count
        for k in 0...40 {
            let f = Double(k) / 40, a = 2 * .pi * 3.5 * f
            points.append((0.72 + 0.075 * sin(a), 0.3 + 0.5 * f + 0.03 * cos(a)))
        }
        return (points, strands, start..<points.count)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let folded = layout.points
        let count = folded.count
        let hairpinEnd = layout.strands[1].upperBound + 8, sheetEnd = layout.strands[2].upperBound
        // The hairpin zips first, then the third strand, then the helix.
        func settle(_ i: Int) -> Double {
            let start: Double
            if i < hairpinEnd { start = 0.9 + 0.006 * Double(i) }
            else if i < sheetEnd { start = 1.55 + 0.006 * Double(i - hairpinEnd) }
            else { start = 2.05 + 0.004 * Double(i - sheetEnd) }
            return Ease.inOut((t - start) / 0.9)
        }
        let points = (0..<count).map { i -> (Double, Double) in
            let s = Double(i)
            let open = (0.05 + 0.9 * s / Double(count - 1), 0.5 + 0.08 * sin(s * 0.22 + t * 1.8))
            let k = settle(i)
            return (open.0 + (folded[i].0 - open.0) * k, open.1 + (folded[i].1 - open.1) * k)
        }
        let cartoon = Ease.inOut((t - 3.0) / 0.7)
        u.stroke(context, u.polyline(Smooth.curve(points, samples: 2)), tint, 0.035)
        // The helix thickens a little once it has coiled.
        if cartoon > 0 {
            u.stroke(context, u.polyline(Smooth.curve(Array(points[layout.helix]), samples: 2)), tint, 0.035 + 0.02 * cartoon)
        }
        guard cartoon > 0 else { return }
        // The β-strands: clay ribbons that widen out of the chain, each
        // ending in a rounded arrowhead pointing along it.
        for range in layout.strands {
            let a = points[range.lowerBound], b = points[range.upperBound - 1]
            let dy = b.1 > a.1 ? 1.0 : -1.0
            let neck = (b.0, b.1 - dy * 0.07 * cartoon)
            u.stroke(context, u.line(a, neck), clay.opacity(cartoon), 0.035 + 0.04 * cartoon)
            let w = 0.065 * cartoon
            var head = u.line((neck.0 - w, neck.1), (neck.0 + w, neck.1), (b.0, b.1 + dy * 0.02))
            head.closeSubpath()
            context.fill(head, with: .color(clay.opacity(cartoon)))
            context.stroke(head, with: .color(clay.opacity(cartoon)),
                           style: StrokeStyle(lineWidth: u.len(0.02), lineJoin: .round))
        }
    }
}
