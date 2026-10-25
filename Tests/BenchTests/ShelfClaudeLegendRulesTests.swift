// ShelfClaudeLegendRulesTests.swift — Claude's own legend for a shelved figure, the pure part (Kept/ShelfClaudeLegend.swift):
// which of an answer's files are legend files and in what order they are offered, which part of a legend file is for
// this figure, how long a legend may be and how the cut is said, what the card offers for the legend it shows, and the
// words of the pill. Nothing here touches a disk or a page; the made-up legend files are about made-up plates.
import Foundation
import Testing
@testable import Bench

private typealias Rules = ShelfClaudeLegendRules

private func file(_ name: String, v: String? = nil, size: Int? = 4_000) -> HistoryFile {
    HistoryFile(v: v ?? "v-\(name)", a: "a-\(name)", name: name, kind: ArtifactKind.classify(name: name, mime: nil), size: size)
}

private func names(_ candidates: [Rules.Candidate]) -> [String] { candidates.map(\.name) }

struct ShelfClaudeLegendCandidateTests {
    @Test func aFileSharingTheFiguresStemIsTheBestCandidate() {
        let found = Rules.candidates(among: [file("FIGURE_LEGENDS_final.md"), file("z_prime_by_plate.md")],
                                     forFigure: "z_prime_by_plate.png", version: "v-figure")
        #expect(names(found) == ["z_prime_by_plate.md", "FIGURE_LEGENDS_final.md"])
        #expect(found.map(\.match) == [.stem, .legend])
    }

    @Test func aStemIsComparedWithoutCase() {
        let found = Rules.candidates(among: [file("Z_Prime_By_Plate.TXT")], forFigure: "z_prime_by_plate.png", version: nil)
        #expect(names(found) == ["Z_Prime_By_Plate.TXT"])
    }

    @Test func legendInANameCountsInAnyCase() {
        let found = Rules.candidates(among: [file("Fig_Legends.TXT"), file("LEGENDS.md"), file("my-legend.markdown"), file("notes.md")],
                                     forFigure: "z_prime_by_plate.png", version: nil)
        #expect(names(found) == ["Fig_Legends.TXT", "LEGENDS.md", "my-legend.markdown"])
    }

    @Test func severalCandidatesAreOrderedStemThenALegendForThisFigureThenAPlainOneThenAnotherFigures() {
        let found = Rules.candidates(
            among: [file("fig1_legend.md"), file("FIGURE_LEGENDS_final.md"), file("fig2_legend.md"), file("fig2_zprime.md")],
            forFigure: "fig2_zprime.png", version: nil)
        #expect(names(found) == ["fig2_zprime.md", "fig2_legend.md", "FIGURE_LEGENDS_final.md", "fig1_legend.md"])
        #expect(found.map(\.match) == [.stem, .legendForThisFigure, .legend, .legendForAnotherFigure])
    }

    @Test func aLegendWhoseNameHasTheFiguresStemIsForThisFigure() {
        let found = Rules.candidates(among: [file("FIGURE_LEGENDS_final.md"), file("z_prime_by_plate_legend.md")],
                                     forFigure: "z_prime_by_plate.png", version: nil)
        #expect(names(found) == ["z_prime_by_plate_legend.md", "FIGURE_LEGENDS_final.md"])
    }

    @Test func theAnswersOrderBreaksTiesAndAtMostSixAreOffered() {
        let all = (1...9).map { file("legend_\($0 * 100).md") }
        let found = Rules.candidates(among: all, forFigure: "plate_map.png", version: nil)
        // All carry numbers that aren't the figure's (the figure has none): a legend for another figure; the answer's order stays.
        #expect(names(found) == (1...6).map { "legend_\($0 * 100).md" })
    }

