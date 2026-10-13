// RemoteServer.swift — the small HTTP/1.1 server behind Bench on your phone
// (DESIGN.md, Bench on your phone). It listens on 127.0.0.1 only; Tailscale
// Serve publishes it to the user's tailnet with a real certificate.
//
// Everything that decides is pure and tested: reading a request
// (`RemoteHTTP`), the one allowlisted route table (`RemoteRoute`) and every
// check a request must pass (`RemoteCheck`). `RemoteServer` is the thin part
// on Network framework that feeds them. It runs on the main queue: one phone
// or two, a few small requests, and the models it reads are main-actor.
//
// It logs the route's pattern and the status, never a path, a body, a token
// or anything a session says.
import AppKit
import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "remote")

// MARK: Reading a request

/// One request as read off the wire. Header names are lowercased; a name
/// sent twice keeps both values, so a doubled Host can be refused.
struct RemoteRequest: Equatable, Sendable {
    let method: String
    /// As sent: a path, maybe a query. Never percent-decoded.
    let target: String
    let headers: [String: [String]]
    let body: Data

    init(method: String, target: String, headers: [String: [String]] = [:], body: Data = Data()) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }

    /// The target without its query.
    var path: Substring {
        target.prefix { $0 != "?" }
    }

    /// The header's value when it was sent exactly once.
    func single(_ name: String) -> String? {
        guard let values = headers[name], values.count == 1 else { return nil }
        return values[0]
    }
}

/// HTTP/1.1 request parsing, pure. Only what Bench needs: origin-form
/// targets, `Content-Length` bodies up to 8 KB, no chunked uploads.
enum RemoteHTTP {
    /// The request line and headers together.
    static let maxHead = 16 * 1024
    static let maxBody = 8 * 1024

    enum Parse: Equatable {
        /// Not all here yet: read more.
        case incomplete
        case request(RemoteRequest)
        /// Refuse with this status and close.
        case reject(Int)
    }

    private static let headEnd = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> Parse {
        guard let end = buffer.range(of: headEnd) else {
            return buffer.count > maxHead ? .reject(431) : .incomplete
        }
        let headBytes = buffer[buffer.startIndex..<end.lowerBound]
        guard headBytes.count <= maxHead else { return .reject(431) }
        // Header bytes are printable ASCII and tabs; anything else is refused
        // rather than guessed at.
        guard headBytes.allSatisfy({ $0 == 0x0D || $0 == 0x0A || $0 == 0x09 || (0x20...0x7E).contains($0) }),
              let head = String(data: headBytes, encoding: .ascii) else { return .reject(400) }
        var lines = head.components(separatedBy: "\r\n")
        // A lone CR or LF is no line break here: refused, not split on.
        guard !lines.contains(where: { $0.contains("\r") || $0.contains("\n") }) else { return .reject(400) }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3 else { return .reject(400) }
        let method = String(requestLine[0]), target = String(requestLine[1]), version = requestLine[2]
        guard !method.isEmpty, method.allSatisfy({ ("A"..."Z").contains($0) }) else { return .reject(400) }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else { return .reject(505) }
        // Origin-form only: no absolute URLs, no `*`.
        guard target.hasPrefix("/"), !target.hasPrefix("//") else { return .reject(400) }

        var headers: [String: [String]] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .reject(400) }
            let name = line[..<colon]
            // No folded lines, no space before the colon.
            guard !name.isEmpty, name.allSatisfy(isTokenCharacter) else { return .reject(400) }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            headers[name.lowercased(), default: []].append(value)
        }

        // A body length Bench can't be sure of is refused: chunked uploads
        // aren't needed, and two lengths are a smuggling attempt.
        if headers["transfer-encoding"] != nil { return .reject(501) }
        var length = 0
        if let values = headers["content-length"] {
            guard values.count == 1, let text = values.first, !text.isEmpty, text.count <= 10,
                  text.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(text) else { return .reject(400) }
            length = number
        }
        guard length <= maxBody else { return .reject(413) }
        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .incomplete }
        let body = Data(buffer[bodyStart..<(bodyStart + length)])
        return .request(RemoteRequest(method: method, target: target, headers: headers, body: body))
    }

    /// RFC 9110's token characters, for header names.
    private static func isTokenCharacter(_ c: Character) -> Bool {
        guard let ascii = c.asciiValue else { return false }
        return (0x30...0x39).contains(ascii) || (0x41...0x5A).contains(ascii) || (0x61...0x7A).contains(ascii)
            || "!#$%&'*+-.^_`|~".utf8.contains(ascii)
    }
}

