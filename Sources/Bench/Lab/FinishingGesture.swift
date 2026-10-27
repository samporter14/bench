// FinishingGesture.swift — how a specimen closes when its session finishes
// (DESIGN.md, "Finishing gestures", since 1.1.0). A model of time and nothing
// else: given the specimen and where in its loop it was, it says what the next
// half second shows. No scene is drawn differently; the drawing is still the
// specimen's own, asked for a different moment than the clock would give.
//
// Two shapes of ending, and a fallback:
//   - `settle`: the scene's own time slows from the speed it was playing at to a
//     stop, covering a fraction of a second of its loop (less as something new
//     draws near, down to nothing), and rests there.
//   - `dissolve`: where no coherent settle is possible (the scene is itself
//     crossfading or sliding back to its start), the frame that was showing
//     gives way to the specimen's poster still, and rests on that.
// Neither speeds anything up: the clock only ever slows, and it never runs on
// to what the specimen would have drawn next (an observation that had not yet
// landed, a new plug entering, the next fiddlehead).
import Foundation

/// What one specimen does when its session finishes.
struct FinishingSpec: Sendable {
    /// Where the scene may stop.
    enum Policy: Sendable {
        /// Anywhere: the clock slows to a stop.
        case slowToStop
        /// At one of these times of its loop, when the nearest one ahead is
        /// within reach; else `otherwise`.
        case easeToRest([Double], otherwise: Otherwise)
    }

    /// What an ease to rest does when no rest is within reach.
    enum Otherwise: Sendable {
        case slowToStop
        /// For a scene that must not stop just anywhere (a shell caught edge on).
        case dissolve
    }

    let policy: Policy
    /// Stretches of the loop where the scene is sliding or crossfading back to
    /// its start. A finish in one dissolves; a settle never runs into one.
    let resets: [Range<Double>]
    /// Moments when something new would appear. A settle stops short of the next.
    let arrivals: [Double]
    /// Whether the loop is periodic by construction, so a settle may run across
    /// its end into its start. The others end in a reset, which a settle stops short of.
    let loops: Bool

    init(_ policy: Policy, resets: [Range<Double>] = [], arrivals: [Double] = [], loops: Bool = false) {
        self.policy = policy
        self.resets = resets
        self.arrivals = arrivals
        self.loops = loops
    }
}

/// One finish, planned from the frame that was showing.
struct FinishingPlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case settle, dissolve }

    /// What to draw at a moment of the gesture.
    enum Frame: Equatable, Sendable {
        /// The scene at this time of its loop, at full strength.
        case scene(Double)
        /// The frame as the rotation showed it, fade and all, giving way to the
        /// still at `to`; `mix` is how much of the still shows.
        case dissolve(from: Double, to: Double, mix: Double)
    }

    /// The specimen's name in the catalogue.
    let scene: String
    let kind: Kind
    /// The scene's own length.
    let loop: Double
    /// Its time when the session finished: the first frame.
    let from: Double
    /// Where it comes to rest: for a settle, `from` plus the time it covers
    /// (past `loop` when it runs across the end); for a dissolve, the poster's time.
    let to: Double
    /// How long the gesture lasts, in seconds.
    let duration: Double

    /// A pure function of the time since the gesture began, so a rebuilt view
    /// carries on where it was, and rests on its last frame for good.
    func frame(at elapsed: Double) -> Frame {
        switch kind {
        case .settle:
            let covered = FinishingGesture.warp(elapsed, over: duration, covering: to - from)
            return .scene((from + covered).truncatingRemainder(dividingBy: loop))
        case .dissolve:
            guard elapsed < duration else { return .scene(to) }
            return .dissolve(from: from, to: to, mix: Ease.inOut(elapsed / duration))
        }
    }

    /// Where it ends and stays.
    var rest: Frame { frame(at: duration) }
}

enum FinishingGesture {
    /// How long a gesture lasts, at least and at most.
    static let shortest = 0.4
    static let longest = 0.9
    /// The most of the scene's own time a settle may cover, and the least a rest
    /// ahead may be to be worth easing to (nearer than that is where it already is).
    static let reach = 0.45
    static let least = 0.1
    /// What a slow stop covers when nothing is in the way.
    static let slowAdvance = 0.4
    /// How long a dissolve takes.
    static let dissolveFor = 0.5
    /// How short of an arrival a settle stops, in the scene's seconds.
    static let margin = 0.02
    /// Frames a second while it plays.
    static let fps = 30.0

