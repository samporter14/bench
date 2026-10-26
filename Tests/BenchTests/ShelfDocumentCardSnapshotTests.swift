// ShelfDocumentCardSnapshotTests.swift — made-up files, offscreen only. The mock bar is added above the content's
// minimum 620 × 480 points, rather than squeezing the bar into the content height and clipping it.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct ShelfDocumentCardSnapshotTests {
    private struct Window: View {
        let model: ShelfModel
        let thumbnails: KeptThumbnails
        let width: CGFloat
        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in Circle().fill(color).frame(width: 12, height: 12) }
                    Text("Shelf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Solanum.ink).padding(.leading, 8)
                    ShelfProjectPill(model: model)
                    Spacer()
                    ShelfSearchPill(search: .constant(""), width: ShelfSearchPill.width(forWindow: width))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook())
            }
            .background(Solanum.page)
        }
    }

    private func draw(_ item: ShelfItem, model: ShelfModel, thumbnails: KeptThumbnails,
                      narrow: Bool, name: String, to directory: URL) async throws {
        model.selection = item.id
        await model.documents.look(at: item)
        let size = narrow ? NSSize(width: 620, height: 532) : NSSize(width: 940, height: 872)
        for dark in [false, true] {
            let host = NSHostingView(rootView: Window(model: model, thumbnails: thumbnails, width: size.width))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(60))
                host.layoutSubtreeIfNeeded()
            }
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                                    pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)\(narrow ? "-narrow" : "")-\(dark ? "dark" : "light").png"))
        }
    }

    @Test func ordinaryDocumentsAndUnchangedFiguresAndTablesAreDrawnWhenAsked() async throws {
        guard let destination = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-document-cards-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let source = try #require(index.results.first { $0.record.figure.path == "qc_notes.md" })
        let short = "# Plate reader QC\n\nEleven plates pass. **Repeat plate 7** before comparing the final columns.\n\n- Check the edge wells.\n- Keep the original export."
        let paragraph = "The edge wells differ from the middle of the plate. Keep that comparison separate from the overall mean, and record the repeat alongside the original export so the decision remains traceable."
        let long = "# Plate reader QC\n\n" + (1...18).map { "## Check \($0)\n\n" + paragraph }.joined(separator: "\n\n")
        let cases = [("qc_short.md", short), ("qc_long.markdown", long),
                     ("qc_plain.txt", "Plate reader QC\n\nKeep **these marks** as literal text.\n\nThe exported file remains available through Copy, drag and Quick Look.")]
        for (name, words) in cases {
            var record = source.record
            record.name = (name as NSString).deletingPathExtension
            record.figure.path = name
            record.figure.version = UUID().uuidString.lowercased()
            record.figure.bytes = words.utf8.count
            let folder = root.appendingPathComponent("Assay development").appendingPathComponent(record.name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(words.utf8).write(to: folder.appendingPathComponent(name))
            try Data(KeptReadme.render(record, text: source.text).utf8).write(to: folder.appendingPathComponent("README.md"))
        }
        await index.refreshAndWait()
        let shelf = KeptDemo.shelf(index: index, root: root)
        let model = ShelfModel(shelf: shelf)
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        for (file, name) in [("qc_short.md", "document-short"), ("qc_long.markdown", "document-long"),
                             ("qc_plain.txt", "document-plain"), ("z_prime_by_plate.png", "document-figure-comparison"),
                             ("receptors.xlsx", "document-table-comparison")] {
            let item = try #require(model.items.first { $0.fileName == file })
            for narrow in [false, true] {
                try await draw(item, model: model, thumbnails: thumbnails, narrow: narrow, name: name, to: directory)
            }
        }
        // A missing supported document must retain the old preview card and its source words.
        let missing = try #require(model.items.first { $0.fileName == "qc_short.md" })
        try FileManager.default.moveItem(at: missing.fileURL, to: missing.fileURL.appendingPathExtension("away"))
        try await draw(missing, model: model, thumbnails: thumbnails, narrow: true, name: "document-missing", to: directory)
        #expect(model.documents.reading(for: missing) == .none)
    }
}