// MARK: The routes

/// The one allowlisted table (DESIGN.md, Routes). Anything not in it is 404.
enum RemoteRoute: Equatable, Sendable {
    case shell
    /// `/app.js`, `/app.css` or `/manifest.webmanifest`, from `RemoteWebApp`.
    case file(String)
    /// `/icon-180.png` or `/icon-512.png`.
    case icon(Int)
    case pair
    case me
    case unpair
    case state
    case events
    case session(String)
    case openSession(String)

    enum Match: Equatable {
        case found(RemoteRoute)
        /// The path is in the table, under another method.
        case wrongMethod
        case notFound
    }

    static let staticFiles: Set<String> = ["/app.js", "/app.css", "/manifest.webmanifest"]

    /// Matches the path exactly, never decoding it: `/api/sessions/<id>` only
    /// with a full frame id (`^[0-9a-f-]{36}$`).
    static func match(method: String, path: Substring) -> Match {
        guard let route = route(for: path) else { return .notFound }
        return method == route.method ? .found(route) : .wrongMethod
    }

    private static func route(for path: Substring) -> RemoteRoute? {
        switch path {
        case "/": return .shell
        case "/icon-180.png": return .icon(180)
        case "/icon-512.png": return .icon(512)
        case "/pair": return .pair
        case "/api/me": return .me
        case "/api/unpair": return .unpair
        case "/api/state": return .state
        case "/api/events": return .events
        default: break
        }
        if staticFiles.contains(String(path)) { return .file(String(path)) }
        let prefix = "/api/sessions/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = path.dropFirst(prefix.count)
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard let id = parts.first.map(String.init), PlanCheck.isFrameID(id) else { return nil }
        switch parts.count {
        case 1: return .session(id)
        case 2 where parts[1] == "open": return .openSession(id)
        default: return nil
        }
    }

    var method: String {
        switch self {
        case .pair, .unpair, .openSession: "POST"
        default: "GET"
        }
    }

    /// Every `/api/*` route needs a paired device's token.
    var needsToken: Bool {
        switch self {
        case .shell, .file, .icon, .pair: false
        default: true
        }
    }

    /// What the log names: the table's own pattern, never an id.
    var pattern: String {
        switch self {
        case .shell: "/"
        case .file(let path): path
        case .icon(let size): "/icon-\(size).png"
        case .pair: "/pair"
        case .me: "/api/me"
        case .unpair: "/api/unpair"
        case .state: "/api/state"
        case .events: "/api/events"
        case .session: "/api/sessions/<id>"
        case .openSession: "/api/sessions/<id>/open"
        }
    }
}

// MARK: The checks

/// Who may reach the server: the Host and Origin it is served under, and the
/// tailnet login Remote was turned on with.
struct RemotePolicy: Equatable, Sendable {
    /// Host values accepted, lowercased. Empty refuses every request: until
    /// Tailscale says the node's name, nothing is served.
    var hosts: Set<String>
    /// The origins a POST may come from.
    var origins: Set<String>
    /// When set, Serve's `Tailscale-User-Login` must be there and equal it.
    /// Nil only in `--demo remote`, which Serve never fronts.
    var login: String?
    /// The device cookie's `Secure` flag: off only in the demo, which is
    /// plain HTTP on this Mac.
    var secureCookie: Bool

    /// Nothing is served.
    static let closed = RemotePolicy(hosts: [], origins: [], login: nil, secureCookie: true)

    static let httpsPort = 8443

    /// Behind Tailscale Serve: `https://<node>.<tailnet>.ts.net:8443`.
    static func tailnet(dnsName: String, login: String) -> RemotePolicy {
        let name = dnsName.lowercased()
        return RemotePolicy(hosts: [name, "\(name):\(httpsPort)"], origins: ["https://\(name):\(httpsPort)"],
                            login: login, secureCookie: true)
    }

