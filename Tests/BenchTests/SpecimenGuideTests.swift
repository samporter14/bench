// SpecimenGuideTests.swift — the field guide's search and its table. The
// ranking and matching tests run on a small table of their own, so they hold
// whatever the real table says; the last few check the real one.
import Testing
@testable import Bench

struct SpecimenGuideTests {
    private static func note(_ caption: String, _ note: String, topics: [String] = [], also: [String] = []) -> SpecimenNote {
        SpecimenNote(caption: caption, note: note, topics: topics, also: also)
    }

    /// Listed in an order that would be wrong for every ranking test: the
    /// weaker match first.
    private static let names = [
        "Kinesin", "Spray", "Gel", "Microscope", "Immunofluorescence", "Cell division",
        "X-ray diffraction", "Prism", "Wöhler synthesis", "Maxwell’s demon", "Plain name",
    ]

    private static let notes: [String: SpecimenNote] = [
        "Kinesin": note("A motor protein on a filament", "It carries cargo along a microtubule inside a cell.",
                        topics: ["Molecular motors"]),
        "Gel": note("DNA sorted by size", "Short pieces run further than long ones.", topics: ["Molecular biology"]),
        "Microscope": note("Focusing on a slide", "A stained slide comes into sharp view.", topics: ["Microscopy", "Optics"]),
        "Immunofluorescence": note("Cells lit up by antibodies", "Only one protein glows.",
                                   topics: ["microscopy", "Cell biology"]),
        "Cell division": note("One cell becoming two", "The chromosomes pull apart.", topics: ["Cell biology"]),
        "Prism": note("White light into a spectrum", "Blue bends more than red.",
                      topics: ["Optics"], also: ["refraction", "Ångström"]),
    ]

    private let index = SpecimenIndex(names: names, notes: notes)

    // MARK: Ranking

    @Test func aNameMatchRanksBeforeANoteMatch() {
        // Kinesin comes first in the list and has a cell in its note, and
        // Immunofluorescence has one in a topic; "Cell division" has it in its
        // name.
        #expect(index.search("cell") == ["Cell division", "Immunofluorescence", "Kinesin"])
    }

    @Test func aWordThatStartsTheNameRanksBeforeOneInsideIt() {
        // "Spray" holds "ray" and comes first in the list.
        #expect(index.search("ray") == ["X-ray diffraction", "Spray"])
    }

    @Test func aTopicRanksBeforeACaptionAndACaptionBeforeANote() {
        let table = [
            "Alpha": Self.note("Nothing here", "Mentions optics in passing."),
            "Beta": Self.note("About optics, mostly", "Nothing here."),
            "Gamma": Self.note("Nothing here", "Nothing here.", topics: ["Optics"]),
            "Delta": Self.note("Nothing here", "Nothing here.", also: ["optics"]),
        ]
        let found = SpecimenIndex(names: ["Alpha", "Beta", "Gamma", "Delta"], notes: table).search("optics")
        #expect(found == ["Gamma", "Delta", "Beta", "Alpha"])
    }

    @Test func specimensThatMatchEquallyKeepTheOrderTheyWereGiven() {
        // All three have "cell" in a topic, in different places in it.
        let table = [
            "One": Self.note("", "", topics: ["Cell biology"]),
            "Two": Self.note("", "", topics: ["Cell cycle"]),
            "Three": Self.note("", "", topics: ["Cell signalling"]),
        ]
        #expect(SpecimenIndex(names: ["Two", "Three", "One"], notes: table).search("cell") == ["Two", "Three", "One"])
    }

    @Test func wordsFoundInDifferentPlacesStillMatchButComeLast() {
        // "motor" is in a topic and "microtubule" in the note, so neither
        // field holds both.
        #expect(index.search("motor microtubule") == ["Kinesin"])
        // The same words together in one place beat them apart.
        let table = [
            "Apart": Self.note("Blue light", "Red light.", topics: ["Waves"]),
            "Together": Self.note("", "Red light, then blue.", topics: ["Waves"]),
        ]
        let two = SpecimenIndex(names: ["Apart", "Together"], notes: table).search("blue red")
        #expect(two == ["Together", "Apart"])
    }

