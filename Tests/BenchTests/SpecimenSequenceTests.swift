// SpecimenSequenceTests.swift — short sequences (DESIGN.md, "Scenes settings",
// "Short sequences"): which stories are eligible, how many are woven in and
// where, that a story is one run of ordinary scenes the clock plays, that the
// choices the user made all still hold, and the setting itself. The stories
// and most scenes here are made up, so none of it depends on which specimens
// the catalogue has; the few checks on the real catalogue read their names
// from it. No window, no timer, no frame is drawn.
import Foundation
import SwiftUI
import Testing
@testable import Bench

// MARK: - Made-up scenes and stories

private func scene(_ name: String, _ theme: LabScene.Theme = .bench, _ duration: Double = 3) -> LabScene {
    LabScene(name: name, theme: theme, duration: duration) { _, _, _, _ in }
}

private func names(_ scenes: [LabScene]) -> [String] { scenes.map(\.name) }

/// The rotation as it ran before there were stories, made here from the
/// catalogue and the spread, not by asking the code under test.
private func todays(_ choice: SpecimenChoice, favorites: Set<String> = [], only: Bool = false) -> [String] {
    let starred = only ? LabScenes.catalogue.filter { favorites.contains($0.name) } : []
    return names(LabScenes.spread(starred.isEmpty ? LabScenes.catalogue.filter(choice.isOn) : starred))
}

/// Standalone scenes S01, S02, … across several themes, 3 s each.
private func standalone(_ count: Int) -> [LabScene] {
    let themes: [LabScene.Theme] = [.bench, .cell, .chemistry, .data, .physics, .plants, .space]
    return (0..<count).map { scene(String(format: "S%02d", $0 + 1), themes[$0 % themes.count]) }
}

/// A made-up story: its members drawn with the given durations.
private func story(_ title: String, _ members: [String]) -> SpecimenSequence {
    SpecimenSequence(title: title, members: members)
}

private let storyA = story("Story A", ["A1", "A2", "A3", "A4"])
private let storyB = story("Story B", ["B1", "B2", "M"])
/// Shares "M" with B, as two curated stories share a specimen.
private let storyC = story("Story C", ["M", "C2", "C3"])

/// The members of the stories as scenes, once each, with different durations
/// so a boundary at the wrong place shows.
private func members(of stories: [SpecimenSequence]) -> [LabScene] {
    var seen = Set<String>()
    var made: [LabScene] = []
    for (k, name) in stories.flatMap(\.members).enumerated() where seen.insert(name).inserted {
        made.append(scene(name, .molecular, Double(2 + k % 4)))
    }
    return made
}

/// What plays: `count` standalone scenes and the members of `stories`.
private func playing(_ count: Int, _ stories: [SpecimenSequence]) -> [LabScene] {
    standalone(count) + members(of: stories)
}

private let identity: @Sendable ([LabScene]) -> [LabScene] = { $0 }

/// How many standalone scenes sit between one block and the next, round the
/// loop, counting the stretch that runs over the end of the list.
private func gaps(_ weave: SpecimenSequence.Weave) -> [Int] {
    let blocks = weave.blocks.map(\.range)
    return blocks.enumerated().map { k, block in
        let after = blocks[(k + 1) % blocks.count]
        return k + 1 < blocks.count
            ? after.lowerBound - block.upperBound
            : weave.scenes.count - block.upperBound + after.lowerBound
    }
}

// MARK: - Which stories can play

struct SpecimenSequenceEligibilityTests {
    @Test func aStoryNeedsEveryMemberToPlay() {
        let all = playing(10, [storyA])
        #expect(SpecimenSequence.eligible([storyA], in: all) == [storyA])
        for missing in storyA.members {
            let without = all.filter { $0.name != missing }
            #expect(SpecimenSequence.eligible([storyA], in: without).isEmpty, "without \(missing)")
        }
    }

    @Test func storiesKeepTheOrderTheyAreTold() {
        let all = playing(10, [storyA, storyB, storyC])
        #expect(SpecimenSequence.eligible([storyA, storyB, storyC], in: all) == [storyA, storyB, storyC])
        #expect(SpecimenSequence.eligible([storyC, storyA], in: all) == [storyC, storyA])
        // One member out keeps out every story that has it.
        let withoutM = all.filter { $0.name != "M" }
        #expect(SpecimenSequence.eligible([storyA, storyB, storyC], in: withoutM) == [storyA])
    }

    @Test func aStoryWithNoMembersNeverPlays() {
        #expect(SpecimenSequence.eligible([story("Empty", [])], in: standalone(10)).isEmpty)
    }

