// WorkspaceVisits.swift — the last conversation in each project (DESIGN.md,
// Project Workspaces → Remembered by itself). As the main web view moves from
// session to session, the session it shows is remembered for its project, two
// opaque ids and nothing else, for the 50 projects shown most recently. There
// is no Save: visiting is what updates it. It rides on the same address watch
// as reopen-where-you-were (Web/LastSession.swift), over an injected
// `UserDefaults` so the tests use a suite of their own, and like it a demo
// neither writes nor reads it. Unlike it, leaving a session for the home page
// forgets nothing: the project's last conversation is still the one it was.
import Foundation

@MainActor
struct WorkspaceVisits {
    typealias Route = LastSession.Route

    /// Projects remembered at most, the most recently shown first.
    static let limit = 50
    /// `["<project id>/<session id>", …]`, newest first. Not registered: absent means none.
    static let key = "workspaceLastSessions"

    private let defaults: UserDefaults
    private let isDemo: Bool

    init(defaults: UserDefaults = .standard, isDemo: Bool = Demo.mode != nil) {
        self.defaults = defaults
        self.isDemo = isDemo
    }

    /// Each remembered project's last session, newest first: entries of the database's shape only, one per project.
    var routes: [Route] {
        guard !isDemo, let stored = defaults.stringArray(forKey: Self.key) else { return [] }
        var seen: Set<String> = []
        let routes = stored.compactMap(Self.route(from:)).filter { seen.insert($0.projectID).inserted }
        return Array(routes.prefix(Self.limit))
    }

    /// The session last shown in `projectID`, if one was.
    func lastSession(in projectID: String) -> String? {
        routes.first { $0.projectID == projectID }?.frameID
    }

    /// Where `projectID` comes in the remembered order (0 the most recent), for "most recent first".
    func recency(of projectID: String) -> Int? {
        routes.firstIndex { $0.projectID == projectID }
    }

    /// The main web view's address changed. A session's page becomes its project's last conversation and moves its
    /// project to the front; any other address changes nothing. Only a change is written.
    func note(url: URL?, daemonPort: Int?) {
        guard !isDemo, let route = NidusTaskSelection.route(url: url, daemonPort: daemonPort) else { return }
        let kept = [route] + routes.filter { $0.projectID != route.projectID }
        let stored = kept.prefix(Self.limit).map { "\($0.projectID)/\($0.frameID)" }
        guard defaults.stringArray(forKey: Self.key) != Array(stored) else { return }
        defaults.set(Array(stored), forKey: Self.key)
    }

    private static func route(from text: String) -> Route? {
        let ids = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard ids.count == 2, BrowseSQL.isProjectID(ids[0]), PlanCheck.isFrameID(ids[1]) else { return nil }
        return Route(projectID: ids[0], frameID: ids[1])
    }

    /// The project the main window shows, on any of its pages (`/projects/<id>`, a session in it, its files), on
    /// the daemon's own address. Nil for the home page and anything else.
    nonisolated static func project(url: URL?, daemonPort: Int?) -> String? {
        guard let url, WebRoute.classify(url, daemonPort: daemonPort) == .daemon else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "projects", BrowseSQL.isProjectID(parts[2]) else { return nil }
        return parts[2]
    }
}
