// RemoteBudgetTests.swift — what a paired device may ask of Bench: the token
// bucket, the routes' costs, two file transfers at a time, Open on Mac once
// every 3 s, three test pushes a minute and two event streams a device. Pure:
// made-up devices and a made-up clock.
import Foundation
import Testing
@testable import Bench

private let start = Date(timeIntervalSince1970: 1_791_833_400)
private let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

struct RequestBucketTests {
    @Test func aHundredAndTwentyAtOnceThenTwoASecond() {
        var bucket = RequestBucket()
        for _ in 0..<120 {
            let spent = bucket.spend(1, device: "phone", at: start)
            #expect(spent == nil)
        }
        // The 121st waits a second; another device has its own.
        #expect(bucket.spend(1, device: "phone", at: start) == 1)
        #expect(bucket.spend(1, device: "tablet", at: start) == nil)
        // Half a second refills one.
        #expect(bucket.spend(1, device: "phone", at: start.addingTimeInterval(0.5)) == nil)
        #expect(bucket.spend(1, device: "phone", at: start.addingTimeInterval(0.5)) == 1)
        // A minute refills it all, and no more.
        let later = start.addingTimeInterval(120)
        for _ in 0..<120 { _ = bucket.spend(1, device: "phone", at: later) }
        #expect(bucket.spend(1, device: "phone", at: later) != nil)
    }

    @Test func aDearRouteWaitsLongerAndSpendsNothingWhenRefused() {
        var bucket = RequestBucket()
        for _ in 0..<11 { _ = bucket.spend(10, device: "phone", at: start) }
        // 10 tokens left: one more download fits, the next wants 10 more (5 s).
        #expect(bucket.spend(10, device: "phone", at: start) == nil)
        #expect(bucket.spend(10, device: "phone", at: start) == 5)
        #expect(bucket.spend(10, device: "phone", at: start) == 5)
        // Refused tries spent nothing: 5 s later it fits.
        #expect(bucket.spend(10, device: "phone", at: start.addingTimeInterval(5)) == nil)
    }

    @Test func aClockThatGoesBackRefillsNothing() {
        var bucket = RequestBucket()
        for _ in 0..<120 { _ = bucket.spend(1, device: "phone", at: start) }
        #expect(bucket.spend(1, device: "phone", at: start.addingTimeInterval(-30)) != nil)
    }

    @Test func eachRouteCostsWhatItMakesBenchDo() {
        #expect(RemoteRoute.state.cost == 1)
        #expect(RemoteRoute.session(id).cost == 1)
        #expect(RemoteRoute.events.cost == 1)
        #expect(RemoteRoute.files(.list(session: id)).cost == 1)
        #expect(RemoteRoute.history(id).cost == 3)
        #expect(RemoteRoute.turn(id, 4).cost == 3)
        #expect(RemoteRoute.files(.thumb(version: "v")).cost == 3)
        #expect(RemoteRoute.files(.text(version: "v")).cost == 3)
        #expect(RemoteRoute.files(.download(version: "v")).cost == 10)
        #expect(RemoteRoute.files(.download(version: "v")).isTransfer)
        #expect(RemoteRoute.files(.thumb(version: "v")).isTransfer)
        #expect(!RemoteRoute.files(.list(session: id)).isTransfer)
        #expect(!RemoteRoute.history(id).isTransfer)
    }
}

struct DeviceBudgetsTests {
    private let download = RemoteRoute.files(.download(version: "v1"))
    private let thumb = RemoteRoute.files(.thumb(version: "v2"))

    @Test func twoTransfersAtOnceAndTheThirdIsBusy() {
        var budgets = DeviceBudgets()
        #expect(budgets.admit(download, device: "phone", at: start) == .go(transfer: true))
        #expect(budgets.admit(thumb, device: "phone", at: start) == .go(transfer: true))
        #expect(budgets.admit(download, device: "phone", at: start) == .refuse(error: "busy", retryAfter: 1))
        // Not the routes that aren't transfers, nor another device.
        #expect(budgets.admit(.state, device: "phone", at: start) == .go(transfer: false))
        #expect(budgets.admit(download, device: "tablet", at: start) == .go(transfer: true))
        // One done: one more may start.
        budgets.finishTransfer(device: "phone")
        #expect(budgets.transfersUnderWay("phone") == 1)
        #expect(budgets.admit(download, device: "phone", at: start) == .go(transfer: true))
    }

