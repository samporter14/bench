// AppIconChoice.swift — the six icons Settings → General → App icon offers
// (DESIGN.md, App icon, since 0.9.5), and what choosing one does: it becomes
// Capsid's Dock icon while Capsid runs, and the icon Capsid draws in its own
// windows.
//
// macOS gives an app no way to change the icon Finder and Launchpad show without
// writing to its bundle, which would break the signature (and with it the
// permissions the user granted) and be undone by every update. So the choice is
// `NSApp.applicationIconImage`, which lasts as long as the process, and nothing
// here touches the bundle or calls `NSWorkspace.setIcon`.
import AppKit
import SwiftUI

/// One of the icons. Each is an Icon Composer document in
/// Resources/AppIconVariants/<id>.icon (Scripts/make-icon-variants.py cuts them
/// from Capsid's own glyph), which Scripts/build-app.sh compiles into
/// Contents/Resources/AppIcons/<id>.icns.
enum AppIconChoice: String, CaseIterable, Identifiable {
    /// Today's icon: a Clay tile, everything in Slate. Also the bundle's own.
    case clay
    /// An Ivory tile; the ring and the capsid in Slate, the escaped dot in Clay.
    case ivory
    /// A Slate tile; the ring in Ivory, the capsid and the dot in Clay.
    case slate
    case ivoryMono
    case slateMono
    /// An Ivory tile with a Slate ring, the capsid and the dot in Clay.
    case ivoryClay

    var id: String { rawValue }

    /// What a new Mac, and anyone who never chooses, gets.
    static let standard = AppIconChoice.clay

    /// The name in Settings and for VoiceOver.
    var title: String {
        switch self {
        case .clay: "Clay"
        case .ivory: "Ivory"
        case .slate: "Slate"
        case .ivoryMono: "Ivory, one color"
        case .slateMono: "Slate, one color"
        case .ivoryClay: "Ivory and Clay"
        }
    }

    /// The tile's ground: one of Solanum's three, as sRGB 0...255.
    var tile: (red: Double, green: Double, blue: Double) {
        switch self {
        case .clay: (217, 119, 87)
        case .ivory, .ivoryMono, .ivoryClay: (250, 249, 245)
        case .slate, .slateMono: (20, 20, 19)
        }
    }

    /// The Icon Composer document, relative to Resources/AppIconVariants.
    var document: String { "\(rawValue).icon" }

    /// The compiled picture, or nil when the app wasn't built by
    /// Scripts/build-app.sh (`swift run`, the tests) or the icon didn't compile.
    func image(in bundle: Bundle = .main) -> NSImage? {
        guard let url = bundle.url(forResource: rawValue, withExtension: "icns", subdirectory: "AppIcons") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// `image()` for the app's own bundle, read once: the pictures can't change
    /// while Capsid runs, and Settings asks for six of them each time it draws.
    @MainActor
    var picture: NSImage? {
        if let known = Self.pictures[self] { return known }
        guard !Self.absent.contains(self) else { return nil }
        guard let image = image() else {
            Self.absent.insert(self)
            return nil
        }
        Self.pictures[self] = image
        return image
    }

    @MainActor private static var pictures: [AppIconChoice: NSImage] = [:]
    @MainActor private static var absent: Set<AppIconChoice> = []

    /// The choice stored in `defaults`: Clay for nothing, or a name this
    /// Capsid doesn't know (a later one's, after going back a version).
    static func stored(in defaults: UserDefaults = .standard) -> AppIconChoice {
        defaults.string(forKey: SettingsKey.appIcon).flatMap(AppIconChoice.init(rawValue:)) ?? standard
    }

    /// The icon to draw in Capsid's own windows (Settings, Welcome) for a
    /// stored name: the chosen picture, else whatever the app's icon is.
    @MainActor
    static func shown(_ name: String) -> NSImage {
        (AppIconChoice(rawValue: name) ?? standard).picture ?? NSApp.applicationIconImage
    }
}

/// What the Dock shows: the stored choice, or Capsid's own icon.
@MainActor
final class AppIconDock {
    static let shared = AppIconDock()

    /// True while a picture other than the bundle's has been handed to the Dock.
    private(set) var showsChosen = false

    /// Makes the stored choice the app's icon. Called at launch and whenever
    /// it changes. Clay, a picture that isn't there, and a name nobody knows
    /// all mean the bundle's own icon (Clay): nil, which restores it, and only
    /// when a chosen picture is up, so a Mac that never chooses is never told
    /// anything and a missing file never leaves a blank Dock tile. `load` and
    /// `set` are injected so a test never touches the real `NSApp`.
    func apply(from defaults: UserDefaults = .standard,
               load: (AppIconChoice) -> NSImage? = { $0.picture },
               set: (NSImage?) -> Void = { NSApp.applicationIconImage = $0 }) {
        let choice = AppIconChoice.stored(in: defaults)
        if choice != .clay, let image = load(choice) {
            set(image)
            showsChosen = true
        } else if showsChosen {
            set(nil)
            showsChosen = false
        }
    }
}
