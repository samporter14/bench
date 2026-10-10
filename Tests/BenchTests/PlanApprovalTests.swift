// PlanApprovalTests.swift — approving a plan from its card, on made-up JSON.
// Nothing here comes from a real Claude Science daemon: the frames, plans and
// answers are invented, and the approver's reads and posts go to a fake that
// only records them. Models under test are fresh ones, never `shared`.
import Foundation
import Testing
@testable import Bench

// MARK: Made-up responses

private enum Made {
    /// Full, made-up frame ids.
    static let root = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
    static let other = "9f8e7d6c-5b4a-4321-8fed-cba987654321"

    /// A shallow frame. The fields Bench must not keep are there too.
    static func frame(status: String = "awaiting_plan_approval",
                      context: String? = #"{"_plan_version_id": "ver-001", "_plan_artifact_id": "art-001", "_plan_approved": false, "_plan_generated_at": 1767225600000}"#,
                      output: String? = nil) -> Data {
        Data("""
        {
          "id": "\(root)",
          "name": "Made-up session",
          "task_summary": "Not the plan's summary",
          "input_data": { "request": "Made-up request" },
          "status": "\(status)",
          "context_data": \(context ?? "null"),
          "output_data": \(output ?? "null")
        }
        """.utf8)
    }

    /// A plan in the current shape: 2 phases, 3 delegations, 5 steps.
    static let phasedPlan = Data("""
    {
      "task_summary": "Screen made-up buffers at two temperatures",
      "phases": [
        { "title": "Prepare", "delegations": [
            { "agent": "A", "steps": [ { "title": "One", "description": "x" }, { "title": "Two" } ] },
            { "agent": "B", "steps": [ { "title": "Three" } ] } ] },
        { "title": "Measure", "delegations": [
            { "agent": "C", "steps": [ { "title": "Four" }, { "title": "Five" } ] } ] }
      ],
      "feasibility": { "confidence": "high", "rationale": "Made up." }
    }
    """.utf8)

    /// An older plan: top-level steps.
    static let flatPlan = Data("""
    { "task_summary": "Count made-up colonies", "steps": [ { "title": "a" }, { "title": "b" }, { "title": "c" } ] }
    """.utf8)

    /// A plan whose step titles are not in alphabetical order, in 3 phases,
    /// so a test can tell the plan's order from a sorted one.
    static let unsortedPlan = Data("""
    {
      "task_summary": "Order made-up reagents",
      "phases": [
        { "delegations": [ { "steps": [ { "title": "Zeta" }, { "title": "Alpha" } ] } ] },
        { "delegations": [ { "steps": [ { "title": "Mu" } ] }, { "steps": [ { "title": "Beta" } ] } ] },
        { "delegations": [ { "steps": [ { "title": "Omega" } ] } ] }
      ]
    }
    """.utf8)
}

private func frame(_ data: Data) -> PlanFrame? { PlanFrame(json: data) }
private func plan(_ json: String) -> PlanDocument? { PlanDocument(json: Data(json.utf8)) }

private func written(_ status: Int, json: Bool = true, code: String? = nil, accepted: Bool = false,
                     noPlanAwaiting: Bool = false) -> APIWriteResult {
    APIWriteResult(status: status, isJSON: json, code: code, accepted: accepted, noPlanAwaiting: noPlanAwaiting)
}

// MARK: Reading the frame

struct PlanFrameTests {
    @Test func theContextFieldsAreRead() throws {
        let read = try #require(frame(Made.frame()))
        #expect(read.status == "awaiting_plan_approval")
        #expect(read.versionID == "ver-001")
        #expect(read.artifactID == "art-001")
        #expect(read.approval == .no)
    }

    @Test func theOutputFieldsAreTheFallback() throws {
        let read = try #require(frame(Made.frame(
            context: nil,
            output: #"{"plan_version_id": "ver-002", "plan_artifact_id": "art-002", "plan_approved": false, "plan_pending_since": 1}"#)))
        #expect(read.versionID == "ver-002")
        #expect(read.artifactID == "art-002")
        #expect(read.approval == .no)
    }

    @Test func theContextWinsOverTheOutput() throws {
        let read = try #require(frame(Made.frame(
            context: #"{"_plan_version_id": "ver-001"}"#, output: #"{"plan_version_id": "ver-002"}"#)))
        #expect(read.versionID == "ver-001")
    }

    @Test func contextDataGivenAsTextIsReadToo() throws {
        let read = try #require(frame(Made.frame(context: #""{\"_plan_version_id\": \"ver-003\"}""#)))
        #expect(read.versionID == "ver-003")
    }

    @Test func missingFieldsAreNoValues() throws {
        let read = try #require(frame(Made.frame(context: "{}", output: "{}")))
        #expect(read.versionID == nil)
        #expect(read.artifactID == nil)
        #expect(read.approval == .no)
    }

