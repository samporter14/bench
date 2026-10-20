// RemoteArtifacts.swift — the phone's artifact routes (DESIGN.md, Bench on your
// phone → Phase 3: Artifacts):
//
//   GET /api/sessions/<id>/artifacts   the session's list, projected in the page
//   GET /api/files/<v>/thumb?w=120|800 a WebP thumbnail, for an image
//   GET /api/files/<v>/text            markdown, text or a table, as JSON
//   GET /api/files/<v>/download        the bytes, as an attachment, ≤ 8 MB
//
// A device may fetch only the versions listed to it (`ListedFiles`), and how a
// file is shown comes from that listing (`ListedFileInfo`), never from the
// request. Nothing a file holds is ever served as a page on Bench's origin:
// text and tables travel as JSON strings, thumbnails only once their bytes say
// WebP, and downloads as `attachment` under `sandbox`. The decisions are pure
// and tested; `RemoteArtifacts` reads through an injected closure: the page in
// the app, made-up files in `--demo remote` and the tests. Nothing here logs.
import Foundation

// MARK: The routes

/// The four routes, matched exactly and never decoded: a session id
/// `^[0-9a-f-]{36}$`, a version id `^[A-Za-z0-9_-]{1,128}$`.
enum RemoteFilesRoute: Equatable, Sendable {
    case list(session: String)
    case thumb(version: String)
    case text(version: String)
    case download(version: String)

    init?(path: Substring) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "api" else { return nil }
        let id = String(parts[3])
        switch (parts[2], parts[4]) {
        case ("sessions", "artifacts") where PlanCheck.isFrameID(id): self = .list(session: id)
        case ("files", "thumb") where PlanCheck.isVersionID(id): self = .thumb(version: id)
        case ("files", "text") where PlanCheck.isVersionID(id): self = .text(version: id)
        case ("files", "download") where PlanCheck.isVersionID(id): self = .download(version: id)
        default: return nil
        }
    }

    /// What the log names: never an id.
    var pattern: String {
        switch self {
        case .list: "/api/sessions/<id>/artifacts"
        case .thumb: "/api/files/<v>/thumb"
        case .text: "/api/files/<v>/text"
        case .download: "/api/files/<v>/download"
        }
    }
}

// MARK: What was listed

/// How each listed version is shown: its name, type, size and kind, as the
/// listing said, kept an hour from when it was last listed. `/text`, `/thumb`
/// and `/download` read the kind and size from here, never from the request.
/// Whatever lists versions to a device (an artifacts list, a history page's
/// `files`) records them here as well as in `ListedFiles`.
@MainActor
final class ListedFileInfo {
    static let shared = ListedFileInfo()

    static let lifetime = ListedFiles.lifetime
    /// At most this many versions; the oldest go first, a tenth at a time
    /// (`ListedFiles.evict`), so a full list isn't sorted at every insert.
    static let capacity = 8_000

    struct Info: Equatable, Sendable {
        let name: String
        let mime: String?
        let size: Int
        let kind: ArtifactKind
    }

    private var infos: [String: (info: Info, at: Date)] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func record(_ version: String, _ info: Info) {
        let time = now()
        infos[version] = (info, time)
        guard infos.count > Self.capacity else { return }
        infos = ListedFiles.evict(infos, capacity: Self.capacity, at: time, lifetime: Self.lifetime, when: \.at)
    }

    /// How many versions are held: for tests.
    var count: Int { infos.count }

    func info(_ version: String) -> Info? {
        guard let entry = infos[version], now().timeIntervalSince(entry.at) < Self.lifetime else { return nil }
        return entry.info
    }
}

// MARK: Headers

/// The headers an artifact goes out with, pure. `RemoteResponse` adds
/// `no-store`, `nosniff`, `no-referrer` and CORP `same-origin` to every
/// response; these add the rest.
enum ArtifactHeaders {
    /// On every artifact route's response: nothing it carries may run.
    static let contentSecurityPolicy = "default-src 'none'; sandbox"
    static let octetStream = "application/octet-stream"
    /// The ASCII `filename` is cut to this many characters, the UTF-8
    /// `filename*` to this many characters of the name.
    static let asciiLimit = 150
    static let encodedLimit = 180

