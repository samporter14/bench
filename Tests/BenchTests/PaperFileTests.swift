// PaperFileTests.swift — PAPER.md and the rules for a paper, on made-up panels:
// what the renderer writes (the contract's own example, to the byte), that what
// it writes is read back as it was (render, parse, render: the same bytes, with
// names in every script), that the parser refuses anything the renderer didn't
// write, that a byte order mark and Windows line ends do not hide a paper, and
// the labels, their order, the gaps, the changes and the words of `PaperRules`.
// Nothing here touches the disk.
import Foundation
import Testing
@testable import Bench

// MARK: Made-up papers

/// 30 October 2026, 9:12 in the zone four hours behind UTC.
private let createdAt = Date(timeIntervalSince1970: 1_793_365_920)
private let zone = TimeZone(secondsFromGMT: -4 * 3600)!

private func label(_ text: String) -> PaperLabel { PaperLabel(text)! }

private func filled(_ text: String, _ name: String = "z_prime_by_plate") -> PaperPanel {
    PaperPanel(label: label(text), folder: "Assay development/\(name)", artifact: "bbbb", version: "eeee", file: "\(name).png")
}

private func empty(_ text: String) -> PaperPanel { PaperPanel(label: label(text)) }

private func paper(name: String = "Z′ assay paper", panels: [PaperPanel]? = nil) -> Paper {
    Paper(name: name, createdAt: createdAt, panels: panels ?? [filled("1A"), empty("2C")], capsid: "1.1.3")
}

private func text(_ paper: Paper) -> String { PaperFile.render(paper, timeZone: zone) }

private let sample = text(paper())

// MARK: Rendering

@Test func theContractsExampleIsWrittenToTheByte() {
    let expected = """
    ---
    capsid_paper: 1
    name: "Z′ assay paper"
    created_at: 2026-10-30T09:12:00-04:00
    panels:
      - { label: "1A", folder: "Assay development/z_prime_by_plate", artifact: "bbbb", version: "eeee", file: "z_prime_by_plate.png" }
      - { label: "2C" }
    capsid: "1.1.3"
    ---

    # Z′ assay paper

    - Fig 1A · z_prime_by_plate.png, from Assay development/z_prime_by_plate
    - Fig 2C · empty

    ---

    Capsid writes this file when you change the paper in the Shelf window. The figures stay in their own kept folders; removing one from the paper never touches its folder.

    """
    #expect(sample == expected)
    #expect(PaperFile.fileName == "PAPER.md")
    #expect(PaperFile.folderName == "Papers")
}

@Test func noPanelsIsAnEmptyListAndASentence() {
    let out = text(paper(panels: []))
    #expect(out.contains("\npanels: []\n"))
    #expect(out.contains("# Z′ assay paper\n\nNo panels yet.\n\n---\n"))
}

@Test func panelsAreWrittenInLabelOrderAndOptionalKeysAreLeftOut() {
    let bare = PaperPanel(label: label("S1"), folder: "Assay development/x")
    let out = text(paper(panels: [bare, empty("10A"), filled("2A"), filled("1B")]))
    let rows = out.split(separator: "\n").filter { $0.hasPrefix("  - ") }
    #expect(out.contains("  - { label: \"S1\", folder: \"Assay development/x\" }\n"))
    // 1B, 2A, 10A, S1.
    let labels = rows.compactMap { $0.split(separator: "\"").dropFirst().first.map(String.init) }
    #expect(labels == ["1B", "2A", "10A", "S1"])
}

@Test func anArtifactWithoutAFolderIsNeverWritten() {
    let odd = PaperPanel(label: label("3A"), folder: nil, artifact: "a", version: "v", file: "f.png")
    #expect(text(paper(panels: [odd])).contains("  - { label: \"3A\" }\n"))
}

// MARK: Round trip

private func roundTrips(_ paper: Paper) {
    let first = text(paper)
    guard let back = PaperFile.parse(first) else {
        Issue.record("did not read back: \(first)")
        return
    }
    #expect(text(back) == first)
}

@Test func renderParseRenderIsTheSameBytes() {
    roundTrips(paper())
    roundTrips(paper(name: "Z′ assay 🧪 paper"))
    roundTrips(paper(name: "A \"quoted\" name \\ with a backslash\nand a line break"))
    roundTrips(paper(name: "日本語の論文"))
}

