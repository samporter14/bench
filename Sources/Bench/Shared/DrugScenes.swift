// DrugScenes.swift
// ScienceStatus — study drugs and SSRIs as skeletal formulas (see
// `Skeleton`): the carbon skeleton in the tint, heteroatoms (O, N, S, F,
// Cl) as clay dots. Each builds bond by bond, then does something in
// character.

import SwiftUI

extension Rings {
    /// A regular polygon's vertices round `c`, the first at `start` degrees.
    static func around(_ c: (Double, Double), _ r: Double, sides: Int = 6, start: Double) -> [(Double, Double)] {
        (0..<sides).map { i in offset(c, r, start + 360 / Double(sides) * Double(i)) }
    }
}

/// Bond length for the formulas below.
private let bond = 0.12

/// Amphetamine, as in Adderall: a benzene ring, then CH₂–CH(CH₃)–NH₂.
/// Built, it gets restless: a quick jitter and clay speed lines.
enum Amphetamine {
    static let duration = 3.6
    private static let skeleton: Skeleton = {
        let hex = Rings.hexagon((0.3, 0.5), bond)
        let ca = Rings.offset(hex[1], bond, -30), cb = Rings.offset(ca, bond, 30)
        let atoms = hex + [ca, cb, Rings.offset(cb, bond, -30), Rings.offset(cb, bond, 90), (0.3, 0.5)]
        return Skeleton(atoms: atoms, bonds: [
            (0, 1, .inside(10)), (1, 2, .single), (2, 3, .inside(10)), (3, 4, .single), (4, 5, .inside(10)), (5, 0, .single),
            (1, 6, .single), (6, 7, .single), (7, 8, .single), (7, 9, .single),
        ], hetero: [8], extent: 0.58)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let wired = Ease.clamp((t - 1.8) / 0.2) * (1 - Ease.clamp((t - 3.2) / 0.3))
        var molecule = context
        molecule.translateBy(x: u.len(0.07 + 0.008 * sin(t * 70) * wired), y: u.len(0.006 * cos(t * 53) * wired))
        skeleton.draw(molecule, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.3))
        guard wired > 0 else { return }
        for (k, y) in [0.4, 0.5, 0.6].enumerated() {
            let run = ((t * 2.4 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1))
            let x = 0.1 - 0.1 * run
            u.stroke(context, u.line((x, y), (x + 0.07, y)), clay.opacity(wired * (1 - run)), 0.03)
        }
    }
}

/// Methylphenidate (Ritalin): a phenyl ring and a piperidine on one carbon
/// with a methyl ester. Built, a clay focus frame closes in on it.
enum Methylphenidate {
    static let duration = 3.8
    private static let skeleton: Skeleton = {
        let cc = (0.5, 0.45)
        let co = Rings.offset(cc, bond, -90)
        let oEster = Rings.offset(co, bond, -30)
        let ipso = Rings.offset(cc, bond, 150), cP = Rings.offset(ipso, bond, 150)
        let c2 = Rings.offset(cc, bond, 30), cQ = Rings.offset(c2, bond, 30)
        let atoms = [cc, co, Rings.offset(co, bond, -150), oEster, Rings.offset(oEster, bond, -90)]
            + Rings.around(cP, bond, start: -30) + Rings.around(cQ, bond, start: 210) + [cP, cQ]
        // 0 the central carbon; 1-4 the ester; 5-10 phenyl; 11-16 piperidine
        // (12 its nitrogen); 17-18 ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (0, 5, .single), (5, 6, .inside(17)), (6, 7, .single), (7, 8, .inside(17)), (8, 9, .single), (9, 10, .inside(17)), (10, 5, .single),
            (0, 11, .single), (11, 12, .single), (12, 13, .single), (13, 14, .single), (14, 15, .single), (15, 16, .single), (16, 11, .single),
            (0, 1, .single), (1, 2, .double), (1, 3, .single), (3, 4, .single),
        ], hetero: [2, 3, 12], extent: 0.66)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        skeleton.draw(context, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.5))
        let focus = Ease.outBack((t - 1.9) / 0.5) * (1 - Ease.inOut((t - 3.3) / 0.4))
        guard focus > 0 else { return }
        let reach = 0.5 - 0.04 * focus
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
            let corner = (0.5 + reach * sx, 0.5 + reach * sy)
            u.stroke(context, u.line((corner.0, corner.1 - 0.08 * sy), corner, (corner.0 - 0.08 * sx, corner.1)),
                     clay.opacity(min(1, focus)), 0.035)
        }
    }
}

