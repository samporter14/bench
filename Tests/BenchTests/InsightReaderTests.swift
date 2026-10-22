// InsightReaderTests.swift — step progress and the reviewer's counts: the
// projections are the very JavaScript the page runs, in JavaScriptCore, on
// made-up trees and answers; then Swift's checks of what comes back, the two
// in-page bodies against a fake fetch, and the allowlist. Nothing reaches a
// daemon. Every SECRET is something that must never leave the page: a step's
// description, a status's note and time, a plan's summary, a finding's text.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let version = "3e0f5c71-4d5e-4f60-8122-d3e4f5a6b7c8"
private let otherVersion = "4f1a6d82-5e6f-4a71-8233-e4f5a6b7c8d9"
private let helperA = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
private let helperB = "2d9e4b60-3c4d-4e5f-8011-c2d3e4f5a6b7"

// MARK: Made-up trees

private func json(_ object: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])) ?? Data(), as: UTF8.self)
}

/// A plan file as the root's `_plan_json` holds it: one phase per entry, one
/// delegation per inner list, one step per title. Descriptions are secret.
private func plan(_ phases: [[[String]]]) -> [String: Any] {
    [
        "version": 1, "task_summary": "SECRET-SUMMARY", "feasibility": ["confidence": "high", "rationale": "SECRET-RATIONALE"],
        "phases": phases.enumerated().map { number, delegations in
            [
                "id": "phase-\(number)", "name": "SECRET-PHASE",
                "delegations": delegations.map { titles in
                    ["agent": "SECRET-AGENT", "name": "Track",
                     "steps": titles.map { ["title": $0, "description": "SECRET-DESCRIPTION-OF-\($0)"] }]
                },
            ] as [String: Any]
        },
    ]
}

/// The steps "Step 1" to "Step n", in one delegation of one phase.
private func steps(_ count: Int) -> [[[String]]] {
    [[(1...count).map { "Step \($0)" }]]
}

private func entry(_ word: String) -> [String: Any] {
    ["status": word, "updated_at": "SECRET-TIME", "notes": "SECRET-NOTE"]
}

private func tree(status: String = "processing", approved: Any = true, version versionID: Any? = version,
                  plan planFile: Any? = plan(steps(6)), statuses: [String: String] = [:], children: [[String: Any]] = [],
                  output: [String: Any]? = nil, context extra: [String: Any] = [:]) -> [String: Any] {
    var context: [String: Any] = [
        "_plan_approved": approved, "_step_statuses": statuses.mapValues(entry),
        "_messages": "SECRET-MESSAGES", "_system": "SECRET-SYSTEM-PROMPT",
    ]
    if let versionID { context["_plan_version_id"] = versionID }
    if let planFile { context["_plan_json"] = planFile }
    for (key, value) in extra { context[key] = value }
    var frame: [String: Any] = ["id": root, "status": status, "name": "SECRET-NAME", "context_data": context, "children": children]
    if let output { frame["output_data"] = output }
    return frame
}

private func helper(_ id: String = helperA, parent: String = root, claims: [(version: String, titles: [String])] = [],
                    statuses: [String: String] = [:], children: [[String: Any]] = []) -> [String: Any] {
    [
        "id": id, "parent_frame_id": parent, "status": "processing", "children": children,
        "context_data": [
            "_plan_claims": claims.map { claim in
                ["phase_id": "phase-0", "delegation_index": 0, "plan_version_id": claim.version,
                 "steps": claim.titles.map { ["title": $0, "description": "SECRET-CLAIM-DESCRIPTION"] }] as [String: Any]
            },
            "_step_statuses": statuses.mapValues(entry),
        ] as [String: Any],
    ]
}

private func answer(_ treeJSON: String, rootID: String = root) -> (text: String?, object: [String: Any]?) {
    let script = PageScript(InsightReaderScript.progressProjection)
    script.set("__tree", treeJSON)
    let text = script.evaluate("JSON.stringify(benchProjectProgress(JSON.parse(__tree), \"\(rootID)\"))")
    #expect(script.exception == nil)
    let object = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    return (text, object)
}

private func project(_ frame: [String: Any], rootID: String = root) -> (text: String?, object: [String: Any]?) {
    answer(json(frame), rootID: rootID)
}

/// `(step, total, title)` of a progress answer, else nil.
private func shown(_ result: (text: String?, object: [String: Any]?)) -> (step: Int, total: Int, title: String?)? {
    guard let object = result.object, object["outcome"] as? String == "progress",
          let step = object["step"] as? Int, let total = object["total"] as? Int else { return nil }
    return (step, total, object["title"] as? String)
}

private func why(_ result: (text: String?, object: [String: Any]?)) -> String? {
    guard result.object?["outcome"] as? String == "idle" else { return nil }
    return result.object?["why"] as? String
}

// MARK: Plan progress

struct PlanProgressProjectionTests {
    @Test func theStepAfterTheDoneOnesAndTheTitleOfTheOneInProgress() throws {
        let result = project(tree(statuses: ["Step 1": "completed", "Step 2": "completed", "Step 3": "skipped", "Step 4": "in_progress"]))
        let got = try #require(shown(result))
        #expect(got.step == 4 && got.total == 6 && got.title == "Step 4")
        // Nothing of the tree but the counts and the one title comes back.
        let text = try #require(result.text)
        #expect(!text.contains("SECRET"))
        #expect(!text.contains(root) && !text.contains(version))
        #expect(Set(Array(try #require(result.object).keys)) == ["outcome", "step", "total", "title", "processing", "children", "reported", "unknown"])
        #expect(result.object?["processing"] as? Bool == true)
        #expect(result.object?["children"] as? Int == 0)
        #expect(result.object?["reported"] as? Int == 4)
    }

