// StartRetryTests.swift — the main window reconnects on its own after Claude
// Science stopped answering: the waits between tries, which failures are
// retried, that a try only signs in to a daemon that answers, and that Try
// again or a page coming up ends the tries. Every status and wait is the
// test's own: no real daemon, no real sleeps.
import Foundation
import Testing
@testable import Bench

/// What a test says the daemon and the window are doing.
@MainActor
private final class Scene {
    /// Answers to `status`, in order; nil is "not running" or no answer.
    var answers: [CLIStatus?] = []
    var waits: [Duration] = []
    var probes = 0
    var failed = true
    var attached: [CLIStatus] = []
    /// Set to hold every wait until the test lets it go.
    var holding = false
    var held: [CheckedContinuation<Void, Never>] = []

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

private let daemon = CLIStatus(running: true, activeFrames: 0, activeConversations: 0, version: "0.1.69", port: 8765, pid: 4321)

@MainActor
private func makeRetry(_ scene: Scene) -> StartRetry {
    StartRetry(probe: {
        scene.probes += 1
        return scene.answers.isEmpty ? nil : scene.answers.removeFirst()
    }, wait: { duration in
        scene.waits.append(duration)
        if scene.holding {
            await withCheckedContinuation { scene.held.append($0) }
        } else {
            // Suspends, as a real wait does, so the loop shares the run loop.
            await Task.yield()
        }
    }, stillFailed: { scene.failed }, attach: { scene.attached.append($0) })
}

/// Lets the retry's task run until it stops trying, or gives up.
@MainActor
private func settle(_ retry: StartRetry) async {
    for _ in 0..<500 where retry.isTrying { await Task.yield() }
}

@MainActor
struct StartRetryTests {
    @Test func waitsGrowThenSettleAtAMinuteThenFiveMinutes() {
        let firsts = (0..<4).map { StartRetry.wait(before: $0) }
        #expect(firsts == [.seconds(5), .seconds(10), .seconds(20), .seconds(40)])
        #expect((4..<19).allSatisfy { StartRetry.wait(before: $0) == .seconds(60) })
        #expect(StartRetry.wait(before: 19) == .seconds(300))
        #expect(StartRetry.wait(before: 500) == .seconds(300))
    }

    @Test func onlyAnUnansweredPageIsRetried() {
        for code in [NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost] {
            #expect(StartRetry.isUnreachable(NSError(domain: NSURLErrorDomain, code: code)))
        }
        #expect(!StartRetry.isUnreachable(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(!StartRetry.isUnreachable(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)))
        #expect(!StartRetry.isUnreachable(NSError(domain: "WebKitErrorDomain", code: NSURLErrorTimedOut)))
    }

    @Test func aBusyOrStartingDaemonIsRetriedAMissingToolIsNot() {
        #expect(DaemonError.statusFailed.isTemporary)
        #expect(DaemonError.didNotStart.isTemporary)
        #expect(!DaemonError.cliMissing.isTemporary)
        #expect(!DaemonError.launchFailed("no").isTemporary)
        // The overlay says it keeps trying, so the sentence no longer asks.
        #expect(!DaemonError.statusFailed.sentence.contains("Try again"))
    }

    @Test func asksAfterEachWaitAndSignsInOnceTheDaemonAnswers() async {
        let scene = Scene()
        scene.answers = [nil, nil, daemon]
        let retry = makeRetry(scene)
        retry.begin()
        await settle(retry)
        #expect(scene.waits == [.seconds(5), .seconds(10), .seconds(20)])
        #expect(scene.probes == 3)
        #expect(scene.attached == [daemon])
        #expect(!retry.isTrying)
        #expect(retry.attempt == 3)
    }

    @Test func aSecondBeginWhileTryingDoesNothing() async {
        let scene = Scene()
        scene.holding = true
        let retry = makeRetry(scene)
        retry.begin()
        await Task.yield()
        retry.begin()
        await Task.yield()
        #expect(scene.waits.count == 1)
        scene.answers = [daemon]
        scene.holding = false
        scene.release()
        await settle(retry)
        #expect(scene.attached == [daemon])
    }

    @Test func tryAgainDuringAWaitEndsItWithoutAskingOrSigningIn() async {
        let scene = Scene()
        scene.holding = true
        scene.answers = [daemon]
        let retry = makeRetry(scene)
        retry.begin()
        await Task.yield()
        #expect(retry.isTrying)
        // Try again: the window stops the tries and starts over itself.
        retry.stop(resetting: true)
        #expect(!retry.isTrying)
        #expect(retry.attempt == 0)
        scene.release()
        for _ in 0..<20 { await Task.yield() }
        #expect(scene.probes == 0)
        #expect(scene.attached.isEmpty)
    }

    @Test func aWindowNoLongerFailingIsNotSignedInAgain() async {
        let scene = Scene()
        scene.answers = [daemon]
        scene.failed = false
        let retry = makeRetry(scene)
        retry.begin()
        await settle(retry)
        #expect(scene.probes == 0)
        #expect(scene.attached.isEmpty)
        #expect(!retry.isTrying)
    }

    @Test func aSignInThatFailsAgainKeepsTheWaitsGrowing() async {
        let scene = Scene()
        scene.answers = [nil, daemon]
        let retry = makeRetry(scene)
        retry.begin()
        await settle(retry)
        #expect(scene.attached.count == 1)
        // The sign-in failed too, so the window begins again: no reset.
        scene.answers = [daemon]
        retry.begin()
        await settle(retry)
        #expect(scene.waits == [.seconds(5), .seconds(10), .seconds(20)])
        #expect(scene.attached.count == 2)
    }

    @Test func aStopForAFailureThatWontPassKeepsTheCountButEndsTheTries() async {
        let scene = Scene()
        scene.holding = true
        let retry = makeRetry(scene)
        retry.begin()
        await Task.yield()
        retry.stop(resetting: false)
        #expect(retry.attempt == 1)
        #expect(!retry.isTrying)
        scene.release()
        for _ in 0..<20 { await Task.yield() }
        #expect(scene.probes == 0)
    }
}
