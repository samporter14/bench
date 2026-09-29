// DNARepairScenes.swift
// ScienceStatus — DNA repair, replication, joining and assembly. Each draws
// in a unit square (see `UnitSquare`): strands and enzymes in the tint,
// the lesion, the new DNA or the insert in clay.

import SwiftUI

/// A duplex drawn as two strands with rungs between, with gaps in either
/// strand where asked.
enum Duplex2 {
    static func draw(_ context: GraphicsContext, _ u: UnitSquare, from x0: Double, to x1: Double, top: Double = 0.44, bottom: Double = 0.56,
                     topGaps: [(Double, Double)] = [], skipRungs: [Double] = [], tint: Color) {
        var x = x0
        while x <= x1 {
            if !skipRungs.contains(where: { abs($0 - x) < 0.012 }) {
                u.stroke(context, u.line((x, top + 0.015), (x, bottom - 0.015)), tint.opacity(0.4), 0.014)
            }
            x += 0.04
        }
        var pieces: [(Double, Double)] = [(x0 - 0.02, x1 + 0.02)]
        for gap in topGaps {
            pieces = pieces.flatMap { p -> [(Double, Double)] in
                guard gap.0 > p.0, gap.1 < p.1 else { return [p] }
                return [(p.0, gap.0), (gap.1, p.1)]
            }
        }
        for p in pieces { u.stroke(context, u.line((p.0, top), (p.1, top)), tint, 0.03) }
        u.stroke(context, u.line((x0 - 0.02, bottom), (x1 + 0.02, bottom)), tint, 0.03)
    }
}

/// Base-excision repair: a glycosylase finds the clay damaged base, flips
/// it out and cuts it away; the backbone is nicked, a new base is put in,
/// and the nick is sealed.
enum BaseExcision {
    static let duration = 4.8
    private static let site = 0.5

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let nicked = t > 1.9 && t < 3.3 ? Ease.clamp((t - 1.9) / 0.3) * (1 - Ease.clamp((t - 3.1) / 0.2)) : 0
        Duplex2.draw(scene, u, from: 0.06, to: 0.94, topGaps: nicked > 0 ? [(site - 0.02 * nicked, site + 0.02 * nicked)] : [], skipRungs: [site], tint: tint)
        u.stroke(scene, u.line((site, 0.54), (site, 0.5)), tint.opacity(0.4), 0.014)
        // The damaged base: flipped out, then cut free.
        let flip = Ease.inOut((t - 1.0) / 0.4)
        let free = Ease.inOut((t - 1.4) / 0.5)
        if free < 1 {
            let a = (90 - 180 * flip) * .pi / 180
            let tip = (site + 0.05 * cos(a) * 0.3 + 0.2 * free, 0.455 + 0.045 * sin(a) - 0.25 * free)
            u.stroke(scene, u.line((site + 0.2 * free, 0.445 - 0.25 * free), tip), clay.opacity(1 - free), 0.045)
            scene.fill(u.circle(tip.0, tip.1, 0.025), with: .color(clay.opacity(1 - free)))
        }
        // The new base, put in by polymerase.
        let fill = Ease.inOut((t - 2.4) / 0.5)
        if fill > 0 { u.stroke(scene, u.line((site, 0.455), (site, 0.455 + 0.045 * fill)), tint, 0.03) }
        let enzymes: [(from: Double, to: Double, size: Double)] = [(0.2, 1.8, 0.14), (1.9, 2.3, 0.1), (2.4, 3.0, 0.14), (3.0, 3.6, 0.1)]
        for e in enzymes {
            let come = Ease.inOut((t - e.from) / 0.3), go = Ease.inOut((t - e.to + 0.2) / 0.2)
            guard come > 0, go < 1 else { continue }
            let x = site - 0.4 * (1 - come) + 0.4 * go
            scene.fill(u.ellipse(x, 0.34, e.size, e.size * 0.8), with: .color(tint.opacity(0.85)))
        }
        let sealed = Ease.clamp((t - 3.2) / 0.2) * (1 - Ease.clamp((t - 3.5) / 0.3))
        if sealed > 0 { scene.fill(Sparkles.star(u, site, 0.44, 0.05 * sealed), with: .color(clay)) }
    }
}

