// UpdateCheck.swift — the check for a newer Bench (DESIGN.md, Update check).
// Bench asks GitHub for its latest release once a day, unless the user turned
// that off in Settings, or when they ask with Check Now or the app menu. It
// reads the release's tag, its page and whether it has a Bench.zip, and sends
// nothing about the user or their sessions. A version can be skipped: the
// card, the toolbar button and the Dock item stop offering it, and a newer
// one is offered again.
//
// `UpdateRules` is pure, so the tests run it on made-up releases and clocks.
// `UpdateChecker` takes its fetch as a parameter, so they never go online.
import AppKit
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "update")

/// A Bench version: dotted numbers, as in a bundle's version or a release's
/// tag. A leading `v` is ignored; anything else (`-beta`, `latest`, an empty
/// string) isn't a version, so it can never count as newer.
struct BenchVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ text: String) {
        var text = Substring(text)
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            // ASCII digits only: Int("+1") would pass, and so would "-0".
            guard !piece.isEmpty, piece.count <= 6, piece.allSatisfy({ ("0"..."9").contains($0) }),
                  let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// 0.3 and 0.3.0 are the same version.
    private func padded(to count: Int) -> [Int] {
        parts + Array(repeating: 0, count: max(0, count - parts.count))
    }

    static func == (a: BenchVersion, b: BenchVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count) == b.padded(to: count)
    }

    static func < (a: BenchVersion, b: BenchVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        return a.padded(to: count).lexicographicallyPrecedes(b.padded(to: count))
    }
}

/// What GitHub's `releases/latest` says, reduced to what Bench uses.
struct GitHubRelease: Equatable, Sendable {
    /// Nil for a draft, a pre-release or a tag that isn't a version.
    let version: BenchVersion?
    let notesURL: URL
    /// Whether the release has a Bench.zip, which the installer downloads.
    let hasZip: Bool
}

/// A newer Bench that can be installed.
struct AvailableUpdate: Equatable, Sendable {
    let version: BenchVersion
    let notesURL: URL
}

/// Why a check gave no answer.
enum CheckFailure: Error, Equatable, Sendable {
    /// This copy has no version to compare with (an unbundled run).
    case noVersion
    case unreachable
    case http(Int)
    case unreadable

    var message: String {
        switch self {
        case .noVersion: "This copy of Capsid has no version number."
        case .unreachable: "Capsid couldn’t reach GitHub."
        case .http(404): "GitHub has no Capsid release yet."
        case .http(403), .http(429): "GitHub is limiting requests from this network. Try again later."
        case .http(let status): "GitHub answered with status \(status)."
        case .unreadable: "GitHub’s answer wasn’t a Capsid release."
        }
    }
}

enum UpdateRules {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/samporter14/bench/releases/latest")!
    /// Where release notes go when GitHub's own link can't be trusted.
    static let releasesPage = URL(string: "https://github.com/samporter14/bench/releases/latest")!
    /// The README's install line, run as it stands. It is a constant, never
    /// read from the network.
    static let installLine = "curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh | zsh"
    static let installDirectory = "/Applications/Capsid.app"
    static let zipName = "Bench.zip"

    /// One automatic check a day.
    static let interval: TimeInterval = 24 * 3600
    /// After an automatic check that failed, the next try.
    static let retryDelay: TimeInterval = 3600
    /// Bench has been open this long before the first automatic check.
    static let launchDelay: Duration = .seconds(30)
    /// After the switch is turned on, the first check comes this soon.
    static let enabledDelay: Duration = .seconds(3)

    // MARK: Asking

