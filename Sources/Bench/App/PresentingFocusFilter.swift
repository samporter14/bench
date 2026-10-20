// PresentingFocusFilter.swift — Capsid's macOS Focus filter (DESIGN.md, Quiet
// while presenting). In System Settings → Focus, under a Focus such as one
// the user keeps for presenting, Focus filters → Add Filter → Capsid adds this,
// with one switch. While that Focus is on, Capsid stays out of sight
// (PresentingMode.swift).
//
// How the system runs it (SetFocusFilterIntent, and Apple's article "Defining
// your app's Focus filter"): `perform()` runs when the Focus turns on, with
// the switch as the user set it, and again when it turns off, with the
// parameter's default. So the default is the answer for "no Focus": a filter
// with no parameter could not tell the two apart. A Focus that was already on
// when Capsid launched ran it before there was a Capsid to hear it, so launch
// asks `current` once (PresentingMode.start).
//
// SwiftPM does not extract App Intents metadata the way Xcode does, so System
// Settings sees this only if Scripts/appintents-metadata.sh has put
// Metadata.appintents into the app bundle (Scripts/build-app.sh does).
import AppIntents

struct QuietWhilePresentingFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Quiet While Presenting"
    static let description = IntentDescription(
        "Keeps Capsid's panel, cards, sounds and notifications out of sight while this Focus is on. What finished comes as one card afterwards.")

    /// On for a Focus that should keep Capsid quiet. The default is off, which
    /// is what the system passes when the Focus ends.
    @Parameter(title: "Keep Capsid quiet", default: false)
    var quiet: Bool

    init() {}

    init(quiet: Bool) {
        self.quiet = quiet
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: quiet ? "Keep Capsid quiet" : "Capsid as usual",
            subtitle: quiet ? "No panel, sounds or notifications" : nil)
    }

    /// Suggested with the switch already on: the filter's default is off, so
    /// adding it without this would do nothing until the switch was turned on.
    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [QuietWhilePresentingFilter] {
        [QuietWhilePresentingFilter(quiet: true)]
    }

    func perform() async throws -> some IntentResult {
        let quiet = quiet
        await MainActor.run {
            // A demo is made-up data and starts nothing real.
            guard Demo.mode == nil else { return }
            PresentingMode.shared.setFocusFilter(quiet)
        }
        return .result()
    }
}

extension PresentingMode {
    /// Starts the Focus-filter half: the model tells the Lab when quiet
    /// begins and ends, and the filter the system last ran is read once, for a
    /// Focus that was already on. Nothing in a demo, which starts nothing real
    /// (AppDelegate returns before this as well).
    func start(inDemo: Bool = Demo.mode != nil, currentFilter: @escaping () async -> Bool? = {
        // `current` throws when no filter is configured; that is off.
        try? await QuietWhilePresentingFilter.current.quiet
    }) {
        guard !inDemo else { return }
        changed = { _ in LabModel.shared.quietChanged() }
        Task { [weak self] in
            self?.catchUp(await currentFilter())
        }
    }
}
