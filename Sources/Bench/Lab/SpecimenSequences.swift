// SpecimenSequences.swift — short sequences (DESIGN.md, "Scenes settings",
// "Short sequences", since 1.1.0). A sequence is a title and the names of a
// few specimens in a set order, like a small illustrated story: a flask, a
// stir bar, a crystal coming out of solution. It is metadata and nothing more.
// With "Play short sequences" on, `weave` lays each story into the rotation
// as one run of ordinary scenes, so the rotation stays what it always was, an
// ordered list played by the clock, and every surface (the panel, the menu
// bar, the toolbar, the caption, the field guide) agrees with no timer, no
// renderer and no frame cache of its own.
import Foundation

struct SpecimenSequence: Equatable, Sendable {
    let title: String
    /// Specimen names, in the order they play.
    let members: [String]

    /// The stories there are, in the order they are told. A story whose
    /// specimens are not all in the catalogue (or not all playing) is left out.
    static let curated: [SpecimenSequence] = [
        SpecimenSequence(title: "From solution to crystal", members: ["Flask", "Stir bar", "Nucleation", "Crystal"]),
        SpecimenSequence(title: "A section under the lens", members: ["Microtome ribbon", "Histology slide", "Microscope"]),
        SpecimenSequence(title: "Small worlds", members: ["Microscope", "Diatom", "Slime mold maze"]),
    ]

    /// Fewest standalone specimens between one story and the next, and the
    /// fewest a rotation needs before stories are mixed in at all.
    static let spacing = 6
    /// About one story for this many standalone specimens (a couple of minutes).
    static let every = 20

    /// The rotation's scenes with the stories woven in, and where each sits.
    struct Weave: Sendable {
        struct Block: Sendable {
            let sequence: SpecimenSequence
            /// Where its scenes are in `scenes`, which are its members in order.
            let range: Range<Int>
        }

        let scenes: [LabScene]
        /// In playing order. A story told more than once is in here each time.
        let blocks: [Block]
    }

    /// Which of the sequences can play: every member is among the specimens
    /// that play now (`playing`), so a category that is off, a specimen
    /// switched off or left unstarred keeps its whole story out. Nothing is
    /// switched back on and nothing stands in for a missing member.
    static func eligible(_ sequences: [SpecimenSequence], in playing: [LabScene]) -> [SpecimenSequence] {
        let names = Set(playing.map(\.name))
        return sequences.filter { !$0.members.isEmpty && $0.members.allSatisfy(names.contains) }
    }

    /// The rotation's scenes. `playing` is what plays, in catalogue order and
    /// not yet spread; `sequences` are the stories on offer, in the order they
    /// are told. Nothing is read but the arguments, and the same arguments
    /// give the same list.
    ///
    /// 1. With no eligible story the list is `spread(playing)`: the rotation as
    ///    it ran before there were stories.
    /// 2. The standalone specimens are what plays less the members of the
    ///    eligible stories, spread as ever. A member never plays alone while
    ///    its story can; a specimen of a story that cannot play stays standalone.
    /// 3. Fewer than `spacing` standalone specimens (a tiny rotation, say
    ///    favourites that are exactly one story): the standalone ones, then
    ///    each eligible story once. With none standalone the stories play
    ///    back to back.
    /// 4. Otherwise at most one story fits every `spacing` standalone
    ///    specimens. When that is fewer than the eligible stories, the first
    ///    ones in the order told play and the rest do not this time: their
    ///    members rejoin the standalone ones, which are spread again. This is
    ///    decided once, on the count before they rejoin.
    /// 5. The stories get `max(stories, standalone / every)` places, never more
    ///    than `standalone / spacing`, evenly through the standalone list: a
    ///    story goes before standalone specimen `(2i + 1) × count / (2 × places)`,
    ///    so the gap round the end of the list is as wide as the rest. Place
    ///    `i` tells story `i mod stories`, all its members in one run.
    static func weave(_ playing: [LabScene], sequences: [SpecimenSequence],
                      spread: ([LabScene]) -> [LabScene] = LabScenes.spread) -> Weave {
        var telling = eligible(sequences, in: playing)
        guard !telling.isEmpty else { return Weave(scenes: spread(playing), blocks: []) }
        let byName = Dictionary(playing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        func members(of story: SpecimenSequence) -> [LabScene] { story.members.compactMap { byName[$0] } }
        func standalone(without stories: [SpecimenSequence]) -> [LabScene] {
            let told = Set(stories.flatMap(\.members))
            return playing.filter { !told.contains($0.name) }
        }

        var rest = standalone(without: telling)
        guard rest.count >= spacing else {
            var scenes = spread(rest)
            var blocks: [Weave.Block] = []
            for story in telling {
                let told = members(of: story)
                blocks.append(Weave.Block(sequence: story, range: scenes.count..<(scenes.count + told.count)))
                scenes += told
            }
            return Weave(scenes: scenes, blocks: blocks)
        }
        let room = rest.count / spacing
        if room < telling.count {
            telling = Array(telling.prefix(room))
            rest = standalone(without: telling)
        }
        let alone = spread(rest)
        let places = min(max(telling.count, alone.count / every), alone.count / spacing)
        var scenes: [LabScene] = []
        var blocks: [Weave.Block] = []
        var next = 0
        for place in 0..<places {
            let before = (2 * place + 1) * alone.count / (2 * places)
            scenes += alone[next..<before]
            next = before
            let story = telling[place % telling.count]
            let told = members(of: story)
            blocks.append(Weave.Block(sequence: story, range: scenes.count..<(scenes.count + told.count)))
            scenes += told
        }
        scenes += alone[next...]
        return Weave(scenes: scenes, blocks: blocks)
    }
}
