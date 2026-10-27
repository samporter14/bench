// PlaybackChunkTests.swift — a specimen plays a second of frames at a time
// (Shared/PlayedViews.swift): which chunks a rotation makes, that each begins
// where the one before ends, that no more than two are ever held, and that a
// restart or a stall leaves nothing behind. The clock and the waits are the
// test's own; no scene is drawn, no window opened, nothing really sleeps.
import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import Bench

// MARK: - The plan

struct PlaybackPlanTests {
    /// Three scenes: 96, 600 and 75 frames at 30 a second.
    private let durations = [3.2, 20.0, 2.5]

    private func chunks(_ count: Int, fps: Double = 30, durations: [Double]? = nil,
                        scene: Int = 0, sceneStart: Double = 100, now: Double? = nil) -> [PlaybackChunk] {
        var plan = PlaybackPlan(sceneDurations: durations ?? self.durations, fps: fps, scene: scene,
                                sceneStart: sceneStart, now: now ?? sceneStart)
        return (0..<count).map { _ in plan.next() }
    }

    @Test func aSceneIsCutIntoEvenChunksOfAtMostASecond() {
        // 96 frames are four of 24, 600 are twenty of 30, 75 are three of 25;
        // then the rotation comes round again.
        let made = chunks(28)
        #expect(made.prefix(4).map(\.frames.count) == [24, 24, 24, 24])
        #expect(made[4..<24].allSatisfy { $0.frames.count == 30 })
        #expect(made[24..<27].map(\.frames.count) == [25, 25, 25])
        #expect(made[27].scene == 0 && made[27].frames.lowerBound == 0)
        #expect(made.map(\.scene) == Array(repeating: 0, count: 4) + Array(repeating: 1, count: 20)
                + Array(repeating: 2, count: 3) + [0])
    }

    @Test func aRemainderIsSharedOutNotLeftAsASliver() {
        // 61 frames: 21, 20, 20 (not 30, 30, 1).
        var plan = PlaybackPlan(sceneDurations: [61.0 / 30 + 0.001], fps: 30, scene: 0, sceneStart: 0, now: 0)
        #expect((0..<3).map { _ in plan.next().frames.count } == [21, 20, 20])
        // Whatever the length, every chunk is between half a second and a second.
        for frames in 31...400 {
            var plan = PlaybackPlan(sceneDurations: [Double(frames) / 30 + 0.001], fps: 30, scene: 0, sceneStart: 0, now: 0)
            var sizes: [Int] = []
            var covered = 0
            while covered < frames {
                let chunk = plan.next()
                sizes.append(chunk.frames.count)
                covered += chunk.frames.count
            }
            #expect(covered == frames)
            #expect(sizes.allSatisfy { $0 <= 30 && $0 >= 15 }, "\(frames) frames: \(sizes)")
        }
    }

    @Test func framesRunOnWithoutAGapOrARepeat() {
        let made = chunks(27)
        var expected = 0
        var scene = 0
        for chunk in made {
            if chunk.scene != scene { scene = chunk.scene; expected = 0 }
            #expect(chunk.frames.lowerBound == expected)
            expected = chunk.frames.upperBound
        }
        // Each scene's last chunk ends on its last frame: Int(duration * fps).
        #expect(made[3].frames.upperBound == 96)
        #expect(made[23].frames.upperBound == 600)
        #expect(made[26].frames.upperBound == 75)
    }

    @Test func eachChunkBeginsWhereTheLastEnds() {
        // At a realistic clock reading (seconds since 2001) a double has about
        // 100 ns to spare; the chunks must agree to well under a frame.
        for start in [100.0, 812_345_678.123] {
            let made = chunks(60, sceneStart: start)
            for (before, after) in zip(made, made.dropFirst()) {
                if after.scene == before.scene {
                    #expect(abs(after.begin - before.end) < 1e-6, "chunk \(after.sequence)")
                }
            }
        }
        // And at a small one, to the bit that matters here: not even a microsecond.
        let made = chunks(30, sceneStart: 100)
        for (before, after) in zip(made, made.dropFirst()) where after.scene == before.scene {
            #expect(abs(after.begin - before.end) < 1e-9)
        }
    }

    @Test func aNewSceneBeginsWhenTheRotationSaysAndNeverEarlierThanTheLastEnds() {
        let made = chunks(60, sceneStart: 1_000)
        // Scenes start at 3.2, 23.2 and 25.7 seconds in, then round again.
        let firsts = made.filter { $0.frames.lowerBound == 0 }
        #expect(firsts.prefix(5).map(\.begin).map { ($0 - 1_000).rounded(toPlaces: 6) } == [0, 3.2, 23.2, 25.7, 28.9])
        for (before, after) in zip(made, made.dropFirst()) where after.scene != before.scene {
            let gap = after.begin - before.end
            #expect(gap >= -1e-9, "a new scene never begins before the last chunk ends")
            #expect(gap < 1.0 / 30 + 1e-9, "and is at most a frame after it")
        }
    }

    @Test func startingPartWayIntoASceneBeginsAtTheFrameDueNow() {
        // One second in is frame 30; 66 frames remain, three chunks of 22.
        let made = chunks(3, sceneStart: 5_000, now: 5_001.0)
        #expect(made[0].frames == 30..<52)
        #expect(made.map(\.frames.count) == [22, 22, 22])
        #expect(abs(made[0].begin - 5_001.0) < 1e-9)
        // Between two frames, the one that is showing: it began before now.
        let between = chunks(1, sceneStart: 5_000, now: 5_001.0 + 0.4 / 30)
        #expect(between[0].frames.lowerBound == 30)
        #expect(between[0].begin <= 5_001.0 + 0.4 / 30)
    }

    @Test func startingInTheLastFractionOfAFrameBeginsTheNextScene() {
        // 18.37 s is 551 frames and a bit; 18.368 s in, no frame is left.
        let made = chunks(1, durations: [18.37, 4.0], sceneStart: 7_000, now: 7_018.368)
        #expect(made[0].scene == 1 && made[0].frames.lowerBound == 0)
        #expect(abs(made[0].begin - 7_018.37) < 1e-9)
    }

    @Test func aLowerRateMakesShorterChunksOfASecond() {
        let made = chunks(8, fps: 15)
        // 48 frames (3.2 s at 15) are four of 12; 300 are twenty of 15.
        #expect(made.prefix(4).map(\.frames.count) == [12, 12, 12, 12])
        #expect(made[4].frames.count == 15)
        #expect(made.allSatisfy { $0.duration <= 1.0 + 1e-9 })
        #expect(abs(made[1].begin - (100 + 12.0 / 15)) < 1e-9)
    }

    @Test func eachChunkHasAKeyOfItsOwn() {
        let made = chunks(80)
        #expect(Set(made.map(\.key)).count == 80)
        #expect(made.map(\.sequence) == Array(0..<80))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (self * scale).rounded() / scale
    }
}

