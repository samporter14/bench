// BatchLChemistryScenes.swift
// ScienceStatus — chemistry at the bench: a separatory funnel draining its lower layer,
// a Büchner funnel under vacuum, a flame test, a precipitate settling, and a
// row of indicator tubes from acid to base.
// Each draws in a unit square (see `UnitSquare`): glassware and kit in the tint,
// the liquid, product or colour the scene is about in clay.

import SwiftUI

/// Odds and ends the glassware in this file shares.
private enum ChemGlass {
    /// A point turned about `pivot` by `angle` radians, clockwise on screen.
    static func turn(_ p: (Double, Double), about pivot: (Double, Double), by angle: Double) -> (Double, Double) {
        let c = cos(angle), s = sin(angle)
        let dx = p.0 - pivot.0, dy = p.1 - pivot.1
        return (pivot.0 + dx * c - dy * s, pivot.1 + dx * s + dy * c)
    }

    static func turnAll(_ points: [(Double, Double)], about pivot: (Double, Double), by angle: Double) -> [(Double, Double)] {
        points.map { turn($0, about: pivot, by: angle) }
    }

    /// A round bottom: the half circle from the left side round to the right.
    static func roundBottom(x: Double, y: Double, r: Double, steps: Int = 8) -> [(Double, Double)] {
        (0...steps).map { i in
            let a = Double.pi * (1 - Double(i) / Double(steps))
            return (x + r * cos(a), y + r * sin(a))
        }
    }

    /// The closed shape through `points`, for filling.
    static func polygon(_ u: UnitSquare, _ points: [(Double, Double)]) -> Path {
        var path = u.polyline(points)
        path.closeSubpath()
        return path
    }
}

