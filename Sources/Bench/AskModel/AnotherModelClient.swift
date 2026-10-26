// AnotherModelClient.swift — the one way Capsid talks to another model
// (DESIGN.md, Ask another model): an OpenAI-compatible API at the address in
// Settings (Abliteration.ai's by default), with the user's own key. Two
// requests, `GET /models` and `POST /chat/completions`, over an ephemeral
// URLSession that keeps no cookies, no cache and no credentials, and follows
// no redirect: a redirect could carry the key to another host. The key goes in
// the Authorization header of a request to that address and nowhere else.
//
// The list has a deadline (20 seconds). An answer is streamed (`"stream": true`,
// AnotherModelStream.swift): two minutes for the first chunk, a minute with none
// after that, ten minutes in all; a server that ignores `stream` and answers
// JSON is read whole, as it was. Cancel ends either at once, keeping the words
// that came; nothing is ever tried again on its own. A failure is one plain
// sentence (`AnotherModelFailure.sentence`). Nothing here logs: the callers log
// fixed words and counts (AnotherModel.swift).
import Foundation

// MARK: The address and the key

/// Where another model is asked: an https address with a host, and no user,
/// password, query or fragment, since the key is sent to it.
enum AnotherModelAddress {
    /// Abliteration.ai's OpenAI-compatible API.
    static let usual = "https://api.abliteration.ai/v1"
    static let maxLength = 300

    /// The address as a URL with no slash at its end (the requests add their
    /// own path), or nil when it isn't one Capsid sends a key to.
    static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maxLength, var parts = URLComponents(string: trimmed),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        parts.scheme = "https"
        while parts.path.hasSuffix("/") { parts.path = String(parts.path.dropLast()) }
        return parts.url
    }

    /// The address's host, for the sentences: "api.abliteration.ai".
    static func host(_ text: String) -> String? {
        url(text)?.host()
    }
}

/// The user's key, as Capsid takes it: pasted by the user, never typed in by
/// Capsid, kept in a file only the user can read (`AnotherModel`), never in
/// the Keychain, the settings or the log.
enum AnotherModelKey {
    /// The file under `~/Library/Application Support/Bench` (`FileDeviceStore`):
    /// folder 0700, file 0600.
    static let fileName = "another-model-key"

    /// A key as pasted, with the white space at its ends taken off; nil when
    /// what is left can't be one: shorter than 8 or longer than 512
    /// characters, or anything but printable ASCII with no spaces (it is sent
    /// in a header line, where a line break would end the header).
    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...512).contains(trimmed.utf8.count), trimmed.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else {
            return nil
        }
        return trimmed
    }
}

// MARK: What is asked and what comes back

/// One message of a chat, as the API takes it.
struct ChatTurn: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let text: String
}

/// Why asking didn't give an answer, each with its sentence.
enum AnotherModelFailure: Error, Equatable, Sendable {
    /// 401 or 403.
    case keyRefused
    /// 429.
    case tooMany
    /// No answer before the deadline.
    case timedOut
    /// The Mac has no network.
    case offline
    /// The host couldn't be reached.
    case unreachable
    /// Cancel was pressed, or the window closed.
    case cancelled
    /// Any other answer that isn't a 2xx, a redirect included.
    case status(Int)
    /// A 2xx whose body isn't an answer (or a list): not JSON, empty, too big.
    case unreadable
    /// The answer was coming and stopped; the words that came are kept.
    case cutOff(Cut)
    /// Something Settings has to say first.
    case notSet(Missing)

    enum Missing: Sendable { case switchedOff, key, model, address }

    /// How a stream that had begun ended: nothing for a minute, still going
    /// after ten (or past 4 MiB), the connection closed or lost, an error chunk.
    enum Cut: Sendable { case stalled, overran, closed, errored }

