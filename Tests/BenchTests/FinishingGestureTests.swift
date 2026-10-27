// FinishingGestureTests.swift — the model of time behind a specimen's closing
// gesture (DESIGN.md, "Finishing gestures", since 1.1.0): how long it lasts, that
// it never runs backwards or on to something new, where it rests and when it
// dissolves instead, checked against the scenes' own code. Nothing is read and
// no window opens.
import AppKit
import SwiftUI
import Testing
@testable import Bench

private func specimen(_ name: String) -> LabScene {
    LabScenes.catalogue.first { $0.name == name }!
}

private let batchR = ["Capillary electrophoresis", "Microtome ribbon", "Möbius strip", "Bayesian update",
                      "Droplet coalescence", "Slime mold maze", "Fern unfurling", "Diatom"]

// MARK: - The model of time

struct FinishingModelTests {
    /// Every moment of every loop, every 0.01 s.
    private func everyMoment(of scene: LabScene) -> [Double] {
        (0..<Int(scene.duration * 100)).map { Double($0) / 100 }
    }

    @Test func onlyTheEightNewSpecimensHaveAGestureAndEveryOtherKeepsItsFinish() {
        #expect(Set(FinishingGesture.specs.keys) == Set(batchR))
        for scene in LabScenes.catalogue {
            let plan = FinishingGesture.plan(for: scene, at: scene.duration / 2, poster: 3)
            #expect((plan != nil) == batchR.contains(scene.name), "\(scene.name)")
        }
    }

    @Test func aGestureLastsBetweenFourAndNineTenthsOfASecondWhereverTheFinishLands() {
        for name in batchR {
            let scene = specimen(name)
            for t in everyMoment(of: scene) {
                let plan = FinishingGesture.plan(for: scene, at: t, poster: scene.duration * 0.6)!
                #expect(plan.duration >= 0.4 && plan.duration <= 0.9, "\(name) at \(t): \(plan.duration)")
            }
        }
    }

    @Test func itNeverAdvancesMoreThanItsBudget() {
        for name in batchR {
            let scene = specimen(name)
            for t in everyMoment(of: scene) {
                let plan = FinishingGesture.plan(for: scene, at: t, poster: scene.duration * 0.6)!
                guard plan.kind == .settle else { continue }
                let covered = plan.to - plan.from
                #expect(covered <= FinishingGesture.reach + 1e-9, "\(name) at \(t): \(covered)")
                #expect(covered >= 0, "\(name) at \(t): \(covered)")
                #expect(abs(FinishingGesture.warp(plan.duration, over: plan.duration, covering: covered) - covered) < 1e-9)
            }
        }
    }

