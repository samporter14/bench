// FinishedResults.swift — what the Finished card shows of the files a session
// made (DESIGN.md, "The panel", Finished): how many, and up to three pictures
// of the images among them. It reads through the page's own artifact reader as
// the Results shelf and the reference reader do, with the same checks
// (`ArtifactGate`), and nothing else.
//
// Bounded, lazy, and only for the card shown:
//   - nothing is read until the card is the one on top (`load`), and a card
//     behind another reads nothing;
//   - one list, then at most `thumbnailLimit` thumbnails of the images in it,
//     one read at a time (a queue of its own, apart from the Results shelf's,
//     as the reference reader has: `ShelfTransfers(limit: 1)`);
//   - the pictures are decoded small and kept within a small byte budget
//     (`ShelfThumbnails`), and let go when the card is (`forget`);
//   - the task that asks being cancelled (the card going) withdraws the read,
//     down to the page's fetch.
// What is read is kept in memory only.
import SwiftUI

/// What the card's buttons are, from what is known of its files. The way
/// `CardOffer` reads a needs-input card's states: one pure rule.
struct FinishedOffer: Equatable {
    /// The button in the clay.
    enum Lead: Equatable { case results, open }

    var lead: Lead
    /// Results is offered at all: not when the session made no files.
    var hasResults: Bool
    /// Open is a plain button beside the lead.
    var hasPlainOpen: Bool { lead == .results }
    /// Keep… is offered for this file: when exactly one figure was made.
    var keepable: ArtifactEntry?

    static func of(_ listing: FinishedResults.Listing) -> FinishedOffer {
        switch listing {
        case .loaded(let entries) where entries.isEmpty:
            return FinishedOffer(lead: .open, hasResults: false, keepable: nil)
        case .loaded(let entries):
            let figures = entries.filter { $0.kind == .image }
            return FinishedOffer(lead: .results, hasResults: true, keepable: figures.count == 1 ? figures[0] : nil)
        case .failed:
            // The list couldn't be read; Results would read it the same way.
            return FinishedOffer(lead: .open, hasResults: true, keepable: nil)
        case .unknown, .reading:
            return FinishedOffer(lead: .results, hasResults: true, keepable: nil)
        }
    }
}

/// The Finished card's words, as plain values: tested without a view.
enum FinishedCardText {
    /// "3 files", "1 file"; nothing when none were made or the list isn't read.
    static func files(_ listing: FinishedResults.Listing) -> String? {
        guard case .loaded(let entries) = listing, !entries.isEmpty else { return nil }
        return entries.count == 1 ? "1 file" : "\(entries.count) files"
    }

    /// "Assay development · 21m": the project, then how long the turn took
    /// (written the one way, `TimeSpan.short`); the project alone when the
    /// length isn't known.
    static func meta(project: String, duration: TimeInterval?) -> String {
        guard let duration else { return project }
        return "\(project) · \(TimeSpan.short(duration))"
    }

    /// The whole card as VoiceOver reads it, in one sentence.
    static func spoken(title: String, project: String, duration: TimeInterval?, files: String?, reviewer: String?) -> String {
        var parts = ["Finished", title]
        if let duration {
            parts.append("\(project), \(spokenDuration(duration))")
        } else {
            parts.append(project)
        }
        parts.append(contentsOf: [files, reviewer].compactMap { $0 })
        return parts.joined(separator: ". ")
    }

    private static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return total == 1 ? "1 second" : "\(total) seconds" }
        let minutes = Int((Double(total) / 60).rounded())
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        var words: [String] = []
        if hours > 0 { words.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if rest > 0 || hours == 0 { words.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        return words.joined(separator: " ")
    }
}

@MainActor
final class FinishedResults: ObservableObject {
    /// The reads, as the shelf's queue is given them: the page's reader and
    /// whether the page is up. Tests give their own.
    struct Dependencies {
        var read: @MainActor (ArtifactRead) async -> ArtifactReadOutcome
        var isReady: @MainActor () -> Bool
        var timeout: Duration = .seconds(20)
        var wait: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

        static func live() -> Dependencies {
            Dependencies(
                read: { read in
                    guard Demo.mode == nil else { return .unreadable }
                    return await ArtifactReadAbort.abortable(read, perform: { read, nonce in
                        (try? await WebContainer.shared.readArtifact(read, nonce: nonce)) ?? .unreadable
                    }, abort: { nonce in
                        await WebContainer.shared.abortArtifactRead(nonce)
                    })
                },
                isReady: { Demo.mode == nil && WebContainer.shared.status == .ready })
        }
    }

    /// What is known of one session's files.
    enum Listing: Equatable {
        /// Not asked for: the card isn't on top.
        case unknown
        case reading
        case loaded([ArtifactEntry])
        case failed
    }

    static let shared = FinishedResults(dependencies: .live())

    /// The pictures on a card.
    static let thumbnailLimit = 3
    /// What the pictures may cost together, bytes: a dozen at most.
    static let thumbnailBudget = 1024 * 1024

    @Published private(set) var listings: [String: Listing] = [:]
    let thumbnails: ShelfThumbnails
    private let transfers: ShelfTransfers

    init(dependencies: Dependencies, thumbnails: ShelfThumbnails = ShelfThumbnails(budget: thumbnailBudget)) {
        self.thumbnails = thumbnails
        transfers = ShelfTransfers(limit: 1, read: dependencies.read, isReady: dependencies.isReady,
                                   timeout: dependencies.timeout, wait: dependencies.wait)
    }

    func listing(for sessionID: String) -> Listing { listings[sessionID] ?? .unknown }

    /// The images among the files, as many as the card shows.
    static func pictures(in entries: [ArtifactEntry]) -> [ArtifactEntry] {
        Array(entries.filter { ArtifactGate.thumb(kind: $0.kind) == nil }.prefix(thumbnailLimit))
    }

    /// Reads the session's list and then the pictures of its first images.
    /// The card is on top: cancel the calling task when it isn't, and the
    /// read in flight is withdrawn.
    func load(_ session: SessionStatus) async {
        let id = session.id
        if case .loaded = listing(for: id) {} else {
            listings[id] = .reading
            switch await transfers.read(.list(frame: id), priority: .list) {
            case .answered(.list(let entries)):
                listings[id] = .loaded(ArtifactJSON.sorted(entries))
            case .cancelled, .answered(.cancelled):
                listings[id] = nil
                return
            default:
                listings[id] = .failed
                return
            }
        }
        guard case .loaded(let entries) = listing(for: id) else { return }
        for entry in Self.pictures(in: entries) where !thumbnails.knows(entry.version) {
            if Task.isCancelled { return }
            let result = await transfers.read(.thumb(version: entry.version, width: 120), priority: .thumbnail)
            if case .answered(.bytes(let data)) = result, case .success(let webp) = ArtifactGate.thumbBytes(data) {
                thumbnails.receive(webp, for: entry.version)
            }
        }
    }

    /// Shows made-up files and pictures, and reads nothing: a demo's, a
    /// snapshot's, a test's.
    func showDemo(_ entries: [ArtifactEntry], for sessionID: String, pictures: [String: CGImage] = [:]) {
        listings[sessionID] = .loaded(entries)
        for (version, image) in pictures { thumbnails.insert(image, for: version) }
    }

    /// The card is gone: its list is let go, and the pictures with the last
    /// one (the next card reads its own).
    func forget(_ sessionID: String) {
        listings[sessionID] = nil
        if listings.isEmpty { thumbnails.removeAll() }
    }
}
