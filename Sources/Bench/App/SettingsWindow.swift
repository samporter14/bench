// SettingsWindow.swift — opens Settings on a tab from anywhere in Bench.
import AppKit
import SwiftUI

/// SwiftUI's `openSettings` only works from a view the app's scenes know
/// about. A toolbar menu in the AppKit-managed main window isn't one, so
/// "Choose specimens…" did nothing there. A tiny, invisible hosting window
/// is one, so the request is made from there, and the window closes once
/// Settings is up.
@MainActor
enum SettingsWindow {
    private static var opener: NSWindow?

    /// `tab` is "general" or "scenes"; nil keeps whatever tab was last shown.
    static func open(tab: String? = nil) {
        if let tab { UserDefaults.standard.set(tab, forKey: SettingsKey.settingsTab) }
        opener?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: Opener {
            SettingsWindow.opener?.close()
            SettingsWindow.opener = nil
        })
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        opener = window
        NSApp.activate()
        window.orderFrontRegardless()
    }

    private struct Opener: View {
        @Environment(\.openSettings) private var openSettings
        let done: @MainActor () -> Void

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear {
                    openSettings()
                    NSApp.activate()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        done()
                    }
                }
        }
    }
}
