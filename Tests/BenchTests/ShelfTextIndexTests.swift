// ShelfTextIndexTests.swift — the Shelf's search reads inside notes and documents
// (Kept/ShelfTextIndex.swift, ShelfRules.matching): a word only in a note's body,
// a shelved document's body or a legend file kept beside a figure is found; every
// word still has to be there, with case and accents set aside; a file is read to
// a cap and read again only when it changed; reading is never on the main actor
// and typing never waits for it; and 500 items stay quick. A made-up reader and
// made-up file dates for the rules, the real `KeptDisk` on a folder made for each
// test for the rest. The words are the made-up kind.
import Foundation
import Testing
@testable import Bench

private let root = URL(fileURLWithPath: "/tmp/kept-text", isDirectory: true)

/// Files that aren't on any disk: their text and dates are set by the test, and every look and read is counted.
private final class MadeFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (text: String, modified: Double, putAway: Bool)] = [:]
    private var readPaths: [String] = []
    private var looks = 0

    func set(_ url: URL, _ text: String, modified: Double = 1_000, putAway: Bool = false) {
        lock.withLock { files[url.path] = (text, modified, putAway) }
    }

    func remove(_ url: URL) { lock.withLock { files[url.path] = nil } }

    func inspect(_ url: URL) -> KeptFileFacts? {
        lock.withLock {
            looks += 1
            return files[url.path].map { KeptFileFacts(modified: Date(timeIntervalSince1970: $0.modified), size: $0.text.utf8.count, putAway: $0.putAway) }
        }
    }

    func text(_ url: URL) -> String? {
        lock.withLock {
            readPaths.append(url.path)
            return files[url.path]?.text
        }
    }

    var reads: Int { lock.withLock { readPaths.count } }
    func reads(of url: URL) -> Int { lock.withLock { readPaths.filter { $0 == url.path }.count } }
}

@MainActor
private func index(_ files: MadeFiles) -> ShelfTextIndex {
    ShelfTextIndex(inspect: { files.inspect($0) }, read: { files.text($0) })
}

private func result(_ file: String, folder: String, legend legendFile: String? = nil, said: String = "", version: String? = nil,
                    session: String = "Plate reader QC", at keptAt: Date = Date(timeIntervalSince1970: 1_792_674_000)) -> KeptResult {
    let record = KeptRecord(
        name: (file as NSString).deletingPathExtension, keptAt: keptAt, projectID: "p", projectName: "Assay development", sessionID: "s",
        sessionTitle: session,
        figure: KeptFile(path: file, role: .figure, artifact: nil, version: version, index: nil, of: nil, sha256: nil, bytes: 10),
        files: legendFile.map { [KeptFile(path: $0, role: .legend, bytes: 10)] } ?? [], missing: [],
        claudeScience: "0.1.70", capsid: "1.0")
    return KeptResult(folder: root.appending(path: "Assay development/\(folder)", directoryHint: .isDirectory), collection: "Assay development",
                      record: record, text: KeptText(legend: "", claudeSaid: said, attribution: "", origin: ""))
}

private func item(_ result: KeptResult) -> ShelfItem { ShelfRules.items(from: [result])[0] }

private func file(_ result: KeptResult, _ name: String) -> URL { result.folder.appending(path: name, directoryHint: .notDirectory) }

@MainActor
private func found(_ items: [ShelfItem], _ query: String, _ index: ShelfTextIndex) -> [String] {
    ShelfRules.matching(items, project: nil, query: query, texts: index.texts).map(\.title)
}

// MARK: The files a search reads

struct ShelfProseFilesTests {
    @Test func aDocumentsOwnMarkdownOrTextFileIsRead() {
        for name in ["qc_notes.md", "qc_notes.MD", "qc_notes.markdown", "qc_notes.txt", "qc_notes.text", "qc_notes.rst"] {
            let made = result(name, folder: "notes")
            #expect(ShelfRules.proseFiles(of: item(made)) == [file(made, name)], "\(name)")
        }
    }