@Test func parsingGivesBackWhatWasWritten() {
    let original = paper(name: "Z′ \"x\"\\\ny", panels: [filled("2B"), empty("1A"), filled("S1")])
    let back = PaperFile.parse(text(original))
    #expect(back?.name == original.name)
    #expect(back?.createdAt == createdAt)
    #expect(back?.capsid == "1.1.3")
    #expect(back?.panels.map(\.label.text) == ["1A", "2B", "S1"])
    #expect(back?.panels.last == filled("S1"))
}

@Test func aPaperWithNoPanelsRoundTrips() {
    roundTrips(paper(panels: []))
    #expect(PaperFile.parse(text(paper(panels: [])))?.panels == [])
}

// MARK: Strict about the front matter

private func replacing(_ old: String, with new: String, in source: String = sample) -> String {
    precondition(source.contains(old), "the sample has no \(old)")
    return source.replacingOccurrences(of: old, with: new)
}

@Test func theParserRefusesWhatTheRendererDidNotWrite() {
    let refused: [(String, String)] = [
        ("empty text", ""),
        ("no front matter", "# Z′ assay paper\n"),
        ("another capsid file", replacing("capsid_paper: 1", with: "capsid_kept: 1")),
        ("another version", replacing("capsid_paper: 1", with: "capsid_paper: 2")),
        ("an unquoted name", replacing("name: \"Z′ assay paper\"", with: "name: Z′ assay paper")),
        ("a bad date", replacing("2026-10-30T09:12:00-04:00", with: "2026-02-30T09:12:00-04:00")),
        ("a date with no zone", replacing("2026-10-30T09:12:00-04:00", with: "2026-10-30T09:12:00")),
        ("fields out of order", replacing("capsid_paper: 1\nname: \"Z′ assay paper\"", with: "name: \"Z′ assay paper\"\ncapsid_paper: 1")),
        ("an unknown key in a row", replacing("{ label: \"2C\" }", with: "{ label: \"2C\", note: \"x\" }")),
        ("keys out of order in a row", replacing("{ label: \"2C\" }", with: "{ folder: \"A/b\", label: \"2C\" }")),
        ("a label that is not canonical", replacing("\"2C\"", with: "\"2c\"")),
        ("a label with a prefix", replacing("\"2C\"", with: "\"Fig 2C\"")),
        ("a label it cannot read", replacing("\"2C\"", with: "\"2CC\"")),
        ("a label written bare", replacing("{ label: \"2C\" }", with: "{ label: 2C }")),
        ("a duplicate label", replacing("{ label: \"2C\" }", with: "{ label: \"1A\" }")),
        ("an artifact with no folder", replacing("{ label: \"2C\" }", with: "{ label: \"2C\", artifact: \"a\" }")),
        ("a version with no folder", replacing("{ label: \"2C\" }", with: "{ label: \"2C\", version: \"a\" }")),
        ("a file with no folder", replacing("{ label: \"2C\" }", with: "{ label: \"2C\", file: \"a.png\" }")),
        ("a folder of one part", replacing("Assay development/z_prime_by_plate\", artifact", with: "z_prime_by_plate\", artifact")),
        ("a folder of three parts", replacing("Assay development/z_prime_by_plate\", artifact", with: "Assay development/x/z_prime_by_plate\", artifact")),
        ("a folder that goes up", replacing("Assay development/z_prime_by_plate\", artifact", with: "../z_prime_by_plate\", artifact")),
        ("a folder with a hidden part", replacing("Assay development/z_prime_by_plate\", artifact", with: "Assay development/.hidden\", artifact")),
        ("a folder with an empty part", replacing("Assay development/z_prime_by_plate\", artifact", with: "/z_prime_by_plate\", artifact")),
        ("an absolute folder", replacing("Assay development/z_prime_by_plate\", artifact", with: "/Assay/z_prime_by_plate\", artifact")),
        ("a panels list with no rows", replacing("  - { label: \"2C\" }\n", with: "").split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("  - ") }.joined(separator: "\n")),
        ("a row without the dash", replacing("  - { label: \"2C\" }", with: "  { label: \"2C\" }")),
        ("no closing divider", String(sample.prefix(upTo: sample.range(of: "capsid: \"1.1.3\"\n")!.upperBound))),
        ("a missing capsid line", replacing("capsid: \"1.1.3\"\n", with: "")),
    ]
    for (what, markdown) in refused {
        #expect(PaperFile.parse(markdown) == nil, "should refuse \(what)")
    }
}