    @Test func aMemberNotInTheCatalogueKeepsItsStoryOut() {
        let everything = LabScenes.catalogue
        #expect(SpecimenSequence.eligible([story("Ghost", [everything[0].name, "Not a specimen"])], in: everything).isEmpty)
        #expect(SpecimenSequence.eligible([story("Real", [everything[0].name, everything[1].name])], in: everything).count == 1)
    }
}

// MARK: - The weave

struct SpecimenSequenceWeaveTests {
    @Test func withNoEligibleStoryTheListIsTheSpreadOneAsItAlwaysWas() {
        let missingOne = standalone(30) + members(of: [storyA]).dropLast()
        for sequences in [[], [storyA]] {
            let woven = SpecimenSequence.weave(missingOne, sequences: sequences)
            #expect(names(woven.scenes) == names(LabScenes.spread(missingOne)))
            #expect(woven.blocks.isEmpty)
        }
    }

    @Test func aStoryIsOneRunOfItsMembersInOrder() {
        let woven = SpecimenSequence.weave(playing(40, [storyA]), sequences: [storyA], spread: identity)
        #expect(woven.blocks.count == 2)
        for block in woven.blocks {
            #expect(block.sequence == storyA)
            #expect(names(Array(woven.scenes[block.range])) == ["A1", "A2", "A3", "A4"])
        }
        // And nothing else is in the run: it is bounded by standalone scenes.
        for block in woven.blocks {
            #expect(woven.scenes[block.range.lowerBound - 1].name.hasPrefix("S"))
            #expect(woven.scenes[block.range.upperBound].name.hasPrefix("S"))
        }
    }

    @Test func aMemberNeverPlaysAloneWhileItsStoryCan() {
        let woven = SpecimenSequence.weave(playing(40, [storyA, storyB, storyC]), sequences: [storyA, storyB, storyC])
        let inBlocks = Set(woven.blocks.flatMap { Array($0.range) })
        for (index, played) in woven.scenes.enumerated() where !inBlocks.contains(index) {
            #expect(!["A1", "A2", "A3", "A4", "B1", "B2", "M", "C2", "C3"].contains(played.name), "\(played.name) alone")
        }
        // Every standalone scene plays exactly once a round.
        for plain in standalone(40) {
            #expect(woven.scenes.filter { $0.name == plain.name }.count == 1, "\(plain.name)")
        }
    }

    @Test func theStandaloneScenesKeepTheSpreadOrder() {
        // The real spread, over made-up scenes of several themes: take the
        // blocks out and what is left is the spread of the rest, untouched.
        let stories = [storyA, storyB]
        let all = playing(40, stories)
        let woven = SpecimenSequence.weave(all, sequences: stories)
        let inBlocks = Set(woven.blocks.flatMap { Array($0.range) })
        let alone = woven.scenes.enumerated().filter { !inBlocks.contains($0.offset) }.map(\.element)
        #expect(names(alone) == names(LabScenes.spread(standalone(40))))
    }

    @Test func aStoryWhoseMemberIsMissingStaysOutWholeAndItsOthersStayStandalone() {
        let all = playing(40, [storyA, storyB]).filter { $0.name != "B2" }
        let woven = SpecimenSequence.weave(all, sequences: [storyA, storyB])
        #expect(woven.blocks.allSatisfy { $0.sequence == storyA })
        // B1 and M have no story to play in, so each plays alone, once.
        for name in ["B1", "M"] {
            #expect(woven.scenes.filter { $0.name == name }.count == 1, "\(name)")
        }
        #expect(!woven.scenes.contains { $0.name == "B2" })
    }

    @Test func aSharedMemberPlaysOnlyInsideItsStories() {
        let woven = SpecimenSequence.weave(playing(40, [storyB, storyC]), sequences: [storyB, storyC], spread: identity)
        let inBlocks = Set(woven.blocks.flatMap { Array($0.range) })
        for (index, played) in woven.scenes.enumerated() where played.name == "M" {
            #expect(inBlocks.contains(index))
        }
    }

    @Test func theSameInputsGiveTheSameList() {
        let all = playing(40, [storyA, storyB, storyC])
        let first = SpecimenSequence.weave(all, sequences: [storyA, storyB, storyC])
        let second = SpecimenSequence.weave(all, sequences: [storyA, storyB, storyC])
        #expect(names(first.scenes) == names(second.scenes))
        #expect(first.blocks.map(\.range) == second.blocks.map(\.range))
    }

    // MARK: How many, and where

