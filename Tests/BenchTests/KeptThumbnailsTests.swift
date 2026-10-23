// KeptThumbnailsTests.swift — the pictures of kept files (Kept/KeptThumbnails.swift)
// on a made-up disk and a made-up Quick Look: that a file put on the shelf
// under the name of one taken off is drawn afresh and not shown as the old one,
// that a picture is drawn once for each state of a file, and that a file iCloud
// has put away is never asked for a picture. Nothing is drawn by the system.
import AppKit
import Foundation
import Testing
@testable import Bench

/// The files' facts and Quick Look, made up: a file's facts are set by the test,
/// and each picture drawn is one pixel wider than the last, so which one a card
/// shows can be told by its width.
private final class MadeDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: KeptThumbnails.FileFacts] = [:]
    private var made = 0

    func set(_ url: URL, modified: Double, size: Int = 100, putAway: Bool = false) {
        lock.withLock { files[url.path] = .init(modified: Date(timeIntervalSince1970: modified), size: size, putAway: putAway) }
    }

    func remove(_ url: URL) { lock.withLock { files[url.path] = nil } }

    func inspect(_ url: URL) -> KeptThumbnails.FileFacts? { lock.withLock { files[url.path] } }

    /// Pictures drawn so far.
    var pictures: Int { lock.withLock { made } }

    func draw(_ url: URL, _ side: CGFloat, _ scale: CGFloat) async -> CGImage? {
        let width = lock.withLock { () -> Int in made += 1; return made }
        let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }
}

@MainActor
private func thumbnails(_ disk: MadeDisk, peek: (@MainActor (URL) async -> String?)? = nil) -> KeptThumbnails {
    KeptThumbnails(peek: peek, inspect: { disk.inspect($0) }, generate: { await disk.draw($0, $1, $2) })
}

@MainActor
private func until(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<600 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw CancellationError()
}

/// Lets what was asked finish, and anything it wrongly started.
@MainActor
private func settle() async throws {
    for _ in 0..<40 { await Task.yield() }
    try await Task.sleep(for: .milliseconds(60))
}

private let file = URL(fileURLWithPath: "/tmp/kept/Assay development/z_prime/z_prime.png")

@MainActor
struct KeptThumbnailsTests {
    @Test func aFileOfTheSameNameAddedAgainIsDrawnAfreshNotShownAsTheOldOne() async throws {
        let disk = MadeDisk()
        let store = thumbnails(disk)
        disk.set(file, modified: 1_000)
        store.want(file, side: 160, scale: 2)
        try await until("the first picture") { store.image(for: file, side: 160) != nil }
        #expect(store.image(for: file, side: 160)?.width == 1)

        // The item is taken off the shelf and another file of the same name is put on:
        // the card appears again and asks again.
        disk.set(file, modified: 2_000, size: 120)
        store.want(file, side: 160, scale: 2)
        try await until("the new picture") { store.image(for: file, side: 160)?.width == 2 }
        #expect(disk.pictures == 2)
        // Both sides of the file are the new file's: a larger picture of it is drawn from it too.
        store.want(file, side: 320, scale: 2)
        try await until("the large picture") { store.image(for: file, side: 320) != nil }
        #expect(store.image(for: file, side: 320)?.width == 3)
    }

    @Test func aFileTheSameSizeButWrittenLaterIsAnotherFile() async throws {
        let disk = MadeDisk()
        let store = thumbnails(disk)
        disk.set(file, modified: 1_000, size: 100)
        store.want(file, side: 160, scale: 2)
        try await until("the first picture") { store.image(for: file, side: 160) != nil }
        disk.set(file, modified: 1_001, size: 100)
        store.want(file, side: 160, scale: 2)
        try await until("the new picture") { store.image(for: file, side: 160)?.width == 2 }
    }

    @Test func aPictureIsDrawnOnceForEachStateOfTheFile() async throws {
        let disk = MadeDisk()
        let store = thumbnails(disk)
        disk.set(file, modified: 1_000)
        for _ in 0..<5 {
            store.want(file, side: 160, scale: 2)
            try await Task.sleep(for: .milliseconds(10))
        }
        try await until("the picture") { store.image(for: file, side: 160) != nil }
        try await settle()
        // Scrolling the card in and out of view asks again; the file is the same.
        store.want(file, side: 160, scale: 2)
        try await settle()
        #expect(disk.pictures == 1)
    }

