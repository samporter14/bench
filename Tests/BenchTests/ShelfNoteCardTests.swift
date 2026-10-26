// ShelfNoteCardTests.swift — a note's detail card after the polish (Kept/ShelfView.swift,
// ShelfRules.swift, ShelfPassage.swift). A note, the words selected in a conversation and
// shelved (`note.md`, no version), used to show them three times on its card: as a picture
// of its first lines, as a title of its first words, and whole. Now its card is one quiet
// header ("Note · Plate reader QC · Assay development · 11:12 AM"), the passage set as a
// quotation, and the three controls; the picture's drag and Quick Look stay reachable
// (the header, ⋯, the grid card); an ordinary document, figure or table keeps its card;
// and a note whose words can't be read is drawn as a document is. The rules are pure and
// made up here; the card's wiring is read from the source, as ShelfDaysTests does; the
// disk work uses a folder made for each test and a private pasteboard.
import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import Vision
@testable import Bench

private let root = URL(fileURLWithPath: "/tmp/kept-note-card", isDirectory: true)
/// 22 October 2026, 13:12 UTC.
private let kept = Date(timeIntervalSince1970: 1_792_674_720)
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
private let english = Locale(identifier: "en_US")

private func result(_ file: String, folder: String = "Plate 7 drifts", version: String? = nil, session: String = "Plate reader QC",
                    project: String = "Assay development", at: Date = kept, in parent: URL = root) -> KeptResult {
    let record = KeptRecord(
        name: folder, keptAt: at, projectID: "p", projectName: project, sessionID: "s", sessionTitle: session,
        figure: KeptFile(path: file, role: .figure, artifact: nil, version: version, index: nil, of: nil, sha256: nil, bytes: 10),
        files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0")
    return KeptResult(folder: parent.appending(path: "\(project)/\(folder)", directoryHint: .isDirectory), collection: project,
                      record: record, text: KeptText(legend: "", claudeSaid: "", attribution: "", origin: ""))
}

private func note(session: String = "Plate reader QC", project: String = "Assay development", at: Date = kept,
                  in parent: URL = root) -> ShelfItem {
    ShelfRules.items(from: [result("note.md", session: session, project: project, at: at, in: parent)])[0]
}

/// What the card says of when: the card's own words for the moment.
private func time(_ date: Date = kept, now: Date) -> String { ShelfRules.when(date, now: now, calendar: utc, locale: english) }

/// The text of `source` from the first `start` to the first `end` after it.
private func slice(_ source: String, from start: String, to end: String) -> String {
    guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { return "" }
    return String(source[a.lowerBound..<b.lowerBound])
}

// MARK: The header's words

struct ShelfNoteHeaderTests {
    private let now = kept.addingTimeInterval(3_600)

    private func header(_ item: ShelfItem) -> String { ShelfRules.noteHeader(for: item, now: now, calendar: utc, locale: english) }

    @Test func theHeaderSaysItIsANoteThenTheSessionTheProjectAndWhenItWasShelved() {
        let moment = time(now: now)
        #expect(moment.contains("1:12"), "today: the time, as the grid card's caption has it")
        #expect(header(note()) == "Note \u{00B7} Plate reader QC \u{00B7} Assay development \u{00B7} \(moment)")
        #expect(ShelfRules.noteHeaderParts(for: note(), now: now, calendar: utc, locale: english)
                == ["Note", "Plate reader QC", "Assay development", moment])
    }

    @Test func aNoteWithNoProjectLeavesItOutWithoutAGap() {
        #expect(header(note(project: "")) == "Note \u{00B7} Plate reader QC \u{00B7} \(time(now: now))")
        #expect(header(note(project: "  \n")) == "Note \u{00B7} Plate reader QC \u{00B7} \(time(now: now))", "blank is none")
    }

    @Test func aMissingTimeIsLeftOutToo() {
        #expect(ShelfRules.noteHeaderParts(session: "Plate reader QC", project: "Assay development", at: nil)
                == ["Note", "Plate reader QC", "Assay development"])
        #expect(ShelfRules.noteHeaderParts(session: "Plate reader QC", project: "", at: nil) == ["Note", "Plate reader QC"])
    }

    @Test func aMissingSessionIsLeftOutAndNothingKnownIsJustNote() {
        #expect(header(note(session: "")) == "Note \u{00B7} Assay development \u{00B7} \(time(now: now))")
        #expect(ShelfRules.noteHeaderParts(session: "", project: "", at: nil) == ["Note"])
        #expect(ShelfRules.noteHeaderParts(session: " ", project: "\t", at: nil) == ["Note"])
    }

    /// The time is the moment the card's caption gives: today the clock, yesterday "Yesterday", this week the weekday,
    /// else the day.
    @Test func theTimeIsTheGridCardsOwnWords() {
        let item = note()
        let offsets: [TimeInterval] = [3_600, 86_400 + 3_600, 3 * 86_400, 40 * 86_400]
        for later in offsets {
            let at = kept.addingTimeInterval(later)
            let caption = ShelfRules.caption(for: item, now: at, calendar: utc, locale: english)
            let line = ShelfRules.noteHeader(for: item, now: at, calendar: utc, locale: english)
            #expect(caption.hasSuffix(time(now: at)))
            #expect(line.hasSuffix(time(now: at)), "\(line)")
        }
        #expect(time(now: kept.addingTimeInterval(86_400 + 3_600)) == "Yesterday")
        #expect(time(now: kept.addingTimeInterval(40 * 86_400)) == "Oct 22")
    }

    @Test func theHeaderSaysNoneOfThePassageOrTheTitleBuiltFromIt() {
        // The title of a note is its first words; the header must not say them again (nor the file's name).
        let words = "Plate 7 drifts after the midpoint, and the edge wells run low."
        let session = SessionStatus(id: "s", projectID: "p", projectName: "Assay development", title: "Plate reader QC", state: .finished,
                                    updatedAt: kept)
        let title = ShelfSelectionNote.title(for: words, session: session)
        #expect(title.hasPrefix("Plate 7 drifts"))
        let line = header(note())
        #expect(!line.contains("drifts") && !line.contains(title) && !line.contains("note.md"))
    }

    @Test func voiceOverReadsTheSamePartsWithCommas() {
        let spoken = ShelfRules.noteHeaderSpoken(for: note(), now: now, calendar: utc, locale: english)
        #expect(spoken == "Note, Plate reader QC, Assay development, \(time(now: now))")
        #expect(!spoken.contains("\u{00B7}"))
    }
}