    /// One story: slots and positions for the standalone counts the handoff
    /// names. A block goes before standalone scene (2i + 1) × S / 2m.
    @Test(arguments: [
        (standalone: 0, places: [0]),
        (standalone: 3, places: [3]),
        (standalone: 6, places: [3]),
        (standalone: 12, places: [6]),
        (standalone: 40, places: [10, 30]),
    ])
    func oneStoryIsPlacedAsTheCadenceSays(standalone count: Int, places: [Int]) {
        let woven = SpecimenSequence.weave(playing(count, [storyA]), sequences: [storyA], spread: identity)
        #expect(woven.blocks.count == places.count)
        #expect(woven.scenes.count == count + 4 * places.count)
        // Each block starts after the standalone scenes before it and the
        // members of the blocks before that.
        for (k, place) in places.enumerated() {
            #expect(woven.blocks[k].range.lowerBound == place + 4 * k, "block \(k)")
        }
        // The standalone scenes are all there, once, in the order given.
        #expect(names(woven.scenes.filter { $0.name.hasPrefix("S") }) == (0..<count).map { String(format: "S%02d", $0 + 1) })
    }

    /// Three stories sharing a specimen (nine different members).
    @Test func severalStoriesAreFittedToTheStandaloneCount() {
        let stories = [storyA, storyB, storyC]
        func woven(_ count: Int) -> SpecimenSequence.Weave {
            SpecimenSequence.weave(playing(count, stories), sequences: stories, spread: identity)
        }
        // Nothing standalone: the stories back to back, in the order told.
        let none = woven(0)
        #expect(names(none.scenes) == ["A1", "A2", "A3", "A4", "B1", "B2", "M", "M", "C2", "C3"])
        #expect(none.blocks.map(\.sequence) == stories)
        // Fewer than six: the standalone ones, then each story once.
        let few = woven(3)
        #expect(names(few.scenes) == ["S01", "S02", "S03", "A1", "A2", "A3", "A4", "B1", "B2", "M", "M", "C2", "C3"])
        #expect(few.blocks.map(\.range.lowerBound) == [3, 7, 10])
        // Six: room for one story, the first in the order told. B and C do
        // not play this time, so their members play alone and are spread in.
        let six = woven(6)
        #expect(six.blocks.map(\.sequence) == [storyA])
        #expect(six.scenes.count == 6 + 5 + 4)
        for name in ["B1", "B2", "M", "C2", "C3"] {
            #expect(six.scenes.filter { $0.name == name }.count == 1, "\(name)")
        }
        #expect(six.blocks[0].range.lowerBound == 5, "(2 × 0 + 1) × 11 / 2")
        // Twelve: room for two. C's own two members rejoin; M stays with B.
        let twelve = woven(12)
        #expect(twelve.blocks.map(\.sequence) == [storyA, storyB])
        #expect(twelve.scenes.count == 12 + 2 + 4 + 3)
        #expect(twelve.scenes.filter { $0.name == "M" }.count == 1, "only inside B")
        #expect(twelve.scenes.filter { $0.name == "C2" }.count == 1)
        #expect(twelve.blocks.map(\.range.lowerBound) == [3, 10 + 4], "before standalone 3 and 10 of 14")
        // Forty: all three, twice-and-a-bit rounds of the standalone scenes.
        let forty = woven(40)
        #expect(forty.blocks.map(\.sequence) == stories)
        #expect(forty.blocks.map(\.range.lowerBound) == [6, 20 + 4, 33 + 4 + 3])
    }

    @Test func aStoryComesRoundInTheOrderTold() {
        // Many places, three stories: place i tells story i mod 3.
        let stories = [storyA, storyB, storyC]
        let woven = SpecimenSequence.weave(playing(300, stories), sequences: stories)
        #expect(woven.blocks.count == 15, "300 / 20")
        for (k, block) in woven.blocks.enumerated() {
            #expect(block.sequence == stories[k % 3], "place \(k)")
            #expect(names(Array(woven.scenes[block.range])) == block.sequence.members)
        }
    }

