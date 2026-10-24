// AskModelClientTests.swift — the requests Ask Another Model makes (AskModel/
// AnotherModelClient.swift), against a fake `URLProtocol`: `GET /models` and
// `POST /chat/completions`, their shape and their one header, the key nowhere
// else, every failure as its sentence, the deadline, Cancel, and a redirect
// that is refused before the key could follow it. Made-up hosts (each test its
// own) and a made-up key; nothing leaves the process.
import Foundation
import Synchronization
import Testing
@testable import Bench

// MARK: The fake

/// Answers a request by its host, from a table each test fills for its own
/// made-up host, and remembers what it was asked.
final class FakeModelProtocol: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        /// A status and a body.
        case reply(Int, String)
        /// A failure before any answer.
        case fail(URLError.Code)
        /// Nothing, ever: only a deadline or Cancel ends it.
        case never
        /// A 302 to another address.
        case redirect(String)
    }

    struct Seen: Sendable {
        var requests: [URLRequest] = []
        var bodies: [Data] = []
        var stops = 0
    }

    private struct Entry: Sendable {
        let answer: @Sendable (URLRequest) -> Answer
        var seen = Seen()
    }

    private static let table = Mutex<[String: Entry]>([:])

    /// A host of its own for a test, answered by `answer`; or `named`, for a
    /// capture that shows the address's real name (nothing reaches it: the
    /// session only has this protocol).
    static func host(named: String? = nil, _ answer: @escaping @Sendable (URLRequest) -> Answer) -> String {
        let host = named ?? "t-\(UUID().uuidString.lowercased()).example"
        table.withLock { $0[host] = Entry(answer: answer) }
        return host
    }

    static func seen(_ host: String) -> Seen {
        table.withLock { $0[host]?.seen ?? Seen() }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = AnotherModelClient.configuration()
        configuration.protocolClasses = [FakeModelProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = request
        let host = request.url?.host() ?? ""
        let body = Self.body(of: request)
        let answer: Answer? = Self.table.withLock { table in
            guard var entry = table[host] else { return nil }
            entry.seen.requests.append(request)
            entry.seen.bodies.append(body)
            table[host] = entry
            return entry.answer(request)
        }
        guard let client, let url = request.url else { return }
        switch answer {
        case nil:
            client.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        case .reply(let status, let text)?:
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(text.utf8))
            client.urlProtocolDidFinishLoading(self)
        case .fail(let code)?:
            client.urlProtocol(self, didFailWithError: URLError(code))
        case .never?:
            break
        case .redirect(let target)?:
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target])!
            var next = request
            next.url = URL(string: target)
            client.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        let host = request.url?.host() ?? ""
        Self.table.withLock { table in table[host]?.seen.stops += 1 }
    }

    /// A POST's body: URLSession hands a protocol the body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A made-up key: printable, no spaces, as a real one is.
let madeUpModelKey = "sk-made-up-0123456789abcdef"

@MainActor
private func client(wait: @escaping @MainActor (Duration) async -> Void = WriteDeadline.sleep) -> AnotherModelClient {
    AnotherModelClient(configuration: FakeModelProtocol.configuration(), wait: wait)
}

private func address(_ host: String) -> URL { URL(string: "https://\(host)/v1")! }

private let answerJSON = #"{"id":"chatcmpl-1","choices":[{"index":0,"message":{"role":"assistant","content":"Use **HEPES** at 25 mM."}}]}"#

// MARK: The requests

