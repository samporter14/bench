// RemoteServerTests.swift — reading a request, the route table and every
// check a request must pass, on made-up requests. Nothing listens.
import Foundation
import Testing
@testable import Bench

struct RemoteServerTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"
    private static let policy = RemotePolicy.tailnet(dnsName: host, login: login)
    private static let token = String(repeating: "A", count: 43)
    private static let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

    private func request(_ target: String, headers: [String: [String]] = [:], cookie: Bool = true) -> RemoteRequest {
        request("GET", target, headers: headers, cookie: cookie)
    }

    /// A request as Serve passes it on from a paired phone.
    private func request(_ method: String, _ target: String, headers: [String: [String]] = [:],
                         body: Data = Data(), cookie: Bool = true) -> RemoteRequest {
        var all: [String: [String]] = [
            "host": ["\(Self.host):8443"],
            "tailscale-user-login": [Self.login],
        ]
        if cookie { all["cookie"] = ["theme=dark; bench_device=\(Self.token)"] }
        if method == "POST" {
            all["content-type"] = ["application/json"]
            all["origin"] = ["https://\(Self.host):8443"]
            all["x-bench"] = ["1"]
        }
        for (name, values) in headers { all[name] = values }
        return RemoteRequest(method: method, target: target, headers: all, body: body)
    }

    private func status(_ request: RemoteRequest, policy: RemotePolicy = RemoteServerTests.policy) -> Int {
        switch RemoteCheck.evaluate(request, policy: policy) {
        case .reject(let status, _, _): status
        case .accept: 200
        }
    }

    // MARK: The checks

    @Test func aGoodRequestPassesWithItsToken() {
        #expect(RemoteCheck.evaluate(request("/api/state"), policy: Self.policy) == .accept(.state, token: Self.token))
        #expect(status(request("POST", "/api/sessions/\(Self.id)/open")) == 200)
    }

    @Test func theHostWithoutAPortPasses() {
        #expect(status(request("/api/state", headers: ["host": [Self.host]])) == 200)
        #expect(status(request("/api/state", headers: ["host": ["STUDIO-MAC.example-tailnet.ts.net:8443"]])) == 200)
    }

    @Test func aWrongHostIs403() {
        #expect(status(request("/api/state", headers: ["host": ["evil.example.com"]])) == 403)
        #expect(status(request("/api/state", headers: ["host": ["127.0.0.1:47280"]])) == 403)
        #expect(status(request("/api/state", headers: ["host": ["\(Self.host):443"]])) == 403)
        #expect(status(request("/", headers: ["host": []])) == 403)
        // Before anything else: a wrong Host on a path that doesn't exist is still 403.
        #expect(status(request("/nothing", headers: ["host": ["evil.example.com"]])) == 403)
    }

    @Test func twoHostsAre403() {
        #expect(status(request("/api/state", headers: ["host": ["\(Self.host):8443", "evil.example.com"]])) == 403)
    }

    @Test func nothingIsServedUntilTheNameIsKnown() {
        #expect(status(request("/"), policy: .closed) == 403)
    }

    @Test func serveIdentityMustMatchTheRecordedLogin() {
        #expect(status(request("/api/state", headers: ["tailscale-user-login": ["someone@example.com"]])) == 403)
        #expect(status(request("/api/state", headers: ["tailscale-user-login": []])) == 403)
        #expect(status(request("/api/state", headers: ["tailscale-user-login": ["PAT@example.com"]])) == 200)
    }

    @Test func eachRefusalNamesItsGate() {
        func gate(_ request: RemoteRequest) -> RemoteCheck.Gate? {
            if case .reject(_, _, let gate) = RemoteCheck.evaluate(request, policy: Self.policy) { gate } else { nil }
        }
        #expect(gate(request("/", headers: ["host": ["evil.example.com"]])) == .host)
        #expect(gate(request("/", headers: ["tailscale-user-login": []])) == .login)
        #expect(gate(request("/", headers: ["tailscale-funnel-request": ["?1"]])) == .funnel)
        #expect(gate(request("/nothing")) == .route)
        #expect(gate(request("POST", "/api/state")) == .method)
        #expect(gate(request("POST", "/pair", headers: ["content-type": ["text/plain"]])) == .type)
        #expect(gate(request("POST", "/pair", headers: ["origin": ["https://evil.example.com"]])) == .origin)
        #expect(gate(request("POST", "/pair", headers: ["x-bench": []])) == .xbench)
        #expect(gate(request("/api/state", cookie: false)) == .token)
    }

    @Test func funnelIsRefused() {
        #expect(status(request("/", headers: ["tailscale-funnel-request": ["?1"]])) == 403)
    }

    @Test func noTokenIs401() {
        #expect(status(request("/api/state", cookie: false)) == 401)
        #expect(status(request("/api/me", headers: ["cookie": ["bench_device=short"]])) == 401)
        #expect(status(request("/api/events", headers: ["cookie": ["other=\(Self.token)"]])) == 401)
        #expect(status(request("POST", "/api/unpair", cookie: false)) == 401)
    }

    @Test func theShellAndItsFilesNeedNoToken() {
        #expect(status(request("/", cookie: false)) == 200)
        #expect(status(request("/app.js", cookie: false)) == 200)
        #expect(status(request("/manifest.webmanifest", cookie: false)) == 200)
        #expect(status(request("/icon-180.png", cookie: false)) == 200)
        #expect(status(request("POST", "/pair", cookie: false)) == 200)
    }

    @Test func aWrongOriginOnAPostIs403() {
        #expect(status(request("POST", "/pair", headers: ["origin": ["https://evil.example.com"]])) == 403)
        #expect(status(request("POST", "/pair", headers: ["origin": ["http://\(Self.host):8443"]])) == 403)
        #expect(status(request("POST", "/pair", headers: ["origin": []])) == 403)
        #expect(status(request("POST", "/api/unpair", headers: ["origin": ["null"]])) == 403)
    }

    @Test func aPostNeedsXBenchAndJSON() {
        #expect(status(request("POST", "/pair", headers: ["x-bench": []])) == 403)
        #expect(status(request("POST", "/pair", headers: ["x-bench": ["yes"]])) == 403)
        #expect(status(request("POST", "/pair", headers: ["content-type": ["text/plain"]])) == 415)
        #expect(status(request("POST", "/pair", headers: ["content-type": ["application/x-www-form-urlencoded"]])) == 415)
        #expect(status(request("POST", "/pair", headers: ["content-type": ["application/json; charset=utf-8"]])) == 200)
    }

    @Test func anOversizedBodyIs413() {
        let big = Data(repeating: 0x20, count: RemoteHTTP.maxBody + 1)
        #expect(status(request("POST", "/pair", body: big)) == 413)
        #expect(status(request("POST", "/pair", body: Data(repeating: 0x20, count: RemoteHTTP.maxBody))) == 200)
    }

    @Test func anUnknownRouteIs404() {
        #expect(status(request("/api/sessions")) == 404)
        #expect(status(request("/api/secrets")) == 404)
        #expect(status(request("/app.js.map")) == 404)
        #expect(status(request("/index.html")) == 404)
        #expect(status(request("/api/state/")) == 404)
        #expect(status(request("/API/state")) == 404)
        #expect(status(request("/%61pi/state")) == 404)
    }

    @Test func anIDThatDoesNotMatchIs404() {
        #expect(status(request("/api/sessions/abc")) == 404)
        #expect(status(request("/api/sessions/0F8FAD5B-D9CB-469F-A165-70867728950E")) == 404)
        #expect(status(request("/api/sessions/0f8fad5b-d9cb-469f-a165-70867728950e0")) == 404)
        #expect(status(request("/api/sessions/../../../etc/passwd-0000000000000000000")) == 404)
        #expect(status(request("/api/sessions/0g8fad5b-d9cb-469f-a165-70867728950e")) == 404)
        #expect(status(request("POST", "/api/sessions/\(Self.id)/close")) == 404)
        #expect(status(request("/api/sessions/\(Self.id)/open/more")) == 404)
        #expect(status(request("/api/sessions/\(Self.id)")) == 200)
    }

    @Test func aKnownPathUnderAnotherMethodIs405() {
        #expect(status(request("POST", "/api/state")) == 405)
        #expect(status(request("GET", "/pair")) == 405)
        #expect(status(request("DELETE", "/api/me")) == 405)
        #expect(status(request("GET", "/api/sessions/\(Self.id)/open")) == 405)
    }

    @Test func theQueryIsNotPartOfTheRoute() {
        #expect(RemoteCheck.evaluate(request("/api/state?fresh=1"), policy: Self.policy) == .accept(.state, token: Self.token))
    }

    @Test func theDemoAllowsLoopbackOnly() {
        let demo = RemotePolicy.demo(port: 47281)
        let local = RemoteRequest(method: "GET", target: "/", headers: ["host": ["127.0.0.1:47281"]])
        #expect(status(local, policy: demo) == 200)
        let named = RemoteRequest(method: "GET", target: "/", headers: ["host": ["localhost:47281"]])
        #expect(status(named, policy: demo) == 200)
        let otherPort = RemoteRequest(method: "GET", target: "/", headers: ["host": ["127.0.0.1:47280"]])
        #expect(status(otherPort, policy: demo) == 403)
        let rebound = RemoteRequest(method: "GET", target: "/", headers: ["host": ["attacker.example:47281"]])
        #expect(status(rebound, policy: demo) == 403)
        #expect(!demo.secureCookie)
    }

    @Test func theLogNamesThePatternNeverTheID() {
        guard case .found(let route) = RemoteRoute.match(method: "GET", path: "/api/sessions/\(Self.id)") else {
            Issue.record("no route")
            return
        }
        #expect(route == .session(Self.id))
        #expect(route.pattern == "/api/sessions/<id>")
        #expect(!route.pattern.contains(Self.id))
        #expect(RemoteRoute.openSession(Self.id).pattern == "/api/sessions/<id>/open")
    }

    @Test func onlyTheAPINeedsAToken() {
        #expect(!RemoteRoute.shell.needsToken)
        #expect(!RemoteRoute.pair.needsToken)
        #expect(!RemoteRoute.icon(512).needsToken)
        #expect(RemoteRoute.me.needsToken)
        #expect(RemoteRoute.events.needsToken)
        #expect(RemoteRoute.openSession(Self.id).needsToken)
    }

    // MARK: Reading a request

    private func parse(_ text: String) -> RemoteHTTP.Parse {
        RemoteHTTP.parse(Data(text.utf8))
    }

    @Test func aWholeRequestIsRead() {
        let parsed = parse("POST /pair HTTP/1.1\r\nHost: a.ts.net:8443\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"code\":\"1\"}x")
        guard case .request(let request) = parsed else {
            Issue.record("not read: \(parsed)")
            return
        }
        #expect(request.method == "POST")
        #expect(request.target == "/pair")
        #expect(request.single("host") == "a.ts.net:8443")
        #expect(request.single("content-type") == "application/json")
        #expect(request.body == Data("{\"code\":\"1\"}x".utf8))
    }

    @Test func aPartRequestWaits() {
        #expect(parse("GET / HTTP/1.1\r\nHost: a") == .incomplete)
        #expect(parse("POST /pair HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"co") == .incomplete)
    }

    @Test func aBodyOverTheCapIsRefusedBeforeItArrives() {
        #expect(parse("POST /pair HTTP/1.1\r\nContent-Length: 8193\r\n\r\n") == .reject(413))
        #expect(parse("POST /pair HTTP/1.1\r\nContent-Length: 99999999999\r\n\r\n") == .reject(400))
    }

    @Test func tooMuchHeaderIs431() {
        let long = "GET / HTTP/1.1\r\nX-Pad: " + String(repeating: "a", count: RemoteHTTP.maxHead + 10)
        #expect(parse(long) == .reject(431))
        #expect(parse(long + "\r\n\r\n") == .reject(431))
    }

    @Test func malformedRequestsAreRefused() {
        // Chunked bodies aren't taken, nor two lengths, nor a length that isn't a number.
        #expect(parse("POST /pair HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") == .reject(501))
        #expect(parse("POST /pair HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\n{}") == .reject(400))
        #expect(parse("POST /pair HTTP/1.1\r\nContent-Length: -1\r\n\r\n") == .reject(400))
        // Absolute and authority targets, a bad version, a folded header.
        #expect(parse("GET http://evil.example/ HTTP/1.1\r\n\r\n") == .reject(400))
        #expect(parse("GET //evil.example/ HTTP/1.1\r\n\r\n") == .reject(400))
        #expect(parse("GET / HTTP/2\r\n\r\n") == .reject(505))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\r\n folded\r\n\r\n") == .reject(400))
        #expect(parse("GET /  HTTP/1.1\r\n\r\n") == .reject(400))
        #expect(parse("get / HTTP/1.1\r\n\r\n") == .reject(400))
        #expect(RemoteHTTP.parse(Data("GET /\u{e9} HTTP/1.1\r\n\r\n".utf8)) == .reject(400))
        #expect(parse("GET / HTTP/1.1\r\nHost a\r\n\r\n") == .reject(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\nX-Other: b\r\n\r\n") == .reject(400))
        #expect(parse("GET / HTTP/1.1\r\nHost: a\rb\r\n\r\n") == .reject(400))
    }

    @Test func headerNamesAreCaseInsensitiveAndRepeatsKept() {
        guard case .request(let request) = parse("GET / HTTP/1.1\r\nHOST: a\r\nhost: b\r\n\r\n") else {
            Issue.record("not read")
            return
        }
        #expect(request.headers["host"] == ["a", "b"])
        #expect(request.single("host") == nil)
    }

    // MARK: Responses

    @Test func everyResponseCarriesTheSecurityHeaders() {
        let html = String(decoding: RemoteResponse.make(status: 200, contentType: "text/html; charset=utf-8", body: Data("<p>".utf8)), as: UTF8.self)
        #expect(html.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(html.contains("Cache-Control: no-store\r\n"))
        #expect(html.contains("X-Content-Type-Options: nosniff\r\n"))
        #expect(html.contains("Referrer-Policy: no-referrer\r\n"))
        #expect(html.contains("Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\r\n"))
        #expect(html.contains("Content-Length: 3\r\n"))
        #expect(html.hasSuffix("\r\n\r\n<p>"))

        let error = String(decoding: RemoteResponse.error(404), as: UTF8.self)
        #expect(error.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(error.contains("Cache-Control: no-store\r\n"))
        #expect(!error.contains("Content-Security-Policy"))
        #expect(error.hasSuffix("{\"error\":\"Not Found\"}"))

        let stream = String(decoding: RemoteResponse.eventStreamHead(), as: UTF8.self)
        #expect(stream.contains("Content-Type: text/event-stream"))
        #expect(stream.contains("Cache-Control: no-store\r\n"))
        #expect(!stream.contains("Content-Length"))
    }

    @Test func theCookieIsHttpOnlyStrictAndSecure() {
        let (name, value) = RemoteResponse.deviceCookie(Self.token, secure: true)
        #expect(name == "Set-Cookie")
        #expect(value == "bench_device=\(Self.token); Path=/; Max-Age=34560000; HttpOnly; SameSite=Strict; Secure")
        #expect(!RemoteResponse.deviceCookie(Self.token, secure: false).1.contains("Secure"))
        #expect(RemoteResponse.clearedCookie(secure: true).1.hasPrefix("bench_device=; Path=/; Max-Age=0;"))
    }

    @Test func eventsAreOneLineOfJSON() {
        let event = RemoteResponse.stateEvent(Data("{\"version\":1}".utf8))
        #expect(String(decoding: event, as: UTF8.self) == "event: state\ndata: {\"version\":1}\n\n")
        #expect(String(decoding: RemoteResponse.keepalive, as: UTF8.self) == ": keepalive\n\n")
    }

    // MARK: Ports

    @Test @MainActor func theRememberedPortIsTriedFirst() {
        #expect(RemoteServer.candidates(remembered: nil) == Array(47280...47290))
        #expect(RemoteServer.candidates(remembered: 47283).first == 47283)
        #expect(RemoteServer.candidates(remembered: 47283).count == 11)
        #expect(RemoteServer.candidates(remembered: 8080) == Array(47280...47290))
    }
}
