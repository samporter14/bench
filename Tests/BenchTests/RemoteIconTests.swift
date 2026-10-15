// RemoteIconTests.swift — the Home Screen icons: opaque, full-bleed squares.
// iOS flattens a touch icon's alpha onto black, so any transparency is a bug.
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Bench

struct RemoteIconTests {
    private func decode(_ png: Data) -> CGImage? {
        CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// The pixel at (x, y), as 8-bit sRGB red, green, blue, alpha.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return bytes
    }

    @Test func theGlyphIsEmbedded() throws {
        let glyph = try #require(decode(RemoteWebApp.iconGlyph))
        #expect(glyph.width == 1024 && glyph.height == 1024)
    }

    @Test(arguments: [180, 512])
    func anIconIsAnOpaqueSquare(size: Int) throws {
        let png = try #require(RemoteIcon.png(size: size, glyph: RemoteWebApp.iconGlyph))
        let image = try #require(decode(png))
        #expect(image.width == size && image.height == size)
        // No alpha channel in the file itself: PNG colour type 2 (RGB), not 6 (RGBA).
        #expect(png[25] == 2)
        #expect([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
        // Full-bleed: all four corners are the Clay fill, fully opaque.
        for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)] {
            #expect(pixel(image, x, y) == [217, 119, 87, 255])
        }
    }

    @Test func aBrokenGlyphMakesNoIcon() {
        #expect(RemoteIcon.png(size: 180, glyph: Data("not a png".utf8)) == nil)
        #expect(RemoteIcon.png(size: 0, glyph: RemoteWebApp.iconGlyph) == nil)
    }
}
