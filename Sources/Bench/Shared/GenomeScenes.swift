// GenomeScenes.swift
// ScienceStatus — the genome at work: reading frames, chromosomes and
// their ends, chromatin marks, factors finding their sites, and barcodes.
// Each draws in a unit square (see `UnitSquare`): DNA, proteins and
// machinery in the tint, the site, the mark or the product in clay.

import SwiftUI

/// A frameshift, codon by codon: the ribosome reads along in threes, stalls
/// on the clay slippery stretch, slips back one letter, and every codon
/// after it is read in the new frame: the chain it makes turns clay.
enum FrameshiftFrame {
    static let duration = 4.8
    private static let base = 0.63
    private static let residues: [(at: Double, shifted: Bool)] = [(0.5, false), (1.1, false), (1.7, false), (2.3, false), (3.5, true), (4.1, true)]

    private static func x(_ nt: Double) -> Double { 0.05 + 0.03 * nt }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.4) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let shift = Ease.inOut((t - 2.6) / 0.3)
        for i in 0..<30 {
            let slippery = (12...18).contains(i)
            u.stroke(scene, u.line((x(Double(i)), base - 0.025), (x(Double(i)), base + 0.01)), slippery ? clay : tint.opacity(0.6), 0.016)
        }
        u.stroke(scene, u.line((x(0) - 0.01, base + 0.01), (x(29) + 0.01, base + 0.01)), tint.opacity(0.6), 0.016)
        for j in stride(from: 0, to: 28, by: 3) {
            let start = Double(j) - (j >= 18 ? shift : 0)
            let a = x(start) - 0.011, b = x(start + 2) + 0.011
            u.stroke(scene, u.line((a, base + 0.035), (a, base + 0.05), (b, base + 0.05), (b, base + 0.035)), tint.opacity(0.45), 0.013)
        }
        let p = Keyframes.value(t, [(0.2, 0), (0.5, 3), (0.8, 3), (1.1, 6), (1.4, 6), (1.7, 9), (2.0, 9), (2.3, 12), (2.6, 12),
                                   (2.9, 11), (3.2, 11), (3.5, 14), (3.8, 14), (4.1, 17)])
        let centre = x(p + 2.5)
        scene.fill(u.ellipse(centre, base + 0.045, 0.22, 0.09), with: .color(tint.opacity(0.25)))
        u.stroke(scene, u.ellipse(centre, base + 0.045, 0.22, 0.09), tint, 0.022)
        scene.fill(u.ellipse(centre, base - 0.08, 0.26, 0.15), with: .color(tint.opacity(0.25)))
        u.stroke(scene, u.ellipse(centre, base - 0.08, 0.26, 0.15), tint, 0.022)
        let made = residues.filter { t > $0.at }
        for (m, residue) in made.reversed().enumerated() {
            let pop = Ease.outBack((t - residue.at) / 0.25)
            let bead = (centre - 0.05 - 0.045 * Double(m), base - 0.19 - 0.035 * Double(m) + 0.01 * sin(Double(m) * 1.7))
            scene.fill(u.circle(bead.0, bead.1, 0.02 * pop), with: .color(residue.shifted ? clay : tint))
        }
    }
}

/// A centromere at work: spindle fibres reach the clay kinetochores from
/// both poles and pull; the cohesin gives, and the sister chromatids are
/// drawn apart, arms trailing.
enum Centromere {
    static let duration = 4.8

    private static func chromatid(_ context: GraphicsContext, _ u: UnitSquare, side: Double, apart: Double, tension: Double, tint: Color) {
        let c = (0.5 + side * (0.02 + tension + apart), 0.5)
        // At rest the arms bow outwards; pulled, they trail behind the
        // centromere, back towards the middle.
        let pulled = min(1, apart / 0.3)
        let tip = 0.05 - 0.17 * pulled
        let top = (c.0 + side * tip, 0.2 + 0.08 * pulled), bottom = (c.0 + side * tip, 0.8 - 0.08 * pulled)
        let arm = Smooth.curve([top, c, bottom], samples: 8)
        u.stroke(context, u.polyline(arm), tint, 0.07)
        context.fill(u.capsule(c.0 + side * 0.035, 0.5, 0.03, 0.07, corner: 0.012), with: .color(clay))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let apart = 0.3 * Ease.inOut((t - 2.5) / 1.1)
        let tension = t > 1.3 && t < 2.5 ? 0.006 + 0.004 * sin(t * 9) : 0
        for side in [-1.0, 1.0] {
            let pole = (0.5 + side * 0.46, 0.5)
            scene.fill(u.circle(pole.0, pole.1, 0.03), with: .color(tint))
            let kinetochore = (0.5 + side * (0.02 + tension + apart + 0.05), 0.5)
            for (k, dy) in [-0.03, 0.0, 0.03].enumerated() {
                let grow = Ease.out((t - 0.3 - 0.2 * Double(k)) / 0.7)
                guard grow > 0 else { continue }
                let target = (kinetochore.0, kinetochore.1 + dy)
                let tip = (pole.0 + (target.0 - pole.0) * grow, pole.1 + (target.1 - pole.1) * grow)
                u.stroke(scene, u.line(pole, tip), tint.opacity(0.6), 0.02)
            }
            chromatid(scene, u, side: side, apart: apart, tension: tension, tint: tint)
        }
        if apart < 0.01 {
            for y in [0.43, 0.57] { u.stroke(scene, u.ellipse(0.5, y, 0.1, 0.03), tint.opacity(0.7), 0.015) }
        }
    }
}