    @Test func skippedIsDoneAndBlockedIsNot() throws {
        let skipped = try #require(shown(project(tree(statuses: ["Step 1": "skipped", "Step 2": "completed", "Step 3": "in_progress"]))))
        #expect(skipped.step == 3 && skipped.title == "Step 3")
        let blocked = try #require(shown(project(tree(statuses: ["Step 1": "completed", "Step 2": "blocked", "Step 3": "in_progress"]))))
        // One done; the blocked one doesn't count, and the one in progress isn't step 2.
        #expect(blocked.step == 2 && blocked.title == nil)
    }

    @Test func theNumberAloneWhenTheModelOnlyMarksWhatIsDone() throws {
        let got = try #require(shown(project(tree(statuses: ["Step 1": "completed", "Step 2": "completed"]))))
        #expect(got.step == 3 && got.total == 6 && got.title == nil)
    }

    @Test func nothingUntilAStepHasReportedAStatus() {
        #expect(why(project(tree())) == "no-statuses")
        #expect(why(project(tree(statuses: ["Step 1": "pending", "Step 2": "pending"]))) == "no-statuses")
        // A status for a title the plan doesn't have is no status of the plan's.
        #expect(why(project(tree(statuses: ["Somewhere else": "completed"]))) == "no-statuses")
        // The page would say "step 1": Capsid says nothing.
        #expect(shown(project(tree())) == nil)
    }

    @Test func nothingOnceEveryStepIsDone() {
        let all = Dictionary(uniqueKeysWithValues: (1...6).map { ("Step \($0)", $0 % 2 == 0 ? "skipped" : "completed") })
        #expect(why(project(tree(statuses: all))) == "complete")
        var almost = all
        almost["Step 6"] = "in_progress"
        let got = shown(project(tree(statuses: almost)))
        #expect(got?.step == 6 && got?.title == "Step 6")
    }

    @Test func twoStepsInProgressHaveNoTitle() throws {
        let got = try #require(shown(project(tree(statuses: ["Step 1": "completed", "Step 2": "in_progress", "Step 3": "in_progress"]))))
        #expect(got.step == 2 && got.title == nil)
    }

    @Test func aStepInProgressThatIsNotWhereTheNumberPointsHasNoTitle() throws {
        // Steps 1 and 2 are done, so the number is 3; the one in progress is step 5.
        let got = try #require(shown(project(tree(statuses: ["Step 1": "completed", "Step 2": "completed", "Step 5": "in_progress"]))))
        #expect(got.step == 3 && got.title == nil)
    }

    @Test func aTitleThatIsInThePlanTwiceIsNeverShown() throws {
        let repeated = plan([[["Load", "Fit", "Load", "Plot"]]])
        let got = try #require(shown(project(tree(plan: repeated, statuses: ["Load": "in_progress"]))))
        // One status entry serves both steps, as the page counts it; the title is ambiguous.
        #expect(got.step == 1 && got.total == 4 && got.title == nil)
        // The number still follows the page: a completed "Load" is one done, however many steps carry the name.
        let done = try #require(shown(project(tree(plan: repeated, statuses: ["Load": "completed", "Fit": "in_progress"]))))
        #expect(done.step == 2 && done.title == "Fit")
        // A unique title in the same plan is shown when it sits at the number.
        let unique = try #require(shown(project(tree(plan: plan([[["Load", "Fit", "Load"]]]), statuses: ["Load": "completed", "Fit": "in_progress"]))))
        #expect(unique.step == 2 && unique.title == "Fit")
    }

    @Test func aTitleIsOneShortLine() throws {
        let long = "Check\n   the \u{7}\tpublished   screens " + String(repeating: "é", count: 300)
        let got = try #require(shown(project(tree(plan: plan([[["Before", long]]]), statuses: ["Before": "completed", long: "in_progress"]))))
        let title = try #require(got.title)
        #expect(title.hasPrefix("Check the published screens ééé"))
        #expect(!title.contains("\n") && !title.contains("\t") && !title.contains("\u{7}"))
        #expect(title.unicodeScalars.count == 200)
        #expect(title.hasSuffix("…"))
        // A title of nothing but white space is no step title at all.
        let blank = try #require(shown(project(tree(plan: plan([[["Before", "  \n "]]]), statuses: ["Before": "completed"]))))
        #expect(blank.total == 2 && blank.title == nil)
    }

    @Test func aHelpersStatusesAreMergedForTheClaimsOfTheCurrentVersionOnly() throws {
        let file = plan([[["A1", "A2"], ["B1", "B2", "B3"]]])
        let tracks = [
            helper(helperA, claims: [(version, ["B1", "B2", "B3"])],
                   statuses: ["B1": "completed", "B2": "in_progress"]),
        ]
        let got = try #require(shown(project(tree(plan: file, statuses: ["A1": "completed"], children: tracks))))
        // Two done (A1 on the root, B1 on the helper): step 3, and B2 is step 4's title, not step 3's.
        #expect(got.step == 3 && got.total == 5 && got.title == nil)
        let text = try #require(project(tree(plan: file, statuses: ["A1": "completed"], children: tracks)).object)
        #expect(text["children"] as? Int == 1)
        #expect(text["reported"] as? Int == 3)
    }

