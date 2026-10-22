// UpdateInstall.swift — installing a newer Capsid natively (DESIGN.md, Update
// check → Installing natively, since 1.0). Install downloads the release's
// Bench.zip for the offered tag into a state folder in Caches, unpacks it,
// checks that the copy is signed the way this one is and says the version
// that was offered, and only then runs Resources/swap.sh, which waits for
// this Capsid to quit, moves the old copy aside, moves the new one into
// place and opens it; if the new one doesn't start, the old one is put back.
// Nothing is deleted until swap.sh has seen the new copy stay up and said so
// in its marker (UpdateAftermath, at the new copy's launch, waits for it). A
// download or a check that fails leaves the installed Capsid untouched and
// deletes what was downloaded without opening it.
//
// `UpdateInstallRules` is pure, so the tests run it on made-up names and
// markers. `UpdateInstallFlow` takes every step that touches the disk, the
// network or the running app as a dependency, so the tests run the whole
// flow with fakes; the live ones are in `UpdateInstallDependencies.live()`.
import AppKit
import Foundation
import OSLog
import Security

private let log = Logger(subsystem: "local.sam.bench", category: "update")

/// Where an install stands: what the popover, the toolbar button and
/// Settings show.
enum InstallPhase: Equatable, Sendable {
    case downloading(received: Int64, expected: Int64?)
    case checking
    /// The swap script is running and Capsid is about to quit.
    case installing
}

/// Why an install stopped. Each case has its sentence; the alert's title
/// names the version that was offered.
enum UpdateInstallFailure: Error, Equatable, Sendable {
    /// The download didn't finish (the reason, in words, for the log).
    case download(String)
    /// Not enough free space for the download and the copy.
    case noRoom(needed: Int64)
    /// The zip held no Capsid.app.
    case noApp
    /// The copy carried a quarantine mark, which this download path never
    /// sets: a tripwire, not a path.
    case quarantined
    /// The copy isn't signed the way this one is, or its seal is broken.
    case signature
    /// The copy says it is another version than the one offered.
    case version(found: String)
    /// The swap script couldn't put the copy in place; the old one is back.
    case swap(String)
    /// The new copy didn't start; the old one is back (shown by it).
    case didNotOpen
    /// This Capsid didn't quit, so the script gave up.
    case didNotQuit
    case cancelled

    /// The alert's text, said to someone running `current` who was offered
    /// `offered`.
    func message(offered: BenchVersion, current: String) -> String {
        let unchanged = "You still have \(current), and nothing was changed."
        switch self {
        case .download:
            return "The download from GitHub stopped before it finished. \(unchanged)"
        case .noRoom(let needed):
            return "There isn\u{2019}t room on this Mac for the new copy (it needs about \(UpdateInstallRules.bytes(needed))). \(unchanged)"
        case .noApp:
            return "The download didn\u{2019}t hold Capsid.app. \(unchanged)"
        case .quarantined:
            return "The downloaded copy was marked as coming from a browser, so Capsid deleted it without opening it. \(unchanged)"
        case .signature:
            return "The downloaded copy isn\u{2019}t signed the way this one is, so Capsid deleted it without opening it. \(unchanged)"
        case .version(let found):
            return "The downloaded copy says it is \(found), not \(offered), so Capsid deleted it without opening it. You still have \(current)."
        case .swap(let reason):
            return "Capsid couldn\u{2019}t put the new copy in Applications: \(reason). The copy you had is back where it was."
        case .didNotOpen:
            return "The new copy didn\u{2019}t start, so Capsid put \(current) back."
        case .didNotQuit:
            return "Capsid didn\u{2019}t quit, so nothing was changed."
        case .cancelled:
            return "The install was cancelled. \(unchanged)"
        }
    }

    /// Whether Try Again is worth offering: the download can be tried again;
    /// a copy that failed its checks will fail them again.
    var canRetry: Bool {
        switch self {
        case .download, .noApp, .didNotQuit: true
        default: false
        }
    }

