// WhatsNewTests.swift — who sees What's New and when (App/WhatsNew.swift): the
// table keyed by release, the gate (a fresh install against an updater, a patch
// release, a release with no entry, a demo), the timing (only while Capsid is
// the app in use, and not over a card or a sheet) and what is recorded (on
// close, never on open). Each test with defaults uses its own throwaway suite,
// never the real settings, and the presenter runs on made-up answers: no window
// is opened.
import AppKit
import Foundation
import Testing
@testable import Bench

struct WhatsNewTests {
    private let release11 = WhatsNew.release11
    private let release12 = WhatsNewRelease(version: "1.2", pages: [
        WhatsNewPage(title: "Something later", text: "A line.", art: .symbol("star")),
    ])

    /// A suite of its own, with the defaults Capsid registers at launch.
    private func suite(_ body: (UserDefaults, String) throws -> Void) throws {
        let scratch = ScratchDefaults.make(prefix: "WhatsNewTests")
        defer { scratch.discard() }
        scratch.defaults.register(defaults: [
            SettingsKey.showPanel: true,
            SettingsKey.appearance: BenchAppearance.system.rawValue,
            SettingsKey.checkForUpdates: true,
        ])
        try body(scratch.defaults, scratch.name)
    }

    // MARK: The table

    @Test func theTableHasOneEntryFor1_1WithFourPages() throws {
        #expect(WhatsNew.releases.map(\.version) == ["1.1"])
        #expect(release11.pages.map(\.title) == [
            "Compare two things on the Shelf", "Project Workspaces", "Eight new specimens", "Show Where It Came From",
        ])
        #expect(release11.number == BenchVersion("1.1"))
    }

    @Test func eachPageHasATitleAndPlainTextAndNothingShouts() {
        for page in release11.pages {
            #expect(!page.title.isEmpty)
            #expect(!page.text.isEmpty)
            #expect(!page.title.contains("!") && !page.text.contains("!"), "\(page.title)")
            // One or two sentences; a third is fine, a paragraph is not.
            #expect(page.text.count < 260, "\(page.title)")
        }
    }

    @Test func entriesAreOldestFirstAndEachKeyedByMajorAndMinorOnly() {
        let numbers = WhatsNew.releases.compactMap(\.number)
        #expect(numbers.count == WhatsNew.releases.count)
        #expect(numbers == numbers.sorted())
        #expect(Set(numbers.map(\.description)).count == numbers.count)
        for release in WhatsNew.releases { #expect(release.version.split(separator: ".").count == 2, "\(release.version)") }
    }

    @Test func theSpecimensPageNamesEightRealSpecimensAndCarriesTheSequencesSwitch() throws {
        let page = try #require(release11.pages.first { $0.title == "Eight new specimens" })
        guard case .specimens(let names) = page.art else {
            Issue.record("the page's picture isn't specimens")
            return
        }
        #expect(names.count == 8)
        #expect(Set(names).count == 8)
        let catalogue = Set(LabScenes.catalogue.map(\.name))
        for name in names { #expect(catalogue.contains(name), "\(name)") }
        #expect(page.control == .playShortSequences)
        // Only that page carries a switch; the others are a symbol each.
        for other in release11.pages where other.id != page.id {
            #expect(other.control == nil)
            if case .symbol = other.art {} else { Issue.record("\(other.title) should be a symbol") }
        }
    }

    // MARK: Which release a version belongs to

    @Test(arguments: [("1.1.0", "1.1"), ("1.1.1", "1.1"), ("1.1", "1.1"), ("1.1.12", "1.1"), ("v1.2.3", "1.2"),
                      ("1", "1.0"), ("1.0.7", "1.0"), ("2.0.0", "2.0")])
    func aPatchReleaseBelongsToItsMajorAndMinor(version: String, release: String) {
        #expect(WhatsNew.releaseNumber(of: version) == BenchVersion(release))
    }

    @Test(arguments: ["", "latest", "1.x", "-1.1"])
    func textThatIsNotAVersionBelongsToNoRelease(version: String) {
        #expect(WhatsNew.releaseNumber(of: version) == nil)
        #expect(WhatsNew.release(for: version) == nil)
    }

    @Test func onlyAVersionOfThe1_1ReleaseHasThe1_1Entry() {
        #expect(WhatsNew.release(for: "1.1.0") == release11)
        #expect(WhatsNew.release(for: "1.1.3") == release11)
        #expect(WhatsNew.release(for: "1.0.7") == nil)
        #expect(WhatsNew.release(for: "1.2.0") == nil)
        #expect(WhatsNew.release(for: "2.1.0") == nil)
    }

    @Test func helpShowsTheNewestEntryUpToTheRunningRelease() {
        let table = [release11, release12]
        #expect(WhatsNew.forHelp(appVersion: "1.1.0", in: table) == release11)
        #expect(WhatsNew.forHelp(appVersion: "1.1.9", in: table) == release11)
        #expect(WhatsNew.forHelp(appVersion: "1.2.0", in: table) == release12)
        // A release with no entry of its own shows the last one before it.
        #expect(WhatsNew.forHelp(appVersion: "1.3.0", in: table) == release12)
        #expect(WhatsNew.forHelp(appVersion: "1.2.0", in: [release11]) == release11)
        // A build older than every entry (a developer's) shows the newest, and a version that isn't one too.
        #expect(WhatsNew.forHelp(appVersion: "1.0.7", in: table) == release12)
        #expect(WhatsNew.forHelp(appVersion: "", in: table) == release12)
        #expect(WhatsNew.forHelp(appVersion: "1.1.0", in: []) == nil)
    }

    // MARK: The gate, pure

    private func verdict(_ version: String, seen: String? = nil, used: Bool = true, demo: Bool = false,
                         table: [WhatsNewRelease]? = nil) -> WhatsNewGate.Verdict {
        WhatsNewGate.verdict(appVersion: version, seen: seen, usedBefore: used, isDemo: demo, table: table ?? WhatsNew.releases)
    }

    @Test func someoneUpdatingWhoHasNotSeenTheReleaseIsShownIt() {
        #expect(verdict("1.1.0") == .show(release11))
    }

    @Test func someoneWhoUpdatesStraightToAPatchReleaseStillGetsTheReleasesPages() {
        // 1.0.7 to 1.1.1, with 1.1.0 never installed.
        #expect(verdict("1.1.1") == .show(release11))
        #expect(verdict("1.1.1", seen: "1.0") == .show(release11))
    }

    @Test func aFreshInstallStartedOnThisReleaseSoItIsRecordedAndNotShown() {
        #expect(verdict("1.1.0", used: false) == .startedHere(release11))
    }

    @Test func aReleaseAlreadySeenIsNotShownAgain() {
        #expect(verdict("1.1.0", seen: "1.1") == .nothing)
        #expect(verdict("1.1.0", seen: "1.1", used: false) == .nothing)
    }

    @Test func aPatchReleaseShowsNothingNew() {
        #expect(verdict("1.1.1", seen: "1.1") == .nothing)
        #expect(verdict("1.1.2", seen: "1.1.0") == .nothing)
    }

    @Test func aReleaseSeenLaterThanThisOneIsNotShown() {
        // An older build put back on a Mac that has gone on since.
        #expect(verdict("1.1.0", seen: "1.2") == .nothing)
        #expect(verdict("1.1.0", seen: "2.0") == .nothing)
    }

    @Test func aReleaseWithNoEntryShowsNothingWhoeverSeesIt() {
        #expect(verdict("1.0.7") == .nothing)
        #expect(verdict("1.0.7", used: false) == .nothing)
        #expect(verdict("1.2.0") == .nothing)
        #expect(verdict("") == .nothing)
        #expect(verdict("1.1.0", table: []) == .nothing)
    }

    @Test func aFutureReleaseOnlyAddsAnEntry() {
        let table = [release11, release12]
        #expect(verdict("1.2.0", seen: "1.1", table: table) == .show(release12))
        #expect(verdict("1.2.0", seen: "1.2", table: table) == .nothing)
        #expect(verdict("1.2.3", seen: "1.1", table: table) == .show(release12))
        // Someone who skipped 1.1 sees the release they are on, not both.
        #expect(verdict("1.2.0", table: table) == .show(release12))
        #expect(verdict("1.2.0", used: false, table: table) == .startedHere(release12))
        #expect(verdict("1.1.5", seen: "1.1", table: table) == .nothing)
    }

    @Test func aDemoNeverShowsAnythingOrRecordsAnything() {
        #expect(verdict("1.1.0", demo: true) == .nothing)
        #expect(verdict("1.1.0", used: false, demo: true) == .nothing)
        #expect(verdict("1.1.0", seen: "1.0", demo: true) == .nothing)
    }

    @Test func aSeenValueThatIsNotAVersionCountsAsNotSeen() {
        #expect(verdict("1.1.0", seen: "yes") == .show(release11))
        #expect(verdict("1.1.0", seen: "") == .show(release11))
    }

    // MARK: Who has used Capsid before

    @Test func hasSeenTheWelcomeOrHasASettingOnlyAUsedCapsidStores() {
        #expect(WhatsNewGate.usedBefore(hasSeenWelcome: true, storedKeys: []))
        #expect(!WhatsNewGate.usedBefore(hasSeenWelcome: false, storedKeys: []))
        for key in WelcomeGate.earlierSettings {
            #expect(WhatsNewGate.usedBefore(hasSeenWelcome: false, storedKeys: [key]), "\(key)")
        }
        // What a first launch can leave behind does not count.
        #expect(!WhatsNewGate.usedBefore(hasSeenWelcome: false,
                                         storedKeys: [SettingsKey.checkForUpdates, SettingsKey.whatsNewSeen, SettingsKey.pageZoom]))
    }

    // MARK: Against real defaults

    @Test func aFreshInstallRecordsTheReleaseItStartedOnAndIsNeverShownItEvenAfterTheWelcomeCloses() throws {
        try suite { defaults, name in
            #expect(WelcomeGate.storedKeys(in: defaults, domain: name).isEmpty)
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == nil)
            WhatsNewGate.settleAtLaunch(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false)
            #expect(WhatsNewGate.seen(in: defaults) == "1.1")
            // The Welcome is up, and then closes: nothing changes for What's New.
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == nil)
            WelcomeGate.markSeen(in: defaults)
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == nil)
            #expect(WhatsNewGate.pending(appVersion: "1.1.4", defaults: defaults, domain: name, isDemo: false) == nil)
        }
    }

    @Test func aFreshInstallOfAReleaseWithNoEntryRecordsNothingAndSeesTheNextEntryLater() throws {
        try suite { defaults, name in
            WhatsNewGate.settleAtLaunch(appVersion: "1.0.8", defaults: defaults, domain: name, isDemo: false)
            #expect(WhatsNewGate.seen(in: defaults) == nil)
            // It used Capsid since: the Welcome closed. Then 1.1.0 arrives.
            WelcomeGate.markSeen(in: defaults)
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == release11)
        }
    }

    @Test func someoneUpdatingIsShownItAtLaunchAndNothingIsWrittenBySettlingOrAsking() throws {
        try suite { defaults, name in
            defaults.set(true, forKey: SettingsKey.hasSeenWelcome)
            WhatsNewGate.settleAtLaunch(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false)
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == release11)
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == release11)
            #expect(WhatsNewGate.seen(in: defaults) == nil)
        }
    }

    @Test(arguments: ["sceneGroups", "settingsTab", "appearance", "showLabPanel"])
    func aMacWithAnEarlierSettingStoredIsAnUpdaterEvenWithoutTheWelcomeFlag(key: String) throws {
        try suite { defaults, name in
            defaults.set(key == "sceneGroups" ? ["lab"] : "value", forKey: key)
            #expect(!defaults.bool(forKey: SettingsKey.hasSeenWelcome))
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == release11)
        }
    }

    @Test func registeredDefaultsDoNotMakeAFreshInstallLookUsed() throws {
        try suite { defaults, name in
            // `object(forKey:)` sees what is registered; the stored keys don't.
            #expect(defaults.object(forKey: SettingsKey.showPanel) != nil)
            WhatsNewGate.settleAtLaunch(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false)
            #expect(WhatsNewGate.seen(in: defaults) == "1.1")
        }
    }

    @Test func closingRecordsTheReleaseAndAPatchReleaseThenShowsNothing() throws {
        try suite { defaults, name in
            defaults.set(true, forKey: SettingsKey.hasSeenWelcome)
            let shown = try #require(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false))
            #expect(WhatsNewGate.seen(in: defaults) == nil, "opening records nothing")
            WhatsNewGate.closed(shown, records: true, in: defaults)
            #expect(WhatsNewGate.seen(in: defaults) == "1.1")
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) == nil)
            #expect(WhatsNewGate.pending(appVersion: "1.1.1", defaults: defaults, domain: name, isDemo: false) == nil)
        }
    }

    @Test func aDemosWindowRecordsNothingWhenItCloses() throws {
        try suite { defaults, _ in
            WhatsNewGate.closed(release11, records: false, in: defaults)
            #expect(WhatsNewGate.seen(in: defaults) == nil)
            #expect(defaults.object(forKey: SettingsKey.whatsNewSeen) == nil)
        }
    }

    @Test func aDemoSettlesNothingAndShowsNothingOnAnyMac() throws {
        try suite { defaults, name in
            WhatsNewGate.settleAtLaunch(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: true)
            #expect(WhatsNewGate.seen(in: defaults) == nil)
            defaults.set(true, forKey: SettingsKey.hasSeenWelcome)
            #expect(WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: true) == nil)
            #expect(WhatsNewGate.seen(in: defaults) == nil)
        }
    }

    @Test func markingSeenNeverGoesBackToAnEarlierRelease() throws {
        try suite { defaults, _ in
            WhatsNewGate.markSeen(release12, in: defaults)
            #expect(WhatsNewGate.seen(in: defaults) == "1.2")
            WhatsNewGate.markSeen(release11, in: defaults)
            #expect(WhatsNewGate.seen(in: defaults) == "1.2")
        }
    }

    // MARK: When it may come up, pure

    @Test func itShowsOnlyWhenEverythingHolds() {
        #expect(WhatsNewTiming.decide(hasPending: true, isActive: true, isOpen: false, somethingIsUp: false) == .show)
    }

    @Test func itWaitsWhileCapsidIsNotTheAppInUse() {
        #expect(WhatsNewTiming.decide(hasPending: true, isActive: false, isOpen: false, somethingIsUp: false) == .wait)
    }

    @Test func itWaitsWhileACardOrASheetIsUp() {
        #expect(WhatsNewTiming.decide(hasPending: true, isActive: true, isOpen: false, somethingIsUp: true) == .wait)
    }

    @Test func itWaitsWhenItIsOpenAlreadyOrNothingIsPending() {
        #expect(WhatsNewTiming.decide(hasPending: true, isActive: true, isOpen: true, somethingIsUp: false) == .wait)
        #expect(WhatsNewTiming.decide(hasPending: false, isActive: true, isOpen: false, somethingIsUp: false) == .wait)
    }

    // MARK: What holds it back

    @MainActor
    @Test func aQuestionAPlanOrAFailureHoldsItBackAndANoticeOrAFinishDoesNot() {
        let session = PanelDemo.session(.running, title: "Plate reader QC", project: "Assay development", minutes: 3)
        #expect(WhatsNewBusy.holds([.needsInput(session)]))
        #expect(WhatsNewBusy.holds([.finished(session), .failed(session)]))
        #expect(!WhatsNewBusy.holds([]))
        #expect(!WhatsNewBusy.holds([.finished(session)]))
        #expect(!WhatsNewBusy.holds([.saved(URL(fileURLWithPath: "/tmp/z_prime_by_plate.png"))]))
    }

    // MARK: The pages' steps

    @Test func thePrimaryButtonReadsNextThenContinueOnTheLastPage() {
        var flow = TourFlow(count: release11.pages.count)
        var titles: [String] = []
        for _ in 0..<4 {
            titles.append(flow.primaryTitle(last: "Continue"))
            flow.next()
        }
        #expect(titles == ["Next", "Next", "Next", "Continue"])
        #expect(flow.isLast)
        flow.next()
        #expect(flow.index == 3)
    }

    @Test func aStartingPageCountsFromOneAndBothEndsStop() {
        #expect(TourFlow(count: 4).index == 0)
        #expect(TourFlow(count: 4, startingAt: 3).index == 2)
        #expect(TourFlow(count: 4, startingAt: 0).index == 0)
        #expect(TourFlow(count: 4, startingAt: 99).index == 3)
        var flow = TourFlow(count: 4)
        flow.back()
        #expect(flow.isFirst)
        #expect(TourFlow(count: 0).count == 1)
    }

    @Test func theDemoIsNamedWhatsnew() {
        #expect(Demo.Mode(rawValue: "whatsnew") == .whatsNew)
    }
}