    /// The request, with only what GitHub needs: the API's media type and a
    /// fixed name. No cookies, no account, no identifier, and the language
    /// header is fixed so the system's preferences aren't sent.
    static func request(appVersion: String) -> URLRequest {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Capsid/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    // MARK: Reading the answer

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?

        struct Asset: Decodable { let name: String? }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
        }
    }

    /// The release in GitHub's JSON, or nil when it isn't one.
    static func parse(_ data: Data) -> GitHubRelease? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let stable = payload.draft != true && payload.prerelease != true
        let version = stable ? BenchVersion(payload.tagName) : nil
        return GitHubRelease(
            version: version,
            notesURL: notesURL(payload.htmlURL, version: version),
            hasZip: payload.assets?.contains { $0.name == zipName } ?? false)
    }

    /// GitHub's `html_url` when it really is a page of Bench's releases; the
    /// answer came off the network and is opened in a browser. Otherwise the
    /// page the version's tag has, or the list of releases.
    static func notesURL(_ text: String?, version: BenchVersion?) -> URL {
        if let text, let url = URL(string: text), url.scheme == "https", url.host?.lowercased() == "github.com",
           url.path.lowercased().hasPrefix("/samporter14/bench/releases") {
            return url
        }
        if let version, let url = URL(string: "https://github.com/samporter14/bench/releases/tag/v\(version)") {
            return url
        }
        return releasesPage
    }

    // MARK: Comparing

    /// Whether `tag` (`v0.3.6`) names a newer version than `current`
    /// (`0.3.5`). Numbers are compared one by one, not as text, and a tag
    /// or a version that isn't a version is never newer.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let tag = BenchVersion(tag), let current = BenchVersion(current) else { return false }
        return tag > current
    }

    /// The update to offer: a stable release that is newer than this one and
    /// has the Bench.zip the installer downloads. One without it is not
    /// offered yet, and comes when the file does.
    static func offer(_ release: GitHubRelease, current: BenchVersion) -> AvailableUpdate? {
        guard let version = release.version, version > current, release.hasZip else { return nil }
        return AvailableUpdate(version: version, notesURL: release.notesURL)
    }

    /// What Settings shows at launch, before any check: the newest version
    /// seen last time if it is still newer than this one, else "up to date"
    /// once a check has been made.
    static func restoredState(newest: String?, current: String, hasChecked: Bool) -> UpdateChecker.State {
        guard let current = BenchVersion(current) else { return .idle }
        if let newest = newest.flatMap(BenchVersion.init), newest > current {
            return .available(AvailableUpdate(version: newest, notesURL: notesURL(nil, version: newest)))
        }
        return hasChecked ? .upToDate(current.description) : .idle
    }

    // MARK: When

    /// Whether the daily check is due. A last check in the future means the
    /// clock moved back, which must not keep checks away for good.
    static func isDue(lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        return elapsed >= interval || elapsed < 0
    }

    /// How long until it is due: nothing if it is now.
    static func delayUntilDue(lastChecked: Date?, now: Date) -> TimeInterval {
        guard !isDue(lastChecked: lastChecked, now: now), let lastChecked else { return 0 }
        return interval - now.timeIntervalSince(lastChecked)
    }

    // MARK: Telling

    /// A version gets one card: not again for the same one, nor for an
    /// older one. A newer one gets its own.
    static func shouldAnnounce(_ version: BenchVersion, announced: String?) -> Bool {
        guard let announced = announced.flatMap(BenchVersion.init) else { return true }
        return version > announced
    }

    /// Whether `version` is still worth offering, given the one the user
    /// skipped (`updateSkippedVersion`): the card, the toolbar button and the
    /// Dock item all ask. Skipping a version hushes it and anything older,
    /// never a newer one. Nothing stored, or something that isn't a version,
    /// hushes nothing.
    static func shouldOffer(_ version: BenchVersion, skipped: String?) -> Bool {
        guard let skipped = skipped.flatMap(BenchVersion.init) else { return true }
        return version > skipped
    }

    /// The card, with Install… on it: that opens the same alert as the Dock
    /// item (`UpdatePrompts.offer`).
    static func notice(for update: AvailableUpdate) -> LabNotice {
        LabNotice(
            id: "update-\(update.version)", symbol: "arrow.down.app", caption: "Update",
            title: "Capsid \(update.version) is available",
            detail: "Install now, or any time from Update in the toolbar", lifetime: .seconds(15),
            action: .installUpdate(update))
    }

    /// What Install does, said before it does it.
    static func installSentence(_ version: BenchVersion) -> String {
        "Capsid will quit, download \(version) from GitHub and reopen. Your sessions keep running in Claude Science."
    }

    static let cannotInstallHere =
        "This copy of Capsid isn\u{2019}t in Applications, so it can\u{2019}t replace itself. Run the install line from the README in Terminal."

    /// The installer replaces /Applications/Capsid.app and quits only that
    /// copy. Run from anywhere else it would open a second Capsid beside the
    /// one running.
    static func canInstall(from bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.path == installDirectory
    }
}

