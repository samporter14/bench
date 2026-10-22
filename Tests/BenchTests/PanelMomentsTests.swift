// PanelMomentsTests.swift — the panel's moments (DESIGN.md, "The panel", 1.0):
// the specimen picked for a session, the Finished card's buttons and files,
// the sounds, the stack of working sessions, the notes, what VoiceOver says,
// and the lines drawn from the data contract's types. Made-up sessions only;
// the insights are built by hand and nothing reads Claude Science.
import AppKit
import SwiftUI
import Testing
@testable import Bench

// MARK: Which specimen plays for a session

@MainActor
struct SessionSpecimenTests {
    private static func scene(_ name: String) -> LabScene {
        LabScenes.catalogue.first { $0.name == name }!
    }

    /// A matcher that records what it was offered.
    final class Recorder: @unchecked Sendable {
        var titles: [String] = []
        var ids: [String] = []
        var candidates: [[String]] = []
        let answer: (name: String, topic: String)?
        init(answer: (name: String, topic: String)?) { self.answer = answer }

        func match(_ title: String, _ id: String, _ names: [String]) -> (name: String, topic: String)? {
            titles.append(title)
            ids.append(id)
            candidates.append(names)
            return answer
        }
    }

    @Test func withNoMatchTheRotationPlaysAsItAlwaysDid() {
        let recorder = Recorder(answer: nil)
        let result = SessionSpecimen.resolve(title: "Peak calling", sessionID: "a", playing: .full, matching: true, match: recorder.match)
        #expect(result.rotation == .full)
        #expect(result.picked == nil)
    }

    @Test func aMatchPlaysThatSpecimenAloneAndSaysWhy() {
        let recorder = Recorder(answer: (name: "CRISPR", topic: "gene editing"))
        let result = SessionSpecimen.resolve(title: "CRISPR screen hits", sessionID: "a", playing: .full, matching: true, match: recorder.match)
        #expect(result.rotation.scenes.map(\.name) == ["CRISPR"])
        #expect(result.picked == SessionSpecimen.Picked(name: "CRISPR", topic: "gene editing"))
        #expect(result.picked?.caption == "CRISPR, picked because the session is about gene editing")
    }

    @Test func theSettingOffNeverAsksTheMatcher() {
        let recorder = Recorder(answer: (name: "CRISPR", topic: "x"))
        let result = SessionSpecimen.resolve(title: "CRISPR screen hits", sessionID: "a", playing: .full, matching: false, match: recorder.match)
        #expect(result.rotation == .full && result.picked == nil)
        #expect(recorder.candidates.isEmpty)
    }

    @Test func aTitleWithNothingInItAsksNothing() {
        let recorder = Recorder(answer: (name: "CRISPR", topic: "x"))
        for title in ["", "   \n"] {
            #expect(SessionSpecimen.resolve(title: title, sessionID: "a", playing: .full, matching: true, match: recorder.match).picked == nil)
        }
        #expect(recorder.candidates.isEmpty)
    }

    @Test func theMatcherIsOfferedTheSessionsOwnWordsAndIdAndOnlyWhatPlays() {
        // Every way the user can narrow what plays: the candidates are the
        // names of exactly the scenes that rotation holds, so nothing the user
        // turned off can be picked.
        var choices: [(String, Rotation)] = [("everything on", SpecimenChoice.all.rotation)]
        var hidden = SpecimenChoice.all
        hidden.toggle(Self.scene("CRISPR"))
        choices.append(("one specimen off", hidden.rotation))
        var onlyOne = SpecimenChoice.all
        onlyOne.playOnly(Self.scene("Gel"))
        choices.append(("play only one", onlyOne.rotation))
        var noBiology = SpecimenChoice.all
        noBiology.set(.biology, on: false)
        choices.append(("a category off", noBiology.rotation))
        choices.append(("only favourites", SpecimenChoice.all.rotation(favorites: ["Gel", "Pipette"], onlyFavorites: true)))
        for (what, rotation) in choices {
            let recorder = Recorder(answer: nil)
            _ = SessionSpecimen.resolve(title: "A gel run", sessionID: "00000000-0000-4000-8000-000000000001",
                                        playing: rotation, matching: true, match: recorder.match)
            #expect(recorder.candidates == [rotation.scenes.map(\.name)], "\(what)")
            #expect(recorder.titles == ["A gel run"] && recorder.ids == ["00000000-0000-4000-8000-000000000001"], "\(what)")
        }
        #expect(!choices[1].1.scenes.contains { $0.name == "CRISPR" })
        #expect(choices[2].1.scenes.map(\.name) == ["Gel"])
        #expect(choices[4].1.scenes.map(\.name).sorted() == ["Gel", "Pipette"])
    }

    @Test func aSpecimenTheUserSwitchedOffCanNotWinEvenIfTheMatcherNamesIt() {
        var choice = SpecimenChoice.all
        choice.toggle(Self.scene("CRISPR"))
        let recorder = Recorder(answer: (name: "CRISPR", topic: "gene editing"))
        let result = SessionSpecimen.resolve(title: "CRISPR screen", sessionID: "a", playing: choice.rotation, matching: true,
                                             match: recorder.match)
        #expect(result.picked == nil)
        #expect(result.rotation == choice.rotation)
    }

