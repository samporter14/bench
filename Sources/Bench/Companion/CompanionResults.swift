// CompanionResults.swift — "Results today" in the home popover (DESIGN.md, Menu
// bar home): the files Claude made today, in a count and four tiles.
//
// It starts from what the app already holds in memory: the lists the Results
// window, the Finished card and Since You Left have read, and the pictures
// they decoded. Where a session made today has no list in memory it reads that
// list, and only while the popover is open:
//   - at most `sessionLimit` sessions, newest first, one read at a time, each
//     in the typing gate's turn (ReadingGate), through the page's own reader
//     with the same checks as the Results shelf (`ArtifactGate`);
//   - then the pictures of the tiles shown, nothing for a file that isn't an
//     image, and nothing for a picture already in memory;
//   - closing the popover cancels the pass, down to the page's fetch, and lets
//     go of everything it read. Nothing is written to disk, and nothing is read
//     while the popover is closed.
// When more sessions made files today than were looked at, the count says so
// ("7+") rather than counting only some of them.
import Combine
import Foundation
import SwiftUI

@MainActor
final class CompanionResults: ObservableObject {
    struct Dependencies {
        /// The sessions that may have made files today, newest first.
        var candidates: @MainActor () -> [SessionStatus]
        /// The lists already in memory, by session id.
        var held: @MainActor () -> [String: [ArtifactEntry]]
        /// A picture already in memory, by version id.
        var picture: @MainActor (String) -> CGImage?
        /// The page's reader and whether it is up (and the limits of a read).
        var reader: FinishedResults.Dependencies
        /// Runs one read in its turn, once the typing has paused.
        var gate: @MainActor (@escaping @MainActor () async -> ShelfTransferResult) async -> ShelfTransferResult
        /// False reads nothing at all: what is in memory is all there is.
        var readsLists = true
        var now: @MainActor () -> Date = { Date() }
        var calendar: Calendar = .current

        @MainActor
        static func live() -> Dependencies {
            Dependencies(
                candidates: {
                    let start = Calendar.current.startOfDay(for: Date())
                    return LabModel.shared.sessions.filter { $0.updatedAt >= start }.sorted { $0.updatedAt > $1.updatedAt }
                },
                held: {
                    var lists: [String: [ArtifactEntry]] = [:]
                    for item in ResultsShelf.shared.sessions {
                        if let entries = item.results.entries { lists[item.id] = entries }
                    }
                    for finished in [FinishedResults.shared, SinceYouLeftModel.shared.finished] {
                        for (id, listing) in finished.listings {
                            if case .loaded(let entries) = listing { lists[id] = entries }
                        }
                    }
                    return lists
                },
                picture: { version in
                    ResultsShelf.shared.thumbnailStore.image(for: version)
                        ?? FinishedResults.shared.thumbnails.image(for: version)
                        ?? SinceYouLeftModel.shared.finished.thumbnails.image(for: version)
                },
                reader: .live(),
                gate: { body in
                    if Demo.mode == nil { ReadingGate.shared.start() }
                    return (try? await ReadingGate.shared.perform { await body() }) ?? .cancelled
                })
        }
    }

    /// How many sessions' lists one opening reads, at the most: what the Results window reads when it opens.
    static let sessionLimit = 8
    /// The pictures a pass may keep: four tiles' worth.
    static let thumbnailBudget = 512 * 1024

    /// Today's files from every list known, newest first, a version once.
    private(set) var entries: [ArtifactEntry] = []
    /// More sessions made files today than have been looked at.
    private(set) var partial = false
    /// Bumped when the files or a picture change, so the popover redraws.
    @Published private(set) var revision = 0
    let thumbnails: ShelfThumbnails

    private(set) var isOpen = false
    /// Lists and pictures read since the popover opened: for tests.
    private(set) var listsRead = 0
    private(set) var picturesRead = 0

