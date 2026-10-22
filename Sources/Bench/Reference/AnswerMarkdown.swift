// AnswerMarkdown.swift — one of Claude's answers (Markdown, as a session's
// history holds it) as the text the reference window shows in a read-only,
// selectable text view. Pure: Markdown in, an attributed string out; nothing
// drawn, nothing read from disk, no main actor.
//
// Foundation parses (`AttributedString(markdown:)`, full syntax) and this file
// lays the blocks out: one paragraph per block, "\n" between them, none at the
// end. Headings, paragraphs, lists (a "•" or the item's own number, hanging
// 20 pt a level), code blocks (the code font on a faint ground, the language
// ignored, every line kept), block quotes (indented, secondary), thematic
// breaks (a centred "⸻"), and bold, italic, `code`, strikethrough and
// http, https and mailto links inside them. A link to anything else keeps its
// words and loses the link. A hard line break becomes U+2028, so the lines
// stay one paragraph (and a list item's second line hangs under its text).
//
// What a text view can't show becomes a placeholder paragraph in the
// secondary colour that carries `unsupportedKey` and is listed in
// `AnswerDocument.unsupported` with its range: a table ("Not shown here: a
// table."), an image ("Figure: <file name>", which also carries `imageKey`
// so the window can put a thumbnail there; an image inside a paragraph splits
// it), and a raw HTML block (its source, as written).
//
// What the parser gives on macOS 27 (probed before this was written): a GFM
// table arrives as `.table`, with its header row, rows and cells; a raw HTML
// block arrives as text runs marked `.blockHTML` with no paragraph of their
// own (inside a list item they still carry the item, and two HTML blocks in a
// row come as one run); an image is a run with `imageURL` whose text is the
// alt text (U+FFFC when there is none); a thematic break is already "⸻"; a
// code block is one run ending in "\n". The parser threw on nothing tried; if
// it ever does, the answer is shown as one plain paragraph of its raw text.
import AppKit

/// The fonts and colours an answer is drawn in. `@unchecked Sendable`: it
/// holds immutable AppKit values (NSFont is not Sendable) and is only read.
struct AnswerStyle: @unchecked Sendable {
    var body: NSFont
    var lineSpacing: CGFloat
    /// h1, h2, then h3 and every level below it.
    var headings: [NSFont]
    var code: NSFont
    var secondary: NSColor
    var link: NSColor

    static let standard = AnswerStyle(
        body: .systemFont(ofSize: 13),
        lineSpacing: 3,
        headings: [.systemFont(ofSize: 17, weight: .semibold),
                   .systemFont(ofSize: 15, weight: .semibold),
                   .systemFont(ofSize: 13, weight: .semibold)],
        code: .monospacedSystemFont(ofSize: 12, weight: .regular),
        secondary: .secondaryLabelColor,
        link: .linkColor)

    /// The font for a heading of this level (1 is the largest).
    func heading(level: Int) -> NSFont {
        headings.isEmpty ? body : headings[min(max(level - 1, 0), headings.count - 1)]
    }
}

/// What the text can't show, with where its placeholder paragraph sits.
enum AnswerUnsupported: Hashable, Sendable { case table, image(name: String), html }

/// The value of `AnswerMarkdown.unsupportedKey`: the kind, in an object an
/// attributed string can hold. Boxes of the same kind are equal, so the same
/// answer rendered twice gives equal strings.
final class AnswerUnsupportedBox: NSObject, Sendable {
    let kind: AnswerUnsupported
    init(_ kind: AnswerUnsupported) {
        self.kind = kind
        super.init()
    }
    override func isEqual(_ object: Any?) -> Bool { (object as? AnswerUnsupportedBox)?.kind == kind }
    override var hash: Int { kind.hashValue }
}

/// An answer, rendered. `@unchecked Sendable`: NSAttributedString is not
/// Sendable; it is only used on the main actor.
struct AnswerDocument: @unchecked Sendable {
    let text: NSAttributedString
    let unsupported: [AnswerPlaceholder]
}

struct AnswerPlaceholder: Equatable, Sendable {
    let kind: AnswerUnsupported
    let range: NSRange
}

enum AnswerMarkdown {
    /// The custom attribute on a placeholder paragraph; its value is an `AnswerUnsupportedBox` (an NSObject wrapping the kind).
    static let unsupportedKey = NSAttributedString.Key("local.sam.bench.answer.unsupported")
    /// The custom attribute on a figure's placeholder paragraph: the image's file name as an NSString.
    static let imageKey = NSAttributedString.Key("local.sam.bench.answer.image")

