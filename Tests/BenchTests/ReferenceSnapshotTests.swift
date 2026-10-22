// ReferenceSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names
// a folder, draws the reference window's content (on the demo's made-up
// reads) into it as PNGs, light and dark, at the window's width, so it can be
// looked at without opening a window. Without it the test does nothing. The
// toolbar belongs to the window and is not drawn here.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct ReferenceSnapshotTests {
    @Test func theReferenceContentIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, failing) in [("reference", false), ("reference-failed", true)] {
            let gate = ReadingGate(now: { Date() }, sleep: { _ in })
            let model = ReferenceModel(session: ReferenceDemo.session,
                                       dependencies: ReferenceDemo.dependencies(failing: failing, delay: .zero), gate: gate)
            model.open()
            for _ in 0..<100 where model.phase == .reading { try await Task.sleep(for: .milliseconds(20)) }
            if !failing {
                // The middle reply, with its two figures.
                model.earlier()
                for _ in 0..<100 where model.phase == .reading { try await Task.sleep(for: .milliseconds(20)) }
                for figure in model.current?.figures ?? [] {
                    model.wantThumbnail(figure)
                    for _ in 0..<100 where !model.thumbnails.contains(figure.v) { try await Task.sleep(for: .milliseconds(20)) }
                }
            }
            for dark in [false, true] {
                let view = ReferenceView(model: model, selection: ReferenceSelection())
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let size = NSSize(width: ReferenceWindowController.size.width, height: ReferenceWindowController.size.height)
                host.frame = CGRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                let rep = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                rep.size = size
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
            model.close()
        }
    }
}
