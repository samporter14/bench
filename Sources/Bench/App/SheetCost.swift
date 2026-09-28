// SheetCost.swift — `Bench --measure-sheets 48,64,72,88` prints, for each
// size, how long the dearest scenes take to draw one second of frames (what
// PlayedGlyph renders ahead of playback), then exits. A development tool.
import SwiftUI

@MainActor
enum SheetCost {
    static func runIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--measure-sheets"), i + 1 < args.count else { return }
        let sizes = args[i + 1].split(separator: ",").compactMap { Double($0) }
        let perSecond = Int(PlayedGlyphView.fps)
        _ = PlayedGlyphView.frames(of: LabScenes.all[0], from: 0, to: perSecond,
                                   size: CGSize(width: 20, height: 20), scale: 2, tint: .white)
        let probe = PlayedGlyphView.frames(of: LabScenes.all[0], from: 0, to: perSecond,
                                           size: CGSize(width: 72, height: 72), scale: 2, tint: .white)
        print("probe: \(probe.count) frames, first \(probe.first.map { "\($0.width)x\($0.height)" } ?? "none")")
        for points in sizes {
            let size = CGSize(width: points, height: points)
            var rows: [(String, Double)] = []
            for scene in LabScenes.all {
                let frames = Int(scene.duration * PlayedGlyphView.fps)
                let start = Date()
                let images = PlayedGlyphView.frames(of: scene, from: 0, to: min(frames, perSecond), size: size, scale: 2, tint: .white)
                // Touch every pixel, in case the images are drawn lazily.
                for image in images { _ = image.dataProvider?.data.map { CFDataGetLength($0) } }
                rows.append((scene.name, Date().timeIntervalSince(start) * 1000))
            }
            rows.sort { $0.1 > $1.1 }
            let mean = rows.map(\.1).reduce(0, +) / Double(rows.count)
            print(String(format: "%.0fpt: mean %.1f ms per second of frames; dearest: ", points, mean)
                  + rows.prefix(4).map { String(format: "%@ %.0f", $0.0, $0.1) }.joined(separator: ", "))
        }
        exit(0)
    }
}
