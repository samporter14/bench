// CompatWatchTests.swift — what Capsid does when Claude Science's version
// changes (App/CompatWatch.swift): remember it, look once with the read-only
// probes, say so only when something answers differently, and say it in one
// card and one "Last problem" line. Everything is made up: the remembered
// version is a variable (no settings are written), probe results are written
// here, the card is only collected. No page, no daemon, no web view.
import Foundation
import Testing
@testable import Bench

// MARK: A watch with every outside part replaced

@MainActor
private final class WatchRig {
    /// What would be in the settings.
    var remembered: String?
    let harness = BreadcrumbHarness()
    let breadcrumbs: CompatBreadcrumbs
    var version: String? = "0.1.70"
    var ready = true
    var enabled = true
    var results: [ProbeResult] = []
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var asked = 0
    private(set) var settled = 0
    private(set) var probed = 0
    private(set) var posted: [LabNotice] = []
    private(set) var watch: CompatWatch!

    init() {
        breadcrumbs = harness.makeStore()
        watch = CompatWatch(CompatWatch.Dependencies(
            remembered: { [self] in self.remembered },
            remember: { [self] in self.remembered = $0 },
            version: { [self] in await self.answer() },
            isReady: { [self] in self.ready },
            settle: { [self] in await self.settleOnce() },
            probe: { [self] in self.probeOnce() },
            post: { [self] in self.posted.append($0) },
            breadcrumbs: breadcrumbs,
            now: { [self] in self.clock },
            enabled: { [self] in self.enabled }))
    }

    private func answer() async -> String? {
        asked += 1
        return version
    }

    private func settleOnce() async { settled += 1 }

    private func probeOnce() -> [ProbeResult] {
        probed += 1
        return results
    }
}

/// Probe results as the probes would hand them back.
private enum Made {
    static func ok(_ name: String) -> ProbeResult { ProbeResult(name: name, verdict: .ok("fine")) }
    static func shape(_ name: String, _ why: String = "made up") -> ProbeResult {
        ProbeResult(name: name, verdict: .unexpectedShape(why))
    }
    static func away(_ name: String) -> ProbeResult { ProbeResult(name: name, verdict: .notOnScreenNow("made up")) }
    static func failed(_ name: String, _ why: String) -> ProbeResult { ProbeResult(name: name, verdict: .failed(why)) }

    /// Every probe answering as expected or not being on screen.
    static var clean: [ProbeResult] {
        CompatProbes.Name.all.enumerated().map { $0.offset.isMultiple(of: 2) ? Made.ok($0.element) : Made.away($0.element) }
    }
}

// MARK: The version memory

@MainActor
struct CompatWatchVersionTests {
    @Test func theFirstLaunchRemembersTheVersionAndProbesNothing() async {
        let rig = WatchRig()
        rig.results = [Made.shape(CompatProbes.Name.usage)]
        #expect(rig.remembered == nil)
        await rig.watch.look()
        #expect(rig.remembered == "0.1.70")
        #expect(rig.probed == 0 && rig.settled == 0)
        #expect(rig.posted.isEmpty && rig.breadcrumbs.last == nil && rig.watch.lastLook == nil)
    }

    @Test func theSameVersionProbesNothing() async {
        let rig = WatchRig()
        rig.remembered = "0.1.70"
        rig.results = [Made.shape(CompatProbes.Name.usage)]
        await rig.watch.look()
        await rig.watch.look()
        #expect(rig.asked == 2)
        #expect(rig.probed == 0 && rig.posted.isEmpty)
        #expect(rig.remembered == "0.1.70")
    }

    @Test func aChangedVersionProbesOnceAndIsThenRemembered() async {
        let rig = WatchRig()
        rig.remembered = "0.1.63"
        rig.results = Made.clean
        await rig.watch.look()
        #expect(rig.probed == 1 && rig.settled == 1)
        #expect(rig.remembered == "0.1.70")
        // The version is the same now: nothing more is probed, however often it is asked.
        await rig.watch.look()
        await rig.watch.look()
        #expect(rig.probed == 1)
    }

