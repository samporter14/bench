// ShelfDocumentTests.swift — a tile of a file with no picture, known by its name
// alone (Shelf/ShelfDocuments.swift, Shelf/ConversationMenu.swift): how a name
// becomes the file of that name among a session's files (one match, none, two
// files of one name, the newest version), how the page's message is read, and
// what each of the four items does with the file once it is found, over a
// made-up session, list, shelf and toast. Nothing is read from or written to
// Claude Science.
import AppKit
import Foundation
import Testing
@testable import Bench

private func id(_ n: Int) -> String { String(format: "aaaaaaaa-0000-4000-8000-%012d", n) }

private func entry(_ name: String, version: Int, artifact: Int? = nil, at: Double? = nil, mime: String? = nil) -> ArtifactEntry {
    ArtifactEntry(version: id(version), artifact: artifact.map { "bbbbbbbb-0000-4000-8000-\(String(format: "%012d", $0))" }, name: name,
                  mime: mime, size: 1_200, at: at.map { Date(timeIntervalSince1970: 1_792_000_000 + $0) })
}

// MARK: Which file

struct ShelfDocumentResolutionTests {
    @Test func aNameWithOneFileIsThatFile() {
        let files = [entry("z_prime.png", version: 1, artifact: 1), entry("notes.md", version: 2, artifact: 2), entry("table.csv", version: 3, artifact: 3)]
        #expect(ShelfDocument.match(name: "notes.md", in: files) == .found(files[1]))
    }

    @Test func aNameNoFileHasIsNone() {
        let files = [entry("z_prime.png", version: 1, artifact: 1), entry("notes.md", version: 2, artifact: 2)]
        #expect(ShelfDocument.match(name: "plan.md", in: files) == .none)
        #expect(ShelfDocument.match(name: "notes.md", in: []) == .none)
    }

    @Test func aNameIsMatchedWholeAndExactly() {
        let files = [entry("notes.md", version: 1, artifact: 1), entry("Notes v2.md", version: 2, artifact: 2)]
        #expect(ShelfDocument.match(name: "Notes.md", in: files) == .none, "another case is another file")
        #expect(ShelfDocument.match(name: "notes", in: files) == .none, "a part of a name is not the name")
        #expect(ShelfDocument.match(name: "notes.md ", in: files) == .none)
        #expect(ShelfDocument.match(name: "Notes v2.md", in: files) == .found(files[1]))
    }

    @Test func twoDifferentFilesOfOneNameAreTwoAndNeitherIsPicked() {
        let files = [entry("notes.md", version: 1, artifact: 1, at: 10), entry("notes.md", version: 2, artifact: 2, at: 99)]
        #expect(ShelfDocument.match(name: "notes.md", in: files) == .several)
        // Listed without artifact ids they can't be told apart, so each is its own file.
        let bare = [entry("notes.md", version: 1, at: 10), entry("notes.md", version: 2, at: 99)]
        #expect(ShelfDocument.match(name: "notes.md", in: bare) == .several)
        // Three files, two of which share a name: only that name is in doubt.
        let mixed = files + [entry("plan.md", version: 3, artifact: 3)]
        #expect(ShelfDocument.match(name: "plan.md", in: mixed) == .found(mixed[2]))
        #expect(ShelfDocument.match(name: "notes.md", in: mixed) == .several)
    }

    @Test func oneFileListedAtSeveralVersionsIsThatFilesNewest() {
        let older = entry("notes.md", version: 1, artifact: 7, at: 10)
        let newest = entry("notes.md", version: 2, artifact: 7, at: 90)
        let middle = entry("notes.md", version: 3, artifact: 7, at: 50)
        // In any order in the list: the latest time wins.
        for files in [[older, newest, middle], [newest, middle, older], [middle, newest, older]] {
            #expect(ShelfDocument.match(name: "notes.md", in: files) == .found(newest))
        }
        // A version with no time is older than any with one; among those with none the later in the list wins.
        let untimed = entry("notes.md", version: 4, artifact: 7)
        #expect(ShelfDocument.match(name: "notes.md", in: [untimed, older]) == .found(older))
        let untimedLater = entry("notes.md", version: 5, artifact: 7)
        #expect(ShelfDocument.match(name: "notes.md", in: [untimed, untimedLater]) == .found(untimedLater))
        // The same time: the later in the list (the list is oldest first).
        let tie = entry("notes.md", version: 6, artifact: 7, at: 90)
        #expect(ShelfDocument.match(name: "notes.md", in: [newest, tie]) == .found(tie))
    }

