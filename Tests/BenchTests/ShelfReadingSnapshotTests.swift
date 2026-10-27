// ShelfReadingSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR` names a
// folder, draws the Shelf window while its search is still reading files (after
// 1.0.7) into it as PNGs, light and dark: a search that has found two figures by
// their names and a note by what it says, with the quiet line at the end of the
// chips ("Still reading 4 files; more may match."), at the window's first size and
// the narrowest (where the line has fewer words); the same search once reading is
// done, the line gone; a search that has found nothing so far, where the Find page's
// line says "yet" (and the same once reading is done); and a one-letter search, whose
// empty state is the Shelf's own and carries the line itself. The index reads through
// a gate the test opens by hand, so the window can be drawn half-way. The notes are
// added through `Shelf.addNote` into a temporary root; the words are made up.
// Without the variable the test does nothing. The title bar belongs to the window; a
// stand-in for it is drawn here, as in KeptWindowSnapshotTests.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct ShelfReadingSnapshotTests {
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

    private func draw(_ content: ShelfView, size: NSSize, name: String, to directory: URL, settle: Int = 10) async throws {
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

    /// Lets the index's reads through a few at a time.
    private final class Steps: @unchecked Sendable {
        private let lock = NSLock()
        private var credits = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                let go = lock.withLock { () -> Bool in
                    if credits > 0 {
                        credits -= 1
                        return true
                    }
                    waiting.append(continuation)
                    return false
                }
                if go { continuation.resume() }
            }
        }

        func allow(_ count: Int) {
            for _ in 0..<count {
                let next = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    if waiting.isEmpty {
                        credits += 1
                        return nil
                    }
                    return waiting.removeFirst()
                }
                next?.resume()
            }
        }
    }

    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000d8", projectID: "demo-Assay development",
                                       projectName: "Assay development", title: "Run notes", state: .finished, updatedAt: Date())

    /// Made-up notes whose first words say nothing of the two searches, and whose later words do.
    static let notes = [
        "Repeat the run on Thursday\n\nBring the heatmap from plate 7 and the raw reads to the group meeting.",
        "Cold room log, week 42\n\nThe incubator ran two degrees warm overnight, so every plate in it is suspect.",
        "Reagent order\n\n- fresh seal film\n- the same lot of buffer\n- a second colour scale for the heatmap",
        "Antibody dilutions\n\nStart at 1:500 and step down; the incubator needs to hold 4 \u{00B0}C.",
        "Questions for the core\n\nCan the reader export the full plate image, or only the heatmap?",
        "Draft figure legend\n\nError bars are the standard deviation of eight controls.",
        "Meeting follow-ups\n\nSend the plate map to the group, and bring the journal club slides.",
        "Notebook index\n\nWeek 42 runs are in the green binder.",
    ]

    @Test func theShelfIsDrawnWhileItsSearchIsStillReadingWhenAsked() async throws {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-reading-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        let shelf = KeptDemo.shelf(index: index, root: root)
        index.refresh()
        for _ in 0..<100 where index.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let base = index.results.count
        for text in Self.notes {
            let outcome = await shelf.addNote(ShelfSelectionNote(session: Self.session, text: try #require(ShelfSelectionNote.clean(text))))
            guard case .added = outcome else { Issue.record("\(outcome)"); return }
        }
        index.refresh()
        for _ in 0..<100 where index.results.count < base + Self.notes.count { try await Task.sleep(for: .milliseconds(50)) }
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        let size = KeptWindowController.size
        let narrow = NSSize(width: 620, height: 480)

        func model(_ steps: Steps) -> ShelfModel {
            let texts = ShelfTextIndex(publishEvery: .zero, read: { url in await steps.wait(); return try await disk.peek(url, limit: ShelfTextIndex.readLimit) })
            return ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining), textIndex: texts, announce: { _ in })
        }
        func until(_ what: String, _ condition: () -> Bool) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("Still waiting: \(what)")
            throw CancellationError()
        }

        // A search that has found two figures by their names and, in the notes read so far (they are read in the order
        // of their titles), one note by what it says; the rest is still to come.
        let steps = Steps()
        let reading = model(steps)
        reading.search = "heatmap"
        steps.allow(6)
        try await until("six files read") { reading.textIndex.texts.folded.count >= 6 }
        #expect(reading.stillReadingFiles != nil)
        try await draw(ShelfView(model: reading, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size, name: "shelf-reading", to: directory)
        try await draw(ShelfView(model: reading, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: narrow, name: "shelf-reading-small", to: directory, settle: 6)

        // Reading is done: the line is gone, and the notes that say it wear "in its text".
        steps.allow(100)
        await reading.textIndex.waitUntilRead()
        #expect(reading.stillReadingFiles == nil)
        try await draw(ShelfView(model: reading, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size, name: "shelf-reading-done", to: directory)

        // Nothing found so far, and nothing read yet: the empty state says "yet" and the line itself.
        let emptySteps = Steps()
        let empty = model(emptySteps)
        empty.search = "incubator"
        #expect(empty.searchFoundNothing && empty.stillReadingFiles != nil)
        try await draw(ShelfView(model: empty, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size, name: "shelf-reading-empty", to: directory, settle: 3)
        try await draw(ShelfView(model: empty, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: narrow, name: "shelf-reading-empty-small", to: directory, settle: 3)

        // Then reading finishes and two notes are found by what they say.
        emptySteps.allow(100)
        await empty.textIndex.waitUntilRead()
        #expect(!empty.searchFoundNothing && empty.stillReadingFiles == nil)
        try await draw(ShelfView(model: empty, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size, name: "shelf-reading-empty-done", to: directory)

        // One letter is too short for the search in sessions, so the empty state is the Shelf's own, and carries the
        // line itself, which the chips then leave out.
        let shortSteps = Steps()
        let short = model(shortSteps)
        short.search = "j"
        #expect(short.searchFoundNothing && !short.finder.isWanted && short.stillReadingFiles != nil)
        try await draw(ShelfView(model: short, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: size, name: "shelf-reading-empty-short", to: directory, settle: 3)
        try await draw(ShelfView(model: short, thumbnails: thumbnails, quickLook: KeptQuickLook()), size: narrow, name: "shelf-reading-empty-short-small", to: directory, settle: 3)
    }
}
