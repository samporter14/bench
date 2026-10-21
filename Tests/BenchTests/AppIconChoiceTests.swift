// AppIconChoiceTests.swift — the six icons Settings → General → App icon
// offers (AppIconChoice): each is an Icon Composer document that exists, with
// the right tile and layers; the layers cut from Capsid's glyph add back to it
// pixel for pixel; the setting defaults to Clay; and choosing an icon sets or
// clears the Dock image through an injected setter, never the real NSApp.
// Nothing here needs a built app: the compiled .icns are Scripts/build-app.sh's.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Bench

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let variants = root.appendingPathComponent("Resources/AppIconVariants")
private let glyphURL = root.appendingPathComponent("Resources/AppIcon.icon/Assets/bench-glyph.png")
private let side = 1024

/// A PNG as premultiplied RGBA8 bytes, read one way for every file so two of
/// them compare byte for byte: no colour conversion, no NSImage in between.
private enum Pixels {
    static func read(_ url: URL) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(url.lastPathComponent)")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == side && image.height == side, "\(url.path)")
        return composite([image])
    }

    /// The images drawn over each other, first at the bottom (source-over).
    static func composite(_ images: [CGImage]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                    bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            for image in images { context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side)) }
        }
        return bytes
    }

    static func image(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func alpha(_ bytes: [UInt8], _ pixel: Int) -> UInt8 { bytes[pixel * 4 + 3] }
}

private let layerNames = ["ring", "capsid", "escapee"]

private func layerURL(_ choice: AppIconChoice, _ name: String) -> URL {
    variants.appendingPathComponent("\(choice.document)/Assets/\(name).png")
}

