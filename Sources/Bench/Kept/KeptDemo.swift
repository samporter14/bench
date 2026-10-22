// KeptDemo.swift — `--demo kept` (DESIGN.md, Keep and Shelf): the Keep sheet
// filled from made-up reads, and the Shelf window on made-up folders in a
// temporary root: figures, documents and tables put on the shelf, and one
// figure kept with its data and code. Nothing is read from Claude Science;
// nothing lands outside the temporary root, which is deleted when Capsid quits.
import AppKit
import SwiftUI

@MainActor
enum KeptDemo {
    private static let session = SessionStatus(
        id: "00000000-0000-4000-8000-0000000000d8", projectID: "demo-assay", projectName: "Assay development",
        title: "Plate reader QC", state: .finished, updatedAt: Date().addingTimeInterval(-50 * 60),
        startedAt: Date().addingTimeInterval(-70 * 60))

    private static let versions: [(v: String, n: Int, minutesAgo: Double, size: Int)] = [
        ("aaaaaaaa-0000-4000-8000-000000000001", 1, 61, 81_920),
        ("aaaaaaaa-0000-4000-8000-000000000002", 2, 58, 83_456),
        ("aaaaaaaa-0000-4000-8000-000000000003", 3, 53, 86_016),
        ("aaaaaaaa-0000-4000-8000-000000000004", 4, 51, 85_000),
    ]
    private static let artifact = "bbbbbbbb-0000-4000-8000-000000000001"
    private static let dataVersion = "cccccccc-0000-4000-8000-000000000001"
    private static let answer = "All plates passed except plate 7, which has an edge effect in column 12. It\u{2019}s flagged and left out of the cleaned table; the other eleven are unchanged."
    private static let script = """
    import pandas as pd
    import matplotlib.pyplot as plt

    plates = pd.read_csv("{{artifact:cccccccc-0000-4000-8000-000000000001}}")
    plates = plates[plates.plate != 7]
    plates.plot.bar(x="plate", y="z_prime", legend=False)
    plt.savefig("z_prime.png", dpi=200)
    """

    private static var keepModel: KeepModel?

