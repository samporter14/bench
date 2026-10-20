// RemoteServerLiveTests.swift — the server itself, listening on 127.0.0.1 on a
// port outside Bench's own range (47391…47399), with made-up devices in
// memory and a made-up backend: a head that fails its checks is refused
// before its body comes, a body that never comes is given up after 3 s, and a
// device over its budget hears 429. Nothing reaches Tailscale, the devices
// file or a web view.
//
// The sockets are real; the clock is not. The server's time limits wait on a
// `ServerClock`, which lets one pass only when the test says so, and its notion
// of "now" is the same clock's, so no test here depends on how fast the Mac is.
// One test keeps the real timer, with a floor and a generous ceiling.
import Foundation
import Testing
@testable import Bench

// MARK: A clock the test holds, and a socket it drives by hand

/// Stands in for the server's clock: a time limit it waits on passes only when
/// the test says so (`advance`), and `date` moves with it. Every limit asked
/// for is kept, in order. Used by the live tests of the photo routes too.
@MainActor
final class ServerClock {
    private struct Sleeper {
        let due: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private var sleepers: [Int: Sleeper] = [:]
    private var next = 0
    private let start = Date(timeIntervalSince1970: 1_792_000_000)
    /// How far the clock has been moved on since it was made.
    private(set) var elapsed: Duration = .zero
    /// Every limit the server waited on, in the order it asked, cancelled or not.
    private(set) var asked: [Duration] = []

    /// What the server takes for now.
    var date: Date {
        let parts = elapsed.components
        return start.addingTimeInterval(Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }

    /// Limits still being waited on.
    var pending: Int { sleepers.count }

    /// The server's wait: returns when the limit has passed, or at once when
    /// its task is cancelled.
    func sleep(_ limit: Duration) async {
        asked.append(limit)
        guard !Task.isCancelled else { return }
        let id = next
        next += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { sleepers[id] = Sleeper(due: elapsed + limit, continuation: $0) }
        } onCancel: {
            Task { @MainActor [weak self] in self?.letGo(id) }
        }
    }

    private func letGo(_ id: Int) {
        sleepers.removeValue(forKey: id)?.continuation.resume()
    }

    /// Moves the clock on; every limit that has come due passes.
    func advance(by time: Duration) {
        elapsed += time
        for id in sleepers.filter({ $0.value.due <= elapsed }).keys.sorted() {
            sleepers.removeValue(forKey: id)?.continuation.resume()
        }
    }
}

/// Lets the other work run until `condition` holds, a few milliseconds at a
/// time. The minute is only a safety net for a broken run, never what a test
/// waits for.
@MainActor
func eventually(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let limit = ContinuousClock.now + .seconds(60)
    while !condition(), ContinuousClock.now < limit { try? await Task.sleep(for: .milliseconds(5)) }
    if !condition() { Issue.record("the condition never held", sourceLocation: sourceLocation) }
}

/// A client socket on 127.0.0.1 that a test drives by hand: `send` returns at
/// once, and `answer` reads whatever the server says until it hangs up.
final class LoopbackConnection: @unchecked Sendable {
    private let fd: Int32

    init?(port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        // A write to a connection the server closed is an error, not a signal.
        var quiet: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
        self.fd = fd
    }

    deinit {
        close(fd)
    }

    func send(_ text: String) {
        send(Array(text.utf8))
    }

    func send(_ bytes: [UInt8]) {
        _ = bytes.withUnsafeBytes { Foundation.send(fd, $0.baseAddress, $0.count, 0) }
    }

    /// What came back, until the server closes the connection or `limit`
    /// seconds pass. Reads off the main actor, which the server needs.
    func answer(limit: TimeInterval) async -> String {
        await Task.detached { self.read(limit: limit) }.value
    }

    private func read(limit: TimeInterval) -> String {
        var wait = timeval(tv_sec: Int(limit), tv_usec: Int32((limit - limit.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        let started = Date()
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date().timeIntervalSince(started) < limit {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            answer.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: answer, as: UTF8.self)
    }
}

// MARK: The server

@MainActor
struct RemoteServerLiveTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"

    /// A server whose time limits wait on `clock`; without one, the real timer.
    private func server(_ auth: RemoteAuth = RemoteAuth(store: MemoryDeviceStore()),
                        clock: ServerClock? = nil) async throws -> (RemoteServer, UInt16) {
        let backend = RemoteBackend(state: { Data("{}".utf8) }, session: { _ in nil }, open: { _ in false }, version: "test")
        let server = if let clock {
            RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: auth, backend: backend,
                         now: { clock.date }, sleep: { await clock.sleep($0) })
        } else {
            RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: auth, backend: backend)
        }
        let port = try await server.start(candidates: Array(47391...47399))
        return (server, port)
    }

