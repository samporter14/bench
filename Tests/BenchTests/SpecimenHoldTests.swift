// SpecimenHoldTests.swift — the specimens hold a still while nobody is at the
// Mac: the idle limit (ten minutes, two in Low Power Mode, or the hidden
// default), the first input that brings them back, how often it looks, and
// that it looks only while something on screen could hold. Every clock, idle
// reader and wait is the test's own: no real sleeps, never the real Mac.
import Combine
import Foundation
import Testing
@testable import Bench

/// What a test says the Mac is doing: how long since the last input, whether
/// Low Power Mode is on, and what time the rotation's clock says.
@MainActor
private final class Mac {
    var idle: TimeInterval = 0
    var lowPower = false
    var clock: TimeInterval = 5_000
    var limit: TimeInterval = SpecimenHold.idleLimit
    var waits: [Duration] = []
}

@MainActor
private func makeHold(_ mac: Mac, center: NotificationCenter = NotificationCenter()) -> SpecimenHold {
    SpecimenHold(secondsSinceInput: { mac.idle }, limit: { mac.limit }, lowPower: { mac.lowPower },
                 now: { mac.clock }, wait: { duration in
                    mac.waits.append(duration)
                    // Suspends, as a real wait does, so the loop shares the run loop.
                    await Task.yield()
                }, center: center)
}

@MainActor
struct SpecimenHoldRuleTests {
    @Test func playsUntilTheIdleLimitThenHolds() {
        let mac = Mac()
        let hold = makeHold(mac)
        mac.idle = 0
        hold.look()
        #expect(!hold.holds)
        mac.idle = 10 * 60 - 0.1
        hold.look()
        #expect(!hold.holds)
        mac.idle = 10 * 60
        hold.look()
        #expect(hold.holds)
    }

    @Test func theFirstInputAfterAHoldPlaysAgain() {
        let mac = Mac()
        let hold = makeHold(mac)
        mac.idle = 3_600
        hold.look()
        #expect(hold.holds)
        // Still idle on the next look: still held.
        mac.idle = 3_602
        hold.look()
        #expect(hold.holds)
        // A touch: the idle time starts again from nothing.
        mac.idle = 0.4
        hold.look()
        #expect(!hold.holds)
    }

    @Test func theHoldRemembersWhenItBeganAndKeepsIt() {
        let mac = Mac()
        let hold = makeHold(mac)
        mac.idle = 700
        mac.clock = 5_000
        hold.look()
        #expect(hold.heldAt == 5_000)
        // Later looks, still idle, do not move it.
        mac.clock = 5_060
        mac.idle = 760
        hold.look()
        #expect(hold.heldAt == 5_000)
        // After a return and another long absence it is the new moment.
        mac.idle = 1
        hold.look()
        mac.clock = 9_000
        mac.idle = 800
        hold.look()
        #expect(hold.holds && hold.heldAt == 9_000)
    }

    @Test func lowPowerModeHoldsAfterTwoMinutes() {
        let mac = Mac()
        let hold = makeHold(mac)
        mac.idle = 150
        hold.look()
        #expect(!hold.holds)
        mac.lowPower = true
        hold.look()
        #expect(hold.holds)
        #expect(hold.idleSeconds == SpecimenHold.lowPowerIdleLimit)
        // And the other way: out of Low Power Mode, 150 s is not enough.
        mac.lowPower = false
        hold.look()
        #expect(!hold.holds)
    }

    @Test func lowPowerNeverLengthensAShorterLimit() {
        let mac = Mac()
        mac.limit = 20
        let hold = makeHold(mac)
        mac.lowPower = true
        #expect(hold.idleSeconds == 20)
        mac.lowPower = false
        #expect(hold.idleSeconds == 20)
    }

    @Test func aLookThatChangesNothingTellsNobody() {
        let mac = Mac()
        let hold = makeHold(mac)
        var told: [Bool] = []
        let listening = hold.$holds.dropFirst().sink { told.append($0) }
        hold.look()
        hold.look()
        mac.idle = 900
        hold.look()
        hold.look()
        mac.idle = 0
        hold.look()
        hold.look()
        #expect(told == [true, false])
        listening.cancel()
    }

    @Test func looksOnceAMinuteWhilePlayingAndEveryTwoSecondsWhileHolding() {
        let mac = Mac()
        let hold = makeHold(mac)
        #expect(hold.nextLook == .seconds(60))
        mac.idle = 900
        hold.look()
        #expect(hold.nextLook == .seconds(2))
        mac.idle = 0
        hold.look()
        #expect(hold.nextLook == .seconds(60))
    }

