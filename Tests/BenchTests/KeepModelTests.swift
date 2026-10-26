// KeepModelTests.swift — the Keep sheet's model (Kept/KeepModel.swift) driven
// whole, on made-up reads and a scratch Kept folder under the temporary
// folder: a failed first read and a failed figure download recovered by Try
// Again; the version that went, swapped for another; an answer pinned by the
// caller, and an answer kept with a version it doesn't show; bytes that don't
// match the daemon's checksum, kept and named; a README that couldn't be
// rewritten after a Try Again, and a Cancel in the middle of one; a README a
// person added sections to, kept as it is through a Try Again, and left alone
// when it was edited while Try Again worked; a Cancel after the last copy and
// while the version is asked (nothing published), and one refused once the
// folder is being put in place. The reads
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

    /// Claude's legend files, as the answer's history lists them (since 1.0.6): a legend for three figures, and one that
    /// shares the figure's name.
    static let legends = "ffffffff-0000-4000-8000-000000000021"
    static let sibling = "ffffffff-0000-4000-8000-000000000022"
    static let legendsText = """
        # Figure legends

        **plate_map.png** Eight plates, sixteen rows.

        **z_prime.png** Z\u{2032} by plate. Plate 7 is the low bar, at 0.41.

        **edge_effect.png** Column 12 reads low.
        """
    /// What the figure's own part comes to.
    static let legendPart = "**z_prime.png** Z\u{2032} by plate. Plate 7 is the low bar, at 0.41."
    static let siblingText = "Z\u{2032} by plate, one dot for each plate.\n"
    static func historyFile(_ v: String, _ name: String, _ text: String) -> HistoryFile {
        HistoryFile(v: v, a: "eeeeeeee-0000-4000-8000-0000000000" + v.suffix(2), name: name,
                    kind: ArtifactKind.classify(name: name, mime: nil), size: text.utf8.count)
    }
    static var legendsFile: HistoryFile { historyFile(legends, "FIGURE_LEGENDS_final.md", legendsText) }
    static var siblingFile: HistoryFile { historyFile(sibling, "z_prime.md", siblingText) }
}

/// Claude Science, made up: four versions of a figure drawn from one or two
/// tables, and the answer that shows one of them. Each step can be made to
/// fail, a set number of times.
@MainActor
private final class Science {
    var inputs = [Made.in1]
    /// The inputs a version's provenance lists, when they aren't `inputs`.
    var inputsByVersion: [String: [String]] = [:]
    /// The versions whose provenance was read, in order.
    private(set) var lineageReads: [String] = []
    /// The first provenance reads say Claude Science is still working it out (no
    /// inputs, no script yet), this many of them.
    var pendingLineage = 0
    /// A provenance read waits here while `holdLineage`; `releaseLineage` lets them go.
    var holdLineage = false
    private var lineageWaiters: [CheckedContinuation<Void, Never>] = []
    /// Settles (the wait for a choice to stay) asked for, held while `holdSettles`.
    private(set) var settles = 0
    var holdSettles = false
    private var settleWaiters: [CheckedContinuation<Void, Never>] = []
    /// The answer the history search finds.
    var showing: ShowingMessage? = Made.showing(Made.v4)
    private(set) var showingCalls = 0
    /// Claude Science's version, asked once per keep: held while `holdVersion`, and `onVersion` runs as it is asked.
    var holdVersion = false
    var onVersion: (@MainActor () -> Void)?
    private(set) var versionAsks = 0
    private var versionWaiters: [CheckedContinuation<Void, Never>] = []
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
    /// The figure's file name now, and what the inputs are called.
    var figureName = "z_prime.png"
    var inputNames = Made.inputNames
    /// A version's size as the listing and the facts say it (the bytes stay small).
    var sizes: [String: Int] = [:]
    /// Versions the artifact's list leaves out, though the daemon knows them.
    var unlisted: Set<String> = []
    /// The session's last answer, the fallback.
    var last: KeepAnswer?
    /// The files of the answer that shows the version (`answerFiles`), and the rows they were asked for; nil can't be read.
    var answerFiles: [HistoryFile]? = []
    private(set) var answerFileAsks: [Int] = []
    /// Bytes for files that aren't the figure or its inputs (Claude's legend files), by version.
    var extraBytes: [String: Data] = [:]
    /// The versions each search was asked about, in order.
    private(set) var searches: [[String]] = []
    /// A search finds the answer only if it shows one of the versions asked about,
    /// as the real reader does; off, it answers whatever it was asked.
    var searchMatchesVersions = true

    func files(row: Int) -> [HistoryFile]? {
        answerFileAsks.append(row)
        return answerFiles
    }

    func search(_ versions: [String]? = nil) -> ShowingRead {
        showingCalls += 1
        searches.append(versions ?? [])
        guard let showing, !searchMatchesVersions || versions?.contains(showing.v) != false else { return .notFound }
        return .found(showing)
    }

    /// The read as the sheet makes it: a provenance read can be held.
    func readHeld(_ read: ArtifactRead) async -> ShelfTransferResult {
        if case .lineage = read, holdLineage {
            await withCheckedContinuation { lineageWaiters.append($0) }
        }
        return self.read(read)
    }

    func version() async -> String? {
        versionAsks += 1
        onVersion?()
        if holdVersion { await withCheckedContinuation { versionWaiters.append($0) } }
        return "0.1.70"
    }

    func releaseVersion() {
        holdVersion = false
        let waiting = versionWaiters
        versionWaiters = []
        for waiter in waiting { waiter.resume() }
    }

    func releaseLineage() {
        holdLineage = false
        let waiting = lineageWaiters
        lineageWaiters = []
        for waiter in waiting { waiter.resume() }
    }

    /// The wait for a choice to stay: at once, unless held.
    func settle() async {
        settles += 1
        guard holdSettles else { return }
        await withCheckedContinuation { settleWaiters.append($0) }
    }

    func releaseSettles() {
        holdSettles = false
        let waiting = settleWaiters
        settleWaiters = []
        for waiter in waiting { waiter.resume() }
    }

