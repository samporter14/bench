// WorkspaceShelfTests.swift — the Shelf shown on a project by Return to
// Project goes by the project's id: two projects of one name keep their
// figures in one collection folder, and only the returned project's show. The
// pill still names the collection, and choosing a project there by name lets
// the id go. Made-up kept folders in a temporary root.
import Foundation
import Testing
@testable import Bench

@MainActor
struct WorkspaceShelfTests {
    /// A seeded shelf plus one figure for each of two projects called "Assay development", in that one collection.
    private func shelf(_ body: @MainActor (ShelfModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-workspace-shelf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        let source = try #require(index.results.first { $0.collection == "Assay development" })
        for (project, file) in [("proj-alpha", "alpha_plate.png"), ("proj-beta", "beta_plate.png")] {
            var record = source.record
            record.name = (file as NSString).deletingPathExtension
            record.figure.path = file
            record.figure.version = UUID().uuidString.lowercased()
            record.projectID = project
            record.projectName = "Assay development"
            let folder = root.appendingPathComponent("Assay development").appendingPathComponent(record.name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try KeptDemo.chart(variant: 1).write(to: folder.appendingPathComponent(file))
            try Data(KeptReadme.render(record, text: source.text).utf8).write(to: folder.appendingPathComponent("README.md"))
        }
        await index.refreshAndWait()
        let model = ShelfModel(shelf: KeptDemo.shelf(index: index, root: root))
        try await body(model)
    }

    @Test func returnShowsOnlyTheProjectsOwnItemsNotAnotherOfTheSameName() async throws {
        try await shelf { model in
            // By name alone, both projects (and the demo's own) share the collection.
            model.project = "Assay development"
            #expect(Set(model.shown.map(\.record.projectID)).isSuperset(of: ["proj-alpha", "proj-beta"]))
            model.search = "plate"
            model.show(projectID: "proj-alpha")
            #expect(model.project == "Assay development" && model.projectID == "proj-alpha")
            #expect(model.search.isEmpty && model.kind == nil)
            #expect(model.shown.map(\.fileName) == ["alpha_plate.png"])
            #expect(model.shown.allSatisfy { $0.record.projectID == "proj-alpha" })
            model.show(projectID: "proj-beta")
            #expect(model.shown.map(\.fileName) == ["beta_plate.png"])
            #expect(model.selected?.record.projectID == "proj-beta")
        }
    }

    @Test func choosingAProjectByNameLetsTheIdGo() async throws {
        try await shelf { model in
            model.show(projectID: "proj-alpha")
            model.project = "Assay development"
            #expect(model.projectID == nil)
            #expect(model.shown.contains { $0.record.projectID == "proj-beta" })
            model.show(projectID: "proj-alpha")
            model.project = nil
            #expect(model.projectID == nil)
        }
    }

    @Test func aProjectWithNothingOnTheShelfChangesNothing() async throws {
        try await shelf { model in
            model.project = "Assay development"
            let before = model.shown.map(\.id)
            model.show(projectID: "proj-gamma")
            #expect(model.projectID == nil && model.shown.map(\.id) == before)
        }
    }
}