/// A separatory funnel on its ring over a beaker, two layers in it, the
/// lower one clay. It is rocked a moment and the layers mix, clay blobs
/// hanging in the upper one; they sink out and settle. Then the stopcock
/// turns, the clay runs off in a thin stream while the beaker fills, and the
/// tap shuts as the interface reaches the stem.
enum SeparatoryFunnel {
    static let duration = 5.0
    private static let pivot = (0.5, 0.535)
    private static let left: [(Double, Double)] = Smooth.curve(
        [(0.455, 0.15), (0.455, 0.2), (0.36, 0.27), (0.27, 0.36), (0.285, 0.45), (0.39, 0.56), (0.465, 0.635)], samples: 6)
    /// The pear: down its left side, up its right.
    private static let pear: [(Double, Double)] = left + left.reversed().map { (1 - $0.0, $0.1) }
    private static let stopper: [(Double, Double)] = [(0.43, 0.085), (0.57, 0.085), (0.545, 0.16), (0.455, 0.16)]
    private static let barrel: [(Double, Double)] = [(0.455, 0.655), (0.545, 0.655), (0.545, 0.725), (0.455, 0.725)]
    private static let stem: [(Double, Double)] = [(0.5, 0.63), (0.5, 0.815)]
    private static let beaker: [(Double, Double)] = [(0.33, 0.76), (0.34, 0.95), (0.66, 0.95), (0.67, 0.76)]
    private static let blobs: [(x: Double, y: Double, r: Double)] = [
        (0.4, 0.33, 0.034), (0.56, 0.31, 0.03), (0.49, 0.4, 0.036), (0.62, 0.4, 0.03), (0.37, 0.42, 0.03),
        (0.53, 0.35, 0.026), (0.45, 0.3, 0.026),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rocking = Ease.clamp((t - 0.3) / 0.9)
        let rock: Double = 7 * sin(.pi * rocking) * sin(4 * .pi * rocking) * .pi / 180
        let drain = Ease.inOut((t - 2.6) / 1.55)
        let open = Ease.inOut((t - 2.45) / 0.25) - Ease.inOut((t - 4.05) / 0.25)
        let back = Ease.inOut((t - 4.5) / 0.5)
        let level = 0.95 - 0.09 * drain

        // Blobs of the lower layer lift into the upper one while it is rocked,
        // then sink back and are taken up again.
        var mixed = 0.0
        var live: [(x: Double, y: Double, r: Double)] = []
        for (k, b) in blobs.enumerated() {
            let s = Double(k)
            let up = Ease.inOut((t - 0.35 - 0.04 * s) / 0.3)
            let down = Ease.inOut((t - 1.3 - 0.05 * s) / 0.6)
            let p = up - down
            mixed += p / Double(blobs.count)
            guard p > 0.02 else { continue }
            let sway = 0.012 * p * sin(2 * .pi * (t * 1.8 + 0.37 * s))
            live.append((b.x + sway, 0.47 + (b.y - 0.47) * p, b.r * min(1, 2 * p)))
        }
        let surface = 0.27 + 0.07 * drain * (1 - back)
        let clayTop = back > 0 ? 0.47 : 0.47 + 0.15 * drain + 0.05 * mixed
        let clayAlpha = back > 0 ? back : 1.0

        // The ring the funnel hangs in, either side of the glass.
        u.stroke(context, u.line((0.1, 0.535), (0.4, 0.535)), tint.opacity(0.7), 0.04)
        u.stroke(context, u.line((0.6, 0.535), (0.9, 0.535)), tint.opacity(0.7), 0.04)

        // The beaker, taking the clay.
        let cup = u.polyline(beaker)
        if drain > 0 { BenchShapes.fill(context, u, cup, from: level, clay.opacity(1 - back)) }
        u.stroke(context, cup, tint, 0.05)

        // The stream, from the stem's tip down to the beaker's surface.
        let head = Ease.clamp((t - 2.55) / 0.12), tail = Ease.clamp((t - 4.15) / 0.12)
        if head > 0, tail < 1 {
            let from = 0.815 + (level - 0.815) * tail, to = 0.815 + (level - 0.815) * head
            u.stroke(context, u.line((0.5, from), (0.5, to)), clay, 0.04)
        }

        // The funnel, rocking on the ring: the liquids keep their own level.
        let glass = ChemGlass.turnAll(pear, about: pivot, by: rock)
        let body = ChemGlass.polygon(u, glass)
        BenchShapes.fill(context, u, body, from: surface, tint.opacity(0.22))
        BenchShapes.fill(context, u, body, from: clayTop, clay.opacity(clayAlpha))
        var inside = context
        inside.clip(to: body)
        for b in live { inside.fill(u.circle(b.x, b.y, b.r), with: .color(clay)) }
        u.stroke(context, u.polyline(glass), tint, 0.05)
        context.fill(ChemGlass.polygon(u, ChemGlass.turnAll(stopper, about: pivot, by: rock)), with: .color(tint))
        u.stroke(context, u.polyline(ChemGlass.turnAll(stem, about: pivot, by: rock)), tint, 0.045)

        // The stopcock: a bar across the stem, turned end-on when it is open.
        let half = 0.02 + 0.075 * abs(cos(.pi / 2 * open))
        context.fill(ChemGlass.polygon(u, ChemGlass.turnAll(barrel, about: pivot, by: rock)), with: .color(tint))
        let bar = ChemGlass.turnAll([(0.5 - half, 0.69), (0.5 + half, 0.69)], about: pivot, by: rock)
        u.stroke(context, u.polyline(bar), tint, 0.05)
    }
}

