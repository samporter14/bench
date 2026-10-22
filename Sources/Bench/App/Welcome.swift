// Welcome.swift — the first-run welcome (DESIGN.md, Welcome window): four
// short pages in a plain window, shown once to someone who is new to Bench
// and again from Help → Welcome to Capsid.
import AppKit
import SwiftUI

// MARK: When it shows

/// Whether the welcome shows at launch: once, and not to someone who used
/// Bench before it existed.
enum WelcomeGate {
    /// Settings an earlier Bench stores only after someone has changed them,
    /// so one being stored means this Mac has run Bench and been used.
    static let earlierSettings: Set<String> = [
        // SceneSettings.Key.groups, which is private there.
        "sceneGroups",
        SettingsKey.settingsTab,
        SettingsKey.appearance,
        SettingsKey.showPanel,
    ]

    /// Pure: whether any of the keys stored for the app is one of those.
    static func isExistingUser(storedKeys: Set<String>) -> Bool {
        !storedKeys.isDisjoint(with: earlierSettings)
    }

    /// Pure: the welcome is for someone who hasn't seen it and is new.
    static func shouldShow(hasSeen: Bool, storedKeys: Set<String>) -> Bool {
        !hasSeen && !isExistingUser(storedKeys: storedKeys)
    }

    /// The domain `UserDefaults.standard` stores the app's settings in.
    static var appDomain: String {
        Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    }

    /// The keys actually stored in the domain. Not `object(forKey:)` or
    /// `dictionaryRepresentation()`: both include the defaults Bench
    /// registers at launch, which would make every install look used.
    static func storedKeys(in defaults: UserDefaults, domain: String) -> Set<String> {
        guard let stored = defaults.persistentDomain(forName: domain) else { return [] }
        return Set(stored.keys)
    }

    /// At launch: whether to show the welcome. Someone who used Bench before
    /// is marked as having seen it, so the answer stays no.
    static func shouldShowAtLaunch(defaults: UserDefaults = .standard, domain: String = WelcomeGate.appDomain) -> Bool {
        let hasSeen = defaults.bool(forKey: SettingsKey.hasSeenWelcome)
        let stored = storedKeys(in: defaults, domain: domain)
        if !hasSeen, isExistingUser(storedKeys: stored) { markSeen(in: defaults) }
        return shouldShow(hasSeen: hasSeen, storedKeys: stored)
    }

    static func markSeen(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: SettingsKey.hasSeenWelcome)
    }
}

// MARK: The pages

enum WelcomePage: Int, CaseIterable {
    case welcome, panel, gettingAround, updates
}

/// Which page is showing, and the steps between them. Both ends stop.
struct WelcomeFlow: Equatable {
    private(set) var page: WelcomePage

    /// `number` counts from 1, as the pages are numbered; one out of range
    /// lands on the nearest page.
    init(startingAt number: Int? = nil) {
        let index = min(max((number ?? 1) - 1, 0), WelcomePage.allCases.count - 1)
        page = WelcomePage(rawValue: index) ?? .welcome
    }

    var isFirst: Bool { page == WelcomePage.allCases.first }
    var isLast: Bool { page == WelcomePage.allCases.last }

    mutating func next() {
        if let next = WelcomePage(rawValue: page.rawValue + 1) { page = next }
    }

    mutating func back() {
        if let back = WelcomePage(rawValue: page.rawValue - 1) { page = back }
    }
}

@MainActor
final class WelcomeModel: ObservableObject {
    @Published var flow = WelcomeFlow()
}

// MARK: The window

