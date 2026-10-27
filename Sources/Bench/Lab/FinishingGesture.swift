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
    /// Where a dissolve ends when the poster is the wrong frame to end on: the
    /// frame the reset is going to, for a scene whose still is its fullest
    /// moment (more evidence, a whole route), or the finished picture, for one
    /// whose still is caught halfway (a stack a section short). Nil is the poster.
    let dissolveTo: Double?

    init(_ policy: Policy, resets: [Range<Double>] = [], arrivals: [Double] = [], loops: Bool = false,
         dissolveTo: Double? = nil) {
        self.policy = policy
        self.resets = resets
        self.arrivals = arrivals
        self.loops = loops
        self.dissolveTo = dissolveTo
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

    /// How the scenes of batches R and S close, read from their code (the names
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
        // every 0.45 s after), and a settle must not let another one in. Its
        // still is the tallest posterior with every observation, so a finish in
        // the reset or a fade goes on to the prior alone (0.35 s, before the
        // first arrival), where the reset was going: no confidence is added.
        "Bayesian update": FinishingSpec(.slowToStop, resets: [4.2..<5.6],
                                         arrivals: [0.5, 0.95, 1.4, 1.85, 2.3, 2.75], dissolveTo: 0.35),
        // The row slides left from `slideAt` (3.9 s) to the end, a fresh pair
        // arriving from the right.
        "Droplet coalescence": FinishingSpec(.slowToStop, resets: [3.9..<5.0]),
        // The route fades from `fadeAt` (6 s) to the end, leaving the seed and the
        // two food dots. Its still is the whole route, so a finish in the fade
        // lets the last faint branches go (0.35 s: the bare maze, the seed and
        // the food) rather than bringing the route back.
        "Slime mold maze": FinishingSpec(.slowToStop, resets: [6.0..<7.0], dissolveTo: 0.35),
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

        // Batch S.
        // The trace scrolls exactly five peak spacings a loop and its heights
        // repeat every five, so the loop is seamless; a call's tick may pop in
        // as it slows, as the trace really does call the next base.
        "Sanger chromatogram": FinishingSpec(.slowToStop, loops: true),
        // A steady state of eight replicates, one begun every `interval`
        // (0.625 s) and drawn in over `drawFor` (0.5 s). It comes to rest on a
        // replicate just drawn, lying whole over the bars, when one is near.
        "Posterior predictive check": FinishingSpec(.easeToRest([0.5, 1.125, 1.75, 2.375, 3.0, 3.625, 4.25, 4.875],
                                                                otherwise: .slowToStop), loops: true),
        // The stage slides the drop away from `slideAt` (3.9 s) while the next
        // bead grows on the needle; the tangent (`tangentAt`, 2 s) and the arc
        // (`arcAt`, 2.4 s) are what a settle must not draw in.
        "Contact angle": FinishingSpec(.slowToStop, resets: [3.9..<5.0], arrivals: [2.0, 2.4]),
        // Each section draws in as the plane comes to its slab (0.05 s before
        // `arrive`); from `returnAt` (4.05 s) to `returnEnd` (5.15 s) the plane
        // rises and they fade. Its still (3.24 s) is the stack a section short,
        // so a finish in the rise goes on to the whole stack (4 s).
        "Confocal z-stack": FinishingSpec(.slowToStop, resets: [4.05..<5.15],
                                          arrivals: [0.7, 1.4, 2.1, 2.8, 3.5], dissolveTo: 4.0),
        // The view pans one flower along from `panAt` (3.5 s) for `panFor`
        // (1.6 s), the bee riding the next flower back to where it began.
        "Pollination": FinishingSpec(.slowToStop, resets: [3.5..<5.1]),
        // The weave, the cilia and the vacuoles are all whole cycles of the
        // loop; nothing new ever appears.
        "Paramecium": FinishingSpec(.slowToStop, loops: true),
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
            FinishingPlan(scene: scene.name, kind: .dissolve, loop: loop, from: start, to: spec.dissolveTo ?? poster(), duration: dissolveFor)
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
