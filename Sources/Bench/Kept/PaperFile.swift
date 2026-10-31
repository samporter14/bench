// PaperFile.swift — the PAPER.md file that organises kept Shelf items as a
// manuscript's figures, and the rules for changing one. A paper is only a list
// of panel labels ("1A", "S2C") and, for each, which kept folder fills it. The
// folders stay the record of the figures themselves: the paper never copies
// them, never moves them and never owns them, so taking a panel out of a paper
// can't lose a figure.
//
// Like the kept README (`KeptReadme`), the renderer and the parser are a pair
// and the parser is strict about the front matter on purpose. It reads only the
// shape the renderer writes (exact lines in exact order, one `- { … }` row for
// each panel, strings in double quotes) and answers nil for anything else, so a
// file it can't read is never half shown and is never touched. What follows the
// front matter is Capsid's own summary for a person to read; it is written from
// the front matter every time and is not read back, so whatever a person or an
// editor does to it can't hide the paper. A byte order mark and Windows line
// ends are read, as in the README. `render` then `parse` then `render` gives the
// same bytes, which `PaperFileTests` checks with names in every script.
//
// `PaperRules` is the pure part: the order panels are shown in, where a figure
// has a gap, what the next label is, the changes the Shelf window offers (assign,
// remove, empty, relabel, swap), and the words it says. It sits here, away from
// any view, so each rule can be tested on made-up panels.
//
// Nothing here touches the disk.
import Foundation

// MARK: Labels

/// One figure of a paper: "Figure 1", or "Supplementary Figure S1". Main
/// figures come before supplementary ones, and each kind in number order, so
/// figure 10 follows figure 2 as a person counts and not as text sorts.
struct PaperFigure: Hashable, Comparable, Sendable {
    var supplementary: Bool
    var number: Int

    /// "Figure 1" or "Supplementary Figure S1": the heading of its group.
    var title: String {
        supplementary ? "Supplementary Figure S\(number)" : "Figure \(number)"
    }

    static func < (a: PaperFigure, b: PaperFigure) -> Bool {
        if a.supplementary != b.supplementary { return !a.supplementary }
        return a.number < b.number
    }
}

/// A panel's label as a manuscript writes it: "1A", "S1A", or "3" for a figure
/// that is one image with no panels. There is one canonical spelling (`text`),
/// and `init?(_:)` accepts the other ways a person types it ("fig. 1a",
/// "Figure S2b") so that what they type is never refused for its case or its
/// prefix, but "1 A", "01A" and "1AB" are, since they could mean something else.
struct PaperLabel: Hashable, Comparable, Sendable {
    var supplementary: Bool
    /// 1 to 99.
    var figure: Int
    /// "" for a whole figure, otherwise one capital letter from A to Z.
    var panel: String

    /// The caller gives a figure of 1 to 99 and a panel that is empty or one
    /// letter; the panel is made a capital so that two spellings are never two
    /// labels.
    init(supplementary: Bool, figure: Int, panel: String) {
        self.supplementary = supplementary
        self.figure = figure
        self.panel = panel.uppercased()
    }

    /// Reads "1A", "1a", "Fig 1A", "Fig. 3", "Figure S2b", "S1". Nil for
    /// anything else: no spaces inside, no leading zero, at most two digits and
    /// one letter. (By scalars, so a letter from another script is never taken
    /// for one of ours.)
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = Array(trimmed.unicodeScalars)
        // Lower-cased ASCII only, for the comparisons; the letters are read from `scalars`.
        let lower = scalars.map { ("A"..."Z").contains($0) ? Unicode.Scalar($0.value + 32)! : $0 }

        var i = 0
        for prefix in ["figure ", "fig. ", "fig "] {
            let wanted = Array(prefix.unicodeScalars)
            if lower.count >= wanted.count, Array(lower[0..<wanted.count]) == wanted {
                i = wanted.count
                break
            }
        }

        var supplementary = false
        if i < lower.count, lower[i] == "s" {
            supplementary = true
            i += 1
        }

        var digits = ""
        while i < scalars.count, digits.count < 2, ("0"..."9").contains(scalars[i]) {
            digits.unicodeScalars.append(scalars[i])
            i += 1
        }
        guard let figure = Int(digits), digits.first != "0" else { return nil }

