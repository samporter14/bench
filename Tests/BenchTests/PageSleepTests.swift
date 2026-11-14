// PageSleepTests.swift — Claude Science's page sleeps while the main window is
// closed, only when the setting is off: the rule's table (on never sleeps), the
// grace after the window closes, what cancels it, what wakes a sleeping page,
// that a call into the page finishes before it unloads, and that an unload
// happens once per grace. Every page state and wait is the test's own: no real
// web view, no real sleeps.
import Foundation
import Testing
@testable import Bench

/// What a test says the page is doing, and what the sleeper did about it.
@MainActor
private final class Scene {
    var page: PageSleepRule.Page = .loaded
    var unloads = 0
    var wakes = 0
    /// Every wait the sleeper asked for, in order.
    var waits: [Duration] = []
    /// Grace waits are held until the test lets them go; drain polls only yield.
    var held: [CheckedContinuation<Void, Never>] = []

    /// Retry waits after a failed wake, held until `releaseRetry`.
    var heldRetries: [CheckedContinuation<Void, Never>] = []

    func releaseRetry() {
        let waiting = heldRetries
        heldRetries = []
        waiting.forEach { $0.resume() }
    }

    var retryWaits: Int { waits.filter { $0 == PageSleep.wakeRetry }.count }

    var graceWaits: Int { waits.filter { $0 == PageSleepRule.grace }.count }
    var drainPolls: Int { waits.filter { $0 == PageSleep.drainPoll }.count }

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

@MainActor
private func makeSleep(_ scene: Scene, keepLoaded: Bool, windowOpen: Bool) -> PageSleep {
    PageSleep(keepLoaded: keepLoaded, windowOpen: windowOpen,
              page: { scene.page },
              unload: {
                  scene.unloads += 1
                  scene.page = .asleep
              },
              wake: {
                  scene.wakes += 1
                  scene.page = .busy
              },
              wait: { duration in
                  scene.waits.append(duration)
                  if duration == PageSleepRule.grace {
                      await withCheckedContinuation { scene.held.append($0) }
                  } else if duration == PageSleep.wakeRetry {
                      await withCheckedContinuation { scene.heldRetries.append($0) }
                  } else {
                      // Suspends, as a real wait does, so the loop shares the run loop.
                      await Task.yield()
                  }
              })
}

/// What `WebContainer.backToSleep` does when a background wake couldn't sign in.
@MainActor
private func wakeFails(_ sleep: PageSleep, _ scene: Scene) {
    sleep.wakeFailed()
    scene.page = .asleep
    sleep.pageChanged()
}

/// A closed window, the setting off, the page asleep, and an action holding it
/// whose wake has just failed.
@MainActor
private func heldUseAfterAFailedWake(_ scene: Scene) async -> PageSleep {
    scene.page = .asleep
    let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
    sleep.beginUse()
    #expect(scene.wakes == 1)
    wakeFails(sleep, scene)
    await settle()
    return sleep
}

/// Lets the sleeper's tasks run as far as they can.
@MainActor
private func settle() async {
    for _ in 0..<200 { await Task.yield() }
}

@MainActor
struct PageSleepTests {
    // MARK: The rule

    @Test func onNeverSleepsWhateverElseIsGoingOn() {
        for windowOpen in [false, true] {
            for uses in 0...2 {
                for page in [PageSleepRule.Page.loaded, .busy, .asleep] {
                    let decision = PageSleepRule.decide(keepLoaded: true, windowOpen: windowOpen, uses: uses, page: page)
                    #expect(decision != .sleepAfterGrace)
                }
            }
        }
    }

