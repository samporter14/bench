// ShelfFreshnessCheckTests.swift: the asking half of the out-of-date marks (Kept/ShelfFreshnessCheck.swift): each
// artifact read once a window session however often its cards come into view, at most three reads at a time, Check
// reading again, a closed window letting everything go (and a late answer dropped), a withdrawn read not taken for an
// answer, and the demo's made-up lists giving the marks the demo shows. Made-up reads only; nothing is asked of
// Claude Science.
import Foundation
import Testing
@testable import Bench

@MainActor
struct ShelfFreshnessCheckTests {
    /// Reads that wait to be let go, counted.
    @MainActor final class Reads {
        var asked: [String] = []
        var inFlight = 0
        var most = 0
        var waiting: [CheckedContinuation<Void, Never>] = []
        var answer: (String) -> ShelfTransferResult = { _ in .answered(.versions([])) }

        func read(_ artifact: String) async -> ShelfTransferResult {
            asked.append(artifact)
            inFlight += 1
            most = max(most, inFlight)
            await withCheckedContinuation { waiting.append($0) }
            inFlight -= 1
            return answer(artifact)
        }

        func releaseAll() {
            let all = waiting
            waiting = []
            all.forEach { $0.resume() }
        }
    }

    private func settle(_ check: ShelfFreshnessCheck, _ reads: Reads) async {
        for _ in 0..<200 {
            reads.releaseAll()
            if !check.isChecking { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    private func items() async -> (items: [ShelfItem], root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("freshness-\(UUID().uuidString)", isDirectory: true)
        let disk = KeptDisk(root: { root })
        await KeptDemo.seed(disk)
        let index = KeptIndex(disk: disk, root: { root })
        await index.refreshAndWait()
        return (ShelfRules.items(from: index.results), root)
    }

    @Test func eachArtifactIsReadOnceAWindowSessionAtMostThreeAtATime() async {
        let (items, root) = await items()
        defer { try? FileManager.default.removeItem(at: root) }
        let reads = Reads()
        let check = ShelfFreshnessCheck(read: { await reads.read($0) })
        let artifacts = Set(items.flatMap { ShelfFreshnessRules.artifacts(of: $0.record) })
        #expect(artifacts.count > 3)
        check.check(items)
        // Cards scrolled past again while the reads are out: nothing more is asked.
        check.check(items)
        await Task.yield()
        #expect(reads.inFlight <= 3)
        await settle(check, reads)
        check.check(items)
        check.check(Array(items.prefix(2)))
        await settle(check, reads)
        #expect(reads.asked.count == artifacts.count, "each once")
        #expect(Set(reads.asked) == artifacts)
        #expect(reads.most == 3)
        // Check reads them again.
        check.checkAgain(Array(items.prefix(1)))
        await settle(check, reads)
        #expect(reads.asked.count == artifacts.count + ShelfFreshnessRules.artifacts(of: items[0].record).count)
    }

    @Test func aClosedWindowLetsEverythingGoAndALateAnswerIsDropped() async {
        let (items, root) = await items()
        defer { try? FileManager.default.removeItem(at: root) }
        let reads = Reads()
        let check = ShelfFreshnessCheck(read: { await reads.read($0) }, limit: 1)
        check.check([items[0]])
        await Task.yield()
        #expect(check.isChecking)
        check.reset()
        #expect(!check.isChecking && check.answers.isEmpty)
        reads.releaseAll()
        for _ in 0..<20 { await Task.yield() }
        #expect(check.answers.isEmpty, "the answer came for a window that has closed")
        // The next window asks again.
        check.check([items[0]])
        await settle(check, reads)
        #expect(!check.answers.isEmpty)
    }

    @Test func aWithdrawnReadIsNoAnswerAndIsAskedAgain() async {
        let (items, root) = await items()
        defer { try? FileManager.default.removeItem(at: root) }
        let reads = Reads()
        reads.answer = { _ in .cancelled }
        let check = ShelfFreshnessCheck(read: { await reads.read($0) })
        let item = items[0]
        check.check([item])
        await settle(check, reads)
        #expect(check.answers.isEmpty)
        #expect(check.verdict(for: item) == .unknown)
        let before = reads.asked.count
        reads.answer = { _ in .timedOut }
        check.check([item])
        await settle(check, reads)
        #expect(reads.asked.count > before)
        // Timed out is an answer that says nothing: no mark, and not asked again until Check.
        #expect(check.verdict(for: item) == .unknown)
        #expect(check.isSettled(item))
        let settled = reads.asked.count
        check.check([item])
        await settle(check, reads)
        #expect(reads.asked.count == settled)
    }

    @Test func theDemosListsGiveTheMarksTheDemoShows() async throws {
        let (items, root) = await items()
        defer { try? FileManager.default.removeItem(at: root) }
        let check = KeptDemo.freshness()
        check.check(items)
        for _ in 0..<300 where check.isChecking { try? await Task.sleep(for: .milliseconds(10)) }
        let kept = try #require(items.first { $0.record.keepsDataOrCode })
        guard case .stale(let stale) = check.verdict(for: kept) else {
            Issue.record("Fig 2B should be out of date")
            return
        }
        #expect(stale.newerFigure?.n == 4 && stale.keptNumber == 3)
        #expect(stale.inputs == [InputChange(name: "z_prime_by_plate.csv", kept: 3, newest: 5)])
        #expect(check.verdict(for: try #require(items.first { $0.fileName == "knockdown_blot.png" })) == .gone)
        #expect(check.verdict(for: try #require(items.first { $0.fileName == "z_prime_by_plate.png" })) == .current)
        #expect(ShelfFreshnessRules.countOutOfDate(items.map(check.verdict(for:))) == 1)
    }

    @Test func theLiveCheckNeverReadsInADemoAndNeverAsksForLineage() throws {
        let source = FindRepo.source("Kept/ShelfFreshnessCheck.swift")
        #expect(source.contains(".versions(artifact: artifact)"))
        #expect(!source.contains(".lineage("))
        #expect(source.contains("guard Demo.mode == nil else { return .notReady }"))
        // Asked as cards come into view and on Check; never on a timer.
        #expect(!source.contains("Timer") && !source.contains("every:"))
        let compat = CompatInventory.readEndpoints.filter { $0.feature == .outOfDate }
        #expect(compat.count == 1 && compat[0].isWhenUsed)
    }
}
