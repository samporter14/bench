// PanelSound.swift — the panel's sounds, in one place (DESIGN.md, Lab, "Sound").
// A question, a plan to approve, a failure and a finish each have a short
// sound of their own, so the kind of thing that happened is known before the
// screen is looked at. One setting still decides whether any play:
// Settings → Alerts → Play a sound (`soundOnNeedsInput`), which now covers a
// finish as well as what asks and what fails.
//
// The sounds are Capsid's own (since 1.0.1): lab glass and metal, made with
// ElevenLabs' sound effects, trimmed under a second and levelled to the same
// loudness, in Resources/Sounds and copied into the app by
// Scripts/build-app.sh. Since 1.1.3 a second family, Bubbles, is chosen in
// Settings → Alerts → Sounds (`soundFamily`), and a fifth, quieter sound says
// that something you sent landed. Where the bundle has none of a family's
// file, the Glass one plays; where it has neither (`swift run`, the tests),
// the Mac's own sounds stand in.
import AppKit

/// Which family of Capsid's sounds plays (Settings → Alerts → Sounds).
enum SoundFamily: String, CaseIterable, Identifiable, Sendable {
    /// Lab glass and metal, the sounds since 1.0.1.
    case glass
    /// Bubbles in water, the same five moments.
    case bubbles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .bubbles: "Bubbles"
        }
    }

    /// The file's name for `sound` in this family: Glass's is the sound's own
    /// name, the others' carry the family's in front ("bubbles-plan").
    func fileName(_ sound: PanelSound) -> String {
        switch self {
        case .glass: sound.fileName
        case .bubbles: "bubbles-" + sound.fileName
        }
    }

    /// The family the setting names, Glass when it names none Capsid knows.
    static func chosen(_ defaults: UserDefaults = .standard) -> SoundFamily {
        defaults.string(forKey: SettingsKey.soundFamily).flatMap(SoundFamily.init(rawValue:)) ?? .glass
    }
}

enum PanelSound: CaseIterable, Sendable {
    /// A session asks you something, or wants to use a tool.
    case question
    /// A plan is ready to approve.
    case plan
    /// A session stopped with an error.
    case failure
    /// A session finished.
    case finish
    /// Something you sent from Capsid landed: an approval, a reply, a figure
    /// added to the Shelf (since 1.1.3). Never a card's sound.
    case sent

    /// The file in Resources/Sounds (a .caf), the one place that maps the
    /// event to Capsid's own sound.
    var fileName: String {
        switch self {
        case .question: "question"
        case .plan: "plan"
        case .failure: "failure"
        case .finish: "finish"
        case .sent: "sent"
        }
    }

    /// Capsid's own sound in a bundle, when it is there: the family's file,
    /// else the Glass one, else none (and the Mac's sound stands in).
    func url(in bundle: Bundle = .main, family: SoundFamily = .glass) -> URL? {
        let names = family == .glass ? [fileName] : [family.fileName(self), fileName]
        return names.lazy.compactMap { bundle.url(forResource: $0, withExtension: "caf", subdirectory: "Sounds") }.first
    }

    /// The Mac's sound that stands in where the bundle has none (`NSSound(named:)`).
    var systemName: String {
        switch self {
        case .question: "Glass"
        case .plan: "Submarine"
        case .failure: "Basso"
        case .finish: "Hero"
        case .sent: "Tink"
        }
    }

    /// How loud, from 0 to 1. Capsid's own sounds are levelled alike; a finish
    /// is the one that comes without a session waiting on you, so it is a little
    /// quieter. The Mac's Hero, standing in, is a fanfare: half. Sent answers
    /// your own click, so it is the quietest.
    func volume(own: Bool) -> Float {
        switch self {
        case .finish: own ? 0.8 : 0.5
        case .sent: 0.6
        default: 1
        }
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
        case .sent: 4
        }
    }

    /// Plays it, if the setting is on. The setting is read each time, so a
    /// change in Settings is heard at once.
    @MainActor
    static func play(_ sound: PanelSound, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: SettingsKey.soundOnNeedsInput) else { return }
        sound.playNow(family: SoundFamily.chosen(defaults))
    }

    /// The quiet sound of something sent that landed, under the same switch,
    /// and never while Capsid is quiet for a presentation.
    @MainActor
    static func playSent(defaults: UserDefaults = .standard, quiet: Bool = PresentingMode.shared.isQuiet) {
        guard !quiet else { return }
        play(.sent, defaults: defaults)
    }

    /// Settings' preview of a family: its question sound, whatever the switch
    /// says, since the press asked for it.
    @MainActor
    static func preview(_ family: SoundFamily) {
        PanelSound.question.playNow(family: family)
    }

    @MainActor
    private func playNow(family: SoundFamily) {
        let own = url(family: family).flatMap { NSSound(contentsOf: $0, byReference: true) }
        guard let player = own ?? NSSound(named: systemName) else { return }
        player.volume = volume(own: own != nil)
        player.play()
    }
}
