// MethodsScenes.swift
// ScienceStatus — chemistry and physical methods. Each draws in a unit
// square (see `UnitSquare`): apparatus and atoms in the tint, the signal,
// the product or the moving charge in clay.

import SwiftUI

/// Click chemistry: an azide and an alkyne come together at a copper
/// catalyst and snap into a five-membered triazole, its three nitrogens
/// in clay.
enum ClickChemistry {
    static let duration = 3.6

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let come = Ease.inOut((t - 0.2) / 1.0)
        let snap = Ease.inOut((t - 1.3) / 0.5)
        let ring = (0..<5).map { k -> (Double, Double) in
            let a = (Double(k) * 72 - 162) * .pi / 180
            return (0.5 + 0.1 * cos(a), 0.52 + 0.1 * sin(a))
        }
        // Azide: three nitrogens in a row; alkyne: two carbons.
        let azide = [(0.28, 0.52), (0.33, 0.52), (0.38, 0.52)].map { ($0.0 + 0.06 * come, $0.1) }
        let alkyne = [(0.64, 0.52), (0.72, 0.52)].map { ($0.0 - 0.06 * come, $0.1) }
        let loose = azide + alkyne
        let closed = [ring[0], ring[4], ring[3], ring[1], ring[2]]
        let atoms = (0..<5).map { i in (loose[i].0 + (closed[i].0 - loose[i].0) * snap, loose[i].1 + (closed[i].1 - loose[i].1) * snap) }
        u.stroke(context, u.line((0.06, 0.52), atoms[0]), tint, 0.04)
        u.stroke(context, u.line(atoms[4], (0.94, 0.52)), tint, 0.04)
        if snap < 0.95 {
            u.stroke(context, u.polyline(Array(atoms[0...2])), tint, 0.035)
            u.stroke(context, u.line(atoms[3], atoms[4]), tint, 0.035)
        }
        if snap > 0.05 {
            var triazole = u.polyline(closed)
            triazole.closeSubpath()
            u.stroke(context, triazole, tint.opacity(snap), 0.04)
        }
        for (i, atom) in atoms.enumerated() {
            context.fill(u.circle(atom.0, atom.1, i < 3 ? 0.03 : 0.02), with: .color(i < 3 ? clay : tint))
        }
        u.stroke(context, u.circle(0.5, 0.3, 0.035), tint, 0.03)
        let click = (t - 1.8) / 0.5
        if click > 0, click < 1 { u.stroke(context, u.circle(0.5, 0.52, 0.14 + 0.08 * click), clay.opacity(1 - click), 0.03) }
    }
}

/// The Belousov–Zhabotinsky reaction: clay chemical waves ring out from
/// two points in a small dish, and where they meet they cancel.
enum BZReaction {
    static let duration = 4.0
    private static let centres = [(0.37, 0.4), (0.64, 0.62)]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.43), tint, 0.05)
        for (c, centre) in centres.enumerated() {
            let other = centres[1 - c]
            for k in 0..<5 {
                let r = ((t + Double(c) * 0.5) * 0.12 + Double(k) * 0.12).truncatingRemainder(dividingBy: 0.6)
                guard r > 0.02 else { continue }
                var run: [(Double, Double)] = []
                for step in 0...72 {
                    let a = Double(step) / 72 * 2 * .pi
                    let p = (centre.0 + r * cos(a), centre.1 + r * sin(a))
                    let mine = hypot(p.0 - other.0, p.1 - other.1) >= r
                    let inside = hypot(p.0 - 0.5, p.1 - 0.5) < 0.4
                    if mine && inside {
                        run.append(p)
                    } else {
                        if run.count > 1 { u.stroke(context, u.polyline(run), clay.opacity(1 - r / 0.6), 0.035) }
                        run = []
                    }
                }
                if run.count > 1 { u.stroke(context, u.polyline(run), clay.opacity(1 - r / 0.6), 0.035) }
            }
            context.fill(u.circle(centre.0, centre.1, 0.02), with: .color(clay))
        }
    }
}

