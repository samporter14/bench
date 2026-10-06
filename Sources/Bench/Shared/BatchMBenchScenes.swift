// BatchMBenchScenes.swift
// ScienceStatus — at the bench and the clinic: a biopsy punch, liquid
// climbing capillaries, a cell strainer. Each draws in a unit square (see
// `UnitSquare`): kit and glass in the tint, the tissue, liquid or filtrate
// the scene is about in clay.

import SwiftUI

/// Biopsy punch: a knurled, pen-like punch comes down over a side section of skin
/// and twists in through the epidermis and dermis to the fat, the clay tissue core
/// filling its bore. It lifts out carrying the core, slides to one side and sets it
/// down on the skin, leaving a neat hole. The core fades as the punch returns and
/// the hole closes up. One loop is 5.6 s.
enum BiopsyPunch {
    static let duration = 5.6

    private static let skinTop = 0.65
    private static let fatTop = 0.81        // where the dermis ends and the lobules begin
    private static let rest = 0.54          // the blade's rim, held clear of the skin
    private static let bladeHalf = 0.1
    private static let coreHalf = 0.088
    private static let coreLength = fatTop - skinTop
    private static let aside = 0.25         // how far the punch slides to set the core down

    private static func waveY(_ x: Double) -> Double { skinTop + 0.012 * sin(x * 24) }

    /// The skin's surface, a gentle wave; the epidermis' lower edge runs parallel to it.
    private static let skinLine: [(Double, Double)] = (0...36).map { i in
        let x = 0.06 + 0.88 * Double(i) / 36
        return (x, waveY(x))
    }
    private static let epiLine: [(Double, Double)] = skinLine.map { ($0.0, $0.1 + 0.06) }
    /// The dermis between the epidermis and the fat, for its faint wash.
    private static let dermis: [(Double, Double)] = epiLine + [(0.94, 0.84), (0.06, 0.84)]
    private static let lobules: [Double] = [0.16, 0.33, 0.5, 0.67, 0.84]

    private static func ramp(_ t: Double, _ start: Double, _ length: Double) -> Double {
        Ease.inOut((t - start) / length)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let down = ramp(t, 0.3, 1.2) - ramp(t, 1.85, 0.7)
        let tip = rest + (fatTop - rest) * down
        let cx = 0.5 + aside * (ramp(t, 2.45, 0.7) - ramp(t, 3.55, 0.7))
        // The handle is rocked back and forth as it goes in.
        let twist = 1.75 * sin(3 * .pi * Ease.clamp((t - 0.3) / 1.4))
        // The cut: as wide as the blade, from the skin down to the fat, shrinking shut at the end.
        let hw = bladeHalf * (1 - ramp(t, 3.9, 1.0))
        let cut = t < 1.85 ? min(tip, fatTop) : fatTop

        // The skin, with the cut taken out of everything above the fat.
        var skin = context
        if hw > 0.003, cut > 0.59 {
            let hole = Path(CGRect(x: u.pt(0.5 - hw, 0).x, y: u.pt(0, 0.58).y, width: u.len(2 * hw), height: u.len(cut - 0.58)))
            skin.clip(to: hole, options: .inverse)
        }
        var wash = u.polyline(dermis)
        wash.closeSubpath()
        skin.fill(wash, with: .color(tint.opacity(0.14)))
        u.stroke(skin, u.polyline(skinLine), tint, 0.06)
        u.stroke(skin, u.polyline(epiLine), tint.opacity(0.6), 0.04)
        for x in lobules { u.stroke(context, u.circle(x, 0.875, 0.06), tint.opacity(0.85), 0.045) }

        // The hole's walls; they fade before they meet, so no scar line is left behind.
        let wallAlpha = Ease.clamp((hw - 0.004) / 0.04)
        if cut > skinTop + 0.02, wallAlpha > 0 {
            for side in [-1.0, 1.0] {
                let x = 0.5 + side * hw
                u.stroke(context, u.line((x, waveY(x)), (x, cut)), tint.opacity(wallAlpha), 0.04)
            }
        }

        // The tissue core: what the bore has cut, then what it carries and sets down.
        let drop = Ease.clamp((t - 3.2) / 0.3)
        let fall = 0.08 * drop * drop
        let coreBottom = tip + fall
        let coreTop = (t < 1.85 ? skinTop : tip - coreLength) + fall
        let coreX = 0.5 + aside * ramp(t, 2.45, 0.7)
        let alpha = 1 - ramp(t, 3.65, 0.6)
        if coreBottom - coreTop > 0.004, alpha > 0.01 {
            let body = Path(CGRect(x: u.pt(coreX - coreHalf, 0).x, y: u.pt(0, coreTop).y,
                                   width: u.len(2 * coreHalf), height: u.len(coreBottom - coreTop)))
            context.fill(body, with: .color(clay.opacity(alpha)))
            context.fill(u.ellipse(coreX, coreBottom, 2 * coreHalf, 0.04), with: .color(clay.opacity(alpha)))
            context.fill(u.ellipse(coreX, coreTop, 2 * coreHalf, 0.04), with: .color(clay.opacity(alpha)))
            context.fill(u.ellipse(coreX, coreTop, 2 * coreHalf, 0.04), with: .color(ivory.opacity(0.35 * alpha)))
            // Faint layer lines: epidermis from dermis, papillary from reticular. Drawn without the
            // kit's floor, so at menu-bar size they fade to texture and the core stays clay.
            for depth in [0.06, 0.12] where coreBottom - coreTop > depth + 0.01 {
                let y = coreTop + depth
                context.stroke(u.line((coreX - coreHalf + 0.012, y), (coreX + coreHalf - 0.012, y)),
                               with: .color(ivory.opacity(0.6 * alpha)),
                               style: StrokeStyle(lineWidth: u.len(0.03), lineCap: .round))
            }
        }

        punch(context, u, x: cx, tip: tip, twist: twist, tint: tint)
    }