    func read(_ read: ArtifactRead) -> ShelfTransferResult {
        switch read {
        case .facts(let v):
            if factsFailures > 0 { factsFailures -= 1; return .timedOut }
            let sha = KeptDisk.sha256(of: Made.bytes(v))
            if let name = inputNames[v] {
                return .answered(.facts(ArtifactFacts(v: v, a: Made.inputArtifact, n: 1, name: name, mime: "text/csv",
                                                      size: Made.table(v).count, at: Made.at(0), sha: sha, isUpload: false,
                                                      code: nil, codeCut: false, environment: nil)))
            }
            guard Made.versions.contains(v) else { return .answered(.missing) }
            return .answered(.facts(ArtifactFacts(v: v, a: Made.artifact, n: Made.n(v), name: figureName, mime: "image/png",
                                                  size: sizes[v] ?? Made.figure(v).count, at: Made.at(Double(Made.n(v))), sha: sha,
                                                  isUpload: false, code: nil, codeCut: false, environment: nil)))
        case .versions:
            return .answered(.versions(Made.versions.filter { !unlisted.contains($0) }.map {
                ArtifactVersion(v: $0, n: Made.n($0), frame: Made.session.id, mime: "image/png", size: sizes[$0] ?? Made.figure($0).count,
                                at: Made.at(Double(Made.n($0))), parent: nil)
            }))
        case .lineage(let v):
            lineageReads.append(v)
            if pendingLineage > 0 {
                pendingLineage -= 1
                return .answered(.lineage(ArtifactLineage(
                    v: v, code: nil, codeCut: false, description: nil, language: "python", pending: true,
                    unavailableModel: nil, unavailableReason: nil, hasCells: true, hasEnvironment: true, mappingStatus: "pending",
                    inputs: [])))
            }
            return .answered(.lineage(ArtifactLineage(
                v: v, code: Made.script, codeCut: false, description: nil, language: "python", pending: false,
                unavailableModel: nil, unavailableReason: nil, hasCells: true, hasEnvironment: true, mappingStatus: "complete",
                inputs: (inputsByVersion[v] ?? inputs).map { LineageInput(v: $0, a: Made.inputArtifact, name: inputNames[$0], file: nil, how: "runtime", inferred: false) })))
        case .download(let v):
            downloads.append(v)
            if let answer = onDownload?(v) { return answer }
            if let extra = extraBytes[v] {
                if let left = downloadFailures[v], left > 0 { downloadFailures[v] = left - 1; return .timedOut }
                return .answered(.bytes(extra))
            }
            if let left = downloadFailures[v], left > 0 { downloadFailures[v] = left - 1; return .timedOut }
            if vanished.contains(v) { return .answered(.missing) }
            if let left = corrupt[v], left > 0 { corrupt[v] = left - 1; return .answered(.bytes(Data("not these bytes".utf8))) }
            return .answered(.bytes(Made.bytes(v)))
        case .thumb, .text, .list:
            return .answered(.unreadable)
        }
    }
}

/// Disk calls that can be held back, as a dropped volume holds them, and let
/// go late. Calls run at once until `holding` is set.
private final class HeldCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [KeptDisk.Work] = []
    private var hold = false
    /// Calls still to go through before the next one is held.
    private var allowed: Int?

    func holding(_ on: Bool) { lock.withLock { hold = on } }
    /// The next `calls` calls run; the one after them, and every later one, is held.
    func holdAfter(_ calls: Int) { lock.withLock { allowed = calls } }
    var count: Int { lock.withLock { held.count } }

    func run(_ work: @escaping KeptDisk.Work) {
        let held = lock.withLock { () -> Bool in
            if let left = allowed {
                if left == 0 { allowed = nil; hold = true } else { allowed = left - 1 }
            }
            return hold
        }
        if held { lock.withLock { self.held.append(work) } } else { work() }
    }

    /// Lets the held calls finish, late, in the order they came.
    func release() {
        let pending = lock.withLock { let all = held; held = []; return all }
        for work in pending { work() }
    }
}

/// A scratch Kept folder, a defaults suite of its own and the made-up reads.
@MainActor
private final class Rig {
    let science = Science()
    let scratch: URL
    let root: URL
    let disk: KeptDisk
    private let settings = ScratchDefaults.make(prefix: "capsid-tests-keep")
    var defaults: UserDefaults { settings.defaults }
    /// The keeps the Results window was told about (`didKeep`).
    private(set) var kept: [KeepOutcome] = []
    /// The sheet's steps as it would log them (`note`).
    private(set) var notes: [String] = []
    /// The model `model()` made last, and whether Keep was on at each wait for a pending provenance.
    private weak var current: KeepModel?
    private(set) var keepOnWhilePending: [Bool] = []

