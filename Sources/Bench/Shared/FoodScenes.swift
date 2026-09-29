// FoodScenes.swift
// ScienceStatus — food science: fermentations, mostly. Each draws in a
// unit square (see `UnitSquare`): vessels in the tint, what's fermenting
// in clay.

import SwiftUI

/// Beer fermenting: in the carboy the clay wort bubbles and wears a head of
/// krausen, yeast settles, and in the airlock on top a bubble rises through
/// the water and pops.
enum BeerFermentation {
    static let duration = 4.2

    private static func carboy(_ u: UnitSquare) -> Path {
        var p = Path()
        p.move(to: u.pt(0.44, 0.24))
        p.addLine(to: u.pt(0.44, 0.3))
        p.addQuadCurve(to: u.pt(0.22, 0.48), control: u.pt(0.22, 0.32))
        p.addLine(to: u.pt(0.22, 0.84))
        p.addQuadCurve(to: u.pt(0.28, 0.9), control: u.pt(0.22, 0.9))
        p.addLine(to: u.pt(0.72, 0.9))
        p.addQuadCurve(to: u.pt(0.78, 0.84), control: u.pt(0.78, 0.9))
        p.addLine(to: u.pt(0.78, 0.48))
        p.addQuadCurve(to: u.pt(0.56, 0.3), control: u.pt(0.78, 0.32))
        p.addLine(to: u.pt(0.56, 0.24))
        return p
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let glass = carboy(u)
        var body = glass
        body.closeSubpath()
        var inside = context
        inside.clip(to: body)
        inside.fill(Path(CGRect(x: u.origin.x, y: u.pt(0, 0.5).y, width: u.side, height: u.side)), with: .color(clay))
        for k in 0..<9 {
            let s = Double(k)
            let x = 0.28 + 0.44 * BenchShapes.rand(s)
            let rise = ((t / 1.6 + BenchShapes.rand(s + 9)).truncatingRemainder(dividingBy: 1))
            // Each fades in at the bottom and out at the top, so none jumps.
            inside.fill(u.circle(x + 0.01 * sin(t * 4 + s), 0.86 - 0.34 * rise, 0.012),
                        with: .color(ivory.opacity(0.8 * sin(.pi * rise))))
        }
        for k in 0..<7 {
            let s = Double(k)
            inside.fill(u.circle(0.26 + 0.075 * s, 0.49 + 0.012 * sin(t * 2 + s), 0.04 + 0.01 * sin(t * 1.5 + s * 2)), with: .color(tint.opacity(0.5)))
        }
        for k in 0..<10 {
            let s = Double(k)
            let settle = ((t / 4.2 + BenchShapes.rand(s + 3)).truncatingRemainder(dividingBy: 1))
            inside.fill(u.circle(0.28 + 0.44 * BenchShapes.rand(s + 50), 0.56 + 0.32 * settle, 0.008),
                        with: .color(tint.opacity(0.7 * sin(.pi * settle))))
        }
        u.stroke(context, glass, tint, 0.04)
        context.fill(u.capsule(0.5, 0.22, 0.16, 0.06, corner: 0.015), with: .color(tint))
        // The airlock: a stem up from the stopper into a little chamber of
        // water. A bubble swells at the stem's mouth, rises through the
        // water and pops at the surface.
        u.stroke(context, u.line((0.5, 0.2), (0.5, 0.135)), tint, 0.03)
        context.fill(u.capsule(0.5, 0.135, 0.1, 0.07, corner: 0.012), with: .color(tint.opacity(0.3)))
        u.stroke(context, u.capsule(0.5, 0.115, 0.14, 0.13, corner: 0.02), tint, 0.025)
        let cycle = (t / 1.4).truncatingRemainder(dividingBy: 1)
        let swell = Ease.out(cycle / 0.15)
        if cycle < 0.62 {
            let rise = Ease.inOut((cycle - 0.15) / 0.47)
            let y = 0.14 - 0.04 * rise
            context.fill(u.circle(0.5 + 0.008 * sin(cycle * 20), y, 0.016 * swell), with: .color(clay))
        } else if cycle < 0.9 {
            let pop = (cycle - 0.62) / 0.28
            u.stroke(context, u.circle(0.5, 0.1, 0.015 + 0.025 * pop), clay.opacity(1 - pop), 0.015)
        }
    }
}

