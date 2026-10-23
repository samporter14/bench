// ShelfFinder.swift — the Shelf window's second section, "In your sessions"
// (DESIGN.md, Find any figure): what the window's search finds in every
// session, below the shelf's own matches. The window's model owns one, tells
// it when the search, the project pill or the kind chip changes, and the
// section draws from it. Everything else is the shelf's: the add, the
// reference window and Results are the ones the rest of the app uses.
import Combine
import Foundation

@MainActor
final class ShelfFinder: ObservableObject {
    let search: FindSearch
    let actions: FindActions
    /// The small pictures the rows draw (Results' store, so a picture read for
    /// either window is kept for both), and how to ask for one.
    let thumbnails: ShelfThumbnails
    private let requestThumbnail: @MainActor (ArtifactEntry) -> Void
    /// Opens the shelf's item in `folder` (the window selects it).
    var selectFolder: @MainActor (URL) -> Void = { _ in }

    /// Versions added from this search, where they landed: they stay in the
    /// list, as "On Shelf ✓", until the words change, rather than vanishing
    /// under the pointer.
    @Published private(set) var added: [String: URL] = [:]
    /// Why an add failed, by version: a sentence under the file.
    @Published private(set) var problems: [String: String] = [:]

    private var subscription: AnyCancellable?
    private var words = ""

    init(search: FindSearch = FindSearch(), actions: FindActions, thumbnails: ShelfThumbnails? = nil,
         requestThumbnail: (@MainActor (ArtifactEntry) -> Void)? = nil,
         changes: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()) {
        self.search = search
        self.actions = actions
        self.thumbnails = thumbnails ?? ResultsShelf.shared.thumbnailStore
        self.requestThumbnail = requestThumbnail ?? { ResultsShelf.shared.wantThumbnail($0) }
        // The shelf changed (a version came or went): the section is drawn again.
        subscription = Publishers.Merge(changes.receive(on: DispatchQueue.main), search.objectWillChange.map { _ in () })
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.objectWillChange.send() } }
    }

    // MARK: What is shown

    /// The query is worth a look: the section is shown.
    var isWanted: Bool { search.query != nil }

    /// The files to show: those not on the shelf, and those added from this search.
    var visible: [FoundFile] {
        FindRanking.visible(search.files, onShelf: actions.onShelf, keeping: Set(added.keys))
    }

    /// The header's count: "14", or "100+" when the database was cut at its limit.
    var countText: String {
        "\(visible.count)\(search.mayHaveMore ? "+" : "")"
    }

    func mark(of file: FoundFile) -> ShelfMark {
        if actions.isAdding(file.version) { return .adding }
        return added[file.version] != nil || actions.onShelf(file.version) ? .on : .off
    }

    // MARK: Typing

    /// The window's search, project pill or kind chip changed.
    func scopeChanged(text: String, project: String?, kind: ShelfKind?) {
        let next = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if next != words {
            words = next
            added = [:]
            problems = [:]
        }
        // Noted so the pictures the answer asks for wait for the typing to pause.
        if !next.isEmpty { ReadingGate.shared.noteKey() }
        search.update(text, kind: kind, project: project)
    }

    func cancel() {
        words = ""
        added = [:]
        problems = [:]
        search.cancel()
    }

    // MARK: Acting

    func add(_ file: FoundFile) {
        guard actions.isAvailable, mark(of: file) == .off else { return }
        problems[file.version] = nil
        Task { [weak self] in
            guard let self else { return }
            // The row shows its spinner from the shelf's own record of the add.
            objectWillChange.send()
            switch await actions.add(file) {
            case .added(let placement), .alreadyOnShelf(let placement): added[file.version] = placement.folder
            case .failed(let sentence): problems[file.version] = sentence
            }
        }
    }

    func showWhere(_ file: FoundFile) {
        guard actions.isAvailable else { return }
        actions.show(file)
    }

    func openInResults(_ file: FoundFile) {
        guard actions.isAvailable else { return }
        actions.results(file)
    }

    /// "On Shelf ✓" was pressed: the item, in the grid.
    func showOnShelf(_ file: FoundFile) {
        if let folder = added[file.version] { selectFolder(folder) }
    }

    // MARK: Pictures

    /// A row came into view: its picture, once, when the typing has paused.
    /// Only for pictures, and never for one already read or being read.
    func wantPicture(of file: FoundFile) async {
        guard actions.isAvailable, file.kind == .figure, !thumbnails.knows(file.version) else { return }
        ReadingGate.shared.start()
        try? await ReadingGate.shared.perform { [requestThumbnail] in requestThumbnail(file.entry) }
    }
}
