// ShelfPassageTests.swift — a note's detail card shows its whole passage and Copy
// copies it (Kept/ShelfPassage.swift, ShelfView.swift; since 1.0.6). A note is the
// file `note.md` with no version of its own, as `Shelf.addNote` makes it; its
// passage is that file as `ShelfSelectionNote.clean` leaves it, short or at the
// 32,000-character limit; an ordinary document, even one called `note.md` that
// has a version, is not a note and is neither read nor changed. The words are read
// through the disk layer, off the main actor, once for each state of the file, and
// copied as text. Made-up files for the rules, a real `KeptDisk` on a folder made
// for each test for the rest, and a private pasteboard, never the general one.
import AppKit
import Foundation
import Testing
@testable import Bench

private let root = URL(fileURLWithPath: "/tmp/kept-passage", isDirectory: true)
private let when = Date(timeIntervalSince1970: 1_792_674_720)

private func result(_ file: String, folder: String, version: String? = nil, in parent: URL = root) -> KeptResult {
    let record = KeptRecord(
        name: folder, keptAt: when, projectID: "p", projectName: "Assay development", sessionID: "s", sessionTitle: "Plate reader QC",
        figure: KeptFile(path: file, role: .figure, artifact: nil, version: version, index: nil, of: nil, sha256: nil, bytes: 10),
        files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
    return KeptResult(folder: parent.appending(path: "Assay development/\(folder)", directoryHint: .isDirectory), collection: "Assay development",
                      record: record, text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
}

private func note(_ folder: String = "Plate 7 drifts", in parent: URL = root) -> ShelfItem {
    ShelfRules.items(from: [result("note.md", folder: folder, in: parent)])[0]
}

/// Files that aren't on any disk: their text and dates are set by the test, and every look and read is counted.
private final class MadeFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (text: String?, modified: Double, putAway: Bool)] = [:]
    private var failing = false
    private var reads = 0

    func set(_ item: ShelfItem, _ text: String?, modified: Double = 1_000, putAway: Bool = false) {
        lock.withLock { files[item.fileURL.path] = (text, modified, putAway) }
    }

    func remove(_ item: ShelfItem) { lock.withLock { files[item.fileURL.path] = nil } }
    func fail(_ on: Bool) { lock.withLock { failing = on } }
    var readCount: Int { lock.withLock { reads } }

    func inspect(_ url: URL) -> KeptFileFacts? {
        lock.withLock {
            files[url.path].map { KeptFileFacts(modified: Date(timeIntervalSince1970: $0.modified), size: ($0.text ?? "").utf8.count, putAway: $0.putAway) }
        }
    }

    func text(_ url: URL) throws -> String? {
        try lock.withLock {
            reads += 1
            if failing { throw CocoaError(.fileReadUnknown) }
            return files[url.path]?.text
        }
    }
}

@MainActor
private func passages(_ files: MadeFiles) -> ShelfPassages {
    ShelfPassages(inspect: { files.inspect($0) }, read: { try files.text($0) })
}

// MARK: Which items, and what text

struct ShelfPassageRulesTests {
    @Test func aNoteIsTheFileNamedNoteMdWithNoVersionOfItsOwn() {
        #expect(note().isSelectionNote)
        // An ordinary document is not one, nor is a Claude document that happens to be called note.md (it has a version).
        #expect(!ShelfRules.items(from: [result("qc_notes.md", folder: "qc_notes")])[0].isSelectionNote)
        #expect(!ShelfRules.items(from: [result("note.md", folder: "note", version: "v-3")])[0].isSelectionNote)
        #expect(!ShelfRules.items(from: [result("z_prime.png", folder: "z_prime", version: "v-1")])[0].isSelectionNote)
    }

    @Test func aShortPassageIsShownAsTheNoteHoldsIt() {
        let held = String(decoding: ShelfSelectionNote.data(for: "Repeat plate 7 with a fresh seal."), as: UTF8.self)
        #expect(ShelfPassage.text(from: held) == "Repeat plate 7 with a fresh seal.")
    }

    @Test func aPassageKeepsItsLinesAndItsMarksAndLosesOnlyItsEnds() {
        let words = "## Repeat plate 7\n- a fresh seal\n\n- the same lot of buffer"
        #expect(ShelfPassage.text(from: "\n  " + words.replacingOccurrences(of: "\n", with: "\r\n") + "  \n\n") == words)
    }

