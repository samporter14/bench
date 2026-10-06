// SceneSettingsView.swift — Settings > Specimens (DESIGN.md, "Scenes
// settings"), in the Mac's own controls: a heading, the size and the preview
// with its light/dark switch, a checkbox per category, search (by name and by
// what the field guide says), a filter and counts, and every specimen in a
// grid, a section per category, to switch on or off one by one and to star.
// With only favourites playing, a click stars instead. The one cell under the
// pointer lifts to glass and plays alone in the preview, with what the guide
// says about it. The cells on screen play; the rest hold a still.
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
        case all = "All", on = "On", off = "Off", favorites = "Favorites"
    }

    /// Every scene by category, in the catalogue's order within each. Built
    /// once: the catalogue does not change.
    private static let sections: [(group: SceneGroup, scenes: [LabScene])] = SceneGroup.allCases.map { group in
        (group, LabScenes.catalogue.filter { $0.theme.group == group })
    }

    /// By name, to turn a search's ranked names back into specimens.
    private static let byName: [String: LabScene] = Dictionary(
        LabScenes.catalogue.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    /// A run of cells under one heading: a category, or, while searching, the
    /// one ranked list of what was found (`group` nil).
    private struct GridSection {
        let group: SceneGroup?
        let scenes: [LabScene]
    }

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
        .frame(width: 760, height: 776)
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
                    Text(hint)
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
                HStack(spacing: 10) {
                    Text("Play")
                    Picker("Play", selection: $settings.onlyFavorites) {
                        Text("What’s on").tag(false)
                        Text("Only favorites").tag(true)
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
                PreviewText(scene: auditioning, resting: settings.playsFavorites ? "Playing your favorites" : "Playing what’s on")
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

    /// What a click does, which depends on what plays.
    private var hint: String {
        guard settings.onlyFavorites else {
            return "One specimen at a time, in the panel at the corner of your screen. Click a specimen below to switch it on or off, or right-click it to play only that one. Star the ones you like best."
        }
        if settings.favoriteCount == 0 {
            return "Only your favorites play, and you have none yet: click a specimen below to star it. Until then, what’s on plays."
        }
        return "Only your favorites play. Click a specimen below to star it or take its star away. What’s on is kept for when you switch back."
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
        // They pick what's on, which waits while only favourites play.
        .disabled(settings.playsFavorites)
    }

    // MARK: Search and counts

    private var controls: some View {
        HStack(spacing: 12) {
            search
            Picker("Show", selection: $showing) {
                ForEach(Showing.allCases, id: \.self) { choice in
                    // A star for favourites keeps the four segments narrow
                    // enough for the row.
                    if choice == .favorites {
                        Image(systemName: "star").accessibilityLabel(choice.rawValue).tag(choice)
                    } else {
                        Text(choice.rawValue).tag(choice)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show every specimen, only those on or off, or your favorites")
            Spacer(minLength: 12)
            if settings.onlyFavorites {
                Text(settings.favoriteCount == 1 ? "1 favorite" : "\(settings.favoriteCount) favorites")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("\(settings.onCount) of \(LabScenes.catalogue.count) on")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("All") { settings.setAll(on: true) }
                    .disabled(settings.onCount == LabScenes.catalogue.count)
                Button("None") { settings.setAll(on: false) }
            }
        }
    }

    /// The field, and beside it the Topics menu: a click on a topic fills the
    /// search with it, and a click on the one that is filled clears it. Left
    /// out when the guide has no topics.
    private var search: some View {
        HStack(spacing: 6) {
            TextField("Search specimens", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            if !SpecimenGuide.topics.isEmpty {
                Menu {
                    ForEach(SpecimenGuide.topics, id: \.self) { topic in
                        Toggle(SpecimenGuide.title(of: topic), isOn: Binding(
                            get: { SpecimenGuide.words(in: query) == SpecimenGuide.words(in: topic) },
                            set: { query = $0 ? topic : "" }))
                    }
                } label: {
                    Label("Topics", systemImage: "tag")
                        .labelStyle(.iconOnly)
                }
                .fixedSize()
                .help("Search by topic")
            }
        }
    }

    // MARK: The grid

    /// The specimens that pass the filter, and match the search if there is
    /// one. With none, each category's, leaving out categories with none;
    /// every category is here, on or off, so a specimen can be picked from one
    /// that is off. With a search, one list, best match first: a name before
    /// a note, as `SpecimenIndex` ranks them, wherever they sit.
    private var matching: [GridSection] {
        func passes(_ scene: LabScene) -> Bool {
            switch showing {
            case .all: true
            case .on: settings.isPlaying(scene)
            case .off: !settings.isPlaying(scene)
            case .favorites: settings.isFavorite(scene)
            }
        }
        guard !SpecimenGuide.words(in: query).isEmpty else {
            return Self.sections.compactMap { section in
                let scenes = section.scenes.filter(passes)
                return scenes.isEmpty ? nil : GridSection(group: section.group, scenes: scenes)
            }
        }
        let found = SpecimenGuide.index.search(query).compactMap { Self.byName[$0] }.filter(passes)
        return found.isEmpty ? [] : [GridSection(group: nil, scenes: found)]
    }

    @ViewBuilder
    private var grid: some View {
        let shown = matching
        Group {
            if shown.isEmpty {
                if SpecimenGuide.words(in: query).isEmpty {
                    Group {
                        switch showing {
                        case .favorites:
                            ContentUnavailableView("No favorites yet", systemImage: "star",
                                                   description: Text("Hover a specimen and click its star."))
                        case .off: ContentUnavailableView("Every specimen is on", systemImage: "flask")
                        default: ContentUnavailableView("No specimens are on", systemImage: "flask")
                        }
                    }
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
                                    SceneCell(scene: scene, isOn: settings.isPlaying(scene), isFavorite: settings.isFavorite(scene),
                                              choosesFavorites: settings.onlyFavorites,
                                              toggle: {
                                                  if settings.onlyFavorites { settings.toggleFavorite(scene) } else { settings.toggle(scene) }
                                              },
                                              star: { settings.toggleFavorite(scene) },
                                              hovered: { audition(scene, $0) })
                                        .equatable()
                                }
                            } header: {
                                if let group = section.group {
                                    sectionHeader(group)
                                } else {
                                    resultsHeader(section.scenes.count)
                                }
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

    private func favorites(in group: SceneGroup) -> String {
        let count = LabScenes.catalogue.count { $0.theme.group == group && settings.isFavorite($0) }
        return count == 1 ? "1 favorite" : "\(count) favorites"
    }

    private func resultsHeader(_ count: Int) -> some View {
        HStack(spacing: 6) {
            Text("Results")
                .font(.headline)
            Text(count == 1 ? "1 specimen" : "\(count) specimens")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private func sectionHeader(_ group: SceneGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title)
                .font(.headline)
            Text(settings.onlyFavorites ? favorites(in: group) : "\(settings.choice.onCount(in: group)) of \(group.count) on")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

/// One specimen in the grid: its tile (playing while on screen), a clay check
/// when on, a star when a favourite (and an empty one to click under the
/// pointer), and its name. It takes plain values and compares by them, so a
/// click re-runs only the cells that changed. Hover is the cell's own state
/// for the same reason, and the hovered cell is the grid's one glass.
private struct SceneCell: View, Equatable {
    let scene: LabScene
    /// In what plays: on, or a favourite while only favourites play.
    let isOn: Bool
    let isFavorite: Bool
    /// Only favourites play: the click stars, and the check isn't shown,
    /// since the star says the same.
    let choosesFavorites: Bool
    let toggle: () -> Void
    let star: () -> Void
    /// Tells the tab the pointer came or went, for the preview.
    let hovered: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    /// On screen in the scroll view. The lazy grid says so as cells scroll
    /// in and out, so only what can be seen plays, a few dozen at most.
    @State private var visible = false

    nonisolated static func == (a: SceneCell, b: SceneCell) -> Bool {
        a.scene.name == b.scene.name && a.isOn == b.isOn && a.isFavorite == b.isFavorite
            && a.choosesFavorites == b.choosesFavorites
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
        // The star is its own button, laid over the tile's top-left corner
        // (the tile is 58 pt, centred, 6 pt down), so it isn't inside the
        // cell's own button.
        .overlay(alignment: .top) {
            if isFavorite || hovering {
                Button(action: star) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isFavorite ? AnyShapeStyle(Theme.clay) : AnyShapeStyle(.secondary))
                        .frame(width: 17, height: 17)
                        .background(Color(nsColor: .controlBackgroundColor), in: .circle)
                        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .offset(x: -25.5, y: 1)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                .accessibilityLabel(isFavorite ? "Remove \(scene.name) from favorites" : "Add \(scene.name) to favorites")
            }
        }
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
        .accessibilityValue([isOn ? "On" : "Off", isFavorite ? "Favorite" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isToggle)
    }

    /// The right-click menu: the star, then this specimen alone, or its whole
    /// category (not while only favourites play, when what's on waits).
    @ViewBuilder private var menu: some View {
        let settings = SceneSettings.shared
        let group = scene.theme.group
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: star)
        if !choosesFavorites {
            Divider()
            choiceItems(settings, group)
        }
    }

    @ViewBuilder private func choiceItems(_ settings: SceneSettings, _ group: SceneGroup) -> some View {
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
            if isOn && !choosesFavorites {
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

/// What the preview says under the well. With a specimen under the pointer:
/// its name, its caption and its note from the field guide, centred. Without
/// one: `resting`, what the well is playing. The lines reserve their height,
/// so nothing under them moves as the pointer crosses the grid, whether the
/// specimen has a note or not.
private struct PreviewText: View {
    let scene: LabScene?
    let resting: String

    var body: some View {
        let note = scene.flatMap { SpecimenGuide.note(for: $0.name) }
        VStack(spacing: 2) {
            Text(scene?.name ?? resting)
                .font(.callout)
                .foregroundStyle(scene == nil ? .secondary : .primary)
                .lineLimit(1)
            // A space, not an empty string: an empty Text reserves nothing.
            Text(note?.caption ?? (scene == nil ? "Hover a specimen to read about it." : " "))
                .font(.system(size: 12))
                .foregroundStyle(scene == nil ? .tertiary : .secondary)
                .lineLimit(1, reservesSpace: true)
            Text(note?.note ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4, reservesSpace: true)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(width: PreviewWell.textWidth)
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

    /// The width of the text under it, wider than the well so a note takes
    /// four lines at most.
    static let textWidth: CGFloat = 248

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
