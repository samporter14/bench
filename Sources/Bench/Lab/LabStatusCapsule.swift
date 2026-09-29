// LabStatusCapsule.swift — the toolbar's live status (DESIGN.md, Lab status
// capsule): a small scene and a few words, or nothing while idle.
import SwiftUI

/// The toolbar's live status: a small scene and "Working · 4:12" or
/// "2 need you"; hidden when idle. Clicking it opens the first session that
/// waits on the user, otherwise the first that works.
struct LabStatusCapsule: View {
    @ObservedObject private var model = LabModel.shared
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let session = model.waiting.first ?? model.working.first {
            Button {
                model.open(session)
            } label: {
                HStack(spacing: 6) {
                    scene(for: model.waiting.first)
                        .frame(width: Theme.capsuleSceneSize, height: Theme.capsuleSceneSize)
                    words
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .help("Open the session")
        }
    }

    /// The waiting reason's glyph while anything waits, else the chosen
    /// rotation. It stays 18 pt whatever the panel's size.
    @ViewBuilder
    private func scene(for waiting: SessionStatus?) -> some View {
        if let waiting {
            PlayedLoop(glyph: (waiting.waitingReason ?? .other).glyph, tint: colorScheme.sceneInk)
        } else {
            PlayedGlyph(tint: colorScheme.sceneInk, rotation: settings.rotation)
        }
    }

    @ViewBuilder
    private var words: some View {
        if !model.waiting.isEmpty {
            let count = model.waiting.count
            Text(count == 1 ? "1 needs you" : "\(count) need you")
                .foregroundStyle(Theme.clay)
        } else if model.working.count == 1, let session = model.working.first {
            TurnClockText(prefix: "Working", since: session.startedAt)
        } else {
            Text("\(model.working.count) working")
        }
    }
}