/// Esc closes it, as in any Mac window.
private final class WelcomeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private let model = WelcomeModel()
    /// Whether closing the window counts as having seen it. A demo's doesn't:
    /// it writes nothing (Demo.swift).
    private var records = true

    private lazy var window: NSWindow = {
        let hosting = NSHostingController(rootView: WelcomeView(model: model) { [weak self] in self?.window.close() })
        let window = WelcomeWindow(contentViewController: hosting)
        window.title = "Welcome to Capsid"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 460))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.delegate = self
        return window
    }()

    /// At launch: the first one only (WelcomeGate).
    func showIfFirstLaunch() {
        if WelcomeGate.shouldShowAtLaunch() { show() }
    }

    /// Help → Welcome to Capsid, from the first page. Already open, it only
    /// comes forward.
    func show() { present(page: nil, records: true, quiet: false) }

    /// `--demo welcome`: `page` counts from 1. Quiet, it doesn't take the
    /// keyboard.
    func showDemo(page: Int?, quiet: Bool) { present(page: page, records: false, quiet: quiet) }

    private func present(page: Int?, records: Bool, quiet: Bool) {
        self.records = records
        if !window.isVisible {
            model.flow = WelcomeFlow(startingAt: page)
            window.center()
        }
        if quiet {
            window.orderFrontRegardless()
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Every way of closing it ends here: Get Started, Esc and the close button.
    func windowWillClose(_ notification: Notification) {
        if records { WelcomeGate.markSeen() }
    }
}

// MARK: The content

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let close: @MainActor () -> Void
    @AppStorage(SettingsKey.checkForUpdates) private var checkForUpdates = true

    init(model: WelcomeModel, close: @escaping @MainActor () -> Void) {
        self.model = model
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.flow.page {
                case .welcome: IntroPage()
                case .panel: PanelPage()
                case .gettingAround: AroundPage()
                case .updates: UpdatesPage(checkForUpdates: $checkForUpdates)
                }
            }
            // The headings stay where they are from page to page; the first
            // page centres itself.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        // Fixed, so the window doesn't change size from page to page.
        .frame(width: 560, height: 460)
        // Esc, when SwiftUI has the key; the window's own cancelOperation
        // takes it otherwise (WelcomeWindow).
        .onExitCommand { close() }
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(WelcomePage.allCases, id: \.self) { page in
                    Circle()
                        .fill(page == model.flow.page ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(model.flow.page.rawValue + 1) of \(WelcomePage.allCases.count)")

            HStack {
                Button("Back") { model.flow.back() }
                    .buttonStyle(.glass)
                    .opacity(model.flow.isFirst ? 0 : 1)
                    .disabled(model.flow.isFirst)
                    .accessibilityHidden(model.flow.isFirst)
                Spacer(minLength: 0)
                Button(model.flow.isLast ? "Get Started" : "Next") {
                    if model.flow.isLast { close() } else { model.flow.next() }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.clay)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct Heading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct BodyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
    }
}

/// 1. Who Bench is.
private struct IntroPage: View {
    @AppStorage(SettingsKey.appIcon) private var appIcon = AppIconChoice.standard.rawValue

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: AppIconChoice.shown(appIcon))
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Welcome to Capsid")
                .font(.system(size: 26, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            BodyText("Capsid keeps Claude Science in one window, and lets you know when a session needs you.")
            Note("A Solanum product. Unofficial, and not affiliated with Anthropic.")
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 2. The panel: a specimen playing at the panel's size, as it will in the
/// corner.
private struct PanelPage: View {
    @ObservedObject private var settings = SceneSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            Heading("The panel")
            WorkingGlyph(tint: colorScheme.sceneInk, rotation: settings.rotation)
                .frame(width: Theme.sceneSize, height: Theme.sceneSize)
                .padding(Theme.panelPadding)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.panelCorner))
                .accessibilityHidden(true)
            BodyText("While a session works, a specimen plays in the corner of your screen. When a session needs you, a card takes its place: Open it, Approve a plan, or put it off with Later.")
            Note("The corner, the screen and which specimens play are yours to choose in Settings (⌘,).")
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }
}

/// 3. Where things are.
private struct AroundPage: View {
    private struct Way: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var keys: String?
        var id: String { title }
    }

    private let ways = [
        Way(symbol: "magnifyingglass", title: "Quick Open", detail: "Type to jump to a session.", keys: "⌘⇧O"),
        Way(symbol: "clock.arrow.circlepath", title: "The activity list",
            detail: "Click the status in the toolbar: every session, and what happened lately."),
        Way(symbol: "star", title: "Favorites",
            detail: "Star specimens in Settings → Specimens, and play only those if you like."),
        Way(symbol: "bell.badge", title: "Mac notifications",
            detail: "In Settings → Alerts. Off unless you turn them on."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            Heading("Getting around")
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ways) { way in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: way.symbol)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(way.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(way.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let keys = way.keys {
                            Text(keys)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 56)
        .padding(.top, 40)
    }
}

/// 4. What Bench reads, and the one request it can make.
private struct UpdatesPage: View {
    @Binding var checkForUpdates: Bool

    var body: some View {
        VStack(spacing: 18) {
            Heading("Updates and privacy")
            BodyText("Capsid reads your sessions on this Mac and changes nothing in Claude Science, except when you press Approve on a plan, or act from a phone you’ve paired.")
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates once a day")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Asks GitHub for the latest Capsid release. Nothing about you or your sessions is sent.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Check for updates once a day", isOn: $checkForUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.clay)
                    .accessibilityHint("Asks GitHub for the latest Capsid release. Nothing about you or your sessions is sent.")
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
            .padding(.top, 4)
        }
        .padding(.horizontal, 48)
        .padding(.top, 40)
    }
}
