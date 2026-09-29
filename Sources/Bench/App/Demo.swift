// Demo.swift — `Bench --demo <mode>`: Bench's real UI filled with made-up
// data, so README screenshots show nothing from anyone's research. A demo
// starts nothing real: no daemon, no `claude-science`, no web page, no read of
// Claude Science's data. It also writes nothing to UserDefaults, which the
// real Bench shares (same bundle id) and may be running against.
//
// Run the binary itself: launched that way it is a second instance, even
// while the real Bench is open. Quit it with ⌘Q.
//
//   build/Bench.app/Contents/MacOS/Bench --demo working  -showLabPanel YES -panelWhileFront YES
//   build/Bench.app/Contents/MacOS/Bench --demo card     -showLabPanel YES -panelWhileFront YES
//   build/Bench.app/Contents/MacOS/Bench --demo toolbar
//   build/Bench.app/Contents/MacOS/Bench --demo settings -settingsTab scenes -ApplePersistenceIgnoreState YES
//
// The `-key value` pairs are command-line defaults: they read like settings
// and are never saved. The panel shows only when `showLabPanel` is on, and
// while Bench is in front only when `panelWhileFront` is on. `settingsTab`
// picks the Settings tab, and `ApplePersistenceIgnoreState` keeps the Settings
// window (which is not ours to configure) out of the saved window state the
// real Bench shares. Don't click the Settings controls or the toolbar's Scenes
// button: those are real settings and would be saved.
import AppKit
import SwiftUI

@MainActor
enum Demo {
    enum Mode: String, CaseIterable {
        /// One session working: the panel's compact face.
        case working
        /// One session asking a question: the panel's card face.
        case card
        /// A window with only the toolbar, its readouts filled in.
        case toolbar
        /// The real Settings window.
        case settings
    }

    /// Nil in a normal launch.
    static let mode: Mode? = parse()

    /// Held so the windows stay up.
    private static var windows: [NSWindow] = []

    /// Reads `mode` at launch. A misspelt `--demo` value ends here: falling
    /// through to a normal start would load the real Claude Science.
    static func validate() {
        _ = mode
    }

    static func start() {
        switch mode {
        case .working?:
            showPanel(working: [session(.running)], cards: [])
        case .card?:
            showPanel(working: [], cards: [.needsInput(session(.needsInput))])
        case .toolbar?:
            showToolbar()
        case .settings?:
            showSettings()
        case nil:
            break
        }
    }

    private static func parse() -> Mode? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--demo") else { return nil }
        if let name = arguments.dropFirst(flag + 1).first, let mode = Mode(rawValue: name) {
            return mode
        }
        let valid = Mode.allCases.map(\.rawValue).joined(separator: ", ")
        FileHandle.standardError.write(Data("Bench: --demo takes one of: \(valid)\n".utf8))
        exit(1)
    }

    // MARK: Made-up data

    private static func session(_ state: SessionState) -> SessionStatus {
        let now = Date()
        return SessionStatus(
            id: "demo-1", projectID: "demo", projectName: "Example project",
            title: "Protein stability screen", state: state,
            updatedAt: now, startedAt: now.addingTimeInterval(-(4 * 60 + 12)),
            waitingReason: .question)
    }

    // MARK: The modes

    private static func showPanel(working: [SessionStatus], cards: [LabCard]) {
        LabModel.shared.showDemo(working: working, cards: cards)
        showBackdrop()
        LabPanelController.shared.start()
    }

    /// The panel's glass samples whatever is behind it, which could be
    /// anyone's private window. This puts a neutral backdrop of ours there.
    private static func showBackdrop() {
        guard let screen = NSScreen.screens.first else { return }
        let size = CGSize(width: 560, height: 460)
        let area = screen.visibleFrame
        let frame = NSRect(x: area.maxX - size.width, y: area.minY, width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: DemoBackdrop())
        hosting.sizingOptions = []
        let backdrop = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless],
                               backing: .buffered, defer: false)
        backdrop.contentView = hosting
        // Just under the panel's `.floating`.
        backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backdrop.hidesOnDeactivate = false
        backdrop.ignoresMouseEvents = true
        backdrop.isOpaque = false
        backdrop.backgroundColor = .clear
        backdrop.hasShadow = false
        backdrop.animationBehavior = .none
        backdrop.isExcludedFromWindowsMenu = true
        backdrop.isReleasedWhenClosed = false
        // Saved window state lives beside the real Bench's, under the same id.
        backdrop.isRestorable = false
        backdrop.orderFrontRegardless()
        windows.append(backdrop)
    }

    private static func showToolbar() {
        ContextModel.shared.showDemo(used: 18_400, window: 200_000, turns: [2_100, 5_300, 9_800, 14_200, 18_400])
        PlanUsageModel.shared.showDemo(limits: [
            PlanLimit(kind: .session, usedPercent: 46, resetsAt: Date(timeIntervalSinceNow: 87 * 60)),
            PlanLimit(kind: .week, usedPercent: 32, resetsAt: Date(timeIntervalSinceNow: 3 * 24 * 3600)),
        ])
        LabModel.shared.showDemo(working: [session(.running)], cards: [])

        // Built like MainWindowController's window, with a placeholder where
        // the web view is, and no frame autosave: that would be a default.
        let hosting = NSHostingController(rootView: DemoToolbarWindow())
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Claude Science"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unifiedCompact
        window.setContentSize(NSSize(width: 1100, height: 640))
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// `openSettings` is what the app's own "Choose scenes…" uses, so it is
    /// asked the same way: from a SwiftUI view in an AppKit window. That one
    /// is invisible, and closes once Settings has opened.
    private static func showSettings() {
        let opener = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                              styleMask: .borderless, backing: .buffered, defer: false)
        opener.contentViewController = NSHostingController(rootView: SettingsOpener { [weak opener] in
            opener?.close()
        })
        opener.alphaValue = 0
        opener.ignoresMouseEvents = true
        opener.isOpaque = false
        opener.backgroundColor = .clear
        opener.hasShadow = false
        opener.isReleasedWhenClosed = false
        opener.isRestorable = false
        windows.append(opener)
        NSApp.activate()
        opener.orderFrontRegardless()
    }
}

/// The toolbar window's content: the window's own colour, and the app's
/// toolbar. Same minimum size as the real content.
private struct DemoToolbarWindow: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .frame(minWidth: 900, minHeight: 560)
            .benchToolbar()
    }
}

/// Opens Settings when it appears, then says it is done a moment later, so
/// the window it opened from is not closed under the request.
private struct SettingsOpener: View {
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

/// Ivory to a warm clay tint, or slate to a slightly lighter warm dark. It
/// fades out at the top and left, where nothing sits on it, so it has no hard
/// edge to show in a screenshot.
private struct DemoBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .mask(fade(from: .leading, to: .trailing, over: 0.2))
            .mask(fade(from: .top, to: .bottom, over: 0.25))
    }

    private var colors: [Color] {
        colorScheme == .dark
            ? [Theme.slate.mix(with: Theme.clay, by: 0.06), Theme.slate.mix(with: Theme.clay, by: 0.2)]
            : [Theme.ivory, Theme.ivory.mix(with: Theme.clay, by: 0.32)]
    }

    /// Clear at the start, solid after `fraction` of the way.
    private func fade(from start: UnitPoint, to end: UnitPoint, over fraction: Double) -> LinearGradient {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: fraction)],
                       startPoint: start, endPoint: end)
    }
}
