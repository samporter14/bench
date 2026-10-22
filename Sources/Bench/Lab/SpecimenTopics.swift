// SpecimenTopics.swift — which specimen plays for a session, when its title
// names a subject the field guide knows (DESIGN.md, Scenes settings → Matching
// the specimen to the session; since 1.0).
//
// Pure: a title, a session id and the scene names the user's choices allow go
// in, a specimen and the topic it was picked for come out, or nothing. The
// title's words are compared with each candidate's name and its
// `SpecimenNotes` topics, folded the way the guide's search folds them
// (`SpecimenGuide.fold`: case, accents, width) with a simple plural stripped
// from each word, so "Centrifuges" finds "centrifuge" and "genomic" finds
// "genomics". A multi-word name or topic must appear as consecutive words
// ("cell biology" is not "cell" somewhere and "biology" elsewhere).
//
// Nothing of the title is kept or returned: the topic that comes back is the
// one written in the notes (or the specimen's own name), so a caption that
// says what a specimen was picked for never carries a session's words.
//
// The choice among several matches must be the same on every read, every
// launch and every Mac: it is a stable hash of the session id (FNV-1a over its
// UTF-8 bytes, mixed by a 64-bit finaliser so that the low bit isn't just the
// parity of the bytes), not Swift's `hashValue`, which is seeded afresh for
// each process.
import Foundation

enum SpecimenTopics {
    /// The specimen for a session, matched by its title's words against each
    /// candidate's name and `SpecimenNotes` topics (folded with
    /// `SpecimenGuide.fold`: accents, case, simple plurals; multi-word topics
    /// match as phrases), chosen deterministically among the matches (seeded
    /// by the session id). Nil with no match. `candidates` are the scene names
    /// the user's choices allow (on, favourites…): a specimen not among them
    /// is never picked.
    ///
    /// A title that names a specimen itself ("Centrifuge run") picks among
    /// the specimens it names; otherwise the choice is among those whose
    /// topics it names. The topic that comes back is the matched topic as the
    /// notes write it, or, for a specimen named in the title, its own name.
    static func match(title: String, sessionID: String, candidates: [String]) -> (name: String, topic: String)? {
        match(title: title, sessionID: sessionID, candidates: candidates, index: .catalogue)
    }

    /// The same over a table of the caller's own, so a test can use made-up
    /// specimens.
    static func match(title: String, sessionID: String, candidates: [String],
                      index: SpecimenTopicIndex) -> (name: String, topic: String)? {
        let words = words(in: title)
        guard !words.isEmpty, !candidates.isEmpty else { return nil }
        var named: [(entry: SpecimenTopicIndex.Entry, topic: String)] = []
        var onTopic: [(entry: SpecimenTopicIndex.Entry, topic: String)] = []
        for name in Set(candidates) {
            let entry = index.entry(for: name)
            if !entry.nameWords.isEmpty, contains(words, phrase: entry.nameWords) {
                named.append((entry, entry.name))
                continue
            }
            // The longest topic that fits, then the one written first
            // (`max(by:)` keeps the first of equals).
            let fitting = entry.topics.filter { contains(words, phrase: $0.words) }
            if let best = fitting.max(by: { $0.words.count < $1.words.count }) {
                onTopic.append((entry, best.text))
            }
        }
        var pool = named.isEmpty ? onTopic : named
        guard !pool.isEmpty else { return nil }
        // By name, so which one is picked doesn't depend on the order the
        // caller's set happened to be read in.
        pool.sort { ($0.entry.sortKey, $0.entry.name) < ($1.entry.sortKey, $1.entry.name) }
        let chosen = pool[position(of: sessionID, among: pool.count)]
        return (chosen.entry.name, chosen.topic)
    }

    // MARK: Words

    /// The words of a text, folded and with a simple plural stripped from
    /// each. Letters and digits make words; anything else (spaces, hyphens,
    /// slashes, other punctuation) parts them, and apostrophes go without
    /// parting ("Sam's" is one word).
    static func words(in text: String) -> [String] {
        let folded = SpecimenGuide.fold(text).replacingOccurrences(of: "'", with: "")
        var words: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                words.append(stem(current))
                current = ""
            }
        }
        if !current.isEmpty { words.append(stem(current)) }
        return words
    }

    /// A simple plural made singular, the same way for every word, so a title's
    /// word and a topic's word meet whichever of the two is the plural:
    /// "-ies" becomes "-y" ("assemblies"), "-xes", "-zes", "-ches", "-shes" and
    /// "-sses" lose "-es" ("boxes", "matches"), and any other "-s" is dropped
    /// unless it ends "-ss", "-us" or "-is" ("cells", "genomics"; not "mass",
    /// "virus", "analysis"). Words of three letters or fewer stay as they are
    /// ("gas", "rna", "pcr").
    static func stem(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        for ending in ["xes", "zes", "ches", "shes", "sses"] where word.hasSuffix(ending) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }

    /// Whether `phrase` appears in `words` as consecutive words.
    static func contains(_ words: [String], phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= words.count else { return false }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
            return true
        }
        return false
    }

    // MARK: The same choice on every read

    /// FNV-1a, 64 bits, over the text's UTF-8 bytes. Fixed by definition, so
    /// the same session id picks the same specimen on every launch and Mac.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// Which of `count` matches a session gets: its stable hash through
    /// MurmurHash3's 64-bit finaliser (FNV-1a's low bit is only the parity of
    /// the bytes' low bits, which would split two matches by the id's digits),
    /// modulo `count`.
    static func position(of sessionID: String, among count: Int) -> Int {
        precondition(count > 0)
        var hash = stableHash(sessionID)
        hash ^= hash >> 33
        hash = hash &* 0xff51_afd7_ed55_8ccd
        hash ^= hash >> 33
        hash = hash &* 0xc4ce_b9fe_1a85_ec53
        hash ^= hash >> 33
        return Int(hash % UInt64(count))
    }
}

/// Every specimen's name and topics as words, built once. A plain value with
/// no globals, so a test can match against a table of its own.
struct SpecimenTopicIndex: Sendable {
    struct Topic: Sendable {
        /// As the notes write it ("cell biology").
        let text: String
        let words: [String]
    }

    struct Entry: Sendable {
        let name: String
        let nameWords: [String]
        let topics: [Topic]
        /// The name folded: what the candidates are put in order by.
        let sortKey: String
    }

    private let entries: [String: Entry]
    private let notes: [String: SpecimenNote]

    init(names: [String], notes: [String: SpecimenNote]) {
        self.notes = notes
        var entries: [String: Entry] = [:]
        for name in names { entries[name] = Self.entry(name, notes: notes) }
        self.entries = entries
    }

    /// Every specimen in the catalogue with the guide's notes.
    static let catalogue = SpecimenTopicIndex(names: LabScenes.catalogue.map(\.name), notes: SpecimenNotes.all)

    /// A name the index wasn't built with is still matched by its name (and
    /// by its notes' topics, if the table has any).
    func entry(for name: String) -> Entry {
        entries[name] ?? Self.entry(name, notes: notes)
    }

    private static func entry(_ name: String, notes: [String: SpecimenNote]) -> Entry {
        let topics = (notes[name]?.topics ?? []).compactMap { text -> Topic? in
            let words = SpecimenTopics.words(in: text)
            return words.isEmpty ? nil : Topic(text: text, words: words)
        }
        return Entry(name: name, nameWords: SpecimenTopics.words(in: name), topics: topics, sortKey: SpecimenGuide.fold(name))
    }
}
