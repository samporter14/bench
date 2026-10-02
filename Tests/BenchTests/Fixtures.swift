// Fixtures.swift — made-up sessions and snapshots. Nothing here comes from a
// real Claude Science database.
import Foundation
@testable import Bench

enum Fixture {
    /// A session that started `minutes` ago and was last written now.
    static func session(_ id: String, _ state: SessionState, reason: WaitingReason? = nil,
                        minutes: Double = 10, title: String = "Example session") -> SessionStatus {
        let now = Date()
        return SessionStatus(id: id, projectID: "p", projectName: "Example project", title: title,
                             state: state, updatedAt: now, startedAt: now.addingTimeInterval(-minutes * 60),
                             waitingReason: reason)
    }

    static func snapshot(_ sessions: SessionStatus...) -> ScienceSnapshot {
        ScienceSnapshot(runningCount: sessions.count, daemonVersion: "test", sessions: sessions)
    }

    static let failedRead = ScienceSnapshot(runningCount: nil, daemonVersion: nil, sessions: [],
                                            readError: .databaseUnreadable("test"))
}
