// WorkspaceVisitsTests.swift — the last conversation of each project, kept by
// visiting: two opaque ids per project and nothing else, the most recent
// first, 50 projects at most, written only on a change, never in a demo, and
// untouched by pages that aren't a session's. Also which project the main
// window shows, for History → Project Workspace. A throwaway defaults suite each.
import Foundation
import Testing
@testable import Bench

@MainActor
struct WorkspaceVisitsTests {
    private static let port = 8765

    private func page(_ path: String, port: Int = WorkspaceVisitsTests.port) -> URL {
        URL(string: "http://localhost:\(port)\(path)")!
    }

    private func session(_ project: String, _ n: Int) -> URL {
        page("/projects/\(project)/frames/\(madeUpID(n))")
    }

    private func visits(demo: Bool = false, _ body: @MainActor (WorkspaceVisits, UserDefaults) throws -> Void) rethrows {
        let scratch = ScratchDefaults.make(prefix: "WorkspaceVisitsTests")
        defer { scratch.discard() }
        try body(WorkspaceVisits(defaults: scratch.defaults, isDemo: demo), scratch.defaults)
    }

    @Test func visitingASessionMakesItItsProjectsLastConversation() {
        visits { visits, defaults in
            visits.note(url: session("proj-alpha", 1), daemonPort: Self.port)
            visits.note(url: session("proj-beta", 2), daemonPort: Self.port)
            visits.note(url: session("proj-alpha", 3), daemonPort: Self.port)
            #expect(visits.lastSession(in: "proj-alpha") == madeUpID(3))
            #expect(visits.lastSession(in: "proj-beta") == madeUpID(2))
            #expect(visits.recency(of: "proj-alpha") == 0 && visits.recency(of: "proj-beta") == 1)
            // Two ids each, and nothing else: no title, no address.
            #expect(defaults.stringArray(forKey: WorkspaceVisits.key) == ["proj-alpha/\(madeUpID(3))", "proj-beta/\(madeUpID(2))"])
        }
    }

    @Test(arguments: ["/", "/projects", "/projects/proj-alpha", "/settings", "/api/me?nonce=x"])
    func otherPagesOfClaudeScienceForgetNothing(path: String) {
        visits { visits, _ in
            visits.note(url: session("proj-alpha", 1), daemonPort: Self.port)
            visits.note(url: page(path), daemonPort: Self.port)
            #expect(visits.lastSession(in: "proj-alpha") == madeUpID(1))
        }
    }

    @Test func pagesThatArentTheDaemonsSayNothing() {
        visits { visits, defaults in
            visits.note(url: URL(string: "https://example.com/projects/proj-alpha/frames/\(madeUpID(1))"), daemonPort: Self.port)
            visits.note(url: session("proj-alpha", 1), daemonPort: 9999)
            visits.note(url: nil, daemonPort: Self.port)
            #expect(defaults.object(forKey: WorkspaceVisits.key) == nil)
        }
    }

    @Test func fiftyProjectsAreKeptTheMostRecentFirst() {
        visits { visits, _ in
            for n in 0..<60 { visits.note(url: session("proj-\(n)", n), daemonPort: Self.port) }
            #expect(visits.routes.count == WorkspaceVisits.limit)
            #expect(visits.routes.first?.projectID == "proj-59" && visits.routes.last?.projectID == "proj-10")
            #expect(visits.lastSession(in: "proj-9") == nil)
        }
    }

    @Test func onlyAChangeIsWritten() {
        visits { visits, defaults in
            visits.note(url: session("proj-alpha", 1), daemonPort: Self.port)
            let changes = TrashedURLs()
            let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults,
                                                                  queue: nil) { _ in changes.add(URL(fileURLWithPath: "/")) }
            defer { NotificationCenter.default.removeObserver(observer) }
            visits.note(url: page("/projects/proj-alpha/frames/\(madeUpID(1))?nonce=abc"), daemonPort: Self.port)
            visits.note(url: session("proj-alpha", 1), daemonPort: Self.port)
            #expect(changes.urls.isEmpty)
            visits.note(url: session("proj-alpha", 2), daemonPort: Self.port)
            #expect(changes.urls.count == 1)
        }
    }

    @Test func storedEntriesOutOfShapeAreSkipped() {
        visits { visits, defaults in
            defaults.set(["proj-alpha/\(madeUpID(1))", "../x/\(madeUpID(2))", "proj-beta/short", "proj-alpha/\(madeUpID(3))"],
                         forKey: WorkspaceVisits.key)
            #expect(visits.routes.map(\.projectID) == ["proj-alpha"])
            #expect(visits.lastSession(in: "proj-alpha") == madeUpID(1))
        }
    }

    @Test func aDemoNeitherWritesNorReads() {
        visits(demo: true) { visits, defaults in
            defaults.set(["proj-alpha/\(madeUpID(1))"], forKey: WorkspaceVisits.key)
            #expect(visits.lastSession(in: "proj-alpha") == nil)
            visits.note(url: session("proj-beta", 2), daemonPort: Self.port)
            #expect(defaults.stringArray(forKey: WorkspaceVisits.key) == ["proj-alpha/\(madeUpID(1))"])
        }
    }

    @Test func theProjectOnShowIsReadFromAnyOfItsPages() {
        #expect(WorkspaceVisits.project(url: session("proj-alpha", 1), daemonPort: Self.port) == "proj-alpha")
        #expect(WorkspaceVisits.project(url: page("/projects/proj-alpha"), daemonPort: Self.port) == "proj-alpha")
        #expect(WorkspaceVisits.project(url: page("/projects/proj-alpha/files"), daemonPort: Self.port) == "proj-alpha")
        #expect(WorkspaceVisits.project(url: page("/"), daemonPort: Self.port) == nil)
        #expect(WorkspaceVisits.project(url: page("/projects/..%2Fx"), daemonPort: Self.port) == nil)
        #expect(WorkspaceVisits.project(url: URL(string: "https://example.com/projects/proj-alpha"), daemonPort: Self.port) == nil)
    }
}
