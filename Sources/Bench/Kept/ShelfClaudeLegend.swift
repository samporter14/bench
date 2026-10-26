// ShelfClaudeLegend.swift — Claude's own legend for a figure on the shelf
// (DESIGN.md, Shelf, "Claude's legend"). When Claude makes a figure, the same
// answer often makes a legend file too, `FIGURE_LEGENDS_final.md` or a `.md`
// that shares the figure's name. The detail card offers it, once, in a quiet
// line: "Use Claude's legend · FIGURE_LEGENDS_final.md".
//
// Finding it. The files of the answer that showed the figure are read the way
// the reference reader reads them (`ReferenceRules.answers` over the page of
// history around the README's `source_row`, the files that aren't pictures);
// nothing is read under Claude Science's own folders, and a figure with no
// known row (a keep from the Kept window, a last answer standing in) has no
// offer. A candidate is a prose file (md, markdown, txt) that is not too big
// and is not the figure itself, whose name has "legend" in it (any case) or whose
// stem is the figure's own. The best is offered first: the stem match, then a
// legend for this figure (its name has the figure's stem or a number the
// figure's name has), then a legend with no number, then a legend that names
// another figure.
//
// Using it. Everything the person sees comes from `ShelfLegendEditor`, so the
// normal save, conflict and byte-for-byte rules apply: the legend is put in the
// field and saved at once, and Claude's file is copied beside the figure and
// listed in the README (role `legend`) by the same editor, one write after the
// other. If the file has a section plainly for this figure, only that part is
// used (`part(of:fromFile:forFigure:)`); otherwise the whole file, cut at
// `cap` characters with the cut said. Something already written is asked
// about first, once. Undo is the Shelf's own dark pill: the legend goes back
// to what it was, unless it was edited since; the copy of Claude's file stays,
// because nothing in a kept folder is ever deleted.
import Foundation

// MARK: The rules, pure

enum ShelfClaudeLegendRules {
    // MARK: Which files

    /// Prose, for a legend: Markdown and plain text.
    static let proseExtensions: Set<String> = ["md", "markdown", "txt"]
    /// A legend file bigger than this isn't offered: it is a document, not a legend.
    static let sizeLimit = 1_000_000
    /// At most this many are offered.
    static let candidateLimit = 6

    /// Why a file is offered, best first.
    enum Match: Int, Comparable, Sendable {
        /// Its name without the extension is the figure's.
        case stem
        /// "Legend" is in its name, and so is the figure's stem or a number the figure's name has.
        case legendForThisFigure
        /// "Legend" is in its name, and no number is.
        case legend
        /// "Legend" is in its name, with numbers that aren't the figure's: a legend for another figure.
        case legendForAnotherFigure

        static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    struct Candidate: Equatable, Identifiable, Sendable {
        let file: HistoryFile
        let match: Match
        var id: String { file.v }
        var name: String { file.name }
    }

    /// The legend files among `files` (an answer's), best first, for `figure` (its file name). The figure's own
    /// version, files too big to be a legend or empty, a version listed twice and anything that isn't prose are left out.
    static func candidates(among files: [HistoryFile], forFigure figure: String, version: String?) -> [Candidate] {
        let figureStem = stem(of: figure).lowercased()
        let figureNumbers = numbers(inFileName: stem(of: figure))
        var seen: Set<String> = []
        var found: [Candidate] = []
        for file in files {
            guard file.v != version, seen.insert(file.v).inserted else { continue }
            guard proseExtensions.contains((file.name as NSString).pathExtension.lowercased()) else { continue }
            if let size = file.size, size == 0 || size > sizeLimit { continue }
            let fileStem = stem(of: file.name).lowercased()
            if fileStem == figureStem {
                found.append(Candidate(file: file, match: .stem))
            } else if file.name.lowercased().contains("legend") {
                let fileNumbers = numbers(inFileName: stem(of: file.name))
                let match: Match
                if (figureStem.count >= 3 && fileStem.contains(figureStem)) || !fileNumbers.isDisjoint(with: figureNumbers) {
                    match = .legendForThisFigure
                } else {
                    match = fileNumbers.isEmpty ? .legend : .legendForAnotherFigure
                }
                found.append(Candidate(file: file, match: match))
            }
        }
        // Best first; the answer's own order inside a match.
        let ranked = found.enumerated().sorted { ($0.element.match, $0.offset) < ($1.element.match, $1.offset) }.map(\.element)
        return Array(ranked.prefix(candidateLimit))
    }