    /// The punch: a hollow blade (two walls and an elliptical rim), a flange, and a
    /// pen-like handle whose knurling ticks slide sideways as it turns.
    private static func punch(_ context: GraphicsContext, _ u: UnitSquare, x: Double, tip: Double, twist: Double, tint: Color) {
        let flange = tip - 0.2
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((x + side * bladeHalf, flange), (x + side * bladeHalf, tip)), tint, 0.045)
        }
        u.stroke(context, u.ellipse(x, tip, 2 * bladeHalf, 0.05), tint, 0.04)
        u.stroke(context, u.line((x - 0.17, flange), (x + 0.17, flange)), tint, 0.05)

        let handle = u.capsule(x, flange - 0.145, 0.22, 0.27, corner: 0.07)
        context.fill(handle, with: .color(tint.opacity(0.16)))
        u.stroke(context, handle, tint, 0.06)
        // Knurling: ticks round the barrel, seen from the side, so they bunch at the edges.
        for i in 0..<9 {
            let a = Double(i) * 2 * .pi / 9 + twist
            let c = cos(a)
            guard c > 0.15 else { continue }
            let tx = x + 0.07 * sin(a)
            u.stroke(context, u.line((tx, flange - 0.22), (tx, flange - 0.08)), tint.opacity(0.4 + 0.6 * c), 0.035)
        }
    }
}

/// Capillary fill: three thin glass tubes of different bore dip into a shallow dish
/// of clay liquid. The liquid climbs each one, the thinnest highest (Jurin's law),
/// with a concave meniscus on top. The tubes lift out and the columns drain back
/// to the dish; the empty tubes are lowered in again. One loop is 5.6 s.
enum CapillaryFill {
    static let duration = 5.6

    private static let surface = 0.82       // the liquid in the dish
    private static let dipped = 0.865       // the tubes' lower ends, just under it
    private static let topEnd = 0.18
    private static let lift = 0.10

    private static let wall = 0.045

