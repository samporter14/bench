// ReferenceModelTests.swift — the reference reader on made-up pages: which
// answer is shown, paging back for earlier ones, the whole-turn read of a cut
// answer landing by row (never on the answer shown meanwhile), failures, and
// that closing cancels. No page, no daemon.
import AppKit
import Foundation
import Testing
@testable import Bench

/// A session's made-up history and the reads the reader makes of it.
@MainActor
final class FakeHistory {
    var rows: [HistoryItem]
    /// The `before` of every page read, in order.
    private(set) var pageReads: [Int?] = []
    private(set) var turnReads: [Int] = []
    private(set) var thumbnailReads: [String] = []
    /// Page reads and turn reads wait here while `holding`; `release` lets them go.
    var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// A held read whose task was cancelled meanwhile.
    private(set) var sawCancellation = false
    var pagesUnreadable = false
    var pagesTooBig = false
    var pagesThrow = false
    var turnsThrow = false
    var wholeTexts: [Int: String] = [:]
    var thumbnails: [String: Data] = [:]
    private(set) var copied: [String] = []
    private(set) var opened: [String] = []

    init(rows: [HistoryItem]) {
        self.rows = rows
    }

    func release() {
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    private func pass() async throws {
        guard holding else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiters.append($0) }
        } onCancel: {
            Task { @MainActor in self.sawCancellation = true }
        }
        try Task.checkCancellation()
    }

    var dependencies: ReferenceDependencies {
        ReferenceDependencies(
            readPage: { [self] _, before in
                pageReads.append(before)
                try await pass()
                if pagesThrow { throw WebAPIError.notReady }
                if pagesUnreadable { return .unreadable }
                if pagesTooBig { return .tooBig }
                let end = before ?? rows.count
                let start = max(0, end - (before == nil ? 12 : ReferenceModel.rows))
                return .page(HistoryPage(total: rows.count, from: start, items: Array(rows[start..<end])))
            },
            readTurn: { [self] _, index in
                turnReads.append(index)
                try await pass()
                if turnsThrow { throw WebAPIError.notReady }
                guard let text = wholeTexts[index] else { return nil }
                return HistoryTurn(i: index, role: .claude, at: nil, text: text)
            },
            thumbnail: { [self] version in
                thumbnailReads.append(version)
                return thumbnails[version]
            },
            open: { [self] in opened.append($0.id) },
            pasteboard: { [self] in copied.append($0); return true },
            render: { ReferenceRules.plainText($0) },
            now: { Date(timeIntervalSince1970: 1_792_000_000) })
    }
}

@MainActor
struct ReferenceModelTests {
    static let session = SessionStatus(
        id: "00000000-0000-4000-8000-000000000001", projectID: "00000000-0000-4000-8000-0000000000aa",
        projectName: "Assay development", title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)

    static func claude(_ i: Int, _ text: String, cut: Bool = false, files: [HistoryFile] = []) -> HistoryItem {
        .turn(i: i, role: .claude, at: Date(timeIntervalSince1970: 1_791_990_000 + Double(i) * 60), text: text, cut: cut, files: files)
    }

    static func you(_ i: Int) -> HistoryItem {
        .turn(i: i, role: .you, at: nil, text: "Question \(i)", cut: false, files: [])
    }

    /// `count` rows of steps, with Claude's answers at the given rows.
    static func history(_ count: Int, answers: [Int: String], cut: Set<Int> = [], files: [Int: [HistoryFile]] = [:]) -> [HistoryItem] {
        (0..<count).map { i in
            if let text = answers[i] { return claude(i, text, cut: cut.contains(i), files: files[i] ?? []) }
            return .steps(i: i, line: "Ran a command", failed: false, files: [])
        }
    }

    static func make(_ rows: [HistoryItem]) -> (FakeHistory, ReferenceModel) {
        let fake = FakeHistory(rows: rows)
        let gate = ReadingGate(now: { Date() }, sleep: { _ in })
        let model = ReferenceModel(session: session, dependencies: fake.dependencies, gate: gate)
        return (fake, model)
    }

    static func settle(_ model: ReferenceModel) async {
        for _ in 0..<200 where model.phase == .reading { await Task.yield() }
    }

