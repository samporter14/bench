// PanelSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the panel's moments (working with progress, finished, stopped
// with an error, a note from Claude, the stack of working sessions) on made-up
// sessions and insights into it as PNGs, light and dark, so they can be looked
// at without opening a window. Without it the test does nothing.
//
// The panel is glass, and glass is not drawn offscreen (a glass button fills
// its whole view with white), so each is drawn on a backdrop (board 6's slate,
// or an ivory) with `flatGlass`: the surface and the buttons become flat
// stand-ins of the same colours. The specimens draw stills (`stillSpecimens`),
// since a playing layer is not painted either. What this cannot show: the glass itself, and the clay
// tint of a glass button.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct PanelSnapshotTests {
    enum Moment: String, CaseIterable {
        case workingProgress = "working-progress"
        case workingPlain = "working"
        case finished
        case finishedOneFigure = "finished-one-figure"
        case failed
        case note
        case stack
    }

    /// Everything one picture needs, set up and torn down by the caller.
    struct Scene {
        let model: LabModel
        let insights: PanelInsights
        let finished: FinishedResults
        let hover: PanelHover
    }

    static func scene(_ moment: Moment) -> Scene {
        let model = LabModel()
        let insights = PanelInsights()
        let finished = FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false }))
        let hover = PanelHover()
        switch moment {
        case .workingProgress, .workingPlain:
            let shown = PanelDemo.prepare(.progress, insights: insights, finished: finished)
            if moment == .workingPlain { insights.showDemo() }
            model.showDemo(working: shown.working, cards: shown.cards)
        case .finished, .finishedOneFigure:
            let shown = PanelDemo.prepare(.finished, oneFigure: moment == .finishedOneFigure, insights: insights, finished: finished)
            model.showDemo(working: shown.working, cards: shown.cards)
        case .failed:
            let failed = PanelDemo.session(.error, id: "snapshot-failed", title: "Figure 2 rebuild", project: "Manuscript figures", minutes: 7 + 58.0 / 60)
            FailureReasoner.shared.showDemo(sessionID: failed.id, reason: FailureReason(
                line: "The R kernel ran out of memory while loading the full count matrix.",
                full: "The R kernel ran out of memory while loading the full count matrix."))
            model.showDemo(working: [], cards: [.failed(failed)])
        case .note:
            let shown = PanelDemo.prepare(.note, insights: insights, finished: finished)
            model.showDemo(working: shown.working, cards: shown.cards)
        case .stack:
            let shown = PanelDemo.prepare(.stack, insights: insights, finished: finished)
            model.showDemo(working: shown.working, cards: shown.cards)
            hover.isInside = true
        }
        return Scene(model: model, insights: insights, finished: finished, hover: hover)
    }

    static func image(of moment: Moment, dark: Bool, defaults: UserDefaults) async throws -> NSBitmapImageRep {
        let scene = scene(moment)
        let view = ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(dark ? Color(red: 0x3B / 255, green: 0x3A / 255, blue: 0x36 / 255)
                                  : Color(red: 0xEC / 255, green: 0xEA / 255, blue: 0xE2 / 255))
            LabPanelView(model: scene.model, hover: scene.hover, insights: scene.insights, finished: scene.finished, onFit: { _ in })
        }
        .environment(\.stillSpecimens, true)
        .environment(\.flatGlass, true)
        .environment(\.colorScheme, dark ? .dark : .light)
        .defaultAppStorage(defaults)
        return try await capture(view, size: NSSize(width: 440, height: moment == .stack ? 330 : 360), dark: dark)
    }

    /// Hosts a view offscreen, lets it settle, and draws it at 2x.
    static func capture(_ view: some View, size: NSSize, dark: Bool, settle: Int = 12) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = host.appearance
        host.layoutSubtreeIfNeeded()
        // Let the plate settle, the pictures and the layout land.
        for _ in 0..<settle {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// The activity list with a working session's progress under its project.
    static func activityImage(dark: Bool, defaults: UserDefaults) async throws -> NSBitmapImageRep {
        let working = [PanelDemo.session(.running, title: "CRISPR screen hits", project: "Screen analysis", minutes: 42),
                       PanelDemo.session(.running, id: "demo-2", title: "Plate layout", project: "Assay design", minutes: 17)]
        LabModel.shared.showDemo(working: working, cards: [])
        PanelInsights.shared.showDemo(progress: [working[0].id: PlanProgress(step: 4, total: 6, title: "Check against published screens")])
        defer {
            LabModel.shared.showDemo(working: [], cards: [])
            PanelInsights.shared.showDemo()
        }
        let view = ZStack {
            Rectangle().fill(dark ? Color(red: 0.16, green: 0.16, blue: 0.15) : Color(red: 0.97, green: 0.96, blue: 0.94))
            ActivityList(close: {}).background(dark ? Color(red: 0.2, green: 0.2, blue: 0.19) : .white)
        }
        .environment(\.stillSpecimens, true)
        .environment(\.colorScheme, dark ? .dark : .light)
        .defaultAppStorage(defaults)
        return try await capture(view, size: NSSize(width: 360, height: 220), dark: dark, settle: 4)
    }

    /// Settings → Specimens, for the new checkbox.
    static func settingsImage(dark: Bool, defaults: UserDefaults) async throws -> NSBitmapImageRep {
        let view = SceneSettingsView()
            .frame(width: 696, height: 520, alignment: .top)
            .background(dark ? Color(red: 0.16, green: 0.16, blue: 0.15) : Color(red: 0.93, green: 0.93, blue: 0.93))
            .environment(\.stillSpecimens, true)
            .environment(\.colorScheme, dark ? .dark : .light)
            .defaultAppStorage(defaults)
        return try await capture(view, size: NSSize(width: 696, height: 520), dark: dark, settle: 4)
    }

    @Test func thePanelsMomentsAreDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Settings the pictures need, registered for this run only: a registered
        // default is never written, so nothing is left in ~/Library/Preferences.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            SettingsKey.showSpecimenCaption: true, SettingsKey.matchSpecimenToSession: true,
            SettingsKey.showCards: true, SettingsKey.showPanel: true,
        ])
        defer {
            SessionSpecimen.matcher = SpecimenTopics.match
            SessionSpecimen.forget()
        }
        // The matcher the data branch brings is not here yet: this one names the
        // board's example.
        SessionSpecimen.matcher = { title, _, candidates in
            title.contains("CRISPR") && candidates.contains("CRISPR") ? (name: "CRISPR", topic: "a CRISPRi screen") : nil
        }
        SessionSpecimen.forget()
        func write(_ rep: NSBitmapImageRep, _ name: String, _ dark: Bool) throws {
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        for dark in [false, true] {
            for moment in Moment.allCases {
                try write(try await Self.image(of: moment, dark: dark, defaults: defaults), "panel-\(moment.rawValue)", dark)
            }
            try write(try await Self.activityImage(dark: dark, defaults: defaults), "activity-progress", dark)
            try write(try await Self.settingsImage(dark: dark, defaults: defaults), "settings-specimens", dark)
        }
    }
}