        var panel = ""
        if i < lower.count, ("a"..."z").contains(lower[i]) {
            panel = String(Character(Unicode.Scalar(lower[i].value - 32)!))
            i += 1
        }
        guard i == scalars.count else { return nil }
        self.init(supplementary: supplementary, figure: figure, panel: panel)
    }

    /// "1A", "S1A", "3": what the file stores.
    var text: String { (supplementary ? "S" : "") + String(figure) + panel }

    /// "Fig 1A", "Fig S1A", "Fig 3": what a person is shown.
    var title: String { "Fig " + text }

    /// The figure this panel belongs to.
    var figureKey: PaperFigure { PaperFigure(supplementary: supplementary, number: figure) }

    /// Main figures before supplementary ones, then by figure number, then the
    /// whole figure ("") before panel A before panel B.
    static func < (a: PaperLabel, b: PaperLabel) -> Bool {
        if a.figureKey != b.figureKey { return a.figureKey < b.figureKey }
        return a.panel < b.panel
    }
}

// MARK: The paper

/// One slot of a paper: a label and, when it is filled, the kept folder that fills it.
struct PaperPanel: Equatable, Sendable {
    var label: PaperLabel
    /// The kept folder relative to the Kept root, "Assay development/z_prime_by_plate"; nil is an empty slot, kept
    /// so that a paper can plan a figure before it has the panel.
    var folder: String?
    /// Which artifact and version of it the folder held when it was put in the paper: what lets the Shelf say a panel
    /// is out of date once the folder has a newer version of the figure.
    var artifact: String?
    var version: String?
    /// The figure's file name in the folder, "z_prime_by_plate.png".
    var file: String?

    var isEmpty: Bool { folder == nil }
}

/// A paper: a name, when it was made, its panels, and the Capsid that wrote the file.
struct Paper: Equatable, Sendable {
    var name: String
    var createdAt: Date
    var panels: [PaperPanel]
    var capsid: String
}

// MARK: Rendering and parsing

enum PaperFile {
    /// The file in the paper's folder.
    static let fileName = "PAPER.md"
    /// The folder the papers live in, beside the Kept root's collections.
    static let folderName = "Papers"

    /// The last line of every PAPER.md. It says who writes the file and, since a person may be nervous of taking a
    /// panel out, that this never reaches the figures.
    static let finePrint = "Capsid writes this file when you change the paper in the Shelf window. "
        + "The figures stay in their own kept folders; removing one from the paper never touches its folder."

    // MARK: Rendering

    /// The file, in full. `timeZone` is the zone `created_at` is written in (the Mac's, unless a test pins one).
    /// Panels are written in label order whatever order they come in.
    static func render(_ paper: Paper, timeZone: TimeZone = .current) -> String {
        let panels = paper.panels.sorted { $0.label < $1.label }

        var front = ["---", "capsid_paper: 1"]
        front.append("name: \(KeptReadme.quoted(paper.name))")
        front.append("created_at: \(KeptReadme.rfc3339(paper.createdAt, timeZone: timeZone))")
        if panels.isEmpty {
            front.append("panels: []")
        } else {
            front.append("panels:")
            front += panels.map { "  - \(row($0))" }
        }
        front.append("capsid: \(KeptReadme.quoted(paper.capsid))")
        front.append("---")

        var out = front.joined(separator: "\n") + "\n\n"
        out += "# \(oneLine(paper.name))\n\n"
        out += panels.isEmpty ? "No panels yet." : panels.map { "- \(summary($0))" }.joined(separator: "\n")
        out += "\n\n---\n\n\(finePrint)\n"
        return out
    }

