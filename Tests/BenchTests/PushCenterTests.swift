// PushCenterTests.swift — push notifications to paired devices, on made-up
// cards and devices: which cards push, in what words and headers, the routes,
// the key, delivery and its retries. The push service is a fake that records
// what it was sent; nothing reaches a network, and the stores are in memory.
import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import Bench

/// Records each request and answers 201, or the answers it is given in turn.
final class FakePushService: PushTransport {
    private let state: Mutex<(requests: [URLRequest], answers: [PushResponse])>

    init(answers: [PushResponse] = []) {
        state = Mutex(([], answers))
    }

    func send(_ request: URLRequest) async throws -> PushResponse {
        state.withLock { state in
            state.requests.append(request)
            return state.answers.isEmpty ? PushResponse(status: 201, retryAfter: nil) : state.answers.removeFirst()
        }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
}

/// A browser's side of a subscription: its keys, and opening what it's sent.
struct FakeBrowser {
    let key = P256.KeyAgreement.PrivateKey()
    let secret = Data((0..<16).map { UInt8($0 &* 13 &+ 5) })
    var endpoint = "https://web.push.apple.com/QGuDK9sLZm1gS2Wq_made-up"

    var subscribeBody: Data {
        Data("""
            {"endpoint":"\(endpoint)","expirationTime":null,
             "keys":{"p256dh":"\(WebPush.base64URL(key.publicKey.x963Representation))","auth":"\(WebPush.base64URL(secret))"}}
            """.utf8)
    }

    /// The JSON a push carries, decrypted as the phone would.
    func open(_ body: Data) throws -> [String: Any] {
        let salt = body.prefix(16)
        let sender = try P256.KeyAgreement.PublicKey(x963Representation: body[21..<86])
        let shared = try key.sharedSecretFromKeyAgreement(with: sender)
        let prkKey = HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: shared.withUnsafeBytes { Data($0) }), salt: secret)
        let info = Data("WebPush: info".utf8) + [0] + key.publicKey.x963Representation + sender.x963Representation
        let ikm = HKDF<SHA256>.expand(pseudoRandomKey: prkKey, info: info, outputByteCount: 32)
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: ikm, salt: Data(salt))
        let cek = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("Content-Encoding: aes128gcm".utf8) + [0], outputByteCount: 16)
        let nonce = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("Content-Encoding: nonce".utf8) + [0], outputByteCount: 12)
        let sealed = body.dropFirst(86)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce.withUnsafeBytes { Data($0) }),
                                        ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
        let plain = try AES.GCM.open(box, using: cek)
        #expect(plain.last == 0x02)
        return try #require(try JSONSerialization.jsonObject(with: plain.dropLast()) as? [String: Any])
    }
}

private enum IDs {
    static let a = "0f8fad5b-d9cb-469f-a165-70867728950e"
    static let b = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    static let c = "1b4e28ba-2fa1-11d2-883f-0016d3cca427"
}

// MARK: Rules

struct PushRulesTests {
    private let waiting = LabCard.needsInput(Fixture.session(IDs.a, .needsInput, reason: .plan, title: "Protein stability screen"))
    private let failed = LabCard.failed(Fixture.session(IDs.a, .error, title: "Protein stability screen"))
    private let finished = LabCard.finished(Fixture.session(IDs.a, .finished, title: "Protein stability screen"))

