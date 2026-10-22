// UpdateToolbarButton.swift — the toolbar's Update button and the popover it
// opens (DESIGN.md, Update check). It is in the toolbar only while an update
// is on offer (`UpdateChecker.offered`: a newer release that wasn't skipped),
// so a Capsid that is up to date shows nothing new. The popover says what is
// out and what Install does, and has Install and Reopen, Release Notes and
// Skip This Version.
//
// `UpdateOfferView` is told everything it shows and given its actions, so a
// test can draw it without the checker or the user's settings.
import AppKit
import SwiftUI

/// The button, in a capsule of its own to the left of the readouts. A clay
/// arrow and the word Update: seen out of the corner of the eye, not a badge.
struct UpdateToolbarButton: View {
    let update: AvailableUpdate
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var showing = false

    /// The arrow with its colour baked in, as the Specimens button's flask is:
    /// the toolbar draws template symbols in its own ink.
    private static let clayArrow: NSImage = {
        let size = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let clay = NSImage.SymbolConfiguration(paletteColors: [NSColor(Theme.clay)])
        let image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(size.applying(clay)) ?? NSImage()
        image.isTemplate = false
        return image
    }()

    private var headline: String { "Capsid \(update.version) is available" }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(nsImage: Self.clayArrow)
                    .accessibilityHidden(true)
                Text("Update")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(ReadoutButtonStyle())
        .accessibilityLabel("Update")
        .accessibilityValue(headline)
        .help(headline)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            UpdateOfferView(
                update: update, currentVersion: updates.currentVersion,
                canInstall: UpdateRules.canInstall(from: Bundle.main.bundleURL), installing: updates.installing,
                install: { updates.install() },
                releaseNotes: {
                    showing = false
                    UpdatePrompts.openReleaseNotes(update)
                },
                skip: {
                    showing = false
                    updates.skip(update)
                })
        }
    }
}

/// What the popover holds: which version is out and which you have, what
/// Install does (or why this copy can't), and the three choices. Install and
/// Reopen is the default action and is left out of a copy that can't replace
/// itself, which gets Release Notes only.
struct UpdateOfferView: View {
    let update: AvailableUpdate
    let currentVersion: String
    let canInstall: Bool
    /// The installer is running: Capsid is about to quit.
    let installing: Bool
    let install: () -> Void
    let releaseNotes: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Capsid \(update.version) is available")
                        .font(.headline)
                    Text("You have \(currentVersion).")
                        .foregroundStyle(.secondary)
                }
            }
            Text(canInstall ? UpdateRules.installSentence(update.version) : UpdateRules.cannotInstallHere)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip This Version", action: skip)
                    .buttonStyle(.borderless)
                Spacer(minLength: 8)
                Button("Release Notes", action: releaseNotes)
                if canInstall {
                    Button(installing ? "Installing\u{2026}" : "Install and Reopen", action: install)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                        .keyboardShortcut(.defaultAction)
                        .disabled(installing)
                }
            }
        }
        .padding(20)
        // Wide enough for the three buttons on one line: at 320 across,
        // "Skip This Version" wrapped.
        .frame(width: 360 + 40)
    }
}