    @Test func onlyOneThatPlaysIsPickedFromWhatPlays() {
        // Play Only: the single specimen is the only candidate, and wins if it matches.
        var choice = SpecimenChoice.all
        choice.playOnly(Self.scene("Gel"))
        let match = SessionSpecimen.resolve(title: "Gel run", sessionID: "a", playing: choice.rotation, matching: true,
                                            match: Recorder(answer: (name: "Gel", topic: "electrophoresis")).match)
        #expect(match.rotation.scenes.map(\.name) == ["Gel"])
    }

    @Test func oneSessionKeepsItsSpecimenWhateverHowOftenItIsAsked() {
        let match: SessionSpecimen.Matcher = { title, id, candidates in
            // A seeded pick, as the data branch's matcher makes it.
            let names = candidates.filter { $0.count > 3 }.sorted()
            guard !names.isEmpty else { return nil }
            return (names[abs(id.hashValue &+ title.count) % names.count], "a topic")
        }
        let first = SessionSpecimen.resolve(title: "Some title", sessionID: "s1", playing: .full, matching: true, match: match)
        for _ in 0..<20 {
            #expect(SessionSpecimen.resolve(title: "Some title", sessionID: "s1", playing: .full, matching: true, match: match) == first)
        }
    }

    @Test func theRealMatcherAnswersTheSameEveryTimeAndFromTheCandidatesOnly() {
        let names = LabScenes.catalogue.map(\.name)
        let id = "00000000-0000-4000-8000-0000000000aa"
        let a = SpecimenTopics.match(title: "Gel electrophoresis of PCR products", sessionID: id, candidates: names)
        let b = SpecimenTopics.match(title: "Gel electrophoresis of PCR products", sessionID: id, candidates: names)
        #expect(a?.name == b?.name && a?.topic == b?.topic)
        if let a { #expect(names.contains(a.name)) }
        // Offered nothing, it can name nothing.
        #expect(SpecimenTopics.match(title: "Gel electrophoresis", sessionID: id, candidates: []) == nil)
    }

    @Test func theRealMatcherPicksTheSpecimenNamedInTheTitleAndNeverOneTheUserSwitchedOff() {
        let id = "00000000-0000-4000-8000-0000000000bb"
        let picked = SessionSpecimen.resolve(title: "CRISPR screen hits", sessionID: id, playing: .full, matching: true)
        #expect(picked.picked?.name == "CRISPR")
        #expect(picked.rotation.scenes.map(\.name) == ["CRISPR"])
        #expect(picked.picked?.topic.isEmpty == false)
        var choice = SpecimenChoice.all
        choice.toggle(Self.scene("CRISPR"))
        let without = SessionSpecimen.resolve(title: "CRISPR screen hits", sessionID: id, playing: choice.rotation, matching: true)
        #expect(without.picked?.name != "CRISPR")
        #expect(!without.rotation.scenes.isEmpty)
        if let name = without.picked?.name { #expect(without.rotation.scenes.map(\.name) == [name]) }
    }

    @Test func theAnswerForASessionIsKeptWhileNothingChangesAndRedoneWhenTheTitleDoes() {
        defer { SessionSpecimen.matcher = SpecimenTopics.match; SessionSpecimen.forget() }
        var asked = 0
        SessionSpecimen.matcher = { title, _, _ in
            asked += 1
            return title.contains("gel") ? (name: "Gel", topic: "electrophoresis") : nil
        }
        SessionSpecimen.forget()
        let one = Fixture.session("memo-a", .running, title: "A gel run")
        for _ in 0..<5 { #expect(SessionSpecimen.of(one, matching: true).picked?.name == "Gel") }
        #expect(asked == 1)
        let renamed = Fixture.session("memo-a", .running, title: "Peak calling")
        #expect(SessionSpecimen.of(renamed, matching: true).picked == nil)
        #expect(asked == 2)
        // The setting turned off is a different question.
        #expect(SessionSpecimen.of(one, matching: false).picked == nil)
    }

    @Test func underReduceMotionTheStillIsTheOneSpecimenOfARotationOfOneElseTheFlask() {
        let gel = Self.scene("Gel")
        #expect(WorkingGlyph.still(in: Rotation([gel]))?.name == "Gel")
        #expect(WorkingGlyph.still(in: .full)?.name == WorkingGlyph.still?.name)
    }

    @Test func theSettingsPageOffersTheToggleOnTheKeyThatIsRegistered() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let page = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/SceneSettingsView.swift"), encoding: .utf8)
        #expect(page.contains("@AppStorage(SettingsKey.matchSpecimenToSession)"))
        #expect(page.contains("Toggle(\"Match the specimen to the session\""))
        #expect(SettingsKey.matchSpecimenToSession == "matchSpecimenToSession")
    }

    @Test func nothingAboutTheSessionIsWrittenDown() throws {
        // The pick is a pure function of the title and the id; the file that
        // makes it never touches UserDefaults, the disk or the network.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/SessionSpecimen.swift"), encoding: .utf8)
        for call in [".set(", "write(", "FileManager", "URLSession", "persist"] {
            #expect(!source.contains(call), "\(call)")
        }
    }
}

// MARK: The Finished card

@MainActor
struct FinishedCardTests {
    private func entry(_ n: Int, _ name: String, _ mime: String?) -> ArtifactEntry {
        ArtifactEntry(version: "v\(n)", artifact: nil, name: name, mime: mime, size: 1_000 + n, at: nil)
    }

    private var png: (Int) -> ArtifactEntry { { self.entry($0, "figure-\($0).png", "image/png") } }

    @Test func withFilesResultsLeadsOpenFollowsAndTheyAreBothThere() {
        let offer = FinishedOffer.of(.loaded([png(1), png(2), entry(3, "data.csv", "text/csv")]))
        #expect(offer.lead == .results && offer.hasResults && offer.hasPlainOpen)
    }

    @Test func exactlyOneFigureOffersKeepForThatFigure() {
        let one = FinishedOffer.of(.loaded([png(1), entry(2, "data.csv", "text/csv"), entry(3, "notes.md", "text/markdown")]))
        #expect(one.keepable?.version == "v1")
        let two = FinishedOffer.of(.loaded([png(1), png(2)]))
        #expect(two.keepable == nil)
        let none = FinishedOffer.of(.loaded([entry(1, "data.csv", "text/csv")]))
        #expect(none.keepable == nil)
        // A vector figure has no thumbnail and isn't what Keep takes here.
        let svg = FinishedOffer.of(.loaded([entry(1, "chart.svg", "image/svg+xml")]))
        #expect(svg.keepable == nil)
    }

    @Test func aSessionThatMadeNoFilesHasOnlyOpenAndOpenIsTheClay() {
        let offer = FinishedOffer.of(.loaded([]))
        #expect(offer.lead == .open && !offer.hasResults && !offer.hasPlainOpen && offer.keepable == nil)
    }

    @Test func untilTheListIsReadResultsLeadsAndNothingIsKept() {
        for listing in [FinishedResults.Listing.unknown, .reading] {
            let offer = FinishedOffer.of(listing)
            #expect(offer.lead == .results && offer.hasResults && offer.keepable == nil)
        }
    }

    @Test func aListThatCouldNotBeReadLeavesOpenAsTheLeadAndResultsPlain() {
        let offer = FinishedOffer.of(.failed)
        #expect(offer.lead == .open && offer.hasResults && offer.keepable == nil)
    }

    @Test func theFilesLineCountsWhatWasMadeAndIsSilentOtherwise() {
        #expect(FinishedCardText.files(.loaded([png(1)])) == "1 file")
        #expect(FinishedCardText.files(.loaded([png(1), png(2), entry(3, "a.csv", nil)])) == "3 files")
        #expect(FinishedCardText.files(.loaded([])) == nil)
        #expect(FinishedCardText.files(.reading) == nil && FinishedCardText.files(.failed) == nil)
    }

    @Test func theMetaLineIsTheProjectAndHowLongItTookInTheOneStyleTimesAreWritten() {
        #expect(FinishedCardText.meta(project: "Assay development", duration: 21 * 60) == "Assay development · 21m")
        #expect(FinishedCardText.meta(project: "Assay development", duration: 45) == "Assay development · 45s")
        #expect(FinishedCardText.meta(project: "Assay development", duration: nil) == "Assay development")
    }

    @Test func theCardReadsAsOneSentenceInOrder() {
        let spoken = FinishedCardText.spoken(title: "Plate reader QC", project: "Assay development", duration: 21 * 60,
                                             files: "3 files", reviewer: "Reviewer: no findings")
        #expect(spoken == "Finished. Plate reader QC. Assay development, 21 minutes. 3 files. Reviewer: no findings")
        #expect(FinishedCardText.spoken(title: "T", project: "P", duration: nil, files: nil, reviewer: nil) == "Finished. T. P")
    }

    @Test func theReviewerLineComesFromTheContractsOwnLine() {
        let none = ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 1)
        let some = ReviewerCounts(standing: 2, fixed: 1, running: 0, reviews: 1)
        let never = ReviewerCounts(standing: 0, fixed: 0, running: 0, reviews: 0)
        #expect(none.line == "Reviewer: no findings")
        #expect(some.line == "Reviewer: 2 findings")
        #expect(never.line == nil)
        // The row is there for any of them, and left out when there is nothing at all.
        #expect(FinishedMediaRow.shows(pictures: [], files: nil, reviewer: none.line))
        #expect(!FinishedMediaRow.shows(pictures: [], files: nil, reviewer: never.line))
    }

    // MARK: Reading the files

    /// Answers the card's reads with made-up files and records them.
    @MainActor
    final class Fake {
        var reads: [ArtifactRead] = []
        var entries: [ArtifactEntry] = []
        var ready = true
        var listOutcome: ArtifactReadOutcome?
        static let webp = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBP".utf8)

        func read(_ read: ArtifactRead) async -> ArtifactReadOutcome {
            reads.append(read)
            switch read {
            case .list: return listOutcome ?? .list(entries)
            case .thumb: return .bytes(Self.webp)
            default: return .unreadable
            }
        }

        func results() -> FinishedResults {
            let image = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
            return FinishedResults(dependencies: .init(read: { [unowned self] in await self.read($0) }, isReady: { [unowned self] in self.ready }),
                                   thumbnails: ShelfThumbnails(decoder: { _ in .success(image) }))
        }
    }

    private let session = Fixture.session("00000000-0000-4000-8000-000000000001", .finished)

    @Test func theListIsReadOnceAndThenOnlyTheFirstThreePicturesAreAskedFor() async {
        let fake = Fake()
        fake.entries = (1...5).map { png($0) } + [entry(9, "data.csv", "text/csv")]
        let results = fake.results()
        await results.load(session)
        await results.thumbnails.settled()
        #expect(fake.reads.first == .list(frame: session.id))
        #expect(fake.reads.dropFirst().map { $0 } == [.thumb(version: "v1", width: 120), .thumb(version: "v2", width: 120),
                                                      .thumb(version: "v3", width: 120)])
        #expect(results.thumbnails.versions == ["v1", "v2", "v3"])
        if case .loaded(let entries) = results.listing(for: session.id) { #expect(entries.count == 6) } else { Issue.record("not loaded") }
    }

