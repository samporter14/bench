// ShelfAddSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the Shelf's ways in (the toast, the reference window with a
// shelved figure and a file, Results' rows, the toolbar's pill) into it as
// PNGs, light and dark, so they can be looked at against boards 10 and 11
// without opening a window. Without it the tests do nothing. Made-up data,
// a made-up shelf, no page and no daemon.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
enum ShelfSnapshot {
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Draws `view` at `size` in light and dark to `<name>-light.png` and `<name>-dark.png`.
    static func write<V: View>(_ view: V, size: CGSize, name: String, to directory: URL,
                               appearances: [Bool] = [false, true]) throws {
        for dark in appearances {
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
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
}

@MainActor
struct ShelfAddSnapshotTests {
    // MARK: The toast

    /// The page's foot: the ivory page and a composer, with the toast where board 10 has it.
    private struct Foot: View {
        @ObservedObject var model: ShelfToastModel
        var body: some View {
            ZStack(alignment: .bottom) {
                Solanum.page
                RoundedRectangle(cornerRadius: 14).fill(Solanum.raised)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Solanum.strong, lineWidth: 1))
                    .frame(height: 56)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                ShelfToastView(model: model)
                    .padding(.bottom, 96)
            }
        }
    }

    @Test func theToastIsDrawnToPNGsWhenAsked() throws {
        guard let directory = ShelfSnapshot.directory else { return }
        let states: [(String, ShelfToastModel.State)] = [
            ("added", .added(MadeShelf.placement("z_prime_by_plate.png"))),
            ("already", .already(MadeShelf.placement())),
            ("adding", .adding),
            ("failed", .failed("That file is gone from Claude Science.")),
            ("undone", .undone("z_prime_by_plate.png")),
            ("long", .added(MadeShelf.placement("a_very_long_file_name_for_the_plate_reader_qc_of_the_overnight_run_21_october.png"))),
        ]
        for (name, state) in states {
            let model = ShelfToastModel(shelf: MadeShelf().access, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        announce: { _ in })
            model.show(state)
            try ShelfSnapshot.write(Foot(model: model), size: CGSize(width: 760, height: 220), name: "toast-\(name)", to: directory)
            model.dismiss()
        }
    }

    // MARK: The toolbar's pill

    @Test func theToolbarPillIsDrawnToPNGsWhenAsked() throws {
        guard let directory = ShelfSnapshot.directory else { return }
        for count in [0, 1, 12] {
            let fake = MadeShelf()
            fake.onShelf = Set((0..<count).map { "v\($0)" })
            let view = HStack(spacing: 8) {
                ResultsToolbarButton()
                ShelfToolbarButton(shelf: fake.access)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            try ShelfSnapshot.write(view, size: CGSize(width: 240, height: 48), name: "pill-\(count)", to: directory)
        }
    }

    // MARK: Results' rows

    @Test func resultsRowsAreDrawnToPNGsWhenAsked() throws {
        guard let directory = ShelfSnapshot.directory else { return }
        // Nothing real: a folder and a defaults suite of this test's own, removed after.
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = "capsid-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: scratch)
            if defaults.persistentDomain(forName: suite) != nil { defaults.removePersistentDomain(forName: suite) }
        }
        let results = ResultsShelf(dependencies: .init(
            recent: { [] }, older: { _ in nil }, read: { _ in .unreadable }, isReady: { false }, open: { _ in },
            temporaryFolder: scratch.appending(path: ShelfTemporaryCopies.folderName, directoryHint: .isDirectory),
            defaults: defaults))
        let session = ReferenceModelTests.session
        let entries = [
            ArtifactEntry(version: "aaaaaaaa-0000-4000-8000-000000000041", artifact: nil, name: "z_prime_by_plate.png",
                          mime: "image/png", size: 85_000, at: Date(timeIntervalSince1970: 1_792_000_000)),
            ArtifactEntry(version: "aaaaaaaa-0000-4000-8000-000000000042", artifact: nil, name: "plate_7_heatmap.png",
                          mime: "image/png", size: 120_000, at: Date(timeIntervalSince1970: 1_792_000_000)),
            ArtifactEntry(version: "aaaaaaaa-0000-4000-8000-000000000043", artifact: nil, name: "qc_notes.md",
                          mime: "text/markdown", size: 4_100, at: Date(timeIntervalSince1970: 1_792_000_000)),
        ]
        let fake = MadeShelf()
        fake.onShelf = [entries[0].version]
        fake.adding = [entries[1].version]
        let view = VStack(spacing: 0) {
            ForEach(entries, id: \.version) { entry in
                ResultFileRow(shelf: results, onShelf: fake.access, entry: entry, session: session, problem: nil,
                              onPreview: {}, onKeep: {}, onAddToShelf: {})
                    .padding(.horizontal, 16).padding(.vertical, 4)
                Divider()
            }
            ResultFileRow(shelf: results, onShelf: fake.access, entry: entries[2], session: session,
                          problem: "Claude Science isn\u{2019}t answering.", onPreview: {}, onKeep: {}, onAddToShelf: {})
                .padding(.horizontal, 16).padding(.vertical, 4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        try ShelfSnapshot.write(view, size: CGSize(width: 640, height: 250), name: "results-rows", to: directory)
    }

    // MARK: The reference window

    /// The demo's history, with two files made on the step that made the heatmap.
    private static func referenceRows() -> (rows: [HistoryItem], notes: HistoryFile, table: HistoryFile) {
        let notes = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000051", a: "bbbbbbbb-0000-4000-8000-000000000051",
                                name: "qc_notes.md", kind: .markdown, size: 4_100)
        let table = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000052", a: "bbbbbbbb-0000-4000-8000-000000000052",
                                name: "z_prime_by_plate.csv", kind: .table, size: 1_900)
        let rows = ReferenceDemo.rows.map { item -> HistoryItem in
            guard case .steps(let i, let line, let failed, let files) = item, i == 17 else { return item }
            return .steps(i: i, line: line, failed: failed, files: files + [notes, table])
        }
        return (rows, notes, table)
    }

