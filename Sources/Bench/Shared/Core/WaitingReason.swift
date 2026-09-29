// WaitingReason.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.

import Foundation

/// Why a session is waiting on the user, in the daemon's own vocabulary: its
/// two `awaiting_*` statuses, or the `kind` of the first pending input
/// request (Claude Science 0.1.53 parses `ask`, `network`, `host`,
/// `host_delete`, `mcp_tool` and `skill_license`). That one word is all that
/// is read: never what was asked, nor what it wants to reach.
public enum WaitingReason: String, Sendable, Equatable, Codable, CaseIterable {
    case plan
    case question
    case web
    case files
    case delete
    case tool
    case license
    case other

    /// `signal` is what the session query reports for a waiting session: an
    /// `awaiting_*` status, else a pending request's kind, else nothing.
    public init(signal: String?) {
        switch signal {
        case "awaiting_plan_approval": self = .plan
        case "awaiting_user_response", "ask": self = .question
        case "network": self = .web
        case "host": self = .files
        case "host_delete": self = .delete
        case "mcp_tool": self = .tool
        case "skill_license": self = .license
        default: self = .other
        }
    }

    /// A few words for the pill: what the user is being asked to do.
    public var shortLabel: String {
        switch self {
        case .plan: return "Review plan"
        case .question: return "Question"
        case .web: return "Web access"
        case .files: return "File access"
        case .delete: return "Delete files"
        case .tool: return "Tool access"
        case .license: return "License"
        case .other: return "Needs you"
        }
    }

    /// A sentence for cards and rows.
    public var sentence: String {
        switch self {
        case .plan: return "Plan ready for your review"
        case .question: return "Asked you a question"
        case .web: return "Wants to reach the web"
        case .files: return "Wants to use files on your Mac"
        case .delete: return "Wants to delete files"
        case .tool: return "Wants to use a connector tool"
        case .license: return "Needs a skill license accepted"
        case .other: return "Waiting for you"
        }
    }

    /// Which of the three waiting glyphs shows it.
    public var glyph: WaitingGlyph {
        switch self {
        case .plan: return .plan
        case .question, .other: return .question
        case .web, .files, .delete, .tool, .license: return .permission
        }
    }

    /// The menu bar's symbol, which can only be a symbol.
    public var systemImage: String {
        switch self {
        case .plan: return "checklist"
        case .question, .other: return "questionmark.bubble.fill"
        case .web, .files, .delete, .tool, .license: return "lock.fill"
        }
    }
}

/// The three animated glyphs a waiting session can show.
public enum WaitingGlyph: String, Sendable, Equatable, CaseIterable {
    /// A clipboard whose last box blinks, waiting to be ticked.
    case plan
    /// A question mark bobbing in a speech bubble.
    case question
    /// A padlock whose shackle keeps trying to lift.
    case permission
}