    /// `hold` makes the disk one that can stop answering, as a dropped volume does:
    /// its held calls time out at once, unless `patient`, which waits for them.
    init(hold: HeldCalls? = nil, patient: Bool = false) throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "capsid-tests-keep-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let root = scratch.appending(path: "Kept", directoryHint: .isDirectory)
        self.scratch = scratch
        self.root = root
        if let hold {
            if patient {
                disk = KeptDisk(root: { root }, wait: { try? await Task.sleep(for: $0) }, run: { hold.run($0) })
            } else {
                disk = KeptDisk(root: { root }, wait: { _ in }, run: { hold.run($0) })
            }
        } else {
            disk = KeptDisk(root: { root })
        }
    }

    /// Where the made-up session's keeps go: its project's name.
    var collection: URL { root.appending(path: "Assay development", directoryHint: .isDirectory) }

    func model(entry v: String = Made.v4, pinned: KeepPinnedAnswer? = nil, selectsItsVersion: Bool = false) -> KeepModel {
        let entry = ArtifactEntry(version: v, artifact: Made.artifact, name: "z_prime.png", mime: "image/png",
                                  size: Made.figure(v).count, at: Made.at(Double(Made.n(v))))
        let science = self.science, root = self.root
        let dependencies = KeepDependencies(
            read: { await science.readHeld($0) },
            showing: { _, versions, _ in science.search(versions) },
            lastAnswer: { _ in science.last },
            thumbnails: ShelfThumbnails(),
            disk: disk,
            defaults: defaults,
            root: { root },
            scienceVersion: { await science.version() },
            capsidVersion: "1.0",
            now: { Made.at(100) },
            didKeep: { [self] outcome in kept.append(outcome) },
            settle: { _ in await science.settle() },
            note: { [self] line in notes.append(line) },
            recheck: { [self] _ in keepOnWhilePending.append(current?.canKeep ?? true) },
            answerFiles: { _, row in science.files(row: row) })
        let model = KeepModel(subject: KeepSubject(session: Made.session, entry: entry, pinned: pinned, selectsItsVersion: selectsItsVersion),
                              dependencies: dependencies)
        current = model
        return model
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        settings.discard()
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

// MARK: D. A version the user picked stays picked

@MainActor
struct KeepPickedVersionModelTests {
    @Test func aVersionClickedInTheConversationStaysSelectedWhileALaterAnswerShowsAnother() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // The later answer shows version 2; version 1 was clicked. Even a reader that
        // hands back that answer whatever it is asked cannot move the pick.
        rig.science.showing = Made.showing(Made.v2)
        rig.science.searchMatchesVersions = false
        let model = rig.model(entry: Made.v1, selectsItsVersion: true)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.choices.version == Made.v1)
        #expect(model.plan?.figure.version == Made.v1)
        // What that answer is about is said, and the answer is left off.
        #expect(model.tiles.first { $0.v == Made.v2 }?.inAnswer == true)
        let answer = try #require(model.row(.answer))
        #expect(answer.detail == "Claude\u{2019}s answer shows version 2, not this one.")
        #expect(answer.available && !answer.onByDefault)
        #expect(model.plan?.answer == nil)

        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let back = try await rig.disk.readme(at: try #require(model.keptOutcome).folder)
        #expect(back.record.figure.version == Made.v1)
        #expect(back.record.figure.sha256 == KeptDisk.sha256(of: Made.figure(Made.v1)))
    }

    @Test func theAnswerLookedForIsTheOneThatShowsTheClickedVersion() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // A newer answer shows version 2; an answer that shows version 1 is not in the page's reach: unknown.
        rig.science.showing = Made.showing(Made.v2)
        let model = rig.model(entry: Made.v1, selectsItsVersion: true)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(rig.science.searches == [[Made.v1]])
        // Its answer is unknown, and the version is still the one clicked, not the newest.
        #expect(model.choices.version == Made.v1)
        #expect(model.sources.showing == nil)
        let none = try #require(model.row(.answer))
        #expect(!none.available)
        #expect(none.detail.hasPrefix("Capsid couldn\u{2019}t find the answer that showed this version."))
        #expect(model.versionSentence.hasPrefix("Version 1 of 4, from "))
        #expect(model.plan?.answer == nil)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let back = try await rig.disk.readme(at: try #require(model.keptOutcome).folder)
        #expect(back.record.figure.version == Made.v1)
        #expect(back.record.answerShowsVersion == nil)
    }

    @Test func withNoAnswerForItTheSessionsLastAnswerIsOfferedAndNeverAnotherVersion() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.last = KeepAnswer(text: "The eleven plates are unchanged.", at: Made.at(30), how: nil, isFallback: true)
        let model = rig.model(entry: Made.v2, selectsItsVersion: true)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.choices.version == Made.v2)
        let row = try #require(model.row(.answer))
        #expect(row.title == "What Claude said last" && row.available)
        #expect(model.plan?.answer?.isFallback == true)
    }

    @Test func whenItsAnswerIsFoundItIsKeptWithItLikeAnyOther() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.showing = Made.showing(Made.v1)
        let model = rig.model(entry: Made.v1, selectsItsVersion: true)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(rig.science.searches == [[Made.v1]])
        #expect(model.choices.version == Made.v1)
        #expect(model.tiles.first { $0.v == Made.v1 }?.inAnswer == true)
        let answer = try #require(model.row(.answer))
        #expect(answer.available && answer.onByDefault && answer.detail.hasPrefix("\u{201C}All plates passed"))
        #expect(model.plan?.answer?.text == Made.answer)
        #expect(model.plan?.answerShows == nil)
    }

    @Test func withoutAPickItFollowsTheNewestAnswerAsBefore() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.showing = Made.showing(Made.v2)
        let model = rig.model(entry: Made.v1)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        // Results' entry is the latest version project-wide, never the user's pick: every version is searched.
        #expect(rig.science.searches == [Made.versions])
        #expect(model.choices.version == Made.v2)
    }

    @Test func aPickTheArtifactsListLeftOutIsInTheStripAndSelected() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.unlisted = [Made.v1]
        let model = rig.model(entry: Made.v1, selectsItsVersion: true)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.tiles.map(\.n) == [1, 2, 3, 4])
        #expect(model.choices.version == Made.v1)
        #expect(model.plan?.figure.version == Made.v1)
    }
}

// MARK: E. A folder is its figure

/// Something done once, from inside a made-up read.
@MainActor
private final class Once {
    private var done = false
    func take() -> Bool {
        defer { done = true }
        return !done
    }
}

