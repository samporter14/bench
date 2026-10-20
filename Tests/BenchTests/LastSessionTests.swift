// LastSessionTests.swift — reopen where you were: the session the main window
// shows is remembered as two opaque ids, forgotten when the user leaves it,
// reopened at launch only while the database still knows it, never in a demo,
// and never over a link that came with the launch. Each test uses a
// throwaway defaults suite, never the real settings, and made-up databases.
import Foundation
import Testing
@testable import Bench

@MainActor
struct LastSessionTests {
    private static let port = 8765
    private static let frame = madeUpID(7)

    private func address(_ path: String, port: Int = LastSessionTests.port, host: String = "localhost") -> URL {
        URL(string: "http://\(host):\(port)\(path)")!
    }

    private func sessionPage(project: String = "proj_a", frame: String = LastSessionTests.frame) -> URL {
        address("/projects/\(project)/frames/\(frame)")
    }

    /// A suite of its own, and the memory over it. `demo` makes a demo's.
    private func memory(demo: Bool = false, _ body: @MainActor (LastSession, UserDefaults) async throws -> Void) async throws {
        let name = "LastSessionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(LastSession(defaults: defaults, isDemo: demo), defaults)
    }

    // MARK: Remembering

    @Test func aSessionPageIsRememberedByItsTwoIds() async throws {
        try await memory { last, defaults in
            #expect(last.route == nil)
            last.note(url: sessionPage(), daemonPort: Self.port)
            #expect(last.route == .init(projectID: "proj_a", frameID: Self.frame))
            // What is stored is the two ids and nothing else: no name, no address.
            #expect(defaults.string(forKey: SettingsKey.lastSession) == "proj_a/\(Self.frame)")
        }
    }

    @Test func movingToAnotherSessionRemembersThatOne() async throws {
        try await memory { last, _ in
            last.note(url: sessionPage(project: "proj_a", frame: madeUpID(1)), daemonPort: Self.port)
            last.note(url: sessionPage(project: "proj_b", frame: madeUpID(2)), daemonPort: Self.port)
            #expect(last.route == .init(projectID: "proj_b", frameID: madeUpID(2)))
        }
    }

    @Test func aSignInCodeOnTheAddressDoesNotChangeTheSession() async throws {
        try await memory { last, defaults in
            last.note(url: address("/projects/proj_a/frames/\(Self.frame)?nonce=abc123"), daemonPort: Self.port)
            #expect(defaults.string(forKey: SettingsKey.lastSession) == "proj_a/\(Self.frame)")
        }
    }

    @Test(arguments: ["/", "/projects", "/projects/proj_a", "/projects/proj_a/frames", "/settings"])
    func leavingTheSessionForAnotherPageOfClaudeScienceForgetsIt(path: String) async throws {
        try await memory { last, defaults in
            last.note(url: sessionPage(), daemonPort: Self.port)
            #expect(last.route != nil)
            last.note(url: address(path), daemonPort: Self.port)
            #expect(last.route == nil)
            #expect(defaults.object(forKey: SettingsKey.lastSession) == nil)
        }
    }

    @Test func anAddressOnThe127LoopbackIsTheDaemonsToo() async throws {
        try await memory { last, _ in
            last.note(url: address("/projects/proj_a/frames/\(Self.frame)", host: "127.0.0.1"), daemonPort: Self.port)
            #expect(last.route != nil)
        }
    }

    @Test func nothingThatIsNotTheDaemonsPageChangesIt() async throws {
        try await memory { last, _ in
            last.note(url: sessionPage(), daemonPort: Self.port)
            let kept = last.route
            #expect(kept != nil)
            let others: [URL?] = [
                nil,
                URL(string: "about:blank"),
                // A preview, on another port of the same machine.
                address("/", port: Self.port + 1),
                URL(string: "https://example.com/projects/proj_x/frames/\(madeUpID(9))"),
                URL(string: "mailto:someone@example.com"),
                URL(string: "blob:http://localhost:8765/00000000"),
            ]
            for other in others { last.note(url: other, daemonPort: Self.port) }
            #expect(last.route == kept)
            // Before the daemon's port is known nothing is the daemon's.
            last.note(url: address("/"), daemonPort: nil)
            #expect(last.route == kept)
        }
    }

    @Test func aStoredValueThatIsNotTwoIdsIsNotARoute() async throws {
        try await memory { last, defaults in
            let bad = ["", "proj_a", "proj_a/", "/\(Self.frame)", "proj_a/\(Self.frame)/more", "proj a/\(Self.frame)",
                       "proj_a/not-a-frame", "../x/\(Self.frame)", "proj_a/\(madeUpID(0xabc).uppercased())",
                       "http://localhost:8765/projects/proj_a/frames/\(Self.frame)"]
            for text in bad {
                defaults.set(text, forKey: SettingsKey.lastSession)
                #expect(last.route == nil, "\(text)")
            }
            defaults.set(5, forKey: SettingsKey.lastSession)
            #expect(last.route == nil)
        }
    }

    // MARK: In a demo

