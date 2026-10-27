// ShelfDocumentReadingTests.swift — bounded reads, Markdown/plain text, cache invalidation and late completions.
import AppKit
import Foundation
import Testing
@testable import Bench

private func document(_ name: String = "qc_notes.md", in root: URL = URL(fileURLWithPath: "/tmp/capsid-document-reading"),
                      version: String? = "v-1") -> ShelfItem {
    let record = KeptRecord(name: name, keptAt: Date(timeIntervalSince1970: 1_792_674_720), projectID: "p",
                            projectName: "Assay development", sessionID: "s", sessionTitle: "Plate reader QC",
                            figure: KeptFile(path: name, role: .figure, artifact: nil, version: version, index: nil, of: nil,
                                             sha256: nil, bytes: 100), files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0.6")
    return ShelfItem(result: KeptResult(folder: root.appendingPathComponent(name + "-folder"), collection: "Assay development",
                                        record: record, text: KeptText(legend: "", claudeSaid: "The checks are complete.",
                                                                      attribution: "", origin: "")), others: [])
}

private final class DocumentFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (String?, KeptFileFacts)] = [:]
    private var count = 0
    var reads: Int { lock.withLock { count } }
    func set(_ item: ShelfItem, _ text: String?, date: Double = 1, size: Int? = nil, putAway: Bool = false) {
        lock.withLock {
            files[item.fileURL.path] = (text, KeptFileFacts(modified: Date(timeIntervalSince1970: date),
                                                          size: size ?? text?.utf8.count ?? 0, putAway: putAway))
        }
    }
    func facts(_ url: URL) -> KeptFileFacts? { lock.withLock { files[url.path]?.1 } }
    func read(_ url: URL) -> String? { lock.withLock { count += 1; return files[url.path]?.0 } }
}

struct ShelfDocumentReadingRulesTests {
    @Test func onlyOrdinarySupportedProseUsesTheReadingCard() {
        for name in ["qc_notes.md", "qc_notes.MARKDOWN", "qc_notes.txt", "qc_notes.text", "qc_notes.rst", "note.md"] {
            #expect(ShelfDocumentReading.accepts(document(name)))
        }
        for name in ["z_prime.png", "qc_notes.pdf", "qc_notes.html", "qc_data.csv", "qc_data.xlsx"] {
            #expect(!ShelfDocumentReading.accepts(document(name)))
        }
        #expect(!ShelfDocumentReading.accepts(document("note.md", version: nil)))
    }

    @Test func markdownIsRenderedAndPlainTextKeepsItsMarks() throws {
        let source = "# Plate reader QC\n\n**Repeat plate 7.**"
        let rendered = ShelfDocumentReading.render(source, markdown: true).text
        #expect(rendered.string.contains("Plate reader QC") && !rendered.string.contains("#"))
        #expect(!rendered.string.contains("**"))
        let index = (rendered.string as NSString).range(of: "Repeat").location
        let font = try #require(rendered.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font.pointSize == 14)
        let plain = ShelfDocumentReading.render(source, markdown: false).text
        #expect(plain.string == source)
        #expect((plain.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 14)
    }

    @Test @MainActor func missingDocumentsFallBackAndFiguresAndTablesKeepTheirLayout() {
        let prose = document()
        for state in [ShelfDocumentReadings.Reading.notYet, .ready] {
            #expect(ShelfDetail.form(for: prose, reading: .none, document: state) == .document)
            for name in ["z_prime.png", "qc_data.csv", "qc_data.xlsx", "qc_notes.pdf"] {
                #expect(ShelfDetail.form(for: document(name), reading: .none, document: state) == .ordinary)
            }
        }
        #expect(ShelfDetail.form(for: prose, reading: .none, document: .none) == .ordinary)
        #expect(ShelfRules.moreMenu(canKeep: true, document: true)
                == [.quickLook, .showInFinder, .divider, .keepWithDataAndCode, .openAsReference, .exportPDF, .divider, .remove])
        #expect(ShelfRules.documentHeaderParts(for: prose).prefix(3) == ["qc_notes.md", "Plate reader QC", "Assay development"])
        #expect(ShelfDetail.documentHeight(forCard: 480 * 0.56) + 160 <= 480 * 0.56 + 1)
    }
}

@MainActor
struct ShelfDocumentReadingCacheTests {
    private func store(_ files: DocumentFiles) -> ShelfDocumentReadings {
        ShelfDocumentReadings(inspect: { files.facts($0) }, read: { files.read($0) })
    }

    @Test func anUnchangedFileIsReadOnceAndAnEditInvalidatesIt() async {
        let item = document(), files = DocumentFiles()
        files.set(item, "# Original")
        let cache = store(files)
        #expect(cache.reading(for: item) == .notYet)
        await cache.look(at: item)
        let first = cache.document(for: item)?.text
        await cache.look(at: item)
        #expect(files.reads == 1)
        #expect(cache.document(for: item)?.text === first)
        files.set(item, "# Changed", date: 2)
        await cache.look(at: item)
        #expect(files.reads == 2)
        #expect(cache.document(for: item)?.text.string == "Changed")
    }