    @Test func otherFilesAreNotRead() {
        for name in ["z_prime.png", "plate_7.csv", "report.pdf", "analysis.py", "data.json", "README"] {
            #expect(ShelfRules.proseFiles(of: item(result(name, folder: "other"))).isEmpty, "\(name)")
        }
    }

    @Test func aLegendFileKeptBesideAFigureIsRead() {
        let made = result("z_prime.png", folder: "z_prime", legend: "z_prime_legend.md")
        #expect(ShelfRules.proseFiles(of: item(made)) == [file(made, "z_prime_legend.md")])
        // A legend that isn't prose, or whose path leaves its folder, is not.
        #expect(ShelfRules.proseFiles(of: item(result("z_prime.png", folder: "z_prime", legend: "legend.pdf"))).isEmpty)
        #expect(ShelfRules.proseFiles(of: item(result("z_prime.png", folder: "z_prime", legend: "../elsewhere/legend.md"))).isEmpty)
        #expect(ShelfRules.proseFiles(of: item(result("z_prime.png", folder: "z_prime", legend: "/etc/legend.md"))).isEmpty)
    }

    @Test func aFigureKeptAgainHasTheLegendFilesOfEveryFolderOnce() {
        let shelved = result("z.png", folder: "z", legend: "z_legend.md", version: "v-9")
        let kept = result("z.png", folder: "Fig 2B", legend: "z_legend.md", version: "v-9")
        let files = ShelfRules.proseFiles(of: ShelfRules.items(from: [shelved, kept])[0])
        #expect(Set(files.map(\.path)) == [file(shelved, "z_legend.md").path, file(kept, "z_legend.md").path])
        #expect(files.count == 2)
    }
}

// MARK: Searching what is read

@MainActor
struct ShelfTextSearchTests {
    @Test func aWordOnlyInANotesBodyIsFound() async {
        let made = result("note.md", folder: "Plate 7 drifts")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(file(made, "note.md"), "Plate 7 drifts after the midpoint.\n\nThe edge wells run low on the zebrafish plate.\n")
        let texts = index(files)
        #expect(found(items, "zebrafish", texts).isEmpty, "nothing is read before the index is asked")
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts) == [items[0].title])
        #expect(found(items, "ZEBRAFISH", texts).count == 1)
        #expect(found(items, "zebrafish plate midpoint", texts).count == 1)
        #expect(found(items, "zebrafish axolotl", texts).isEmpty, "every word has to be there")
        // The title, the session and the words in the file, each word wherever it is.
        #expect(found(items, "zebrafish reader", texts).count == 1)
        #expect(ShelfRules.foundOnlyInText(items[0], query: "zebrafish", texts: texts.texts))
        #expect(ShelfRules.foundOnlyInText(items[0], query: "zebrafish reader", texts: texts.texts))
        #expect(!ShelfRules.foundOnlyInText(items[0], query: "reader", texts: texts.texts), "the session says it already")
        #expect(!ShelfRules.foundOnlyInText(items[0], query: "axolotl", texts: texts.texts), "not found at all")
        #expect(!ShelfRules.foundOnlyInText(items[0], query: "", texts: texts.texts))
    }

    @Test func aWordOnlyInADocumentsBodyIsFound() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let items = [item(made), item(result("z_prime.png", folder: "z_prime"))]
        let files = MadeFiles()
        files.set(file(made, "qc_notes.md"), "# QC notes\n\nThe Z\u{2032} factor of plate 3 is 0.71, above the cutoff.\n")
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "cutoff", texts) == ["qc_notes.md"])
        #expect(found(items, "factor cutoff", texts) == ["qc_notes.md"])
        #expect(files.reads == 1, "the figure has no prose file to read")
    }

    @Test func aLegendFileKeptBesideAFigureIsFoundByItsWords() async {
        let made = result("z_prime.png", folder: "z_prime", legend: "z_prime_legend.md")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(file(made, "z_prime_legend.md"), "Z\u{2032} by plate; error bars are the standard deviation of eight controls.")
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "eight controls", texts) == ["z_prime.png"])
        #expect(ShelfRules.foundOnlyInText(items[0], query: "eight controls", texts: texts.texts))
    }

    @Test func caseAndAccentsAreSetAside() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(file(made, "qc_notes.md"), "Résumé of the Müller plate: fluorescence, naïve cells, Ångström scale.")
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        for query in ["resume", "RÉSUMÉ", "muller", "NAIVE", "angstrom", "ångström", "résumé müller"] {
            #expect(found(items, query, texts).count == 1, "\(query)")
        }
        #expect(found(items, "résumés", texts).isEmpty)
        // The words a card already carries are matched the same way.
        #expect(ShelfRules.matching(items, project: nil, query: "QC_NOTES").count == 1)
        let accented = [item(result("z_prime.png", folder: "z", session: "Électrophorèse"))]
        #expect(ShelfRules.matching(accented, project: nil, query: "electrophorese").count == 1)
    }

    @Test func aSearchWithNoTextReadMatchesAsItAlwaysDid() {
        let items = [item(result("qc_notes.md", folder: "qc_notes", said: "Plate 7 is the low bar."))]
        #expect(ShelfRules.matching(items, project: nil, query: "low bar").count == 1)
        #expect(ShelfRules.matching(items, project: nil, query: "zebrafish").isEmpty)
        #expect(ShelfRules.matching(items, project: nil, query: "zebrafish", texts: .none).isEmpty)
    }
}

