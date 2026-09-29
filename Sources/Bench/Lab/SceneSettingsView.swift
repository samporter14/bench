// SceneSettingsView.swift — Settings > Specimens, in Solanum (DESIGN.md,
// "Scenes settings"; the Bench Settings canvas): a serif heading, the size and
// the preview with its light/dark switch, the category chips, search and
// counts, and every specimen in a grid on a raised card to switch on or off.
// Structure comes from hairline borders; the one cell under the pointer lifts
// to glass. The cells on screen play; the rest hold a still.
import SwiftUI

struct SceneSettingsView: View {
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    /// Light or dark for this whole tab (its window, while the tab shows);
    /// nil follows the app.
    @State private var previewScheme: ColorScheme?

    private var shownScheme: ColorScheme { previewScheme ?? colorScheme }

    /// Every scene, each category's together so that a chip's switch reads as
    /// one block of the grid. Built once: the catalogue does not change.
    private static let scenes: [LabScene] = SceneGroup.allCases.flatMap { group in
        LabScenes.catalogue.filter { $0.theme.group == group }
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    private var spring: Animation? { reduceMotion ? nil : Theme.spring }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            categories
            controls
            grid
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(width: 760, height: 700)
        .background(Solanum.page)
        // The switch under the preview sets the window's scheme, so the whole
        // tab shows the specimens on light or dark, not a board inside it.
        .preferredColorScheme(previewScheme)
    }

    // MARK: Heading, size and preview

