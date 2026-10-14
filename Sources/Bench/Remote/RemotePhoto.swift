// RemotePhoto.swift — the phone's photos, the pure part (DESIGN.md, Bench on
// your phone → Phase 4: Photos): the two routes, their body, the check of the
// text, what Bench does to the picture, the attachment line, and the text a
// photo's message carries. Nothing here reads a session or touches the page;
// `RemotePhotoUpload.swift` is the in-page upload and `RemotePhotos.swift` the
// flow around it.
//
// The picture is never forwarded as it came. Bench decodes it with ImageIO
// and draws it again through the thumbnail API with the transform flag (the
// orientation is baked in), as a JPEG of at most 3,072 px and 3 MB, then
// drops every marker but JFIF and an ICC profile: GPS, EXIF, XMP and the
// rest never leave the phone's picture for Claude Science. The phone's own
// file name is never used either.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: The routes

/// `POST /api/sessions/<id>/photo` and `POST /api/projects/<pid>/photo`.
enum RemotePhotoRoute: Equatable, Sendable {
    case session(String)
    case project(String)

    /// The two paths, matched exactly and never decoded: a full frame id
    /// (`^[0-9a-f-]{36}$`), or a project id (`^[A-Za-z0-9_-]{1,64}$`).
    init?(path: Substring) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "api", parts[4] == "photo" else { return nil }
        switch parts[2] {
        case "sessions":
            guard PlanCheck.isFrameID(String(parts[3])) else { return nil }
            self = .session(String(parts[3]))
        case "projects":
            guard BrowseSQL.isProjectID(parts[3]) else { return nil }
            self = .project(String(parts[3]))
        default:
            return nil
        }
    }

    var method: String { "POST" }

    /// What the log names: the table's own pattern, never an id.
    var pattern: String {
        switch self {
        case .session: "/api/sessions/<id>/photo"
        case .project: "/api/projects/<pid>/photo"
        }
    }

    /// A body of up to 6 MB: 3 MB of JPEG is 4 MB of base64, and the text
    /// and the JSON around it. Only these two routes take it.
    static let bodyLimit = 6 * 1024 * 1024
    /// A photo makes Bench decode, draw, encode and hand the page 4 MB.
    static let cost = 10

    /// How long a body may go quiet: every chunk that arrives starts the wait
    /// again, so a slow phone isn't cut off at the flat 3 s the other routes
    /// have, and a body that stalls is.
    static let idleTimeout: TimeInterval = 10
    /// The most the whole body may take, however steadily it arrives.
    static let totalTimeout: TimeInterval = 120

    /// How long to wait for more of the body, `elapsed` seconds in.
    static func bodyWait(elapsed: TimeInterval) -> TimeInterval {
        max(0.1, min(idleTimeout, totalTimeout - max(0, elapsed)))
    }
}

extension RemoteRoute {
    /// How long this route's body may stay quiet once its head has passed
    /// every check, `elapsed` seconds after that: a photo's re-arms as data
    /// arrives (`rearmsBodyTimer`); every other route has the flat
    /// `RemoteServer.bodyTimeout`.
    func bodyWait(elapsed: TimeInterval) -> Duration {
        if case .photo = self { return .milliseconds(Int((RemotePhotoRoute.bodyWait(elapsed: elapsed) * 1000).rounded())) }
        return RemoteServer.bodyTimeout
    }

    var rearmsBodyTimer: Bool {
        if case .photo = self { return true }
        return false
    }
}

// MARK: The body

/// Why a photo was turned away, and the answer the phone gets.
enum PhotoRefusal: Error, Equatable, Sendable {
    /// 400: not JSON, a field out of shape, a base64 that doesn't decode.
    case badRequest
    /// 400 `{"error":"reference"}`: the text holds one of the UI's reference
    /// prefixes, which Claude Science would read as an attachment or an
    /// artifact.
    case reference
    /// 415 `{"error":"notAnImage"}`: not a JPEG, PNG or HEIC ImageIO can read.
    case notAnImage
    /// 413 `{"error":"tooBig"}`: too many pixels, or no JPEG small enough.
    case tooBig

