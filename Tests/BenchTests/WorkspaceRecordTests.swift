// WorkspaceRecordTests.swift — what a workspace's file is: a record of this
// shape, a damaged file or a newer Capsid's (both left alone), the file's name
// for a project id (never a way out of the folder, never one file for two ids),
// the note's limit, and how a list tells two projects of one name apart. Also
// the live disk on a temporary folder: whole writes, 0600 files, the Trash
// through an injected trasher. Made-up names and ids only.
import Foundation
import Testing
@testable import Bench

struct WorkspaceRecordTests {
    private static let at = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(_ projectID: String = "proj-alpha", note: String = "Repeat plate 7.", pins: Int = 1) -> WorkspaceRecord {
        WorkspaceRecord(projectID: projectID, projectName: "Assay development", note: note,
                        pins: (0..<pins).map { WorkspacePin(sessionID: madeUpID($0 + 1), projectID: projectID, row: 19 + $0,
                                                             title: "Plate reader QC \($0)", pinnedAt: Self.at) },
                        updatedAt: Self.at)
    }

    // MARK: Files

    @Test func aRecordGoesToDiskAndComesBackTheSame() throws {
        let made = record()
        let data = try WorkspaceRules.encode(made)
        #expect(WorkspaceRules.decode(data, projectID: "proj-alpha") == .record(made))
        // Ids, rows, titles and the note: nothing else is in it.
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == ["note", "pins", "projectID", "projectName", "schema", "updatedAt"])
    }

    @Test func aFileNameIsTheIdInHexAndComesBack() throws {
        let name = try #require(WorkspaceRules.fileName(for: "proj-alpha"))
        #expect(name == "project-70726f6a2d616c706861.json")
        #expect(WorkspaceRules.projectID(fromFileName: name) == "proj-alpha")
        // Two ids that differ only in case are two files, on a disk that doesn't tell case apart too.
        #expect(WorkspaceRules.fileName(for: "Proj") != WorkspaceRules.fileName(for: "proj"))
        #expect(WorkspaceRules.fileName(for: "Proj")?.lowercased() != WorkspaceRules.fileName(for: "proj")?.lowercased())
    }

    @Test(arguments: ["", "../x", "a/b", "a b", ".", "..", String(repeating: "a", count: 65), "é"])
    func anIdOutOfShapeHasNoFile(id: String) {
        #expect(WorkspaceRules.fileName(for: id) == nil)
    }

    @Test(arguments: ["notes.json", "project-.json", "project-7.json", "project-zz.json", "project-2e2e2f.json", ".project-70.json"])
    func otherFilesInTheFolderAreNoProjects(name: String) {
        #expect(WorkspaceRules.projectID(fromFileName: name) == nil)
    }

    // MARK: Damaged and newer files

    @Test(arguments: ["", "{", "[]", "not json", #"{"schema": 1}"#, #"{"schema": "one"}"#])
    func bytesThatAreNoRecordAreDamaged(text: String) {
        #expect(WorkspaceRules.decode(Data(text.utf8), projectID: "proj-alpha") == .damaged)
    }

    @Test func aNewerSchemaIsNewerWhateverElseItHolds() {
        let text = #"{"schema": 2, "projectID": "proj-alpha", "somethingNew": [1, 2, 3]}"#
        #expect(WorkspaceRules.decode(Data(text.utf8), projectID: "proj-alpha") == .newer(2))
    }

    @Test func aRecordNotWhollyInShapeIsDamagedNotMended() throws {
        // Another project's record under this project's name.
        #expect(WorkspaceRules.decode(try WorkspaceRules.encode(record("proj-beta")), projectID: "proj-alpha") == .damaged)
        // Five pins.
        #expect(WorkspaceRules.decode(try WorkspaceRules.encode(record(pins: 5)), projectID: "proj-alpha") == .damaged)
        // A note over the limit.
        let long = record(note: String(repeating: "a", count: WorkspaceRules.noteLimit + 1))
        #expect(WorkspaceRules.decode(try WorkspaceRules.encode(long), projectID: "proj-alpha") == .damaged)
        // A session id that isn't one, and a pin of another project.
        var bad = record()
        bad.pins = [WorkspacePin(sessionID: "../x", projectID: "proj-alpha", row: 1, title: "x", pinnedAt: Self.at)]
        #expect(WorkspaceRules.decode(try WorkspaceRules.encode(bad), projectID: "proj-alpha") == .damaged)
        bad.pins = [WorkspacePin(sessionID: madeUpID(1), projectID: "proj-beta", row: 1, title: "x", pinnedAt: Self.at)]
        #expect(WorkspaceRules.decode(try WorkspaceRules.encode(bad), projectID: "proj-alpha") == .damaged)
    }

    // MARK: The note

    @Test func theNoteLimitIsSixtyFourKibibytesOfUTF8() {
        #expect(WorkspaceRules.fits(note: String(repeating: "a", count: 65_536)))
        #expect(!WorkspaceRules.fits(note: String(repeating: "a", count: 65_537)))
        // Bytes, not characters: "é" is two.
        #expect(!WorkspaceRules.fits(note: String(repeating: "é", count: 32_769)))
        #expect(WorkspaceRules.sizeLine(for: String(repeating: "a", count: 1_000)) == nil)
        #expect(WorkspaceRules.sizeLine(for: String(repeating: "a", count: 52 * 1_024)) == "52 KB of 64 KB")
        #expect(WorkspaceRules.sizeLine(for: String(repeating: "a", count: 65_536)) == "64 KB of 64 KB")
    }

    // MARK: Lists

    @Test func twoProjectsOfOneNameAreToldApartInAList() {
        let titles = WorkspaceRules.listTitles([("proj-alpha-c0ffee", "Assay development"), ("proj-beta-decade", "Assay development"),
                                                ("proj-gamma", "Plate reader QC")])
        #expect(titles == ["Assay development \u{00B7} \u{2026}c0ffee", "Assay development \u{00B7} \u{2026}decade", "Plate reader QC"])
        // Ids that end alike are named whole.
        let alike = WorkspaceRules.listTitles([("one-same12", "Assay development"), ("two-same12", "Assay development")])
        #expect(alike == ["Assay development \u{00B7} one-same12", "Assay development \u{00B7} two-same12"])
        #expect(Set(alike).count == 2)
    }

    // MARK: The live disk, on a temporary folder

    @Test func theLiveDiskWritesWholeFilesOnlyThisUserCanReadAndTrashesThem() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-workspaces-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-workspaces-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: trash) }
        let disk = WorkspaceFiles(folder: folder, trasher: { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        })
        #expect(await disk.read("proj-alpha") == .missing)
        let data = try WorkspaceRules.encode(record())
        try await disk.write(data, for: "proj-alpha")
        #expect(await disk.read("proj-alpha") == .bytes(data))
        let file = folder.appendingPathComponent(try #require(WorkspaceRules.fileName(for: "proj-alpha")))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        let folderPermissions = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber
        #expect(folderPermissions?.intValue == 0o700)
        // No temporary file is left beside it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [file.lastPathComponent])
        #expect(await disk.projects() == ["proj-alpha"])
        await #expect(throws: WorkspaceDiskError.badID) { try await disk.write(data, for: "../escape") }
        try await disk.trash("proj-alpha")
        #expect(await disk.read("proj-alpha") == .missing)
        #expect(try Data(contentsOf: trash.appendingPathComponent(file.lastPathComponent)) == data)
        // Nothing there to trash is no error.
        try await disk.trash("proj-alpha")
    }
}