    /// Whether the alert offers the release notes: a copy that failed its
    /// checks or didn't open is worth reading about.
    var offersNotes: Bool {
        switch self {
        case .signature, .didNotOpen: true
        default: false
        }
    }

    var isCancellation: Bool { self == .cancelled }
}

/// What swap.sh leaves in the state folder's `marker` file.
enum SwapMarker: Equatable, Sendable {
    case installed(version: String)
    case failed(reason: String)
}

enum UpdateInstallRules {
    /// A release's tag, as GitHub has it: `v0.9.8`, or the version alone.
    /// Nothing else, so nothing read off the network can steer the URL.
    static func isTag(_ text: String) -> Bool {
        var rest = Substring(text)
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        let pieces = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return false }
        return pieces.allSatisfy { !$0.isEmpty && $0.count <= 6 && $0.allSatisfy { ("0"..."9").contains($0) } }
    }

    /// The release's Bench.zip, by its tag.
    static func assetURL(tag: String) -> URL? {
        guard isTag(tag) else { return nil }
        return URL(string: "https://github.com/samporter14/bench/releases/download/\(tag)/\(UpdateRules.zipName)")
    }

    /// A download bigger than this isn't Capsid.
    static let maxZipBytes: Int64 = 200 * 1024 * 1024
    /// Free space wanted before downloading: the zip, the copy and room to
    /// spare. Capsid's zip is about 15 MB and its app about 40 MB.
    static let minimumFreeBytes: Int64 = 200 * 1024 * 1024

    /// `~/Library/Caches/local.sam.bench/update`, the state folder: the
    /// download, the unpacked copy, swap.sh's copy, its log and its marker.
    static func stateFolder(caches: URL) -> URL {
        caches.appendingPathComponent("local.sam.bench/update", isDirectory: true)
    }

    /// The environment the swap script gets: this process's, without the
    /// script's test hooks.
    static func swapEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { !$0.key.hasPrefix("CAPSID_SWAP_") }
    }

    /// What the unpacked copy's Info.plist must say.
    static func checkBundle(id: String?, version: String?, offered: BenchVersion) -> UpdateInstallFailure? {
        guard id == "local.sam.bench" else { return .signature }
        guard let version, let found = BenchVersion(version), found == offered else {
            return .version(found: version ?? "nothing")
        }
        return nil
    }

    /// The marker swap.sh wrote: "installed 0.9.8" or "failed: <reason>".
    static func parseMarker(_ text: String) -> SwapMarker? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("installed ") {
            return .installed(version: String(line.dropFirst("installed ".count)))
        }
        if line.hasPrefix("failed: ") {
            return .failed(reason: String(line.dropFirst("failed: ".count)))
        }
        return nil
    }

    /// The failure a marker's reason stands for.
    static func failure(forReason reason: String) -> UpdateInstallFailure {
        if reason.hasPrefix("the new copy didn") { return .didNotOpen }
        if reason.hasPrefix("the running copy didn") { return .didNotQuit }
        return .swap(reason)
    }

    /// The new Capsid removes the copy swap.sh set aside only when that copy
    /// is older than itself: anything else is left for a look.
    static func shouldRemovePrevious(previousVersion: String?, current: String) -> Bool {
        guard let previousVersion, let previous = BenchVersion(previousVersion), let now = BenchVersion(current) else {
            return false
        }
        return previous < now
    }

    /// "3.1 of 9.4 MB", or "3.1 MB" while the size isn't known, or nothing
    /// before the first byte.
    static func progressSentence(version: BenchVersion, received: Int64, expected: Int64?) -> String {
        let lead = "Downloading Capsid \(version)\u{2026} "
        guard let expected, expected > 0 else {
            return received > 0 ? lead + bytes(received) : String(lead.dropLast())
        }
        let got = bytes(received), whole = bytes(expected)
        let gotParts = got.split(separator: " "), wholeParts = whole.split(separator: " ")
        if gotParts.count == 2, wholeParts.count == 2, gotParts[1] == wholeParts[1] {
            return lead + "\(gotParts[0]) of \(whole)"
        }
        return lead + "\(got) of \(whole)"
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }

    /// The card the new Capsid shows once, at the launch after an install.
    static func installedNotice(version: String) -> LabNotice {
        LabNotice(
            id: "updated-\(version)", symbol: "checkmark.circle", caption: "Updated",
            title: "Capsid \(version) is installed",
            detail: "Your sessions kept running in Claude Science.", lifetime: .seconds(15))
    }
}

