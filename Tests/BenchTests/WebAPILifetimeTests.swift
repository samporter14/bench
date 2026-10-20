// The read bridge against made-up fetches and a manually advanced deadline.
// No daemon, network, real timers or page session is involved.
import Foundation
import Testing
@testable import Bench

private final class APIReadPage {
    let script = PageScript(#"""
    var __timers = new Map(), __nextTimer = 0, __answers = {}, __results = {}, __seen = {};
    function setTimeout(callback) { const id = ++__nextTimer; __timers.set(id, callback); return id; }
    function clearTimeout(id) { __timers.delete(id); }
    function __fireTimers() { for (const callback of Array.from(__timers.values())) { callback(); } }
    class AbortController {
        constructor() {
            this.signal = { aborted: false, listeners: new Set(),
                addEventListener(type, callback) { this.listeners.add(callback); },
                removeEventListener(type, callback) { this.listeners.delete(callback); } };
        }
        abort() {
            if (this.signal.aborted) { return; }
            this.signal.aborted = true;
            for (const callback of Array.from(this.signal.listeners)) { callback(); }
        }
    }
    // Fixtures are ASCII. WebKit supplies the streaming UTF-8 TextDecoder.
    class TextDecoder { decode(bytes) { return bytes ? String.fromCharCode(...bytes) : ""; } }
    function fetch(path, init) {
        const answer = __answers[path];
        const seen = __seen[path] = { pulled: 0, cancelled: 0, signal: init.signal,
                                     credentials: init.credentials, cache: init.cache };
        if (answer.stage === "headers") { return new Promise(() => {}); }
        if (answer.stage === "network") { return Promise.reject(new Error("network failed")); }
        let offset = 0;
        return Promise.resolve({
            status: answer.status, ok: answer.status >= 200 && answer.status < 300,
            headers: { get() { return answer.length; } },
            body: { getReader() { return {
                read() {
                    seen.pulled += 1;
                    if (answer.stage === "body") { return new Promise(() => {}); }
                    if (offset >= answer.chunks.length) { return Promise.resolve({ done: true }); }
                    return Promise.resolve({ done: false, value: new Uint8Array(answer.chunks[offset++]) });
                },
                cancel() { seen.cancelled += 1; return Promise.resolve(); },
            }; } },
        });
    }
    """#)

    func start(_ nonce: String = "read-a", stage: String = "complete", status: Int = 200,
               chunks: [[UInt8]] = [Array("{}".utf8)], declaredLength: Int? = nil, maxBytes: Int = 64) {
        let answer: [String: Any] = ["stage": stage, "status": status, "chunks": chunks,
                                     "length": declaredLength.map(String.init) as Any? ?? NSNull()]
        let json = try! JSONSerialization.data(withJSONObject: answer)
        script.set("__answer", String(decoding: json, as: UTF8.self))
        script.set("__nonce", nonce)
        script.evaluate("__answers[__nonce] = JSON.parse(__answer);")
        script.evaluate("""
        (async function(path, nonce, timeoutMS, maxBytes) {
        \(WebAPIReadScript.body)
        })(__nonce, __nonce, 15000, \(maxBytes)).then(
            ((id) => value => { __results[id] = { value }; })(__nonce),
            ((id) => error => { __results[id] = { error: error.message }; })(__nonce));
        """)
        #expect(script.exception == nil)
    }

    func result(_ nonce: String = "read-a", field: String) -> String? {
        script.set("__lookup", nonce)
        return script.evaluate("__results[__lookup] && __results[__lookup].\(field)")
    }

    func abort(_ nonce: String = "read-a") {
        script.set("__abortNonce", nonce)
        script.evaluate("""
        (async function(nonce) { \(WebAPIReadScript.abort) })(__abortNonce);
        """)
        #expect(script.exception == nil)
    }

    var activeReads: String? { script.evaluate("String(globalThis.__capsidAPIReads.size)") }
    var timers: String? { script.evaluate("String(__timers.size)") }
    func expire() { script.evaluate("__fireTimers()") }
}

struct WebAPIReadLifetimeTests {
    @Test func successReadsAllChunksAndReleasesItsControllerAndTimer() {
        let page = APIReadPage()
        page.start(chunks: [Array("{\"a\":".utf8), Array("1}".utf8)])
        #expect(page.result(field: "value") == "{\"a\":1}")
        #expect(page.activeReads == "0")
        #expect(page.timers == "0")
        #expect(page.script.evaluate("__seen['read-a'].cache") == "no-store")
        #expect(page.script.evaluate("__seen['read-a'].credentials") == "include")
    }

    @Test(arguments: ["headers", "body"])
    func theSameDeadlineEndsAStallBeforeOrAfterHeaders(_ stage: String) {
        let page = APIReadPage()
        page.start(stage: stage)
        #expect(page.result(field: "value") == nil)
        #expect(page.activeReads == "1")
        page.expire()
        #expect(page.result(field: "error") == "CAPSID_API_TIMEOUT")
        #expect(page.activeReads == "0")
        #expect(page.timers == "0")
        #expect(page.script.evaluate("String(__seen['read-a'].signal.aborted)") == "true")
    }

    @Test func cancellingOneReadLeavesAnotherAlone() {
        let page = APIReadPage()
        page.start("read-a", stage: "body")
        page.start("read-b", stage: "headers")
        page.abort("read-a")
        #expect(page.result("read-a", field: "error") == "CAPSID_API_CANCELLED")
        #expect(page.result("read-b", field: "error") == nil)
        #expect(page.activeReads == "1")
        #expect(page.timers == "1")
        #expect(page.script.evaluate("String(__seen['read-b'].signal.aborted)") == "false")
        page.expire()
        #expect(page.result("read-b", field: "error") == "CAPSID_API_TIMEOUT")
        #expect(page.activeReads == "0")
    }

    @Test func aDeclaredOversizeBodyIsNotReadAndAnUndeclaredOneIsBounded() {
        let declared = APIReadPage()
        declared.start(declaredLength: 5, maxBytes: 4)
        #expect(declared.result(field: "error") == "CAPSID_API_TOO_LARGE")
        #expect(declared.script.evaluate("String(__seen['read-a'].pulled)") == "0")
        #expect(declared.activeReads == "0")
        #expect(declared.timers == "0")

        let streamed = APIReadPage()
        streamed.start(chunks: [[65, 66, 67], [68, 69]], maxBytes: 4)
        #expect(streamed.result(field: "error") == "CAPSID_API_TOO_LARGE")
        #expect(streamed.script.evaluate("String(__seen['read-a'].cancelled)") == "1")
        #expect(streamed.activeReads == "0")
        #expect(streamed.timers == "0")

        let exact = APIReadPage()
        exact.start(chunks: [[65, 66], [67, 68]], maxBytes: 4)
        #expect(exact.result(field: "value") == "ABCD")
    }

    @Test func authenticationAndNetworkFailuresKeepTheirMeaningAndCleanUp() {
        let refused = APIReadPage()
        refused.start(status: 401)
        #expect(refused.result(field: "error") == "HTTP 401")
        #expect(refused.activeReads == "0")
        #expect(refused.timers == "0")
        let failed = APIReadPage()
        failed.start(stage: "network")
        #expect(failed.result(field: "error") == "network failed")
        #expect(failed.activeReads == "0")
        #expect(failed.timers == "0")
    }
}

@MainActor
private final class HeldContextReads {
    struct Request {
        let frame: String
        let continuation: CheckedContinuation<TokenSeries, any Error>
    }
    var requests: [Request] = []
    var cancelled: [String] = []

    func fetch(_ frame: String) async throws -> TokenSeries {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { requests.append(Request(frame: frame, continuation: $0)) }
        } onCancel: {
            Task { @MainActor in self.cancelled.append(frame) }
        }
    }

    func finish(_ index: Int, used: Int) {
        requests[index].continuation.resume(returning: TokenSeries(window: 200, turns: [.init(ctxTotal: used)], truncated: false))
    }
}

@MainActor
private final class HeldAPIRead {
    var continuation: CheckedContinuation<Data, Never>?
    var nonces: [String] = []
    var aborted: [String] = []
}

@MainActor
struct WebAPICancellationTests {
    @Test func taskCancellationAbortsOnlyItsNonceAndRejectsALateSuccess() async {
        let held = HeldAPIRead()
        let task = Task {
            try await WebAPIReadAbort.run(nonce: "owned-read") { nonce in
                held.nonces.append(nonce)
                return await withCheckedContinuation { held.continuation = $0 }
            } abort: { held.aborted.append($0) }
        }
        for _ in 0..<1_000 {
            if held.continuation != nil { break }
            await Task.yield()
        }
        #expect(held.continuation != nil)
        task.cancel()
        for _ in 0..<1_000 {
            if !held.aborted.isEmpty { break }
            await Task.yield()
        }
        #expect(held.nonces == ["owned-read"])
        #expect(held.aborted == ["owned-read"])
        held.continuation?.resume(returning: Data("late".utf8))
        do {
            _ = try await task.value
            Issue.record("a cancelled read published its late success")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func successfulReadsDoNotSendAnAbort() async throws {
        let held = HeldAPIRead()
        let value = try await WebAPIReadAbort.run(nonce: "done") { _ in
            Data("ok".utf8)
        } abort: { held.aborted.append($0) }
        #expect(value == Data("ok".utf8))
        #expect(held.aborted.isEmpty)
    }
}

@MainActor
struct ContextReadLifetimeTests {
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition(), "the deterministic task did not make progress")
    }

    @Test func changingSessionsCancelsTheOldReadAndItsLateAnswerCannotClearTheNewOne() async {
        let reads = HeldContextReads()
        let model = ContextModel(fetchSeries: reads.fetch, pageReady: { true }, isDemo: { false })
        model.show("a")
        await until { reads.requests.count == 1 }
        model.show("b")
        await until { reads.requests.count == 2 && reads.cancelled == ["a"] }
        reads.finish(0, used: 100)
        // A second hop lets the cancelled task's completion run.
        for _ in 0..<20 { await Task.yield() }
        #expect(model.frameID == "b")
        #expect(model.loading)
        #expect(model.used == nil)
        reads.finish(1, used: 25)
        await until { !model.loading }
        #expect(model.used == 25)
    }

    @Test func returningToTheSameSessionRejectsTheEarlierGeneration() async {
        let reads = HeldContextReads()
        let model = ContextModel(fetchSeries: reads.fetch, pageReady: { true }, isDemo: { false })
        model.show("a")
        await until { reads.requests.count == 1 }
        model.show(nil)
        #expect(!model.loading)
        model.show("a")
        await until { reads.requests.count == 2 }
        reads.finish(1, used: 30)
        await until { !model.loading }
        reads.finish(0, used: 150)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.used == 30)
        #expect(model.failure == nil)
    }

    @Test func aTimeoutEndsLoadingAndAllowsAnExplicitRetry() async {
        let reads = HeldContextReads()
        let model = ContextModel(fetchSeries: reads.fetch, pageReady: { true }, isDemo: { false })
        model.show("a")
        await until { reads.requests.count == 1 }
        reads.requests[0].continuation.resume(throwing: WebAPIError.timedOut)
        await until { !model.loading }
        #expect(model.failure != nil)
        model.refresh()
        await until { reads.requests.count == 2 }
        reads.finish(1, used: 20)
        await until { !model.loading }
        #expect(model.used == 20)
        #expect(model.failure == nil)
    }
}