@MainActor
struct AskModelRequestTests {
    @Test func theListIsAGetToModelsWithTheKeyInTheAuthorizationHeaderOnly() async throws {
        let host = FakeModelProtocol.host { _ in .reply(200, #"{"object":"list","data":[{"id":"abliterated-model"},{"id":"abliterated-model-large"}]}"#) }
        let result = await client().models(address: address(host), key: madeUpModelKey)
        #expect(result == .success(["abliterated-model", "abliterated-model-large"]))
        let seen = FakeModelProtocol.seen(host)
        let request = try #require(seen.requests.first)
        #expect(seen.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://\(host)/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(madeUpModelKey)")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        // The key is in that header and nowhere else: not the address, not another header.
        #expect(request.url?.absoluteString.contains(madeUpModelKey) == false)
        let others = (request.allHTTPHeaderFields ?? [:]).filter { $0.key != "Authorization" }
        #expect(!others.values.contains { $0.contains(madeUpModelKey) })
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func anAskIsAPostOfTheModelAndTheTurnsAndNothingMore() async throws {
        let host = FakeModelProtocol.host { _ in .reply(200, answerJSON) }
        let turns = [ChatTurn(role: .user, text: "Plate reader QC: which wells failed?"),
                     ChatTurn(role: .assistant, text: "Wells A3 and B7."),
                     ChatTurn(role: .user, text: "Which buffer should the rerun use?")]
        let result = await client().ask(address: address(host), key: madeUpModelKey, model: "abliteration-ai/abliterated-model",
                                        turns: turns)
        #expect(result == .success("Use **HEPES** at 25 mM."))
        let seen = FakeModelProtocol.seen(host)
        let request = try #require(seen.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://\(host)/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(madeUpModelKey)")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(seen.bodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["model", "messages", "stream"])
        #expect(json["model"] as? String == "abliteration-ai/abliterated-model")
        #expect(json["stream"] as? Bool == false)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "Plate reader QC: which wells failed?"],
                             ["role": "assistant", "content": "Wells A3 and B7."],
                             ["role": "user", "content": "Which buffer should the rerun use?"]])
        // The key is never in the body.
        #expect(String(decoding: body, as: UTF8.self).contains(madeUpModelKey) == false)
    }

    @Test func theAddressCarriesItsOwnPathAndNoTrailingSlash() {
        #expect(AnotherModelAddress.url("https://api.abliteration.ai/v1/")?.absoluteString == "https://api.abliteration.ai/v1")
        #expect(AnotherModelAddress.url("  https://api.abliteration.ai/v1  ")?.absoluteString == "https://api.abliteration.ai/v1")
        let request = AnotherModelClient.listRequest(address: AnotherModelAddress.url(AnotherModelAddress.usual)!,
                                                     key: madeUpModelKey, limit: .seconds(20))
        #expect(request.url?.absoluteString == "https://api.abliteration.ai/v1/models")
        #expect(request.timeoutInterval == 20)
        #expect(AnotherModelAddress.host(AnotherModelAddress.usual) == "api.abliteration.ai")
    }

    @Test func onlyAnHttpsAddressWithAHostAndNothingElseIsTaken() {
        for refused in ["http://api.abliteration.ai/v1", "api.abliteration.ai/v1", "https://", "https:///v1",
                        "https://user:secret@api.abliteration.ai/v1", "https://api.abliteration.ai/v1?key=x",
                        "https://api.abliteration.ai/v1#part", "ftp://api.abliteration.ai", "",
                        "https://" + String(repeating: "a", count: 300) + ".example"] {
            #expect(AnotherModelAddress.url(refused) == nil, "\(refused)")
        }
        #expect(AnotherModelAddress.url("HTTPS://api.abliteration.ai/v1") != nil)
    }

    @Test func aKeyIsTrimmedAndMustBeOneHeaderLine() {
        #expect(AnotherModelKey.cleaned("  \(madeUpModelKey)\n") == madeUpModelKey)
        for refused in ["", "short", "sk made up with spaces", "sk-made-up\nX-Other: 1", "sk-made-up-\u{00E9}\u{00E9}\u{00E9}",
                        String(repeating: "k", count: 513)] {
            #expect(AnotherModelKey.cleaned(refused) == nil, "\(refused)")
        }
    }

    @Test func theSessionKeepsNoCookiesNoCacheAndNoCredentials() {
        let configuration = AnotherModelClient.configuration()
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.waitsForConnectivity == false)
    }
}

// MARK: Reading the answers

struct AskModelAnswerReadingTests {
    private func names(_ json: String) -> [String]? { AnotherModelClient.modelNames(in: Data(json.utf8)) }

