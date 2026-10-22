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

    private var headline: String {
        if let phase = updates.installPhase { return UpdatesSection.installTitle(phase, version: update.version) }
        return "Capsid \(update.version) is available"
    }

    /// The download's share, for the ring while it runs.
    private var fraction: Double? {
        guard case .downloading(let received, let expected?) = updates.installPhase, expected > 0 else { return nil }
        return min(1, Double(received) / Double(expected))
    }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 5) {
                if let phase = updates.installPhase {
                    // A clay ring in the arrow's place: filling while the
                    // download runs, turning while the copy is checked.
                    Group {
                        if phase == .installing {
                            ProgressView(value: 1)
                        } else if let fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView()
                        }
                    }
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(Theme.clay)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                    Text("Updating")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Image(nsImage: Self.clayArrow)
                        .accessibilityHidden(true)
                    Text("Update")
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .buttonStyle(ReadoutButtonStyle())
        .accessibilityLabel(updates.installPhase == nil ? "Update" : "Updating")
        .accessibilityValue(headline)
        .help(headline)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            UpdateOfferView(
                update: update, currentVersion: updates.currentVersion,
                canInstall: UpdateRules.canInstall(from: Bundle.main.bundleURL), phase: updates.installPhase,
                install: { updates.install() },
                cancel: { updates.cancelInstall() },
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
/// itself, which gets Release Notes only. While an install runs, the button
/// row gives way to its progress: a clay bar and what is being done, with
/// Cancel until the swap starts.
struct UpdateOfferView: View {
    let update: AvailableUpdate
    let currentVersion: String
    let canInstall: Bool
    /// Where the install stands, while one runs.
    let phase: InstallPhase?
    let install: () -> Void
    let cancel: () -> Void
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
            if let phase {
                progress(phase)
            } else {
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
                        Button("Install and Reopen", action: install)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.clay)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        // Wide enough for the three buttons on one line: at 320 across,
        // "Skip This Version" wrapped.
        .frame(width: 360 + 40)
    }

    /// The install's progress in the buttons' place: a bar (filling for the
    /// download, turning for the checks), one line saying what is being done,
    /// and Cancel while there is something to cancel.
    @ViewBuilder
    private func progress(_ phase: InstallPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch phase {
            case .downloading(let received, let expected):
                if let expected, expected > 0 {
                    ProgressView(value: Double(received), total: Double(expected))
                } else {
                    ProgressView()
                }
            case .checking:
                ProgressView()
            case .installing:
                ProgressView(value: 1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Self.sentence(phase, version: update.version))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if phase != .installing {
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(Theme.clay)
        .accessibilityElement(children: .combine)
    }

    static func sentence(_ phase: InstallPhase, version: BenchVersion) -> String {
        switch phase {
        case .downloading(let received, let expected):
            UpdateInstallRules.progressSentence(version: version, received: received, expected: expected)
        case .checking:
            "Checking the signature\u{2026}"
        case .installing:
            "Installing\u{2026} Capsid will reopen in a moment."
        }
    }
}
