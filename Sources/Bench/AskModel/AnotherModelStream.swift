// AnotherModelStream.swift — an answer that arrives as it is written (DESIGN.md,
// Ask another model → The request). `POST /chat/completions` is sent with
// `"stream": true`, and the server answers with server-sent events: one
// `data: {...}` line a chunk, `choices[0].delta.content` the words, and
// `data: [DONE]` the end. A server that ignores `stream` answers plain JSON,
// which is read as it always was.
//
// What this file holds: the words that come out of a stream (`AskProgress`),
// what an ask gives back whole or in part (`AnotherModelAnswer`), how one line
// of the stream is read (`AnotherModelClient.event(line:)`), and the run that
// owns one ask: its three deadlines, Cancel, and the one place an ask ends.
//
// The rules the run keeps:
// - One request, one body, never again on its own. A status that isn't a 2xx
//   ends it before any body is read (the same sentences as ever).
// - Three deadlines on one clock the tests can set off: no first chunk in two
//   minutes (`.timedOut`, as before), then no chunk for a minute
//   (`.cutOff(.stalled)`), and ten minutes in all (`.cutOff(.overran)`). A
//   chunk is a `data:` line that reads as one, reasoning included. A ":"
//   keepalive line renews the minute once a chunk has come, and does not meet
//   the two minutes.
// - The words that arrived are kept whatever ends it: Cancel, a deadline, an
//   error chunk, a lost connection. The run ends exactly once and delivers
//   nothing after it.
// - The reading itself is off the main actor (`@concurrent`); each line hops
//   to the main actor once. Lines end at LF, CR or CRLF and nowhere else
//   (`AskStreamLines`): Foundation's own `bytes.lines` also breaks at U+2028,
//   U+0085 and the like, which are valid inside a JSON string and would cut a
//   chunk in two.
// - Reasoning (`reasoning_content`, or `reasoning`) is never part of the
//   answer; the window only learns that the model is thinking.
import Foundation

// MARK: What an ask gives

/// What a stream tells the window as it goes.
enum AskProgress: Equatable, Sendable {
    /// Only reasoning has come so far (told once, until words arrive).
    case thinking
    /// Words of the answer, in order. A piece, not the whole so far.
    case words(String)
}

/// An ask's end: the words that arrived and, if it didn't finish, why not.
struct AnotherModelAnswer: Equatable, Sendable {
    /// Every word that arrived, in order. Whole when `failure` is nil.
    var text: String
    /// Nil: the answer finished. Else why it didn't; `text` is what came before.
    var failure: AnotherModelFailure?

    static func failed(_ failure: AnotherModelFailure) -> AnotherModelAnswer {
        AnotherModelAnswer(text: "", failure: failure)
    }

    /// The whole answer, or why there isn't one (the words kept are dropped).
    var result: Result<String, AnotherModelFailure> {
        if let failure { return .failure(failure) }
        return .success(text)
    }
}

// MARK: Lines

/// A stream's bytes cut into lines, the way server-sent events are: at LF, CR
/// or CRLF, and nowhere else. A line is decoded once it is whole, so a
/// character that arrived in two reads is whole by then. Blank lines are
/// dropped (they only separate events, and an event here is one line).
struct AskStreamLines: Sendable {
    private var line: [UInt8] = []
    private var afterReturn = false

    /// The next byte; the line it ends, if it ends one.
    mutating func take(_ byte: UInt8) -> String? {
        if afterReturn {
            afterReturn = false
            if byte == 0x0A { return nil }
        }
        switch byte {
        case 0x0A: return finished()
        case 0x0D:
            afterReturn = true
            return finished()
        default:
            line.append(byte)
            return nil
        }
    }

    /// The last line, when the stream ended without a line end after it.
    mutating func rest() -> String? { finished() }

    private mutating func finished() -> String? {
        defer { line.removeAll(keepingCapacity: true) }
        return line.isEmpty ? nil : String(decoding: line, as: UTF8.self)
    }
}

// MARK: Reading a line of the stream

