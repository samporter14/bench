// SpecimenTopicsTests.swift — matching a session's title to a specimen
// (Lab/SpecimenTopics.swift): accents, case and plurals, topics of several
// words, a choice that is the same on every read, and the user's choices
// winning. Titles and session ids are made up.
import Foundation
import Testing
@testable import Bench

private func note(_ topics: [String]) -> SpecimenNote {
    SpecimenNote(caption: "Made up", note: "Made up.", topics: topics, also: [])
}

/// A table of made-up specimens, so the tests don't depend on the real one.
private let table: [String: SpecimenNote] = [
    "Alpha": note(["cell biology", "microscopy"]),
    "Beta": note(["microscopy", "Ångström optics"]),
    "Gamma": note(["genomics", "PCR"]),
    "Delta": note([]),
    "Plate reader": note(["measurement"]),
]
private let index = SpecimenTopicIndex(names: Array(table.keys), notes: table)
private let all = ["Alpha", "Beta", "Gamma", "Delta", "Plate reader"]
private let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

private func match(_ title: String, id: String = session, among candidates: [String] = all) -> (name: String, topic: String)? {
    SpecimenTopics.match(title: title, sessionID: id, candidates: candidates, index: index)
}

struct SpecimenTopicWordsTests {
    @Test func caseAccentsAndWidthFoldAway() {
        #expect(SpecimenTopics.words(in: "Ångström ÓPTICS") == ["angstrom", "optic"])
        #expect(SpecimenTopics.words(in: "ＰＣＲ") == ["pcr"])
        #expect(SpecimenTopics.words(in: "Naïve café") == ["naive", "cafe"])
    }

    @Test func punctuationPartsWordsAndApostrophesDont() {
        #expect(SpecimenTopics.words(in: "6-well plate/seeding: Sam’s run") == ["6", "well", "plate", "seeding", "sam", "run"])
        #expect(SpecimenTopics.words(in: "   ") == [])
        #expect(SpecimenTopics.words(in: "—, !") == [])
    }

    @Test func simplePluralsMeetTheirSingulars() {
        let pairs = [("cells", "cell"), ("genomics", "genomic"), ("assemblies", "assembly"), ("boxes", "box"),
                     ("matches", "match"), ("brushes", "brush"), ("classes", "class"), ("phases", "phase"),
                     ("enzymes", "enzyme"), ("studies", "study")]
        for (plural, singular) in pairs {
            #expect(SpecimenTopics.stem(plural) == SpecimenTopics.stem(singular), "\(plural)")
        }
    }

    @Test func wordsThatLookPluralButArentStayAsTheyAre() {
        for word in ["mass", "virus", "analysis", "gas", "rna", "pcr", "lab"] {
            #expect(SpecimenTopics.stem(word) == word, "\(word)")
        }
    }

    @Test func aPhraseMustBeConsecutiveWords() {
        let words = SpecimenTopics.words(in: "Notes on cell biology of yeast")
        #expect(SpecimenTopics.contains(words, phrase: ["cell", "biology"]))
        #expect(!SpecimenTopics.contains(words, phrase: ["biology", "cell"]))
        #expect(!SpecimenTopics.contains(SpecimenTopics.words(in: "biology of the cell"), phrase: ["cell", "biology"]))
        #expect(!SpecimenTopics.contains(words, phrase: []))
        #expect(!SpecimenTopics.contains(["cell"], phrase: ["cell", "biology"]))
    }
}

struct SpecimenTopicMatchTests {
    @Test func aTopicInTheTitleFindsItsSpecimens() {
        let found = match("Genomics pipeline for the screen")
        #expect(found?.name == "Gamma")
        #expect(found?.topic == "genomics")
    }

    @Test func caseAccentsAndPluralsDontMatter() {
        for title in ["GENOMIC pipeline", "genomics", "Notes on Genomics!", "génomics"] {
            #expect(match(title)?.name == "Gamma", "\(title)")
        }
        // The topic is written with an accent and a capital; the title has neither.
        #expect(match("angstrom optics bench")?.name == "Beta")
        #expect(match("angstrom optics bench")?.topic == "Ångström optics")
        // A plural in the title for a singular in the table, and the other way round.
        #expect(match("Several PCRs")?.name == "Gamma")
        #expect(match("Microscopies of yeast")?.topic == "microscopy")
        #expect(match("Microscopy of yeast")?.topic == "microscopy")
    }

