// ShelfPassage.swift — a note's whole passage on its detail card (DESIGN.md,
// Shelf; since 1.0.6). A note made by Add Selection to Shelf is a document-kind
// item whose file, `note.md`, holds the words selected and nothing else (the
// record of where they came from is the README beside it), so the passage is
// that file as `ShelfSelectionNote.clean` leaves it: line ends as `\n`, blanks at
// either end trimmed, at most 32,000 characters. A note's words are shown as
// they were selected, not rendered: what the card shows, what Copy puts on the
// pasteboard and what the file holds are one text. An ordinary document keeps
// its picture of first lines and its detail as they were.
//
// The file is read through the disk layer (`KeptDisk.peek`), off the main actor,
// once for each state of it (its date and size); the detail card asks when it is
// shown and again whenever the folders are read. Nothing about a passage is
// logged: it is the user's own words.
import Foundation

extension ShelfItem {
    /// Made by Add Selection to Shelf: a file called `note.md` with no version of its own (the same test
    /// `Shelf.addNote` makes to find a note it has added already).
    var isSelectionNote: Bool { version == nil && fileName == ShelfSelectionNote.fileName }
}

enum ShelfPassage {
    /// The most bytes of a note's file that are read: the most characters a note keeps, at four bytes each, and a final
    /// line end. A file bigger than that (it was changed in another app) is shown to the cap.
    static let readLimit = ShelfSelectionNote.limit * 4 + 4

    /// The passage a note's file holds, as the card shows it and Copy copies it. Nil when nothing is left in it.
    static func text(from raw: String) -> String? { ShelfSelectionNote.clean(raw) }

    /// The passage of `item` as the disk has it now: nil for an item that isn't a note, a file that is gone, put away in
    /// iCloud, not text or empty, or a disk that didn't answer.
    static func read(_ item: ShelfItem, disk: KeptDisk) async -> String? {
        guard item.isSelectionNote else { return nil }
        guard let raw = (try? await disk.peek(item.fileURL, limit: readLimit)) ?? nil else { return nil }
        return text(from: raw)
    }
}

/// The passages of the notes whose detail card was shown, by the path of their file, each with the state of the file it
/// was read from: a file that is not the one read before is read again. A few are kept, the newest looked at.
@MainActor
final class ShelfPassages: ObservableObject {
    typealias Inspect = @Sendable (URL) async -> KeptFileFacts?
    /// A file's text, or nil when it has none to give; a throw is a disk that didn't answer.
    typealias Read = @MainActor (URL) async throws -> String?

    /// How many passages are held.
    static let kept = 12

    private struct Held {
        let stamp: KeptFileStamp
        let text: String
    }

    @Published private var held: [String: Held] = [:]
    private var order: [String] = []
    private let inspect: Inspect
    private let read: Read

    init(inspect: @escaping Inspect = KeptDisk.fileFacts(of:), read: @escaping Read) {
        self.inspect = inspect
        self.read = read
    }

    /// The passages of a disk: files looked at and read through it.
    convenience init(disk: KeptDisk) {
        self.init(read: { url in try await disk.peek(url, limit: ShelfPassage.readLimit) })
    }

    /// The passage of `item` as last read; nil for an item that isn't a note, or one not read (yet).
    func text(for item: ShelfItem) -> String? {
        item.isSelectionNote ? held[item.fileURL.path]?.text : nil
    }

    /// Reads the passage of `item` if it isn't held for the file as it is now. Nothing for an item that isn't a note.
    /// A file that is gone, put away in iCloud (never fetched), not text or empty has no passage: one held before goes.
    func look(at item: ShelfItem) async {
        guard item.isSelectionNote else { return }
        let url = item.fileURL
        let path = url.path
        guard let facts = await inspect(url), !facts.putAway else {
            drop(path)
            return
        }
        if held[path]?.stamp == facts.stamp { return }
        let raw: String?
        do {
            raw = try await read(url)
        } catch {
            // The disk didn't answer: what is held stays, and the next look tries again.
            return
        }
        guard let raw, let text = ShelfPassage.text(from: raw) else {
            drop(path)
            return
        }
        held[path] = Held(stamp: facts.stamp, text: text)
        order.removeAll { $0 == path }
        order.append(path)
        while order.count > Self.kept { held[order.removeFirst()] = nil }
    }

    private func drop(_ path: String) {
        guard held[path] != nil else { return }
        held[path] = nil
        order.removeAll { $0 == path }
    }
}
