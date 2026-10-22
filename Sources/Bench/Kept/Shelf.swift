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
// THE CONTRACT. The shelf-core agent implements this file; the shelf-add
// agent calls it from the conversation, Results and the reference window.
// Names and shapes here are fixed; the bodies are placeholders until then.
import AppKit
import Foundation

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
    /// The file's name as shown ("z_prime_by_plate.png").
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

@MainActor
final class Shelf: ObservableObject {
    static let shared = Shelf()

    /// Version ids on the shelf, for "On Shelf ✓" and the "On your shelf" mark.
    @Published private(set) var versions: Set<String> = []
    /// Adds under way, by version id: a spinner where it was asked.
    @Published private(set) var adding: Set<String> = []

    func contains(version: String) -> Bool { versions.contains(version) }

    /// Puts one file on the shelf: copied, with Claude's words and where it
    /// came from. One at a time per version; a second ask while the first
    /// runs answers with the first's outcome.
    func add(_ source: ShelfSource) async -> ShelfAddOutcome {
        .failed("The shelf isn\u{2019}t built yet.")
    }

    /// Undo, right after an add: the folder goes to the Trash (never deleted).
    func undo(_ placement: ShelfPlacement) async -> Bool { false }

    /// Shows the Shelf window, selecting `folder` when given.
    func show(selecting folder: URL? = nil) {
        KeptWindowController.shared.show(select: folder)
    }
}