/// Telomeres: each round of copying loses a clay repeat off the end, three
/// times; then telomerase arrives with its template and writes them back.
enum Telomere {
    static let duration = 4.8
    private static let rounds = [0.4, 1.0, 1.6]
    private static let writes = [2.5, 2.9, 3.3]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var count = 8.0
        for r in rounds { count -= Ease.inOut((t - r - 0.4) / 0.2) }
        for w in writes { count += Ease.out((t - w) / 0.25) }
        let end = 0.36 + 0.06 * count
        u.stroke(context, u.line((0.04, 0.44), (end, 0.44)), tint, 0.04)
        u.stroke(context, u.line((0.04, 0.56), (end - 0.03, 0.56)), tint, 0.04)
        for k in 0..<Int(ceil(count)) {
            let whole = min(1, count - Double(k))
            context.fill(u.capsule(0.4 + 0.06 * Double(k) + 0.025, 0.5, 0.045 * whole, 0.09, corner: 0.012), with: .color(clay.opacity(whole)))
        }
        for r in rounds {
            let sweep = Ease.inOut((t - r) / 0.4)
            guard sweep > 0, t < r + 0.55 else { continue }
            let x = 0.04 + (end - 0.1) * sweep
            u.stroke(context, u.line((0.04, 0.63), (x, 0.63)), clay.opacity(0.6), 0.025)
        }
        // Telomerase: in, writing a repeat per step, and away.
        let come = Ease.inOut((t - 2.0) / 0.4), go = Ease.inOut((t - 3.7) / 0.5)
        guard come > 0, go < 1 else { return }
        let at = (end + 0.03 + 0.3 * (1 - come) + 0.3 * go, 0.5 - 0.3 * (1 - come) - 0.3 * go)
        context.fill(u.ellipse(at.0, at.1 - 0.03, 0.2, 0.2), with: .color(tint.opacity(0.9)))
        u.stroke(context, u.line((at.0 - 0.06, at.1 + 0.03), (at.0 + 0.05, at.1 + 0.03)), clay, 0.025)
    }
}

/// A chromosome condensing: loose clay chromatin fills the nucleus; the
/// envelope fades, and the fibre gathers into the loops of an X.
enum ChromosomeCondensing {
    static let duration = 4.8
    private static let points = 30

    private static func loose(_ s: Double) -> (Double, Double) {
        (0.5 + 0.24 * sin(2 * .pi * 2.3 * s + 1) + 0.05 * sin(2 * .pi * 9 * s),
         0.5 + 0.24 * cos(2 * .pi * 1.7 * s) * sin(2 * .pi * 0.9 * s + 0.4) + 0.05 * cos(2 * .pi * 11 * s))
    }

    /// Arm `k` of the X, `q` from its centromere (0) to its tip (1), wound
    /// into tight loops.
    private static func arm(_ k: Int, _ q: Double) -> (Double, Double) {
        let side = k < 2 ? -1.0 : 1.0, up = k % 2 == 0 ? -1.0 : 1.0
        let centre = (0.5 + 0.035 * side, 0.5)
        let tip = (0.5 + 0.13 * side, 0.5 + 0.32 * up)
        let dir = (tip.0 - centre.0, tip.1 - centre.1)
        let len = hypot(dir.0, dir.1)
        let perp = (-dir.1 / len, dir.0 / len)
        let wiggle = 0.035 * sin(2 * .pi * 5 * q)
        return (centre.0 + dir.0 * q + perp.0 * wiggle, centre.1 + dir.1 * q + perp.1 * wiggle)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let condense = Ease.inOut((t - 0.4) / 2.4)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.circle(0.5, 0.5, 0.38), tint.opacity(1 - condense), 0.035)
        for k in 0..<4 {
            let piece = (0...points).map { i -> (Double, Double) in
                let q = Double(i) / Double(points)
                let a = loose((Double(k) + q) / 4)
                let b = arm(k, q)
                let wobble = 0.02 * sin(.pi * condense) * sin(q * 20 + t * 3)
                return (a.0 + (b.0 - a.0) * condense + wobble, a.1 + (b.1 - a.1) * condense)
            }
            u.stroke(scene, u.polyline(piece), clay, 0.028 + 0.012 * condense)
        }
    }
}

