// SceneSettings.swift — STUB, to be replaced by the scenes agent (DESIGN.md,
// "Scenes settings"). Keep every public name and signature.
import SwiftUI

enum SceneSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .small: 64
        case .medium: 88
        case .large: 120
        }
    }
    var title: String { rawValue.capitalized }
}

@MainActor
final class SceneSettings: ObservableObject {
    static let shared = SceneSettings()
    @Published var size: SceneSize = .medium
    @Published var groups: Set<SceneGroup> = Set(SceneGroup.allCases)
    @Published var hidden: Set<String> = []
    var rotation: Rotation { .full }
    private init() {}
}

/// The toolbar's Scenes split button (DESIGN.md, Main window).
struct ScenesToolbarButton: View {
    var body: some View { Text("Scenes") }
}

/// Settings > Scenes (DESIGN.md, Scenes settings).
struct SceneSettingsView: View {
    var body: some View { Text("Scenes") }
}
