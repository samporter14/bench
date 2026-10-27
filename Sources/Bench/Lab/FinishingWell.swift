// FinishingWell.swift — the Finished card's well, with a closing gesture when
// the session's specimen has one (DESIGN.md, "Finishing gestures", since 1.1.0).
//
// It is the well the working specimen was in, 88 pt at the card's left, so
// the gesture is the working specimen settling where it already was, and the
// plate (`FinishedPlateWell`) is its fallback for every other specimen and for
// every other reason: there is never a second celebration beside it.
import SwiftUI

/// The well of a Finished card: the closing gesture of the specimen that was
/// playing, or, when there is none to play, the plate that fills.
struct FinishedWell: View {
    let session: SessionStatus
    let tint: Color
    var gestures: FinishingGestures = .shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.stillSpecimens) private var stillSpecimens
    /// While nobody is at the Mac the well is the plate's last frame at once.
    @ObservedObject private var hold = SpecimenHold.shared

    var body: some View {
        // The first ask decides for good (`FinishingGestures.claim`), so this can be
        // read as often as SwiftUI likes.
        if let run = gestures.claim(session, allowed: !(systemReduceMotion || stillSpecimens || hold.holds)) {
            // A new turn of the same session is another finish, with a well of its own.
            FinishingSpecimenWell(run: run, tint: tint, now: gestures.now)
                .id(FinishingGestures.id(of: session))
        } else {
            FinishedPlateWell(tint: tint)
        }
    }
}

/// The specimen settling to a stop, or dissolving to its still, in 0.4 to 0.9
/// s, then resting on its last frame. Drawn by a timeline that has exactly the
/// gesture's frames and then no more, so nothing runs after it; a view built
/// after it is over draws the last frame once.
struct FinishingSpecimenWell: View {
    let run: FinishingGestures.Run
    let tint: Color
    var now: () -> Date = { Date() }

    /// By name, for the frames of the run; the catalogue does not change.
    private static let byName = Dictionary(LabScenes.catalogue.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    private var scene: LabScene? { Self.byName[run.plan.scene] }

    var body: some View {
        Group {
            if now().timeIntervalSince(run.began) >= run.plan.duration {
                canvas(elapsed: run.plan.duration)
            } else {
                TimelineView(FinishingSchedule(began: run.began, duration: run.plan.duration)) { _ in
                    canvas(elapsed: now().timeIntervalSince(run.began))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(elapsed: Double) -> some View {
        Canvas { context, size in
            guard let scene else { return }
            FinishingDraw.draw(run.plan.frame(at: elapsed), of: scene, in: &context, size: size, tint: tint)
        }
    }
}

/// The frames of one gesture: every 1/30 s from its start and, last, exactly at
/// its end. There are no entries after that, so the timeline stops asking.
struct FinishingSchedule: TimelineSchedule {
    let began: Date
    let duration: Double

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var dates = FinishingGesture.frameTimes(duration: duration).map { began.addingTimeInterval($0) }.filter { $0 >= start }
        // A display that asks for less (always on, dimmed) gets the last frame alone.
        if mode == .lowFrequency { dates = Array(dates.suffix(1)) }
        var next = dates.makeIterator()
        return AnyIterator { next.next() }
    }
}

enum FinishingDraw {
    /// The specimen's own drawing at the moment the plan asks for. A settle is the
    /// scene at full strength, as the rotation drew it between its fades; a
    /// dissolve is the frame as the rotation showed it giving way to the still.
    static func draw(_ frame: FinishingPlan.Frame, of scene: LabScene, in context: inout GraphicsContext,
                     size: CGSize, tint: Color) {
        switch frame {
        case .scene(let local):
            SpecimenPoster.drawLooping(scene, in: &context, size: size, local: local, tint: tint)
        case .dissolve(let from, let to, let mix):
            // Added together in one layer: ink both frames share stays whole
            // (two half-strength layers laid one over the other would leave it
            // at three quarters halfway), and only what differs fades.
            context.drawLayer { both in
                var shown = both
                shown.opacity = 1 - mix
                shown.drawLayer { layer in
                    LabScenes.draw(scene, in: &layer, size: size, local: from, tint: tint)
                }
                var still = both
                still.opacity = mix
                still.blendMode = .plusLighter
                still.drawLayer { layer in
                    SpecimenPoster.drawLooping(scene, in: &layer, size: size, local: to, tint: tint)
                }
            }
        }
    }
}
