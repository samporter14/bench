// RemoteServerLiveTests.swift — the server itself, listening on 127.0.0.1 on a
// port outside Bench's own range (47391…47399), with made-up devices in
// memory and a made-up backend: a head that fails its checks is refused
// before its body comes, a body that never comes is given up after 3 s, and a
// device over its budget hears 429. Nothing reaches Tailscale, the devices
// file or a web view.
import Foundation
import Testing
@testable import Bench

@MainActor
struct RemoteServerLiveTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"

    private func server(_ auth: RemoteAuth = RemoteAuth(store: MemoryDeviceStore())) async throws -> (RemoteServer, UInt16) {
        let server = RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: auth,
                                  backend: RemoteBackend(state: { Data("{}".utf8) }, session: { _ in nil }, open: { _ in false },
                                                         version: "test"))
        let port = try await server.start(candidates: Array(47391...47399))
        return (server, port)
    }

    /// Sends `text` on a new connection and reads until the server closes it
    /// or `limit` passes: what came back, and how long it took.
    private nonisolated static func exchange(_ text: String, port: UInt16, limit: TimeInterval) -> (String, TimeInterval) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return ("", 0) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return ("", 0) }
        var wait = timeval(tv_sec: Int(limit), tv_usec: Int32((limit - limit.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        let started = Date()
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date().timeIntervalSince(started) < limit {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            answer.append(contentsOf: buffer[0..<count])
        }
        return (String(decoding: answer, as: UTF8.self), Date().timeIntervalSince(started))
    }

    private func exchange(_ text: String, port: UInt16, limit: TimeInterval = 8) async -> (String, TimeInterval) {
        await Task.detached { Self.exchange(text, port: port, limit: limit) }.value
    }

    @Test func aHeadThatFailsItsChecksIsRefusedWithItsBodyStillToCome() async throws {
        let (server, port) = try await server()
        defer { server.stop() }
        let head = "POST /pair HTTP/1.1\r\nHost: evil.example.com\r\nContent-Type: application/json\r\nContent-Length: 10\r\n\r\n"
        let (answer, seconds) = await exchange(head, port: port)
        #expect(answer.hasPrefix("HTTP/1.1 403 "))
        #expect(seconds < 2)
        // A stranger's login is refused just as early.
        let stranger = "POST /pair HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: someone@example.com\r\n"
            + "Content-Type: application/json\r\nContent-Length: 10\r\n\r\n"
        let (refused, quickly) = await exchange(stranger, port: port)
        #expect(refused.hasPrefix("HTTP/1.1 403 "))
        #expect(quickly < 2)
    }

    @Test func aBodyThatNeverComesIsGivenUpAfterThreeSeconds() async throws {
        let (server, port) = try await server()
        defer { server.stop() }
        let head = "POST /pair HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\n"
            + "Content-Type: application/json\r\nOrigin: https://\(Self.host):8443\r\nX-Bench: 1\r\nContent-Length: 10\r\n\r\n"
        let (answer, seconds) = await exchange(head, port: port)
        #expect(answer.hasPrefix("HTTP/1.1 408 "))
        #expect(seconds > 2.5 && seconds < 6)
    }

    @Test func aDeviceOverItsBudgetIsToldToSlowDown() async throws {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        guard case .paired(let token, _) = auth.pair(code: "000000", name: "Phone") else {
            Issue.record("not paired")
            return
        }
        let (server, port) = try await server(auth)
        defer { server.stop() }
        let get = "GET /api/state HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\n"
            + "Cookie: bench_device=\(token)\r\n\r\n"
        for n in 0..<Int(RequestBucket.capacity) {
            let (answer, _) = await exchange(get, port: port)
            #expect(answer.hasPrefix("HTTP/1.1 200 "), "request \(n)")
        }
        let (over, _) = await exchange(get, port: port)
        #expect(over.hasPrefix("HTTP/1.1 429 "))
        #expect(over.contains("Retry-After: 1\r\n"))
        #expect(over.hasSuffix(#"{"error":"slowDown"}"#))
    }
}
