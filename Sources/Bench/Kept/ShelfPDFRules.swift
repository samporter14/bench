// ShelfPDFRules.swift — the decisions behind Export Figure as PDF… (DESIGN.md, Shelf →
// Lab-meeting PDF), pure: which words go on a figure's page (its title, its
// legend, the line that says where it came from), which picture stands for a
// file that isn't a picture, what the PDF is called, and the page's
// geometry: a 16:9 sheet, margins, and the biggest a figure can be drawn in
// the space the words leave without being stretched. Nothing here touches the
// disk, the page or a window, so the tests run it on made-up items; the
// drawing is ShelfPDF.swift's, the panel and the reveal ShelfPDFCommand.swift's.
import CoreGraphics
import Foundation

/// One page of the PDF, decided before anything is drawn: the words, and what
/// stands for the file. A page never holds more than one file.
struct ShelfPDFPage: Equatable, Sendable {
    /// What the page shows of the file.
    enum Picture: Equatable, Sendable {
        /// A picture file: the PDF takes its pixels as they are.
        case image(URL)
        /// A PDF: its first page, drawn as the vector it is.
        case pdf(URL)
        /// A Markdown or text file's first lines, as plain text.
        case text([ShelfPDFBlock])
        /// A tile with the file's kind and size, for everything else (and for a
        /// picture that can't be drawn).
        case tile
    }

    /// The big letters and the line under them on a tile.
    struct Tile: Equatable, Sendable {
        let label: String
        let detail: String
    }

    let title: String
    /// What the figure shows, in a sentence or two; empty when there is nothing honest to say.
    let legend: String
    /// "Plate reader QC · Assay development · 22 Oct 2026".
    let source: String
    let picture: Picture
    let tile: Tile
    /// The file's name, for the sentence that says it couldn't be read.
    let fileName: String
}

/// A block of a text file, with its Markdown marks taken off.
enum ShelfPDFBlock: Equatable, Sendable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
}

enum ShelfPDFRules {
    // MARK: The pages

    /// The pages for items, in the order given. `text` is each item's first
    /// words when it is a text file the caller has read (`KeptDisk.peek`), by
    /// the item's id; an item with none is drawn as a tile.
    static func pages(for items: [ShelfItem], text: [String: String] = [:], locale: Locale = .current,
                      calendar: Calendar = .current) -> [ShelfPDFPage] {
        items.map { page(for: $0, text: text[$0.id], locale: locale, calendar: calendar) }
    }

    static func page(for item: ShelfItem, text: String? = nil, locale: Locale = .current, calendar: Calendar = .current) -> ShelfPDFPage {
        let said = words(for: item)
        return ShelfPDFPage(title: said.title, legend: said.legend, source: sourceLine(for: item, locale: locale, calendar: calendar),
                            picture: picture(for: item, text: text), tile: tile(for: item), fileName: item.fileName)
    }

    /// What stands for the file on its page.
    static func picture(for item: ShelfItem, text: String?) -> ShelfPDFPage.Picture {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        if item.kind == .figure { return .image(item.fileURL) }
        if ext == "pdf" { return .pdf(item.fileURL) }
        if ShelfPeek.proseExtensions.contains(ext), let text {
            let blocks = blocks(fromText: text)
            if !blocks.isEmpty { return .text(blocks) }
        }
        return .tile
    }

    /// "CSV" over "Table · 4 KB": the file's extension, then its kind and size.
    static func tile(for item: ShelfItem) -> ShelfPDFPage.Tile {
        tile(fileName: item.fileName, kind: item.kind, bytes: item.record.figure.bytes)
    }