@MainActor
struct KeepFigureFirstModelTests {
    @Test func aFigureCalledReadmeIsKeptBesideCapsidsOwnReadme() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.figureName = "README.md"
        rig.science.inputNames = [Made.in1: "readme.md", Made.in2: "plate_layout.csv"]
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.plan?.figure.name == "README 2.md")
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3 && outcome.total == 3)
        #expect(names(outcome.folder) == ["README 2.md", "README.md", "code", "data"])
        // README.md is Capsid's, and says where everything is.
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.markdown.contains("capsid_kept: 1"))
        #expect(back.record.figure.path == "README 2.md")
        #expect(back.record.figure.sha256 == KeptDisk.sha256(of: Made.figure(Made.v4)))
        #expect(Set(back.record.files.map(\.path)) == ["data/readme 3.md", "code/README.py"])
        #expect(back.record.missing.isEmpty)
        let figure = try Data(contentsOf: outcome.folder.appending(path: "README 2.md", directoryHint: .notDirectory))
        #expect(figure == Made.figure(Made.v4))
        let script = try String(contentsOf: outcome.folder.appending(path: "code/README.py", directoryHint: .notDirectory), encoding: .utf8)
        #expect(script.contains("../data/readme 3.md"))
        #expect(try await rig.disk.scan().count == 1)
    }

    @Test func aFigureCalledDataDoesntTakeTheDataFoldersPlace() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.figureName = "data"
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3 && outcome.total == 3)
        #expect(names(outcome.folder) == ["README.md", "code", "data", "data 2"])
        #expect(exists(outcome.folder, "data/z_prime_by_plate.csv"))
        #expect(try await rig.disk.readme(at: outcome.folder).record.figure.path == "data 2")
    }

    @Test func aFigureOverTheCapIsSaidBeforeKeepingAndNothingIsMade() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.sizes[Made.v4] = KeepRules.cap + 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(!model.canKeep)
        #expect(model.versionSentence.hasSuffix("it\u{2019}s over the 8 MB Capsid can copy here, so this version can\u{2019}t be kept."))
        model.keep()
        #expect(model.phase == .ready)
        #expect(rig.science.downloads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.root.path))

        // Another version can be kept, and reads as it always did.
        model.choose(Made.v3)
        try await until("version 3 is read") { model.settled }
        #expect(model.canKeep)
        #expect(!model.versionSentence.contains("8 MB"))
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        #expect(try #require(model.keptOutcome).isComplete)
        #expect(names(rig.collection) == ["z_prime"])
    }

    @Test func aFigureTheDaemonCallsTooBigEndsTheKeepWithNothingMadeAndRetryHasNothingToDo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // Its listing didn't say how big it is; the read does.
        rig.science.onDownload = { v in v == Made.v4 ? .answered(.tooBig) : nil }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.canKeep)
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        #expect(model.failure?.sentence == KeepRules.figureTooBig("z_prime.png"))
        #expect(model.failure?.sentence.contains("nothing was kept") == true)
        #expect(model.failure?.retry == nil)
        #expect(!model.canTryAgain)
        // Nothing was made: no folder, no hidden one, and the data and code were never fetched.
        #expect(names(rig.collection).isEmpty)
        #expect(rig.science.downloads == [Made.v4])
        #expect(try await rig.disk.scan().isEmpty)

        // Another version, then, as the sentence says.
        rig.science.onDownload = nil
        #expect(model.canKeep)
        model.choose(Made.v3)
        try await until("version 3 is read") { model.settled }
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.missing.isEmpty)
        #expect(names(outcome.folder) == ["README.md", "code", "data", "z_prime.png"])
        #expect(try await rig.disk.scan().count == 1)
    }

    @Test func aFigureThatCantBeWrittenEndsTheKeepWithNothingMade() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // The folder being built goes while the figure is coming, as when a volume is pulled.
        let once = Once()
        let collection = rig.collection
        rig.science.onDownload = { v in
            guard v == Made.v4, once.take() else { return nil }
            for name in names(collection) where KeptName.isTemporary(name) {
                try? FileManager.default.removeItem(at: collection.appending(path: name, directoryHint: .isDirectory))
            }
            return nil
        }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        #expect(model.failure?.sentence
            == KeepRules.figureNotCopied("z_prime.png", because: "The folder for this keep isn't there."))
        #expect(model.failure?.retry == nil)
        #expect(names(rig.collection).isEmpty)
        #expect(rig.science.downloads == [Made.v4])
        #expect(try await rig.disk.scan().isEmpty)

        // Keep is on again for another go, and it works.
        #expect(model.canKeep)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3)
        #expect(names(rig.collection) == ["z_prime"])
        #expect(rig.science.downloads.filter { $0 == Made.v4 }.count == 2)
    }

    @Test func aFigureWriteThatGetsNoAnswerSaysTheFolderDidntRespondAndLeavesNothing() async throws {
        let hold = HeldCalls()
        let rig = try Rig(hold: hold)
        defer { rig.tearDown() }
        // The volume stops answering just as the figure arrives.
        rig.science.onDownload = { v in
            if v == Made.v4 { hold.holding(true) }
            return nil
        }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        let sentence = try #require(model.failure?.sentence)
        #expect(sentence == KeepRules.figureNotCopied("z_prime.png", because: KeptDiskError.lookDidNotRespond))
        // The file isn't going to appear there: the hidden folder is abandoned.
        #expect(!sentence.contains("may still appear"))
        #expect(model.failure?.retry == nil)

        // The volume comes back: the late calls finish, and the hidden folder goes.
        hold.holding(false)
        hold.release()
        #expect(hold.count == 0)
        #expect(names(rig.collection).isEmpty)
        #expect(try await rig.disk.scan().isEmpty)
        rig.science.onDownload = nil
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        #expect(try #require(model.keptOutcome).isComplete)
    }

    @Test func aDataFileTooBigIsStillListedAndTheFolderStillMade() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // Only the figure ends a keep: the other files are listed when they can't be copied.
        rig.science.onDownload = { v in v == Made.in1 ? .answered(.tooBig) : nil }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let outcome = try #require(model.partialOutcome)
        #expect(outcome.kept == 2 && outcome.total == 3)
        #expect(outcome.missing.map(\.name) == ["z_prime_by_plate.csv"])
        #expect(outcome.missing.allSatisfy { $0.role != .figure })
        #expect(exists(outcome.folder, "z_prime.png"))
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.figure.sha256 == KeptDisk.sha256(of: Made.figure(Made.v4)))
        #expect(back.record.missing.map(\.name) == ["z_prime_by_plate.csv"])
    }
}

// MARK: E. Choosing a version: once the keep has begun, and once the choice stays

@MainActor
struct KeepChoosingTests {
    @Test func stepsThroughTheTilesReadTheProvenanceOnceForTheOneStoppedOn() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        // The sheet's own first choice reads at once, with no wait.
        #expect(rig.science.settles == 0)
        #expect(rig.science.lineageReads == [Made.v4])

        // Arrow, arrow, arrow: each choice waits to stay, and the next one cancels it.
        rig.science.holdSettles = true
        model.choose(Made.v3)
        model.choose(Made.v2)
        model.choose(Made.v1)
        try await until("the waits begin") { rig.science.settles == 3 }
        #expect(model.choices.version == Made.v1)
        #expect(model.readingProvenance)
        #expect(!model.canKeep)
        #expect(rig.science.lineageReads == [Made.v4])

