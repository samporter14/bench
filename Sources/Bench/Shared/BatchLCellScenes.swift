// BatchLCellScenes.swift
// ScienceStatus — the cell and the freezer: antibodies lighting up a cell's filaments,
// and a vial of cells cooled a degree a minute.
// Each draws in a unit square (see `UnitSquare`).

import SwiftUI

/// A point and a heading, to place a shape that turns with what it sits on:
/// local +x runs along the surface and -y points away from it.
private struct SurfacePose {
    let x: Double, y: Double, angle: Double

    /// A point in the shape's own coordinates, in the unit square's.
    func at(_ lx: Double, _ ly: Double) -> (Double, Double) {
        let c = cos(angle), s = sin(angle)
        return (x + lx * c - ly * s, y + lx * s + ly * c)
    }
}

/// Immunofluorescence: primary antibodies drift up to a fixed cell's filaments
/// and dock along them, secondary antibodies carrying a clay fluorophore dock
/// onto those, and under the microscope the antibodies drop away and the
/// filaments light up in clay along their length, the nucleus a faint disc;
/// then the cell is unstained again.
enum Immunofluorescence {
    static let duration = 5.0
    private static let fadeAt = 2.5, resetAt = 4.5

    private static let nucleus: (x: Double, y: Double, r: Double) = (0.47, 0.52, 0.11)

    /// The cell's edge at angle `a` from its middle, `scale` of the way out:
    /// wider than tall, a little lumpy.
    private static func edge(_ a: Double, _ scale: Double = 1) -> (Double, Double) {
        let wobble: Double = 1 + 0.04 * sin(3 * a + 0.7) + 0.03 * cos(2 * a)
        let x: Double = 0.5 + 0.4 * scale * wobble * cos(a)
        let y: Double = 0.5 + 0.35 * scale * wobble * sin(a)
        return (x, y)
    }
    private static let outline: [(Double, Double)] = (0..<72).map { edge(Double($0) * 2 * .pi / 72) }

    /// A filament: a curve from the nucleus's rim out to near the cell's edge.
    private struct Filament {
        let from: (Double, Double), bend: (Double, Double), to: (Double, Double)

        func point(_ s: Double) -> (Double, Double) {
            let a = (1 - s) * (1 - s), b = 2 * (1 - s) * s, c = s * s
            return (a * from.0 + b * bend.0 + c * to.0, a * from.1 + b * bend.1 + c * to.1)
        }

        /// The way it runs at `s`, as a unit vector.
        func heading(_ s: Double) -> (Double, Double) {
            let dx = 2 * (1 - s) * (bend.0 - from.0) + 2 * s * (to.0 - bend.0)
            let dy = 2 * (1 - s) * (bend.1 - from.1) + 2 * s * (to.1 - bend.1)
            let n = max(hypot(dx, dy), 0.0001)
            return (dx / n, dy / n)
        }

        func path(_ u: UnitSquare) -> Path {
            var p = Path()
            p.move(to: u.pt(from.0, from.1))
            p.addQuadCurve(to: u.pt(to.0, to.1), control: u.pt(bend.0, bend.1))
            return p
        }
    }

    /// Five filaments, each leaving the nucleus at its own angle and curling
    /// round as it runs out to near the cell's edge, some longer than others:
    /// a loose aster.
    private static let filaments: [Filament] = [
        (-155.0, 0.7, 0.93, 0.12), (-85, 0.35, 0.85, 0.1), (-15, 0.5, 0.92, 0.11),
        (60, 0.3, 0.85, 0.1), (130, 0.65, 0.94, 0.12),
    ].map { (degrees: Double, curl: Double, reach: Double, bow: Double) -> Filament in
        let a = degrees * .pi / 180
        let rim = nucleus.r + 0.01
        let from: (Double, Double) = (nucleus.x + rim * cos(a), nucleus.y + rim * sin(a))
        let to = edge(a + curl, reach)
        let mid: (Double, Double) = ((from.0 + to.0) / 2, (from.1 + to.1) / 2)
        let bend: (Double, Double) = (mid.0 - bow * (to.1 - from.1), mid.1 + bow * (to.0 - from.0))
        return Filament(from: from, bend: bend, to: to)
    }

