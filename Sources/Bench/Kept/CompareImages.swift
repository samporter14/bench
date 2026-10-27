// CompareImages.swift — the pictures Compare shows (DESIGN.md, Compare), decoded
// off the main actor from bytes the disk layer read (`KeptDisk.pictureBytes`:
// a file under the Kept folder, on this Mac and not put away by iCloud, at most
// 8 MB, the most a keep copies). The header is read before any pixel, as the
// Results shelf's thumbnails do (`ShelfThumbnails.decode`): not a picture ImageIO
// reads, or more than 64 megapixels, is refused unread. The picture is then
// decoded upright (its EXIF orientation applied) and never larger than 3,072
// pixels on its long side, so the two sides together hold at most about 75 MB
// (3,072 × 3,072 × 4 bytes each). A larger picture is shown at that size, and its
// own pixel size is still the one Compare states and the one Wipe compares.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One side's picture: what is drawn, and the upright size of the file's own pixels.
struct CompareImage: Equatable, @unchecked Sendable {
    /// Decoded upright, at most `CompareImages.sideLimit` on its long side.
    let image: CGImage
    /// The file's pixel size with its orientation applied: what the side says, and what Wipe needs to match.
    let source: CGSize

    /// The decoded picture's size, which is `source` unless that was over the long-side limit.
    var shown: CGSize { CGSize(width: image.width, height: image.height) }

    static func == (a: CompareImage, b: CompareImage) -> Bool { a.image === b.image && a.source == b.source }
}

/// Why a file's bytes gave no picture.
enum CompareImageRefusal: Error, Equatable, Sendable {
    /// Not a picture ImageIO reads, or one whose header has no size.
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

    /// The size a picture is seen at: EXIF orientations 5 to 8 turn it a quarter, so its width and height trade places.
    static func uprightSize(width: Int, height: Int, orientation: Int) -> CGSize {
        (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
