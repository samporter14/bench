// BenchApp.swift — the app: launch, menus, settings, and the wiring between
// the Web and Lab halves (DESIGN.md). The main window is AppKit-managed so
// closing it only hides it and the one web view survives.
import AppKit
import SwiftUI

@main
struct BenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        SheetCost.runIfAsked()
        SceneReel.runIfAsked()
        Diagnose.runIfAsked()
        Demo.validate()
        SettingsKey.register()
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands { BenchCommands() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A demo shows made-up data and starts nothing real (Demo.swift).
        if Demo.mode != nil {
            Demo.start()
            return
        }
        Router.shared.showWindow = { MainWindowController.shared.show() }
        MainWindowController.shared.show()
        WebContainer.shared.start()
        // Started here, not by its toolbar item: the item only exists once
        // the model has a reading.
        ContextModel.shared.start()
        LabModel.shared.start()
        LabPanelController.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Demo.mode == nil { MainWindowController.shared.show() }
        return true
    }

    /// Closing the window only hides it: Bench keeps watching, and the panel
    /// keeps playing.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard Demo.mode == nil else { return }
        for url in urls where url.scheme == "bench" {
            Router.shared.handle(benchURL: url, port: WebContainer.shared.port)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LabModel.shared.stop()
    }
}

/// The one main window. Its content is SwiftUI; its toolbar is the system's
/// (glass on macOS 26), filled from the view's `.toolbar`.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private lazy var window: NSWindow = {
        let hosting = NSHostingController(rootView: MainView())
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Claude Science"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 900, height: 600)
        window.setContentSize(NSSize(width: 1360, height: 900))
        window.center()
        window.setFrameAutosaveName("BenchMain")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        return window
    }()

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window.isVisible }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// The window's content: the web view, and the toolbar.
struct MainView: View {
    var body: some View {
        BrowserView()
            .frame(minWidth: 900, minHeight: 560)
            .benchToolbar()
    }
}

/// The main window's toolbar, apart from MainView so the demo window
/// (Demo.swift) shows exactly the same one. A modifier, not a ToolbarContent:
/// it needs to watch the Lab model, and a view's modifier is where that is
/// sure to work.
struct BenchToolbar: ViewModifier {
    @ObservedObject private var lab = LabModel.shared

    func body(content: Content) -> some View {
        content
            // No back/forward/reload: Claude Science has its own navigation,
            // and ⌘[ ⌘] ⌘R stay in the menus.
            .toolbar {
                // On the Mac, items start at the leading edge: push them right.
                ToolbarSpacer(.flexible)
                // Only while something works or waits: an item with nothing in
                // it would still draw an empty glass bubble.
                if !lab.working.isEmpty || !lab.waiting.isEmpty {
                    ToolbarItem {
                        LabStatusCapsule()
                    }
                }
                // The two readouts share one glass capsule. A group of two
                // items would get a bubble each.
                ToolbarItem {
                    TitleBarReadouts()
                }
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    ScenesToolbarButton()
                }
            }
    }
}

extension View {
    func benchToolbar() -> some View { modifier(BenchToolbar()) }
}

struct BenchCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Reload") { WebContainer.shared.reload() }
                .keyboardShortcut("r")
            Divider()
            Button("Zoom In") { WebContainer.shared.zoomIn() }
                .keyboardShortcut("+")
            Button("Zoom Out") { WebContainer.shared.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { WebContainer.shared.resetZoom() }
                .keyboardShortcut("0")
            Divider()
            Button("Show Scenes Panel") {
                let defaults = UserDefaults.standard
                defaults.set(!defaults.bool(forKey: SettingsKey.showPanel), forKey: SettingsKey.showPanel)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { WebContainer.shared.showFind() }
                .keyboardShortcut("f")
        }
        CommandMenu("History") {
            Button("Back") { WebContainer.shared.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { WebContainer.shared.goForward() }
                .keyboardShortcut("]")
        }
    }
}

/// Two tabs: General, and Scenes (which "Choose scenes…" opens).
struct SettingsView: View {
    /// Set to "scenes" before opening Settings to land on that tab.
    @AppStorage(SettingsKey.settingsTab) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") { GeneralSettingsView() }
            Tab("Scenes", systemImage: "flask", value: "scenes") { SceneSettingsView() }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.showPanel) private var showPanel = true
    @AppStorage(SettingsKey.soundOnNeedsInput) private var sound = true
    @AppStorage(SettingsKey.panelWhileFront) private var panelWhileFront = true
    @ObservedObject private var lab = LabModel.shared

    var body: some View {
        Form {
            if let problem = lab.problem {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Can't see your sessions: \(problem.label)")
                            Text("\(problem.hint) For details, run Bench with --diagnose in Terminal.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.clay)
                    }
                }
            }
            Toggle("Show the scenes panel while a session works", isOn: $showPanel)
            Toggle("Keep showing it while Bench is in front", isOn: $panelWhileFront)
                .disabled(!showPanel)
            Toggle("Play a sound when a session needs you", isOn: $sound)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
