// PanelDemo.swift — the made-up sessions, insights and files the panel's
// moments are shown with (`--demo progress`, `finished`, `note`, `stack`; also
// the snapshot tests). Nothing is read from Claude Science: the insights and
// the files are set by hand, and no session, project or word is anyone's.
import AppKit
import SwiftUI

@MainActor
enum PanelDemo {
    enum Step: String, CaseIterable {
        /// One session working, with its plan's progress and, with
        /// `-showSpecimenCaption YES`, the specimen picked for its title.
        case progress
        /// A session that finished: the plate fills, two pictures, "3 files",
        /// the reviewer's line. `--one-figure` makes it one picture, which
        /// offers Keep….
        case finished
        /// A note Claude sent while it worked, over the session working.
        case note
        /// Three sessions working. `--hover` opens the panel into a row each,
        /// as the pointer over it does (a capture can't hover).
        case stack
    }

    /// Whether `--hover` opens the stack in the demo.
    static let hoversStack = CommandLine.arguments.contains("--hover")

    static let ids = (primary: "demo-1", second: "demo-2", third: "demo-3")

    static func session(_ state: SessionState, id: String = ids.primary, title: String, project: String,
                        minutes: Double, now: Date = Date()) -> SessionStatus {
        SessionStatus(id: id, projectID: "demo", projectName: project, title: title, state: state,
                      updatedAt: now, startedAt: now.addingTimeInterval(-minutes * 60))
    }

    /// Sets the made-up insights and files for `step` and says what the panel
    /// shows: the sessions working and the cards.
    static func prepare(_ step: Step, oneFigure: Bool = false, insights: PanelInsights = .shared,
                        finished: FinishedResults = .shared) -> (working: [SessionStatus], cards: [LabCard]) {
        switch step {
        case .progress:
            let working = session(.running, title: "CRISPR screen hits", project: "Screen analysis", minutes: 42 + 10.0 / 60)
            insights.showDemo(progress: [working.id: PlanProgress(step: 4, total: 6, title: "Check against published screens")])
            return ([working], [])
        case .finished:
            let done = session(.finished, title: "Plate reader QC", project: "Assay development", minutes: 21)
            insights.showDemo(reviewers: [done.id: ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 1)])
            finished.showDemo(files(oneFigure: oneFigure), for: done.id,
                              pictures: Dictionary(uniqueKeysWithValues: pictures(oneFigure: oneFigure)))
            return ([], [.finished(done)])
        case .note:
            let working = session(.running, title: "Plate layout", project: "Assay design", minutes: 12)
            let note = MidRunNote(id: "\(working.id)#4", sessionID: working.id,
                                  text: "Two wells in column 12 of the plate map are empty. I'm leaving them out of the controls and carrying on.",
                                  at: Date())
            insights.showDemo(notes: [note])
            return ([working], [.notice(MidRunNoteCards.notice(for: note, session: working))])
        case .stack:
            insights.showDemo()
            return ([session(.running, title: "Literature sweep", project: "Reading group", minutes: 4.2),
                     session(.running, id: ids.second, title: "Plate layout", project: "Assay design", minutes: 17.5),
                     session(.running, id: ids.third, title: "Buffer screen", project: "Assay development", minutes: 63)], [])
        }
    }

    /// `working`, finished (`--demo morph`): its card, with the Finished demo's files and pictures.
    static func finish(_ working: SessionStatus, insights: PanelInsights = .shared,
                       finished: FinishedResults = .shared) -> LabCard {
        let done = SessionStatus(id: working.id, projectID: working.projectID, projectName: working.projectName,
                                 title: working.title, state: .finished, updatedAt: Date(), startedAt: working.startedAt)
        insights.showDemo(reviewers: [done.id: ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 1)])
        finished.showDemo(files(oneFigure: false), for: done.id,
                          pictures: Dictionary(uniqueKeysWithValues: pictures(oneFigure: false)))
        return .finished(done)
    }

    // MARK: Files

    static func files(oneFigure: Bool) -> [ArtifactEntry] {
        func entry(_ n: Int, _ name: String, _ mime: String) -> ArtifactEntry {
            ArtifactEntry(version: "demo-file-\(n)", artifact: nil, name: name, mime: mime, size: 20_000 + n, at: nil)
        }
        if oneFigure {
            return [entry(1, "z_prime.png", "image/png"), entry(3, "plates_cleaned.csv", "text/csv"),
                    entry(4, "notes.md", "text/markdown")]
        }
        return [entry(1, "z_prime.png", "image/png"), entry(2, "plate_map.png", "image/png"),
                entry(3, "plates_cleaned.csv", "text/csv")]
    }

    static func pictures(oneFigure: Bool) -> [(String, CGImage)] {
        let bars = render(BarsPicture()), grid = render(GridPicture())
        var made: [(String, CGImage)] = []
        if let bars { made.append(("demo-file-1", bars)) }
        if !oneFigure, let grid { made.append(("demo-file-2", grid)) }
        return made
    }

    private static func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// Four bars, the last low, in clay: the board's first picture.
    private struct BarsPicture: View {
        var body: some View {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach([(34.0, false), (28.0, false), (38.0, false), (13.0, true)], id: \.0) { bar in
                    Rectangle().fill(bar.1 ? Theme.clay : Color(red: 0.08, green: 0.08, blue: 0.075))
                        .frame(width: 11, height: bar.0)
                }
            }
            .padding(.bottom, 9)
            .frame(width: 120, height: 75, alignment: .bottom)
            .background(PanelColor.ivory)
        }
    }

    /// A grid of pale cells with two in clay: the board's second picture.
    private struct GridPicture: View {
        var body: some View {
            VStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { column in
                            Rectangle()
                                .fill(column == 5 ? Theme.clay : Color(red: 0.95, green: 0.86, blue: 0.82))
                                .frame(width: 14, height: 26)
                        }
                    }
                }
            }
            .frame(width: 120, height: 75)
            .background(PanelColor.ivory)
        }
    }
}
