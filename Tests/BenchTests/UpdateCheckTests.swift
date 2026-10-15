// UpdateCheckTests.swift — the update check on made-up releases and clocks.
// Nothing here goes online: the checker is given a fetch that records what it
// is asked and answers from a fixture, and keeps its state in a scratch
// UserDefaults suite, never Bench's own.
import Foundation
import Testing
@testable import Bench

// MARK: Fixtures

private enum Release {
    static func json(tag: String = "v0.3.6", url: String? = "https://github.com/samporter14/bench/releases/tag/v0.3.6",
                     assets: [String]? = ["Bench.zip"], draft: Bool = false, prerelease: Bool = false) -> String {
        var fields = ["\"tag_name\": \"\(tag)\"", "\"draft\": \(draft)", "\"prerelease\": \(prerelease)",
                      "\"name\": \"Made-up notes\"", "\"author\": {\"login\": \"someone\"}"]
        if let url { fields.append("\"html_url\": \"\(url)\"") }
        if let assets {
            let list = assets.map { "{\"name\": \"\($0)\", \"size\": 3100000, \"state\": \"uploaded\"}" }
            fields.append("\"assets\": [\(list.joined(separator: ", "))]")
        }
        return "{\(fields.joined(separator: ", "))}"
    }

    static func reply(_ json: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(json.utf8),
         HTTPURLResponse(url: UpdateRules.latestReleaseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

/// Stands in for the network: records every request, and answers from the
/// closure given the number of the call (the first is 1).
private final class FakeNetwork: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let delay: Duration
    private let answer: @Sendable (Int) throws -> (Data, URLResponse)

    init(delay: Duration = .zero, answer: @escaping @Sendable (Int) throws -> (Data, URLResponse)) {
        self.delay = delay
        self.answer = answer
    }

    /// Always the same release.
    convenience init(json: String, status: Int = 200) {
        self.init { _ in Release.reply(json, status: status) }
    }

    var requests: [URLRequest] { lock.withLock { recorded } }
    var calls: Int { requests.count }

    @Sendable func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let number = lock.withLock { () -> Int in
            recorded.append(request)
            return recorded.count
        }
        if delay != .zero { try await Task.sleep(for: delay) }
        return try answer(number)
    }
}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = date }

    var date: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current = current.addingTimeInterval(hours * 3600) } }
}

@MainActor
private final class Posted {
    var notices: [LabNotice] = []
}

private struct Scratch {
    let defaults: UserDefaults
    private let name: String

    init() {
        name = "bench-update-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
    }

    func clean() { defaults.removePersistentDomain(forName: name) }
}

@MainActor
private func checker(_ scratch: Scratch, network: FakeNetwork, clock: FakeClock = FakeClock(), posted: Posted = Posted(),
                     current: String = "0.3.5", enabled: Bool, isDemo: Bool = false,
                     launchDelay: Duration = .seconds(30), enabledDelay: Duration = .seconds(3)) -> UpdateChecker {
    scratch.defaults.set(enabled, forKey: SettingsKey.checkForUpdates)
    return UpdateChecker(defaults: scratch.defaults, currentVersion: current, fetch: network.fetch,
                         now: { clock.date }, isDemo: isDemo, launchDelay: launchDelay, enabledDelay: enabledDelay,
                         post: { posted.notices.append($0) })
}

