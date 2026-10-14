// RemotePhotoTests.swift — the phone's photos, the pure part, on synthetic
// pictures made here (a flat red, blue and green drawing, random noise, a
// rotated JPEG with made-up GPS and camera tags): the routes and their
// limits, the body, the text check, what Bench does to a picture, the file
// name, and the attachment line. Nothing reaches a real daemon, web view or
// phone.
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Bench

private let root = ReaderFixture.root
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"

// MARK: Synthetic pictures

enum PhotoFixture {
    /// Left half red, right half blue, a green square at the top-left corner.
    static func picture(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - height / 4, width: width / 4, height: height / 4))
        return context.makeImage()!
    }

    /// Transparent on the left, opaque red on the right.
    static func halfTransparent(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    /// Random pixels, which no JPEG makes small.
    static func noise(_ width: Int, _ height: Int) -> CGImage {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            for channel in 0..<3 { bytes[index * 4 + channel] = UInt8.random(in: 0...255, using: &generator) }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 4000 × 3000, orientation 6 (to be turned a quarter clockwise), with made-up
    /// GPS, camera and Exif tags.
    static let rotatedWithMetadata: Data = encode(picture(4000, 3000), as: .jpeg, properties: [
        kCGImagePropertyOrientation: 6,
        kCGImageDestinationLossyCompressionQuality: 0.9,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N",
                                        kCGImagePropertyGPSLongitude: 3.25, kCGImagePropertyGPSLongitudeRef: "E"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "MadeUpCam", kCGImagePropertyTIFFModel: "X1"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:14 10:00:00",
                                         kCGImagePropertyExifUserComment: "made-up secret"],
    ])!

    /// A small PNG, for the flows that only need a picture that decodes.
    static let png: Data = encode(picture(32, 24), as: .png)!

    /// The picture's pixel `x`, `y` (from the top left), 0…255.
    static func pixel(_ data: Data, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    static func properties(_ data: Data) -> [String: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
    }

    /// The JPEG's marker bytes in order, up to the scan.
    static func markers(_ jpeg: Data) -> [UInt8] {
        let bytes = [UInt8](jpeg)
        var found: [UInt8] = []
        var i = 2
        while i + 4 <= bytes.count, bytes[i] == 0xFF {
            let marker = bytes[i + 1]
            found.append(marker)
            if marker == 0xDA { break }
            i += 2 + (Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]))
        }
        return found
    }

    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// A photo request's body.
    static func body(image: Data = png, text: String? = nil, id: String = intent, planFirst: Bool? = nil) -> Data {
        var object: [String: Any] = ["image": image.base64EncodedString(), "id": id]
        if let text { object["text"] = text }
        if let planFirst { object["planFirst"] = planFirst }
        return json(object)
    }
}

/// JPEG turns a pure blue into about (4, 51, 252): close is enough.
private func near(_ pixel: (r: Int, g: Int, b: Int), _ r: Int, _ g: Int, _ b: Int, within: Int = 60) -> Bool {
    abs(pixel.r - r) <= within && abs(pixel.g - g) <= within && abs(pixel.b - b) <= within
}

private func made(_ result: Result<PhotoFile, PhotoRefusal>) throws -> PhotoFile {
    try result.get()
}

private let when = Date(timeIntervalSince1970: 1_791_833_400)

// MARK: The routes

struct RemotePhotoRouteTests {
    private func match(_ method: String, _ path: String) -> RemoteRoute.Match {
        RemoteRoute.match(method: method, path: Substring(path))
    }

    @Test func theTwoPaths() {
        #expect(match("POST", "/api/sessions/\(root)/photo") == .found(.photo(.session(root))))
        #expect(match("POST", "/api/projects/proj_a-1/photo") == .found(.photo(.project("proj_a-1"))))
        #expect(match("GET", "/api/sessions/\(root)/photo") == .wrongMethod)
        #expect(match("GET", "/api/projects/proj_a-1/photo") == .wrongMethod)
        // The routes around them are as they were.
        #expect(match("POST", "/api/sessions/\(root)/message") == .found(.action(.message, root)))
        #expect(match("POST", "/api/projects/proj_a-1/sessions") == .found(.newSession("proj_a-1")))
    }

    @Test(arguments: [
        "/api/sessions/short/photo", "/api/sessions/\(root.uppercased())/photo", "/api/sessions/\(root)/photo/",
        "/api/sessions/\(root)/photos", "/api/sessions/\(root)/photo/x", "/api/sessions//photo",
        "/api/projects/a%2Fb/photo", "/api/projects/a.b/photo", "/api/projects//photo", "/api/projects/a/photo/x",
        "/api/projects/\(String(repeating: "a", count: 65))/photo", "/api/frames/\(root)/photo", "/api/photo",
        "//api/projects/a/photo",
    ])
    func nothingElseMatches(_ path: String) {
        #expect(match("POST", path) == .notFound)
    }

