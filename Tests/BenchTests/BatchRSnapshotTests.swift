// BatchRSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws batch R's specimens (DESIGN.md, "Scenes settings") into it,
// one sheet each: eight moments through the loop, the moment just before it
// closes, and the still the field guide shows, at 16, 24, 48 and 96 pt in each
// theme, all at 2x. It also writes cost.txt: what one second of frames costs
// to draw at the panel's 88 pt, as the panel's player draws it, beside a few
// older specimens, and how many bytes those frames hold. Without the folder
// the test does nothing.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct BatchRSnapshotTests {
    static let names = ["Capillary electrophoresis", "Microtome ribbon", "Möbius strip", "Bayesian update",
                        "Droplet coalescence", "Slime mold maze", "Fern unfurling", "Diatom"]
    /// Older specimens to measure beside them: plain, busy and in between.
    static let older = ["Flask", "Microscope", "Crystal", "Histology slide", "Nucleation"]
    static let sides: [CGFloat] = [16, 24, 48, 96]
    static let gap: CGFloat = 6

    struct Look {
        let ground: Color
        let ink: Color
    }

    static let looks = [
        Look(ground: Color(red: 0.97, green: 0.96, blue: 0.94), ink: ColorScheme.light.sceneInk),
        Look(ground: Color(red: 0.2, green: 0.2, blue: 0.19), ink: ColorScheme.dark.sceneInk),
    ]

    /// The moments a sheet shows: eight evenly through the loop, the last
    /// hundredth before it closes (which should match the first), and the still.
    static func moments(of scene: LabScene) -> [Double] {
        (0..<8).map { scene.duration * Double($0) / 8 } + [scene.duration - 0.01, SpecimenPoster.time(for: scene)]
    }

    static func sheet(for scene: LabScene) -> CGImage? {
        let times = moments(of: scene)
        let width = sides.map { CGFloat(times.count) * ($0 + gap) + gap }.max() ?? 0
        let height = CGFloat(looks.count) * sides.map { $0 + gap }.reduce(gap, +)
        let canvas = Canvas { context, _ in
            var y: CGFloat = 0
            for look in looks {
                let band = sides.map { $0 + gap }.reduce(gap, +)
                context.fill(Path(CGRect(x: 0, y: y, width: width, height: band)), with: .color(look.ground))
                var top = y + gap
                for side in sides {
                    for (column, t) in times.enumerated() {
                        var cell = context
                        cell.translateBy(x: gap + CGFloat(column) * (side + gap), y: top)
                        SpecimenPoster.drawLooping(scene, in: &cell, size: CGSize(width: side, height: side), local: t, tint: look.ink)
                    }
                    top += side + gap
                }
                y += band
            }
        }
        .frame(width: width, height: height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        return renderer.cgImage
    }

    @Test func batchRIsDrawnWhenAsked() throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scenes = Self.names.compactMap { name in LabScenes.catalogue.first { $0.name == name } }
        for scene in scenes {
            let image = try #require(Self.sheet(for: scene))
            let slug = scene.name.folding(options: .diacriticInsensitive, locale: nil).lowercased().replacingOccurrences(of: " ", with: "-")
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("\(slug).png"))
        }

        // One second of frames at 88 pt and 2x, as PlayedGlyphView draws a chunk;
        // the best of three, after one to warm up.
        let perSecond = Int(PlayedGlyphView.fps)
        let size = CGSize(width: 88, height: 88)
        var lines = ["One second of frames (\(perSecond)) at 88 pt, 2x: best of three, ms; bytes held"]
        let measured = scenes + Self.older.compactMap { name in LabScenes.catalogue.first { $0.name == name } }
        for scene in measured {
            _ = PlayedGlyphView.frames(of: scene, from: 0, to: perSecond, size: size, scale: 2, tint: .white)
            var best = Double.infinity
            var bytes = 0
            for _ in 0..<3 {
                let start = Date()
                let images = PlayedGlyphView.frames(of: scene, from: 0, to: perSecond, size: size, scale: 2, tint: .white)
                // Touch every pixel, in case the images are drawn lazily (as SheetCost does).
                for image in images { _ = image.dataProvider?.data.map { CFDataGetLength($0) } }
                bytes = images.reduce(0) { $0 + $1.bytesPerRow * $1.height }
                best = min(best, Date().timeIntervalSince(start) * 1000)
            }
            lines.append(String(format: "%@%@: %.1f ms; %d bytes", Self.names.contains(scene.name) ? "" : "(older) ",
                                scene.name, best, bytes))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("cost.txt"), atomically: true, encoding: .utf8)
    }
}