    @Test(arguments: [6, 7, 12, 19, 20, 40, 41, 100, 537, 1000])
    func storiesAreNeverCloserThanSixStandaloneScenesAndAreEvenlySpread(count: Int) {
        for stories in [[storyA], [storyA, storyB, storyC]] {
            let woven = SpecimenSequence.weave(playing(count, stories), sequences: stories, spread: identity)
            let between = gaps(woven)
            #expect(!between.isEmpty)
            #expect(between.min()! >= SpecimenSequence.spacing, "\(count) with \(stories.count): \(between)")
            // Even to within one scene.
            #expect(between.max()! - between.min()! <= 1, "\(count) with \(stories.count): \(between)")
            // About one story for every twenty standalone scenes (at least one
            // for each that plays), never more than one for every six.
            let told = Set(woven.blocks.map(\.sequence.title)).count
            let alone = woven.scenes.count - woven.blocks.map(\.range.count).reduce(0, +)
            #expect(woven.blocks.count == min(max(told, alone / SpecimenSequence.every), alone / SpecimenSequence.spacing),
                    "\(count) with \(stories.count)")
        }
    }

    @Test func theRealCatalogueGetsOneStoryAboutEveryTwentyScenes() {
        let all = LabScenes.catalogue
        let tale = story("Real", Array(all.prefix(4).map(\.name)))
        let woven = SpecimenSequence.weave(all, sequences: [tale])
        let alone = all.count - 4
        #expect(woven.blocks.count == alone / 20)
        // The story's four specimens play once for each block, and nothing else repeats.
        #expect(woven.scenes.count == all.count + 4 * (woven.blocks.count - 1))
        #expect(gaps(woven).min()! >= SpecimenSequence.spacing)
        #expect(gaps(woven).max()! - gaps(woven).min()! <= 1)
    }

    @Test func cadenceHoldsWithTheRealSpreadAndEveryStory() {
        let stories = [storyA, storyB, storyC]
        let woven = SpecimenSequence.weave(playing(200, stories), sequences: stories)
        #expect(woven.blocks.count == 10)
        #expect(gaps(woven).min()! >= SpecimenSequence.spacing)
    }
}

// MARK: - Played by the clock

@MainActor
struct SpecimenSequencePlaybackTests {
    /// A rotation of 40 standalone scenes (3 s) with story A woven in twice.
    private static func rotation() -> (Rotation, SpecimenSequence.Weave) {
        let woven = SpecimenSequence.weave(playing(40, [storyA]), sequences: [storyA], spread: identity)
        return (Rotation(woven.scenes), woven)
    }

    /// When scene `index` begins, in seconds on the rotation's clock.
    private static func start(of index: Int, in rotation: Rotation) -> Double {
        rotation.scenes.prefix(index).reduce(0) { $0 + $1.duration }
    }

    @Test func eachMemberPlaysInOrderWithItsOwnLocalTime() throws {
        let (rotation, woven) = Self.rotation()
        for block in woven.blocks {
            for index in block.range {
                let begins = Self.start(of: index, in: rotation)
                let duration = rotation.scenes[index].duration
                #expect(rotation.scene(at: begins) == (index, 0))
                #expect(rotation.scene(at: begins + 0.25) == (index, 0.25))
                #expect(rotation.scene(at: begins + duration - 0.25) == (index, duration - 0.25))
                // The instant the scene ends, the next begins: no scene runs on, none is skipped.
                let next = (index + 1) % rotation.scenes.count
                #expect(rotation.scene(at: begins + duration) == (next, 0))
            }
        }
    }

    @Test func aStoryRunsStraightThroughIts() throws {
        let (rotation, woven) = Self.rotation()
        let block = try #require(woven.blocks.first)
        var t = Self.start(of: block.range.lowerBound, in: rotation)
        var played: [String] = []
        while t < Self.start(of: block.range.upperBound, in: rotation) {
            let (index, local) = rotation.scene(at: t)
            played.append(rotation.scenes[index].name)
            #expect(local == 0)
            t += rotation.scenes[index].duration
        }
        #expect(played == ["A1", "A2", "A3", "A4"])
    }

    @Test func theClockWrapsRoundTheListAndSoDoesALargeOne() {
        let (rotation, _) = Self.rotation()
        let cycle = rotation.cycle
        #expect(cycle == rotation.scenes.reduce(0) { $0 + $1.duration })
        for t in [0.0, 0.25, 7.5, 43.0, 61.25, cycle - 0.25] {
            let here = rotation.scene(at: t)
            for rounds in [-3.0, 1, 2, 1_000, 1_000_000, 1e9] {
                // Whole rounds of an integer cycle are exact in a double.
                let there = rotation.scene(at: t + rounds * cycle)
                #expect(there.index == here.index, "t \(t) + \(rounds) rounds")
                #expect(there.local == here.local, "t \(t) + \(rounds) rounds")
            }
        }
        // The first instant of the next round is the first scene again.
        #expect(rotation.scene(at: cycle) == (0, 0))
        #expect(rotation.scene(at: -0.25) == (rotation.scenes.count - 1, rotation.scenes.last!.duration - 0.25))
    }