/// A Büchner funnel on its side-arm flask: a beaker tips over it and pours a
/// slurry, clay specks in a faint liquid. The vacuum pulls the liquid through
/// the perforated plate, drop after drop into the flask, and the specks are
/// left behind as a clay cake that thickens on the paper.
enum BuchnerFunnel {
    static let duration = 4.8
    private static let axis = 0.52, rim = 0.31, plate = 0.505
    /// The pouring beaker's lip, where it rests and where it pours from; the
    /// beaker is drawn upright from the lip, then turned about it.
    private static let rest = (0.27, 0.06), pour = (0.38, 0.17)
    private static let tipped = 52.0
    private static let jar: [(Double, Double)] = [(-0.18, 0), (-0.18, 0.18), (0, 0.18), (0, 0)]
    /// The slurry's specks: spread through the standing beaker, and where they
    /// gather at the lip's side of the floor once it is tipped.
    private static let jarSpecks: [(from: (Double, Double), to: (Double, Double))] = [
        ((-0.14, 0.14), (-0.06, 0.17)), ((-0.08, 0.15), (-0.03, 0.165)), ((-0.04, 0.12), (-0.045, 0.14)),
        ((-0.12, 0.09), (-0.02, 0.13)), ((-0.06, 0.08), (-0.07, 0.15)), ((-0.15, 0.11), (-0.035, 0.115)),
    ]
    private static let cup: [(Double, Double)] = [(0.26, rim), (0.31, 0.5), (0.73, 0.5), (0.78, rim)]
    private static let flask: [(Double, Double)] = [
        (0.445, 0.62), (0.445, 0.7), (0.25, 0.93), (0.27, 0.96), (0.77, 0.96), (0.79, 0.93), (0.595, 0.7), (0.595, 0.62),
    ]
    private static let holes: [Double] = (0..<6).map { 0.345 + 0.07 * Double($0) }
    /// Specks hung in the slurry: across the cup, and how far down the liquid.
    private static let specks: [(x: Double, f: Double)] = [
        (-0.16, 0.2), (-0.1, 0.65), (-0.04, 0.35), (0.03, 0.85), (0.09, 0.15), (0.15, 0.55), (-0.13, 0.92), (0.12, 0.8), (0.0, 0.5), (-0.07, 0.05),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let back = Ease.inOut((t - 4.3) / 0.5)
        let poured = Ease.inOut((t - 0.7) / 1.3)
        let drawn = Ease.inOut((t - 1.3) / 2.5)
        let lean = Ease.inOut((t - 0.25) / 0.65) - Ease.inOut((t - 1.95) / 0.55)
        let tilt = tipped * lean * Double.pi / 180
        let lip = (rest.0 + (pour.0 - rest.0) * lean, rest.1 + (pour.1 - rest.1) * lean)
        let cake = 0.06 * drawn * (1 - back)
        let cakeTop = plate - 0.02 - cake
        let held = poured - drawn
        let surface = cakeTop - 0.16 * held
        let filtrate = 0.94 - 0.13 * drawn

        // The flask: its side arm, the hose that leaves it, and the filtrate.
        let flaskPath = u.polyline(flask)
        BenchShapes.fill(context, u, flaskPath, from: filtrate, tint.opacity(0.45 * (1 - back)))
        u.stroke(context, flaskPath, tint, 0.05)
        u.stroke(context, u.line((0.595, 0.665), (0.72, 0.665)), tint, 0.045)
        let hose = u.line((0.72, 0.665), (0.92, 0.665), (0.95, 0.52))
        u.stroke(context, hose, tint.opacity(0.6), 0.05)
        let pump = Ease.clamp((t - 1.0) / 0.2) * (1 - Ease.clamp((t - 3.7) / 0.3))
        if pump > 0 {
            let period = u.len(0.09)
            context.stroke(hose, with: .color(tint.opacity(pump)),
                           style: StrokeStyle(lineWidth: max(u.len(0.03), UnitSquare.hairline), lineCap: .round,
                                              dash: [u.len(0.02), u.len(0.07)], dashPhase: -period * 5 * t / duration))
        }

        // Drops leave the stem, fall to the filtrate and join it.
        if drawn > 0.02, drawn < 0.98 {
            for k in 0..<2 {
                let phase = (t * 3.4 + 0.5 * Double(k)).truncatingRemainder(dividingBy: 1)
                let y = 0.64 + (filtrate - 0.03 - 0.64) * phase * phase
                context.fill(u.circle(axis, y, 0.02), with: .color(tint.opacity(0.85)))
            }
        }

        // The funnel: slurry, specks and cake inside it, the plate of holes under.
        let slurry = ChemGlass.polygon(u, cup)
        if held > 0.01 {
            BenchShapes.fill(context, u, slurry, from: surface, tint.opacity(0.3))
            let gate = min(1, held * 6)
            for s in specks {
                context.fill(u.circle(axis + s.x, surface + s.f * (cakeTop - surface), 0.017 * gate), with: .color(clay))
            }
        }
        if cake > 0 {
            context.fill(u.capsule(axis, cakeTop + cake / 2, 0.4, cake, corner: min(cake / 2, 0.025)), with: .color(clay))
        }
        u.stroke(context, u.line((0.26, rim), (0.31, 0.5)), tint, 0.05)
        u.stroke(context, u.line((0.78, rim), (0.73, 0.5)), tint, 0.05)
        for x in holes { context.fill(u.circle(x, plate, 0.024), with: .color(tint)) }
        u.stroke(context, u.line((axis - 0.035, 0.53), (axis - 0.035, 0.6)), tint, 0.04)
        u.stroke(context, u.line((axis + 0.035, 0.53), (axis + 0.035, 0.6)), tint, 0.04)
        context.fill(u.capsule(axis, 0.6, 0.2, 0.05, corner: 0.02), with: .color(tint))

        // The beaker, pivoting on its lip; its slurry keeps a level surface.
        let world = ChemGlass.turnAll(jar, about: (0, 0), by: tilt).map { (lip.0 + $0.0, lip.1 + $0.1) }
        let jarPath = u.polyline(world)
        let liquidAt = lip.1 + (back > 0 ? 0.04 : 0.04 + 0.08 * poured)
        let liquid = back > 0 ? back : 1 - Ease.clamp((poured - 0.85) / 0.1)
        if liquid > 0.01 {
            var inside = context
            inside.clip(to: ChemGlass.polygon(u, world))
            inside.clip(to: Path(CGRect(x: u.origin.x - u.side, y: u.pt(0, liquidAt).y, width: 3 * u.side, height: 2 * u.side)))
            inside.fill(ChemGlass.polygon(u, world), with: .color(tint.opacity(0.3 * liquid)))
            for s in jarSpecks {
                let there = (s.from.0 + (s.to.0 - s.from.0) * lean, s.from.1 + (s.to.1 - s.from.1) * lean)
                let p = ChemGlass.turn(there, about: (0, 0), by: tilt)
                inside.fill(u.circle(lip.0 + p.0, lip.1 + p.1, 0.02), with: .color(clay.opacity(liquid)))
            }
        }
        u.stroke(context, jarPath, tint, 0.05)

        // The pour: from the lip down to the slurry, specks running in it.
        let head = Ease.clamp((t - 0.62) / 0.16), tail = Ease.clamp((t - 1.95) / 0.16)
        if head > tail {
            let fall = max(surface, 0.34) - lip.1
            func along(_ s: Double) -> (Double, Double) { (lip.0 + 0.03 + 0.05 * s * s, lip.1 + fall * s) }
            let jet = stride(from: tail, through: head, by: 0.1).map(along)
            u.stroke(context, u.polyline(jet), tint.opacity(0.5), 0.03)
            for k in 0..<3 {
                let s = (t * 2.2 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                guard s >= tail, s <= head else { continue }
                let p = along(s)
                context.fill(u.circle(p.0, p.1, 0.017), with: .color(clay))
            }
        }
    }
}

/// A flame test: a burner's flame, an outline in the tint with a cone inside.
/// A wire loop on its handle dips in the sample, picks up a bead, and is
/// carried into the flame, which flares clay while the bead burns; the loop
/// draws back and the flame goes back to its outline.
enum FlameTest {
    static let duration = 4.0
    private static let axis = 0.66, foot = 0.645
    private static let hover = (0.24, 0.62), well = (0.24, 0.83), flame = (0.63, 0.4)
    private static let reach = 0.5

