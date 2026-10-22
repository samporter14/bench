// KeepModelTests.swift — the Keep sheet's model (Kept/KeepModel.swift) driven
// whole, on made-up reads and a scratch Kept folder under the temporary
// folder: a failed first read and a failed figure download recovered by Try
// Again; the version that went, swapped for another; an answer pinned by the
// caller, and an answer kept with a version it doesn't show; bytes that don't
// match the daemon's checksum, kept and named; a README that couldn't be
// rewritten after a Try Again, and a Cancel in the middle of one. The reads
// are fakes (nothing here talks to Claude Science); the disk is the real
// `KeptDisk` on a folder made for each test and removed after it.
import Foundation
import Testing
@testable import Bench

private enum Made {
    static let session = SessionStatus(id: "00000000-0000-4000-8000-0000000000bb", projectID: "p-2", projectName: "Assay development",
                                       title: "Plate reader QC", state: .finished, updatedAt: Date(), startedAt: nil)
    static let artifact = "bbbbbbbb-0000-4000-8000-000000000002"
    static let v1 = "aaaaaaaa-0000-4000-8000-000000000011"
    static let v2 = "aaaaaaaa-0000-4000-8000-000000000012"
    static let v3 = "aaaaaaaa-0000-4000-8000-000000000013"
    static let v4 = "aaaaaaaa-0000-4000-8000-000000000014"
    static let versions = [v1, v2, v3, v4]
    static let inputArtifact = "dddddddd-0000-4000-8000-000000000002"
    static let in1 = "cccccccc-0000-4000-8000-000000000011"
    static let in2 = "cccccccc-0000-4000-8000-000000000012"
    static let inputNames = [in1: "z_prime_by_plate.csv", in2: "plate_layout.csv"]
    static let base = Date(timeIntervalSince1970: 1_800_000_000)
    static let answer = "All plates passed except plate 7, which has an edge effect in column 12."
    static let script = "import pandas as pd\nplates = pd.read_csv(\"{{artifact:\(in1)}}\")\n"

    static func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
    static func n(_ v: String) -> Int { (versions.firstIndex(of: v) ?? 0) + 1 }
    static func figure(_ v: String) -> Data { Data("made-up figure, version \(n(v))".utf8) }
    static func table(_ v: String) -> Data { Data("plate,z_prime\n1,0.71\n# \(inputNames[v] ?? v)\n".utf8) }
    static func bytes(_ v: String) -> Data { inputNames[v] == nil ? figure(v) : table(v) }
    static func showing(_ v: String) -> ShowingMessage { ShowingMessage(i: 12, at: at(20), text: answer, how: .image, v: v) }
}

/// Claude Science, made up: four versions of a figure drawn from one or two
/// tables, and the answer that shows one of them. Each step can be made to
/// fail, a set number of times.
@MainActor
private final class Science {
    var inputs = [Made.in1]
    /// The answer the history search finds.
    var showing: ShowingMessage? = Made.showing(Made.v4)
    private(set) var showingCalls = 0
    /// The first facts reads time out, this many of them.
    var factsFailures = 0
    /// A version's download times out this many times first.
    var downloadFailures: [String: Int] = [:]
    /// A version's download brings other bytes this many times first.
    var corrupt: [String: Int] = [:]
    /// Versions that aren't there any more.
    var vanished: Set<String> = []
    /// A download answered here first; nil goes on as usual.
    var onDownload: (@MainActor (String) -> ShelfTransferResult?)?
    private(set) var downloads: [String] = []

    func search() -> ShowingRead {
        showingCalls += 1
        return showing.map { .found($0) } ?? .notFound
    }

