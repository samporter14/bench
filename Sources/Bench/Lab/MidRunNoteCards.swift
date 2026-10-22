// MidRunNoteCards.swift — a note Claude sent while it worked, as a quiet card
// (DESIGN.md, Notices, "Claude says"). `LabInsights` reads the notes (gated by
// "Show plans, questions and requests on the card"); this turns each unseen
// one into a notice that queues behind the cards about sessions, times out and
// never plays a sound, and tells `LabInsights` the note was seen when its card
// reaches the top of the panel, so it is never offered twice. Its words reach
// the screen only: no Mac notification, no push, nothing stored.
import Combine
import Foundation

@MainActor
final class MidRunNoteCards {
    static let shared = MidRunNoteCards()

    /// How long it stays on top.
    static let lifetime: Duration = .seconds(10)
    /// What a note card's id starts with, after the notices' own.
    static let idPrefix = "note-"

    private var subscriptions = Set<AnyCancellable>()
    private var posted: [String] = []
    private var seen: Set<String> = []

    /// The card for a note: the words in `midRunNote`, the session to open
    /// in the action, and the session's title and project beneath.
    static func notice(for note: MidRunNote, session: SessionStatus) -> LabNotice {
        LabNotice(id: idPrefix + note.id, symbol: "text.bubble", caption: "Claude says", title: note.text,
                  detail: "\(session.displayTitle) · \(session.projectName)", lifetime: lifetime,
                  action: .openSession(session), midRunNote: note)
    }

    /// A note gets a card only where cards do, and where plans, questions and
    /// requests do: the same switch that lets Capsid read the note at all.
    static func mayPost(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: SettingsKey.showCards) && defaults.bool(forKey: SettingsKey.showPlansOnCard)
    }

    /// Starts watching, once.
    func start(model: LabModel = .shared, insights: PanelInsights = .shared, defaults: UserDefaults = .standard) {
        guard subscriptions.isEmpty else { return }
        insights.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notes in self?.offer(notes, to: model, defaults: defaults) }
            .store(in: &subscriptions)
        model.$cards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cards in self?.watch(cards, insights: insights) }
            .store(in: &subscriptions)
    }

    /// Unseen notes, oldest first, each posted once.
    func offer(_ notes: [MidRunNote], to model: LabModel, defaults: UserDefaults = .standard) {
        guard Self.mayPost(defaults: defaults) else { return }
        for note in notes.reversed() where !posted.contains(note.id) {
            guard let session = (model.sessions + model.working + model.waiting).first(where: { $0.id == note.sessionID }) else { continue }
            posted = Array((posted + [note.id]).suffix(200))
            model.post(Self.notice(for: note, session: session))
        }
    }

    /// A note card on top has been shown: its note is seen.
    func watch(_ cards: [LabCard], insights: PanelInsights) {
        guard case .notice(let notice)? = cards.first, let note = notice.midRunNote, seen.insert(note.id).inserted else { return }
        insights.noteSeen(note.id)
    }
}
