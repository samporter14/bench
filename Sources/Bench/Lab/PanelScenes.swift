// PanelScenes.swift — the two small scenes the panel draws for itself (DESIGN.md,
// "The panel", moments): a well plate whose wells fill and then sparkle, when a
// session finishes, and a culture plate with one stray colony, when it stops
// with an error. After board 6 of the 1.0 mock-ups.
//
// They are not specimens: neither is in `LabScenes.catalogue`, so neither
// plays in the rotation, appears in Settings or needs a field-guide note.
// They are drawn the way the specimens are (a unit square, the house weights,
// tint plus clay, a pure function of time) and live here and not in Shared/,
// which the droplet owns.
import SwiftUI

/// A 4 × 2 well plate. Its wells fill one after another, pale clay settling
/// to the tint, and two clay sparkles pop in above it. 1.3 s, then it stays.
enum FilledPlate {
    static let duration = 1.3

    /// Wells in filling order: along each row, then the next.
    static let wells: [(x: Double, y: Double)] = [0.42, 0.6].flatMap { y in
        [0.26, 0.42, 0.58, 0.74].map { (x: $0, y: y + 0.07) }
    }
    private static let radius = 0.062
    /// Where each well starts to fill, in seconds, and how long it takes.
    private static func start(_ index: Int) -> Double { 0.1 + 0.09 * Double(index) }
    private static let fillTime = 0.25

    /// The two sparkles: where, how big (centre to tip) and when each pops in.
    static let sparkles: [(x: Double, y: Double, size: Double, at: Double)] = [
        (0.76, 0.2, 0.115, 0.85), (0.2, 0.17, 0.08, 1.0),
    ]

    static func draw(in context: inout GraphicsContext, size: CGSize, elapsed e: Double, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.capsule(0.5, 0.56, 0.8, 0.5, corner: 0.07), tint, 0.05)
        for (index, well) in wells.enumerated() {
            let age = e - start(index)
            // The ring is the empty well; it goes as the well fills.
            let empty = 1 - Ease.clamp(age / 0.2)
            if empty > 0 { u.stroke(context, u.circle(well.x, well.y, radius), tint.opacity(0.55 * empty), 0.03) }
            guard age > 0 else { continue }
            let pop = Ease.outBack(age / fillTime)
            let settled = Ease.clamp((age - fillTime) / 0.3)
            context.fill(u.circle(well.x, well.y, radius * pop), with: .color(tint))
            // Each well lights in clay as it fills and settles to the tint.
            context.fill(u.circle(well.x, well.y, radius * pop), with: .color(clay.opacity(1 - settled)))
        }
        for sparkle in sparkles {
            let pop = Ease.outBack((e - sparkle.at) / 0.3)
            guard pop > 0 else { continue }
            context.fill(star(u, sparkle.x, sparkle.y, sparkle.size * pop), with: .color(clay))
        }
    }

    /// A four-point sparkle as board 6 draws it: fatter in the waist than
    /// `Sparkles.star`, so it reads at 88 points.
    static func star(_ u: UnitSquare, _ x: Double, _ y: Double, _ size: Double) -> Path {
        let points = (0..<8).map { k -> (Double, Double) in
            let r = k % 2 == 0 ? size : size * 0.47
            let b = Double(k) * .pi / 4 - .pi / 2
            return (x + r * cos(b), y + r * sin(b))
        }
        var path = u.polyline(points)
        path.closeSubpath()
        return path
    }
}

/// A culture plate with one stray clay colony: the contamination. Still.
enum ContaminatedPlate {
    static func draw(in context: inout GraphicsContext, size: CGSize, tint: Color) {
        let u = UnitSquare(size)
        u.stroke(context, u.circle(0.5, 0.5, 0.37), tint, 0.05)
        // The agar's edge, dashed.
        let dash = StrokeStyle(lineWidth: max(u.len(0.022), UnitSquare.hairline), lineCap: .round, dash: [u.len(0.03), u.len(0.048)])
        context.stroke(u.circle(0.5, 0.5, 0.3), with: .color(tint.opacity(0.7)), style: dash)
        // The culture's own colonies, small and pale.
        for (x, y) in [(0.375, 0.41), (0.47, 0.6), (0.345, 0.56)] {
            context.fill(u.circle(x, y, 0.034), with: .color(tint))
        }
        // The stray: a large colony and two satellites, in clay.
        context.fill(u.circle(0.625, 0.42, 0.095), with: .color(clay))
        context.fill(u.circle(0.7, 0.36, 0.04), with: .color(clay))
        context.fill(u.circle(0.69, 0.52, 0.032), with: .color(clay))
    }
}

/// The finished card's well: the plate fills and sparkles once, as the card
/// settles, then rests on its last frame. Under Reduce Motion, and while
/// nobody is at the Mac (`SpecimenHold`), it is that last frame at once.
struct FinishedPlateWell: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.stillSpecimens) private var stillSpecimens
    private var reduceMotion: Bool { systemReduceMotion || stillSpecimens }
    @ObservedObject private var hold = SpecimenHold.shared
    @State private var start = Date()
    @State private var settled = false

    var body: some View {
        Group {
            if reduceMotion || hold.holds || settled {
                still
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: settled)) { timeline in
                    Canvas { context, size in
                        FilledPlate.draw(in: &context, size: size, elapsed: timeline.date.timeIntervalSince(start), tint: tint)
                    }
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(FilledPlate.duration + 0.05))
            settled = true
        }
        .accessibilityHidden(true)
    }

    private var still: some View {
        Canvas { context, size in
            FilledPlate.draw(in: &context, size: size, elapsed: FilledPlate.duration + 1, tint: tint)
        }
    }
}

/// The failure card's well: the contaminated plate, still.
struct ContaminatedPlateWell: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            ContaminatedPlate.draw(in: &context, size: size, tint: tint)
        }
        .accessibilityHidden(true)
    }
}
