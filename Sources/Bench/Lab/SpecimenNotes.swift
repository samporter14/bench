// SpecimenNotes.swift — what the field guide says about each specimen (DESIGN.md,
// "Scenes settings"). Data only: the lookups and the search are in
// SpecimenGuide.swift, so this file can be regenerated without touching them.
//
// THIS TABLE IS A STUB: a few specimens, to build the field guide against. The
// full table, one entry for every specimen in `LabScenes.catalogue`, replaces
// it, generated into this file.
import Foundation

/// The words that go with one specimen.
struct SpecimenNote: Sendable {
    /// A few words for the panel's quiet line, 36 characters at most.
    let caption: String
    /// One sentence for the field guide, 140 characters at most.
    let note: String
    /// Which subjects it belongs to, from a fixed list. The Specimens tab's
    /// Topics menu offers them, and searching one finds its specimens.
    let topics: [String]
    /// Extra words to search by that the name, caption and note don't use:
    /// what else it's called, or what it's for.
    let also: [String]
}

enum SpecimenNotes {
    /// By specimen name, as in `LabScenes.catalogue`.
    static let all: [String: SpecimenNote] = [
        "Flask": SpecimenNote(
            caption: "Something bubbling gently in glass",
            note: "A flask warmed on a hotplate: the bubbles are a reaction giving off gas as the liquid swirls.",
            topics: ["Chemistry", "Glassware"],
            also: ["erlenmeyer", "conical flask", "beaker", "reaction"]),
        "Kinesin": SpecimenNote(
            caption: "A motor protein on a microtubule",
            note: "Kinesin steps hand over hand along a microtubule, spending one ATP for each 8 nm step as it hauls its cargo.",
            topics: ["Molecular motors", "Cell biology"],
            also: ["cytoskeleton", "atp", "walking"]),
        "PCR": SpecimenNote(
            caption: "Copying DNA by heating and cooling",
            note: "Each cycle melts the DNA, lets short primers bind, then a polymerase copies it, so the copies double every round.",
            topics: ["DNA", "Molecular biology"],
            also: ["polymerase chain reaction", "thermal cycler", "amplification", "primers"]),
        "Microscope": SpecimenNote(
            caption: "Focusing on a slide of cells",
            note: "Turning the focus knob brings a stained slide from a blur into sharp view under the objective lens.",
            topics: ["Microscopy", "Optics"],
            also: ["objective", "eyepiece", "slide", "magnification"]),
        "Immunofluorescence": SpecimenNote(
            caption: "Cells lit up by glowing antibodies",
            note: "Antibodies carrying a fluorescent dye stick to one protein, so under the microscope only that part of the cell glows.",
            topics: ["Microscopy", "Cell biology"],
            also: ["antibody", "staining", "fluorescent dye"]),
        "Volcano plot": SpecimenNote(
            caption: "Each dot is a gene, up or down",
            note: "Size of change runs along one axis and confidence along the other, so the genes that matter climb into the top corners.",
            topics: ["Data", "Statistics"],
            also: ["differential expression", "fold change", "p value", "significance"]),
        "Prism": SpecimenNote(
            caption: "White light split into a spectrum",
            note: "Light slows in glass by a different amount for each color, so a prism bends blue more than red and fans out a rainbow.",
            topics: ["Optics", "Light"],
            also: ["refraction", "rainbow", "wavelength", "ångström"]),
    ]
}