    @Test func theHeldSceneIsTheOneTheRotationWasInThenWhateverTheTimeNow() throws {
        let mac = Mac()
        let hold = makeHold(mac)
        let rotation = Rotation.full
        let then = Date(timeIntervalSinceReferenceDate: 12_345)
        let later = Date(timeIntervalSinceReferenceDate: 12_345 + rotation.cycle / 2)
        let thenScene = rotation.scenes[rotation.scene(at: 12_345).index]
        // Playing: the scene at the date asked about.
        #expect(hold.scene(in: rotation, at: then).name == thenScene.name)
        let laterScene = rotation.scenes[rotation.scene(at: later.timeIntervalSinceReferenceDate).index]
        // The two scenes differ, or what follows proves nothing.
        try #require(thenScene.name != laterScene.name)
        #expect(hold.scene(in: rotation, at: later).name == laterScene.name)
        // Holding since 12 345: that one, at any date.
        mac.clock = 12_345
        mac.idle = 900
        hold.look()
        #expect(hold.scene(in: rotation, at: later).name == thenScene.name)
        // Back: the clock's again.
        mac.idle = 0
        hold.look()
        #expect(hold.scene(in: rotation, at: later).name == laterScene.name)
    }
}

@MainActor
struct SpecimenHoldLimitTests {
    /// What the hold's default limit comes to over a suite holding `value` (nothing for nil).
    private func limit(_ value: Any?) -> TimeInterval {
        let scratch = ScratchDefaults.make(prefix: "SpecimenHoldTests")
        defer { scratch.discard() }
        if let value { scratch.defaults.set(value, forKey: SpecimenHold.idleKey) }
        return SpecimenHold.defaultLimit(scratch.defaults)
    }

    @Test func tenMinutesUnlessTheHiddenDefaultSaysOtherwise() {
        #expect(SpecimenHold.idleLimit == 600)
        #expect(limit(nil) == 600)
        #expect(limit(20) == 20)
        // A command-line `-specimenIdleSeconds 20` arrives as a string.
        #expect(limit("20") == 20)
    }

    @Test func nothingUsableMeansTenMinutes() {
        #expect(limit(0) == 600)
        #expect(limit(-5) == 600)
        #expect(limit("soon") == 600)
    }
}

@MainActor
struct SpecimenHoldWatchingTests {
    /// Lets the looking task run until `done`, a turn of the run loop at a
    /// time. It never waits on a clock: the hold's own wait is the test's.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<1_000 where !done() { await Task.yield() }
    }

    @Test func nothingLooksUntilSomethingIsOnScreen() {
        let mac = Mac()
        let hold = makeHold(mac)
        #expect(!hold.isLooking)
        hold.watch()
        #expect(hold.isLooking)
        hold.unwatch()
        #expect(!hold.isLooking)
    }

    @Test func itLooksAtOnceWhenWatchingBeginsAndStopsWithTheLastView() {
        let mac = Mac()
        mac.idle = 3_600
        let hold = makeHold(mac)
        hold.watch()
        // The Mac had been left alone for an hour: held before any wait.
        #expect(hold.holds)
        // A second view and the first leaving: still looking.
        hold.watch()
        hold.unwatch()
        #expect(hold.isLooking)
        hold.unwatch()
        #expect(!hold.isLooking)
        // More leaving than arriving is no harm.
        hold.unwatch()
        hold.watch()
        #expect(hold.isLooking)
        hold.unwatch()
    }

    @Test func theLoopWaitsThenLooksAndPicksItsWaitFromWhatItFound() async {
        let mac = Mac()
        let hold = makeHold(mac)
        hold.watch()
        await settle { mac.waits.count >= 1 }
        // Playing: it waits a minute, then looks.
        #expect(mac.waits.first == .seconds(60))
        mac.idle = 900
        await settle { hold.holds }
        #expect(hold.holds)
        // Holding: the next wait is the short one.
        await settle { mac.waits.contains(.seconds(2)) }
        #expect(mac.waits.contains(.seconds(2)))
        // An input; the next look brings it back.
        mac.idle = 0.2
        await settle { !hold.holds }
        #expect(!hold.holds)
        hold.unwatch()
    }

    @Test func aChangeOfPowerStateLooksAtOnce() async {
        let mac = Mac()
        let center = NotificationCenter()
        let hold = makeHold(mac, center: center)
        mac.idle = 150
        hold.watch()
        #expect(!hold.holds)
        // Low Power Mode comes on: no input to look at, but the notice says look.
        mac.lowPower = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await settle { hold.holds }
        #expect(hold.holds)
        mac.lowPower = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await settle { !hold.holds }
        #expect(!hold.holds)
        // Once nothing is on screen the notice is no longer listened to.
        hold.unwatch()
        mac.lowPower = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await settle { hold.holds }
        #expect(!hold.holds)
    }
}
