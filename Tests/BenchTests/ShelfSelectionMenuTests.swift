// ShelfSelectionMenuTests.swift — Add Selection to Shelf in the Mac's menu on
// words the user selected (Shelf/ConversationMenu.swift), on made-up menus and
// a made-up session, shelf and toast: how the page's count of selected
// characters is read and how long it is fresh, when the item is offered and
// when it is not (no selection, not a session's page, a menu with Capsid's tab
// or figure items already), where it goes in the menu, and what choosing it
// does with the words read from the page. The script that posts the count is
// run in DocumentTileScriptTests; WebKit's own menu is checked by a real
// right-click (TESTING.md).
import AppKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct ShelfSelectionMenuTests {
    static let start = ContinuousClock.Instant.now
    static let copy = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierCopy")

    /// A menu as WebKit makes one on selected text: Look Up, a rule, Copy, Share.
    private func textMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Look Up", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        copy.identifier = Self.copy
        menu.addItem(copy)
        menu.addItem(NSMenuItem(title: "Share\u{2026}", action: nil, keyEquivalent: ""))
        return menu
    }

    private func titles(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    }

    private func shelfMenu(onSession: Bool = true, now: @escaping () -> ContinuousClock.Instant = { ShelfSelectionMenuTests.start },
                           shelve: @escaping @MainActor () -> Void = {}) -> ConversationMenu {
        ConversationMenu(now: now, daemonPort: { 8123 }, breadcrumbs: CompatBreadcrumbs(), traced: { _ in },
                         isSession: { onSession }, shelveSelection: shelve, run: { _, _ in })
    }

    // MARK: The count

    @Test func aMessageSaysHowManyCharactersAreSelected() {
        #expect(ConversationMenuMessage.selection(in: ["kind": NSNull(), "selected": 62]) == 62)
        #expect(ConversationMenuMessage.selection(in: ["kind": "image", "url": "x", "selected": 1]) == 1)
    }

    @Test func anythingElseIsNoSelection() {
        #expect(ConversationMenuMessage.selection(in: ["kind": NSNull()]) == nil)
        #expect(ConversationMenuMessage.selection(in: ["selected": 0]) == nil)
        #expect(ConversationMenuMessage.selection(in: ["selected": -4]) == nil)
        #expect(ConversationMenuMessage.selection(in: ["selected": "62"]) == nil)
        #expect(ConversationMenuMessage.selection(in: ["selected": NSNull()]) == nil)
        #expect(ConversationMenuMessage.selection(in: 62) == nil)
        #expect(ConversationMenuMessage.selection(in: nil) == nil)
    }

    @Test func aCountIsFreshForASecondAndTakenOnce() {
        var target = SelectionTarget()
        let start = Self.start
        target.record(62, at: start)
        #expect(target.take(at: start + .milliseconds(900)) == 62)
        #expect(target.take(at: start + .milliseconds(901)) == nil, "taken once")
        target.record(62, at: start)
        #expect(target.take(at: start + .milliseconds(1_001)) == nil, "stale")
        target.record(nil, at: start)
        #expect(target.take(at: start) == nil)
        target.record(5, at: start + .seconds(1))
        #expect(target.take(at: start) == nil, "not from the future")
    }

    // MARK: When the item is offered

    private func offered(_ message: Any?, accepted: Bool = true, onSession: Bool = true, after: Duration = .milliseconds(200),
                         menu: NSMenu? = nil) -> NSMenu {
        var now = Self.start
        let shelf = shelfMenu(onSession: onSession, now: { now })
        shelf.hear(message, accepted: accepted)
        now = Self.start + after
        let made = menu ?? textMenu()
        shelf.addSelectionItem(to: made)
        return made
    }

    @Test func aRightClickThatLeftWordsSelectedGetsTheItemAfterCopy() {
        let menu = offered(["kind": NSNull(), "selected": 62])
        #expect(titles(menu) == ["Look Up", "-", "Copy", "Add Selection to Shelf", "Share\u{2026}"])
        #expect(menu.items[3].identifier == ConversationMenu.selectionID)
        #expect(menu.items[3].keyEquivalent == "", "no key: none is safe from the page")
    }

    @Test func aMenuWithNoCopyGetsItAtTheEndAfterARule() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Look Up", action: nil, keyEquivalent: ""))
        _ = offered(["kind": NSNull(), "selected": 3], menu: menu)
        #expect(titles(menu) == ["Look Up", "-", "Add Selection to Shelf"])
        // After a rule already, no second; and alone, no rule at all.
        let ruled = NSMenu()
        ruled.addItem(NSMenuItem(title: "Look Up", action: nil, keyEquivalent: ""))
        ruled.addItem(.separator())
        _ = offered(["kind": NSNull(), "selected": 3], menu: ruled)
        #expect(titles(ruled) == ["Look Up", "-", "Add Selection to Shelf"])
        let empty = NSMenu()
        _ = offered(["kind": NSNull(), "selected": 3], menu: empty)
        #expect(titles(empty) == ["Add Selection to Shelf"])
    }

    @Test func noSelectionNoItem() {
        #expect(titles(offered(["kind": NSNull()])) == titles(textMenu()))
        #expect(titles(offered(["kind": NSNull(), "selected": 0])) == titles(textMenu()))
        #expect(titles(offered(nil)) == titles(textMenu()))
    }

    @Test func aStaleCountIsNotUsed() {
        #expect(titles(offered(["kind": NSNull(), "selected": 62], after: .seconds(3))) == titles(textMenu()))
    }

    @Test func notOnASessionsPageNoItem() {
        #expect(titles(offered(["kind": NSNull(), "selected": 62], onSession: false)) == titles(textMenu()))
    }

    @Test func aMessageFromAnyoneElseIsNothing() {
        #expect(titles(offered(["kind": NSNull(), "selected": 62], accepted: false)) == titles(textMenu()))
    }

    @Test func aCountFromAnAcceptedMessageIsClearedByThenAnUnacceptedOne() {
        var now = Self.start
        let shelf = shelfMenu(now: { now })
        shelf.hear(["kind": NSNull(), "selected": 62], accepted: true)
        shelf.hear(["kind": NSNull(), "selected": 62], accepted: false)
        now = Self.start + .milliseconds(10)
        let menu = textMenu()
        #expect(shelf.addSelectionItem(to: menu) == false)
        #expect(titles(menu) == titles(textMenu()))
    }

    @Test func aLaterRightClickWithNoSelectionTakesTheOldCountAway() {
        var now = Self.start
        let shelf = shelfMenu(now: { now })
        shelf.hear(["kind": NSNull(), "selected": 62], accepted: true)
        shelf.hear(["kind": NSNull()], accepted: true)
        now = Self.start + .milliseconds(10)
        #expect(shelf.addSelectionItem(to: textMenu()) == false)
    }

    @Test func notTwiceAndNotInAMenuWithCapsidsItems() {
        // The count is spent by the menu it was for.
        var now = Self.start
        let shelf = shelfMenu(now: { now })
        shelf.hear(["kind": NSNull(), "selected": 62], accepted: true)
        now = Self.start + .milliseconds(10)
        let first = textMenu()
        #expect(shelf.addSelectionItem(to: first) == true)
        #expect(shelf.addSelectionItem(to: first) == false)
        #expect(first.items.filter { $0.identifier == ConversationMenu.selectionID }.count == 1)
        // And never beside the items of a tab, a figure or a file link: they keep theirs.
        let counts: [(String, NSUserInterfaceItemIdentifier)] = [("a figure's", ConversationMenu.itemID), ("a tab's", TabContextMenu.itemID),
                                                                 ("this item's own", ConversationMenu.selectionID)]
        for (whose, identifier) in counts {
            let menu = textMenu()
            let theirs = NSMenuItem(title: "Theirs", action: nil, keyEquivalent: "")
            theirs.identifier = identifier
            menu.addItem(theirs)
            #expect(ConversationMenu.mayOfferSelection(selected: 62, onSession: true, menu: menu) == false, "\(whose)")
        }
        #expect(ConversationMenu.mayOfferSelection(selected: 62, onSession: true, menu: textMenu()))
        #expect(!ConversationMenu.mayOfferSelection(selected: nil, onSession: true, menu: textMenu()))
        #expect(!ConversationMenu.mayOfferSelection(selected: 0, onSession: true, menu: textMenu()))
        #expect(!ConversationMenu.mayOfferSelection(selected: 62, onSession: false, menu: textMenu()))
    }

    @Test func aFigureRightClickWithASelectionKeepsOnlyTheFiguresItems() {
        var now = Self.start
        let shelf = shelfMenu(now: { now })
        let pick = ConversationPick(kind: .image, version: ShelfAddressTests.version, name: "Z prime")
        shelf.record(pick, selected: 62)
        now = Self.start + .milliseconds(10)
        let menu = textMenu()
        shelf.addItems(to: menu)
        shelf.addSelectionItem(to: menu)
        #expect(menu.items.contains { $0.identifier == ConversationMenu.itemID })
        #expect(!menu.items.contains { $0.identifier == ConversationMenu.selectionID })
    }

    @Test func choosingTheItemShelvesTheSelection() {
        var shelved = 0
        var now = Self.start
        let shelf = shelfMenu(now: { now }, shelve: { shelved += 1 })
        shelf.hear(["kind": NSNull(), "selected": 62], accepted: true)
        now = Self.start + .milliseconds(10)
        let menu = textMenu()
        shelf.addSelectionItem(to: menu)
        let item = menu.items[3]
        #expect(item.title == "Add Selection to Shelf")
        _ = item.target?.perform(item.action, with: item)
        #expect(shelved == 1)
    }

    @Test func theWebViewAsksForTheItemAfterTheTabAndFigureGroups() throws {
        // `willOpenMenu` is WebKit's own call and no test makes one; the wiring is read.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Web/TabContextMenu.swift"), encoding: .utf8)
        let tab = try #require(view.range(of: "tabMenu?.addItems(to: menu)"))
        let figure = try #require(view.range(of: "shelfMenu?.addItems(to: menu)"))
        let selection = try #require(view.range(of: "shelfMenu?.addSelectionItem(to: menu)"))
        #expect(tab.upperBound <= figure.lowerBound && figure.upperBound <= selection.lowerBound)
        let container = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Web/WebContainer.swift"), encoding: .utf8)
        #expect(container.contains("PlanCheck.isFrameID"), "a session's page only")
        #expect(container.contains("ConversationShelf.shared.shelveSelection()"))
        #expect(container.contains("contentWorld: ConversationMenu.world"), "the words are read in Capsid's own world")
    }
}

