// ShelfSelectionNoteTests.swift — words selected in a conversation, put on the
// shelf (Kept/ShelfSelectionNote.swift, Shelf.addNote): how the selection is
// cleaned and cut, the title it is given, the folder and README an add writes
// (byte for byte), that the README parses and round-trips like every other,
// that the note is a document on the Shelf with its first lines, found by the
// Shelf's search and exported to PDF as a document, and that Undo takes it
// off. The disk is the real `KeptDisk` on a folder made for each test and
// removed after it; the Trash is a stand-in. Nothing talks to Claude Science,
// and the words are the made-up kind.
import Foundation
import Testing
@testable import Bench

private enum Made {
    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000c1", projectID: "p-3", projectName: "Assay development",
                                       title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)
    static let unnamed = SessionStatus(id: "00000000-0000-4000-8000-0000000000c2", projectID: "p-4", projectName: "",
                                       title: "", state: .finished, updatedAt: Date(), startedAt: nil)
    static let passage = "Plate 7 drifts after the midpoint, and the edge wells run low.\n\nThe cutoff is 0.5; plate 7 sits at 0.41."
    static let keptAt = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
}

// MARK: The rules

struct ShelfSelectionNoteRuleTests {
    @Test func theSelectionIsTrimmedAndKeptWithItsLineBreaks() {
        #expect(ShelfSelectionNote.clean("  \n First line.\r\nSecond line.\r\n\r\n  ") == "First line.\nSecond line.")
        #expect(ShelfSelectionNote.clean("a\tb") == "a\tb", "a tab is part of the words")
        #expect(ShelfSelectionNote.clean("no\u{0007}te") == "note")
        #expect(ShelfSelectionNote.clean("Z\u{2032} by plate \u{1F9EA}") == "Z\u{2032} by plate \u{1F9EA}")
    }

    @Test func nothingLeftIsNoNote() {
        for empty in ["", "   ", "\n\n", " \t\r\n ", "\u{0007}\u{0000}"] {
            #expect(ShelfSelectionNote.clean(empty) == nil, "\(empty.debugDescription)")
        }
    }

    @Test func aLongSelectionIsCutAtTheLimit() {
        let long = String(repeating: "a", count: 40_000)
        #expect(ShelfSelectionNote.clean(long)?.count == 32_000)
        let exact = String(repeating: "b", count: 32_000)
        #expect(ShelfSelectionNote.clean(exact)?.count == 32_000)
        // Cut where blanks fall at the end, they go too.
        let blanks = String(repeating: "c", count: 31_999) + "   more"
        #expect(ShelfSelectionNote.clean(blanks)?.count == 31_999)
        // Whole characters, not pieces of them.
        let emoji = String(repeating: "\u{1F9EA}", count: 33_000)
        #expect(ShelfSelectionNote.clean(emoji)?.count == 32_000)
        #expect(ShelfSelectionNote.limit == 32_000)
    }

    @Test func theFileIsTheWordsAndAFinalLineEnd() {
        #expect(String(decoding: ShelfSelectionNote.data(for: "Plate 7 drifts."), as: UTF8.self) == "Plate 7 drifts.\n")
        #expect(ShelfSelectionNote.fileName == "note.md")
    }

    @Test(arguments: [
        ("a short sentence", "Plate 7 drifts after the midpoint.", "Plate 7 drifts after the midpoint"),
        ("a long one: eight words, then an ellipsis", "Plate 7 drifts after the midpoint, and the edge wells run low.",
         "Plate 7 drifts after the midpoint, and the\u{2026}"),
        ("the first line only", "Plate map notes\nThe edge wells run low and the centre does not.", "Plate map notes"),
        ("a heading's marks off", "## Plate 7: a drift\nMore.", "Plate 7 a drift"),
        ("a list item's", "- the edge wells run low", "the edge wells run low"),
        ("a quote's and its bold", "> **Plate 7** drifts", "Plate 7 drifts"),
        ("a link's words", "[the protocol](https://example.com/p) says so", "the protocol says so"),
        ("a path's slashes", "results/plate7/summary.csv holds it", "results plate7 summary.csv holds it"),
        ("blank lines first", "\n\n  The first words.", "The first words"),
        ("a line of rules first", "***\nThe words.", "The words"),
        ("a trailing comma", "Plate 7 drifts,", "Plate 7 drifts"),
    ])
    func theTitleIsTheFirstWords(_ what: String, _ text: String, _ title: String) {
        #expect(ShelfSelectionNote.title(for: text, session: Made.session) == title, "\(what)")
    }