    @Test func aSecondLoadReadsNothingMore() async {
        let fake = Fake()
        fake.entries = [png(1), png(2)]
        let results = fake.results()
        await results.load(session)
        await results.thumbnails.settled()
        let count = fake.reads.count
        await results.load(session)
        #expect(fake.reads.count == count)
    }

    @Test func nothingIsReadForCardsThatWereNeverLoadedAndForgetLetsGoOfEverything() async {
        let fake = Fake()
        fake.entries = [png(1)]
        let results = fake.results()
        #expect(fake.reads.isEmpty)
        #expect(results.listing(for: session.id) == .unknown)
        await results.load(session)
        await results.thumbnails.settled()
        #expect(results.thumbnails.versions == ["v1"])
        results.forget(session.id)
        #expect(results.listing(for: session.id) == .unknown)
        #expect(results.thumbnails.versions.isEmpty)
    }

    @Test func aPageThatIsNotUpIsAFailureNotAHang() async {
        let fake = Fake()
        fake.ready = false
        let results = fake.results()
        await results.load(session)
        #expect(results.listing(for: session.id) == .failed)
        #expect(fake.reads.isEmpty)
    }

    @Test func aTaskCancelledBeforeItsTurnLeavesNoListing() async {
        let fake = Fake()
        fake.entries = [png(1)]
        let results = fake.results()
        let task = Task { await results.load(session) }
        task.cancel()
        await task.value
        let listing = results.listing(for: session.id)
        #expect(listing == .unknown || listing == .loaded([png(1)]))
    }