    @Test func aClockOfTodayAndOneImmenselyLargeAgreeWithPlainArithmetic() {
        let (rotation, _) = Self.rotation()
        let cycle = Int(rotation.cycle)
        for t in [812_345_678.0, 1e12 + 0.25, 3e15, -9e11] {
            let (index, local) = rotation.scene(at: t)
            // Whole seconds and a quarter: exact, so the integers decide.
            var remainder = (Int(t.rounded(.down)) % cycle + cycle) % cycle
            var expected = 0
            while remainder >= Int(rotation.scenes[expected].duration) {
                remainder -= Int(rotation.scenes[expected].duration)
                expected += 1
            }
            #expect(index == expected, "t \(t)")
            #expect(abs(local - (Double(remainder) + (t - t.rounded(.down)))) < 1e-9, "t \(t)")
        }
    }

    @Test func twoSurfacesAskingAtTheSameMomentAreTold() {
        let (rotation, woven) = Self.rotation()
        // Another surface built the same rotation on its own.
        let other = Rotation(SpecimenSequence.weave(playing(40, [storyA]), sequences: [storyA], spread: identity).scenes)
        #expect(rotation == other)
        let hold = SpecimenHold(secondsSinceInput: { 0 }, limit: { 600 }, lowPower: { false }, now: { 0 },
                                wait: { _ in await Task.yield() }, center: NotificationCenter())
        for k in 0..<2_000 {
            let t = Double(k) * 0.7 + 0.1
            let a = rotation.scene(at: t)
            let b = other.scene(at: t)
            #expect(a == b)
            // The panel's well and caption ask the hold for the scene.
            #expect(hold.scene(in: rotation, at: Date(timeIntervalSinceReferenceDate: t)).name == rotation.scenes[a.index].name)
        }
        #expect(!woven.blocks.isEmpty)
    }

    @Test func aHoldMidStoryHoldsAndNamesThatMember() throws {
        let (rotation, woven) = Self.rotation()
        let block = try #require(woven.blocks.first)
        let middle = block.range.lowerBound + 1
        var clock = Self.start(of: middle, in: rotation) + 1
        let hold = SpecimenHold(secondsSinceInput: { 3_600 }, limit: { 600 }, lowPower: { false }, now: { clock },
                                wait: { _ in await Task.yield() }, center: NotificationCenter())
        hold.look()
        #expect(hold.holds)
        // Whatever the date, the still and its name are the member the hold began in.
        clock += 500
        for later in [0.0, 100, 1e9] {
            #expect(hold.scene(in: rotation, at: Date(timeIntervalSinceReferenceDate: later)).name == "A2")
        }
    }

    @Test func theCaptionTicksOnceAMemberAndNamesTheOneNowPlaying() throws {
        let (rotation, woven) = Self.rotation()
        let block = try #require(woven.blocks.first)
        let begins = Self.start(of: block.range.lowerBound, in: rotation)
        var entries = SceneBoundarySchedule(rotation: rotation)
            .entries(from: Date(timeIntervalSinceReferenceDate: begins), mode: .normal)
        var dates: [Double] = []
        var named: [String] = []
        for _ in 0...block.range.count {
            let date = entries.next()!.timeIntervalSinceReferenceDate
            dates.append(date)
            named.append(rotation.scenes[rotation.scene(at: date).index].name)
        }
        // One tick for each member and one for the scene after the story:
        // the line changes once at each boundary and in between it is asleep.
        #expect(Array(named.dropLast()) == ["A1", "A2", "A3", "A4"])
        #expect(named.last?.hasPrefix("S") == true)
        let durations = block.range.map { rotation.scenes[$0].duration }
        for (k, duration) in durations.enumerated() {
            #expect(abs(dates[k + 1] - dates[k] - duration) < 0.02, "tick \(k)")
        }
    }

    @Test func aRotationWithRepeatedNamesIsEqualToItselfAndToNothingElse() {
        let (rotation, _) = Self.rotation()
        #expect(rotation.scenes.filter { $0.name == "A1" }.count == 2, "a story can come round twice")
        #expect(rotation == rotation)
        #expect(rotation != Rotation(rotation.scenes.filter { !$0.name.hasPrefix("A") }))
        #expect(rotation != Rotation(Array(rotation.scenes.reversed())))
        // A different place for the story is a different rotation.
        var moved = rotation.scenes
        let at = moved.firstIndex { $0.name == "A1" }!
        moved.swapAt(at, at - 1)
        #expect(rotation != Rotation(moved))
    }