/// Histone marks: a writer walks along the nucleosomes leaving clay marks
/// on their tails; a reader docks on one; and the chromatin loosens and
/// opens.
enum HistoneMarks {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let open = Ease.inOut((t - 2.9) / 0.7)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let spacing = 0.18 + 0.05 * open
        let first = 0.5 - 1.5 * spacing
        let wave = stride(from: 0.0, through: 1.0, by: 0.01).map { x in (x, 0.6 + (0.07 - 0.03 * open) * sin((x - first) / spacing * 2 * .pi + .pi / 2)) }
        u.stroke(scene, u.polyline(wave), clay.opacity(0.9), 0.028)
        for k in 0..<4 {
            let x = first + spacing * Double(k)
            scene.fill(u.ellipse(x, 0.6, 0.12, 0.13), with: .color(tint))
            u.stroke(scene, u.line((x - 0.05, 0.64), (x + 0.05, 0.56)), clay, 0.028)
            for (j, lean) in [-1.0, 1.0].enumerated() {
                let tail = stride(from: 0.0, through: 1.0, by: 0.1).map { s in
                    (x + 0.03 * lean + 0.03 * lean * s + 0.008 * sin(s * 12 + Double(k)), 0.53 - 0.14 * s)
                }
                u.stroke(scene, u.polyline(tail), tint, 0.02)
                let marked = Ease.outBack((t - 0.6 - 0.45 * Double(k) - 0.1 * Double(j)) / 0.25)
                guard marked > 0, let end = tail.last else { continue }
                if k % 2 == 0 {
                    scene.fill(u.circle(end.0, end.1 - 0.015, 0.018 * marked), with: .color(clay))
                } else {
                    var flag = u.line((end.0 - 0.02 * marked, end.1 - 0.005), (end.0, end.1 - 0.04 * marked), (end.0 + 0.02 * marked, end.1 - 0.005))
                    flag.closeSubpath()
                    scene.fill(flag, with: .color(clay))
                }
            }
        }
        let walk = Keyframes.value(t, [(0.4, first - 0.1), (0.6, first), (1.05, first + spacing), (1.5, first + 2 * spacing), (1.95, first + 3 * spacing), (2.3, 1.1)])
        if t < 2.3 { scene.fill(u.ellipse(walk, 0.3, 0.11, 0.08), with: .color(tint.opacity(0.6))) }
        let dock = Ease.out((t - 2.4) / 0.4)
        if dock > 0 {
            let x = first + spacing + 0.06 + 0.03 * open
            var reader = scene
            reader.translateBy(x: 0, y: -u.len(0.25 * (1 - dock)))
            reader.fill(u.capsule(x, 0.27, 0.1, 0.07, corner: 0.025), with: .color(tint))
        }
    }
}

/// A transcription factor finding its site: it lands on the DNA, slides and
/// hops, reaches the clay motif and clamps on; the polymerase follows and
/// clay message comes off.
enum TFSearch {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        u.stroke(scene, u.line((0.02, 0.56), (0.98, 0.56)), tint, 0.025)
        u.stroke(scene, u.line((0.02, 0.64), (0.98, 0.64)), tint, 0.025)
        for k in 0..<32 {
            let x = 0.04 + 0.03 * Double(k)
            let motif = x > 0.63 && x < 0.77
            u.stroke(scene, u.line((x, 0.57), (x, 0.63)), motif ? clay : tint.opacity(0.4), 0.014)
        }
        let x = Keyframes.value(t, [(0.2, 0.2), (0.5, 0.2), (1.3, 0.3), (1.7, 0.5), (2.3, 0.7)]) + (t > 0.5 && t < 2.3 ? 0.012 * sin(t * 11) : 0)
        let y = Keyframes.value(t, [(0.2, 0.08), (0.5, 0.5), (1.3, 0.5), (1.5, 0.36), (1.7, 0.5)])
        let bound = Ease.clamp((t - 2.3) / 0.2)
        scene.fill(u.capsule(x, y - 0.02, 0.13, 0.09, corner: 0.035), with: .color(bound > 0.5 ? clay : tint))
        for side in [-1.0, 1.0] {
            let leg = (x + 0.045 * side, y + 0.02)
            let foot = (x + 0.05 * side, y + 0.06 + 0.1 * bound)
            u.stroke(scene, u.line(leg, foot), bound > 0.5 ? clay : tint, 0.022)
        }
        let come = Ease.inOut((t - 2.6) / 0.5)
        if come > 0 {
            let p = (0.88 + 0.2 * (1 - come), 0.48 - 0.3 * (1 - come))
            scene.fill(u.ellipse(p.0, p.1, 0.17, 0.15), with: .color(tint))
            let grow = Ease.clamp((t - 3.2) / 0.8)
            if grow > 0 {
                let message = stride(from: 0.0, through: grow, by: 0.02).map { s in (p.0 - 0.04 - 0.1 * s + 0.012 * sin(s * 25), p.1 - 0.08 - 0.3 * s) }
                if message.count > 1 { u.stroke(scene, u.polyline(message), clay, 0.025) }
            }
        }
    }
}