    @Test func theSameCardsAsMacNotificationsPush() {
        let everything = NotificationRules.Settings(enabled: true, authorized: true, finishes: true, showNames: true,
                                                    benchPlaysSound: true, holdingFinishes: false)
        let held = NoticeRules.held([Fixture.session(IDs.a, .finished)])!
        let otherNotice = NoticeRules.context(frameID: IDs.a, percent: 90, title: "x", announced: [])!
        let page = WebNotification(id: "n", title: "Done", body: "Finished", tag: "t", requireInteraction: false, receivedAt: Date())
        let cards: [LabCard] = [waiting, failed, finished, .notice(held), .notice(otherNotice), .web(page),
                                .saved(URL(fileURLWithPath: "/tmp/x.csv"))]
        for card in cards {
            #expect((PushRules.event(for: card, holdingFinishes: false) != nil)
                    == (NotificationRules.content(for: card, settings: everything) != nil), "\(card.id)")
        }
        #expect(PushRules.event(for: waiting, holdingFinishes: false)?.kind == .needsYou)
        #expect(PushRules.event(for: failed, holdingFinishes: false)?.kind == .errors)
        #expect(PushRules.event(for: finished, holdingFinishes: false)?.kind == .finishes)
        #expect(PushRules.event(for: .notice(held), holdingFinishes: false)?.kind == .finishes)
    }

    @Test func aFinishWaitsWhileAFocusSessionHoldsFinishes() {
        #expect(PushRules.event(for: finished, holdingFinishes: true) == nil)
        #expect(PushRules.event(for: waiting, holdingFinishes: true) != nil)
        #expect(PushRules.event(for: failed, holdingFinishes: true) != nil)
    }

    @Test func namesOnSayTheSessionItsSentenceAndProject() throws {
        let event = try #require(PushRules.event(for: waiting, holdingFinishes: false))
        let message = PushRules.message(event, names: true)
        #expect(message == PushMessage(title: "Protein stability screen", body: "Plan ready for your review · Example project",
                                       tag: "needs-\(IDs.a)", url: "/#/session/\(IDs.a)", urgent: true))
        let fail = PushRules.message(try #require(PushRules.event(for: failed, holdingFinishes: false)), names: true)
        #expect(fail.body == "Stopped with an error · Example project")
        #expect(fail.tag == "failed-\(IDs.a)")
        #expect(fail.urgent)
        let done = PushRules.message(try #require(PushRules.event(for: finished, holdingFinishes: false)), names: true)
        #expect(done.body == "Finished · Example project")
        #expect(!done.urgent)
    }

    @Test func namesOffSayNothingAboutWhichSession() throws {
        for (card, body) in [(waiting, "A session needs you: plan ready for review"),
                             (failed, "A session stopped with an error"),
                             (finished, "A session finished")] {
            let message = PushRules.message(try #require(PushRules.event(for: card, holdingFinishes: false)), names: false)
            #expect(message.title == "Claude Science")
            #expect(message.body == body)
            #expect(!message.title.contains("Protein") && !message.body.contains("Protein") && !message.body.contains("Example"))
        }
        let question = LabCard.needsInput(Fixture.session(IDs.a, .needsInput, reason: .question))
        #expect(PushRules.message(PushRules.event(for: question, holdingFinishes: false)!, names: false).body
                == "A session needs you: a question to answer")
        let other = LabCard.needsInput(Fixture.session(IDs.a, .needsInput))
        #expect(PushRules.message(PushRules.event(for: other, holdingFinishes: false)!, names: false).body == "A session needs you")
    }

    @Test func heldFinishesPushAsOneFinish() throws {
        let one = try #require(NoticeRules.held([Fixture.session(IDs.a, .finished, title: "Fit the curves")]))
        let single = try #require(PushRules.event(for: .notice(one), holdingFinishes: false))
        #expect(PushRules.message(single, names: true) == PushMessage(
            title: "Fit the curves", body: "Finished while you focused · Example project",
            tag: "finished-\(IDs.a)", url: "/#/session/\(IDs.a)", urgent: false))
        #expect(PushRules.message(single, names: false).body == "A session finished")
        let many = try #require(NoticeRules.held([Fixture.session(IDs.a, .finished, title: "Fit the curves"),
                                                   Fixture.session(IDs.b, .finished)]))
        let both = try #require(PushRules.event(for: .notice(many), holdingFinishes: false))
        #expect(PushRules.message(both, names: true) == PushMessage(
            title: "2 sessions finished", body: "Fit the curves and 1 more", tag: "finished-held", url: "/", urgent: false))
        #expect(PushRules.message(both, names: false) == PushMessage(
            title: "Claude Science", body: "Sessions finished while you focused", tag: "finished-held", url: "/", urgent: false))
    }

    @Test func anEventIsTheSessionItsKindAndSinceWhen() throws {
        let session = Fixture.session(IDs.a, .needsInput, reason: .question)
        let first = try #require(PushRules.event(for: .needsInput(session), holdingFinishes: false))
        #expect(PushRules.event(for: .needsInput(session), holdingFinishes: false)?.key == first.key)
        // The same session, asking for a plan now.
        let plan = SessionStatus(id: session.id, projectID: "p", projectName: "Example project", title: session.title,
                                 state: .needsInput, updatedAt: session.updatedAt, startedAt: session.startedAt, waitingReason: .plan)
        #expect(PushRules.event(for: .needsInput(plan), holdingFinishes: false)?.key != first.key)
        // Waiting again, later.
        let later = SessionStatus(id: session.id, projectID: "p", projectName: "Example project", title: session.title,
                                  state: .needsInput, updatedAt: session.updatedAt.addingTimeInterval(600),
                                  startedAt: session.startedAt, waitingReason: .question)
        #expect(PushRules.event(for: .needsInput(later), holdingFinishes: false)?.key != first.key)
        // Not a frame id: no session page to open.
        #expect(PushRules.url("not-a-frame") == "/")
    }

    @Test func thePayloadIsTheSpecsJSONAndAtMost1KB() throws {
        let message = PushRules.message(try #require(PushRules.event(for: waiting, holdingFinishes: false)), names: false)
        let json = String(decoding: PushRules.payload(message), as: UTF8.self)
        #expect(json == #"{"body":"A session needs you: plan ready for review","tag":"needs-\#(IDs.a)","title":"Claude Science","url":"/#/session/\#(IDs.a)","v":1}"#)

        let long = Fixture.session(IDs.a, .error, title: String(repeating: "Ångström 🧪 ", count: 200))
        for names in [true, false] {
            let event = try #require(PushRules.event(for: .failed(long), holdingFinishes: false))
            let data = PushRules.payload(PushRules.message(event, names: names))
            #expect(data.count <= 1024)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["tag"] as? String == "failed-\(IDs.a)")
            #expect(object["v"] as? Int == 1)
            if names { #expect((object["title"] as? String)?.hasSuffix("…") == true) }
        }
        let huge = PushMessage(title: String(repeating: "😀", count: 2000), body: String(repeating: "😀", count: 2000),
                               tag: "x", url: "/", urgent: false)
        #expect(PushRules.payload(huge).count <= 1024)
    }

    @Test func theBadgeIsInThePayloadOnlyWhenTheMessageHasOne() throws {
        let message = PushRules.message(try #require(PushRules.event(for: waiting, holdingFinishes: false)), names: false)
        #expect(message.badge == nil)
        #expect(!String(decoding: PushRules.payload(message), as: UTF8.self).contains("badge"))
        let json = String(decoding: PushRules.payload(message.badged(3)), as: UTF8.self)
        #expect(json == #"{"badge":3,"body":"A session needs you: plan ready for review","tag":"needs-\#(IDs.a)","title":"Claude Science","url":"/#/session/\#(IDs.a)","v":1}"#)
        // Nothing waits any more: the count is 0, which clears the icon, and is still sent.
        let zero = try #require(try JSONSerialization.jsonObject(with: PushRules.payload(message.badged(0))) as? [String: Any])
        #expect(zero["badge"] as? Int == 0)
        // A long title and body are cut, never the count.
        let huge = PushMessage(title: String(repeating: "😀", count: 2000), body: String(repeating: "😀", count: 2000),
                               tag: "x", url: "/", urgent: false, badge: 12)
        let data = PushRules.payload(huge)
        #expect(data.count <= 1024)
        #expect(try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])["badge"] as? Int == 12)
        // The test push can carry it too.
        #expect(PushRules.test.badge == nil)
        #expect(PushRules.test.badged(2).badge == 2)
    }

    @Test func prefsFromBeforeTheBadgeReadAsOn() throws {
        let old = Data(#"{"needsYou":true,"errors":false,"finishes":true,"names":true,"onlyAway":false}"#.utf8)
        let prefs = try JSONDecoder().decode(PushPrefs.self, from: old)
        #expect(prefs == PushPrefs(needsYou: true, errors: false, finishes: true, names: true, onlyAway: false, badge: true))
        // A whole device record from before, too.
        let record = Data(#"{"prefs":{"needsYou":true,"errors":true,"finishes":false,"names":false,"onlyAway":true}}"#.utf8)
        #expect(try JSONDecoder().decode(RemoteDevicePush.self, from: record).prefs.badge)
        #expect(try JSONDecoder().decode(PushPrefs.self, from: Data("{}".utf8)) == PushPrefs())
        // Off is kept.
        let off = try JSONEncoder().encode(PushPrefs(badge: false))
        #expect(try JSONDecoder().decode(PushPrefs.self, from: off).badge == false)
    }

    @Test func theTopicIs22Base64URLCharactersOfTheTagsHash() {
        let topic = PushRules.topic("needs-\(IDs.a)")
        #expect(topic.count == 22)
        #expect(topic.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(topic == PushRules.topic("needs-\(IDs.a)"))
        #expect(topic != PushRules.topic("failed-\(IDs.a)"))
        #expect(topic == String(WebPush.base64URL(Data(SHA256.hash(data: Data("needs-\(IDs.a)".utf8)))).prefix(22)))
    }

    @Test func theRequestHasTheSpecsHeadersAndOpensOnTheDevice() throws {
        let browser = FakeBrowser()
        let subscription = PushSubscription(endpoint: browser.endpoint, p256dh: browser.key.publicKey.x963Representation,
                                            auth: browser.secret, since: Date())
        let vapid = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let message = PushRules.message(try #require(PushRules.event(for: waiting, holdingFinishes: false)), names: true)
        let request = try PushRules.request(message, to: subscription, key: vapid, now: now)
        #expect(request.url?.absoluteString == browser.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "TTL") == "3600")
        #expect(request.value(forHTTPHeaderField: "Urgency") == "high")
        #expect(request.value(forHTTPHeaderField: "Topic") == PushRules.topic("needs-\(IDs.a)"))
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "aes128gcm")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!request.httpShouldHandleCookies)

        let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
        let match = try #require(authorization.wholeMatch(of: /vapid t=([^,]+), k=([A-Za-z0-9_-]+)/))
        #expect(WebPush.data(base64URL: String(match.2)) == vapid.publicKey.x963Representation)
        let parts = match.1.split(separator: ".").map(String.init)
        let claims = try #require(try JSONSerialization.jsonObject(with: WebPush.data(base64URL: parts[1])!) as? [String: Any])
        #expect(claims["aud"] as? String == "https://web.push.apple.com")
        #expect(claims["exp"] as? Int == 1_800_003_600)
        #expect(claims["sub"] as? String == "https://github.com/samporter14/bench")
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: WebPush.data(base64URL: parts[2])!)
        #expect(vapid.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))

        let payload = try browser.open(try #require(request.httpBody))
        #expect(payload["title"] as? String == "Protein stability screen")
        #expect(payload["body"] as? String == "Plan ready for your review · Example project")
        #expect(payload["url"] as? String == "/#/session/\(IDs.a)")
        let finish = PushRules.message(try #require(PushRules.event(for: finished, holdingFinishes: false)), names: true)
        #expect(try PushRules.request(finish, to: subscription, key: vapid, now: now).value(forHTTPHeaderField: "Urgency") == "normal")
    }

    @Test func aStoredEndpointIsCheckedAgainBeforeSending() {
        let subscription = PushSubscription(endpoint: "https://example.com/push", p256dh: FakeBrowser().key.publicKey.x963Representation,
                                            auth: Data(count: 16), since: Date())
        #expect(throws: PushRules.Failure.endpoint) {
            try PushRules.request(PushRules.test, to: subscription, key: P256.Signing.PrivateKey(), now: Date())
        }
    }

    @Test func whatThePushServiceSaysDecidesWhatHappens() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PushRules.outcome(status: 201, retryAfter: nil, now: now) == .delivered)
        #expect(PushRules.outcome(status: 404, retryAfter: nil, now: now) == .gone)
        #expect(PushRules.outcome(status: 410, retryAfter: nil, now: now) == .gone)
        for status in [200, 202, 400, 401, 403, 413] {
            #expect(PushRules.outcome(status: status, retryAfter: nil, now: now) == .failed)
        }
        #expect(PushRules.outcome(status: 429, retryAfter: "120", now: now) == .retry(after: 120))
        #expect(PushRules.outcome(status: 503, retryAfter: nil, now: now) == .retry(after: 60))
        #expect(PushRules.outcome(status: 500, retryAfter: "86400", now: now) == .retry(after: 600))
        #expect(PushRules.outcome(status: 502, retryAfter: "soon", now: now) == .retry(after: 60))
        let date = "Fri, 15 Jan 2027 08:01:30 GMT" // now + 90 s
        #expect(PushRules.retryWait(date, now: now) == 90)
        #expect(PushRules.retryWait("Fri, 15 Jan 2027 07:59:00 GMT", now: now) == 0)
        #expect(PushRules.retryWait("Sat, 16 Jan 2027 08:01:00 GMT", now: now) == 600)
    }

    @Test func theMacIsInUseWhileUnlockedWithRecentInput() {
        #expect(MacPresence(secondsSinceInput: { 5 }, screenLocked: { false }).inUse)
        #expect(MacPresence(secondsSinceInput: { 119 }, screenLocked: { false }).inUse)
        #expect(!MacPresence(secondsSinceInput: { 120 }, screenLocked: { false }).inUse)
        #expect(!MacPresence(secondsSinceInput: { 5 }, screenLocked: { true }).inUse)
    }
}

// MARK: The center

@MainActor
struct PushCenterTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var enabled = true
        var holding = false
        var waits: [TimeInterval] = []
        /// What the icon's count is, as the lab says it.
        var badge = 0
    }

    /// Whether someone is at the Mac, as the presence closures read it.
    private final class AtTheMac: Sendable {
        let value = Mutex(false)
    }

    private struct Setup {
        let center: PushCenter
        let auth: RemoteAuth
        let keys: MemoryDeviceStore
        let service: FakePushService
        let clock: Clock
        let atTheMac: AtTheMac
        let device: RemoteDevice
    }

    private func setup(answers: [PushResponse] = [], badge: (() -> Int)? = nil) throws -> Setup {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        guard case .paired(_, let device) = auth.pair(code: "000000", name: "Phone") else { throw CancellationError() }
        let keys = MemoryDeviceStore()
        let service = FakePushService(answers: answers)
        let clock = Clock()
        let atTheMac = AtTheMac()
        let presence = MacPresence(secondsSinceInput: { atTheMac.value.withLock { $0 } ? 3 : 600 }, screenLocked: { false })
        let center = PushCenter(auth: auth, keyStore: keys, transport: service, presence: presence,
                                enabled: { clock.enabled }, holdingFinishes: { clock.holding }, badge: badge ?? { clock.badge },
                                now: { clock.now }, wait: { clock.waits.append($0) })
        return Setup(center: center, auth: auth, keys: keys, service: service, clock: clock, atTheMac: atTheMac, device: device)
    }

    private func setInUse(_ setup: Setup, _ inUse: Bool) {
        setup.atTheMac.value.withLock { $0 = inUse }
    }

    private func json(_ reply: PushCenter.Reply) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: reply.json) as? [String: Any])
    }

    private func subscribe(_ setup: Setup, _ browser: FakeBrowser = FakeBrowser(), prefs: String? = nil) throws {
        var body = browser.subscribeBody
        if let prefs {
            var object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            object["prefs"] = try JSONSerialization.jsonObject(with: Data(prefs.utf8))
            body = try JSONSerialization.data(withJSONObject: object)
        }
        let reply = setup.center.respond(.subscribe, body: body, device: setup.device)
        #expect(reply.status == 200)
    }

    private var plan: LabCard { .needsInput(Fixture.session(IDs.a, .needsInput, reason: .plan, title: "Protein stability screen")) }

    // MARK: Routes

    @Test func askingMakesTheKeyOnceAndSaysNotSubscribed() throws {
        let s = try setup()
        #expect(s.keys.data == nil)
        let reply = s.center.respond(.status, body: Data(), device: s.device)
        #expect(reply.status == 200)
        let object = try json(reply)
        let publicKey = try #require(object["publicKey"] as? String)
        #expect(publicKey.count == 87)
        #expect(WebPush.data(base64URL: publicKey)?.first == 0x04)
        #expect(object["subscribed"] as? Bool == false)
        #expect(object["prefs"] as? [String: Bool] == ["needsYou": true, "errors": true, "finishes": false, "names": false, "onlyAway": true, "badge": true])
        let stored = try #require(s.keys.data)
        #expect(!String(decoding: stored, as: UTF8.self).contains(publicKey))
        // The same key the next time, and from the store after a relaunch.
        #expect(try json(s.center.respond(.status, body: Data(), device: s.device))["publicKey"] as? String == publicKey)
        let relaunched = PushCenter(auth: s.auth, keyStore: s.keys, transport: s.service, presence: .live,
                                    enabled: { true }, holdingFinishes: { false }, badge: { 0 })
        #expect(relaunched.publicKey(creating: false) == publicKey)
        // The devices' item is untouched by it.
        #expect(s.auth.devices.first?.push == nil)
    }

    @Test func subscribingKeepsTheSubscriptionWithTheDevice() throws {
        let s = try setup()
        let browser = FakeBrowser()
        try subscribe(s, browser, prefs: #"{"finishes":true,"names":true}"#)
        let push = try #require(s.auth.devices.first?.push)
        #expect(push.subscription?.endpoint == browser.endpoint)
        #expect(push.subscription?.p256dh == browser.key.publicKey.x963Representation)
        #expect(push.subscription?.auth == browser.secret)
        #expect(push.prefs == PushPrefs(needsYou: true, errors: true, finishes: true, names: true, onlyAway: true))
        let object = try json(s.center.respond(.status, body: Data(), device: s.device))
        #expect(object["subscribed"] as? Bool == true)
        #expect(s.keys.data != nil)
    }

    @Test func aBadSubscriptionIsRefused() throws {
        let s = try setup()
        var evil = FakeBrowser()
        evil.endpoint = "https://attacker.example.com/collect"
        #expect(s.center.respond(.subscribe, body: evil.subscribeBody, device: s.device) == .error(400, "endpoint"))
        #expect(s.center.respond(.subscribe, body: Data("nope".utf8), device: s.device) == .error(400, "body"))
        #expect(s.center.respond(.subscribe, body: Data(#"{"endpoint":"https://web.push.apple.com/x"}"#.utf8), device: s.device)
                == .error(400, "body"))
        let shortAuth = Data(#"{"endpoint":"https://web.push.apple.com/x","keys":{"p256dh":"\#(WebPush.base64URL(FakeBrowser().key.publicKey.x963Representation))","auth":"AAAA"}}"#.utf8)
        #expect(s.center.respond(.subscribe, body: shortAuth, device: s.device) == .error(400, "keys"))
        let badPoint = Data(#"{"endpoint":"https://web.push.apple.com/x","keys":{"p256dh":"\#(WebPush.base64URL(Data(repeating: 4, count: 65)))","auth":"BTBZMqHH6r4Tts7J_aSIgg"}}"#.utf8)
        #expect(s.center.respond(.subscribe, body: badPoint, device: s.device) == .error(400, "keys"))
        #expect(s.auth.devices.first?.push == nil)
    }

    @Test func oneEndpointBelongsToOneDevice() throws {
        let s = try setup()
        guard case .paired(_, let second) = s.auth.pair(code: "000000", name: "Same phone, paired again") else { return }
        let browser = FakeBrowser()
        try subscribe(s, browser)
        #expect(s.center.respond(.subscribe, body: browser.subscribeBody, device: second).status == 200)
        let byID = Dictionary(uniqueKeysWithValues: s.auth.devices.map { ($0.id, $0) })
        #expect(byID[s.device.id]?.push?.subscription == nil)
        #expect(byID[second.id]?.push?.subscription?.endpoint == browser.endpoint)
    }

    @Test func prefsChangeOnlyWhatIsSent() throws {
        let s = try setup()
        try subscribe(s)
        let reply = s.center.respond(.prefs, body: Data(#"{"onlyAway":false,"names":true}"#.utf8), device: s.device)
        #expect(reply.status == 200)
        #expect(try json(reply)["prefs"] as? [String: Bool]
                == ["needsYou": true, "errors": true, "finishes": false, "names": true, "onlyAway": false, "badge": true])
        #expect(s.center.respond(.prefs, body: Data(#"{"names":"yes"}"#.utf8), device: s.device) == .error(400, "prefs"))
        #expect(s.center.respond(.prefs, body: Data(#"{"names":1}"#.utf8), device: s.device) == .error(400, "prefs"))
        #expect(s.auth.devices.first?.push?.prefs.names == true)
    }

    @Test func unsubscribingDropsTheSubscriptionAndKeepsThePrefs() throws {
        let s = try setup()
        try subscribe(s, prefs: #"{"finishes":true}"#)
        let reply = s.center.respond(.unsubscribe, body: Data("{}".utf8), device: s.device)
        #expect(try json(reply)["subscribed"] as? Bool == false)
        #expect(s.auth.devices.first?.push == RemoteDevicePush(subscription: nil, prefs: PushPrefs(finishes: true)))
    }

    @Test func removingTheDeviceTakesItsSubscription() async throws {
        let s = try setup()
        try subscribe(s)
        s.auth.remove(s.device.id)
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.isEmpty)
    }

    @Test func aRecordFromBeforePushStillReads() throws {
        let old = Data(#"[{"id":"d1","lastSeen":"2026-10-01T10:00:00Z","name":"Sam's iPhone","pairedAt":"2026-09-30T10:00:00Z","tokenHash":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}]"#.utf8)
        // Read as of a day after it was last seen: not yet 60 days old, whatever today is.
        let then = Date(timeIntervalSince1970: 1_791_000_000)
        let auth = RemoteAuth(store: MemoryDeviceStore(data: old))
        auth.load(now: then)
        #expect(auth.devices.count == 1)
        #expect(auth.devices.first?.push == nil)
        // A device without push writes no `push` key, so older Benches read it too.
        #expect(auth.updatePush { _ in nil })
        let store = MemoryDeviceStore(data: old)
        let again = RemoteAuth(store: store)
        again.load(now: then)
        let browser = FakeBrowser()
        let push = RemoteDevicePush(subscription: PushSubscription(endpoint: browser.endpoint, p256dh: browser.key.publicKey.x963Representation,
                                                                   auth: browser.secret, since: Date(timeIntervalSince1970: 1_800_000_000)),
                                    prefs: PushPrefs(names: true))
        #expect(again.updatePush { _ in push })
        let reread = RemoteAuth(store: MemoryDeviceStore(data: store.data))
        reread.load(now: then)
        #expect(reread.devices.first?.push == push)
        #expect(reread.devices.first?.name == "Sam's iPhone")
        again.updatePush { _ in nil }
        #expect(!String(decoding: store.data ?? Data(), as: UTF8.self).contains("push"))
    }

    @Test func theTestPushIgnoresOnlyAwayAndThePrefs() async throws {
        let s = try setup()
        #expect(s.center.respond(.test, body: Data("{}".utf8), device: s.device) == .error(400, "notSubscribed"))
        let browser = FakeBrowser()
        try subscribe(s, browser, prefs: #"{"needsYou":false,"errors":false,"finishes":false,"onlyAway":true}"#)
        setInUse(s, true)
        let reply = s.center.respond(.test, body: Data("{}".utf8), device: s.device)
        #expect(reply == PushCenter.Reply(status: 200, json: Data(#"{"sent":true}"#.utf8)))
        await s.center.settle()
        let request = try #require(s.service.requests.first)
        let payload = try browser.open(try #require(request.httpBody))
        #expect(payload["body"] as? String == "Notifications are on.")
        #expect(payload["title"] as? String == "Claude Science")
    }

    @Test func theTestPushShowsTheCountUnlessThatIsOff() async throws {
        let s = try setup()
        s.clock.badge = 4
        let browser = FakeBrowser()
        try subscribe(s, browser)
        _ = s.center.respond(.test, body: Data("{}".utf8), device: s.device)
        await s.center.settle()
        #expect(try browser.open(try #require(s.service.requests.last?.httpBody))["badge"] as? Int == 4)
        _ = s.center.respond(.prefs, body: Data(#"{"badge":false}"#.utf8), device: s.device)
        _ = s.center.respond(.test, body: Data("{}".utf8), device: s.device)
        await s.center.settle()
        #expect(try browser.open(try #require(s.service.requests.last?.httpBody))["badge"] == nil)
    }

    @Test func theBadgePrefChangesWithThePrefsRoute() throws {
        let s = try setup()
        try subscribe(s)
        #expect(s.auth.devices.first?.push?.prefs.badge == true)
        let reply = s.center.respond(.prefs, body: Data(#"{"badge":false}"#.utf8), device: s.device)
        #expect(try json(reply)["prefs"] as? [String: Bool]
                == ["needsYou": true, "errors": true, "finishes": false, "names": false, "onlyAway": true, "badge": false])
        #expect(s.center.respond(.prefs, body: Data(#"{"badge":"no"}"#.utf8), device: s.device) == .error(400, "prefs"))
        // Asking for it again leaves the rest alone.
        _ = s.center.respond(.prefs, body: Data(#"{"badge":true,"names":true}"#.utf8), device: s.device)
        #expect(s.auth.devices.first?.push?.prefs == PushPrefs(names: true))
    }

    // MARK: Announcing

    @Test func aPushCarriesTheIconsCountWhenTheDeviceWantsIt() async throws {
        let s = try setup()
        s.clock.badge = 3
        let browser = FakeBrowser()
        try subscribe(s, browser)
        s.center.announce(plan)
        await s.center.settle()
        let on = try browser.open(try #require(s.service.requests.last?.httpBody))
        #expect(on["badge"] as? Int == 3)
        // Turned off on the phone: the Mac leaves it out, and the worker leaves the icon alone.
        _ = s.center.respond(.prefs, body: Data(#"{"badge":false}"#.utf8), device: s.device)
        s.center.announce(.failed(Fixture.session(IDs.b, .error)))
        await s.center.settle()
        #expect(s.service.requests.count == 2)
        let off = try browser.open(try #require(s.service.requests.last?.httpBody))
        #expect(off["badge"] == nil)
        #expect(off["tag"] as? String == "failed-\(IDs.b)")
        // And on again.
        _ = s.center.respond(.prefs, body: Data(#"{"badge":true}"#.utf8), device: s.device)
        s.clock.badge = 0
        s.center.announce(.failed(Fixture.session(IDs.a, .error)))
        await s.center.settle()
        #expect(try browser.open(try #require(s.service.requests.last?.httpBody))["badge"] as? Int == 0)
    }

    @Test func theCountIsReadWhenThePushGoesNotWhenItIsDecided() async throws {
        let s = try setup()
        let browser = FakeBrowser()
        try subscribe(s, browser)
        s.clock.badge = 1
        s.center.announce(plan)
        // LabModel raises a card before it updates what waits: the count settles after.
        s.clock.badge = 2
        await s.center.settle()
        #expect(try browser.open(try #require(s.service.requests.first?.httpBody))["badge"] as? Int == 2)
    }

    @Test func theLabsOwnCountReachesThePush() async throws {
        let lab = LabModel()
        let s = try setup(badge: { RemoteAPI.badge(lab: lab) })
        let browser = FakeBrowser()
        try subscribe(s, browser)
        lab.pushRaised = { s.center.announce($0) }
        lab.ingest(Fixture.snapshot(Fixture.session(IDs.a, .running), Fixture.session(IDs.b, .running), Fixture.session(IDs.c, .running)))
        lab.ingest(Fixture.snapshot(Fixture.session(IDs.a, .needsInput, reason: .plan), Fixture.session(IDs.b, .error),
                                    Fixture.session(IDs.c, .running)))
        await s.center.settle()
        // One session needs you and one stopped: 2, even for the push sent as the first one began to wait.
        #expect(RemoteAPI.badge(lab: lab) == 2)
        #expect(s.service.requests.count == 2)
        for request in s.service.requests {
            #expect(try browser.open(try #require(request.httpBody))["badge"] as? Int == 2)
        }
    }

    @Test func aCardThatNeedsYouPushesOncePerEvent() async throws {
        let s = try setup()
        let browser = FakeBrowser()
        try subscribe(s, browser)
        s.center.announce(plan)
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.count == 1)
        let payload = try browser.open(try #require(s.service.requests.first?.httpBody))
        #expect(payload["title"] as? String == "Claude Science")
        #expect(payload["body"] as? String == "A session needs you: plan ready for review")
        #expect(payload["tag"] as? String == "needs-\(IDs.a)")
        #expect(payload["url"] as? String == "/#/session/\(IDs.a)")
        // The same session waiting again, later, is a new event.
        let later = Fixture.session(IDs.a, .needsInput, reason: .plan)
        s.center.announce(.needsInput(SessionStatus(id: later.id, projectID: "p", projectName: "Example project", title: "",
                                                    state: .needsInput, updatedAt: later.updatedAt.addingTimeInterval(120),
                                                    startedAt: nil, waitingReason: .plan)))
        await s.center.settle()
        #expect(s.service.requests.count == 2)
    }

    @Test func namesOnPushTheSessionsWords() async throws {
        let s = try setup()
        let browser = FakeBrowser()
        try subscribe(s, browser, prefs: #"{"names":true}"#)
        s.center.announce(plan)
        await s.center.settle()
        let payload = try browser.open(try #require(s.service.requests.first?.httpBody))
        #expect(payload["title"] as? String == "Protein stability screen")
        #expect(payload["body"] as? String == "Plan ready for your review · Example project")
    }

    @Test func eachDeviceGetsWhatItsPrefsAskFor() async throws {
        let s = try setup()
        try subscribe(s) // finishes off by default
        s.center.announce(.finished(Fixture.session(IDs.a, .finished)))
        s.center.announce(.failed(Fixture.session(IDs.b, .error)))
        await s.center.settle()
        #expect(s.service.requests.map { $0.value(forHTTPHeaderField: "Topic") } == [PushRules.topic("failed-\(IDs.b)")])
        _ = s.center.respond(.prefs, body: Data(#"{"errors":false,"finishes":true}"#.utf8), device: s.device)
        s.center.announce(.failed(Fixture.session(IDs.a, .error)))
        s.center.announce(.finished(Fixture.session(IDs.a, .finished)))
        await s.center.settle()
        #expect(s.service.requests.count == 2)
        #expect(s.service.requests.last?.value(forHTTPHeaderField: "Urgency") == "normal")
    }

    @Test func onlyAwaySkipsWhileTheMacIsInUse() async throws {
        let s = try setup()
        try subscribe(s)
        setInUse(s, true)
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.isEmpty)
        // Away now: the same event, not sent before, goes.
        setInUse(s, false)
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.count == 1)
        // Asked for even while at the Mac.
        _ = s.center.respond(.prefs, body: Data(#"{"onlyAway":false}"#.utf8), device: s.device)
        setInUse(s, true)
        s.center.announce(.failed(Fixture.session(IDs.b, .error)))
        await s.center.settle()
        #expect(s.service.requests.count == 2)
    }

    @Test func nothingIsPushedWhileThePhoneIsOffOrInTheDemo() async throws {
        let s = try setup()
        try subscribe(s)
        s.clock.enabled = false
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.isEmpty)
    }

    @Test func aHeldFinishPushesWhenItIsReleased() async throws {
        let s = try setup()
        let browser = FakeBrowser()
        try subscribe(s, browser, prefs: #"{"finishes":true,"names":true}"#)
        let model = LabModel()
        model.lifetimeScale = 0.01
        var focusing = true
        model.holdsFinishes = { focusing }
        model.isFocusing = { focusing }
        model.pushRaised = { s.center.announce($0) }
        s.clock.holding = true
        model.ingest(Fixture.snapshot(Fixture.session(IDs.a, .running, title: "Fit the curves")))
        model.ingest(Fixture.snapshot(Fixture.session(IDs.a, .finished, title: "Fit the curves")))
        await s.center.settle()
        #expect(s.service.requests.isEmpty)
        focusing = false
        s.clock.holding = false
        model.focusEnded()
        await s.center.settle()
        #expect(s.service.requests.count == 1)
        let payload = try browser.open(try #require(s.service.requests.first?.httpBody))
        #expect(payload["title"] as? String == "Fit the curves")
        #expect(payload["body"] as? String == "Finished while you focused · Example project")
    }

    @Test func theModelPushesAtTheSameMomentsItNotifies() {
        let model = LabModel()
        model.lifetimeScale = 0.01
        model.holdsFinishes = { false }
        model.isFocusing = { false }
        var raised: [String] = [], pushed: [String] = []
        model.cardRaised = { raised.append($0.id) }
        model.pushRaised = { pushed.append($0.id) }
        // What waits at launch is no news.
        model.ingest(Fixture.snapshot(Fixture.session("w", .needsInput, reason: .question), Fixture.session("a", .running)))
        model.ingest(Fixture.snapshot(Fixture.session("w", .needsInput, reason: .question), Fixture.session("a", .needsInput, reason: .question)))
        model.ingest(Fixture.snapshot(Fixture.session("w", .needsInput, reason: .question), Fixture.session("a", .needsInput, reason: .plan)))
        #expect(raised == ["needs-a", "needs-a"])
        #expect(pushed == raised)
    }

    // MARK: Delivery

    @Test func goneDropsTheSubscription() async throws {
        for status in [404, 410] {
            let s = try setup(answers: [PushResponse(status: status, retryAfter: nil)])
            try subscribe(s)
            s.center.announce(plan)
            await s.center.settle()
            #expect(s.service.requests.count == 1)
            #expect(s.auth.devices.first?.push?.subscription == nil)
            #expect(s.auth.devices.first?.push?.prefs == PushPrefs())
        }
    }

    @Test func busyIsTriedOnceMoreAfterRetryAfter() async throws {
        let s = try setup(answers: [PushResponse(status: 429, retryAfter: "30"), PushResponse(status: 201, retryAfter: nil)])
        try subscribe(s)
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.count == 2)
        #expect(s.clock.waits == [30])
        // Each try is sealed afresh.
        #expect(s.service.requests[0].httpBody != s.service.requests[1].httpBody)
    }

    @Test func busyTwiceIsGivenUpAndTheWaitIsCapped() async throws {
        let s = try setup(answers: [PushResponse(status: 503, retryAfter: "3600"), PushResponse(status: 503, retryAfter: nil),
                                    PushResponse(status: 201, retryAfter: nil)])
        try subscribe(s)
        s.center.announce(plan)
        await s.center.settle()
        #expect(s.service.requests.count == 2)
        #expect(s.clock.waits == [600])
        #expect(s.auth.devices.first?.push?.subscription != nil)
    }

    @Test func otherAnswersAreOnlyLogged() async throws {
        let s = try setup(answers: [PushResponse(status: 413, retryAfter: nil), PushResponse(status: 400, retryAfter: nil)])
        try subscribe(s)
        s.center.announce(plan)
        s.center.announce(.failed(Fixture.session(IDs.b, .error)))
        await s.center.settle()
        #expect(s.service.requests.count == 2)
        #expect(s.clock.waits.isEmpty)
        #expect(s.auth.devices.first?.push?.subscription != nil)
    }

    // MARK: The demo

    @Test func theDemoMakesNoKeyAndSendsNothing() async throws {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        guard case .paired(_, let device) = auth.pair(code: "000000", name: "Phone") else { return }
        let demo = PushCenter.demo(auth: auth)
        let status = try json(demo.respond(.status, body: Data(), device: device))
        // A key a browser can subscribe with, kept nowhere.
        let publicKey = try #require(status["publicKey"] as? String)
        #expect(WebPush.receiverKey(publicKey) != nil)
        #expect(demo.publicKey(creating: true) == publicKey)
        #expect(status["subscribed"] as? Bool == false)
        // As if subscribed, whatever was sent.
        let reply = demo.respond(.subscribe, body: Data("{}".utf8), device: device)
        #expect(try json(reply)["subscribed"] as? Bool == true)
        #expect(demo.respond(.test, body: Data(), device: device) == PushCenter.Reply(status: 200, json: Data(#"{"sent":true}"#.utf8)))
        demo.announce(plan)
        await demo.settle()
        #expect(try json(demo.respond(.unsubscribe, body: Data(), device: device))["subscribed"] as? Bool == false)
    }
}

// MARK: The route table

struct PushRouteTests {
    @Test func thePushRoutesAreInTheTableAndNeedAToken() {
        #expect(RemoteRoute.match(method: "GET", path: "/api/push") == .found(.push(.status)))
        for route in [RemotePushRoute.subscribe, .prefs, .unsubscribe, .test] {
            #expect(RemoteRoute.match(method: "POST", path: Substring(route.rawValue)) == .found(.push(route)))
            #expect(RemoteRoute.match(method: "GET", path: Substring(route.rawValue)) == .wrongMethod)
            #expect(RemoteRoute.push(route).method == "POST")
        }
        #expect(RemoteRoute.match(method: "POST", path: "/api/push") == .wrongMethod)
        #expect(RemoteRoute.match(method: "GET", path: "/api/push/") == .notFound)
        #expect(RemoteRoute.match(method: "POST", path: "/api/push/subscribe/x") == .notFound)
        #expect(RemoteRoute.match(method: "POST", path: "/api/PUSH/test") == .notFound)
        for route in RemotePushRoute.allCases {
            #expect(RemoteRoute.push(route).needsToken)
            #expect(RemoteRoute.push(route).pattern == route.rawValue)
        }
    }

    @Test func pushRoutesPassTheSameChecksAsEveryPOST() {
        let host = "studio-mac.example-tailnet.ts.net"
        let policy = RemotePolicy.tailnet(dnsName: host, login: "pat@example.com")
        var headers: [String: [String]] = [
            "host": ["\(host):8443"], "tailscale-user-login": ["pat@example.com"],
            "cookie": ["bench_device=\(String(repeating: "A", count: 43))"],
            "content-type": ["application/json"], "origin": ["https://\(host):8443"], "x-bench": ["1"],
        ]
        let request = { RemoteRequest(method: "POST", target: "/api/push/subscribe", headers: headers, body: Data("{}".utf8)) }
        #expect(RemoteCheck.evaluate(request(), policy: policy) == .accept(.push(.subscribe), token: String(repeating: "A", count: 43)))
        headers["x-bench"] = nil
        #expect(RemoteCheck.evaluate(request(), policy: policy) == .reject(403, route: .push(.subscribe), gate: .xbench))
        headers["x-bench"] = ["1"]
        headers["cookie"] = nil
        #expect(RemoteCheck.evaluate(request(), policy: policy) == .reject(401, route: .push(.subscribe), gate: .token))
    }

    @Test func theServiceWorkerIsAStaticFileWithoutAToken() {
        #expect(RemoteRoute.match(method: "GET", path: "/sw.js") == .found(.file("/sw.js")))
        #expect(!RemoteRoute.file("/sw.js").needsToken)
        // Served as JavaScript once the phone app has it.
        if let file = RemoteWebApp.files[PushServiceWorker.path] {
            #expect(file.contentType == PushServiceWorker.contentType)
        }
        #expect(PushServiceWorker.contentType == "text/javascript; charset=utf-8")
    }
}