/// The one place Bench goes online by itself: an ephemeral session with no
/// cookies, no cache and no credentials.
enum UpdateTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    enum State: Equatable {
        /// Nothing checked yet.
        case idle
        case checking
        /// The version running, which is the newest there is.
        case upToDate(String)
        case available(AvailableUpdate)
        case failed(CheckFailure)
    }

    /// Whether a check is Bench's own, on its schedule, or was asked for. Only
    /// the first posts a card: whoever asked is already looking.
    enum Trigger { case scheduled, requested }

    @Published private(set) var state: State
    /// When the last check that got an answer was made: what Settings shows.
    @Published private(set) var lastChecked: Date?
    /// The installer is running: Bench is about to quit.
    @Published private(set) var installing = false
    /// The newest version the user chose to skip (`updateSkippedVersion`), as
    /// text. Settings and the app menu still show it: those are explicit asks.
    @Published private(set) var skippedVersion: String?

    let currentVersion: String

    private enum Key {
        static let lastChecked = "updateLastChecked"
        static let lastAsked = "updateLastAsked"
        static let newestVersion = "updateNewestVersion"
        static let announcedVersion = "updateAnnouncedVersion"
        static let skippedVersion = "updateSkippedVersion"
    }

    private let defaults: UserDefaults
    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private let isDemo: Bool
    private let post: @MainActor (LabNotice) -> Void
    private let launchDelay: Duration
    private let enabledDelay: Duration
    /// When Bench last got any response from GitHub, an answer or not. The
    /// schedule counts from this, so a GitHub that refuses isn't asked again
    /// until tomorrow.
    private var lastAsked: Date?
    private var inFlight: Task<State, Never>?
    private var loop: Task<Void, Never>?
    private var observer: AnyCancellable?
    private var wasEnabled = false

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
         fetch: @escaping Fetch = UpdateTransport.fetch,
         now: @escaping @Sendable () -> Date = { Date() },
         isDemo: Bool = Demo.mode != nil,
         launchDelay: Duration = UpdateRules.launchDelay,
         enabledDelay: Duration = UpdateRules.enabledDelay,
         post: @escaping @MainActor (LabNotice) -> Void = { LabModel.shared.post($0) }) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.fetch = fetch
        self.now = now
        self.isDemo = isDemo
        self.post = post
        self.launchDelay = launchDelay
        self.enabledDelay = enabledDelay
        let stored = (defaults.object(forKey: Key.lastChecked) as? Double).map(Date.init(timeIntervalSince1970:))
        lastChecked = stored
        lastAsked = (defaults.object(forKey: Key.lastAsked) as? Double).map(Date.init(timeIntervalSince1970:))
        skippedVersion = defaults.string(forKey: Key.skippedVersion)
        state = UpdateRules.restoredState(
            newest: defaults.string(forKey: Key.newestVersion), current: currentVersion, hasChecked: stored != nil)
    }

    isolated deinit {
        loop?.cancel()
    }

    /// Whether Settings has the daily check on.
    var enabled: Bool { defaults.bool(forKey: SettingsKey.checkForUpdates) }

    // MARK: Offering

    /// The update to put in front of the user unasked: the toolbar button,
    /// the Dock item. The one `state` holds, unless they skipped it.
    var offered: AvailableUpdate? {
        guard case .available(let update) = state,
              UpdateRules.shouldOffer(update.version, skipped: skippedVersion) else { return nil }
        return update
    }

    /// Skip This Version: nothing offers it again, but a newer one is offered.
    /// `state` stays as it is, so Settings and the app menu still show it.
    func skip(_ update: AvailableUpdate) {
        let version = update.version.description
        skippedVersion = version
        defaults.set(version, forKey: Key.skippedVersion)
    }

    // MARK: On a schedule

    /// At launch. With the setting on, the first look comes after 30 seconds
    /// and the next ones when a day has passed. With it off nothing is
    /// scheduled at all, and turning it on, here or in the welcome window,
    /// starts it. Never in a demo.
    func start() {
        guard !isDemo, observer == nil else { return }
        wasEnabled = enabled
        observer = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingMayHaveChanged() }
        if wasEnabled { schedule(after: launchDelay) }
    }

    private func settingMayHaveChanged() {
        let isOn = enabled
        guard isOn != wasEnabled else { return }
        wasEnabled = isOn
        if isOn {
            schedule(after: enabledDelay)
        } else {
            loop?.cancel()
            loop = nil
        }
    }

    private func schedule(after delay: Duration) {
        loop?.cancel()
        loop = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                guard let wait = await self?.checkIfDue() else { return }
                try? await Task.sleep(for: .seconds(max(wait, 60)), tolerance: .seconds(300))
            }
        }
    }

    /// The automatic check: asks GitHub only if the setting is on and a day
    /// has passed since it last responded. Returns how long to wait before
    /// looking again: a day, or an hour after a try that never reached GitHub.
    @discardableResult
    func checkIfDue() async -> TimeInterval {
        guard enabled, !isDemo else { return UpdateRules.interval }
        if UpdateRules.isDue(lastChecked: lastAsked, now: now()) {
            switch await perform(.scheduled) {
            case .failed(.unreachable): return UpdateRules.retryDelay
            case .failed(.noVersion): return UpdateRules.interval
            default: break
            }
        }
        return UpdateRules.delayUntilDue(lastChecked: lastAsked, now: now())
    }

    // MARK: When asked

    /// Check Now and the app menu's Check for Updates…: asks at once, setting
    /// or not. A check already under way answers for both.
    @discardableResult
    func checkNow() async -> State {
        guard !isDemo else { return state }
        return await perform(.requested)
    }

    private func perform(_ trigger: Trigger) async -> State {
        if let inFlight { return await inFlight.value }
        let task = Task { @MainActor [self] in
            let result = await run(trigger)
            inFlight = nil
            return result
        }
        inFlight = task
        return await task.value
    }

    private func run(_ trigger: Trigger) async -> State {
        guard let current = BenchVersion(currentVersion) else {
            state = .failed(.noVersion)
            return state
        }
        state = .checking
        do {
            let (data, response) = try await fetch(UpdateRules.request(appVersion: current.description))
            // GitHub responded, so today's ask is made, whatever it said.
            let askedAt = now()
            lastAsked = askedAt
            defaults.set(askedAt.timeIntervalSince1970, forKey: Key.lastAsked)
            guard let http = response as? HTTPURLResponse else { throw CheckFailure.unreadable }
            guard http.statusCode == 200 else { throw CheckFailure.http(http.statusCode) }
            guard let release = UpdateRules.parse(data) else { throw CheckFailure.unreadable }
            lastChecked = askedAt
            defaults.set(askedAt.timeIntervalSince1970, forKey: Key.lastChecked)
            guard let update = UpdateRules.offer(release, current: current) else {
                defaults.removeObject(forKey: Key.newestVersion)
                log.info("Update check: up to date")
                state = .upToDate(current.description)
                return state
            }
            defaults.set(update.version.description, forKey: Key.newestVersion)
            // Once per version, whoever finds it first. Whoever asked sees the
            // answer, so only a check on the schedule posts the card, and not
            // for a version that was skipped.
            if UpdateRules.shouldAnnounce(update.version, announced: defaults.string(forKey: Key.announcedVersion)) {
                defaults.set(update.version.description, forKey: Key.announcedVersion)
                if trigger == .scheduled, UpdateRules.shouldOffer(update.version, skipped: skippedVersion) {
                    post(UpdateRules.notice(for: update))
                }
            }
            log.notice("Update check: a newer version is out")
            state = .available(update)
            return state
        } catch let failure as CheckFailure {
            log.error("Update check failed: \(String(describing: failure), privacy: .public)")
            state = .failed(failure)
            return state
        } catch {
            log.error("Update check failed: unreachable")
            state = .failed(.unreachable)
            return state
        }
    }

    // MARK: Installing

    /// Runs the README's install line, which quits this Bench, replaces it
    /// and opens the new one. Callers have said so first.
    func install() {
        guard case .available(let update) = state, !installing,
              UpdateRules.canInstall(from: Bundle.main.bundleURL) else { return }
        installing = true
        log.notice("Installing an update")
        do {
            try UpdateInstaller.launch { [weak self] in self?.installerExited(update) }
        } catch {
            installerExited(update)
        }
    }

    /// The installer ended while Bench is still here. When it works, Bench
    /// has been quit before it ends, so this means it didn't.
    private func installerExited(_ update: AvailableUpdate) {
        installing = false
        log.error("The installer ended without replacing Bench")
        UpdatePrompts.installFailed(update)
    }
}

/// Starts the install line the way the README has it, detached: its output
/// goes nowhere, and it carries on after this Bench has been quit, which is
/// the first thing it does.
@MainActor
enum UpdateInstaller {
    static func launch(onExit: @escaping @MainActor () -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", UpdateRules.installLine]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // The script's own switch for testing it; an update is always a real
        // install into Applications.
        var environment = ProcessInfo.processInfo.environment
        environment["BENCH_INSTALL_DIR"] = nil
        process.environment = environment
        process.terminationHandler = { _ in Task { @MainActor in onExit() } }
        try process.run()
    }
}