    /// One pair of antibodies to a filament, in order: how far along it they
    /// dock, which side of it they stand out on (the roomier one, clear of
    /// the cell's edge, the nucleus and the other filaments and pairs), and
    /// when the primary lands.
    private static let docks: [(s: Double, side: Double, lands: Double)] = [
        (0.75, 1, 0.7), (0.6, 1, 0.9), (0.4, 1, 1.1), (0.5, 1, 1.3), (0.6, 1, 1.5),
    ]

    private static let arm = (w: 0.03, h: 0.036), stem = 0.036

    /// One antibody: a Y whose arm tips rest at `pose`'s origin and whose
    /// stem stands out from it. The secondary carries the fluorophore, a clay
    /// dot at the stem's end.
    private static func antibody(_ context: GraphicsContext, _ u: UnitSquare, _ pose: SurfacePose, tint: Color, alpha: Double, dot: Bool) {
        let left = pose.at(-arm.w, 0), right = pose.at(arm.w, 0)
        let fork = pose.at(0, -arm.h), end = pose.at(0, -arm.h - stem)
        var shape = u.line(left, fork, right)
        shape.addPath(u.line(fork, end))
        u.stroke(context, shape, tint.opacity(alpha), 0.03)
        if dot { context.fill(u.circle(end.0, end.1, 0.032), with: .color(clay.opacity(alpha))) }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The antibodies go; the clay is what the microscope sees; then back.
        let fade = Ease.inOut((t - fadeAt) / 0.5)
        let reset = Ease.inOut((t - resetAt) / 0.5)
        let seen = Ease.inOut((t - fadeAt) / 0.6) * (1 - reset)

        var cell = u.polyline(outline)
        cell.closeSubpath()
        u.stroke(context, cell, tint.opacity(1 - 0.65 * seen), 0.05)
        let core = u.circle(nucleus.x, nucleus.y, nucleus.r)
        context.fill(core, with: .color(tint.opacity(0.14 + 0.18 * seen)))
        u.stroke(context, core, tint.opacity(0.6 * (1 - seen)), 0.03)
        for f in filaments {
            u.stroke(context, f.path(u), tint.opacity(0.8 - 0.35 * seen), 0.04)
        }

        // The light, growing out from where the antibodies sit.
        for (i, f) in filaments.enumerated() {
            let sweep = Ease.inOut((t - fadeAt - 0.1 - 0.06 * Double(i)) / 0.75)
            guard sweep > 0 else { continue }
            let lit = sweep < 1 ? f.path(u).trimmedPath(from: docks[i].s * (1 - sweep), to: docks[i].s + (1 - docks[i].s) * sweep) : f.path(u)
            u.stroke(context, lit, clay.opacity(1 - reset), 0.06)
        }

        for (k, dock) in docks.enumerated() {
            let f = filaments[k]
            let at = f.point(dock.s), run = f.heading(dock.s)
            let out = (-run.1 * dock.side, run.0 * dock.side)
            let angle = atan2(out.0, -out.1)
            let flip = k % 2 == 0 ? 1.0 : -1.0
            // Loose ends sway once a loop, so the loop closes on itself.
            let sway = sin(2 * .pi * t / duration * 2 + Double(k))

            // The primary drifts in and settles, and starts over at the loop's end.
            let landed = t < resetAt ? Ease.out(t / dock.lands) : 0
            let away = 1 - landed
            let aside = -0.08 * away
            let lift = 0.1 * away
            let primary = SurfacePose(x: at.0 + out.0 * lift + run.0 * aside + 0.012 * sway * away,
                               y: at.1 + out.1 * lift + run.1 * aside + 0.012 * sway * away,
                               angle: angle + (0.8 * flip + 0.25 * sway) * away)
            let primaryAlpha = max(1 - fade, reset)
            antibody(context, u, primary, tint: tint, alpha: primaryAlpha, dot: false)

            // The secondary comes in later and grips the primary's stem.
            let starts = dock.lands + 0.1, arrives = dock.lands + 0.85
            let come = t < resetAt ? Ease.out((t - starts) / (arrives - starts)) : 0
            let secondaryAlpha = t < resetAt ? Ease.clamp((t - starts) / 0.25) * (1 - fade) : 0
            guard secondaryAlpha > 0 else { continue }
            let docked = SurfacePose(x: at.0, y: at.1, angle: angle)
            let tip = docked.at(0, -arm.h - stem)
            let near = 1 - come
            let secondary = SurfacePose(x: tip.0 + out.0 * 0.05 * near - run.0 * 0.1 * near,
                                 y: tip.1 + out.1 * 0.05 * near - run.1 * 0.1 * near,
                                 angle: angle + 0.35 * flip + 0.9 * flip * near)
            antibody(context, u, secondary, tint: tint, alpha: secondaryAlpha, dot: true)
        }
    }
}

