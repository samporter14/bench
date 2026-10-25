// AskModelStreamTests.swift — the answer that arrives as it is written (AskModel/
// AnotherModelStream.swift, AnotherModelClient.swift): how a line of a
// server-sent stream is read, a stream sent in uneven pieces (a line cut in two,
// a character cut in two, comments, reasoning, an end), an error chunk, a server
// that ignores `stream` and answers JSON, a status before any byte, the three
// deadlines on a manual clock, and Cancel with the words kept. The fake is
// FakeModelProtocol's feed (AskModelClientTests.swift): a made-up host each, a
// made-up key, and no clock but the test's own. Nothing leaves the process.
import Foundation
import Testing
@testable import Bench

// MARK: Made-up streams

private let sse = "text/event-stream; charset=utf-8"

/// One `data:` line of a stream, as a server writes it: the JSON is escaped by
/// Foundation, so a character outside ASCII stays whole in the bytes.
private func chunk(_ content: String? = nil, reasoning: String? = nil, role: Bool = false, finish: String? = nil,
                   key: String = "reasoning_content") -> String {
    var delta: [String: Any] = [:]
    if role { delta["role"] = "assistant" }
    if let content { delta["content"] = content }
    if let reasoning { delta[key] = reasoning }
    let body: [String: Any] = ["id": "chatcmpl-1", "object": "chat.completion.chunk",
                               "choices": [["index": 0, "delta": delta, "finish_reason": finish.map { $0 as Any } ?? NSNull()]]]
    let json = try! JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
    return "data: " + String(decoding: json, as: UTF8.self) + "\n\n"
}

/// What the stream below says once read: the reasoning is not in it.
private let streamedAnswer = "Use **HEPES** at 25 \u{00B5}M \u{2014} caf\u{00E9} \u{1F9EA} done."

/// A whole stream: a comment, the role, reasoning, words (with a two-byte, a
/// three-byte and a four-byte character), unknown fields, a finish and `[DONE]`.
private func wholeStream(lineEnd: String = "\n") -> String {
    let text = [
        ": keep-alive\n\n",
        chunk(role: true),
        chunk(reasoning: "Let me think about the buffer."),
        chunk(reasoning: " Tris drifts.", key: "reasoning"),
        chunk("Use "),
        "event: message\nid: 7\nretry: 3000\n",
        chunk("**HEPES** at 25 \u{00B5}M \u{2014} caf\u{00E9} "),
        chunk("\u{1F9EA} done."),
        chunk(finish: "stop"),
        ": about to end\n\n",
        "data: [DONE]\n\n",
    ].joined()
    return lineEnd == "\n" ? text : text.replacingOccurrences(of: "\n", with: lineEnd)
}

/// A body cut in pieces: every byte alone, every `size` bytes, or just before
/// every continuation byte (so every multi-byte character is cut in two).
private func pieces(_ text: String, every size: Int? = nil, midCharacter: Bool = false) -> [Data] {
    let bytes = Array(text.utf8)
    var cuts: [Int] = []
    for (index, byte) in bytes.enumerated() where index > 0 {
        if midCharacter { if byte & 0xC0 == 0x80 { cuts.append(index) } } else if index % (size ?? 1) == 0 { cuts.append(index) }
    }
    var result: [Data] = []
    var from = 0
    for cut in cuts + [bytes.count] {
        result.append(Data(bytes[from..<cut]))
        from = cut
    }
    return result.filter { !$0.isEmpty }
}

// MARK: Rigs

@MainActor
private func client(_ clock: ManualClock? = nil, started: StartedWaits? = nil) -> AnotherModelClient {
    guard let clock else { return AnotherModelClient(configuration: FakeModelProtocol.configuration()) }
    return AnotherModelClient(configuration: FakeModelProtocol.configuration(), wait: { duration in
        started?.note(duration)
        await clock.wait(duration)
    })
}

/// How many times each deadline was set, so a deadline renewed by a chunk shows as a new wait.
@MainActor
private final class StartedWaits {
    private(set) var counts: [Duration: Int] = [:]
    func note(_ duration: Duration) { counts[duration, default: 0] += 1 }
    func count(_ seconds: Int) -> Int { counts[.seconds(seconds)] ?? 0 }
}

