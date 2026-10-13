// RemoteIcon.swift — the phone app's Home Screen icon.
//
// iOS flattens an apple-touch-icon that has an alpha channel onto black, so
// the Mac's squircle (transparent corners, drop shadow) looks broken there.
// This draws what iOS wants instead: an opaque, full-bleed square in the app
// icon's Fig fill with the bench glyph over all of it. iOS applies its own
// mask. The glyph's bytes come from `RemoteWebApp.iconGlyph`, because the raw
// asset is not in the app bundle.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RemoteIcon {
    /// The app icon's fill (Resources/AppIcon.icon/icon.json: srgb 0.76863, 0.40000, 0.52549).
    static let fig = (red: 196.0 / 255, green: 102.0 / 255, blue: 134.0 / 255)

    /// A `size` x `size` PNG with no alpha channel, or nil if the glyph can't be read.
    static func png(size: Int, glyph: Data) -> Data? {
        guard size > 0,
              let source = CGImageSourceCreateWithData(glyph as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let fill = CGColor(colorSpace: space, components: [fig.red, fig.green, fig.blue, 1]),
              // noneSkipLast: four bytes a pixel, the fourth ignored, so nothing is transparent.
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let square = CGRect(x: 0, y: 0, width: size, height: size)
        context.setFillColor(fill)
        context.fill(square)
        context.interpolationQuality = .high
        context.draw(image, in: square)
        guard let flat = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, flat, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
