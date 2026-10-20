// SettingsPages.swift — Settings (⌘,), a tab for each kind of choice
// (DESIGN.md, Settings): General (who Bench is, the theme, help), Panel (the
// specimen and where it sits), Alerts (what reaches you when a session needs
// you), Usage (heads-up about your plan), Specimens (what plays) and Phone
// (Capsid on your phone, Remote/PhoneSettings.swift). Each page is a grouped
// form, as System Settings is.
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
            Tab("Phone", systemImage: "iphone", value: "phone") { PhoneSettingsView() }
        }
    }
}

extension View {
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
/// sessions, the theme, updates and help.
struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = BenchAppearance.system.rawValue
    @AppStorage(SettingsKey.shareTaskWithNidus) private var shareTaskWithNidus = false
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
                        Text("Capsid")
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
                            Text("\(problem.hint) For details, open Help → Capsid Diagnostics.")
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

            UpdatesSection()

            Section("Nidus") {
                Toggle(isOn: $shareTaskWithNidus) {
                    Text("Share the task I'm viewing with Nidus")
                    Text("While Capsid's Claude Science window is focused, Nidus can show its project and task title. Capsid clears them when you switch away.")
                }
                .onChange(of: shareTaskWithNidus) { NidusTaskContext.shared.refresh() }
            }

            Section("Help") {
                LabeledContent {
                    Button("Diagnostics…") { DiagnosticsWindowController.shared.show() }
                } label: {
                    Text("If specimens or cards don't show up")
                    Text("Checks each step Capsid takes to see your sessions. Names no projects.")
                }
            }
        }
        .settingsPage(height: 634)
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
                    InfoTitle("Screen", info: PanelInfo.screen)
                    Text(screens.count > 1 || !panelScreen.isEmpty
                         ? "Which display the panel shows on."
                         : "Connect another display to put the panel there.")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    screens = NSScreen.screens.map(\.localizedName)
                }
                Toggle(isOn: $panelWhileFront) {
                    Text("Keep showing the panel while Capsid is in front")
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
        .settingsPage(height: 504)
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
                    InfoTitle("Show a card", info: AlertsInfo.showCard)
                    Text("A card in the panel's corner when a session needs you, stops with an error or finishes.")
                }
                Toggle(isOn: $plansOnCard) {
                    InfoTitle("Show plans, questions and requests on the card", info: AlertsInfo.answerOnCard)
                    Text("Approve, reply or allow on the card, and see why a session stopped.")
                }
                .disabled(!showCards)
                Toggle(isOn: $sound) {
                    Text("Play a sound")
                    Text("Once, when a session needs you or stops with an error, with or without the card.")
                }
            }

            QuietWhilePresentingSection()

            MacNotificationsSection()

            Section("While Nidus is focusing") {
                Toggle(isOn: $holdDuringFocus) {
                    InfoTitle("Hold finishes", info: AlertsInfo.holdFinishes)
                    Text("\u{201C}Finished\u{201D} cards wait for a Nidus focus session to end, then come as one.")
                }
                // Off mid-session: what's held comes now, rather than waiting
                // for a focus session it no longer waits for.
                .onChange(of: holdDuringFocus) { _, on in if !on { LabModel.shared.releaseHeldFinishes() } }
            }
        }
        .settingsPage(height: 818)
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
                    InfoTitle("Plan and context", info: UsageInfo.headsUp)
                    Text("A card when a plan limit runs low or resets, and when a session's context fills up.")
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
        .settingsPage(height: 238)
    }
}

// MARK: The fuller explanations (the ⓘ on a row)

/// Settings → Alerts: what the line under a switch leaves out.
enum AlertsInfo {
    static let showCard = """
        Off, the panel shows only the specimen while a session works. Recent in the toolbar still lists everything \
        that happened, and the heads-up cards from the Usage tab need this on too.
        """

    static let holdFinishes = """
        During a Nidus focus session, \u{201C}Finished\u{201D} cards wait for it to end, then come as one card. \
        Questions and errors still come at once, and everything still goes to Recent in the toolbar.

        Turning this off brings what is waiting, unless Capsid is quiet for a presentation.
        """

    static let answerOnCard = """
        A plan shows its summary, with Approve and Request changes. A question shows what it asks, with Reply. A \
        permission request shows what it wants, with Allow Once or Deny when they can be answered here (code is \
        read in a small window first).

        Capsid checks that it's still the same plan, question or request before it sends anything. If it isn't, \
        or it can't be answered here, the card opens the session instead.

        A session that stopped with an error shows the first line of why, with Copy for all of it. That is read \
        from the session, once, when its card comes up. Mac notifications and your phone never show it.

        With names shown in Mac notifications, a question's notification offers its answers too.
        """
}

/// Settings → Panel.
enum PanelInfo {
    static let screen = """
        Which display the panel shows on. If the one you chose isn't connected, the panel uses the one with the \
        menu bar, and goes back to yours when it is.
        """
}

/// Settings → Usage.
enum UsageInfo {
    static let headsUp = """
        A card comes when your 5-hour or weekly limit has 10% left, is on pace to run out within 45 minutes, or \
        has just reset, and when the session you have open has used 85% of its context. Each one comes once.
        """
}