    @Test func nothingIsOfferedWhenThereIsNoLegendFile() {
        #expect(Rules.candidates(among: [file("plate_map.png"), file("z_prime.csv"), file("analysis.py"), file("notes.md")],
                                 forFigure: "plate_map.png", version: nil).isEmpty)
        #expect(Rules.candidates(among: [], forFigure: "plate_map.png", version: nil).isEmpty)
    }

    @Test func filesThatAreNotProseAreIgnoredWhateverTheirNames() {
        let found = Rules.candidates(
            among: [file("legend.png"), file("figure_legends.docx"), file("legend.csv"), file("legend.py"), file("legend.json"),
                    file("legend.html"), file("legend.pdf"), file("legend"), file("z_prime.csv"), file("z_prime.png"), file("legend.md")],
            forFigure: "z_prime.png", version: nil)
        #expect(names(found) == ["legend.md"])
    }

    @Test func theFigureItselfAnEmptyFileABigOneAndARepeatedVersionAreLeftOut() {
        let found = Rules.candidates(
            among: [file("z_prime.md", v: "v-figure"), file("empty_legend.md", size: 0), file("huge_legend.md", size: Rules.sizeLimit + 1),
                    file("legend.md", v: "v-1"), file("legend copy.md", v: "v-1"), file("unknown_size_legend.md", size: nil)],
            forFigure: "z_prime.png", version: "v-figure")
        #expect(names(found) == ["legend.md", "unknown_size_legend.md"])
    }

    @Test func theNumbersInAFigureNameAreNotDatesVersionsOrBigRuns() {
        #expect(Rules.numbers(inFileName: "fig2_zprime") == [.init(n: 2, supplementary: false)])
        #expect(Rules.numbers(inFileName: "plate7_edge_2") == [.init(n: 7, supplementary: false), .init(n: 2, supplementary: false)])
        #expect(Rules.numbers(inFileName: "run_2026-10-22_umap").isEmpty)
        #expect(Rules.numbers(inFileName: "zprime_v2").isEmpty)
        #expect(Rules.numbers(inFileName: "img20261022").isEmpty)
        #expect(Rules.numbers(inFileName: "fig12") == [.init(n: 12, supplementary: false)])
        #expect(Rules.numbers(inFileName: "figS3_x") == [.init(n: 3, supplementary: true)])
        #expect(Rules.numbers(inFileName: "S4_map") == [.init(n: 4, supplementary: true)])
        #expect(Rules.numbers(inFileName: "supp_fig5") == [.init(n: 5, supplementary: true)])
    }

    @Test func aFigureReferenceIsFigureOrFigNumberAndNotAPanel() {
        #expect(Rules.figureReferences(in: "Figure 2") == [.init(n: 2, supplementary: false)])
        #expect(Rules.figureReferences(in: "Fig. 2: Edge effects") == [.init(n: 2, supplementary: false)])
        #expect(Rules.figureReferences(in: "Figure S2") == [.init(n: 2, supplementary: true)])
        #expect(Rules.figureReferences(in: "Supplementary Figure 2") == [.init(n: 2, supplementary: true)])
        #expect(Rules.figureReferences(in: "Figure 2A").isEmpty)
        #expect(Rules.figureReferences(in: "Figure 20") == [.init(n: 20, supplementary: false)])
        #expect(Rules.figureReferences(in: "Reconfiguring 2").isEmpty)
    }
}

struct ShelfClaudeLegendPartTests {
    /// A legend file with a section for each of three figures, under headings.
    private static let headings = """
        # Figure legends

        Made-up legends for a made-up assay.

        ## Figure 1

        **Plate map.** Eight plates, sixteen rows.

        ## Figure 2

        **Edge effects.** Wells in column 1 read low on every plate.

        ### Panel notes

        Panel B repeats panel A on plate 7.

        ## Figure 3

        **Recovery.** Spiked wells came back at 94%.
        """

    /// The same, as bold labels at the start of paragraphs.
    private static let labels = """
        Figure legends

        **Figure 1.** Plate map. Eight plates,
        sixteen rows.

        **Figure 2.** Edge effects. Wells in column 1
        read low on every plate.

        **(A)** Column 1. **(B)** Column 12.

        **Figure 3.** Recovery. Spiked wells came back at 94%.
        """