    @Test func timeNeverRunsBackwardsAndArrivesAtRestSlowing() {
        for (duration, covered) in [(0.4, 0.1), (0.4, 0.2), (0.8, 0.4), (0.9, 0.45), (0.6, 0.3)] {
            var previous = 0.0
            for step in 0...200 {
                let at = FinishingGesture.warp(duration * Double(step) / 200, over: duration, covering: covered)
                #expect(at >= previous, "\(duration), \(covered) at step \(step)")
                previous = at
            }
            // It starts at the speed the scene was playing at, and ends at none.
            let early = FinishingGesture.warp(0.001, over: duration, covering: covered) / 0.001
            #expect(abs(early - 1) < 0.05, "\(duration), \(covered): \(early)")
            let late = (covered - FinishingGesture.warp(duration - 0.01, over: duration, covering: covered)) / 0.01
            #expect(late < 0.2, "\(duration), \(covered): \(late)")
            // And it rests: later is the same.
            #expect(FinishingGesture.warp(duration + 5, over: duration, covering: covered)
                    == FinishingGesture.warp(duration, over: duration, covering: covered))
        }
    }

    @Test func aSettleInALoopThatWrapsRunsAcrossItsEndIntoItsStart() {
        // 4.69 s into a 5 s loop, the last moment before the rotation fades it out.
        let scene = specimen("Capillary electrophoresis")
        let plan = FinishingGesture.plan(for: scene, at: 4.69, poster: 3)!
        #expect(plan.kind == .settle)
        #expect(plan.to > scene.duration, "it covers the wrap")
        if case .scene(let t) = plan.rest { #expect(t >= 0 && t < scene.duration) } else { Issue.record("not a scene") }
    }

    @Test func itBeginsOnTheFrameThatWasShowing() {
        for name in batchR {
            let scene = specimen(name)
            for t in stride(from: 0.0, to: scene.duration, by: 0.13) {
                let plan = FinishingGesture.plan(for: scene, at: t, poster: scene.duration * 0.6)!
                switch plan.frame(at: 0) {
                case .scene(let local): #expect(abs(local - t) < 1e-9, "\(name) at \(t)")
                case .dissolve(let from, _, let mix):
                    #expect(abs(from - t) < 1e-9 && mix == 0, "\(name) at \(t)")
                }
            }
        }
    }

    @Test func itRestsOnItsLastFrameForGood() {
        for name in batchR {
            let scene = specimen(name)
            for t in stride(from: 0.0, to: scene.duration, by: 0.37) {
                let plan = FinishingGesture.plan(for: scene, at: t, poster: scene.duration * 0.6)!
                #expect(plan.frame(at: plan.duration) == plan.frame(at: plan.duration + 5), "\(name) at \(t)")
                #expect(plan.rest == plan.frame(at: 100))
            }
        }
    }

    @Test func aSlowStopWithNothingInItsWayCoversFourTenthsOfASecond() throws {
        // The capillary at 1.5 s: nothing new within reach, no reset ahead.
        let plan = try #require(FinishingGesture.plan(for: specimen("Capillary electrophoresis"), at: 1.5, poster: 3))
        #expect(plan.kind == .settle)
        #expect(abs(plan.to - plan.from - 0.4) < 1e-9)
        #expect(abs(plan.duration - 0.8) < 1e-9)
    }

    // MARK: Reset windows

    @Test func aFinishInAResetWindowDissolvesToThePosterStill() throws {
        for (name, at) in [("Fern unfurling", 5.9), ("Fern unfurling", 5.6), ("Droplet coalescence", 4.2), ("Droplet coalescence", 3.9),
                           ("Slime mold maze", 6.4), ("Bayesian update", 4.5), ("Bayesian update", 5.5)] {
            let plan = try #require(FinishingGesture.plan(for: specimen(name), at: at, poster: 2.5))
            #expect(plan.kind == .dissolve, "\(name) at \(at)")
            #expect(plan.to == 2.5, "\(name) at \(at): the poster's time")
            #expect(plan.duration == FinishingGesture.dissolveFor)
            // It starts on the frame that showed and ends on the still alone.
            #expect(plan.frame(at: 0) == .dissolve(from: at, to: 2.5, mix: 0))
            #expect(plan.rest == .scene(2.5))
        }
    }

    @Test func aFinishWhileTheRotationFadesTheSceneInOrOutDissolvesToo() throws {
        for name in batchR {
            let scene = specimen(name)
            for at in [0.0, 0.1, 0.29, scene.duration - 0.29, scene.duration - 0.01] {
                let plan = try #require(FinishingGesture.plan(for: scene, at: at, poster: scene.duration * 0.6))
                #expect(plan.kind == .dissolve, "\(name) at \(at)")
            }
        }
    }

    @Test func theDissolveIsAGentleCrossfadeThatOnlyEverGrows() throws {
        let plan = try #require(FinishingGesture.plan(for: specimen("Fern unfurling"), at: 6.0, poster: 3))
        var previous = 0.0
        for step in 0...50 {
            guard case .dissolve(_, _, let mix) = plan.frame(at: plan.duration * Double(step) / 50 * 0.999) else {
                Issue.record("not a dissolve")
                return
            }
            #expect(mix >= previous && mix <= 1)
            previous = mix
        }
    }

    @Test func aSettleNeverRunsIntoAResetOrPastTheEndOfALoopThatDoesNotWrap() {
        for name in batchR {
            guard let spec = FinishingGesture.specs[name] else { continue }
            let scene = specimen(name)
            for t in everyMoment(of: scene) {
                let plan = FinishingGesture.plan(for: scene, at: t, poster: 3)!
                guard plan.kind == .settle else { continue }
                for reset in spec.resets where reset.lowerBound > plan.from {
                    #expect(plan.to <= reset.lowerBound + 1e-9, "\(name) at \(t) runs into the reset at \(reset.lowerBound)")
                }
                if !spec.loops { #expect(plan.to <= scene.duration + 1e-9, "\(name) at \(t)") }
            }
        }
    }

    @Test func hemmedInByAnArrivalItStopsInTheRoomThereIsAndNeverDissolvesIntoTheFinalState() throws {
        let scene = specimen("Bayesian update")
        // 0.08 s before the sixth observation lands (2.75 s): no room to ease, and the still has all six.
        let near = try #require(FinishingGesture.plan(for: scene, at: 2.67, poster: 3.36))
        #expect(near.kind == .settle)
        #expect(near.to < 2.75 && near.to > 2.67, "stops short of the arrival")
        // Inside the margin there is no room at all: it holds.
        let held = try #require(FinishingGesture.plan(for: scene, at: 2.74, poster: 3.36))
        #expect(held.kind == .settle && held.to == held.from)
        #expect(held.frame(at: 0) == held.rest)
        // Before the first reset the fern, too, stops in what room there is.
        let fern = try #require(FinishingGesture.plan(for: specimen("Fern unfurling"), at: 5.55, poster: 3))
        #expect(fern.kind == .settle && abs(fern.to - 5.6) < 1e-9)
    }

    @Test func aSettleNeverLetsAnotherObservationIn() {
        let scene = specimen("Bayesian update")
        let arrivals = FinishingGesture.specs["Bayesian update"]!.arrivals
        #expect(arrivals.count == 6)
        for t in everyMoment(of: scene) {
            let plan = FinishingGesture.plan(for: scene, at: t, poster: 3)!
            guard plan.kind == .settle else { continue }
            for arrival in arrivals where arrival > plan.from {
                #expect(plan.to < arrival, "at \(t) it would show the observation that lands at \(arrival)")
            }
        }
    }

    // MARK: Rests

    @Test func theDiatomEasesToTheNearestReadableAngleAheadAndNeverStopsEdgeOn() throws {
        /// How much of its face the shell shows at `t` in its loop: |cos| of its turn.
        func face(_ t: Double) -> Double {
            let x = t / 5
            return abs(cos(Double.pi * (x - 0.55 / (2 * Double.pi) * sin(2 * Double.pi * x))))
        }
        let scene = specimen("Diatom")
        // Edge on at 2.5 s, and square on at the ends.
        #expect(face(2.5) < 0.01 && face(0) > 0.99 && face(5) > 0.99)
        var settled = 0, dissolved = 0
        for t in everyMoment(of: scene) {
            let plan = try #require(FinishingGesture.plan(for: scene, at: t, poster: 3))
            switch plan.kind {
            case .settle:
                settled += 1
                let rest = plan.to.truncatingRemainder(dividingBy: 5)
                #expect(face(rest) >= 0.8, "at \(t) it would rest at \(rest), showing \(face(rest)) of its face")
                #expect(FinishingGesture.specs["Diatom"]!.policy.isRest(rest), "at \(t): \(rest) is one of the rests")
            case .dissolve:
                dissolved += 1
            }
        }
        print("FINISHING Diatom over every 0.01 s of its loop: \(settled) settle, \(dissolved) dissolve")
        #expect(settled > dissolved, "the readable stretches are most of the loop that is not fading: \(settled) settled, \(dissolved) dissolved")
        // The nearest rest ahead: 3.6 s from 3.2 s, 4.65 s from 4.5 s, and the start of the next loop from 4.6 s.
        let toward36 = try #require(FinishingGesture.plan(for: scene, at: 3.2, poster: 3))
        #expect(toward36.kind == .settle && abs(toward36.to - 3.6) < 1e-9)
        let near = try #require(FinishingGesture.plan(for: scene, at: 4.5, poster: 3))
        #expect(near.kind == .settle && abs(near.to - 4.65) < 1e-9)
        let across = try #require(FinishingGesture.plan(for: scene, at: 4.6, poster: 3))
        #expect(across.kind == .settle && abs(across.to - 5.0) < 1e-9, "the 4.65 s rest is too close to be a settle")
        // Caught mid-turn, with no rest within reach, it dissolves rather than stop on its edge.
        for t in [1.6, 2.0, 2.5, 3.0] {
            #expect(try #require(FinishingGesture.plan(for: scene, at: t, poster: 3)).kind == .dissolve, "at \(t)")
        }
    }

    @Test func theMarkerReachesItsHomeMarkOnlyWhenAShortMoveAllowsItAndOtherwiseSlowsToAStop() throws {
        let scene = specimen("Möbius strip")
        // 0.3 s short of the home mark at 3 s, and of the one at the start of the next loop.
        let near = try #require(FinishingGesture.plan(for: scene, at: 2.7, poster: 3))
        #expect(near.kind == .settle && abs(near.to - 3.0) < 1e-9, "eases home")
        let wrap = try #require(FinishingGesture.plan(for: scene, at: 5.6, poster: 3))
        #expect(wrap.kind == .settle && abs(wrap.to - 6.0) < 1e-9, "eases home across the end of the loop")
        let fading = try #require(FinishingGesture.plan(for: scene, at: 5.8, poster: 3))
        #expect(fading.kind == .dissolve, "5.8 s is the rotation fading the scene out")
        // Far from any home mark it is the slow stop, where it is.
        let far = try #require(FinishingGesture.plan(for: scene, at: 1.2, poster: 3))
        #expect(far.kind == .settle && abs(far.to - 1.6) < 1e-9, "slows to a stop 0.4 s on")
        // Just out of reach of home: still the slow stop, not an ease that overshoots.
        let out = try #require(FinishingGesture.plan(for: scene, at: 2.5, poster: 3))
        #expect(out.kind == .settle && abs(out.to - 2.9) < 1e-9)
    }

    @Test func anEaseToRestPicksTheRightMomentOrFallsBack() {
        let plain = LabScene(name: "Made up", theme: .physics, duration: 5) { _, _, _, _ in }
        let toDissolve = FinishingSpec(.easeToRest([1.5, 2.5], otherwise: .dissolve))
        let toSlow = FinishingSpec(.easeToRest([1.5, 2.5], otherwise: .slowToStop))
        func plan(_ spec: FinishingSpec, at t: Double) -> FinishingPlan {
            FinishingGesture.plan(for: plain, at: t, spec: spec, poster: 4)
        }
        // The nearest rest ahead, not the one behind and not the one beyond.
        #expect(plan(toDissolve, at: 1.3).to == 1.5 && plan(toDissolve, at: 1.3).kind == .settle)
        #expect(plan(toDissolve, at: 1.7).kind == .dissolve, "2.5 is 0.8 s on, beyond reach")
        #expect(plan(toDissolve, at: 2.2).to == 2.5)
        // A rest a hair away is no gesture to ease to: the next, or the fallback.
        #expect(plan(toDissolve, at: 1.45).kind == .dissolve)
        // Out of reach: the fallback it was given.
        #expect(plan(toDissolve, at: 3.0).kind == .dissolve && plan(toDissolve, at: 3.0).to == 4)
        #expect(plan(toSlow, at: 3.0).kind == .settle && abs(plan(toSlow, at: 3.0).to - 3.4) < 1e-9)
        // A rest past a reset is never reached.
        let blocked = FinishingSpec(.easeToRest([2.5], otherwise: .dissolve), resets: [2.2..<3.0])
        #expect(FinishingGesture.plan(for: plain, at: 2.1, spec: blocked, poster: 4).kind == .dissolve)
        // A rest at the start of the next loop is reached only by a loop that wraps.
        let wraps = FinishingSpec(.easeToRest([0], otherwise: .dissolve), loops: true)
        let stops = FinishingSpec(.easeToRest([0], otherwise: .dissolve), loops: false)
        #expect(abs(FinishingGesture.plan(for: plain, at: 4.6, spec: wraps, poster: 4).to - 5.0) < 1e-9)
        #expect(FinishingGesture.plan(for: plain, at: 4.6, spec: stops, poster: 4).kind == .dissolve)
    }

    // MARK: The scene's own code, which the table above is read from

    /// The ink in the rows of a scene `at` seconds in, drawn small.
    @MainActor
    private func ink(of scene: LabScene, at local: Double, rows: ClosedRange<Double>) -> Double {
        let side = 100
        let view = Canvas { context, size in
            scene.draw(&context, size, local, .black)
        }.frame(width: CGFloat(side), height: CGFloat(side))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return 0 }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }
        var total = 0
        for y in Int(rows.lowerBound * Double(side))...Int(rows.upperBound * Double(side)) {
            for x in 0..<side { total += Int(pixels[(y * side + x) * 4 + 3]) }
        }
        return Double(total) / 255
    }

    @MainActor
    @Test func theBayesianObservationsLandWhenTheTableSaysTheyDo() {
        let scene = specimen("Bayesian update")
        let arrivals = FinishingGesture.specs["Bayesian update"]!.arrivals
        // The row of dots under the curve, y from 0.80 to 0.93.
        let row = 0.80...0.93
        var before = ink(of: scene, at: arrivals[0] - 0.02, rows: row)
        #expect(before == 0, "no dot before the first arrival")
        for (k, arrival) in arrivals.enumerated() {
            let after = ink(of: scene, at: arrival + 0.3, rows: row)
            #expect(after > before, "observation \(k + 1) lands at \(arrival)")
            if k + 1 < arrivals.count {
                // And nothing else lands in between.
                #expect(ink(of: scene, at: arrivals[k + 1] - 0.02, rows: row) == after, "no dot between \(arrival) and \(arrivals[k + 1])")
            }
            before = after
        }
    }

    @MainActor
    @Test func theLoopsThatWrapCloseOnThemselves() {
        // The end of the loop and its start are one picture, as far as one step of the clock goes.
        for name in batchR where FinishingGesture.specs[name]!.loops {
            let scene = specimen(name)
            func image(_ t: Double) -> [Double] {
                let renderer = ImageRenderer(content: Canvas { context, size in scene.draw(&context, size, t, .black) }.frame(width: 60, height: 60))
                renderer.scale = 1
                guard let cg = renderer.cgImage, let data = cg.dataProvider?.data as Data? else { return [] }
                return data.map { Double($0) }
            }
            func gap(_ a: Double, _ b: Double) -> Double {
                zip(image(a), image(b)).reduce(0) { $0 + abs($1.0 - $1.1) }
            }
            let across = gap(scene.duration - 0.01, 0)
            let step = gap(0, 0.02)
            let middle = gap(scene.duration / 2, scene.duration / 2 + 0.02)
            print("FINISHING loop closes, \(name): across the end \(Int(across)), one step at the start \(Int(step)), one step midway \(Int(middle))")
            // Across the end is one step of the clock, so no more than a step elsewhere in the loop.
            #expect(across <= max(step, middle) * 1.5 + 200, "\(name) closes: across \(across), a step \(step), \(middle)")
        }
    }
}

extension FinishingSpec.Policy {
    /// Whether `time` is one of its rests.
    fileprivate func isRest(_ time: Double) -> Bool {
        if case .easeToRest(let rests, _) = self { return rests.contains { abs($0 - time) < 1e-9 } }
        return false
    }
}