    @Test func aTitleIsNeverLongerThanItsLimit() {
        let long = "supercalifragilisticexpialidocious " + String(repeating: "x", count: 100)
        #expect(ShelfSelectionNote.title(for: long, session: Made.session).count <= ShelfSelectionNote.titleLimit + 1)
        let one = ShelfSelectionNote.title(for: String(repeating: "y", count: 200), session: Made.session)
        #expect(one.count == ShelfSelectionNote.titleLimit + 1 && one.hasSuffix("\u{2026}"))
        // Eight words of 9 letters would be 79 characters: the words that fit.
        let nines = Array(repeating: "abcdefghi", count: 9).joined(separator: " ")
        let title = ShelfSelectionNote.title(for: nines, session: Made.session)
        #expect(title.count <= ShelfSelectionNote.titleLimit + 1)
        #expect(title == Array(repeating: "abcdefghi", count: 6).joined(separator: " ") + "\u{2026}")
    }

    @Test func aPassageWithNoWordsIsNamedForItsSession() {
        #expect(ShelfSelectionNote.title(for: "***\n---\n\u{2014}", session: Made.session) == "Note from Plate reader QC")
        #expect(ShelfSelectionNote.title(for: "1 / 2", session: Made.session) == "1 2", "digits are words")
        #expect(ShelfSelectionNote.title(for: "...", session: Made.session) == "Note from Plate reader QC")
        // A session with no title is named for its project; with neither, the note is just a note.
        let untitled = SessionStatus(id: Made.session.id, projectID: "p-3", projectName: "Assay development", title: "",
                                     state: .finished, updatedAt: Date(), startedAt: nil)
        #expect(ShelfSelectionNote.title(for: "***", session: untitled) == "Note from Assay development")
        #expect(ShelfSelectionNote.title(for: "***", session: Made.unnamed) == "Note")
    }

    @Test func theTitleIsAFolderNameAsItIs() {
        for text in [Made.passage, "a/b: c", "***", "Z\u{2032} by plate", "\u{1F9EA} flask"] {
            let title = ShelfSelectionNote.title(for: text, session: Made.session)
            #expect(KeptName.sanitized(title) == title, "\(title)")
        }
    }