    @Test func aHelpersStatusOverridesTheRootsAndTheTitleCanBeTheHelpers() throws {
        let file = plan([[["A1", "A2"], ["B1", "B2"]]])
        let tracks = [helper(claims: [(version, ["B1", "B2"])], statuses: ["B1": "completed", "B2": "in_progress"])]
        // A1 and A2 done on the root, B1 on the helper: step 4, and B2 is the 4th step.
        let got = try #require(shown(project(tree(plan: file, statuses: ["A1": "completed", "A2": "completed"], children: tracks))))
        #expect(got.step == 4 && got.total == 4 && got.title == "B2")
        // The helper's word wins over the root's for a title it claims.
        let over = try #require(shown(project(tree(plan: file, statuses: ["B1": "in_progress"],
                                                   children: [helper(claims: [(version, ["B1"])], statuses: ["B1": "completed"])]))))
        #expect(over.step == 2 && over.title == nil)
    }

    @Test func aClaimOfAnotherVersionAStatusNobodyClaimedAndAHelpersHelperAreIgnored() throws {
        let file = plan([[["A1", "A2"], ["B1", "B2"]]])
        let stale = helper(helperA, claims: [(otherVersion, ["B1", "B2"])], statuses: ["B1": "completed", "B2": "completed"])
        let unclaimed = helper(helperB, claims: [(version, ["B1"])], statuses: ["B1": "completed", "B2": "completed", "A1": "completed"])
        let deep = helper("5a2b7e93-6f70-4b82-8344-f5a6b7c8d9e0", parent: helperB, claims: [(version, ["A2"])], statuses: ["A2": "completed"])
        let nested = helper(helperA, claims: [(otherVersion, ["B1"])], children: [deep])
        let got = try #require(shown(project(tree(plan: file, statuses: ["A1": "in_progress"], children: [stale, unclaimed, nested]))))
        // Only B1 counts (helper B claimed it for this version): one done, A1 in progress is step 1, not step 2.
        #expect(got.step == 2 && got.total == 4 && got.title == nil)
        // A helper that says it is under another frame is not the root's.
        let elsewhere = helper(helperA, parent: helperB, claims: [(version, ["B1"])], statuses: ["B1": "completed"])
        let none = project(tree(plan: file, children: [elsewhere]))
        #expect(why(none) == "no-statuses")
    }

    @Test func aClaimMayNameTitlesAsPlainStrings() throws {
        let file = plan([[["A1"], ["B1"]]])
        let claim: [String: Any] = ["plan_version_id": version, "steps": ["B1"]]
        let frame: [String: Any] = ["id": helperA, "parent_frame_id": root,
                                    "context_data": ["_plan_claims": [claim], "_step_statuses": ["B1": entry("completed")]]]
        let got = try #require(shown(project(tree(plan: file, children: [frame]))))
        #expect(got.step == 2 && got.total == 2)
    }

    @Test func onlyAnApprovedPlanIsFollowedAndOnlyOnTheContext() {
        let statuses = ["Step 1": "in_progress"]
        #expect(why(project(tree(approved: false, statuses: statuses))) == "not-approved")
        #expect(why(project(tree(approved: NSNull(), statuses: statuses))) == "not-approved")
        // Only the JSON true is an approval: not "true", not 1.
        #expect(why(project(tree(approved: "true", statuses: statuses))) == "not-approved")
        #expect(why(project(tree(approved: 1, statuses: statuses))) == "not-approved")
        // The output's flag is not the page's: it reads the context alone.
        var frame = tree(approved: false, statuses: statuses, output: ["plan_approved": true])
        #expect(why(project(frame)) == "not-approved")
        frame["context_data"] = NSNull()
        #expect(why(project(frame)) == "not-approved")
        #expect(shown(project(tree(statuses: statuses))) != nil)
    }

    @Test func theVersionIsTheContextsElseTheOutputsAndFitForAPath() {
        let statuses = ["Step 1": "in_progress"]
        #expect(shown(project(tree(version: nil, statuses: statuses, output: ["plan_version_id": version]))) != nil)
        #expect(why(project(tree(version: nil, statuses: statuses))) == "no-plan")
        #expect(why(project(tree(version: "../etc", statuses: statuses))) == "no-plan")
        #expect(why(project(tree(version: 7, statuses: statuses))) == "no-plan")
        // A version in the context is not passed over for the output's.
        #expect(why(project(tree(version: "bad/version", statuses: statuses, output: ["plan_version_id": version]))) == "no-plan")
    }

    @Test func aPlanNeedsPhasesAndSteps() {
        let statuses = ["Step 1": "in_progress"]
        // An older plan, flat: the page shows no progress for it either.
        #expect(why(project(tree(plan: ["steps": [["title": "Step 1", "description": "SECRET"]]], statuses: statuses))) == "no-plan")
        #expect(why(project(tree(plan: ["phases": []], statuses: statuses))) == "no-plan")
        #expect(why(project(tree(plan: ["phases": [["delegations": [["steps": []]]]]], statuses: statuses))) == "no-plan")
        // The tree carries no plan at all: that is not a flat plan.
        #expect(why(project(tree(plan: nil, statuses: statuses))) == "plan-missing")
        #expect(why(project(tree(plan: 5, statuses: statuses))) == "plan-missing")
        #expect(why(project(tree(plan: "not json", statuses: statuses))) == "plan-missing")
    }

    @Test func thePlanMayBeAStringOfJSONAndStatusesToo() throws {
        let frame = tree(plan: json(plan(steps(4))), context: ["_step_statuses": json(["Step 1": entry("completed")])])
        let got = try #require(shown(project(frame)))
        #expect(got.step == 2 && got.total == 4)
    }

    @Test func aPlanOfSeveralPhasesCountsEveryStepInOrder() throws {
        let file = plan([[["P1a", "P1b"]], [["P2a"], ["P2b", "P2c"]]])
        let got = try #require(shown(project(tree(plan: file, statuses: ["P1a": "completed", "P1b": "completed", "P2a": "completed", "P2b": "in_progress"]))))
        #expect(got.total == 5 && got.step == 4 && got.title == "P2b")
    }

    @Test func tooManyStepsIsNoPlan() {
        let huge = plan([[(1...1001).map { "S\($0)" }]])
        #expect(why(project(tree(plan: huge, statuses: ["S1": "completed"]))) == "no-plan")
        #expect(shown(project(tree(plan: plan([[(1...1000).map { "S\($0)" }]]), statuses: ["S1": "completed"]))) != nil)
    }

    @Test func aRootThatIsNotProcessingSaysSoAndKeepsItsCounts() throws {
        let result = project(tree(status: "awaiting_user_response", statuses: ["Step 1": "completed"]))
        #expect(result.object?["processing"] as? Bool == false)
        #expect(shown(result)?.step == 2)
        #expect(shown(project(tree(status: "completed", statuses: ["Step 1": "completed"])))?.step == 2)
    }

    @Test func aStatusWordThePageDoesNotKnowCountsAsNoStatus() throws {
        let result = project(tree(statuses: ["Step 1": "completed", "Step 2": "almost done", "Step 3": "in_progress"]))
        let got = try #require(shown(result))
        #expect(got.step == 2 && got.title == nil)
        #expect(result.object?["unknown"] as? Int == 1)
        #expect(result.object?["reported"] as? Int == 2)
        let only = project(tree(statuses: ["Step 1": "almost done"]))
        #expect(why(only) == "no-statuses")
        #expect(only.object?["unknown"] as? Int == 1)
        // A status that is not an object is none.
        let odd = project(tree(context: ["_step_statuses": ["Step 1": "completed", "Step 2": ["status": 5], "Step 3": NSNull()]]))
        #expect(why(odd) == "no-statuses")
    }

    @Test func titlesThatAreNamesOfObjectsAreNotAlreadyStatuses() throws {
        let file = plan([[["constructor", "toString", "__proto__", "hasOwnProperty"]]])
        #expect(why(project(tree(plan: file))) == "no-statuses")
        let got = try #require(shown(project(tree(plan: file, statuses: ["constructor": "completed", "toString": "in_progress"]))))
        #expect(got.step == 2 && got.title == "toString")
    }

    @Test func aShapeThatDoesNotMatchIsUnreadable() {
        let good = tree(statuses: ["Step 1": "completed"])
        #expect(shown(project(good)) != nil)
        var other = good
        other["id"] = helperA
        #expect(project(other).text == "null")
        #expect(project(good, rootID: "../usage").text == "null")
        #expect(project(good, rootID: String(root.dropLast())).text == "null")
        for (key, value) in [("status", 5), ("context_data", 5), ("children", "x")] as [(String, Any)] {
            var frame = good
            frame[key] = value
            #expect(project(frame).text == "null", "\(key)")
        }
        var noStatus = good
        noStatus["status"] = nil
        #expect(project(noStatus).text == "null")
        #expect(project(tree(context: ["_step_statuses": 5])).text == "null")
        #expect(answer("[]").text == "null")
        #expect(answer("5").text == "null")
        #expect(answer("null").text == "null")
    }

    @Test func aHelperThatIsNotUnderstoodIsLeftOutAndTheRestIsStillCounted() throws {
        let odd: [[String: Any]] = [["id": "x", "context_data": 5], ["context_data": ["_plan_claims": "no"]], ["id": helperB]]
        let frame = tree(statuses: ["Step 1": "completed"], children: odd + [helper(helperA, claims: [(version, ["Step 2"])], statuses: ["Step 2": "completed"])])
        let got = try #require(shown(project(frame)))
        #expect(got.step == 3)
    }

    @Test func aTreeWithoutChildrenIsTheRootAlone() throws {
        var frame = tree(statuses: ["Step 1": "completed"])
        frame["children"] = nil
        #expect(shown(project(frame))?.step == 2)
        frame["children"] = NSNull()
        #expect(shown(project(frame))?.step == 2)
    }
}