/// The icon.json as a dictionary.
private func icon(_ choice: AppIconChoice) throws -> [String: Any] {
    let data = try Data(contentsOf: variants.appendingPathComponent("\(choice.document)/icon.json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

struct AppIconChoiceTests {
    // MARK: The choices

    @Test func theSixAreTheOnesSettingsOffersInOrder() {
        #expect(AppIconChoice.allCases.map(\.rawValue) == ["clay", "ivory", "slate", "ivoryMono", "slateMono", "ivoryClay"])
        #expect(AppIconChoice.allCases.map(\.title) == [
            "Clay", "Ivory", "Slate", "Ivory, one color", "Slate, one color", "Ivory and Clay",
        ])
        #expect(AppIconChoice.standard == .clay)
    }

    @Test func userFacingNamesUseAmericanSpelling() {
        for choice in AppIconChoice.allCases { #expect(!choice.title.contains("colour"), "\(choice.title)") }
    }

    // MARK: The documents

    @Test func everyChoiceHasADocumentAndNoDocumentHasNoChoice() throws {
        let documents = try FileManager.default.contentsOfDirectory(atPath: variants.path).filter { $0.hasSuffix(".icon") }
        #expect(Set(documents) == Set(AppIconChoice.allCases.map(\.document)))
    }

    @Test(arguments: AppIconChoice.allCases)
    func theDocumentHasItsTileAndItsLayerFiles(choice: AppIconChoice) throws {
        let json = try icon(choice)
        // The tile is a solid sRGB fill, in the ground the choice names.
        let fill = try #require(json["fill"] as? [String: String])
        let tile = choice.tile
        #expect(fill["solid"] == String(format: "srgb:%.5f,%.5f,%.5f,1.00000", tile.red / 255, tile.green / 255, tile.blue / 255))
        // One group of three layers, each with a file.
        let groups = try #require(json["groups"] as? [[String: Any]])
        #expect(groups.count == 1)
        let layers = try #require(groups.first?["layers"] as? [[String: Any]])
        #expect(layers.compactMap { $0["image-name"] as? String } == layerNames.map { "\($0).png" })
        for layer in layers {
            #expect(layer["hidden"] as? Bool == false)
            let file = try #require(layer["image-name"] as? String)
            #expect(FileManager.default.fileExists(atPath: variants.appendingPathComponent("\(choice.document)/Assets/\(file)").path), "\(file)")
        }
        #expect((json["supported-platforms"] as? [String: Any])?["squares"] as? String == "shared")
    }

    /// The tile's ground is one of Solanum's three, the Clay one is Capsid's own icon's, and
    /// the fallback tile colours in the picker are the documents' (they are the same numbers).
    @Test func theClayDocumentKeepsTheTileOfCapsidsOwnIcon() throws {
        let own = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.icon/icon.json"))) as? [String: Any]
        let ownFill = (own?["fill"] as? [String: String])?["solid"]
        #expect(ownFill == "srgb:0.85098,0.46667,0.34118,1.00000")
        #expect((try icon(.clay)["fill"] as? [String: String])?["solid"] == ownFill)
    }

    // MARK: The split

    /// Today's icon is the glyph unchanged (Slate on Clay), so its three layers drawn over
    /// each other are bench-glyph.png, and so are the one-colour Ivory icon's (Slate too).
    @Test(arguments: [AppIconChoice.clay, .ivoryMono])
    func theLayersCompositeBackToTheGlyphPixelForPixel(choice: AppIconChoice) throws {
        let glyph = try Pixels.read(glyphURL)
        let stacked = Pixels.composite(try layerNames.map { try Pixels.image(layerURL(choice, $0)) })
        #expect(stacked == glyph)
    }

    /// Every icon keeps the glyph's alpha, so its antialiasing is the glyph's: the three layers'
    /// ink never overlaps, and together it is exactly the glyph's ink.
    @Test(arguments: AppIconChoice.allCases)
    func everyIconKeepsTheGlyphsAlphaWithNoOverlap(choice: AppIconChoice) throws {
        let glyph = try Pixels.read(glyphURL)
        let layers = try layerNames.map { try Pixels.read(layerURL(choice, $0)) }
        var overlapping = 0, different = 0
        for pixel in 0..<(side * side) {
            let inked = layers.filter { Pixels.alpha($0, pixel) > 0 }
            if inked.count > 1 { overlapping += 1 }
            if (inked.first.map { Pixels.alpha($0, pixel) } ?? 0) != Pixels.alpha(glyph, pixel) { different += 1 }
        }
        #expect(overlapping == 0)
        #expect(different == 0)
    }

    /// The cut is by geometry: the capsid inside the ring, the ring an annulus, the escaped dot
    /// outside it at the upper right.
    @Test(arguments: AppIconChoice.allCases)
    func eachLayerHoldsItsOwnPartOfTheGlyph(choice: AppIconChoice) throws {
        let bands: [(name: String, inner: Double, outer: Double)] = [
            ("capsid", 0, 230), ("ring", 230, 310), ("escapee", 310, .infinity),
        ]
        for band in bands {
            let bytes = try Pixels.read(layerURL(choice, band.name))
            var count = 0, outside = 0
            var upperRight = true
            for pixel in 0..<(side * side) where Pixels.alpha(bytes, pixel) > 0 {
                let (x, y) = (Double(pixel % side), Double(pixel / side))
                let radius = hypot(x - 511.5, y - 511.5)
                if !(radius >= band.inner && radius < band.outer) { outside += 1 }
                if !(x > 512 && y < 512) { upperRight = false }
                count += 1
            }
            #expect(outside == 0, "\(choice) \(band.name) has ink outside its band")
            #expect(count > 1_000, "\(choice) \(band.name) has ink")
            if band.name == "escapee" { #expect(upperRight, "the escaped dot is at the upper right") }
        }
    }

    // MARK: The colours

    /// The brand's rule, from the table: structure (ring, capsid) takes ink, the organism (the
    /// escaped dot) takes Clay, one-colour versions set everything to ink; no other colour.
    private enum Ink { case slate, ivory, clay }

    private static let colours: [AppIconChoice: (ring: Ink, capsid: Ink, escapee: Ink)] = [
        .clay: (.slate, .slate, .slate),
        .ivory: (.slate, .slate, .clay),
        .slate: (.ivory, .clay, .clay),
        .ivoryMono: (.slate, .slate, .slate),
        .slateMono: (.ivory, .ivory, .ivory),
        .ivoryClay: (.slate, .clay, .clay),
    ]

    @Test(arguments: AppIconChoice.allCases)
    func eachLayerIsItsOwnColour(choice: AppIconChoice) throws {
        let expected = try #require(Self.colours[choice])
        for (name, ink) in [("ring", expected.ring), ("capsid", expected.capsid), ("escapee", expected.escapee)] {
            let bytes = try Pixels.read(layerURL(choice, name))
            var opaque = 0, wrong: [String] = []
            for pixel in 0..<(side * side) where Pixels.alpha(bytes, pixel) == 255 {
                let rgb = (Int(bytes[pixel * 4]), Int(bytes[pixel * 4 + 1]), Int(bytes[pixel * 4 + 2]))
                let ok: Bool
                switch ink {
                // The glyph's own Slate varies a little (20 to 22) where its antialiasing was drawn.
                case .slate: ok = abs(rgb.0 - 20) <= 3 && abs(rgb.1 - 20) <= 3 && abs(rgb.2 - 19) <= 3
                case .ivory: ok = rgb == (250, 249, 245)
                case .clay: ok = rgb == (217, 119, 87)
                }
                if !ok { wrong.append("\(rgb)") }
                opaque += 1
            }
            #expect(wrong.isEmpty, "\(choice) \(name): \(wrong.prefix(3)) of \(wrong.count)")
            #expect(opaque > 100, "\(choice) \(name) has solid ink")
        }
    }

    @Test func theTileAndTheInkOfAChoiceAreNeverTheSameGround() {
        // A Clay tile carries Slate ink only; an Ivory tile never Ivory ink; a Slate tile never Slate ink.
        for (choice, ink) in Self.colours {
            let tile = choice.tile
            for part in [ink.ring, ink.capsid, ink.escapee] {
                switch (tile.red, part) {
                case (217, .clay), (250, .ivory), (20, .slate): Issue.record("\(choice): ink the colour of its tile")
                default: break
                }
            }
        }
    }

    // MARK: The setting

    private func suite(_ body: (UserDefaults) throws -> Void) throws {
        let name = "AppIconChoiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// Read from the registered defaults rather than the stored ones, so a value set on this
    /// Mac can't change the answer.
    @Test func theSettingDefaultsToClay() {
        SettingsKey.register()
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        #expect(registered[SettingsKey.appIcon] as? String == "clay")
        #expect(SettingsKey.appIcon == "appIcon")
    }

    @Test func nothingStoredOrAnUnknownNameIsClay() throws {
        try suite { defaults in
            #expect(AppIconChoice.stored(in: defaults) == .clay)
            defaults.set("ivoryClay", forKey: SettingsKey.appIcon)
            #expect(AppIconChoice.stored(in: defaults) == .ivoryClay)
            defaults.set("mauve", forKey: SettingsKey.appIcon)
            #expect(AppIconChoice.stored(in: defaults) == .clay)
        }
    }

    // MARK: Choosing

    @MainActor
    @Test func chosenIconBecomesTheDockImageAndClayClearsIt() throws {
        try suite { defaults in
            let pictures = Dictionary(uniqueKeysWithValues: AppIconChoice.allCases.map { ($0, NSImage(size: NSSize(width: 8, height: 8))) })
            let dock = AppIconDock()
            var loaded: [AppIconChoice] = []
            var handed: [NSImage?] = []
            @MainActor func apply() {
                dock.apply(from: defaults, load: { loaded.append($0); return pictures[$0] }, set: { handed.append($0) })
            }

            // At launch with nothing chosen the Dock is left alone: no file read, nothing set.
            apply()
            #expect(handed.isEmpty && loaded.isEmpty && !dock.showsChosen)

            defaults.set(AppIconChoice.slateMono.rawValue, forKey: SettingsKey.appIcon)
            apply()
            #expect(handed.count == 1 && handed[0] === pictures[.slateMono] && dock.showsChosen)

            defaults.set(AppIconChoice.ivory.rawValue, forKey: SettingsKey.appIcon)
            apply()
            #expect(handed.count == 2 && handed[1] === pictures[.ivory])

            // Back to Clay: the Dock image is cleared (nil restores the bundle's icon), once.
            defaults.set(AppIconChoice.clay.rawValue, forKey: SettingsKey.appIcon)
            apply()
            #expect(handed.count == 3 && handed[2] == nil && !dock.showsChosen)
            apply()
            #expect(handed.count == 3)
            #expect(loaded == [.slateMono, .ivory])
        }
    }

    /// A launch with a choice stored hands the Dock that picture straight away.
    @MainActor
    @Test func aStoredChoiceIsAppliedAtLaunch() throws {
        try suite { defaults in
            defaults.set(AppIconChoice.slate.rawValue, forKey: SettingsKey.appIcon)
            let picture = NSImage(size: NSSize(width: 8, height: 8))
            var handed: [NSImage?] = []
            AppIconDock().apply(from: defaults, load: { $0 == .slate ? picture : nil }, set: { handed.append($0) })
            #expect(handed.count == 1 && handed[0] === picture)
        }
    }

    /// A picture that didn't compile or isn't there, or a choice from a later Capsid, never
    /// leaves a blank Dock tile: the bundle's icon comes back, and until something was set
    /// there is nothing to take back.
    @MainActor
    @Test func aMissingPictureOrUnknownChoiceRestoresTheBundlesIcon() throws {
        try suite { defaults in
            let picture = NSImage(size: NSSize(width: 8, height: 8))
            let dock = AppIconDock()
            var handed: [NSImage?] = []
            defaults.set(AppIconChoice.ivory.rawValue, forKey: SettingsKey.appIcon)
            dock.apply(from: defaults, load: { _ in nil }, set: { handed.append($0) })
            #expect(handed.isEmpty, "nothing was set, so nothing is cleared")

            dock.apply(from: defaults, load: { _ in picture }, set: { handed.append($0) })
            defaults.set(AppIconChoice.slate.rawValue, forKey: SettingsKey.appIcon)
            dock.apply(from: defaults, load: { _ in nil }, set: { handed.append($0) })
            #expect(handed.count == 2 && handed[0] === picture && handed[1] == nil, "the picture went missing")

            dock.apply(from: defaults, load: { _ in picture }, set: { handed.append($0) })
            defaults.set("mauve", forKey: SettingsKey.appIcon)
            dock.apply(from: defaults, load: { _ in picture }, set: { handed.append($0) })
            #expect(handed.count == 4 && handed[3] == nil, "a name nobody knows")
        }
    }

    // MARK: What the code may and may not do

    /// The Dock image is set in one place, and nothing writes an icon to the bundle or a file.
    @Test func onlyAppIconChoiceSetsTheAppIconAndNothingSetsAFileIcon() throws {
        let base = root.appendingPathComponent("Sources/Bench")
        let walker = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        var setters: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(base.path.count + 1))
            if relative.hasPrefix("Shared/") { continue }
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("//") { continue }
                if text.contains("applicationIconImage =") || text.contains("applicationIconImage=") { setters.append(relative) }
                #expect(!text.contains("setIcon("), "\(relative): \(text)")
            }
        }
        #expect(setters == ["App/AppIconChoice.swift"])
    }

    /// Scripts/build-app.sh compiles whatever is in Resources/AppIconVariants, so a document
    /// added there (and to the enum) reaches the app without editing the script.
    @Test func theBuildScriptCompilesEveryDocumentInTheVariantsFolder() throws {
        let script = try String(contentsOf: root.appendingPathComponent("Scripts/build-app.sh"), encoding: .utf8)
        #expect(script.contains("Resources/AppIconVariants"))
        #expect(script.contains("AppIcons"))
        #expect(script.contains("--app-icon \"$ID\""))
    }

    @Test func settingsHasTheRowWithItsPlainLineAndItsInfo() throws {
        let pages = try String(contentsOf: root.appendingPathComponent("Sources/Bench/App/SettingsPages.swift"), encoding: .utf8)
        #expect(pages.contains("InfoTitle(\"App icon\", info: AppIconInfo.dockOnly)"))
        #expect(pages.contains("Text(\"Changes Capsid's icon in the Dock while it's open.\")"))
        #expect(AppIconInfo.dockOnly.contains("Finder"))
        #expect(AppIconInfo.dockOnly.contains("Launchpad"))
    }
}
