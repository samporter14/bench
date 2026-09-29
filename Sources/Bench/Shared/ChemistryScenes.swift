// ChemistryScenes.swift
// ScienceStatus — molecules drawing themselves bond by bond as skeletal
// formulas: the carbon skeleton in the tint, oxygen and nitrogen as clay
// dots. Once made, each does something in character.

import SwiftUI

/// A skeletal formula in the unit square, its bonds in drawing order.
struct Skeleton {
    enum Kind {
        case single
        /// A double bond drawn as two lines either side of the bond.
        case double
        /// A ring double bond: a shorter second line towards `atoms[index]`,
        /// the ring's centre (listed with the atoms, never drawn).
        case inside(Int)
        /// A triple bond, as in a nitrile: three lines.
        case triple
    }

    let atoms: [(Double, Double)]
    let bonds: [(Int, Int, Kind)]
    /// Oxygen and nitrogen, drawn as clay dots.
    let hetero: Set<Int>

    /// The atoms moved and scaled together so the whole fits `extent` of
    /// the square, centred.
    init(atoms: [(Double, Double)], bonds: [(Int, Int, Kind)], hetero: Set<Int>, extent: Double = 0.8) {
        let xs = atoms.map(\.0), ys = atoms.map(\.1)
        let (minX, maxX, minY, maxY) = (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
        let scale = extent / max(maxX - minX, maxY - minY, 0.001)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        self.atoms = atoms.map { (0.5 + ($0.0 - cx) * scale, 0.5 + ($0.1 - cy) * scale) }
        self.bonds = bonds
        self.hetero = hetero
    }

    /// Draws the first `built` bonds; a fraction draws the next part way.
    /// A clay atom appears as soon as a bond reaches it.
    func draw(_ context: GraphicsContext, _ u: UnitSquare, tint: Color, built: Double) {
        var reached = Set<Int>()
        for (i, bond) in bonds.enumerated() {
            let k = Ease.clamp(built - Double(i))
            guard k > 0 else { break }
            let a = atoms[bond.0], b = atoms[bond.1]
            let end = (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k)
            let dx = b.0 - a.0, dy = b.1 - a.1
            let length = max(hypot(dx, dy), 0.0001)
            let normal = (-dy / length, dx / length)
            switch bond.2 {
            case .single:
                u.stroke(context, u.line(a, end), tint, 0.05)
            case .double:
                for side in [-1.0, 1.0] {
                    let o = (normal.0 * 0.022 * side, normal.1 * 0.022 * side)
                    u.stroke(context, u.line((a.0 + o.0, a.1 + o.1), (end.0 + o.0, end.1 + o.1)), tint, 0.04)
                }
            case .triple:
                for side in [-1.0, 0, 1.0] {
                    let o = (normal.0 * 0.03 * side, normal.1 * 0.03 * side)
                    u.stroke(context, u.line((a.0 + o.0, a.1 + o.1), (end.0 + o.0, end.1 + o.1)), tint, 0.03)
                }
            case .inside(let centre):
                u.stroke(context, u.line(a, end), tint, 0.05)
                let c = atoms[centre]
                let mid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
                let towards = (c.0 - mid.0) * normal.0 + (c.1 - mid.1) * normal.1 > 0 ? 1.0 : -1.0
                let o = (normal.0 * 0.045 * towards, normal.1 * 0.045 * towards)
                let from = (a.0 + dx * 0.2 + o.0, a.1 + dy * 0.2 + o.1)
                let inner = min(k, 0.8)
                if inner > 0.2 {
                    let to = (a.0 + dx * inner + o.0, a.1 + dy * inner + o.1)
                    u.stroke(context, u.line(from, to), tint, 0.04)
                }
            }
            reached.insert(bond.0)
            if k >= 1 { reached.insert(bond.1) }
        }
        for index in hetero where reached.contains(index) {
            let p = atoms[index]
            context.fill(u.circle(p.0, p.1, 0.042), with: .color(clay))
        }
    }

    /// How many bonds are built `t` seconds in, drawing from `start` over
    /// `length` seconds.
    func built(at t: Double, start: Double, length: Double) -> Double {
        Double(bonds.count) * Ease.clamp((t - start) / length)
    }
}

/// Ring vertices for skeletal formulas.
enum Rings {
    /// A hexagon with a vertex at the top: top, upper right, lower right,
    /// bottom, lower left, upper left.
    static func hexagon(_ c: (Double, Double), _ r: Double) -> [(Double, Double)] {
        (0..<6).map { i in
            let a = (-90 + 60 * Double(i)) * .pi / 180
            return (c.0 + r * cos(a), c.1 + r * sin(a))
        }
    }