// MARK: The caps

@MainActor
struct ShelfTextCapsTests {
    @Test func theCapsAreAMegabyteReadAndTwoHundredThousandCharactersKept() {
        #expect(ShelfTextIndex.readLimit == 1_048_576)
        #expect(ShelfTextIndex.indexedCharacters == 200_000)
    }

    @Test func aWordPastTheCapIsNotFoundAndOneJustInsideIsFound() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let items = [item(made)]
        let files = MadeFiles()
        let filler = String(repeating: "a", count: ShelfTextIndex.indexedCharacters - 9)
        // "zebrafish" fills the last nine characters kept; "axolotl" is the first after them.
        files.set(file(made, "qc_notes.md"), filler + "zebrafish" + " axolotl")
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
        #expect(found(items, "axolotl", texts).isEmpty)
    }

    @Test func aWordPastTheCapOfACharacterThatTakesSeveralBytesIsNotFoundEither() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(file(made, "qc_notes.md"), String(repeating: "\u{00E9}", count: ShelfTextIndex.indexedCharacters) + " axolotl")
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "axolotl", texts).isEmpty)
        #expect(found(items, "eeee", texts).count == 1)
    }

    @Test func thePreparedTextIsTheFoldedPrefix() {
        let text = String(repeating: "\u{00C9}", count: ShelfTextIndex.indexedCharacters + 50)
        let prepared = ShelfTextIndex.prepare(text)
        #expect(prepared.count == ShelfTextIndex.indexedCharacters)
        #expect(prepared.allSatisfy { $0 == UInt8(ascii: "e") })
    }
}

// MARK: Reading again, and not

@MainActor
struct ShelfTextRereadTests {
    @Test func anEditedFileIsReadAgainAndAnUnchangedOneIsNot() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let url = file(made, "qc_notes.md")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(url, "The first draft mentions zebrafish.", modified: 1_000)
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
        #expect(files.reads(of: url) == 1)

        // The folders are read again and nothing changed: the file is looked at, not read.
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(files.reads(of: url) == 1)

