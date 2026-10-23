// CompatBreadcrumbTests.swift — the last time a feature found Claude Science
// changed: what is recorded, what is not (ordinary states), how it reads in
// Diagnostics, and that the log gets one line, not a line per read. Every test
// uses a breadcrumb store of its own, never the shared one, and all the data
// is made up.
import Foundation
import Testing
@testable import Bench

/// A clock the test moves, and the log lines it collected.
final class BreadcrumbHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var moment = Date(timeIntervalSince1970: 1_800_000_000)
    private var lines: [String] = []

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return moment
    }

    var logged: [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); moment = moment.addingTimeInterval(seconds); lock.unlock()
    }

    func log(_ text: String) {
        lock.lock(); lines.append(text); lock.unlock()
    }

    func makeStore() -> CompatBreadcrumbs {
        CompatBreadcrumbs(now: { [self] in now }, emit: { [self] in log($0) })
    }
}

struct CompatBreadcrumbTests {
    private let harness = BreadcrumbHarness()

    // MARK: Recording

    @Test func nothingIsRecordedUntilSomethingMisses() {
        let store = harness.makeStore()
        #expect(store.last == nil)
        #expect(store.line() == nil)
    }

    @Test func theLastMissIsKeptWithTheTimeItHappened() {
        let store = harness.makeStore()
        let first = harness.now
        store.record(.tabStripWithoutToolbar)
        harness.advance(90)
        store.record(.usageWithoutLimits)
        #expect(store.last == CompatBreadcrumbs.Entry(miss: .usageWithoutLimits, at: first.addingTimeInterval(90)))
    }

    @Test func theLineNamesTheFeatureTheTimeAndWhatWasMissing() {
        let store = harness.makeStore()
        store.record(.tabStripWithoutToolbar)
        #expect(store.line() == "Last problem: Close Other Tabs, just now: the tab strip has no toolbar of open panels")
        harness.advance(12 * 60 + 5)
        #expect(store.line() == "Last problem: Close Other Tabs, 12 minutes ago: the tab strip has no toolbar of open panels")
    }

    @Test func ageIsPlainEnglishAtEveryScale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func age(_ seconds: TimeInterval) -> String { CompatBreadcrumbs.age(of: now.addingTimeInterval(-seconds), now: now) }
        #expect(age(0) == "just now")
        #expect(age(59) == "just now")
        #expect(age(60) == "1 minute ago")
        #expect(age(119) == "1 minute ago")
        #expect(age(59 * 60) == "59 minutes ago")
        #expect(age(3600) == "1 hour ago")
        #expect(age(5 * 3600 + 59) == "5 hours ago")
        #expect(age(86_400) == "1 day ago")
        #expect(age(3 * 86_400) == "3 days ago")
        // A clock that went backwards is not a negative age.
        #expect(CompatBreadcrumbs.age(of: now.addingTimeInterval(500), now: now) == "just now")
    }

    // MARK: The log

    @Test func aMissIsLoggedOnceWhateverTheReadsKeepSaying() {
        let store = harness.makeStore()
        let start = harness.now
        for _ in 0..<5 {
            store.record(.usageWithoutLimits)
            harness.advance(300)
        }
        // Five reads, five minutes apart: noted at the start, then at ten and at twenty minutes.
        #expect(harness.logged.count == 3)
        #expect(harness.logged.allSatisfy { $0 == "Claude Science may have changed: The usage readout: the usage answer has none of the limits Capsid reads" })
        #expect(store.last?.at == start.addingTimeInterval(1200))
    }

    @Test func aRepeatKeepsTheFirstTimeSoTheLineDoesntRestartEveryRead() {
        let store = harness.makeStore()
        store.record(.usageWithoutLimits)
        harness.advance(300)
        store.record(.usageWithoutLimits)
        // Five minutes on, still the first miss's time, not "just now".
        #expect(store.line() == "Last problem: The usage readout, 5 minutes ago: the usage answer has none of the limits Capsid reads")
        harness.advance(299)
        store.record(.usageWithoutLimits)
        #expect(store.line()?.contains("9 minutes ago") == true)
        // Ten minutes after the first, a repeat is noted again.
        harness.advance(1)
        store.record(.usageWithoutLimits)
        #expect(store.line()?.contains("just now") == true)
        #expect(harness.logged.count == 2)
    }

    @Test func aMissThatComesBackAfterAnotherIsNotAStaleRepeat() {
        let store = harness.makeStore()
        store.record(.usageWithoutLimits)
        harness.advance(60)
        store.record(.contextWithoutWindow)
        harness.advance(60)
        store.record(.usageWithoutLimits)
        #expect(store.last?.miss == .usageWithoutLimits)
        #expect(harness.logged.count == 3)
    }

    @Test func aUsageAnswerWithNoLimitsReadEveryFiveMinutesIsOneProblem() throws {
        let store = harness.makeStore()
        let empty = Data(#"{"ok":true,"data":{}}"#.utf8)
        _ = try PlanUsageModel.parseNoting(empty, breadcrumbs: store)
        harness.advance(300)
        _ = try PlanUsageModel.parseNoting(empty, breadcrumbs: store)
        #expect(store.line()?.contains("5 minutes ago") == true)
        #expect(harness.logged.count == 1)
    }

    @Test func aDifferentMissIsLoggedAtOnce() {
        let store = harness.makeStore()
        store.record(.usageWithoutLimits)
        store.record(.contextWithoutWindow)
        store.record(.usageWithoutLimits)
        #expect(harness.logged.count == 3)
    }

    // MARK: The words

    @Test func everyMissHasAFeatureAndAPlainPhrase() {
        for miss in CompatMiss.allCases {
            let phrase = miss.phrase
            #expect(!phrase.isEmpty)
            #expect(phrase.first?.isLowercase == true, "\(miss)")
            #expect(!phrase.hasSuffix("."), "\(miss)")
            // Nothing that could be a name or an id: the phrase is fixed text.
            #expect(!phrase.contains { $0.isNumber }, "\(miss)")
            #expect(CompatFeature.allCases.contains(miss.feature))
            #expect(!miss.feature.shortTitle.isEmpty)
        }
        #expect(Set(CompatMiss.allCases.map(\.phrase)).count == CompatMiss.allCases.count)
    }
}

