// CompareImages.swift — the figures Compare shows (DESIGN.md, Compare), decoded
// off the main actor from bytes the disk layer read (`KeptDisk.pictureBytes`:
// a file under the Kept folder, on this Mac and not put away by iCloud, at most
// 8 MB, the most a keep copies, so nothing on the Shelf is larger). A raster
// picture's header is read before any pixel, as the Results shelf's thumbnails
// do (`ShelfThumbnails.decode`): not a picture ImageIO reads, or more than 64
// megapixels, is refused unread. It is then decoded upright (its EXIF
// orientation applied) and never larger than 3,072 pixels on its long side, so
// the two sides together hold at most about 75 MB (3,072 × 3,072 × 4 bytes
// each). A larger picture is shown at that size, and its own pixel size is still
// the one Compare states and the one Wipe compares. A PDF (its first page) or an
// SVG is a figure too: told apart by its first bytes, drawn on white with its long
// side at 3,072 pixels, as Export as PDF… draws it (`ShelfVectorDrawing`), and its
// size is stated in points, the page's or the SVG's own.
import CoreGraphics
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// One side's picture: what is drawn, and the upright size of the file's own pixels.
struct CompareImage: Equatable, @unchecked Sendable {
    /// Decoded upright, at most `CompareImages.sideLimit` on its long side.
    let image: CGImage
    /// The file's own size, upright: pixels for a picture (its orientation applied), points for a PDF's page or an
    /// SVG. What the side says, and what Wipe needs to match.
    let source: CGSize
    /// What `source` counts: a raster picture's pixels, or a vector figure's points.
    var unit: Unit = .pixels
    /// A PDF's pages (the first is shown); nil for anything else.
    var pages: Int?

    enum Unit: Equatable, Sendable {
        case pixels
        case points
    }

    /// The decoded picture's size: `source` for a raster picture unless that was over the long-side limit; for a
    /// vector figure, what it was drawn at.
    var shown: CGSize { CGSize(width: image.width, height: image.height) }

    static func == (a: CompareImage, b: CompareImage) -> Bool {
        a.image === b.image && a.source == b.source && a.unit == b.unit && a.pages == b.pages
    }
}

/// Why a file's bytes gave no picture.
enum CompareImageRefusal: Error, Equatable, Sendable {
    /// Not a picture ImageIO reads, or one whose header has no size; a PDF that is locked, has no pages or no size; an
    /// SVG AppKit can't draw, or one with no size.
    case notAnImage
    /// Its header declares more pixels than Compare decodes (the upright size).
    case tooManyPixels(CGSize)
}

enum CompareImages {
    /// The most a picture's long side is decoded at.
    static let sideLimit = 3_072
    /// More pixels than this in the header is refused before decoding: the 64 megapixels Claude Science itself takes.
    static let pixelLimit = 64_000_000
    /// The most bytes of a picture read: the 8 MB a keep copies (`KeptDisk.pictureBytes`' own limit).
    static let byteLimit = 8 << 20

    /// The picture in `data`, upright and at most `side` pixels long, or why not. Safe off the main actor.
    nonisolated static func decode(_ data: Data, side: Int = sideLimit, maxPixels: Int = pixelLimit) -> Result<CompareImage, CompareImageRefusal> {
        switch vector(data) {
        case .pdf: return decodePDF(data, side: side)
        case .svg: return decodeSVG(data, side: side)
        case nil: break
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let identifier = CGImageSourceGetType(source) as String?,
              UTType(identifier)?.conforms(to: .image) == true,
              CGImageSourceGetCount(source) >= 1 else { return .failure(.notAnImage) }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return .failure(.notAnImage) }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let upright = uprightSize(width: width, height: height, orientation: orientation)
        guard width <= maxPixels, height <= maxPixels, width * height <= maxPixels else { return .failure(.tooManyPixels(upright)) }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(side, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return .failure(.notAnImage) }
        return .success(CompareImage(image: image, source: upright))
    }

    // MARK: Vector figures

    enum Vector: Equatable, Sendable {
        case pdf
        case svg
    }

    /// A PDF or an SVG, told by its first bytes (never by its name): "%PDF-" within the first kilobyte, as PDF readers
    /// allow; or text that starts with "<" and has "<svg" in its first 4 KB. Nil for anything else.
    nonisolated static func vector(_ data: Data) -> Vector? {
        if data.prefix(1_024).range(of: Data("%PDF-".utf8)) != nil { return .pdf }
        let start = String(decoding: data.prefix(4_096), as: UTF8.self)
        let trimmed = start.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard trimmed.first == "<", trimmed.contains("<svg") else { return nil }
        return .svg
    }

    /// A PDF's first page, its long side at `side` pixels, on white. Refused: locked, no pages, or a page with no size.
    nonisolated static func decodePDF(_ data: Data, side: Int = sideLimit) -> Result<CompareImage, CompareImageRefusal> {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              document.isUnlocked, document.numberOfPages > 0, let first = document.page(at: 1) else { return .failure(.notAnImage) }
        let size = ShelfVectorDrawing.uprightSize(of: first)
        guard let image = render(size, side: side, draw: { ShelfVectorDrawing.draw(first, in: $1, context: $0) }) else {
            return .failure(.notAnImage)
        }
        return .success(CompareImage(image: image, source: size, unit: .points, pages: document.numberOfPages))
    }

    /// An SVG drawn as AppKit draws it (macOS reads SVG since 14), its long side at `side` pixels, on white. Refused:
    /// one AppKit can't read, or one with no size.
    nonisolated static func decodeSVG(_ data: Data, side: Int = sideLimit) -> Result<CompareImage, CompareImageRefusal> {
        guard let svg = NSImage(data: data) else { return .failure(.notAnImage) }
        let size = svg.size
        guard let image = render(size, side: side, draw: { context, target in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(target)
            ShelfVectorDrawing.draw(svg, in: target, context: context)
        }) else { return .failure(.notAnImage) }
        return .success(CompareImage(image: image, source: size, unit: .points))
    }

    /// A picture of a figure `size` points large, its long side `side` pixels, made by `draw` into the whole of it.
    /// Nil for a size that isn't a size.
    nonisolated static func render(_ size: CGSize, side: Int, draw: (CGContext, CGRect) -> Void) -> CGImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, side > 0 else { return nil }
        let scale = CGFloat(side) / max(size.width, size.height)
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        draw(context, CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The size a picture is seen at: EXIF orientations 5 to 8 turn it a quarter, so its width and height trade places.
    static func uprightSize(width: Int, height: Int, orientation: Int) -> CGSize {
        (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