    /// `{ label: "1A", folder: …, artifact: …, version: …, file: … }`. An empty slot is only its label: an artifact
    /// with no folder to belong to is never written.
    private static func row(_ panel: PaperPanel) -> String {
        var fields = ["label: \(KeptReadme.quoted(panel.label.text))"]
        if let folder = panel.folder {
            fields.append("folder: \(KeptReadme.quoted(folder))")
            if let artifact = panel.artifact { fields.append("artifact: \(KeptReadme.quoted(artifact))") }
            if let version = panel.version { fields.append("version: \(KeptReadme.quoted(version))") }
            if let file = panel.file { fields.append("file: \(KeptReadme.quoted(file))") }
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    /// "Fig 1A · z_prime_by_plate.png, from Assay development/z_prime_by_plate", or "Fig 2C · empty".
    private static func summary(_ panel: PaperPanel) -> String {
        guard let folder = panel.folder else { return "\(panel.label.title) · empty" }
        let what = panel.file ?? PaperRules.lastComponent(of: folder)
        return "\(panel.label.title) · \(oneLine(what)), from \(oneLine(folder))"
    }

    /// Line breaks become blanks: for the places a single line is needed.
    private static func oneLine(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0 == "\n" || $0 == "\r" ? " " : $0 }))
    }

    // MARK: Parsing

    private static let panelFields = [
        KeptReadme.Field("label", .string), KeptReadme.Field("folder", .string, optional: true),
        KeptReadme.Field("artifact", .string, optional: true), KeptReadme.Field("version", .string, optional: true),
        KeptReadme.Field("file", .string, optional: true),
    ]

    /// The paper, or nil when the file is not one this renderer made (no `capsid_paper: 1`, front matter out of order
    /// or with a key it doesn't know, a label that isn't written the way Capsid writes it or is there twice, a
    /// folder that isn't "Collection/Name" inside the Kept root, a bad date, no closing `---`). Only the front matter
    /// is read; whatever follows it is Capsid's summary and a person's notes, and is not looked at. A byte order mark
    /// and Windows line ends are ignored. Panels come back in label order.
    static func parse(_ markdown: String) -> Paper? {
        var all = KeptReadme.lines(plainLineEnds(markdown))
        if all.first?.unicodeScalars.first == "\u{FEFF}" {
            all[0] = String(all[0].unicodeScalars.dropFirst())
        }

        var i = 0
        func next() -> String? {
            defer { i += 1 }
            return i < all.count ? all[i] : nil
        }
        func string(_ key: String) -> String? {
            guard let line = next(), line.hasPrefix("\(key): ") else { return nil }
            let raw = String(line.dropFirst(key.count + 2))
            guard let (text, end) = KeptReadme.readQuoted(raw, from: raw.unicodeScalars.startIndex),
                  end == raw.unicodeScalars.endIndex else { return nil }
            return text
        }

        guard next() == "---", next() == "capsid_paper: 1",
              let name = string("name"),
              let createdLine = next(), createdLine.hasPrefix("created_at: "),
              let createdAt = KeptReadme.date(rfc3339: String(createdLine.dropFirst("created_at: ".count))),
              let head = next() else { return nil }

        var rows: [[String: KeptReadme.Value]] = []
        if head != "panels: []" {
            guard head == "panels:" else { return nil }
            while i < all.count, all[i].hasPrefix("  - ") {
                guard let row = KeptReadme.readMap(String(all[i].dropFirst(4)), panelFields) else { return nil }
                rows.append(row)
                i += 1
            }
            guard !rows.isEmpty else { return nil }
        }

        guard let capsid = string("capsid"), next() == "---" else { return nil }

        var panels: [PaperPanel] = []
        var seen = Set<PaperLabel>()
        for row in rows {
            func text(_ key: String) -> String? {
                if case .string(let value)? = row[key] { return value }
                return nil
            }
            guard let labelText = text("label"), let label = PaperLabel(labelText), label.text == labelText,
                  seen.insert(label).inserted else { return nil }
            let folder = text("folder")
            if let folder {
                guard isKeptFolder(folder) else { return nil }
            } else if text("artifact") != nil || text("version") != nil || text("file") != nil {
                return nil
            }
            panels.append(PaperPanel(label: label, folder: folder, artifact: text("artifact"),
                                     version: text("version"), file: text("file")))
        }
        return Paper(name: name, createdAt: createdAt, panels: panels.sorted { $0.label < $1.label }, capsid: capsid)
    }

    /// Whether a folder the file names is exactly "Collection/Name" and stays in the Kept root. The two parts are
    /// real names: not empty, not hidden (a name that starts with "." is not one Keep makes), and never "..".
    private static func isKeptFolder(_ folder: String) -> Bool {
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") }
            && KeptReadme.staysInFolder(folder)
    }

    /// Every "\r\n" as "\n". (By scalars: Swift counts "\r\n" as one character.)
    private static func plainLineEnds(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n", out.last == "\r" { out.removeLast() }
            out.append(scalar)
        }
        return String(out)
    }
}

// MARK: Rules

enum PaperRules {
    /// What the Shelf window shows in a figure's row: a panel, or the place of one that is not there yet.
    enum Slot: Equatable, Sendable {
        case panel(PaperPanel)
        /// A letter below the highest in use that has no panel: shown as a gap, so the figure doesn't look
        /// complete when 1B is missing between 1A and 1C.
        case gap(PaperLabel)
    }

    /// One figure and what is in it, in order.
    struct FigureGroup: Equatable, Sendable, Identifiable {
        let figure: PaperFigure
        let slots: [Slot]
        var id: PaperFigure { figure }
    }

    private static let letters = (0..<26).map { String(Character(Unicode.Scalar(UInt8(65 + $0)))) }