/// Host–guest chemistry: a crown ether, its six oxygens drawn larger,
/// flexes; an ion too big for its hole bumps the ring and bounces away; the
/// clay ion that fits slips inside, the ring tightens round it, and dashed
/// lines show the oxygens holding it.
enum HostGuest {
    static let duration = 3.8

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let caught = Ease.inOut((t - 2.2) / 0.45)
        let radius = 0.2 + 0.02 * sin(t * 3) * (1 - caught) - 0.03 * caught
        let atoms = (0..<12).map { k -> (Double, Double) in
            let a = Double(k) / 12 * 2 * .pi
            return (0.5 + radius * cos(a), 0.5 + radius * sin(a))
        }
        // Held: each oxygen to the ion.
        if caught > 0 {
            for (k, atom) in atoms.enumerated() where k % 2 == 0 {
                context.stroke(u.line(atom, (0.5, 0.5)), with: .color(tint.opacity(0.6 * caught)),
                               style: StrokeStyle(lineWidth: max(u.len(0.02), UnitSquare.hairline), lineCap: .round,
                                                  dash: [u.len(0.025), u.len(0.03)]))
            }
        }
        var ring = u.polyline(atoms)
        ring.closeSubpath()
        u.stroke(context, ring, tint, 0.035)
        for (k, atom) in atoms.enumerated() {
            context.fill(u.circle(atom.0, atom.1, k % 2 == 0 ? 0.034 : 0.018), with: .color(tint))
        }
        // Too big: comes in from the left, meets the ring, bounces off.
        let big = Keyframes.value(t, [(0, 0), (0.6, 1), (1.2, 0.2)])
        let gone = Ease.clamp((t - 0.9) / 0.4)
        if gone < 1 {
            context.fill(u.circle(0.5 - 0.53 + 0.2 * big - 0.1 * gone, 0.5, 0.14), with: .color(tint.opacity(0.85 * (1 - gone))))
        }
        // The one that fits: in from the lower right to the middle.
        let enter = Ease.inOut((t - 1.3) / 0.9)
        if t > 1.1 {
            context.fill(u.circle(0.92 + (0.5 - 0.92) * enter, 0.9 + (0.5 - 0.9) * enter, 0.07), with: .color(clay))
        }
    }
}

/// An electrochemical cell: ions drift across the salt bridge while one
/// clay electron runs round the outer wire, lighting the bulb on its way
/// and the electrode it arrives at.
enum Electrochemistry {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        for x in [0.24, 0.76] {
            context.fill(u.capsule(x, 0.76, 0.28, 0.3, corner: 0.02), with: .color(tint.opacity(0.1)))
            u.stroke(context, u.line((x - 0.15, 0.52), (x - 0.15, 0.92), (x + 0.15, 0.92), (x + 0.15, 0.52)), tint, 0.04)
        }
        let wire = [(0.2, 0.36), (0.2, 0.12), (0.8, 0.12), (0.8, 0.36)]
        u.stroke(context, u.polyline(wire), tint, 0.03)
        var bridge = Path()
        bridge.move(to: u.pt(0.34, 0.8))
        bridge.addLine(to: u.pt(0.34, 0.46))
        bridge.addQuadCurve(to: u.pt(0.66, 0.46), control: u.pt(0.5, 0.3))
        bridge.addLine(to: u.pt(0.66, 0.8))
        u.stroke(context, bridge, tint.opacity(0.6), 0.05)
        for k in 0..<3 {
            let s = (t / 2.0 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let p = Polyline.point([(0.34, 0.78), (0.34, 0.46), (0.5, 0.39), (0.66, 0.46), (0.66, 0.78)], at: k % 2 == 0 ? s : 1 - s)
            context.fill(u.circle(p.0, p.1, 0.016), with: .color(tint))
        }
        let run = Ease.inOut((t - 0.4) / 2.0)
        let arrive = Ease.clamp((t - 2.4) / 0.2) * (1 - Ease.clamp((t - 3.3) / 0.5))
        for (x, lit) in [(0.2, 0.0), (0.8, arrive)] {
            context.fill(u.capsule(x, 0.58, 0.05, 0.44, corner: 0.01), with: .color(tint))
            if lit > 0 { context.fill(u.capsule(x, 0.58, 0.05, 0.44, corner: 0.01), with: .color(clay.opacity(lit))) }
        }
        let bulbLit = max(0, 1 - abs(run - 0.5) / 0.25)
        context.fill(u.circle(0.5, 0.12, 0.045), with: .color(clay.opacity(bulbLit)))
        u.stroke(context, u.circle(0.5, 0.12, 0.045), tint, 0.03)
        if run > 0, run < 1 {
            let p = Polyline.point(wire, at: run)
            context.fill(u.circle(p.0, p.1, 0.025), with: .color(clay))
        }
    }
}