// MARK: - The player

/// Made-up surroundings for a `ChunkedPlayback`: a clock that moves when the
/// test lets the playback's wait end, and a record of every draw, begin and
/// release.
@MainActor
private final class Stage {
    var time: Double
    var begun: [PlaybackChunk] = []
    var released: [PlaybackChunk] = []
    var drawn: [PlaybackChunk] = []
    var drawTimes: [Int: Double] = [:]
    var releaseTimes: [Int: Double] = [:]
    var beginTimes: [Int: Double] = [:]
    var waits: [Double] = []
    /// Chunks begun and not yet released, as the layer would hold them.
    var held: Set<Int> = []
    var mostHeld = 0
    /// How many were held at each draw.
    var heldWhenDrawing: [Int] = []
    /// The next draws that make no frames.
    var emptyDraws = 0
    /// Draw returns nil, as it does when the view has gone.
    var gone = false
    /// Extra seconds the clock jumps each time a wait ends, as a stalled main thread would.
    var stall = 0.0

    private var asleep: (until: Double, resume: CheckedContinuation<Void, Never>)?
    private var watcher: CheckedContinuation<Void, Never>?
    private let pixel: CGImage

    init(time: Double) {
        self.time = time
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixel = context.makeImage()!
    }

    func playback(_ plan: PlaybackPlan) -> ChunkedPlayback {
        ChunkedPlayback(plan: plan, now: { self.time }, wait: { await self.sleep($0) },
                        draw: { self.draw($0) }, begin: { chunk, _ in self.begin(chunk) },
                        release: { self.release($0) })
    }

