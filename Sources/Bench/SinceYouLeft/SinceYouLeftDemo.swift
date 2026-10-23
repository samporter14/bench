// SinceYouLeftDemo.swift — the made-up return `--demo since-you-left` and the
// snapshot tests show (board 2): three sessions finished, one stopped, one
// asking which normalization to use, with a made-up plan limit. Nothing is
// read from Claude Science, no answer sent from here goes anywhere, and no
// session, project or word is anyone's.
import AppKit
import SwiftUI

@MainActor
enum SinceYouLeftDemo {
    static let ask = "00000000-0000-4000-8000-0000000000a1"
    static let plate = "00000000-0000-4000-8000-0000000000b1"
    static let literature = "00000000-0000-4000-8000-0000000000b2"
    static let blot = "00000000-0000-4000-8000-0000000000b3"
    static let rebuild = "00000000-0000-4000-8000-0000000000c1"

    /// The stretch: 2 hours 14 minutes, ending at `now`.
    static let away: TimeInterval = (2 * 60 + 14) * 60

    /// The made-up sessions, as the sheet shows them.
    struct Made {
        let ask: SessionStatus
        let finished: [SessionStatus]
        let stopped: SessionStatus
        let events: [LabEvent]
        let since: Date
        let back: Date
        let baseline: PlanLimit
        let current: PlanLimit
    }

    static func made(now: Date = Date()) -> Made {
        let since = now.addingTimeInterval(-away)
        func at(_ minutes: Double) -> Date { since.addingTimeInterval(minutes * 60) }
        func session(_ id: String, _ title: String, _ project: String, _ state: SessionState, updated: Date,
                     reason: WaitingReason? = nil) -> SessionStatus {
            SessionStatus(id: id, projectID: "demo", projectName: project, title: title, state: state, updatedAt: updated,
                          startedAt: updated.addingTimeInterval(-20 * 60), waitingReason: reason)
        }
        let asking = session(ask, "Differential expression, KO vs WT", "RNA-seq pilot", .needsInput,
                             updated: now.addingTimeInterval(-41 * 60), reason: .question)
        let done = [
            session(plate, "Plate reader QC", "Assay development", .finished, updated: at(22)),
            session(literature, "Literature sweep: ER-phagy receptors", "Reading group", .finished, updated: at(57)),
            session(blot, "Western blot quantification", "Knockdown validation", .finished, updated: at(100)),
        ]
        let stopped = session(rebuild, "Figure 2 rebuild", "Manuscript figures", .error, updated: at(8))
        let events = [
            LabEvent(.failed, session: stopped, at: at(8)),
            LabEvent(.finished, session: done[0], at: at(22)),
            LabEvent(.finished, session: done[1], at: at(57)),
            LabEvent(.finished, session: done[2], at: at(100)),
            LabEvent(.needsInput(.question), session: asking, at: asking.updatedAt),
        ]
        let resets = now.addingTimeInterval(68 * 60)
        return Made(ask: asking, finished: done, stopped: stopped, events: events, since: since, back: now,
                    baseline: PlanLimit(kind: .session, usedPercent: 0, resetsAt: resets),
                    current: PlanLimit(kind: .session, usedPercent: 38, resetsAt: resets))
    }

    /// Sets the model, its lab, the replier and the finished files up with the
    /// made-up return. `radio` picks the first choice, as the board draws it.
    static func fill(model: SinceYouLeftModel, replier: QuestionReplier, now: Date = Date(), radio: Bool = false) {
        let made = made(now: now)
        model.lab.showDemo(working: [], cards: [.needsInput(made.ask)])
        replier.showDemo(sessionID: made.ask.id, ask: QuestionAsk(toolID: "demo-since", items: [
            .init(question: "Two samples have under 5 million reads. Which normalization should I use before testing?",
                  header: "Normalization", multi: false,
                  options: [.init(label: "DESeq2 median of ratios", detail: nil), .init(label: "TMM (edgeR)", detail: nil),
                            .init(label: "Drop the two samples", detail: nil)]),
        ]))
        if radio {
            replier.beginReply(made.ask.id)
            replier.updateDraft(made.ask.id) { $0.pick(0, in: 0, multi: false) }
        }
        model.finished.showDemo(files(for: plate), for: plate, pictures: pictures(of: plate, ["plate-bars", "plate-grid"]))
        model.finished.showDemo(files(for: literature), for: literature, pictures: [:])
        model.finished.showDemo(files(for: blot), for: blot, pictures: pictures(of: blot, ["blot-bands"]))
        model.showDemo(since: made.since, back: made.back, events: made.events, baseline: made.baseline, details: [
            plate: .init(answer: "All plates passed except plate 7, which has an edge effect in column 12. It\u{2019}s flagged and left out of the cleaned table."),
            literature: .init(answer: "A reading list ranked by relevance, and a table of every receptor with the evidence behind it and where it was reported."),
            blot: .init(answer: "Bands normalized to the loading control for all three replicates. The figure and the per-lane table are saved."),
            rebuild: .init(reason: "The R kernel ran out of memory while loading the full count matrix."),
        ])
    }

