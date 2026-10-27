// WhatsNew.swift — "What's New in Capsid" (DESIGN.md, What's New window): a few
// short pages shown once to someone who is updating, in the Welcome's window
// (App/TourWindow.swift). This file is what decides, and none of it draws:
//   - the table of releases and their pages (`WhatsNew`), where a future
//     release only adds an entry;
//   - who sees which release (`WhatsNewGate`), pure apart from one thin
//     wrapper over a `UserDefaults`;
//   - when the window may come up (`WhatsNewTiming`, `WhatsNewPresenter`):
//     only while Capsid is the app in use, and never over a card or a sheet.
// The window and its pages are in WhatsNewWindow.swift.
import AppKit
import Foundation

// MARK: The table

/// One page: a heading, a line or two, and one illustration.
struct WhatsNewPage: Equatable, Identifiable, Sendable {
    enum Art: Equatable, Sendable {
        /// One SF Symbol, in ink, in the glass well.
        case symbol(String)
        /// These specimens (names in `LabScenes.catalogue`), playing in the
        /// well one after another; the first, still, under Reduce Motion.
        case specimens([String])
    }

    /// A real setting the page carries as a native switch.
    enum Control: Equatable, Sendable {
        case playShortSequences
    }

    let title: String
    let text: String
    let art: Art
    var control: Control?

    var id: String { title }
}

/// A release's pages. `version` is major.minor, as "1.1": every 1.1.x is this
/// release.
struct WhatsNewRelease: Equatable, Sendable {
    let version: String
    let pages: [WhatsNewPage]

    /// `version` as a number to compare; nil for one that isn't a version.
    var number: BenchVersion? { BenchVersion(version) }
}

enum WhatsNew {
    /// Oldest first. A release without an entry has no What's New, and shows
    /// nothing; the next release adds an entry here and nothing else.
    static let releases: [WhatsNewRelease] = [release11]

    /// 1.1: four pages.
    static let release11 = WhatsNewRelease(version: "1.1", pages: [
        WhatsNewPage(
            title: "Compare two things on the Shelf",
            text: "Right-click a picture or a text file on the Shelf and choose Compare With. Pictures sit side by side, or one wipes over the other; for text, you see what changed, line by line.",
            art: .symbol("square.split.2x1")),
        WhatsNewPage(
            title: "Project Workspaces",
            text: "Each project keeps its last conversation, the references you pin to it and a small working note. History → Return to Project brings them back together. There’s nothing to save.",
            art: .symbol("folder")),
        WhatsNewPage(
            title: "Fourteen new specimens",
            text: "Capillary electrophoresis, a Möbius strip, a paramecium, a fern unfurling and ten more. When a session finishes, they settle to a stop. Turn on Play short sequences and now and then a few play in order, like a little story.",
            art: .specimens(["Capillary electrophoresis", "Paramecium", "Microtome ribbon", "Pollination",
                             "Droplet coalescence", "Sanger chromatogram", "Slime mold maze", "Confocal z-stack",
                             "Möbius strip", "Contact angle", "Bayesian update", "Posterior predictive check",
                             "Fern unfurling", "Diatom"]),
            control: .playShortSequences),
        WhatsNewPage(
            title: "Show Where It Came From",
            text: "From the Shelf, it now opens the conversation at the exact reply something came from, with its results in view.",
            art: .symbol("text.bubble")),
    ])

    /// The app's version, "1.1.0"; empty when it has none (a bare binary).
    static var runningVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Pure: major.minor of a version, so 1.1.0 and 1.1.1 are both 1.1 and a
    /// bare 1 is 1.0. Nil for text that isn't a version.
    static func releaseNumber(of appVersion: String) -> BenchVersion? {
        guard let version = BenchVersion(appVersion), let major = version.parts.first else { return nil }
        let minor = version.parts.count > 1 ? version.parts[1] : 0
        return BenchVersion("\(major).\(minor)")
    }

    /// Pure: the entry for the release this version belongs to, if it has one.
    static func release(for appVersion: String, in table: [WhatsNewRelease] = releases) -> WhatsNewRelease? {
        guard let number = releaseNumber(of: appVersion) else { return nil }
        return table.first { $0.number == number }
    }