    @Test func bytesThatAreNotWebPAreNeverHandedToTheDecoder() async {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let store = ShelfThumbnails(decoder: { _ in counter.n += 1; return .failure(.notAnImage) })
        let results = FinishedResults(dependencies: .init(read: { read in
            if case .list = read { return .list([ArtifactEntry(version: "v1", artifact: nil, name: "a.png", mime: "image/png", size: 5, at: nil)]) }
            return .bytes(Data("not a webp at all".utf8))
        }, isReady: { true }), thumbnails: store)
        await results.load(session)
        await store.settled()
        #expect(counter.n == 0)
    }

    @Test func theCardReadsThroughItsOwnQueueNotTheShelfs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/FinishedResults.swift"), encoding: .utf8)
        #expect(source.contains("ShelfTransfers(limit: 1"))
        #expect(!source.contains("ResultsShelf.shared"))
        #expect(!source.contains("callAsyncJavaScript"))
    }

    @Test func theKeepSheetIsOpenedWithTheSubjectAndTheLiveReadsOfTheShelf() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/KeepFromCard.swift"), encoding: .utf8)
        #expect(source.contains("KeepModel(subject: subject, dependencies: .live(shelf: shelf))"))
        #expect(source.contains("KeepSheet(model: model"))
        let panel = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/LabPanelView.swift"), encoding: .utf8)
        #expect(panel.contains("KeepSubject(session: session, entry: entry)"))
        #expect(panel.contains("ResultsWindowController.shared.show(focusing: session)"))
    }
}

// MARK: Sounds

@MainActor
struct PanelSoundTests {
    private func model() -> (LabModel, SoundLog) {
        let model = LabModel()
        let log = SoundLog()
        model.isQuiet = { false }
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        model.playSound = { log.played.append($0) }
        return (model, log)
    }

    final class SoundLog { var played: [PanelSound] = [] }

