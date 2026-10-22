// CompatProbeTests.swift — Diagnostics' live look at the page and the API, on
// made-up pages and answers: how each answer is classified (ok, not the shape
// Capsid reads, not on screen now, couldn't be checked), the tab-strip look run
// in JavaScriptCore against the fake strip, and the runner with fakes in place
// of the page. Nothing here loads a web view or reaches a daemon.
import Foundation
import Testing
@testable import Bench

extension FakeTabPage {
    /// `PageTabsScript.probe` run as the page would, and its JSON answer.
    func probe() -> String? {
        script.evaluate("""
        var __probeOut = null;
        (async function () {
        \(PageTabsScript.probe)
        })().then(function (v) { __probeOut = v; }, function (e) { __probeOut = "threw: " + e; });
        """)
        return script.evaluate("__probeOut")
    }
}

// MARK: The tab strip

struct TabStripProbeTests {
    private func look(_ page: FakeTabDOM.Page) -> (answer: String, verdict: ProbeVerdict, clicks: String) {
        let fake = FakeTabPage(page)
        let answer = fake.probe() ?? ""
        return (answer, CompatProbeRules.tabStrip(answer), fake.clicks)
    }

    private func tabs(_ count: Int, shown: String? = "t1") -> [FakeTabDOM.Tab] {
        (1...count).map { FakeTabDOM.Tab(id: "t\($0)", shown: "t\($0)" == shown) }
    }

    @Test func aStripWithTabsIsOkWhenEachCanBeClosedAndOneIsShown() {
        let result = look(.init(tabs: tabs(3)))
        #expect(result.verdict == .ok("3 tabs, each with a close button, one shown"))
        #expect(look(.init(tabs: tabs(1))).verdict == .ok("1 tab, each with a close button, one shown"))
    }

    @Test func theShownTabMayBeMarkedEitherWay() {
        for via in ["aria", "data", "both"] {
            var list = tabs(2)
            list[0].shownVia = via
            #expect(look(.init(tabs: list)).verdict == .ok("2 tabs, each with a close button, one shown"), "\(via)")
        }
    }

    @Test func noStripIsNotOnScreenAndNotAFault() {
        let result = look(.init(tabs: [], strips: 0))
        #expect(result.verdict == .notOnScreenNow("no tab is open; open one and run this again"))
        #expect(result.verdict.isFault == false)
    }

    @Test func twoStripsOrNoToolbarAreNotTheShapeCapsidReads() {
        #expect(look(.init(tabs: tabs(2), strips: 2)).verdict == .unexpectedShape("the page has more than one tab strip"))
        #expect(look(.init(tabs: tabs(2), toolbar: false)).verdict == .unexpectedShape("the strip has no toolbar of open panels"))
    }

    @Test func aTabWithNoCloseButtonOrNoShownTabIsNotTheShapeCapsidReads() {
        var list = tabs(3)
        list[1].close = "none"
        #expect(look(.init(tabs: list)).verdict == .unexpectedShape("1 of 3 tabs have no close button"))
        #expect(look(.init(tabs: tabs(3, shown: nil))).verdict == .unexpectedShape("0 of 3 tabs are marked as shown, not one"))
        var two = tabs(3)
        two[2].shown = true
        #expect(look(.init(tabs: two)).verdict == .unexpectedShape("2 of 3 tabs are marked as shown, not one"))
    }

    @Test func aStripWithNoTabsIsFoundButHasNothingToCheck() {
        let result = look(.init(tabs: [], unmount: false))
        #expect(result.verdict == .ok("strip and toolbar found, with no tab to look at"))
    }

    @Test func tabsOutsideTheStripAreNotCounted() {
        let result = look(.init(tabs: tabs(2), decoys: true))
        #expect(result.verdict == .ok("2 tabs, each with a close button, one shown"))
    }

    @Test func itPressesNothingAndReportsOnlyCounts() {
        let fake = FakeTabPage(.init(tabs: tabs(3)))
        let answer = fake.probe() ?? ""
        #expect(fake.clicks == "")
        #expect(fake.remaining == "t1,t2,t3")
        // Counts and a state word: no tab id or name.
        #expect(!answer.contains("t1"))
        #expect(answer == #"{"strip":"ok","tabs":3,"withButton":3,"withClose":3,"shown":1}"#)
    }

