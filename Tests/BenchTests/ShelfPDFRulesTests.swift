// ShelfPDFRulesTests.swift — what goes on each page of the lab-meeting PDF
// (Kept/ShelfPDFRules.swift), pure, on made-up items: the title and where it
// falls back to, which legend a page has (the person's own, else Claude's
// first sentences kept short, else none), the line that says where a figure
// came from, which picture stands for each kind of file, the PDF's name, and
// the page's geometry: its shape, its margins, and the biggest a figure can
// be without being stretched.
import CoreGraphics
import Foundation
import Testing
@testable import Bench

private let zone = TimeZone(secondsFromGMT: -4 * 3600)!
private let english = Locale(identifier: "en_US")
private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// 22 October 2026, 9:12 in the zone four hours behind UTC.
private let now = Date(timeIntervalSince1970: 1_792_674_720)

private func item(_ file: String = "z_prime_by_plate.png", name: String? = nil, session: String = "Plate reader QC",
                  project: String = "Assay development", legend: String = "", said: String = "Plate 7 is the low bar.",
                  isLast: Bool = false, keptAt: Date = now, answerAt: Date? = nil, bytes: Int = 83_456) -> ShelfItem {
    let stem = (file as NSString).deletingPathExtension
    let record = KeptRecord(
        name: name ?? stem, keptAt: keptAt, projectID: "p", projectName: project, sessionID: "s", sessionTitle: session,
        figure: KeptFile(path: file, role: .figure, artifact: "a", version: "v-1", index: 3, of: nil, sha256: nil, bytes: bytes),
        files: [], missing: [], claudeScience: "0.1.70", capsid: "1.0", sourceRow: 12, question: nil, answerAt: answerAt)
    let attribution = isLast ? "From Claude\u{2019}s last answer in the session." : "From Claude\u{2019}s answer."
    let result = KeptResult(folder: URL(fileURLWithPath: "/tmp/kept/\(project)/\(stem)", isDirectory: true), collection: project,
                            record: record, text: KeptText(legend: legend, claudeSaid: said, attribution: attribution, origin: ""))
    return ShelfRules.items(from: [result])[0]
}

struct ShelfPDFWordsTests {
    @Test func theTitleIsTheFilesNameUnlessTheKeepHasOneOfItsOwn() {
        #expect(ShelfPDFRules.words(for: item("z_prime_by_plate.png")).title == "z_prime_by_plate.png")
        #expect(ShelfPDFRules.words(for: item("z_prime.png", name: "Fig 2B \u{00B7} Z\u{2032} by plate")).title == "Fig 2B \u{00B7} Z\u{2032} by plate")
    }

    @Test func aLegendThatOpensWithATitleLendsItToThePageWhenTheKeepHasNoName() {
        let marked = item(legend: "## Z\u{2032} by plate\n\nZ\u{2032} for each of 12 plates; plate 7 was excluded.")
        #expect(ShelfPDFRules.words(for: marked).title == "Z\u{2032} by plate")
        #expect(ShelfPDFRules.words(for: marked).legend == "Z\u{2032} for each of 12 plates; plate 7 was excluded.")
        // A short line of its own, with more under it, is a title too.
        let plain = item(legend: "Z\u{2032} by plate\n\nOne bar for each of 12 plates.")
        #expect(ShelfPDFRules.words(for: plain).title == "Z\u{2032} by plate")
        #expect(ShelfPDFRules.words(for: plain).legend == "One bar for each of 12 plates.")
        // A sentence is not a title, nor is a line with nothing under it.
        let sentence = item(legend: "Z\u{2032} for each plate.\n\nPlate 7 was excluded.")
        #expect(ShelfPDFRules.words(for: sentence).title == "z_prime_by_plate.png")
        #expect(ShelfPDFRules.words(for: sentence).legend == "Z\u{2032} for each plate. Plate 7 was excluded.")
        let lone = item(legend: "Z\u{2032} by plate")
        #expect(ShelfPDFRules.words(for: lone).title == "z_prime_by_plate.png")
        #expect(ShelfPDFRules.words(for: lone).legend == "Z\u{2032} by plate")
        // The keep's own name wins, and the legend keeps all its words.
        let named = item(name: "Fig 2B", legend: "## Z\u{2032} by plate\n\nOne bar for each plate.")
        #expect(ShelfPDFRules.words(for: named).title == "Fig 2B")
        #expect(ShelfPDFRules.words(for: named).legend == "Z\u{2032} by plate One bar for each plate.")
    }

