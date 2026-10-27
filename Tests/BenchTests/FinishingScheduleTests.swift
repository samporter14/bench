// FinishingScheduleTests.swift — the frames of a closing gesture, and then no more
// (DESIGN.md, "Finishing gestures", since 1.1.0): the timeline has exactly the
// gesture's frames, and the last frame is the one it rests on.
import SwiftUI
import Testing
@testable import Bench

private func specimen(_ name: String) -> LabScene {
    LabScenes.catalogue.first { $0.name == name }!
}

struct FinishingScheduleTests {
    @Test func itDrawsEveryThirtiethOfASecondAndLastlyTheEndAndNothingAfter() {
        for duration in [0.4, 0.5, 0.8, 0.9] {
            let times = FinishingGesture.frameTimes(duration: duration)
            #expect(times.first == 0 && times.last == duration)
            #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "strictly later each time")
            #expect(times.count <= 28)
            #expect(times.allSatisfy { $0 <= duration })
        }
    }

    @Test func theTimelineEndsWhenTheGestureDoesAndAskedAgainStaysEnded() {
        let began = Date(timeIntervalSinceReferenceDate: 1_000)
        let schedule = FinishingSchedule(began: began, duration: 0.8)
        var entries = schedule.entries(from: began, mode: .normal)
        var dates: [Date] = []
        while let date = entries.next() { dates.append(date) }
        #expect(dates.first == began)
        #expect(dates.last == began.addingTimeInterval(0.8))
        // After the last, the timeline gets nothing: nothing more is drawn.
        #expect(entries.next() == nil && entries.next() == nil)
        #expect(dates.count == FinishingGesture.frameTimes(duration: 0.8).count)
        // Asked from the middle of it, only what is left; from after it, nothing at all.
        var middle = schedule.entries(from: began.addingTimeInterval(0.4), mode: .normal)
        var left: [Date] = []
        while let date = middle.next() { left.append(date) }
        #expect(left.first! >= began.addingTimeInterval(0.4) && left.last == began.addingTimeInterval(0.8))
        var after = schedule.entries(from: began.addingTimeInterval(0.81), mode: .normal)
        #expect(after.next() == nil)
    }

    @Test func aDisplayThatAsksForLessGetsTheLastFrameAlone() {
        let began = Date(timeIntervalSinceReferenceDate: 1_000)
        var entries = FinishingSchedule(began: began, duration: 0.6).entries(from: began, mode: .lowFrequency)
        #expect(entries.next() == began.addingTimeInterval(0.6))
        #expect(entries.next() == nil)
    }

    @MainActor
    @Test func thePlanDrawsNothingNewAfterItsEndAndItsLastFrameIsTheSameImage() throws {
        let scene = specimen("Droplet coalescence")
        let plan = try #require(FinishingGesture.plan(for: scene, at: 2.0, poster: 3))
        func image(_ elapsed: Double) -> Data? {
            let view = Canvas { context, size in
                FinishingDraw.draw(plan.frame(at: elapsed), of: scene, in: &context, size: size, tint: .black)
            }.frame(width: 88, height: 88)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return renderer.cgImage?.dataProvider?.data as Data?
        }
        let last = try #require(image(plan.duration))
        #expect(last == image(plan.duration + 5), "rests on its last frame")
        #expect(last != image(0), "and it did move")
        #expect(image(0) == image(-1), "before it begins, it is the frame that showed")
    }

    /// A dissolve adds its two frames, so ink they share stays whole halfway: a
    /// frame dissolving into itself looks just like that frame, where two
    /// half-strength layers laid over each other would leave it at three quarters.
    @MainActor
    @Test func inkBothFramesShareDoesNotDimHalfwayThroughADissolve() throws {
        for name in ["Slime mold maze", "Droplet coalescence", "Fern unfurling"] {
            let scene = specimen(name)
            let at = scene.duration / 2
            func pixels(_ frame: FinishingPlan.Frame) throws -> [UInt8] {
                let view = Canvas { context, size in
                    FinishingDraw.draw(frame, of: scene, in: &context, size: size, tint: .black)
                }.frame(width: 88, height: 88)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                return [UInt8](try #require(renderer.cgImage?.dataProvider?.data as Data?))
            }
            let plain = try pixels(.scene(at))
            let halfway = try pixels(.dissolve(from: at, to: at, mix: 0.5))
            #expect(plain.count == halfway.count)
            let worst = zip(plain, halfway).map { abs(Int($0) - Int($1)) }.max() ?? 0
            #expect(worst <= 3, "\(name): at most rounding apart, not \(worst)")
        }
    }
}
