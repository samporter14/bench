// SpecimenNotes.swift — what the field guide says about each specimen (DESIGN.md,
// "Scenes settings"). Data only: the lookups and the search are in
// SpecimenGuide.swift, so this file can be regenerated without touching them.
//
// One entry for every specimen in `LabScenes.catalogue` (a test checks), in
// the catalogue's order. Written for scientists and fact-checked: what the
// real thing is, never how it is drawn. A new specimen needs its entry here.
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
            caption: "Liquid swirling in a lab flask",
            note: "A conical flask holds and mixes liquids; its sloped sides and narrow neck let the contents be swirled with little splashing.",
            topics: ["lab life", "chemistry"],
            also: ["Erlenmeyer", "conical flask", "glassware"]),
        "ECL detection": SpecimenNote(
            caption: "Antibodies lighting up a blot",
            note: "In Western blot detection, a primary antibody binds the protein, an HRP-linked secondary binds that, and ECL substrate then gives off light.",
            topics: ["immunology", "imaging"],
            also: ["Western blot", "chemiluminescence", "HRP", "immunoblot"]),
        "Plate reader": SpecimenNote(
            caption: "Reading every well of a plate",
            note: "A plate reader measures absorbance, fluorescence or luminescence in each well of a microplate, quantifying many samples in one run.",
            topics: ["measurement", "spectroscopy"],
            also: ["microplate reader", "96-well", "absorbance"]),
        "Petri dish": SpecimenNote(
            caption: "Colonies appearing on agar",
            note: "A Petri dish holds nutrient agar on which single microbes multiply into visible colonies, each usually descended from one cell.",
            topics: ["microbiology", "cell culture"],
            also: ["agar plate", "colony", "culture"]),
        "Streak plate": SpecimenNote(
            caption: "Streaking out single colonies",
            note: "Streaking a plate thins bacteria out across the agar so that isolated single colonies grow, giving a pure culture from one cell.",
            topics: ["microbiology", "sample prep"],
            also: ["streaking", "isolation", "agar", "pure culture"]),
        "Centrifuge": SpecimenNote(
            caption: "Balanced tubes spinning in a rotor",
            note: "A centrifuge spins samples at high speed so denser particles sediment; tubes must be loaded in balanced, opposite pairs.",
            topics: ["centrifugation", "separation"],
            also: ["rotor", "spin", "balance"]),
        "Microscope": SpecimenNote(
            caption: "Bringing cells into focus",
            note: "Turning the focus knob of a light microscope moves the specimen into the focal plane, where cells and their nuclei appear sharp.",
            topics: ["microscopy", "imaging", "optics"],
            also: ["light microscope", "focus", "brightfield"]),
        "Pipette": SpecimenNote(
            caption: "Dispensing drops from a micropipette",
            note: "A micropipette uses a plunger to measure and dispense microliter volumes of liquid accurately, and is a staple of every bench.",
            topics: ["liquid handling"],
            also: ["micropipette", "Gilson", "microliter", "plunger"]),
        "Vortex": SpecimenNote(
            caption: "Tube shaking into a swirl",
            note: "A vortex mixer shakes a tube in a tight orbit so the liquid swirls into a vortex, quickly mixing or resuspending its contents.",
            topics: ["sample prep", "liquid handling"],
            also: ["vortexer", "mixer", "shaker"]),
        "Gel": SpecimenNote(
            caption: "Bands running through a gel",
            note: "Gel electrophoresis uses an electric field to pull charged molecules such as DNA through a gel, sorting them by size.",
            topics: ["electrophoresis", "separation"],
            also: ["agarose", "SDS-PAGE", "lanes", "bands"]),
        "Column": SpecimenNote(
            caption: "A mixture splitting on a column",
            note: "In column chromatography, a mixture travels down packed material and its components separate because they move at different speeds.",
            topics: ["chromatography", "separation", "chemistry"],
            also: ["eluent", "elution", "silica", "purification"]),
        "Bunsen burner": SpecimenNote(
            caption: "A flickering gas flame",
            note: "A Bunsen burner burns gas to give a controllable flame for heating, sterilizing tools and flaming glassware.",
            topics: ["lab life", "safety"],
            also: ["gas flame", "flame sterilization", "burner"]),
        "Serial dilution": SpecimenNote(
            caption: "Stock diluted tube by tube",
            note: "A serial dilution transfers a fixed volume from tube to tube, making each step a constant fold weaker for counting or standard curves.",
            topics: ["liquid handling", "sample prep"],
            also: ["dilution series", "tenfold", "stock", "diluent"]),
        "Flow cytometry": SpecimenNote(
            caption: "Cells crossing a laser, then plotted",
            note: "Flow cytometry sends cells single file past a laser, measuring light scatter and fluorescence of each one to classify populations.",
            topics: ["cell biology", "immunology", "measurement"],
            also: ["FACS", "cytometer", "scatter plot", "fluorescence"]),
        "Stir bar": SpecimenNote(
            caption: "A magnetic stir bar spinning",
            note: "A magnetic stirrer turns a magnet beneath the vessel, spinning a coated stir bar in the liquid to mix it steadily, hands-free.",
            topics: ["chemistry", "sample prep"],
            also: ["stirrer", "stir plate", "magnetic stirrer", "beaker"]),
        "Magnetic beads": SpecimenNote(
            caption: "Beads pulled to a magnet",
            note: "Magnetic beads coated to bind DNA, protein or cells are pulled to the tube wall by a magnet, so the liquid can be removed cleanly.",
            topics: ["separation", "sample prep"],
            also: ["magnetic separation", "Dynabeads", "pulldown", "SPRI"]),
        "Hemocytometer": SpecimenNote(
            caption: "Counting cells on a grid",
            note: "A hemocytometer is a slide with a ruled grid of known volume, used to count cells under a microscope and find their concentration.",
            topics: ["cell culture", "measurement", "microscopy"],
            also: ["cell counting", "counting chamber", "Neubauer"]),
        "Aliquoting": SpecimenNote(
            caption: "Splitting a stock into tubes",
            note: "Aliquoting divides a stock into small single-use portions, avoiding repeated freeze-thaw cycles and contamination of the original.",
            topics: ["liquid handling", "sample prep"],
            also: ["aliquot", "stock", "freeze-thaw"]),
        "Western transfer": SpecimenNote(
            caption: "Proteins moving from gel to membrane",
            note: "In Western blotting, an electric current moves separated proteins from a gel onto a membrane, where antibodies can then detect them.",
            topics: ["electrophoresis", "sample prep"],
            also: ["blotting", "immunoblot", "PVDF", "nitrocellulose"]),
        "Microfluidics": SpecimenNote(
            caption: "A droplet splitting and rejoining",
            note: "Microfluidics handles tiny fluid volumes in channels micrometers wide, enabling fast, low-reagent assays and sorting of cells or droplets.",
            topics: ["liquid handling", "physics"],
            also: ["lab on a chip", "droplet", "channel"]),
        "FACS": SpecimenNote(
            caption: "Sorting fluorescent cells into tubes",
            note: "FACS sorts cells by fluorescence: droplets holding a bright cell are given a charge and deflected by plates into a collection tube.",
            topics: ["cell biology", "separation"],
            also: ["cell sorting", "flow cytometry", "sorter", "fluorescence"]),
        "Spectrophotometer": SpecimenNote(
            caption: "Light dimming through a sample",
            note: "A spectrophotometer measures how much light a sample absorbs; absorbance rises with concentration, as the Beer-Lambert law describes.",
            topics: ["spectroscopy", "measurement"],
            also: ["absorbance", "Beer-Lambert", "OD", "photometer"]),
        "Microfuge": SpecimenNote(
            caption: "Cells pelleting in a small tube",
            note: "A microcentrifuge spins small tubes quickly to pellet cells or precipitates at the bottom, so the supernatant can be removed.",
            topics: ["centrifugation", "separation"],
            also: ["microcentrifuge", "Eppendorf", "pellet", "spin down"]),
        "Multichannel": SpecimenNote(
            caption: "Filling a row of wells at once",
            note: "A multichannel pipette carries several tips at once, so a full row of a microplate is filled in a single dispense.",
            topics: ["liquid handling"],
            also: ["8-channel", "12-channel", "96-well", "microplate"]),
        "Blot develop": SpecimenNote(
            caption: "Bands appearing on a blot",
            note: "A developed Western blot has bands whose position gives protein size and whose intensity reflects amount, checked against a loading control.",
            topics: ["imaging", "immunology"],
            also: ["Western blot", "loading control", "ladder", "chemiluminescence"]),
        "Orbital shaker": SpecimenNote(
            caption: "A platform swirling two flasks",
            note: "An orbital shaker moves flasks in a circle to mix and aerate cultures, keeping cells suspended and supplied with oxygen.",
            topics: ["cell culture", "microbiology"],
            also: ["shaker", "shaking incubator", "aeration"]),
        "Culture flask": SpecimenNote(
            caption: "Cells growing to cover a flask",
            note: "Adherent cells grow across the flask floor until confluent, then are detached and split into fresh flasks, a step called passaging.",
            topics: ["cell culture", "cell division"],
            also: ["passaging", "confluence", "T75", "tissue culture"]),
        "Thermocycler": SpecimenNote(
            caption: "PCR cycling hot, cool, warm",
            note: "A thermocycler cycles tubes through denaturing, annealing and extension temperatures, letting PCR double a DNA target each cycle.",
            topics: ["PCR"],
            also: ["PCR machine", "thermal cycler", "amplification", "denaturation"]),
        "Tube rack": SpecimenNote(
            caption: "Capped tubes dropping into a rack",
            note: "A tube rack holds sample tubes upright and organized on the bench, and closing the lids protects samples from spills and contamination.",
            topics: ["lab life", "sample prep"],
            also: ["microtube", "rack", "sample tubes"]),
        "Spin column": SpecimenNote(
            caption: "DNA binding to a silica membrane",
            note: "In a spin column, DNA binds a silica membrane in high-salt buffer while contaminants flow through, and pure DNA is then eluted.",
            topics: ["sample prep", "separation"],
            also: ["miniprep", "DNA extraction", "silica", "Qiagen"]),
        "Phase separation": SpecimenNote(
            caption: "Two liquids settling into layers",
            note: "A separatory funnel splits immiscible liquids such as water and an organic solvent, so a compound can be extracted into one layer.",
            topics: ["separation", "chemistry"],
            also: ["liquid-liquid extraction", "separatory funnel", "immiscible", "extraction"]),
        "Colony picking": SpecimenNote(
            caption: "Picking single colonies from agar",
            note: "Colony picking transfers single clones from an agar plate to fresh media so they can be grown, screened or sequenced.",
            topics: ["microbiology", "cloning"],
            also: ["clone", "agar", "pipette tip", "transformant"]),
        "NanoDrop": SpecimenNote(
            caption: "A microliter drop read for DNA",
            note: "A NanoDrop spectrophotometer measures DNA or RNA concentration from about a microliter, using absorbance that peaks at 260 nm.",
            topics: ["spectroscopy", "measurement"],
            also: ["A260", "nucleic acid quantification", "microvolume", "260 nm"]),
        "ELISA": SpecimenNote(
            caption: "Color deepening with more antigen",
            note: "An ELISA uses antibodies and an enzyme that makes a colored product, so color intensity reports how much target protein is present.",
            topics: ["immunology", "measurement"],
            also: ["immunoassay", "antibody", "antigen", "enzyme-linked"]),
        "Gel casting": SpecimenNote(
            caption: "Pouring a gel around a comb",
            note: "To cast an agarose gel, the molten agarose is poured around a comb, which leaves wells for loading samples once it sets.",
            topics: ["electrophoresis"],
            also: ["agarose", "comb", "wells", "gel tray"]),
        "DNA spooling": SpecimenNote(
            caption: "DNA threads winding onto a rod",
            note: "Adding cold ethanol makes DNA precipitate out of solution as visible white threads that can be wound onto a glass rod.",
            topics: ["sample prep", "genomics"],
            also: ["DNA extraction", "ethanol precipitation", "precipitation"]),
        "Homogenizer": SpecimenNote(
            caption: "Tissue ground to a fine suspension",
            note: "A Dounce homogenizer breaks up tissue or cells with a hand-driven pestle in a glass tube, gently releasing organelles or proteins.",
            topics: ["sample prep"],
            also: ["Dounce", "pestle", "lysis", "tissue grinder"]),
        "Sonicator": SpecimenNote(
            caption: "Sound waves bursting cells open",
            note: "A probe sonicator uses ultrasound to rupture cells, or shear DNA, through cavitation: tiny bubbles forming and collapsing.",
            topics: ["sample prep", "waves"],
            also: ["ultrasound", "cell lysis", "cavitation", "shearing"]),
        "Cryovial thaw": SpecimenNote(
            caption: "Thawing frozen cells in a water bath",
            note: "Frozen cells are thawed fast in a warm water bath to limit ice damage, then moved into fresh medium to dilute the cryoprotectant.",
            topics: ["cell culture"],
            also: ["cryopreservation", "frozen stock", "water bath", "DMSO"]),
        "Vacuum filtration": SpecimenNote(
            caption: "Liquid pulled through a filter",
            note: "Vacuum filtration uses suction to pull liquid through filter paper in a Büchner funnel, quickly separating a solid from a solution.",
            topics: ["separation", "chemistry"],
            also: ["Büchner funnel", "filter", "suction", "filtrate"]),
        "Wash bottle": SpecimenNote(
            caption: "Squirting a rinse from a bottle",
            note: "A wash bottle gives a thin, controlled jet of water or solvent when squeezed, for rinsing glassware and washing down precipitates.",
            topics: ["lab life", "chemistry"],
            also: ["squirt bottle", "rinse", "ethanol", "water"]),
        "Racking tips": SpecimenNote(
            caption: "Fresh tips loaded into a rack",
            note: "Pipette tips are racked into boxes row by row so they can be picked up cleanly and kept sterile until used.",
            topics: ["liquid handling", "lab life"],
            also: ["pipette tips", "tip box", "refill", "sterile"]),
        "Tip on and off": SpecimenNote(
            caption: "Loading and ejecting a pipette tip",
            note: "A fresh tip is pressed onto the pipette for each sample and ejected into waste afterward, preventing cross-contamination.",
            topics: ["liquid handling"],
            also: ["tip ejector", "pipette tip", "contamination"]),
        "Multichannel tips": SpecimenNote(
            caption: "A row of tips loaded, then dropped",
            note: "A multichannel pipette picks up a full row of tips in one press and ejects them together, which speeds up plate work.",
            topics: ["liquid handling"],
            also: ["tip box", "8-channel", "12-channel"]),
        "Pipette mixing": SpecimenNote(
            caption: "Mixing by pipetting up and down",
            note: "Pulling liquid up and down in a pipette tip mixes layers or suspensions evenly, a gentler alternative to vortexing.",
            topics: ["liquid handling", "sample prep"],
            also: ["pipetting", "triturate", "mix", "resuspend"]),
        "Aspirator": SpecimenNote(
            caption: "Sucking spent medium off a dish",
            note: "A vacuum aspirator removes spent medium from culture dishes; tilting the dish pools the liquid so the cells stay undisturbed.",
            topics: ["cell culture", "liquid handling"],
            also: ["vacuum aspiration", "Pasteur pipette", "medium", "tissue culture"]),
        "Liquid handler": SpecimenNote(
            caption: "A robot filling a plate",
            note: "A liquid-handling robot moves pipetting heads along a gantry to dispense samples and reagents into plates accurately and tirelessly.",
            topics: ["liquid handling"],
            also: ["pipetting robot", "automation", "gantry", "high-throughput"]),
        "Gel imager": SpecimenNote(
            caption: "Glowing DNA bands on a light box",
            note: "A transilluminator lights a stained gel so the DNA bands glow and can be photographed to check their size and amount.",
            topics: ["imaging", "electrophoresis"],
            also: ["UV box", "ethidium bromide", "gel doc", "transilluminator"]),
        "Cuvette": SpecimenNote(
            caption: "A cuvette read in a photometer",
            note: "A cuvette is a small transparent cell that holds a sample in a photometer, whose absorbance reading gives concentration or cell density.",
            topics: ["spectroscopy", "measurement"],
            also: ["spectrophotometer", "OD600", "absorbance", "optical density"]),
        "Transfer sandwich": SpecimenNote(
            caption: "Stacking gel and membrane layers",
            note: "A Western transfer sandwich stacks sponge, filter paper, gel and membrane so proteins move from the gel onto the membrane under current.",
            topics: ["electrophoresis", "sample prep"],
            also: ["Western blot", "transfer cassette", "blotting"]),
        "Gel loading": SpecimenNote(
            caption: "Sample sinking into a gel well",
            note: "Samples mixed with dense loading dye sink into the gel wells beneath the buffer, so they can be run without floating away.",
            topics: ["electrophoresis", "liquid handling"],
            also: ["loading dye", "wells", "agarose", "buffer"]),
        "Fly flip": SpecimenNote(
            caption: "Tapping flies into a fresh vial",
            note: "Drosophila stocks are flipped regularly into vials of fresh food, which keeps each fly line going from one generation to the next.",
            topics: ["model organisms"],
            also: ["Drosophila", "fruit flies", "fly stock", "fly food"]),
        "Coverslip": SpecimenNote(
            caption: "Lowering a coverslip on a section",
            note: "A coverslip is lowered over mounting medium on a slide to flatten the sample, protect it and allow sharp imaging without trapped bubbles.",
            topics: ["microscopy", "sample prep"],
            also: ["mounting medium", "slide", "mountant", "bubble"]),
        "Freezer box": SpecimenNote(
            caption: "Cryovials stored in a freezer box",
            note: "Cryovials are kept in gridded boxes in freezer racks so samples can be organized, logged and found again.",
            topics: ["lab life", "sample prep"],
            also: ["cryobox", "-80", "freezer", "storage"]),
        "Dish scrape": SpecimenNote(
            caption: "Scraping cells off a dish",
            note: "A cell scraper lifts adherent cells off a dish by force rather than trypsin, useful when surface proteins must stay intact or for lysates.",
            topics: ["cell culture", "sample prep"],
            also: ["cell scraper", "adherent cells", "monolayer", "harvest"]),
        "Plaque assay": SpecimenNote(
            caption: "Counting clear spots in a cell lawn",
            note: "A plaque assay counts virus: each infectious particle kills nearby cells to leave a clear plaque, so counts across dilutions give the titer.",
            topics: ["virology", "microbiology"],
            also: ["plaque-forming units", "PFU", "titer", "viral titration"]),
        "Slide staining": SpecimenNote(
            caption: "Slides dipped through stain jars",
            note: "Slides are moved through jars of alcohol, stain and water to color tissue, so structures stand out under the microscope.",
            topics: ["microscopy", "sample prep"],
            also: ["histology", "H&E", "staining", "Coplin jar"]),
        "Histology slide": SpecimenNote(
            caption: "Tissue section seen through a lens",
            note: "A histology slide carries a stained, thin tissue section whose structure, such as a gland ringed by cells, shows how tissue is organized.",
            topics: ["microscopy", "cell biology"],
            also: ["tissue section", "H&E", "pathology", "gland"]),
        "Cryosection": SpecimenNote(
            caption: "Slicing frozen tissue into sections",
            note: "A cryostat is a microtome inside a refrigerated chamber that cuts thin sections of frozen tissue, ready for staining or antibody labeling.",
            topics: ["sample prep", "microscopy"],
            also: ["cryostat", "microtome", "frozen section", "tissue"]),
        "Radiolabel": SpecimenNote(
            caption: "Geiger counter finding a hot tube",
            note: "A Geiger counter detects ionizing radiation as clicks and needle deflection, and is used to survey benches for radiolabeled spills.",
            topics: ["safety", "physics"],
            also: ["Geiger-Müller", "radioactivity", "survey meter", "radioisotope"]),
        "Ice bucket": SpecimenNote(
            caption: "Tubes kept cold in ice",
            note: "Samples, enzymes and lysates are kept on ice to slow degradation, enzyme activity and unwanted reactions while work goes on.",
            topics: ["lab life", "sample prep"],
            also: ["on ice", "ice", "cold", "ice bucket"]),
        "Plate reader drawer": SpecimenNote(
            caption: "A plate sliding into a reader",
            note: "A plate reader takes a microplate on a motorized tray, measures each well inside, and then reports the readings.",
            topics: ["measurement"],
            also: ["microplate", "tray", "absorbance", "plate reader"]),
        "Pipette volume": SpecimenNote(
            caption: "Dialing a volume on a pipette",
            note: "Micropipettes are set with a dial that shows volume in microliters, so one pipette covers a defined range such as 20 to 200 µL.",
            topics: ["liquid handling"],
            also: ["micropipette", "P200", "microliter", "volume"]),
        "Agar pour": SpecimenNote(
            caption: "Pouring molten agar into dishes",
            note: "Molten agar medium is poured into Petri dishes and left to set, making solid plates on which microbes grow into colonies.",
            topics: ["microbiology"],
            also: ["agar plates", "pouring plates", "media", "LB agar"]),
        "Blot rocker": SpecimenNote(
            caption: "Rocking a blot in wash buffer",
            note: "A rocking platform gently tilts a membrane in wash or antibody solution so it is bathed evenly during blotting steps.",
            topics: ["sample prep", "immunology"],
            also: ["platform rocker", "Western blot", "membrane", "wash"]),
        "Tube labels": SpecimenNote(
            caption: "Labeling tubes with a marker",
            note: "Labeling every tube clearly with sample, date and initials prevents mix-ups and keeps samples traceable.",
            topics: ["lab life"],
            also: ["marker", "Sharpie", "labels", "microfuge tube"]),
        "Label tape": SpecimenNote(
            caption: "Wrapping label tape on tubes",
            note: "Lab tape wraps around tubes and flasks to give a writable label that stays on through cold storage and peels off when done.",
            topics: ["lab life"],
            also: ["lab tape", "labeling", "tube", "marker"]),
        "Sequencing dropbox": SpecimenNote(
            caption: "Tubes dropped off for sequencing",
            note: "A sequencing core accepts drop-off tubes, such as plasmids or PCR products, then runs them and returns the DNA sequence.",
            topics: ["sequencing", "lab life"],
            also: ["Sanger", "sequencing core", "plasmid", "sample submission"]),
        "pH meter": SpecimenNote(
            caption: "Reading the pH of a solution",
            note: "A pH meter measures the acidity of a solution with a glass electrode; adding acid lowers the reading, and it is calibrated with buffers.",
            topics: ["chemistry", "measurement"],
            also: ["acidity", "electrode", "buffer", "pH probe"]),
        "Drying rack": SpecimenNote(
            caption: "Washed glassware drying on pegs",
            note: "Washed glassware is inverted on pegs to drain and air-dry, so it is clean and free of residue before reuse.",
            topics: ["lab life"],
            also: ["glassware", "pegboard", "washing", "drain"]),
        "Inoculation": SpecimenNote(
            caption: "Seeding broth with a colony",
            note: "To inoculate a culture, a sterile inoculating loop carries a colony into broth, where the bacteria multiply and turn it cloudy.",
            topics: ["microbiology"],
            also: ["inoculating loop", "broth", "starter culture", "overnight culture"]),
        "Roller drum": SpecimenNote(
            caption: "Culture tubes rolling on a drum",
            note: "A roller drum slowly turns culture tubes so cells stay suspended and aerated, a common way to grow small bacterial cultures.",
            topics: ["microbiology", "cell culture"],
            also: ["tube roller", "rotator", "culture tubes", "aeration"]),
        "Shaker platform": SpecimenNote(
            caption: "Swirling cultures in an incubator",
            note: "A shaking incubator warms flasks while swirling them, giving bacteria or yeast heat and oxygen to grow quickly.",
            topics: ["microbiology", "cell culture"],
            also: ["shaking incubator", "37 °C", "flasks", "aeration"]),
        "Bubble centrifuge": SpecimenNote(
            caption: "A quick spin bringing drops down",
            note: "A mini centrifuge gives a quick spin that pulls droplets from the tube walls and caps down to the bottom before the liquid is used.",
            topics: ["centrifugation"],
            also: ["mini centrifuge", "quick spin", "fixed-angle rotor", "spin down"]),
        "Microwave agarose": SpecimenNote(
            caption: "Melting agarose in a microwave",
            note: "Agarose powder in buffer is heated in a microwave until it dissolves into a clear liquid, ready to pour into a gel tray.",
            topics: ["electrophoresis", "lab life"],
            also: ["agarose", "microwave", "gel prep", "melting"]),
        "Heat shock": SpecimenNote(
            caption: "A heat jolt pushing DNA into cells",
            note: "In heat-shock transformation, competent bacteria on ice are briefly warmed to 42 °C, which lets plasmid DNA slip into the cells.",
            topics: ["cloning", "microbiology"],
            also: ["transformation", "competent cells", "plasmid", "42 °C"]),
        "Electroporation": SpecimenNote(
            caption: "An electric pulse opening cells",
            note: "Electroporation applies a brief high-voltage pulse that opens pores in cell membranes, letting DNA or other molecules enter.",
            topics: ["cloning", "membranes"],
            also: ["transformation", "transfection", "plasmid", "electric pulse"]),
        "Quadrant streak": SpecimenNote(
            caption: "Streaking in four quadrants",
            note: "Streaking in four quadrants, flaming the inoculating loop between them, thins bacteria so the last quadrant gives single, isolated colonies.",
            topics: ["microbiology"],
            also: ["streak plate", "isolation", "pure culture", "colonies"]),
        "Colonies to wells": SpecimenNote(
            caption: "Colonies picked into culture wells",
            note: "Picked colonies are put into separate wells of broth and grown, so each clone can be screened or sequenced.",
            topics: ["microbiology", "cloning"],
            also: ["clone screening", "colony picking", "96-well", "broth"]),
        "Pellet resuspend": SpecimenNote(
            caption: "Breaking up a pellet by pipetting",
            note: "After centrifugation, a pellet is resuspended by pipetting up and down in buffer or medium until the cells are evenly dispersed.",
            topics: ["sample prep", "liquid handling"],
            also: ["resuspension", "pellet", "triturate", "cells"]),
        "Swinging bucket": SpecimenNote(
            caption: "Buckets swinging out in a rotor",
            note: "A swinging-bucket rotor, such as the SW 41, tilts tubes horizontal as it spins so particles separate down a density gradient.",
            topics: ["centrifugation", "separation"],
            also: ["ultracentrifuge", "SW 41", "Beckman", "density gradient"]),
        "Sucrose gradient": SpecimenNote(
            caption: "Pouring a density gradient",
            note: "A sucrose gradient layers solutions from light to dense, so particles later spun through it separate by size or density.",
            topics: ["centrifugation", "separation"],
            also: ["density gradient", "gradient maker", "sucrose", "ultracentrifuge"]),
        "Fractions": SpecimenNote(
            caption: "Collecting a gradient in fractions",
            note: "Fraction collecting drips a gradient from the tube into a row of tubes, so each slice can be assayed to find where a component sits.",
            topics: ["centrifugation", "separation"],
            also: ["fractionation", "gradient", "fraction collector"]),
        "Media change": SpecimenNote(
            caption: "Swapping spent medium for fresh",
            note: "Cells need fresh medium every few days, so spent medium is removed and replaced to restore nutrients and clear away waste.",
            topics: ["cell culture"],
            also: ["medium change", "feeding", "culture medium", "tissue culture"]),
        "PFA ampoule": SpecimenNote(
            caption: "Cracking open a fixative ampoule",
            note: "Sealed ampoules hold fresh formaldehyde made from paraformaldehyde (PFA), which fixes cells and tissue by cross-linking their proteins.",
            topics: ["sample prep", "microscopy"],
            also: ["paraformaldehyde", "formaldehyde", "fixative", "fixation"]),
        "Calipers": SpecimenNote(
            caption: "Measuring a sample with calipers",
            note: "Digital calipers measure an object's size to a fraction of a millimeter, for example a tumor, a tissue sample or a part.",
            topics: ["measurement"],
            also: ["digital calipers", "vernier", "tumor size", "length"]),
        "Vortex from above": SpecimenNote(
            caption: "Looking down on a swirling tube",
            note: "Seen from above, vortex mixing drives the liquid into a swirl with a central dimple, mixing the tube's contents quickly.",
            topics: ["sample prep"],
            also: ["vortex mixer", "vortexer", "swirl", "mixing"]),
        "Bead cleanup": SpecimenNote(
            caption: "Cleaning up DNA with magnetic beads",
            note: "A bead cleanup binds DNA to magnetic beads, washes off contaminants with ethanol and elutes pure DNA, as in sequencing library prep.",
            topics: ["sample prep", "sequencing"],
            also: ["SPRI", "AMPure", "library prep", "magnetic beads"]),
        "Kirby-Bauer": SpecimenNote(
            caption: "Antibiotic disks making clear zones",
            note: "The Kirby-Bauer test puts antibiotic disks on a bacterial lawn; clear zones show growth inhibition, so zone size shows susceptibility.",
            topics: ["microbiology", "medicine"],
            also: ["disk diffusion", "antibiotic susceptibility", "zone of inhibition", "antibiogram"]),
        "Patch clamp": SpecimenNote(
            caption: "Recording currents from one cell",
            note: "Patch clamp records ion currents across a cell membrane through a glass pipette sealed onto the cell, revealing ion channel activity.",
            topics: ["neuroscience", "membranes"],
            also: ["electrophysiology", "ion channel", "whole-cell", "gigaseal"]),
        "Light sheet": SpecimenNote(
            caption: "A sheet of light slicing an embryo",
            note: "Light-sheet microscopy lights one thin plane of a specimen at a time, imaging large live samples such as embryos fast and gently.",
            topics: ["microscopy", "imaging", "development"],
            also: ["LSFM", "SPIM", "embryo", "optical sectioning"]),
        "Glove box": SpecimenNote(
            caption: "Working inside a sealed glove box",
            note: "A glove box lets hands work through sealed gloves in a controlled atmosphere, such as oxygen-free gas for air-sensitive materials.",
            topics: ["chemistry", "safety"],
            also: ["anaerobic chamber", "inert atmosphere", "airlock", "glovebox"]),
        "Rotary evaporator": SpecimenNote(
            caption: "Solvent evaporating and condensing",
            note: "A rotary evaporator turns a flask in a warm bath under vacuum, so solvent evaporates, condenses on a coil and is collected separately.",
            topics: ["chemistry", "separation"],
            also: ["rotavap", "rotovap", "solvent removal", "condenser"]),
        "Freeze-dryer": SpecimenNote(
            caption: "Ice turning to powder under vacuum",
            note: "A freeze-dryer removes water by sublimation under vacuum, leaving a dry, stable powder that preserves delicate samples.",
            topics: ["sample prep", "thermodynamics"],
            also: ["lyophilizer", "lyophilization", "sublimation", "vacuum"]),
        "Liquid nitrogen": SpecimenNote(
            caption: "Pouring liquid nitrogen, fog and all",
            note: "Liquid nitrogen boils at -196 °C and is used to flash-freeze samples and cool equipment; handling needs gloves and eye protection.",
            topics: ["safety", "lab life"],
            also: ["cryogen", "LN2", "-196", "flash freezing"]),
        "Analytical balance": SpecimenNote(
            caption: "Weighing a sample very precisely",
            note: "An analytical balance weighs to about 0.1 mg inside a draft-proof enclosure, and a stability mark shows when the reading has settled.",
            topics: ["measurement", "chemistry"],
            also: ["balance", "weighing", "milligram", "scale"]),
        "6-well plate": SpecimenNote(
            caption: "Cells growing in a 6-well plate",
            note: "A 6-well plate holds six separate cultures, so cells can be grown under different conditions side by side until near confluence.",
            topics: ["cell culture"],
            also: ["multiwell plate", "six-well", "confluence", "tissue culture"]),
        "Serological pipette": SpecimenNote(
            caption: "Pipetting media with a pipette aid",
            note: "A serological pipette with a pipette controller transfers milliliter volumes of media or buffer, such as when filling culture flasks.",
            topics: ["liquid handling", "cell culture"],
            also: ["pipette aid", "pipette controller", "media", "milliliter"]),
        "Mortar and pestle": SpecimenNote(
            caption: "Grinding frozen leaves to powder",
            note: "Tissue frozen in liquid nitrogen turns brittle and is ground to a fine powder, to extract DNA, RNA or protein from tough plant material.",
            topics: ["sample prep", "plants"],
            also: ["liquid nitrogen", "grinding", "plant tissue", "extraction"]),
        "Parafilm": SpecimenNote(
            caption: "Sealing a flask with Parafilm",
            note: "Parafilm is a stretchy paraffin film that clings to itself when stretched, sealing tubes and flasks against evaporation and contamination.",
            topics: ["lab life"],
            also: ["sealing film", "stretch", "flask", "seal"]),
        "Dialysis bag": SpecimenNote(
            caption: "Small molecules leaving a bag",
            note: "Dialysis uses a semipermeable membrane that lets small molecules such as salts pass out while keeping large proteins inside.",
            topics: ["separation", "membranes"],
            also: ["semipermeable membrane", "buffer exchange", "desalting", "diffusion"]),
        "Round coverslip": SpecimenNote(
            caption: "Placing a round coverslip on a slide",
            note: "Round coverslips, often carrying cultured cells, are mounted on a slide in mountant so the sample is flat and ready for imaging.",
            topics: ["microscopy", "sample prep"],
            also: ["coverslip", "mounting", "forceps", "immunofluorescence"]),
        "Gel extraction": SpecimenNote(
            caption: "Cutting a DNA band out of a gel",
            note: "A band of the right size is cut from a gel on a blue-light box and its DNA purified, to isolate a specific fragment for cloning.",
            topics: ["electrophoresis", "cloning"],
            also: ["gel purification", "blue light", "band", "scalpel"]),
        "Plate sealing": SpecimenNote(
            caption: "Sealing film pressed on a plate",
            note: "Adhesive film sealed over a microplate prevents evaporation, spills and cross-contamination while samples are stored or incubated.",
            topics: ["lab life", "sample prep"],
            also: ["plate seal", "microplate", "film", "roller"]),
        "Coomassie destain": SpecimenNote(
            caption: "Dye washing from a protein gel",
            note: "Coomassie stains all the protein in a gel blue; destaining washes dye from the background so the protein bands stand out.",
            topics: ["electrophoresis", "imaging"],
            also: ["Coomassie blue", "SDS-PAGE", "protein gel", "staining"]),
        "Bradford assay": SpecimenNote(
            caption: "Protein amount read from a color",
            note: "The Bradford assay measures protein concentration: the dye turns bluer with more protein, and unknowns are read off a standard curve.",
            topics: ["measurement", "spectroscopy"],
            also: ["protein assay", "standard curve", "Coomassie dye", "BSA"]),
        "Colony formation": SpecimenNote(
            caption: "Single cells growing into colonies",
            note: "A clonogenic assay tests whether single cells can form colonies, showing how a drug or radiation dose reduces survival.",
            topics: ["cell culture", "medicine"],
            also: ["clonogenic assay", "crystal violet", "survival", "radiation"]),
        "Freezing cells": SpecimenNote(
            caption: "Slow-cooling cells in a freezing jar",
            note: "Cells are frozen slowly, about 1 °C per minute, in a cooling container so ice does not damage them before storage at -80 °C.",
            topics: ["cell culture", "sample prep"],
            also: ["cryopreservation", "Mr. Frosty", "cryovial", "DMSO"]),
        "Cell strainer": SpecimenNote(
            caption: "Straining clumps from cells",
            note: "A cell strainer is a fine mesh that passes single cells and catches clumps and debris, giving a clean suspension for counting or flow.",
            topics: ["sample prep", "cell culture"],
            also: ["cell strainer", "filter", "single-cell suspension", "mesh"]),
        "Weigh boat": SpecimenNote(
            caption: "Spooning powder into a weigh boat",
            note: "Powder is spooned into a small weigh boat on a balance to measure out an exact mass before it is dissolved or used.",
            topics: ["measurement", "chemistry"],
            also: ["spatula", "balance", "weighing", "powder"]),
        "Tube uncapping": SpecimenNote(
            caption: "A snap-cap tube popping open",
            note: "Microcentrifuge tubes have a hinged snap cap that pops open for pipetting and clicks shut again to seal the sample.",
            topics: ["lab life", "sample prep"],
            also: ["microtube", "Eppendorf tube", "snap cap", "1.5 mL"]),
        "Vacuum desiccator": SpecimenNote(
            caption: "Drying samples over silica gel",
            note: "A vacuum desiccator removes air and moisture, with silica gel soaking up water, to keep samples dry or dry them gently.",
            topics: ["chemistry", "sample prep"],
            also: ["desiccant", "silica gel", "vacuum", "drying"]),
        "Coffee": SpecimenNote(
            caption: "Filling a mug from the pot",
            note: "Coffee is the unofficial fuel of long lab days: caffeine blocks adenosine receptors in the brain, which wards off sleepiness.",
            topics: ["lab life", "neuroscience"],
            also: ["caffeine", "mug", "break", "adenosine"]),
        "Notebook": SpecimenNote(
            caption: "Writing up the day's results",
            note: "A lab notebook records what was done and found, dated and signed, so experiments can be reproduced and results traced.",
            topics: ["lab life"],
            also: ["ELN", "record keeping", "reproducibility", "protocol"]),
        "Gloves": SpecimenNote(
            caption: "Pulling lab gloves on and off",
            note: "Disposable gloves protect hands from chemicals and microbes, and samples from skin, and are removed inside out to contain contamination.",
            topics: ["safety", "lab life"],
            also: ["nitrile", "PPE", "personal protective equipment", "latex"]),
        "Biohazard": SpecimenNote(
            caption: "Bagging biohazard waste",
            note: "Biohazard waste such as used tips and cultures goes into marked bags, then is decontaminated, often by autoclaving, before disposal.",
            topics: ["safety"],
            also: ["biohazard bag", "waste", "disposal", "decontamination"]),
        "Printer": SpecimenNote(
            caption: "A page printing out with a plot",
            note: "Printers turn data plots and protocols into paper copies that get taped into notebooks and pinned up near the bench.",
            topics: ["lab life", "data"],
            also: ["printout", "figure", "protocol", "plot"]),
        "Autoclave": SpecimenNote(
            caption: "Sterilizing with pressurized steam",
            note: "An autoclave sterilizes media, glassware and waste with pressurized steam, typically at 121 °C for 15 to 30 minutes.",
            topics: ["safety", "microbiology"],
            also: ["sterilization", "steam", "121 °C", "pressure"]),
        "Incubator": SpecimenNote(
            caption: "A warm CO2 incubator for cells",
            note: "A CO₂ incubator holds cultures at 37 °C with 5% CO₂ and high humidity, mimicking the conditions cells experience in the body.",
            topics: ["cell culture"],
            also: ["CO2 incubator", "37 °C", "tissue culture", "humidified"]),
        "Freezer frost": SpecimenNote(
            caption: "Scraping frost off a -80 freezer",
            note: "Freezers at -80 °C store samples long term, and frost builds up each time the door opens, so it has to be scraped away.",
            topics: ["lab life"],
            also: ["-80 freezer", "ultra-low freezer", "frost", "defrost"]),
        "Biosafety cabinet": SpecimenNote(
            caption: "Working in a biosafety cabinet",
            note: "A biosafety cabinet sends filtered air downward and inward to protect the user, the sample and the room while handling cells and microbes.",
            topics: ["safety", "cell culture"],
            also: ["laminar flow hood", "tissue culture hood", "BSC", "HEPA"]),
        "Media bottle": SpecimenNote(
            caption: "Taking medium from a square bottle",
            note: "Sterile culture medium is taken from its bottle with a serological pipette, using aseptic technique to keep the cap and contents clean.",
            topics: ["cell culture", "liquid handling"],
            also: ["media bottle", "aseptic technique", "serological pipette", "medium"]),
        "Water bath": SpecimenNote(
            caption: "Warming tubes in a water bath",
            note: "A water bath holds samples at a set temperature, such as 37 °C, for warming medium, thawing reagents or incubating reactions.",
            topics: ["lab life", "sample prep"],
            also: ["37 °C", "incubation", "warming", "float"]),
        "Typing": SpecimenNote(
            caption: "Writing up a paper",
            note: "Writing a paper is where experiments become a publication: methods, results and figures laid out so others can check and build on them.",
            topics: ["lab life"],
            also: ["manuscript", "publication", "paper", "writing"]),
        "Laptop": SpecimenNote(
            caption: "A sticker-covered laptop opening",
            note: "Laptops are where much of a scientist's analysis and writing happens, and stickers from conferences or favorite organisms are common.",
            topics: ["lab life", "data"],
            also: ["stickers", "computer", "analysis", "notebook computer"]),
        "Gas cylinders": SpecimenNote(
            caption: "Connecting CO2 to an incubator",
            note: "A regulator on a CO₂ cylinder steps its high pressure down to a safe, steady flow that feeds an incubator.",
            topics: ["lab life", "safety"],
            also: ["regulator", "compressed gas", "CO2", "gauge"]),
        "Sharps bin": SpecimenNote(
            caption: "Disposing of a used syringe",
            note: "Used needles and blades go into rigid, puncture-proof sharps containers, never ordinary trash, to prevent needlestick injuries.",
            topics: ["safety"],
            also: ["sharps container", "needle", "syringe", "needlestick"]),
        "Beer fermentation": SpecimenNote(
            caption: "Yeast fermenting wort into beer",
            note: "In brewing, yeast ferments the sugars in wort into ethanol and carbon dioxide, and the airlock lets gas out but keeps air away.",
            topics: ["food science", "metabolism"],
            also: ["brewing", "yeast", "krausen", "carboy"]),
        "Sourdough": SpecimenNote(
            caption: "Dough rising from wild yeast",
            note: "Sourdough rises as wild yeast and lactic acid bacteria ferment sugars, making carbon dioxide that is trapped as bubbles in the dough.",
            topics: ["food science", "microbiology"],
            also: ["starter", "fermentation", "yeast", "lactobacillus"]),
        "Yogurt": SpecimenNote(
            caption: "Bacteria turning milk to yogurt",
            note: "Yogurt cultures such as Lactobacillus and Streptococcus ferment lactose to lactic acid, which curdles milk proteins into a gel.",
            topics: ["food science", "microbiology"],
            also: ["fermentation", "lactic acid", "lactose", "starter culture"]),
        "Cheese making": SpecimenNote(
            caption: "Milk setting into curds and whey",
            note: "Cheesemaking uses rennet to clot milk into curd; cutting the curd lets whey drain out, which firms and shapes the cheese.",
            topics: ["food science", "enzymes"],
            also: ["rennet", "curd", "whey", "chymosin"]),
        "Chromatin breathing": SpecimenNote(
            caption: "Chromatin packing and loosening",
            note: "Chromatin shifts between tightly packed and open states, which controls how accessible DNA is to the transcription machinery.",
            topics: ["transcription", "cell biology"],
            also: ["epigenetics", "nucleosome", "histone", "euchromatin"]),
        "Polymerase": SpecimenNote(
            caption: "An enzyme copying a DNA strand",
            note: "DNA polymerase reads a template strand and adds matching nucleotides to build a new complementary strand with high fidelity.",
            topics: ["replication", "enzymes"],
            also: ["DNA polymerase", "template", "nucleotide"]),
        "Kinesin": SpecimenNote(
            caption: "Motor protein walking a microtubule",
            note: "Kinesin is a motor protein that carries cargo toward the plus end of a microtubule, taking 8 nm steps powered by ATP.",
            topics: ["cell biology", "transport"],
            also: ["motor protein", "microtubule", "cargo"]),
        "Helix": SpecimenNote(
            caption: "DNA's twisted double strand turning",
            note: "DNA is a double helix of two strands joined by base pairs, A with T and G with C, which store genetic information.",
            topics: ["genomics", "chemistry"],
            also: ["DNA", "double helix", "base pair", "Watson-Crick"]),
        "Enzyme": SpecimenNote(
            caption: "An enzyme grabbing a substrate",
            note: "Enzymes are biological catalysts that bind a substrate in their active site and speed its conversion into products.",
            topics: ["enzymes", "metabolism"],
            also: ["catalyst", "substrate", "active site", "induced fit"]),
        "CRISPR": SpecimenNote(
            caption: "Cas9 cutting DNA, then a repair",
            note: "CRISPR-Cas9 uses a guide RNA to cut DNA at a chosen site, and repair from a donor template then writes in a new sequence.",
            topics: ["gene editing"],
            also: ["Cas9", "sgRNA", "genome editing", "HDR"]),
        "Chaperone": SpecimenNote(
            caption: "A chaperonin folding a protein",
            note: "Chaperonins such as GroEL/GroES are barrels that enclose an unfolded protein and help it fold correctly, using ATP.",
            topics: ["protein folding"],
            also: ["GroEL", "GroES", "chaperonin", "heat shock protein"]),
        "Nucleosome": SpecimenNote(
            caption: "DNA wrapped around a histone core",
            note: "A nucleosome is about 147 base pairs of DNA wrapped roughly 1.65 turns around a histone octamer, the basic unit of chromatin.",
            topics: ["genomics", "cell biology"],
            also: ["histone", "chromatin", "octamer"]),
        "Proteasome": SpecimenNote(
            caption: "A barrel chewing up proteins",
            note: "The proteasome is a barrel-shaped protease complex that degrades unneeded or damaged proteins into short peptides.",
            topics: ["enzymes", "cell biology"],
            also: ["protease", "protein degradation", "ubiquitin"]),
        "PCR": SpecimenNote(
            caption: "DNA doubling with each cycle",
            note: "PCR repeatedly melts DNA, anneals primers and extends them with a polymerase, doubling a target sequence every cycle.",
            topics: ["PCR"],
            also: ["polymerase chain reaction", "primers", "thermocycler", "amplification"]),
        "Folding": SpecimenNote(
            caption: "A chain collapsing into a bundle",
            note: "Protein folding is how an amino acid chain collapses, burying its oily residues in a core, into a compact functional 3D structure.",
            topics: ["protein folding", "protein structure"],
            also: ["hydrophobic collapse", "helix bundle", "tertiary structure"]),
        "Helicase": SpecimenNote(
            caption: "A ring enzyme unzipping DNA",
            note: "Helicases are motor enzymes, often ring-shaped like DnaB, that use ATP to unwind double-stranded DNA for replication and repair.",
            topics: ["replication", "enzymes"],
            also: ["unwinding", "DnaB", "DNA unzipping"]),
        "VLP assembly": SpecimenNote(
            caption: "A virus-like shell assembling",
            note: "Virus-like particles are empty protein shells that self-assemble from capsid proteins, used in vaccines and as delivery vehicles.",
            topics: ["virology", "medicine"],
            also: ["capsid", "VLP", "vaccine", "self-assembly"]),
        "DNA repair": SpecimenNote(
            caption: "Filling and sealing a DNA gap",
            note: "Cells constantly repair DNA damage; a polymerase fills the gap in one strand and DNA ligase seals the nick that remains.",
            topics: ["DNA repair"],
            also: ["polymerase", "ligase", "nick", "gap filling"]),
        "Ribosome": SpecimenNote(
            caption: "Reading mRNA codon by codon",
            note: "The ribosome reads mRNA three bases (one codon) at a time and links the matching amino acids into a growing protein chain.",
            topics: ["translation"],
            also: ["mRNA", "codon", "protein synthesis", "peptide"]),
        "Restriction digest": SpecimenNote(
            caption: "A plasmid cut open to sticky ends",
            note: "A restriction enzyme cuts DNA at a specific sequence; staggered cuts leave sticky ends that make fragments easy to join in cloning.",
            topics: ["cloning", "enzymes"],
            also: ["restriction enzyme", "EcoRI", "plasmid", "sticky ends"]),
        "tRNA": SpecimenNote(
            caption: "An amino acid loaded onto tRNA",
            note: "A tRNA is charged when a synthetase attaches its matching amino acid to the 3′ end, ready to deliver it to the ribosome.",
            topics: ["translation", "RNA"],
            also: ["aminoacyl-tRNA", "cloverleaf", "synthetase", "charging"]),
        "RNA splicing": SpecimenNote(
            caption: "An intron looping out and removed",
            note: "Splicing removes introns from pre-mRNA and joins the exons together, producing the mature message that is translated into protein.",
            topics: ["RNA", "transcription"],
            also: ["intron", "exon", "spliceosome", "pre-mRNA"]),
        "Nanopore": SpecimenNote(
            caption: "DNA threading through a pore",
            note: "Nanopore sequencing reads DNA or RNA as a single strand passes through a pore, the few bases inside it shifting the ionic current.",
            topics: ["sequencing"],
            also: ["Oxford Nanopore", "long reads", "MinION"]),
        "PAM patrol": SpecimenNote(
            caption: "Cas9 scanning DNA for a PAM",
            note: "Cas9 only opens DNA next to a short PAM motif (NGG for SpCas9), so it scans for that sequence before checking the guide match.",
            topics: ["gene editing"],
            also: ["PAM", "Cas9", "NGG", "target search"]),
        "R-loop": SpecimenNote(
            caption: "Guide RNA pairing with target DNA",
            note: "In the R-loop, Cas9's guide RNA pairs with the target strand while the other strand is displaced, readying the HNH domain to cut.",
            topics: ["gene editing"],
            also: ["Cas9", "guide RNA", "HNH", "R-loop"]),
        "Double cut": SpecimenNote(
            caption: "Cas9 cutting both DNA strands",
            note: "Cas9 cuts the two DNA strands with two nuclease domains, HNH on the target strand and RuvC on the other, making a double-strand break.",
            topics: ["gene editing"],
            also: ["HNH", "RuvC", "double-strand break", "DSB"]),
        "Base edit": SpecimenNote(
            caption: "Swapping one DNA base, no break",
            note: "Base editors chemically convert one DNA base to another, such as C to T, without making a double-strand break.",
            topics: ["gene editing"],
            also: ["base editor", "deaminase", "point mutation", "ABE"]),
        "Prime edit": SpecimenNote(
            caption: "Writing a new sequence at a nick",
            note: "Prime editing uses a nickase Cas9, reverse transcriptase and a pegRNA template to write a small edit into DNA without a double-strand break.",
            topics: ["gene editing"],
            also: ["pegRNA", "reverse transcriptase", "nickase", "search and replace"]),
        "Topoisomerase": SpecimenNote(
            caption: "Relieving twist in coiled DNA",
            note: "Topoisomerases cut and reseal DNA so it can swivel or pass through itself, relieving supercoiling from replication and transcription.",
            topics: ["replication", "enzymes"],
            also: ["supercoiling", "gyrase", "DNA topology"]),
        "Proteasome threading": SpecimenNote(
            caption: "Tagged protein fed into a barrel",
            note: "The proteasome strips the ubiquitin tag from a tagged protein, unfolds it and threads it into its core to cut it into peptides.",
            topics: ["enzymes", "cell biology"],
            also: ["ubiquitin", "26S proteasome", "protein degradation", "deubiquitinase"]),
        "Condensin": SpecimenNote(
            caption: "A ring reeling in a loop of DNA",
            note: "Condensin is a ring-shaped motor that extrudes loops of chromatin, compacting chromosomes for cell division.",
            topics: ["cell division", "cell biology"],
            also: ["loop extrusion", "SMC complex", "chromosome compaction"]),
        "Mismatch repair": SpecimenNote(
            caption: "Cutting out and fixing a mispair",
            note: "Mismatch repair spots wrongly paired bases left by replication, removes the stretch of new strand around them and fills it in correctly.",
            topics: ["DNA repair"],
            also: ["MutS", "MutL", "mispair", "replication errors"]),
        "Recombination": SpecimenNote(
            caption: "A broken DNA end invading a copy",
            note: "In homologous recombination, a broken DNA end invades an intact matching duplex and uses it as a template to repair the break accurately.",
            topics: ["DNA repair"],
            also: ["strand invasion", "RAD51", "homology-directed repair", "D-loop"]),
        "Lipofection": SpecimenNote(
            caption: "Lipids carrying a plasmid into cells",
            note: "Lipofection packs DNA or RNA into cationic lipid complexes that cells take up, mainly by endocytosis, to transfect cultured cells.",
            topics: ["cell culture", "membranes"],
            also: ["transfection", "Lipofectamine", "liposome"]),
        "Lac operon": SpecimenNote(
            caption: "Lactose switching on bacterial genes",
            note: "In the lac operon, lactose (as allolactose) inactivates the LacI repressor so RNA polymerase can transcribe the lactose-digesting genes.",
            topics: ["transcription", "microbiology"],
            also: ["repressor", "operator", "E. coli", "gene regulation"]),
        "ATP rotor": SpecimenNote(
            caption: "A proton-driven ring making ATP",
            note: "In ATP synthase, protons crossing the membrane spin a ring of c-subunits and the central stalk, which drives ATP synthesis in the head.",
            topics: ["metabolism", "membranes"],
            also: ["F0F1", "proton motive force", "c-ring", "stator"]),
        "Centromere": SpecimenNote(
            caption: "Sister chromatids pulled apart",
            note: "At the centromere, kinetochores attach to spindle fibers and pull sister chromatids to opposite poles once cohesin is released.",
            topics: ["cell division"],
            also: ["kinetochore", "cohesin", "anaphase", "spindle"]),
        "Telomere": SpecimenNote(
            caption: "Chromosome ends shortening, rebuilt",
            note: "Telomeres are repeat sequences capping chromosome ends; they shorten with each round of copying unless telomerase adds repeats back.",
            topics: ["replication", "cell biology"],
            also: ["telomerase", "chromosome ends", "aging", "TTAGGG"]),
        "Condensing": SpecimenNote(
            caption: "Chromatin gathering into an X",
            note: "Before division, chromatin condenses into compact X-shaped chromosomes as the nuclear envelope breaks down.",
            topics: ["cell division"],
            also: ["prophase", "chromosome", "mitosis"]),
        "Histone marks": SpecimenNote(
            caption: "Chemical tags opening chromatin",
            note: "Enzymes add chemical marks to histone tails, and reader proteins that recognize them change how tightly chromatin is packed.",
            topics: ["transcription", "cell biology"],
            also: ["epigenetics", "acetylation", "methylation", "histone code"]),
        "TF search": SpecimenNote(
            caption: "A factor finding its DNA site",
            note: "Transcription factors find their DNA motifs by sliding and hopping along the helix, then recruit polymerase to start making RNA.",
            topics: ["transcription"],
            also: ["transcription factor", "promoter", "gene regulation", "RNA polymerase"]),
        "Base excision": SpecimenNote(
            caption: "Removing and replacing a bad base",
            note: "Base-excision repair removes a single damaged base with a glycosylase, then fills in and seals the gap with a polymerase and ligase.",
            topics: ["DNA repair"],
            also: ["glycosylase", "abasic site", "BER"]),
        "Nucleotide excision": SpecimenNote(
            caption: "Cutting out a bulky DNA lesion",
            note: "Nucleotide-excision repair removes bulky, helix-distorting lesions such as UV damage by excising a short strand stretch and refilling it.",
            topics: ["DNA repair"],
            also: ["UV damage", "thymine dimer", "NER"]),
        "NHEJ": SpecimenNote(
            caption: "Broken DNA ends joined directly",
            note: "Non-homologous end joining repairs double-strand breaks by directly ligating the ends, which is quick but can leave small indels.",
            topics: ["DNA repair", "gene editing"],
            also: ["Ku", "double-strand break", "indel"]),
        "Replication fork": SpecimenNote(
            caption: "Leading and lagging strand copying",
            note: "At a replication fork, the leading strand is copied continuously and the lagging strand in short Okazaki fragments begun on primers.",
            topics: ["replication"],
            also: ["Okazaki fragment", "helicase", "lagging strand", "primase"]),
        "Ligase": SpecimenNote(
            caption: "An enzyme sealing a nick in DNA",
            note: "DNA ligase uses ATP (NAD+ in bacteria) to seal nicks in the sugar-phosphate backbone, a final step in replication, repair and cloning.",
            topics: ["enzymes", "DNA repair", "cloning"],
            also: ["T4 ligase", "nick", "phosphodiester bond"]),
        "HiFi assembly": SpecimenNote(
            caption: "Joining DNA pieces by overlaps",
            note: "HiFi assembly joins DNA fragments with overlapping ends using an exonuclease, polymerase and ligase in one tube.",
            topics: ["cloning"],
            also: ["NEBuilder", "Gibson assembly", "plasmid", "seamless cloning"]),
        "Meiotic crossover": SpecimenNote(
            caption: "Homologs swapping chromosome arms",
            note: "In meiosis, paired homologous chromosomes exchange segments at crossovers, creating new combinations of alleles in the gametes.",
            topics: ["cell division", "genomics"],
            also: ["chiasma", "recombination", "homologous chromosomes", "meiosis"]),
        "Myosin V": SpecimenNote(
            caption: "A motor walking along actin",
            note: "Myosin V is a two-headed motor that walks along actin filaments in roughly 36 nm steps, hauling cargo such as vesicles.",
            topics: ["cell biology", "transport"],
            also: ["motor protein", "actin", "cargo", "ATP"]),
        "Transposon jump": SpecimenNote(
            caption: "A DNA segment hopping to a new site",
            note: "DNA transposons are segments that a transposase cuts out and pastes into a new genome location, a source of mutation and genome change.",
            topics: ["genomics"],
            also: ["transposase", "jumping gene", "cut and paste", "mobile element"]),
        "Sliding clamp": SpecimenNote(
            caption: "A ring clamp keeping polymerase on",
            note: "The sliding clamp (PCNA in eukaryotes, beta clamp in bacteria) encircles DNA and keeps polymerase attached for long stretches.",
            topics: ["replication"],
            also: ["PCNA", "beta clamp", "processivity", "clamp loader"]),
        "Strand displacement": SpecimenNote(
            caption: "One strand displacing another",
            note: "In toehold-mediated strand displacement, an invading strand binds a short single-stranded toehold and replaces the incumbent strand.",
            topics: ["chemistry", "reactions"],
            also: ["toehold", "DNA nanotechnology", "DNA computing", "branch migration"]),
        "Spike raster": SpecimenNote(
            caption: "Neuron spikes plotted over time",
            note: "A spike raster plots when each neuron fires, one row per cell; the histogram below counts spikes per time bin to reveal synchrony.",
            topics: ["neuroscience", "data"],
            also: ["raster plot", "PSTH", "spike train", "electrophysiology"]),
        "Rough ER": SpecimenNote(
            caption: "Ribosomes feeding proteins to the ER",
            note: "The rough ER is studded with ribosomes that thread new proteins into its lumen, where they fold before moving on to the Golgi.",
            topics: ["cell biology", "translation"],
            also: ["endoplasmic reticulum", "secretory pathway", "ribosome"]),
        "Mitosis": SpecimenNote(
            caption: "A cell dividing into two",
            note: "In mitosis, a cell condenses its chromosomes, aligns and separates them, and splits into two genetically identical daughter cells.",
            topics: ["cell division"],
            also: ["chromosomes", "spindle", "cytokinesis", "cell cycle"]),
        "Antibody": SpecimenNote(
            caption: "Antibodies grabbing antigens",
            note: "Antibodies are Y-shaped proteins whose two arm tips bind a specific antigen, flagging pathogens for the immune system.",
            topics: ["immunology"],
            also: ["immunoglobulin", "IgG", "antigen", "Fab"]),
        "Phagocytosis": SpecimenNote(
            caption: "A cell engulfing a particle",
            note: "In phagocytosis, immune cells such as macrophages wrap membrane around a large particle or microbe and take it in to destroy it.",
            topics: ["immunology", "cell biology"],
            also: ["engulfment", "macrophage", "phagosome"]),
        "Neuron": SpecimenNote(
            caption: "A neuron firing, releasing vesicles",
            note: "Neurons fire action potentials that travel down the axon to its terminals, where vesicles release neurotransmitter onto the next cell.",
            topics: ["neuroscience"],
            also: ["action potential", "axon", "neurotransmitter", "spike"]),
        "Vesicle budding": SpecimenNote(
            caption: "Cargo pinched off in a vesicle",
            note: "Vesicle budding packages cargo into membrane-bound carriers that pinch off one compartment and later fuse with another.",
            topics: ["membranes", "transport"],
            also: ["vesicle trafficking", "exocytosis", "endocytosis"]),
        "Mitochondria": SpecimenNote(
            caption: "The cell's energy-making organelle",
            note: "Mitochondria make most of a cell's ATP; their folded inner membranes (cristae) hold the electron transport chain and ATP synthase.",
            topics: ["metabolism", "cell biology"],
            also: ["ATP", "cristae", "respiration", "organelle"]),
        "Ion channel": SpecimenNote(
            caption: "Ions crossing a membrane pore",
            note: "Ion channels are membrane proteins with a pore that lets specific ions cross, generating electrical signals in nerves and muscle.",
            topics: ["membranes", "transport"],
            also: ["pore", "voltage-gated", "ion transport"]),
        "Cilia": SpecimenNote(
            caption: "Cilia beating to move particles",
            note: "Cilia are hair-like projections that beat in coordinated waves, moving fluid or particles across a cell surface, as in the airway.",
            topics: ["cell biology"],
            also: ["motile cilia", "ciliary beating", "mucociliary clearance"]),
        "Receptor": SpecimenNote(
            caption: "A ligand switching on a receptor",
            note: "Cell-surface receptors bind a ligand outside the cell and relay the message across the membrane to start a signaling cascade inside.",
            topics: ["signaling"],
            also: ["ligand", "signal transduction", "receptor binding"]),
        "Fission": SpecimenNote(
            caption: "A bacterium copying and splitting",
            note: "Binary fission is how bacteria reproduce: the cell copies its chromosome, elongates and splits at the middle into two daughter cells.",
            topics: ["microbiology", "cell division"],
            also: ["binary fission", "bacterial division", "FtsZ"]),
        "Synapse": SpecimenNote(
            caption: "Neurotransmitter crossing a synapse",
            note: "At a chemical synapse, vesicles fuse with the terminal membrane and release neurotransmitter that activates receptors on the next neuron.",
            topics: ["neuroscience", "signaling"],
            also: ["neurotransmitter", "vesicle release", "synaptic cleft", "receptors"]),
        "Cell migration": SpecimenNote(
            caption: "A cell crawling forward",
            note: "Cells migrate by extending a pseudopod, anchoring it and pulling the rear forward, a process key to wound healing, immunity and metastasis.",
            topics: ["cell biology"],
            also: ["motility", "pseudopod", "lamellipodium", "chemotaxis"]),
        "Phage": SpecimenNote(
            caption: "A virus injecting DNA into a cell",
            note: "Bacteriophages are viruses that infect bacteria; some, like T4, land on the cell, contract their tail and inject their genome.",
            topics: ["virology", "microbiology"],
            also: ["bacteriophage", "T4", "tail contraction", "infection"]),
        "Autophagosome": SpecimenNote(
            caption: "A double membrane wrapping cargo",
            note: "Autophagosomes are double-membraned vesicles that engulf damaged cell components and deliver them to lysosomes for recycling.",
            topics: ["cell biology", "membranes"],
            also: ["autophagy", "LC3", "lysosome", "phagophore"]),
        "Viral fusion": SpecimenNote(
            caption: "A virus fusing with a cell membrane",
            note: "Enveloped viruses use surface spike proteins to dock on cells and fuse their envelope with a membrane, releasing the genome inside.",
            topics: ["virology", "membranes"],
            also: ["envelope", "spike protein", "membrane fusion", "viral entry"]),
        "ATP synthase": SpecimenNote(
            caption: "A molecular turbine making ATP",
            note: "ATP synthase uses the proton gradient across a membrane to spin a rotor that makes ATP from ADP and phosphate.",
            topics: ["metabolism", "membranes"],
            also: ["F1F0", "proton gradient", "ATPase", "oxidative phosphorylation"]),
        "Nuclear import": SpecimenNote(
            caption: "Cargo passing through a nuclear pore",
            note: "Proteins with a nuclear localization signal are carried by importins through nuclear pores into the nucleus and then released.",
            topics: ["transport", "cell biology"],
            also: ["importin", "NLS", "nuclear pore", "Ran"]),
        "Mitophagy": SpecimenNote(
            caption: "Recycling a damaged mitochondrion",
            note: "Mitophagy is a form of autophagy that engulfs damaged mitochondria in a membrane and delivers them for degradation, a quality-control step.",
            topics: ["cell biology", "metabolism"],
            also: ["PINK1", "Parkin", "autophagy", "quality control"]),
        "Condensate": SpecimenNote(
            caption: "Molecules condensing into droplets",
            note: "Biomolecular condensates are membraneless droplets formed by phase separation of proteins and RNA, concentrating molecules for reactions.",
            topics: ["cell biology", "chemistry"],
            also: ["phase separation", "liquid-liquid", "membraneless organelle", "droplet"]),
        "GPCR": SpecimenNote(
            caption: "A receptor activating its G protein",
            note: "GPCRs cross the membrane seven times and, once a ligand binds, activate a G protein; many hormone and drug signals work this way.",
            topics: ["signaling", "drug discovery"],
            also: ["G protein", "seven-transmembrane", "GTP", "receptor"]),
        "Golgi": SpecimenNote(
            caption: "Cargo moving through the Golgi stack",
            note: "The Golgi apparatus modifies, sorts and ships proteins and lipids as they pass through its stacked sacs from the cis to the trans face.",
            topics: ["cell biology", "transport"],
            also: ["Golgi apparatus", "secretory pathway", "glycosylation", "cisternae"]),
        "Apoptosis": SpecimenNote(
            caption: "A cell dismantling itself tidily",
            note: "Apoptosis is programmed cell death: the cell shrinks, blebs and fragments into apoptotic bodies that are cleared without inflammation.",
            topics: ["cell biology"],
            also: ["programmed cell death", "caspase", "blebbing", "apoptotic bodies"]),
        "Microtubule": SpecimenNote(
            caption: "Microtubule growing and shrinking",
            note: "Microtubules switch between growing and rapidly shrinking, called dynamic instability, controlled by a GTP-tubulin cap at the plus end.",
            topics: ["cell biology"],
            also: ["tubulin", "dynamic instability", "GTP cap", "cytoskeleton"]),
        "Endosome": SpecimenNote(
            caption: "An endosome turning acidic",
            note: "Endosomes pump in protons to become acidic, which makes cargo release from its receptor so the receptor can be recycled.",
            topics: ["cell biology", "transport"],
            also: ["proton pump", "V-ATPase", "endocytosis", "pH"]),
        "Conjugation": SpecimenNote(
            caption: "Bacteria passing a plasmid across",
            note: "In bacterial conjugation, a donor passes a copy of a plasmid to a recipient through a pilus, spreading genes such as antibiotic resistance.",
            topics: ["microbiology"],
            also: ["pilus", "horizontal gene transfer", "F plasmid", "antibiotic resistance"]),
        "Transduction": SpecimenNote(
            caption: "A phage moving DNA between bacteria",
            note: "In transduction, a phage carries bacterial DNA from one host to the next, where it can recombine into the new host's chromosome.",
            topics: ["microbiology", "virology"],
            also: ["bacteriophage", "horizontal gene transfer", "recombination"]),
        "Sec61": SpecimenNote(
            caption: "A protein threading into the ER",
            note: "The Sec61 translocon is a channel in the ER membrane through which new secretory and membrane proteins are threaded as they are made.",
            topics: ["translation", "membranes", "transport"],
            also: ["translocon", "signal peptide", "endoplasmic reticulum", "signal peptidase"]),
        "HEK293": SpecimenNote(
            caption: "Cells piling up in round clumps",
            note: "HEK 293 cells are a human embryonic kidney line, widely used for transfection and protein or virus production; they grow loosely attached.",
            topics: ["cell culture"],
            also: ["HEK 293", "kidney cells", "transfection", "cell line"]),
        "HeLa": SpecimenNote(
            caption: "Cells spreading into a flat sheet",
            note: "HeLa cells, the first immortal human cell line, came from Henrietta Lacks' cervical cancer in 1951 and remain a workhorse of cell biology.",
            topics: ["cell culture"],
            also: ["Henrietta Lacks", "cervical cancer", "cell line", "immortal cells"]),
        "Fibroblasts": SpecimenNote(
            caption: "Spindle cells aligning in streams",
            note: "Fibroblasts are elongated connective-tissue cells that make extracellular matrix and align in parallel streams in culture.",
            topics: ["cell culture", "cell biology"],
            also: ["connective tissue", "3T3", "collagen", "spindle cells"]),
        "MDCK islands": SpecimenNote(
            caption: "Epithelial cells growing in islands",
            note: "MDCK cells are a canine kidney epithelial line that forms tight, polarized colonies and sheets, a standard model for epithelia.",
            topics: ["cell culture"],
            also: ["Madin-Darby canine kidney", "epithelium", "polarity", "cell line"]),
        "Neuron culture": SpecimenNote(
            caption: "Neurites growing out and branching",
            note: "Cultured neurons sprout neurites tipped by growth cones, which sense their surroundings as the cells build a connected network.",
            topics: ["neuroscience", "cell culture"],
            also: ["neurites", "growth cone", "primary neurons", "axon"]),
        "Macrophages": SpecimenNote(
            caption: "Immune cells ruffling and probing",
            note: "Macrophages are immune cells that patrol tissue, probing with filopodia and ruffling their edges to sample and engulf debris and microbes.",
            topics: ["immunology", "cell biology"],
            also: ["filopodia", "phagocyte", "ruffles", "innate immunity"]),
        "Trypsinisation": SpecimenNote(
            caption: "Lifting adherent cells off a flask",
            note: "Trypsinization uses the protease trypsin to cut cell-surface attachments so adherent cultured cells round up and can be passaged.",
            topics: ["cell culture", "sample prep"],
            also: ["trypsin", "passaging", "detach cells", "adherent cells"]),
        "STORM": SpecimenNote(
            caption: "Blinking molecules build an image",
            note: "STORM super-resolution microscopy localizes single blinking fluorophores one at a time, building images sharper than the diffraction limit.",
            topics: ["microscopy", "imaging"],
            also: ["super-resolution", "single-molecule localization", "nuclear pore", "fluorophore"]),
        "Sarcomere": SpecimenNote(
            caption: "Muscle fiber units contracting",
            note: "The sarcomere is muscle's contractile unit: myosin heads pull on actin filaments, bringing the Z-lines together to shorten the fiber.",
            topics: ["cell biology"],
            also: ["myosin", "actin", "Z-line", "muscle contraction"]),
        "Cell fates": SpecimenNote(
            caption: "A stem cell making different cells",
            note: "A pluripotent stem cell can renew itself while its daughters differentiate into specialized types such as neurons, blood cells and muscle.",
            topics: ["development", "cell biology"],
            also: ["differentiation", "stem cell", "self-renewal", "lineage"]),
        "Optogenetics": SpecimenNote(
            caption: "Light flashes making a neuron fire",
            note: "Optogenetics puts light-gated ion channels in neurons so light flashes trigger firing, letting researchers test cause and effect.",
            topics: ["neuroscience"],
            also: ["channelrhodopsin", "optical fiber", "light-gated channel", "stimulation"]),
        "Clathrin cage": SpecimenNote(
            caption: "A protein cage forming a vesicle",
            note: "Clathrin triskelions assemble into a cage on the membrane, shaping coated pits that pinch off as vesicles during endocytosis.",
            topics: ["membranes", "transport"],
            also: ["triskelion", "endocytosis", "coated vesicle", "dynamin"]),
        "Actin treadmilling": SpecimenNote(
            caption: "Actin network pushing a cell edge",
            note: "At a cell's leading edge, actin filaments grow at the tip and disassemble behind, pushing the membrane forward as the network treadmills.",
            topics: ["cell biology"],
            also: ["lamellipodium", "Arp2/3", "cytoskeleton", "filament"]),
        "Calcium wave": SpecimenNote(
            caption: "Calcium flash passing cell to cell",
            note: "Calcium waves spread from cell to cell, often through gap junctions, coordinating activity across a tissue or cell sheet.",
            topics: ["signaling"],
            also: ["gap junction", "calcium imaging", "intercellular signaling"]),
        "24-well scratch assay": SpecimenNote(
            caption: "Cells closing a scratched wound",
            note: "In a scratch assay, a gap is scraped in a confluent cell layer and how fast cells close it measures their migration and wound healing.",
            topics: ["cell culture", "measurement"],
            also: ["wound healing", "migration assay", "monolayer", "multiwell plate"]),
        "Saltatory conduction": SpecimenNote(
            caption: "Impulses leaping between nodes",
            note: "In myelinated axons, action potentials jump between nodes of Ranvier, conducting far faster than in unmyelinated fibers.",
            topics: ["neuroscience"],
            also: ["myelin", "node of Ranvier", "axon", "action potential"]),
        "Notch checkerboard": SpecimenNote(
            caption: "Neighbors choosing opposite fates",
            note: "Notch signaling lets neighboring cells inhibit each other, so a uniform sheet resolves into alternating cell fates like a checkerboard.",
            topics: ["development", "signaling"],
            also: ["lateral inhibition", "Delta", "patterning"]),
        "Immunofluorescence": SpecimenNote(
            caption: "Antibodies making filaments glow",
            note: "Immunofluorescence uses primary antibodies and fluorescent secondary antibodies to label specific proteins in fixed cells for microscopy.",
            topics: ["microscopy", "imaging"],
            also: ["antibody staining", "fluorophore", "IF", "secondary antibody"]),
        "Gap junction": SpecimenNote(
            caption: "Channels joining two cells",
            note: "Gap junctions are connexon channels linking neighboring cells, letting ions and small molecules pass directly from one cell to the next.",
            topics: ["cell biology", "signaling"],
            also: ["connexin", "connexon", "electrical coupling"]),
        "Tight junction": SpecimenNote(
            caption: "Seals between cells blocking leaks",
            note: "Tight junctions seal the gaps between epithelial cells, blocking leaks between them and keeping the two sides of a barrier distinct.",
            topics: ["cell biology", "membranes"],
            also: ["epithelium", "claudin", "barrier", "paracellular"]),
        "Desmosome": SpecimenNote(
            caption: "Cell-cell rivets resisting a pull",
            note: "Desmosomes are cadherin-based junctions anchored to intermediate filaments (keratin in skin, desmin in heart), giving tissues strength.",
            topics: ["cell biology"],
            also: ["cadherin", "keratin", "cell adhesion", "intermediate filaments"]),
        "Peroxisome": SpecimenNote(
            caption: "Chopping fatty acids in peroxisomes",
            note: "Peroxisomes break down very-long-chain fatty acids by beta-oxidation, two carbons at a time, and also handle hydrogen peroxide.",
            topics: ["metabolism", "cell biology"],
            also: ["beta-oxidation", "fatty acid", "organelle", "catalase"]),
        "Nuclear lamina": SpecimenNote(
            caption: "A nucleus squeezing through a gap",
            note: "The nuclear lamina, a meshwork under the nuclear envelope, stiffens the nucleus and shapes how cells squeeze through tight spaces.",
            topics: ["cell biology"],
            also: ["lamin", "confined migration", "nuclear envelope", "nuclear mechanics"]),
        "SNARE zipper": SpecimenNote(
            caption: "SNAREs zipping vesicle to membrane",
            note: "SNARE proteins zip together between a vesicle and its target membrane, pulling them close to drive membrane fusion and cargo release.",
            topics: ["membranes", "transport"],
            also: ["v-SNARE", "t-SNARE", "membrane fusion", "exocytosis"]),
        "Mouse sniff": SpecimenNote(
            caption: "Mouse sniffing, whiskers twitching",
            note: "Mice sample odors by sniffing in quick bursts while moving their whiskers, behaviors used to study olfaction and sensory processing.",
            topics: ["neuroscience", "model organisms"],
            also: ["whisking", "olfaction", "sniffing", "mouse behavior"]),
        "Fly eye": SpecimenNote(
            caption: "A fly's many-lensed compound eye",
            note: "The fruit fly's compound eye is made of hundreds of ommatidia, each a tiny lens and photoreceptor unit sampling one point of the scene.",
            topics: ["model organisms", "neuroscience"],
            also: ["Drosophila", "ommatidia", "compound eye", "vision"]),
        "Planaria": SpecimenNote(
            caption: "A flatworm regrowing from each half",
            note: "Planarian flatworms regenerate a whole body from a fragment using abundant stem cells called neoblasts, a classic regeneration model.",
            topics: ["model organisms", "development"],
            also: ["flatworm", "regeneration", "neoblasts", "Schmidtea"]),
        "C. elegans": SpecimenNote(
            caption: "A roundworm crawling in waves",
            note: "C. elegans is a roundworm about 1 mm long with exactly 302 neurons in the hermaphrodite, a leading model for genetics and development.",
            topics: ["model organisms"],
            also: ["roundworm", "nematode", "worm"]),
        "Y-maze": SpecimenNote(
            caption: "A mouse choosing an arm of a maze",
            note: "The Y-maze tests spatial working memory in rodents by how often they alternate between arms, a common behavior and memory assay.",
            topics: ["neuroscience", "model organisms"],
            also: ["spontaneous alternation", "working memory", "rodent behavior", "maze"]),
        "Frog embryo": SpecimenNote(
            caption: "An embryo dividing 1, 2, 4, 8 cells",
            note: "After fertilization, a frog embryo undergoes rapid cleavage divisions without growing, splitting one cell into many smaller ones.",
            topics: ["development", "model organisms"],
            also: ["Xenopus", "cleavage", "blastomere", "amphibian embryo"]),
        "Zebrafish": SpecimenNote(
            caption: "A striped fish swimming",
            note: "Zebrafish are small fish with transparent larvae, widely used as a vertebrate model for development, genetics and drug screening.",
            topics: ["model organisms", "development"],
            also: ["Danio rerio", "vertebrate model", "larvae"]),
        "Fly climbing": SpecimenNote(
            caption: "Flies climbing a vial after a tap",
            note: "The climbing assay (negative geotaxis) taps flies to the bottom of a vial and times their climb, a test of motor function and aging.",
            topics: ["model organisms", "neuroscience", "measurement"],
            also: ["negative geotaxis", "Drosophila", "motor assay", "locomotion"]),
        "Fertilisation": SpecimenNote(
            caption: "One sperm in, the rest blocked",
            note: "At fertilization, the first sperm to fuse triggers a block to polyspermy, and its nucleus joins the egg's to form the zygote.",
            topics: ["development"],
            also: ["sperm", "egg", "polyspermy block", "zygote"]),
        "Mouse wheel": SpecimenNote(
            caption: "A mouse running on a wheel",
            note: "Running-wheel activity is a common measure of voluntary exercise and daily activity rhythms in lab mice.",
            topics: ["model organisms", "measurement"],
            also: ["circadian rhythm", "locomotor activity", "exercise"]),
        "Mouse water": SpecimenNote(
            caption: "A mouse drinking at a bottle",
            note: "Lab mice drink from a sipper bottle, and measuring their water intake helps track health, thirst and the effects of treatments.",
            topics: ["model organisms", "lab life"],
            also: ["sipper", "drinking behavior", "animal husbandry", "water bottle"]),
        "Zebrafish somites": SpecimenNote(
            caption: "Segmentation waves making somites",
            note: "Somites are blocks of tissue that form in sequence along the embryo and later become vertebrae and muscle, timed by the segmentation clock.",
            topics: ["development", "model organisms"],
            also: ["segmentation clock", "somitogenesis", "embryo"]),
        "Gastrulation": SpecimenNote(
            caption: "Cells rolling in to form germ layers",
            note: "Gastrulation reorganizes the embryo into germ layers by moving cells inward at the blastopore, which forms the gut cavity.",
            topics: ["development", "model organisms"],
            also: ["blastopore", "Xenopus", "germ layers", "embryo"]),
        "Fly syncytium": SpecimenNote(
            caption: "Nuclei dividing, then cells forming",
            note: "The early Drosophila embryo divides its nuclei without dividing the cell, forming a syncytium that cellularizes after about 13 divisions.",
            topics: ["development", "model organisms"],
            also: ["Drosophila", "syncytial blastoderm", "cellularization", "pole cells"]),
        "Worm zygote": SpecimenNote(
            caption: "The worm's first uneven division",
            note: "The C. elegans zygote divides asymmetrically into a larger AB cell and a smaller P1 cell, a classic model of cell polarity.",
            topics: ["development", "model organisms"],
            also: ["C. elegans", "asymmetric division", "PAR proteins", "polarity"]),
        "Microinjection": SpecimenNote(
            caption: "A glass needle injecting eggs",
            note: "Microinjection uses a fine glass needle to deliver DNA, RNA or protein into eggs or embryos, for example to make transgenic animals.",
            topics: ["model organisms", "gene editing"],
            also: ["needle", "transgenic", "embryo injection", "zygote"]),
        "Fossil": SpecimenNote(
            caption: "An ammonite being freed from rock",
            note: "Fossil preparation removes rock from around a specimen with brushes and fine tools, revealing ammonites and other ancient life.",
            topics: ["earth science", "evolution"],
            also: ["paleontology", "ammonite", "excavation", "fossil preparation"]),
        "Grid cells": SpecimenNote(
            caption: "Neurons firing in a hexagonal grid",
            note: "Grid cells in the entorhinal cortex fire at points of a triangular lattice as an animal moves, a spatial map that won a 2014 Nobel Prize.",
            topics: ["neuroscience"],
            also: ["entorhinal cortex", "spatial navigation", "Moser", "place cells"]),
        "Waggle dance": SpecimenNote(
            caption: "A bee dancing directions to food",
            note: "Honeybees waggle along a line whose angle from vertical encodes the food's direction relative to the sun; waggle length encodes distance.",
            topics: ["ecology"],
            also: ["honeybee", "Karl von Frisch", "communication", "foraging"]),
        "Tardigrade": SpecimenNote(
            caption: "A water bear drying out and reviving",
            note: "Tardigrades survive drying by curling into a dormant tun and revive when rehydrated, a tolerance called anhydrobiosis.",
            topics: ["ecology", "model organisms"],
            also: ["water bear", "tun", "anhydrobiosis", "cryptobiosis"]),
        "Fly pushing": SpecimenNote(
            caption: "Sorting flies on a CO2 pad",
            note: "Fly pushing is the routine of anesthetizing flies with CO2 and sorting them under a microscope by sex and markers such as curly wings.",
            topics: ["lab life", "model organisms"],
            also: ["Drosophila", "CO2 pad", "balancer", "genetic crosses"]),
        "Caffeine": SpecimenNote(
            caption: "The stimulant in coffee and tea",
            note: "Caffeine is a methylxanthine that blocks adenosine receptors in the brain, which is why it fights drowsiness.",
            topics: ["chemistry", "neuroscience"],
            also: ["methylxanthine", "coffee", "stimulant", "adenosine"]),
        "Titration": SpecimenNote(
            caption: "Drops added until the color flips",
            note: "A titration adds a solution of known concentration drop by drop until an indicator changes color, showing how much analyte was present.",
            topics: ["chemistry", "measurement"],
            also: ["burette", "endpoint", "indicator", "analytical chemistry"]),
        "Molecule": SpecimenNote(
            caption: "A tetrahedral molecule in 3D",
            note: "A ball-and-stick model shows atoms as spheres and bonds as sticks, here a central atom with four neighbors at tetrahedral angles.",
            topics: ["chemistry"],
            also: ["ball-and-stick", "methane", "tetrahedral", "molecular model"]),
        "Serotonin": SpecimenNote(
            caption: "The mood and gut signaling molecule",
            note: "Serotonin (5-hydroxytryptamine) is an indole-derived neurotransmitter that helps regulate mood, sleep, and gut motility.",
            topics: ["neuroscience", "chemistry"],
            also: ["5-HT", "5-hydroxytryptamine", "neurotransmitter", "indole"]),
        "Distillation": SpecimenNote(
            caption: "Boiling a mixture to purify it",
            note: "Distillation separates liquids by boiling point: the more volatile one evaporates, condenses in a condenser, and is collected.",
            topics: ["separation", "chemistry"],
            also: ["condenser", "boiling", "hot plate", "purification"]),
        "Ethanol": SpecimenNote(
            caption: "The alcohol in drinks and solvents",
            note: "Ethanol (C₂H₅OH) is a two-carbon alcohol made by yeast fermentation and widely used as a solvent, disinfectant, and fuel.",
            topics: ["chemistry"],
            also: ["alcohol", "EtOH", "fermentation", "solvent"]),
        "Crystal": SpecimenNote(
            caption: "A crystal growing layer by layer",
            note: "Crystals grow as molecules add layer by layer onto a seed, a way to purify compounds and to prepare samples for X-ray diffraction.",
            topics: ["chemistry", "physics"],
            also: ["crystallization", "seed crystal", "lattice", "facets"]),
        "THC": SpecimenNote(
            caption: "The main psychoactive cannabinoid",
            note: "Tetrahydrocannabinol (THC) is the main psychoactive compound in cannabis; it acts on CB1 cannabinoid receptors in the brain.",
            topics: ["chemistry", "neuroscience"],
            also: ["tetrahydrocannabinol", "cannabis", "cannabinoid", "CB1"]),
        "Oxytocin": SpecimenNote(
            caption: "A nine-residue peptide hormone",
            note: "Oxytocin, a nine-residue peptide hormone with a disulfide ring, drives labor contractions and milk release and influences social bonding.",
            topics: ["neuroscience", "signaling"],
            also: ["peptide hormone", "neuropeptide", "disulfide", "love hormone"]),
        "SN2": SpecimenNote(
            caption: "Backside attack inverts a carbon",
            note: "In an SN2 reaction a nucleophile attacks opposite the leaving group in a single step, inverting the carbon's stereochemistry.",
            topics: ["reactions", "chemistry"],
            also: ["nucleophilic substitution", "Walden inversion", "nucleophile", "leaving group"]),
        "Diels–Alder": SpecimenNote(
            caption: "A diene and an alkene form a ring",
            note: "The Diels–Alder reaction joins a diene and a dienophile in one concerted step to make a six-membered ring, a workhorse of synthesis.",
            topics: ["reactions", "chemistry"],
            also: ["cycloaddition", "diene", "dienophile", "[4+2]"]),
        "Nucleation": SpecimenNote(
            caption: "The first seed of a new crystal",
            note: "Nucleation is the first step of crystallization, when a few molecules assemble into a stable ordered seed that others then join.",
            topics: ["chemistry", "thermodynamics"],
            also: ["crystallization", "seed", "supersaturation", "lattice"]),
        "Click chemistry": SpecimenNote(
            caption: "Azide and alkyne snap together",
            note: "Copper-catalyzed azide–alkyne cycloaddition joins two molecules through a stable triazole ring, a fast, selective way to label biomolecules.",
            topics: ["reactions", "chemistry"],
            also: ["CuAAC", "azide", "alkyne", "triazole"]),
        "BZ reaction": SpecimenNote(
            caption: "Oscillating chemical waves in a dish",
            note: "The Belousov–Zhabotinsky reaction is a chemical oscillator whose color changes spread as waves, a classic case of self-organization.",
            topics: ["chemistry", "reactions"],
            also: ["chemical oscillator", "oscillating reaction", "Belousov", "Zhabotinsky"]),
        "Host–guest": SpecimenNote(
            caption: "A crown ether trapping a fitting ion",
            note: "A host such as a crown ether binds most tightly the guest whose size fits its cavity, the basis of selective molecular recognition.",
            topics: ["chemistry"],
            also: ["crown ether", "supramolecular", "molecular recognition", "ionophore"]),
        "Electrochemistry": SpecimenNote(
            caption: "A battery cell powering a bulb",
            note: "A galvanic cell links oxidation and reduction at two electrodes, with a salt bridge balancing charge, to push current through a wire.",
            topics: ["chemistry", "electromagnetism"],
            also: ["galvanic cell", "battery", "salt bridge", "redox"]),
        "MOF": SpecimenNote(
            caption: "Metal nodes and linkers build pores",
            note: "Metal–organic frameworks are porous crystals of metal nodes joined by organic linkers, used for gas storage, separation, and catalysis.",
            topics: ["chemistry"],
            also: ["metal-organic framework", "porous material", "linker", "reticular chemistry"]),
        "Amphetamine": SpecimenNote(
            caption: "A stimulant used in ADHD treatment",
            note: "Amphetamine is a stimulant that raises dopamine and norepinephrine signaling; it is prescribed for ADHD and narcolepsy.",
            topics: ["medicine", "neuroscience"],
            also: ["Adderall", "stimulant", "ADHD", "phenethylamine"]),
        "Methylphenidate": SpecimenNote(
            caption: "A stimulant used for ADHD",
            note: "Methylphenidate (Ritalin) treats ADHD by blocking reuptake of dopamine and norepinephrine, boosting their signaling in the brain.",
            topics: ["medicine", "neuroscience"],
            also: ["Ritalin", "Concerta", "ADHD", "stimulant"]),
        "Modafinil": SpecimenNote(
            caption: "A wakefulness-promoting drug",
            note: "Modafinil is prescribed for narcolepsy and shift-work sleep disorder; it promotes wakefulness, partly via the dopamine transporter.",
            topics: ["medicine", "neuroscience"],
            also: ["Provigil", "narcolepsy", "wakefulness", "eugeroic"]),
        "Nicotine": SpecimenNote(
            caption: "The stimulant in tobacco",
            note: "Nicotine is an alkaloid from tobacco that activates nicotinic acetylcholine receptors, producing stimulation and dependence.",
            topics: ["neuroscience", "chemistry"],
            also: ["alkaloid", "tobacco", "nicotinic receptor", "acetylcholine"]),
        "Fluoxetine": SpecimenNote(
            caption: "An SSRI that keeps serotonin around",
            note: "Fluoxetine (Prozac) is an SSRI antidepressant that blocks the serotonin transporter, so serotonin stays longer in the synapse.",
            topics: ["medicine", "neuroscience"],
            also: ["Prozac", "SSRI", "antidepressant", "reuptake inhibitor"]),
        "Sertraline": SpecimenNote(
            caption: "A widely prescribed SSRI",
            note: "Sertraline (Zoloft) is an SSRI antidepressant used for depression, anxiety, and OCD; it works by blocking serotonin reuptake.",
            topics: ["medicine", "neuroscience"],
            also: ["Zoloft", "SSRI", "antidepressant", "serotonin reuptake"]),
        "Escitalopram": SpecimenNote(
            caption: "An SSRI used for depression",
            note: "Escitalopram (Lexapro) is the active S-enantiomer of citalopram, an SSRI antidepressant used for depression and anxiety.",
            topics: ["medicine", "neuroscience"],
            also: ["Lexapro", "Cipralex", "SSRI", "citalopram"]),
        "HPLC": SpecimenNote(
            caption: "A sample separating on a column",
            note: "High-performance liquid chromatography pumps a sample through a packed column so its components separate and register as peaks.",
            topics: ["chromatography", "separation"],
            also: ["high-performance liquid chromatography", "column", "chromatogram", "detector"]),
        "MALDI": SpecimenNote(
            caption: "A laser launching ions down a tube",
            note: "MALDI-TOF mass spectrometry uses a laser to ionize a sample on a plate, then times the ions flying down a tube to weigh them.",
            topics: ["mass spectrometry"],
            also: ["MALDI-TOF", "time of flight", "laser desorption", "mass spec"]),
        "Electrospray": SpecimenNote(
            caption: "Charged droplets from a needle tip",
            note: "Electrospray ionization uses high voltage to make gas-phase ions from a liquid, a gentle way to feed biomolecules to a mass spectrometer.",
            topics: ["mass spectrometry", "chemistry"],
            also: ["ESI", "Taylor cone", "ionization", "nanospray"]),
        "Orbitrap": SpecimenNote(
            caption: "Ions circling a central electrode",
            note: "An Orbitrap traps ions orbiting a central spindle electrode and reads their oscillation frequencies, giving very precise mass measurements.",
            topics: ["mass spectrometry"],
            also: ["Fourier transform", "ion trap", "high-resolution mass spec", "mass analyzer"]),
        "Quadrupole": SpecimenNote(
            caption: "Rods letting only one mass through",
            note: "A quadrupole mass filter applies oscillating voltages to four rods so that only ions of a chosen mass-to-charge ratio get through.",
            topics: ["mass spectrometry", "physics"],
            also: ["mass filter", "mass analyzer", "m/z", "four rods"]),
        "Titration curve": SpecimenNote(
            caption: "pH leaping at the equivalence point",
            note: "A titration curve plots pH against titrant added, and its steep jump marks the equivalence point where acid and base are matched.",
            topics: ["chemistry", "measurement"],
            also: ["equivalence point", "pH curve", "burette", "acid-base"]),
        "TLC plate": SpecimenNote(
            caption: "A mixture splitting up a plate",
            note: "Thin-layer chromatography separates a mixture as solvent climbs a plate; each compound's Rf is its travel relative to the solvent front.",
            topics: ["chromatography", "separation"],
            also: ["TLC", "Rf", "thin-layer chromatography", "solvent front"]),
        "Nylon rope": SpecimenNote(
            caption: "Pulling nylon from two liquids",
            note: "In the nylon rope trick, two monomers react where two immiscible liquids meet, and the polymer film is pulled out as a continuous thread.",
            topics: ["chemistry", "reactions"],
            also: ["polymerization", "nylon 6,10", "interfacial polymerization", "polyamide"]),
        "Chemiluminescence": SpecimenNote(
            caption: "A chemical reaction giving off light",
            note: "In chemiluminescence a reaction, such as luminol being oxidized, releases energy as light; it is used in forensics and blot detection.",
            topics: ["chemistry", "reactions"],
            also: ["luminol", "glow", "luminescence", "light emission"]),
        "Chemical garden": SpecimenNote(
            caption: "Mineral tubes growing in waterglass",
            note: "A chemical garden forms when metal salt crystals sit in sodium silicate solution and grow hollow tubes from precipitate membranes.",
            topics: ["chemistry", "reactions"],
            also: ["silica garden", "waterglass", "sodium silicate", "self-assembly"]),
        "Benzene resonance": SpecimenNote(
            caption: "Benzene's bonds sharing electrons",
            note: "Benzene's six carbon–carbon bonds are identical, with electrons shared around the ring, a state the two Kekulé structures describe together.",
            topics: ["chemistry"],
            also: ["Kekulé", "aromaticity", "delocalization", "resonance structure"]),
        "Turing pattern": SpecimenNote(
            caption: "Spots forming from chemical rules",
            note: "A Turing pattern emerges when a slowly diffusing activator and a fast inhibitor interact, spontaneously forming spots or stripes.",
            topics: ["chemistry", "development", "math"],
            also: ["reaction-diffusion", "morphogenesis", "activator inhibitor", "Alan Turing"]),
        "Separatory funnel": SpecimenNote(
            caption: "Splitting two liquid layers apart",
            note: "A separatory funnel splits immiscible liquids, such as water and an organic solvent, so a dissolved compound can be extracted.",
            topics: ["separation", "sample prep", "chemistry"],
            also: ["liquid-liquid extraction", "extraction", "immiscible", "partition"]),
        "Büchner funnel": SpecimenNote(
            caption: "Vacuum pulling liquid off a solid",
            note: "Vacuum filtration through a Büchner funnel quickly pulls liquid through filter paper, leaving the solid behind to be collected and washed.",
            topics: ["separation", "sample prep"],
            also: ["vacuum filtration", "suction filtration", "Buchner", "filter flask"]),
        "Flame test": SpecimenNote(
            caption: "Metal ions coloring a flame",
            note: "A flame test identifies metal ions by the characteristic color they give a flame, as excited electrons emit light on falling back.",
            topics: ["chemistry", "spectroscopy"],
            also: ["atomic emission", "metal ions", "wire loop", "emission spectrum"]),
        "Precipitate": SpecimenNote(
            caption: "A solid forming in a clear solution",
            note: "A precipitate is an insoluble solid formed when two solutions react, signaling a reaction and letting the solid be filtered out.",
            topics: ["chemistry", "reactions"],
            also: ["precipitation", "insoluble", "solubility", "reagent"]),
        "pH rainbow": SpecimenNote(
            caption: "An indicator coloring a pH series",
            note: "A pH indicator shifts color with acidity, so a row of solutions reads as a graded scale from acidic through neutral to basic.",
            topics: ["chemistry", "measurement"],
            also: ["pH indicator", "universal indicator", "acid", "base"]),
        "Lollipop plot": SpecimenNote(
            caption: "Mutations plotted along a protein",
            note: "A lollipop plot marks mutation positions along a protein's domains, with stem height showing how often each occurs, to reveal hotspots.",
            topics: ["data", "genomics"],
            also: ["mutation plot", "hotspot", "protein domains", "cancer genomics"]),
        "Disulfide bond": SpecimenNote(
            caption: "Cysteines joined in the ER",
            note: "Protein disulfide isomerase (PDI) helps form S–S bonds between cysteines in the ER, locking secreted proteins into their fold.",
            topics: ["protein folding", "protein structure"],
            also: ["PDI", "cysteine", "endoplasmic reticulum", "oxidative folding"]),
        "Sheets and helices": SpecimenNote(
            caption: "Secondary structure taking shape",
            note: "Alpha helices and beta sheets are a protein's main secondary structures, held together by hydrogen bonds between backbone atoms.",
            topics: ["protein structure", "protein folding"],
            also: ["alpha helix", "beta sheet", "secondary structure", "beta strand"]),
        "Confidence bloom": SpecimenNote(
            caption: "A predicted fold and its confidence",
            note: "Structure predictors such as AlphaFold give each residue a confidence score (pLDDT); low scores usually mark flexible or disordered regions.",
            topics: ["protein structure", "machine learning"],
            also: ["AlphaFold", "pLDDT", "structure prediction", "confidence score"]),
        "Binder swarm": SpecimenNote(
            caption: "Designing a protein to bind a target",
            note: "Generative models propose many candidate protein binders for a target site, and the best are picked by predicted fit for lab testing.",
            topics: ["protein structure", "machine learning", "drug discovery"],
            also: ["binder design", "de novo design", "epitope", "protein design"]),
        "Inverse folding": SpecimenNote(
            caption: "Finding a sequence for a given fold",
            note: "Inverse folding asks which amino acid sequence will fold into a chosen backbone; tools such as ProteinMPNN design such sequences.",
            topics: ["protein structure", "machine learning"],
            also: ["ProteinMPNN", "protein design", "sequence design", "fold"]),
        "Multimer": SpecimenNote(
            caption: "Predicting how subunits assemble",
            note: "Multimer prediction models the structure of a protein complex made of several chains, such as a symmetric ring of identical subunits.",
            topics: ["protein structure", "machine learning"],
            also: ["AlphaFold-Multimer", "protein complex", "oligomer", "homo-oligomer"]),
        "Interface polish": SpecimenNote(
            caption: "Tuning a protein-protein interface",
            note: "Affinity optimization refines a protein–protein interface, swapping side chains to fill gaps and add contacts so the pair binds tighter.",
            topics: ["protein structure", "drug discovery"],
            also: ["affinity maturation", "binding affinity", "interface design", "side chains"]),
        "Diffusion design": SpecimenNote(
            caption: "A new protein backbone from noise",
            note: "Diffusion models for protein design start from random noise and iteratively denoise it into a new backbone with a chosen shape.",
            topics: ["protein structure", "machine learning"],
            also: ["de novo design", "generative model", "RFdiffusion", "denoising"]),
        "Cryo-EM": SpecimenNote(
            caption: "Frozen particles averaged to a map",
            note: "Cryo-electron microscopy averages images of thousands of flash-frozen particles at many angles into a 3D density map for atomic modeling.",
            topics: ["microscopy", "protein structure"],
            also: ["cryo-electron microscopy", "single particle", "density map", "cryoEM"]),
        "Structural alignment": SpecimenNote(
            caption: "Overlaying two protein folds",
            note: "Structural alignment superimposes two protein structures to find their shared core, scored by RMSD, and can reveal distant relatives.",
            topics: ["protein structure", "bioinformatics"],
            also: ["superposition", "RMSD", "fold comparison", "TM-align"]),
        "Fluorescence": SpecimenNote(
            caption: "A protein that glows when lit",
            note: "Fluorescent proteins such as GFP fold into a barrel around a chromophore that absorbs light and re-emits it, used to tag living cells.",
            topics: ["imaging", "protein structure"],
            also: ["GFP", "green fluorescent protein", "chromophore", "beta barrel"]),
        "Polyprotein": SpecimenNote(
            caption: "A viral protein chain cut into parts",
            note: "Many RNA viruses make one long polyprotein that viral proteases cut into working proteins, making the protease a drug target.",
            topics: ["virology", "enzymes"],
            also: ["protease", "proteolytic processing", "cleavage", "autoprocessing"]),
        "Ubiquitin chain": SpecimenNote(
            caption: "Tagging a protein with ubiquitin",
            note: "E3 ligases and E2 enzymes build a ubiquitin chain on a substrate protein, a tag that often marks it for destruction by the proteasome.",
            topics: ["enzymes", "signaling", "cell biology"],
            also: ["ubiquitination", "E3 ligase", "E2", "proteasome"]),
        "Glycosylation": SpecimenNote(
            caption: "Sugars built onto a protein",
            note: "N-linked glycosylation builds a branched sugar tree on an asparagine of a protein, aiding its folding, stability, and recognition.",
            topics: ["cell biology", "protein folding"],
            also: ["N-glycan", "N-linked", "glycoprotein", "post-translational modification"]),
        "Detergent solubilization": SpecimenNote(
            caption: "Detergent freeing a membrane protein",
            note: "Detergents dissolve a lipid bilayer into micelles and coat a membrane protein, keeping it soluble so it can be purified and studied.",
            topics: ["membranes", "protein structure", "sample prep"],
            also: ["micelle", "membrane protein", "purification", "reconstitution"]),
        "Circular genome plot": SpecimenNote(
            caption: "Chromosomes in a ring with links",
            note: "A circular genome plot (Circos plot) arranges chromosomes around a ring and links related loci, such as translocations, with chords.",
            topics: ["genomics", "data"],
            also: ["Circos", "circos plot", "chromosomes", "translocation"]),
        "Genome browser": SpecimenNote(
            caption: "Layered tracks along a genome",
            note: "A genome browser stacks tracks such as genes, sequencing reads, and ChIP-seq peaks along one axis so they can be compared by position.",
            topics: ["genomics", "bioinformatics"],
            also: ["IGV", "UCSC browser", "tracks", "ChIP-seq"]),
        "Hi-C map": SpecimenNote(
            caption: "Which genome regions touch",
            note: "A Hi-C map counts how often stretches of the genome sit close together in the nucleus, revealing domains (TADs) and chromatin looping.",
            topics: ["genomics", "sequencing", "data"],
            also: ["chromosome conformation", "TAD", "chromatin looping", "3D genome"]),
        "Poly(A) tail": SpecimenNote(
            caption: "A tail of A's added to an mRNA",
            note: "Polyadenylation cuts pre-mRNA after a signal sequence and adds a poly(A) tail that stabilizes the mRNA and aids its export and translation.",
            topics: ["RNA", "transcription"],
            also: ["polyadenylation", "poly(A) polymerase", "mRNA processing", "3′ end"]),
        "5′ cap": SpecimenNote(
            caption: "A cap added to new RNA",
            note: "The 5′ cap, a methylated guanosine linked by a triphosphate, is added to new RNA early on, protecting it and aiding translation.",
            topics: ["RNA", "transcription"],
            also: ["m7G", "capping enzyme", "RNA polymerase II", "mRNA processing"]),
        "mRNA export": SpecimenNote(
            caption: "mRNA passing out of the nucleus",
            note: "Mature mRNAs are exported through nuclear pores into the cytoplasm, where ribosomes can begin translating them.",
            topics: ["RNA", "transport"],
            also: ["nuclear pore", "nuclear export", "cytoplasm", "ribosome"]),
        "HCV IRES": SpecimenNote(
            caption: "A viral RNA that recruits ribosomes",
            note: "The hepatitis C virus IRES is a folded RNA element that binds the 40S ribosomal subunit directly, starting translation without a 5′ cap.",
            topics: ["RNA", "translation", "virology"],
            also: ["IRES", "internal ribosome entry site", "hepatitis C", "40S"]),
        "Covariation": SpecimenNote(
            caption: "Paired bases mutating together",
            note: "Compensatory mutations change both partners of a base pair, and this covariation in alignments is evidence that an RNA helix is real.",
            topics: ["RNA", "bioinformatics"],
            also: ["compensatory mutation", "co-variation", "base pair", "RNA structure"]),
        "CrPV IRES": SpecimenNote(
            caption: "A viral RNA mimicking a tRNA",
            note: "The cricket paralysis virus IGR IRES has a tRNA-like pseudoknot that grabs the ribosome and starts translation without initiation factors.",
            topics: ["RNA", "translation", "virology"],
            also: ["IRES", "IGR IRES", "cricket paralysis virus", "pseudoknot"]),
        "Hammerhead": SpecimenNote(
            caption: "A self-cutting RNA enzyme",
            note: "The hammerhead ribozyme is a small RNA that folds around a three-way junction and cleaves its own backbone, showing RNA can be an enzyme.",
            topics: ["RNA", "enzymes"],
            also: ["ribozyme", "self-cleaving RNA", "catalytic RNA"]),
        "RNA ensemble": SpecimenNote(
            caption: "One RNA, many possible folds",
            note: "An RNA can fold many ways; prediction software ranks the structures by free energy, and the lowest-energy one is often the real fold.",
            topics: ["RNA", "bioinformatics", "thermodynamics"],
            also: ["secondary structure", "minimum free energy", "RNA folding", "ViennaRNA"]),
        "Frameshift": SpecimenNote(
            caption: "A ribosome slipping back one base",
            note: "Programmed −1 ribosomal frameshifting, used by coronaviruses to make replicase proteins, needs a slippery sequence and an RNA pseudoknot.",
            topics: ["translation", "virology", "RNA"],
            also: ["ribosomal frameshifting", "slippery sequence", "pseudoknot", "SARS-CoV-2"]),
        "TAR": SpecimenNote(
            caption: "HIV's RNA hairpin binding Tat",
            note: "TAR is a hairpin at the start of HIV-1 transcripts; binding of the viral Tat protein at its bulge is needed for efficient transcription.",
            topics: ["RNA", "virology"],
            also: ["HIV-1", "Tat", "trans-activation response element", "RNA hairpin"]),
        "tRNA fold": SpecimenNote(
            caption: "tRNA folding into its L shape",
            note: "Transfer RNA folds from a flat cloverleaf into a compact L shape, with the amino acid on one end and the anticodon at the other.",
            topics: ["RNA", "translation"],
            also: ["transfer RNA", "cloverleaf", "anticodon", "aminoacylation"]),
        "SAM riboswitch": SpecimenNote(
            caption: "An RNA switch that senses SAM",
            note: "The SAM-I riboswitch is an RNA sensor in bacterial mRNAs: binding S-adenosylmethionine changes its fold and switches gene expression off.",
            topics: ["RNA", "transcription"],
            also: ["riboswitch", "S-adenosylmethionine", "aptamer", "gene regulation"]),
        "glmS": SpecimenNote(
            caption: "A ribozyme that cuts when fed sugar",
            note: "The glmS ribozyme is a riboswitch that cleaves itself when glucosamine-6-phosphate binds, shutting down the gene that makes this metabolite.",
            topics: ["RNA", "enzymes"],
            also: ["ribozyme", "riboswitch", "glucosamine-6-phosphate", "self-cleaving"]),
        "G-quadruplex": SpecimenNote(
            caption: "Guanines stacking into quartets",
            note: "A G-quadruplex is a four-stranded structure of stacked guanine quartets held by a central ion, found in telomeres and gene promoters.",
            topics: ["genomics", "RNA"],
            also: ["G4", "guanine quartet", "telomere", "quadruplex"]),
        "Dicer": SpecimenNote(
            caption: "An enzyme trimming a hairpin RNA",
            note: "Dicer cuts the terminal loop off a pre-miRNA hairpin, releasing a short double-stranded RNA that goes on to silence target genes.",
            topics: ["RNA", "enzymes"],
            also: ["microRNA", "miRNA", "RNAi", "siRNA"]),
        "HDV": SpecimenNote(
            caption: "A hepatitis D self-cutting RNA",
            note: "The hepatitis delta virus ribozyme is a self-cleaving RNA with a double pseudoknot fold that processes the viral genome during replication.",
            topics: ["RNA", "virology"],
            also: ["ribozyme", "hepatitis delta virus", "self-cleaving RNA", "pseudoknot"]),
        "RNA helicase": SpecimenNote(
            caption: "An enzyme unwinding an RNA hairpin",
            note: "RNA helicases use ATP to unwind RNA duplexes and remodel RNA–protein complexes, acting in splicing, translation, and decay.",
            topics: ["RNA", "enzymes"],
            also: ["helicase", "unwinding", "DEAD-box", "ATPase"]),
        "Reading frame": SpecimenNote(
            caption: "Codons read in a shifted frame",
            note: "Ribosomes read mRNA in three-letter codons, so a shift of one base changes every codon downstream and yields a different protein.",
            topics: ["translation", "RNA"],
            also: ["codon", "frameshift", "ribosome", "slippery sequence"]),
        "Pseudoknot": SpecimenNote(
            caption: "An RNA fold with crossing stems",
            note: "A pseudoknot forms when bases in a hairpin loop pair with a stretch outside it, making two interleaved stems, as in ribozymes and viruses.",
            topics: ["RNA"],
            also: ["RNA structure", "hairpin", "stem-loop", "base pairing"]),
        "Lentivirus": SpecimenNote(
            caption: "Packaging a gene into lentivirus",
            note: "Lentiviral vectors are made by transfecting packaging cells with several plasmids; the particles carry a transfer gene into target cells.",
            topics: ["virology", "cell culture"],
            also: ["lentiviral vector", "packaging cells", "transfection", "gene delivery"]),
        "Prion": SpecimenNote(
            caption: "Misfolded protein converting others",
            note: "Prions are infectious misfolded proteins whose β-rich form converts normal prion protein into more of itself, causing diseases such as CJD.",
            topics: ["protein folding", "medicine"],
            also: ["prion disease", "misfolding", "amyloid", "Creutzfeldt-Jakob"]),
        "Oxygen exchange": SpecimenNote(
            caption: "A red cell loading and unloading O₂",
            note: "Red blood cells carry oxygen bound to hemoglobin, loading it in the lungs where oxygen is high and releasing it in tissues where it is low.",
            topics: ["medicine", "cell biology"],
            also: ["hemoglobin", "gas exchange", "erythrocyte", "capillary"]),
        "Immune synapse": SpecimenNote(
            caption: "A T cell meeting its target",
            note: "The immunological synapse is the contact zone where a T cell and its target cluster receptors and exchange signals or cytotoxic granules.",
            topics: ["immunology", "signaling"],
            also: ["T cell", "cytotoxic T lymphocyte", "cell contact", "granules"]),
        "Nephron": SpecimenNote(
            caption: "A kidney filter sorting by size",
            note: "The nephron filters blood by size, passing water and small solutes into its tubule, keeping proteins, and reclaiming useful molecules.",
            topics: ["medicine", "transport"],
            also: ["kidney", "glomerulus", "filtration", "reabsorption"]),
        "Membrane attack": SpecimenNote(
            caption: "Complement proteins punching a pore",
            note: "The membrane attack complex is a ring of complement proteins (C5b–C9) that punches a pore in a microbe's membrane, killing bacteria.",
            topics: ["immunology", "membranes"],
            also: ["complement", "MAC", "C5b-9", "pore-forming"]),
        "NETosis": SpecimenNote(
            caption: "A neutrophil casting a net of DNA",
            note: "In NETosis, neutrophils release webs of chromatin studded with antimicrobial proteins that trap and kill microbes outside the cell.",
            topics: ["immunology", "cell biology"],
            also: ["neutrophil extracellular traps", "NETs", "neutrophil", "chromatin"]),
        "Phototransduction": SpecimenNote(
            caption: "How a photon becomes a nerve signal",
            note: "In vision, a photon isomerizes retinal in rhodopsin, triggering a cascade that closes cGMP-gated channels in photoreceptors.",
            topics: ["neuroscience", "signaling"],
            also: ["rhodopsin", "retina", "vision", "photoreceptor"]),
        "Mucociliary": SpecimenNote(
            caption: "Cilia sweeping mucus and particles",
            note: "Mucociliary clearance uses beating cilia to move a mucus layer, with trapped particles and microbes, out of the airways.",
            topics: ["medicine", "cell biology"],
            also: ["cilia", "mucus", "airway", "respiratory epithelium"]),
        "T cell receptor": SpecimenNote(
            caption: "A T cell scanning for its peptide",
            note: "A T cell receptor scans peptides presented on MHC molecules and signals only when it binds its matching antigen, ignoring self peptides.",
            topics: ["immunology", "signaling"],
            also: ["TCR", "MHC", "antigen", "peptide-MHC"]),
        "B cell receptor": SpecimenNote(
            caption: "Antigen clustering B cell receptors",
            note: "A B cell's receptors cluster around bound antigen, triggering signaling and antigen uptake so the cell can start an antibody response.",
            topics: ["immunology", "signaling"],
            also: ["BCR", "antigen", "B cell", "receptor clustering"]),
        "Clonal expansion": SpecimenNote(
            caption: "One B cell dividing into a clone",
            note: "In clonal expansion, the lymphocyte that recognizes an antigen divides repeatedly, making identical daughters, including plasma cells.",
            topics: ["immunology", "cell division"],
            also: ["clonal selection", "B cell", "antibodies", "lymphocyte"]),
        "Blood draw": SpecimenNote(
            caption: "Collecting blood in a vacuum tube",
            note: "Venipuncture collects blood from a vein into evacuated tubes, giving samples for clinical tests and research.",
            topics: ["medicine", "sample prep"],
            also: ["venipuncture", "phlebotomy", "Vacutainer", "blood sample"]),
        "HIV budding": SpecimenNote(
            caption: "HIV budding off and maturing",
            note: "HIV assembles with Gag at the host membrane and buds out; its protease then cuts Gag so the capsid forms a cone-shaped mature core.",
            topics: ["virology"],
            also: ["Gag", "capsid", "maturation", "retrovirus"]),
        "Coronavirus budding": SpecimenNote(
            caption: "Coronavirus assembling and budding",
            note: "Coronaviruses assemble at the ER–Golgi intermediate compartment, where nucleocapsids and spikes gather and particles bud into the lumen.",
            topics: ["virology"],
            also: ["SARS-CoV-2", "ERGIC", "nucleocapsid", "spike protein"]),
        "Flu budding": SpecimenNote(
            caption: "Influenza budding with its genome",
            note: "Influenza A packages eight separate RNA segments, with HA and NA spikes, into each particle as it buds from the infected cell's membrane.",
            topics: ["virology"],
            also: ["hemagglutinin", "neuraminidase", "flu", "genome segments"]),
        "Cytokine storm": SpecimenNote(
            caption: "Cytokines setting off more cytokines",
            note: "A cytokine storm is an excessive immune response in which cytokines trigger more cytokine release, a feedback loop that can damage tissue.",
            topics: ["immunology", "signaling", "medicine"],
            also: ["hypercytokinemia", "cytokine release syndrome", "inflammation", "interleukin"]),
        "mRNA vaccine": SpecimenNote(
            caption: "A lipid particle delivering mRNA",
            note: "mRNA vaccines deliver mRNA in lipid nanoparticles; cells translate it into an antigen, such as spike, to train the immune system.",
            topics: ["immunology", "medicine", "translation"],
            also: ["lipid nanoparticle", "LNP", "vaccine", "spike protein"]),
        "CAR-T": SpecimenNote(
            caption: "Engineered T cells attacking a tumor",
            note: "CAR-T therapy equips a patient's T cells with a chimeric antigen receptor so they kill cancer cells, used against some blood cancers.",
            topics: ["immunology", "medicine"],
            also: ["chimeric antigen receptor", "cell therapy", "immunotherapy", "CAR T"]),
        "Heartbeat": SpecimenNote(
            caption: "A beating heart and its ECG trace",
            note: "An ECG traces each heartbeat's electrical cycle: the P wave (atria), QRS complex (ventricles firing), and T wave (ventricular recovery).",
            topics: ["medicine", "measurement"],
            also: ["ECG", "EKG", "electrocardiogram", "cardiac cycle"]),
        "12-well dose series": SpecimenNote(
            caption: "Adding a drug across a 12-well plate",
            note: "A dose series adds rising drug concentrations across a plate's wells so the cell response can be read out as a dose–response curve.",
            topics: ["cell culture", "drug discovery", "liquid handling"],
            also: ["dose-response", "multichannel pipette", "serial dilution", "IC50"]),
        "MRI": SpecimenNote(
            caption: "Slices of the head built up by MRI",
            note: "MRI places the body in a strong magnetic field and uses radio pulses to map hydrogen nuclei, imaging soft tissue without ionizing radiation.",
            topics: ["imaging", "medicine", "physics"],
            also: ["magnetic resonance imaging", "scanner", "NMR", "brain scan"]),
        "Tablet dissolving": SpecimenNote(
            caption: "A tablet disintegrating in water",
            note: "Dissolution testing tracks how fast a tablet breaks up and releases its drug, which affects how quickly the drug is absorbed.",
            topics: ["medicine", "drug discovery"],
            also: ["dissolution", "drug release", "coating", "pharmaceutics"]),
        "Biopsy punch": SpecimenNote(
            caption: "Taking a skin sample with a punch",
            note: "A punch biopsy uses a small circular blade to lift a core of skin, from epidermis through dermis to fat, for diagnosis.",
            topics: ["medicine", "sample prep"],
            also: ["skin biopsy", "dermatology", "tissue sample", "histology"]),
        "Michaelis–Menten": SpecimenNote(
            caption: "Enzyme rate curve to straight line",
            note: "The Michaelis–Menten curve gives an enzyme's Vmax and Km; the Lineweaver–Burk plot straightens it so its intercepts reveal both.",
            topics: ["enzymes", "data"],
            also: ["enzyme kinetics", "Lineweaver-Burk", "Vmax", "Km"]),
        "Glycolysis": SpecimenNote(
            caption: "Glucose broken down to pyruvate",
            note: "Glycolysis splits glucose into two pyruvates in ten steps, spending two ATP and making four, for a net gain of two ATP plus NADH.",
            topics: ["metabolism", "enzymes"],
            also: ["glucose", "pyruvate", "ATP", "Embden-Meyerhof pathway"]),
        "Krebs cycle": SpecimenNote(
            caption: "The cycle that burns acetyl carbons",
            note: "The Krebs (citric acid) cycle oxidizes acetyl groups to CO₂ in mitochondria, producing NADH, FADH₂, and GTP that feed energy production.",
            topics: ["metabolism", "cell biology"],
            also: ["citric acid cycle", "TCA cycle", "mitochondria", "NADH"]),
        "Kinase cascade": SpecimenNote(
            caption: "A signal amplified by kinases",
            note: "In a kinase cascade, each kinase phosphorylates the next, amplifying a signal from a membrane receptor to gene changes in the nucleus.",
            topics: ["signaling", "enzymes"],
            also: ["phosphorylation", "MAPK", "signal transduction", "receptor"]),
        "Repressilator": SpecimenNote(
            caption: "Three genes repressing one another",
            note: "The repressilator is a synthetic gene circuit of three genes that each repress the next, making protein levels oscillate in bacteria.",
            topics: ["transcription", "microbiology"],
            also: ["synthetic biology", "gene circuit", "oscillator", "Elowitz"]),
        "Insulin signalling": SpecimenNote(
            caption: "Insulin moving glucose into a cell",
            note: "Insulin binds its receptor and, through signaling, moves glucose transporters (GLUT4) to the cell surface so cells can take up glucose.",
            topics: ["signaling", "metabolism", "transport"],
            also: ["GLUT4", "insulin receptor", "glucose uptake", "diabetes"]),
        "Circadian clock": SpecimenNote(
            caption: "A protein clock keeping time",
            note: "The cyanobacterial clock is the KaiC protein, which with KaiA and KaiB cycles through phosphorylation over about 24 hours, even in vitro.",
            topics: ["microbiology", "signaling"],
            also: ["KaiC", "Kai proteins", "circadian rhythm", "cyanobacteria"]),
        "Growth curve": SpecimenNote(
            caption: "A culture's lag, growth and plateau",
            note: "A bacterial growth curve plots cell density over time through lag, exponential, and stationary phases; its steepest slope gives growth rate.",
            topics: ["microbiology", "measurement", "data"],
            also: ["OD600", "lag phase", "exponential phase", "doubling time"]),
        "Run and tumble": SpecimenNote(
            caption: "How E. coli steers by tumbling",
            note: "E. coli swims in straight runs and reorients by tumbling when its flagella unbundle; biasing this lets it climb gradients of attractants.",
            topics: ["microbiology", "signaling"],
            also: ["chemotaxis", "flagella", "E. coli", "bacterial motility"]),
        "Polar flagellum": SpecimenNote(
            caption: "Swimming with a single flagellum",
            note: "Many bacteria swim with a single polar flagellum, and some, such as Vibrio, reverse and then flick to change direction.",
            topics: ["microbiology"],
            also: ["Vibrio", "flagellum", "motility", "run-reverse-flick"]),
        "Spirochete": SpecimenNote(
            caption: "A corkscrew-shaped swimmer",
            note: "Spirochetes, such as the Lyme disease and syphilis bacteria, swim using internal flagella that make the whole cell wave like a corkscrew.",
            topics: ["microbiology"],
            also: ["Borrelia", "Treponema", "periplasmic flagella", "bacterial motility"]),
        "Twitching": SpecimenNote(
            caption: "Pulling along a surface with pili",
            note: "Twitching motility lets bacteria crawl over surfaces by extending type IV pili, which attach and retract to pull the cell forward.",
            topics: ["microbiology"],
            also: ["type IV pili", "pili", "surface motility", "Pseudomonas"]),
        "Amoeboid": SpecimenNote(
            caption: "A cell crawling by pseudopods",
            note: "Amoeboid movement is crawling by extending pseudopods, as in amoebae and many white blood cells, driven by actin and cytoplasmic flow.",
            topics: ["cell biology", "microbiology"],
            also: ["pseudopod", "amoeba", "cell migration", "actin"]),
        "Chlamydomonas": SpecimenNote(
            caption: "An alga swimming with two flagella",
            note: "Chlamydomonas is a single-celled green alga that swims by beating two flagella like a breaststroke, a model for flagella and photosynthesis.",
            topics: ["model organisms", "microbiology", "cell biology"],
            also: ["green alga", "flagella", "cilia", "microalga"]),
        "Flagellar motor": SpecimenNote(
            caption: "A rotary motor driven by protons",
            note: "The bacterial flagellar motor is a rotary engine in the cell envelope that uses proton flow to spin the filament and can reverse direction.",
            topics: ["microbiology", "cell biology"],
            also: ["flagellum", "rotor", "stator", "proton motive force"]),
        "Quorum sensing": SpecimenNote(
            caption: "Bacteria lighting up as a crowd",
            note: "Quorum sensing lets bacteria release signal molecules and switch on group behaviors, such as bioluminescence, at high cell density.",
            topics: ["microbiology", "signaling"],
            also: ["autoinducer", "bioluminescence", "cell density", "Vibrio"]),
        "Biofilm": SpecimenNote(
            caption: "A biofilm growing and dispersing",
            note: "A biofilm is a community of bacteria embedded in a self-made matrix on a surface, which makes them harder to kill with antibiotics.",
            topics: ["microbiology", "medicine"],
            also: ["biofilm matrix", "EPS", "bacterial community", "antibiotic tolerance"]),
        "MEGA-plate": SpecimenNote(
            caption: "Bacteria evolving across drug bands",
            note: "The MEGA-plate has bands of rising antibiotic concentration, letting researchers watch bacteria evolve resistance as they spread across it.",
            topics: ["microbiology", "evolution", "medicine"],
            also: ["antibiotic resistance", "evolution", "giant petri dish", "Baym"]),
        "FtsZ ring": SpecimenNote(
            caption: "A ring that splits a bacterium",
            note: "FtsZ, a tubulin-like protein, forms a ring at a bacterium's middle that constricts and recruits the machinery to divide the cell in two.",
            topics: ["microbiology", "cell division"],
            also: ["binary fission", "cytokinesis", "divisome", "tubulin homolog"]),
        "Magnetospirillum": SpecimenNote(
            caption: "A bacterium aligning with a magnet",
            note: "Magnetotactic bacteria such as Magnetospirillum make chains of magnetite crystals, magnetosomes, that align the cell with magnetic fields.",
            topics: ["microbiology", "electromagnetism"],
            also: ["magnetotactic bacteria", "magnetosome", "magnetite", "magnetotaxis"]),
        "Anabaena": SpecimenNote(
            caption: "Nitrogen-fixing cells in a filament",
            note: "Anabaena is a filamentous cyanobacterium that fixes nitrogen in thick-walled cells called heterocysts and shares it along the filament.",
            topics: ["microbiology", "ecology"],
            also: ["cyanobacteria", "heterocyst", "nitrogen fixation", "filament"]),
        "Myxococcus": SpecimenNote(
            caption: "Swarm becoming a fruiting body",
            note: "Myxococcus xanthus cells swarm together when starved and build a spore-filled fruiting body, a model of bacterial cooperation.",
            topics: ["microbiology", "development", "model organisms"],
            also: ["myxobacteria", "fruiting body", "social bacteria", "starvation"]),
        "Caulobacter": SpecimenNote(
            caption: "An asymmetric bacterial division",
            note: "Caulobacter crescentus divides unevenly into a stalked cell and a swimming cell, a model for how bacteria control cell cycle and polarity.",
            topics: ["microbiology", "model organisms", "cell division"],
            also: ["Caulobacter crescentus", "holdfast", "stalk", "asymmetric division"]),
        "Streptomyces": SpecimenNote(
            caption: "Branching hyphae making spore chains",
            note: "Streptomyces grow as branching hyphae and form spore-bearing aerial filaments; they make many antibiotics, including streptomycin.",
            topics: ["microbiology", "drug discovery"],
            also: ["actinomycetes", "hyphae", "antibiotic producer", "sporulation"]),
        "Bdellovibrio": SpecimenNote(
            caption: "A predatory bacterium eating prey",
            note: "Bdellovibrio is a predatory bacterium that invades other Gram-negative bacteria, grows inside the prey, and bursts out as several new cells.",
            topics: ["microbiology"],
            also: ["predatory bacteria", "bdelloplast", "Gram-negative", "predation"]),
        "Glycerol stock": SpecimenNote(
            caption: "Scraping a frozen bacterial stock",
            note: "A glycerol stock keeps bacteria frozen at −80 °C; scraping a bit with a tip, without thawing the vial, starts a fresh culture.",
            topics: ["sample prep", "microbiology", "lab life"],
            also: ["freezer stock", "cryostock", "inoculate", "−80 °C"]),
        "Spread plating": SpecimenNote(
            caption: "Spreading cells over an agar plate",
            note: "Spread plating uses a sterile bent spreader to distribute a liquid culture evenly over agar so single cells grow into countable colonies.",
            topics: ["microbiology", "sample prep"],
            also: ["agar plate", "L-spreader", "colonies", "CFU"]),
        "Bead plating": SpecimenNote(
            caption: "Glass beads spreading a culture",
            note: "Bead plating shakes sterile glass beads over an agar plate to spread a culture evenly, a quick alternative to a spreader.",
            topics: ["microbiology", "sample prep"],
            also: ["glass beads", "agar plate", "colonies", "plating"]),
        "Gram stain": SpecimenNote(
            caption: "Sorting bacteria by their cell walls",
            note: "The Gram stain divides bacteria by cell wall: thick peptidoglycan keeps crystal violet (Gram-positive); thin walls lose it and stain pink.",
            topics: ["microbiology", "microscopy"],
            also: ["Gram-positive", "Gram-negative", "crystal violet", "safranin"]),
        "Replica plating": SpecimenNote(
            caption: "Copying colonies onto a new plate",
            note: "Replica plating uses a velvet block to print colonies from a master plate onto selective plates, revealing which ones fail to grow there.",
            topics: ["microbiology", "sample prep"],
            also: ["velvet", "master plate", "selective plate", "Lederberg"]),
        "Sine wave": SpecimenNote(
            caption: "A circle unwinding into a wave",
            note: "A sine wave is the height of a point moving around a circle at constant speed, plotted over time; it is the basic shape of oscillation.",
            topics: ["waves", "math", "physics"],
            also: ["sinusoid", "unit circle", "oscillation", "harmonic"]),
        "Atom": SpecimenNote(
            caption: "Electrons circling a nucleus",
            note: "An atom is a tiny nucleus of protons and neutrons surrounded by electrons; the orbit picture is a simple model of that structure.",
            topics: ["physics", "chemistry", "quantum"],
            also: ["nucleus", "electron", "Bohr model", "orbits"]),
        "Double pendulum": SpecimenNote(
            caption: "Two linked arms swinging chaotically",
            note: "A double pendulum, one pendulum hung from another, is a classic chaotic system: tiny changes in the start give wildly different motion.",
            topics: ["physics", "mechanics"],
            also: ["chaos", "pendulum", "chaotic system"]),
        "E = mc²": SpecimenNote(
            caption: "Mass and energy, written out",
            note: "E = mc² is Einstein's relation showing that mass and energy are equivalent, with the speed of light squared as the conversion factor.",
            topics: ["physics"],
            also: ["Einstein", "relativity", "mass-energy equivalence"]),
        "Pulsar": SpecimenNote(
            caption: "A spinning star sweeping out beams",
            note: "A pulsar is a rapidly spinning neutron star whose beams of radiation sweep past Earth like a lighthouse, seen as regular pulses.",
            topics: ["astronomy", "physics"],
            also: ["neutron star", "radio pulsar", "lighthouse", "pulse"]),
        "Double slit": SpecimenNote(
            caption: "Waves through two slits interfere",
            note: "In the double-slit experiment, waves or particles passing through two slits build up a pattern of bright and dark fringes by interference.",
            topics: ["optics", "quantum", "waves"],
            also: ["Young's experiment", "interference", "diffraction", "fringes"]),
        "Wind tunnel": SpecimenNote(
            caption: "Airflow bending around a wing",
            note: "A wind tunnel blows air past a model such as an airfoil so engineers can study lift, drag and flow patterns.",
            topics: ["physics", "mechanics"],
            also: ["airfoil", "aerodynamics", "streamlines", "lift"]),
        "Orbit": SpecimenNote(
            caption: "A planet speeding up near its star",
            note: "Planets move on ellipses, fastest near the star and slowest far away, as Kepler's second law says: equal areas are swept in equal times.",
            topics: ["astronomy", "mechanics", "physics"],
            also: ["Kepler", "elliptical orbit", "orbital mechanics", "eccentricity"]),
        "Pythagoras": SpecimenNote(
            caption: "Squares on a right triangle's sides",
            note: "In a right triangle, the Pythagorean theorem says the squares on the two legs together equal the square on the hypotenuse in area.",
            topics: ["math"],
            also: ["Pythagorean theorem", "hypotenuse", "geometry", "right triangle"]),
        "Lissajous": SpecimenNote(
            caption: "A curve from two oscillations",
            note: "A Lissajous figure is traced by two perpendicular oscillations; its shape reveals their frequency ratio and phase, as on an oscilloscope.",
            topics: ["waves", "math", "physics"],
            also: ["oscilloscope", "frequency ratio", "phase", "oscillation"]),
        "Spacetime": SpecimenNote(
            caption: "A mass bending spacetime around it",
            note: "General relativity describes gravity as the curvature of spacetime by mass, with orbiting bodies following the curved paths.",
            topics: ["physics", "astronomy"],
            also: ["general relativity", "gravity well", "Einstein", "curved space"]),
        "Galaxy": SpecimenNote(
            caption: "A spiral galaxy turning",
            note: "Spiral galaxies are rotating disks of stars with spiral arms around a bright core; inner stars take less time to orbit than outer ones.",
            topics: ["astronomy"],
            also: ["Milky Way", "spiral arms", "differential rotation", "stars"]),
        "Cradle": SpecimenNote(
            caption: "Swinging balls passing on momentum",
            note: "Newton's cradle shows conservation of momentum and energy: the ball swung in sends an equal number of balls swinging out at the far end.",
            topics: ["mechanics", "physics"],
            also: ["Newton's cradle", "momentum", "collision", "conservation"]),
        "Tunneling": SpecimenNote(
            caption: "A wave leaking through a barrier",
            note: "Quantum tunneling lets a particle cross an energy barrier it could not pass classically, as its wavefunction extends through the barrier.",
            topics: ["quantum", "physics"],
            also: ["quantum tunneling", "wave packet", "wavefunction", "barrier"]),
        "Chirp": SpecimenNote(
            caption: "Two massive objects spiraling in",
            note: "A gravitational-wave chirp is the rising signal from two compact objects, such as black holes, spiraling together; LIGO detects them.",
            topics: ["astronomy", "physics", "waves"],
            also: ["LIGO", "gravitational waves", "black hole merger", "binary inspiral"]),
        "Spin echo": SpecimenNote(
            caption: "Spins fanning out, then refocusing",
            note: "An NMR spin echo uses a second pulse to refocus spins that fanned out, recovering signal otherwise lost to static field variations.",
            topics: ["spectroscopy", "physics"],
            also: ["NMR", "Hahn echo", "MRI", "relaxation"]),
        "X-ray diffraction": SpecimenNote(
            caption: "X-rays scattering off a crystal",
            note: "X-ray diffraction sends X-rays through a crystal, and the pattern of spots encodes how its atoms are arranged, as for proteins.",
            topics: ["physics", "chemistry", "protein structure"],
            also: ["crystallography", "Bragg", "diffraction pattern", "X-ray crystallography"]),
        "FRET": SpecimenNote(
            caption: "Dyes reporting a molecule's motion",
            note: "FRET transfers energy from a donor dye to a nearby acceptor dye, so their signal ratio reports distances of a few nanometers in a molecule.",
            topics: ["microscopy", "imaging", "measurement"],
            also: ["Förster resonance energy transfer", "single-molecule", "donor", "acceptor"]),
        "Optical tweezers": SpecimenNote(
            caption: "Light trapping a tiny bead",
            note: "Optical tweezers use a tightly focused laser beam to hold and move microscopic particles and to measure piconewton forces on molecules.",
            topics: ["optics", "physics", "measurement"],
            also: ["laser trap", "optical trap", "piconewton", "single-molecule"]),
        "Vortex street": SpecimenNote(
            caption: "Alternating whirls behind a cylinder",
            note: "A Kármán vortex street is the alternating pattern of opposite-spinning vortices shed behind a cylinder or other blunt body in a steady flow.",
            topics: ["physics", "mechanics"],
            also: ["Kármán vortex street", "fluid dynamics", "turbulence", "vortex shedding"]),
        "Meissner": SpecimenNote(
            caption: "Levitation by a superconductor",
            note: "The Meissner effect is a superconductor's expulsion of magnetic fields as it cools below its critical temperature, so a magnet can float.",
            topics: ["physics", "electromagnetism"],
            also: ["superconductivity", "levitation", "magnetic field", "superconductor"]),
        "Precession": SpecimenNote(
            caption: "A spin circling around a field",
            note: "Precession is the circling of a spinning magnetic moment, such as a nuclear spin, around a magnetic field at the Larmor frequency.",
            topics: ["physics", "spectroscopy", "quantum"],
            also: ["Larmor", "NMR", "spin", "angular momentum"]),
        "Electron excitation": SpecimenNote(
            caption: "Hydrogen's electron jumping levels",
            note: "An excited hydrogen electron falls back in steps, giving off light of set wavelengths such as red Balmer-alpha and ultraviolet Lyman-alpha.",
            topics: ["physics", "quantum", "spectroscopy"],
            also: ["Bohr model", "energy levels", "emission lines", "Balmer series"]),
        "s orbitals": SpecimenNote(
            caption: "Hydrogen s orbitals, 1s to 3s",
            note: "s orbitals are spherical electron-density distributions; 2s and 3s contain radial nodes where the density drops to zero.",
            topics: ["quantum", "chemistry", "physics"],
            also: ["hydrogen orbitals", "radial nodes", "wavefunction", "electron density"]),
        "p orbitals": SpecimenNote(
            caption: "Dumbbell-shaped p orbitals",
            note: "The three p orbitals are dumbbells with two lobes of opposite wavefunction sign along the x, y or z axis, with a node at the nucleus.",
            topics: ["quantum", "chemistry"],
            also: ["atomic orbital", "px py pz", "lobes", "wavefunction"]),
        "d orbitals": SpecimenNote(
            caption: "Cloverleaf and ringed d orbitals",
            note: "The d orbitals include four-lobed cloverleafs like d_xy and d_x²−y², and d_z² with two lobes and a ring; they shape metal bonding.",
            topics: ["quantum", "chemistry"],
            also: ["atomic orbital", "transition metals", "crystal field", "cloverleaf"]),
        "Tesla coil": SpecimenNote(
            caption: "Sparks leaping from a resonant coil",
            note: "A Tesla coil is a resonant transformer that steps voltage up to very high levels, producing branching high-frequency sparks.",
            topics: ["electromagnetism", "physics"],
            also: ["high voltage", "resonant transformer", "spark", "Nikola Tesla"]),
        "Lithography": SpecimenNote(
            caption: "Printing circuit patterns with light",
            note: "Photolithography transfers a mask pattern onto light-sensitive resist on a wafer, which is then etched to make microchip features.",
            topics: ["optics", "chemistry"],
            also: ["photoresist", "wafer", "microfabrication", "semiconductor"]),
        "TEM column": SpecimenNote(
            caption: "Electrons imaging through a specimen",
            note: "A transmission electron microscope focuses an electron beam through a thin specimen with magnetic lenses to image fine structure.",
            topics: ["microscopy", "imaging", "physics"],
            also: ["TEM", "electron microscope", "electron beam", "magnetic lens"]),
        "Negative stain": SpecimenNote(
            caption: "Particles pale against a dark stain",
            note: "Negative-stain EM coats particles on a grid with heavy-metal salt, so they appear pale against a dark background, a quick sample check.",
            topics: ["microscopy", "sample prep", "protein structure"],
            also: ["electron microscopy", "uranyl acetate", "EM grid", "TEM"]),
        "Tilt series": SpecimenNote(
            caption: "Tilted views combined into 3D",
            note: "In cryo-electron tomography, a frozen specimen is imaged at many tilt angles and the views are combined to reconstruct a 3D volume.",
            topics: ["microscopy", "imaging", "cell biology"],
            also: ["cryo-ET", "tomography", "back-projection", "cryo-EM"]),
        "AFM scan": SpecimenNote(
            caption: "A fine tip feeling a surface",
            note: "Atomic force microscopy scans a sharp tip on a cantilever across a surface, mapping its height to image molecules such as DNA.",
            topics: ["microscopy", "imaging"],
            also: ["atomic force microscopy", "cantilever", "scanning probe", "topography"]),
        "Chladni plate": SpecimenNote(
            caption: "Sand gathering on still lines",
            note: "Chladni figures form when sand collects on the nodal lines of a vibrating plate, revealing its resonant modes at different frequencies.",
            topics: ["waves", "physics"],
            also: ["nodal lines", "resonance", "vibration", "sand figures"]),
        "Pendulum wave": SpecimenNote(
            caption: "Pendulums drifting out of step",
            note: "A pendulum wave is a row of pendulums with graded lengths whose differing periods make traveling waves and patterns before realigning.",
            topics: ["waves", "mechanics", "physics"],
            also: ["pendulum array", "period", "interference", "beats"]),
        "Laser": SpecimenNote(
            caption: "Light amplified between mirrors",
            note: "A laser amplifies light by stimulated emission: excited atoms in a cavity add photons in step, producing a coherent, narrow beam.",
            topics: ["optics", "physics", "quantum"],
            also: ["stimulated emission", "coherent light", "optical cavity", "population inversion"]),
        "Doppler effect": SpecimenNote(
            caption: "Pitch shifting as a source passes",
            note: "The Doppler effect is the change in a wave's observed frequency when source and observer move relative to each other, as with a siren.",
            topics: ["waves", "physics", "astronomy"],
            also: ["redshift", "siren", "frequency shift", "wavefronts"]),
        "Brownian motion": SpecimenNote(
            caption: "A grain jittering in random steps",
            note: "Brownian motion is the random jiggling of small particles from molecular collisions; Einstein's analysis helped prove molecules are real.",
            topics: ["physics", "thermodynamics"],
            also: ["random walk", "diffusion", "pollen", "Einstein"]),
        "Ferrofluid": SpecimenNote(
            caption: "Magnetic liquid rising in spikes",
            note: "Ferrofluid is a liquid of magnetic nanoparticles that rises into spikes in a magnetic field, an effect called the normal-field instability.",
            topics: ["physics", "electromagnetism"],
            also: ["magnetic fluid", "Rosensweig instability", "nanoparticles", "magnet"]),
        "Iron filings": SpecimenNote(
            caption: "Filings revealing field lines",
            note: "Iron filings near a magnet line up along its magnetic field lines and crowd at the poles, making the invisible field visible.",
            topics: ["electromagnetism", "physics"],
            also: ["magnetic field", "bar magnet", "field lines", "dipole"]),
        "Standing waves": SpecimenNote(
            caption: "A string vibrating in harmonics",
            note: "A string fixed at both ends supports standing waves at whole-number multiples of its fundamental frequency, with still nodes between.",
            topics: ["waves", "physics"],
            also: ["harmonics", "nodes", "resonance", "overtones"]),
        "Prism": SpecimenNote(
            caption: "White light splitting into colors",
            note: "A prism disperses white light into a spectrum because glass bends shorter wavelengths more, so violet is deflected more than red.",
            topics: ["optics", "physics"],
            also: ["dispersion", "refraction", "spectrum", "rainbow"]),
        "Faraday coil": SpecimenNote(
            caption: "A moving magnet inducing current",
            note: "Faraday's law of induction says a changing magnetic flux through a coil induces a voltage, the principle behind generators and transformers.",
            topics: ["electromagnetism", "physics"],
            also: ["electromagnetic induction", "galvanometer", "generator", "Faraday's law"]),
        "Van de Graaff": SpecimenNote(
            caption: "Charge building up, then sparking",
            note: "A Van de Graaff generator carries charge on a moving belt to a metal dome, building a very high voltage until it discharges as a spark.",
            topics: ["electromagnetism", "physics"],
            also: ["electrostatics", "static electricity", "high voltage", "generator"]),
        "Half-life": SpecimenNote(
            caption: "Half the nuclei gone each half-life",
            note: "Half-life is the time for half of a radioactive sample's nuclei to decay; it is fixed for each isotope and used for dating and medicine.",
            topics: ["physics"],
            also: ["radioactive decay", "exponential decay", "isotope", "radiometric dating"]),
        "Gyroscope": SpecimenNote(
            caption: "A spinning rotor precessing slowly",
            note: "A gyroscope's spinning rotor resists changes in orientation, and gravity's torque makes its axis precess slowly instead of toppling.",
            topics: ["mechanics", "physics"],
            also: ["angular momentum", "precession", "rotor", "spinning top"]),
        "Newton's rings": SpecimenNote(
            caption: "Rings of light from a thin air gap",
            note: "Newton's rings are interference fringes seen where a curved lens touches a flat plate, caused by the thin, varying air gap between them.",
            topics: ["optics", "waves", "physics"],
            also: ["thin-film interference", "interference fringes", "lens", "air gap"]),
        "Capillary fill": SpecimenNote(
            caption: "Liquid climbing thin tubes",
            note: "Capillary action draws liquid up narrow tubes by surface tension, and the thinner the tube, the higher it rises, as Jurin's law describes.",
            topics: ["physics"],
            also: ["capillary action", "surface tension", "meniscus", "Jurin's law"]),
        "Seedling": SpecimenNote(
            caption: "A seed sprouting into leaves",
            note: "A germinating seed sends a shoot up through the soil and unfolds its first leaves, starting life as a photosynthesizing seedling.",
            topics: ["plants", "development"],
            also: ["germination", "sprout", "cotyledon", "seed"]),
        "Dandelion": SpecimenNote(
            caption: "Seeds floating off on the wind",
            note: "Dandelion seeds (technically small fruits) carry a feathery pappus that works as a parachute, so wind can carry them far from the parent.",
            topics: ["plants", "ecology"],
            also: ["seed dispersal", "pappus", "wind dispersal", "Taraxacum"]),
        "Stomata": SpecimenNote(
            caption: "Pores opening for gas exchange",
            note: "Stomata are leaf pores opened and closed by paired guard cells, letting CO₂ in for photosynthesis and water vapor out.",
            topics: ["plants", "cell biology"],
            also: ["stoma", "guard cells", "gas exchange", "transpiration"]),
        "Bloom": SpecimenNote(
            caption: "A flower bud opening",
            note: "Anthesis is the opening of a flower, which exposes its reproductive organs to pollinators as the petals expand.",
            topics: ["plants", "development"],
            also: ["anthesis", "petals", "flowering", "blossom"]),
        "Photosynthesis": SpecimenNote(
            caption: "A leaf turning light into sugar",
            note: "Photosynthesis uses light energy to turn carbon dioxide and water into sugars, releasing oxygen as a by-product.",
            topics: ["plants", "metabolism"],
            also: ["chloroplast", "chlorophyll", "carbon fixation", "oxygen"]),
        "Roots": SpecimenNote(
            caption: "Roots branching through soil",
            note: "A primary root grows down from its tip and forms lateral roots, building the network that takes up water and nutrients.",
            topics: ["plants", "development"],
            also: ["lateral roots", "root system", "root tip", "root meristem"]),
        "Mushroom": SpecimenNote(
            caption: "A mushroom releasing spores",
            note: "A mushroom is the fruiting body of a fungus, releasing huge numbers of spores from its gills or pores to spread the organism.",
            topics: ["microbiology", "ecology"],
            also: ["fungus", "spores", "fruiting body", "basidiomycete"]),
        "Phototropism": SpecimenNote(
            caption: "A shoot bending toward light",
            note: "Phototropism is growth toward light, driven by auxin that builds up on the shaded side of a shoot and makes it elongate faster.",
            topics: ["plants", "signaling"],
            also: ["auxin", "tropism", "phototropin", "shoot"]),
        "Subduction": SpecimenNote(
            caption: "One plate sliding under another",
            note: "At a subduction zone, one tectonic plate sinks beneath another, and water it releases helps melt the mantle above, feeding volcanoes.",
            topics: ["earth science"],
            also: ["plate tectonics", "volcano", "oceanic crust", "magma"]),
        "Phyllotaxis": SpecimenNote(
            caption: "Seeds spiraling into a sunflower",
            note: "Phyllotaxis is the arrangement of leaves or seeds on a plant; the golden angle of 137.5° packs a sunflower head with Fibonacci spirals.",
            topics: ["plants", "development", "math"],
            also: ["golden angle", "Fibonacci", "sunflower", "spiral"]),
        "Mycorrhizal network": SpecimenNote(
            caption: "Fungal threads linking tree roots",
            note: "Mycorrhizal fungi form networks on and in roots that trade soil nutrients for plant sugars and can connect neighboring plants.",
            topics: ["plants", "ecology", "microbiology"],
            also: ["wood wide web", "mycorrhiza", "fungal network", "symbiosis"]),
        "Tree rings": SpecimenNote(
            caption: "A trunk recording its years",
            note: "Tree rings are yearly growth layers whose widths reflect conditions such as drought, used to date wood and read past climate.",
            topics: ["plants", "earth science"],
            also: ["dendrochronology", "annual rings", "drought", "climate record"]),
        "Mimosa": SpecimenNote(
            caption: "A leaf folding shut when touched",
            note: "Mimosa pudica folds its leaflets within seconds of a touch, as water pressure shifts in cells at the leaf joints.",
            topics: ["plants", "signaling"],
            also: ["Mimosa pudica", "sensitive plant", "thigmonasty", "touch response"]),
        "Venus flytrap": SpecimenNote(
            caption: "A trap snapping shut on a fly",
            note: "A Venus flytrap snaps shut when its trigger hairs are touched twice in quick succession, which helps avoid wasting energy on false alarms.",
            topics: ["plants", "signaling"],
            also: ["Dionaea muscipula", "carnivorous plant", "trigger hairs", "insect trap"]),
        "Pollen tube": SpecimenNote(
            caption: "A pollen tube growing to the ovule",
            note: "After landing on a stigma, a pollen grain grows a tube down the style that carries sperm cells to the ovule for fertilization.",
            topics: ["plants", "development"],
            also: ["fertilization", "stigma", "style", "pollination"]),
        "Clustered heatmap": SpecimenNote(
            caption: "Rows sorted into similar groups",
            note: "A clustered heatmap shows a data matrix as color-coded values, with rows and columns ordered by similarity so related groups stand out.",
            topics: ["data", "statistics", "bioinformatics"],
            also: ["hierarchical clustering", "dendrogram", "gene expression", "heat map"]),
        "Violin and bracket": SpecimenNote(
            caption: "Two groups compared in violins",
            note: "A violin plot shows each group's full distribution, and a bracket with stars marks a significant difference between two groups.",
            topics: ["statistics", "data"],
            also: ["violin plot", "significance stars", "p-value", "box plot"]),
        "PCA": SpecimenNote(
            caption: "Finding the axis of most variation",
            note: "Principal component analysis finds the directions of greatest variance in many-dimensional data so it can be summarized in fewer dimensions.",
            topics: ["statistics", "data", "machine learning"],
            also: ["principal component analysis", "dimensionality reduction", "variance", "principal components"]),
        "Forest plot": SpecimenNote(
            caption: "Studies pooled into one estimate",
            note: "A forest plot shows each study's effect estimate and confidence interval, with a pooled diamond summarizing them in a meta-analysis.",
            topics: ["statistics", "medicine", "data"],
            also: ["meta-analysis", "confidence interval", "pooled estimate", "systematic review"]),
        "ROC curve": SpecimenNote(
            caption: "Sensitivity against false positives",
            note: "An ROC curve plots a test's true-positive rate against its false-positive rate across thresholds; the area under it measures discrimination.",
            topics: ["statistics", "machine learning", "medicine"],
            also: ["receiver operating characteristic", "AUC", "sensitivity", "specificity"]),
        "Ridgeline": SpecimenNote(
            caption: "Stacked distributions compared",
            note: "A ridgeline plot stacks partly overlapping density curves, one per group or condition, to show how distributions shift between them.",
            topics: ["data", "statistics"],
            also: ["joyplot", "density plot", "distributions", "ridge plot"]),
        "Blot figure": SpecimenNote(
            caption: "Preparing a western blot figure",
            note: "Preparing a western blot figure means cropping to the relevant lanes, labeling each lane and marking molecular-weight sizes by the bands.",
            topics: ["electrophoresis", "data", "lab life"],
            also: ["western blot", "figure preparation", "vector graphics", "lane labels"]),
        "Blot annotation": SpecimenNote(
            caption: "Marking up and quantifying a blot",
            note: "Western blot analysis marks the band of interest against the molecular-weight ladder and normalizes its intensity to a loading control.",
            topics: ["electrophoresis", "measurement"],
            also: ["western blot", "loading control", "densitometry", "band quantification"]),
        "Clonogenic survival": SpecimenNote(
            caption: "Colonies surviving rising radiation",
            note: "A clonogenic survival curve plots the fraction of cells that can still form colonies after radiation; radiosensitizers make it fall faster.",
            topics: ["cell culture", "medicine"],
            also: ["radiosensitizer", "colony formation assay", "linear-quadratic", "radiation dose"]),
        "Dose response": SpecimenNote(
            caption: "Response falling as dose rises",
            note: "A dose-response curve fits a sigmoid to response against log dose, and the IC50 marks the dose giving half-maximal inhibition.",
            topics: ["drug discovery", "data"],
            also: ["IC50", "EC50", "sigmoid", "pharmacology"]),
        "Curve fit": SpecimenNote(
            caption: "Points landing on a fitted curve",
            note: "Curve fitting finds the parameters of a model, such as a saturating curve, that best match measured data points, usually by least squares.",
            topics: ["data", "statistics", "measurement"],
            also: ["regression", "least squares", "saturation curve", "nonlinear fit"]),
        "Alignment": SpecimenNote(
            caption: "Sequences lined up by shared sites",
            note: "A multiple sequence alignment lines up DNA or protein sequences so matching positions share a column, revealing conserved regions.",
            topics: ["bioinformatics", "genomics"],
            also: ["MSA", "conserved residues", "Clustal", "MUSCLE"]),
        "Read mapping": SpecimenNote(
            caption: "Reads snapping onto a reference",
            note: "Read mapping aligns short sequencing reads to a reference genome to find where each came from; the stacked reads give coverage.",
            topics: ["sequencing", "genomics", "bioinformatics"],
            also: ["alignment", "BWA", "coverage", "BAM"]),
        "Single cell": SpecimenNote(
            caption: "Cells gathering into clusters",
            note: "Single-cell RNA-seq data are clustered by similar gene expression so groups of cells can be identified as distinct cell types or states.",
            topics: ["sequencing", "bioinformatics"],
            also: ["scRNA-seq", "clustering", "UMAP", "cell types"]),
        "Homology search": SpecimenNote(
            caption: "Searching a database for matches",
            note: "A homology search such as BLAST compares a query with a database to find similar sequences that likely share ancestry or function.",
            topics: ["bioinformatics", "genomics"],
            also: ["BLAST", "sequence similarity", "database search", "local alignment"]),
        "Phylogeny": SpecimenNote(
            caption: "Finding the best-supported tree",
            note: "Phylogenetic inference builds a tree of evolutionary relationships from sequences, comparing candidate trees to find the best-supported one.",
            topics: ["evolution", "bioinformatics", "genomics"],
            also: ["phylogenetic tree", "tree of life", "maximum likelihood", "clade"]),
        "Variant calling": SpecimenNote(
            caption: "Spotting a variant in stacked reads",
            note: "Variant calling finds positions where a sample's sequencing reads consistently differ from the reference, such as SNPs and small indels.",
            topics: ["genomics", "sequencing", "bioinformatics"],
            also: ["SNP", "mutation", "VCF", "genotyping"]),
        "Basecalling": SpecimenNote(
            caption: "Reading bases from nanopore current",
            note: "Nanopore basecalling converts the changing electrical current as DNA passes through a pore into a sequence of A, C, G and T.",
            topics: ["sequencing", "genomics"],
            also: ["Oxford Nanopore", "nanopore", "squiggle", "long reads"]),
        "Assembly": SpecimenNote(
            caption: "Fragments joining into one contig",
            note: "Genome assembly stitches overlapping sequencing reads into longer contiguous sequences, or contigs, to reconstruct a genome.",
            topics: ["genomics", "sequencing", "bioinformatics"],
            also: ["contig", "de novo assembly", "overlap", "scaffold"]),
        "K-means": SpecimenNote(
            caption: "Centroids settling into clusters",
            note: "k-means clustering splits data into k groups by assigning each point to its nearest centroid and moving each centroid to its group's mean.",
            topics: ["machine learning", "statistics", "data"],
            also: ["clustering", "centroid", "unsupervised learning", "Lloyd's algorithm"]),
        "Action potential": SpecimenNote(
            caption: "A neuron firing, as recorded",
            note: "An action potential is a brief spike in a neuron's membrane voltage after it crosses threshold, the signal that travels along axons.",
            topics: ["neuroscience", "signaling", "membranes"],
            also: ["spike", "membrane potential", "neuron", "electrophysiology"]),
        "De Bruijn": SpecimenNote(
            caption: "Finding one path through a graph",
            note: "A de Bruijn graph links overlapping k-mers from sequencing reads; assemblers prune dead ends and tangles to find the genome's path.",
            topics: ["bioinformatics", "genomics"],
            also: ["k-mer", "assembly graph", "genome assembly", "Eulerian path"]),
        "Pangenome": SpecimenNote(
            caption: "Variation as alternate routes",
            note: "A pangenome graph represents many genomes at once, with bubbles where individuals carry different alleles along a shared path.",
            topics: ["genomics", "bioinformatics"],
            also: ["graph genome", "variation graph", "alleles", "structural variants"]),
        "Phasing": SpecimenNote(
            caption: "Sorting variants onto two copies",
            note: "Haplotype phasing assigns variants to the maternal or paternal copy of a chromosome, using reads that span several variants.",
            topics: ["genomics", "sequencing", "bioinformatics"],
            also: ["haplotype", "phased genome", "diploid", "long reads"]),
        "Binning": SpecimenNote(
            caption: "Contigs gathering into genome bins",
            note: "Metagenomic binning groups contigs from a mixed community into bins, each approximating one organism's genome, by coverage and composition.",
            topics: ["genomics", "microbiology", "bioinformatics"],
            also: ["metagenomics", "MAG", "metagenome-assembled genome", "contigs"]),
        "Spatial UMAP": SpecimenNote(
            caption: "Tissue spots mapped into clusters",
            note: "Spatial transcriptomics measures gene expression at spots in a tissue; clustering spots by expression reveals cell types, shown in a UMAP.",
            topics: ["genomics", "bioinformatics"],
            also: ["spatial transcriptomics", "UMAP", "Visium", "embedding"]),
        "Synteny": SpecimenNote(
            caption: "Gene order conserved between species",
            note: "Synteny is the conservation of gene order between genomes, used to trace shared ancestry and rearrangements between species.",
            topics: ["genomics", "evolution", "bioinformatics"],
            also: ["conserved synteny", "genome comparison", "collinearity", "rearrangement"]),
        "Mass spec": SpecimenNote(
            caption: "A peptide broken into fragments",
            note: "Tandem mass spectrometry breaks a peptide into fragments and measures their masses, and the pattern reveals its amino acid sequence.",
            topics: ["mass spectrometry", "chemistry"],
            also: ["MS/MS", "peptide sequencing", "proteomics", "fragmentation"]),
        "Demultiplex": SpecimenNote(
            caption: "Reads sorted by barcode",
            note: "Demultiplexing sorts pooled sequencing reads back into separate samples using the short barcode sequences added to each sample.",
            topics: ["sequencing", "bioinformatics", "genomics"],
            also: ["barcode", "index", "multiplexing", "FASTQ"]),
        "Copy number": SpecimenNote(
            caption: "Gains and losses along a chromosome",
            note: "A copy-number profile plots how many copies of each genome region are present; gains and losses are common in cancer.",
            topics: ["genomics", "data"],
            also: ["CNV", "amplification", "deletion", "aneuploidy"]),
        "Spectra": SpecimenNote(
            caption: "Excitation, emission and a filter",
            note: "A fluorophore absorbs light in its excitation spectrum and emits at longer wavelengths; filters pass the emission and block the laser.",
            topics: ["spectroscopy", "microscopy", "imaging"],
            also: ["fluorescence", "Stokes shift", "band-pass filter", "fluorophore"]),
        "Tree of life": SpecimenNote(
            caption: "Branching lineages around a circle",
            note: "A tree of life shows evolutionary relationships among organisms as branches from a common root; circular layouts fit many tips.",
            topics: ["evolution", "bioinformatics"],
            also: ["phylogenetic tree", "phylogeny", "clade", "taxonomy"]),
        "Droplet barcoding": SpecimenNote(
            caption: "A cell and bead sealed in a droplet",
            note: "In droplet-based single-cell sequencing, each cell is captured with a barcoded bead so its RNA is tagged with a barcode unique to that cell.",
            topics: ["sequencing", "genomics", "RNA"],
            also: ["10x Genomics", "Drop-seq", "single-cell", "microfluidics"]),
        "qPCR curves": SpecimenNote(
            caption: "Dilutions crossing the threshold",
            note: "In qPCR, the cycle where fluorescence crosses a threshold (Ct) comes earlier with more starting template, which lets amounts be quantified.",
            topics: ["PCR", "measurement"],
            also: ["real-time PCR", "Ct", "standard curve", "amplification"]),
        "Melt curve": SpecimenNote(
            caption: "DNA melting as temperature rises",
            note: "A qPCR melt curve tracks fluorescence as double-stranded DNA melts; one sharp peak in its derivative suggests a single specific product.",
            topics: ["PCR", "measurement"],
            also: ["melting temperature", "Tm", "primer dimer", "SYBR Green"]),
        "Flow dot plot": SpecimenNote(
            caption: "Cells gated by size and granularity",
            note: "Flow cytometry plots each cell by size and granularity, and a gate selects one population, such as lymphocytes, for further analysis.",
            topics: ["cell biology", "measurement", "data"],
            also: ["FACS", "forward scatter", "side scatter", "gating"]),
        "Sort purity": SpecimenNote(
            caption: "Sorting cells and checking purity",
            note: "Cell sorting separates a gated population from a mixture, and re-running the sorted sample on the cytometer checks how pure it is.",
            topics: ["cell biology", "separation", "measurement"],
            also: ["FACS", "cell sorter", "purity check", "gating"]),
        "Illumina sequencing": SpecimenNote(
            caption: "Reading DNA one base per cycle",
            note: "Illumina sequencing by synthesis images clusters of copied DNA on a flow cell, reading one fluorescent base per cycle to build each read.",
            topics: ["sequencing", "genomics"],
            also: ["Illumina", "sequencing by synthesis", "flow cell", "NGS"]),
        "Fourier epicycles": SpecimenNote(
            caption: "Circles on circles tracing a wave",
            note: "A Fourier series builds a periodic wave from sine waves; odd harmonics with amplitudes falling as 1/n add up to a square wave.",
            topics: ["math", "waves", "data"],
            also: ["Fourier series", "square wave", "harmonics", "Fourier transform"]),
        "Volcano plot": SpecimenNote(
            caption: "Fold change against significance",
            note: "A volcano plot graphs each gene's fold change against its statistical significance, making strongly and reliably changed genes easy to spot.",
            topics: ["statistics", "genomics", "data"],
            also: ["differential expression", "fold change", "p-value", "RNA-seq"]),
        "Manhattan plot": SpecimenNote(
            caption: "Significance peaks along chromosomes",
            note: "A Manhattan plot shows each genetic variant's significance by genome position, and peaks above the threshold flag candidate loci in GWAS.",
            topics: ["genomics", "statistics", "data"],
            also: ["GWAS", "genome-wide association", "genome-wide significance", "SNP"]),
        "Neural network": SpecimenNote(
            caption: "Signals flowing through layers",
            note: "A neural network passes inputs through layers of weighted units, each with a nonlinearity, to produce an output such as a class label.",
            topics: ["machine learning", "data"],
            also: ["deep learning", "layers", "activations", "AI"]),
        "Kaplan–Meier": SpecimenNote(
            caption: "Survival curves for two groups",
            note: "A Kaplan–Meier plot estimates the fraction of patients surviving over time, marking censored patients, to compare treatments.",
            topics: ["statistics", "medicine", "data"],
            also: ["survival analysis", "censoring", "log-rank", "hazard"]),
        "Sequence logo": SpecimenNote(
            caption: "Conserved positions as tall letters",
            note: "A sequence logo shows each position of aligned sequences as stacked letters, with height showing information content and conservation.",
            topics: ["bioinformatics", "genomics"],
            also: ["motif", "information content", "WebLogo", "binding site"]),
        "Transit": SpecimenNote(
            caption: "A planet dimming its star",
            note: "In the transit method, a planet crossing its star briefly dims the starlight, revealing the planet's size and orbit.",
            topics: ["astronomy"],
            also: ["exoplanet", "light curve", "Kepler", "TESS"]),
        "Lagrange": SpecimenNote(
            caption: "A body trailing a planet by 60°",
            note: "Lagrange points are places where gravity and orbital motion balance; an object at L4 or L5 stays 60° ahead of or behind a planet.",
            topics: ["astronomy", "mechanics", "physics"],
            also: ["L4", "L5", "Trojan asteroids", "three-body problem"]),
        "Einstein ring": SpecimenNote(
            caption: "Gravity bending light into a ring",
            note: "An Einstein ring forms when a massive object's gravity bends light from a source behind it into a ring, a form of gravitational lensing.",
            topics: ["astronomy", "physics"],
            also: ["gravitational lensing", "lens", "general relativity", "arc"]),
        "Aurora": SpecimenNote(
            caption: "Solar particles lighting the poles",
            note: "Auroras glow when charged particles, energized by the solar wind and guided by Earth's field, strike upper-atmosphere gases near the poles.",
            topics: ["earth science", "astronomy", "physics"],
            also: ["northern lights", "aurora borealis", "solar wind", "magnetosphere"]),
        "JWST mirror": SpecimenNote(
            caption: "Mirror segments aligning to focus",
            note: "The James Webb Space Telescope's 18 hexagonal mirror segments are adjusted individually so they act as one mirror with a single focus.",
            topics: ["astronomy", "optics"],
            also: ["James Webb", "telescope", "wavefront sensing", "segmented mirror"]),
        "Saturn": SpecimenNote(
            caption: "A ringed planet with a moon",
            note: "Saturn is a gas giant circled by broad rings of mostly water ice, with gaps such as the Cassini Division, and by many moons.",
            topics: ["astronomy"],
            also: ["rings", "Cassini Division", "gas giant", "moon"]),
        "Cold front": SpecimenNote(
            caption: "Cold air wedging under warm air",
            note: "At a cold front, dense cold air pushes under warmer air and lifts it, often producing a band of clouds, showers or thunderstorms.",
            topics: ["weather", "earth science"],
            also: ["weather front", "meteorology", "warm air", "frontal lifting"]),
        "Hurricane": SpecimenNote(
            caption: "A storm spiraling around its eye",
            note: "A hurricane is a tropical cyclone with spiral rainbands around a calm eye; in the Northern Hemisphere it rotates counterclockwise.",
            topics: ["weather", "earth science"],
            also: ["tropical cyclone", "typhoon", "eye", "rainbands"]),
        "Thunderstorm": SpecimenNote(
            caption: "A storm cloud growing and striking",
            note: "Thunderstorms grow from tall cumulonimbus clouds whose rising air builds an anvil top, and charge separation inside makes lightning.",
            topics: ["weather", "earth science"],
            also: ["lightning", "cumulonimbus", "anvil", "convection"]),
        "Barometer": SpecimenNote(
            caption: "Falling pressure forecasting rain",
            note: "An aneroid barometer measures air pressure with a flexible sealed metal capsule; falling pressure usually signals stormy, wetter weather.",
            topics: ["weather", "measurement"],
            also: ["air pressure", "aneroid", "atmospheric pressure", "forecast"]),
        "Snowflake": SpecimenNote(
            caption: "A snow crystal growing six arms",
            note: "Snow crystals grow from water vapor into six-fold shapes because ice's hexagonal lattice and the same conditions shape each arm alike.",
            topics: ["weather", "physics"],
            also: ["ice crystal", "dendrite", "hexagonal symmetry", "crystal growth"]),
        "Seismograph": SpecimenNote(
            caption: "Quake waves arriving at a station",
            note: "A seismograph records ground motion: P waves arrive first, then slower S waves, then surface waves, which help locate and size a quake.",
            topics: ["earth science", "waves", "measurement"],
            also: ["earthquake", "P wave", "S wave", "seismogram"]),
        "Water cycle": SpecimenNote(
            caption: "Water cycling between sea and sky",
            note: "The water cycle moves water by evaporation, condensation, precipitation and runoff among the oceans, atmosphere and land.",
            topics: ["earth science", "weather", "ecology"],
            also: ["hydrologic cycle", "evaporation", "precipitation", "runoff"]),
        "Eruption": SpecimenNote(
            caption: "A volcano throwing ash and lava",
            note: "A volcanic eruption expels ash, gas and lava as magma reaches the surface; a tall ash column can spread into an umbrella cloud.",
            topics: ["earth science"],
            also: ["volcano", "lava", "ash plume", "magma"]),
        "Tornado": SpecimenNote(
            caption: "A funnel touching down",
            note: "A tornado is a violently rotating column of air reaching from a thunderstorm to the ground, seen as a funnel with a swirl of debris.",
            topics: ["weather", "earth science"],
            also: ["funnel cloud", "supercell", "twister", "vortex"]),
    ]
}