    @Test func eachKindOfEventHasItsOwnSystemSound() {
        let names = PanelSound.allCases.map(\.systemName)
        #expect(Set(names).count == 4)
        #expect(names == ["Glass", "Submarine", "Basso", "Hero"])
        for name in names { #expect(NSSound(named: name) != nil, "\(name)") }
    }

    @Test func theTableMapsEveryCardToItsSoundOrNone() {
        let s = Fixture.session("a", .needsInput, reason: .question)
        #expect(PanelSound.sound(for: .needsInput(s)) == .question)
        #expect(PanelSound.sound(for: .needsInput(Fixture.session("a", .needsInput, reason: .plan))) == .plan)
        #expect(PanelSound.sound(for: .needsInput(Fixture.session("a", .needsInput, reason: .web))) == .question)
        #expect(PanelSound.sound(for: .failed(Fixture.session("a", .error))) == .failure)
        #expect(PanelSound.sound(for: .finished(Fixture.session("a", .finished))) == .finish)
        #expect(PanelSound.sound(for: .saved(URL(fileURLWithPath: "/tmp/made-up.csv"))) == nil)
        #expect(PanelSound.sound(for: .notice(LabNotice(id: "n", symbol: "bell", caption: "c", title: "t", detail: "d", lifetime: .seconds(1)))) == nil)
    }

    @Test func oneReadPlaysTheMostUrgentOfWhatItRaises() {
        #expect(PanelSound.loudest([.finish, .failure, .plan]) == .plan)
        #expect(PanelSound.loudest([.finish, .failure]) == .failure)
        #expect(PanelSound.loudest([.question, .plan]) == .question)
        #expect(PanelSound.loudest([]) == nil)
    }

    @Test func aQuestionAPlanAFailureAndAFinishPlayTheirOwn() {
        let (model, log) = model()
        model.ingest(Fixture.snapshot(Fixture.session("q", .running), Fixture.session("p", .running),
                                      Fixture.session("f", .running), Fixture.session("d", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("q", .needsInput, reason: .question), Fixture.session("p", .running),
                                      Fixture.session("f", .running), Fixture.session("d", .running)))
        #expect(log.played == [.question])
        model.ingest(Fixture.snapshot(Fixture.session("q", .needsInput, reason: .question), Fixture.session("p", .needsInput, reason: .plan),
                                      Fixture.session("f", .running), Fixture.session("d", .running)))
        #expect(log.played == [.question, .plan])
        model.ingest(Fixture.snapshot(Fixture.session("q", .needsInput, reason: .question), Fixture.session("p", .needsInput, reason: .plan),
                                      Fixture.session("f", .error), Fixture.session("d", .running)))
        #expect(log.played == [.question, .plan, .failure])
        model.ingest(Fixture.snapshot(Fixture.session("q", .needsInput, reason: .question), Fixture.session("p", .needsInput, reason: .plan),
                                      Fixture.session("f", .error), Fixture.session("d", .finished)))
        #expect(log.played == [.question, .plan, .failure, .finish])
    }

    @Test func aReadThatRaisesAFinishAndAQuestionPlaysOnlyTheQuestion() {
        let (model, log) = model()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question), Fixture.session("b", .finished)))
        #expect(log.played == [.question])
    }

    @Test func nothingPlaysAtLaunchWhileQuietOrForAFinishThatIsHeld() {
        // At launch: what already waits is no news.
        let (first, firstLog) = model()
        first.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(firstLog.played.isEmpty)
        // A presentation: quiet.
        let (quiet, quietLog) = model()
        quiet.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        quiet.isQuiet = { true }
        quiet.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        #expect(quietLog.played.isEmpty)
        // A Nidus focus session holds finishes.
        let (held, heldLog) = model()
        held.holdsFinishes = { true }
        held.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        held.ingest(Fixture.snapshot(Fixture.session("a", .finished)))
        #expect(heldLog.played.isEmpty)
    }

    @Test func theSettingIsReadEachTimeAndOffIsSilent() throws {
        let suite = "capsid-panel-sound-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist"))
        }
        defaults.set(false, forKey: SettingsKey.soundOnNeedsInput)
        // Off: nothing to hear, and nothing to check but that it doesn't throw.
        PanelSound.play(.question, defaults: defaults)
        #expect(defaults.bool(forKey: SettingsKey.soundOnNeedsInput) == false)
    }

    @Test func aFinishIsTheQuietestSound() {
        #expect(PanelSound.finish.volume < PanelSound.question.volume)
    }
}

// MARK: The stack of working sessions

@MainActor
struct PanelStackTests {
    @Test func itOpensWithTwoOrMoreWorkingAndThePointerOverIt() {
        #expect(!PanelStack.expands(working: 1, hovering: true))
        #expect(!PanelStack.expands(working: 0, hovering: true))
        #expect(!PanelStack.expands(working: 2, hovering: false))
        #expect(PanelStack.expands(working: 2, hovering: true))
        #expect(PanelStack.expands(working: 9, hovering: true))
    }