    @Test func aTopicOfSeveralWordsMatchesAsAPhrase() {
        #expect(match("Cell biology seminar")?.name == "Alpha")
        #expect(match("Cell biology seminar")?.topic == "cell biology")
        #expect(match("Cells and their biology") == nil)
        #expect(match("biology cell") == nil)
        #expect(match("Seeding cell") == nil)
    }

    @Test func theLongestTopicThatFitsIsTheOneReported() {
        // Alpha fits "microscopy" and "cell biology": the phrase wins.
        let found = match("Cell biology by microscopy", among: ["Alpha"])
        #expect(found?.name == "Alpha")
        #expect(found?.topic == "cell biology")
        // Beta fits "microscopy" and the phrase "Ångström optics": the phrase again.
        #expect(match("Microscopy and angstrom optics", among: ["Beta"])?.topic == "Ångström optics")
        // Equal lengths: the one the notes write first, whichever the title says first.
        #expect(match("PCR and genomics", among: ["Gamma"])?.topic == "genomics")
        #expect(match("Genomics and PCR", among: ["Gamma"])?.topic == "genomics")
    }

    @Test func aSpecimenNamedInTheTitleBeatsThoseOnlyItsTopicsFit() {
        // "Plate reader" is named; Alpha and Beta fit "microscopy".
        let found = match("Plate reader after microscopy")
        #expect(found?.name == "Plate reader")
        #expect(found?.topic == "Plate reader")
        // Named in the plural, and as a phrase: "plate" alone doesn't name it.
        #expect(match("Plate readers in the core")?.name == "Plate reader")
        #expect(match("Plate counts") == nil)
        // A specimen with no topics at all is found by its name.
        #expect(match("Delta check")?.name == "Delta")
    }

    @Test func noMatchIsNil() {
        #expect(match("Quarterly budget review") == nil)
        #expect(match("") == nil)
        #expect(match("   \n ") == nil)
        #expect(match("—") == nil)
        #expect(match("microscopy", among: []) == nil)
    }

    @Test func onlyTheCandidatesAreEverPicked() {
        // Microscopy fits Alpha and Beta; with Beta off, only Alpha can play.
        for n in 0..<40 {
            let id = String(format: "%08lx-0000-4000-8000-000000000001", n)
            #expect(match("Microscopy", id: id, among: ["Alpha", "Gamma"])?.name == "Alpha")
            #expect(match("Microscopy", id: id, among: ["Gamma", "Delta"]) == nil)
        }
        // A name the table doesn't know is matched by its name alone.
        #expect(match("Spinning disk imaging", among: ["Spinning disk"])?.name == "Spinning disk")
        #expect(match("Spinning disk imaging", among: ["Spinning disk"])?.topic == "Spinning disk")
        // And a duplicate candidate is no second chance.
        #expect(match("Genomics", among: ["Gamma", "Gamma", "Gamma"])?.name == "Gamma")
    }

    @Test func theSameSessionKeepsItsSpecimenWhateverTheOrderOfTheCandidates() {
        let first = match("Microscopy", among: ["Alpha", "Beta"])
        for _ in 0..<50 {
            #expect(match("Microscopy", among: ["Alpha", "Beta"])?.name == first?.name)
            #expect(match("Microscopy", among: ["Beta", "Alpha"])?.name == first?.name)
            #expect(match("Microscopy", among: ["Beta", "Alpha", "Delta", "Alpha"])?.name == first?.name)
        }
        // The title can change around the match without moving it.
        #expect(match("More microscopy today", among: ["Beta", "Alpha"])?.name == first?.name)
    }

    @Test func differentSessionsSpreadAcrossTheMatches() {
        var picked: [String: Int] = [:]
        for n in 0..<200 {
            let id = String(format: "%08lx-aaaa-4000-8000-%012lx", n * 7919, n)
            if let name = match("Microscopy", id: id, among: ["Alpha", "Beta"])?.name { picked[name, default: 0] += 1 }
        }
        #expect(Set(picked.keys) == ["Alpha", "Beta"])
        #expect(picked.values.allSatisfy { $0 > 40 }, "\(picked)")
    }

