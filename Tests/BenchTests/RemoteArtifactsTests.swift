// RemoteArtifactsTests.swift — the phone's artifact routes (Phase 3 files) on
// made-up files. The in-page reader is the very JavaScript the page runs, run
// here in JavaScriptCore against a fake `fetch` that serves bytes; Swift's own
// checks, the table parser, the headers and the routes run on what it returns.
// Every file, name and id is invented; fields Bench must never pass on hold
// "SECRET" so a leak shows. Nothing reaches a real daemon.
import Foundation
import ImageIO
import JavaScriptCore
import Testing
@testable import Bench

// MARK: A page that serves bytes

/// `ArtifactReaderScript.body` in JavaScriptCore, with a `fetch` that answers
/// from a table by path and streams bytes through `body.getReader()`.
private final class ArtifactPage {
    struct Answer: Encodable {
        var status = 200
        var headers: [String: String] = [:]
        /// A JSON or text body, for `text()`.
        var text: String?
        /// The first bytes of the body.
        var bytes: [UInt8] = []
        /// The body's whole length: past `bytes`, made of `fill` in the script.
        var length: Int?
        var fill = 0x41
        var chunk = 65_536
    }

    struct Seen: Decodable, Equatable {
        let path: String
        let cache: String?
        let credentials: String?
        let range: String?
        let accept: String?
        /// Bytes handed to the reader.
        let pulled: Int
        let cancelled: Bool
    }

    private let script = PageScript(ArtifactPage.fake)

    private static let fake = """
    var __seen = [];
    var __table = {};
    var document = { cookie: "" };
    var AbortSignal = function () {};
    AbortSignal.timeout = function () { return undefined; };
    var fetch = function (path, init) {
        init = init || {};
        var headers = init.headers || {};
        var seen = { path: path, cache: init.cache || null, credentials: init.credentials || null,
                     range: headers["Range"] || null, accept: headers["Accept"] || null, pulled: 0, cancelled: false };
        __seen.push(seen);
        var answer = __table[path];
        if (!answer) { return Promise.reject(new Error("no answer")); }
        var length = typeof answer.length === "number" ? answer.length : answer.bytes.length;
        var bytes = new Uint8Array(length);
        bytes.fill(answer.fill);
        bytes.set(answer.bytes.slice(0, length), 0);
        var offset = 0;
        var cancel = function () { seen.cancelled = true; return Promise.resolve(); };
        var body = {
            getReader: function () {
                return {
                    read: function () {
                        if (seen.cancelled || offset >= bytes.length) { return Promise.resolve({ done: true, value: undefined }); }
                        var end = Math.min(bytes.length, offset + answer.chunk);
                        var value = bytes.subarray(offset, end);
                        offset = end;
                        seen.pulled = offset;
                        return Promise.resolve({ done: false, value: value });
                    },
                    cancel: cancel,
                };
            },
            cancel: cancel,
        };
        var lower = {};
        for (var name in answer.headers) { lower[name.toLowerCase()] = answer.headers[name]; }
        return Promise.resolve({
            status: answer.status, ok: answer.status >= 200 && answer.status < 300,
            headers: { get: function (name) { var v = lower[String(name).toLowerCase()]; return v === undefined ? null : v; } },
            body: body,
            text: function () { return Promise.resolve(typeof answer.text === "string" ? answer.text : ""); },
        });
    };
    var __result = null;
    """

    /// Runs one read; returns what the page answered (raw and checked) and
    /// the requests it made.
    func run(_ read: ArtifactRead, _ answers: [String: Answer]) -> (raw: String?, outcome: ArtifactReadOutcome, seen: [Seen]) {
        run(arguments: Self.arguments(read), answers, read: read)
    }

    func run(arguments: String, _ answers: [String: Answer], read: ArtifactRead) -> (raw: String?, outcome: ArtifactReadOutcome, seen: [Seen]) {
        let table = (try? JSONEncoder().encode(answers)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        script.set("__answers", table)
        script.set("__args", arguments)
        script.evaluate("__seen = []; __table = JSON.parse(__answers); __result = null;")
        script.evaluate("""
        (function (a) {
            return (async function (op, frameId, versionId, width, artifactId) {
            \(ArtifactReaderScript.body)
            })(a.op, a.frameId, a.versionId, a.width, a.artifactId);
        })(JSON.parse(__args)).then(function (v) { __result = v; }, function (e) { __result = "threw: " + e; });
        """)
        #expect(script.exception == nil)
        let raw = script.evaluate("__result")
        let seenJSON = script.evaluate("JSON.stringify(__seen)") ?? "[]"
        let seen = (try? JSONDecoder().decode([Seen].self, from: Data(seenJSON.utf8))) ?? []
        let outcome = raw.map { ArtifactReaderScript.outcome(of: Data($0.utf8), for: read) } ?? .unreadable
        return (raw, outcome, seen)
    }

    static func arguments(_ read: ArtifactRead) -> String {
        let object = read.arguments.mapValues { $0 is NSNull ? NSNull() : $0 }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Calls a pure function of the script with JSON arguments.
    func call(_ function: String, _ arguments: [String?]) -> String? {
        script.callJSON(function, arguments)
    }

    /// Runs any expression with the reader's functions defined.
    func evaluate(_ source: String) -> String? {
        script.evaluate(ArtifactReaderScript.pathBuilder + "\n" + ArtifactReaderScript.projection + "\n"
                        + ArtifactReaderScript.keepProjection + "\n" + ArtifactReaderScript.codecs + "\n" + source)
    }

    func set(_ name: String, _ value: String) {
        script.set(name, value)
    }
}

private enum Made {
    static let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
    static let version = "ver_Made-up_01"
    static let listPath = "/api/frames/\(session)/artifacts"
    static let versionPath = "/api/artifacts/versions/\(version)"

    /// One row as the daemon lists it, with every field Bench must drop.
    static func row(_ name: String, version: String = "ver_1", type: String = "text/plain", size: Int = 12,
                    extra: String = "", created: String = "\"2026-10-12T19:30:00Z\"") -> String {
        let quoted = String(decoding: try! JSONEncoder().encode(name), as: UTF8.self)
        return """
        {"id": "art_1", "version_id": "\(version)", "version_number": 1, "root_frame_id": "\(session)",
         "frame_id": "SECRET-FRAME", "creating_frame_id": "SECRET-CREATOR", "filename": \(quoted),
         "content_type": "\(type)", "size_bytes": \(size), "created_at": \(created), "is_user_upload": false,
         "is_intermediate": false, "priority": "normal", "superseded_by_artifact_id": null,
         "checksum": "SECRET-CHECKSUM", "agent_name": "SECRET-AGENT",
         "file_path": "/Users/someone/SECRET-PATH/file.bin", "ref_host_path": "/Users/someone/SECRET-HOST"\(extra)}
        """
    }

    // Keep's reads: made-up 36-character ids and rows. Every path here is under
    // /opt/made-up, and every field Capsid must drop holds "SECRET".
    static let artifact = "6d1f0c2e-7a3b-4c8d-9e10-2b3c4d5e6f70"
    static let other = "7e20d1f3-8b4c-4d9e-8f21-3c4d5e6f7081"
    static let v1 = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
    static let v2 = "2d9e4b60-3c4d-4e5f-8011-c2d3e4f5a6b7"
    static let v3 = "3eaf5c71-4d5e-4f60-9122-d3e4f5a6b7c8"
    static let frame = "4fb06d82-5e6f-4071-a233-e4f5a6b7c8d9"
    static let digest = String(repeating: "ab12", count: 16)
    static let versionsPath = "/api/artifacts/\(artifact)/versions"
    static func factsPath(_ v: String = v3) -> String { "/api/artifacts/versions/\(v)?include_metadata=true" }
    static func lineagePath(_ v: String = v3) -> String { "/api/artifacts/versions/\(v)/lineage?slim=1" }

    /// An id of 36 characters for the n-th made-up row.
    static func id(_ n: Int) -> String { String(format: "%08lx-0000-4000-8000-%012lx", n, n) }

    static func json(_ object: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    /// One row of `/versions` as the daemon writes it, with every field Capsid must drop.
    static func versionRow(_ v: String, n: Int, frame: String? = Made.frame, type: String = "image/png", size: Int = 2048,
                           created: Any = "2026-10-12T19:30:00.000Z", parent: String? = nil) -> [String: Any] {
        ["version_id": v, "version_number": n, "artifact_id": artifact, "frame_id": frame ?? NSNull(),
         "agent_name": "SECRET-AGENT", "language": "SECRET-LANGUAGE", "content_type": type, "size_bytes": size,
         "created_at": created, "file_path": "/opt/made-up/SECRET-PATH/fig.png", "parent_version_id": parent ?? NSNull()]
    }

    static func versions(_ rows: [[String: Any]]) -> String { json(rows) }

    /// The answer of `?include_metadata=true`, `edit`ed.
    static func facts(version: String = v3, _ edit: (inout [String: Any]) -> Void = { _ in }) -> String {
        var object: [String: Any] = [
            "artifact_id": artifact, "version_id": version, "version_number": 3, "filename": "plots/z_prime.png",
            "content_type": "image/png; charset=binary", "size_bytes": 86016, "created_at": "2026-10-12T19:30:00.000Z",
            "agent_name": "SECRET-AGENT", "is_user_upload": false, "checksum": digest,
            "file_path": "/opt/made-up/SECRET-PATH/z_prime.png", "ref_host_path": "/opt/made-up/SECRET-HOST"]
        edit(&object)
        return json(object)
    }

    static let code = "import pandas as pd\nplot({{artifact:\(v2)}})\n"

    static var mapping: [String: Any] {
        ["inputs": [
            ["filename": "plate_reader.csv", "artifact_id": other, "version_id": v2, "workspace_path": NSNull(),
             "consensus": "runtime", "read_cell_id": "SECRET-CELL"] as [String: Any],
            ["filename": NSNull(), "workspace_path": "/opt/made-up/SECRET-WORKSPACE/raw/notes.xlsx", "consensus": "ast_only"],
        ], "outputs": [["SECRET": "output"]], "mapping_status": "complete", "mapping_attempts": 1]
    }

    /// The answer of `lineage?slim=1`, `edit`ed.
    static func lineage(version: String = v3, _ edit: (inout [String: Any]) -> Void = { _ in }) -> String {
        var object: [String: Any] = [
            "artifact_id": artifact, "version_id": version, "version_number": 3, "filename": "z_prime.png",
            "code": code, "code_description": "Plots Z prime by plate.", "messages": NSNull(),
            "environment_snapshot": NSNull(), "language": "python", "interactions": NSNull(), "has_cell_sources": true,
            "has_messages": true, "has_environment": true, "pending": false, "dependency_mappings": mapping]
        edit(&object)
        return json(object)
    }

    static func entry(_ name: String, version: String = "ver_1", mime: String? = nil, size: Int = 12) -> ArtifactEntry {
        ArtifactEntry(version: version, artifact: "art_\(version)", name: name, mime: mime, size: size, at: nil)
    }
}

// MARK: Paths

struct ArtifactPathTests {
    @Test func theThreeShapesAndNothingElse() {
        let frame = Made.session, v = Made.version
        #expect(ArtifactRead.list(frame: frame).path == "/api/frames/\(frame)/artifacts")
        #expect(ArtifactRead.thumb(version: v, width: 120).path == "/api/artifacts/versions/\(v)?thumbnail=120")
        #expect(ArtifactRead.thumb(version: v, width: 800).path == "/api/artifacts/versions/\(v)?thumbnail=800")
        #expect(ArtifactRead.text(version: v).path == "/api/artifacts/versions/\(v)")
        #expect(ArtifactRead.download(version: v).path == "/api/artifacts/versions/\(v)")

        let hostile = ["", "../etc", "a/b", "a?b", "a%2Fb", "a b", "ü", "a.b", String(repeating: "a", count: 129), "a\n"]
        for version in hostile {
            #expect(ArtifactRead.text(version: version).path == nil)
            #expect(ArtifactRead.thumb(version: version, width: 120).path == nil)
        }
        #expect(ArtifactRead.thumb(version: v, width: 121).path == nil)
        #expect(ArtifactRead.thumb(version: v, width: 0).path == nil)
        for frame in [String(Made.session.dropLast()), Made.session.uppercased(), "../" + Made.session.dropFirst(3), ""] {
            #expect(ArtifactRead.list(frame: frame).path == nil)
        }
    }

    @Test func thePageBuildsTheSamePathsAsSwift() {
        let page = ArtifactPage()
        let cases: [ArtifactRead] = [
            .list(frame: Made.session), .list(frame: Made.session.uppercased()), .list(frame: "x"),
            .thumb(version: Made.version, width: 120), .thumb(version: Made.version, width: 800),
            .thumb(version: Made.version, width: 400), .thumb(version: "../x", width: 120),
            .text(version: Made.version), .text(version: "a/b"), .text(version: "a?thumbnail=800"),
            .download(version: Made.version), .download(version: String(repeating: "z", count: 129)),
        ]
        for read in cases {
            page.set("__args", ArtifactPage.arguments(read))
            let built = page.evaluate("var a = JSON.parse(__args); JSON.stringify(benchArtifactPath(a.op, a.frameId, a.versionId, a.width, a.artifactId))")
            let expected = read.path.map { "\"\($0)\"" } ?? "null"
            #expect(built == expected, "\(read)")
        }
        // A width that is a string, an unknown op: no path.
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('thumb', null, 'v1', '800'))") == "null")
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('delete', null, 'v1', null))") == "null")
    }

    @Test func theAllowlistIsExact() {
        #expect(ArtifactRead.isAllowedPath("/api/frames/\(Made.session)/artifacts"))
        #expect(ArtifactRead.isAllowedPath("/api/artifacts/versions/v1"))
        #expect(ArtifactRead.isAllowedPath("/api/artifacts/versions/v1?thumbnail=120"))
        #expect(!ArtifactRead.isAllowedPath("/api/artifacts/versions/v1?thumbnail=400"))
        #expect(!ArtifactRead.isAllowedPath("/api/artifacts/versions/v1?include_metadata=true"))
        #expect(!ArtifactRead.isAllowedPath("/api/artifacts/versions/v1/../x"))
        #expect(!ArtifactRead.isAllowedPath("/api/frames/\(Made.session)/artifacts/download"))
        #expect(!ArtifactRead.isAllowedPath("/api/artifacts/v1"))
        #expect(!ArtifactRead.isAllowedPath("/api/projects/p/artifacts"))
    }

    @Test func aReadThatMakesNoPathIsRefusedInThePageBeforeAnyFetch() {
        let read = ArtifactRead.text(version: "../../x")
        let result = ArtifactPage().run(read, [:])
        #expect(result.raw == #"{"outcome":"refused"}"#)
        #expect(result.seen.isEmpty)
        #expect(result.outcome == .unreadable)
    }
}

// MARK: The list

struct ArtifactListTests {
    private func project(_ rows: String, cap: Int = 300) -> (json: String?, entries: [ArtifactEntry]?) {
        let page = ArtifactPage()
        let json = page.evaluate("JSON.stringify(benchProjectArtifacts(\(rows), \(cap)))")
        guard let json, json != "null" else { return (json, nil) }
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return (json, ArtifactReaderScript.entries(object))
    }

