// QuickStartDemo.swift — `Capsid --demo quick-start` (App/Demo.swift): the
// Quick Start panel on made-up projects, recipes and a made-up file, for a
// screenshot that shows nothing from anyone's research. Start does nothing but
// show its sent state; no session is started, no message sent, nothing read
// from Claude Science or the disk, nothing written to settings.
import AppKit
import Foundation

@MainActor
enum QuickStartDemo {
    static let projects: [QuickStartProject] = [
        QuickStartProject(id: "proj_demo_assay", name: "Assay development"),
        QuickStartProject(id: "proj_demo_rnaseq", name: "RNA-seq pilot"),
        QuickStartProject(id: "proj_demo_screen", name: "Screen analysis"),
        QuickStartProject(id: "proj_demo_reading", name: "Reading group"),
        QuickStartProject(id: "proj_demo_cloning", name: "Cloning"),
    ]

    static let recipes: [Recipe] = [
        Recipe(id: "demo-recipe-1", name: "QC a plate-reader export", project: "proj_demo_assay",
               text: "QC this plate-reader export, flag edge effects", planFirst: true),
        Recipe(id: "demo-recipe-2", name: "Summarize a new paper for journal club", project: "proj_demo_reading",
               text: "Summarize this paper for journal club: the question, the method, what it shows and what it doesn't.",
               planFirst: false),
        Recipe(id: "demo-recipe-3", name: "Re-run the last analysis on these files", project: nil,
               text: "Re-run the last analysis on these files and tell me what changed.", planFirst: true),
    ]

    /// The one made-up file on the panel.
    static let file = QuickStartFile(url: URL(fileURLWithPath: "/tmp/capsid-demo/plate_reader_2026-10-22.xlsx"),
                                     name: "plate_reader_2026-10-22.xlsx", size: 2_400_000,
                                     contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

    /// The session in view, for ⇧↩.
    static let viewed = ViewedSession(id: "00000000-0000-4000-8000-000000000001", title: "Plate reader QC",
                                      projectID: "proj_demo_assay", projectName: "Assay development")

    /// Made-up everything: what is sent is ignored, and the answer is "started".
    static func dependencies(linger: Duration = .seconds(3600), close: @escaping @MainActor () -> Void)
        -> QuickStartModel.Dependencies {
        QuickStartModel.Dependencies(
            recipes: { recipes },
            recentProjects: { Array(projects.prefix(4)) },
            allProjects: { projects },
            viewed: { viewed },
            sender: DemoSender(),
            // The made-up file as it is; any other name is judged by its name alone, off the disk.
            makeFile: { url in url == file.url ? .success(file) : QuickStartFile.make(url: url, size: 1_000, isFolder: false) },
            close: close,
            linger: linger)
    }

    /// `--demo quick-start`: the panel, with the first recipe applied and the
    /// file on it.
    static func show() {
        QuickStartController.shared.show(
            files: [file.url], text: nil,
            dependencies: dependencies(close: { QuickStartController.shared.close() }))
        QuickStartController.shared.model?.applyRecipe(number: 1)
    }

    /// The model the snapshot test draws: the same state `show` leaves.
    static func model(shift: Bool = false, close: @escaping @MainActor () -> Void = {}) -> QuickStartModel {
        let model = QuickStartModel(dependencies: dependencies(close: close))
        model.open(files: [file.url])
        model.applyRecipe(number: 1)
        model.shiftHeld = shift
        return model
    }
}

/// Answers "started" after a moment, and sends nothing anywhere.
@MainActor
final class DemoSender: QuickStartSending {
    func perform(_ request: QuickStartFlow.Request) async -> QuickStartFlow.Outcome {
        try? await Task.sleep(for: .milliseconds(500))
        switch request.target {
        case .newSession:
            return .started(sessionID: "00000000-0000-4000-8000-000000000002",
                            sentence: QuickStartFlow.Sentence.started(project: request.projectName))
        case .session:
            return .sent(.sent, sentence: RemoteDecide.Sentence.sent)
        }
    }
}
