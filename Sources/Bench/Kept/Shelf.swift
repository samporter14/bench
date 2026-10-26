// Shelf.swift — the shelf (DESIGN.md, Shelf; boards 10 and 11 of the Capsid
// 1.0 mock-ups): one click puts a file Claude made — a figure, a document, a
// table — on the shelf, with what Claude said about it and exactly where it
// came from, and the Shelf window finds it again and goes back to that place.
//
// A shelved item is a small kept folder (Kept/KeptDisk.swift): the file, its
// README with Claude's words and its origin (the session, the history row of
// the message that showed it, the version), in the project's collection under
// the Kept root. It is the Kept window, renamed: Keep with Data and Code…
// (the Keep sheet) is the heavier way in, for a paper.
//
// THE CONTRACT. This file implements it; the conversation, Results and the
// reference window call it. The names and shapes of `ShelfSource`,
// `ShelfPlacement`, `ShelfAddOutcome` and `Shelf`'s `versions`, `adding`,
// `contains`, `add`, `undo` and `show` are fixed; what follows them is the
// Shelf window's.
import AppKit
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "shelf")

/// What is being shelved, and what is known of where it came from.
struct ShelfSource: Equatable, Sendable {
    let session: SessionStatus
    let entry: ArtifactEntry
    /// The answer that showed it, when the caller knows it (the reference
    /// reader's reply). Nil: the shelf looks for it (Keep's showing read).
    var answer: KeepPinnedAnswer? = nil
    /// The history row of the message that showed it, when known.
    var row: Int? = nil
    /// What the user asked in that exchange, when known.
    var question: String? = nil
}

/// Where a shelved item landed.
struct ShelfPlacement: Equatable, Sendable {
    let folder: URL
    /// The file's name as shown ("z_prime_by_plate.png"); a note's title.
    let name: String
    let collection: String
}

enum ShelfAddOutcome: Equatable, Sendable {
    case added(ShelfPlacement)
    /// That version is on the shelf already: nothing new was made.
    case alreadyOnShelf(ShelfPlacement)
    /// A sentence saying what happened, in Solanum's voice.
    case failed(String)
}

/// Every step of an add that reaches the page, besides the ones Keep already
/// has (`KeepDependencies`: the reads, the disk, the settings).
struct ShelfDependencies {
    var keep: KeepDependencies
    /// What the user asked in the exchange that includes history row `row`:
    /// the nearest message of theirs before it. Nil when it can't be read.
    var question: @MainActor (_ frameID: String, _ row: Int) async -> String?
    /// The files of the answer that holds history row `row`, as the reference reader tells them (the ones that aren't
    /// pictures): where Claude's legend file is looked for (ShelfClaudeLegend.swift). Nil when they can't be read;
    /// empty when the page has no answer around that row.
    var answerFiles: @MainActor (_ frameID: String, _ row: Int) async -> [HistoryFile]? = { _, _ in nil }

    @MainActor
    static func live(shelf: ResultsShelf = .shared) -> ShelfDependencies {
        ShelfDependencies(
            keep: .live(shelf: shelf),
            question: { frameID, row in
                guard Demo.mode == nil else { return nil }
                var before: Int? = row + 1
                // Two pages back is enough for a question; a longer run of steps leaves it out.
                for _ in 0..<2 {
                    guard let read = try? await WebContainer.shared.readHistory(frameID, before: before, rows: 25,
                                                                                nonce: ArtifactReadAbort.makeNonce()),
                          case .page(let page) = read else { return nil }
                    for item in page.items.reversed() {
                        if case .turn(let i, .you, _, let text, _, _) = item, i <= row {
                            let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            return asked.isEmpty ? nil : String(asked.prefix(ShelfRules.questionLimit))
                        }
                    }
                    guard page.from > 0 else { return nil }
                    before = page.from
                }
                return nil
            },
            answerFiles: { await KeepDependencies.liveAnswerFiles(frameID: $0, row: $1) })
    }
}

/// A removal from the shelf, as far as it got: what moved to the Trash, so it
/// can be put back.
struct ShelfRemoval: Equatable, Sendable {
    struct Moved: Equatable, Sendable {
        let from: URL
        let trashed: URL
    }

    /// The name shown ("z_prime_by_plate.png").
    let name: String
    fileprivate(set) var moved: [Moved]
    /// Why some folders didn't move, in a sentence; nil when all did.
    fileprivate(set) var problem: String?

    var isEmpty: Bool { moved.isEmpty }
}

@MainActor
final class Shelf: ObservableObject {
    static let shared = Shelf(index: .shared, dependencies: { .live() })