    @Test func theChoiceRestsOnAHashThatIsFixedByDefinition() {
        // FNV-1a, 64 bits: the published test vectors. Swift's own hashValue
        // is seeded afresh for every process and would move the choice.
        #expect(SpecimenTopics.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(SpecimenTopics.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(SpecimenTopics.stableHash("foobar") == 0x8594_4171_f739_67e8)
        // So a session's specimen is a value that can be written down: these
        // positions were worked out by hand, outside Swift.
        let one = "00000000-0000-4000-8000-000000000001"
        #expect(SpecimenTopics.position(of: one, among: 2) == 1)
        #expect(SpecimenTopics.position(of: one, among: 3) == 2)
        #expect(SpecimenTopics.position(of: one, among: 7) == 6)
        #expect(SpecimenTopics.position(of: session, among: 2) == 0)
        #expect(SpecimenTopics.position(of: "foobar", among: 3) == 1)
        #expect(match("Microscopy", id: one, among: ["Alpha", "Beta"])?.name == "Beta")
        #expect(match("Microscopy", id: session, among: ["Alpha", "Beta"])?.name == "Alpha")
    }

    @Test func theTopicReturnedIsNeverAWordOfTheTitle() {
        // "Quarterly" is in no table: the title's own words never come back.
        let found = match("Quarterly genomics review for Sam’s lab")
        #expect(found?.topic == "genomics")
        #expect(found?.name == "Gamma")
    }
}

/// The real field guide: what a title finds among the 555 specimens.
struct SpecimenTopicCatalogueTests {
    private let everyone = LabScenes.catalogue.map(\.name)

    @Test func aTopicPicksAmongTheSpecimensThatHaveIt() {
        let having = Set(SpecimenNotes.all.filter { $0.value.topics.contains("centrifugation") }.keys)
        #expect(having.count > 1)
        var picked = Set<String>()
        for n in 0..<120 {
            let id = String(format: "%08lx-0000-4000-8000-%012lx", n * 104_729, n)
            // "Centrifuge" is a specimen's own name; the topic is "centrifugation".
            guard let found = SpecimenTopics.match(title: "Centrifugation of the lysates", sessionID: id, candidates: everyone) else {
                Issue.record("no match for \(id)"); return
            }
            #expect(having.contains(found.name), "\(found.name)")
            #expect(found.topic == "centrifugation")
            picked.insert(found.name)
        }
        #expect(picked.count > 1)
    }

    @Test func aNameInTheTitlePicksThatSpecimen() {
        let found = SpecimenTopics.match(title: "Centrifuge balance check", sessionID: session, candidates: everyone)
        #expect(found?.name == "Centrifuge")
        #expect(found?.topic == "Centrifuge")
    }

    @Test func whatComesBackIsAlwaysACandidateAndATopicOrItsOwnName() {
        let titles = ["Plate reader QC", "Assay development", "RNA-seq of the knockdowns", "Western blot quantification",
                      "Imaging cells by microscopy", "PCR optimisation", "Mass spectrometry run", "Sourdough starter notes"]
        for (n, title) in titles.enumerated() {
            let id = String(format: "%08lx-1111-4000-8000-%012lx", n, n)
            guard let found = SpecimenTopics.match(title: title, sessionID: id, candidates: everyone) else { continue }
            #expect(everyone.contains(found.name), "\(title)")
            #expect(found.topic == found.name || SpecimenNotes.all[found.name]?.topics.contains(found.topic) == true,
                    "\(title) → \(found.name) / \(found.topic)")
        }
        // At least the obvious ones do match.
        #expect(SpecimenTopics.match(title: "PCR optimisation", sessionID: session, candidates: everyone) != nil)
        #expect(SpecimenTopics.match(title: "Plate reader QC", sessionID: session, candidates: everyone)?.name == "Plate reader")
    }

    @Test func aChoiceThatLeavesOnlyOneSpecimenKeepsItOrNothing() {
        let only = ["Gel"]
        #expect(SpecimenTopics.match(title: "Electrophoresis check", sessionID: session, candidates: only)?.name == "Gel")
        #expect(SpecimenTopics.match(title: "Centrifugation", sessionID: session, candidates: only) == nil)
    }

    @Test func theIndexForTheCatalogueCoversEverySpecimen() {
        for scene in LabScenes.catalogue {
            let entry = SpecimenTopicIndex.catalogue.entry(for: scene.name)
            #expect(!entry.nameWords.isEmpty, "\(scene.name)")
            #expect(entry.topics.count == SpecimenNotes.all[scene.name]?.topics.count, "\(scene.name)")
        }
    }
}