// MARK: What choosing it does

@MainActor
struct ShelfSelectionActionTests {
    static let route = ConversationShelfTests.route
    static let session = ConversationShelfTests.session

    final class Calls {
        var asks: [Int] = []
        var words: String? = "  Plate 7 drifts after the midpoint.\n"
        var sessionAsks = 0
    }

    private func make(route: NidusTaskSelection.Route? = ShelfSelectionActionTests.route)
        -> (ConversationShelf, MadeNotes, ShelfToastModel, Calls) {
        let notes = MadeNotes()
        let calls = Calls()
        let toast = ShelfToastModel(shelf: notes.access, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, announce: { _ in })
        let shelf = ConversationShelf(dependencies: .init(
            route: { route },
            session: { _ in calls.sessionAsks += 1; return Self.session },
            facts: { _ in nil },
            shelf: notes.access, toast: toast,
            keep: { _ in }, reference: { _, _ in }, results: { _ in },
            selection: { limit in calls.asks.append(limit); return calls.words }))
        return (shelf, notes, toast, calls)
    }

    @Test func theSelectionBecomesANoteForThisSessionWithTheWordsTrimmed() async {
        let (shelf, notes, toast, calls) = make()
        await shelf.shelveSelection()
        #expect(calls.asks == [32_000])
        #expect(notes.notes == [ShelfSelectionNote(session: Self.session, text: "Plate 7 drifts after the midpoint.")])
        #expect(toast.state == .added(MadeShelf.placement("Plate 7 drifts after the midpoint")))
    }

