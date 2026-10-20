// SpecimenHold.swift — when the specimens stop moving (DESIGN.md, Lab,
// "Holding still"). After ten minutes with no key, click or touch on the Mac
// (two in Low Power Mode) nobody can be watching, so the working specimen
// holds a still, as it already does while its window is covered or the
// screen sleeps, and plays again on the next input.
//
// This file is the state and nothing else. The idle time, the clock, the
// power state and the wait come in as closures, so the rules are tested
// without a Mac to leave alone; `WorkingGlyph`, the panel's caption and menu
// and the turn clock ask it what to show.
import AppKit
import Combine

@MainActor
final class SpecimenHold: ObservableObject {
    static let shared = SpecimenHold()

    /// A hidden default, not a setting: seconds without input before the
    /// specimens hold still. For trying the rule without waiting ten minutes
    /// (`-specimenIdleSeconds 20` on a demo's command line) and not offered
    /// anywhere in Settings.
    static let idleKey = "specimenIdleSeconds"
    static let idleLimit: TimeInterval = 10 * 60
    /// The limit in Low Power Mode, which asked for less to be done: never
    /// longer than this.
    static let lowPowerIdleLimit: TimeInterval = 2 * 60

    /// How often it looks while the specimens play: going quiet is slow news
    /// next to a ten-minute limit, so once a minute.
    static let lookWhilePlaying: Duration = .seconds(60)
    /// How often it looks while they hold: an input should bring them back
    /// at once, and the look is one cheap call, so every two seconds.
    static let lookWhileHolding: Duration = .seconds(2)

    /// The specimens hold a still. Assigned after `heldAt`, so whoever is
    /// told reads where the hold began.
    @Published private(set) var holds = false
    /// When the hold began, on the rotation's clock
    /// (`Date.timeIntervalSinceReferenceDate`): the scene the rotation was
    /// in then is the one every copy of the specimen holds, and names.
    private(set) var heldAt: TimeInterval = 0

    /// Seconds since the last key, click or touch.
    private let secondsSinceInput: () -> TimeInterval
    private let limit: () -> TimeInterval
    private let lowPower: () -> Bool
    private let now: () -> TimeInterval
    private let wait: (Duration) async -> Void
    private let center: NotificationCenter

    /// How many views are showing something that could be told to hold: it
    /// looks only while one is, so a Capsid with nothing on screen runs no
    /// timer at all.
    private var watchers = 0
    private var looking: Task<Void, Never>?
    private var powerObserver: (any NSObjectProtocol)?

    /// The app uses `shared`; tests make their own.
    init(secondsSinceInput: @escaping () -> TimeInterval = { MacPresence.live.secondsSinceInput() },
         limit: @escaping () -> TimeInterval = { SpecimenHold.defaultLimit() },
         lowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
         now: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate },
         wait: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0, tolerance: $0 / 4) },
         center: NotificationCenter = .default) {
        self.secondsSinceInput = secondsSinceInput
        self.limit = limit
        self.lowPower = lowPower
        self.now = now
        self.wait = wait
        self.center = center
    }

    /// Ten minutes, or the hidden default when it is a number above zero.
    static func defaultLimit(_ defaults: UserDefaults = .standard) -> TimeInterval {
        let seconds = defaults.double(forKey: idleKey)
        return seconds > 0 ? seconds : idleLimit
    }

    /// Seconds without input that make the specimens hold, now.
    var idleSeconds: TimeInterval {
        lowPower() ? min(limit(), Self.lowPowerIdleLimit) : limit()
    }

    /// How long until it looks again.
    var nextLook: Duration { holds ? Self.lookWhileHolding : Self.lookWhilePlaying }

    /// Reads the idle time and settles the hold: on at the limit, off at the
    /// first input after it. Nothing is assigned when the answer stays the
    /// same, so a look that changes nothing wakes no view.
    func look() {
        let idle = secondsSinceInput() >= idleSeconds
        guard idle != holds else { return }
        if idle { heldAt = now() }
        holds = idle
    }

    /// The scene the specimens show: the one the rotation was in when the hold
    /// began, while they hold (the still, the caption and the menu agree), else
    /// the one playing at `date`.
    func scene(in rotation: Rotation, at date: Date) -> LabScene {
        let time = holds ? heldAt : date.timeIntervalSinceReferenceDate
        return rotation.scenes[rotation.scene(at: time).index]
    }

    /// Whether it is looking at all: some view is on screen.
    var isLooking: Bool { looking != nil }

    /// A view that shows something that could hold has appeared. The first
    /// looks at once: the Mac may have been left alone for an hour before a
    /// session began.
    func watch() {
        watchers += 1
        guard looking == nil else { return }
        look()
        // Low Power Mode comes and goes without any input to look at. The
        // notice may come from any thread.
        powerObserver = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.look() }
        }
        looking = Task { [weak self] in
            while !Task.isCancelled {
                guard let pause = self?.nextLook, let wait = self?.wait else { return }
                await wait(pause)
                guard !Task.isCancelled else { return }
                self?.look()
            }
        }
    }

    /// A view that showed one is gone. With the last, the looking stops; the
    /// hold stays as it was until the next view asks again.
    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        looking?.cancel()
        looking = nil
        if let powerObserver { center.removeObserver(powerObserver) }
        powerObserver = nil
    }
}