    /// `--demo remote`: loopback by number or by name, plain HTTP.
    static func demo(port: UInt16) -> RemotePolicy {
        RemotePolicy(hosts: ["127.0.0.1:\(port)", "localhost:\(port)"],
                     origins: ["http://127.0.0.1:\(port)", "http://localhost:\(port)"],
                     login: nil, secureCookie: false)
    }
}

/// Every check a request must pass before it is answered, pure. What is
/// left for the server is the token, which needs the devices.
enum RemoteCheck {
    enum Outcome: Equatable {
        /// Answer with this status; `route` is for the log, when known.
        case reject(Int, route: RemoteRoute?)
        /// Go on. `token` is the device cookie, for a route that needs one.
        case accept(RemoteRoute, token: String?)
    }

    static let cookieName = "bench_device"

    /// In this order: the Host (403; blocks DNS rebinding), Serve's
    /// identity (403), the route (404, or 405 for a known path), for a POST
    /// its type (415), Origin and `X-Bench: 1` (403) and size (413), and
    /// for `/api/*` a device cookie (401).
    static func evaluate(_ request: RemoteRequest, policy: RemotePolicy) -> Outcome {
        guard let host = request.single("host")?.lowercased(), policy.hosts.contains(host) else {
            return .reject(403, route: nil)
        }
        // Funnel would put the server on the internet. Bench never turns it
        // on, and refuses whatever comes through it.
        if request.headers["tailscale-funnel-request"] != nil { return .reject(403, route: nil) }
        if let login = policy.login {
            guard let sent = request.single("tailscale-user-login"),
                  sent.caseInsensitiveCompare(login) == .orderedSame else { return .reject(403, route: nil) }
        }

        let route: RemoteRoute
        switch RemoteRoute.match(method: request.method, path: request.path) {
        case .found(let found): route = found
        case .wrongMethod: return .reject(405, route: nil)
        case .notFound: return .reject(404, route: nil)
        }

        if route.method == "POST" {
            guard isJSON(request.single("content-type")) else { return .reject(415, route: route) }
            guard let origin = request.single("origin"), policy.origins.contains(origin) else {
                return .reject(403, route: route)
            }
            guard request.single("x-bench") == "1" else { return .reject(403, route: route) }
            guard request.body.count <= RemoteHTTP.maxBody else { return .reject(413, route: route) }
        }

        guard route.needsToken else { return .accept(route, token: nil) }
        guard let token = deviceToken(request) else { return .reject(401, route: route) }
        return .accept(route, token: token)
    }

    /// `application/json`, with or without parameters (`; charset=utf-8`).
    static func isJSON(_ contentType: String?) -> Bool {
        guard let contentType else { return false }
        let media = contentType.split(separator: ";", maxSplits: 1).first ?? ""
        return media.trimmingCharacters(in: .whitespaces).lowercased() == "application/json"
    }

    /// The `bench_device` cookie, when it is token-shaped. The first one
    /// that is wins.
    static func deviceToken(_ request: RemoteRequest) -> String? {
        for header in request.headers["cookie"] ?? [] {
            for pair in header.split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == cookieName else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if RemoteToken.isWellFormed(value) { return value }
            }
        }
        return nil
    }
}

// MARK: Responses

/// The bytes of a response, pure.
enum RemoteResponse {
    /// For HTML (DESIGN.md, Every request).
    static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
        + "connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"

    /// On every response.
    static let securityHeaders: [(String, String)] = [
        ("Cache-Control", "no-store"),
        ("X-Content-Type-Options", "nosniff"),
        ("Referrer-Policy", "no-referrer"),
        ("Cross-Origin-Resource-Policy", "same-origin"),
    ]

    static let json = "application/json; charset=utf-8"

    /// A whole response, closing the connection after it.
    static func make(status: Int, contentType: String, body: Data, headers: [(String, String)] = []) -> Data {
        var all = headers
        all.append(("Content-Type", contentType))
        all.append(("Content-Length", String(body.count)))
        all.append(("Connection", "close"))
        if contentType.hasPrefix("text/html") { all.append(("Content-Security-Policy", contentSecurityPolicy)) }
        return head(status: status, headers: all) + body
    }