    // MARK: Topics

    @Test func aTopicFindsEverySpecimenWithIt() {
        #expect(Set(index.search("microscopy")) == ["Microscope", "Immunofluorescence"])
        // However it is typed, and however the table spells it.
        #expect(Set(index.search("MICROSCOPY")) == ["Microscope", "Immunofluorescence"])
        #expect(Set(index.search("  Cell   Biology ")) == ["Immunofluorescence", "Cell division"])
    }

    @Test func topicsAreListedOnceEachInAlphabeticalOrder() {
        // "Microscopy" is spelled two ways in the table, and is one topic.
        let topics = SpecimenGuide.topics(in: Self.notes)
        #expect(topics.count == 5)
        #expect(topics.map(SpecimenGuide.fold) == [
            "cell biology", "microscopy", "molecular biology", "molecular motors", "optics",
        ])
    }

    // MARK: Case and accents

    @Test func accentsAndCaseDontMatter() {
        #expect(index.search("angstrom") == ["Prism"])
        #expect(index.search("ÅNGSTRÖM") == ["Prism"])
        #expect(index.search("wohler") == ["Wöhler synthesis"])
        #expect(index.search("WÖHLER") == ["Wöhler synthesis"])
        #expect(index.search("Öhler") == ["Wöhler synthesis"])
    }

    @Test func aCurlyApostropheMatchesAStraightOne() {
        #expect(index.search("maxwell's") == ["Maxwell’s demon"])
        #expect(index.search("maxwell’s") == ["Maxwell’s demon"])
    }

    // MARK: Edges

    @Test func noSearchMatchesEverySpecimenInTheOrderGiven() {
        #expect(index.search("") == Self.names)
        #expect(index.search("   ") == Self.names)
    }

    @Test func nothingFoundIsNothing() {
        #expect(index.search("zebrafish").isEmpty)
        // Every word has to be somewhere.
        #expect(index.search("kinesin zebrafish").isEmpty)
    }

    @Test func aSpecimenWithNoNoteStillMatchesByName() {
        #expect(index.search("plain") == ["Plain name"])
    }

    @Test func theCatalogueFindsItselfByName() {
        let catalogue = LabScenes.catalogue.map(\.name)
        #expect(SpecimenGuide.index.search("") == catalogue)
        for name in catalogue {
            #expect(SpecimenGuide.index.search(name).contains(name), "\(name)")
        }
    }

    // MARK: The panel's line

    @Test func theLineNamesTheSpecimenAndItsCaption() {
        #expect(SpecimenGuide.line(for: "Gel", notes: Self.notes) == "Gel · DNA sorted by size")
        // No note, so the name alone: the line is never empty.
        #expect(SpecimenGuide.line(for: "Plain name", notes: Self.notes) == "Plain name")
    }

    // MARK: The real table

    @Test func captionsAndNotesStayWithinTheirLimits() {
        for (name, note) in SpecimenNotes.all {
            #expect(!note.caption.isEmpty && note.caption.count <= SpecimenGuide.captionLimit, "caption of \(name)")
            #expect(!note.note.isEmpty && note.note.count <= SpecimenGuide.noteLimit, "note of \(name)")
        }
    }

    @Test func everyNoteIsForARealSpecimen() {
        let names = Set(LabScenes.catalogue.map(\.name))
        #expect(SpecimenNotes.all.keys.filter { !names.contains($0) }.sorted().isEmpty)
    }

    @Test(.disabled("until the notes table lands"))
    func everySpecimenHasANoteAndEveryNoteHasASpecimen() {
        let names = Set(LabScenes.catalogue.map(\.name))
        #expect(names.subtracting(SpecimenNotes.all.keys).sorted().isEmpty, "specimens with no note")
        #expect(Set(SpecimenNotes.all.keys).subtracting(names).sorted().isEmpty, "notes for no specimen")
    }
}