    /// A code block's ground: the quaternary label colour at half its own
    /// alpha, in whichever appearance it is drawn. (On macOS 27
    /// `quaternaryLabelColor.withAlphaComponent(0.5)` is a fixed 50% black:
    /// it sets the alpha rather than halving it, and loses the dark
    /// appearance.) One instance, so two renders are equal.
    static let codeBackground = NSColor(name: nil) { appearance in
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.quaternaryLabelColor.usingColorSpace(.sRGB)
        }
        guard let resolved else { return .quaternaryLabelColor }
        return resolved.withAlphaComponent(resolved.alphaComponent * 0.5)
    }

    static let tableText = "Not shown here: a table."
    static let ruleText = "\u{2E3B}"

    static func render(_ markdown: String, style: AnswerStyle = .standard) -> AnswerDocument {
        render(markdown, style: style) { try AttributedString(markdown: $0, options: .init(interpretedSyntax: .full)) }
    }

    /// `render`, with the parse passed in (the tests make it throw).
    static func render(_ markdown: String, style: AnswerStyle,
                       parser: (String) throws -> AttributedString) -> AnswerDocument {
        if markdown.isEmpty { return AnswerDocument(text: NSAttributedString(), unsupported: []) }
        let parsed: AttributedString
        do { parsed = try parser(markdown) } catch { return rawText(markdown, style: style) }
        var layout = Layout(style: style)
        layout.read(parsed)
        return layout.finish()
    }

    /// What the parser rejected, as one plain paragraph.
    private static func rawText(_ markdown: String, style: AnswerStyle) -> AnswerDocument {
        var raw = markdown
        while raw.last?.isNewline == true { raw.removeLast() }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = 8
        let text = NSAttributedString(string: raw, attributes: [
            .font: style.body, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph.copy(),
        ])
        return AnswerDocument(text: text, unsupported: [])
    }

    /// Links that open: the web and mail. Anything else stays words.
    static func opens(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    /// An image's file name: the last segment of its path, without control
    /// characters or line breaks, at most 255 characters. "" if there is none.
    static func fileName(_ url: URL) -> String {
        let last = url.lastPathComponent.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let kept = last.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }
        let name = String(String.UnicodeScalarView(kept))
        return name == "." || name == ".." ? "" : String(name.prefix(255))
    }

    /// `base` with bold and/or italic added to the traits it has.
    static func font(_ base: NSFont, adding traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        guard !traits.isEmpty else { return base }
        let descriptor = base.fontDescriptor
        return NSFont(descriptor: descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(traits)),
                      size: base.pointSize) ?? base
    }
}

// MARK: Layout

/// One paragraph of the output.
private struct Piece {
    enum Role { case prose, heading, code, html, rule, placeholder }
    var text: NSMutableAttributedString
    var role: Role
    /// The font of the "\n" after it.
    var font: NSFont
    /// Where its text starts, from its quotes and list items.
    var indent: CGFloat
    /// Starts with a list marker that hangs 20 pt left of `indent`.
    var marked = false
    /// The outermost list it sits in.
    var list: Int?
    var unsupported: AnswerUnsupported?
}

/// One block of the parse, as it is read.
private struct Block {
    enum Kind { case paragraph, heading(Int), code, rule, table, html }
    enum Segment { case text(NSMutableAttributedString), image(URL) }
    var kind: Kind
    var indent: CGFloat
    var marker: String?
    var list: Int?
    var font: NSFont
    var colour: NSColor
    var segments: [Segment] = []

    mutating func append(_ text: NSAttributedString) {
        if case .text(let last)? = segments.last {
            last.append(text)
        } else {
            segments.append(.text(NSMutableAttributedString(attributedString: text)))
        }
    }

    /// Everything read, as one string (a code block's or an HTML block's source).
    var source: NSMutableAttributedString {
        let all = NSMutableAttributedString()
        for case .text(let text) in segments { all.append(text) }
        return all
    }
}

private struct Layout {
    let style: AnswerStyle
    var pieces: [Piece] = []
    /// The list items that have had a block already: only the first gets the marker.
    var startedItems: Set<Int> = []

    init(style: AnswerStyle) { self.style = style }

    private enum BlockKey: Equatable { case block(Int), html(Int), loose }

    mutating func read(_ parsed: AttributedString) {
        var key: BlockKey?
        var block: Block?
        var htmlBlocks = 0
        for run in parsed.runs {
            let inline = run.inlinePresentationIntent ?? []
            let components = run.presentationIntent?.components ?? []
            let runKey: BlockKey, kind: Block.Kind, containers: ArraySlice<PresentationIntent.IntentType>
            if inline.contains(.blockHTML) {
                htmlBlocks += 1
                (runKey, kind, containers) = (.html(htmlBlocks), .html, components[...])
            } else if let table = components.firstIndex(where: { if case .table = $0.kind { true } else { false } }) {
                (runKey, kind, containers) = (.block(components[table].identity), .table, components[(table + 1)...])
            } else if let first = components.first {
                (runKey, kind, containers) = (.block(first.identity), Self.kind(first.kind), components.dropFirst())
            } else {
                (runKey, kind, containers) = (.loose, .paragraph, [])
            }
            if runKey != key {
                if let block { flush(block) }
                block = start(kind, in: containers)
                key = runKey
            }
            add(String(parsed[run.range].characters), inline: inline, link: run.link, image: run.imageURL, to: &block!)
        }
        if let block { flush(block) }
    }

