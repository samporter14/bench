// RemotePhotosFlowTests.swift — the phone's photos past the picture: the
// upload's in-page script run in JavaScriptCore against a fake daemon that
// records every request (with shims for what a bare JSContext lacks: `atob`,
// `Blob`, `FormData`), the writer's room for the attachment line, the whole
// flow of both routes against fakes that only record what they were asked,
// and the server itself taking a photo's body slowly. Nothing reaches a real
// daemon, database or web view.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let intent = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"
private let attachmentID = "11111111-2222-4333-8444-555555555555"
private let versionID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
private let newID = "9f8e7d6c-5b4a-4321-8fed-cba987654321"

private func decode(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

private func decode(_ reply: RemoteActionReply) -> [String: Any] {
    decode(reply.body)
}

private func someBytes(_ count: Int, name: String = "phone-photo-20261012-193000.jpg") -> PhotoFile {
    PhotoFile(data: Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) }), name: name, width: 4, height: 3)
}

// MARK: The upload script

struct PhotoUploadBuilderTests {
    private func build(_ arguments: [String: Any]) -> [String: Any]? {
        let script = PageScript(PhotoUploadScript.builder)
        let json = String(decoding: PhotoFixture.json(arguments), as: UTF8.self)
        guard let answer = script.callJSON("benchBuildUpload", [json]) else { return nil }
        #expect(script.exception == nil)
        return (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any]
    }

    private let good = PhotoUploadScript.arguments(project: "proj_a-1", photo: someBytes(10))

    @Test func theOnePathAndNothingTheArgumentsCanChange() {
        let made = build(good)
        #expect(made?["path"] as? String == "/api/projects/proj_a-1/attachments")
        #expect(made?["filename"] as? String == "phone-photo-20261012-193000.jpg")
        #expect(made?["contentType"] as? String == "image/jpeg")
        #expect(made?["size"] as? Int == 10)
        var withPath = good
        withPath["path"] = "/api/frames/x/approve-plan"
        withPath["url"] = "https://evil.example.com/"
        #expect(build(withPath)?["path"] as? String == "/api/projects/proj_a-1/attachments")
        #expect(PageScript(PhotoUploadScript.builder).callJSON("benchBuildUpload", [nil]) == "null")
        #expect(PageScript(PhotoUploadScript.builder).callJSON("benchBuildUpload", ["[1]"]) == "null")
    }

    @Test(arguments: [
        ("projectId", "../x"), ("projectId", "a/b"), ("projectId", ""), ("projectId", String(repeating: "a", count: 65)),
        ("projectId", "a b"), ("projectId", "a?b=1"), ("projectId", "a%2Fb"),
        ("filename", "../phone-photo-20261012-193000.jpg"), ("filename", "IMG_0001.jpg"), ("filename", "phone-photo-20261012-193000.JPG"),
        ("filename", "phone-photo-20261012-193000.jpg\""), ("filename", "phone-photo-2026101-193000.jpg"), ("filename", ""),
        ("contentType", "image/png"), ("contentType", "image/jpeg; charset=utf-8"), ("contentType", "application/octet-stream"),
        ("data", "AA AA AAAA"), ("data", "AAA"), ("data", "AAAA=AAA"), ("data", "AAAAAAAAAAAA"), ("data", ""),
        ("data", "!!!!!!!!!!!!"), ("data", "AAAAAAAA"),
        // The right length for 10 bytes (16 characters), and still not base64.
        ("data", "AAAAAAAA AAAAAAA"), ("data", "AAAAAAAA!AAAAAAA"), ("data", "AAAAAAA=AAAAAAAA"), ("data", "AAAAAAAAAAAAAA\n="),
    ])
    func anythingElseBuildsNothing(_ name: String, _ value: String) {
        var arguments = good
        arguments[name] = value
        #expect(build(arguments) == nil)
    }

    @Test func theSizeAndTheDataMustAgreeAndStayWithinThreeMebibytes() {
        var arguments = good
        for size in [0, -1, 9, 13, 3 * 1024 * 1024 + 1] as [Any] {
            arguments["size"] = size
            #expect(build(arguments) == nil, "\(size)")
        }
        arguments["size"] = "10"
        #expect(build(arguments) == nil)
        arguments["size"] = 10.5
        #expect(build(arguments) == nil)
        // 3 MiB exactly is allowed: 4,194,304 characters of base64.
        let big = PhotoUploadScript.arguments(project: "p", photo: someBytes(PhotoImage.maxBytes))
        #expect((big["data"] as? String)?.count == 4_194_304)
        #expect(build(big)?["size"] as? Int == PhotoImage.maxBytes)
        #expect(PhotoImage.maxBytes == 3_145_728)
    }
}

/// A bare JSContext has no `atob`, `Blob`, `FormData` or `fetch`: these stand in,
/// and the fake `fetch` records everything a script sends, forms included.
private let uploadPrelude = """
var __requests = [];
var __table = JSON.parse(__answers);
var __seen = {};
var __forms = 0;
var __result = null;
var document = { cookie: __cookie };
var AbortSignal = function () {};
AbortSignal.timeout = function () { return undefined; };
var Blob = function (parts, options) {
    var size = 0;
    for (var i = 0; i < parts.length; i++) { size += parts[i].length; }
    this.size = size;
    this.type = options && options.type ? options.type : "";
};
var FormData = function () { this.entries = []; this.serial = ++__forms; };
FormData.prototype.append = function (name, blob, filename) {
    this.entries.push({ name: name, filename: filename, type: blob.type, size: blob.size });
};
var atob = function (text) {
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var table = {};
    for (var k = 0; k < 64; k++) { table[alphabet.charAt(k)] = k; }
    var out = [], acc = 0, bits = 0;
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i);
        if (c === "=") { break; }
        acc = (acc << 6) | table[c];
        bits += 6;
        if (bits >= 8) { bits -= 8; out.push(String.fromCharCode((acc >> bits) & 255)); acc &= (1 << bits) - 1; }
    }
    return out.join("");
};
var fetch = function (path, init) {
    init = init || {};
    var headers = init.headers || {};
    var isForm = init.body instanceof FormData;
    __requests.push({ path: path, method: init.method || "GET", headerNames: Object.keys(headers),
                      csrf: typeof headers["x-operon-csrf"] === "string" ? headers["x-operon-csrf"] : null,
                      cache: typeof init.cache === "string" ? init.cache : null,
                      credentials: typeof init.credentials === "string" ? init.credentials : null,
                      isForm: isForm, serial: isForm ? init.body.serial : 0, entries: isForm ? init.body.entries : [] });
    var list = __table[path];
    if (!list || list.length === 0) { return Promise.reject(new Error("no answer for " + path)); }
    var n = __seen[path] || 0;
    __seen[path] = n + 1;
    var answer = list[Math.min(n, list.length - 1)];
    return Promise.resolve({ status: answer.status, ok: answer.status >= 200 && answer.status < 300,
                             text: function () { return Promise.resolve(answer.body); } });
};
"""