    static func tile(fileName: String, kind: ShelfKind, bytes: Int) -> ShelfPDFPage.Tile {
        let ext = (fileName as NSString).pathExtension.uppercased()
        let word: String
        switch kind {
        case .figure: word = "Figure"
        case .document: word = "Document"
        case .table: word = "Table"
        }
        let label = ext.isEmpty || ext.count > 5 ? "FILE" : ext
        return .init(label: label, detail: "\(word) \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
    }

    // MARK: The words

    /// How much of a legend a page takes: the person's own, and Claude's when
    /// there is no legend (a page can't hold a paper's legend; "kept short").
    static let legendLimit = 600
    static let claudeLimit = 220

    struct Words: Equatable, Sendable {
        let title: String
        let legend: String
    }

    /// The title and the legend of an item's page.
    ///
    /// The title is the name the person gave the keep, else the heading line
    /// that opens their legend, else the file's name. The legend is the
    /// person's own, from Kept writing, else the first lines of what Claude
    /// said, kept short, unless the words kept with the item are Claude's last
    /// in the session because the one that showed it wasn't found (then they
    /// say nothing about this figure, and the page has no legend).
    static func words(for item: ShelfItem) -> Words {
        let mine = item.text.legend.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = item.title
        var legend = ""
        if !mine.isEmpty {
            let split = splitLegendTitle(mine)
            let named = item.title != item.fileName
            if let heading = split.title, !named {
                title = heading
                legend = cut(flatten(split.body), to: legendLimit)
            } else {
                legend = cut(flatten(mine), to: legendLimit)
            }
        }
        if legend.isEmpty, !ShelfRules.isLastAnswer(item.text) {
            legend = shortWords(item.text.claudeSaid)
        }
        return Words(title: title, legend: legend)
    }

    /// A legend that opens with a title: a Markdown heading, or a short line
    /// of its own (no more than 80 characters, not a sentence) followed by
    /// more. The rest is the legend.
    static func splitLegendTitle(_ legend: String) -> (title: String?, body: String) {
        let normal = legend.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = normal.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = paragraphs.first else { return (nil, "") }
        let rest = paragraphs.dropFirst().joined(separator: "\n\n")
        let lines = first.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if let head = lines.first, head.hasPrefix("#") {
            let title = ShelfPeek.plain(head)
            guard !title.isEmpty else { return (nil, normal) }
            // The heading's own paragraph may go on under it.
            let under = lines.dropFirst().joined(separator: "\n")
            return (title, [under, rest].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        if lines.count == 1, !rest.isEmpty {
            let line = ShelfPeek.plain(first)
            if !line.isEmpty, line.count <= 80, !".:;!?".contains(line.last!) { return (line, rest) }
        }
        return (nil, normal)
    }

    /// Lines joined with a space, their Markdown marks off: a legend is one paragraph on the page.
    static func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { ShelfPeek.plain(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The first sentences of what Claude said, in at most `limit` characters:
    /// code, tables, rules and comments left out, the marks off, cut at a
    /// sentence when it can be and at a word, with an ellipsis, when it can't.
    static func shortWords(_ said: String, limit: Int = claudeLimit) -> String {
        var lines: [String] = []
        var inCode = false
        for raw in said.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inCode.toggle(); continue }
            // Headings, tables, comments and rules are structure, not sentences.
            if inCode || line.isEmpty || line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix("<!--") || isRule(line) { continue }
            let plain = ShelfPeek.plain(line)
            if !plain.isEmpty { lines.append(plain) }
        }
        let text = lines.joined(separator: " ")
        guard !text.isEmpty else { return "" }
        guard text.count > limit else { return text }
        var kept = ""
        for sentence in sentences(of: text) {
            let next = kept.isEmpty ? sentence : kept + " " + sentence
            if next.count > limit { break }
            kept = next
        }
        return kept.isEmpty ? cut(text, to: limit) : kept
    }

    private static func isRule(_ line: String) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        return marks.count >= 3 && Set(marks).count == 1 && "-*_=".contains(marks.first!)
    }

    /// Sentences: after a full stop, question mark or exclamation mark and a
    /// space, when a capital letter, a quote or a bracket follows.
    static func sentences(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard ".?!".contains(character), index + 2 < characters.count, characters[index + 1] == " " else { continue }
            let next = characters[index + 2]
            if next.isUppercase || "\u{201C}\"(\u{2018}".contains(next) {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// `text` in at most `limit` characters: cut at the last sentence end past
    /// the half, else at the last word, with an ellipsis.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let head = String(text.prefix(limit - 1))
        if let end = head.lastIndex(where: { ".?!".contains($0) }), head.distance(from: head.startIndex, to: end) >= limit / 2 {
            return String(head[...end])
        }
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) >= limit / 2 {
            return head[..<space].trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return head.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// "Plate reader QC · Assay development · 22 Oct 2026": the session, the
    /// project and the day the answer was given (the day it went on the shelf
    /// when that isn't known); what is empty is left out.
    static func sourceLine(for item: ShelfItem, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let record = item.record
        let when = record.answerAt ?? record.keptAt
        let parts = [record.sessionTitle, record.projectName].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } + [day(when, locale: locale, calendar: calendar)]
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "22 Oct 2026", in the order the PDF uses whatever the Mac's region.
    static func day(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: A text file

    /// A Markdown or text file's first lines as blocks: headings, paragraphs
    /// (the lines up to a blank one, joined) and bullets, with the marks off;
    /// front matter, code, tables, comments and rules left out. At most `limit` blocks.
    static func blocks(fromText text: String, limit: Int = 40) -> [ShelfPDFBlock] {
        var blocks: [ShelfPDFBlock] = []
        var paragraph: [String] = []
        func flush() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var inCode = false
        var start = 0
        // Front matter: a first line of dashes, to the next.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        for line in lines.dropFirst(start) {
            if line.hasPrefix("```") || line.hasPrefix("~~~") { flush(); inCode.toggle(); continue }
            if inCode { continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("|") || line.hasPrefix("<!--") || isRule(line) { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let heading = ShelfPeek.plain(line)
                if !heading.isEmpty { blocks.append(.heading(heading)) }
                continue
            }
            if line.range(of: "^([-*+]|\\d+[.)])\\s+", options: .regularExpression) != nil {
                flush()
                let item = ShelfPeek.plain(line)
                if !item.isEmpty { blocks.append(.bullet(item)) }
                continue
            }
            paragraph.append(ShelfPeek.plain(line))
        }
        flush()
        return Array(blocks.prefix(limit))
    }

    // MARK: The file

    /// "Lab meeting 2026-10-23.pdf", with the day's date.
    static func fileName(on date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "Lab meeting %04d-%02d-%02d.pdf", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: The command's name

    /// What the command is called where there is room for the count: "Export Figure as PDF…" for one,
    /// "Export 3 Figures as PDF…" for several. The save panel opens on it and the file is "Lab meeting <date>.pdf".
    /// What isn't all figures (a note, a document, a table among them) says what it is (since 1.0.6): "Export as
    /// PDF…" for one, "Export 3 Items as PDF…" for several.
    static func exportName(count: Int, allFigures: Bool = true) -> String {
        guard allFigures else { return count > 1 ? "Export \(count) Items as PDF\u{2026}" : exportPillName }
        return count > 1 ? "Export \(count) Figures as PDF\u{2026}" : "Export Figure as PDF\u{2026}"
    }

    /// The same, as VoiceOver says it: no ellipsis.
    static func exportSpoken(count: Int, allFigures: Bool = true) -> String {
        guard allFigures else { return count > 1 ? "Export \(count) Items as PDF" : "Export as PDF" }
        return count > 1 ? "Export \(count) Figures as PDF" : "Export Figure as PDF"
    }

    /// The title bar's pill. Short, because at the window's narrowest the bar also holds "Shelf", the project pill and
    /// the search, and "Export 12 Figures as PDF…" would push the search off it; the count is on the card under the
    /// grid, on the cards' page numbers and in what VoiceOver says, so the pill can leave it out.
    static let exportPillName = "Export as PDF\u{2026}"

    /// The pill and the card's button while the PDF is made: "Exporting…", then "Exporting… 2/3" for several pages.
    static func exporting(done: Int, total: Int) -> String {
        total > 1 ? "Exporting\u{2026} \(done)/\(total)" : "Exporting\u{2026}"
    }

    /// The save panel's button; its message says what the file is.
    static let savePanelPrompt = "Export"

    // MARK: The sentences

    /// A file that couldn't be read; no PDF is made, so a page is never quietly missing.
    static func couldntRead(_ name: String) -> String {
        "Couldn\u{2019}t read \(name), which may have been moved out of the Shelf folder."
    }

    static func couldntSave(in folder: String) -> String {
        "Couldn\u{2019}t save the PDF to \(folder), which may be read-only or full."
    }

    static let nothingChosen = "Choose a figure on the shelf first."
}

// MARK: - The page's geometry

/// The sheet and where things go on it, in points with the origin at the top
/// left (the renderer turns it over for PDF).
enum ShelfPDFLayout {
    /// 16:9, the shape of a projector: the size PowerPoint calls widescreen.
    static let page = CGSize(width: 960, height: 540)
    static let marginX: CGFloat = 56
    static let marginTop: CGFloat = 44
    static let marginBottom: CGFloat = 32
    /// Between the words and the figure, and the figure and the line below it.
    static let gapAbove: CGFloat = 20
    static let gapBelow: CGFloat = 16
    /// Title, legend and source: sizes in points.
    static let titleMax: CGFloat = 20
    static let titleMin: CGFloat = 14
    static let legendSize: CGFloat = 14
    static let legendLeading: CGFloat = 21
    static let legendLines = 3
    static let legendWidth: CGFloat = 720
    static let sourceSize: CGFloat = 11
    static let sourceHeight: CGFloat = 14
    /// A picture is never drawn bigger than its own pixels, one point to a pixel.
    static let maxPointsPerPixel: CGFloat = 1

    /// The page's shape.
    static var aspect: CGFloat { page.width / page.height }

    /// The widest the words run.
    static var contentWidth: CGFloat { page.width - 2 * marginX }

    /// The regions of a page, from how tall the title and the legend came out.
    struct Regions: Equatable {
        let title: CGRect
        let legend: CGRect
        let figure: CGRect
        let footer: CGRect
    }

    static func regions(titleHeight: CGFloat, legendHeight: CGFloat) -> Regions {
        let title = CGRect(x: marginX, y: marginTop, width: contentWidth, height: titleHeight)
        let legendTop = title.maxY + (legendHeight > 0 ? 8 : 0)
        let legend = CGRect(x: marginX, y: legendTop, width: min(legendWidth, contentWidth), height: legendHeight)
        let footer = CGRect(x: marginX, y: page.height - marginBottom - sourceHeight, width: contentWidth, height: sourceHeight)
        let top = legend.maxY + gapAbove
        let bottom = footer.minY - gapBelow
        let figure = CGRect(x: marginX, y: top, width: contentWidth, height: max(0, bottom - top))
        return Regions(title: title, legend: legend, figure: figure, footer: footer)
    }

    /// The biggest `size` fits in `box` without changing its shape, centred;
    /// never more than `maxScale` times its own size when that is given.
    static func fit(_ size: CGSize, in box: CGRect, maxScale: CGFloat? = nil) -> CGRect {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else {
            return CGRect(x: box.midX, y: box.midY, width: 0, height: 0)
        }
        var scale = min(box.width / size.width, box.height / size.height)
        if let maxScale { scale = min(scale, maxScale) }
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    /// The title's size: 20 points, or smaller, down to 14, until it fits `width` on one line.
    static func titleSize(for title: String, width: CGFloat, measure: (_ text: String, _ size: CGFloat) -> CGFloat) -> CGFloat {
        var size = titleMax
        while size > titleMin, measure(title, size) > width { size -= 1 }
        return size
    }

    /// A title's line, as tall as its type needs.
    static func titleHeight(for size: CGFloat) -> CGFloat { (size * 13 / 10).rounded(.up) }
}
