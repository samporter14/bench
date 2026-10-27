// CompareRulesTests.swift — Compare's rules (Kept/CompareRules.swift,
// CompareImages.swift, CompareTextView.swift): which two Shelf items pair and
// what the Shelf's menu says when they don't, each side's words, the pictures
// decoded upright and within their bounds (an EXIF-turned JPEG, a large picture,
// a header with too many pixels, bytes that aren't a picture), Wipe's sizes and
// divider, the geometry of Fit, zoom and pan, and the Text Changes column: its
// marks, what VoiceOver hears, and a copy that is the words alone.
import AppKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct CompareRulesTests {
    // MARK: The pair

    @Test func twoPicturesOrTwoTextFilesPairAndNothingElseDoes() {
        let png = CompareFixtures.item("z_prime_by_plate.png"), jpg = CompareFixtures.item("plate_7.JPG")
        let md = CompareFixtures.item("qc_notes.md"), txt = CompareFixtures.item("qc_notes.txt")
        let note = CompareFixtures.item("note.md", version: nil)
        #expect(CompareRules.pairing(png, jpg) == .comparable(.images))
        #expect(CompareRules.pairing(md, txt) == .comparable(.text))
        #expect(CompareRules.pairing(md, note) == .comparable(.text))
        #expect(CompareRules.pairing(png, md) == .notComparable)
        for other in ["receptors.xlsx", "z_prime_by_plate.csv", "plot.py", "page.html"] {
            #expect(CompareRules.pairing(png, CompareFixtures.item(other)) == .notComparable, "\(other)")
            #expect(CompareRules.pairing(CompareFixtures.item(other), md) == .notComparable, "\(other)")
        }
        // PDFs and SVGs are figures: they pair with a picture, and with each other, never with text.
        #expect(CompareRules.kind(of: "figure.svg") == .images)
        #expect(CompareRules.kind(of: "Z_PRIME_BY_PLATE.PDF") == .images)
        let pdf = CompareFixtures.item("z_prime_by_plate.pdf"), svg = CompareFixtures.item("z_prime_by_plate.svg")
        #expect(CompareRules.pairing(png, pdf) == .comparable(.images))
        #expect(CompareRules.pairing(pdf, svg) == .comparable(.images))
        #expect(CompareRules.pairing(svg, jpg) == .comparable(.images))
        #expect(CompareRules.pairing(pdf, md) == .notComparable && CompareRules.pairing(note, svg) == .notComparable)
        #expect(CompareRules.kind(of: "notes.RST") == .text)
        #expect(CompareRules.kind(of: "scan.heic") == .images)
    }

    @Test func eachSideSaysItsOwnSessionAndVersionAndNothingItDoesntKnow() {
        #expect(CompareRules.sourceLine(for: CompareFixtures.item("a.png", session: "Plate reader QC", version: 3)) == "Plate reader QC \u{00B7} version 3")
        #expect(CompareRules.sourceLine(for: CompareFixtures.item("a.png", version: 3, of: 4)) == "Plate reader QC \u{00B7} version 3 of 4")
        #expect(CompareRules.sourceLine(for: CompareFixtures.item("a.png", session: "Assay development", version: nil)) == "Assay development")
        #expect(CompareRules.sourceLine(for: CompareFixtures.item("a.png", session: " ", version: nil)) == nil)
    }

    @Test func theShelfMenuNamesTheReasonWhenThePairCantBeCompared() {
        #expect(CompareRules.menuTitle == "Compare")
        #expect(CompareRules.unavailableTitle.hasPrefix("Compare ("))
        #expect(CompareRules.unavailableTitle.count < 45)
    }

    @Test func twoPickedOnTheShelfAreThePairInTheShelfsOrderAndOtherCountsAreNone() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compare-pair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root), pdf: ShelfPDFMaker(dependencies: .declining))
        func named(_ file: String) -> ShelfItem { model.shown.first { $0.fileName == file }! }
        // One picked: no pair.
        model.pick(named("plate_7_heatmap.png").id, .only)
        #expect(model.comparePair == nil)
        // Picked in either order, the pair is in the Shelf's order (the newer card first).
        model.pick(named("z_prime_by_plate.png").id, .toggle)
        let pair = try #require(model.comparePair)
        #expect(pair.0.fileName == "z_prime_by_plate.png" && pair.1.fileName == "plate_7_heatmap.png")
        #expect(CompareRules.pairing(pair.0, pair.1) == .comparable(.images))
        // A third: no pair.
        model.pick(named("qc_notes.md").id, .toggle)
        #expect(model.comparePair == nil)
        // A picture and a note: a pair that can't be compared.
        model.pick(named("qc_notes.md").id, .only)
        model.pick(named("knockdown_blot.png").id, .toggle)
        let mixed = try #require(model.comparePair)
        #expect(CompareRules.pairing(mixed.0, mixed.1) == .notComparable)
        // Two documents.
        model.pick(named("methods_draft.md").id, .toggle)
        model.pick(named("knockdown_blot.png").id, .toggle)
        let documents = try #require(model.comparePair)
        #expect(CompareRules.pairing(documents.0, documents.1) == .comparable(.text))
    }

    // MARK: Pictures

    private func gradient(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) { (UInt8(x % 256), UInt8(y % 256), 128) }

    @Test func aPictureIsDecodedUprightWithItsOwnPixelSize() throws {
        let png = try CompareImages.decode(CompareFixtures.png(width: 400, height: 300, colour: gradient)).get()
        #expect(png.source == CGSize(width: 400, height: 300) && png.shown == CGSize(width: 400, height: 300))
        // Stored 400 × 300 on its side (EXIF 6): seen, and stated, as 300 × 400.
        let turned = try CompareImages.decode(CompareFixtures.jpeg(width: 400, height: 300, orientation: 6, colour: gradient)).get()
        #expect(turned.source == CGSize(width: 300, height: 400))
        #expect(turned.shown == CGSize(width: 300, height: 400))
        #expect(CompareImages.uprightSize(width: 400, height: 300, orientation: 8) == CGSize(width: 300, height: 400))
        #expect(CompareImages.uprightSize(width: 400, height: 300, orientation: 3) == CGSize(width: 400, height: 300))
        // Wipe goes by the upright size: the turned JPEG matches a 300 × 400 PNG, not a 400 × 300 one.
        let tall = try CompareImages.decode(CompareFixtures.png(width: 300, height: 400, colour: gradient)).get()
        #expect(CompareRules.canWipe(turned.source, tall.source))
        #expect(!CompareRules.canWipe(turned.source, png.source))
        #expect(!CompareRules.canWipe(png.source, nil))
    }

    @Test func aLargePictureIsDecodedSmallerAndStillStatesItsOwnSize() throws {
        let wide = try CompareImages.decode(CompareFixtures.png(width: 4_000, height: 1_000, colour: gradient)).get()
        #expect(wide.source == CGSize(width: 4_000, height: 1_000))
        #expect(wide.shown == CGSize(width: 3_072, height: 768))
        #expect(CompareRules.pixelLine(source: wide.source, shown: wide.shown) == "4,000 \u{00D7} 1,000 px \u{00B7} shown at 3,072 \u{00D7} 768")
        #expect(CompareRules.pixelLine(source: CGSize(width: 480, height: 320), shown: CGSize(width: 480, height: 320)) == "480 \u{00D7} 320 px")
        // At most 3,072 × 3,072 × 4 bytes a side.
        #expect(wide.image.bytesPerRow * wide.image.height <= CompareImages.sideLimit * CompareImages.sideLimit * 4 + 64 * CompareImages.sideLimit)
    }

    @Test func tooManyPixelsOrBytesThatArentAPictureAreRefusedUnread() {
        let data = CompareFixtures.png(width: 400, height: 300, colour: gradient)
        #expect(CompareImages.decode(data, maxPixels: 100_000) == .failure(.tooManyPixels(CGSize(width: 400, height: 300))))
        #expect(CompareImages.decode(Data("not a picture".utf8)) == .failure(.notAnImage))
        #expect(CompareImages.decode(Data()) == .failure(.notAnImage))
        #expect(CompareImages.pixelLimit == 64_000_000 && CompareImages.byteLimit == 8 << 20)
    }

    // MARK: PDFs and SVGs

    @Test func aPDFsFirstPageIsDrawnOnWhiteAtItsOwnAspectAndStatedInPoints() throws {
        let one = try CompareImages.decode(CompareFixtures.pdf(width: 400, height: 300)).get()
        #expect(one.unit == .points && one.source == CGSize(width: 400, height: 300) && one.pages == 1)
        // Its long side at the limit, its aspect kept.
        #expect(one.shown == CGSize(width: 3_072, height: 2_304))
        // On white where the page is empty, the bar's blue in the lower half.
        let top = CompareFixtures.pixel(one.image, x: 1_536, y: 400), bottom = CompareFixtures.pixel(one.image, x: 1_536, y: 2_000)
        #expect(top.r > 245 && top.g > 245 && top.b > 245, "\(top)")
        #expect(bottom.b > 150 && bottom.r < 60, "\(bottom)")
        #expect(CompareRules.sizeLine(one) == "400 \u{00D7} 300 pt")
        #expect(CompareRules.sizeSpoken(one) == "400 by 300 points")
        // Several pages: the first is shown, and its side says so.
        let three = try CompareImages.decode(CompareFixtures.pdf(width: 612, height: 792, pages: 3)).get()
        #expect(three.pages == 3 && three.shown == CGSize(width: 2_374, height: 3_072))
        #expect(CompareRules.sizeLine(three) == "612 \u{00D7} 792 pt \u{00B7} page 1 of 3")
        #expect(CompareRules.sizeLine(three, pages: false) == "612 \u{00D7} 792 pt")
        #expect(CompareRules.sizeSpoken(three) == "612 by 792 points, page 1 of 3")
        // A picture's line is as it was.
        let png = try CompareImages.decode(CompareFixtures.png(width: 480, height: 320, colour: gradient)).get()
        #expect(png.unit == .pixels && png.pages == nil && CompareRules.sizeLine(png) == "480 \u{00D7} 320 px")
    }

    @Test func anSVGIsDrawnOnWhiteAtItsOwnAspectAndStatedInPoints() throws {
        let svg = try CompareImages.decode(CompareFixtures.svg(width: 200, height: 100)).get()
        #expect(svg.unit == .points && svg.source == CGSize(width: 200, height: 100) && svg.pages == nil)
        #expect(svg.shown == CGSize(width: 3_072, height: 1_536))
        // Its transparent top on white, as the Shelf's cards show figures.
        let top = CompareFixtures.pixel(svg.image, x: 1_536, y: 300), bottom = CompareFixtures.pixel(svg.image, x: 1_536, y: 1_200)
        #expect(top.r > 245 && top.g > 245 && top.b > 245, "\(top)")
        #expect(bottom.b > 150 && bottom.r < 60, "\(bottom)")
        #expect(CompareRules.sizeLine(svg) == "200 \u{00D7} 100 pt")
        // Told by its bytes, not its name, with a byte order mark or space before it.
        #expect(CompareImages.vector(Data("\u{FEFF}  <svg width=\"1\" height=\"1\"/>".utf8)) == .svg)
        #expect(CompareImages.vector(CompareFixtures.pdf(width: 10, height: 10)) == .pdf)
        #expect(CompareImages.vector(CompareFixtures.png(width: 4, height: 4, colour: gradient)) == nil)
        #expect(CompareImages.vector(Data("# Notes about <svg> files".utf8)) == nil)
    }

    @Test func aBrokenPDFOrSVGIsRefusedAsNotAFigure() {
        // A PDF's header and nothing that makes a page; a PDF cut short.
        #expect(CompareImages.decode(Data("%PDF-1.7\n%%EOF\n".utf8)) == .failure(.notAnImage))
        let whole = CompareFixtures.pdf(width: 400, height: 300)
        #expect(CompareImages.decode(whole.prefix(whole.count / 3)) == .failure(.notAnImage))
        // An SVG with no size, one cut off in its tag, and one that isn't XML at all.
        #expect(CompareImages.decode(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)) == .failure(.notAnImage))
        #expect(CompareImages.decode(Data("<svg width=\"200\" hei".utf8)) == .failure(.notAnImage))
        #expect(CompareImages.decode(Data("<svg>>>>< not xml".utf8)) == .failure(.notAnImage))
        // The side's sentence covers PDFs and SVGs.
        #expect(CompareProblem.notAPicture.sentence("z_prime_by_plate.pdf") == "\u{201C}z_prime_by_plate.pdf\u{201D} isn\u{2019}t a figure Capsid can read.")
    }

    @Test func wipeNeedsTheSameSizeCountedTheSameWay() throws {
        let pageA = try CompareImages.decode(CompareFixtures.pdf(width: 400, height: 300)).get()
        let pageB = try CompareImages.decode(CompareFixtures.pdf(width: 400, height: 300, pages: 2)).get()
        let svg = try CompareImages.decode(CompareFixtures.svg(width: 400, height: 300)).get()
        let png = try CompareImages.decode(CompareFixtures.png(width: 400, height: 300, colour: gradient)).get()
        // Two pages of one size, and a page and an SVG of it: Wipe.
        #expect(CompareRules.canWipe(pageA, pageB) && CompareRules.canWipe(pageA, svg))
        // A 400 × 300 px picture beside a 400 × 300 pt page: not one size, so no Wipe.
        #expect(!CompareRules.canWipe(pageA, png) && !CompareRules.canWipe(png, svg))
        #expect(CompareRules.canWipe(png, png) && !CompareRules.canWipe(png, nil))
    }

    // MARK: Geometry

    @Test func fitKeepsTheAspectAndCentresThePicture() {
        let image = CGSize(width: 400, height: 300), view = CGSize(width: 200, height: 200)
        #expect(CompareGeometry.fitScale(image: image, view: view) == 0.5)
        #expect(CompareGeometry.imageRect(image: image, view: view, viewport: .fit) == CGRect(x: 0, y: 25, width: 200, height: 150))
        // A centre asked for off the picture is held at the middle while it all fits.
        let off = CompareViewport(scale: 1, center: CGPoint(x: 0.9, y: 0.1))
        #expect(CompareGeometry.imageRect(image: image, view: view, viewport: off) == CGRect(x: 0, y: 25, width: 200, height: 150))
    }

    @Test func zoomKeepsThePointUnderTheAnchorAndPanStopsAtTheEdges() {
        let image = CGSize(width: 400, height: 300), view = CGSize(width: 200, height: 200)
        let anchor = CGPoint(x: 50, y: 80)
        let before = CompareGeometry.pixel(at: anchor, image: image, view: view, viewport: .fit)!
        let zoomed = CompareGeometry.zoomed(.fit, by: 4, at: anchor, image: image, view: view)
        #expect(zoomed.scale == 4)
        let after = CompareGeometry.pixel(at: anchor, image: image, view: view, viewport: zoomed)!
        #expect(abs(after.x - before.x) < 0.001 && abs(after.y - before.y) < 0.001)
        // Panned far past the left edge, the picture's left edge stops at the pane's.
        let panned = CompareGeometry.panned(zoomed, by: CGSize(width: 10_000, height: -10_000), image: image, view: view)
        let rect = CompareGeometry.imageRect(image: image, view: view, viewport: panned)
        #expect(abs(rect.minX) < 0.001 && abs(rect.maxY - view.height) < 0.001)
        // Zoom stays between Fit and 32 times it.
        #expect(CompareGeometry.zoomed(.fit, by: 0.1, at: nil, image: image, view: view).scale == 1)
        #expect(CompareGeometry.zoomed(.fit, by: 1_000, at: nil, image: image, view: view).scale == CompareViewport.maxScale)
    }

    @Test func linkedPanesShowTheSameFractionOfEachPictureAtTheSameZoomOfItsOwnFit() {
        // Two sizes and two shapes: the shared centre is the same fraction of each, clamped in each.
        let viewport = CompareViewport(scale: 3, center: CGPoint(x: 0.3, y: 0.6))
        let view = CGSize(width: 300, height: 260)
        for image in [CGSize(width: 400, height: 300), CGSize(width: 1_600, height: 1_200), CGSize(width: 500, height: 900)] {
            let rect = CompareGeometry.imageRect(image: image, view: view, viewport: viewport)
            #expect(abs(rect.width - image.width * CompareGeometry.fitScale(image: image, view: view) * 3) < 0.001)
            let middle = CompareGeometry.pixel(at: CGPoint(x: 150, y: 130), image: image, view: view, viewport: viewport)!
            let held = CompareGeometry.clamped(viewport, image: image, view: view).center
            #expect(abs(middle.x / image.width - held.x) < 0.001 && abs(middle.y / image.height - held.y) < 0.001)
        }
    }

    @Test func theWipeDividerStepsAndSaysItsValue() {
        #expect(CompareWipe.stepped(0.5, by: 1) == 0.55)
        #expect(abs(CompareWipe.stepped(0.5, by: -1, fine: true) - 0.49) < 1e-9)
        #expect(CompareWipe.stepped(0.98, by: 1) == 1)
        #expect(CompareWipe.stepped(0.02, by: -1) == 0)
        #expect(CompareWipe.percent(0.5) == "50%" && CompareWipe.percent(1.4) == "100%")
        #expect(CompareWipe.x(0.25, width: 400) == 100)
    }

    // MARK: The Text Changes column

    private func document(_ left: String, _ right: String) throws -> CompareTextDocument {
        guard case .changes(let lines) = try CompareDiff.compare(left, right) else { throw CancellationError() }
        return CompareTextDocument(lines: lines)
    }

    @Test func theColumnMarksEachChangedLineAndCountsTheChanges() throws {
        let made = try document("# Plate reader QC\nEleven plates pass.\nRepeat plate 7.\n",
                                "# Plate reader QC\nTwelve plates pass.\nRepeat plate 7.\nSeal it fresh.\n")
        #expect(made.text.string == "# Plate reader QC\nEleven plates pass.\nTwelve plates pass.\nRepeat plate 7.\nSeal it fresh.")
        #expect(made.marks.map(\.kind) == [.removed, .added, .added])
        #expect(made.added == 2 && made.removed == 1 && made.changes.count == 2)
        let string = made.text.string as NSString
        #expect(string.substring(with: made.changes[0]) == "Eleven plates pass.\nTwelve plates pass.\n")
        #expect(string.substring(with: made.changes[1]) == "Seal it fresh.")
        #expect(made.spoken[0] == "Change 1 of 2. Removed 1 line, added 1.")
        #expect(made.spoken[1] == "Change 2 of 2. Added 1 line.")
        #expect(CompareRules.summary(changes: 2, added: 2, removed: 1) == "2 changes \u{00B7} 2 lines added, 1 removed")
    }

    @Test func voiceOverHearsAddedAndRemovedAndACopyIsTheWordsAlone() throws {
        let made = try document("a\nold line\nc\n", "a\nnew line\nc\n")
        let view = CompareChangesView.makeTextView()
        view.textStorage?.setAttributedString(made.text)
        view.marks = made.marks
        let whole = NSRange(location: 0, length: (view.string as NSString).length)
        #expect(view.accessibilityString(for: whole) == "a\nRemoved, old line\nAdded, new line\nc")
        // A line alone, as VoiceOver reads by line.
        let second = (view.string as NSString).range(of: "new line")
        #expect(view.accessibilityString(for: second) == "Added, new line")
        // Copy: the words as written, no markers, no styles.
        view.setSelectedRange(whole)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("capsid-compare-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == "a\nold line\nnew line\nc")
        #expect(pasteboard.data(forType: .rtf) == nil)
    }
}
