// ConversationShelfTests.swift — what the four items of the conversation's
// menu do (Shelf/ConversationMenu.swift), over a made-up session, shelf, toast
// and windows: Add to Shelf's three answers on the toast, Keep with Data and
// Code… handing the Keep sheet this file and session, Open as Reference and
// Show in Results, and what happens when the page isn't on a session. Nothing
// is read from or written to Claude Science; the shelf is a fake.
import Foundation
import Testing
@testable import Bench

@MainActor
struct ConversationShelfTests {
    static let route = NidusTaskSelection.Route(projectID: "proj_a", frameID: "00000000-0000-4000-8000-000000000001")
    static let session = SessionStatus(id: route.frameID, projectID: route.projectID, projectName: "Assay development",
                                       title: "Plate reader QC", state: .finished, updatedAt: Date(timeIntervalSince1970: 1_792_000_000))
    static let version = ShelfAddressTests.version
    static let figure = ConversationPick(kind: .image, version: version, name: "z_prime_by_plate.png")

    /// The actions over fakes, and what they were asked.
    final class Calls {
        var kept: [KeepSubject] = []
        var references: [(SessionStatus, String)] = []
        var results: [SessionStatus] = []
        var sessionAsks = 0
        var factsAsks: [String] = []
        var facts: ArtifactFacts?
    }

    private func make(route: NidusTaskSelection.Route? = ConversationShelfTests.route)
        -> (ConversationShelf, MadeShelf, ShelfToastModel, Calls) {
        let fake = MadeShelf()
        let calls = Calls()
        let toast = ShelfToastModel(shelf: fake.access, sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, announce: { _ in })
        let shelf = ConversationShelf(dependencies: .init(
            route: { route },
            session: { _ in calls.sessionAsks += 1; return Self.session },
            facts: { calls.factsAsks.append($0); return calls.facts },
            shelf: fake.access, toast: toast,
            keep: { calls.kept.append($0) },
            reference: { calls.references.append(($0, $1)) },
            results: { calls.results.append($0) }))
        return (shelf, fake, toast, calls)
    }

    // MARK: Add to Shelf

    @Test func addToShelfAsksTheShelfForThisVersionInThisSession() async {
        let (shelf, fake, toast, _) = make()
        await shelf.run(.addToShelf, on: Self.figure)
        #expect(fake.added.count == 1)
        let source = fake.added[0]
        #expect(source.session == Self.session)
        #expect(source.entry.version == Self.version)
        #expect(source.entry.name == "z_prime_by_plate.png")
        #expect(source.entry.kind == .image)
        // The shelf finds the answer itself: nothing is claimed here.
        #expect(source.answer == nil && source.row == nil && source.question == nil)
        #expect(toast.state == .added(MadeShelf.placement("z_prime_by_plate.png")))
    }

    @Test func aFileLinkWithNoExtensionKeepsItsWordsAndIsNotAPicture() async {
        let (shelf, fake, _, _) = make()
        await shelf.run(.addToShelf, on: ConversationPick(kind: .link, version: Self.version, name: "the notes"))
        #expect(fake.added.first?.entry.kind == .other)
        #expect(fake.added.first?.entry.name == "the notes")
    }

    @Test func theToastSaysAddingWhileTheFileIsFetched() async {
        let (shelf, fake, toast, _) = make()
        fake.holding = true
        let adding = Task { await shelf.run(.addToShelf, on: Self.figure) }
        for _ in 0..<20 { await Task.yield() }
        #expect(toast.state == .adding)
        fake.release()
        await adding.value
        #expect(toast.state == .added(MadeShelf.placement("z_prime_by_plate.png")))
    }

    @Test func aDuplicateSaysSoWithTheShelfButton() async {
        let (shelf, fake, toast, _) = make()
        let placement = MadeShelf.placement("z_prime_by_plate.png")
        fake.outcome = .alreadyOnShelf(placement)
        await shelf.run(.addToShelf, on: Self.figure)
        #expect(toast.state == .already(placement))
    }

    @Test func aFailureIsTheShelfsSentenceAndNothingElse() async {
        let (shelf, fake, toast, _) = make()
        fake.outcome = .failed("That file is too big to put on the shelf.")
        await shelf.run(.addToShelf, on: Self.figure)
        #expect(toast.state == .failed("That file is too big to put on the shelf."))
    }

    @Test func aPageNotOnASessionSaysSoAndAsksNothing() async {
        let (shelf, fake, toast, calls) = make(route: nil)
        for action in ConversationAction.allCases {
            await shelf.run(action, on: Self.figure)
            #expect(toast.state == .failed(ConversationShelf.noSession))
            toast.dismiss()
        }
        #expect(fake.added.isEmpty && calls.kept.isEmpty && calls.references.isEmpty && calls.results.isEmpty)
        #expect(calls.sessionAsks == 0)
    }

