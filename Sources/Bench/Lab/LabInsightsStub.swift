// LabInsightsStub.swift — DELETE THIS FILE WHEN THE DATA BRANCH MERGES.
//
// The panel agent's compile shim for the M6/M7 data contract (brief:
// m678-brief.md, "The data contract"). The data agent's real
// `Lab/LabInsights.swift` and `Lab/SpecimenTopics.swift` declare these same
// names; merging both would be a redeclaration, so this whole file goes.
// Nothing here reads anything: the dictionaries stay empty and the methods
// do nothing. The panel's own tests never use these types' behaviour; they
// build the values by hand (`PlanProgress(step:total:title:)`,
// `ReviewerCounts(standing:fixed:running:reviews:)`,
// `MidRunNote(id:sessionID:text:at:)`) and hand them to the views.
import Combine
import Foundation

struct PlanProgress: Equatable, Sendable {
    let step: Int
    let total: Int
    let title: String?
    var line: String { title.map { "Step \(step) of \(total) · \($0)" } ?? "Step \(step) of \(total)" }
    var fraction: Double { total > 0 ? min(1, max(0, Double(step - 1) / Double(total))) : 0 }
}

struct ReviewerCounts: Equatable, Sendable {
    let standing: Int, fixed: Int, running: Int, reviews: Int
    var line: String? {
        guard reviews > 0 else { return nil }
        return standing == 0 ? "Reviewer: no findings" : "Reviewer: \(standing) finding\(standing == 1 ? "" : "s")"
    }
}

struct MidRunNote: Equatable, Sendable, Identifiable {
    let id: String
    let sessionID: String
    let text: String
    let at: Date?
}

@MainActor
final class LabInsights: ObservableObject {
    static let shared = LabInsights()
    @Published private(set) var progress: [String: PlanProgress] = [:]
    @Published private(set) var reviewers: [String: ReviewerCounts] = [:]
    @Published private(set) var notes: [MidRunNote] = []
    func showing(running sessions: [SessionStatus]) {}
    func wantReviewers(for session: SessionStatus) {}
    func noteSeen(_ id: String) {}
}

enum SpecimenTopics {
    /// The stub names a candidate whose name the title contains, and nothing else.
    static func match(title: String, sessionID: String, candidates: [String]) -> (name: String, topic: String)? {
        let folded = title.lowercased()
        return candidates.sorted().first { folded.contains($0.lowercased()) }.map { ($0, $0) }
    }
}