private struct UploadRun {
    var raw: String?
    var requests: [[String: Any]]
    var exception: String?

    func reply(sent: PhotoFile) -> PhotoUploadReply? {
        raw.flatMap { try? PhotoUploadScript.result(of: Data($0.utf8), sent: sent) }
    }
}

private func runUpload(_ photo: PhotoFile, project: String = "proj_a", overrides: [String: Any] = [:],
                       answers: [String: [PageScript.Answer]],
                       cookie: String = "theme=dark; operon_csrf=secret%20one") -> UploadRun {
    let script = PageScript()
    script.set("__answers", (try? JSONEncoder().encode(answers)).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
    script.set("__cookie", cookie)
    script.evaluate(uploadPrelude)
    var arguments = PhotoUploadScript.arguments(project: project, photo: photo)
    for (key, value) in overrides { arguments[key] = value }
    let names = ["projectId", "filename", "contentType", "data", "size"]
    var values: [String] = []
    for (index, name) in names.enumerated() {
        let data = (try? JSONSerialization.data(withJSONObject: arguments[name] ?? NSNull(), options: [.fragmentsAllowed])) ?? Data("null".utf8)
        script.set("__value\(index)", String(decoding: data, as: UTF8.self))
        values.append("JSON.parse(__value\(index))")
    }
    script.evaluate("""
    (async function (\(names.joined(separator: ", "))) {
    \(PhotoUploadScript.body)
    })(\(values.joined(separator: ", "))).then(function (v) { __result = v; }, function (e) { __result = "threw: " + e; });
    """)
    let raw = script.evaluate("__result")
    let json = script.evaluate("JSON.stringify(__requests)") ?? "[]"
    let requests = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]]) ?? []
    return UploadRun(raw: raw, requests: requests, exception: script.exception)
}

private func accepted(_ photo: PhotoFile, extra: String = "") -> PageScript.Answer {
    PageScript.Answer(status: 200, body: """
    {"id":"\(attachmentID)","version_id":"\(versionID)","root_frame_id":"SECRET-ROOT-FRAME","filename":"\(photo.name)",\
    "content_type":"image/jpeg","size_bytes":\(photo.data.count),"created_at":"2026-10-12T19:30:00Z",\
    "file_path":"/Users/someone/SECRET-PATH.jpg"\(extra)}
    """)
}

struct PhotoUploadPageTests {
    private let path = "/api/projects/proj_a/attachments"
    private let photo = someBytes(40)

    @Test func oneMultipartPostWithTheSecretAndNoContentType() {
        let run = runUpload(photo, answers: [path: [accepted(photo)]])
        #expect(run.exception == nil)
        #expect(run.requests.count == 1)
        let request = run.requests.first
        #expect(request?["path"] as? String == path)
        #expect(request?["method"] as? String == "POST")
        #expect(request?["isForm"] as? Bool == true)
        #expect(request?["csrf"] as? String == "secret one")
        #expect(request?["cache"] as? String == "no-store")
        #expect(request?["credentials"] as? String == "include")
        // `fetch` sets the type with its boundary: a header of ours would break it.
        #expect((request?["headerNames"] as? [String])?.sorted() == ["Accept", "x-operon-csrf"])
        let entries = request?["entries"] as? [[String: Any]]
        #expect(entries?.count == 1)
        #expect(entries?.first?["name"] as? String == "file")
        #expect(entries?.first?["filename"] as? String == photo.name)
        #expect(entries?.first?["type"] as? String == "image/jpeg")
        #expect(entries?.first?["size"] as? Int == 40)
    }

