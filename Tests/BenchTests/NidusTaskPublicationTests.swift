// Nidus publication lifecycle and file ordering, using a fake focus/clock and
// private temporary files. Nothing observes NSApp or touches the live context.
import Combine
import Foundation
import Testing
@testable import Bench

@MainActor
private final class NidusSharingHarness {
    var selection: NidusTaskContext.Selection?
    var time = Date(timeIntervalSince1970: 1_000)
    var publications: [NidusTaskFile?] = []
    var selectionReads = 0
    var scheduled = 0
    var cancelled = 0
    var flushes = 0
    var lookups = 0
    var holdLookup = false
    var lookupGate: CheckedContinuation<(project: String, task: String)?, Never>?
    var changed: (@MainActor () -> Void)?
    var beat: (@MainActor () -> Void)?

    func select(_ task: String = "Analyze assay", frame: String = "12345678-1234-1234-1234-123456789abc") {
        selection = .init(route: .init(projectID: "lab", frameID: frame),
                          names: (project: "Protein study", task: task))
    }

    func make() -> NidusTaskContext {
        NidusTaskContext(dependencies: .init(selection: { [unowned self] in
            selectionReads += 1
            return selection
        }, lookup: { [unowned self] _ in
            lookups += 1
            if holdLookup { return await withCheckedContinuation { lookupGate = $0 } }
            return nil
        }, observe: { [unowned self] callback in
            changed = callback
            return []
        }, scheduleHeartbeat: { [unowned self] callback in
            scheduled += 1
            beat = callback
            return AnyCancellable { [weak self] in
                MainActor.assumeIsolated {
                    self?.cancelled += 1
                    self?.beat = nil
                }
            }
        }, publish: { [unowned self] in publications.append($0) },
           flush: { [unowned self] in flushes += 1 }, now: { [unowned self] in time }))
    }
}

@MainActor
struct NidusTaskPublicationTests {
    @Test func disabledSharingClearsOnceAndStartsNoHeartbeat() {
        let harness = NidusSharingHarness()
        let context = harness.make()
        context.start()
        for _ in 0..<100 { context.refresh() }
        #expect(harness.scheduled == 0)
        #expect(harness.publications.count == 1)
        #expect(harness.publications.compactMap { $0 }.isEmpty)
        #expect(harness.lookups == 0)
        context.clear()
        #expect(harness.publications.count == 1)
        #expect(harness.flushes == 1)
    }

    @Test func unchangedSnapshotsDontWriteButHeartbeatRefreshesTimestamp() throws {
        let harness = NidusSharingHarness()
        harness.select()
        let context = harness.make()
        context.start()
        for _ in 0..<100 { context.refresh() }
        #expect(harness.scheduled == 1)
        #expect(harness.publications.count == 1)
        harness.time.addTimeInterval(NidusTaskContext.heartbeatInterval)
        harness.beat?()
        let files = harness.publications.compactMap { $0 }
        #expect(files.count == 2)
        let last = try #require(files.last)
        #expect(last.updatedAt == 1_005)
        #expect(last.taskName == "Analyze assay")
        #expect(last.version == 1)
        context.clear()
    }

    @Test func losingFocusStopsHeartbeatAndClearsOnlyOnce() {
        let harness = NidusSharingHarness()
        harness.select()
        let context = harness.make()
        context.start()
        let lateBeat = harness.beat
        harness.selection = nil
        context.refresh()
        context.refresh()
        lateBeat?()
        #expect(harness.cancelled == 1)
        #expect(harness.beat == nil)
        #expect(harness.publications.count == 2)
        #expect(harness.publications.compactMap { $0 }.count == 1)
        harness.select()
        context.refresh()
        #expect(harness.scheduled == 2)
        #expect(harness.publications.compactMap { $0 }.count == 2)
        context.clear()
    }