    var reply: RemoteActionReply {
        switch self {
        case .badRequest: .badRequest
        case .reference: Self.reply(400, "reference")
        case .notAnImage: Self.reply(415, "notAnImage")
        case .tooBig: Self.reply(413, "tooBig")
        }
    }

    private static func reply(_ status: Int, _ error: String) -> RemoteActionReply {
        RemoteActionReply(status: status, body: Data(#"{"error":"\#(error)"}"#.utf8))
    }
}

/// `{"image":"<base64>","text":"…0–4,000","id":"<uuid v4>","planFirst":false}`,
/// checked. `planFirst` is the project route's; the session route ignores it.
struct PhotoRequest: Equatable, Sendable {
    let image: Data
    /// Trimmed; empty for a photo alone.
    let text: String
    let intentID: String
    let planFirst: Bool

    static let textLimit = RemoteActionRequest.messageLimit

    static func parse(_ body: Data, project: Bool) -> Result<PhotoRequest, PhotoRefusal> {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let id = Pick.string(root["id"]), RemoteActionRequest.isUUIDv4(id) else { return .failure(.badRequest) }
        var text = ""
        if !Pick.isNull(root["text"]) {
            guard let given = Pick.string(root["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  given.unicodeScalars.count <= textLimit else { return .failure(.badRequest) }
            text = given
        }
        var planFirst = false
        if project, !Pick.isNull(root["planFirst"]) {
            guard let given = Pick.bool(root["planFirst"]) else { return .failure(.badRequest) }
            planFirst = given
        }
        guard !PhotoText.hasReference(text) else { return .failure(.reference) }
        guard let encoded = Pick.string(root["image"]), let image = PhotoBase64.decode(encoded), !image.isEmpty else {
            return .failure(.badRequest)
        }
        return .success(PhotoRequest(image: image, text: text, intentID: id, planFirst: planFirst))
    }
}

/// Standard base64, as the phone's `btoa` writes it: padded, no whitespace,
/// no line breaks, nothing Foundation might forgive.
enum PhotoBase64 {
    static func decode(_ text: String) -> Data? {
        var count = 0
        var padding = 0
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2B, 0x2F:
                guard padding == 0 else { return nil }
            case 0x3D:
                padding += 1
                guard padding <= 2 else { return nil }
            default:
                return nil
            }
            count += 1
        }
        guard count > 0, count % 4 == 0 else { return nil }
        return Data(base64Encoded: text)
    }
}

// MARK: The text

enum PhotoText {
    /// What the UI itself neutralises in typed text: any of these in a
    /// message could pass for an attachment, an artifact, a skill or a
    /// session the person never attached.
    static let referencePrefixes = [
        "{{artifact:", #"{"type":"artifact""#, #"{"type":"attachment""#, #"{"type":"skill""#,
        #"{"type":"session""#, #"{"artifact_ref":"#, #"{"file_path":"#,
    ]

    /// Whether the text holds one, as it is or with its whitespace taken out
    /// (`{ "type" : "attachment"`).
    static func hasReference(_ text: String) -> Bool {
        guard text.contains("{") else { return false }
        let squeezed = String(text.unicodeScalars.filter { !$0.properties.isWhitespace })
        return referencePrefixes.contains { text.contains($0) || squeezed.contains($0) }
    }

    /// `input_data.request`: the text, a blank line, then the attachment
    /// line; the line alone for a photo with no text.
    static func request(text: String, attachment: PhotoAttachment) -> String {
        text.isEmpty ? attachment.line : text + "\n\n" + attachment.line
    }

    /// What a new session is called until the daemon names it: the text's
    /// first 50 characters, or "Photo" for a photo alone (the request's own
    /// first 50 characters would be the line).
    static func title(text: String) -> String {
        text.isEmpty ? "Photo" : String(text.prefix(50))
    }
}

// MARK: The attachment line

/// What the daemon says it stored, once it has passed the page's gate and
/// Swift's own.
struct PhotoAttachment: Equatable, Sendable {
    let id: String
    let versionID: String
    let filename: String
    let contentType: String
    let sizeBytes: Int

    /// The line Claude Science's own composer puts in a message for a chip:
    /// `{"type":"attachment","id","version_id","filename","artifact_ref":"{{artifact:<vid>}}","content_type","size_bytes"}`,
    /// in exactly that key order and with no spaces. Written key by key, never
    /// from a dictionary, whose order Swift doesn't keep.
    var line: String {
        "{\"type\":\"attachment\",\"id\":\(Self.quoted(id)),\"version_id\":\(Self.quoted(versionID)),"
            + "\"filename\":\(Self.quoted(filename)),\"artifact_ref\":\(Self.quoted("{{artifact:" + versionID + "}}")),"
            + "\"content_type\":\(Self.quoted(contentType)),\"size_bytes\":\(sizeBytes)}"
    }

    /// A JSON string as `JSON.stringify` writes it.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// `8-4-4-4-12` hex digits, any case.
    static func isUUID(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                if byte != 0x2D { return false }
            } else if !((0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)) {
                return false
            }
        }
        return true
    }

