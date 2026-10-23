// SinceYouLeftSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR`
// names a folder, draws Since You Left (board 2's sheet, the activity list's
// section and the panel's card) on the demo's made-up return into it as PNGs,
// light and dark, so it can be looked at without opening a window. Without the
// variable the test does nothing. It draws through an `NSHostingView` that is
// never put in a window, so a sheet's own material is absent (the sheet paints
// its own ivory or slate), and the panel's glass is its flat stand-in.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct SinceYouLeftSnapshotTests {
    static func model(radio: Bool = true) -> (model: SinceYouLeftModel, actions: CardActions) {
        let lab = LabModel()
        let finished = FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false }))
        let model = SinceYouLeftModel(lab: lab, finished: finished, dependencies: SinceYouLeftDemo.demoDependencies(model: nil))
        let replier = QuestionReplier(model: lab, dependencies: .live())
        SinceYouLeftDemo.fill(model: model, replier: replier, radio: radio)
        return (model, CardActions(model: lab, plans: PlanApprover.shared, questions: replier))
    }

    static func write(_ rep: NSBitmapImageRep, _ name: String, dark: Bool, to directory: URL) throws {
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    /// Hosts a view offscreen at `width`, lets it settle and draws it at 2x at its own height.
    static func draw(_ view: some View, width: CGFloat, height: CGFloat = 1200, dark: Bool, backdrop: Bool = false) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: max(size.height, 10)))
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    @Test func theSheetTheListAndTheCardAreDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        defaults.register(defaults: [SinceYouLeftSettings.sheetKey: true, SettingsKey.showCards: true, SettingsKey.showPanel: true])
        let (model, actions) = Self.model()
        for dark in [false, true] {
            let sheet = SinceYouLeftSheet(model: model, maxHeight: 900, cardActions: actions)
            try Self.write(try await Self.draw(sheet, width: SinceYouLeftSheet.width, dark: dark), "since-sheet", dark: dark, to: directory)
        }

        // The activity list's section, over the shared lab and model.
        SinceYouLeftDemo.fill(model: .shared, replier: .shared)
        defer {
            LabModel.shared.showDemo(working: [], cards: [])
            SinceYouLeftModel.shared.done()
        }
        for dark in [false, true] {
            let list = ZStack {
                Rectangle().fill(dark ? Color(red: 0.16, green: 0.16, blue: 0.15) : Color(red: 0.97, green: 0.96, blue: 0.94))
                ActivityList(close: {}).background(dark ? Color(red: 0.2, green: 0.2, blue: 0.19) : .white)
            }
            .environment(\.stillSpecimens, true)
            .environment(\.colorScheme, dark ? .dark : .light)
            try Self.write(try await PanelSnapshotTests.capture(list, size: NSSize(width: 360, height: 220), dark: dark, settle: 4),
                           "since-list", dark: dark, to: directory)
        }

        // The panel's card, on the panel's own backdrops.
        let made = SinceYouLeftDemo.made()
        let summary = SinceYouLeftSummary.make(since: made.since, back: made.back, events: made.events,
                                               waiting: [made.ask], working: [])
        let notice = try #require(SinceYouLeftModel.notice(for: summary, now: made.back))
        let lab = LabModel()
        lab.showDemo(working: [], cards: [.notice(notice)])
        for dark in [false, true] {
            let view = ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(dark ? Color(red: 0x3B / 255, green: 0x3A / 255, blue: 0x36 / 255)
                                      : Color(red: 0xEC / 255, green: 0xEA / 255, blue: 0xE2 / 255))
                LabPanelView(model: lab, hover: PanelHover(), insights: PanelInsights(),
                             finished: FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false })), onFit: { _ in })
            }
            .environment(\.stillSpecimens, true)
            .environment(\.flatGlass, true)
            .environment(\.colorScheme, dark ? .dark : .light)
            try Self.write(try await PanelSnapshotTests.capture(view, size: NSSize(width: 440, height: 200), dark: dark, settle: 6),
                           "since-card", dark: dark, to: directory)
        }
    }
}