    /// The five-membered ring fused onto a hexagon's right-hand edge: its
    /// centre and its three other atoms, upper, right and lower.
    static func fivefold(onto hexagon: [(Double, Double)]) -> (centre: (Double, Double), atoms: [(Double, Double)]) {
        let top = hexagon[1], bottom = hexagon[2]
        let side = bottom.1 - top.1
        let apothem = side / (2 * tan(.pi / 5))
        let radius = side / (2 * sin(.pi / 5))
        let centre = (top.0 + apothem, (top.1 + bottom.1) / 2)
        let atoms = [-72.0, 0, 72].map { degrees -> (Double, Double) in
            let a = degrees * .pi / 180
            return (centre.0 + radius * cos(a), centre.1 + radius * sin(a))
        }
        return (centre, atoms)
    }

    static func offset(_ p: (Double, Double), _ length: Double, _ degrees: Double) -> (Double, Double) {
        let a = degrees * .pi / 180
        return (p.0 + length * cos(a), p.1 + length * sin(a))
    }
}

/// Ethanol: two carbons and an OH, drawn, and then it gets a little tipsy,
/// swaying and hiccuping.
enum Ethanol {
    static let duration = 3.6
    private static let skeleton = Skeleton(
        atoms: [(0, 0.05), (0.0866, 0), (0.1732, 0.05), (0.2598, 0)],
        bonds: [(0, 1, .single), (1, 2, .single), (2, 3, .single)],
        hetero: [2], extent: 0.62)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let tipsy = Ease.clamp((t - 1.2) / 0.4)
        let hiccup = 0.05 * sin(.pi * Ease.clamp((t - 2.6) / 0.25))
        var glass = context
        let pivot = u.pt(0.5, 0.5 - hiccup)
        glass.translateBy(x: pivot.x, y: pivot.y)
        glass.rotate(by: .degrees(13 * sin(2 * .pi * (t - 1.2) / 1.6) * tipsy))
        glass.translateBy(x: -pivot.x, y: -u.pt(0.5, 0.5).y)
        skeleton.draw(glass, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 0.9))
        // The hydroxyl's hydrogen, once the oxygen is there.
        if skeleton.built(at: t, start: 0.2, length: 0.9) >= 3 {
            let h = skeleton.atoms[3]
            glass.fill(u.circle(h.0, h.1, 0.028), with: .color(tint))
        }
    }
}

/// Caffeine: the fused rings, two carbonyls and three methyls, drawn; then
/// it jitters, as caffeine does.
enum Caffeine {
    static let duration = 3.6
    private static let skeleton: Skeleton = {
        let hex = Rings.hexagon((0.36, 0.5), 0.13)
        let five = Rings.fivefold(onto: hex)
        let n7 = five.atoms[0], c8 = five.atoms[1], n9 = five.atoms[2]
        let atoms = hex + [n7, c8, n9,
                           Rings.offset(hex[0], 0.12, -90), Rings.offset(hex[4], 0.12, 150),
                           Rings.offset(hex[5], 0.12, 210), Rings.offset(hex[3], 0.12, 90),
                           Rings.offset(n7, 0.12, -72),
                           (0.36, 0.5), five.centre]
        // 0-5 ring: C6, C5, C4, N3, C2, N1; 6 N7, 7 C8, 8 N9; 9 O6, 10 O2;
        // 11-13 methyls; 14 and 15 the ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (5, 0, .single), (0, 1, .single), (1, 2, .inside(14)), (2, 3, .single), (3, 4, .single),
            (4, 5, .single), (1, 6, .single), (6, 7, .single), (7, 8, .inside(15)), (8, 2, .single),
            (0, 9, .double), (4, 10, .double), (5, 11, .single), (3, 12, .single), (6, 13, .single),
        ], hetero: [5, 3, 6, 8, 9, 10])
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let wired = Ease.clamp((t - 1.9) / 0.2)
        var jitter = context
        jitter.translateBy(x: u.len(0.012 * sin(t * 57) * wired), y: u.len(0.012 * sin(t * 63 + 1) * wired))
        skeleton.draw(jitter, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.6))
    }
}