// MARK: The ⋯ menu

struct ShelfNoteMenuTests {
    @Test func aNotesMenuOpensWithTheTwoThingsItsPictureDidToTheFile() {
        let menu = ShelfRules.moreMenu(canKeep: false, note: true)
        #expect(menu == [.quickLook, .showInFinder, .divider, .exportPDF, .divider, .remove])
        #expect(menu.map(\.title) == ["Quick Look", "Show in Finder", "", "Export Figure as PDF\u{2026}", "", "Remove"])
        #expect(!menu.contains(.keepWithDataAndCode), "a note has no version to keep")
        #expect(ShelfRules.moreMenu(canKeep: true, note: true) == menu, "and never offered it")
    }

    @Test func everyOtherItemsMenuIsAsItWas() {
        #expect(ShelfRules.moreMenu(canKeep: true) == [.keepWithDataAndCode, .exportPDF, .divider, .remove])
        #expect(ShelfRules.moreMenu(canKeep: false) == [.exportPDF, .divider, .remove])
        #expect(ShelfRules.moreMenu(canKeep: true, note: false) == ShelfRules.moreMenu(canKeep: true))
        #expect(!ShelfRules.moreMenu(canKeep: true).contains(.quickLook) && !ShelfRules.moreMenu(canKeep: false).contains(.showInFinder))
    }