    /// Pure: what Help → What's New in Capsid shows. The entry for this
    /// release; failing that the newest entry up to it (a release without one
    /// of its own, 1.2 after 1.1); failing that the newest there is (a build
    /// older than every entry, which only a developer's has).
    static func forHelp(appVersion: String, in table: [WhatsNewRelease] = releases) -> WhatsNewRelease? {
        if let exact = release(for: appVersion, in: table) { return exact }
        if let number = releaseNumber(of: appVersion),
           let earlier = table.last(where: { ($0.number ?? number) < number }) { return earlier }
        return table.last
    }
}

// MARK: Who sees it

/// Whether a release's pages are shown, at launch and later, and what is
/// recorded. Pure apart from the wrappers over a `UserDefaults`.
enum WhatsNewGate {
    enum Verdict: Equatable {
        /// Nothing to show now, and nothing to record.
        case nothing
        /// A fresh install: the Welcome has this Mac, and it started on this
        /// release, so this release's notes are not news. Record it as seen.
        case startedHere(WhatsNewRelease)
        /// Someone who has used Capsid, updating to a release with an entry
        /// they haven't seen.
        case show(WhatsNewRelease)
    }

    /// Pure: someone who has used an earlier Capsid has seen the Welcome, or
    /// is taken for having (`WelcomeGate.isExistingUser`: a setting only a
    /// used Capsid stores).
    static func usedBefore(hasSeenWelcome: Bool, storedKeys: Set<String>) -> Bool {
        hasSeenWelcome || WelcomeGate.isExistingUser(storedKeys: storedKeys)
    }

    /// Pure: what to do for this version.
    ///
    /// - A demo: nothing, ever.
    /// - A version whose release has no entry: nothing.
    /// - An entry already seen (`seen` is that release or a later one, so a
    ///   patch release, a reinstalled older one or a Mac that has gone on
    ///   since all stay quiet): nothing.
    /// - Not used before: `startedHere`.
    /// - Otherwise: show it.
    static func verdict(appVersion: String, seen: String?, usedBefore: Bool, isDemo: Bool,
                        table: [WhatsNewRelease] = WhatsNew.releases) -> Verdict {
        guard !isDemo, let release = WhatsNew.release(for: appVersion, in: table), let number = release.number else { return .nothing }
        if let seen, let seenNumber = BenchVersion(seen), seenNumber >= number { return .nothing }
        return usedBefore ? .show(release) : .startedHere(release)
    }

    // MARK: Over UserDefaults

    /// The last release recorded as seen, "1.1"; nil for none.
    static func seen(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: SettingsKey.whatsNewSeen)
    }

    /// Records the release as seen, never going back to an earlier one.
    static func markSeen(_ release: WhatsNewRelease, in defaults: UserDefaults = .standard) {
        if let seen = seen(in: defaults).flatMap(BenchVersion.init), let number = release.number, seen >= number { return }
        defaults.set(release.version, forKey: SettingsKey.whatsNewSeen)
    }

    /// `verdict` over what the defaults hold now. The stored keys, not
    /// `object(forKey:)`: see `WelcomeGate.storedKeys`.
    static func verdict(appVersion: String = WhatsNew.runningVersion, defaults: UserDefaults = .standard,
                        domain: String = WelcomeGate.appDomain, isDemo: Bool,
                        table: [WhatsNewRelease] = WhatsNew.releases) -> Verdict {
        let used = usedBefore(hasSeenWelcome: defaults.bool(forKey: SettingsKey.hasSeenWelcome),
                              storedKeys: WelcomeGate.storedKeys(in: defaults, domain: domain))
        return verdict(appVersion: appVersion, seen: seen(in: defaults), usedBefore: used, isDemo: isDemo, table: table)
    }

    /// At launch: a fresh install records the release it started on as seen,
    /// and nothing is shown for it, now or at any later activation.
    static func settleAtLaunch(appVersion: String = WhatsNew.runningVersion, defaults: UserDefaults = .standard,
                               domain: String = WelcomeGate.appDomain, isDemo: Bool,
                               table: [WhatsNewRelease] = WhatsNew.releases) {
        if case .startedHere(let release) = verdict(appVersion: appVersion, defaults: defaults, domain: domain, isDemo: isDemo, table: table) {
            markSeen(release, in: defaults)
        }
    }

    /// The release to show now, if there is one; read afresh each time, so
    /// one seen meanwhile (Help → What's New, closed) is not shown again.
    static func pending(appVersion: String = WhatsNew.runningVersion, defaults: UserDefaults = .standard,
                        domain: String = WelcomeGate.appDomain, isDemo: Bool,
                        table: [WhatsNewRelease] = WhatsNew.releases) -> WhatsNewRelease? {
        if case .show(let release) = verdict(appVersion: appVersion, defaults: defaults, domain: domain, isDemo: isDemo, table: table) {
            return release
        }
        return nil
    }

    /// The window has closed, by Continue, Esc or the close button. A real
    /// window records its release as seen; a demo's records nothing.
    static func closed(_ release: WhatsNewRelease, records: Bool, in defaults: UserDefaults = .standard) {
        if records { markSeen(release, in: defaults) }
    }
}

