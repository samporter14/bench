// WorkingGlyph.swift — the working specimen, or under Reduce Motion a still
// one: the panel and the toolbar capsule say a session works either way.
import SwiftUI

struct WorkingGlyph: View {
    let tint: Color
    var rotation: Rotation = .full
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The specimen under Reduce Motion: the first one, the flask. The
    /// panel's caption line names it.
    static var still: LabScene? { LabScenes.catalogue.first }

    var body: some View {
        if reduceMotion {
            StillSpecimen(tint: tint)
        } else {
            PlayedGlyph(tint: tint, rotation: rotation)
        }
    }
}

/// The first specimen (the flask), drawn once, well into its loop.
private struct StillSpecimen: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard let scene = WorkingGlyph.still else { return }
            LabScenes.draw(scene, in: &context, size: size, local: scene.duration * 0.6, tint: tint)
        }
        .accessibilityHidden(true)
    }
}

/// The working panel's right-click menu: star the specimen that is playing,
/// stop it or play only it (or, while only favourites play, take its star
/// away), or choose in Settings. The menu follows the rotation, so it names
/// whatever is playing when it opens.
struct PlayingSpecimenMenu: ViewModifier {
    let active: Bool
    let rotation: Rotation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if !active {
            content
        } else if reduceMotion {
            // A still flask plays nothing to name.
            content.contextMenu { choose }
        } else {
            TimelineView(SceneBoundarySchedule(rotation: rotation)) { timeline in
                let scene = rotation.scenes[rotation.scene(at: timeline.date.timeIntervalSinceReferenceDate).index]
                content.contextMenu {
                    let settings = SceneSettings.shared
                    if settings.playsFavorites {
                        Button("Remove “\(scene.name)” from Favorites") { settings.toggleFavorite(scene) }
                    } else {
                        Button(settings.isFavorite(scene) ? "Remove “\(scene.name)” from Favorites" : "Add “\(scene.name)” to Favorites") {
                            settings.toggleFavorite(scene)
                        }
                        Divider()
                        Button("Don’t Play “\(scene.name)”") { settings.toggle(scene) }
                            .disabled(!settings.isOn(scene) || !settings.canTurnOff(scene))
                        Button("Play Only “\(scene.name)”") { settings.playOnly(scene) }
                    }
                    Divider()
                    choose
                }
            }
        }
    }

    private var choose: some View {
        Button("Choose Specimens…") { SettingsWindow.open(tab: "scenes") }
    }
}
