// RemoteAuth.swift — pairing a phone with Bench, and the devices paired
// (DESIGN.md, Bench on your phone → Transport and trust). A device proves
// itself with a token Bench gave it once, in a cookie; Bench keeps only the
// token's SHA-256 hash, with the device's name and when it was paired and
// last seen, as one Keychain item of JSON.
//
// The code and the hashes are checked in constant time. The store is
// injected: the app's is the Keychain, the tests' and `--demo remote`'s
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

/// The app's store: one generic-password item in the login keychain.
@MainActor
final class KeychainDeviceStore: RemoteDeviceStore {
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    private let service = "local.sam.bench.remote"
    private let account: String
    private let label: String

    // Phase 2 push: the push key is a second item beside the devices.
    init(account: String = "devices", label: String = "Bench paired devices") {
        self.account = account
        self.label = label
    }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    func load() throws -> Data? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return result as? Data
    }

    func save(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrLabel] = label
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

/// Tests and `--demo remote`: nothing leaves memory.
@MainActor
final class MemoryDeviceStore: RemoteDeviceStore {
    private(set) var data: Data?
    /// Tests set it to make a save fail.
    var failsToSave = false

    init(data: Data? = nil) {
        self.data = data
    }

    func load() throws -> Data? { data }

    func save(_ data: Data) throws {
        if failsToSave { throw KeychainDeviceStore.Failure(status: errSecIO) }
        self.data = data
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
    /// The tries after the fifth wrong one, for a while: the code is gone.
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
    /// After the fifth wrong try, tries are refused for this long (429), so
    /// the code can't be guessed quickly code after code.
    static let lockout: TimeInterval = 30
    static let maxDevices = 20
    /// `lastSeen` changes in memory at most this often, and reaches the
    /// store at most every `persistEvery`: the events stream and the phone's
    /// refetches would otherwise rewrite the Keychain item constantly.
    static let seenEvery: TimeInterval = 60
    static let persistEvery: TimeInterval = 5 * 60

    @Published private(set) var devices: [RemoteDevice] = []
    /// The code Settings shows; nil until it asks for one, and after one is
    /// used or worn out by wrong tries.
    @Published private(set) var code: PairingCode?

    private let store: any RemoteDeviceStore
    /// `--demo remote`'s fixed code: it never expires or wears out, though
    /// wrong tries still wait after the fifth.
    private let fixedCode: String?
    private let makeDigits: () -> String
    private var lockedUntil: Date?
    private var loaded = false
    /// When each device's `lastSeen` last reached the store.
    private var persistedSeen: [String: Date] = [:]

    init(store: any RemoteDeviceStore, fixedCode: String? = nil, makeDigits: @escaping () -> String = RemoteAuth.randomDigits) {
        self.store = store
        self.fixedCode = fixedCode
        self.makeDigits = makeDigits
        if let fixedCode { code = PairingCode(digits: fixedCode, issuedAt: .distantFuture) }
    }

    /// Reads the devices from the store, once. Not at init: someone who never
    /// turns Remote on never has Bench read the Keychain.
    func load() {
        guard !loaded else { return }
        loaded = true
        do {
            guard let data = try store.load() else { return }
            devices = try Self.decoder.decode([RemoteDevice].self, from: data)
            persistedSeen = Dictionary(devices.compactMap { d in d.lastSeen.map { (d.id, $0) } }, uniquingKeysWith: { a, _ in a })
        } catch {
            log.error("Couldn't read the paired devices")
        }
    }

    // MARK: The code

    /// The code to show: the one out, while it's good, else a new one.
    @discardableResult
    func issueCode(now: Date = Date()) -> PairingCode {
        if let code, fixedCode != nil || !code.isExpired(at: now) { return code }
        let fresh = PairingCode(digits: makeDigits(), issuedAt: now)
        code = fresh
        return fresh
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
            code.wrongTries += 1
            if code.wrongTries >= Self.maxWrongTries {
                // The fifth is still a wrong code to the phone. Settings shows
                // a new code at once (the demo keeps its own); the next tries
                // wait a while.
                self.code = fixedCode.map { PairingCode(digits: $0, issuedAt: .distantFuture) }
                lockedUntil = now.addingTimeInterval(Self.lockout)
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
        log.notice("Paired a device")
        return .paired(token: token, device: device)
    }

    // MARK: Devices

    /// The device a token belongs to. Every device's hash is compared, in
    /// constant time.
    func device(forToken token: String) -> RemoteDevice? {
        guard RemoteToken.isWellFormed(token) else { return nil }
        load()
        let hash = RemoteToken.hash(token)
        var found: RemoteDevice?
        for device in devices where RemoteToken.matches(device.tokenHash, hash) {
            found = device
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

    /// "Remove All Devices": the Keychain item goes.
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

    /// Writes the list, and takes it only if the write worked.
    private func save(_ next: [RemoteDevice]) -> Bool {
        do {
            try store.save(Self.encoder.encode(next))
            devices = next
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
}
