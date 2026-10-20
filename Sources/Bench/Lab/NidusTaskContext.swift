// NidusTaskContext.swift — an opt-in, short-lived description of the one
// Claude Science task visible in Capsid's focused main window. Nidus reads
// this local file; no conversation text or URLs leave Capsid.
import AppKit
import Combine
import Darwin

/// The complete wire format. Keep it small and versioned so another app can
/// reject a future format rather than guessing about its meaning.
struct NidusTaskFile: Codable, Equatable, Sendable {
    let version: Int
    let pid: Int32
    let updatedAt: TimeInterval
    let projectName: String
    let taskName: String
}

enum NidusTaskSelection {
    struct Route: Equatable, Sendable {
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

/// One utility queue owns the file. Superseded requests are discarded before
/// doing work and again before committing. A clear is ordered after any write
/// already in progress, so an old write cannot recreate the file after removal.
final class NidusTaskWriter: @unchecked Sendable {
    private let file: URL
    private let queue: DispatchQueue
    private let beforeCommit: @Sendable () -> Void
    private let lock = NSLock()
    private var generation: UInt64 = 0
    // Only touched on queue.
    private var directoryReady = false

    init(file: URL, queue: DispatchQueue = DispatchQueue(label: "local.sam.bench.nidus-context", qos: .utility),
         beforeCommit: @escaping @Sendable () -> Void = {}) {
        self.file = file
        self.queue = queue
        // Tests can hold a prepared write while focus is lost.
        self.beforeCommit = beforeCommit
    }

    func publish(_ context: NidusTaskFile?) {
        lock.lock()
        generation &+= 1
        let mine = generation
        lock.unlock()
        queue.async { [self] in
            guard isCurrent(mine) else { return }
            guard let context else {
                try? FileManager.default.removeItem(at: file)
                return
            }
            write(context, generation: mine)
        }
    }

    /// The explicit quit path waits for removal; ordinary updates never wait.
    func flush() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        queue.sync {}
    }

    /// Tests await queued work without blocking their main actor.
    func settled() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }

    private func write(_ context: NidusTaskFile, generation: UInt64) {
        let directory = file.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".nidus-context-\(UUID().uuidString)")
        var moved = false
        defer { if !moved { try? FileManager.default.removeItem(at: temporary) } }
        do {
            let data = try JSONEncoder().encode(context)
            guard data.count <= 8_192 else { throw CocoaError(.fileWriteUnknown) }
            if !directoryReady {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                directoryReady = true
            }
            // This unique temporary file is already the staging copy. The
            // rename below provides atomic publication without a second copy.
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            beforeCommit()
            guard isCurrent(generation) else { return }
            guard rename(temporary.path, file.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            moved = true
        } catch {
            directoryReady = false
            // A failed current write must not leave an old title appearing fresh.
            if isCurrent(generation) { try? FileManager.default.removeItem(at: file) }
        }
    }
}

@MainActor
final class NidusTaskContext {
    static let shared = NidusTaskContext()
    static let heartbeatInterval: TimeInterval = 5

