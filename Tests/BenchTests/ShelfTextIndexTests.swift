// ShelfTextIndexTests.swift — the Shelf's search reads inside notes and documents
// (Kept/ShelfTextIndex.swift, ShelfRules.matching): a word only in a note's body,
// a shelved document's body or a legend file kept beside a figure is found; every
// word still has to be there, with case and accents set aside; a file is read to
// a cap and read again only when it changed; reading is never on the main actor
// and typing never waits for it; and 500 items stay quick. A made-up reader and
// made-up file dates for the rules, the real `KeptDisk` on a folder made for each
// test for the rest. The words are the made-up kind.
import Combine
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
                    session: String = "Plate reader QC", project: String = "Assay development",
                    at keptAt: Date = Date(timeIntervalSince1970: 1_792_674_000)) -> KeptResult {
    let record = KeptRecord(
        name: (file as NSString).deletingPathExtension, keptAt: keptAt, projectID: "p", projectName: project, sessionID: "s",
        sessionTitle: session,
        figure: KeptFile(path: file, role: .figure, artifact: nil, version: version, index: nil, of: nil, sha256: nil, bytes: 10),
        files: legendFile.map { [KeptFile(path: $0, role: .legend, bytes: 10)] } ?? [], missing: [],
        claudeScience: "0.1.70", capsid: "1.0")
    return KeptResult(folder: root.appending(path: "\(project)/\(folder)", directoryHint: .isDirectory), collection: project,
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
        // Reading is utility work: alone it takes a fraction of a second, but in the full suite it waits behind
        // thousands of tests, so this only guards against a stall. The typing budget below is the one that matters.
        #expect(indexed < .seconds(60), "indexing took \(indexed)")

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

// MARK: A search that is still reading

/// Lets reads through a few at a time: `allow(2)` frees the next two, however soon they come.
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

    func allow(_ count: Int = 1) {
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

@MainActor
private func waitFor(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw CancellationError()
}

/// Made-up notes, one prose file each, in one project or another.
@MainActor
private func notes(_ count: Int, project: String = "Assay development", from first: Int = 0) -> (results: [KeptResult], files: MadeFiles) {
    let files = MadeFiles()
    let results = (first..<first + count).map { number -> KeptResult in
        let made = result("notes_\(number).md", folder: "notes_\(number)", version: "v-\(number)", session: "Run notes", project: project)
        files.set(file(made, "notes_\(number).md"), "Note \(number) is about plate \(number % 7).")
        return made
    }
    return (results, files)
}

struct ShelfStillReadingWordsTests {
    @Test func theLineSaysHowManyFilesAndThatMoreMayMatch() {
        #expect(ShelfRules.stillReadingSentence(12) == "Still reading 12 files; more may match.")
        #expect(ShelfRules.stillReadingSentence(2) == "Still reading 2 files; more may match.")
        #expect(ShelfRules.stillReadingSentence(1) == "Still reading 1 file; more may match.")
    }

    @Test func whatVoiceOverIsToldHasNoCountInIt() {
        #expect(ShelfRules.stillReadingLabel == "Still reading files; more may match.")
        #expect(!ShelfRules.stillReadingLabel.contains { $0.isNumber })
    }

    @Test func theLineHasShorterWordsForWhenTheChipsLeaveItNoRoom() {
        let all = [ShelfRules.stillReadingSentence(128)] + ShelfRules.stillReadingShorter
        #expect(all == ["Still reading 128 files; more may match.", "Still reading; more may match.", "More may match."])
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.count > $1.count })
    }

    @Test func theFindPagesLineSaysYetWhileReadingAndEndsWithAFullStopOnceItIsDone() {
        #expect(ShelfRules.shelfFoundLine(typed: "zebrafish", kindNoun: nil, stillReading: false) == "Nothing on your shelf matches \u{201C}zebrafish\u{201D}.")
        #expect(ShelfRules.shelfFoundLine(typed: "zebrafish", kindNoun: nil, stillReading: true) == "Nothing on your shelf matches \u{201C}zebrafish\u{201D} yet.")
        #expect(ShelfRules.shelfFoundLine(typed: "zebrafish", kindNoun: "tables", stillReading: false) == "No tables on your shelf match \u{201C}zebrafish\u{201D}.")
        #expect(ShelfRules.shelfFoundLine(typed: "zebrafish", kindNoun: "tables", stillReading: true) == "No tables on your shelf match \u{201C}zebrafish\u{201D} yet.")
    }

    @Test func theEmptyStateSaysYetWhileReadingAndNothingMatchesOnceItIsDone() {
        #expect(ShelfRules.nothingFoundTitle(for: "zebrafish", stillReading: false) == "Nothing on your shelf matches \u{201C}zebrafish\u{201D}")
        #expect(ShelfRules.nothingFoundTitle(for: "zebrafish", stillReading: true) == "Nothing matches \u{201C}zebrafish\u{201D} yet")
        #expect(ShelfRules.nothingFoundSentence(stillReadingFiles: nil) == "Search covers names, sessions, legends and Claude\u{2019}s words.")
        #expect(ShelfRules.nothingFoundSentence(stillReadingFiles: 12) == "Still reading 12 files; more may match.")
    }
}

struct ShelfFilesStillToReadTests {
    private let session = "Run notes"

    @Test func countsTheUnreadFilesOfItemsTheSearchHasNotFoundYet() {
        let found = result("plate_log.md", folder: "plate_log", session: session)
        let other = result("seal_repeat.md", folder: "seal_repeat", session: session)
        let figure = result("z_prime.png", folder: "z_prime", legend: "z_prime_legend.md", session: session)
        let items = ShelfRules.items(from: [found, other, figure])
        let all = Set([file(found, "plate_log.md"), file(other, "seal_repeat.md"), file(figure, "z_prime_legend.md")].map(\.path))
        // "plate" is in a file's name already: reading its text can add nothing to it.
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "plate", texts: .none, unread: all) == 2)
        // A word on no card: all three could match.
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "zebrafish", texts: .none, unread: all) == 3)
        // Only the files not read yet.
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "zebrafish", texts: .none,
                                            unread: [file(other, "seal_repeat.md").path]) == 1)
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "zebrafish", texts: .none, unread: []) == 0)
    }

    @Test func noSearchAndASearchOfBlanksCountNothing() {
        let made = result("seal_repeat.md", folder: "seal_repeat", session: session)
        let all: Set<String> = [file(made, "seal_repeat.md").path]
        let items = [item(made)]
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "", texts: .none, unread: all) == 0)
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "   ", texts: .none, unread: all) == 0)
    }

    @Test func onlyTheChosenProjectsFilesCount() {
        let here = result("seal_repeat.md", folder: "seal_repeat", session: session)
        let there = result("cold_room.md", folder: "cold_room", session: session, project: "Paper draft")
        let items = ShelfRules.items(from: [here, there])
        let all: Set<String> = [file(here, "seal_repeat.md").path, file(there, "cold_room.md").path]
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "zebrafish", texts: .none, unread: all) == 2)
        #expect(ShelfRules.filesStillToRead(in: items, project: "Assay development", query: "zebrafish", texts: .none, unread: all) == 1)
        #expect(ShelfRules.filesStillToRead(in: items, project: "Paper draft", query: "zebrafish", texts: .none, unread: all) == 1)
        #expect(ShelfRules.filesStillToRead(in: items, project: "Nowhere", query: "zebrafish", texts: .none, unread: all) == 0)
    }

    @Test @MainActor func anItemTheTextReadSoFarAlreadyFindsGainsNothingFromItsOtherFiles() async {
        // A figure with two legend files: one is read and has the word, the other is not read yet.
        let first = result("z_prime.png", folder: "z_prime", legend: "z_prime_legend.md", version: "v-1", session: session)
        let second = result("z_prime.png", folder: "Fig 2B", legend: "z_prime_legend.md", version: "v-1", session: session)
        let items = ShelfRules.items(from: [first, second])
        #expect(items.count == 1)
        let made = MadeFiles()
        made.set(file(first, "z_prime_legend.md"), "mentions zebrafish")
        made.set(file(second, "z_prime_legend.md"), "mentions axolotl")
        let texts = ShelfTextIndex(inspect: { made.inspect($0) }, read: { url in
            url.path == file(second, "z_prime_legend.md").path ? nil : made.text(url)
        })
        texts.update(for: items)
        await texts.waitUntilRead()
        let left: Set<String> = [file(second, "z_prime_legend.md").path]
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "zebrafish", texts: texts.texts, unread: left) == 0)
        #expect(ShelfRules.filesStillToRead(in: items, project: nil, query: "zebrafish axolotl", texts: texts.texts, unread: left) == 1)
    }
}

