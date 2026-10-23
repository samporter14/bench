// ShelfPDF.swift — draws the lab-meeting PDF (DESIGN.md, Shelf → Lab-meeting
// PDF) from `ShelfPDFPage`s: one 16:9 sheet for each figure, white, in
// Solanum's ink and type. The title is set at the top left, the legend under
// it, the picture as large as the room allows without being stretched or
// drawn bigger than its own pixels, and a small line closes the page with
// where it came from.
//
// It is drawn straight into a PDF `CGContext` with Core Text and ImageIO, not
// through `ImageRenderer`, which is main-actor and would put the disk reads
// there: the words stay text (searchable, sharp at any zoom), a picture goes
// in with its own pixels (the PDF context passes a JPEG through untouched and
// stores a PNG's pixels as they are, never resampled), a PDF is drawn as the
// vector it is, and the rest is a quiet tile. Everything here runs on a queue
// of its own, off the main actor; the files it reads are opened by ImageIO and
// Core Graphics, and the one thing it writes is the PDF, whole, or not at all.
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum ShelfPDF {
    /// What stops a PDF being made.
    enum Failure: Error, Equatable {
        /// A file of a page can't be opened: moved, deleted, or its disk isn't there.
        case unreadable(String)
        /// The PDF can't be written where it was asked.
        case cantWrite
    }

    /// The queue the drawing runs on, one PDF at a time.
    private static let queue = DispatchQueue(label: "local.sam.bench.shelf-pdf", qos: .userInitiated)

    /// Makes the PDF at `url`, replacing what is there only when it is whole.
    /// `progress` is told how many pages are done, from the drawing's queue.
    static func make(_ pages: [ShelfPDFPage], to url: URL, title: String = "Lab meeting",
                     progress: (@Sendable (Int) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { try write(pages, to: url, title: title, progress: progress) })
            }
        }
    }

    /// The PDF's bytes, for the tests and for looking at a page.
    static func data(_ pages: [ShelfPDFPage], title: String = "Lab meeting") throws -> Data {
        let bytes = CFDataCreateMutable(nil, 0)!
        guard let consumer = CGDataConsumer(data: bytes) else { throw Failure.cantWrite }
        try draw(pages, into: consumer, title: title, progress: nil)
        return bytes as Data
    }

    // MARK: Writing

    private static var files: FileManager { FileManager.default }

    private static func write(_ pages: [ShelfPDFPage], to url: URL, title: String, progress: (@Sendable (Int) -> Void)?) throws {
        // Into a temporary file first: a PDF that fails half way never replaces one that was whole.
        let temporary = URL.temporaryDirectory.appending(path: "Capsid-\(UUID().uuidString).pdf", directoryHint: .notDirectory)
        do {
            guard let consumer = CGDataConsumer(url: temporary as CFURL) else { throw Failure.cantWrite }
            try draw(pages, into: consumer, title: title, progress: progress)
            if (try? files.replaceItemAt(url, withItemAt: temporary)) == nil {
                try files.moveItem(at: temporary, to: url)
            }
        } catch {
            try? files.removeItem(at: temporary)
            throw error is Failure ? error : Failure.cantWrite
        }
    }

    // MARK: Drawing

    private static func draw(_ pages: [ShelfPDFPage], into consumer: CGDataConsumer, title: String,
                             progress: (@Sendable (Int) -> Void)?) throws {
        var box = CGRect(origin: .zero, size: ShelfPDFLayout.page)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Capsid"]
        guard let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { throw Failure.cantWrite }
        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            try Sheet(context: context, page: page, number: index + 1, of: pages.count).draw()
            context.endPDFPage()
            progress?(index + 1)
        }
        context.closePDF()
    }

    // MARK: Colours and type

    /// The page is white in every appearance; these are Solanum's light tokens.
    private static let ink = CGColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255, alpha: 1)
    private static let muted = CGColor(srgbRed: 0x5E / 255, green: 0x5D / 255, blue: 0x59 / 255, alpha: 1)
    private static let hairline = CGColor(srgbRed: 31 / 255, green: 30 / 255, blue: 29 / 255, alpha: 0.18)
    /// The paper a tile or a text sits on: Solanum's ivory.
    private static let paper = CGColor(srgbRed: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255, alpha: 1)
    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    }

    private static func attributed(_ text: String, _ font: CTFont, _ color: CGColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
    }

    /// A line's width in points.
    static func width(of text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, font(size, weight), ink))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// The lines `text` breaks into at `width`, at most `maxLines` of them; the
    /// last ends with an ellipsis when there was more.
    private static func lines(_ text: NSAttributedString, width: CGFloat, maxLines: Int) -> [CTLine] {
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        let length = text.length
        var result: [CTLine] = []
        var start = 0
        while start < length, result.count < maxLines {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            if result.count == maxLines - 1, start + count < length {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length - start))
                let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}",
                                                                                 attributes: text.attributes(at: max(0, length - 1), effectiveRange: nil)))
                result.append(CTLineCreateTruncatedLine(rest, Double(width), .end, token) ?? rest)
                break
            }
            result.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return result
    }

    /// One line, cut with an ellipsis when it is wider than `width`.
    private static func oneLine(_ text: NSAttributedString, width: CGFloat) -> CTLine {
        let line = CTLineCreateWithAttributedString(text)
        guard CTLineGetTypographicBounds(line, nil, nil, nil) > Double(width) else { return line }
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}",
                                                                         attributes: text.attributes(at: 0, effectiveRange: nil)))
        return CTLineCreateTruncatedLine(line, Double(width), .end, token) ?? line
    }

    // MARK: One sheet

    /// A page's drawing, in the layout's top-left coordinates, turned over for PDF.
    private struct Sheet {
        let context: CGContext
        let page: ShelfPDFPage
        let number: Int
        let of: Int

        private var height: CGFloat { ShelfPDFLayout.page.height }

        /// A rect from the layout's space (origin top left) into the PDF's.
        private func pdf(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }

        init(context: CGContext, page: ShelfPDFPage, number: Int, of: Int) {
            self.context = context
            self.page = page
            self.number = number
            self.of = of
        }

        func draw() throws {
            context.setFillColor(ShelfPDF.white)
            context.fill(CGRect(origin: .zero, size: ShelfPDFLayout.page))

            // The words first: how tall they come out decides the figure's room.
            let titleSize = ShelfPDFLayout.titleSize(for: page.title, width: ShelfPDFLayout.contentWidth) {
                ShelfPDF.width(of: $0, size: $1, weight: .semibold)
            }
            let title = ShelfPDF.oneLine(ShelfPDF.attributed(page.title, ShelfPDF.font(titleSize, .semibold), ShelfPDF.ink),
                                         width: ShelfPDFLayout.contentWidth)
            let legend = page.legend.isEmpty ? [] : ShelfPDF.lines(
                ShelfPDF.attributed(page.legend, ShelfPDF.font(ShelfPDFLayout.legendSize), ShelfPDF.ink),
                width: ShelfPDFLayout.legendWidth, maxLines: ShelfPDFLayout.legendLines)
            let regions = ShelfPDFLayout.regions(titleHeight: ShelfPDFLayout.titleHeight(for: titleSize),
                                                 legendHeight: CGFloat(legend.count) * ShelfPDFLayout.legendLeading)

            drawLine(title, in: regions.title, leading: regions.title.height)
            for (row, line) in legend.enumerated() {
                let box = CGRect(x: regions.legend.minX, y: regions.legend.minY + CGFloat(row) * ShelfPDFLayout.legendLeading,
                                 width: regions.legend.width, height: ShelfPDFLayout.legendLeading)
                drawLine(line, in: box, leading: ShelfPDFLayout.legendLeading)
            }
            try drawPicture(in: regions.figure)
            drawFooter(in: regions.footer)
        }

        // MARK: Text

        /// A line of text with its baseline set inside a box `leading` tall.
        private func drawLine(_ line: CTLine, in box: CGRect, leading: CGFloat, alignRight: Bool = false) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, gap: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &gap))
            let baseline = box.minY + (leading - (ascent + descent)) / 2 + ascent
            let x = alignRight ? box.maxX - width : box.minX
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x, y: height - baseline)
            CTLineDraw(line, context)
        }

        private func drawFooter(in box: CGRect) {
            let small = ShelfPDF.font(ShelfPDFLayout.sourceSize)
            var room = box.width
            if of > 1 {
                let numbers = ShelfPDF.attributed("\(number) / \(of)", small, ShelfPDF.muted)
                let line = CTLineCreateWithAttributedString(numbers)
                room -= CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 24
                drawLine(line, in: box, leading: box.height, alignRight: true)
            }
            guard !page.source.isEmpty else { return }
            drawLine(ShelfPDF.oneLine(ShelfPDF.attributed(page.source, small, ShelfPDF.muted), width: max(0, room)),
                     in: box, leading: box.height)
        }

        // MARK: The picture

        private func drawPicture(in box: CGRect) throws {
            switch page.picture {
            case .image(let url):
                if try drawImage(url, in: box) { return }
            case .pdf(let url):
                if try drawFirstPage(of: url, in: box) { return }
            case .text(let blocks):
                drawText(blocks, in: box)
                return
            case .tile:
                break
            }
            drawTile(in: box)
        }

        /// The picture's frame: a hairline just outside it, so a figure with a white ground has an edge.
        private func frame(_ rect: CGRect) {
            context.setStrokeColor(ShelfPDF.hairline)
            context.setLineWidth(0.75)
            context.stroke(pdf(rect).insetBy(dx: -0.4, dy: -0.4))
        }

        /// A picture file at its own pixels, as large as the box allows and no larger than one point to a pixel.
        /// False when ImageIO can't read it (it is drawn as a tile); throws when the file can't be opened.
        private func drawImage(_ url: URL, in box: CGRect) throws -> Bool {
            guard let provider = CGDataProvider(url: url as CFURL) else { throw Failure.unreadable(page.fileName) }
            if url.pathExtension.lowercased() == "svg" { return drawSVG(url, in: box) }
            guard let source = CGImageSourceCreateWithDataProvider(provider, nil), CGImageSourceGetCount(source) > 0,
                  let image = Self.decode(source) else { return false }
            let target = ShelfPDFLayout.fit(CGSize(width: image.width, height: image.height), in: box,
                                            maxScale: ShelfPDFLayout.maxPointsPerPixel)
            guard target.width > 0 else { return false }
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(image, in: pdf(target))
            context.restoreGState()
            frame(target)
            return true
        }

        /// The first frame, turned upright when the file says it is on its side.
        private static func decode(_ source: CGImageSource) -> CGImage? {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            if orientation == 1 { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
            let longest = max((properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
                              (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0)
            guard longest > 0 else { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: longest,
            ] as CFDictionary)
        }

        /// An SVG, which ImageIO doesn't read: AppKit's image draws it as paths.
        private func drawSVG(_ url: URL, in box: CGRect) -> Bool {
            guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return false }
            let target = ShelfPDFLayout.fit(image.size, in: box)
            guard target.width > 0 else { return false }
            context.saveGState()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: pdf(target), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            frame(target)
            return true
        }

        /// A PDF's first page, as the vector it is. False for one that is locked or has no pages.
        private func drawFirstPage(of url: URL, in box: CGRect) throws -> Bool {
            guard let provider = CGDataProvider(url: url as CFURL) else { throw Failure.unreadable(page.fileName) }
            guard let document = CGPDFDocument(provider), document.isUnlocked, document.numberOfPages > 0,
                  let first = document.page(at: 1) else { return false }
            let media = first.getBoxRect(.cropBox)
            let sideways = first.rotationAngle % 180 != 0
            let size = sideways ? CGSize(width: media.height, height: media.width) : media.size
            let target = ShelfPDFLayout.fit(size, in: box)
            guard target.width > 0 else { return false }
            context.saveGState()
            context.setFillColor(ShelfPDF.white)
            context.fill(pdf(target))
            context.clip(to: pdf(target))
            // The page's own turn and crop, then up (or down) to the target: the drawing transform doesn't scale up.
            context.translateBy(x: pdf(target).minX, y: pdf(target).minY)
            let scale = target.width / size.width
            context.scaleBy(x: scale, y: scale)
            context.concatenate(first.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(first)
            context.restoreGState()
            frame(target)
            return true
        }

        // MARK: A text file

        /// A Markdown or text file's first lines on paper, as large as will fit, ending with an ellipsis where it was cut.
        private func drawText(_ blocks: [ShelfPDFBlock], in box: CGRect) {
            let width = min(box.width, 680)
            let inset: CGFloat = 28
            let textWidth = width - 2 * inset
            struct Laid {
                let lines: [CTLine]
                let top: CGFloat
                let leading: CGFloat
                let indent: CGFloat
                let bullet: Bool
            }
            var laid: [Laid] = []
            var y: CGFloat = inset
            var bottom: CGFloat = inset
            let room = box.height - inset
            var needsEllipsis = false
            for (index, block) in blocks.enumerated() {
                let (text, leading, indent, gap): (NSAttributedString, CGFloat, CGFloat, CGFloat)
                switch block {
                case .heading(let words):
                    (text, leading, indent, gap) = (ShelfPDF.attributed(words, ShelfPDF.font(17, .semibold), ShelfPDF.ink), 24, 0, 8)
                case .paragraph(let words):
                    (text, leading, indent, gap) = (ShelfPDF.attributed(words, ShelfPDF.font(13.5), ShelfPDF.ink), 20, 0, 10)
                case .bullet(let words):
                    (text, leading, indent, gap) = (ShelfPDF.attributed(words, ShelfPDF.font(13.5), ShelfPDF.ink), 20, 18, 4)
                }
                let wanted = ShelfPDF.lines(text, width: textWidth - indent, maxLines: 40)
                // A line is kept back for the ellipsis unless this is the last block.
                let available = index == blocks.count - 1 ? room : room - 20
                let fits = Int((available - y) / leading)
                if fits < 1 { needsEllipsis = true; break }
                // What doesn't fit is cut at a line, with an ellipsis, and nothing follows it.
                let taken = wanted.count <= fits ? wanted : ShelfPDF.lines(text, width: textWidth - indent, maxLines: fits)
                let isBullet: Bool = if case .bullet = block { true } else { false }
                laid.append(Laid(lines: taken, top: y, leading: leading, indent: indent, bullet: isBullet))
                bottom = y + CGFloat(taken.count) * leading
                y = bottom + gap
                if wanted.count > fits { break }
            }
            if needsEllipsis {
                let dots = CTLineCreateWithAttributedString(ShelfPDF.attributed("\u{2026}", ShelfPDF.font(13.5), ShelfPDF.muted))
                laid.append(Laid(lines: [dots], top: bottom + 4, leading: 20, indent: 0, bullet: false))
                bottom += 24
            }
            let paper = CGRect(x: box.midX - width / 2, y: box.minY, width: width, height: min(box.height, max(bottom + inset, 120)))
            context.saveGState()
            let path = CGPath(roundedRect: pdf(paper), cornerWidth: 10, cornerHeight: 10, transform: nil)
            context.addPath(path)
            context.setFillColor(ShelfPDF.paper)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(ShelfPDF.hairline)
            context.setLineWidth(0.75)
            context.strokePath()
            context.restoreGState()
            for item in laid {
                if item.bullet {
                    let dot = ShelfPDF.attributed("\u{2022}", ShelfPDF.font(13.5), ShelfPDF.muted)
                    drawLine(CTLineCreateWithAttributedString(dot),
                             in: CGRect(x: paper.minX + inset, y: paper.minY + item.top, width: 14, height: item.leading), leading: item.leading)
                }
                for (row, line) in item.lines.enumerated() {
                    let lineBox = CGRect(x: paper.minX + inset + item.indent, y: paper.minY + item.top + CGFloat(row) * item.leading,
                                         width: textWidth - item.indent, height: item.leading)
                    drawLine(line, in: lineBox, leading: item.leading)
                }
            }
        }

        // MARK: A tile

        /// The file's extension in large light letters over its kind and size, on a quiet ivory tile.
        private func drawTile(in box: CGRect) {
            let size = CGSize(width: min(box.width, 520), height: min(box.height, 250))
            let tile = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
            context.saveGState()
            let path = CGPath(roundedRect: pdf(tile), cornerWidth: 12, cornerHeight: 12, transform: nil)
            context.addPath(path)
            context.setFillColor(ShelfPDF.paper)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(ShelfPDF.hairline)
            context.setLineWidth(0.75)
            context.strokePath()
            context.restoreGState()
            let label = CTLineCreateWithAttributedString(ShelfPDF.attributed(page.tile.label, ShelfPDF.font(56, .light), ShelfPDF.muted))
            let detail = CTLineCreateWithAttributedString(ShelfPDF.attributed(page.tile.detail, ShelfPDF.font(14), ShelfPDF.muted))
            let labelBox = CGRect(x: tile.minX, y: tile.midY - 52, width: tile.width, height: 64)
            let detailBox = CGRect(x: tile.minX, y: tile.midY + 18, width: tile.width, height: 22)
            drawCentred(label, in: labelBox)
            drawCentred(detail, in: detailBox)
        }

        private func drawCentred(_ line: CTLine, in box: CGRect) {
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            drawLine(line, in: CGRect(x: box.midX - width / 2, y: box.minY, width: width, height: box.height), leading: box.height)
        }
    }
}
