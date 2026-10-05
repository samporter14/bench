// SceneSettingsView.swift — Settings > Specimens (DESIGN.md, "Scenes
// settings"), in the Mac's own controls: a heading, the size and the preview
// with its light/dark switch, a checkbox per category, search, a filter and
// counts, and every specimen in a grid, a section per category, to switch on
// or off one by one. The one cell under the pointer lifts to glass and plays
// alone in the preview. The cells on screen play; the rest hold a still.
import SwiftUI

struct SceneSettingsView: View {
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var showing = Showing.all
    /// The specimen under the pointer, which the preview plays alone so it
    /// can be judged at the panel's size.
    @State private var auditioning: LabScene?
    @State private var endAudition: Task<Void, Never>?
    /// Light or dark for this whole tab (its window, while the tab shows);
    /// nil follows the app.
    @State private var previewScheme: ColorScheme?

    private var shownScheme: ColorScheme { previewScheme ?? colorScheme }

    /// Which specimens the grid shows.
    private enum Showing: String, CaseIterable {
        case all = "All", on = "On", off = "Off"
    }

    /// Every scene by category, in the catalogue's order within each. Built
    /// once: the catalogue does not change.
    private static let sections: [(group: SceneGroup, scenes: [LabScene])] = SceneGroup.allCases.map { group in
        (group, LabScenes.catalogue.filter { $0.theme.group == group })
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
                        .font(.title2.weight(.semibold))
                    Text("One specimen at a time, in the panel at the corner of your screen. Click a specimen below to switch it on or off, or right-click it to play only that one.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Text("Size")
                    Picker("Size", selection: $settings.size) {
                        ForEach(SceneSize.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                PreviewWell(size: settings.size, rotation: auditioning.map { Rotation([$0]) } ?? settings.rotation, spring: spring)
                Text(auditioning?.name ?? "Playing what’s on")
                    .font(.callout)
                    .foregroundStyle(auditioning == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: PreviewWell.side)
                Picker("Show this tab in", selection: Binding(get: { shownScheme }, set: { previewScheme = $0 })) {
                    Image(systemName: "sun.max").accessibilityLabel("Ivory").tag(ColorScheme.light)
                    Image(systemName: "moon").accessibilityLabel("Slate").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show this tab in Ivory or Slate")
            }
        }
    }

    // MARK: Categories

    private var categories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(200), spacing: 12, alignment: .leading), count: 3),
                      alignment: .leading, spacing: 6) {
                ForEach(SceneGroup.allCases, id: \.self) { group in
                    CategoryChip(group: group)
                }
            }
        }
    }

    // MARK: Search and counts

    private var controls: some View {
        HStack(spacing: 12) {
            search
            Picker("Show", selection: $showing) {
                ForEach(Showing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show every specimen, or only those on or off")
            Spacer(minLength: 12)
            Text("\(settings.onCount) of \(LabScenes.catalogue.count) on")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("All") { settings.setAll(on: true) }
                .disabled(settings.onCount == LabScenes.catalogue.count)
            Button("None") { settings.setAll(on: false) }
        }
    }

    private var search: some View {
        TextField("Search specimens", text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
    }

    // MARK: The grid

    /// Each category's specimens that pass the filter and whose name holds
    /// the search text, leaving out categories with none. Every category is
    /// here, on or off, so a specimen can be picked from one that is off.
    private var matching: [(group: SceneGroup, scenes: [LabScene])] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return Self.sections.compactMap { section in
            let scenes = section.scenes.filter { scene in
                switch showing {
                case .all: break
                case .on: guard settings.isOn(scene) else { return false }
                case .off: guard !settings.isOn(scene) else { return false }
                }
                return needle.isEmpty || scene.name.localizedCaseInsensitiveContains(needle)
            }
            return scenes.isEmpty ? nil : (section.group, scenes)
        }
    }

    @ViewBuilder
    private var grid: some View {
        let shown = matching
        Group {
            if shown.isEmpty {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(showing == .off ? "Every specimen is on" : "No specimens are on",
                                           systemImage: "flask")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        ForEach(shown, id: \.group) { section in
                            Section {
                                ForEach(section.scenes, id: \.name) { scene in
                                    SceneCell(scene: scene, isOn: settings.isOn(scene), toggle: { settings.toggle(scene) },
                                              hovered: { audition(scene, $0) })
                                        .equatable()
                                }
                            } header: {
                                sectionHeader(section.group)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .clipShape(.rect(cornerRadius: 10))
    }

    /// The preview takes the hovered specimen at once, and goes back to the
    /// rotation a moment after the pointer leaves, so crossing from one cell
    /// to the next doesn't flash the rotation in between.
    private func audition(_ scene: LabScene, _ hovering: Bool) {
        endAudition?.cancel()
        if hovering {
            auditioning = scene
        } else if auditioning?.name == scene.name {
            endAudition = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { auditioning = nil }
            }
        }
    }

    private func sectionHeader(_ group: SceneGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.headline)
            Text("\(settings.choice.onCount(in: group)) of \(group.count) on")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
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
    /// Tells the tab the pointer came or went, for the preview.
    let hovered: (Bool) -> Void

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
        .onHover {
            hovering = $0
            hovered($0)
        }
        .contextMenu { menu }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .help(scene.name)
        .accessibilityLabel(scene.name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    /// The right-click menu: this specimen alone, or its whole category.
    @ViewBuilder private var menu: some View {
        let settings = SceneSettings.shared
        let group = scene.theme.group
        Button("Play Only “\(scene.name)”") { settings.playOnly(scene) }
        Button(isOn ? "Switch Off" : "Switch On", action: toggle)
            .disabled(!settings.canTurnOff(scene))
        Divider()
        Button("Switch On All in \(group.title)") { settings.set(group, on: true) }
            .disabled(settings.state(of: group) == .on)
        Button("Switch Off All in \(group.title)") { settings.set(group, on: false) }
            .disabled(settings.state(of: group) == .off || !settings.canTurnOff(group))
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
        .background(.background, in: .rect(cornerRadius: 13))
        .clipShape(.rect(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color(nsColor: .separatorColor)))
        .overlay(alignment: .topTrailing) {
            if isOn {
                // Slate on clay: 6:1, where white on clay would be under 3.
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Theme.slate)
                    .frame(width: 17, height: 17)
                    .background(Theme.clay, in: .circle)
                    .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2).padding(-2))
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
    static let side = SceneSize.large.points + 28

    var body: some View {
        ZStack {
            PlayedGlyph(tint: colorScheme.sceneInk, rotation: rotation)
                .frame(width: size.points, height: size.points)
                .background(.background, in: .rect(cornerRadius: 14))
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor)))
                .id(size)
                .transition(.opacity)
        }
        .animation(spring, value: size)
        .frame(width: Self.side, height: Self.side)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
