// PushCenter.swift — push notifications to paired devices that ask for them
// (DESIGN.md, Bench on your phone → Notifications). Bench sends them itself,
// through the device's push service (Apple's, for an iPhone), encrypted so
// only that device can read them (WebPush.swift).
//
// What to send, in what words and with what headers is `PushRules`: pure and
// tested on made-up cards. `PushCenter` keeps the VAPID key, answers the
// `/api/push` routes, hears LabModel's announce moments and delivers. The
// devices' subscriptions and prefs live in their records
// (`RemoteDevice.push`); the key in a second file beside them. Tests and
// `--demo remote` keep both in memory, and the demo sends nothing.
//
// Never logged: endpoints, payloads, keys. Only a route and a status.
import CoreGraphics
import CryptoKit
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "remote")

// MARK: Stored with the device

/// A device's notifications: its subscription while it has one, and what it
/// asked for (kept when it turns them off, for the next time).
struct RemoteDevicePush: Codable, Equatable, Sendable {
    var subscription: PushSubscription?
    var prefs: PushPrefs
}

/// Where the device's push service takes pushes for it, and its keys.
struct PushSubscription: Codable, Equatable, Sendable {
    /// Checked by `WebPush.endpoint` before it was kept.
    let endpoint: String
    /// The device's P-256 public key, uncompressed (65 bytes).
    let p256dh: Data
    /// The device's auth secret (16 bytes).
    let auth: Data
    let since: Date
}

/// What a device wants to hear about (DESIGN.md, Prefs).
struct PushPrefs: Codable, Equatable, Sendable {
    var needsYou = true
    var errors = true
    var finishes = false
    /// Session titles and project names in the push; off, generic words.
    var names = false
    /// Only while the Mac isn't in use.
    var onlyAway = true
    /// The count on the phone's Home Screen icon. The service worker can't
    /// read the app's localStorage, so the Mac keeps the choice and leaves
    /// the count out of this device's pushes when it's off.
    var badge = true

    init(needsYou: Bool = true, errors: Bool = true, finishes: Bool = false, names: Bool = false, onlyAway: Bool = true,
         badge: Bool = true) {
        self.needsYou = needsYou
        self.errors = errors
        self.finishes = finishes
        self.names = names
        self.onlyAway = onlyAway
        self.badge = badge
    }

    // A key left out (an older record, or a phone sending a few) keeps its default.
    init(from decoder: any Decoder) throws {
        let patch = try PushPrefsPatch(from: decoder)
        self.init()
        patch.apply(to: &self)
    }
}

/// Some of the prefs, as a phone sends them: `true`/`false` only.
struct PushPrefsPatch: Decodable, Equatable {
    var needsYou: Bool?
    var errors: Bool?
    var finishes: Bool?
    var names: Bool?
    var onlyAway: Bool?
    var badge: Bool?

    func apply(to prefs: inout PushPrefs) {
        if let needsYou { prefs.needsYou = needsYou }
        if let errors { prefs.errors = errors }
        if let finishes { prefs.finishes = finishes }
        if let names { prefs.names = names }
        if let onlyAway { prefs.onlyAway = onlyAway }
        if let badge { prefs.badge = badge }
    }
}

// MARK: The routes

/// `/api/push` and its four POSTs (DESIGN.md, Notifications → Routes). All
/// need a paired device's token.
enum RemotePushRoute: String, CaseIterable, Equatable, Sendable {
    case status = "/api/push"
    case subscribe = "/api/push/subscribe"
    case prefs = "/api/push/prefs"
    case unsubscribe = "/api/push/unsubscribe"
    case test = "/api/push/test"

    init?(path: Substring) {
        self.init(rawValue: String(path))
    }

    var method: String { self == .status ? "GET" : "POST" }
    var pattern: String { rawValue }
}

/// The service worker the phone registers for pushes: a static file like
/// `/app.js`, served once `RemoteWebApp.files` has it.
enum PushServiceWorker {
    static let path = "/sw.js"
    static let contentType = "text/javascript; charset=utf-8"
}