    /// `{"error": "…"}` with the status.
    static func error(_ status: Int, _ reason: String? = nil, headers: [(String, String)] = []) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": reason ?? phrase(status)], options: [.sortedKeys])) ?? Data()
        return make(status: status, contentType: json, body: body, headers: headers)
    }

    /// The start of the events stream: no length, open until either end
    /// closes it.
    static func eventStreamHead() -> Data {
        head(status: 200, headers: [
            ("Content-Type", "text/event-stream; charset=utf-8"),
            ("Connection", "close"),
            ("X-Accel-Buffering", "no"),
        ])
    }

    static func head(status: Int, headers: [(String, String)]) -> Data {
        var text = "HTTP/1.1 \(status) \(phrase(status))\r\n"
        for (name, value) in securityHeaders + headers { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        return Data(text.utf8)
    }

    /// The device cookie: HttpOnly, SameSite=Strict, Path=/, Secure but in
    /// the demo, and kept for 400 days so a Home Screen app stays paired.
    static func deviceCookie(_ token: String, secure: Bool) -> (String, String) {
        ("Set-Cookie", "\(RemoteCheck.cookieName)=\(token); Path=/; Max-Age=34560000; HttpOnly; SameSite=Strict\(secure ? "; Secure" : "")")
    }

    /// Unpaired: the cookie goes.
    static func clearedCookie(secure: Bool) -> (String, String) {
        ("Set-Cookie", "\(RemoteCheck.cookieName)=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict\(secure ? "; Secure" : "")")
    }

    static func phrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 408: "Request Timeout"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        case 505: "HTTP Version Not Supported"
        default: "Status"
        }
    }

    /// Server-Sent Events: one `state` event with the snapshot.
    static func stateEvent(_ json: Data) -> Data {
        Data("event: state\ndata: ".utf8) + json + Data("\n\n".utf8)
    }

    static let keepalive = Data(": keepalive\n\n".utf8)
}

// MARK: The server

/// What the server asks of the rest of Bench, on the main actor.
struct RemoteBackend {
    /// `/api/state`'s JSON, as of now.
    var state: @MainActor () -> Data
    /// One session's JSON; nil when Bench doesn't know it.
    var session: @MainActor (String) -> Data?
    /// Opens the session on the Mac; false when Bench doesn't know it.
    var open: @MainActor (String) -> Bool
    /// Bench's version, for `/api/me`.
    var version: String
}

enum RemoteServerError: Error, Equatable {
    case noFreePort
}

@MainActor
final class RemoteServer {
    /// 47280, then the next free one up to 47290.
    nonisolated static let ports: ClosedRange<UInt16> = 47280...47290
    static let keepaliveEvery: Duration = .seconds(25)
    /// A request has this long to arrive whole.
    static let readTimeout: Duration = .seconds(10)
    static let maxConnections = 32
    static let maxStreams = 8

    var policy: RemotePolicy
    let auth: RemoteAuth
    let backend: RemoteBackend
    private(set) var port: UInt16?

    private var listener: NWListener?
    private var starting: CheckedContinuation<Bool, Never>?
    private var clients: [Int: Client] = [:]
    private var nextID = 0
    /// Icons made from the app's own, when `RemoteWebApp` has none.
    private var iconCache: [Int: Data] = [:]

    private final class Client {
        let connection: NWConnection
        var buffer = Data()
        /// Answered (or answering): nothing more is read as a request.
        var answered = false
        /// For an events stream: the device it belongs to.
        var streamDevice: String?
        var opened = Date()
        var timer: Task<Void, Never>?

        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    init(policy: RemotePolicy, auth: RemoteAuth, backend: RemoteBackend) {
        self.policy = policy
        self.auth = auth
        self.backend = backend
    }

    // MARK: Listening

    /// Listens on the first free port of `candidates`, on 127.0.0.1 only.
    func start(candidates: [UInt16]) async throws -> UInt16 {
        if let port { return port }
        for candidate in candidates where await listen(on: candidate) {
            port = candidate
            log.notice("Remote listening on loopback port \(candidate, privacy: .public)")
            return candidate
        }
        throw RemoteServerError.noFreePort
    }

    /// The remembered port first, then the range in order.
    static func candidates(remembered: Int?) -> [UInt16] {
        var list = Array(ports)
        if let remembered, let port = UInt16(exactly: remembered), ports.contains(port) {
            list.removeAll { $0 == port }
            list.insert(port, at: 0)
        }
        return list
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        for id in Array(clients.keys) { close(id) }
        log.notice("Remote stopped")
    }