    @Test func theReadmeIsExactlyThis() throws {
        let sha = "0f" + String(repeating: "a", count: 62)
        let file = KeptFile(path: "note.md", role: .figure, artifact: nil, version: nil, index: nil, of: nil, sha256: sha, bytes: 112)
        let written = ShelfSelectionNote.readme(session: Made.session, folderName: "Plate 7 drifts after the midpoint, and the\u{2026}",
                                                file: file, keptAt: Made.keptAt, claudeScience: "0.1.70", capsid: "1.0.5",
                                                timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US"))
        let readme = KeptReadme.render(written.record, text: written.text, timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US"))
        let expected = """
        ---
        capsid_kept: 1
        name: "Plate 7 drifts after the midpoint, and the\u{2026}"
        kept_at: 2026-10-24T12:00:00+00:00
        project: { id: "p-3", name: "Assay development" }
        session: { id: "00000000-0000-4000-8000-0000000000c1", title: "Plate reader QC" }
        figure: { file: "note.md", sha256: "\(sha)", bytes: 112 }
        files: []
        missing: []
        claude_science: "0.1.70"
        capsid: "1.0.5"
        ---

        # Plate 7 drifts after the midpoint, and the\u{2026}

        ## Your legend

        <!-- Write the legend here, or in Capsid\u{2019}s Shelf window. -->

        ## What Claude said

        ## Where it came from

        [Plate reader QC](bench://session?project=p-3&frame=00000000-0000-4000-8000-0000000000c1), in Assay development.
        Selected in the conversation and put on your shelf on 24 October 2026 at 12:00 PM by Capsid 1.0.5, from Claude Science 0.1.70. The link opens the session in Capsid on a Mac that has it.

        ---

        Capsid updates the file lists, \u{201C}Not copied\u{201D}, \u{201C}Checksums\u{201D} and \u{201C}Your legend\u{201D} here; everything else in this file is yours.

        """
        #expect(readme == expected)
        // And it parses and renders again to the same bytes, as every README does.
        let parsed = try #require(KeptReadme.parse(readme))
        #expect(parsed.record == written.record && parsed.text == written.text)
        #expect(KeptReadme.render(parsed.record, text: parsed.text, timeZone: TimeZone(identifier: "UTC")!, locale: Locale(identifier: "en_US")) == readme)
    }

    @Test func theReadmeNamesNoReplyAndNoWordsOfClaudes() {
        let file = KeptFile(path: "note.md", role: .figure, artifact: nil, version: nil, index: nil, of: nil, sha256: nil, bytes: 5)
        let written = ShelfSelectionNote.readme(session: Made.session, folderName: "x", file: file, keptAt: Made.keptAt, claudeScience: nil, capsid: "")
        #expect(written.record.sourceRow == nil && written.record.question == nil && written.record.answerAt == nil)
        #expect(written.record.answerShowsVersion == nil && written.record.files.isEmpty && written.record.missing.isEmpty)
        #expect(written.text.claudeSaid.isEmpty && written.text.attribution.isEmpty && written.text.legend.isEmpty)
        #expect(written.record.claudeScience == "unknown")
        #expect(!written.text.origin.contains("by Capsid ,"))
    }
}

// MARK: Adding one

@MainActor
private final class NoteRig {
    let scratch: URL
    let root: URL
    let trash: URL
    let disk: KeptDisk
    let index: KeptIndex
    let shelf: Shelf
    private let settings = ScratchDefaults.make(prefix: "capsid-tests-notes")

    init(rootExists: Bool = true) throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-notes-\(UUID().uuidString)", directoryHint: .isDirectory)
        // A root whose parent isn't there is "The Kept folder isn't there."
        let root = rootExists ? scratch.appending(path: "Kept", directoryHint: .isDirectory)
            : scratch.appending(path: "gone/Kept", directoryHint: .isDirectory)
        let trash = scratch.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        self.scratch = scratch
        self.root = root
        self.trash = trash
        let disk = KeptDisk(root: { root }, trash: { folder in
            let target = trash.appending(path: "\(UUID().uuidString) \(folder.lastPathComponent)", directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: folder, to: target)
            return target
        })
        self.disk = disk
        index = KeptIndex(disk: disk, root: { root })
        let defaults = settings.defaults
        shelf = Shelf(index: index, dependencies: {
            ShelfDependencies(
                keep: KeepDependencies(
                    read: { _ in .answered(.unreadable) },
                    showing: { _, _, _ in Issue.record("a note asks Claude Science nothing"); return .unreadable },
                    lastAnswer: { _ in Issue.record("a note asks Claude Science nothing"); return nil },
                    thumbnails: ShelfThumbnails(),
                    disk: disk, defaults: defaults, root: { root },
                    scienceVersion: { "0.1.70" }, capsidVersion: "1.0.5",
                    now: { Made.keptAt },
                    didKeep: { _ in }),
                question: { _, _ in Issue.record("a note asks Claude Science nothing"); return nil })
        })
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        settings.discard()
    }

    func names(in collection: String = "Assay development") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: collection).path)) ?? []).sorted()
    }
}

@MainActor
struct ShelfSelectionNoteAddTests {
    private func note(_ text: String = Made.passage, session: SessionStatus = Made.session) -> ShelfSelectionNote {
        ShelfSelectionNote(session: session, text: ShelfSelectionNote.clean(text)!)
    }

