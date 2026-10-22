// LastSession.swift — reopen where you were (DESIGN.md, Reopen where you
// were). The main window keeps the session it is showing, as the two opaque
// ids in its address, and the next launch opens that session instead of
// Claude Science's home page when the database still knows it. The rules are
// here, over an injected `UserDefaults` so tests use a suite of their own;
// WebContainer does the wiring.
import Foundation

@MainActor
struct LastSession {
    /// A session's address: project id and session id, and nothing else.
    typealias Route = NidusTaskSelection.Route

    private let defaults: UserDefaults
    /// A demo shows made-up data with no daemon behind it, and shares the
    /// real app's defaults: it must neither change what is remembered nor
    /// use it.
    private let isDemo: Bool

    init(defaults: UserDefaults = .standard, isDemo: Bool = Demo.mode != nil) {
        self.defaults = defaults
        self.isDemo = isDemo
    }

    // MARK: Remembering

    /// The route kept, when what is stored is one (`<project id>/<session id>`,
    /// each of the shape the database's ids have).
    var route: Route? {
        guard !isDemo, let text = defaults.string(forKey: SettingsKey.lastSession) else { return nil }
        let ids = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard ids.count == 2, BrowseSQL.isProjectID(ids[0]), PlanCheck.isFrameID(ids[1]) else { return nil }
        return Route(projectID: ids[0], frameID: ids[1])
    }

    /// The main web view's address changed. A session's page is kept, and
    /// any other page of Claude Science (home, a project's overview) forgets
    /// it: the user left the session, so a launch should not bring them back
    /// into it. Nothing else counts: a blank page, a download or a link that
    /// went to another window never reaches the daemon's page, and says
    /// nothing about where the user is.
    func note(url: URL?, daemonPort: Int?) {
        guard !isDemo, WebRoute.classify(url, daemonPort: daemonPort) == .daemon else { return }
        // The daemon's own sign-in step (`/api/me`) is where the user is not.
        guard !SignInPlan.isSignInStep(url) else { return }
        if let route = NidusTaskSelection.route(url: url, daemonPort: daemonPort) {
            keep("\(route.projectID)/\(route.frameID)")
        } else {
            keep(nil)
        }
    }

    /// Writes only a change: every write is a `UserDefaults.didChangeNotification`
    /// that other watchers (the Nidus task file) answer.
    private func keep(_ text: String?) {
        guard defaults.string(forKey: SettingsKey.lastSession) != text else { return }
        if let text {
            defaults.set(text, forKey: SettingsKey.lastSession)
        } else {
            defaults.removeObject(forKey: SettingsKey.lastSession)
        }
    }

    // MARK: Reopening

    /// The address to open at launch in place of the home page: the session
    /// that was showing, on the daemon's host and port, when `isKnown` says the
    /// database still has it. Nil (the home page) for none kept, one the
    /// database doesn't know or can't be asked about, and in a demo.
    func reopenURL(port: Int, host: String = DaemonHost.usual, isKnown: (Route) async -> Bool) async -> URL? {
        guard let route, await isKnown(route) else { return nil }
        return URL(string: "http://\(host):\(port)/projects/\(route.projectID)/frames/\(route.frameID)")
    }

    /// The live `isKnown`: the database has `route` as a root session of that
    /// project, as the session list counts sessions (not hidden, not a
    /// sub-agent). Read off the main actor and given two seconds: a launch
    /// does not wait on a locked database, and falls back to the home page.
    nonisolated static func databaseKnows(_ route: Route) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            guard let db = resolveDatabase() else { return false }
            return isKnown(route, in: db)
        }.value
    }

    /// `databaseKnows` against one database.
    nonisolated static func isKnown(_ route: Route, in db: URL) -> Bool {
        (try? fetchSession(db: db, id: route.frameID, timeout: 2))?.projectID == route.projectID
    }

    /// Where the launch loads. A link that arrived (`bench://…`, from the
    /// droplet or a click) is what the user asked for and wins, and when it
    /// isn't a page of Claude Science's, the home page as it always was: a
    /// link never mixes with a remembered session. With no link, the
    /// remembered session, else the home page.
    nonisolated static func launchDestination(link: URL?, remembered: URL?, root: URL, port: Int) -> URL {
        if let link {
            return WebRoute.classify(link, daemonPort: port) == .daemon ? link : root
        }
        return remembered ?? root
    }
}