    @Test func voiceOverOffersTheNewItemsWithoutEllipses() {
        #expect([ShelfRules.MoreItem.quickLook, .showInFinder].map(\.spoken) == ["Quick Look", "Show in Finder"])
    }
}

// MARK: Which card, and what a card has to go on

struct ShelfNoteFormTests {
    private func form(_ item: ShelfItem, _ reading: ShelfPassages.Reading) -> ShelfDetail.Form { ShelfDetail.form(for: item, reading: reading) }

    @Test func aNoteIsDrawnAsANoteWhenItsWordsAreReadAndWhileTheyAreBeingRead() {
        #expect(form(note(), .words("Plate 7 drifts.")) == .note)
        #expect(form(note(), .notYet) == .note, "no picture and no title in the moment before the words arrive")
    }

    @Test func aNoteWithNoWordsIsDrawnAsAnyDocumentIsWithItsPictureAndName() {
        #expect(form(note(), .none) == .ordinary)
    }

    @Test func aDocumentAFigureAndATableKeepTheirCard() {
        let document = ShelfRules.items(from: [result("qc_notes.md", folder: "qc_notes")])[0]
        let numbered = ShelfRules.items(from: [result("note.md", folder: "note", version: "v-3")])[0]
        let figure = ShelfRules.items(from: [result("z_prime.png", folder: "z_prime", version: "v-1")])[0]
        let table = ShelfRules.items(from: [result("receptors.xlsx", folder: "receptors", version: "v-1")])[0]
        for item in [document, numbered, figure, table] {
            for reading in [ShelfPassages.Reading.notYet, .words("anything"), .none] {
                #expect(form(item, reading) == .ordinary, "\(item.fileName), \(reading)")
            }
        }
    }

    /// A note's card has no picture, so its menu has Quick Look and Show in Finder; one drawn as a document's has the
    /// picture, and a document's menu.
    @Test func theMenuFollowsTheCardNotTheFile() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        #expect(view.contains("ShelfRules.moreMenu(canKeep: item.canKeepWithDataAndCode, note: drawsAsNote)"))
        #expect(view.contains("private var drawsAsNote: Bool { Self.form(for: item, reading: reading) == .note }"))
    }
}

// MARK: Reading a note's words, and not finding them

@MainActor
struct ShelfNoteReadingTests {
    private final class Files: @unchecked Sendable {
        private let lock = NSLock()
        private var files: [String: (text: String?, modified: Double, putAway: Bool)] = [:]
        private var failing = false

        func set(_ item: ShelfItem, _ text: String?, modified: Double = 1_000, putAway: Bool = false) {
            lock.withLock { files[item.fileURL.path] = (text, modified, putAway) }
        }

        func fail(_ on: Bool) { lock.withLock { failing = on } }

        func inspect(_ url: URL) -> KeptFileFacts? {
            lock.withLock {
                files[url.path].map { KeptFileFacts(modified: Date(timeIntervalSince1970: $0.modified), size: ($0.text ?? "").utf8.count, putAway: $0.putAway) }
            }
        }

        func text(_ url: URL) throws -> String? {
            try lock.withLock {
                if failing { throw CocoaError(.fileReadUnknown) }
                return files[url.path]?.text
            }
        }
    }

    private func store(_ files: Files) -> ShelfPassages {
        ShelfPassages(inspect: { files.inspect($0) }, read: { try files.text($0) })
    }

    @Test func aNoteIsNotYetReadThenHasItsWords() async {
        let files = Files()
        let held = note()
        files.set(held, "Plate 7 drifts.\n")
        let passages = store(files)
        #expect(passages.reading(for: held) == .notYet)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .words("Plate 7 drifts."))
        #expect(passages.text(for: held) == "Plate 7 drifts.", "the text the card shows is the one the reading holds")
    }