    /// How the eight scenes of batch R close, read from their code (the names
    /// the code gives are in the comments). Any other specimen has no entry and
    /// keeps the plate.
    static let specs: [String: FinishingSpec] = [
        // Periodic by construction: the trace and the bands of the last run wrap
        // round, and the next plug (`injectAt`, 0.3 into the loop) is further
        // away than a settle goes.
        "Capillary electrophoresis": FinishingSpec(.slowToStop, loops: true),
        // Four identical passes of 1.4 s (`strokes`); the ribbon moves on by one
        // section a pass, so the loop is seamless.
        "Microtome ribbon": FinishingSpec(.slowToStop, loops: true),
        // Two laps of the marker in 6 s; the loop is seamless. It has a home
        // mark where it began (0, and again at 3 s with its tick on the other
        // face, `markerFrom`): reached only when it is a short move away, else
        // the marker slows to a stop where it is.
        "Möbius strip": FinishingSpec(.easeToRest([0, 3], otherwise: .slowToStop), loops: true),
        // The posterior goes back to the prior from `resetAt` (4.2 s) and is gone
        // by 5.25 s. Before that each observation lands at `arrive` (0.5 s and
        // every 0.45 s after), and a settle must not let another one in.
        "Bayesian update": FinishingSpec(.slowToStop, resets: [4.2..<5.6],
                                         arrivals: [0.5, 0.95, 1.4, 1.85, 2.3, 2.75]),
        // The row slides left from `slideAt` (3.9 s) to the end, a fresh pair
        // arriving from the right.
        "Droplet coalescence": FinishingSpec(.slowToStop, resets: [3.9..<5.0]),
        // The route fades from `fadeAt` (6 s) to the end, leaving the seed and the
        // two food dots.
        "Slime mold maze": FinishingSpec(.slowToStop, resets: [6.0..<7.0]),
        // The open frond fades as the next fiddlehead fades in, from `fadeAt`
        // (5.6 s) to the end.
        "Fern unfurling": FinishingSpec(.slowToStop, resets: [5.6..<6.4]),
        // A half turn in 5 s that is the same at both ends. It is square on, and
        // readable, for the first and last 1.4 s or so (the face is at least 0.8
        // of its width); edge on at 2.5 s, where it is never to stop. The rests
        // are spread through the readable stretches, and the end of the loop is
        // the start (5 s is 0 s). A shell caught turning too far from one dissolves.
        "Diatom": FinishingSpec(.easeToRest([0, 0.35, 0.7, 1.05, 1.4, 3.6, 3.95, 4.3, 4.65], otherwise: .dissolve),
                                loops: true),
    ]

    /// The loop time into the scene's own length.
    static func wrapped(_ time: Double, in loop: Double) -> Double {
        let r = time.truncatingRemainder(dividingBy: loop)
        return r < 0 ? r + loop : r
    }

    /// The gesture for a specimen whose session finished `local` seconds into
    /// its loop, or nil for a specimen with no gesture of its own. `poster` is
    /// asked for only when the answer is a dissolve.
    static func plan(for scene: LabScene, at local: Double, poster: @autoclosure () -> Double) -> FinishingPlan? {
        specs[scene.name].map { plan(for: scene, at: local, spec: $0, poster: poster()) }
    }

    /// The same for a spec given, which is how the choice is tested on its own.
    static func plan(for scene: LabScene, at local: Double, spec: FinishingSpec, poster: @autoclosure () -> Double) -> FinishingPlan {
        let loop = scene.duration
        let start = wrapped(local, in: loop)

        func dissolve() -> FinishingPlan {
            FinishingPlan(scene: scene.name, kind: .dissolve, loop: loop, from: start, to: poster(), duration: dissolveFor)
        }
        func settle(covering advance: Double) -> FinishingPlan {
            // Twice the time covered, within the budget: the clock falls from its own
            // speed to a stop along a curve that covers exactly `advance` in it.
            let duration = min(longest, max(shortest, 2 * advance))
            return FinishingPlan(scene: scene.name, kind: .settle, loop: loop, from: start, to: start + advance, duration: duration)
        }

        // The rotation fades a scene in and out at the ends of its turn: a finish
        // there is already a crossfade.
        let fades = [0..<LabScenes.fade, (loop - LabScenes.fade)..<loop]
        if (spec.resets + fades).contains(where: { $0.contains(start) }) { return dissolve() }

        // How far on it may go: not further than its reach, into a reset, past
        // the end of a loop that does not wrap, or up to something new.
        var limit = start + reach
        for reset in spec.resets where reset.lowerBound > start { limit = min(limit, reset.lowerBound) }
        for arrival in spec.arrivals where arrival > start { limit = min(limit, arrival - margin) }
        if !spec.loops { limit = min(limit, loop) }

        // Hemmed in by a reset or an arrival, the scene still only slows and stops,
        // in what room there is (none at all is a hold): a dissolve to the still would
        // bring in what the stop is there to keep out.
        func slowStop() -> FinishingPlan {
            settle(covering: max(0, min(slowAdvance, limit - start)))
        }
        switch spec.policy {
        case .slowToStop:
            return slowStop()
        case .easeToRest(let rests, let otherwise):
            let ahead = (rests + (spec.loops ? rests.map { $0 + loop } : []))
                .filter { $0 - start >= least && $0 <= limit }
            if let rest = ahead.min() { return settle(covering: rest - start) }
            switch otherwise {
            case .slowToStop: return slowStop()
            case .dissolve: return dissolve()
            }
        }
    }

    /// How much of the scene's time has passed `elapsed` into a gesture of
    /// `duration` that covers `advance`. The clock starts at the speed it was
    /// playing at (a rate of 1) and falls to nothing as `(1 - u)^k`, which
    /// covers `advance` exactly: never backwards, and arriving at rest.
    static func warp(_ elapsed: Double, over duration: Double, covering advance: Double) -> Double {
        guard advance > 0, duration > 0 else { return 0 }
        let u = Ease.clamp(elapsed / duration)
        let k = duration / advance - 1
        return advance * (1 - pow(1 - u, k + 1))
    }

    /// When, in seconds from its start, a gesture of `duration` draws a frame:
    /// every 1/30 s and, last, exactly at its end. Nothing after.
    static func frameTimes(duration: Double) -> [Double] {
        let steps = Int((duration * fps).rounded(.down))
        var times = (0...steps).map { Double($0) / fps }.filter { $0 < duration }
        times.append(duration)
        return times
    }
}