    @Test func theLogNamesThePatternNotTheId() {
        #expect(RemoteRoute.photo(.session(root)).pattern == "/api/sessions/<id>/photo")
        #expect(RemoteRoute.photo(.project("proj_a")).pattern == "/api/projects/<pid>/photo")
        #expect(RemoteRoute.photo(.session(root)).needsToken)
        #expect(RemoteRoute.photo(.session(root)).method == "POST")
    }

    @Test func sixMegabytesOnTheseTwoRoutesAndNoOtherChanges() {
        #expect(RemotePhotoRoute.bodyLimit == 6 * 1024 * 1024)
        #expect(RemoteRoute.photo(.session(root)).bodyLimit == 6 * 1024 * 1024)
        #expect(RemoteRoute.photo(.project("p")).bodyLimit == 6 * 1024 * 1024)
        #expect(RemoteRoute.action(.message, root).bodyLimit == RemoteRoute.messageBodyLimit)
        #expect(RemoteRoute.newSession("p").bodyLimit == RemoteRoute.messageBodyLimit)
        #expect(RemoteRoute.action(.approve, root).bodyLimit == RemoteHTTP.maxBody)
        #expect(RemoteRoute.pair.bodyLimit == RemoteHTTP.maxBody)
    }

    private func head(_ path: String, length: Int) -> Data {
        Data("POST \(path) HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: \(length)\r\n\r\n".utf8)
    }

    @Test func theParserTakesAPhotoHeadButNotOneOverTheLimitOrAnotherRouteOverItsOwn() {
        let photo = "/api/sessions/\(root)/photo"
        if case .head(_, let length) = RemoteHTTP.parse(head(photo, length: 5_000_000)) { #expect(length == 5_000_000) } else {
            Issue.record("a 5 MB photo's head wasn't taken")
        }
        if case .head = RemoteHTTP.parse(head("/api/projects/p/photo", length: 6 * 1024 * 1024)) {} else {
            Issue.record("exactly 6 MB wasn't taken")
        }
        #expect(RemoteHTTP.parse(head(photo, length: 6 * 1024 * 1024 + 1)) == .reject(413))
        #expect(RemoteHTTP.parse(head("/api/projects/p/photo", length: 7_000_000)) == .reject(413))
        // Everyone else keeps their own.
        #expect(RemoteHTTP.parse(head("/api/sessions/\(root)/message", length: 20_000)) == .reject(413))
        #expect(RemoteHTTP.parse(head("/api/sessions/\(root)/approve", length: 9_000)) == .reject(413))
        #expect(RemoteHTTP.parse(head("/pair", length: 5_000_000)) == .reject(413))
    }

    @Test func aPhotoBodyThatIsNotJSONIsRefusedBeforeItsBody() {
        let policy = RemotePolicy.demo(port: 47281)
        let request = RemoteRequest(method: "POST", target: "/api/sessions/\(root)/photo", headers: [
            "host": ["127.0.0.1:47281"], "content-type": ["image/jpeg"], "origin": ["http://127.0.0.1:47281"],
            "x-bench": ["1"], "cookie": ["bench_device=x"],
        ])
        #expect(RemoteCheck.evaluate(request, policy: policy) == .reject(415, route: .photo(.session(root)), gate: .type))
    }

    @Test func aPhotoCostsTenAndTwelveAreAllACleanBucketAllows() {
        #expect(RemoteRoute.photo(.session(root)).cost == 10)
        #expect(RemoteRoute.photo(.project("p")).cost == 10)
        #expect(RemoteRoute.me.cost == 1)
        var budgets = DeviceBudgets()
        let now = Date(timeIntervalSince1970: 1_791_833_400)
        for n in 0..<12 {
            #expect(budgets.admit(.photo(.session(root)), device: "d", at: now) == .go(transfer: false), "photo \(n)")
        }
        #expect(budgets.admit(.photo(.session(root)), device: "d", at: now) == .refuse(error: DeviceBudgets.slowDown, retryAfter: 5))
        // Not a transfer: it doesn't count against the two at a time.
        #expect(budgets.transfersUnderWay("d") == 0)
    }

    @Test func aBodyMayGoQuietTenSecondsAndTakeTwoMinutesInAll() {
        #expect(RemotePhotoRoute.bodyWait(elapsed: 0) == 10)
        #expect(RemotePhotoRoute.bodyWait(elapsed: 60) == 10)
        #expect(RemotePhotoRoute.bodyWait(elapsed: 115) == 5)
        #expect(RemotePhotoRoute.bodyWait(elapsed: 120) == 0.1)
        #expect(RemotePhotoRoute.bodyWait(elapsed: 500) == 0.1)
        #expect(RemoteRoute.photo(.session(root)).bodyWait(elapsed: 0) == .milliseconds(10_000))
        #expect(RemoteRoute.photo(.session(root)).rearmsBodyTimer)
        // Every other route keeps the flat 3 s and never re-arms.
        #expect(RemoteRoute.action(.message, root).bodyWait(elapsed: 0) == RemoteServer.bodyTimeout)
        #expect(RemoteRoute.newSession("p").bodyWait(elapsed: 2) == RemoteServer.bodyTimeout)
        #expect(!RemoteRoute.action(.message, root).rearmsBodyTimer)
        #expect(!RemoteRoute.pair.rearmsBodyTimer)
    }
}

