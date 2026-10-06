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
        static let favorites = "favoriteScenes"
        static let onlyFavorites = "onlyFavoriteScenes"
    }

    @Published var size: SceneSize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: Key.size) }
    }

    /// Which specimens play (SpecimenChoice has the rules), stored as the
    /// categories that are on and the specimens switched off one by one.
    @Published private(set) var choice: SpecimenChoice {
        didSet {
            guard choice != oldValue else { return }
            let defaults = UserDefaults.standard
            // In the enum's order, so the stored array doesn't shuffle between writes.
            defaults.set(SceneGroup.allCases.filter(choice.groups.contains).map(\.rawValue), forKey: Key.groups)
            defaults.set(choice.hidden.sorted(), forKey: Key.hidden)
            cachedRotation = nil
        }
    }

    /// Specimens starred, by name: kept apart from what is on, so a
    /// favourite can be off in the everyday choice and still play when only
    /// favourites do.
    @Published private(set) var favorites: Set<String> {
        didSet {
            guard favorites != oldValue else { return }
            UserDefaults.standard.set(favorites.sorted(), forKey: Key.favorites)
            cachedRotation = nil
        }
    }

    /// Play the favourites and nothing else.
    @Published var onlyFavorites: Bool {
        didSet {
            guard onlyFavorites != oldValue else { return }
            UserDefaults.standard.set(onlyFavorites, forKey: Key.onlyFavorites)
            cachedRotation = nil
        }
    }

    /// What plays. Built when first read after a change, not on every change
    /// (a run of clicks in the grid asks for it once) and not at all while
    /// nothing is showing it. Views read it on every layout, so it is kept.
    var rotation: Rotation {
        if let cachedRotation { return cachedRotation }
        let built = choice.rotation(favorites: favorites, onlyFavorites: onlyFavorites)
        cachedRotation = built
        return built
    }

    private var cachedRotation: Rotation?

    private init() {
        let defaults = UserDefaults.standard
        let groups = defaults.stringArray(forKey: Key.groups).map { Set($0.compactMap(SceneGroup.init(rawValue:))) }
        choice = SpecimenChoice(groups: groups ?? Set(SceneGroup.allCases), hidden: Set(defaults.stringArray(forKey: Key.hidden) ?? []))
        size = defaults.string(forKey: Key.size).flatMap(SceneSize.init(rawValue:)) ?? .medium
        favorites = Set(defaults.stringArray(forKey: Key.favorites) ?? [])
        onlyFavorites = defaults.bool(forKey: Key.onlyFavorites)
    }

    // MARK: Reading

    func isOn(_ scene: LabScene) -> Bool { choice.isOn(scene) }

    /// How many scenes are on.
    var onCount: Int { choice.onCount }

    func state(of group: SceneGroup) -> SpecimenChoice.State { choice.state(of: group) }

    func canTurnOff(_ group: SceneGroup) -> Bool { choice.canTurnOff(group) }

    func canTurnOff(_ scene: LabScene) -> Bool { choice.canTurnOff(scene) }

    func isFavorite(_ scene: LabScene) -> Bool { favorites.contains(scene.name) }

    /// How many favourites there are among the specimens Bench has now.
    var favoriteCount: Int { LabScenes.catalogue.count { favorites.contains($0.name) } }

    /// Whether the favourites are what plays: asked for, and there are some.
    var playsFavorites: Bool { onlyFavorites && favoriteCount > 0 }

    /// Whether a specimen is in what plays: a favourite while only favourites
    /// play, else on.
    func isPlaying(_ scene: LabScene) -> Bool {
        onlyFavorites ? isFavorite(scene) : isOn(scene)
    }

    // MARK: Changing

    func toggleFavorite(_ scene: LabScene) {
        if favorites.contains(scene.name) {
            favorites.remove(scene.name)
        } else {
            favorites.insert(scene.name)
        }
    }

    func toggle(_ group: SceneGroup) { choice.toggle(group) }

    func set(_ group: SceneGroup, on: Bool) { choice.set(group, on: on) }

    func toggle(_ scene: LabScene) { choice.toggle(scene) }

    func playOnly(_ scene: LabScene) { choice.playOnly(scene) }

    func setAll(on: Bool) { choice.setAll(on: on) }
}
