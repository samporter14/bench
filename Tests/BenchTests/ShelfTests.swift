// ShelfTests.swift — the shelf's add, undo and remove (Kept/Shelf.swift) driven
// whole, on made-up reads and a scratch Kept folder under the temporary
// folder: a file copied with its README (the answer given, found, or the
// session's last), a version already on the shelf, a download that failed or
// that was too big, one add at a time for a version, `versions` and `count`
// staying current through add, undo and remove, and the Trash that a removal
// goes to (a stand-in for it: nothing here touches the real one). Nothing here
// talks to Claude Science; the disk is the real `KeptDisk` on a folder made for
// each test and removed after it.
import Foundation
import Testing
@testable import Bench

private enum Made {
    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000c1", projectID: "p-3", projectName: "Assay development",
                                       title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)
    static let artifact = "bbbbbbbb-0000-4000-8000-000000000031"
    static let v3 = "aaaaaaaa-0000-4000-8000-000000000033"
    static let v4 = "aaaaaaaa-0000-4000-8000-000000000034"
    static let notes = "aaaaaaaa-0000-4000-8000-000000000035"
    static let sheet = "aaaaaaaa-0000-4000-8000-000000000036"
    static let session2 = SessionStatus(id: "00000000-0000-4000-8000-0000000000c2", projectID: "p-4", projectName: "Receptor biology",
                                        title: "ER-phagy receptors", state: .finished, updatedAt: Date(), startedAt: nil)
    /// The nth made-up version: `aaaaaaaa-0000-4000-8000-0000000001nn`.
    static func version(_ n: Int) -> String { String(format: "aaaaaaaa-0000-4000-8000-%012d", 100 + n) }
    static let base = Date(timeIntervalSince1970: 1_800_000_000)
    static let answer = "Plate 7 is the low bar, at 0.41 against a cutoff of 0.5."
    static let asked = "Plot Z′ by plate, and show me where plate 7 goes wrong."

    static func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    static func entry(_ v: String = v3, name: String = "z_prime_by_plate.png") -> ArtifactEntry {
        ArtifactEntry(version: v, artifact: artifact, name: name, mime: name.hasSuffix(".md") ? "text/markdown" : "image/png",
                      size: bytes(v).count, at: at(1))
    }
    static func bytes(_ v: String) -> Data { Data("made-up bytes of \(v)".utf8) }
    static func source(_ v: String = v3, name: String = "z_prime_by_plate.png", session: SessionStatus = session,
                       answer: KeepPinnedAnswer? = nil, row: Int? = nil, question: String? = nil) -> ShelfSource {
        ShelfSource(session: session, entry: entry(v, name: name), answer: answer, row: row, question: question)
    }
}

/// Claude Science, made up. Each step can be made to fail.
@MainActor
private final class Science {
    var factsName = "z_prime_by_plate.png"
    /// A name for a version, instead of `factsName`.
    var names: [String: String] = [:]
    var factsSize: Int?
    var factsFail: ShelfTransferResult?
    var downloadFail: ShelfTransferResult?
    var corrupt = false
    var showing: ShowingRead = .found(ShowingMessage(i: 12, at: Made.at(20), text: Made.answer, how: .image, v: Made.v3))
    var last: KeepAnswer? = KeepAnswer(text: "Last words of the session.", at: Made.at(40), how: nil, isFallback: true)
    var asked: String? = Made.asked
    /// How long a download takes, to hold an add in flight.
    var downloadDelay: Duration = .zero
    private(set) var downloads: [String] = []
    private(set) var showingCalls = 0
    private(set) var lastCalls = 0
    private(set) var questions: [Int] = []

    func read(_ read: ArtifactRead) async -> ShelfTransferResult {
        switch read {
        case .facts(let v):
            if let factsFail { return factsFail }
            let sha = KeptDisk.sha256(of: Made.bytes(v))
            return .answered(.facts(ArtifactFacts(v: v, a: Made.artifact, n: v == Made.v4 ? 4 : 3, name: names[v] ?? factsName, mime: "image/png",
                                                  size: factsSize ?? Made.bytes(v).count, at: Made.at(1), sha: sha, isUpload: false,
                                                  code: nil, codeCut: false, environment: nil)))
        case .download(let v):
            downloads.append(v)
            if downloadDelay > .zero { try? await Task.sleep(for: downloadDelay) }
            if let downloadFail { return downloadFail }
            return .answered(.bytes(corrupt ? Data("not these bytes".utf8) : Made.bytes(v)))
        default:
            return .answered(.unreadable)
        }
    }
}

/// The time the made-up shelf thinks it is.
@MainActor
private final class Clock {
    var date = Made.at(100)
}