    @Test func cacheBoundsDoNotGrowWithTheLengthOfAStory() throws {
        // A story of sixty members, each as long as a long scene: a plan
        // still hands out chunks of at most a second, from the scene it is in.
        let long = story("Long", (1...60).map { "L\($0)" })
        let woven = SpecimenSequence.weave(playing(40, [long]), sequences: [long], spread: identity)
        let rotation = Rotation(woven.scenes)
        let block = try #require(woven.blocks.first)
        var plan = PlaybackPlan(sceneDurations: rotation.scenes.map(\.duration), fps: 30,
                                scene: block.range.lowerBound, sceneStart: 0, now: 0)
        var chunks: [PlaybackChunk] = []
        for _ in 0..<2_000 { chunks.append(plan.next()) }
        #expect(chunks.allSatisfy { $0.frames.count <= 30 && $0.duration <= 1.0 + 1e-9 })
        #expect(chunks.map(\.scene).contains(block.range.upperBound - 1))
    }
}

// MARK: - What the user chose still holds

struct SpecimenSequenceChoiceTests {
    /// Two lab specimens and two chemistry ones, read from the catalogue by
    /// category so that the test survives a rename.
    fileprivate static let members: [String] = {
        let lab = LabScenes.catalogue.filter { $0.theme.group == .lab }.prefix(2).map(\.name)
        let chemistry = LabScenes.catalogue.filter { $0.theme.group == .chemistry }.prefix(2).map(\.name)
        return lab + chemistry
    }()
    fileprivate static let tale = story("Test story", members)

    private static func scene(_ name: String) -> LabScene { LabScenes.catalogue.first { $0.name == name }! }

    private func rotation(_ choice: SpecimenChoice, favorites: Set<String> = [], only: Bool = false,
                          sequences: [SpecimenSequence] = [tale]) -> Rotation {
        choice.rotation(favorites: favorites, onlyFavorites: only, sequences: sequences)
    }

    /// Whether the test story plays, whole and in order, anywhere in the list.
    private func plays(_ rotation: Rotation) -> Bool {
        let list = names(rotation.scenes)
        let n = Self.members.count
        return list.indices.contains { $0 + n <= list.count && Array(list[$0..<($0 + n)]) == Self.members }
    }

    @Test func theMembersAreFourDifferentSpecimens() {
        #expect(Set(Self.members).count == 4)
    }

    @Test func withTheSettingOffTheRotationIsTodaysForEveryChoice() {
        var choices: [(String, SpecimenChoice, Set<String>, Bool)] = [("all on", .all, [], false)]
        var noChemistry = SpecimenChoice.all
        noChemistry.set(.chemistry, on: false)
        choices.append(("a category off", noChemistry, [], false))
        var hiddenOne = SpecimenChoice.all
        hiddenOne.toggle(Self.scene(Self.members[1]))
        choices.append(("one off", hiddenOne, [], false))
        choices.append(("favourites", .all, Set(Self.members + ["Gel", "Pipette"]), true))
        for (what, choice, favorites, only) in choices {
            let off = choice.rotation(favorites: favorites, onlyFavorites: only, sequences: [])
            #expect(names(off.scenes) == todays(choice, favorites: favorites, only: only), "\(what)")
            // And the call every surface made before there were stories.
            #expect(off == choice.rotation(favorites: favorites, onlyFavorites: only), "\(what)")
        }
        // And the full rotation, exactly.
        #expect(names(SpecimenChoice.all.rotation(favorites: [], onlyFavorites: false, sequences: []).scenes) == names(LabScenes.all))
        #expect(SpecimenChoice.all.rotation(favorites: [], onlyFavorites: false, sequences: []) == .full)
    }

    @Test func withTheSettingOnEverythingOnPlaysTheStoryAndEverySpecimen() {
        let on = rotation(.all)
        #expect(plays(on))
        // Every specimen plays, and a member only inside its story.
        #expect(Set(names(on.scenes)) == Set(names(LabScenes.all)))
        let runs = names(on.scenes).filter { Self.members.contains($0) }.count
        #expect(runs % Self.members.count == 0 && runs > 0)
        #expect(on != .full)
    }

    @Test func aStoryWithNoMatchInTheCatalogueLeavesTheRotationAlone() {
        let ghost = story("Ghost", [Self.members[0], "Not a specimen"])
        #expect(rotation(.all, sequences: [ghost]) == .full)
        #expect(rotation(.all, sequences: [ghost, story("Empty", [])]) == .full)
    }

