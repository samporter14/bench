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
        /// The head is all here, its body (`length` bytes, declared) not
        /// yet: the request without it, so the checks that need only the head
        /// can refuse it now, before a body that may never come.
        case head(RemoteRequest, length: Int)
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
        guard length <= RemoteRoute.bodyLimit(method: method, path: target.prefix { $0 != "?" }) else { return .reject(413) } // Phase 2 actions
        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else {
            return .head(RemoteRequest(method: method, target: target, headers: headers), length: length)
        }
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
    /// Phase 2 push: `/api/push` and its POSTs (PushCenter.swift).
    case push(RemotePushRoute)
    /// `POST /api/sessions/<id>/approve|answer|message`. // Phase 2 actions
    case action(RemoteAction, String)
    /// `/api/sessions/<id>/artifacts` and `/api/files/<v>/…` (RemoteArtifacts.swift). // Phase 3 files
    case files(RemoteFilesRoute)
    // Phase 3 browse (RemoteBrowse.swift)
    /// `GET /api/projects`.
    case projects
    /// `GET /api/projects/<pid>/sessions`.
    case projectSessions(String)
    /// `POST /api/projects/<pid>/sessions`: start one.
    case newSession(String)
    /// `GET /api/sessions/<id>/history`.
    case history(String)
    /// `GET /api/sessions/<id>/turn/<i>`.
    case turn(String, Int)
    /// `GET /api/sessions/<id>/live`: the working session's text so far. // Phase 4 live
    case live(String)

    enum Match: Equatable {
        case found(RemoteRoute)
        /// The path is in the table, under another method.
        case wrongMethod
        case notFound
    }

    static let staticFiles: Set<String> = ["/app.js", "/app.css", "/manifest.webmanifest", PushServiceWorker.path] // Phase 2 push

    /// Matches the path exactly, never decoding it: `/api/sessions/<id>` only
    /// with a full frame id (`^[0-9a-f-]{36}$`).
    static func match(method: String, path: Substring) -> Match {
        guard let route = route(for: path) else { return .notFound }
        if method == "POST", case .projectSessions(let project) = route { return .found(.newSession(project)) } // Phase 3 browse
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
        if let push = RemotePushRoute(path: path) { return .push(push) } // Phase 2 push
        if let files = RemoteFilesRoute(path: path) { return .files(files) } // Phase 3 files
        if let browse = browseRoute(for: path) { return browse } // Phase 3 browse
        let prefix = "/api/sessions/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = path.dropFirst(prefix.count)
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard let id = parts.first.map(String.init), PlanCheck.isFrameID(id) else { return nil }
        switch parts.count {
        case 1: return .session(id)
        case 2 where parts[1] == "open": return .openSession(id)
        case 2 where parts[1] == "live": return .live(id) // Phase 4 live
        case 2: return RemoteAction(rawValue: String(parts[1])).map { .action($0, id) } // Phase 2 actions
        default: return nil
        }
    }

    var method: String {
        switch self {
        case .pair, .unpair, .openSession: "POST"
        case .push(let push): push.method // Phase 2 push
        case .action: "POST" // Phase 2 actions
        case .newSession: "POST" // Phase 3 browse
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
        case .push(let push): push.pattern // Phase 2 push
        case .action(let action, _): "/api/sessions/<id>/\(action.rawValue)" // Phase 2 actions
        case .files(let files): files.pattern // Phase 3 files
        // Phase 3 browse
        case .projects: "/api/projects"
        case .projectSessions, .newSession: "/api/projects/<pid>/sessions"
        case .history: "/api/sessions/<id>/history"
        case .turn: "/api/sessions/<id>/turn/<i>"
        case .live: "/api/sessions/<id>/live" // Phase 4 live
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
    /// When set, Serve's `Tailscale-User-Login` must be there and hash to it
    /// (`RemoteLogin`): Bench keeps the login only as this hash. Nil only in
    /// `--demo remote`, which Serve never fronts.
    var loginHash: String?
    /// The device cookie's `Secure` flag: off only in the demo, which is
    /// plain HTTP on this Mac.
    var secureCookie: Bool

    /// Nothing is served.
    static let closed = RemotePolicy(hosts: [], origins: [], loginHash: nil, secureCookie: true)

    static let httpsPort = 8443

    /// Behind Tailscale Serve: `https://<node>.<tailnet>.ts.net:8443`, for
    /// the login recorded (as its hash) when Remote was turned on.
    static func tailnet(dnsName: String, loginHash: String) -> RemotePolicy {
        let name = dnsName.lowercased()
        return RemotePolicy(hosts: [name, "\(name):\(httpsPort)"], origins: ["https://\(name):\(httpsPort)"],
                            loginHash: loginHash, secureCookie: true)
    }

    /// The same, from the login as Tailscale says it.
    static func tailnet(dnsName: String, login: String) -> RemotePolicy {
        tailnet(dnsName: dnsName, loginHash: RemoteLogin.hash(login))
    }

    /// `--demo remote`: loopback by number or by name, plain HTTP.
    static func demo(port: UInt16) -> RemotePolicy {
        RemotePolicy(hosts: ["127.0.0.1:\(port)", "localhost:\(port)"],
                     origins: ["http://127.0.0.1:\(port)", "http://localhost:\(port)"],
                     loginHash: nil, secureCookie: false)
    }
}

/// Every check a request must pass before it is answered, pure. What is
/// left for the server is the token, which needs the devices.
enum RemoteCheck {
    /// Which check refused: a word for the log, so a refusal can be told
    /// apart without logging anything the request carried.
    enum Gate: String, Equatable, Sendable {
        case host, funnel, login, route, method, type, origin, xbench, size, token
    }

    enum Outcome: Equatable {
        /// Answer with this status; `route` is for the log, when known.
        case reject(Int, route: RemoteRoute?, gate: Gate)
        /// Go on. `token` is the device cookie, for a route that needs one.
        case accept(RemoteRoute, token: String?)
    }

    static let cookieName = "bench_device"

    /// In this order: the Host (403; blocks DNS rebinding), Serve's
    /// identity (403), the route (404, or 405 for a known path), for a POST
    /// its type (415), Origin and `X-Bench: 1` (403) and size (413), and
    /// for `/api/*` a device cookie (401).
    ///
    /// Every one of them reads the head alone, so the server asks as soon as
    /// the head is in (`RemoteHTTP.Parse.head`, whose body is still empty)
    /// and again with the body; the parser has already held the declared
    /// length to the route's limit.
    static func evaluate(_ request: RemoteRequest, policy: RemotePolicy) -> Outcome {
        guard let host = request.single("host")?.lowercased(), policy.hosts.contains(host) else {
            return .reject(403, route: nil, gate: .host)
        }
        // Funnel would put the server on the internet. Bench never turns it
        // on, and refuses whatever comes through it.
        if request.headers["tailscale-funnel-request"] != nil { return .reject(403, route: nil, gate: .funnel) }
        if let loginHash = policy.loginHash {
            guard let sent = request.single("tailscale-user-login"),
                  RemoteLogin.matches(sent, hash: loginHash) else { return .reject(403, route: nil, gate: .login) }
        }

        let route: RemoteRoute
        switch RemoteRoute.match(method: request.method, path: request.path) {
        case .found(let found): route = found
        case .wrongMethod: return .reject(405, route: nil, gate: .method)
        case .notFound: return .reject(404, route: nil, gate: .route)
        }

        if route.method == "POST" {
            guard isJSON(request.single("content-type")) else { return .reject(415, route: route, gate: .type) }
            guard let origin = request.single("origin"), policy.origins.contains(origin) else {
                return .reject(403, route: route, gate: .origin)
            }
            guard request.single("x-bench") == "1" else { return .reject(403, route: route, gate: .xbench) }
            guard request.body.count <= route.bodyLimit else { return .reject(413, route: route, gate: .size) } // Phase 2 actions
        }

        guard route.needsToken else { return .accept(route, token: nil) }
        guard let token = deviceToken(request) else { return .reject(401, route: route, gate: .token) }
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
    /// One session's JSON; nil when Bench doesn't know it. Async since
    /// Phase 2: it may read the session through the page.
    var session: @MainActor (String) async -> Data?
    /// Opens the session on the Mac; false when Bench doesn't know it.
    var open: @MainActor (String) -> Bool
    /// Bench's version, for `/api/me`.
    var version: String
    /// An action (session id, device id, body). // Phase 2 actions
    var act: @MainActor (RemoteAction, String, String, Data) async -> RemoteActionReply = { _, _, _, _ in .notFound }
    /// A files route (the route, the request's target, device id): the whole response. // Phase 3 files
    var files: @MainActor (RemoteFilesRoute, String, String) async -> Data = { _, _, _ in RemoteResponse.error(404) }
    /// A Phase 3 browse route (the route, the request target with its query,
    /// device id, body). // Phase 3 browse
    var browse: @MainActor (RemoteRoute, String, String, Data) async -> RemoteActionReply = { _, _, _, _ in .notFound }
    /// One session's live text (the session id); nil when the phone may not open it. // Phase 4 live
    var live: @MainActor (String) async -> Data? = { _ in nil }
}

enum RemoteServerError: Error, Equatable {
    case noFreePort
}

@MainActor
final class RemoteServer {
    /// 47280, then the next free one up to 47290.
    nonisolated static let ports: ClosedRange<UInt16> = 47280...47290
    static let keepaliveEvery: Duration = .seconds(25)
    /// A request's head has this long to arrive.
    nonisolated static let readTimeout: Duration = .seconds(10)
    /// Once the head is in and has passed every check, its body has this
    /// long: a body that never comes holds a connection only briefly.
    nonisolated static let bodyTimeout: Duration = .seconds(3)
    /// A response, or one write to an events stream, has this long to be
    /// taken by the phone: a client that reads slowly can't hold its buffer.
    nonisolated static let sendTimeout: Duration = .seconds(60)
    static let maxConnections = 32

    var policy: RemotePolicy
    let auth: RemoteAuth
    let backend: RemoteBackend
    private(set) var port: UInt16?
    /// Phase 2 push: answers `/api/push*`; without it they are 404.
    var push: PushCenter?

    private var listener: NWListener?
    private var starting: CheckedContinuation<Bool, Never>?
    private var clients: [Int: Client] = [:]
    private var nextID = 0
    /// Icons drawn by `RemoteIcon`, when `RemoteWebApp` names none.
    private var iconCache: [Int: Data] = [:]
    /// What each device may still ask (RemoteBudget.swift).
    private var budgets = DeviceBudgets()
    private let now: () -> Date

    private final class Client {
        let connection: NWConnection
        var buffer = Data()
        /// Answered (or answering): nothing more is read as a request.
        var answered = false
        /// The head passed every check: the route, and its device.
        var admitted: Admitted?
        /// For an events stream: the device it belongs to.
        var streamDevice: String?
        var opened = Date()
        var timer: Task<Void, Never>?
        /// A file transfer this connection counts as, until it goes.
        var transfer: Transfer?
        /// Writes to an events stream, made and taken: one not taken within
        /// `sendTimeout` ends the stream.
        var writes = 0
        var written = 0

        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    private struct Admitted {
        let route: RemoteRoute
        let device: RemoteDevice?
    }

    /// One of a device's two file transfers. It is under way while its
    /// connection is open and while the page is still reading for it, so a
    /// phone that hangs up early can't start another read before this one ends.
    private final class Transfer {
        let device: String
        var holds = 1

        init(device: String) {
            self.device = device
        }
    }

    init(policy: RemotePolicy, auth: RemoteAuth, backend: RemoteBackend, now: @escaping () -> Date = Date.init) {
        self.policy = policy
        self.auth = auth
        self.backend = backend
        self.now = now
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
            // Only the listener being started speaks: one given up on
            // reports its cancellation later, during the next one's start.
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated {
                    guard let self, let listener, listener === self.listener else { return }
                    self.listenerChanged(state)
                }
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
        // A head that doesn't arrive in time is dropped.
        client.timer = timeout(id, after: Self.readTimeout)
        connection.start(queue: .main)
        receive(id)
    }

    /// 408 once `wait` is up, unless the request was answered by then.
    private func timeout(_ id: Int, after wait: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, let client = self.clients[id], !client.answered else { return }
            self.send(id, RemoteResponse.error(408), route: client.admitted?.route, why: "timeout", closing: true)
        }
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
        let parsed = RemoteHTTP.parse(client.buffer)
        let head: RemoteRequest
        switch parsed {
        case .incomplete:
            if isComplete || failed { close(id) } else { receive(id) }
            return
        case .reject(let status):
            return send(id, RemoteResponse.error(status), route: nil, why: "parse", closing: true)
        case .head(let request, _), .request(let request):
            head = request
        }
        // The head is in: every check runs now, before any body is waited for.
        if client.admitted == nil {
            guard let admitted = admit(head, client: id) else { return }
            client.admitted = admitted
            if case .head = parsed {
                client.timer?.cancel()
                client.timer = timeout(id, after: Self.bodyTimeout)
            }
        }
        guard case .request(let request) = parsed, let admitted = client.admitted else {
            if isComplete || failed { close(id) } else { receive(id) }
            return
        }
        client.answered = true
        client.timer?.cancel()
        client.buffer = Data()
        respond(admitted.route, request: request, device: admitted.device, client: id)
    }

    /// The checks (`RemoteCheck`), the device a route needs, and that
    /// device's budget. Nil when refused: the refusal is on its way.
    private func admit(_ request: RemoteRequest, client id: Int) -> Admitted? {
        switch RemoteCheck.evaluate(request, policy: policy) {
        case .reject(let status, let route, let gate):
            send(id, RemoteResponse.error(status), route: route, why: gate.rawValue, closing: true)
            return nil
        case .accept(let route, let token):
            guard route.needsToken else { return Admitted(route: route, device: nil) }
            guard let token, let found = auth.device(forToken: token) else {
                send(id, RemoteResponse.error(401), route: route, why: "device", closing: true)
                return nil
            }
            auth.touch(found.id)
            switch budgets.admit(route, device: found.id, at: now()) {
            case .refuse(let error, let retryAfter):
                send(id, RemoteResponse.error(429, error, headers: [("Retry-After", String(retryAfter))]),
                     route: route, why: error, closing: true)
                return nil
            case .go(let transfer):
                if transfer { clients[id]?.transfer = Transfer(device: found.id) }
            }
            return Admitted(route: route, device: found)
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
            Task { [weak self] in
                guard let self else { return }
                guard let json = await self.backend.session(sessionID) else {
                    return self.send(id, RemoteResponse.error(404), route: route, closing: true)
                }
                self.send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: json), route: route, closing: true)
            }
        case .openSession(let sessionID):
            guard backend.open(sessionID) else { return send(id, RemoteResponse.error(404), route: route, closing: true) }
            send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: Data(#"{"opened":true}"#.utf8)),
                 route: route, closing: true)
        case .push(let pushRoute): // Phase 2 push
            guard let push, let device else { return send(id, RemoteResponse.error(404), route: route, closing: true) }
            let reply = push.respond(pushRoute, body: request.body, device: device)
            send(id, RemoteResponse.make(status: reply.status, contentType: RemoteResponse.json, body: reply.json), route: route, closing: true)
        case .action(let action, let sessionID): // Phase 2 actions
            let deviceID = device?.id ?? "", body = request.body
            Task { [weak self] in
                guard let self else { return }
                let reply = await self.backend.act(action, sessionID, deviceID, body)
                self.send(id, RemoteResponse.make(status: reply.status, contentType: RemoteResponse.json, body: reply.body),
                          route: route, closing: true)
            }
        case .files(let filesRoute): // Phase 3 files
            let deviceID = device?.id ?? "", target = request.target
            // The page's read holds the transfer too, until it is done.
            let transfer = clients[id]?.transfer
            transfer?.holds += 1
            Task { [weak self] in
                guard let self else { return }
                let response = await self.backend.files(filesRoute, target, deviceID)
                self.release(transfer)
                self.send(id, response, route: route, closing: true)
            }
        case .live(let sessionID): // Phase 4 live
            Task { [weak self] in
                guard let self else { return }
                guard let json = await self.backend.live(sessionID) else {
                    return self.send(id, RemoteResponse.error(404), route: route, closing: true)
                }
                self.send(id, RemoteResponse.make(status: 200, contentType: RemoteResponse.json, body: json), route: route, closing: true)
            }
        case .projects, .projectSessions, .newSession, .history, .turn: // Phase 3 browse
            let deviceID = device?.id ?? "", target = request.target, body = request.body
            Task { [weak self] in
                guard let self else { return }
                let reply = await self.backend.browse(route, target, deviceID, body)
                self.send(id, RemoteResponse.make(status: reply.status, contentType: RemoteResponse.json, body: reply.body),
                          route: route, closing: true)
            }
        }
    }

    // MARK: Events

    private func openStream(_ id: Int, device: String) {
        guard let client = clients[id] else { return }
        // Two a device and eight in all; the oldest go (`StreamCap`).
        let streams = clients.compactMap { id, client in
            client.streamDevice.map { StreamCap.Stream(id: id, device: $0, opened: client.opened) }
        }
        for old in StreamCap.toClose(streams, for: device) { close(old) }
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

    /// `why` names the check that refused, for the log. The phone has
    /// `sendTimeout` to take the response; after that the connection goes.
    private func send(_ id: Int, _ response: Data, route: RemoteRoute?, why: String? = nil, closing: Bool) {
        guard let client = clients[id] else { return }
        client.answered = true
        client.timer?.cancel()
        log.info("\(route?.pattern ?? "-", privacy: .public) \(Self.status(of: response), privacy: .public) \(why ?? "", privacy: .public)")
        let connection = client.connection
        connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
        client.timer = Task { [weak self] in
            try? await Task.sleep(for: Self.sendTimeout)
            guard !Task.isCancelled, let self, self.clients[id] != nil else { return }
            log.info("\(route?.pattern ?? "-", privacy: .public) send timeout")
            self.close(id)
        }
    }

    /// One write to an events stream; a write the phone hasn't taken
    /// within `sendTimeout` ends the stream.
    private func write(_ id: Int, _ data: Data) {
        guard let client = clients[id] else { return }
        client.writes += 1
        let number = client.writes
        client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, let client = self.clients[id] else { return }
                guard error == nil else { return self.close(id) }
                client.written = max(client.written, number)
            }
        })
        Task { [weak self] in
            try? await Task.sleep(for: Self.sendTimeout)
            guard let self, let client = self.clients[id], client.written < number else { return }
            log.info("/api/events send timeout")
            self.close(id)
        }
    }

    private func close(_ id: Int) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timer?.cancel()
        client.connection.cancel()
        release(client.transfer)
    }

    private func forget(_ id: Int) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.timer?.cancel()
        release(client.transfer)
    }

    /// One hold on a transfer let go: the connection went, or the page's
    /// read is done. Both gone, the device may start another.
    private func release(_ transfer: Transfer?) {
        guard let transfer, transfer.holds > 0 else { return }
        transfer.holds -= 1
        if transfer.holds == 0 { budgets.finishTransfer(device: transfer.device) }
    }

    /// The status code from a response's first line, for the log.
    private static func status(of response: Data) -> String {
        String(decoding: response.prefix(12).dropFirst(9), as: UTF8.self)
    }

    // MARK: Icons

    /// `RemoteWebApp`'s icon if it names one, else the Home Screen icon drawn
    /// once from the embedded glyph (opaque, full-bleed: see `RemoteIcon`).
    private func icon(_ size: Int) -> Data? {
        if let given = size == 180 ? RemoteWebApp.icon180 : RemoteWebApp.icon512 { return given }
        if let cached = iconCache[size] { return cached }
        guard let png = RemoteIcon.png(size: size, glyph: RemoteWebApp.iconGlyph) else { return nil }
        iconCache[size] = png
        return png
    }
}
