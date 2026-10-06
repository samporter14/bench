// ScenesToolbarButton.swift — the toolbar's Specimens split button (DESIGN.md,
// Main window): a click on its left half shows or hides the panel, and the
// arrow opens a glass popover that sets what plays without opening Settings.
//
// A popover, not a Menu: a SwiftUI Menu in this AppKit window's toolbar kept
// the ticks it was first drawn with, so it showed a size and categories that
// were no longer true, and clicking what looked on turned things on or off
// unseen. The popover is a live view of the settings.
import AppKit
import SwiftUI

/// The split button: one glass capsule, like the readouts beside it.
struct ScenesToolbarButton: View {
    /// A symbol with its colour baked in (not a template), in case the toolbar
    /// redraws template images in its own ink.
    private static let clayFlask: NSImage = {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [NSColor(Theme.clay)])
        let image = NSImage(systemSymbolName: "flask.fill", accessibilityDescription: "Specimens on")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }()

    @AppStorage(SettingsKey.showPanel) private var showPanel = true
    @ObservedObject private var lab = LabModel.shared
    @State private var showing = false

    var body: some View {
        HStack(spacing: 0) {
            // ⌘⇧L stays with the View menu's command: bound here too, the two
            // could both claim the key.
            Button { showPanel.toggle() } label: { label }
                .buttonStyle(ReadoutButtonStyle())
                .help(lab.problem.map { "Can't see your Claude Science sessions: \($0.label)" }
                      ?? (showPanel ? "Hide the specimens panel" : "Show the specimens panel"))
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
                .accessibilityHidden(true)
            Button { showing.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(ReadoutButtonStyle())
            .help("Specimen options")
            .accessibilityLabel("Specimen options")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                SpecimenOptions { showing = false }
            }
            .task {
                if Demo.opensSpecimenOptions {
                    try? await Task.sleep(for: .seconds(1))
                    showing = true
                }
            }
        }
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: 6) {
            if showPanel, lab.problem != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.clay)
                Text("Specimens")
            } else if showPanel {
                // Only the symbol takes the accent: the word stays plain.
                Image(nsImage: Self.clayFlask)
                Text("Specimens")
            } else {
                Image(systemName: "flask")
                    .foregroundStyle(.secondary)
                Text("Specimens off")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .fixedSize()
    }
}

/// What the arrow opens: the panel switch, the size, the categories and the
/// way into Settings > Specimens, all read live from the settings.
private struct SpecimenOptions: View {
    let close: () -> Void

    @AppStorage(SettingsKey.showPanel) private var showPanel = true
    @ObservedObject private var settings = SceneSettings.shared
    @ObservedObject private var lab = LabModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let problem = lab.problem {
                // Without the sessions there is nothing to play or announce.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.clay)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Can't see your sessions: \(problem.label)")
                            .font(.system(size: 12, weight: .medium))
                        Text(problem.hint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Diagnostics…") {
                            close()
                            DiagnosticsWindowController.shared.show()
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }

            Toggle("Show the working specimen", isOn: $showPanel)
                .toggleStyle(.switch)
                .tint(Theme.clay)
                .font(.system(size: 13, weight: .medium))

            LabeledContent("Size") {
                Picker("Size", selection: $settings.size) {
                    ForEach(SceneSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Toggle(isOn: $settings.onlyFavorites) {
                Text("Only favorites")
                Text(settings.favoriteCount == 0
                     ? "Star specimens in Settings → Specimens first."
                     : settings.favoriteCount == 1 ? "Your 1 favorite plays." : "Your \(settings.favoriteCount) favorites play.")
            }
            .toggleStyle(.switch)
            .tint(Theme.clay)
            .font(.system(size: 13, weight: .medium))
            .disabled(settings.favoriteCount == 0 && !settings.onlyFavorites)

            VStack(alignment: .leading, spacing: 8) {
                Text("Categories")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(SceneGroup.allCases, id: \.self) { group in
                        CategoryChip(group: group)
                    }
                }
                Text("\(settings.onCount) of \(LabScenes.catalogue.count) on")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // What's on waits while only favourites play.
            .disabled(settings.playsFavorites)

            Button("Choose specimens one by one…") {
                close()
                SettingsWindow.open(tab: "scenes")
            }
            .buttonStyle(.glass)
        }
        .padding(18)
        .frame(width: 400)
    }
}

/// A category's checkbox, with how many specimens it holds: checked when
/// all are on, a dash when some are (picked one by one in Settings), clear
/// when none are. Checked is unmistakable on every macOS, where a tinted chip
/// was not. The last category on can't be switched off: its box stays
/// checked and greyed (`set` refuses).
struct CategoryChip: View {
    let group: SceneGroup
    @ObservedObject private var settings = SceneSettings.shared

    var body: some View {
        let state = settings.state(of: group)
        // SwiftUI draws a mixed checkbox for a toggle over several sources:
        // two, one on when any specimen is and one when all are. Each writes
        // the whole category, so a click changes it once however many it sets.
        let sources = [
            Binding(get: { state != .off }, set: { settings.set(group, on: $0) }),
            Binding(get: { state == .on }, set: { settings.set(group, on: $0) }),
        ]
        Toggle(sources: sources, isOn: \.self) {
            HStack(spacing: 5) {
                Text(group.title)
                Text(state == .mixed ? "\(settings.choice.onCount(in: group)) of \(group.count)" : "\(group.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .fixedSize()
        }
        .toggleStyle(.checkbox)
        .disabled(state == .on && !settings.canTurnOff(group))
        .help(state == .on && !settings.canTurnOff(group) ? "At least one specimen has to stay on" : group.title)
    }
}