    @Test func offSleepsOnlyALoadedPageNothingWants() {
        func decide(_ windowOpen: Bool, _ uses: Int, _ page: PageSleepRule.Page) -> PageSleepRule.Decision {
            PageSleepRule.decide(keepLoaded: false, windowOpen: windowOpen, uses: uses, page: page)
        }
        #expect(decide(false, 0, .loaded) == .sleepAfterGrace)
        #expect(decide(true, 0, .loaded) == .keep)
        #expect(decide(false, 1, .loaded) == .keep)
        #expect(decide(false, 0, .busy) == .keep)
        #expect(decide(true, 0, .busy) == .keep)
        #expect(decide(false, 0, .asleep) == .keep)
        #expect(decide(true, 0, .asleep) == .wake)
        #expect(decide(false, 1, .asleep) == .wake)
    }

    @Test func theGraceIsLongEnoughToReopenTheWindow() {
        #expect(PageSleepRule.grace == .seconds(45))
    }

    // MARK: The grace

    @Test func aClosedWindowWithTheSettingOffUnloadsOnceAfterTheGrace() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: true)
        sleep.pageChanged()
        #expect(!sleep.isCountingDown)
        sleep.setWindowOpen(false)
        await settle()
        #expect(sleep.isCountingDown)
        #expect(scene.waits == [PageSleepRule.grace])
        #expect(scene.unloads == 0)
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
        #expect(scene.wakes == 0)
        #expect(!sleep.isCountingDown)
        #expect(scene.page == .asleep)
    }

    @Test func onKeepsTheClosedPageLoadedForever() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: true, windowOpen: true)
        sleep.setWindowOpen(false)
        sleep.pageChanged()
        await settle()
        #expect(!sleep.isCountingDown)
        #expect(scene.waits.isEmpty)
        #expect(scene.unloads == 0)
    }

    @Test func reopeningTheWindowDuringTheGraceKeepsThePage() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        #expect(sleep.isCountingDown)
        sleep.setWindowOpen(true)
        #expect(!sleep.isCountingDown)
        scene.release()
        await settle()
        #expect(scene.unloads == 0)
        #expect(scene.wakes == 0)
        #expect(scene.page == .loaded)
    }

    @Test func turningTheSettingBackOnDuringTheGraceKeepsThePage() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        #expect(sleep.isCountingDown)
        sleep.setKeepLoaded(true)
        #expect(!sleep.isCountingDown)
        scene.release()
        await settle()
        #expect(scene.unloads == 0)
        #expect(scene.page == .loaded)
    }

    @Test func aWindowClosedAgainAfterABrokenGraceStartsAFreshOne() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        sleep.setWindowOpen(true)
        sleep.setWindowOpen(false)
        await settle()
        #expect(sleep.isCountingDown)
        #expect(scene.graceWaits == 2)
        // The first wait ending changes nothing; only the second one unloads.
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
    }

    @Test func aPageStillStartingIsNotCountedDownUntilItIsLoaded() async {
        let scene = Scene()
        scene.page = .busy
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        #expect(!sleep.isCountingDown)
        #expect(scene.waits.isEmpty)
        scene.page = .loaded
        sleep.pageChanged()
        await settle()
        #expect(sleep.isCountingDown)
        #expect(scene.waits == [PageSleepRule.grace])
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
    }

    @Test func turningTheSettingOffWithTheWindowAlreadyClosedStartsTheGrace() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: true, windowOpen: false)
        sleep.pageChanged()
        await settle()
        #expect(!sleep.isCountingDown)
        sleep.setKeepLoaded(false)
        await settle()
        #expect(sleep.isCountingDown)
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
    }

    @Test func oneGraceUnloadsOnceHoweverOftenThePageIsReported() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        for _ in 0..<5 {
            sleep.pageChanged()
            await settle()
        }
        #expect(scene.graceWaits == 1)
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
        // Asleep and unwanted: more reports change nothing.
        for _ in 0..<5 { sleep.pageChanged() }
        await settle()
        #expect(scene.unloads == 1)
        #expect(scene.wakes == 0)
        #expect(scene.graceWaits == 1)
    }

    // MARK: Waking

    @Test func aSleepingPageWakesOnceWhenTheWindowOpens() async {
        let scene = Scene()
        scene.page = .asleep
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.setWindowOpen(true)
        #expect(scene.wakes == 1)
        // Waking made it busy; the window's own changes don't wake it again.
        sleep.pageChanged()
        #expect(scene.wakes == 1)
        await settle()
        #expect(scene.unloads == 0)
    }

    @Test func aSleepingPageWakesAtOnceWhenTheSettingIsTurnedOn() {
        let scene = Scene()
        scene.page = .asleep
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.setKeepLoaded(true)
        #expect(scene.wakes == 1)
        #expect(scene.page == .busy)
    }

    @Test func aSleepingPageWakesForAnActionThatNeedsIt() {
        let scene = Scene()
        scene.page = .asleep
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.beginUse()
        #expect(scene.wakes == 1)
        #expect(sleep.uses == 1)
    }

    @Test func aSleepingPageNothingWantsStaysAsleep() async {
        let scene = Scene()
        scene.page = .asleep
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        sleep.pageChanged()
        await settle()
        #expect(scene.wakes == 0)
        #expect(scene.unloads == 0)
        #expect(!sleep.isCountingDown)
    }

    @Test func wakingDuringTheGraceIsNotNeededAndTheGraceIsDropped() async {
        // A page that went to sleep some other way while counting down.
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        #expect(sleep.isCountingDown)
        sleep.beginUse()
        #expect(!sleep.isCountingDown)
        scene.release()
        await settle()
        #expect(scene.unloads == 0)
        #expect(scene.wakes == 0)
    }

    // MARK: Uses

    @Test func aUseHeldKeepsTheClosedPageFromCountingDownUntilItEnds() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.beginUse()
        sleep.pageChanged()
        await settle()
        #expect(!sleep.isCountingDown)
        #expect(scene.waits.isEmpty)
        #expect(!sleep.wantsPageForItself)
        sleep.endUse()
        await settle()
        #expect(sleep.isCountingDown)
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
    }

    @Test func twoUsesKeepThePageUntilTheLastEnds() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.beginUse()
        sleep.beginUse()
        sleep.endUse()
        await settle()
        #expect(!sleep.isCountingDown)
        sleep.endUse()
        await settle()
        #expect(sleep.isCountingDown)
        sleep.endUse()
        #expect(sleep.uses == 0)
        scene.release()
    }

    @Test func wantsThePageForItselfIsTheWindowOrTheSettingNotAnAction() {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        #expect(!sleep.wantsPageForItself)
        sleep.beginUse()
        #expect(!sleep.wantsPageForItself)
        sleep.setWindowOpen(true)
        #expect(sleep.wantsPageForItself)
        sleep.setWindowOpen(false)
        sleep.setKeepLoaded(true)
        #expect(sleep.wantsPageForItself)
    }

    // MARK: Calls into the page

    @Test func aCallUnderWayWhenTheGraceEndsDelaysTheUnloadUntilItFinishes() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        sleep.beginCall()
        scene.release()
        await settle()
        #expect(scene.unloads == 0)
        #expect(scene.drainPolls > 1)
        #expect(sleep.isCountingDown)
        sleep.endCall()
        await settle()
        #expect(scene.unloads == 1)
        #expect(!sleep.isCountingDown)
        #expect(scene.waits.first == PageSleepRule.grace)
        #expect(scene.waits.dropFirst().allSatisfy { $0 == PageSleep.drainPoll })
    }

    @Test func aCallEndingBeforeTheGraceDoesNotDelayTheUnload() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        sleep.beginCall()
        sleep.endCall()
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
        #expect(scene.drainPolls == 0)
    }

    @Test func reopeningTheWindowWhileACallDrainsKeepsThePage() async {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.pageChanged()
        await settle()
        sleep.beginCall()
        scene.release()
        await settle()
        sleep.setWindowOpen(true)
        sleep.endCall()
        await settle()
        #expect(scene.unloads == 0)
        #expect(!sleep.isCountingDown)
    }

    @Test func aCallAloneNeitherWakesASleepingPageNorStartsTheGraceOver() async {
        let scene = Scene()
        scene.page = .asleep
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: false)
        sleep.beginCall()
        await settle()
        #expect(scene.wakes == 0)
        #expect(!sleep.isCountingDown)
        sleep.endCall()
        #expect(sleep.inFlight == 0)

        // Nor does one restart a grace already running.
        scene.page = .loaded
        sleep.pageChanged()
        await settle()
        sleep.beginCall()
        sleep.endCall()
        await settle()
        #expect(scene.graceWaits == 1)
        scene.release()
        await settle()
        #expect(scene.unloads == 1)
    }

    @Test func endingMoreCallsThanWereBeganLeavesNoneInFlight() {
        let scene = Scene()
        let sleep = makeSleep(scene, keepLoaded: false, windowOpen: true)
        sleep.endCall()
        #expect(sleep.inFlight == 0)
        sleep.beginCall()
        #expect(sleep.inFlight == 1)
    }

    // MARK: The setting

    @Test func theSettingIsOnWhenUnsetAndOffWhenSetOff() {
        let scratch = ScratchDefaults.make(prefix: "PageSleepTests")
        defer { scratch.discard() }
        let defaults = scratch.defaults
        #expect(PageSleepSetting.keepsLoaded(defaults))
        defaults.set(false, forKey: SettingsKey.keepPageLoaded)
        #expect(!PageSleepSetting.keepsLoaded(defaults))
        defaults.set(true, forKey: SettingsKey.keepPageLoaded)
        #expect(PageSleepSetting.keepsLoaded(defaults))
        defaults.removeObject(forKey: SettingsKey.keepPageLoaded)
        #expect(PageSleepSetting.keepsLoaded(defaults))
    }

    // MARK: A wake that fails

    @Test func aFailedWakeIsNotTriedAgainWhileTheSameUseIsHeld() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        #expect(scene.wakes == 1)
        #expect(sleep.wakeHeldBack)
        // The page's status changing again, with nothing else changing, is no reason.
        sleep.pageChanged()
        sleep.pageChanged()
        await settle()
        #expect(scene.wakes == 1)
        #expect(scene.page == .asleep)
    }

    @Test func aNewActionTriesTheWakeAgain() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        sleep.beginUse()
        #expect(scene.wakes == 2)
        #expect(!sleep.wakeHeldBack)
    }

    @Test func theWindowOpeningTriesTheWakeAgain() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        sleep.setWindowOpen(true)
        #expect(scene.wakes == 2)
    }

    @Test func theSwitchTurningOnTriesTheWakeAgain() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        sleep.setKeepLoaded(true)
        #expect(scene.wakes == 2)
    }

    @Test func aHeldUseIsTriedAgainOnlyAfterTheSlowRetry() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        #expect(PageSleep.wakeRetry >= .seconds(30))
        #expect(scene.retryWaits == 1)
        scene.releaseRetry()
        await settle()
        #expect(scene.wakes == 2)
        // Failing again waits the whole retry again, never back to back.
        wakeFails(sleep, scene)
        await settle()
        #expect(scene.wakes == 2)
        #expect(scene.retryWaits == 2)
        scene.releaseRetry()
        await settle()
        #expect(scene.wakes == 3)
    }

    @Test func theRetryWakesNothingOnceTheUseHasEnded() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        sleep.endUse()
        scene.releaseRetry()
        await settle()
        #expect(scene.wakes == 1)
        #expect(!sleep.wakeHeldBack)
        #expect(scene.page == .asleep)
    }

    @Test func aRetryOvertakenByANewActionDoesNotWakeTwice() async {
        let scene = Scene()
        let sleep = await heldUseAfterAFailedWake(scene)
        sleep.beginUse()
        #expect(scene.wakes == 2)
        scene.page = .loaded
        sleep.pageChanged()
        scene.releaseRetry()
        await settle()
        #expect(scene.wakes == 2)
    }
}