/// Freezing cells the slow way: a cryovial of clay cells in their liquid gets
/// its cap screwed on, drops into the round cooling jar (drawn as a cutaway,
/// so the vial stays in view), the lid closes, and the readout steps down
/// 20, 0, -40, -80 while frost creeps over the jar; at the bottom the cells
/// stop moving and ice crystals set in the liquid. Then the jar opens for the
/// next vial.
enum FreezingCells {
    static let duration = 5.0

    private static let tubX = 0.32, tubHalf = 0.23, rim = 0.47, floor = 0.88, liquid = 0.82
    /// The vial: its half width, its body's height, where its body starts
    /// above the jar and how far it drops to stand in it.
    private static let half = 0.085, body = 0.27, above = 0.13, dropBy = 0.42
    private static let hoverGap = 0.05
    /// How far down the vial's body the liquid's surface is.
    private static let liquidLevel = 0.07
    private static let lidShut = (x: tubX, y: rim - 0.04), lidOpen = (x: 0.73, y: 0.26, turn: 0.25)

    /// The cells: where each sits in the liquid (down from the body's top),
    /// and how it jitters, in whole cycles per loop.
    private static let cells: [(dx: Double, dy: Double, mx: Double, my: Double, phase: Double)] = [
        (-0.033, 0.125, 5, 7, 0.0), (0.033, 0.155, 6, 4, 1.7), (-0.028, 0.19, 4, 6, 3.1), (0.02, 0.215, 7, 5, 4.4),
    ]

    /// The readout as the jar cools: from when, and what each of its three
    /// cells shows (a minus sign is the middle bar alone).
    private static let readings: [(at: Double, cells: [String])] = [
        (-1, ["", SevenSegment.digits[2], SevenSegment.digits[0]]),
        (2.2, ["", "", SevenSegment.digits[0]]),
        (2.75, ["g", SevenSegment.digits[4], SevenSegment.digits[0]]),
        (3.3, ["g", SevenSegment.digits[8], SevenSegment.digits[0]]),
    ]

    /// Frost on the jar: from the rim down as it cools, a serrated rime along
    /// the outside of each wall, `reach` long.
    private static func rime(_ context: GraphicsContext, _ u: UnitSquare, reach: Double, tint: Color) {
        let half = 0.032, teeth = 0.045, start = rim + 0.03
        for (side, phase) in [(-1.0, 0), (1.0, 1)] {
            let wall = tubX + side * (tubHalf + 0.025)
            func x(_ i: Int) -> Double { (i + phase) % 2 == 0 ? wall : wall + side * teeth }
            var points: [(Double, Double)] = [(x(0), start)]
            var i = 1
            while Double(i - 1) * half < reach {
                let f = min(1, (reach - Double(i - 1) * half) / half)
                points.append((x(i - 1) + (x(i) - x(i - 1)) * f, start + (Double(i - 1) + f) * half))
                i += 1
            }
            u.stroke(context, u.polyline(points), tint, 0.03)
        }
    }