/// What a stream told the window.
@MainActor
private final class Heard {
    var events: [AskProgress] = []
    var words: String {
        events.compactMap { event -> String? in if case .words(let piece) = event { piece } else { nil } }.joined()
    }
    var thinking: Int { events.filter { $0 == .thinking }.count }
    func hear(_ event: AskProgress) { events.append(event) }
}

private func address(_ host: String) -> URL { URL(string: "https://\(host)/v1")! }

@MainActor
private func until(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1_000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}

/// The minute has been set the `nth` time and is the only one waiting: the one a chunk just started, the old one gone.
@MainActor
private func minute(_ nth: Int, _ started: StartedWaits, _ clock: ManualClock) async {
    await until { started.count(60) == nth && clock.waiting(.seconds(60)) == 1 }
}

@MainActor
private func stops(_ host: String, _ count: Int = 1) async {
    await until { FakeModelProtocol.seen(host).stops >= count }
}

@MainActor
private func ask(_ host: String, _ client: AnotherModelClient, _ heard: Heard) async -> AnotherModelAnswer {
    await client.ask(address: address(host), key: madeUpModelKey, model: "abliterated-model",
                     turns: [ChatTurn(role: .user, text: "Which buffer?")], progress: { heard.hear($0) })
}

// MARK: Cutting lines

struct AskStreamLinesTests {
    /// Every line a run of bytes makes, fed in `cuts`-sized pieces, then the rest.
    private func lines(_ bytes: [UInt8], every size: Int = 1) -> [String] {
        var splitter = AskStreamLines()
        var found: [String] = []
        for byte in bytes { if let line = splitter.take(byte) { found.append(line) } }
        if let rest = splitter.rest() { found.append(rest) }
        return found
    }

    @Test func linesEndAtLfCrOrCrlfAndNowhereElse() {
        #expect(lines(Array("a\nb\r\nc\rd\n".utf8)) == ["a", "b", "c", "d"])
        // Blank lines (an event's end) are dropped, in every spelling.
        #expect(lines(Array("a\n\nb\r\n\r\nc\r\rd".utf8)) == ["a", "b", "c", "d"])
        // The last line needs no line end.
        #expect(lines(Array("data: [DONE]".utf8)) == ["data: [DONE]"])
        #expect(lines([]).isEmpty)
        // Unicode's line ends, and the page's other controls, stay inside the line.
        let odd = "a\u{2028}b\u{2029}c\u{0085}d\u{000B}e\u{000C}f"
        #expect(lines(Array(odd.utf8)) == [odd])
    }

    @Test func aCharacterIsWholeWhateverReadItArrivedIn() {
        let text = "caf\u{00E9} \u{2014} \u{1F9EA}"
        var splitter = AskStreamLines()
        // One byte at a time, so every multi-byte character is cut in two (or three) between calls.
        let bytes = Array((text + "\n").utf8)
        var found: [String] = []
        for byte in bytes { if let line = splitter.take(byte) { found.append(line) } }
        #expect(found == [text])
    }

    @Test func aCrlfSplitAcrossTwoReadsIsOneLineEnd() {
        var splitter = AskStreamLines()
        #expect(splitter.take(0x61) == nil)
        #expect(splitter.take(0x0D) == "a")
        // The LF of the pair comes in the next read, and ends nothing more.
        #expect(splitter.take(0x0A) == nil)
        #expect(splitter.take(0x62) == nil)
        #expect(splitter.take(0x0A) == "b")
        #expect(splitter.rest() == nil)
    }

    @Test func bytesThatAreNoTextAreReplacedAndNeverThrow() {
        #expect(lines([0x61, 0xFF, 0x62, 0x0A]) == ["a\u{FFFD}b"])
    }
}

// MARK: Reading a line

struct AskStreamLineTests {
    private func event(_ line: String) -> AskStreamEvent? { AnotherModelClient.event(line: line) }
    private func data(_ json: String) -> String { "data: " + json }