/// A scratch Kept folder, a stand-in Trash, a defaults suite of its own and the made-up reads.
@MainActor
private final class Rig {
    let clock = Clock()
    let science = Science()
    let scratch: URL
    let root: URL
    let trash: URL
    let disk: KeptDisk
    let index: KeptIndex
    let shelf: Shelf
    let defaults: UserDefaults
    private let suite = "capsid-tests-shelf-\(UUID().uuidString)"

    init() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-shelf-\(UUID().uuidString)", directoryHint: .isDirectory)
        let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        let trash = scratch.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        self.scratch = scratch
        self.root = root
        self.trash = trash
        defaults = UserDefaults(suiteName: suite)!
        let disk = KeptDisk(root: { root }, trash: { folder in
            let target = trash.appending(path: "\(UUID().uuidString) \(folder.lastPathComponent)", directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: folder, to: target)
            return target
        })
        self.disk = disk
        index = KeptIndex(disk: disk, root: { root })
        let science = self.science, defaults = self.defaults, clock = self.clock
        shelf = Shelf(index: index, dependencies: {
            ShelfDependencies(
                keep: KeepDependencies(
                    read: { await science.read($0) },
                    showing: { _, _, _ in science.noteShowing() },
                    lastAnswer: { _ in science.noteLast() },
                    thumbnails: ShelfThumbnails(),
                    disk: disk,
                    defaults: defaults,
                    root: { root },
                    scienceVersion: { "0.1.70" },
                    capsidVersion: "1.0",
                    now: { clock.date },
                    didKeep: { _ in }),
                question: { _, row in science.noteQuestion(row) })
        })
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        defaults.removePersistentDomain(forName: suite)
    }

    /// The README of the one folder in a collection, read back.
    func readme(in collection: String = "Assay development", folder name: String? = nil) throws -> (record: KeptRecord, text: KeptText, markdown: String) {
        let collectionFolder = root.appending(path: collection, directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: collectionFolder.path).filter { !$0.hasPrefix(".") }
        let folder = collectionFolder.appending(path: name ?? names.sorted()[0], directoryHint: .isDirectory)
        let markdown = try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8)
        let parsed = try #require(KeptReadme.parse(markdown))
        return (parsed.record, parsed.text, markdown)
    }

    func folders(in collection: String = "Assay development") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: collection).path)) ?? []).sorted()
    }

    func trashed() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []).sorted()
    }
}

@MainActor
private extension Science {
    func noteShowing() -> ShowingRead {
        showingCalls += 1
        return showing
    }

    func noteLast() -> KeepAnswer? {
        lastCalls += 1
        return last
    }

    func noteQuestion(_ row: Int) -> String? {
        questions.append(row)
        return asked
    }
}

private struct StillWaiting: Error {}

/// Waits, up to five seconds, for the condition.
@MainActor
private func until(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw StillWaiting()
}

private func placement(_ outcome: ShelfAddOutcome) -> ShelfPlacement? {
    switch outcome {
    case .added(let placement), .alreadyOnShelf(let placement): placement
    case .failed: nil
    }
}

private func failure(_ outcome: ShelfAddOutcome) -> String? {
    if case .failed(let sentence) = outcome { return sentence }
    return nil
}

// MARK: Adding

@Suite(.serialized) @MainActor
struct ShelfAddTests {
    @Test func aFileIsCopiedWithItsReadmeAndNothingElse() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let outcome = await rig.shelf.add(Made.source())
        let there = try #require(placement(outcome))
        guard case .added = outcome else { Issue.record("not added: \(outcome)"); return }
        #expect(there.name == "z_prime_by_plate.png")
        #expect(there.collection == "Assay development")
        #expect(there.folder == rig.root.appending(path: "Assay development/z_prime_by_plate", directoryHint: .isDirectory))
        // The file's own bytes, the README, and no data or code.
        let listing = try FileManager.default.subpathsOfDirectory(atPath: there.folder.path).sorted()
        #expect(listing == ["README.md", "z_prime_by_plate.png"])
        #expect(try Data(contentsOf: there.folder.appending(path: "z_prime_by_plate.png")) == Made.bytes(Made.v3))
        #expect(rig.science.downloads == [Made.v3])
        // Nothing hidden is left behind.
        #expect(rig.folders() == ["z_prime_by_plate"])

