// CompareTextView.swift — Text Changes drawn (DESIGN.md, Compare): one column of
// the source text, every line of both files once, in a read-only text view, so
// selecting and copying work as they do anywhere (the words and nothing else:
// the markers are drawn, not typed). A line only on the left is marked − in a
// gutter, its words in the muted ink on a faint ink ground; a line only on the
// right is marked + in clay-text on a faint clay ground. VoiceOver reads each
// changed line as "Removed, …" or "Added, …", and Previous and Next Change
// select the change and say what it is. The column is monospaced: it is the file
// as written, not the document rendered.
import AppKit
import SwiftUI

/// The column, ready to draw: its text, where each changed line is, and each change (a run of changed lines) with what
/// VoiceOver says on reaching it.
struct CompareTextDocument {
    struct Mark: Equatable {
        /// The line, with its line break when it has one.
        let range: NSRange
        let kind: CompareDiff.Kind
    }

    let text: NSAttributedString
    /// The changed lines, in order.
    let marks: [Mark]
    /// Each change: from the start of its first line to the end of its last.
    let changes: [NSRange]
    let spoken: [String]
    let added: Int
    let removed: Int

    static var font: NSFont { .monospacedSystemFont(ofSize: 12.5, weight: .regular) }
    static let lineHeight: CGFloat = 19
    /// Room at the leading edge for the markers.
    static let gutter: CGFloat = 30

    init(lines: [CompareDiff.Line]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Self.lineHeight
        paragraph.maximumLineHeight = Self.lineHeight
        paragraph.firstLineHeadIndent = Self.gutter
        paragraph.headIndent = Self.gutter
        paragraph.tailIndent = -16
        paragraph.lineBreakMode = .byWordWrapping
        let plain: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: Solanum.inkColor, .paragraphStyle: paragraph]
        var quiet = plain
        quiet[.foregroundColor] = Solanum.mutedColor
        let text = NSMutableAttributedString()
        var marks: [Mark] = []
        var location = 0
        var added = 0, removed = 0
        var lineStarts: [Int] = []
        lineStarts.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            let words = index < lines.count - 1 ? line.text + "\n" : line.text
            let length = (words as NSString).length
            text.append(NSAttributedString(string: words, attributes: line.kind == .removed ? quiet : plain))
            lineStarts.append(location)
            switch line.kind {
            case .same: break
            case .added:
                added += 1
                marks.append(Mark(range: NSRange(location: location, length: length), kind: .added))
            case .removed:
                removed += 1
                marks.append(Mark(range: NSRange(location: location, length: length), kind: .removed))
            }
            location += length
        }
        let runs = CompareDiff.changes(in: lines)
        changes = runs.map { run in
            let start = lineStarts[run.lowerBound]
            let end = run.upperBound < lineStarts.count ? lineStarts[run.upperBound] : location
            return NSRange(location: start, length: end - start)
        }
        spoken = runs.enumerated().map { offset, run in
            let slice = lines[run]
            return CompareRules.spoken(change: offset, of: runs.count, added: slice.filter { $0.kind == .added }.count,
                                       removed: slice.filter { $0.kind == .removed }.count)
        }
        self.text = text
        self.marks = marks
        self.added = added
        self.removed = removed
    }

    /// "Added, " or "Removed, ": what VoiceOver hears before a changed line.
    static func spokenPrefix(_ kind: CompareDiff.Kind) -> String {
        switch kind {
        case .same: ""
        case .added: "Added, "
        case .removed: "Removed, "
        }
    }

    /// `string`'s characters in `range`, as VoiceOver reads them: each changed line that starts in the range says
    /// whether it was added or removed first.
    static func spoken(_ string: NSString, range: NSRange, marks: [Mark]) -> String {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        var out = ""
        var at = range.location
        for mark in marks where mark.range.location >= range.location && mark.range.location < NSMaxRange(range) {
            out += string.substring(with: NSRange(location: at, length: mark.range.location - at))
            out += spokenPrefix(mark.kind)
            at = mark.range.location
        }
        out += string.substring(with: NSRange(location: at, length: NSMaxRange(range) - at))
        return out
    }
}

