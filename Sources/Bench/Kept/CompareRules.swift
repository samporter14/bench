// CompareRules.swift — the decisions behind Compare (DESIGN.md, Compare), pure:
// which two Shelf items make a pair (two pictures ImageIO can read, or two text
// files read as source), what a Shelf card's menu offers (Compare With and the
// cards shown that pair with it, or Compare on two picks) and what it says when
// nothing pairs, when the title bar's Compare pill shows, the words
// each side carries (its file's name and its own source line, nothing invented),
// whether Wipe is offered (the same upright pixel size), and the geometry of a
// picture in its pane: Fit, a zoom relative to each picture's own fit and a
// centre shared as a fraction of each picture, held inside each picture's
// bounds. Nothing here reads the disk or draws, so the tests run it as it is.
import CoreGraphics
import Foundation

/// What two Shelf items are compared as.
enum CompareKind: Equatable, Sendable {
    /// Two raster pictures, side by side (and Wipe when their sizes match).
    case images
    /// Two text files, as their source text, line by line.
    case text
}

enum CompareRules {
    // MARK: The pair

    /// Pictures ImageIO decodes. An SVG is a figure on the Shelf but is drawn, not decoded, so it isn't one of these.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "bmp", "heic", "avif"]
    /// The Shelf's prose formats (`ShelfPeek.proseExtensions`), compared as source text. A note made by Add Selection to
    /// Shelf is a `note.md` and compares as one.
    static let textExtensions: Set<String> = ShelfPeek.proseExtensions