@MainActor
struct ShelfUnreadTests {
    private func counts(of index: ShelfTextIndex, into seen: Seen) -> AnyCancellable {
        index.$unread.sink { seen.add($0.count) }
    }

    @Test func theFilesStillToReadAreCountedWhileTheyAreHeldAndGoWhenReadingFinishes() async throws {
        let made = notes(5)
        let steps = Steps()
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .zero, read: { url in await steps.wait(); return made.files.text(url) })
        #expect(texts.unread.isEmpty)
        texts.update(for: ShelfRules.items(from: made.results))
        #expect(texts.unread.count == 5, "counted as soon as the reading is asked for")
        steps.allow(5)
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty)
        #expect(!texts.isReading)
    }

    @Test func eachFileThatFinishesTakesOneOffTheCount() async throws {
        let made = notes(4)
        let steps = Steps()
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .zero, read: { url in await steps.wait(); return made.files.text(url) })
        let seen = Seen()
        let watch = counts(of: texts, into: seen)
        texts.update(for: ShelfRules.items(from: made.results))
        for left in [3, 2, 1, 0] {
            steps.allow()
            try await waitFor("\(left) left") { texts.unread.count == left }
        }
        await texts.waitUntilRead()
        #expect(seen.values == [0, 4, 3, 2, 1, 0])
        withExtendedLifetime(watch) {}
    }

    @Test func fileReadsBetweenPublishesAreNotEachPublished() async throws {
        let made = notes(20)
        // A long interval: the count is published when it fills and when it empties, and in between not at all.
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .seconds(30), read: { made.files.text($0) })
        let seen = Seen()
        let watch = counts(of: texts, into: seen)
        texts.update(for: ShelfRules.items(from: made.results))
        await texts.waitUntilRead()
        #expect(seen.values == [0, 20, 0])
        #expect(made.files.reads == 20)
        withExtendedLifetime(watch) {}
    }

    @Test func theLastChangeInAnIntervalIsPublishedWhenItIsUp() async throws {
        let made = notes(6)
        let steps = Steps()
        // Timing-sensitive by nature: the three reads must all come inside one interval, so it is long.
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .milliseconds(1_500),
                                   read: { url in await steps.wait(); return made.files.text(url) })
        let seen = Seen()
        let watch = counts(of: texts, into: seen)
        texts.update(for: ShelfRules.items(from: made.results))
        steps.allow(3)
        try await waitFor("three files read") { texts.texts.folded.count == 3 }
        // Three have finished, and one interval has not gone by: still the six published, then the three.
        #expect(seen.values.first == 0 && seen.values.dropFirst().first == 6)
        try await waitFor("the count catches up") { texts.unread.count == 3 }
        #expect(seen.values.count <= 4, "a few at most, not one for each file: \(seen.values)")
        steps.allow(3)
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty, "empty at once when the reading ends")
        withExtendedLifetime(watch) {}
    }

    @Test func aRescanThatFindsNothingNewNamesNothingAndPublishesNothing() async throws {
        let made = notes(3)
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .zero, read: { made.files.text($0) })
        let items = ShelfRules.items(from: made.results)
        texts.update(for: items)
        await texts.waitUntilRead()
        let seen = Seen()
        let watch = counts(of: texts, into: seen)
        texts.update(for: items)
        #expect(texts.unread.isEmpty)
        await texts.waitUntilRead()
        #expect(seen.values == [0], "no line flashes on the periodic read of the folders")
        // A file changed since is read again, but it has its old words meanwhile, so it is not named.
        made.files.set(file(made.results[0], "notes_0.md"), "Another word", modified: 2_000)
        texts.update(for: items)
        #expect(texts.unread.isEmpty)
        await texts.waitUntilRead()
        #expect(seen.values == [0])
        withExtendedLifetime(watch) {}
    }

    @Test func aFileThatIsGoneDoesNotPutTheLineUpAgainOnEachRescan() async throws {
        let made = notes(3)
        made.files.remove(file(made.results[1], "notes_1.md"))
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .zero, read: { made.files.text($0) })
        let items = ShelfRules.items(from: made.results)
        // The first read of the folders has to look to find it gone.
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty)
        let seen = Seen()
        let watch = counts(of: texts, into: seen)
        texts.update(for: items)
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(seen.values == [0], "looked at again, but never named: no flash on each rescan of a shelf with a note whose file is gone")
        // It comes back: read when it is looked at, and found.
        made.files.set(file(made.results[1], "notes_1.md"), "Note 1 mentions zebrafish.")
        texts.update(for: items)
        await texts.waitUntilRead()
        #expect(ShelfRules.matching(items, project: nil, query: "zebrafish", texts: texts.texts).count == 1)
        withExtendedLifetime(watch) {}
    }

    @Test func aNewFileOnTheShelfIsNamedUntilItIsRead() async throws {
        let made = notes(3)
        let more = notes(1, from: 3)
        let steps = Steps()
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) ?? more.files.inspect($0) }, publishEvery: .zero,
                                   read: { url in await steps.wait(); return made.files.text(url) ?? more.files.text(url) })
        let items = ShelfRules.items(from: made.results)
        texts.update(for: items)
        steps.allow(3)
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty)
        texts.update(for: ShelfRules.items(from: made.results + more.results))
        #expect(texts.unread == [file(more.results[0], "notes_3.md").path])
        steps.allow()
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty)
    }

    @Test func aFileTakenOffTheShelfWhileReadingIsNoLongerWaitedFor() async throws {
        let made = notes(4)
        let steps = Steps()
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .zero, read: { url in await steps.wait(); return made.files.text(url) })
        let items = ShelfRules.items(from: made.results)
        texts.update(for: items)
        #expect(texts.unread.count == 4)
        texts.update(for: Array(items.prefix(2)))
        #expect(texts.unread.count == 2)
        steps.allow(4)
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty)
    }

    @Test func aFileThatCouldNotBeReadDoesNotKeepTheLineUp() async throws {
        let made = notes(3)
        let texts = ShelfTextIndex(inspect: { made.files.inspect($0) }, publishEvery: .zero, read: { url in
            if url.lastPathComponent == "notes_1.md" { throw KeptDiskError.notResponding("read") }
            return made.files.text(url)
        })
        texts.update(for: ShelfRules.items(from: made.results))
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty, "a disk that didn't answer is tried again next time, not waited for now")
        // A file that is gone, and one iCloud has put away, are not waited for either.
        made.files.remove(file(made.results[2], "notes_2.md"))
        made.files.set(file(made.results[0], "notes_0.md"), "away", modified: 5, putAway: true)
        texts.update(for: ShelfRules.items(from: made.results))
        await texts.waitUntilRead()
        #expect(texts.unread.isEmpty)
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int] = []
    func add(_ count: Int) { lock.withLock { counts.append(count) } }
    var values: [Int] { lock.withLock { counts } }
}