        let read = try rig.readme()
        #expect(read.record.name == "z_prime_by_plate")
        #expect(read.record.figure.path == "z_prime_by_plate.png")
        #expect(read.record.figure.version == Made.v3)
        #expect(read.record.figure.index == 3)
        #expect(read.record.figure.sha256 == KeptDisk.sha256(of: Made.bytes(Made.v3)))
        #expect(read.record.files.isEmpty && read.record.missing.isEmpty)
        #expect(read.record.sessionTitle == "Plate reader QC" && read.record.projectName == "Assay development")
        #expect(read.record.claudeScience == "0.1.70" && read.record.capsid == "1.0")
        #expect(read.text.legend == "")
        #expect(read.text.claudeSaid == Made.answer)
        #expect(read.text.origin.contains("[Plate reader QC](bench://session?project=p-3&frame=\(Made.session.id)), in Assay development."))
        #expect(read.text.origin.contains("message 12 in the session’s history. You asked: “\(Made.asked)”"))
        #expect(read.text.origin.contains("Version 3 of z_prime_by_plate.png, put on your shelf on "))
    }

    @Test func theAnswerTheCallerGaveIsUsedAndNothingIsLookedFor() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let answer = KeepPinnedAnswer(text: "The reply the reader showed.", at: Made.at(7))
        let outcome = await rig.shelf.add(Made.source(answer: answer, row: 31, question: "What went wrong with plate 7?"))
        #expect(placement(outcome) != nil)
        #expect(rig.science.showingCalls == 0 && rig.science.lastCalls == 0 && rig.science.questions.isEmpty)
        let read = try rig.readme()
        #expect(read.text.claudeSaid == "The reply the reader showed.")
        #expect(read.record.sourceRow == 31)
        #expect(read.record.question == "What went wrong with plate 7?")
        #expect(read.record.answerAt == Made.at(7))
        #expect(read.text.attribution.hasPrefix("From Claude’s answer at "))
        #expect(!ShelfRules.isLastAnswer(read.text))
    }

    @Test func aGivenAnswerWithAKnownRowButNoQuestionAsksForTheQuestion() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let answer = KeepPinnedAnswer(text: "The reply.", at: Made.at(7))
        _ = await rig.shelf.add(Made.source(answer: answer, row: 31))
        #expect(rig.science.showingCalls == 0)
        #expect(rig.science.questions == [31])
        #expect(try rig.readme().record.question == Made.asked)
    }

    @Test func theMessageThatShowedItIsFoundAndItsRowAndQuestionKept() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let outcome = await rig.shelf.add(Made.source())
        #expect(placement(outcome) != nil)
        #expect(rig.science.showingCalls == 1 && rig.science.lastCalls == 0)
        #expect(rig.science.questions == [12])
        let read = try rig.readme()
        #expect(read.record.sourceRow == 12)
        #expect(read.record.question == Made.asked)
        #expect(read.record.answerAt == Made.at(20))
        #expect(read.text.claudeSaid == Made.answer)
        #expect(!ShelfRules.isLastAnswer(read.text))
    }

    @Test func whenNoMessageIsFoundTheLastAnswerStandsInAndTheReadmeSaysSo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.showing = .notFound
        let outcome = await rig.shelf.add(Made.source())
        #expect(placement(outcome) != nil)
        #expect(rig.science.showingCalls == 1 && rig.science.lastCalls == 1)
        // No row, so no question is asked for.
        #expect(rig.science.questions.isEmpty)
        let read = try rig.readme()
        #expect(read.record.sourceRow == nil && read.record.question == nil)
        #expect(read.text.claudeSaid == "Last words of the session.")
        #expect(ShelfRules.isLastAnswer(read.text))
        #expect(read.text.attribution.contains("The answer that shows this version wasn’t found."))
        #expect(read.text.origin.contains("Capsid couldn’t find the answer that showed this version, so the words kept with it are Claude’s last in the session"))
        #expect(!read.text.origin.contains("message"))
    }

    @Test func withNoAnswerAtAllTheFileIsStillShelved() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.showing = .unreadable
        rig.science.last = nil
        let outcome = await rig.shelf.add(Made.source())
        #expect(placement(outcome) != nil)
        let read = try rig.readme()
        #expect(read.text.claudeSaid == "" && read.text.attribution == "")
        #expect(read.text.origin.contains("Capsid couldn’t find the answer that showed this version."))
        #expect(read.record.sourceRow == nil)
    }

    @Test func aVersionAlreadyOnTheShelfIsNotAddedAgain() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let first = await rig.shelf.add(Made.source())
        let again = await rig.shelf.add(Made.source())
        guard case .added(let one) = first, case .alreadyOnShelf(let two) = again else {
            Issue.record("expected added, then already on the shelf: \(first), \(again)")
            return
        }
        #expect(one == two)
        #expect(rig.folders() == ["z_prime_by_plate"])
        #expect(rig.science.downloads.count == 1)
    }

    @Test func aVersionKeptAnywhereUnderTheRootCountsAsOnTheShelf() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // Put it there the way Keep does, in a collection of its own, then ask a Shelf that never saw it.
        _ = await rig.shelf.add(Made.source(Made.v3))
        let moved = rig.root.appending(path: "Paper draft", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: false)
        try FileManager.default.moveItem(at: rig.root.appending(path: "Assay development/z_prime_by_plate"),
                                         to: moved.appending(path: "Fig 2B"))
        let other = Rig.freshShelf(on: rig)
        let outcome = await other.add(Made.source(Made.v3))
        guard case .alreadyOnShelf(let there) = outcome else { Issue.record("expected already on the shelf: \(outcome)"); return }
        #expect(there.collection == "Paper draft")
        #expect(there.folder == moved.appending(path: "Fig 2B", directoryHint: .isDirectory))
        #expect(rig.science.downloads.count == 1)
    }

    @Test func theProjectsCollectionIsTheOneLastKeptInto() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        KeptSettings.remember(collection: "Paper draft", for: "p-3", defaults: rig.defaults)
        let outcome = await rig.shelf.add(Made.source())
        #expect(placement(outcome)?.collection == "Paper draft")
        #expect(rig.folders(in: "Paper draft") == ["z_prime_by_plate"])
        #expect(rig.folders(in: "Assay development").isEmpty)
    }

    @Test func aNameThatIsTakenGetsTheDatedName() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        _ = await rig.shelf.add(Made.source(Made.v3))
        let outcome = await rig.shelf.add(Made.source(Made.v4))
        let there = try #require(placement(outcome))
        #expect(there.name == "z_prime_by_plate.png")
        #expect(there.folder.lastPathComponent.hasPrefix("z_prime_by_plate 20"))
        #expect(rig.folders().count == 2)
        #expect(rig.shelf.versions == [Made.v3, Made.v4])
        // Both cards read the file's own name.
        let items = ShelfRules.items(from: try await rig.scan())
        #expect(items.map(\.title) == ["z_prime_by_plate.png", "z_prime_by_plate.png"])
    }

    @Test func aDocumentIsShelvedUnderItsOwnName() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.factsName = "qc_notes.md"
        let outcome = await rig.shelf.add(Made.source(Made.notes, name: "qc_notes.md"))
        let there = try #require(placement(outcome))
        #expect(there.name == "qc_notes.md")
        #expect(there.folder.lastPathComponent == "qc_notes")
        #expect(ShelfKind.classify(fileName: there.name) == .document)
        #expect(FileManager.default.fileExists(atPath: there.folder.appending(path: "qc_notes.md").path))
    }

    @Test func aFileCalledReadmeDoesNotTakeTheReadmesPlace() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.factsName = "README.md"
        let outcome = await rig.shelf.add(Made.source(Made.notes, name: "README.md"))
        let there = try #require(placement(outcome))
        #expect(there.name == "README 2.md")
        #expect(try rig.readme().record.figure.path == "README 2.md")
        #expect(try Data(contentsOf: there.folder.appending(path: "README 2.md")) == Made.bytes(Made.notes))
    }

    @Test func bytesThatDontMatchTheChecksumAreShelvedAndTheReadmeSaysSo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.corrupt = true
        let outcome = await rig.shelf.add(Made.source())
        #expect(placement(outcome) != nil)
        let read = try rig.readme()
        #expect(read.record.figure.expectedSha256 == KeptDisk.sha256(of: Made.bytes(Made.v3)))
        #expect(read.markdown.contains("## Checksums"))
    }
}