        rig.science.releaseSettles()
        try await until("the one it stopped on is read") { model.settled }
        // One more read, for the version stopped on; the ones stepped past never asked the daemon.
        #expect(rig.science.lineageReads == [Made.v4, Made.v1])
        #expect(model.plan?.figure.version == Made.v1)
    }

    @Test func aChoiceThatMovedOnIsNotReadWhenItsWaitEnds() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        rig.science.holdSettles = true
        model.choose(Made.v2)
        try await until("the wait begins") { rig.science.settles == 1 }
        // Cancel (or the sheet closing) while it waits: nothing is read afterwards.
        model.cancel()
        rig.science.releaseSettles()
        for _ in 0..<50 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(rig.science.lineageReads == [Made.v4])
    }

    @Test func versionsCanBeChosenOnlyWhileTheSheetReadsOrIsReadyOrOnlyAnotherVersionHelps() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.vanished = [Made.v4]
        let model = rig.model()
        #expect(model.phase == .reading && model.canChoose)
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.canChoose)
        // The version went: only another version helps, so one can be chosen.
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        #expect(model.failure?.retry == nil)
        #expect(model.canChoose)
        // A failure that Try Again answers leaves the version as it is.
        let other = try Rig()
        defer { other.tearDown() }
        other.science.downloadFailures[Made.v4] = 1
        let again = other.model()
        again.open()
        try await until("the sheet is filled") { again.isReady }
        again.keep()
        try await until("the keep fails") { again.failure != nil }
        #expect(again.failure?.retry == .keep)
        #expect(!again.canChoose)
        again.choose(Made.v3)
        #expect(again.choices.version == Made.v4)
    }

    @Test func afterAPartialKeepTheVersionStaysAndTryAgainFinishesThatVersion() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // Version 3's provenance lists a different table that has the same file name.
        rig.science.inputsByVersion[Made.v3] = [Made.in2]
        rig.science.inputNames[Made.in2] = "z_prime_by_plate.csv"
        rig.science.downloadFailures[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.choices.version == Made.v4)
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let first = try #require(model.partialOutcome)
        #expect(first.missing.map(\.name) == ["z_prime_by_plate.csv"])

        // The tiles are still there to press (and the arrow keys): the sheet takes no notice.
        #expect(!model.canChoose)
        model.choose(Made.v3)
        try await until("a choice would be read") { model.settled }
        #expect(model.choices.version == Made.v4)
        #expect(model.plan?.figure.version == Made.v4)

        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.folder == first.folder && outcome.isComplete)
        // Version 4's table landed in version 4's folder, not version 3's.
        let table = try Data(contentsOf: outcome.folder.appending(path: "data/z_prime_by_plate.csv", directoryHint: .notDirectory))
        #expect(table == Made.table(Made.in1))
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.figure.version == Made.v4)
        #expect(back.record.files.first { $0.path == "data/z_prime_by_plate.csv" }?.version == Made.in1)
        #expect(!rig.science.downloads.contains(Made.in2))
    }

    @Test func tryAgainCopiesWhatTheKeepWasMadeWithNotWhatIsTickedNow() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadFailures[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        // The data row is unticked afterwards (the sheet disables it; the model must not depend on that).
        model.toggle(.data, false)
        #expect(model.plan?.files.contains { $0.role == .data } == false)
        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3)
        #expect(exists(outcome.folder, "data/z_prime_by_plate.csv"))
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.missing.isEmpty)
    }

    @Test func anUntickMadeWhileTheProvenanceIsReadStaysUnticked() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.holdLineage = true
        let model = rig.model()
        model.open()
        try await until("the sheet is ready and reading the provenance") { model.phase == .ready && model.readingProvenance }
        #expect(model.isOn(.answer))
        model.toggle(.answer, false)
        rig.science.releaseLineage()
        try await until("the provenance is read") { model.settled }
        // The lineage landing gives the data and code rows their defaults, and leaves the answer's alone.
        #expect(!model.isOn(.answer))
        #expect(model.isOn(.data) && model.isOn(.code))
        #expect(model.plan?.answer == nil)
    }

    @Test func aSecondKeepDoesntReplaceASheetInUse() throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let host = ShelfSheetHost()
        let first = rig.model(), second = rig.model()
        var made = 0
        #expect(host.present { made += 1; return first })
        #expect(host.keeping === first)
        // Keep… again, on this figure or another: the sheet in use stays, and the second is never made.
        #expect(!host.present { made += 1; return second })
        #expect(host.keeping === first && made == 1)
        host.keeping = nil
        #expect(host.present { made += 1; return second })
        #expect(host.keeping === second && made == 2)
    }
}

// MARK: E. Try Again leaves a person's README as it is

@MainActor
struct KeepRetryReadmeTests {
    /// A partial keep: the table timed out, so the figure and the script are in and the table is missing.
    private func partialKeep(_ rig: Rig) async throws -> (model: KeepModel, outcome: KeepOutcome, readme: URL, original: String) {
        rig.science.downloadFailures[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let outcome = try #require(model.partialOutcome)
        let readme = outcome.folder.appending(path: "README.md", directoryHint: .notDirectory)
        return (model, outcome, readme, try String(contentsOf: readme, encoding: .utf8))
    }

    /// What Try Again should leave of `edited`: the table listed, nothing missing, and no "Not copied".
    private func landed(_ edited: String, reason: String) -> String {
        let sha = KeptDisk.sha256(of: Made.table(Made.in1))
        let code = "  - { path: \"code/z_prime.py\", "
        guard let row = edited.range(of: code), let end = edited[row.lowerBound...].firstIndex(of: "\n") else { return edited }
        let table = "  - { path: \"data/z_prime_by_plate.csv\", role: data, artifact: \"\(Made.inputArtifact)\", version: \"\(Made.in1)\", "
            + "sha256: \"\(sha)\", bytes: \(Made.table(Made.in1).count) }\n"
        var out = edited
        out.insert(contentsOf: table, at: out.index(after: end))
        return out
            .replacingOccurrences(of: "missing:\n  - { role: data, name: \"z_prime_by_plate.csv\", reason: \(KeptReadme.quoted(reason)) }\n",
                                  with: "missing: []\n")
            .replacingOccurrences(of: "## Not copied\n\n- The data file, z_prime_by_plate.csv: \(reason).\n\n", with: "")
    }

    @Test func aSectionAPersonAddedToTheReadmeSurvivesTryAgain() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let (model, first, readme, original) = try await partialKeep(rig)
        let reason = try #require(first.missing.first?.reason)
        // Notes before the legend and after the last section, a line after the fine print, and a legend.
        let edited = original
            .replacingOccurrences(of: "## Your legend", with: "## Lab notes\n\nPlate 7 re-run on the 22nd.\n\n## Your legend")
            .replacingOccurrences(of: "---\n\nCapsid updates", with: "## Follow-ups\n\n- Ask about column 12\n\n---\n\nCapsid updates")
            + "Added by hand.\n"
        #expect(edited != original)
        try Data(edited.utf8).write(to: readme)

        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        #expect(try #require(model.keptOutcome).isComplete)
        let after = try String(contentsOf: readme, encoding: .utf8)
        // The README a person edited, with the table listed and nothing missing: not one byte more.
        #expect(after == landed(edited, reason: reason))
        #expect(after.contains("## Lab notes\n\nPlate 7 re-run on the 22nd.\n\n## Your legend"))
        #expect(after.contains("## Follow-ups\n\n- Ask about column 12\n\n---\n\nCapsid updates"))
        #expect(after.hasSuffix("Added by hand.\n"))
        let back = try await rig.disk.readme(at: first.folder)
        #expect(back.record.files.map(\.path) == ["code/z_prime.py", "data/z_prime_by_plate.csv"])
        #expect(back.record.missing.isEmpty)
    }

    @Test func aNewChecksumSectionIsMadeBesideCapsidsOwnAndLeavesThePersonsAlone() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        // The table times out, then comes with other bytes: it lands, listed with the checksum it didn't match.
        rig.science.corrupt[Made.in1] = 1
        rig.science.downloadFailures[Made.in1] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let first = try #require(model.partialOutcome)
        let readme = first.folder.appending(path: "README.md", directoryHint: .notDirectory)
        let edited = try String(contentsOf: readme, encoding: .utf8)
            .replacingOccurrences(of: "---\n\nCapsid updates", with: "## Follow-ups\n\nRe-download the table.\n\n---\n\nCapsid updates")
        try Data(edited.utf8).write(to: readme)

        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let after = try String(contentsOf: readme, encoding: .utf8)
        #expect(after.contains("## Checksums\n\n- data/z_prime_by_plate.csv doesn\u{2019}t match"))
        #expect(after.contains("Re-download the table.\n\n---\n\nCapsid updates"))
        let order = ["## Where it came from", "## Checksums", "## Follow-ups"]
        let places = try order.map { try #require(after.range(of: $0)?.lowerBound) }
        #expect(places == places.sorted())
    }

