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
        #expect(auth.device(forToken: token, now: start) == device)
        #expect(auth.device(forToken: RemoteToken.make(), now: start) == nil)
        #expect(auth.device(forToken: "not a token", now: start) == nil)
        #expect(device.name == "Pat's iPhone")
        #expect(device.tokenHash == RemoteToken.hash(token))
        let stored = String(decoding: store.data ?? Data(), as: UTF8.self)
        #expect(!stored.contains(token))
        #expect(stored.contains(RemoteToken.hash(token).base64EncodedString()))

        // A second Bench reading the same store knows the device.
        let again = RemoteAuth(store: store)
        again.load(now: start)
        #expect(again.device(forToken: token, now: start)?.id == device.id)
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
        let one = auth.device(forToken: first, now: start)!
        auth.remove(one.id)
        #expect(auth.device(forToken: first, now: start) == nil)
        #expect(auth.device(forToken: second, now: start)?.name == "Two")
        let reread = RemoteAuth(store: store)
        reread.load(now: start)
        #expect(reread.devices.map(\.name) == ["Two"])
    }

    @Test func removeAllEmptiesTheStore() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let token = token(auth.pair(code: auth.issueCode(now: start).digits, name: "One", now: start))!
        auth.removeAll()
        #expect(auth.devices.isEmpty)
        #expect(store.data == nil)
        #expect(auth.device(forToken: token, now: start) == nil)
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
        let id = auth.device(forToken: token, now: start)!.id
        let saved = store.data
        // A minute on: in memory, not stored.
        auth.touch(id, now: start.addingTimeInterval(90))
        #expect(auth.devices.first?.lastSeen == start.addingTimeInterval(90))
        #expect(store.data == saved)
        // Five minutes on: stored.
        auth.touch(id, now: start.addingTimeInterval(400))
        #expect(store.data != saved)
        let reread = RemoteAuth(store: store)
        reread.load(now: start)
        #expect(reread.devices.first?.lastSeen == start.addingTimeInterval(400))
    }
}

// MARK: Guessing the code, expiry, prefs, the login (since the 0.4.0 review)