    @Test func theLegendIsTheUsersOwnWhenThereIsOne() {
        let words = ShelfPDFRules.words(for: item(legend: "Z\u{2032} for 12 plates.\nPlate 7 was **excluded**.", said: "Claude's words."))
        #expect(words.legend == "Z\u{2032} for 12 plates. Plate 7 was excluded.")
    }

    @Test func withoutOneItIsTheFirstSentencesOfWhatClaudeSaid() {
        let said = "Plate 7 is the low bar, at 0.41 against a cutoff of 0.5. The other eleven sit between 0.62 and 0.78. A third sentence that runs on long enough to take it past the limit and out of the legend altogether, so it never gets in."
        let words = ShelfPDFRules.words(for: item(said: said))
        #expect(words.legend == "Plate 7 is the low bar, at 0.41 against a cutoff of 0.5. The other eleven sit between 0.62 and 0.78.")
        #expect(words.legend.count <= ShelfPDFRules.claudeLimit)
    }

    @Test func claudesWordsLoseTheirMarksCodeTablesAndRules() {
        let said = """
        ## Result

        **Plate 7** is the low bar, see [the table](x).

        ```python
        print("not this")
        ```

        | plate | z |
        |---|---|
        | 7 | 0.41 |

        ---
        - the other eleven pass
        """
        #expect(ShelfPDFRules.shortWords(said) == "Plate 7 is the low bar, see the table. the other eleven pass")
    }

    @Test func aLongFirstSentenceIsCutAtAWordWithAnEllipsis() {
        let said = String(repeating: "plate ", count: 80)
        let cut = ShelfPDFRules.shortWords(said)
        #expect(cut.count <= ShelfPDFRules.claudeLimit)
        #expect(cut.hasSuffix("\u{2026}"))
        #expect(!cut.dropLast().hasSuffix(" "))
        #expect(ShelfPDFRules.shortWords("Short and whole.") == "Short and whole.")
        #expect(ShelfPDFRules.shortWords("") == "")
    }

    @Test func theUsersLegendIsCutOnlyPastSixHundredCharacters() {
        let long = String(repeating: "A bar for each plate. ", count: 40)
        let words = ShelfPDFRules.words(for: item(legend: long))
        #expect(words.legend.count <= ShelfPDFRules.legendLimit)
        #expect(words.legend.hasSuffix("."))
        let middle = String(repeating: "word ", count: 100)
        #expect(ShelfPDFRules.cut(middle, to: 100).hasSuffix("\u{2026}"))
        #expect(ShelfPDFRules.cut("whole", to: 100) == "whole")
    }

    @Test func claudesLastAnswerIsNotALegendForAFigureItDoesNotShow() {
        let stand = item(said: "Something about the whole session.", isLast: true)
        #expect(ShelfPDFRules.words(for: stand).legend == "")
        // The person's own legend is still theirs.
        #expect(ShelfPDFRules.words(for: item(legend: "Mine.", said: "Claude's.", isLast: true)).legend == "Mine.")
        #expect(ShelfPDFRules.words(for: item(said: "")).legend == "")
    }
}

struct ShelfPDFSourceTests {
    @Test func theSourceLineSaysTheSessionTheProjectAndTheDay() {
        let line = ShelfPDFRules.sourceLine(for: item(), locale: english, calendar: calendar)
        #expect(line == "Plate reader QC \u{00B7} Assay development \u{00B7} 22 Oct 2026")
    }

    @Test func theDayIsWhenClaudeAnsweredElseWhenItWentOnTheShelf() {
        let answered = now.addingTimeInterval(-3 * 86_400)
        #expect(ShelfPDFRules.sourceLine(for: item(answerAt: answered), locale: english, calendar: calendar).hasSuffix("19 Oct 2026"))
        #expect(ShelfPDFRules.sourceLine(for: item(keptAt: answered), locale: english, calendar: calendar).hasSuffix("19 Oct 2026"))
    }

