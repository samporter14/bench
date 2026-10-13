// RemoteAuth.swift — pairing a phone with Bench, and the devices paired
// (DESIGN.md, Bench on your phone → Transport and trust). A device proves
// itself with a token Bench gave it once, in a cookie; Bench keeps only the
// token's SHA-256 hash, with the device's name and when it was paired and
// last seen, as one file of JSON only this user can read.
//
// The code and the hashes are checked in constant time. The store is
// injected: the app's is that file, the tests' and `--demo remote`'s
// live in memory.
import CryptoKit
import Foundation
import OSLog
import Security

private let log = Logger(subsystem: "local.sam.bench", category: "remote")

// MARK: Tokens

/// A device token: 32 random bytes, base64url without padding (43
/// characters). Only its hash is ever kept.
enum RemoteToken {
    static let byteCount = 32
    static let length = 43

    /// A new token, from the system's secure random source.
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Without randomness there is no safe token to hand out.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URL(Data(bytes))
    }

    static func hash(_ token: String) -> Data {
        Data(SHA256.hash(data: Data(token.utf8)))
    }

    /// 43 base64url characters: the only shape `make()` gives. Anything else
    /// is no token, and isn't hashed or looked up.
    static func isWellFormed(_ token: String) -> Bool {
        token.utf8.count == length && token.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    /// Whether two byte strings are equal, taking the same time wherever they
    /// differ. Lengths aren't secret (a hash is always 32 bytes, a code 6
    /// digits), so a length mismatch returns at once.
    static func matches(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: The login

/// The tailnet login Remote was turned on with, kept in `remoteLogin` only as
/// the SHA-256 (hex) of its lowercased form: Serve's `Tailscale-User-Login`
/// is hashed the same way and compared, so the address itself is never
/// stored. Lowercased, since the check has always ignored case.
enum RemoteLogin {
    static func hash(_ login: String) -> String {
        SHA256.hash(data: Data(login.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 64 lowercase hex digits: what `hash` gives.
    static func isHash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    /// Whether Serve's login is the one recorded, in constant time.
    static func matches(_ sent: String, hash recorded: String) -> Bool {
        RemoteToken.matches(Data(hash(sent).utf8), Data(recorded.utf8))
    }

    /// What `remoteLogin` should hold: a hash as it is; anything else (the
    /// address an earlier build kept there) hashed.
    static func normalized(_ stored: String) -> String {
        isHash(stored) ? stored : hash(stored)
    }

    /// `remoteLogin`, as its hash. An address an earlier build kept there is
    /// hashed and written back, so it doesn't stay in the preferences.
    static func recorded(_ defaults: UserDefaults) -> String? {
        guard let stored = defaults.string(forKey: SettingsKey.remoteLogin) else { return nil }
        let hashed = normalized(stored)
        if hashed != stored { defaults.set(hashed, forKey: SettingsKey.remoteLogin) }
        return hashed
    }

    static func record(_ login: String, in defaults: UserDefaults) {
        defaults.set(hash(login), forKey: SettingsKey.remoteLogin)
    }
}

// MARK: Devices

/// A paired device as the store keeps it: never its token, only the hash.
struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    /// SHA-256 of the device's token (base64 in the JSON).
    let tokenHash: Data
    let pairedAt: Date
    var lastSeen: Date?
    /// Phase 2 push: its notifications (PushCenter.swift); nil in records
    /// from before, and for a device that never asked.
    var push: RemoteDevicePush? = nil

    /// The longest name kept, in characters.
    static let nameLimit = 64

    /// Not seen for `RemoteAuth.expiry`: no longer paired. A device never
    /// seen counts from when it was paired.
    func isExpired(at now: Date) -> Bool {
        now.timeIntervalSince(lastSeen ?? pairedAt) >= RemoteAuth.expiry
    }

    /// The name a phone sent, made fit to show in Settings: control
    /// characters out, white space runs to one space, at most `nameLimit`
    /// characters. Empty becomes "Unnamed device".
    static func cleanName(_ raw: String) -> String {
        let visible = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let line = String(String.UnicodeScalarView(visible)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = String(line.prefix(nameLimit))
        return name.isEmpty ? "Unnamed device" : name
    }
}

/// Where the devices are kept: one blob of JSON.
@MainActor
protocol RemoteDeviceStore: AnyObject {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

/// The app's store: one JSON file in Bench's own Application Support folder,
/// readable by this user only (folder 0700, file 0600), written whole to a
/// temporary file and then renamed over the old one.
///
/// Not the Keychain: Bench is signed without a Team ID, so macOS ties a
/// Keychain item to one exact build and asks for the login password again
/// after every update, with Bench stuck waiting. Nothing here is a secret a
/// file can't hold: tokens are kept only as SHA-256 hashes, and the push key
/// lets its holder do no more than send this user's own devices a
/// notification.
@MainActor
final class FileDeviceStore: RemoteDeviceStore {
    struct Failure: Error, Equatable {
        let errno: Int32
    }

    private let url: URL

    /// `~/Library/Application Support/Bench`.
    nonisolated static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bench", isDirectory: true)
    }

    // Phase 2 push: the push key is a second file beside the devices.
    init(name: String = "remote-devices.json", folder: URL = FileDeviceStore.folder) {
        url = folder.appendingPathComponent(name, isDirectory: false)
    }

    func load() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ data: Data) throws {
        let folder = url.deletingLastPathComponent()
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try? files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard files.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw Failure(errno: EIO)
        }
        guard rename(temporary.path, url.path) == 0 else {
            let failure = Failure(errno: errno)
            try? files.removeItem(at: temporary)
            throw failure
        }
    }

    func delete() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

/// Tests and `--demo remote`: nothing leaves memory.
@MainActor
final class MemoryDeviceStore: RemoteDeviceStore {
    private(set) var data: Data?
    /// Tests set it to make a save fail.
    var failsToSave = false
    /// Saves that worked, for tests.
    private(set) var saves = 0

    init(data: Data? = nil) {
        self.data = data
    }

    func load() throws -> Data? { data }

    func save(_ data: Data) throws {
        if failsToSave { throw FileDeviceStore.Failure(errno: EIO) }
        self.data = data
        saves += 1
    }

    func delete() throws { data = nil }
}

// MARK: Pairing

/// The one-time code Settings shows. Six digits, good for ten minutes and
/// five wrong tries, and for one pairing.
struct PairingCode: Equatable, Sendable {
    let digits: String
    let issuedAt: Date
    var wrongTries = 0

    var expiresAt: Date { issuedAt.addingTimeInterval(RemoteAuth.codeLifetime) }

    func isExpired(at now: Date) -> Bool { now >= expiresAt }
}

/// Why a pairing was refused.
enum PairingRefusal: Equatable, Sendable {
    /// No code is out: Settings hasn't shown one, or the last was used.
    case noCode
    case expired
    case wrongCode
    /// The tries after the fifth wrong one, for a while (30 s, then 2 min,
    /// then 10 min): the code is gone.
    case tooManyTries
    /// Too many devices are paired already.
    case tooManyDevices
    /// The store couldn't save the new device.
    case storeFailed
}

enum PairingResult: Equatable, Sendable {
    /// The token goes to the device, once, in its cookie.
    case paired(token: String, device: RemoteDevice)
    case refused(PairingRefusal)
}

/// The pairing code, and the devices paired. Main actor only, like the
/// server that asks it.
@MainActor
final class RemoteAuth: ObservableObject {
    nonisolated static let codeLifetime: TimeInterval = 10 * 60
    static let maxWrongTries = 5
    /// After the fifth wrong try, tries are refused for a while (429): 30 s
    /// the first time, then 2 minutes, then 10 minutes each time after. And
    /// no new code comes until someone presses New Code in Settings.
    static let lockouts: [TimeInterval] = [30, 2 * 60, 10 * 60]
    static let lockout = lockouts[0]
    /// The waits start again from 30 s after a pairing, or after an hour
    /// without a wrong try.
    static let lockoutMemory: TimeInterval = 60 * 60
    static let maxDevices = 20
    /// A device not seen for 60 days is no longer paired: its token stops
    /// working, and it leaves the list.
    nonisolated static let expiry: TimeInterval = 60 * 24 * 60 * 60
    /// Push prefs reach the store at most once a second: a phone flipping
    /// its switches would otherwise rewrite the file at every tap.
    static let prefsEvery: TimeInterval = 1
    /// `lastSeen` changes in memory at most this often, and reaches the
    /// store at most every `persistEvery`: the events stream and the phone's
    /// refetches would otherwise rewrite the file constantly.
    static let seenEvery: TimeInterval = 60
    static let persistEvery: TimeInterval = 5 * 60

    @Published private(set) var devices: [RemoteDevice] = []
    /// The code Settings shows; nil until it asks for one, and after one is
    /// used or worn out by wrong tries.
    @Published private(set) var code: PairingCode?
    /// The last code was worn out by wrong tries: Settings says so, and
    /// shows another only when asked (New Code).
    @Published private(set) var wornOut = false

    private let store: any RemoteDeviceStore
    /// `--demo remote`'s fixed code: it never expires or wears out, though
    /// wrong tries still wait after the fifth.
    private let fixedCode: String?
    private let makeDigits: () -> String
    private var lockedUntil: Date?
    /// Codes worn out since the waits last started again, and the last wrong try.
    private var strikes = 0
    private var lastWrongTry: Date?
    private var loaded = false
    /// When each device's `lastSeen` last reached the store.
    private var persistedSeen: [String: Date] = [:]
    /// Push prefs changed in memory and not yet stored, and when they last were.
    private var pushUnsaved = false
    private var pushSavedAt = Date.distantPast
    private var pushSave: Task<Void, Never>?

    init(store: any RemoteDeviceStore, fixedCode: String? = nil, makeDigits: @escaping () -> String = RemoteAuth.randomDigits) {
        self.store = store
        self.fixedCode = fixedCode
        self.makeDigits = makeDigits
        if let fixedCode { code = PairingCode(digits: fixedCode, issuedAt: .distantFuture) }
    }

    /// Reads the devices from the store, once. Not at init: someone who never
    /// turns Remote on never has Bench read the file. Devices not seen for
    /// 60 days leave the list here.
    func load(now: Date = Date()) {
        guard !loaded else { return }
        loaded = true
        do {
            guard let data = try store.load() else { return }
            devices = try Self.decoder.decode([RemoteDevice].self, from: data)
            persistedSeen = Dictionary(devices.compactMap { d in d.lastSeen.map { (d.id, $0) } }, uniquingKeysWith: { a, _ in a })
        } catch {
            log.error("Couldn't read the paired devices")
        }
        dropExpired(now: now)
    }

    /// Devices not seen for 60 days leave the list (and the file). The log
    /// says how many, never which.
    func dropExpired(now: Date = Date()) {
        let expired = devices.filter { $0.isExpired(at: now) }.map(\.id)
        guard !expired.isEmpty, save(devices.filter { !expired.contains($0.id) }) else { return }
        for id in expired {
            persistedSeen[id] = nil
            ListedFiles.shared.forget(device: id)
        }
        log.notice("Removed \(expired.count, privacy: .public) devices not seen for 60 days")
    }

    // MARK: The code

    /// New Code in Settings: the code out, while it's good, else a new one,
    /// even after one was worn out by wrong tries.
    @discardableResult
    func issueCode(now: Date = Date()) -> PairingCode {
        wornOut = false
        if let code, fixedCode != nil || !code.isExpired(at: now) { return code }
        let fresh = PairingCode(digits: makeDigits(), issuedAt: now)
        code = fresh
        return fresh
    }

    /// What Settings → Phone shows by itself: as `issueCode`, but none once
    /// a code was worn out by wrong tries, so someone guessing doesn't get a
    /// fresh code to guess at after every wait.
    func codeForSettings(now: Date = Date()) -> PairingCode? {
        wornOut ? nil : issueCode(now: now)
    }

    /// Six digits, uniform, from the secure random source.
    nonisolated static func randomDigits() -> String {
        // Below the largest multiple of a million that fits, so no number
        // comes up more often than another.
        let limit = UInt32.max - UInt32.max % 1_000_000
        while true {
            var value: UInt32 = 0
            let status = withUnsafeMutableBytes(of: &value) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
            if value < limit { return String(format: "%06u", value % 1_000_000) }
        }
    }

    /// `POST /pair`: the code checked, then a device made with a new token.
    func pair(code given: String, name: String, now: Date = Date()) -> PairingResult {
        load()
        if let lockedUntil, now < lockedUntil { return .refused(.tooManyTries) }
        guard var code else { return .refused(.noCode) }
        if fixedCode == nil, code.isExpired(at: now) {
            self.code = nil
            return .refused(.expired)
        }
        guard RemoteToken.matches(Data(given.utf8), Data(code.digits.utf8)) else {
            if let last = lastWrongTry, now.timeIntervalSince(last) >= Self.lockoutMemory { strikes = 0 }
            lastWrongTry = now
            code.wrongTries += 1
            if code.wrongTries >= Self.maxWrongTries {
                // The fifth is still a wrong code to the phone. The next tries
                // wait, longer each time, and Settings shows no new code until
                // asked (the demo keeps its own).
                lockedUntil = now.addingTimeInterval(Self.lockout(after: strikes))
                strikes += 1
                if let fixedCode {
                    self.code = PairingCode(digits: fixedCode, issuedAt: .distantFuture)
                } else {
                    self.code = nil
                    wornOut = true
                }
                log.notice("Pairing code worn out by wrong tries")
            } else {
                self.code = code
            }
            return .refused(.wrongCode)
        }
        guard devices.count < Self.maxDevices else { return .refused(.tooManyDevices) }
        let token = RemoteToken.make()
        let device = RemoteDevice(id: UUID().uuidString, name: RemoteDevice.cleanName(name),
                                  tokenHash: RemoteToken.hash(token), pairedAt: now, lastSeen: now)
        guard save(devices + [device]) else { return .refused(.storeFailed) }
        persistedSeen[device.id] = now
        // Used once.
        if fixedCode == nil { self.code = nil }
        strikes = 0
        lastWrongTry = nil
        log.notice("Paired a device")
        return .paired(token: token, device: device)
    }

    /// The wait after this many codes worn out in a row: 30 s, 2 min, then
    /// 10 min.
    static func lockout(after strikes: Int) -> TimeInterval {
        lockouts[min(max(strikes, 0), lockouts.count - 1)]
    }

    // MARK: Devices

    /// The device a token belongs to. Every device's hash is compared, in
    /// constant time. One not seen for 60 days is no longer paired, even
    /// before it leaves the list.
    func device(forToken token: String, now: Date = Date()) -> RemoteDevice? {
        guard RemoteToken.isWellFormed(token) else { return nil }
        load(now: now)
        let hash = RemoteToken.hash(token)
        var found: RemoteDevice?
        for device in devices where RemoteToken.matches(device.tokenHash, hash) {
            found = device
        }
        if let found, found.isExpired(at: now) {
            dropExpired(now: now)
            return nil
        }
        return found
    }

    /// A request from this device: `lastSeen` moves on, now and then.
    func touch(_ id: String, now: Date = Date()) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if let seen = devices[index].lastSeen, now.timeIntervalSince(seen) < Self.seenEvery { return }
        var next = devices
        next[index].lastSeen = now
        if now.timeIntervalSince(persistedSeen[id] ?? .distantPast) >= Self.persistEvery {
            if save(next) { persistedSeen[id] = now }
        } else {
            devices = next
        }
    }

    /// Unpair, from the phone or from Settings.
    func remove(_ id: String) {
        load()
        guard devices.contains(where: { $0.id == id }) else { return }
        if save(devices.filter { $0.id != id }) {
            persistedSeen[id] = nil
            ListedFiles.shared.forget(device: id)
            log.notice("Removed a device")
        }
    }

    /// "Remove All Devices": the file goes.
    func removeAll() {
        load()
        do {
            try store.delete()
            devices = []
            persistedSeen = [:]
            ListedFiles.shared.forgetAll()
            log.notice("Removed all devices")
        } catch {
            log.error("Couldn't remove the paired devices")
        }
    }

    /// The code goes: Remote was turned off.
    func withdrawCode() {
        if fixedCode == nil { code = nil }
    }

    /// Writes the list, and takes it only if the write worked. Push prefs
    /// held back (`updatePushSoon`) go with it.
    private func save(_ next: [RemoteDevice]) -> Bool {
        do {
            try store.save(Self.encoder.encode(next))
            devices = next
            pushUnsaved = false
            return true
        } catch {
            log.error("Couldn't save the paired devices")
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // Phase 2 push: each device's `push`, as `change` gives it, in one write.
    // Nothing else in a record changes. True when stored (or nothing changed).
    @discardableResult
    func updatePush(_ change: (RemoteDevice) -> RemoteDevicePush?) -> Bool {
        load()
        var next = devices
        for index in next.indices { next[index].push = change(next[index]) }
        return next == devices || save(next)
    }

    /// The same for a change of prefs, which a phone may make tap after tap:
    /// it holds in memory at once and reaches the store at most once a
    /// second (the first at once, the rest a second after the last write).
    func updatePushSoon(_ change: (RemoteDevice) -> RemoteDevicePush?, now: Date = Date()) {
        load()
        var next = devices
        for index in next.indices { next[index].push = change(next[index]) }
        guard next != devices else { return }
        devices = next
        pushUnsaved = true
        let wait = Self.prefsEvery - now.timeIntervalSince(pushSavedAt)
        guard wait > 0 else { return savePush(now: now) }
        guard pushSave == nil else { return }
        pushSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.savePush()
        }
    }

    /// Writes push prefs held back, if any: a second after the last write,
    /// and when Bench quits.
    func savePush(now: Date = Date()) {
        pushSave?.cancel()
        pushSave = nil
        guard pushUnsaved, save(devices) else { return }
        pushSavedAt = now
    }

    /// Whether prefs wait to be stored, for tests.
    var pushWaiting: Bool { pushUnsaved }
}