    @Test func aListIsReadInItsOrderEachNameOnce() {
        #expect(names(#"{"data":[{"id":"abliterated-model"},{"id":"abliterated-model"},{"id":" abliterated-model-large "}]}"#)
            == ["abliterated-model", "abliterated-model-large"])
        #expect(names(#"{"models":[{"name":"abliteration-ai/abliterated-model"}]}"#) == ["abliteration-ai/abliterated-model"])
        #expect(names(#"["abliterated-model", {"id": "abliterated-model-large"}, 7, {"other": 1}]"#)
            == ["abliterated-model", "abliterated-model-large"])
        #expect(names(#"{"data":[]}"#) == [])
        // A name with a control character, or too long, is left out.
        #expect(names(#"{"data":[{"id":"bad\u0007name"},{"id":"ok"}]}"#) == ["ok"])
        #expect(names(#"{"data":[{"id":"\#(String(repeating: "m", count: 201))"}]}"#) == [])
    }

    @Test func aBodyThatIsNoListIsUnreadable() {
        #expect(names("not json") == nil)
        #expect(names(#"{"error":"nope"}"#) == nil)
        #expect(names("7") == nil)
    }

    @Test func anAnswerIsTheFirstChoicesText() {
        func answer(_ json: String) -> String? { AnotherModelClient.answer(in: Data(json.utf8)) }
        #expect(answer(answerJSON) == "Use **HEPES** at 25 mM.")
        #expect(answer(#"{"choices":[{"message":{"content":[{"type":"text","text":"Part one. "},{"type":"image_url"},{"type":"text","text":"Part two."}]}}]}"#)
            == "Part one. Part two.")
        #expect(answer(#"{"choices":[{"message":{"content":"   "}}]}"#) == nil)
        #expect(answer(#"{"choices":[]}"#) == nil)
        #expect(answer(#"{"choices":[{"message":{"content":null}}]}"#) == nil)
        #expect(answer("{}") == nil)
    }
}

// MARK: Failures

@MainActor
struct AskModelFailureTests {
    private let turns = [ChatTurn(role: .user, text: "Which buffer?")]

    private func ask(_ answer: FakeModelProtocol.Answer) async -> Result<String, AnotherModelFailure> {
        let host = FakeModelProtocol.host { _ in answer }
        return await client().ask(address: address(host), key: madeUpModelKey, model: "abliterated-model", turns: turns)
    }

