// CompareSnapshotTests.swift — Compare drawn offscreen (Kept/CompareView.swift):
// the wipe's pixels checked at 0%, 50% and 100% on every run, and, only when
// CAPSID_SNAPSHOT_DIR names a folder, captures of each state in light and dark at
// the window's first size and its least (pictures side by side, Wipe at half,
// two sizes, zoomed and linked, Text Changes, no text changes, a side that can't
// be read) and the Shelf with two cards picked. Made-up files only, from a disk
// in memory; nothing is opened on screen. The title bar is drawn as a stand-in
// above the content, as the Shelf's captures do, with the window's own controls.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct CompareSnapshotTests {
    private struct Window: View {
        let model: CompareModel

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color).frame(width: 12, height: 12) }
                    CompareTitle().padding(.leading, 8)
                    Spacer()
                    CompareControls(model: model)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                CompareView(model: model)
            }
            .background(Solanum.page)
        }
    }

    /// Draws `view` at `size` points, twice the pixels, in light or dark.
    private func render<V: View>(_ view: V, size: NSSize, dark: Bool) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    // MARK: Wipe's pixels

    @Test func wipeShowsTheLeftPictureLeftOfTheDividerAndNeitherMoves() async throws {
        // Left: red, its green channel counting the columns; right: blue, the same count. 200 × 100 in a 200 × 100 pane.
        let left = try CompareImages.decode(CompareFixtures.png(width: 200, height: 100) { x, _ in (230, UInt8(x), 20) }).get()
        let right = try CompareImages.decode(CompareFixtures.png(width: 200, height: 100) { x, _ in (20, UInt8(x), 230) }).get()
        let size = CGSize(width: 200, height: 100)
        let rect = CompareGeometry.imageRect(image: left.source, view: size, viewport: .fit)
        #expect(rect == CGRect(x: 0, y: 0, width: 200, height: 100))
        for fraction in [0.0, 0.5, 1.0] {
            let x = CompareWipe.x(fraction, width: size.width)
            let view = CompareWipeImages(left: left, right: right, rect: rect, x: x, height: size.height).frame(width: 200, height: 100)
            let rep = try await render(view, size: size, dark: false)
            for column in [10, 60, 98, 102, 140, 190] {
                let colour = try #require(rep.colorAt(x: column * 2 + 1, y: 100)?.usingColorSpace(.sRGB))
                let red = colour.redComponent * 255, green = colour.greenComponent * 255, blue = colour.blueComponent * 255
                let fromLeft = CGFloat(column) < x
                #expect(fromLeft ? red > 180 && blue < 80 : blue > 180 && red < 80, "column \(column) at \(fraction)")
                // The column shows its own pixel, wherever the divider is.
                #expect(abs(green - CGFloat(column)) < 6, "column \(column) at \(fraction): green \(green)")
            }
        }
    }

    // MARK: Captures

    private static let notesBefore = """
    # Plate reader QC, 21 October

    Eleven plates pass with Z\u{2032} between 0.62 and 0.78.
    Plate 7 fails because of an edge effect in column 12.

    ## Next steps

    - Repeat plate 7 with a fresh seal.
    - Check the incubator\u{2019}s humidity log.
    - Keep the original export.

    | Plate | Z\u{2032} |
    |---|---|
    | 6 | 0.71 |
    | 7 | 0.41 |
    | 8 | 0.74 |

    Readings are from the 21 October run.

    """

    private static let notesAfter = """
    # Plate reader QC, 22 October

    Twelve plates pass with Z\u{2032} between 0.62 and 0.81.
    Plate 7 passes on the repeat, at Z\u{2032} 0.66.

    ## Next steps

    - Check the incubator\u{2019}s humidity log.
    - Keep the original export beside the repeat.
    - Note the new seal\u{2019}s lot number.

    | Plate | Z\u{2032} |
    |---|---|
    | 6 | 0.71 |
    | 7 | 0.66 |
    | 8 | 0.74 |

    Readings are from the 21 October run.

    """

    private func capture(_ model: CompareModel, _ name: String, minimum: Bool = false, to directory: URL) async throws {
        let size = minimum ? NSSize(width: CompareWindowController.minimum.width, height: CompareWindowController.minimum.height + 52)
                           : NSSize(width: CompareWindowController.size.width, height: CompareWindowController.size.height + 52)
        for dark in [false, true] {
            let rep = try await render(Window(model: model), size: size, dark: dark)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)\(minimum ? "-minimum" : "")-\(dark ? "dark" : "light").png"))
        }
    }

    @Test func eachStateIsDrawnWhenAsked() async throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let disk = CompareFakeDisk()
        let before = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC", version: 2)
        let after = CompareFixtures.item("z_prime_by_plate.png", session: "Plate reader QC, repeat", version: 3)
        let square = CompareFixtures.item("plate_7_layout.png", session: "Assay development", version: nil)
        let gone = CompareFixtures.item("z_prime_rerun.png", session: "Plate reader QC, repeat", version: 1)
        disk.put(CompareFixtures.chart(width: 960, height: 640, low: 0.30), at: before.fileURL)
        disk.put(CompareFixtures.chart(width: 960, height: 640, low: 0.66), at: after.fileURL)
        disk.put(CompareFixtures.chart(width: 600, height: 600, low: 0.5), at: square.fileURL)
        let model = CompareModel(reader: disk.reader, announce: { _ in })

        // Pictures side by side, with Wipe offered.
        model.compare(before, after)
        await model.settle()
        try await capture(model, "side-by-side", to: directory)
        try await capture(model, "side-by-side", minimum: true, to: directory)
        // Zoomed in, linked: the same place in both.
        model.zoom(before.id, by: 3, at: CGPoint(x: 300, y: 330), view: CGSize(width: 507, height: 560))
        try await capture(model, "zoomed-linked", to: directory)
        model.fit()
        // Wipe, at half.
        model.setWiping(true)
        model.wipeFraction = 0.5
        try await capture(model, "wipe-50", to: directory)
        try await capture(model, "wipe-50", minimum: true, to: directory)
        // Two sizes: no Wipe.
        model.compare(before, square)
        await model.settle()
        try await capture(model, "unequal", to: directory)
        // One side that can't be read.
        model.compare(before, gone)
        await model.settle()
        try await capture(model, "unreadable-side", to: directory)

        // Text Changes.
        let notes = CompareFixtures.item("qc_notes.md", session: "Plate reader QC", version: 2)
        let revised = CompareFixtures.item("qc_notes.md", session: "Plate reader QC, repeat", version: 3)
        let same = CompareFixtures.item("qc_notes_copy.md", session: "Assay development", version: nil)
        let away = CompareFixtures.item("methods_draft.md", session: "Methods for the paper", version: 1)
        disk.put(Self.notesBefore, at: notes.fileURL)
        disk.put(Self.notesAfter, at: revised.fileURL)
        disk.put(Self.notesBefore.replacingOccurrences(of: "\n", with: "\r\n"), at: same.fileURL)
        disk.put(Data("# Methods".utf8), at: away.fileURL, putAway: true)
        model.compare(notes, revised)
        await model.settle()
        try await capture(model, "text-changes", to: directory)
        try await capture(model, "text-changes", minimum: true, to: directory)
        model.nextChange()
        model.nextChange()
        try await capture(model, "text-changes-next", to: directory)
        model.compare(notes, same)
        await model.settle()
        #expect(model.outcome == .identical)
        try await capture(model, "no-text-changes", to: directory)
        model.compare(notes, away)
        await model.settle()
        try await capture(model, "text-unreadable-side", to: directory)
    }

    @Test func theShelfWithTwoPickedIsDrawnWhenAsked() async throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compare-shelf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), pdf: ShelfPDFMaker(dependencies: .declining))
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        model.pick(try #require(model.shown.first { $0.fileName == "z_prime_by_plate.png" }).id, .only)
        model.pick(try #require(model.shown.first { $0.fileName == "plate_7_heatmap.png" }).id, .toggle)
        #expect(model.comparePair != nil)
        let size = NSSize(width: 940, height: 872)
        for dark in [false, true] {
            let view = VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color).frame(width: 12, height: 12) }
                    Text("Shelf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Solanum.ink).padding(.leading, 8)
                    ShelfProjectPill(model: model)
                    Spacer()
                    ShelfExportPDFButton(model: model)
                    ShelfSearchPill(search: .constant(""), width: 200)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook())
            }
            .background(Solanum.page)
            let rep = try await render(view, size: size, dark: dark)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("shelf-two-picked-\(dark ? "dark" : "light").png"))
        }
    }
}