    // MARK: The others

    @Test func keepWithDataAndCodeHandsTheKeepSheetThisFileAndSession() async {
        let (shelf, fake, toast, calls) = make()
        await shelf.run(.keep, on: Self.figure)
        #expect(calls.kept.count == 1)
        #expect(calls.kept[0].session == Self.session)
        #expect(calls.kept[0].entry.version == Self.version)
        // The sheet reads its own facts and finds the answer, so no answer is pinned;
        // but the version is the user's pick, and no newer answer moves it.
        #expect(calls.kept[0].pinned == nil)
        #expect(calls.kept[0].selectsItsVersion)
        #expect(calls.kept[0].picksItsVersion)
        #expect(fake.added.isEmpty)
        #expect(toast.state == nil)
    }

    @Test func keepWithDataAndCodeUsesTheFilesOwnNameAndTypeOnceTheDaemonHasGivenThem() async {
        let (shelf, _, _, calls) = make()
        calls.facts = ArtifactFacts(v: Self.version, a: "bbbbbbbb-0000-4000-8000-000000000001", n: 3, name: "z_prime_by_plate.png",
                                    mime: "image/png", size: 85_000, at: Date(timeIntervalSince1970: 1_792_000_000),
                                    sha: nil, isUpload: false, code: nil, codeCut: false, environment: nil)
        await shelf.run(.keep, on: ConversationPick(kind: .image, version: Self.version, name: "Z prime by plate"))
        #expect(calls.factsAsks == [Self.version])
        let entry = calls.kept.first?.entry
        #expect(entry?.name == "z_prime_by_plate.png" && entry?.mime == "image/png" && entry?.size == 85_000)
        #expect(entry?.artifact == "bbbbbbbb-0000-4000-8000-000000000001")
        #expect(entry?.at == Date(timeIntervalSince1970: 1_792_000_000))
        // The sheet's proposed folder name is the file's, not the picture's alt text.
        #expect(KeepRules.defaultName(for: entry!) == "z_prime_by_plate")
        #expect(calls.kept.first?.selectsItsVersion == true)
    }

    @Test func keepWithDataAndCodeWithNoFactsStillOpensOnTheElementsWords() async {
        let (shelf, _, _, calls) = make()
        await shelf.run(.keep, on: Self.figure)
        #expect(calls.factsAsks == [Self.version])
        #expect(calls.kept.first?.entry.name == "z_prime_by_plate.png")
        #expect(calls.kept.first?.entry.version == Self.version)
        // Facts or not, the clicked version is the selection.
        #expect(calls.kept.first?.selectsItsVersion == true)
    }

    @Test func openAsReferenceNamesTheVersionToShow() async {
        let (shelf, fake, toast, calls) = make()
        await shelf.run(.openAsReference, on: Self.figure)
        #expect(calls.references.count == 1)
        #expect(calls.references[0].0 == Self.session && calls.references[0].1 == Self.version)
        #expect(fake.added.isEmpty && toast.state == nil)
    }

    @Test func showInResultsFocusesTheSession() async {
        let (shelf, _, _, calls) = make()
        await shelf.run(.showInResults, on: Self.figure)
        #expect(calls.results == [Self.session])
    }

    // MARK: A session made from ids

    @Test func aSessionBuiltFromIdsOpensTheConversationOnTheDaemonsPort() {
        let built = ConversationShelf.built(Self.route, port: 8123)
        #expect(built.id == Self.route.frameID && built.projectID == Self.route.projectID)
        #expect(built.deepLink?.absoluteString == "http://localhost:8123/projects/proj_a/frames/00000000-0000-4000-8000-000000000001")
        #expect(ConversationShelf.built(Self.route, port: nil).deepLink?.port == 8765)
    }

    @Test func theMainWindowsAddressIsTheSessionOnlyOnATaskRoute() {
        let frame = Self.route.frameID
        func route(_ address: String) -> NidusTaskSelection.Route? {
            NidusTaskSelection.route(url: URL(string: address), daemonPort: 8123)
        }
        #expect(route("http://localhost:8123/projects/proj_a/frames/\(frame)") == Self.route)
        #expect(route("http://localhost:8123/projects/proj_a") == nil)
        #expect(route("http://localhost:8123/") == nil)
        #expect(route("http://example.com:8123/projects/proj_a/frames/\(frame)") == nil)
    }
}
