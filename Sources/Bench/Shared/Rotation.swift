// Rotation.swift
// ScienceStatus — which scenes play while a session works. The seventeen
// themes roll up into six groups the user can switch on and off; the
// rotation is the chosen groups' scenes, spread so neighbours differ, and
// which scene plays is still a function of the clock alone.

import SwiftUI

/// The groups a user picks from, each a handful of themes.
enum SceneGroup: String, CaseIterable, Codable, Sendable {
    case lab, biology, chemistry, physics, earth, data

    var title: String {
        switch self {
        case .lab: return "Lab"
        case .biology: return "Biology"
        case .chemistry: return "Chemistry"
        case .physics: return "Physics & space"
        case .earth: return "Earth"
        case .data: return "Data"
        }
    }

    /// How many scenes the group holds.
    var count: Int { LabScenes.catalogue.filter { $0.theme.group == self }.count }
}

extension LabScene.Theme {
    var group: SceneGroup {
        switch self {
        case .bench, .life, .food: return .lab
        case .molecular, .cell, .organisms, .protein, .rna, .medicine, .pathways, .microbes: return .biology
        case .chemistry: return .chemistry
        case .physics, .space: return .physics
        case .plants, .weather: return .earth
        case .data: return .data
        }
    }
}

/// An ordered list of scenes played end to end, round and round.
struct Rotation: Sendable, Equatable {
    let scenes: [LabScene]
    let cycle: Double

    init(_ scenes: [LabScene]) {
        self.scenes = scenes
        cycle = scenes.reduce(0) { $0 + $1.duration }
    }

    /// Every scene, the way the rotation always ran.
    static let full = Rotation(LabScenes.all)

    /// The chosen groups' scenes, spread afresh. No groups, or all of them,
    /// is the full rotation.
    static func of(_ groups: Set<SceneGroup>) -> Rotation {
        guard !groups.isEmpty, groups.count < SceneGroup.allCases.count else { return full }
        return Rotation(LabScenes.spread(LabScenes.catalogue.filter { groups.contains($0.theme.group) }))
    }

    /// The scene playing at `t` (seconds on any clock) and how far into it.
    func scene(at t: Double) -> (index: Int, local: Double) {
        var x = t.truncatingRemainder(dividingBy: cycle)
        if x < 0 { x += cycle }
        for (index, scene) in scenes.enumerated() {
            if x < scene.duration { return (index, x) }
            x -= scene.duration
        }
        return (scenes.count - 1, scenes[scenes.count - 1].duration)
    }

    static func == (a: Rotation, b: Rotation) -> Bool {
        a.scenes.map(\.name) == b.scenes.map(\.name)
    }
}

/// A timeline that ticks only when the rotation moves to its next scene, for
/// views that show which scene is playing and nothing else about it.
struct SceneBoundarySchedule: TimelineSchedule {
    let rotation: Rotation

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        let rotation = self.rotation
        return AnyIterator {
            let date = next
            let t = date.timeIntervalSinceReferenceDate
            let (index, local) = rotation.scene(at: t)
            next = Date(timeIntervalSinceReferenceDate: t - local + rotation.scenes[index].duration + 0.01)
            return date
        }
    }
}

/// "Now playing: Illumina sequencing", following the rotation.
struct NowPlayingLine: View {
    let rotation: Rotation
    let palette: ActivityPalette

    var body: some View {
        TimelineView(SceneBoundarySchedule(rotation: rotation)) { timeline in
            let scene = rotation.scenes[rotation.scene(at: timeline.date.timeIntervalSinceReferenceDate).index]
            Text("Now playing: \(scene.name)")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
