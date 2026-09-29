// ScenesToolbarButton.swift — the toolbar's Scenes split button (DESIGN.md,
// Main window): a click shows or hides the panel, and the menu beside it sets
// what plays without opening Settings.
import AppKit
import SwiftUI

/// A click toggles the panel; the menu holds the panel switch, the size, one
/// switch per category and the way into Settings > Scenes. The label says
/// which state the panel is in, since a toggle in a toolbar has no other cue.
struct ScenesToolbarButton: View {
    /// The toolbar redraws symbol images as flat templates in its own ink, so a
    /// `foregroundStyle` is ignored there. A symbol with its colour baked in
    /// (not a template) keeps the clay.
    private static let clayFlask: NSImage = {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [NSColor(Theme.clay)])
        let image = NSImage(systemSymbolName: "flask.fill", accessibilityDescription: "Scenes on")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }()

    @AppStorage(SettingsKey.showPanel) private var showPanel = true
    @AppStorage(SettingsKey.settingsTab) private var settingsTab = "general"
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            // ⌘⇧L stays with the View menu's command: bound here too, the two
            // could both claim the key.
            Toggle("Show scenes panel", isOn: $showPanel)
            Section("Size") {
                Picker("Size", selection: $settings.size) {
                    ForEach(SceneSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Categories") {
                ForEach(SceneGroup.allCases, id: \.self) { group in
                    Toggle("\(group.title) · \(group.count)", isOn: binding(for: group))
                        .disabled(!settings.canToggle(group))
                }
            }
            Divider()
            Button("Choose scenes…") {
                settingsTab = "scenes"
                openSettings()
                NSApp.activate()
            }
        } label: {
            if showPanel {
                // Only the symbol takes the accent: the word stays plain.
                Label {
                    Text("Scenes")
                } icon: {
                    Image(nsImage: Self.clayFlask)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Label("Scenes off", systemImage: "flask")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }
        } primaryAction: {
            showPanel.toggle()
        }
        .help("Show or hide the scenes panel")
    }

    /// A category's switch. The last one on is disabled, and `toggle` refuses
    /// it too, so a stray call cannot empty the rotation.
    private func binding(for group: SceneGroup) -> Binding<Bool> {
        Binding(
            get: { settings.groups.contains(group) },
            set: { _ in settings.toggle(group) })
    }
}
