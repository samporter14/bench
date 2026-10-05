// LabStatusCapsule.swift — the toolbar's live status (DESIGN.md, Lab status
// capsule): a small scene and a few words, or a quiet Activity while idle.
import SwiftUI

/// The toolbar's live status: a small scene and "Working · 4:12" or
/// "2 need you", or "Recent" once something has happened, "Activity" before
/// then. Clicking it opens the activity list, where each session is a row.
struct LabStatusCapsule: View {
    @ObservedObject private var model = LabModel.shared
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                if model.waiting.isEmpty, model.working.isEmpty {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                } else {
                    scene(for: model.waiting.first)
                        .frame(width: Theme.capsuleSceneSize, height: Theme.capsuleSceneSize)
                }
                words
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .help("Show every session")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ActivityList { showing = false }
        }
        .task {
            if Demo.opensActivity {
                try? await Task.sleep(for: .seconds(1))
                showing = true
            }
        }
    }

    /// The waiting reason's glyph while anything waits, else the chosen
    /// rotation. It stays 18 pt whatever the panel's size.
    @ViewBuilder
    private func scene(for waiting: SessionStatus?) -> some View {
        if let waiting {
            PlayedLoop(glyph: (waiting.waitingReason ?? .other).glyph, tint: colorScheme.sceneInk)
        } else {
            WorkingGlyph(tint: colorScheme.sceneInk, rotation: settings.rotation)
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
        } else if model.working.count > 1 {
            Text("\(model.working.count) working")
        } else {
            Text(model.recent.isEmpty ? "Activity" : "Recent")
                .foregroundStyle(.secondary)
        }
    }
}