// MARK: What Swift accepts of it

struct PlanProgressOutcomeTests {
    private func read(_ object: [String: Any]) -> PlanProgressRead {
        InsightReaderScript.progressOutcome(of: Data(json(object).utf8))
    }

    private func progress(_ changes: [String: Any?] = [:]) -> [String: Any] {
        var object: [String: Any] = ["outcome": "progress", "step": 4, "total": 6, "title": "Check against published screens",
                                     "processing": true, "children": 2, "reported": 3, "unknown": 0]
        for (key, value) in changes { object[key] = value ?? NSNull() }
        return object
    }

    @Test func aWholeAnswerIsRead() {
        let facts = PlanProgressFacts(running: true, children: 2, reported: 3, unknown: 0)
        #expect(read(progress()) == .progress(PlanProgress(step: 4, total: 6, title: "Check against published screens"), facts))
        #expect(read(progress(["title": nil])) == .progress(PlanProgress(step: 4, total: 6, title: nil), facts))
        #expect(read(["outcome": "idle", "why": "complete", "processing": false, "children": 0, "reported": 6, "unknown": 0])
                == .idle(.complete, PlanProgressFacts(running: false, children: 0, reported: 6, unknown: 0)))
        for (word, expected) in [("not-approved", PlanProgressWhy.notApproved), ("no-plan", .noPlan), ("plan-missing", .planMissing),
                                 ("no-statuses", .noStatuses), ("complete", .complete)] {
            let got = read(["outcome": "idle", "why": word, "processing": true, "children": 0, "reported": 0, "unknown": 0])
            #expect(got == .idle(expected, PlanProgressFacts(running: true, children: 0, reported: 0, unknown: 0)), "\(word)")
        }
    }

    @Test func theOtherOutcomes() {
        for (word, expected) in [("lost", PlanProgressRead.lost), ("missing", .missing), ("tooBig", .tooBig),
                                 ("cancelled", .cancelled), ("unreadable", .unreadable), ("refused", .unreadable), ("whatever", .unreadable)] {
            #expect(read(["outcome": word]) == expected, "\(word)")
        }
        #expect(InsightReaderScript.progressOutcome(of: Data("not json".utf8)) == .unreadable)
        #expect(InsightReaderScript.progressOutcome(of: Data("[]".utf8)) == .unreadable)
        #expect(InsightReaderScript.progressOutcome(of: Data(#"{"outcome":5}"#.utf8)) == .unreadable)
    }

    @Test func aFieldOutOfShapeIsUnreadable() {
        let bad: [[String: Any]] = [
            ["step": 0], ["step": 7], ["step": -1], ["step": 1.5], ["step": "4"], ["step": NSNull()],
            ["total": 0], ["total": 1001], ["total": "6"],
            ["title": ""], ["title": "   "], ["title": 5], ["title": "two\nlines"], ["title": " padded "],
            ["title": String(repeating: "x", count: 201)],
            ["processing": 1], ["processing": "true"], ["processing": NSNull()],
            ["children": -1], ["children": 2001], ["reported": 0], ["reported": 7], ["reported": 1.5], ["unknown": -1], ["unknown": 1001],
        ]
        for changes in bad {
            var object = progress()
            for (key, value) in changes { object[key] = value }
            #expect(read(object) == .unreadable, "\(changes)")
        }
    }

    @Test func missingFieldsAreUnreadable() {
        for key in ["step", "total", "processing", "children", "reported", "unknown"] {
            var object = progress()
            object[key] = nil
            #expect(read(object) == .unreadable, "\(key)")
        }
        #expect(read(["outcome": "idle", "why": "complete", "processing": true, "children": 0, "reported": 0]) == .unreadable)
        #expect(read(["outcome": "idle", "why": "sometimes", "processing": true, "children": 0, "reported": 0, "unknown": 0]) == .unreadable)
        #expect(read(["outcome": "idle", "processing": true, "children": 0, "reported": 0, "unknown": 0]) == .unreadable)
    }

    @Test func theLineAndTheBar() {
        #expect(PlanProgress(step: 4, total: 6, title: "Check against published screens").line == "Step 4 of 6 · Check against published screens")
        #expect(PlanProgress(step: 4, total: 6).line == "Step 4 of 6")
        #expect(PlanProgress(step: 4, total: 6, title: "").line == "Step 4 of 6")
        #expect(PlanProgress(step: 1, total: 6).fraction == 0)
        #expect(PlanProgress(step: 4, total: 6).fraction == 0.5)
        #expect(PlanProgress(step: 6, total: 6).fraction == 5.0 / 6.0)
        #expect(PlanProgress(step: 9, total: 6).fraction == 1)
        #expect(PlanProgress(step: 1, total: 0).fraction == 0)
    }
}

