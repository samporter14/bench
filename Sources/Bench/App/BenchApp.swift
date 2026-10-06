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

/// Two tabs: General, and Scenes (which "Choose scenes…" opens).
struct SettingsView: View {
    /// Set to "scenes" before opening Settings to land on that tab.
    @AppStorage(SettingsKey.settingsTab) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") { GeneralSettingsView() }
            Tab("Specimens", systemImage: "flask", value: "scenes") { SceneSettingsView() }
        }
    }
}

/// General: a grouped form, as System Settings is, with Bench's name and
/// version at the top.
struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.showPanel) private var showPanel = true
    @AppStorage(SettingsKey.showCards) private var showCards = true
    @AppStorage(SettingsKey.showMenuBarSpecimen) private var menuBarSpecimen = false
    @AppStorage(SettingsKey.headsUpNotices) private var headsUp = true
    @AppStorage(SettingsKey.weekInReview) private var weekInReview = true
    @AppStorage(SettingsKey.holdDuringFocus) private var holdDuringFocus = true
    @AppStorage(SettingsKey.soundOnNeedsInput) private var sound = true
    @AppStorage(SettingsKey.panelWhileFront) private var panelWhileFront = true
    @AppStorage(SettingsKey.panelCorner) private var panelCorner = PanelCorner.bottomRight
    @AppStorage(SettingsKey.panelScreen) private var panelScreen = ""
    /// The connected screens' names, kept up to date as screens come and go.
    @State private var screens: [String] = NSScreen.screens.map(\.localizedName)
    @AppStorage(SettingsKey.appearance) private var appearance = BenchAppearance.system.rawValue
    @ObservedObject private var lab = LabModel.shared

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bench")
                            .font(.title2.weight(.semibold))
                        Text("A Solanum product. Unofficial, and not affiliated with Anthropic.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(version)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }

            if let problem = lab.problem {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Can't see your sessions: \(problem.label)")
                            Text("\(problem.hint) For details, open Help → Bench Diagnostics.")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Section("Appearance") {
                Picker(selection: Binding(get: { BenchAppearance(rawValue: appearance) ?? .system },
                                          set: { appearance = $0.rawValue })) {
                    ForEach(BenchAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Theme")
                    Text("The window, the panel and the Claude Science page.")
                }
                .pickerStyle(.segmented)
            }

            Section("Specimens panel") {
                Toggle(isOn: $showPanel) {
                    Text("Show a specimen while a session works")
                    Text("It plays in the corner of your screen until the session stops. Off, cards still come.")
                }
                Toggle(isOn: $menuBarSpecimen) {
                    Text("Show it in the menu bar too")
                    Text("While a session works, or a count while any wait. Click it for every session.")
                }
                Toggle(isOn: $panelWhileFront) {
                    Text("Keep showing the panel while Bench is in front")
                    Text("Off, the panel waits until you switch to another app.")
                }
                .disabled(!showPanel && !showCards)
                Picker(selection: $panelCorner) {
                    ForEach(PanelCorner.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Corner")
                    Text("Where the specimen and the cards sit.")
                }
                .disabled(!showPanel && !showCards)
                Picker(selection: $panelScreen) {
                    Text("The one with the menu bar").tag("")
                    Divider()
                    ForEach(screens, id: \.self) { Text($0).tag($0) }
                    // A screen chosen before and unplugged now: still listed,
                    // so the choice reads true, and used again when it's back.
                    if !panelScreen.isEmpty, !screens.contains(panelScreen) {
                        Text("\(panelScreen) (not connected)").tag(panelScreen)
                    }
                } label: {
                    Text("Screen")
                    Text(screens.count > 1 || !panelScreen.isEmpty
                         ? "Which display the panel shows on. One that isn't connected falls back to the menu bar's."
                         : "Connect another display to put the panel there.")
                }
                .disabled(!showPanel && !showCards)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    screens = NSScreen.screens.map(\.localizedName)
                }
            }

            Section("When a session needs you") {
                Toggle(isOn: $showCards) {
                    Text("Show a card")
                    Text("In the same corner: a question, a plan to approve, an error or a finish. Recent in the toolbar keeps them either way.")
                }
                Toggle(isOn: $sound) {
                    Text("Play a sound")
                    Text("Once, when a session needs you or stops with an error, with or without the card.")
                }
            }

            MacNotificationsSection()

            Section("Heads-up") {
                Toggle(isOn: $headsUp) {
                    Text("Plan and context")
                    Text("A card when your 5-hour or weekly limit has 10% left, is on pace to run out within 45 minutes, or resets; and when the session you have open has used 85% of its context.")
                }
                Toggle(isOn: $weekInReview) {
                    Text("Week in review")
                    Text("Once a new week starts: last week's sessions, messages and busiest day.")
                }
                Toggle(isOn: $holdDuringFocus) {
                    Text("Hold finishes while Nidus is focusing")
                    Text("During a Nidus focus session, \u{201C}Finished\u{201D} cards wait for it to end, then come as one. Questions and errors still come at once.")
                }
            }

            Section("Help") {
                LabeledContent {
                    Button("Diagnostics…") { DiagnosticsWindowController.shared.show() }
                } label: {
                    Text("If specimens or cards don't show up")
                    Text("Checks each step Bench takes to see your sessions. Names no projects.")
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Theme.clay)
        .frame(width: 600, height: 720)
        .onChange(of: appearance) { BenchAppearance.apply() }
    }
}