/// Serotonin: the indole, its hydroxyl and the ethylamine arm, drawn; then
/// two clay sparkles, a small discovery.
enum Serotonin {
    static let duration = 3.6
    private static let skeleton: Skeleton = {
        let hex = Rings.hexagon((0.3, 0.56), 0.12)
        let five = Rings.fivefold(onto: hex)
        let c3 = five.atoms[0], c2 = five.atoms[1], n1 = five.atoms[2]
        let ca = Rings.offset(c3, 0.12, -90)
        let cb = Rings.offset(ca, 0.12, -30)
        let amine = Rings.offset(cb, 0.12, 30)
        let oxygen = Rings.offset(hex[5], 0.12, 210)
        let atoms = hex + [c3, c2, n1, ca, cb, amine, oxygen, (0.3, 0.56), five.centre]
        // 0-5 benzene; 6 C3, 7 C2, 8 N1; 9-11 the arm to its NH2; 12 the
        // OH oxygen; 13 and 14 the ring centres.
        return Skeleton(atoms: atoms, bonds: [
            (0, 1, .single), (1, 2, .inside(13)), (2, 3, .single), (3, 4, .inside(13)), (4, 5, .single),
            (5, 0, .inside(13)), (1, 6, .single), (6, 7, .inside(14)), (7, 8, .single), (8, 2, .single),
            (6, 9, .single), (9, 10, .single), (10, 11, .single), (5, 12, .single),
        ], hetero: [8, 11, 12])
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        skeleton.draw(context, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 1.6))
        for (x, y, at, s) in [(0.16, 0.2, 2.0, 0.07), (0.86, 0.78, 2.2, 0.06), (0.84, 0.16, 2.45, 0.05)] {
            let age = (t - at) / 0.8
            guard age > 0, age < 1 else { continue }
            context.fill(Sparkles.star(u, x, y, s * sin(.pi * age)), with: .color(clay))
        }
    }
}

/// THC: three fused rings, the pyran oxygen, the hydroxyl and the pentyl
/// tail, drawn; then it floats, very relaxed.
enum THC {
    static let duration = 4.0
    private static let skeleton: Skeleton = {
        let r = 0.1, step = sqrt(3) * r
        let b = Rings.hexagon((0.42, 0.56), r)
        let c = Rings.hexagon((0.42 + step, 0.56), r)
        let a = Rings.hexagon((0.42 - step / 2, 0.56 - 1.5 * r), r)
        let hydroxyl = Rings.offset(c[0], r, -90)
        var tail = [Rings.offset(c[2], 0.085, 30)]
        for k in 1..<5 { tail.append(Rings.offset(tail[k - 1], 0.085, k % 2 == 1 ? -30 : 30)) }
        let atoms: [(Double, Double)] = [
            b[0], b[1], b[2], b[3], b[4], b[5],        // 0-5 ring B (3 is the oxygen)
            c[0], c[1], c[2], c[3],                    // 6-9 ring C (shares 1 and 2)
            a[0], a[1], a[4], a[5],                    // 10-13 ring A (shares 0 and 5)
            Rings.offset(a[0], r, -90),                // 14 ring A's methyl
            Rings.offset(b[4], r, 120), Rings.offset(b[4], r, 180), // 15-16 the gem-dimethyl
            hydroxyl,                                  // 17
        ] + tail + [(0.42, 0.56), (0.42 + step, 0.56), (0.42 - step / 2, 0.56 - 1.5 * r)] // 18-22 tail; 23-25 centres
        return Skeleton(atoms: atoms, bonds: [
            (6, 7, .inside(24)), (7, 8, .single), (8, 9, .inside(24)), (9, 2, .single), (2, 1, .inside(24)),
            (1, 6, .single),
            (1, 0, .single), (2, 3, .single), (3, 4, .single), (4, 5, .single), (5, 0, .single),
            (0, 11, .single), (11, 10, .single), (10, 13, .single), (13, 12, .inside(25)), (12, 5, .single),
            (10, 14, .single), (4, 15, .single), (4, 16, .single), (6, 17, .single),
            (8, 18, .single), (18, 19, .single), (19, 20, .single), (20, 21, .single), (21, 22, .single),
        ], hetero: [3, 17], extent: 0.84)
    }()

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let chill = Ease.clamp((t - 2.2) / 0.6)
        var float = context
        let pivot = u.pt(0.5, 0.5)
        float.translateBy(x: pivot.x, y: pivot.y - u.len(0.03 * sin((t - 2.2) * 1.8) * chill))
        float.rotate(by: .degrees(4 * sin((t - 2.2) * 1.2) * chill))
        float.translateBy(x: -pivot.x, y: -pivot.y)
        skeleton.draw(float, u, tint: tint, built: skeleton.built(at: t, start: 0.2, length: 2.0))
    }
}