        // Edited, so its date is another: read again, and what it said before is gone.
        files.set(url, "The second draft mentions axolotl.", modified: 2_000)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(files.reads(of: url) == 2)
        #expect(found(items, "axolotl", texts).count == 1)
        #expect(found(items, "zebrafish", texts).isEmpty)
    }

    @Test func aFileOfAnotherSizeAtTheSameDateIsReadAgain() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let url = file(made, "qc_notes.md")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(url, "one", modified: 1_000)
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        files.set(url, "one two", modified: 1_000)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(files.reads(of: url) == 2)
        #expect(found(items, "two", texts).count == 1)
    }

    @Test func aFileOffTheShelfOrGoneFromDiskIsLetGo() async {
        let a = result("qc_notes.md", folder: "qc_notes"), b = result("methods.txt", folder: "methods")
        let items = ShelfRules.items(from: [a, b])
        let files = MadeFiles()
        files.set(file(a, "qc_notes.md"), "mentions zebrafish")
        files.set(file(b, "methods.txt"), "mentions axolotl")
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1 && found(items, "axolotl", texts).count == 1)
        // One is taken off the shelf, the other's file is deleted in Finder.
        files.remove(file(b, "methods.txt"))
        texts.update(for: items.filter { $0.fileName == "methods.txt" })
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).isEmpty)
        #expect(found(items, "axolotl", texts).isEmpty)
        #expect(texts.texts.isEmpty)
    }

    @Test func aFileWithNoTextToGiveIsReadOnceUntilItChanges() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let items = [item(made)]
        let reads = Attempts()
        // The reader says "no text" (not text, empty) with nil.
        let texts = ShelfTextIndex(inspect: { _ in KeptFileFacts(modified: Date(timeIntervalSince1970: 1), size: 10) },
                                   read: { _ in _ = reads.next(); return nil })
        texts.update(for: items)
        await texts.waitUntilRead()
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(reads.next() == 2, "one read, and this call is the second ask")
        #expect(texts.texts.isEmpty)
    }

    @Test func aFileIcloudHasPutAwayIsNeverReadUntilItIsBack() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let url = file(made, "qc_notes.md")
        let items = [item(made)]
        let files = MadeFiles()
        let texts = index(files)
        files.set(url, "", modified: 1_000, putAway: true)
        texts.update(for: items)
        await texts.waitUntilRead()
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(files.reads == 0, "a file put away in iCloud is never read, so never brought back")
        #expect(texts.texts.isEmpty)
        // It comes back to this Mac: now it is another file, and read.
        files.set(url, "back with zebrafish", modified: 1_000, putAway: false)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
    }

    @Test func aDiskThatDoesntAnswerIsTriedAgainNextTime() async {
        let made = result("qc_notes.md", folder: "qc_notes")
        let url = file(made, "qc_notes.md")
        let items = [item(made)]
        let files = MadeFiles()
        files.set(url, "mentions zebrafish")
        let attempts = Attempts()
        let texts = ShelfTextIndex(inspect: { files.inspect($0) }, read: { url in
            if attempts.next() == 1 { throw KeptDiskError.notResponding("read") }
            return files.text(url)
        })
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).isEmpty)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
    }
}

private final class Attempts: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}

// MARK: Never on the main actor, never waited for

