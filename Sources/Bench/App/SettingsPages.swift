// SettingsPages.swift — Settings (⌘,), a tab for each kind of choice
// (DESIGN.md, Settings): General (who Bench is, the theme, help), Panel (the
// specimen and where it sits), Alerts (what reaches you when a session needs
// you), Usage (heads-up about your plan) and Specimens (what plays). Each
// page is a grouped form, as System Settings is.
import SwiftUI

/// The tabs. "Choose specimens…" lands on Specimens by setting the tab first.
struct SettingsView: View {
    /// Set to a tab's value before opening Settings to land on that tab.
    @AppStorage(SettingsKey.settingsTab) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") { GeneralSettingsView() }
            Tab("Panel", systemImage: "rectangle.inset.bottomright.filled", value: "panel") { PanelSettingsView() }
            Tab("Alerts", systemImage: "bell.badge", value: "alerts") { AlertSettingsView() }
            Tab("Usage", systemImage: "gauge.with.dots.needle.50percent", value: "usage") { UsageSettingsView() }
            Tab("Specimens", systemImage: "flask", value: "scenes") { SceneSettingsView() }
        }
    }
}

private extension View {
    /// A Settings page: a grouped form with switches in the one accent, at
    /// the page's own height (the window follows the tab).
    func settingsPage(height: CGFloat) -> some View {
        formStyle(.grouped)
            .toggleStyle(.switch)
            .tint(Theme.clay)
            .frame(width: 600, height: height)
    }
}

/// General: Bench's name and version, anything keeping it from your
/// sessions, the theme, and help.
struct GeneralSettingsView: View {
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

            Section("Help") {
                LabeledContent {
                    Button("Diagnostics…") { DiagnosticsWindowController.shared.show() }
                } label: {
                    Text("If specimens or cards don't show up")
                    Text("Checks each step Bench takes to see your sessions. Names no projects.")
                }
            }
        }
        .settingsPage(height: 340)
        .onChange(of: appearance) { BenchAppearance.apply() }
    }
}

/// Panel: the specimen that plays while a session works, and where the panel
/// and its cards sit.
struct PanelSettingsView: View {
    @AppStorage(SettingsKey.showPanel) private var showPanel = true
    @AppStorage(SettingsKey.showCards) private var showCards = true
    @AppStorage(SettingsKey.showMenuBarSpecimen) private var menuBarSpecimen = false
    @AppStorage(SettingsKey.showSpecimenCaption) private var showSpecimenCaption = false
    @AppStorage(SettingsKey.panelWhileFront) private var panelWhileFront = true
    @AppStorage(SettingsKey.panelCorner) private var panelCorner = PanelCorner.bottomRight
    @AppStorage(SettingsKey.panelScreen) private var panelScreen = ""
    /// The connected screens' names, kept up to date as screens come and go.
    @State private var screens: [String] = NSScreen.screens.map(\.localizedName)

    var body: some View {
        Form {
            Section("While a session works") {
                Toggle(isOn: $showPanel) {
                    Text("Show a specimen while a session works")
                    Text("It plays in the corner of your screen until the session stops. Off, cards still come.")
                }
                Toggle(isOn: $showSpecimenCaption) {
                    Text("Name the specimen that's playing")
                    Text("Its name and a few words about it, under the session in the panel.")
                }
                .disabled(!showPanel)
                Toggle(isOn: $menuBarSpecimen) {
                    Text("Show it in the menu bar too")
                    Text("While a session works, or a count while any wait. Click it for every session.")
                }
            }

            Section("Where the panel sits") {
                Picker(selection: $panelCorner) {
                    ForEach(PanelCorner.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Corner")
                    Text("Where the specimen and the cards sit.")
                }
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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    screens = NSScreen.screens.map(\.localizedName)
                }
                Toggle(isOn: $panelWhileFront) {
                    Text("Keep showing the panel while Bench is in front")
                    Text("Off, the panel waits until you switch to another app.")
                }
            }
            .disabled(!showPanel && !showCards)

            Section {
                LabeledContent {
                    Button("Choose…") { SettingsWindow.open(tab: "scenes") }
                } label: {
                    Text("Which specimens play")
                    Text("Categories, favorites, one by one, and their size: in the Specimens tab.")
                }
            }
        }
        .settingsPage(height: 540)
    }
}

/// Alerts: what reaches you when a session needs you, stops with an error or
/// finishes, on the panel, as a sound or as a Mac notification, and what
/// waits while Nidus is focusing.
struct AlertSettingsView: View {
    @AppStorage(SettingsKey.showCards) private var showCards = true
    @AppStorage(SettingsKey.soundOnNeedsInput) private var sound = true
    @AppStorage(SettingsKey.showPlansOnCard) private var plansOnCard = true
    @AppStorage(SettingsKey.holdDuringFocus) private var holdDuringFocus = true

    var body: some View {
        Form {
            Section("On the panel") {
                Toggle(isOn: $showCards) {
                    Text("Show a card")
                    Text("In the panel's corner: a question, a plan to approve, an error or a finish. Recent in the toolbar keeps them either way.")
                }
                Toggle(isOn: $plansOnCard) {
                    Text("Show plans on the card, with Approve")
                    Text("When a session asks you to approve its plan, the card shows the plan's summary and an Approve button. Bench checks it's still the same plan before approving; anything else opens the session.")
                }
                .disabled(!showCards)
                Toggle(isOn: $sound) {
                    Text("Play a sound")
                    Text("Once, when a session needs you or stops with an error, with or without the card.")
                }
            }

            MacNotificationsSection()

            Section("While Nidus is focusing") {
                Toggle(isOn: $holdDuringFocus) {
                    Text("Hold finishes")
                    Text("During a Nidus focus session, \u{201C}Finished\u{201D} cards wait for it to end, then come as one. Questions and errors still come at once.")
                }
            }
        }
        .settingsPage(height: 800)
    }
}

/// Usage: heads-up about your plan and your week.
struct UsageSettingsView: View {
    @AppStorage(SettingsKey.headsUpNotices) private var headsUp = true
    @AppStorage(SettingsKey.weekInReview) private var weekInReview = true

    var body: some View {
        Form {
            Section("Heads-up") {
                Toggle(isOn: $headsUp) {
                    Text("Plan and context")
                    Text("A card when your 5-hour or weekly limit has 10% left, is on pace to run out within 45 minutes, or resets; and when the session you have open has used 85% of its context.")
                }
                Toggle(isOn: $weekInReview) {
                    Text("Week in review")
                    Text("Once a new week starts: last week's sessions, messages and busiest day.")
                }
            }
            Section {
                Text("Your plan's limits, the pace you're on, and your activity are in the toolbar's usage readout: click it for the details.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage(height: 300)
    }
}