    /// `note.md` is only the words: the README beside it is the record. A passage that opens with a rule and has another
    /// further on is the person's own words, and is not taken for front matter.
    @Test func aPassageThatLooksLikeFrontMatterIsKeptWhole() {
        let words = "---\nplate: 7\n---\nThe edge wells run low."
        #expect(ShelfPassage.text(from: words + "\n") == words)
    }

    @Test func aLongPassageIsShownWholeToTheLimitAndNoFurther() {
        let paragraph = String(repeating: "The edge wells run low. ", count: 40)
        let long = (0..<30).map { "\($0). " + paragraph }.joined(separator: "\n\n")
        #expect(long.count < ShelfSelectionNote.limit)
        #expect(ShelfPassage.text(from: long + "\n") == long.trimmingCharacters(in: .whitespacesAndNewlines))
        let over = String(repeating: "a ", count: ShelfSelectionNote.limit)
        #expect(ShelfPassage.text(from: over)?.count == ShelfSelectionNote.limit - 1, "cut at 32,000 characters, the blank at the cut trimmed")
    }

    @Test func aFileWithNothingInItHasNoPassage() {
        #expect(ShelfPassage.text(from: "") == nil)
        #expect(ShelfPassage.text(from: " \n\t\n") == nil)
    }

    @Test func theFileIsReadToTheLimitOfAFullNoteAndItsFinalLineEnd() {
        // 32,000 characters at four bytes each, and the line end.
        #expect(ShelfPassage.readLimit == 128_004)
    }

    @Test func theCardGivesAPassageRoomAndNoMoreThanItsMaximum() {
        #expect(ShelfDetail.passageHeight(forCard: 459) == 280, "the default window")
        #expect(ShelfDetail.passageHeight(forCard: 269) == 97, "the narrowest window")
        #expect(ShelfDetail.passageHeight(forCard: 120) == 96)
        #expect(ShelfDetail.passageHeight(forCard: 2_000) == 280)
    }
}

// MARK: Reading it

@MainActor
struct ShelfPassagesTests {
    @Test func aNotesPassageIsReadWhenItsCardAsks() async {
        let files = MadeFiles()
        let held = note()
        files.set(held, "Plate 7 drifts after the midpoint.\n")
        let store = passages(files)
        #expect(store.text(for: held) == nil, "nothing is read until it is asked for")
        await store.look(at: held)
        #expect(store.text(for: held) == "Plate 7 drifts after the midpoint.")
    }

    @Test func aFileThatHasNotChangedIsNotReadAgainAndOneThatHasIs() async {
        let files = MadeFiles()
        let held = note()
        files.set(held, "Plate 7 drifts.\n")
        let store = passages(files)
        await store.look(at: held)
        await store.look(at: held)
        #expect(files.readCount == 1)
        // Edited in another app: the same size, a later date.
        files.set(held, "Plate 8 drifts.\n", modified: 2_000)
        await store.look(at: held)
        #expect(files.readCount == 2)
        #expect(store.text(for: held) == "Plate 8 drifts.")
    }

    @Test func anOrdinaryDocumentIsNeverReadForItsPassage() async {
        let files = MadeFiles()
        let document = ShelfRules.items(from: [result("qc_notes.md", folder: "qc_notes")])[0]
        files.set(document, "# Plate 7\nThe edge wells run low.")
        let store = passages(files)
        await store.look(at: document)
        #expect(store.text(for: document) == nil)
        #expect(files.readCount == 0)
    }

    @Test func aNoteWhoseFileIsGonePutAwayOrEmptyHasNoPassageAndOneHeldBeforeGoes() async {
        let files = MadeFiles()
        let held = note()
        files.set(held, "Plate 7 drifts.\n")
        let store = passages(files)
        await store.look(at: held)
        #expect(store.text(for: held) != nil)

        files.set(held, "Plate 7 drifts.\n", modified: 2_000, putAway: true)
        await store.look(at: held)
        #expect(store.text(for: held) == nil, "put away in iCloud: no passage, and none was read")
        #expect(files.readCount == 1)

        files.set(held, "Plate 7 drifts.\n", modified: 3_000)
        await store.look(at: held)
        #expect(store.text(for: held) != nil)
        files.remove(held)
        await store.look(at: held)
        #expect(store.text(for: held) == nil, "gone")

        files.set(held, "\n\n", modified: 4_000)
        await store.look(at: held)
        #expect(store.text(for: held) == nil, "nothing in it")
    }