    @Test func onlyTheSixFieldsLeaveThePage() throws {
        let rows = "[\(Made.row("figure.png", version: "v1", type: "image/png", size: 2048)), \(Made.row("notes.md", version: "v2", type: "text/markdown; charset=utf-8"))]"
        let (json, entries) = project(rows)
        let text = try #require(json)
        #expect(!text.contains("SECRET"))
        #expect(!text.contains("/Users"))
        let list = try #require(entries)
        #expect(list.map(\.version) == ["v1", "v2"])
        #expect(list[0] == ArtifactEntry(version: "v1", artifact: "art_1", name: "figure.png", mime: "image/png", size: 2048,
                                         at: Date(timeIntervalSince1970: 1_791_833_400)))
        #expect(list[1].mime == "text/markdown")
        #expect(list.map(\.kind) == [.image, .markdown])
        let keys = try #require((try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])?.first?.keys)
        #expect(Set(keys) == ["v", "a", "name", "mime", "size", "at"])
    }

    @Test func whatTheUIHidesStaysHidden() throws {
        let rows = """
        [\(Made.row("kept.csv", version: "keep")),
         \(Made.row("step.csv", version: "h1", extra: #", "is_intermediate": true"#)),
         \(Made.row("mine.csv", version: "h2", extra: #", "priority": "user_hidden""#)),
         \(Made.row("plan.json", version: "h3")), \(Made.row("plan_v2.json", version: "h4")),
         \(Made.row("work/plan-final.json", version: "h5")), \(Made.row("goal_1.html", version: "h6")),
         \(Made.row("goal.html", version: "keep2")), \(Made.row("my-plan.json", version: "keep3"))]
        """
        let list = try #require(project(rows).entries)
        #expect(list.map(\.version) == ["keep", "keep2", "keep3"])
    }

    @Test func namesLoseFoldersControlsAndLength() throws {
        let long = String(repeating: "n", count: 400) + ".txt"
        let rows = """
        [\(Made.row("results/run 1/figure.png", version: "a")), \(Made.row("C:\\\\data\\\\table.csv", version: "b")),
         \(Made.row("evil\u{0}\u{202E}gnp.txt\r\n", version: "c")), \(Made.row(long, version: "d")),
         \(Made.row("folder/", version: "e"))]
        """
        let list = try #require(project(rows).entries)
        #expect(list.map(\.name).prefix(3) == ["figure.png", "table.csv", "evilgnp.txt"])
        #expect(list[3].name.unicodeScalars.count == 255)
        #expect(list[3].name.hasSuffix("…"))
        #expect(list[4].name == "file")
    }

    @Test func typesAndTimesAreCleanedOrNull() throws {
        let rows = """
        [\(Made.row("a.csv", version: "a", type: "Text/CSV; charset=utf-8", created: "1791833400")),
         \(Made.row("b.bin", version: "b", type: "nonsense", created: "\"yesterday\"")),
         \(Made.row("c.bin", version: "c", type: "", created: "1791833400000"))]
        """
        let list = try #require(project(rows).entries)
        #expect(list.map(\.mime) == ["text/csv", nil, nil])
        #expect(list.map(\.at) == [Date(timeIntervalSince1970: 1_791_833_400), nil, Date(timeIntervalSince1970: 1_791_833_400)])
    }

    @Test func eitherEnvelopeIsRead() {
        #expect(project("[\(Made.row("a.txt"))]").entries?.count == 1)
        #expect(project("{\"artifacts\": [\(Made.row("a.txt"))]}").entries?.count == 1)
        #expect(project("[]").entries == [])
        #expect(project("{\"items\": []}").entries == nil)
        #expect(project("\"[]\"").entries == nil)
        #expect(project("null").entries == nil)
    }

    @Test func aShapeThatDoesntMatchReadsNothing() {
        let bad = [
            Made.row("a.txt").replacingOccurrences(of: #""version_id": "ver_1""#, with: #""version_id": 7"#),
            Made.row("a.txt", version: "a/b"),
            Made.row("a.txt", version: "../x"),
            Made.row("a.txt").replacingOccurrences(of: #""size_bytes": 12"#, with: #""size_bytes": "12""#),
            Made.row("a.txt", size: -1),
            Made.row("a.txt").replacingOccurrences(of: #""id": "art_1""#, with: #""id": 1"#),
            Made.row("a.txt").replacingOccurrences(of: #""content_type": "text/plain""#, with: #""content_type": null"#),
            "\"just a string\"",
        ]
        for row in bad {
            #expect(project("[\(Made.row("ok.txt", version: "ok")), \(row)]").json == "null", "\(row.prefix(80))")
        }
    }

    @Test func theNewestThreeHundredAreKept() throws {
        let rows = "[" + (0..<350).map { Made.row("f\($0).txt", version: "v\($0)") }.joined(separator: ",") + "]"
        let list = try #require(project(rows).entries)
        #expect(list.count == 300)
        #expect(list.first?.version == "v50")
        #expect(list.last?.version == "v349")
    }

    @Test func swiftChecksEveryFieldAgain() {
        func entries(_ json: String) -> [ArtifactEntry]? {
            ArtifactReaderScript.entries(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
        }
        let good = #"{"v":"v1","a":"art","name":"a.txt","mime":"text/plain","size":3,"at":null}"#
        #expect(entries("[\(good)]")?.count == 1)
        #expect(entries("[\(good), \(good)]")?.count == 1)
        for bad in [
            #"{"v":"a/b","a":null,"name":"a.txt","mime":null,"size":3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a\u0007.txt","mime":null,"size":3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a\u202e.txt","mime":null,"size":3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"","mime":null,"size":3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a.txt","mime":"text","size":3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a.txt","mime":"Text/Plain","size":3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a.txt","mime":null,"size":-3,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a.txt","mime":null,"size":true,"at":null}"#,
            #"{"v":"v1","a":null,"name":"a.txt","mime":null,"size":3,"at":"today"}"#,
        ] {
            #expect(entries("[\(bad)]") == nil, "\(bad)")
        }
        let many = "[" + (0...300).map { #"{"v":"v\#($0)","a":null,"name":"a.txt","mime":null,"size":1,"at":null}"# }
            .joined(separator: ",") + "]"
        #expect(entries(many) == nil)
    }
}

// MARK: The codecs

struct ArtifactCodecTests {
    private let page = ArtifactPage()

    private func base64(_ bytes: [UInt8]) -> String? {
        page.set("__bytes", String(decoding: try! JSONEncoder().encode(bytes), as: UTF8.self))
        return page.evaluate("benchBase64(new Uint8Array(JSON.parse(__bytes)))")
    }

    private func decode(_ bytes: [UInt8], truncated: Bool = false) -> String? {
        page.set("__bytes", String(decoding: try! JSONEncoder().encode(bytes), as: UTF8.self))
        return page.evaluate("benchDecodeUTF8(new Uint8Array(JSON.parse(__bytes)), \(truncated))")
    }

    @Test func base64MatchesSwiftForEveryLengthAndByte() {
        for length in 0...7 {
            let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 97 &+ 13) }
            #expect(base64(bytes) == Data(bytes).base64EncodedString(), "length \(length)")
        }
        let every = (0...255).map(UInt8.init)
        #expect(base64(every) == Data(every).base64EncodedString())
        let big = (0..<100_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }
        #expect(base64(big) == Data(big).base64EncodedString())
    }

    private func chunked(_ bytes: [UInt8]) -> String? {
        page.set("__bytes", String(decoding: try! JSONEncoder().encode(bytes), as: UTF8.self))
        _ = page.evaluate("""
            var __chunked = null;
            benchBase64Chunked(new Uint8Array(JSON.parse(__bytes))).then(function (v) { __chunked = v; });
            """)
        return page.evaluate("__chunked")
    }

    /// Fable's review of 0.5.0, P3: in pieces, the same text as in one go.
    @Test func base64InPiecesIsTheSameAtEveryEdge() {
        let chunk = 3 * 174_762
        for length in [0, 1, 2, 3, chunk - 1, chunk, chunk + 1, chunk + 2, 2 * chunk + 2, 3 * chunk] {
            let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ 7) }
            #expect(chunked(bytes) == Data(bytes).base64EncodedString(), "length \(length)")
        }
    }

    @Test func utf8DecodesAsSwiftDoes() {
        let cases: [[UInt8]] = [
            Array("plain ascii".utf8), Array("é 日本 🧪 Ω".utf8),
            [0xC0, 0x80], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0x80], [0xFF, 0x41],
            [0xE6, 0x97], [0x41, 0xF0, 0x9F, 0xA7, 0x42], [0xE0, 0x80, 0x80], [0xF5, 0x80],
        ]
        for bytes in cases {
            #expect(decode(bytes) == String(decoding: bytes, as: UTF8.self), "\(bytes)")
        }
    }

    @Test func aSequenceTheRangeCutIsDropped() {
        let text = Array("ab日".utf8)
        #expect(decode(Array(text.dropLast()), truncated: true) == "ab")
        #expect(decode(Array(text.dropLast(2)), truncated: true) == "ab")
        #expect(decode(Array("x🧪".utf8).dropLast(1).map { $0 }, truncated: true) == "x")
        #expect(decode(Array("x🧪".utf8), truncated: true) == "x🧪")
        // Not cut short: the stray start shows as U+FFFD.
        #expect(decode(Array(text.dropLast()), truncated: false) == "ab\u{FFFD}")
    }
}

// MARK: The reads, in the page

struct ArtifactReadTests {
    private let page = ArtifactPage()

    @Test func theListIsOneNoStoreGet() throws {
        let rows = "[\(Made.row("figure.png", version: "v1", type: "image/png"))]"
        let result = page.run(.list(frame: Made.session), [Made.listPath: .init(text: rows)])
        #expect(result.seen.map(\.path) == [Made.listPath])
        #expect(result.seen.first?.cache == "no-store")
        #expect(result.seen.first?.credentials == "include")
        #expect(result.seen.first?.accept == "application/json")
        #expect(result.seen.first?.range == nil)
        guard case .list(let entries) = result.outcome else { Issue.record("not a list"); return }
        #expect(entries.map(\.name) == ["figure.png"])
        #expect(!(result.raw ?? "").contains("SECRET"))
    }

    @Test func aListThatFailsIsUnreadable() {
        // A session that isn't there any more is told apart (the results shelf says so).
        #expect(page.run(.list(frame: Made.session), [Made.listPath: .init(status: 404, text: "{}")]).outcome == .missing)
        #expect(page.run(.list(frame: Made.session), [Made.listPath: .init(status: 500, text: "{}")]).outcome == .unreadable)
        #expect(page.run(.list(frame: Made.session), [Made.listPath: .init(status: 200, text: "<html>")]).outcome == .unreadable)
        #expect(page.run(.list(frame: Made.session), [:]).outcome == .unreadable)
        #expect(page.run(.list(frame: Made.session), [Made.listPath: .init(status: 401, text: "")]).outcome == .lost)
    }