@Test func theBodyAfterTheFrontMatterIsNotRead() {
    let front = String(sample.prefix(upTo: sample.range(of: "capsid: \"1.1.3\"\n---\n")!.upperBound))
    // Nothing at all after the divider, or anything a person wrote.
    #expect(PaperFile.parse(front)?.panels.count == 2)
    #expect(PaperFile.parse(front + "\nWhatever a person typed.\n## Not a Capsid section\n")?.panels.count == 2)
    #expect(PaperFile.parse(replacing("# Z′ assay paper", with: "# Another title"))?.name == "Z′ assay paper")
}

@Test func aByteOrderMarkAndWindowsLineEndsAreRead() {
    let expected = PaperFile.parse(sample)
    #expect(expected != nil)
    #expect(PaperFile.parse("\u{FEFF}" + sample) == expected)
    #expect(PaperFile.parse(sample.replacingOccurrences(of: "\n", with: "\r\n")) == expected)
    #expect(PaperFile.parse("\u{FEFF}" + sample.replacingOccurrences(of: "\n", with: "\r\n")) == expected)
}

// MARK: Labels

@Test func labelsAreReadTheWayAPersonTypesThem() {
    #expect(PaperLabel("1a")?.text == "1A")
    #expect(PaperLabel("Fig 1A")?.text == "1A")
    #expect(PaperLabel("Figure S2b")?.text == "S2B")
    #expect(PaperLabel("fig. 3")?.text == "3")
    #expect(PaperLabel(" FIG 12c ")?.text == "12C")
    #expect(PaperLabel("s1")?.text == "S1")
    #expect(PaperLabel("99Z")?.text == "99Z")
    #expect(PaperLabel("Figure S2b") == PaperLabel(supplementary: true, figure: 2, panel: "B"))
}

@Test func labelsThatCouldMeanSomethingElseAreRefused() {
    for bad in ["0A", "100A", "1AB", "1 A", "", "S", "A1", "01A", "Fig", "Fig  1A", "Figs 1A", "1-A", "1Ä", "SS1", "Fig S"] {
        #expect(PaperLabel(bad) == nil, "should refuse \(bad)")
    }
}

@Test func labelsHaveTheirWrittenForms() {
    #expect(label("1A").text == "1A")
    #expect(label("1A").title == "Fig 1A")
    #expect(label("S1A").title == "Fig S1A")
    #expect(label("3").title == "Fig 3")
    #expect(label("S1A").figureKey == PaperFigure(supplementary: true, number: 1))
    #expect(PaperFigure(supplementary: false, number: 1).title == "Figure 1")
    #expect(PaperFigure(supplementary: true, number: 1).title == "Supplementary Figure S1")
}

@Test func labelsAreInManuscriptOrder() {
    #expect(label("1A") < label("1B"))
    #expect(label("2A") < label("10A"))
    #expect(label("1") < label("1A"))
    #expect(label("99Z") < label("S1A"))
    #expect(label("S1A") < label("S1B"))
    #expect(label("S2A") < label("S10A"))
    #expect(!(label("S1") < label("1")))
    let shuffled = ["S1A", "10A", "2B", "1", "2A", "1B", "S2", "1A"].map(label)
    #expect(shuffled.sorted().map(\.text) == ["1", "1A", "1B", "2A", "2B", "10A", "S1A", "S2"])
    #expect(PaperFigure(supplementary: false, number: 10) < PaperFigure(supplementary: true, number: 1))
}

// MARK: Layout

@Test func aMissingLetterBelowTheHighestShowsAsAGap() {
    let groups = PaperRules.figures([filled("1C"), filled("1A")])
    #expect(groups.count == 1)
    #expect(groups[0].figure == PaperFigure(supplementary: false, number: 1))
    #expect(groups[0].slots == [.panel(filled("1A")), .gap(label("1B")), .panel(filled("1C"))])
}

@Test func aWholeFigureCausesNoGaps() {
    let groups = PaperRules.figures([filled("2")])
    #expect(groups.map(\.slots) == [[.panel(filled("2"))]])
    // A whole-figure label comes first when the figure also has panels.
    let both = PaperRules.figures([filled("3B"), filled("3")])
    #expect(both[0].slots == [.panel(filled("3")), .gap(label("3A")), .panel(filled("3B"))])
}

@Test func figuresAreGroupedInOrderAndEmptySlotsAreSlots() {
    let groups = PaperRules.figures([filled("S1"), empty("10A"), filled("2A"), filled("1A")])
    #expect(groups.map(\.id.title) == ["Figure 1", "Figure 2", "Figure 10", "Supplementary Figure S1"])
    #expect(groups[2].slots == [.panel(empty("10A"))])
    #expect(PaperRules.figures([]).isEmpty)
}