    /// Version ids on the shelf, for "On Shelf ✓" and the "On your shelf" mark.
    /// Empty until the folders are read once, lazily (`load`, `contains`, an add).
    @Published private(set) var versions: Set<String> = []
    /// Adds under way, by version id: a spinner where it was asked.
    @Published private(set) var adding: Set<String> = []
    /// How many things are on the shelf (the toolbar's "Shelf · 12").
    @Published private(set) var count = 0

    /// The folders as the Shelf window and the Results window read them.
    let index: KeptIndex
    private let makeDependencies: @MainActor () -> ShelfDependencies
    private lazy var dependencies: ShelfDependencies = makeDependencies()
    private var running: [String: Task<ShelfAddOutcome, Never>] = [:]
    /// Notes being added, by session and checksum of the words.
    private var runningNotes: [String: Task<ShelfAddOutcome, Never>] = [:]
    private var placements: [String: ShelfPlacement] = [:]
    /// Landed, and not in a read of the folders yet.
    private var added: [String: ShelfPlacement] = [:]
    /// Folders taken off, and still in a read of the folders. Notes have no version of their own.
    private var removed: Set<URL> = []
    private var requestedRead = false
    private var subscription: AnyCancellable?

    init(index: KeptIndex, dependencies: @escaping @MainActor () -> ShelfDependencies) {
        self.index = index
        self.makeDependencies = dependencies
        subscription = index.$results.sink { [weak self] results in
            MainActor.assumeIsolated { self?.sync(results) }
        }
    }

    func contains(version: String) -> Bool {
        load()
        return versions.contains(version)
    }

    /// The reads and the disk the detail card's offer of Claude's legend uses (ShelfClaudeLegend.swift).
    var legendDependencies: ShelfDependencies { dependencies }

    /// Reads the shelf's folders once, off the main actor, when something first
    /// asks what is on it. Harmless to call again.
    func load() {
        guard !requestedRead else { return }
        requestedRead = true
        // Not inside a view's update: the read publishes.
        Task { @MainActor [index] in
            if !index.hasRead { index.refresh() }
        }
    }

    // MARK: Adding

    /// Puts one file on the shelf: copied, with Claude's words and where it
    /// came from. One at a time per version; a second ask while the first
    /// runs answers with the first's outcome.
    func add(_ source: ShelfSource) async -> ShelfAddOutcome {
        let version = source.entry.version
        if let first = running[version] { return await first.value }
        adding.insert(version)
        let task = Task { @MainActor [self] in
            let outcome = await perform(source)
            running[version] = nil
            adding.remove(version)
            return outcome
        }
        running[version] = task
        return await task.value
    }