    @Test func aThumbnailIsItsBytes() {
        let path = Made.versionPath + "?thumbnail=800"
        let webp = Array("RIFF".utf8) + [4, 0, 0, 0] + Array("WEBPVP8L".utf8) + [1, 2, 3]
        let result = page.run(.thumb(version: Made.version, width: 800), [path: .init(bytes: webp)])
        #expect(result.seen.map(\.path) == [path])
        #expect(result.seen.first?.cache == "no-store")
        #expect(result.outcome == .bytes(Data(webp)))
    }

    @Test func aThumbnailOverFourMegabytesIsRefused() {
        let path = Made.versionPath + "?thumbnail=120"
        let cap = ArtifactReaderScript.Cap.thumb
        // By its length: not read at all.
        let declared = page.run(.thumb(version: Made.version, width: 120),
                                [path: .init(headers: ["Content-Length": "\(cap + 1)"], length: cap + 1)])
        #expect(declared.outcome == .tooBig)
        #expect(declared.seen.first?.pulled == 0)
        #expect(declared.seen.first?.cancelled == true)
        // Without a length: read up to the cap, then given up.
        let streamed = page.run(.thumb(version: Made.version, width: 120), [path: .init(length: cap + 1)])
        #expect(streamed.outcome == .tooBig)
        #expect(streamed.seen.first?.cancelled == true)
        #expect((streamed.seen.first?.pulled ?? .max) <= cap + 65_536)
        // At the cap: fine.
        let exact = page.run(.thumb(version: Made.version, width: 120), [path: .init(length: cap)])
        guard case .bytes(let data) = exact.outcome else { Issue.record("not bytes"); return }
        #expect(data.count == cap)
    }

    @Test func aDownloadUpToEightMegabytesComesWholeAndNoMore() {
        let cap = ArtifactReaderScript.Cap.download
        let exact = page.run(.download(version: Made.version),
                             [Made.versionPath: .init(headers: ["Content-Length": "\(cap)"], bytes: [0x89, 0x50], length: cap)])
        #expect(exact.seen.first?.range == nil)
        guard case .bytes(let data) = exact.outcome else { Issue.record("not bytes"); return }
        #expect(data.count == cap)
        #expect(data.prefix(3) == Data([0x89, 0x50, 0x41]))
        let over = page.run(.download(version: Made.version), [Made.versionPath: .init(length: cap + 1)])
        #expect(over.outcome == .tooBig)
        let declared = page.run(.download(version: Made.version),
                                [Made.versionPath: .init(headers: ["content-length": "999999999999"], length: 10)])
        #expect(declared.outcome == .tooBig)
        #expect(declared.seen.first?.pulled == 0)
    }

    @Test func otherStatusesAreUnreadable() {
        for status in [204, 206, 302, 403, 500] {
            let result = page.run(.download(version: Made.version), [Made.versionPath: .init(status: status, length: 4)])
            #expect(result.outcome == .unreadable, "\(status)")
        }
        #expect(page.run(.download(version: Made.version), [Made.versionPath: .init(status: 401)]).outcome == .lost)
    }

    /// A version deleted or expired is told apart from a failure, for every
    /// read, and nothing of its body is read.
    @Test func aVersionThatIsGoneIsMissing() {
        for status in [404, 410] {
            for read in [ArtifactRead.download(version: Made.version), .text(version: Made.version),
                         .thumb(version: Made.version, width: 120)] {
                let result = page.run(read, [Made.versionPath: .init(status: status, length: 4),
                                             Made.versionPath + "?thumbnail=120": .init(status: status, length: 4)])
                #expect(result.outcome == .missing, "\(status) \(read)")
            }
        }
    }

    @Test func textIsARangeReadOfTheFirst256KB() {
        let small = page.run(.text(version: Made.version),
                             [Made.versionPath: .init(status: 206, headers: ["Content-Range": "bytes 0-10/11"],
                                                      bytes: Array("# Made up\nok".utf8.prefix(11)))])
        #expect(small.seen.first?.range == "bytes=0-262143")
        #expect(small.seen.first?.accept == "*/*")
        #expect(small.outcome == .text("# Made up\no", truncated: false))

        let longer = page.run(.text(version: Made.version),
                              [Made.versionPath: .init(status: 206, headers: ["Content-Range": "bytes 0-262143/1000000"],
                                                       length: 262_144)])
        guard case .text(let text, let truncated) = longer.outcome else { Issue.record("not text"); return }
        #expect(text.unicodeScalars.count == 262_144)
        #expect(truncated)
    }

    @Test func aDaemonThatIgnoresTheRangeIsReadOnlyToTheCap() {
        let result = page.run(.text(version: Made.version), [Made.versionPath: .init(status: 200, length: 1_000_000)])
        guard case .text(let text, let truncated) = result.outcome else { Issue.record("not text"); return }
        #expect(text.utf8.count == 262_144)
        #expect(truncated)
        #expect(result.seen.first?.cancelled == true)
        #expect((result.seen.first?.pulled ?? .max) <= 262_144 + 65_536)
        // Exactly the cap, whole: not truncated.
        let exact = page.run(.text(version: Made.version), [Made.versionPath: .init(status: 200, length: 262_144)])
        #expect(exact.outcome == .text(String(repeating: "A", count: 262_144), truncated: false))
    }

    @Test func aNulInTheFirst8KBMeansBinary() {
        var early = [UInt8](repeating: 0x41, count: 100)
        early[50] = 0
        #expect(page.run(.text(version: Made.version), [Made.versionPath: .init(bytes: early)]).outcome == .binary)
        var late = [UInt8](repeating: 0x41, count: 9_000)
        late[8_500] = 0
        guard case .text(let text, _) = page.run(.text(version: Made.version), [Made.versionPath: .init(bytes: late)]).outcome
        else { Issue.record("not text"); return }
        #expect(text.utf8.count == 9_000)
    }

    @Test func anEmptyFileAndOddRanges() {
        #expect(page.run(.text(version: Made.version), [Made.versionPath: .init(status: 416)]).outcome
                == .text("", truncated: false))
        let elsewhere = page.run(.text(version: Made.version),
                                 [Made.versionPath: .init(status: 206, headers: ["Content-Range": "bytes 5-9/10"], bytes: [0x41])])
        #expect(elsewhere.outcome == .unreadable)
        // A 206 without Content-Range: truncated only when it filled the range.
        let short = page.run(.text(version: Made.version), [Made.versionPath: .init(status: 206, bytes: [0x41, 0x42])])
        #expect(short.outcome == .text("AB", truncated: false))
    }

    @Test func aCharacterCutByTheRangeIsDropped() {
        let bytes = Array("ok 日".utf8)
        let result = page.run(.text(version: Made.version),
                              [Made.versionPath: .init(status: 206, headers: ["Content-Range": "bytes 0-4/40"],
                                                       bytes: Array(bytes.prefix(5)))])
        #expect(result.outcome == .text("ok ", truncated: true))
    }

    @Test func swiftChecksTheAnswerFitsTheRead() {
        let text = Data(#"{"outcome":"text","text":"hi","truncated":false}"#.utf8)
        #expect(ArtifactReaderScript.outcome(of: text, for: .text(version: "v")) == .text("hi", truncated: false))
        #expect(ArtifactReaderScript.outcome(of: text, for: .download(version: "v")) == .unreadable)
        let bytes = Data(#"{"outcome":"bytes","base64":"AAEC"}"#.utf8)
        #expect(ArtifactReaderScript.outcome(of: bytes, for: .download(version: "v")) == .bytes(Data([0, 1, 2])))
        #expect(ArtifactReaderScript.outcome(of: bytes, for: .text(version: "v")) == .unreadable)
        #expect(ArtifactReaderScript.outcome(of: Data(#"{"outcome":"bytes","base64":"%%%"}"#.utf8),
                                             for: .download(version: "v")) == .unreadable)
        let nul = Data(#"{"outcome":"text","text":"a\u0000b","truncated":false}"#.utf8)
        #expect(ArtifactReaderScript.outcome(of: nul, for: .text(version: "v")) == .binary)
        let tooLong = try! JSONSerialization.data(withJSONObject: ["outcome": "text", "truncated": false,
                                                                   "text": String(repeating: "a", count: 262_145)])
        #expect(ArtifactReaderScript.outcome(of: tooLong, for: .text(version: "v")) == .unreadable)
        let big = try! JSONSerialization.data(withJSONObject: [
            "outcome": "bytes", "base64": Data(count: ArtifactReaderScript.Cap.thumb + 1).base64EncodedString()])
        #expect(ArtifactReaderScript.outcome(of: big, for: .thumb(version: "v", width: 120)) == .tooBig)
        #expect(ArtifactReaderScript.outcome(of: Data("[]".utf8), for: .text(version: "v")) == .unreadable)
        #expect(ArtifactReaderScript.outcome(of: Data(#"{"outcome":"lost"}"#.utf8), for: .text(version: "v")) == .lost)
    }
}

// MARK: Keep's reads: the paths

struct KeepPathTests {
    @Test func theThreeReadsAreBuiltFromTypedIdsAndNothingElse() {
        #expect(ArtifactRead.versions(artifact: Made.artifact).path == Made.versionsPath)
        #expect(ArtifactRead.facts(version: Made.v3).path == Made.factsPath())
        #expect(ArtifactRead.lineage(version: Made.v3).path == Made.lineagePath())
        // The older reads are as they were, and pass no artifact id.
        #expect(ArtifactRead.download(version: "ver_Made-up_01").path == "/api/artifacts/versions/ver_Made-up_01")
        #expect(ArtifactRead.versions(artifact: "x").arguments["artifactId"] as? String == "x")
        #expect(ArtifactRead.download(version: "x").arguments["artifactId"] is NSNull)
        #expect(ArtifactRead.facts(version: "x").arguments["versionId"] as? String == "x")
    }

    @Test func onlyFullIdsMakeAPath() {
        let hostile = ["", "ver_1", "../etc", Made.v3.uppercased(), String(Made.v3.dropLast()), Made.v3 + "0", "a/b",
                       "a?include_metadata=true", Made.v3 + "\n", "ü" + Made.v3.dropFirst(2), "..",
                       String(repeating: "-", count: 35) + "x"]
        for id in hostile {
            #expect(ArtifactRead.versions(artifact: id).path == nil, "\(id)")
            #expect(ArtifactRead.facts(version: id).path == nil, "\(id)")
            #expect(ArtifactRead.lineage(version: id).path == nil, "\(id)")
        }
        #expect(!PlanCheck.isUUIDLike("ver_1") && PlanCheck.isUUIDLike(Made.v1))
    }

    @Test func theAllowlistTakesKeepsThreeShapesAndRefusesTheNearMisses() {
        #expect(ArtifactRead.isAllowedPath(Made.versionsPath))
        #expect(ArtifactRead.isAllowedPath(Made.factsPath()))
        #expect(ArtifactRead.isAllowedPath(Made.lineagePath()))
        let a = Made.artifact, v = Made.v3
        let refused = [
            // An artifact's id where a version's goes, and the other way round.
            "/api/artifacts/versions/\(v)/versions", "/api/artifacts/\(v)/lineage?slim=1", "/api/artifacts/\(a)/lineage?slim=1",
            "/api/artifacts/versions/\(v)/versions?x=1",
            // Short, long, capital or odd ids.
            "/api/artifacts/ver_1/versions", "/api/artifacts/versions/ver_1?include_metadata=true",
            "/api/artifacts/versions/ver_1/lineage?slim=1", "/api/artifacts/\(a.uppercased())/versions",
            "/api/artifacts/versions/\(v.uppercased())/lineage?slim=1", "/api/artifacts/\(a)0/versions",
            // The query is exactly what it should be.
            "/api/artifacts/versions/\(v)/lineage?slim=0", "/api/artifacts/versions/\(v)/lineage", "/api/artifacts/versions/\(v)/lineage?",
            "/api/artifacts/versions/\(v)/lineage?slim=1&x=1", "/api/artifacts/versions/\(v)/lineage?slim=true",
            "/api/artifacts/versions/\(v)?include_metadata=false", "/api/artifacts/versions/\(v)?include_metadata=true&x=1",
            "/api/artifacts/versions/\(v)?include_metadata=1", "/api/artifacts/versions/\(v)?include_metadata=true&thumbnail=120",
            "/api/artifacts/versions/\(v)/script-bundle", "/api/artifacts/\(v)/script-bundle",
            // Slashes, dots and trailing parts.
            "/api/artifacts/\(a)/versions/", "/api/artifacts//versions", "/api/artifacts/../versions",
            "/api/artifacts/versions/../\(v)/lineage?slim=1", "/api/artifacts/\(a)/versions/..", "/artifacts/\(a)/versions",
            "/api/artifacts/\(a)", "/api/artifacts/\(a)/lineage", "/api/projects/\(a)/versions",
        ]
        for path in refused { #expect(!ArtifactRead.isAllowedPath(path), "\(path)") }
        // The phone's and the shelf's shapes are as they were.
        #expect(ArtifactRead.isAllowedPath("/api/artifacts/versions/ver_1?thumbnail=120"))
        #expect(!ArtifactRead.isAllowedPath("/api/artifacts/versions/ver_1/lineage?slim=1"))
    }

    @Test func thePageBuildsTheSamePathsAsSwiftForKeepsReads() {
        let page = ArtifactPage()
        let cases: [ArtifactRead] = [
            .versions(artifact: Made.artifact), .versions(artifact: Made.v3), .versions(artifact: "x"),
            .versions(artifact: Made.artifact.uppercased()), .facts(version: Made.v3), .facts(version: "ver_1"),
            .facts(version: Made.v3.uppercased()), .lineage(version: Made.v3), .lineage(version: "ver_1"),
            .lineage(version: Made.v3 + "0"),
        ]
        for read in cases {
            page.set("__args", ArtifactPage.arguments(read))
            let built = page.evaluate("var a = JSON.parse(__args); JSON.stringify(benchArtifactPath(a.op, a.frameId, a.versionId, a.width, a.artifactId))")
            #expect(built == (read.path.map { "\"\($0)\"" } ?? "null"), "\(read)")
        }
        // An id in the wrong slot, a missing one, an unknown op: no path.
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('versions', null, '\(Made.artifact)', null, null))") == "null")
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('versions', null, null, null, undefined))") == "null")
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('facts', null, null, null, '\(Made.v3)'))") == "null")
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('script-bundle', null, '\(Made.v3)', null, '\(Made.artifact)'))") == "null")
        // The older ops ignore an artifact id.
        #expect(page.evaluate("JSON.stringify(benchArtifactPath('download', null, 'v1', null, '\(Made.artifact)'))") == "\"/api/artifacts/versions/v1\"")
    }

    @Test func aReadThatMakesNoPathIsRefusedInThePageBeforeAnyFetch() {
        for read in [ArtifactRead.versions(artifact: "../x"), .facts(version: "ver_1"), .lineage(version: Made.v3.uppercased())] {
            let result = ArtifactPage().run(read, [:])
            #expect(result.raw == #"{"outcome":"refused"}"#, "\(read)")
            #expect(result.seen.isEmpty)
            #expect(result.outcome == .unreadable)
        }
    }
}

