// NidusTaskContext.swift — an opt-in, short-lived description of the one
// Claude Science task visible in Capsid's focused main window. Nidus reads
// this local file; no conversation text or URLs leave Capsid.
import AppKit
import Combine
import Darwin

/// The complete wire format. Keep it small and versioned so another app can
/// reject a future format rather than guessing about its meaning.
struct NidusTaskFile: Codable, Equatable {
    let version: Int
    let pid: Int32
    let updatedAt: TimeInterval
    let projectName: String
    let taskName: String
}

enum NidusTaskSelection {
    struct Route: Equatable {
        let projectID: String
        let frameID: String
    }

    /// Only an exact task route on Capsid's daemon, with a matching database
    /// row, is eligible. In particular, a project overview, Browser window,
    /// or unrelated web page never supplies a name.
    static func route(url: URL?, daemonPort: Int?) -> Route? {
        guard let url, WebRoute.classify(url, daemonPort: daemonPort) == .daemon else { return nil }
        let parts = url.pathComponents
        guard parts.count == 5, parts[1] == "projects", parts[3] == "frames",
              BrowseSQL.isProjectID(parts[2]), PlanCheck.isFrameID(parts[4]) else { return nil }
        return Route(projectID: parts[2], frameID: parts[4])
    }

    static func names(url: URL?, daemonPort: Int?, sessions: [SessionStatus]) -> (project: String, task: String)? {
        guard let route = route(url: url, daemonPort: daemonPort),
              let session = sessions.first(where: { $0.id == route.frameID && $0.projectID == route.projectID })
        else { return nil }
        return names(project: session.projectName, task: session.title)
    }

    static func names(project rawProject: String, task rawTask: String) -> (project: String, task: String)? {
        let project = clean(rawProject), task = clean(rawTask)
        guard !project.isEmpty, !task.isEmpty else { return nil }
        return (project, task)
    }

    /// Titles are user-authored. Keep only a bounded, printable title rather
    /// than allowing a malformed row to create an oversized file or line.
    private static func clean(_ value: String) -> String {
        String(value.filter { character in
            !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class NidusTaskContext {
    static let shared = NidusTaskContext()

    /// Nidus reads this path. Its 15-second freshness limit protects against
    /// an app crash or an unexpected loss of focus notifications.
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Capsid/nidus-context.json")
    }

    private var observers: [AnyCancellable] = []
    private var started = false
    private var lookedUpRoute: NidusTaskSelection.Route?
    private var lookup: Task<Void, Never>?
    private var lastLookupAt = Date.distantPast
    private var fallback: (route: NidusTaskSelection.Route, project: String, task: String)?

    func start() {
        guard !started else { return }
        started = true

        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            UserDefaults.didChangeNotification,
        ]
        // Let AppKit settle on its new key window before deciding whether the
        // main one still owns focus.
        for name in names {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
                .store(in: &observers)
        }
        WebContainer.shared.$currentFrameID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &observers)
        LabModel.shared.reads.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &observers)
        Timer.publish(every: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &observers)
        refresh()
    }

    func refresh() {
        guard started else { return }
        guard UserDefaults.standard.bool(forKey: SettingsKey.shareTaskWithNidus),
              NSApp.isActive,
              let window = MainWindowController.shared.windowIfLoaded,
              window.isVisible, NSApp.keyWindow === window
        else { forget(); clear(); return }

        let web = WebContainer.shared
        guard let route = NidusTaskSelection.route(url: web.webView.url, daemonPort: web.port)
        else { forget(); clear(); return }
        if route != lookedUpRoute {
            lookup?.cancel()
            lookup = nil
            lookedUpRoute = route
            lastLookupAt = .distantPast
            fallback = nil
        }
        let recentNames = NidusTaskSelection.names(url: web.webView.url, daemonPort: web.port,
                                                   sessions: LabModel.shared.sessions)
        let names = recentNames
            ?? fallback.flatMap { $0.route == route ? (project: $0.project, task: $0.task) : nil }
        if let names {
            write(NidusTaskFile(version: 1, pid: getpid(), updatedAt: Date().timeIntervalSince1970,
                                projectName: names.project, taskName: names.task))
        } else {
            clear()
        }
        // An older selected session can be beyond LabModel's 25 recent rows.
        // Query only its exact frame ID off the main thread, at most once per
        // five seconds, and recheck focus before publishing the answer.
        if recentNames == nil, lookup == nil, Date().timeIntervalSince(lastLookupAt) >= 5 {
            readOlderSession(route)
        }
    }

    /// Only the copy that publishes may remove the file. A demo never starts
    /// this, but shares the path, so its Settings toggle or quit must not
    /// delete the running Capsid's file.
    func clear() {
        guard started else { return }
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func forget() {
        lookup?.cancel()
        lookup = nil
        lookedUpRoute = nil
        fallback = nil
    }

    private func readOlderSession(_ route: NidusTaskSelection.Route) {
        lastLookupAt = Date()
        lookup = Task { [weak self] in
            let names = await Task.detached(priority: .utility) {
                guard let db = resolveDatabase(),
                      let row = try? fetchSession(db: db, id: route.frameID),
                      row.projectID == route.projectID else { return nil as (String, String)? }
                return (row.projectName, row.name)
            }.value
            guard let self, !Task.isCancelled, lookedUpRoute == route else { return }
            lookup = nil
            fallback = names.flatMap { raw in
                NidusTaskSelection.names(project: raw.0, task: raw.1).map {
                    (route: route, project: $0.project, task: $0.task)
                }
            }
            refresh()
        }
    }

    private func write(_ context: NidusTaskFile) {
        let file = Self.fileURL
        let directory = file.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".nidus-context-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(context)
            guard data.count <= 8_192 else { clear(); return }
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            // POSIX rename replaces the old file in one step, so Nidus never
            // sees a partially written JSON document.
            guard rename(temporary.path, file.path) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            // A failed update must not keep an older title appearing current.
            clear()
        }
    }
}