    /// The vial with its cap: `drop` down from where it starts, `gap` of air
    /// between cap and body, the cap turned `turn` times.
    private static func vial(_ context: GraphicsContext, _ u: UnitSquare, drop: Double, gap: Double, turn: Double,
                             time t: Double, jitter: Double, frozen: Double, alpha: Double, tint: Color) {
        var scene = context
        scene.opacity = context.opacity * alpha
        let top = above + drop, bottom = top + body
        var glass = Path()
        glass.move(to: u.pt(tubX - half, top))
        glass.addLine(to: u.pt(tubX - half, bottom - 0.06))
        glass.addQuadCurve(to: u.pt(tubX + half, bottom - 0.06), control: u.pt(tubX, bottom + 0.05))
        glass.addLine(to: u.pt(tubX + half, top))
        BenchShapes.fill(scene, u, glass, from: top + liquidLevel, tint.opacity(0.16 + 0.06 * frozen))

        // Ice sets in the liquid: a lattice of thin crystal lines behind the cells.
        if frozen > 0 {
            var inside = scene
            var closed = glass
            closed.closeSubpath()
            inside.clip(to: closed)
            inside.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, top + liquidLevel).y, width: u.side, height: u.side)))
            var lattice = Path()
            for k in -1...1 {
                let x = tubX + 0.11 * Double(k)
                lattice.addPath(u.line((x - 0.07, bottom), (x + 0.07, top + liquidLevel)))
                lattice.addPath(u.line((x + 0.07, bottom), (x - 0.07, top + liquidLevel)))
            }
            u.stroke(inside, lattice, tint.opacity(0.7 * frozen), 0.03)
        }
        for (k, cell) in cells.enumerated() {
            let w = 2 * Double.pi * t / duration
            let x: Double = tubX + cell.dx + 0.007 * jitter * sin(w * cell.mx + cell.phase)
            let y: Double = top + cell.dy + 0.007 * jitter * cos(w * cell.my + cell.phase + Double(k))
            scene.fill(u.circle(x, y, 0.024), with: .color(clay))
        }
        u.stroke(scene, glass, tint, 0.04)

        // The cap, ridged: the ridges run round it as it turns.
        let capY = top - 0.022 - gap
        scene.drawLayer { layer in
            layer.fill(u.capsule(tubX, capY, 0.2, 0.075, corner: 0.022), with: .color(tint))
            layer.blendMode = .destinationOut
            for k in 0..<4 {
                let a = (turn + Double(k) / 4) * 2 * .pi
                guard cos(a) > 0.15 else { continue }
                let x = tubX + 0.085 * sin(a)
                u.stroke(layer, u.line((x, capY - 0.02), (x, capY + 0.02)), .black, 0.03)
            }
        }
    }

    /// The jar's lid with its knob, centred at (x, y) and turned `angle`.
    private static func lid(_ context: GraphicsContext, _ u: UnitSquare, x: Double, y: Double, angle: Double, tint: Color) {
        var piece = context
        let at = u.pt(x, y)
        piece.translateBy(x: at.x, y: at.y)
        piece.rotate(by: .radians(angle))
        piece.fill(Path(roundedRect: CGRect(x: -u.len(0.24), y: -u.len(0.0375), width: u.len(0.48), height: u.len(0.075)),
                        cornerRadius: u.len(0.03)), with: .color(tint))
        piece.fill(Path(roundedRect: CGRect(x: -u.len(0.08), y: -u.len(0.08), width: u.len(0.16), height: u.len(0.05)),
                        cornerRadius: u.len(0.02)), with: .color(tint))
    }

    /// The readout showing reading `index`, at `alpha`.
    private static func readout(_ context: GraphicsContext, _ u: UnitSquare, index: Int, alpha: Double, tint: Color) {
        guard alpha > 0 else { return }
        for (k, segments) in readings[index].cells.enumerated() {
            SevenSegment.draw(context, u, segments, x: 0.715 + 0.09 * Double(k), y: 0.67, w: 0.055, h: 0.11,
                              color: tint.opacity(alpha), width: 0.03)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        // The loop turns over: the lid lifts and the frozen vial fades, then
        // the next vial and a reading of 20 fade in.
        let lift = Ease.inOut((t - 4.5) / 0.3)
        let outgoing = Ease.clamp((t - 4.5) / 0.3)
        let incoming = Ease.clamp((t - 4.72) / 0.28)

        // The jar: a round tub, with a little coolant in the bottom.
        var tub = Path()
        tub.move(to: u.pt(tubX - tubHalf, rim))
        tub.addLine(to: u.pt(tubX - tubHalf, floor - 0.07))
        tub.addQuadCurve(to: u.pt(tubX - tubHalf + 0.07, floor), control: u.pt(tubX - tubHalf, floor))
        tub.addLine(to: u.pt(tubX + tubHalf - 0.07, floor))
        tub.addQuadCurve(to: u.pt(tubX + tubHalf, floor - 0.07), control: u.pt(tubX + tubHalf, floor))
        tub.addLine(to: u.pt(tubX + tubHalf, rim))
        BenchShapes.fill(context, u, tub, from: liquid, tint.opacity(0.16))

        // The vial: its cap goes on, it goes in, and the cells freeze at the
        // bottom of the readout. At the loop's end the next one takes its place.
        let screwing = Ease.clamp((t - 0.15) / 0.9)
        let drop = dropBy * Ease.inOut((t - 1.0) / 0.6)
        let cooled = Ease.inOut((t - 2.2) / 1.1)
        let frozen = Ease.inOut((t - 3.3) / 0.6)
        vial(context, u, drop: drop, gap: hoverGap * (1 - screwing), turn: 2 * screwing, time: t,
             jitter: (1 - 0.5 * cooled) * (1 - frozen), frozen: frozen, alpha: 1 - outgoing, tint: tint)
        if incoming > 0 {
            vial(context, u, drop: 0, gap: hoverGap, turn: 0, time: t, jitter: 1, frozen: 0, alpha: incoming, tint: tint)
        }
        u.stroke(context, tub, tint, 0.05)

        // The lid comes across and shuts; at the end it lifts off again.
        let shut = Ease.inOut((t - 1.65) / 0.45) * (1 - lift)
        lid(context, u, x: lidOpen.x + (lidShut.x - lidOpen.x) * shut, y: lidOpen.y + (lidShut.y - lidOpen.y) * shut,
            angle: lidOpen.turn * (1 - shut), tint: tint)

        // Frost creeps down the walls a step at a time, with the readout.
        let creep = Ease.inOut((t - 2.3) / 0.3) + Ease.inOut((t - 2.85) / 0.3) + Ease.inOut((t - 3.4) / 0.3)
        if creep > 0 && outgoing < 1 {
            var frosted = context
            frosted.opacity = context.opacity * (1 - outgoing)
            rime(frosted, u, reach: 0.02 + 0.11 * creep, tint: tint)
        }

        // The readout, in a frame, stepping down; back to 20 as the loop turns over.
        u.stroke(context, u.capsule(0.805, 0.67, 0.31, 0.24, corner: 0.05), tint.opacity(0.5), 0.03)
        for index in readings.indices {
            let on = Ease.clamp((t - readings[index].at) / 0.12)
            let off = index + 1 < readings.count ? Ease.clamp((t - readings[index + 1].at) / 0.12) : 0
            var weight = on - off
            if index == 0 { weight = max(weight, incoming) }
            if index == readings.count - 1 { weight *= 1 - outgoing }
            readout(context, u, index: index, alpha: weight, tint: tint)
        }
    }
}
