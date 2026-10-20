// SettingsViewport.swift — one width for Settings, and a content height that
// leaves room for its window chrome on the screen it actually occupies.
// Forms already scroll; the Specimens page supplies its own compact layout.
import AppKit
import SwiftUI

enum SettingsSizing {
    static let width: CGFloat = 760
    static let formWidth: CGFloat = 600
    static let screenMargin: CGFloat = 16
    /// Before a window exists, allow room for Settings' title and tab toolbar.
    static let initialChrome: CGFloat = 100

    static func heightLimit(visibleHeight: CGFloat, chrome: CGFloat) -> CGFloat {
        max(1, visibleHeight - max(0, chrome) - 2 * screenMargin)
    }

    @MainActor
    static var initialHeightLimit: CGFloat {
        heightLimit(visibleHeight: (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 900,
                    chrome: initialChrome)
    }
}

extension View {
    func settingsViewport(height: CGFloat) -> some View {
        modifier(SettingsViewport(preferredHeight: height))
    }
}

private struct SettingsViewport: ViewModifier {
    let preferredHeight: CGFloat
    @State private var heightLimit = SettingsSizing.initialHeightLimit

    func body(content: Content) -> some View {
        content
            .frame(width: SettingsSizing.width, height: min(preferredHeight, heightLimit))
            .background {
                SettingsScreenReader { limit in
                    if heightLimit != limit { heightLimit = limit }
                }
            }
    }
}

/// Watches only window/screen changes. No polling, and no dependence on which
/// other Capsid window is key while Settings remains open.
private struct SettingsScreenReader: NSViewRepresentable {
    let changed: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenView { ScreenView() }

    func updateNSView(_ view: ScreenView, context: Context) {
        view.changed = changed
        view.scheduleReport()
    }

    static func dismantleNSView(_ view: ScreenView, coordinator: ()) { view.stop() }

    final class ScreenView: NSView {
        var changed: (@MainActor (CGFloat) -> Void)?
        private var reportPending = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(screenChanged),
                               name: NSWindow.didChangeScreenNotification, object: window)
            center.addObserver(self, selector: #selector(screenChanged),
                               name: NSWindow.didResizeNotification, object: window)
            center.addObserver(self, selector: #selector(screenChanged),
                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
            scheduleReport()
        }

        @objc private func screenChanged(_ notification: Notification) { scheduleReport() }

        func scheduleReport() {
            guard !reportPending else { return }
            reportPending = true
            // Do not mutate SwiftUI state from updateNSView or AppKit's layout.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportPending = false
                guard let window = self.window,
                      let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
                let chrome = max(0, window.frame.height - window.contentLayoutRect.height)
                self.changed?(SettingsSizing.heightLimit(visibleHeight: screen.visibleFrame.height, chrome: chrome))
            }
        }

        func stop() {
            NotificationCenter.default.removeObserver(self)
            changed = nil
        }
    }
}