    // MARK: Layout

    /// The panels grouped by figure, in figure order. Within a figure a whole-figure panel comes first, then every
    /// letter from A to the highest present, a `.gap` where no panel has it. A gap is only ever below the highest
    /// panel: what is past it is the next label (`nextLabel`), not a hole.
    static func figures(_ panels: [PaperPanel]) -> [FigureGroup] {
        var byFigure: [PaperFigure: [String: PaperPanel]] = [:]
        for panel in panels.sorted(by: { $0.label < $1.label }) {
            // The first of two panels with one label wins; a paper read from a file never has two.
            if byFigure[panel.label.figureKey, default: [:]][panel.label.panel] == nil {
                byFigure[panel.label.figureKey, default: [:]][panel.label.panel] = panel
            }
        }
        return byFigure.keys.sorted().map { figure in
            let found = byFigure[figure] ?? [:]
            var slots: [Slot] = []
            if let whole = found[""] { slots.append(.panel(whole)) }
            if let highest = found.keys.filter({ !$0.isEmpty }).max(), let top = letters.firstIndex(of: highest) {
                for letter in letters[0...top] {
                    if let panel = found[letter] {
                        slots.append(.panel(panel))
                    } else {
                        slots.append(.gap(PaperLabel(supplementary: figure.supplementary, figure: figure.number, panel: letter)))
                    }
                }
            }
            return FigureGroup(figure: figure, slots: slots)
        }
    }

    /// The label a new panel in `figure` gets: the first letter after the highest in use, so a gap left on purpose
    /// stays a gap. Nil when the figure already reaches Z. A figure with no lettered panel starts at A.
    static func nextLabel(in figure: PaperFigure, after panels: [PaperPanel]) -> PaperLabel? {
        let used = panels.filter { $0.label.figureKey == figure && !$0.label.panel.isEmpty }
            .compactMap { letters.firstIndex(of: $0.label.panel) }
        let index = (used.max() ?? -1) + 1
        guard index < letters.count else { return nil }
        return PaperLabel(supplementary: figure.supplementary, figure: figure.number, panel: letters[index])
    }

    /// The figure after the highest of its kind, or the first when there is none. A paper has at most 99 of each
    /// kind (the label has two digits), so past that it answers the last rather than a figure no label can name.
    static func nextFigure(supplementary: Bool, after panels: [PaperPanel]) -> PaperFigure {
        let highest = panels.filter { $0.label.supplementary == supplementary }.map(\.label.figure).max() ?? 0
        return PaperFigure(supplementary: supplementary, number: min(highest + 1, 99))
    }

    // MARK: Changes

    /// The panels with `panel` in its label's place: replacing what was there, or added. In label order.
    static func assigning(_ panel: PaperPanel, in panels: [PaperPanel]) -> [PaperPanel] {
        (panels.filter { $0.label != panel.label } + [panel]).sorted { $0.label < $1.label }
    }

    /// The panels without that label at all: for taking a slot out of the paper, not only the figure from the slot.
    static func removing(_ label: PaperLabel, from panels: [PaperPanel]) -> [PaperPanel] {
        panels.filter { $0.label != label }.sorted { $0.label < $1.label }
    }

    /// The panel kept as an empty slot: its label stays and the folder, artifact, version and file go. The kept
    /// folder itself is not touched, and a label that isn't there is not made.
    static func emptying(_ label: PaperLabel, in panels: [PaperPanel]) -> [PaperPanel] {
        panels.map { $0.label == label ? PaperPanel(label: label) : $0 }.sorted { $0.label < $1.label }
    }

    /// The panel at `from` moved to `to`. Nil when `to` already holds a figure (nothing is overwritten without a
    /// person choosing a swap) or when there is no panel at `from`; an empty slot at `to` is replaced.
    static func relabelling(_ from: PaperLabel, to: PaperLabel, in panels: [PaperPanel]) -> [PaperPanel]? {
        guard let moving = panels.first(where: { $0.label == from }) else { return nil }
        if from == to { return panels.sorted { $0.label < $1.label } }
        if let taken = panels.first(where: { $0.label == to }), !taken.isEmpty { return nil }
        var moved = moving
        moved.label = to
        return assigning(moved, in: removing(from, from: panels))
    }