    @Test func aBurstOfIdentityChangesPublishesOnlyTheSettledSelection() async {
        let harness = NidusSharingHarness()
        harness.select()
        let context = harness.make()
        context.start()
        let before = harness.selectionReads
        for name in ["First edit", "Second edit", "Final title"] {
            harness.select(name)
            harness.changed?()
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(harness.selectionReads == before + 1)
        #expect(harness.publications.compactMap { $0 }.map(\.taskName) == ["Analyze assay", "Final title"])
        context.clear()
    }

    @Test func changingRoutesPublishesEvenWhenNamesMatch() {
        let harness = NidusSharingHarness()
        harness.select()
        let context = harness.make()
        context.start()
        harness.select(frame: "12345678-1234-1234-1234-123456789def")
        context.refresh()
        #expect(harness.publications.compactMap { $0 }.count == 2)
        #expect(harness.scheduled == 1)
        context.clear()
    }

    @Test func anOlderSessionLookupCannotPublishAfterFocusIsLost() async throws {
        let harness = NidusSharingHarness()
        harness.selection = .init(route: .init(projectID: "lab", frameID: "12345678-1234-1234-1234-123456789abc"), names: nil)
        harness.holdLookup = true
        let context = harness.make()
        context.start()
        for _ in 0..<20 where harness.lookupGate == nil { await Task.yield() }
        let gate = try #require(harness.lookupGate)
        harness.selection = nil
        context.refresh()
        gate.resume(returning: (project: "Protein study", task: "Old title"))
        harness.lookupGate = nil
        for _ in 0..<20 { await Task.yield() }
        #expect(harness.publications.compactMap { $0 }.isEmpty)
        #expect(harness.cancelled == 1)
        context.clear()
    }

    @Test func aNeverStartedDemoDoesNotPublishOrClear() {
        let harness = NidusSharingHarness()
        harness.select()
        let context = harness.make()
        context.refresh()
        context.clear()
        #expect(harness.publications.isEmpty)
        #expect(harness.scheduled == 0)
        #expect(harness.flushes == 0)
    }
}

struct NidusTaskWriterTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("capsid-nidus-\(UUID().uuidString)")
            .appendingPathComponent("nidus-context.json")
    }

    private func context(_ title: String = "Made-up task") -> NidusTaskFile {
        NidusTaskFile(version: 1, pid: 123, updatedAt: 1_000, projectName: "Made-up project", taskName: title)
    }

    @Test func publishesAtomicallyWithPrivatePermissionsAndClears() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = NidusTaskWriter(file: file)
        writer.publish(context())
        await writer.settled()
        #expect(try JSONDecoder().decode(NidusTaskFile.self, from: Data(contentsOf: file)) == context())
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700)
        writer.publish(nil)
        await writer.settled()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).isEmpty)
    }

    @Test func aPreparedWriteSupersededByClearNeverCommits() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = DispatchQueue(label: "capsid.nidus-test")
        let prepared = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        // The hook holds the commit until the test says so. Its time limits are
        // only a backstop for a broken test: under load (agents building beside
        // the suite) the test body reached `publish(nil)` after a 5 s limit, the
        // hook had let the commit through, and the test failed though the writer
        // was right. Every path below signals `resume`.
        let writer = NidusTaskWriter(file: file, queue: queue, beforeCommit: {
            prepared.signal()
            _ = resume.wait(timeout: .now() + 120)
        })
        writer.publish(context())
        let ready = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: prepared.wait(timeout: .now() + 60) == .success)
            }
        }
        #expect(ready)
        guard ready else { resume.signal(); await writer.settled(); return }
        // Inspect after the prepared write ends but before the queued clear.
        // Generation invalidation must suppress the rename itself.
        let existedBeforeRemoval = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: FileManager.default.fileExists(atPath: file.path)) }
            writer.publish(nil)
            resume.signal()
        }
        #expect(!existedBeforeRemoval)
        await writer.settled()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFailedCurrentPublicationRemovesThePreviousCopy() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writer = NidusTaskWriter(file: file)
        writer.publish(context())
        await writer.settled()
        try #require(FileManager.default.fileExists(atPath: file.path))
        writer.publish(context(String(repeating: "x", count: 9_000)))
        await writer.settled()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