    private func draw(_ chunk: PlaybackChunk) -> [CGImage]? {
        heldWhenDrawing.append(held.count)
        drawn.append(chunk)
        drawTimes[chunk.sequence] = time
        if gone { return nil }
        if emptyDraws > 0 { emptyDraws -= 1; return [] }
        return Array(repeating: pixel, count: chunk.frames.count)
    }

    private func begin(_ chunk: PlaybackChunk) {
        begun.append(chunk)
        beginTimes[chunk.sequence] = time
        held.insert(chunk.sequence)
        mostHeld = max(mostHeld, held.count)
    }

    private func release(_ chunk: PlaybackChunk) {
        released.append(chunk)
        releaseTimes[chunk.sequence] = time
        held.remove(chunk.sequence)
    }

    private func sleep(_ seconds: Double) async {
        waits.append(seconds)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            asleep = (time + seconds, continuation)
            watcher?.resume()
            watcher = nil
        }
    }

    /// Waits until the playback is asleep, then lets it sleep out its time.
    func turn() async {
        await settle()
        guard let (until, resume) = asleep else { return }
        asleep = nil
        time = max(time, until) + stall
        resume.resume()
    }

    /// Waits until the playback is asleep (its work for now is done).
    func settle() async {
        if asleep == nil { await withCheckedContinuation { watcher = $0 } }
    }

    /// Ends the playback's wait without moving the clock, as cancelling does to a real one.
    func interrupt() {
        guard let (_, resume) = asleep else { return }
        asleep = nil
        resume.resume()
    }

    var isAsleep: Bool { asleep != nil }
}

@MainActor
struct ChunkedPlaybackTests {
    private static let start = 812_345_678.0
    private let durations = [3.2, 20.0, 2.5]

    /// A playback beginning 0.3 s into the first scene, which began at `start - 0.3`.
    private func make(_ stage: Stage, fps: Double = 30, now: Double = ChunkedPlaybackTests.start) -> ChunkedPlayback {
        let plan = PlaybackPlan(sceneDurations: durations, fps: fps, scene: 0,
                                sceneStart: Self.start - 0.3, now: now)
        return stage.playback(plan)
    }