    @Test func theWordsAreCutAtThe32000thCharacter() async {
        let (shelf, notes, _, calls) = make()
        calls.words = String(repeating: "word ", count: 20_000)
        await shelf.shelveSelection()
        // 32,000 characters are "word " 6,400 times; the blank the cut ends on is trimmed.
        #expect(notes.notes.first?.text.count == 31_999)
        #expect(notes.notes.first?.text.hasSuffix("word") == true)
    }

    @Test func theToastSaysAddingWhileTheWordsAreRead() async {
        let (shelf, notes, toast, _) = make()
        notes.holding = true
        let adding = Task { await shelf.shelveSelection() }
        for _ in 0..<20 { await Task.yield() }
        #expect(toast.state == .adding)
        notes.release()
        await adding.value
        #expect(toast.state != .adding)
    }

    @Test func aDuplicateAndAFailureAreTheShelfsOwnAnswers() async {
        let (shelf, notes, toast, _) = make()
        let placement = MadeShelf.placement("Plate 7 drifts after the midpoint")
        notes.outcome = .alreadyOnShelf(placement)
        await shelf.shelveSelection()
        #expect(toast.state == .already(placement))
        notes.outcome = .failed("The Kept folder isn\u{2019}t there.")
        await shelf.shelveSelection()
        #expect(toast.state == .failed("The Kept folder isn\u{2019}t there."))
    }

