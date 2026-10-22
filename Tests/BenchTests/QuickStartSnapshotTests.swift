// QuickStartSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names
// a folder, draws the Quick Start panel's content (the demo's made-up
// projects, recipes and file) into it as PNGs, light and dark, on the board's
// dark ground, so it can be looked at without opening a window. Without it the
// test does nothing. The blur behind the glass belongs to the window and is not
// drawn here; the ivory over it is.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct QuickStartSnapshotTests {
    /// The board's ground behind the panel, and its margins around it.
    private struct Scene: View {
        @ObservedObject var model: QuickStartModel

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color(red: 0x3B / 255, green: 0x3A / 255, blue: 0x36 / 255)
                QuickStartView(model: model)
                    .padding(.leading, 32)
                    .padding(.top, 48)
                    .padding(.trailing, 32)
                    .padding(.bottom, 32)
            }
        }
    }

    private func draw(_ model: QuickStartModel, dark: Bool, name: String, to directory: URL) async throws {
        let host = NSHostingView(rootView: Scene(model: model))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: NSSize(width: 632, height: 700))
        host.layoutSubtreeIfNeeded()
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(60))
            host.layoutSubtreeIfNeeded()
        }
        let height = ceil(host.fittingSize.height)
        host.frame = CGRect(origin: .zero, size: NSSize(width: 632, height: height))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 632 * 2, pixelsHigh: Int(height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 632, height: height)
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    @Test func theQuickStartPanelIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = QuickStartDemo.model()
        // Let the project and session lookups land.
        try await Task.sleep(for: .milliseconds(200))
        for dark in [false, true] {
            try await draw(model, dark: dark, name: "quick-start", to: directory)
        }
        // ⇧ down: the message to the session in view.
        model.shiftHeld = true
        try await draw(model, dark: false, name: "quick-start-shift", to: directory)
        model.shiftHeld = false
        // A file turned away, in the foot's one line.
        model.addFiles([URL(fileURLWithPath: "/tmp/capsid-demo/setup.dmg")])
        try await draw(model, dark: false, name: "quick-start-failed", to: directory)
    }
}