    @Test func aFilesOwnFactsComeFromTheListNotFromAGuess() {
        let listed = entry("notes.md", version: 2, artifact: 2, at: 5, mime: "text/markdown")
        guard case .found(let found) = ShelfDocument.match(name: "notes.md", in: [listed]) else { Issue.record("not found"); return }
        #expect(found.version == id(2) && found.artifact == listed.artifact && found.mime == "text/markdown" && found.size == 1_200)
        #expect(found.kind == .markdown)
    }

    @Test func aNameFromATileIsAFileName() {
        #expect(ShelfDocument.name(hint: "notes.md") == "notes.md")
        #expect(ShelfDocument.name(hint: "  results/qc summary.csv  ") == "qc summary.csv")
        #expect(ShelfDocument.name(hint: "outputs\\notes.md") == "notes.md")
        #expect(ShelfDocument.name(hint: "line one.md\nline two") == "line one.md")
        #expect(ShelfDocument.name(hint: "no\u{0007}tes.md") == "notes.md")
        #expect(ShelfDocument.name(hint: String(repeating: "a", count: 400))?.count == 255)
        for empty in ["", "   ", "/", "\n", "\u{0007}"] {
            #expect(ShelfDocument.name(hint: empty) == nil, "\(empty.debugDescription)")
        }
        // A path that ends in a slash names its last part: "a" is a name.
        #expect(ShelfDocument.name(hint: "a/") == "a")
    }

    @Test func theSentencesNameTheFileAndSayWhatToDo() {
        #expect(ShelfDocument.notFound("notes.md") == "Capsid couldn\u{2019}t find \u{201C}notes.md\u{201D} among this conversation\u{2019}s files.")
        #expect(ShelfDocument.several("notes.md").contains("more than one file called \u{201C}notes.md\u{201D}"))
        #expect(ShelfDocument.several("notes.md").hasSuffix("Results lists them."))
        #expect(ShelfDocument.unreadable.contains("couldn\u{2019}t read"))
    }
}

// MARK: The page's message

@MainActor
struct ShelfDocumentMessageTests {
    private func body(_ action: String = "addToShelf", name: Any? = "notes.md", kind: Any? = "document", version: Any? = nil) -> [String: Any] {
        var body: [String: Any] = ["action": action]
        if let name { body["name"] = name }
        if let kind { body["kind"] = kind }
        if let version { body["version"] = version }
        return body
    }

    @Test func aMessageNamesTheActionAndTheFile() {
        for action in ConversationAction.allCases {
            let choice = ConversationMenuMessage.documentChoice(in: body(action.rawValue))
            #expect(choice == .init(action: action, name: "notes.md"))
        }
    }

    @Test func aFiguresMessageIsNotADocuments() {
        // With a version it is a figure's, read by `choice(in:)`, which a document's never is.
        let figure = body(version: ShelfAddressTests.version)
        #expect(ConversationMenuMessage.documentChoice(in: figure) == nil)
        #expect(ConversationMenuMessage.choice(in: figure) != nil)
        #expect(ConversationMenuMessage.choice(in: body()) == nil)
    }

    @Test func anythingElseIsNoDocumentChoice() {
        #expect(ConversationMenuMessage.documentChoice(in: body("delete")) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: body(kind: "image")) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: body(kind: nil)) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: body(name: nil)) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: body(name: "   ")) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: body(name: 5)) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: body(name: ["notes.md"])) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: "addToShelf") == nil)
        #expect(ConversationMenuMessage.documentChoice(in: nil) == nil)
        #expect(ConversationMenuMessage.documentChoice(in: ["trace": ["contextmenu"]]) == nil)
    }

    @Test func aLongOrOddNameIsCleanedBeforeItIsUsed() {
        #expect(ConversationMenuMessage.documentChoice(in: body(name: "reports/q3\u{0007} notes.md"))?.name == "q3 notes.md")
        let long = ConversationMenuMessage.documentChoice(in: body(name: String(repeating: "x", count: 5_000)))
        #expect(long?.name.count == ShelfDocument.nameLimit, "cut to 300 by the reader, then to a file name's 255")
    }

    // MARK: Hearing it

    private func menu(accepting: Bool = true, runs: @escaping @MainActor (ConversationAction, String) -> Void) -> ConversationMenu {
        ConversationMenu(daemonPort: { 8123 }, breadcrumbs: CompatBreadcrumbs(), traced: { _ in }, runDocument: runs,
                         run: { _, _ in Issue.record("a document is no figure") })
    }

    @Test func aChoiceFromTheMainWindowsPageRunsTheActionOnTheNameAtOnce() {
        var ran: [String] = []
        let shelf = menu { ran.append("\($0.rawValue):\($1)") }
        shelf.hear(body("keep"), accepted: true)
        shelf.hear(body("showInResults", name: "plan.md"), accepted: true)
        #expect(ran == ["keep:notes.md", "showInResults:plan.md"])
    }