    @Test func aNoteWhoseFileIsGonePutAwayOrEmptyHasNoWordsAndOneThatIsBackHasThemAgain() async {
        let files = Files()
        let held = note()
        let passages = store(files)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .none, "no such file")

        files.set(held, "Plate 7 drifts.\n", modified: 2_000, putAway: true)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .none, "put away in iCloud")

        files.set(held, "\n \n", modified: 3_000)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .none, "nothing in it")

        files.set(held, "Plate 7 drifts.\n", modified: 4_000)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .words("Plate 7 drifts."))

        files.set(held, "", modified: 5_000)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .none, "words held before go when the file has none")
    }

    @Test func aDiskThatDoesNotAnswerIsADocumentsCardUnlessWordsWereHeld() async {
        let files = Files()
        let held = note()
        files.set(held, "Plate 7 drifts.\n")
        files.fail(true)
        let passages = store(files)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .none, "nothing held: not a note's card with a blank where the words go")
        files.fail(false)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .words("Plate 7 drifts."))

        files.set(held, "Plate 8 drifts.\n", modified: 2_000)
        files.fail(true)
        await passages.look(at: held)
        #expect(passages.reading(for: held) == .words("Plate 7 drifts."), "what was held stays")
    }

    @Test func nothingButANoteHasAReading() async {
        let files = Files()
        let document = ShelfRules.items(from: [result("qc_notes.md", folder: "qc_notes")])[0]
        files.set(document, "# Plate 7")
        let passages = store(files)
        await passages.look(at: document)
        #expect(passages.reading(for: document) == .none)
    }

    @Test func aFewWordlessNotesAreRememberedAndTheRestGoBackToNotYet() async {
        let files = Files()
        let passages = store(files)
        let notes = (0...ShelfPassages.remembered).map { note(session: "S\($0)", in: URL(fileURLWithPath: "/tmp/kept-note-card-\($0)", isDirectory: true)) }
        for held in notes { await passages.look(at: held) }
        #expect(passages.reading(for: notes[ShelfPassages.remembered]) == .none)
        #expect(passages.reading(for: notes[0]) == .notYet, "forgotten: looked at again when its card is shown")
    }
}

// MARK: What the picture did, kept