// MARK: The reviewer's counts

/// A made-up verification answer: every field a finding holds, with its text secret.
private func check(_ verdict: String, _ status: String, rebuttal: Any? = nil, reflags: Any? = 0) -> [String: Any] {
    var one: [String: Any] = ["id": "SECRET-ID", "claim": "SECRET-CLAIM", "evidence": "SECRET-EVIDENCE", "verdict": verdict,
                              "status": status, "severity": "high", "reviewer_model": "SECRET-MODEL", "source_ref": ["kind": "message_span", "frame_id": root]]
    if let rebuttal { one["rebuttal"] = rebuttal }
    if let reflags { one["reflag_count"] = reflags }
    return one
}

private func verification(_ checks: [[String: Any]], running: [Any] = [], reviews: Any? = 1, byVerdict: Any? = nil) -> [String: Any] {
    var body: [String: Any] = ["checks": checks, "claims": [["claim": "SECRET-CLAIM"]], "running": running,
                               "resolved_total": 3, "actionable_total": checks.count, "actionable_truncated": false]
    if let reviews { body["completed_review_count"] = reviews }
    if let byVerdict { body["resolved_by_verdict"] = byVerdict }
    return body
}

private func counts(_ body: Any) -> (text: String?, object: [String: Any]?) {
    let script = PageScript(InsightReaderScript.reviewerProjection)
    script.set("__body", json(body))
    let text = script.evaluate("JSON.stringify(benchProjectReviewers(JSON.parse(__body)))")
    #expect(script.exception == nil)
    return (text, text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
}

private func four(_ result: (text: String?, object: [String: Any]?)) -> [Int]? {
    guard let o = result.object, o["outcome"] as? String == "counts",
          let standing = o["standing"] as? Int, let fixed = o["fixed"] as? Int, let running = o["running"] as? Int,
          let reviews = o["reviews"] as? Int else { return nil }
    return [standing, fixed, running, reviews]
}

struct ReviewerProjectionTests {
    @Test func aFindingIsAFailOrAWarnThatStillStands() {
        let body = verification([
            check("fail", "open"), check("warn", "claimed"), check("fail", "unaddressed"),
            check("pass", "open"), check("inconclusive", "open"), check("pass", "resolved"),
            check("warn", "resolved"), check("fail", "resolved"), check("fail", "something new"),
        ], reviews: 2)
        let result = counts(body)
        #expect(four(result) == [3, 2, 0, 2])
        // Nothing of any finding comes back.
        #expect(result.text?.contains("SECRET") == false)
        #expect(Set(result.object.map { Array($0.keys) } ?? []) == ["outcome", "standing", "fixed", "running", "reviews"])
    }

    @Test func atTheEndOfATurnTheOpenOnesAreUnaddressedAndStillCount() {
        // Counting only `open` would show 0 here.
        #expect(four(counts(verification([check("fail", "unaddressed"), check("warn", "unaddressed")]))) == [2, 0, 0, 1])
    }

    @Test func anUnaddressedFindingWithARebuttalAndFewReflagsIsWithdrawn() {
        let body = verification([
            check("fail", "unaddressed", rebuttal: "SECRET-REBUTTAL", reflags: 0),     // withdrawn
            check("warn", "unaddressed", rebuttal: "SECRET-REBUTTAL", reflags: 3),     // withdrawn
            check("fail", "unaddressed", rebuttal: "SECRET-REBUTTAL", reflags: 4),     // re-flagged enough: stands
            check("fail", "unaddressed", rebuttal: "SECRET-REBUTTAL", reflags: 9),     // stands
            check("fail", "unaddressed", rebuttal: "", reflags: 0),                    // no rebuttal: stands
            check("fail", "unaddressed", rebuttal: "  \n ", reflags: 0),               // an empty one: stands
            check("fail", "unaddressed", rebuttal: nil, reflags: 0),                   // none at all: stands
            check("warn", "unaddressed", rebuttal: "SECRET-REBUTTAL", reflags: nil),   // no count is 0: withdrawn
            check("warn", "unaddressed", rebuttal: "SECRET-REBUTTAL", reflags: "3"),   // not a number is 0: withdrawn
            check("fail", "open", rebuttal: "SECRET-REBUTTAL", reflags: 0),            // a rebuttal on an open one doesn't withdraw it
            check("fail", "claimed", rebuttal: "SECRET-REBUTTAL", reflags: 0),
        ])
        #expect(four(counts(body)) == [7, 0, 0, 1])
    }

    @Test func fixedComesFromTheChecksOrFromTheCountsByVerdictWhicheverIsMore() {
        // No resolved check is asked for, so the count by verdict is the source.
        #expect(four(counts(verification([check("fail", "open")], byVerdict: ["fail": 2, "warn": 1, "pass": 7, "inconclusive": 4]))) == [1, 3, 0, 1])
        #expect(four(counts(verification([check("fail", "open")], byVerdict: [:]))) == [1, 0, 0, 1])
        // Resolved checks listed in the answer count too, and never twice.
        #expect(four(counts(verification([check("fail", "resolved"), check("warn", "resolved"), check("pass", "resolved")],
                                         byVerdict: ["fail": 1, "warn": 1, "pass": 1]))) == [0, 2, 0, 1])
        #expect(four(counts(verification([check("fail", "resolved"), check("warn", "resolved")], byVerdict: ["fail": 0]))) == [0, 2, 0, 1])
        #expect(four(counts(verification([check("fail", "resolved"), check("warn", "resolved")]))) == [0, 2, 0, 1])
    }

    @Test func aSessionNobodyReviewedIsFourZeros() {
        let empty = verification([], reviews: 0, byVerdict: [:])
        #expect(four(counts(empty)) == [0, 0, 0, 0])
        #expect(four(counts(verification([], reviews: nil))) == [0, 0, 0, 0])
    }

    @Test func reviewsUnderWayAreCounted() {
        let running: [Any] = [["frame_id": root, "target_frame_id": root, "model": "SECRET-MODEL", "created_at": "SECRET-TIME"], ["frame_id": helperA]]
        #expect(four(counts(verification([], running: running, reviews: 3))) == [0, 0, 2, 3])
    }

    @Test func aShapeThatDoesNotMatchIsUnreadable() {
        let bad: [[String: Any]] = [
            ["checks": "no", "running": []],
            ["checks": [], "running": "no"],
            ["running": []],
            ["checks": []],
            ["checks": [5], "running": []],
            ["checks": [["verdict": "fail"]], "running": []],
            ["checks": [["status": "open"]], "running": []],
            ["checks": [["verdict": 5, "status": "open"]], "running": []],
            ["checks": [], "running": [], "completed_review_count": "2"],
            ["checks": [], "running": [], "completed_review_count": -1],
            ["checks": [], "running": [], "completed_review_count": 1.5],
            ["checks": [], "running": [], "resolved_by_verdict": [1, 2]],
            ["checks": [], "running": [], "resolved_by_verdict": ["fail": "2"]],
            ["checks": [], "running": [], "resolved_by_verdict": ["warn": -1]],
        ]
        for body in bad { #expect(counts(body).text == "null", "\(body)") }
    }

    @Test func nothingButAnObjectIsAnAnswer() {
        for body in [[Any](), 5, "x", NSNull()] as [Any] { #expect(counts(body).text == "null") }
    }
}

struct ReviewerOutcomeTests {
    private func read(_ object: [String: Any]) -> ReviewerRead {
        InsightReaderScript.reviewerOutcome(of: Data(json(object).utf8))
    }

    @Test func fourWholeNumbersAreRead() {
        #expect(read(["outcome": "counts", "standing": 2, "fixed": 1, "running": 0, "reviews": 3])
                == .counts(ReviewerCounts(standing: 2, fixed: 1, running: 0, reviews: 3)))
    }

    @Test func theOtherOutcomes() {
        for (word, expected) in [("lost", ReviewerRead.lost), ("missing", .missing), ("tooBig", .tooBig), ("cancelled", .cancelled),
                                 ("unreadable", .unreadable), ("refused", .unreadable), ("progress", .unreadable)] {
            #expect(read(["outcome": word]) == expected, "\(word)")
        }
        #expect(InsightReaderScript.reviewerOutcome(of: Data("nope".utf8)) == .unreadable)
    }

    @Test func aFieldOutOfShapeIsUnreadable() {
        let bad: [[String: Any]] = [
            ["standing": -1], ["standing": 1.5], ["standing": "2"], ["standing": NSNull()], ["standing": 1_000_001],
            ["fixed": -1], ["running": true], ["reviews": "x"],
        ]
        for changes in bad {
            var object: [String: Any] = ["outcome": "counts", "standing": 2, "fixed": 1, "running": 0, "reviews": 3]
            for (key, value) in changes { object[key] = value }
            #expect(read(object) == .unreadable, "\(changes)")
        }
    }

    @Test func anyMissingCountIsUnreadable() {
        for key in ["standing", "fixed", "running", "reviews"] {
            var object: [String: Any] = ["outcome": "counts", "standing": 2, "fixed": 1, "running": 0, "reviews": 3]
            object[key] = nil
            #expect(read(object) == .unreadable, "\(key)")
        }
    }

    @Test func theLineSaysWhatStandsOrThatNothingDoes() {
        func line(_ standing: Int, fixed: Int = 0, running: Int = 0, reviews: Int = 1) -> String? {
            ReviewerCounts(standing: standing, fixed: fixed, running: running, reviews: reviews).line
        }
        #expect(line(2) == "Reviewer: 2 findings")
        #expect(line(1) == "Reviewer: 1 finding")
        #expect(line(0) == "Reviewer: no findings")
        #expect(line(0, fixed: 3) == "Reviewer: no findings")
        // No review ran, or the first is still under way: nothing to say yet.
        #expect(line(0, reviews: 0) == nil)
        #expect(line(0, fixed: 0, running: 1, reviews: 0) == nil)
    }
}