// MARK: Rules

/// One push, in the words it will show.
struct PushMessage: Equatable, Sendable {
    let title: String
    let body: String
    /// `<kind>-<id>`: the phone shows one notification per tag, and Topic
    /// lets the push service replace an older one not yet delivered.
    let tag: String
    /// What a tap opens.
    let url: String
    /// `Urgency: high`, for needs you and errors; else `normal`.
    let urgent: Bool
    /// The count for the Home Screen icon (`needsYou` plus `failed`, as
    /// `/api/state` says them), when the device wants it. Nil leaves the
    /// icon as it is.
    var badge: Int? = nil

    func badged(_ count: Int?) -> PushMessage {
        var message = self
        message.badge = count
        return message
    }
}

enum PushRules {
    enum Kind: Equatable, Sendable {
        case needsYou, errors, finishes
    }

    /// Something a device may be told of, before its prefs choose the words.
    struct Event: Equatable, Sendable {
        let kind: Kind
        /// Once per device per event: the session, the kind and since when.
        let key: String
        let tag: String
        let url: String
        let namedTitle: String
        let namedBody: String
        let genericBody: String
    }

    static let genericTitle = "Claude Science"
    static let maxPayload = 1024
    static let ttl = 3600
    static let topicLength = 22
    /// Retry-After's longest wait, and the wait when it says none.
    static let maxRetryWait: TimeInterval = 10 * 60
    static let defaultRetryWait: TimeInterval = 60

    /// The same cards as `NotificationRules`: a session that needs you, one
    /// that stopped with an error, one that finished (not while a Nidus focus
    /// session holds finishes) and the "While you focused" notice that
    /// releases them. Nothing for a page's notification, a saved file or any
    /// other notice.
    static func event(for card: LabCard, holdingFinishes: Bool) -> Event? {
        switch card {
        case .needsInput(let s):
            let reason = s.waitingReason ?? .other
            return Event(kind: .needsYou, key: "needs-\(reason.rawValue)-\(s.id)-\(since(s))", tag: card.id, url: url(s.id),
                         namedTitle: s.displayTitle, namedBody: "\(reason.sentence) · \(s.projectName)",
                         genericBody: needsYouBody(reason))
        case .failed(let s):
            return Event(kind: .errors, key: "failed-\(s.id)-\(since(s))", tag: card.id, url: url(s.id),
                         namedTitle: s.displayTitle, namedBody: "Stopped with an error · \(s.projectName)",
                         genericBody: "A session stopped with an error")
        case .finished(let s):
            guard !holdingFinishes else { return nil }
            return Event(kind: .finishes, key: "finished-\(s.id)-\(since(s))", tag: card.id, url: url(s.id),
                         namedTitle: s.displayTitle, namedBody: "Finished · \(s.projectName)",
                         genericBody: "A session finished")
        case .notice(let notice):
            guard notice.isHeldFinishes else { return nil }
            if case .openSession(let s) = notice.action {
                return Event(kind: .finishes, key: "held-\(notice.id)-\(since(s))", tag: "finished-\(s.id)", url: url(s.id),
                             namedTitle: s.displayTitle, namedBody: "Finished while you focused · \(s.projectName)",
                             genericBody: "A session finished")
            }
            return Event(kind: .finishes, key: "held-\(notice.id)", tag: "finished-held", url: "/",
                         namedTitle: notice.title, namedBody: notice.detail,
                         genericBody: "Sessions finished while you focused")
        case .web, .saved:
            return nil
        }
    }

    private static func since(_ session: SessionStatus) -> Int {
        Int(session.updatedAt.timeIntervalSince1970)
    }

    /// The session's page in the phone app, for a frame id; else the app.
    static func url(_ sessionID: String) -> String {
        PlanCheck.isFrameID(sessionID) ? "/#/session/\(sessionID)" : "/"
    }