// MARK: When it shows

enum WhatsNewTiming {
    enum Decision: Equatable {
        case show
        /// Not now: the next time Capsid is brought to the front.
        case wait
    }

    /// Pure: whether the window may come up this moment. All of these must
    /// hold: there is a release to show; Capsid is the app in use (it is never
    /// activated to show this); the window isn't open already; and nothing of
    /// Capsid's that wants the user first is up (a card, a sheet, a reply
    /// window, the home popover, Quick Start or Quick Open, or Capsid
    /// kept quiet for a presentation).
    static func decide(hasPending: Bool, isActive: Bool, isOpen: Bool, somethingIsUp: Bool) -> Decision {
        hasPending && isActive && !isOpen && !somethingIsUp ? .show : .wait
    }
}

/// Shows the pending release the first time Capsid is the app in use, at
/// launch or when it is next brought to the front, and not before. What it
/// asks of the world is passed in, so the rules run on made-up answers.
@MainActor
final class WhatsNewPresenter {
    private let pending: @MainActor () -> WhatsNewRelease?
    private let isActive: @MainActor () -> Bool
    private let somethingIsUp: @MainActor () -> Bool
    private let isOpen: @MainActor () -> Bool
    private let show: @MainActor (WhatsNewRelease) -> Void
    private let center: NotificationCenter
    private let settle: Duration

    private var observer: (any NSObjectProtocol)?
    private var waiting: Task<Void, Never>?

    /// `settle` is how long after launch or an activation it looks: the
    /// panel's cards are read a moment after launch, and are in the way when
    /// they come.
    init(pending: @escaping @MainActor () -> WhatsNewRelease?,
         isActive: @escaping @MainActor () -> Bool,
         somethingIsUp: @escaping @MainActor () -> Bool,
         isOpen: @escaping @MainActor () -> Bool,
         show: @escaping @MainActor (WhatsNewRelease) -> Void,
         center: NotificationCenter = .default,
         settle: Duration = .seconds(1.5)) {
        self.pending = pending
        self.isActive = isActive
        self.somethingIsUp = somethingIsUp
        self.isOpen = isOpen
        self.show = show
        self.center = center
        self.settle = settle
    }

    /// Whether it is listening for Capsid being brought to the front.
    var isListening: Bool { observer != nil }

    /// At launch, once. With nothing to show for this version it does not
    /// listen at all.
    func start() {
        guard observer == nil, pending() != nil else { return }
        observer = center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activated() }
        }
        activated()
    }

    func stop() {
        if let observer { center.removeObserver(observer) }
        observer = nil
        waiting?.cancel()
        waiting = nil
    }

    /// Capsid is in front, now or just now: look once the cards have had a
    /// moment to appear.
    func activated() {
        waiting?.cancel()
        guard settle > .zero else {
            attempt()
            return
        }
        waiting = Task { [settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
            attempt()
        }
    }

    /// Shows the release if every condition holds this moment; returns
    /// whether it did. Nothing is recorded by showing; closing records it.
    @discardableResult
    func attempt() -> Bool {
        let release = pending()
        // Seen meanwhile, say from Help: nothing is left to wait for.
        if release == nil { stop() }
        guard let release,
              WhatsNewTiming.decide(hasPending: true, isActive: isActive(), isOpen: isOpen(), somethingIsUp: somethingIsUp()) == .show
        else { return false }
        show(release)
        return true
    }
}
