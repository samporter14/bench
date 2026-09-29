// SceneSettingsView.swift — Settings > Scenes (DESIGN.md, "Scenes settings" and
// "Where the glass goes"): the size, the categories, and every scene in a grid
// to switch on or off. Glass is for the few surfaces that are touched (the
// preview well, the chips, the search capsule, the buttons and the one cell
// under the pointer); the 474 cells at rest are plain fills.
import SwiftUI

struct SceneSettingsView: View {
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    /// Every scene, each category's together so that a chip's switch reads as
    /// one block of the grid. Built once: the catalogue does not change.
    private static let scenes: [LabScene] = SceneGroup.allCases.flatMap { group in
        LabScenes.catalogue.filter { $0.theme.group == group }
    }

    private static let columns = [GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 8)]

    /// The preview well holds the largest size, so the rows below never move
    /// when the size changes.
    private static let previewSide = SceneSize.large.points + 24

    private var spring: Animation? { reduceMotion ? nil : Theme.spring }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sizeRow
            chips
            controls
            grid
        }
        .padding(20)
        .frame(width: 760, height: 640)
    }

    // MARK: Size

    private var sizeRow: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Size")
                    .font(.system(size: 15, weight: .semibold))
                Picker("Size", selection: $settings.size) {
                    ForEach(SceneSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                Text("How large a scene plays in the panel.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            preview
        }
    }

    /// The panel's well as it will look, playing what is switched on. A new
    /// size fades in a new well instead of stretching the old one: a scene
    /// view draws its frames again at every size it is laid out in, so a
    /// spring would make it draw them again on every tick.
    private var preview: some View {
        ZStack {
            PlayedGlyph(tint: colorScheme.sceneInk, rotation: settings.rotation)
                .frame(width: settings.size.points, height: settings.size.points)
                .background(Color.primary.opacity(0.06))
                .clipShape(.rect(cornerRadius: Theme.panelCorner - Theme.panelPadding))
                .id(settings.size)
                .transition(.opacity)
        }
        .animation(spring, value: settings.size)
        .frame(width: Self.previewSide, height: Self.previewSide)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: Categories

    private var chips: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(SceneGroup.allCases, id: \.self) { group in
                    chip(group)
                }
            }
        }
        .animation(spring, value: settings.groups)
    }

    private func chip(_ group: SceneGroup) -> some View {
        let on = settings.groups.contains(group)
        return Button {
            settings.toggle(group)
        } label: {
            HStack(spacing: 6) {
                Text(group.title)
                Text("\(group.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(Theme.clay.opacity(0.35)).interactive() : .regular.interactive(),
                     in: .capsule)
        .help(settings.canToggle(group) ? group.title : "At least one scene has to stay on")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: Search and counts

    private var controls: some View {
        HStack(spacing: 12) {
            search
            Spacer(minLength: 12)
            Text("\(settings.onCount) of \(LabScenes.catalogue.count) on")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button("All") { settings.setAll(on: true) }
                        .disabled(settings.onCount == LabScenes.catalogue.count)
                    Button("None") { settings.setAll(on: false) }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search scenes", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: 260)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: The grid

    /// The scenes whose name holds the search text, in the grid's order.
    private var matching: [LabScene] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Self.scenes }
        return Self.scenes.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    @ViewBuilder
    private var grid: some View {
        let shown = matching
        if shown.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(shown, id: \.name) { scene in
                        SceneCell(scene: scene, isOn: settings.isOn(scene)) { settings.toggle(scene) }
                            .equatable()
                    }
                }
            }
        }
    }
}

/// One scene in the grid. It takes plain values and compares by them, so a
/// click re-runs only the cells that changed rather than every visible still.
/// Hover is the cell's own state for the same reason.
private struct SceneCell: View, Equatable {
    let scene: LabScene
    let isOn: Bool
    let toggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    nonisolated static func == (a: SceneCell, b: SceneCell) -> Bool {
        a.scene.name == b.scene.name && a.isOn == b.isOn
    }

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 4) {
                well
                Text(scene.name)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            // Off is dimmed, but a hovered scene plays at full strength so it
            // can be judged before it is switched on.
            .opacity(isOn || hovering ? 1 : 0.35)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background {
            // The only glass in the grid: 474 glass layers would cost frames.
            if hovering {
                Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
        }
        .onHover { hovering = $0 }
        .help(scene.name)
        .accessibilityLabel(scene.name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    /// The still, or the scene playing while the pointer is on it, with a clay
    /// check at the corner when it is on.
    private var well: some View {
        ZStack {
            if hovering {
                PlayedGlyph(tint: colorScheme.sceneInk, rotation: Rotation([scene]))
            } else {
                SceneStill(scene: scene, ink: colorScheme.sceneInk)
                    .equatable()
            }
        }
        .frame(width: 56, height: 56)
        .background(Color.primary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Theme.clay, in: .circle)
                    .offset(x: 4, y: -4)
            }
        }
    }
}

/// A scene's still, drawn well into it (three fifths of the way, past the
/// fade-in) with a Canvas: no timers, and no frames kept.
private struct SceneStill: View, Equatable {
    let scene: LabScene
    let ink: Color

    nonisolated static func == (a: SceneStill, b: SceneStill) -> Bool {
        a.scene.name == b.scene.name && a.ink == b.ink
    }

    var body: some View {
        Canvas { context, size in
            LabScenes.draw(scene, in: &context, size: size, local: scene.duration * 0.6, tint: ink)
        }
    }
}
