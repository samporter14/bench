// ShelfPDFSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, makes the lab-meeting PDF from the demo's made-up shelf (every kind
// of file: figures, a Markdown note, a spreadsheet, a script) and writes the
// PDF and a PNG of each of its pages there, so the pages can be looked at
// without opening anything. Without it the test does nothing.
import AppKit
import ImageIO
import PDFKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Bench

@MainActor
struct ShelfPDFSnapshotTests {
    /// A page of a PDF drawn at `scale` times its size, on white.
    nonisolated static func image(of data: Data, page number: Int, scale: CGFloat = 2) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: number))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        return try #require(context.makeImage())
    }

    /// A page of a PDF as a PNG at `scale` times its size.
    nonisolated static func png(of data: Data, page number: Int, scale: CGFloat = 2) throws -> Data {
        let image = try image(of: data, page: number, scale: scale)
        let out = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    /// The made-up shelf's items, read back from a temporary root.
    static func madeItems(in root: URL) async throws -> (items: [ShelfItem], disk: KeptDisk) {
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        return (ShelfRules.items(from: index.results), disk)
    }

    /// The made-up shelf's items by file name, with the first words of its text files read as Export as PDF… reads them.
    private static func madeShelf(in root: URL) async throws -> (items: [ShelfItem], text: [String: String]) {
        let (items, disk) = try await madeItems(in: root)
        var text: [String: String] = [:]
        for item in items where item.kind == .document {
            if let words = try await disk.peek(item.fileURL, limit: ShelfPDFMaker.textBytes) { text[item.id] = words }
        }
        return (items, text)
    }

    /// The three pages of the lab-meeting PDF in the brief: a figure with Claude's words for its legend, a figure
    /// kept with a legend of its own, and a Markdown note.
    private static func three(_ items: [ShelfItem]) throws -> [ShelfItem] {
        [try #require(items.first { $0.fileName == "z_prime_by_plate.png" }),
         try #require(items.first { $0.title == "Fig 2B \u{00B7} Z\u{2032} by plate" }),
         try #require(items.first { $0.fileName == "qc_notes.md" })]
    }

    @Test func theMadeUpShelfMakesAThreePagePDFWithEachFilesOwnWords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pdf-three-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (items, text) = try await Self.madeShelf(in: root)
        let chosen = try Self.three(items)
        let pages = ShelfPDFRules.pages(for: chosen, text: text, locale: Locale(identifier: "en_US"))
        let data = try ShelfPDF.data(pages)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 3)
        let pdf = try #require(PDFDocument(data: data))
        // The text a PDF gives back has a line break where a line wrapped, and sometimes in a file name.
        func flat(_ index: Int) -> String { (pdf.page(at: index)?.string ?? "").replacingOccurrences(of: "\n", with: " ") }
        func joined(_ index: Int) -> String { (pdf.page(at: index)?.string ?? "").replacingOccurrences(of: "\n", with: "") }
        // Claude's words, kept short, under the file's own name.
        #expect(joined(0).contains("z_prime_by_plate.png") && flat(0).contains("Plate 7 is the low bar, at 0.41 against a cutoff of 0.5"))
        // The keep's name and the person's legend.
        #expect(flat(1).contains("Fig 2B \u{00B7} Z\u{2032} by plate") && flat(1).contains("plate 7 was excluded for an edge effect in column 12."))
        #expect(!flat(1).contains("All plates passed"))
        // The note's own lines on paper.
        #expect(joined(2).contains("qc_notes.md") && flat(2).contains("Plate reader QC, 21 October") && flat(2).contains("Repeat plate 7 with a fresh seal."))
        for index in 0..<3 { #expect(flat(index).contains("Plate reader QC \u{00B7} "), "page \(index + 1)") }
        // Each figure went in with its own pixels.
        for (index, item) in chosen.prefix(2).enumerated() {
            let source = try #require(CGImageSourceCreateWithURL(item.fileURL as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let own = CGSize(width: (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0, height: (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0)
            let embedded = try xObjectSizes(of: data, page: index + 1)
            #expect(own.width > 0 && embedded == [own], "\(item.fileName)")
        }
        #expect(try xObjectSizes(of: data, page: 3).isEmpty)
    }

    /// The sizes of the pictures embedded in a page.
    private func xObjectSizes(of data: Data, page number: Int) throws -> [CGSize] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: number))
        guard let dictionary = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return [] }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }
        final class Found { var sizes: [CGSize] = [] }
        let found = Found()
        CGPDFDictionaryApplyBlock(objects, { _, object, info in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) else { return true }
            var width: CGPDFInteger = 0, height: CGPDFInteger = 0
            guard CGPDFDictionaryGetInteger(dictionary, "Width", &width), CGPDFDictionaryGetInteger(dictionary, "Height", &height) else { return true }
            Unmanaged<Found>.fromOpaque(info!).takeUnretainedValue().sizes.append(CGSize(width: width, height: height))
            return true
        }, Unmanaged.passUnretained(found).toOpaque())
        return found.sizes
    }

    @Test func theLabMeetingPDFIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pdf-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (items, text) = try await Self.madeShelf(in: root)
        let english = Locale(identifier: "en_US")

        // The three pages of the brief.
        let three = ShelfPDFRules.pages(for: try Self.three(items), text: text, locale: english)
        let threeData = try ShelfPDF.data(three)
        try threeData.write(to: directory.appendingPathComponent("lab-meeting.pdf"))
        for index in three.indices {
            try Self.png(of: threeData, page: index + 1).write(to: directory.appendingPathComponent("page-\(index + 1).png"))
        }

        // Every kind of file the shelf holds, a page each.
        let pages = ShelfPDFRules.pages(for: items, text: text, locale: english)
        let data = try ShelfPDF.data(pages)
        try data.write(to: directory.appendingPathComponent("lab-meeting-kinds.pdf"))
        for (index, page) in pages.enumerated() {
            let name = (page.fileName as NSString).deletingPathExtension.replacingOccurrences(of: " ", with: "-")
            try Self.png(of: data, page: index + 1).write(to: directory.appendingPathComponent("kinds-\(index + 1)-\(name).png"))
        }

        // The edges: a title and a legend too long for the page, and a picture with no legend.
        let wide = root.appendingPathComponent("wide.png", isDirectory: false)
        try KeptDemo.heatmap(variant: 1).write(to: wide)
        let source = ShelfPDFRules.page(for: items[0], locale: english)
        let edges = [
            ShelfPDFPage(title: String(repeating: "Z\u{2032} by plate and by well, ", count: 12),
                         legend: String(repeating: "A bar for each plate, and a longer sentence after it. ", count: 12),
                         source: source.source, picture: source.picture, tile: source.tile, fileName: "long"),
            ShelfPDFPage(title: "A heatmap", legend: "", source: source.source, picture: .image(wide), tile: source.tile, fileName: "heatmap"),
        ]
        let edgeData = try ShelfPDF.data(edges)
        try edgeData.write(to: directory.appendingPathComponent("lab-meeting-edges.pdf"))
        for index in edges.indices {
            try Self.png(of: edgeData, page: index + 1).write(to: directory.appendingPathComponent("edge-\(index + 1)-\(edges[index].fileName).png"))
        }
    }

    // MARK: The Shelf window with Export as PDF…

    /// The title bar the window draws around the content (the toolbar belongs to the window), with Export as PDF… in it.
    private struct Window: View {
        let model: ShelfModel
        let content: ShelfView

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color(red: 0.88, green: 0.38, blue: 0.35), Color(red: 0.91, green: 0.69, blue: 0.29), Color(red: 0.42, green: 0.75, blue: 0.36)], id: \.self) { color in
                        Circle().fill(color).frame(width: 12, height: 12)
                    }
                    Text("Shelf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Solanum.ink).padding(.leading, 8)
                    ShelfProjectPill(model: model)
                    Spacer()
                    if model.pickCount > 0 { ShelfExportPDFButton(model: model) }
                    ShelfSearchPill(search: .constant(model.search))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                content
            }
            .background(Solanum.page)
        }
    }

    private func draw(_ model: ShelfModel, thumbnails: KeptThumbnails, size: NSSize, name: String, to directory: URL) async throws {
        let view = Window(model: model, content: ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()))
        for dark in [false, true] {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
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
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    @Test func theShelfWindowWithSeveralPickedIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pdf-window-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        await index.refreshAndWait()
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let size = NSSize(width: 880, height: 820)

        // One selected, as the window opens: Export as PDF… is in the title bar, the detail below.
        let one = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining))
        try await draw(one, thumbnails: thumbnails, size: size, name: "shelf-pdf-one", to: directory)

        // Three picked: numbered cards and the card that asks.
        let three = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining))
        three.pick(three.shown[0].id, .only)
        three.pick(three.shown[1].id, .toggle)
        three.pick(three.shown[3].id, .toggle)
        try await draw(three, thumbnails: thumbnails, size: size, name: "shelf-pdf-three", to: directory)

        // Everything, in the narrowest window.
        let all = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining))
        all.pickAll()
        try await draw(all, thumbnails: thumbnails, size: NSSize(width: 620, height: 640), name: "shelf-pdf-all-small", to: directory)
    }
}