    @Test func anAnswerThatIsNotUnderstoodIsNotTheShapeCapsidReads() {
        let bad = ProbeVerdict.unexpectedShape("the page's answer wasn't understood")
        #expect(CompatProbeRules.tabStrip("") == bad)
        #expect(CompatProbeRules.tabStrip("[]") == bad)
        #expect(CompatProbeRules.tabStrip(#"{"strip":"ok"}"#) == bad)
        #expect(CompatProbeRules.tabStrip(#"{"strip":"elsewhere","tabs":0,"withButton":0,"withClose":0,"shown":0}"#) == bad)
        #expect(CompatProbeRules.tabStrip(#"{"strip":"ok","tabs":-1,"withButton":0,"withClose":0,"shown":0}"#) == bad)
        #expect(CompatProbeRules.tabStrip(#"{"strip":"ok","tabs":true,"withButton":0,"withClose":0,"shown":0}"#) == bad)
        #expect(CompatProbeRules.tabStrip(#"{"strip":"ok","tabs":1.5,"withButton":0,"withClose":0,"shown":0}"#) == bad)
    }

    @Test func aTabWithNoShowingButtonIsNotTheShapeCapsidReads() {
        let json = #"{"strip":"ok","tabs":3,"withButton":2,"withClose":3,"shown":1}"#
        #expect(CompatProbeRules.tabStrip(json) == .unexpectedShape("1 of 3 tabs have no button that shows them"))
    }

    @Test func theLookAndTheCommandsReadTheStripTheSameWay() {
        // The same function reads it for both: whatever the look calls "none",
        // the commands call "no-strip".
        let page = FakeTabPage(.init(tabs: tabs(2), toolbar: false))
        #expect(page.run("all") == .unavailable)
        #expect(page.answer.map { PageTabsReason(parsing: $0) } == .some(.noToolbar))
        #expect(look(.init(tabs: tabs(2), toolbar: false)).verdict == .unexpectedShape("the strip has no toolbar of open panels"))
    }
}

extension ProbeVerdict {
    /// A verdict that says something is wrong, as against fine or merely
    /// not on screen.
    var isFault: Bool {
        switch self {
        case .unexpectedShape, .failed: true
        case .ok, .notOnScreenNow: false
        }
    }
}

// MARK: The strip's reasons, from the commands

struct TabCommandReasonTests {
    private func reason(_ page: FakeTabDOM.Page, _ mode: String = "all", keep: String? = nil) -> PageTabsReason? {
        let fake = FakeTabPage(page)
        _ = fake.run(mode, keep: keep)
        return fake.answer.flatMap { PageTabsReason(parsing: $0) }
    }

    private func tabs(shown: String? = "t1") -> [FakeTabDOM.Tab] {
        FakeTabDOM.tabs("t1", "t2", "t3", shown: shown)
    }

    @Test func noStripIsTheOrdinaryReason() {
        #expect(reason(.init(tabs: tabs(), strips: 0)) == .noStrip)
    }

    @Test func aWrongStripNamesWhatIsWrong() {
        #expect(reason(.init(tabs: tabs(), strips: 2)) == .severalStrips)
        #expect(reason(.init(tabs: tabs(), toolbar: false)) == .noToolbar)
        var list = tabs()
        list[2].close = "none"
        #expect(reason(.init(tabs: list)) == .noCloseButton)
    }

    @Test func othersWithNoSingleShownTabSaysSoAndAMissingKeptTabDoesNot() {
        #expect(reason(.init(tabs: tabs(shown: nil)), "others") == .noShownTab)
        #expect(reason(.init(tabs: tabs()), "others", keep: "gone") == .tabMissing)
        #expect(reason(.init(tabs: tabs(shown: nil)), "others", keep: "t2") == nil)
    }

    @Test func aSweepThatRanHasNoReason() {
        #expect(reason(.init(tabs: tabs())) == nil)
        #expect(reason(.init(tabs: tabs()), "others") == nil)
    }
}

// MARK: Classifying the API's answers

