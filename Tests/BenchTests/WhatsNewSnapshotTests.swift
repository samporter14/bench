// WhatsNewSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws What's New in Capsid offscreen (App/WhatsNewWindow.swift), every
// page in light and dark, page 3 playing and under Reduce Motion, and the
// fourteen new specimens on their own, into it as PNGs. Without the folder the
// test does nothing. Nothing is opened on screen: the window's content is
// hosted in a view that is never shown, and a title bar is drawn above it as a
// stand-in.
//
// Glass is not drawn offscreen (PanelSnapshotTests), so the well and the two
// buttons are the flat stand-ins of the same colours (`flatGlass`); the clay
// of the primary button and of the switch are the real ones. A playing layer is
// not painted either, so page 3 "playing" is the specimens well drawing one
// frame of its cycle (`specimenCycleFrame`), and Reduce Motion is the well's
// own still (`stillSpecimens` is what the well reads beside the system's setting).
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct WhatsNewSnapshotTests {
    /// The window as it looks: a title bar's stand-in over the content, which
    /// is the real view.
    private struct Frame: View {
        let model: WhatsNewModel
        let settings: SceneSettings

        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12, height: 12) }
                        Spacer()
                    }
                    .padding(.leading, 12)
                    Text("What\u{2019}s New in Capsid")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(height: 28)
                WhatsNewView(model: model, close: {}, settings: settings)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private static let size = NSSize(width: TourWindow.size.width, height: TourWindow.size.height + 28)

    private func write(_ rep: NSBitmapImageRep, _ name: String, to directory: URL) throws {
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func snapshotDirectory() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func everyPageIsDrawnInBothThemesWhenAsked() async throws {
        guard let directory = try snapshotDirectory() else { return }
        let scratch = ScratchDefaults.make(prefix: "WhatsNewSnapshotTests")
        defer { scratch.discard() }
        let settings = SceneSettings(defaults: scratch.defaults)
        let release = WhatsNew.release11
        // Where the cycle is in the middle of the fern unfurling.
        let scenes = release.pages.compactMap { page -> [String]? in
            if case .specimens(let names) = page.art { return names } else { return nil }
        }.first ?? []
        let cycle = Rotation(scenes.compactMap { name in LabScenes.catalogue.first { $0.name == name } })
        let fern = try #require(scenes.firstIndex(of: "Fern unfurling"))
        let before = cycle.scenes[..<fern].reduce(0) { $0 + $1.duration }
        let frame = (before + cycle.scenes[fern].duration * 0.6) / cycle.cycle

        let names = ["compare", "workspaces", "specimens", "show-source"]
        for (index, name) in names.enumerated() {
            for dark in [false, true] {
                let model = WhatsNewModel(release: release)
                model.open(release, page: index + 1)
                // Page 3 playing is one frame of the cycle; the others have nothing that moves.
                let view = Frame(model: model, settings: settings)
                    .environment(\.specimenCycleFrame, index == 2 ? frame : nil)
                    .environment(\.flatGlass, true)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let rep = try await PanelSnapshotTests.capture(view, size: Self.size, dark: dark, settle: 4)
                try write(rep, "page\(index + 1)-\(name)-\(dark ? "dark" : "light")", to: directory)
            }
        }
    }

    @Test func pageThreeIsDrawnUnderReduceMotionAndWithTheSwitchOnWhenAsked() async throws {
        guard let directory = try snapshotDirectory() else { return }
        let scratch = ScratchDefaults.make(prefix: "WhatsNewSnapshotTests")
        defer { scratch.discard() }
        let settings = SceneSettings(defaults: scratch.defaults)
        let release = WhatsNew.release11
        let model = WhatsNewModel(release: release)
        model.open(release, page: 3)
        // Under Reduce Motion the well rests on the first specimen's still; its poster time is worked out a moment after.
        for dark in [false, true] {
            let view = Frame(model: model, settings: settings)
                .environment(\.stillSpecimens, true)
                .environment(\.flatGlass, true)
                .environment(\.colorScheme, dark ? .dark : .light)
            let rep = try await PanelSnapshotTests.capture(view, size: Self.size, dark: dark, settle: 14)
            try write(rep, "page3-specimens-reduce-motion-\(dark ? "dark" : "light")", to: directory)
        }
        // The switch on is the real setting on a throwaway suite.
        settings.playSequences = true
        let on = Frame(model: model, settings: settings)
            .environment(\.stillSpecimens, true)
            .environment(\.flatGlass, true)
            .environment(\.colorScheme, .light)
        let rep = try await PanelSnapshotTests.capture(on, size: Self.size, dark: false, settle: 14)
        try write(rep, "page3-switch-on-light", to: directory)
        #expect(scratch.defaults.bool(forKey: "playShortSequences"))
    }

    /// The Welcome's panel page in the same frame, to see the two as siblings.
    @Test func theWelcomesPanelPageIsDrawnBesideItWhenAsked() async throws {
        guard let directory = try snapshotDirectory() else { return }
        let model = WelcomeModel()
        model.flow = WelcomeFlow(startingAt: 2)
        for dark in [false, true] {
            let view = VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 8) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12, height: 12) }
                        Spacer()
                    }
                    .padding(.leading, 12)
                    Text("Welcome to Capsid").font(.system(size: 13, weight: .semibold))
                }
                .frame(height: 28)
                WelcomeView(model: model, close: {})
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.stillSpecimens, true)
            .environment(\.flatGlass, true)
            .environment(\.colorScheme, dark ? .dark : .light)
            let rep = try await PanelSnapshotTests.capture(view, size: Self.size, dark: dark, settle: 14)
            try write(rep, "compare-welcome-page2-\(dark ? "dark" : "light")", to: directory)
        }
    }

    /// The fourteen new specimens, each at the middle of its scene in the well, in a row, to see that every one draws.
    @Test func theNewSpecimensAreDrawnInTheirWellWhenAsked() async throws {
        guard let directory = try snapshotDirectory() else { return }
        guard case .specimens(let names) = WhatsNew.release11.pages[2].art else { return }
        for dark in [false, true] {
            let ink = (dark ? ColorScheme.dark : ColorScheme.light).sceneInk
            let row = HStack(spacing: 14) {
                ForEach(names, id: \.self) { name in
                    VStack(spacing: 6) {
                        TourWell {
                            Canvas { context, size in
                                if let scene = LabScenes.catalogue.first(where: { $0.name == name }) {
                                    LabScenes.draw(scene, in: &context, size: size, local: scene.duration * 0.55, tint: ink)
                                }
                            }
                            .frame(width: 64, height: 64)
                        }
                        Text(name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.center).frame(width: 96)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.flatGlass, true)
            .environment(\.colorScheme, dark ? .dark : .light)
            let rep = try await PanelSnapshotTests.capture(row, size: NSSize(width: 1240, height: 160), dark: dark, settle: 3)
            try write(rep, "specimens-sheet-\(dark ? "dark" : "light")", to: directory)
        }
    }
}