// MARK: The bodies, against a fake page

struct InsightBodyTests {
    private func path(_ tail: String) -> String { "/api/frames/\(root)/\(tail)" }
    private let tracePath = "/api/frames/\(root)/trace-shallow?include_messages=false"
    private let reviewPath = "/api/frames/\(root)/verification?resolved_limit=0&actionable_limit=500"

    private func run(_ body: String, frame: String = "\"\(root)\"", answers: [String: [PageScript.Answer]])
        -> (raw: String?, requests: [PageScript.Request]) {
        let script = PageScript()
        let (raw, requests) = script.runPage(body, arguments: [("frameId", frame)], answers: answers)
        #expect(script.exception == nil)
        return (raw, requests)
    }

    private func ok(_ body: String) -> [PageScript.Answer] { [PageScript.Answer(status: 200, body: body)] }

    @Test func progressIsOneNoStoreGETOfTheTreeAndAnswersTheProjection() {
        let frame = tree(statuses: ["Step 1": "completed", "Step 2": "in_progress"], children: [helper(claims: [(version, ["Step 3"])])])
        let (raw, requests) = run(InsightReaderScript.progressBody, answers: [tracePath: ok(json(frame))])
        #expect(requests.map(\.path) == [tracePath])
        #expect(requests.allSatisfy { $0.cache == "no-store" && $0.method == "GET" && $0.body == nil && $0.csrf == nil })
        #expect(requests.allSatisfy { InsightReaderScript.isAllowedPath($0.path) })
        #expect(raw?.contains("SECRET") == false)
        guard case .progress(let value, let facts)? = raw.map({ InsightReaderScript.progressOutcome(of: Data($0.utf8)) }) else {
            Issue.record("not read: \(raw ?? "nothing")"); return
        }
        #expect(value == PlanProgress(step: 2, total: 6, title: "Step 2"))
        #expect(facts == PlanProgressFacts(running: true, children: 1, reported: 2, unknown: 0))
    }