@Test func theNextLabelIsAfterTheHighestUsed() {
    let one = PaperFigure(supplementary: false, number: 1)
    #expect(PaperRules.nextLabel(in: one, after: []) == label("1A"))
    #expect(PaperRules.nextLabel(in: one, after: [filled("1A"), filled("1C")]) == label("1D"))
    #expect(PaperRules.nextLabel(in: one, after: [filled("2A")]) == label("1A"))
    #expect(PaperRules.nextLabel(in: one, after: [filled("1")]) == label("1A"))
    #expect(PaperRules.nextLabel(in: one, after: [filled("1Z")]) == nil)
    let supp = PaperFigure(supplementary: true, number: 1)
    #expect(PaperRules.nextLabel(in: supp, after: [filled("1A"), filled("S1A")]) == label("S1B"))
}

@Test func theNextFigureIsOneAboveTheHighestOfItsKind() {
    #expect(PaperRules.nextFigure(supplementary: false, after: []) == PaperFigure(supplementary: false, number: 1))
    #expect(PaperRules.nextFigure(supplementary: false, after: [filled("1A"), filled("4"), filled("S9")]) == PaperFigure(supplementary: false, number: 5))
    #expect(PaperRules.nextFigure(supplementary: true, after: [filled("1A"), filled("S9")]) == PaperFigure(supplementary: true, number: 10))
    #expect(PaperRules.nextFigure(supplementary: true, after: [filled("1A")]) == PaperFigure(supplementary: true, number: 1))
}

// MARK: Changes

@Test func assigningSetsOrReplacesThePanelWithThatLabel() {
    let start = [filled("1A", "a"), empty("1C")]
    let added = PaperRules.assigning(filled("1B", "b"), in: start)
    #expect(added.map(\.label.text) == ["1A", "1B", "1C"])
    let replaced = PaperRules.assigning(filled("1C", "c"), in: start)
    #expect(replaced == [filled("1A", "a"), filled("1C", "c")])
    let before = PaperRules.assigning(filled("S1"), in: [filled("2A")])
    #expect(before.map(\.label.text) == ["2A", "S1"])
}

@Test func removingTakesTheSlotOutAndEmptyingKeepsIt() {
    let start = [filled("1A"), filled("1B")]
    #expect(PaperRules.removing(label("1A"), from: start) == [filled("1B")])
    #expect(PaperRules.removing(label("9Z"), from: start) == start)
    #expect(PaperRules.emptying(label("1A"), in: start) == [empty("1A"), filled("1B")])
    #expect(PaperRules.emptying(label("9Z"), in: start) == start)
    #expect(PaperRules.emptying(label("1A"), in: start)[0].isEmpty)
}

@Test func relabellingMovesAPanelButNeverOntoAFigure() {
    let start = [filled("1A", "a"), filled("1B", "b"), empty("1D")]
    #expect(PaperRules.relabelling(label("1A"), to: label("1B"), in: start) == nil)
    let toFree = PaperRules.relabelling(label("1A"), to: label("1C"), in: start)
    #expect(toFree?.map(\.label.text) == ["1B", "1C", "1D"])
    #expect(toFree?[1].folder == "Assay development/a")
    // Onto an empty slot: the slot goes.
    let toEmpty = PaperRules.relabelling(label("1A"), to: label("1D"), in: start)
    #expect(toEmpty == [filled("1B", "b"), PaperPanel(label: label("1D"), folder: "Assay development/a", artifact: "bbbb", version: "eeee", file: "a.png")])
    #expect(PaperRules.relabelling(label("1A"), to: label("1A"), in: start) == start)
    #expect(PaperRules.relabelling(label("3A"), to: label("3B"), in: start) == nil)
}

@Test func swappingExchangesContentsAndKeepsLabels() {
    let start = [filled("1A", "a"), filled("1B", "b")]
    let swapped = PaperRules.swapping(label("1A"), label("1B"), in: start)
    #expect(swapped.map(\.label.text) == ["1A", "1B"])
    #expect(swapped[0].folder == "Assay development/b")
    #expect(swapped[1].folder == "Assay development/a")
    // With an empty slot.
    let withEmpty = PaperRules.swapping(label("1A"), label("1C"), in: [filled("1A", "a"), empty("1C")])
    #expect(withEmpty == [empty("1A"), PaperPanel(label: label("1C"), folder: "Assay development/a", artifact: "bbbb", version: "eeee", file: "a.png")])
}