    @Test func aHeadingForFigure2IsPickedForFig2AndItsLabelIsLeftOutAsBareButItsPanelNotesStay() {
        let part = Rules.part(of: Self.headings, fromFile: "FIGURE_LEGENDS_final.md", forFigure: "fig2_edge_effects.png")
        #expect(part.scope == .section(label: "Figure 2"))
        #expect(part.text == """
            **Edge effects.** Wells in column 1 read low on every plate.

            ### Panel notes

            Panel B repeats panel A on plate 7.
            """)
        #expect(!part.cut)
    }

    @Test func aTitledHeadingOpensTheTextWithoutItsHashes() {
        let file = "## Figure 2: Edge effects\n\nWells in column 1 read low.\n\n## Figure 3: Recovery\n\nBack at 94%."
        let part = Rules.part(of: file, fromFile: "legends.md", forFigure: "fig2_edge.png")
        #expect(part.text == "Figure 2: Edge effects\n\nWells in column 1 read low.")
        #expect(part.scope == .section(label: "Figure 2: Edge effects"))
    }

    @Test func aBoldLabelIsPartOfTheSentenceAndTheSectionRunsToTheNextFigure() {
        let part = Rules.part(of: Self.labels, fromFile: "legends.md", forFigure: "fig2_edge_effects.png")
        #expect(part.scope == .section(label: "Figure 2"))
        // The panel line opens with a bold "(A)", which doesn't open a figure: it is inside the section.
        #expect(part.text == "**Figure 2.** Edge effects. Wells in column 1\nread low on every plate.\n\n**(A)** Column 1. **(B)** Column 12.")
    }

    @Test func theFileNameIsTheBestWayToNameAFigureThenItsStemThenItsNumber() {
        let file = """
            ## Figure 2

            By number.

            ## z_prime_by_plate

            By stem.

            ## `z_prime_by_plate.png`

            By file name.

            ## Figure 9

            Other.
            """
        let figure = "z_prime_by_plate.png"
        #expect(Rules.part(of: file, fromFile: "l.md", forFigure: figure).text == "By file name.")
        let withoutName = file.replacingOccurrences(of: "## `z_prime_by_plate.png`\n\nBy file name.\n\n", with: "")
        #expect(Rules.part(of: withoutName, fromFile: "l.md", forFigure: figure).text == "By stem.")
        // A figure with the number 2 in its name and no other way to be named: the number.
        #expect(Rules.part(of: withoutName, fromFile: "l.md", forFigure: "run2_by_plate.png").text == "By number.")
    }

    @Test func aFigureReferenceMatchesOnlyItsOwnNumber() {
        // Each of these has one section that a loose reading of "2" would take, and none that is Figure 2.
        for other in ["Figure 12", "Figure 20", "Figure 2A", "Figure 200", "Figure 22"] {
            let file = "## \(other)\n\nNot this one.\n\n## Figure 3\n\nThird."
            let part = Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_edge.png")
            #expect(part.scope == .whole && part.text == file, "\(other)")
        }
        // Panels of the figure are not the figure.
        let panels = "## Figure 2A\n\nPanel A.\n\n## Figure 2B\n\nPanel B."
        #expect(Rules.part(of: panels, fromFile: "l.md", forFigure: "fig2_edge.png").scope == .whole)
        // And its own number is found among others, in any case.
        let among = "## FIGURE 12\n\nTwelve.\n\n## fig. 2\n\nTwo.\n\n## Figure 20\n\nTwenty."
        #expect(Rules.part(of: among, fromFile: "l.md", forFigure: "fig2_edge.png").text == "Two.")
    }

    @Test func aSupplementaryFigureAndAMainOneWithTheSameNumberAreTold() {
        let file = "## Supplementary Figure 2\n\nSupplementary.\n\n## Figure 2\n\nMain."
        #expect(Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_a.png").text == "Main.")
        #expect(Rules.part(of: file, fromFile: "l.md", forFigure: "figS2_a.png").text == "Supplementary.")
    }

    @Test func twoSectionsEquallyPlainMeanNoneIsAndTheWholeFileIsUsed() {
        let file = "## Figure 2\n\nFirst.\n\n## Figure 3\n\nThird.\n\n## Figure 2\n\nAgain."
        let part = Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_a.png")
        #expect(part.scope == .whole && part.text == file)
    }

    @Test func aLabelInsideTheSectionItNamesIsTheSameSection() {
        let file = "## Figure 2\n\n**Figure 2.** Edge effects.\n\nMore.\n\n## Figure 3\n\nThird."
        let part = Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_a.png")
        #expect(part.scope == .section(label: "Figure 2"))
        #expect(part.text == "**Figure 2.** Edge effects.\n\nMore.")
    }

    @Test func aFileWithNoSectionForTheFigureIsUsedWhole() {
        let file = "Plate 7 reads low because of the edge.\n\nSeen on every plate."
        let part = Rules.part(of: file, fromFile: "plate_map_legend.md", forFigure: "plate_map.png")
        #expect(part.scope == .whole && part.text == file && !part.cut)
        // A figure with no number in its name finds no "Figure N" section either.
        let numbered = Rules.part(of: Self.headings, fromFile: "l.md", forFigure: "plate_map.png")
        #expect(numbered.scope == .whole)
    }

    @Test func aHeadingInsideACodeFenceIsNotAHeading() {
        let file = "Notes.\n\n```\n## Figure 2\nnot a section\n```\n\nEnd."
        #expect(Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_a.png").scope == .whole)
    }

    @Test func windowsLineEndsAndAByteOrderMarkAreTakenOff() {
        let file = "\u{FEFF}## Figure 2\r\n\r\nWells read low.\r\nEvery plate.\r\n\r\n## Figure 3\r\n\r\nThird.\r\n"
        let part = Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_a.png")
        #expect(part.text == "Wells read low.\nEvery plate.")
        let whole = Rules.part(of: "\u{FEFF}One.\r\nTwo.\r\n", fromFile: "l.md", forFigure: "plate_map.png")
        #expect(whole.text == "One.\nTwo.")
    }

    @Test func aLongFileIsCutAtAParagraphAtTheCapAndTheCutIsSaidInTheText() {
        let paragraph = String(repeating: "Wells in column 1 read low on every plate. ", count: 9).trimmingCharacters(in: .whitespaces)
        let file = (1...30).map { _ in paragraph }.joined(separator: "\n\n")
        #expect(file.count > Rules.cap)
        let part = Rules.part(of: file, fromFile: "FIGURE_LEGENDS_final.md", forFigure: "plate_map.png")
        #expect(part.cut && part.scope == .whole)
        #expect(part.text.hasSuffix("\n\n[Cut here: the rest is in FIGURE_LEGENDS_final.md.]"))
        let kept = part.text.replacingOccurrences(of: "\n\n[Cut here: the rest is in FIGURE_LEGENDS_final.md.]", with: "")
        #expect(kept.count <= Rules.cap && kept.count > Rules.cap / 2)
        // Whole paragraphs only.
        #expect(kept.components(separatedBy: "\n\n").allSatisfy { $0 == paragraph })
    }

    @Test func aLongSectionIsCutToo() {
        let body = String(repeating: "Spiked wells came back. ", count: 400)
        let file = "## Figure 1\n\nShort.\n\n## Figure 2\n\n" + body + "\n\n## Figure 3\n\nThird."
        let part = Rules.part(of: file, fromFile: "l.md", forFigure: "fig2_a.png")
        #expect(part.cut && part.scope == .section(label: "Figure 2"))
        #expect(part.text.count <= Rules.cap + 60)
        #expect(part.text.hasSuffix(Rules.cutNote("l.md")))
    }

    @Test func aTextExactlyAtTheCapIsNotCut() {
        let text = String(repeating: "a", count: Rules.cap)
        let part = Rules.part(of: text, fromFile: "l.md", forFigure: "plate_map.png")
        #expect(!part.cut && part.text == text)
        #expect(Rules.part(of: text + "a", fromFile: "l.md", forFigure: "plate_map.png").cut)
    }

    @Test func aLegendWithOneLongWordIsCutWithinTheCap() {
        let text = String(repeating: "a", count: Rules.cap + 500)
        let part = Rules.part(of: text, fromFile: "l.md", forFigure: "plate_map.png")
        #expect(part.cut)
        #expect(part.text.hasPrefix(String(repeating: "a", count: Rules.cap)))
    }
}

struct ShelfClaudeLegendOfferTests {
    private let one = [Rules.Candidate(file: file("FIGURE_LEGENDS_final.md"), match: .legend)]
    private let several = [Rules.Candidate(file: file("fig2_zprime.md"), match: .stem),
                           Rules.Candidate(file: file("FIGURE_LEGENDS_final.md"), match: .legend)]

    @Test func anEmptyLegendIsOfferedClaudesWithoutAsking() {
        for legend in ["", "  \n "] {
            let offer = Rules.offer(candidates: one, legend: legend, applied: nil)
            #expect(offer == .use(one))
            #expect(offer?.title == "Use Claude\u{2019}s legend" && offer?.asksFirst == false)
        }
    }

    @Test func aWrittenLegendIsOfferedReplacingAndAsksFirst() {
        let offer = Rules.offer(candidates: one, legend: "Z\u{2032} per plate; plate 7 re-run.", applied: nil)
        #expect(offer == .replace(one))
        #expect(offer?.title == "Replace with Claude\u{2019}s legend\u{2026}" && offer?.asksFirst == true)
    }

    @Test func severalCandidatesAreAllInTheOfferBestFirst() {
        #expect(Rules.offer(candidates: several, legend: "", applied: nil)?.candidates.map(\.name) == ["fig2_zprime.md", "FIGURE_LEGENDS_final.md"])
        #expect(Rules.offer(candidates: several, legend: "Mine.", applied: nil)?.candidates.count == 2)
    }

    @Test func noCandidateIsNoOffer() {
        #expect(Rules.offer(candidates: [], legend: "", applied: nil) == nil)
        #expect(Rules.offer(candidates: [], legend: "Mine.", applied: nil) == nil)
    }

    @Test func theOfferWaitsWhileTheLegendIsExactlyWhatClaudesPutIn() {
        #expect(Rules.offer(candidates: one, legend: "Claude says.", applied: "Claude says.") == nil)
        // Edited since: a written legend again.
        #expect(Rules.offer(candidates: one, legend: "Claude says, and I add.", applied: "Claude says.") == .replace(one))
        // Taken back to empty: the offer is back.
        #expect(Rules.offer(candidates: one, legend: "", applied: "Claude says.") == .use(one))
    }
}

struct ShelfClaudeLegendSentenceTests {
    private let section = Rules.Part(text: "x", scope: .section(label: "Figure 2"), cut: false)
    private let whole = Rules.Part(text: "x", scope: .whole, cut: false)

    @Test func theSentenceSaysWhichPartAndFromWhichFile() {
        #expect(Rules.putIn(section, file: "FIGURE_LEGENDS_final.md", figure: "fig2_edge.png", filing: .alreadyThere)
                == "Put in Claude\u{2019}s legend for \u{201C}Figure 2\u{201D} from FIGURE_LEGENDS_final.md.")
        #expect(Rules.putIn(whole, file: "FIGURE_LEGENDS_final.md", figure: "fig2_edge.png", filing: .alreadyThere)
                == "Put in all of FIGURE_LEGENDS_final.md, which has no section for fig2_edge.png.")
    }

    @Test func aCutIsSaidWithTheCap() {
        let cut = Rules.Part(text: "x", scope: .whole, cut: true)
        #expect(Rules.putIn(cut, file: "l.md", figure: "a.png", filing: .alreadyThere)
                == "Put in the first 3,000 characters of l.md, which has no section for a.png.")
        let cutSection = Rules.Part(text: "x", scope: .section(label: "Figure 2"), cut: true)
        #expect(Rules.putIn(cutSection, file: "l.md", figure: "a.png", filing: .alreadyThere).hasPrefix("Put in the first 3,000 characters of Claude"))
    }

    @Test func theFilesFateIsSaidAfterIt() {
        #expect(Rules.putIn(section, file: "l.md", figure: "a.png", filing: .copied).hasSuffix(" The file is beside the figure."))
        #expect(Rules.putIn(section, file: "l.md", figure: "a.png", filing: .notCopied("There isn\u{2019}t room on this disk."))
            .hasSuffix(" The file itself wasn\u{2019}t copied: There isn\u{2019}t room on this disk."))
    }

    @Test func aLongFigureNameIsShortened() {
        let name = String(repeating: "x", count: 40) + ".png"
        #expect(Rules.putIn(whole, file: "l.md", figure: name, filing: .alreadyThere).contains(String(repeating: "x", count: 31) + "\u{2026}"))
    }

    @Test func aFailureAlwaysSaysNothingWasChanged() {
        #expect(Rules.notChanged(Rules.gone("l.md")) == "Couldn\u{2019}t put Claude\u{2019}s legend in. l.md isn\u{2019}t in Claude Science any more. Nothing was changed.")
    }
}

struct ShelfClaudeLegendAnswerFilesTests {
    private func page(_ items: [HistoryItem], from: Int = 0) -> HistoryPage {
        HistoryPage(total: (items.last?.index ?? 0) + 1, from: from, items: items)
    }

    @Test func theFilesOfTheAnswerAroundARowAreTheOnesThatAreNotPicturesLessTheHiddenOnes() {
        let items: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Plot Z\u{2032}.", cut: false, files: []),
            .turn(i: 1, role: .claude, at: nil, text: "Here it is.", cut: false,
                  files: [file("fig2_zprime.png"), file("FIGURE_LEGENDS_final.md"), file("plan_1.json"), file("z_prime.csv")]),
            .turn(i: 2, role: .you, at: nil, text: "Now plate 7.", cut: false, files: []),
            .turn(i: 3, role: .claude, at: nil, text: "Done.", cut: false, files: [file("plate7_legend.md")]),
        ]
        let first = Rules.files(ofAnswerAtRow: 1, in: page(items))
        #expect(first.map(\.name) == ["FIGURE_LEGENDS_final.md", "z_prime.csv"])
        // Another row, another answer.
        #expect(Rules.files(ofAnswerAtRow: 3, in: page(items)).map(\.name) == ["plate7_legend.md"])
    }

    @Test func aReplysFilesSitUnderItsLastMessageAndStillBelongToARowBeforeIt() {
        let items: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Plot Z\u{2032}.", cut: false, files: []),
            .turn(i: 1, role: .claude, at: nil, text: "Working.", cut: false, files: []),
            .steps(i: 2, line: "Ran a command", failed: false, files: []),
            .turn(i: 4, role: .claude, at: nil, text: "Here it is.", cut: false, files: [file("legend.md")]),
        ]
        #expect(Rules.files(ofAnswerAtRow: 1, in: page(items)).map(\.name) == ["legend.md"])
    }

    @Test func aRowThePageDoesNotHoldHasNoFiles() {
        let items: [HistoryItem] = [
            .turn(i: 10, role: .you, at: nil, text: "Plot.", cut: false, files: []),
            .turn(i: 11, role: .claude, at: nil, text: "Done.", cut: false, files: [file("legend.md")]),
        ]
        #expect(Rules.files(ofAnswerAtRow: 3, in: page(items, from: 10)).isEmpty)
    }
}