/// One line of a stream, read.
enum AskStreamEvent: Equatable, Sendable {
    /// A ":" line: a keepalive, no information.
    case comment
    /// `data: [DONE]`.
    case done
    /// A chunk. `words` is `delta.content` (empty when absent, null or empty);
    /// `reasoning` that `delta` carried reasoning; `finished` that the choice
    /// had a `finish_reason`.
    case chunk(words: String, reasoning: Bool, finished: Bool)
    /// A chunk that is `{"error": …}`. Its words are never shown.
    case error
}

extension AnotherModelClient {
    /// A line of a server-sent stream as Capsid reads it. Nil for what is
    /// ignored: a blank line, a field that isn't `data` (`event:`, `id:`,
    /// `retry:`, anything unknown), and a `data:` line that isn't a JSON object.
    nonisolated static func event(line raw: String) -> AskStreamEvent? {
        var line = Substring(raw)
        if line.first == "\u{FEFF}" { line = line.dropFirst() }
        guard !line.isEmpty else { return nil }
        if line.first == ":" { return .comment }
        guard let colon = line.firstIndex(of: ":"), line[..<colon] == "data" else { return nil }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        if value.trimmingCharacters(in: .whitespaces) == "[DONE]" { return .done }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] else { return nil }
        if let error = root["error"], !(error is NSNull) { return .error }
        let choice = (root["choices"] as? [Any])?.first as? [String: Any]
        let delta = choice?["delta"] as? [String: Any]
        let words = deltaText(delta?["content"]) ?? ""
        let thinking = deltaText(delta?["reasoning_content"]) ?? deltaText(delta?["reasoning"]) ?? ""
        let finish = (choice?["finish_reason"] as? String).map { !$0.isEmpty } ?? false
        return .chunk(words: words, reasoning: !thinking.isEmpty, finished: finish)
    }

    /// A delta's text: a string, or a list of `{"type": "text", "text"}` parts, joined.
    private nonisolated static func deltaText(_ value: Any?) -> String? {
        if let plain = value as? String { return plain }
        guard let parts = value as? [Any] else { return nil }
        return parts.compactMap { part in
            guard let part = part as? [String: Any], (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }.joined()
    }

    /// Whether a response is a server-sent stream: its type starts with
    /// `text/event-stream` (real servers add `; charset=utf-8`).
    nonisolated static func isEventStream(_ response: HTTPURLResponse) -> Bool {
        (response.value(forHTTPHeaderField: "Content-Type") ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("text/event-stream")
    }
}

// MARK: One ask

/// One ask from its request to its end. Created for each ask and used once.
@MainActor
final class AskStreamRun {
    private let progress: @MainActor (AskProgress) -> Void
    private let wait: @MainActor (Duration) async -> Void
    private let first: Duration
    private let idle: Duration
    private let overall: Duration

    private var text = ""
    /// A chunk has come: the first-chunk deadline is met.
    private var gotChunk = false
    /// `[DONE]` or a `finish_reason` was read: a stream that closes after it is finished.
    private var sawEnd = false
    private var toldThinking = false
    private var continuation: CheckedContinuation<AnotherModelAnswer, Never>?
    private var timer: Task<Void, Never>?
    private var cap: Task<Void, Never>?
    private var reader: Task<Void, Never>?

    init(progress: @escaping @MainActor (AskProgress) -> Void, wait: @escaping @MainActor (Duration) async -> Void,
         first: Duration, idle: Duration, overall: Duration) {
        self.progress = progress
        self.wait = wait
        self.first = first
        self.idle = idle
        self.overall = overall
    }

    /// Sends the request and returns when the ask has ended, by any means.
    /// Cancelling the caller ends it at once with `.cancelled`, the words
    /// kept, and the request with it.
    func start(session: URLSession, request: URLRequest) async -> AnotherModelAnswer {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AnotherModelAnswer, Never>) in
                self.continuation = continuation
                arm(first, .timedOut)
                let wait = wait, overall = overall
                cap = Task { @MainActor [weak self] in
                    await wait(overall)
                    guard !Task.isCancelled else { return }
                    self?.end(.cutOff(.overran))
                }
                reader = Task { [self] in
                    await Self.read(session: session, request: request, run: self)
                }
                if Task.isCancelled { end(.cancelled) }
            }
        } onCancel: {
            Task { @MainActor [self] in end(.cancelled) }
        }
    }

    // MARK: Deadlines

    /// The deadline that runs now: `limit` from here, ending the ask with `failure`.
    private func arm(_ limit: Duration, _ failure: AnotherModelFailure) {
        timer?.cancel()
        let wait = wait
        timer = Task { @MainActor [weak self] in
            await wait(limit)
            guard !Task.isCancelled else { return }
            self?.end(failure)
        }
    }

    // MARK: The end

    /// The one place an ask ends: the words so far with `failure` (nil:
    /// finished). Nothing is delivered after it, and the request is stopped.
    func end(_ failure: AnotherModelFailure?) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        cap?.cancel()
        reader?.cancel()
        timer = nil
        cap = nil
        reader = nil
        continuation.resume(returning: AnotherModelAnswer(text: text, failure: failure))
    }

    /// Finished, as long as some words came.
    private func finish() {
        end(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unreadable : nil)
    }

    // MARK: What the reader hands over

    /// One line of the stream.
    func deliver(_ line: String) {
        guard continuation != nil, let event = AnotherModelClient.event(line: line) else { return }
        switch event {
        case .comment:
            if gotChunk { arm(idle, .cutOff(.stalled)) }
        case .done:
            finish()
        case .error:
            end(.cutOff(.errored))
        case .chunk(let words, let reasoning, let finished):
            gotChunk = true
            arm(idle, .cutOff(.stalled))
            if finished { sawEnd = true }
            if !words.isEmpty {
                text += words
                progress(.words(words))
                if text.utf8.count > AnotherModelClient.maxBody { end(.cutOff(.overran)) }
            } else if reasoning, !toldThinking {
                toldThinking = true
                progress(.thinking)
            }
        }
    }

    /// The stream closed cleanly: finished after `[DONE]` or a finish reason,
    /// else cut off (a connection that is lost usually arrives as an error, so
    /// a clean close without either is a server that stopped early).
    func streamEnded() {
        if sawEnd { finish() } else { end(.cutOff(.closed)) }
    }

    /// A body that isn't a stream: a server that ignored `stream` answers
    /// JSON, read as it always was. A body that is a stream sent under another
    /// content type is read line by line, whole.
    func body(_ data: Data) {
        guard continuation != nil else { return }
        if let answer = AnotherModelClient.answer(in: data) {
            text = answer
            end(nil)
            return
        }
        var splitter = AskStreamLines()
        var lines: [String] = data.compactMap { splitter.take($0) }
        if let rest = splitter.rest() { lines.append(rest) }
        guard lines.contains(where: { line in
            if case .chunk? = AnotherModelClient.event(line: line) { return true }
            return false
        }) else {
            end(.unreadable)
            return
        }
        lines.forEach { deliver($0) }
        streamEnded()
    }

    /// The request failed or the connection broke. Once a chunk has come, a
    /// lost connection is the answer cut off, not a Mac without a network.
    func failed(_ error: any Error) {
        guard continuation != nil else { return }
        guard let error = error as? URLError else {
            end(gotChunk ? .cutOff(.closed) : .unreachable)
            return
        }
        var failure = AnotherModelFailure.of(error)
        if gotChunk {
            switch failure {
            case .offline, .unreachable: failure = .cutOff(.closed)
            case .timedOut: failure = .cutOff(.stalled)
            default: break
            }
        }
        end(failure)
    }

    // MARK: Reading, off the main actor

    /// The request, its status, then the stream line by line (or the JSON body
    /// whole).
    @concurrent
    private nonisolated static func read(session: URLSession, request: URLRequest, run: AskStreamRun) async {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                await run.end(.unreadable)
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                if case .failure(let failure) = AnotherModelClient.result(status: http.statusCode, data: Data()) {
                    await run.end(failure)
                }
                return
            }
            if AnotherModelClient.isEventStream(http) {
                var lines = AskStreamLines()
                for try await byte in bytes {
                    if let line = lines.take(byte) { await run.deliver(line) }
                }
                if let rest = lines.rest() { await run.deliver(rest) }
                await run.streamEnded()
            } else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    if data.count > AnotherModelClient.maxBody { break }
                }
                if data.count > AnotherModelClient.maxBody {
                    await run.end(.unreadable)
                } else {
                    await run.body(data)
                }
            }
        } catch is CancellationError {
            // The ask ended some other way, and cancelled this.
        } catch {
            await run.failed(error)
        }
    }
}