    @Test func anOlderVersionIsAChangeToo() async {
        let rig = WatchRig()
        rig.remembered = "0.1.71"
        rig.results = Made.clean
        await rig.watch.look()
        #expect(rig.probed == 1 && rig.remembered == "0.1.70")
    }

    @Test func aPageThatIsNotReadyAfterAllLooksAgainAtTheNextReadyPage() async {
        let rig = WatchRig()
        rig.remembered = "0.1.63"
        rig.ready = false
        await rig.watch.look()
        // Nothing was looked at, so nothing is remembered.
        #expect(rig.probed == 0 && rig.remembered == "0.1.63")
        rig.ready = true
        rig.results = Made.clean
        await rig.watch.look()
        #expect(rig.probed == 1 && rig.remembered == "0.1.70")
    }

    @Test func aVersionThatCantBeToldIsNotRemembered() async {
        let rig = WatchRig()
        for odd in [nil, "", "  ", "unknown", "Unknown", "0.1.70\n0.1.71", String(repeating: "9", count: 41), "0.1.70 (beta)", "0.1/70", "v0.1.70\u{202E}"] as [String?] {
            rig.version = odd
            await rig.watch.look()
        }
        #expect(rig.remembered == nil)
        #expect(rig.probed == 0 && rig.posted.isEmpty)
    }

    @Test func aVersionWithASuffixIsRememberedAsItIs() async {
        let rig = WatchRig()
        rig.version = " 0.1.71-rc1\n"
        await rig.watch.look()
        #expect(rig.remembered == "0.1.71-rc1")
    }

    @Test func theRulesDecideFromWhatIsRememberedAndWhatIsSeen() {
        #expect(CompatWatchRules.decide(remembered: nil, seen: "0.1.70") == .firstSight)
        #expect(CompatWatchRules.decide(remembered: "0.1.70", seen: "0.1.70") == .unchanged)
        #expect(CompatWatchRules.decide(remembered: "0.1.63", seen: "0.1.70") == .changed)
        #expect(CompatWatchRules.decide(remembered: "0.1.70", seen: "0.1.70-rc1") == .changed)
    }
}

// MARK: Asking

@MainActor
struct CompatWatchAskingTests {
    @Test func aReadyPageAsksOnceAndNotAgainWithinAMinute() async {
        let rig = WatchRig()
        let first = rig.watch.pageReady()
        #expect(first != nil)
        // While the first is under way, and just after it, a second is not started.
        #expect(rig.watch.pageReady() == nil)
        await first?.value
        #expect(rig.watch.pageReady() == nil)
        rig.clock = rig.clock.addingTimeInterval(CompatWatch.askEvery - 1)
        #expect(rig.watch.pageReady() == nil)
        #expect(rig.asked == 1)
        rig.clock = rig.clock.addingTimeInterval(2)
        await rig.watch.pageReady()?.value
        #expect(rig.asked == 2)
    }

    @Test func aDemoAsksNothingAndKeepsNothing() async {
        let rig = WatchRig()
        rig.enabled = false
        #expect(rig.watch.pageReady() == nil)
        #expect(rig.asked == 0 && rig.remembered == nil)
    }

    @Test func aPageThatWasNotReadyIsAskedAgainWithoutWaiting() async {
        let rig = WatchRig()
        rig.remembered = "0.1.63"
        rig.ready = false
        await rig.watch.pageReady()?.value
        rig.ready = true
        rig.results = Made.clean
        // Inside the minute, but the look didn't happen, so asking is allowed.
        await rig.watch.pageReady()?.value
        #expect(rig.probed == 1 && rig.remembered == "0.1.70")
    }
}

// MARK: Which answers count