@MainActor
struct ShelfNoteReachTests {
    private func scratch(_ body: (_ kept: URL, _ disk: KeptDisk, _ board: NSPasteboard) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-note-card-\(UUID().uuidString)", directoryHint: .isDirectory)
        let kept = folder.appending(path: "Kept", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let board = NSPasteboard(name: NSPasteboard.Name("capsid-tests-note-card-\(UUID().uuidString)"))
        defer {
            try? FileManager.default.removeItem(at: folder)
            board.releaseGlobally()
        }
        try await body(kept, KeptDisk(root: { kept }), board)
    }

    private func keep(_ text: String, in kept: URL) throws -> ShelfItem {
        let made = note(in: kept)
        try FileManager.default.createDirectory(at: made.folder, withIntermediateDirectories: true)
        try ShelfSelectionNote.data(for: text).write(to: made.fileURL)
        return made
    }

    /// The header, the grid card and an ordinary item's picture all drag what `fileProvider` gives: the item's file.
    @Test func aNotesDragCarriesItsFile() async throws {
        try await scratch { kept, _, _ in
            let held = try keep("Plate 7 drifts.", in: kept)
            let provider = ShelfActions.fileProvider(for: held)
            #expect(!provider.registeredTypeIdentifiers.isEmpty, "something to drop, as the grid card's drag has always had")
            #expect(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        }
    }

    @Test func theDragAndQuickLookAreStillWiredOnTheHeaderTheMenuAndTheGridCard() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let header = slice(view, from: "struct ShelfNoteHeader: View", to: "/// A note's passage on its detail card")
        #expect(header.contains(".onDrag { ShelfActions.fileProvider(for: item) }"))
        #expect(header.contains(".onTapGesture(count: 2) { quickLook.show([item.fileURL], at: 0) }"))
        #expect(header.contains(".help(Self.help)"))
        #expect(ShelfNoteHeader.help.contains("Drag") && ShelfNoteHeader.help.contains("double-click"), "the picture's tooltip, for the note")
        // The two menu items do what the grid card's menu does.
        let perform = slice(view, from: "private func perform(_ entry: ShelfRules.MoreItem)", to: "/// A note's detail header")
        #expect(perform.contains("case .quickLook:\n            quickLook.show([item.fileURL], at: 0)"))
        #expect(perform.contains("case .showInFinder:\n            NSWorkspace.shared.activateFileViewerSelecting([item.folder])"))
        // And the card in the grid, which is drawn for a note as for any item, is as it was.
        let card = slice(view, from: "private func card(_ item: ShelfItem)", to: "// MARK: Nothing to show")
        #expect(card.contains(".onDrag { ShelfActions.fileProvider(for: item) }"))
        #expect(card.contains("Button(\"Quick Look\") { model.selection = item.id; quickLookSelected() }"))
        #expect(card.contains("Button(\"Show in Finder\") { NSWorkspace.shared.activateFileViewerSelecting([item.folder]) }"))
        #expect(card.contains(".onTapGesture(count: 2) {\n            model.selection = item.id\n            quickLookSelected()"))
        #expect(view.contains(".onKeyPress(.space) { previewSelected() ? .handled : .ignored }"))
    }

    /// What the card shows is what Copy copies: the reading the card draws and the pasteboard's text are one string.
    @Test func copyStillCopiesThePassageTheCardShows() async throws {
        try await scratch { kept, disk, board in
            let words = "Plate 7 drifts after the midpoint.\n\nRepeat it with a fresh seal.\n\n- a fresh seal"
            let held = try keep(words, in: kept)
            let passages = ShelfPassages(disk: disk)
            await passages.look(at: held)
            guard case .words(let shown) = passages.reading(for: held) else {
                Issue.record("the note's words were not read")
                return
            }
            await ShelfActions.copy(held, disk: disk, to: board).value
            #expect(board.string(forType: .string) == shown)
            #expect(shown == words)
            #expect((board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).isEmpty)
        }
    }

    /// The Copy button of a note's card is the one every card has, and still asks `ShelfActions.copy`.
    @Test func theNoteCardHasTheSameThreeControls() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let main = slice(view, from: "private var noteMain: some View", to: "private var preview: some View")
        #expect(main.contains("buttons"), "Show Where It Came From, Copy and ⋯, drawn once for every card")
        let buttons = slice(view, from: "private var buttons: some View", to: "/// What a ⋯ item (or its VoiceOver action) does.")
        #expect(buttons.contains("ShelfActions.copy(item, disk: model.index.disk)"))
        #expect(buttons.contains("SolanumPillStyle(.regular, prominent: true)"))
        #expect(buttons.components(separatedBy: "prominent: true").count == 2, "one clay action")
    }
}

// MARK: Said once