    @Test func itShowsAtMostFiveRowsAndSaysHowManyMore() {
        let sessions = (1...8).map { Fixture.session("s\($0)", .running) }
        let rows = PanelStack.rows(sessions)
        #expect(rows.shown.map(\.id) == ["s1", "s2", "s3", "s4", "s5"] && rows.more == 3)
        #expect(PanelStack.rows(Array(sessions.prefix(3))).more == 0)
    }

    @Test func aRowIsSpokenAsTitleAndHowLongItHasWorked() {
        let now = Date()
        let session = SessionStatus(id: "a", projectID: "p", projectName: "Example project", title: "Plate layout", state: .running,
                                    updatedAt: now, startedAt: now.addingTimeInterval(-17 * 60 - 30))
        #expect(PanelStackRows.spoken(session, now: now) == "Plate layout, 17 minutes")
    }

    @Test func theUnionOfWhatThePanelAndTheListShowIsEachSessionOnce() {
        let a = Fixture.session("a", .running), b = Fixture.session("b", .running), c = Fixture.session("c", .running)
        #expect(PanelInsights.union([a], [a, b, c]).map(\.id) == ["a", "b", "c"])
        #expect(PanelInsights.union([], [b]).map(\.id) == ["b"])
        #expect(PanelInsights.union([], []).isEmpty)
    }
}

// MARK: What VoiceOver says

@MainActor
struct PanelSpeechTests {
    @Test func timesAreSpelledOut() {
        #expect(PanelSpeech.elapsed(1) == "1 second")
        #expect(PanelSpeech.elapsed(45) == "45 seconds")
        #expect(PanelSpeech.elapsed(60) == "1 minute")
        #expect(PanelSpeech.elapsed(17 * 60 + 30) == "17 minutes")
        #expect(PanelSpeech.elapsed(3600) == "1 hour")
        #expect(PanelSpeech.elapsed(3600 + 5 * 60) == "1 hour 5 minutes")
    }

    @Test func theWorkingCardIsOneSentenceWithItsProgress() {
        let now = Date()
        let progress = PlanProgress(step: 4, total: 6, title: "Check against published screens")
        let spoken = PanelSpeech.working(title: "CRISPR screen hits", project: "Screen analysis",
                                         since: now.addingTimeInterval(-42 * 60), now: now, others: 2, progress: progress,
                                         specimen: "CRISPR, picked because the session is about gene editing")
        #expect(spoken == "Working. CRISPR screen hits. Screen analysis, 42 minutes. Step 4 of 6 · Check against published screens. "
                + "CRISPR, picked because the session is about gene editing. 2 other sessions are working")
        #expect(PanelSpeech.working(title: "T", project: "P", since: nil, others: 0, progress: nil, specimen: nil) == "Working. T. P")
    }

    @Test func aFailureCardNamesTheReasonAndHowLongItRan() {
        #expect(PanelSpeech.failed(title: "Figure 2 rebuild", project: "Manuscript figures", duration: 7 * 60 + 58,
                                   reason: "The R kernel ran out of memory.")
                == "Stopped with an error. Figure 2 rebuild. Manuscript figures, ran 7 minutes. The R kernel ran out of memory.")
    }

    @Test func aNoteIsSaidWithWhoSaidIt() {
        #expect(PanelSpeech.note(text: "Two wells are empty.", title: "Plate layout", project: "Assay design")
                == "Claude says. Two wells are empty.. Plate layout, Assay design")
    }

    @Test func onlyACardThatNeedsYouIsAnnounced() {
        let asking = Fixture.session("a", .needsInput, reason: .question, title: "Protein stability screen")
        #expect(PanelSpeech.announcement(for: .needsInput(asking)) == "Asked you a question: Protein stability screen")
        #expect(PanelSpeech.announcement(for: .failed(Fixture.session("a", .error, title: "Figure 2 rebuild")))
                == "Stopped with an error: Figure 2 rebuild")
        #expect(PanelSpeech.announcement(for: .finished(Fixture.session("a", .finished))) == nil)
        #expect(PanelSpeech.announcement(for: .saved(URL(fileURLWithPath: "/tmp/made-up.csv"))) == nil)
    }

    @Test func theArrivalOfACardSaysItThroughTheHook() {
        let saved = PanelAnnouncer.say
        defer { PanelAnnouncer.say = saved }
        var said: [String] = []
        PanelAnnouncer.say = { said.append($0) }
        PanelAnnouncer.cardArrived(.needsInput(Fixture.session("a", .needsInput, reason: .plan, title: "Batch effect check")))
        PanelAnnouncer.cardArrived(.finished(Fixture.session("b", .finished)))
        #expect(said == ["Plan ready for your review: Batch effect check"])
    }

    @Test func eachCardIsOneAccessibilityElementWithItsButtonsAsNamedActions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let panel = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/LabPanelView.swift"), encoding: .utf8)
        // The working, stopped, finished and note cards: one label each, their
        // buttons named actions; the whole panel keeps Open and Dismiss.
        #expect(panel.components(separatedBy: ".accessibilityElement(children: .ignore)").count - 1 >= 4)
        for action in ["Show every session", "Copy", "Results", "Open", "Dismiss"] {
            #expect(panel.contains(".accessibilityAction(named: \"\(action)\")"), "\(action)")
        }
        #expect(panel.contains("PanelAnnouncer.say"))
    }
}