    @Test func aDiskThatDoesNotAnswerLeavesWhatWasHeldAndIsAskedAgain() async {
        let files = MadeFiles()
        let held = note()
        files.set(held, "Plate 7 drifts.\n")
        let store = passages(files)
        await store.look(at: held)
        files.set(held, "Plate 8 drifts.\n", modified: 2_000)
        files.fail(true)
        await store.look(at: held)
        #expect(store.text(for: held) == "Plate 7 drifts.")
        files.fail(false)
        await store.look(at: held)
        #expect(store.text(for: held) == "Plate 8 drifts.")
    }

    @Test func aFewPassagesAreHeldAndTheOldestIsLetGo() async {
        let files = MadeFiles()
        let store = passages(files)
        let notes = (0..<(ShelfPassages.kept + 1)).map { note("Note \($0)") }
        for (offset, held) in notes.enumerated() {
            files.set(held, "Passage \(offset)\n")
            await store.look(at: held)
        }
        #expect(store.text(for: notes[0]) == nil)
        #expect(store.text(for: notes[1]) == "Passage 1")
        #expect(store.text(for: notes[ShelfPassages.kept]) == "Passage \(ShelfPassages.kept)")
    }

    @Test func theModelOwnsOnePassageStoreAndIsRedrawnWhenAPassageArrives() async throws {
        let files = MadeFiles()
        let held = note()
        files.set(held, "Plate 7 drifts.\n")
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-passage-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let disk = KeptDisk(root: { scratch })
        let model = ShelfModel(shelf: KeptDemo.shelf(index: KeptIndex(disk: disk, root: { scratch }), root: scratch), passages: passages(files))
        var redraws = 0
        let subscription = model.objectWillChange.sink { redraws += 1 }
        defer { subscription.cancel() }
        await model.passages.look(at: held)
        #expect(redraws >= 1)
        #expect(model.passages.text(for: held) == "Plate 7 drifts.")
    }
}

// MARK: On a real disk, and Copy