    @Test func whatIsEmptyIsLeftOut() {
        #expect(ShelfPDFRules.sourceLine(for: item(project: ""), locale: english, calendar: calendar) == "Plate reader QC \u{00B7} 22 Oct 2026")
        #expect(ShelfPDFRules.sourceLine(for: item(session: " ", project: ""), locale: english, calendar: calendar) == "22 Oct 2026")
    }

    @Test func theDayKeepsItsOrderWhateverTheRegion() {
        #expect(ShelfPDFRules.day(now, locale: Locale(identifier: "en_GB"), calendar: calendar) == "22 Oct 2026")
        #expect(ShelfPDFRules.day(now, locale: Locale(identifier: "en_US"), calendar: calendar) == "22 Oct 2026")
        // The day in the Mac's zone, not UTC's: 22:30 here is still the 22nd (it is the 23rd in UTC), and past midnight here is the 23rd.
        #expect(ShelfPDFRules.day(now.addingTimeInterval(13 * 3_600 + 18 * 60), locale: english, calendar: calendar) == "22 Oct 2026")
        #expect(ShelfPDFRules.day(now.addingTimeInterval(15 * 3_600), locale: english, calendar: calendar) == "23 Oct 2026")
    }
}

struct ShelfPDFFileTests {
    @Test func thePDFIsNamedForTheDay() {
        #expect(ShelfPDFRules.fileName(on: now, calendar: calendar) == "Lab meeting 2026-10-22.pdf")
        let early = Date(timeIntervalSince1970: 1_767_225_600 + 3_600)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(ShelfPDFRules.fileName(on: early, calendar: utc) == "Lab meeting 2026-01-01.pdf")
        // The digits are the same in any calendar the Mac is set to.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = zone
        #expect(ShelfPDFRules.fileName(on: now, calendar: buddhist) == "Lab meeting 2026-10-22.pdf")
    }

    @Test func theSentencesAreOneEachInSolanumsVoice() {
        #expect(ShelfPDFRules.couldntRead("z.png") == "Couldn\u{2019}t read z.png, which may have been moved out of the Shelf folder.")
        #expect(ShelfPDFRules.couldntSave(in: "Downloads") == "Couldn\u{2019}t save the PDF to Downloads, which may be read-only or full.")
        for sentence in [ShelfPDFRules.couldntRead("z.png"), ShelfPDFRules.couldntSave(in: "Downloads"), ShelfPDFRules.nothingChosen] {
            #expect(!sentence.contains("!"))
            // One sentence: it ends with its only full stop.
            #expect(sentence.hasSuffix(".") && !sentence.dropLast().contains(". "), "\(sentence)")
        }
    }
}

struct ShelfPDFPictureTests {
    @Test func aPictureIsDrawnFromItsFileAndAPDFFromItsFirstPage() {
        #expect(ShelfPDFRules.picture(for: item("z.png"), text: nil) == .image(URL(fileURLWithPath: "/tmp/kept/Assay development/z/z.png")))
        #expect(ShelfPDFRules.picture(for: item("scan.JPG"), text: nil) == .image(URL(fileURLWithPath: "/tmp/kept/Assay development/scan/scan.JPG")))
        #expect(ShelfPDFRules.picture(for: item("diagram.svg"), text: nil) == .image(URL(fileURLWithPath: "/tmp/kept/Assay development/diagram/diagram.svg")))
        #expect(ShelfPDFRules.picture(for: item("report.pdf"), text: nil) == .pdf(URL(fileURLWithPath: "/tmp/kept/Assay development/report/report.pdf")))
    }