    func read(_ read: ArtifactRead) -> ShelfTransferResult {
        switch read {
        case .facts(let v):
            if factsFailures > 0 { factsFailures -= 1; return .timedOut }
            let sha = KeptDisk.sha256(of: Made.bytes(v))
            if let name = Made.inputNames[v] {
                return .answered(.facts(ArtifactFacts(v: v, a: Made.inputArtifact, n: 1, name: name, mime: "text/csv",
                                                      size: Made.table(v).count, at: Made.at(0), sha: sha, isUpload: false,
                                                      code: nil, codeCut: false, environment: nil)))
            }
            guard Made.versions.contains(v) else { return .answered(.missing) }
            return .answered(.facts(ArtifactFacts(v: v, a: Made.artifact, n: Made.n(v), name: "z_prime.png", mime: "image/png",
                                                  size: Made.figure(v).count, at: Made.at(Double(Made.n(v))), sha: sha,
                                                  isUpload: false, code: nil, codeCut: false, environment: nil)))
        case .versions:
            return .answered(.versions(Made.versions.map {
                ArtifactVersion(v: $0, n: Made.n($0), frame: Made.session.id, mime: "image/png", size: Made.figure($0).count,
                                at: Made.at(Double(Made.n($0))), parent: nil)
            }))
        case .lineage(let v):
            return .answered(.lineage(ArtifactLineage(
                v: v, code: Made.script, codeCut: false, description: nil, language: "python", pending: false,
                unavailableModel: nil, unavailableReason: nil, hasCells: true, hasEnvironment: true, mappingStatus: "complete",
                inputs: inputs.map { LineageInput(v: $0, a: Made.inputArtifact, name: Made.inputNames[$0], file: nil, how: "runtime", inferred: false) })))
        case .download(let v):
            downloads.append(v)
            if let answer = onDownload?(v) { return answer }
            if let left = downloadFailures[v], left > 0 { downloadFailures[v] = left - 1; return .timedOut }
            if vanished.contains(v) { return .answered(.missing) }
            if let left = corrupt[v], left > 0 { corrupt[v] = left - 1; return .answered(.bytes(Data("not these bytes".utf8))) }
            return .answered(.bytes(Made.bytes(v)))
        case .thumb, .text, .list:
            return .answered(.unreadable)
        }
    }
}

/// A scratch Kept folder, a defaults suite of its own and the made-up reads.
@MainActor
private final class Rig {
    let science = Science()
    let scratch: URL
    let root: URL
    let disk: KeptDisk
    private let suite = "capsid-tests-keep-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-keep-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        self.scratch = scratch
        self.root = root
        disk = KeptDisk(root: { root })
        defaults = UserDefaults(suiteName: suite)!
    }

    /// Where the made-up session's keeps go: its project's name.
    var collection: URL { root.appending(path: "Assay development", directoryHint: .isDirectory) }

    func model(entry v: String = Made.v4, pinned: KeepPinnedAnswer? = nil) -> KeepModel {
        let entry = ArtifactEntry(version: v, artifact: Made.artifact, name: "z_prime.png", mime: "image/png",
                                  size: Made.figure(v).count, at: Made.at(Double(Made.n(v))))
        let science = self.science, root = self.root
        let dependencies = KeepDependencies(
            read: { science.read($0) },
            showing: { _, _, _ in science.search() },
            lastAnswer: { _ in nil },
            thumbnails: ShelfThumbnails(),
            disk: disk,
            defaults: defaults,
            root: { root },
            scienceVersion: { "0.1.70" },
            capsidVersion: "1.0",
            now: { Made.at(100) },
            didKeep: { _ in })
        return KeepModel(subject: KeepSubject(session: Made.session, entry: entry, pinned: pinned), dependencies: dependencies)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        defaults.removePersistentDomain(forName: suite)
    }
}

private struct StillWaiting: Error {}

/// Waits, up to five seconds, for the model to get there.
@MainActor
private func until(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Still waiting: \(what)")
    throw StillWaiting()
}

private func names(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

private func exists(_ folder: URL, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: folder.appending(path: path, directoryHint: .notDirectory).path)
}

@MainActor
private extension KeepModel {
    /// A version is chosen and its provenance read.
    var settled: Bool { !readingProvenance && plan != nil }
    var isReady: Bool { phase == .ready && settled }
    var failure: (sentence: String, retry: KeepRetry?)? {
        if case .failed(let sentence, let retry) = phase { return (sentence, retry) }
        return nil
    }
    var keptOutcome: KeepOutcome? {
        if case .kept(let outcome) = phase { return outcome }
        return nil
    }
    var partialOutcome: KeepOutcome? {
        if case .partial(let outcome) = phase { return outcome }
        return nil
    }
    func row(_ kind: KeepRowKind) -> KeepRow? { rows.first { $0.kind == kind } }
}

// MARK: A. Try Again after a failure

@MainActor
struct KeepTryAgainTests {
    @Test func aFirstReadThatFailedIsReadAgainFromTheStart() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.factsFailures = 1
        let model = rig.model()
        model.open()
        try await until("the first read fails") { model.failure != nil }
        #expect(model.failure?.retry == .load)
        #expect(model.failure?.sentence == ShelfFailure.timedOut.sentence)
        #expect(model.canTryAgain)
        #expect(!model.canKeep)

