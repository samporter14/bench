// ShelfModel.swift — what the Shelf window has chosen (DESIGN.md, Shelf): the
// project, the kind chip, the search, the selected item, and the line that
// follows a removal. The items come from the kept folders (`KeptIndex`,
// `ShelfRules.items`); everything the window shows follows from them and
// from these choices, so the rules live here and the tests drive them without
// drawing anything. A choice that hides the selected item moves the selection
// to the first one shown, and the arrow keys move it through the cards, which
// stand under their days (`days`) as many to a row as the window's width holds.
import Combine
import Foundation

@MainActor
final class ShelfModel: ObservableObject {
    /// Cards to a row, as the window's width has it (`ShelfRules.columns(forWidth:)`): ↑ and ↓ count in it. The view
    /// sets it when its width changes; nothing is drawn from it, so it isn't published.
    var columns = 3

    /// A line on the window after a removal: what happened, and Undo while it can be.
    struct Note: Equatable, Identifiable {
        let id = UUID()
        let sentence: String
        let removal: ShelfRemoval?
        /// Claude's legend went into an item's field: Undo puts the legend back (ShelfClaudeLegend.swift).
        var legend: ShelfClaudeLegend.Undo? = nil

        /// The pill offers Undo.
        var hasUndo: Bool { removal != nil || legend != nil }
    }

    let shelf: Shelf
    var index: KeptIndex { shelf.index }
    /// Claude's legend files for the items: what the detail card offers and what using one does (ShelfClaudeLegend.swift).
    let claudeLegend: ShelfClaudeLegend
    /// Export Figure as PDF… (ShelfPDFCommand.swift).
    let pdf: ShelfPDFMaker

    /// What the search reads inside the prose files (Kept/ShelfTextIndex.swift): reading starts when a search is first typed.
    let textIndex: ShelfTextIndex
    /// The whole passage of a note, for its detail card and for Copy (Kept/ShelfPassage.swift).
    let passages: ShelfPassages

    @Published private(set) var items: [ShelfItem] = [] { didSet { scopedStale = true } }
    @Published var project: String? { didSet { if project != oldValue { scopedStale = true; reconcile(); findScopeChanged() } } }
    @Published var kind: ShelfKind? { didSet { if kind != oldValue { reconcile(); findScopeChanged() } } }
    @Published var search = "" {
        didSet {
            guard search != oldValue else { return }
            scopedStale = true
            // The first search starts the reading; what is read so far is searched at once.
            if !search.isEmpty, !textIndex.isActive { textIndex.update(for: items) }
            reconcile()
            findScopeChanged()
        }
    }
    /// "In your sessions": what the search finds beyond the shelf (Find/ShelfFinder.swift).
    @Published var finder: ShelfFinder
    /// The selected item's id (`ShelfItem.id`): the one the detail shows and the arrows move from.
    /// Choosing it alone goes back to one pick (ShelfPicking.swift).
    @Published var selection: String? {
        didSet {
            picked = selection.map { [$0] } ?? []
            pickAnchor = selection
        }
    }
    /// Every item picked (⌘-click, ⇧-click, ⌘A), the selected one among them: what Export as PDF… makes a page of each.
    @Published var picked: Set<String> = []
    /// The card a ⇧-click runs from.
    var pickAnchor: String?
    @Published private(set) var note: Note?

    /// Items being taken off right now, by id: Remove pressed again before the first removal is done (a
    /// double-click) asks for nothing more, so the second can't fail on a folder that has already moved and
    /// put its error where the Undo was.
    private(set) var removing: Set<String> = []

    /// The legend editors, by item id (its folder): one for each item whose field is or was on screen and still has
    /// something to save or to say. The card shows the model's editor, so a draft outlives the card (ShelfLegend.swift),
    /// and a PDF waits for the editors of the items it is made from (ShelfPicking.swift).
    private var legendEditors: [String: ShelfLegendEditor] = [:]
    private let legendDelay: Duration

    private var subscription: AnyCancellable?
    private var textSubscription: AnyCancellable?
    /// What the search has read of the prose files; replaced as reading finishes.
    private var texts = ShelfTexts.none
    /// `scoped` as last made, and whether a choice, the items or the text read has changed since.
    private var scopedItems: [ShelfItem] = []
    private var scopedStale = true
    private var legendSubscription: AnyCancellable?
    private var passageSubscription: AnyCancellable?
    private var noteTask: Task<Void, Never>?
    private var pending: (folder: URL, until: Date)?
    private let now: () -> Date
    /// The user's calendar: the days the cards stand under.
    let calendar: Calendar
    /// How long the line after a removal stays; one that only says what went wrong, twice as long.
    private let noteLifetime: Duration