    /// The sentence the window or Settings shows. `host` names the address;
    /// `limit` is the deadline that ran out; `inSettings` is Settings' own
    /// model row, where "in Settings" would send the person to where they are.
    func sentence(host: String, limit: Duration, inSettings: Bool = false) -> String {
        switch self {
        case .keyRefused where inSettings: "\(host) didn\u{2019}t accept your key. Remove it, then paste another."
        case .unreachable where inSettings: "Couldn\u{2019}t reach \(host). Check the address above."
        case .notSet(.address) where inSettings: "That isn\u{2019}t an https address."
        case .keyRefused: "\(host) didn\u{2019}t accept your key. Check it in Settings \u{2192} General."
        case .tooMany: "Too many requests to \(host) just now. Wait a minute, then ask again."
        case .timedOut: "No answer came within \(Self.words(limit)). Ask again, or ask something shorter."
        case .offline: "This Mac isn\u{2019}t connected to the internet."
        case .unreachable: "Couldn\u{2019}t reach \(host). Check the address in Settings \u{2192} General."
        case .cancelled: "Cancelled."
        case .status(let code): "\(host) answered with an error (\(code)). Try again in a moment."
        case .unreadable: "\(host) sent back something that isn\u{2019}t an answer."
        case .cutOff(.stalled): "The answer stopped coming. Ask again, or ask something shorter."
        case .cutOff(.overran): "The answer ran on for too long, so Capsid stopped it."
        case .cutOff(.closed): "\(host) closed the connection before the answer was done. Ask again."
        case .cutOff(.errored): "\(host) reported an error while it was answering. Try again in a moment."
        case .notSet(.switchedOff): "Ask another model is off. Turn it on in Settings \u{2192} General first."
        case .notSet(.key): "Paste your key in Settings \u{2192} General first."
        case .notSet(.model): "Choose a model in Settings \u{2192} General first."
        case .notSet(.address): "The address in Settings \u{2192} General isn\u{2019}t an https address."
        }
    }

    /// The log's word for it: fixed words, never the server's own text.
    var word: String {
        switch self {
        case .keyRefused: "key not accepted"
        case .tooMany: "too many requests"
        case .timedOut: "timed out"
        case .offline: "no network"
        case .unreachable: "host unreachable"
        case .cancelled: "cancelled"
        case .status(let code): "status \(code)"
        case .unreadable: "unreadable answer"
        case .cutOff(.stalled): "stalled"
        case .cutOff(.overran): "ran too long"
        case .cutOff(.closed): "connection closed"
        case .cutOff(.errored): "error in the stream"
        case .notSet(.switchedOff): "switched off"
        case .notSet(.key): "no key"
        case .notSet(.model): "no model"
        case .notSet(.address): "no address"
        }
    }

    /// "2 minutes", "20 seconds".
    static func words(_ limit: Duration) -> String {
        let seconds = Int(limit.components.seconds)
        if seconds >= 60, seconds % 60 == 0 { return seconds == 60 ? "a minute" : "\(seconds / 60) minutes" }
        return seconds == 1 ? "a second" : "\(seconds) seconds"
    }

    /// What a URLSession error means here.
    static func of(_ error: URLError) -> AnotherModelFailure {
        switch error.code {
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive: .offline
        default: .unreachable
        }
    }
}

// MARK: The requests

@MainActor
final class AnotherModelClient {
    static let shared = AnotherModelClient()

    /// The first chunk of an answer may take two minutes; the list, 20 seconds.
    nonisolated static let askLimit: Duration = .seconds(120)
    nonisolated static let listLimit: Duration = .seconds(20)
    /// Once an answer has begun: a minute with no chunk ends it, and ten minutes in all.
    nonisolated static let idleLimit: Duration = .seconds(60)
    nonisolated static let overallLimit: Duration = .seconds(600)
    /// A body over this (4 MiB), or an answer longer, isn't read as an answer.
    nonisolated static let maxBody = 4 * 1024 * 1024
    /// The most models a list gives, and the longest name taken. 1,000 holds
    /// the largest public lists (OpenRouter's has about 470; since 1.0.6).
    nonisolated static let maxModels = 1000
    nonisolated static let maxModelName = 200

    let askLimit: Duration
    let listLimit: Duration
    let idleLimit: Duration
    let overallLimit: Duration
    private let session: URLSession
    private let wait: @MainActor (Duration) async -> Void

    /// `configuration` is the tests' way in (a fake `URLProtocol`); `wait`
    /// stands in for the clock, so a deadline can run out at once.
    init(configuration: URLSessionConfiguration = AnotherModelClient.configuration(),
         askLimit: Duration = AnotherModelClient.askLimit, listLimit: Duration = AnotherModelClient.listLimit,
         idleLimit: Duration = AnotherModelClient.idleLimit, overallLimit: Duration = AnotherModelClient.overallLimit,
         wait: @escaping @MainActor (Duration) async -> Void = WriteDeadline.sleep) {
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        self.askLimit = askLimit
        self.listLimit = listLimit
        self.idleLimit = idleLimit
        self.overallLimit = overallLimit
        self.wait = wait
    }

