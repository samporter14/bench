// ShelfTemporaryCopiesTests.swift — the temporary copies Quick Look and drag use,
// and the names the shelf writes: where a copy goes, how a name is made safe, the
// permissions, the cache by version, and deleting a run's folder or all of them.
// Each test works in a folder of its own under the temporary folder, removed after.
import Foundation
import Testing
@testable import Bench

private func made(_ name: String, version: String = "v-1") -> ArtifactEntry {
    ArtifactEntry(version: version, artifact: nil, name: name, mime: nil, size: 3, at: nil)
}

private func permissions(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

struct ShelfFileNameTests {
    @Test func aNameIsMadeSafeToWrite() {
        #expect(ShelfFileName.sanitized("report.md") == "report.md")
        #expect(ShelfFileName.sanitized("my report (final).md") == "my report (final).md")
        #expect(ShelfFileName.sanitized("../../etc/passwd") == "_.._etc_passwd", "no separators, no leading dot")
        #expect(ShelfFileName.sanitized("a/b\\c.txt") == "a_b\\c.txt")
        #expect(ShelfFileName.sanitized("a:b.txt") == "a_b.txt")
        #expect(ShelfFileName.sanitized(".hidden.txt") == "hidden.txt")
        #expect(ShelfFileName.sanitized("..") == "file")
        #expect(ShelfFileName.sanitized("...  ") == "file")
        #expect(ShelfFileName.sanitized("") == "file")
        #expect(ShelfFileName.sanitized("   ") == "file")
        #expect(ShelfFileName.sanitized("  spaced .md ") == "spaced .md")
        #expect(ShelfFileName.sanitized("a\u{0}b\u{7}c\nd.txt") == "a_b_c_d.txt", "control characters never reach a file name")
        #expect(ShelfFileName.sanitized("/") == "_")
        #expect(ShelfFileName.sanitized("héllo wörld.csv") == "héllo wörld.csv")
    }

    @Test func aLongNameKeepsItsExtensionWithin255Bytes() {
        let long = ShelfFileName.sanitized(String(repeating: "é", count: 300) + ".png")
        #expect(long.utf8.count <= ShelfFileName.longest && long.hasSuffix(".png") && long.hasPrefix("é"))
        let plain = ShelfFileName.sanitized(String(repeating: "x", count: 400) + ".csv")
        #expect(plain.utf8.count == ShelfFileName.longest && plain.hasSuffix(".csv"))
        let noExtension = ShelfFileName.sanitized(String(repeating: "y", count: 400))
        #expect(noExtension.utf8.count == ShelfFileName.longest)
        let absurd = ShelfFileName.sanitized("a." + String(repeating: "z", count: 300))
        #expect(absurd.utf8.count <= ShelfFileName.longest && !absurd.isEmpty)
        #expect(ShelfFileName.sanitized(String(repeating: "x", count: 255)).utf8.count == 255, "255 bytes is allowed")
    }

    @Test func aVersionIDMakesOnlyOneSafeFolderName() {
        #expect(ShelfTemporaryCopies.folderComponent(for: "v_abc-123") == "v_abc-123")
        #expect(ShelfTemporaryCopies.folderComponent(for: "../../x") == "______x")
        #expect(ShelfTemporaryCopies.folderComponent(for: "") == "_")
        #expect(ShelfTemporaryCopies.folderComponent(for: String(repeating: "a", count: 200)).count == 128)
    }
}

@MainActor
final class ShelfTemporaryCopiesTests {
    private let scratch = FileManager.default.temporaryDirectory
        .appending(path: "capsid-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var base: URL { scratch.appending(path: ShelfTemporaryCopies.folderName, directoryHint: .isDirectory) }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
    }

    @Test func aCopyGoesIntoThisRunsFolderUnderTheVersionID() {
        let copies = ShelfTemporaryCopies(base: base)
        let url = copies.url(for: made("report.md", version: "v-md"))
        #expect(url.path == copies.runFolder.path + "/v-md/report.md")
        #expect(copies.runFolder.deletingLastPathComponent().path == base.path)
        #expect(UUID(uuidString: copies.runFolder.lastPathComponent) != nil)
        #expect(!FileManager.default.fileExists(atPath: base.path), "working out a path makes nothing")
        #expect(copies.cached("v-md") == nil)
        // Another run has another folder.
        #expect(ShelfTemporaryCopies(base: base).runFolder != copies.runFolder)
    }

    @Test func foldersAreOwnerOnlyAndFilesAreReadWriteForTheOwnerOnly() throws {
        let copies = ShelfTemporaryCopies(base: base)
        let url = try copies.write(Data("made-up".utf8), for: made("report.md", version: "v-md"))
        #expect(try Data(contentsOf: url) == Data("made-up".utf8))
        #expect(permissions(url) == 0o600)
        #expect([url.deletingLastPathComponent(), copies.runFolder, base].map(permissions) == [0o700, 0o700, 0o700])
    }

    @Test func aCopyIsCachedByVersionUntilItsFileGoes() throws {
        let copies = ShelfTemporaryCopies(base: base)
        let url = try copies.write(Data("a".utf8), for: made("a.md", version: "v-a"))
        #expect(copies.cached("v-a") == url)
        #expect(copies.cached("v-other") == nil)
        try FileManager.default.removeItem(at: url)
        #expect(copies.cached("v-a") == nil, "a file the system cleaned away is made again, not trusted")
        // Written again over the same place.
        let again = try copies.write(Data("b".utf8), for: made("a.md", version: "v-a"))
        #expect(again == url && copies.cached("v-a") == url)
        #expect(try Data(contentsOf: again) == Data("b".utf8))
    }

    @Test func twoVersionsOfOneNameDontShareAFile() throws {
        let copies = ShelfTemporaryCopies(base: base)
        let first = try copies.write(Data("1".utf8), for: made("figure.png", version: "v-1"))
        let second = try copies.write(Data("2".utf8), for: made("figure.png", version: "v-2"))
        #expect(first != second && first.lastPathComponent == second.lastPathComponent)
        #expect(try Data(contentsOf: first) == Data("1".utf8) && Data(contentsOf: second) == Data("2".utf8))
    }

    @Test func aHostileNameOrVersionStaysInsideTheRunFolder() throws {
        let copies = ShelfTemporaryCopies(base: base)
        let url = try copies.write(Data("x".utf8), for: made("../../../escape.md", version: "../../v"))
        #expect(url.path.hasPrefix(copies.runFolder.path + "/"))
        #expect(url.standardizedFileURL.path.hasPrefix(copies.runFolder.standardizedFileURL.path + "/"))
        #expect(!FileManager.default.fileExists(atPath: scratch.appending(path: "escape.md").path))
    }

    @Test func removingAllDeletesTheRunAndTheNextCopyGoesToANewOne() throws {
        let copies = ShelfTemporaryCopies(base: base)
        let first = try copies.write(Data("x".utf8), for: made("a.md", version: "v-a"))
        let run = copies.runFolder
        copies.removeAll()
        #expect(!FileManager.default.fileExists(atPath: run.path))
        #expect(copies.cached("v-a") == nil)
        copies.removeAll() // nothing there: no trouble
        let second = try copies.write(Data("y".utf8), for: made("a.md", version: "v-a"))
        #expect(second != first && copies.runFolder != run)
    }

    @Test func removingTheBaseTakesEveryRunsFolder() throws {
        let one = ShelfTemporaryCopies(base: base)
        let two = ShelfTemporaryCopies(base: base)
        try one.write(Data("1".utf8), for: made("a.md"))
        try two.write(Data("2".utf8), for: made("b.md"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).count == 2)
        ShelfTemporaryCopies.removeAll(base: base)
        #expect(!FileManager.default.fileExists(atPath: base.path))
        ShelfTemporaryCopies.removeAll(base: base) // already gone: no trouble
    }

    @Test func aWriteThatCantBeMadeSaysSo() throws {
        // The base is a file, so no folder can go under it.
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base)
        let copies = ShelfTemporaryCopies(base: base)
        #expect(throws: (any Error).self) { try copies.write(Data("x".utf8), for: made("a.md")) }
        #expect(copies.cached("v-1") == nil)
    }
}
