// SessionSpecimen.swift — which specimen plays for a session (DESIGN.md,
// "Topic-matched specimens", since 1.0). A session whose title is about
// something a specimen is about (a CRISPRi screen, a gel) plays that specimen,
// and the panel says why. The matching itself is `SpecimenTopics.match`; this
// file wires it to what the user chose, and nothing else.
//
// Every choice the user made still holds, because the matcher is only ever
// offered what already plays: `SceneSettings.rotation` is the categories that
// are on, less the specimens switched off, or the favourites alone, or the one
// from Play Only. A specimen the user switched off can't be picked, and with no
// match, or the setting off, the rotation plays as it always did. The pick is
// the matcher's, seeded by the session's id, so one session keeps its specimen.
// Nothing is stored: not the title, not the match.
import Foundation

struct SessionSpecimen: Equatable {
    /// What plays: the matched specimen alone, else the user's rotation.
    let rotation: Rotation
    /// The specimen was picked for the session's words.
    let picked: Picked?

    struct Picked: Equatable {
        let name: String
        /// What the title is about, in the words the matcher found.
        let topic: String

        /// The panel's quiet line: "CRISPR, picked because the session is about gene editing".
        var caption: String { "\(name), picked because the session is about \(topic)" }
    }

    /// `SpecimenTopics.match`, or a test's own.
    typealias Matcher = (_ title: String, _ sessionID: String, _ candidates: [String]) -> (name: String, topic: String)?

    /// The pure rule. `playing` is the rotation the user's choices leave;
    /// its scenes are the candidates, so nothing the user turned off can win.
    static func resolve(title: String, sessionID: String, playing: Rotation, matching: Bool,
                        match: Matcher = SpecimenTopics.match) -> SessionSpecimen {
        let words = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matching, !words.isEmpty, !playing.scenes.isEmpty,
              let found = match(words, sessionID, playing.distinctNames),
              let scene = playing.scenes.first(where: { $0.name == found.name }) else {
            return SessionSpecimen(rotation: playing, picked: nil)
        }
        return SessionSpecimen(rotation: Rotation([scene]), picked: Picked(name: scene.name, topic: found.topic))
    }

    /// The matcher in use: `SpecimenTopics.match`. A snapshot or a test
    /// swaps its own in and puts this one back.
    @MainActor static var matcher: Matcher = SpecimenTopics.match

    /// The session's specimen under the user's settings now. Asked on every
    /// layout of the panel, so the last answer is kept per session and used
    /// again while the title, the rotation and the setting are as they were.
    @MainActor
    static func of(_ session: SessionStatus, matching: Bool, settings: SceneSettings = .shared) -> SessionSpecimen {
        let playing = settings.rotation
        let key = Key(titleHash: session.title.hashValue, rotation: playing, matching: matching)
        if let kept = memo[session.id], kept.key == key { return kept.value }
        let value = resolve(title: session.title, sessionID: session.id, playing: playing, matching: matching, match: matcher)
        if memo.count >= 32 { memo.removeAll() }
        memo[session.id] = (key, value)
        return value
    }

    /// Forgets the answers kept (a test that swapped the matcher).
    @MainActor static func forget() { memo.removeAll() }

    /// What an answer was made from. The title is kept as a hash, for this
    /// run only, so the memo never holds the words themselves.
    private struct Key: Equatable {
        let titleHash: Int
        let rotation: Rotation
        let matching: Bool
    }

    @MainActor private static var memo: [String: (key: Key, value: SessionSpecimen)] = [:]
}

private extension Rotation {
    /// The names of the scenes, each once, in the order they first play: a
    /// short story can come round more than once, and the matcher is offered
    /// specimens, not slots.
    var distinctNames: [String] {
        var seen = Set<String>()
        return scenes.map(\.name).filter { seen.insert($0).inserted }
    }
}