struct ShelfNoteOnceTests {
    @Test func aNotesCardHasNoPictureAndNoTitle() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let main = slice(view, from: "private var noteMain: some View", to: "private var preview: some View")
        #expect(main.contains("ShelfNoteHeader(item: item, quickLook: quickLook)"))
        #expect(main.contains("ShelfPassageText(text: passage"))
        for word in ["preview", "ShelfPaper", "ShelfName", "nameParts", "item.title", "item.fileName", "sourceLine", "askedLine"] {
            #expect(!main.contains(word), "a note's card says its words once: \(word)")
        }
        // The body chooses between the two from the rule the tests above pin.
        #expect(view.contains("switch Self.form(for: item, reading: reading) {\n                case .note: noteMain\n                case .ordinary: ordinaryMain"))
    }

    @Test func anOrdinaryCardStillHasItsPictureItsNameAndItsSourceLine() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let main = slice(view, from: "private var ordinaryMain: some View", to: "/// A note's main column")
        #expect(main.contains("preview\n"))
        #expect(main.contains("ShelfName(parts: item.nameParts, size: 17, weight: .semibold)"))
        #expect(main.contains("Text(ShelfRules.sourceLine(for: item))"))
        #expect(main.contains("minHeight: 150"))
        #expect(!main.contains("ShelfPassageText"), "words are a note's alone")
        let preview = slice(view, from: "private var preview: some View", to: "private var buttons: some View")
        #expect(preview.contains(".onDrag { ShelfActions.fileProvider(for: item) }"))
        #expect(preview.contains(".onTapGesture(count: 2) { quickLook.show([item.fileURL], at: 0) }"))
        #expect(preview.contains(".accessibilityLabel(\"Preview of \\(item.fileName)\")"))
        #expect(preview.contains(".frame(width: previewWidth, height: 150)"))
    }

    /// VoiceOver: the header is one element read with commas (its own words, so no other label repeats them), the rule
    /// is hidden, and the passage is one text.
    @Test func voiceOverReadsTheHeaderOnceAndHidesTheRule() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let header = slice(view, from: "struct ShelfNoteHeader: View", to: "/// A note's passage on its detail card")
        #expect(header.contains(".accessibilityElement(children: .ignore)"))
        #expect(header.contains(".accessibilityLabel(ShelfRules.noteHeaderSpoken(for: item))"))
        let passage = slice(view, from: "struct ShelfPassageText: View", to: "/// The detail's ⋯: a round button")
        #expect(passage.contains(".accessibilityHidden(true)"))
        #expect(passage.contains(".textSelection(.enabled)"), "selectable, so Copy and Look Up work as anywhere")
        #expect(!passage.contains(".accessibilityLabel"), "the words are the label, once")
    }
}

// MARK: The passage's look

struct ShelfPassageLookTests {
    @Test func theNarrowestWindowsCardFitsItsPassageThePaddingTheHeaderAndTheControls() {
        // 18 + header (about 15) + 14 + passage + 20 + the controls (30) + 18, no more than the window leaves the card.
        let narrowest: CGFloat = max(220, 480 * 0.56)
        let chrome: CGFloat = 18 + 15 + 14 + 20 + 30 + 18
        #expect(ShelfDetail.passageHeight(forCard: narrowest) + chrome <= narrowest + 1)
    }

    @Test func theWordsAreSetInTheReferenceWindowsReadingType() {
        #expect(Solanum.bodySize == 14 && Solanum.bodyLeading == 21)
        #expect(ShelfPassageText.measure >= 480 && ShelfPassageText.measure <= 680, "a reading width, not the card's")
        let view = FindRepo.source("Kept/ShelfView.swift")
        let passage = slice(view, from: "struct ShelfPassageText: View", to: "/// The detail's ⋯: a round button")
        #expect(passage.contains(".font(.system(size: Solanum.bodySize))"))
        #expect(passage.contains(".lineSpacing(Solanum.bodyLeading - Self.lineHeight)"))
        #expect(passage.contains(".foregroundStyle(Solanum.ink)"))
    }

    @Test func theRuleIsAStrongHairlineAndTheMutedInkWithIncreasedContrast() {
        #expect(ShelfPassageText.ruleColor(.standard) == Solanum.strong)
        #expect(ShelfPassageText.ruleColor(.increased) == Solanum.muted)
        #expect(ShelfPassageText.ruleColor(.standard) != ShelfPassageText.ruleColor(.increased))
    }

