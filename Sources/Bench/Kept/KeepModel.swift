// KeepModel.swift — the Keep sheet's state and its work (DESIGN.md, Keep):
// the reads that fill it (the file's facts, the artifact's versions, the
// answer that shows one, the chosen version's provenance), the choices, and
// the keep itself: each file fetched through the shelf's queue, checked
// against the daemon's checksum, written into a hidden folder beside its
// destination, the README last, then the folder renamed into place. What
// couldn't be copied is listed, never guessed, and Try Again copies only
// that. Every step that touches the page or the disk is a dependency, so the
// demo and the tests run the whole sheet on made-up data.
import AppKit
import CryptoKit
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "keep")

/// Where the sheet stands.
enum KeepPhase: Equatable, Sendable {
    /// The facts, versions and answer are being read.
    case reading
    case ready
    /// Files copied so far, of how many.
    case keeping(done: Int, total: Int)
    /// Everything copied: the sheet closes.
    case kept(KeepOutcome)
    /// Some files weren't: the sheet stays with Try Again.
    case partial(KeepOutcome)
    /// Nothing was kept. `retryable` offers Try Again (a read that failed);
    /// otherwise Cancel, or another version.
    case failed(String, retryable: Bool)
}

/// Every step of a keep that reaches the page or the disk.
struct KeepDependencies {
    /// A read through the shelf's queue, kept through the window closing.
    var read: @MainActor (ArtifactRead) async -> ShelfTransferResult
    /// The answer that shows one of the versions (Remote/HistoryReader.swift).
    var showing: @MainActor (_ frameID: String, _ versions: [String], _ near: Date?) async -> ShowingRead
    /// The session's last answer, the fallback.
    var lastAnswer: @MainActor (_ frameID: String) async -> KeepAnswer?
    var thumbnails: ShelfThumbnails
    var disk: KeptDisk
    var defaults: UserDefaults
    var root: @MainActor () -> URL
    /// Claude Science's version, for the README: asked once per keep.
    var scienceVersion: @MainActor () async -> String?
    var capsidVersion: String
    var now: @MainActor () -> Date
    /// A folder was kept: the Results window's Kept section takes it in.
    var didKeep: @MainActor (KeepOutcome) -> Void

    @MainActor
    static func live(shelf: ResultsShelf) -> KeepDependencies {
        let disk = KeptDisk(root: { KeptSettings.root() })
        return KeepDependencies(
            read: { await shelf.transfers.read($0, priority: .foreground, keepsOnClose: true) },
            showing: { frameID, versions, near in
                guard Demo.mode == nil else { return .unreadable }
                let nonce = UUID().uuidString
                return await withTaskCancellationHandler {
                    (try? await WebContainer.shared.readShowing(frameID: frameID, versions: versions, near: near, nonce: nonce))
                        ?? .unreadable
                } onCancel: {
                    Task { @MainActor in await WebContainer.shared.abortArtifactRead(nonce) }
                }
            },
            lastAnswer: { frameID in
                guard Demo.mode == nil, let projection = try? await WebContainer.shared.readSession(frameID, turns: false),
                      let reply = projection.reply, !reply.isEmpty else { return nil }
                return KeepAnswer(text: reply, at: projection.replyAt, how: nil, isFallback: true)
            },
            thumbnails: shelf.thumbnailStore,
            disk: disk,
            defaults: .standard,
            root: { KeptSettings.root() },
            scienceVersion: { await DaemonController.runningStatus()?.version },
            capsidVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            now: { Date() },
            didKeep: { KeptIndex.shared.add($0) })
    }
}

/// The Kept root and the per-project collection memory (settings-sized values).
enum KeptSettings {
    /// `keptRoot`: a path; empty means `~/Documents/Kept`.
    static func root(defaults: UserDefaults = .standard) -> URL {
        if let path = defaults.string(forKey: SettingsKey.keptRoot), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return KeptDefaults.root()
    }