    @Test func aChunkIsItsDeltasContentWhichMayBeAbsentOrNull() {
        #expect(event(data(#"{"choices":[{"delta":{"content":"Use "}}]}"#)) == .chunk(words: "Use ", reasoning: false, finished: false))
        // No space after the colon is as good as one.
        #expect(event(#"data:{"choices":[{"delta":{"content":"Use"}}]}"#) == .chunk(words: "Use", reasoning: false, finished: false))
        for quiet in [#"{"choices":[{"delta":{"content":null}}]}"#, #"{"choices":[{"delta":{}}]}"#,
                      #"{"choices":[{"delta":{"content":""}}]}"#, #"{"choices":[{"delta":{"role":"assistant"}}]}"#,
                      #"{"choices":[{"index":0}]}"#, #"{"choices":[]}"#, #"{"id":"x","usage":{"total_tokens":9}}"#, "{}"] {
            #expect(event(data(quiet)) == .chunk(words: "", reasoning: false, finished: false), "\(quiet)")
        }
        // Parts, as some servers write them.
        #expect(event(data(#"{"choices":[{"delta":{"content":[{"type":"text","text":"A"},{"type":"image"},{"type":"text","text":"B"}]}}]}"#))
            == .chunk(words: "AB", reasoning: false, finished: false))
        #expect(event(data(#"{"choices":[{"delta":{"content":"café 🧪"}}]}"#))
            == .chunk(words: "caf\u{00E9} \u{1F9EA}", reasoning: false, finished: false))
    }

    @Test func reasoningIsToldApartFromTheAnswer() {
        #expect(event(data(#"{"choices":[{"delta":{"reasoning_content":"Let me think"}}]}"#))
            == .chunk(words: "", reasoning: true, finished: false))
        #expect(event(data(#"{"choices":[{"delta":{"reasoning":"Let me think"}}]}"#))
            == .chunk(words: "", reasoning: true, finished: false))
        #expect(event(data(#"{"choices":[{"delta":{"reasoning_content":""}}]}"#)) == .chunk(words: "", reasoning: false, finished: false))
        // Both in one chunk: the words are the answer, and only they are handed over.
        #expect(event(data(#"{"choices":[{"delta":{"content":"Use","reasoning_content":"hm"}}]}"#))
            == .chunk(words: "Use", reasoning: true, finished: false))
    }

    @Test func aFinishReasonIsNoted() {
        #expect(event(data(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#)) == .chunk(words: "", reasoning: false, finished: true))
        #expect(event(data(#"{"choices":[{"delta":{"content":"x"},"finish_reason":null}]}"#))
            == .chunk(words: "x", reasoning: false, finished: false))
    }

    @Test func doneEndsAndAnErrorChunkIsAnError() {
        #expect(event("data: [DONE]") == .done)
        #expect(event("data:[DONE]") == .done)
        #expect(event("data: [DONE]  ") == .done)
        #expect(event(data(#"{"error":{"message":"overloaded","code":500}}"#)) == .error)
        #expect(event(data(#"{"error":"overloaded"}"#)) == .error)
        // A null error on every chunk is no error.
        #expect(event(data(#"{"error":null,"choices":[{"delta":{"content":"ok"}}]}"#)) == .chunk(words: "ok", reasoning: false, finished: false))
    }

    @Test func commentsBlanksAndUnknownFieldsAreIgnored() {
        #expect(event(": keep-alive") == .comment)
        #expect(event(":") == .comment)
        for ignored in ["", "event: message", "id: 7", "retry: 3000", "data", "foo: bar", "data: not json", "data: [1,2]",
                        "data: \"text\"", "data: 7", "data:", "no colon at all"] {
            #expect(event(ignored) == nil, "\(ignored)")
        }
        // A byte order mark at the start of the stream is not part of the first line.
        #expect(event("\u{FEFF}data: [DONE]") == .done)
        #expect(event("\u{FEFF}: hello") == .comment)
    }

    @Test func aResponseIsAStreamByItsContentTypeWhateverFollowsIt() throws {
        func response(_ type: String?) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://x.example")!, statusCode: 200, httpVersion: "HTTP/1.1",
                            headerFields: type.map { ["Content-Type": $0] })!
        }
        #expect(AnotherModelClient.isEventStream(response("text/event-stream")))
        #expect(AnotherModelClient.isEventStream(response("text/event-stream; charset=utf-8")))
        #expect(AnotherModelClient.isEventStream(response("Text/Event-Stream")))
        #expect(!AnotherModelClient.isEventStream(response("application/json")))
        #expect(!AnotherModelClient.isEventStream(response("application/json; charset=utf-8")))
        #expect(!AnotherModelClient.isEventStream(response(nil)))
    }
}

