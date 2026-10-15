// WebPush.swift — the Web Push wire format Bench sends notifications in
// (DESIGN.md, Capsid on your phone → Notifications). Pure and tested:
//
// - RFC 8291 message encryption (`aes128gcm`, RFC 8188), so only the device
//   that subscribed can read a push: P-256 key agreement, HKDF-SHA-256 and
//   AES-128-GCM, one record.
// - RFC 8292 VAPID: an ES256 JWT that says the push comes from Bench's key,
//   and the `Authorization` header that carries it.
// - The checks a subscription must pass before Bench keeps it.
//
// All of it with CryptoKit. Nothing here logs, stores or sends anything.
import CryptoKit
import Foundation

enum WebPush {
    // MARK: base64url

    /// Base64url without padding (RFC 4648 §5).
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Base64url, with or without padding. Nil for anything else: standard
    /// base64's `+` and `/`, white space, a length no encoding gives.
    static func data(base64URL text: String) -> Data? {
        var body = Substring(text)
        while body.hasSuffix("=") { body = body.dropLast() }
        guard body.utf8.allSatisfy({
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }) else { return nil }
        // Padding, if sent, must be what the length needs.
        let padding = text.count - body.count
        guard body.count % 4 != 1, padding == 0 || (body.count + padding) % 4 == 0 else { return nil }
        let standard = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: standard + String(repeating: "=", count: (4 - standard.count % 4) % 4))
    }

    // MARK: Subscriptions

    static let maxEndpointLength = 1024
    /// Push services whose own host an endpoint may be on, exactly.
    static let pushHosts: Set<String> = ["web.push.apple.com", "fcm.googleapis.com", "updates.push.services.mozilla.com"]
    /// Push services an endpoint may be on a subdomain of (`*.notify.windows.com`).
    static let pushDomains: [String] = ["notify.windows.com"]

    /// The endpoint a browser gave, if Bench may send to it: `https`, at most
    /// 1,024 characters, no user or password, the default port, and a host on
    /// the push services' list. Anything else would let a paired device make
    /// Bench post to a server of its choosing.
    static func endpoint(_ text: String) -> URL? {
        guard text.utf8.count <= maxEndpointLength,
              text.utf8.allSatisfy({ (0x21...0x7E).contains($0) }),
              let components = URLComponents(string: text),
              components.scheme == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.fragment == nil,
              let host = components.host, isPushHost(host),
              let url = components.url else { return nil }
        return url
    }

    static func isPushHost(_ host: String) -> Bool {
        let host = host.lowercased()
        if pushHosts.contains(host) { return true }
        return pushDomains.contains { domain in
            host.hasSuffix("." + domain) && host.count > domain.count + 1
        }
    }

    /// VAPID's `aud`: the endpoint's origin, `https://<host>`.
    static func audience(of endpoint: URL) -> String? {
        guard endpoint.scheme == "https", let host = endpoint.host() else { return nil }
        return "https://\(host.lowercased())"
    }

    /// The subscription's `p256dh`: an uncompressed P-256 point, 65 bytes,
    /// that is on the curve.
    static func receiverKey(_ text: String) -> Data? {
        guard let data = data(base64URL: text), data.count == 65, data.first == 0x04,
              (try? P256.KeyAgreement.PublicKey(x963Representation: data)) != nil else { return nil }
        return data
    }

    /// The subscription's `auth` secret: 16 bytes.
    static func authSecret(_ text: String) -> Data? {
        guard let data = data(base64URL: text), data.count == 16 else { return nil }
        return data
    }

    // MARK: Encryption (RFC 8291, aes128gcm)

    enum Failure: Error, Equatable {
        case receiverKey
        case authSecret
        case salt
        /// More than one record holds.
        case tooLarge
        case signing
    }

    /// The record size written in the header. The whole push is one record.
    static let recordSize: UInt32 = 4096
    /// The record's padding delimiter: this is the last record.
    static let lastRecord: UInt8 = 0x02
    static let tagLength = 16

    /// Every value the key schedule makes (RFC 8291 §3.3-3.4, RFC 8188 §2.2),
    /// kept apart so the tests can hold each one to the RFC's example.
    struct Keys: Equatable {
        let ecdhSecret: Data
        let prkKey: Data
        let ikm: Data
        let prk: Data
        let cek: Data
        let nonce: Data
    }

    static func keys(senderKey: P256.KeyAgreement.PrivateKey, receiverKey: Data, authSecret: Data, salt: Data) throws -> Keys {
        guard receiverKey.count == 65, let receiver = try? P256.KeyAgreement.PublicKey(x963Representation: receiverKey)
        else { throw Failure.receiverKey }
        guard authSecret.count == 16 else { throw Failure.authSecret }
        guard salt.count == 16 else { throw Failure.salt }
        let shared = try senderKey.sharedSecretFromKeyAgreement(with: receiver)
        let ecdh = shared.withUnsafeBytes { Data($0) }
        // PRK_key = HKDF-Extract(auth_secret, ecdh_secret)
        let prkKey = HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: ecdh), salt: authSecret)
        // IKM = HKDF-Expand(PRK_key, "WebPush: info" || 0x00 || ua_public || as_public, 32)
        let keyInfo = Data("WebPush: info".utf8) + [0x00] + receiverKey + senderKey.publicKey.x963Representation
        let ikm = HKDF<SHA256>.expand(pseudoRandomKey: prkKey, info: keyInfo, outputByteCount: 32)
        // PRK = HKDF-Extract(salt, IKM); then the key and the nonce.
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: ikm, salt: salt)
        let cek = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("Content-Encoding: aes128gcm".utf8) + [0x00], outputByteCount: 16)
        let nonce = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("Content-Encoding: nonce".utf8) + [0x00], outputByteCount: 12)
        return Keys(ecdhSecret: ecdh, prkKey: Data(prkKey), ikm: ikm.withUnsafeBytes { Data($0) }, prk: Data(prk),
                    cek: cek.withUnsafeBytes { Data($0) }, nonce: nonce.withUnsafeBytes { Data($0) })
    }

    /// `salt || rs || idlen || keyid`, with the sender's public key as the
    /// key id: 86 bytes.
    static func header(salt: Data, recordSize: UInt32 = WebPush.recordSize, keyID: Data) -> Data {
        var data = salt
        withUnsafeBytes(of: recordSize.bigEndian) { data.append(contentsOf: $0) }
        data.append(UInt8(keyID.count))
        data.append(keyID)
        return data
    }

    /// The body of the push: the header, then `plaintext || 0x02` sealed
    /// with AES-128-GCM. A new salt and a new sender key every time, unless
    /// given (the tests give the RFC's).
    static func encrypt(_ plaintext: Data, receiverKey: Data, authSecret: Data,
                        salt: Data? = nil, senderKey: P256.KeyAgreement.PrivateKey? = nil) throws -> Data {
        // One record: the content, its delimiter and the tag within rs.
        guard plaintext.count + 1 + tagLength <= Int(recordSize) else { throw Failure.tooLarge }
        let salt = salt ?? Data(SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) })
        let senderKey = senderKey ?? P256.KeyAgreement.PrivateKey()
        let keys = try keys(senderKey: senderKey, receiverKey: receiverKey, authSecret: authSecret, salt: salt)
        // The only record is record 0, so its nonce is NONCE itself.
        let sealed = try AES.GCM.seal(plaintext + [lastRecord], using: SymmetricKey(data: keys.cek),
                                      nonce: AES.GCM.Nonce(data: keys.nonce))
        return header(salt: salt, keyID: senderKey.publicKey.x963Representation) + sealed.ciphertext + sealed.tag
    }

    // MARK: VAPID (RFC 8292)

    /// Who sends: VAPID's `sub`, a contact for the push service.
    static let subject = "https://github.com/samporter14/bench"
    static let tokenLifetime: TimeInterval = 60 * 60

    /// An ES256 JWT: `{"typ":"JWT","alg":"ES256"}`, then `aud`, `exp` and
    /// `sub`, signed with the VAPID key. The signature is JWS's raw `r || s`
    /// (64 bytes), not DER.
    static func token(audience: String, expires: Date, subject: String = WebPush.subject,
                      key: P256.Signing.PrivateKey) throws -> String {
        let header = #"{"typ":"JWT","alg":"ES256"}"#
        let claims: [String: Any] = ["aud": audience, "exp": Int(expires.timeIntervalSince1970), "sub": subject]
        guard let body = try? JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys, .withoutEscapingSlashes])
        else { throw Failure.signing }
        let input = base64URL(Data(header.utf8)) + "." + base64URL(body)
        guard let signature = try? key.signature(for: Data(input.utf8)) else { throw Failure.signing }
        return input + "." + base64URL(signature.rawRepresentation)
    }

    /// `vapid t=<jwt>, k=<the public key, uncompressed, base64url>`.
    static func authorization(token: String, publicKey: P256.Signing.PublicKey) -> String {
        "vapid t=\(token), k=\(base64URL(publicKey.x963Representation))"
    }
}