    @Test func onlyTheFiveFieldsComeBack() throws {
        let run = runUpload(photo, answers: [path: [accepted(photo)]])
        let raw = try #require(run.raw)
        for secret in ["SECRET", "file_path", "root_frame_id", "created_at", "/Users"] { #expect(!raw.contains(secret), "\(secret)") }
        let reply = try #require(run.reply(sent: photo))
        #expect(reply == PhotoUploadReply(status: 200, upload: PhotoAttachment(
            id: attachmentID, versionID: versionID, filename: photo.name, contentType: "image/jpeg", sizeBytes: 40)))
        let upload = try #require(((try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])?["result"] as? [String: Any])?["upload"] as? [String: Any])
        #expect(Set(upload.keys) == ["id", "version_id", "filename", "content_type", "size_bytes"])
    }

    @Test func aStaleSecretIsRefreshedAndTheFormBuiltAgain() {
        let stale = PageScript.Answer(status: 403, body: #"{"code":"csrf_stale"}"#)
        let run = runUpload(photo, answers: [path: [stale, accepted(photo)], "/api/csrf": [.init(status: 204, body: "")]])
        #expect(run.requests.map { $0["path"] as? String } == [path, "/api/csrf", path])
        #expect(run.requests.map { $0["method"] as? String } == ["POST", "GET", "POST"])
        let serials = run.requests.compactMap { $0["serial"] as? Int }.filter { $0 != 0 }
        #expect(serials == [1, 2])
        #expect((run.requests[2]["entries"] as? [[String: Any]])?.first?["size"] as? Int == 40)
        #expect(run.reply(sent: photo)?.upload != nil)
        // Only once.
        let twice = runUpload(photo, answers: [path: [stale], "/api/csrf": [.init(status: 204, body: "")]])
        #expect(twice.requests.map { $0["path"] as? String } == [path, "/api/csrf", path])
        #expect(twice.reply(sent: photo) == PhotoUploadReply(status: 403, code: "csrf_stale"))
    }

    @Test func aReplyThatDoesntMatchWhatWasSentIsNoUpload() {
        let good = accepted(photo).body
        let swaps: [(String, String)] = [
            (attachmentID, "not-a-uuid"), (attachmentID, "11111111-2222-4333-8444-55555555555"),
            (versionID, "x"), (#""filename":"\#(photo.name)""#, #""filename":"phone-photo-20261012-193001.jpg""#),
            (#""content_type":"image/jpeg""#, #""content_type":"image/png""#), (#""size_bytes":40"#, #""size_bytes":41"#),
            (#""size_bytes":40"#, #""size_bytes":"40""#), (#""id":"\#(attachmentID)""#, #""idd":"\#(attachmentID)""#),
            (#""version_id":"\#(versionID)""#, #""version_id":null"#),
        ]
        for (index, (from, to)) in swaps.enumerated() {
            let run = runUpload(photo, answers: [path: [.init(status: 200, body: good.replacingOccurrences(of: from, with: to))]])
            #expect(run.reply(sent: photo) == PhotoUploadReply(status: 200), "swap \(index)")
        }
        for body in ["", "ok", "<html>SECRET</html>", "[]", "null", #"{"detail":"No file uploaded"}"#] {
            let run = runUpload(photo, answers: [path: [.init(status: 200, body: body)]])
            #expect(run.reply(sent: photo) == PhotoUploadReply(status: 200), "\(body)")
            #expect(!(run.raw ?? "").contains("SECRET"))
        }
        for status in [201, 204, 400, 401, 404, 405, 413, 500] {
            let run = runUpload(photo, answers: [path: [.init(status: status, body: good)]])
            #expect(run.reply(sent: photo) == PhotoUploadReply(status: status), "\(status)")
        }
        // A UUID in capitals is still one.
        let upper = runUpload(photo, answers: [path: [.init(status: 200, body: good.replacingOccurrences(of: versionID, with: versionID.uppercased()))]])
        #expect(upper.reply(sent: photo)?.upload?.versionID == versionID.uppercased())
    }

    @Test func aReplyNamingAnotherSizeOrNameIsRefusedAgainInSwift() throws {
        let forged = #"{"result":{"status":200,"code":"","upload":{"id":"\#(attachmentID)","version_id":"\#(versionID)","filename":"phone-photo-20261012-193001.jpg","content_type":"image/jpeg","size_bytes":40}}}"#
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(forged.utf8), sent: photo) }
        let wrongSize = forged.replacingOccurrences(of: "193001", with: "193000").replacingOccurrences(of: ":40}", with: ":41}")
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(wrongSize.utf8), sent: photo) }
        let sound = forged.replacingOccurrences(of: "193001", with: "193000")
        #expect(try PhotoUploadScript.result(of: Data(sound.utf8), sent: photo).upload?.sizeBytes == 40)
        let notUUID = sound.replacingOccurrences(of: attachmentID, with: "../../x")
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(notUUID.utf8), sent: photo) }
        // An upload with a status that isn't 200 isn't one.
        let notOK = sound.replacingOccurrences(of: #""status":200"#, with: #""status":404"#)
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(notOK.utf8), sent: photo) }
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data("[]".utf8), sent: photo) }
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(#"{"failed":true}"#.utf8), sent: photo) }
        #expect(throws: WebAPIError.self) { try PhotoUploadScript.result(of: Data(#"{"refused":true}"#.utf8), sent: photo) }
    }

    @Test func refusedArgumentsSendNothing() {
        for overrides: [String: Any] in [["projectId": "../x"], ["filename": "IMG_1.jpg"], ["contentType": "image/png"], ["size": 41]] {
            let run = runUpload(photo, overrides: overrides, answers: [path: [accepted(photo)]])
            #expect(run.raw == #"{"refused":true}"#)
            #expect(run.requests.isEmpty)
        }
    }

    @Test func aRequestThatFailsIsNoResult() {
        let run = runUpload(photo, answers: [:])
        #expect(run.raw == #"{"failed":true}"#)
        #expect(run.reply(sent: photo) == nil)
    }

    @Test func aThreeMebibytePhotoGoesThroughThePage() {
        let big = someBytes(PhotoImage.maxBytes)
        let run = runUpload(big, answers: ["/api/projects/proj_a/attachments": [accepted(big)]])
        #expect(run.exception == nil)
        #expect(run.requests.count == 1)
        #expect((run.requests.first?["entries"] as? [[String: Any]])?.first?["size"] as? Int == PhotoImage.maxBytes)
        #expect(run.reply(sent: big)?.upload?.sizeBytes == PhotoImage.maxBytes)
    }
}

// MARK: The writer's room for the line

struct PhotoWriterRoomTests {
    private func builds(_ write: RemoteWrite) -> Bool {
        let script = PageScript(SessionWriterScript.builder)
        let json = String(decoding: PhotoFixture.json(write.arguments), as: UTF8.self)
        return script.callJSON("benchBuildWrite", [json]) != "null"
    }

    private let line = PhotoLineTests.attachment.line
    /// A photo's: the one flow that may end in the attachment line.
    private func message(_ text: String, attachment: Bool = true) -> RemoteWrite {
        .message(frame: root, agent: "made-up-agent", projectID: "proj-1", text: text, intentID: intent, attachment: attachment)
    }
    private func newSession(_ text: String, attachment: Bool = true) -> RemoteWrite {
        .newSession(project: "proj_a", text: text, planMode: false, intentID: intent, attachment: attachment)
    }