    /// A flame of `height` and `width` standing on `foot`, its tip leaning.
    private static func teardrop(_ u: UnitSquare, height h: Double, width w: Double, lean: Double) -> Path {
        var path = Path()
        path.move(to: u.pt(axis + lean, foot - h))
        path.addQuadCurve(to: u.pt(axis + w, foot - w), control: u.pt(axis + w, foot - h * 0.55))
        path.addArc(center: u.pt(axis, foot - w), radius: u.len(w), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(to: u.pt(axis + lean, foot - h), control: u.pt(axis - w, foot - h * 0.55))
        path.closeSubpath()
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let cycle = 2 * Double.pi * t / duration

        // The loop: down into the sample, over to the flame, held, and back.
        let dip = Ease.inOut((t - 0.15) / 0.35)
        let carry = Ease.inOut((t - 0.8) / 1.0)
        let away = Ease.inOut((t - 2.8) / 0.9)
        let inFlame = carry - away
        let tipX: Double = hover.0 + (well.0 - hover.0) * dip + (flame.0 - well.0) * carry
            + (hover.0 - flame.0) * away + 0.008 * inFlame * sin(11 * cycle)
        var tipY: Double = hover.1 + (well.1 - hover.1) * dip + (flame.1 - well.1) * carry + (hover.1 - flame.1) * away
        tipY -= 0.14 * sin(.pi * carry) + 0.06 * sin(.pi * away)
        let flare = Ease.inOut((t - 1.45) / 0.25) - Ease.inOut((t - 2.7) / 0.35)
        let bead = Ease.inOut((t - 0.45) / 0.2) - Ease.inOut((t - 2.2) / 0.5)

        // The burner.
        context.fill(u.capsule(axis, 0.93, 0.3, 0.06, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(axis, 0.79, 0.09, 0.22, corner: 0.03), with: .color(tint))
        context.fill(u.capsule(axis, 0.77, 0.16, 0.05, corner: 0.02), with: .color(tint))

        // The flame: an outline with a cone inside, flickering; clay when flared.
        let flick: Double = 0.018 * sin(9 * cycle) + 0.01 * sin(23 * cycle + 1.3)
        let sway: Double = 0.02 * sin(7 * cycle) + 0.008 * sin(17 * cycle + 0.5)
        let h = 0.5 + 0.08 * flare + flick
        let w = 0.1 + 0.025 * flare
        let outer = teardrop(u, height: h, width: w, lean: sway)
        let inner = teardrop(u, height: 0.5 * h, width: 0.45 * w, lean: 0.5 * sway)
        if flare > 0 {
            context.fill(outer, with: .color(clay.opacity(flare)))
            context.fill(inner, with: .color(ivory.opacity(0.85 * flare)))
        }
        if flare < 1 {
            if flare > 0 { u.stroke(context, outer, clay.opacity(flare), 0.045) }
            u.stroke(context, outer, tint.opacity(1 - flare), 0.045)
            u.stroke(context, inner, tint.opacity(1 - flare), 0.035)
        }

        // The sample well and its powder.
        var powder = Path()
        powder.move(to: u.pt(0.14, 0.915))
        powder.addQuadCurve(to: u.pt(0.34, 0.915), control: u.pt(0.24, 0.79))
        context.fill(powder, with: .color(clay))
        u.stroke(context, u.line((0.09, 0.82), (0.12, 0.93), (0.36, 0.93), (0.39, 0.82)), tint, 0.05)

        // The loop and its handle, over the flame, turning up from the well.
        let angle = (66 - 48 * inFlame) * Double.pi / 180
        let toHand = (-cos(angle), -sin(angle))
        func onRod(_ d: Double) -> (Double, Double) { (tipX + toHand.0 * d, tipY + toHand.1 * d) }
        u.stroke(context, u.line(onRod(0.05), onRod(0.3)), tint, 0.03)
        u.stroke(context, u.line(onRod(0.3), onRod(reach)), tint, 0.075)
        if bead > 0 { context.fill(u.circle(tipX, tipY, 0.042 * bead), with: .color(clay)) }
        u.stroke(context, u.circle(tipX, tipY, 0.05), tint, 0.035)
    }
}

/// A precipitate: three drops of reagent fall into a test tube of clear
/// solution. Each lands and a cloud of fine clay particles blooms out of it,
/// swirls a little and drifts down to add to the layer at the bottom, which
/// grows with every drop. The precipitate fades and the tube resets.
enum Precipitate {
    static let duration = 4.4
    private static let surface = 0.5, bottom = 0.93, thickness = 0.07
    private static let lands = [0.7, 1.55, 2.4]
    private static let tube: [(Double, Double)] = [(0.34, 0.36), (0.34, 0.77)] + ChemGlass.roundBottom(x: 0.5, y: 0.77, r: 0.16) + [(0.66, 0.36)]

    private struct Speck {
        let dx: Double, dy: Double, delay: Double, phase: Double, size: Double
    }

    private static func cloud(_ j: Int) -> [Speck] {
        (0..<8).map { k in
            let s = Double(j * 8 + k)
            return Speck(dx: (BenchShapes.rand(s * 3.7 + 1) - 0.5) * 0.22, dy: 0.02 + 0.06 * BenchShapes.rand(s * 5.3 + 2),
                         delay: 0.4 * BenchShapes.rand(s * 7.1 + 3), phase: 6.28 * BenchShapes.rand(s * 2.9 + 4),
                         size: 0.017 + 0.009 * BenchShapes.rand(s * 4.1 + 5))
        }
    }
    private static let clouds: [[Speck]] = (0..<3).map { cloud($0) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fade = 1 - Ease.inOut((t - 3.85) / 0.5)

        // The dropper's bulb is squeezed as each drop forms.
        var press = 0.0
        for land in lands { press += Ease.inOut((t - land + 0.6) / 0.1) - Ease.inOut((t - land + 0.42) / 0.15) }
        let squeeze = 0.13 - 0.035 * press
        context.fill(u.capsule(0.5, 0.02 + squeeze / 2, 0.11 + 0.015 * press, squeeze, corner: 0.05), with: .color(tint))
        u.stroke(context, u.line((0.465, 0.15), (0.465, 0.24), (0.492, 0.33)), tint, 0.04)
        u.stroke(context, u.line((0.535, 0.15), (0.535, 0.24), (0.508, 0.33)), tint, 0.04)

        // The drops: growing at the tip, then falling to the surface.
        for land in lands {
            let form = Ease.clamp((t - (land - 0.55)) / 0.23)
            let fall = (t - (land - 0.32)) / 0.32
            guard form > 0, fall < 1 else { continue }
            let y = fall <= 0 ? 0.345 : 0.345 + (surface - 0.345) * fall * fall
            context.fill(u.circle(0.5, y, 0.035 * form), with: .color(tint))
        }

        // The clouds: each speck spreads out, swirls, then sinks to its
        // drop's share of the layer and is absorbed into it.
        var layer = 0.0
        var drifting: [(Double, Double, Double)] = []
        for (j, land) in lands.enumerated() {
            let top = bottom - thickness * Double(j + 1)
            var absorbed = 0.0
            for s in clouds[j] {
                let age = t - land
                guard age > 0 else { continue }
                let spread = Ease.out(age / 0.5)
                let sink = Ease.inOut((age - 0.3 - s.delay) / 0.95)
                let gone = Ease.clamp((sink - 0.8) / 0.2)
                absorbed += gone / Double(clouds[j].count)
                guard gone < 1 else { continue }
                let swirl = 1 - sink
                let x: Double = 0.5 + s.dx * spread + 0.012 * spread * swirl * sin(age * 7 + s.phase)
                let from: Double = surface + s.dy * spread + 0.008 * spread * swirl * cos(age * 7 + s.phase)
                drifting.append((x, from + (top - from) * sink, s.size * (1 - gone)))
            }
            layer += thickness * absorbed
        }

        // The solution, the precipitate under it, and the glass.
        let glass = u.polyline(tube)
        BenchShapes.fill(context, u, glass, from: surface, tint.opacity(0.22))
        if layer > 0.001 { BenchShapes.fill(context, u, glass, from: bottom - layer, clay.opacity(fade)) }
        for d in drifting { context.fill(u.circle(d.0, d.1, d.2), with: .color(clay.opacity(fade))) }
        u.stroke(context, glass, tint, 0.05)
        u.stroke(context, u.line((0.32, 0.36), (0.68, 0.36)), tint, 0.045)
    }
}

/// A pH series: a dropper moves along a row of five tubes standing in a
/// base, adding indicator to each in turn, and each fills to its shade. Acid
/// is a tint, neutral a light clay, and base clay that strengthens, so the
/// row reads as a graded scale left to right. Below, a scale bar fills in
/// step and a clay pointer slides along it. Then every tube empties together,
/// and the dropper goes back to the start.
enum PHRainbow {
    static let duration = 4.8
    private static let xs: [Double] = [0.14, 0.32, 0.5, 0.68, 0.86]
    private static let stops: [Double] = (0..<5).map { 0.4 + 0.55 * Double($0) }
    private static let half = 0.044
    private static let rim = 0.3, floor = 0.72, full = 0.4
    /// From acid to base: whether the shade is clay, and how strong.
    private static let shades: [(clay: Bool, alpha: Double)] = [
        (false, 0.85), (false, 0.5), (true, 0.45), (true, 0.75), (true, 1.0),
    ]
    /// A tube's sides, open at the top; its foot is hidden in the base.
    private static func tube(_ x: Double, half h: Double) -> [(Double, Double)] {
        [(x - h, rim), (x - h, floor), (x + h, floor), (x + h, rim)]
    }
    private static let glass: [[(Double, Double)]] = xs.map { tube($0, half: half) }
    /// The liquid, out to the glass's outer edge so that it shows at small sizes.
    private static let liquid: [[(Double, Double)]] = xs.map { tube($0, half: half + 0.0175) }

    private static func shade(_ i: Int, _ tint: Color, _ k: Double = 1) -> Color {
        (shades[i].clay ? clay : tint).opacity(shades[i].alpha * k)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let empty = Ease.inOut((t - 4.0) / 0.5)
        let last = xs.count - 1

        // The dropper's place along the row: on to each tube, then back.
        var x = xs[0]
        for i in 1...last { x += (xs[i] - xs[i - 1]) * Ease.inOut((t - stops[i] + 0.2) / 0.2) }
        x -= (xs[last] - xs[0]) * Ease.inOut((t - 3.7) / 0.7)
        var press = 0.0
        for s in stops { press += Ease.inOut((t - s) / 0.07) - Ease.inOut((t - s - 0.12) / 0.1) }

        // The tubes and what each has been given: the glass fades where liquid fills it.
        var fills: [Double] = []
        for i in xs.indices {
            let fill = Ease.out((t - stops[i] - 0.2) / 0.4) * (1 - empty)
            fills.append(fill)
            let tubePath = u.polyline(glass[i])
            u.stroke(context, u.line((xs[i] - half - 0.004, rim), (xs[i] + half + 0.004, rim)), tint, 0.035)
            context.fill(ChemGlass.polygon(u, liquid[i]), with: .color(tint.opacity(0.3)))
            guard fill > 0.001 else {
                u.stroke(context, tubePath, tint.opacity(0.35), 0.035)
                continue
            }
            let level = floor - (floor - full) * fill
            BenchShapes.fill(context, u, u.polyline(liquid[i]), from: level, shade(i, tint))
            let cut = u.pt(0, level).y
            var above = context
            above.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: cut - u.origin.y)))
            u.stroke(above, tubePath, tint.opacity(0.35), 0.035)
            var below = context
            below.clip(to: Path(CGRect(x: u.origin.x, y: cut, width: u.side, height: u.side)))
            u.stroke(below, tubePath, tint.opacity(0.2), 0.035)
        }