/// An NMR spin echo: spins stand together, fan out after the first pulse,
/// are flipped by the second, and come back together into the echo, the
/// clay trace below showing both pulses and the echo.
enum SpinEcho {
    static let duration = 4.0
    private static let first = 0.5, second = 1.8

    private static func phase(_ i: Int, _ t: Double) -> Double {
        let rate = Double(i - 3) * 40
        if t < first { return 0 }
        if t < second { return rate * (t - first) }
        return rate * (t - (2 * second - first))
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let centre = (0.5, 0.42)
        for i in 0..<7 {
            let a = (-90 + phase(i, t)) * .pi / 180
            let tip = (centre.0 + 0.28 * cos(a), centre.1 + 0.28 * sin(a))
            u.stroke(context, u.line(centre, tip), tint, 0.03)
            let back = a + .pi
            u.stroke(context, u.line(tip, (tip.0 + 0.05 * cos(back - 0.4), tip.1 + 0.05 * sin(back - 0.4))), tint, 0.03)
            u.stroke(context, u.line(tip, (tip.0 + 0.05 * cos(back + 0.4), tip.1 + 0.05 * sin(back + 0.4))), tint, 0.03)
        }
        context.fill(u.circle(centre.0, centre.1, 0.025), with: .color(tint))

        // The trace: time runs left to right.
        func x(_ time: Double) -> Double { 0.06 + 0.88 * time / duration }
        u.stroke(context, u.line((0.06, 0.88), (0.94, 0.88)), tint.opacity(0.3), 0.02)
        for (at, h) in [(first, 0.08), (second, 0.13)] where t >= at {
            u.stroke(context, u.line((x(at), 0.88), (x(at), 0.88 - h)), clay, 0.035)
        }
        let echo = 2 * second - first
        let trace = stride(from: 0.0, through: t, by: 0.01).map { s -> (Double, Double) in
            let fid = s > first ? exp(-(s - first) * 3) * sin((s - first) * 30) : 0
            let bump = exp(-pow((s - echo) / 0.12, 2)) * sin((s - echo) * 30 + .pi / 2)
            return (x(s), 0.88 - 0.06 * (fid + bump))
        }
        if trace.count > 1 { u.stroke(context, u.polyline(trace), clay, 0.03) }
    }
}

/// X-ray diffraction: a narrow beam hits a tiny crystal lattice and a
/// symmetric pattern of clay spots blooms on the detector, centre out.
enum XRayDiffraction {
    static let duration = 4.0

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let beam = Ease.clamp((t - 0.2) / 0.4)
        u.stroke(context, u.line((0.02, 0.5), (0.02 + 0.32 * beam, 0.5)), tint, 0.03)
        for i in -1...1 {
            for j in -1...1 { context.fill(u.circle(0.38 + 0.035 * Double(i), 0.5 + 0.035 * Double(j), 0.012), with: .color(tint)) }
        }
        u.stroke(context, u.capsule(0.8, 0.5, 0.26, 0.6, corner: 0.02), tint, 0.04)
        context.fill(u.circle(0.8, 0.5, 0.015), with: .color(tint))
        for i in -2...2 {
            for j in -3...3 where !(i == 0 && j == 0) {
                let d = hypot(Double(i), Double(j) * 0.8)
                let bloom = Ease.outBack((t - 0.8 - 0.25 * d) / 0.3)
                guard bloom > 0 else { continue }
                let p = (0.8 + 0.05 * Double(i), 0.5 + 0.07 * Double(j))
                let strength = 0.35 + 0.65 * abs(cos(Double(i * 3 + j * 5)))
                context.fill(u.circle(p.0, p.1, 0.014 * min(1, bloom) * (0.7 + strength)), with: .color(clay.opacity(strength)))
                if bloom < 1 { u.stroke(context, u.line((0.38, 0.5), p), tint.opacity(0.25 * (1 - bloom)), 0.015) }
            }
        }
    }
}

