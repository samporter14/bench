// AnswerMarkdownTests.swift — the reference window's renderer, on made-up
// answers: each block kind's fonts, paragraph styles and colours (walked run by
// run with enumerateAttributes), lists and their nesting, which links stay
// links, the placeholders for what the text can't show and their ranges, and
// the edges (empty, long, the same answer twice, a parse that throws). Nothing
// here draws or opens a window.
import AppKit
import Testing
@testable import Bench

private typealias Attributes = [NSAttributedString.Key: Any]

private extension AnswerDocument {
    var string: String { text.string }
    var whole: NSRange { NSRange(location: 0, length: text.length) }

    /// Where `needle` first appears, in UTF-16 units (an empty range, and an
    /// issue, if it doesn't).
    func range(of needle: String, sourceLocation: SourceLocation = #_sourceLocation) -> NSRange {
        let found = (text.string as NSString).range(of: needle)
        guard found.location != NSNotFound else {
            Issue.record("\(needle.debugDescription) is not in \(text.string.debugDescription)", sourceLocation: sourceLocation)
            return NSRange(location: 0, length: 0)
        }
        return found
    }

    /// Every run of attributes across `range`, but the line breaks between
    /// paragraphs (which carry only the font and the paragraph style).
    func runs(in range: NSRange) -> [Attributes] {
        var all: [Attributes] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, run, _ in
            if string.substring(with: run) != "\n" { all.append(attributes) }
        }
        return all
    }

    func runs(of needle: String, sourceLocation: SourceLocation = #_sourceLocation) -> [Attributes] {
        runs(in: range(of: needle, sourceLocation: sourceLocation))
    }

    /// The attributes at the start of `needle` (none if it isn't there).
    func attributes(at needle: String, sourceLocation: SourceLocation = #_sourceLocation) -> Attributes {
        let found = range(of: needle, sourceLocation: sourceLocation)
        return found.length == 0 ? [:] : text.attributes(at: found.location, effectiveRange: nil)
    }

    func paragraph(at needle: String, sourceLocation: SourceLocation = #_sourceLocation) -> NSParagraphStyle {
        attributes(at: needle, sourceLocation: sourceLocation).paragraph
    }

    /// The ranges that carry `key`, each as long as it runs.
    func ranges(of key: NSAttributedString.Key) -> [NSRange] {
        var found: [NSRange] = []
        text.enumerateAttribute(key, in: whole) { value, range, _ in if value != nil { found.append(range) } }
        return found
    }
}

private extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    // A missing font or paragraph style fails the expectations on it rather than trapping.
    var font: NSFont { self[.font] as? NSFont ?? .systemFont(ofSize: 1) }
    var traits: NSFontDescriptor.SymbolicTraits { font.fontDescriptor.symbolicTraits }
    var colour: NSColor? { self[.foregroundColor] as? NSColor }
    var paragraph: NSParagraphStyle { self[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle() }
}

private func render(_ markdown: String) -> AnswerDocument { AnswerMarkdown.render(markdown) }

private struct ParseFailed: Error {}

@Suite struct AnswerMarkdownTests {
    // MARK: Paragraphs and headings

    @Test func anEmptyAnswerIsAnEmptyString() {
        for markdown in ["", "   \n\n  \n"] {
            let document = render(markdown)
            #expect(document.text.length == 0)
            #expect(document.unsupported.isEmpty)
        }
    }

    @Test func plainTextWithBlankLinesIsOneParagraphEach() {
        let document = render("First paragraph.\n\nSecond one,\nwith a soft break.\n\n\n\nThird.")
        #expect(document.string == "First paragraph.\nSecond one, with a soft break.\nThird.")
        for run in document.runs(in: document.whole) {
            #expect(run.font.pointSize == 13)
            #expect(!run.traits.contains(.bold) && !run.traits.contains(.italic))
            #expect(run.colour == NSColor.labelColor)
            #expect(run.paragraph.lineSpacing == 3)
            #expect(run.paragraph.paragraphSpacing == 8)
            #expect(run.paragraph.paragraphSpacingBefore == 0)
            #expect(run.paragraph.headIndent == 0 && run.paragraph.firstLineHeadIndent == 0)
        }
    }