// MARK: The presenter, on made-up answers

@MainActor
struct WhatsNewPresenterTests {
    /// What the world answers, and what the presenter did about it.
    @MainActor
    final class Stage {
        var release: WhatsNewRelease? = WhatsNew.release11
        var active = true
        var somethingUp = false
        var open = false
        var shown: [WhatsNewRelease] = []
        let center = NotificationCenter()

        func presenter() -> WhatsNewPresenter {
            WhatsNewPresenter(
                pending: { self.release }, isActive: { self.active }, somethingIsUp: { self.somethingUp },
                isOpen: { self.open },
                show: { release in
                    self.shown.append(release)
                    self.open = true
                },
                center: center, settle: .zero)
        }

        /// Capsid is brought to the front, the way AppKit tells it.
        func bringToFront() { center.post(name: NSApplication.didBecomeActiveNotification, object: nil) }
    }

    /// The notification reaches the presenter on the main queue, a turn later.
    private func settled(_ stage: Stage, count: Int) async {
        for _ in 0..<200 where stage.shown.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
        // And a little longer, to see that nothing more comes.
        try? await Task.sleep(for: .milliseconds(60))
    }

    @Test func shownAtLaunchWhenCapsidIsAlreadyTheAppInUse() {
        let stage = Stage()
        let presenter = stage.presenter()
        presenter.start()
        #expect(stage.shown == [WhatsNew.release11])
    }

