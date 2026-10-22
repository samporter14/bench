// KeptWindowSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR`
// names a folder, draws the Kept window's content (the demo's made-up kept
// results, in a temporary root) into it as PNGs, light and dark, so it can be
// looked at without opening a window. Without it the test does nothing. The
// title bar belongs to the window and is not drawn here.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct KeptWindowSnapshotTests {
    @Test func theKeptWindowIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kept-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails()
        for dark in [false, true] {
            let view = KeptView(index: index, thumbnails: thumbnails, quickLook: KeptQuickLook(), initialSelection: nil)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = NSSize(width: 760, height: 720)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            // Let the selection, the README read and the thumbnails land.
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
            }
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("kept-window-\(dark ? "dark" : "light").png"))
        }
    }
}
