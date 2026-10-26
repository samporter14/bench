// ShelfTextIndex.swift — the words inside the Shelf's prose files, so a search
// finds a note by what it says (DESIGN.md, Shelf; since 1.0.6). The prose files
// of an item are its own file when that is Markdown or text (a document, a
// note made by Add Selection to Shelf), and Claude's legend files kept beside a
// figure (`ShelfRules.proseFiles`). Their text is read through the disk layer
// (`KeptDisk.peek`, as a card's first lines are), never on the main actor, up to
// a cap: 1 MB of a file is read, and 200,000 characters of that are kept. What
// is kept is folded for searching (case and accents set aside) and held by path
// with the file's date and size, so a file is read again only when it is not the
// one read before. Reading starts when a search is first typed and goes on
// whenever the folders are read again; typing never waits for it: a search runs
// on what has been read so far, and finds more as the reading finishes.
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "shelf-text")

/// What has been read of the prose files so far, as a search sees it: each path's text, folded. A plain value, so
/// the model holds the one it searched and a read finishing meanwhile changes nothing under it.
struct ShelfTexts: Sendable {
    fileprivate(set) var folded: [String: ContiguousArray<UInt8>] = [:]

    static let none = ShelfTexts()

    var isEmpty: Bool { folded.isEmpty }

    /// Case, accents and width set aside, the way the words of a search and the text it looks in are made alike.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whether a folded word (UTF-8) is in the text of any of these files. A word is looked for by bytes: UTF-8 can't
    /// match in the middle of a character, and a 200,000-character note is searched in microseconds.
    func contains(_ word: [UInt8], inFilesAt paths: [String]) -> Bool {
        guard !word.isEmpty else { return false }
        for path in paths {
            guard let text = folded[path], text.count >= word.count else { continue }
            let found = text.withUnsafeBufferPointer { haystack in
                word.withUnsafeBufferPointer { needle in
                    memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
                }
            }
            if found { return true }
        }
        return false
    }
}

@MainActor
final class ShelfTextIndex: ObservableObject {
    /// At most this many bytes of a file are read, and this many characters of them are kept.
    nonisolated static let readLimit = 1 << 20
    nonisolated static let indexedCharacters = 200_000

    typealias Inspect = @Sendable (URL) async -> KeptFileFacts?
    /// A file's first bytes as text, or nil when it has none to give (not text, put away in iCloud, empty). A throw
    /// is a disk that didn't answer: nothing is remembered, so the next look tries again.
    typealias Read = @MainActor (URL) async throws -> String?

    /// What is read so far, published as each file finishes.
    @Published private(set) var texts = ShelfTexts.none
    /// Reading has been asked for: a search was typed. From then on, every read of the folders refreshes it.
    private(set) var isActive = false

    private struct Entry {
        let stamp: KeptFileStamp?
    }

    private var entries: [String: Entry] = [:]
    private var task: Task<Void, Never>?
    private var wanted: [URL] = []
    private var wantedPaths: Set<String> = []
    private var again = false
    private let inspect: Inspect
    private let read: Read

    init(inspect: @escaping Inspect = KeptDisk.fileFacts(of:), read: @escaping Read) {
        self.inspect = inspect
        self.read = read
    }

    /// The index for a disk: files looked at and read through it.
    convenience init(disk: KeptDisk) {
        self.init(read: { url in try await disk.peek(url, limit: ShelfTextIndex.readLimit) })
    }

    /// Whether a read is under way: for tests.
    var isReading: Bool { task != nil }

    /// Waits for the reading under way, and for what was asked meanwhile: for tests.
    func waitUntilRead() async {
        while let task { await task.value }
    }

    /// Makes the index match `items`: files that are gone are let go, files not read yet or changed since are read.
    /// The first call starts it; after that the Shelf calls again each time the folders are read. Asks that come while
    /// a read is under way are one more pass after it.
    func update(for items: [ShelfItem]) {
        isActive = true
        var seen: Set<String> = []
        wanted = items.flatMap(ShelfRules.proseFiles(of:)).filter { seen.insert($0.path).inserted }
        wantedPaths = seen
        // What is no longer on the shelf is let go at once.
        if entries.keys.contains(where: { !seen.contains($0) }) {
            entries = entries.filter { seen.contains($0.key) }
            texts.folded = texts.folded.filter { seen.contains($0.key) }
        }
        guard task == nil else {
            again = true
            return
        }
        task = Task { [weak self] in
            guard let self else { return }
            repeat {
                again = false
                await pass()
            } while again
            task = nil
        }
    }

    private func pass() async {
        let files = wanted
        var count = 0
        for url in files {
            let path = url.path
            guard let facts = await inspect(url) else {
                // Not there, or not to be looked at: nothing of it is held.
                drop(path)
                continue
            }
            let stamp = facts.stamp
            if let held = entries[path], held.stamp == stamp { continue }
            if facts.putAway {
                // Put away in iCloud: no text, and none is fetched.
                entries[path] = Entry(stamp: stamp)
                texts.folded[path] = nil
                continue
            }
            let text: String?
            do {
                text = try await read(url)
            } catch {
                // The disk didn't answer: nothing is remembered, so the next pass tries again.
                continue
            }
            guard let text else {
                // A file with no text to give (empty, or not text) is remembered as such.
                entries[path] = Entry(stamp: stamp)
                texts.folded[path] = nil
                continue
            }
            let folded = await Task.detached(priority: .utility) { Self.prepare(text) }.value
            // The folders were read again while this one was read, and it is no longer on the shelf.
            guard wantedPaths.contains(path) else { continue }
            entries[path] = Entry(stamp: stamp)
            texts.folded[path] = folded
            count += 1
        }
        if count > 0 { log.info("Read \(count) text files for the Shelf's search") }
    }

    private func drop(_ path: String) {
        entries[path] = nil
        texts.folded[path] = nil
    }

    /// The text as it is kept: its first 200,000 characters, folded, as UTF-8.
    nonisolated static func prepare(_ text: String) -> ContiguousArray<UInt8> {
        ContiguousArray(ShelfTexts.fold(String(text.prefix(indexedCharacters))).utf8)
    }
}
