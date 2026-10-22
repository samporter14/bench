// ReferenceDemo.swift — `--demo reference` (DESIGN.md, Reference): the
// reference window on a made-up session, its pages and pictures answered from
// here. The history is shaped like a real one: Claude narrates, runs steps
// (the figures sit on the steps that made them), then answers. Nothing is
// read from Claude Science; Open Conversation and Copy with Source do their
// ordinary things (the latter on the real pasteboard). `--step figures`
// opens it on the answer with two figures, `--step failed` on reads that fail.
import AppKit
import Foundation

@MainActor
enum ReferenceDemo {
    static let session = SessionStatus(
        id: "00000000-0000-4000-8000-0000000000e1", projectID: "demo-assay", projectName: "Assay development",
        title: "Plate reader QC", state: .finished, updatedAt: Date().addingTimeInterval(-50 * 60),
        startedAt: Date().addingTimeInterval(-70 * 60))

    static let barChart = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000004", a: "bbbbbbbb-0000-4000-8000-000000000001",
                                      name: "z_prime_by_plate.png", kind: .image, size: 85_000)
    static let heatmap = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000011", a: "bbbbbbbb-0000-4000-8000-000000000002",
                                     name: "plate_7_heatmap.png", kind: .image, size: 120_000)
    /// An earlier draft of the bar chart: the reply shows only the last version.
    static let barChartDraft = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000003", a: "bbbbbbbb-0000-4000-8000-000000000001",
                                           name: "z_prime_by_plate.png", kind: .image, size: 84_000)

    /// The history: 34 rows, three replies.
    static let rows: [HistoryItem] = {
        var items: [HistoryItem] = []
        func at(_ minutesAgo: Double) -> Date { Date().addingTimeInterval(-minutesAgo * 60) }
        func steps(_ range: ClosedRange<Int>, files: [Int: [HistoryFile]] = [:]) {
            for i in range { items.append(.steps(i: i, line: "Ran code", failed: false, files: files[i] ?? [])) }
        }
        items.append(.turn(i: 0, role: .you, at: at(69), text: "Run the plate reader QC on last night\u{2019}s run.", cut: false, files: []))
        items.append(.turn(i: 1, role: .claude, at: at(68), text: "I\u{2019}ll load the twelve plates and check the controls first.",
                           cut: false, files: []))
        steps(2...8)
        items.append(.turn(i: 9, role: .claude, at: at(64), text: first, cut: false, files: []))
        items.append(.turn(i: 10, role: .you, at: at(63),
                           text: "Plot Z\u{2032} by plate, and show me where plate 7 goes wrong.", cut: false, files: []))
        steps(11...18, files: [13: [barChartDraft], 15: [barChart], 17: [heatmap]])
        items.append(.turn(i: 19, role: .claude, at: at(58), text: second, cut: false, files: []))
        items.append(.turn(i: 20, role: .you, at: at(55), text: "Write up what you found.", cut: false, files: []))
        steps(21...32)
        items.append(.turn(i: 33, role: .claude, at: at(50), text: String(third.prefix(2_000)), cut: true, files: []))
        return items
    }()

    static let first = """
    I ran the QC over all twelve plates. **Eleven passed.** Plate 7 has an edge effect in column 12: \
    the signal falls by about 40% in the outer wells, which is the usual sign of evaporation.

    - Z\u{2032} is above 0.6 on every plate but plate 7 (0.41).
    - The DMSO controls are within 5% of each other across plates.
    - No plate drifts along its rows.

    I\u{2019}d leave plate 7 out of the cleaned table unless you want it kept with a flag.
    """

    static let second = """
    Plate 7 is the low bar, at 0.41 against a cutoff of 0.5; the other eleven sit between 0.62 and 0.78. \
    The heatmap shows why: the outer wells of column 12 read about 40% low, and only there.

    That pattern is evaporation at the plate\u{2019}s edge rather than a pipetting fault, which would follow a \
    row or a tip. A fresh seal and a humidified incubator should fix it on the repeat.
    """

    static let third: String = {
        let opening = """
        ## Plate reader QC, 21 October

        ### What was run
        Twelve 384-well plates from the overnight run, each with 16 DMSO wells and 16 positive controls in the \
        outer columns.

        ### What I found
        1. Eleven plates pass with Z\u{2032} between 0.62 and 0.78.
        2. Plate 7 fails (Z\u{2032} 0.41) because of an edge effect in column 12.
        3. The positive controls are tight: CV under 4% on every plate.

        ### What I\u{2019}d do next
        Repeat plate 7 with a fresh seal. The other eleven can go to hit picking as they are.

        | Plate | Z\u{2032} | Pass |
        |---|---|---|
        | 1 | 0.71 | yes |
        | 7 | 0.41 | no |


        """
        let filler = (1...30).map { n in
            "Plate detail \(n): the raw signal, background and the normalised value for each of the 384 wells " +
            "were checked against the plate map, and none was out of place."
        }.joined(separator: "\n\n")
        return opening + filler
    }()

    /// `answer` (the newest), `figures` (the one before it, with its two
    /// figures) or `failed`.
    static func show(step: String, quiet: Bool) {
        ReferenceWindowController.shared.show(session, dependencies: dependencies(failing: step == "failed"))
        guard step == "figures" else { return }
        Task { @MainActor in
            let model = ReferenceWindowController.shared.model(for: session.id)
            for _ in 0..<50 where model?.current == nil { try? await Task.sleep(for: .milliseconds(100)) }
            model?.earlier()
        }
    }

    /// Made-up reads: a page is the `ReferenceModel.rows` rows before `before`
    /// (the newest 50 when nil, as the page's first read gives), after a short
    /// pause.
    static func dependencies(failing: Bool = false, delay: Duration = .milliseconds(300)) -> ReferenceDependencies {
        var live = ReferenceDependencies.live()
        live.readPage = { _, before in
            try await Task.sleep(for: delay)
            if failing { return .unreadable }
            let end = before ?? rows.count
            let start = max(0, end - (before == nil ? 50 : ReferenceModel.rows))
            return .page(HistoryPage(total: rows.count, from: start, items: rows.filter { (start..<end).contains($0.index) }))
        }
        live.readTurn = { _, index in
            try await Task.sleep(for: delay)
            guard !failing, index == 33 else { return nil }
            return HistoryTurn(i: 33, role: .claude, at: Date().addingTimeInterval(-50 * 60), text: third)
        }
        live.thumbnail = { version in
            try? await Task.sleep(for: delay)
            switch version {
            case barChart.v: return KeptDemo.chart(variant: 1)
            case heatmap.v: return heatmapPicture()
            default: return nil
            }
        }
        return live
    }

    /// A plate's heatmap, drawn here: 16 rows by 24 columns, column 12's outer
    /// wells low.
    static func heatmapPicture() -> Data {
        let size = NSSize(width: 720, height: 480)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let rows = 16, columns = 24
        let left: CGFloat = 48, bottom: CGFloat = 32, cell: CGFloat = 26
        for row in 0..<rows {
            for column in 0..<columns {
                var value = 0.82 + 0.06 * sin(Double(row * 7 + column * 3))
                if column == 11, row < 3 || row > 12 { value = 0.42 + 0.05 * Double(row % 3) }
                let shade = CGFloat(1 - value)
                NSColor(srgbRed: 0.12 + shade * 0.7, green: 0.2 + shade * 0.45, blue: 0.32 + shade * 0.2, alpha: 1).setFill()
                NSRect(x: left + CGFloat(column) * cell, y: bottom + CGFloat(rows - 1 - row) * cell,
                       width: cell - 2, height: cell - 2).fill()
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