/// Sourdough rising: the clay dough climbs its lidded jar, bubbles opening
/// in it, then is knocked back down.
enum Sourdough {
    static let duration = 4.4

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rise = Ease.inOut((t - 0.2) / 2.8) * (1 - Ease.inOut((t - 3.6) / 0.5))
        let top = 0.66 - 0.36 * rise
        var jar = Path()
        jar.move(to: u.pt(0.28, 0.2))
        jar.addLine(to: u.pt(0.28, 0.82))
        jar.addQuadCurve(to: u.pt(0.34, 0.88), control: u.pt(0.28, 0.88))
        jar.addLine(to: u.pt(0.66, 0.88))
        jar.addQuadCurve(to: u.pt(0.72, 0.82), control: u.pt(0.72, 0.88))
        jar.addLine(to: u.pt(0.72, 0.2))
        var body = jar
        body.closeSubpath()
        context.drawLayer { layer in
            layer.clip(to: body)
            let dome = stride(from: 0.28, through: 0.72, by: 0.02).map { x in (x, top - 0.05 * rise * sin(.pi * (x - 0.28) / 0.44)) }
            var dough = u.polyline(dome + [(0.72, 0.9), (0.28, 0.9)])
            dough.closeSubpath()
            layer.fill(dough, with: .color(clay))
            layer.blendMode = .destinationOut
            for k in 0..<12 {
                let s = Double(k)
                let y = top + 0.04 + (0.84 - top - 0.04) * BenchShapes.rand(s + 4)
                let r = (0.008 + 0.022 * BenchShapes.rand(s + 8)) * rise
                if r > 0.002 { layer.fill(u.circle(0.32 + 0.36 * BenchShapes.rand(s), y, r), with: .color(.black)) }
            }
        }
        u.stroke(context, jar, tint, 0.04)
        // The lid, sitting loose on top.
        context.fill(u.capsule(0.5, 0.165, 0.52, 0.06, corner: 0.02), with: .color(tint))
    }
}

/// Yogurt: warm milk, a spoon of culture, and the clay bacteria — rods and
/// chains — multiply until the milk has set.
enum Yogurt {
    static let duration = 4.2

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let set = Ease.inOut((t - 1.0) / 2.4)
        let fade = Ease.inOut((t - 3.8) / 0.35)
        var jar = context
        jar.opacity = 1 - fade
        let glass = u.line((0.24, 0.26), (0.26, 0.88), (0.74, 0.88), (0.76, 0.26))
        let wobble = 0.012 * (1 - set) * sin(t * 4)
        var body = glass
        body.closeSubpath()
        var inside = jar
        inside.clip(to: body)
        let surface = stride(from: 0.2, through: 0.8, by: 0.02).map { x in (x, 0.4 + wobble * sin(x * 20)) }
        var milk = u.polyline(surface + [(0.8, 0.9), (0.2, 0.9)])
        milk.closeSubpath()
        inside.fill(milk, with: .color(tint.opacity(0.12 + 0.18 * set)))
        let count = Int(3 + 17 * set)
        for k in 0..<count {
            let s = Double(k)
            let p = (0.3 + 0.4 * BenchShapes.rand(s), 0.46 + 0.38 * BenchShapes.rand(s + 20))
            if k % 3 == 0 {
                for j in 0..<3 { inside.fill(u.circle(p.0 + 0.022 * Double(j), p.1, 0.01), with: .color(clay)) }
            } else {
                var rod = inside
                let at = u.pt(p.0, p.1)
                rod.translateBy(x: at.x, y: at.y)
                rod.rotate(by: .radians(.pi * BenchShapes.rand(s + 40)))
                rod.fill(Path(roundedRect: CGRect(x: -u.len(0.025), y: -u.len(0.009), width: u.len(0.05), height: u.len(0.018)),
                              cornerRadius: u.len(0.009)), with: .color(clay))
            }
        }
        u.stroke(jar, glass, tint, 0.04)
        let spoon = Keyframes.value(t, [(0.2, 0), (0.5, 1), (0.8, 1), (1.1, 0)])
        if spoon > 0 {
            let y = 0.1 + 0.3 * spoon
            jar.fill(u.ellipse(0.6, y, 0.1, 0.05), with: .color(tint))
            u.stroke(jar, u.line((0.6, y), (0.78, y - 0.2)), tint, 0.03)
            if spoon > 0.6 { jar.fill(u.circle(0.6, y - 0.01, 0.015), with: .color(clay)) }
        }
    }
}