// MARK: Which states are misses

struct CompatMissRuleTests {
    // MARK: The tab commands

    @Test func aWrongStripIsAMissAndNoStripIsNot() {
        #expect(PageTabsReason.noStrip.miss == nil)
        #expect(PageTabsReason.tabMissing.miss == nil)
        #expect(PageTabsReason.severalStrips.miss == .severalTabStrips)
        #expect(PageTabsReason.noToolbar.miss == .tabStripWithoutToolbar)
        #expect(PageTabsReason.noCloseButton.miss == .tabWithoutCloseButton)
        #expect(PageTabsReason.noShownTab.miss == .noTabMarkedShown)
    }

    @Test func theScriptsReasonIsReadFromItsAnswer() {
        #expect(PageTabsReason(parsing: #"{"status":"unavailable","closed":0,"stayed":0,"reason":"no-toolbar"}"#) == .noToolbar)
        #expect(PageTabsReason(parsing: #"{"status":"done","closed":1,"stayed":0}"#) == nil)
        #expect(PageTabsReason(parsing: #"{"status":"unavailable","reason":"something-new"}"#) == nil)
        #expect(PageTabsReason(parsing: #"{"status":"unavailable","reason":5}"#) == nil)
        #expect(PageTabsReason(parsing: "not json") == nil)
    }

    @Test func theSweepsAnswerIsNotedAsTheStateItSays() {
        func note(_ value: Any?) -> (PageTabsOutcome?, CompatMiss?) {
            let store = BreadcrumbHarness().makeStore()
            let outcome = PageTabsOutcome.read(value, breadcrumbs: store)
            return (outcome, store.last?.miss)
        }
        // Done, and the ordinary nothing-to-do states, note nothing.
        #expect(note(#"{"status":"done","closed":2,"stayed":0}"#).1 == nil)
        #expect(note(#"{"status":"unavailable","closed":0,"stayed":0,"reason":"no-strip"}"#) == (.unavailable, nil))
        #expect(note(#"{"status":"refused","closed":0,"stayed":0,"reason":"tab-missing"}"#) == (.refused, nil))
        // A strip that is wrong is a change.
        #expect(note(#"{"status":"unavailable","closed":0,"stayed":0,"reason":"no-toolbar"}"#) == (.unavailable, .tabStripWithoutToolbar))
        #expect(note(#"{"status":"unavailable","closed":0,"stayed":0,"reason":"several-strips"}"#).1 == .severalTabStrips)
        #expect(note(#"{"status":"unavailable","closed":0,"stayed":0,"reason":"no-close-button"}"#).1 == .tabWithoutCloseButton)
        #expect(note(#"{"status":"refused","closed":0,"stayed":0,"reason":"no-shown-tab"}"#) == (.refused, .noTabMarkedShown))
        // An answer that isn't one is a change too, and gives no outcome.
        #expect(note("not json") == (nil, .tabAnswerNotUnderstood))
        #expect(note(nil) == (nil, .tabAnswerNotUnderstood))
        #expect(note(42) == (nil, .tabAnswerNotUnderstood))
        #expect(note(#"{"status":"done","closed":-1,"stayed":0}"#) == (nil, .tabAnswerNotUnderstood))
    }