// MARK: The window's model, while the search is still reading

@MainActor
private final class Said {
    var lines: [String] = []
}

@MainActor
private final class Redraws {
    var count = 0
    var watch: AnyCancellable?
}

@MainActor
struct ShelfStillReadingModelTests {
    /// A shelf of made-up notes on a real disk, searched through an index whose reads are let through by hand.
    /// Each note is (project, file name without its extension, what it says).
    private struct Rig {
        let model: ShelfModel
        let steps: Steps
        let said: Said
        let scratch: URL
    }

    private func rig(_ notes: [(project: String, name: String, text: String)], publishEvery: Duration = .zero) async throws -> Rig {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-reading-\(UUID().uuidString)", directoryHint: .isDirectory)
        let kept = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        var says: [String: String] = [:]
        for note in notes {
            let made = result("\(note.name).md", folder: note.name, session: "Run notes", project: note.project)
            let there = kept.appending(path: "\(note.project)/\(note.name)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: there, withIntermediateDirectories: true)
            try Data(note.text.utf8).write(to: there.appending(path: "\(note.name).md", directoryHint: .notDirectory))
            try Data(KeptReadme.render(made.record, text: made.text).utf8).write(to: there.appending(path: "README.md", directoryHint: .notDirectory))
            says["\(note.name).md"] = note.text
        }
        let disk = KeptDisk(root: { kept })
        let index = KeptIndex(disk: disk, root: { kept })
        let shelf = KeptDemo.shelf(index: index, root: kept)
        await index.refreshAndWait()
        let steps = Steps(), said = Said()
        let texts = ShelfTextIndex(inspect: { _ in KeptFileFacts(modified: Date(timeIntervalSince1970: 1), size: 10) }, publishEvery: publishEvery,
                                   read: { [says] url in await steps.wait(); return says[url.lastPathComponent] })
        let model = ShelfModel(shelf: shelf, pdf: ShelfPDFMaker(dependencies: .declining), textIndex: texts, announce: { said.lines.append($0) })
        #expect(model.items.count == notes.count)
        return Rig(model: model, steps: steps, said: said, scratch: scratch)
    }

    private static let three: [(project: String, name: String, text: String)] = [
        ("Assay development", "plate_log", "Plate 7 drifts after the midpoint."),
        ("Assay development", "seal_repeat", "Repeat it with a fresh seal. The zebrafish plate is the one to watch."),
        ("Paper draft", "cold_room", "The cold room ran two degrees warm overnight."),
    ]

    @Test func nothingShowsWithoutASearch() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        #expect(!rig.model.textIndex.isActive, "nothing is read until a search is typed")
        #expect(rig.model.stillReadingFiles == nil && rig.model.stillReadingLine == nil)
        #expect(rig.said.lines.isEmpty)
        // Reading started for another reason, with no search typed, still shows nothing.
        rig.model.textIndex.update(for: rig.model.items)
        #expect(rig.model.textIndex.isReading)
        #expect(rig.model.stillReadingFiles == nil)
        rig.steps.allow(3)
        await rig.model.textIndex.waitUntilRead()
    }

