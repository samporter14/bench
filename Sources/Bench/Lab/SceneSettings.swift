// SceneSettings.swift — which scenes play, and how large (DESIGN.md, "Scenes
// settings"). The panel, the toolbar capsule, the toolbar menu and the
// Settings tab all read and write this one object, so a change in any of them
// shows in the others at once.
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

    private enum Key {
        static let size = "sceneSize"
        static let groups = "sceneGroups"
        static let hidden = "hiddenScenes"
    }

    @Published var size: SceneSize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: Key.size) }
    }

    /// The categories that are on. A scene plays only if its category is on
    /// and it isn't in `hidden`.
    @Published var groups: Set<SceneGroup> {
        didSet {
            // In the enum's order, so the stored array doesn't shuffle between writes.
            let stored = SceneGroup.allCases.filter(groups.contains).map(\.rawValue)
            UserDefaults.standard.set(stored, forKey: Key.groups)
            cachedRotation = nil
        }
    }

    /// Names of the scenes switched off one by one.
    @Published var hidden: Set<String> {
        didSet {
            UserDefaults.standard.set(hidden.sorted(), forKey: Key.hidden)
            cachedRotation = nil
        }
    }

    /// What plays. Built when first read after a change, not on every change
    /// (a run of clicks in the grid asks for it once) and not at all while
    /// nothing is showing it. Views read it on every layout, so it is kept.
    var rotation: Rotation {
        if let cachedRotation { return cachedRotation }
        let built = Self.rotation(groups: groups, hidden: hidden)
        cachedRotation = built
        return built
    }

    private var cachedRotation: Rotation?

    private init() {
        let defaults = UserDefaults.standard
        var groups = Set(SceneGroup.allCases)
        if let stored = defaults.stringArray(forKey: Key.groups) {
            groups = Set(stored.compactMap(SceneGroup.init(rawValue:)))
        }
        var hidden = Set(defaults.stringArray(forKey: Key.hidden) ?? [])
        // A stored choice that leaves nothing playing (an edited plist, scenes
        // renamed since) starts afresh: an empty rotation cannot be played.
        if Self.count(groups: groups, hidden: hidden) == 0 {
            groups = Set(SceneGroup.allCases)
            hidden = []
        }
        size = defaults.string(forKey: Key.size).flatMap(SceneSize.init(rawValue:)) ?? .medium
        self.groups = groups
        self.hidden = hidden
    }

    // MARK: Reading

    func isOn(_ scene: LabScene) -> Bool {
        groups.contains(scene.theme.group) && !hidden.contains(scene.name)
    }

    /// How many scenes are on.
    var onCount: Int { Self.count(groups: groups, hidden: hidden) }

    /// Whether the category can be flipped: switching off the one that holds
    /// the last scenes would leave nothing to play.
    func canToggle(_ group: SceneGroup) -> Bool {
        !groups.contains(group) || Self.count(groups: groups.subtracting([group]), hidden: hidden) > 0
    }

    // MARK: Changing

    func toggle(_ group: SceneGroup) {
        guard canToggle(group) else { return }
        if groups.contains(group) {
            groups.remove(group)
        } else {
            groups.insert(group)
        }
    }

    /// Flips one scene. In a category that is off, the scene shows dimmed and a
    /// click brings the category back, this scene included. The last scene
    /// that is on stays on.
    func toggle(_ scene: LabScene) {
        let group = scene.theme.group
        if !groups.contains(group) {
            hidden.remove(scene.name)
            groups.insert(group)
        } else if hidden.contains(scene.name) {
            hidden.remove(scene.name)
        } else if onCount > 1 {
            hidden.insert(scene.name)
        }
    }

    /// Everything on, or everything off but one scene: the first one that is
    /// on now, so "None" leaves something the user chose to start from.
    func setAll(on: Bool) {
        guard !on else {
            groups = Set(SceneGroup.allCases)
            hidden = []
            return
        }
        let keeper = LabScenes.catalogue.first(where: isOn) ?? LabScenes.catalogue[0]
        let group = keeper.theme.group
        groups = [group]
        hidden = Set(LabScenes.catalogue.filter { $0.theme.group == group && $0.name != keeper.name }.map(\.name))
    }

    // MARK: Deriving

    private static func count(groups: Set<SceneGroup>, hidden: Set<String>) -> Int {
        LabScenes.catalogue.count(where: { groups.contains($0.theme.group) && !hidden.contains($0.name) })
    }

    /// The full rotation when nothing is filtered, so the everyday case is the
    /// one already built. Never empty: nothing chosen falls back to everything.
    private static func rotation(groups: Set<SceneGroup>, hidden: Set<String>) -> Rotation {
        guard !hidden.isEmpty || groups.count < SceneGroup.allCases.count else { return .full }
        let chosen = LabScenes.catalogue.filter { groups.contains($0.theme.group) && !hidden.contains($0.name) }
        return chosen.isEmpty ? .full : Rotation(LabScenes.spread(chosen))
    }
}
