// ShelfReferenceTests.swift — the reference window's side of the Shelf
// (Reference/): Show Where It Came From landing on the right reply (a row
// several pages back, a row inside a reply that began earlier, a version only,
// a draft a later version replaced, a row too far back), what a reply keeps of
// its pictures and files, what Add to Shelf tells the shelf, and how a file's
// pill reads. Made-up histories and a made-up shelf; no page, no daemon.
import Foundation
import Testing
@testable import Bench

@MainActor
struct ShelfReferenceTests {
    typealias Made = ReferenceModelTests

    /// `count` rows: the user asks at every multiple of `period`, and Claude
    /// answers in the last row of the period. Reply k holds rows
    /// k·period…(k+1)·period − 1, and its id is the last of them.
    static func conversation(rows count: Int, period: Int = 12, figures: [Int: [HistoryFile]] = [:]) -> [HistoryItem] {
        var you: [Int: String] = [:], claude: [Int: String] = [:]
        for start in stride(from: 0, to: count, by: period) {
            you[start] = "Question \(start / period)"
            claude[min(start + period, count) - 1] = "Answer \(start / period)"
        }
        return Made.history(count, you: you, claude: claude, figures: figures)
    }

    static func make(_ rows: [HistoryItem], shelf: MadeShelf = MadeShelf()) -> (FakeHistory, ReferenceModel, MadeShelf) {
        let fake = FakeHistory(rows: rows)
        var dependencies = fake.dependencies
        dependencies.shelf = shelf.access
        let model = ReferenceModel(session: Made.session, dependencies: dependencies,
                                   gate: ReadingGate(now: { Date() }, sleep: { _ in }))
        return (fake, model, shelf)
    }

    /// Until the landing is over (it may read dozens of pages).
    static func land(_ model: ReferenceModel) async {
        func failed() -> Bool {
            if case .failed = model.phase { return true }
            return false
        }
        for _ in 0..<40_000 where model.isLanding && !failed() { await Task.yield() }
        // And a look that isn't a landing (a plain open) reading its first page.
        for _ in 0..<5_000 where model.phase == .reading { await Task.yield() }
    }

    // MARK: Landing on a row