    /// The two labels exchange what they hold. When `b` isn't in the paper, `a`'s content moves to it and `a` goes
    /// (and the same the other way round, when `a` isn't there); when neither is, nothing changes.
    static func swapping(_ a: PaperLabel, _ b: PaperLabel, in panels: [PaperPanel]) -> [PaperPanel] {
        let first = panels.first { $0.label == a }
        let second = panels.first { $0.label == b }
        func moved(_ panel: PaperPanel, to label: PaperLabel) -> PaperPanel {
            var copy = panel
            copy.label = label
            return copy
        }
        switch (first, second) {
        case (nil, nil):
            return panels.sorted { $0.label < $1.label }
        case (let first?, nil):
            return assigning(moved(first, to: b), in: removing(a, from: panels))
        case (nil, let second?):
            return assigning(moved(second, to: a), in: removing(b, from: panels))
        case (let first?, let second?):
            return assigning(moved(first, to: b), in: assigning(moved(second, to: a), in: panels))
        }
    }

    // MARK: Words and names

    /// The name a figure is saved under when it is exported with its paper label: "Fig 2B · z_prime_by_plate.png".
    /// The kept name may already end in the file's extension (it often is the file name), and it is not written
    /// twice; the extension is the file's, exactly as it is. The middle dot and the spaces around it are what
    /// the Shelf's names use already. The whole is made safe to write (`ShelfFileName.sanitized`).
    static func exportName(label: PaperLabel, name: String, fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        var stem = name
        if !ext.isEmpty, stem.hasSuffix("." + ext) { stem = String(stem.dropLast(ext.count + 1)) }
        return ShelfFileName.sanitized("\(label.title) \u{00B7} \(stem)" + (ext.isEmpty ? "" : "." + ext))
    }

    /// One panel as the legends file needs it: what the person wrote, what Claude said, and whether Claude's words
    /// are only the last answer of its session (kept for the record, not a legend for the figure).
    struct LegendEntry: Equatable, Sendable {
        let label: PaperLabel
        let title: String
        let legend: String
        let claudeSaid: String
        let claudeIsLastAnswer: Bool
    }

    /// All the legends of a paper in one Markdown file, for pasting into a manuscript: a heading for each figure and,
    /// under it, each panel's label and title with its legend. The person's own words come first; Claude's are used
    /// only when the person wrote none, are marked as Claude's, and are left out when they are merely the last
    /// answer of a session rather than a description of the figure. A panel with neither says so, so a gap is seen
    /// rather than skipped. One newline ends the file.
    static func legends(paper name: String, _ entries: [LegendEntry]) -> String {
        let heading = String(String.UnicodeScalarView(name.unicodeScalars.map { $0 == "\n" || $0 == "\r" ? " " : $0 }))
        var out = "# \(heading)\n\n"
        let sorted = entries.sorted { $0.label < $1.label }
        var current: PaperFigure?
        for entry in sorted {
            if entry.label.figureKey != current {
                current = entry.label.figureKey
                out += "## \(entry.label.figureKey.title)\n\n"
            }
            out += "**\(entry.label.title)** \u{00B7} \(entry.title)\n\n\(words(for: entry))\n\n"
        }
        while out.hasSuffix("\n") { out.removeLast() }
        return out + "\n"
    }

    private static func words(for entry: LegendEntry) -> String {
        let legend = entry.legend.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legend.isEmpty { return legend }
        let claude = entry.claudeSaid.trimmingCharacters(in: .whitespacesAndNewlines)
        if !claude.isEmpty, !entry.claudeIsLastAnswer { return "Claude: " + claude }
        return "_No legend yet._"
    }

    /// "1 panel out of date", "2 panels out of date"; nil when there is nothing to say.
    static func outOfDateSummary(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 panel out of date" : "\(count) panels out of date"
    }

    /// "3 of 5 panels filled": how far the paper is from its planned slots.
    static func missingSummary(filled: Int, slots: Int) -> String {
        "\(filled) of \(slots) panels filled"
    }

    /// What a slot says when its folder isn't in the Shelf any more. It names the figure as the person knows it (the
    /// folder's own name) and the usual reasons, since Capsid can't tell which it was.
    static func brokenSlot(folder: String) -> String {
        "\u{201C}\(lastComponent(of: folder))\u{201D} isn\u{2019}t in the Shelf folder any more. "
            + "It may have been moved, renamed or put in the Trash."
    }

    /// "Assay development/z_prime_by_plate" for the collection and the folder's name.
    static func folderPath(collection: String, name: String) -> String {
        "\(collection)/\(name)"
    }

    /// The last part of a folder path: the folder's own name.
    static func lastComponent(of folder: String) -> String {
        folder.split(separator: "/").last.map(String.init) ?? folder
    }
}