    @Test func aDemoRemembersNothingAndUsesNothing() async throws {
        try await memory(demo: true) { demo, defaults in
            demo.note(url: sessionPage(), daemonPort: Self.port)
            #expect(defaults.object(forKey: SettingsKey.lastSession) == nil)
            // What the real app remembered is not the demo's to use or to forget.
            defaults.set("proj_a/\(Self.frame)", forKey: SettingsKey.lastSession)
            #expect(demo.route == nil)
            demo.note(url: address("/"), daemonPort: Self.port)
            #expect(defaults.string(forKey: SettingsKey.lastSession) == "proj_a/\(Self.frame)")
            var asked = false
            let url = await demo.reopenURL(port: Self.port, isKnown: { _ in asked = true; return true })
            #expect(url == nil && !asked)
        }
    }

    // MARK: Reopening

    @Test func aRememberedSessionTheDatabaseKnowsReopensOnTheDaemonsPort() async throws {
        try await memory { last, _ in
            last.note(url: sessionPage(), daemonPort: Self.port)
            var asked: [LastSession.Route] = []
            let url = await last.reopenURL(port: 9100, isKnown: { asked.append($0); return true })
            #expect(url?.absoluteString == "http://localhost:9100/projects/proj_a/frames/\(Self.frame)")
            #expect(asked == [.init(projectID: "proj_a", frameID: Self.frame)])
        }
    }

    @Test func aSessionTheDatabaseDoesNotKnowIsNotReopened() async throws {
        try await memory { last, _ in
            last.note(url: sessionPage(), daemonPort: Self.port)
            #expect(await last.reopenURL(port: Self.port, isKnown: { _ in false }) == nil)
        }
    }

    @Test func nothingRememberedAsksNoOneAndReopensNothing() async throws {
        try await memory { last, _ in
            var asked = false
            let url = await last.reopenURL(port: Self.port, isKnown: { _ in asked = true; return true })
            #expect(url == nil && !asked)
        }
    }

    // MARK: Does the database know it

    @Test func theDatabaseKnowsARootSessionOfThatProject() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Made-up A")
        try db.frame(madeUpID(1), project: "proj_a")
        try db.frame(madeUpID(2), project: "proj_a", parent: madeUpID(1))
        try db.frame(madeUpID(3), project: "proj_a", hidden: true)
        try db.frame(madeUpID(4), project: "proj_a", type: "uploads")
        try db.frame(madeUpID(5), project: "proj_a", agent: "CONCIERGE")
        func known(_ project: String, _ frame: String) -> Bool {
            LastSession.isKnown(.init(projectID: project, frameID: frame), in: db.url)
        }
        #expect(known("proj_a", madeUpID(1)))
        // A different project's address for the same session is not that session.
        #expect(!known("proj_b", madeUpID(1)))
        // Gone, a sub-agent, hidden, an upload frame, a concierge: none is a session.
        #expect(!known("proj_a", madeUpID(99)))
        for n in 2...5 { #expect(!known("proj_a", madeUpID(n)), "\(n)") }
    }

    @Test func aDatabaseThatCantBeReadKnowsNothing() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).db")
        #expect(!LastSession.isKnown(.init(projectID: "proj_a", frameID: Self.frame), in: missing))
    }

    @Test func fromTheMemoryThroughTheDatabaseToAnAddress() async throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        try db.project("proj_a", "Made-up A")
        try db.frame(Self.frame, project: "proj_a")
        try await memory { last, _ in
            last.note(url: sessionPage(), daemonPort: Self.port)
            let url = await last.reopenURL(port: Self.port, isKnown: { LastSession.isKnown($0, in: db.url) })
            #expect(url == sessionPage())
            // The session goes away (the database is another org's, or it was deleted).
            let other = try MadeUpDatabase()
            defer { other.remove() }
            #expect(await last.reopenURL(port: Self.port, isKnown: { LastSession.isKnown($0, in: other.url) }) == nil)
        }
    }

    // MARK: Where the launch goes

    private let root = URL(string: "http://localhost:8765/")!

    @Test func withNoLinkTheRememberedSessionIsWhereTheLaunchGoes() {
        let session = sessionPage()
        #expect(LastSession.launchDestination(link: nil, remembered: session, root: root, port: Self.port) == session)
        #expect(LastSession.launchDestination(link: nil, remembered: nil, root: root, port: Self.port) == root)
    }

    @Test func aLinkThatCameWithTheLaunchWinsOverTheRememberedSession() {
        let remembered = sessionPage(project: "proj_a", frame: madeUpID(1))
        let linked = sessionPage(project: "proj_b", frame: madeUpID(2))
        #expect(LastSession.launchDestination(link: linked, remembered: remembered, root: root, port: Self.port) == linked)
        // A link to another page of Claude Science is the user's ask too.
        let overview = address("/projects/proj_b")
        #expect(LastSession.launchDestination(link: overview, remembered: remembered, root: root, port: Self.port) == overview)
    }

    @Test func aLinkToSomewhereElseOpensTheHomePageAsItAlwaysDidNotTheRememberedSession() {
        let remembered = sessionPage()
        let elsewhere = URL(string: "https://example.com/page")!
        #expect(LastSession.launchDestination(link: elsewhere, remembered: remembered, root: root, port: Self.port) == root)
    }
}