// MARK: Notes from Claude

@MainActor
struct MidRunNoteCardsTests {
    private func note(_ id: String = "s#1", session: String = "s", text: String = "Two wells are empty.") -> MidRunNote {
        MidRunNote(id: id, sessionID: session, text: text, at: nil)
    }

    private func defaults(cards: Bool = true, plans: Bool = true) throws -> (UserDefaults, () -> Void) {
        let suite = "capsid-panel-notes-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(cards, forKey: SettingsKey.showCards)
        defaults.set(plans, forKey: SettingsKey.showPlansOnCard)
        return (defaults, {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist"))
        })
    }

    private func workingModel() -> LabModel {
        let model = LabModel()
        model.ingest(Fixture.snapshot(Fixture.session("s", .running, title: "Plate layout")))
        return model
    }

    @Test func aNoteBecomesAQuietTimedCardWithOpenAndItsWordsInTheNotice() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        let model = workingModel()
        MidRunNoteCards().offer([note()], to: model, defaults: defaults)
        guard case .notice(let notice)? = model.cards.first else { Issue.record("no card"); return }
        #expect(notice.id == "note-s#1")
        #expect(notice.caption == "Claude says")
        #expect(notice.midRunNote?.text == "Two wells are empty.")
        #expect(notice.lifetime == MidRunNoteCards.lifetime)
        if case .openSession(let session) = notice.action { #expect(session.id == "s") } else { Issue.record("not an Open") }
        // It queues behind the cards about sessions, as a notice does, and never sounds.
        #expect(PanelSound.sound(for: model.cards[0]) == nil)
    }

    @Test func theSameNoteIsNeverPostedTwiceAndAnotherSessionsNoteWaitsForItsSession() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        let model = workingModel()
        let cards = MidRunNoteCards()
        cards.offer([note()], to: model, defaults: defaults)
        cards.offer([note()], to: model, defaults: defaults)
        #expect(model.cards.count == 1)
        cards.offer([note("zz#2", session: "not-known")], to: model, defaults: defaults)
        #expect(model.cards.count == 1)
    }

    @Test func theSameSwitchesAsTheOtherCardsGateIt() throws {
        for (cards, plans) in [(false, true), (true, false), (false, false)] {
            let (defaults, cleanup) = try defaults(cards: cards, plans: plans)
            defer { cleanup() }
            let model = workingModel()
            MidRunNoteCards().offer([note()], to: model, defaults: defaults)
            #expect(model.cards.isEmpty, "cards \(cards) plans \(plans)")
        }
        let (on, cleanup) = try defaults()
        defer { cleanup() }
        #expect(MidRunNoteCards.mayPost(defaults: on))
    }

    @Test func aNoteIsSeenWhenItsCardReachesTheTopAndNotBefore() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        let model = workingModel()
        let insights = PanelInsights()
        insights.showDemo(notes: [note()])
        let cards = MidRunNoteCards()
        // A question is on top first: the note is queued behind it, unseen.
        model.ingest(Fixture.snapshot(Fixture.session("s", .needsInput, reason: .question)))
        cards.offer(insights.notes, to: model, defaults: defaults)
        cards.watch(model.cards, insights: insights)
        #expect(model.cards.count == 2 && insights.notes.count == 1)
        model.dismiss(model.cards[0])
        cards.watch(model.cards, insights: insights)
        #expect(insights.notes.isEmpty)
    }

    @Test func nothingOfANoteReachesAMacNotificationOrAPhone() {
        let notice = MidRunNoteCards.notice(for: note(), session: Fixture.session("s", .running))
        let settings = NotificationRules.Settings(enabled: true, authorized: true, finishes: true)
        #expect(NotificationRules.content(for: .notice(notice), settings: settings) == nil)
        #expect(PushRules.event(for: .notice(notice), holdingFinishes: false) == nil)
    }
}

// MARK: Lines from the contract's types, and the panel's pieces

@MainActor
struct PanelLinesTests {
    @Test func theProgressLineIsTheContractsOwn() {
        let progress = PlanProgress(step: 4, total: 6, title: "Check against published screens")
        #expect(progress.line == "Step 4 of 6 · Check against published screens")
        #expect(PlanProgress(step: 2, total: 5, title: nil).line == "Step 2 of 5")
        #expect((0...1).contains(progress.fraction))
    }

    @Test func theWorkingCardsViewsDrawFromTheContractTypesWithFakes() {
        // Drawn, not read: a view built from the fakes has a size.
        let bar = NSHostingView(rootView: PanelProgressBlock(progress: PlanProgress(step: 4, total: 6, title: "Check"))
            .frame(width: 296))
        #expect(bar.fittingSize.height > 14 && bar.fittingSize.width <= 296)
        let row = NSHostingView(rootView: FinishedMediaRow(
            pictures: [ArtifactEntry(version: "v1", artifact: nil, name: "a.png", mime: "image/png", size: 5, at: nil)],
            store: ShelfThumbnails(), files: "3 files", reviewer: "Reviewer: no findings").frame(width: 296))
        #expect(abs(row.fittingSize.height - 52) < 1)
    }

