// WorkingGlyph.swift — the working specimen, or under Reduce Motion a still
// one: the panel and the toolbar capsule say a session works either way. It
// is also still while nobody is at the Mac (SpecimenHold).
import SwiftUI

struct WorkingGlyph: View {
    let tint: Color
    var rotation: Rotation = .full
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nobody has touched the Mac for ten minutes: a still, not the rotation.
    @ObservedObject private var hold = SpecimenHold.shared

    /// The specimen under Reduce Motion: the first one, the flask. The
    /// panel's caption line names it.
    static var still: LabScene? { LabScenes.catalogue.first }

    var body: some View {
        // The ZStack keeps the view's identity across the switch, so the
        // watching below starts and stops with the glyph, not with each face.
        ZStack {
            if reduceMotion {
                StillSpecimen(tint: tint)
            } else if hold.holds {
                // The scene the rotation was in when the hold began, at the
                // middle of it, as a covered window's specimen is held.
                StillSpecimen(tint: tint, scene: hold.scene(in: rotation, at: .now), at: 0.5)
            } else {
                PlayedGlyph(tint: tint, rotation: rotation)
            }
        }
        .modifier(WatchesHold(active: !reduceMotion))
    }
}

/// Asks `SpecimenHold` to look for as long as a specimen is on screen that
/// could be told to hold. Under Reduce Motion none moves, so none looks.
struct WatchesHold: ViewModifier {
    let active: Bool
    @State private var watching = false

    func body(content: Content) -> some View {
        content
            .onAppear { set(active) }
            .onDisappear { set(false) }
            .onChange(of: active) { _, now in set(now) }
    }

    private func set(_ on: Bool) {
        guard on != watching else { return }
        watching = on
        if on { SpecimenHold.shared.watch() } else { SpecimenHold.shared.unwatch() }
    }
}

/// A scene drawn once, `at` this far through it (the flask under Reduce
/// Motion, well into its loop; the held specimen at its middle).
private struct StillSpecimen: View {
    let tint: Color
    var scene: LabScene? = WorkingGlyph.still
    var at = 0.6

    var body: some View {
        Canvas { context, size in
            guard let scene else { return }
            LabScenes.draw(scene, in: &context, size: size, local: scene.duration * at, tint: tint)
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
    @ObservedObject private var hold = SpecimenHold.shared

    func body(content: Content) -> some View {
        if !active {
            content
        } else if reduceMotion {
            // A still flask plays nothing to name.
            content.contextMenu { choose }
        } else {
            TimelineView(SceneBoundarySchedule(rotation: rotation)) { timeline in
                let scene = hold.scene(in: rotation, at: timeline.date)
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