    @Test func theLineShowsWhileASearchHasFilesToReadAndGoesWhenReadingFinishes() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        rig.model.search = "zebrafish"
        #expect(rig.model.stillReadingFiles == 3)
        #expect(rig.model.stillReadingLine == "Still reading 3 files; more may match.")
        rig.steps.allow(3)
        await rig.model.textIndex.waitUntilRead()
        #expect(rig.model.stillReadingFiles == nil && rig.model.stillReadingLine == nil)
        #expect(rig.model.shown.count == 1, "and the note that says it is found")
    }

    @Test func theCountFollowsTheFilesAndVoiceOverIsToldOnce() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        rig.model.search = "zebrafish"
        #expect(rig.said.lines == [ShelfRules.stillReadingLabel])
        rig.steps.allow()
        try await waitFor("one file read") { rig.model.textIndex.unread.count == 2 }
        #expect(rig.model.stillReadingFiles == 2)
        rig.steps.allow()
        try await waitFor("two files read") { rig.model.textIndex.unread.count == 1 }
        #expect(rig.model.stillReadingLine == "Still reading 1 file; more may match.")
        rig.steps.allow()
        await rig.model.textIndex.waitUntilRead()
        #expect(rig.said.lines == [ShelfRules.stillReadingLabel], "said when it appeared, not as it counted down or went")
    }

    @Test func aSearchWithNothingLeftToReadShowsNoLine() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        rig.model.search = "zebrafish"
        rig.steps.allow(3)
        await rig.model.textIndex.waitUntilRead()
        // Everything is read: another search, and the folders read again, find nothing to wait for.
        rig.model.search = "axolotl"
        #expect(rig.model.stillReadingFiles == nil)
        rig.model.textIndex.update(for: rig.model.items)
        await rig.model.textIndex.waitUntilRead()
        #expect(rig.model.stillReadingFiles == nil)
        #expect(rig.said.lines.count == 1)
    }

    @Test func clearingTheSearchTakesTheLineAwayAtOnceWhileReadingGoesOn() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        rig.model.search = "zeb"
        #expect(rig.model.stillReadingFiles == 3)
        rig.model.search = ""
        #expect(rig.model.textIndex.isReading)
        #expect(rig.model.stillReadingFiles == nil)
        rig.model.search = "zebra"
        #expect(rig.model.stillReadingFiles == 3)
        #expect(rig.said.lines.count == 2, "it appeared twice")
        rig.steps.allow(3)
        await rig.model.textIndex.waitUntilRead()
    }

    @Test func theCountIsTheFilesThatCouldStillMatch() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        // "plate" is in a file name already, so that note gains nothing from its text; the other two could.
        rig.model.search = "plate"
        #expect(rig.model.stillReadingFiles == 2)
        rig.model.project = "Paper draft"
        #expect(rig.model.stillReadingFiles == 1)
        rig.model.project = "Assay development"
        #expect(rig.model.stillReadingFiles == 1)
        rig.model.project = nil
        #expect(rig.model.stillReadingFiles == 2)
        rig.steps.allow(3)
        await rig.model.textIndex.waitUntilRead()
        #expect(rig.model.stillReadingFiles == nil)
    }

    @Test func theEmptyStateSaysMatchesMayStillComeWhileReadingAndNothingMatchesOnceDone() async throws {
        let rig = try await rig(Self.three)
        defer { try? FileManager.default.removeItem(at: rig.scratch) }
        rig.model.search = "zebrafish"
        #expect(rig.model.shown.isEmpty && rig.model.searchFoundNothing)
        #expect(rig.model.nothingFoundTitle == "Nothing matches \u{201C}zebrafish\u{201D} yet")
        #expect(rig.model.nothingFoundSentence == "Still reading 3 files; more may match.")
        rig.steps.allow(3)
        await rig.model.textIndex.waitUntilRead()
        #expect(!rig.model.searchFoundNothing, "the note that says it has come")
        // A word no file has: once reading is done, the empty state is final.
        rig.model.search = "axolotl"
        #expect(rig.model.searchFoundNothing)
        #expect(rig.model.nothingFoundTitle == "Nothing on your shelf matches \u{201C}axolotl\u{201D}")
        #expect(rig.model.nothingFoundSentence == "Search covers names, sessions, legends and Claude\u{2019}s words.")
    }

    @Test func filesThatAddNothingDoNotRedrawTheWindowAndOneThatAddsAMatchDoes() async throws {
        // 30 notes that say nothing of the search: reading them changes nothing that is shown, so the window is
        // redrawn for the line going, not for each file.
        let plain = (0..<30).map { (project: "Assay development", name: "plain_\($0)", text: "Nothing to see in note \($0).") }
        let quiet = try await rig(plain, publishEvery: .seconds(30))
        defer { try? FileManager.default.removeItem(at: quiet.scratch) }
        let redraws = Redraws()
        redraws.watch = quiet.model.objectWillChange.sink { [redraws] _ in MainActor.assumeIsolated { redraws.count += 1 } }
        quiet.model.search = "zebrafish"
        let typed = redraws.count
        quiet.steps.allow(30)
        await quiet.model.textIndex.waitUntilRead()
        #expect(quiet.model.shown.isEmpty)
        #expect(redraws.count - typed <= 1, "\(redraws.count - typed) redraws while 30 files were read")

        // The same with one note that does say it: that one is a change to what is shown, and is drawn.
        let loud = try await rig(plain + [("Assay development", "match", "mentions zebrafish")], publishEvery: .seconds(30))
        defer { try? FileManager.default.removeItem(at: loud.scratch) }
        let found = Redraws()
        found.watch = loud.model.objectWillChange.sink { [found] _ in MainActor.assumeIsolated { found.count += 1 } }
        loud.model.search = "zebrafish"
        let before = found.count
        loud.steps.allow(31)
        await loud.model.textIndex.waitUntilRead()
        #expect(loud.model.shown.count == 1)
        #expect(found.count > before)
        #expect(found.count - before < 31, "\(found.count - before) redraws while 31 files were read")
    }
}