/// Waits for `condition`, up to a few seconds.
@MainActor
private func until(_ condition: () -> Bool) async throws {
    for _ in 0..<300 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: Versions

struct VersionCompareTests {
    @Test func aTagIsNewerWhenItsNumbersAre() {
        #expect(UpdateRules.isNewer("v0.3.6", than: "0.3.5"))
        #expect(UpdateRules.isNewer("0.4.0", than: "0.3.9"))
        #expect(UpdateRules.isNewer("v1.0.0", than: "0.9.9"))
        #expect(UpdateRules.isNewer("v0.3.5.1", than: "0.3.5"))
    }

    @Test func numbersAreComparedAsNumbersNotAsText() {
        #expect(UpdateRules.isNewer("v0.3.10", than: "0.3.9"))
        #expect(!UpdateRules.isNewer("v0.3.9", than: "0.3.10"))
        #expect(UpdateRules.isNewer("v0.10.0", than: "0.9.0"))
    }

    @Test func theSameOrOlderIsNotNewer() {
        #expect(!UpdateRules.isNewer("v0.3.5", than: "0.3.5"))
        #expect(!UpdateRules.isNewer("v0.3.4", than: "0.3.5"))
        #expect(!UpdateRules.isNewer("v0.2.99", than: "0.3.5"))
    }

    @Test func missingTrailingZerosChangeNothing() throws {
        #expect(!UpdateRules.isNewer("v0.3", than: "0.3.0"))
        #expect(!UpdateRules.isNewer("0.3.0", than: "v0.3"))
        #expect(try #require(BenchVersion("1.0")) == #require(BenchVersion("1.0.0")))
        #expect(UpdateRules.isNewer("v1", than: "0.9.9"))
    }

    @Test func aLeadingVIsIgnored() throws {
        #expect(try #require(BenchVersion("v0.3.6")).description == "0.3.6")
        #expect(try #require(BenchVersion("0.3.6")).description == "0.3.6")
        #expect(try #require(BenchVersion("v0.3.6")) == #require(BenchVersion("0.3.6")))
    }

    @Test func preReleasesAndGarbageAreIgnored() {
        for tag in ["v0.4.0-beta", "v0.4.0-beta.1", "0.4.0-rc1", "v0.4.0+build5", "v0.4.x", "latest", "nightly", "",
                    "v", "vv0.4.0", "0.4..1", ".4", "0.4.", "1.2.3.4.5", "+1.0", "-1.0", " 0.4.0", "0.4.0\n",
                    "\u{0663}.\u{0664}", "9999999.0.0"] {
            #expect(BenchVersion(tag) == nil, "\(tag.debugDescription) is not a version")
            #expect(!UpdateRules.isNewer(tag, than: "0.3.5"), "\(tag.debugDescription) is never newer")
        }
    }

    @Test func aRunningVersionThatIsNotOneIsNeverOutOfDate() {
        #expect(!UpdateRules.isNewer("v9.9.9", than: ""))
        #expect(!UpdateRules.isNewer("v9.9.9", than: "(unbundled)"))
    }
}

// MARK: The answer

struct ReleaseParsingTests {
    @Test func aReleaseWithItsZip() throws {
        let release = try #require(UpdateRules.parse(Data(Release.json().utf8)))
        #expect(release.version?.description == "0.3.6")
        #expect(release.hasZip)
        #expect(release.notesURL.absoluteString == "https://github.com/samporter14/bench/releases/tag/v0.3.6")
    }

    @Test func aReleaseWithoutTheZipIsNotOneToInstall() throws {
        for assets in [["Source.tar.gz", "Bench.zip.sha256"], [], nil] as [[String]?] {
            let release = try #require(UpdateRules.parse(Data(Release.json(assets: assets).utf8)))
            #expect(!release.hasZip)
            #expect(UpdateRules.offer(release, current: try #require(BenchVersion("0.3.5"))) == nil)
        }
    }

    @Test func draftsPreReleasesAndOddTagsHaveNoVersion() throws {
        for json in [Release.json(draft: true), Release.json(prerelease: true), Release.json(tag: "v0.4.0-beta"),
                     Release.json(tag: "nightly")] {
            #expect(try #require(UpdateRules.parse(Data(json.utf8))).version == nil)
        }
    }

    @Test func somethingThatIsNotAReleaseIsNil() {
        #expect(UpdateRules.parse(Data()) == nil)
        #expect(UpdateRules.parse(Data("<html>Rate limited</html>".utf8)) == nil)
        #expect(UpdateRules.parse(Data("{\"message\": \"Not Found\"}".utf8)) == nil)
        #expect(UpdateRules.parse(Data("[]".utf8)) == nil)
    }

    @Test func aReleasePageIsOnlyTrustedWhenItIsGitHubsPageOfBenchsReleases() throws {
        let tag = "https://github.com/samporter14/bench/releases/tag/v0.3.6"
        let fallback = "https://github.com/samporter14/bench/releases/tag/v0.3.6"
        for page in ["https://evil.example/samporter14/bench/releases/tag/v0.3.6",
                     "http://github.com/samporter14/bench/releases/tag/v0.3.6",
                     "https://github.com.evil.example/samporter14/bench/releases/tag/v0.3.6",
                     "https://github.com/someone/else/releases/tag/v0.3.6",
                     "https://github.com/samporter14/bench/issues/1",
                     "javascript:alert(1)", "file:///Applications/Bench.app", "not a url at all"] {
            let release = try #require(UpdateRules.parse(Data(Release.json(url: page).utf8)))
            #expect(release.notesURL.absoluteString == fallback, "\(page) is not trusted")
        }
        #expect(try #require(UpdateRules.parse(Data(Release.json(url: tag).utf8))).notesURL.absoluteString == tag)
        // No link at all: the tag's page, or the list when the tag isn't a version.
        #expect(try #require(UpdateRules.parse(Data(Release.json(url: nil).utf8))).notesURL.absoluteString == fallback)
        #expect(try #require(UpdateRules.parse(Data(Release.json(tag: "nightly", url: nil).utf8))).notesURL
            == UpdateRules.releasesPage)
    }

    @Test func onlyANewerReleaseWithItsZipIsOffered() throws {
        let current = try #require(BenchVersion("0.3.5"))
        func offered(_ tag: String, zip: Bool = true) throws -> AvailableUpdate? {
            let assets = zip ? ["Bench.zip"] : []
            return UpdateRules.offer(try #require(UpdateRules.parse(Data(Release.json(tag: tag, assets: assets).utf8))),
                                     current: current)
        }
        #expect(try offered("v0.3.6")?.version.description == "0.3.6")
        #expect(try offered("v0.3.5") == nil)
        #expect(try offered("v0.3.4") == nil)
        #expect(try offered("v0.3.6", zip: false) == nil)
        #expect(try offered("v0.3.6-beta") == nil)
    }
}