    /// The fade is a mask (it shows the card's own colour in light and dark alike), it leaves the rule out of it, and it
    /// melts away as the end arrives, with no animation to leave a mask the wrong size where nothing is on a display.
    @Test func theFadeIsAMaskOverTheWordsAloneAndGrowsWithWhatIsBelow() {
        let view = FindRepo.source("Kept/ShelfView.swift")
        let passage = slice(view, from: "struct ShelfPassageText: View", to: "/// The detail's ⋯: a round button")
        let mask = slice(passage, from: ".mask {", to: ".frame(height: min(contentHeight, maxHeight))")
        #expect(mask.contains("LinearGradient(colors: [.black, .black.opacity(1 - below)]"))
        #expect(!mask.contains(".animation"))
        let rule = slice(passage, from: ".overlay(alignment: .leading)", to: ".frame(maxWidth: Self.measure")
        #expect(rule.contains("Capsule().fill(Self.ruleColor(contrast))"))
        #expect(passage.contains("max(0, min(1, ($0.contentSize.height - $0.contentOffset.y - $0.containerSize.height) / Self.fade))"))
    }
}

// MARK: Drawn, and read back

/// The card drawn offscreen (no window, nothing on a display) and read back by the system's text recognition: how many
/// times a note's first words are on it, and that a document's picture still is. The same bitmap path as the snapshot
/// tests, in light only.
@MainActor
struct ShelfNoteRenderedTests {
    private func recognised(_ view: some View, size: CGSize) async throws -> [String] {
        let host = NSHostingView(rootView: view.frame(width: size.width).background(Solanum.raised).background(Solanum.page))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
        }
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = try #require(rep.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    @Test func aNotesFirstWordsAreOnItsCardOnceAndADocumentsPictureIsStillThere() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("note-card-render-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = KeptDisk(root: { folder })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { folder })
        let shelf = KeptDemo.shelf(index: index, root: folder)
        let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000d9", projectID: "demo-Assay development",
                                    projectName: "Assay development", title: "Plate reader QC", state: .finished, updatedAt: Date())
        let words = "Plate 7 drifts after the midpoint, and the edge wells run low.\n\nRepeat it with a fresh seal before anyone reads the other columns."
        let outcome = await shelf.addNote(ShelfSelectionNote(session: session, text: try #require(ShelfSelectionNote.clean(words))))
        guard case .added = outcome else { Issue.record("\(outcome)"); return }
        index.refresh()
        for _ in 0..<100 where index.results.count < 11 { try await Task.sleep(for: .milliseconds(50)) }
        let model = ShelfModel(shelf: shelf)
        let thumbnails = KeptThumbnails(peek: { url in (try? await disk.peek(url)) ?? nil })
        func card(_ item: ShelfItem) -> some View {
            ShelfDetail(item: item, model: model, thumbnails: thumbnails, quickLook: KeptQuickLook(), keep: {}, maxHeight: 460)
        }

        let held = try #require(model.items.first { $0.isSelectionNote })
        let noteLines = try await recognised(card(held), size: CGSize(width: 900, height: 300))
        let first = noteLines.filter { $0.localizedCaseInsensitiveContains("drifts after the mid") }
        #expect(first.count == 1, "the first words of a note are on its card once: \(noteLines)")
        #expect(noteLines.contains { $0.hasPrefix("Note") && $0.localizedCaseInsensitiveContains("Plate reader QC") }, "\(noteLines)")
        #expect(!noteLines.contains { $0.localizedCaseInsensitiveContains("note.md") })

        let document = try #require(model.items.first { $0.fileName == "qc_notes.md" })
        let documentLines = try await recognised(card(document), size: CGSize(width: 900, height: 300))
        #expect(documentLines.contains { $0.localizedCaseInsensitiveContains("qc_notes") }, "the name: \(documentLines)")
        // Only the picture of the file has its heading; the card's own words are what Claude said.
        #expect(documentLines.contains { $0.localizedCaseInsensitiveContains("Plate reader QC, 21 October") }, "its picture: \(documentLines)")
    }
}