    @Test func aVersionIDOfTheWrongTypeIsNone() throws {
        let read = try #require(frame(Made.frame(context: #"{"_plan_version_id": 42}"#,
                                                 output: #"{"plan_version_id": "ver-002"}"#)))
        // Not passed over for the output's: the context said something odd.
        #expect(read.versionID == nil)
        #expect(PlanCheck.versionToRead(read) == nil)
    }

    @Test(arguments: [#""yes""#, "1", "0", #"{"a": true}"#, "[true]"])
    func anApprovalFlagThatIsNotABoolIsUnclear(_ flag: String) throws {
        let read = try #require(frame(Made.frame(context: #"{"_plan_version_id": "ver-001", "_plan_approved": \#(flag)}"#)))
        #expect(read.approval == .unclear)
    }

    @Test func approvedAnywhereIsApproved() throws {
        let inOutput = try #require(frame(Made.frame(
            context: #"{"_plan_version_id": "ver-001", "_plan_approved": false}"#, output: #"{"plan_approved": true}"#)))
        #expect(inOutput.approval == .yes)
        let inContext = try #require(frame(Made.frame(context: #"{"_plan_version_id": "ver-001", "_plan_approved": true}"#)))
        #expect(inContext.approval == .yes)
    }

    @Test(arguments: ["", "<html>Not JSON</html>", "[]", #"{"status": 3}"#, #"{"context_data": {}}"#])
    func aBodyWithoutAStringStatusIsNoFrame(_ body: String) {
        #expect(PlanFrame(json: Data(body.utf8)) == nil)
    }
}

// MARK: Reading the plan

struct PlanDocumentTests {
    @Test func thePhasesShapeCountsEveryStep() throws {
        let read = try #require(PlanDocument(json: Made.phasedPlan))
        #expect(read.summary == "Screen made-up buffers at two temperatures")
        #expect(read.steps == 5)
        #expect(read.confidence == "high")
    }

    @Test func theOlderShapeCountsTopLevelSteps() throws {
        let read = try #require(PlanDocument(json: Made.flatPlan))
        #expect(read.summary == "Count made-up colonies")
        #expect(read.steps == 3)
        #expect(read.confidence == nil)
    }

    @Test(arguments: [
        #"{"phases": []}"#,
        #"{"task_summary": 42}"#,
        #"{"task_summary": null}"#,
        #"{"task_summary": "   "}"#,
        #"{"task_summary": ["Made up"]}"#,
    ])
    func aMissingOrOddSummaryIsNone(_ json: String) throws {
        let read = try #require(plan(json))
        #expect(read.summary == nil)
    }

    @Test func oddStepsAndConfidenceAreLeftOutButTheSummaryStays() throws {
        let read = try #require(plan(#"{"task_summary": "Made up", "phases": {"a": 1}, "feasibility": {"confidence": 0.9}}"#))
        #expect(read.summary == "Made up")
        #expect(read.steps == nil)
        #expect(read.confidence == nil)
    }

    @Test func stepsThatAreNotObjectsStillCount() throws {
        let read = try #require(plan(#"{"task_summary": "Made up", "phases": [{"delegations": [{"steps": ["a", 2, null]}]}]}"#))
        #expect(read.steps == 3)
    }

    @Test func aConfidenceSentenceIsLeftOut() throws {
        let long = plan(#"{"task_summary": "Made up", "feasibility": {"confidence": "Fairly sure, given the made-up controls"}}"#)
        #expect(long?.confidence == nil)
        let worded = plan(#"{"task_summary": "Made up", "feasibility": {"confidence": "High confidence"}}"#)
        #expect(worded?.confidence == "high")
    }

    @Test(arguments: ["", "<html>Not JSON</html>", "[]", #""text""#])
    func aBodyThatIsNotAnObjectIsNoPlan(_ body: String) {
        #expect(PlanDocument(json: Data(body.utf8)) == nil)
    }
}

// MARK: Reading the steps' titles

struct PlanStepTitleTests {
    @Test func thePhasesShapeGivesTitlesInPlanOrder() throws {
        let read = try #require(PlanDocument(json: Made.phasedPlan))
        #expect(read.stepTitles == ["One", "Two", "Three", "Four", "Five"])
        #expect(read.stepTitles.count == read.steps)
    }

    @Test func theOlderShapeGivesTopLevelTitles() throws {
        let read = try #require(PlanDocument(json: Made.flatPlan))
        #expect(read.stepTitles == ["a", "b", "c"])
    }

    @Test func theOrderIsThePlansNotASortedOne() throws {
        let read = try #require(PlanDocument(json: Made.unsortedPlan))
        #expect(read.stepTitles == ["Zeta", "Alpha", "Mu", "Beta", "Omega"])
        #expect(read.steps == 5)
    }

    @Test func aStepsDescriptionIsNotRead() throws {
        // `phasedPlan`'s first step has one; only titles are kept anywhere.
        let read = try #require(PlanDocument(json: Made.phasedPlan))
        #expect(!read.stepTitles.contains("x"))
        let described = plan(#"{"task_summary": "Made up", "steps": [{"description": "Only a made-up description"}]}"#)
        #expect(described?.steps == 1)
        #expect(described?.stepTitles == [])
    }

    @Test func aPlanWithoutTitlesStillHasItsCount() throws {
        let read = try #require(plan(#"{"task_summary": "Made up", "steps": [{}, {}, {}]}"#))
        #expect(read.steps == 3)
        #expect(read.stepTitles == [])
    }

    @Test(arguments: [
        #"{"task_summary": "Made up"}"#,
        #"{"task_summary": "Made up", "steps": []}"#,
        #"{"task_summary": "Made up", "phases": []}"#,
        #"{"task_summary": "Made up", "phases": {"a": 1}}"#,
        #"{"task_summary": "Made up", "steps": "One, Two"}"#,
        #"{"task_summary": "Made up", "steps": {"title": "One"}}"#,
        #"{"task_summary": "Made up", "phases": [{"delegations": {"steps": [{"title": "One"}]}}]}"#,
        #"{"task_summary": "Made up", "phases": [{"delegations": [{"steps": {"title": "One"}}]}]}"#,
        #"{"task_summary": "Made up", "phases": ["One", 2, null]}"#,
    ])
    func aShapeThatDoesNotMatchHasNoTitles(_ json: String) throws {
        let read = try #require(plan(json))
        #expect(read.stepTitles == [])
    }

    @Test func titlesOfTheWrongTypeOrEmptyAreLeftOutButTheStepsCount() throws {
        let read = try #require(plan("""
        {"task_summary": "Made up", "steps": [
            {"title": 7}, {"title": null}, {"title": ["a"]}, {"title": {"a": 1}}, {"title": true},
            {"title": ""}, {"title": "   \\n\\t "}, {"title": "Kept"}, "Bare text", 3, null, []
        ]}
        """))
        #expect(read.steps == 12)
        #expect(read.stepTitles == ["Kept"])
    }

    @Test func aTitleIsOneTrimmedLine() throws {
        let read = try #require(plan(#"{"task_summary": "Made up", "steps": [{"title": "  Mix   the\nbuffers\t\r\nwell  "}]}"#))
        #expect(read.stepTitles == ["Mix the buffers well"])
    }

    @Test func aVeryLongTitleIsCutAtTheLimit() throws {
        let long = String(repeating: "a", count: PlanDocument.titleLimit + 50)
        let read = try #require(plan(#"{"task_summary": "Made up", "steps": [{"title": "\#(long)"}]}"#))
        #expect(read.stepTitles == [String(repeating: "a", count: PlanDocument.titleLimit)])
    }

    @Test func titlesComeFromTheShapeThatIsCounted() throws {
        // Both shapes at once: the phases count, so only their titles do.
        let both = try #require(plan("""
        {"task_summary": "Made up",
         "phases": [{"delegations": [{"steps": [{"title": "Phased"}]}]}],
         "steps": [{"title": "Flat one"}, {"title": "Flat two"}]}
        """))
        #expect(both.steps == 1)
        #expect(both.stepTitles == ["Phased"])
        // Phases with no steps in them: the top-level steps are the plan's.
        let empty = try #require(plan("""
        {"task_summary": "Made up",
         "phases": [{"delegations": [{"steps": []}]}],
         "steps": [{"title": "Flat one"}, {"title": "Flat two"}]}
        """))
        #expect(empty.steps == 2)
        #expect(empty.stepTitles == ["Flat one", "Flat two"])
    }

    @Test func aPlanWithoutTitlesIsStillOfferedAndShowsNoList() throws {
        let untitled = PlanDocument(json: Data(#"{"task_summary": "Made up", "steps": [{}, {}]}"#.utf8))
        let preview = try #require(PlanCheck.preview(frame: frame(Made.frame()), plan: untitled))
        #expect(preview.detail == "2 steps")
        #expect(preview.stepTitles == [])
        #expect(preview.stepList == nil)
    }

    @Test func thePreviewCarriesTheTitlesAndTheirList() throws {
        let preview = try #require(PlanCheck.preview(frame: frame(Made.frame()), plan: PlanDocument(json: Made.unsortedPlan)))
        #expect(preview.stepTitles == ["Zeta", "Alpha", "Mu", "Beta", "Omega"])
        #expect(preview.stepList == PlanStepList(["Zeta", "Alpha", "Mu", "Beta", "Omega"]))
    }
}

// MARK: How many titles the card lists

struct PlanStepListTests {
    private func titles(_ count: Int) -> [String] { (0..<count).map { "Step \($0 + 1)" } }

    @Test func theCapIsEight() {
        #expect(PlanStepList.limit == 8)
    }

    @Test(arguments: [(0, 0, 0), (1, 1, 0), (7, 7, 0), (8, 8, 0), (9, 8, 1), (10, 8, 2), (100, 8, 92)])
    func aLongPlanIsCutAtTheCap(_ count: Int, _ shown: Int, _ more: Int) {
        let list = PlanStepList(titles(count))
        #expect(list.shown == Array(titles(count).prefix(8)))
        #expect(list.shown.count == shown)
        #expect(list.more == more)
        #expect(list.shown.count + list.more == count)
    }

    @Test func theFirstTitlesAreTheOnesShownInOrder() {
        let list = PlanStepList(titles(10))
        #expect(list.shown.first == "Step 1")
        #expect(list.shown.last == "Step 8")
    }

    @Test func theMoreLineNamesHowManyAreLeftOut() {
        #expect(PlanStepList(titles(10)).moreLine == "and 2 more…")
        #expect(PlanStepList(titles(9)).moreLine == "and 1 more…")
        #expect(PlanStepList(titles(8)).moreLine == nil)
        #expect(PlanStepList(titles(3)).moreLine == nil)
        #expect(PlanStepList([]).moreLine == nil)
    }

    @Test func theLimitCanBeAskedFor() {
        let list = PlanStepList(titles(5), limit: 2)
        #expect(list.shown == ["Step 1", "Step 2"])
        #expect(list.more == 3)
        #expect(PlanStepList(titles(5), limit: 0).shown == [])
        #expect(PlanStepList(titles(5), limit: 0).more == 5)
        // A limit below zero is no limit to cut at: nothing is shown.
        #expect(PlanStepList(titles(5), limit: -3).shown == [])
        #expect(PlanStepList(titles(5), limit: -3).more == 5)
        // A limit above the count shows all.
        #expect(PlanStepList(titles(5), limit: 50).shown.count == 5)
    }
}

// MARK: Offering Approve

struct PlanOfferTests {
    private let phased = PlanDocument(json: Made.phasedPlan)

    @Test func approveIsOfferedWhenEverythingChecksOut() throws {
        let preview = try #require(PlanCheck.preview(frame: frame(Made.frame()), plan: phased))
        #expect(preview.summary == "Screen made-up buffers at two temperatures")
        #expect(preview.versionID == "ver-001")
        #expect(preview.artifactID == "art-001")
        #expect(preview.detail == "5 steps · feasibility: high")
        #expect(preview.stepTitles == ["One", "Two", "Three", "Four", "Five"])
    }

    @Test func aSubAgentWaitingLeavesTheRootProcessing() {
        // The session waits because a sub-agent does: the root isn't the one
        // with a plan to approve, so only Open.
        #expect(PlanCheck.versionToRead(frame(Made.frame(status: "processing"))) == nil)
        #expect(PlanCheck.preview(frame: frame(Made.frame(status: "processing")), plan: phased) == nil)
    }

    @Test(arguments: ["awaiting_user_response", "completed", "failed", "AWAITING_PLAN_APPROVAL", ""])
    func anyOtherStatusOffersNothing(_ status: String) {
        #expect(PlanCheck.preview(frame: frame(Made.frame(status: status)), plan: phased) == nil)
    }

    @Test func anApprovedOrUnclearPlanOffersNothing() {
        let approved = frame(Made.frame(context: #"{"_plan_version_id": "ver-001", "_plan_approved": true}"#))
        #expect(PlanCheck.preview(frame: approved, plan: phased) == nil)
        let unclear = frame(Made.frame(context: #"{"_plan_version_id": "ver-001", "_plan_approved": "no"}"#))
        #expect(PlanCheck.preview(frame: unclear, plan: phased) == nil)
    }

    @Test func noVersionOffersNothing() {
        #expect(PlanCheck.preview(frame: frame(Made.frame(context: "{}")), plan: phased) == nil)
    }

    @Test(arguments: ["../usage", "ver/001", "ver 001", "ver-001?x=1", "", String(repeating: "a", count: 129)])
    func aVersionIDUnfitForAPathOffersNothing(_ id: String) {
        let read = PlanFrame(status: "awaiting_plan_approval", versionID: id, artifactID: nil, approval: .no)
        #expect(PlanCheck.versionToRead(read) == nil)
        #expect(PlanCheck.versionPath(id) == nil)
    }

    @Test func noSummaryOffersNothing() {
        #expect(PlanCheck.preview(frame: frame(Made.frame()), plan: plan(#"{"phases": []}"#)) == nil)
        #expect(PlanCheck.preview(frame: frame(Made.frame()), plan: plan(#"{"task_summary": 7}"#)) == nil)
        #expect(PlanCheck.preview(frame: frame(Made.frame()), plan: nil) == nil)
        #expect(PlanCheck.preview(frame: nil, plan: phased) == nil)
    }

    @Test func theOlderShapeIsOfferedToo() throws {
        let preview = try #require(PlanCheck.preview(frame: frame(Made.frame()), plan: PlanDocument(json: Made.flatPlan)))
        #expect(preview.detail == "3 steps")
    }

    @Test func theStepsLineSaysWhatIsKnown() {
        func line(_ steps: Int?, _ confidence: String?) -> String? {
            PlanPreview(summary: "Made up", steps: steps, confidence: confidence, versionID: "v", artifactID: nil).detail
        }
        #expect(line(5, "high") == "5 steps · feasibility: high")
        #expect(line(1, "medium") == "1 step · feasibility: medium")
        #expect(line(6, nil) == "6 steps")
        #expect(line(nil, "low") == "feasibility: low")
        #expect(line(0, nil) == nil)
        #expect(line(nil, nil) == nil)
    }
}

// MARK: Checking again before approving

struct PlanPressTests {
    private let shown = PlanPreview(summary: "Made up", steps: 5, confidence: "high", versionID: "ver-001", artifactID: "art-001")

    @Test func theSamePlanStillWaiting() {
        #expect(PlanCheck.isSamePlan(frame(Made.frame()), as: shown))
    }

    @Test func aNewVersionIsAChange() {
        let newer = frame(Made.frame(context: #"{"_plan_version_id": "ver-002", "_plan_artifact_id": "art-001"}"#))
        #expect(!PlanCheck.isSamePlan(newer, as: shown))
    }

    @Test func aNewArtifactIsAChange() {
        let other = frame(Made.frame(context: #"{"_plan_version_id": "ver-001", "_plan_artifact_id": "art-009"}"#))
        #expect(!PlanCheck.isSamePlan(other, as: shown))
    }

    @Test func noLongerWaitingOrApprovedIsAChange() {
        #expect(!PlanCheck.isSamePlan(frame(Made.frame(status: "processing")), as: shown))
        let approved = frame(Made.frame(context: #"{"_plan_version_id": "ver-001", "_plan_approved": true}"#))
        #expect(!PlanCheck.isSamePlan(approved, as: shown))
        #expect(!PlanCheck.isSamePlan(nil, as: shown))
        #expect(!PlanCheck.isSamePlan(frame(Made.frame(context: "{}")), as: shown))
    }
}

// MARK: What the daemon's answer means

struct PlanOutcomeTests {
    @Test func acceptedIsApproved() {
        #expect(PlanCheck.outcome(written(200, accepted: true)) == .approved)
    }

    @Test func alreadyApprovedCountsAsApproved() {
        #expect(PlanCheck.outcome(written(400, code: "plan_already_approved")) == .approved)
    }

    @Test func stillProcessingIsBusy() {
        #expect(PlanCheck.outcome(written(400, code: "plan_frame_processing")) == .busy)
    }

    @Test func noPlanAwaitingIsAChange() {
        #expect(PlanCheck.outcome(written(400, noPlanAwaiting: true)) == .changed)
        #expect(PlanCheck.outcome(written(400, json: false, noPlanAwaiting: true)) == .changed)
    }

    @Test(arguments: [
        written(200),                                         // JSON, but not "accepted"
        written(200, json: false),                            // not JSON
        written(201, accepted: true),
        written(204, json: false),
        written(400),                                         // no code, no sentence
        written(400, code: "invalid_body"),
        written(400, json: false),
        written(401, code: "unauthorized"),
        written(401, json: false),
        written(403, code: "csrf_stale"),                     // still stale after the one retry
        written(403, code: "origin_mismatch"),
        written(403, json: false),
        written(404, json: false),
        written(404, code: "not_found"),
        written(405, json: false),
        written(500, json: false),
    ])
    func anythingElseFails(_ result: APIWriteResult) {
        #expect(PlanCheck.outcome(result) == .failed)
    }

    @Test func eachProblemHasASentenceAndApprovedHasNone() {
        #expect(PlanOutcome.approved.message == nil)
        #expect(PlanOutcome.failed.message == "Couldn't approve here")
        #expect(PlanOutcome.busy.message != nil)
        #expect(PlanOutcome.changed.message != nil)
    }
}

// MARK: The one write path

struct PlanPathTests {
    @Test func theApprovePathIsAllowed() throws {
        let path = try #require(PlanCheck.approvePath(Made.root))
        #expect(path == "/frames/\(Made.root)/approve-plan")
        #expect(PlanCheck.isApprovePath(path))
    }

    @Test(arguments: [
        "/frames/\(Made.root)/discard-plan",
        "/frames/\(Made.root)/resolve-input",
        "/frames/\(Made.root)/approve-plan/",
        "/frames/\(Made.root)/approve-plan?x=1",
        "/frames/\(Made.root.uppercased())/approve-plan",
        "/frames/\(Made.root.dropLast())/approve-plan",
        "/frames/\(Made.root)0/approve-plan",
        "/frames/\(Made.root)/../approve-plan",
        "/frames/../../usage/approve-plan",
        "/api/frames/\(Made.root)/approve-plan",
        "frames/\(Made.root)/approve-plan",
        "/request",
        "",
    ])
    func everyOtherPathIsRefused(_ path: String) {
        #expect(!PlanCheck.isApprovePath(path))
    }

    @Test func onlyFullFrameIDsAreUsed() {
        #expect(PlanCheck.isFrameID(Made.root))
        #expect(!PlanCheck.isFrameID(String(Made.root.prefix(8))))
        #expect(!PlanCheck.isFrameID("demo-1"))
        #expect(!PlanCheck.isFrameID(Made.root.uppercased()))
        #expect(PlanCheck.framePath("0b7c2f4e") == nil)
        #expect(PlanCheck.approvePath("demo-1") == nil)
        #expect(PlanCheck.framePath(Made.root) == "/frames/\(Made.root)?shallow=true")
        #expect(PlanCheck.versionPath("ver-001") == "/artifacts/versions/ver-001")
    }
}

// MARK: The approver, against a fake daemon

/// Stands in for the page's API: answers with made-up JSON and records every
/// path asked for. Nothing reaches a real daemon.
@MainActor
private final class FakeDaemon {
    var frame = Made.frame()
    var plan = Made.phasedPlan
    var answer: APIWriteResult? = written(200, accepted: true)
    var enabled = true
    private(set) var reads: [String] = []
    private(set) var posts: [String] = []

    func dependencies() -> PlanApprover.Dependencies {
        PlanApprover.Dependencies(
            isEnabled: { [unowned self] in self.enabled },
            isReady: { true },
            get: { [unowned self] path in
                self.reads.append(path)
                if path.hasPrefix("/frames/") { return self.frame }
                if path.hasPrefix("/artifacts/versions/") { return self.plan }
                throw WebAPIError.notAllowed
            },
            post: { [unowned self] path in
                self.posts.append(path)
                guard let answer = self.answer else { throw WebAPIError.badResponse }
                return answer
            },
            approvedPause: .milliseconds(20))
    }
}

@MainActor
struct PlanApproverTests {
    private let daemon = FakeDaemon()
    private let model = LabModel()

    private func waiting(_ reason: WaitingReason = .plan, id: String = Made.root) -> SessionStatus {
        Fixture.session(id, .needsInput, reason: reason, title: "Made-up plan session")
    }

    /// A model with the plan card on top, and an approver that has read it.
    private func ready() async throws -> PlanApprover {
        model.ingest(Fixture.snapshot(Fixture.session(Made.root, .running)))
        model.ingest(Fixture.snapshot(waiting()))
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.sync()
        #expect(approver.state(for: Made.root) == .loading)
        await approver.settled()
        return approver
    }

    @Test func thePlanIsReadOnceAndApproveOffered() async throws {
        let approver = try await ready()
        guard case .ready(let preview)? = approver.state(for: Made.root) else {
            Issue.record("Approve was not offered")
            return
        }
        #expect(preview.detail == "5 steps · feasibility: high")
        #expect(preview.stepTitles == ["One", "Two", "Three", "Four", "Five"])
        #expect(daemon.reads == ["/frames/\(Made.root)?shallow=true", "/artifacts/versions/ver-001"])
        approver.sync()
        await approver.settled()
        #expect(daemon.reads.count == 2)
    }

    @Test func aSubAgentWaitingReadsNoPlanAndOffersOnlyOpen() async throws {
        daemon.frame = Made.frame(status: "processing")
        let approver = try await ready()
        #expect(approver.state(for: Made.root) == .unavailable)
        #expect(daemon.reads == ["/frames/\(Made.root)?shallow=true"])
    }

    @Test func withTheSettingOffNothingIsRead() {
        daemon.enabled = false
        model.ingest(Fixture.snapshot(waiting()))
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.sync()
        #expect(approver.states.isEmpty)
        #expect(daemon.reads.isEmpty)
    }

    @Test func otherWaitingKindsReadNothing() {
        model.ingest(Fixture.snapshot(waiting(.question)))
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.sync()
        #expect(approver.states.isEmpty)
        #expect(daemon.reads.isEmpty)
    }

    @Test func aShortSessionIDIsNeverSent() async {
        model.ingest(Fixture.snapshot(waiting(id: "0b7c2f4e")))
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.sync()
        await approver.settled()
        #expect(approver.state(for: "0b7c2f4e") == .unavailable)
        #expect(daemon.reads.isEmpty)
    }

    @Test func approvingPostsOnceThenTheCardGoes() async throws {
        let approver = try await ready()
        approver.approve(Made.root)
        approver.approve(Made.root)
        #expect(approver.state(for: Made.root).map { if case .approving = $0 { true } else { false } } == true)
        await approver.settled()
        #expect(daemon.posts == ["/frames/\(Made.root)/approve-plan"])
        // The frame was read again just before the post.
        #expect(daemon.reads.filter { $0.hasPrefix("/frames/") }.count == 2)
        #expect(model.cards.isEmpty)
        #expect(approver.states.isEmpty)
        approver.approve(Made.root)
        await approver.settled()
        #expect(daemon.posts.count == 1)
    }

    @Test func aChangedPlanIsNeverPosted() async throws {
        let approver = try await ready()
        daemon.frame = Made.frame(context: #"{"_plan_version_id": "ver-002", "_plan_artifact_id": "art-001"}"#)
        approver.approve(Made.root)
        await approver.settled()
        #expect(daemon.posts.isEmpty)
        guard case .problem(let message, _)? = approver.state(for: Made.root) else {
            Issue.record("No problem shown")
            return
        }
        #expect(message == PlanOutcome.changed.message)
        // Open stays: the card is still there.
        #expect(model.cards.map(\.id) == ["needs-\(Made.root)"])
    }

    @Test func aPlanApprovedElsewhereMeanwhileIsNeverPosted() async throws {
        let approver = try await ready()
        daemon.frame = Made.frame(status: "processing")
        approver.approve(Made.root)
        await approver.settled()
        #expect(daemon.posts.isEmpty)
        #expect(approver.state(for: Made.root).map { if case .problem = $0 { true } else { false } } == true)
    }

    @Test(arguments: [
        (written(400, code: "plan_frame_processing"), PlanOutcome.busy),
        (written(400, noPlanAwaiting: true), PlanOutcome.changed),
        (written(404, json: false), PlanOutcome.failed),
        (written(401, json: false), PlanOutcome.failed),
    ])
    func aRefusalKeepsTheCardWithOpen(_ answer: APIWriteResult, _ outcome: PlanOutcome) async throws {
        daemon.answer = answer
        let approver = try await ready()
        approver.approve(Made.root)
        await approver.settled()
        #expect(daemon.posts.count == 1)
        guard case .problem(let message, _)? = approver.state(for: Made.root) else {
            Issue.record("No problem shown")
            return
        }
        #expect(message == outcome.message)
        #expect(model.cards.map(\.id) == ["needs-\(Made.root)"])
        #expect(!model.holdsPlanCard(Made.root))
    }

    @Test func aPostThatThrowsFails() async throws {
        daemon.answer = nil
        let approver = try await ready()
        approver.approve(Made.root)
        await approver.settled()
        guard case .problem(let message, _)? = approver.state(for: Made.root) else {
            Issue.record("No problem shown")
            return
        }
        #expect(message == "Couldn't approve here")
    }

    @Test func theCardGoingDropsItsPlan() async throws {
        let approver = try await ready()
        model.ingest(Fixture.snapshot(Fixture.session(Made.root, .running)))
        #expect(model.cards.isEmpty)
        approver.sync()
        #expect(approver.states.isEmpty)
    }

    @Test func aPlanCardThatAsksSomethingElseDropsItsPlan() async throws {
        let approver = try await ready()
        model.ingest(Fixture.snapshot(waiting(.question)))
        approver.sync()
        #expect(approver.states.isEmpty)
    }

    @Test func turningTheSettingOffDropsThePlan() async throws {
        let approver = try await ready()
        daemon.enabled = false
        approver.sync()
        #expect(approver.states.isEmpty)
        #expect(model.cards.map(\.id) == ["needs-\(Made.root)"])
    }

    @Test func theStepsStartClosedAndOpenForThatCardAlone() async throws {
        let approver = try await ready()
        #expect(!approver.isShowingSteps(Made.root))
        approver.toggleSteps(Made.root)
        #expect(approver.isShowingSteps(Made.root))
        // Another session's card is not opened by it.
        #expect(!approver.isShowingSteps(Made.other))
        approver.toggleSteps(Made.root)
        #expect(!approver.isShowingSteps(Made.root))
    }

    @Test func aCardWithNoPlanStateCannotBeOpened() {
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.toggleSteps(Made.root)
        #expect(!approver.isShowingSteps(Made.root))
        #expect(approver.stepsOpen.isEmpty)
    }

    @Test func theCardGoingClosesItsSteps() async throws {
        let approver = try await ready()
        approver.toggleSteps(Made.root)
        model.ingest(Fixture.snapshot(Fixture.session(Made.root, .running)))
        approver.sync()
        #expect(approver.states.isEmpty)
        #expect(approver.stepsOpen.isEmpty)
        // Back again, it reads afresh and starts closed.
        model.ingest(Fixture.snapshot(waiting()))
        approver.sync()
        await approver.settled()
        #expect(approver.state(for: Made.root) != nil)
        #expect(!approver.isShowingSteps(Made.root))
    }

    @Test func turningTheSettingOffClosesTheSteps() async throws {
        let approver = try await ready()
        approver.toggleSteps(Made.root)
        daemon.enabled = false
        approver.sync()
        #expect(approver.stepsOpen.isEmpty)
    }

    @Test func approvingKeepsTheStepsOpenThenClosesThemWhenTheCardGoes() async throws {
        let approver = try await ready()
        approver.toggleSteps(Made.root)
        approver.approve(Made.root)
        #expect(approver.isShowingSteps(Made.root))
        await approver.settled()
        #expect(approver.states.isEmpty)
        #expect(approver.stepsOpen.isEmpty)
    }

    @Test func theDemoPlanShowsItsMoreLineAndOpens() {
        model.showDemo(working: [], cards: [.needsInput(Fixture.session("demo-1", .needsInput, reason: .plan))])
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        let titles = (1...10).map { "Made-up step \($0)" }
        let preview = PlanPreview(summary: "Made up", steps: 10, confidence: "high", stepTitles: titles,
                                  versionID: "demo", artifactID: nil)
        approver.showDemo(sessionID: "demo-1", preview: preview)
        #expect(preview.stepList?.moreLine == "and 2 more…")
        approver.toggleSteps("demo-1")
        #expect(approver.isShowingSteps("demo-1"))
        #expect(daemon.reads.isEmpty)
    }

    @Test func theDemoApprovesWithNothingSent() async {
        model.showDemo(working: [], cards: [.needsInput(Fixture.session("demo-1", .needsInput, reason: .plan))])
        let approver = PlanApprover(model: model, dependencies: daemon.dependencies())
        approver.showDemo(sessionID: "demo-1", preview: PlanPreview(
            summary: "Screen 24 buffer conditions", steps: 6, confidence: "high", versionID: "demo", artifactID: nil))
        approver.approve("demo-1")
        await approver.settled()
        #expect(approver.state(for: "demo-1").map { if case .approved = $0 { true } else { false } } == true)
        #expect(daemon.reads.isEmpty)
        #expect(daemon.posts.isEmpty)
    }
}

// MARK: The card held through an approval

@MainActor
struct PlanHoldTests {
    private let model: LabModel = {
        let model = LabModel()
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        return model
    }()

    @Test func aHeldCardStaysOnceTheSessionRunsThenGoesWhenApproved() {
        model.holdPlanCard("a")
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        #expect(model.cards.map(\.id) == ["needs-a"])
        model.releasePlanCard("a", approved: true)
        #expect(model.cards.isEmpty)
        #expect(!model.holdsPlanCard("a"))
    }

    @Test func releasedUnapprovedItStaysOnlyWhileTheSessionWaits() {
        model.holdPlanCard("a")
        model.releasePlanCard("a", approved: false)
        #expect(model.cards.map(\.id) == ["needs-a"])

        model.holdPlanCard("a")
        model.ingest(Fixture.snapshot(Fixture.session("a", .running)))
        model.releasePlanCard("a", approved: false)
        #expect(model.cards.isEmpty)
    }

    @Test func readingTheSameWaitingPlanAgainKeepsTheHold() {
        model.holdPlanCard("a")
        // A later read of the same wait (a fresh write time, the same reason)
        // is no new request: the approval under way keeps its card.
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan)))
        #expect(model.holdsPlanCard("a"))
        #expect(model.cards.map(\.id) == ["needs-a"])
    }

    @Test func aNewRequestLetsTheHoldGo() {
        model.holdPlanCard("a")
        model.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(!model.holdsPlanCard("a"))
        // The question's card is not taken by the approval's end.
        model.releasePlanCard("a", approved: true)
        #expect(model.cards.first?.session?.waitingReason == .question)
    }

    @Test func dismissingTheCardLetsTheHoldGo() {
        model.holdPlanCard("a")
        model.dismiss(model.cards[0])
        #expect(!model.holdsPlanCard("a"))
    }

    @Test func onlyACardInTheQueueIsHeld() {
        model.holdPlanCard("b")
        #expect(!model.holdsPlanCard("b"))
    }
}
