// PresentingSettings.swift — Settings → Alerts → While you present (DESIGN.md,
// Quiet while presenting): the same switch the app menu and the Dock menu
// have, a line about adding Capsid's filter to a Focus, and a button to
// System Settings → Focus. What the row says, and where the button goes, is
// pure and tested; the view only draws it.
import AppKit
import SwiftUI

enum PresentingSettings {
    static let header = "While you present"
    static let focusTitle = "Quiet during a Focus"
    static let focusDetail = "Add Capsid's filter to a Focus."
    static let focusButton = "Open Focus Settings\u{2026}"

    /// What a Focus that keeps Capsid quiet is called, here and on the Dock
    /// menu's item.
    static let focusNote = "A Focus is keeping Capsid quiet"

    /// System Settings → Focus. Focus's pane is a settings extension, found in
    /// /System/Library/ExtensionKit/Extensions/FocusSettingsExtension.appex:
    /// its bundle identifier is `com.apple.Focus-Settings.extension`, and it
    /// allows this URL scheme (`allowsXAppleSystemPreferencesURLScheme`). The
    /// same shape as the Notifications pane's (MacNotifications.settingsURL).
    static let focusSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!

    /// Under the switch. It says what the switch does, that it isn't saved,
    /// and, when a Focus is keeping Capsid quiet, that one is: the switch is
    /// separate from it, and turning the switch off does not end its quiet.
    static func rowDetail(manualOn: Bool, focusFilterOn: Bool) -> String {
        guard focusFilterOn else {
            return "Hides the panel and mutes sounds and notifications. Not saved: off again after a quit."
        }
        return manualOn
            ? "\(focusNote) too. Not saved: off again after a quit."
            : "\(focusNote) right now. This switch is separate, and not saved."
    }

    /// In the switch's ⓘ: what quiet means.
    static let switchInfo = """
        While it's on, the panel and its cards stay out of sight, no sound plays and no Mac notification is posted. \
        Sessions that finish are held and come as one card when it ends. Anything that needs you is still \
        waiting, and shows its card then.

        Your phone still gets its notifications, except for finishes, which wait with the rest. The menu bar \
        specimen, the Dock menu and the main window stay as they are.

        If a Focus is keeping Capsid quiet as well, it stays quiet until the Focus has ended and this is off. \
        This switch isn't saved, so Capsid never starts up silent unless you say so.
        """

    /// In the Focus row's ⓘ: how to add the filter, and the way round if it
    /// isn't there (an app built from source can't be sure of showing up).
    static let focusInfo = """
        In System Settings, open Focus and choose the Focus you use for presenting. Then Focus filters, \
        Add Filter, Capsid, and leave \u{201C}Keep Capsid quiet\u{201D} on. Capsid is quiet whenever that Focus is on.

        If Capsid isn't in the list of filters, use the switch above instead.
        """
}

/// The section itself. The switch is `PresentingMode.shared`'s, as in the
/// menus: off and dimmed in a demo, which starts none of it.
struct QuietWhilePresentingSection: View {
    @ObservedObject private var presenting = PresentingMode.shared
    private let isDemo = Demo.mode != nil
    /// Opens a URL; a test's own, or the system's.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var body: some View {
        Section(PresentingSettings.header) {
            Toggle(isOn: Binding(get: { presenting.manualOn }, set: { presenting.setManual($0) })) {
                InfoTitle(PresentingMenu.title, info: PresentingSettings.switchInfo)
                Text(PresentingSettings.rowDetail(manualOn: presenting.manualOn, focusFilterOn: presenting.focusFilterOn))
            }
            .disabled(isDemo)
            LabeledContent {
                Button(PresentingSettings.focusButton) { open(PresentingSettings.focusSettingsURL) }
                    .disabled(isDemo)
            } label: {
                InfoTitle(PresentingSettings.focusTitle, info: PresentingSettings.focusInfo)
                Text(PresentingSettings.focusDetail)
            }
        }
    }
}
