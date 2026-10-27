// SessionEndingTests.swift — how a turn that is over ended (Shared/Core/SessionState.swift):
// the one thing `SessionState.finished` leaves out. Only a status the daemon
// calls completed is a success, which is what a closing gesture is for.
import Testing
@testable import Bench

struct SessionEndingTests {
    @Test func onlyCompletedAndSuccessAreSuccessesAndNothingIsGuessed() {
        #expect(SessionEnding(frameStatus: "completed") == .completed)
        #expect(SessionEnding(frameStatus: "success") == .completed)
        #expect(SessionEnding(frameStatus: "cancelled") == .cancelled)
        #expect(SessionEnding(frameStatus: "replaced") == .replaced)
        for status in ["processing", "failed", "error", "awaiting_user_response", "something new", ""] {
            #expect(SessionEnding(frameStatus: status) == nil, "\(status)")
        }
        // All three still read as finished, as before.
        for status in ["completed", "success", "cancelled", "replaced"] {
            #expect(SessionState(frameStatus: status) == .finished)
        }
    }
}