    static func show(step: String, quiet: Bool, present: (AnyView, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Capsid Kept demo-\(UUID().uuidString)", isDirectory: true)
        let disk = KeptDisk(root: { root })
        switch step {
        case "window", "window-empty":
            let index = KeptIndex(disk: disk, root: { root })
            let shelf = shelf(index: index, root: root)
            Task { @MainActor in
                if step == "window" { await seed(disk) }
                KeptWindowController.shared.show(shelf: shelf)
            }
        default:
            let model = makeModel(disk: disk, root: root, failingData: step == "sheet-partial")
            keepModel = model
            present(AnyView(KeepSheet(model: model, dismiss: {})), "Keep")
            if step == "sheet-partial" {
                Task { @MainActor in
                    while model.readingProvenance || model.phase == .reading { try? await Task.sleep(for: .milliseconds(100)) }
                    model.keep()
                }
            }
        }
    }

    // MARK: The sheet's made-up reads

    /// The sheet's model on made-up reads, for a snapshot test or a demo.
    static func sheetModel(root: URL, failingData: Bool = false) -> KeepModel {
        makeModel(disk: KeptDisk(root: { root }), root: root, failingData: failingData)
    }

    private static func makeModel(disk: KeptDisk, root: URL, failingData: Bool) -> KeepModel {
        let entry = ArtifactEntry(version: versions[3].v, artifact: artifact, name: "z_prime.png", mime: "image/png",
                                  size: versions[3].size, at: at(versions[3].minutesAgo))
        return KeepModel(subject: KeepSubject(session: session, entry: entry),
                         dependencies: dependencies(disk: disk, root: root, failingData: failingData))
    }

    /// The Shelf on made-up folders: its reads answer nothing, as the Keep
    /// sheet's do for a figure that isn't there.
    static func shelf(index: KeptIndex, root: URL) -> Shelf {
        Shelf(index: index, dependencies: {
            ShelfDependencies(keep: dependencies(disk: index.disk, root: root, failingData: false), question: { _, _ in nil })
        })
    }

    private static func dependencies(disk: KeptDisk, root: URL, failingData: Bool) -> KeepDependencies {
        let thumbnails = ShelfThumbnails()
        for (index, version) in versions.enumerated() {
            thumbnails.receive(chart(variant: index), for: version.v)
        }
        return KeepDependencies(
            read: { read in
                try? await Task.sleep(for: .milliseconds(150))
                switch read {
                case .facts(let v):
                    if v == dataVersion {
                        return .answered(.facts(ArtifactFacts(v: v, a: "dddddddd-0000-4000-8000-000000000001", n: 1, name: "z_prime_by_plate.csv",
                                                              mime: "text/csv", size: 4096, at: at(62), sha: nil, isUpload: false,
                                                              code: nil, codeCut: false, environment: nil)))
                    }
                    guard let version = versions.first(where: { $0.v == v }) else { return .answered(.missing) }
                    return .answered(.facts(ArtifactFacts(v: v, a: artifact, n: version.n, name: "z_prime.png", mime: "image/png",
                                                          size: version.size, at: at(version.minutesAgo), sha: nil, isUpload: false,
                                                          code: nil, codeCut: false, environment: nil)))
                case .versions:
                    return .answered(.versions(versions.map {
                        ArtifactVersion(v: $0.v, n: $0.n, frame: session.id, mime: "image/png", size: $0.size, at: at($0.minutesAgo), parent: nil)
                    }))
                case .lineage(let v):
                    return .answered(.lineage(ArtifactLineage(
                        v: v, code: script, codeCut: false, description: nil, language: "python", pending: false,
                        unavailableModel: nil, unavailableReason: nil, hasCells: true, hasEnvironment: true, mappingStatus: "complete",
                        inputs: [LineageInput(v: dataVersion, a: "dddddddd-0000-4000-8000-000000000001", name: "z_prime_by_plate.csv",
                                              file: nil, how: "runtime", inferred: false)])))
                case .download(let v):
                    if v == dataVersion {
                        return failingData ? .timedOut : .answered(.bytes(csv()))
                    }
                    if let index = versions.firstIndex(where: { $0.v == v }) { return .answered(.bytes(chart(variant: index))) }
                    return .answered(.missing)
                case .thumb, .text, .list:
                    return .answered(.unreadable)
                }
            },
            showing: { _, _, _ in
                try? await Task.sleep(for: .milliseconds(200))
                return .found(ShowingMessage(i: 41, at: at(50), text: answer, how: .image, v: versions[2].v))
            },
            lastAnswer: { _ in nil },
            thumbnails: thumbnails,
            disk: disk,
            defaults: UserDefaults(suiteName: "kept-demo-\(UUID().uuidString)")!,
            root: { root },
            scienceVersion: { "0.1.70" },
            capsidVersion: "1.0",
            now: { Date() },
            didKeep: { _ in })
    }

    private static func at(_ minutesAgo: Double) -> Date { Date().addingTimeInterval(-minutesAgo * 60) }

    // MARK: Made-up folders

    /// One thing on the made-up shelf.
    private struct Seed {
        let file: String
        let data: Data
        let session: String
        let project: String
        let collection: String
        let version: String
        /// How long ago it was put on the shelf.
        let minutesAgo: Double
        let answer: String
        let question: String?
        let row: Int
    }

    private static func version(_ n: Int) -> String { String(format: "eeeeeeee-0000-4000-8000-%012d", n) }

    /// The made-up shelf: the mock-up's first row (a figure, a heatmap, a
    /// Markdown note, a spreadsheet), more of each kind below it, and one
    /// figure kept with its data and code.
    private static func seeds() -> [Seed] {
        let qc = "Plate reader QC", assay = "Assay development"
        return [
            Seed(file: "z_prime_by_plate.png", data: chart(variant: 2), session: qc, project: assay, collection: assay, version: version(1),
                 minutesAgo: 20, answer: "Plate 7 is the low bar, at 0.41 against a cutoff of 0.5; the other eleven sit between 0.62 and 0.78.",
                 question: "Plot Z\u{2032} by plate, and show me where plate 7 goes wrong.", row: 41),
            Seed(file: "plate_7_heatmap.png", data: heatmap(variant: 0), session: qc, project: assay, collection: assay, version: version(2),
                 minutesAgo: 21, answer: "The heatmap puts plate 7 beside plate 8: the edge effect is in column 12 alone.",
                 question: "Show plate 7 as a heatmap.", row: 43),
            Seed(file: "qc_notes.md", data: notes(), session: qc, project: assay, collection: assay, version: version(3),
                 minutesAgo: 35, answer: "Eleven plates pass with Z\u{2032} between 0.62 and 0.78. Plate 7 fails because of an edge effect in column 12. Repeat plate 7 with a fresh seal.",
                 question: "Write up the QC for the notebook.", row: 47),
            Seed(file: "receptors.xlsx", data: xlsx(), session: "ER-phagy receptors", project: "Receptor biology", collection: "Receptor biology",
                 version: version(4), minutesAgo: 3 * 1440 + 10, answer: "Eleven receptors carry an LC3-interacting region; four of them are annotated for the endoplasmic reticulum.",
                 question: "Which ER-phagy receptors have an LIR motif?", row: 22),
            Seed(file: "z_prime_by_plate.csv", data: csv(), session: qc, project: assay, collection: assay, version: version(5),
                 minutesAgo: 1440 + 40, answer: "The table behind the figure: one row for each plate, with its Z\u{2032}.", question: nil, row: 39),
            Seed(file: "knockdown_blot.png", data: chart(variant: 1), session: "Western blot quantification", project: "Knockdown validation",
                 collection: "Knockdown validation", version: version(6), minutesAgo: 5 * 1440, answer: "The knockdown holds at 72 hours: the band at 55 kDa is down by about 80%.",
                 question: "Quantify the knockdown.", row: 30),
            Seed(file: "de_heatmap.png", data: heatmap(variant: 1), session: "Differential expression, KO vs WT", project: "RNA-seq pilot",
                 collection: "RNA-seq pilot", version: version(7), minutesAgo: 9 * 1440, answer: "Forty genes pass the cutoff; the heatmap clusters the knockout away from the wild type.",
                 question: "Cluster the differentially expressed genes.", row: 64),
            Seed(file: "methods_draft.md", data: notes(), session: "Methods for the paper", project: "Paper draft", collection: "Paper draft",
                 version: version(8), minutesAgo: 12 * 1440, answer: "Here is the methods section, with the plate reader settings and the Z\u{2032} definition.",
                 question: "Draft the methods for the plate reader assay.", row: 12),
        ]
    }

    /// The made-up shelf in `disk`'s root: every item put there as an add
    /// does it, and one kept with data and code, as Keep does.
    static func seed(_ disk: KeptDisk) async {
        for item in seeds() {
            let keptAt = Date().addingTimeInterval(-item.minutesAgo * 60)
            let answered = Date().addingTimeInterval(-item.minutesAgo * 60 - 150)
            guard let destination = try? await disk.prepare(collection: item.collection, name: (item.file as NSString).deletingPathExtension, at: keptAt) else { continue }
            try? await disk.write(item.data, to: item.file, in: destination)
            let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000d8", projectID: "demo-\(item.project)", projectName: item.project,
                                        title: item.session, state: .finished, updatedAt: keptAt)
            let figure = KeptFile(path: item.file, role: .figure, artifact: artifact, version: item.version, index: 3, of: nil,
                                  sha256: disk.sha256(of: item.data), bytes: item.data.count)
            let written = ShelfRules.readme(session: session, folderName: destination.name, figure: figure,
                                            answer: .init(text: item.answer, at: answered, isLast: false), row: item.row,
                                            question: item.question, keptAt: keptAt, claudeScience: "0.1.70", capsid: "1.0")
            _ = try? await disk.finish(destination, readme: KeptReadme.render(written.record, text: written.text))
        }
        await seedKept(disk)
    }