    // MARK: Files

    private static func files(for id: String) -> [ArtifactEntry] {
        func entry(_ key: String, _ name: String, _ mime: String) -> ArtifactEntry {
            ArtifactEntry(version: "\(id)-\(key)", artifact: nil, name: name, mime: mime, size: 24_000, at: nil)
        }
        switch id {
        case plate:
            return [entry("plate-bars", "z_prime.png", "image/png"), entry("plate-grid", "plate_map.png", "image/png"),
                    entry("table", "plates_cleaned.csv", "text/csv")]
        case literature:
            return [entry("list", "reading_list.md", "text/markdown"),
                    entry("table", "receptors.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")]
        default:
            return [entry("blot-bands", "blot.png", "image/png"), entry("table", "lane_table.csv", "text/csv")]
        }
    }

    /// The pictures of a session's images, by version id: its own, once each.
    private static func pictures(of id: String, _ keys: [String]) -> [String: CGImage] {
        var made: [String: CGImage] = [:]
        for key in keys {
            let view: AnyView = key.hasSuffix("grid") ? AnyView(GridPicture()) : key.hasSuffix("bands") ? AnyView(BandsPicture()) : AnyView(BarsPicture())
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.cgImage { made["\(id)-\(key)"] = image }
        }
        return made
    }

    /// Four bars, the last low, in clay: the board's first picture.
    private struct BarsPicture: View {
        var body: some View {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach([(34.0, false), (28.0, false), (38.0, false), (13.0, true)], id: \.0) { bar in
                    Rectangle().fill(bar.1 ? Theme.clay : Color(red: 0.08, green: 0.08, blue: 0.075)).frame(width: 11, height: bar.0)
                }
            }
            .padding(.bottom, 9)
            .frame(width: 120, height: 75, alignment: .bottom)
            .background(Color.white)
        }
    }

    /// A grid of pale cells with two in clay: the board's second picture.
    private struct GridPicture: View {
        var body: some View {
            VStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { column in
                            Rectangle().fill(column == 5 ? Theme.clay : Color(red: 0.95, green: 0.86, blue: 0.82)).frame(width: 14, height: 26)
                        }
                    }
                }
            }
            .frame(width: 120, height: 75)
            .background(Color.white)
        }
    }

    /// Three bands on slate: a blot, the board's third picture.
    private struct BandsPicture: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                Capsule().fill(Color(red: 0.69, green: 0.68, blue: 0.65)).frame(width: 90, height: 6)
                Capsule().fill(Color(red: 0.69, green: 0.68, blue: 0.65)).frame(width: 54, height: 6)
                Capsule().fill(Color(red: 0.37, green: 0.36, blue: 0.35)).frame(width: 90, height: 6)
            }
            .frame(width: 120, height: 75)
            .background(Color(red: 0.08, green: 0.08, blue: 0.075))
        }
    }

    // MARK: The demo

    /// Held so the windows stay up.
    private static var windows: [NSWindow] = []

    /// `--demo since-you-left`: the sheet in a plain window on a made-up
    /// return. `--step card` shows the panel's card instead.
    static func show(quiet: Bool) {
        PlanUsageModel.shared.showDemo(limits: [made().current])
        let model = SinceYouLeftModel(lab: .shared, finished: FinishedResults(dependencies: .init(read: { _ in .unreadable }, isReady: { false })),
                                      dependencies: Self.demoDependencies(model: nil))
        fill(model: model, replier: .shared, radio: true)
        let view = SinceYouLeftSheet(model: model, done: { model.done() }, dismiss: {})
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Since you left"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        windows.append(window)
        if quiet { window.orderFrontRegardless() } else { NSApp.activate(); window.makeKeyAndOrderFront(nil) }
    }

    /// Dependencies that read, open and show nothing.
    static func demoDependencies(model: SinceYouLeftModel?) -> SinceYouLeftDependencies {
        var deps = SinceYouLeftDependencies()
        deps.canRead = { false }
        deps.showSheet = {}
        deps.closeSheet = {}
        deps.readAnswer = { _ in nil }
        deps.readReason = { _ in nil }
        deps.knownReason = { _ in nil }
        deps.refreshUsage = {}
        deps.usage = { made().current }
        return deps
    }
}
