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
        PosterCost.runIfAsked()
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
            // A made-up pause, when the demo asks for one (`-demoUsagePause YES`).
            UsagePauseModel.shared.start()
            if Demo.logsDockMenu { Demo.logDockMenu() }
            return
        }
        Router.shared.showWindow = { MainWindowController.shared.show() }
        MainWindowController.shared.show()
        // The first launch only, in front of the main window (App/Welcome.swift).
        WelcomeWindowController.shared.showIfFirstLaunch()
        WebContainer.shared.start()
        // Started here, not by its toolbar item: the item only exists once
        // the model has a reading.
        ContextModel.shared.start()
        LabModel.shared.start()
        MacNotifications.shared.start()
        LabPanelController.shared.start()
        // Reads a plan for its card, and approves it when asked (Lab/PlanApproval.swift).
        PlanApprover.shared.start()
        // A question, a permission request or a plan's changes answered from its card (Lab/QuestionReply.swift).
        QuestionReplier.shared.start()
        // Why a session stopped, on its failure card (Lab/FailureReason.swift).
        FailureReasoner.shared.start()
        // Quick Look's temporary copies left by a run that never closed Results, deleted off
        // the main actor; this run's first copy waits for it (Results/ShelfTemporaryCopies.swift).
        ResultsShelf.shared.cleanUpAtLaunch()
        NidusFocus.shared.start()
        // The Focus filter and the menu switch that keep Capsid quiet while
        // presenting (Lab/PresentingMode.swift). A demo returned above.
        PresentingMode.shared.start()
        NidusTaskContext.shared.start()
        NoticeWatchers.shared.start()
        // Running sessions held by a used-up plan limit (Lab/UsagePause.swift).
        UsagePauseModel.shared.start()
        // The opt-in daily look for a newer Bench (App/UpdateCheck.swift).
        UpdateChecker.shared.start()
        // Capsid on your phone, if it was on (Remote/RemoteController.swift).
        RemoteController.shared.start()
        MenuBarSpecimen.shared.start()
        // ⌘⇧O reaches Quick Open before the page: a web view offers key
        // equivalents to the page first, and a page that binds ⌘⇧O itself
        // would keep it from the menu.
        // Only in the Claude Science window: a Browser window shows other
        // sites, which may use ⌘⇧O themselves. Caps Lock doesn't count.
        quickOpenKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "o",
                  !QuickOpenPresenter.shared.isShowing,
                  event.window != nil, event.window === MainWindowController.shared.windowIfLoaded else { return event }
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
        NidusTaskContext.shared.clear()
        LabModel.shared.stop()
        // Capsid on your phone: its Serve mapping goes with it, waiting
        // at most 2 s (Remote/RemoteController.swift). Never in a demo.
        if Demo.mode == nil { RemoteController.shared.removeMappingAtQuit() }
    }

    /// The Dock icon's menu: the activity list's sessions, so they can be
    /// opened with the window closed.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = ActivityMenu.shared.make()
        menu.addItem(.separator())
        menu.addItem(PresentingMenu.shared.item())
        Logger.app.notice("Dock menu: \(menu.items.count, privacy: .public) items")
        return menu
    }
}

/// The one main window. Its content is SwiftUI; its toolbar is the system's
/// (glass on macOS 26), filled from the view's `.toolbar`.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    /// The window once it exists, without making it: for checks like "is
    /// this event in the main window?" that must not create one.
    var windowIfLoaded: NSWindow? { isLoaded ? window : nil }
    private var isLoaded = false

    private lazy var window: NSWindow = {
        isLoaded = true
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
                    ResultsToolbarButton()
                }
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
    /// Whether a window with a web page is in front. Reload, Zoom, Find and
    /// Back/Forward act on that window's page, not always the main window's,
    /// and go dim when there is none (Settings).
    @ObservedObject private var active = ActiveWebPage.shared
    /// Whether the main window is in front with its page ready: Close Other
    /// Tabs and Close All Tabs act on that page's tabs only (Web/PageTabs.swift).
    @ObservedObject private var tabs = PageTabCommands.shared
    /// Quiet While Presenting's checkmark (Lab/PresentingMode.swift).
    @ObservedObject private var presenting = PresentingMode.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdatePrompts.checkFromMenu() }
                .disabled(Demo.mode != nil)
        }
        CommandGroup(after: .appSettings) {
            // The panel, sounds and notifications stay away; what finished
            // comes as one card afterwards. A Focus filter does the same
            // (App/PresentingFocusFilter.swift). A demo starts none of it.
            Toggle(PresentingMenu.title, isOn: Binding(get: { presenting.manualOn }, set: { presenting.setManual($0) }))
                .disabled(Demo.mode != nil)
        }
        CommandGroup(after: .newItem) {
            // A demo has no main window to show it on.
            Button("Open Session…") { QuickOpenPresenter.shared.show() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(Demo.mode != nil)
            // The files sessions made (Results/ResultsWindow.swift).
            Button("Results…") { ResultsWindowController.shared.show() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(Demo.mode != nil)
            Divider()
            // The artifact tabs in Claude Science's right-hand panel. ⌥⌘W is
            // Safari's Close Other Tabs; Close All Tabs has no shortcut.
            Button("Close Other Tabs") { PageTabCommands.shared.closeOthers() }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(!tabs.isEnabled)
            Button("Close All Tabs") { PageTabCommands.shared.closeAll() }
                .disabled(!tabs.isEnabled)
        }
        CommandGroup(after: .toolbar) {
            Group {
                Button("Reload") { ActiveWebPage.current?.reload() }
                    .keyboardShortcut("r")
                Divider()
                Button("Zoom In") { ActiveWebPage.current?.zoomIn() }
                    .keyboardShortcut("+")
                Button("Zoom Out") { ActiveWebPage.current?.zoomOut() }
                    .keyboardShortcut("-")
                Button("Actual Size") { ActiveWebPage.current?.resetZoom() }
                    .keyboardShortcut("0")
            }
            .disabled(!active.hasPage)
            Divider()
            Button("Show Specimens Panel") {
                let defaults = UserDefaults.standard
                defaults.set(!defaults.bool(forKey: SettingsKey.showPanel), forKey: SettingsKey.showPanel)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { ActiveWebPage.current?.showFind() }
                .keyboardShortcut("f")
                .disabled(!active.hasPage)
        }
        CommandGroup(after: .help) {
            // A demo has its own welcome (`--demo welcome`), which records nothing.
            Button("Welcome to Capsid") { WelcomeWindowController.shared.show() }
                .disabled(Demo.mode != nil)
            Button("Capsid Diagnostics…") { DiagnosticsWindowController.shared.show() }
        }
        CommandMenu("History") {
            Group {
                Button("Back") { ActiveWebPage.current?.goBack() }
                    .keyboardShortcut("[")
                Button("Forward") { ActiveWebPage.current?.goForward() }
                    .keyboardShortcut("]")
            }
            .disabled(!active.hasPage)
        }
    }
}