    @Test func notShownAtLaunchInTheBackgroundButTheFirstTimeItIsBroughtToTheFront() async {
        let stage = Stage()
        stage.active = false
        let presenter = stage.presenter()
        presenter.start()
        #expect(stage.shown.isEmpty)
        #expect(presenter.isListening)
        await settled(stage, count: 1)
        #expect(stage.shown.isEmpty, "waiting is not polling")

        stage.active = true
        stage.bringToFront()
        await settled(stage, count: 1)
        #expect(stage.shown == [WhatsNew.release11])
    }

    @Test func neverShownWhileCapsidIsNotActiveEvenWhenNotifiedOfAnActivation() async {
        let stage = Stage()
        stage.active = false
        let presenter = stage.presenter()
        presenter.start()
        // The notification arrives after the user has already gone elsewhere.
        stage.bringToFront()
        await settled(stage, count: 1)
        #expect(stage.shown.isEmpty)
    }

    @Test func aCardOrSheetUpDefersItToTheNextActivationNotToWhenItGoes() async {
        let stage = Stage()
        stage.somethingUp = true
        let presenter = stage.presenter()
        presenter.start()
        #expect(stage.shown.isEmpty)

        stage.bringToFront()
        await settled(stage, count: 1)
        #expect(stage.shown.isEmpty, "still up at the next activation")

        // The card goes: nothing happens by itself.
        stage.somethingUp = false
        await settled(stage, count: 1)
        #expect(stage.shown.isEmpty)

        stage.bringToFront()
        await settled(stage, count: 1)
        #expect(stage.shown == [WhatsNew.release11])
    }

