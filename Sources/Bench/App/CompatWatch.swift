// CompatWatch.swift — what Capsid does when Claude Science's version changes
// (DESIGN.md, Diagnostics). An update can move a page hook or an answer's shape
// without a word, and the features that lean on it then keep trying and quietly
// do nothing: Close Other Tabs presses nothing, a readout goes blank. They do not
// turn themselves off. So the first time the page is ready under a version
// Capsid has not seen before, it looks once, quietly, with the same read-only
// probes Diagnostics runs (CompatProbes), and only if some of them found a
// change says so: one card naming what may not work, and a line for
// Diagnostics' "Last problem". When all answer, or are simply not on screen,
// it says nothing.
//
// The version is the one `claude-science status` reports (the same call the
// start-up makes), remembered in Capsid's settings. The first time there is
// nothing to compare with: the version is remembered and nothing is probed.
// The new version is remembered only after the look has run, so a quit before
// the page was ready looks again at the next launch.
//
// This file runs no script in the page and sends nothing: the probes are the
// ones Diagnostics already runs, which have no way to write.
import Foundation

extension SettingsKey {
    /// The Claude Science version Capsid last saw (`claude-science status`).
    /// No default: nothing stored means this is the first launch that saw one.
    static let lastScienceVersion = "lastScienceVersionSeen"
}

/// What the look after an update found, for the card and for Diagnostics.
struct CompatLook: Equatable, Sendable {
    let version: String
    /// How many probes ran.
    let checks: Int
    /// The features whose probes found a change, in the probes' order, each once.
    let features: [CompatFeature]
}

/// The pure part: what a version change and a set of probe results mean.
enum CompatWatchRules {
    enum Decision: Equatable, Sendable {
        /// The same version as last time: nothing to do.
        case unchanged
        /// Nothing stored yet: remember it, probe nothing.
        case firstSight
        /// A different version from the one remembered: look once.
        case changed
    }

    /// The longest version Capsid remembers or shows: `status` is a command
    /// line tool's answer, and a version is a handful of characters.
    static let longestVersion = 40

    /// A version worth remembering, or nil: nothing, "unknown" (what the
    /// status parser says when the field is missing), or anything that isn't a
    /// short line of printable characters.
    static func clean(_ version: String?) -> String? {
        guard let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.lowercased() != "unknown", trimmed.count <= longestVersion,
              trimmed.allSatisfy({ $0.isASCII && !$0.isNewline && ($0.isLetter || $0.isNumber || ".-+_".contains($0)) })
        else { return nil }
        return trimmed
    }

    static func decide(remembered: String?, seen: String) -> Decision {
        guard let remembered else { return .firstSight }
        return remembered == seen ? .unchanged : .changed
    }

    /// The features whose probes say Claude Science changed
    /// (`ProbeVerdict.suggestsAChange`), each once, in the probes' order.
    static func features(in results: [ProbeResult]) -> [CompatFeature] {
        var found: [CompatFeature] = []
        for result in results where result.verdict.suggestsAChange {
            guard let feature = CompatProbes.feature(ofProbe: result.name), !found.contains(feature) else { continue }
            found.append(feature)
        }
        return found
    }

    /// The Diagnostics lines for a look made this run: ✓ when nothing changed,
    /// ✗ naming the features when something did.
    static func lines(for look: CompatLook) -> [String] {
        guard !look.features.isEmpty else {
            return ["✓ Claude Science changed to \(look.version); Capsid looked at the page and the reads once, and found nothing different (\(look.checks) checks)"]
        }
        let names = look.features.map(\.inASentence).joined(separator: ", ")
        return ["✗ Claude Science changed to \(look.version); Capsid looked at the page and the reads once, and these didn't answer as it reads them: \(names)"]
    }
}

/// Watches for a new Claude Science version, and looks once when there is one.
@MainActor
final class CompatWatch {
    static let shared = CompatWatch(.live())

