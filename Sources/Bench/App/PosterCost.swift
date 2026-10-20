// PosterCost.swift — `Capsid --measure-posters [sheet.png]` chooses every
// specimen's poster time (Lab/SpecimenPoster.swift) the way the app does and
// prints how long it took, then exits. With a path it also writes a sheet of
// the stills before and after, for the specimens that change most. A
// development tool, like SheetCost.
import AppKit
import SwiftUI

@MainActor
enum PosterCost {
    static func runIfAsked() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--measure-posters") else { return }
        let sheetPath = args.dropFirst(flag + 1).first.flatMap { $0.hasPrefix("--") ? nil : $0 }

        // The first render pays for the framework's own start-up.
        _ = SpecimenPoster.time(for: LabScenes.catalogue[0])
        var rows: [(name: String, ms: Double, old: Double, new: Double, time: Double)] = []
        let begin = Date()
        for scene in LabScenes.catalogue {
            let start = Date()
            let times = SpecimenPoster.times(for: scene)
            let ink = SpecimenPoster.ink(of: scene, at: times)
            let time = SpecimenPoster.choose(ink: ink, at: times)
            rows.append((scene.name, Date().timeIntervalSince(start) * 1000, ink.first ?? 0, ink.max() ?? 0, time))
        }
        let total = Date().timeIntervalSince(begin) * 1000
        let moved = rows.indices.filter { rows[$0].time != SpecimenPoster.fallback(LabScenes.catalogue[$0]) }.count
        let slowest = rows.sorted { $0.ms > $1.ms }.prefix(3)
            .map { String(format: "%@ %.1f", $0.name, $0.ms) }.joined(separator: ", ")
        print(String(format: "%d specimens, %d candidates each: %.0f ms in all, %.2f ms each; dearest %@",
                     rows.count, SpecimenPoster.candidates + 1, total, total / Double(rows.count), slowest))
        print("\(moved) of \(rows.count) posters moved off the old 60% still (the old keeps its place at \(Int(SpecimenPoster.keepsOldStill * 100))% of the best ink)")
        for name in ["ECL detection", "Streak plate", "Column", "Flow cytometry"] {
            guard let row = rows.first(where: { $0.name == name }) else { continue }
            print(String(format: "%@: ink at 60%% %.0f, at poster %.0f (%.1fx)", name, row.old, row.new, row.new / max(row.old, 0.001)))
        }
        if let sheetPath { writeSheet(to: sheetPath, rows: rows) }
        exit(0)
    }

    private static func scene(named name: String) -> LabScene {
        LabScenes.catalogue.first { $0.name == name } ?? LabScenes.catalogue[0]
    }

    /// The four named above, then the 20 specimens whose posters gained the
    /// most ink: each as the old still and the new one.
    private static func writeSheet(to path: String, rows: [(name: String, ms: Double, old: Double, new: Double, time: Double)]) {
        let named = ["ECL detection", "Streak plate", "Column", "Flow cytometry"]
        let byGain = rows.filter { $0.time != SpecimenPoster.fallback(scene(named: $0.name)) }
            .sorted { $0.new / max($0.old, 1) > $1.new / max($1.old, 1) }.map(\.name)
        let names = Array(NSOrderedSet(array: named + byGain).array as! [String]).prefix(24)
        let scenes = names.compactMap { name in LabScenes.catalogue.first { $0.name == name } }
        let sheet = PosterSheet(scenes: scenes, times: Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.time) }))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("could not draw the sheet")
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

private struct PosterSheet: View {
    let scenes: [LabScene]
    let times: [String: Double]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 8), count: 4), spacing: 10) {
            ForEach(scenes, id: \.name) { scene in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        tile(scene, at: SpecimenPoster.fallback(scene))
                        tile(scene, at: times[scene.name] ?? SpecimenPoster.fallback(scene))
                    }
                    Text(scene.name).font(.system(size: 10)).foregroundStyle(.black)
                }
            }
        }
        .padding(12)
        .background(Color.white)
    }

    private func tile(_ scene: LabScene, at time: Double) -> some View {
        Canvas { context, size in
            LabScenes.draw(scene, in: &context, size: size, local: time, tint: Color(red: 0.08, green: 0.08, blue: 0.075))
        }
        .frame(width: 70, height: 70)
        .background(Color(white: 0.96), in: .rect(cornerRadius: 10))
    }
}