// MARK: A stream, in pieces

@MainActor
struct AskStreamingTests {
    @Test func aStreamCutAnywhereIsReadWholeAndTheReasoningIsNotTheAnswer() async {
        let splits: [(String, [Data])] = [
            ("one byte at a time", pieces(wholeStream())),
            ("every 3 bytes", pieces(wholeStream(), every: 3)),
            ("every 11 bytes", pieces(wholeStream(), every: 11)),
            ("every character cut in two", pieces(wholeStream(), midCharacter: true)),
            ("CRLF, one byte at a time", pieces(wholeStream(lineEnd: "\r\n"))),
            ("CR alone, every 5 bytes", pieces(wholeStream(lineEnd: "\r"), every: 5)),
            ("one piece", [Data(wholeStream().utf8)]),
        ]
        for (label, cut) in splits {
            let feed = StreamFeed()
            cut.forEach { feed.send($0) }
            feed.finish()
            let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
            let heard = Heard()
            let answer = await ask(host, client(), heard)
            #expect(answer == AnotherModelAnswer(text: streamedAnswer, failure: nil), "\(label): \(answer)")
            #expect(heard.words == streamedAnswer, "\(label)")
            // Reasoning is told once, first, and never as words.
            #expect(heard.events.first == .thinking, "\(label)")
            #expect(heard.thinking == 1, "\(label)")
            #expect(!heard.words.contains("think") && !heard.words.contains("Tris"), "\(label)")
            #expect(FakeModelProtocol.seen(host).requests.count == 1, "\(label)")
        }
    }

    @Test func aLineSeparatorInsideTheWordsIsNotALineEnd() async {
        // U+2028, U+2029 and U+0085 are line ends to Unicode (Foundation's `bytes.lines` breaks there), not to a
        // stream: raw in a JSON string, they stay in the words.
        let text = "a\u{2028}b\u{0085}c\u{2029}d"
        let feed = StreamFeed(["data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\n\n", "data: [DONE]\n\n"])
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let answer = await ask(host, client(), Heard())
        #expect(answer == AnotherModelAnswer(text: text, failure: nil))
    }

    @Test func wordsAreHeardWhileTheStreamIsStillOpen() async {
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(), heard) }
        feed.send(chunk("Use "))
        await until { heard.words == "Use " }
        // Not buffered to the end: the stream has not finished, and the first words are here.
        #expect(heard.words == "Use ")
        feed.send(chunk("HEPES."))
        await until { heard.words == "Use HEPES." }
        #expect(heard.words == "Use HEPES.")
        feed.send("data: [DONE]\n\n")
        feed.finish()
        #expect(await task.value == AnotherModelAnswer(text: "Use HEPES.", failure: nil))
    }

    @Test func aStreamThatEndsAfterAFinishReasonWithoutDoneIsFinished() async {
        let feed = StreamFeed([chunk("Use HEPES."), chunk(finish: "stop")])
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        #expect(await ask(host, client(), Heard()) == AnotherModelAnswer(text: "Use HEPES.", failure: nil))
    }

    @Test func aLastLineWithNoLineEndIsStillRead() async {
        let feed = StreamFeed([chunk("Use HEPES."), "data: [DONE]"])
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        #expect(await ask(host, client(), Heard()) == AnotherModelAnswer(text: "Use HEPES.", failure: nil))
    }

    @Test func aStreamThatClosesEarlyIsCutOffAndKeepsItsWords() async {
        let feed = StreamFeed([chunk("Use "), chunk("HEPES")])
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let answer = await ask(host, client(), Heard())
        #expect(answer == AnotherModelAnswer(text: "Use HEPES", failure: .cutOff(.closed)))
    }

    @Test func aStreamWithOnlyReasoningThenDoneIsNoAnswer() async {
        let feed = StreamFeed([chunk(reasoning: "Thinking."), chunk(finish: "stop"), "data: [DONE]\n\n"])
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let answer = await ask(host, client(), heard)
        #expect(answer == AnotherModelAnswer(text: "", failure: .unreadable))
        #expect(heard.events == [.thinking])
    }

    @Test func aConnectionLostMidStreamIsCutOffAndOneLostAtOnceIsOffline() async {
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(), heard) }
        feed.send(chunk("Use "))
        await until { heard.words == "Use " }
        feed.fail(.networkConnectionLost)
        let answer = await task.value
        #expect(answer == AnotherModelAnswer(text: "Use ", failure: .cutOff(.closed)))
        let early = StreamFeed([], then: .fail(.networkConnectionLost))
        let other = FakeModelProtocol.host { _ in .stream(200, sse, early) }
        #expect(await ask(other, client(), Heard()) == .failed(.offline))
    }
}

