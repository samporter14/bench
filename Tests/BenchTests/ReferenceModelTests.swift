// ReferenceModelTests.swift — the reference reader on made-up histories
// shaped like real ones (the user asks, Claude narrates, runs steps that make
// figures, answers): which reply is shown, reading back until a reply's
// question is in, Earlier and Later, a cut turn read whole and landing on its
// own row, failures, and that closing cancels. No page, no daemon.
import AppKit
import Foundation
import Testing
@testable import Bench

/// A session's made-up history and the reads the reader makes of it. The
/// first read is the newest 50 rows, as the page's is; later ones are 25.
@MainActor
final class FakeHistory {
    var rows: [HistoryItem]
    var total: Int
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

    init(rows: [HistoryItem], total: Int? = nil) {
        self.rows = rows
        self.total = total ?? ((rows.map(\.index).max() ?? -1) + 1)
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
                let end = before ?? total
                let start = max(0, end - (before == nil ? 50 : ReferenceModel.rows))
                return .page(HistoryPage(total: total, from: start, items: rows.filter { (start..<end).contains($0.index) }))
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

    static func figure(_ n: Int, artifact: Int? = nil, kind: ArtifactKind = .image) -> HistoryFile {
        HistoryFile(v: String(format: "aaaaaaaa-0000-4000-8000-%012d", n),
                    a: String(format: "bbbbbbbb-0000-4000-8000-%012d", artifact ?? n),
                    name: kind == .image ? "figure_\(n).png" : "table_\(n).csv", kind: kind, size: 1_000)
    }

    /// `count` rows of steps, with the user's turns, Claude's turns and the
    /// steps' figures where given.
    static func history(_ count: Int, you: [Int: String], claude: [Int: String], cut: Set<Int> = [],
                        figures: [Int: [HistoryFile]] = [:]) -> [HistoryItem] {
        (0..<count).map { i in
            if let text = you[i] { return .turn(i: i, role: .you, at: nil, text: text, cut: false, files: []) }
            if let text = claude[i] {
                return .turn(i: i, role: .claude, at: Date(timeIntervalSince1970: 1_791_990_000 + Double(i) * 60),
                             text: text, cut: cut.contains(i), files: [])
            }
            return .steps(i: i, line: "Ran code", failed: false, files: figures[i] ?? [])
        }
    }

    static func make(_ rows: [HistoryItem]) -> (FakeHistory, ReferenceModel) {
        let fake = FakeHistory(rows: rows)
        let gate = ReadingGate(now: { Date() }, sleep: { _ in })
        let model = ReferenceModel(session: session, dependencies: fake.dependencies, gate: gate)
        return (fake, model)
    }

    static func settle(_ model: ReferenceModel) async {
        for _ in 0..<400 where model.phase == .reading { await Task.yield() }
    }

    @Test func openShowsTheNewestReplyWithItsQuestionFiguresAndWords() async throws {
        let chart = Self.figure(1)
        let (fake, model) = Self.make(Self.history(30, you: [0: "Run the QC.", 20: "Plot Z′ by plate."],
                                                   claude: [5: "Eleven passed.", 22: "Let me plot it.", 28: "Plate 7 is low."],
                                                   figures: [25: [chart]]))
        model.open()
        await Self.settle(model)
        #expect(fake.pageReads == [nil])
        #expect(model.reachedStart)
        #expect(model.answers.map(\.id) == [19, 29])
        let shown = try #require(model.current)
        #expect(shown.id == 29)
        #expect(shown.question == "Plot Z′ by plate.")
        #expect(shown.figures == [chart])
        #expect(shown.text == "Let me plot it.\n\nPlate 7 is low.")
        #expect(shown.complete)
        #expect(model.caption.hasSuffix(" · 2 of 2"))
        #expect(model.canGoEarlier)
        #expect(!model.canGoLater)
    }

    @Test func aLongReplyIsReadBackUntilItsQuestionIsIn() async throws {
        // The reply that began at row 30 runs to row 119: the first read (70..<120)
        // has no question, so the reader goes back 25 rows at a time.
        let (fake, model) = Self.make(Self.history(120, you: [0: "First.", 30: "Analyse the screen."],
                                                   claude: [10: "Done.", 119: "Here is the analysis."]))
        model.open()
        await Self.settle(model)
        #expect(fake.pageReads == [nil, 70, 45])
        #expect(model.current?.id == 119)
        #expect(model.current?.question == "Analyse the screen.")
        #expect(model.current?.complete == true)
        #expect(!model.reachedStart)
    }

    @Test func theLookStopsAfterEightPagesAndShowsWhatItHasThenEarlierFinishesIt() async throws {
        let (fake, model) = Self.make(Self.history(400, you: [0: "Start the run."], claude: [399: "Finished."]))
        model.open()
        await Self.settle(model)
        #expect(fake.pageReads.count == ReferenceModel.pagesPerLook)
        #expect(model.current?.id == 399)
        #expect(model.current?.question == nil)
        #expect(model.current?.complete == false)
        model.earlier()
        await Self.settle(model)
        #expect(model.reachedStart)
        #expect(model.current?.id == 399)
        #expect(model.current?.question == "Start the run.")
        #expect(model.current?.complete == true)
    }

    @Test func earlierAtTheEdgeReadsBackAndShowsTheNewestOlderReply() async throws {
        let (fake, model) = Self.make(Self.history(100, you: [0: "Q1", 40: "Q2", 80: "Q3"],
                                                   claude: [5: "A1", 45: "A2", 95: "A3"]))
        model.open()
        await Self.settle(model)
        #expect(model.current?.text == "A3")
        #expect(fake.pageReads == [nil])
        model.earlier()
        await Self.settle(model)
        #expect(fake.pageReads == [nil, 50])
        #expect(model.current?.text == "A2")
        #expect(model.current?.question == "Q2")
        model.earlier()
        await Self.settle(model)
        #expect(fake.pageReads == [nil, 50, 25])
        #expect(model.current?.text == "A1")
        #expect(model.reachedStart)
        #expect(!model.canGoEarlier)
        model.later()
        model.later()
        #expect(model.current?.text == "A3")
        #expect(!model.canGoLater)
        #expect(fake.pageReads.count == 3)
    }

    @Test func aPageLandingWhileTheUserMovedKeepsTheReplyShown() async throws {
        let (fake, model) = Self.make(Self.history(100, you: [0: "Q1", 40: "Q2", 60: "Q3", 80: "Q4"],
                                                   claude: [5: "A1", 45: "A2", 65: "A3", 95: "A4"]))
        model.open()
        await Self.settle(model)
        model.earlier()
        #expect(model.current?.text == "A3")
        fake.holding = true
        model.earlier()
        #expect(model.phase == .reading)
        for _ in 0..<50 where fake.pageReads.count < 2 { await Task.yield() }
        model.later()
        #expect(model.current?.text == "A4")
        fake.holding = false
        fake.release()
        await Self.settle(model)
        #expect(model.answers.map(\.text) == ["A2", "A3", "A4"])
        #expect(model.current?.text == "A4")
    }

    @Test func aSessionWithoutRepliesReachesItsStart() async throws {
        let (_, model) = Self.make(Self.history(6, you: [0: "Hello?"], claude: [:]))
        model.open()
        await Self.settle(model)
        #expect(model.answers.isEmpty)
        #expect(model.reachedStart)
        #expect(!model.canGoEarlier)
        #expect(model.phase == .idle)
    }

    @Test func aCutTurnIsReadWholeAndReplacedInPlace() async throws {
        let (fake, model) = Self.make(Self.history(30, you: [0: "Write it up."], claude: [28: "Cut…"], cut: [28]))
        fake.wholeTexts[28] = "The whole report"
        model.open()
        await Self.settle(model)
        for _ in 0..<200 where model.current?.text != "The whole report" { await Task.yield() }
        #expect(fake.turnReads == [28])
        #expect(model.current?.text == "The whole report")
        #expect(model.current?.cutRows.isEmpty == true)
        #expect(!model.readingRest)
    }

    @Test func aLateWholeTurnLandsOnItsOwnRowWhileAnotherReplyIsShown() async throws {
        let (fake, model) = Self.make(Self.history(40, you: [0: "Q1", 20: "Q2"], claude: [10: "B cut…", 30: "C"], cut: [10]))
        fake.wholeTexts[10] = "B whole"
        model.open()
        await Self.settle(model)
        #expect(model.current?.text == "C")
        fake.holding = true
        model.earlier()
        #expect(model.current?.text == "B cut…")
        #expect(model.readingRest)
        for _ in 0..<50 where fake.turnReads.isEmpty { await Task.yield() }
        #expect(fake.turnReads == [10])
        model.later()
        #expect(model.current?.text == "C")
        fake.holding = false
        fake.release()
        for _ in 0..<200 where model.answers.first?.text != "B whole" { await Task.yield() }
        #expect(model.current?.text == "C")
        #expect(model.answers.first?.text == "B whole")
        model.earlier()
        #expect(model.current?.text == "B whole")
        #expect(!model.readingRest)
        await Task.yield()
        #expect(fake.turnReads == [10])
    }

    @Test func aWholeReadThatFailsLeavesTheCutTextWithANote() async throws {
        let (fake, model) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Cut…"], cut: [28]))
        fake.turnsThrow = true
        model.open()
        await Self.settle(model)
        for _ in 0..<200 where !model.restMissing { await Task.yield() }
        #expect(model.restMissing)
        #expect(model.current?.text == "Cut…")
        #expect(!model.readingRest)
        // A turn the page says isn't one is the same failure.
        let (fake2, model2) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Cut…"], cut: [28]))
        model2.open()
        await Self.settle(model2)
        for _ in 0..<200 where !model2.restMissing { await Task.yield() }
        #expect(fake2.turnReads == [28])
        #expect(model2.restMissing)
    }

    @Test func anUnreadablePageFailsAndTryAgainReads() async throws {
        let (fake, model) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Newest"]))
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

    @Test func aReadThatThrowsFailsAndOneOverTheCapSaysSo() async throws {
        let (fake, model) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Newest"]))
        fake.pagesThrow = true
        model.open()
        await Self.settle(model)
        #expect(model.phase == .failed(ReferenceRules.failureSentence))
        let (fake2, model2) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Newest"]))
        fake2.pagesTooBig = true
        model2.open()
        await Self.settle(model2)
        #expect(model2.phase == .failed(ReferenceRules.tooBigSentence))
        #expect(model2.current == nil)
    }

    @Test func closingCancelsTheReadAndDropsWhatLands() async throws {
        let (fake, model) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Newest"]))
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
        #expect(model.shownID == nil)
    }

    @Test func copyWithSourceAddsTheSourceLineAndTheLink() async throws {
        let (fake, model) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Newest"]))
        model.open()
        await Self.settle(model)
        #expect(model.copy("the part I selected"))
        let copied = try #require(fake.copied.first)
        #expect(copied.hasPrefix("the part I selected\n\n\u{2014} Claude, in \u{201C}Plate reader QC\u{201D} (Assay development), "))
        #expect(copied.hasSuffix("\nbench://session?project=00000000-0000-4000-8000-0000000000aa&frame=00000000-0000-4000-8000-000000000001"))
        #expect(model.copied)
        model.openConversation()
        #expect(fake.opened == [Self.session.id])
    }

    @Test func aFigureIsReadOnceAndAFailedOneNotAgain() async throws {
        let chart = Self.figure(4), missing = Self.figure(5)
        let (fake, model) = Self.make(Self.history(30, you: [0: "Q"], claude: [28: "Newest"],
                                                   figures: [10: [chart], 12: [missing, Self.figure(6, kind: .table)]]))
        fake.thumbnails[chart.v] = KeptDemo.chart(variant: 1)
        model.open()
        await Self.settle(model)
        #expect(model.current?.figures.map(\.v) == [chart.v, missing.v])
        model.wantThumbnail(chart)
        model.wantThumbnail(chart)
        model.wantThumbnail(missing)
        for _ in 0..<400 where !model.thumbnails.contains(chart.v) || !model.thumbnailFailed(missing) {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.thumbnails.contains(chart.v))
        #expect(model.thumbnailFailed(missing))
        model.wantThumbnail(chart)
        model.wantThumbnail(missing)
        await Task.yield()
        #expect(fake.thumbnailReads == [chart.v, missing.v])
        let subject = model.keepSubject(chart)
        #expect(subject.entry.version == chart.v)
        #expect(subject.entry.name == "figure_4.png")
        #expect(subject.entry.kind == .image)
        #expect(subject.session.id == Self.session.id)
        // The answer the figure sat in goes with it.
        #expect(subject.pinned == KeepPinnedAnswer(text: "Newest", at: model.current?.at))
    }
}