// MARK: Failing

@Suite(.serialized) @MainActor
struct ShelfFailureTests {
    @Test func aDownloadThatFailedIsASentenceAndLeavesNothing() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadFail = .timedOut
        let outcome = await rig.shelf.add(Made.source())
        #expect(failure(outcome) == "Couldn’t add z_prime_by_plate.png to your shelf. Claude Science took too long to answer.")
        #expect(rig.shelf.versions.isEmpty && rig.shelf.adding.isEmpty && rig.shelf.count == 0)
        #expect(!FileManager.default.fileExists(atPath: rig.root.appending(path: "Assay development").path)
            || rig.folders().isEmpty)
        // And a try afterwards works.
        rig.science.downloadFail = nil
        #expect(placement(await rig.shelf.add(Made.source())) != nil)
    }

    @Test func theFactsThatCouldntBeReadAreASentenceToo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.factsFail = .notReady
        #expect(failure(await rig.shelf.add(Made.source())) == "Couldn’t add z_prime_by_plate.png to your shelf. Capsid isn't connected to Claude Science right now.")
        rig.science.factsFail = .answered(.missing)
        #expect(failure(await rig.shelf.add(Made.source())) == "z_prime_by_plate.png isn’t in Claude Science any more, so it can’t go on your shelf.")
        rig.science.factsFail = .answered(.lost)
        #expect(failure(await rig.shelf.add(Made.source())) == "Couldn’t add z_prime_by_plate.png to your shelf. Claude Science needs you to sign in again.")
        #expect(rig.science.downloads.isEmpty)
    }

    @Test func aFileOverTheCapIsNotDownloaded() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.factsSize = 9 * 1024 * 1024
        #expect(failure(await rig.shelf.add(Made.source())) == "z_prime_by_plate.png is over 8 MB, which is more than the shelf takes.")
        #expect(rig.science.downloads.isEmpty)
    }

    @Test func aFileThatWentWhileItWasBeingFetched() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadFail = .answered(.missing)
        #expect(failure(await rig.shelf.add(Made.source())) == "z_prime_by_plate.png isn’t in Claude Science any more, so it can’t go on your shelf.")
    }

    @Test func aKeptFolderThatIsntThereIsASentence() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // The folder the Kept folder belongs in is a file: nothing is made on a path that isn't ours.
        let blocked = rig.scratch.appending(path: "Blocked", directoryHint: .isDirectory)
        try Data("x".utf8).write(to: blocked)
        let disk = KeptDisk(root: { blocked.appending(path: "Kept", directoryHint: .isDirectory) })
        let index = KeptIndex(disk: disk, root: { blocked.appending(path: "Kept", directoryHint: .isDirectory) })
        let science = rig.science, defaults = rig.defaults
        let shelf = Shelf(index: index, dependencies: {
            ShelfDependencies(
                keep: KeepDependencies(read: { await science.read($0) }, showing: { _, _, _ in .notFound }, lastAnswer: { _ in nil },
                                       thumbnails: ShelfThumbnails(), disk: disk, defaults: defaults, root: { blocked },
                                       scienceVersion: { nil }, capsidVersion: "1.0", now: { Made.at(100) }, didKeep: { _ in }),
                question: { _, _ in nil })
        })
        let sentence = try #require(failure(await shelf.add(Made.source())))
        #expect(sentence.hasPrefix("Couldn’t add z_prime_by_plate.png to your shelf. "))
        #expect(shelf.versions.isEmpty && shelf.adding.isEmpty)
    }
}