        model.tryAgain()
        #expect(model.phase == .reading)
        try await until("the sheet is filled") { model.isReady }
        #expect(model.tiles.map(\.n) == [1, 2, 3, 4])
        #expect(model.choices.version == Made.v4)
        let plan = try #require(model.plan)
        #expect(plan.figure.version == Made.v4)
        #expect(plan.files.map(\.relativePath) == ["data/z_prime_by_plate.csv", "code/z_prime.py"])
        #expect(model.canKeep)
    }

    @Test func aFigureDownloadThatFailedIsKeptAgainIntoOneFolder() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadFailures[Made.v4] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        #expect(model.failure?.retry == .keep)
        #expect(model.failure?.sentence == ShelfFailure.timedOut.sentence)
        // Nothing landed, and the hidden folder it was being built in is gone.
        #expect(names(rig.collection).isEmpty)
        #expect(model.canTryAgain)

        model.tryAgain()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3 && outcome.total == 3)
        // One folder, under the plain name: the first attempt left nothing behind.
        #expect(names(rig.collection) == ["z_prime"])
        #expect(names(outcome.folder) == ["README.md", "code", "data", "z_prime.png"])
        #expect(rig.science.downloads.filter { $0 == Made.v4 }.count == 2)
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.figure.version == Made.v4)
        #expect(back.record.figure.sha256 == KeptDisk.sha256(of: Made.figure(Made.v4)))
        #expect(back.record.missing.isEmpty)
    }

    @Test func aVersionThatWentCanBeSwappedForAnotherAndKept() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.vanished = [Made.v4]
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        #expect(model.failure?.retry == nil)
        #expect(model.failure?.sentence.hasPrefix("Version 4 isn\u{2019}t in Claude Science any more, so nothing was kept.") == true)
        #expect(model.tiles.first { $0.v == Made.v4 }?.gone == true)
        // Trying the same version again can't help; another version can be kept.
        #expect(!model.canTryAgain)
        #expect(!model.canKeep)
        model.choose(Made.v3)
        try await until("version 3 is read") { model.settled }
        #expect(model.canKeep)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.figure.version == Made.v3)
        #expect(names(rig.collection) == ["z_prime"])
    }
}

// MARK: B. Which answer goes with which version

@MainActor
struct KeepPinnedAnswerTests {
    @Test func aPinnedAnswerPicksItsVersionAndIsNeverSearchedFor() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // A newer answer shows version 4; the figure was pressed in the answer about version 2.
        rig.science.showing = Made.showing(Made.v4)
        let pinned = KeepPinnedAnswer(text: "Version 2 leaves plate 7 in, edge effect and all.", at: Made.at(3))
        let model = rig.model(entry: Made.v2, pinned: pinned)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(rig.science.showingCalls == 0)
        #expect(model.choices.version == Made.v2)
        #expect(model.sources.showing?.v == Made.v2)
        #expect(model.sources.showing?.text == pinned.text)
        #expect(model.sources.showing?.at == pinned.at)
        #expect(model.tiles.first { $0.v == Made.v2 }?.inAnswer == true)
        #expect(model.tiles.first { $0.v == Made.v4 }?.inAnswer == false)
        let answer = try #require(model.row(.answer))
        #expect(answer.available && answer.onByDefault)
        #expect(answer.detail.hasPrefix("\u{201C}\(pinned.text)\u{201D}"))
        #expect(model.isOn(.answer))
        let plan = try #require(model.plan)
        #expect(plan.figure.version == Made.v2)
        #expect(plan.answer?.text == pinned.text)
        #expect(plan.answerShows == nil)

        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let back = try await rig.disk.readme(at: try #require(model.keptOutcome).folder)
        #expect(back.record.figure.version == Made.v2)
        #expect(back.record.answerShowsVersion == nil)
        #expect(back.text.claudeSaid == pinned.text)

        // Without a pinned answer, the search finds the newer one and its version is chosen.
        let searched = rig.model(entry: Made.v2)
        searched.open()
        try await until("the sheet is filled") { searched.isReady }
        #expect(rig.science.showingCalls == 1)
        #expect(searched.choices.version == Made.v4)
    }