/// Nucleotide-excision repair: a clay lesion kinks the helix; the helix is
/// opened round it, cut on both sides, and the stretch holding it lifts
/// away; the gap is filled in and the bubble closes.
enum NucleotideExcision {
    static let duration = 4.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.3) / 0.4)
        var scene = context
        scene.opacity = 1 - fade
        let open = Ease.inOut((t - 0.6) / 0.5) * (1 - Ease.inOut((t - 3.4) / 0.5))
        let lift = Ease.inOut((t - 1.6) / 0.6)
        let refill = Ease.inOut((t - 2.4) / 0.9)
        let bulge = { (x: Double) -> Double in 0.1 * open * max(0, cos((x - 0.5) / 0.14 * .pi / 2)) * (abs(x - 0.5) < 0.14 ? 1 : 0) }
        // The bottom strand, the template, straight throughout.
        u.stroke(scene, u.line((0.04, 0.56), (0.96, 0.56)), tint, 0.03)
        var x = 0.06
        while x <= 0.94 {
            if abs(x - 0.5) > 0.14 || open < 0.1 { u.stroke(scene, u.line((x, 0.455 - bulge(x)), (x, 0.545)), tint.opacity(0.4), 0.014) }
            x += 0.04
        }
        // The top strand: bowed open, the patch lifted out and filled back.
        let left = stride(from: 0.04, through: 0.4, by: 0.01).map { x in (x, 0.44 - bulge(x)) }
        let right = stride(from: 0.6, through: 0.96, by: 0.01).map { x in (x, 0.44 - bulge(x)) }
        u.stroke(scene, u.polyline(left), tint, 0.03)
        u.stroke(scene, u.polyline(right), tint, 0.03)
        if lift < 1 {
            let patch = stride(from: 0.4, through: 0.6, by: 0.01).map { x in (x, 0.44 - bulge(x) - 0.3 * lift) }
            u.stroke(scene, u.polyline(patch), tint.opacity(1 - lift), 0.03)
            scene.fill(u.capsule(0.5, 0.44 - bulge(0.5) - 0.3 * lift + 0.02, 0.07, 0.035, corner: 0.012), with: .color(clay.opacity(1 - lift)))
        }
        if refill > 0 {
            let patch = stride(from: 0.4, through: 0.4 + 0.2 * refill, by: 0.01).map { x in (x, 0.44 - bulge(x)) }
            if patch.count > 1 { u.stroke(scene, u.polyline(patch), clay.opacity(0.9), 0.03) }
        }
        for (k, at) in [(0, 1.3), (1, 1.45)] {
            let cut = sin(.pi * Ease.clamp((t - at) / 0.3))
            if cut > 0 { scene.fill(Sparkles.star(u, k == 0 ? 0.4 : 0.6, 0.44 - bulge(k == 0 ? 0.4 : 0.6), 0.05 * cut), with: .color(clay)) }
        }
    }
}

/// Non-homologous end joining: the duplex breaks clean through; Ku rings
/// slide onto both ends, hold them together, and they are joined, leaving
/// a small clay scar.
enum NHEJ {
    static let duration = 4.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.2) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let apart = Keyframes.value(t, [(0.3, 0), (0.7, 0.1), (1.7, 0.1), (2.2, 0)])
        let joined = Ease.clamp((t - 2.4) / 0.4)
        for side in [-1.0, 1.0] {
            let inner = 0.5 + side * (0.012 + apart) * (1 - joined)
            let outer = side < 0 ? 0.04 : 0.96
            Duplex2.draw(scene, u, from: min(inner, outer) + (side < 0 ? 0 : 0.02), to: max(inner, outer) - (side < 0 ? 0.02 : 0), tint: tint)
            let ku = Ease.out((t - 0.9 - (side > 0 ? 0.15 : 0)) / 0.45) * (1 - Ease.inOut((t - 3.0) / 0.5))
            if ku > 0 {
                let x = inner - side * 0.04 + side * 0.25 * (1 - ku) + side * 0.3 * Ease.inOut((t - 3.0) / 0.5)
                u.stroke(scene, u.ellipse(x, 0.5, 0.06, 0.22), tint.opacity(min(1, ku * 2)), 0.035)
            }
        }
        let snap = sin(.pi * Ease.clamp((t - 0.25) / 0.3))
        if snap > 0 { scene.fill(Sparkles.star(u, 0.5, 0.5, 0.06 * snap), with: .color(clay)) }
        if joined > 0 { scene.fill(u.capsule(0.5, 0.5, 0.02, 0.1, corner: 0.01), with: .color(clay.opacity(joined))) }
    }
}