// MARK: The body and the text

struct PhotoBodyTests {
    private func parse(_ object: [String: Any], project: Bool = false) -> Result<PhotoRequest, PhotoRefusal> {
        PhotoRequest.parse(PhotoFixture.json(object), project: project)
    }

    private let image = PhotoFixture.png.base64EncodedString()

    @Test func aGoodBody() throws {
        let request = try PhotoRequest.parse(PhotoFixture.body(text: "  Look at this gel. \n", planFirst: true), project: true).get()
        #expect(request.image == PhotoFixture.png)
        #expect(request.text == "Look at this gel.")
        #expect(request.intentID == intent)
        #expect(request.planFirst)
        // The session route ignores `planFirst`; a photo alone has no text.
        let alone = try PhotoRequest.parse(PhotoFixture.body(planFirst: true), project: false).get()
        #expect(alone.text == "")
        #expect(!alone.planFirst)
        let nulls = try parse(["image": image, "id": intent, "text": NSNull(), "planFirst": NSNull()], project: true).get()
        #expect(nulls.text == "" && !nulls.planFirst)
    }

    @Test func fourThousandCharactersFitAndOneMoreDoesNot() throws {
        let most = String(repeating: "界", count: 4000)
        #expect(try parse(["image": image, "id": intent, "text": most]).get().text == most)
        #expect(parse(["image": image, "id": intent, "text": most + "界"]) == .failure(.badRequest))
    }

    @Test(arguments: [
        "{{artifact:abc}}", #"{"type":"artifact","id":"x"}"#, #"{"type":"attachment","id":"x"}"#, #"{"type":"skill","name":"x"}"#,
        #"{"type":"session","id":"x"}"#, #"{"artifact_ref":"x"}"#, #"{"file_path":"/x"}"#,
    ])
    func aReferencePrefixIsRefused(_ prefix: String) {
        #expect(parse(["image": image, "id": intent, "text": prefix]) == .failure(.reference))
        #expect(parse(["image": image, "id": intent, "text": "Look at this: " + prefix + " and that"]) == .failure(.reference))
        #expect(parse(["image": image, "id": intent, "text": prefix, "planFirst": false], project: true) == .failure(.reference))
    }

    @Test func aReferenceWithSpacesInItIsRefusedToo() {
        #expect(parse(["image": image, "id": intent, "text": #"{ "type" : "attachment", "id": "x"}"#]) == .failure(.reference))
        #expect(parse(["image": image, "id": intent, "text": "{\"type\":\n\"skill\"}"]) == .failure(.reference))
        #expect(parse(["image": image, "id": intent, "text": "{{ artifact: 5 }}"]) == .failure(.reference))
    }