    @Test func anotherVersionThanTheAnswersSaysSoAndLeavesTheAnswerOff() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.showing = Made.showing(Made.v3)
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.choices.version == Made.v3)
        let quoted = try #require(model.row(.answer))
        #expect(quoted.onByDefault && quoted.detail.hasPrefix("\u{201C}All plates passed"))
        #expect(model.isOn(.answer))

        // Version 4: the answer is about version 3, and says so.
        model.choose(Made.v4)
        try await until("version 4 is read") { model.settled }
        let other = try #require(model.row(.answer))
        #expect(other.detail == "Claude\u{2019}s answer shows version 3, not this one.")
        #expect(other.available && !other.onByDefault)
        #expect(!model.isOn(.answer))
        #expect(model.plan?.answer == nil)
        #expect(model.plan?.answerShows == nil)

        // Back to version 3: as before.
        model.choose(Made.v3)
        try await until("version 3 is read") { model.settled }
        let again = try #require(model.row(.answer))
        #expect(again == quoted)
        #expect(model.isOn(.answer))
        #expect(model.plan?.answer?.text == Made.answer)
        #expect(model.plan?.answerShows == nil)

        // Version 4 with the answer ticked anyway: the README says which version it shows.
        model.choose(Made.v4)
        try await until("version 4 is read") { model.settled }
        model.toggle(.answer, true)
        let plan = try #require(model.plan)
        #expect(plan.answer?.text == Made.answer)
        #expect(plan.answerShows == Made.v3)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let folder = try #require(model.keptOutcome).folder
        let back = try await rig.disk.readme(at: folder)
        #expect(back.record.figure.version == Made.v4)
        #expect(back.record.answerShowsVersion == 3)
        #expect(back.text.claudeSaid == Made.answer)
        #expect(back.text.attribution.hasSuffix("That answer shows version 3, not this one."))
        #expect(back.markdown.contains("\nanswer_shows_version: 3\nfiles:\n"))
    }
}

// MARK: C. Bytes that don't match the checksum

@MainActor
struct KeepChecksumTests {
    private static let other = Data("not these bytes".utf8)

    @Test func aFigureWhoseBytesDontMatchIsKeptAndTheSheetSaysSo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.corrupt[Made.v4] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        let expected = KeptDisk.sha256(of: Made.figure(Made.v4))
        #expect(model.plan?.figure.sha == expected)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        // Kept, every file, but not silently: the sheet stays open with the sentence until Done.
        #expect(outcome.isComplete && outcome.kept == 3)
        #expect(!outcome.closesSheet)
        #expect(model.shownOutcome == outcome)
        #expect(outcome.mismatched.map(\.path) == ["z_prime.png"])
        #expect(outcome.mismatched.first?.expectedSha256 == expected)
        #expect(outcome.mismatched.first?.sha256 == KeptDisk.sha256(of: Self.other))
        #expect(model.outcomeSentence == "Kept 3 files. z_prime.png doesn\u{2019}t match Claude Science\u{2019}s checksum; see README.md before you use it.")
        // The bytes that came are the ones written.
        let figure = try Data(contentsOf: outcome.folder.appending(path: "z_prime.png", directoryHint: .notDirectory))
        #expect(figure == Self.other)
        // The README has both checksums and says it in a sentence.
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.figure.expectedSha256 == expected)
        #expect(back.record.figure.sha256 == KeptDisk.sha256(of: Self.other))
        #expect(back.record.missing.isEmpty)
        #expect(back.markdown.contains("sha256: \"\(KeptDisk.sha256(of: Self.other))\", expected_sha256: \"\(expected)\", bytes: \(Self.other.count) }"))
        #expect(back.markdown.contains("## Checksums\n\n- z_prime.png doesn\u{2019}t match Claude Science\u{2019}s checksum for this version (expected \(expected.prefix(8))\u{2026}, got \(KeptDisk.sha256(of: Self.other).prefix(8))\u{2026}). It may be a reference file that changed since; check it before you use it.\n"))
    }

    @Test func aDataFileWhoseBytesDontMatchIsKeptWithTheWarning() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.corrupt[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        // Not missing: kept, and named.
        #expect(outcome.missing.isEmpty && outcome.kept == 3 && outcome.total == 3)
        #expect(!outcome.closesSheet)
        #expect(outcome.mismatched.map(\.path) == ["data/z_prime_by_plate.csv"])
        #expect(exists(outcome.folder, "data/z_prime_by_plate.csv"))
        #expect(model.fate(of: .data)?.text == "Kept, but it doesn\u{2019}t match Claude Science\u{2019}s checksum.")
        #expect(model.fate(of: .data)?.isProblem == true)
        #expect(model.fate(of: .code)?.text == "Kept")
        #expect(model.outcomeSentence == "Kept 3 files. data/z_prime_by_plate.csv doesn\u{2019}t match Claude Science\u{2019}s checksum; see README.md before you use it.")
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.missing.isEmpty)
        let data = try #require(back.record.files.first { $0.path == "data/z_prime_by_plate.csv" })
        #expect(data.expectedSha256 == KeptDisk.sha256(of: Made.table(Made.in1)))
        #expect(data.sha256 == KeptDisk.sha256(of: Self.other))
        #expect(back.record.figure.expectedSha256 == nil)
        #expect(back.markdown.contains("- data/z_prime_by_plate.csv doesn\u{2019}t match Claude Science\u{2019}s checksum for this version"))
    }

    @Test func aFileThatLandsInTryAgainWithoutItsChecksumIsNamedToo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // The table times out once, then comes with other bytes.
        rig.science.downloadFailures[Made.in1] = 1
        rig.science.corrupt[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        #expect(model.partialOutcome?.mismatched.isEmpty == true)
        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.missing.isEmpty)
        #expect(!outcome.closesSheet)
        #expect(outcome.mismatched.map(\.path) == ["data/z_prime_by_plate.csv"])
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.files.first { $0.path == "data/z_prime_by_plate.csv" }?.expectedSha256
            == KeptDisk.sha256(of: Made.table(Made.in1)))
        #expect(back.markdown.contains("\n## Checksums\n"))
    }

    @Test func bytesThatMatchCloseTheSheetAsBefore() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.closesSheet && outcome.mismatched.isEmpty)
        #expect(model.shownOutcome == nil)
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(KeptReadme.mismatched(back.record).isEmpty)
        #expect(!back.markdown.contains("## Checksums"))
        #expect(!back.markdown.contains("expected_sha256"))
    }
}

