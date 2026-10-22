// KeepSheetSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names
// a folder, draws the Keep sheet (on the demo's made-up reads, after they
// have come in) into it as PNGs, light and dark, so it can be looked at
// without opening a window. Without it the test does nothing. It draws
// through an `NSHostingView` that is never put in a window, as the update
// popover's snapshot does, so a window-modal sheet's own material is absent.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct KeepSheetSnapshotTests {
    @Test func theKeepSheetIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keep-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, failing) in [("keep-sheet", false), ("keep-sheet-partial", true)] {
            let model = KeptDemo.sheetModel(root: root, failingData: failing)
            model.open()
            for _ in 0..<100 where model.phase == .reading || model.readingProvenance {
                try await Task.sleep(for: .milliseconds(50))
            }
            if failing {
                model.keep()
                for _ in 0..<100 {
                    if case .partial = model.phase { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            for dark in [false, true] {
                let view = KeepSheet(model: model, dismiss: {})
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let size = host.fittingSize
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
        }
    }
}