@MainActor
struct RemoteAuthHardeningTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

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

    /// Five wrong tries at `at`: the code wears out.
    private func wearOut(_ auth: RemoteAuth, at time: Date) {
        _ = auth.issueCode(now: time)
        for _ in 1...RemoteAuth.maxWrongTries { _ = auth.pair(code: "000000", name: "x", now: time) }
    }

    private func pairs(_ auth: RemoteAuth, at time: Date) -> Bool {
        guard let code = auth.code else { return false }
        return token(auth.pair(code: code.digits, name: "x", now: time)) != nil
    }

    @Test func aWornOutCodeIsNotReplacedUntilAsked() {
        let auth = auth()
        _ = auth.codeForSettings(now: start)
        wearOut(auth, at: start)
        #expect(auth.code == nil)
        #expect(auth.wornOut)
        // Settings shows none by itself, now or after the wait.
        #expect(auth.codeForSettings(now: start) == nil)
        #expect(auth.codeForSettings(now: start.addingTimeInterval(3_600)) == nil)
        #expect(auth.pair(code: "100002", name: "x", now: start.addingTimeInterval(3_600)) == .refused(.noCode))
        // New Code.
        let fresh = auth.issueCode(now: start.addingTimeInterval(3_600))
        #expect(!auth.wornOut)
        #expect(auth.codeForSettings(now: start.addingTimeInterval(3_600)) == fresh)
    }

    @Test func anExpiredCodeIsStillReplacedBySettings() {
        let auth = auth()
        let first = auth.codeForSettings(now: start)
        let next = auth.codeForSettings(now: start.addingTimeInterval(RemoteAuth.codeLifetime + 1))
        #expect(next != nil && next != first)
    }

    @Test func theWaitsGrowThirtySecondsTwoMinutesTenMinutes() {
        let auth = auth()
        var now = start
        for (round, wait) in [30.0, 120, 600, 600].enumerated() {
            wearOut(auth, at: now)
            _ = auth.issueCode(now: now)
            #expect(auth.pair(code: "000000", name: "x", now: now.addingTimeInterval(wait - 1)) == .refused(.tooManyTries),
                    "round \(round)")
            now = now.addingTimeInterval(wait)
        }
        #expect(RemoteAuth.lockout(after: 0) == 30)
        #expect(RemoteAuth.lockout(after: 1) == 120)
        #expect(RemoteAuth.lockout(after: 7) == 600)
    }

    @Test func aPairingStartsTheWaitsAgain() {
        let auth = auth()
        wearOut(auth, at: start)
        var now = start.addingTimeInterval(30)
        wearOut(auth, at: now)
        now = now.addingTimeInterval(120)
        _ = auth.issueCode(now: now)
        #expect(pairs(auth, at: now))
        wearOut(auth, at: now)
        // 30 s again, not 10 minutes.
        _ = auth.issueCode(now: now)
        #expect(pairs(auth, at: now.addingTimeInterval(30)))
    }

    @Test func anHourWithoutAWrongTryStartsTheWaitsAgain() {
        let auth = auth()
        wearOut(auth, at: start)
        wearOut(auth, at: start.addingTimeInterval(30))
        // The next would be 10 minutes; after an hour without a wrong try it is 30 s.
        let later = start.addingTimeInterval(30 + RemoteAuth.lockoutMemory + 1)
        wearOut(auth, at: later)
        _ = auth.issueCode(now: later)
        #expect(pairs(auth, at: later.addingTimeInterval(30)))
    }

    @Test func theDemoKeepsItsCodeButWaitsLongerToo() {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        for _ in 1...5 { _ = auth.pair(code: "123456", name: "x", now: start) }
        let second = start.addingTimeInterval(30)
        for _ in 1...5 { _ = auth.pair(code: "123456", name: "x", now: second) }
        #expect(!auth.wornOut)
        #expect(auth.code?.digits == "000000")
        #expect(auth.pair(code: "000000", name: "x", now: second.addingTimeInterval(119)) == .refused(.tooManyTries))
        #expect(token(auth.pair(code: "000000", name: "x", now: second.addingTimeInterval(120))) != nil)
    }

    // MARK: Expiry

    @Test func aDeviceNotSeenForSixtyDaysIsNoLongerPaired() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let kept = token(auth.pair(code: auth.issueCode(now: start).digits, name: "Kept", now: start))!
        // The lost one is paired ten days later and never seen again.
        let later = start.addingTimeInterval(10 * 86_400)
        let lost = token(auth.pair(code: auth.issueCode(now: later).digits, name: "Lost", now: later))!
        let keptID = auth.device(forToken: kept, now: start.addingTimeInterval(50 * 86_400))!.id
        auth.touch(keptID, now: start.addingTimeInterval(50 * 86_400))
        // 59 days after it was last seen: still paired.
        let almost = later.addingTimeInterval(59 * 86_400)
        #expect(auth.device(forToken: lost, now: almost)?.name == "Lost")
        // 60: its token stops working, and it leaves the list and the file.
        let gone = later.addingTimeInterval(RemoteAuth.expiry)
        #expect(auth.device(forToken: lost, now: gone) == nil)
        #expect(auth.devices.map(\.name) == ["Kept"])
        let reread = RemoteAuth(store: MemoryDeviceStore(data: store.data))
        reread.load(now: gone)
        #expect(reread.devices.map(\.name) == ["Kept"])
        #expect(auth.device(forToken: kept, now: gone)?.name == "Kept")
    }

    @Test func expiredDevicesLeaveTheListOnTheNextLoad() throws {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        _ = token(auth.pair(code: auth.issueCode(now: start).digits, name: "Old", now: start))
        let saves = store.saves
        let reread = RemoteAuth(store: store)
        reread.load(now: start.addingTimeInterval(RemoteAuth.expiry - 1))
        #expect(reread.devices.count == 1)
        #expect(store.saves == saves)
        let late = RemoteAuth(store: store)
        late.load(now: start.addingTimeInterval(RemoteAuth.expiry))
        #expect(late.devices.isEmpty)
        #expect(store.saves == saves + 1)
        let data = try #require(store.data)
        #expect((try JSONSerialization.jsonObject(with: data) as? [Any])?.isEmpty == true)
    }

    @Test func aDeviceNeverSeenCountsFromWhenItWasPaired() {
        let device = RemoteDevice(id: "d", name: "x", tokenHash: Data(count: 32), pairedAt: start, lastSeen: nil)
        #expect(!device.isExpired(at: start.addingTimeInterval(RemoteAuth.expiry - 1)))
        #expect(device.isExpired(at: start.addingTimeInterval(RemoteAuth.expiry)))
        var seen = device
        seen.lastSeen = start.addingTimeInterval(30 * 86_400)
        #expect(!seen.isExpired(at: start.addingTimeInterval(RemoteAuth.expiry)))
    }

    // MARK: Push prefs

    @Test func prefsReachTheFileAtMostOnceASecond() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        _ = token(auth.pair(code: auth.issueCode(now: start).digits, name: "Phone", now: start))
        let before = store.saves
        func set(_ names: Bool, at second: Double) {
            auth.updatePushSoon({ _ in RemoteDevicePush(subscription: nil, prefs: PushPrefs(names: names)) },
                                now: start.addingTimeInterval(second))
        }
        // The first at once.
        set(true, at: 10)
        #expect(store.saves == before + 1)
        // The next within the second: in memory now, in the file later.
        set(false, at: 10.2)
        set(true, at: 10.4)
        set(false, at: 10.6)
        #expect(store.saves == before + 1)
        #expect(auth.devices.first?.push?.prefs.names == false)
        #expect(auth.pushWaiting)
        auth.savePush(now: start.addingTimeInterval(11))
        #expect(store.saves == before + 2)
        #expect(!auth.pushWaiting)
        let reread = RemoteAuth(store: MemoryDeviceStore(data: store.data))
        reread.load(now: start.addingTimeInterval(11))
        #expect(reread.devices.first?.push?.prefs.names == false)
        // Nothing waiting: nothing written.
        auth.savePush(now: start.addingTimeInterval(12))
        #expect(store.saves == before + 2)
        // The same prefs again change nothing.
        set(false, at: 20)
        #expect(store.saves == before + 2)
    }

    @Test func anotherWriteCarriesPrefsHeldBack() {
        let store = MemoryDeviceStore()
        let auth = auth(store: store)
        let phone = token(auth.pair(code: auth.issueCode(now: start).digits, name: "Phone", now: start))!
        auth.updatePushSoon({ _ in RemoteDevicePush(subscription: nil, prefs: PushPrefs(names: true)) }, now: start)
        auth.updatePushSoon({ _ in RemoteDevicePush(subscription: nil, prefs: PushPrefs(finishes: true)) }, now: start)
        #expect(auth.pushWaiting)
        // Five minutes on, `lastSeen` is written: the prefs go with it.
        auth.touch(auth.device(forToken: phone, now: start)!.id, now: start.addingTimeInterval(400))
        #expect(!auth.pushWaiting)
        let reread = RemoteAuth(store: MemoryDeviceStore(data: store.data))
        reread.load(now: start.addingTimeInterval(400))
        #expect(reread.devices.first?.push?.prefs.finishes == true)
    }

    // MARK: The login

    @Test func theLoginIsKeptOnlyAsTheHashOfItsLowercaseForm() {
        let hash = RemoteLogin.hash("Pat@Example.com")
        #expect(hash == RemoteLogin.hash("pat@example.com"))
        #expect(RemoteLogin.isHash(hash))
        #expect(!hash.contains("@") && !hash.contains("pat"))
        // SHA-256 of "pat@example.com", in hex.
        #expect(hash == "fe9733fcc96501276776fc927df08a395835461a2c5b12c65ebab3454877e227")
        #expect(RemoteLogin.matches("PAT@example.com", hash: hash))
        #expect(!RemoteLogin.matches("someone@example.com", hash: hash))
        #expect(!RemoteLogin.isHash("pat@example.com"))
        #expect(!RemoteLogin.isHash(hash.uppercased()))
    }

    @Test func anAddressAnEarlierBuildKeptIsHashedAndWrittenBack() throws {
        let scratch = ScratchDefaults.make(prefix: "bench.tests.remoteLogin")
        defer { scratch.discard() }
        let defaults = scratch.defaults
        #expect(RemoteLogin.recorded(defaults) == nil)
        defaults.set("Pat@example.com", forKey: SettingsKey.remoteLogin)
        let hashed = RemoteLogin.recorded(defaults)
        #expect(hashed == RemoteLogin.hash("pat@example.com"))
        #expect(defaults.string(forKey: SettingsKey.remoteLogin) == hashed)
        // A hash stays as it is.
        #expect(RemoteLogin.recorded(defaults) == hashed)
        #expect(RemoteLogin.normalized(hashed!) == hashed)
        RemoteLogin.record("someone@example.com", in: defaults)
        #expect(defaults.string(forKey: SettingsKey.remoteLogin) == RemoteLogin.hash("someone@example.com"))
    }
}