        // The base the tubes stand in.
        context.fill(u.capsule(0.5, 0.715, 0.94, 0.08, corner: 0.03), with: .color(tint))

        // A drop from the dropper into the tube it stands over.
        for (i, s) in stops.enumerated() {
            let a = (t - s - 0.05) / 0.2
            guard a > 0, a < 1 else { continue }
            context.fill(u.circle(xs[i], 0.28 + 0.27 * a * a, 0.036), with: .color(shade(i, tint)))
        }

        // The dropper: bulb, then the glass tapering to its tip.
        let bulb = 0.12 - 0.03 * press
        context.fill(u.capsule(x, 0.02 + bulb / 2, 0.1 + 0.012 * press, bulb, corner: 0.045), with: .color(tint))
        u.stroke(context, u.line((x - 0.032, 0.13), (x - 0.032, 0.2), (x - 0.01, 0.265)), tint, 0.04)
        u.stroke(context, u.line((x + 0.032, 0.13), (x + 0.032, 0.2), (x + 0.01, 0.265)), tint, 0.04)

        // The scale: a cell per tube, coloured as its tube fills, and the pointer.
        for i in xs.indices {
            let cell = u.capsule(xs[i], 0.93, 0.14, 0.07, corner: 0.025)
            context.fill(cell, with: .color(tint.opacity(0.22)))
            if fills[i] > 0 { context.fill(cell, with: .color(shade(i, tint, fills[i]))) }
        }
        var pointer = Path()
        pointer.move(to: u.pt(x - 0.045, 0.81))
        pointer.addLine(to: u.pt(x + 0.045, 0.81))
        pointer.addLine(to: u.pt(x, 0.885))
        pointer.closeSubpath()
        context.fill(pointer, with: .color(clay))
    }
}