    @Test func playsOneChunkAndDrawsTheNextWhileItPlays() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        await stage.settle()
        // The chunk due now, at once; then a moment for the run loop, and the next.
        #expect(stage.begun.map(\.sequence) == [0])
        #expect(stage.waits == [0.005])
        #expect(stage.begun[0].begin <= Self.start, "the first is playing now")
        await stage.turn()
        await stage.settle()
        #expect(stage.begun.map(\.sequence) == [0, 1])
        #expect(stage.begun[1].begin > Self.start, "the second is waiting")
        #expect(abs(stage.begun[1].begin - stage.begun[0].end) < 1e-6)
        #expect(stage.held == [0, 1])
        playback.stop()
    }

    @Test func neverHoldsMoreThanTwoChunks() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        // Over two passes through the rotation (25.7 s each).
        for _ in 0..<70 { await stage.turn() }
        await stage.settle()
        #expect(stage.mostHeld == 2)
        // A chunk is drawn only once there is room: at most one held.
        #expect(stage.heldWhenDrawing.allSatisfy { $0 <= 1 })
        #expect(stage.begun.count > 60)
        #expect(stage.held.count == 2)
        #expect(stage.begun.count - stage.released.count == 2)
        playback.stop()
        #expect(stage.held.isEmpty)
    }

    @Test func aLongStoryWovenIntoTheRotationStillHoldsNoMoreThanTwoChunks() async {
        // Short sequences (Lab/SpecimenSequences.swift) are ordinary scenes in
        // the list, so a story of sixty members costs what sixty scenes do:
        // two chunks at a time, however long the run.
        let told = (1...60).map { "L\($0)" }
        let silent: @Sendable (inout GraphicsContext, CGSize, Double, Color) -> Void = { _, _, _, _ in }
        let alone = (1...30).map { LabScene(name: "S\($0)", theme: .bench, duration: 3, draw: silent) }
        let members = told.map { LabScene(name: $0, theme: .cell, duration: 4, draw: silent) }
        let woven = SpecimenSequence.weave(alone + members, sequences: [SpecimenSequence(title: "Long", members: told)],
                                           spread: { $0 })
        let block = woven.blocks[0].range
        #expect(block.count == 60)
        let stage = Stage(time: Self.start)
        let plan = PlaybackPlan(sceneDurations: woven.scenes.map(\.duration), fps: 30, scene: block.lowerBound,
                                sceneStart: Self.start, now: Self.start)
        let playback = stage.playback(plan)
        playback.start()
        for _ in 0..<70 { await stage.turn() }
        await stage.settle()
        #expect(stage.mostHeld == 2)
        #expect(stage.heldWhenDrawing.allSatisfy { $0 <= 1 })
        #expect(stage.begun.count - stage.released.count == 2)
        // It really went through members of the story, one scene after another.
        #expect(Set(stage.begun.map(\.scene)).count > 10)
        #expect(stage.begun.allSatisfy { block.contains($0.scene) })
        playback.stop()
        #expect(stage.held.isEmpty)
    }

    @Test func chunksPlayInOrderEndToEnd() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        for _ in 0..<70 { await stage.turn() }
        await stage.settle()
        #expect(stage.begun.map(\.sequence) == Array(0..<stage.begun.count))
        #expect(stage.released.map(\.sequence) == Array(0..<stage.released.count))
        for (before, after) in zip(stage.begun, stage.begun.dropFirst()) {
            let gap = after.begin - before.end
            if after.scene == before.scene {
                #expect(abs(gap) < 1e-6, "chunk \(after.sequence) begins as \(before.sequence) ends")
            } else {
                #expect(gap >= -1e-6 && gap < 1.0 / 30 + 1e-6)
            }
        }
        playback.stop()
    }

    @Test func aChunkIsDrawnBeforeItIsDueAndReleasedOnlyOnceTheNextHasBegun() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        for _ in 0..<70 { await stage.turn() }
        await stage.settle()
        for chunk in stage.begun where chunk.sequence >= 2 {
            let drawnAt = stage.drawTimes[chunk.sequence]!
            // Drawn most of a second ahead, never less than half of one.
            #expect(chunk.begin - drawnAt > 0.5, "chunk \(chunk.sequence) drawn \(chunk.begin - drawnAt) s ahead")
            #expect(chunk.begin - drawnAt <= 1.0 + 1.0 / 30 + 1e-6)
        }
        for chunk in stage.released {
            let next = stage.begun[chunk.sequence + 1]
            let releasedAt = stage.releaseTimes[chunk.sequence]!
            #expect(releasedAt >= next.begin + ChunkedPlayback.margin - 1e-9,
                    "chunk \(chunk.sequence) released before \(next.sequence) had begun")
            #expect(releasedAt - next.begin < 0.1, "and not long after")
            // The room it leaves is used at once: the next chunk is drawn then.
            #expect(stage.drawTimes[chunk.sequence + 2] == releasedAt)
        }
        playback.stop()
    }

    @Test func stoppingReleasesWhatItHoldsAndNothingMoreIsDrawnOrBegun() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        for _ in 0..<5 { await stage.turn() }
        await stage.settle()
        let drawn = stage.drawn.count, begun = stage.begun.count
        #expect(stage.held.count == 2)
        playback.stop()
        #expect(stage.held.isEmpty, "stopping hands back both chunks")
        #expect(stage.released.count == begun)
        #expect(!playback.isRunning)
        // The wait it was in ends (cancelling a real one does); it must not
        // draw, begin or release again.
        stage.interrupt()
        for _ in 0..<5 { await Task.yield() }
        #expect(stage.drawn.count == drawn)
        #expect(stage.begun.count == begun)
        #expect(stage.released.count == begun)
        #expect(stage.mostHeld == 2)
    }

    @Test func stoppingBetweenTheFirstTwoDrawsDrawsNoSecondChunk() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        await stage.settle()
        // Asleep for the 5 ms between the first two draws: it has the first only.
        #expect(stage.begun.count == 1)
        playback.stop()
        stage.interrupt()
        for _ in 0..<5 { await Task.yield() }
        #expect(stage.drawn.count == 1)
        #expect(stage.begun.count == 1)
        #expect(stage.held.isEmpty)
        #expect(stage.released.count == 1)
    }

    @Test func aReplacementStartsFromNothingWhileTheOldOneStaysSilent() async {
        // A restart: the view stops the playback and starts another, planned
        // from the clock now. The old one must add nothing to the layer.
        let stage = Stage(time: Self.start)
        let first = make(stage)
        first.start()
        for _ in 0..<3 { await stage.turn() }
        await stage.settle()
        first.stop()
        let drawnBefore = stage.drawn.count
        stage.interrupt()
        let second = make(stage, now: stage.time)
        second.start()
        for _ in 0..<3 { await stage.turn() }
        await stage.settle()
        // Everything drawn since is the second's: sequences start again at 0.
        let since = stage.drawn[drawnBefore...]
        #expect(since.first?.sequence == 0)
        #expect(stage.mostHeld == 2)
        second.stop()
        #expect(stage.held.isEmpty)
    }

    @Test func aChunkThatIsOverByTheTimeItsTurnComesIsSkippedNotDrawnLate() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        await stage.settle()
        // The main thread stalls for 7 s: the clock is past three chunks.
        stage.stall = 7
        await stage.turn()
        stage.stall = 0
        await stage.settle()
        let late = stage.drawn.last!
        #expect(late.end > stage.time, "the chunk drawn after the stall is not already over")
        #expect(late.sequence >= 5, "the ones in between were skipped, not drawn")
        for _ in 0..<10 { await stage.turn() }
        await stage.settle()
        #expect(stage.mostHeld == 2)
        #expect(stage.heldWhenDrawing.allSatisfy { $0 <= 1 })
        // And it catches up: what plays now is current.
        #expect(stage.begun.last!.end > stage.time)
        playback.stop()
    }

    @Test func aDrawThatMakesNoFramesWaitsInsteadOfSpinning() async {
        let stage = Stage(time: Self.start)
        stage.emptyDraws = 1
        let playback = make(stage)
        playback.start()
        await stage.settle()
        // The first chunk made nothing: it waited (at least 50 ms) rather than
        // drawing the next at once.
        #expect(stage.drawn.count == 1)
        #expect(stage.begun.isEmpty)
        #expect(stage.waits.first! >= 0.05)
        for _ in 0..<4 { await stage.turn() }
        await stage.settle()
        #expect(!stage.begun.isEmpty)
        #expect(stage.mostHeld <= 2)
        playback.stop()
    }

    @Test func endsWhenThereIsNothingLeftToDrawFor() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage)
        playback.start()
        for _ in 0..<3 { await stage.turn() }
        await stage.settle()
        #expect(playback.isRunning)
        stage.gone = true
        await stage.turn()
        for _ in 0..<5 { await Task.yield() }
        #expect(!playback.isRunning)
        #expect(!stage.isAsleep)
    }

    @Test func aLowerRateDrawsHalfAsManyFramesPerChunk() async {
        let stage = Stage(time: Self.start)
        let playback = make(stage, fps: 15)
        playback.start()
        for _ in 0..<6 { await stage.turn() }
        await stage.settle()
        #expect(stage.begun.allSatisfy { $0.frames.count <= 15 && $0.fps == 15 })
        #expect(stage.mostHeld == 2)
        playback.stop()
    }
}