/// Modafinil: a diphenylmethyl on a sulfinyl, then an acetamide. Built, a
/// small clay sun comes up in the corner: awake.
enum Modafinil {
    static let duration = 4.0
    private static let skeleton: Skeleton = {
        let cb = (0.42, 0.5)
        let ipsoA = Rings.offset(cb, bond, 240), cA = Rings.offset(ipsoA, bond, 240)
        let ipsoB = Rings.offset(cb, bond, 120), cB = Rings.offset(ipsoB, bond, 120)
        let s = Rings.offset(cb, bond, 0), ch2 = Rings.offset(s, bond, 60), amide = Rings.offset(ch2, bond, 0)
        let atoms = [cb, s, Rings.offset(s, bond, 300), ch2, amide, Rings.offset(amide, bond, 300), Rings.offset(amide, bond, 60)]
            + Rings.around(cA, bond, start: 60) + Rings.around(cB, bond, start: 300) + [cA, cB]
        // 0 the benzhydryl carbon; 1 S, 2 its O; 3 CH₂; 4-6 the amide;
        // 7-12 and 13-18 the phenyls; 19-20 ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (0, 7, .single), (7, 8, .inside(19)), (8, 9, .single), (9, 10, .inside(19)), (10, 11, .single), (11, 12, .inside(19)), (12, 7, .single),
            (0, 13, .single), (13, 14, .inside(20)), (14, 15, .single), (15, 16, .inside(20)), (16, 17, .single), (17, 18, .inside(20)), (18, 13, .single),
            (0, 1, .single), (1, 2, .double), (1, 3, .single), (3, 4, .single), (4, 5, .double), (4, 6, .single),
        ], hetero: [1, 2, 5, 6], extent: 0.7)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let rise = Ease.out((t - 2.0) / 0.8) * (1 - Ease.inOut((t - 3.5) / 0.4))
        if rise > 0 {
            let sun = (0.86, 0.3 - 0.14 * rise)
            var sky = context
            sky.clip(to: Path(CGRect(x: u.origin.x, y: u.origin.y, width: u.side, height: u.len(0.3))))
            sky.fill(u.circle(sun.0, sun.1 + 0.04, 0.05), with: .color(clay))
            for k in 0..<5 {
                let a = -180 + 45 * Double(k)
                let from = Rings.offset((sun.0, sun.1 + 0.04), 0.075, a), to = Rings.offset((sun.0, sun.1 + 0.04), 0.1, a)
                u.stroke(sky, u.line(from, to), clay.opacity(rise), 0.025)
            }
        }
        skeleton.draw(context, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.6))
    }
}

/// Nicotine: a pyridine joined to an N-methylpyrrolidine. Built, it hums:
/// two small clay arcs buzz either side.
enum Nicotine {
    static let duration = 3.6
    private static let skeleton: Skeleton = {
        let hex = Rings.hexagon((0.38, 0.52), bond)
        let c2 = Rings.offset(hex[1], bond, -30)
        let r5 = bond / (2 * sin(.pi / 5))
        let c5 = Rings.offset(c2, r5, -30)
        let pent = Rings.around(c5, r5, sides: 5, start: 150)
        let atoms = hex + pent + [Rings.offset(pent[4], bond, 78), (0.38, 0.52)]
        // 0-5 pyridine (3 its nitrogen); 6-10 pyrrolidine (6 joins, 10 its
        // nitrogen); 11 the methyl; 12 the ring centre.
        return Skeleton(atoms: atoms, bonds: [
            (0, 1, .single), (1, 2, .inside(12)), (2, 3, .single), (3, 4, .inside(12)), (4, 5, .single), (5, 0, .inside(12)),
            (1, 6, .single), (6, 7, .single), (7, 8, .single), (8, 9, .single), (9, 10, .single), (10, 6, .single), (10, 11, .single),
        ], hetero: [3, 10], extent: 0.64)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        skeleton.draw(context, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.3))
        let hum = Ease.clamp((t - 1.8) / 0.2) * (1 - Ease.clamp((t - 3.2) / 0.3))
        guard hum > 0 else { return }
        for side in [-1.0, 1.0] {
            for k in 0..<2 {
                let r = 0.08 + 0.05 * Double(k) + 0.01 * sin(t * 30 + Double(k))
                var arc = Path()
                let start = side < 0 ? 150.0 : -30.0
                arc.addArc(center: u.pt(0.5 + 0.34 * side, 0.5), radius: u.len(r), startAngle: .degrees(start), endAngle: .degrees(start + 60), clockwise: false)
                u.stroke(context, arc, clay.opacity(hum * (1 - 0.4 * Double(k))), 0.025)
            }
        }
    }
}