    @Test(arguments: ["{x}", "use {{ var }} here", #"{"type": "gel"}"#, "the artifact: a figure", #"{"name":"attachment"}"#, "{}"])
    func ordinaryBracesAreFine(_ text: String) throws {
        #expect(try parse(["image": image, "id": intent, "text": text]).get().text == text)
    }

    @Test(arguments: [
        #"{"id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AAAA"}"#,
        #"{"image":"","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":5,"id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AAA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AA AA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AA\nAA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"A=AA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AAA===","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AA-_","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"====","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"data:image/png;base64,AAAA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427"}"#,
        #"{"image":"AAAA","id":"1B4E28BA-2FA1-41D2-883F-0016D3CCA427"}"#,
        #"{"image":"AAAA","id":"6ba7b810-9dad-11d1-80b4-00c04fd430c8"}"#,
        #"{"image":"AAAA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427","text":5}"#,
        #"{"image":"AAAA","id":"1b4e28ba-2fa1-41d2-883f-0016d3cca427","planFirst":"yes"}"#,
        #"["AAAA"]"#, "not json", "",
    ])
    func badBodies(_ json: String) {
        #expect(PhotoRequest.parse(Data(json.utf8), project: true) == .failure(.badRequest))
    }

    @Test func aPlanFirstThatIsNotABooleanIsOnlyRefusedWhereItIsRead() throws {
        let object: [String: Any] = ["image": image, "id": intent, "planFirst": "yes"]
        #expect(parse(object, project: true) == .failure(.badRequest))
        #expect(try parse(object, project: false).get().planFirst == false)
    }

    @Test func base64IsTheStrictKind() {
        #expect(PhotoBase64.decode("AAAA") == Data([0, 0, 0]))
        #expect(PhotoBase64.decode("QQ==") == Data("A".utf8))
        #expect(PhotoBase64.decode("QUI=") == Data("AB".utf8))
        for bad in ["", "Q", "QQ=", "QQ", "Q===", "QQ==QQ==", "QU I=", " QQ==", "QQ==\n", "Q-Q_", "QQ=A"] {
            #expect(PhotoBase64.decode(bad) == nil, "\(bad)")
        }
    }

    @Test func theRefusalsAnswerAsTheSpecSays() {
        #expect(PhotoRefusal.reference.reply == RemoteActionReply(status: 400, body: Data(#"{"error":"reference"}"#.utf8)))
        #expect(PhotoRefusal.notAnImage.reply == RemoteActionReply(status: 415, body: Data(#"{"error":"notAnImage"}"#.utf8)))
        #expect(PhotoRefusal.tooBig.reply == RemoteActionReply(status: 413, body: Data(#"{"error":"tooBig"}"#.utf8)))
        #expect(PhotoRefusal.badRequest.reply == .badRequest)
    }
}

// MARK: The picture

struct PhotoImageTests {
    @Test func theMagicBytesDecideNotTheClaim() {
        #expect(PhotoImage.kind(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(PhotoImage.kind(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])) == .png)
        for brand in ["heic", "heix", "mif1"] {
            #expect(PhotoImage.kind(of: Data([0, 0, 0, 0x18] + Array("ftyp\(brand)".utf8) + [0, 0, 0, 0])) == .heic, "\(brand)")
        }
        let others: [Data] = [
            Data("GIF89a......".utf8), Data("RIFF....WEBPVP8 ".utf8), Data("%PDF-1.7\n".utf8), Data("<svg xmlns=".utf8),
            Data([0, 0, 0, 0x18] + Array("ftypavif".utf8) + [0, 0, 0, 0]), Data([0, 0, 0, 0x18] + Array("ftypmp42".utf8) + [0, 0, 0, 0]),
            Data([0xFF, 0xD8]), Data([0x89, 0x50, 0x4E, 0x47]), Data([0, 0, 0, 0x18] + Array("ftyp".utf8)), Data(), Data("MM\0*".utf8),
        ]
        for data in others { #expect(PhotoImage.kind(of: data) == nil) }
    }

    @Test func aRotatedPhotoComesOutUprightWithNoMetadata() throws {
        let input = PhotoFixture.rotatedWithMetadata
        // The input really has what the test says it has.
        let before = PhotoFixture.properties(input)
        #expect(before["{GPS}"] != nil)
        #expect((before["Orientation"] as? NSNumber)?.intValue == 6)
        #expect(input.range(of: Data("MadeUpCam".utf8)) != nil)

        let photo = try made(PhotoImage.process(input, at: when))
        let out = photo.data
        // Upright: 4000 × 3000 turned a quarter, and brought down to 3,072 on the long side.
        #expect(photo.width == 2304 && photo.height == 3072)
        #expect(photo.width < photo.height)
        let after = PhotoFixture.properties(out)
        #expect(after["PixelWidth"] as? Int == 2304 && after["PixelHeight"] as? Int == 3072)
        #expect(after["Orientation"] == nil)
        // Red on top, blue below, the green corner top right: the picture turned clockwise.
        #expect(near(PhotoFixture.pixel(out, x: 1152, y: 400), 255, 0, 0))
        #expect(near(PhotoFixture.pixel(out, x: 100, y: 100), 255, 0, 0))
        #expect(near(PhotoFixture.pixel(out, x: 1152, y: 2700), 0, 0, 255))
        #expect(near(PhotoFixture.pixel(out, x: 2204, y: 100), 0, 255, 0))
        // No GPS, no camera, no Exif: in what ImageIO reads, and in the bytes.
        #expect(after["{GPS}"] == nil)
        #expect(after["{TIFF}"] == nil)
        let markers = PhotoFixture.markers(out)
        #expect(!markers.contains(0xE1) && !markers.contains(0xED) && !markers.contains(0xFE))
        #expect(markers.first == 0xE0 && markers.last == 0xDA)
        for needle in ["Exif", "GPS", "MadeUpCam", "made-up secret", "2026:10:14", "http://ns.adobe.com", "Photoshop"] {
            #expect(out.range(of: Data(needle.utf8)) == nil, "\(needle)")
        }
        #expect(out.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(out.count <= PhotoImage.maxBytes)
        // The name: UTC, the phone's own never used.
        #expect(photo.name == "phone-photo-20261012-193000.jpg")
        #expect(photo.contentType == "image/jpeg")
    }

    @Test func aPNGBecomesAJPEGAndItsTransparencyWhite() throws {
        let png = try #require(PhotoFixture.encode(PhotoFixture.halfTransparent(200, 100), as: .png))
        #expect(PhotoImage.kind(of: png) == .png)
        let photo = try made(PhotoImage.process(png, at: when))
        #expect(photo.data.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(photo.width == 200 && photo.height == 100)
        #expect(near(PhotoFixture.pixel(photo.data, x: 40, y: 50), 255, 255, 255, within: 12))
        #expect(near(PhotoFixture.pixel(photo.data, x: 160, y: 50), 255, 0, 0))
        // An opaque PNG is only converted.
        let flat = try made(PhotoImage.process(PhotoFixture.png, at: when))
        #expect(flat.width == 32 && flat.height == 24)
        #expect(near(PhotoFixture.pixel(flat.data, x: 6, y: 18), 255, 0, 0, within: 60))
        #expect(near(PhotoFixture.pixel(flat.data, x: 28, y: 18), 0, 0, 255, within: 60))
    }

    @Test func aCMYKJPEGComesOutAsRGB() throws {
        let space = CGColorSpaceCreateDeviceCMYK()
        let context = try #require(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [0, 1, 1, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let drawn = try #require(context.makeImage())
        let cmyk = try #require(PhotoFixture.encode(drawn, as: .jpeg))
        #expect(PhotoFixture.markers(cmyk).contains(0xEE))
        let photo = try made(PhotoImage.process(cmyk, at: when))
        #expect(photo.width == 120 && photo.height == 80)
        #expect(near(PhotoFixture.pixel(photo.data, x: 60, y: 40), 237, 28, 36, within: 70))
        #expect(!PhotoFixture.markers(photo.data).contains(0xEE))
    }

    @Test func aGreyPictureStaysGrey() throws {
        let space = CGColorSpaceCreateDeviceGray()
        let context = try #require(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        let drawn = try #require(context.makeImage())
        let grey = try #require(PhotoFixture.encode(drawn, as: .png))
        let photo = try made(PhotoImage.process(grey, at: when))
        #expect(photo.width == 60 && photo.height == 40)
        #expect(near(PhotoFixture.pixel(photo.data, x: 30, y: 20), 128, 128, 128, within: 20))
    }

    @Test func anOversizedPictureIsBroughtDown() throws {
        let wide = try #require(PhotoFixture.encode(PhotoFixture.picture(5000, 2000), as: .jpeg))
        let photo = try made(PhotoImage.process(wide, at: when))
        #expect(photo.width == 3072)
        #expect((1228...1229).contains(photo.height))
        // A picture already within bounds is never enlarged.
        let small = try #require(PhotoFixture.encode(PhotoFixture.picture(100, 80), as: .jpeg))
        let kept = try made(PhotoImage.process(small, at: when))
        #expect(kept.width == 100 && kept.height == 80)
    }

    @Test func aHEICComesOutUpright() throws {
        // Skipped where ImageIO can't write one.
        guard let heic = PhotoFixture.encode(PhotoFixture.picture(640, 480), as: .heic, properties: [kCGImagePropertyOrientation: 6])
        else { return }
        #expect(PhotoImage.kind(of: heic) == .heic)
        let photo = try made(PhotoImage.process(heic, at: when))
        #expect(photo.width == 480 && photo.height == 640)
        #expect(photo.data.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(near(PhotoFixture.pixel(photo.data, x: 240, y: 100), 255, 0, 0))
        #expect(near(PhotoFixture.pixel(photo.data, x: 240, y: 560), 0, 0, 255))
        #expect(PhotoFixture.properties(photo.data)["Orientation"] == nil)
    }

    @Test func whatIsNotAPictureIsRefused() {
        var random = [UInt8](repeating: 0, count: 4_000)
        for index in random.indices { random[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 7) }
        let jpegHead = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let pngHead = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let cases: [Data] = [
            Data(random), Data("not an image at all".utf8), Data(), Data([0xFF]),
            // The right first bytes, and nothing a decoder can use after them.
            jpegHead + Data(random), pngHead + Data(random), jpegHead,
            Data([0, 0, 0, 0x18] + Array("ftypheic".utf8) + random.prefix(100)),
            // A real picture of another kind is refused by its magic bytes.
            PhotoFixture.encode(PhotoFixture.picture(40, 30), as: .gif) ?? Data("GIF89a".utf8),
            Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8),
        ]
        for (index, data) in cases.enumerated() {
            #expect(PhotoImage.process(data, at: when) == .failure(.notAnImage), "case \(index)")
        }
        // Cut in half, a real JPEG is no picture either, or at worst one whole.
        let half = PhotoFixture.rotatedWithMetadata.prefix(PhotoFixture.rotatedWithMetadata.count / 2)
        if case .success(let photo) = PhotoImage.process(Data(half), at: when) {
            #expect(photo.data.starts(with: [0xFF, 0xD8, 0xFF]))
        }
    }

    @Test func aTooBigJPEGIsDrawnWithLessQualityUntilItFits() throws {
        let png = try #require(PhotoFixture.encode(PhotoFixture.noise(900, 700), as: .png))
        let first = try made(PhotoImage.process(png, at: when))
        #expect(first.data.count > 200_000)
        let squeezed = try made(PhotoImage.process(png, at: when, maxBytes: 200_000))
        #expect(squeezed.data.count <= 200_000)
        #expect(squeezed.data.count < first.data.count)
        #expect(squeezed.data.starts(with: [0xFF, 0xD8, 0xFF]))
        // Squeezed small enough, the picture itself is smaller too, drawn from the one decode.
        let tight = try made(PhotoImage.process(png, at: when, maxBytes: 20_000))
        #expect(tight.data.count <= 20_000)
        #expect(tight.width < 900 && tight.height < 700)
        #expect(abs(Double(tight.width) / Double(tight.height) - 900.0 / 700.0) < 0.03)
        let after = PhotoFixture.properties(tight.data)
        #expect(after["PixelWidth"] as? Int == tight.width && after["PixelHeight"] as? Int == tight.height)
        // Nothing smaller than a few bytes is a JPEG.
        let tiny = try #require(PhotoFixture.encode(PhotoFixture.noise(300, 200), as: .png))
        #expect(PhotoImage.process(tiny, at: when, maxBytes: 100) == .failure(.tooBig))
    }

    @Test func tooManyPixelsAreRefusedFromTheHeader() throws {
        let jpeg = try #require(PhotoFixture.encode(PhotoFixture.picture(400, 300), as: .jpeg))
        #expect(PhotoImage.process(jpeg, at: when, maxPixels: 100_000) == .failure(.tooBig))
        #expect(PhotoImage.process(jpeg, at: when, maxPixels: 120_000) != .failure(.tooBig))
        // 24 megapixels: 7× what the phone sends (3,072 px on a side is 9.4).
        #expect(PhotoImage.maxPixels == 24_000_000)
    }

    @Test func aPictureOver24MegapixelsIsRefusedBeforeItIsDecoded() throws {
        // 5,000 × 5,000 is 25 MP, a few flat colours that make a small PNG.
        let big = try #require(PhotoFixture.encode(PhotoFixture.picture(5000, 5000), as: .png))
        let started = Date()
        #expect(PhotoImage.process(big, at: when) == .failure(.tooBig))
        #expect(Date().timeIntervalSince(started) < 1)
        // And a wide strip over the same count in one side alone.
        let strip = try #require(PhotoFixture.encode(PhotoFixture.picture(24_001, 1000), as: .png))
        #expect(PhotoImage.process(strip, at: when) == .failure(.tooBig))
    }

    @Test func aPictureJustUnderTheCapIsStillMadeAndComesOutAtTheSendSize() throws {
        // 6,000 × 3,999 is 23.99 MP: one decode, straight to 3,072 on the long side.
        let big = try #require(PhotoFixture.encode(PhotoFixture.picture(6000, 3999), as: .jpeg))
        let photo = try made(PhotoImage.process(big, at: when))
        #expect(photo.width == 3072 && (2047...2048).contains(photo.height))
        #expect(photo.data.count <= PhotoImage.maxBytes)
    }

    @Test func theFileNameIsUTCWhateverTheMacsZone() {
        #expect(PhotoImage.fileName(at: Date(timeIntervalSince1970: 1_791_833_400)) == "phone-photo-20261012-193000.jpg")
        #expect(PhotoImage.fileName(at: Date(timeIntervalSince1970: 0)) == "phone-photo-19700101-000000.jpg")
        #expect(PhotoImage.fileName(at: Date(timeIntervalSince1970: 1_798_761_599)) == "phone-photo-20261231-235959.jpg")
        for date in [0.0, 1_791_833_400, 1_798_761_599] {
            #expect(PhotoAttachment.isPhotoName(PhotoImage.fileName(at: Date(timeIntervalSince1970: date))))
        }
    }

    // MARK: The colour profile

    /// A picture in Display P3: the one a phone's camera or screenshot may carry.
    private func displayP3(_ width: Int, _ height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(colorSpace: space, components: [0, 0, 1, 1])!)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    /// The ICC profiles a JPEG carries: each APP2 `ICC_PROFILE` payload, in order.
    private func profiles(_ jpeg: Data) -> [Data] {
        let bytes = [UInt8](jpeg)
        var found: [Data] = []
        var i = 2
        while i + 4 <= bytes.count, bytes[i] == 0xFF {
            let marker = bytes[i + 1]
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if marker == 0xE2, bytes[(i + 4)...].starts(with: Array("ICC_PROFILE\0".utf8)) {
                found.append(Data(bytes[(i + 4)..<(i + 2 + length)]))
            }
            if marker == 0xDA { break }
            i += 2 + length
        }
        return found
    }

    @Test func aDisplayP3PictureComesOutAsSRGBWithOnlyThatProfile() throws {
        let picture = try displayP3(400, 300)
        let p3 = try #require(PhotoFixture.encode(picture, as: .jpeg))
        // The input really is in Display P3, with its profile in it.
        #expect((PhotoFixture.properties(p3)["ProfileName"] as? String)?.contains("Display P3") == true)
        let photo = try made(PhotoImage.process(p3, at: when))
        let out = PhotoFixture.properties(photo.data)
        #expect(out["ProfileName"] as? String == "sRGB IEC61966-2.1")
        // At most one, and it is the small standard one, not the source's.
        let carried = profiles(photo.data)
        #expect(carried.count <= 1)
        #expect(carried.allSatisfy { $0.count < 4_096 })
        #expect(photo.data.range(of: Data("Display P3".utf8)) == nil)
        // The colours were converted, not just relabelled: P3's pure red is outside sRGB and is clamped to it.
        #expect(near(PhotoFixture.pixel(photo.data, x: 50, y: 150), 255, 0, 0))
        #expect(near(PhotoFixture.pixel(photo.data, x: 350, y: 150), 0, 0, 255))
    }

    @Test func aProfileOfTheSourcesOwnMakingNeverSurvives() throws {
        // A hostile file's ICC segment: big, and bytes nothing should pass on.
        let marker = Array("hostile-profile-bytes".utf8)
        let junk = Array("ICC_PROFILE\0".utf8) + [1, 1] + (0..<60_000).map { marker[$0 % marker.count] }
        let base = try #require(PhotoFixture.encode(PhotoFixture.picture(120, 90), as: .jpeg))
        let hostile = withSegments([segment(0xE2, junk)], into: base)
        #expect(hostile.range(of: Data(marker)) != nil)
        let photo = try made(PhotoImage.process(hostile, at: when))
        #expect(photo.data.range(of: Data(marker)) == nil)
        #expect(profiles(photo.data).allSatisfy { $0.count < 4_096 })
        #expect(PhotoFixture.properties(photo.data)["ProfileName"] as? String == "sRGB IEC61966-2.1")
        // The picture is still the picture.
        #expect(photo.width == 120 && photo.height == 90)
    }

    @Test(arguments: ["png", "grey", "cmyk", "alpha"])
    func everyKindOfSourceComesOutAsSRGB(_ kind: String) throws {
        let data: Data
        switch kind {
        case "grey":
            let space = CGColorSpaceCreateDeviceGray()
            let context = try #require(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
            let drawn = try #require(context.makeImage())
            data = try #require(PhotoFixture.encode(drawn, as: .png))
        case "cmyk":
            let space = CGColorSpaceCreateDeviceCMYK()
            let context = try #require(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(CGColor(colorSpace: space, components: [0, 1, 1, 0, 1])!)
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
            let drawn = try #require(context.makeImage())
            data = try #require(PhotoFixture.encode(drawn, as: .jpeg))
        case "alpha": data = try #require(PhotoFixture.encode(PhotoFixture.halfTransparent(60, 40), as: .png))
        default: data = PhotoFixture.png
        }
        let photo = try made(PhotoImage.process(data, at: when))
        #expect(PhotoFixture.properties(photo.data)["ProfileName"] as? String == "sRGB IEC61966-2.1", "\(kind)")
        #expect(profiles(photo.data).count <= 1 && profiles(photo.data).allSatisfy { $0.count < 4_096 }, "\(kind)")
    }

    // MARK: Stripping

    private func withSegments(_ segments: [[UInt8]], into jpeg: Data) -> Data {
        Data(jpeg.prefix(2)) + Data(segments.flatMap { $0 }) + jpeg.dropFirst(2)
    }

    private func segment(_ marker: UInt8, _ payload: [UInt8]) -> [UInt8] {
        let length = payload.count + 2
        return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
    }

    @Test func everyMarkerButJFIFAndAnICCProfileGoes() throws {
        let base = try #require(PhotoFixture.encode(PhotoFixture.picture(64, 48), as: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N"],
        ]))
        #expect(PhotoFixture.markers(base).contains(0xE1))
        let icc = segment(0xE2, Array("ICC_PROFILE\0".utf8) + [1, 1, 9, 9])
        let mpf = segment(0xE2, Array("MPF\0".utf8) + [1, 2, 3])
        let comment = segment(0xFE, Array("made-up comment".utf8))
        let xmp = segment(0xE1, Array("http://ns.adobe.com/xap/1.0/\0".utf8) + [60, 120])
        let adobe = segment(0xEE, Array("Adobe".utf8) + [0, 100, 0, 0, 0, 0, 1])
        let thumbnail = segment(0xE0, Array("JFXX\0".utf8) + [0x10] + Array(repeating: 7, count: 30))
        let messy = withSegments([comment, xmp, icc, mpf, adobe, thumbnail], into: base)
        let clean = try #require(PhotoImage.stripMetadata(messy))
        let markers = PhotoFixture.markers(clean)
        #expect(markers.filter { $0 == 0xE0 }.count == 1)
        #expect(markers.filter { $0 == 0xE2 }.count == 1)
        for gone: UInt8 in [0xE1, 0xED, 0xFE, 0xEE] { #expect(!markers.contains(gone)) }
        #expect(clean.range(of: Data("made-up comment".utf8)) == nil)
        #expect(clean.range(of: Data("JFXX".utf8)) == nil)
        #expect(clean.range(of: Data("MPF".utf8)) == nil)
        #expect(clean.range(of: Data("ICC_PROFILE".utf8)) != nil)
        // The scan is untouched, and the end marker is still the end.
        #expect(clean.suffix(2) == Data([0xFF, 0xD9]))
        // Without the bogus profile, it is still a picture of the same size.
        let plain = try #require(PhotoImage.stripMetadata(withSegments([comment, xmp], into: base)))
        let properties = PhotoFixture.properties(plain)
        #expect(properties["PixelWidth"] as? Int == 64 && properties["PixelHeight"] as? Int == 48)
        #expect(properties["{GPS}"] == nil)
        #expect(plain.range(of: Data("Exif".utf8)) == nil)
    }