    /// Fig 2B, kept with its data and code and a legend.
    private static func seedKept(_ disk: KeptDisk) async {
        let keptAt = Date().addingTimeInterval(-2 * 1440 * 60 - 3_600)
        let name = "Fig 2B \u{00B7} Z\u{2032} by plate"
        guard let destination = try? await disk.prepare(collection: "Paper draft", name: name, at: keptAt) else { return }
        let figure = chart(variant: 3)
        let data = csv()
        try? await disk.write(figure, to: "z_prime.png", in: destination)
        try? await disk.write(data, to: "data/z_prime_by_plate.csv", in: destination)
        try? await disk.write(Data(script.utf8), to: "code/z_prime.py", in: destination)
        let record = KeptRecord(
            name: destination.name, keptAt: keptAt, projectID: "demo-Paper draft", projectName: "Paper draft",
            sessionID: session.id, sessionTitle: "Plate reader QC",
            figure: KeptFile(path: "z_prime.png", role: .figure, artifact: artifact, version: versions[2].v, index: 3, of: 4,
                             sha256: disk.sha256(of: figure), bytes: figure.count),
            files: [KeptFile(path: "data/z_prime_by_plate.csv", role: .data, artifact: "dddddddd-0000-4000-8000-000000000001",
                             version: dataVersion, index: nil, of: nil, sha256: disk.sha256(of: data), bytes: data.count),
                    KeptFile(path: "code/z_prime.py", role: .code, artifact: nil, version: versions[2].v, index: nil, of: nil,
                             sha256: nil, bytes: script.utf8.count)],
            missing: [], claudeScience: "0.1.70", capsid: "1.0", sourceRow: 41,
            question: "Plot Z\u{2032} by plate, and show me where plate 7 goes wrong.", answerAt: at(50))
        let text = KeptText(legend: "Z\u{2032} factor for each of 12 plates; plate 7 was excluded for an edge effect in column 12.",
                            claudeSaid: answer,
                            attribution: "From Claude\u{2019}s answer at \(KeepRules.longTime(at(50))) on \(KeepRules.longDate(at(50))).",
                            origin: "[Plate reader QC](bench://session?project=demo-assay&frame=\(session.id)), in Paper draft.\nVersion 3 of 4 of z_prime.png, kept on \(KeepRules.longDate(keptAt)) at \(KeepRules.longTime(keptAt)) by Capsid 1.0, from Claude Science 0.1.70. The link opens the session in Capsid on a Mac that has it.")
        _ = try? await disk.finish(destination, readme: KeptReadme.render(record, text: text))
    }

