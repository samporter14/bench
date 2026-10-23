// CompanionSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names
// a folder, draws the home popover (board 1's state, a return waiting, nothing
// to do, more rows than fit) and the menu bar item's faces into it as PNGs,
// light and dark, so they can be looked at without opening a window. Without
// it the test does nothing.
//
// The popover is glass, and glass is not drawn offscreen, so each is drawn on
// the board's neutral ground with the tint the panel puts over the blur. The
// specimens draw stills (`stillSpecimens`), since a playing layer is not
// painted either. What this cannot show: the blur itself, and the window the
// panel sits in.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct CompanionSnapshotTests {
    private func image(of step: CompanionDemo.Step, dark: Bool) async throws -> NSBitmapImageRep {
        let made = CompanionDemo.made(step)
        made.model.open()
        defer { made.model.close() }
        let view = ZStack {
            Rectangle().fill(CompanionDemo.ground(dark: dark))
            CompanionHomeView(model: made.model, presenting: made.presenting, actions: CompanionDemo.actions(made), maxHeight: 900)
                .padding(28)
        }
        .environment(\.stillSpecimens, true)
        .environment(\.colorScheme, dark ? .dark : .light)
        // The tallest picture is the busy one.
        let height: CGFloat = step == .busy ? 1000 : step == .empty ? 440 : 820
        return try await PanelSnapshotTests.capture(view, size: NSSize(width: 456, height: height), dark: dark, settle: 6)
    }

    /// The menu bar item's faces on a bar's own ground (the picture is drawn at 2×).
    private func itemImage(dark: Bool) async throws -> NSBitmapImageRep {
        let faces: [MenuBarFace] = [
            .of(homeOn: true, specimenOn: false, working: 0, allPaused: false, needs: 0),
            .of(homeOn: true, specimenOn: false, working: 2, allPaused: false, needs: 2),
            .of(homeOn: true, specimenOn: true, working: 1, allPaused: false, needs: 0),
            .of(homeOn: true, specimenOn: true, working: 1, allPaused: false, needs: 14),
            .of(homeOn: true, specimenOn: true, working: 2, allPaused: true, needs: 0),
        ]
        let ground = dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.93, green: 0.93, blue: 0.92)
        let view = HStack(spacing: 10) {
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                MenuBarItemView(face: face, dark: dark).frame(width: face.width, height: 24)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(ground)
        .environment(\.stillSpecimens, true)
        .environment(\.colorScheme, dark ? .dark : .light)
        return try await PanelSnapshotTests.capture(view, size: NSSize(width: 330, height: 30), dark: dark, settle: 3)
    }

    @Test func theHomePopoverIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for step in CompanionDemo.Step.allCases where step != .panel {
                let rep = try await image(of: step, dark: dark)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("menubar-\(step.rawValue)-\(dark ? "dark" : "light").png"))
            }
            let rep = try await itemImage(dark: dark)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("menubar-item-\(dark ? "dark" : "light").png"))
        }
    }

    @Test func theDemoWorldHoldsTheBoardsCounts() async {
        let made = CompanionDemo.made(.board)
        made.model.open()
        defer { made.model.close() }
        let sections = made.model.sections
        #expect(sections.needsTitle == "Needs you · 2" && sections.workingTitle == "Working · 2")
        #expect(sections.results?.title == "Results today · 7")
        #expect(sections.results?.tiles.map(\.name) == ["volcano.png", "z_prime.png", "heatmap.pdf", "hits_ranked.csv"])
        #expect(sections.usage?.value.hasPrefix("54% left") == true && sections.since == nil)
        let rows = sections.needs
        #expect(rows.map(\.pills).map { $0.map(\.title) } == [["Reply", "Open", "Later"], ["Approve", "Request changes…"]])
        #expect(rows.map(\.steps) == [nil, 6])
        #expect(made.results.picture(for: "demo-volcano") != nil && made.results.picture(for: "demo-zprime") != nil)
    }

    @Test func theOtherDemoStepsShowWhatTheyAreFor() async {
        let since = CompanionDemo.made(.since)
        since.model.open()
        #expect(since.model.sections.since != nil)
        since.model.close()
        let empty = CompanionDemo.made(.empty)
        empty.model.open()
        #expect(empty.model.sections.isQuiet && empty.model.sections.results == nil)
        empty.model.close()
        let busy = CompanionDemo.made(.busy)
        busy.model.open()
        #expect(busy.model.sections.needsHidden > 0 && busy.model.sections.workingHidden > 0)
        busy.model.close()
    }
}
