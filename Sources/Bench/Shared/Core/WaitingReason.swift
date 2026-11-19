// WaitingReason.swift
// ScienceStatus — DroppyKit-free core. No DroppyKit import in this file.

import Foundation

/// Why a session is waiting on the user, in the daemon's own vocabulary: its
/// two `awaiting_*` statuses, or the `kind` of the first pending input
/// request (Claude Science 0.1.53 parses `ask`, `network`, `host`,
/// `host_delete`, `mcp_tool` and `skill_license`; 0.1.73 adds `share_save`).
/// That one word is all that is read: never what was asked, nor what it wants
/// to reach. One flag stands in for the kind: a request held by the saved-key
/// check (`key_check_held`, 0.1.73) reads as `key_check_held`.
public enum WaitingReason: String, Sendable, Equatable, Codable, CaseIterable {
    case plan
    case question
    case web
    case files
    case delete
    case tool
    case license
    /// `local_exec`: code to run.
    case code
    /// `credential_access`: a saved key handed to Claude's code.
    case credentials
    /// Any request the saved-key check holds (Claude Science 0.1.73): denied
    /// by the daemon after 10 minutes with nobody looking.
    case keyCheck
    /// `share_save` (0.1.73): a file or folder saved into a Read & write folder.
    case saveFile
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
        case "local_exec": self = .code
        case "credential_access": self = .credentials
        case "key_check_held": self = .keyCheck
        case "share_save": self = .saveFile
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
        case .code: return "Run code"
        case .credentials: return "Saved key"
        case .keyCheck: return "Safety check"
        case .saveFile: return "Save file"
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
        case .code: return "Wants to run code"
        case .credentials: return "Wants to use a saved key"
        case .keyCheck: return "Wants your OK to use a saved key. Skipped after 10 minutes"
        case .saveFile: return "Wants to save a file into your folder"
        case .other: return "Waiting for you"
        }
    }

    /// Which of the three waiting glyphs shows it.
    public var glyph: WaitingGlyph {
        switch self {
        case .plan: return .plan
        case .question, .other: return .question
        case .web, .files, .delete, .tool, .license, .code, .credentials, .keyCheck, .saveFile: return .permission
        }
    }

    /// The menu bar's symbol, which can only be a symbol.
    public var systemImage: String {
        switch self {
        case .plan: return "checklist"
        case .question, .other: return "questionmark.bubble.fill"
        case .web, .files, .delete, .tool, .license, .code, .credentials, .keyCheck, .saveFile: return "lock.fill"
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