    private static func kind(_ kind: PresentationIntent.Kind) -> Block.Kind {
        switch kind {
        case .header(let level): .heading(level)
        case .codeBlock: .code
        case .thematicBreak: .rule
        default: .paragraph
        }
    }

    /// A block's indent, marker, list, font and colour, from what holds it
    /// (innermost first).
    private mutating func start(_ kind: Block.Kind, in containers: ArraySlice<PresentationIntent.IntentType>) -> Block {
        var indent: CGFloat = 0, quoted = false, list: Int?
        for container in containers.reversed() {
            switch container.kind {
            case .blockQuote: indent += 16; quoted = true
            case .listItem: indent += 20
            case .orderedList, .unorderedList: if list == nil { list = container.identity }
            default: break
            }
        }
        var marker: String?
        if let item = containers.first, case .listItem(let ordinal) = item.kind, !startedItems.contains(item.identity) {
            switch kind {
            case .paragraph, .heading:
                let ordered = containers.dropFirst().first.map { if case .orderedList = $0.kind { true } else { false } } ?? false
                marker = ordered ? "\(ordinal).\t" : "•\t"
            default: break
            }
        }
        for container in containers { if case .listItem = container.kind { startedItems.insert(container.identity) } }

        let text: NSColor = quoted ? style.secondary : .labelColor
        let (font, colour): (NSFont, NSColor) = switch kind {
        case .paragraph: (style.body, text)
        case .heading(let level): (style.heading(level: level), text)
        case .code: (style.code, .labelColor)
        case .rule, .table, .html: (style.body, style.secondary)
        }
        return Block(kind: kind, indent: indent, marker: marker, list: list, font: font, colour: colour)
    }

    private func add(_ string: String, inline: InlinePresentationIntent, link: URL?, image: URL?, to block: inout Block) {
        switch block.kind {
        case .table, .rule:
            return  // their words are fixed
        case .code, .html:
            block.append(NSAttributedString(string: string, attributes: [.font: block.font, .foregroundColor: block.colour]))
        case .paragraph, .heading:
            if let image {
                block.segments.append(.image(image))
                return
            }
            var font = block.font
            if inline.contains(.code) {
                font = codeFont(beside: block.font)
            } else {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if inline.contains(.emphasized) { traits.insert(.italic) }
                font = AnswerMarkdown.font(block.font, adding: traits)
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: block.colour]
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link, AnswerMarkdown.opens(link) {
                attributes[.link] = link
                attributes[.foregroundColor] = style.link
            }
            let text = inline.contains(.lineBreak) ? string.replacingOccurrences(of: "\n", with: "\u{2028}") : string
            block.append(NSAttributedString(string: text, attributes: attributes))
        }
    }

    /// The code font, as much smaller than a heading as it is than the body.
    private func codeFont(beside font: NSFont) -> NSFont {
        let size = max(style.code.pointSize, font.pointSize - (style.body.pointSize - style.code.pointSize))
        return size == style.code.pointSize ? style.code : NSFont(descriptor: style.code.fontDescriptor, size: size) ?? style.code
    }

