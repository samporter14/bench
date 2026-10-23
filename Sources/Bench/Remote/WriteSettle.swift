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
// the head of the permission queue, the last twelve turns (a turn of yours
// with its intent id and its files' ids) and a bare count of queued messages.
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

/// Whether a message just sent can be seen in the session, by what ties a
/// turn to this very message and to no other.
///
/// The turn's intent id is this message's (a turn of yours carries the id it
/// was sent with, `_intent_id`): it is this one, whatever its words. A turn
/// with another intent id is never this one; if it has the same words since
/// the send, though, it leaves the answer unclear rather than absent. A turn
/// with no intent id is this one only when all of it agrees: the same words,
/// whole (not their opening), the same files (by id, not by name), and a time
/// no earlier than the send. A larger queue says nothing of whose message
/// joined it: another device's would do the same.
enum MessageSeen: Equatable, Sendable {
    /// A turn that is this message.
    case sent
    /// Nothing that is this message, and nothing that could be.
    case absent
    /// Something that could be this message and could be another: a turn of
    /// the same words with no time, cut short, or whose files can't be seen;
    /// or a queue that grew.
    case unclear

    static func look(text: String, intent: String?, turns: [SessionProjection.Turn], since: Date,
                     queuedBefore: Int, queuedNow: Int) -> MessageSeen {
        let wanted = Request(text)
        // Turns are dated in whole milliseconds; the send began within the one `since` is in.
        let start = Date(timeIntervalSince1970: (since.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        var maybe = false
        for turn in turns.reversed() where turn.role == .you {
            if let seen = turn.intent, seen == intent { return .sent }
            let likeness = wanted.compare(turn)
            if likeness == .different { continue }
            // Nil: the turn has no time, so it could be from before the send or after.
            let since = turn.at.map { $0 >= start }
            if likeness == .same, turn.intent == nil, since == true { return .sent }
            if since ?? true { maybe = true }
        }
        if queuedNow > queuedBefore { return .unclear }
        return maybe ? .unclear : .absent
    }

    /// A request's words and files, as the session reader would show them.
    struct Request: Equatable {
        /// The words without the attachment lines, on one line.
        let words: String
        /// The attachment lines' file ids, lowercased, in order.
        let files: [String]

        init(_ text: String) {
            var kept: [Substring] = []
            var files: [String] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if let id = MessageSeen.attachmentID(line) {
                    files.append(id)
                } else {
                    kept.append(line)
                }
            }
            words = MessageSeen.oneLine(kept.joined(separator: "\n"))
            self.files = files
        }

        enum Likeness { case same, couldBe, different }

        /// How a turn of yours compares with it.
        func compare(_ turn: SessionProjection.Turn) -> Likeness {
            // The reader cuts a long turn and ends it "…": only its opening can be compared.
            let limit = SessionProjection.Limit.turn
            if turn.text.unicodeScalars.count >= limit, turn.text.hasSuffix("…") {
                let opening = MessageSeen.oneLine(String(turn.text.dropLast()))
                return !opening.isEmpty && words.hasPrefix(opening) ? .couldBe : .different
            }
            guard MessageSeen.oneLine(MessageSeen.withoutFileNames(turn)) == words else { return .different }
            if turn.files == files { return .same }
            // The words are these, but the files can't be seen in the turn.
            return turn.files.isEmpty && !files.isEmpty ? .couldBe : .different
        }
    }

    /// A line that is one of Claude Science's attachment lines: its file id.
    static func attachmentID(_ line: Substring) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(#"{"type":"attachment""#),
              let object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any],
              Pick.string(object["type"]) == "attachment" else { return nil }
        guard let id = Pick.string(object["id"]), PhotoAttachment.isUUID(id) else { return "" }
        return id.lowercased()
    }

    /// A turn's words: the reader puts "Attached: <names>" after them, as a
    /// paragraph of its own, when the message had files.
    static func withoutFileNames(_ turn: SessionProjection.Turn) -> String {
        guard !turn.files.isEmpty else { return turn.text }
        if let range = turn.text.range(of: "\n\nAttached: ", options: .backwards) {
            return String(turn.text[..<range.lowerBound])
        }
        return turn.text.hasPrefix("Attached: ") ? "" : turn.text
    }

    static func oneLine(_ text: String) -> String {
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

    /// A message that got no answer: seen in the session, or not
    /// (`MessageSeen`). `intent` is the id it was sent with; `before` is the
    /// read the write was decided by (its status says send, queue or resume;
    /// its count is the queue's); `fresh` must have the turns. Sent only on a
    /// turn that is this message: a queue that grew is unknown, never queued.
    static func settledMessage(text: String, intent: String?, before: SessionProjection?, since: Date,
                               fresh: SessionProjection?) -> RemoteActionResult {
        guard let fresh, let turns = fresh.turns else { return .unsure }
        let seen = MessageSeen.look(text: text, intent: intent, turns: turns, since: since,
                                    queuedBefore: before?.queued ?? 0, queuedNow: fresh.queued)
        switch seen {
        case .sent:
            return RemoteMessageMode(status: before?.status ?? "") == .resume
                ? RemoteActionResult(result: .resumed, sentence: Sentence.resumed)
                : RemoteActionResult(result: .sent, sentence: Sentence.sent)
        case .absent:
            return .notThere
        case .unclear:
            return .unsure
        }
    }

    /// What to change in a plan, sent and not answered: the words are a turn
    /// of yours (by the same rule as a message), or the plan is still waiting
    /// at the version shown (and they are not), or it moved on.
    static func settledPlanFeedback(version: String, text: String, intent: String?, since: Date,
                                    fresh: SessionProjection?) -> RemoteActionResult {
        guard let fresh, let turns = fresh.turns else { return .unsure }
        switch MessageSeen.look(text: text, intent: intent, turns: turns, since: since, queuedBefore: 0, queuedNow: 0) {
        case .sent:
            return RemoteActionResult(result: .sent, sentence: Sentence.revising)
        case .unclear:
            return .unsure
        case .absent:
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