    /// The raster type the bytes' magic says: PNG, JPEG, GIF or WebP. Nil
    /// for anything else, whatever its name or kind says.
    static func sniff(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return "image/gif" }
        if isWebP(data) { return "image/webp" }
        return nil
    }

    /// `RIFF????WEBP`.
    static func isWebP(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        return bytes.count == 12 && bytes[0..<4].elementsEqual("RIFF".utf8) && bytes[8..<12].elementsEqual("WEBP".utf8)
    }

    /// A download's `Content-Type`: the sniffed raster type, only for a file
    /// listed as an image whose bytes agree; everything else is bytes.
    static func downloadType(kind: ArtifactKind, data: Data) -> String {
        guard kind == .image, let type = sniff(data), type != "image/svg+xml" else { return octetStream }
        return type
    }

    /// `attachment; filename="<ASCII-safe>"; filename*=UTF-8''<percent-encoded>`.
    static func disposition(_ name: String) -> String {
        "attachment; filename=\"\(asciiName(name))\"; filename*=UTF-8''\(encodedName(name))"
    }

    /// Printable ASCII only, without quotes, backslashes, separators or `%`;
    /// a leading dot made visible; the extension kept when cut; "file" when
    /// nothing is left.
    static func asciiName(_ name: String) -> String {
        let forbidden = Set("\"\\/:;%*?<>|".unicodeScalars)
        var scalars = String.UnicodeScalarView()
        // "Résumé" reads "Resume"; what is left outside ASCII becomes "_".
        let folded = baseName(name).folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        for scalar in folded.unicodeScalars where !isInvisible(scalar) {
            if (0x20...0x7E).contains(scalar.value), !forbidden.contains(scalar) {
                scalars.append(scalar)
            } else if scalar.properties.isWhitespace {
                scalars.append(" ")
            } else {
                scalars.append("_")
            }
        }
        var text = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if text.isEmpty || text.allSatisfy({ $0 == "_" }) { text = "file" }
        if baseName(name).hasPrefix(".") { text = "_" + text }
        return shortened(text, limit: asciiLimit)
    }

    /// RFC 8187: UTF-8, every byte outside `[A-Za-z0-9._-]` percent-encoded.
    static func encodedName(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in baseName(name).unicodeScalars where !isInvisible(scalar) { scalars.append(scalar) }
        var text = String(scalars).trimmingCharacters(in: .whitespaces)
        if text.isEmpty { text = "file" }
        text = shortened(text, limit: encodedLimit)
        var out = ""
        for byte in text.utf8 {
            if (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || byte == 0x2E || byte == 0x5F || byte == 0x2D {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// The last path segment: a name never carries a folder.
    private static func baseName(_ name: String) -> String {
        String(name.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? "")
    }

    /// Controls and direction overrides: dropped, never shown.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || scalar.value == 0x200E || scalar.value == 0x200F
            || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
    }

    /// At most `limit` characters, keeping a short extension.
    private static func shortened(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let ext = (text as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 16 else { return String(text.prefix(limit)) }
        return String(text.prefix(limit - ext.count - 1)) + "." + ext
    }
}

// MARK: Tables

/// A CSV or TSV file as the phone shows it: the first record as the columns,
/// then at most 200 rows of at most 30 cells of at most 200 characters, every
/// row as wide as the widest. RFC 4180 quoting (`""` inside quotes, line
/// breaks inside quotes), CRLF, LF or CR line ends, a leading BOM skipped;
/// lenient where files aren't (a quote mid-field is kept as it is, text after
/// a closing quote is kept, an unclosed quote runs to the end).
struct ArtifactTable: Equatable, Sendable {
    static let maxRows = 200
    static let maxColumns = 30
    static let maxCell = 200
    /// What a cell holds while it is read; beyond it, it is cut anyway.
    private static let cellScalars = 4 * maxCell

    let columns: [String]
    let rows: [[String]]
    /// Rows, columns, cells or the file itself were cut.
    let truncated: Bool

    /// Tab for `.tsv` or `text/tab-separated-values`, else comma.
    static func delimiter(name: String, mime: String?) -> Unicode.Scalar {
        if (name as NSString).pathExtension.lowercased() == "tsv" { return "\t" }
        if (mime ?? "").lowercased().hasPrefix("text/tab-separated-values") { return "\t" }
        return ","
    }

    /// `cutShort`: the text is only the start of the file, so a last record
    /// without its line end is dropped as incomplete.
    static func parse(_ text: String, delimiter: Unicode.Scalar, cutShort: Bool) -> ArtifactTable {
        let scalars = Array(text.unicodeScalars)
        var builder = Builder()
        var index = scalars.first == "\u{FEFF}" ? 1 : 0
        var inQuotes = false
        // Something was read since the last line end: a blank line is no record.
        var open = false
        while index < scalars.count, !builder.full {
            let scalar = scalars[index]
            index += 1
            if inQuotes {
                if scalar != "\"" {
                    builder.append(scalar)
                } else if index < scalars.count, scalars[index] == "\"" {
                    // `""` is one quote.
                    builder.append("\"")
                    index += 1
                } else {
                    inQuotes = false
                }
                continue
            }
            switch scalar {
            case delimiter:
                open = true
                builder.endField()
            case "\n", "\r":
                if scalar == "\r", index < scalars.count, scalars[index] == "\n" { index += 1 }
                if open { builder.endRecord() }
                open = false
            case "\"" where !builder.fieldSeen:
                inQuotes = true
                open = true
                builder.fieldSeen = true
            default:
                open = true
                builder.append(scalar)
            }
        }
        if open, !builder.full {
            // Only the start of the file: its last record is incomplete.
            if cutShort { builder.cut = true } else { builder.endRecord() }
        }
        return builder.table(cutShort: cutShort)
    }

    private struct Builder {
        var records: [[String]] = []
        var record: [String] = []
        /// Fields ended in this record, kept or not.
        var fields = 0
        var cell = String.UnicodeScalarView()
        var cellLength = 0
        var cellCut = false
        /// Anything (a character, an opening quote) was read in this field.
        var fieldSeen = false
        /// Rows, columns or a cell were cut.
        var cut = false
        /// A record past the 200th row came: nothing more is read.
        var full = false

        mutating func append(_ scalar: Unicode.Scalar) {
            fieldSeen = true
            // Past the 30th column nothing is kept, only scanned over.
            guard fields < ArtifactTable.maxColumns else { return }
            if cellLength < ArtifactTable.cellScalars {
                cell.append(scalar)
                cellLength += 1
            } else {
                cellCut = true
            }
        }

        mutating func endField() {
            if fields < ArtifactTable.maxColumns {
                var text = String(cell)
                if cellCut || text.count > ArtifactTable.maxCell {
                    text = String(text.prefix(ArtifactTable.maxCell - 1)) + "…"
                    cut = true
                }
                record.append(text)
            } else {
                cut = true
            }
            fields += 1
            cell = String.UnicodeScalarView()
            cellLength = 0
            cellCut = false
            fieldSeen = false
        }

        mutating func endRecord() {
            endField()
            if records.count > ArtifactTable.maxRows {
                full = true
                cut = true
            } else {
                records.append(record)
            }
            record = []
            fields = 0
        }

        func table(cutShort: Bool) -> ArtifactTable {
            let width = records.map(\.count).max() ?? 0
            let padded = records.map { $0 + Array(repeating: "", count: width - $0.count) }
            return ArtifactTable(columns: padded.first ?? [], rows: Array(padded.dropFirst()), truncated: cut || cutShort)
        }
    }
}

// MARK: The answers

/// A files route's answer: status, type, extra headers and body.
struct RemoteFilesReply: Equatable, Sendable {
    struct Header: Equatable, Sendable {
        let name: String
        let value: String
    }

    let status: Int
    let contentType: String
    let headers: [Header]
    let body: Data

    /// The whole response, as the server sends it.
    var response: Data {
        RemoteResponse.make(status: status, contentType: contentType, body: body,
                            headers: headers.map { ($0.name, $0.value) })
    }

    private static let sandbox = Header(name: "Content-Security-Policy", value: ArtifactHeaders.contentSecurityPolicy)

    static func json(_ body: Data, status: Int = 200) -> RemoteFilesReply {
        RemoteFilesReply(status: status, contentType: RemoteResponse.json, headers: [sandbox], body: body)
    }

    /// `{"error": "…"}`.
    static func error(_ status: Int, _ reason: String) -> RemoteFilesReply {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": reason], options: [.sortedKeys])) ?? Data()
        return json(body, status: status)
    }

    static let browseOff = error(403, "browseOff")
    static let notFound = error(404, "Not Found")
    static let tooBig = error(413, "tooBig")
    /// The page couldn't read it, or what it read didn't match.
    static let unreadable = error(503, "unreadable")

    /// A thumbnail: WebP, shown by `<img>`, never a page.
    static func webp(_ data: Data) -> RemoteFilesReply {
        RemoteFilesReply(status: 200, contentType: "image/webp", headers: [sandbox], body: data)
    }

    /// A download: always an attachment, under `sandbox`.
    static func download(_ data: Data, name: String, kind: ArtifactKind) -> RemoteFilesReply {
        RemoteFilesReply(status: 200, contentType: ArtifactHeaders.downloadType(kind: kind, data: data),
                         headers: [Header(name: "Content-Disposition", value: ArtifactHeaders.disposition(name)), sandbox],
                         body: data)
    }
}

/// The JSON the routes answer.
enum ArtifactJSON {
    struct List: Encodable {
        let artifacts: [Item]
    }

    struct Item: Encodable {
        let v: String
        let a: String?
        let name: String
        let kind: ArtifactKind
        let size: Int
        let mime: String?
        let at: Date?

        private enum CodingKeys: String, CodingKey {
            case v, a, name, kind, size, mime, at
        }

        // Written out so a missing value is `null`, not left out.
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(v, forKey: .v)
            try c.encode(a, forKey: .a)
            try c.encode(name, forKey: .name)
            try c.encode(kind, forKey: .kind)
            try c.encode(size, forKey: .size)
            try c.encode(mime, forKey: .mime)
            try c.encode(at, forKey: .at)
        }
    }

    /// `{"kind":"markdown"|"text","text","truncated"}`.
    struct Text: Encodable {
        let kind: ArtifactKind
        let text: String
        let truncated: Bool
    }

    /// `{"kind":"table","columns","rows","truncated"}`.
    struct Table: Encodable {
        let kind: ArtifactKind
        let columns: [String]
        let rows: [[String]]
        let truncated: Bool
    }

    /// Documents, then images, then tables, then the rest; the list's own
    /// order (oldest first) within each.
    static func bucket(_ kind: ArtifactKind) -> Int {
        switch kind {
        case .markdown, .pdf, .html, .notebook: 0
        case .image, .svg: 1
        case .table: 2
        case .text, .other: 3
        }
    }

    static func sorted(_ entries: [ArtifactEntry]) -> [ArtifactEntry] {
        entries.enumerated().sorted { lhs, rhs in
            let left = bucket(lhs.element.kind), right = bucket(rhs.element.kind)
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

// MARK: What may be read

/// What may be read of a listed version, and whether what came back may be
/// used: the phone's routes and the results shelf (Results/ResultsShelf.swift)
/// ask the very same questions, with the kind and size from the listing,
/// never from whoever asks.
enum ArtifactGate {
    enum Refusal: Error, Equatable, Sendable {
        /// Not a kind this read is for.
        case kind
        /// Over the cap: 4 MB for a thumbnail, 8 MB for a download.
        case tooBig
        /// A thumbnail whose bytes don't say WebP.
        case notWebP
    }

    /// A thumbnail: only of an image.
    static func thumb(kind: ArtifactKind) -> Refusal? {
        kind == .image ? nil : .kind
    }

    /// Text: only of markdown, text and tables.
    static func text(kind: ArtifactKind) -> Refusal? {
        RemoteArtifacts.textKinds.contains(kind) ? nil : .kind
    }

    /// A download: only when the listing's own size is within 8 MB.
    static func download(size: Int) -> Refusal? {
        size <= ArtifactReaderScript.Cap.download ? nil : .tooBig
    }

    /// A thumbnail's bytes: within 4 MB, and WebP by their own first bytes.
    static func thumbBytes(_ data: Data) -> Result<Data, Refusal> {
        guard data.count <= ArtifactReaderScript.Cap.thumb else { return .failure(.tooBig) }
        return ArtifactHeaders.isWebP(data) ? .success(data) : .failure(.notWebP)
    }

    /// A download's bytes: within 8 MB, whatever the listing said.
    static func downloadBytes(_ data: Data) -> Result<Data, Refusal> {
        data.count <= ArtifactReaderScript.Cap.download ? .success(data) : .failure(.tooBig)
    }
}

// MARK: Serving

/// The four routes over an injected read. Order of the checks: the browse
/// switch (403 `browseOff`); for the list, a session Bench knows (404); for
/// a file, listed to this device within the hour with its listing at hand
/// (404), a kind the route serves (415 `kind`), a size it serves (413
/// `tooBig`, from the listing first); then the read (503 `unreadable` when it
/// fails), and the bytes checked again.
@MainActor
final class RemoteArtifacts {
    static let shared = RemoteArtifacts(dependencies: .live())

    struct Dependencies {
        /// Settings → Phone → "Let paired devices browse…" (`remoteBrowse`).
        var browseOn: @MainActor () -> Bool
        /// A root session the phone may open: one Bench knows now, or, while
        /// browse is on, any in the database (`RemoteSessions.admitted`).
        var isSession: @MainActor (String) async -> Bool
        /// The page's read, checked (`WebContainer.readArtifact`). The live one is abortable: cancelling the task
        /// awaiting it (the phone hung up, `RemoteServer.hungUp`) stops the page's fetch too (`ArtifactReadAbort`).
        var read: @MainActor (ArtifactRead) async -> ArtifactReadOutcome
        var listed: ListedFiles
        var info: ListedFileInfo

        /// `perform` reads under a nonce and `abort` stops the fetch filed under one; tests stand in for the page.
        @MainActor static func live(
            perform: @escaping @MainActor (ArtifactRead, String) async -> ArtifactReadOutcome = { read, nonce in
                (try? await WebContainer.shared.readArtifact(read, nonce: nonce)) ?? .unreadable
            },
            abort: @escaping @Sendable @MainActor (String) async -> Void = { nonce in
                await WebContainer.shared.abortArtifactRead(nonce)
            }) -> Dependencies {
            Dependencies(
                browseOn: { RemoteBrowse.isOn },
                isSession: { id in await RemoteSessions.shared.admitted(id) != nil },
                read: { read in
                    guard Demo.mode == nil else { return .unreadable }
                    return await ArtifactReadAbort.abortable(read, perform: perform, abort: abort)
                },
                listed: .shared,
                info: .shared)
        }
    }

    /// The kinds `/text` serves.
    nonisolated static let textKinds: Set<ArtifactKind> = [.markdown, .text, .table]

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// One request. `target` is the request's own (for `?w=`).
    func respond(_ route: RemoteFilesRoute, target: String, device: String) async -> RemoteFilesReply {
        guard dependencies.browseOn() else { return .browseOff }
        switch route {
        case .list(let session):
            return await list(session, device: device)
        case .thumb(let version):
            guard let info = listed(version, device: device) else { return .notFound }
            guard let width = Self.width(target) else { return .error(400, "width") }
            if let refusal = ArtifactGate.thumb(kind: info.kind) { return Self.reply(refusal) }
            switch await dependencies.read(.thumb(version: version, width: width)) {
            case .bytes(let data):
                switch ArtifactGate.thumbBytes(data) {
                case .success(let data): return .webp(data)
                case .failure(let refusal): return Self.reply(refusal)
                }
            case .tooBig: return .tooBig
            default: return .unreadable
            }
        case .text(let version):
            guard let info = listed(version, device: device) else { return .notFound }
            if let refusal = ArtifactGate.text(kind: info.kind) { return Self.reply(refusal) }
            switch await dependencies.read(.text(version: version)) {
            case .text(let text, let truncated): return Self.text(text, truncated: truncated, info: info)
            case .binary: return .error(415, "notText")
            default: return .unreadable
            }
        case .download(let version):
            guard let info = listed(version, device: device) else { return .notFound }
            if let refusal = ArtifactGate.download(size: info.size) { return Self.reply(refusal) }
            switch await dependencies.read(.download(version: version)) {
            case .bytes(let data):
                switch ArtifactGate.downloadBytes(data) {
                case .success(let data): return .download(data, name: info.name, kind: info.kind)
                case .failure(let refusal): return Self.reply(refusal)
                }
            case .tooBig: return .tooBig
            default: return .unreadable
            }
        }
    }

    /// A gate's refusal, as the phone's routes answer it.
    private static func reply(_ refusal: ArtifactGate.Refusal) -> RemoteFilesReply {
        switch refusal {
        case .kind: .error(415, "kind")
        case .tooBig: .tooBig
        case .notWebP: .error(415, "notWebP")
        }
    }

    private func list(_ session: String, device: String) async -> RemoteFilesReply {
        guard await dependencies.isSession(session) else { return .notFound }
        guard case .list(let entries) = await dependencies.read(.list(frame: session)) else { return .unreadable }
        let sorted = ArtifactJSON.sorted(entries)
        dependencies.listed.record(sorted.map(\.version), device: device)
        for entry in sorted {
            dependencies.info.record(entry.version, ListedFileInfo.Info(name: entry.name, mime: entry.mime,
                                                                        size: entry.size, kind: entry.kind))
        }
        let items = sorted.map {
            ArtifactJSON.Item(v: $0.version, a: $0.artifact, name: $0.name, kind: $0.kind, size: $0.size,
                              mime: $0.mime, at: $0.at)
        }
        return .json(RemoteAPI.encode(ArtifactJSON.List(artifacts: items)))
    }

    /// Listed to this device, with its listing at hand.
    private func listed(_ version: String, device: String) -> ListedFileInfo.Info? {
        guard dependencies.listed.allows(version, device: device) else { return nil }
        return dependencies.info.info(version)
    }

    /// `?w=120` or `?w=800`, and nothing else.
    static func width(_ target: String) -> Int? {
        guard let query = target.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        switch query {
        case "w=120": return 120
        case "w=800": return 800
        default: return nil
        }
    }

    /// Markdown and text as they are (a leading BOM dropped); a table parsed.
    static func text(_ text: String, truncated: Bool, info: ListedFileInfo.Info) -> RemoteFilesReply {
        var text = text
        if text.unicodeScalars.first == "\u{FEFF}" { text = String(text.unicodeScalars.dropFirst()) }
        if info.kind == .table {
            let table = ArtifactTable.parse(text, delimiter: ArtifactTable.delimiter(name: info.name, mime: info.mime),
                                            cutShort: truncated)
            return .json(RemoteAPI.encode(ArtifactJSON.Table(kind: .table, columns: table.columns, rows: table.rows,
                                                             truncated: table.truncated)))
        }
        return .json(RemoteAPI.encode(ArtifactJSON.Text(kind: info.kind, text: text, truncated: truncated)))
    }
}
