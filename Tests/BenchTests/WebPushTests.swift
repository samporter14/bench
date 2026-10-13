// WebPushTests.swift — RFC 8291's worked example (§5 and Appendix A) byte for
// byte, VAPID tokens (RFC 8292) checked against their own key, and the checks
// a subscription must pass. Nothing is sent anywhere.
import CryptoKit
import Foundation
import Testing
@testable import Bench

struct WebPushTests {
    /// The RFC's values print with spaces inside long ones; base64url has none.
    private func bytes(_ text: String) -> Data {
        let joined = text.filter { !$0.isWhitespace }
        guard let data = WebPush.data(base64URL: joined) else {
            Issue.record("not base64url: \(joined)")
            return Data()
        }
        return data
    }

    // MARK: RFC 8291 §5 and Appendix A

    private enum RFC8291 {
        static let plaintext = "When I grow up, I want to be a watermelon"
        static let asPublic = "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIg Dll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
        static let asPrivate = "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"
        static let uaPublic = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV- JvLexhqUzORcx aOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
        static let uaPrivate = "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94"
        static let salt = "DGv6ra1nlYgDCS1FRnbzlw"
        static let authSecret = "BTBZMqHH6r4Tts7J_aSIgg"
        static let ecdhSecret = "kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs"
        static let prkKey = "Snr3JMxaHVDXHWJn5wdC52WjpCtd2EIEGBykDcZW32k"
        static let keyInfo = """
            V2ViUHVzaDogaW5mbwAEJXGyvs3942BVG q8e0PTNNmwR zr5VX4m8t7GGpTM5FzFo7OLr4BhZe9MEebhuPI-OztV3
            ylkYfpJGmQ22ggCLDgT-M_SrDepxkU21WCP3O1SUj0Ew bZIHMtu5pZpTKGSCIA5Zent7wmC6HCJ5mFgJkuk5cwAv MBKiiujwa7t45ewP
            """
        static let ikm = "S4lYMb_L0FxCeq0WhDx813KgSYqU26kOyzWUdsXYyrg"
        static let prk = "09_eUZGrsvxChDCGRCdkLiDXrReGOEVeSCdCcPBSJSc"
        static let cekInfo = "Q29udGVudC1FbmNvZGluZzogYWVzMTI4Z2NtAA"
        static let cek = "oIhVW04MRdy2XN9CiKLxTg"
        static let nonceInfo = "Q29udGVudC1FbmNvZGluZzogbm9uY2UA"
        static let nonce = "4h_95klXJ5E_qnoN"
        static let header = """
            DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z 9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml
            mlMoZIIgDll6e3vCYLocInmYWAmS6Tlz AC8wEqKK6PBru3jl7A8
            """
        static let padded = "V2hlbiBJIGdyb3cgdXAsIEkgd2FudCB0 byBiZSBhIHdhdGVybWVsb24C"
        static let ciphertext = """
            8pfeW0KbunFT06SuDKoJH9Ql87S1QUrd irN6GcG7sFz1y1sqLgVi1VhjVkHsUoEs
            bI_0LpXMuGvnzQ
            """
        /// §5: the whole body, as sent.
        static let body = """
            DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml
            mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT
            pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN
            """
    }

