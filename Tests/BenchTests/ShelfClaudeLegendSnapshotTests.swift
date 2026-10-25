// ShelfClaudeLegendSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a folder, draws the detail card of a
// shelved figure with Claude's legend on offer (Kept/ShelfClaudeLegendView.swift) into it as PNGs, light and dark: the
// offer for a figure shelved alone, the offer with several files to choose from (the name is a menu; an open menu can't be
// drawn off screen, so a stand-in for it is drawn beside the card), after the legend was used (the legend field filled, the
// file listed, the pill with Undo), and the offer to replace a written legend. Without the variable the test does nothing.
// Made-up plates, a made-up bar chart as the figure, a scratch Kept folder.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct ShelfClaudeLegendSnapshotTests {
    /// A small bar chart, as PNG bytes: the figure.
    private static func chart() -> Data {
        let size = NSSize(width: 640, height: 320)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let values: [CGFloat] = [0.82, 0.79, 0.84, 0.77, 0.81, 0.80, 0.41, 0.83]
        for (i, value) in values.enumerated() {
            (i == 6 ? NSColor(red: 0.82, green: 0.38, blue: 0.27, alpha: 1) : NSColor(red: 0.30, green: 0.36, blue: 0.45, alpha: 1)).setFill()
            NSRect(x: 50 + CGFloat(i) * 72, y: 40, width: 48, height: value * 240).fill()
        }
        NSColor(white: 0.55, alpha: 1).setFill()
        NSRect(x: 40, y: 40, width: 560, height: 1).fill()
        NSRect(x: 40, y: 40 + 0.5 * 240, width: 560, height: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private func draw<Content: View>(_ content: Content, size: CGSize, name: String, to directory: URL) async throws {
        for dark in [false, true] {
            let host = NSHostingView(rootView: content.background(Solanum.page))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<14 {
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
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    /// The detail card as the window draws it, with the pill under it when there is one.
    private struct Card: View {
        let rig: ClaudeLegendRig
        let item: ShelfItem
        let thumbnails: KeptThumbnails
        var body: some View {
            VStack(spacing: 0) {
                ShelfDetail(item: item, model: rig.model, thumbnails: thumbnails, quickLook: KeptQuickLook(), keep: {},
                            maxHeight: 440, previewWidth: ShelfDetail.previewWidth(forWindow: 900))
                if let note = rig.model.note {
                    ShelfNote(note: note, undo: {})
                        .padding(.top, 4)
                }
            }
            .frame(width: 900, alignment: .top)
        }
    }

    /// What an open menu of the candidates looks like, drawn by hand beside the card: the system draws the real one.
    private struct StandInMenu: View {
        let names: [String]
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 24, alignment: .leading)
                }
            }
            .padding(.vertical, 5)
            .frame(width: 230, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        }
    }

    @Test func theOfferIsDrawnForAFigureShelvedAloneWithSeveralFilesAfterUseAndForAWrittenLegendWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rig = try ClaudeLegendRig()
        defer { rig.tearDown() }
        rig.science.bytes[ClaudeLegendMade.figure] = Self.chart()
        rig.science.files = [ClaudeLegendMade.legendsFile]
        let thumbnails = KeptThumbnails(peek: { url in (try? await rig.disk.peek(url)) ?? nil })
        let size = CGSize(width: 900, height: 330)

        // 1. A figure shelved alone: one quiet line under the card's main row.
        var item = try await rig.shelve()
        await rig.model.claudeLegend.look(at: item)
        try await draw(Card(rig: rig, item: item, thumbnails: thumbnails), size: size, name: "legend-1-offer", to: directory)

        // 2. After using it: the legend in the field, the file listed beside the figure, the pill with Undo.
        let candidate = try #require(rig.model.claudeLegend.candidates(for: item).first)
        await rig.model.useClaudeLegend(candidate, for: item, confirmed: false)
        item = try rig.item()
        try await draw(Card(rig: rig, item: item, thumbnails: thumbnails), size: CGSize(width: 900, height: 400), name: "legend-2-after", to: directory)

        // 3. A written legend: the line reads "Replace with Claude's legend…" (the question is the system's, drawn when asked).
        rig.model.dismissNote()
        let editor = rig.model.legendEditor(for: item)
        await editor.show()
        editor.legend = "Z\u{2032} per plate from the 22 October run; plate 7 repeated after the edge fix."
        await editor.settle()
        item = try rig.item()
        try await draw(Card(rig: rig, item: item, thumbnails: thumbnails), size: CGSize(width: 900, height: 400), name: "legend-3-replace", to: directory)

        // 4. Several files to choose from: the name is a small menu. A second figure, shelved by itself.
        let other = try ClaudeLegendRig()
        defer { other.tearDown() }
        other.science.bytes[ClaudeLegendMade.figure] = Self.chart()
        other.science.files = [ClaudeLegendMade.siblingFile, ClaudeLegendMade.legendsFile,
                               ClaudeLegendMade.historyFile("aaaaaaaa-0000-4000-8000-000000000205", "fig1_legend.md", size: 900)]
        let thumbnailsOther = KeptThumbnails(peek: { url in (try? await other.disk.peek(url)) ?? nil })
        let several = try await other.shelve()
        await other.model.claudeLegend.look(at: several)
        try await draw(Card(rig: other, item: several, thumbnails: thumbnailsOther), size: size, name: "legend-4-several", to: directory)
        let menu = ZStack(alignment: .topLeading) {
            Card(rig: other, item: several, thumbnails: thumbnailsOther)
            StandInMenu(names: other.model.claudeLegend.candidates(for: several).map(\.name))
                .offset(x: 168, y: 232)
        }
        try await draw(menu, size: CGSize(width: 900, height: 450), name: "legend-5-several-menu", to: directory)
    }
}