/// The ground under each kind of changed line.
enum CompareTint {
    static let added = NSColor(name: nil) { appearance in
        NSColor(Theme.clay).withAlphaComponent(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.16 : 0.12)
    }
    static let removed = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.06)
            : NSColor(srgbRed: 31 / 255, green: 30 / 255, blue: 29 / 255, alpha: 0.05)
    }
}

/// The read-only text view of Text Changes: TextKit 1, so each line's fragments are known to draw its ground and its
/// marker, and plain text, so Copy copies the words.
final class CompareChangesTextView: NSTextView {
    var marks: [CompareTextDocument.Mark] = [] { didSet { needsDisplay = true } }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer, !marks.isEmpty else { return }
        let origin = textContainerOrigin
        let visible = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        // The first mark that could be in view.
        var low = 0, high = marks.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(marks[mid].range) < characters.location { low = mid + 1 } else { high = mid }
        }
        let length = (string as NSString).length
        for mark in marks[low...] {
            if mark.range.location > NSMaxRange(characters) { break }
            var fragments: [NSRect] = []
            if mark.range.location >= length {
                // An empty last line has no characters: the extra line fragment is where it is.
                let extra = layoutManager.extraLineFragmentRect
                if extra.height > 0 { fragments.append(extra) }
            } else {
                let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: mark.range.location, length: max(1, mark.range.length)),
                                                      actualCharacterRange: nil)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in fragments.append(fragment) }
            }
            guard let first = fragments.first else { continue }
            (mark.kind == .added ? CompareTint.added : CompareTint.removed).setFill()
            for fragment in fragments {
                NSRect(x: 0, y: fragment.minY + origin.y, width: bounds.width, height: fragment.height).fill()
            }
            // The marker on the line's own baseline, centred in the gutter.
            let marker = (mark.kind == .added ? "+" : "\u{2212}") as NSString
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: mark.kind == .added ? Theme.clayTextColor : Solanum.mutedColor,
            ]
            let baseline = mark.range.location < length
                ? layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: mark.range.location)).y
                : (length > 0 ? layoutManager.location(forGlyphAt: 0).y : first.height * 0.75)
            let width = marker.size(withAttributes: attributes).width
            marker.draw(at: NSPoint(x: (CompareTextDocument.gutter - 6 - width) / 2, y: first.minY + origin.y + baseline - font.ascender),
                        withAttributes: attributes)
        }
    }

    // VoiceOver hears "Added, …" and "Removed, …" before a changed line; the text and a copy of it are the words alone.
    override func accessibilityString(for range: NSRange) -> String? {
        CompareTextDocument.spoken(string as NSString, range: range, marks: marks)
    }

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        NSAttributedString(string: CompareTextDocument.spoken(string as NSString, range: range, marks: marks))
    }

    /// Selects `range` and scrolls it to a third of the way down, so the lines before it show too.
    func reveal(_ range: NSRange) {
        guard let layoutManager, let textContainer, let scroll = enclosingScrollView else { return }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(range)))
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: 0, dy: textContainerOrigin.y)
        let visible = scroll.contentView.bounds.height
        let top = max(0, min(rect.minY - visible / 3, frame.height - visible))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
        setSelectedRange(range)
        // The keyboard follows, so ⌘C copies the change and the arrows start from it.
        window?.makeFirstResponder(self)
    }
}

/// The column in a scroll view of its own, for SwiftUI.
struct CompareChangesView: NSViewRepresentable {
    let document: CompareTextDocument
    /// The change to go to, and the count of jumps asked for: a new count scrolls to it.
    let change: Int?
    let jumps: Int
    let label: String

    final class Coordinator {
        var shown: NSAttributedString?
        var jumps = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The text view, read-only and plain (so a copy is the words alone), on TextKit 1.
    static func makeTextView() -> CompareChangesTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let textView = CompareChangesTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.selectedTextAttributes = [.backgroundColor: Solanum.selectionColor]
        return textView
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = Self.makeTextView()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CompareChangesTextView else { return }
        textView.setAccessibilityLabel(label)
        if context.coordinator.shown !== document.text {
            context.coordinator.shown = document.text
            textView.textStorage?.setAttributedString(document.text)
            textView.marks = document.marks
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
        if context.coordinator.jumps != jumps {
            context.coordinator.jumps = jumps
            if let change, document.changes.indices.contains(change) {
                textView.reveal(document.changes[change])
            }
        }
    }
}
