// ShelfDocuments.swift — which file a tile with no picture is (DESIGN.md,
// Shelf → From the conversation → Claude Science's own figure menu). A figure
// carries the address of its version, so the page script finds the file from
// that. A Markdown, CSV or text file shows no picture and carries no address at
// all: its tile shows only its name. So the script posts the name it saw, and
// this decides which file of the session that is, from the session's own list
// of files (the list the Results window reads). Pure: no page, no network.
//
// The rule is "never a wrong file". A name is matched whole and exactly. If
// the list holds one artifact by that name, its newest version is the file. If
// it holds two or more different artifacts by that name, Capsid can't tell
// which tile was meant, and says so; it does not pick the newest. If it holds
// none, it says that. The list names each artifact once, by its latest
// version, so a tile stepped back to an older version of a file is the file's
// latest one here.
import Foundation

enum ShelfDocument {
    /// The longest name the list keeps (`ArtifactReaderScript`'s cut).
    static let nameLimit = 255

    /// The name a tile showed, as a file name: one line, no control characters,
    /// the last part if it was given as a path (the list names a file by its
    /// last part), and at most 255 characters. Nil when nothing is left.
    static func name(hint: String) -> String? {
        let line = hint.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let clean = String(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        let last = clean.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let name = String(last.trimmingCharacters(in: .whitespaces).prefix(nameLimit))
        return name.isEmpty ? nil : name
    }

    enum Match: Equatable, Sendable {
        case found(ArtifactEntry)
        /// Nothing in the session's files has this name.
        case none
        /// Two or more different artifacts have it.
        case several
    }

    /// The file named `name` among `entries`. Exact: the same characters, not
    /// the same letters in another case, and not a part of a longer name.
    static func match(name: String, in entries: [ArtifactEntry]) -> Match {
        let named = entries.enumerated().filter { $0.element.name == name }
        guard !named.isEmpty else { return .none }
        // One artifact listed more than once is one file; an entry with no
        // artifact id can't be told from another, so each stands alone.
        let artifacts = Set(named.map { $0.element.artifact ?? $0.element.version })
        guard artifacts.count == 1 else { return .several }
        // The newest version: the latest time; a version with no time is older
        // than any with one, and among equals the later in the list (it is
        // listed oldest first).
        let newest = named.max { lhs, rhs in
            switch (lhs.element.at, rhs.element.at) {
            case let (left?, right?): left != right ? left < right : lhs.offset < rhs.offset
            case (nil, .some): true
            case (.some, nil): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }
        return newest.map { .found($0.element) } ?? .none
    }

    // MARK: The sentences

    static func notFound(_ name: String) -> String {
        "Capsid couldn\u{2019}t find \u{201C}\(name)\u{201D} among this conversation\u{2019}s files."
    }

    static func several(_ name: String) -> String {
        "This conversation has more than one file called \u{201C}\(name)\u{201D}, so Capsid can\u{2019}t tell which you meant. "
            + "Results lists them."
    }

    static let unreadable = "Capsid couldn\u{2019}t read this conversation\u{2019}s files just now. Try again in a moment."
}