@MainActor
struct ShelfTextOffMainTests {
    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-text-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Kept folders on a real disk: `files` are (folder, file name, text).
    private func keep(_ files: [(String, String, String)], legends: [String: String] = [:], in root: URL) throws -> [KeptResult] {
        try files.map { folder, name, text in
            let made = result(name, folder: folder, legend: legends[folder])
            let there = root.appending(path: "Assay development/\(folder)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: there, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: there.appending(path: name, directoryHint: .notDirectory))
            if let legend = legends[folder] {
                try Data("Legend for \(folder): eight controls.".utf8).write(to: there.appending(path: legend, directoryHint: .notDirectory))
            }
            return KeptResult(folder: there, collection: made.collection, record: made.record, text: made.text)
        }
    }

    @Test func noLookAndNoReadHappensOnTheMainThread() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let kept = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        let results = try keep([("qc_notes", "qc_notes.md", "mentions zebrafish"), ("methods", "methods.txt", "mentions axolotl")],
                               in: kept)
        let onMain = Flags()
        let disk = KeptDisk(root: { kept }, run: { work in
            KeptDisk.runOnDisk { onMain.record(Thread.isMainThread); work() }
        })
        let texts = ShelfTextIndex(inspect: { url in
            onMain.record(onMainThread())
            return await KeptDisk.fileFacts(of: url)
        }, read: { url in try await disk.peek(url, limit: ShelfTextIndex.readLimit) })
        let items = ShelfRules.items(from: results)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1 && found(items, "axolotl", texts).count == 1)
        #expect(onMain.count >= 4, "two files, each looked at and read")
        #expect(!onMain.sawMain, "everything the disk was asked ran off the main thread")
    }

    @Test func typingNeverWaitsForTheDiskAndResultsFillInWhenReadingFinishes() async throws {
        let made = result("note.md", folder: "Plate 7 drifts", said: "Plate 7 is the low bar.")
        let items = [item(made)]
        let gate = Gate()
        let texts = ShelfTextIndex(inspect: { _ in KeptFileFacts(modified: Date(timeIntervalSince1970: 1), size: 10) },
                                   read: { _ in await gate.wait(); return "mentions zebrafish" })
        let before = ContinuousClock.now
        texts.update(for: items)
        // The read is held: update came back at once, and a search answers from the words a card has.
        #expect(texts.isReading)
        #expect(found(items, "low bar", texts).count == 1)
        #expect(found(items, "zebrafish", texts).isEmpty)
        #expect(ContinuousClock.now - before < .seconds(1))
        gate.open()
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
        #expect(!texts.isReading)
    }

    @Test func aBigFileIsReadToItsCapOnARealDisk() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let kept = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        // 1.2 MB of text: a word at the start is found, one at the very end is not.
        let big = "mentions zebrafish. " + String(repeating: "plate ", count: 200_000) + "axolotl"
        let results = try keep([("big", "big_notes.txt", big)], in: kept)
        let texts = ShelfTextIndex(disk: KeptDisk(root: { kept }))
        let items = ShelfRules.items(from: results)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
        #expect(found(items, "axolotl", texts).isEmpty)
    }

    @Test func aFileEditedOnARealDiskIsReadAgain() async throws {
        let scratch = try scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let kept = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        let results = try keep([("qc_notes", "qc_notes.md", "mentions zebrafish")], in: kept)
        let url = results[0].folder.appending(path: "qc_notes.md", directoryHint: .notDirectory)
        let texts = ShelfTextIndex(disk: KeptDisk(root: { kept }))
        let items = ShelfRules.items(from: results)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "zebrafish", texts).count == 1)
        // Same size, a minute later: only the modification date says it changed.
        try Data("mentions axolotl!!".utf8.prefix(18)).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(found(items, "axolotl", texts).count == 1)
        #expect(found(items, "zebrafish", texts).isEmpty)
    }

    @Test func theIndexIsOnlyBuiltThroughTheDiskLayer() throws {
        // The Kept/ scan (KeptDiskCallsTests) already fails on any file call outside KeptDisk.swift; this says the index
        // reads through `KeptDisk.peek` and looks through `KeptDisk.fileFacts`.
        let source = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/Kept/ShelfTextIndex.swift", isDirectory: false)
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(text.contains("disk.peek("))
        #expect(text.contains("KeptDisk.fileFacts(of:)"))
    }
}

/// `Thread.isMainThread` can't be asked in an async closure; it can here.
private func onMainThread() -> Bool { Thread.isMainThread }

private final class Flags: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Bool] = []
    func record(_ main: Bool) { lock.withLock { seen.append(main) } }
    var count: Int { lock.withLock { seen.count } }
    var sawMain: Bool { lock.withLock { seen.contains(true) } }
}

/// Holds a read until the test lets it go.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let now = lock.withLock { () -> Bool in
                if !isOpen { waiting.append(continuation) }
                return isOpen
            }
            if now { continuation.resume() }
        }
    }

    func open() {
        let release = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiting = [] }
            return waiting
        }
        for continuation in release { continuation.resume() }
    }
}

// MARK: Many items