    @Test func markdownIsPlainTextAndEverythingElseATile() {
        #expect(ShelfPDFRules.picture(for: item("notes.md"), text: "# Plate reader QC\n\nEleven plates pass.")
                == .text([.heading("Plate reader QC"), .paragraph("Eleven plates pass.")]))
        // A note that hasn't been read, or is empty, is a tile; so is a table, a script, a workbook.
        #expect(ShelfPDFRules.picture(for: item("notes.md"), text: nil) == .tile)
        #expect(ShelfPDFRules.picture(for: item("notes.md"), text: "\n\n") == .tile)
        #expect(ShelfPDFRules.picture(for: item("plates.csv"), text: "plate,z\n1,0.8") == .tile)
        #expect(ShelfPDFRules.picture(for: item("receptors.xlsx"), text: nil) == .tile)
        #expect(ShelfPDFRules.picture(for: item("plot.py"), text: "import x") == .tile)
        #expect(ShelfPDFRules.picture(for: item("page.html"), text: "<p>x</p>") == .tile)
    }

    @Test func aTileSaysTheKindAndTheSize() {
        let table = ShelfPDFRules.tile(for: item("plates.csv", bytes: 4_096))
        #expect(table.label == "CSV")
        #expect(table.detail == "Table \u{00B7} \(ByteCountFormatter.string(fromByteCount: 4_096, countStyle: .file))")
        #expect(ShelfPDFRules.tile(for: item("receptors.xlsx", bytes: 2_000_000)).detail.hasPrefix("Table \u{00B7} 2"))
        #expect(ShelfPDFRules.tile(for: item("notes.docx")).detail.hasPrefix("Document \u{00B7} "))
        #expect(ShelfPDFRules.tile(for: item("README")).label == "FILE")
        #expect(ShelfPDFRules.tile(for: item("archive.longext")).label == "FILE")
    }

    @Test func aPageHoldsOneFileAndEveryItemGetsOne() {
        let items = [item("a.png"), item("b.md"), item("c.csv")]
        let pages = ShelfPDFRules.pages(for: items, text: [items[1].id: "# B"], locale: english, calendar: calendar)
        #expect(pages.map(\.fileName) == ["a.png", "b.md", "c.csv"])
        #expect(pages.map(\.title) == ["a.png", "b.md", "c.csv"])
        if case .text(let blocks) = pages[1].picture { #expect(blocks == [.heading("B")]) } else { Issue.record("not text") }
        #expect(ShelfPDFRules.pages(for: [], locale: english, calendar: calendar).isEmpty)
    }
}

struct ShelfPDFBlocksTests {
    @Test func markdownBecomesHeadingsParagraphsAndBulletsWithoutItsMarks() {
        let text = """
        ---
        title: hidden front matter
        ---
        # Plate reader QC, **21 October**

        Eleven plates pass with Z\u{2032} between 0.62
        and 0.78. See [the table](plates.csv).

        ## Next
        - repeat plate 7
        2. with a fresh seal
        """
        #expect(ShelfPDFRules.blocks(fromText: text) == [
            .heading("Plate reader QC, 21 October"),
            .paragraph("Eleven plates pass with Z\u{2032} between 0.62 and 0.78. See the table."),
            .heading("Next"),
            .bullet("repeat plate 7"),
            .bullet("with a fresh seal"),
        ])
    }

    @Test func codeTablesCommentsAndRulesAreLeftOut() {
        let text = "Before.\n```\ncode\n```\n| a | b |\n<!-- note -->\n***\nAfter."
        #expect(ShelfPDFRules.blocks(fromText: text) == [.paragraph("Before."), .paragraph("After.")])
        #expect(ShelfPDFRules.blocks(fromText: "").isEmpty)
        #expect(ShelfPDFRules.blocks(fromText: String(repeating: "Line.\n\n", count: 100)).count == 40)
    }
}

struct ShelfPDFLayoutTests {
    private let layout = ShelfPDFLayout.self

    @Test func theSheetIsSixteenByNineAndIsProjectedSoItsMarginsAreEven() {
        #expect(layout.page == CGSize(width: 960, height: 540))
        #expect(abs(layout.aspect - 16.0 / 9.0) < 0.0001)
        #expect(layout.contentWidth == layout.page.width - 2 * layout.marginX)
        let regions = layout.regions(titleHeight: 26, legendHeight: 63)
        #expect(regions.title.minX == layout.marginX && regions.title.maxX == layout.page.width - layout.marginX)
        #expect(regions.figure.minX == regions.title.minX && regions.figure.maxX == regions.title.maxX)
        #expect(regions.title.minY == layout.marginTop)
        #expect(regions.footer.maxY == layout.page.height - layout.marginBottom)
    }

