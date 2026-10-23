// SinceYouLeftReads.swift — the two reads a row of Since You Left may ask the
// page for, each a shallow one (DESIGN.md, 1.0 spikes S5: six shallow frames,
// not six history pages): the last answer of a finished session
// (`readSession(_, turns: false)`, one GET whose `reply` is already Claude's
// last words) and the frame of a stopped one (`GET /api/frames/<id>?shallow=true`,
// the failure card's own read). Both go through the typing gate, so neither
// starts within 400 ms of a key press in the main window, and one runs at a
// time. What was read is turned into a couple of plain lines or a sentence and
// the rest is dropped. Nothing here logs what a session says.
import Combine
import Foundation

@MainActor
enum SinceYouLeftReads {
    /// Claude's last words in a finished session: its first lines as plain text.
    static func answer(for sessionID: String, gate: ReadingGate = .shared) async -> String? {
        guard Demo.mode == nil else { return nil }
        let read = try? await gate.perform { () -> SessionProjection? in
            try await WebContainer.shared.readSession(sessionID, turns: false)
        }
        guard let reply = read?.reply else { return nil }
        return AnswerLines.first(reply)
    }

    /// Says when the card reads (or lets go of) a reason: the phone's state has it for a stopped row.
    static var reasonChanges: AnyPublisher<Void, Never> {
        FailureReasoner.shared.$states.map { _ in () }.eraseToAnyPublisher()
    }

    /// What the failure card has already read of why a session stopped, its first line: no read of ours.
    /// (This file is the one place Since You Left names the reason's type, as the card's own file does.)
    static func known(for sessionID: String) -> String? {
        FailureReasoner.shared.reason(for: sessionID)?.line
    }

    /// All of the reason the card read, for Copy.
    static func full(for sessionID: String) -> String? {
        FailureReasoner.shared.reason(for: sessionID)?.full
    }

    /// Why a session stopped, the first line of the reason, when it says.
    static func reason(for sessionID: String, gate: ReadingGate = .shared) async -> String? {
        guard Demo.mode == nil, let path = FailureCheck.framePath(sessionID) else { return nil }
        let data = try? await gate.perform { () -> Data in try await WebContainer.shared.apiGET(path) }
        guard let data, let frame = FailureFrame(json: data), let reason = FailureReason(frame: frame) else { return nil }
        return reason.line
    }
}