/// Droplet barcoding: a cell and a clay barcoded bead are caught together in
/// a droplet of oil; the bead dissolves, the cell opens, and each message
/// inside picks up the droplet's barcode.
enum DropletBarcoding {
    static let duration = 4.8
    private static let every = 1.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for k in -3...3 {
            let born = 0.3 + every * Double(k)
            let age = t - born
            guard age > 0 else { continue }
            let x = 0.36 + 0.22 * age
            guard x < 1.12 else { continue }
            let form = Ease.out(age / 0.3)
            let r = 0.1 * form
            context.fill(u.circle(x, 0.5, r), with: .color(tint.opacity(0.07)))
            u.stroke(context, u.circle(x, 0.5, r), tint, 0.022)
            let dissolve = Ease.inOut((age - 0.6) / 0.8)
            let lyse = Ease.inOut((age - 0.8) / 0.4)
            let tag = Ease.inOut((age - 1.4) / 0.8)
            if dissolve < 1 {
                let bead = (x - 0.035, 0.48)
                context.fill(u.circle(bead.0, bead.1, 0.035 * (1 - dissolve) * form), with: .color(clay))
                let pattern = (k + 12) % 4
                for s in 0..<3 where (pattern >> (s % 2)) & 1 == 0 || s == 1 {
                    let dx = (Double(s) - 1) * 0.012
                    u.stroke(context, u.line((bead.0 + dx, bead.1 - 0.022 * (1 - dissolve)), (bead.0 + dx, bead.1 + 0.022 * (1 - dissolve))), ivory, 0.006)
                }
            }
            if lyse < 1 { u.stroke(context, u.circle(x + 0.035, 0.53, 0.03 * form), tint, 0.02) }
            for m in 0..<4 {
                let a = Double(m) * .pi / 2 + 0.5
                let spot = (x + 0.02 + 0.05 * cos(a) * lyse, 0.51 + 0.045 * sin(a) * lyse)
                if lyse > 0 {
                    let strand = stride(from: 0.0, through: 1.0, by: 0.2).map { s in (spot.0 - 0.015 + 0.03 * s, spot.1 + 0.006 * sin(s * 9)) }
                    u.stroke(context, u.polyline(strand), tint.opacity(lyse), 0.012)
                }
                if dissolve > 0 {
                    let from = (x - 0.035, 0.48), to = (spot.0 + 0.015, spot.1)
                    let p = (from.0 + (to.0 - from.0) * tag + 0.03 * cos(a + 1) * dissolve * (1 - tag),
                             from.1 + (to.1 - from.1) * tag + 0.03 * sin(a + 1) * dissolve * (1 - tag))
                    context.fill(u.circle(p.0, p.1, 0.009), with: .color(clay))
                }
            }
        }
        // The channels: the aqueous stream in from the left, oil from above
        // and below, and the wide outlet.
        u.stroke(context, u.line((0.0, 0.46), (0.29, 0.46), (0.29, 0.0)), tint, 0.035)
        u.stroke(context, u.line((0.0, 0.54), (0.29, 0.54), (0.29, 1.0)), tint, 0.035)
        u.stroke(context, u.line((0.35, 0.0), (0.35, 0.38), (1.0, 0.38)), tint, 0.035)
        u.stroke(context, u.line((0.35, 1.0), (0.35, 0.62), (1.0, 0.62)), tint, 0.035)
        let next = (t - 0.3).truncatingRemainder(dividingBy: every) / every
        context.fill(u.circle(0.06 + 0.22 * next, 0.5, 0.02), with: .color(clay))
        u.stroke(context, u.circle(0.02 + 0.22 * next, 0.5, 0.018), tint, 0.015)
    }
}