    @Test func theRegionsStackInOrderWithoutOverlapAndTheFigureTakesWhatIsLeft() {
        let regions = layout.regions(titleHeight: 26, legendHeight: 63)
        #expect(regions.title.maxY <= regions.legend.minY)
        #expect(regions.legend.maxY + layout.gapAbove == regions.figure.minY)
        #expect(regions.figure.maxY + layout.gapBelow == regions.footer.minY)
        #expect(regions.figure.height > 0)
        // The legend's width is a comfortable measure, not the page's.
        #expect(regions.legend.width == layout.legendWidth && regions.legend.width < regions.title.width)
        // No legend, more room; a taller legend, less.
        let bare = layout.regions(titleHeight: 26, legendHeight: 0)
        let long = layout.regions(titleHeight: 26, legendHeight: 63)
        #expect(bare.figure.height > long.figure.height)
        #expect(bare.legend.height == 0 && bare.legend.minY == bare.title.maxY)
        // Even the longest legend and the tallest title leave a figure.
        let most = layout.regions(titleHeight: layout.titleHeight(for: layout.titleMax),
                                  legendHeight: CGFloat(layout.legendLines) * layout.legendLeading)
        #expect(most.figure.height > 250)
        #expect(most.figure.maxY <= layout.page.height)
    }

    @Test func aPictureFillsTheBoxOnTheTightSideKeepsItsShapeAndIsCentred() {
        let box = CGRect(x: 56, y: 140, width: 848, height: 340)
        let wide = layout.fit(CGSize(width: 3000, height: 1000), in: box)
        #expect(wide.width == 848 && abs(wide.height - 848.0 / 3) < 0.001)
        #expect(abs(wide.midX - box.midX) < 0.001 && abs(wide.midY - box.midY) < 0.001)
        let tall = layout.fit(CGSize(width: 1000, height: 2000), in: box)
        #expect(tall.height == 340 && tall.width == 170)
        #expect(abs(tall.midX - box.midX) < 0.001)
        for size in [CGSize(width: 1600, height: 1000), CGSize(width: 480, height: 320), CGSize(width: 7, height: 900), CGSize(width: 900, height: 7)] {
            let placed = layout.fit(size, in: box)
            #expect(abs(placed.width / placed.height - size.width / size.height) < 0.0001, "\(size)")
            #expect(box.insetBy(dx: -0.001, dy: -0.001).contains(placed), "\(size)")
        }
    }

    @Test func aPictureIsNeverDrawnBiggerThanItsOwnPixelsOneToAPoint() {
        let box = CGRect(x: 56, y: 140, width: 848, height: 340)
        let small = layout.fit(CGSize(width: 480, height: 320), in: box, maxScale: layout.maxPointsPerPixel)
        #expect(small.size == CGSize(width: 480, height: 320))
        #expect(abs(small.midX - box.midX) < 0.001 && abs(small.midY - box.midY) < 0.001)
        // Bigger than the room, it comes down to fit; the cap never makes anything larger.
        let big = layout.fit(CGSize(width: 2400, height: 1600), in: box, maxScale: layout.maxPointsPerPixel)
        #expect(abs(big.height - 340) < 0.001 && abs(big.width - 510) < 0.001)
        // A vector has no pixels: it takes the room.
        let vector = layout.fit(CGSize(width: 480, height: 320), in: box)
        #expect(abs(vector.height - 340) < 0.001)
    }

    @Test func nothingIsDrawnInNoRoomOrWithNoSize() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(layout.fit(.zero, in: box).size == .zero)
        #expect(layout.fit(CGSize(width: 10, height: 0), in: box).size == .zero)
        #expect(layout.fit(CGSize(width: 10, height: 10), in: .zero).size == .zero)
    }

    @Test func theTitleIsTwentyPointsAndShrinksToFourteenBeforeItIsCut() {
        // A measure that grows with the size and the length: half a size a character.
        let measure: (String, CGFloat) -> CGFloat = { text, size in CGFloat(text.count) * size * 0.5 }
        #expect(layout.titleSize(for: "Plate 7", width: 848, measure: measure) == 20)
        // 60 characters at 20 points is 600; 100 is 1000, too wide until 16.
        #expect(layout.titleSize(for: String(repeating: "x", count: 60), width: 848, measure: measure) == 20)
        #expect(layout.titleSize(for: String(repeating: "x", count: 100), width: 848, measure: measure) == 16)
        #expect(layout.titleSize(for: String(repeating: "x", count: 500), width: 848, measure: measure) == 14)
        #expect(layout.titleHeight(for: 20) == 26 && layout.titleHeight(for: 14) == 19)
    }
}