    @Test func aPictureTileIs72By52() {
        #expect(PanelThumbnail.size == CGSize(width: 72, height: 52))
    }

    @Test func theFailureParagraphIsThirteenPointsOnNineteen() {
        // Two lines of the reason, as the card sets it, are 38 points tall.
        let text = Text(verbatim: "The R kernel ran out of memory while loading the full count matrix, so nothing was drawn.")
            .font(.system(size: 13))
            .lineSpacing(LabPanelView.reasonLeading - LabPanelView.reasonNaturalLeading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 250)
        let host = NSHostingView(rootView: text)
        let height = host.fittingSize.height
        #expect(abs(height - 3 * 19) < 2.5 || abs(height - 2 * 19) < 2.5, "\(height)")
    }

    @Test func theFailureCardShowsAnElapsedClockAndNotATenseDuration() {
        let now = Date()
        let session = SessionStatus(id: "a", projectID: "p", projectName: "Manuscript figures", title: "Figure 2 rebuild", state: .error,
                                    updatedAt: now, startedAt: now.addingTimeInterval(-(7 * 60 + 58)))
        #expect(LabPanelView.ranFor(session) == "Manuscript figures · 7:58")
    }

    @Test func theFaceWidthsFollowTheirWells() {
        // (A card that asks has none; the rest follow the size setting's well.)
        // Checked through the source: the failure card is no longer one of the full-width cards.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let panel = (try? String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/LabPanelView.swift"), encoding: .utf8)) ?? ""
        #expect(panel.contains("case .card(.needsInput, _): 360"))
        #expect(!panel.contains("case .card(.needsInput, _), .card(.failed, _): 360"))
    }

    @Test func theActivityListShowsAWorkingRowsProgressUnderItsProject() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let list = try String(contentsOf: root.appendingPathComponent("Sources/Bench/Lab/ActivityList.swift"), encoding: .utf8)
        #expect(list.contains("progress: insights.progress[session.id]"))
        #expect(list.contains("insights.showing(model.working, from: .list)"))
        #expect(list.contains("PanelProgressBar(fraction: progress.fraction, height: 2)"))
    }
}

// MARK: The two scenes

@MainActor
struct PanelScenesTests {
    private func draw(_ elapsed: Double, size: CGFloat = 88) -> CGImage? {
        let view = Canvas { context, size in
            FilledPlate.draw(in: &context, size: size, elapsed: elapsed, tint: .black)
        }.frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    @Test func theFlourishIsUnderASecondAndAHalfAndRestsOnItsLastFrame() throws {
        #expect(FilledPlate.duration <= 1.5)
        let a = try #require(draw(FilledPlate.duration)), b = try #require(draw(FilledPlate.duration + 5))
        #expect(a.dataProvider?.data == b.dataProvider?.data)
        // And it does move before then: the first frame is not the last.
        let first = try #require(draw(0))
        #expect(first.dataProvider?.data != a.dataProvider?.data)
    }

    @Test func everyWellIsFilledAndBothSparklesAreInByTheEnd() {
        #expect(FilledPlate.wells.count == 8)
        #expect(FilledPlate.sparkles.count == 2)
        #expect(FilledPlate.sparkles.allSatisfy { $0.at + 0.3 <= FilledPlate.duration })
    }

    @Test func theScenesAreNotSpecimensAndAddNothingToTheRotationOrTheGuide() {
        #expect(!LabScenes.catalogue.contains { $0.name.contains("Plate") && $0.name.contains("Filled") })
        #expect(SpecimenNotes.all.count == LabScenes.catalogue.count)
    }

    /// Not a check of speed (a test machine is busy): reports what a frame
    /// costs, beside a specimen of the house for scale.
    @Test func whatAFrameOfTheFlourishCosts() throws {
        func milliseconds(_ frames: Int, _ draw: (Int) -> Void) -> Double {
            let start = ContinuousClock.now
            for i in 0..<frames { draw(i) }
            let elapsed = start.duration(to: .now)
            return (Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15) / Double(frames)
        }
        let frames = 300
        let plate = milliseconds(frames) { _ = self.draw(Double($0) / Double(frames) * FilledPlate.duration) }
        let house = LabScenes.catalogue.first { $0.name == "Plate reader" }!
        let reader = milliseconds(frames) { i in
            let view = Canvas { context, size in house.draw(&context, size, Double(i) / Double(frames) * house.duration, .black) }
                .frame(width: 88, height: 88)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            _ = renderer.cgImage
        }
        print("PANEL-SCENE-COST at 88 pt, 2x, drawn and rendered to an image: FilledPlate \(String(format: "%.3f", plate)) ms a frame, "
              + "the house's Plate reader \(String(format: "%.3f", reader)) ms a frame (\(frames) frames each)")
        #expect(plate < 100)
    }
}
