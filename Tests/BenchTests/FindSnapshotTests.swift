// FindSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the Shelf window with a search typed in it (the demo's made-up
// shelf and made-up sessions) into it as PNGs, light and dark: the shelf's own
// matches with "In your sessions" under them, a search the shelf has nothing
// for, an empty shelf, a search the database couldn't answer, a failed add, a
// small window, and Quick Open's group. Without it the test does nothing. The
// title bar belongs to the window and is not drawn here.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct FindSnapshotTests {
    /// The title bar the window draws around the content, as the mock-up has it.
    private struct Window<Content: View>: View {
        let model: ShelfModel
        let content: Content

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach([Color(red: 0.88, green: 0.38, blue: 0.35), Color(red: 0.91, green: 0.69, blue: 0.29), Color(red: 0.42, green: 0.75, blue: 0.36)], id: \.self) { color in
                        Circle().fill(color).frame(width: 12, height: 12)
                    }
                    Text("Shelf").font(.system(size: 15, weight: .semibold)).foregroundStyle(Solanum.ink).padding(.leading, 8)
                    ShelfProjectPill(model: model)
                    Spacer()
                    ShelfSearchPill(search: .constant(model.search))
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

    private func draw<V: View>(_ view: V, size: NSSize, name: String, to directory: URL, settle: Int = 14) async throws {
        for dark in [false, true] {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
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

    @Test func theSearchIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("find-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let size = NSSize(width: 880, height: 820)

        func shelfWindow(_ text: String, finder: ShelfFinder? = nil, on other: Shelf? = nil) -> ShelfView {
            let target = other ?? shelf
            let model = ShelfModel(shelf: target)
            model.finder = finder ?? FindDemo.finder(shelf: target, root: root)
            model.search = text
            return ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook())
        }
        func window(_ view: ShelfView) -> some View { Window(model: view.model, content: view) }

        // The shelf's two heatmaps, and the others in every session under them.
        try await draw(window(shelfWindow("heatmap")), size: size, name: "find-heatmap", to: directory)
        // Words the shelf has no match for: one line, Clear Search, and the section.
        try await draw(window(shelfWindow("yesterday")), size: size, name: "find-yesterday", to: directory)
        try await draw(window(shelfWindow("figures plate")), size: size, name: "find-figures-plate", to: directory)
        // The kind chip narrows the section too.
        let tables = shelfWindow("heatmap")
        tables.model.kind = .table
        try await draw(window(tables), size: size, name: "find-heatmap-tables", to: directory)
        // The narrowest window.
        try await draw(window(shelfWindow("heatmap")), size: NSSize(width: 620, height: 480), name: "find-small", to: directory)

        // A shelf with nothing on it: the section alone.
        let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("find-snapshot-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyDisk = KeptDisk(root: { emptyRoot })
        let emptyIndex = KeptIndex(disk: emptyDisk, root: { emptyRoot })
        let emptyShelf = KeptDemo.shelf(index: emptyIndex, root: emptyRoot)
        emptyIndex.refresh()
        try await Task.sleep(for: .milliseconds(400))
        try await draw(window(shelfWindow("heatmap", on: emptyShelf)), size: size, name: "find-empty-shelf", to: directory)

        // The database couldn't be read, and nothing matched.
        let unreadable = FindSearch(dependencies: .init(lookup: { _ in nil }, pause: .zero))
        let broken = ShelfFinder(search: unreadable, actions: FindDemo.finder(shelf: shelf, root: root).actions,
                                 thumbnails: ShelfThumbnails(), requestThumbnail: { _ in })
        try await draw(window(shelfWindow("heatmap", finder: broken)), size: size, name: "find-unreadable", to: directory, settle: 6)
        let nothing = FindSearch(dependencies: .init(lookup: { _ in [] }, pause: .zero))
        let none = ShelfFinder(search: nothing, actions: FindDemo.finder(shelf: shelf, root: root).actions,
                               thumbnails: ShelfThumbnails(), requestThumbnail: { _ in })
        try await draw(window(shelfWindow("zebrafish", finder: none)), size: size, name: "find-nothing", to: directory, settle: 6)

        // Rows in each of their states: one being added, one added from this search, one that couldn't be.
        let files = FindDemo.files(now: Date())
        let spinning = files[2].version, landed = files[3].version, refused = files[4].version
        let base = FindDemo.finder(shelf: shelf, root: root)
        let actions = FindActions(
            isAvailable: true,
            add: { file in
                file.version == landed
                    ? .added(ShelfPlacement(folder: root.appendingPathComponent("x"), name: file.name, collection: file.projectName))
                    : .failed("Capsid couldn\u{2019}t add \(file.name). Claude Science didn\u{2019}t answer.")
            },
            show: { _ in }, results: { _ in },
            onShelf: { shelf.contains(version: $0) }, isAdding: { $0 == spinning })
        let states = ShelfFinder(search: base.search, actions: actions, thumbnails: base.thumbnails, requestThumbnail: { _ in })
        let stateWindow = shelfWindow("heatmap", finder: states, on: emptyShelf)
        try await Task.sleep(for: .milliseconds(600))
        states.add(files.first { $0.version == landed }!)
        states.add(files.first { $0.version == refused }!)
        try await draw(window(stateWindow), size: size, name: "find-states", to: directory, settle: 10)
    }

    /// The window is up with the first card selected, and then the search is typed, which moves the
    /// selection: the detail card must show the new file's picture (it keeps its view, so the picture is
    /// asked for when the file changes, not only when the view appears).
    @Test func theDetailShowsThePictureOfTheFileASearchSelectsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("find-snapshot-move-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let model = ShelfModel(shelf: shelf)
        model.finder = FindDemo.finder(shelf: shelf, root: root)
        let size = NSSize(width: 880, height: 820)
        let host = NSHostingView(rootView: Window(model: model, content: ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook())))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
        }
        let first = model.selection
        model.search = "heatmap"
        for _ in 0..<25 {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
        }
        #expect(model.selection != first && model.selection != nil)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("find-selection-moves-light.png"))
        // The detail's picture is in the store at the detail's size.
        let selected = try #require(model.selected)
        #expect(thumbnails.image(for: selected.fileURL, side: 280) != nil)
    }

    @Test func quickOpenGroupIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let files = FindDemo.files(now: now).filter { $0.name.contains("heatmap") }
        let session = SessionStatus(id: madeUpID(1), projectID: "demo", projectName: "Assay development", title: "Plate heatmap check",
                                    state: .finished, updatedAt: now.addingTimeInterval(-3_600))
        struct Sheet: View {
            let session: SessionStatus
            let files: [FoundFile]
            var body: some View {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                        Text("heatmap").font(.title3)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider()
                    VStack(spacing: 2) {
                        Text("Plate heatmap check").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        Text(QuickOpenFiles.heading)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.top, 10)
                        ForEach(Array(files.prefix(QuickOpenFiles.shown).enumerated()), id: \.element.version) { n, file in
                            QuickOpenFileRow(file: file, isSelected: n == 0, onShelf: n == 2, action: {}, add: {})
                        }
                    }
                    .padding(8)
                }
                .frame(width: 560)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        try await draw(Sheet(session: session, files: files), size: NSSize(width: 560, height: 420), name: "find-quick-open", to: directory, settle: 2)
    }
}
