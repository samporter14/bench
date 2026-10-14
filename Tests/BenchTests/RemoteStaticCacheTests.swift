// RemoteStaticCacheTests.swift — the phone app's files and how long a browser
// may keep them: /app.js and /app.css are named in index.html by a content
// hash and kept for a year only when asked for by exactly that hash; the shell,
// the service worker and every API route stay no-store. The pure header rules
// first, then one real server on 127.0.0.1 (ports 47361…47369, outside Bench's
// own range and the other live tests') for the wiring.
import CryptoKit
import Foundation
import Testing
@testable import Bench

@MainActor
struct RemoteStaticCacheTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"
    private static let immutable = "Cache-Control: private, max-age=31536000, immutable\r\n"
    private static let noStore = "Cache-Control: no-store\r\n"

    private static var js: String { RemoteWebApp.assetVersions["/app.js"] ?? "missing" }
    private static var css: String { RemoteWebApp.assetVersions["/app.css"] ?? "missing" }

    /// The head of the response the server would build for `path` asked with `query`.
    private func response(_ path: String, _ query: String?) -> String {
        let file = RemoteWebApp.files[path]
        let headers = RemoteResponse.assetHeaders(path: path, query: query.map { Substring($0) })
        let bytes = RemoteResponse.make(status: 200, contentType: file?.contentType ?? "text/plain", body: Data(), headers: headers)
        return String(decoding: bytes, as: UTF8.self)
    }

    private func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: The header rules

    @Test func aVersionedFileAskedForByItsCurrentHashIsKeptForAYear() {
        for (path, hash) in [("/app.js", Self.js), ("/app.css", Self.css)] {
            let head = response(path, "v=\(hash)")
            #expect(head.hasPrefix("HTTP/1.1 200 OK\r\n"), "\(path)")
            #expect(head.contains(Self.immutable), "\(path)")
            // One Cache-Control, not the default beside it.
            #expect(count(of: "Cache-Control:", in: head) == 1, "\(path)")
            #expect(!head.contains("no-store"), "\(path)")
            // The other defaults stay.
            #expect(head.contains("X-Content-Type-Options: nosniff\r\n"), "\(path)")
            #expect(head.contains("Referrer-Policy: no-referrer\r\n"), "\(path)")
            #expect(head.contains("Cross-Origin-Resource-Policy: same-origin\r\n"), "\(path)")
        }
    }

    @Test func aMissingWrongOrPaddedVersionStaysNoStore() {
        let queries: [String?] = [
            nil, "", "v", "v=", "v=0", "v=000000000000",
            "v=\(Self.js)0", "v=\(Self.js.dropLast())", "v=\(Self.js.uppercased())", "V=\(Self.js)",
            "v=\(Self.js)&v=\(Self.js)", "v=\(Self.js)&x=1", "x=1&v=\(Self.js)", "v=\(Self.js)#", "v=\(Self.js)?v=\(Self.js)",
            "v=%\(Self.js.dropFirst())", " v=\(Self.js)", "v=\(Self.js) ", "v=\(Self.css)", "?v=\(Self.js)", "ver=\(Self.js)",
        ]
        for query in queries {
            let head = response("/app.js", query)
            #expect(head.contains(Self.noStore), "query \(query ?? "nil")")
            #expect(count(of: "Cache-Control:", in: head) == 1, "query \(query ?? "nil")")
            #expect(!head.contains("immutable"), "query \(query ?? "nil")")
        }
        // Each file has its own hash: the stylesheet's does not unlock the script, nor the script's the stylesheet.
        #expect(response("/app.js", "v=\(Self.css)").contains(Self.noStore))
        #expect(response("/app.css", "v=\(Self.js)").contains(Self.noStore))
    }

    @Test func nothingElseIsEverKept() {
        for path in ["/", PushServiceWorker.path, "/manifest.webmanifest", "/api/state", "/api/me", "/icon-180.png"] {
            for hash in [Self.js, Self.css, "anything"] {
                #expect(response(path, "v=\(hash)").contains(Self.noStore), "\(path) v=\(hash)")
                #expect(!response(path, "v=\(hash)").contains("immutable"), "\(path) v=\(hash)")
            }
        }
        // The hash is only for the two files that index.html names.
        #expect(Set(RemoteWebApp.assetVersions.keys) == ["/app.js", "/app.css"])
        #expect(RemoteWebApp.assetVersions[PushServiceWorker.path] == nil)
    }

    @Test func anErrorOrAnApiAnswerNeverCarriesTheYear() {
        for text in [String(decoding: RemoteResponse.error(404), as: UTF8.self),
                     String(decoding: RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: Data("{}".utf8)), as: UTF8.self)] {
            #expect(text.contains(Self.noStore))
            #expect(!text.contains("immutable"))
        }
    }

    @Test func aDefaultHeaderIsReplacedNotRepeated() {
        let head = String(decoding: RemoteResponse.head(status: 200, headers: [("cache-control", "max-age=5")]), as: UTF8.self)
        #expect(count(of: "ache-", in: head) == 1)
        #expect(head.contains("cache-control: max-age=5\r\n"))
        #expect(!head.contains("no-store"))
    }

    // MARK: The query is read apart from the path

    @Test func theQueryIsEverythingAfterTheFirstQuestionMarkAndNeverDecoded() {
        func query(_ target: String) -> Substring? { RemoteRequest(method: "GET", target: target).query }
        #expect(query("/app.js") == nil)
        #expect(query("/app.js?") == "")
        #expect(query("/app.js?v=abc") == "v=abc")
        #expect(query("/app.js?v=a?b") == "v=a?b")
        #expect(query("/app.js?v=%61bc") == "v=%61bc")
        #expect(RemoteRequest(method: "GET", target: "/app.js?v=abc").path == "/app.js")
    }

    @Test func aQueryDoesNotChangeWhichRouteIsMatched() {
        let policy = RemotePolicy.tailnet(dnsName: Self.host, login: Self.login)
        func evaluate(_ target: String) -> RemoteCheck.Outcome {
            RemoteCheck.evaluate(RemoteRequest(method: "GET", target: target, headers: ["host": ["\(Self.host):8443"], "tailscale-user-login": [Self.login]]),
                                 policy: policy)
        }
        #expect(evaluate("/app.js?v=\(Self.js)") == .accept(.file("/app.js"), token: nil))
        #expect(evaluate("/app.css?v=nothing") == .accept(.file("/app.css"), token: nil))
        #expect(evaluate("/app.js?") == .accept(.file("/app.js"), token: nil))
        #expect(evaluate("/sw.js?v=\(Self.js)") == .accept(.file("/sw.js"), token: nil))
        // The query is no part of the path: a file that isn't there is still 404, and an API route still wants its token.
        #expect(evaluate("/app.js.map?v=\(Self.js)") == .reject(404, route: nil, gate: .route))
        #expect(evaluate("/app.js/?v=\(Self.js)") == .reject(404, route: nil, gate: .route))
        #expect(evaluate("/api/state?v=\(Self.js)") == .reject(401, route: .state, gate: .token))
    }

    // MARK: The generated files

    @Test func theHashesAreOfTheBytesTheServerSends() throws {
        for path in ["/app.js", "/app.css"] {
            let file = try #require(RemoteWebApp.files[path])
            let digest = SHA256.hash(data: Data(file.body.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(RemoteWebApp.assetVersions[path] == String(digest.prefix(12)), "\(path)")
        }
        #expect(Self.js != Self.css)
        #expect(Self.js.count == 12 && Self.js.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test func theShellNamesTheCurrentHashes() throws {
        let shell = try #require(RemoteWebApp.files["/"]).body
        #expect(shell.contains(#"<script type="module" src="/app.js?v=\#(Self.js)"></script>"#))
        #expect(shell.contains(#"<link rel="stylesheet" href="/app.css?v=\#(Self.css)">"#))
        // No bare reference is left behind, and the service worker's address is its own.
        #expect(!shell.contains(#""/app.js""#))
        #expect(!shell.contains(#""/app.css""#))
        #expect(count(of: "/app.js", in: shell) == 1)
        #expect(count(of: "/app.css", in: shell) == 1)
        #expect(!shell.contains("sw.js"))
    }

    // MARK: The permission card's code box (the phone's own files, as embedded)

    @Test func theCodeBoxWrapsInsideThePageAndNeverFoldsOrScrolls() throws {
        let css = try #require(RemoteWebApp.files["/app.css"]).body
        let start = try #require(css.range(of: "\n.perm-code {\n"))
        let end = try #require(css.range(of: "\n}\n", range: start.upperBound..<css.endIndex))
        let rule = String(css[start.upperBound..<end.lowerBound])
        #expect(rule.contains("white-space: pre-wrap;"))
        #expect(rule.contains("overflow-wrap: anywhere;"))
        #expect(rule.contains("max-width: 100%;"))
        #expect(!rule.contains("max-height"))
        #expect(!rule.contains("overflow: auto") && !rule.contains("overflow: scroll") && !rule.contains("overflow-x"))
        #expect(!rule.contains("white-space: pre;"))
        // Each line carries a number where it starts, and nothing else sets a height on the box.
        #expect(css.contains(".perm-code .ln::before {\ncontent: counter(ln);"))
        #expect(!css.contains(".perm-code.all"))

        let js = try #require(RemoteWebApp.files["/app.js"]).body
        #expect(!js.contains("PERM_LINES"))
        #expect(!js.contains("permAll"))
        #expect(!js.contains("perm-more"))
        #expect(js.contains("lines of code once?"))
    }

    // MARK: A real server

    /// Sends `text` on a new connection and reads until the server closes it.
    private nonisolated static func exchange(_ text: String, port: UInt16) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "" }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return "" }
        var wait = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            answer.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: answer, as: UTF8.self)
    }

    @Test func theServerKeepsTheVersionedFilesAndOnlyThose() async throws {
        let server = RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: RemoteAuth(store: MemoryDeviceStore()),
                                  backend: RemoteBackend(state: { Data("{}".utf8) }, session: { _ in nil }, open: { _ in false }, version: "test"))
        let port = try await server.start(candidates: Array(47361...47369))
        defer { server.stop() }
        func get(_ target: String) async -> String {
            let text = "GET \(target) HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\n\r\n"
            return await Task.detached { Self.exchange(text, port: port) }.value
        }

        let script = await get("/app.js?v=\(Self.js)")
        #expect(script.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(script.contains(Self.immutable))
        #expect(count(of: "Cache-Control:", in: script) == 1)
        #expect(script.contains("Content-Type: text/javascript; charset=utf-8\r\n"))
        #expect(script.hasSuffix(try #require(RemoteWebApp.files["/app.js"]).body))

        let sheet = await get("/app.css?v=\(Self.css)")
        #expect(sheet.contains(Self.immutable))
        #expect(sheet.contains("Content-Type: text/css; charset=utf-8\r\n"))

        for target in ["/app.js", "/app.js?v=old", "/app.js?v=\(Self.js)&x=1", "/app.css?v=\(Self.js)", "/", "/?v=\(Self.js)",
                       "/sw.js", "/sw.js?v=\(Self.js)", "/manifest.webmanifest?v=\(Self.js)", "/icon-180.png?v=\(Self.js)"] {
            let answer = await get(target)
            #expect(answer.hasPrefix("HTTP/1.1 200 OK\r\n") || target.hasPrefix("/icon"), "\(target)")
            #expect(answer.contains(Self.noStore), "\(target)")
            #expect(!answer.contains("immutable"), "\(target)")
        }
        // The state needs a device: refused, and still no-store.
        let state = await get("/api/state?v=\(Self.js)")
        #expect(state.hasPrefix("HTTP/1.1 401 "))
        #expect(state.contains(Self.noStore))
    }
}
