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
            return (async function (op, frameId, versionId, width) {
            \(ArtifactReaderScript.body)
            })(a.op, a.frameId, a.versionId, a.width);
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
                        + ArtifactReaderScript.codecs + "\n" + source)
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
            let built = page.evaluate("var a = JSON.parse(__args); JSON.stringify(benchArtifactPath(a.op, a.frameId, a.versionId, a.width))")
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
        #expect(page.run(.list(frame: Made.session), [Made.listPath: .init(status: 404, text: "{}")]).outcome == .unreadable)
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
        for status in [204, 206, 302, 403, 404, 500] {
            let result = page.run(.download(version: Made.version), [Made.versionPath: .init(status: status, length: 4)])
            #expect(result.outcome == .unreadable, "\(status)")
        }
        #expect(page.run(.download(version: Made.version), [Made.versionPath: .init(status: 401)]).outcome == .lost)
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