    private func senderKey() throws -> P256.KeyAgreement.PrivateKey {
        try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes(RFC8291.asPrivate))
    }

    @Test func theRFCKeysAreTheKeyPairsItSays() throws {
        #expect(try senderKey().publicKey.x963Representation == bytes(RFC8291.asPublic))
        let receiver = try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes(RFC8291.uaPrivate))
        #expect(receiver.publicKey.x963Representation == bytes(RFC8291.uaPublic))
    }

    @Test func theKeyScheduleMatchesAppendixA() throws {
        let keys = try WebPush.keys(senderKey: senderKey(), receiverKey: bytes(RFC8291.uaPublic),
                                    authSecret: bytes(RFC8291.authSecret), salt: bytes(RFC8291.salt))
        #expect(keys.ecdhSecret == bytes(RFC8291.ecdhSecret))
        #expect(keys.prkKey == bytes(RFC8291.prkKey))
        #expect(keys.ikm == bytes(RFC8291.ikm))
        #expect(keys.prk == bytes(RFC8291.prk))
        #expect(keys.cek == bytes(RFC8291.cek))
        #expect(keys.nonce == bytes(RFC8291.nonce))
        // The info strings, as the RFC prints them.
        let keyInfo = Data("WebPush: info".utf8) + [0x00] + bytes(RFC8291.uaPublic) + bytes(RFC8291.asPublic)
        #expect(keyInfo == bytes(RFC8291.keyInfo))
        #expect(Data("Content-Encoding: aes128gcm".utf8) + [0x00] == bytes(RFC8291.cekInfo))
        #expect(Data("Content-Encoding: nonce".utf8) + [0x00] == bytes(RFC8291.nonceInfo))
    }

    @Test func theHeaderIs86BytesAsAppendixAShows() {
        let header = WebPush.header(salt: bytes(RFC8291.salt), keyID: bytes(RFC8291.asPublic))
        #expect(header.count == 86)
        #expect(header == bytes(RFC8291.header))
        #expect(Data(RFC8291.plaintext.utf8) + [0x02] == bytes(RFC8291.padded))
    }

    @Test func theWholeMessageMatchesSection5ByteForByte() throws {
        let body = try WebPush.encrypt(Data(RFC8291.plaintext.utf8), receiverKey: bytes(RFC8291.uaPublic),
                                       authSecret: bytes(RFC8291.authSecret), salt: bytes(RFC8291.salt),
                                       senderKey: senderKey())
        #expect(body.count == 144)
        #expect(body.dropFirst(86) == bytes(RFC8291.ciphertext))
        #expect(body == bytes(RFC8291.body))
    }

    /// The receiver's side, as the RFC describes it, opens what Bench sealed
    /// with fresh keys.
    @Test func theReceiverCanOpenAFreshMessage() throws {
        let receiver = P256.KeyAgreement.PrivateKey()
        let auth = Data((0..<16).map { UInt8($0 * 7) })
        let message = Data(#"{"v":1,"title":"Claude Science","body":"A session finished"}"#.utf8)
        let body = try WebPush.encrypt(message, receiverKey: receiver.publicKey.x963Representation, authSecret: auth)
        let salt = body.prefix(16)
        #expect(body[16..<20] == Data([0, 0, 0x10, 0]))
        #expect(body[20] == 65)
        let senderPublic = try P256.KeyAgreement.PublicKey(x963Representation: body[21..<86])
        let shared = try receiver.sharedSecretFromKeyAgreement(with: senderPublic)
        let ecdh = shared.withUnsafeBytes { Data($0) }
        let prkKey = HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: ecdh), salt: auth)
        let info = Data("WebPush: info".utf8) + [0x00] + receiver.publicKey.x963Representation + senderPublic.x963Representation
        let ikm = HKDF<SHA256>.expand(pseudoRandomKey: prkKey, info: info, outputByteCount: 32)
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: ikm, salt: Data(salt))
        let cek = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("Content-Encoding: aes128gcm".utf8) + [0], outputByteCount: 16)
        let nonce = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("Content-Encoding: nonce".utf8) + [0], outputByteCount: 12)
        let sealed = body.dropFirst(86)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce.withUnsafeBytes { Data($0) }),
                                        ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
        let opened = try AES.GCM.open(box, using: cek)
        #expect(opened == message + [0x02])
    }

    @Test func eachMessageHasItsOwnSaltAndSenderKey() throws {
        let receiver = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        let auth = Data(repeating: 1, count: 16)
        let a = try WebPush.encrypt(Data("same".utf8), receiverKey: receiver, authSecret: auth)
        let b = try WebPush.encrypt(Data("same".utf8), receiverKey: receiver, authSecret: auth)
        #expect(a.prefix(16) != b.prefix(16))
        #expect(a[21..<86] != b[21..<86])
    }

    @Test func badKeysAndTooMuchAreRefused() {
        let receiver = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        let auth = Data(repeating: 1, count: 16)
        #expect(throws: WebPush.Failure.receiverKey) {
            try WebPush.encrypt(Data("x".utf8), receiverKey: Data(repeating: 4, count: 65), authSecret: auth)
        }
        #expect(throws: WebPush.Failure.authSecret) {
            try WebPush.encrypt(Data("x".utf8), receiverKey: receiver, authSecret: Data(count: 15))
        }
        #expect(throws: WebPush.Failure.tooLarge) {
            try WebPush.encrypt(Data(count: 4080), receiverKey: receiver, authSecret: auth)
        }
        #expect((try? WebPush.encrypt(Data(count: 4079), receiverKey: receiver, authSecret: auth))?.count == 86 + 4096)
    }

    // MARK: VAPID (RFC 8292)

    private func parts(_ token: String) -> [String] {
        token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }

    @Test func aTokenVerifiesWithThePublicKeyAndSaysWhatItShould() throws {
        let key = P256.Signing.PrivateKey()
        let expires = Date(timeIntervalSince1970: 1_800_003_600)
        let token = try WebPush.token(audience: "https://web.push.apple.com", expires: expires, key: key)
        let p = parts(token)
        #expect(p.count == 3)
        let header = try #require(try JSONSerialization.jsonObject(with: bytes(p[0])) as? [String: Any])
        #expect(header["typ"] as? String == "JWT")
        #expect(header["alg"] as? String == "ES256")
        let claims = try #require(try JSONSerialization.jsonObject(with: bytes(p[1])) as? [String: Any])
        #expect(claims["aud"] as? String == "https://web.push.apple.com")
        #expect(claims["exp"] as? Int == 1_800_003_600)
        #expect(claims["sub"] as? String == "https://github.com/samporter14/bench")
        #expect(claims.count == 3)
        // JWS's raw r || s, not DER.
        let signature = bytes(p[2])
        #expect(signature.count == 64)
        let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        #expect(key.publicKey.isValidSignature(ecdsa, for: Data("\(p[0]).\(p[1])".utf8)))
        // Not with another key, and not for other claims.
        #expect(!P256.Signing.PrivateKey().publicKey.isValidSignature(ecdsa, for: Data("\(p[0]).\(p[1])".utf8)))
        #expect(!key.publicKey.isValidSignature(ecdsa, for: Data("\(p[0]).\(p[1])x".utf8)))
        // No padding, nothing standard base64 would add.
        #expect(!token.contains("=") && !token.contains("+") && !token.contains("/"))
    }

    @Test func theAuthorizationHeaderCarriesTheTokenAndTheUncompressedKey() throws {
        let key = P256.Signing.PrivateKey()
        let header = WebPush.authorization(token: "a.b.c", publicKey: key.publicKey)
        #expect(header.hasPrefix("vapid t=a.b.c, k="))
        let k = bytes(String(header.dropFirst("vapid t=a.b.c, k=".count)))
        #expect(k.count == 65)
        #expect(k.first == 0x04)
        #expect(k == key.publicKey.x963Representation)
    }

    @Test func theAudienceIsTheEndpointsOrigin() throws {
        let apple = try #require(WebPush.endpoint("https://web.push.apple.com/QGuDK9sLZm1gS2Wq_example-token"))
        #expect(WebPush.audience(of: apple) == "https://web.push.apple.com")
        let windows = try #require(WebPush.endpoint("https://wns2-par02p.notify.windows.com/w/?token=BQYAAA%3d"))
        #expect(WebPush.audience(of: windows) == "https://wns2-par02p.notify.windows.com")
        let port = try #require(WebPush.endpoint("https://fcm.googleapis.com:443/fcm/send/abc"))
        #expect(WebPush.audience(of: port) == "https://fcm.googleapis.com")
    }

    // MARK: Subscriptions

    @Test func endpointsOnThePushServicesPass() {
        #expect(WebPush.endpoint("https://web.push.apple.com/QGuDK9sLZm1gS2Wq") != nil)
        #expect(WebPush.endpoint("https://fcm.googleapis.com/fcm/send/dQw4w9WgXcQ:APA91b") != nil)
        #expect(WebPush.endpoint("https://updates.push.services.mozilla.com/wpush/v2/gAAAAA") != nil)
        #expect(WebPush.endpoint("https://db5p.notify.windows.com/w/?token=AwYAAAB") != nil)
        #expect(WebPush.endpoint("https://WEB.PUSH.APPLE.COM/abc") != nil)
        #expect(WebPush.endpoint("https://web.push.apple.com/" + String(repeating: "a", count: 1024 - 27)) != nil)
    }

    @Test func otherEndpointsAreRefused() {
        let refused = [
            "http://web.push.apple.com/abc",
            "https://evil-web.push.apple.com/abc",
            "https://web.push.apple.com.evil.com/abc",
            "https://xweb.push.apple.com/abc",
            "https://api.web.push.apple.com/abc",
            "https://notify.windows.com/w/?token=a",
            "https://evilnotify.windows.com/w/",
            "https://notify.windows.com.evil.com/w/",
            "https://example.com/push",
            "https://127.0.0.1/push",
            "https://user:pass@web.push.apple.com/abc",
            "https://web.push.apple.com:8443/abc",
            "https://web.push.apple.com/abc#frag",
            "https://web.push.apple.com/a b",
            "https://web.push.apple.com/\n",
            "wss://web.push.apple.com/abc",
            "web.push.apple.com/abc",
            "",
            "https://web.push.apple.com/" + String(repeating: "a", count: 1024 - 27 + 1),
        ]
        for text in refused {
            #expect(WebPush.endpoint(text) == nil, "\(text.prefix(60))")
        }
    }

    @Test func receiverKeysMustBeUncompressedPointsOnTheCurve() {
        let good = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        #expect(WebPush.receiverKey(WebPush.base64URL(good)) == good)
        // Padded is fine too.
        #expect(WebPush.receiverKey(WebPush.base64URL(good) + "=") == good)
        #expect(WebPush.receiverKey(WebPush.base64URL(good.dropLast())) == nil)
        #expect(WebPush.receiverKey(WebPush.base64URL(good + [0])) == nil)
        var compressedTag = good
        compressedTag[0] = 0x02
        #expect(WebPush.receiverKey(WebPush.base64URL(compressedTag)) == nil)
        var offCurve = good
        offCurve[64] ^= 0x01
        #expect(WebPush.receiverKey(WebPush.base64URL(offCurve)) == nil)
        #expect(WebPush.receiverKey("") == nil)
    }

    @Test func authSecretsAre16Bytes() {
        #expect(WebPush.authSecret("BTBZMqHH6r4Tts7J_aSIgg")?.count == 16)
        #expect(WebPush.authSecret(WebPush.base64URL(Data(count: 15))) == nil)
        #expect(WebPush.authSecret(WebPush.base64URL(Data(count: 17))) == nil)
        #expect(WebPush.authSecret("BTBZMqHH6r4Tts7J/aSIgg") == nil)
    }

    @Test func base64URLRoundTripsAndRefusesOtherAlphabets() {
        for length in 0..<40 {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 * 37 + 250) })
            let text = WebPush.base64URL(data)
            #expect(!text.contains("=") && !text.contains("+") && !text.contains("/"))
            #expect(WebPush.data(base64URL: text) == data)
        }
        #expect(WebPush.data(base64URL: "a+b/") == nil)
        #expect(WebPush.data(base64URL: "ab cd") == nil)
        #expect(WebPush.data(base64URL: "abcde") == nil)
        #expect(WebPush.data(base64URL: "abc==") == nil)
        #expect(WebPush.data(base64URL: "ab==") == Data([0x69]))
        #expect(WebPush.data(base64URL: "") == Data())
    }
}