    @Test func busySpendsNothing() {
        var budgets = DeviceBudgets()
        _ = budgets.admit(download, device: "phone", at: start)
        _ = budgets.admit(download, device: "phone", at: start)
        // Refused as busy many times: the bucket still has its 100.
        for _ in 0..<50 { _ = budgets.admit(download, device: "phone", at: start) }
        for _ in 0..<100 {
            let verdict = budgets.admit(.state, device: "phone", at: start)
            #expect(verdict == .go(transfer: false))
        }
        #expect(budgets.admit(.state, device: "phone", at: start) == .refuse(error: "slowDown", retryAfter: 1))
    }

    @Test func overBudgetIsSlowDownWithItsWait() {
        var budgets = DeviceBudgets()
        for n in 0..<12 {
            let verdict = budgets.admit(download, device: "phone", at: start)
            #expect(verdict == .go(transfer: true), "download \(n)")
            budgets.finishTransfer(device: "phone")
        }
        #expect(budgets.admit(download, device: "phone", at: start) == .refuse(error: "slowDown", retryAfter: 5))
        #expect(budgets.admit(.history(id), device: "phone", at: start) == .refuse(error: "slowDown", retryAfter: 2))
        #expect(budgets.transfersUnderWay("phone") == 0)
    }

    @Test func openOnMacOnceEveryThreeSeconds() {
        var budgets = DeviceBudgets()
        #expect(budgets.admit(.openSession(id), device: "phone", at: start) == .go(transfer: false))
        #expect(budgets.admit(.openSession(id), device: "phone", at: start.addingTimeInterval(2)) == .refuse(error: "slowDown", retryAfter: 1))
        #expect(budgets.admit(.openSession(id), device: "tablet", at: start.addingTimeInterval(2)) == .go(transfer: false))
        #expect(budgets.admit(.openSession(id), device: "phone", at: start.addingTimeInterval(3)) == .go(transfer: false))
    }

    @Test func threeTestPushesAMinute() {
        var budgets = DeviceBudgets()
        for second in [0.0, 10, 20] {
            let verdict = budgets.admit(.push(.test), device: "phone", at: start.addingTimeInterval(second))
            #expect(verdict == .go(transfer: false))
        }
        #expect(budgets.admit(.push(.test), device: "phone", at: start.addingTimeInterval(30)) == .refuse(error: "slowDown", retryAfter: 30))
        // The other push routes aren't held to it.
        #expect(budgets.admit(.push(.prefs), device: "phone", at: start.addingTimeInterval(30)) == .go(transfer: false))
        // A minute after the first, one more.
        #expect(budgets.admit(.push(.test), device: "phone", at: start.addingTimeInterval(60)) == .go(transfer: false))
        #expect(budgets.admit(.push(.test), device: "phone", at: start.addingTimeInterval(61)) == .refuse(error: "slowDown", retryAfter: 9))
    }

    @Test func aRouteWindowRefusalSpendsNothingFromTheBucket() {
        var budgets = DeviceBudgets()
        _ = budgets.admit(.openSession(id), device: "phone", at: start)
        for _ in 0..<200 { _ = budgets.admit(.openSession(id), device: "phone", at: start) }
        for _ in 0..<119 {
            let verdict = budgets.admit(.state, device: "phone", at: start)
            #expect(verdict == .go(transfer: false))
        }
    }
}

struct StreamCapTests {
    private func stream(_ id: Int, _ device: String, _ second: Double) -> StreamCap.Stream {
        StreamCap.Stream(id: id, device: device, opened: start.addingTimeInterval(second))
    }

    @Test func aThirdStreamFromOneDeviceClosesItsOwnOldest() {
        let open = [stream(1, "a", 0), stream(2, "b", 1), stream(3, "a", 2)]
        #expect(StreamCap.toClose(open, for: "a") == [1])
        #expect(StreamCap.toClose(open, for: "b").isEmpty)
        #expect(StreamCap.toClose(open, for: "c").isEmpty)
    }

    @Test func oneDeviceCantPushOutAnothers() {
        // Device a reconnecting over and over only ever closes its own.
        var open = [stream(1, "b", 0), stream(2, "b", 1)]
        var next = 3
        for second in 2..<20 {
            let closing = StreamCap.toClose(open, for: "a")
            #expect(!closing.contains(1) && !closing.contains(2))
            open.removeAll { closing.contains($0.id) }
            open.append(stream(next, "a", Double(second)))
            next += 1
        }
        #expect(open.filter { $0.device == "a" }.count == 2)
        #expect(open.filter { $0.device == "b" }.count == 2)
    }

    @Test func eightInAllTheOldestGoes() {
        let open = (0..<8).map { stream($0, "d\($0 / 2)", Double($0)) }
        #expect(StreamCap.toClose(open, for: "new") == [0])
        // Its own two first, then nothing more needed.
        #expect(StreamCap.toClose(open, for: "d3") == [6])
    }
}