// MARK: Keep's reads: the projections

struct KeepProjectionTests {
    private let page = ArtifactPage()

    private func project(_ call: String, _ raw: String) -> String? {
        page.set("__raw", raw)
        return page.evaluate("JSON.stringify(\(call))")
    }

    private func parsed(_ json: String?) -> Any? {
        json.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: [.fragmentsAllowed]) }
    }

    private func versions(_ raw: String, cap: Int = 500) -> (json: String?, versions: [ArtifactVersion]?) {
        let json = project("benchProjectVersions(JSON.parse(__raw), \(cap))", raw)
        guard let json, json != "null" else { return (json, nil) }
        return (json, ArtifactReaderScript.versions(parsed(json)))
    }

    private func facts(_ raw: String, asked: String = Made.v3) -> (json: String?, facts: ArtifactFacts?) {
        let json = project("benchProjectFacts(JSON.parse(__raw), '\(asked)')", raw)
        guard let json, json != "null" else { return (json, nil) }
        return (json, ArtifactReaderScript.facts(parsed(json), asked: asked))
    }

    private func lineage(_ raw: String, asked: String = Made.v3) -> (json: String?, lineage: ArtifactLineage?) {
        let json = project("benchProjectLineage(JSON.parse(__raw), '\(asked)')", raw)
        guard let json, json != "null" else { return (json, nil) }
        return (json, ArtifactReaderScript.lineage(parsed(json), asked: asked))
    }

    /// Nothing the fixtures mark as a secret, and no path.
    private func leaks(_ json: String?) -> Bool {
        guard let json else { return true }
        return json.contains("SECRET") || json.contains("/opt") || json.contains("made-up/")
    }

    private func keys(_ json: String?, at path: [String] = []) -> Set<String>? {
        var value = parsed(json)
        if let array = value as? [Any] { value = array.first }
        for step in path { value = (value as? [String: Any])?[step]; if let array = value as? [Any] { value = array.first } }
        return (value as? [String: Any]).map { Set($0.keys) }
    }

    // MARK: Versions

    @Test func eachVersionKeepsSevenFieldsAndNothingElse() throws {
        let rows = Made.versions([
            Made.versionRow(Made.v1, n: 1),
            Made.versionRow(Made.v2, n: 2, frame: nil, type: "Image/PNG; x=y", size: 4096, parent: Made.v1),
            Made.versionRow(Made.v3, n: 3, parent: Made.v2),
        ])
        let (json, list) = versions(rows)
        #expect(!leaks(json))
        #expect(!(json ?? "").contains("agent") && !(json ?? "").contains("language"))
        let all = try #require(list)
        #expect(all.map(\.v) == [Made.v1, Made.v2, Made.v3])
        #expect(all.map(\.n) == [1, 2, 3])
        #expect(all[0] == ArtifactVersion(v: Made.v1, n: 1, frame: Made.frame, mime: "image/png", size: 2048,
                                         at: Date(timeIntervalSince1970: 1_791_833_400), parent: nil))
        #expect(all[1].frame == nil && all[1].parent == Made.v1 && all[1].size == 4096 && all[1].mime == "image/png")
        #expect(keys(json) == ["v", "n", "frame", "mime", "size", "at", "parent"])
    }

    @Test func fieldsTheDaemonDoesntGiveCleanlyAreNull() throws {
        let row = Made.versionRow(Made.v1, n: 1, frame: "not-an-id", type: "nonsense", created: "yesterday", parent: "x")
        let all = try #require(versions(Made.versions([row])).versions)
        #expect(all[0].frame == nil && all[0].mime == nil && all[0].at == nil && all[0].parent == nil)
        let epoch = Made.versionRow(Made.v1, n: 1, created: 1_791_833_400_000)
        #expect(try #require(versions(Made.versions([epoch])).versions)[0].at == Date(timeIntervalSince1970: 1_791_833_400))
    }

    @Test func aVersionListThatIsntTheShapeReadsNothing() {
        let good = Made.versionRow(Made.v1, n: 1)
        for body in [Made.json(["versions": [good]]), "\"[]\"", "null", "5", "{}"] {
            #expect(versions(body).json == "null", "\(body.prefix(40))")
        }
        let bad: [[String: Any]] = [
            Made.versionRow("ver_1", n: 2), Made.versionRow(Made.v2.uppercased(), n: 2), Made.versionRow(Made.v2, n: -1),
            Made.versionRow(Made.v2, n: 2, size: -5),
            Made.versionRow(Made.v2, n: 2).merging(["version_number": "2"]) { $1 },
            Made.versionRow(Made.v2, n: 2).merging(["version_number": 2.5]) { $1 },
            Made.versionRow(Made.v2, n: 2).merging(["size_bytes": NSNull()]) { $1 },
            Made.versionRow(Made.v2, n: 2).merging(["content_type": 5]) { $1 },
            Made.versionRow(Made.v2, n: 2).merging(["version_id": 7]) { $1 },
        ]
        #expect(versions("[]").versions == [])
        for row in bad {
            #expect(versions(Made.versions([good, row])).json == "null", "\(Made.json(row).prefix(80))")
        }
        #expect(versions("[5]").json == "null")
    }

    @Test func theNewestFiveHundredAreKept() throws {
        let rows = Made.versions((0..<600).map { Made.versionRow(Made.id($0), n: $0 + 1) })
        let all = try #require(versions(rows).versions)
        #expect(all.count == 500)
        #expect(all.first?.n == 101 && all.last?.n == 600)
        #expect(all.first?.v == Made.id(100))
    }

    @Test func swiftChecksEveryVersionFieldAgain() {
        func check(_ row: [String: Any]) -> [ArtifactVersion]? {
            ArtifactReaderScript.versions(parsed(Made.json([row])))
        }
        let good: [String: Any] = ["v": Made.v1, "n": 1, "frame": NSNull(), "mime": "image/png", "size": 3, "at": NSNull(), "parent": NSNull()]
        #expect(check(good)?.count == 1)
        #expect(ArtifactReaderScript.versions(parsed(Made.json([good, good])))?.count == 1)
        let overrides: [(String, Any)] = [
            ("v", "ver_1"), ("n", 1.5), ("n", -1), ("n", true), ("frame", "x"), ("mime", "Image/PNG"), ("size", -3),
            ("at", "today"), ("parent", "../x"),
        ]
        for (key, value) in overrides {
            #expect(check(good.merging([key: value]) { $1 }) == nil, "\(key) \(value)")
        }
        let many = (0...500).map { good.merging(["v": Made.id($0)]) { $1 } }
        #expect(ArtifactReaderScript.versions(parsed(Made.json(many))) == nil)
    }

    // MARK: Facts

    @Test func factsKeepTwelveFieldsAndNeverAPath() throws {
        let raw = Made.facts {
            $0["reproduction_code"] = "x = 1\n"
            $0["environment"] = ["environment_name": "base", "python_version": "3.12.4",
                                 "packages": [["name": "numpy", "version": "1.26.4"], ["name": "pandas", "version": "2.2.2"]],
                                 "op_log": [["operation": "SECRET-OP", "packages": ["SECRET-PKG"]]]] as [String: Any]
        }
        let (json, read) = facts(raw)
        #expect(!leaks(json))
        #expect(try #require(read) == ArtifactFacts(
            v: Made.v3, a: Made.artifact, n: 3, name: "z_prime.png", mime: "image/png", size: 86016,
            at: Date(timeIntervalSince1970: 1_791_833_400), sha: Made.digest, isUpload: false, code: "x = 1\n", codeCut: false,
            environment: ArtifactEnvironment(name: "base", python: "3.12.4",
                                             packages: [(name: "numpy", version: "1.26.4"), (name: "pandas", version: "2.2.2")])))
        #expect(keys(json) == ["v", "a", "n", "name", "mime", "size", "at", "sha", "upload", "code", "codeCut", "env"])
        #expect(keys(json, at: ["env"]) == ["name", "python", "packages"])
        #expect(keys(json, at: ["env", "packages"]) == ["name", "version"])
    }

    @Test func aVersionWithNoCodeOrEnvironmentHasNone() throws {
        let known = try #require(facts(Made.facts()).facts)
        #expect(known.code == nil && !known.codeCut && known.environment == nil && !known.isUpload)
    }

    @Test func theChecksumIsSixtyFourHexDigitsOrNil() throws {
        func sha(_ value: Any) throws -> String? {
            try #require(facts(Made.facts { $0["checksum"] = value }).facts).sha
        }
        #expect(try sha(NSNull()) == nil)
        #expect(try sha("") == nil)
        #expect(try sha("abc") == nil)
        #expect(try sha(String(repeating: "g", count: 64)) == nil)
        #expect(try sha(String(repeating: "ab", count: 33)) == nil)
        #expect(try sha(12345) == nil)
        #expect(try sha(String(repeating: "AB12", count: 16)) == String(repeating: "ab12", count: 16))
        #expect(try sha(Made.digest) == Made.digest)
    }

    @Test func anAnswerForAnotherVersionIsRefusedInThePageAndInSwift() throws {
        // An artifact's id in a version's place serves the artifact's latest version.
        #expect(facts(Made.facts(version: Made.v2), asked: Made.v3).json == "null")
        #expect(facts(Made.facts(version: Made.artifact), asked: Made.v3).json == "null")
        // Swift refuses it too, were the page to let one through.
        let ok = try #require(facts(Made.facts()).json)
        let answer = Data(#"{"outcome":"facts","facts":\#(ok)}"#.utf8)
        #expect(ArtifactReaderScript.outcome(of: answer, for: .facts(version: Made.v1)) == .unreadable)
        #expect(ArtifactReaderScript.outcome(of: answer, for: .facts(version: Made.v3)) != .unreadable)
        // And an answer of another kind of read.
        #expect(ArtifactReaderScript.outcome(of: answer, for: .lineage(version: Made.v3)) == .unreadable)
        #expect(ArtifactReaderScript.outcome(of: answer, for: .versions(artifact: Made.artifact)) == .unreadable)
    }

    @Test func factsThatArentTheShapeReadNothing() {
        for raw in ["[]", "null", "\"x\"", "5", Made.facts { $0["is_user_upload"] = "no" }, Made.facts { $0["is_user_upload"] = NSNull() },
                    Made.facts { $0.removeValue(forKey: "is_user_upload") }, Made.facts { $0["version_id"] = 5 }] {
            #expect(facts(raw).json == "null", "\(raw.prefix(60))")
        }
        #expect(facts(Made.facts(version: "ver_1"), asked: "ver_1").json == "null")
    }

    @Test func theNameIsTheLastSegmentWithoutControls() throws {
        func name(_ filename: String) throws -> String? {
            try #require(facts(Made.facts { $0["filename"] = filename }).facts).name
        }
        #expect(try name("results/run 1/Z′ by plate.png") == "Z′ by plate.png")
        #expect(try name("C:\\data\\table.csv") == "table.csv")
        #expect(try name("evil\u{0}\u{202E}gnp.txt\r\n") == "evilgnp.txt")
        #expect(try name("folder/") == nil)
        #expect(try name("") == nil)
        #expect(try name(String(repeating: "n", count: 400) + ".txt")?.unicodeScalars.count == 255)
    }

    @Test func codeIsCutAtTwoHundredFiftySixKilobytesOfUTF8WithoutSplittingACharacter() throws {
        func code(_ text: String) throws -> (code: String?, cut: Bool) {
            let known = try #require(facts(Made.facts { $0["reproduction_code"] = text }).facts)
            return (known.code, known.codeCut)
        }
        let limit = 256 * 1024
        let exact = String(repeating: "a", count: limit)
        let whole = try code(exact)
        #expect(whole.code == exact && !whole.cut)
        let over = try code(String(repeating: "a", count: limit + 1))
        #expect(over.code?.utf8.count == limit && over.cut)
        // Two-byte characters meet the limit exactly; three- and four-byte ones stop short of it.
        let two = try code(String(repeating: "é", count: 200_000))
        #expect(two.code?.utf8.count == limit && two.code?.unicodeScalars.count == limit / 2 && two.cut)
        let three = try code(String(repeating: "日", count: 100_000))
        #expect(three.code?.utf8.count == 3 * (limit / 3) && three.cut)
        let four = try code("a" + String(repeating: "🧪", count: 70_000))
        #expect(four.code?.utf8.count == 1 + 4 * ((limit - 1) / 4) && four.cut)
        #expect(four.code?.unicodeScalars.last == "🧪")
        #expect(try code("").code == nil)
        let short = try code("short\n")
        #expect(short.code == "short\n" && !short.cut)
    }

    @Test func anEnvironmentKeepsNamePythonAndAtMostTwoThousandPackages() throws {
        var packages: [Any] = (0..<2_500).map { ["name": "pkg\($0)", "version": "1.\($0)", "channel": "SECRET-CHANNEL"] as [String: Any] }
        packages += [5, ["version": "9"], ["name": 3]] as [Any]
        let raw = Made.facts { $0["environment"] = ["environment_name": "base", "python_version": "3.12", "packages": packages] as [String: Any] }
        let (json, read) = facts(raw)
        #expect(!leaks(json))
        let env = try #require(read?.environment)
        #expect(env.name == "base" && env.python == "3.12")
        #expect(env.packages.count == 2_000)
        #expect(env.packages.first?.name == "pkg0" && env.packages.first?.version == "1.0")
        #expect(env.packages.last?.name == "pkg1999")
        // An environment that isn't an object is none; one with nothing in it has nothing.
        #expect(try #require(facts(Made.facts { $0["environment"] = "x" }).facts).environment == nil)
        let bare = try #require(facts(Made.facts { $0["environment"] = [String: Any]() }).facts).environment
        #expect(bare == ArtifactEnvironment(name: nil, python: nil, packages: []))
    }

    @Test func swiftChecksEveryFactsFieldAgain() {
        let base: [String: Any] = ["v": Made.v3, "a": NSNull(), "n": NSNull(), "name": NSNull(), "mime": NSNull(), "size": NSNull(),
                                   "at": NSNull(), "sha": NSNull(), "upload": false, "code": NSNull(), "codeCut": false, "env": NSNull()]
        func check(_ key: String? = nil, _ value: Any = NSNull(), asked: String = Made.v3) -> ArtifactFacts? {
            var row = base
            if let key { row[key] = value }
            return ArtifactReaderScript.facts(parsed(Made.json(row)), asked: asked)
        }
        #expect(check() != nil)
        #expect(check(asked: Made.v2) == nil)
        let environment = { (packages: Any) -> [String: Any] in ["name": NSNull(), "python": NSNull(), "packages": packages] }
        let overrides: [(String, Any)] = [
            ("sha", String(repeating: "A", count: 64)), ("sha", "abc"), ("sha", 5), ("n", -1), ("n", 1.5), ("size", -1), ("size", "3"),
            ("at", "today"), ("a", "art_1"), ("a", 5), ("name", "a\u{7}b"), ("mime", "Text/Plain"), ("upload", 1), ("upload", NSNull()),
            ("codeCut", true), ("code", ""), ("code", 5), ("code", String(repeating: "a", count: 256 * 1024 + 1)),
            ("env", environment([["name": "", "version": "1"]])), ("env", environment([["name": "a", "version": 1]])),
            ("env", ["name": NSNull(), "python": NSNull()] as [String: Any]), ("env", 5),
            ("env", environment((0...2_000).map { ["name": "p\($0)", "version": "1"] })),
        ]
        for (key, value) in overrides {
            #expect(check(key, value) == nil, "\(key) \(String(describing: value).prefix(40))")
        }
        #expect(check("env", environment([["name": "a", "version": ""]]))?.environment?.packages.count == 1)
        #expect(check("codeCut", true) == nil && check("code", "x") != nil)
    }

    // MARK: Lineage

    @Test func aLineageKeepsElevenFieldsAndNeverAPathOrAProvenanceMessage() throws {
        let (json, read) = lineage(Made.lineage())
        #expect(!leaks(json))
        let known = try #require(read)
        #expect(known.v == Made.v3)
        #expect(known.code == "import pandas as pd\nplot({{artifact:\(Made.v2)}})\n" && !known.codeCut)
        #expect(known.description == "Plots Z prime by plate." && known.language == "python")
        #expect(!known.pending && known.unavailableModel == nil && known.unavailableReason == nil)
        #expect(known.hasCells && known.hasEnvironment && known.mappingStatus == "complete")
        #expect(known.inputs == [
            LineageInput(v: Made.v2, a: Made.other, name: "plate_reader.csv", file: nil, how: "runtime", inferred: false),
            LineageInput(v: nil, a: nil, name: nil, file: "notes.xlsx", how: "ast_only", inferred: true),
        ])
        #expect(known.inputs.map(\.fetchable) == [true, false])
        #expect(keys(json) == ["v", "code", "codeCut", "desc", "lang", "pending", "unavailable", "cells", "env", "mapping", "inputs"])
        #expect(keys(json, at: ["inputs"]) == ["v", "a", "name", "file", "how", "inferred", "fetchable"])
    }

    @Test func aLineageThatCarriesTheConversationOrTheSnapshotOrTheCellsIsRefused() {
        #expect(lineage(Made.lineage()).lineage != nil)
        let carrying: [(String, Any)] = [
            ("messages", [["role": "user", "content": "SECRET-MESSAGE"]]), ("messages", [Any]()),
            ("environment_snapshot", ["packages": [Any]()]), ("environment_snapshot", [String: Any]()),
            ("interactions", [Any]()), ("interactions", [["source": "SECRET-CELL"]]), ("messages", "SECRET"),
        ]
        for (key, value) in carrying {
            let result = lineage(Made.lineage { $0[key] = value })
            #expect(result.json == "null", "\(key)")
        }
        // Absent is as null: an older daemon's slim answer.
        let bare = Made.lineage { $0.removeValue(forKey: "messages"); $0.removeValue(forKey: "environment_snapshot"); $0.removeValue(forKey: "interactions") }
        #expect(!bare.contains("\"messages\"") && lineage(bare).lineage != nil)
    }

    @Test func aLineageForAnotherVersionIsRefused() throws {
        #expect(lineage(Made.lineage(version: Made.v2), asked: Made.v3).json == "null")
        let ok = try #require(lineage(Made.lineage()).json)
        let answer = Data(#"{"outcome":"lineage","lineage":\#(ok)}"#.utf8)
        #expect(ArtifactReaderScript.outcome(of: answer, for: .lineage(version: Made.v1)) == .unreadable)
        #expect(ArtifactReaderScript.outcome(of: answer, for: .lineage(version: Made.v3)) != .unreadable)
    }

    @Test func pendingAndUnavailableAndUploadAndNoMappingAreKept() throws {
        let pending = try #require(lineage(Made.lineage { $0["pending"] = true; $0["code"] = NSNull() }).lineage)
        #expect(pending.pending && pending.code == nil)
        let off = try #require(lineage(Made.lineage {
            $0["code_unavailable"] = ["model": "a-made-up-model", "reason": "not_enabled_for_org"]
        }).lineage)
        #expect(off.unavailableModel == "a-made-up-model" && off.unavailableReason == "not_enabled_for_org")
        let none = try #require(lineage(Made.lineage { $0["dependency_mappings"] = NSNull() }).lineage)
        #expect(none.inputs.isEmpty && none.mappingStatus == nil)
        let waiting = try #require(lineage(Made.lineage {
            $0["dependency_mappings"] = ["inputs": [Any](), "mapping_status": "pending"] as [String: Any]
        }).lineage)
        #expect(waiting.inputs.isEmpty && waiting.mappingStatus == "pending")
        // A user upload answers with no code and no description.
        let upload = try #require(lineage(Made.lineage { $0["code"] = NSNull(); $0["code_description"] = NSNull() }).lineage)
        #expect(upload.code == nil && upload.description == nil)
    }

    @Test func inputsAreCappedAtTwoHundredAndKeepOnlyTheLastSegmentOfAWorkspacePath() throws {
        let many: [Any] = (0..<250).map {
            ["filename": "f\($0).csv", "artifact_id": Made.id($0), "version_id": Made.id($0 + 1_000), "consensus": "both"] as [String: Any]
        }
        let capped = try #require(lineage(Made.lineage {
            $0["dependency_mappings"] = ["inputs": many, "mapping_status": "complete"] as [String: Any]
        }).lineage)
        #expect(capped.inputs.count == 200 && capped.inputs.last?.name == "f199.csv" && capped.inputs.allSatisfy(\.fetchable))
        let odd: [Any] = [
            ["workspace_path": "/opt/made-up/SECRET-WS/a/b/data.tsv"], ["workspace_path": "C:\\SECRET\\x.txt", "version_id": "../x"],
            ["consensus": "weird consensus"], 5, ["filename": "k.csv", "consensus": "ast_only", "version_id": Made.v1],
        ]
        let read = lineage(Made.lineage { $0["dependency_mappings"] = ["inputs": odd] as [String: Any] })
        #expect(!leaks(read.json))
        let inputs = try #require(read.lineage).inputs
        // The odd ones are left out or cleaned; the paths never come through.
        #expect(inputs.map(\.file) == ["data.tsv", "x.txt", nil])
        #expect(inputs.map(\.v) == [nil, nil, Made.v1])
        #expect(inputs.last?.inferred == true && inputs.last?.fetchable == false && inputs.first?.fetchable == false)
    }

    @Test func aLongDescriptionIsCutAtTwoThousandCharacters() throws {
        let known = try #require(lineage(Made.lineage { $0["code_description"] = String(repeating: "é", count: 3_000) }).lineage)
        #expect(known.description?.unicodeScalars.count == 2_000 && known.description?.hasSuffix("…") == true)
    }

    @Test func swiftChecksEveryLineageFieldAgain() {
        let base: [String: Any] = ["v": Made.v3, "code": NSNull(), "codeCut": false, "desc": NSNull(), "lang": NSNull(), "pending": false,
                                   "unavailable": NSNull(), "cells": false, "env": false, "mapping": NSNull(), "inputs": [Any]()]
        func check(_ key: String? = nil, _ value: Any = NSNull(), asked: String = Made.v3) -> ArtifactLineage? {
            var row = base
            if let key { row[key] = value }
            return ArtifactReaderScript.lineage(parsed(Made.json(row)), asked: asked)
        }
        let input: [String: Any] = ["v": NSNull(), "a": NSNull(), "name": "x.csv", "file": NSNull(), "how": "runtime", "inferred": false, "fetchable": false]
        #expect(check("inputs", [input])?.inputs.count == 1)
        #expect(check() != nil && check(asked: Made.v1) == nil)
        let bad: [[String: Any]] = [
            input.merging(["name": NSNull()]) { $1 },
            input.merging(["v": "a/b", "name": NSNull()]) { $1 },
            input.merging(["how": "ast_only"]) { $1 },
            input.merging(["inferred": true]) { $1 },
            input.merging(["v": "v1", "a": "a1"]) { $1 },
            input.merging(["v": "v1", "fetchable": true]) { $1 },
            input.merging(["name": "x\u{7}"]) { $1 },
            input.merging(["how": "two words"]) { $1 },
        ]
        for row in bad { #expect(check("inputs", [row]) == nil, "\(row)") }
        #expect(check("inputs", Array(repeating: input, count: 201)) == nil)
        #expect(check("inputs", ["x": 1]) == nil)
        for (key, value) in [("pending", 1), ("cells", "yes"), ("lang", "two words"), ("mapping", "a b"), ("desc", "x\u{7}")] as [(String, Any)] {
            #expect(check(key, value) == nil, "\(key)")
        }
        #expect(check("unavailable", ["model": "m", "reason": "not_enabled_for_org"])?.unavailableReason == "not_enabled_for_org")
        #expect(check("unavailable", ["model": 5, "reason": NSNull()]) == nil)
        #expect(check("codeCut", true) == nil && check("code", "x") != nil)
    }
}

