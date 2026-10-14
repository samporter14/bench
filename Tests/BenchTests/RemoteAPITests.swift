// RemoteAPITests.swift — `/api/state` and `/api/sessions/<id>` built from
// made-up sessions, checked as the JSON the phone reads.
import Foundation
import Testing
@testable import Bench

@MainActor
struct RemoteAPITests {
    private let now = Date(timeIntervalSince1970: 1_791_833_400) // 2026-10-12T19:30:00Z

    private func session(_ id: String, _ state: SessionState, reason: WaitingReason? = nil,
                         title: String = "Protein stability screen", started: TimeInterval? = -600) -> SessionStatus {
        SessionStatus(id: id, projectID: "p", projectName: "Example project", title: title, state: state,
                      updatedAt: now.addingTimeInterval(-60), startedAt: started.map { now.addingTimeInterval($0) },
                      waitingReason: reason)
    }

    private func input(waiting: [SessionStatus] = [], snoozed: [SnoozedReminder] = [], failed: [SessionStatus] = [],
                       working: [SessionStatus] = [], recent: [LabEvent] = [], limits: [PlanLimit] = [],
                       forecasts: [PlanLimit.Kind: Forecast] = [:], problem: ScienceError? = nil) -> RemoteAPI.Input {
        RemoteAPI.Input(bench: "0.4.0", now: now, problem: problem, waiting: waiting, snoozed: snoozed, failed: failed,
                        working: working, recent: recent, limits: limits, forecasts: forecasts)
    }