    @Test func openShowsTheNewestAnswerOnTheLastPage() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest", 5: "First"]))
        model.open()
        await Self.settle(model)
        #expect(fake.pageReads == [nil])
        #expect(model.answers.map(\.i) == [28])
        #expect(model.shown == 0)
        #expect(model.current?.text == "Newest")
        #expect(!model.reachedStart)
        #expect(model.canGoEarlier)
        #expect(!model.canGoLater)
        #expect(model.positionLine?.hasSuffix("1 of 1 so far") == true)
    }

    @Test func earlierAtTheEdgeReadsBackAndShowsThePageNewestAnswer() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest", 12: "Middle", 5: "First"]))
        model.open()
        await Self.settle(model)
        model.earlier()
        await Self.settle(model)
        #expect(fake.pageReads == [nil, 18])
        #expect(model.answers.map(\.i) == [5, 12, 28])
        #expect(model.shown == 1)
        #expect(model.current?.text == "Middle")
        #expect(model.reachedStart)
        #expect(model.positionLine?.hasSuffix("2 of 3") == true)
        model.earlier()
        #expect(model.current?.text == "First")
        #expect(!model.canGoEarlier)
        model.earlier()
        #expect(model.current?.text == "First")
        model.later()
        model.later()
        #expect(model.current?.text == "Newest")
        #expect(!model.canGoLater)
        #expect(fake.pageReads.count == 2)
    }

    @Test func pagesWithoutAnAnswerAreReadUntilOneAppears() async throws {
        // Rows 88..<100 and 63..<88 hold none; 38..<63 holds one.
        let (fake, model) = Self.make(Self.history(100, answers: [40: "Found"]))
        model.open()
        await Self.settle(model)
        #expect(fake.pageReads == [nil, 88, 63])
        #expect(model.current?.text == "Found")
        #expect(model.from == 38)
    }

    @Test func theLookStopsAfterEightPagesAndEarlierLooksAgain() async throws {
        let (fake, model) = Self.make(Self.history(400, answers: [3: "Far back"]))
        model.open()
        await Self.settle(model)
        #expect(fake.pageReads.count == ReferenceModel.pagesPerLook)
        #expect(model.answers.isEmpty)
        #expect(model.shown == nil)
        #expect(model.phase == .idle)
        #expect(!model.reachedStart)
        #expect(model.canGoEarlier)
        model.earlier()
        await Self.settle(model)
        #expect(fake.pageReads.count == 2 * ReferenceModel.pagesPerLook)
        model.earlier()
        await Self.settle(model)
        #expect(model.current?.text == "Far back")
        #expect(model.reachedStart)
    }

    @Test func aSessionWithoutAnswersReachesItsStart() async throws {
        let (_, model) = Self.make([Self.you(0), .steps(i: 1, line: "Ran a command", failed: false, files: [])])
        model.open()
        await Self.settle(model)
        #expect(model.answers.isEmpty)
        #expect(model.reachedStart)
        #expect(!model.canGoEarlier)
        #expect(model.phase == .idle)
    }

    @Test func aCutAnswerIsReadWholeAndReplacedInPlace() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Cut…"], cut: [28]))
        fake.wholeTexts[28] = "The whole answer"
        model.open()
        await Self.settle(model)
        for _ in 0..<200 where model.current?.cut == true { await Task.yield() }
        #expect(fake.turnReads == [28])
        #expect(model.current?.text == "The whole answer")
        #expect(model.current?.cut == false)
        #expect(!model.readingRest)
    }

    @Test func aLateWholeAnswerLandsOnItsOwnRowNotTheOneShown() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "C whole", 20: "B cut…"], cut: [20]))
        fake.wholeTexts[20] = "B whole"
        model.open()
        await Self.settle(model)
        #expect(model.current?.text == "C whole")
        fake.holding = true
        model.earlier()
        #expect(model.current?.text == "B cut…")
        #expect(model.readingRest)
        for _ in 0..<50 where fake.turnReads.isEmpty { await Task.yield() }
        #expect(fake.turnReads == [20])
        // Moved on while B's whole text is still being read.
        model.later()
        #expect(model.current?.text == "C whole")
        fake.holding = false
        fake.release()
        for _ in 0..<200 where model.answers[0].cut { await Task.yield() }
        #expect(model.current?.text == "C whole")
        #expect(model.answers[0].text == "B whole")
        #expect(model.answers[0].cut == false)
        // Back on B: whole, with nothing read again.
        model.earlier()
        #expect(model.current?.text == "B whole")
        #expect(!model.readingRest)
        await Task.yield()
        #expect(fake.turnReads == [20])
    }

    @Test func aWholeReadThatFailsLeavesTheCutTextWithANote() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Cut…"], cut: [28]))
        fake.turnsThrow = true
        model.open()
        await Self.settle(model)
        for _ in 0..<200 where !model.restFailed.contains(28) { await Task.yield() }
        #expect(model.restFailed.contains(28))
        #expect(model.current?.text == "Cut…")
        #expect(!model.readingRest)
        // A turn the page says isn't one is the same failure.
        let (fake2, model2) = Self.make(Self.history(30, answers: [28: "Cut…"], cut: [28]))
        model2.open()
        await Self.settle(model2)
        for _ in 0..<200 where !model2.restFailed.contains(28) { await Task.yield() }
        #expect(fake2.turnReads == [28])
        #expect(model2.restFailed.contains(28))
    }

    @Test func anUnreadablePageFailsAndTryAgainReads() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest"]))
        fake.pagesUnreadable = true
        model.open()
        await Self.settle(model)
        #expect(model.phase == .failed(ReferenceRules.failureSentence))
        #expect(model.current == nil)
        fake.pagesUnreadable = false
        model.retry()
        await Self.settle(model)
        #expect(model.phase == .idle)
        #expect(model.current?.text == "Newest")
        #expect(fake.pageReads == [nil, nil])
    }

    @Test func aReadThatThrowsFails() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest"]))
        fake.pagesThrow = true
        model.open()
        await Self.settle(model)
        #expect(model.phase == .failed(ReferenceRules.failureSentence))
    }

    @Test func aPageOverTheCapSaysSoAndPointsAtClaudeScience() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest"]))
        fake.pagesTooBig = true
        model.open()
        await Self.settle(model)
        #expect(model.phase == .failed(ReferenceRules.tooBigSentence))
        #expect(model.current == nil)
    }

    @Test func closingCancelsTheReadAndDropsWhatLands() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest"]))
        fake.holding = true
        model.open()
        for _ in 0..<50 where fake.pageReads.isEmpty { await Task.yield() }
        #expect(fake.pageReads == [nil])
        model.close()
        for _ in 0..<50 where !fake.sawCancellation { await Task.yield() }
        #expect(fake.sawCancellation)
        fake.holding = false
        fake.release()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.answers.isEmpty)
        #expect(model.shown == nil)
    }

    @Test func aPageLandingWhileTheUserMovedKeepsTheShownAnswer() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "D", 25: "C", 12: "B", 5: "A"]))
        model.open()
        await Self.settle(model)
        #expect(model.current?.text == "D")
        model.earlier()
        #expect(model.current?.text == "C")
        fake.holding = true
        model.earlier()
        #expect(model.phase == .reading)
        for _ in 0..<50 where fake.pageReads.count < 2 { await Task.yield() }
        model.later()
        #expect(model.current?.text == "D")
        fake.holding = false
        fake.release()
        await Self.settle(model)
        #expect(model.answers.map(\.text) == ["A", "B", "C", "D"])
        #expect(model.current?.text == "D")
        #expect(model.shown == 3)
        #expect(model.positionLine?.hasSuffix("4 of 4") == true)
    }

    @Test func copyWithSourceAddsTheSourceLineAndTheLink() async throws {
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest"]))
        model.open()
        await Self.settle(model)
        #expect(model.copy("the part I selected"))
        let copied = try #require(fake.copied.first)
        #expect(copied.hasPrefix("the part I selected\n\n\u{2014} Claude, in \u{201C}Plate reader QC\u{201D} (Assay development), "))
        #expect(copied.hasSuffix("\nbench://session?project=00000000-0000-4000-8000-0000000000aa&frame=00000000-0000-4000-8000-000000000001"))
        #expect(model.copied)
        model.openInScience()
        #expect(fake.opened == [Self.session.id])
    }

    @Test func aFigureThumbnailIsReadOnceAndAFailedOneNotAgain() async throws {
        let figure = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000004", a: nil, name: "z_prime.png", kind: .image, size: 85_000)
        let missing = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000005", a: nil, name: "other.png", kind: .image, size: 100)
        let table = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000006", a: nil, name: "plates.csv", kind: .table, size: 100)
        let (fake, model) = Self.make(Self.history(30, answers: [28: "Newest"], files: [28: [figure, missing, table]]))
        fake.thumbnails[figure.v] = KeptDemo.chart(variant: 1)
        model.open()
        await Self.settle(model)
        #expect(model.current?.figures.map(\.v) == [figure.v, missing.v])
        model.wantThumbnail(figure)
        model.wantThumbnail(figure)
        model.wantThumbnail(missing)
        model.wantThumbnail(table)
        for _ in 0..<400 where !model.thumbnails.contains(figure.v) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.thumbnails.contains(figure.v))
        model.wantThumbnail(figure)
        model.wantThumbnail(missing)
        await Task.yield()
        #expect(fake.thumbnailReads == [figure.v, missing.v])
        let subject = model.keepSubject(figure)
        #expect(subject.entry.name == "z_prime.png")
        #expect(subject.entry.kind == .image)
        #expect(subject.session.id == Self.session.id)
    }
}
