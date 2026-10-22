// KeptDemo.swift — `--demo kept` (DESIGN.md, Keep): the Keep sheet filled
// from made-up reads, and the Kept window on made-up folders in a temporary
// root. Nothing is read from Claude Science; nothing lands outside the
// temporary root, which is deleted when Capsid quits.
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
            Task { @MainActor in
                if step == "window" { await seed(disk) }
                KeptWindowController.shared.show(index: index)
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
        let thumbnails = ShelfThumbnails()
        for (index, version) in versions.enumerated() {
            thumbnails.receive(chart(variant: index), for: version.v)
        }
        let dependencies = KeepDependencies(
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
        return KeepModel(subject: KeepSubject(session: session, entry: entry), dependencies: dependencies)
    }

    private static func at(_ minutesAgo: Double) -> Date { Date().addingTimeInterval(-minutesAgo * 60) }

    // MARK: Made-up folders

    /// Three kept results in two collections, with the same pictures.
    static func seed(_ disk: KeptDisk) async {
        let items: [(collection: String, name: String, session: String, project: String, daysAgo: Double, variant: Int, legend: String)] = [
            ("Paper draft", "Fig 2B · Z′ by plate", "Plate reader QC", "Assay development", 0, 2,
             "Z′ factor for each of 12 plates; plate 7 was excluded for an edge effect in column 12."),
            ("Paper draft", "Fig 1C · Knockdown blot", "Western blot quantification", "Knockdown validation", 2, 1, ""),
            ("RNA-seq pilot", "Fig 3A · DE heatmap", "Differential expression, KO vs WT", "RNA-seq pilot", 1, 0, ""),
        ]
        for item in items {
            let keptAt = Date().addingTimeInterval(-item.daysAgo * 86_400 - 3_600)
            guard let destination = try? await disk.prepare(collection: item.collection, name: item.name, at: keptAt) else { continue }
            let figure = chart(variant: item.variant)
            let data = csv()
            try? await disk.write(figure, to: "z_prime.png", in: destination)
            try? await disk.write(data, to: "data/z_prime_by_plate.csv", in: destination)
            try? await disk.write(Data(script.utf8), to: "code/z_prime.py", in: destination)
            let record = KeptRecord(
                name: destination.name, keptAt: keptAt, projectID: "demo-\(item.project)", projectName: item.project,
                sessionID: session.id, sessionTitle: item.session,
                figure: KeptFile(path: "z_prime.png", role: .figure, artifact: artifact, version: versions[2].v, index: 3, of: 4,
                                 sha256: disk.sha256(of: figure), bytes: figure.count),
                files: [KeptFile(path: "data/z_prime_by_plate.csv", role: .data, artifact: "dddddddd-0000-4000-8000-000000000001",
                                 version: dataVersion, index: nil, of: nil, sha256: disk.sha256(of: data), bytes: data.count),
                        KeptFile(path: "code/z_prime.py", role: .code, artifact: nil, version: versions[2].v, index: nil, of: nil,
                                 sha256: nil, bytes: script.utf8.count)],
                missing: [], claudeScience: "0.1.70", capsid: "1.0")
            let text = KeptText(legend: item.legend, claudeSaid: answer,
                                attribution: "From Claude\u{2019}s answer at \(KeepRules.longTime(at(50))) on \(KeepRules.longDate(at(50))).",
                                origin: "[\(item.session)](bench://session?project=demo-assay&frame=\(session.id)), in \(item.project).\nVersion 3 of 4 of z_prime.png, kept on \(KeepRules.longDate(keptAt)) at \(KeepRules.longTime(keptAt)) by Capsid 1.0, from Claude Science 0.1.70. The link opens the session in Capsid on a Mac that has it.")
            _ = try? await disk.finish(destination, readme: KeptReadme.render(record, text: text))
        }
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
}