    @Test func aFileICloudHasPutAwayIsNeverAskedForAPicture() async throws {
        let disk = MadeDisk()
        let store = thumbnails(disk)
        disk.set(file, modified: 1_000, putAway: true)
        store.want(file, side: 160, scale: 2)
        store.want(file, side: 36, scale: 2)
        try await settle()
        // No picture was drawn (asking Quick Look would bring the file back): its kind's symbol shows.
        #expect(disk.pictures == 0)
        #expect(store.image(for: file, side: 160) == nil && store.image(for: file, side: 36) == nil)

        // Once it is back on this Mac, it is drawn.
        disk.set(file, modified: 1_000, putAway: false)
        store.want(file, side: 160, scale: 2)
        try await until("the picture") { store.image(for: file, side: 160) != nil }
        #expect(disk.pictures == 1)
    }

    @Test func aTextFileOfTheSameNameAddedAgainIsReadAgain() async throws {
        let disk = MadeDisk()
        let note = URL(fileURLWithPath: "/tmp/kept/Assay development/qc_notes/qc_notes.md")
        var text = "# First notes\n\nPlate 7 is low."
        let store = thumbnails(disk, peek: { _ in text })
        disk.set(note, modified: 1_000)
        #expect(store.usesPeek(note))
        store.wantPeek(note)
        try await until("the first text") { store.peek(for: note) != nil }
        #expect(store.peek(for: note) == .document(title: "First notes", paragraphs: ["Plate 7 is low."]))

        // The same file again: not read twice.
        store.wantPeek(note)
        try await settle()
        #expect(store.peek(for: note) == .document(title: "First notes", paragraphs: ["Plate 7 is low."]))

        // Another file of the same name.
        text = "# Second notes\n\nPlate 9 is the low one."
        disk.set(note, modified: 2_000, size: 150)
        store.wantPeek(note)
        try await until("the new text") { store.peek(for: note) == .document(title: "Second notes", paragraphs: ["Plate 9 is the low one."]) }
    }

    @Test func aTextFileICloudHasPutAwayIsNotReadAndGoesToTheSymbol() async throws {
        let disk = MadeDisk()
        let note = URL(fileURLWithPath: "/tmp/kept/Assay development/qc_notes/qc_notes.md")
        var asked = 0
        let store = thumbnails(disk, peek: { _ in asked += 1; return "# Notes" })
        disk.set(note, modified: 1_000, putAway: true)
        store.wantPeek(note)
        try await settle()
        #expect(asked == 0)
        #expect(store.peek(for: note) == nil)
        // The card falls back to the picture path, which does not draw it either.
        #expect(!store.usesPeek(note))
        store.want(note, side: 160, scale: 2)
        try await settle()
        #expect(disk.pictures == 0)
    }

    @Test func closingTheWindowLetsEverythingGo() async throws {
        let disk = MadeDisk()
        let store = thumbnails(disk)
        disk.set(file, modified: 1_000)
        store.want(file, side: 160, scale: 2)
        try await until("the picture") { store.image(for: file, side: 160) != nil }
        store.removeAll()
        #expect(store.image(for: file, side: 160) == nil)
        store.want(file, side: 160, scale: 2)
        try await until("the picture again") { store.image(for: file, side: 160) != nil }
        #expect(disk.pictures == 2)
    }
}

struct KeptFileFactsTests {
    @Test func aRealFileIsToldByItsDateAndSizeAndIsNotPutAway() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-thumbs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "z.png", directoryHint: .notDirectory)
        try Data("first".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: url.path)
        let first = try #require(await KeptThumbnails.inspectFile(url))
        #expect(first.size == 5 && !first.putAway)
        #expect(first.modified == Date(timeIntervalSince1970: 1_000_000_000))

        try Data("second one".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_500)], ofItemAtPath: url.path)
        let second = try #require(await KeptThumbnails.inspectFile(url))
        #expect(second.stamp != first.stamp && second.size == 10 && !second.putAway)
        #expect(await KeptThumbnails.inspectFile(folder.appending(path: "gone.png", directoryHint: .notDirectory)) == nil)
    }
}