    @Test func aRefusedKeyIsSaidAsSuch() async {
        #expect(await ask(.reply(401, #"{"error":{"message":"bad key"}}"#)) == .failure(.keyRefused))
        #expect(await ask(.reply(403, "{}")) == .failure(.keyRefused))
        #expect(AnotherModelFailure.keyRefused.sentence(host: "api.abliteration.ai", limit: .seconds(120))
            == "api.abliteration.ai didn\u{2019}t accept your key. Check it in Settings \u{2192} General.")
    }

    @Test func inSettingsTheSentencesDontSendYouToSettings() {
        let host = "api.abliteration.ai"
        let kinds: [AnotherModelFailure] = [.keyRefused, .tooMany, .timedOut, .offline, .unreachable, .status(500), .unreadable,
                                            .notSet(.address)]
        for failure in kinds {
            let sentence = failure.sentence(host: host, limit: .seconds(20), inSettings: true)
            #expect(!sentence.contains("Settings"), "\(failure): \(sentence)")
            #expect(sentence.hasSuffix("."))
        }
        // Where the window says it, it names Settings.
        #expect(AnotherModelFailure.keyRefused.sentence(host: host, limit: .seconds(20)).contains("Settings"))
    }

    @Test func tooManyRequestsIsItsOwnSentence() async {
        #expect(await ask(.reply(429, "{}")) == .failure(.tooMany))
        #expect(AnotherModelFailure.tooMany.sentence(host: "api.abliteration.ai", limit: .seconds(120))
            == "Too many requests to api.abliteration.ai just now. Wait a minute, then ask again.")
    }

    @Test func noNetworkAndAnUnreachableHostAreToldApart() async {
        #expect(await ask(.fail(.notConnectedToInternet)) == .failure(.offline))
        #expect(await ask(.fail(.networkConnectionLost)) == .failure(.offline))
        #expect(await ask(.fail(.cannotFindHost)) == .failure(.unreachable))
        #expect(await ask(.fail(.cannotConnectToHost)) == .failure(.unreachable))
        #expect(await ask(.fail(.secureConnectionFailed)) == .failure(.unreachable))
        #expect(AnotherModelFailure.offline.sentence(host: "x", limit: .seconds(1)) == "This Mac isn\u{2019}t connected to the internet.")
    }

    @Test func anythingElseSaysItsStatus() async {
        #expect(await ask(.reply(500, "<html>oops</html>")) == .failure(.status(500)))
        #expect(await ask(.reply(404, "{}")) == .failure(.status(404)))
        #expect(await ask(.reply(200, "not json")) == .failure(.unreadable))
        #expect(await ask(.reply(200, #"{"choices":[{"message":{"content":""}}]}"#)) == .failure(.unreadable))
        #expect(AnotherModelFailure.status(500).sentence(host: "api.abliteration.ai", limit: .seconds(120))
            == "api.abliteration.ai answered with an error (500). Try again in a moment.")
        #expect(AnotherModelClient.result(status: 200, data: Data(count: AnotherModelClient.maxBody + 1)) == .failure(.unreadable))
    }

    @Test func aRedirectIsRefusedAndTheKeyNeverReachesTheOtherHost() async {
        let other = FakeModelProtocol.host { _ in .reply(200, answerJSON) }
        let host = FakeModelProtocol.host { _ in .redirect("https://\(other)/v1/chat/completions") }
        let result = await client().ask(address: address(host), key: madeUpModelKey, model: "abliterated-model", turns: turns)
        #expect(result == .failure(.status(302)))
        #expect(FakeModelProtocol.seen(other).requests.isEmpty)
    }

    @Test func theDeadlineEndsAnAskThatNeverAnswersAndStopsTheRequest() async {
        let clock = ManualClock()
        let host = FakeModelProtocol.host { _ in .never }
        let task = Task { @MainActor in
            await client(wait: { await clock.wait($0) }).ask(address: address(host), key: madeUpModelKey,
                                                             model: "abliterated-model", turns: turns)
        }
        await clock.until(waiting: 1, AnotherModelClient.askLimit)
        #expect(clock.waiting(.seconds(120)) == 1)
        clock.fire()
        #expect(await task.value == .failure(.timedOut))
        // The request itself was ended, not left to run.
        for _ in 0..<200 where FakeModelProtocol.seen(host).stops == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(FakeModelProtocol.seen(host).stops == 1)
        #expect(AnotherModelFailure.timedOut.sentence(host: host, limit: .seconds(120))
            == "No answer came within 2 minutes. Ask again, or ask something shorter.")
    }

    @Test func theListHasItsOwnShorterDeadline() async {
        let clock = ManualClock()
        let host = FakeModelProtocol.host { _ in .never }
        let task = Task { @MainActor in
            await client(wait: { await clock.wait($0) }).models(address: address(host), key: madeUpModelKey)
        }
        await clock.until(waiting: 1)
        #expect(clock.waiting(.seconds(20)) == 1)
        clock.fire()
        #expect(await task.value == .failure(.timedOut))
    }

    @Test func cancelEndsTheAskAtOnceAndStopsTheRequest() async {
        let clock = ManualClock()
        let host = FakeModelProtocol.host { _ in .never }
        let task = Task { @MainActor in
            await client(wait: { await clock.wait($0) }).ask(address: address(host), key: madeUpModelKey,
                                                             model: "abliterated-model", turns: turns)
        }
        await clock.until(waiting: 1)
        for _ in 0..<200 where FakeModelProtocol.seen(host).requests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
        for _ in 0..<200 where FakeModelProtocol.seen(host).stops == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(FakeModelProtocol.seen(host).stops == 1)
        // Asked once: nothing is tried again on its own.
        #expect(FakeModelProtocol.seen(host).requests.count == 1)
    }

    @Test func aFailureIsAskedOnceAndNeverAgainOnItsOwn() async {
        let host = FakeModelProtocol.host { _ in .reply(503, "{}") }
        _ = await client().ask(address: address(host), key: madeUpModelKey, model: "abliterated-model", turns: turns)
        #expect(FakeModelProtocol.seen(host).requests.count == 1)
    }

    @Test func theDeadlineReadsAsWords() {
        #expect(AnotherModelFailure.words(.seconds(120)) == "2 minutes")
        #expect(AnotherModelFailure.words(.seconds(60)) == "a minute")
        #expect(AnotherModelFailure.words(.seconds(20)) == "20 seconds")
    }

    @Test func everyFailureHasAPlainSentenceAndAFixedWord() {
        let all: [AnotherModelFailure] = [.keyRefused, .tooMany, .timedOut, .offline, .unreachable, .cancelled, .status(502),
                                          .unreadable, .notSet(.switchedOff), .notSet(.key), .notSet(.model), .notSet(.address)]
        for failure in all {
            let sentence = failure.sentence(host: "api.abliteration.ai", limit: .seconds(120))
            #expect(sentence.hasSuffix("."), "\(failure)")
            #expect(!failure.word.isEmpty)
            #expect(!failure.word.contains("api."), "a log word names no host")
        }
    }
}
