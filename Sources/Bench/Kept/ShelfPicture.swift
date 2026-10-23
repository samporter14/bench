// ShelfPicture.swift — the picture Copy puts on the pasteboard beside a figure's
// file (DESIGN.md, Shelf). The bytes are read by `KeptDisk` on its queue and
// made ready here on a thread of their own, so nothing about a figure, which may
// sit on a share that answers slowly, is read or decoded on the main actor. A
// PNG goes on as it is; an SVG as SVG; any other picture ImageIO can read (JPEG,
// TIFF, GIF, WebP, HEIC…) as a PNG, which is what web pages and every editor
// take. A file that isn't a picture after all gets none, and the file itself,
// already on the pasteboard, is all that was asked for.
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ShelfPicture {
    /// One picture on the pasteboard: the type it is declared as, and its bytes.
    struct Flavor: Equatable, Sendable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    static let svgType = NSPasteboard.PasteboardType(UTType.svg.identifier)

    /// What a figure file's bytes become on the pasteboard; nil for a file that is not a picture.
    static func flavor(of data: Data, fileName: String) async -> Flavor? {
        await Task.detached(priority: .userInitiated) { convert(data, fileName: fileName) }.value
    }

    nonisolated static func convert(_ data: Data, fileName: String) -> Flavor? {
        if (fileName as NSString).pathExtension.lowercased() == "svg" {
            // Text, so a look at its start tells an SVG from anything else.
            guard let start = String(data: data.prefix(2_000), encoding: .utf8), start.contains("<svg") else { return nil }
            return Flavor(type: svgType, data: data)
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return Flavor(type: .png, data: data)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let image = upright(source) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Flavor(type: .png, data: out as Data)
    }

    /// The first frame, turned upright when the file says it is on its side.
    nonisolated private static func upright(_ source: CGImageSource) -> CGImage? {
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
}