    /// A tube: its centre, its bore (clear width between the walls), how high the liquid
    /// climbs, how long it takes to drain. The walls' centre lines sit half a wall outside the bore.
    private struct Spec {
        let x: Double, bore: Double, rise: Double, drain: Double
        var half: Double { bore / 2 + CapillaryFill.wall / 2 }
    }
    // Rises go with 1 / bore.
    private static let specs: [Spec] = [
        Spec(x: 0.24, bore: 0.12, rise: 0.21, drain: 0.7),
        Spec(x: 0.53, bore: 0.08, rise: 0.31, drain: 0.9),
        Spec(x: 0.79, bore: 0.05, rise: 0.5, drain: 1.1),
    ]
    private static let dish: [(Double, Double)] = [(0.05, 0.74), (0.12, 0.92), (0.88, 0.92), (0.95, 0.74)]
    private static let liquid: [(Double, Double)] = [(0.0811, surface), (0.12, 0.92), (0.88, 0.92), (0.9189, surface)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let climb = Ease.out((t - 0.35) / 1.7)
        let shift = lift * (Ease.inOut((t - 2.5) / 0.55) - Ease.inOut((t - 4.25) / 0.7))

        var pool = u.polyline(liquid)
        pool.closeSubpath()
        context.fill(pool, with: .color(clay))
        u.stroke(context, u.polyline(dish), tint, 0.06)

        for s in specs {
            let bottom = dipped - shift
            let top = topEnd - shift
            let xl = s.x - s.half, xr = s.x + s.half
            // The column's top: it climbs with the tube still in the dish, rides up with the
            // tube when it is lifted, then falls out through the open end.
            let drained = Ease.inOut((t - 3.05) / s.drain)
            let base = surface - s.rise * climb - shift
            var colTop = base + (bottom - base) * drained
            // An empty tube dipped in the dish fills to the dish's level.
            if bottom > surface { colTop = min(colTop, surface) }
            let length = bottom - colTop

            // The stream leaving the lifted tube, back to the dish.
            let flow = min(1, drained / 0.1, (1 - drained) / 0.1)
            if flow > 0, bottom < surface {
                u.stroke(context, u.line((s.x, bottom), (s.x, surface)), clay.opacity(flow), max(0.03, s.half * 0.6))
            }

            // The column, under the walls so they stay whole: from its top down to the tube's
            // lower end, which takes in the part dipped below the dish's surface.
            if length > 0.004 {
                let m = s.half * 0.45 * Ease.clamp((length - 0.05) / 0.1)   // meniscus depth
                var column = Path()
                column.move(to: u.pt(xl, colTop))
                column.addQuadCurve(to: u.pt(xr, colTop), control: u.pt(s.x, colTop + 2 * m))
                column.addLine(to: u.pt(xr, bottom))
                column.addLine(to: u.pt(xl, bottom))
                column.closeSubpath()
                context.fill(column, with: .color(clay))
            }
            u.stroke(context, u.line((xl, top), (xl, bottom)), tint, wall)
            u.stroke(context, u.line((xr, top), (xr, bottom)), tint, wall)
        }
    }
}

/// Cell strainer: a 50 mL conical tube with a cell strainer sitting in its mouth, its
/// lip on the rim and a mesh across the bottom of the cup. A pipette tip above
/// dispenses a suspension: single cells fall through the mesh into the tube, where a
/// clay filtrate level rises; two clumps are caught on the mesh. Then the filled tube
/// slides out to the right while a fresh one slides in from the left. One loop is 6 s.
enum CellStrainer {
    static let duration = 6.0

    /// One thing the pipette lets go: when, where it lands on the mesh, and what it is.
    private struct Drop {
        let at: Double, x: Double
        let kind: Int           // 0 a single cell, 1 a clump of three, 2 a clump of four
    }
    private static let drops: [Drop] = [
        Drop(at: 0.35, x: 0.47, kind: 0), Drop(at: 0.57, x: 0.53, kind: 0), Drop(at: 0.79, x: 0.42, kind: 1),
        Drop(at: 1.01, x: 0.47, kind: 0), Drop(at: 1.23, x: 0.53, kind: 0), Drop(at: 1.45, x: 0.47, kind: 0),
        Drop(at: 1.67, x: 0.58, kind: 2), Drop(at: 1.89, x: 0.53, kind: 0), Drop(at: 2.11, x: 0.47, kind: 0),
        Drop(at: 2.33, x: 0.53, kind: 0),
    ]
    private static let singles = drops.filter { $0.kind == 0 }.count
    /// Clump shapes: circle centres up from the clump's base, as it sits on the mesh.
    private static let clumps: [[(Double, Double)]] = [
        [(-0.024, -0.025), (0.024, -0.025), (0, -0.073)],
        [(-0.024, -0.025), (0.024, -0.025), (-0.024, -0.073), (0.024, -0.073)],
    ]