    @Test func aNoteIsAFolderWithTheWordsAndAReadmeAndNothingElse() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        let outcome = await rig.shelf.addNote(note())
        guard case .added(let placement) = outcome else { Issue.record("\(outcome)"); return }
        #expect(placement.name == "Plate 7 drifts after the midpoint, and the\u{2026}")
        #expect(placement.collection == "Assay development")
        #expect(rig.names() == ["Plate 7 drifts after the midpoint, and the\u{2026}"])
        let folder = placement.folder
        #expect(folder.lastPathComponent == "Plate 7 drifts after the midpoint, and the\u{2026}")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(files == ["README.md", "note.md"])
        // The words, byte for byte, with the line end the file ends on.
        let words = try String(contentsOf: folder.appending(path: "note.md"), encoding: .utf8)
        #expect(words == Made.passage + "\n")
        // The README is what the rules make of this session and these words.
        let bytes = Data(words.utf8)
        let file = KeptFile(path: "note.md", role: .figure, artifact: nil, version: nil, index: nil, of: nil,
                            sha256: KeptDisk.sha256(of: bytes), bytes: bytes.count)
        let written = ShelfSelectionNote.readme(session: Made.session, folderName: folder.lastPathComponent, file: file,
                                                keptAt: Made.keptAt, claudeScience: "0.1.70", capsid: "1.0.5")
        let expected = KeptReadme.render(written.record, text: written.text)
        let readme = try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8)
        #expect(readme == expected)
        #expect(readme.contains("[Plate reader QC](bench://session?project=p-3&frame=00000000-0000-4000-8000-0000000000c1)"))
        #expect(!readme.contains("drifts after the midpoint, and the edge"), "the words are in note.md, not repeated in the README")
    }

    @Test func theReadmeParsesLikeAnyOtherAndRoundTripsToTheSameBytes() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added(let placement) = await rig.shelf.addNote(note()) else { Issue.record("not added"); return }
        let markdown = try String(contentsOf: placement.folder.appending(path: "README.md"), encoding: .utf8)
        let parsed = try #require(KeptReadme.parse(markdown))
        #expect(KeptReadme.render(parsed.record, text: parsed.text) == markdown)
        #expect(parsed.record.figure.path == "note.md" && parsed.record.figure.version == nil && parsed.record.figure.artifact == nil)
        #expect(parsed.record.sessionID == Made.session.id && parsed.record.projectID == "p-3")
        #expect(parsed.record.keptAt == Made.keptAt)
        #expect(parsed.record.claudeScience == "0.1.70" && parsed.record.capsid == "1.0.5")
        // And the disk reads the folder as it reads every kept folder.
        let read = try await rig.disk.readme(at: placement.folder)
        #expect(read.record == parsed.record && read.text == parsed.text)
        let scanned = try await rig.disk.scan()
        #expect(scanned.map(\.folder.path) == [placement.folder.path])
        #expect(scanned.first?.record.name == "Plate 7 drifts after the midpoint, and the\u{2026}")
    }

    @Test func itIsADocumentCardOnTheShelfWithNoVersionAndItsFirstLines() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added = await rig.shelf.addNote(note()) else { Issue.record("not added"); return }
        let items = ShelfRules.items(from: rig.index.results)
        let item = try #require(items.first)
        #expect(items.count == 1 && item.kind == .document)
        #expect(item.fileName == "note.md" && item.version == nil)
        #expect(item.title == "Plate 7 drifts after the midpoint, and the\u{2026}")
        #expect(item.nameParts.ext == "", "a title that isn't the file's name is never split")
        #expect(!item.canKeepWithDataAndCode, "no version to keep with its data and code")
        #expect(ShelfActions.keepSubject(item) == nil)
        #expect(item.record.sourceRow == nil && item.record.question == nil)
        #expect(ShelfRules.sourceLine(for: item) == "Plate reader QC \u{00B7} Assay development")
        #expect(ShelfRules.askedLine(for: item) == nil && ShelfRules.lastAnswerNote(for: item) == nil)
        #expect(rig.shelf.count == 1)
        // The card's lines are the note's first: Quick Look's page of them is too small to read.
        let first = try String(contentsOf: item.fileURL, encoding: .utf8)
        guard case .document(let title, let paragraphs)? = ShelfPeek.make(text: first, fileName: item.fileName) else {
            Issue.record("no peek")
            return
        }
        #expect(title == nil)
        #expect(paragraphs.first == "Plate 7 drifts after the midpoint, and the edge wells run low.")
        #expect(paragraphs.count == 2)
    }

    @Test func theShelfsSearchFindsItByItsFirstWordsItsSessionAndItsProject() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added = await rig.shelf.addNote(note()) else { Issue.record("not added"); return }
        _ = await rig.shelf.addNote(note("Reagent lot 12 expires in March.", session: Made.session))
        let items = ShelfRules.items(from: rig.index.results)
        #expect(items.count == 2)
        func found(_ query: String, project: String? = nil) -> [String] { ShelfRules.matching(items, project: project, query: query).map(\.title) }
        #expect(found("midpoint") == ["Plate 7 drifts after the midpoint, and the\u{2026}"])
        #expect(found("DRIFTS plate") == ["Plate 7 drifts after the midpoint, and the\u{2026}"])
        #expect(found("reagent").count == 1)
        #expect(found("Plate reader").count == 2, "the session")
        #expect(found("assay development").count == 2, "the project")
        #expect(found("midpoint", project: "Assay development").count == 1)
        #expect(found("midpoint", project: "Another project").isEmpty)
        #expect(found("zebrafish").isEmpty)
        // The chips count it as a document.
        let counts = ShelfRules.counts(of: items)
        #expect(counts.documents == 2 && counts.figures == 0 && counts.tables == 0 && counts.all == 2)
    }

    @Test func itExportsToPdfAsADocumentWithItsWordsAsText() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added = await rig.shelf.addNote(note()) else { Issue.record("not added"); return }
        let item = try #require(ShelfRules.items(from: rig.index.results).first)
        let text = try String(contentsOf: item.fileURL, encoding: .utf8)
        let page = ShelfPDFRules.page(for: item, text: text)
        #expect(page.title == "Plate 7 drifts after the midpoint, and the\u{2026}")
        guard case .text(let blocks) = page.picture else { Issue.record("\(page.picture)"); return }
        #expect(!blocks.isEmpty)
        #expect(page.legend.isEmpty, "no words of Claude's to take for a legend, and the words are not said twice")
        #expect(page.source.hasPrefix("Plate reader QC \u{00B7} Assay development \u{00B7} 24 Oct 2026"))
        #expect(page.tile.label == "MD" && page.tile.detail.hasPrefix("Document"))
    }

    @Test func undoTakesTheFolderToTheTrashAndOffTheShelf() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added(let placement) = await rig.shelf.addNote(note()) else { Issue.record("not added"); return }
        #expect(rig.shelf.count == 1)
        #expect(await rig.shelf.undo(placement))
        #expect(rig.names().isEmpty, "the folder is gone from the collection")
        let trashed = (try? FileManager.default.contentsOfDirectory(atPath: rig.trash.path)) ?? []
        #expect(trashed.count == 1 && trashed[0].hasSuffix("Plate 7 drifts after the midpoint, and the\u{2026}"), "and in the Trash, not deleted")
        await rig.index.refreshAndWait()
        #expect(ShelfRules.items(from: rig.index.results).isEmpty)
        #expect(rig.shelf.count == 0)
        // Through the toast, as the user sees it.
        guard case .added(let again) = await rig.shelf.addNote(note()) else { Issue.record("not added again"); return }
        let toast = ShelfToastModel(shelf: ShelfAccess(contains: { _ in false }, count: { 0 }, add: { _ in .failed("") },
                                                       undo: { await rig.shelf.undo($0) }),
                                    sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, announce: { _ in })
        toast.show(.added(again))
        await toast.undo()
        #expect(toast.state == .undone("Plate 7 drifts after the midpoint, and the\u{2026}"))
        #expect(rig.names().isEmpty)
    }

    @Test func theSameWordsFromTheSameSessionAreOnTheShelfAlready() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added(let first) = await rig.shelf.addNote(note()) else { Issue.record("not added"); return }
        let again = await rig.shelf.addNote(note())
        guard case .alreadyOnShelf(let there) = again else { Issue.record("\(again)"); return }
        #expect(there.folder.path == first.folder.path)
        #expect(rig.names().count == 1)
        // The same words in another session are another note; so are other words in this one.
        let elsewhere = await rig.shelf.addNote(note(session: Made.unnamed))
        guard case .added = elsewhere else { Issue.record("\(elsewhere)"); return }
        #expect(rig.names(in: "Shelf").count == 1 && rig.names().count == 1)
        guard case .added = await rig.shelf.addNote(note("Reagent lot 12 expires in March.")) else { Issue.record("other words"); return }
        #expect(rig.names().count == 2)
    }

    @Test func twoAsksAtOnceMakeOneNote() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        async let first = rig.shelf.addNote(note())
        async let second = rig.shelf.addNote(note())
        let (a, b) = await (first, second)
        #expect(a == b)
        #expect(rig.names().count == 1)
    }

    @Test func twoNotesWithOneBeginningGetFoldersApartFromOneAnother() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added(let one) = await rig.shelf.addNote(note("Plate 7 drifts after the midpoint and the edge wells run low.")) else {
            Issue.record("one")
            return
        }
        guard case .added(let two) = await rig.shelf.addNote(note("Plate 7 drifts after the midpoint and the edge wells hold.")) else {
            Issue.record("two")
            return
        }
        #expect(one.name == two.name, "the first eight words are the same")
        #expect(one.folder != two.folder)
        #expect(rig.names().count == 2)
        #expect(KeptName.isDated(two.folder.lastPathComponent), "the second is told apart by the date, as any keep is")
        let items = ShelfRules.items(from: rig.index.results)
        #expect(items.count == 2, "each a card of its own")
    }

    @Test func aPassageWithNoWordsIsANoteFromItsSession() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added(let placement) = await rig.shelf.addNote(note("***")) else { Issue.record("not added"); return }
        #expect(placement.name == "Note from Plate reader QC")
        #expect(rig.names() == ["Note from Plate reader QC"])
    }

    @Test func aSessionWithNoProjectNameGoesInTheShelfCollection() async throws {
        let rig = try NoteRig()
        defer { rig.tearDown() }
        guard case .added(let placement) = await rig.shelf.addNote(note(session: Made.unnamed)) else { Issue.record("not added"); return }
        #expect(placement.collection == "Shelf")
    }

    @Test func aKeptFolderThatIsntThereIsASentenceAndLeavesNothingBehind() async throws {
        let rig = try NoteRig(rootExists: false)
        defer { rig.tearDown() }
        let outcome = await rig.shelf.addNote(note())
        guard case .failed(let sentence) = outcome else { Issue.record("\(outcome)"); return }
        #expect(sentence.hasPrefix("Couldn\u{2019}t add Plate 7 drifts after the midpoint, and the\u{2026} to your shelf."))
        #expect(!sentence.contains("edge wells"), "the sentence has the title and no more of the words")
        #expect(!FileManager.default.fileExists(atPath: rig.root.path))
    }

    @Test func theWordsAreNeverLogged() throws {
        // Every logging line of the files that handle the words interpolates a count at most: never the words,
        // the note, the selection or the title made from them.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let interpolation = try NSRegularExpression(pattern: #"\\\(([^)]*)\)"#)
        var seen = 0
        for file in ["Kept/Shelf.swift", "Shelf/ConversationMenu.swift", "Kept/ShelfSelectionNote.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/Bench/\(file)"), encoding: .utf8)
            for line in source.split(separator: "\n") where line.contains("log.notice(") || line.contains("log.info(") || line.contains("log.error(")
                || line.contains("log.debug(") || line.contains("print(") || line.contains("NSLog(") {
                seen += 1
                let text = String(line)
                for match in interpolation.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range(at: 1), in: text) else { continue }
                    let inside = String(text[range])
                    let allowed = inside.contains(".count") || inside.hasPrefix("line,") || inside.hasPrefix("KeptDiskError.sentence")
                    #expect(allowed, "\(file): \(text)")
                }
            }
        }
        #expect(seen >= 3, "the scan saw the logging lines it is for")
        let shelf = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Kept/Shelf.swift"), encoding: .utf8)
        #expect(shelf.contains("Put a note on the shelf, \\(note.text.count) characters"))
    }
}