    /// Nidus rejects a copy older than 15 seconds. Only an eligible, focused
    /// route needs the five-second heartbeat; disabled sharing has no timer.
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Capsid/nidus-context.json")
    }

    struct Selection {
        let route: NidusTaskSelection.Route
        let names: (project: String, task: String)?
    }

    struct Dependencies {
        var selection: @MainActor () -> Selection?
        var lookup: @MainActor (NidusTaskSelection.Route) async -> (project: String, task: String)?
        var observe: @MainActor (@escaping @MainActor () -> Void) -> [AnyCancellable]
        var scheduleHeartbeat: @MainActor (@escaping @MainActor () -> Void) -> AnyCancellable
        var publish: @MainActor (NidusTaskFile?) -> Void
        var flush: @MainActor () -> Void
        var now: @MainActor () -> Date = { Date() }

        @MainActor static func live() -> Dependencies {
            let writer = NidusTaskWriter(file: NidusTaskContext.fileURL)
            return Dependencies(selection: {
                guard UserDefaults.standard.bool(forKey: SettingsKey.shareTaskWithNidus), NSApp.isActive,
                      let window = MainWindowController.shared.windowIfLoaded,
                      window.isVisible, NSApp.keyWindow === window else { return nil }
                let web = WebContainer.shared
                guard let route = NidusTaskSelection.route(url: web.webView.url, daemonPort: web.port) else { return nil }
                return Selection(route: route,
                                 names: NidusTaskSelection.names(url: web.webView.url, daemonPort: web.port,
                                                                sessions: LabModel.shared.sessions))
            }, lookup: { route in
                await Task.detached(priority: .utility) {
                    guard let db = resolveDatabase(), let row = try? fetchSession(db: db, id: route.frameID),
                          row.projectID == route.projectID else { return nil as (project: String, task: String)? }
                    return NidusTaskSelection.names(project: row.projectName, task: row.name)
                }.value
            }, observe: { changed in
                var observers: [AnyCancellable] = []
                let names: [Notification.Name] = [
                    NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                    NSWindow.willCloseNotification,
                    NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                    UserDefaults.didChangeNotification,
                ]
                for name in names {
                    NotificationCenter.default.publisher(for: name)
                        .receive(on: DispatchQueue.main)
                        .sink { _ in MainActor.assumeIsolated { changed() } }
                        .store(in: &observers)
                }
                WebContainer.shared.$currentFrameID
                    .receive(on: DispatchQueue.main)
                    .sink { _ in MainActor.assumeIsolated { changed() } }
                    .store(in: &observers)
                LabModel.shared.reads.$sessions
                    .receive(on: DispatchQueue.main)
                    .sink { _ in MainActor.assumeIsolated { changed() } }
                    .store(in: &observers)
                return observers
            }, scheduleHeartbeat: { beat in
                Timer.publish(every: NidusTaskContext.heartbeatInterval, tolerance: 1, on: .main, in: .common).autoconnect()
                    .sink { _ in MainActor.assumeIsolated { beat() } }
            }, publish: { writer.publish($0) }, flush: { writer.flush() })
        }
    }

    private struct Publication: Equatable {
        let route: NidusTaskSelection.Route
        let project: String
        let task: String
    }

    private let dependencies: Dependencies
    private var observers: [AnyCancellable] = []
    private var heartbeat: AnyCancellable?
    private var refreshQueued = false
    private var started = false
    private var cleared = false
    private var published: Publication?
    private var lookedUpRoute: NidusTaskSelection.Route?
    private var lookup: Task<Void, Never>?
    private var lastLookupAt = Date.distantPast
    private var fallback: Publication?

    init(dependencies: Dependencies = .live()) { self.dependencies = dependencies }

    func start() {
        guard !started else { return }
        started = true
        observers = dependencies.observe { [weak self] in self?.requestRefresh() }
        refresh()
    }

    /// A burst of focus, settings and snapshot notifications gets one read of
    /// the settled selection. Token-only updates then compare equal below.
    private func requestRefresh() {
        guard started, !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.refresh()
        }
    }

    func refresh() { refresh(heartbeat: false) }

    private func refresh(heartbeat isHeartbeat: Bool) {
        guard started else { return }
        guard let selection = dependencies.selection() else {
            heartbeat?.cancel()
            heartbeat = nil
            forget()
            clearPublication()
            return
        }
        if heartbeat == nil {
            heartbeat = dependencies.scheduleHeartbeat { [weak self] in self?.refresh(heartbeat: true) }
        }
        let route = selection.route
        if route != lookedUpRoute {
            forget()
            lookedUpRoute = route
            lastLookupAt = .distantPast
        }
        let publication = selection.names.map { Publication(route: route, project: $0.project, task: $0.task) }
            ?? fallback.flatMap { $0.route == route ? $0 : nil }
        if let publication {
            if publication != published || isHeartbeat {
                published = publication
                cleared = false
                dependencies.publish(NidusTaskFile(version: 1, pid: getpid(),
                    updatedAt: dependencies.now().timeIntervalSince1970,
                    projectName: publication.project, taskName: publication.task))
            }
        } else {
            clearPublication()
        }
        // Older sessions can be outside the 25 recent rows. A focused route's
        // heartbeat also retries this bounded lookup when needed.
        if selection.names == nil, lookup == nil,
           dependencies.now().timeIntervalSince(lastLookupAt) >= Self.heartbeatInterval {
            readOlderSession(route)
        }
    }

    /// Quit waits for removal before the process exits. A demo never starts
    /// this object, so its settings or quit cannot remove the real app's file.
    func clear() {
        guard started else { return }
        started = false
        observers.removeAll()
        heartbeat?.cancel()
        heartbeat = nil
        forget()
        clearPublication()
        dependencies.flush()
    }

    private func clearPublication() {
        published = nil
        guard !cleared else { return }
        cleared = true
        dependencies.publish(nil)
    }

    private func forget() {
        lookup?.cancel()
        lookup = nil
        lookedUpRoute = nil
        fallback = nil
    }

    private func readOlderSession(_ route: NidusTaskSelection.Route) {
        lastLookupAt = dependencies.now()
        lookup = Task { [weak self] in
            guard let self else { return }
            let names = await dependencies.lookup(route)
            guard !Task.isCancelled, started, lookedUpRoute == route else { return }
            lookup = nil
            fallback = names.map { Publication(route: route, project: $0.project, task: $0.task) }
            refresh()
        }
    }
}
