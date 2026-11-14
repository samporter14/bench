// RemoteRevocationTests.swift — a device removed while one of its requests is
// still on its way: the server is real and so are its sockets (as in
// RemotePhotosFlowTests' live tests), and the backend only records what it was
// asked. A photo's body may take two minutes to arrive; the head was let in, but
// nothing is done for a device removed before the body is all here.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root

@MainActor
struct RemoteRevocationTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"

    private final class Seen: @unchecked Sendable {
        var photos = 0
    }

    private struct Rig {
        let server: RemoteServer
        let port: UInt16
        let token: String
        let device: RemoteDevice
        let auth: RemoteAuth
        let store: MemoryDeviceStore
    }

    private func rig(seen: Seen, clock: ServerClock) async throws -> Rig {
        let store = MemoryDeviceStore()
        let auth = RemoteAuth(store: store, fixedCode: "000000")
        guard case .paired(let token, let device) = auth.pair(code: "000000", name: "Phone", now: clock.date) else {
            Issue.record("not paired")
            throw WebAPIError.notReady
        }
        let server = RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: auth,
                                  backend: RemoteBackend(state: { Data("{}".utf8) }, session: { _ in nil }, open: { _ in false },
                                                         version: "test", photo: { _, _, _ in
            seen.photos += 1
            return RemoteActionReply(status: 200, body: Data(#"{"result":"sent","sentence":"Sent."}"#.utf8))
        }), now: { clock.date }, sleep: { await clock.sleep($0) })
        let port = try await server.start(candidates: Array(47381...47389))
        return Rig(server: server, port: port, token: token, device: device, auth: auth, store: store)
    }

    private func head(_ path: String, token: String, length: Int, method: String = "POST") -> String {
        "\(method) \(path) HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\nCookie: bench_device=\(token)\r\n"
            + "Content-Type: application/json\r\nOrigin: https://\(Self.host):8443\r\nX-Bench: 1\r\nContent-Length: \(length)\r\n\r\n"
    }

    /// The head and the first part of a photo's body, then the server waiting for the rest.
    private func startPhoto(_ rig: Rig, clock: ServerClock) async throws -> (LoopbackConnection, [UInt8]) {
        let body = [UInt8](repeating: 0x41, count: 20_000)
        let connection = try #require(LoopbackConnection(port: rig.port))
        connection.send(Array(head("/api/sessions/\(root)/photo", token: rig.token, length: body.count).utf8) + body[0..<5_000])
        // The head's own wait, the body's, and the first piece starting it again.
        await eventually { clock.asked.count >= 3 }
        return (connection, Array(body[5_000...]))
    }

    /// Removed the way the app removes it: the server is told, and the request
    /// still waiting for its body goes with the device.
    @Test func aDeviceRemovedWhileItsPhotoArrivesHasItsRequestClosed() async throws {
        let seen = Seen()
        let clock = ServerClock()
        let rig = try await rig(seen: seen, clock: clock)
        defer { rig.server.stop() }
        let (connection, rest) = try await startPhoto(rig, clock: clock)
        #expect(rig.auth.remove(rig.device.id) == .removed)
        rig.server.revoke(device: rig.device.id)
        connection.send(rest)
        let answer = await connection.answer(limit: 30)
        #expect(!answer.hasPrefix("HTTP/1.1 200 "), "\(answer.prefix(40))")
        #expect(seen.photos == 0)
    }

    /// The server not told at all: the device is asked about again once the
    /// body is in, and the photo is refused, not sent.
    @Test func aDeviceRemovedWhileItsPhotoArrivesIsAskedAboutAgainAndRefused() async throws {
        let seen = Seen()
        let clock = ServerClock()
        let rig = try await rig(seen: seen, clock: clock)
        defer { rig.server.stop() }
        let (connection, rest) = try await startPhoto(rig, clock: clock)
        rig.store.failsToSave = true
        // Refused at once even though the list couldn't be written.
        #expect(rig.auth.remove(rig.device.id) == .notStored)
        connection.send(rest)
        let answer = await connection.answer(limit: 30)
        #expect(answer.hasPrefix("HTTP/1.1 401 "), "\(answer.prefix(40))")
        #expect(seen.photos == 0)
    }

    /// A device still paired is untouched by another's removal.
    @Test func anotherDevicesRemovalLeavesThePhotoAlone() async throws {
        let seen = Seen()
        let clock = ServerClock()
        let rig = try await rig(seen: seen, clock: clock)
        defer { rig.server.stop() }
        guard case .paired(_, let other) = rig.auth.pair(code: "000000", name: "Tablet", now: clock.date) else {
            Issue.record("not paired")
            return
        }
        let (connection, rest) = try await startPhoto(rig, clock: clock)
        rig.auth.remove(other.id)
        rig.server.revoke(device: other.id)
        connection.send(rest)
        let answer = await connection.answer(limit: 30)
        #expect(answer.hasPrefix("HTTP/1.1 200 "), "\(answer.prefix(40))")
        #expect(seen.photos == 1)
    }

    /// Unpairing from the phone when the list can't be written: the phone is
    /// still unpaired (cookie cleared, token refused) and is told it wasn't saved.
    @Test func unpairingThatCantBeSavedSaysSoAndStillUnpairs() async throws {
        let seen = Seen()
        let clock = ServerClock()
        let rig = try await rig(seen: seen, clock: clock)
        defer { rig.server.stop() }
        rig.store.failsToSave = true
        let connection = try #require(LoopbackConnection(port: rig.port))
        connection.send(head("/api/unpair", token: rig.token, length: 2) + "{}")
        let answer = await connection.answer(limit: 30)
        #expect(answer.hasPrefix("HTTP/1.1 200 "), "\(answer.prefix(40))")
        #expect(answer.contains("Max-Age=0"))
        #expect(answer.hasSuffix(#"{"paired":false,"saved":false}"#))
        #expect(rig.auth.device(forToken: rig.token, now: clock.date) == nil)
        #expect(rig.auth.revoked == [rig.device.id])
    }

    @Test func unpairingThatIsSavedSaysOnlyPairedFalse() async throws {
        let seen = Seen()
        let clock = ServerClock()
        let rig = try await rig(seen: seen, clock: clock)
        defer { rig.server.stop() }
        let connection = try #require(LoopbackConnection(port: rig.port))
        connection.send(head("/api/unpair", token: rig.token, length: 2) + "{}")
        let answer = await connection.answer(limit: 30)
        #expect(answer.hasSuffix(#"{"paired":false}"#))
        #expect(rig.auth.revoked.isEmpty)
    }
}
