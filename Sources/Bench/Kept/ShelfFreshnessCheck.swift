// ShelfFreshnessCheck.swift — asking Claude Science whether a kept figure, or the data it was drawn from, has a newer
// version (DESIGN.md, Shelf → Out of date). The rules are ShelfFreshness.swift's; this is the asking.
//
// One read, and only one: `GET /api/artifacts/<artifact>/versions`, a pure read the page makes for its own version
// stepper. Never the lineage read, which can start a model call. It is asked when a card, a detail or a paper's slot
// comes into view and when the person presses Check, never on a timer (Efficiency): each artifact once for as long as
// the Shelf window is open, through the Results shelf's queue at the list's priority, at most three at a time, and
// let go when the window closes. Several items of one artifact share the one read.
//
// What can't be learned says nothing. A daemon that is down, a page not signed in, a read that timed out or came back
// in a shape Capsid doesn't know is `unknown`, and an item with nothing known has no mark: never a false alarm. A 404 or
// 410 is a fact ("This version isn't in Claude Science any more.").
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "shelf-fresh")

@MainActor
final class ShelfFreshnessCheck: ObservableObject {
    /// The one read, as the shelf's queue answers it; the demo and the tests give their own.
    typealias Read = @MainActor (_ artifact: String) async -> ShelfTransferResult

    /// What each artifact's read said, this window session.
    @Published private(set) var answers: [String: VersionsAnswer] = [:]
    /// Reads asked for or under way.
    @Published private(set) var pending: Set<String> = []

    private let read: Read
    private let limit: Int
    private var queue: [String] = []
    private var running = 0
    /// Bumped by `reset`: an answer for an earlier session is dropped.
    private var session = 0
    private var asked = 0

    init(read: @escaping Read, limit: Int = 3) {
        self.read = read
        self.limit = max(1, limit)
    }

    /// The real reads: the Results shelf's queue, as Keep's are. Nothing in a demo but the demo's own.
    static func live(shelf: ResultsShelf = .shared) -> ShelfFreshnessCheck {
        ShelfFreshnessCheck(read: { artifact in
            guard Demo.mode == nil else { return .notReady }
            return await shelf.transfers.read(.versions(artifact: artifact), priority: .list)
        })
    }

    var isChecking: Bool { !pending.isEmpty }

    /// The verdict for an item, from what has been read so far: `.unknown` until its reads are back.
    func verdict(for item: ShelfItem) -> ShelfFreshness {
        ShelfFreshnessRules.verdict(for: item.record, answers: answers)
    }

    /// Whether every read an item needs is back (or can't be made): a check under way for it is not yet a verdict.
    func isSettled(_ item: ShelfItem) -> Bool {
        ShelfFreshnessRules.artifacts(of: item.record).allSatisfy { answers[$0] != nil && !pending.contains($0) }
    }

    /// Asks for the reads `items` need that haven't been asked this session. Cheap to call again and again (a card
    /// coming into view): an artifact asked once is not asked twice.
    func check(_ items: [ShelfItem]) {
        for item in items {
            for artifact in ShelfFreshnessRules.artifacts(of: item.record) where answers[artifact] == nil && !pending.contains(artifact) {
                enqueue(artifact)
            }
        }
        pump()
    }

    /// The person's Check: `items`' artifacts read again, whatever was read before. What was known stays shown until
    /// the new answer replaces it.
    func checkAgain(_ items: [ShelfItem]) {
        for item in items {
            for artifact in ShelfFreshnessRules.artifacts(of: item.record) where !pending.contains(artifact) {
                enqueue(artifact)
            }
        }
        pump()
    }

    /// The window closed: everything read is let go, and reads still out are dropped when they come back.
    func reset() {
        session += 1
        answers = [:]
        pending = []
        queue = []
        running = 0
    }

    private func enqueue(_ artifact: String) {
        pending.insert(artifact)
        queue.append(artifact)
    }

    private func pump() {
        while running < limit, !queue.isEmpty {
            let artifact = queue.removeFirst()
            running += 1
            let session = self.session
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await read(artifact)
                guard session == self.session else { return }
                running -= 1
                pending.remove(artifact)
                // A read withdrawn (the window closed under it) is no answer: asked again next time.
                if let answer = VersionsAnswer.from(result) { answers[artifact] = answer }
                asked += 1
                if queue.isEmpty, running == 0 { note() }
                pump()
            }
        }
    }

    /// One line when a run of reads ends: counts only, never a name or an id.
    private func note() {
        let unknown = answers.values.filter { $0 == .unknown }.count
        log.notice("Out of date: \(self.asked, privacy: .public) reads, \(unknown, privacy: .public) unknown")
        asked = 0
    }
}