    @Test func gonePutAwayOversizedEmptyAndBinaryFilesUseThePreview() async {
        let item = document(), files = DocumentFiles()
        let cache = store(files)
        await cache.look(at: item)
        #expect(cache.reading(for: item) == .none)
        files.set(item, "Words", putAway: true)
        await cache.look(at: item)
        files.set(item, "Words", size: ShelfDocumentReading.byteLimit + 1)
        await cache.look(at: item)
        #expect(files.reads == 0, "offloaded and oversized files are not read")
        files.set(item, "Words")
        await cache.look(at: item)
        #expect(cache.reading(for: item) == .ready)
        for text in [" \n ", "a\0b", String(repeating: "x", count: ShelfDocumentReading.byteLimit + 1)] {
            files.set(item, text, date: 2, size: 1)
            await cache.look(at: item)
            #expect(cache.reading(for: item) == .none)
            #expect(cache.document(for: item) == nil)
        }
    }

    @Test func aReadFailureDropsOldWordsAndTheNextLookCanRecover() async {
        let item = document(), files = DocumentFiles()
        files.set(item, "Original")
        var fail = false
        let cache = ShelfDocumentReadings(inspect: { files.facts($0) }, read: { url in
            if fail { throw CocoaError(.fileReadUnknown) }
            return files.read(url)
        })
        await cache.look(at: item)
        files.set(item, "Changed", date: 2)
        fail = true
        await cache.look(at: item)
        #expect(cache.reading(for: item) == .none)
        fail = false
        await cache.look(at: item)
        #expect(cache.document(for: item)?.text.string == "Changed")
    }

    @Test func onlyFourDocumentsAreHeldAndCacheHitsCountAsRecent() async {
        let files = DocumentFiles(), cache = store(files)
        let items = (0...ShelfDocumentReadings.kept).map { document("qc_notes_\($0).txt") }
        for item in items { files.set(item, "Plate reader QC") }
        for item in items.dropLast() { await cache.look(at: item) }
        await cache.look(at: items[0])
        await cache.look(at: items.last!)
        #expect(cache.reading(for: items[0]) == .ready)
        #expect(cache.reading(for: items[1]) == .notYet)
        #expect(items.filter { cache.document(for: $0) != nil }.count == ShelfDocumentReadings.kept)
        #expect(files.reads == items.count)
    }

    @Test func realDiskReadsAreBoundedAndPreservePlainText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-document-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let item = document("qc_notes.txt", in: root)
        try FileManager.default.createDirectory(at: item.folder, withIntermediateDirectories: true)
        let cache = ShelfDocumentReadings(disk: KeptDisk(root: { root }))
        try Data("\u{FEFF}# Literal\r\n**Plain text**".utf8).write(to: item.fileURL)
        await cache.look(at: item)
        #expect(cache.document(for: item)?.text.string == "# Literal\n**Plain text**")
        try Data(repeating: 120, count: ShelfDocumentReading.byteLimit + 1).write(to: item.fileURL)
        await cache.look(at: item)
        #expect(cache.reading(for: item) == .none)
        try Data([0xff, 0xfe, 0xff]).write(to: item.fileURL)
        await cache.look(at: item)
        #expect(cache.reading(for: item) == .none)
    }
}

@MainActor
private final class DocumentReadGate {
    var held: CheckedContinuation<String?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var calls = 0
    func read() async -> String? {
        calls += 1
        if calls > 1 { return "New words" }
        return await withCheckedContinuation { continuation in
            held = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { held?.resume(returning: "Old words"); held = nil }
}

@MainActor
struct ShelfDocumentReadingRaceTests {
    @Test func aLateReadCannotReplaceANewerRead() async {
        let item = document(), files = DocumentFiles(), gate = DocumentReadGate()
        files.set(item, "Old words")
        let cache = ShelfDocumentReadings(inspect: { files.facts($0) }, read: { _ in await gate.read() })
        let first = Task { await cache.look(at: item) }
        await gate.waitUntilHeld()
        // Same date and size: request ownership must still reject the first read, independent of the file stamp.
        files.set(item, "New words")
        await cache.look(at: item)
        gate.release()
        await first.value
        #expect(cache.document(for: item)?.text.string == "New words")
    }

    @Test func aCancelledReadDoesNotPublish() async {
        let item = document(), files = DocumentFiles(), gate = DocumentReadGate()
        files.set(item, "Old words")
        let cache = ShelfDocumentReadings(inspect: { files.facts($0) }, read: { _ in await gate.read() })
        let pending = Task { await cache.look(at: item) }
        await gate.waitUntilHeld()
        pending.cancel()
        gate.release()
        await pending.value
        #expect(cache.reading(for: item) == .notYet)
    }

    @Test func aFileChangedDuringTheReadIsNotPublished() async {
        let item = document(), files = DocumentFiles(), gate = DocumentReadGate()
        files.set(item, "Old words")
        let cache = ShelfDocumentReadings(inspect: { files.facts($0) }, read: { _ in await gate.read() })
        let pending = Task { await cache.look(at: item) }
        await gate.waitUntilHeld()
        files.set(item, "New words", date: 2)
        gate.release()
        await pending.value
        #expect(cache.reading(for: item) == .none)
        await cache.look(at: item)
        #expect(cache.document(for: item)?.text.string == "New words")
    }
}