    @Test func nothingSelectedAnyMoreIsASentenceAndNoNote() async {
        for words in [nil, "", "   \n\t "] as [String?] {
            let (shelf, notes, toast, calls) = make()
            calls.words = words
            await shelf.shelveSelection()
            #expect(notes.notes.isEmpty)
            #expect(toast.state == .failed(ShelfSelectionNote.nothingSelected))
        }
    }

    @Test func aPageNotOnASessionSaysSoAndReadsNothing() async {
        let (shelf, notes, toast, calls) = make(route: nil)
        await shelf.shelveSelection()
        #expect(toast.state == .failed(ConversationShelf.noSession))
        #expect(notes.notes.isEmpty && calls.asks.isEmpty && calls.sessionAsks == 0)
    }

    @Test func theToastNeverHoldsTheWords() async {
        let (shelf, _, toast, calls) = make()
        calls.words = "Plate 7 drifts after the midpoint, and the edge wells run low, which is the whole of the secret."
        await shelf.shelveSelection()
        // The note's title is its first few words; the rest of what was selected is in the note only.
        let said = toast.state.map(ShelfToastModel.words) ?? ""
        #expect(said.contains("Plate 7 drifts after the midpoint, and the"))
        #expect(!said.contains("the whole of the secret"))
    }
}

/// A made-up shelf for notes: what it was asked to add, and what it answers.
@MainActor
final class MadeNotes {
    private(set) var notes: [ShelfSelectionNote] = []
    var outcome: ShelfAddOutcome?
    var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func release() {
        let waiting = waiters
        waiters = []
        holding = false
        for waiter in waiting { waiter.resume() }
    }

    private(set) lazy var access = ShelfAccess(
        contains: { _ in false }, count: { 0 },
        add: { _ in .failed("A note is no file.") },
        addNote: { [self] note in
            notes.append(note)
            if holding { await withCheckedContinuation { waiters.append($0) } }
            return outcome ?? .added(MadeShelf.placement(ShelfSelectionNote.title(for: note.text, session: note.session)))
        })
}