// MARK: Errors, JSON, statuses

@MainActor
struct AskStreamEndingsTests {
    @Test func anErrorChunkMidStreamFailsAndKeepsTheWordsThatCame() async {
        let feed = StreamFeed([chunk("Use "), chunk("HEPES"), #"data: {"error":{"message":"overloaded: secret-detail","code":500}}"# + "\n\n",
                               chunk("never shown")], then: nil)
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let answer = await ask(host, client(), heard)
        #expect(answer == AnotherModelAnswer(text: "Use HEPES", failure: .cutOff(.errored)))
        #expect(heard.words == "Use HEPES")
        // The server's own words are not the window's.
        let sentence = AnotherModelFailure.cutOff(.errored).sentence(host: "api.abliteration.ai", limit: .seconds(120))
        #expect(sentence == "api.abliteration.ai reported an error while it was answering. Try again in a moment.")
        #expect(!sentence.contains("secret-detail"))
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
        #expect(FakeModelProtocol.seen(host).requests.count == 1)
    }

    @Test func anErrorChunkBeforeAnyWordsFailsWithNoWords() async {
        let feed = StreamFeed([#"data: {"error":"rate limited"}"# + "\n\n"], then: nil)
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        #expect(await ask(host, client(), Heard()) == .failed(.cutOff(.errored)))
    }

    @Test func aServerThatIgnoresStreamAnswersJSONAndItIsReadAsItAlwaysWas() async {
        let json = #"{"id":"c1","choices":[{"index":0,"message":{"role":"assistant","content":"Use **HEPES** at 25 mM."}}]}"#
        for type in ["application/json", "application/json; charset=utf-8"] {
            let feed = StreamFeed(pieces(json).map { String(decoding: $0, as: UTF8.self) })
            let host = FakeModelProtocol.host { _ in .stream(200, type, feed) }
            let heard = Heard()
            let answer = await ask(host, client(), heard)
            #expect(answer == AnotherModelAnswer(text: "Use **HEPES** at 25 mM.", failure: nil), "\(type)")
            // Nothing arrived piece by piece: the whole answer is the result.
            #expect(heard.events.isEmpty)
        }
        let plain = FakeModelProtocol.host { _ in .reply(200, json) }
        #expect(await ask(plain, client(), Heard()).result == .success("Use **HEPES** at 25 mM."))
        // JSON that holds no answer is not one.
        let empty = FakeModelProtocol.host { _ in .reply(200, #"{"choices":[{"message":{"content":""}}]}"#) }
        #expect(await ask(empty, client(), Heard()) == .failed(.unreadable))
        let junk = FakeModelProtocol.host { _ in .reply(200, "<html>nope</html>") }
        #expect(await ask(junk, client(), Heard()) == .failed(.unreadable))
    }

    @Test func aStreamSentUnderAnotherContentTypeIsStillReadAndThenWhole() async {
        let host = FakeModelProtocol.host { _ in .reply(200, wholeStream()) }
        let heard = Heard()
        let answer = await ask(host, client(), heard)
        #expect(answer == AnotherModelAnswer(text: streamedAnswer, failure: nil))
        #expect(heard.words == streamedAnswer)
    }

    @Test func aStatusBeforeAnyByteKeepsTodaysFailuresAndTheBodyIsNeverReadAsAnAnswer() async {
        let cases: [(Int, AnotherModelFailure)] = [(401, .keyRefused), (403, .keyRefused), (429, .tooMany), (500, .status(500)),
                                                   (404, .status(404)), (302, .status(302))]
        for (status, failure) in cases {
            // A body that would read as an answer, if it were read.
            let feed = StreamFeed([chunk("SHOULD NOT SHOW"), "data: [DONE]\n\n"])
            let host = FakeModelProtocol.host { _ in .stream(status, sse, feed) }
            let heard = Heard()
            #expect(await ask(host, client(), heard) == .failed(failure), "\(status)")
            #expect(heard.events.isEmpty, "\(status)")
            #expect(FakeModelProtocol.seen(host).requests.count == 1, "\(status)")
        }
    }

    @Test func aStreamOverFourMebibytesIsStoppedAndKeepsWhatCame() async {
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(), heard) }
        let block = chunk(String(repeating: "a", count: 60_000))
        for _ in 0..<80 { feed.send(block) }
        let answer = await task.value
        #expect(answer.failure == .cutOff(.overran))
        #expect(answer.text.utf8.count > AnotherModelClient.maxBody && answer.text.utf8.count <= AnotherModelClient.maxBody + 60_000)
        #expect(heard.words == answer.text)
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
    }
}

// MARK: Deadlines and Cancel

@MainActor
struct AskStreamDeadlineTests {
    @Test func theFirstChunkHasTwoMinutesAndTheWholeAskTen() async {
        let clock = ManualClock()
        let started = StartedWaits()
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let task = Task { @MainActor in await ask(host, client(clock, started: started), Heard()) }
        await clock.until(waiting: 2)
        #expect(clock.waiting(.seconds(120)) == 1)
        #expect(clock.waiting(.seconds(600)) == 1)
        #expect(clock.waiting(.seconds(60)) == 0)
        // A keepalive before any chunk does not meet the two minutes.
        feed.send(": still here\n\n")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(clock.waiting(.seconds(120)) == 1 && started.count(60) == 0)
        clock.fire(.seconds(120))
        let answer = await task.value
        #expect(answer == .failed(.timedOut))
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
        #expect(FakeModelProtocol.seen(host).requests.count == 1)
        #expect(AnotherModelFailure.timedOut.sentence(host: host, limit: .seconds(120))
            == "No answer came within 2 minutes. Ask again, or ask something shorter.")
    }

    @Test func aReasoningChunkMeetsTheFirstDeadlineAndStartsTheMinute() async {
        let clock = ManualClock()
        let started = StartedWaits()
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(clock, started: started), heard) }
        await clock.until(waiting: 2)
        feed.send(chunk(reasoning: "Thinking."))
        await until { heard.thinking == 1 }
        await minute(1, started, clock)
        #expect(clock.waiting(.seconds(60)) == 1)
        await until { clock.waiting(.seconds(120)) == 0 }
        #expect(clock.waiting(.seconds(120)) == 0)
        clock.fire(.seconds(60))
        // Only reasoning came: the minute ran out with no words to keep.
        #expect(await task.value == .failed(.cutOff(.stalled)))
    }

    @Test func aMinuteWithNoChunkEndsItAsStalledKeepingTheWords() async {
        let clock = ManualClock()
        let started = StartedWaits()
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(clock, started: started), heard) }
        await clock.until(waiting: 2)
        feed.send(chunk("Use "))
        feed.send(chunk("HEPES"))
        await until { heard.words == "Use HEPES" }
        // The minute set by the second chunk is the one waiting, and the first chunk's is gone.
        await minute(2, started, clock)
        #expect(clock.waiting(.seconds(60)) == 1)
        clock.fire(.seconds(60))
        let answer = await task.value
        #expect(answer == AnotherModelAnswer(text: "Use HEPES", failure: .cutOff(.stalled)))
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
        // Never tried again on its own.
        #expect(FakeModelProtocol.seen(host).requests.count == 1)
        #expect(AnotherModelFailure.cutOff(.stalled).sentence(host: host, limit: .seconds(120))
            == "The answer stopped coming. Ask again, or ask something shorter.")
    }

    @Test func everyChunkStartsTheMinuteOverAndAKeepaliveRenewsItOnceWordsHaveCome() async {
        let clock = ManualClock()
        let started = StartedWaits()
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(clock, started: started), heard) }
        await clock.until(waiting: 2)
        feed.send(chunk("A"))
        await until { heard.words == "A" }
        await minute(1, started, clock)
        #expect(started.count(60) == 1)
        feed.send(chunk("B"))
        await until { heard.words == "AB" }
        // A new minute, and the old one was cancelled: one is waiting, not two.
        await minute(2, started, clock)
        #expect(started.count(60) == 2 && clock.waiting(.seconds(60)) == 1)
        feed.send(": keep-alive\n\n")
        await minute(3, started, clock)
        #expect(started.count(60) == 3)
        // A chunk with no words, no reasoning (a role, a usage) renews it too.
        feed.send(chunk(role: true))
        await minute(4, started, clock)
        #expect(started.count(60) == 4)
        await until { clock.waiting(.seconds(120)) == 0 }
        #expect(clock.waiting(.seconds(120)) == 0)
        feed.send("data: [DONE]\n\n")
        feed.finish()
        #expect(await task.value == AnotherModelAnswer(text: "AB", failure: nil))
        // Done: no deadline is left waiting.
        await clock.until(waiting: 0)
        for _ in 0..<200 where clock.waiting() > 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(clock.waiting() == 0)
    }

    @Test func tenMinutesInAllEndsItEvenWhileChunksKeepComing() async {
        let clock = ManualClock()
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(clock), heard) }
        await clock.until(waiting: 2)
        feed.send(chunk("Use "))
        await until { heard.words == "Use " }
        clock.fire(.seconds(600))
        let answer = await task.value
        #expect(answer == AnotherModelAnswer(text: "Use ", failure: .cutOff(.overran)))
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
        #expect(AnotherModelFailure.cutOff(.overran).sentence(host: host, limit: .seconds(120))
            == "The answer ran on for too long, so Capsid stopped it.")
        // Nothing arrives after the ask has ended.
        feed.send(chunk("more"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(heard.words == "Use ")
    }

    @Test func cancelStopsTheStreamAtOnceAndKeepsWhatCame() async {
        let clock = ManualClock()
        let feed = StreamFeed()
        let host = FakeModelProtocol.host { _ in .stream(200, sse, feed) }
        let heard = Heard()
        let task = Task { @MainActor in await ask(host, client(clock), heard) }
        await clock.until(waiting: 2)
        feed.send(chunk("Use "))
        feed.send(chunk("HEPES"))
        await until { heard.words == "Use HEPES" }
        task.cancel()
        let answer = await task.value
        #expect(answer == AnotherModelAnswer(text: "Use HEPES", failure: .cancelled))
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
        #expect(FakeModelProtocol.seen(host).requests.count == 1)
        // Nothing is heard after it, and every deadline is gone.
        feed.send(chunk(" and more"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(heard.words == "Use HEPES")
        for _ in 0..<200 where clock.waiting() > 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(clock.waiting() == 0)
    }

    @Test func cancelBeforeTheFirstByteEndsItWithNoWords() async {
        let clock = ManualClock()
        let host = FakeModelProtocol.host { _ in .never }
        let task = Task { @MainActor in await ask(host, client(clock), Heard()) }
        await clock.until(waiting: 2)
        task.cancel()
        #expect(await task.value == .failed(.cancelled))
        await stops(host)
        #expect(FakeModelProtocol.seen(host).stops == 1)
    }

    @Test func anAskCancelledBeforeItStartedNeverHangs() async {
        let host = FakeModelProtocol.host { _ in .never }
        let task = Task { @MainActor () -> AnotherModelAnswer in
            withUnsafeCurrentTask { $0?.cancel() }
            return await ask(host, client(), Heard())
        }
        #expect(await task.value.failure == .cancelled)
    }
}
