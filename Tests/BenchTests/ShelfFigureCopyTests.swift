// ShelfFigureCopyTests.swift — Copy on the Shelf window (Kept/ShelfView.swift,
// ShelfPicture.swift): the file goes on the pasteboard at once, and a figure's
// picture follows in the same item once the disk's queue has read it and a
// thread of its own has made it ready. Nothing about the picture is read or
// decoded on the main actor: the Kept folder can be on a share, and the file
// up to 8 MB. Every test copies to a private pasteboard, never the general one.
import AppKit
import Foundation
import Testing
@testable import Bench

/// The disk's calls, held back as a slow share holds them and let go late, and the threads they ran on.
private final class HeldDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [KeptDisk.Work] = []
    private var hold = false
    private var started: [Bool] = []

    /// While `on`, a call is kept and not started; turning it off starts the ones kept, on the disk's queue.
    func holding(_ on: Bool) {
        let release: [KeptDisk.Work] = lock.withLock {
            hold = on
            guard !on else { return [] }
            defer { held = [] }
            return held
        }
        for work in release { KeptDisk.runOnDisk(work) }
    }

    /// How many calls were made (held or run), and whether any ran on the main thread.
    var calls: Int { lock.withLock { started.count + held.count } }
    var ranOnMain: Bool { lock.withLock { started.contains(true) } }

    func run(_ work: @escaping KeptDisk.Work) {
        let counted: KeptDisk.Work = { [self] in
            lock.withLock { started.append(Thread.isMainThread) }
            work()
        }
        let kept = lock.withLock { () -> Bool in
            guard hold else { return false }
            held.append(counted)
            return true
        }
        if !kept { KeptDisk.runOnDisk(counted) }
    }
}

private func bitmap(_ type: NSBitmapImageRep.FileType, width: Int = 6, height: Int = 4) throws -> Data {
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return try #require(rep.representation(using: type, properties: [:]))
}

@MainActor
struct ShelfFigureCopyTests {
    private let when = Date(timeIntervalSince1970: 1_792_674_720)