    /// `keptCollections`: the collection last kept into, by project id.
    static func collection(for project: String, defaults: UserDefaults = .standard) -> String? {
        (defaults.dictionary(forKey: SettingsKey.keptCollections) as? [String: String])?[project]
    }

    static func remember(collection: String, for project: String, defaults: UserDefaults = .standard) {
        var memory = (defaults.dictionary(forKey: SettingsKey.keptCollections) as? [String: String]) ?? [:]
        memory[project] = collection
        defaults.set(memory, forKey: SettingsKey.keptCollections)
    }
}

@MainActor
final class KeepModel: ObservableObject, Identifiable {
    let id = UUID()
    let subject: KeepSubject
    private let dependencies: KeepDependencies

    @Published private(set) var phase: KeepPhase = .reading
    @Published private(set) var sources = KeepSources()
    @Published var choices: KeepChoices
    @Published private(set) var tiles: [VersionTile] = []
    @Published private(set) var rows: [KeepRow] = []
    @Published private(set) var collections: [String] = []
    /// The folder the keep will make: the name, or the dated name when taken.
    @Published private(set) var folderName: String
    @Published private(set) var nameTaken = false
    /// The provenance is being read for the chosen version.
    @Published private(set) var readingProvenance = false
    /// After a partial keep: the folder, for Try Again and Show in Finder.
    @Published private(set) var folder: URL?

    private var openTask: Task<Void, Never>?
    private var chosenTask: Task<Void, Never>?
    private var keepTask: Task<Void, Never>?
    private var nameTask: Task<Void, Never>?
    private var thumbnailTasks: [Task<Void, Never>] = []

    init(subject: KeepSubject, dependencies: KeepDependencies) {
        self.subject = subject
        self.dependencies = dependencies
        let name = KeepRules.defaultName(for: subject.entry)
        let project = subject.session.projectID
        let collection = KeptSettings.collection(for: project, defaults: dependencies.defaults)
            ?? KeptName.sanitized(subject.session.projectName)
        choices = KeepChoices(name: name, version: nil, withAnswer: true, withData: true, withCode: true,
                              collection: collection)
        folderName = KeptName.sanitized(name)
    }

    var root: URL { dependencies.root() }
    var thumbnails: ShelfThumbnails { dependencies.thumbnails }
    var isUpload: Bool { KeepRules.isUpload(sources) }

    /// What the keep will copy, as the choices stand.
    var plan: KeepPlan? { KeepRules.plan(subject: subject, sources: sources, choices: choices) }

    var versionSentence: String { KeepRules.versionSentence(tiles: tiles, chosen: choices.version, showing: sources.showing) }

    var destinationSentence: String {
        KeepRules.destinationSentence(root: root, collection: choices.collection, folderName: folderName, plan: plan,
                                      nameTaken: nameTaken, requested: KeptName.sanitized(choices.name))
    }