    @Test func aJPEGThatDoesntParseIsNotStripped() {
        #expect(PhotoImage.stripMetadata(Data()) == nil)
        #expect(PhotoImage.stripMetadata(Data("not a jpeg".utf8)) == nil)
        #expect(PhotoImage.stripMetadata(Data([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x40, 0x00])) == nil)
        #expect(PhotoImage.stripMetadata(Data([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x01, 0x00, 0x00])) == nil)
        #expect(PhotoImage.stripMetadata(Data([0xFF, 0xD8, 0x12, 0x34, 0x56, 0x78])) == nil)
    }
}

// MARK: The attachment line and the text

struct PhotoLineTests {
    static let attachment = PhotoAttachment(id: "11111111-2222-4333-8444-555555555555",
                                            versionID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
                                            filename: "phone-photo-20261012-193000.jpg", contentType: "image/jpeg", sizeBytes: 123_456)

    @Test func theLineIsExactlyTheComposersInThatKeyOrder() {
        #expect(Self.attachment.line == #"{"type":"attachment","id":"11111111-2222-4333-8444-555555555555","version_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","filename":"phone-photo-20261012-193000.jpg","artifact_ref":"{{artifact:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee}}","content_type":"image/jpeg","size_bytes":123456}"#)
    }

    @Test func itIsWhatJSONStringifyWritesForTheChip() {
        let a = Self.attachment
        let script = PageScript()
        let line = script.evaluate("""
        JSON.stringify({ type: "attachment", id: "\(a.id)", version_id: "\(a.versionID)", filename: "\(a.filename)",
                         artifact_ref: "{{artifact:\(a.versionID)}}", content_type: "\(a.contentType)", size_bytes: \(a.sizeBytes) })
        """)
        #expect(line == a.line)
        let parsed = (try? JSONSerialization.jsonObject(with: Data(a.line.utf8))) as? [String: Any]
        #expect(parsed?.count == 7)
        #expect(parsed?["artifact_ref"] as? String == "{{artifact:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee}}")
        #expect(parsed?["size_bytes"] as? Int == 123_456)
    }