    @Test func aCategoryThatIsOffKeepsTheWholeStoryOut() {
        var choice = SpecimenChoice.all
        choice.set(.chemistry, on: false)
        let before = choice
        let woven = rotation(choice)
        #expect(!plays(woven))
        #expect(names(woven.scenes) == todays(choice))
        // The members that are on play alone, once; nothing was switched on.
        for name in Self.members.prefix(2) { #expect(names(woven.scenes).filter { $0 == name }.count == 1, "\(name)") }
        for name in Self.members.suffix(2) { #expect(!names(woven.scenes).contains(name), "\(name)") }
        #expect(choice == before)
        #expect(!choice.groups.contains(.chemistry))
    }

    @Test func aSpecimenSwitchedOffKeepsTheWholeStoryOutAndOthersStayStandalone() {
        for hidden in Self.members {
            var choice = SpecimenChoice.all
            choice.toggle(Self.scene(hidden))
            let before = choice
            let woven = rotation(choice)
            #expect(!plays(woven), "without \(hidden)")
            #expect(names(woven.scenes) == todays(choice), "without \(hidden)")
            #expect(!names(woven.scenes).contains(hidden))
            for other in Self.members where other != hidden {
                #expect(names(woven.scenes).filter { $0 == other }.count == 1, "\(other) plays alone")
            }
            #expect(choice == before && !choice.isOn(Self.scene(hidden)))
        }
    }

    @Test func onlyFavoritesPlaysAStoryOnlyIfEveryMemberIsAFavorite() {
        let extra = LabScenes.catalogue.filter { !Self.members.contains($0.name) }.prefix(12).map(\.name)
        // Every member among the favourites: the story plays, even with chemistry off.
        var choice = SpecimenChoice.all
        choice.set(.chemistry, on: false)
        let all = Set(Self.members + extra)
        let with = rotation(choice, favorites: all, only: true)
        #expect(plays(with))
        #expect(Set(names(with.scenes)) == all)
        // One short: no story, and the favourites play as they did.
        let short = Set(Self.members.dropLast() + extra)
        let without = rotation(choice, favorites: short, only: true)
        #expect(!plays(without))
        #expect(names(without.scenes) == todays(choice, favorites: short, only: true))
        #expect(Set(names(without.scenes)) == short)
    }

    @Test func aRotationOfExactlyOneStoryPlaysItInOrder() {
        let only = Set(Self.members)
        let woven = rotation(.all, favorites: only, only: true)
        #expect(names(woven.scenes) == Self.members)
    }

    @Test func aTinyRotationPlaysItsSpecimensThenTheStory() {
        let alone = Array(LabScenes.catalogue.filter { !Self.members.contains($0.name) }.prefix(3).map(\.name))
        let woven = rotation(.all, favorites: Set(Self.members + alone), only: true)
        #expect(Array(names(woven.scenes).suffix(4)) == Self.members)
        #expect(Set(names(woven.scenes).prefix(3)) == Set(alone))
    }

    @Test func playOnlyStaysThatOneSpecimen() {
        for member in Self.members {
            var choice = SpecimenChoice.all
            choice.playOnly(Self.scene(member))
            #expect(names(rotation(choice).scenes) == [member], "play only \(member)")
            // And with a story of three, or of two, around it.
            let stories = [Self.tale, story("Three", Array(Self.members.prefix(3))), story("Two", Array(Self.members.prefix(2))),
                           story("One", [member])]
            for stories in stories.map({ [$0] }) {
                #expect(names(rotation(choice, sequences: stories).scenes) == [member])
            }
        }
        #expect(SpecimenChoice.all.onCount > 1)
        var choice = SpecimenChoice.all
        choice.playOnly(Self.scene(Self.members[0]))
        #expect(choice.onCount == 1)
    }

    @Test func aTopicMatchedSessionStillPlaysItsOneSpecimen() throws {
        let woven = rotation(.all)
        #expect(woven.scenes.count > LabScenes.all.count, "the story comes round more than once")
        let heard = Heard(answer: (name: Self.members[1], topic: "a topic"))
        let result = SessionSpecimen.resolve(title: "Anything", sessionID: "s", playing: woven, matching: true, match: heard.match)
        #expect(names(result.rotation.scenes) == [Self.members[1]])
        #expect(result.picked?.name == Self.members[1])
        // What the matcher was offered: each specimen once, a story's slots not counted.
        let offered = try #require(heard.candidates.first)
        #expect(offered.count == Set(offered).count)
        #expect(Set(offered) == Set(names(LabScenes.all)))
        // No match: the woven rotation, story and all.
        let none = SessionSpecimen.resolve(title: "Anything", sessionID: "s", playing: woven, matching: true, match: Heard(answer: nil).match)
        #expect(none.rotation == woven && none.picked == nil)
    }

    @Test func aTopicMatchCanNotPickAMemberOfAStoryThatIsOut() {
        var choice = SpecimenChoice.all
        choice.toggle(Self.scene(Self.members[2]))
        let woven = rotation(choice)
        let heard = Heard(answer: (name: Self.members[2], topic: "a topic"))
        let result = SessionSpecimen.resolve(title: "Anything", sessionID: "s", playing: woven, matching: true, match: heard.match)
        #expect(result.picked == nil)
        #expect(!(heard.candidates.first ?? []).contains(Self.members[2]))
    }

    /// A matcher that records what it was offered.
    final class Heard: @unchecked Sendable {
        var candidates: [[String]] = []
        let answer: (name: String, topic: String)?
        init(answer: (name: String, topic: String)?) { self.answer = answer }
        func match(_ title: String, _ id: String, _ names: [String]) -> (name: String, topic: String)? {
            candidates.append(names)
            return answer
        }
    }
}

// MARK: - The setting

@MainActor
struct SpecimenSequenceSettingTests {
    private static let tale = SpecimenSequenceChoiceTests.tale
    private static let members = SpecimenSequenceChoiceTests.members
    private static let stranger = LabScenes.catalogue.first { !SpecimenSequenceChoiceTests.members.contains($0.name) }!

    private func settings(_ scratch: ScratchDefaults) -> SceneSettings {
        SceneSettings(defaults: scratch.defaults, stories: [Self.tale])
    }

    private func plays(_ rotation: Rotation) -> Bool {
        names(rotation.scenes).count > LabScenes.all.count
    }

    @Test func itIsOffUntilAskedFor() {
        let scratch = ScratchDefaults.make(prefix: "sequences-default")
        defer { scratch.discard() }
        let sceneSettings = settings(scratch)
        #expect(!sceneSettings.playSequences)
        #expect(sceneSettings.rotation == .full)
        #expect(scratch.defaults.object(forKey: "playShortSequences") == nil)
    }

    @Test func itIsKeptWithTheOtherSceneChoices() {
        let scratch = ScratchDefaults.make(prefix: "sequences-kept")
        defer { scratch.discard() }
        let first = settings(scratch)
        first.playSequences = true
        #expect(scratch.defaults.bool(forKey: "playShortSequences"))
        // Another run reads it back.
        let second = settings(scratch)
        #expect(second.playSequences)
        #expect(second.rotation == first.rotation)
        second.playSequences = false
        #expect(!settings(scratch).playSequences)
    }

    @Test func aChangeRebuildsTheRotationAtOnceForEveryReader() {
        let scratch = ScratchDefaults.make(prefix: "sequences-change")
        defer { scratch.discard() }
        let sceneSettings = settings(scratch)
        let off = sceneSettings.rotation
        // Read again: kept, the same list.
        #expect(sceneSettings.rotation == off)
        sceneSettings.playSequences = true
        let on = sceneSettings.rotation
        #expect(on != off)
        #expect(plays(on))
        // Whoever else asks, the session's panel included, is told the same.
        let session = Fixture.session("sequences-change", .running, title: "Quarterly review")
        #expect(SessionSpecimen.of(session, matching: false, settings: sceneSettings).rotation == on)
        sceneSettings.playSequences = false
        #expect(sceneSettings.rotation == off)
        #expect(SessionSpecimen.of(session, matching: false, settings: sceneSettings).rotation == off)
    }

    @Test func aChoiceMadeWhileOnTakesEffectPromptlyAndIsNeverUndone() {
        let scratch = ScratchDefaults.make(prefix: "sequences-choice")
        defer { scratch.discard() }
        let sceneSettings = settings(scratch)
        sceneSettings.playSequences = true
        #expect(plays(sceneSettings.rotation))
        // A member switched off: the whole story goes at once, the rest stay.
        let member = LabScenes.catalogue.first { $0.name == Self.members[1] }!
        sceneSettings.toggle(member)
        #expect(!plays(sceneSettings.rotation))
        #expect(!sceneSettings.isOn(member))
        #expect(!names(sceneSettings.rotation.scenes).contains(member.name))
        #expect(names(sceneSettings.rotation.scenes).contains(Self.members[0]))
        // Switched back on, the story returns.
        sceneSettings.toggle(member)
        #expect(plays(sceneSettings.rotation))
        // Only favourites that do not include the story: no story.
        sceneSettings.toggleFavorite(Self.stranger)
        sceneSettings.onlyFavorites = true
        #expect(!plays(sceneSettings.rotation))
        sceneSettings.onlyFavorites = false
        // Play Only: that one specimen, the setting still on.
        sceneSettings.playOnly(member)
        #expect(sceneSettings.playSequences)
        #expect(names(sceneSettings.rotation.scenes) == [member.name])
    }
}