@MainActor
struct ShelfTextManyTests {
    @Test func fiveHundredItemsWithAMadeUpReaderAreIndexedAndSearchedQuickly() async {
        var results: [KeptResult] = []
        let files = MadeFiles()
        for number in 0..<500 {
            let made = result("notes_\(number).md", folder: "notes_\(number)", version: "v-\(number)",
                              at: Date(timeIntervalSince1970: 1_792_000_000 + Double(number)))
            results.append(made)
            let body = (0..<300).map { "line \($0) of note \(number) about plate \($0 % 7)" }.joined(separator: "\n")
            files.set(file(made, "notes_\(number).md"), body + (number == 321 ? "\nthe zebrafish line" : ""))
        }
        let items = ShelfRules.items(from: results)
        #expect(items.count == 500)
        let texts = index(files)
        let clock = ContinuousClock()
        let start = clock.now
        texts.update(for: items)
        await texts.waitUntilRead()
        let indexed = clock.now - start
        #expect(files.reads == 500)
        #expect(indexed < .seconds(10), "indexing took \(indexed)")

        // Typing: every keystroke of a word searches all 500.
        let typing = clock.now
        var last: [String] = []
        for query in ["z", "ze", "zeb", "zebr", "zebra", "zebraf", "zebrafi", "zebrafis", "zebrafish", "zebrafish line"] {
            last = found(items, query, texts)
        }
        let searched = clock.now - typing
        #expect(last == ["notes_321.md"])
        #expect(found(items, "note 499 plate 3", texts).count == 1)
        #expect(searched < .seconds(2), "ten searches took \(searched)")
    }

    @Test func aSearchOfTheLargestIndexedTextsIsStillQuick() async {
        // Worst case for the bytes searched: 40 notes at the cap, none holding the word.
        var results: [KeptResult] = []
        let files = MadeFiles()
        let body = String(repeating: "plate reader drift ", count: 11_000)
        for number in 0..<40 {
            let made = result("big_\(number).md", folder: "big_\(number)", version: "v-\(number)")
            results.append(made)
            files.set(file(made, "big_\(number).md"), body)
        }
        let items = ShelfRules.items(from: results)
        let texts = index(files)
        texts.update(for: items)
        await texts.waitUntilRead()
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<10 { #expect(found(items, "zebrafish", texts).isEmpty) }
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(1), "ten searches took \(elapsed)")
    }
}

// MARK: The window's model

@MainActor
struct ShelfTextModelTests {
    private func until(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Still waiting: \(what)")
        throw CancellationError()
    }

    @Test func aNoteIsFoundInTheModelByItsBodyOnceReadingFinishesAndSaysSoOnItsCard() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-text-\(UUID().uuidString)", directoryHint: .isDirectory)
        let kept = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let there = kept.appending(path: "Assay development/Plate 7 drifts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: there, withIntermediateDirectories: true)
        let words = "Plate 7 drifts after the midpoint.\n\nThe edge wells run low on the zebrafish plate.\n"
        try Data(words.utf8).write(to: there.appending(path: "note.md", directoryHint: .notDirectory))
        let made = result("note.md", folder: "Plate 7 drifts", said: "")
        let readme = KeptReadme.render(made.record, text: made.text)
        try Data(readme.utf8).write(to: there.appending(path: "README.md", directoryHint: .notDirectory))

        let disk = KeptDisk(root: { kept })
        let index = KeptIndex(disk: disk, root: { kept })
        let shelf = KeptDemo.shelf(index: index, root: kept)
        await index.refreshAndWait()
        let model = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining))
        #expect(model.items.count == 1)
        #expect(!model.textIndex.isActive, "nothing is read until a search is typed")

        model.search = "zebrafish"
        #expect(model.textIndex.isActive)
        try await until("the note is found by its body") { model.shown.count == 1 }
        let item = try #require(model.shown.first)
        #expect(model.foundOnlyInText(item))
        #expect(model.counts.documents == 1)
        // A word on the card itself needs no such line.
        model.search = "reader"
        #expect(model.shown.count == 1)
        #expect(!model.foundOnlyInText(item))
        // Cleared, everything is shown again and nothing says "in its text".
        model.search = ""
        #expect(!model.foundOnlyInText(item))
        model.search = "axolotl"
        #expect(model.shown.isEmpty)
    }
}