    /// Keep is on when a version is chosen and read, the name isn't empty,
    /// and nothing is under way.
    var canKeep: Bool {
        guard case .ready = phase, plan != nil, !readingProvenance else { return false }
        return !choices.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Reading

    /// Fills the sheet: facts, versions, the answer, the collections, then
    /// the chosen version's provenance.
    func open() {
        guard openTask == nil else { return }
        openTask = Task { [weak self] in
            await self?.load()
        }
    }

    private func load() async {
        let entry = subject.entry
        // 1. The picked version's facts: the artifact id and the name.
        switch await dependencies.read(.facts(version: entry.version)) {
        case .answered(.facts(let facts)):
            sources.facts = facts
        case .answered(.missing):
            phase = .failed(ShelfFailure.missing.sentence, retryable: false)
            return
        case .answered(.cancelled), .cancelled:
            return
        case .answered(let other):
            phase = .failed(ShelfFailure(other).sentence, retryable: true)
            return
        case .timedOut:
            phase = .failed(ShelfFailure.timedOut.sentence, retryable: true)
            return
        case .notReady:
            phase = .failed(ShelfFailure.notReady.sentence, retryable: true)
            return
        }
        if Task.isCancelled { return }
        // 2. Every version of the artifact.
        if let artifact = sources.facts?.a ?? entry.artifact {
            switch await dependencies.read(.versions(artifact: artifact)) {
            case .answered(.versions(let versions)):
                sources.versions = versions
            case .answered(.cancelled), .cancelled:
                return
            case .answered(let other):
                sources.versionsFailed = ShelfFailure(other)
            case .timedOut:
                sources.versionsFailed = .timedOut
            case .notReady:
                sources.versionsFailed = .notReady
            }
        }
        if sources.versions.isEmpty {
            // No list: the picked version is the one there is.
            let facts = sources.facts
            sources.versions = [ArtifactVersion(v: entry.version, n: facts?.n ?? 1, frame: nil, mime: facts?.mime ?? entry.mime,
                                                size: facts?.size ?? entry.size, at: facts?.at ?? entry.at, parent: nil)]
        }
        if Task.isCancelled { return }
        wantThumbnails()
        // 3. The answer that shows one of them, else the last answer.
        let ids = sources.versions.map(\.v)
        let near = sources.versions.compactMap(\.at).min()
        if case .found(let message) = await dependencies.showing(subject.session.id, ids, near) {
            sources.showing = message
        } else if !Task.isCancelled {
            sources.lastAnswer = await dependencies.lastAnswer(subject.session.id)
        }
        if Task.isCancelled { return }
        tiles = KeepRules.tiles(versions: sources.versions, showing: sources.showing, gone: sources.gone)
        // 4. Where it can go.
        collections = (try? await dependencies.disk.listCollections()) ?? []
        if Task.isCancelled { return }
        phase = .ready
        // 5. The chosen version: its provenance.
        choose(KeepRules.preselect(versions: sources.versions, showing: sources.showing))
        checkName()
    }

    /// The tiles' pictures, through the shelf's store, newest first.
    private func wantThumbnails() {
        guard ArtifactGate.thumb(kind: subject.entry.kind) == nil else { return }
        for version in sources.versions.sorted(by: { $0.n > $1.n }).prefix(12) where !thumbnails.knows(version.v) {
            thumbnailTasks.append(Task { [weak self] in
                guard let self else { return }
                if case .answered(.bytes(let data)) = await dependencies.read(.thumb(version: version.v, width: 120)),
                   case .success(let webp) = ArtifactGate.thumbBytes(data) {
                    thumbnails.receive(webp, for: version.v)
                }
            })
        }
    }

    // MARK: Choosing

    /// Picks a version: its provenance and facts are read, and the rows
    /// follow. Picking the one chosen changes nothing.
    func choose(_ version: String?) {
        guard version != choices.version || sources.lineage?.v != version else { return }
        choices.version = version
        chosenTask?.cancel()
        sources.lineage = nil
        sources.lineageFailed = false
        sources.chosenFacts = nil
        sources.inputFacts = [:]
        rows = KeepRules.rows(sources: sources)
        guard let version else { return }
        readingProvenance = true
        chosenTask = Task { [weak self] in
            await self?.loadChosen(version)
        }
    }

    private func loadChosen(_ version: String) async {
        defer { if !Task.isCancelled { readingProvenance = false } }
        if version != subject.entry.version {
            if case .answered(.facts(let facts)) = await dependencies.read(.facts(version: version)) {
                sources.chosenFacts = facts
            }
        } else {
            sources.chosenFacts = sources.facts
        }
        if Task.isCancelled { return }
        if KeepRules.isUpload(sources) {
            rows = KeepRules.rows(sources: sources)
            return
        }
        switch await dependencies.read(.lineage(version: version)) {
        case .answered(.lineage(let lineage)):
            sources.lineage = lineage
        case .answered(.cancelled), .cancelled:
            return
        default:
            sources.lineageFailed = true
        }
        if Task.isCancelled { return }
        rows = KeepRules.rows(sources: sources)
        applyRowDefaults()
        // Each copyable input's name and size, a few at a time.
        if let lineage = sources.lineage {
            for input in lineage.inputs.prefix(KeepRules.inputLimit) where input.fetchable {
                guard let v = input.v, sources.inputFacts[v] == nil else { continue }
                if case .answered(.facts(let facts)) = await dependencies.read(.facts(version: v)), facts.v == v {
                    sources.inputFacts[v] = facts
                }
                if Task.isCancelled { return }
            }
            rows = KeepRules.rows(sources: sources)
        }
        // The provenance's mapping may still be pending: once more in a while.
        if sources.lineage?.pending == true || sources.lineage?.mappingStatus == "pending" {
            readingProvenance = false
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                guard case .answered(.lineage(let again)) = await dependencies.read(.lineage(version: version)) else { return }
                sources.lineage = again
                rows = KeepRules.rows(sources: sources)
                if !again.pending, again.mappingStatus != "pending" { return }
            }
        }
    }