    private mutating func flush(_ block: Block) {
        func piece(_ text: NSMutableAttributedString, _ role: Piece.Role, font: NSFont,
                   unsupported: AnswerUnsupported? = nil) -> Piece {
            Piece(text: text, role: role, font: font, indent: block.indent, list: block.list, unsupported: unsupported)
        }
        switch block.kind {
        case .table:
            pieces.append(placeholder(AnswerMarkdown.tableText, .table, block: block))
        case .rule:
            let text = NSMutableAttributedString(string: AnswerMarkdown.ruleText,
                                                 attributes: [.font: block.font, .foregroundColor: block.colour])
            pieces.append(piece(text, .rule, font: block.font))
        case .code, .html:
            let text = block.source
            if text.string.hasSuffix("\n") { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
            guard text.length > 0 else { return }
            if case .code = block.kind {
                text.addAttribute(.backgroundColor, value: AnswerMarkdown.codeBackground,
                                  range: NSRange(location: 0, length: text.length))
                pieces.append(piece(text, .code, font: block.font))
            } else {
                text.addAttribute(AnswerMarkdown.unsupportedKey, value: AnswerUnsupportedBox(.html),
                                  range: NSRange(location: 0, length: text.length))
                pieces.append(piece(text, .html, font: block.font, unsupported: .html))
            }
        case .paragraph, .heading:
            let role: Piece.Role = if case .heading = block.kind { .heading } else { .prose }
            let split = block.segments.contains { if case .image = $0 { true } else { false } }
            var first = true
            for segment in block.segments {
                switch segment {
                case .text(let text):
                    if split { Self.trim(text) }
                    guard text.length > 0 else { continue }
                    var made = piece(text, role, font: block.font)
                    if first, let marker = block.marker {
                        text.insert(NSAttributedString(string: marker, attributes: [.font: block.font, .foregroundColor: block.colour]), at: 0)
                        made.marked = true
                    }
                    pieces.append(made)
                case .image(let url):
                    let name = AnswerMarkdown.fileName(url)
                    pieces.append(placeholder(name.isEmpty ? "Figure" : "Figure: \(name)", .image(name: name), block: block))
                }
                first = false
            }
        }
    }

    private func placeholder(_ string: String, _ kind: AnswerUnsupported, block: Block) -> Piece {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.body, .foregroundColor: style.secondary, AnswerMarkdown.unsupportedKey: AnswerUnsupportedBox(kind),
        ]
        if case .image(let name) = kind, !name.isEmpty { attributes[AnswerMarkdown.imageKey] = name as NSString }
        return Piece(text: NSMutableAttributedString(string: string, attributes: attributes), role: .placeholder,
                     font: style.body, indent: block.indent, list: block.list, unsupported: kind)
    }

    /// Takes the white space off both ends (the words either side of an image).
    private static func trim(_ text: NSMutableAttributedString) {
        let string = text.string as NSString
        let kept = string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
        guard kept.location != NSNotFound else {
            text.deleteCharacters(in: NSRange(location: 0, length: text.length))
            return
        }
        let last = string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: .backwards)
        let end = last.location + last.length
        text.deleteCharacters(in: NSRange(location: end, length: string.length - end))
        text.deleteCharacters(in: NSRange(location: 0, length: kept.location))
    }

    func finish() -> AnswerDocument {
        let output = NSMutableAttributedString()
        var placeholders: [AnswerPlaceholder] = []
        for (index, piece) in pieces.enumerated() {
            let next = index + 1 < pieces.count ? pieces[index + 1] : nil
            let after: CGFloat = if piece.role == .heading {
                4
            } else if let list = piece.list {
                next?.list == list ? 4 : 8  // 8 after the last block of an outermost list
            } else {
                8
            }
            let paragraph = paragraphStyle(piece, before: piece.role == .heading && index > 0 ? 12 : 0, after: after)
            let text = piece.text
            let whole = NSRange(location: 0, length: text.length)
            text.addAttribute(.paragraphStyle, value: paragraph, range: whole)
            // A code or HTML block keeps its lines as lines: the spacing goes after the last one only.
            if piece.role == .code || piece.role == .html {
                let lastBreak = (text.string as NSString).range(of: "\n", options: .backwards)
                if lastBreak.location != NSNotFound, let inner = paragraph.mutableCopy() as? NSMutableParagraphStyle {
                    inner.paragraphSpacing = 0
                    text.addAttribute(.paragraphStyle, value: inner.copy(),
                                      range: NSRange(location: 0, length: lastBreak.location + 1))
                }
            }
            if let kind = piece.unsupported {
                placeholders.append(AnswerPlaceholder(kind: kind, range: NSRange(location: output.length, length: text.length)))
            }
            output.append(text)
            if next != nil {
                output.append(NSAttributedString(string: "\n", attributes: [.font: piece.font, .paragraphStyle: paragraph]))
            }
        }
        return AnswerDocument(text: output, unsupported: placeholders)
    }

    private func paragraphStyle(_ piece: Piece, before: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = before
        paragraph.paragraphSpacing = after
        switch piece.role {
        case .code:
            paragraph.firstLineHeadIndent = piece.indent + 10
            paragraph.headIndent = piece.indent + 10
            paragraph.tailIndent = -10
        case .rule:
            paragraph.alignment = .center
            paragraph.firstLineHeadIndent = piece.indent
            paragraph.headIndent = piece.indent
        case .prose, .heading, .html, .placeholder:
            paragraph.lineSpacing = style.lineSpacing
            paragraph.headIndent = piece.indent
            paragraph.firstLineHeadIndent = piece.marked ? piece.indent - 20 : piece.indent
            if piece.marked {
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: piece.indent)]
                paragraph.defaultTabInterval = 20
            }
        }
        return paragraph.copy() as! NSParagraphStyle
    }
}