// MARK: One at a time

@Suite(.serialized) @MainActor
struct ShelfOneAtATimeTests {
    @Test func aSecondAskForTheSameVersionAnswersWithTheFirstsOutcome() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadDelay = .milliseconds(120)
        async let first = rig.shelf.add(Made.source())
        try await until("the add is under way") { rig.shelf.adding.contains(Made.v3) }
        async let second = rig.shelf.add(Made.source())
        let (one, two) = await (first, second)
        #expect(one == two)
        guard case .added = one else { Issue.record("expected added: \(one)"); return }
        #expect(rig.science.downloads.count == 1)
        #expect(rig.folders() == ["z_prime_by_plate"])
        #expect(rig.shelf.adding.isEmpty)
    }

    @Test func differentVersionsMayBeAddedTogether() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadDelay = .milliseconds(60)
        async let a = rig.shelf.add(Made.source(Made.v3))
        async let b = rig.shelf.add(Made.source(Made.v4))
        try await until("both under way") { rig.shelf.adding == [Made.v3, Made.v4] }
        let (one, two) = await (a, b)
        #expect(placement(one) != nil && placement(two) != nil)
        #expect(rig.shelf.adding.isEmpty)
        #expect(rig.shelf.versions == [Made.v3, Made.v4])
    }

    @Test func theSpinnerIsOnlyForTheVersionBeingAdded() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadDelay = .milliseconds(80)
        async let outcome = rig.shelf.add(Made.source())
        try await until("under way") { rig.shelf.adding.contains(Made.v3) }
        #expect(!rig.shelf.adding.contains(Made.v4))
        #expect(!rig.shelf.contains(version: Made.v3))
        _ = await outcome
        #expect(rig.shelf.adding.isEmpty)
        #expect(rig.shelf.contains(version: Made.v3))
    }
}

// MARK: What is on it

