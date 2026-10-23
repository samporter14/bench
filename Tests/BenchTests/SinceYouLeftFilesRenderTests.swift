// SinceYouLeftFilesRenderTests.swift — the sheet's finished row, drawn for real (offscreen, the way the snapshot tests
// draw it) with "Show plans, questions and requests on the card" on and off. On, a finished row has up to three small
// tiles at its right edge; off, it has none, whether its files were read before the setting went off or not. The
// model's own reads are in SinceYouLeftModelTests; this is what a person sees. Made-up sessions and files only.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct SinceYouLeftFilesRenderTests {
    /// The setting, as the sheet's model reads it.
    private final class Setting { var on = true }

    private static func picture(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return context.makeImage()!
    }

    /// One finished session whose files (two pictures and a table) were read, in a sheet whose header has nothing at its
    /// right, so that the strip at the right edge of the row holds the tiles and nothing else.
    private func scene(_ setting: Setting) -> (model: SinceYouLeftModel, actions: CardActions) {
        let lab = LabModel()
        let finished = FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false }))
        var deps = SinceYouLeftDemo.demoDependencies(model: nil)
        deps.usage = { nil }
        deps.readsContent = { setting.on }
        let model = SinceYouLeftModel(lab: lab, finished: finished, dependencies: deps)
        let made = SinceYouLeftDemo.made()
        let session = made.finished[0]
        func file(_ key: String, _ name: String, _ mime: String) -> ArtifactEntry {
            ArtifactEntry(version: "tile-\(key)", artifact: nil, name: name, mime: mime, size: 24_000, at: nil)
        }
        finished.showDemo([file("bars", "z_prime.png", "image/png"), file("grid", "plate_map.png", "image/png"),
                           file("table", "plates_cleaned.csv", "text/csv")], for: session.id,
                          pictures: ["tile-bars": Self.picture(0.1, 0.1, 0.1), "tile-grid": Self.picture(0.85, 0.35, 0.2)])
        lab.showDemo(working: [], cards: [])
        model.showDemo(since: made.since, back: made.back,
                       events: [LabEvent(.finished, session: session, at: made.since.addingTimeInterval(22 * 60))], baseline: nil,
                       details: [session.id: .init(answer: "All plates passed except plate 7, which has an edge effect in column 12.")])
        let actions = CardActions(model: lab, plans: PlanApprover.shared, questions: QuestionReplier(model: lab, dependencies: .live()))
        return (model, actions)
    }

    private func draw(_ model: SinceYouLeftModel, _ actions: CardActions, dark: Bool = false) async throws -> NSBitmapImageRep {
        try await SinceYouLeftSnapshotTests.draw(SinceYouLeftSheet(model: model, maxHeight: 900, cardActions: actions),
                                                 width: SinceYouLeftSheet.width, dark: dark)
    }

    /// How many pixels in the strip where a finished row's tiles are differ from the sheet's own ground. The band is
    /// the first 32 points of the row, counted from the top of the sheet (the header is the same with the setting on or
    /// off, and the row starts 131 points down; the rule under a short row, further down, is not in it); the strip is
    /// the 206 points the three tiles take, at the row's right edge.
    private func tilePixels(in rep: NSBitmapImageRep) -> Int {
        let scale = 2.0
        let width = Double(rep.pixelsWide) / scale
        let band = (Int(128 * scale)..<Int(160 * scale))
        let strip = (Int((width - 28 - 206) * scale)..<Int((width - 28) * scale))
        guard let ground = rep.colorAt(x: Int((width - 10) * scale), y: (band.lowerBound + band.upperBound) / 2)?.usingColorSpace(.deviceRGB) else { return -1 }
        var different = 0
        for y in band {
            for x in strip {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let gap = abs(color.redComponent - ground.redComponent) + abs(color.greenComponent - ground.greenComponent)
                    + abs(color.blueComponent - ground.blueComponent)
                if gap > 0.02 { different += 1 }
            }
        }
        return different
    }

    @Test func aFinishedRowDrawsItsTilesWhileTheSettingIsOnAndNoneOnceItIsOff() async throws {
        let setting = Setting()
        let (model, actions) = scene(setting)
        let on = try await draw(model, actions)
        #expect(tilePixels(in: on) > 2_000, "the control: three 64 by 48 tiles are drawn with it on (\(tilePixels(in: on)) pixels)")
        // The files stay in memory, as the Finished card's own would; the sheet draws none of them.
        setting.on = false
        #expect(model.finished.listing(for: SinceYouLeftDemo.made().finished[0].id) != .unknown)
        let off = try await draw(model, actions)
        #expect(tilePixels(in: off) == 0, "no tile, no picture and no placeholder is left at the row's edge (\(tilePixels(in: off)) pixels)")
        // Turned on again, they are back as they were.
        setting.on = true
        let again = try await draw(model, actions)
        #expect(tilePixels(in: again) == tilePixels(in: on))
        if let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try SinceYouLeftSnapshotTests.write(on, "since-sheet-files-on", dark: false, to: directory)
            try SinceYouLeftSnapshotTests.write(off, "since-sheet-files-off", dark: false, to: directory)
        }
    }

    @Test func aRowWhoseFilesWereNeverReadHasNoTilesEitherWayTheSettingGoes() async throws {
        let setting = Setting()
        setting.on = false
        let (model, actions) = scene(setting)
        model.finished.forget(SinceYouLeftDemo.made().finished[0].id)
        #expect(tilePixels(in: try await draw(model, actions)) == 0)
    }
}