    private static let mouth = (x: 0.5, y: 0.12)       // the tip's opening
    private static let meshTop = 0.32, meshBottom = 0.4, rimY = 0.32
    private static let cellR = 0.026
    private static let tube: [(Double, Double)] = [(0.34, rimY), (0.34, 0.73), (0.465, 0.92), (0.535, 0.92), (0.66, 0.73), (0.66, rimY)]
    private static let ticks: [(y: Double, len: Double)] = [(0.47, 0.04), (0.53, 0.08), (0.59, 0.04), (0.65, 0.08), (0.71, 0.04)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var frame = context
        frame.clip(to: Path(CGRect(origin: u.origin, size: CGSize(width: u.side, height: u.side))))

        // A conveyor: the filled tube leaves to the right as a fresh one arrives from the left.
        let slide = Ease.inOut((t - 4.0) / 1.2)
        var current = frame
        current.translateBy(x: u.len(slide), y: 0)
        assembly(current, u, at: min(t, 4.0), tint: tint)
        if slide > 0 {
            var fresh = frame
            fresh.translateBy(x: u.len(slide - 1), y: 0)
            assembly(fresh, u, at: 0, tint: tint)
        }

        // The pipette tip stays put above the starting place.
        u.stroke(frame, u.line((0.43, 0.04), (mouth.x - 0.015, mouth.y)), tint, 0.045)
        u.stroke(frame, u.line((0.57, 0.04), (mouth.x + 0.015, mouth.y)), tint, 0.045)
        u.stroke(frame, u.line((0.4, 0.04), (0.6, 0.04)), tint, 0.05)
    }

    /// Where the filtrate stands, `tt` seconds in: each single cell raises it as it arrives.
    private static func level(_ tt: Double) -> Double {
        var got = 0.0
        for d in drops where d.kind == 0 { got += Ease.inOut((tt - d.at - 0.76) / 0.5) }
        return 0.92 - 0.36 * pow(got / Double(singles), 0.75)
    }

    /// Fills the closed outline from `level` down to its bottom.
    private static func fill(_ context: GraphicsContext, _ u: UnitSquare, _ outline: [(Double, Double)], from level: Double, _ color: Color) {
        var body = u.polyline(outline)
        body.closeSubpath()
        var liquid = context
        liquid.clip(to: Path(CGRect(x: u.origin.x - u.side, y: u.pt(0, level).y, width: 3 * u.side, height: 2 * u.side)))
        liquid.fill(body, with: .color(color))
    }

    /// The tube and strainer as they stand `tt` seconds into the dispensing.
    private static func assembly(_ context: GraphicsContext, _ u: UnitSquare, at tt: Double, tint: Color) {
        let level = level(tt)
        fill(context, u, tube, from: level, clay)
        u.stroke(context, u.polyline(tube), tint, 0.045)
        for k in ticks { u.stroke(context, u.line((0.635, k.y), (0.635 - k.len, k.y)), tint, 0.035) }

        // The strainer: the cup's walls, the lip on the rim, the mesh across the bottom of the cup.
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((0.5 + side * 0.18, 0.17), (0.5 + side * 0.16, rimY)), tint, 0.045)
        }
        u.stroke(context, u.line((0.25, rimY), (0.75, rimY)), tint, 0.05)
        for y in [meshTop, (meshTop + meshBottom) / 2, meshBottom] { u.stroke(context, u.line((0.34, y), (0.66, y)), tint, 0.035) }
        for i in -2...2 {
            let x = 0.5 + 0.05 * Double(i)
            u.stroke(context, u.line((x, meshTop), (x, meshBottom)), tint, 0.035)
        }

        // The cells, in free fall from the tip.
        for d in drops {
            let tau = tt - d.at
            guard tau > 0 else { continue }
            let y = mouth.y + 0.2 * tau + 0.7 * tau * tau
            let spread = Ease.out((y - mouth.y) / 0.12)
            if d.kind == 0 {
                // Through the mesh, then towards the middle of the tube; ivory and fading once in the filtrate.
                let x = 0.5 + (d.x - 0.5) * spread * (1 - Ease.clamp((y - 0.45) / 0.25))
                let depth = y - level
                guard depth < 0.05 else { continue }
                let alpha = min(1, tau / 0.06) * (depth > 0 ? 1 - depth / 0.05 : 1)
                context.fill(u.circle(x, y, cellR), with: .color((depth > 0 ? ivory : tint).opacity(alpha)))
            } else {
                // A clump swells from the tip's mouth, falls and stays on the mesh.
                let base = min(y, meshTop - 0.015)
                let x = 0.5 + (d.x - 0.5) * Ease.out((base - mouth.y) / 0.15)
                let grow = 0.4 + 0.6 * Ease.out(tau / 0.25)
                for c in clumps[d.kind - 1] {
                    context.fill(u.circle(x + c.0 * grow, base + c.1 * grow, cellR * grow), with: .color(tint))
                }
            }
        }
    }
}