    @Test func openOnceItIsNotShownAgainWhileItIsOpen() async {
        let stage = Stage()
        let presenter = stage.presenter()
        presenter.start()
        stage.bringToFront()
        stage.bringToFront()
        await settled(stage, count: 2)
        #expect(stage.shown.count == 1)
    }

    @Test func nothingToShowForThisVersionMeansNothingListensAtAll() {
        let stage = Stage()
        stage.release = nil
        let presenter = stage.presenter()
        presenter.start()
        #expect(!presenter.isListening)
        #expect(stage.shown.isEmpty)
    }

    @Test func seenMeanwhileFromHelpItIsNotShownAndStopsListening() async {
        let stage = Stage()
        stage.active = false
        let presenter = stage.presenter()
        presenter.start()
        #expect(presenter.isListening)
        // Help → What's New in Capsid, read and closed, before the first activation.
        stage.release = nil
        stage.active = true
        stage.bringToFront()
        await settled(stage, count: 1)
        #expect(stage.shown.isEmpty)
        #expect(!presenter.isListening)
    }

    @Test func afterItIsClosedAndRecordedTheNextActivationShowsNothingAndStopsListening() async throws {
        let scratch = ScratchDefaults.make(prefix: "WhatsNewPresenterTests")
        defer { scratch.discard() }
        let defaults = scratch.defaults
        defaults.set(true, forKey: SettingsKey.hasSeenWelcome)
        let center = NotificationCenter()
        var shown: [WhatsNewRelease] = []
        var open = false
        let name = scratch.name
        let presenter = WhatsNewPresenter(
            pending: { WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: false) },
            isActive: { true }, somethingIsUp: { false }, isOpen: { open },
            show: { shown.append($0); open = true },
            center: center, settle: .zero)
        presenter.start()
        #expect(shown == [WhatsNew.release11])
        // Opened, not recorded.
        #expect(WhatsNewGate.seen(in: defaults) == nil)

