// Welcome.swift — the first-run welcome (DESIGN.md, Welcome window): four
// short pages in a plain window, shown once to someone who is new to Bench
// and again from Help → Welcome to Capsid. The window and its frame are
// TourWindow.swift's, which What's New (App/WhatsNew.swift) shares.
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
    private var tour: TourFlow

    /// `number` counts from 1, as the pages are numbered; one out of range
    /// lands on the nearest page.
    init(startingAt number: Int? = nil) {
        tour = TourFlow(count: WelcomePage.allCases.count, startingAt: number)
    }

    var page: WelcomePage { WelcomePage(rawValue: tour.index) ?? .welcome }
    var isFirst: Bool { tour.isFirst }
    var isLast: Bool { tour.isLast }
    /// The same position as steps of a tour, for the window's footer.
    var steps: TourFlow { tour }

    mutating func next() { tour.next() }
    mutating func back() { tour.back() }
}

@MainActor
final class WelcomeModel: ObservableObject {
    @Published var flow = WelcomeFlow()
}

// MARK: The window

@MainActor
final class WelcomeWindowController: NSObject {
    static let shared = WelcomeWindowController()

    private let model = WelcomeModel()
    /// Whether closing the window counts as having seen it. A demo's doesn't:
    /// it writes nothing (Demo.swift).
    private var records = true

    private lazy var tour: TourWindow = {
        let tour = TourWindow(title: "Welcome to Capsid") { [model] close in
            NSHostingController(rootView: WelcomeView(model: model, close: close))
        }
        // Every way of closing it ends here: Get Started, Esc and the close button.
        tour.didClose = { [weak self] in
            if self?.records == true { WelcomeGate.markSeen() }
        }
        return tour
    }()

    /// Whether the window is on screen.
    var isVisible: Bool { tour.isVisible }

    /// At launch: the first one only (WelcomeGate).
    func showIfFirstLaunch() {
        if WelcomeGate.shouldShowAtLaunch() { show() }
    }

    /// Help → Welcome to Capsid, from the first page. Already open, it only
    /// comes forward.
    func show() { present(page: nil, records: true, activation: .activating) }

    /// `--demo welcome`: `page` counts from 1. Quiet, it doesn't take the
    /// keyboard.
    func showDemo(page: Int?, quiet: Bool) { present(page: page, records: false, activation: quiet ? .quiet : .activating) }

    private func present(page: Int?, records: Bool, activation: TourActivation) {
        self.records = records
        tour.present(activation) { model.flow = WelcomeFlow(startingAt: page) }
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
        TourChrome(flow: model.flow.steps, lastTitle: "Get Started",
                   back: { model.flow.back() }, next: { model.flow.next() }, close: close) {
            switch model.flow.page {
            case .welcome: IntroPage()
            case .panel: PanelPage()
            case .gettingAround: AroundPage()
            case .updates: UpdatesPage(checkForUpdates: $checkForUpdates)
            }
        }
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
            TourBodyText("Capsid keeps Claude Science in one window, and lets you know when a session needs you.")
            TourNote("A Solanum product. Unofficial, and not affiliated with Anthropic.")
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
            TourHeading("The panel")
            TourWell {
                WorkingGlyph(tint: colorScheme.sceneInk, rotation: settings.rotation)
                    .frame(width: Theme.sceneSize, height: Theme.sceneSize)
            }
            TourBodyText("While a session works, a specimen plays in the corner of your screen. When a session needs you, a card takes its place: Open it, Approve a plan, or put it off with Later.")
            TourNote("The corner, the screen and which specimens play are yours to choose in Settings (⌘,).")
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
            TourHeading("Getting around")
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
            TourHeading("Updates and privacy")
            TourBodyText("Capsid reads your sessions on this Mac and changes nothing in Claude Science, except when you press Approve on a plan, or act from a phone you’ve paired.")
            TourSwitchRow(title: "Check for updates once a day",
                          detail: "Asks GitHub for the latest Capsid release. Nothing about you or your sessions is sent.",
                          isOn: $checkForUpdates)
                .padding(.top, 4)
        }
        .padding(.horizontal, 48)
        .padding(.top, 40)
    }
}