@Suite(.serialized) @MainActor
struct ShelfVersionsTests {
    @Test func theFoldersAreReadOnceLazilyAndOnlyWhenSomethingAsks() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        _ = await rig.shelf.add(Made.source(Made.v3))
        _ = await rig.shelf.add(Made.source(Made.v4))
        // A shelf that has never looked knows nothing.
        let fresh = Rig.freshShelf(on: rig)
        #expect(fresh.versions.isEmpty && fresh.count == 0)
        #expect(!fresh.contains(version: Made.v3))
        try await until("the folders are read") { fresh.versions == [Made.v3, Made.v4] }
        #expect(fresh.count == 2)
        #expect(fresh.contains(version: Made.v4))
        #expect(!fresh.contains(version: Made.notes))
    }

    @Test func versionsAndCountFollowAnAddAtOnce() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        #expect(rig.shelf.count == 0)
        _ = await rig.shelf.add(Made.source())
        #expect(rig.shelf.versions == [Made.v3])
        #expect(rig.shelf.count == 1)
        // The read of the folders that follows agrees.
        await rig.index.refreshAndWait()
        #expect(rig.shelf.versions == [Made.v3] && rig.shelf.count == 1)
    }

    @Test func undoPutsTheFolderInTheTrashAndOffTheShelf() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let there = try #require(placement(await rig.shelf.add(Made.source())))
        #expect(await rig.shelf.undo(there))
        #expect(rig.shelf.versions.isEmpty && rig.shelf.count == 0)
        #expect(!rig.shelf.contains(version: Made.v3))
        #expect(rig.folders().isEmpty)
        // In the Trash whole, with its README: never deleted.
        let trashed = try #require(rig.trashed().first)
        #expect(trashed.hasSuffix("z_prime_by_plate"))
        let inside = try FileManager.default.subpathsOfDirectory(atPath: rig.trash.appending(path: trashed).path).sorted()
        #expect(inside == ["README.md", "z_prime_by_plate.png"])
        await rig.index.refreshAndWait()
        #expect(rig.shelf.versions.isEmpty && rig.shelf.count == 0)
        // Added again afterwards, it is a new add.
        guard case .added = await rig.shelf.add(Made.source()) else { Issue.record("expected added"); return }
        #expect(rig.shelf.versions == [Made.v3])
    }

    @Test func undoRefusesAFolderThatIsNotAShelvedOne() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let stray = rig.root.appending(path: "Assay development/Notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: stray.appending(path: "README.md"))
        #expect(!(await rig.shelf.undo(ShelfPlacement(folder: stray, name: "Notes", collection: "Assay development"))))
        // And one outside the Kept folder.
        let outside = rig.scratch.appending(path: "Elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        #expect(!(await rig.shelf.undo(ShelfPlacement(folder: outside, name: "Elsewhere", collection: "x"))))
        #expect(FileManager.default.fileExists(atPath: stray.path) && FileManager.default.fileExists(atPath: outside.path))
        #expect(rig.trashed().isEmpty)
    }

    @Test func removingAnItemTakesEveryFolderOfItToTheTrashAndPuttingItBackBringsThemAll() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let there = try #require(placement(await rig.shelf.add(Made.source())))
        // The same version kept again with its data and code, in another folder.
        let twin = rig.root.appending(path: "Assay development/Fig 2B", directoryHint: .isDirectory)
        try await rig.copyKept(there.folder, to: twin, withData: true)
        await rig.index.refreshAndWait()
        let items = ShelfRules.items(from: rig.index.results)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.folder == twin && item.others.map(\.folder) == [there.folder])
        #expect(rig.shelf.count == 1)

        let removal = await rig.shelf.remove(item)
        #expect(removal.problem == nil && removal.moved.count == 2)
        #expect(rig.shelf.versions.isEmpty && rig.shelf.count == 0)
        #expect(rig.folders().isEmpty)
        #expect(rig.trashed().count == 2)

        #expect(await rig.shelf.putBack(removal) == nil)
        #expect(rig.folders() == ["Fig 2B", "z_prime_by_plate"])
        #expect(rig.trashed().isEmpty)
        #expect(rig.shelf.versions == [Made.v3] && rig.shelf.count == 1)
    }

    @Test func puttingBackNeverReplacesAFolderThatIsThereNow() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let there = try #require(placement(await rig.shelf.add(Made.source())))
        await rig.index.refreshAndWait()
        let item = try #require(ShelfRules.items(from: rig.index.results).first)
        let removal = await rig.shelf.remove(item)
        // Something took the name meanwhile.
        try FileManager.default.createDirectory(at: there.folder, withIntermediateDirectories: true)
        try Data("not ours".utf8).write(to: there.folder.appending(path: "mine.txt"))
        #expect(await rig.shelf.putBack(removal) == nil)
        #expect(try Data(contentsOf: there.folder.appending(path: "mine.txt")) == Data("not ours".utf8))
        let names = rig.folders()
        #expect(names.count == 2 && names.contains("z_prime_by_plate"))
        #expect(names.contains { $0.hasPrefix("z_prime_by_plate 20") })
        #expect(rig.shelf.versions == [Made.v3])
    }
}

@MainActor
private extension Rig {
    /// A second shelf on the same folders, that has never looked.
    static func freshShelf(on rig: Rig) -> Shelf {
        let science = rig.science, disk = rig.disk, defaults = rig.defaults, root = rig.root
        let index = KeptIndex(disk: disk, root: { root })
        return Shelf(index: index, dependencies: {
            ShelfDependencies(
                keep: KeepDependencies(read: { await science.read($0) }, showing: { _, _, _ in .notFound }, lastAnswer: { _ in nil },
                                       thumbnails: ShelfThumbnails(), disk: disk, defaults: defaults, root: { root },
                                       scienceVersion: { nil }, capsidVersion: "1.0", now: { Made.at(100) }, didKeep: { _ in }),
                question: { _, _ in nil })
        })
    }

    func scan() async throws -> [KeptResult] {
        try await disk.scan()
    }