    /// A model landed on the demo's middle reply (history row 19), the bar chart marked.
    private static func landedModel(shelved: Set<String>, adding: Set<String> = []) async throws -> ReferenceModel {
        let (rows, _, _) = referenceRows()
        let shelf = MadeShelf()
        shelf.onShelf = shelved
        shelf.adding = adding
        let fake = FakeHistory(rows: rows)
        var dependencies = ReferenceDemo.dependencies(delay: .zero)
        dependencies.readPage = fake.dependencies.readPage
        dependencies.shelf = shelf.access
        let model = ReferenceModel(session: ReferenceDemo.session, dependencies: dependencies,
                                   gate: ReadingGate(now: { Date() }, sleep: { _ in }))
        model.open(at: 19, mark: ReferenceDemo.barChart.v)
        for _ in 0..<2_000 where model.isLanding || model.phase == .reading { try await Task.sleep(for: .milliseconds(5)) }
        for figure in model.current?.figures ?? [] {
            model.wantThumbnail(figure)
            for _ in 0..<200 where !model.thumbnails.contains(figure.v) { try await Task.sleep(for: .milliseconds(10)) }
        }
        return model
    }

    @Test func theReferenceWindowWithAShelvedFigureIsDrawnToPNGsWhenAsked() async throws {
        guard let directory = ShelfSnapshot.directory else { return }
        let (_, notes, _) = Self.referenceRows()
        let model = try await Self.landedModel(shelved: [ReferenceDemo.barChart.v, notes.v])
        #expect(model.current?.shows(version: ReferenceDemo.barChart.v) == true)
        // What opens first (the window's own size), and the whole page.
        try ShelfSnapshot.write(ReferenceView(model: model, selection: ReferenceSelection()),
                                size: ReferenceWindowController.size, name: "reference-shelved", to: directory)
        try ShelfSnapshot.write(ReferenceView(model: model, selection: ReferenceSelection()),
                                size: CGSize(width: 440, height: 960), name: "reference-shelved-full", to: directory)
        model.close()
    }

    @Test func theReferenceWindowBeforeAnythingIsShelvedIsDrawnToPNGsWhenAsked() async throws {
        guard let directory = ShelfSnapshot.directory else { return }
        let model = try await Self.landedModel(shelved: [], adding: [ReferenceDemo.heatmap.v])
        try ShelfSnapshot.write(ReferenceView(model: model, selection: ReferenceSelection()),
                                size: CGSize(width: 440, height: 960), name: "reference-unshelved-full", to: directory)
        model.close()
    }
}
