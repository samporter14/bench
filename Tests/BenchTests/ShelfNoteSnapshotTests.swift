// ShelfNoteSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the Shelf window with notes on it (words selected in a
// conversation and shelved, Kept/ShelfSelectionNote.swift) into it as PNGs,
// light and dark, so they can be looked at without opening a window: the note
// as a card among the demo's made-up items, with its detail below; the
// Documents chip with a second, shorter note selected; and the narrowest window.
// The notes are added through `Shelf.addNote` into a temporary root, so the
// folders on screen are the ones a real add writes. A second test draws the
// passage on a note's detail card (since 1.0.6): a short note's, a long one's that
// scrolls, and both in the narrowest window. Without the variable the
// test does nothing. The title bar belongs to the window; a stand-in for it is
// drawn here, as in KeptWindowSnapshotTests.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct ShelfNoteSnapshotTests {
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

    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000d8", projectID: "demo-Assay development",
                                       projectName: "Assay development", title: "Plate reader QC", state: .finished, updatedAt: Date())
    static let long = """
        Plate 7 drifts after the midpoint, and the edge wells run low.

        The cutoff is 0.5; plate 7 sits at 0.41, while the other eleven sit between 0.62 and 0.78. Repeat it with a fresh seal before anyone reads the other columns.
        """
    static let short = "## Repeat plate 7\n- a fresh seal\n- the same lot of buffer\n- read at 37 \u{00B0}C"

    @Test func theShelfWithNotesIsDrawnToPNGsWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-note-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        for text in [Self.long, Self.short] {
            let outcome = await shelf.addNote(ShelfSelectionNote(session: Self.session, text: try #require(ShelfSelectionNote.clean(text))))
            guard case .added = outcome else { Issue.record("\(outcome)"); return }
        }
        index.refresh()
        for _ in 0..<100 where index.results.count < 11 { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let size = KeptWindowController.size

        // The note among the shelf's other cards, selected: its detail below.
        let model = ShelfModel(shelf: shelf)
        let note = try #require(model.items.first { $0.title.hasPrefix("Plate 7 drifts after") })
        #expect(note.kind == .document && note.version == nil)
        model.selection = note.id
        try await draw(ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-note", to: directory)

        // The Documents chip, with the shorter note selected.
        let documents = ShelfModel(shelf: shelf)
        documents.kind = .document
        documents.selection = documents.items.first { $0.title.hasPrefix("Repeat plate 7") }?.id
        try await draw(ShelfView(model: documents, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size,
                       name: "shelf-note-documents", to: directory)

        // The narrowest window.
        try await draw(ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: NSSize(width: 620, height: 480),
                       name: "shelf-note-small", to: directory, settle: 8)
    }

    /// Ten made-up findings from one plate run: more than the card shows at once, so it scrolls.
    static let passage: String = {
        let findings = [
            "Plate 7 drifts after the midpoint, and the edge wells run low.",
            "The cutoff is 0.5; plate 7 sits at 0.41, while the other eleven sit between 0.62 and 0.78.",
            "Columns 1 and 12 read about 8% below the middle of the plate on every run since the seal changed.",
            "The positive control wells agree to within 3%, so the reader is steady; the drift is in the plate.",
            "Repeat it with a fresh seal before anyone reads the other columns.",
            "Keep the same lot of buffer, read at 37 \u{00B0}C, and note the time between the last dispense and the first read.",
            "If the edge wells still run low, move the assay to the inner 60 wells and call the rest blanks.",
            "Before the repeat, check that the plate sealer's pressure has not drifted: the service log shows it was last set in the spring.",
            "Ask the group whether anyone has seen the same edge effect with the other plate brand, and share the three plates' raw reads.",
            "Z' alone does not tell the whole story here: the signal window narrows at the edges even when the controls are tidy.",
        ]
        return findings.joined(separator: "\n\n")
    }()

    @Test func theShelfShowsANotesPassageOnItsDetailCardWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-passage-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        for text in [Self.passage, Self.short] {
            let outcome = await shelf.addNote(ShelfSelectionNote(session: Self.session, text: try #require(ShelfSelectionNote.clean(text))))
            guard case .added = outcome else { Issue.record("\(outcome)"); return }
        }
        index.refresh()
        for _ in 0..<100 where index.results.count < 11 { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let size = KeptWindowController.size
        let narrow = NSSize(width: 620, height: 480)

        for (title, name) in [("Repeat plate 7", "shelf-passage-short"), ("Plate 7 drifts after", "shelf-passage-long")] {
            let model = ShelfModel(shelf: shelf)
            let note = try #require(model.items.first { $0.title.hasPrefix(title) })
            #expect(note.isSelectionNote)
            model.selection = note.id
            try await draw(ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size, name: name, to: directory)
            try await draw(ShelfView(model: model, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: narrow,
                           name: "\(name)-small", to: directory, settle: 8)
            #expect(model.passages.text(for: note) != nil, "the card asked for the words and they were read")
        }
    }
}