    /// Sends `text` on a new connection and reads until the server closes it
    /// or `limit` passes: what came back, and how long it took. The limit is
    /// only a ceiling for a server that never answers.
    private func exchange(_ text: String, port: UInt16, limit: TimeInterval = 30) async -> (String, TimeInterval) {
        guard let connection = LoopbackConnection(port: port) else { return ("", 0) }
        let started = Date()
        connection.send(text)
        let answer = await connection.answer(limit: limit)
        return (answer, Date().timeIntervalSince(started))
    }

    private var pairHead: String {
        "POST /pair HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\n"
            + "Content-Type: application/json\r\nOrigin: https://\(Self.host):8443\r\nX-Bench: 1\r\nContent-Length: 10\r\n\r\n"
    }

    @Test func aHeadThatFailsItsChecksIsRefusedWithItsBodyStillToCome() async throws {
        let clock = ServerClock()
        let (server, port) = try await server(clock: clock)
        defer { server.stop() }
        let head = "POST /pair HTTP/1.1\r\nHost: evil.example.com\r\nContent-Type: application/json\r\nContent-Length: 10\r\n\r\n"
        let (answer, _) = await exchange(head, port: port)
        #expect(answer.hasPrefix("HTTP/1.1 403 "))
        // A stranger's login is refused just as early.
        let stranger = "POST /pair HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: someone@example.com\r\n"
            + "Content-Type: application/json\r\nContent-Length: 10\r\n\r\n"
        let (refused, _) = await exchange(stranger, port: port)
        #expect(refused.hasPrefix("HTTP/1.1 403 "))
        // "Early" is not a stopwatch reading: the clock never moved, so no wait for
        // the body can have run out, and none was even begun. A server that waited
        // for the ten bytes would not have answered at all.
        #expect(clock.elapsed == .zero)
        #expect(!clock.asked.contains(.seconds(3)), "\(clock.asked)")
    }

    @Test func aBodyThatNeverComesIsGivenUpAfterThreeSeconds() async throws {
        let clock = ServerClock()
        let (server, port) = try await server(clock: clock)
        defer { server.stop() }
        async let reply = exchange(pairHead, port: port)
        // The head's own wait (10 s) is let go once it passes its checks; the body has 3 s.
        await eventually { clock.asked.count == 2 && clock.pending == 1 }
        #expect(clock.asked == [RemoteServer.readTimeout, .seconds(3)])
        clock.advance(by: .milliseconds(2_900))
        #expect(clock.pending == 1, "not yet")
        clock.advance(by: .milliseconds(100))
        let (answer, _) = await reply
        #expect(answer.hasPrefix("HTTP/1.1 408 "))
    }

    /// The same, on the real timer: the one test here that really waits. It can't
    /// answer early, so the floor is firm; how late it answers is up to the Mac,
    /// so the ceiling is the exchange's, 30 s.
    @Test func aBodyThatNeverComesIsGivenUpByTheRealTimerToo() async throws {
        let (server, port) = try await server()
        defer { server.stop() }
        let (answer, seconds) = await exchange(pairHead, port: port)
        #expect(answer.hasPrefix("HTTP/1.1 408 "))
        #expect(seconds >= 2.5)
    }

    @Test func aDeviceOverItsBudgetIsToldToSlowDown() async throws {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        guard case .paired(let token, _) = auth.pair(code: "000000", name: "Phone") else {
            Issue.record("not paired")
            return
        }
        // The bucket fills at two a second; on a clock that stands still it can't, however slowly the Mac answers.
        let clock = ServerClock()
        let (server, port) = try await server(auth, clock: clock)
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
        // And it fills again as the clock moves on, as the Retry-After said.
        clock.advance(by: .seconds(1))
        let (later, _) = await exchange(get, port: port)
        #expect(later.hasPrefix("HTTP/1.1 200 "))
    }
}
