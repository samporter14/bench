// ShelfPDFRenderTests.swift — the drawing of the lab-meeting PDF
// (Kept/ShelfPDF.swift) on real files made here: one 16:9 page for each page
// asked for, its words as text, a picture embedded at its own pixels and drawn
// no bigger than them and never stretched, a PDF's first page as a vector, a
// Markdown note as plain text, a tile for the rest, a file that can't be
// opened as a sentence's worth of failure, and a PDF that is written whole or
// not at all. The pages are read back with PDFKit and Core Graphics.
import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Bench

private final class Folder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-pdf-render-\(UUID().uuidString)", isDirectory: true)

    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    func remove() { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appendingPathComponent(name, isDirectory: false) }

    /// A PNG of one flat colour.
    func png(_ name: String, width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 1) throws -> URL {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let target = file(name)
        let destination = try #require(CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return target
    }

    /// A one-page PDF with a flat red rectangle on it, `width` by `height` points.
    func pdf(_ name: String, width: CGFloat, height: CGFloat) throws -> URL {
        let target = file(name)
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let context = try #require(CGContext(target as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return target
    }
}

private func page(_ title: String = "z_prime_by_plate.png", legend: String = "", source: String = "Plate reader QC \u{00B7} Assay development \u{00B7} 22 Oct 2026",
                  picture: ShelfPDFPage.Picture, name: String? = nil,
                  tile: ShelfPDFPage.Tile = .init(label: "PNG", detail: "Figure \u{00B7} 4 KB")) -> ShelfPDFPage {
    ShelfPDFPage(title: title, legend: legend, source: source, picture: picture, tile: tile, fileName: name ?? title)
}

/// The pixels of a page drawn at 2× and where the flat-coloured ones are: the box of every pixel the test accepts.
private func box(of data: Data, page number: Int = 1, where matches: (UInt8, UInt8, UInt8) -> Bool) throws -> CGRect? {
    let image = try ShelfPDFSnapshotTests.image(of: data, page: number, scale: 2)
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var minX = width, maxX = -1, minY = height, maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            let at = (y * width + x) * 4
            if matches(pixels[at], pixels[at + 1], pixels[at + 2]) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    // Back to points, from the top left, as the layout has it.
    return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2, width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
}

private func isMagenta(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { r > 200 && g < 60 && b > 200 }
private func isRed(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { r > 200 && g < 60 && b < 60 }

/// The streams of a page's resources: how many are images, how many forms, and each image's size.
private func xObjects(of data: Data, page number: Int) throws -> (images: [CGSize], forms: Int) {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    let page = try #require(document.page(at: number))
    var images: [CGSize] = []
    var forms = 0
    guard let dictionary = page.dictionary else { return ([], 0) }
    var resources: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return ([], 0) }
    var objects: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return ([], 0) }
    final class Found { var images: [CGSize] = []; var forms = 0 }
    let found = Found()
    CGPDFDictionaryApplyBlock(objects, { _, object, info in
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) else { return true }
        let found = Unmanaged<Found>.fromOpaque(info!).takeUnretainedValue()
        var subtype: UnsafePointer<Int8>?
        _ = CGPDFDictionaryGetName(dictionary, "Subtype", &subtype)
        let name = subtype.map { String(cString: $0) }
        if name == "Image" {
            var width: CGPDFInteger = 0, height: CGPDFInteger = 0
            _ = CGPDFDictionaryGetInteger(dictionary, "Width", &width)
            _ = CGPDFDictionaryGetInteger(dictionary, "Height", &height)
            found.images.append(CGSize(width: width, height: height))
        } else if name == "Form" {
            found.forms += 1
        }
        return true
    }, Unmanaged.passUnretained(found).toOpaque())
    images = found.images
    forms = found.forms
    return (images, forms)
}

@MainActor
struct ShelfPDFRenderTests {
    private func text(_ data: Data, page: Int? = nil) throws -> String {
        let document = try #require(PDFDocument(data: data))
        if let page { return document.page(at: page - 1)?.string ?? "" }
        return document.string ?? ""
    }

