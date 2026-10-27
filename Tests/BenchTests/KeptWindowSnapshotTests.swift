// KeptWindowSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR`
// names a folder, draws the Shelf window's content (the demo's made-up shelf,
// in a temporary root) into it as PNGs, light and dark, so it can be looked at
// without opening a window: board 12's window with the first card selected, an
// item kept with data and code, a kind, a search that finds nothing, the
// narrowest window, three picked, the older days, one project, and the empty
// shelf.
// Without it the test does nothing. The title bar belongs to the window; a
// stand-in for it is drawn here.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct KeptWindowSnapshotTests {
    /// The title bar the window draws around the content, as the mock-up has it
    /// (the toolbar itself belongs to the window): the three dots, "Shelf", the
    /// project pill, and at the right Export as PDF… (two or more picked) and
    /// the search pill, in a band
    /// under a hairline.
    private struct Window<Content: View>: View {
        let model: ShelfModel
        let content: Content
        var width: CGFloat = KeptWindowController.size.width

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color(red: 0.88, green: 0.38, blue: 0.35), Color(red: 0.91, green: 0.69, blue: 0.29), Color(red: 0.42, green: 0.75, blue: 0.36)], id: \.self) { color in
                        Circle().fill(color).frame(width: 12, height: 12)
                    }
                    Text("Shelf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Solanum.ink).padding(.leading, 8)
                    ShelfProjectPill(model: model)
                    Spacer()
                    if model.showsExportPill { ShelfExportPDFButton(model: model) }
                    ShelfSearchPill(search: .constant(model.search), width: ShelfSearchPill.width(forWindow: width))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Solanum.bar)
                .overlay(alignment: .bottom) { Solanum.hairline.frame(height: 1) }
                content
            }
            .background(Solanum.page)
        }
    }

    /// Draws a view the size of the window into `name-light.png` and `name-dark.png`.
    private func draw(_ content: ShelfView, size: NSSize, name: String, to directory: URL, settle: Int = 20) async throws {
        let view = Window(model: content.model, content: content, width: size.width)
        for dark in [false, true] {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            // Let the selection, the README read and the thumbnails land.
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
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    /// The legend and files under an item kept with data and code, as the detail card draws them: with its README read, and
    /// with the README gone, where the field is off and a line says why.
    @Test func theLegendFieldIsDrawnReadableAndUnreadableWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let model = ShelfModel(shelf: shelf)
        let item = try #require(model.items.first { !$0.record.files.isEmpty })

        func card(_ name: String) async throws {
            let view = ShelfExtras(item: item, model: model)
                .padding(18)
                .frame(width: 840)
                .background(Solanum.raised)
                .background(Solanum.page)
            for dark in [false, true] {
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: CGSize(width: 840 + 36, height: 190))
                host.layoutSubtreeIfNeeded()
                for _ in 0..<10 {
                    try await Task.sleep(for: .milliseconds(100))
                    host.layoutSubtreeIfNeeded()
                }
                let size = host.bounds.size
                let rep = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                rep.size = size
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }

        try await card("shelf-legend")
        // The README is gone: the field is off, and the line says why.
        try FileManager.default.removeItem(at: item.folder.appendingPathComponent("README.md"))
        try await card("shelf-legend-unreadable")
    }

    @Test func theShelfWindowIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let size = KeptWindowController.size

        // The board's window: the first card selected.
        let model = ShelfModel(shelf: shelf)
        try await draw(ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window", to: directory)

        // The item kept with data and code: its legend and files below.
        let kept = ShelfModel(shelf: shelf)
        kept.selection = kept.items.first { $0.hasMore }?.id
        try await draw(ShelfView(model: kept, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-kept", to: directory)

        // A kind, a search with no match, a project.
        let tables = ShelfModel(shelf: shelf)
        tables.kind = .table
        try await draw(ShelfView(model: tables, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-tables", to: directory)
        let none = ShelfModel(shelf: shelf)
        none.search = "zebrafish"
        try await draw(ShelfView(model: none, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-no-match", to: directory, settle: 3)

        // A small window, the narrowest and shortest the window allows.
        try await draw(ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: NSSize(width: 620, height: 480),
                       name: "shelf-window-small", to: directory, settle: 8)

        // Three picked: the page badges, the picked card, and Export as PDF… in the title bar.
        let picked = ShelfModel(shelf: shelf)
        let figures = picked.shown.filter { $0.kind == .figure }
        picked.pick(figures[0].id, .only)
        picked.pick(figures[1].id, .toggle)
        picked.pick(figures[2].id, .toggle)
        try await draw(ShelfView(model: picked, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-picked", to: directory)
        // Scrolled to the older days: the selection at the end, with the legend field of the item kept with data and code.
        let older = ShelfModel(shelf: shelf)
        older.selection = older.shown.last?.id
        try await draw(ShelfView(model: older, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-older", to: directory)
        // One project: its days, This week and Earlier this month among them.
        let paper = ShelfModel(shelf: shelf)
        paper.project = "Paper draft"
        try await draw(ShelfView(model: paper, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-project", to: directory)

        // Nothing on the shelf yet.
        let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-snapshot-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyDisk = KeptDisk(root: { emptyRoot })
        let emptyIndex = KeptIndex(disk: emptyDisk, root: { emptyRoot })
        let emptyShelf = KeptDemo.shelf(index: emptyIndex, root: emptyRoot)
        emptyIndex.refresh()
        try await Task.sleep(for: .milliseconds(500))
        try await draw(ShelfView(model: ShelfModel(shelf: emptyShelf), thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-window-empty", to: directory, settle: 3)
    }
}
