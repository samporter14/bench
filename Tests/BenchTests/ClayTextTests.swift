// ClayTextTests.swift — clay for words (Theme.clayText): the darker clay on
// light grounds and the lighter one on dark, readable on both; and a guard that
// nothing draws words in the clay fill again.
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Bench

// SwiftUI resolves colours on the main actor; off it, `Color.resolve` waits for
// a main thread that is waiting for the test.
@MainActor
struct ClayTextTests {
    private typealias RGB = (red: Double, green: Double, blue: Double)

    private func rgb(_ color: NSColor, in name: NSAppearance.Name) -> RGB {
        var result: RGB = (0, 0, 0)
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let resolved = color.usingColorSpace(.sRGB)!
            result = (Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent))
        }
        return result
    }

    private func hex(_ value: RGB) -> String {
        String(format: "#%02X%02X%02X", Int((value.red * 255).rounded()), Int((value.green * 255).rounded()), Int((value.blue * 255).rounded()))
    }

    /// WCAG relative luminance of an sRGB colour.
    private func luminance(_ c: RGB) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    private func colour(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    @Test func clayTextIsSolanumsDarkClayInLightAndTheLightOneInDark() {
        #expect(hex(rgb(Theme.clayTextColor, in: .aqua)) == "#9C4221")
        #expect(hex(rgb(Theme.clayTextColor, in: .darkAqua)) == "#E4927A")
        // Vibrant appearances (a popover's) follow their light or dark base.
        #expect(hex(rgb(Theme.clayTextColor, in: .vibrantLight)) == "#9C4221")
        #expect(hex(rgb(Theme.clayTextColor, in: .vibrantDark)) == "#E4927A")
    }

    @Test func theColourSwiftUIDrawsFollowsTheEnvironmentsScheme() {
        func drawn(_ scheme: ColorScheme) -> RGB {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let resolved = Theme.clayText.resolve(in: environment)
            return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
        }
        #expect(hex(drawn(.light)) == "#9C4221")
        #expect(hex(drawn(.dark)) == "#E4927A")
    }

    @Test func clayTextReadsOnItsGroundsWhereTheFillDoesNot() {
        let ivory = colour(0xFAF9F5), softIvory = colour(0xF0EEE6), slate = colour(0x141413)
        let fill = colour(0xD97757)
        // 4.5:1 is what small text needs.
        #expect(contrast(rgb(Theme.clayTextColor, in: .aqua), ivory) >= 4.5)
        #expect(contrast(rgb(Theme.clayTextColor, in: .aqua), softIvory) >= 4.5)
        #expect(contrast(rgb(Theme.clayTextColor, in: .darkAqua), slate) >= 4.5)
        // The fill, the reason for it: about 3:1 on ivory.
        #expect(contrast(fill, ivory) < 4)
        #expect(contrast(fill, softIvory) < 4)
    }

    /// Every line in Capsid's own code that colours something with the clay
    /// fill through `foregroundStyle` or a `style:` argument. Each is a glyph
    /// or a mark, not words; words use `clayText`. A new line here means
    /// deciding which it is.
    private static let marks: [String: Int] = [
        // A warning triangle beside "Specimens" and one beside a problem's sentence (the words are primary).
        "Lab/ScenesToolbarButton.swift: .foregroundStyle(Theme.clay)": 2,
        // The choice marks (radio and checkbox glyphs) and the reply window's heading icon.
        "Lab/ReplyWindow.swift: .foregroundStyle(on ? Theme.clay : .secondary)": 1,
        "Lab/ReplyWindow.swift: .foregroundStyle(Theme.clay)": 1,
        // A favourite's star.
        "Lab/SceneSettingsView.swift: .foregroundStyle(isFavorite ? AnyShapeStyle(Theme.clay) : AnyShapeStyle(.secondary))": 1,
        // The warning or check glyph beside a keep's result line, and beside a legend that couldn't be saved (the Shelf window's, since it moved from the Kept window) (the words are primary).
        "Kept/KeepSheet.swift: Image(systemName: symbol).foregroundStyle(Theme.clay).accessibilityHidden(true)": 1,
        "Kept/ShelfView.swift: Image(systemName: \"exclamationmark.triangle\").foregroundStyle(Theme.clay).accessibilityHidden(true)": 1,
    ]

    @Test func noWordsAreDrawnInTheClayFill() throws {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench")
        let walker = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        var found: [String: Int] = [:]
        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(base.path.count + 1))
            // Shared/ draws the specimens in their own inks; Theme.swift defines the colours.
            if relative.hasPrefix("Shared/") || relative == "App/Theme.swift" { continue }
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                guard text.contains("Theme.clay"), !text.contains("Theme.clayText"), !text.hasPrefix("//"),
                      text.contains("foregroundStyle(") || text.contains("style: Theme.clay") else { continue }
                found["\(relative): \(text)", default: 0] += 1
            }
        }
        #expect(found == Self.marks)
    }
}