// MARK: D. The README is part of a Try Again

@MainActor
struct KeepRetryRecordTests {
    @Test func aReadmeThatCantBeRewrittenKeepsTheSheetOpenUntilItIs() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadFailures[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let first = try #require(model.partialOutcome)
        #expect(first.missing.map(\.name) == ["z_prime_by_plate.csv"])

        // README.md can't be replaced (locked in Finder, say); the folder takes new files.
        let readme = first.folder.appending(path: "README.md", directoryHint: .notDirectory).path
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: readme)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: readme) }
        model.retry()
        try await until("the retry ends") { model.partialOutcome?.recordFailed != nil }
        let stuck = try #require(model.partialOutcome)
        #expect(stuck.missing.isEmpty)
        #expect(stuck.kept == 3 && stuck.total == 3)
        #expect(!stuck.isComplete)
        #expect(model.keptOutcome == nil)
        #expect(KeepRules.outcomeSentence(stuck).hasPrefix("Kept 3 files. The files landed, but README.md couldn\u{2019}t be updated to list them. "))
        #expect(exists(first.folder, "data/z_prime_by_plate.csv"))
        // The README still says what it said, and the sheet says it does.
        let stale = try await rig.disk.readme(at: first.folder)
        #expect(stale.record.missing.map(\.name) == ["z_prime_by_plate.csv"])

        // It can be replaced again: Try Again only rewrites it.
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: readme)
        let downloads = rig.science.downloads.count
        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let done = try #require(model.keptOutcome)
        #expect(done.isComplete && done.kept == 3)
        #expect(rig.science.downloads.count == downloads)
        let back = try await rig.disk.readme(at: first.folder)
        #expect(back.record.missing.isEmpty)
        #expect(back.record.files.map(\.path) == ["code/z_prime.py", "data/z_prime_by_plate.csv"])
        #expect(back.record.files.last?.sha256 == KeptDisk.sha256(of: Made.table(Made.in1)))
    }

    @Test func aCancelInTheMiddleOfTryAgainRecordsWhatLanded() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.inputs = [Made.in1, Made.in2]
        rig.science.downloadFailures = [Made.in1: 1, Made.in2: 1]
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let first = try #require(model.partialOutcome)
        #expect(first.missing.map(\.name) == ["z_prime_by_plate.csv", "plate_layout.csv"])
        #expect(first.kept == 2 && first.total == 4)

        // The first table lands; Cancel is pressed while the second is coming.
        rig.science.onDownload = { [weak model] v in
            guard v == Made.in2 else { return nil }
            model?.cancel()
            return .cancelled
        }
        model.retry()
        try await until("the retry stops") { model.partialOutcome.map { $0.missing.count == 1 } == true }
        let after = try #require(model.partialOutcome)
        #expect(after.missing.map(\.name) == ["plate_layout.csv"])
        #expect(after.kept == 3)
        #expect(after.recordFailed == nil)
        #expect(exists(first.folder, "data/z_prime_by_plate.csv"))
        #expect(!exists(first.folder, "data/plate_layout.csv"))
        // The README agrees with the folder.
        let back = try await rig.disk.readme(at: first.folder)
        #expect(back.record.missing == after.missing)
        #expect(back.record.files.map(\.path).contains("data/z_prime_by_plate.csv"))
        #expect(!back.record.files.map(\.path).contains("data/plate_layout.csv"))
    }
}
