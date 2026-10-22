// PanelInsights.swift — what the panel knows of the sessions beyond their
// state: a plan's progress, a reviewer's findings, the notes Claude sent
// mid-run (Lab/LabInsights.swift reads them from Claude Science, gated by
// "Show plans, questions and requests on the card"). The panel and the
// activity list read this and never `LabInsights` itself, for two reasons:
//   - the two of them both say which running sessions are on screen, and
//     `LabInsights.showing(running:)` takes one list, so this puts them
//     together (a session shown by either is read);
//   - a demo, a snapshot and a test show made-up insights without anything
//     reading, which the contract gives `LabInsights` no setter for.
// It follows `LabInsights` unless it was told to show something made up.
import Combine
import Foundation

@MainActor
final class PanelInsights: ObservableObject {
    static let shared = PanelInsights(following: LabInsights.shared)

    /// By session id: only sessions that were asked for.
    @Published private(set) var progress: [String: PlanProgress] = [:]
    @Published private(set) var reviewers: [String: ReviewerCounts] = [:]
    /// Unseen, newest first.
    @Published private(set) var notes: [MidRunNote] = []

    /// Who says which sessions are on screen.
    enum Reporter: Hashable, Sendable { case panel, list }

    private var source: LabInsights?
    private var subscriptions = Set<AnyCancellable>()
    private var shown: [Reporter: [SessionStatus]] = [:]

    /// Follows `source`; nil follows nothing (a test's, a demo's).
    init(following source: LabInsights? = nil) {
        self.source = source
        guard let source else { return }
        source.$progress.sink { [weak self] in self?.progress = $0 }.store(in: &subscriptions)
        source.$reviewers.sink { [weak self] in self?.reviewers = $0 }.store(in: &subscriptions)
        source.$notes.sink { [weak self] in self?.notes = $0 }.store(in: &subscriptions)
    }

    // MARK: Asking

    /// `reporter` shows these running sessions now (none, when it stops
    /// showing any). `LabInsights` is told the sessions either one shows.
    func showing(_ sessions: [SessionStatus], from reporter: Reporter) {
        guard shown[reporter] != sessions else { return }
        shown[reporter] = sessions
        source?.showing(running: Self.union(shown[.panel] ?? [], shown[.list] ?? []))
    }

    /// The sessions of both lists, each once, the panel's first.
    static func union(_ first: [SessionStatus], _ second: [SessionStatus]) -> [SessionStatus] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }

    /// A finished card is up for this session: its reviewer line is read once.
    func wantReviewers(for session: SessionStatus) {
        source?.wantReviewers(for: session)
    }

    /// A note card was shown or dismissed: it isn't offered again.
    func noteSeen(_ id: String) {
        notes.removeAll { $0.id == id }
        source?.noteSeen(id)
    }

    // MARK: Made up

    /// Shows made-up insights and follows nothing: no read is made. Only a
    /// demo, a snapshot or a test calls it.
    func showDemo(progress: [String: PlanProgress] = [:], reviewers: [String: ReviewerCounts] = [:],
                  notes: [MidRunNote] = []) {
        subscriptions.removeAll()
        source = nil
        self.progress = progress
        self.reviewers = reviewers
        self.notes = notes
    }
}
