// PanelSound.swift — the panel's sounds, in one place (DESIGN.md, Lab, "Sound").
// A question, a plan to approve, a failure and a finish each have a short
// system sound of their own, so the kind of thing that happened is known
// before the screen is looked at. One setting still decides whether any play:
// Settings → Alerts → Play a sound (`soundOnNeedsInput`), which now covers a
// finish as well as what asks and what fails.
//
// The sounds are placeholders: the Mac's own, picked to be told apart and to
// be quiet enough to hear a hundred times a week.
import AppKit

enum PanelSound: CaseIterable, Sendable {
    /// A session asks you something, or wants to use a tool.
    case question
    /// A plan is ready to approve.
    case plan
    /// A session stopped with an error.
    case failure
    /// A session finished.
    case finish

    /// The system sound's name (`NSSound(named:)`): the one place that maps
    /// the event to the sound.
    var systemName: String {
        switch self {
        case .question: "Glass"
        case .plan: "Submarine"
        case .failure: "Basso"
        case .finish: "Hero"
        }
    }

    /// How loud, from 0 to 1. A finish is the one sound that comes without a
    /// session waiting on you, and Hero is a fanfare: it plays at half.
    var volume: Float {
        self == .finish ? 0.5 : 1
    }

    /// The sound a card makes when it comes, or none: only the cards about a
    /// session (it asks, it failed, it finished) have one. A question waits
    /// for a reply; a plan, for its approval; any other request is a question.
    static func sound(for card: LabCard) -> PanelSound? {
        switch card {
        case .needsInput(let session): session.waitingReason == .plan ? .plan : .question
        case .failed: .failure
        case .finished: .finish
        case .web, .saved, .notice: nil
        }
    }

    /// Which of several sounds one read plays: just one, the most urgent.
    /// What asks comes first, then what failed, then what finished.
    static func loudest(_ sounds: [PanelSound]) -> PanelSound? {
        sounds.min { $0.urgency < $1.urgency }
    }

    private var urgency: Int {
        switch self {
        case .question: 0
        case .plan: 1
        case .failure: 2
        case .finish: 3
        }
    }

    /// Plays it, if the setting is on. The setting is read each time, so a
    /// change in Settings is heard at once.
    @MainActor
    static func play(_ sound: PanelSound, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: SettingsKey.soundOnNeedsInput), let named = NSSound(named: sound.systemName) else { return }
        named.volume = sound.volume
        named.play()
    }
}