/// Oxytocin, the love hormone: its nine residues join one by one, the
/// chain folds into its ring with the clay disulfide bridge, and then it
/// rearranges into a heart that beats twice.
enum Oxytocin {
    static let duration = 4.4
    private static let count = 9

    private static let chain: [(Double, Double)] = (0..<count).map { k in
        (0.14 + 0.09 * Double(k), 0.5 + (k % 2 == 0 ? -0.05 : 0.05))
    }
    /// Six residues in a ring closed by the bridge between the two
    /// cysteines (0 and 5), the last three trailing off to the right.
    private static let folded: [(Double, Double)] = (0..<6).map { k -> (Double, Double) in
        let a = (330 - 60 * Double(k)) * .pi / 180
        return (0.36 + 0.15 * cos(a), 0.46 + 0.15 * sin(a))
    } + [(0.6, 0.6), (0.71, 0.55), (0.82, 0.62)]
    private static let heart: [(Double, Double)] = (0..<count).map { j in
        let s = 2 * .pi * Double(j) / Double(count) + 0.35
        let x = 16 * pow(sin(s), 3)
        let y = 13 * cos(s) - 5 * cos(2 * s) - 2 * cos(3 * s) - cos(4 * s)
        return (0.5 + x / 17 * 0.36, 0.47 - y / 17 * 0.36)
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let fold = Ease.inOut((t - 1.6) / 0.6)
        let love = Ease.inOut((t - 2.7) / 0.6)
        var beat = 0.0
        for b in [3.45, 3.8] { beat = max(beat, sin(.pi * Ease.clamp((t - b) / 0.22))) }
        let grow = 1 + 0.1 * beat

        let beads = (0..<count).map { k -> (Double, Double) in
            let c = chain[k], f = folded[k], h = heart[k]
            var p = (c.0 + (f.0 - c.0) * fold, c.1 + (f.1 - c.1) * fold)
            p = (p.0 + (h.0 - p.0) * love, p.1 + (h.1 - p.1) * love)
            return (0.5 + (p.0 - 0.5) * grow, 0.47 + (p.1 - 0.47) * grow)
        }
        let made = min(count, Int(t / 0.15) + 1)
        let shown = Array(beads.prefix(made))
        if shown.count > 1 { u.stroke(context, u.polyline(shown), tint, 0.045) }
        // The heart closes its outline; the bridge gives way as it forms.
        if love > 0 {
            u.stroke(context, u.line(beads[count - 1], beads[0]), tint.opacity(love), 0.045)
        }
        let bridge = Ease.clamp((t - 2.1) / 0.2) * (1 - love)
        if bridge > 0 { u.stroke(context, u.line(beads[0], beads[5]), clay.opacity(bridge), 0.06) }
        for (k, p) in shown.enumerated() {
            let cysteine = k == 0 || k == 5
            let pop = Ease.outBack((t - 0.15 * Double(k)) / 0.2)
            context.fill(u.circle(p.0, p.1, (cysteine ? 0.048 : 0.04) * pop), with: .color(cysteine ? clay : tint))
        }
    }
}

/// A titration: drops fall from the burette into the swirling flask, and
/// the last one tips it over the endpoint, turning the flask clay.
enum Titration {
    static let duration = 4.0
    private static let drops = 7

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let used = Ease.clamp((t - 0.2) / (0.35 * Double(drops)))
        let top = 0.08 + 0.12 * used
        context.fill(u.capsule(0.5, (top + 0.34) / 2, 0.05, 0.34 - top, corner: 0.01), with: .color(tint.opacity(0.3)))
        u.stroke(context, u.line((0.47, 0.02), (0.47, 0.34), (0.495, 0.4)), tint, 0.04)
        u.stroke(context, u.line((0.53, 0.02), (0.53, 0.34), (0.505, 0.4)), tint, 0.04)
        u.stroke(context, u.line((0.43, 0.36), (0.57, 0.36)), tint, 0.05)