    @Test func headingsHaveTheirFontsAndSpacing() {
        let document = render("# One\n\nText under it.\n\n## Two\n\n### Three\n\n#### Four")
        #expect(document.string == "One\nText under it.\nTwo\nThree\nFour")
        for (needle, size) in [("One", 17.0), ("Two", 15.0), ("Three", 13.0), ("Four", 13.0)] {
            for run in document.runs(of: needle) {
                #expect(run.font.pointSize == CGFloat(size))
                #expect(run.traits.contains(.bold))  // semibold reads as bold
                #expect(run.colour == NSColor.labelColor)
                #expect(run.paragraph.paragraphSpacing == 4)
            }
        }
        // The first block of the answer has nothing above it.
        #expect(document.paragraph(at: "One").paragraphSpacingBefore == 0)
        #expect(document.paragraph(at: "Two").paragraphSpacingBefore == 12)
        #expect(document.paragraph(at: "Four").paragraphSpacingBefore == 12)
        #expect(document.paragraph(at: "Text under it.").paragraphSpacing == 8)
        #expect(!document.attributes(at: "Text under it.").traits.contains(.bold))
    }

    @Test func aHardLineBreakStaysInsideItsParagraph() {
        let document = render("first line  \nsecond line")
        #expect(document.string == "first line\u{2028}second line")
    }

    @Test func unicodeEmojiAndCJKPassThrough() {
        let document = render("## 見出し 🧪\n\nCafé — naïve 😀👩‍🔬 漢字かな ünïcödé")
        #expect(document.string == "見出し 🧪\nCafé — naïve 😀👩‍🔬 漢字かな ünïcödé")
    }

    // MARK: Inline

