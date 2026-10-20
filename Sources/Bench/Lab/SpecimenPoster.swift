// SpecimenPoster.swift — a still for each specimen that shows something
// (DESIGN.md, Scenes settings). A still used to be the scene three fifths of
// the way in, and a few specimens (ECL detection, Streak plate, Column, Flow
// cytometry) are nearly empty there: they draw themselves up over the loop.
// A specimen's poster is the frame with the most ink, found once by drawing a
// few candidates small and counting; a still that already shows enough stays.
//
// The drawing is the shared one (`LabScenes.draw`); the choice lives here,
// since Shared/ is copied from the droplet and is not ours to change.
import SwiftUI

enum SpecimenPoster {
    /// Candidates spread between the fade-in and the fade-out, plus the old
    /// still: that one goes first, so a specimen that shows well there keeps
    /// it and ties never move a poster.
    static let candidates = 10

    /// Where the still used to be drawn, well past the fade-in.
    static func fallback(_ scene: LabScene) -> Double { scene.duration * 0.6 }

    /// The times to try, `fallback` first. Inside the fade (`LabScenes.fade`)
    /// a scene is only half there, so no candidate sits in it.
    static func times(for scene: LabScene) -> [Double] {
        let first = LabScenes.fade, last = scene.duration - LabScenes.fade
        guard last > first else { return [fallback(scene)] }
        return [fallback(scene)] + (0..<candidates).map { first + (last - first) * (Double($0) + 0.5) / Double(candidates) }
    }

    /// The old still keeps its place while it already shows at least this
    /// much of the best frame's ink. Ink is a rough measure (a closed black
    /// door has more than an open one with things in it), so a still that is
    /// good enough stays, and a poster only replaces one that is thin.
    static let keepsOldStill = 0.6

    /// The time whose ink is greatest, unless the old still (`times[0]`) has
    /// `keepsOldStill` of it already; the earliest of equals.
    static func choose(ink: [Double], at times: [Double]) -> Double {
        var best = 0
        for k in ink.indices where k < times.count && ink[k] > ink[best] { best = k }
        guard times.indices.contains(best) else { return times.first ?? 0 }
        return ink[0] >= keepsOldStill * ink[best] ? times[0] : times[best]
    }

    /// A scene `local` seconds into its own loop at full strength, clipped to
    /// its square as `LabScenes.draw` clips it. That one also fades and grows
    /// the scene in and out, which is the rotation handing over to the next;
    /// a grid cell plays one scene round and round, and would be pale for a
    /// fifth of every loop of a three-second scene.
    static func drawLooping(_ scene: LabScene, in context: inout GraphicsContext, size: CGSize, local: Double, tint: Color) {
        var layer = context
        layer.clip(to: Path(CGRect(origin: .zero, size: size)))
        scene.draw(&layer, size, local, tint)
    }

    /// Each time's ink: the total opacity of what the scene draws there, so
    /// a faint wash counts for less than a solid line. Drawn in one pass onto
    /// a sheet of small cells, as the panel's player draws its frames.
    @MainActor
    static func ink(of scene: LabScene, at times: [Double], side: CGFloat = 40, fading: Bool = true) -> [Double] {
        guard !times.isEmpty else { return [] }
        let columns = 4
        let rows = (times.count + columns - 1) / columns
        let sheet = Canvas { context, _ in
            for (k, t) in times.enumerated() {
                var cell = context
                cell.translateBy(x: side * CGFloat(k % columns), y: side * CGFloat(k / columns))
                let size = CGSize(width: side, height: side)
                if fading {
                    LabScenes.draw(scene, in: &cell, size: size, local: t, tint: .black)
                } else {
                    drawLooping(scene, in: &cell, size: size, local: t, tint: .black)
                }
            }
        }
        .frame(width: side * CGFloat(columns), height: side * CGFloat(rows))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return times.map { _ in 0 } }

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return times.map { _ in 0 } }
        let cell = Int(side)
        return times.indices.map { k in
            var total = 0
            for y in (k / columns) * cell..<(k / columns + 1) * cell {
                for x in (k % columns) * cell..<(k % columns + 1) * cell {
                    total += Int(pixels[(y * width + x) * 4 + 3])
                }
            }
            return Double(total) / 255
        }
    }

    /// The poster time of one specimen: a few milliseconds of drawing.
    @MainActor
    static func time(for scene: LabScene) -> Double {
        let times = times(for: scene)
        return choose(ink: ink(of: scene, at: times), at: times)
    }
}

/// The choices, made when a still is first drawn and kept for the run. Asking
/// is async: the drawing needs the main actor (`ImageRenderer`), so requests
/// wait in line and are answered one at a time with a breath between, rather
/// than all at once in the frame that opens a tab. Nothing is asked for while
/// every cell is playing live, which is nearly always: the stills show under
/// Reduce Motion, and for a cell the moment before it plays.
@MainActor
final class SpecimenPosters {
    static let shared = SpecimenPosters()

    private var chosen: [String: Double] = [:]
    private var waiting: [String: (scene: LabScene, resumes: [CheckedContinuation<Double, Never>])] = [:]
    private var line: [String] = []
    private var answering = false

    /// The choice, if it has been made.
    func cached(_ scene: LabScene) -> Double? { chosen[scene.name] }

    func time(for scene: LabScene) async -> Double {
        if let time = chosen[scene.name] { return time }
        return await withCheckedContinuation { continuation in
            if waiting[scene.name] == nil {
                waiting[scene.name] = (scene, [])
                line.append(scene.name)
            }
            waiting[scene.name]?.resumes.append(continuation)
            answerWaiting()
        }
    }

    private func answerWaiting() {
        guard !answering else { return }
        answering = true
        Task { @MainActor in
            while !line.isEmpty {
                let name = line.removeFirst()
                guard let job = waiting.removeValue(forKey: name) else { continue }
                let time = SpecimenPoster.time(for: job.scene)
                chosen[name] = time
                for resume in job.resumes { resume.resume(returning: time) }
                // A breath between specimens, so scrolling and clicks stay smooth.
                try? await Task.sleep(for: .milliseconds(2))
            }
            answering = false
        }
    }
}