/// What the swap script is started with.
struct SwapRequest: Equatable, Sendable {
    let script: URL
    let pid: Int32
    let installedApp: URL
    let newApp: URL
    let state: URL
}

/// Every step of an install that touches the disk, the network or the app.
struct UpdateInstallDependencies: Sendable {
    var stateFolder: URL
    var installedApp: URL
    /// Free space on the state folder's volume.
    var freeBytes: @Sendable (URL) -> Int64?
    /// Downloads `url` to the file at the second URL, reporting bytes
    /// received and expected.
    var download: @Sendable (URL, URL, @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Void
    /// Unpacks the zip into the folder.
    var unzip: @Sendable (URL, URL) async throws -> Void
    var isQuarantined: @Sendable (URL) -> Bool
    /// The copy's signature is valid and meets this Capsid's own designated
    /// requirement.
    var meetsRequirement: @Sendable (URL) -> Bool
    /// `codesign --verify --deep --strict` agrees.
    var codesignVerifies: @Sendable (URL) async -> Bool
    /// The copy's bundle id and version.
    var bundleInfo: @Sendable (URL) -> (id: String?, version: String?)
    /// The swap script in this bundle.
    var bundledScript: URL?
    var pid: Int32
    /// Runs the script detached; `onExit` is called if it ends while this
    /// Capsid is still here, with the marker it left.
    var launchSwap: @MainActor @Sendable (SwapRequest, @escaping @MainActor @Sendable (String?) -> Void) throws -> Void
    var terminate: @MainActor @Sendable () -> Void

    static func live() -> UpdateInstallDependencies {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return UpdateInstallDependencies(
            stateFolder: UpdateInstallRules.stateFolder(caches: caches),
            installedApp: URL(fileURLWithPath: UpdateRules.installDirectory, isDirectory: true),
            freeBytes: UpdateDisk.freeBytes,
            download: UpdateDownloader.download,
            unzip: UpdateDisk.unzip,
            isQuarantined: UpdateDisk.isQuarantined,
            meetsRequirement: UpdateSignature.meetsOwnRequirement,
            codesignVerifies: UpdateSignature.codesignVerifies,
            bundleInfo: UpdateDisk.bundleInfo,
            bundledScript: Bundle.main.url(forResource: "swap", withExtension: "sh"),
            pid: ProcessInfo.processInfo.processIdentifier,
            launchSwap: UpdateSwap.launch,
            terminate: { NSApp.terminate(nil) })
    }
}

/// One install, from the download to the swap script's start.
@MainActor
final class UpdateInstallFlow {
    private let dependencies: UpdateInstallDependencies
    private let onPhase: @MainActor (InstallPhase) -> Void

    init(dependencies: UpdateInstallDependencies, onPhase: @escaping @MainActor (InstallPhase) -> Void) {
        self.dependencies = dependencies
        self.onPhase = onPhase
    }

