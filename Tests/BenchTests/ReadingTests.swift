// ReadingTests.swift — the status check, the database's text handling and the
// session-link port, against made-up inputs only.
import Foundation
import Testing
@testable import Bench

struct StatusParsingTests {
    @Test func runningGivesItsPort() throws {
        let json = #"{"running": true, "port": 9100, "version": "0.1", "daemon": {"active_frames": 2}}"#
        let status = try parseCLIStatus(Data(json.utf8), exitStatus: 0)
        #expect(status.port == 9100)
        #expect(status.activeFrames == 2)
    }

    @Test func onlyAnExplicitFalseMeansStopped() {
        #expect(throws: ScienceError.daemonNotRunning) {
            try parseCLIStatus(Data(#"{"running": false}"#.utf8), exitStatus: 0)
        }
    }

    @Test(arguments: [#"{"error": "something went wrong"}"#, #"{"running": "yes"}"#, "not json"])
    func anythingElseIsAFailedCheck(_ reply: String) {
        #expect {
            try parseCLIStatus(Data(reply.utf8), exitStatus: 1)
        } throws: { error in
            if case ScienceError.cliFailed = error { return true }
            return false
        }
    }
}

struct DatabaseTextTests {
    /// A real sqlite3 database, made here, with a name across two lines.
    @Test func aLineBreakInANameKeepsItsRow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("test.db")
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        make.arguments = [db.path, """
            CREATE TABLE projects(id TEXT, name TEXT);
            INSERT INTO projects VALUES ('p1', 'First line' || char(10) || 'second line'), ('p2', 'Plain');
            """]
        try make.run()
        make.waitUntilExit()
        let names = try fetchProjectNames(db: db)
        #expect(names == ["p1": "First line second line", "p2": "Plain"])
    }
}

@MainActor
struct SessionLinkTests {
    @Test func aLinkBuiltBeforeThePortWasKnownMovesToIt() throws {
        let early = try #require(URL(string: "http://localhost:8765/projects/p/frames/f"))
        #expect(WebContainer.moving(early, toPort: 9100).absoluteString == "http://localhost:9100/projects/p/frames/f")
        let elsewhere = try #require(URL(string: "https://example.com/page"))
        #expect(WebContainer.moving(elsewhere, toPort: 9100) == elsewhere)
    }
}
