// UpdatePrompts.swift — what the update check says to the user: the alert
// that offers an update (from the card, the Dock item and the app menu's Check
// for Updates…), the alert for an install that didn't work, and Settings →
// General → Updates (DESIGN.md, Update check). The toolbar's Update button
// has its own file (UpdateToolbarButton.swift).
import AppKit
import SwiftUI

@MainActor
enum UpdatePrompts {
    /// A menu check is under way: choosing it again waits for the answer
    /// rather than stacking a second alert.
    private static var checking = false

    /// Capsid → Check for Updates…: asks now, then says what it found.
    static func checkFromMenu() {
        guard !checking else { return }
        checking = true
        Task {
            let state = await UpdateChecker.shared.checkNow()
            checking = false
            present(state)
        }
    }

    /// The release's page, in the in-app Browser window like any other link
    /// to a website (DESIGN.md, Web routing policy). `notesURL` is always a
    /// github.com page of Bench's releases.
    static func openReleaseNotes(_ update: AvailableUpdate) {
        LinkDispatcher.open(update.notesURL, as: .web)
    }

    private enum Choice { case install, notes, dismiss }

    /// An offer is on screen: asking again (a second click on the card or the
    /// Dock item) must not stack another.
    private static var offering = false

    /// The alert that offers an update, the one place that does: the card's
    /// Install…, the Dock item and the menu's check all come here. Install
    /// (only for a copy that can replace itself), Release Notes and Later
    /// (Esc), and a "Skip this version" box that, left checked on any answer
    /// but Install, stops the card, the toolbar button and the Dock item
    /// offering this version (`UpdateChecker.skip`).
    static func offer(_ update: AvailableUpdate) {
        guard !offering else { return }
        offering = true
        defer { offering = false }
        let alert = NSAlert()
        var choices: [Choice] = []
        alert.messageText = "Capsid \(update.version) is available"
        if UpdateRules.canInstall(from: Bundle.main.bundleURL) {
            // The alert says what Install does, so it needs no second one.
            alert.informativeText = UpdateRules.installSentence(update.version)
            alert.addButton(withTitle: "Install")
            choices.append(.install)
        } else {
            alert.informativeText = UpdateRules.cannotInstallHere
        }
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        choices += [.notes, .dismiss]
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Skip this version"
        NSApp.activate()
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let choice = choices.indices.contains(index) ? choices[index] : .dismiss
        switch choice {
        case .install: UpdateChecker.shared.install()
        case .notes: openReleaseNotes(update)
        case .dismiss: break
        }
        if choice != .install, alert.suppressionButton?.state == .on { UpdateChecker.shared.skip(update) }
    }

    /// What the menu's check found: an offer, or an alert with just OK.
    private static func present(_ state: UpdateChecker.State) {
        let alert = NSAlert()
        switch state {
        case .upToDate(let version):
            alert.messageText = "Capsid is up to date (\(version))"
            alert.informativeText = "This is the latest release on GitHub."
        case .available(let update):
            offer(update)
            return
        case .failed(let failure):
            alert.alertStyle = .warning
            alert.messageText = "Couldn\u{2019}t check for updates"
            alert.informativeText = failure.message
        case .idle, .checking:
            return
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    /// The installer ended and Bench is still here, so nothing was replaced.
    static func installFailed(_ update: AvailableUpdate) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Capsid \(update.version) didn\u{2019}t install"
        alert.informativeText = "Capsid is still the version you had. Try again later, or run the install line from the README in Terminal."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}

/// Settings → General → Updates: the switch for the daily check, Check Now,
/// and, when one is out, Install Update and Release Notes.
struct UpdatesSection: View {
    @AppStorage(SettingsKey.checkForUpdates) private var enabled = true
    @ObservedObject private var updates = UpdateChecker.shared
    /// The update waiting on the answer to "Install?".
    @State private var confirming: AvailableUpdate?

    /// A demo checks nothing.
    private let isDemo = Demo.mode != nil
    private var canInstall: Bool { UpdateRules.canInstall(from: Bundle.main.bundleURL) }

    private var title: String {
        switch updates.state {
        case .idle: "Check for a newer version"
        case .checking: "Asking GitHub\u{2026}"
        case .upToDate(let version): "Capsid is up to date (\(version))"
        case .available(let update): "Capsid \(update.version) is available"
        case .failed: "Couldn\u{2019}t check for updates"
        }
    }

    /// Under the title: the reason a check failed, else when the last one
    /// got an answer.
    private var detail: String {
        if case .failed(let failure) = updates.state { return failure.message }
        guard let date = updates.lastChecked else { return "Not checked yet" }
        return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        Section("Updates") {
            Toggle(isOn: $enabled) {
                Text("Check for updates once a day")
                Text("Asks GitHub for the latest Capsid release. Nothing about you or your sessions is sent.")
            }
            LabeledContent {
                Button(updates.state == .checking ? "Checking\u{2026}" : "Check Now") {
                    Task { await updates.checkNow() }
                }
                .disabled(updates.state == .checking || isDemo)
            } label: {
                Text(title)
                Text(detail)
            }
            if case .available(let update) = updates.state {
                LabeledContent {
                    HStack {
                        Button("Release Notes") { UpdatePrompts.openReleaseNotes(update) }
                        Button(updates.installing ? "Installing\u{2026}" : "Install Update") { confirming = update }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canInstall || updates.installing)
                    }
                } label: {
                    Text(canInstall ? UpdateRules.installSentence(update.version) : UpdateRules.cannotInstallHere)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Install the update?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
               presenting: confirming) { _ in
            Button("Install") { updates.install() }
            Button("Cancel", role: .cancel) {}
        } message: { update in
            Text(UpdateRules.installSentence(update.version))
        }
    }
}