    /// A Kept folder in a scratch folder, a disk over it and a private pasteboard, all gone after.
    private func scratch(_ body: (_ root: URL, _ disk: HeldDisk, _ kept: KeptDisk, _ board: NSPasteboard) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-copy-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = folder.appending(path: "Kept", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Assay development/z_prime", directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
        let board = NSPasteboard(name: NSPasteboard.Name("capsid-tests-copy-\(UUID().uuidString)"))
        defer {
            try? FileManager.default.removeItem(at: folder)
            board.releaseGlobally()
        }
        let disk = HeldDisk()
        try await body(root, disk, KeptDisk(root: { root }, run: { disk.run($0) }), board)
    }

    /// The item for a file in the made-up folder, written there with these bytes (none for a file that isn't there).
    private func item(_ file: String, bytes: Data?, in root: URL) throws -> ShelfItem {
        let folder = root.appending(path: "Assay development/z_prime", directoryHint: .isDirectory)
        if let bytes { try bytes.write(to: folder.appending(path: file, directoryHint: .notDirectory)) }
        let record = KeptRecord(
            name: "z_prime", keptAt: when, projectID: "p", projectName: "Assay development", sessionID: "s", sessionTitle: "Plate reader QC",
            figure: KeptFile(path: file, role: .figure, artifact: "a", version: "v-1", index: 1, of: nil, sha256: nil, bytes: bytes?.count ?? 0),
            files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
        let result = KeptResult(folder: folder, collection: "Assay development", record: record,
                                text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
        return ShelfItem(result: result, others: [])
    }

    private func files(on board: NSPasteboard) -> [URL] {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    @Test func aFigureIsTheFileAtOnceAndThePictureOnceTheDiskHasReadIt() async throws {
        try await scratch { root, disk, kept, board in
            let png = try bitmap(.png)
            let figure = try item("z_prime.png", bytes: png, in: root)
            disk.holding(true)
            let picture = ShelfActions.copy(figure, disk: kept, to: board)
            // The disk has not answered: the file is there, the picture is not, and nothing waited for it.
            #expect(files(on: board).map(\.lastPathComponent) == ["z_prime.png"])
            #expect(board.data(forType: .png) == nil)
            disk.holding(false)
            await picture.value
            // The same bytes, in the same item as the file, and read off the main thread.
            #expect(board.data(forType: .png) == png)
            #expect(board.pasteboardItems?.count == 1)
            #expect(files(on: board).map(\.lastPathComponent) == ["z_prime.png"])
            #expect(disk.calls == 1 && !disk.ranOnMain)
        }
    }

    @Test func aPictureOfAnotherKindIsMadeAPNGOffTheMainActor() async throws {
        try await scratch { root, disk, kept, board in
            let jpeg = try bitmap(.jpeg, width: 8, height: 5)
            await ShelfActions.copy(try item("plot.jpg", bytes: jpeg, in: root), disk: kept, to: board).value
            let made = try #require(board.data(forType: .png))
            let rep = try #require(NSBitmapImageRep(data: made))
            #expect(rep.pixelsWide == 8 && rep.pixelsHigh == 5)
            #expect(board.data(forType: NSPasteboard.PasteboardType("public.jpeg")) == nil, "one picture, the PNG that every editor takes")
            #expect(!disk.ranOnMain)

            // The converter on its own, here and off the main actor: a TIFF too.
            let tiff = try bitmap(.tiff, width: 3, height: 3)
            let flavor = try #require(await ShelfPicture.flavor(of: tiff, fileName: "scan.tif"))
            #expect(flavor.type == .png && NSBitmapImageRep(data: flavor.data)?.pixelsWide == 3)
        }
    }

    @Test func anSVGGoesOnAsSVGAndAFileThatIsNoPictureGetsNone() async throws {
        try await scratch { root, _, kept, board in
            let svg = Data(#"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>"#.utf8)
            await ShelfActions.copy(try item("plot.svg", bytes: svg, in: root), disk: kept, to: board).value
            #expect(board.data(forType: ShelfPicture.svgType) == svg)
            #expect(board.data(forType: .png) == nil)

            // Named like a picture, but not one: the file alone is copied.
            await ShelfActions.copy(try item("broken.png", bytes: Data("not a picture".utf8), in: root), disk: kept, to: board).value
            #expect(files(on: board).map(\.lastPathComponent) == ["broken.png"])
            #expect(board.data(forType: .png) == nil && board.data(forType: ShelfPicture.svgType) == nil)
            await ShelfActions.copy(try item("fake.svg", bytes: Data("plain words".utf8), in: root), disk: kept, to: board).value
            #expect(board.data(forType: ShelfPicture.svgType) == nil)

            // A figure whose file is gone: the file's address is still copied, and nothing fails.
            await ShelfActions.copy(try item("gone.png", bytes: nil, in: root), disk: kept, to: board).value
            #expect(files(on: board).map(\.lastPathComponent) == ["gone.png"])
            #expect(board.data(forType: .png) == nil)
        }
    }

    @Test func aDocumentIsOnlyTheFileAndTheDiskIsNeverAsked() async throws {
        try await scratch { root, disk, kept, board in
            let notes = try item("qc_notes.md", bytes: Data("# Plate 7".utf8), in: root)
            #expect(notes.kind == .document)
            await ShelfActions.copy(notes, disk: kept, to: board).value
            #expect(files(on: board).map(\.lastPathComponent) == ["qc_notes.md"])
            #expect(board.types?.contains(.png) != true)
            #expect(disk.calls == 0)
        }
    }

    @Test func aPictureThatArrivesAfterSomethingElseWasCopiedIsNotAdded() async throws {
        try await scratch { root, disk, kept, board in
            let figure = try item("z_prime.png", bytes: try bitmap(.png), in: root)
            disk.holding(true)
            let picture = ShelfActions.copy(figure, disk: kept, to: board)
            // Meanwhile, in another app.
            board.clearContents()
            board.setString("pH 7.4", forType: .string)
            disk.holding(false)
            await picture.value
            #expect(board.string(forType: .string) == "pH 7.4")
            #expect(board.data(forType: .png) == nil)
            #expect(files(on: board).isEmpty)
        }
    }

    @Test func theDiskReadsAFileWholeUpToTheLimitAndOnlyInsideTheKeptFolder() async throws {
        try await scratch { root, _, kept, _ in
            let folder = root.appending(path: "Assay development/z_prime", directoryHint: .isDirectory)
            let file = folder.appending(path: "a.png", directoryHint: .notDirectory)
            let bytes = Data(repeating: 7, count: 100)
            try bytes.write(to: file)
            #expect(try await kept.pictureBytes(file, limit: 100) == bytes, "exactly the limit")
            #expect(try await kept.pictureBytes(file, limit: 99) == nil, "one byte over")
            try Data().write(to: file)
            #expect(try await kept.pictureBytes(file) == nil, "an empty file")
            let outside = folder.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "outside.png", directoryHint: .notDirectory)
            try bytes.write(to: outside)
            #expect(try await kept.pictureBytes(outside) == nil, "a file outside the Kept folder")
            #expect(try await kept.pictureBytes(folder.appending(path: "missing.png", directoryHint: .notDirectory)) == nil)
        }
    }

    /// Nothing in the view reads a picture itself: the copy goes through the disk and the converter.
    @Test func theWindowCopiesThroughTheDiskAndNeverReadsAPictureItself() throws {
        let kept = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Bench/Kept", directoryHint: .isDirectory)
        let view = try String(contentsOf: kept.appending(path: "ShelfView.swift", directoryHint: .notDirectory), encoding: .utf8)
        #expect(!view.contains("NSImage("))
        #expect(view.components(separatedBy: "ShelfActions.copy(item, disk: model.index.disk)").count == 3, "the button and the context menu")
    }
}