    @Test func aPhotosRequestIsTheTextABlankLineAndOneLine() {
        let text = String(repeating: "界", count: 4000)
        for make in [message, newSession] {
            #expect(builds(make(line, true)))
            #expect(builds(make("Look at this.\n\n" + line, true)))
            #expect(builds(make(text + "\n\n" + line, true)))
            // Plain text stays at 4,000, and the room is for that one line alone.
            #expect(!builds(make(text + "界", true)))
            #expect(!builds(make(text + "界\n\n" + line, true)))
            #expect(!builds(make(text + " " + line, true)))
            #expect(!builds(make(text + "\n" + line, true)))
            #expect(!builds(make("a\n\n" + line + "\n\nb" + String(repeating: "c", count: 4000), true)))
            // A line of any other shape gets no room.
            for odd in [line.replacingOccurrences(of: "phone-photo-20261012-193000.jpg", with: "a.jpg"),
                        line.replacingOccurrences(of: #""type":"attachment""#, with: #""type":"artifact""#),
                        line.replacingOccurrences(of: "image/jpeg", with: "image/png"),
                        line.replacingOccurrences(of: #""size_bytes":123456"#, with: #""size_bytes":-1"#),
                        line + " "] {
                #expect(!builds(make(text + "\n\n" + odd, true)))
            }
        }
    }

    @Test func aPlainMessageOrNewSessionGetsNoRoomForTheLine() {
        for make in [message, newSession] {
            // The very line a photo sends is refused anywhere else, alone or after text.
            #expect(!builds(make(line, false)))
            #expect(!builds(make("Look at this.\n\n" + line, false)))
            #expect(!builds(make("Look at this." + line, false)))
            // And ordinary text goes through, with or without the flag.
            #expect(builds(make("Look at this.", false)))
            #expect(builds(make("Look at this.", true)))
        }
    }

    @Test func onlyTheBooleanTrueOpensTheRoom() throws {
        for value: Any in ["true", 1, "yes", NSNull(), [true]] {
            var arguments = message(line).arguments
            arguments["attachment"] = value
            let script = PageScript(SessionWriterScript.builder)
            let json = String(decoding: PhotoFixture.json(arguments), as: UTF8.self)
            #expect(script.callJSON("benchBuildWrite", [json]) == "null", "\(value)")
        }
        // Left out of the arguments, the same.
        var left = message(line).arguments
        left["attachment"] = nil
        let script = PageScript(SessionWriterScript.builder)
        #expect(script.callJSON("benchBuildWrite", [String(decoding: PhotoFixture.json(left), as: UTF8.self)]) == "null")
        #expect(message(line).arguments["attachment"] as? Bool == true)
        #expect(message("x", attachment: false).arguments["attachment"] as? Bool == false)
    }

    @Test(arguments: [
        "{{artifact:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee}}", #"{"type":"artifact","id":"x"}"#, #"{"type":"attachment","id":"x"}"#,
        #"{"type":"skill","name":"x"}"#, #"{"type":"session","id":"x"}"#, #"{"artifact_ref":"x"}"#, #"{"file_path":"/x"}"#,
        #"{ "type" : "attachment", "id": "x"}"#, "{{ artifact: aaaa }}", "{\"type\":\n\"skill\"}",
    ])
    func aReferenceInTheTextIsRefusedEvenAfterThePhotosOwn(_ reference: String) {
        for make in [message, newSession] {
            #expect(!builds(make("look at " + reference, false)), "\(reference)")
            #expect(!builds(make(reference, false)), "\(reference)")
            // A photo's text is checked too, apart from the one line it ends in.
            #expect(!builds(make("look at " + reference + "\n\n" + line, true)), "\(reference)")
            #expect(!builds(make(reference, true)), "\(reference)")
        }
    }

    @Test(arguments: ["{x}", "use {{ var }} here", #"{"type": "gel"}"#, "the artifact: a figure", "{}"])
    func ordinaryBracesAreFine(_ text: String) {
        for make in [message, newSession] {
            #expect(builds(make(text, false)))
            #expect(builds(make(text + "\n\n" + line, true)))
        }
    }

    @Test func theRequestBodyCarriesTheLineAndTheText() {
        let script = PageScript(SessionWriterScript.builder)
        let text = "Look at this.\n\n" + line
        let json = String(decoding: PhotoFixture.json(message(text).arguments), as: UTF8.self)
        let write = script.callJSON("benchBuildWrite", [json]).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
        let input = (write?["body"] as? [String: Any])?["input_data"] as? [String: Any]
        #expect(input?["request"] as? String == text)
        #expect(Set(input?.keys.map { $0 } ?? []) == ["request"])
    }
}

// MARK: The flow, against fakes

@MainActor
private final class PhotoRig {
    enum Upload { case echo, none, status(Int), noUpload, wrongSize }

    var actionsOn = true
    var browseOn = true
    var known: [SessionStatus] = [Fixture.session(root, .finished, title: "Made-up session")]
    /// Handed out in turn, the last one repeating; a new list starts over.
    var reads: [SessionProjection?] = [PhotoRig.session("completed")] {
        didSet { readIndex = 0 }
    }
    var upload: Upload = .echo
    var writeReply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted")
    var createReply: RemoteWriteResult? = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: newID)
    var intents: [String?] = []
    var projects: [ProjectRow]? = [ProjectRow(id: "proj-1", name: "Made-up", sessions: 1, lastActiveMs: nil),
                                   ProjectRow(id: "proj_a", name: "Made-up A", sessions: 0, lastActiveMs: nil)]
    var now = Date(timeIntervalSince1970: 1_791_833_400)
    private(set) var log: [String] = []
    private(set) var writes: [RemoteWrite] = []
    private(set) var uploads: [(project: String, photo: PhotoFile)] = []
    private var readIndex = 0

    static func session(_ status: String, agent: String? = "made-up-agent", project: String? = "proj-1") -> SessionProjection {
        SessionProjection(status: status, agentName: agent, projectID: project)
    }

    lazy var sessions = RemoteSessions(dependencies: RemoteSessions.Dependencies(
        actionsOn: { [unowned self] in self.actionsOn },
        known: { [unowned self] in self.known },
        cardPlan: { _ in nil },
        read: { [unowned self] _, turns in
            self.log.append(turns ? "turns" : "read")
            let index = min(self.readIndex, self.reads.count - 1)
            self.readIndex += 1
            return self.reads.isEmpty ? nil : self.reads[index]
        },
        readPlan: { _ in nil },
        write: { [unowned self] write in
            self.log.append("write")
            self.writes.append(write)
            return self.writeReply
        },
        now: { [unowned self] in self.now },
        browseOn: { [unowned self] in self.browseOn },
        lookup: { _ in nil }))

    lazy var browser = RemoteBrowser(sessions: sessions, dependencies: RemoteBrowser.Dependencies(
        browseOn: { [unowned self] in self.browseOn },
        actionsOn: { [unowned self] in self.actionsOn },
        projects: { [unowned self] in self.log.append("projects"); return self.projects },
        sessions: { _, _, _ in nil },
        known: { [unowned self] in self.known },
        history: { _, _, _ in .unreadable },
        turn: { _, _ in .none },
        create: { [unowned self] write in
            self.log.append("create")
            self.writes.append(write)
            return self.createReply
        },
        findIntent: { [unowned self] _, _ in
            self.log.append("intent")
            return self.intents.isEmpty ? nil : self.intents.removeFirst()
        },
        listed: { _, _ in },
        now: { [unowned self] in self.now },
        pause: { [unowned self] in self.log.append("pause") }))

    lazy var photos = RemotePhotos(sessions: sessions, browser: browser, dependencies: RemotePhotos.Dependencies(
        upload: { [unowned self] project, photo in
            self.log.append("upload")
            self.uploads.append((project, photo))
            switch self.upload {
            case .echo:
                return PhotoUploadReply(status: 200, upload: PhotoAttachment(
                    id: attachmentID, versionID: versionID, filename: photo.name, contentType: photo.contentType,
                    sizeBytes: photo.data.count))
            case .wrongSize:
                return PhotoUploadReply(status: 200, upload: PhotoAttachment(
                    id: attachmentID, versionID: versionID, filename: photo.name, contentType: photo.contentType,
                    sizeBytes: photo.data.count + 1))
            case .none: return nil
            case .status(let status): return PhotoUploadReply(status: status)
            case .noUpload: return PhotoUploadReply(status: 200)
            }
        }))

    func session(_ body: Data, device: String = "device-1", id: String = root) async -> RemoteActionReply {
        await photos.respond(.session(id), device: device, body: body)
    }

    func project(_ body: Data, device: String = "device-1", id: String = "proj-1") async -> RemoteActionReply {
        await photos.respond(.project(id), device: device, body: body)
    }

    /// The line the upload made, as the daemon would be told it.
    func line(of photo: PhotoFile) -> String {
        PhotoAttachment(id: attachmentID, versionID: versionID, filename: photo.name, contentType: photo.contentType,
                        sizeBytes: photo.data.count).line
    }
}

@MainActor
struct RemotePhotosSessionTests {
    private let rig = PhotoRig()

    private func sentText(_ write: RemoteWrite?) -> String? {
        if case .message(_, _, _, let text, _, _)? = write { return text }
        return nil
    }

    @Test func aSessionThatTakesAMessageGetsThePhotoThenTheMessage() async throws {
        let reply = await rig.session(PhotoFixture.body(text: "  Look at this gel.  "))
        #expect(reply.status == 200)
        #expect(decode(reply.body)["result"] as? String == "sent")
        #expect(decode(reply.body)["sentence"] as? String == "Sent.")
        // Read, upload, read again (the message route's own), write.
        #expect(rig.log == ["read", "upload", "read", "write"])
        let upload = try #require(rig.uploads.first)
        #expect(rig.uploads.count == 1)
        #expect(upload.project == "proj-1")
        #expect(upload.photo.name == "phone-photo-20261012-193000.jpg")
        #expect(upload.photo.data.starts(with: [0xFF, 0xD8, 0xFF]))
        // The one write that may end in an attachment line says so.
        #expect(rig.writes == [.message(frame: root, agent: "made-up-agent", projectID: "proj-1",
                                        text: "Look at this gel.\n\n" + rig.line(of: upload.photo), intentID: intent, attachment: true)])
    }