    /// The folder copied to another name, with a data file and a script added
    /// to its README: what Keep with Data and Code… leaves of the same figure.
    func copyKept(_ folder: URL, to target: URL, withData: Bool) async throws {
        try FileManager.default.copyItem(at: folder, to: target)
        guard withData else { return }
        var read = try await disk.readme(at: target)
        read.record.name = target.lastPathComponent
        read.record.files = [KeptFile(path: "data/z_prime_by_plate.csv", role: .data, artifact: nil, version: nil, sha256: nil, bytes: 8)]
        try FileManager.default.createDirectory(at: target.appending(path: "data"), withIntermediateDirectories: true)
        try Data("plate\n1\n".utf8).write(to: target.appending(path: "data/z_prime_by_plate.csv"))
        try await disk.replaceReadme(at: target, markdown: KeptReadme.render(read.record, text: read.text))
    }
}

// MARK: The window's rules

@MainActor
private extension Rig {
    /// `count` figures shelved one minute apart, the newest last added: item 1 is the oldest.
    func shelve(_ count: Int) async {
        for n in 1...count {
            let v = Made.version(n)
            science.names[v] = "item_\(n).png"
            clock.date = Made.at(100 + Double(n))
            _ = await shelf.add(Made.source(v, name: "item_\(n).png"))
        }
    }

    /// The four of the board's first row, in two projects: a figure, a heatmap, a note, a spreadsheet.
    func shelveTheBoardsRow() async {
        let items: [(String, String, SessionStatus)] = [
            (Made.v3, "z_prime_by_plate.png", Made.session), (Made.v4, "plate_7_heatmap.png", Made.session),
            (Made.notes, "qc_notes.md", Made.session), (Made.sheet, "receptors.xlsx", Made.session2),
        ]
        for (n, item) in items.enumerated() {
            science.names[item.0] = item.1
            clock.date = Made.at(100 + Double(n))
            _ = await shelf.add(Made.source(item.0, name: item.1, session: item.2))
        }
        await index.refreshAndWait()
    }
}

@Suite(.serialized) @MainActor
struct ShelfWindowRulesTests {
    @Test func theChipsCountWhatTheProjectAndTheSearchLeaveAndTheGridFollowsTheKind() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        let model = ShelfModel(shelf: rig.shelf)
        // Newest first: the spreadsheet was shelved last.
        #expect(model.shown.map(\.fileName) == ["receptors.xlsx", "qc_notes.md", "plate_7_heatmap.png", "z_prime_by_plate.png"])
        #expect(model.counts == ShelfRules.Counts(all: 4, figures: 2, documents: 1, tables: 1))
        #expect(model.projects == ["Receptor biology", "Assay development"])
        #expect(!model.isEmpty && !model.isFiltered)