    /// `^phone-photo-\d{8}-\d{6}\.jpg$`: the only name Bench gives a photo.
    static func isPhotoName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        let prefix = Array("phone-photo-".utf8), suffix = Array(".jpg".utf8)
        guard bytes.count == prefix.count + 15 + suffix.count, bytes.starts(with: prefix), bytes.suffix(4).elementsEqual(suffix)
        else { return false }
        let middle = bytes[prefix.count..<(prefix.count + 15)]
        return middle.enumerated().allSatisfy { $0.offset == 8 ? $0.element == 0x2D : (0x30...0x39).contains($0.element) }
    }
}

// MARK: The picture

/// A photo as Bench sends it on.
struct PhotoFile: Equatable, Sendable {
    let data: Data
    let name: String
    let width: Int
    let height: Int

    var contentType: String { PhotoImage.contentType }
}

enum PhotoImage {
    static let contentType = "image/jpeg"
    static let maxLongSide = 3_072
    static let maxBytes = 3 * 1024 * 1024
    /// 64 megapixels, the daemon's own limit: read from the header, before
    /// anything is decoded.
    static let maxPixels = 64_000_000
    static let startQuality = 0.85
    static let qualityStep = 0.05
    static let lowestQuality = 0.4

    enum Kind: Equatable, Sendable {
        case jpeg, png, heic
    }

    /// The magic bytes, whatever the phone says the type is: JPEG
    /// `FF D8 FF`, PNG `89 50 4E 47 0D 0A 1A 0A`, HEIC `ftyp` at offset 4
    /// with the brand `heic`, `heix` or `mif1`.
    static func kind(of data: Data) -> Kind? {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if head.count == 12, Array(head[4..<8]) == Array("ftyp".utf8),
           [Array("heic".utf8), Array("heix".utf8), Array("mif1".utf8)].contains(Array(head[8..<12])) { return .heic }
        return nil
    }