    @Test func aPhotoAloneIsTheLineAlone() async throws {
        _ = await rig.session(PhotoFixture.body())
        let upload = try #require(rig.uploads.first)
        #expect(sentText(rig.writes.first) == rig.line(of: upload.photo))
    }

    @Test func theStatusDecidesTheWordAsItDoesForAMessage() async {
        rig.reads = [PhotoRig.session("processing")]
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "message_queued")
        let queued = decode(await rig.session(PhotoFixture.body(text: "x")))
        #expect(queued.string("result") == "queued")
        #expect(queued.string("sentence") == "Queued. Claude reads it at the next safe point.")
        rig.reads = [PhotoRig.session("failed")]
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "accepted")
        let resumed = decode(await rig.session(PhotoFixture.body(text: "x"), device: "device-2"))
        #expect(resumed.string("result") == "resumed")
        #expect(resumed.string("sentence") == "Sent. The session picks up again.")
        rig.reads = [PhotoRig.session("completed")]
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "already_delivered")
        #expect(decode(await rig.session(PhotoFixture.body(text: "x"), device: "device-3")).string("result") == "sent")
    }

    @Test func theAgentAndTheProjectComeFromTheFreshRead() async {
        rig.reads = [PhotoRig.session("completed", agent: "agent-before"), PhotoRig.session("completed", agent: "agent-after")]
        _ = await rig.session(PhotoFixture.body(text: "x"))
        #expect(rig.writes.first.map { if case .message(_, let agent, _, _, _, _) = $0 { agent } else { "" } } == "agent-after")
    }

    @Test func aSessionThatCantTakeAMessageGetsNothingUploaded() async {
        rig.reads = [PhotoRig.session("awaiting_user_response")]
        let blocked = await rig.session(PhotoFixture.body(text: "x"))
        #expect(decode(blocked.body).string("result") == "blocked")
        #expect(decode(blocked.body).string("sentence") == "Answer its question first.")
        rig.reads = [PhotoRig.session("awaiting_plan_approval")]
        #expect(decode(await rig.session(PhotoFixture.body(text: "x"), device: "b")).string("sentence") == "Approve or revise the plan on your Mac.")
        for unreadable in [nil, PhotoRig.session("completed", agent: nil), PhotoRig.session("completed", project: nil),
                           PhotoRig.session("replaced")] as [SessionProjection?] {
            rig.reads = [unreadable]
            let answer = await rig.session(PhotoFixture.body(text: "x"), device: "c-\(UUID().uuidString)")
            #expect(decode(answer.body).string("result") == (unreadable?.status == "replaced" ? "blocked" : "unavailable"))
        }
        #expect(rig.uploads.isEmpty)
        #expect(rig.writes.isEmpty)
        #expect(!rig.log.contains("upload"))
    }

    @Test func aProjectIdThatIsNotOneIsNeverUploadedTo() async {
        rig.reads = [PhotoRig.session("completed", project: "has space/../x")]
        let reply = await rig.session(PhotoFixture.body(text: "x"))
        #expect(decode(reply.body).string("result") == "unavailable")
        #expect(rig.uploads.isEmpty && rig.writes.isEmpty)
        #expect(decode(reply.body).string("sentence") == RemotePhotos.Sentence.notAttached)
    }

    @Test func aSessionThatChangedWhileItUploadedSavesThePhotoAndSaysSo() async {
        rig.reads = [PhotoRig.session("completed"), PhotoRig.session("awaiting_user_response")]
        let reply = await rig.session(PhotoFixture.body(text: "x"))
        #expect(rig.log == ["read", "upload", "read"])
        #expect(decode(reply.body).string("result") == "unavailable")
        #expect(decode(reply.body).string("sentence") == "The photo was saved to the project, but the message didn't send. Open it on your Mac.")
        #expect(rig.writes.isEmpty)
    }

    @Test func aReadThatLetGoOrMovedProjectAfterTheUploadSendsNothing() async {
        rig.reads = [PhotoRig.session("completed"), nil]
        #expect(decode(await rig.session(PhotoFixture.body(text: "x"))).string("sentence") == RemotePhotos.Sentence.savedNotSent)
        rig.reads = [PhotoRig.session("completed", project: "proj-1"), PhotoRig.session("completed", project: "proj-2")]
        #expect(decode(await rig.session(PhotoFixture.body(text: "x"), device: "b")).string("sentence") == RemotePhotos.Sentence.savedNotSent)
        #expect(rig.writes.isEmpty)
    }

    @Test func anUploadThatDidntWorkSendsNothing() async {
        for upload in [PhotoRig.Upload.none, .status(404), .status(413), .status(500), .noUpload, .wrongSize] {
            rig.upload = upload
            let reply = await rig.session(PhotoFixture.body(text: "x"), device: "d-\(UUID().uuidString)")
            #expect(reply.status == 200)
            #expect(decode(reply.body).string("result") == "unavailable")
            #expect(decode(reply.body).string("sentence") == "Couldn't attach the photo from here. Send it from your Mac.")
        }
        #expect(rig.writes.isEmpty)
        #expect(!rig.log.contains("write"))
        // One read, then the upload, and no second read.
        #expect(rig.log.filter { $0 == "read" }.count == 6)
    }

    @Test func aSendThatFailedAfterTheUploadIsUnavailableWithTheSavedSentence() async {
        let saved = "The photo was saved to the project, but the message didn't send. Open it on your Mac."
        let failures: [RemoteWriteResult?] = [nil, RemoteWriteResult(status: 500), RemoteWriteResult(status: 404),
                                              RemoteWriteResult(status: 429), RemoteWriteResult(status: 400, askPending: true),
                                              RemoteWriteResult(status: 200, isJSON: false)]
        for (index, failure) in failures.enumerated() {
            rig.writeReply = failure
            let reply = await rig.session(PhotoFixture.body(text: "x"), device: "d\(index)")
            #expect(decode(reply.body).string("result") == "unavailable", "\(index)")
            #expect(decode(reply.body).string("sentence") == saved, "\(index)")
        }
    }

    // MARK: A retry

    private let other = "6ba7b810-9dad-41d1-80b4-00c04fd430c8"

    @Test func aRetryOfThePhotoReusesTheUploadAndSendsTheSameLine() async throws {
        // The daemon took the message but its answer was lost: saved, not sent.
        rig.writeReply = nil
        let first = await rig.session(PhotoFixture.body(text: "Look at this gel."))
        #expect(decode(first.body).string("sentence") == RemotePhotos.Sentence.savedNotSent)
        #expect(rig.uploads.count == 1)
        // Send again: the same intent, the same picture.
        rig.writeReply = RemoteWriteResult(status: 200, bodyStatus: "already_delivered")
        let again = await rig.session(PhotoFixture.body(text: "Look at this gel."), device: "device-2")
        #expect(decode(again.body).string("result") == "sent")
        // One copy in the project, and both messages carry its line.
        #expect(rig.uploads.count == 1)
        #expect(rig.log == ["read", "upload", "read", "write", "read", "read", "write"])
        let upload = try #require(rig.uploads.first)
        #expect(sentText(rig.writes[1]) == "Look at this gel.\n\n" + rig.line(of: upload.photo))
        #expect(rig.writes.count == 2 && rig.writes[0] == rig.writes[1])
    }

    @Test func aRetryOnlyReusesTheUploadOfTheSameIntentThePhotoAndTheProject() async {
        rig.writeReply = nil
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "a")
        #expect(rig.uploads.count == 1)
        // Another intent, the same picture: its own upload.
        _ = await rig.session(PhotoFixture.body(text: "x", id: other), device: "b")
        #expect(rig.uploads.count == 2)
        // The same intent as that one, another picture: uploaded, and remembered over the first.
        let another = PhotoFixture.encode(PhotoFixture.picture(48, 36), as: .png)!
        _ = await rig.session(PhotoFixture.body(image: another, text: "x", id: other), device: "c")
        #expect(rig.uploads.count == 3)
        _ = await rig.session(PhotoFixture.body(image: another, text: "x", id: other), device: "d")
        #expect(rig.uploads.count == 3)
        // The same intent and picture once the session reads as in another project.
        rig.reads = [PhotoRig.session("completed", project: "proj-2")]
        _ = await rig.session(PhotoFixture.body(image: another, text: "x", id: other), device: "e")
        #expect(rig.uploads.count == 4)
        #expect(rig.uploads.last?.project == "proj-2")
    }

    @Test func theUploadIsRememberedTenMinutesAndNoLonger() async {
        #expect(RemotePhotos.uploadedLifetime == 600)
        rig.writeReply = nil
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "a")
        rig.now = rig.now.addingTimeInterval(599)
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "b")
        #expect(rig.uploads.count == 1)
        rig.now = rig.now.addingTimeInterval(2)
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "c")
        #expect(rig.uploads.count == 2)
        // The new one is remembered from now.
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "d")
        #expect(rig.uploads.count == 2)
    }

    @Test func aRetryThatNeverGotItsUploadMakesOne() async {
        rig.upload = .none
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "a")
        rig.upload = .echo
        let retried = await rig.session(PhotoFixture.body(text: "x"), device: "b")
        #expect(decode(retried.body).string("result") == "sent")
        #expect(rig.uploads.count == 2)
    }

    @Test func a409OnARetriedIntentReadsAsSent() async {
        rig.writeReply = nil
        _ = await rig.session(PhotoFixture.body(text: "x"), device: "a")
        rig.writeReply = RemoteWriteResult(status: 409, code: "intent_conflict")
        let retried = await rig.session(PhotoFixture.body(text: "x"), device: "b")
        #expect(decode(retried.body).string("result") == "sent")
        #expect(decode(retried.body).string("sentence") == "Sent.")
        // A first try the daemon refuses with a 409 isn't a repeat of anything Bench did.
        let fresh = await rig.session(PhotoFixture.body(text: "y", id: other), device: "c")
        #expect(decode(fresh.body).string("sentence") == RemotePhotos.Sentence.savedNotSent)
    }

    @Test func theRoutesOwnChecksComeFirst() async {
        rig.actionsOn = false
        let off = await rig.session(PhotoFixture.body(text: "x"))
        #expect(off.status == 403)
        #expect(decode(off.body).string("sentence") == "Actions are off in Capsid's Settings")
        rig.actionsOn = true
        let other = await rig.session(PhotoFixture.body(text: "x"), id: newID)
        #expect(other.status == 404)
        #expect(rig.log.isEmpty)
        // A body or a picture that is no good is refused before anything is read.
        #expect(await rig.session(Data("nope".utf8)).status == 400)
        let reference = await rig.session(PhotoFixture.body(text: #"{"type":"attachment","id":"x"}"#))
        #expect(reference.status == 400)
        #expect(String(decoding: reference.body, as: UTF8.self) == #"{"error":"reference"}"#)
        let garbage = await rig.session(PhotoFixture.body(image: Data("not a picture, whatever the phone says".utf8)))
        #expect(garbage.status == 415)
        #expect(String(decoding: garbage.body, as: UTF8.self) == #"{"error":"notAnImage"}"#)
        #expect(rig.log.isEmpty)
        #expect(rig.uploads.isEmpty)
    }

    @Test func itCountsAsAnActionAndTheSeventhInAMinuteIs429() async {
        for _ in 0..<6 { #expect(await rig.session(Data("nope".utf8)).status == 400) }
        let over = await rig.session(PhotoFixture.body(text: "x"))
        #expect(over.status == 429)
        #expect(decode(over.body).string("error") == "tooMany")
        // The same six a minute the messages share.
        let message = await rig.sessions.act(.message, session: root, device: "device-1", body: Data(#"{"text":"hi","id":"\#(intent)"}"#.utf8))
        #expect(message.status == 429)
        #expect(await rig.session(PhotoFixture.body(text: "x"), device: "device-2").status == 200)
        rig.now = rig.now.addingTimeInterval(61)
        #expect(await rig.session(PhotoFixture.body(text: "x")).status == 200)
    }

    @Test func theCachedReadIsDroppedAfterwards() async throws {
        _ = await rig.sessions.sessionJSON(root)
        #expect(rig.sessions.cachedSessions == [root])
        _ = await rig.session(PhotoFixture.body(text: "x"))
        #expect(rig.sessions.cachedSessions.isEmpty)
    }
}

@MainActor
struct RemotePhotosProjectTests {
    private let rig = PhotoRig()

    private func newSession(_ write: RemoteWrite?) -> (project: String, text: String, planMode: Bool, intent: String)? {
        if case .newSession(let project, let text, let planMode, let intent, _)? = write { return (project, text, planMode, intent) }
        return nil
    }

    @Test func aProjectGetsThePhotoThenANewSession() async throws {
        let reply = await rig.project(PhotoFixture.body(text: "Look at this gel."))
        #expect(reply.status == 200)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"id":"\#(newID)","result":"started","sentence":"Started"}"#)
        #expect(rig.log == ["projects", "upload", "create"])
        let upload = try #require(rig.uploads.first)
        #expect(upload.project == "proj-1")
        let made = try #require(newSession(rig.writes.first))
        #expect(made.project == "proj-1")
        #expect(made.text == "Look at this gel.\n\n" + rig.line(of: upload.photo))
        #expect(!made.planMode)
        #expect(made.intent == intent)
        // The phone may open it straight away, under the text's own title.
        #expect(rig.sessions.heldSession(newID)?.title == "Look at this gel.")
    }

    @Test func aRetriedNewSessionReusesTheUploadToo() async throws {
        rig.createReply = nil
        rig.intents = []
        let first = await rig.project(PhotoFixture.body(text: "x"))
        #expect(decode(first.body).string("sentence") == RemotePhotos.Sentence.savedNotSent)
        #expect(rig.uploads.count == 1)
        rig.createReply = RemoteWriteResult(status: 200, bodyStatus: "accepted", rootFrameID: newID)
        let again = await rig.project(PhotoFixture.body(text: "x"), device: "device-2")
        #expect(decode(again.body).string("result") == "started")
        #expect(rig.uploads.count == 1)
        let upload = try #require(rig.uploads.first)
        #expect(rig.writes.count == 2)
        for write in rig.writes { #expect(newSession(write)?.text == "x\n\n" + rig.line(of: upload.photo)) }
        // Another picture under that intent is a new upload.
        let another = PhotoFixture.encode(PhotoFixture.picture(48, 36), as: .png)!
        _ = await rig.project(PhotoFixture.body(image: another, text: "x"), device: "device-3")
        #expect(rig.uploads.count == 2)
    }

    @Test func thePhotosWriteIsTheOneThatMayEndInTheLine() async {
        _ = await rig.project(PhotoFixture.body(text: "x"))
        if case .newSession(_, _, _, _, let attachment)? = rig.writes.first { #expect(attachment) } else { Issue.record("no new session") }
    }

    @Test func planFirstIsPlanModeAndAPhotoAloneIsTheLineAndNamedPhoto() async throws {
        _ = await rig.project(PhotoFixture.body(planFirst: true))
        let upload = try #require(rig.uploads.first)
        let made = try #require(newSession(rig.writes.first))
        #expect(made.planMode)
        #expect(made.text == rig.line(of: upload.photo))
        #expect(rig.sessions.heldSession(newID)?.title == "Photo")
    }

    @Test func theNewSessionRoutesOrderOfChecks() async {
        rig.browseOn = false
        let browse = await rig.project(PhotoFixture.body())
        #expect(browse.status == 403)
        #expect(String(decoding: browse.body, as: UTF8.self) == #"{"error":"browseOff"}"#)
        rig.browseOn = true
        rig.actionsOn = false
        #expect(await rig.project(PhotoFixture.body()).status == 403)
        rig.actionsOn = true
        #expect(rig.log.isEmpty)
        #expect(await rig.project(Data("nope".utf8)).status == 400)
        #expect(await rig.project(PhotoFixture.body(), id: "has space").status == 400)
        let unknown = await rig.project(PhotoFixture.body(), id: "proj_other")
        #expect(unknown.status == 404)
        // The list is held a minute; once it is old, it is read again, and can't be.
        rig.projects = nil
        rig.now = rig.now.addingTimeInterval(61)
        let unreadable = await rig.project(PhotoFixture.body(), device: "device-2", id: "proj_z")
        #expect(unreadable.status == 503)
        #expect(String(decoding: unreadable.body, as: UTF8.self) == #"{"error":"unreadable"}"#)
        #expect(rig.uploads.isEmpty)
        #expect(!rig.log.contains("create"))
    }

    @Test func aPictureThatIsNoneIsRefusedBeforeTheUpload() async {
        let garbage = await rig.project(PhotoFixture.body(image: Data(repeating: 0x41, count: 500)))
        #expect(garbage.status == 415)
        #expect(String(decoding: garbage.body, as: UTF8.self) == #"{"error":"notAnImage"}"#)
        let reference = await rig.project(PhotoFixture.body(text: "see {{artifact:abc}}"))
        #expect(String(decoding: reference.body, as: UTF8.self) == #"{"error":"reference"}"#)
        #expect(rig.uploads.isEmpty)
        #expect(!rig.log.contains("create"))
    }

    @Test func itSharesTheSixAMinuteWithEveryOtherAction() async {
        for _ in 0..<6 { #expect(await rig.project(Data("nope".utf8)).status == 400) }
        #expect(await rig.project(PhotoFixture.body()).status == 429)
        #expect(await rig.project(PhotoFixture.body(), device: "device-2").status == 200)
    }

    @Test func anUploadThatDidntWorkStartsNothing() async {
        rig.upload = .noUpload
        let reply = await rig.project(PhotoFixture.body(text: "x"))
        #expect(decode(reply.body).string("sentence") == RemotePhotos.Sentence.notAttached)
        #expect(decode(reply.body).string("result") == "unavailable")
        #expect(!rig.log.contains("create"))
    }

    @Test func aLostAnswerIsLookedForAsANewSessionIs() async throws {
        // The daemon says 409: an earlier try with this intent made the session.
        rig.createReply = RemoteWriteResult(status: 409, code: "intent_conflict")
        rig.intents = [newID]
        let reply = await rig.project(PhotoFixture.body(text: "x"))
        #expect(decode(reply.body).string("result") == "started")
        #expect(decode(reply.body).string("id") == newID)
        #expect(rig.log == ["projects", "upload", "create", "intent"])
        // Never found: the photo is saved and the session isn't.
        rig.intents = []
        rig.createReply = nil
        let lost = await rig.project(PhotoFixture.body(text: "x"), device: "device-2")
        #expect(decode(lost.body).string("result") == "unavailable")
        #expect(decode(lost.body).string("sentence") == "The photo was saved to the project, but the message didn't send. Open it on your Mac.")
        // The same photo under the same intent: a retry, so its upload is reused, not made again.
        #expect(rig.log.suffix(4) == ["create", "intent", "pause", "intent"])
        #expect(rig.uploads.count == 1)
        rig.createReply = RemoteWriteResult(status: 500)
        let failed = await rig.project(PhotoFixture.body(text: "x"), device: "device-3")
        #expect(decode(failed.body).string("sentence") == RemotePhotos.Sentence.savedNotSent)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
}

// MARK: The demo

@MainActor
struct RemotePhotosDemoTests {
    @Test func theDemoAcceptsAPhotoAndStillRefusesGarbage() async throws {
        let session = SessionStatus(id: root, projectID: "proj_demo_example", projectName: "Example project", title: "Made-up",
                                    state: .finished, updatedAt: Date(), startedAt: Date())
        let reads = [root: SessionProjection(status: "completed", agentName: "demo", projectID: "demo")]
        let sessions = RemoteSessions.demo(reads: reads, known: { [session] }, cardPlan: { _ in nil })
        let store = DemoBrowseStore(nowSessions: [session], reads: reads)
        let browser = RemoteBrowser.demo(sessions: sessions, store: store)
        let photos = RemotePhotos.demo(sessions: sessions, browser: browser)

        let sent = await photos.respond(.session(root), device: "d", body: PhotoFixture.body(text: "Look at this."))
        #expect(sent.status == 200)
        #expect(decode(sent.body)["result"] as? String == "sent")
        let started = await photos.respond(.project("proj_demo_example"), device: "d", body: PhotoFixture.body(planFirst: true))
        #expect(started.status == 200)
        #expect(decode(started.body)["result"] as? String == "started")
        let garbage = await photos.respond(.project("proj_demo_example"), device: "d", body: PhotoFixture.body(image: Data("garbage".utf8)))
        #expect(garbage.status == 415)
        let garbageSession = await photos.respond(.session(root), device: "d", body: PhotoFixture.body(image: Data("garbage".utf8)))
        #expect(String(decoding: garbageSession.body, as: UTF8.self) == #"{"error":"notAnImage"}"#)
    }
}

// MARK: The server, taking a body slowly

@MainActor
struct RemotePhotoLiveTests {
    private static let host = "studio-mac.example-tailnet.ts.net"
    private static let login = "pat@example.com"

    private final class Seen: @unchecked Sendable {
        var bytes = 0
    }

    private func server(seen: Seen) async throws -> (RemoteServer, UInt16, String) {
        let auth = RemoteAuth(store: MemoryDeviceStore(), fixedCode: "000000")
        guard case .paired(let token, _) = auth.pair(code: "000000", name: "Phone") else {
            Issue.record("not paired")
            throw WebAPIError.notReady
        }
        let server = RemoteServer(policy: .tailnet(dnsName: Self.host, login: Self.login), auth: auth,
                                  backend: RemoteBackend(state: { Data("{}".utf8) }, session: { _ in nil }, open: { _ in false },
                                                         version: "test", photo: { _, _, body in
            seen.bytes = body.count
            return RemoteActionReply(status: 200, body: Data(#"{"result":"sent","sentence":"Sent."}"#.utf8))
        }))
        let port = try await server.start(candidates: Array(47371...47379))
        return (server, port, token)
    }

    /// Sends the head and the first chunk, then the rest `pause` seconds apart; reads
    /// what the server answers, for up to `limit` seconds.
    private nonisolated static func dribble(port: UInt16, head: String, body: [UInt8], chunks: Int, pause: TimeInterval,
                                            limit: TimeInterval) -> (String, TimeInterval) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return ("", 0) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return ("", 0) }
        var quiet: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: Int(limit), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        let started = Date()
        let size = (body.count + chunks - 1) / chunks
        for index in 0..<chunks {
            let part = Array(body[(index * size)..<min(body.count, (index + 1) * size)])
            let bytes = index == 0 ? Array(head.utf8) + part : part
            _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            if index < chunks - 1 { Thread.sleep(forTimeInterval: pause) }
        }
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date().timeIntervalSince(started) < limit {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            answer.append(contentsOf: buffer[0..<count])
        }
        return (String(decoding: answer, as: UTF8.self), Date().timeIntervalSince(started))
    }

    private func head(_ path: String, token: String, length: Int) -> String {
        "POST \(path) HTTP/1.1\r\nHost: \(Self.host):8443\r\nTailscale-User-Login: \(Self.login)\r\nCookie: bench_device=\(token)\r\n"
            + "Content-Type: application/json\r\nOrigin: https://\(Self.host):8443\r\nX-Bench: 1\r\nContent-Length: \(length)\r\n\r\n"
    }

    @Test func aPhotoBodyThatKeepsArrivingIsNotCutOffAtThreeSeconds() async throws {
        let seen = Seen()
        let (server, port, token) = try await server(seen: seen)
        defer { server.stop() }
        let body = [UInt8](repeating: 0x41, count: 30_000)
        let text = head("/api/sessions/\(root)/photo", token: token, length: body.count)
        // Five pieces 1.2 s apart: nearly five seconds in all, never ten quiet.
        let (answer, seconds) = await Task.detached {
            Self.dribble(port: port, head: text, body: body, chunks: 5, pause: 1.2, limit: 12)
        }.value
        #expect(answer.hasPrefix("HTTP/1.1 200 "), "\(answer.prefix(40))")
        #expect(answer.hasSuffix(#"{"result":"sent","sentence":"Sent."}"#))
        #expect(seconds > 4.5 && seconds < 9)
        #expect(seen.bytes == 30_000)
    }

    @Test func everyOtherRouteStillHasTheFlatThreeSeconds() async throws {
        let seen = Seen()
        let (server, port, token) = try await server(seen: seen)
        defer { server.stop() }
        let body = [UInt8](repeating: 0x41, count: 40)
        let text = head("/api/sessions/\(root)/message", token: token, length: body.count)
        let (answer, _) = await Task.detached {
            Self.dribble(port: port, head: text, body: body, chunks: 4, pause: 1.2, limit: 12)
        }.value
        #expect(answer.hasPrefix("HTTP/1.1 408 "), "\(answer.prefix(40))")
        #expect(seen.bytes == 0)
    }

    @Test func aPhotoOverSixMegabytesIsRefusedAtItsHead() async throws {
        let seen = Seen()
        let (server, port, token) = try await server(seen: seen)
        defer { server.stop() }
        let text = head("/api/projects/proj_a/photo", token: token, length: 6 * 1024 * 1024 + 1)
        let (answer, seconds) = await Task.detached {
            Self.dribble(port: port, head: text, body: [], chunks: 1, pause: 0, limit: 8)
        }.value
        #expect(answer.hasPrefix("HTTP/1.1 413 "))
        #expect(seconds < 2)
    }
}
