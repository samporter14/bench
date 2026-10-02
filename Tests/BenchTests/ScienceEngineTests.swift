// ScienceEngineTests.swift — the transitions the panel and cards are built on.
import Foundation
import Testing
@testable import Bench

struct ScienceEngineTests {
    @Test func workingWaitingWorkingFinished() {
        var engine = ScienceEngine(minDuration: 30)
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .running))).count == 1)
        let waiting = engine.advance(to: Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(waiting.map(kind) == ["needsInput"])
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .running))).map(kind) == ["started"])
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .finished))).map(kind) == ["finished"])
    }

    @Test(arguments: [SessionState.running, .needsInput])
    func failureFromWorkingOrWaiting(_ before: SessionState) {
        var engine = ScienceEngine(minDuration: 30)
        _ = engine.advance(to: Fixture.snapshot(Fixture.session("a", before, reason: .question)))
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .error))).map(kind) == ["failed"])
    }

    @Test func aNewKindOfRequestEmitsAgainTheSameOneDoesNot() {
        var engine = ScienceEngine(minDuration: 30)
        _ = engine.advance(to: Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question)))
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .needsInput, reason: .question))).isEmpty)
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .needsInput, reason: .plan))).map(kind) == ["needsInput"])
    }

    @Test func aFailedReadKeepsTheBaselineSoAFinishDuringTheGapStillEmits() {
        var engine = ScienceEngine(minDuration: 30)
        _ = engine.advance(to: Fixture.snapshot(Fixture.session("a", .running)))
        #expect(engine.advance(to: Fixture.failedRead).isEmpty)
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .finished))).map(kind) == ["finished"])
    }

    @Test func shortSessionsAndHistoryStayQuiet() {
        var engine = ScienceEngine(minDuration: 30)
        _ = engine.advance(to: Fixture.snapshot(Fixture.session("a", .running, minutes: 0.1)))
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("a", .finished, minutes: 0.1))).isEmpty)
        // A finished row never seen running is history, not news.
        #expect(engine.advance(to: Fixture.snapshot(Fixture.session("b", .finished))).isEmpty)
    }

    @Test func statusMapping() {
        #expect(SessionState(frameStatus: "processing") == .running)
        #expect(SessionState(frameStatus: "processing", hasPendingInput: true) == .needsInput)
        #expect(SessionState(frameStatus: "awaiting_plan_approval") == .needsInput)
        #expect(SessionState(frameStatus: "failed") == .error)
        #expect(SessionState(frameStatus: "completed") == .finished)
        #expect(SessionState(frameStatus: "something new") == .unknown)
    }

    private func kind(_ transition: ScienceTransition) -> String {
        switch transition {
        case .started: "started"
        case .finished: "finished"
        case .needsInput: "needsInput"
        case .failed: "failed"
        }
    }
}
