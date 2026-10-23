// ShelfModel.swift — what the Shelf window has chosen (DESIGN.md, Shelf): the
// project, the kind chip, the search, the selected item, and the line that
// follows a removal. The items come from the kept folders (`KeptIndex`,
// `ShelfRules.items`); everything the window shows follows from them and
// from these choices, so the rules live here and the tests drive them without
// drawing anything. A choice that hides the selected item moves the selection
// to the first one shown, and the arrow keys move it through the grid.
import Combine
import Foundation

@MainActor
final class ShelfModel: ObservableObject {
    /// The grid's width in cards: the arrow keys count in it.
    static let columns = 4

    /// A line on the window after a removal: what happened, and Undo while it can be.
    struct Note: Equatable, Identifiable {
        let id = UUID()
        let sentence: String
        let removal: ShelfRemoval?
    }

    let shelf: Shelf
    var index: KeptIndex { shelf.index }
    /// Export Figure as PDF… (ShelfPDFCommand.swift).
    let pdf: ShelfPDFMaker

    @Published private(set) var items: [ShelfItem] = []
    @Published var project: String? { didSet { if project != oldValue { reconcile(); findScopeChanged() } } }
    @Published var kind: ShelfKind? { didSet { if kind != oldValue { reconcile(); findScopeChanged() } } }
    @Published var search = "" { didSet { if search != oldValue { reconcile(); findScopeChanged() } } }
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
    private var noteTask: Task<Void, Never>?
    private var pending: (folder: URL, until: Date)?
    private let now: () -> Date
    /// How long the line after a removal stays; one that only says what went wrong, twice as long.
    private let noteLifetime: Duration

    init(shelf: Shelf, noteLifetime: Duration = .seconds(8), now: @escaping () -> Date = { Date() },
         pdf: ShelfPDFMaker? = nil, legendDelay: Duration = .seconds(1)) {
        self.shelf = shelf
        self.legendDelay = legendDelay
        self.pdf = pdf ?? .live(disk: shelf.index.disk)
        self.now = now
        self.noteLifetime = noteLifetime
        finder = ShelfFinder(actions: .live(shelf: shelf), changes: shelf.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        finder.selectFolder = { [weak self] in self?.select(folder: $0) }
        items = ShelfRules.items(from: shelf.index.results)
        subscription = shelf.index.$results.sink { [weak self] results in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.items = ShelfRules.items(from: results)
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
    var scoped: [ShelfItem] { ShelfRules.matching(items, project: project, query: search) }
    var counts: ShelfRules.Counts { ShelfRules.counts(of: scoped) }
    /// The grid: the scoped items of the chosen kind.
    var shown: [ShelfItem] { ShelfRules.items(scoped, of: kind) }
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

    /// ←, →, ↑ and ↓ through the grid: a card at a time, or a row.
    func move(_ dx: Int, _ dy: Int) {
        let shown = self.shown
        guard !shown.isEmpty else { return }
        guard let selection, let at = shown.firstIndex(where: { $0.id == selection }) else {
            self.selection = shown.first?.id
            return
        }
        let target = at + dx + dy * Self.columns
        // Up from the first row and down from the last stay where they are; sideways stops at the ends.
        guard (0..<shown.count).contains(target) else {
            if dy > 0, at / Self.columns < (shown.count - 1) / Self.columns { self.selection = shown[shown.count - 1].id }
            return
        }
        self.selection = shown[target].id
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

    func say(_ sentence: String, removal: ShelfRemoval? = nil) {
        let made = Note(sentence: sentence, removal: removal)
        note = made
        noteTask?.cancel()
        let lifetime = removal == nil ? noteLifetime * 2 : noteLifetime
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self else { return }
            if self.note?.id == made.id { self.note = nil }
        }
    }
}