struct ProbeClassificationTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Usage

    @Test func aUsageAnswerWithLimitsIsOk() {
        let whole = data(#"{"ok":true,"data":{"five_hour":{"utilization":3,"resets_at":null},"seven_day":{"utilization":20,"resets_at":null},"seven_day_opus":null}}"#)
        #expect(CompatProbeRules.usage(whole) == .ok("2 limits read"))
        let bare = data(#"{"five_hour":{"utilization":3}}"#)
        #expect(CompatProbeRules.usage(bare) == .ok("1 limit read"))
    }

    @Test func aUsageAnswerWithNoLimitsOrNotJSONOrRefusedIsNotTheShape() {
        #expect(CompatProbeRules.usage(data(#"{"ok":true,"data":{}}"#)) == .unexpectedShape("the usage answer has none of the limits Capsid reads"))
        #expect(CompatProbeRules.usage(data(#"{"ok":true,"data":{"limits":[{"name":"x"}]}}"#)) == .unexpectedShape("the usage answer has none of the limits Capsid reads"))
        #expect(CompatProbeRules.usage(data("<html>")) == .unexpectedShape("the usage answer couldn't be read"))
        #expect(CompatProbeRules.usage(data("[]")) == .unexpectedShape("the usage answer couldn't be read"))
        #expect(CompatProbeRules.usage(data(#"{"ok":false}"#)) == .unexpectedShape("the answer says ok: false"))
    }

    // MARK: Context

    @Test func aContextAnswerIsOkWithItsWindowAndTurns() {
        #expect(CompatProbeRules.context(data(#"{"window":200000,"turns":[{"ctx_total":10},{"ctx_total":20}]}"#))
                == .ok("a window size and 2 turns"))
        #expect(CompatProbeRules.context(data(#"{"window":200000,"turns":[]}"#)) == .ok("a window size and 0 turns"))
        #expect(CompatProbeRules.context(data(#"{"window":200000,"turns":[{"ctx_total":1}]}"#)) == .ok("a window size and 1 turn"))
    }

    @Test func aContextAnswerWithoutAWindowOrTurnsOrJSONIsNotTheShape() {
        #expect(CompatProbeRules.context(data(#"{"turns":[]}"#)) == .unexpectedShape("the context answer has no window size"))
        #expect(CompatProbeRules.context(data(#"{"window":200000}"#)) == .unexpectedShape("the context answer has no turns with a size"))
        #expect(CompatProbeRules.context(data("nope")) == .unexpectedShape("the context answer couldn't be read"))
    }

    // MARK: The frame and the plan

    @Test func aFrameWithAStatusIsOkAndIsKept() {
        let read = CompatProbeRules.frame(data(#"{"status":"completed","context_data":null}"#))
        #expect(read.verdict == .ok("a status, and the plan fields if it has a plan"))
        #expect(read.frame?.status == "completed")
    }

    @Test func aFrameWithNoStatusOrAWaitingPlanWithNoFileIsNotTheShape() {
        let none = CompatProbeRules.frame(data(#"{"name":"x"}"#))
        #expect(none.verdict == .unexpectedShape("the session's answer has no status"))
        #expect(none.frame == nil)
        let waiting = CompatProbeRules.frame(data(#"{"status":"awaiting_plan_approval","context_data":{}}"#))
        #expect(waiting.verdict == .unexpectedShape("a session waiting for its plan names no plan file"))
        #expect(waiting.frame != nil)
    }

    @Test func aPlanWithASummaryIsOkAndOneWithoutIsNot() {
        #expect(CompatProbeRules.plan(data(#"{"task_summary":"Screen buffers","steps":[{"title":"a"},{"title":"b"}]}"#)) == .ok("a summary, 2 steps"))
        #expect(CompatProbeRules.plan(data(#"{"task_summary":"Screen buffers"}"#)) == .ok("a summary"))
        #expect(CompatProbeRules.plan(data(#"{"steps":[]}"#)) == .unexpectedShape("the plan file has no summary"))
        #expect(CompatProbeRules.plan(data("[]")) == .unexpectedShape("the plan file wasn't a JSON object"))
    }

    // MARK: Keep's reads

    @Test func versionsAreOkWhenEachHasANumberAndATime() {
        #expect(CompatProbeRules.versions(.versions([FakePage.version(1)])) == .ok("1 version, each with a number and a time"))
        #expect(CompatProbeRules.versions(.versions([FakePage.version(1), FakePage.version(2), FakePage.version(3)]))
                == .ok("3 versions, each with a number and a time"))
        #expect(CompatProbeRules.versions(.versions([])) == .unexpectedShape("the list was empty"))
        #expect(CompatProbeRules.versions(.versions([FakePage.version(1), FakePage.version(2, at: nil)]))
                == .unexpectedShape("1 of 2 versions have no time"))
    }

    @Test func factsAreOkForTheVersionAskedWithANumberAndAChecksumOrNone() {
        let plan = FakePage.plan
        #expect(CompatProbeRules.facts(.facts(FakePage.facts()), version: plan) == .ok("a checksum and a number"))
        #expect(CompatProbeRules.facts(.facts(FakePage.facts(sha: nil)), version: plan)
                == .ok("a number, and no checksum (a file read from your Mac may have none)"))
        #expect(CompatProbeRules.facts(.facts(FakePage.facts()), version: FakePage.version(9).v) == .unexpectedShape("the answer was for another version"))
        #expect(CompatProbeRules.facts(.facts(FakePage.facts(number: nil)), version: plan) == .unexpectedShape("the answer has no version number"))
    }

    @Test func anAnswerOfTheWrongKindOrNoAnswerHasItsWords() {
        let plan = FakePage.plan
        #expect(CompatProbeRules.facts(.unreadable, version: plan) == .unexpectedShape("a version's details weren't the shape Capsid reads"))
        #expect(CompatProbeRules.facts(.versions([]), version: plan) == .unexpectedShape("a version's details weren't the shape Capsid reads"))
        #expect(CompatProbeRules.versions(.facts(FakePage.facts())) == .unexpectedShape("the list of an artifact's versions wasn't the shape Capsid reads"))
        for outcome in [ArtifactReadOutcome.bytes(Data()), .binary, .text("x", truncated: false)] {
            #expect(CompatProbeRules.versions(outcome) == .unexpectedShape("the list of an artifact's versions wasn't the shape Capsid reads"))
        }
        #expect(CompatProbeRules.versions(.lost) == .failed("signed out (401); Capsid signs back in by itself"))
        #expect(CompatProbeRules.facts(.missing, version: plan) == .failed("answered 404: the route may have moved, or that session is gone"))
        #expect(CompatProbeRules.facts(.tooBig, version: plan) == .failed("the answer exceeded the read limit"))
        #expect(CompatProbeRules.versions(.cancelled) == .failed("the read didn't complete"))
    }

    // MARK: Failures

    private func refused(_ message: String) -> NSError {
        NSError(domain: "WKErrorDomain", code: 4, userInfo: ["WKJavaScriptExceptionMessage": message])
    }

    @Test func aPageThatIsntUpYetIsNotOnScreenAndNotAFault() {
        #expect(CompatProbeRules.failure(WebAPIError.notReady) == .notOnScreenNow("the page isn't up yet"))
    }

    @Test func eachKindOfRefusalIsSaidInPlainWords() {
        #expect(CompatProbeRules.failure(refused("Error: HTTP 401")) == .failed("signed out (401); Capsid signs back in by itself"))
        #expect(CompatProbeRules.failure(refused("Error: HTTP 404")) == .failed("answered 404: the route may have moved, or that session is gone"))
        #expect(CompatProbeRules.failure(refused("Error: HTTP 405")) == .failed("answered 405: the route may have moved, or that session is gone"))
        #expect(CompatProbeRules.failure(refused("Error: HTTP 500")) == .failed("answered 500"))
        #expect(CompatProbeRules.failure(ProbeTimeout()) == .failed("no answer in time"))
        #expect(CompatProbeRules.failure(WebAPIError.notAllowed) == .failed("Capsid's list of readable paths doesn't allow it"))
        #expect(CompatProbeRules.failure(WebAPIError.badResponse) == .unexpectedShape("the page didn't hand back text"))
        #expect(CompatProbeRules.failure(refused("TypeError: Load failed")) == .failed("the read didn't complete"))
    }

    @Test func theErrorsTextNeverReachesTheReport() {
        // A refusal's message can hold an address with a session in it.
        let verdict = CompatProbeRules.failure(refused("HTTP 404 for /api/frames/0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5?shallow=true"))
        guard case .failed(let words) = verdict else { Issue.record("not failed"); return }
        #expect(!words.contains("0b7c2f4e"))
        #expect(!words.contains("/api"))
    }

    @Test func theStatusIsReadFromHTTPAndThreeDigitsOnly() {
        #expect(CompatProbeRules.httpStatus(in: "HTTP 503") == 503)
        #expect(CompatProbeRules.httpStatus(in: "Error: HTTP 404 (x)") == 404)
        #expect(CompatProbeRules.httpStatus(in: "HTTP 4") == nil)
        #expect(CompatProbeRules.httpStatus(in: "HTTP abc") == nil)
        #expect(CompatProbeRules.httpStatus(in: "no status") == nil)
    }

    // MARK: The other hooks

    @Test func theSignInButtonOnlyShowsWhileSignedOut() {
        #expect(CompatProbeRules.signIn(showing: false) == .notOnScreenNow("it shows only while signed out, so this can't be checked until then"))
        #expect(CompatProbeRules.signIn(showing: true) == .ok("found, which means the page is signed out"))
    }

    @Test func aSessionAddressNeedsASessionShown() {
        #expect(CompatProbeRules.sessionAddress(shown: nil) == .notOnScreenNow("no session is open in the window"))
        #expect(CompatProbeRules.sessionAddress(shown: "x") == .ok("the page names the session shown"))
    }

    @Test func theLinesUseTheDiagnosticsMarks() {
        #expect(ProbeResult(name: "A", verdict: .ok("fine")).line == "✓ A: fine")
        #expect(ProbeResult(name: "A", verdict: .ok("")).line == "✓ A")
        #expect(ProbeResult(name: "A", verdict: .unexpectedShape("why")).line == "✗ A: not the shape Capsid reads (why)")
        #expect(ProbeResult(name: "A", verdict: .notOnScreenNow("why")).line == "• A: not on screen now (why)")
        #expect(ProbeResult(name: "A", verdict: .failed("why")).line == "✗ A: couldn't be checked (why)")
    }
}

// MARK: Running them

/// A made-up page and daemon for the runner: it answers the reads it is
/// given, records every path asked for, and has no way to be written to.
@MainActor
private final class FakePage {
    nonisolated static let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
    /// The shown session's plan: made-up 36-character ids, as Keep's reads take.
    nonisolated static let plan = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
    nonisolated static let artifact = "6d1f0c2e-7a3b-4c8d-9e10-2b3c4d5e6f70"
    nonisolated static let digest = String(repeating: "ab12", count: 16)

    var ready = true
    var shown: String? = FakePage.session
    var tabs = #"{"strip":"ok","tabs":2,"withButton":2,"withClose":2,"shown":1}"#
    var signIn = false
    var answers: [String: Result<Data, NSError>] = [:]
    var hangs: Set<String> = []
    /// What the typed artifact reader answers, by read; a read not here is gone (404).
    var reads: [ArtifactRead: ArtifactReadOutcome] = [:]
    var readFailures: [ArtifactRead: any Error] = [:]
    var readHangs: Set<ArtifactRead> = []
    private(set) var asked: [String] = []
    private(set) var readsAsked: [ArtifactRead] = []

    init() {
        answers["/usage"] = .success(Data(#"{"ok":true,"data":{"five_hour":{"utilization":3,"resets_at":null},"seven_day":{"utilization":9,"resets_at":null}}}"#.utf8))
        answers["/frames/\(Self.session)/token-series"] = .success(Data(#"{"window":200000,"turns":[{"ctx_total":900}]}"#.utf8))
        answers["/frames/\(Self.session)?shallow=true"] = .success(Data(#"{"status":"completed","context_data":{"_plan_version_id":"\#(Self.plan)","_plan_artifact_id":"\#(Self.artifact)","_plan_approved":true}}"#.utf8))
        answers["/artifacts/versions/\(Self.plan)"] = .success(Data(#"{"task_summary":"Screen made-up buffers","steps":[{"title":"a"}]}"#.utf8))
        reads[.facts(version: Self.plan)] = .facts(Self.facts())
        reads[.versions(artifact: Self.artifact)] = .versions([Self.version(1), Self.version(2)])
    }

    nonisolated static func facts(version: String = FakePage.plan, number: Int? = 2, sha: String? = FakePage.digest) -> ArtifactFacts {
        ArtifactFacts(v: version, a: artifact, n: number, name: "plan.json", mime: "application/json", size: 900,
                      at: Date(timeIntervalSince1970: 1_791_833_400), sha: sha, isUpload: false, code: nil, codeCut: false,
                      environment: nil)
    }

    nonisolated static func version(_ number: Int, at: Date? = Date(timeIntervalSince1970: 1_791_833_400)) -> ArtifactVersion {
        ArtifactVersion(v: String(format: "%08lx-0000-4000-8000-%012lx", number, number), n: number, frame: nil, mime: nil,
                        size: 900, at: at, parent: nil)
    }

    func environment(timeout: Duration = .seconds(5)) -> CompatProbeEnvironment {
        CompatProbeEnvironment(
            isReady: { [unowned self] in self.ready },
            shownSession: { [unowned self] in self.shown },
            get: { [unowned self] path in
                self.asked.append(path)
                if self.hangs.contains(path) { try await Task.sleep(for: .seconds(30)) }
                switch self.answers[path] {
                case .success(let data)?: return data
                case .failure(let error)?: throw error
                case nil: throw NSError(domain: "WKErrorDomain", code: 4, userInfo: ["WKJavaScriptExceptionMessage": "HTTP 404"])
                }
            },
            tabStrip: { [unowned self] in self.tabs },
            signInShowing: { [unowned self] in self.signIn },
            artifactRead: { [unowned self] read in
                self.readsAsked.append(read)
                if self.readHangs.contains(read) { try await Task.sleep(for: .seconds(30)) }
                if let error = self.readFailures[read] { throw error }
                return self.reads[read] ?? .missing
            },
            timeout: timeout)
    }
}

@MainActor
struct CompatProbeRunTests {
    private let page = FakePage()

    private func verdicts(_ results: [ProbeResult]) -> [String: ProbeVerdict] {
        Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0.verdict) })
    }

    @Test func aWholePageReportsEachProbeInOrder() async {
        let results = await CompatProbes.run(page.environment())
        #expect(results.map(\.name) == CompatProbes.Name.all)
        #expect(results.map(\.line) == [
            "✓ Tab strip: 2 tabs, each with a close button, one shown",
            "• Sign in button: not on screen now (it shows only while signed out, so this can't be checked until then)",
            "✓ Session address: the page names the session shown",
            "✓ GET /api/usage: 2 limits read",
            "✓ GET /api/frames/<session>/token-series: a window size and 1 turn",
            "✓ GET /api/frames/<session>?shallow=true: a status, and the plan fields if it has a plan",
            "✓ GET /api/artifacts/versions/<version>: a summary, 1 step",
            "✓ GET /api/artifacts/<artifact>/versions: 2 versions, each with a number and a time",
            "✓ GET /api/artifacts/versions/<version>?include_metadata=true: a checksum and a number",
        ])
    }

    @Test func onlyReadsOfTheAllowedPathsAreMadeAndNoWriteIsPossible() async {
        _ = await CompatProbes.run(page.environment())
        #expect(page.asked == ["/usage", "/frames/\(FakePage.session)/token-series",
                               "/frames/\(FakePage.session)?shallow=true", "/artifacts/versions/\(FakePage.plan)"])
        for path in page.asked {
            #expect(WebContainer.isReadablePath(path), "\(path)")
            #expect(!WebContainer.isWritablePath(path), "\(path)")
            #expect(!path.contains("approve-plan") && !path.contains("resolve-input") && !path.contains("messages"))
        }
    }

    @Test func keepsTwoReadsAreThePureOnesOnThePlansArtifactAndNeverTheLineage() async {
        _ = await CompatProbes.run(page.environment())
        // The facts first (they name the artifact when the frame doesn't), then the versions.
        #expect(page.readsAsked == [.facts(version: FakePage.plan), .versions(artifact: FakePage.artifact)])
        for read in page.readsAsked {
            switch read {
            case .versions, .facts: break
            default: Issue.record("a probe asked for \(read)")
            }
            #expect(read.path.map(ArtifactRead.isAllowedPath) == true)
        }
        // Nothing but looks: not one of the typed reads is the lineage, a download, a thumbnail or a list.
        #expect(!page.readsAsked.contains { if case .lineage = $0 { true } else { false } })
    }

    @Test func theArtifactTheFrameDoesntNameIsTakenFromTheFacts() async {
        page.answers["/frames/\(FakePage.session)?shallow=true"] = .success(Data(#"{"status":"completed","context_data":{"_plan_version_id":"\#(FakePage.plan)","_plan_approved":true}}"#.utf8))
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(page.readsAsked == [.facts(version: FakePage.plan), .versions(artifact: FakePage.artifact)])
        #expect(results[CompatProbes.Name.versions] == .ok("2 versions, each with a number and a time"))
    }

    @Test func aPlanWithNoFullIdsIsNotOnScreenAndAsksForNothing() async {
        page.answers["/frames/\(FakePage.session)?shallow=true"] = .success(Data(#"{"status":"completed","context_data":{"_plan_version_id":"ver-001","_plan_artifact_id":"art-1","_plan_approved":true}}"#.utf8))
        page.answers["/artifacts/versions/ver-001"] = .success(Data(#"{"task_summary":"Screen made-up buffers"}"#.utf8))
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.plan] == .ok("a summary"))
        #expect(results[CompatProbes.Name.facts] == .notOnScreenNow("the shown session's plan has no 36-character version id"))
        #expect(results[CompatProbes.Name.versions] == .notOnScreenNow("the shown session's plan has no 36-character artifact id"))
        #expect(page.readsAsked.isEmpty)
    }

    @Test func aKeepReadThatIsGoneOrSignedOutOrSlowIsFailedAndTheRestStillRun() async {
        page.reads[.facts(version: FakePage.plan)] = .lost
        page.reads[.versions(artifact: FakePage.artifact)] = nil
        var results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.facts] == .failed("signed out (401); Capsid signs back in by itself"))
        #expect(results[CompatProbes.Name.versions] == .failed("answered 404: the route may have moved, or that session is gone"))
        #expect(results[CompatProbes.Name.plan] == .ok("a summary, 1 step"))

        let slow = FakePage()
        slow.readHangs = [.facts(version: FakePage.plan)]
        slow.readFailures[.versions(artifact: FakePage.artifact)] = WebAPIError.notAllowed
        results = verdicts(await CompatProbes.run(slow.environment(timeout: .milliseconds(80))))
        #expect(results[CompatProbes.Name.facts] == .failed("no answer in time"))
        #expect(results[CompatProbes.Name.versions] == .failed("Capsid's list of readable paths doesn't allow it"))
    }

    @Test func aKeepAnswerThatIsntTheShapeIsReportedAsSuch() async {
        page.reads[.facts(version: FakePage.plan)] = .unreadable
        page.reads[.versions(artifact: FakePage.artifact)] = .versions([])
        var results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.facts] == .unexpectedShape("a version's details weren't the shape Capsid reads"))
        #expect(results[CompatProbes.Name.versions] == .unexpectedShape("the list was empty"))
        // An answer for another version of the plan is no answer.
        page.reads[.facts(version: FakePage.plan)] = .facts(FakePage.facts(version: FakePage.version(9).v))
        results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.facts] == .unexpectedShape("the answer was for another version"))
    }

    @Test func aPageThatIsntUpIsNotOnScreenAndAsksNothing() async {
        page.ready = false
        let results = await CompatProbes.run(page.environment())
        #expect(results.map(\.name) == CompatProbes.Name.all)
        #expect(results.allSatisfy { $0.verdict == .notOnScreenNow("the page isn't up yet") })
        #expect(page.asked.isEmpty)
    }

    @Test func withNoSessionShownTheSessionProbesAreNotOnScreen() async {
        page.shown = nil
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(page.asked == ["/usage"])
        #expect(page.readsAsked.isEmpty)
        for name in [CompatProbes.Name.address, CompatProbes.Name.context, CompatProbes.Name.frame, CompatProbes.Name.plan,
                     CompatProbes.Name.versions, CompatProbes.Name.facts] {
            #expect(results[name] == .notOnScreenNow("no session is open in the window"), "\(name)")
        }
        #expect(results[CompatProbes.Name.usage]?.isFault == false)
    }

    @Test func aSessionWithNoPlanDoesntAskForOne() async {
        page.answers["/frames/\(FakePage.session)?shallow=true"] = .success(Data(#"{"status":"completed","context_data":null}"#.utf8))
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.plan] == .notOnScreenNow("the shown session has no plan"))
        #expect(results[CompatProbes.Name.versions] == .notOnScreenNow("the shown session has no plan"))
        #expect(results[CompatProbes.Name.facts] == .notOnScreenNow("the shown session has no plan"))
        #expect(page.asked.count == 3 && page.readsAsked.isEmpty)
    }

    @Test func aPlanVersionNotFitForAPathIsNotAsked() async {
        page.answers["/frames/\(FakePage.session)?shallow=true"] = .success(Data(#"{"status":"completed","context_data":{"_plan_version_id":"../etc"}}"#.utf8))
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.plan] == .notOnScreenNow("the shown session has no plan"))
        #expect(results[CompatProbes.Name.facts] == .notOnScreenNow("the shown session has no plan"))
        #expect(!page.asked.contains { $0.contains("..") })
        #expect(page.readsAsked.isEmpty)
    }

    @Test func eachShapeProblemIsReportedWhereItIs() async {
        page.answers["/usage"] = .success(Data(#"{"ok":true,"data":{}}"#.utf8))
        page.answers["/frames/\(FakePage.session)/token-series"] = .success(Data(#"{"turns":[]}"#.utf8))
        page.answers["/frames/\(FakePage.session)?shallow=true"] = .success(Data(#"{"name":"x"}"#.utf8))
        page.tabs = #"{"strip":"several","tabs":0,"withButton":0,"withClose":0,"shown":0}"#
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.usage] == .unexpectedShape("the usage answer has none of the limits Capsid reads"))
        #expect(results[CompatProbes.Name.context] == .unexpectedShape("the context answer has no window size"))
        #expect(results[CompatProbes.Name.frame] == .unexpectedShape("the session's answer has no status"))
        #expect(results[CompatProbes.Name.tabStrip] == .unexpectedShape("the page has more than one tab strip"))
        // With no readable frame there is no plan to follow.
        #expect(results[CompatProbes.Name.plan] == .notOnScreenNow("the shown session has no plan"))
    }

    @Test func aReadThatIsRefusedIsFailedAndTheRestStillRun() async {
        page.answers["/usage"] = .failure(NSError(domain: "WKErrorDomain", code: 4, userInfo: ["WKJavaScriptExceptionMessage": "Error: HTTP 401"]))
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.usage] == .failed("signed out (401); Capsid signs back in by itself"))
        #expect(results[CompatProbes.Name.context]?.isFault == false)
        #expect(page.asked.count == 4)
    }

    @Test func aReadThatNeverAnswersTimesOutAndTheRestStillRun() async {
        page.hangs = ["/usage"]
        let results = verdicts(await CompatProbes.run(page.environment(timeout: .milliseconds(80))))
        #expect(results[CompatProbes.Name.usage] == .failed("no answer in time"))
        #expect(results[CompatProbes.Name.context] == .ok("a window size and 1 turn"))
    }

    @Test func aSessionIdOutOfShapeIsReportedNotSent() async {
        page.shown = "abc"
        page.answers["/frames/abc/token-series"] = .success(Data(#"{"window":10,"turns":[]}"#.utf8))
        let results = verdicts(await CompatProbes.run(page.environment()))
        #expect(results[CompatProbes.Name.frame] == .unexpectedShape("the session's id isn't the 36-character id Capsid reads"))
        #expect(results[CompatProbes.Name.versions] == .notOnScreenNow("the session has no readable id"))
        #expect(results[CompatProbes.Name.facts] == .notOnScreenNow("the session has no readable id"))
        #expect(page.asked == ["/usage", "/frames/abc/token-series"] && page.readsAsked.isEmpty)
    }

    @Test func aSessionIdIsMadeSafeAsOnePathSegment() async {
        page.shown = "a/b?c"
        _ = await CompatProbes.run(page.environment())
        #expect(page.asked.contains("/frames/a%2Fb%3Fc/token-series"))
    }

    @Test func theTabAndSignInLooksFailWithoutStoppingTheReads() async {
        let broken = CompatProbeEnvironment(
            isReady: { true }, shownSession: { nil },
            get: { _ in throw WebAPIError.badResponse },
            tabStrip: { throw ProbeTimeout() },
            signInShowing: { throw WebAPIError.notReady },
            artifactRead: { _ in throw WebAPIError.notReady },
            timeout: .seconds(1))
        let results = verdicts(await CompatProbes.run(broken))
        #expect(results[CompatProbes.Name.tabStrip] == .failed("no answer in time"))
        #expect(results[CompatProbes.Name.signIn] == .notOnScreenNow("the page isn't up yet"))
        #expect(results[CompatProbes.Name.usage] == .unexpectedShape("the page didn't hand back text"))
    }

    // MARK: The whole addition to the report

    @Test func theWindowsPageReportHasTheProbesWhatIsCheckedOnlyWhenUsedAndTheLastProblem() async {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        let quiet = await Diagnose.pageReport(environment: page.environment(), breadcrumbs: store)
        #expect(quiet.first == "")
        #expect(quiet.contains(CompatReport.probesHeading))
        #expect(quiet.contains(CompatReport.whenUsedHeading))
        #expect(!quiet.contains { $0.hasPrefix("Last problem") })

        store.record(.tabWithoutCloseButton)
        harness.advance(125)
        let noisy = await Diagnose.pageReport(environment: page.environment(), breadcrumbs: store)
        #expect(noisy.suffix(2) == ["", "Last problem: Close Other Tabs, 2 minutes ago: a tab has no close button"])
    }

    @Test func theCommandLineSaysThePageChecksNeedTheWindow() {
        #expect(CompatReport.notFromTheCommandLine.hasPrefix("• Page and API checks"))
        #expect(CompatReport.notFromTheCommandLine.contains("Help → Capsid Diagnostics…"))
    }

    @Test func everyWriteAndEveryReadTheProbesCantMakeIsListedAsCheckedOnlyWhenUsed() {
        let lines = CompatReport.whenUsedLines()
        #expect(lines.first == "Checked only when used:")
        for write in CompatInventory.writeEndpoints {
            #expect(lines.contains("• \(write.token): \(write.feature.title) (it changes things, so Diagnostics never sends it)"), "\(write.token)")
        }
        #expect(lines.contains("• GET /api/frames/<session>/messages?from=<n>&limit=<n>: Capsid on your phone (it is what was said, so it is never read from here)"))
        // A read the probes make is not on the list.
        for name in CompatProbes.Name.all where name.hasPrefix("GET ") {
            #expect(!lines.contains { $0.hasPrefix("• \(name):") }, "\(name)")
        }
        // Keep's two that they don't: the lineage can start a reconstruction, and the messages are what was said.
        #expect(lines.contains("• GET /api/artifacts/versions/<version>/lineage?slim=1: Keep a figure with its answer, data and script (reading it can start Claude Science's own code reconstruction, so it is not read from here)"))
        #expect(lines.contains("• _artifact_refs and _ts on GET /api/frames/<session>/messages: Keep a figure with its answer, data and script (it is what was said, so it is never read from here)"))
    }
}