// MARK: When

struct UpdateScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    @Test func neverCheckedIsDue() {
        #expect(UpdateRules.isDue(lastChecked: nil, now: now))
        #expect(UpdateRules.delayUntilDue(lastChecked: nil, now: now) == 0)
    }

    @Test func notDueUntilADayHasPassed() {
        #expect(!UpdateRules.isDue(lastChecked: now, now: now))
        #expect(!UpdateRules.isDue(lastChecked: ago(hours: 1), now: now))
        #expect(!UpdateRules.isDue(lastChecked: ago(hours: 23.9), now: now))
        #expect(UpdateRules.isDue(lastChecked: ago(hours: 24), now: now))
        #expect(UpdateRules.isDue(lastChecked: ago(hours: 25), now: now))
        #expect(UpdateRules.isDue(lastChecked: ago(hours: 24 * 30), now: now))
    }

    @Test func aClockMovedBackDoesNotSilenceTheCheck() {
        #expect(UpdateRules.isDue(lastChecked: now.addingTimeInterval(3600), now: now))
        #expect(UpdateRules.isDue(lastChecked: now.addingTimeInterval(10 * 24 * 3600), now: now))
    }

    @Test func theWaitIsWhatIsLeftOfTheDay() {
        #expect(UpdateRules.delayUntilDue(lastChecked: now, now: now) == 24 * 3600)
        #expect(UpdateRules.delayUntilDue(lastChecked: ago(hours: 20), now: now) == 4 * 3600)
        #expect(UpdateRules.delayUntilDue(lastChecked: ago(hours: 24), now: now) == 0)
        #expect(UpdateRules.delayUntilDue(lastChecked: ago(hours: 30), now: now) == 0)
    }
}

// MARK: Telling