    @Test func reviewersIsOneNoStoreGETOfTheVerificationRouteWithItsFixedQuery() {
        let body = verification([check("fail", "open"), check("warn", "unaddressed", rebuttal: "SECRET-REBUTTAL")], reviews: 1,
                                byVerdict: ["fail": 1])
        let (raw, requests) = run(InsightReaderScript.reviewerBody, answers: [reviewPath: ok(json(body))])
        #expect(requests.map(\.path) == [reviewPath])
        #expect(requests.allSatisfy { $0.cache == "no-store" && $0.method == "GET" })
        #expect(raw?.contains("SECRET") == false)
        #expect(raw.map { InsightReaderScript.reviewerOutcome(of: Data($0.utf8)) } == .counts(ReviewerCounts(standing: 1, fixed: 1, running: 0, reviews: 1)))
    }

    @Test func aRefusalIsLostAGoneRouteIsMissingAndTheRestIsUnreadable() {
        for (status, body, expected) in [(401, "{}", "lost"), (404, "{}", "missing"), (410, "", "missing"), (500, "{}", "unreadable"),
                                         (403, "{}", "unreadable"), (200, "not json", "unreadable"), (200, "", "unreadable")] {
            for (read, address) in [(InsightReaderScript.progressBody, tracePath), (InsightReaderScript.reviewerBody, reviewPath)] {
                let (raw, _) = run(read, answers: [address: [PageScript.Answer(status: status, body: body)]])
                #expect(raw == #"{"outcome":"\#(expected)"}"#, "\(status) \(address)")
            }
        }
    }