    @Test func aChoiceFromAnyoneElseIsNothing() {
        var ran = 0
        let shelf = menu { _, _ in ran += 1 }
        shelf.hear(body(), accepted: false)
        #expect(ran == 0)
    }

    @Test func theSenderChecksAreTheTabMenusAndAnotherFramesOrWebViewsOrOriginIsRefused() {
        // `receive` hears a message only when this holds, as for every message of the script.
        #expect(TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: false, fromMainWebView: true, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: false, isDaemonOrigin: true))
        #expect(!TabMenuMessage.isAccepted(isMainFrame: true, fromMainWebView: true, isDaemonOrigin: false))
        #expect(ConversationMenu.script.contains("location.protocol !== \"http:\""))
    }

    @Test func aDocumentChoiceDoesNotSpendOrClearThePickForTheMacsMenu() {
        let clock = ContinuousClock.Instant.now
        var added = 0
        let shelf = ConversationMenu(now: { clock }, daemonPort: { 8123 }, breadcrumbs: CompatBreadcrumbs(), traced: { _ in },
                                     runDocument: { _, _ in }, run: { _, _ in added += 1 })
        let pick = ConversationPick(kind: .image, version: ShelfAddressTests.version, name: "Z prime")
        shelf.record(pick)
        shelf.hear(body(), accepted: true)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy Image", action: nil, keyEquivalent: ""))
        shelf.addItems(to: menu)
        #expect(menu.items.contains { $0.identifier == ConversationMenu.itemID }, "the pick was still there")
        #expect(added == 0)
    }
}

// MARK: What the items do

@MainActor
struct ShelfDocumentActionTests {
    static let route = ConversationShelfTests.route
    static let session = ConversationShelfTests.session

    final class Calls {
        var kept: [KeepSubject] = []
        var references: [(SessionStatus, String)] = []
        var results: [SessionStatus] = []
        var fileAsks: [String] = []
        var factsAsks: [String] = []
        var files: [ArtifactEntry]? = []
        var facts: ArtifactFacts?
        var order: [String] = []
    }

    private func make(route: NidusTaskSelection.Route? = ShelfDocumentActionTests.route)
        -> (ConversationShelf, MadeShelf, ShelfToastModel, Calls) {
        let fake = MadeShelf()
        let calls = Calls()
        let toast = ShelfToastModel(shelf: fake.access, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, announce: { _ in })
        let shelf = ConversationShelf(dependencies: .init(
            route: { route },
            session: { _ in Self.session },
            facts: { calls.factsAsks.append($0); return calls.facts },
            shelf: fake.access, toast: toast,
            keep: { calls.kept.append($0) },
            reference: { calls.references.append(($0, $1)) },
            results: { calls.results.append($0) },
            files: { calls.fileAsks.append($0); return calls.files }))
        return (shelf, fake, toast, calls)
    }

    static let notes = entry("notes.md", version: 20, artifact: 20, at: 30, mime: "text/markdown")
    static let others = [entry("z_prime.png", version: 21, artifact: 21, at: 10), entry("table.csv", version: 22, artifact: 22, at: 20)]

    @Test func addToShelfAddsTheFileOfThatNameInThisSession() async {
        let (shelf, fake, toast, calls) = make()
        calls.files = Self.others + [Self.notes]
        await shelf.run(.addToShelf, named: "notes.md")
        #expect(calls.fileAsks == [Self.session.id], "the session in the main window's files")
        #expect(fake.added.count == 1)
        let source = fake.added[0]
        #expect(source.session == Self.session)
        // The listing's own entry: its version, artifact, type and size, not a guess from the words.
        #expect(source.entry == Self.notes)
        #expect(source.entry.kind == .markdown)
        #expect(source.answer == nil && source.row == nil && source.question == nil)
        #expect(toast.state == .added(MadeShelf.placement("notes.md")))
    }

    @Test func theToastSaysAddingWhileTheListIsRead() async {
        let (shelf, fake, toast, calls) = make()
        calls.files = [Self.notes]
        fake.holding = true
        let adding = Task { await shelf.run(.addToShelf, named: "notes.md") }
        for _ in 0..<20 { await Task.yield() }
        #expect(toast.state == .adding)
        fake.release()
        await adding.value
        #expect(toast.state == .added(MadeShelf.placement("notes.md")))
    }

    @Test func aDuplicateAndAFailureAreTheShelfsOwnAnswers() async {
        let (shelf, fake, toast, calls) = make()
        calls.files = [Self.notes]
        let placement = MadeShelf.placement("notes.md")
        fake.outcome = .alreadyOnShelf(placement)
        await shelf.run(.addToShelf, named: "notes.md")
        #expect(toast.state == .already(placement))
        fake.outcome = .failed("That file is too big to put on the shelf.")
        await shelf.run(.addToShelf, named: "notes.md")
        #expect(toast.state == .failed("That file is too big to put on the shelf."))
    }