    private func perform(_ source: ShelfSource) async -> ShelfAddOutcome {
        let d = dependencies
        let entry = source.entry
        let version = entry.version
        requestedRead = true
        await index.refreshAndWait()
        if let there = placements[version] { return .alreadyOnShelf(there) }

        // 1. The file's facts: its name now, its number, its checksum.
        let facts: ArtifactFacts
        switch await d.keep.read(.facts(version: version)) {
        case .answered(.facts(let found)):
            facts = found
        case .answered(.missing):
            return .failed(ShelfRules.gone(entry.name))
        case .answered(.cancelled), .cancelled:
            return .failed(ShelfRules.couldntAdd(entry.name, "It was stopped."))
        case .answered(let other):
            return .failed(ShelfRules.couldntAdd(entry.name, ShelfFailure(other).sentence))
        case .timedOut:
            return .failed(ShelfRules.couldntAdd(entry.name, ShelfFailure.timedOut.sentence))
        case .notReady:
            return .failed(ShelfRules.couldntAdd(entry.name, ShelfFailure.notReady.sentence))
        }
        let fileName = KeptLayout.fileName(facts.name ?? entry.name)

        // 2. Claude's words and where they sit: the answer the caller knows, else
        // the message that showed this version, else the session's last answer.
        var answer: ShelfRules.Answer?
        var row = source.row
        if let given = source.answer {
            answer = ShelfRules.Answer(text: given.text, at: given.at, isLast: false, cut: given.cut)
        } else if case .found(let message) = await d.keep.showing(source.session.id, [version], facts.at) {
            answer = ShelfRules.Answer(text: message.text, at: message.at, isLast: false)
            row = row ?? message.i
        } else if let last = await d.keep.lastAnswer(source.session.id) {
            answer = ShelfRules.Answer(text: last.text, at: last.at, isLast: true)
            row = nil
        }
        var question = source.question
        if question == nil, answer?.isLast != true, let row {
            question = await d.question(source.session.id, row)
        }

        // 3. The file, through the Results shelf's queue and its 8 MB cap.
        let item = KeepItem(role: .figure, source: .download(version: version), artifact: facts.a ?? entry.artifact, version: version,
                            name: fileName, size: facts.size ?? entry.size, sha: facts.sha)
        let bytes: Data
        var expected: String?
        switch await d.keep.fetch(item) {
        case .bytes(let data, let sha):
            bytes = data
            expected = sha
        case .gone:
            return .failed(ShelfRules.gone(fileName))
        case .tooBig:
            return .failed(ShelfRules.tooBig(fileName))
        case .failed(let sentence):
            return .failed(ShelfRules.couldntAdd(fileName, sentence))
        case .cancelled:
            return .failed(ShelfRules.couldntAdd(fileName, "It was stopped."))
        }

        // 4. A folder in the project's collection: the file, then the README.
        let keptAt = d.keep.now()
        let session = source.session
        let collection = KeptSettings.collection(for: session.projectID, defaults: d.keep.defaults)
            ?? (session.projectName.isEmpty ? "Shelf" : KeptName.sanitized(session.projectName))
        let stem = (fileName as NSString).deletingPathExtension
        let destination: KeptDestination
        do {
            destination = try await d.keep.disk.prepare(collection: collection, name: KeptName.sanitized(stem.isEmpty ? fileName : stem),
                                                        at: keptAt)
        } catch {
            return .failed(ShelfRules.couldntAdd(fileName, KeptDiskError.sentence(error)))
        }
        let figure = KeptFile(path: fileName, role: .figure, artifact: facts.a ?? entry.artifact, version: version, index: facts.n,
                              of: nil, sha256: d.keep.disk.sha256(of: bytes), bytes: bytes.count, expectedSha256: expected)
        do {
            try await d.keep.disk.write(bytes, to: fileName, in: destination)
        } catch {
            await d.keep.disk.abandon(destination)
            return .failed(ShelfRules.couldntAdd(fileName, KeptDiskError.sentence(error)))
        }
        let scienceVersion = await d.keep.scienceVersion()
        let written = ShelfRules.readme(session: session, folderName: destination.name, figure: figure, answer: answer, row: row,
                                        question: question, keptAt: keptAt, claudeScience: scienceVersion, capsid: d.keep.capsidVersion)
        let folder: URL
        do {
            folder = try await d.keep.disk.finish(destination, readme: KeptReadme.render(written.record, text: written.text))
        } catch {
            await d.keep.disk.abandon(destination)
            return .failed(ShelfRules.couldntAdd(fileName, KeptDiskError.sentence(error)))
        }
        let placement = ShelfPlacement(folder: folder, name: fileName, collection: destination.collection)
        log.notice("Put one file on the shelf")
        removed.remove(folder)
        added[version] = placement
        sync(index.results)
        index.refresh()
        return .added(placement)
    }

    // MARK: Adding a note

    /// Puts words selected in a conversation on the shelf (`ShelfSelectionNote`): a
    /// kept folder with them as `note.md`, a document with no version, and a
    /// README saying where they were selected. Nothing is read from Claude
    /// Science, and the words go to the folder and nowhere else: the log says
    /// only how many characters. The same words from the same session are on
    /// the shelf already after the first add, and a second ask while the first
    /// runs gets its outcome.
    func addNote(_ note: ShelfSelectionNote) async -> ShelfAddOutcome {
        let bytes = ShelfSelectionNote.data(for: note.text)
        let sha = dependencies.keep.disk.sha256(of: bytes)
        let key = note.session.id + "\n" + sha
        if let first = runningNotes[key] { return await first.value }
        let task = Task { @MainActor [self] in
            let outcome = await performNote(note, bytes: bytes, sha: sha)
            runningNotes[key] = nil
            return outcome
        }
        runningNotes[key] = task
        return await task.value
    }