// MARK: Keep's reads: in the page

struct KeepReadTests {
    private let page = ArtifactPage()

    private func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> ArtifactPage.Answer {
        .init(status: status, headers: headers, bytes: Array(text.utf8))
    }

    @Test func eachReadIsOneNoStoreJSONGetAndItsAnswerIsProjected() throws {
        let rows = Made.versions([Made.versionRow(Made.v1, n: 1), Made.versionRow(Made.v2, n: 2, parent: Made.v1)])
        let versions = page.run(.versions(artifact: Made.artifact), [Made.versionsPath: json(rows)])
        #expect(versions.seen.map(\.path) == [Made.versionsPath])
        #expect(versions.seen.first?.cache == "no-store" && versions.seen.first?.credentials == "include")
        #expect(versions.seen.first?.accept == "application/json" && versions.seen.first?.range == nil)
        guard case .versions(let list) = versions.outcome else { Issue.record("not versions"); return }
        #expect(list.map(\.v) == [Made.v1, Made.v2])
        #expect(!(versions.raw ?? "").contains("SECRET") && !(versions.raw ?? "").contains("/opt"))

        let facts = page.run(.facts(version: Made.v3), [Made.factsPath(): json(Made.facts())])
        #expect(facts.seen.map(\.path) == [Made.factsPath()])
        #expect(facts.seen.first?.accept == "application/json" && facts.seen.first?.cache == "no-store")
        guard case .facts(let known) = facts.outcome else { Issue.record("not facts"); return }
        #expect(known.v == Made.v3 && known.sha == Made.digest)
        #expect(!(facts.raw ?? "").contains("SECRET") && !(facts.raw ?? "").contains("/opt"))

        let lineage = page.run(.lineage(version: Made.v3), [Made.lineagePath(): json(Made.lineage())])
        #expect(lineage.seen.map(\.path) == [Made.lineagePath()])
        guard case .lineage(let found) = lineage.outcome else { Issue.record("not lineage"); return }
        #expect(found.inputs.count == 2)
        #expect(!(lineage.raw ?? "").contains("SECRET") && !(lineage.raw ?? "").contains("/opt"))
    }