@MainActor
struct ShelfPassageDiskTests {
    private func scratch(_ body: (_ kept: URL, _ disk: KeptDisk, _ board: NSPasteboard) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-passage-\(UUID().uuidString)", directoryHint: .isDirectory)
        let kept = folder.appending(path: "Kept", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let board = NSPasteboard(name: NSPasteboard.Name("capsid-tests-passage-\(UUID().uuidString)"))
        defer {
            try? FileManager.default.removeItem(at: folder)
            board.releaseGlobally()
        }
        try await body(kept, KeptDisk(root: { kept }), board)
    }

    /// A note written as `Shelf.addNote` writes one: the words and a line end, in a folder of its own.
    private func keep(_ text: String, in kept: URL, folder: String = "Plate 7 drifts") throws -> ShelfItem {
        let made = note(folder, in: kept)
        try FileManager.default.createDirectory(at: made.folder, withIntermediateDirectories: true)
        try ShelfSelectionNote.data(for: text).write(to: made.fileURL)
        return made
    }

    private func files(on board: NSPasteboard) -> [URL] {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    @Test func aShortNoteIsReadThroughTheDiskAsTheWordsSelected() async throws {
        try await scratch { kept, disk, _ in
            let short = "## Repeat plate 7\n- a fresh seal\n- read at 37 \u{00B0}C"
            let held = try keep(short, in: kept)
            #expect(await ShelfPassage.read(held, disk: disk) == short)
        }
    }

    @Test func aNoteAtTheLimitIsReadWholeIncludingWordsPastAnyCardsFirstLines() async throws {
        try await scratch { kept, disk, _ in
            // Four-byte characters, so the file is as big as a note can be: 128,001 bytes.
            let limit = String(repeating: "\u{1F9EA}", count: ShelfSelectionNote.limit - 4) + " end"
            #expect(limit.count == ShelfSelectionNote.limit)
            let held = try keep(limit, in: kept)
            let passage = await ShelfPassage.read(held, disk: disk)
            #expect(passage == limit)
            #expect(passage?.hasSuffix(" end") == true)
        }
    }

    @Test func nothingButANoteIsReadForItsPassage() async throws {
        try await scratch { kept, disk, _ in
            let document = ShelfRules.items(from: [result("qc_notes.md", folder: "qc_notes", in: kept)])[0]
            try FileManager.default.createDirectory(at: document.folder, withIntermediateDirectories: true)
            try Data("# Plate 7".utf8).write(to: document.fileURL)
            #expect(await ShelfPassage.read(document, disk: disk) == nil)
        }
    }

    @Test func copyingANoteCopiesItsPassageAsText() async throws {
        try await scratch { kept, disk, board in
            let words = "Plate 7 drifts after the midpoint.\n\nRepeat it with a fresh seal."
            let held = try keep(words, in: kept)
            await ShelfActions.copy(held, disk: disk, to: board).value
            #expect(board.string(forType: .string) == words)
            #expect(files(on: board).isEmpty, "the words, not the file")
        }
    }

    @Test func copyingALongNoteCopiesItWhole() async throws {
        try await scratch { kept, disk, board in
            let long = (0..<400).map { "Line \($0): the edge wells run low." }.joined(separator: "\n")
            let held = try keep(long, in: kept)
            await ShelfActions.copy(held, disk: disk, to: board).value
            #expect(board.string(forType: .string) == long)
        }
    }

    @Test func aNoteWhoseWordsCannotBeReadIsCopiedAsTheFile() async throws {
        try await scratch { kept, disk, board in
            let held = try keep("   \n", in: kept)
            await ShelfActions.copy(held, disk: disk, to: board).value
            #expect(files(on: board).map(\.lastPathComponent) == ["note.md"])
            #expect(board.string(forType: .string) == nil)
        }
    }

    @Test func wordsThatArriveAfterSomethingElseWasCopiedAreNotPutOnThePasteboard() async throws {
        try await scratch { kept, disk, board in
            let held = try keep("Plate 7 drifts.", in: kept)
            let copy = ShelfActions.copy(held, disk: disk, to: board)
            // Meanwhile, in another app.
            board.clearContents()
            board.setString("pH 7.4", forType: .string)
            await copy.value
            #expect(board.string(forType: .string) == "pH 7.4")
        }
    }

    @Test func anOrdinaryDocumentIsStillCopiedAsTheFileAlone() async throws {
        try await scratch { kept, disk, board in
            let document = ShelfRules.items(from: [result("qc_notes.md", folder: "qc_notes", version: "v-1", in: kept)])[0]
            try FileManager.default.createDirectory(at: document.folder, withIntermediateDirectories: true)
            try Data("# Plate 7".utf8).write(to: document.fileURL)
            await ShelfActions.copy(document, disk: disk, to: board).value
            #expect(files(on: board).map(\.lastPathComponent) == ["qc_notes.md"])
            #expect(board.string(forType: .string) == nil)
        }
    }

    @Test func aRealDiskReadsAnEditedNoteAgain() async throws {
        try await scratch { kept, disk, _ in
            let held = try keep("Plate 7 drifts.", in: kept)
            let store = ShelfPassages(disk: disk)
            await store.look(at: held)
            #expect(store.text(for: held) == "Plate 7 drifts.")
            try Data("Plate 8 drifts.\n".utf8).write(to: held.fileURL)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: held.fileURL.path)
            await store.look(at: held)
            #expect(store.text(for: held) == "Plate 8 drifts.")
        }
    }

    /// The passage is read in `ShelfPassage.read` and `ShelfPassages` through the disk layer, and the detail card shows
    /// the model's, never reading a file itself (KeptDiskCallsTests scans every file of Kept/ for calls of its own).
    @Test func theCardShowsThePassageTheModelHoldsAndTheCopyReadsThroughTheDisk() throws {
        let kept = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/Bench/Kept", directoryHint: .isDirectory)
        let source = try String(contentsOf: kept.appending(path: "ShelfPassage.swift", directoryHint: .notDirectory), encoding: .utf8)
        #expect(source.contains("disk.peek("))
        let view = try String(contentsOf: kept.appending(path: "ShelfView.swift", directoryHint: .notDirectory), encoding: .utf8)
        #expect(view.contains("model.passages.text(for: item)"))
        #expect(view.contains("ShelfPassage.read(item, disk: disk)"))
        #expect(view.contains("await model.passages.look(at: item)"))
    }
}
