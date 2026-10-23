// WriteSettle.swift — what a fresh read says of a write that got no answer
// (DESIGN.md, Bounded writes). Pure: each takes the session as it reads now and
// answers with a result a phone, a card or Quick Start can say as it is:
//
//   · it landed        → the same result the daemon's own answer would have made;
//   · it did not land  → `.retry` ("That didn't go through. Try again."): safe to
//                        send again, because every write here is deduplicated by
//                        the daemon (an intent id, a plan already approved, a
//                        question already resolved), and still only by the person;
//   · cannot be told   → `.unknown` ("Not sure that went through…"), with
//                        nothing claimed either way: the read failed, or showed
//                        something that could be this write and could be
//                        another.
//
// The reads are those the actions already make (`SessionProjection`, which is
// not this file's to change): the frame's status, plan and pending questions,
// the head of the permission queue, the last twelve turns and a bare count of
// queued messages.
import Foundation

// MARK: A plan

/// Where a plan stands against the version that was approved.
enum PlanSettle: Equatable, Sendable {
    /// Still waiting for approval at that version: the approval did not land.
    case waiting
    /// No longer waiting, and approved or working: it landed.
    case approved
    /// Waiting at another version: the plan changed.
    case changed
    /// Nothing that says either.
    case unclear
}

extension PlanCheck {
    /// The root frame, read again after an approval that got no answer.
    static func settle(_ frame: PlanFrame?, version: String) -> PlanSettle {
        guard let frame else { return .unclear }
        if versionToRead(frame) == version { return .waiting }
        if frame.status == awaitingStatus {
            // Waiting, but not for this plan (or not clearly).
            if frame.approval == .no, let other = frame.versionID, isVersionID(other), other != version { return .changed }
            return frame.approval == .yes ? .approved : .unclear
        }
        if frame.approval == .yes { return .approved }
        switch frame.status {
        case "processing", "completed", "success": return .approved
        default: return .unclear
        }
    }

    /// The card's check: the very plan it showed (its artifact too, when both
    /// are known) still waiting is `.waiting`.
    static func settle(_ frame: PlanFrame?, as shown: PlanPreview) -> PlanSettle {
        let settled = settle(frame, version: shown.versionID)
        guard settled == .waiting else { return settled }
        return isSamePlan(frame, as: shown) ? .waiting : .changed
    }
}

// MARK: A message

/// Whether a message just sent can be seen in the session.
enum MessageSeen: Equatable, Sendable {
    /// A turn of yours, made since it was sent, begins with its words.
    case sent
    /// It is not a turn, but the queue holds more messages than before.
    case queued
    /// Neither: it did not land.
    case absent
    /// A turn begins with its words but has no time, so it could be an
    /// earlier message of the same words.
    case unclear

    /// How far before the send a turn may be dated and still be this message
    /// (the two clocks are one Mac's, so this is for rounding).
    static let slack: TimeInterval = 5
    /// How much of the words are compared: the turns the session reads back
    /// are cut, and an attachment line is rewritten to a file name.
    static let compared = 200

    static func look(text: String, turns: [SessionProjection.Turn], since: Date,
                     queuedBefore: Int, queuedNow: Int) -> MessageSeen {
        let wanted = key(of: text)
        var undated = false
        for turn in turns.reversed() where turn.role == .you {
            guard matches(turn.text, wanted) else { continue }
            guard let at = turn.at else { undated = true; continue }
            if at >= since.addingTimeInterval(-slack) { return .sent }
        }
        if queuedNow > queuedBefore { return .queued }
        return undated ? .unclear : .absent
    }