// MARK: - On the layer

@MainActor
struct PlayedGlyphViewTests {
    private func images(_ count: Int) -> [CGImage] {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        return Array(repeating: image, count: count)
    }

    @Test func aChunkIsOneDiscreteAnimationThatHoldsItsLastFrame() {
        let animation = PlayedGlyphView.animation(of: images(24), fps: 30, beginTime: 12.5)
        #expect(animation.keyPath == "contents")
        #expect(animation.calculationMode == .discrete)
        #expect(animation.values?.count == 24)
        #expect(animation.keyTimes?.count == 25)
        #expect(animation.keyTimes?.first?.doubleValue == 0 && animation.keyTimes?.last?.doubleValue == 1)
        #expect(abs(animation.duration - 0.8) < 1e-12)
        #expect(animation.beginTime == 12.5)
        // The seam between chunks: the last frame stays until the chunk is
        // released, so a clock a hair out never shows the layer's own contents.
        #expect(animation.fillMode == .forwards)
        #expect(!animation.isRemovedOnCompletion)
        #expect(animation.repeatCount == 0)
    }

    @Test func aViewPlaysAtThirtyFramesUnlessToldOtherwise() {
        let view = PlayedGlyphView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        #expect(view.fps == 30)
        #expect(PlayedGlyphView.fps == 30)
        view.fps = 15
        #expect(view.fps == 15)
    }