    private var header: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What plays while you work")
                        .font(Solanum.serif(26))
                        .foregroundStyle(Solanum.ink)
                    Text("One specimen at a time, in the panel at the corner of your screen.")
                        .font(.system(size: 14))
                        .foregroundStyle(Solanum.inkMuted)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Overline("Size")
                    SolanumSegmented(selection: $settings.size, options: SceneSize.allCases,
                                     label: { Text($0.title) }, accessibilityName: "Size")
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                PreviewWell(size: settings.size, rotation: settings.rotation, spring: spring)
                SolanumSegmented(
                    selection: Binding(get: { shownScheme }, set: { previewScheme = $0 }),
                    options: [ColorScheme.light, .dark],
                    label: { scheme in
                        Image(systemName: scheme == .light ? "sun.max" : "moon")
                            .accessibilityLabel(scheme == .light ? "Ivory" : "Slate")
                    },
                    accessibilityName: "Show this tab in")
                    .help("Show this tab in Ivory or Slate")
            }
        }
    }

    // MARK: Categories

    private var categories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline("Categories")
            FlowLayout(spacing: 8) {
                ForEach(SceneGroup.allCases, id: \.self) { group in
                    CategoryChip(group: group)
                }
            }
            .animation(spring, value: settings.groups)
        }
    }

    // MARK: Search and counts

    private var controls: some View {
        HStack(spacing: 12) {
            search
            Spacer(minLength: 12)
            Text("\(settings.onCount) of \(LabScenes.catalogue.count) on")
                .font(.system(size: 13))
                .foregroundStyle(Solanum.inkMuted)
                .monospacedDigit()
            Button("All") { settings.setAll(on: true) }
                .disabled(settings.onCount == LabScenes.catalogue.count)
            Button("None") { settings.setAll(on: false) }
        }
        .buttonStyle(SolanumButtonStyle())
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Solanum.inkMuted)
            TextField("Search specimens", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Solanum.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Solanum.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(width: 260, height: 32)
        .background(Solanum.raised, in: .capsule)
        .overlay(Capsule().strokeBorder(Solanum.strong))
    }

    // MARK: The grid

    /// The scenes in the categories that are on whose name holds the search
    /// text, in the grid's order. A category that is off leaves the grid, so
    /// the grid is what can play; its scenes come back with its chip.
    private var matching: [LabScene] {
        let inGroups = Self.scenes.filter { settings.groups.contains($0.theme.group) }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return inGroups }
        return inGroups.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    @ViewBuilder
    private var grid: some View {
        let shown = matching
        Group {
            if shown.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        ForEach(shown, id: \.name) { scene in
                            SceneCell(scene: scene, isOn: settings.isOn(scene)) { settings.toggle(scene) }
                                .equatable()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .solanumCard(radius: 14)
        .clipShape(.rect(cornerRadius: 14))
    }
}

/// One specimen in the grid: its tile (playing while on screen), a clay badge
/// when on, and its name. It takes plain values and compares by them, so a
/// click re-runs only the cells that changed. Hover is the cell's own state
/// for the same reason, and the hovered cell is the grid's one glass.
private struct SceneCell: View, Equatable {
    let scene: LabScene
    let isOn: Bool
    let toggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    /// On screen in the scroll view. The lazy grid says so as cells scroll
    /// in and out, so only what can be seen plays, a few dozen at most.
    @State private var visible = false

    nonisolated static func == (a: SceneCell, b: SceneCell) -> Bool {
        a.scene.name == b.scene.name && a.isOn == b.isOn
    }

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                tile
                Text(scene.name)
                    .font(.system(size: 11))
                    .foregroundStyle(Solanum.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            // Off is dimmed, but a hovered specimen plays at full strength so
            // it can be judged before it is switched on.
            .opacity(isOn || hovering ? 1 : 0.45)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background {
            if hovering {
                Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
            }
        }
        .onHover { hovering = $0 }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .help(scene.name)
        .accessibilityLabel(scene.name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var tile: some View {
        ZStack {
            if hovering || (visible && !reduceMotion) {
                SceneLive(scene: scene, ink: colorScheme.sceneInk, fps: hovering ? 30 : 20)
            } else {
                SceneStill(scene: scene, ink: colorScheme.sceneInk)
                    .equatable()
            }
        }
        .frame(width: 58, height: 58)
        .background(Solanum.page, in: .rect(cornerRadius: 13))
        .clipShape(.rect(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Solanum.hairline))
        .overlay(alignment: .topTrailing) {
            if isOn {
                // Slate on clay: 6:1, where white on clay would be under 3.
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Theme.slate)
                    .frame(width: 17, height: 17)
                    .background(Theme.clay, in: .circle)
                    .overlay(Circle().strokeBorder(Solanum.raised, lineWidth: 2).padding(-2))
                    .offset(x: 5, y: -5)
            }
        }
    }
}

/// A scene drawn live, frame by frame. Nothing is kept between frames, so a
/// grid of these costs a little CPU while on screen and no memory: the
/// panel's player renders a second and more ahead, which a few dozen cells
/// at once would turn into hundreds of megabytes.
private struct SceneLive: View {
    let scene: LabScene
    let ink: Color
    let fps: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: scene.duration)
                LabScenes.draw(scene, in: &context, size: size, local: t, tint: ink)
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


/// The panel's well as it will look, playing what is on, on a raised card in
/// the tab's scheme. A new size fades in a new well instead of stretching the
/// old one: a scene view draws its frames again at every size it is laid out
/// in, so a spring would make it draw them again on every tick.
private struct PreviewWell: View {
    let size: SceneSize
    let rotation: Rotation
    let spring: Animation?

    @Environment(\.colorScheme) private var colorScheme

    /// Holds the largest well, so nothing around it moves when the size does.
    private static let side = SceneSize.large.points + 28

    var body: some View {
        ZStack {
            PlayedGlyph(tint: colorScheme.sceneInk, rotation: rotation)
                .frame(width: size.points, height: size.points)
                .background(Solanum.page, in: .rect(cornerRadius: 14))
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Solanum.hairline))
                .id(size)
                .transition(.opacity)
        }
        .animation(spring, value: size)
        .frame(width: Self.side, height: Self.side)
        .solanumCard(radius: 18)
    }
}
