import CryptoKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct ArtifactFileIntegrationTests {
    private static let largeSize = ArtifactReaderScript.Cap.download + 17
    private static let session = SessionStatus(id: "00000000-0000-4000-8000-000000000701", projectID: "file-tests",
                                                projectName: "File transfer tests", title: "Large results",
                                                state: .finished, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

    private func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsid-file-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func spool(size: Int = Self.largeSize) async throws -> ArtifactFile {
        let writer = ArtifactFileWriter()
        let chunk = Data(repeating: 0x6B, count: ArtifactFileLimits.chunk)
        var left = size
        while left > 0 {
            let count = min(left, chunk.count)
            try await writer.append(base64: chunk.prefix(count).base64EncodedString())
            left -= count
        }
        return try await writer.finish(expected: size)
    }

    private func entry(_ version: String, size: Int = Self.largeSize) -> ArtifactEntry {
        ArtifactEntry(version: version, artifact: nil, name: "large.bin", mime: "application/octet-stream", size: size, at: nil)
    }

    private nonisolated static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let bytes = try handle.read(upToCount: ArtifactFileLimits.chunk), !bytes.isEmpty { digest.update(data: bytes) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @Test func aLargeSingleSaveUsesTheFileReadAndWritesTheWholeSpool() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = ScratchDefaults.make(prefix: "capsid-file-save")
        defer { settings.discard() }
        let file = try await spool()
        let item = entry("large-single")
        var reads: [ArtifactRead] = []
        var notices: [URL] = []
        let shelf = ResultsShelf(dependencies: .init(
            recent: { [] }, older: { _ in nil },
            read: { read in
                reads.append(read)
                return read == .fileDownload(version: item.version) ? .file(file) : .unreadable
            }, isReady: { true }, open: { _ in }, didSave: { notices.append($0) },
            temporaryFolder: folder.appendingPathComponent("previews"), defaults: settings.defaults))
        let target = folder.appendingPathComponent("saved.bin")
        #expect(await shelf.save(item, to: target, project: "file-tests") == .saved(target))
        #expect(reads == [.fileDownload(version: item.version)])
        #expect(shelf.saved[item.version] == target)
        #expect(notices == [target])
        #expect(!shelf.saving.contains(item.version))
        let digest = try await Task.detached { try Self.digest(target) }.value
        #expect(digest == file.sha256)
        #expect((try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue == Self.largeSize)
    }

    @Test func saveAllStreamsLargeFilesAndPreservesNamesAlreadyOnDisk() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = ScratchDefaults.make(prefix: "capsid-file-save-all")
        defer { settings.discard() }
        let file = try await spool()
        let entries = [entry("large-first"), entry("large-second")]
        let existing = folder.appendingPathComponent("large.bin")
        let original = Data("an existing user file".utf8)
        try original.write(to: existing)
        var downloads: [ArtifactRead] = []
        let shelf = ResultsShelf(dependencies: .init(
            recent: { [Self.session] }, older: { _ in nil },
            read: { read in
                switch read {
                case .list(let frame) where frame == Self.session.id: return .list(entries)
                case .fileDownload(let version) where entries.contains(where: { $0.version == version }):
                    downloads.append(read)
                    return .file(file)
                default: return .unreadable
                }
            }, isReady: { true }, open: { _ in },
            temporaryFolder: folder.appendingPathComponent("previews"), defaults: settings.defaults))
        shelf.open()
        await shelf.settled()
        shelf.saveAll(Self.session.id, into: folder)
        await shelf.settled()
        #expect(shelf.batches[Self.session.id] == .finished(ShelfSaveAllSummary(folder: folder, saved: 2)))
        #expect(Set(downloads) == Set(entries.map { ArtifactRead.fileDownload(version: $0.version) }))
        #expect(shelf.saved[entries[0].version]?.lastPathComponent == "large 2.bin")
        #expect(shelf.saved[entries[1].version]?.lastPathComponent == "large 3.bin")
        #expect(try Data(contentsOf: existing) == original)
        for item in entries {
            let target = try #require(shelf.saved[item.version])
            let digest = try await Task.detached { try Self.digest(target) }.value
            #expect(digest == file.sha256)
        }
    }

    @Test func keepPreservesAChecksumMismatchAndCopiesTheFileWithoutReadingItIntoMemory() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = ScratchDefaults.make(prefix: "capsid-file-keep")
        defer { settings.discard() }
        let file = try await spool()
        let disk = KeptDisk(root: { folder.appendingPathComponent("kept") })
        var reads: [ArtifactRead] = []
        var dependencies = KeepDependencies(
            read: { read in reads.append(read); return .answered(.file(file)) },
            showing: { _, _, _ in .unreadable }, lastAnswer: { _ in nil }, thumbnails: ShelfThumbnails(),
            disk: disk, defaults: settings.defaults, root: { folder }, scienceVersion: { nil }, capsidVersion: "test",
            now: { Date(timeIntervalSince1970: 1_800_000_000) }, didKeep: { _ in })
        let expected = String(repeating: "AB", count: 32)
        let item = KeepItem(role: .figure, source: .download(version: "kept-large"), artifact: nil,
                            version: "kept-large", name: "large.bin", size: file.bytes, sha: expected)
        guard case .file(let received, let mismatch) = await dependencies.fetch(item) else {
            Issue.record("Keep did not return the streamed file")
            return
        }
        #expect(reads == [.fileDownload(version: "kept-large")])
        #expect(received === file)
        #expect(mismatch == expected.lowercased())
        let destination = try await disk.prepare(collection: "Files", name: "Large result", at: Date())
        try await disk.write(received, to: "large.bin", in: destination)
        let target = destination.tempFolder.appendingPathComponent("large.bin")
        let digest = try await Task.detached { try Self.digest(target) }.value
        #expect(digest == file.sha256)
        #expect(digest != mismatch)
        await disk.abandon(destination)

        // An inaccurate small listing must try the file-backed path after
        // the in-memory reader encounters its cap; it is still keepable.
        reads = []
        dependencies.read = { read in
            reads.append(read)
            if case .download = read { return .answered(.tooBig) }
            return .answered(.file(file))
        }
        let unlistedSize = KeepItem(role: .figure, source: .download(version: "unknown-size"), artifact: nil,
                                   version: "unknown-size", name: "large.bin", size: nil, sha: file.sha256)
        guard case .file(let fallback, let unexpectedMismatch) = await dependencies.fetch(unlistedSize) else {
            Issue.record("An unknown-size file did not fall back to the streamed transfer")
            return
        }
        #expect(fallback === file && unexpectedMismatch == nil)
        #expect(reads == [.download(version: "unknown-size"), .fileDownload(version: "unknown-size")])
    }

    @Test func cancellingASingleSaveDiscardsALateFileReplyWithoutWriting() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = ScratchDefaults.make(prefix: "capsid-file-save-cancel")
        defer { settings.discard() }
        let file = try await spool(size: 32)
        let item = entry("cancelled-file")
        let gate = FileReadGate()
        let shelf = ResultsShelf(dependencies: .init(
            recent: { [] }, older: { _ in nil }, read: { _ in await gate.read() },
            isReady: { true }, open: { _ in },
            temporaryFolder: folder.appendingPathComponent("previews"), defaults: settings.defaults))
        let target = folder.appendingPathComponent("never-written.bin")
        var result: ShelfSaveOutcome?
        let task = Task { result = await shelf.save(item, to: target) }
        defer { task.cancel(); gate.release(.cancelled) }
        for _ in 0..<500 where !gate.waiting { try? await Task.sleep(for: .milliseconds(2)) }
        #expect(gate.waiting)
        task.cancel()
        for _ in 0..<500 where result == nil { try? await Task.sleep(for: .milliseconds(2)) }
        // The consumer must stop before the page returns; the queue still owns the late reader.
        #expect(result == .cancelled)
        gate.release(.file(file))
        await task.value
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(shelf.saved[item.version] == nil)
        #expect(!shelf.saving.contains(item.version))
    }
}

@MainActor
private final class FileReadGate {
    private var continuation: CheckedContinuation<ArtifactReadOutcome, Never>?
    var waiting: Bool { continuation != nil }

    func read() async -> ArtifactReadOutcome {
        await withCheckedContinuation { continuation = $0 }
    }

    func release(_ value: ArtifactReadOutcome) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: value)
    }
}