    func toggle(_ kind: KeepRowKind, _ on: Bool) {
        switch kind {
        case .answer: choices.withAnswer = on
        case .data: choices.withData = on
        case .code: choices.withCode = on
        }
    }

    func isOn(_ kind: KeepRowKind) -> Bool {
        guard rows.first(where: { $0.kind == kind })?.available == true else { return false }
        switch kind {
        case .answer: return choices.withAnswer
        case .data: return choices.withData
        case .code: return choices.withCode
        }
    }

    /// The rows take their defaults when the provenance comes.
    private func applyRowDefaults() {
        for row in rows {
            switch row.kind {
            case .answer: choices.withAnswer = row.onByDefault
            case .data: choices.withData = row.onByDefault
            case .code: choices.withCode = row.onByDefault
            }
        }
    }

    // MARK: The name and the collection

    func setName(_ name: String) {
        choices.name = name
        checkName()
    }

    func setCollection(_ collection: String) {
        choices.collection = collection
        checkName()
    }

    /// A new collection: made when the keep lands, listed now.
    func addCollection(_ name: String) {
        let clean = KeptName.sanitized(name)
        guard !clean.isEmpty else { return }
        if !collections.contains(clean) { collections.append(clean); collections.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
        setCollection(clean)
    }

    /// Whether the name is taken in the collection, asked of the disk.
    private func checkName() {
        nameTask?.cancel()
        let requested = KeptName.sanitized(choices.name)
        folderName = requested
        nameTask = Task { [weak self] in
            guard let self else { return }
            let taken = (try? await dependencies.disk.isTaken(collection: choices.collection, name: requested)) ?? false
            guard !Task.isCancelled, KeptName.sanitized(choices.name) == requested else { return }
            nameTaken = taken
            folderName = taken ? KeptName.dated(requested, at: dependencies.now()) : requested
        }
    }

    // MARK: Keeping

    func keep() {
        guard canKeep, let plan, keepTask == nil else { return }
        let total = plan.all.count
        phase = .keeping(done: 0, total: total)
        keepTask = Task { [weak self] in
            await self?.perform(plan)
            self?.keepTask = nil
        }
    }

    /// Cancel while copying: the reads stop and the hidden folder goes.
    func cancel() {
        keepTask?.cancel()
        openTask?.cancel()
        chosenTask?.cancel()
        thumbnailTasks.forEach { $0.cancel() }
    }

    private func perform(_ plan: KeepPlan) async {
        let d = dependencies
        let keptAt = d.now()
        let destination: KeptDestination
        do {
            destination = try await d.disk.prepare(collection: choices.collection, name: KeptName.sanitized(choices.name), at: keptAt)
        } catch {
            phase = .failed(KeptDiskError.sentence(error), retryable: false)
            return
        }
        var copied: [KeptFile] = []
        var missing: [KeptMissing] = []
        for (index, item) in plan.all.enumerated() {
            if Task.isCancelled { await d.disk.abandon(destination); phase = .ready; return }
            switch await fetch(item) {
            case .bytes(let data):
                do {
                    try await d.disk.write(data, to: item.relativePath, in: destination)
                    copied.append(KeptFile(path: item.relativePath, role: item.role, artifact: item.artifact, version: item.version,
                                           index: nil, of: nil, sha256: d.disk.sha256(of: data), bytes: data.count))
                } catch {
                    missing.append(KeptMissing(role: item.role, name: item.name, reason: KeptDiskError.sentence(error)))
                }
            case .gone where item.role == .figure:
                await d.disk.abandon(destination)
                if let version = item.version { sources.gone.insert(version) }
                tiles = KeepRules.tiles(versions: sources.versions, showing: sources.showing, gone: sources.gone)
                let n = tiles.first { $0.v == item.version }?.n ?? 0
                phase = .failed("Version \(n) isn\u{2019}t in Claude Science any more, so nothing was kept. Choose another version, or Cancel.",
                                retryable: false)
                return
            case .gone:
                missing.append(KeptMissing(role: item.role, name: item.name, reason: ShelfFailure.missing.sentence))
            case .tooBig:
                missing.append(KeptMissing(role: item.role, name: item.name, reason: "too big to keep here (over 8 MB)"))
            case .failed(let sentence) where item.role == .figure:
                await d.disk.abandon(destination)
                phase = .failed(sentence, retryable: true)
                return
            case .failed(let sentence):
                missing.append(KeptMissing(role: item.role, name: item.name, reason: sentence))
            case .cancelled:
                await d.disk.abandon(destination)
                phase = .ready
                return
            }
            phase = .keeping(done: index + 1, total: plan.all.count)
        }
        let scienceVersion = await d.scienceVersion()
        let (record, text) = KeepRules.record(subject: subject, sources: sources, plan: plan, folderName: destination.name,
                                              keptAt: keptAt, copied: copied, missing: missing,
                                              scienceVersion: scienceVersion, capsidVersion: d.capsidVersion)
        let folder: URL
        do {
            folder = try await d.disk.finish(destination, readme: KeptReadme.render(record, text: text))
        } catch {
            await d.disk.abandon(destination)
            phase = .failed(KeptDiskError.sentence(error), retryable: false)
            return
        }
        self.folder = folder
        KeptSettings.remember(collection: destination.collection, for: subject.session.projectID, defaults: d.defaults)
        let outcome = KeepOutcome(folder: folder, collection: destination.collection, folderName: folder.lastPathComponent,
                                  kept: copied.count, total: plan.all.count, missing: missing)
        log.notice("Kept \(outcome.kept, privacy: .public) of \(outcome.total, privacy: .public) files")
        d.didKeep(outcome)
        phase = outcome.isComplete ? .kept(outcome) : .partial(outcome)
    }

    /// Try Again after a partial keep: only what is missing, into the folder
    /// that exists, and the README rewritten.
    func retry() {
        guard case .partial(let outcome) = phase, let plan, let folder, keepTask == nil else { return }
        let wanted = plan.files.filter { item in outcome.missing.contains { $0.name == item.name && $0.role == item.role } }
        guard !wanted.isEmpty else { return }
        phase = .keeping(done: outcome.kept, total: outcome.total)
        keepTask = Task { [weak self] in
            await self?.performRetry(plan: plan, folder: folder, outcome: outcome, wanted: wanted)
            self?.keepTask = nil
        }
    }

    private func performRetry(plan: KeepPlan, folder: URL, outcome: KeepOutcome, wanted: [KeepItem]) async {
        let d = dependencies
        var missing = outcome.missing
        var copied: [KeptFile] = []
        var kept = outcome.kept
        for item in wanted {
            if Task.isCancelled { phase = .partial(outcome); return }
            switch await fetch(item) {
            case .bytes(let data):
                do {
                    try await d.disk.writeInto(folder, data, relativePath: item.relativePath)
                    copied.append(KeptFile(path: item.relativePath, role: item.role, artifact: item.artifact, version: item.version,
                                           index: nil, of: nil, sha256: d.disk.sha256(of: data), bytes: data.count))
                    missing.removeAll { $0.name == item.name && $0.role == item.role }
                    kept += 1
                    phase = .keeping(done: kept, total: outcome.total)
                } catch {
                    replaceReason(&missing, item, KeptDiskError.sentence(error))
                }
            case .gone: replaceReason(&missing, item, ShelfFailure.missing.sentence)
            case .tooBig: replaceReason(&missing, item, "too big to keep here (over 8 MB)")
            case .failed(let sentence): replaceReason(&missing, item, sentence)
            case .cancelled:
                phase = .partial(outcome)
                return
            }
        }
        // The README, with what is there now.
        if let read = try? await d.disk.readme(at: folder) {
            var record = read.record
            record.files += copied
            record.missing = missing
            let markdown = KeptReadme.render(record, text: read.text)
            try? await d.disk.replaceReadme(at: folder, markdown: markdown)
        }
        let result = KeepOutcome(folder: folder, collection: outcome.collection, folderName: outcome.folderName,
                                 kept: kept, total: outcome.total, missing: missing)
        d.didKeep(result)
        phase = result.isComplete ? .kept(result) : .partial(result)
    }

    private func replaceReason(_ missing: inout [KeptMissing], _ item: KeepItem, _ reason: String) {
        missing.removeAll { $0.name == item.name && $0.role == item.role }
        missing.append(KeptMissing(role: item.role, name: item.name, reason: reason))
    }

    private enum Fetched {
        case bytes(Data), gone, tooBig, failed(String), cancelled
    }

    /// A file's bytes: the script from the text it is, the rest through the
    /// shelf's queue and the 8 MB cap, checked against the daemon's checksum
    /// when it has one.
    private func fetch(_ item: KeepItem) async -> Fetched {
        switch item.source {
        case .text(let text):
            return .bytes(Data(text.utf8))
        case .download(let version):
            if let size = item.size, size > KeepRules.cap { return .tooBig }
            switch await dependencies.read(.download(version: version)) {
            case .answered(.bytes(let data)):
                guard case .success(let bytes) = ArtifactGate.downloadBytes(data) else { return .tooBig }
                if let sha = item.sha, sha != dependencies.disk.sha256(of: bytes) {
                    log.error("A kept file's bytes don't match the daemon's checksum")
                }
                return .bytes(bytes)
            case .answered(.tooBig): return .tooBig
            case .answered(.missing): return .gone
            case .answered(.cancelled), .cancelled: return .cancelled
            case .answered(let other): return .failed(ShelfFailure(other).sentence)
            case .timedOut: return .failed(ShelfFailure.timedOut.sentence)
            case .notReady: return .failed(ShelfFailure.notReady.sentence)
            }
        }
    }

    // MARK: The result

    /// The sentence under the rows after a keep: what landed, and what didn't.
    var outcomeSentence: String? {
        switch phase {
        case .kept(let outcome), .partial(let outcome): return KeepRules.outcomeSentence(outcome)
        default: return nil
        }
    }

    /// After a keep, each row's fate: "Kept", or why not.
    func fate(of kind: KeepRowKind) -> (text: String, isProblem: Bool)? {
        guard case .partial(let outcome) = phase, let plan else { return nil }
        let role: KeptRole = switch kind {
        case .answer: .figure
        case .data: .data
        case .code: .code
        }
        if kind == .answer { return nil }
        let items = plan.files.filter { $0.role == role }
        guard !items.isEmpty else { return nil }
        let lost = outcome.missing.filter { $0.role == role }
        if lost.isEmpty { return ("Kept", false) }
        var reason = lost.first?.reason ?? ""
        if reason.hasSuffix(".") { reason.removeLast() }
        return ("Not copied: \(reason).", true)
    }

    func showInFinder() {
        guard let folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

extension KeptDiskError {
    /// The sentence for any disk error.
    static func sentence(_ error: any Error) -> String {
        KeptDiskError.from(error).errorDescription ?? "Couldn\u{2019}t keep it there."
    }
}