@Test func swappingWithALabelNotInThePaperMovesThePanel() {
    let start = [filled("1A", "a"), filled("2A", "x")]
    let moved = PaperRules.swapping(label("1A"), label("1B"), in: start)
    #expect(moved.map(\.label.text) == ["1B", "2A"])
    #expect(moved[0].folder == "Assay development/a")
    let backwards = PaperRules.swapping(label("1C"), label("1A"), in: start)
    #expect(backwards.map(\.label.text) == ["1C", "2A"])
    #expect(PaperRules.swapping(label("5A"), label("5B"), in: start) == start)
}

// MARK: Words and names

@Test func theExportNameCarriesTheLabelAndTheFilesExtension() {
    #expect(PaperRules.exportName(label: label("2B"), name: "z_prime_by_plate.png", fileName: "z_prime_by_plate.png") == "Fig 2B · z_prime_by_plate.png")
    #expect(PaperRules.exportName(label: label("2B"), name: "Z′ by plate", fileName: "fig.pdf") == "Fig 2B · Z′ by plate.pdf")
    #expect(PaperRules.exportName(label: label("S1A"), name: "Plate/QC: 3", fileName: "fig.svg") == "Fig S1A · Plate_QC_ 3.svg")
    #expect(PaperRules.exportName(label: label("3"), name: "Overview", fileName: "overview") == "Fig 3 · Overview")
    #expect(PaperRules.exportName(label: label("3"), name: "Overview.PNG", fileName: "overview.png") == "Fig 3 · Overview.PNG.png")
    #expect(PaperRules.exportName(label: label("3"), name: "Overview", fileName: "Overview.PNG") == "Fig 3 · Overview.PNG")
}

private func entry(_ text: String, title: String = "A figure", legend: String = "", claude: String = "", last: Bool = false) -> PaperRules.LegendEntry {
    PaperRules.LegendEntry(label: label(text), title: title, legend: legend, claudeSaid: claude, claudeIsLastAnswer: last)
}

@Test func legendsAreInLabelOrderUnderTheirFigures() {
    let out = PaperRules.legends(paper: "Z′ assay paper", [
        entry("S1", title: "Supp", legend: "Supplementary words."),
        entry("2A", title: "Second", legend: "Two."),
        entry("1B", title: "Plate B", legend: "B words."),
        entry("1A", title: "Plate A", legend: "A words."),
    ])
    let expected = """
    # Z′ assay paper

    ## Figure 1

    **Fig 1A** · Plate A

    A words.

    **Fig 1B** · Plate B

    B words.

    ## Figure 2

    **Fig 2A** · Second

    Two.

    ## Supplementary Figure S1

    **Fig S1** · Supp

    Supplementary words.

    """
    #expect(out == expected)
}

@Test func legendsFallBackToClaudeThenToASaidGap() {
    let out = PaperRules.legends(paper: "P", [
        entry("1A", legend: "  Mine.  ", claude: "Claude's words."),
        entry("1B", legend: "   ", claude: "Claude's words."),
        entry("1C", claude: "Only the last answer.", last: true),
        entry("1D"),
    ])
    #expect(out.contains("**Fig 1A** · A figure\n\nMine.\n\n"))
    #expect(!out.contains("Claude: Claude's words.\n\n**Fig 1A**"))
    #expect(out.contains("**Fig 1B** · A figure\n\nClaude: Claude's words.\n\n"))
    #expect(out.contains("**Fig 1C** · A figure\n\n_No legend yet._\n\n"))
    #expect(!out.contains("Only the last answer."))
    #expect(out.hasSuffix("**Fig 1D** · A figure\n\n_No legend yet._\n"))
    #expect(!out.hasSuffix("\n\n"))
}

@Test func legendsOfNothingAreJustTheTitle() {
    #expect(PaperRules.legends(paper: "P", []) == "# P\n")
}

@Test func theSummariesAreInPlainWords() {
    #expect(PaperRules.outOfDateSummary(0) == nil)
    #expect(PaperRules.outOfDateSummary(1) == "1 panel out of date")
    #expect(PaperRules.outOfDateSummary(2) == "2 panels out of date")
    #expect(PaperRules.missingSummary(filled: 3, slots: 5) == "3 of 5 panels filled")
}

@Test func aBrokenSlotNamesTheFolderAndTheUsualReasons() {
    #expect(PaperRules.brokenSlot(folder: "Assay development/z_prime_by_plate")
        == "\u{201C}z_prime_by_plate\u{201D} isn\u{2019}t in the Shelf folder any more. It may have been moved, renamed or put in the Trash.")
    #expect(PaperRules.folderPath(collection: "Assay development", name: "z_prime_by_plate") == "Assay development/z_prime_by_plate")
}
