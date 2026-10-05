// SpecimenChoice.swift — which specimens play, as a value: the categories
// that are on, less the specimens switched off one by one. SceneSettings keeps
// one in UserDefaults; the rules live here so they can be tested without it.
import Foundation

struct SpecimenChoice: Equatable {
    /// A category's checkbox: every specimen on, some, or none.
    enum State { case on, mixed, off }

    /// The categories that are on. A category that is off stays off as new
    /// specimens arrive in an update, which is why it isn't just `hidden`.
    private(set) var groups: Set<SceneGroup>
    /// Specimens switched off inside a category that is on.
    private(set) var hidden: Set<String>

    /// Everything on.
    static let all = SpecimenChoice(groups: Set(SceneGroup.allCases), hidden: [])

    /// A stored choice, tidied; one that leaves nothing playing (an edited
    /// plist, specimens renamed since) starts afresh, since an empty rotation
    /// can't be played.
    init(groups: Set<SceneGroup>, hidden: Set<String>) {
        self.groups = groups
        self.hidden = hidden
        for group in SceneGroup.allCases { tidy(group) }
        if onCount == 0 { self = .all }
    }

    private static let names: [SceneGroup: Set<String>] = Dictionary(grouping: LabScenes.catalogue, by: \.theme.group)
        .mapValues { Set($0.map(\.name)) }

    private static func names(_ group: SceneGroup) -> Set<String> { names[group] ?? [] }

    // MARK: Reading

    func isOn(_ scene: LabScene) -> Bool {
        groups.contains(scene.theme.group) && !hidden.contains(scene.name)
    }

    var onCount: Int { LabScenes.catalogue.count(where: isOn) }

    func onCount(in group: SceneGroup) -> Int {
        groups.contains(group) ? Self.names(group).subtracting(hidden).count : 0
    }

    func state(of group: SceneGroup) -> State {
        switch onCount(in: group) {
        case 0: .off
        case Self.names(group).count: .on
        default: .mixed
        }
    }

    /// Whether the category can be switched off: not if it holds every
    /// specimen still on.
    func canTurnOff(_ group: SceneGroup) -> Bool { onCount(in: group) < onCount }

    /// Whether the specimen can be switched off: not if it's the last one on.
    func canTurnOff(_ scene: LabScene) -> Bool { !isOn(scene) || onCount > 1 }

    // MARK: Changing

    /// A category's checkbox, as a Mac's mixed checkbox goes: on goes all
    /// off; mixed or off goes all on.
    mutating func toggle(_ group: SceneGroup) {
        set(group, on: state(of: group) != .on)
    }

    mutating func set(_ group: SceneGroup, on: Bool) {
        if on {
            groups.insert(group)
            hidden.subtract(Self.names(group))
        } else if canTurnOff(group) {
            groups.remove(group)
            hidden.subtract(Self.names(group))
        }
    }

    /// One specimen on or off. Switching one on in a category that is off
    /// turns on that specimen alone, not the rest of its category. The last
    /// specimen that is on stays on.
    mutating func toggle(_ scene: LabScene) {
        let group = scene.theme.group
        if isOn(scene) {
            guard onCount > 1 else { return }
            hidden.insert(scene.name)
            tidy(group)
        } else if groups.contains(group) {
            hidden.remove(scene.name)
        } else {
            groups.insert(group)
            hidden.formUnion(Self.names(group).subtracting([scene.name]))
        }
    }

    /// This specimen and nothing else.
    mutating func playOnly(_ scene: LabScene) {
        let group = scene.theme.group
        groups = [group]
        hidden = Self.names(group).subtracting([scene.name])
    }

    /// Everything on, or everything off but one specimen: the first that is
    /// on now, so "None" leaves something the user chose to start from.
    mutating func setAll(on: Bool) {
        if on {
            self = .all
        } else if let keeper = LabScenes.catalogue.first(where: isOn) {
            playOnly(keeper)
        }
    }

    /// A category whose specimens are all switched off one by one is off, so
    /// specimens added to it later stay off too.
    private mutating func tidy(_ group: SceneGroup) {
        guard groups.contains(group), onCount(in: group) == 0 else { return }
        groups.remove(group)
        hidden.subtract(Self.names(group))
    }

    // MARK: Deriving

    /// What plays: the full rotation when nothing is filtered, so the everyday
    /// case is the one already built.
    var rotation: Rotation {
        guard self != .all else { return .full }
        return Rotation(LabScenes.spread(LabScenes.catalogue.filter(isOn)))
    }
}