    /// Runs the whole install. Nil means the swap script is running and
    /// `terminate` has been called; a failure means the installed Capsid is
    /// untouched and the download is gone. Cancelling the task cancels the
    /// download and the checks; nothing after the swap's start can be.
    func run(_ update: AvailableUpdate, onSwapExit: @escaping @MainActor @Sendable (String?) -> Void) async -> UpdateInstallFailure? {
        let d = dependencies
        let files = FileManager.default
        guard let url = UpdateInstallRules.assetURL(tag: update.tag) else { return .download("the tag isn't one") }
        let tagFolder = d.stateFolder.appendingPathComponent(update.tag, isDirectory: true)
        let zip = tagFolder.appendingPathComponent(UpdateRules.zipName)
        let unpacked = tagFolder.appendingPathComponent("unpacked", isDirectory: true)
        let newApp = unpacked.appendingPathComponent("Capsid.app", isDirectory: true)
        func abandon() { try? files.removeItem(at: tagFolder) }

        do {
            try? files.removeItem(at: tagFolder)
            try files.createDirectory(at: unpacked, withIntermediateDirectories: true)
        } catch {
            return .download("the state folder couldn't be made")
        }
        if let free = d.freeBytes(d.stateFolder), free < UpdateInstallRules.minimumFreeBytes {
            abandon()
            return .noRoom(needed: UpdateInstallRules.minimumFreeBytes)
        }

        // 1. Download.
        onPhase(.downloading(received: 0, expected: nil))
        let phase = onPhase
        do {
            try await d.download(url, zip) { received, expected in
                Task { @MainActor in phase(.downloading(received: received, expected: expected)) }
            }
        } catch is CancellationError {
            abandon()
            return .cancelled
        } catch let failure as UpdateInstallFailure {
            abandon()
            log.error("Update download failed: \(String(describing: failure), privacy: .public)")
            return failure
        } catch {
            abandon()
            log.error("Update download failed: \(String(describing: error), privacy: .public)")
            return .download(String(describing: error))
        }
        if Task.isCancelled { abandon(); return .cancelled }

        // 2. Check, before anything is quit or moved.
        onPhase(.checking)
        do {
            try await d.unzip(zip, unpacked)
        } catch is CancellationError {
            abandon()
            return .cancelled
        } catch {
            abandon()
            return .noApp
        }
        if Task.isCancelled { abandon(); return .cancelled }
        guard files.fileExists(atPath: newApp.path) else { abandon(); return .noApp }
        if d.isQuarantined(newApp) {
            abandon()
            log.error("The downloaded copy was quarantined")
            return .quarantined
        }
        guard d.meetsRequirement(newApp), await d.codesignVerifies(newApp) else {
            abandon()
            log.error("The downloaded copy didn't meet this copy's signing requirement")
            return .signature
        }
        let info = d.bundleInfo(newApp)
        if let failure = UpdateInstallRules.checkBundle(id: info.id, version: info.version, offered: update.version) {
            abandon()
            return failure
        }
        if Task.isCancelled { abandon(); return .cancelled }

        // 3. Swap: from here on nothing can be cancelled.
        onPhase(.installing)
        guard let bundled = d.bundledScript else { abandon(); return .swap("this copy has no swap script") }
        let script = d.stateFolder.appendingPathComponent("swap.sh")
        do {
            try? files.removeItem(at: script)
            try files.copyItem(at: bundled, to: script)
            try? files.removeItem(at: d.stateFolder.appendingPathComponent("marker"))
            try d.launchSwap(SwapRequest(script: script, pid: d.pid, installedApp: d.installedApp, newApp: newApp,
                                         state: d.stateFolder), onSwapExit)
        } catch {
            abandon()
            return .swap("the swap script couldn't be started")
        }
        log.notice("Update: the swap script is running; quitting")
        d.terminate()
        return nil
    }
}

// MARK: The live steps

enum UpdateDisk {
    @Sendable static func freeBytes(_ folder: URL) -> Int64? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// `ditto -x -k`, as install.sh unpacks the same zip, off the main actor.
    @Sendable static func unzip(_ zip: URL, into folder: URL) async throws {
        let status = await run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        if status != 0 { throw UpdateInstallFailure.noApp }
    }

    @Sendable static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    @Sendable static func bundleInfo(_ app: URL) -> (id: String?, version: String?) {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return (nil, nil) }
        return (plist["CFBundleIdentifier"] as? String, plist["CFBundleShortVersionString"] as? String)
    }

