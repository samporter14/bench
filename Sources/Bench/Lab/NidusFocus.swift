// NidusFocus.swift — whether a Nidus focus session is on (DESIGN.md, Nidus).
// Nidus, a Solanum app, writes `focus.json` in its Application Support folder
// (whether a session runs and until when, never its goal) and posts
// `local.sam.nidus.focus` on this Mac when that changes. Bench holds
// "Finished" cards while it is on; questions and errors still come.
import AppKit
import Combine

@MainActor
final class NidusFocus: NSObject, ObservableObject {
    static let shared = NidusFocus()
    nonisolated static let bundleID = "local.sam.nidus"
    nonisolated static let changed = Notification.Name("local.sam.nidus.focus")

    /// A focus session is on, by the file and with Nidus running.
    @Published private(set) var focusing = false
    private var observers: [NSObjectProtocol] = []
    private var expiry: Task<Void, Never>?

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nidus/focus.json")
    }

    /// Focusing, and the setting says to hold finishes for it.
    var holding: Bool {
        focusing && UserDefaults.standard.bool(forKey: SettingsKey.holdDuringFocus)
    }

    func start() {
        guard observers.isEmpty else { return }
        // Delivered at once, even while Bench is in the background, which is
        // when it matters.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(nidusChanged), name: Self.changed, object: nil,
            suspensionBehavior: .deliverImmediately)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                MainActor.assumeIsolated { self?.check() }
            })
        }
        check()
    }

    @objc private func nidusChanged() { check() }

    private func check() {
        let data = try? Data(contentsOf: Self.file)
        let file = data.flatMap { try? JSONDecoder().decode(NoticeRules.FocusFile.self, from: $0) }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        let now = NoticeRules.isFocusing(file, nidusRunning: running, now: Date())
        expiry?.cancel()
        // A timed session ends on its own: look again then, in case Nidus's
        // own word is late.
        if now, let until = file?.until {
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, until - Date().timeIntervalSince1970 + 1)))
                guard !Task.isCancelled else { return }
                self?.check()
            }
        }
        if now != focusing {
            focusing = now
            if !now { LabModel.shared.focusEnded() }
        }
    }
}
