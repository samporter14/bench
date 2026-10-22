// GlobalHotKey.swift — Quick Start's and Reply's keys from anywhere (DESIGN.md,
// Quick Start → Keys). Carbon's `RegisterEventHotKey`: it asks for no
// Accessibility or Input Monitoring permission, because the system matches the
// key and hands Capsid one event for it, never the keystrokes themselves.
//
// The keys are a short list, not free recording: each is control and option,
// usually with command, on a key no text field or Claude Science page uses. A
// choice is stored by name (`SettingsKey.quickStartKey`, `replyKey`) and read
// when Capsid starts and when Settings → General → Keyboard changes it. A key
// another app already holds can't be registered; Settings says so under the
// pop-up, and the other key keeps working.
//
// ⌃⌥Space is also macOS's own shortcut for "select the next source in the
// Input menu", off until the person turns it on in Keyboard settings; Settings
// says so when it is chosen.
import Carbon.HIToolbox
import Foundation
import SwiftUI

enum GlobalHotKey {
    /// What a person can pick for one of the two keys. The raw value is what is
    /// stored.
    enum Choice: String, CaseIterable, Identifiable, Sendable {
        case none
        case controlOptionCommandSpace
        case controlOptionSpace
        case controlOptionCommandR
        case controlOptionCommandN

        var id: String { rawValue }

        /// The choice a stored string names, else `fallback` (a value this
        /// build doesn't know, or none stored).
        static func parse(_ raw: String?, fallback: Choice) -> Choice {
            raw.flatMap(Choice.init(rawValue:)) ?? fallback
        }

        /// A virtual key code (`kVK_…`), nil for none.
        var keyCode: UInt32? {
            switch self {
            case .none: nil
            case .controlOptionCommandSpace, .controlOptionSpace: UInt32(kVK_Space)
            case .controlOptionCommandR: UInt32(kVK_ANSI_R)
            case .controlOptionCommandN: UInt32(kVK_ANSI_N)
            }
        }

        /// Carbon's modifier mask (`controlKey` …), 0 for none.
        var carbonModifiers: UInt32 {
            switch self {
            case .none: 0
            case .controlOptionSpace: UInt32(controlKey | optionKey)
            default: UInt32(controlKey | optionKey | cmdKey)
            }
        }

        /// How it reads in a pop-up and a menu: "⌃⌥⌘Space".
        var title: String {
            switch self {
            case .none: "None"
            case .controlOptionCommandSpace: "⌃⌥⌘Space"
            case .controlOptionSpace: "⌃⌥Space"
            case .controlOptionCommandR: "⌃⌥⌘R"
            case .controlOptionCommandN: "⌃⌥⌘N"
            }
        }

        /// Whether macOS may already use it, for the note under the pop-up.
        var mayBeTheInputSourceKey: Bool { self == .controlOptionSpace }

        /// For the File menu's item, which shows the key beside Quick Start…
        var menuShortcut: KeyboardShortcut? {
            switch self {
            case .none: nil
            case .controlOptionCommandSpace: KeyboardShortcut(.space, modifiers: [.control, .option, .command])
            case .controlOptionSpace: KeyboardShortcut(.space, modifiers: [.control, .option])
            case .controlOptionCommandR: KeyboardShortcut("r", modifiers: [.control, .option, .command])
            case .controlOptionCommandN: KeyboardShortcut("n", modifiers: [.control, .option, .command])
            }
        }
    }

    /// The two keys.
    enum Slot: String, CaseIterable, Sendable {
        case quickStart, reply

        var setting: String {
            switch self {
            case .quickStart: SettingsKey.quickStartKey
            case .reply: SettingsKey.replyKey
            }
        }

        /// What it is when nothing (or nothing known) is stored: the same as
        /// the registered defaults.
        var fallback: Choice {
            switch self {
            case .quickStart: .controlOptionCommandSpace
            case .reply: .controlOptionCommandR
            }
        }

        /// In a sentence: "Quick Start's key".
        var words: String {
            switch self {
            case .quickStart: "Quick Start"
            case .reply: "Reply"
            }
        }

        var number: UInt32 {
            switch self {
            case .quickStart: 1
            case .reply: 2
            }
        }
    }

    /// The sentence for a key that couldn't be registered.
    static func problem(for status: OSStatus, choice: Choice, taken: Slot? = nil) -> String {
        if let taken { return "\(choice.title) is already \(taken.words)'s key. Pick another." }
        if status == OSStatus(eventHotKeyExistsErr) {
            return "Another app already uses \(choice.title). Pick another key."
        }
        return "macOS wouldn't take \(choice.title) (error \(status)). Pick another key."
    }
}

/// What registers a key with the system: Carbon in the app, a fake in tests.
@MainActor
protocol HotKeyBackend: AnyObject {
    /// `noErr`, or the system's reason it couldn't.
    func register(_ slot: GlobalHotKey.Slot, keyCode: UInt32, modifiers: UInt32) -> OSStatus
    func unregister(_ slot: GlobalHotKey.Slot)
}

/// The two keys, registered from settings; what each does is set by the app.
@MainActor
final class GlobalKeys: ObservableObject {
    static let shared = GlobalKeys(backend: CarbonHotKeys.shared, defaults: UserDefaults.standard)

    /// A sentence for each key that isn't working, for Settings.
    @Published private(set) var problems: [GlobalHotKey.Slot: String] = [:]
    /// What each key is now registered as (`.none` for off).
    private(set) var active: [GlobalHotKey.Slot: GlobalHotKey.Choice] = [:]
    /// What a press does.
    var actions: [GlobalHotKey.Slot: @MainActor () -> Void] = [:]