    /// The words of a request without its attachment lines, on one line, and
    /// the first `compared` characters of them.
    static func key(of text: String) -> String {
        let words = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(#"{"type":"attachment""#) }
            .joined(separator: " ")
        return String(oneLine(words).prefix(compared))
    }

    /// A turn is this message when it begins with its words; a message of
    /// files alone has none, and its turn begins with "Attached:".
    static func matches(_ turn: String, _ key: String) -> Bool {
        let line = oneLine(turn)
        return key.isEmpty ? line.hasPrefix("Attached:") : line.hasPrefix(key)
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: The results

extension RemoteDecide {
    /// An approval that got no answer, by the root as it reads now.
    static func settledApprove(version: String, fresh: SessionProjection?) -> RemoteActionResult {
        switch PlanCheck.settle(fresh?.planFrame, version: version) {
        case .waiting: .notThere
        case .approved: RemoteActionResult(result: .approved, sentence: Sentence.approved)
        case .changed: RemoteActionResult(result: .changed, sentence: Sentence.planChanged)
        case .unclear: .unsure
        }
    }

    /// An answer (or Choose for me, or Cancel Question) that got no answer: the
    /// question is still waiting, or it isn't. One that isn't was answered,
    /// most likely by this write; the sentence says only that it was.
    static func settledAnswer(toolID: String, fresh: SessionProjection?) -> RemoteActionResult {
        guard let fresh else { return .unsure }
        if fresh.status == "awaiting_user_response" {
            // A question the read couldn't understand could be this one.
            if fresh.asks.contains(where: { $0 == nil }) { return .unsure }
            if fresh.asks.contains(where: { $0?.toolID == toolID }) { return .notThere }
        }
        return RemoteActionResult(result: .changed, sentence: Sentence.alreadyAnswered)
    }

    /// A message that got no answer: seen in the session, or not. `before` is
    /// the read the write was decided by (its status says send, queue or
    /// resume; its count is the queue's); `fresh` must have the turns.
    static func settledMessage(text: String, before: SessionProjection?, since: Date,
                               fresh: SessionProjection?) -> RemoteActionResult {
        guard let fresh, let turns = fresh.turns else { return .unsure }
        let seen = MessageSeen.look(text: text, turns: turns, since: since,
                                    queuedBefore: before?.queued ?? 0, queuedNow: fresh.queued)
        switch seen {
        case .sent:
            return RemoteMessageMode(status: before?.status ?? "") == .resume
                ? RemoteActionResult(result: .resumed, sentence: Sentence.resumed)
                : RemoteActionResult(result: .sent, sentence: Sentence.sent)
        case .queued:
            return RemoteActionResult(result: .queued, sentence: Sentence.queued)
        case .absent:
            return .notThere
        case .unclear:
            return .unsure
        }
    }

    /// What to change in a plan, sent and not answered: the words are a turn
    /// of yours, or the plan is still waiting at the version shown (and they
    /// are not), or it moved on.
    static func settledPlanFeedback(version: String, text: String, since: Date,
                                    fresh: SessionProjection?) -> RemoteActionResult {
        guard let fresh, let turns = fresh.turns else { return .unsure }
        switch MessageSeen.look(text: text, turns: turns, since: since, queuedBefore: 0, queuedNow: 0) {
        case .sent:
            return RemoteActionResult(result: .sent, sentence: Sentence.revising)
        case .unclear:
            return .unsure
        case .queued, .absent:
            switch PlanCheck.settle(fresh.planFrame, version: version) {
            case .waiting: return .notThere
            case .unclear: return .unsure
            case .approved, .changed: return RemoteActionResult(result: .changed, sentence: Sentence.planChanged)
            }
        }
    }
}

extension PermissionDecide {
    /// A permission answer that got no answer: the same request is still the
    /// head of the queue, or it is not. A session that still waits but shows
    /// no request may be holding one the read couldn't understand.
    static func settled(requestID: String, fresh: SessionProjection?) -> RemoteActionResult {
        guard let fresh else { return .unsure }
        if fresh.permission?.id == requestID { return .notThere }
        if fresh.permission == nil, fresh.status == "awaiting_user_response" { return .unsure }
        return RemoteActionResult(result: .changed, sentence: Sentence.alreadyHandled)
    }
}