    @Test func aMissingVersionIs404AndASignedOutPageIs401() {
        let reads: [(ArtifactRead, String)] = [
            (.versions(artifact: Made.artifact), Made.versionsPath), (.facts(version: Made.v3), Made.factsPath()),
            (.lineage(version: Made.v3), Made.lineagePath()),
        ]
        for (read, path) in reads {
            for status in [404, 410] {
                let result = page.run(read, [path: .init(status: status, length: 4)])
                #expect(result.outcome == .missing, "\(status) \(read)")
                #expect(result.seen.first?.pulled == 0 && result.seen.first?.cancelled == true, "its body isn't read")
            }
            #expect(page.run(read, [path: .init(status: 401)]).outcome == .lost)
            for status in [204, 206, 302, 403, 416, 500] {
                #expect(page.run(read, [path: json("[]", status: status)]).outcome == .unreadable, "\(status) \(read)")
            }
            #expect(page.run(read, [:]).outcome == .unreadable)
        }
    }

    @Test func aBodyThatIsntTheShapeIsUnreadable() {
        for text in ["<html>", "", "null", "5", "\"[]\"", "{\"versions\": []}", "[5]", "{"] {
            #expect(page.run(.versions(artifact: Made.artifact), [Made.versionsPath: json(text)]).outcome == .unreadable, "\(text)")
        }
        for text in ["<html>", "[]", "null", "{}", #"{"version_id": 5}"#] {
            #expect(page.run(.facts(version: Made.v3), [Made.factsPath(): json(text)]).outcome == .unreadable, "\(text)")
            #expect(page.run(.lineage(version: Made.v3), [Made.lineagePath(): json(text)]).outcome == .unreadable, "\(text)")
        }
    }

    @Test func anAnswerForAnotherVersionIsUnreadable() {
        // What the daemon does with an artifact's id in a version's place.
        let result = page.run(.facts(version: Made.v3), [Made.factsPath(): json(Made.facts(version: Made.v2))])
        #expect(result.outcome == .unreadable)
        #expect(result.raw == #"{"outcome":"unreadable"}"#)
        let lineage = page.run(.lineage(version: Made.v3), [Made.lineagePath(): json(Made.lineage(version: Made.v2))])
        #expect(lineage.outcome == .unreadable)
    }

    @Test func aLineageThatCarriesTheConversationIsUnreadableAndNothingOfItLeaves() {
        let carrying = Made.lineage { $0["messages"] = [["role": "user", "content": "SECRET-MESSAGE"]] }
        let result = page.run(.lineage(version: Made.v3), [Made.lineagePath(): json(carrying)])
        #expect(result.outcome == .unreadable)
        #expect(!(result.raw ?? "").contains("SECRET"))
    }

    @Test func eachBodyIsReadOnlyToItsCap() {
        let caps: [(ArtifactRead, String, Int)] = [
            (.versions(artifact: Made.artifact), Made.versionsPath, 1024 * 1024),
            (.facts(version: Made.v3), Made.factsPath(), 2 * 1024 * 1024),
            (.lineage(version: Made.v3), Made.lineagePath(), 2 * 1024 * 1024),
        ]
        for (read, path, cap) in caps {
            // By its own length: not read at all.
            let declared = page.run(read, [path: .init(headers: ["Content-Length": "\(cap + 1)"], length: cap + 1)])
            #expect(declared.outcome == .tooBig, "\(read)")
            #expect(declared.seen.first?.pulled == 0 && declared.seen.first?.cancelled == true)
            // Without a length: read up to the cap, then given up.
            let streamed = page.run(read, [path: .init(length: cap + 1)])
            #expect(streamed.outcome == .tooBig, "\(read)")
            #expect(streamed.seen.first?.cancelled == true)
            #expect((streamed.seen.first?.pulled ?? .max) <= cap + 65_536)
        }
    }

    @Test func aBodyUpToTheCapIsReadAndItsCodeCutNotRefused() throws {
        // More rows than any real list: 2,000, the newest 500 kept, under 1 MB.
        let rows = Made.versions((0..<2_000).map { Made.versionRow(Made.id($0), n: $0 + 1) })
        #expect(rows.utf8.count > 500_000 && rows.utf8.count <= 1024 * 1024)
        guard case .versions(let list) = page.run(.versions(artifact: Made.artifact), [Made.versionsPath: json(rows)]).outcome
        else { Issue.record("not versions"); return }
        #expect(list.count == 500 && list.last?.n == 2_000)
        // Facts with code over 256 KB in a body under 2 MB.
        let big = Made.facts { $0["reproduction_code"] = String(repeating: "x = 1\n", count: 100_000) }
        guard case .facts(let facts) = page.run(.facts(version: Made.v3), [Made.factsPath(): json(big)]).outcome
        else { Issue.record("not facts"); return }
        #expect(facts.codeCut && facts.code?.utf8.count == 256 * 1024)
    }

    @Test func theOlderReadsAreAsTheyWere() {
        let list = page.run(.list(frame: Made.session), [Made.listPath: .init(text: "[\(Made.row("a.txt"))]")])
        guard case .list(let entries) = list.outcome else { Issue.record("not a list"); return }
        #expect(entries.count == 1 && list.seen.count == 1)
        let download = page.run(.download(version: Made.version), [Made.versionPath: .init(bytes: [1, 2, 3])])
        #expect(download.outcome == .bytes(Data([1, 2, 3])))
        #expect(download.seen.first?.accept == "*/*")
    }

    @Test func swiftTakesAnAnswerOnlyForTheReadItAskedFor() {
        let versions = Data(#"{"outcome":"versions","versions":[]}"#.utf8)
        #expect(ArtifactReaderScript.outcome(of: versions, for: .versions(artifact: Made.artifact)) == .versions([]))
        for read in [ArtifactRead.facts(version: Made.v3), .lineage(version: Made.v3), .download(version: "v"), .list(frame: Made.session)] {
            #expect(ArtifactReaderScript.outcome(of: versions, for: read) == .unreadable, "\(read)")
        }
        let tooBig = Data(#"{"outcome":"tooBig"}"#.utf8)
        for read in [ArtifactRead.versions(artifact: Made.artifact), .facts(version: Made.v3), .lineage(version: Made.v3)] {
            #expect(ArtifactReaderScript.outcome(of: tooBig, for: read) == .tooBig)
        }
        #expect(ArtifactReaderScript.outcome(of: tooBig, for: .list(frame: Made.session)) == .unreadable)
        #expect(ArtifactReaderScript.outcome(of: Data(#"{"outcome":"missing"}"#.utf8), for: .facts(version: Made.v3)) == .missing)
        #expect(ArtifactReaderScript.outcome(of: Data(#"{"outcome":"lost"}"#.utf8), for: .lineage(version: Made.v3)) == .lost)
    }
}

// MARK: Tables

struct ArtifactTableTests {
    private func parse(_ text: String, _ delimiter: Unicode.Scalar = ",", cutShort: Bool = false) -> ArtifactTable {
        ArtifactTable.parse(text, delimiter: delimiter, cutShort: cutShort)
    }

    @Test func quotesCommasAndDoubledQuotes() {
        let table = parse("name,note\n\"Smith, J\",\"says \"\"hi\"\"\"\nplain,\"\"\n")
        #expect(table.columns == ["name", "note"])
        #expect(table.rows == [["Smith, J", "says \"hi\""], ["plain", ""]])
        #expect(!table.truncated)
    }

    @Test func lineBreaksInsideQuotesStayInTheCell() {
        let table = parse("a,b\r\n\"one\r\ntwo\",x\r\n\"three\nfour\",y\r\n")
        #expect(table.rows == [["one\r\ntwo", "x"], ["three\nfour", "y"]])
    }

    @Test func aBOMAndEveryLineEnd() {
        #expect(parse("\u{FEFF}a,b\r\n1,2\r\n").columns == ["a", "b"])
        #expect(parse("a,b\r1,2\r3,4").rows == [["1", "2"], ["3", "4"]])
        #expect(parse("a,b\n1,2").rows == [["1", "2"]])
    }

    @Test func raggedRowsArePaddedToTheWidest() {
        let table = parse("a,b\n1\n1,2,3,4\n\n\n5,6\n")
        #expect(table.columns == ["a", "b", "", ""])
        #expect(table.rows == [["1", "", "", ""], ["1", "2", "3", "4"], ["5", "6", "", ""]])
    }

    @Test func blankLinesAndATrailingNewlineMakeNoRows() {
        #expect(parse("a\n\n1\n\n").rows == [["1"]])
        #expect(parse("") == ArtifactTable(columns: [], rows: [], truncated: false))
        #expect(parse("\n\n\r\n") == ArtifactTable(columns: [], rows: [], truncated: false))
        #expect(parse("only,header\n") == ArtifactTable(columns: ["only", "header"], rows: [], truncated: false))
        // A line of empty fields is a row.
        #expect(parse("a,b\n,\n").rows == [["", ""]])
    }

    @Test func leniencyWhereFilesArent() {
        // A quote mid-field is kept; text after a closing quote is kept.
        #expect(parse("x\nab\"c\n").rows == [["ab\"c"]])
        #expect(parse("x\n\"ab\"cd\n").rows == [["abcd"]])
        // An unclosed quote runs to the end of a whole file.
        #expect(parse("x\n\"never closed\nstill,going").rows == [["never closed\nstill,going"]])
    }

    @Test func aFileCutShortLosesItsIncompleteLastRecord() {
        let cut = parse("a,b\n1,2\n3,", cutShort: true)
        #expect(cut.rows == [["1", "2"]])
        #expect(cut.truncated)
        let inQuotes = parse("a,b\n1,2\n\"3\nmore", cutShort: true)
        #expect(inQuotes.rows == [["1", "2"]])
        let whole = parse("a,b\n1,2\n", cutShort: true)
        #expect(whole.rows == [["1", "2"]])
        #expect(whole.truncated)
    }

    @Test func tenThousandColumnsKeepThirty() {
        let line = (0..<10_000).map { "c\($0)" }.joined(separator: ",")
        let table = parse(line + "\n" + line + "\n")
        #expect(table.columns.count == 30)
        #expect(table.columns.last == "c29")
        #expect(table.rows.count == 1)
        #expect(table.rows[0].count == 30)
        #expect(table.truncated)
    }

    @Test func twoHundredRowsAndNoMore() {
        let text = "n\n" + (1...250).map(String.init).joined(separator: "\n") + "\n"
        let table = parse(text)
        #expect(table.rows.count == 200)
        #expect(table.rows.last == ["200"])
        #expect(table.truncated)
        let exact = parse("n\n" + (1...200).map(String.init).joined(separator: "\n") + "\n")
        #expect(exact.rows.count == 200)
        #expect(!exact.truncated)
    }

    @Test func longCellsAreCutAt200Characters() {
        let long = String(repeating: "é", count: 5_000)
        let table = parse("a\n\"\(long)\"\n")
        #expect(table.rows[0][0].count == 200)
        #expect(table.rows[0][0].hasSuffix("…"))
        #expect(table.truncated)
        let exact = parse("a\n" + String(repeating: "x", count: 200) + "\n")
        #expect(exact.rows[0][0].count == 200)
        #expect(!exact.truncated)
    }

    @Test func tabsForTSV() {
        #expect(ArtifactTable.delimiter(name: "counts.TSV", mime: nil) == "\t")
        #expect(ArtifactTable.delimiter(name: "counts", mime: "text/tab-separated-values") == "\t")
        #expect(ArtifactTable.delimiter(name: "counts.csv", mime: "text/csv") == ",")
        let table = parse("gene\tcount\tnote\nA\t3\t\"tab\there\"\nB,C\t4\t\n", "\t")
        #expect(table.rows == [["A", "3", "tab\there"], ["B,C", "4", ""]])
    }
}

// MARK: Headers

struct ArtifactHeaderTests {
    private func isSafeHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    }

    @Test func hostileNamesMakeSafeDispositions() {
        let hostile = [
            "report\".pdf", "a\"; filename=\"evil.html", "evil\r\nSet-Cookie: bench_device=x.txt", "line\nbreak.csv",
            "Résumé – 日本語.csv", "../../etc/passwd", "..\\..\\boot.ini", "C:\\Users\\someone\\secret.docx",
            String(repeating: "長", count: 1_000) + ".csv", String(repeating: "a", count: 1_000),
            ".bashrc", "", "///", "100%25.txt", "semi;colon.txt", "tab\there.txt", "nul\u{0}byte.txt",
            "\u{202E}gnp.exe", "😀.png", "con:stream.txt",
        ]
        for name in hostile {
            let value = ArtifactHeaders.disposition(name)
            #expect(isSafeHeaderValue(value), "\(name)")
            #expect(value.hasPrefix("attachment; filename=\""), "\(name)")
            let ascii = ArtifactHeaders.asciiName(name)
            #expect(!ascii.isEmpty && ascii.count <= ArtifactHeaders.asciiLimit, "\(name)")
            #expect(!ascii.contains { "\"\\/;%:\r\n".contains($0) }, "\(name)")
            #expect(!ascii.hasPrefix("."), "\(name)")
            let encoded = ArtifactHeaders.encodedName(name)
            #expect(encoded.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._-%".unicodeScalars.contains($0)
            }, "\(name)")
            // Exactly the two parameters: nothing a name holds starts a third.
            #expect(value.components(separatedBy: ";").count == 3, "\(name)")
        }
    }

    @Test func namesReadWellWhenTheyCan() {
        #expect(ArtifactHeaders.asciiName("figure 2.png") == "figure 2.png")
        #expect(ArtifactHeaders.asciiName("Résumé.pdf") == "Resume.pdf")
        #expect(ArtifactHeaders.asciiName("../../etc/passwd") == "passwd")
        #expect(ArtifactHeaders.asciiName("..\\..\\boot.ini") == "boot.ini")
        #expect(ArtifactHeaders.asciiName(".bashrc") == "_bashrc")
        #expect(ArtifactHeaders.asciiName("") == "file")
        #expect(ArtifactHeaders.asciiName("日本") == "file")
        #expect(ArtifactHeaders.asciiName("a\"b.txt") == "a_b.txt")
        #expect(ArtifactHeaders.asciiName("evil\r\nx.txt") == "evilx.txt")
        let long = ArtifactHeaders.asciiName(String(repeating: "a", count: 1_000) + ".csv")
        #expect(long.count == ArtifactHeaders.asciiLimit && long.hasSuffix(".csv"))
        #expect(ArtifactHeaders.encodedName("Résumé.pdf") == "R%C3%A9sum%C3%A9.pdf")
        #expect(ArtifactHeaders.encodedName("a b\"c.txt") == "a%20b%22c.txt")
        #expect(ArtifactHeaders.encodedName("dir/x.txt") == "x.txt")
        #expect(ArtifactHeaders.encodedName(String(repeating: "長", count: 1_000) + ".csv").hasSuffix(".csv"))
    }

    @Test func onlyRasterMagicIsSniffed() {
        #expect(ArtifactHeaders.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])) == "image/png")
        #expect(ArtifactHeaders.sniff(Data([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
        #expect(ArtifactHeaders.sniff(Data("GIF89a..".utf8)) == "image/gif")
        #expect(ArtifactHeaders.sniff(Data("RIFF\u{4}\0\0\0WEBPVP8L".utf8)) == "image/webp")
        #expect(ArtifactHeaders.sniff(Data("RIFF\u{4}\0\0\0WAVEfmt ".utf8)) == nil)
        #expect(ArtifactHeaders.sniff(Data("<svg xmlns=".utf8)) == nil)
        #expect(ArtifactHeaders.sniff(Data("<!doctype html>".utf8)) == nil)
        #expect(ArtifactHeaders.sniff(Data()) == nil)
        #expect(!ArtifactHeaders.isWebP(Data("RIFF".utf8)))
    }

    /// The whole response, its header lines by lowercased name.
    static func headers(_ reply: RemoteFilesReply) -> (status: String, lines: [String: [String]]) {
        let response = reply.response
        let end = response.range(of: Data("\r\n\r\n".utf8))!.lowerBound
        let head = String(decoding: response[..<end], as: UTF8.self).components(separatedBy: "\r\n")
        var lines: [String: [String]] = [:]
        for line in head.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            lines[parts[0].lowercased(), default: []].append(parts[1].trimmingCharacters(in: .whitespaces))
        }
        #expect(response.count == end + 4 + reply.body.count)
        return (head[0], lines)
    }

    @Test func aDownloadGoesOutAsAnAttachmentUnderSandbox() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let (status, lines) = Self.headers(.download(png, name: "plot \"1\".png", kind: .image))
        #expect(status == "HTTP/1.1 200 OK")
        #expect(lines["content-type"] == ["image/png"])
        #expect(lines["content-disposition"] == [#"attachment; filename="plot _1_.png"; filename*=UTF-8''plot%20%221%22.png"#])
        #expect(lines["content-security-policy"] == ["default-src 'none'; sandbox"])
        #expect(lines["x-content-type-options"] == ["nosniff"])
        #expect(lines["cross-origin-resource-policy"] == ["same-origin"])
        #expect(lines["cache-control"] == ["no-store"])
        #expect(lines["content-length"] == ["\(png.count)"])
    }

    @Test func scriptCapableKindsAreNeverServedAsSomethingThatRenders() {
        let page = Data("<!doctype html><script>alert(1)</script>".utf8)
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + page
        for kind in [ArtifactKind.html, .svg, .notebook, .markdown, .text, .other, .pdf] {
            for bytes in [page, pngMagic] {
                let (_, lines) = Self.headers(.download(bytes, name: "x.html", kind: kind))
                #expect(lines["content-type"] == ["application/octet-stream"], "\(kind)")
                #expect(lines["content-disposition"]?.first?.hasPrefix("attachment;") == true)
                #expect(lines["content-security-policy"] == ["default-src 'none'; sandbox"])
            }
        }
        // An "image" whose bytes are a page: bytes, not a page.
        #expect(Self.headers(.download(page, name: "x.png", kind: .image)).lines["content-type"] == ["application/octet-stream"])
    }
}