/// A replication fork: the helicase opens the parent duplex; clay new DNA
/// runs on continuously along one template, and in Okazaki fragments, each
/// begun on a primer, along the other.
enum ReplicationFork {
    static let duration = 5.0

    private static func fork(_ t: Double) -> Double { 0.45 + 0.34 * Ease.clamp(t / duration) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let x = fork(t)
        Duplex2.draw(context, u, from: x + 0.02, to: 1.0, top: 0.47, bottom: 0.53, tint: tint)
        u.stroke(context, u.line((0.0, 0.33), (x - 0.1, 0.33), (x, 0.47)), tint, 0.03)
        u.stroke(context, u.line((0.0, 0.67), (x - 0.1, 0.67), (x, 0.53)), tint, 0.03)
        // The leading strand: continuous, right up to the fork.
        u.stroke(context, u.line((0.0, 0.715), (x - 0.12, 0.715)), clay, 0.03)
        context.fill(u.ellipse(x - 0.12, 0.7, 0.1, 0.08), with: .color(tint.opacity(0.85)))
        // The lagging strand: fragments, each begun near the fork on a
        // primer and extended back towards the one before.
        var starts: [Double] = []
        var s = 0.3
        while s < t { starts.append(s); s += 0.95 }
        for (k, begun) in starts.enumerated() {
            let from = fork(begun) - 0.12
            let stop = k == 0 ? 0.0 : fork(starts[k - 1]) - 0.12
            let grown = Ease.clamp((t - begun) / 0.8)
            let end = from - (from - stop) * grown
            context.fill(u.capsule(from, 0.285, 0.035, 0.022, corner: 0.006), with: .color(tint))
            if grown > 0 { u.stroke(context, u.line((from - 0.02, 0.285), (end, 0.285)), clay, 0.03) }
            if k == starts.count - 1 && grown < 1 { context.fill(u.ellipse(end, 0.27, 0.09, 0.07), with: .color(tint.opacity(0.85))) }
        }
        u.stroke(context, u.ellipse(x + 0.01, 0.5, 0.05, 0.14), clay, 0.03)
    }
}

/// DNA ligase: the enzyme closes round a nick, takes up a clay ATP, and
/// seals the backbone; AMP and pyrophosphate come off and it lets go.
enum Ligase {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let sealed = Ease.clamp((t - 2.3) / 0.3)
        Duplex2.draw(context, u, from: 0.06, to: 0.94, topGaps: sealed < 1 ? [(0.49 + 0.01 * sealed, 0.51 - 0.01 * sealed)] : [], tint: tint)
        let clamp = Keyframes.value(t, [(0.3, 0), (0.9, 1), (3.0, 1), (3.6, 0)])
        let away = Ease.inOut((t - 3.4) / 0.6)
        if clamp > 0 || away < 1 {
            var arc = Path()
            let gap = 70 * (1 - clamp)
            arc.addArc(center: u.pt(0.5, 0.5 - 0.4 * away), radius: u.len(0.15), startAngle: .degrees(-90 + gap), endAngle: .degrees(270 - gap), clockwise: false)
            u.stroke(context, arc, tint.opacity(min(1, clamp * 2) * (1 - away)), 0.05)
        }
        let atp = Keyframes.value(t, [(0.9, 0), (1.5, 1), (2.1, 2)])
        if t > 0.9 && t < 2.4 {
            let p: (Double, Double) = atp < 1 ? (0.8 - 0.3 * atp, 0.14 + 0.2 * atp) : (0.5, 0.34 + 0.1 * (atp - 1))
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(clay))
        }
        for (k, dir) in [(0, -1.0), (1, 1.0)] {
            let off = Ease.out((t - 2.4 - 0.1 * Double(k)) / 0.8)
            guard off > 0, off < 1 else { continue }
            context.fill(u.circle(0.5 + 0.3 * dir * off, 0.42 - 0.3 * off, 0.014), with: .color(clay.opacity(1 - off)))
        }
        let flash = sin(.pi * Ease.clamp((t - 2.3) / 0.35))
        if flash > 0 { context.fill(Sparkles.star(u, 0.5, 0.44, 0.05 * flash), with: .color(clay)) }
    }
}