    private let backend: HotKeyBackend
    private let defaults: SettingsStoring
    /// The choice a slot failed with, so a settings change that isn't its own
    /// doesn't ask the system again.
    private var failed: [GlobalHotKey.Slot: GlobalHotKey.Choice] = [:]
    private var lastPress: [GlobalHotKey.Slot: Date] = [:]
    private var observer: NSObjectProtocol?
    private let now: () -> Date

    init(backend: HotKeyBackend, defaults: SettingsStoring, now: @escaping () -> Date = { Date() }) {
        self.backend = backend
        self.defaults = defaults
        self.now = now
    }

    /// Registers both keys, and again whenever a setting changes.
    func start() {
        apply()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for slot in GlobalHotKey.Slot.allCases { backend.unregister(slot) }
        active = [:]
        failed = [:]
    }

    /// The choice stored for a slot.
    func choice(for slot: GlobalHotKey.Slot) -> GlobalHotKey.Choice {
        GlobalHotKey.Choice.parse(defaults.string(forKey: slot.setting), fallback: slot.fallback)
    }

    /// Makes what is registered match settings. Anything that changed is let
    /// go first, so two keys can swap; then each is registered, and a key the
    /// system refuses (another app has it) or that the other slot holds gets
    /// its sentence in `problems` and nothing registered.
    func apply() {
        let wanted = Dictionary(uniqueKeysWithValues: GlobalHotKey.Slot.allCases.map { ($0, choice(for: $0)) })
        for slot in GlobalHotKey.Slot.allCases where active[slot] != nil && active[slot] != wanted[slot] {
            backend.unregister(slot)
            active[slot] = nil
        }
        var next = problems
        for slot in GlobalHotKey.Slot.allCases {
            guard let choice = wanted[slot], active[slot] != choice else { continue }
            if choice == .none {
                active[slot] = GlobalHotKey.Choice.none
                failed[slot] = nil
                next[slot] = nil
                continue
            }
            if failed[slot] == choice { continue }
            // The other key holds it: asked again at every change, since it may let go.
            if let other = GlobalHotKey.Slot.allCases.first(where: { $0 != slot && active[$0] == choice }) {
                next[slot] = GlobalHotKey.problem(for: 0, choice: choice, taken: other)
                continue
            }
            guard let code = choice.keyCode else { continue }
            let status = backend.register(slot, keyCode: code, modifiers: choice.carbonModifiers)
            if status == noErr {
                active[slot] = choice
                failed[slot] = nil
                next[slot] = nil
            } else {
                failed[slot] = choice
                next[slot] = GlobalHotKey.problem(for: status, choice: choice)
            }
        }
        // A slot whose choice changed to something else has no old failure.
        for slot in GlobalHotKey.Slot.allCases where failed[slot] != nil && failed[slot] != wanted[slot] {
            failed[slot] = nil
            next[slot] = nil
        }
        if next != problems { problems = next }
    }

    /// The system says a key was pressed. A press within half a second of the
    /// last (a held key may repeat) is the same press.
    func fire(_ slot: GlobalHotKey.Slot) {
        let at = now()
        if let last = lastPress[slot], at.timeIntervalSince(last) < 0.5, at >= last { return }
        lastPress[slot] = at
        actions[slot]?()
    }
}

// MARK: Carbon

/// `RegisterEventHotKey`, one event handler on the application's target.
@MainActor
final class CarbonHotKeys: HotKeyBackend {
    static let shared = CarbonHotKeys()
    /// 'CPSD'.
    nonisolated static let signature: OSType = 0x4350_5344

    private var refs: [GlobalHotKey.Slot: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    func register(_ slot: GlobalHotKey.Slot, keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        let installed = installHandler()
        guard installed == noErr else { return installed }
        unregister(slot)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: slot.number)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[slot] = ref }
        return status
    }

    func unregister(_ slot: GlobalHotKey.Slot) {
        if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
    }

    private func installHandler() -> OSStatus {
        guard handler == nil else { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard read == noErr, id.signature == CarbonHotKeys.signature,
                  let slot = GlobalHotKey.Slot.allCases.first(where: { $0.number == id.id }) else {
                return OSStatus(eventNotHandledErr)
            }
            // The application's event target runs on the main thread.
            MainActor.assumeIsolated { GlobalKeys.shared.fire(slot) }
            return noErr
        }, 1, &spec, nil, &ref)
        if status == noErr { handler = ref }
        return status
    }
}

// MARK: Reply's key

/// What Reply's key does: opens the reply window on the session whose card is
/// on top of the panel's queue, and nothing, quietly, when no card waits on you.
@MainActor
enum ReplyKey {
    /// The session of the first needs-input card, and whether it is a plan
    /// (its window is then "Request Changes": a key never approves).
    static func topCard(in cards: [LabCard]) -> (session: SessionStatus, plan: Bool)? {
        for case .needsInput(let session) in cards { return (session, session.waitingReason == .plan) }
        return nil
    }

    @discardableResult
    static func openTopCard(cards: [LabCard] = LabModel.shared.cards,
                            show: (String, Bool) -> Void = { ReplyWindowController.shared.show($0, plan: $1) }) -> Bool {
        guard let top = topCard(in: cards) else { return false }
        show(top.session.id, top.plan)
        return true
    }
}