    /// What a file is compared as, by its name; nil for a kind Compare doesn't read (a PDF, a table, an SVG…).
    static func kind(of fileName: String) -> CompareKind? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .images }
        if textExtensions.contains(ext) { return .text }
        return nil
    }

    /// Whether the picks can be compared, and if not, why.
    enum Pairing: Equatable, Sendable {
        case comparable(CompareKind)
        /// Two items, but not two of a kind Compare reads.
        case notComparable
    }

    /// Two items pair when both are pictures or both are text files.
    static func pairing(_ a: ShelfItem, _ b: ShelfItem) -> Pairing {
        guard let first = kind(of: a.fileName), let second = kind(of: b.fileName), first == second else { return .notComparable }
        return .comparable(first)
    }

    /// The Shelf card's menu item while two are picked: "Compare", or, when the pair isn't one Compare reads, the
    /// same words with the reason, dimmed.
    static let menuTitle = "Compare"
    static let unavailableTitle = "Compare (Two Pictures or Two Text Files)"
    static let unavailableHelp = "Compare reads two pictures, or two text or Markdown files, side by side."

    // MARK: The card's menu

    /// What a Shelf card's menu offers for Compare, after Export … as PDF….
    enum Offer: Equatable, Sendable {
        /// Nothing: a kind Compare doesn't read (a PDF, a table, an SVG…), outside a pair of picks.
        case none
        /// Exactly two picked, this card one of them, and they pair: Compare, left and right as the Shelf shows them.
        case compare(left: ShelfItem, right: ShelfItem)
        /// Exactly two picked, this card one of them, and they don't pair: `unavailableTitle`, dimmed, with its reason.
        case unavailable
        /// Compare With ▸ and the other items this card pairs with.
        case compareWith([Entry])
        /// Compare With, dimmed: this card is one Compare reads, but nothing shown pairs with it. The help says why.
        case nothingToCompareWith(help: String)
    }

    /// One line of Compare With: the card the menu belongs to on the left, the one chosen on the right.
    struct Entry: Equatable, Identifiable, Sendable {
        let left: ShelfItem
        let right: ShelfItem
        /// "z_prime_by_plate.png (Plate reader QC · 8:47 AM)": the right side's name and its card's caption.
        let title: String
        var id: String { right.id }
    }

    static let compareWithTitle = "Compare With"
    /// Compare With lists at most this many: the first that pair, in the order the Shelf shows them.
    static let compareWithLimit = 12
    /// The longest a name, or a session, runs in an entry before it is cut short, so an entry stays one calm line.
    static let entryNameLimit = 40
    static let entrySessionLimit = 36

    /// The dimmed Compare With's help: nothing else of its kind, on the Shelf or among the cards a search, a project or
    /// a kind leaves shown.
    static func nothingToCompareWithHelp(_ kind: CompareKind, filtered: Bool) -> String {
        let what = kind == .images ? "picture" : "text file"
        return filtered
            ? "No other \(what) is shown to compare with. Clear the search or the filters to see more."
            : "There\u{2019}s no other \(what) on the Shelf to compare with."
    }

    /// The card's offer. `pickedPair` is the two picks, in the Shelf's order, when exactly two are picked and this card
    /// is one of them (`ShelfModel.comparePair`): then the menu says what it said before Compare With, and nothing
    /// more. Otherwise a card Compare reads gets Compare With, from `shown` (the cards the Shelf shows now, in their
    /// order, so the search, the project and the kind chip narrow it), and any other card gets nothing. Only names and
    /// what the cards already say are read: nothing from disk, no thumbnails.
    static func offer(for item: ShelfItem, pickedPair: (ShelfItem, ShelfItem)?, shown: [ShelfItem], filtered: Bool,
                      limit: Int = compareWithLimit, now: Date = Date(), calendar: Calendar = .current,
                      locale: Locale = .current) -> Offer {
        if let pair = pickedPair, pair.0.id == item.id || pair.1.id == item.id {
            guard case .comparable = pairing(pair.0, pair.1) else { return .unavailable }
            return .compare(left: pair.0, right: pair.1)
        }
        guard let kind = kind(of: item.fileName) else { return .none }
        let others = candidates(for: item, in: shown, limit: limit)
        guard !others.isEmpty else { return .nothingToCompareWith(help: nothingToCompareWithHelp(kind, filtered: filtered)) }
        return .compareWith(entries(for: item, others, now: now, calendar: calendar, locale: locale))
    }

    /// The items Compare With lists for `item`: those shown that pair with it, not itself, in the order shown, at most
    /// `limit`. Stops reading `shown` once it has them.
    static func candidates(for item: ShelfItem, in shown: [ShelfItem], limit: Int = compareWithLimit) -> [ShelfItem] {
        guard let mine = kind(of: item.fileName), limit > 0 else { return [] }
        var found: [ShelfItem] = []
        for other in shown where other.id != item.id && kind(of: other.fileName) == mine {
            found.append(other)
            if found.count == limit { break }
        }
        return found
    }

    /// The entries for `others`, `item` on the left of each. One that would read the same as another, or as the card
    /// itself (one name, one session, one day), also says its version, when it is known.
    static func entries(for item: ShelfItem, _ others: [ShelfItem], now: Date = Date(), calendar: Calendar = .current,
                        locale: Locale = .current) -> [Entry] {
        let titles = others.map { entryTitle(for: $0, now: now, calendar: calendar, locale: locale) }
        var seen: [String: Int] = [entryTitle(for: item, now: now, calendar: calendar, locale: locale): 1]
        for title in titles { seen[title, default: 0] += 1 }
        return zip(others, titles).map { other, title in
            let same = seen[title, default: 0] > 1
            return Entry(left: item, right: other,
                         title: same ? entryTitle(for: other, now: now, calendar: calendar, locale: locale, version: true) : title)
        }
    }

    /// An entry's words: the name the card shows, then in brackets its caption (the session, and when it was put on the
    /// Shelf), and the version when asked and known. One line: a long name is cut in the middle (its extension kept),
    /// a long session at its end. The brackets keep a keep's own name, which may hold a "·" itself, apart from the
    /// caption: "Fig 2B · Z′ by plate (Plate reader QC · Sun)".
    static func entryTitle(for item: ShelfItem, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current,
                           version: Bool = false) -> String {
        let name = clipped(oneLine(item.title), to: entryNameLimit, middle: true)
        var caption: [String] = []
        let session = oneLine(item.record.sessionTitle)
        if !session.isEmpty { caption.append(clipped(session, to: entrySessionLimit, middle: false)) }
        caption.append(ShelfRules.when(item.addedAt, now: now, calendar: calendar, locale: locale))
        if version, let index = item.record.figure.index { caption.append("version \(index)") }
        return "\(name) (\(caption.joined(separator: " \u{00B7} ")))"
    }

    /// Line breaks and runs of spaces as one space, trimmed.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// `text` at most `limit` characters, an ellipsis where it was cut: in the middle, or at the end.
    static func clipped(_ text: String, to limit: Int, middle: Bool) -> String {
        guard text.count > limit, limit > 1 else { return text }
        guard middle else { return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}" }
        let tail = (limit - 1) / 2, head = limit - 1 - tail
        return String(text.prefix(head)) + "\u{2026}" + String(text.suffix(tail))
    }

    // MARK: The title bar's pill

    /// The Compare pill beside Export as PDF…: shown only for exactly two picks that pair.
    static let pillTitle = "Compare"
    static func pillHelp(_ kind: CompareKind) -> String {
        kind == .images ? "Put the two pictures side by side" : "See what changed between the two text files, line by line"
    }
    static func pillSpoken(_ kind: CompareKind) -> String {
        kind == .images ? "Compare the two pictures" : "Compare the two text files"
    }

    // MARK: Each side's words

    /// "Plate reader QC · version 3": the session and the version, each only when known; nil when neither is. The
    /// project and the times are left to the Shelf: a side says where it came from, not when.
    static func sourceLine(for item: ShelfItem) -> String? {
        let record = item.record
        var parts: [String] = []
        let session = record.sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !session.isEmpty { parts.append(session) }
        if let index = record.figure.index {
            parts.append(record.figure.of.map { "version \(index) of \($0)" } ?? "version \(index)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// "1,600 × 1,200 px", and when the picture was decoded smaller than that, "· shown at 3,072 × 2,304".
    static func pixelLine(source: CGSize, shown: CGSize) -> String {
        let size = "\(grouped(source.width)) \u{00D7} \(grouped(source.height)) px"
        guard Int(shown.width) < Int(source.width) || Int(shown.height) < Int(source.height) else { return size }
        return size + " \u{00B7} shown at \(grouped(shown.width)) \u{00D7} \(grouped(shown.height))"
    }

    /// The same, for VoiceOver: "1600 by 1200 pixels".
    static func pixelSpoken(source: CGSize) -> String {
        "\(Int(source.width)) by \(Int(source.height)) pixels"
    }

    static func grouped(_ value: CGFloat) -> String { Int(value).formatted(.number.grouping(.automatic)) }
    static func grouped(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }

    /// Wipe lays one picture over the other in one coordinate system, so it is offered only when their upright pixel
    /// sizes are the same; otherwise it isn't offered at all.
    static func canWipe(_ a: CGSize?, _ b: CGSize?) -> Bool {
        guard let a, let b, a.width > 0, a.height > 0 else { return false }
        return Int(a.width) == Int(b.width) && Int(a.height) == Int(b.height)
    }

    // MARK: The sentences

    /// The quiet note after a rescan found a side's file changed.
    static func changedOnDisk(_ names: [String]) -> String {
        names.count == 1
            ? "\u{201C}\(names[0])\u{201D} changed on disk, so both sides were read again."
            : "Both files changed on disk, so both sides were read again."
    }

    /// The quiet note after a file changed while it was read.
    static func changedWhileReading(_ name: String) -> String {
        "\u{201C}\(name)\u{201D} changed while Capsid read it, so both sides were read again."
    }

    static let textTitle = "Text Changes"
    static let textSubtitle = "source text, not rendered"

    static let noChangesTitle = "No text changes"
    static let noChangesSentence = "The two files have the same source text."
    static let sameLinesTitle = "Every line is the same"
    /// Only the end differs: one file ends with a line break and the other doesn't.
    static func lastLineBreak(leftEnds: Bool, left: String, right: String) -> String {
        let (ends, doesnt) = leftEnds ? (left, right) : (right, left)
        return "Only the end differs: \u{201C}\(ends)\u{201D} ends with a line break and \u{201C}\(doesnt)\u{201D} doesn\u{2019}t."
    }

    static let tooManyLinesTitle = "Too many lines to compare line by line"
    static let tooManyChangesTitle = "Too many changes to list line by line"
    /// Under either: the counts, and the bounds.
    static func counts(left: String, leftLines: Int, right: String, rightLines: Int) -> String {
        "\u{201C}\(left)\u{201D} has \(lines(leftLines)) and \u{201C}\(right)\u{201D} has \(lines(rightLines)). "
            + "Compare lists up to \(grouped(CompareDiff.lineLimit)) lines a side and \(grouped(CompareDiff.editLimit)) changed lines."
    }

    static func lines(_ count: Int) -> String { count == 1 ? "1 line" : "\(grouped(count)) lines" }

    /// "3 changes · 5 lines added, 2 removed".
    static func summary(changes: Int, added: Int, removed: Int) -> String {
        let runs = changes == 1 ? "1 change" : "\(grouped(changes)) changes"
        var parts: [String] = []
        if added > 0 { parts.append("\(lines(added)) added") }
        if removed > 0 { parts.append(parts.isEmpty ? "\(lines(removed)) removed" : "\(grouped(removed)) removed") }
        return ([runs] + [parts.joined(separator: ", ")]).filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// What VoiceOver says on reaching a change with Previous or Next Change: "Change 2 of 5. Removed 1 line, added 2."
    static func spoken(change: Int, of count: Int, added: Int, removed: Int) -> String {
        var what: [String] = []
        if removed > 0 { what.append("Removed \(lines(removed))") }
        if added > 0 { what.append(what.isEmpty ? "Added \(lines(added))" : "added \(grouped(added))") }
        return "Change \(change + 1) of \(count). " + what.joined(separator: ", ") + "."
    }
}

// MARK: - Where a picture sits in its pane

/// A picture's zoom and pan, relative to its own fit: `scale` 1 is Fit (the whole picture in the pane, its aspect
/// kept), 2 twice that; `center` is the point of the picture at the pane's centre, as a fraction of its width and
/// height (0.5, 0.5 is its middle). Linked panes share one of these, so each picture shows the same fraction of itself
/// at the same zoom relative to its own fit, whatever its size.
struct CompareViewport: Equatable, Sendable {
    var scale: CGFloat = 1
    var center = CGPoint(x: 0.5, y: 0.5)

    static let fit = CompareViewport()
    /// Zooms run from Fit to this many times it.
    static let maxScale: CGFloat = 32
}

enum CompareGeometry {
    /// The scale that fits `image` (pixels) in `view` (points), aspect kept: points per pixel.
    static func fitScale(image: CGSize, view: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0, view.width > 0, view.height > 0 else { return 1 }
        return min(view.width / image.width, view.height / image.height)
    }

    /// The picture's size on screen at `viewport`.
    static func drawnSize(image: CGSize, view: CGSize, viewport: CompareViewport) -> CGSize {
        let scale = fitScale(image: image, view: view) * viewport.scale
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// The centre held inside the picture: the pane never shows past an edge of a picture larger than it, and a
    /// picture smaller than the pane along an axis stays centred along it.
    static func clamped(_ viewport: CompareViewport, image: CGSize, view: CGSize) -> CompareViewport {
        var held = viewport
        held.scale = min(CompareViewport.maxScale, max(1, viewport.scale))
        let drawn = drawnSize(image: image, view: view, viewport: held)
        func axis(_ c: CGFloat, _ visible: CGFloat, _ length: CGFloat) -> CGFloat {
            guard length > 0 else { return 0.5 }
            let half = visible / (2 * length)
            guard half < 0.5 else { return 0.5 }
            return min(1 - half, max(half, c.isFinite ? c : 0.5))
        }
        held.center = CGPoint(x: axis(viewport.center.x, view.width, drawn.width),
                              y: axis(viewport.center.y, view.height, drawn.height))
        return held
    }

    /// Where the picture is drawn in its pane (top-left origin, y down), after clamping.
    static func imageRect(image: CGSize, view: CGSize, viewport: CompareViewport) -> CGRect {
        let held = clamped(viewport, image: image, view: view)
        let drawn = drawnSize(image: image, view: view, viewport: held)
        return CGRect(x: view.width / 2 - held.center.x * drawn.width, y: view.height / 2 - held.center.y * drawn.height,
                      width: drawn.width, height: drawn.height)
    }

    /// A drag of `delta` points on a picture: the centre moves the other way by that fraction of the picture, and is
    /// held inside it.
    static func panned(_ viewport: CompareViewport, by delta: CGSize, image: CGSize, view: CGSize) -> CompareViewport {
        let drawn = drawnSize(image: image, view: view, viewport: clamped(viewport, image: image, view: view))
        guard drawn.width > 0, drawn.height > 0 else { return viewport }
        var moved = clamped(viewport, image: image, view: view)
        moved.center.x -= delta.width / drawn.width
        moved.center.y -= delta.height / drawn.height
        return clamped(moved, image: image, view: view)
    }

    /// A zoom by `factor` about `anchor` (a point in the pane): the point of the picture under it stays under it,
    /// within the picture's bounds and Fit to 32 times it.
    static func zoomed(_ viewport: CompareViewport, by factor: CGFloat, at anchor: CGPoint?, image: CGSize, view: CGSize) -> CompareViewport {
        let before = clamped(viewport, image: image, view: view)
        let scale = min(CompareViewport.maxScale, max(1, before.scale * factor))
        let anchor = anchor ?? CGPoint(x: view.width / 2, y: view.height / 2)
        let drawnBefore = drawnSize(image: image, view: view, viewport: before)
        guard drawnBefore.width > 0, drawnBefore.height > 0 else { return before }
        // The picture's point under the anchor, as a fraction of it.
        let u = CGPoint(x: before.center.x + (anchor.x - view.width / 2) / drawnBefore.width,
                        y: before.center.y + (anchor.y - view.height / 2) / drawnBefore.height)
        var after = before
        after.scale = scale
        let drawnAfter = drawnSize(image: image, view: view, viewport: after)
        after.center = CGPoint(x: u.x - (anchor.x - view.width / 2) / drawnAfter.width,
                               y: u.y - (anchor.y - view.height / 2) / drawnAfter.height)
        return clamped(after, image: image, view: view)
    }

    /// The pixel of the picture (in its own pixels, top-left origin) under a point of the pane, or nil off the picture.
    static func pixel(at point: CGPoint, image: CGSize, view: CGSize, viewport: CompareViewport) -> CGPoint? {
        let rect = imageRect(image: image, view: view, viewport: viewport)
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width * image.width, y: (point.y - rect.minY) / rect.height * image.height)
    }
}

// MARK: - The wipe

/// The divider of Wipe, as a fraction of the pane's width from its leading edge: left of it is the left side's picture,
/// right of it the right side's, both drawn in the one rectangle, so neither moves as the divider does.
enum CompareWipe {
    /// What an arrow key moves it by, and what VoiceOver's increment does.
    static let step: Double = 0.05
    /// With Option: a finer step.
    static let fineStep: Double = 0.01

    static func clamped(_ fraction: Double) -> Double { min(1, max(0, fraction.isFinite ? fraction : 0.5)) }

    static func stepped(_ fraction: Double, by steps: Int, fine: Bool = false) -> Double {
        // Rounded to the step, so repeated presses land on 45%, 50%, 55%… rather than drifting.
        let size = fine ? fineStep : step
        let raw = clamped(fraction) + Double(steps) * size
        return clamped((raw / size).rounded() * size)
    }

    /// "50%": the divider's value, as VoiceOver reads it.
    static func percent(_ fraction: Double) -> String { "\(Int((clamped(fraction) * 100).rounded()))%" }

    /// The divider's position in a pane `width` points wide.
    static func x(_ fraction: Double, width: CGFloat) -> CGFloat { CGFloat(clamped(fraction)) * width }
}