    /// Names off: what kind of thing a session waits for, never which session.
    static func needsYouBody(_ reason: WaitingReason) -> String {
        let what: String? = switch reason {
        case .plan: "plan ready for review"
        case .question: "a question to answer"
        case .web: "permission to reach the web"
        case .files: "permission to use files"
        case .delete: "permission to delete files"
        case .tool: "permission to use a connector tool"
        case .license: "a skill license to accept"
        case .other: nil
        }
        return what.map { "A session needs you: \($0)" } ?? "A session needs you"
    }

    static func wants(_ kind: Kind, _ prefs: PushPrefs) -> Bool {
        switch kind {
        case .needsYou: prefs.needsYou
        case .errors: prefs.errors
        case .finishes: prefs.finishes
        }
    }

    static func message(_ event: Event, names: Bool) -> PushMessage {
        PushMessage(title: names ? event.namedTitle : genericTitle,
                    body: names ? event.namedBody : event.genericBody,
                    tag: event.tag, url: event.url, urgent: event.kind != .finishes)
    }

    /// The test push: it says nothing about any session.
    static let test = PushMessage(title: genericTitle, body: "Notifications are on.", tag: "test", url: "/", urgent: true)

    // MARK: The wire

    /// `{"v":1,"title","body","tag","url"}` and, for a device that wants the
    /// icon's count, `"badge"`: at most 1 KB, a long title or body cut short,
    /// the body first.
    static func payload(_ message: PushMessage) -> Data {
        var title = clip(message.title, to: 120)
        var body = clip(message.body, to: 240)
        while true {
            var object: [String: Any] = ["v": 1, "title": title, "body": body, "tag": message.tag, "url": message.url]
            if let badge = message.badge { object["badge"] = max(0, badge) }
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            if data.count <= maxPayload || (title.isEmpty && body.isEmpty) { return data }
            if !body.isEmpty { body = clip(body, to: body.count - 16) } else { title = clip(title, to: title.count - 16) }
        }
    }

    /// At most `count` characters, an ellipsis ending one that was cut.
    static func clip(_ text: String, to count: Int) -> String {
        guard text.count > count else { return text }
        guard count > 1 else { return "" }
        return text.prefix(count - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// 22 characters of base64url SHA-256 of the tag: the push service keeps
    /// only the newest undelivered push per topic.
    static func topic(_ tag: String) -> String {
        String(WebPush.base64URL(Data(SHA256.hash(data: Data(tag.utf8)))).prefix(topicLength))
    }

    static func headers(_ message: PushMessage, authorization: String) -> [(String, String)] {
        [
            ("TTL", String(ttl)),
            ("Urgency", message.urgent ? "high" : "normal"),
            ("Topic", topic(message.tag)),
            ("Content-Encoding", "aes128gcm"),
            ("Content-Type", "application/octet-stream"),
            ("Authorization", authorization),
        ]
    }

    enum Failure: Error, Equatable {
        case endpoint
    }

    /// The POST to the device's push service: the payload encrypted for it,
    /// signed with Bench's VAPID key for the endpoint's origin, good for an
    /// hour.
    static func request(_ message: PushMessage, to subscription: PushSubscription, key: P256.Signing.PrivateKey, now: Date,
                        salt: Data? = nil, senderKey: P256.KeyAgreement.PrivateKey? = nil) throws -> URLRequest {
        guard let endpoint = WebPush.endpoint(subscription.endpoint), let audience = WebPush.audience(of: endpoint)
        else { throw Failure.endpoint }
        let body = try WebPush.encrypt(payload(message), receiverKey: subscription.p256dh, authSecret: subscription.auth,
                                       salt: salt, senderKey: senderKey)
        let token = try WebPush.token(audience: audience, expires: now.addingTimeInterval(WebPush.tokenLifetime), key: key)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        for (name, value) in headers(message, authorization: WebPush.authorization(token: token, publicKey: key.publicKey)) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        return request
    }

    /// What the push service's answer means.
    enum Outcome: Equatable {
        case delivered
        /// 404 or 410: the subscription is gone for good.
        case gone
        /// 429 or 5xx: once more, after this long.
        case retry(after: TimeInterval)
        /// Anything else: logged, nothing more.
        case failed
    }

    static func outcome(status: Int, retryAfter: String?, now: Date) -> Outcome {
        switch status {
        case 201: .delivered
        case 404, 410: .gone
        case 429, 500...599: .retry(after: retryWait(retryAfter, now: now))
        default: .failed
        }
    }

    /// Retry-After as seconds or an HTTP date, at most 10 minutes; a minute
    /// when it says neither.
    static func retryWait(_ header: String?, now: Date) -> TimeInterval {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return defaultRetryWait }
        if header.allSatisfy(\.isASCII), header.allSatisfy(\.isNumber) {
            return min(TimeInterval(header) ?? maxRetryWait, maxRetryWait)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return defaultRetryWait }
        return min(max(date.timeIntervalSince(now), 0), maxRetryWait)
    }
}

// MARK: Whether the Mac is in use

/// `onlyAway`'s question: is someone at the Mac? Yes while the screen is
/// unlocked and there was input in the last two minutes.
struct MacPresence: Sendable {
    static let idleLimit: TimeInterval = 2 * 60

