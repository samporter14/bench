// FinishingGestures.swift — which finishes get a closing gesture, and what
// became of each (DESIGN.md, "Finishing gestures", since 1.1.0).
//
// `LabModel` tells it of every finish that raised a Finished card for the first
// time, with whether the session's specimen was what the panel was playing. It
// takes what that specimen was doing, there and then (the scene and where in
// its loop), and plans the gesture from that (`FinishingGesture.plan`). The
// plan is kept under the finish's own identity, the one Recent uses
// (`LabEvent.id`: the session and the turn), so:
//   - the same completion told twice is one gesture;
//   - a new turn of the same session finishes again, by itself;
//   - a finish can only ever close the scene of the session it belongs to,
//     because nothing is looked up by "what is showing now".
// The Finished card's well asks for it when it is built (`claim`): the first
// ask decides, for good, whether it plays or the plate does, so a rebuilt view
// or a card that comes back carries on or rests and never plays again.
//
// In memory only, like Recent. Nothing here runs a timer or a task.
import Foundation

@MainActor
final class FinishingGestures {
    static let shared = FinishingGestures()

    /// How many finishes are kept. The oldest go first; a card lives six
    /// seconds, so this is a good many cards more than are ever on screen.
    static let kept = 16

    /// A gesture that has begun: its plan and when.
    struct Run: Equatable {
        let plan: FinishingPlan
        let began: Date
    }

    private enum Fate {
        /// Planned, and its card's well has not asked yet.
        case waiting
        case played(Date)
        /// The well asked when it could not play it (Reduce Motion, a held
        /// still): the plate shows, now and for good.
        case declined
    }

    private var plans: [String: (plan: FinishingPlan, fate: Fate)] = [:]
    /// Oldest first.
    private var order: [String] = []

    // What it asks of the world; the app's answers are the defaults, a test gives its own.
    private let isOn: () -> Bool
    private let rotation: (SessionStatus) -> Rotation
    private let clock: () -> Double
    private let holds: () -> Bool
    private let panelShows: (SessionStatus) -> Bool
    private let poster: (LabScene) -> Double
    /// The time the gesture runs by: the well reads it, and so a capture can
    /// stand still on any moment of it.
    let now: () -> Date

    init(isOn: @escaping () -> Bool = { FinishingGestures.settingIsOn() },
         rotation: @escaping (SessionStatus) -> Rotation = { FinishingGestures.specimen(of: $0) },
         clock: @escaping () -> Double = { Date.timeIntervalSinceReferenceDate },
         holds: @escaping () -> Bool = { SpecimenHold.shared.holds },
         panelShows: @escaping (SessionStatus) -> Bool = { FinishingGestures.panelShowsSpecimen(of: $0) },
         poster: @escaping (LabScene) -> Double = { SpecimenPoster.time(for: $0) },
         now: @escaping () -> Date = { Date() }) {
        self.isOn = isOn
        self.rotation = rotation
        self.clock = clock
        self.holds = holds
        self.panelShows = panelShows
        self.poster = poster
        self.now = now
    }

    // MARK: The app's answers

    /// Settings → Specimens → "Finish with a closing gesture"; on unless switched off.
    static func settingIsOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKey.finishingGesture) as? Bool ?? true
    }

    /// The rotation the session's specimen plays from, as the panel works it out.
    static func specimen(of session: SessionStatus) -> Rotation {
        let matching = UserDefaults.standard.object(forKey: SettingsKey.matchSpecimenToSession) as? Bool ?? true
        return SessionSpecimen.of(session, matching: matching).rotation
    }

    /// Whether the settings and the session's state let the panel play its
    /// specimen: the working panel and the cards are on, and no used-up limit holds it.
    static func panelShowsSpecimen(of session: SessionStatus) -> Bool {
        let defaults = UserDefaults.standard
        return (defaults.object(forKey: SettingsKey.showPanel) as? Bool ?? true)
            && (defaults.object(forKey: SettingsKey.showCards) as? Bool ?? true)
            && UsagePauseModel.shared.pause(for: session.id) == nil
    }

    // MARK: Deciding

    /// Whether the specimen the panel was playing, just before a read, was
    /// `session`'s: it was the head of the working sessions, nothing hid the
    /// panel's working face (a card on top, the user's ×) and the sessions
    /// could be read. A session that was working behind the head, or that a card
    /// covered, had no specimen on show to close.
    static func wasOnShow(_ session: SessionStatus, head: SessionStatus?, hidden: Bool, cardUp: Bool, unreadable: Bool) -> Bool {
        head?.id == session.id && !hidden && !cardUp && !unreadable
    }

    /// The identity of a finish: the one Recent keeps it under.
    static func id(of session: SessionStatus) -> String {
        LabEvent(.finished, session: session).id
    }

    /// A Finished card was raised for `session`, new to the panel. Plans its
    /// closing gesture when everything allows one, and otherwise does nothing:
    /// the plate shows, as it always did.
    func finishRaised(_ session: SessionStatus, onShow: Bool) {
        // A success the daemon says is one: not an error, not a question, not a
        // cancelled or replaced turn, and never a guess from the time it took.
        guard isOn(), onShow, session.state == .finished, session.ending == .completed else { return }
        let id = Self.id(of: session)
        guard plans[id] == nil else { return }
        // Nobody is at the Mac: the well holds a still, and so does the card.
        guard !holds(), panelShows(session) else { return }
        let rotation = rotation(session)
        guard !rotation.scenes.isEmpty else { return }
        let (index, local) = rotation.scene(at: clock())
        let scene = rotation.scenes[index]
        guard let plan = FinishingGesture.plan(for: scene, at: local, poster: poster(scene)) else { return }
        plans[id] = (plan, .waiting)
        order.append(id)
        if order.count > Self.kept { plans.removeValue(forKey: order.removeFirst()) }
    }

    /// The well of `session`'s Finished card asks whether to play a gesture.
    /// The first ask decides: `allowed` is false under Reduce Motion and while
    /// the specimen holds a still, and then it is the plate, for good. Asked
    /// again, it answers as it did, so a rebuilt view carries on from where the
    /// gesture is and a reopened card finds it over.
    func claim(_ session: SessionStatus, allowed: Bool) -> Run? {
        let id = Self.id(of: session)
        guard let entry = plans[id] else { return nil }
        switch entry.fate {
        case .played(let began):
            return Run(plan: entry.plan, began: began)
        case .declined:
            return nil
        case .waiting:
            guard allowed else {
                plans[id]?.fate = .declined
                return nil
            }
            let began = now()
            plans[id]?.fate = .played(began)
            return Run(plan: entry.plan, began: began)
        }
    }

    /// What became of `session`'s finish, for tests.
    enum Standing: Equatable { case none, waiting, played, declined }

    func standing(of session: SessionStatus) -> Standing {
        switch plans[Self.id(of: session)]?.fate {
        case nil: .none
        case .waiting?: .waiting
        case .played?: .played
        case .declined?: .declined
        }
    }

    /// Everything planned and not yet forgotten, for tests.
    var count: Int { plans.count }
}
