// SpecimenPosterTests.swift — a specimen's still is the frame with the most
// ink (SpecimenPoster). Made-up scenes whose ink is known at every moment,
// and the real catalogue for what is true of all of it.
import SwiftUI
import Testing
@testable import Bench

@MainActor
struct SpecimenPosterTests {
    /// A square that grows as the scene goes on: the most ink at the end.
    private let grower = LabScene(name: "Grower", theme: .bench, duration: 4) { context, size, t, tint in
        let side = size.width * 0.8 * min(1, t / 4)
        context.fill(Path(CGRect(x: 2, y: 2, width: side, height: side)), with: .color(tint))
    }

    /// Ink only in the middle second, a patch that swells and shrinks again:
    /// the most at 2 s.
    private let swell = LabScene(name: "Swell", theme: .bench, duration: 4) { context, size, t, tint in
        let side = size.width * 0.8 * max(0, 1 - abs(t - 2))
        context.fill(Path(CGRect(x: 2, y: 2, width: side, height: side)), with: .color(tint))
    }

    /// Draws nothing, ever.
    private let empty = LabScene(name: "Empty", theme: .bench, duration: 4) { _, _, _, _ in }

    @Test func candidatesStayOutOfTheFadesAndTheOldStillComesFirst() {
        let times = SpecimenPoster.times(for: grower)
        #expect(times.first == SpecimenPoster.fallback(grower))
        #expect(SpecimenPoster.fallback(grower) == 2.4)
        #expect(times.count == SpecimenPoster.candidates + 1)
        for time in times.dropFirst() {
            #expect(time > LabScenes.fade && time < grower.duration - LabScenes.fade)
        }
        #expect(times.dropFirst().elementsEqual(times.dropFirst().sorted()))
    }

    @Test func aSceneTooShortForCandidatesKeepsTheOldStill() {
        let blink = LabScene(name: "Blink", theme: .bench, duration: 0.5) { _, _, _, _ in }
        #expect(SpecimenPoster.times(for: blink) == [0.3])
    }

    @Test func theChoiceIsTheMostInkAndATieGoesToTheEarliest() {
        let times = [2.4, 0.5, 1.0, 3.0]
        #expect(SpecimenPoster.choose(ink: [1, 9, 7, 9], at: times) == 0.5)
        #expect(SpecimenPoster.choose(ink: [9, 9, 9, 9], at: times) == 2.4)
        #expect(SpecimenPoster.choose(ink: [1, 2, 3, 4], at: times) == 3.0)
        #expect(SpecimenPoster.choose(ink: [], at: []) == 0)
    }

    @Test func aStillThatAlreadyShowsEnoughKeepsItsTime() {
        let times = [2.4, 0.5, 1.0]
        // 6 of 10 is as much as the old still needs; 5.9 of 10 is not.
        #expect(SpecimenPoster.choose(ink: [6, 10, 7], at: times) == 2.4)
        #expect(SpecimenPoster.choose(ink: [5.9, 10, 7], at: times) == 0.5)
        // And it is the old still that is thin, not just the best frame that is rich.
        #expect(SpecimenPoster.choose(ink: [0, 0, 0], at: times) == 2.4)
    }

    @Test func inkIsHowMuchIsDrawnAtEachTime() {
        let ink = SpecimenPoster.ink(of: grower, at: [1, 2, 3, 3.5])
        #expect(ink.count == 4)
        #expect(ink[0] > 0)
        #expect(ink[0] < ink[1] && ink[1] < ink[2] && ink[2] < ink[3])
        // A square a quarter and then half the width: about a quarter and a half of the cell's 0.8.
        #expect(abs(ink[1] / ink[0] - 4) < 0.5)
        #expect(SpecimenPoster.ink(of: empty, at: [1, 2]) == [0, 0])
    }

    @Test func aGrowingSceneGetsItsLastFrameAndASwellingOneItsMiddle() {
        #expect(SpecimenPoster.time(for: grower) == SpecimenPoster.times(for: grower).last)
        let poster = SpecimenPoster.time(for: swell)
        #expect(abs(poster - 2) < 0.2)
        // A scene with nothing to show keeps the old still rather than moving it.
        #expect(SpecimenPoster.time(for: empty) == SpecimenPoster.fallback(empty))
    }

    @Test func aLiveCellIsNotFadedAtTheStartOfItsLoop() {
        // The same block at every moment. In the rotation a scene fades in over
        // its first 0.3 s, so a cell that drew it that way would be pale there.
        let steady = LabScene(name: "Steady", theme: .bench, duration: 4) { context, size, _, tint in
            context.fill(Path(CGRect(x: 4, y: 4, width: size.width / 2, height: size.height / 2)), with: .color(tint))
        }
        let full = SpecimenPoster.ink(of: steady, at: [2], fading: true)[0]
        let faded = SpecimenPoster.ink(of: steady, at: [0.05], fading: true)[0]
        let looping = SpecimenPoster.ink(of: steady, at: [0.05, 3.97], fading: false)
        #expect(faded < full * 0.5)
        #expect(looping[0] == full && looping[1] == full)
    }

    @Test func aStillThatAlreadyShowsWellKeepsItsTime() {
        // A scene that is the same at every moment: nothing beats the old still.
        let steady = LabScene(name: "Steady", theme: .bench, duration: 4) { context, size, _, tint in
            context.fill(Path(CGRect(x: 4, y: 4, width: size.width / 2, height: size.height / 2)), with: .color(tint))
        }
        #expect(SpecimenPoster.time(for: steady) == SpecimenPoster.fallback(steady))
    }

    @Test func theThinStillsOfTheCatalogueNowShowMoreAndTheRestDoNotMove() throws {
        // Specimens whose old still (60% in) is thin: a poster draws more of them.
        for name in ["Lithography", "Tardigrade", "Cryo-EM", "Aspirator"] {
            let scene = try #require(LabScenes.catalogue.first { $0.name == name })
            let times = SpecimenPoster.times(for: scene)
            let ink = SpecimenPoster.ink(of: scene, at: times)
            let poster = SpecimenPoster.choose(ink: ink, at: times)
            let drawn = try #require(times.firstIndex(of: poster))
            #expect(poster != SpecimenPoster.fallback(scene), "\(name) kept its thin still")
            #expect(ink[drawn] > ink[0] / SpecimenPoster.keepsOldStill, "\(name)'s poster shows too little more")
        }
        // A sample across the rest: a poster is one of the candidates, and
        // never has less ink than the old still.
        for scene in LabScenes.catalogue.enumerated().filter({ $0.offset % 23 == 0 }).map(\.element) {
            let times = SpecimenPoster.times(for: scene)
            let ink = SpecimenPoster.ink(of: scene, at: times)
            let poster = SpecimenPoster.choose(ink: ink, at: times)
            let drawn = try #require(times.firstIndex(of: poster), "\(scene.name)'s poster is not a candidate")
            #expect(ink[drawn] >= ink[0], "\(scene.name)'s poster has less ink than the old still")
        }
    }

    @Test func requestsAreAnsweredOnceAndRememberedForTheRun() async {
        let posters = SpecimenPosters()
        #expect(posters.cached(grower) == nil)
        async let first = posters.time(for: grower)
        async let second = posters.time(for: grower)
        let (a, b) = await (first, second)
        #expect(a == b)
        #expect(a == SpecimenPoster.times(for: grower).last)
        #expect(posters.cached(grower) == a)
        #expect(await posters.time(for: grower) == a)
    }
}