    /// Records the moment each frame was drawn for.
    private final class Moments: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: Set<Double> = []
        func note(_ t: Double) { lock.lock(); seen.insert((t * 1_000_000).rounded() / 1_000_000); lock.unlock() }
        var sorted: [Double] { lock.lock(); defer { lock.unlock() }; return seen.sorted() }
    }

    @Test func framesAreDrawnAtTheRateAskedFor() {
        let moments = Moments()
        let scene = LabScene(name: "Clock", theme: .bench, duration: 4) { context, size, t, tint in
            moments.note(t)
            context.fill(Path(CGRect(x: 0, y: 0, width: 2, height: 2)), with: .color(tint))
        }
        let made = PlayedGlyphView.frames(of: scene, from: 15, to: 30, size: CGSize(width: 8, height: 8),
                                          scale: 1, tint: .white, fps: 15)
        #expect(made.count == 15)
        #expect(moments.sorted.count == 15)
        // Frame 15 at 15 a second is one second in; frame 29 is 1.93 s.
        #expect(abs(moments.sorted.first! - 1.0) < 1e-5)
        #expect(abs(moments.sorted.last! - 29.0 / 15) < 1e-5)
        // The default rate is the one the scenes were always drawn at.
        let again = Moments()
        let thirty = LabScene(name: "Clock", theme: .bench, duration: 4) { context, size, t, tint in again.note(t) }
        _ = PlayedGlyphView.frames(of: thirty, from: 30, to: 60, size: CGSize(width: 8, height: 8), scale: 1, tint: .white)
        #expect(abs(again.sorted.first! - 1.0) < 1e-5)
        #expect(abs(again.sorted.last! - 59.0 / 30) < 1e-5)
    }
}