    // MARK: The context ring

    private func series(_ json: String) throws -> TokenSeries {
        try TokenSeries.decode(Data(json.utf8))
    }

    @Test func aWholeContextAnswerIsNoMiss() throws {
        #expect(try series(#"{"window":200000,"turns":[{"ctx_total":1200},{"ctx_total":4100}],"truncated":false}"#).shapeMiss == nil)
    }

    @Test func aSessionWithNoTurnsYetOrOneStillUnderWayIsNotAMiss() throws {
        #expect(try series(#"{"window":200000,"turns":[]}"#).shapeMiss == nil)
        #expect(try series(#"{"window":200000,"turns":[{}]}"#).shapeMiss == nil)
        #expect(try series(#"{"window":200000,"turns":[{"ctx_total":5},{}]}"#).shapeMiss == nil)
    }

    @Test func aMissingWindowOrTurnsListOrSizesIsAMiss() throws {
        #expect(try series(#"{"turns":[{"ctx_total":5}]}"#).shapeMiss == .contextWithoutWindow)
        #expect(try series(#"{"window":0,"turns":[]}"#).shapeMiss == .contextWithoutWindow)
        #expect(try series(#"{"window":200000}"#).shapeMiss == .contextWithoutTurns)
        #expect(try series(#"{"window":200000,"turns":[{"tokens":1},{"tokens":2}]}"#).shapeMiss == .contextWithoutTurns)
        #expect(try series("{}").shapeMiss == .contextWithoutWindow)
    }

    @Test func theRingNotesAnAnswerThatDoesntDecodeOrLacksWhatItNeeds() throws {
        func note(_ json: String) -> (TokenSeries?, CompatMiss?) {
            let store = BreadcrumbHarness().makeStore()
            let series = try? TokenSeries.decodeNoting(Data(json.utf8), breadcrumbs: store)
            return (series, store.last?.miss)
        }
        #expect(note(#"{"window":200000,"turns":[{"ctx_total":5}]}"#).1 == nil)
        #expect(note(#"{"window":200000,"turns":[]}"#).1 == nil)
        #expect(note(#"{"turns":[{"ctx_total":5}]}"#).1 == .contextWithoutWindow)
        #expect(note(#"{"window":200000}"#).1 == .contextWithoutTurns)
        let broken = note("<html>")
        #expect(broken.0 == nil)
        #expect(broken.1 == .contextNotDecoded)
    }

    @Test func anAnswerThatIsNotOfThatShapeAtAllDoesntDecode() {
        #expect(throws: DecodingError.self) { try series("[1,2]") }
        #expect(throws: DecodingError.self) { try series("not json") }
        #expect(throws: DecodingError.self) { try series(#"{"window":"big"}"#) }
    }

    // MARK: The usage readout