/// Single-molecule FRET: a molecule opens and closes; when its two dyes
/// are close the clay acceptor shines, when apart the donor does, and
/// their two traces run in opposition below.
enum FRET {
    static let duration = 4.0

    private static func closeness(_ t: Double) -> Double { 0.5 + 0.5 * sin(t * 2 * .pi / 2.0) }

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        let close = closeness(t)
        let half = (70 - 55 * close) * .pi / 180
        let hinge = (0.5, 0.14)
        let left = (hinge.0 - 0.24 * sin(half), hinge.1 + 0.24 * cos(half))
        let right = (hinge.0 + 0.24 * sin(half), hinge.1 + 0.24 * cos(half))
        u.stroke(context, u.polyline(Smooth.curve([left, (hinge.0 - 0.04, hinge.1 + 0.08), hinge, (hinge.0 + 0.04, hinge.1 + 0.08), right])),
                 tint, 0.035)
        let donor = 0.028 + 0.025 * (1 - close), acceptor = 0.028 + 0.025 * close
        context.fill(u.circle(left.0, left.1, donor), with: .color(tint))
        context.fill(u.circle(right.0, right.1, acceptor), with: .color(clay))
        if close > 0.6 { u.stroke(context, u.circle(right.0, right.1, acceptor + 0.03), clay.opacity((close - 0.6) / 0.4 * 0.6), 0.02) }
        if close < 0.4 { u.stroke(context, u.circle(left.0, left.1, donor + 0.03), tint.opacity((0.4 - close) / 0.4 * 0.6), 0.02) }

        let history = stride(from: t - 2.0, through: t, by: 0.03)
        let donorTrace = history.map { s in (0.08 + 0.84 * (s - t + 2.0) / 2.0, 0.92 - 0.14 * (1 - closeness(s))) }
        let acceptorTrace = history.map { s in (0.08 + 0.84 * (s - t + 2.0) / 2.0, 0.92 - 0.14 * closeness(s)) }
        u.stroke(context, u.polyline(donorTrace), tint.opacity(0.7), 0.025)
        u.stroke(context, u.polyline(acceptorTrace), clay, 0.03)
    }
}

/// A metal–organic framework assembling: clay metal nodes appear and bent
/// organic linkers join them one by one into a small porous lattice.
enum MOF {
    static let duration = 4.0
    private static let grid = [0.26, 0.5, 0.74]

    static func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, tint: Color) {
        let u = UnitSquare(size)
        func appears(_ i: Int, _ j: Int) -> Double { 0.2 + 0.12 * Double(i * 3 + j) }
        var links: [((Double, Double), (Double, Double), Double)] = []
        for i in 0..<3 {
            for j in 0..<3 {
                if j < 2 { links.append(((grid[j], grid[i]), (grid[j + 1], grid[i]), max(appears(i, j), appears(i, j + 1)))) }
                if i < 2 { links.append(((grid[j], grid[i]), (grid[j], grid[i + 1]), max(appears(i, j), appears(i + 1, j)))) }
            }
        }
        for (k, link) in links.enumerated() {
            let grow = Ease.inOut((t - link.2 - 0.1 - 0.02 * Double(k)) / 0.3)
            guard grow > 0 else { continue }
            let a = link.0, b = link.1
            let mid = ((a.0 + b.0) / 2, (a.1 + b.1) / 2)
            let dx = b.0 - a.0, dy = b.1 - a.1
            let kink = (mid.0 - dy * 0.14, mid.1 + dx * 0.14)
            u.stroke(context, u.line(a, kink, b).trimmedPath(from: 0, to: grow), tint, 0.035)
        }
        for i in 0..<3 {
            for j in 0..<3 {
                let pop = Ease.outBack((t - appears(i, j)) / 0.25)
                guard pop > 0 else { continue }
                context.fill(u.capsule(grid[j], grid[i], 0.07 * min(1.2, pop), 0.07 * min(1.2, pop), corner: 0.01), with: .color(clay))
            }
        }
    }
}