    @Test func aBodyOverTwoMebibytesIsTooBigAndNothingOfItIsRead() {
        let big = String(repeating: " ", count: HistoryReaderScript.bodyCap + 1)
        let (raw, _) = run(InsightReaderScript.progressBody, answers: [tracePath: ok(big)])
        #expect(raw == #"{"outcome":"tooBig"}"#)
        let (reviewer, _) = run(InsightReaderScript.reviewerBody, answers: [reviewPath: ok(big)])
        #expect(reviewer == #"{"outcome":"tooBig"}"#)
    }

    @Test func aFrameIdThatIsNotWholeIsRefusedAndNothingIsFetched() {
        for bad in [#""../../usage""#, #""abc""#, #""\#(root.uppercased())""#, "5", "null", #""\#(root)/x""#, #""\#(root.dropLast())""#] {
            for body in [InsightReaderScript.progressBody, InsightReaderScript.reviewerBody] {
                let (raw, requests) = run(body, frame: bad, answers: [:])
                #expect(raw == #"{"outcome":"refused"}"#, "\(bad)")
                #expect(requests.isEmpty)
            }
        }
    }

    @Test func aNetworkErrorIsUnreadableNotAThrow() {
        let (raw, requests) = run(InsightReaderScript.progressBody, answers: [:])
        #expect(requests.count == 1)
        #expect(raw == #"{"outcome":"unreadable"}"#)
    }

    @Test func aTreeThatIsNotATreeIsUnreadable() {
        let (raw, _) = run(InsightReaderScript.progressBody, answers: [tracePath: ok(#"{"id": "x", "status": "processing"}"#)])
        #expect(raw == #"{"outcome":"unreadable"}"#)
        let (list, _) = run(InsightReaderScript.reviewerBody, answers: [reviewPath: ok("[]")])
        #expect(list == #"{"outcome":"unreadable"}"#)
    }

    @Test func theAllowedPathsAndThePageAgree() {
        let good = [
            "/api/frames/\(root)/trace-shallow?include_messages=false",
            "/api/frames/\(root)/verification?resolved_limit=0&actionable_limit=500",
        ]
        let bad = [
            "/api/frames/\(root)/trace-shallow", "/api/frames/\(root)/trace-shallow?include_messages=true",
            "/api/frames/\(root)/trace-shallow?include_messages=false&x=1", "/api/frames/\(root)/trace-shallow?cursor=1",
            "/api/frames/\(root)/verification", "/api/frames/\(root)/verification?resolved_limit=200&actionable_limit=500",
            "/api/frames/\(root)/verification?actionable_limit=500&resolved_limit=0",
            "/api/frames/\(root)/verification?resolved_limit=0&actionable_limit=501",
            "/api/frames/\(root)/verification?resolved_limit=0&actionable_limit=500&actionable_after=x",
            "/api/frames/\(root.uppercased())/verification?resolved_limit=0&actionable_limit=500",
            "/api/frames/\(root.dropLast())/trace-shallow?include_messages=false",
            "/frames/\(root)/trace-shallow?include_messages=false",
            "/api/frames/\(root)/messages?from=0&limit=1", "/api/frames/\(root)/streaming", "/api/frames/\(root)?shallow=true",
            "/api/frames/\(root)/token-series", "/api/frames/\(root)/audit", "/api/frames/../usage",
            "/api/artifacts/versions/\(version)/verification", "/api/frames/\(root)/verification/../usage",
        ]
        let script = PageScript(InsightReaderScript.fetcher)
        func page(_ path: String) -> Bool {
            script.set("__path", path)
            return script.evaluate("ALLOWED.some(rule => rule.test(__path))") == "true"
        }
        for path in good {
            #expect(InsightReaderScript.isAllowedPath(path), "\(path)")
            #expect(page(path), "\(path)")
        }
        for path in bad {
            #expect(!InsightReaderScript.isAllowedPath(path), "\(path)")
            #expect(!page(path), "\(path)")
        }
        // The builders make nothing else, and nothing from a short or long id.
        #expect(InsightReaderScript.tracePath("abc") == nil && InsightReaderScript.verificationPath("abc") == nil)
        #expect(InsightReaderScript.tracePath(root + "0") == nil)
        #expect(InsightReaderScript.tracePath(root) == good[0] && InsightReaderScript.verificationPath(root) == good[1])
    }

    @Test func theFetchesOfBothBodiesStayInsideTheirOwnPaths() {
        // No other address is written into either body.
        for body in [InsightReaderScript.progressBody, InsightReaderScript.reviewerBody] {
            let literals = body.components(separatedBy: "\"/api/").dropFirst().map { $0.prefix { $0 != "\"" } }
            #expect(literals.allSatisfy { $0.hasPrefix("frames/") }, "\(literals)")
            #expect(!body.contains("method:") && !body.contains("POST") && !body.contains("PUT") && !body.contains("DELETE"))
        }
    }
}