struct UpdateNoticeTests {
    private func version(_ text: String) throws -> BenchVersion { try #require(BenchVersion(text)) }

    @Test func aVersionIsAnnouncedOnce() throws {
        let latest = try version("0.3.6")
        #expect(UpdateRules.shouldAnnounce(latest, announced: nil))
        #expect(!UpdateRules.shouldAnnounce(latest, announced: "0.3.6"))
        #expect(!UpdateRules.shouldAnnounce(latest, announced: "v0.3.6"))
        #expect(!UpdateRules.shouldAnnounce(latest, announced: "0.3.7"))
        // A newer one is news again.
        #expect(UpdateRules.shouldAnnounce(latest, announced: "0.3.5"))
        #expect(UpdateRules.shouldAnnounce(try version("0.3.10"), announced: "0.3.9"))
        // Something stored that isn't a version doesn't hush it.
        #expect(UpdateRules.shouldAnnounce(latest, announced: "garbage"))
    }

    @Test func theCardSaysWhatIsOutAndWhereToGetIt() throws {
        let update = AvailableUpdate(version: try version("0.3.6"), notesURL: UpdateRules.releasesPage)
        let notice = UpdateRules.notice(for: update)
        #expect(notice.title == "Capsid 0.3.6 is available")
        #expect(notice.id == "update-0.3.6")
        #expect(notice.action == .none)
        #expect(notice.detail.contains("Check for Updates"))
    }

    @Test func whatInstallDoesIsSaidInWords() throws {
        #expect(UpdateRules.installSentence(try version("0.3.6")) == "Capsid will quit, download 0.3.6 from GitHub and reopen.")
    }
}

// MARK: Asking

@MainActor
struct UpdateCheckerTests {
    @Test func withTheSettingOffTheScheduleAsksNobody() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, enabled: false)
        let wait = await updates.checkIfDue()
        #expect(network.calls == 0)
        #expect(updates.state == .idle)
        #expect(updates.lastChecked == nil)
        #expect(wait == UpdateRules.interval)
    }

    @Test func withTheSettingOnItAsksOnceAndThenWaitsForTheDay() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let clock = FakeClock()
        let updates = checker(scratch, network: network, clock: clock, enabled: true)
        let wait = await updates.checkIfDue()
        #expect(network.calls == 1)
        #expect(updates.lastChecked == clock.date)
        #expect(wait == UpdateRules.interval)
        // An hour later, a launch an hour later, anything before the day is up: not due.
        clock.advance(hours: 1)
        await updates.checkIfDue()
        clock.advance(hours: 22)
        await updates.checkIfDue()
        #expect(network.calls == 1)
        // A day after the first.
        clock.advance(hours: 1.5)
        await updates.checkIfDue()
        #expect(network.calls == 2)
    }

    @Test func aCheckKeepsItsTimeAcrossLaunches() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let clock = FakeClock()
        let first = FakeNetwork(json: Release.json())
        await checker(scratch, network: first, clock: clock, enabled: true).checkIfDue()
        // Bench is opened again an hour later: a fresh checker, the same defaults.
        clock.advance(hours: 1)
        let second = FakeNetwork(json: Release.json())
        await checker(scratch, network: second, clock: clock, enabled: true).checkIfDue()
        #expect(first.calls == 1)
        #expect(second.calls == 0)
    }

    // MARK: The schedule

    @Test func startingWithTheSettingOffSchedulesNothingUntilItIsTurnedOn() async throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, enabled: false,
                              launchDelay: .milliseconds(5), enabledDelay: .milliseconds(5))
        updates.start()
        try await Task.sleep(for: .milliseconds(150))
        #expect(network.calls == 0)
        // Turned on in Settings, or in the welcome window: noticed without a relaunch.
        scratch.defaults.set(true, forKey: SettingsKey.checkForUpdates)
        // The request goes out a moment before the check records its time.
        try await until { network.calls == 1 && updates.lastChecked != nil }
        #expect(network.calls == 1)
        #expect(updates.lastChecked != nil)
    }

    @Test func startingWithTheSettingOnChecksAfterTheLaunchDelay() async throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, enabled: true,
                              launchDelay: .milliseconds(150), enabledDelay: .seconds(60))
        updates.start()
        try await Task.sleep(for: .milliseconds(20))
        #expect(network.calls == 0)
        try await until { network.calls == 1 }
        #expect(network.calls == 1)
    }

    @Test func turningTheSettingOffBeforeTheFirstCheckCancelsIt() async throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, enabled: true,
                              launchDelay: .milliseconds(200), enabledDelay: .seconds(60))
        updates.start()
        scratch.defaults.set(false, forKey: SettingsKey.checkForUpdates)
        try await Task.sleep(for: .milliseconds(400))
        #expect(network.calls == 0)
    }

    @Test func checkNowAsksWhateverTheSettingSays() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, enabled: false)
        let state = await updates.checkNow()
        #expect(network.calls == 1)
        guard case .available(let update) = state else { Issue.record("expected an update, got \(state)"); return }
        #expect(update.version.description == "0.3.6")
    }

    @Test func aDemoAsksNobodyEvenWhenAsked() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, enabled: true, isDemo: true)
        await updates.checkIfDue()
        await updates.checkNow()
        updates.start()
        #expect(network.calls == 0)
    }

    @Test func theRequestCarriesNothingAboutTheUser() async throws {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        await checker(scratch, network: network, enabled: true).checkIfDue()
        let request = try #require(network.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/samporter14/bench/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.allHTTPHeaderFields == ["Accept": "application/vnd.github+json", "User-Agent": "Capsid/0.3.5",
                                                "Accept-Language": "en"])
    }

    @Test func checksAtTheSameMomentShareOneRequest() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(delay: .milliseconds(40)) { _ in Release.reply(Release.json()) }
        let updates = checker(scratch, network: network, enabled: true)
        async let menu = updates.checkNow()
        async let button = updates.checkNow()
        let (first, second) = await (menu, button)
        #expect(first == second)
        #expect(network.calls == 1)
    }

    @Test func nothingNewIsUpToDateAndForgetsAnOlderSighting() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json(tag: "v0.3.5", url: nil))
        let updates = checker(scratch, network: network, enabled: false)
        scratch.defaults.set("0.3.6", forKey: "updateNewestVersion")
        let state = await updates.checkNow()
        #expect(state == .upToDate("0.3.5"))
        #expect(scratch.defaults.string(forKey: "updateNewestVersion") == nil)
    }

    @Test func aReleaseWithoutItsZipIsNotOfferedYet() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let posted = Posted()
        let network = FakeNetwork(json: Release.json(assets: []))
        let updates = checker(scratch, network: network, posted: posted, enabled: true)
        await updates.checkIfDue()
        #expect(updates.state == .upToDate("0.3.5"))
        #expect(posted.notices.isEmpty)
    }

    // MARK: Failures

    @Test func aTryThatNeverReachedGitHubIsRepeatedInAnHour() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork { _ in throw URLError(.notConnectedToInternet) }
        let clock = FakeClock()
        let updates = checker(scratch, network: network, clock: clock, enabled: true)
        #expect(await updates.checkIfDue() == UpdateRules.retryDelay)
        #expect(updates.state == .failed(.unreachable))
        #expect(updates.lastChecked == nil)
        #expect(scratch.defaults.object(forKey: "updateLastChecked") == nil)
        #expect(scratch.defaults.object(forKey: "updateLastAsked") == nil)
        // Nothing left the Mac, so an hour on it asks again, a day's ask not yet made.
        clock.advance(hours: 1)
        await updates.checkIfDue()
        #expect(network.calls == 2)
    }

    @Test func aTryGitHubRespondedToCountsAsTheDaysAskWhateverItSaid() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        for (reply, failure): (@Sendable (Int) throws -> (Data, URLResponse), CheckFailure) in [
            ({ _ in Release.reply("{\"message\": \"rate limited\"}", status: 403) }, .http(403)),
            ({ _ in Release.reply("{\"message\": \"Not Found\"}", status: 404) }, .http(404)),
            ({ _ in Release.reply("<html>", status: 200) }, .unreadable),
        ] {
            let network = FakeNetwork(answer: reply)
            let clock = FakeClock()
            let updates = checker(scratch, network: network, clock: clock, enabled: true)
            let wait = await updates.checkIfDue()
            #expect(updates.state == .failed(failure))
            #expect(!failure.message.isEmpty)
            // Nothing was learnt, so Settings shows no "last checked"...
            #expect(updates.lastChecked == nil)
            #expect(scratch.defaults.object(forKey: "updateLastChecked") == nil)
            // ...but a day passes before the next ask, not an hour.
            #expect(wait == UpdateRules.interval)
            clock.advance(hours: 1)
            await updates.checkIfDue()
            clock.advance(hours: 22)
            await updates.checkIfDue()
            #expect(network.calls == 1)
            clock.advance(hours: 2)
            await updates.checkIfDue()
            #expect(network.calls == 2)
            scratch.defaults.removeObject(forKey: "updateLastAsked")
        }
    }

    @Test func aRefusalIsRememberedAcrossLaunchesToo() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let clock = FakeClock()
        let first = FakeNetwork(json: "{}", status: 403)
        await checker(scratch, network: first, clock: clock, enabled: true).checkIfDue()
        clock.advance(hours: 2)
        let second = FakeNetwork(json: Release.json())
        await checker(scratch, network: second, clock: clock, enabled: true).checkIfDue()
        #expect(first.calls == 1)
        #expect(second.calls == 0)
    }

    @Test func aCopyWithNoVersionHasNothingToCompare() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        let updates = checker(scratch, network: network, current: "", enabled: true)
        #expect(await updates.checkNow() == .failed(.noVersion))
        #expect(network.calls == 0)
    }

    // MARK: Telling

    @Test func aScheduledCheckPostsOneCardPerVersion() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let posted = Posted()
        let clock = FakeClock()
        let network = FakeNetwork { call in
            call <= 3 ? Release.reply(Release.json()) : Release.reply(Release.json(tag: "v0.3.7", url: nil))
        }
        let updates = checker(scratch, network: network, clock: clock, posted: posted, enabled: true)
        await updates.checkIfDue()
        #expect(posted.notices.map(\.title) == ["Capsid 0.3.6 is available"])
        // Two days on, and again: the same version, so no second card.
        clock.advance(hours: 25)
        await updates.checkIfDue()
        clock.advance(hours: 25)
        await updates.checkIfDue()
        #expect(network.calls == 3)
        #expect(posted.notices.count == 1)
        #expect(updates.state == .available(AvailableUpdate(version: BenchVersion("0.3.6")!, notesURL: UpdateRules.notesURL(nil, version: BenchVersion("0.3.6")))))
        // The next release is news.
        clock.advance(hours: 25)
        await updates.checkIfDue()
        #expect(posted.notices.map(\.title) == ["Capsid 0.3.6 is available", "Capsid 0.3.7 is available"])
    }

    @Test func aCheckYouAskedForShowsItselfAndPostsNoCard() async {
        let scratch = Scratch()
        defer { scratch.clean() }
        let posted = Posted()
        let network = FakeNetwork(json: Release.json())
        let clock = FakeClock()
        let updates = checker(scratch, network: network, clock: clock, posted: posted, enabled: true)
        await updates.checkNow()
        #expect(posted.notices.isEmpty)
        // You were told, so the schedule doesn't tell you again.
        clock.advance(hours: 25)
        await updates.checkIfDue()
        #expect(network.calls == 2)
        #expect(posted.notices.isEmpty)
    }

    @Test func aVersionSeenLastTimeShowsAtLaunchWhileItIsStillNewer() {
        let scratch = Scratch()
        defer { scratch.clean() }
        let network = FakeNetwork(json: Release.json())
        scratch.defaults.set("0.3.6", forKey: "updateNewestVersion")
        scratch.defaults.set(1_800_000_000.0, forKey: "updateLastChecked")
        let old = checker(scratch, network: network, current: "0.3.5", enabled: true)
        #expect(old.state == .available(AvailableUpdate(version: BenchVersion("0.3.6")!, notesURL: UpdateRules.notesURL(nil, version: BenchVersion("0.3.6")))))
        // Updated since: nothing left to offer.
        let updated = checker(scratch, network: network, current: "0.3.6", enabled: true)
        #expect(updated.state == .upToDate("0.3.6"))
        // Never checked: nothing to say.
        let fresh = Scratch()
        defer { fresh.clean() }
        #expect(checker(fresh, network: network, enabled: false).state == .idle)
        #expect(network.calls == 0)
    }
}

// MARK: Installing

struct UpdateInstallTests {
    @Test func theInstallLineIsTheREADMEsLineAndInstallShsAddress() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(readme.contains(UpdateRules.installLine))
        #expect(UpdateRules.installLine == "curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh | zsh")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("install.sh").path))
    }

    @Test func onlyTheCopyInApplicationsCanReplaceItself() {
        #expect(UpdateRules.canInstall(from: URL(fileURLWithPath: "/Applications/Capsid.app")))
        #expect(UpdateRules.canInstall(from: URL(fileURLWithPath: "/Applications/Capsid.app/")))
        #expect(!UpdateRules.canInstall(from: URL(fileURLWithPath: "/Users/someone/Downloads/Capsid.app")))
        #expect(!UpdateRules.canInstall(from: URL(fileURLWithPath: "/Applications/Utilities/Capsid.app")))
        #expect(!UpdateRules.canInstall(from: URL(fileURLWithPath: "/Users/someone/build/Capsid.app")))
    }
}
