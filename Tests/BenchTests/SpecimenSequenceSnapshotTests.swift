// SpecimenSequenceSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR`
// names a folder, draws every short sequence the catalogue can play, through
// the rotation the app plays and the drawing it uses (`Rotation.scene(at:)`
// and `LabScenes.draw(_:in:size:local:tint:)`, fade and all), into it:
//   - one GIF of the whole run, member after member, at 10 frames a second and
//     96 pt at 2x, in each theme;
//   - stills just before and just after every change, as a PNG each and as one
//     sheet per sequence, with the run's entry and exit among them;
//   - Settings → Specimens with the "Play short sequences" checkbox off and on.
// Without the folder the test does nothing. A grid of isolated loops would
// show none of what this shows: the order, the hand-over and the timing.
import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Bench

@MainActor
struct SpecimenSequenceSnapshotTests {
    /// The size the panel's well is (88 pt) rounded to a tidy 96, and drawn at 2x.
    static let side: CGFloat = 96
    static let scale: CGFloat = 2
    static let fps = 10.0
    /// How far either side of a change the stills are taken.
    static let nudge = 0.1

    struct Look {
        let name: String
        let ground: Color
        let ink: Color
        var scheme: ColorScheme { name == "dark" ? .dark : .light }
    }

    /// The panel's own grounds and the scenes' own ink in each theme.
    static let looks = [
        Look(name: "light", ground: Color(red: 0.97, green: 0.96, blue: 0.94), ink: ColorScheme.light.sceneInk),
        Look(name: "dark", ground: Color(red: 0.2, green: 0.2, blue: 0.19), ink: ColorScheme.dark.sceneInk),
    ]

    /// The rotation at `t`, drawn the way the app draws it: the scene it says
    /// is playing, `local` seconds in, with the fade.
    static func frame(of rotation: Rotation, at t: Double, look: Look) -> CGImage? {
        let (index, local) = rotation.scene(at: t)
        let scene = rotation.scenes[index]
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(look.ground))
            LabScenes.draw(scene, in: &context, size: size, local: local, tint: look.ink)
        }
        .frame(width: side, height: side)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = scale
        return renderer.cgImage
    }

    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let properties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(destination, frame, properties) }
        try #require(CGImageDestinationFinalize(destination))
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// One change: from the scene on the left of it to the one on the right.
    struct Change {
        let label: String
        let at: Double
    }

    /// A sheet of the stills, one row a change.
    struct Sheet: View {
        let rows: [(label: String, before: CGImage, after: CGImage)]
        let look: Look

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 10) {
                        Image(decorative: rows[row].before, scale: SpecimenSequenceSnapshotTests.scale)
                        Image(decorative: rows[row].after, scale: SpecimenSequenceSnapshotTests.scale)
                        Text(rows[row].label)
                            .font(.system(size: 12))
                            .foregroundStyle(look.ink)
                            .frame(width: 210, alignment: .leading)
                    }
                }
            }
            .padding(16)
            .background(look.ground)
        }
    }

    @Test func theSequencesAreDrawnWhereTheyAreMadeWhenAsked() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The rotation the app plays with the setting on, from the catalogue.
        let scratch = ScratchDefaults.make(prefix: "sequence-snapshot")
        defer { scratch.discard() }
        let settings = SceneSettings(defaults: scratch.defaults)
        settings.playSequences = true
        let rotation = settings.rotation
        let woven = SpecimenSequence.weave(LabScenes.catalogue, sequences: SpecimenSequence.curated)
        #expect(rotation == Rotation(woven.scenes), "the setting plays what the weave makes")

        var made: [String] = []
        var seen = Set<String>()
        for block in woven.blocks where seen.insert(block.sequence.title).inserted {
            let slug = block.sequence.title.lowercased().replacingOccurrences(of: " ", with: "-")
            let first = block.range.lowerBound
            let begins = rotation.scenes.prefix(first).reduce(0) { $0 + $1.duration }
            let total = block.range.reduce(0) { $0 + rotation.scenes[$1].duration }
            // The changes: into the first member, between members, out of the last.
            var changes: [Change] = []
            let before = rotation.scenes[(first + rotation.scenes.count - 1) % rotation.scenes.count].name
            let after = rotation.scenes[block.range.upperBound % rotation.scenes.count].name
            var at = begins
            var previous = before
            for index in block.range {
                changes.append(Change(label: "\(previous) → \(rotation.scenes[index].name)", at: at))
                previous = rotation.scenes[index].name
                at += rotation.scenes[index].duration
            }
            changes.append(Change(label: "\(previous) → \(after)", at: at))

            for look in Self.looks {
                let count = Int((total * Self.fps).rounded())
                let frames = (0..<count).compactMap { Self.frame(of: rotation, at: begins + Double($0) / Self.fps, look: look) }
                #expect(frames.count == count)
                try Self.writeGIF(frames, delay: 1 / Self.fps, to: directory.appendingPathComponent("\(slug)-\(look.name).gif"))

                var rows: [(label: String, before: CGImage, after: CGImage)] = []
                for (k, change) in changes.enumerated() {
                    let one = try #require(Self.frame(of: rotation, at: change.at - Self.nudge, look: look))
                    let two = try #require(Self.frame(of: rotation, at: change.at + Self.nudge, look: look))
                    try Self.writePNG(one, to: directory.appendingPathComponent("\(slug)-\(look.name)-change\(k + 1)-before.png"))
                    try Self.writePNG(two, to: directory.appendingPathComponent("\(slug)-\(look.name)-change\(k + 1)-after.png"))
                    rows.append((change.label, one, two))
                }
                let renderer = ImageRenderer(content: Sheet(rows: rows, look: look).environment(\.colorScheme, look.scheme))
                renderer.scale = Self.scale
                try Self.writePNG(try #require(renderer.cgImage), to: directory.appendingPathComponent("\(slug)-\(look.name)-changes.png"))
            }
            made.append(block.sequence.title)
        }
        // Nothing here is a check of the stories themselves; this says which
        // ones the catalogue can play, so a missing member shows.
        print("short sequences drawn: \(made.isEmpty ? "none" : made.joined(separator: ", "))")
    }

    @Test func theSettingsCheckboxIsDrawnOffAndOnWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        defaults.register(defaults: [SettingsKey.matchSpecimenToSession: true])
        for on in [false, true] {
            // The page's own settings, over a scratch suite: nothing is written
            // to the app's preferences.
            let scratch = ScratchDefaults.make(prefix: "sequence-settings-snapshot")
            defer { scratch.discard() }
            let settings = SceneSettings(defaults: scratch.defaults)
            settings.playSequences = on
            for dark in [false, true] {
                let view = SceneSettingsView(settings: settings)
                    .frame(width: 696, height: 520, alignment: .top)
                    .background(dark ? Color(red: 0.16, green: 0.16, blue: 0.15) : Color(red: 0.93, green: 0.93, blue: 0.93))
                    .environment(\.stillSpecimens, true)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .defaultAppStorage(defaults)
                let rep = try await PanelSnapshotTests.capture(view, size: NSSize(width: 696, height: 520), dark: dark, settle: 4)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("settings-specimens-sequences-\(on ? "on" : "off")-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