        for k in 0..<drops {
            let age = (t - 0.3 - 0.35 * Double(k)) / 0.3
            guard age > 0, age < 1 else { continue }
            context.fill(u.circle(0.5, 0.42 + 0.3 * age * age, 0.022), with: .color(tint))
        }

        var outline = context.resolve(Image(systemName: "flask"))
        var fill = context.resolve(Image(systemName: "flask.fill"))
        outline.shading = .color(tint)
        let box = CGRect(x: u.pt(0.27, 0.48).x, y: u.pt(0.27, 0.48).y, width: u.len(0.46), height: u.len(0.48))
        let scale = min(box.width / max(outline.size.width, 1), box.height / max(outline.size.height, 1))
        let w = outline.size.width * scale, h = outline.size.height * scale
        let rect = CGRect(x: box.midX - w / 2, y: box.maxY - h, width: w, height: h)
        let surface = rect.minY + rect.height * (0.58 + 0.02 * sin(t * 6))
        var liquid = context
        liquid.clip(to: Path(CGRect(x: rect.minX, y: surface, width: rect.width, height: rect.maxY - surface)))
        fill.shading = .color(tint.opacity(0.22))
        liquid.draw(fill, in: rect)
        let endpoint = Ease.inOut((t - 0.3 - 0.35 * Double(drops - 1) - 0.3) / 0.35)
        if endpoint > 0 {
            fill.shading = .color(clay.opacity(endpoint))
            liquid.draw(fill, in: rect)
        }
        context.draw(outline, in: rect)
    }
}

/// A distillation: the clay mixture boils on the hot plate, its condensate
/// runs down the condenser a drop at a time, and the receiver fills.
enum Distillation {
    static let duration = 4.0
    private static let start = (0.27, 0.31), end = (0.78, 0.57)

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        context.fill(u.capsule(0.26, 0.9, 0.36, 0.05, corner: 0.02), with: .color(tint))

        // The boiling flask.
        let centre = (0.26, 0.69), radius = 0.15
        var liquid = context
        liquid.clip(to: Path(CGRect(x: u.origin.x, y: u.pt(0, 0.68).y, width: u.side, height: u.side)))
        liquid.fill(u.circle(centre.0, centre.1, radius - 0.02), with: .color(clay))
        for k in 0..<3 {
            let phase = (t / 0.8 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let x = 0.26 + [-0.05, 0.04, -0.005][k]
            liquid.fill(u.circle(x, 0.8 - 0.11 * phase, 0.018 + 0.008 * phase), with: .color(ivory.opacity(0.9 * (1 - phase))))
        }
        u.stroke(context, u.circle(centre.0, centre.1, radius), tint, 0.05)
        u.stroke(context, u.line((0.23, 0.55), (0.23, 0.3)), tint, 0.04)
        u.stroke(context, u.line((0.29, 0.55), (0.29, 0.36)), tint, 0.04)

        // The condenser: a tube running down to the right.
        let dx = end.0 - start.0, dy = end.1 - start.1
        let length = hypot(dx, dy)
        let normal = (-dy / length * 0.03, dx / length * 0.03)
        for side in [-1.0, 1.0] {
            u.stroke(context, u.line((start.0 + normal.0 * side, start.1 + normal.1 * side),
                                     (end.0 + normal.0 * side, end.1 + normal.1 * side)), tint, 0.04)
        }

        // The receiver, filling.
        let fill = Ease.inOut((t - 0.9) / 3.0)
        let level = 0.9 - 0.12 * fill
        context.fill(u.capsule(0.8, (level + 0.9) / 2, 0.16, 0.9 - level, corner: 0.01), with: .color(clay))
        u.stroke(context, u.line((0.71, 0.66), (0.71, 0.92), (0.89, 0.92), (0.89, 0.66)), tint, 0.045)

        // Drops: down the condenser, then off its end into the receiver.
        for k in 0..<8 {
            let age = t - 0.3 - 0.45 * Double(k)
            guard age > 0 else { continue }
            if age < 0.8 {
                let s = age / 0.8
                context.fill(u.circle(start.0 + dx * s, start.1 + dy * s, 0.02), with: .color(clay))
            } else if age < 1.05 {
                let f = (age - 0.8) / 0.25
                context.fill(u.circle(end.0 + 0.01, end.1 + 0.03 + (level - end.1 - 0.03) * f * f, 0.02), with: .color(clay))
            }
        }
    }
}