    // MARK: Pictures

    /// A small bar chart, drawn here: twelve plates, one low (the seventh)
    /// in clay, as the mock-ups have it. Variants differ in the low bar.
    static func chart(variant: Int) -> Data {
        let size = NSSize(width: 480, height: 320)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let heights: [CGFloat] = [0.78, 0.84, 0.81, 0.86, 0.8, 0.79, 0.3, 0.83, 0.77, 0.85, 0.82, 0.8]
        let barWidth: CGFloat = 24, gap: CGFloat = 12, left: CGFloat = 48, bottom: CGFloat = 40
        for (index, height) in heights.enumerated() {
            let x = left + CGFloat(index) * (barWidth + gap)
            var h = height
            if index == 6 { h = [0.3, 0.3, 0.3, 0.0][min(variant, 3)] }
            if index == 6, variant == 3 { continue }
            let rect = NSRect(x: x, y: bottom, width: barWidth, height: h * 240)
            (index == 6 ? NSColor(Theme.clay) : NSColor(white: variant == 0 ? 0.65 : 0.12, alpha: 1)).setFill()
            rect.fill()
        }
        NSColor(white: 0.12, alpha: 1).setStroke()
        let axis = NSBezierPath()
        axis.move(to: NSPoint(x: left - 8, y: bottom))
        axis.line(to: NSPoint(x: size.width - 24, y: bottom))
        axis.lineWidth = 1.5
        axis.stroke()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }

    static func csv() -> Data {
        var lines = ["plate,z_prime"]
        for plate in 1...12 { lines.append("\(plate),\(plate == 7 ? "0.31" : String(format: "%.2f", 0.76 + Double(plate % 5) * 0.02))") }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// A plate-shaped heatmap: eight rows by twelve columns, slate with a
    /// few clay wells, as the mock-up draws one. Variants move the clay.
    static func heatmap(variant: Int) -> Data {
        let size = NSSize(width: 480, height: 320)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let rows = 8, columns = 12
        let cell = NSSize(width: 30, height: 28)
        let origin = NSPoint(x: (size.width - CGFloat(columns) * cell.width) / 2 - 4, y: 36)
        for row in 0..<rows {
            for column in 0..<columns {
                let low = variant == 0 ? column == 11 && row % 2 == 0 : (row * 5 + column * 3) % 17 == 0
                let shade = CGFloat((row * 3 + column * 7) % 5) * 0.025
                let color = low ? NSColor(Theme.clay) : NSColor(srgbRed: 0.18 + shade, green: 0.23 + shade, blue: 0.31 + shade, alpha: 1)
                color.setFill()
                NSRect(x: origin.x + CGFloat(column) * cell.width + 1, y: origin.y + CGFloat(rows - 1 - row) * cell.height + 1,
                       width: cell.width - 2, height: cell.height - 2).fill()
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }

    static func notes() -> Data {
        Data("""
        # Plate reader QC, 21 October

        Eleven plates pass with Z\u{2032} between 0.62 and 0.78. Plate 7 fails because of an edge effect in column 12.

        Repeat plate 7 with a fresh seal.
        """.utf8)
    }

    /// A small spreadsheet, made here: a stored zip of the five parts a
    /// workbook needs, with the cells' text inline.
    static func xlsx() -> Data {
        let rows = [["Receptor", "LIR motif", "Compartment"], ["FAM134B", "yes", "ER"], ["SEC62", "yes", "ER"], ["RTN3", "yes", "ER"],
                    ["CCPG1", "yes", "ER"], ["TEX264", "yes", "ER"], ["ATL3", "no", "ER"]]
        func cell(_ text: String, _ row: Int, _ column: Int) -> String {
            "<c r=\"\(["A", "B", "C"][column])\(row + 1)\" t=\"inlineStr\"><is><t>\(text)</t></is></c>"
        }
        let sheet = rows.enumerated().map { row, cells in
            "<row r=\"\(row + 1)\">" + cells.enumerated().map { cell($1, row, $0) }.joined() + "</row>"
        }.joined()
        let parts: [(String, String)] = [
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Receptors" sheetId="1" r:id="rId1"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
            """),
            ("xl/worksheets/sheet1.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(sheet)</sheetData></worksheet>
            """),
        ]
        return StoredZip.archive(parts.map { ($0.0, Data($0.1.utf8)) })
    }
}

/// A zip with nothing compressed: enough for a made-up workbook.
enum StoredZip {
    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }

    static func archive(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data(), central = Data()
        func put(_ data: inout Data, _ values: [UInt64], widths: [Int]) {
            for (value, width) in zip(values, widths) {
                for byte in 0..<width { data.append(UInt8((value >> (8 * UInt64(byte))) & 0xFF)) }
            }
        }
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = UInt64(crc32(entry.data))
            let size = UInt64(entry.data.count)
            let offset = UInt64(out.count)
            // Local header: signature, version, flags, method, time, date, crc, sizes, name and extra lengths.
            put(&out, [0x0403_4B50, 20, 0, 0, 0, 33, crc, size, size, UInt64(name.count), 0], widths: [4, 2, 2, 2, 2, 2, 4, 4, 4, 2, 2])
            out.append(name)
            out.append(entry.data)
            // Central directory entry: the same, then the comment, the disks, the attributes and where the header is.
            put(&central, [0x0201_4B50, 20, 20, 0, 0, 0, 33, crc, size, size, UInt64(name.count), 0, 0, 0, 0, 0, offset],
                widths: [4, 2, 2, 2, 2, 2, 2, 4, 4, 4, 2, 2, 2, 2, 2, 4, 4])
            central.append(name)
        }
        let start = UInt64(out.count)
        out.append(central)
        put(&out, [0x0605_4B50, 0, 0, UInt64(entries.count), UInt64(entries.count), UInt64(central.count), start, 0],
            widths: [4, 2, 2, 2, 2, 4, 4, 2])
        return out
    }
}
