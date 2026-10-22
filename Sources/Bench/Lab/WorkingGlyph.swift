// WorkingGlyph.swift — the working specimen, or under Reduce Motion a still
// one: the panel and the toolbar capsule say a session works either way. It
// is also still while nobody is at the Mac (SpecimenHold).
import SwiftUI

struct WorkingGlyph: View {
    let tint: Color
    var rotation: Rotation = .full
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Stills, as Reduce Motion asks, for a view that is drawn once (a snapshot).
    @Environment(\.stillSpecimens) private var stillSpecimens
    private var reduceMotion: Bool { systemReduceMotion || stillSpecimens }
    /// Nobody has touched the Mac for ten minutes: a still, not the rotation.
    @ObservedObject private var hold = SpecimenHold.shared

    /// The specimen under Reduce Motion: the first one, the flask. The
    /// panel's caption line names it.
    static var still: LabScene? { LabScenes.catalogue.first }

    /// The specimen under Reduce Motion for what plays: the one specimen of a
    /// rotation of one (a specimen picked for its session, SessionSpecimen),
    /// else the flask.
    static func still(in rotation: Rotation) -> LabScene? {
        rotation.scenes.count == 1 ? rotation.scenes[0] : still
    }

    var body: some View {
        // The ZStack keeps the view's identity across the switch, so the
        // watching below starts and stops with the glyph, not with each face.
        ZStack {
            if reduceMotion {
                StillSpecimen(tint: tint, scene: Self.still(in: rotation))
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

private struct StillSpecimensKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Every specimen below draws a still, as under Reduce Motion: for a
    /// picture of the panel taken offscreen, where a playing layer would not
    /// be painted. The system's own setting can't be set from a test.
    var stillSpecimens: Bool {
        get { self[StillSpecimensKey.self] }
        set { self[StillSpecimensKey.self] = newValue }
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

/// A scene drawn once: the flask under Reduce Motion at its poster time
/// (SpecimenPoster), or the held specimen `at` this far through it (its
/// middle, as a covered window's specimen is held).
private struct StillSpecimen: View {
    let tint: Color
    var scene: LabScene? = WorkingGlyph.still
    /// How far through the scene; nil is its poster time.
    var at: Double? = nil
    @State private var poster: Double?

    var body: some View {
        Canvas { context, size in
            guard let scene else { return }
            let local = at.map { scene.duration * $0 }
                ?? poster ?? SpecimenPosters.shared.cached(scene) ?? SpecimenPoster.fallback(scene)
            LabScenes.draw(scene, in: &context, size: size, local: local, tint: tint)
        }
        .accessibilityHidden(true)
        .task(id: scene?.name) {
            guard at == nil, let scene, SpecimenPosters.shared.cached(scene) == nil else { return }
            poster = await SpecimenPosters.shared.time(for: scene)
        }
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