// MARK: The routes

@MainActor
struct ArtifactRouteTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let policy = RemotePolicy.tailnet(dnsName: host, login: "pat@example.com")

    private func evaluate(_ method: String, _ target: String, cookie: Bool = true) -> RemoteCheck.Outcome {
        var headers: [String: [String]] = ["host": ["\(Self.host):8443"], "tailscale-user-login": ["pat@example.com"]]
        if cookie { headers["cookie"] = ["bench_device=\(String(repeating: "A", count: 43))"] }
        return RemoteCheck.evaluate(RemoteRequest(method: method, target: target, headers: headers), policy: Self.policy)
    }

    @Test func theFourRoutesAreInTheTable() {
        let token = String(repeating: "A", count: 43), v = Made.version
        #expect(evaluate("GET", "/api/sessions/\(Made.session)/artifacts")
                == .accept(.files(.list(session: Made.session)), token: token))
        #expect(evaluate("GET", "/api/files/\(v)/thumb?w=120") == .accept(.files(.thumb(version: v)), token: token))
        #expect(evaluate("GET", "/api/files/\(v)/text") == .accept(.files(.text(version: v)), token: token))
        #expect(evaluate("GET", "/api/files/\(v)/download") == .accept(.files(.download(version: v)), token: token))
        #expect(RemoteRoute.files(.list(session: Made.session)).pattern == "/api/sessions/<id>/artifacts")
        #expect(RemoteRoute.files(.thumb(version: v)).pattern == "/api/files/<v>/thumb")
        #expect(RemoteRoute.files(.download(version: v)).pattern == "/api/files/<v>/download")
        // Phase 2's routes are as they were.
        #expect(RemoteRoute.match(method: "GET", path: Substring("/api/sessions/\(Made.session)")) == .found(.session(Made.session)))
        #expect(RemoteRoute.match(method: "POST", path: Substring("/api/sessions/\(Made.session)/approve"))
                == .found(.action(.approve, Made.session)))
    }

    @Test func anythingElseIsRefused() {
        func status(_ outcome: RemoteCheck.Outcome) -> Int {
            if case .reject(let status, _, _) = outcome { status } else { 200 }
        }
        #expect(status(evaluate("POST", "/api/files/v1/download")) == 405)
        #expect(status(evaluate("GET", "/api/files/v1/download", cookie: false)) == 401)
        for path in ["/api/files/v1", "/api/files/v1/raw", "/api/files/v1/text/more", "/api/files/a.b/text",
                     "/api/files/%2E%2E/text", "/api/files//text", "/api/files/\(String(repeating: "a", count: 129))/text",
                     "/api/sessions/\(Made.session.uppercased())/artifacts", "/api/sessions/short/artifacts",
                     "/api/files/v1/download/", "/api/projects/p/artifacts"] {
            #expect(status(evaluate("GET", path)) == 404, "\(path)")
        }
    }

    @Test func theWidthIsExactlyOneOfTwo() {
        #expect(RemoteArtifacts.width("/api/files/v/thumb?w=120") == 120)
        #expect(RemoteArtifacts.width("/api/files/v/thumb?w=800") == 800)
        for target in ["/api/files/v/thumb", "/api/files/v/thumb?w=400", "/api/files/v/thumb?w=120&x=1",
                       "/api/files/v/thumb?w=0120", "/api/files/v/thumb?W=120", "/api/files/v/thumb?"] {
            #expect(RemoteArtifacts.width(target) == nil, "\(target)")
        }
    }
}

// MARK: Serving

@MainActor
private final class FakeFiles {
    var browse = true
    var sessions: Set<String> = [Made.session]
    var answers: [ArtifactRead: ArtifactReadOutcome] = [:]
    var reads: [ArtifactRead] = []
    let listed = ListedFiles()
    let info = ListedFileInfo()

    lazy var artifacts = RemoteArtifacts(dependencies: .init(
        browseOn: { [unowned self] in self.browse },
        isSession: { [unowned self] in self.sessions.contains($0) },
        read: { [unowned self] read in
            self.reads.append(read)
            return self.answers[read] ?? .unreadable
        },
        listed: listed, info: info))

    func get(_ target: String, device: String = "phone") async -> RemoteFilesReply {
        guard let route = RemoteFilesRoute(path: target.prefix { $0 != "?" }) else { return .notFound }
        return await artifacts.respond(route, target: target, device: device)
    }

    /// Lists these entries to `device`, through the list route.
    func list(_ entries: [ArtifactEntry], device: String = "phone") async -> RemoteFilesReply {
        answers[.list(frame: Made.session)] = .list(entries)
        return await get("/api/sessions/\(Made.session)/artifacts", device: device)
    }
}

