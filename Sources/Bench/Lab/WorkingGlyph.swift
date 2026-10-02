// WorkingGlyph.swift — the working specimen, or under Reduce Motion a still
// one: the panel and the toolbar capsule say a session works either way.
import SwiftUI

struct WorkingGlyph: View {
    let tint: Color
    var rotation: Rotation = .full
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            guard let scene = LabScenes.catalogue.first else { return }
            LabScenes.draw(scene, in: &context, size: size, local: scene.duration * 0.6, tint: tint)
        }
        .accessibilityHidden(true)
    }
}