    /// `phone-photo-YYYYMMDD-HHMMSS.jpg`, in UTC.
    static func fileName(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "phone-photo-%04d%02d%02d-%02d%02d%02d.jpg", c.year ?? 1970, c.month ?? 1, c.day ?? 1,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Checks, decodes and draws the picture again. The size and the pixel
    /// count are parameters only so the tests needn't make a 64 MP image.
    static func process(_ data: Data, at now: Date, maxBytes: Int = maxBytes,
                        maxPixels: Int = maxPixels) -> Result<PhotoFile, PhotoRefusal> {
        guard kind(of: data) != nil,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.jpeg", "public.png", "public.heic", "public.heif"].contains(type),
              CGImageSourceGetCount(source) >= 1 else { return .failure(.notAnImage) }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return .failure(.notAnImage) }
        guard width <= maxPixels, height <= maxPixels, width * height <= maxPixels else { return .failure(.tooBig) }

        // JPEG at 0.85 and lower, then smaller, until it fits.
        var side = min(maxLongSide, max(width, height))
        for _ in 0..<5 {
            guard let thumbnail = thumbnail(source, index: index, side: side), let drawn = flattened(thumbnail) else {
                return .failure(.notAnImage)
            }
            var quality = startQuality
            while quality >= lowestQuality - 0.001 {
                guard let jpeg = encode(drawn, quality: quality), let clean = stripMetadata(jpeg) else {
                    return .failure(.notAnImage)
                }
                if clean.count <= maxBytes {
                    guard readable(clean, width: drawn.width, height: drawn.height) else { return .failure(.notAnImage) }
                    return .success(PhotoFile(data: clean, name: fileName(at: now), width: drawn.width, height: drawn.height))
                }
                quality -= qualityStep
            }
            side = max(64, Int(Double(side) * 0.75))
        }
        return .failure(.tooBig)
    }

    /// The picture upright (`WithTransform`), drawn from the whole image
    /// (`FromImageAlways`, never the small preview a file may carry), no
    /// larger than `side` and never enlarged.
    private static func thumbnail(_ source: CGImageSource, index: Int, side: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    /// A JPEG has no alpha: a picture that has some is drawn on white first
    /// (as the daemon does), not left to turn black. One that is neither RGB
    /// nor grey (CMYK, Lab) is drawn as sRGB: a CMYK JPEG needs the Adobe
    /// marker `stripMetadata` drops, and the daemon's own decoder wants RGB.
    private static func flattened(_ image: CGImage) -> CGImage? {
        let model = image.colorSpace?.model
        let plain = model == .rgb || model == .monochrome
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: if plain { return image }
        default: break
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let space, let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// The JPEG, with no properties given: nothing of the source's metadata
    /// is written.
    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let jpeg = data as Data
        return jpeg.starts(with: [0xFF, 0xD8, 0xFF]) ? jpeg : nil
    }

    /// ImageIO still writes a small Exif segment (the colour space and the
    /// pixel size) and a Photoshop one. Every marker but JFIF and an ICC
    /// profile goes, so no APP1 (Exif, XMP), APP13 (IPTC), comment or other
    /// application segment is left. The scan itself is copied as it is.
    static func stripMetadata(_ jpeg: Data) -> Data? {
        let bytes = [UInt8](jpeg)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        var i = 2
        while i + 2 <= bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }
            // Markers with no length: a restart, a temporary, the end.
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                out += bytes[i..<(i + 2)]
                i += 2
                continue
            }
            if marker == 0xD9 {
                out += bytes[i...]
                return Data(out)
            }
            guard i + 4 <= bytes.count else { return nil }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return nil }
            let payload = bytes[(i + 4)..<(i + 2 + length)]
            let keep: Bool
            switch marker {
            case 0xE0: keep = payload.starts(with: Array("JFIF\0".utf8)) && length <= 16
            case 0xE2: keep = payload.starts(with: Array("ICC_PROFILE\0".utf8))
            case 0xE1, 0xE3...0xEF, 0xFE: keep = false
            default: keep = true
            }
            if keep { out += bytes[i..<(i + 2 + length)] }
            i += 2 + length
            // The scan: everything after its header goes as it is.
            if marker == 0xDA {
                out += bytes[i...]
                return Data(out)
            }
        }
        return nil
    }

    /// The JPEG that came out reads back as one image of the size it was drawn.
    private static func readable(_ jpeg: Data, width: Int, height: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == width
            && (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == height
    }
}
