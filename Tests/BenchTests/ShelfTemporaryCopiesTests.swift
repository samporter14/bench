// ShelfTemporaryCopiesTests.swift — the temporary copies Quick Look and drag use,
// and the names the shelf writes: where a copy goes, how a name is made safe, the
// permissions, a run removed (and a late write for it dropped), and launch's
// cleanup of every earlier run.
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

final class ShelfTemporaryCopiesTests {
    private let scratch = FileManager.default.temporaryDirectory
        .appending(path: "capsid-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var base: URL { scratch.appending(path: ShelfTemporaryCopies.folderName, directoryHint: .isDirectory) }

    deinit {
        try? FileManager.default.removeItem(at: scratch)
    }

    @Test func aCopyGoesIntoItsRunsFolderUnderTheVersionID() async {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let url = copies.url(for: made("report.md", version: "v-md"), run: run)
        #expect(url.path == copies.runFolder(run).path + "/v-md/report.md")
        #expect(copies.runFolder(run).deletingLastPathComponent().path == base.path)
        #expect(copies.runFolder(run).lastPathComponent == run.uuidString)
        #expect(!FileManager.default.fileExists(atPath: base.path), "working out a path makes nothing")
        #expect(await !copies.exists(url))
        // Another run has another folder.
        #expect(copies.runFolder(UUID()) != copies.runFolder(run))
    }

    @Test func foldersAreOwnerOnlyAndFilesAreReadWriteForTheOwnerOnly() async throws {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let url = try #require(try await copies.write(Data("made-up".utf8), for: made("report.md", version: "v-md"), run: run))
        #expect(try Data(contentsOf: url) == Data("made-up".utf8))
        #expect(try await copies.read(url) == Data("made-up".utf8))
        #expect(permissions(url) == 0o600)
        #expect([url.deletingLastPathComponent(), copies.runFolder(run), base].map(permissions) == [0o700, 0o700, 0o700])
    }

    @Test func aCopyThatGoesIsSeenToBeGoneAndIsWrittenAgainInItsPlace() async throws {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let url = try #require(try await copies.write(Data("a".utf8), for: made("a.md", version: "v-a"), run: run))
        #expect(await copies.exists(url))
        try FileManager.default.removeItem(at: url)
        #expect(await !copies.exists(url), "a file the system cleaned away is made again, not trusted")
        await #expect(throws: (any Error).self) { try await copies.read(url) }
        // Written again over the same place.
        let again = try #require(try await copies.write(Data("b".utf8), for: made("a.md", version: "v-a"), run: run))
        #expect(again == url)
        #expect(try Data(contentsOf: again) == Data("b".utf8))
    }

    @Test func twoVersionsOfOneNameDontShareAFile() async throws {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let first = try #require(try await copies.write(Data("1".utf8), for: made("figure.png", version: "v-1"), run: run))
        let second = try #require(try await copies.write(Data("2".utf8), for: made("figure.png", version: "v-2"), run: run))
        #expect(first != second && first.lastPathComponent == second.lastPathComponent)
        #expect(try Data(contentsOf: first) == Data("1".utf8) && Data(contentsOf: second) == Data("2".utf8))
    }

    @Test func aHostileNameOrVersionStaysInsideTheRunFolder() async throws {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let url = try #require(try await copies.write(Data("x".utf8), for: made("../../../escape.md", version: "../../v"), run: run))
        #expect(url.path.hasPrefix(copies.runFolder(run).path + "/"))
        #expect(url.standardizedFileURL.path.hasPrefix(copies.runFolder(run).standardizedFileURL.path + "/"))
        #expect(!FileManager.default.fileExists(atPath: scratch.appending(path: "escape.md").path))
    }

    @Test func removingARunDeletesItAndTheNextCopyGoesToANewOne() async throws {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let first = try #require(try await copies.write(Data("x".utf8), for: made("a.md", version: "v-a"), run: run))
        await copies.remove(run: run)
        #expect(!FileManager.default.fileExists(atPath: copies.runFolder(run).path))
        #expect(await !copies.exists(first))
        await copies.remove(run: run) // nothing there: no trouble
        let next = UUID()
        let second = try #require(try await copies.write(Data("y".utf8), for: made("a.md", version: "v-a"), run: next))
        #expect(second != first && copies.runFolder(next) != copies.runFolder(run))
    }

    @Test func aWriteThatLandsAfterItsRunWasRemovedIsDroppedAndMakesNoFolder() async throws {
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        _ = try await copies.write(Data("x".utf8), for: made("a.md", version: "v-a"), run: run)
        await copies.remove(run: run)
        // The window closed while this one was on its way.
        #expect(try await copies.write(Data("late".utf8), for: made("b.md", version: "v-b"), run: run) == nil)
        #expect(!FileManager.default.fileExists(atPath: copies.runFolder(run).path), "the run's folder isn't made again")
        // A run that was never written to is removed the same way.
        let unused = UUID()
        await copies.remove(run: unused)
        #expect(try await copies.write(Data("late".utf8), for: made("c.md", version: "v-c"), run: unused) == nil)
        #expect(!FileManager.default.fileExists(atPath: copies.runFolder(unused).path))
    }

    @Test func removingTheBaseTakesEveryRunsFolder() async throws {
        let one = ShelfTemporaryCopies(base: base)
        let two = ShelfTemporaryCopies(base: base)
        _ = try await one.write(Data("1".utf8), for: made("a.md"), run: UUID())
        _ = try await two.write(Data("2".utf8), for: made("b.md"), run: UUID())
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).count == 2)
        ShelfTemporaryCopies.removeAll(base: base)
        #expect(!FileManager.default.fileExists(atPath: base.path))
        ShelfTemporaryCopies.removeAll(base: base) // already gone: no trouble
    }

    @Test func launchCleanupTakesEarlierRunsAndLeavesTheOneBeingWritten() async throws {
        // An earlier launch's run that never closed.
        let earlier = ShelfTemporaryCopies(base: base)
        _ = try await earlier.write(Data("old".utf8), for: made("old.md"), run: UUID())
        let copies = ShelfTemporaryCopies(base: base)
        let run = UUID()
        let kept = try #require(try await copies.write(Data("new".utf8), for: made("new.md", version: "v-new"), run: run))
        await copies.removeLeftovers()
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path) == [run.uuidString])
        #expect(try Data(contentsOf: kept) == Data("new".utf8))
        // With nothing of its own written, the whole folder goes.
        await copies.remove(run: run)
        await copies.removeLeftovers()
        #expect(!FileManager.default.fileExists(atPath: base.path))
        await copies.removeLeftovers() // already gone: no trouble
    }

    @Test func aWriteThatCantBeMadeSaysSo() async throws {
        // The base is a file, so no folder can go under it.
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base)
        let copies = ShelfTemporaryCopies(base: base)
        await #expect(throws: (any Error).self) { try await copies.write(Data("x".utf8), for: made("a.md"), run: UUID()) }
    }
}