/// Fluoxetine (Prozac): phenyl and a trifluoromethyl-phenoxy on one carbon,
/// a chain to its methylamine. Built, clay serotonin gathers round it and
/// stays: reuptake blocked.
enum Fluoxetine {
    static let duration = 4.0
    private static let skeleton: Skeleton = {
        let c3 = (0.42, 0.42)
        let ipso = Rings.offset(c3, bond, 210), cP = Rings.offset(ipso, bond, 210)
        let c2 = Rings.offset(c3, bond, 330), c1 = Rings.offset(c2, bond, 30), n = Rings.offset(c1, bond, 330)
        let o = Rings.offset(c3, bond, 90)
        let aryl = Rings.offset(o, bond, 30), cA = Rings.offset(aryl, bond, 30)
        let ring = Rings.around(cA, bond, start: 210)
        let cf = Rings.offset(ring[3], bond, 30)
        let atoms = [c3, c2, c1, n, Rings.offset(n, bond, 30), o] + Rings.around(cP, bond, start: 30) + ring
            + [cf, Rings.offset(cf, bond, -60), Rings.offset(cf, bond, 30), Rings.offset(cf, bond, 120), cP, cA]
        // 0 C3; 1-2 the chain; 3 N, 4 its methyl; 5 the ether O; 6-11
        // phenyl; 12-17 the aryl ring; 18 CF₃, 19-21 its fluorines; 22-23
        // ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (0, 6, .single), (6, 7, .inside(22)), (7, 8, .single), (8, 9, .inside(22)), (9, 10, .single), (10, 11, .inside(22)), (11, 6, .single),
            (0, 1, .single), (1, 2, .single), (2, 3, .single), (3, 4, .single),
            (0, 5, .single), (5, 12, .single), (12, 13, .inside(23)), (13, 14, .single), (14, 15, .inside(23)), (15, 16, .single),
            (16, 17, .inside(23)), (17, 12, .single), (15, 18, .single), (18, 19, .single), (18, 20, .single), (18, 21, .single),
        ], hetero: [3, 5, 19, 20, 21], extent: 0.74)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        skeleton.draw(context, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.7))
        let fade = 1 - Ease.inOut((t - 3.5) / 0.4)
        for k in 0..<5 {
            let arrive = Ease.out((t - 2.0 - 0.18 * Double(k)) / 0.6)
            guard arrive > 0 else { continue }
            let a = Double(k) * 72 + 20
            let home = Rings.offset((0.5, 0.5), 0.44, a)
            let start = Rings.offset((0.5, 0.5), 0.75, a)
            let p = (start.0 + (home.0 - start.0) * arrive, start.1 + (home.1 - start.1) * arrive + 0.01 * sin(t * 3 + Double(k)))
            context.fill(u.circle(p.0, p.1, 0.022), with: .color(clay.opacity(fade)))
        }
    }
}