    @Test func aRowSeveralPagesBackLandsOnItsReplyReadingMoreThanOneLook() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 300))
        // Reply 3 holds rows 36…47.
        model.open(at: 40, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 47)
        #expect(model.current?.question == "Question 3")
        #expect(model.current?.complete == true)
        // 50 rows, then 25 at a time down to the page that holds row 40: more than one look of eight.
        #expect(fake.pageReads == [nil, 250, 225, 200, 175, 150, 125, 100, 75, 50])
        #expect(fake.pageReads.count > ReferenceModel.pagesPerLook)
        #expect(!model.isLanding)
        #expect(model.phase == .idle)
    }

    @Test func aRowInsideAReplyWhoseStartIsEarlierReadsOnUntilTheQuestionIsIn() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 300))
        // Reply 4 holds rows 48…59; the page that first holds row 55 begins at row 50.
        model.open(at: 55, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 59)
        #expect(model.current?.question == "Question 4")
        #expect(model.current?.complete == true)
        #expect(fake.pageReads.last == 50)
        #expect(model.from == 25)
    }

    @Test func aRowInTheNewestRepliesNeedsOnlyTheFirstPage() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 300))
        model.open(at: 290, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 299)
        #expect(fake.pageReads == [nil])
    }

    @Test func theLastRowOfAReplyIsInThatReply() async throws {
        let (_, model, _) = Self.make(Self.conversation(rows: 300))
        model.open(at: 47, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 47)
        // And the first row of the next reply is in the next.
        model.land(at: 48, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 59)
    }

    @Test func aRowInsideAStepsRunThatEndsAReplyIsInThatReply() async throws {
        // The page folds a run of tool calls into one item with the run's first row as its id:
        // reply 0 is rows 0…5 (its steps item is row 2), reply 1 begins at row 6.
        let rows: [HistoryItem] = [
            .turn(i: 0, role: .you, at: nil, text: "Question 0", cut: false, files: []),
            .turn(i: 1, role: .claude, at: Date(timeIntervalSince1970: 1_791_990_000), text: "Answer 0", cut: false, files: []),
            .steps(i: 2, line: "Ran code", failed: false, files: [Self.chart]),
            .turn(i: 6, role: .you, at: nil, text: "Question 1", cut: false, files: []),
            .turn(i: 7, role: .claude, at: Date(timeIntervalSince1970: 1_791_990_600), text: "Answer 1", cut: false, files: []),
        ]
        let (_, model, _) = Self.make(rows)
        // Row 4 is inside the run: reply 0, whose id is 2, not reply 1.
        model.open(at: 4, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 2)
        #expect(model.current?.rowEnd == 5)
        #expect(model.current?.question == "Question 0")
        // The first row of the next reply is the next reply's.
        model.land(at: 6, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 7)
        #expect(model.current?.rowEnd == nil)
    }

    @Test func aRowPastTheLastReplyLandsOnTheNewest() async throws {
        let (_, model, _) = Self.make(Self.conversation(rows: 300))
        model.open(at: 5_000, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 299)
    }

    @Test func aRowBeforeTheFirstReplyLandsOnTheFirst() async throws {
        let (_, model, _) = Self.make(Self.conversation(rows: 100))
        model.open(at: 0, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 11)
        #expect(model.reachedStart)
    }

    @Test func aWindowAlreadyOpenMovesToTheReplyItIsAskedFor() async throws {
        let (_, model, _) = Self.make(Self.conversation(rows: 300))
        model.open()
        await Self.land(model)
        #expect(model.current?.id == 299)
        model.land(at: 40, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 47)
        // Asked again for the one it is on, it stays and doesn't read.
        model.land(at: 41, mark: nil)
        await Self.land(model)
        #expect(model.current?.id == 47)
    }

    @Test func aLandingAskedWhileTheFirstLookReadsCarriesOnAfterIt() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 300))
        fake.holding = true
        model.open()
        for _ in 0..<50 where fake.pageReads.isEmpty { await Task.yield() }
        model.land(at: 40, mark: nil)
        fake.holding = false
        fake.release()
        await Self.land(model)
        #expect(model.current?.id == 47)
    }

    // MARK: Landing on a version

    static let chart = Made.figure(1)
    static let later = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000101", a: Made.figure(1).a, name: "figure_1.png",
                                   kind: .image, size: 2_000)
    static let other = Made.figure(2)

    @Test func aVersionAloneLandsOnTheNewestReplyThatShowsItAndScrollsToIt() async throws {
        // Figure 1 in reply 5 (row 65) and again in reply 15 (row 185); figure 2 only in reply 15.
        let rows = Self.conversation(rows: 300, figures: [65: [Self.chart], 185: [Self.later, Self.other]])
        let (_, model, _) = Self.make(rows)
        model.open(at: nil, mark: Self.chart.v)
        await Self.land(model)
        #expect(model.current?.id == 71)
        #expect(model.current?.question == "Question 5")
        #expect(model.scrollRequest?.id == Self.chart.v)
        #expect(model.marked == Self.chart.v)
        // The later version and the other figure are in the newer reply.
        model.land(at: nil, mark: Self.other.v)
        await Self.land(model)
        #expect(model.current?.id == 191)
        #expect(model.scrollRequest?.id == Self.other.v)
    }

    @Test func aDraftALaterVersionReplacedIsShownInItsPlaceWhenItIsTheOneMarked() async throws {
        // One reply made a figure and then made it again.
        let rows = Self.conversation(rows: 60, figures: [30: [Self.chart], 33: [Self.later]])
        let (_, model, _) = Self.make(rows)
        model.open(at: 30, mark: nil)
        await Self.land(model)
        let reply = try #require(model.current)
        #expect(reply.id == 35)
        #expect(reply.figures == [Self.later])
        #expect(reply.pictureVersions == [Self.chart, Self.later])
        #expect(model.figures(of: reply) == [Self.later])
        model.land(at: nil, mark: Self.chart.v)
        await Self.land(model)
        #expect(model.current?.id == 35)
        // The window shows the draft that was shelved, not the later one.
        #expect(model.figures(of: reply) == [Self.chart])
        #expect(model.scrollRequest?.id == Self.chart.v)
        // Marking the later one shows it; no mark at all, the reply as it was.
        model.land(at: nil, mark: Self.later.v)
        await Self.land(model)
        #expect(model.figures(of: reply) == [Self.later])
        model.land(at: nil, mark: nil)
        await Self.land(model)
        #expect(model.figures(of: reply) == [Self.later])
    }

    @Test func aVersionTheSessionNeverShowedLandsOnTheNewestReplyWithNoScroll() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 100))
        model.open(at: nil, mark: "aaaaaaaa-0000-4000-8000-0000000fffff")
        await Self.land(model)
        // It read to the start looking, and settled on the newest reply.
        #expect(model.reachedStart)
        #expect(fake.pageReads.last == 25)
        #expect(model.current?.id == 99)
        #expect(model.scrollRequest == nil)
        #expect(!model.isLanding)
    }

    @Test func aRowAndAVersionTogetherGoToTheRowsReplyAndScrollToTheVersion() async throws {
        let rows = Self.conversation(rows: 300, figures: [65: [Self.chart]])
        let (_, model, _) = Self.make(rows)
        model.open(at: 70, mark: Self.chart.v)
        await Self.land(model)
        #expect(model.current?.id == 71)
        #expect(model.scrollRequest?.id == Self.chart.v)
        // A row whose reply doesn't show the version scrolls to nothing.
        model.land(at: 100, mark: Self.chart.v)
        await Self.land(model)
        #expect(model.current?.id == 107)
        #expect(model.scrollRequest == nil)
    }

    // MARK: Limits and failures

    @Test func aRowFurtherBackThanOneLandingReadsStopsAndSaysSo() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 3_600))
        model.open(at: 10, mark: nil)
        await Self.land(model)
        #expect(fake.pageReads.count == ReferenceModel.landingPages)
        #expect(model.landingNote == ReferenceModel.tooFarSentence)
        #expect(!model.isLanding)
        #expect(!model.reachedStart)
        // It shows the oldest reply it read whole: the page it stopped at begins at row 1,575,
        // in the middle of reply 131, so reply 132 (rows 1,584…1,595) is the first whole one.
        #expect(model.from == 1_575)
        #expect(model.current?.complete == true)
        #expect(model.current?.id == 1_595)
        // Earlier carries on from there.
        let before = fake.pageReads.count
        model.earlier()
        await Self.land(model)
        #expect(fake.pageReads.count > before)
    }

    @Test func aFailedPageMidLandingWaitsForTryAgainThenFinishes() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 300))
        fake.pagesUnreadable = true
        model.open(at: 40, mark: nil)
        await Self.land(model)
        #expect(model.phase == .failed(ReferenceRules.failureSentence))
        #expect(model.current == nil)
        fake.pagesUnreadable = false
        model.retry()
        await Self.land(model)
        #expect(model.current?.id == 47)
        #expect(model.phase == .idle)
    }

    @Test func closingDropsALanding() async throws {
        let (fake, model, _) = Self.make(Self.conversation(rows: 300))
        fake.holding = true
        model.open(at: 40, mark: nil)
        for _ in 0..<50 where fake.pageReads.isEmpty { await Task.yield() }
        model.close()
        fake.holding = false
        fake.release()
        for _ in 0..<50 { await Task.yield() }
        #expect(!model.isLanding)
        #expect(model.current == nil)
    }

    @Test func aSessionWithNoRepliesLandsOnNothing() async throws {
        let (_, model, _) = Self.make(Made.history(6, you: [0: "Hello?"], claude: [:]))
        model.open(at: 3, mark: nil)
        await Self.land(model)
        #expect(model.current == nil)
        #expect(!model.isLanding)
        #expect(model.reachedStart)
    }

    // MARK: The window's address

    @Test func theSessionAShelvedItemNamesOpensItsConversationOnTheDaemonsPort() {
        let id = "00000000-0000-4000-8000-000000000001"
        let session = ReferenceWindowController.session(id: id, projectID: "proj_a", title: "Plate reader QC",
                                                        projectName: "Assay development", port: 8123)
        #expect(session.deepLink?.absoluteString == "http://localhost:8123/projects/proj_a/frames/\(id)")
        #expect(session.displayTitle == "Plate reader QC" && session.projectName == "Assay development")
        #expect(ReferenceWindowController.session(id: id, projectID: "proj_a", title: "t", projectName: "p", port: nil)
            .deepLink?.port == 8765)
        // Ids a README made by hand could hold are never put in an address.
        for (project, frame) in [("proj_a/../x", id), ("proj_a", "not-a-frame"), ("", id), ("proj a", id)] {
            #expect(ReferenceWindowController.session(id: frame, projectID: project, title: "t", projectName: "p", port: 8123)
                .deepLink == nil, "\(project) \(frame)")
        }
    }

    // MARK: What a reply keeps

    @Test func filesOfOtherKindsAreKeptBesideTheFigures() {
        let notes = Made.figure(7, kind: .markdown)
        let table = Made.figure(8, kind: .table)
        let rows = Self.conversation(rows: 24, figures: [5: [Self.chart, notes], 6: [table]])
        let answers = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:])
        let first = answers[0]
        #expect(first.figures == [Self.chart])
        #expect(first.files == [notes, table])
        #expect(first.pictureVersions == [Self.chart])
        #expect(first.file(version: notes.v) == notes)
        #expect(first.shows(version: table.v) && first.shows(version: Self.chart.v))
        #expect(!first.shows(version: Self.other.v))
        // The next reply has none.
        #expect(answers[1].files.isEmpty && answers[1].figures.isEmpty)
    }

    @Test func aFileMadeAgainKeepsItsLastVersionInItsPlace() {
        let first = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000201", a: "bbbbbbbb-0000-4000-8000-000000000201",
                                name: "notes.md", kind: .markdown, size: 100)
        let second = HistoryFile(v: "aaaaaaaa-0000-4000-8000-000000000202", a: "bbbbbbbb-0000-4000-8000-000000000201",
                                 name: "notes.md", kind: .markdown, size: 120)
        let rows = Self.conversation(rows: 12, figures: [3: [first], 6: [Made.figure(8, kind: .table), second]])
        let reply = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:])[0]
        #expect(reply.files.map(\.v) == [second.v, Made.figure(8, kind: .table).v])
    }

    @Test func aReplyOfOnlyFilesIsStillNoReply() {
        let rows = Made.history(6, you: [0: "Write it."], claude: [:], figures: [3: [Made.figure(7, kind: .markdown)]])
        #expect(ReferenceRules.answers(items: rows, reachedStart: true, whole: [:]).isEmpty)
    }

    @Test func aReplyRemembersEveryDraftOfAFigureUpToALimit() {
        let drafts = (0..<(ReferenceRules.versionLimit + 10)).map { n in
            HistoryFile(v: String(format: "aaaaaaaa-0000-4000-8000-%012d", 1_000 + n), a: Made.figure(1).a,
                        name: "figure_1.png", kind: .image, size: 10)
        }
        let rows = Made.history(5, you: [0: "Draw."], claude: [4: "Done."], figures: [2: drafts])
        let reply = ReferenceRules.answers(items: rows, reachedStart: true, whole: [:])[0]
        #expect(reply.figures == [drafts.last!])
        #expect(reply.pictureVersions.count == ReferenceRules.versionLimit)
        #expect(reply.pictureVersions.first == drafts.first)
    }

    // MARK: Add to Shelf from the window

    private func landed(figures: [Int: [HistoryFile]], shelf: MadeShelf = MadeShelf()) async -> (ReferenceModel, MadeShelf) {
        let (_, model, shelf) = Self.make(Self.conversation(rows: 24, figures: figures), shelf: shelf)
        model.open()
        await Self.land(model)
        return (model, shelf)
    }

    @Test func theShelfIsToldTheFileThisRepliesWordsItsRowAndTheQuestion() async throws {
        let (model, _) = await landed(figures: [14: [Self.chart]])
        let source = model.shelfSource(Self.chart)
        #expect(source.session == Made.session)
        #expect(source.entry.version == Self.chart.v && source.entry.name == "figure_1.png" && source.entry.artifact == Self.chart.a)
        #expect(source.row == 23)
        #expect(source.question == "Question 1")
        #expect(source.answer?.text == "Answer 1")
        #expect(source.answer?.at == model.current?.at)
    }

    @Test func aFileFromAnEarlierReplyIsToldItsOwnReply() async throws {
        let (model, _) = await landed(figures: [4: [Self.other], 14: [Self.chart]])
        // The newest reply is on the page; the file is from the one before it.
        let source = model.shelfSource(Self.other)
        #expect(source.row == 11)
        #expect(source.question == "Question 0")
        #expect(source.answer?.text == "Answer 0")
    }

    @Test func addToShelfPutsItOnAndTheMarkFollows() async throws {
        let (model, shelf) = await landed(figures: [14: [Self.chart]])
        #expect(model.shelfMark(Self.chart) == .off)
        let outcome = await model.addToShelf(Self.chart)
        #expect(outcome == .added(MadeShelf.placement("figure_1.png")))
        #expect(shelf.added.count == 1 && shelf.added[0].entry.version == Self.chart.v)
        #expect(model.shelfMark(Self.chart) == .on)
        #expect(model.shelfProblems.isEmpty)
        // "On Shelf ✓" shows the shelf on the item it put there.
        model.showOnShelf(Self.chart)
        #expect(shelf.shown == [MadeShelf.placement("figure_1.png").folder])
        // Another figure it didn't put there: the window alone.
        model.showOnShelf(Self.other)
        #expect(shelf.shown.last! == nil)
    }

    @Test func aFileAlreadyOnTheShelfIsOnItWithNothingAdded() async throws {
        let shelf = MadeShelf()
        shelf.onShelf = [Self.chart.v]
        let (model, _) = await landed(figures: [14: [Self.chart]], shelf: shelf)
        #expect(model.shelfMark(Self.chart) == .on)
        #expect(await model.addToShelf(Self.chart) == nil)
        #expect(shelf.added.isEmpty)
    }

    @Test func aFailureIsASentenceUnderTheFileUntilTheNextTry() async throws {
        let (model, shelf) = await landed(figures: [14: [Self.chart]])
        shelf.outcome = .failed("Claude Science isn\u{2019}t answering.")
        _ = await model.addToShelf(Self.chart)
        #expect(model.shelfProblems[Self.chart.v] == "Claude Science isn\u{2019}t answering.")
        #expect(model.shelfMark(Self.chart) == .off)
        shelf.outcome = nil
        _ = await model.addToShelf(Self.chart)
        #expect(model.shelfProblems.isEmpty)
        #expect(model.shelfMark(Self.chart) == .on)
    }

    @Test func aSecondAskWhileTheFirstRunsDoesNothingAndTheMarkSaysAdding() async throws {
        let (model, shelf) = await landed(figures: [14: [Self.chart]])
        shelf.holding = true
        let first = Task { await model.addToShelf(Self.chart) }
        for _ in 0..<50 where shelf.added.isEmpty { await Task.yield() }
        #expect(model.shelfMark(Self.chart) == .adding)
        #expect(await model.addToShelf(Self.chart) == nil)
        shelf.release()
        _ = await first.value
        #expect(shelf.added.count == 1)
        #expect(model.shelfMark(Self.chart) == .on)
    }

    @Test func anAddAnotherWindowStartedShowsAsAdding() async throws {
        let shelf = MadeShelf()
        shelf.adding = [Self.chart.v]
        let (model, _) = await landed(figures: [14: [Self.chart]], shelf: shelf)
        #expect(model.shelfMark(Self.chart) == .adding)
        #expect(await model.addToShelf(Self.chart) == nil)
        #expect(shelf.added.isEmpty)
    }

    @Test func keepWithDataAndCodeIsPinnedToTheFilesOwnReply() async throws {
        let (model, _) = await landed(figures: [4: [Self.other], 14: [Self.chart]])
        let subject = model.keepSubject(Self.other)
        #expect(subject.entry.version == Self.other.v)
        #expect(subject.pinned?.text == "Answer 0")
    }
}