    private static func stem(of name: String) -> String { (name as NSString).deletingPathExtension }

    /// A number in a name, and whether it is of a supplementary figure.
    struct Number: Hashable, Sendable {
        let n: Int
        let supplementary: Bool
    }

    /// The numbers a figure's file name carries: runs of one to three digits, not those of a date ("2026-10-22"), not a
    /// version ("v2"), "S2" and "figS2" and a name with "supp" or "extended" in it being a supplementary figure's.
    static func numbers(inFileName name: String) -> Set<Number> {
        let lower = name.lowercased()
        let supplementaryName = lower.contains("supp") || lower.contains("extended")
        let undated = lower.replacingOccurrences(of: #"\d{4}[-_.]\d{1,2}[-_.]\d{1,2}"#, with: " ", options: .regularExpression)
        let scalars = Array(undated.unicodeScalars)
        func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
        func isLetter(_ s: Unicode.Scalar) -> Bool { s.properties.isAlphabetic }
        var found: Set<Number> = []
        var i = 0
        while i < scalars.count {
            guard isDigit(scalars[i]) else { i += 1; continue }
            var j = i
            while j < scalars.count, isDigit(scalars[j]) { j += 1 }
            let start = i
            i = j
            guard j - start <= 3, let n = Int(String(String.UnicodeScalarView(scalars[start..<j]))) else { continue }
            // "v2" is a version, not a figure.
            if start >= 1, scalars[start - 1] == "v", start == 1 || !isLetter(scalars[start - 2]) { continue }
            var supplementary = supplementaryName
            if start >= 1, scalars[start - 1] == "s" {
                let before = String(String.UnicodeScalarView(scalars[0..<(start - 1)]))
                if before.isEmpty || !isLetter(before.unicodeScalars.last!) || before.hasSuffix("fig") || before.hasSuffix("figure") {
                    supplementary = true
                }
            }
            found.insert(Number(n: n, supplementary: supplementary))
        }
        return found
    }

    /// The figures a heading or a bold label names: "Figure 2", "Fig. 2", "Figure S2", "Supplementary Figure 2". A
    /// number followed by a letter ("Figure 2A", a panel) or another digit is not one.
    static func figureReferences(in label: String) -> Set<Number> {
        let text = label as NSString
        var found: Set<Number> = []
        for match in figureReference.matches(in: label, range: NSRange(location: 0, length: text.length)) {
            guard let n = Int(text.substring(with: match.range(at: 3))) else { continue }
            let supplementary = match.range(at: 1).location != NSNotFound || match.range(at: 2).location != NSNotFound
            found.insert(Number(n: n, supplementary: supplementary))
        }
        return found
    }

    // MARK: Which part

    /// Longest legend put in the field, in characters.
    static let cap = 3_000

    /// What goes into Your legend, and what was chosen.
    struct Part: Equatable, Sendable {
        enum Scope: Equatable, Sendable {
            /// The file has a section plainly for this figure; the label is its heading or bold label.
            case section(label: String)
            /// No section for it, or more than one: all of the file.
            case whole
        }

        /// The legend's words, with the cut said at the end when there is one.
        let text: String
        let scope: Scope
        /// The words were cut at `cap`.
        let cut: Bool
    }

    /// What a legend file's bytes come to for a figure.
    enum Reading: Equatable, Sendable {
        case part(Part)
        /// Not text Capsid can read (a NUL in it, or not UTF-8).
        case notText
        /// Nothing but blank lines.
        case empty
    }

    /// `bytes` of Claude's legend file `fileName`, read the one way for everything that puts a legend in a field: the
    /// Shelf's "Use Claude's legend" and Keep with Data and Code (since 1.0.6) both go through here, so the same file gives
    /// the same words wherever it is used.
    static func reading(_ bytes: Data, fileName: String, forFigure figure: String) -> Reading {
        guard let read = ReferenceFileRules.text(from: bytes) else { return .notText }
        guard !normalized(read.text).isEmpty else { return .empty }
        return .part(part(of: read.text, fromFile: fileName, forFigure: figure))
    }

    /// A heading ("## Figure 2") or a bold label at the start of a line ("**Figure 2.** …").
    private struct Marker {
        let line: Int
        /// The heading's level; nil for a bold label.
        let level: Int?
        let label: String
        /// How plainly it names the figure: its file name (0), its stem (1), its number (2).
        var rank = 0
    }

    private static let figureReference = try! NSRegularExpression(
        pattern: #"(?i)(?:\b(supplementary|suppl\.?|extended\s+data)\s+)?\bfig(?:ure)?s?\.?\s*(s)?(\d{1,3})(?![0-9A-Za-z])"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$"#)
    private static let boldPattern = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[-*+][ \t]+|\d+[.)][ \t]+)?(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)