/// Sertraline (Zoloft): a tetralin with its methylamine and a
/// dichlorophenyl. Built, a clay line beneath it swings, then calms flat.
enum Sertraline {
    static let duration = 4.0
    private static let skeleton: Skeleton = {
        let r = bond, step = sqrt(3) * r
        let cA = (0.3, 0.36), cB = (0.3 + step, 0.36)
        let a = Rings.hexagon(cA, r), b = Rings.hexagon(cB, r)
        let n = Rings.offset(b[0], bond, -90)
        let ipso = Rings.offset(b[3], bond, 90), cC = (ipso.0, ipso.1 + r)
        let c = Rings.hexagon(cC, r)
        let atoms = a + [b[0], b[1], b[2], b[3], n, Rings.offset(n, bond, -30)] + c
            + [Rings.offset(c[2], bond, 30), Rings.offset(c[3], bond, 90), cA, cC]
        // 0-5 the aromatic ring; 6-9 the saturated ring's own carbons (6 is
        // C1, 9 is C4); 10 N, 11 its methyl; 12-17 the dichlorophenyl;
        // 18-19 the chlorines; 20-21 ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (0, 1, .inside(20)), (1, 2, .single), (2, 3, .inside(20)), (3, 4, .single), (4, 5, .inside(20)), (5, 0, .single),
            (1, 6, .single), (6, 7, .single), (7, 8, .single), (8, 9, .single), (9, 2, .single),
            (6, 10, .single), (10, 11, .single),
            (9, 12, .single), (12, 13, .inside(21)), (13, 14, .single), (14, 15, .inside(21)), (15, 16, .single), (16, 17, .inside(21)),
            (17, 12, .single), (14, 18, .single), (15, 19, .single),
        ], hetero: [10, 18, 19], extent: 0.7)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        var molecule = context
        molecule.translateBy(x: u.len(-0.1), y: 0)
        skeleton.draw(molecule, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.7))
        let show = Ease.clamp((t - 1.9) / 0.3) * (1 - Ease.inOut((t - 3.5) / 0.4))
        guard show > 0 else { return }
        let calm = 1 - Ease.inOut((t - 2.2) / 1.1)
        let wave = stride(from: 0.0, through: 1.0, by: 0.02).map { s in
            (0.72 + 0.22 * s, 0.5 + 0.12 * calm * sin(s * 3 * 2 * .pi + t * 5) * sin(.pi * s))
        }
        u.stroke(context, u.polyline(wave), clay.opacity(show), 0.03)
    }
}

/// Escitalopram (Lexapro): a phthalane carrying a nitrile, a
/// fluorophenyl and a dimethylaminopropyl. Built, soft clay sparkles.
enum Escitalopram {
    static let duration = 4.2
    private static let skeleton: Skeleton = {
        let hexC = (0.34, 0.56)
        let hex = Rings.hexagon(hexC, bond)
        let five = Rings.fivefold(onto: hex)
        let c1 = five.atoms[0]
        let cn = Rings.offset(hex[4], bond, 150)
        let ipso = Rings.offset(c1, bond, -20), cF = Rings.offset(ipso, bond, -20)
        let ring = Rings.around(cF, bond, start: 160)
        let ca = Rings.offset(c1, bond, -130), cb = Rings.offset(ca, bond, -70)
        let cc = Rings.offset(cb, bond, -130), n = Rings.offset(cc, bond, -70)
        let atoms = hex + [c1, five.atoms[1], five.atoms[2], cn, Rings.offset(cn, bond, 150)] + ring
            + [Rings.offset(ring[3], bond, -20), ca, cb, cc, n, Rings.offset(n, bond, -130), Rings.offset(n, bond, -10),
               hexC, five.centre, cF]
        // 0-5 the benzene ring (4 carries the nitrile); 6 C1, 7 the ring O,
        // 8 C3; 9-10 the nitrile; 11-16 the fluorophenyl, 17 its F; 18-20
        // the propyl, 21 N, 22-23 its methyls; 24-26 ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (0, 1, .inside(24)), (1, 2, .single), (2, 3, .inside(24)), (3, 4, .single), (4, 5, .inside(24)), (5, 0, .single),
            (1, 6, .single), (6, 7, .single), (7, 8, .single), (8, 2, .single),
            (4, 9, .single), (9, 10, .triple),
            (6, 11, .single), (11, 12, .inside(26)), (12, 13, .single), (13, 14, .inside(26)), (14, 15, .single), (15, 16, .inside(26)),
            (16, 11, .single), (14, 17, .single),
            (6, 18, .single), (18, 19, .single), (19, 20, .single), (20, 21, .single), (21, 22, .single), (21, 23, .single),
        ], hetero: [7, 10, 17, 21], extent: 0.74)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        skeleton.draw(context, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.9))
        for (x, y, at, s) in [(0.14, 0.18, 2.3, 0.06), (0.88, 0.84, 2.55, 0.055), (0.12, 0.86, 2.8, 0.05)] {
            let age = (t - at) / 0.9
            guard age > 0, age < 1 else { continue }
            context.fill(Sparkles.star(u, x, y, s * sin(.pi * age)), with: .color(clay))
        }
    }
}
