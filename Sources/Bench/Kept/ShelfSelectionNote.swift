// ShelfSelectionNote.swift — words selected in a conversation, put on the shelf (DESIGN.md,
// Shelf → The ways in → Add Selection to Shelf). A note is a kept folder like
// any other: the words as `note.md`, a document with no version of its own, and
// a README that says where they were selected. It shows on the Shelf as a
// document card with its first lines, is found by the Shelf's search by its
// title (the first words) and by its session and project, exports to PDF as a
// document does, and goes to the Trash with Undo. Pure rules here; the add
// itself is `Shelf.addNote`.
//
// The words are the user's own content. They are written to the note and
// nowhere else: not to the log, not to the toast, not to the README beyond
// what a person would read in it (the title is their first few words).
import Foundation

struct ShelfSelectionNote: Equatable, Sendable {
    let session: SessionStatus
    /// The words, as `clean` leaves them.
    let text: String

    /// The most characters a note keeps.
    static let limit = 32_000
    /// The file inside the folder.
    static let fileName = "note.md"
    /// A title is at most this many words and characters.
    static let titleWords = 8
    static let titleLimit = 64

    static let nothingSelected = "Nothing is selected any more, so there is nothing to put on your shelf."

    /// The selection as a note keeps it: line ends as `\n`, control characters
    /// but tabs and line breaks gone, blanks at either end trimmed, at most
    /// 32,000 characters. Nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let printable = String(String.UnicodeScalarView(lines.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }))
        let trimmed = printable.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }

    /// The file's bytes: the words and a final line end.
    static func data(for text: String) -> Data {
        Data((text + "\n").utf8)
    }

    // MARK: The title

    /// The first few words of the first line that has any (up to eight, in at
    /// most 64 characters, the Markdown marks off, no trailing punctuation, and
    /// an ellipsis when the line goes on) so that the card says what the note
    /// is and the search can find it by them. A passage that has no words in it
    /// ("—", "***") is "Note from <session>", or "Note" when the session has no
    /// name.
    static func title(for text: String, session: SessionStatus) -> String {
        let line = text.split(whereSeparator: \.isNewline).map { ShelfPeek.plain(String($0)) }
            .first { $0.contains { $0.isLetter || $0.isNumber } } ?? ""
        let all = line.split(whereSeparator: \.isWhitespace).map(String.init)
        var title = ""
        var used = 0
        for word in all.prefix(titleWords) {
            let next = title.isEmpty ? word : title + " " + word
            if next.count > titleLimit { break }
            title = next
            used += 1
        }
        var cut = all.count > used
        if title.isEmpty, let first = all.first {
            title = String(first.prefix(titleLimit))
            cut = true
        }
        // A folder's name can't hold "/" or ":", which would show as "_".
        title = title.replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ":", with: " ")
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let end = CharacterSet(charactersIn: ",;:.-\u{2013}\u{2014}(\u{201C}\u{2018}\"'")
        while let last = title.unicodeScalars.last, end.contains(last) || CharacterSet.whitespaces.contains(last) {
            title.removeLast()
        }
        guard title.contains(where: { $0.isLetter || $0.isNumber }) else {
            let named = session.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return named.isEmpty ? "Note" : "Note from \(String(named.prefix(titleLimit)))"
        }
        return cut ? title + "\u{2026}" : title
    }

    // MARK: The README

    /// The record and the sections for a note: no data, no code, no Claude's
    /// words (the passage may be the user's own, or a tool's, and `note.md` has
    /// it); "Where it came from" names the session, with the link that opens
    /// it in Capsid, and when the words were put on the shelf. The reply they
    /// were selected in is not named: the page does not say which reply holds
    /// a selection, and a guess would point at the wrong one.
    static func readme(session: SessionStatus, folderName: String, file: KeptFile, keptAt: Date, claudeScience: String?,
                       capsid: String, timeZone: TimeZone = .current, locale: Locale = .current)
        -> (record: KeptRecord, text: KeptText) {
        let record = KeptRecord(
            name: folderName, keptAt: keptAt, projectID: session.projectID, projectName: session.projectName,
            sessionID: session.id, sessionTitle: session.displayTitle, figure: file, files: [], missing: [],
            claudeScience: claudeScience ?? "unknown", capsid: capsid)
        let usual = KeptReadme.origin(for: record, timeZone: timeZone, locale: locale)
            .split(separator: "\n", omittingEmptySubsequences: false)
        var last = "Selected in the conversation and put on your shelf on \(KeptReadme.englishDate(keptAt, timeZone: timeZone))"
        last += " at \(KeptReadme.shortTime(keptAt, timeZone: timeZone, locale: locale))"
        last += " by Capsid" + (capsid.isEmpty ? "" : " \(capsid)")
        if let claudeScience, !claudeScience.isEmpty { last += ", from Claude Science \(claudeScience)" }
        last += ". The link opens the session in Capsid on a Mac that has it."
        let origin = [String(usual.first ?? ""), last].joined(separator: "\n")
        return (record, KeptText(legend: "", claudeSaid: "", attribution: "", origin: origin))
    }
}
