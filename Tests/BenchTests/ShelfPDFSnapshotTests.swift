// ShelfPDFSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, makes the lab-meeting PDF from the demo's made-up shelf (every kind
// of file: figures, a Markdown note, a spreadsheet, a script) and writes the
// PDF and a PNG of each of its pages there, so the pages can be looked at
// without opening anything. Without it the test does nothing.
import AppKit
import ImageIO
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

    @Test func theLabMeetingPDFIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pdf-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (items, disk) = try await Self.madeItems(in: root)
        var text: [String: String] = [:]
        for item in items where item.kind == .document {
            if let words = try await disk.peek(item.fileURL, limit: 20_000) { text[item.id] = words }
        }
        let english = Locale(identifier: "en_US")
        let pages = ShelfPDFRules.pages(for: items, text: text, locale: english)
        let data = try ShelfPDF.data(pages)
        try data.write(to: directory.appendingPathComponent("lab-meeting.pdf"))
        for (index, page) in pages.enumerated() {
            let png = try Self.png(of: data, page: index + 1)
            let name = (page.fileName as NSString).deletingPathExtension.replacingOccurrences(of: " ", with: "-")
            try png.write(to: directory.appendingPathComponent("page-\(index + 1)-\(name).png"))
        }

        // The edges: a title and a legend too long for the page, a small picture, a wide one, a PDF's first page.
        let wide = root.appendingPathComponent("wide.png", isDirectory: false)
        try KeptDemo.heatmap(variant: 1).write(to: wide)
        let first = items.first { $0.kind == .figure }!
        let source = ShelfPDFRules.page(for: first, locale: english)
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
}
