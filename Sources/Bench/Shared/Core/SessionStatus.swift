// SessionStatus.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.

import Foundation

/// One Claude Science session as the shelf/HUD/pill shows it.
///
/// Metadata only: ids, names, states, timestamps, deep link. Never message
/// bodies, payload text, or research content.
public struct SessionStatus: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectID: String
    public let projectName: String
    public let title: String
    public let state: SessionState
    public let updatedAt: Date
    public let startedAt: Date?
    /// Tokens the whole session has used, when known.
    public let tokens: Int?
    public let deepLink: URL?
    /// Why it waits, when it needs input.
    public let waitingReason: WaitingReason?

    public init(
        id: String,
        projectID: String,
        projectName: String,
        title: String,
        state: SessionState,
        updatedAt: Date,
        startedAt: Date? = nil,
        tokens: Int? = nil,
        deepLink: URL? = nil,
        waitingReason: WaitingReason? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.title = title
        self.state = state
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.tokens = tokens
        self.deepLink = deepLink
        self.waitingReason = state == .needsInput ? (waitingReason ?? .other) : nil
    }

    /// Short display title. Falls back to project name when untitled.
    public var displayTitle: String {
        title.isEmpty ? projectName : title
    }

    /// Session length, when both ends are known. Used for the "don't HUD for
    /// sessions shorter than N seconds" threshold.
    public var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return updatedAt.timeIntervalSince(startedAt)
    }
}

/// The notch's running clock: "0:42", "12:04", "1:02:33".
public enum ElapsedClock {
    /// A span that runs backwards (the Mac's clock moved) reads as 0:00.
    public static func format(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
