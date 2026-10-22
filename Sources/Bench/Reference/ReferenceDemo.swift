// ReferenceDemo.swift — `--demo reference` (DESIGN.md, Reference): the
// reference window on a made-up session, its pages and thumbnails answered
// from here. Nothing is read from Claude Science; Open in Claude Science and
// Copy with Source do their ordinary things (the latter on the real
// pasteboard). `--step failed` opens it on reads that fail.
import AppKit
import Foundation

@MainActor
enum ReferenceDemo {
    static let session = SessionStatus(
        id: "00000000-0000-4000-8000-0000000000e1", projectID: "demo-assay", projectName: "Assay development",
        title: "Plate reader QC", state: .finished, updatedAt: Date().addingTimeInterval(-50 * 60),
        startedAt: Date().addingTimeInterval(-70 * 60))

    static let figure = "aaaaaaaa-0000-4000-8000-000000000004"

    /// The history: 31 rows, three of them Claude's answers. The newest is
    /// cut on its page and whole on a turn read; the middle one shows a figure.
    static let rows: [HistoryItem] = {
        var items: [HistoryItem] = []
        func at(_ minutesAgo: Double) -> Date { Date().addingTimeInterval(-minutesAgo * 60) }
        items.append(.turn(i: 0, role: .you, at: at(69), text: "Run the plate reader QC on last night\u{2019}s run.", cut: false, files: []))
        for i in 1...9 { items.append(.steps(i: i, line: "Ran a command", failed: false, files: [])) }
        items.append(.turn(i: 10, role: .claude, at: at(64), text: first, cut: false, files: []))
        items.append(.turn(i: 11, role: .you, at: at(63), text: "Plot Z\u{2032} by plate.", cut: false, files: []))
        for i in 12...19 { items.append(.steps(i: i, line: "Ran a command", failed: false, files: [])) }
        items.append(.turn(i: 20, role: .claude, at: at(58), text: second, cut: false,
                           files: [HistoryFile(v: figure, a: "bbbbbbbb-0000-4000-8000-000000000001", name: "z_prime.png",
                                               kind: .image, size: 85_000)]))
        items.append(.turn(i: 21, role: .you, at: at(55), text: "Write up what you found.", cut: false, files: []))
        for i in 22...29 { items.append(.steps(i: i, line: "Ran a command", failed: false, files: [])) }
        items.append(.turn(i: 30, role: .claude, at: at(50), text: String(third.prefix(2_000)), cut: true, files: []))
        return items
    }()

    static let first = """
    I ran the QC over all twelve plates. **Eleven passed.** Plate 7 has an edge effect in column 12: \
    the signal falls by about 40% in the outer wells, which is the usual sign of evaporation.

    - Z\u{2032} is above 0.6 on every plate but plate 7 (0.41).
    - The DMSO controls are within 5% of each other across plates.
    - No plate shows a drift along the rows.

    I\u{2019}d leave plate 7 out of the cleaned table unless you want it kept with a flag.
    """

    static let second = """
    Here is Z\u{2032} by plate. Plate 7 is the low bar; the dashed line is the 0.5 cutoff.

    ```python
    plates = plates[plates.plate != 7]
    plates.plot.bar(x="plate", y="z_prime", legend=False)
    ```

    The figure is saved as `z_prime.png`.
    """

    static let third: String = {
        let opening = """
        ## Plate reader QC, 21 October

        ### What was run
        Twelve 384-well plates from the overnight run, read on the Envision at 09:12. Each plate carries \
        16 DMSO wells and 16 positive controls in the outer columns.

        ### What I found
        1. Eleven plates pass with Z\u{2032} between 0.62 and 0.78.
        2. Plate 7 fails (Z\u{2032} 0.41) because of an edge effect in column 12.
        3. The positive controls are tight: CV under 4% on every plate.

        ### What I\u{2019}d do next
        Repeat plate 7 with a fresh seal and keep the plate in the humidified incubator between reads. \
        The other eleven can go to the hit-picking step as they are.

        | Plate | Z\u{2032} | Pass |
        |---|---|---|
        | 1 | 0.71 | yes |
        | 7 | 0.41 | no |


        """
        let filler = (1...30).map { n in
            "Well-level detail \(n): the raw signal, background and the normalised value for each of the 384 wells " +
            "were checked against the plate map, and none was out of place."
        }.joined(separator: "\n\n")
        return opening + filler
    }()

    static func show(step: String, quiet: Bool) {
        let failing = step == "failed"
        ReferenceWindowController.shared.show(session, dependencies: dependencies(failing: failing))
    }

    /// Made-up reads: a page is the `ReferenceModel.rows` rows before `before`
    /// (the last 12 when nil), after a short pause, as the page would give them.
    static func dependencies(failing: Bool = false, delay: Duration = .milliseconds(300)) -> ReferenceDependencies {
        var live = ReferenceDependencies.live()
        live.readPage = { _, before in
            try await Task.sleep(for: delay)
            if failing { return .unreadable }
            let end = before ?? rows.count
            let start = max(0, end - (before == nil ? 12 : ReferenceModel.rows))
            return .page(HistoryPage(total: rows.count, from: start, items: Array(rows[start..<end])))
        }
        live.readTurn = { _, index in
            try await Task.sleep(for: delay)
            guard !failing, index == 30 else { return nil }
            return HistoryTurn(i: 30, role: .claude, at: Date().addingTimeInterval(-50 * 60), text: third)
        }
        live.thumbnail = { version in
            try? await Task.sleep(for: delay)
            return version == figure ? KeptDemo.chart(variant: 1) : nil
        }
        return live
    }
}
