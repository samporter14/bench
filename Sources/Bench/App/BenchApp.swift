// BenchApp.swift — the app: launch, menus, settings, and the wiring between
// the Web and Lab halves (DESIGN.md). The main window is AppKit-managed so
// closing it only hides it and the one web view survives.
import AppKit
import OSLog
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
    /// SIGTERM (the installer's quit, or `kill`) quits the way ⌘Q does, so the
    /// web view saves its session. Killed outright, a restart could come up
    /// on Claude Science's Sign in card.
    private var terminateSignal: DispatchSourceSignal?
    private var quickOpenKey: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminateSignal = source
        BenchAppearance.apply()
        // A demo shows made-up data and starts nothing real (Demo.swift).
        if Demo.mode != nil {
            Demo.start()
            if Demo.logsDockMenu { Demo.logDockMenu() }
            return
        }
        Router.shared.showWindow = { MainWindowController.shared.show() }
        MainWindowController.shared.show()
        WebContainer.shared.start()
        // Started here, not by its toolbar item: the item only exists once
        // the model has a reading.
        ContextModel.shared.start()
        LabModel.shared.start()
        MacNotifications.shared.start()
        LabPanelController.shared.start()
        // Reads a plan for its card, and approves it when asked (Lab/PlanApproval.swift).
        PlanApprover.shared.start()
        NidusFocus.shared.start()
        NoticeWatchers.shared.start()
        MenuBarSpecimen.shared.start()
        // ⌘⇧O reaches Quick Open before the page: a web view offers key
        // equivalents to the page first, and a page that binds ⌘⇧O itself
        // would keep it from the menu.
        quickOpenKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "o",
                  !QuickOpenPresenter.shared.isShowing else { return event }
            QuickOpenPresenter.shared.show()
            return nil
        }
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

    /// The Dock icon's menu: the activity list's sessions, so they can be
    /// opened with the window closed.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = ActivityMenu.shared.make()
        Logger.app.notice("Dock menu: \(menu.items.count, privacy: .public) items")
        return menu
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
    @ObservedObject private var quickOpen = QuickOpenPresenter.shared

    var body: some View {
        BrowserView()
            .frame(minWidth: 900, minHeight: 560)
            .benchToolbar()
            // ⌘⇧O: type to jump to a session (Lab/QuickOpen.swift).
            .sheet(isPresented: $quickOpen.isShowing) { QuickOpenSheet() }
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
                // Always there: what works or waits, else Recent, else a quiet
                // Activity, so the list stays one click away when all is done.
                ToolbarItem {
                    LabStatusCapsule()
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
        CommandGroup(after: .newItem) {
            // A demo has no main window to show it on.
            Button("Open Session…") { QuickOpenPresenter.shared.show() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(Demo.mode != nil)
        }
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
            Button("Show Specimens Panel") {
                let defaults = UserDefaults.standard
                defaults.set(!defaults.bool(forKey: SettingsKey.showPanel), forKey: SettingsKey.showPanel)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { WebContainer.shared.showFind() }
                .keyboardShortcut("f")
        }
        CommandGroup(after: .help) {
            Button("Bench Diagnostics…") { DiagnosticsWindowController.shared.show() }
        }
        CommandMenu("History") {
            Button("Back") { WebContainer.shared.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { WebContainer.shared.goForward() }
                .keyboardShortcut("]")
        }
    }
}