struct CompatWatchVerdictTests {
    @Test func aShapeCapsidDoesntReadCountsAsAChange() {
        #expect(ProbeVerdict.unexpectedShape("the usage answer couldn't be read").suggestsAChange)
        #expect(ProbeVerdict.unexpectedShape("the page has more than one tab strip").suggestsAChange)
    }

    @Test func aRouteThatAnswersGoneCountsAsAChange() {
        for status in [404, 405, 410] {
            #expect(CompatProbeRules.answeredGone(status).suggestsAChange, "\(status)")
        }
        // The same words come from every place a gone route is reported.
        #expect(CompatProbeRules.failure(ArtifactReadOutcome.missing, miss: .keepFactsNotUnderstood).suggestsAChange)
        #expect(CompatProbeRules.progress(.missing).suggestsAChange)
        #expect(CompatProbeRules.reviewer(.missing).suggestsAChange)
    }

    @Test func theOrdinaryThingsDoNot() {
        let ordinary: [ProbeVerdict] = [
            .ok("fine"),
            .notOnScreenNow("no session is open in the window"),
            .failed("signed out (401); Capsid signs back in by itself"),
            .failed("no answer in time"),
            .failed("the read didn't complete"),
            .failed("answered 500"),
            .failed("answered 403"),
            .failed("the answer exceeded the read limit"),
            .failed("Capsid's list of readable paths doesn't allow it"),
            // What usage says when it can't give the limits (not signed in with an account, say): the breadcrumbs treat it as ordinary.
            .unexpectedShape(CompatProbeRules.usageRefusedPhrase),
        ]
        for verdict in ordinary { #expect(!verdict.suggestsAChange, "\(verdict)") }
    }

    @Test func usageSayingNotOkIsTheOrdinaryOneAndNothingElseIs() {
        let refused = CompatProbeRules.usage(Data(#"{"ok": false}"#.utf8))
        #expect(refused == .unexpectedShape(CompatProbeRules.usageRefusedPhrase) && !refused.suggestsAChange)
        let undecodable = CompatProbeRules.usage(Data("[]".utf8))
        #expect(undecodable.suggestsAChange)
        let noLimits = CompatProbeRules.usage(Data(#"{"ok": true, "data": {}}"#.utf8))
        #expect(noLimits.suggestsAChange)
    }

    @Test func gonePhraseIsWhatDiagnosticsAlwaysSaid() {
        #expect(CompatProbeRules.answeredGone(404) == .failed("answered 404: the route may have moved, or that session is gone"))
        #expect(CompatProbeRules.failure(CompatMissingStatus.error(410)) == .failed("answered 410: the route may have moved, or that session is gone"))
    }
}

/// An error shaped like the page's own refusal (`HTTP 410`), as the probes read it.
private struct CompatMissingStatus: Error {
    static func error(_ status: Int) -> NSError {
        NSError(domain: "WKErrorDomain", code: 4, userInfo: ["WKJavaScriptExceptionMessage": "HTTP \(status)"])
    }
}

// MARK: Naming the features

struct CompatWatchFeatureTests {
    @Test func everyProbeIsKnownToAFeature() {
        for name in CompatProbes.Name.all {
            #expect(CompatProbes.feature(ofProbe: name) != nil, "\(name)")
        }
        #expect(CompatProbes.feature(ofProbe: "made up") == nil)
    }

    @Test func theProbesMapToTheFeaturesTheyLookAfter() {
        let expected: [String: CompatFeature] = [
            CompatProbes.Name.tabStrip: .closeTabs,
            CompatProbes.Name.signIn: .signIn,
            CompatProbes.Name.address: .sessionAddress,
            CompatProbes.Name.usage: .usage,
            CompatProbes.Name.context: .context,
            CompatProbes.Name.frame: .planCard,
            CompatProbes.Name.plan: .planCard,
            CompatProbes.Name.versions: .keep,
            CompatProbes.Name.facts: .keep,
            CompatProbes.Name.progress: .planProgress,
            CompatProbes.Name.reviewer: .reviewer,
        ]
        #expect(Set(expected.keys) == Set(CompatProbes.Name.all))
        for (name, feature) in expected { #expect(CompatProbes.feature(ofProbe: name) == feature, "\(name)") }
    }

    @Test func theFeaturesAreThoseWhoseProbesFoundAChangeEachOnceInOrder() {
        let results: [ProbeResult] = [
            Made.shape(CompatProbes.Name.tabStrip),
            Made.ok(CompatProbes.Name.signIn),
            Made.away(CompatProbes.Name.address),
            Made.failed(CompatProbes.Name.usage, "signed out (401); Capsid signs back in by itself"),
            Made.shape(CompatProbes.Name.frame),
            Made.shape(CompatProbes.Name.plan),
            Made.failed(CompatProbes.Name.versions, "answered 404: the route may have moved, or that session is gone"),
            Made.shape(CompatProbes.Name.facts),
            Made.ok(CompatProbes.Name.reviewer),
        ]
        #expect(CompatWatchRules.features(in: results) == [.closeTabs, .planCard, .keep])
        #expect(CompatWatchRules.features(in: Made.clean).isEmpty)
        #expect(CompatWatchRules.features(in: []).isEmpty)
        // A probe nobody knows can't be named, and is left out.
        #expect(CompatWatchRules.features(in: [Made.shape("made up")]).isEmpty)
    }

    @Test func everyFeatureHasWordsForTheMiddleOfASentence() {
        for feature in CompatFeature.allCases {
            let words = feature.inASentence
            #expect(!words.isEmpty && !words.hasSuffix("."), "\(feature)")
            #expect(!words.contains("!"), "\(feature)")
        }
    }
}

// MARK: What it says

@MainActor
struct CompatWatchSayingTests {
    @Test func aCleanLookSaysNothing() async {
        let rig = WatchRig()
        rig.remembered = "0.1.63"
        // Not on screen, signed out, slow and refused are all ordinary.
        rig.results = Made.clean + [
            Made.failed("x", "signed out (401); Capsid signs back in by itself"),
            Made.failed("y", "no answer in time"),
        ]
        await rig.watch.look()
        #expect(rig.probed == 1)
        #expect(rig.posted.isEmpty)
        #expect(rig.breadcrumbs.last == nil && rig.harness.logged.isEmpty)
        let look = rig.watch.lastLook
        #expect(look?.features.isEmpty == true && look?.version == "0.1.70")
        #expect(rig.watch.diagnosticsLines().last?.hasPrefix("✓ Claude Science changed to 0.1.70") == true)
    }

    @Test func aChangeIsOneCardOneBreadcrumbAndOneLogLine() async {
        let rig = WatchRig()
        rig.remembered = "0.1.63"
        rig.results = [
            Made.shape(CompatProbes.Name.tabStrip, "the page has more than one tab strip"),
            Made.ok(CompatProbes.Name.signIn),
            Made.shape(CompatProbes.Name.usage, CompatMiss.usageNotDecoded.phrase),
            Made.shape(CompatProbes.Name.context, CompatMiss.contextNotDecoded.phrase),
            Made.shape(CompatProbes.Name.frame, CompatMiss.planFrameNotUnderstood.phrase),
            Made.shape(CompatProbes.Name.plan, CompatMiss.planFileWithoutSummary.phrase),
        ]
        await rig.watch.look()
        #expect(rig.posted.count == 1)
        let card = rig.posted[0]
        #expect(card.caption == "Claude Science updated")
        #expect(card.title == "Close Other Tabs and 3 more may not work")
        // The breadcrumb names the miss and the features; the log carries the same fixed words.
        let entry = rig.breadcrumbs.last
        #expect(entry?.miss == .probesAfterUpdate)
        #expect(entry?.features == [.closeTabs, .usage, .context, .planCard])
        #expect(rig.harness.logged == ["Claude Science may have changed: A Claude Science update: some of what Capsid reads didn't answer as it expects (Close Other Tabs, the usage readout, the context ring, plans on cards)"])
        #expect(rig.breadcrumbs.line()?.hasPrefix("Last problem: A Claude Science update, just now: some of what Capsid reads didn't answer as it expects (Close Other Tabs") == true)
        // And Diagnostics says it, with the version Capsid now remembers.
        let lines = rig.watch.diagnosticsLines()
        #expect(lines[0] == "• Claude Science version Capsid last saw: 0.1.70. When it changes, Capsid looks at the page and the reads once, quietly.")
        #expect(lines[1] == "✗ Claude Science changed to 0.1.70; Capsid looked at the page and the reads once, and these didn't answer as it reads them: Close Other Tabs, the usage readout, the context ring, plans on cards")
    }

    @Test func itIsOneCardEvenWhenAskedAgain() async {
        let rig = WatchRig()
        rig.remembered = "0.1.63"
        rig.results = [Made.shape(CompatProbes.Name.usage)]
        await rig.watch.look()
        await rig.watch.look()
        await rig.watch.look()
        #expect(rig.posted.count == 1 && rig.probed == 1)
    }

    @Test func nothingIsSentOrWrittenByTheLook() {
        // The watch holds the probes and nothing else: no write, no script of its own.
        let source = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bench/App/CompatWatch.swift"), encoding: .utf8)) ?? ""
        #expect(!source.isEmpty)
        for forbidden in ["callAsyncJavaScript", "evaluateJavaScript", "WKUserScript", "apiPOST", "POST", "URLSession"] {
            #expect(!source.contains(forbidden), "\(forbidden)")
        }
        #expect(source.contains("CompatProbes.run(.live())"))
    }

    @Test func diagnosticsSaysWhenNoVersionWasSeenYet() {
        let rig = WatchRig()
        let lines = rig.watch.diagnosticsLines()
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("• Capsid has not yet seen which Claude Science version this is"))
    }
}

// MARK: The card's words

struct CompatNoticeWordsTests {
    private let detail = "See Help \u{2192} Capsid Diagnostics\u{2026}"

    @Test func oneFeatureIsNamedAsItself() throws {
        let card = try #require(NoticeRules.afterUpdate(version: "0.1.70", features: [.usage]))
        #expect(card.caption == "Claude Science updated")
        #expect(card.title == "The usage readout may not work")
        #expect(card.detail == detail)
        #expect(card.id == "compat-update-0.1.70")
        #expect(card.action == .none && card.heldFor == nil && card.midRunNote == nil)
        #expect(card.lifetime == .seconds(20))
    }

    @Test func severalAreTheFirstAndAHowMany() throws {
        let two = try #require(NoticeRules.afterUpdate(version: "0.1.70", features: [.closeTabs, .usage]))
        #expect(two.title == "Close Other Tabs and 1 more may not work")
        let five = try #require(NoticeRules.afterUpdate(version: "0.1.70", features: [.closeTabs, .usage, .context, .planCard, .keep]))
        #expect(five.title == "Close Other Tabs and 4 more may not work")
        #expect(five.detail == detail)
    }

    @Test func aFeatureNamedInLowerCaseStartsTheSentence() throws {
        #expect(try #require(NoticeRules.afterUpdate(version: nil, features: [.planCard])).title == "Plans on cards may not work")
        #expect(try #require(NoticeRules.afterUpdate(version: nil, features: [.reviewer, .keep])).title == "Reviewer findings and 1 more may not work")
        #expect(try #require(NoticeRules.afterUpdate(version: nil, features: [.keep])).title == "Keep may not work")
    }

    @Test func aVersionThatIsNotPlainNumbersOnlyKeysTheCard() throws {
        for odd in ["0.1.71-rc1", "nightly", "", "0.1.70 (beta)"] {
            let card = try #require(NoticeRules.afterUpdate(version: odd, features: [.usage]))
            #expect(card.id == "compat-update-unknown", "\(odd)")
            #expect(!card.title.contains(odd) || odd.isEmpty, "\(odd)")
        }
        #expect(try #require(NoticeRules.afterUpdate(version: nil, features: [.usage])).id == "compat-update-unknown")
        #expect(try #require(NoticeRules.afterUpdate(version: "0.1.71", features: [.usage])).id == "compat-update-0.1.71")
    }

    @Test func nothingAffectedIsNoCard() {
        #expect(NoticeRules.afterUpdate(version: "0.1.70", features: []) == nil)
    }

    @Test func theWordsAreSolanumsAndSayWhatIsTrue() throws {
        for features in [[CompatFeature.closeTabs], [.usage, .context], CompatFeature.allCases] {
            let card = try #require(NoticeRules.afterUpdate(version: "0.1.70", features: features))
            for text in [card.title, card.detail, card.caption] {
                #expect(!text.contains("!"), "\(text)")
                #expect(text.first?.isUppercase == true, "\(text)")
            }
            // What happened, and what may follow: not that anything was switched off, which nothing is.
            #expect(card.title.hasSuffix(" may not work"))
            for word in ["turned off", "disabled", "broken", "failed"] {
                #expect(!card.title.localizedCaseInsensitiveContains(word) && !card.detail.localizedCaseInsensitiveContains(word), "\(word)")
            }
        }
    }

    @Test func itFitsTheCardsTitleOfTwoLinesAndDetailOfOne() throws {
        // The panel's title wraps to two lines (about 28 characters each on
        // its narrowest card) and its detail stays on one (about 30). The
        // longest a title gets: the longest feature name and a count.
        let longest = CompatFeature.allCases.map(\.inASentence).max { $0.count < $1.count } ?? ""
        let worst = try #require(NoticeRules.afterUpdate(version: nil, features: [.reviewer, .keep, .usage, .context, .planCard, .closeTabs, .planProgress]))
        #expect(worst.title.count <= 42, "\(worst.title)")
        #expect(worst.detail.count <= 30)
        #expect(worst.caption.count <= 24)
        // The features a probe can flag are all short.
        let probed = Set(CompatProbes.Name.all.compactMap { CompatProbes.feature(ofProbe: $0) })
        #expect(probed.allSatisfy { $0.inASentence.count <= 20 }, "\(longest)")
    }

    @Test func theNoticeIsInTheLabNoticeFile() {
        let notice = Repo.sourceText("Lab/LabNotice.swift")
        #expect(notice.contains("static func afterUpdate(version: String?, features: [CompatFeature]) -> LabNotice?"))
    }
}

// MARK: The breadcrumb

struct CompatUpdateBreadcrumbTests {
    @Test func theMissHasAFeatureAndAPlainPhraseLikeTheRest() {
        let miss = CompatMiss.probesAfterUpdate
        #expect(miss.feature == .update && miss.feature != .signIn)
        #expect(miss.feature.shortTitle == "A Claude Science update")
        #expect(miss.phrase == "some of what Capsid reads didn't answer as it expects")
        #expect(miss.phrase.first?.isLowercase == true && !miss.phrase.hasSuffix(".") && !miss.phrase.contains { $0.isNumber })
    }

    @Test func aMissWithNoFeaturesReadsAsBefore() {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        store.record(.usageWithoutLimits)
        #expect(store.line() == "Last problem: The usage readout, just now: the usage answer has none of the limits Capsid reads")
        #expect(harness.logged == ["Claude Science may have changed: The usage readout: the usage answer has none of the limits Capsid reads"])
        #expect(store.last == CompatBreadcrumbs.Entry(miss: .usageWithoutLimits, at: harness.now))
    }

    @Test func theFeaturesAreNamedInBracketsAndRepeatsAreIgnoredAsOthersAre() {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        store.record(.probesAfterUpdate, affecting: [.closeTabs, .keep])
        harness.advance(120)
        store.record(.probesAfterUpdate, affecting: [.usage])
        #expect(harness.logged.count == 1)
        #expect(store.line() == "Last problem: A Claude Science update, 2 minutes ago: some of what Capsid reads didn't answer as it expects (Close Other Tabs, Keep)")
        #expect(store.last?.features == [.closeTabs, .keep])
    }
}

// MARK: Wired in, and held to what it should be

struct CompatWatchWiringTests {
    @Test func theWebContainerStartsItWithOneLineAndNoBreadcrumbs() {
        let container = Repo.sourceText("Web/WebContainer.swift")
        #expect(container.components(separatedBy: "CompatWatch.shared.pageReady()").count == 2)
        #expect(!container.contains("CompatBreadcrumbs"))
        // After the page is ready, never before.
        let ready = container.range(of: "status = .ready\n        // Looks once")
        #expect(ready != nil)
    }

    @Test func diagnosticsShowsWhatTheWatchSaw() {
        let diagnose = Repo.sourceText("App/Diagnose.swift")
        #expect(diagnose.contains("watch.diagnosticsLines()"))
    }

    @Test func theStoredVersionIsOneSettingsKeyWithNoDefault() {
        #expect(SettingsKey.lastScienceVersion == "lastScienceVersionSeen")
        #expect(Repo.sourceText("App/CompatWatch.swift").contains("extension SettingsKey"))
        #expect(!Repo.sourceText("App/Theme.swift").contains("lastScienceVersion"))
    }

    @Test func theLiveWatchUsesStatusTheShownPageAndTheDiagnosticsProbes() {
        let watch = Repo.sourceText("App/CompatWatch.swift")
        #expect(watch.contains("UserDefaults.standard.set($0, forKey: SettingsKey.lastScienceVersion)"))
        #expect(watch.contains("DaemonController.runningStatus()?.version"))
        #expect(watch.contains("WebContainer.shared.status == .ready"))
        #expect(watch.contains("CompatProbes.run(.live())"))
        #expect(watch.contains("Demo.mode == nil"))
    }
}

/// Capsid's own source as text: the one place these tests read a file.
private enum Repo {
    static func sourceText(_ relative: String) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)) ?? ""
    }
}

// MARK: The inventory, walked against 0.1.70

struct CompatWalkTests {
    @Test func theInventoryWasWalkedAgainst0170() {
        #expect(CompatInventory.checkedWith == "0.1.70")
        #expect(ScienceVersion.relation(running: "0.1.70") == .same)
        #expect(ScienceVersion.relation(running: "0.1.71") == .newer)
        #expect(ScienceVersion.relation(running: "0.1.63") == .older)
    }

    @Test func theRestartingDialogEntrySaysItIsForEveryRestart() {
        let dialog = CompatInventory.pageHooks.first { $0.token == #"[data-testid="restarting-dialog"]"# }
        #expect(dialog?.detail.contains("whenever Claude Science restarts its server") == true)
        #expect(dialog?.detail.contains("an update") == true)
        #expect(dialog?.detail.contains("never its words") == true)
    }

    @Test func thePlanProgressEntryAdmitsWhatOnlyALiveReadCanConfirm() {
        let progress = CompatInventory.readEndpoints.first { $0.token == CompatProbes.Name.progress }
        #expect(progress?.detail.contains("_plan_json is the daemon's own, so only this live read can confirm it") == true)
    }

    @Test func thePreviewEntryNamesWhereThePageGetsItsSandbox() {
        let preview = CompatInventory.pageHooks.first { $0.token == "another localhost port" }
        #expect(preview?.detail.contains("sandboxOrigin") == true)
        #expect(preview?.feature == .previews && preview?.isWhenUsed == true)
    }
}