    init(shelf: Shelf, noteLifetime: Duration = .seconds(8), now: @escaping () -> Date = { Date() }, calendar: Calendar = .current,
         pdf: ShelfPDFMaker? = nil, legendDelay: Duration = .seconds(1), claudeLegend: ShelfClaudeLegend? = nil,
         textIndex: ShelfTextIndex? = nil, passages: ShelfPassages? = nil) {
        self.shelf = shelf
        self.passages = passages ?? ShelfPassages(disk: shelf.index.disk)
        self.textIndex = textIndex ?? ShelfTextIndex(disk: shelf.index.disk)
        self.legendDelay = legendDelay
        self.claudeLegend = claudeLegend ?? ShelfClaudeLegend(dependencies: { shelf.legendDependencies })
        self.pdf = pdf ?? .live(disk: shelf.index.disk)
        self.now = now
        self.calendar = calendar
        self.noteLifetime = noteLifetime
        finder = ShelfFinder(actions: .live(shelf: shelf), changes: shelf.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        finder.selectFolder = { [weak self] in self?.select(folder: $0) }
        items = ShelfRules.items(from: shelf.index.results)
        // The card is redrawn when a look at an item's legend files ends or one is put in.
        legendSubscription = self.claudeLegend.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        // The card is redrawn when a note's passage has been read.
        passageSubscription = self.passages.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        subscription = shelf.index.$results.sink { [weak self] results in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.items = ShelfRules.items(from: results)
                // The folders were read again: the files read for the search are looked at again too.
                if self.textIndex.isActive { self.textIndex.update(for: self.items) }
                self.reconcile()
            }
        }
        // A file's text was read: the search runs again on it, when there is one.
        textSubscription = self.textIndex.$texts.dropFirst().sink { [weak self] texts in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.texts = texts
                guard !self.search.isEmpty else { return }
                self.scopedStale = true
                self.objectWillChange.send()
                self.reconcile()
            }
        }
        reconcile()
    }

    // MARK: The legend fields

    /// The editor for `item`'s legend: the one kept from before when it still holds a draft, a save under way or a
    /// sentence, else a new one. Editors with nothing left to say are let go here. A save that fails after the field
    /// is gone puts a line on the window's pill, naming the item.
    func legendEditor(for item: ShelfItem) -> ShelfLegendEditor {
        legendEditors = legendEditors.filter { $0.key == item.id || !$0.value.isIdle }
        if let held = legendEditors[item.id] { return held }
        let editor = ShelfLegendEditor(folder: item.folder, disk: index.disk, delay: legendDelay) { [weak self] in
            await self?.index.reload(item.result)
        }
        let name = item.title
        editor.failed = { [weak self] conflict in self?.say(ShelfLegendEditor.leftUnsaved(name, conflict: conflict)) }
        legendEditors[item.id] = editor
        return editor
    }

    /// Whether an editor is kept for `id`: a draft, a save or a sentence is waiting in it.
    func keepsLegendEditor(for id: String) -> Bool { legendEditors[id].map { !$0.isIdle } ?? false }

    /// `items` as the disk has them now: the legends typed in their fields written first (and a save that was
    /// already under way finished), then each README read again, so a PDF is made from what is saved, not from the
    /// words the shelf held when the command was given. An item whose README can't be read stays as it was.
    func latest(of items: [ShelfItem]) async -> [ShelfItem] {
        for item in items { await legendEditors[item.id]?.settle() }
        var fresh: [ShelfItem] = []
        for item in items {
            guard let read = try? await index.disk.readme(at: item.folder) else {
                fresh.append(item)
                continue
            }
            let result = KeptResult(folder: item.folder, collection: item.collection, record: read.record, text: read.text)
            fresh.append(ShelfItem(result: result, others: item.others))
        }
        return fresh
    }

    // MARK: What is shown

    /// The projects (collections) with something on the shelf, by their newest item.
    var projects: [String] {
        var seen: Set<String> = []
        return items.compactMap { seen.insert($0.collection).inserted ? $0.collection : nil }
    }

    /// In the project and matching the search: what the chips count.
    /// Made again only when something it depends on changed: a search reads up to 200,000 characters of each item.
    var scoped: [ShelfItem] {
        if scopedStale {
            scopedItems = ShelfRules.matching(items, project: project, query: search, texts: texts)
            scopedStale = false
        }
        return scopedItems
    }
    /// The search found this item only by what its text says (a quiet word on its card).
    func foundOnlyInText(_ item: ShelfItem) -> Bool {
        !search.isEmpty && ShelfRules.foundOnlyInText(item, query: search, texts: texts)
    }
    var counts: ShelfRules.Counts { ShelfRules.counts(of: scoped) }
    /// The grid: the scoped items of the chosen kind.
    var shown: [ShelfItem] { ShelfRules.items(scoped, of: kind) }
    /// The grid under its headings: Today, Yesterday, This week… (the same items as `shown`, in the same order).
    var days: [ShelfRules.DayGroup] { ShelfRules.days(shown, now: now(), calendar: calendar) }
    /// A heading's words, said as of now.
    func title(of day: ShelfRules.Day) -> String { day.title(now: now(), calendar: calendar) }
    var selected: ShelfItem? { shown.first { $0.id == selection } }
    var isEmpty: Bool { items.isEmpty }
    var isFiltered: Bool { project != nil || kind != nil || !search.isEmpty }

    /// A choice or the folders changed: the selection stays on what it was on
    /// when that is still shown, else goes to the first thing shown.
    private func reconcile() {
        if let pending, now() > pending.until { self.pending = nil }
        applyPending()
        let shown = self.shown
        // Picks still shown stay picked: moving the selection puts it back to one pick, so they are kept aside.
        let keep = picked.intersection(shown.map(\.id))
        defer { if let selection, keep.contains(selection) { picked = keep } }
        if let selection, !shown.contains(where: { $0.id == selection }), let first = shown.first(where: { keep.contains($0.id) }) {
            self.selection = first.id
        }
        if let selection, shown.contains(where: { $0.id == selection }) { return }
        // The folder it was is gone or regrouped (kept with data and code now): the item that holds it.
        if let selection, let there = items.first(where: { item in item.folders.contains { $0.path == selection } }),
           shown.contains(where: { $0.id == there.id }) {
            self.selection = there.id
            return
        }
        selection = shown.first?.id
    }

    // MARK: Moving

    /// ←, →, ↑ and ↓ through the cards: a card at a time, running on from one row and one day to the next, or a row,
    /// to the card in the same column (the last of a row that is shorter), across a day's heading too.
    func move(_ dx: Int, _ dy: Int) {
        let shown = self.shown
        guard !shown.isEmpty else { return }
        guard let selection, let at = shown.firstIndex(where: { $0.id == selection }) else {
            self.selection = shown.first?.id
            return
        }
        guard dy != 0 else {
            // Sideways stops at the ends.
            if shown.indices.contains(at + dx) { self.selection = shown[at + dx].id }
            return
        }
        let rows = ShelfRules.rows(groupSizes: days.map(\.items.count), columns: columns)
        guard let row = rows.firstIndex(where: { $0.contains(at) }), let column = rows[row].firstIndex(of: at) else { return }
        // Up from the first row and down from the last stay where they are.
        guard rows.indices.contains(row + dy) else { return }
        let next = rows[row + dy]
        self.selection = shown[next[min(column, next.count - 1)]].id
    }

    // MARK: Asking for an item

    /// "Show Shelf" after an add: the item in `folder`, whatever the filters
    /// hide. If the folders haven't been read since it landed, as soon as they are.
    func select(folder: URL) {
        pending = (folder, now().addingTimeInterval(5))
        shelf.index.refresh()
        reconcile()
    }

    private func applyPending() {
        guard let pending else { return }
        guard let item = items.first(where: { $0.contains(folder: pending.folder) }) else { return }
        self.pending = nil
        if shown.contains(where: { $0.id == item.id }) == false {
            project = nil
            kind = nil
            search = ""
        }
        selection = item.id
    }

    // MARK: Removing

    /// Takes the selected item off the shelf (to the Trash) and says so, with Undo.
    func removeSelected() {
        guard let item = selected, removing.insert(item.id).inserted else { return }
        let neighbour = neighbour(of: item)
        Task { [weak self] in
            guard let self else { return }
            defer { removing.remove(item.id) }
            let removal = await shelf.remove(item)
            if removal.isEmpty {
                say(ShelfRules.couldntRemove(item.fileName, removal.problem))
                return
            }
            if let problem = removal.problem {
                say(ShelfRules.partlyRemoved(item.fileName, problem), removal: removal)
            } else {
                say(ShelfRules.removed(item.fileName), removal: removal)
            }
            // The next one in line, unless the choice has moved on.
            if selection == item.id || selected == nil { selection = neighbour }
        }
    }

    /// Undo on the line after a removal.
    func undoRemoval() {
        guard let removal = note?.removal else { return }
        note = nil
        noteTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            if let problem = await shelf.putBack(removal) {
                say(ShelfRules.couldntPutBack(removal.name, problem))
            } else if let first = removal.moved.first {
                pending = (first.from, now().addingTimeInterval(5))
                reconcile()
            }
        }
    }

    func dismissNote() {
        noteTask?.cancel()
        note = nil
    }

    private func neighbour(of item: ShelfItem) -> String? {
        let shown = self.shown
        guard let at = shown.firstIndex(where: { $0.id == item.id }) else { return nil }
        if at + 1 < shown.count { return shown[at + 1].id }
        return at > 0 ? shown[at - 1].id : nil
    }

    func say(_ sentence: String, removal: ShelfRemoval? = nil, legend: ShelfClaudeLegend.Undo? = nil) {
        let made = Note(sentence: sentence, removal: removal, legend: legend)
        note = made
        noteTask?.cancel()
        let lifetime = made.hasUndo ? noteLifetime : noteLifetime * 2
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self else { return }
            if self.note?.id == made.id { self.note = nil }
        }
    }
}