    /// Ephemeral, and keeping nothing: no cookies, no cache, no credentials,
    /// and no waiting for a network that isn't there.
    nonisolated static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return configuration
    }

    /// The models the address lists (`GET /models`), in its order, each once.
    func models(address: URL, key: String) async -> Result<[String], AnotherModelFailure> {
        switch await perform(Self.listRequest(address: address, key: key, limit: listLimit), limit: listLimit) {
        case .failure(let failure): return .failure(failure)
        case .success(let data):
            guard let names = Self.modelNames(in: data) else { return .failure(.unreadable) }
            return .success(names)
        }
    }

    /// One question and the turns before it (`POST /chat/completions`,
    /// streamed): the answer's text, or the words that came and why it didn't
    /// finish. `progress` hears the words as they arrive (AnotherModelStream.swift).
    func ask(address: URL, key: String, model: String, turns: [ChatTurn],
             progress: @escaping @MainActor (AskProgress) -> Void = { _ in }) async -> AnotherModelAnswer {
        guard let request = Self.askRequest(address: address, key: key, model: model, turns: turns, limit: askLimit) else {
            return .failed(.unreadable)
        }
        let run = AskStreamRun(progress: progress, wait: wait, first: askLimit, idle: idleLimit, overall: overallLimit)
        return await run.start(session: session, request: request)
    }

    /// The request, its deadline and its answer's status. Cancelling the
    /// caller ends it at once with `.cancelled`, and the request with it.
    private func perform(_ request: URLRequest, limit: Duration) async -> Result<Data, AnotherModelFailure> {
        let session = session
        let raced = await WriteDeadline.race(limit, wait: wait, cancel: .finish) { () async -> Result<Data, AnotherModelFailure> in
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure(.unreadable) }
                return Self.result(status: http.statusCode, data: data)
            } catch let error as URLError {
                return .failure(AnotherModelFailure.of(error))
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch {
                return .failure(.unreachable)
            }
        }
        switch raced {
        case .finished(let result): return result
        case .timedOut: return .failure(.timedOut)
        case .cancelled: return .failure(.cancelled)
        }
    }

    /// A status and its body: a 2xx within `maxBody`, or why not.
    nonisolated static func result(status: Int, data: Data) -> Result<Data, AnotherModelFailure> {
        switch status {
        case 200..<300: data.count <= maxBody ? .success(data) : .failure(.unreadable)
        case 401, 403: .failure(.keyRefused)
        case 429: .failure(.tooMany)
        default: .failure(.status(status))
        }
    }

    // MARK: Building them

    nonisolated static func listRequest(address: URL, key: String, limit: Duration) -> URLRequest {
        var request = URLRequest(url: address.appending(path: "models"))
        request.httpMethod = "GET"
        prepare(&request, key: key, limit: limit)
        return request
    }

    /// `{"model", "messages": [{"role", "content"}], "stream": true}`, asking
    /// for server-sent events.
    nonisolated static func askRequest(address: URL, key: String, model: String, turns: [ChatTurn], limit: Duration) -> URLRequest? {
        let messages = turns.map { ["role": $0.role.rawValue, "content": $0.text] }
        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        var request = URLRequest(url: address.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        prepare(&request, key: key, limit: limit)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    /// The key in the Authorization header (its only place), JSON asked for,
    /// no cookies, no cache, and the deadline as the request's own timeout too.
    private nonisolated static func prepare(_ request: inout URLRequest, key: String, limit: Duration) {
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = TimeInterval(limit.components.seconds)
    }

    // MARK: Reading them

    /// The names in a list: OpenAI's `{"data": [{"id"}]}`, or `{"models": […]}`,
    /// or a bare array, of names or of objects with an `id` or a `name`. In
    /// the list's order, each once, 1,000 at most; a name is 1 to 200
    /// characters with no control character. Nil when the body is no list.
    nonisolated static func modelNames(in data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let items: [Any]
        if let object = root as? [String: Any] {
            guard let list = (object["data"] as? [Any]) ?? (object["models"] as? [Any]) else { return nil }
            items = list
        } else if let list = root as? [Any] {
            items = list
        } else {
            return nil
        }
        var names: [String] = []
        var seen = Set<String>()
        for item in items {
            let found = (item as? String)
                ?? ((item as? [String: Any]).flatMap { ($0["id"] as? String) ?? ($0["name"] as? String) })
            guard let name = found?.trimmingCharacters(in: .whitespaces), (1...maxModelName).contains(name.count),
                  !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
                  seen.insert(name).inserted else { continue }
            names.append(name)
            if names.count == maxModels { break }
        }
        return names
    }

    /// The answer's text: `choices[0].message.content`, a string or a list of
    /// `{"type": "text", "text"}` parts, joined. Nil when there is none, or it
    /// is only white space.
    nonisolated static func answer(in data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = root["choices"] as? [Any], let first = choices.first as? [String: Any],
              let message = first["message"] as? [String: Any] else { return nil }
        let text: String
        if let plain = message["content"] as? String {
            text = plain
        } else if let parts = message["content"] as? [Any] {
            text = parts.compactMap { part in
                guard let part = part as? [String: Any], (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }.joined()
        } else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}

/// Every redirect is refused: the request ends with the redirect's own
/// status, and the key never follows it to another host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