/// HiFi assembly: the linearised vector and a clay insert have their ends
/// chewed back, the overlaps find each other, the insert drops into place,
/// and the gaps are filled and sealed into a closed plasmid.
enum GibsonAssembly {
    static let duration = 4.8
    private static let centre = (0.5, 0.56), outer = 0.28, inner = 0.245
    private static let gapFrom = 245.0, gapTo = 295.0

    private static func arc(_ radius: Double, _ from: Double, _ to: Double) -> [(Double, Double)] {
        stride(from: from, through: to, by: 3).map { d in
            let a = d * .pi / 180
            return (centre.0 + radius * cos(a), centre.1 + radius * sin(a))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = Ease.inOut((t - 4.35) / 0.35)
        var scene = context
        scene.opacity = 1 - fade
        let chew = Ease.inOut((t - 0.4) / 0.5) * (1 - Ease.inOut((t - 2.4) / 0.6))
        let place = Ease.inOut((t - 1.1) / 0.9)
        let sealed = Ease.clamp((t - 3.0) / 0.2)
        // The vector: both strands, the inner one chewed back at the ends.
        u.stroke(scene, u.polyline(arc(outer, gapTo - 360, gapFrom)), tint, 0.03)
        u.stroke(scene, u.polyline(arc(inner, gapTo - 360 + 12 * chew, gapFrom - 12 * chew)), tint, 0.03)
        // The insert: straight and floating, then bent into the gap.
        let steps = 17
        let outerPath = (0..<steps).map { i -> (Double, Double) in
            let s = Double(i) / Double(steps - 1)
            let straight = (0.34 + 0.32 * s, 0.1)
            let a = (gapFrom - 8 + (gapTo - gapFrom + 16) * s) * .pi / 180
            let bent = (centre.0 + outer * cos(a), centre.1 + outer * sin(a))
            return (straight.0 + (bent.0 - straight.0) * place, straight.1 + (bent.1 - straight.1) * place)
        }
        let innerPath = (0..<steps).compactMap { i -> (Double, Double)? in
            let s = Double(i) / Double(steps - 1)
            guard s > 0.15 * chew, s < 1 - 0.15 * chew else { return nil }
            let straight = (0.34 + 0.32 * s, 0.14)
            let a = (gapFrom - 8 + (gapTo - gapFrom + 16) * s) * .pi / 180
            let bent = (centre.0 + inner * cos(a), centre.1 + inner * sin(a))
            return (straight.0 + (bent.0 - straight.0) * place, straight.1 + (bent.1 - straight.1) * place)
        }
        u.stroke(scene, u.polyline(outerPath), clay, 0.03)
        if innerPath.count > 1 { u.stroke(scene, u.polyline(innerPath), clay, 0.03) }
        if sealed > 0 {
            let glow = sin(.pi * Ease.clamp((t - 3.0) / 0.6))
            scene.fill(Sparkles.star(u, 0.5, 0.2, 0.06 * glow), with: .color(clay))
            u.stroke(scene, u.circle(centre.0, centre.1, 0.2), tint.opacity(0.3 * glow), 0.02)
        }
    }
}