    private func performNote(_ note: ShelfSelectionNote, bytes: Data, sha: String) async -> ShelfAddOutcome {
        let d = dependencies
        let session = note.session
        requestedRead = true
        await index.refreshAndWait()
        if let same = index.results.first(where: {
            $0.record.sessionID == session.id && $0.record.figure.version == nil && $0.record.figure.path == ShelfSelectionNote.fileName
                && $0.record.figure.sha256 == sha
        }) {
            return .alreadyOnShelf(ShelfPlacement(folder: same.folder, name: ShelfRules.title(for: same.record), collection: same.collection))
        }

        let title = ShelfSelectionNote.title(for: note.text, session: session)
        let keptAt = d.keep.now()
        let collection = KeptSettings.collection(for: session.projectID, defaults: d.keep.defaults)
            ?? (session.projectName.isEmpty ? "Shelf" : KeptName.sanitized(session.projectName))
        let destination: KeptDestination
        do {
            destination = try await d.keep.disk.prepare(collection: collection, name: KeptName.sanitized(title), at: keptAt)
        } catch {
            return .failed(ShelfRules.couldntAdd(title, KeptDiskError.sentence(error)))
        }
        let file = KeptFile(path: ShelfSelectionNote.fileName, role: .figure, artifact: nil, version: nil, index: nil, of: nil,
                            sha256: sha, bytes: bytes.count)
        do {
            try await d.keep.disk.write(bytes, to: ShelfSelectionNote.fileName, in: destination)
        } catch {
            await d.keep.disk.abandon(destination)
            return .failed(ShelfRules.couldntAdd(title, KeptDiskError.sentence(error)))
        }
        let scienceVersion = await d.keep.scienceVersion()
        let written = ShelfSelectionNote.readme(session: session, folderName: destination.name, file: file, keptAt: keptAt,
                                       claudeScience: scienceVersion, capsid: d.keep.capsidVersion)
        let folder: URL
        do {
            folder = try await d.keep.disk.finish(destination, readme: KeptReadme.render(written.record, text: written.text))
        } catch {
            await d.keep.disk.abandon(destination)
            return .failed(ShelfRules.couldntAdd(title, KeptDiskError.sentence(error)))
        }
        log.notice("Put a note on the shelf, \(note.text.count) characters")
        await index.refreshAndWait()
        return .added(ShelfPlacement(folder: folder, name: title, collection: destination.collection))
    }

    // MARK: Taking off

    /// Undo, right after an add: the folder goes to the Trash (never deleted).
    func undo(_ placement: ShelfPlacement) async -> Bool {
        do {
            _ = try await dependencies.keep.disk.trash(placement.folder)
        } catch {
            log.error("Couldn't undo an add: \(KeptDiskError.sentence(error), privacy: .public)")
            return false
        }
        forget(folders: [placement.folder])
        return true
    }

    /// Takes an item off the shelf: each of its folders goes to the Trash.
    /// Answers what moved, so Undo can put it back, and why not all did.
    func remove(_ item: ShelfItem) async -> ShelfRemoval {
        var removal = ShelfRemoval(name: item.fileName, moved: [], problem: nil)
        for folder in item.folders {
            do {
                let trashed = try await dependencies.keep.disk.trash(folder)
                removal.moved.append(.init(from: folder, trashed: trashed))
            } catch {
                removal.problem = KeptDiskError.sentence(error)
                break
            }
        }
        forget(folders: removal.moved.map(\.from))
        return removal
    }

    /// Undo after a removal: what moved goes back where it was. Nil when it
    /// did; else a sentence.
    func putBack(_ removal: ShelfRemoval) async -> String? {
        var problem: String?
        for move in removal.moved {
            do {
                _ = try await dependencies.keep.disk.restore(move.trashed, to: move.from, at: dependencies.keep.now())
                removed.remove(move.from)
            } catch {
                problem = KeptDiskError.sentence(error)
            }
        }
        sync(index.results)
        await index.refreshAndWait()
        return problem
    }

    /// Folders went to the Trash: the count and the version marks change before another scan. Filtering folders
    /// before grouping versions also keeps a second copy on the shelf when only one of its folders moved.
    private func forget(folders: [URL]) {
        guard !folders.isEmpty else { return }
        removed.formUnion(folders)
        added = added.filter { !removed.contains($0.value.folder) }
        sync(index.results)
        index.refresh()
    }

    // MARK: What is on it

    /// The folders as read, and what has landed or gone since.
    private func sync(_ results: [KeptResult]) {
        removed.formIntersection(Set(results.map(\.folder)))
        let items = ShelfRules.items(from: results.filter { !removed.contains($0.folder) })
        var map: [String: ShelfPlacement] = [:]
        for item in items {
            if let version = item.version {
                map[version] = ShelfPlacement(folder: item.folder, name: item.fileName, collection: item.collection)
            }
        }
        let present = Set(map.keys)
        for version in Array(added.keys) where present.contains(version) { added[version] = nil }
        for (version, placement) in added where map[version] == nil { map[version] = placement }
        placements = map
        let now = Set(map.keys)
        if versions != now { versions = now }
        let total = items.count + added.keys.filter { !present.contains($0) }.count
        if count != total { count = total }
    }

    /// Shows the Shelf window, selecting `folder` when given.
    func show(selecting folder: URL? = nil) {
        KeptWindowController.shared.show(shelf: self, select: folder)
    }
}
