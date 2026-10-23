// ReferenceFilesSnapshotTests.swift — not a check: when `CAPSID_SNAPSHOT_DIR`
// names a folder, draws the reference window's content with what the reply
// made (DESIGN.md, Reference) into it as PNGs, light and dark, at the window's
// width: the reply with its figures and its documents listed, a figure and a
// document being opened (and one that couldn't be), a Markdown document open
// in the reading view, and one that was cut. Without it the test does nothing.
// The toolbar belongs to the window and is not drawn here.
import AppKit
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct ReferenceFilesSnapshotTests {
    private static func directory() throws -> URL? {
        guard let path = ProcessInfo.processInfo.environment["CAPSID_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The demo's window on its middle reply, with its two figures drawn.
    private static func model(_ adjust: (inout ReferenceDependencies) -> Void = { _ in }) async throws -> ReferenceModel {
        var dependencies = ReferenceDemo.dependencies(delay: .zero)
        adjust(&dependencies)
        let gate = ReadingGate(now: { Date() }, sleep: { _ in })
        let model = ReferenceModel(session: ReferenceDemo.session, dependencies: dependencies, gate: gate)
        model.open()
        for _ in 0..<100 where model.phase == .reading { try await Task.sleep(for: .milliseconds(20)) }
        model.earlier()
        for _ in 0..<100 where model.phase == .reading { try await Task.sleep(for: .milliseconds(20)) }
        for figure in model.current?.figures ?? [] {
            model.wantThumbnail(figure)
            for _ in 0..<100 where !model.thumbnails.contains(figure.v) { try await Task.sleep(for: .milliseconds(20)) }
        }
        return model
    }

    /// `height` is the window's, 620 as it opens, or taller to see the whole page.
    private static func draw(_ model: ReferenceModel, as name: String, into directory: URL,
                             height: CGFloat = ReferenceWindowController.size.height) throws {
        for dark in [false, true] {
            let host = NSHostingView(rootView: ReferenceView(model: model, selection: ReferenceSelection()))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = NSSize(width: ReferenceWindowController.size.width, height: height)
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

    @Test func theReplyWithItsDocumentsListedIsDrawnWhenAsked() async throws {
        guard let directory = try Self.directory() else { return }
        let shelf = MadeShelf()
        shelf.onShelf = [ReferenceDemo.table.v]
        let model = try await Self.model { $0.shelf = shelf.access }
        // As the window opens, and the whole page (taller than the window).
        try Self.draw(model, as: "reference-documents", into: directory)
        try Self.draw(model, as: "reference-documents-tall", into: directory, height: 1_000)
        model.close()
    }

    @Test func aFigureBeingOpenedAndOneThatCouldntBeAreDrawnWhenAsked() async throws {
        guard let directory = try Self.directory() else { return }
        let model = try await Self.model { dependencies in
            dependencies.download = { version in
                switch version {
                case ReferenceDemo.barChart.v, ReferenceDemo.table.v:
                    // Reading: the spinner stays until the window closes.
                    try? await Task.sleep(for: .seconds(600))
                    return .cancelled
                default:
                    return .failed(.timedOut)
                }
            }
        }
        // One at a time, through the gate: the one that fails first, then two that wait.
        model.openFile(ReferenceDemo.heatmap)
        for _ in 0..<100 where model.files.problems[ReferenceDemo.heatmap.v] == nil { try await Task.sleep(for: .milliseconds(20)) }
        model.openFile(ReferenceDemo.barChart)
        model.openFile(ReferenceDemo.table)
        try Self.draw(model, as: "reference-opening", into: directory, height: 1_000)
        model.close()
    }

    @Test func aMarkdownDocumentOpenInTheReadingViewIsDrawnWhenAsked() async throws {
        guard let directory = try Self.directory() else { return }
        let shelf = MadeShelf()
        let model = try await Self.model { $0.shelf = shelf.access }
        model.openFile(ReferenceDemo.notes)
        for _ in 0..<100 where model.files.document == nil { try await Task.sleep(for: .milliseconds(20)) }
        try Self.draw(model, as: "reference-document", into: directory)
        // The same document on the shelf, and one that was cut.
        shelf.onShelf = [ReferenceDemo.notes.v]
        shelf.changes.send()
        if let document = model.files.document {
            model.files.show(ReferenceDocument(file: document.file, rendered: document.rendered, cut: true, isEmpty: false))
        }
        try await Task.sleep(for: .milliseconds(50))
        try Self.draw(model, as: "reference-document-cut", into: directory, height: 1_200)
        model.close()
    }
}
