// RemoteAuthTests.swift — the pairing code and the devices, with an
// in-memory store: nothing here reads or writes the devices file.
import Foundation
import Testing
@testable import Bench

@MainActor
struct RemoteAuthTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Codes come from a counter, so each new one is known.
    private func auth(store: MemoryDeviceStore = MemoryDeviceStore()) -> RemoteAuth {
        var next = 100_000
        return RemoteAuth(store: store, makeDigits: {
            next += 1
            return String(next)
        })
    }

    private func token(_ result: PairingResult) -> String? {
        if case .paired(let token, _) = result { token } else { nil }
    }

    // MARK: Tokens

    @Test func tokensAre32RandomBytesInBase64URL() {
        let a = RemoteToken.make(), b = RemoteToken.make()
        #expect(a.count == 43)
        #expect(RemoteToken.isWellFormed(a))
        #expect(a != b)
        #expect(!a.contains("=") && !a.contains("+") && !a.contains("/"))
        #expect(!RemoteToken.isWellFormed(a + "x"))
        #expect(!RemoteToken.isWellFormed(String(a.dropLast()) + "!"))
    }

    @Test func aTokenIsCheckedAgainstItsHash() {
        let token = RemoteToken.make()
        let hash = RemoteToken.hash(token)
        #expect(hash.count == 32)
        #expect(RemoteToken.matches(RemoteToken.hash(token), hash))
        #expect(!RemoteToken.matches(RemoteToken.hash(RemoteToken.make()), hash))
        #expect(!RemoteToken.matches(hash.prefix(31), hash))
    }

    @Test func aPairedDeviceIsFoundByItsTokenAndOnlyItsHashIsStored() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let code = auth.issueCode(now: start)
        let result = auth.pair(code: code.digits, name: "Pat's iPhone", now: start)
        guard case .paired(let token, let device) = result else {
            Issue.record("not paired: \(result)")
            return
        }
        #expect(auth.device(forToken: token) == device)
        #expect(auth.device(forToken: RemoteToken.make()) == nil)
        #expect(auth.device(forToken: "not a token") == nil)
        #expect(device.name == "Pat's iPhone")
        #expect(device.tokenHash == RemoteToken.hash(token))
        let stored = String(decoding: store.data ?? Data(), as: UTF8.self)
        #expect(!stored.contains(token))
        #expect(stored.contains(RemoteToken.hash(token).base64EncodedString()))

        // A second Bench reading the same store knows the device.
        let again = RemoteAuth(store: store)
        again.load()
        #expect(again.device(forToken: token)?.id == device.id)
    }

    // MARK: The code

    @Test func thereIsNoCodeUntilSettingsShowsOne() {
        let auth = auth()
        #expect(auth.code == nil)
        #expect(auth.pair(code: "100001", name: "x", now: start) == .refused(.noCode))
    }

    @Test func theCodeIsSixDigits() {
        for _ in 0..<50 {
            let digits = RemoteAuth.randomDigits()
            #expect(digits.count == 6)
            #expect(digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber))
        }
    }

    @Test func theCodeExpiresAfterTenMinutes() {
        let auth = auth()
        let code = auth.issueCode(now: start)
        #expect(code.expiresAt == start.addingTimeInterval(600))
        // Asked again within the ten minutes: the same code.
        #expect(auth.issueCode(now: start.addingTimeInterval(599)) == code)
        #expect(auth.pair(code: code.digits, name: "x", now: start.addingTimeInterval(600)) == .refused(.expired))
        #expect(auth.code == nil)
        #expect(auth.devices.isEmpty)
        // A new one after.
        let next = auth.issueCode(now: start.addingTimeInterval(601))
        #expect(next.digits != code.digits)
        #expect(token(auth.pair(code: next.digits, name: "x", now: start.addingTimeInterval(602))) != nil)
    }

    @Test func fiveWrongTriesAndTheCodeIsGone() {
        let auth = auth()
        let code = auth.issueCode(now: start)
        for n in 1...4 {
            #expect(auth.pair(code: "000000", name: "x", now: start) == .refused(.wrongCode))
            #expect(auth.code?.wrongTries == n)
        }
        // The fifth is wrong too, and wears the code out.
        #expect(auth.pair(code: "000000", name: "x", now: start) == .refused(.wrongCode))
        #expect(auth.code == nil)
        // The sixth waits (429), and the right code is no good now.
        #expect(auth.pair(code: "000000", name: "x", now: start) == .refused(.tooManyTries))
        #expect(auth.pair(code: code.digits, name: "x", now: start.addingTimeInterval(1)) == .refused(.tooManyTries))
        // Settings shows a new one; after the wait it pairs.
        let next = auth.issueCode(now: start.addingTimeInterval(2))
        #expect(next.digits != code.digits)
        #expect(auth.pair(code: next.digits, name: "x", now: start.addingTimeInterval(10)) == .refused(.tooManyTries))
        #expect(token(auth.pair(code: next.digits, name: "x", now: start.addingTimeInterval(RemoteAuth.lockout + 1))) != nil)
    }

    @Test func fourWrongTriesStillLeaveTheCode() {
        let auth = auth()
        let code = auth.issueCode(now: start)
        for _ in 1...4 { _ = auth.pair(code: "999999", name: "x", now: start) }
        #expect(token(auth.pair(code: code.digits, name: "x", now: start)) != nil)
    }

    @Test func aCodeIsUsedOnce() {
        let auth = auth()
        let code = auth.issueCode(now: start)
        #expect(token(auth.pair(code: code.digits, name: "First", now: start)) != nil)
        #expect(auth.code == nil)
        #expect(auth.pair(code: code.digits, name: "Second", now: start) == .refused(.noCode))
        #expect(auth.devices.map(\.name) == ["First"])
        // The next device gets the next code.
        let next = auth.issueCode(now: start)
        #expect(next.digits != code.digits)
    }

    @Test func theDemoCodeIsFixed() {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        #expect(auth.issueCode(now: start).digits == "000000")
        #expect(token(auth.pair(code: "000000", name: "a", now: start)) != nil)
        #expect(token(auth.pair(code: "000000", name: "b", now: start.addingTimeInterval(86_400))) != nil)
        for _ in 1...5 { #expect(auth.pair(code: "123456", name: "x", now: start) == .refused(.wrongCode)) }
        #expect(auth.pair(code: "000000", name: "x", now: start) == .refused(.tooManyTries))
        #expect(auth.code?.digits == "000000")
        #expect(token(auth.pair(code: "000000", name: "c", now: start.addingTimeInterval(RemoteAuth.lockout))) != nil)
    }

    // MARK: Devices

    @Test func removingADeviceEndsItsToken() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let first = token(auth.pair(code: auth.issueCode(now: start).digits, name: "One", now: start))!
        let second = token(auth.pair(code: auth.issueCode(now: start).digits, name: "Two", now: start))!
        let one = auth.device(forToken: first)!
        auth.remove(one.id)
        #expect(auth.device(forToken: first) == nil)
        #expect(auth.device(forToken: second)?.name == "Two")
        let reread = RemoteAuth(store: store)
        reread.load()
        #expect(reread.devices.map(\.name) == ["Two"])
    }

    @Test func removeAllEmptiesTheStore() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let token = token(auth.pair(code: auth.issueCode(now: start).digits, name: "One", now: start))!
        auth.removeAll()
        #expect(auth.devices.isEmpty)
        #expect(store.data == nil)
        #expect(auth.device(forToken: token) == nil)
    }

    @Test func aStoreThatFailsPairsNothing() {
        let store = MemoryDeviceStore()
        store.failsToSave = true
        let auth = auth(store: store)
        let code = auth.issueCode(now: start)
        #expect(auth.pair(code: code.digits, name: "x", now: start) == .refused(.storeFailed))
        #expect(auth.devices.isEmpty)
    }

    @Test func namesAreCleaned() {
        #expect(RemoteDevice.cleanName("  Pat's\n iPhone\u{0007} ") == "Pat's iPhone")
        #expect(RemoteDevice.cleanName("") == "Unnamed device")
        #expect(RemoteDevice.cleanName("\u{0000}\u{001B}") == "Unnamed device")
        #expect(RemoteDevice.cleanName(String(repeating: "x", count: 500)).count == RemoteDevice.nameLimit)
    }

    @Test func lastSeenReachesTheStoreNowAndThen() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let token = token(auth.pair(code: auth.issueCode(now: start).digits, name: "One", now: start))!
        let id = auth.device(forToken: token)!.id
        let saved = store.data
        // A minute on: in memory, not stored.
        auth.touch(id, now: start.addingTimeInterval(90))
        #expect(auth.devices.first?.lastSeen == start.addingTimeInterval(90))
        #expect(store.data == saved)
        // Five minutes on: stored.
        auth.touch(id, now: start.addingTimeInterval(400))
        #expect(store.data != saved)
        let reread = RemoteAuth(store: store)
        reread.load()
        #expect(reread.devices.first?.lastSeen == start.addingTimeInterval(400))
    }
}
