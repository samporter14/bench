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
// Add `--quiet` (and launch with `open -g -n build/Bench.app --args …`) to keep
// the demo from taking the keyboard: its windows open without activating.
//
// The `-key value` pairs are command-line defaults: they read like settings
// and are never saved. The panel shows only when `showLabPanel` is on, and
// while Bench is in front only when `panelWhileFront` is on. `settingsTab`
// picks the Settings tab, and `ApplePersistenceIgnoreState` keeps the Settings
// window (which is not ours to configure) out of the saved window state the
// real Bench shares. Don't click the Settings controls or the toolbar's Scenes
// button: those are real settings and would be saved.
import AppKit
import OSLog
import SwiftUI

@MainActor
enum Demo {
    enum Mode: String, CaseIterable {
        /// One session working: the panel's compact face.
        case working
        /// One session asking a question: the panel's card face.
        case card
        /// One session that stopped with an error: the failure card.
        case failed
        /// One session working while the reads fail: "Not updating".
        case stale
        /// A window with only the toolbar, its readouts filled in.
        case toolbar
        /// The real Settings window.
        case settings
        /// The Usage popover's content in a window: plan limits and a made-up
        /// activity history since Claude Science's launch.
        case usage
        /// Settings > General, or Settings > Specimens, each in a plain
        /// window: unlike the Settings scene, it opens without activating
        /// Bench, so a quiet demo can be captured while you type elsewhere.
        case general, specimens
    }

    /// Nil in a normal launch.
    static let mode: Mode? = parse()

    /// `--open-options` with `--demo toolbar`: the Specimens options popover
    /// opens by itself, for a screenshot.
    static let opensSpecimenOptions = mode == .toolbar && CommandLine.arguments.contains("--open-options")
    /// `--log-dock-menu`: asks the app's delegate for the Dock menu the way
    /// the Dock does, and logs what came back, to check SwiftUI passes the
    /// request on.
    static let logsDockMenu = mode != nil && CommandLine.arguments.contains("--log-dock-menu")

    static func logDockMenu() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let delegate = NSApp.delegate
            let responds = delegate?.responds(to: #selector(NSApplicationDelegate.applicationDockMenu(_:))) ?? false
            let menu = delegate?.applicationDockMenu?(NSApp)
            Logger.app.notice("Dock menu check: delegate responds \(responds, privacy: .public), items \(menu?.items.map(\.title) ?? [], privacy: .public)")
        }
    }

    /// `--open-activity` with `--demo toolbar`: the activity list opens by
    /// itself, filled with made-up sessions.
    static let opensActivity = mode == .toolbar && CommandLine.arguments.contains("--open-activity")

    /// Held so the windows stay up.
    private static var windows: [NSWindow] = []

    /// `--quiet`: the demo never makes Bench the active app, so its windows
    /// come up behind whatever you are typing in, for `screencapture -l`.
    /// Launch it with `open -g -n` so the launch doesn't either.
    static let isQuiet = mode != nil && CommandLine.arguments.contains("--quiet")

    /// NSApp.activate(), except in a quiet demo.
    static func activateUnlessQuiet() {
        if !isQuiet { NSApp.activate() }
    }

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
        case .failed?:
            showPanel(working: [], cards: [.failed(session(.error))])
        case .stale?:
            LabModel.shared.showDemo(working: [session(.running)], cards: [],
                                     problem: .databaseUnreadable("demo"), staleSince: Date().addingTimeInterval(-3 * 60))
            showBackdrop()
            LabPanelController.shared.start()
        case .toolbar?:
            showToolbar()
        case .settings?:
            showSettings()
        case .usage?:
            showUsage()
        case .general?:
            showPage(GeneralSettingsView(), title: "General")
        case .specimens?:
            showPage(SceneSettingsView(), title: "Specimens")
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

    /// Made-up sessions in every state, for the activity list.
    private static func showActivity() {
        func make(_ id: String, _ title: String, _ project: String, _ state: SessionState,
                  _ reason: WaitingReason? = nil, minutes: Double) -> SessionStatus {
            let now = Date()
            return SessionStatus(id: id, projectID: "demo", projectName: project, title: title, state: state,
                                 updatedAt: now, startedAt: now.addingTimeInterval(-minutes * 60), waitingReason: reason)
        }
        let question = make("d1", "Protein stability screen", "Example project", .needsInput, .question, minutes: 6)
        let plan = make("d2", "Batch effect check", "Sequencing pilot", .needsInput, .plan, minutes: 12)
        let failed = make("d3", "Figure 2 rebuild", "Example project", .error, minutes: 3)
        let working = [make("d4", "Literature sweep", "Reading group", .running, minutes: 4.2),
                       make("d5", "Plate layout", "Assay design", .running, minutes: 17.5)]
        let finished = make("d6", "Primer design", "Cloning", .finished, minutes: 40)
        let recent = [
            LabEvent(.finished, session: finished, at: Date().addingTimeInterval(-9 * 60)),
            LabEvent(.failed, session: failed, at: Date().addingTimeInterval(-2 * 60)),
            LabEvent(.needsInput(.plan), session: plan, at: Date().addingTimeInterval(-11 * 60)),
            LabEvent(.saved(URL(fileURLWithPath: "/tmp/example-results.csv")), session: nil,
                     at: Date().addingTimeInterval(-25 * 60)),
        ].sorted { $0.at > $1.at }
        LabModel.shared.showDemo(working: working, cards: [.needsInput(question), .needsInput(plan), .failed(failed)],
                                 recent: recent)
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
        if opensActivity {
            showActivity()
        } else {
            LabModel.shared.showDemo(working: [session(.running)], cards: [])
        }

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
        activateUnlessQuiet()
        window.makeKeyAndOrderFront(nil)
    }

    private static func showUsage() {
        PlanUsageModel.shared.showDemo(limits: [
            PlanLimit(kind: .session, usedPercent: 46, resetsAt: Date(timeIntervalSinceNow: 87 * 60)),
            PlanLimit(kind: .week, usedPercent: 32, resetsAt: Date(timeIntervalSinceNow: 3 * 24 * 3600)),
        ])
        // A fixed, made-up pattern: busy weekdays, quiet weekends, a few gaps.
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        var sessions: [String: Int] = [:], messages: [String: Int] = [:], tokens: [String: Int] = [:]
        var day = calendar.startOfDay(for: ActivityGraph.launch)
        var n = 0
        while day <= Date() {
            let weekday = calendar.component(.weekday, from: day)
            let base = (weekday == 1 || weekday == 7) ? 0 : [1, 3, 0, 5, 2, 4, 6, 2, 0, 3][n % 10]
            if base > 0 {
                let key = formatter.string(from: day)
                sessions[key] = base
                messages[key] = base * 14 + n % 9
                tokens[key] = base * 2_100_000 + (n % 7) * 350_000
            }
            n += 1
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        UsageModel.shared.showDemo(history: ActivityHistory(
            sessions: DailyCounts(counts: sessions),
            messages: DailyCounts(counts: messages),
            tokens: DailyCounts(counts: tokens)))

        let hosting = NSHostingController(rootView: UsageView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Usage"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        windows.append(window)
        activateUnlessQuiet()
        window.makeKeyAndOrderFront(nil)
    }

    private static func showPage<V: View>(_ view: V, title: String) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        windows.append(window)
        if isQuiet {
            window.orderFrontRegardless()
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// The same way "Choose specimens…" opens Settings. The tab comes from
    /// the command line (`-settingsTab`), so nothing is written.
    private static func showSettings() {
        SettingsWindow.open()
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
