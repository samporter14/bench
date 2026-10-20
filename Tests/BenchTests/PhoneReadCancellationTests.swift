// PhoneReadCancellationTests.swift — a phone that gives up on a read (an aborted fetch, a screen left, a page put
// away) closes its connection, and the server drops the read: the task answering it is cancelled, and an
// artifact read also asks the page to abort its fetch. A write is never dropped. The sockets are real, on
// 127.0.0.1 only and outside Bench's own ports (47391…47399), with made-up devices in memory and made-up
// backends that wait until a test lets them go. Nothing reaches Tailscale, a web view or a daemon.
import Foundation
import Testing
@testable import Bench

// MARK: A read that waits

/// Stands in for a read (or a write) that takes a while: `hold()` returns when `release()` is called or when
/// the task awaiting it is cancelled, and counts which.
@MainActor
private final class Probe {
    private(set) var started = 0
    private(set) var cancelled = 0
    private(set) var finished = 0
    private var gates: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        started += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { gates.append($0) }
        } onCancel: {
            Task { @MainActor in
                self.cancelled += 1
                self.release()
            }
        }
        finished += 1
    }

    func release() {
        let waiting = gates
        gates = []
        for gate in waiting { gate.resume() }
    }
}

// MARK: The server

@Suite(.serialized) @MainActor
struct PhoneHangUpTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"
    private static let session = "00000000-0000-4000-8000-0000000000a1"

    private enum Goodbye: CaseIterable {
        /// A FIN: the connection shut down.
        case shutdown
        /// A RST: the connection torn down.
        case reset
    }

    private func serve(_ configure: (inout RemoteBackend) -> Void) async throws -> (RemoteServer, UInt16, String) {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        guard case .paired(let token, _) = auth.pair(code: "000000", name: "Phone") else {
            Issue.record("not paired")
            throw CancellationError()
        }
        var backend = RemoteBackend(state: { Data("{}".utf8) }, session: { _ in nil }, open: { _ in false }, version: "test")
        configure(&backend)
        let server = RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: auth, backend: backend)
        let port = try await server.start(candidates: Array(47391...47399))
        return (server, port, token)
    }

    private func get(_ path: String, token: String) -> String {
        "GET \(path) HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\nCookie: bench_device=\(token)\r\n\r\n"
    }

    private func post(_ path: String, token: String, body: String) -> String {
        "POST \(path) HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\n"
            + "Content-Type: application/json\r\nOrigin: https://\(Self.host):8443\r\nX-Bench: 1\r\n"
            + "Cookie: bench_device=\(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    }

    private func goodbye(_ how: Goodbye, _ connection: LoopbackConnection) {
        switch how {
        case .shutdown: connection.hangUp()
        case .reset: connection.reset()
        }
    }

    @Test(arguments: Goodbye.allCases)
    private func aFileReadIsCancelledWhenThePhoneHangsUp(how: Goodbye) async throws {
        let probe = Probe()
        let (server, port, token) = try await serve { $0.files = { _, _, _ in await probe.hold(); return RemoteResponse.error(503) } }
        defer { server.stop() }
        let connection = try #require(LoopbackConnection(port: port))
        connection.send(get("/api/files/ver_1/thumb?w=120", token: token))
        await eventually { probe.started == 1 }
        #expect(probe.cancelled == 0, "still waiting for the page: nothing has been dropped yet")
        goodbye(how, connection)
        await eventually { probe.cancelled == 1 }
        await eventually { probe.finished == 1 }
    }

    @Test func everyKindOfReadIsCancelledNotJustFiles() async throws {
        let probe = Probe()
        let (server, port, token) = try await serve {
            $0.files = { _, _, _ in await probe.hold(); return RemoteResponse.error(503) }
            $0.session = { _ in await probe.hold(); return nil }
            $0.live = { _ in await probe.hold(); return nil }
            $0.browse = { _, _, _, _ in await probe.hold(); return .notFound }
        }
        defer { server.stop() }
        let paths = ["/api/sessions/\(Self.session)/artifacts", "/api/files/ver_1/text", "/api/files/ver_1/download",
                     "/api/sessions/\(Self.session)", "/api/sessions/\(Self.session)/live", "/api/projects",
                     "/api/projects/proj_1/sessions", "/api/sessions/\(Self.session)/history",
                     "/api/sessions/\(Self.session)/turn/3"]
        var connections: [LoopbackConnection] = []
        // Two file transfers at a time per device: one path at a time, so none is turned away as busy.
        for (n, path) in paths.enumerated() {
            let connection = try #require(LoopbackConnection(port: port))
            connection.send(get(path, token: token))
            await eventually { probe.started == n + 1 }
            connection.hangUp()
            await eventually { probe.cancelled == n + 1 }
            connections.append(connection)
        }
        #expect(probe.cancelled == paths.count)
    }

    @Test func aReadTheServerIsStillWaitingForIsAnsweredNormally() async throws {
        let probe = Probe()
        let (server, port, token) = try await serve { $0.files = { _, _, _ in await probe.hold(); return RemoteResponse.error(503) } }
        defer { server.stop() }
        let connection = try #require(LoopbackConnection(port: port))
        connection.send(get("/api/files/ver_1/thumb?w=120", token: token))
        await eventually { probe.started == 1 }
        // Bytes that arrive meanwhile are no goodbye.
        connection.send("\r\n")
        probe.release()
        let answer = await connection.answer(limit: 30)
        #expect(answer.hasPrefix("HTTP/1.1 503 "))
        #expect(probe.cancelled == 0 && probe.finished == 1)
    }

    @Test func aWriteIsNeverCancelledByAHangUp() async throws {
        let reading = Probe(), acting = Probe(), starting = Probe()
        let (server, port, token) = try await serve {
            $0.act = { _, _, _, _ in await acting.hold(); return .notFound }
            $0.browse = { route, _, _, _ in
                if case .newSession = route { await starting.hold() } else { await reading.hold() }
                return .notFound
            }
        }
        defer { server.stop() }
        let message = try #require(LoopbackConnection(port: port))
        message.send(post("/api/sessions/\(Self.session)/message", token: token, body: #"{"text":"hello","id":"made-up"}"#))
        let newSession = try #require(LoopbackConnection(port: port))
        newSession.send(post("/api/projects/proj_1/sessions", token: token, body: #"{"text":"hello","id":"made-up","planFirst":false}"#))
        await eventually { acting.started == 1 && starting.started == 1 }
        message.reset()
        newSession.hangUp()
        // A read hung up afterwards is dropped: the server has heard both goodbyes by the time it has heard this one.
        let history = try #require(LoopbackConnection(port: port))
        history.send(get("/api/sessions/\(Self.session)/history", token: token))
        await eventually { reading.started == 1 }
        history.hangUp()
        await eventually { reading.cancelled == 1 }
        #expect(acting.cancelled == 0 && acting.finished == 0, "a message already on its way is not abandoned")
        #expect(starting.cancelled == 0 && starting.finished == 0, "nor is a session already being started")
        acting.release()
        starting.release()
        await eventually { acting.finished == 1 && starting.finished == 1 }
        #expect(acting.cancelled == 0 && starting.cancelled == 0)
    }

    @Test func aCancelledTransferGivesItsPlaceBackOnceThePageHasLetGo() async throws {
        let probe = Probe()
        let (server, port, token) = try await serve { $0.files = { _, _, _ in await probe.hold(); return RemoteResponse.error(503) } }
        defer { server.stop() }
        // Two transfers a device may have under way; both hang up.
        var first: [LoopbackConnection] = []
        for n in 1...2 {
            let connection = try #require(LoopbackConnection(port: port))
            connection.send(get("/api/files/ver_\(n)/thumb?w=120", token: token))
            first.append(connection)
        }
        await eventually { probe.started == 2 }
        for connection in first { connection.hangUp() }
        await eventually { probe.finished == 2 }
        // The page's reads are over, so the device may start another (not told it is busy).
        let third = try #require(LoopbackConnection(port: port))
        third.send(get("/api/files/ver_3/thumb?w=120", token: token))
        await eventually { probe.started == 3 }
        third.hangUp()
        await eventually { probe.finished == 3 }
    }
}

// MARK: The page's fetch

@MainActor
private final class AbortRecord {
    var performed: [String] = []
    var aborted: [String] = []
    var gate: CheckedContinuation<Void, Never>?
}

@MainActor
struct PhoneArtifactAbortTests {
    private static let version = "ver_1"

    /// The phone's artifact routes as `Dependencies.live` builds them, over a page that waits and a record of
    /// what the page was asked to abort. Only the web view is made up.
    private func artifacts(perform: @escaping @MainActor (ArtifactRead, String) async -> ArtifactReadOutcome,
                           abort: @escaping @Sendable @MainActor (String) async -> Void) -> RemoteArtifacts {
        var dependencies = RemoteArtifacts.Dependencies.live(perform: perform, abort: abort)
        dependencies.browseOn = { true }
        dependencies.isSession = { _ in true }
        let listed = ListedFiles(), info = ListedFileInfo()
        listed.record([Self.version], device: "phone")
        info.record(Self.version, .init(name: "figure.png", mime: "image/png", size: 100, kind: .image))
        dependencies.listed = listed
        dependencies.info = info
        return RemoteArtifacts(dependencies: dependencies)
    }

    @Test func aCancelledFileReadAsksThePageToAbortItsFetchByTheNonceItReadUnder() async {
        let record = AbortRecord()
        let files = artifacts(perform: { _, nonce in
            record.performed.append(nonce)
            await withCheckedContinuation { record.gate = $0 }
            return .cancelled
        }, abort: { record.aborted.append($0) })
        let task = Task { await files.respond(.thumb(version: Self.version), target: "/api/files/ver_1/thumb?w=120", device: "phone") }
        await eventually { record.gate != nil }
        #expect(record.aborted.isEmpty)
        task.cancel()
        await eventually { !record.aborted.isEmpty }
        #expect(record.aborted == record.performed)
        #expect(record.performed.count == 1)
        record.gate?.resume()
        // The read comes back cancelled, and the route says only that the file couldn't be read.
        #expect(await task.value.status == 503)
    }

    @Test func aReadNobodyCancelsIsNeverAborted() async {
        let record = AbortRecord()
        let webp = Data("RIFF\u{4}\0\0\0WEBPVP8L".utf8)
        let files = artifacts(perform: { _, nonce in
            record.performed.append(nonce)
            return .bytes(webp)
        }, abort: { record.aborted.append($0) })
        let reply = await files.respond(.thumb(version: Self.version), target: "/api/files/ver_1/thumb?w=120", device: "phone")
        #expect(reply.status == 200 && reply.body == webp)
        #expect(record.performed.count == 1 && record.aborted.isEmpty)
    }
}