    var secondsSinceInput: @Sendable () -> TimeInterval
    var screenLocked: @Sendable () -> Bool

    var inUse: Bool {
        !screenLocked() && secondsSinceInput() < Self.idleLimit
    }

    static let live = MacPresence(
        secondsSinceInput: {
            // kCGAnyInputEventType: keys, the mouse, the trackpad.
            guard let any = CGEventType(rawValue: ~0) else { return 0 }
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        },
        screenLocked: {
            // No login session to look at: nobody is at this Mac.
            guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
            if session["CGSSessionScreenIsLocked"] as? Bool == true { return true }
            // Another user's session is in front (fast user switching).
            return session["kCGSSessionOnConsoleKey"] as? Bool == false
        })
}

// MARK: Delivery

struct PushResponse: Equatable, Sendable {
    let status: Int
    let retryAfter: String?
}

/// How a push leaves Bench: the app's is an ephemeral `URLSession`, the
/// tests' records requests and sends nothing.
protocol PushTransport: Sendable {
    func send(_ request: URLRequest) async throws -> PushResponse
}

struct URLSessionPushTransport: PushTransport {
    /// No cookies, no cache, no credentials, as for the update check.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> PushResponse {
        let (_, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return PushResponse(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}

// MARK: The center

@MainActor
final class PushCenter {
    static let shared = PushCenter(
        auth: RemoteController.shared.auth,
        keyStore: FileDeviceStore(name: PushCenter.keyFile),
        transport: URLSessionPushTransport(),
        presence: .live,
        enabled: { RemoteController.shared.enabled },
        holdingFinishes: { NidusFocus.shared.holding },
        badge: { RemoteAPI.badge(lab: LabModel.shared) })

    /// The file beside the devices that holds the VAPID key.
    nonisolated static let keyFile = "remote-push-key.json"
    /// Events sent are remembered this long, per device.
    static let rememberSent: TimeInterval = 24 * 60 * 60

    struct Reply: Equatable {
        let status: Int
        let json: Data

        static func error(_ status: Int, _ code: String) -> Reply {
            Reply(status: status, json: Data(#"{"error":"\#(code)"}"#.utf8))
        }
    }

    let auth: RemoteAuth
    /// Nil in the demo: no key is ever made.
    private let keyStore: (any RemoteDeviceStore)?
    private let transport: any PushTransport
    private let presence: MacPresence
    private let enabled: () -> Bool
    private let holdingFinishes: () -> Bool
    /// What the icon should show: the phone's own sum, from the live lab.
    private let badge: () -> Int
    private let now: () -> Date
    private let wait: (TimeInterval) async -> Void

    private var key: P256.Signing.PrivateKey?
    /// `--demo remote`'s public key, so a browser can subscribe: new each
    /// launch, in memory only, and never sent with.
    private lazy var demoPublicKey = WebPush.base64URL(P256.Signing.PrivateKey().publicKey.x963Representation)
    private var keyLoaded = false
    /// Per device, the events already pushed and when.
    private var sent: [String: [String: Date]] = [:]
    /// Demo devices that "subscribed", whatever they sent.
    private var demoSubscribed: Set<String> = []
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private var started = false

    var isDemo: Bool { keyStore == nil }

    init(auth: RemoteAuth, keyStore: (any RemoteDeviceStore)?, transport: any PushTransport, presence: MacPresence,
         enabled: @escaping () -> Bool, holdingFinishes: @escaping () -> Bool, badge: @escaping () -> Int,
         now: @escaping () -> Date = Date.init,
         wait: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.auth = auth
        self.keyStore = keyStore
        self.transport = transport
        self.presence = presence
        self.enabled = enabled
        self.holdingFinishes = holdingFinishes
        self.badge = badge
        self.now = now
        self.wait = wait
    }

    /// `--demo remote`: no key, no network; subscribing answers as if it
    /// worked, and the test sends nothing.
    static func demo(auth: RemoteAuth) -> PushCenter {
        PushCenter(auth: auth, keyStore: nil, transport: NoTransport(), presence: MacPresence(secondsSinceInput: { 0 }, screenLocked: { false }),
                   enabled: { false }, holdingFinishes: { false }, badge: { 0 })
    }

    private struct NoTransport: PushTransport {
        func send(_ request: URLRequest) async throws -> PushResponse { throw URLError(.notConnectedToInternet) }
    }

    /// Hears LabModel's announce moments. At launch, never in a demo.
    func start() {
        guard !started, !isDemo else { return }
        started = true
        LabModel.shared.pushRaised = { [weak self] in self?.announce($0) }
    }

    // MARK: Routes

    func respond(_ route: RemotePushRoute, body: Data, device: RemoteDevice) -> Reply {
        let current = auth.devices.first { $0.id == device.id } ?? device
        switch route {
        case .status:
            return status(current)
        case .subscribe:
            return subscribe(current, body: body)
        case .prefs:
            guard let patch = Self.decode(PushPrefsPatch.self, body) else { return .error(400, "prefs") }
            var push = current.push ?? RemoteDevicePush(subscription: nil, prefs: PushPrefs())
            patch.apply(to: &push.prefs)
            // Tap after tap: in memory at once, in the file at most once a second.
            if push != current.push { auth.updatePushSoon { $0.id == current.id ? push : $0.push } }
            return status(current.id)
        case .unsubscribe:
            demoSubscribed.remove(current.id)
            if var push = current.push, push.subscription != nil {
                push.subscription = nil
                guard set(push, for: current.id) else { return .error(500, "store") }
                log.notice("A device turned notifications off")
            }
            return status(current.id)
        case .test:
            guard isSubscribed(current) else { return .error(400, "notSubscribed") }
            // Sam is at the Mac when he presses it: no onlyAway, no prefs.
            // The icon's count rides along, so a test shows what the phone will do.
            if !isDemo { deliver(PushRules.test, to: current.id, withBadge: (current.push?.prefs ?? PushPrefs()).badge) }
            return Reply(status: 200, json: Data(#"{"sent":true}"#.utf8))
        }
    }

    private func subscribe(_ device: RemoteDevice, body: Data) -> Reply {
        struct Body: Decodable {
            struct Keys: Decodable {
                let p256dh: String
                let auth: String
            }
            let endpoint: String
            let keys: Keys
            let prefs: PushPrefsPatch?
        }
        let request = Self.decode(Body.self, body)
        var prefs = device.push?.prefs ?? PushPrefs()
        request?.prefs?.apply(to: &prefs)
        let checked = request.flatMap { request -> PushSubscription? in
            guard let endpoint = WebPush.endpoint(request.endpoint), let p256dh = WebPush.receiverKey(request.keys.p256dh),
                  let secret = WebPush.authSecret(request.keys.auth) else { return nil }
            return PushSubscription(endpoint: endpoint.absoluteString, p256dh: p256dh, auth: secret, since: now())
        }
        if isDemo {
            // As if it worked, whatever came; kept in memory only.
            demoSubscribed.insert(device.id)
            _ = set(RemoteDevicePush(subscription: checked ?? device.push?.subscription, prefs: prefs), for: device.id)
            return status(device.id)
        }
        guard let request else { return .error(400, "body") }
        guard WebPush.endpoint(request.endpoint) != nil else { return .error(400, "endpoint") }
        guard let subscription = checked else { return .error(400, "keys") }
        // The key the browser subscribed with must be there to sign with.
        guard publicKey(creating: true) != nil else { return .error(500, "key") }
        // One endpoint, one device: a phone paired twice hears each push once.
        let saved = auth.updatePush { other in
            if other.id == device.id { return RemoteDevicePush(subscription: subscription, prefs: prefs) }
            guard var push = other.push, push.subscription?.endpoint == subscription.endpoint else { return other.push }
            push.subscription = nil
            return push
        }
        guard saved else { return .error(500, "store") }
        log.notice("A device turned notifications on")
        return status(device.id)
    }

    /// `{"publicKey","subscribed","prefs"}`: every route's answer but the test's.
    private func status(_ deviceID: String) -> Reply {
        guard let device = auth.devices.first(where: { $0.id == deviceID }) else { return .error(401, "device") }
        return status(device)
    }

    private func status(_ device: RemoteDevice) -> Reply {
        guard let publicKey = publicKey(creating: true) else { return .error(500, "key") }
        let prefs = device.push?.prefs ?? PushPrefs()
        let object: [String: Any] = [
            "publicKey": publicKey,
            "subscribed": isSubscribed(device),
            "prefs": ["needsYou": prefs.needsYou, "errors": prefs.errors, "finishes": prefs.finishes,
                      "names": prefs.names, "onlyAway": prefs.onlyAway, "badge": prefs.badge],
        ]
        let json = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return Reply(status: 200, json: json)
    }

    private func isSubscribed(_ device: RemoteDevice) -> Bool {
        device.push?.subscription != nil || (isDemo && demoSubscribed.contains(device.id))
    }

    private func set(_ push: RemoteDevicePush, for deviceID: String) -> Bool {
        auth.updatePush { $0.id == deviceID ? push : $0.push }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ body: Data) -> T? {
        try? JSONDecoder().decode(type, from: body)
    }

    // MARK: The key

    /// The VAPID public key, uncompressed, base64url. Made the first time a
    /// device asks: the phone needs it to subscribe.
    func publicKey(creating: Bool) -> String? {
        if isDemo { return demoPublicKey }
        return signingKey(creating: creating).map { WebPush.base64URL($0.publicKey.x963Representation) }
    }

    private struct StoredKey: Codable {
        var version = 1
        /// The private scalar, base64url.
        let key: String
    }

    private func signingKey(creating: Bool) -> P256.Signing.PrivateKey? {
        if let key { return key }
        guard let keyStore else { return nil }
        if !keyLoaded {
            do {
                if let data = try keyStore.load() {
                    guard let stored = try? JSONDecoder().decode(StoredKey.self, from: data),
                          let raw = WebPush.data(base64URL: stored.key),
                          let found = try? P256.Signing.PrivateKey(rawRepresentation: raw) else {
                        // Never replaced unseen: subscriptions made with it would all break.
                        log.error("The push key file is unreadable")
                        return nil
                    }
                    key = found
                }
                keyLoaded = true
            } catch {
                log.error("Couldn't read the push key")
                return nil
            }
        }
        if key == nil, creating {
            let made = P256.Signing.PrivateKey()
            do {
                try keyStore.save(JSONEncoder().encode(StoredKey(key: WebPush.base64URL(made.rawRepresentation))))
                key = made
                log.notice("Made the push key")
            } catch {
                log.error("Couldn't save the push key")
            }
        }
        return key
    }

    // MARK: Announcing

    /// A card came (LabModel's announce moment): each subscribed device that
    /// wants this kind hears of it once, unless it asked to only while the
    /// Mac is not in use and someone is at it.
    func announce(_ card: LabCard) {
        guard !isDemo, enabled(), let event = PushRules.event(for: card, holdingFinishes: holdingFinishes()) else { return }
        auth.load()
        let targets = auth.devices.filter { device in
            guard let push = device.push, push.subscription != nil else { return false }
            return PushRules.wants(event.kind, push.prefs)
        }
        guard !targets.isEmpty else { return }
        forgetOldSends()
        var inUse: Bool?
        for device in targets {
            guard let prefs = device.push?.prefs, sent[device.id]?[event.key] == nil else { continue }
            if prefs.onlyAway {
                let busy = inUse ?? presence.inUse
                inUse = busy
                if busy { continue }
            }
            sent[device.id, default: [:]][event.key] = now()
            deliver(PushRules.message(event, names: prefs.names), to: device.id, withBadge: prefs.badge)
        }
    }

    private func forgetOldSends() {
        let present = Set(auth.devices.map(\.id))
        let cutoff = now().addingTimeInterval(-Self.rememberSent)
        sent = sent.filter { present.contains($0.key) }.mapValues { $0.filter { $0.value > cutoff } }.filter { !$0.value.isEmpty }
    }

    // MARK: Sending

    /// `withBadge` puts the icon's count in the push. It is read when the push
    /// goes, a turn after it was decided: LabModel raises a card before it
    /// updates `waiting`, so the count read at that moment would miss the
    /// session that just began to wait.
    private func deliver(_ message: PushMessage, to deviceID: String, withBadge: Bool) {
        let id = UUID()
        inFlight[id] = Task { [weak self] in
            if let self {
                await self.send(withBadge ? message.badged(self.badge()) : message, to: deviceID, retried: false)
            }
            self?.inFlight[id] = nil
        }
    }

    /// Waits for every push under way, retries included. For tests.
    func settle() async {
        while let task = inFlight.values.first { await task.value }
    }

    private func send(_ message: PushMessage, to deviceID: String, retried: Bool) async {
        guard let subscription = auth.devices.first(where: { $0.id == deviceID })?.push?.subscription,
              let key = signingKey(creating: false) else { return }
        let request: URLRequest
        do {
            request = try PushRules.request(message, to: subscription, key: key, now: now())
        } catch {
            log.error("Couldn't make a push")
            return
        }
        let response: PushResponse
        do {
            response = try await transport.send(request)
        } catch {
            log.error("Push not sent: no answer from the push service")
            return
        }
        let status = response.status
        switch PushRules.outcome(status: status, retryAfter: response.retryAfter, now: now()) {
        case .delivered:
            log.info("Push \(status, privacy: .public)")
        case .gone:
            // Only the subscription that answered so: the device may have
            // subscribed again meanwhile.
            auth.updatePush { device in
                guard device.id == deviceID, var push = device.push, push.subscription?.endpoint == subscription.endpoint
                else { return device.push }
                push.subscription = nil
                return push
            }
            log.notice("Push \(status, privacy: .public): subscription dropped")
        case .retry(let after):
            guard !retried else {
                log.error("Push \(status, privacy: .public) again: given up")
                return
            }
            log.notice("Push \(status, privacy: .public): trying once more in \(Int(after), privacy: .public) s")
            await wait(after)
            // Not if the phone was turned off meanwhile.
            guard enabled() else { return }
            await send(message, to: deviceID, retried: true)
        case .failed:
            log.error("Push \(status, privacy: .public)")
        }
    }
}