    @Test func boldItalicAndBoth() {
        let document = render("Plain **strong** *leaning* ***both*** end")
        #expect(document.string == "Plain strong leaning both end")
        let plain = document.attributes(at: "Plain").traits
        #expect(!plain.contains(.bold) && !plain.contains(.italic))
        let strong = document.attributes(at: "strong").traits
        #expect(strong.contains(.bold) && !strong.contains(.italic))
        let leaning = document.attributes(at: "leaning").traits
        #expect(!leaning.contains(.bold) && leaning.contains(.italic))
        let both = document.attributes(at: "both").traits
        #expect(both.contains(.bold) && both.contains(.italic))
        for run in document.runs(in: document.whole) { #expect(run.font.pointSize == 13) }
    }

    @Test func inlineCodeIsInTheCodeFont() {
        let document = render("Run `make test` now\n\n## Use `git`")
        let code = document.attributes(at: "make test")
        #expect(code.traits.contains(.monoSpace))
        #expect(code.font.pointSize == 12)
        #expect(code.colour == NSColor.labelColor)
        #expect(!document.attributes(at: "Run").traits.contains(.monoSpace))
        // In a heading, the code font is as much smaller than the heading as it is than the body.
        let inHeading = document.attributes(at: "git")
        #expect(inHeading.traits.contains(.monoSpace))
        #expect(inHeading.font.pointSize == 14)
    }

    @Test func strikethroughIsASingleLine() {
        let document = render("~~gone~~ kept")
        #expect(document.attributes(at: "gone")[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(document.attributes(at: "kept")[.strikethroughStyle] == nil)
    }

    @Test func webAndMailLinksStayLinks() {
        let document = render("See [the docs](https://example.com/a?b=1), [plain](http://example.org), "
            + "[write](mailto:someone@example.com) or www.example.net.")
        #expect(document.string == "See the docs, plain, write or www.example.net.")
        let expected = [("the docs", "https://example.com/a?b=1"), ("plain", "http://example.org"),
                        ("write", "mailto:someone@example.com"), ("www.example.net", "http://www.example.net")]
        for (words, url) in expected {
            for run in document.runs(of: words) {
                #expect((run[.link] as? URL)?.absoluteString == url)
                #expect(run.colour == NSColor.linkColor)
            }
        }
        #expect(document.attributes(at: "See")[.link] == nil)
        #expect(document.ranges(of: .link).count == 4)
    }

    @Test func otherSchemesLoseTheLinkButKeepTheWords() {
        let document = render("[run me](javascript:alert(1)) [a file](file:///etc/hosts) [notes](notes.md) "
            + "<javascript:alert(2)> [shout](JAVASCRIPT:void(0))")
        #expect(document.string == "run me a file notes javascript:alert(2) shout")
        #expect(document.ranges(of: .link).isEmpty)
        for run in document.runs(in: document.whole) { #expect(run.colour == NSColor.labelColor) }
    }

    // MARK: Lists

    @Test func aBulletListHangsItsItems() {
        let document = render("- one\n- two\n- three\n\nAfter the list.")
        #expect(document.string == "•\tone\n•\ttwo\n•\tthree\nAfter the list.")
        for (item, spacing) in [("•\tone", 4.0), ("•\ttwo", 4.0), ("•\tthree", 8.0)] {
            for run in document.runs(of: item) {
                #expect(run.font.pointSize == 13)
                #expect(run.colour == NSColor.labelColor)
                #expect(run.paragraph.firstLineHeadIndent == 0)
                #expect(run.paragraph.headIndent == 20)
                #expect(run.paragraph.tabStops.map(\.location) == [20])
                #expect(run.paragraph.paragraphSpacing == CGFloat(spacing))
            }
        }
        let after = document.paragraph(at: "After the list.")
        #expect(after.headIndent == 0 && after.firstLineHeadIndent == 0 && after.paragraphSpacing == 8)
    }

    @Test func anOrderedListKeepsItsNumbers() {
        let document = render("3. three\n4. four\n\nBetween.\n\n1. one\n2. two")
        #expect(document.string == "3.\tthree\n4.\tfour\nBetween.\n1.\tone\n2.\ttwo")
        // Two lists: the last item of each has 8 after it.
        #expect(document.paragraph(at: "3.\tthree").paragraphSpacing == 4)
        #expect(document.paragraph(at: "4.\tfour").paragraphSpacing == 8)
        #expect(document.paragraph(at: "2.\ttwo").paragraphSpacing == 8)
        #expect(document.paragraph(at: "1.\tone").tabStops.map(\.location) == [20])
    }

    @Test func nestedListsIndentTwentyALevel() {
        let document = render("""
            - top
              - middle
                1. deep
                2. deeper
              - middle two
            - top two

            After
            """)
        #expect(document.string == "•\ttop\n•\tmiddle\n1.\tdeep\n2.\tdeeper\n•\tmiddle two\n•\ttop two\nAfter")
        let levels: [(String, CGFloat, CGFloat)] = [
            ("•\ttop\n", 0, 20), ("•\tmiddle\n", 20, 40), ("1.\tdeep", 40, 60), ("2.\tdeeper", 40, 60),
            ("•\tmiddle two", 20, 40), ("•\ttop two", 0, 20),
        ]
        for (item, first, head) in levels {
            for run in document.runs(of: item) {
                #expect(run.paragraph.firstLineHeadIndent == first)
                #expect(run.paragraph.headIndent == head)
                #expect(run.paragraph.tabStops.map(\.location) == [head])
            }
        }
        // 4 between items at every level (the end of a nested list too); 8 after the outermost list.
        for item in ["•\ttop\n", "•\tmiddle\n", "1.\tdeep", "2.\tdeeper", "•\tmiddle two"] {
            #expect(document.paragraph(at: item).paragraphSpacing == 4)
        }
        #expect(document.paragraph(at: "•\ttop two").paragraphSpacing == 8)
        #expect(document.paragraph(at: "After").headIndent == 0)
    }

    @Test func aSecondParagraphInAnItemHangsUnderItsText() {
        let document = render("1. first\n\n   more of the first\n2. second")
        #expect(document.string == "1.\tfirst\nmore of the first\n2.\tsecond")
        let more = document.paragraph(at: "more of the first")
        #expect(more.firstLineHeadIndent == 20 && more.headIndent == 20)
        #expect(more.paragraphSpacing == 4)
        #expect(document.paragraph(at: "2.\tsecond").paragraphSpacing == 8)
    }

    // MARK: Code, quotes, rules

    @Test func aCodeBlockKeepsItsLinesAndDropsTheLanguage() {
        let document = render("Before\n\n```swift\nlet x = 1\n\n  indented\n```\n\nAfter")
        #expect(document.string == "Before\nlet x = 1\n\n  indented\nAfter")
        let code = document.range(of: "let x = 1\n\n  indented")
        for run in document.runs(in: code) {
            #expect(run.traits.contains(.monoSpace))
            #expect(run.font.pointSize == 12)
            #expect(run.colour == NSColor.labelColor)
            #expect((run[.backgroundColor] as? NSColor) == AnswerMarkdown.codeBackground)
            #expect(run.paragraph.firstLineHeadIndent == 10 && run.paragraph.headIndent == 10)
            #expect(run.paragraph.tailIndent == -10)
        }
        // The spacing goes after the block's last line, not between its lines.
        #expect(document.paragraph(at: "let x = 1").paragraphSpacing == 0)
        #expect(document.paragraph(at: "  indented").paragraphSpacing == 8)
        #expect(document.attributes(at: "Before")[.backgroundColor] == nil)
        #expect(document.attributes(at: "After")[.backgroundColor] == nil)
        // The answer ends with its last block, never with a line break.
        #expect(!render("```\ncode\n```").string.hasSuffix("\n"))
        #expect(render("```\ncode\n```").string == "code")
    }

    @MainActor @Test func theCodeGroundIsFaintInBothAppearances() {
        func resolved(in name: NSAppearance.Name) -> NSColor {
            var colour = NSColor.clear
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                colour = AnswerMarkdown.codeBackground.usingColorSpace(.sRGB)!
            }
            return colour
        }
        let light = resolved(in: .aqua), dark = resolved(in: .darkAqua)
        #expect(light.redComponent < 0.1 && light.alphaComponent > 0 && light.alphaComponent < 0.1)
        #expect(dark.redComponent > 0.9 && dark.alphaComponent > 0 && dark.alphaComponent < 0.1)
    }

    @Test func aBlockQuoteIsIndentedAndSecondary() {
        let document = render("> quoted *words*\n>\n> second paragraph\n\nOutside")
        #expect(document.string == "quoted words\nsecond paragraph\nOutside")
        for run in document.runs(of: "quoted words\nsecond paragraph") {
            #expect(run.font.pointSize == 13)
            #expect(run.colour == NSColor.secondaryLabelColor)
            #expect(run.paragraph.firstLineHeadIndent == 16 && run.paragraph.headIndent == 16)
        }
        #expect(document.attributes(at: "words").traits.contains(.italic))
        #expect(document.attributes(at: "Outside").colour == NSColor.labelColor)
        #expect(document.paragraph(at: "Outside").headIndent == 0)
    }

    @Test func aThematicBreakIsACentredDash() {
        let document = render("above\n\n---\n\nbelow")
        #expect(document.string == "above\n\u{2E3B}\nbelow")
        let rule = document.attributes(at: "\u{2E3B}")
        #expect(rule.paragraph.alignment == .center)
        #expect(rule.colour == NSColor.secondaryLabelColor)
        #expect(document.unsupported.isEmpty)
    }

    // MARK: Placeholders

    @Test func aTableIsOnePlaceholder() {
        let document = render("Before\n\n| A | B |\n|---|:-:|\n| 1 | 2 |\n| 3 | 4 |\n\nAfter")
        #expect(document.string == "Before\nNot shown here: a table.\nAfter")
        let placeholder = document.range(of: "Not shown here: a table.")
        #expect(document.unsupported == [AnswerPlaceholder(kind: .table, range: placeholder)])
        #expect(document.ranges(of: AnswerMarkdown.unsupportedKey) == [placeholder])
        #expect((document.attributes(at: "Not shown")[AnswerMarkdown.unsupportedKey] as? AnswerUnsupportedBox)?.kind == .table)
        for run in document.runs(in: placeholder) {
            #expect(run.colour == NSColor.secondaryLabelColor)
            #expect(run.font.pointSize == 13)
        }
        #expect(document.ranges(of: AnswerMarkdown.imageKey).isEmpty)
    }

    @Test func anImageIsAFigurePlaceholder() {
        let document = render("Look:\n\n![The Z′ plot](figures/z_prime.png)\n\nDone")
        #expect(document.string == "Look:\nFigure: z_prime.png\nDone")
        let placeholder = document.range(of: "Figure: z_prime.png")
        #expect(document.unsupported == [AnswerPlaceholder(kind: .image(name: "z_prime.png"), range: placeholder)])
        #expect(document.ranges(of: AnswerMarkdown.imageKey) == [placeholder])
        #expect(document.ranges(of: AnswerMarkdown.unsupportedKey) == [placeholder])
        let attributes = document.attributes(at: "Figure")
        #expect(attributes[AnswerMarkdown.imageKey] as? String == "z_prime.png")
        #expect((attributes[AnswerMarkdown.unsupportedKey] as? AnswerUnsupportedBox)?.kind == .image(name: "z_prime.png"))
        for run in document.runs(in: placeholder) { #expect(run.colour == NSColor.secondaryLabelColor) }
    }

    @Test func anImageInsideAParagraphSplitsIt() {
        let document = render("Before ![x](a.png) after, and ![y](b.png)")
        #expect(document.string == "Before\nFigure: a.png\nafter, and\nFigure: b.png")
        #expect(document.unsupported.map(\.kind) == [.image(name: "a.png"), .image(name: "b.png")])
        #expect(document.paragraph(at: "after, and").paragraphSpacing == 8)
    }

    @Test func anImageNameIsItsLastSegmentAtMost255Characters() throws {
        func name(_ markdown: String) throws -> String {
            let placeholder = try #require(render(markdown).unsupported.first)
            guard case .image(let name) = placeholder.kind else { Issue.record("not an image"); return "" }
            return name
        }
        #expect(try name("![a](https://example.org/a/b%20c.png?q=1)") == "b c.png")
        let encodedSlash = try name("![a](dir%2Fx.png)")
        #expect(encodedSlash.hasSuffix("x.png") && !encodedSlash.contains("/"))
        let long = try name("![a](" + String(repeating: "a", count: 300) + ".png)")
        #expect(long.count == 255 && long.allSatisfy { $0 == "a" })
        // No file name at all: the words say so, and there is nothing for a thumbnail.
        let bare = render("![a](https://example.org/)")
        #expect(bare.string == "Figure")
        #expect(bare.unsupported.map(\.kind) == [.image(name: "")])
        #expect(bare.ranges(of: AnswerMarkdown.imageKey).isEmpty)
    }

    @Test func anHTMLBlockIsItsSourceInSecondary() {
        let document = render("<div>\nhi\n</div>\n\nAfter")
        #expect(document.string == "<div>\nhi\n</div>\nAfter")
        let source = document.range(of: "<div>\nhi\n</div>")
        #expect(document.unsupported == [AnswerPlaceholder(kind: .html, range: source)])
        #expect(document.ranges(of: AnswerMarkdown.unsupportedKey) == [source])
        for run in document.runs(in: source) {
            #expect(run.colour == NSColor.secondaryLabelColor)
            #expect(run.font.pointSize == 13 && !run.traits.contains(.monoSpace))
        }
        #expect(document.paragraph(at: "<div>").paragraphSpacing == 0)
        #expect(document.paragraph(at: "</div>").paragraphSpacing == 8)
        // Inline HTML is only words in its paragraph.
        let inline = render("a <b>bold</b> c")
        #expect(inline.string == "a <b>bold</b> c")
        #expect(inline.unsupported.isEmpty)
    }

    @Test func placeholdersInsideAListKeepItsIndent() {
        let document = render("- item\n\n  <div>in list</div>\n- ![chart](c.png)\n- last")
        #expect(document.string == "•\titem\n<div>in list</div>\nFigure: c.png\n•\tlast")
        for needle in ["<div>in list</div>", "Figure: c.png"] {
            let paragraph = document.paragraph(at: needle)
            #expect(paragraph.firstLineHeadIndent == 20 && paragraph.headIndent == 20)
            #expect(paragraph.paragraphSpacing == 4)
        }
        #expect(document.unsupported.map(\.kind) == [.html, .image(name: "c.png")])
    }

    @Test func placeholderRangesCountUTF16() {
        let document = render("😀 漢字 👩‍🔬 ünïcödé\n\n![a](fig.png)\n\n| A |\n|---|\n| 1 |\n\n<p>raw</p>")
        let string = document.string as NSString
        let shown = document.unsupported.map { string.substring(with: $0.range) }
        #expect(shown == ["Figure: fig.png", "Not shown here: a table.", "<p>raw</p>"])
        #expect(document.unsupported.map(\.kind) == [.image(name: "fig.png"), .table, .html])
    }

    @Test func everyPlaceholderCarriesItsBox() {
        let document = render(Self.everything)
        #expect(document.unsupported.count == 3)
        #expect(document.ranges(of: AnswerMarkdown.unsupportedKey) == document.unsupported.map(\.range))
        for placeholder in document.unsupported {
            for run in document.runs(in: placeholder.range) {
                #expect((run[AnswerMarkdown.unsupportedKey] as? AnswerUnsupportedBox)?.kind == placeholder.kind)
            }
        }
    }

    // MARK: Edges

    /// Every kind of block, once.
    private static let everything = """
        # Results

        The **plate** *reader* gave `z_prime` above 0.5; see [the run](https://example.com/run) or ~~not~~ this.

        - first
          1. nested
        - second

        > A quoted line.

        ```python
        print("hi")
        ```

        ---

        | A | B |
        |---|---|
        | 1 | 2 |

        ![Figure 2](plots/fig2.png)

        <div>raw</div>

        Last line.
        """

    @Test func theSameAnswerTwiceIsEqual() {
        let first = render(Self.everything), second = render(Self.everything)
        #expect(first.text.isEqual(second.text))
        #expect(first.unsupported == second.unsupported)
    }

    @Test func aLongAnswerRendersWhole() {
        var markdown = ""
        var paragraphs = 0
        while markdown.count <= 20_000 {
            paragraphs += 1
            markdown += "## Part \(paragraphs)\n\nParagraph \(paragraphs) has **bold**, `code` and [a link](https://example.com/\(paragraphs)).\n\n"
                + "- an item\n- another\n\n| A |\n|---|\n| \(paragraphs) |\n\n"
        }
        #expect(markdown.count > 20_000)
        let document = render(markdown)
        #expect(document.string.components(separatedBy: "Paragraph ").count - 1 == paragraphs)
        #expect(document.unsupported.count == paragraphs)
        #expect(document.unsupported.allSatisfy { $0.kind == .table })
        #expect(!document.string.hasSuffix("\n"))
    }

    @Test func aParseThatThrowsShowsTheRawTextAsOneParagraph() {
        let raw = "# Not *parsed*\n\n- raw | text"
        let document = AnswerMarkdown.render(raw + "\n", style: .standard) { _ in throw ParseFailed() }
        #expect(document.string == raw)
        #expect(document.unsupported.isEmpty)
        let runs = document.runs(in: document.whole)
        #expect(runs.count == 1)
        #expect(runs.first?.font.pointSize == 13)
        #expect(runs.first?.colour == NSColor.labelColor)
        #expect(runs.first?.paragraph.paragraphSpacing == 8)
    }
}
