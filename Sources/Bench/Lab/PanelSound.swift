// PanelSound.swift — the panel's sounds, in one place (DESIGN.md, Lab, "Sound").
// A question, a plan to approve, a failure and a finish each have a short
// sound of their own, so the kind of thing that happened is known before the
// screen is looked at. One setting still decides whether any play:
// Settings → Alerts → Play a sound (`soundOnNeedsInput`), which now covers a
// finish as well as what asks and what fails.
//
// The sounds are Capsid's own (since 1.0.1): one family of lab glass and metal,
// made with ElevenLabs' sound effects, trimmed under a second and levelled to
// the same loudness, in Resources/Sounds and copied into the app by
// Scripts/build-app.sh. Where the bundle has none (`swift run`, the tests), the
// Mac's own sounds stand in.
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

    /// The file in Resources/Sounds (a .caf), the one place that maps the
    /// event to Capsid's own sound.
    var fileName: String {
        switch self {
        case .question: "question"
        case .plan: "plan"
        case .failure: "failure"
        case .finish: "finish"
        }
    }

    /// Capsid's own sound in a bundle, when it is there.
    func url(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: fileName, withExtension: "caf", subdirectory: "Sounds")
    }

    /// The Mac's sound that stands in where the bundle has none (`NSSound(named:)`).
    var systemName: String {
        switch self {
        case .question: "Glass"
        case .plan: "Submarine"
        case .failure: "Basso"
        case .finish: "Hero"
        }
    }

    /// How loud, from 0 to 1. Capsid's own sounds are levelled alike; a finish
    /// is the one that comes without a session waiting on you, so it is a little
    /// quieter. The Mac's Hero, standing in, is a fanfare: half.
    func volume(own: Bool) -> Float {
        guard self == .finish else { return 1 }
        return own ? 0.8 : 0.5
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
        guard defaults.bool(forKey: SettingsKey.soundOnNeedsInput) else { return }
        let own = sound.url().flatMap { NSSound(contentsOf: $0, byReference: true) }
        guard let player = own ?? NSSound(named: sound.systemName) else { return }
        player.volume = sound.volume(own: own != nil)
        player.play()
    }
}