    @Test func oneSixteenByNinePageForEachPageAskedForAndNoneForNone() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("a.png", width: 600, height: 400)
        let pages = [page("a.png", picture: .image(image)), page("b.csv", picture: .tile), page("c.md", picture: .text([.heading("C")]))]
        let data = try ShelfPDF.data(pages)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 3)
        for number in 1...3 {
            let box = try #require(document.page(at: number)).getBoxRect(.mediaBox)
            #expect(box.size == CGSize(width: 960, height: 540), "page \(number)")
        }
    }

    @Test func theWordsAreTextOnThePageTheTitleTheLegendAndWhereItCameFromAndTheNumbersOnlyWithSeveral() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("a.png", width: 600, height: 400)
        let many = try ShelfPDF.data([
            page("Z\u{2032} by plate", legend: "Plate 7 is the low bar, at 0.41.", picture: .image(image)),
            page("Second", picture: .tile),
        ])
        let first = try text(many, page: 1)
        #expect(first.contains("Z\u{2032} by plate"))
        #expect(first.contains("Plate 7 is the low bar, at 0.41."))
        #expect(first.contains("Plate reader QC \u{00B7} Assay development \u{00B7} 22 Oct 2026"))
        #expect(first.contains("1 / 2"))
        #expect(try text(many, page: 2).contains("2 / 2"))
        let one = try text(try ShelfPDF.data([page("Only", picture: .tile)]))
        #expect(one.contains("Only") && !one.contains("1 / 1"))
    }

    @Test func aLongTitleAndALongLegendAreCutWithEllipsesNotRunOffThePage() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("a.png", width: 600, height: 400)
        let title = String(repeating: "Z\u{2032} by plate and by well, ", count: 12)
        let legend = String(repeating: "A bar for each plate, and a longer sentence after it. ", count: 12)
        let data = try ShelfPDF.data([page(title, legend: legend, picture: .image(image))])
        let words = try text(data)
        // Cut, not wrapped or run on: the start of each is there, the whole of neither (the ellipsis is a glyph
        // the text extraction leaves out, so it is looked at in the snapshot).
        #expect(words.contains("Z\u{2032} by plate and by well, Z\u{2032} by plate"))
        #expect(!words.contains(title))
        #expect(!words.contains(legend))
        #expect(words.split(separator: "\n").count == 5)
        // At most three lines of legend, so the figure keeps its room.
        let figure = try #require(try box(of: data, where: isMagenta))
        // The title came down to 14 points to fit, and the legend is three lines: that much room is used, no more.
        let room = ShelfPDFLayout.regions(titleHeight: ShelfPDFLayout.titleHeight(for: ShelfPDFLayout.titleMin),
                                          legendHeight: CGFloat(ShelfPDFLayout.legendLines) * ShelfPDFLayout.legendLeading).figure
        #expect(figure.minY >= room.minY - 1.5 && figure.maxY <= room.maxY + 1.5, "\(figure) in \(room)")
    }

    @Test func aPictureIsEmbeddedWithItsOwnPixelsAndNeverAsACopyAtScreenSize() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("a.png", width: 1234, height: 567)
        let data = try ShelfPDF.data([page(picture: .image(image))])
        let found = try xObjects(of: data, page: 1)
        #expect(found.images == [CGSize(width: 1234, height: 567)])
    }

    @Test func aSmallPictureIsDrawnNoBiggerThanItsPixelsAndCentredInTheRoomTheWordsLeave() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("small.png", width: 200, height: 100)
        let data = try ShelfPDF.data([page(picture: .image(image))])
        let drawn = try #require(try box(of: data, where: isMagenta))
        #expect(abs(drawn.width - 200) <= 1.5 && abs(drawn.height - 100) <= 1.5, "\(drawn)")
        let room = ShelfPDFLayout.regions(titleHeight: ShelfPDFLayout.titleHeight(for: 20), legendHeight: 0).figure
        #expect(abs(drawn.midX - room.midX) <= 1.5 && abs(drawn.midY - room.midY) <= 1.5, "\(drawn) in \(room)")
    }

    @Test func aBigPictureFillsTheRoomOnItsTightSideKeepingItsShape() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let room = ShelfPDFLayout.regions(titleHeight: ShelfPDFLayout.titleHeight(for: 20), legendHeight: 0).figure
        // Wider than the room: it takes the width. Taller: it takes the height.
        let wide = try folder.png("wide.png", width: 6000, height: 1000)
        let tall = try folder.png("tall.png", width: 1000, height: 6000)
        let wideBox = try #require(try box(of: try ShelfPDF.data([page(picture: .image(wide))]), where: isMagenta))
        #expect(abs(wideBox.width - room.width) <= 1.5 && abs(wideBox.width / wideBox.height - 6) < 0.1, "\(wideBox)")
        let tallBox = try #require(try box(of: try ShelfPDF.data([page(picture: .image(tall))]), where: isMagenta))
        #expect(abs(tallBox.height - room.height) <= 1.5 && abs(tallBox.height / tallBox.width - 6) < 0.15, "\(tallBox)")
        #expect(room.insetBy(dx: -1.5, dy: -1.5).contains(tallBox) && room.insetBy(dx: -1.5, dy: -1.5).contains(wideBox))
    }

    @Test func aLegendTakesRoomFromThePictureAndAPageWithoutOneGivesItBack() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("big.png", width: 3000, height: 2000)
        let bare = try #require(try box(of: try ShelfPDF.data([page(picture: .image(image))]), where: isMagenta))
        let worded = try #require(try box(of: try ShelfPDF.data([page(legend: "Plate 7 is the low bar.", picture: .image(image))]), where: isMagenta))
        #expect(worded.height < bare.height)
        #expect(abs(worded.width / worded.height - 1.5) < 0.02 && abs(bare.width / bare.height - 1.5) < 0.02)
    }

    @Test func aPDFsFirstPageIsDrawnAsAVectorAndAsLargeAsTheRoomAllows() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let source = try folder.pdf("report.pdf", width: 300, height: 200)
        let data = try ShelfPDF.data([page("report.pdf", picture: .pdf(source))])
        let found = try xObjects(of: data, page: 1)
        #expect(found.images.isEmpty)
        let drawn = try #require(try box(of: data, where: isRed))
        let room = ShelfPDFLayout.regions(titleHeight: ShelfPDFLayout.titleHeight(for: 20), legendHeight: 0).figure
        // Not capped at its own size: a vector has none.
        #expect(abs(drawn.height - room.height) <= 1.5 && abs(drawn.width / drawn.height - 1.5) < 0.02, "\(drawn)")
    }

    @Test func aMarkdownNoteIsPlainTextOnPaper() throws {
        let data = try ShelfPDF.data([page("qc_notes.md", picture: .text([
            .heading("Plate reader QC, 21 October"),
            .paragraph("Eleven plates pass with Z\u{2032} between 0.62 and 0.78."),
            .bullet("Repeat plate 7"),
        ]))])
        let words = try text(data)
        #expect(words.contains("Plate reader QC, 21 October"))
        #expect(words.contains("Eleven plates pass with Z\u{2032} between 0.62 and 0.78."))
        #expect(words.contains("Repeat plate 7"))
    }

    @Test func aNoteTooLongForThePageEndsWithAnEllipsisAndLeavesTheRestOut() throws {
        let blocks = (1...60).map { ShelfPDFBlock.paragraph("Paragraph \($0) of the note, which says something about plate \($0) and how it went.") }
        let words = try text(try ShelfPDF.data([page("long.md", picture: .text(blocks))]))
        #expect(words.contains("Paragraph 1 of the note"))
        #expect(!words.contains("Paragraph 60 of the note"))
        #expect(words.contains("\u{2026}"))
    }

    @Test func everythingElseIsATileWithTheKindAndTheSizeAndNoPictureIsEmbedded() throws {
        let data = try ShelfPDF.data([page("plates.csv", picture: .tile, tile: .init(label: "CSV", detail: "Table \u{00B7} 4 KB"))])
        let words = try text(data)
        #expect(words.contains("CSV") && words.contains("Table \u{00B7} 4 KB") && words.contains("plates.csv"))
        #expect(try xObjects(of: data, page: 1).images.isEmpty)
    }

    @Test func aPictureThatCantBeDecodedIsATileNotAFailure() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let broken = folder.file("broken.png")
        try Data("not a picture".utf8).write(to: broken)
        let words = try text(try ShelfPDF.data([page("broken.png", picture: .image(broken))]))
        #expect(words.contains("PNG") && words.contains("Figure \u{00B7} 4 KB"))
        // A PDF with nothing to draw likewise.
        let notPDF = folder.file("not.pdf")
        try Data("%not really".utf8).write(to: notPDF)
        #expect(try text(try ShelfPDF.data([page("not.pdf", picture: .pdf(notPDF), tile: .init(label: "PDF", detail: "Document \u{00B7} 1 KB"))])).contains("Document \u{00B7} 1 KB"))
    }

    @Test func aFileThatCantBeOpenedStopsThePDFAndNamesTheFile() throws {
        let folder = try Folder()
        defer { folder.remove() }
        let gone = folder.file("gone.png")
        #expect(throws: ShelfPDF.Failure.unreadable("gone.png")) {
            try ShelfPDF.data([page("gone.png", picture: .image(gone))])
        }
        #expect(throws: ShelfPDF.Failure.unreadable("gone.pdf")) {
            try ShelfPDF.data([page("gone.pdf", picture: .pdf(folder.file("gone.pdf")))])
        }
    }

    @Test func theFileIsWrittenWholeAndReplacesAnOldOneOnlyWhenItIs() async throws {
        let folder = try Folder()
        defer { folder.remove() }
        let image = try folder.png("a.png", width: 300, height: 200)
        let target = folder.file("Lab meeting 2026-10-22.pdf")
        let counted = Counted()
        try await ShelfPDF.make([page(picture: .image(image)), page("b", picture: .tile)], to: target, title: "Lab meeting 2026-10-22") { counted.add($0) }
        let document = try #require(PDFDocument(url: target))
        #expect(document.pageCount == 2)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Lab meeting 2026-10-22")
        #expect(counted.values == [1, 2])
        // A failure leaves what was there alone.
        let before = try Data(contentsOf: target)
        await #expect(throws: ShelfPDF.Failure.unreadable("gone.png")) {
            try await ShelfPDF.make([page("gone.png", picture: .image(folder.file("gone.png")))], to: target)
        }
        #expect(try Data(contentsOf: target) == before)
        // And a new one replaces it.
        try await ShelfPDF.make([page("c", picture: .tile)], to: target)
        #expect(PDFDocument(url: target)?.pageCount == 1)
        // A folder that isn't there is a failure to save, not a crash.
        await #expect(throws: ShelfPDF.Failure.cantWrite) {
            try await ShelfPDF.make([page("c", picture: .tile)], to: folder.file("nowhere/inside.pdf"))
        }
    }
}

/// Page counts told from the drawing's queue.
private final class Counted: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [Int] = []
    func add(_ value: Int) { lock.lock(); all.append(value); lock.unlock() }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return all }
}