    /// Runs a tool with its output discarded and returns its exit status, or
    /// -1 if it couldn't start.
    static func run(_ tool: String, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(returning: -1) }
        }
    }
}

enum UpdateSignature {
    /// The copy's static code is valid, every nested piece included, and
    /// meets the designated requirement of the code running now: the same
    /// identifier and the same signing certificate. A release signed another
    /// way (an ad-hoc build, or the first one signed with a Developer ID
    /// certificate after self-signed ones) fails here on purpose.
    @Sendable static func meetsOwnRequirement(_ app: URL) -> Bool {
        var me: SecCode?
        var mine: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return meets(app, requirement: requirement)
    }

    static func meets(_ app: URL, requirement: SecRequirement) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    @Sendable static func codesignVerifies(_ app: URL) async -> Bool {
        await UpdateDisk.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0
    }
}

/// The download: one file through the update check's own ephemeral session,
/// with progress, a size cap, and redirects to https only (GitHub hands the
/// file off to its content host).
final class UpdateDownloader: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64?) -> Void
    private let lock = NSLock()
    private var didOverflow = false

    private init(progress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.progress = progress
    }

    @Sendable static func download(_ url: URL, to destination: URL,
                                   progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpShouldHandleCookies = false
        request.setValue("Capsid", forHTTPHeaderField: "User-Agent")
        let delegate = UpdateDownloader(progress: progress)
        let file: URL, response: URLResponse
        do {
            (file, response) = try await UpdateTransport.session.download(for: request, delegate: delegate)
        } catch let error as URLError where error.code == .cancelled {
            // The session says "cancelled" for both: a file over the cap,
            // which the delegate stopped, and the task's own cancellation.
            if delegate.overflowed { throw UpdateInstallFailure.download("the file was too large") }
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        // The file is a temporary that goes away after this returns.
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateInstallFailure.download("GitHub answered with status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
    }

    var overflowed: Bool { lock.withLock { didOverflow } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        request.url?.scheme == "https" ? request : nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        if max(totalBytesWritten, expected ?? 0) > UpdateInstallRules.maxZipBytes {
            lock.withLock { didOverflow = true }
            downloadTask.cancel()
            return
        }
        progress(totalBytesWritten, expected)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async `download(for:)` moves the file itself.
    }
}

/// Starts swap.sh detached: its output goes to its own log, and it carries
/// on after this Capsid has quit, which is the first thing it waits for.
@MainActor
enum UpdateSwap {
    static func launch(_ request: SwapRequest, onExit: @escaping @MainActor @Sendable (String?) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [request.script.path, String(request.pid), request.installedApp.path, request.newApp.path,
                             request.state.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = UpdateInstallRules.swapEnvironment(ProcessInfo.processInfo.environment)
        let marker = request.state.appendingPathComponent("marker")
        process.terminationHandler = { _ in
            let text = try? String(contentsOf: marker, encoding: .utf8)
            Task { @MainActor in onExit(text) }
        }
        try process.run()
    }
}

// MARK: A dry run from the command line

/// `Capsid --update-dry-run <tag>`: downloads that release's Bench.zip into
/// a folder of its own, unpacks it and runs every check the real install
/// runs, prints each step, and stops before the swap: nothing is quit,
/// moved or opened. It is how the live download and the signature check are
/// tried against a real release (TESTING.md) without a newer one existing.
enum UpdateDryRun {
    @MainActor
    static func runIfAsked() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--update-dry-run") else { return }
        let tag = flag + 1 < CommandLine.arguments.count ? CommandLine.arguments[flag + 1] : ""
        Task { @MainActor in exit(await run(tag: tag)) }
        // Nothing else runs: the task above ends the process.
        RunLoop.main.run()
    }

    @MainActor
    static func run(tag: String) async -> Int32 {
        guard UpdateInstallRules.isTag(tag), let version = BenchVersion(tag) else {
            print("Usage: Capsid --update-dry-run <tag>   (a release's tag, such as v0.9.7)")
            return 2
        }
        var live = UpdateInstallDependencies.live()
        live.stateFolder = live.stateFolder.deletingLastPathComponent().appendingPathComponent("update-dry-run", isDirectory: true)
        live.launchSwap = { request, _ in
            print("Would run \(request.script.path) \(request.pid) \(request.installedApp.path) \(request.newApp.path) \(request.state.path)")
        }
        live.terminate = { print("Would quit here. Dry run: nothing was moved, quit or opened.") }
        print("Dry run of an install of \(tag) into a scratch folder: \(live.stateFolder.path)")
        let flow = UpdateInstallFlow(dependencies: live) { phase in
            switch phase {
            case .downloading(let received, let expected):
                if received == 0 { print("Downloading \(UpdateInstallRules.assetURL(tag: tag)?.absoluteString ?? "")") }
                if let expected, received == expected { print("Downloaded \(UpdateInstallRules.bytes(received))") }
            case .checking: print("Checking: unpacking, quarantine, this copy's designated requirement, codesign --verify --deep --strict, bundle id and version")
            case .installing: print("Checks passed: the copy is Capsid \(version), signed the way this one is")
            }
        }
        let update = AvailableUpdate(version: version, notesURL: UpdateRules.releasesPage, tag: tag)
        let failure = await flow.run(update) { _ in }
        try? FileManager.default.removeItem(at: live.stateFolder)
        if let failure {
            print("Stopped: \(failure)")
            print(failure.message(offered: version, current: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))
            return 1
        }
        return 0
    }
}

// MARK: After a launch

/// What the state folder says at launch: a copy was just installed (the
/// old one waits beside it to be removed), or the swap failed and this is
/// the copy that was put back.
///
/// The old copy beside a new one is the swap's way back, so it is removed
/// only after the handshake: swap.sh opens the new copy, waits until it runs,
/// looks again two seconds later (a copy that dies on launch is seen running
/// for an instant) and only then writes `installed <version>`. A new copy that
/// reaches its own launch clean-up before that must leave the old one alone:
/// if it then crashes, swap.sh moves it away and needs the old copy at
/// `.previous` to put back.
enum UpdateAftermath {
    enum Outcome: Equatable, Sendable {
        case nothing
        case installed(version: String)
        case failed(UpdateInstallFailure, offered: String?)
        /// An older copy sits beside this one, but swap.sh hasn't written
        /// its marker yet: nothing was removed, and a later look will say.
        case waiting
    }

    /// How often `run` looks again while the outcome is `.waiting`, and for
    /// how long in all.
    static let retryInterval: Duration = .seconds(2)
    static let retryLimit: Duration = .seconds(30)

    /// Reads the marker and the `.previous` copy, removes what is finished
    /// with, and says what happened. `remove` is injected so the tests
    /// never delete anything real.
    static func settle(stateFolder: URL, installedApp: URL, currentVersion: String,
                       bundleInfo: (URL) -> (id: String?, version: String?),
                       remove: (URL) -> Void) -> Outcome {
        let files = FileManager.default
        let previous = URL(fileURLWithPath: installedApp.path + ".previous", isDirectory: true)
        let markerText = try? String(contentsOf: stateFolder.appendingPathComponent("marker"), encoding: .utf8)
        let marker = markerText.flatMap(UpdateInstallRules.parseMarker)
        // The tag folder names the version that was offered.
        let offered = (try? files.contentsOfDirectory(atPath: stateFolder.path))?
            .first(where: UpdateInstallRules.isTag)

        var outcome = Outcome.nothing
        if case .failed(let reason) = marker {
            outcome = .failed(UpdateInstallRules.failure(forReason: reason), offered: offered)
            remove(stateFolder)
        } else if files.fileExists(atPath: previous.path) {
            let previousVersion = bundleInfo(previous).version
            let isOlder = UpdateInstallRules.shouldRemovePrevious(previousVersion: previousVersion, current: currentVersion)
            if case .installed = marker {
                if isOlder {
                    remove(previous)
                    outcome = .installed(version: currentVersion)
                } else {
                    log.error("A copy beside this one wasn't removed: it isn't older")
                }
                remove(stateFolder)
            } else if isOlder {
                // No marker yet: swap.sh is still looking at this copy, and may
                // yet need the old one back. Remove nothing.
                outcome = .waiting
            } else {
                log.error("A copy beside this one wasn't removed: it isn't older")
            }
        } else if case .installed = marker {
            outcome = .installed(version: currentVersion)
            remove(stateFolder)
        }
        return outcome
    }

    /// `settle` once now and, while it answers `.waiting`, again every
    /// `interval` until `limit` has gone by, then says what happened as `run`
    /// always has: the notice for an install, the alert for a failed swap.
    /// The first look is made before this returns; the returned task, nil when
    /// the first look settled things, holds the later ones. Past the limit the
    /// old copy is left where it is (the next update's swap.sh moves a stale
    /// one into the state folder) and one line goes to the log. `sleep` is
    /// injected so the tests don't wait.
    @MainActor
    @discardableResult
    static func settleAndReport(
        stateFolder: URL, installedApp: URL, currentVersion: String,
        bundleInfo: @escaping @Sendable (URL) -> (id: String?, version: String?),
        remove: @escaping @Sendable (URL) -> Void,
        post: @escaping @MainActor @Sendable (LabNotice) -> Void,
        alert: @escaping @MainActor @Sendable (UpdateInstallFailure, String?) -> Void,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        interval: Duration = retryInterval, limit: Duration = retryLimit) -> Task<Void, Never>? {
        func look() -> Outcome {
            settle(stateFolder: stateFolder, installedApp: installedApp, currentVersion: currentVersion,
                   bundleInfo: bundleInfo, remove: remove)
        }
        let first = look()
        guard first == .waiting else {
            report(first, post: post, alert: alert)
            return nil
        }
        return Task { @MainActor in
            var waited = Duration.zero
            var outcome = Outcome.waiting
            while outcome == .waiting, waited < limit {
                await sleep(interval)
                if Task.isCancelled { return }
                waited += interval
                outcome = look()
            }
            report(outcome, post: post, alert: alert)
        }
    }

    @MainActor
    private static func report(_ outcome: Outcome, post: @MainActor (LabNotice) -> Void,
                               alert: @MainActor (UpdateInstallFailure, String?) -> Void) {
        switch outcome {
        case .nothing: break
        case .installed(let version):
            log.notice("Update: \(version, privacy: .public) is installed; the old copy is gone")
            post(UpdateInstallRules.installedNotice(version: version))
        case .failed(let failure, let offered):
            log.error("Update: the swap failed: \(String(describing: failure), privacy: .public)")
            alert(failure, offered)
        case .waiting:
            log.notice("Update: the swap script never wrote its marker; the old copy was left beside this one")
        }
    }

    /// At launch, for the copy in Applications, never in a demo.
    @MainActor
    static func run(currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    post: @escaping @MainActor @Sendable (LabNotice) -> Void = { LabModel.shared.post($0) },
                    alert: @escaping @MainActor @Sendable (UpdateInstallFailure, String?) -> Void = { UpdatePrompts.installFailedAtLaunch($0, offered: $1) }) {
        guard Demo.mode == nil, UpdateRules.canInstall(from: Bundle.main.bundleURL) else { return }
        let live = UpdateInstallDependencies.live()
        settleAndReport(stateFolder: live.stateFolder, installedApp: live.installedApp, currentVersion: currentVersion,
                        bundleInfo: live.bundleInfo, remove: { try? FileManager.default.removeItem(at: $0) },
                        post: post, alert: alert)
    }
}