    @Test func keepWithDataAndCodeHandsTheSheetTheFileFound() async {
        let (shelf, fake, toast, calls) = make()
        calls.files = Self.others + [Self.notes]
        await shelf.run(.keep, named: "notes.md")
        #expect(calls.kept.count == 1)
        #expect(calls.kept[0].session == Self.session)
        #expect(calls.kept[0].entry.version == id(20))
        #expect(calls.kept[0].entry.name == "notes.md" && calls.kept[0].entry.mime == "text/markdown")
        #expect(calls.kept[0].selectsItsVersion && calls.kept[0].pinned == nil)
        #expect(calls.factsAsks == [id(20)], "the file's own facts, for the version found")
        #expect(fake.added.isEmpty)
        #expect(toast.state == nil)
    }

    @Test func keepUsesTheDaemonsFactsWhenItHasThem() async {
        let (shelf, _, _, calls) = make()
        calls.files = [Self.notes]
        calls.facts = ArtifactFacts(v: id(20), a: "bbbbbbbb-0000-4000-8000-000000000020", n: 3, name: "notes.md", mime: "text/markdown",
                                    size: 4_100, at: Date(timeIntervalSince1970: 1_792_000_500), sha: nil, isUpload: false, code: nil,
                                    codeCut: false, environment: nil)
        await shelf.run(.keep, named: "notes.md")
        #expect(calls.kept.first?.entry.size == 4_100)
        #expect(calls.kept.first?.entry.version == id(20))
    }

    @Test func openAsReferenceNamesTheVersionOfTheFileFound() async {
        let (shelf, fake, toast, calls) = make()
        calls.files = Self.others + [Self.notes]
        await shelf.run(.openAsReference, named: "notes.md")
        #expect(calls.references.count == 1)
        #expect(calls.references[0].0 == Self.session && calls.references[0].1 == id(20))
        #expect(fake.added.isEmpty && toast.state == nil)
    }

    @Test func showInResultsNeedsOnlyTheSessionAndAsksForNoList() async {
        let (shelf, _, toast, calls) = make()
        calls.files = []
        await shelf.run(.showInResults, named: "a file nobody has.md")
        #expect(calls.results == [Self.session])
        #expect(calls.fileAsks.isEmpty, "it acts on no file, so it does not wait for the list")
        #expect(toast.state == nil)
    }

    @Test func aNameNoFileHasIsASentenceAndNothingElse() async {
        for action in [ConversationAction.addToShelf, .keep, .openAsReference] {
            let (shelf, fake, toast, calls) = make()
            calls.files = Self.others
            await shelf.run(action, named: "notes.md")
            #expect(toast.state == .failed(ShelfDocument.notFound("notes.md")), "\(action)")
            #expect(fake.added.isEmpty && calls.kept.isEmpty && calls.references.isEmpty && calls.results.isEmpty, "\(action)")
        }
    }

    @Test func twoFilesOfOneNameAreRefusedWithASentenceAndNeitherIsUsed() async {
        for action in [ConversationAction.addToShelf, .keep, .openAsReference] {
            let (shelf, fake, toast, calls) = make()
            calls.files = [Self.notes, entry("notes.md", version: 23, artifact: 23, at: 99)]
            await shelf.run(action, named: "notes.md")
            #expect(toast.state == .failed(ShelfDocument.several("notes.md")), "\(action)")
            #expect(fake.added.isEmpty && calls.kept.isEmpty && calls.references.isEmpty && calls.factsAsks.isEmpty, "\(action)")
        }
    }

    @Test func aListThatCouldntBeReadIsASentenceToo() async {
        let (shelf, fake, toast, calls) = make()
        calls.files = nil
        await shelf.run(.addToShelf, named: "notes.md")
        #expect(toast.state == .failed(ShelfDocument.unreadable))
        #expect(fake.added.isEmpty)
    }

    @Test func aPageNotOnASessionSaysSoAndAsksNothing() async {
        let (shelf, fake, toast, calls) = make(route: nil)
        calls.files = [Self.notes]
        for action in ConversationAction.allCases {
            await shelf.run(action, named: "notes.md")
            #expect(toast.state == .failed(ConversationShelf.noSession), "\(action)")
            toast.dismiss()
        }
        #expect(fake.added.isEmpty && calls.kept.isEmpty && calls.references.isEmpty && calls.results.isEmpty && calls.fileAsks.isEmpty)
    }

    @Test func theFilesAreTheMainWindowsSessionsNotAnyOther() async {
        let (shelf, _, _, calls) = make()
        calls.files = [Self.notes]
        await shelf.run(.openAsReference, named: "notes.md")
        #expect(calls.fileAsks == [Self.route.frameID])
    }
}
