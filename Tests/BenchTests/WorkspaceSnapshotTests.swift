// WorkspaceSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the Project Workspace panel into it as PNGs, offscreen, light
// and dark, at the window's first size and at its least: a project with
// nothing yet, a note and pins, a Return that couldn't bring everything back,
// a long project name, a note near its limit, and a save that failed. The
// title bar is drawn as the window draws it (the toolbar belongs to the window,
// so the same title and ⋯ views stand on a band of the bar's colour). Made-up
// names and a disk in memory; without the variable the test does nothing.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct WorkspaceSnapshotTests {
    private struct Window: View {
        let model: WorkspacePanelModel
        let width: CGFloat
        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    WorkspaceTitle(name: model.displayName, windowWidth: width)
                    HStack(spacing: 8) {
                        ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                                 Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                            Circle().fill(color).frame(width: 12, height: 12)
                        }
                        Spacer()
                        WorkspaceMoreMenu(canClear: model.canClear, clear: {})
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(ZStack { Solanum.page; Solanum.bar })
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                WorkspaceView(model: model)
            }
            .background(Solanum.page)
        }
    }

    private static let alpha = "proj-alpha"

    private func draw(_ model: WorkspacePanelModel, name: String, sizes: [NSSize], to directory: URL) async throws {
        for size in sizes {
            for dark in [false, true] {
                let host = NSHostingView(rootView: Window(model: model, width: size.width))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                for _ in 0..<8 {
                    try await Task.sleep(for: .milliseconds(40))
                    host.layoutSubtreeIfNeeded()
                }
                let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                                        pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                                        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                        bytesPerRow: 0, bitsPerPixel: 0))
                rep.size = size
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                let suffix = size == WorkspacePanelController.minimum ? "-minimum" : ""
                try png.write(to: directory.appendingPathComponent("\(name)\(suffix)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    /// `gone`: the sessions the made-up database no longer has.
    private static let titles = [madeUpID(100): "Plate reader QC", madeUpID(1): "Dose response, plate 7 repeat",
                                 madeUpID(2): "Z\u{2032} by plate", madeUpID(3): "Edge effects, first look",
                                 madeUpID(4): "Controls, overnight run"]

    private func panel(disk: FakeWorkspaceDisk, app: FakeWorkspaceApp, last: String? = madeUpID(100),
                       gone: Set<String> = [madeUpID(3)], projectName: String = "Assay development") -> WorkspacePanelModel {
        let store = WorkspaceStore(disk: disk, delay: .seconds(60), longest: .seconds(60))
        let titles = Self.titles
        return WorkspacePanelModel(store: store, returner: WorkspaceReturner(dependencies: app.dependencies),
                                   dependencies: WorkspacePanelDependencies(
                                       look: { sessionID, _ in
                                           gone.contains(sessionID) ? .gone
                                               : .known(title: titles[sessionID] ?? "Untitled", projectName: projectName)
                                       },
                                       projectName: { _ in nil }, watchedName: { _ in nil }, lastSession: { _ in last },
                                       openPin: { _, _ in }))
    }

    private func pin(_ store: WorkspaceStore, _ n: Int, _ title: String, project: String = WorkspaceSnapshotTests.alpha,
                     name: String = "Assay development") async {
        _ = await store.pin(sessionID: madeUpID(n), projectID: project, row: 10 * n, title: title, projectName: name)
    }

    private static let note = """
    Plate 7 fails on an edge effect in column 12. Repeat it with a fresh seal before hit picking.

    Keep the repeat's plate map the same so the columns compare.
    """

    @Test func theWorkspacePanelIsDrawnWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let both = [WorkspacePanelController.size, WorkspacePanelController.minimum]
        let normal = [WorkspacePanelController.size]

        // A project with nothing yet.
        do {
            let model = panel(disk: FakeWorkspaceDisk(), app: FakeWorkspaceApp())
            await model.show(Self.alpha, name: "Assay development").value
            try await draw(model, name: "workspace-empty", sizes: both, to: directory)
        }

        // A note and two pins (one whose session has gone).
        do {
            let model = panel(disk: FakeWorkspaceDisk(), app: FakeWorkspaceApp())
            await pin(model.store, 1, "Dose response, plate 7 repeat")
            await pin(model.store, 2, "Z\u{2032} by plate")
            await pin(model.store, 3, "Edge effects, first look")
            model.store.setNote(Self.note, for: Self.alpha)
            await model.show(Self.alpha, name: "Assay development").value
            try await draw(model, name: "workspace-note-and-pins", sizes: both, to: directory)
        }

        // A Return that couldn't bring everything back: the last conversation has gone, one pin's session too, and
        // one pin's reply isn't there any more.
        do {
            let app = FakeWorkspaceApp()
            app.sessions[madeUpID(1)] = .known(title: "Dose response, plate 7 repeat", projectName: "Assay development")
            app.sessions[madeUpID(2)] = .known(title: "Z\u{2032} by plate", projectName: "Assay development")
            app.landings[madeUpID(2)] = .replyMissing
            let model = panel(disk: FakeWorkspaceDisk(), app: app, gone: [madeUpID(100), madeUpID(3), madeUpID(4)])
            await pin(model.store, 1, "Dose response, plate 7 repeat")
            await pin(model.store, 2, "Z\u{2032} by plate")
            await pin(model.store, 3, "Edge effects, first look")
            await pin(model.store, 4, "Controls, overnight run")
            model.store.setNote(Self.note, for: Self.alpha)
            await model.show(Self.alpha, name: "Assay development").value
            await model.returnToProject().value
            try await draw(model, name: "workspace-return-partial", sizes: both, to: directory)
        }

        // A long project name.
        do {
            let long = "Assay development and plate reader QC for the overnight 384-well screening campaign, second round"
            let model = panel(disk: FakeWorkspaceDisk(), app: FakeWorkspaceApp(), projectName: long)
            await pin(model.store, 1, "Dose response, plate 7 repeat", name: long)
            model.store.setNote(Self.note, for: Self.alpha)
            await model.show(Self.alpha, name: long).value
            try await draw(model, name: "workspace-long-name", sizes: both, to: directory)
        }

        // A note near its limit.
        do {
            let model = panel(disk: FakeWorkspaceDisk(), app: FakeWorkspaceApp())
            let paragraph = "Column 12 reads low on every plate from the third incubator shelf. Check the seal and the humidity tray. "
            var text = ""
            while WorkspaceRules.bytes(text) + paragraph.utf8.count <= 61 * 1_024 { text += paragraph }
            await pin(model.store, 1, "Dose response, plate 7 repeat")
            model.store.setNote(text, for: Self.alpha)
            await model.show(Self.alpha, name: "Assay development").value
            // A paste that would go past the limit was refused.
            model.store.refuseNote(for: Self.alpha)
            try await draw(model, name: "workspace-note-near-limit", sizes: normal, to: directory)
        }

        // A save that failed.
        do {
            let disk = FakeWorkspaceDisk()
            let model = panel(disk: disk, app: FakeWorkspaceApp())
            await pin(model.store, 1, "Dose response, plate 7 repeat")
            await model.show(Self.alpha, name: "Assay development").value
            disk.failsWrites = true
            model.edit(Self.note)
            await model.store.flush(Self.alpha).value
            try await draw(model, name: "workspace-save-failed", sizes: both, to: directory)
        }

        // A file Capsid can't read.
        do {
            let disk = FakeWorkspaceDisk()
            disk.files[Self.alpha] = Data(#"{"schema": 4}"#.utf8)
            let model = panel(disk: disk, app: FakeWorkspaceApp())
            await model.show(Self.alpha, name: "Assay development").value
            try await draw(model, name: "workspace-newer-file", sizes: normal, to: directory)
        }
    }
}
