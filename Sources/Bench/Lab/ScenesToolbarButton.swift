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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            Toggle("Show the specimens panel", isOn: $showPanel)
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .medium))

            VStack(alignment: .leading, spacing: 8) {
                heading("Size")
                Picker("Size", selection: $settings.size) {
                    ForEach(SceneSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                heading("Categories")
                GlassEffectContainer(spacing: 8) {
                    // Two columns keep the popover narrow.
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                ForEach(SceneGroup.allCases[(row * 2)..<(row * 2 + 2)], id: \.self) { group in
                                    CategoryChip(group: group)
                                }
                            }
                        }
                    }
                }
                .animation(reduceMotion ? nil : Theme.spring, value: settings.groups)
                Text("\(settings.onCount) of \(LabScenes.catalogue.count) on")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button("Choose specimens…") {
                close()
                SettingsWindow.open(tab: "scenes")
            }
            .buttonStyle(.glass)
        }
        .padding(18)
        .frame(width: 330)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

/// A category's switch: a glass capsule, clay-tinted while on, with the
/// category's count. The last one on can't be switched off (`toggle` refuses).
struct CategoryChip: View {
    let group: SceneGroup
    @ObservedObject private var settings = SceneSettings.shared

    var body: some View {
        let on = settings.groups.contains(group)
        Button {
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
        .help(settings.canToggle(group) ? group.title : "At least one specimen has to stay on")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