    @Test func aReadmeAnEditorSavedWithAByteOrderMarkIsUpdatedAndKeepsIt() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let (model, first, readme, original) = try await partialKeep(rig)
        let reason = try #require(first.missing.first?.reason)
        let mark = Data([0xEF, 0xBB, 0xBF])
        try (mark + Data(original.utf8)).write(to: readme)

        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        #expect(try #require(model.keptOutcome).isComplete)
        let bytes = try Data(contentsOf: readme)
        #expect(bytes.starts(with: mark))
        #expect(String(decoding: bytes.dropFirst(3), as: UTF8.self) == landed(original, reason: reason))
    }

    @Test func anEditMadeWhileTryAgainWorksLeavesTheReadmeAsThePersonLeftItAndSaysSo() async throws {
        let hold = HeldCalls()
        let rig = try Rig(hold: hold, patient: true)
        defer { rig.tearDown() }
        // The first keep doesn't use the held disk: it goes through, with the table missing.
        let (model, first, readme, original) = try await partialKeep(rig)
        let reason = try #require(first.missing.first?.reason)
        let downloads = rig.science.downloads.count

        // Try Again: the table is written (call 1) and the README read (call 2); the call that
        // writes the README (call 3) is held, as a share that has stopped answering holds it.
        rig.science.onDownload = { _ in
            hold.holdAfter(2)
            return nil
        }
        model.retry()
        try await until("the README write is held") { hold.count == 1 }
        #expect(exists(first.folder, "data/z_prime_by_plate.csv"))
        // Meanwhile it is edited in another app.
        let edited = original + "\nWritten in an editor while Capsid worked.\n"
        try Data(edited.utf8).write(to: readme)
        hold.holding(false)
        hold.release()

        try await until("the retry ends") { model.partialOutcome?.recordFailed != nil }
        let stuck = try #require(model.partialOutcome)
        // Left exactly as the person saved it, with no temporary file beside it.
        #expect(try String(contentsOf: readme, encoding: .utf8) == edited)
        #expect(names(first.folder) == ["README.md", "code", "data", "z_prime.png"])
        // The sheet says so in one sentence, and Try Again is there.
        #expect(stuck.recordFailed == KeepModel.readmeChangedSentence)
        #expect(KeepModel.readmeChangedSentence == "README.md was changed in another app, so Capsid left it alone.")
        #expect(KeepRules.outcomeSentence(stuck)
            == "Kept 3 files. The files landed, but README.md couldn\u{2019}t be updated to list them. \(KeepModel.readmeChangedSentence)")
        #expect(stuck.kept == 3 && stuck.missing.isEmpty && !stuck.isComplete)
        #expect(model.keptOutcome == nil)

        // Try Again reads it as it is now and updates that: the person's line stays, and nothing is copied again.
        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        #expect(try #require(model.keptOutcome).isComplete)
        #expect(rig.science.downloads.count == downloads + 1)
        let after = try String(contentsOf: readme, encoding: .utf8)
        #expect(after == landed(edited, reason: reason))
        #expect(after.contains("\nWritten in an editor while Capsid worked.\n"))
    }
}

// MARK: F. Cancel, right up to the folder going into place

@MainActor
struct KeepCancelTests {
    /// The hidden folder a keep builds in, beside where it will be.
    private func hiddenFolders(_ rig: Rig) -> [String] { names(rig.collection).filter { $0.hasPrefix(".") } }

    @Test func aCancelWhileTheLastFileIsBeingWrittenKeepsNothing() async throws {
        let hold = HeldCalls()
        let rig = try Rig(hold: hold, patient: true)
        defer { rig.tearDown() }
        // The figure and the table go in; the disk stops answering as the script, the last file, is written.
        rig.science.onDownload = { v in
            if v == Made.in1 { hold.holdAfter(1) }
            return nil
        }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the last write is held") { hold.count == 1 }
        #expect(hiddenFolders(rig).count == 1)
        #expect(model.cancel())

        // The write comes back (it ignores a Cancel, as it must): the keep still stops, and the folder never appears.
        hold.holding(false)
        hold.release()
        try await until("the keep stops") { model.phase == .ready }
        #expect(names(rig.collection).isEmpty)
        #expect(rig.kept.isEmpty)
        #expect(model.folder == nil && model.keptOutcome == nil && model.partialOutcome == nil)
        #expect(!model.isFinishing)
        // Not even Claude Science's version was asked for.
        #expect(rig.science.versionAsks == 0)
        // The same sheet keeps again.
        #expect(model.canKeep)
    }

    @Test func aCancelWhileClaudeSciencesVersionIsAskedKeepsNothing() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.holdVersion = true
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the version is asked") { rig.science.versionAsks == 1 }
        // Every file is copied into the hidden folder, and nothing is in place yet.
        #expect(hiddenFolders(rig).count == 1)
        #expect(model.phase == .keeping(done: 3, total: 3))
        #expect(!model.isFinishing && model.canCancel)
        #expect(model.cancel())

        rig.science.releaseVersion()
        try await until("the keep stops") { model.phase == .ready }
        #expect(names(rig.collection).isEmpty)
        #expect(rig.kept.isEmpty)
        #expect(model.folder == nil && model.keptOutcome == nil)
        #expect(!model.isFinishing)
    }

    @Test func aCancelOnceTheFolderIsBeingPutInPlaceIsRefusedAndTheSheetSaysSo() async throws {
        let hold = HeldCalls()
        let rig = try Rig(hold: hold, patient: true)
        defer { rig.tearDown() }
        // The version is the last thing asked before the folder is put in place: the next disk call, held, is that.
        rig.science.onVersion = { hold.holding(true) }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.canCancel && !model.isFinishing)
        model.keep()
        try await until("the folder is being put in place") { model.isFinishing && hold.count == 1 }

        // Cancel is off, and says why where the sheet says what it is doing.
        #expect(!model.canCancel)
        #expect(!model.cancel())
        #expect(KeepRules.finishingSentence == "Finishing\u{2026}")
        #expect(KeepRules.finishingHelp == "The folder is being put in place. It can\u{2019}t be cancelled now.")
        #expect(model.phase == .keeping(done: 3, total: 3))

        // The refusal changed nothing: the folder goes in place, and the sheet says kept.
        hold.holding(false)
        hold.release()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3)
        #expect(names(rig.collection) == ["z_prime"])
        #expect(rig.kept.count == 1)
        #expect(!model.isFinishing && model.canCancel)
    }

    /// The sheet is the model's two facts and nothing of its own: its status says "Finishing…" in place of
    /// the count while `isFinishing`, and its Cancel (and so Esc) follows `canCancel`. (An accessibility
    /// tree needs a window, and a test opens none: the sheet is drawn to PNGs by `KeepSheetSnapshotTests`.)
    @Test func theSheetFollowsTheModelsFinishingAndCanCancel() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/Kept/KeepSheet.swift", isDirectory: false), encoding: .utf8)
        let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains { $0.contains("model.isFinishing ? KeepRules.finishingSentence : \"Keeping \\(done) of \\(total) files") })
        // The Cancel of a keep that is under way (not the one of a failed read) is dimmed with the help that says why.
        #expect(lines.contains(".disabled(!model.canCancel)"))
        #expect(lines.contains { $0.hasPrefix(".help(model.canCancel ? \"\" : KeepRules.finishingHelp)") })
        #expect(lines.contains(".interactiveDismissDisabled(!model.canCancel)"))
    }
}