    /// The JSON as the phone gets it, parsed back.
    private func json<T: Encodable>(_ value: T) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: RemoteAPI.encode(value))) as? [String: Any] ?? [:]
    }

    @Test func anEmptyStateHasItsNulls() {
        let text = String(decoding: RemoteAPI.encode(RemoteAPI.state(input())), as: UTF8.self)
        #expect(text == #"{"bench":"0.4.0","failed":[],"needsYou":[],"problem":null,"recent":[],"updatedAt":"2026-10-12T19:30:00Z","usage":null,"version":1,"working":[]}"#)
    }

    @Test func whatNeedsYouSaysWhyAndWhetherItIsPutOff() {
        let plan = session("a", .needsInput, reason: .plan)
        let question = session("b", .needsInput, reason: .question, title: "")
        let focus = session("c", .needsInput, reason: .web)
        let state = json(RemoteAPI.state(input(
            waiting: [plan, question, focus],
            snoozed: [SnoozedReminder(session: plan, due: now.addingTimeInterval(20 * 60)),
                      SnoozedReminder(session: focus, due: nil)])))
        let needsYou = state["needsYou"] as? [[String: Any]] ?? []
        #expect(needsYou.count == 3)
        #expect(needsYou[0]["id"] as? String == "a")
        #expect(needsYou[0]["title"] as? String == "Protein stability screen")
        #expect(needsYou[0]["project"] as? String == "Example project")
        #expect(needsYou[0]["reason"] as? String == "plan")
        #expect(needsYou[0]["sentence"] as? String == "Plan ready for your review")
        #expect(needsYou[0]["since"] as? String == "2026-10-12T19:29:00Z")
        let snooze = needsYou[0]["snooze"] as? [String: Any]
        #expect(snooze?["until"] as? String == "2026-10-12T19:50:00Z")
        #expect(snooze?["afterFocus"] as? Bool == false)
        // Untitled: the project's name, as everywhere in Bench.
        #expect(needsYou[1]["title"] as? String == "Example project")
        #expect(needsYou[1]["snooze"] is NSNull)
        let afterFocus = needsYou[2]["snooze"] as? [String: Any]
        #expect(afterFocus?["until"] is NSNull)
        #expect(afterFocus?["afterFocus"] as? Bool == true)
    }

    @Test func theBadgeIsWhatNeedsYouPlusWhatStopped() {
        #expect(RemoteAPI.state(input()).badge == 0)
        let plan = session("a", .needsInput, reason: .plan)
        let state = RemoteAPI.state(input(waiting: [plan, session("b", .needsInput, reason: .question)],
                                          snoozed: [SnoozedReminder(session: plan, due: now.addingTimeInterval(600))],
                                          failed: [session("f", .error)], working: [session("w", .running)]))
        // A session put off still waits; one that works doesn't count.
        #expect(state.badge == 3)
        #expect(state.badge == state.needsYou.count + state.failed.count)
    }

    @Test func theLabsBadgeIsTheStatesBadge() {
        let lab = LabModel()
        #expect(RemoteAPI.badge(lab: lab) == 0)
        lab.ingest(Fixture.snapshot(Fixture.session("a", .running), Fixture.session("b", .running), Fixture.session("c", .running)))
        lab.ingest(Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan), Fixture.session("b", .error),
                                    Fixture.session("c", .finished)))
        // A finish is not something that needs you.
        #expect(RemoteAPI.badge(lab: lab) == 2)
        let input = RemoteAPI.input(lab: lab, usage: PlanUsageModel.shared, bench: "test", now: now)
        #expect(RemoteAPI.state(input).badge == RemoteAPI.badge(lab: lab))
        #expect(RemoteAPI.failedSessions(lab: lab).map(\.id) == ["b"])
    }

    @Test func failedWorkingAndRecent() {
        let failed = session("f", .error)
        let working = session("w", .running, started: -125)
        let unstarted = session("u", .running, started: nil)
        let finished = session("d", .finished)
        let recent = [
            LabEvent(.finished, session: finished, at: now.addingTimeInterval(-30)),
            LabEvent(.saved(URL(fileURLWithPath: "/tmp/private-results.csv")), session: nil, at: now.addingTimeInterval(-40)),
            LabEvent(.needsInput(.plan), session: session("a", .needsInput, reason: .plan), at: now.addingTimeInterval(-50)),
            LabEvent(.failed, session: failed, at: now.addingTimeInterval(-70)),
        ]
        let state = json(RemoteAPI.state(input(failed: [failed], working: [working, unstarted], recent: recent)))
        let failedRows = state["failed"] as? [[String: Any]] ?? []
        #expect(failedRows.count == 1)
        #expect(failedRows.first?["since"] as? String == "2026-10-12T19:29:00Z")
        let workingRows = state["working"] as? [[String: Any]] ?? []
        #expect(workingRows.first?["startedAt"] as? String == "2026-10-12T19:27:55Z")
        #expect(workingRows.last?["startedAt"] is NSNull)
        let recentRows = state["recent"] as? [[String: Any]] ?? []
        // The download is left out: its file name stays on the Mac.
        #expect(recentRows.map { $0["kind"] as? String } == ["finished", "needsInput", "failed"])
        #expect(recentRows.map { $0["line"] as? String } == ["Finished", "Had a plan for you to review", "Stopped with an error"])
        #expect(recentRows.first?["at"] as? String == "2026-10-12T19:29:30Z")
        #expect(!String(decoding: RemoteAPI.encode(RemoteAPI.state(input(recent: recent))), as: UTF8.self).contains("private-results"))
    }

    @Test func usageHasTheLimitsAndThePace() {
        let reset = now.addingTimeInterval(90 * 60)
        let state = json(RemoteAPI.state(input(
            limits: [PlanLimit(kind: .session, usedPercent: 54, resetsAt: reset),
                     PlanLimit(kind: .week, usedPercent: 20, resetsAt: nil)],
            forecasts: [.session: .lastsUntilReset, .week: .tooEarly])))
        let limits = (state["usage"] as? [String: Any])?["limits"] as? [[String: Any]] ?? []
        #expect(limits.count == 2)
        #expect(limits[0]["name"] as? String == "5-hour")
        #expect(limits[0]["usedPercent"] as? Int == 54)
        #expect(limits[0]["resetsAt"] as? String == "2026-10-12T21:00:00Z")
        #expect(limits[0]["pace"] as? String == "At this pace: lasts until it resets")
        #expect(limits[1]["name"] as? String == "Weekly")
        #expect(limits[1]["resetsAt"] is NSNull)
        #expect(limits[1]["pace"] is NSNull)
    }

    @Test func theProblemIsAShortSentence() {
        let state = json(RemoteAPI.state(input(problem: .daemonNotRunning)))
        #expect(state["problem"] as? String == "Claude Science isn't running")
    }

    @Test func aChangeIsToldFromATick() {
        let one = RemoteAPI.state(input(working: [session("w", .running)]))
        #expect(one.at(.distantPast) == RemoteAPI.state(RemoteAPI.Input(
            bench: "0.4.0", now: now.addingTimeInterval(5), problem: nil, waiting: [], snoozed: [], failed: [],
            working: [session("w", .running)], recent: [], limits: [], forecasts: [:])).at(.distantPast))
        #expect(one.at(.distantPast) != RemoteAPI.state(input()).at(.distantPast))
    }

    // MARK: One session

    private let preview = PlanPreview(summary: "Screen 24 buffer conditions", steps: 3, confidence: "high",
                                      stepTitles: ["Prepare the stocks", "Lay out the plate", "Read the plate"],
                                      versionID: "v1", artifactID: nil)

    @Test func aSessionWaitingOnItsPlanCarriesThePlan() {
        let waiting = session("a", .needsInput, reason: .plan)
        guard let built = RemoteAPI.session(id: "a", candidates: [session("b", .running), waiting], plan: preview) else {
            Issue.record("not found")
            return
        }
        let detail = json(built)
        #expect(detail["version"] as? Int == 2)
        #expect(detail["state"] as? String == "needsInput")
        #expect(detail["reason"] as? String == "plan")
        #expect(detail["sentence"] as? String == "Plan ready for your review")
        #expect(detail["startedAt"] as? String == "2026-10-12T19:20:00Z")
        #expect(detail["updatedAt"] as? String == "2026-10-12T19:29:00Z")
        let plan = detail["plan"] as? [String: Any]
        #expect(plan?["summary"] as? String == "Screen 24 buffer conditions")
        #expect(plan?["steps"] as? [String] == ["Prepare the stocks", "Lay out the plate", "Read the plate"])
        #expect(plan?["feasibility"] as? String == "high")
        #expect((detail["messages"] as? [Any])?.isEmpty == true)
    }

    @Test func noPlanUnlessTheSessionWaitsOnOne() {
        let question = json(RemoteAPI.session(id: "a", candidates: [session("a", .needsInput, reason: .question)], plan: preview)!)
        #expect(question["plan"] is NSNull)
        let none = json(RemoteAPI.session(id: "a", candidates: [session("a", .needsInput, reason: .plan)], plan: nil)!)
        #expect(none["plan"] is NSNull)
        let running = json(RemoteAPI.session(id: "a", candidates: [session("a", .running)], plan: preview)!)
        #expect(running["plan"] is NSNull)
        #expect(running["reason"] is NSNull)
        #expect(running["sentence"] as? String == "Working")
    }

    @Test func anUnknownSessionIsNil() {
        #expect(RemoteAPI.session(id: "zz", candidates: [session("a", .running)], plan: nil) == nil)
    }

    @Test func theFirstCandidateWins() {
        let fresh = session("a", .error)
        let stale = session("a", .running)
        #expect(RemoteAPI.session(id: "a", candidates: [fresh, stale], plan: nil)?.state == "error")
    }

    @Test func theMeAnswer() {
        let me = String(decoding: RemoteAPI.encode(RemoteAPI.Me(paired: true, device: "Pat's iPhone", bench: "0.4.0", browse: true)), as: UTF8.self)
        #expect(me == #"{"bench":"0.4.0","browse":true,"device":"Pat's iPhone","paired":true}"#)
    }
}
