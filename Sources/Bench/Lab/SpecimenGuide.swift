// SpecimenGuide.swift — looking up a specimen's note, and searching the guide
// (DESIGN.md, "Scenes settings"). The logic is here and the table is in
// SpecimenNotes.swift, so regenerating the table doesn't touch it.
import Foundation

enum SpecimenGuide {
    /// What a caption and a note may hold, which the table is held to.
    static let captionLimit = 36
    static let noteLimit = 140

    /// What the guide says about a specimen, if it says anything.
    static func note(for name: String) -> SpecimenNote? {
        SpecimenNotes.all[name]
    }

    /// "Kinesin · A motor protein on a microtubule", for the panel's quiet
    /// line. A specimen with no note is its name alone, so the line never
    /// comes up empty.
    static func line(for name: String, notes: [String: SpecimenNote] = SpecimenNotes.all) -> String {
        guard let caption = notes[name]?.caption, !caption.isEmpty else { return name }
        return "\(name) · \(caption)"
    }

    /// A topic as a menu shows it: its first letter capitalised, the rest as
    /// written, so "cell biology" reads "Cell biology" and "PCR" stays.
    static func title(of topic: String) -> String {
        topic.prefix(1).uppercased() + topic.dropFirst()
    }

    /// Every topic in use, once each, in alphabetical order. Taken from the
    /// table itself rather than listed here, so a new table brings its own.
    static let topics: [String] = topics(in: SpecimenNotes.all)

    static func topics(in notes: [String: SpecimenNote]) -> [String] {
        var seen: [String: String] = [:]
        // By name, so the spelling that stays doesn't depend on the order a
        // dictionary happens to be read in.
        for (_, note) in notes.sorted(by: { $0.key < $1.key }) {
            for topic in note.topics {
                // "Optics" and "optics" are one topic; the first spelling stays.
                seen[fold(topic)] = seen[fold(topic)] ?? topic
            }
        }
        return seen.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The text without its case, accents and width, and with one kind of
    /// apostrophe, so "Ångström" and "angstrom" read as the same word. Not
    /// localised: the same text folds the same way on every Mac.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
    }

    /// The words of a search, folded. Empty when there is nothing to search for.
    static func words(in query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every specimen in the catalogue, searched with the table. Built once,
    /// since folding every note is the cost.
    static let index = SpecimenIndex(names: LabScenes.catalogue.map(\.name), notes: SpecimenNotes.all)
}

/// Every specimen's words, folded once, to search by. A plain value with no
/// globals, so a test can search a table of its own.
struct SpecimenIndex: Sendable {
    private struct Entry: Sendable {
        let name: String
        // Folded, so a search folds only what was typed.
        let folded: String
        let topics: String
        let also: String
        let caption: String
        let note: String
        /// All of the above in one string, for the quick check that every
        /// word of a search is somewhere in it. The fields are joined by
        /// newlines, which a word never holds, so no word spans two of them.
        let everything: String
    }

    /// How well a specimen matches, best first. A word that starts the name
    /// is better than one inside it, a name is better than a deliberate
    /// topic or alias, those are better than the prose, and the caption is
    /// better than the note. Words found in different places come last.
    private enum Rank: Int, Comparable {
        case nameStart, nameInside, topic, also, caption, note, scattered

        static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
    }

    private let entries: [Entry]

    init(names: [String], notes: [String: SpecimenNote]) {
        entries = names.map { name in
            let note = notes[name]
            let folded = SpecimenGuide.fold(name)
            let topics = SpecimenGuide.fold((note?.topics ?? []).joined(separator: "\n"))
            let also = SpecimenGuide.fold((note?.also ?? []).joined(separator: "\n"))
            let caption = SpecimenGuide.fold(note?.caption ?? "")
            let text = SpecimenGuide.fold(note?.note ?? "")
            return Entry(name: name, folded: folded, topics: topics, also: also, caption: caption, note: text,
                         everything: [folded, topics, also, caption, text].joined(separator: "\n"))
        }
    }

    /// The names that match, best first, and in the order they were given
    /// among equals. A specimen matches when every word of the search is
    /// somewhere in its name, caption, note, topics or alias words. An empty
    /// search matches every name, in the order given.
    func search(_ query: String) -> [String] {
        let words = SpecimenGuide.words(in: query)
        guard !words.isEmpty else { return entries.map(\.name) }
        let phrase = words.joined(separator: " ")
        let ranked: [(rank: Rank, position: Int, name: String)] = entries.enumerated().compactMap { position, entry in
            guard let rank = Self.rank(of: entry, words: words, phrase: phrase) else { return nil }
            return (rank, position, entry.name)
        }
        return ranked.sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }.map(\.name)
    }

    private static func rank(of entry: Entry, words: [String], phrase: String) -> Rank? {
        guard words.allSatisfy({ entry.everything.contains($0) }) else { return nil }
        if startsAWord(phrase, in: entry.folded) { return .nameStart }
        let fields: [(Rank, String)] = [
            (.nameInside, entry.folded), (.topic, entry.topics), (.also, entry.also),
            (.caption, entry.caption), (.note, entry.note),
        ]
        return fields.first { _, text in words.allSatisfy { text.contains($0) } }?.0 ?? .scattered
    }

    /// Whether `phrase` starts the text or any word in it ("ray" starts a
    /// word in "x-ray diffraction", and not one in "spray").
    private static func startsAWord(_ phrase: String, in text: String) -> Bool {
        text.ranges(of: phrase).contains { range in
            guard range.lowerBound > text.startIndex else { return true }
            let before = text[text.index(before: range.lowerBound)]
            return !before.isLetter && !before.isNumber
        }
    }
}