    private let dependencies: Dependencies
    private let transfers: ShelfTransfers
    private var fetched: [String: [ArtifactEntry]] = [:]
    private var task: Task<Void, Never>?
    private var pictureChanges: AnyCancellable?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        thumbnails = ShelfThumbnails(budget: Self.thumbnailBudget)
        transfers = ShelfTransfers(limit: 1, read: dependencies.reader.read, isReady: dependencies.reader.isReady,
                                   timeout: dependencies.reader.timeout, wait: dependencies.reader.wait)
        pictureChanges = thumbnails.$changes.dropFirst().sink { [weak self] _ in self?.revision += 1 }
    }

    // MARK: Opening and closing

    /// The popover opened: take what is in memory, then read what is missing.
    func open() {
        guard !isOpen else { return }
        isOpen = true
        recompute()
        guard dependencies.readsLists else { return }
        task = Task { [weak self] in await self?.pass() }
    }

    /// The popover closed: the pass stops, down to the page's fetch, and everything it read is let go.
    func close() {
        guard isOpen else { return }
        isOpen = false
        task?.cancel()
        task = nil
        transfers.close()
        fetched = [:]
        entries = []
        partial = false
        thumbnails.removeAll()
        revision += 1
    }

    /// Waits for the pass under way: for tests.
    func settled() async {
        await task?.value
    }

    /// A picture for a tile: one this pass read, else one the app already holds.
    func picture(for version: String) -> CGImage? {
        thumbnails.image(for: version) ?? dependencies.picture(version)
    }

    // MARK: What is known

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return dependencies.calendar.isDate(date, inSameDayAs: dependencies.now())
    }

    /// Today's files from the lists in memory and the lists read; whether a session made today has none.
    private func recompute() {
        let held = dependencies.held()
        var seen = Set<String>()
        var found: [ArtifactEntry] = []
        for list in Array(held.values) + Array(fetched.values) {
            for entry in list where isToday(entry.at) && seen.insert(entry.version).inserted { found.append(entry) }
        }
        entries = found.sorted { a, b in
            let (x, y) = (a.at ?? .distantPast, b.at ?? .distantPast)
            return x != y ? x > y : a.name < b.name
        }
        partial = dependencies.candidates().contains { held[$0.id] == nil && fetched[$0.id] == nil }
        revision += 1
    }

    // MARK: The pass

    private func pass() async {
        let held = dependencies.held()
        let missing = dependencies.candidates().filter { held[$0.id] == nil && fetched[$0.id] == nil }
        for session in missing.prefix(Self.sessionLimit) {
            if Task.isCancelled { return }
            let id = session.id
            let result = await dependencies.gate { [transfers] in
                await transfers.read(.list(frame: id), priority: .list)
            }
            if Task.isCancelled { return }
            switch result {
            case .answered(.list(let list)):
                listsRead += 1
                fetched[id] = ArtifactJSON.sorted(list)
                recompute()
            case .cancelled, .answered(.cancelled):
                return
            default:
                // Not read (the page isn't up, a time-out, a refusal): the count says "+".
                break
            }
        }
        await readPictures()
        // A pass that was cancelled has been replaced by the next opening's: its handle isn't this one's to clear.
        if !Task.isCancelled { task = nil }
    }

    /// The pictures of the images among the tiles, that nothing holds yet.
    private func readPictures() async {
        let shown = entries.filter { ArtifactGate.thumb(kind: $0.kind) == nil }.prefix(CompanionResultsSection.tileLimit)
        for entry in shown where !thumbnails.knows(entry.version) && dependencies.picture(entry.version) == nil {
            if Task.isCancelled { return }
            let version = entry.version
            let result = await dependencies.gate { [transfers] in
                await transfers.read(.thumb(version: version, width: 120), priority: .thumbnail)
            }
            if Task.isCancelled { return }
            if case .answered(.bytes(let data)) = result, case .success(let webp) = ArtifactGate.thumbBytes(data) {
                picturesRead += 1
                thumbnails.receive(webp, for: version)
            }
        }
    }
}