        model.kind = .figure
        #expect(model.shown.map(\.fileName) == ["plate_7_heatmap.png", "z_prime_by_plate.png"])
        // The chips keep counting the project and the search, not the kind chosen.
        #expect(model.counts == ShelfRules.Counts(all: 4, figures: 2, documents: 1, tables: 1))
        model.project = "Assay development"
        #expect(model.counts == ShelfRules.Counts(all: 3, figures: 2, documents: 1, tables: 0))
        model.kind = .table
        #expect(model.shown.isEmpty && model.selection == nil && model.selected == nil)
        model.kind = nil
        model.search = "qc_notes"
        #expect(model.shown.map(\.fileName) == ["qc_notes.md"])
        #expect(model.counts == ShelfRules.Counts(all: 1, figures: 0, documents: 1, tables: 0))
        #expect(model.isFiltered)
        model.project = nil
        model.search = ""
        #expect(model.shown.count == 4 && !model.isFiltered)
    }

    @Test func theSelectionStaysOnWhatItWasOnOrGoesToTheFirstShown() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        let model = ShelfModel(shelf: rig.shelf)
        // The first is selected as the window opens.
        #expect(model.selected?.fileName == "receptors.xlsx")
        let heatmap = try #require(model.items.first { $0.fileName == "plate_7_heatmap.png" })
        model.selection = heatmap.id
        model.kind = .figure
        #expect(model.selected?.fileName == "plate_7_heatmap.png")
        model.kind = .document
        #expect(model.selected?.fileName == "qc_notes.md")
        model.kind = nil
        #expect(model.selected?.fileName == "qc_notes.md")
    }

    @Test func theArrowKeysMoveThroughAGridFourWide() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelve(9)
        await rig.index.refreshAndWait()
        let model = ShelfModel(shelf: rig.shelf)
        #expect(model.shown.map(\.fileName) == (1...9).reversed().map { "item_\($0).png" })
        func at() -> Int { model.shown.firstIndex { $0.id == model.selection } ?? -1 }
        #expect(at() == 0)
        model.move(-1, 0); model.move(0, -1)
        #expect(at() == 0)
        model.move(1, 0); model.move(1, 0)
        #expect(at() == 2)
        model.move(0, 1)
        #expect(at() == 6)
        // Down from the second row, to a row that is only partly there: the last card.
        model.move(0, 1)
        #expect(at() == 8)
        model.move(0, 1); model.move(1, 0)
        #expect(at() == 8)
        model.move(0, -1)
        #expect(at() == 4)
        model.move(0, -1)
        #expect(at() == 0)
        // Sideways runs on into the next row.
        model.move(1, 0); model.move(1, 0); model.move(1, 0); model.move(1, 0)
        #expect(at() == 4)
        model.move(-1, 0)
        #expect(at() == 3)
    }

    @Test func showShelfSelectsTheItemWhateverTheFiltersHideAndWaitsForOneNotThereYet() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        let model = ShelfModel(shelf: rig.shelf)
        model.kind = .table
        model.project = "Receptor biology"
        model.search = "xlsx"
        let target = try #require(model.items.first { $0.fileName == "z_prime_by_plate.png" })
        model.select(folder: target.folder)
        #expect(model.selection == target.id)
        #expect(model.kind == nil && model.project == nil && model.search == "")

        // An item that lands after it was asked for: chosen as soon as the folders are read.
        let landing = rig.root.appending(path: "Assay development/item_1", directoryHint: .isDirectory)
        model.select(folder: landing)
        #expect(model.selection == target.id)
        rig.science.names[Made.version(1)] = "item_1.png"
        rig.clock.date = Made.at(200)
        let outcome = await rig.shelf.add(Made.source(Made.version(1), name: "item_1.png"))
        #expect(placement(outcome)?.folder == landing)
        try await until("the new item is selected") { model.selected?.fileName == "item_1.png" }
    }

    @Test func aRequestForAFolderThatNeverComesIsDroppedAfterAWhile() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        var time = Date(timeIntervalSince1970: 1_000)
        let model = ShelfModel(shelf: rig.shelf, now: { time })
        let first = model.selection
        model.select(folder: rig.root.appending(path: "Assay development/nothing", directoryHint: .isDirectory))
        time = time.addingTimeInterval(60)
        model.kind = .figure
        model.kind = nil
        // Nothing hijacks the selection later.
        rig.science.names[Made.version(2)] = "item_2.png"
        _ = await rig.shelf.add(Made.source(Made.version(2), name: "item_2.png"))
        await rig.index.refreshAndWait()
        #expect(model.selection != nil)
        #expect(model.selected?.fileName != "nothing")
        _ = first
    }

    @Test func removingTheSelectedItemMovesToTheNextAndSaysSoWithUndo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        let model = ShelfModel(shelf: rig.shelf)
        let note = model.shown[1]
        model.selection = note.id
        model.removeSelected()
        try await until("the removal") { model.note != nil }
        #expect(model.note?.sentence == "Moved qc_notes.md to the Trash.")
        #expect(model.note?.removal != nil)
        try await until("the folders are read again") { model.items.count == 3 }
        // The next in line, not the first.
        #expect(model.selected?.fileName == "plate_7_heatmap.png")
        #expect(model.counts.all == 3 && model.counts.documents == 0)
        #expect(!rig.shelf.versions.contains(Made.notes))
        #expect(rig.trashed().count == 1)

        model.undoRemoval()
        try await until("the note is gone") { model.note == nil }
        try await until("it is back") { model.items.count == 4 }
        try await until("it is selected") { model.selected?.fileName == "qc_notes.md" }
        #expect(rig.shelf.versions.contains(Made.notes))
        #expect(rig.trashed().isEmpty)
    }

    @Test func aRemovalThatFailsSaysWhyAndOffersNoUndo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        let model = ShelfModel(shelf: rig.shelf)
        let item = model.shown[0]
        // The README changed in another app since the folders were read: it isn't ours any more.
        try Data("# Not ours\n".utf8).write(to: item.folder.appending(path: "README.md"))
        model.removeSelected()
        try await until("the sentence") { model.note != nil }
        #expect(model.note?.sentence == "Couldn\u{2019}t move receptors.xlsx to the Trash. This isn't a folder Capsid keeps.")
        #expect(model.note?.removal == nil)
        #expect(rig.trashed().isEmpty)
        #expect(model.items.count == 4)
    }

    @Test func theLineAfterARemovalFadesOnItsOwn() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        await rig.shelveTheBoardsRow()
        let model = ShelfModel(shelf: rig.shelf, noteLifetime: .milliseconds(80))
        model.removeSelected()
        try await until("the removal") { model.note != nil }
        try await until("the line fades") { model.note == nil }
        #expect(rig.trashed().count == 1)
    }

    @Test func anEmptyShelfIsSaidToBeEmptyAndNothingIsSelected() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let model = ShelfModel(shelf: rig.shelf)
        #expect(model.isEmpty && model.selection == nil && model.shown.isEmpty && model.projects.isEmpty)
        model.move(1, 0)
        #expect(model.selection == nil)
        model.removeSelected()
        #expect(model.note == nil)
    }
}