// MARK: The log: what the sheet did, in fixed words

@MainActor
struct KeepNoteTests {
    @Test func aKeepThatLandsNotesEachStepAndNoName() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let notes = rig.notes
        #expect(notes.first == "Keep: the sheet opened")
        #expect(notes.contains { $0.hasPrefix("Keep: ready, 4 versions, ") }, "\(notes)")
        #expect(notes.contains { $0.hasPrefix("Keep: provenance read, ") && $0.hasSuffix(" files to keep") }, "\(notes)")
        #expect(notes.last == "Keep: keeping \(model.keptOutcome?.total ?? -1) files")
        // The made-up figure's, project's and session's names are nowhere in them.
        for note in notes {
            #expect(!note.contains("z_prime") && !note.contains("Assay") && !note.contains(Made.session.title), "\(note)")
        }
    }

    @Test func aFirstReadThatFailsSaysWhichWay() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.factsFailures = 1
        let model = rig.model()
        model.open()
        try await until("the first read fails") { model.failure != nil }
        #expect(rig.notes == ["Keep: the sheet opened", "Keep: the figure's first read failed: timedOut"])
    }

    @Test func aFigureThatCouldNotBeReadIsAFailureInTheLog() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.downloadFailures[Made.v4] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep fails") { model.failure != nil }
        #expect(rig.notes.last == "Keep failed: the figure couldn't be read")
    }
}

// MARK: A provenance Claude Science is still working out

@MainActor
struct KeepPendingTests {
    private func readme(_ outcome: KeepOutcome) throws -> String {
        try String(contentsOf: outcome.folder.appending(path: "README.md", directoryHint: .notDirectory), encoding: .utf8)
    }

    @Test func keepWaitsWhilePendingThenKeepsTheDataAndCodeOnceTheyAreThere() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.pendingLineage = 3
        let model = rig.model()
        model.open()
        try await until("the provenance is there") { model.isReady }
        // Keep was off at every wait: a keep then would have held the figure alone.
        #expect(rig.keepOnWhilePending == [false, false, false])
        // The rows are ticked as for any provenance (they were unticked while it was pending).
        #expect(model.row(.data)?.available == true && model.row(.code)?.available == true)
        #expect(model.choices.withData && model.choices.withCode)
        #expect(rig.notes.contains { $0.hasPrefix("Keep: provenance ready after 3 checks, 1 inputs, 1 copyable; ") }, "\(rig.notes)")
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.isComplete && outcome.kept == 3, "the figure, its data and its code")
        #expect(!(try readme(outcome)).contains("not kept"))
    }

    @Test func afterTwoMinutesKeepIsOnAndTheReadmeSaysWhyThereIsNoDataOrCode() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.pendingLineage = 1 + KeepDependencies.rechecks
        let model = rig.model()
        model.open()
        try await until("the waiting is over") { model.isReady }
        #expect(rig.keepOnWhilePending.count == KeepDependencies.rechecks)
        #expect(!rig.keepOnWhilePending.contains(true))
        #expect(rig.notes.last?.hasPrefix("Keep: provenance still pending after two minutes; ") == true, "\(rig.notes)")
        #expect(model.canKeep)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.kept == 1 && outcome.total == 1)
        #expect(try readme(outcome).contains(KeepRules.pendingSentence))
    }

    @Test func aFigureWithNoInputsRecordedSaysSoInItsReadme() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        rig.science.inputs = []
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let text = try readme(try #require(model.keptOutcome))
        #expect(text.contains("The data it was drawn from: not kept. No source data recorded."))
        #expect(!text.contains("The code that drew it: not kept"), "the script was kept")
        // The Kept window still reads it, and reads the line back as written.
        let parsed = try #require(KeptReadme.parse(text))
        #expect(parsed.text.origin.hasSuffix("\nThe data it was drawn from: not kept. No source data recorded."))
        #expect(KeptReadme.render(parsed.record, text: parsed.text) == text)
    }

    @Test func aRowLeftOutByChoiceSaysSo() async throws {
        let rig = try Rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.toggle(.code, false)
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        #expect(try readme(try #require(model.keptOutcome)).contains("The code that drew it: not kept. Left out when it was kept."))
    }
}

// MARK: F. Claude's legend file (since 1.0.6)

@MainActor
struct KeepLegendTests {
    /// A sheet on a made-up answer that shows version 3 and made a legend file, with the legend files read.
    private func rig(files: [HistoryFile]? = [Made.legendsFile]) throws -> Rig {
        let rig = try Rig()
        rig.science.showing = Made.showing(Made.v3)
        rig.science.answerFiles = files
        rig.science.extraBytes = [Made.legends: Data(Made.legendsText.utf8), Made.sibling: Data(Made.siblingText.utf8)]
        return rig
    }

    private func readme(_ outcome: KeepOutcome) throws -> String {
        try String(contentsOf: outcome.folder.appending(path: "README.md", directoryHint: .notDirectory), encoding: .utf8)
    }