@MainActor
struct ArtifactServingTests {
    private func json(_ reply: RemoteFilesReply) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any] ?? [:]
    }

    @Test func browseOffRefusesEveryRouteBeforeReading() async {
        let files = FakeFiles()
        _ = await files.list([Made.entry("a.md")])
        files.browse = false
        files.reads = []
        for target in ["/api/sessions/\(Made.session)/artifacts", "/api/files/ver_1/thumb?w=120",
                       "/api/files/ver_1/text", "/api/files/ver_1/download"] {
            let reply = await files.get(target)
            #expect(reply.status == 403)
            #expect(json(reply)["error"] as? String == "browseOff")
        }
        #expect(files.reads.isEmpty)
    }

    @Test func theListIsSortedRecordedAndNamesNoPath() async throws {
        let files = FakeFiles()
        let entries = [
            Made.entry("run.log", version: "v-log"), Made.entry("figure.png", version: "v-png", mime: "image/png"),
            Made.entry("counts.csv", version: "v-csv"), Made.entry("report.md", version: "v-md"),
            Made.entry("page.html", version: "v-html"), Made.entry("plot.svg", version: "v-svg"),
            Made.entry("blob.bin", version: "v-bin"), Made.entry("paper.pdf", version: "v-pdf"),
        ]
        let reply = await files.list(entries)
        #expect(reply.status == 200)
        #expect(reply.contentType == RemoteResponse.json)
        let list = try #require(json(reply)["artifacts"] as? [[String: Any]])
        #expect(list.map { $0["v"] as? String } == ["v-md", "v-html", "v-pdf", "v-png", "v-svg", "v-csv", "v-log", "v-bin"])
        #expect(list.map { $0["kind"] as? String } == ["markdown", "html", "pdf", "image", "svg", "table", "text", "other"])
        #expect(Set(list[0].keys) == ["v", "a", "name", "kind", "size", "mime", "at"])
        #expect(list[0]["mime"] is NSNull && list[0]["at"] is NSNull)
        for entry in entries {
            #expect(files.listed.allows(entry.version, device: "phone"))
            #expect(!files.listed.allows(entry.version, device: "tablet"))
            #expect(files.info.info(entry.version)?.kind == entry.kind)
        }
    }

    @Test func aSessionBenchDoesntKnowIsNotRead() async {
        let files = FakeFiles()
        files.sessions = []
        #expect(await files.get("/api/sessions/\(Made.session)/artifacts").status == 404)
        #expect(files.reads.isEmpty)
        files.sessions = [Made.session]
        #expect(await files.get("/api/sessions/\(Made.session)/artifacts").status == 503)
    }

    @Test func onlyWhatWasListedToThisDeviceIsServed() async {
        let files = FakeFiles()
        files.answers[.download(version: "ver_1")] = .bytes(Data("hello".utf8))
        #expect(await files.get("/api/files/ver_1/download").status == 404)
        _ = await files.list([Made.entry("hello.txt")], device: "phone")
        #expect(await files.get("/api/files/ver_1/download", device: "tablet").status == 404)
        #expect(await files.get("/api/files/ver_2/download").status == 404)
        #expect(await files.get("/api/files/ver_1/download").status == 200)
        // Listed some other way, without its listing: still not served.
        files.listed.record(["ver_9"], device: "phone")
        #expect(await files.get("/api/files/ver_9/download").status == 404)
        #expect(files.reads == [.list(frame: Made.session), .download(version: "ver_1")])
    }

    @Test func thumbnailsOnlyForImagesAndOnlyWebP() async {
        let files = FakeFiles()
        _ = await files.list([Made.entry("a.png", version: "img", mime: "image/png"), Made.entry("b.svg", version: "svg"),
                              Made.entry("c.html", version: "page")])
        let webp = Data("RIFF\u{4}\0\0\0WEBPVP8L".utf8)
        files.answers[.thumb(version: "img", width: 800)] = .bytes(webp)
        files.answers[.thumb(version: "img", width: 120)] = .bytes(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let good = await files.get("/api/files/img/thumb?w=800")
        #expect(good.status == 200 && good.contentType == "image/webp" && good.body == webp)
        #expect(good.headers.contains(.init(name: "Content-Security-Policy", value: "default-src 'none'; sandbox")))
        let notWebP = await files.get("/api/files/img/thumb?w=120")
        #expect(notWebP.status == 415 && json(notWebP)["error"] as? String == "notWebP")
        #expect(await files.get("/api/files/img/thumb?w=400").status == 400)
        #expect(await files.get("/api/files/img/thumb").status == 400)
        files.reads = []
        for version in ["svg", "page"] {
            let reply = await files.get("/api/files/\(version)/thumb?w=120")
            #expect(reply.status == 415 && json(reply)["error"] as? String == "kind")
        }
        #expect(files.reads.isEmpty)
        files.answers[.thumb(version: "img", width: 120)] = .tooBig
        #expect(await files.get("/api/files/img/thumb?w=120").status == 413)
    }

    @Test func textForMarkdownTextAndTablesOnly() async throws {
        let files = FakeFiles()
        _ = await files.list([Made.entry("a.md", version: "md"), Made.entry("b.log", version: "log"),
                              Made.entry("c.tsv", version: "tsv"), Made.entry("d.html", version: "html"),
                              Made.entry("e.svg", version: "svg"), Made.entry("f.ipynb", version: "nb"),
                              Made.entry("g.png", version: "png"), Made.entry("h.pdf", version: "pdf"),
                              Made.entry("i.zip", version: "zip")])
        files.answers[.text(version: "md")] = .text("\u{FEFF}# Made up", truncated: false)
        files.answers[.text(version: "log")] = .text("line", truncated: true)
        files.answers[.text(version: "tsv")] = .text("a\tb\n1\t2\n3", truncated: true)

        let markdown = json(await files.get("/api/files/md/text"))
        #expect(markdown["kind"] as? String == "markdown" && markdown["text"] as? String == "# Made up")
        #expect(markdown["truncated"] as? Bool == false)
        let log = json(await files.get("/api/files/log/text"))
        #expect(log["kind"] as? String == "text" && log["truncated"] as? Bool == true)
        let table = json(await files.get("/api/files/tsv/text"))
        #expect(table["kind"] as? String == "table")
        #expect(table["columns"] as? [String] == ["a", "b"])
        #expect(table["rows"] as? [[String]] == [["1", "2"]])
        #expect(table["truncated"] as? Bool == true)

        files.reads = []
        for version in ["html", "svg", "nb", "png", "pdf", "zip"] {
            let reply = await files.get("/api/files/\(version)/text")
            #expect(reply.status == 415 && json(reply)["error"] as? String == "kind", "\(version)")
        }
        #expect(files.reads.isEmpty)
        files.answers[.text(version: "log")] = .binary
        #expect(json(await files.get("/api/files/log/text"))["error"] as? String == "notText")
        files.answers[.text(version: "log")] = .unreadable
        #expect(await files.get("/api/files/log/text").status == 503)
        // A version that's gone answers the phone as it always did.
        files.answers[.text(version: "log")] = .missing
        #expect(await files.get("/api/files/log/text").status == 503)
    }

    @Test func downloadsCheckTheListedSizeFirstThenTheBytes() async {
        let files = FakeFiles()
        let cap = ArtifactReaderScript.Cap.download
        _ = await files.list([Made.entry("big.zip", version: "big", size: cap + 1),
                              Made.entry("liar.zip", version: "liar", size: 10),
                              Made.entry("ok.bin", version: "ok", size: cap)])
        files.reads = []
        let big = await files.get("/api/files/big/download")
        #expect(big.status == 413 && json(big)["error"] as? String == "tooBig")
        #expect(files.reads.isEmpty)
        files.answers[.download(version: "liar")] = .tooBig
        #expect(await files.get("/api/files/liar/download").status == 413)
        files.answers[.download(version: "liar")] = .bytes(Data(count: cap + 1))
        #expect(await files.get("/api/files/liar/download").status == 413)
        files.answers[.download(version: "ok")] = .bytes(Data(count: cap))
        let ok = await files.get("/api/files/ok/download")
        #expect(ok.status == 200 && ok.body.count == cap)
        #expect(ok.response.count > cap)
    }

    @Test func htmlSvgAndNotebooksOnlyEverDownload() async {
        let files = FakeFiles()
        _ = await files.list([Made.entry("page.html", version: "html", mime: "text/html"),
                              Made.entry("plot.svg", version: "svg", mime: "image/svg+xml"),
                              Made.entry("run.ipynb", version: "nb"),
                              Made.entry("sneaky.png", version: "sneaky", mime: "text/html")])
        let script = Data("<svg onload=alert(1)><script>alert(2)</script></svg>".utf8)
        for version in ["html", "svg", "nb", "sneaky"] {
            files.answers[.download(version: version)] = .bytes(script)
            files.answers[.thumb(version: version, width: 800)] = .bytes(script)
            files.answers[.text(version: version)] = .text("<script>", truncated: false)
            #expect(await files.get("/api/files/\(version)/thumb?w=800").status == 415)
            #expect(await files.get("/api/files/\(version)/text").status == 415)
            let download = await files.get("/api/files/\(version)/download")
            #expect(download.status == 200)
            let (_, lines) = ArtifactHeaderTests.headers(download)
            #expect(lines["content-type"] == ["application/octet-stream"], "\(version)")
            #expect(lines["content-disposition"]?.first?.hasPrefix("attachment; filename=") == true)
            #expect(lines["content-security-policy"] == ["default-src 'none'; sandbox"])
            #expect(lines["x-content-type-options"] == ["nosniff"])
        }
    }

    @Test func listingsAreRememberedAnHour() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let info = ListedFileInfo(now: { now })
        let made = ListedFileInfo.Info(name: "a.md", mime: nil, size: 1, kind: .markdown)
        info.record("v1", made)
        now += ListedFileInfo.lifetime - 1
        #expect(info.info("v1") == made)
        now += 2
        #expect(info.info("v1") == nil)
    }

    @Test func pastCapacityTheOldestTenthGoesAtOnce() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let info = ListedFileInfo(now: { now })
        let made = ListedFileInfo.Info(name: "a.md", mime: nil, size: 1, kind: .markdown)
        for n in 0...ListedFileInfo.capacity {
            now += 0.01
            info.record("v\(n)", made)
        }
        let room = ListedFileInfo.capacity - ListedFileInfo.capacity / 10
        #expect(info.count == room)
        #expect(info.info("v\(ListedFileInfo.capacity)") == made)
        #expect(info.info("v0") == nil)
        now += 0.01
        info.record("next", made)
        #expect(info.count == room + 1)
    }
}

// MARK: `--demo remote`

@MainActor
struct ArtifactDemoTests {
    private static func sessions() -> [SessionStatus] {
        let now = Date()
        return [("d6", "Primer design", SessionState.finished), ("d1", "Protein stability screen", .needsInput),
                ("d7", "Gel quantification", .needsInput), ("d5", "Plate layout", .running)].map {
            SessionStatus(id: "00000000-0000-4000-8000-0000000000\($0.0)", projectID: "demo", projectName: "Example project",
                          title: $0.1, state: $0.2, updatedAt: now)
        }
    }

    private func demo() -> (RemoteArtifacts, [SessionStatus]) {
        let sessions = Self.sessions()
        return (RemoteArtifacts.demo(known: { sessions }, browseOn: { true }), sessions)
    }

    private func get(_ artifacts: RemoteArtifacts, _ target: String) async -> RemoteFilesReply {
        await artifacts.respond(RemoteFilesRoute(path: target.prefix { $0 != "?" })!, target: target, device: "phone")
    }

    private func listing(_ artifacts: RemoteArtifacts, _ session: String) async -> [[String: Any]] {
        let reply = await get(artifacts, "/api/sessions/\(session)/artifacts")
        return ((try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any])?["artifacts"] as? [[String: Any]] ?? []
    }

    @Test func everyKindIsThere() async {
        let (artifacts, sessions) = demo()
        let list = await listing(artifacts, sessions[0].id)
        let kinds = Set(list.compactMap { $0["kind"] as? String })
        #expect(kinds == Set(ArtifactKind.allCases.map(\.rawValue)))
        #expect(await listing(artifacts, sessions[3].id).isEmpty)
        #expect(await get(artifacts, "/api/sessions/\(sessions[2].id)/artifacts").status == 503)
    }

    @Test func theChartsThumbnailIsAWebPThatDecodes() async throws {
        let (artifacts, sessions) = demo()
        let list = await listing(artifacts, sessions[0].id)
        let png = try #require(list.first { $0["kind"] as? String == "image" }?["v"] as? String)
        for width in [120, 800] {
            let reply = await get(artifacts, "/api/files/\(png)/thumb?w=\(width)")
            #expect(reply.status == 200 && reply.contentType == "image/webp")
            let source = try #require(CGImageSourceCreateWithData(reply.body as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == width)
            #expect(image.height == Int((Double(width) * DemoChart.aspect).rounded()))
            // Its pixels are the chart's: ivory where the mask is off, clay where on.
            let (mask, _) = DemoChart.mask(bars: [58.4, 60.1, 61.7, 59.2, 62.0, 58.9], width: width)
            var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(CGContext(data: &rgba, width: image.width, height: image.height, bitsPerComponent: 8,
                                                 bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var wrong = 0
            for (index, on) in mask.enumerated() {
                // Green: clay's and ivory's are far apart.
                let green = Int(rgba[index * 4 + 1])
                let nearClay = abs(green - Int(DemoChart.clay.1)) < abs(green - Int(DemoChart.ivory.1))
                if nearClay != on { wrong += 1 }
            }
            #expect(wrong == 0)
            #expect(mask.contains(true) && mask.contains(false))
        }
    }

    @Test func downloadsTextAndTheCaps() async throws {
        let (artifacts, sessions) = demo()
        let list = await listing(artifacts, sessions[0].id)
        func version(_ name: String) throws -> String {
            try #require(list.first { $0["name"] as? String == name }?["v"] as? String)
        }
        let png = await get(artifacts, "/api/files/\(try version("primer-melting-points.png"))/download")
        #expect(png.status == 200 && png.contentType == "image/png")
        #expect(CGImageSourceCreateWithData(png.body as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil)
        let raw = await get(artifacts, "/api/files/\(try version("plate-reader-raw.dat"))/download")
        #expect(raw.status == 200 && raw.body.count == ArtifactReaderScript.Cap.download)
        #expect(raw.contentType == "application/octet-stream")
        #expect(await get(artifacts, "/api/files/\(try version("gel-images.zip"))/download").status == 413)
        let html = await get(artifacts, "/api/files/\(try version("summary.html"))/download")
        #expect(html.status == 200 && html.contentType == "application/octet-stream")
        let pdf = await get(artifacts, "/api/files/\(try version("primer-design.pdf"))/download")
        #expect(pdf.body.starts(with: Data("%PDF".utf8)))
        let table = await get(artifacts, "/api/files/\(try version("primer-pairs.csv"))/text")
        let parsed = try #require((try JSONSerialization.jsonObject(with: table.body)) as? [String: Any])
        #expect(parsed["columns"] as? [String] == ["pair", "gene", "forward", "reverse", "tm_c", "note"])
        let rows = try #require(parsed["rows"] as? [[String]])
        #expect(rows.count == 6)
        #expect(rows[2][5] == "says \"check\" on gel")
        #expect(rows[4][5] == "two\nlines")
        let markdown = await get(artifacts, "/api/files/\(try version("primer-report.md"))/text")
        #expect(markdown.status == 200)
        #expect(await get(artifacts, "/api/files/\(try version("plate-map.svg"))/thumb?w=120").status == 415)
    }
}