    private func listen(on port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let parameters = NWParameters.tcp
        // Loopback only: never another interface.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = false
        guard let listener = try? NWListener(using: parameters) else { return false }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        let ready = await withCheckedContinuation { continuation in
            starting = continuation
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerChanged(state) }
            }
            listener.start(queue: .main)
        }
        if !ready {
            listener.cancel()
            if self.listener === listener { self.listener = nil }
        }
        return ready
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            starting?.resume(returning: true)
            starting = nil
        case .failed, .waiting:
            if let starting {
                starting.resume(returning: false)
                self.starting = nil
            } else if case .failed = state {
                log.error("Remote listener failed")
            }
        case .cancelled:
            starting?.resume(returning: false)
            starting = nil
        default:
            break
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        guard listener != nil, clients.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        nextID += 1
        let id = nextID
        let client = Client(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.forget(id)
                default: break
                }
            }
        }
        // A request that doesn't arrive whole in time is dropped.
        client.timer = Task { [weak self] in
            try? await Task.sleep(for: Self.readTimeout)
            guard !Task.isCancelled, let self, let client = self.clients[id], !client.answered else { return }
            self.send(id, RemoteResponse.error(408), route: nil, closing: true)
        }
        connection.start(queue: .main)
        receive(id)
    }

    private func receive(_ id: Int) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated { self?.received(id, data: data, isComplete: isComplete, failed: error != nil) }
        }
    }

    private func received(_ id: Int, data: Data?, isComplete: Bool, failed: Bool) {
        guard let client = clients[id] else { return }
        // An events stream reads only to hear the phone go.
        if client.streamDevice != nil {
            if isComplete || failed { close(id) } else { receive(id) }
            return
        }
        guard !client.answered else { return }
        if let data { client.buffer.append(data) }
        switch RemoteHTTP.parse(client.buffer) {
        case .incomplete:
            if isComplete || failed { close(id) } else { receive(id) }
        case .reject(let status):
            send(id, RemoteResponse.error(status), route: nil, closing: true)
        case .request(let request):
            client.answered = true
            client.timer?.cancel()
            client.buffer = Data()
            answer(request, client: id)
        }
    }

    private func answer(_ request: RemoteRequest, client id: Int) {
        switch RemoteCheck.evaluate(request, policy: policy) {
        case .reject(let status, let route):
            send(id, RemoteResponse.error(status), route: route, closing: true)
        case .accept(let route, let token):
            var device: RemoteDevice?
            if route.needsToken {
                guard let token, let found = auth.device(forToken: token) else {
                    send(id, RemoteResponse.error(401), route: route, closing: true)
                    return
                }
                auth.touch(found.id)
                device = found
            }
            respond(route, request: request, device: device, client: id)
        }
    }

    private func respond(_ route: RemoteRoute, request: RemoteRequest, device: RemoteDevice?, client id: Int) {
        let secure = policy.secureCookie
        switch route {
        case .shell, .file:
            let path = route == .shell ? "/" : route.pattern
            guard let file = RemoteWebApp.files[path] else { return send(id, RemoteResponse.error(404), route: route, closing: true) }
            send(id, RemoteResponse.make(status: 200, contentType: file.contentType, body: Data(file.body.utf8)), route: route, closing: true)
        case .icon(let size):
            guard let png = icon(size) else { return send(id, RemoteResponse.error(404), route: route, closing: true) }
            send(id, RemoteResponse.make(status: 200, contentType: "image/png", body: png), route: route, closing: true)
        case .pair:
            guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let code = body["code"] as? String, code.utf8.count <= 16 else {
                return send(id, RemoteResponse.error(400), route: route, closing: true)
            }
            let name = (body["name"] as? String).map { String($0.prefix(256)) } ?? ""
            switch auth.pair(code: code, name: name) {
            case .paired(let token, let paired):
                let json = RemoteAPI.encode(RemoteAPI.Me(paired: true, device: paired.name, bench: backend.version))
                send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: json,
                                             headers: [RemoteResponse.deviceCookie(token, secure: secure)]),
                     route: route, closing: true)
            case .refused(let why):
                let status = switch why {
                case .tooManyTries: 429
                case .storeFailed: 500
                default: 403
                }
                send(id, RemoteResponse.error(status, "\(why)"), route: route, closing: true)
            }
        case .me:
            let json = RemoteAPI.encode(RemoteAPI.Me(paired: true, device: device?.name ?? "", bench: backend.version))
            send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: json), route: route, closing: true)
        case .unpair:
            if let device {
                auth.remove(device.id)
                closeStreams(of: device.id)
            }
            let json = Data(#"{"paired":false}"#.utf8)
            send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: json,
                                         headers: [RemoteResponse.clearedCookie(secure: secure)]),
                 route: route, closing: true)
        case .state:
            send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: backend.state()), route: route, closing: true)
        case .events:
            openStream(id, device: device?.id ?? "")
        case .session(let sessionID):
            guard let json = backend.session(sessionID) else { return send(id, RemoteResponse.error(404), route: route, closing: true) }
            send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: json), route: route, closing: true)
        case .openSession(let sessionID):
            guard backend.open(sessionID) else { return send(id, RemoteResponse.error(404), route: route, closing: true) }
            send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: Data(#"{"opened":true}"#.utf8)),
                 route: route, closing: true)
        }
    }

    // MARK: Events

    private func openStream(_ id: Int, device: String) {
        guard let client = clients[id] else { return }
        // The oldest stream goes when there are too many: a phone that
        // reconnects leaves its last one behind until the drop is noticed.
        let streams = clients.filter { $0.value.streamDevice != nil }.sorted { $0.value.opened < $1.value.opened }
        if streams.count >= Self.maxStreams, let oldest = streams.first { close(oldest.key) }
        client.streamDevice = device
        log.info("/api/events 200")
        let first = RemoteResponse.eventStreamHead() + Data("retry: 5000\n\n".utf8) + RemoteResponse.stateEvent(backend.state())
        write(id, first)
        client.timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.keepaliveEvery)
                guard !Task.isCancelled else { return }
                self?.write(id, RemoteResponse.keepalive)
            }
        }
        // Reading on is how a dropped phone is noticed.
        receive(id)
    }

    /// Sends the state to every events stream.
    func broadcast(_ json: Data) {
        let event = RemoteResponse.stateEvent(json)
        for (id, client) in clients where client.streamDevice != nil { write(id, event) }
    }

    var streamCount: Int { clients.values.filter { $0.streamDevice != nil }.count }

    /// A device removed: its streams end.
    func closeStreams(of device: String) {
        for (id, client) in clients where client.streamDevice == device { close(id) }
    }

    /// Every device removed.
    func closeAllStreams() {
        for (id, client) in clients where client.streamDevice != nil { close(id) }
    }

    // MARK: Writing

    private func send(_ id: Int, _ response: Data, route: RemoteRoute?, closing: Bool) {
        guard let client = clients[id] else { return }
        client.answered = true
        client.timer?.cancel()
        log.info("\(route?.pattern ?? "-", privacy: .public) \(Self.status(of: response), privacy: .public)")
        let connection = client.connection
        connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func write(_ id: Int, _ data: Data) {
        guard let client = clients[id] else { return }
        client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            MainActor.assumeIsolated { self?.close(id) }
        })
    }

    private func close(_ id: Int) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timer?.cancel()
        client.connection.cancel()
    }

    private func forget(_ id: Int) {
        clients.removeValue(forKey: id)?.timer?.cancel()
    }

    /// The status code from a response's first line, for the log.
    private static func status(of response: Data) -> String {
        String(decoding: response.prefix(12).dropFirst(9), as: UTF8.self)
    }

    // MARK: Icons

    /// `RemoteWebApp`'s icon, else one made from the app's own icon.
    private func icon(_ size: Int) -> Data? {
        if let given = size == 180 ? RemoteWebApp.icon180 : RemoteWebApp.icon512 { return given }
        if let cached = iconCache[size] { return cached }
        guard let png = Self.png(of: NSApplication.shared.applicationIconImage, size: size) else { return nil }
        iconCache[size] = png
        return png
    }

    private static func png(of image: NSImage?, size: Int) -> Data? {
        guard let image, let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        context.flushGraphics()
        return bitmap.representation(using: .png, properties: [:])
    }
}