    /// What the watch needs from outside; tests replace every part.
    struct Dependencies {
        /// The version Capsid last saw, and where it keeps it.
        var remembered: () -> String?
        var remember: (String) -> Void
        /// The running Claude Science's version, or nil when it can't be told.
        var version: @Sendable () async -> String?
        /// The page is up and signed in.
        var isReady: @MainActor () -> Bool
        /// Waits for the page to draw before the probes look at it.
        var settle: @Sendable () async -> Void
        /// The probes, all read-only.
        var probe: @MainActor () async -> [ProbeResult]
        /// Where the one card goes.
        var post: @MainActor (LabNotice) -> Void
        var breadcrumbs: CompatBreadcrumbs
        var now: () -> Date
        /// Off in a demo: nothing is read and nothing is kept.
        var enabled: () -> Bool
    }

    /// The least time between two questions to `status`: a page that reloads
    /// often must not ask the command line each time. A minute is short enough
    /// that the reload after an update's restart is not missed.
    static let askEvery: TimeInterval = 60
    /// How long the page is given to draw after it is ready.
    static let settleFor: Duration = .seconds(4)

    private let dependencies: Dependencies
    private var asking = false
    private var lastAsked: Date?
    /// What the look after the last change found, this run only.
    private(set) var lastLook: CompatLook?

    init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// The version Capsid remembers, if it has seen one.
    var remembered: String? {
        dependencies.remembered()
    }

    /// The main page finished loading and is ready: ask for the version, at
    /// most every few minutes and never twice at once.
    @discardableResult
    func pageReady() -> Task<Void, Never>? {
        guard dependencies.enabled(), !asking else { return nil }
        let moment = dependencies.now()
        if let last = lastAsked, moment.timeIntervalSince(last) < Self.askEvery { return nil }
        lastAsked = moment
        asking = true
        return Task {
            await look()
            asking = false
        }
    }

    /// Asks for the version and, when it has changed, looks once. Separate
    /// from `pageReady` so a test can wait for it.
    func look() async {
        guard let seen = CompatWatchRules.clean(await dependencies.version()) else { return }
        switch CompatWatchRules.decide(remembered: remembered, seen: seen) {
        case .unchanged:
            return
        case .firstSight:
            dependencies.remember(seen)
            return
        case .changed:
            break
        }
        await dependencies.settle()
        // Not up after all: nothing was looked at, so the version isn't
        // remembered and the next ready page asks again.
        guard dependencies.isReady() else {
            lastAsked = nil
            return
        }
        let results = await dependencies.probe()
        dependencies.remember(seen)
        let look = CompatLook(version: seen, checks: results.count, features: CompatWatchRules.features(in: results))
        lastLook = look
        guard let notice = NoticeRules.afterUpdate(version: seen, features: look.features) else { return }
        dependencies.breadcrumbs.record(.probesAfterUpdate, affecting: look.features)
        dependencies.post(notice)
    }

    /// Diagnostics' lines about this: the version Capsid last saw, and what
    /// the look after the last change found, when there was one this run.
    func diagnosticsLines() -> [String] {
        var lines: [String] = []
        if let remembered {
            lines.append("• Claude Science version Capsid last saw: \(remembered). When it changes, Capsid looks at the page and the reads once, quietly.")
        } else {
            lines.append("• Capsid has not yet seen which Claude Science version this is; when it does it keeps it, and looks once when it changes.")
        }
        if let lastLook { lines += CompatWatchRules.lines(for: lastLook) }
        return lines
    }
}

extension CompatWatch.Dependencies {
    /// The app's own: the standard settings, `status` for the version, the
    /// shown page and the probes Diagnostics runs.
    @MainActor
    static func live() -> CompatWatch.Dependencies {
        CompatWatch.Dependencies(
            remembered: { UserDefaults.standard.string(forKey: SettingsKey.lastScienceVersion) },
            remember: { UserDefaults.standard.set($0, forKey: SettingsKey.lastScienceVersion) },
            version: { await DaemonController.runningStatus()?.version },
            isReady: { WebContainer.shared.status == .ready },
            settle: { try? await Task.sleep(for: CompatWatch.settleFor) },
            probe: { await CompatProbes.run(.live()) },
            post: { LabModel.shared.post($0) },
            breadcrumbs: .shared,
            now: { Date() },
            enabled: { Demo.mode == nil })
    }
}
