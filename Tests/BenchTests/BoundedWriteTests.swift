// BoundedWriteTests.swift — every write has a deadline (Remote/WriteDeadline.swift).
// The page scripts against a fake daemon whose answers can be made never to come,
// and a clock the test sets off; the Swift deadline against work that never returns.
// Nothing here reaches a real daemon, page or network.
import Foundation
import Testing
@testable import Bench

private let root = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
private let approve = "/api/frames/\(root)/approve-plan"
private let stale = PageScript.Answer(status: 403, body: #"{"code":"csrf_stale"}"#)
private let accepted = PageScript.Answer(status: 200, body: #"{"status":"accepted"}"#)
private let hangs = PageScript.Answer(status: 0, body: "__hang__")
private let hangsAndIgnoresItsSignal = PageScript.Answer(status: 0, body: "__hang-ignore__")

// MARK: The phone's writer

struct SessionWriterDeadlineTests {
    private func run(_ write: RemoteWrite, answers: [String: [PageScript.Answer]], expire: Bool = false)
        -> (raw: String?, requests: [PageScript.Request], script: PageScript) {
        let script = PageScript()
        let arguments = write.arguments.keys.sorted().map { key -> (String, String) in
            let data = (try? JSONSerialization.data(withJSONObject: write.arguments[key]!, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            return (key, String(decoding: data, as: UTF8.self))
        }
        let (raw, requests) = script.runPage(SessionWriterScript.body, arguments: arguments, answers: answers, expire: expire)
        #expect(script.exception == nil)
        return (raw, requests, script)
    }

    @Test func aPostThatNeverAnswersIsUnknownOnceTheTimeIsUp() {
        let made = run(.approvePlan(frame: root), answers: [approve: [hangs]], expire: true)
        #expect(made.raw == #"{"unknown":true}"#)
        #expect(made.requests.map(\.path) == [approve])
        #expect(made.script.abortedSignals == 1)
        #expect(made.script.pendingTimers == 0)
        // Swift reads that as no answer, not as a failure.
        #expect(throws: WebAPIError.timedOut) { try SessionWriterScript.result(of: Data(#"{"unknown":true}"#.utf8)) }
    }

    @Test func beforeTheTimeIsUpItIsStillWaiting() {
        let made = run(.approvePlan(frame: root), answers: [approve: [hangs]])
        #expect(made.raw == nil)
        #expect(made.script.pendingTimers == 1)
        #expect(made.script.abortedSignals == 0)
    }

    @Test func aFetchThatIgnoresItsSignalDoesNotHoldTheBridge() {
        let made = run(.approvePlan(frame: root), answers: [approve: [hangsAndIgnoresItsSignal]], expire: true)
        #expect(made.raw == #"{"unknown":true}"#)
    }

    @Test func theRefreshIsBoundedAndAStaleAnswerIsNotUnknown() throws {
        // The first POST answered 403: nothing was accepted. The refresh never answers, so
        // that 403 is the answer, and no second POST is made.
        let made = run(.approvePlan(frame: root), answers: [approve: [stale], "/api/csrf": [hangs]], expire: true)
        #expect(made.requests.map(\.path) == [approve, "/api/csrf"])
        let result = try SessionWriterScript.result(of: Data(try #require(made.raw).utf8))
        #expect(result.status == 403 && result.code == "csrf_stale" && !result.isUnknown)
        #expect(made.script.abortedSignals == 1)
    }

    @Test func aRefreshThatIgnoresItsSignalIsBoundedToo() throws {
        let made = run(.approvePlan(frame: root), answers: [approve: [stale], "/api/csrf": [hangsAndIgnoresItsSignal]], expire: true)
        #expect(made.requests.map(\.path) == [approve, "/api/csrf"])
        #expect(try SessionWriterScript.result(of: Data(try #require(made.raw).utf8)).status == 403)
    }

    @Test func theSecondPostThatNeverAnswersIsUnknown() {
        let made = run(.approvePlan(frame: root), answers: [approve: [stale, hangs], "/api/csrf": [.init(status: 204, body: "")]], expire: true)
        #expect(made.requests.map(\.path) == [approve, "/api/csrf", approve])
        #expect(made.raw == #"{"unknown":true}"#)
    }

    @Test func everyKindOfWriteIsBounded() {
        let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
        let writes: [(RemoteWrite, String)] = [
            (.answer(frame: root, toolID: "t", answers: ["Q": "A"]), "/api/frames/\(root)/resolve-input"),
            (.cancel(frame: root, toolID: "t"), "/api/frames/\(root)/resolve-input"),
            (.message(frame: root, agent: "a", projectID: "proj_a", text: "Hi", intentID: intent), "/api/request"),
            (.newSession(project: "proj_a", text: "Hi", planMode: true, intentID: intent), "/api/projects/proj_a/request"),
            (.permission(frame: root, requestID: "r", toolID: "t", allow: true), "/api/frames/\(root)/resolve-input"),
            (.planFeedback(frame: root, agent: "a", projectID: "proj_a", text: "Change", intentID: intent), "/api/request"),
        ]
        for (write, path) in writes {
            let made = run(write, answers: [path: [hangs]], expire: true)
            #expect(made.raw == #"{"unknown":true}"#, "\(path)")
        }
    }

    @Test func anAnswerBeforeTheDeadlineLeavesNoTimerBehind() {
        let made = run(.approvePlan(frame: root), answers: [approve: [accepted]])
        #expect(made.raw?.contains(#""bodyStatus":"accepted""#) == true)
        #expect(made.script.pendingTimers == 0)
        #expect(made.script.abortedSignals == 0)
    }

    @Test func theDeadlineIsTheArgumentNotAConstantInThePage() {
        let made = run(.approvePlan(frame: root), answers: [approve: [hangs]])
        #expect(made.script.evaluate("String(__timers[0].ms)") == String(WriteDeadline.milliseconds(WriteDeadline.small)))
        #expect(SessionWriterScript.body.contains("benchBounded(timeoutMS,"))
        #expect(!SessionWriterScript.body.contains("AbortSignal.timeout"))
        #expect(RemoteWrite.approvePlan(frame: root).arguments["timeoutMS"] as? Int == 20_000)
    }

    @Test func everyFetchOfTheWriteCarriesTheSignal() {
        #expect(SessionWriterScript.body.contains(#"fetch("/api/csrf", { credentials: "include", cache: "no-store", signal: signal })"#))
        #expect(SessionWriterScript.body.contains("signal: signal,"))
    }
}

// MARK: The card's approval

struct ApprovePostDeadlineTests {
    private let path = "/api/frames/\(root)/approve-plan"

    private func run(answers: [String: [PageScript.Answer]], expire: Bool = false) -> (raw: String?, requests: [PageScript.Request], script: PageScript) {
        let script = PageScript()
        let (raw, requests) = script.runPage(WebAPIWriteScript.body, arguments: [("path", "\"\(path)\""), ("timeoutMS", "20000")],
                                             answers: answers, expire: expire)
        #expect(script.exception == nil)
        return (raw, requests, script)
    }

    @Test func anApprovalThatIsAnsweredComesBackWhole() throws {
        let made = run(answers: [path: [accepted]])
        let result = try WebAPIWriteScript.result(of: Data(try #require(made.raw).utf8))
        #expect(result == APIWriteResult(status: 200, isJSON: true, code: nil, accepted: true, noPlanAwaiting: false))
        #expect(made.requests.first?.body == "{}")
        #expect(made.requests.first?.csrf == "secret-one")
        #expect(made.script.pendingTimers == 0)
    }

    @Test func aPostThatNeverAnswersIsUnknown() {
        let made = run(answers: [path: [hangs]], expire: true)
        #expect(made.raw == #"{"unknown":true}"#)
        #expect(made.script.abortedSignals == 1)
        #expect(throws: WebAPIError.timedOut) { try WebAPIWriteScript.result(of: Data(#"{"unknown":true}"#.utf8)) }
    }

    @Test func theRefreshIsBoundedAndTheStale403Stands() throws {
        let made = run(answers: [path: [stale], "/api/csrf": [hangs]], expire: true)
        #expect(made.requests.map(\.path) == [path, "/api/csrf"])
        let result = try WebAPIWriteScript.result(of: Data(try #require(made.raw).utf8))
        #expect(result.status == 403 && result.code == "csrf_stale")
    }

    @Test func aStaleSecretIsRefreshedAndTriedOnceMore() throws {
        let made = run(answers: [path: [stale, accepted], "/api/csrf": [.init(status: 204, body: "")]])
        #expect(made.requests.map(\.path) == [path, "/api/csrf", path])
        #expect(try WebAPIWriteScript.result(of: Data(try #require(made.raw).utf8)).accepted)
    }

    @Test func aFetchThatFailsWithNoAnswerIsUnknownToo() {
        let made = run(answers: [:])
        #expect(made.raw == #"{"unknown":true}"#)
    }

    @Test func theScriptKeepsTheCSRFLiteralAndTheDeadline() {
        #expect(WebAPIWriteScript.body.contains(#""/api/csrf""#))
        #expect(WebAPIWriteScript.body.contains("benchBounded(timeoutMS,"))
        #expect(WebAPIWriteScript.body.contains("signal: signal"))
    }

    @Test func aBodyThatIsntOneIsRefused() {
        #expect(throws: WebAPIError.badResponse) { try WebAPIWriteScript.result(of: Data("[]".utf8)) }
        #expect(throws: WebAPIError.badResponse) { try WebAPIWriteScript.result(of: Data(#"{"result":{"status":0}}"#.utf8)) }
    }
}

// MARK: The names and the sizes

struct WriteDeadlineConstantsTests {
    @Test func aSmallWriteHasTwentySecondsInThePageAndSwiftWaitsLonger() {
        #expect(WriteDeadline.small == .seconds(20))
        #expect(WriteDeadline.milliseconds(WriteDeadline.small) == 20_000)
        #expect(WriteDeadline.small + WriteDeadline.grace > WriteDeadline.small)
    }

    @Test func anUploadHasMoreTimeTheBiggerItIs() {
        #expect(WriteDeadline.upload(bytes: 1) == .seconds(60))
        #expect(WriteDeadline.upload(bytes: PhotoImage.maxBytes) == .seconds(60))
        #expect(WriteDeadline.upload(bytes: 10 * 1_048_576) == .seconds(80))
        #expect(WriteDeadline.upload(bytes: UploadFile.maxFileBytes) == .seconds(130))
        #expect(WriteDeadline.upload(bytes: 1_000_000_000) == .seconds(180))
        #expect(WriteDeadline.upload(bytes: -5) == .seconds(60))
    }

    @Test func theUploadScriptIsGivenThatTimeInMilliseconds() {
        let file = UploadFile(data: Data(count: 3_000_000), name: "plate.csv", contentType: "text/csv", kind: .file)
        let arguments = PhotoUploadScript.arguments(project: "proj_a", file: file)
        #expect(arguments["timeoutMS"] as? Int == WriteDeadline.milliseconds(WriteDeadline.upload(bytes: 3_000_000)))
        #expect(PhotoUploadScript.body.contains("benchBounded(timeoutMS,"))
        #expect(!PhotoUploadScript.body.contains("AbortSignal.timeout"))
    }

    @Test func aTurnInTheQueueOutlastsEveryStepInIt() {
        let turn = WriteDeadline.turn()
        #expect(turn > WriteDeadline.settleRead + WriteDeadline.small + WriteDeadline.grace)
        let withFile = WriteDeadline.turn(uploadBytes: [UploadFile.maxFileBytes])
        #expect(withFile > turn + WriteDeadline.upload(bytes: UploadFile.maxFileBytes))
    }

    @Test func milliseconds() {
        #expect(WriteDeadline.milliseconds(.milliseconds(1_500)) == 1_500)
        #expect(WriteDeadline.milliseconds(.seconds(3)) == 3_000)
    }
}

// MARK: The Swift side

@MainActor
struct WriteDeadlineRaceTests {
    /// Work that never returns, as a page that never answers does.
    private func forever() async -> Int {
        await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
    }

    @Test func workThatFinishesFirstWins() async {
        let raced = await WriteDeadline.race(.seconds(30)) { 7 }
        guard case .finished(7) = raced else { Issue.record("not finished: \(raced)"); return }
    }

    @Test func workThatNeverReturnsTimesOut() async {
        let raced = await WriteDeadline.race(.milliseconds(30)) { await self.forever() }
        guard case .timedOut = raced else { Issue.record("not timed out: \(raced)"); return }
    }

    @Test func aClockOfTheTestsOwnEndsTheWaitAtOnce() async {
        let raced = await WriteDeadline.race(.seconds(3_600), wait: { _ in }) { await self.forever() }
        guard case .timedOut = raced else { Issue.record("not timed out: \(raced)"); return }
    }

    @Test func noLimitMeansNoTimer() async {
        let raced = await WriteDeadline.race(nil) { 3 }
        guard case .finished(3) = raced else { Issue.record("not finished: \(raced)"); return }
    }

    @Test func aCancelledCallerEndsTheWaitAtOnce() async {
        let task = Task { @MainActor in await WriteDeadline.race(.seconds(3_600)) { await self.forever() } }
        await Task.yield()
        task.cancel()
        guard case .cancelled = await task.value else { Issue.record("not cancelled"); return }
    }

    @Test func aCancelThatPropagatesLeavesTheWorkItsAnswer() async {
        // Work under way can't be taken back: it is told, and waited for.
        let sawIt = Flag()
        let task = Task { @MainActor in
            await WriteDeadline.race(.seconds(3_600), cancel: .propagate) { () async -> Int in
                while !Task.isCancelled { await Task.yield() }
                sawIt.on = true
                return 9
            }
        }
        await Task.yield()
        task.cancel()
        guard case .finished(9) = await task.value else { Issue.record("not finished"); return }
        #expect(sawIt.on)
    }

    @Test func aCancelThatIsIgnoredChangesNothing() async {
        let task = Task { @MainActor in
            await WriteDeadline.race(.seconds(3_600), cancel: .ignore) { () async -> Int in
                try? await Task.sleep(for: .milliseconds(20))
                return 5
            }
        }
        await Task.yield()
        task.cancel()
        guard case .finished(5) = await task.value else { Issue.record("not finished"); return }
    }

    @Test func aBridgeCallThatNeverReturnsIsAnUnknownOutcome() async {
        await #expect(throws: WebAPIError.timedOut) {
            try await WriteDeadline.bridge(.milliseconds(30)) { () async throws -> Int in await self.forever() }
        }
    }

    @Test func aBridgeCallThatReturnsIsPassedOn() async throws {
        let value = try await WriteDeadline.bridge(.seconds(30)) { () async throws -> Int in 11 }
        #expect(value == 11)
    }

    @Test func aBridgeCallsOwnErrorIsPassedOnAsItIs() async {
        await #expect(throws: WebAPIError.notReady) {
            try await WriteDeadline.bridge(.seconds(30)) { () async throws -> Int in throw WebAPIError.notReady }
        }
    }

    @Test func aBridgeCallIsNotTakenBackByItsCallersCancel() async throws {
        // A write in the page has gone; cancelling the caller doesn't un-send it, so it is waited for.
        let task = Task { @MainActor in
            try await WriteDeadline.bridge(.seconds(30)) { () async throws -> Int in
                try? await Task.sleep(for: .milliseconds(20))
                return 4
            }
        }
        await Task.yield()
        task.cancel()
        #expect(try await task.value == 4)
    }
}

@MainActor
private final class Flag {
    var on = false
}