    private let wholeUsage = Data(#"{"ok":true,"data":{"five_hour":{"utilization":12.5,"resets_at":"2026-10-19T18:00:00Z"},"seven_day":{"utilization":40,"resets_at":null}}}"#.utf8)

    @Test func aReadableUsageAnswerIsNoMiss() throws {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        let parsed = try PlanUsageModel.parseNoting(wholeUsage, breadcrumbs: store)
        #expect(parsed.limits.count == 2)
        #expect(store.last == nil)
    }

    @Test func anAnswerWithNoneOfTheLimitsIsAMiss() throws {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        let parsed = try PlanUsageModel.parseNoting(Data(#"{"ok":true,"data":{"limits":[]}}"#.utf8), breadcrumbs: store)
        #expect(parsed.limits.isEmpty)
        #expect(store.last?.miss == .usageWithoutLimits)
    }

    @Test func anAnswerThatIsNotJSONIsAMiss() {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        #expect(throws: (any Error).self) { try PlanUsageModel.parseNoting(Data("<html>".utf8), breadcrumbs: store) }
        #expect(store.last?.miss == .usageNotDecoded)
    }

    @Test func theDaemonSayingNoIsNotAChange() {
        let harness = BreadcrumbHarness()
        let store = harness.makeStore()
        #expect(throws: PlanUsageModel.PlanUsageError.self) {
            try PlanUsageModel.parseNoting(Data(#"{"ok":false,"error":"busy"}"#.utf8), breadcrumbs: store)
        }
        #expect(store.last == nil)
    }

    // MARK: The plan on a card

    private func frame(status: String = "awaiting_plan_approval", version: String? = "ver-001", approved: Bool = false) -> PlanFrame {
        PlanFrame(status: status, versionID: version, artifactID: nil, approval: approved ? .yes : .no)
    }

    @Test func aWaitingPlanThatNamesNoFileIsAMissButOrdinaryStatesAreNot() {
        #expect(PlanCheck.frameMiss(frame()) == nil)
        #expect(PlanCheck.frameMiss(frame(version: nil)) == .planWithoutVersion)
        #expect(PlanCheck.frameMiss(frame(version: "../x")) == .planWithoutVersion)
        // A sub-agent waiting leaves the root processing; an approved plan has nothing to read.
        #expect(PlanCheck.frameMiss(frame(status: "processing", version: nil)) == nil)
        #expect(PlanCheck.frameMiss(frame(version: nil, approved: true)) == nil)
        #expect(PlanCheck.frameMiss(PlanFrame(status: "awaiting_plan_approval", versionID: nil, artifactID: nil, approval: .unclear)) == nil)
    }

    @Test func aPlanFileThatIsNotAnObjectOrHasNoSummaryIsAMiss() {
        #expect(PlanCheck.planMiss(PlanDocument(json: Data(#"{"task_summary":"Screen buffers"}"#.utf8))) == nil)
        #expect(PlanCheck.planMiss(PlanDocument(json: Data("[1]".utf8))) == .planFileNotUnderstood)
        #expect(PlanCheck.planMiss(PlanDocument(json: Data("nope".utf8))) == .planFileNotUnderstood)
        #expect(PlanCheck.planMiss(PlanDocument(json: Data(#"{"steps":[]}"#.utf8))) == .planFileWithoutSummary)
        #expect(PlanCheck.planMiss(PlanDocument(json: Data(#"{"task_summary":"   "}"#.utf8))) == .planFileWithoutSummary)
    }

    private func answer(_ status: Int, json: Bool = true, accepted: Bool = false, code: String? = nil) -> APIWriteResult {
        APIWriteResult(status: status, isJSON: json, code: code, accepted: accepted, noPlanAwaiting: false)
    }

    @Test func approveAnswersThatMeanTheRouteChangedAreMisses() {
        #expect(PlanCheck.writeMiss(answer(404)) == .approveRouteGone)
        #expect(PlanCheck.writeMiss(answer(405)) == .approveRouteGone)
        #expect(PlanCheck.writeMiss(answer(200, accepted: false)) == .approveAnswerNotUnderstood)
        #expect(PlanCheck.writeMiss(answer(200, json: false, accepted: true)) == .approveAnswerNotUnderstood)
    }

    @Test func approveAnswersThatAreTheDaemonSayingNoAreNot() {
        #expect(PlanCheck.writeMiss(answer(200, accepted: true)) == nil)
        #expect(PlanCheck.writeMiss(answer(400, code: "plan_already_approved")) == nil)
        #expect(PlanCheck.writeMiss(answer(400, code: "plan_frame_processing")) == nil)
        #expect(PlanCheck.writeMiss(answer(401)) == nil)
        #expect(PlanCheck.writeMiss(answer(403, code: "csrf_stale")) == nil)
        #expect(PlanCheck.writeMiss(answer(500)) == nil)
    }
}

// MARK: The approver notes them

/// A made-up daemon for the approver: frames and plans from fields, every
/// post answered as set. Nothing reaches a real one.
@MainActor
private final class CompatDaemon {
    static let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"

    var frame: Data? = CompatDaemon.frame()
    var plan: Data? = Data(#"{"task_summary":"Screen made-up buffers","steps":[{"title":"a"}]}"#.utf8)
    var answer = APIWriteResult(status: 200, isJSON: true, code: nil, accepted: true, noPlanAwaiting: false)
    let breadcrumbs: CompatBreadcrumbs

    init(_ breadcrumbs: CompatBreadcrumbs) { self.breadcrumbs = breadcrumbs }

    static func frame(status: String = "awaiting_plan_approval", context: String = #"{"_plan_version_id":"ver-001","_plan_approved":false}"#) -> Data {
        Data(#"{"status":"\#(status)","context_data":\#(context),"output_data":null}"#.utf8)
    }

    func dependencies() -> PlanApprover.Dependencies {
        PlanApprover.Dependencies(
            isEnabled: { true }, isReady: { true },
            get: { [self] path in
                if path.hasPrefix("/frames/"), let frame = self.frame { return frame }
                if path.hasPrefix("/artifacts/versions/"), let plan = self.plan { return plan }
                throw WebAPIError.badResponse
            },
            post: { [self] _ in self.answer },
            approvedPause: .milliseconds(10),
            breadcrumbs: breadcrumbs)
    }
}

@MainActor
struct CompatApproverTests {
    private let harness = BreadcrumbHarness()
    private let model = LabModel()

    private func read(_ daemon: CompatDaemon) async -> PlanApprover {
        let id = CompatDaemon.session
        model.ingest(Fixture.snapshot(Fixture.session(id, .running)))
        model.ingest(Fixture.snapshot(Fixture.session(id, .needsInput, reason: .plan)))
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.sync()
        await approver.settled()
        return approver
    }

    @Test func aPlanThatReadsFineNotesNothing() async {
        let store = harness.makeStore()
        let approver = await read(CompatDaemon(store))
        if case .ready? = approver.state(for: CompatDaemon.session) {} else { Issue.record("not ready") }
        #expect(store.last == nil)
    }

    @Test func anAnswerThatIsNotAFrameIsNoted() async {
        let store = harness.makeStore()
        let daemon = CompatDaemon(store)
        daemon.frame = Data("[]".utf8)
        let approver = await read(daemon)
        #expect(approver.state(for: CompatDaemon.session) == .unavailable)
        #expect(store.last?.miss == .planFrameNotUnderstood)
    }

    @Test func aWaitingPlanThatNamesNoFileIsNoted() async {
        let store = harness.makeStore()
        let daemon = CompatDaemon(store)
        daemon.frame = CompatDaemon.frame(context: #"{"_plan_approved":false}"#)
        _ = await read(daemon)
        #expect(store.last?.miss == .planWithoutVersion)
    }

    @Test func aPlanFileWithNoSummaryIsNoted() async {
        let store = harness.makeStore()
        let daemon = CompatDaemon(store)
        daemon.plan = Data(#"{"steps":[]}"#.utf8)
        _ = await read(daemon)
        #expect(store.last?.miss == .planFileWithoutSummary)
    }

    @Test func aReadThatFailsOrASubAgentWaitingIsNotNoted() async {
        let failing = harness.makeStore()
        let broken = CompatDaemon(failing)
        broken.frame = nil
        _ = await read(broken)
        #expect(failing.last == nil)

        let sub = harness.makeStore()
        let waiting = CompatDaemon(sub)
        waiting.frame = CompatDaemon.frame(status: "processing", context: "null")
        _ = await read(waiting)
        #expect(sub.last == nil)
    }

    @Test func anApproveRouteThatIsGoneIsNoted() async {
        let store = harness.makeStore()
        let daemon = CompatDaemon(store)
        daemon.answer = APIWriteResult(status: 404, isJSON: false, code: nil, accepted: false, noPlanAwaiting: false)
        let approver = await read(daemon)
        approver.approve(CompatDaemon.session)
        await approver.settled()
        #expect(store.last?.miss == .approveRouteGone)
    }

    @Test func anApproveTheDaemonRefusesInItsOwnWordsIsNot() async {
        let store = harness.makeStore()
        let daemon = CompatDaemon(store)
        daemon.answer = APIWriteResult(status: 400, isJSON: true, code: "plan_frame_processing", accepted: false, noPlanAwaiting: false)
        let approver = await read(daemon)
        approver.approve(CompatDaemon.session)
        await approver.settled()
        #expect(store.last == nil)
    }
}