        // Closed: by Continue, Esc or the close button alike, it ends in `closed`.
        open = false
        WhatsNewGate.closed(try #require(shown.first), records: true, in: defaults)
        #expect(WhatsNewGate.seen(in: defaults) == "1.1")
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<100 where presenter.isListening { try await Task.sleep(for: .milliseconds(10)) }
        #expect(shown.count == 1)
        #expect(!presenter.isListening)
    }

    @Test func aDemoNeverStartsListeningOrShows() throws {
        let scratch = ScratchDefaults.make(prefix: "WhatsNewPresenterTests")
        defer { scratch.discard() }
        scratch.defaults.set(true, forKey: SettingsKey.hasSeenWelcome)
        let name = scratch.name
        let defaults = scratch.defaults
        var shown = 0
        let presenter = WhatsNewPresenter(
            pending: { WhatsNewGate.pending(appVersion: "1.1.0", defaults: defaults, domain: name, isDemo: true) },
            isActive: { true }, somethingIsUp: { false }, isOpen: { false },
            show: { _ in shown += 1 },
            center: NotificationCenter(), settle: .zero)
        presenter.start()
        #expect(shown == 0)
        #expect(!presenter.isListening)
        #expect(WhatsNewGate.seen(in: defaults) == nil)
    }
}