    @Test func aValueIsEscapedAsJSONStringifyEscapesIt() {
        #expect(PhotoAttachment.quoted(#"a"b\c"#) == #""a\"b\\c""#)
        #expect(PhotoAttachment.quoted("a\nb\tc\u{01}") == #""a\nb\tc\u0001""#)
        #expect(PhotoAttachment.quoted("a/b é 界") == "\"a/b é 界\"")
        let script = PageScript()
        script.set("__s", "q\"u\\o\nte\u{1F}")
        #expect(script.evaluate("JSON.stringify(__s)") == PhotoAttachment.quoted("q\"u\\o\nte\u{1F}"))
    }

    @Test func theRequestIsTheTextABlankLineAndTheLine() {
        let line = Self.attachment.line
        #expect(PhotoText.request(text: "Look at this gel.", attachment: Self.attachment) == "Look at this gel.\n\n" + line)
        #expect(PhotoText.request(text: "", attachment: Self.attachment) == line)
        #expect(PhotoText.title(text: "Look at this gel.") == "Look at this gel.")
        #expect(PhotoText.title(text: "") == "Photo")
        #expect(PhotoText.title(text: String(repeating: "a", count: 80)).count == 50)
    }

    @Test func aUUIDAndAPhotoNameAreOfTheirShapes() {
        for good in ["11111111-2222-4333-8444-555555555555", "AAAAAAAA-bbbb-4CCC-8ddd-eeeeeeeeeeee", "019e5f3c-0000-7000-8000-000000000001"] {
            #expect(PhotoAttachment.isUUID(good))
        }
        for bad in ["", "11111111-2222-4333-8444-55555555555", "11111111222243338444555555555555", "g1111111-2222-4333-8444-555555555555",
                    "11111111-2222-4333-8444-5555555555555", "11111111_2222_4333_8444_555555555555"] {
            #expect(!PhotoAttachment.isUUID(bad), "\(bad)")
        }
        #expect(PhotoAttachment.isPhotoName("phone-photo-20261012-193000.jpg"))
        for bad in ["", "phone-photo-20261012-193000.jpeg", "Phone-photo-20261012-193000.jpg", "phone-photo-2026101-193000.jpg",
                    "phone-photo-20261012_193000.jpg", "phone-photo-20261012-193000.jpg ", "../phone-photo-20261012-193000.jpg",
                    "phone-photo-20261012-19300a.jpg", "phone-photo-20261012-1930000.jpg", "IMG_0001.HEIC", #"phone-photo-20261012-193000".jpg"#] {
            #expect(!PhotoAttachment.isPhotoName(bad), "\(bad)")
        }
    }
}