    @Test func theRowIsThereOnlyWithALegendFileAndOnByDefault() async throws {
        let none = try rig(files: [])
        defer { none.tearDown() }
        let without = none.model()
        without.open()
        try await until("the sheet is filled") { without.isReady }
        #expect(without.rows.map(\.kind) == [.answer, .data, .code])
        #expect(without.row(.legend) == nil && !without.isOn(.legend))

        let rig = try rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.rows.map(\.kind) == [.answer, .data, .code, .legend])
        let row = try #require(model.row(.legend))
        #expect(row.title == "Claude\u{2019}s legend")
        #expect(row.detail.hasPrefix("FIGURE_LEGENDS_final.md \u{00B7} "))
        #expect(row.available && row.onByDefault)
        #expect(model.isOn(.legend) && model.choices.withLegend)
        // It was looked for around the row of the answer that shows the version, once.
        #expect(rig.science.answerFileAsks == [12])
    }

    @Test func anAnswerWithNoRowOrUnreadableFilesHasNoLegendRow() async throws {
        // Pinned by the caller: no row of the history to look around.
        let pinned = try rig()
        defer { pinned.tearDown() }
        let fromPage = pinned.model(entry: Made.v3, pinned: KeepPinnedAnswer(text: Made.answer, at: Made.at(20)))
        fromPage.open()
        try await until("the sheet is filled") { fromPage.isReady }
        #expect(fromPage.row(.legend) == nil)
        #expect(pinned.science.answerFileAsks.isEmpty)

        // The page couldn't be read: the keep goes on without the row, and says so in the log.
        let unreadable = try rig(files: nil)
        defer { unreadable.tearDown() }
        let model = unreadable.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.row(.legend) == nil)
        #expect(unreadable.notes.contains("Keep: the answer's files couldn't be read"))
    }

    @Test func theRowFollowsTheVersionTheAnswerShows() async throws {
        let rig = try rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        #expect(model.row(.legend) != nil)
        // Version 4 isn't the one the answer shows: its legend is for another figure.
        model.choose(Made.v4)
        try await until("version 4 is read") { model.settled && model.choices.version == Made.v4 }
        #expect(model.row(.legend) == nil && !model.isOn(.legend))
        #expect(model.plan?.files.contains { $0.role == .legend } == false)
        model.choose(Made.v3)
        try await until("version 3 is read") { model.settled && model.choices.version == Made.v3 }
        #expect(model.row(.legend) != nil && model.isOn(.legend))
    }

    @Test func keepingCopiesTheFileAndPutsTheFiguresPartInYourLegend() async throws {
        let rig = try rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        let legend = try #require(model.plan?.files.first { $0.role == .legend })
        #expect(legend.relativePath == "FIGURE_LEGENDS_final.md" && legend.version == Made.legends)
        #expect(model.destinationSentence.contains("code, Claude\u{2019}s legend and a README.md."), "\(model.destinationSentence)")
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.closesSheet && outcome.kept == 4 && outcome.total == 4)
        #expect(names(outcome.folder) == ["FIGURE_LEGENDS_final.md", "README.md", "code", "data", "z_prime.png"])
        // The file as Claude made it, whole.
        let copy = try Data(contentsOf: outcome.folder.appending(path: "FIGURE_LEGENDS_final.md", directoryHint: .notDirectory))
        #expect(copy == Data(Made.legendsText.utf8))
        // Listed with its role, and the legend holds the figure's section alone.
        let back = try await rig.disk.readme(at: outcome.folder)
        let listed = try #require(back.record.files.first { $0.path == "FIGURE_LEGENDS_final.md" })
        #expect(listed.role == .legend && listed.version == Made.legends)
        #expect(listed.sha256 == KeptDisk.sha256(of: copy))
        #expect(back.text.legend == Made.legendPart)
        #expect(!back.text.legend.contains("plate_map") && !back.text.legend.contains("edge_effect"))
        #expect(try readme(outcome).contains("## Your legend\n\n\(Made.legendPart)\n"))
    }

    @Test func severalLegendFilesKeepTheBestAndTheRowSaysWhich() async throws {
        let rig = try rig(files: [Made.legendsFile, Made.siblingFile])
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        // The file that shares the figure's name beats the one with "legend" in its name.
        let row = try #require(model.row(.legend))
        #expect(row.detail.hasPrefix("z_prime.md, the closest of 2 in the answer \u{00B7} "), "\(row.detail)")
        #expect(model.plan?.files.filter { $0.role == .legend }.map(\.name) == ["z_prime.md"])
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(!exists(outcome.folder, "FIGURE_LEGENDS_final.md") && exists(outcome.folder, "z_prime.md"))
        // No section for the figure in a file that is only for it: all of it.
        #expect(try await rig.disk.readme(at: outcome.folder).text.legend == Made.siblingText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func untickingLeavesItOut() async throws {
        let rig = try rig()
        defer { rig.tearDown() }
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.toggle(.legend, false)
        #expect(!model.isOn(.legend))
        #expect(model.plan?.files.contains { $0.role == .legend } == false)
        #expect(!model.destinationSentence.contains("legend"))
        model.keep()
        try await until("it is kept") { model.keptOutcome != nil }
        let outcome = try #require(model.keptOutcome)
        #expect(outcome.total == 3)
        #expect(names(outcome.folder) == ["README.md", "code", "data", "z_prime.png"])
        #expect(!rig.science.downloads.contains(Made.legends))
        let back = try await rig.disk.readme(at: outcome.folder)
        #expect(back.record.files.allSatisfy { $0.role != .legend })
        #expect(back.text.legend.isEmpty)
    }

    @Test func aLegendFileThatCouldntBeCopiedIsListedAndTryAgainFillsYourLegend() async throws {
        let rig = try rig()
        defer { rig.tearDown() }
        rig.science.downloadFailures[Made.legends] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let first = try #require(model.partialOutcome)
        #expect(first.missing.map(\.role) == [.legend])
        #expect(model.fate(of: .legend)?.isProblem == true)
        #expect(try await rig.disk.readme(at: first.folder).text.legend.isEmpty)
        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let done = try #require(model.keptOutcome)
        #expect(done.isComplete)
        let back = try await rig.disk.readme(at: done.folder)
        #expect(back.record.files.contains { $0.path == "FIGURE_LEGENDS_final.md" && $0.role == .legend })
        #expect(back.text.legend == Made.legendPart)
    }

    @Test func aLegendAPersonWroteMeanwhileIsNeverWrittenOver() async throws {
        let rig = try rig()
        defer { rig.tearDown() }
        rig.science.downloadFailures[Made.legends] = 1
        let model = rig.model()
        model.open()
        try await until("the sheet is filled") { model.isReady }
        model.keep()
        try await until("the keep ends") { model.partialOutcome != nil }
        let first = try #require(model.partialOutcome)
        // Their own words, typed into the README before Try Again.
        let before = try await rig.disk.readme(at: first.folder)
        let written = try #require(KeptReadme.replacingLegend(in: before.markdown, with: "Z\u{2032} per plate, in my words."))
        try await rig.disk.replaceReadme(at: first.folder, markdown: written, lastRead: before.markdown)
        model.retry()
        try await until("it is kept") { model.keptOutcome != nil }
        let back = try await rig.disk.readme(at: first.folder)
        #expect(back.text.legend == "Z\u{2032} per plate, in my words.")
        #expect(back.record.files.contains { $0.role == .legend })
    }
}