    /// The text as it is used: no byte order mark, plain line ends, no blank lines at the ends.
    static func normalized(_ text: String) -> String {
        var plain = text
        if plain.hasPrefix("\u{FEFF}") { plain.removeFirst() }
        plain = plain.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return plain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The part of `fileText` (Claude's legend file, `fileName`) to put in the legend of `figure`: the section plainly
    /// for it, else the whole file; at most `limit` characters either way, the cut said.
    ///
    /// A section is plainly for the figure when its heading or bold label names the figure's file name, its stem (at
    /// least three characters, as a word of its own), or "Figure N" / "Fig. N" for a number N the figure's name has. The
    /// best of those wins; two sections that are equally plain (outside each other) are not plain, and the whole file is
    /// used. A heading's section runs to the next heading of its level or higher; a bold label's to the next heading or the
    /// next bold label that opens a figure. The heading line itself is left out when it only names the figure ("Figure
    /// 2", its file name, its stem), else it opens the text without its "#"s; a bold label is part of the sentence and stays.
    static func part(of fileText: String, fromFile fileName: String, forFigure figure: String, limit: Int = cap) -> Part {
        let text = normalized(fileText)
        let lines = text.components(separatedBy: "\n")
        let markers = self.markers(in: lines)
        let figureName = figure.lowercased()
        let figureStem = stem(of: figure).lowercased()
        let figureNumbers = numbers(inFileName: stem(of: figure))

        var named: [Marker] = []
        for var marker in markers {
            let lower = marker.label.lowercased()
            if contains(lower, word: figureName) {
                marker.rank = 0
            } else if figureStem.count >= 3, contains(lower, word: figureStem) {
                marker.rank = 1
            } else if !figureNumbers.isEmpty, !figureReferences(in: marker.label).isDisjoint(with: figureNumbers) {
                marker.rank = 2
            } else {
                continue
            }
            named.append(marker)
        }
        if let best = named.map(\.rank).min() {
            // The best sort of match, and of those only the outermost ones: a "Figure 2." label inside the
            // "## Figure 2" section it belongs to is the same section.
            var kept: [(marker: Marker, end: Int)] = []
            for marker in named where marker.rank == best {
                let end = sectionEnd(of: marker, markers: markers, lines: lines.count)
                if kept.contains(where: { marker.line > $0.marker.line && marker.line < $0.end }) { continue }
                kept.append((marker, end))
            }
            if kept.count == 1, let one = kept.first {
                var body = Array(lines[(one.marker.level == nil ? one.marker.line : one.marker.line + 1)..<one.end])
                while let first = body.first, first.trimmingCharacters(in: .whitespaces).isEmpty { body.removeFirst() }
                var section = body
                // A heading that only names the figure (its number, its file name, its stem) is dropped; one with words of its own opens the text.
                let lowerLabel = one.marker.label.lowercased()
                let bare = isBareFigureLabel(one.marker.label) || lowerLabel == figureName || lowerLabel == figureStem
                if one.marker.level != nil, !bare { section = [one.marker.label, ""] + body }
                let (shown, cut) = truncated(unbolded(section.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines), limit: limit)
                return Part(text: cut ? shown + "\n\n" + cutNote(fileName) : shown, scope: .section(label: shortLabel(one.marker.label)), cut: cut)
            }
        }
        let (shown, cut) = truncated(unbolded(text), limit: limit)
        return Part(text: cut ? shown + "\n\n" + cutNote(fileName) : shown, scope: .whole, cut: cut)
    }

    /// The headings and bold labels of the lines, in order.
    private static func markers(in lines: [String]) -> [Marker] {
        var found: [Marker] = []
        var fenced = false
        for (line, text) in lines.enumerated() {
            // Code in a legend file is not a heading.
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
            guard !fenced else { continue }
            let range = NSRange(location: 0, length: (text as NSString).length)
            if let match = headingPattern.firstMatch(in: text, range: range) {
                let level = (text as NSString).substring(with: match.range(at: 1)).count
                found.append(Marker(line: line, level: level, label: cleaned((text as NSString).substring(with: match.range(at: 2)))))
            } else if let match = boldPattern.firstMatch(in: text, range: range) {
                found.append(Marker(line: line, level: nil, label: cleaned((text as NSString).substring(with: match.range(at: 2)))))
            }
        }
        return found
    }

    private static let doubleStars = try! NSRegularExpression(pattern: #"\*\*(?=[^*\s])((?:(?!\*\*).)+?)(?<=[^*\s])\*\*"#)
    private static let doubleUnderscores = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])__(?=[^_\s])((?:(?!__).)+?)(?<=[^_\s])__(?![A-Za-z0-9_])"#)

    /// The legend's words without Markdown's bold marks, since "Your legend" is a plain field (since 1.0.6): "**Edge
    /// effects.**" reads "Edge effects.". Only a pair around words goes: significance stars ("****"), a lone "*",
    /// snake_case names, code between backticks and fenced code are left as they are.
    static func unbolded(_ text: String) -> String {
        var fenced = false
        return text.components(separatedBy: "\n").map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); return line }
            guard !fenced, line.contains("**") || line.contains("__") else { return line }
            // Between backticks is code: the even pieces are prose, the odd ones code.
            return line.components(separatedBy: "`").enumerated().map { index, piece -> String in
                guard index.isMultiple(of: 2) else { return piece }
                var plain = piece
                for pattern in [doubleStars, doubleUnderscores] {
                    plain = pattern.stringByReplacingMatches(in: plain, range: NSRange(location: 0, length: (plain as NSString).length),
                                                             withTemplate: "$1")
                }
                return plain
            }.joined(separator: "`")
        }.joined(separator: "\n")
    }

    /// A label without its emphasis marks and backticks, on one line.
    private static func cleaned(_ label: String) -> String {
        label.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The line after the last one of `marker`'s section.
    private static func sectionEnd(of marker: Marker, markers: [Marker], lines: Int) -> Int {
        for next in markers where next.line > marker.line {
            if let level = marker.level {
                if let nextLevel = next.level, nextLevel <= level { return next.line }
            } else if next.level != nil || opensFigure(next.label) {
                return next.line
            }
        }
        return lines
    }

    /// A bold label that opens a figure's legend of its own ("Figure 3.", "Fig. S1", "fig4_umap.png"), not a panel's.
    private static func opensFigure(_ label: String) -> Bool {
        let lower = label.lowercased()
        if lower.hasPrefix("fig") || lower.hasPrefix("supplementary") || lower.hasPrefix("extended data") { return true }
        return lower.range(of: #"\.(png|jpe?g|svg|pdf|tiff?|gif|webp)\b"#, options: .regularExpression) != nil
    }

    /// "Figure 2", "Fig. S1:": a heading that says nothing but which figure.
    private static func isBareFigureLabel(_ label: String) -> Bool {
        label.range(of: #"(?i)^(supplementary\s+|suppl\.?\s+|extended\s+data\s+)?fig(ure)?s?\.?\s*s?\d{1,3}[a-z]?\s*[.:]?$"#,
                    options: .regularExpression) != nil
    }

    /// Whether `word` is in `text` as a word of its own: nothing but a mark, a space or the end on either side
    /// (letters, digits and "_" are parts of a word). Both are lowercase.
    private static func contains(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        var from = text.startIndex
        while let found = text.range(of: word, range: from..<text.endIndex) {
            let beforeOK = found.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: found.lowerBound)])
            let afterOK = found.upperBound == text.endIndex || !isWordCharacter(text[found.upperBound])
            if beforeOK, afterOK { return true }
            from = text.index(after: found.lowerBound)
        }
        return false
    }

    /// A label for a sentence: one line, at most 40 characters, no closing full stop or colon.
    private static func shortLabel(_ label: String) -> String {
        var text = label
        while let last = text.last, last == "." || last == ":" || last == " " { text.removeLast() }
        return text.count > 40 ? String(text.prefix(39)) + "\u{2026}" : text
    }

    /// `text` cut to at most `limit` characters: at the end of a paragraph, else of a line, else of a word, when
    /// that leaves at least half of it.
    static func truncated(_ text: String, limit: Int) -> (text: String, cut: Bool) {
        guard text.count > limit else { return (text, false) }
        let head = String(text.prefix(limit))
        for separator in ["\n\n", "\n", " "] {
            if let found = head.range(of: separator, options: .backwards),
               head.distance(from: head.startIndex, to: found.lowerBound) >= limit / 2 {
                return (String(head[..<found.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), true)
            }
        }
        return (head.trimmingCharacters(in: .whitespacesAndNewlines), true)
    }

    /// The last line of a legend that was cut.
    static func cutNote(_ fileName: String) -> String { "[Cut here: the rest is in \(fileName).]" }

    // MARK: The answer's files

    /// How many rows after the README's row the page covers: the reply's files sit under its last message.
    static let rowsAhead = 25

    /// The files of the answer that holds history row `row`, in `page`, as the reference reader tells them: the files
    /// that aren't pictures, one for each artifact, less those Claude Science hides. Empty when no answer on the page
    /// holds the row.
    static func files(ofAnswerAtRow row: Int, in page: HistoryPage) -> [HistoryFile] {
        let answers = ReferenceRules.answers(items: page.items, reachedStart: page.from == 0, whole: [:])
        guard let answer = answers.first(where: { $0.start <= row && row <= ($0.rowEnd ?? Int.max) }) else { return [] }
        return ReferenceFileRules.documents(of: answer)
    }

    // MARK: The offer

    static let useTitle = "Use Claude\u{2019}s legend"
    static let replaceTitle = "Replace with Claude\u{2019}s legend\u{2026}"

    enum Offer: Equatable, Sendable {
        /// The legend is empty: one line to use Claude's.
        case use([Candidate])
        /// A legend is written: replacing it asks once.
        case replace([Candidate])

        var candidates: [Candidate] {
            switch self {
            case .use(let found), .replace(let found): found
            }
        }

        var title: String {
            switch self {
            case .use: ShelfClaudeLegendRules.useTitle
            case .replace: ShelfClaudeLegendRules.replaceTitle
            }
        }

        var asksFirst: Bool {
            if case .replace = self { return true }
            return false
        }
    }

    /// What the card offers for a legend as it stands. Nothing when there is no candidate, or when the legend is
    /// exactly what Claude's put in (`applied`) and the person hasn't touched it.
    static func offer(candidates: [Candidate], legend: String, applied: String?) -> Offer? {
        guard !candidates.isEmpty else { return nil }
        if let applied, applied == legend { return nil }
        return legend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .use(candidates) : .replace(candidates)
    }

    // MARK: The sentences

    static let replaceQuestion = "Replace your legend?"
    static let replaceButton = "Replace"

    static func replaceMessage(file: String) -> String {
        "Your legend will be replaced with Claude\u{2019}s, from \(file). Undo is on the line that follows."
    }

    /// How the copy of Claude's file beside the figure came out.
    enum Filing: Equatable, Sendable {
        case copied
        /// It was listed already (the same version): nothing was copied again.
        case alreadyThere
        case notCopied(String)
    }

    /// What was put in, said once, on the pill: which part and from which file, and what became of the file.
    static func putIn(_ part: Part, file: String, figure: String, filing: Filing) -> String {
        var sentence: String
        switch part.scope {
        case .section(let label):
            sentence = part.cut
                ? "Put in the first \(characters(cap)) characters of Claude\u{2019}s legend for \u{201C}\(label)\u{201D} from \(file)."
                : "Put in Claude\u{2019}s legend for \u{201C}\(label)\u{201D} from \(file)."
        case .whole:
            sentence = part.cut
                ? "Put in the first \(characters(cap)) characters of \(file), which has no section for \(short(figure))."
                : "Put in all of \(file), which has no section for \(short(figure))."
        }
        switch filing {
        case .copied: sentence += " The file is beside the figure."
        case .alreadyThere: break
        case .notCopied(let why): sentence += " The file itself wasn\u{2019}t copied: \(why)"
        }
        return sentence
    }

    static func characters(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    static func short(_ name: String) -> String { name.count > 32 ? String(name.prefix(31)) + "\u{2026}" : name }

    /// Nothing was changed.
    static func notChanged(_ why: String) -> String {
        "Couldn\u{2019}t put Claude\u{2019}s legend in. \(why) Nothing was changed."
    }

    static func gone(_ file: String) -> String { "\(file) isn\u{2019}t in Claude Science any more." }
    static func tooBig(_ file: String) -> String { "\(file) is too big to be a legend." }
    static func notText(_ file: String) -> String { "\(file) isn\u{2019}t text Capsid can read." }
    static func empty(_ file: String) -> String { "\(file) is empty." }
    static let stopped = "It was stopped."
    static let undone = "Put your legend back as it was."
    static let editedSince = "Your legend was edited since, so it was left as it is."

    static func couldntUndo(_ why: String) -> String { "Couldn\u{2019}t put your legend back. \(why)" }
}

// MARK: The coordinator

/// What the card knows of Claude's legend files, and what using one does (`ShelfModel.useClaudeLegend`). One for the
/// Shelf window: it looks at an item once, when its card is first shown, and keeps what it found.
@MainActor
final class ShelfClaudeLegend: ObservableObject {
    typealias Rules = ShelfClaudeLegendRules
    typealias Candidate = ShelfClaudeLegendRules.Candidate

    /// What a look at an item came to.
    enum Look: Equatable {
        case looking
        case nothing
        case found([Candidate])
    }

    /// What Undo needs: whose legend, what was put in, what it was before.
    struct Undo: Equatable, Sendable {
        let itemID: String
        let put: String
        let before: String
    }

    struct Done: Equatable {
        let sentence: String
        /// Nil when the legend was already what Claude's would make it.
        let undo: Undo?
    }

    enum Outcome: Equatable {
        /// A legend is written, and nothing has been changed: ask, then use it again with `confirmed`.
        case needsConfirmation
        case done(Done)
        /// Nothing was changed; the sentence says why.
        case failed(String)
        /// This item's legend is going in already.
        case busy
    }

    @Published private(set) var looks: [String: Look] = [:]
    /// Items whose legend is going in.
    @Published private(set) var busy: Set<String> = []
    /// What Claude's legend put in an item's field, while the field still holds exactly that: the offer waits until
    /// the person changes it.
    @Published private(set) var applied: [String: String] = [:]

    private let dependencies: @MainActor () -> ShelfDependencies

    init(dependencies: @escaping @MainActor () -> ShelfDependencies) {
        self.dependencies = dependencies
    }

    /// Whether the card can look for a legend file at all: a figure whose README knows the row of the message that
    /// showed it.
    static func canLook(at item: ShelfItem) -> Bool {
        item.kind == .figure && item.version != nil && item.record.sourceRow != nil && PlanCheck.isFrameID(item.record.sessionID)
            && !ShelfRules.isLastAnswer(item.text)
    }

    func candidates(for item: ShelfItem) -> [Candidate] {
        if case .found(let found)? = looks[item.id] { return found }
        return []
    }

    /// What the card offers, for the legend it shows now.
    func offer(for item: ShelfItem, legend: String) -> Rules.Offer? {
        Rules.offer(candidates: candidates(for: item), legend: legend, applied: applied[item.id])
    }

    // MARK: Looking

    /// Reads the files of the answer that showed the figure, once for an item; an unreadable page is tried again the
    /// next time the card is shown.
    func look(at item: ShelfItem) async {
        let id = item.id
        guard looks[id] == nil else { return }
        guard Self.canLook(at: item), let row = item.record.sourceRow else {
            looks[id] = .nothing
            return
        }
        looks[id] = .looking
        // A card left meanwhile still keeps what was read: it is true of the item.
        guard let files = await dependencies().answerFiles(item.record.sessionID, row) else {
            looks[id] = nil
            return
        }
        let found = Rules.candidates(among: files, forFigure: item.fileName, version: item.version)
        looks[id] = found.isEmpty ? .nothing : .found(found)
    }

    // MARK: Using

    /// Puts `candidate`'s legend in `item`'s field through `editor`, and copies the file beside the figure. Nothing is
    /// changed when it fails, or when a written legend is there and `confirmed` is false.
    func use(_ candidate: Candidate, for item: ShelfItem, editor: ShelfLegendEditor, confirmed: Bool) async -> Outcome {
        let id = item.id
        guard busy.insert(id).inserted else { return .busy }
        defer { busy.remove(id) }
        let d = dependencies()
        let name = candidate.name

        // The README as it is now; one that can't be read ends it here, with the editor's own sentence.
        if !editor.canEdit { await editor.load() }
        guard editor.canEdit else { return .failed(editor.problem ?? Rules.notChanged("")) }
        if let waiting = editor.waitingOnThePerson { return .failed(Rules.notChanged(waiting)) }
        if !confirmed, !editor.legend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .needsConfirmation }

        // Claude's file: the bytes are the legend and the copy.
        let fileName = KeptLayout.fileName(name)
        let kept = KeepItem(role: .legend, source: .download(version: candidate.file.v), artifact: candidate.file.a, version: candidate.file.v,
                            name: fileName, size: candidate.file.size, sha: nil)
        let bytes: Data
        switch await d.keep.fetch(kept) {
        case .bytes(let data, _): bytes = data
        case .gone: return .failed(Rules.notChanged(Rules.gone(name)))
        case .tooBig: return .failed(Rules.notChanged(Rules.tooBig(name)))
        case .failed(let why): return .failed(Rules.notChanged("Couldn\u{2019}t get \(name). \(why)"))
        case .cancelled: return .failed(Rules.notChanged(Rules.stopped))
        }
        let part: Rules.Part
        switch Rules.reading(bytes, fileName: name, forFigure: item.fileName) {
        case .notText: return .failed(Rules.notChanged(Rules.notText(name)))
        case .empty: return .failed(Rules.notChanged(Rules.empty(name)))
        case .part(let found): part = found
        }

        // The legend, by the field's own save: the conflict rule and the byte rules are the editor's.
        var undo: Undo?
        switch await editor.put(part.text) {
        case .failed(let why): return .failed(Rules.notChanged(why))
        case .unchanged: break
        case .saved(let before): undo = Undo(itemID: id, put: part.text, before: before)
        }
        applied[id] = part.text

        // The file beside the figure, listed in the README; the legend stays if this can't be done.
        let record = KeptFile(path: fileName, role: .legend, artifact: candidate.file.a, version: candidate.file.v, index: nil, of: nil,
                              sha256: d.keep.disk.sha256(of: bytes), bytes: bytes.count)
        let filing: Rules.Filing
        switch await editor.list(bytes, as: record) {
        case .listed: filing = .copied
        case .alreadyListed: filing = .alreadyThere
        case .failed(let why): filing = .notCopied(why)
        }
        return .done(Done(sentence: Rules.putIn(part, file: name, figure: item.fileName, filing: filing), undo: undo))
    }

    /// Undo on the pill: the legend as it was, unless it was edited since. Answers the sentence to say.
    func undo(_ undo: Undo, editor: ShelfLegendEditor) async -> String {
        switch await editor.undoPut(undo.put, restoring: undo.before) {
        case .restored:
            applied[undo.itemID] = nil
            return Rules.undone
        case .edited:
            applied[undo.itemID] = nil
            return Rules.editedSince
        case .failed(let why):
            return Rules.couldntUndo(why)
        }
    }
}

// MARK: The model's side

extension ShelfModel {
    /// Uses Claude's legend for the selected item or one given, and says what came of it on the pill, with Undo when
    /// the legend changed.
    func useClaudeLegend(_ candidate: ShelfClaudeLegend.Candidate, for item: ShelfItem, confirmed: Bool) async {
        let outcome = await claudeLegend.use(candidate, for: item, editor: legendEditor(for: item), confirmed: confirmed)
        switch outcome {
        case .needsConfirmation, .busy: break
        case .failed(let sentence): say(sentence)
        case .done(let done): say(done.sentence, legend: done.undo)
        }
    }

    /// Undo on the pill after Claude's legend went in.
    func undoLegend() {
        guard let undo = note?.legend else { return }
        dismissNote()
        guard let item = items.first(where: { $0.id == undo.itemID }) else {
            say(ShelfClaudeLegendRules.couldntUndo("It isn\u{2019}t on the shelf any more."))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            say(await claudeLegend.undo(undo, editor: legendEditor(for: item)))
        }
    }

    /// Undo on the pill: the removal's, or the legend's.
    func undoNote() {
        if note?.legend != nil { undoLegend() } else { undoRemoval() }
    }
}
